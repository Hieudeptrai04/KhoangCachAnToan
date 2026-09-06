#import "KCMainViewController.h"
#import "KCCameraController.h"
#import "KCDetector.h"
#import "KCTracker.h"
#import "KCRangeEstimator.h"
#import "KCMotion.h"
#import "KCLocation.h"
#import "KCLegalRules.h"
#import "KCAlertEngine.h"
#import "KCSettings.h"
#import "KCSettingsViewController.h"
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
@property (nonatomic, strong) KCRangeEstimator *estimator;
@property (nonatomic, strong) KCMotion *motion;
@property (nonatomic, strong) KCLocation *location;
@property (nonatomic, strong) KCAlertEngine *alertEngine;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) KCOverlayView *overlay;
@property (nonatomic, strong) KCHUDView *hud;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NSTimer *uiTimer;
@property (nonatomic, assign) BOOL adverseWeather;
@property (nonatomic, assign) BOOL cameraStarted;
@property (nonatomic, assign) AVCaptureVideoOrientation currentVideoOrientation;
@property (nonatomic, assign) CGSize lastBufferSize;

// Trạng thái mới nhất (chỉ đọc/ghi trên main queue).
@property (nonatomic, assign) NSUInteger lastDetectionCount;
@property (nonatomic, assign) NSUInteger lastInLaneCount;
@property (nonatomic, copy) NSString *lastLeaderText;
@property (nonatomic, assign) BOOL lastLeaderLost;
@property (nonatomic, assign) KCRangeResult lastRange;
@property (nonatomic, assign) CFAbsoluteTime lastRangeTime;
@property (nonatomic, assign) CFAbsoluteTime lastHudTextRefresh;
@property (nonatomic, assign) double lastThresholdMeters;
@property (nonatomic, assign) BOOL lastOverSpeed;
@end

@implementation KCMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.lastLeaderText = @"—";

    KCSettings *s = [KCSettings shared];

    self.camera = [[KCCameraController alloc] init];
    self.camera.delegate = self;

    self.tracker = [[KCTracker alloc] init];
    self.estimator = [[KCRangeEstimator alloc] init];

    self.motion = [[KCMotion alloc] init];
    self.motion.pitchOffsetRadians = s.pitchOffsetRadians;

    self.location = [[KCLocation alloc] init];
    self.alertEngine = [[KCAlertEngine alloc] init];

    // Nạp bảng luật, tự kiểm tra bảng ngưỡng (mục 10.4), rồi kiểm tra bản mới (tối đa 1 lần / 7 ngày).
    [[KCLegalRules shared] load];
    [[KCLegalRules shared] runSelfTest];
    [[KCLegalRules shared] updateFromServerIfDue];

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

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.errorLabel.textColor = KCColorRed();
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    [self applySettings];
    [self loadDetector];
    [self refreshBadges];
    [self.hud setSpeedKmh:0 valid:NO];
    [self.hud setGapSeconds:0 valid:NO];
    [self.hud setThresholdText:@"đang chờ GPS"];

    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(uiTick) userInfo:nil repeats:YES];
}

- (void)dealloc {
    [_uiTimer invalidate];
    [_motion stop];
    [_location stop];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startCameraIfNeeded];
    [self.motion start];
    [self.location start];
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

#pragma mark - Cài đặt

