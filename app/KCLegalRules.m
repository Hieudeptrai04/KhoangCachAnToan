#import "KCLegalRules.h"
#import "KCCommon.h"
#import "KCLog.h"

static NSString *const kKCLegalURL = @"https://hieudeptrai04.github.io/KhoangCachAnToan/legal.json";
static NSString *const kKCLastCheckKey = @"legalLastCheck";
static const NSTimeInterval kKCUpdateInterval = 7 * 24 * 3600;
/// Độ trễ đổi bracket: phải vượt mốc 2 km/h và giữ 1 giây.
static const double kKCHysteresisKmh = 2.0;
static const NSTimeInterval kKCHysteresisSeconds = 1.0;

@interface KCLegalRules ()
@property (nonatomic, copy) NSString *version;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, copy) NSString *disclaimer;
@property (nonatomic, copy) NSString *originLabel;
@property (nonatomic, copy) NSArray<NSDictionary *> *brackets;
@property (nonatomic, copy) NSArray<NSDictionary *> *penalties;
@property (nonatomic, copy) NSArray<NSString *> *notes;
@property (nonatomic, assign) double legalFromKmh;
@property (nonatomic, assign) double advisorySeconds;
@property (nonatomic, assign) double adverseFactorDefault;

@property (nonatomic, assign) NSInteger currentIndex;      // -1 = khuyến nghị, 0..n-1 = bracket
@property (nonatomic, assign) NSInteger pendingIndex;
@property (nonatomic, assign) NSTimeInterval pendingSince;
@property (nonatomic, assign) BOOL updating;
@end

@implementation KCLegalRules

+ (instancetype)shared {
    static KCLegalRules *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[KCLegalRules alloc] init];
        [instance load];
    });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _currentIndex = NSIntegerMin;
        _pendingIndex = NSIntegerMin;
    }
    return self;
}

#pragma mark - Nạp

- (NSString *)downloadedPath {
    return [[KCLog dataDirectory] stringByAppendingPathComponent:@"legal.json"];
}

- (void)load {
    NSDictionary *bundled = [self readJSONAtPath:[[NSBundle mainBundle] pathForResource:@"legal" ofType:@"json"]];
    if (!bundled) {
        KCLogf(@"legal: KHONG doc duoc legal.json trong bundle");
        return;
    }
    NSDictionary *chosen = bundled;
    NSString *origin = @"trong app";

    NSDictionary *downloaded = [self readJSONAtPath:[self downloadedPath]];
    if (downloaded) {
        NSString *bv = bundled[@"version"], *dv = downloaded[@"version"];
        if ([dv isKindOfClass:[NSString class]] && [bv isKindOfClass:[NSString class]] &&
            [dv compare:bv options:NSNumericSearch] == NSOrderedDescending) {
            chosen = downloaded;
            origin = @"tải về";
        }
    }
    [self applyDictionary:chosen origin:origin];
    KCLogf(@"legal: dung ban %@ (%@), %lu bracket, tu %@",
           self.version, origin, (unsigned long)self.brackets.count, self.source);
}

/// Đọc và XÁC THỰC. Trả nil nếu thiếu trường bắt buộc — không bao giờ nhận bản hỏng.
- (NSDictionary *)readJSONAtPath:(NSString *)path {
    if (!path.length) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) return nil;
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&err];
    if (![obj isKindOfClass:[NSDictionary class]]) {
        KCLogf(@"legal: %@ khong phai JSON hop le: %@", path.lastPathComponent, err);
        return nil;
    }
    NSDictionary *d = obj;
    if (![d[@"version"] isKindOfClass:[NSString class]]) return nil;
    NSArray *br = d[@"brackets"];
    if (![br isKindOfClass:[NSArray class]] || br.count == 0) return nil;
    for (id item in br) {
        if (![item isKindOfClass:[NSDictionary class]]) return nil;
        if (![item[@"v_max"] isKindOfClass:[NSNumber class]]) return nil;
        if (![item[@"min_m"] isKindOfClass:[NSNumber class]]) return nil;
    }
    return d;
}

