#import "KCOverlayView.h"
#import "KCCommon.h"
#import <math.h>

/// Số dải tối đa của thảm khoảng cách.
static const NSUInteger kKCLadderBands = 12;
/// Dải gần nhất bắt đầu từ đây (mét, tính từ ống kính).
static const double kKCLadderNearMeters = 4.0;

@interface KCOverlayView ()
@property (nonatomic, strong) CAShapeLayer *othersLayer;
@property (nonatomic, strong) CAShapeLayer *leaderLayer;
@property (nonatomic, strong) CAShapeLayer *farRegionLayer;
@property (nonatomic, strong) NSArray<CAShapeLayer *> *bandLayers;
@property (nonatomic, strong) UIView *distancePill;
@property (nonatomic, strong) UILabel *distanceLabel;
@end

@implementation KCOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        self.layer.masksToBounds = YES;
        _leaderColor = KCColorGreen();
        _showsLadder = YES;

        // Các dải thảm nằm dưới cùng để khung bao xe vẽ đè lên trên.
        NSMutableArray<CAShapeLayer *> *bands = [NSMutableArray array];
        for (NSUInteger i = 0; i < kKCLadderBands; i++) {
            CAShapeLayer *l = [CAShapeLayer layer];
            l.strokeColor = [UIColor clearColor].CGColor;
            l.hidden = YES;
            [self.layer addSublayer:l];
            [bands addObject:l];
        }
        _bandLayers = bands;

        _farRegionLayer = [CAShapeLayer layer];
        _farRegionLayer.fillColor = [UIColor clearColor].CGColor;
        _farRegionLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
        _farRegionLayer.lineWidth = 1.0;
        _farRegionLayer.lineDashPattern = @[@4, @6];
        _farRegionLayer.hidden = YES;
        [self.layer addSublayer:_farRegionLayer];

        _othersLayer = [CAShapeLayer layer];
        _othersLayer.fillColor = [UIColor clearColor].CGColor;
        _othersLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.5].CGColor;
        _othersLayer.lineWidth = 1.5;
        [self.layer addSublayer:_othersLayer];

        _leaderLayer = [CAShapeLayer layer];
        _leaderLayer.fillColor = [UIColor clearColor].CGColor;
        _leaderLayer.strokeColor = _leaderColor.CGColor;
        _leaderLayer.lineWidth = 3.0;
        _leaderLayer.shadowColor = _leaderColor.CGColor;
        _leaderLayer.shadowOpacity = 0.9;
        _leaderLayer.shadowRadius = 6;
        _leaderLayer.shadowOffset = CGSizeZero;
        [self.layer addSublayer:_leaderLayer];

        _distancePill = [[UIView alloc] init];
        _distancePill.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.78];
        _distancePill.layer.cornerRadius = 13;
        _distancePill.layer.cornerCurve = kCACornerCurveContinuous;
        _distancePill.layer.borderWidth = 1;
        _distancePill.hidden = YES;
        [self addSubview:_distancePill];

        _distanceLabel = [[UILabel alloc] init];
        _distanceLabel.font = KCRoundedDigitFont(14, UIFontWeightBold);
        _distanceLabel.textColor = [UIColor whiteColor];
        _distanceLabel.textAlignment = NSTextAlignmentCenter;
        [_distancePill addSubview:_distanceLabel];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.othersLayer.frame = self.bounds;
    self.leaderLayer.frame = self.bounds;
    self.farRegionLayer.frame = self.bounds;
    for (CAShapeLayer *l in self.bandLayers) l.frame = self.bounds;
    [CATransaction commit];
}

- (void)setLeaderColor:(UIColor *)leaderColor {
    _leaderColor = leaderColor ?: KCColorGreen();
    self.leaderLayer.strokeColor = _leaderColor.CGColor;
    self.leaderLayer.shadowColor = _leaderColor.CGColor;
    self.distancePill.layer.borderColor = [_leaderColor colorWithAlphaComponent:0.7].CGColor;
}

- (void)setShowsFarRegion:(BOOL)showsFarRegion {
    _showsFarRegion = showsFarRegion;
    self.farRegionLayer.hidden = !showsFarRegion;
}

- (CGRect)viewRectFor:(CGRect)nrect {
    if (self.rectConverter) return self.rectConverter(nrect);
    CGRect b = self.bounds;
    return CGRectMake(nrect.origin.x * b.size.width, nrect.origin.y * b.size.height,
                      nrect.size.width * b.size.width, nrect.size.height * b.size.height);
}

- (CGPoint)viewPointFor:(CGPoint)npoint {
    if (self.pointConverter) return self.pointConverter(npoint);
    CGRect b = self.bounds;
    return CGPointMake(npoint.x * b.size.width, npoint.y * b.size.height);
}

#pragma mark - Thảm khoảng cách

/// Hàng ảnh của một điểm trên mặt đường cách ống kính D mét:
/// góc nhìn xuống = atan(h/D), trừ đi góc chúc rồi chiếu qua tiêu cự.
static double KCRowForDistance(KCLadderGeometry g, double D) {
    if (D <= 0.01) return NAN;
    double depression = atan(g.cameraHeightMeters / D);
    return g.cy + g.fy * tan(depression - g.pitchRadians);
}

/// Nửa bề rộng làn tại khoảng cách D, theo pixel ảnh.
static double KCHalfWidthForDistance(KCLadderGeometry g, double D) {
    if (D <= 0.01) return 0;
    return g.fx * (g.laneWidthMeters / 2.0) / D;
}

- (UIColor *)colorForBandDistance:(double)D threshold:(double)threshold {
    if (threshold <= 0) return KCColorGreen();
    if (D < threshold) return KCColorRed();
    if (D < threshold * 1.10) return KCColorYellow();
    return KCColorGreen();
}

