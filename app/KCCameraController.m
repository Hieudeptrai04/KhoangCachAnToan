#import "KCCameraController.h"
#import "KCLog.h"
#import <simd/simd.h>
#import <math.h>

@interface KCCameraController () <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) AVCaptureSession *session;
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, copy) NSString *deviceLabel;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoOutput;
@property (nonatomic, strong) dispatch_queue_t frameQueue;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, assign) KCIntrinsics lastIntrinsics;
@property (nonatomic, assign) double measuredFPS;
@property (nonatomic, assign) BOOL loggedIntrinsics;
@property (nonatomic, assign) NSUInteger fpsFrameCount;
@property (nonatomic, assign) CFAbsoluteTime fpsWindowStart;
@property (nonatomic, assign) AVCaptureVideoOrientation pendingOrientation;
@property (nonatomic, assign) NSUInteger totalFrames;
@property (nonatomic, assign) BOOL buffersRotated;
@property (nonatomic, strong) NSTimer *watchdog;
@property (nonatomic, assign) NSInteger watchdogStage;
@property (nonatomic, assign) NSUInteger droppedFrames;
@property (nonatomic, assign) BOOL loggedIntrinsicMismatch;
@end

@implementation KCCameraController

- (instancetype)init {
    if ((self = [super init])) {
        _frameQueue = dispatch_queue_create("com.khoangcachantoan.camera.frames", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("com.khoangcachantoan.camera.session", DISPATCH_QUEUE_SERIAL);
        _pendingOrientation = AVCaptureVideoOrientationLandscapeRight;
        _buffersRotated = YES;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
        [nc addObserver:self selector:@selector(sessionInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:nil];
        [nc addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_watchdog invalidate];
}

#pragma mark - Setup

- (BOOL)setupPreferTelephoto:(BOOL)preferTele use4K:(BOOL)use4K error:(NSError **)error {
    AVCaptureDevice *dev = nil;
    NSString *label = nil;
    if (preferTele) {
        dev = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInTelephotoCamera
                                                 mediaType:AVMediaTypeVideo
                                                  position:AVCaptureDevicePositionBack];
        if (dev) label = @"tele";
    }
    if (!dev) {
        dev = [AVCaptureDevice defaultDeviceWithDeviceType:AVCaptureDeviceTypeBuiltInWideAngleCamera
                                                 mediaType:AVMediaTypeVideo
                                                  position:AVCaptureDevicePositionBack];
        if (dev) label = @"wide";
    }
    if (!dev) {
        KCLogf(@"camera: khong tim thay camera sau");
        if (error) *error = [NSError errorWithDomain:@"KCCamera" code:1 userInfo:@{NSLocalizedDescriptionKey: @"Không tìm thấy camera sau"}];
        return NO;
    }
    self.device = dev;
    self.deviceLabel = label;

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    [session beginConfiguration];

    NSString *preset = AVCaptureSessionPreset1920x1080;
    if (use4K && [session canSetSessionPreset:AVCaptureSessionPreset3840x2160]) preset = AVCaptureSessionPreset3840x2160;
    if (![session canSetSessionPreset:preset]) preset = AVCaptureSessionPresetHigh;
    session.sessionPreset = preset;

    NSError *inputErr = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:dev error:&inputErr];
    if (!input || ![session canAddInput:input]) {
        [session commitConfiguration];
        KCLogf(@"camera: khong them duoc input: %@", inputErr);
        if (error) *error = inputErr ?: [NSError errorWithDomain:@"KCCamera" code:2 userInfo:@{NSLocalizedDescriptionKey: @"Không mở được camera"}];
        return NO;
    }
    [session addInput:input];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.videoSettings = @{ (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) };
    output.alwaysDiscardsLateVideoFrames = YES;
    [output setSampleBufferDelegate:self queue:self.frameQueue];
    if (![session canAddOutput:output]) {
        [session commitConfiguration];
        KCLogf(@"camera: khong them duoc video data output");
        if (error) *error = [NSError errorWithDomain:@"KCCamera" code:3 userInfo:@{NSLocalizedDescriptionKey: @"Không thêm được video output"}];
        return NO;
    }
    [session addOutput:output];
    [session commitConfiguration];

    AVCaptureConnection *conn = [output connectionWithMediaType:AVMediaTypeVideo];
    if (conn.isCameraIntrinsicMatrixDeliverySupported) {
        conn.cameraIntrinsicMatrixDeliveryEnabled = YES;
        KCLogf(@"camera: intrinsic matrix delivery = ON");
    } else {
        KCLogf(@"camera: intrinsic matrix delivery KHONG ho tro -> tinh tu FOV");
    }
    // Đặt videoOrientation ở đây khiến data output XOAY THẬT từng buffer trước khi giao.
    // KCMainViewController dựa vào điều đó: nó khai kCGImagePropertyOrientationUp cho Vision
    // và quy đổi khung bao bằng phép co giãn thuần. Bỏ dòng này thì phải sửa cả hai chỗ đó.
    if (conn.isVideoOrientationSupported) conn.videoOrientation = self.pendingOrientation;

    self.session = session;
    self.videoOutput = output;
    [self configureDeviceFocus];

    CMVideoDimensions dims = CMVideoFormatDescriptionGetDimensions(dev.activeFormat.formatDescription);
    KCLogf(@"camera: device=%@ (%@) uniqueID=%@ preset=%@ format=%dx%d fov=%.2f",
           dev.localizedName, label, dev.uniqueID, preset, dims.width, dims.height, dev.activeFormat.videoFieldOfView);
    return YES;
}

- (void)configureDeviceFocus {
    NSError *err = nil;
    if (![self.device lockForConfiguration:&err]) {
        KCLogf(@"camera: lockForConfiguration that bai: %@", err);
        return;
    }
    if (self.device.isLockingFocusWithCustomLensPositionSupported) {
        [self.device setFocusModeLockedWithLensPosition:1.0f completionHandler:nil];   // khóa lấy nét vô cực
        KCLogf(@"camera: focus locked lensPosition=1.0");
    } else if ([self.device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
        self.device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        KCLogf(@"camera: custom lens position khong ho tro -> continuous AF");
    }
    if ([self.device isExposureModeSupported:AVCaptureExposureModeContinuousAutoExposure]) {
        self.device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
    }
    [self.device unlockForConfiguration];
}

#pragma mark - Run

- (void)startRunning {
    dispatch_async(self.sessionQueue, ^{
        if (!self.session || self.session.isRunning) return;
        [self.session startRunning];
        KCLogf(@"camera: session running=%d", self.session.isRunning);
        dispatch_async(dispatch_get_main_queue(), ^{ [self startWatchdog]; });
    });
}

#pragma mark - Theo dõi khung hình

/// Phiên chạy nhưng data output không giao khung nào là lỗi câm: không exception, không
/// runtime error, chỉ đơn giản là không có gì. Bộ theo dõi này ghi lại toàn bộ trạng thái
/// rồi lần lượt gỡ hai thứ dễ gây nghẽn nhất (giao ma trận nội tại, rồi xoay buffer).
- (void)startWatchdog {
    [self.watchdog invalidate];
    self.watchdogStage = 0;
    self.watchdog = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self
                                                   selector:@selector(watchdogTick)
                                                   userInfo:nil repeats:YES];
}

- (void)watchdogTick {
    if (self.totalFrames > 0) {
        KCLogf(@"camera: da nhan %lu khung, bo theo doi dung lai", (unsigned long)self.totalFrames);
        [self.watchdog invalidate];
        self.watchdog = nil;
        return;
    }
    self.watchdogStage += 1;
    [self logDetailedState];

    AVCaptureConnection *conn = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (self.watchdogStage == 1) {
        if (conn.cameraIntrinsicMatrixDeliveryEnabled) {
            conn.cameraIntrinsicMatrixDeliveryEnabled = NO;
            KCLogf(@"camera: THU GO giao ma tran noi tai -> tinh fx tu FOV");
        }
    } else if (self.watchdogStage == 2) {
        if (conn.isVideoOrientationSupported && conn.videoOrientation != AVCaptureVideoOrientationPortrait) {
            conn.videoOrientation = AVCaptureVideoOrientationPortrait;
            self.buffersRotated = NO;
            KCLogf(@"camera: THU GO xoay buffer (ve Portrait) -> buffersRotated=NO");
        }
    } else if (self.watchdogStage >= 3) {
        KCLogf(@"camera: VAN KHONG CO KHUNG sau %ld lan thu, dung theo doi", (long)self.watchdogStage);
        [self.watchdog invalidate];
        self.watchdog = nil;
    }
}

- (void)logDetailedState {
    AVCaptureSession *s = self.session;
    AVCaptureConnection *conn = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    KCLogf(@"camera: KHONG CO KHUNG (lan %ld) running=%d interrupted=%d inputs=%lu outputs=%lu bo=%lu",
           (long)self.watchdogStage, s.isRunning, s.isInterrupted,
           (unsigned long)s.inputs.count, (unsigned long)s.outputs.count, (unsigned long)self.droppedFrames);
    if (conn) {
        KCLogf(@"camera:   connection active=%d enabled=%d ports=%lu orientation=%ld stabilization=%ld intrinsics=%d",
               conn.isActive, conn.isEnabled, (unsigned long)conn.inputPorts.count,
               (long)conn.videoOrientation, (long)conn.activeVideoStabilizationMode,
               conn.cameraIntrinsicMatrixDeliveryEnabled);
    } else {
        KCLogf(@"camera:   connection = nil");
    }
    NSArray<NSNumber *> *formats = self.videoOutput.availableVideoCVPixelFormatTypes;
    NSMutableArray *names = [NSMutableArray array];
    for (NSNumber *n in formats) {
        OSType t = (OSType)n.unsignedIntValue;
        [names addObject:[NSString stringWithFormat:@"%c%c%c%c",
                          (char)((t >> 24) & 0xFF), (char)((t >> 16) & 0xFF),
                          (char)((t >> 8) & 0xFF), (char)(t & 0xFF)]];
    }
    KCLogf(@"camera:   dinh dang ho tro = [%@], dang dat = %@",
           [names componentsJoinedByString:@","], self.videoOutput.videoSettings);
}

- (void)stopRunning {
    dispatch_async(self.sessionQueue, ^{
        if (self.session.isRunning) [self.session stopRunning];
        KCLogf(@"camera: session stopped");
    });
}

- (void)applyVideoOrientation:(AVCaptureVideoOrientation)orientation {
    self.pendingOrientation = orientation;
    AVCaptureConnection *conn = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    if (conn && conn.isVideoOrientationSupported && conn.videoOrientation != orientation) {
        conn.videoOrientation = orientation;
        self.loggedIntrinsics = NO;
        KCLogf(@"camera: data output orientation -> %ld", (long)orientation);
    }
}

#pragma mark - Notifications

- (void)sessionRuntimeError:(NSNotification *)n {
    KCLogf(@"camera: runtime error %@", n.userInfo[AVCaptureSessionErrorKey]);
}
- (void)sessionInterrupted:(NSNotification *)n {
    // 1=audioDeviceInUseByAnotherClient 2=videoDeviceInUseByAnotherClient
    // 3=videoDeviceNotAvailableWithMultipleForegroundApps 4=videoDeviceNotAvailableDueToSystemPressure
    KCLogf(@"camera: BI NGAT reason=%@", n.userInfo[AVCaptureSessionInterruptionReasonKey]);
}
- (void)sessionInterruptionEnded:(NSNotification *)n {
    KCLogf(@"camera: interruption ended");
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    self.droppedFrames += 1;
    if (self.droppedFrames <= 3) {
        CFTypeRef reason = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_DroppedFrameReason, NULL);
        KCLogf(@"camera: bo khung #%lu, ly do=%@", (unsigned long)self.droppedFrames, reason);
    }
}

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    self.totalFrames += 1;
    if (self.totalFrames == 1) KCLogf(@"camera: KHUNG DAU TIEN da ve");

    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pb) {
        if (self.totalFrames <= 3) KCLogf(@"camera: sample buffer khong co image buffer");
        return;
    }

    KCIntrinsics intr;
    memset(&intr, 0, sizeof(intr));
    intr.width = (int)CVPixelBufferGetWidth(pb);
    intr.height = (int)CVPixelBufferGetHeight(pb);

    BOOL gotIntrinsics = NO;
    CFTypeRef att = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, NULL);
    if (att && CFGetTypeID(att) == CFDataGetTypeID() && CFDataGetLength((CFDataRef)att) >= (CFIndex)sizeof(matrix_float3x3)) {
        matrix_float3x3 m;
        CFDataGetBytes((CFDataRef)att, CFRangeMake(0, sizeof(m)), (UInt8 *)&m);
        float cx = m.columns[2][0], cy = m.columns[2][1];
        // Ma trận được mô tả theo khung CHƯA xoay. Nếu buffer đã xoay sang dọc thì tâm ảnh
        // sẽ lệch hẳn khỏi giữa buffer — khi đó số liệu không dùng được, quay về tính từ FOV.
        BOOL centred = (fabsf(cx - intr.width / 2.0f) < intr.width * 0.25f) &&
                       (fabsf(cy - intr.height / 2.0f) < intr.height * 0.25f);
        if (centred) {
            intr.fx = m.columns[0][0];
            intr.fy = m.columns[1][1];
            intr.cx = cx;
            intr.cy = cy;
            intr.fromDelivery = YES;
            gotIntrinsics = YES;
        } else if (!self.loggedIntrinsicMismatch) {
            self.loggedIntrinsicMismatch = YES;
            KCLogf(@"camera: ma tran noi tai (cx=%.0f cy=%.0f) khong khop buffer %dx%d -> dung FOV",
                   cx, cy, intr.width, intr.height);
        }
    }
    if (!gotIntrinsics) {
        float fovDeg = self.device.activeFormat.videoFieldOfView;
        if (fovDeg <= 0) fovDeg = 60.0f;
        // videoFieldOfView là góc nhìn ngang của khung gốc (cạnh DÀI của cảm biến).
        // Pixel vuông nên tiêu cự theo pixel như nhau ở cả hai trục, không phụ thuộc chiều xoay.
        float longSide = MAX(intr.width, intr.height);
        float f = (longSide / 2.0f) / tanf(fovDeg * (float)M_PI / 360.0f);
        intr.fx = f;
        intr.fy = f;
        intr.cx = intr.width / 2.0f;
        intr.cy = intr.height / 2.0f;
        intr.fromDelivery = NO;
    }

    // FPS camera (cửa sổ 1 s)
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.fpsWindowStart == 0) self.fpsWindowStart = now;
    self.fpsFrameCount += 1;
    CFAbsoluteTime dt = now - self.fpsWindowStart;
    if (dt >= 1.0) {
        self.measuredFPS = self.fpsFrameCount / dt;
        self.fpsFrameCount = 0;
        self.fpsWindowStart = now;
    }

    if (!self.loggedIntrinsics || intr.width != self.lastIntrinsics.width || intr.height != self.lastIntrinsics.height) {
        KCLogf(@"intrinsics: buffer=%dx%d fx=%.2f fy=%.2f cx=%.2f cy=%.2f nguon=%@",
               intr.width, intr.height, intr.fx, intr.fy, intr.cx, intr.cy, intr.fromDelivery ? @"CameraIntrinsicMatrix" : @"FOV");
        self.loggedIntrinsics = YES;
    }
    self.lastIntrinsics = intr;

    id<KCCameraFrameDelegate> d = self.delegate;
    if (d) [d cameraController:self didOutputPixelBuffer:pb intrinsics:intr timestamp:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
}

@end
