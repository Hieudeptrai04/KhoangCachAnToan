#import "KCOnboardingViewController.h"
#import "KCLegalRules.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreLocation/CoreLocation.h>

static NSString *const kKCOnboardingKey = @"onboardingCompleted";

@interface KCOnboardingViewController () <UIScrollViewDelegate>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIPageControl *pageControl;
@property (nonatomic, strong) UIButton *nextButton;
@property (nonatomic, strong) NSArray<NSArray<NSString *> *> *pages;   // [icon, tiêu đề, nội dung]
@property (nonatomic, strong) CLLocationManager *locationManager;
@end

@implementation KCOnboardingViewController

+ (BOOL)shouldShow {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kKCPrefsPath];
    id v = prefs[kKCOnboardingKey];
    return !([v isKindOfClass:[NSNumber class]] && [v boolValue]);
}

+ (void)markCompleted {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kKCPrefsPath];
    NSMutableDictionary *m = prefs ? [prefs mutableCopy] : [NSMutableDictionary dictionary];
    m[kKCOnboardingKey] = @YES;
    NSString *dir = [kKCPrefsPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    [m writeToFile:kKCPrefsPath atomically:YES];
    KCLogf(@"onboarding: da danh dau hoan tat");
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    NSString *disclaimer = [KCLegalRules shared].disclaimer;
    if (!disclaimer.length) {
        disclaimer = @"Ứng dụng chỉ ước lượng bằng camera điện thoại, không phải thiết bị đo được kiểm định và không phải bằng chứng pháp lý.";
    }

    self.pages = @[
        @[@"📱", @"Gắn máy đúng chỗ",
          @"Đặt điện thoại NẰM NGANG, ở giữa kính lái, cao ngang gương chiếu hậu trong.\n\n"
          @"Ống kính không bị cần gạt mưa hay vết bẩn che. Giá đỡ phải chắc, máy không rung khi xe chạy."],
        @[@"📐", @"Cân ngang trước khi đi",
          @"Đỗ xe trên mặt phẳng, nhìn thẳng về phía trước.\n\n"
          @"Mở ⚙ → nhập chiều cao ống kính so mặt đường và khoảng cách từ máy tới đầu xe (đo bằng thước), "
          @"rồi bấm Cân ngang. Vạch nét đứt trên màn hình phải trùng đường chân trời thật."],
        @[@"⚠️", @"Đây chỉ là công cụ hỗ trợ",
          disclaimer],
    ];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.scrollView.pagingEnabled = YES;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.delegate = self;
    [self.view addSubview:self.scrollView];

    self.pageControl = [[UIPageControl alloc] init];
    self.pageControl.numberOfPages = self.pages.count;
    self.pageControl.currentPageIndicatorTintColor = KCColorGreen();
    self.pageControl.pageIndicatorTintColor = [UIColor colorWithWhite:0.35 alpha:1];
    self.pageControl.userInteractionEnabled = NO;
    [self.view addSubview:self.pageControl];

    self.nextButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.nextButton.backgroundColor = KCColorGreen();
    [self.nextButton setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
    self.nextButton.titleLabel.font = KCRoundedFont(18, UIFontWeightBold);
    self.nextButton.layer.cornerRadius = 16;
    self.nextButton.layer.cornerCurve = kCACornerCurveContinuous;
    [self.nextButton addTarget:self action:@selector(nextTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];

    [self updateButtonTitle];
    [self requestPermissions];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskPortrait; }
- (BOOL)prefersStatusBarHidden { return YES; }

- (void)requestPermissions {
    // Xin quyền ngay ở màn hướng dẫn để lúc vào màn đo là chạy được luôn.
    if ([AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo] == AVAuthorizationStatusNotDetermined) {
        [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
            KCLogf(@"onboarding: quyen camera = %d", granted);
        }];
    }
    self.locationManager = [[CLLocationManager alloc] init];
    if (self.locationManager.authorizationStatus == kCLAuthorizationStatusNotDetermined) {
        [self.locationManager requestWhenInUseAuthorization];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    UIEdgeInsets in = self.view.safeAreaInsets;
    self.scrollView.frame = b;
    self.scrollView.contentSize = CGSizeMake(b.size.width * self.pages.count, b.size.height);

    for (UIView *v in [self.scrollView.subviews copy]) [v removeFromSuperview];

    for (NSUInteger i = 0; i < self.pages.count; i++) {
        NSArray<NSString *> *page = self.pages[i];
        CGFloat x = b.size.width * i;
        CGFloat left = x + 32;
        CGFloat width = b.size.width - 64;
        CGFloat top = in.top + MAX(60, (b.size.height - in.top - in.bottom) * 0.16);

        UILabel *icon = [[UILabel alloc] initWithFrame:CGRectMake(left, top, width, 80)];
        icon.text = page[0];
        icon.font = [UIFont systemFontOfSize:64];
        [self.scrollView addSubview:icon];

        UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(left, top + 96, width, 40)];
        title.text = page[1];
        title.font = KCRoundedFont(28, UIFontWeightBold);
        title.textColor = KCColorGreen();
        [self.scrollView addSubview:title];

        UILabel *body = [[UILabel alloc] initWithFrame:CGRectMake(left, top + 148, width, b.size.height - top - 260)];
        body.text = page[2];
        body.font = [UIFont systemFontOfSize:17];
        body.textColor = [UIColor colorWithWhite:0.88 alpha:1];
        body.numberOfLines = 0;
        [self.scrollView addSubview:body];
    }

    CGFloat bottom = b.size.height - in.bottom - 24;
    self.nextButton.frame = CGRectMake(32, bottom - 54, b.size.width - 64, 54);
    self.pageControl.frame = CGRectMake(32, bottom - 54 - 40, b.size.width - 64, 34);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    NSInteger page = (NSInteger)round(scrollView.contentOffset.x / MAX(scrollView.bounds.size.width, 1));
    if (page != self.pageControl.currentPage) {
        self.pageControl.currentPage = page;
        [self updateButtonTitle];
    }
}

- (void)updateButtonTitle {
    BOOL last = (self.pageControl.currentPage == (NSInteger)self.pages.count - 1);
    [self.nextButton setTitle:last ? @"Tôi đã hiểu, bắt đầu" : @"Tiếp theo" forState:UIControlStateNormal];
}

- (void)nextTapped {
    NSInteger page = self.pageControl.currentPage;
    if (page < (NSInteger)self.pages.count - 1) {
        [self.scrollView setContentOffset:CGPointMake(self.scrollView.bounds.size.width * (page + 1), 0) animated:YES];
        return;
    }
    [KCOnboardingViewController markCompleted];
    void (^finish)(void) = self.onFinish;
    [self dismissViewControllerAnimated:YES completion:^{
        if (finish) finish();
    }];
}

@end
