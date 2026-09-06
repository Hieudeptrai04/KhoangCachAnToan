#import "KCMainViewController.h"
#import "KCCameraController.h"
#import "KCDetector.h"
#import "KCTracker.h"
#import "KCOverlayView.h"
#import "KCHUDView.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

@interface KCMainViewController () <KCCameraFrameDelegate, KCDetectorDelegate>
@property (nonatomic, strong) KCCameraController *camera;
@property (nonatomic, strong) KCDetector *detector;
@property (nonatomic, strong) KCTracker *tracker;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) KCOverlayView *overlay;
@property (nonatomic, strong) KCHUDView *hud;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NSTimer *demoTimer;
@property (nonatomic, assign) double demoT;
@property (nonatomic, assign) BOOL adverseWeather;
@property (nonatomic, assign) BOOL cameraStarted;
@property (nonatomic, assign) AVCaptureVideoOrientation currentVideoOrientation;

// Trạng thái phát hiện mới nhất (chỉ đọc/ghi trên main queue).
@property (nonatomic, assign) NSUInteger lastDetectionCount;
@property (nonatomic, assign) NSUInteger lastInLaneCount;
@property (nonatomic, copy) NSString *lastLeaderText;
@property (nonatomic, assign) BOOL lastLeaderLost;
@property (nonatomic, assign) CFAbsoluteTime lastHudTextRefresh;
@property (nonatomic, assign) CGSize lastBufferSize;
@end

@implementation KCMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.lastLeaderText = @"—";

    self.camera = [[KCCameraController alloc] init];
    self.camera.delegate = self;

    self.tracker = [[KCTracker alloc] init];

    self.detector = [[KCDetector alloc] init];
    self.detector.delegate = self;

    self.overlay = [[KCOverlayView alloc] initWithFrame:self.view.bounds];
    self.overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.overlay];

    self.hud = [[KCHUDView alloc] initWithFrame:self.view.bounds];
    self.hud.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.hud];
    [self.hud.weatherButton addTarget:self action:@selector(toggleWeather) forControlEvents:UIControlEventTouchUpInside];
    [self.hud.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.hud setThresholdText:@"≥ 55 m (luật)"];
    self.tracker.horizonY = self.hud.horizonY;

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.errorLabel.textColor = KCColorRed();
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    [self loadDetector];
    [self refreshBadges];

    // Phase 1: khoảng cách/tốc độ vẫn là số giả (nhãn DEMO); phát hiện xe là thật.
    self.demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(demoTick) userInfo:nil repeats:YES];
}

- (void)dealloc {
    [_demoTimer invalidate];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startCameraIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
    self.errorLabel.frame = CGRectInset(self.view.bounds, 60, 120);
    [self.view bringSubviewToFront:self.overlay];
    [self.view bringSubviewToFront:self.hud];
    [self applyOrientation];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext> ctx) {
        [self applyOrientation];
    }];
}

