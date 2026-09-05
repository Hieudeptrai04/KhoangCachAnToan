#import "KCMainViewController.h"
#import "KCCameraController.h"
#import "KCHUDView.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <AVFoundation/AVFoundation.h>
#import <math.h>

@interface KCMainViewController () <KCCameraFrameDelegate>
@property (nonatomic, strong) KCCameraController *camera;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) KCHUDView *hud;
@property (nonatomic, strong) UILabel *errorLabel;
@property (nonatomic, strong) NSTimer *demoTimer;
@property (nonatomic, assign) double demoT;
@property (nonatomic, assign) BOOL adverseWeather;
@property (nonatomic, assign) BOOL cameraStarted;
@property (nonatomic, assign) NSUInteger frameCounter;
@property (nonatomic, assign) AVCaptureVideoOrientation currentVideoOrientation;
@end

@implementation KCMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.camera = [[KCCameraController alloc] init];
    self.camera.delegate = self;

    self.hud = [[KCHUDView alloc] initWithFrame:self.view.bounds];
    self.hud.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.hud];
    [self.hud.weatherButton addTarget:self action:@selector(toggleWeather) forControlEvents:UIControlEventTouchUpInside];
    [self.hud.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.hud setBadges:@[@"DEMO", @"GPS…"]];
    [self.hud setThresholdText:@"≥ 55 m (luật)"];

    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.errorLabel.textColor = KCColorRed();
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 0;
    self.errorLabel.hidden = YES;
    [self.view addSubview:self.errorLabel];

    // Phase 0: HUD số giả để kiểm tra bố cục; thay bằng đo thật ở Phase 1–3.
    self.demoTimer = [NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(demoTick) userInfo:nil repeats:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startCameraIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.previewLayer.frame = self.view.bounds;
    self.errorLabel.frame = CGRectInset(self.view.bounds, 60, 120);
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
    UIInterfaceOrientation io = [self interfaceOrientationNow];
    AVCaptureVideoOrientation vo = (io == UIInterfaceOrientationLandscapeLeft) ? AVCaptureVideoOrientationLandscapeLeft
                                                                              : AVCaptureVideoOrientationLandscapeRight;
    if (self.previewLayer.connection.isVideoOrientationSupported && self.previewLayer.connection.videoOrientation != vo) {
        self.previewLayer.connection.videoOrientation = vo;
    }
    [self.camera applyVideoOrientation:vo];
    if (vo != self.currentVideoOrientation) {
        self.currentVideoOrientation = vo;
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
    [self applyOrientation];
    [self.camera startRunning];
    KCLogf(@"camera: preview layer added, session start requested (device=%@)", self.camera.deviceLabel);
}

- (void)showError:(NSString *)msg {
    KCLogf(@"ERROR: %@", msg);
    self.errorLabel.text = msg;
    self.errorLabel.hidden = NO;
}

#pragma mark - KCCameraFrameDelegate (hàng đợi camera)

- (void)cameraController:(KCCameraController *)controller didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer intrinsics:(KCIntrinsics)intrinsics timestamp:(CMTime)timestamp {
    self.frameCounter += 1;
    if (self.frameCounter % 15 != 0) return;
    double fps = controller.measuredFPS;
    NSString *label = controller.deviceLabel ?: @"?";
    KCIntrinsics intr = intrinsics;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.hud setDebugText:[NSString stringWithFormat:@"%@ %dx%d  fx=%.0f fy=%.0f cx=%.0f cy=%.0f (%@)  cam %.0f fps",
                                label, intr.width, intr.height, intr.fx, intr.fy, intr.cx, intr.cy,
                                intr.fromDelivery ? @"intrinsics" : @"fov", fps]];
    });
}

#pragma mark - Demo HUD (Phase 0)

- (void)demoTick {
    self.demoT += 0.2;
    double v = 72.0;                                           // km/h giả
    double threshold = 55.0 * (self.adverseWeather ? 1.5 : 1.0);
    double d = 58.0 + 14.0 * sin(self.demoT / 3.0);            // dao động 44–72 m để thấy đủ 3 màu
    [self.hud setDistanceMeters:d valid:YES approximate:NO];
    [self.hud setSpeedKmh:v valid:YES];
    [self.hud setGapSeconds:d / (v / 3.6) valid:YES];
    [self.hud setThresholdText:[NSString stringWithFormat:@"≥ %@ m (%@)", KCFormatNumber(threshold, 0),
                                self.adverseWeather ? @"khuyến nghị (mưa/sương mù)" : @"luật"]];
    KCStatus s = (d >= threshold * 1.10) ? KCStatusGreen : (d >= threshold ? KCStatusYellow : KCStatusRed);   // FR-3
    [self.hud setStatus:s];
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
                     @"Phiên bản %@ (Phase 0 – khung xương)\nCamera: %@ %d×%d\nfx=%.1f fy=%.1f cx=%.1f cy=%.1f (%@)\nCam FPS: %.1f\nLog: %@/log.txt",
                     kAppVersion, self.camera.deviceLabel ?: @"?", i.width, i.height, i.fx, i.fy, i.cx, i.cy,
                     i.fromDelivery ? @"intrinsics" : @"FOV", self.camera.measuredFPS, kKCDataDirectory];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Khoảng Cách An Toàn" message:msg preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    NSString *guideTitle = self.hud.showsGuides ? @"Ẩn vạch hướng dẫn" : @"Hiện vạch hướng dẫn";
    [ac addAction:[UIAlertAction actionWithTitle:guideTitle style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        weakSelf.hud.showsGuides = !weakSelf.hud.showsGuides;
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Đóng" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
