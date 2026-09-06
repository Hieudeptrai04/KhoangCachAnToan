#import "KCRangeEstimator.h"
#import "KCSettings.h"
#import "KCLog.h"
#import <math.h>

/// Sai số vị trí cạnh khung bao, tính bằng pixel Ở TỈ LỆ 416 (đầu vào model),
/// sẽ được quy về pixel của buffer theo hệ số thu nhỏ của từng kênh.
static const double kKCSigmaPixelsAt416 = 2.0;
/// Góc nhìn xuống tối thiểu để công thức mặt đường còn có nghĩa.
static const double kKCMinDepressionRad = 0.5 * M_PI / 180.0;
/// Nhiễu quá trình của Kalman: phương sai gia tốc tương đối giữa hai xe (m²/s⁴).
static const double kKCProcessNoise = 4.0;
/// Ngưỡng lệch giữa hai phép đo và thời gian phải kéo dài để báo "cần hiệu chỉnh".
static const double kKCMismatchRatio = 0.30;
static const double kKCMismatchSeconds = 1.0;

@interface KCRangeEstimator ()
// Kalman 1 chiều, mô hình vận tốc không đổi: trạng thái [khoảng cách, vận tốc].
@property (nonatomic, assign) BOOL hasState;
@property (nonatomic, assign) double x0, x1;         // d, v
@property (nonatomic, assign) double p00, p01, p10, p11;
@property (nonatomic, assign) NSTimeInterval lastUpdate;
@property (nonatomic, assign) double closingSpeedMps;
// Lọc trung vị 5 mẫu trước khi đưa vào Kalman.
@property (nonatomic, strong) NSMutableArray<NSNumber *> *window;
// Theo dõi mức lệch giữa hai phép đo.
@property (nonatomic, assign) NSTimeInterval mismatchSince;
@property (nonatomic, assign) BOOL needsCalibration;
@property (nonatomic, assign) NSUInteger logCounter;
@end

@implementation KCRangeEstimator

- (instancetype)init {
    if ((self = [super init])) {
        _window = [NSMutableArray arrayWithCapacity:5];
    }
    return self;
}

- (void)reset {
    self.hasState = NO;
    self.lastUpdate = 0;
    self.closingSpeedMps = 0;
    [self.window removeAllObjects];
    self.mismatchSince = 0;
    self.needsCalibration = NO;
}

- (double)horizonRowForIntrinsics:(KCIntrinsics)intr {
    return intr.cy - intr.fy * tan(self.pitchRadians);
}

#pragma mark - Ước lượng