- (void)applyDictionary:(NSDictionary *)d origin:(NSString *)origin {
    self.version = d[@"version"];
    self.source = [d[@"source"] isKindOfClass:[NSString class]] ? d[@"source"] : @"";
    self.disclaimer = [d[@"disclaimer"] isKindOfClass:[NSString class]] ? d[@"disclaimer"] : @"";
    self.originLabel = origin;

    // Sắp xếp theo v_max tăng dần để tra "bracket đầu tiên có v ≤ v_max".
    NSArray *br = [d[@"brackets"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"v_max"] compare:b[@"v_max"]];
    }];
    self.brackets = br;
    self.penalties = [d[@"penalties"] isKindOfClass:[NSArray class]] ? d[@"penalties"] : @[];
    self.notes = [d[@"notes"] isKindOfClass:[NSArray class]] ? d[@"notes"] : @[];

    NSNumber *from = d[@"legal_from_kmh"];
    self.legalFromKmh = [from isKindOfClass:[NSNumber class]] ? from.doubleValue : 60.0;

    NSDictionary *below = d[@"below_legal"];
    NSNumber *secs = [below isKindOfClass:[NSDictionary class]] ? below[@"advisory_seconds"] : nil;
    self.advisorySeconds = [secs isKindOfClass:[NSNumber class]] ? secs.doubleValue : 2.0;

    NSNumber *adv = d[@"adverse_factor_default"];
    self.adverseFactorDefault = [adv isKindOfClass:[NSNumber class]] ? adv.doubleValue : 1.5;

    [self resetHysteresis];
}

#pragma mark - Tra ngưỡng

- (double)vMaxAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.brackets.count) return 0;
    return [self.brackets[i][@"v_max"] doubleValue];
}

- (double)minMetersAtIndex:(NSInteger)i {
    if (i < 0 || i >= (NSInteger)self.brackets.count) return 0;
    return [self.brackets[i][@"min_m"] doubleValue];
}

/// -1 = dưới ngưỡng luật (khuyến nghị); ngược lại là chỉ số bracket đầu tiên có v ≤ v_max.
/// Vượt mốc cao nhất thì trả về bracket cuối (kèm cờ overSpeed ở hàm gọi).
- (NSInteger)rawIndexForSpeed:(double)kmh {
    if (kmh < self.legalFromKmh) return -1;
    for (NSInteger i = 0; i < (NSInteger)self.brackets.count; i++) {
        if (kmh <= [self vMaxAtIndex:i]) return i;
    }
    return (NSInteger)self.brackets.count - 1;
}

- (KCThreshold)thresholdForIndex:(NSInteger)index speed:(double)kmh adverseFactor:(double)factor {
    KCThreshold t;
    memset(&t, 0, sizeof(t));
    if (factor < 1.0) factor = 1.0;

    if (index < 0) {
        t.kind = KCThresholdAdvisory;
        t.baseMeters = (kmh / 3.6) * self.advisorySeconds;
    } else {
        t.kind = KCThresholdLegal;
        t.baseMeters = [self minMetersAtIndex:index];
        t.overSpeed = (kmh > [self vMaxAtIndex:(NSInteger)self.brackets.count - 1]);
    }
    t.adverseApplied = (factor > 1.0);
    t.meters = t.baseMeters * factor;
    return t;
}

- (KCThreshold)rawThresholdForSpeedKmh:(double)kmh adverseFactor:(double)factor {
    if (self.brackets.count == 0) {
        KCThreshold none;
        memset(&none, 0, sizeof(none));
        return none;
    }
    return [self thresholdForIndex:[self rawIndexForSpeed:kmh] speed:kmh adverseFactor:factor];
}

/// Mốc tốc độ ngăn giữa hai chỉ số: dùng v_max của chỉ số NHỎ HƠN,
/// riêng ranh giới giữa "khuyến nghị" (-1) và bracket đầu là legal_from_kmh.
- (double)boundaryBetween:(NSInteger)a and:(NSInteger)b {
    NSInteger lower = MIN(a, b);
    if (lower < 0) return self.legalFromKmh;
    return [self vMaxAtIndex:lower];
}

