#import "KCMotion.h"
#import "KCLog.h"
#import <CoreMotion/CoreMotion.h>
#import <math.h>

@interface KCMotion ()
@property (nonatomic, strong) CMMotionManager *manager;
@property (nonatomic, strong) NSOperationQueue *queue;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) double rawPitchRadians;
@property (nonatomic, assign) double filteredPitch;
@property (nonatomic, assign) BOOL hasSample;
@property (nonatomic, assign) NSTimeInterval lastSampleTime;
@property (nonatomic, assign) NSUInteger sampleCount;
@end

@implementation KCMotion

- (instancetype)init {
    if ((self = [super init])) {
        _manager = [[CMMotionManager alloc] init];
        _manager.deviceMotionUpdateInterval = 1.0 / 30.0;
        _queue = [[NSOperationQueue alloc] init];
        _queue.maxConcurrentOperationCount = 1;
        _queue.name = @"com.khoangcachantoan.motion";
        _smoothingSeconds = 0.5;
    }
    return self;
}

- (BOOL)available {
    return self.manager.isDeviceMotionAvailable;
}

- (double)pitchRadians {
    return self.filteredPitch + self.pitchOffsetRadians;
}

- (void)start {
    if (self.running) return;
    if (!self.manager.isDeviceMotionAvailable) {
        KCLogf(@"motion: thiet bi khong co device motion");
        return;
    }
    self.running = YES;
    __weak typeof(self) weakSelf = self;
    [self.manager startDeviceMotionUpdatesToQueue:self.queue withHandler:^(CMDeviceMotion *motion, NSError *error) {
        if (error) { KCLogf(@"motion: loi %@", error); return; }
        if (!motion) return;
        [weakSelf consumeMotion:motion];
    }];
    KCLogf(@"motion: bat dau doc device motion (%.0f Hz)", 1.0 / self.manager.deviceMotionUpdateInterval);
}

- (void)stop {
    if (!self.running) return;
    [self.manager stopDeviceMotionUpdates];
    self.running = NO;
    KCLogf(@"motion: dung");
}

- (void)consumeMotion:(CMDeviceMotion *)motion {
    CMAcceleration g = motion.gravity;
    // Trục quang camera sau = −z của thiết bị; gravity là vector đơn vị hướng xuống.
    double s = -g.z;
    if (s > 1.0) s = 1.0;
    if (s < -1.0) s = -1.0;
    double raw = asin(s);
    self.rawPitchRadians = raw;

    NSTimeInterval now = motion.timestamp;
    double dt = (self.lastSampleTime > 0) ? (now - self.lastSampleTime) : (1.0 / 30.0);
    self.lastSampleTime = now;
    if (dt <= 0 || dt > 1.0) dt = 1.0 / 30.0;

    if (!self.hasSample) {
        self.filteredPitch = raw;
        self.hasSample = YES;
    } else {
        // Lọc thông thấp một cực, hằng số thời gian smoothingSeconds.
        double tau = MAX(self.smoothingSeconds, 0.01);
        double alpha = dt / (tau + dt);
        self.filteredPitch += alpha * (raw - self.filteredPitch);
    }

    self.sampleCount += 1;
    if (self.sampleCount % 300 == 1) {   // ~10 giây một dòng
        KCLogf(@"motion: gravity=(%.3f,%.3f,%.3f) pitch tho=%.2f° loc=%.2f° offset=%.2f° dung=%.2f°",
               g.x, g.y, g.z, raw * 180 / M_PI, self.filteredPitch * 180 / M_PI,
               self.pitchOffsetRadians * 180 / M_PI, self.pitchRadians * 180 / M_PI);
    }
}

- (double)levelNow {
    double offset = -self.filteredPitch;
    self.pitchOffsetRadians = offset;
    KCLogf(@"motion: can ngang -> offset = %.3f rad (%.2f°)", offset, offset * 180 / M_PI);
    return offset;
}

@end
