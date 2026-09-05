#import "KCLog.h"
#import "KCCommon.h"

static const unsigned long long kKCLogMaxBytes = 1024 * 1024;

@interface KCLog ()
@property (nonatomic, strong) dispatch_queue_t queue;
@property (nonatomic, strong) NSFileHandle *handle;
@property (nonatomic, strong) NSDateFormatter *formatter;
@property (nonatomic, copy) NSString *path;
@end

@implementation KCLog

+ (instancetype)shared {
    static KCLog *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[KCLog alloc] init]; });
    return instance;
}

+ (NSString *)dataDirectory {
    NSString *dir = kKCDataDirectory;
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        NSError *err = nil;
        if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:&err]) {
            NSLog(@"[KC] cannot create %@: %@ -> fallback NSTemporaryDirectory", dir, err);
            dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"KhoangCachAnToan"];
            [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
        }
    }
    return dir;
}

- (instancetype)init {
    if ((self = [super init])) {
        _queue = dispatch_queue_create("com.khoangcachantoan.log", DISPATCH_QUEUE_SERIAL);
        _formatter = [[NSDateFormatter alloc] init];
        _formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        _formatter.dateFormat = @"yyyy-MM-dd HH:mm:ss.SSS";
        _path = [[KCLog dataDirectory] stringByAppendingPathComponent:@"log.txt"];
        [self openHandle];
    }
    return self;
}

- (void)openHandle {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.path]) {
        [fm createFileAtPath:self.path contents:nil attributes:nil];
    }
    self.handle = [NSFileHandle fileHandleForWritingAtPath:self.path];
    @try { [self.handle seekToEndOfFile]; } @catch (NSException *e) { self.handle = nil; }
}

- (void)rotateIfNeeded {
    if (!self.handle) return;
    unsigned long long size = 0;
    @try { size = [self.handle offsetInFile]; } @catch (NSException *e) { return; }
    if (size < kKCLogMaxBytes) return;
    [self.handle closeFile];
    self.handle = nil;
    NSString *old = [self.path stringByAppendingString:@".1"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm removeItemAtPath:old error:nil];
    [fm moveItemAtPath:self.path toPath:old error:nil];
    [self openHandle];
}

- (void)write:(NSString *)line {
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [self.formatter stringFromDate:[NSDate date]], line];
    NSLog(@"[KC] %@", line);
    dispatch_async(self.queue, ^{
        [self rotateIfNeeded];
        NSData *data = [stamped dataUsingEncoding:NSUTF8StringEncoding];
        if (data && self.handle) {
            @try { [self.handle writeData:data]; } @catch (NSException *e) { }
        }
    });
}

@end

void KCLogf(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *s = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [[KCLog shared] write:s];
}