- (void)updateLadder:(KCLadderGeometry)g {
    BOOL canDraw = (self.showsLadder && g.valid && g.fx > 0 && g.fy > 0 &&
                    g.bufferWidth > 0 && g.bufferHeight > 0 &&
                    g.cameraHeightMeters > 0.1 && g.leadDistanceMeters > kKCLadderNearMeters + 1.0);
    if (!canDraw) {
        for (CAShapeLayer *l in self.bandLayers) l.hidden = YES;
        return;
    }

    double far = MIN(g.leadDistanceMeters, 90.0);
    double near = kKCLadderNearMeters;
    NSUInteger count = kKCLadderBands;
    double step = (far - near) / (double)count;
    CGFloat limit = (self.bottomLimitY > 0) ? self.bottomLimitY : self.bounds.size.height;

    for (NSUInteger i = 0; i < count; i++) {
        CAShapeLayer *layer = self.bandLayers[i];
        // Dải gần ở dưới, dải xa ở trên; chừa khe giữa hai dải cho thoáng.
        double d0 = near + step * i;
        double d1 = d0 + step * 0.62;

        double y0 = KCRowForDistance(g, d0);
        double y1 = KCRowForDistance(g, d1);
        double hw0 = KCHalfWidthForDistance(g, d0);
        double hw1 = KCHalfWidthForDistance(g, d1);
        if (isnan(y0) || isnan(y1) || y1 >= y0) { layer.hidden = YES; continue; }

        CGPoint bl = [self viewPointFor:CGPointMake((g.cx - hw0) / g.bufferWidth, y0 / g.bufferHeight)];
        CGPoint br = [self viewPointFor:CGPointMake((g.cx + hw0) / g.bufferWidth, y0 / g.bufferHeight)];
        CGPoint tr = [self viewPointFor:CGPointMake((g.cx + hw1) / g.bufferWidth, y1 / g.bufferHeight)];
        CGPoint tl = [self viewPointFor:CGPointMake((g.cx - hw1) / g.bufferWidth, y1 / g.bufferHeight)];

        if (bl.y > limit || tl.y < 0 || bl.y <= tl.y) { layer.hidden = YES; continue; }

        UIBezierPath *p = [UIBezierPath bezierPath];
        [p moveToPoint:bl];
        [p addLineToPoint:br];
        [p addLineToPoint:tr];
        [p addLineToPoint:tl];
        [p closePath];

        UIColor *c = [self colorForBandDistance:d1 threshold:g.thresholdMeters];
        // Dải càng xa càng mờ, tạo cảm giác chiều sâu.
        CGFloat alpha = (CGFloat)(0.62 - 0.34 * ((double)i / (double)count));

        layer.hidden = NO;
        layer.path = p.CGPath;
        layer.fillColor = [c colorWithAlphaComponent:alpha].CGColor;
    }
}

#pragma mark - Cập nhật

- (void)updateWithDetections:(NSArray<KCDetection *> *)detections
                      leader:(KCDetection *)leader
                  leaderLost:(BOOL)leaderLost
             displayedMeters:(double)displayedMeters
             distanceIsValid:(BOOL)distanceIsValid
                    geometry:(KCLadderGeometry)geometry {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    [self updateLadder:geometry];

    UIBezierPath *others = [UIBezierPath bezierPath];
    for (KCDetection *d in detections) {
        if (leader && d.trackID == leader.trackID && d.isLeader) continue;
        CGRect r = [self viewRectFor:d.nrect];
        if (CGRectIsEmpty(r)) continue;
        [others appendPath:[UIBezierPath bezierPathWithRoundedRect:r cornerRadius:4]];
    }
    self.othersLayer.path = others.CGPath;

    CGRect leaderRect = CGRectZero;
    UIBezierPath *leaderPath = nil;
    if (leader) {
        leaderRect = [self viewRectFor:leader.nrect];
        if (!CGRectIsEmpty(leaderRect)) leaderPath = [UIBezierPath bezierPathWithRoundedRect:leaderRect cornerRadius:8];
    }
    self.leaderLayer.path = leaderPath.CGPath;
    self.leaderLayer.opacity = leaderLost ? 0.4f : 1.0f;
    self.leaderLayer.lineDashPattern = leaderLost ? @[@7, @5] : nil;

    UIBezierPath *far = nil;
    if (self.showsFarRegion) {
        CGRect r = [self viewRectFor:self.farRegionTopLeft];
        if (!CGRectIsEmpty(r)) far = [UIBezierPath bezierPathWithRect:r];
    }
    self.farRegionLayer.path = far.CGPath;
    [CATransaction commit];

    // Nhãn cự ly bám ngay trên nóc xe dẫn đầu.
    if (leaderPath && distanceIsValid) {
        NSString *text = [NSString stringWithFormat:@"Cự ly %@ m",
                          displayedMeters < 10 ? KCFormatNumber(displayedMeters, 1) : KCFormatNumber(displayedMeters, 0)];
        if (![self.distanceLabel.text isEqualToString:text]) self.distanceLabel.text = text;
        CGSize s = [self.distanceLabel sizeThatFits:CGSizeMake(200, 26)];
        CGFloat w = s.width + 22, h = 26;
        CGFloat x = CGRectGetMidX(leaderRect) - w / 2;
        CGFloat y = CGRectGetMinY(leaderRect) - h - 6;
        if (y < 4) y = CGRectGetMaxY(leaderRect) + 6;
        x = MAX(6, MIN(x, self.bounds.size.width - w - 6));
        self.distancePill.frame = CGRectMake(x, y, w, h);
        self.distanceLabel.frame = self.distancePill.bounds;
        self.distancePill.hidden = NO;
    } else {
        self.distancePill.hidden = YES;
    }
}

@end