#pragma mark - Orientation (FR-9: chỉ ngang)

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)shouldAutorotate { return YES; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (UIInterfaceOrientation)interfaceOrientationNow {
    UIWindowScene *scene = self.view.window.windowScene;
    if (scene) return scene.interfaceOrientation;
    return [UIApplication sharedApplication].statusBarOrientation;
}

- (void)applyOrientation {
    // Khớp theo TÊN ở đây là đúng, và trùng với khớp theo giá trị số:
    // UIInterfaceOrientationLandscapeLeft = UIDeviceOrientationLandscapeRight = 4
    // = AVCaptureVideoOrientationLandscapeLeft; LandscapeRight = 3 ở cả hai kiểu liệt kê.
    // (Chỗ hay nhầm 180° là khi khớp UIDeviceOrientation với AVCaptureVideoOrientation theo tên.)
    UIInterfaceOrientation io = [self interfaceOrientationNow];
    AVCaptureVideoOrientation vo = (io == UIInterfaceOrientationLandscapeLeft) ? AVCaptureVideoOrientationLandscapeLeft
                                                                              : AVCaptureVideoOrientationLandscapeRight;
    if (self.previewLayer.connection.isVideoOrientationSupported && self.previewLayer.connection.videoOrientation != vo) {
        self.previewLayer.connection.videoOrientation = vo;
    }
    [self.camera applyVideoOrientation:vo];
    if (vo != self.currentVideoOrientation) {
        self.currentVideoOrientation = vo;
        [self.tracker reset];
        KCLogf(@"orientation: interface=%ld -> video=%ld", (long)io, (long)vo);
    }
}

#pragma mark - Camera

- (void)startCameraIfNeeded {
    if (self.cameraStarted) return;
    AVAuthorizationStatus st = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    KCLogf(@"camera: authorization status=%ld (0=notDetermined 1=restricted 2=denied 3=authorized)", (long)st);
    if (st == AVAuthorizationStatusAuthorized) {
        [self setupAndStartCamera];
    } else if (st == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            KCLogf(@"camera: requestAccess granted=%d", granted);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) [self setupAndStartCamera];
                else [self showError:@"Không có quyền camera.\nKiểm tra entitlement TCC (kTCCServiceCamera)."];
            });
        }];
    } else {
        [self showError:@"Không có quyền camera (TCC từ chối).\nXem log.txt."];
    }
}

- (void)setupAndStartCamera {
    if (self.cameraStarted) return;
    self.cameraStarted = YES;
    NSError *err = nil;
    if (![self.camera setupPreferTelephoto:YES use4K:NO error:&err]) {
        [self showError:[NSString stringWithFormat:@"Không mở được camera: %@", err.localizedDescription ?: @"?"]];
        return;
    }
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.camera.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];

    // Quy đổi khung bao sang toạ độ màn hình.
    //
    // KHÔNG dùng rectForMetadataOutputRectOfInterest: ở đây. Hàm đó nhận toạ độ theo
    // khung CHƯA XOAY của thiết bị và tự áp phép xoay của preview. Nhưng buffer đưa cho
    // Vision ĐÃ được xoay sẵn (videoOrientation đặt trên connection của data output,
    // xem KCCameraController), nên nrect vốn đã ở hệ hiển thị — dùng hàm đó là xoay hai lần:
    // ở một trong hai chiều ngang, mọi khung bao bị lật đối xứng qua tâm màn hình
    // trong khi hình vẫn hiện đúng.
    //
    // Vì buffer và ảnh trên preview là cùng một ảnh, phép biến đổi chỉ còn là co giãn
    // resizeAspectFill cộng lệch tâm, không xoay, và đúng ở cả hai chiều ngang.
    __weak typeof(self) weakSelf = self;
    self.overlay.rectConverter = ^CGRect(CGRect nrect) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return CGRectZero;
        AVCaptureVideoPreviewLayer *layer = strongSelf.previewLayer;
        if (!layer) return CGRectZero;

        CGSize buf = strongSelf.lastBufferSize;
        CGSize ls = layer.bounds.size;
        if (buf.width <= 0 || buf.height <= 0 || ls.width <= 0 || ls.height <= 0) return CGRectZero;

        CGFloat s = MAX(ls.width / buf.width, ls.height / buf.height);   // resizeAspectFill
        CGFloat dw = buf.width * s;
        CGFloat dh = buf.height * s;
        CGFloat ox = (ls.width - dw) * 0.5;
        CGFloat oy = (ls.height - dh) * 0.5;

        return CGRectMake(ox + nrect.origin.x * dw,
                          oy + nrect.origin.y * dh,
                          nrect.size.width * dw,
                          nrect.size.height * dh);
    };
    // Vùng quan tâm kênh xa: đổi từ hệ Vision (gốc dưới-trái) sang quy ước app (gốc trên-trái).
    CGRect roi = self.detector.farRegionOfInterest;
    self.overlay.farRegionTopLeft = CGRectMake(roi.origin.x, 1.0 - (roi.origin.y + roi.size.height),
                                               roi.size.width, roi.size.height);

    [self applyOrientation];
    [self.camera startRunning];
    KCLogf(@"camera: preview layer added, session start requested (device=%@)", self.camera.deviceLabel);
    [self refreshBadges];
}

