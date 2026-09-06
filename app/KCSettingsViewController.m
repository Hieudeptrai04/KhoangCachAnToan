#import "KCSettingsViewController.h"
#import "KCSettings.h"
#import "KCMotion.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <math.h>

typedef NS_ENUM(NSInteger, KCRowKind) {
    KCRowStepper,
    KCRowSwitch,
    KCRowButton,
    KCRowInfo,
};

@interface KCSettingsRow : NSObject
@property (nonatomic, assign) KCRowKind kind;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *unit;
@property (nonatomic, assign) double minValue, maxValue, step;
@property (nonatomic, assign) int decimals;
@property (nonatomic, copy) double (^getter)(void);
@property (nonatomic, copy) void (^setter)(double);
@property (nonatomic, copy) BOOL (^flagGetter)(void);
@property (nonatomic, copy) void (^flagSetter)(BOOL);
@property (nonatomic, copy) NSString * (^detailGetter)(void);
@property (nonatomic, copy) void (^action)(void);
@end

@implementation KCSettingsRow
@end

@interface KCSettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray<NSString *> *sectionTitles;
@property (nonatomic, strong) NSMutableArray<NSArray<KCSettingsRow *> *> *sections;
@end

@implementation KCSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;

    [self buildRows];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.backgroundColor = [UIColor blackColor];
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.rowHeight = 52;
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
    self.tableView.contentInset = UIEdgeInsetsMake(56, 0, 0, 0);
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }
- (BOOL)prefersStatusBarHidden { return YES; }

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)changed {
    if (self.onChange) self.onChange();
}

#pragma mark - Định nghĩa các hàng

- (KCSettingsRow *)stepper:(NSString *)title unit:(NSString *)unit
                       min:(double)mn max:(double)mx step:(double)st decimals:(int)dec
                    getter:(double (^)(void))getter setter:(void (^)(double))setter {
    KCSettingsRow *r = [[KCSettingsRow alloc] init];
    r.kind = KCRowStepper;
    r.title = title; r.unit = unit;
    r.minValue = mn; r.maxValue = mx; r.step = st; r.decimals = dec;
    r.getter = getter; r.setter = setter;
    return r;
}

- (KCSettingsRow *)toggle:(NSString *)title getter:(BOOL (^)(void))getter setter:(void (^)(BOOL))setter {
    KCSettingsRow *r = [[KCSettingsRow alloc] init];
    r.kind = KCRowSwitch;
    r.title = title;
    r.flagGetter = getter; r.flagSetter = setter;
    return r;
}

- (KCSettingsRow *)button:(NSString *)title detail:(NSString * (^)(void))detail action:(void (^)(void))action {
    KCSettingsRow *r = [[KCSettingsRow alloc] init];
    r.kind = KCRowButton;
    r.title = title; r.detailGetter = detail; r.action = action;
    return r;
}

