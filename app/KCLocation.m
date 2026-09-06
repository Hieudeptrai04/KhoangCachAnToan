#import "KCLocation.h"
#import "KCLog.h"
#import <CoreLocation/CoreLocation.h>

/// Dưới mức này coi như xe đứng yên (FR-2).
static const double kKCMovingThresholdKmh = 5.0;
/// Hằng số thời gian làm mượt tốc độ.
static const double kKCSpeedSmoothingSeconds = 1.0;

@interface KCLocation () <CLLocationManagerDelegate>
@property (nonatomic, strong) CLLocationManager *manager;
@property (nonatomic, assign) BOOL authorized;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) double speedKmh;
@property (nonatomic, assign) BOOL speedValid;
@property (nonatomic, assign) double horizontalAccuracy;
@property (nonatomic, assign) BOOL hasSample;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;
@property (nonatomic, assign) NSUInteger sampleCount;
@end

@implementation KCLocation

- (instancetype)init {
    if ((self = [super init])) {
        _manager = [[CLLocationManager alloc] init];
        _manager.delegate = self;
        _manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation;
        _manager.activityType = CLActivityTypeAutomotiveNavigation;
        _manager.pausesLocationUpdatesAutomatically = NO;
        _manager.distanceFilter = kCLDistanceFilterNone;
        _horizontalAccuracy = -1;
    }
    return self;
}

- (BOOL)moving {
    return self.speedValid && self.speedKmh >= kKCMovingThresholdKmh;
}

- (void)start {
    if (self.running) return;
    CLAuthorizationStatus st = self.manager.authorizationStatus;
    KCLogf(@"gps: authorization status=%d, servicesEnabled=%d", (int)st, [CLLocationManager locationServicesEnabled]);
    if (st == kCLAuthorizationStatusNotDetermined) {
        [self.manager requestWhenInUseAuthorization];
    }
    self.authorized = (st == kCLAuthorizationStatusAuthorizedWhenInUse || st == kCLAuthorizationStatusAuthorizedAlways);
    [self.manager startUpdatingLocation];
    self.running = YES;
    KCLogf(@"gps: bat dau cap nhat vi tri");
}

- (void)stop {
    if (!self.running) return;
    [self.manager stopUpdatingLocation];
    self.running = NO;
    self.speedValid = NO;
    KCLogf(@"gps: dung");
}

#pragma mark - CLLocationManagerDelegate

- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
    CLAuthorizationStatus st = manager.authorizationStatus;
    self.authorized = (st == kCLAuthorizationStatusAuthorizedWhenInUse || st == kCLAuthorizationStatusAuthorizedAlways);
    KCLogf(@"gps: quyen doi -> %d (duoc phep=%d)", (int)st, self.authorized);
    if (self.authorized && self.running) [manager startUpdatingLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray<CLLocation *> *)locations {
    CLLocation *loc = locations.lastObject;
    if (!loc) return;
    self.horizontalAccuracy = loc.horizontalAccuracy;

    double raw = loc.speed;      // m/s, âm nghĩa là không hợp lệ
    if (raw < 0) {
        self.speedValid = NO;
        return;
    }
    double kmh = raw * 3.6;

    NSTimeInterval now = [loc.timestamp timeIntervalSince1970];
    double dt = (self.lastSampleTime > 0) ? (now - self.lastSampleTime) : 1.0;
    self.lastSampleTime = now;
    if (dt <= 0 || dt > 5.0) dt = 1.0;

    if (!self.hasSample) {
        self.speedKmh = kmh;
        self.hasSample = YES;
    } else {
        double alpha = dt / (kKCSpeedSmoothingSeconds + dt);
        self.speedKmh = self.speedKmh + alpha * (kmh - self.speedKmh);
    }
    self.speedValid = YES;

    self.sampleCount += 1;
    if (self.sampleCount % 30 == 1) {
        KCLogf(@"gps: %.1f km/h (tho %.1f), sai so ngang %.0f m", self.speedKmh, kmh, loc.horizontalAccuracy);
    }
}

- (void)locationManager:(CLLocationManager *)manager didFailWithError:(NSError *)error {
    KCLogf(@"gps: loi %@", error.localizedDescription);
    if (error.code == kCLErrorDenied) {
        self.authorized = NO;
        self.speedValid = NO;
    }
}

@end
