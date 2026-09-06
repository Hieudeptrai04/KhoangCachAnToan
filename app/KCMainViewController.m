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
#import "KCOnboardingViewController.h"
#import "KCTripLogger.h"
#import "KCOverlayView.h"
#import "KCHUDView.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

/// Bề rộng làn giả định khi vẽ thảm khoảng cách (m).
static const double kKCLaneWidthMeters = 3.5;

@interface KCMainViewController () <KCCameraFrameDelegate, KCDetectorDelegate>
@property (nonatomic, strong) KCCameraController *camera;
@property (nonatomic, strong) KCDetector *detector;
@property (nonatomic, strong) KCTracker *tracker;
@property (nonatomic, strong) KCRangeEstimator *estimator;
@property (nonatomic, strong) KCMotion *motion;
@property (nonatomic, strong) KCLocation *location;
@property (nonatomic, strong) KCAlertEngine *alertEngine;
@property (nonatomic, strong) KCTripLogger *tripLogger;
@property (nonatomic, assign) BOOL onboardingHandled;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) KCOverlayView *overlay;
@property (nonatomic, strong) KCHUDView *hud;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NSTimer *uiTimer;
@property (nonatomic, assign) BOOL adverseWeather;
@property (nonatomic, assign) BOOL cameraStarted;
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
    self.tripLogger = [[KCTripLogger alloc] init];

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
    self.errorLabel.font = KCRoundedFont(17, UIFontWeightSemibold);
    self.errorLabel.textColor = KCColorRed();
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    [self applySettings];
    [self loadDetector];
    [self refreshBadges];
    [self.hud setStatus:KCStatusNone text:@"Đang chờ GPS"];

    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(uiTick) userInfo:nil repeats:YES];
}

- (void)dealloc {
    [_uiTimer invalidate];
    [_motion stop];
    [_location stop];
    [_tripLogger stop];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    // Lần mở đầu tiên: 3 slide hướng dẫn và xin quyền, sau đó mới bật camera.
    if (!self.onboardingHandled) {
        self.onboardingHandled = YES;
        if ([KCOnboardingViewController shouldShow]) {
            KCOnboardingViewController *vc = [[KCOnboardingViewController alloc] init];
            vc.modalPresentationStyle = UIModalPresentationFullScreen;
            __weak typeof(self) weakSelf = self;
            vc.onFinish = ^{ [weakSelf startEverything]; };
            [self presentViewController:vc animated:NO completion:nil];
            return;
        }
    }
    [self startEverything];
}

- (void)startEverything {
    [self startCameraIfNeeded];
    [self.motion start];
    [self.location start];
    if ([KCSettings shared].logTripCSV && !self.tripLogger.recording) [self.tripLogger start];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
    self.errorLabel.frame = CGRectInset(self.view.bounds, 32, 200);
    [self.view bringSubviewToFront:self.overlay];
    [self.view bringSubviewToFront:self.hud];
    self.overlay.bottomLimitY = self.hud.cardTopY > 0 ? self.hud.cardTopY - 8 : 0;
    [self applyOrientation];
}

#pragma mark - Hướng màn hình: chỉ DỌC

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (BOOL)shouldAutorotate { return NO; }
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }

- (void)applyOrientation {
    AVCaptureVideoOrientation vo = AVCaptureVideoOrientationPortrait;
    if (self.previewLayer.connection.isVideoOrientationSupported && self.previewLayer.connection.videoOrientation != vo) {
        self.previewLayer.connection.videoOrientation = vo;
    }
    [self.camera applyVideoOrientation:vo];
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
    if (s.logTripCSV && !self.tripLogger.recording) [self.tripLogger start];
    else if (!s.logTripCSV && self.tripLogger.recording) [self.tripLogger stop];

    CGRect roi = self.detector.farRegionOfInterest;
    self.overlay.farRegionTopLeft = CGRectMake(roi.origin.x, 1.0 - (roi.origin.y + roi.size.height),
                                               roi.size.width, roi.size.height);
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
    KCSettings *cfg = [KCSettings shared];
    if (![self.camera setupPreferTelephoto:cfg.preferTelephoto use4K:cfg.use4K error:&err]) {
        [self showError:[NSString stringWithFormat:@"Không mở được camera: %@", err.localizedDescription ?: @"?"]];
        return;
    }
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.camera.session];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    self.previewLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:self.previewLayer atIndex:0];

    // Buffer đưa cho Vision đã được data output xoay theo chiều màn hình, tức cùng ảnh mà
    // preview đang hiển thị. Vì vậy chỉ cần co giãn resizeAspectFill, KHÔNG xoay thêm lần nữa
    // (dùng rectForMetadataOutputRectOfInterest: ở đây sẽ xoay hai lần).
    __weak typeof(self) weakSelf = self;
    self.overlay.rectConverter = ^CGRect(CGRect nrect) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        CGFloat sc, ox, oy;
        if (![strongSelf previewScale:&sc offsetX:&ox offsetY:&oy]) return CGRectZero;
        CGSize buf = strongSelf.lastBufferSize;
        return CGRectMake(ox + nrect.origin.x * buf.width * sc,
                          oy + nrect.origin.y * buf.height * sc,
                          nrect.size.width * buf.width * sc,
                          nrect.size.height * buf.height * sc);
    };
    self.overlay.pointConverter = ^CGPoint(CGPoint np) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        CGFloat sc, ox, oy;
        if (![strongSelf previewScale:&sc offsetX:&ox offsetY:&oy]) return CGPointZero;
        CGSize buf = strongSelf.lastBufferSize;
        return CGPointMake(ox + np.x * buf.width * sc, oy + np.y * buf.height * sc);
    };

    [self applySettings];
    [self applyOrientation];
    [self.camera startRunning];
    KCLogf(@"camera: preview layer added, session start requested (device=%@)", self.camera.deviceLabel);
    [self refreshBadges];
}