- (KCThreshold)thresholdForSpeedKmh:(double)kmh adverseFactor:(double)factor timestamp:(NSTimeInterval)timestamp {
    if (self.brackets.count == 0) {
        KCThreshold none;
        memset(&none, 0, sizeof(none));
        return none;
    }
    NSInteger raw = [self rawIndexForSpeed:kmh];

    if (self.currentIndex == NSIntegerMin) {          // lần đầu: nhận ngay
        self.currentIndex = raw;
        self.pendingIndex = NSIntegerMin;
    } else if (raw == self.currentIndex) {
        self.pendingIndex = NSIntegerMin;
    } else {
        double boundary = [self boundaryBetween:self.currentIndex and:raw];
        BOOL pastMargin = (raw > self.currentIndex) ? (kmh >= boundary + kKCHysteresisKmh)
                                                    : (kmh <= boundary - kKCHysteresisKmh);
        if (!pastMargin) {
            self.pendingIndex = NSIntegerMin;
        } else if (raw != self.pendingIndex) {
            self.pendingIndex = raw;
            self.pendingSince = timestamp;
        } else if (timestamp - self.pendingSince >= kKCHysteresisSeconds) {
            KCLogf(@"legal: doi bracket %ld -> %ld tai %.0f km/h", (long)self.currentIndex, (long)raw, kmh);
            self.currentIndex = raw;
            self.pendingIndex = NSIntegerMin;
        }
    }
    return [self thresholdForIndex:self.currentIndex speed:kmh adverseFactor:factor];
}

- (void)resetHysteresis {
    self.currentIndex = NSIntegerMin;
    self.pendingIndex = NSIntegerMin;
    self.pendingSince = 0;
}

#pragma mark - Cập nhật từ máy chủ

- (void)updateFromServerIfDue {
    if (self.updating) return;
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kKCPrefsPath];
    NSNumber *last = prefs[kKCLastCheckKey];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if ([last isKindOfClass:[NSNumber class]] && (now - last.doubleValue) < kKCUpdateInterval) {
        return;
    }
    self.updating = YES;

    // Ghi mốc thời gian TRƯỚC khi tải: hỏng mạng cũng không thử lại liên tục.
    NSMutableDictionary *m = prefs ? [prefs mutableCopy] : [NSMutableDictionary dictionary];
    m[kKCLastCheckKey] = @(now);
    [m writeToFile:kKCPrefsPath atomically:YES];

    NSURL *url = [NSURL URLWithString:kKCLegalURL];
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    cfg.timeoutIntervalForRequest = 15;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:cfg];
    KCLogf(@"legal: kiem tra ban moi tai %@", kKCLegalURL);
    __weak typeof(self) weakSelf = self;
    [[session dataTaskWithURL:url completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.updating = NO;
        if (error || !data.length) {
            KCLogf(@"legal: tai that bai: %@", error.localizedDescription ?: @"khong co du lieu");
            return;
        }
        NSError *jerr = nil;
        id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jerr];
        if (![obj isKindOfClass:[NSDictionary class]]) {
            KCLogf(@"legal: ban tai ve khong phai JSON: %@", jerr.localizedDescription);
            return;
        }
        NSString *newVersion = ((NSDictionary *)obj)[@"version"];
        if (![newVersion isKindOfClass:[NSString class]]) {
            KCLogf(@"legal: ban tai ve thieu truong version -> giu ban cu");
            return;
        }
        if ([newVersion compare:strongSelf.version options:NSNumericSearch] != NSOrderedDescending) {
            KCLogf(@"legal: ban tren mang (%@) khong moi hon ban dang dung (%@)", newVersion, strongSelf.version);
            return;
        }
        // Ghi ra file tạm rồi xác thực lại qua đúng đường đọc, chỉ đổi tên khi chắc chắn hợp lệ.
        NSString *dest = [strongSelf downloadedPath];
        NSString *tmp = [dest stringByAppendingPathExtension:@"tmp"];
        if (![data writeToFile:tmp atomically:YES]) {
            KCLogf(@"legal: khong ghi duoc file tam");
            return;
        }
        if (![strongSelf readJSONAtPath:tmp]) {
            KCLogf(@"legal: ban tai ve khong qua duoc xac thuc -> giu ban cu");
            [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
            return;
        }
        [[NSFileManager defaultManager] removeItemAtPath:dest error:nil];
        NSError *mvErr = nil;
        if (![[NSFileManager defaultManager] moveItemAtPath:tmp toPath:dest error:&mvErr]) {
            KCLogf(@"legal: khong doi ten duoc file tai ve: %@", mvErr);
            return;
        }
        KCLogf(@"legal: da tai ban moi %@ -> ap dung o lan mo app sau", newVersion);
    }] resume];
}

