#import "KCTripLogger.h"
#import "KCLog.h"

@interface KCTripLogger ()
@property (nonatomic, assign) BOOL recording;
@property (nonatomic, copy) NSString *currentPath;
@property (nonatomic, assign) NSUInteger rowCount;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, strong) NSDateFormatter *rowFormatter;
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, assign) CFAbsoluteTime lastRow;
@end

@implementation KCTripLogger

- (instancetype)init {
    if ((self = [super init])) {
        _minimumInterval = 0.5;
        _queue = dispatch_queue_create("com.khoangcachantoan.trip", DISPATCH_QUEUE_SERIAL);
        _rowFormatter = [[NSDateFormatter alloc] init];
        _rowFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _rowFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.S";
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (BOOL)start {
    if (self.recording) return YES;

    NSDateFormatter *nameFormatter = [[NSDateFormatter alloc] init];
    nameFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    nameFormatter.dateFormat = @"yyyyMMdd_HHmm";
    NSString *name = [NSString stringWithFormat:@"trip_%@.csv", [nameFormatter stringFromDate:[NSDate date]]];
    NSString *path = [[KCLog dataDirectory] stringByAppendingPathComponent:name];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        NSString *header = @"thoi_gian,toc_do_kmh,khoang_cach_m,nguong_m,trang_thai\n";
        if (![fm createFileAtPath:path contents:[header dataUsingEncoding:NSUTF8StringEncoding] attributes:nil]) {
            KCLogf(@"trip: khong tao duoc %@", path);
            return NO;
        }
    }
    self.handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!self.handle) {
        KCLogf(@"trip: khong mo duoc %@", path);
        return NO;
    }
    @try { [self.handle seekToEndOfFile]; } @catch (NSException *e) { self.handle = nil; return NO; }

    self.currentPath = path;
    self.rowCount = 0;
    self.recording = YES;
    KCLogf(@"trip: bat dau ghi %@", name);
    return YES;
}

- (void)stop {
    if (!self.recording) return;
    self.recording = NO;
    NSFileHandle *h = self.handle;
    self.handle = nil;
    NSString *path = self.currentPath;
    NSUInteger rows = self.rowCount;
    dispatch_async(self.queue, ^{
        @try { [h closeFile]; } @catch (NSException *e) { }
        KCLogf(@"trip: da dung, %lu dong trong %@", (unsigned long)rows, path.lastPathComponent);
    });
}

- (void)logSpeedKmh:(double)speedKmh
         speedValid:(BOOL)speedValid
           distance:(double)distanceMeters
      distanceValid:(BOOL)distanceValid
          threshold:(double)thresholdMeters
             status:(NSString *)status {
    if (!self.recording) return;
    CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
    if (self.lastRow > 0 && (now - self.lastRow) < self.minimumInterval) return;
    self.lastRow = now;

    NSString *line = [NSString stringWithFormat:@"%@,%@,%@,%@,%@\n",
                      [self.rowFormatter stringFromDate:[NSDate date]],
                      speedValid ? [NSString stringWithFormat:@"%.1f", speedKmh] : @"",
                      distanceValid ? [NSString stringWithFormat:@"%.1f", distanceMeters] : @"",
                      thresholdMeters > 0 ? [NSString stringWithFormat:@"%.1f", thresholdMeters] : @"",
                      status ?: @""];
    self.rowCount += 1;
    NSFileHandle *h = self.handle;
    dispatch_async(self.queue, ^{
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (data && h) {
            @try { [h writeData:data]; } @catch (NSException *e) { }
        }
    });
}

+ (NSArray<NSString *> *)existingTripFiles {
    NSString *dir = [KCLog dataDirectory];
    NSArray *all = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil];
    NSMutableArray *trips = [NSMutableArray array];
    for (NSString *f in all) {
        if ([f hasPrefix:@"trip_"] && [f hasSuffix:@".csv"]) [trips addObject:f];
    }
    return [trips sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [b compare:a];    // mới nhất trước
    }];
}

@end
