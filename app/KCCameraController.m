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
@end

@implementation KCCameraController

- (instancetype)init {
    if ((self = [super init])) {
        _frameQueue = dispatch_queue_create("com.khoangcachantoan.camera.frames", DISPATCH_QUEUE_SERIAL);
        _sessionQueue = dispatch_queue_create("com.khoangcachantoan.camera.session", DISPATCH_QUEUE_SERIAL);
        _pendingOrientation = AVCaptureVideoOrientationLandscapeRight;
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver:self selector:@selector(sessionRuntimeError:) name:AVCaptureSessionRuntimeErrorNotification object:nil];
        [nc addObserver:self selector:@selector(sessionInterrupted:) name:AVCaptureSessionWasInterruptedNotification object:nil];
        [nc addObserver:self selector:@selector(sessionInterruptionEnded:) name:AVCaptureSessionInterruptionEndedNotification object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
    });
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
    KCLogf(@"camera: interrupted reason=%@", n.userInfo[AVCaptureSessionInterruptionReasonKey]);
}
- (void)sessionInterruptionEnded:(NSNotification *)n {
    KCLogf(@"camera: interruption ended");
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pb) return;

    KCIntrinsics intr;
    memset(&intr, 0, sizeof(intr));
    intr.width = (int)CVPixelBufferGetWidth(pb);
    intr.height = (int)CVPixelBufferGetHeight(pb);

    CFTypeRef att = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, NULL);
    if (att && CFGetTypeID(att) == CFDataGetTypeID() && CFDataGetLength((CFDataRef)att) >= (CFIndex)sizeof(matrix_float3x3)) {
        matrix_float3x3 m;
        CFDataGetBytes((CFDataRef)att, CFRangeMake(0, sizeof(m)), (UInt8 *)&m);
        intr.fx = m.columns[0][0];
        intr.fy = m.columns[1][1];
        intr.cx = m.columns[2][0];
        intr.cy = m.columns[2][1];
        intr.fromDelivery = YES;
    } else {
        float fovDeg = self.device.activeFormat.videoFieldOfView;
        if (fovDeg <= 0) fovDeg = 60.0f;
        float fx = (intr.width / 2.0f) / tanf(fovDeg * (float)M_PI / 360.0f);
        intr.fx = fx;
        intr.fy = fx;
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