- (void)applySettings {
    KCSettings *s = [KCSettings shared];
    self.detector.maxInferenceFPS = s.maxInferenceFPS;
    self.hud.showsGuides = s.showsGuides;
    self.overlay.showsFarRegion = s.showsFarRegion;
    self.motion.pitchOffsetRadians = s.pitchOffsetRadians;
    self.alertEngine.beepEnabled = s.alertBeep;
    self.alertEngine.hapticEnabled = s.alertHaptic;
    self.alertEngine.speechEnabled = s.alertSpeech;
    CGRect roi = self.detector.farRegionOfInterest;
    self.overlay.farRegionTopLeft = CGRectMake(roi.origin.x, 1.0 - (roi.origin.y + roi.size.height),
                                               roi.size.width, roi.size.height);
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
        [self.estimator reset];
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
    // Vision ĐÃ được xoay sẵn (videoOrientation đặt trên connection của data output),
    // nên nrect vốn đã ở hệ hiển thị — dùng hàm đó là xoay hai lần: ở một trong hai chiều
    // ngang, mọi khung bao bị lật đối xứng qua tâm màn hình trong khi hình vẫn hiện đúng.
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

        CGFloat sc = MAX(ls.width / buf.width, ls.height / buf.height);   // resizeAspectFill
        CGFloat dw = buf.width * sc;
        CGFloat dh = buf.height * sc;
        CGFloat ox = (ls.width - dw) * 0.5;
        CGFloat oy = (ls.height - dh) * 0.5;

        return CGRectMake(ox + nrect.origin.x * dw,
                          oy + nrect.origin.y * dh,
                          nrect.size.width * dw,
                          nrect.size.height * dh);
    };

    [self applySettings];
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
    NSTimeInterval now = CFAbsoluteTimeGetCurrent();
    KCTrackerResult *result = [self.tracker updateWithDetections:detections timestamp:now];
    NSUInteger inLane = 0;
    for (KCDetection *d in result.detections) if (d.inLane) inLane += 1;

    KCIntrinsics intr = self.camera.lastIntrinsics;
    self.estimator.pitchRadians = self.motion.pitchRadians;

    KCRangeResult range;
    memset(&range, 0, sizeof(range));
    if (result.leader && !result.leaderLost) {
        range = [self.estimator estimateForDetection:result.leader
                                          intrinsics:intr
                                       farRegionSize:self.detector.farRegionOfInterest.size.width
                                           timestamp:now];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        [self.overlay updateWithDetections:result.detections leader:result.leader leaderLost:result.leaderLost];
        self.lastDetectionCount = result.detections.count;
        self.lastInLaneCount = inLane;
        self.lastLeaderLost = result.leaderLost;

        if (range.valid) {
            self.lastRange = range;
            self.lastRangeTime = CFAbsoluteTimeGetCurrent();
            [self.hud setDistanceMeters:range.distanceMeters valid:YES approximate:range.approximate];
        }

        if (result.leader) {
            CGFloat wpx = [result.leader widthPixelsForBufferWidth:intr.width];
            self.lastLeaderText = [NSString stringWithFormat:@"%@ #%ld %.0fpx %@",
                                   result.leader.label, (long)result.leader.trackID, wpx,
                                   result.leader.fromFarChannel ? @"xa" : @"gần"];
        } else {
            self.lastLeaderText = @"—";
        }

        // Khung bao vẽ lại mỗi lần suy luận; phần chữ chỉ 4 lần/giây
        // (dựng lại nhãn huy hiệu ở 15 Hz tốn CPU vô ích).
        CFAbsoluteTime t = CFAbsoluteTimeGetCurrent();
        if (t - self.lastHudTextRefresh >= 0.25) {
            self.lastHudTextRefresh = t;
            [self refreshDebugText];
            [self refreshBadges];
        }
    });
}

#pragma mark - Nhịp giao diện

- (void)uiTick {
    // Vạch chân trời theo góc chúc hiện tại: y = cy − fy·tan(θ).
    KCIntrinsics intr = self.camera.lastIntrinsics;
    if (intr.height > 0 && intr.fy > 0) {
        self.estimator.pitchRadians = self.motion.pitchRadians;
        double row = [self.estimator horizonRowForIntrinsics:intr];
        CGFloat ny = (CGFloat)(row / intr.height);
        if (ny > 0.02 && ny < 0.98) {
            self.hud.horizonY = ny;
            self.tracker.horizonY = ny;
        }
    }

    // Quá 1 giây không đo được thì xoá số, không giữ giá trị cũ trên màn hình.
    if (self.lastRangeTime > 0 && (CFAbsoluteTimeGetCurrent() - self.lastRangeTime) > 1.0) {
        [self.hud setDistanceMeters:0 valid:NO approximate:NO];
        KCRangeResult empty;
        memset(&empty, 0, sizeof(empty));
        self.lastRange = empty;
        self.lastRangeTime = 0;
        [self refreshBadges];
    }

    [self evaluateAgainstLaw];
}

