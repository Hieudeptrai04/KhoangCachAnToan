#import "KCSettings.h"
#import "KCCommon.h"
#import "KCLog.h"

static NSString *const kKeyCameraHeight = @"cameraHeightMeters";
static NSString *const kKeyFrontOffset = @"frontOffsetMeters";
static NSString *const kKeyCalibration = @"calibrationFactor";
static NSString *const kKeyPitchOffset = @"pitchOffsetRadians";
static NSString *const kKeyWidthCar = @"widthCar";
static NSString *const kKeyWidthTruck = @"widthTruck";
static NSString *const kKeyWidthBus = @"widthBus";
static NSString *const kKeyWidthMotorcycle = @"widthMotorcycle";
static NSString *const kKeyMaxInferenceFPS = @"maxInferenceFPS";
static NSString *const kKeyAdverseFactor = @"adverseFactor";
static NSString *const kKeyShowsGuides = @"showsGuides";
static NSString *const kKeyShowsFarRegion = @"showsFarRegion";
static NSString *const kKeyPreferTelephoto = @"preferTelephoto";
static NSString *const kKeyUse4K = @"use4K";
static NSString *const kKeyLogTripCSV = @"logTripCSV";
static NSString *const kKeyAlertBeep = @"alertBeep";
static NSString *const kKeyAlertHaptic = @"alertHaptic";
static NSString *const kKeyAlertSpeech = @"alertSpeech";

@interface KCSettings ()
@property (nonatomic, strong) NSMutableDictionary *store;
@property (nonatomic, assign) BOOL loading;
@end

@implementation KCSettings

+ (instancetype)shared {
    static KCSettings *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[KCSettings alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        [self load];
    }
    return self;
}

#pragma mark - Đọc / ghi plist

- (void)load {
    self.loading = YES;
    NSDictionary *onDisk = [NSDictionary dictionaryWithContentsOfFile:kKCPrefsPath];
    self.store = onDisk ? [onDisk mutableCopy] : [NSMutableDictionary dictionary];
    KCLogf(@"settings: doc %lu khoa tu %@", (unsigned long)self.store.count, kKCPrefsPath);

    _cameraHeightMeters = [self doubleFor:kKeyCameraHeight fallback:1.25];
    _frontOffsetMeters = [self doubleFor:kKeyFrontOffset fallback:1.5];
    _calibrationFactor = [self doubleFor:kKeyCalibration fallback:1.0];
    _pitchOffsetRadians = [self doubleFor:kKeyPitchOffset fallback:0.0];
    _widthCar = [self doubleFor:kKeyWidthCar fallback:1.80];
    _widthTruck = [self doubleFor:kKeyWidthTruck fallback:2.50];
    _widthBus = [self doubleFor:kKeyWidthBus fallback:2.55];
    _widthMotorcycle = [self doubleFor:kKeyWidthMotorcycle fallback:0.80];
    _maxInferenceFPS = [self doubleFor:kKeyMaxInferenceFPS fallback:15.0];
    _adverseFactor = [self doubleFor:kKeyAdverseFactor fallback:1.5];
    _showsGuides = [self boolFor:kKeyShowsGuides fallback:YES];
    _showsFarRegion = [self boolFor:kKeyShowsFarRegion fallback:NO];
    _preferTelephoto = [self boolFor:kKeyPreferTelephoto fallback:YES];
    _use4K = [self boolFor:kKeyUse4K fallback:NO];
    _logTripCSV = [self boolFor:kKeyLogTripCSV fallback:NO];
    _alertBeep = [self boolFor:kKeyAlertBeep fallback:YES];
    _alertHaptic = [self boolFor:kKeyAlertHaptic fallback:YES];
    _alertSpeech = [self boolFor:kKeyAlertSpeech fallback:YES];
    self.loading = NO;
}