/// Hệ số co giãn và độ lệch tâm của preview theo kiểu resizeAspectFill.
- (BOOL)previewScale:(CGFloat *)scale offsetX:(CGFloat *)ox offsetY:(CGFloat *)oy {
    AVCaptureVideoPreviewLayer *layer = self.previewLayer;
    if (!layer) return NO;
    CGSize buf = self.lastBufferSize;
    CGSize ls = layer.bounds.size;
    if (buf.width <= 0 || buf.height <= 0 || ls.width <= 0 || ls.height <= 0) return NO;
    CGFloat s = MAX(ls.width / buf.width, ls.height / buf.height);
    *scale = s;
    *ox = (ls.width - buf.width * s) * 0.5;
    *oy = (ls.height - buf.height * s) * 0.5;
    return YES;
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
    self.lastBufferSize = CGSizeMake(CVPixelBufferGetWidth(pixelBuffer), CVPixelBufferGetHeight(pixelBuffer));
    // Buffer đã được data output xoay đúng chiều -> khai .up cho Vision là đúng sự thật.
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
        if (range.valid) {
            self.lastRange = range;
            self.lastRangeTime = CFAbsoluteTimeGetCurrent();
            [self.hud setDistanceMeters:range.distanceMeters valid:YES approximate:range.approximate];
        }
        self.lastDetectionCount = result.detections.count;
        self.lastInLaneCount = inLane;
        self.lastLeaderLost = result.leaderLost;

        KCRangeResult shown = self.lastRange;
        BOOL haveDistance = (shown.valid && self.lastRangeTime > 0);
        [self.overlay updateWithDetections:result.detections
                                    leader:result.leader
                                leaderLost:result.leaderLost
                           displayedMeters:shown.distanceMeters
                           distanceIsValid:haveDistance
                                  geometry:[self ladderGeometryWithIntrinsics:intr fused:shown.fusedMeters valid:haveDistance]];

        if (result.leader) {
            CGFloat wpx = [result.leader widthPixelsForBufferWidth:intr.width];
            self.lastLeaderText = [NSString stringWithFormat:@"%@ #%ld %.0fpx %@",
                                   result.leader.label, (long)result.leader.trackID, wpx,
                                   result.leader.fromFarChannel ? @"xa" : @"gần"];
        } else {
            self.lastLeaderText = @"—";
        }

        CFAbsoluteTime t = CFAbsoluteTimeGetCurrent();
        if (t - self.lastHudTextRefresh >= 0.25) {
            self.lastHudTextRefresh = t;
            [self.hud setInferenceFPS:self.detector.inferenceFPS];
            [self refreshDebugText];
            [self refreshBadges];
        }
    });
}

- (KCLadderGeometry)ladderGeometryWithIntrinsics:(KCIntrinsics)intr fused:(double)fusedMeters valid:(BOOL)valid {
    KCLadderGeometry g;
    memset(&g, 0, sizeof(g));
    g.valid = valid && intr.width > 0 && intr.fx > 0;
    g.fx = intr.fx; g.fy = intr.fy; g.cx = intr.cx; g.cy = intr.cy;
    g.bufferWidth = intr.width; g.bufferHeight = intr.height;
    g.pitchRadians = self.motion.pitchRadians;
    g.cameraHeightMeters = [KCSettings shared].cameraHeightMeters;
    g.laneWidthMeters = kKCLaneWidthMeters;
    g.leadDistanceMeters = fusedMeters;
    g.thresholdMeters = self.lastThresholdMeters;
    return g;
}

#pragma mark - Nhịp giao diện