#pragma mark - Tự kiểm tra (mục 10.4)

- (NSInteger)runSelfTest {
    NSInteger failed = 0;
    // Bảng 3.1: v = 60 -> 35; 60<v≤80 -> 55; 80<v≤100 -> 70; 100<v≤120 -> 100; v<60 -> 2 giây.
    NSArray *cases = @[
        @[@0.0,   @0.0],
        @[@30.0,  @(30.0 / 3.6 * 2.0)],
        @[@59.0,  @(59.0 / 3.6 * 2.0)],
        @[@60.0,  @35.0],
        @[@61.0,  @55.0],
        @[@80.0,  @55.0],
        @[@81.0,  @70.0],
        @[@100.0, @70.0],
        @[@101.0, @100.0],
        @[@120.0, @100.0],
        @[@130.0, @100.0],
    ];
    for (NSArray *c in cases) {
        double v = [c[0] doubleValue], expect = [c[1] doubleValue];
        KCThreshold t = [self rawThresholdForSpeedKmh:v adverseFactor:1.0];
        BOOL ok = fabs(t.meters - expect) < 0.05;
        if (!ok) failed += 1;
        KCLogf(@"selftest: v=%.0f -> %.1f m (mong doi %.1f) %@%@",
               v, t.meters, expect, ok ? @"PASS" : @"FAIL",
               t.overSpeed ? @" [vuot toc do]" : @"");
    }

    // Hệ số thời tiết xấu nhân đúng.
    KCThreshold adv = [self rawThresholdForSpeedKmh:81 adverseFactor:1.5];
    BOOL advOK = fabs(adv.meters - 105.0) < 0.05 && adv.adverseApplied;
    if (!advOK) failed += 1;
    KCLogf(@"selftest: v=81 x1.5 -> %.1f m (mong doi 105.0) %@", adv.meters, advOK ? @"PASS" : @"FAIL");

    // Vượt 120 km/h phải bật cờ vượt tốc độ.
    KCThreshold over = [self rawThresholdForSpeedKmh:130 adverseFactor:1.0];
    if (!over.overSpeed) failed += 1;
    KCLogf(@"selftest: v=130 co bao vuot toc do: %@", over.overSpeed ? @"PASS" : @"FAIL");

    // Độ trễ: 81 -> 79 không được đổi ngay (chưa vượt biên 2 km/h), 77 giữ 1 giây thì đổi.
    [self resetHysteresis];
    NSTimeInterval t0 = 1000.0;
    KCThreshold h1 = [self thresholdForSpeedKmh:81 adverseFactor:1.0 timestamp:t0];
    KCThreshold h2 = [self thresholdForSpeedKmh:79 adverseFactor:1.0 timestamp:t0 + 0.2];
    KCThreshold h3 = [self thresholdForSpeedKmh:77 adverseFactor:1.0 timestamp:t0 + 0.4];
    KCThreshold h4 = [self thresholdForSpeedKmh:77 adverseFactor:1.0 timestamp:t0 + 2.0];
    BOOL hOK = fabs(h1.meters - 70.0) < 0.05 &&
               fabs(h2.meters - 70.0) < 0.05 &&
               fabs(h3.meters - 70.0) < 0.05 &&
               fabs(h4.meters - 55.0) < 0.05;
    if (!hOK) failed += 1;
    KCLogf(@"selftest: do tre 81->79->77 = %.0f/%.0f/%.0f/%.0f m (mong doi 70/70/70/55) %@",
           h1.meters, h2.meters, h3.meters, h4.meters, hOK ? @"PASS" : @"FAIL");
    [self resetHysteresis];

    // JSON hỏng thì không được nhận.
    NSString *bad = [[KCLog dataDirectory] stringByAppendingPathComponent:@"legal_bad_test.json"];
    [@"{ khong phai json" writeToFile:bad atomically:YES encoding:NSUTF8StringEncoding error:nil];
    BOOL rejected = ([self readJSONAtPath:bad] == nil);
    if (!rejected) failed += 1;
    KCLogf(@"selftest: JSON hong bi tu choi: %@", rejected ? @"PASS" : @"FAIL");
    [[NSFileManager defaultManager] removeItemAtPath:bad error:nil];

    KCLogf(@"selftest: tong ket %ld phep thu hong", (long)failed);
    return failed;
}

@end