- (double)doubleFor:(NSString *)key fallback:(double)fallback {
    id v = self.store[key];
    if ([v isKindOfClass:[NSNumber class]]) return [v doubleValue];
    return fallback;
}

- (BOOL)boolFor:(NSString *)key fallback:(BOOL)fallback {
    id v = self.store[key];
    if ([v isKindOfClass:[NSNumber class]]) return [v boolValue];
    return fallback;
}

- (void)set:(NSString *)key number:(double)value {
    self.store[key] = @(value);
    if (!self.loading) [self save];
}

- (void)set:(NSString *)key flag:(BOOL)value {
    self.store[key] = @(value);
    if (!self.loading) [self save];
}

- (void)save {
    NSString *dir = [kKCPrefsPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }
    if (![self.store writeToFile:kKCPrefsPath atomically:YES]) {
        KCLogf(@"settings: GHI THAT BAI vao %@", kKCPrefsPath);
    }
}

- (void)resetToDefaults {
    [self.store removeAllObjects];
    [self save];
    [self load];
    KCLogf(@"settings: da dat lai mac dinh");
}

#pragma mark - Thuộc tính

- (void)setCameraHeightMeters:(double)v { _cameraHeightMeters = v; [self set:kKeyCameraHeight number:v]; }
- (void)setFrontOffsetMeters:(double)v  { _frontOffsetMeters = v;  [self set:kKeyFrontOffset number:v]; }
- (void)setCalibrationFactor:(double)v  { _calibrationFactor = v;  [self set:kKeyCalibration number:v]; }
- (void)setPitchOffsetRadians:(double)v { _pitchOffsetRadians = v; [self set:kKeyPitchOffset number:v]; }
- (void)setWidthCar:(double)v           { _widthCar = v;           [self set:kKeyWidthCar number:v]; }
- (void)setWidthTruck:(double)v         { _widthTruck = v;         [self set:kKeyWidthTruck number:v]; }
- (void)setWidthBus:(double)v           { _widthBus = v;           [self set:kKeyWidthBus number:v]; }
- (void)setWidthMotorcycle:(double)v    { _widthMotorcycle = v;    [self set:kKeyWidthMotorcycle number:v]; }
- (void)setMaxInferenceFPS:(double)v    { _maxInferenceFPS = v;    [self set:kKeyMaxInferenceFPS number:v]; }
- (void)setAdverseFactor:(double)v      { _adverseFactor = v;      [self set:kKeyAdverseFactor number:v]; }
- (void)setShowsGuides:(BOOL)v          { _showsGuides = v;        [self set:kKeyShowsGuides flag:v]; }
- (void)setShowsFarRegion:(BOOL)v       { _showsFarRegion = v;     [self set:kKeyShowsFarRegion flag:v]; }
- (void)setPreferTelephoto:(BOOL)v      { _preferTelephoto = v;    [self set:kKeyPreferTelephoto flag:v]; }
- (void)setUse4K:(BOOL)v                { _use4K = v;              [self set:kKeyUse4K flag:v]; }
- (void)setLogTripCSV:(BOOL)v           { _logTripCSV = v;         [self set:kKeyLogTripCSV flag:v]; }
- (void)setAlertBeep:(BOOL)v            { _alertBeep = v;          [self set:kKeyAlertBeep flag:v]; }
- (void)setAlertHaptic:(BOOL)v          { _alertHaptic = v;        [self set:kKeyAlertHaptic flag:v]; }
- (void)setAlertSpeech:(BOOL)v          { _alertSpeech = v;        [self set:kKeyAlertSpeech flag:v]; }

- (double)vehicleWidthForLabel:(NSString *)label {
    NSString *l = label.lowercaseString;
    if ([l isEqualToString:@"truck"]) return self.widthTruck;
    if ([l isEqualToString:@"bus"]) return self.widthBus;
    if ([l hasPrefix:@"motor"]) return self.widthMotorcycle;
    return self.widthCar;
}

@end
