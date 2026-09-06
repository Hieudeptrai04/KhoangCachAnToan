#import "KCLegalViewController.h"
#import "KCLegalRules.h"
#import "KCCommon.h"

/// 1000000 -> "1.000.000" (cách viết số tiền của Việt Nam).
static NSString *KCFormatVND(double amount) {
    NSNumberFormatter *f = [[NSNumberFormatter alloc] init];
    f.numberStyle = NSNumberFormatterDecimalStyle;
    f.groupingSeparator = @".";
    f.groupingSize = 3;
    f.usesGroupingSeparator = YES;
    f.maximumFractionDigits = 0;
    return [f stringFromNumber:@(amount)] ?: @"?";
}

@interface KCLegalViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray<NSArray<NSArray<NSString *> *> *> *sections;   // [section][row] = @[trái, phải]
@property (nonatomic, strong) NSArray<NSString *> *titles;
@property (nonatomic, strong) NSArray<NSString *> *footers;
@end

@implementation KCLegalViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    [self buildContent];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 48;
    self.tableView.contentInset = UIEdgeInsetsMake(56, 0, 0, 0);
    [self.view addSubview:self.tableView];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Đóng" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    [close setTitleColor:KCColorGreen() forState:UIControlStateNormal];
    close.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
    close.layer.cornerRadius = 10;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:close];
    [NSLayoutConstraint activateConstraints:@[
        [close.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor constant:-16],
        [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [close.widthAnchor constraintEqualToConstant:96],
        [close.heightAnchor constraintEqualToConstant:40],
    ]];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)prefersStatusBarHidden { return YES; }

- (void)closeTapped { [self dismissViewControllerAnimated:YES completion:nil]; }

#pragma mark - Nội dung

- (void)buildContent {
    KCLegalRules *r = [KCLegalRules shared];
    NSMutableArray *sections = [NSMutableArray array];
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *footers = [NSMutableArray array];

    // --- Khoảng cách tối thiểu ---
    NSMutableArray *rows = [NSMutableArray array];
    NSArray<NSDictionary *> *brackets = r.brackets;
    for (NSUInteger i = 0; i < brackets.count; i++) {
        double vmax = [brackets[i][@"v_max"] doubleValue];
        double m = [brackets[i][@"min_m"] doubleValue];
        NSString *left;
        if (i == 0) left = [NSString stringWithFormat:@"V = %@ km/h", KCFormatNumber(vmax, 0)];
        else left = [NSString stringWithFormat:@"%@ < V ≤ %@ km/h",
                     KCFormatNumber([brackets[i - 1][@"v_max"] doubleValue], 0), KCFormatNumber(vmax, 0)];
        [rows addObject:@[left, [NSString stringWithFormat:@"%@ m", KCFormatNumber(m, 0)]]];
    }
    [rows addObject:@[[NSString stringWithFormat:@"V < %@ km/h", KCFormatNumber(r.legalFromKmh, 0)],
                      @"tài xế chủ động"]];
    [titles addObject:@"Khoảng cách an toàn tối thiểu"];
    [sections addObject:rows];
    [footers addObject:[NSString stringWithFormat:
                        @"%@\nÁp dụng khi mặt đường khô ráo, không sương mù, không trơn trượt, đường thẳng, tầm nhìn tốt.\n"
                        @"Dưới %@ km/h luật không cho số cứng; app gợi ý khoảng cách đi hết %@ giây.\n"
                        @"Nơi có biển P.121 “Cự ly tối thiểu giữa hai xe”: giữ không nhỏ hơn trị số trên biển.\n"
                        @"Mưa, sương mù, đường trơn, đèo dốc, tầm nhìn hạn chế: phải tăng khoảng cách so với bảng.",
                        r.source, KCFormatNumber(r.legalFromKmh, 0), KCFormatNumber(r.advisorySeconds, 0)]];

    // --- Mức phạt ---
    NSMutableArray *fines = [NSMutableArray array];
    NSDictionary *contextNames = @{
        @"normal": @"Không giữ khoảng cách để xảy ra va chạm, hoặc không giữ theo biển “Cự ly tối thiểu”",
        @"highway": @"Không giữ khoảng cách với xe liền trước trên đường cao tốc",
        @"accident": @"Không giữ khoảng cách an toàn gây tai nạn giao thông",
    };
    NSString *refText = nil;
    for (NSDictionary *p in r.penalties) {
        NSString *ctx = p[@"context"];
        NSArray *range = p[@"fine_vnd"];
        if (![range isKindOfClass:[NSArray class]] || range.count < 2) continue;
        NSString *money = [NSString stringWithFormat:@"%@ – %@ đ",
                           KCFormatVND([range[0] doubleValue]), KCFormatVND([range[1] doubleValue])];
        NSInteger points = [p[@"points"] integerValue];
        if (points > 0) money = [money stringByAppendingFormat:@"\ntrừ %ld điểm giấy phép lái xe", (long)points];
        [fines addObject:@[contextNames[ctx] ?: (ctx ?: @"—"), money]];
        if (!refText && [p[@"ref"] isKindOfClass:[NSString class]]) refText = p[@"ref"];
    }
    [titles addObject:@"Mức phạt với ô tô"];
    [sections addObject:fines];
    [footers addObject:refText ?: @""];

    // --- Bối cảnh ---
    NSMutableArray *noteRows = [NSMutableArray array];
    for (NSString *n in r.notes) [noteRows addObject:@[n, @""]];
    if (noteRows.count) {
        [titles addObject:@"Bối cảnh"];
        [sections addObject:noteRows];
        [footers addObject:@"Số liệu có thể thay đổi. App tự kiểm tra bản cập nhật tối đa 1 lần mỗi 7 ngày."];
    }

    // --- Nguồn số liệu ---
    [titles addObject:@"Số liệu đang dùng"];
    [sections addObject:@[
        @[@"Phiên bản", r.version ?: @"—"],
        @[@"Nguồn tệp", r.originLabel ?: @"—"],
        @[@"Phiên bản app", kAppVersion],
    ]];
    [footers addObject:r.disclaimer ?: @""];

    self.sections = sections;
    self.titles = titles;
    self.footers = footers;
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return self.titles[section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    NSString *f = self.footers[section];
    return f.length ? f : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray<NSString *> *pair = self.sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.text = pair[0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.text = pair.count > 1 ? pair[1] : @"";
    cell.detailTextLabel.textColor = KCColorGreen();
    cell.detailTextLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    cell.detailTextLabel.numberOfLines = 0;
    return cell;
}

@end
