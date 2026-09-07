#import "KCMapViewController.h"
#import "KCLocation.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <MapKit/MapKit.h>

@interface KCMapViewController () <MKMapViewDelegate>
@property (nonatomic, strong) MKMapView *mapView;
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *speedUnitLabel;
@property (nonatomic, strong) UILabel *accuracyLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *styleButton;
@property (nonatomic, strong) UIButton *recenterButton;
@property (nonatomic, strong) UIButton *handoffButton;
@property (nonatomic, strong) NSTimer *tick;
@property (nonatomic, assign) BOOL hybrid;
@end

@implementation KCMapViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    self.mapView = [[MKMapView alloc] initWithFrame:self.view.bounds];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.delegate = self;
    self.mapView.showsUserLocation = YES;
    self.mapView.showsCompass = YES;
    self.mapView.showsScale = YES;
    self.mapView.showsTraffic = NO;
    self.mapView.userTrackingMode = MKUserTrackingModeFollowWithHeading;
    [self.view addSubview:self.mapView];

    self.closeButton = [self glassButtonWithSymbol:@"xmark" action:@selector(closeTapped)];
    self.styleButton = [self glassButtonWithSymbol:@"map" action:@selector(styleTapped)];
    [self.view addSubview:self.closeButton];
    [self.view addSubview:self.styleButton];

    [self buildCard];

    self.tick = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refresh)
                                               userInfo:nil repeats:YES];
    [self refresh];
    KCLogf(@"map: mo ban do");
}

- (void)dealloc {
    [_tick invalidate];
    _mapView.delegate = nil;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (BOOL)prefersStatusBarHidden { return YES; }

- (UIButton *)glassButtonWithSymbol:(NSString *)symbol action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                      weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    b.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.72];
    b.layer.cornerRadius = 25;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)buildCard {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    self.card = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.card.layer.cornerRadius = 26;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.clipsToBounds = YES;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    [self.view addSubview:self.card];

    UIView *content = self.card.contentView;

    self.speedLabel = [[UILabel alloc] init];
    self.speedLabel.font = KCRoundedDigitFont(44, UIFontWeightHeavy);
    self.speedLabel.textColor = [UIColor whiteColor];
    self.speedLabel.text = @"—";
    [content addSubview:self.speedLabel];

    self.speedUnitLabel = [[UILabel alloc] init];
    self.speedUnitLabel.font = KCRoundedFont(13, UIFontWeightSemibold);
    self.speedUnitLabel.textColor = KCColorMuted();
    self.speedUnitLabel.text = @"km/h";
    [content addSubview:self.speedUnitLabel];

    self.accuracyLabel = [[UILabel alloc] init];
    self.accuracyLabel.font = KCRoundedFont(11.5, UIFontWeightMedium);
    self.accuracyLabel.textColor = KCColorMuted();
    self.accuracyLabel.numberOfLines = 2;
    self.accuracyLabel.text = @"Đang chờ GPS";
    [content addSubview:self.accuracyLabel];

    self.recenterButton = [self pillButtonWithTitle:@"Về vị trí của tôi" symbol:@"location.fill"
                                             filled:NO action:@selector(recenterTapped)];
    self.handoffButton = [self pillButtonWithTitle:@"Mở Google Maps" symbol:@"arrow.up.forward.app"
                                            filled:YES action:@selector(handoffTapped)];
    [content addSubview:self.recenterButton];
    [content addSubview:self.handoffButton];
}