- (void)showError:(NSString *)msg {
    KCLogf(@"ERROR: %@", msg);
    self.errorLabel.text = msg;
    self.errorLabel.hidden = NO;
}

#pragma mark - Detector

- (void)loadDetector {
    NSError *err = nil;
    if (![self.detector loadModelWithError:&err]) {
        KCLogf(@"detector: khong nap duoc model: %@", err.localizedDescription);
    }
}

#pragma mark - KCCameraFrameDelegate (hàng đợi camera)

- (void)cameraController:(KCCameraController *)controller didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer intrinsics:(KCIntrinsics)intrinsics timestamp:(CMTime)timestamp {
    // Kích thước buffer dùng cho phép quy đổi khung bao sang toạ độ màn hình.
    self.lastBufferSize = CGSizeMake(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    // Buffer đã được data output xoay đúng chiều (videoOrientation) -> khai .up cho Vision là đúng sự thật.
    // Hai điều này đi kèm nhau: bỏ videoOrientation ở data output thì phải đổi luôn hướng ở đây.
    [self.detector submitPixelBuffer:pixelBuffer orientation:kCGImagePropertyOrientationUp];
}

#pragma mark - KCDetectorDelegate (hàng đợi suy luận)

- (void)detector:(KCDetector *)detector didFindVehicles:(NSArray<KCDetection *> *)detections inferenceTime:(NSTimeInterval)seconds {
    KCTrackerResult *result = [self.tracker updateWithDetections:detections timestamp:CFAbsoluteTimeGetCurrent()];
    NSUInteger inLane = 0;
    for (KCDetection *d in result.detections) if (d.inLane) inLane += 1;

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.overlay updateWithDetections:result.detections leader:result.leader leaderLost:result.leaderLost];
        self.lastDetectionCount = result.detections.count;
        self.lastInLaneCount = inLane;
        self.lastLeaderLost = result.leaderLost;
        if (result.leader) {
            CGFloat wpx = [result.leader widthPixelsForBufferWidth:self.camera.lastIntrinsics.width];
            self.lastLeaderText = [NSString stringWithFormat:@"%@ #%ld %.0fpx %@",
                                   result.leader.label, (long)result.leader.trackID, wpx,
                                   result.leader.fromFarChannel ? @"xa" : @"gần"];
        } else {
            self.lastLeaderText = @"—";
        }
        // Khung bao vẽ lại mỗi lần suy luận; phần chữ chỉ 4 lần/giây
        // (dựng lại nhãn huy hiệu ở 15 Hz tốn CPU vô ích).
        CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
        if (now - self.lastHudTextRefresh >= 0.25) {
            self.lastHudTextRefresh = now;
            [self refreshDebugText];
            [self refreshBadges];
        }
    });
}

#pragma mark - HUD

- (void)refreshDebugText {
    KCIntrinsics i = self.camera.lastIntrinsics;
    [self.hud setDebugText:[NSString stringWithFormat:
                            @"%@ %d×%d fx=%.0f cy=%.0f · cam %.0f fps · suy luận %.1f fps (%.0f ms) · %lu xe / %lu cùng làn · dẫn đầu: %@",
                            self.camera.deviceLabel ?: @"?", i.width, i.height, i.fx, i.cy,
                            self.camera.measuredFPS, self.detector.inferenceFPS,
                            self.detector.lastInferenceSeconds * 1000,
                            (unsigned long)self.lastDetectionCount, (unsigned long)self.lastInLaneCount,
                            self.lastLeaderText]];
}