- (void)buildRows {
    KCSettings *s = [KCSettings shared];
    __weak typeof(self) weakSelf = self;

    self.sectionTitles = [NSMutableArray array];
    self.sections = [NSMutableArray array];

    // --- Hiệu chỉnh ---
    [self.sectionTitles addObject:@"Hiệu chỉnh — đo bằng thước rồi nhập"];
    [self.sections addObject:@[
        [self stepper:@"Chiều cao ống kính so mặt đường" unit:@"m" min:0.5 max:2.5 step:0.01 decimals:2
               getter:^double{ return s.cameraHeightMeters; }
               setter:^(double v){ s.cameraHeightMeters = v; [weakSelf changed]; }],
        [self stepper:@"Điện thoại tới đầu xe" unit:@"m" min:0.0 max:4.0 step:0.05 decimals:2
               getter:^double{ return s.frontOffsetMeters; }
               setter:^(double v){ s.frontOffsetMeters = v; [weakSelf changed]; }],
        [self stepper:@"Hệ số chỉnh tay k" unit:@"" min:0.5 max:2.0 step:0.01 decimals:2
               getter:^double{ return s.calibrationFactor; }
               setter:^(double v){ s.calibrationFactor = v; [weakSelf changed]; }],
        [self button:@"Cân ngang (lưu góc đặt máy)"
              detail:^NSString *{
                  KCMotion *m = weakSelf.motion;
                  if (!m) return @"—";
                  return [NSString stringWithFormat:@"đang %@°, offset %@°",
                          KCFormatNumber(m.pitchRadians * 180 / M_PI, 1),
                          KCFormatNumber(m.pitchOffsetRadians * 180 / M_PI, 1)];
              }
              action:^{ [weakSelf levelNow]; }],
        [self button:@"Đặt k từ khoảng cách thật"
              detail:^NSString *{
                  double d = weakSelf.currentFusedDistance ? weakSelf.currentFusedDistance() : 0;
                  return d > 0 ? [NSString stringWithFormat:@"đang đo %@ m", KCFormatNumber(d, 1)] : @"chưa đo được";
              }
              action:^{ [weakSelf askRealDistance]; }],
    ]];

    // --- Bề rộng xe ---
    [self.sectionTitles addObject:@"Bề rộng thật của xe phía trước"];
    [self.sections addObject:@[
        [self stepper:@"Xe con" unit:@"m" min:1.2 max:2.4 step:0.01 decimals:2
               getter:^double{ return s.widthCar; } setter:^(double v){ s.widthCar = v; [weakSelf changed]; }],
        [self stepper:@"Xe tải" unit:@"m" min:1.8 max:3.0 step:0.01 decimals:2
               getter:^double{ return s.widthTruck; } setter:^(double v){ s.widthTruck = v; [weakSelf changed]; }],
        [self stepper:@"Xe buýt" unit:@"m" min:1.8 max:3.0 step:0.01 decimals:2
               getter:^double{ return s.widthBus; } setter:^(double v){ s.widthBus = v; [weakSelf changed]; }],
        [self stepper:@"Xe máy" unit:@"m" min:0.4 max:1.5 step:0.01 decimals:2
               getter:^double{ return s.widthMotorcycle; } setter:^(double v){ s.widthMotorcycle = v; [weakSelf changed]; }],
    ]];

    // --- Hiển thị và hiệu năng ---
    [self.sectionTitles addObject:@"Hiển thị và hiệu năng"];
    [self.sections addObject:@[
        [self toggle:@"Vạch chân trời và hình thang làn"
              getter:^BOOL{ return s.showsGuides; } setter:^(BOOL v){ s.showsGuides = v; [weakSelf changed]; }],
        [self toggle:@"Hiện vùng quan tâm (kênh xa)"
              getter:^BOOL{ return s.showsFarRegion; } setter:^(BOOL v){ s.showsFarRegion = v; [weakSelf changed]; }],
        [self stepper:@"Suy luận tối đa" unit:@"fps" min:5 max:20 step:1 decimals:0
               getter:^double{ return s.maxInferenceFPS; }
               setter:^(double v){ s.maxInferenceFPS = v; [weakSelf changed]; }],
        [self stepper:@"Hệ số thời tiết xấu" unit:@"×" min:1.0 max:2.5 step:0.1 decimals:1
               getter:^double{ return s.adverseFactor; }
               setter:^(double v){ s.adverseFactor = v; [weakSelf changed]; }],
    ]];

    // --- Đặt lại ---
    [self.sectionTitles addObject:@""];
    [self.sections addObject:@[
        [self button:@"Đặt lại toàn bộ về mặc định" detail:nil action:^{ [weakSelf confirmReset]; }],
    ]];
}

#pragma mark - Hành động

- (void)levelNow {
    KCMotion *m = self.motion;
    if (!m) return;
    double offset = [m levelNow];
    [KCSettings shared].pitchOffsetRadians = offset;
    [self changed];
    [self.tableView reloadData];
    [self toast:[NSString stringWithFormat:@"Đã lưu góc đặt máy: %@°", KCFormatNumber(offset * 180 / M_PI, 1)]];
}