/// Tra ngưỡng theo tốc độ, chấm trạng thái 3 màu và bắn cảnh báo (FR-2, FR-3, FR-4, FR-5).
- (void)evaluateAgainstLaw {
    KCSettings *s = [KCSettings shared];
    BOOL speedOK = self.location.speedValid;
    double v = self.location.speedKmh;

    [self.hud setSpeedKmh:v valid:speedOK];

    KCRangeResult r = self.lastRange;
    BOOL haveDistance = (r.valid && self.lastRangeTime > 0);

    // FR-2: chưa khoá GPS hoặc dưới 5 km/h thì ẩn phần luật, chỉ hiện khoảng cách.
    if (!speedOK || !self.location.moving) {
        [self.hud setGapSeconds:0 valid:NO];
        [self.hud setStatus:KCStatusNone];
        self.overlay.leaderColor = KCColorGreen();
        [self.hud setThresholdText:speedOK ? @"đang đứng yên" : @"đang chờ GPS"];
        self.lastOverSpeed = NO;
        return;
    }

    double factor = self.adverseWeather ? s.adverseFactor : 1.0;
    KCThreshold t = [[KCLegalRules shared] thresholdForSpeedKmh:v
                                                  adverseFactor:factor
                                                      timestamp:CFAbsoluteTimeGetCurrent()];
    self.lastThresholdMeters = t.meters;
    self.lastOverSpeed = t.overSpeed;

    NSString *kindText;
    if (t.kind == KCThresholdAdvisory) kindText = self.adverseWeather ? @"khuyến nghị (mưa/sương mù)" : @"khuyến nghị";
    else kindText = self.adverseWeather ? @"khuyến nghị (mưa/sương mù)" : @"luật";
    [self.hud setThresholdText:[NSString stringWithFormat:@"≥ %@ m (%@)", KCFormatNumber(t.meters, 0), kindText]];

    if (!haveDistance) {
        [self.hud setGapSeconds:0 valid:NO];
        [self.hud setStatus:KCStatusNone];
        self.overlay.leaderColor = KCColorGreen();
        return;
    }

    double d = r.distanceMeters;
    [self.hud setGapSeconds:d / (v / 3.6) valid:YES];

    KCStatus status;
    if (d >= t.meters * 1.10) status = KCStatusGreen;
    else if (d >= t.meters) status = KCStatusYellow;
    else status = KCStatusRed;

    [self.hud setStatus:status];
    self.overlay.leaderColor = (status == KCStatusRed) ? KCColorRed()
                             : (status == KCStatusYellow ? KCColorYellow() : KCColorGreen());

    if (status == KCStatusRed) {
        if ([self.alertEngine fireAlertWithSpokenText:@"Khoảng cách quá gần"]) {
            KCLogf(@"canh bao: D=%.1f m < nguong %.1f m tai %.0f km/h", d, t.meters, v);
        }
    }
}

#pragma mark - HUD

- (void)refreshDebugText {
    KCIntrinsics i = self.camera.lastIntrinsics;
    KCRangeResult r = self.lastRange;
    NSString *rangeText = r.valid
        ? [NSString stringWithFormat:@"D_w=%@ D_g=%@ hợp=%@±%@ v=%@ m/s",
           r.widthValid ? KCFormatNumber(r.widthMeters, 1) : @"—",
           r.groundValid ? KCFormatNumber(r.groundMeters, 1) : @"—",
           KCFormatNumber(r.fusedMeters, 1), KCFormatNumber(r.sigmaMeters, 1),
           KCFormatNumber(r.closingSpeedMps, 1)]
        : @"chưa đo";
    [self.hud setDebugText:[NSString stringWithFormat:
                            @"%@ %d×%d · cam %.0f fps · suy luận %.1f fps (%.0f ms) · %lu xe / %lu cùng làn · θ=%@° · %@",
                            self.camera.deviceLabel ?: @"?", i.width, i.height,
                            self.camera.measuredFPS, self.detector.inferenceFPS,
                            self.detector.lastInferenceSeconds * 1000,
                            (unsigned long)self.lastDetectionCount, (unsigned long)self.lastInLaneCount,
                            KCFormatNumber(self.motion.pitchRadians * 180 / M_PI, 1),
                            rangeText]];
}

- (void)refreshBadges {
    NSMutableArray<NSString *> *badges = [NSMutableArray array];
    if (!self.detector.ready) [badges addObject:[NSString stringWithFormat:@"model: %@", self.detector.statusText]];
    else [badges addObject:[NSString stringWithFormat:@"%.0f fps", self.detector.inferenceFPS]];
    if (self.lastLeaderLost) [badges addObject:@"mất dấu"];
    if (self.lastRange.needsCalibration) [badges addObject:@"cần hiệu chỉnh"];
    if (!self.motion.running) [badges addObject:@"chưa có cảm biến nghiêng"];
    if (!self.location.speedValid) [badges addObject:@"GPS…"];
    if (self.lastOverSpeed) [badges addObject:@"quá tốc độ"];
    if (self.adverseWeather) [badges addObject:@"thời tiết xấu"];
    [self.hud setBadges:badges];
}

#pragma mark - Nút

- (void)toggleWeather {
    self.adverseWeather = !self.adverseWeather;
    [self.hud setAdverseWeatherActive:self.adverseWeather];
    KCLogf(@"ui: adverse weather = %d", self.adverseWeather);
}

- (void)showSettings {
    KCSettingsViewController *vc = [[KCSettingsViewController alloc] init];
    vc.motion = self.motion;
    vc.alertEngine = self.alertEngine;
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    __weak typeof(self) weakSelf = self;
    vc.currentFusedDistance = ^double{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return 0;
        KCRangeResult r = strongSelf.lastRange;
        return r.valid ? r.fusedMeters : 0;
    };
    vc.onChange = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf applySettings];
    };
    [self presentViewController:vc animated:YES completion:nil];
}

@end
