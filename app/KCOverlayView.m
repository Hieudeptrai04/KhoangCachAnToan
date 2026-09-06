#import "KCOverlayView.h"
#import "KCCommon.h"

@interface KCOverlayView ()
@property (nonatomic, strong) CAShapeLayer *othersLayer;
@property (nonatomic, strong) CAShapeLayer *leaderLayer;
@property (nonatomic, strong) CAShapeLayer *farRegionLayer;
@property (nonatomic, strong) CATextLayer *leaderLabel;
@end

@implementation KCOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = NO;
        _leaderColor = KCColorGreen();

        _farRegionLayer = [CAShapeLayer layer];
        _farRegionLayer.fillColor = [UIColor clearColor].CGColor;
        _farRegionLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        _farRegionLayer.lineWidth = 1.0;
        _farRegionLayer.lineDashPattern = @[@4, @6];
        _farRegionLayer.hidden = YES;
        [self.layer addSublayer:_farRegionLayer];

        _othersLayer = [CAShapeLayer layer];
        _othersLayer.fillColor = [UIColor clearColor].CGColor;
        _othersLayer.strokeColor = [UIColor colorWithWhite:0.75 alpha:0.85].CGColor;
        _othersLayer.lineWidth = 1.5;
        [self.layer addSublayer:_othersLayer];

        _leaderLayer = [CAShapeLayer layer];
        _leaderLayer.fillColor = [UIColor clearColor].CGColor;
        _leaderLayer.strokeColor = _leaderColor.CGColor;
        _leaderLayer.lineWidth = 4.0;
        [self.layer addSublayer:_leaderLayer];

        _leaderLabel = [CATextLayer layer];
        _leaderLabel.fontSize = 15;
        _leaderLabel.alignmentMode = kCAAlignmentCenter;
        _leaderLabel.foregroundColor = [UIColor whiteColor].CGColor;
        _leaderLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55].CGColor;
        _leaderLabel.cornerRadius = 4;
        _leaderLabel.contentsScale = [UIScreen mainScreen].scale;
        _leaderLabel.hidden = YES;
        [self.layer addSublayer:_leaderLabel];
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
    [CATransaction commit];
}

- (void)setLeaderColor:(UIColor *)leaderColor {
    _leaderColor = leaderColor ?: KCColorGreen();
    self.leaderLayer.strokeColor = _leaderColor.CGColor;
}

- (void)setShowsFarRegion:(BOOL)showsFarRegion {
    _showsFarRegion = showsFarRegion;
    self.farRegionLayer.hidden = !showsFarRegion;
}

- (CGRect)viewRectFor:(CGRect)nrect {
    if (self.rectConverter) return self.rectConverter(nrect);
    CGRect b = self.bounds;   // dự phòng: co giãn đều theo bounds
    return CGRectMake(nrect.origin.x * b.size.width, nrect.origin.y * b.size.height,
                      nrect.size.width * b.size.width, nrect.size.height * b.size.height);
}

- (void)updateWithDetections:(NSArray<KCDetection *> *)detections
                      leader:(KCDetection *)leader
                  leaderLost:(BOOL)leaderLost {
    UIBezierPath *others = [UIBezierPath bezierPath];
    for (KCDetection *d in detections) {
        if (leader && d.trackID == leader.trackID && d.isLeader) continue;
        CGRect r = [self viewRectFor:d.nrect];
        if (CGRectIsEmpty(r)) continue;
        [others appendPath:[UIBezierPath bezierPathWithRect:r]];
    }

    UIBezierPath *leaderPath = nil;
    CGRect leaderRect = CGRectZero;
    if (leader) {
        leaderRect = [self viewRectFor:leader.nrect];
        if (!CGRectIsEmpty(leaderRect)) leaderPath = [UIBezierPath bezierPathWithRoundedRect:leaderRect cornerRadius:3];
    }

    UIBezierPath *far = nil;
    if (self.showsFarRegion) {
        CGRect r = [self viewRectFor:self.farRegionTopLeft];
        if (!CGRectIsEmpty(r)) far = [UIBezierPath bezierPathWithRect:r];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.othersLayer.path = others.CGPath;
    self.leaderLayer.path = leaderPath.CGPath;
    self.leaderLayer.opacity = leaderLost ? 0.45f : 1.0f;
    self.leaderLayer.lineDashPattern = leaderLost ? @[@6, @4] : nil;
    self.farRegionLayer.path = far.CGPath;

    if (leaderPath) {
        NSString *text = [NSString stringWithFormat:@" %@ %.0f%%%@ ", leader.label, leader.confidence * 100,
                          leaderLost ? @" · mất dấu" : @""];
        self.leaderLabel.string = text;
        CGFloat w = MAX(72, text.length * 8.0);
        CGFloat y = CGRectGetMinY(leaderRect) - 22;
        if (y < 2) y = CGRectGetMaxY(leaderRect) + 2;
        self.leaderLabel.frame = CGRectMake(CGRectGetMidX(leaderRect) - w / 2, y, w, 19);
        self.leaderLabel.hidden = NO;
    } else {
        self.leaderLabel.hidden = YES;
    }
    [CATransaction commit];
}

@end