- (KCRangeResult)estimateForDetection:(KCDetection *)detection
                           intrinsics:(KCIntrinsics)intr
                        farRegionSize:(CGFloat)farRegionWidthFraction
                            timestamp:(NSTimeInterval)timestamp {
    KCRangeResult r;
    memset(&r, 0, sizeof(r));

    if (!detection || intr.width <= 0 || intr.height <= 0 || intr.fx <= 0 || intr.fy <= 0) return r;

    KCSettings *s = [KCSettings shared];
    double bufferW = intr.width;
    double bufferH = intr.height;
    double realWidth = [s vehicleWidthForLabel:detection.label];
    double h = s.cameraHeightMeters;

    // (1) Theo bề rộng xe: D_w = fx · W / w_px
    double wpx = detection.nrect.size.width * bufferW;
    double hpx = detection.nrect.size.height * bufferH;
    double Dw = 0;
    BOOL widthValid = NO;
    if (wpx > 1.0 && hpx > 1.0) {
        double aspect = wpx / hpx;
        // Xe lệch góc làm khung bao rộng ra; ngoài dải này thì bề rộng không đáng tin.
        double lo = 1.0, hi = 2.2;
        NSString *l = detection.label.lowercaseString;
        if ([l isEqualToString:@"truck"] || [l isEqualToString:@"bus"]) { lo = 0.8; hi = 2.6; }
        else if ([l hasPrefix:@"motor"]) { lo = 0.35; hi = 1.6; }
        if (aspect >= lo && aspect <= hi) {
            Dw = intr.fx * realWidth / wpx;
            widthValid = (Dw > 0.5 && Dw < 400.0);
        }
    }

    // (2) Theo mặt đường: α = atan((y_b − cy)/fy); D_g = h / tan(α + θ)
    double yb = CGRectGetMaxY(detection.nrect) * bufferH;
    double alpha = atan((yb - intr.cy) / intr.fy);
    double depression = alpha + self.pitchRadians;
    double Dg = 0;
    BOOL groundValid = NO;
    if (depression > kKCMinDepressionRad && h > 0.1) {
        Dg = h / tan(depression);
        groundValid = (Dg > 0.5 && Dg < 400.0);
    }

    if (!widthValid && !groundValid) {
        r.valid = NO;
        r.needsCalibration = self.needsCalibration;
        return r;
    }

    // (3) Hợp nhất theo nghịch phương sai.
    // σ_px quy từ tỉ lệ 416 về pixel buffer theo hệ số thu nhỏ của kênh đang dùng.
    double channelWidthPx = detection.fromFarChannel ? (farRegionWidthFraction * bufferW) : bufferW;
    double sigmaPx = kKCSigmaPixelsAt416 * (channelWidthPx / 416.0);
    if (sigmaPx < 0.5) sigmaPx = 0.5;

    double sigmaW = widthValid ? (Dw * Dw * sigmaPx / (intr.fx * realWidth)) : 0;
    double sigmaG = groundValid ? (Dg * Dg * sigmaPx / (intr.fy * h)) : 0;

    double fused, sigma;
    if (widthValid && groundValid) {
        double ww = 1.0 / MAX(sigmaW * sigmaW, 1e-9);
        double wg = 1.0 / MAX(sigmaG * sigmaG, 1e-9);
        fused = (Dw * ww + Dg * wg) / (ww + wg);
        sigma = sqrt(1.0 / (ww + wg));

        double rel = fabs(Dw - Dg) / MAX(Dw, 1e-6);
        if (rel > kKCMismatchRatio) {
            if (self.mismatchSince == 0) self.mismatchSince = timestamp;
            else if (timestamp - self.mismatchSince > kKCMismatchSeconds) self.needsCalibration = YES;
        } else {
            self.mismatchSince = 0;
            self.needsCalibration = NO;
        }
    } else if (widthValid) {
        fused = Dw; sigma = sigmaW;
        self.mismatchSince = 0;
    } else {
        fused = Dg; sigma = sigmaG;
        self.mismatchSince = 0;
    }
    if (sigma <= 0) sigma = 1.0;

    // (4) Lọc theo thời gian: trung vị 5 mẫu rồi Kalman vận tốc không đổi.
    double measured = [self medianPush:fused];
    double filtered = [self kalmanUpdate:measured variance:(sigma * sigma) timestamp:timestamp];

    // (5) Quy về đầu xe mình.
    double display = s.calibrationFactor * filtered - s.frontOffsetMeters;
    if (display < 0) display = 0;

    r.valid = YES;
    r.widthMeters = Dw;
    r.groundMeters = Dg;
    r.widthValid = widthValid;
    r.groundValid = groundValid;
    r.fusedMeters = filtered;
    r.sigmaMeters = sigma;
    r.distanceMeters = display;
    r.closingSpeedMps = self.closingSpeedMps;
    r.needsCalibration = self.needsCalibration;
    r.approximate = (display >= 100.0);

    self.logCounter += 1;
    if (self.logCounter % 150 == 1) {   // ~10 giây một dòng ở 15 fps
        KCLogf(@"range: %@ w_px=%.0f D_w=%.1f%@ D_g=%.1f%@ hop=%.1f±%.1f loc=%.1f -> %.1f m (theta=%.2f°)",
               detection.label, wpx,
               Dw, widthValid ? @"" : @"(bo)", Dg, groundValid ? @"" : @"(bo)",
               fused, sigma, filtered, display, self.pitchRadians * 180 / M_PI);
    }
    return r;
}

#pragma mark - Bộ lọc

- (double)medianPush:(double)value {
    [self.window addObject:@(value)];
    if (self.window.count > 5) [self.window removeObjectAtIndex:0];
    NSArray<NSNumber *> *sorted = [self.window sortedArrayUsingSelector:@selector(compare:)];
    return sorted[sorted.count / 2].doubleValue;
}

- (double)kalmanUpdate:(double)z variance:(double)R timestamp:(NSTimeInterval)t {
    if (R < 1e-6) R = 1e-6;

    if (!self.hasState || self.lastUpdate == 0 || (t - self.lastUpdate) > 1.0) {
        // Khởi tạo lại khi chưa có trạng thái hoặc đã mất dấu quá lâu.
        self.hasState = YES;
        self.x0 = z; self.x1 = 0;
        self.p00 = R; self.p01 = 0; self.p10 = 0; self.p11 = 25.0;
        self.lastUpdate = t;
        self.closingSpeedMps = 0;
        return z;
    }

    double dt = t - self.lastUpdate;
    if (dt <= 0) dt = 1e-3;
    self.lastUpdate = t;

    // Dự đoán: d += v·dt
    double x0 = self.x0 + self.x1 * dt;
    double x1 = self.x1;
    double p00 = self.p00 + dt * (self.p10 + self.p01) + dt * dt * self.p11;
    double p01 = self.p01 + dt * self.p11;
    double p10 = self.p10 + dt * self.p11;
    double p11 = self.p11;

    double q = kKCProcessNoise;
    double dt2 = dt * dt, dt3 = dt2 * dt, dt4 = dt2 * dt2;
    p00 += q * dt4 / 4.0;
    p01 += q * dt3 / 2.0;
    p10 += q * dt3 / 2.0;
    p11 += q * dt2;

    // Hiệu chỉnh với phép đo khoảng cách (H = [1 0])
    double sInnov = p00 + R;
    double k0 = p00 / sInnov;
    double k1 = p10 / sInnov;
    double y = z - x0;
    x0 += k0 * y;
    x1 += k1 * y;

    double np00 = (1 - k0) * p00;
    double np01 = (1 - k0) * p01;
    double np10 = p10 - k1 * p00;
    double np11 = p11 - k1 * p01;

    self.x0 = x0; self.x1 = x1;
    self.p00 = np00; self.p01 = np01; self.p10 = np10; self.p11 = np11;
    self.closingSpeedMps = x1;
    return x0;
}

@end