- (void)uiTick {
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

    // Thời gian tới va chạm: chỉ có nghĩa khi đang tiến sát.
    double closing = -r.closingSpeedMps;
    BOOL ttcValid = haveDistance && closing > 0.3;
    [self.hud setTimeToCollisionSeconds:ttcValid ? (r.distanceMeters / closing) : 0 valid:ttcValid];

    // FR-2: chưa khoá GPS hoặc dưới 5 km/h thì ẩn phần luật, chỉ hiện khoảng cách.
    if (!speedOK || !self.location.moving) {
        [self.hud setGapSeconds:0 valid:NO];
        [self.hud setThresholdMeters:0 valid:NO legal:YES];
        [self.hud setStatus:KCStatusNone text:speedOK ? @"Đang đứng yên" : @"Đang chờ GPS"];
        self.overlay.leaderColor = KCColorGreen();
        self.lastOverSpeed = NO;
        self.lastThresholdMeters = 0;
        [self.tripLogger logSpeedKmh:v speedValid:speedOK
                            distance:r.distanceMeters distanceValid:haveDistance
                           threshold:0 status:speedOK ? @"dung_yen" : @"cho_gps"];
        return;
    }

    double factor = self.adverseWeather ? s.adverseFactor : 1.0;
    KCThreshold t = [[KCLegalRules shared] thresholdForSpeedKmh:v
                                                  adverseFactor:factor
                                                      timestamp:CFAbsoluteTimeGetCurrent()];
    self.lastThresholdMeters = t.meters;
    self.lastOverSpeed = t.overSpeed;
    [self.hud setThresholdMeters:t.meters valid:YES legal:(t.kind == KCThresholdLegal && !self.adverseWeather)];

    if (!haveDistance) {
        [self.hud setGapSeconds:0 valid:NO];
        [self.hud setStatus:KCStatusNone text:@"Không thấy xe trước"];
        self.overlay.leaderColor = KCColorGreen();
        [self.tripLogger logSpeedKmh:v speedValid:YES distance:0 distanceValid:NO
                           threshold:t.meters status:@"khong_thay_xe"];
        return;
    }

    double d = r.distanceMeters;
    [self.hud setGapSeconds:d / (v / 3.6) valid:YES];

    KCStatus status;
    NSString *statusText;
    if (d >= t.meters * 1.10)      { status = KCStatusGreen;  statusText = @"An toàn"; }
    else if (d >= t.meters)        { status = KCStatusYellow; statusText = @"Sát ngưỡng"; }
    else                           { status = KCStatusRed;    statusText = @"Quá gần"; }

    [self.hud setStatus:status text:statusText];
    self.overlay.leaderColor = (status == KCStatusRed) ? KCColorRed()
                             : (status == KCStatusYellow ? KCColorYellow() : KCColorGreen());

    if (status == KCStatusRed) {
        if ([self.alertEngine fireAlertWithSpokenText:@"Khoảng cách quá gần"]) {
            KCLogf(@"canh bao: D=%.1f m < nguong %.1f m tai %.0f km/h", d, t.meters, v);
        }
    }

    NSString *logStatus = (status == KCStatusRed) ? @"do" : (status == KCStatusYellow ? @"vang" : @"xanh");
    [self.tripLogger logSpeedKmh:v speedValid:YES distance:d distanceValid:YES
                       threshold:t.meters status:logStatus];
}

#pragma mark - HUD

- (void)refreshDebugText {
    KCIntrinsics i = self.camera.lastIntrinsics;
    KCRangeResult r = self.lastRange;
    NSString *rangeText = r.valid
        ? [NSString stringWithFormat:@"D_w=%@ D_g=%@ hợp=%@±%@",
           r.widthValid ? KCFormatNumber(r.widthMeters, 1) : @"—",
           r.groundValid ? KCFormatNumber(r.groundMeters, 1) : @"—",
           KCFormatNumber(r.fusedMeters, 1), KCFormatNumber(r.sigmaMeters, 1)]
        : @"chưa đo";
    [self.hud setDebugText:[NSString stringWithFormat:
                            @"%@ %d×%d · %lu khung · cam %.0f fps · suy luận %.1f fps (%.0f ms)\n"
                            @"%lu xe / %lu cùng làn · θ=%@° · %@",
                            self.camera.deviceLabel ?: @"?", i.width, i.height,
                            (unsigned long)self.camera.totalFrames,
                            self.camera.measuredFPS, self.detector.inferenceFPS,
                            self.detector.lastInferenceSeconds * 1000,
                            (unsigned long)self.lastDetectionCount, (unsigned long)self.lastInLaneCount,
                            KCFormatNumber(self.motion.pitchRadians * 180 / M_PI, 1),
                            rangeText]];
}

- (void)refreshBadges {
    NSMutableArray<NSString *> *badges = [NSMutableArray array];
    if (!self.detector.ready) [badges addObject:[NSString stringWithFormat:@"model: %@", self.detector.statusText]];
    if (self.lastLeaderLost) [badges addObject:@"mất dấu"];
    if (self.lastRange.needsCalibration) [badges addObject:@"cần hiệu chỉnh"];
    if (!self.location.speedValid) [badges addObject:@"GPS…"];
    if (self.lastOverSpeed) [badges addObject:@"quá tốc độ"];
    if (self.adverseWeather) [badges addObject:@"thời tiết xấu"];
    if (self.camera.totalFrames == 0 && self.cameraStarted) [badges addObject:@"chưa có hình"];
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
    vc.debugToggle = ^(BOOL on) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        [strongSelf.hud setDebugVisible:on];
    };
    [self presentViewController:vc animated:YES completion:nil];
}

@end