- (void)askRealDistance {
    double fused = self.currentFusedDistance ? self.currentFusedDistance() : 0;
    if (fused <= 0) {
        [self toast:@"Chưa đo được xe phía trước. Hướng camera vào xe rồi thử lại."];
        return;
    }
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Đặt k từ khoảng cách thật"
                                                                message:[NSString stringWithFormat:@"App đang đo %@ m tính từ ống kính.\nNhập khoảng cách thật đo bằng thước, tính từ ĐẦU XE MÌNH tới đuôi xe trước.", KCFormatNumber(fused, 1)]
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.placeholder = @"ví dụ 15";
    }];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Lưu" style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *text = [ac.textFields.firstObject.text stringByReplacingOccurrencesOfString:@"," withString:@"."];
        double real = text.doubleValue;
        if (real <= 0) { [weakSelf toast:@"Số không hợp lệ."]; return; }
        KCSettings *s = [KCSettings shared];
        // Hiển thị = k · fused − d_front  ⇒  k = (thật + d_front) / fused
        double k = (real + s.frontOffsetMeters) / fused;
        if (k < 0.5 || k > 2.0) {
            [weakSelf toast:[NSString stringWithFormat:@"k = %@ nằm ngoài dải hợp lý (0,5–2,0). Kiểm tra lại chiều cao camera và cân ngang trước.", KCFormatNumber(k, 2)]];
            return;
        }
        s.calibrationFactor = k;
        KCLogf(@"settings: dat k = %.3f tu khoang cach that %.2f m (fused %.2f, d_front %.2f)", k, real, fused, s.frontOffsetMeters);
        [weakSelf changed];
        [weakSelf.tableView reloadData];
        [weakSelf toast:[NSString stringWithFormat:@"Đã đặt k = %@", KCFormatNumber(k, 2)]];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmReset {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Đặt lại mặc định"
                                                               message:@"Xoá toàn bộ hiệu chỉnh và cài đặt?"
                                                        preferredStyle:UIAlertControllerStyleAlert];
    __weak typeof(self) weakSelf = self;
    [ac addAction:[UIAlertAction actionWithTitle:@"Đặt lại" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        [[KCSettings shared] resetToDefaults];
        KCMotion *m = weakSelf.motion;
        if (m) m.pitchOffsetRadians = [KCSettings shared].pitchOffsetRadians;
        [weakSelf changed];
        [weakSelf.tableView reloadData];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)toast:(NSString *)message {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Bảng

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.sections[section].count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *t = self.sectionTitles[section];
    return t.length ? t : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    KCSettingsRow *row = self.sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.11 alpha:1];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.textLabel.numberOfLines = 2;
    cell.detailTextLabel.textColor = [UIColor colorWithWhite:0.62 alpha:1];
    cell.detailTextLabel.font = [UIFont systemFontOfSize:13];
    cell.textLabel.text = row.title;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (row.kind == KCRowStepper) {
        double value = row.getter ? row.getter() : 0;
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", KCFormatNumber(value, row.decimals), row.unit ?: @""];
        UIStepper *st = [[UIStepper alloc] init];
        st.minimumValue = row.minValue;
        st.maximumValue = row.maxValue;
        st.stepValue = row.step;
        st.value = value;
        st.tintColor = KCColorGreen();
        st.tag = indexPath.section * 1000 + indexPath.row;
        [st addTarget:self action:@selector(stepperChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = st;
    } else if (row.kind == KCRowSwitch) {
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = row.flagGetter ? row.flagGetter() : NO;
        sw.onTintColor = KCColorGreen();
        sw.tag = indexPath.section * 1000 + indexPath.row;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if (row.kind == KCRowButton) {
        cell.textLabel.textColor = KCColorGreen();
        cell.detailTextLabel.text = row.detailGetter ? row.detailGetter() : nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    KCSettingsRow *row = self.sections[indexPath.section][indexPath.row];
    if (row.kind == KCRowButton && row.action) row.action();
}

- (KCSettingsRow *)rowForTag:(NSInteger)tag {
    NSInteger section = tag / 1000, index = tag % 1000;
    if (section < 0 || section >= (NSInteger)self.sections.count) return nil;
    NSArray<KCSettingsRow *> *rows = self.sections[section];
    if (index < 0 || index >= (NSInteger)rows.count) return nil;
    return rows[index];
}

- (void)stepperChanged:(UIStepper *)sender {
    KCSettingsRow *row = [self rowForTag:sender.tag];
    if (!row.setter) return;
    row.setter(sender.value);
    NSIndexPath *ip = [NSIndexPath indexPathForRow:(sender.tag % 1000) inSection:(sender.tag / 1000)];
    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ %@", KCFormatNumber(sender.value, row.decimals), row.unit ?: @""];
}

- (void)switchChanged:(UISwitch *)sender {
    KCSettingsRow *row = [self rowForTag:sender.tag];
    if (row.flagSetter) row.flagSetter(sender.isOn);
}

@end