- (void)refreshBadges {
    NSMutableArray<NSString *> *badges = [NSMutableArray arrayWithObject:@"DEMO"];
    if (!self.detector.ready) [badges addObject:[NSString stringWithFormat:@"model: %@", self.detector.statusText]];
    else [badges addObject:[NSString stringWithFormat:@"%.0f fps", self.detector.inferenceFPS]];
    if (self.lastLeaderLost) [badges addObject:@"mất dấu"];
    [badges addObject:@"GPS…"];
    [self.hud setBadges:badges];
}

#pragma mark - Demo HUD (khoảng cách thật ở Phase 2)

- (void)demoTick {
    self.demoT += 0.2;
    double v = 72.0;
    double threshold = 55.0 * (self.adverseWeather ? 1.5 : 1.0);
    double d = 58.0 + 14.0 * sin(self.demoT / 3.0);
    [self.hud setDistanceMeters:d valid:YES approximate:NO];
    [self.hud setSpeedKmh:v valid:YES];
    [self.hud setGapSeconds:d / (v / 3.6) valid:YES];
    [self.hud setThresholdText:[NSString stringWithFormat:@"≥ %@ m (%@)", KCFormatNumber(threshold, 0),
                                self.adverseWeather ? @"khuyến nghị (mưa/sương mù)" : @"luật"]];
    KCStatus s = (d >= threshold * 1.10) ? KCStatusGreen : (d >= threshold ? KCStatusYellow : KCStatusRed);
    [self.hud setStatus:s];
    self.overlay.leaderColor = (s == KCStatusRed) ? KCColorRed() : (s == KCStatusYellow ? KCColorYellow() : KCColorGreen());
}

#pragma mark - Buttons

- (void)toggleWeather {
    self.adverseWeather = !self.adverseWeather;
    [self.hud setAdverseWeatherActive:self.adverseWeather];
    KCLogf(@"ui: adverse weather = %d", self.adverseWeather);
}

- (void)showSettings {
    KCIntrinsics i = self.camera.lastIntrinsics;
    NSString *msg = [NSString stringWithFormat:
                     @"Phiên bản %@ (Phase 1 – phát hiện xe)\n"
                     @"Camera: %@ %d×%d, %.0f fps\n"
                     @"fx=%.1f fy=%.1f cx=%.1f cy=%.1f (%@)\n"
                     @"Model: %@ · suy luận %.1f fps (%.0f ms)\n"
                     @"Log: %@/log.txt",
                     kAppVersion, self.camera.deviceLabel ?: @"?", i.width, i.height, self.camera.measuredFPS,
                     i.fx, i.fy, i.cx, i.cy, i.fromDelivery ? @"intrinsics" : @"FOV",
                     self.detector.statusText, self.detector.inferenceFPS, self.detector.lastInferenceSeconds * 1000,
                     kKCDataDirectory];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Khoảng Cách An Toàn" message:msg preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;

    NSString *guideTitle = self.hud.showsGuides ? @"Ẩn vạch hướng dẫn" : @"Hiện vạch hướng dẫn";
    [ac addAction:[UIAlertAction actionWithTitle:guideTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        weakSelf.hud.showsGuides = !weakSelf.hud.showsGuides;
    }]];

    NSString *roiTitle = self.overlay.showsFarRegion ? @"Ẩn vùng quan tâm (kênh xa)" : @"Hiện vùng quan tâm (kênh xa)";
    [ac addAction:[UIAlertAction actionWithTitle:roiTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        weakSelf.overlay.showsFarRegion = !weakSelf.overlay.showsFarRegion;
    }]];

    BOOL saving = (self.detector.maxInferenceFPS <= 10.5);
    NSString *fpsTitle = saving ? @"Suy luận thường (15 fps)" : @"Tiết kiệm pin (10 fps)";
    [ac addAction:[UIAlertAction actionWithTitle:fpsTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        weakSelf.detector.maxInferenceFPS = saving ? 15.0 : 10.0;
        KCLogf(@"ui: maxInferenceFPS = %.0f", weakSelf.detector.maxInferenceFPS);
    }]];

    [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