- (UIButton *)pillButtonWithTitle:(NSString *)title symbol:(NSString *)symbol filled:(BOOL)filled action:(SEL)action {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:13
                                                                                      weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    [b setTitle:[@"  " stringByAppendingString:title] forState:UIControlStateNormal];
    b.titleLabel.font = KCRoundedFont(14, UIFontWeightSemibold);
    b.tintColor = filled ? [UIColor blackColor] : [UIColor whiteColor];
    [b setTitleColor:filled ? [UIColor blackColor] : [UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = filled ? KCColorGreen() : [UIColor colorWithWhite:1 alpha:0.14];
    b.layer.cornerRadius = 18;
    b.layer.cornerCurve = kCACornerCurveContinuous;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets in = self.view.safeAreaInsets;

    CGFloat top = in.top + 10;
    self.closeButton.frame = CGRectMake(16, top, 50, 50);
    self.styleButton.frame = CGRectMake(b.size.width - 16 - 50, top, 50, 50);

    CGFloat cardH = 148;
    CGFloat cardW = b.size.width - 24;
    CGFloat cardY = b.size.height - in.bottom - 10 - cardH;
    self.card.frame = CGRectMake(12, cardY, cardW, cardH);

    CGFloat pad = 16;
    self.speedLabel.frame = CGRectMake(pad, pad - 6, 130, 48);
    self.speedUnitLabel.frame = CGRectMake(pad + 2, pad + 40, 60, 16);
    self.accuracyLabel.frame = CGRectMake(pad + 130, pad, cardW - pad * 2 - 130, 46);

    CGFloat bw = (cardW - pad * 2 - 10) / 2.0;
    CGFloat by = cardH - pad - 40;
    self.recenterButton.frame = CGRectMake(pad, by, bw, 40);
    self.handoffButton.frame = CGRectMake(pad + bw + 10, by, bw, 40);

    // Chừa chỗ cho thẻ đáy và hai nút trên, để điều khiển của bản đồ không bị che.
    self.mapView.layoutMargins = UIEdgeInsetsMake(top + 56, 16, b.size.height - cardY + 10, 16);
}

#pragma mark - Hành động

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)styleTapped {
    self.hybrid = !self.hybrid;
    self.mapView.mapType = self.hybrid ? MKMapTypeHybrid : MKMapTypeStandard;
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18
                                                                                      weight:UIImageSymbolWeightSemibold];
    [self.styleButton setImage:[UIImage systemImageNamed:(self.hybrid ? @"globe.asia.australia" : @"map")
                                       withConfiguration:cfg]
                      forState:UIControlStateNormal];
}

- (void)recenterTapped {
    [self.mapView setUserTrackingMode:MKUserTrackingModeFollowWithHeading animated:YES];
}

/// Bàn giao sang Google Maps ở đúng vị trí hiện tại. Chưa cài Google Maps thì mở bản web.
- (void)handoffTapped {
    CLLocationCoordinate2D c = self.mapView.userLocation.location
        ? self.mapView.userLocation.location.coordinate
        : self.mapView.centerCoordinate;
    if (!CLLocationCoordinate2DIsValid(c)) {
        KCLogf(@"map: chua co toa do de ban giao");
        return;
    }
    NSString *appURL = [NSString stringWithFormat:@"comgooglemaps://?center=%.6f,%.6f&zoom=16", c.latitude, c.longitude];
    NSURL *url = [NSURL URLWithString:appURL];
    UIApplication *app = [UIApplication sharedApplication];
    if (![app canOpenURL:url]) {
        url = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.google.com/maps/@%.6f,%.6f,16z",
                                    c.latitude, c.longitude]];
    }
    KCLogf(@"map: ban giao sang %@", url.scheme);
    [app openURL:url options:@{} completionHandler:nil];
}

#pragma mark - Cập nhật

- (void)refresh {
    KCLocation *loc = self.location;
    BOOL ok = loc.speedValid;
    NSString *t = ok ? KCFormatNumber(loc.speedKmh, 0) : @"—";
    if (![self.speedLabel.text isEqualToString:t]) self.speedLabel.text = t;

    CLLocation *fix = self.mapView.userLocation.location;
    if (fix && fix.horizontalAccuracy > 0) {
        self.accuracyLabel.text = [NSString stringWithFormat:@"Sai số vị trí khoảng %@ m\nBản đồ chỉ để xem, không dẫn đường",
                                   KCFormatNumber(fix.horizontalAccuracy, 0)];
    } else {
        self.accuracyLabel.text = @"Đang chờ GPS";
    }
}

@end
