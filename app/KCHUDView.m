#import "KCHUDView.h"
#import "KCCommon.h"

@interface KCHUDView ()
@property (nonatomic, strong) UILabel *distanceLabel;
@property (nonatomic, strong) UILabel *unitLabel;
@property (nonatomic, strong) UILabel *thresholdLabel;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *speedUnitLabel;
@property (nonatomic, strong) UILabel *gapLabel;
@property (nonatomic, strong) UIView *statusBar;
@property (nonatomic, strong) UIStackView *badgeStack;
@property (nonatomic, strong) UILabel *debugLabel;
@property (nonatomic, strong) CAShapeLayer *horizonLayer;
@property (nonatomic, strong) CAShapeLayer *laneLayer;
@property (nonatomic, strong) UIButton *weatherButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, assign) KCStatus status;
@end

@implementation KCHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _showsGuides = YES;
        _horizonY = 0.5;

        _laneLayer = [CAShapeLayer layer];
        _laneLayer.fillColor = [UIColor colorWithWhite:1 alpha:0.05].CGColor;
        _laneLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.45].CGColor;
        _laneLayer.lineWidth = 1.0;
        _laneLayer.lineDashPattern = @[@6, @4];
        [self.layer addSublayer:_laneLayer];

        _horizonLayer = [CAShapeLayer layer];
        _horizonLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
        _horizonLayer.lineWidth = 1.0;
        _horizonLayer.lineDashPattern = @[@10, @6];
        [self.layer addSublayer:_horizonLayer];

        _distanceLabel = [self makeLabelWithFont:[UIFont monospacedDigitSystemFontOfSize:96 weight:UIFontWeightBold]];
        _distanceLabel.text = @"—";
        _unitLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:28 weight:UIFontWeightSemibold]];
        _unitLabel.text = @"m";
        _thresholdLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:22 weight:UIFontWeightMedium]];
        _speedLabel = [self makeLabelWithFont:[UIFont monospacedDigitSystemFontOfSize:44 weight:UIFontWeightBold]];
        _speedLabel.text = @"—";
        _speedLabel.textAlignment = NSTextAlignmentRight;
        _speedUnitLabel = [self makeLabelWithFont:[UIFont systemFontOfSize:20 weight:UIFontWeightMedium]];
        _speedUnitLabel.text = @"km/h";
        _gapLabel = [self makeLabelWithFont:[UIFont monospacedDigitSystemFontOfSize:26 weight:UIFontWeightMedium]];
        _gapLabel.textAlignment = NSTextAlignmentRight;

        _statusBar = [[UIView alloc] init];
        _statusBar.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.6];
        [self addSubview:_statusBar];

        _badgeStack = [[UIStackView alloc] init];
        _badgeStack.axis = UILayoutConstraintAxisHorizontal;
        _badgeStack.spacing = 6;
        _badgeStack.alignment = UIStackViewAlignmentCenter;
        [self addSubview:_badgeStack];

        _debugLabel = [self makeLabelWithFont:[UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular]];
        _debugLabel.textColor = [UIColor colorWithWhite:0.9 alpha:1];
        _debugLabel.numberOfLines = 2;
        _debugLabel.textAlignment = NSTextAlignmentCenter;

        _weatherButton = [self makeRoundButtonWithTitle:@"☔"];
        _settingsButton = [self makeRoundButtonWithTitle:@"⚙"];
        [self addSubview:_weatherButton];
        [self addSubview:_settingsButton];
    }
    return self;
}

- (UILabel *)makeLabelWithFont:(UIFont *)font {
    UILabel *l = [[UILabel alloc] init];
    l.font = font;
    l.textColor = [UIColor whiteColor];
    l.shadowColor = [UIColor colorWithWhite:0 alpha:0.85];
    l.shadowOffset = CGSizeMake(0, 1.5);
    l.text = @"";
    [self addSubview:l];
    return l;
}

- (UIButton *)makeRoundButtonWithTitle:(NSString *)title {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:30];
    b.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
    b.layer.cornerRadius = 28;
    b.layer.borderWidth = 1.5;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.6].CGColor;
    b.frame = CGRectMake(0, 0, 56, 56);
    return b;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    UIEdgeInsets in = self.safeAreaInsets;
    CGFloat left = in.left + 18;
    CGFloat right = b.size.width - in.right - 18;
    CGFloat top = in.top + 6;
    CGFloat barH = 14;
    CGFloat barY = b.size.height - barH;

    // Khoảng cách (trái trên)
    CGSize ds = [self.distanceLabel sizeThatFits:CGSizeMake(520, 130)];
    self.distanceLabel.frame = CGRectMake(left, top, ds.width, ds.height);
    CGSize us = [self.unitLabel sizeThatFits:CGSizeMake(100, 50)];
    self.unitLabel.frame = CGRectMake(CGRectGetMaxX(self.distanceLabel.frame) + 8,
                                      CGRectGetMaxY(self.distanceLabel.frame) - us.height - 18, us.width, us.height);
    self.thresholdLabel.frame = CGRectMake(left, CGRectGetMaxY(self.distanceLabel.frame) - 8, 460, 30);

    // Tốc độ (phải trên)
    CGSize sus = [self.speedUnitLabel sizeThatFits:CGSizeMake(100, 40)];
    self.speedUnitLabel.frame = CGRectMake(right - sus.width, top + 24, sus.width, sus.height);
    CGSize ss = [self.speedLabel sizeThatFits:CGSizeMake(300, 60)];
    self.speedLabel.frame = CGRectMake(CGRectGetMinX(self.speedUnitLabel.frame) - 8 - ss.width, top, ss.width, ss.height);
    self.gapLabel.frame = CGRectMake(right - 260, CGRectGetMaxY(self.speedLabel.frame) - 2, 260, 34);

    // Dải trạng thái sát mép dưới
    self.statusBar.frame = CGRectMake(0, barY, b.size.width, barH);

    // Hai nút to
    CGFloat btnY = barY - in.bottom - 8 - 56;
    self.weatherButton.frame = CGRectMake(left, btnY, 56, 56);
    self.settingsButton.frame = CGRectMake(right - 56, btnY, 56, 56);

    // Huy hiệu (giữa trên)
    CGSize bs = [self.badgeStack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    self.badgeStack.frame = CGRectMake(floor((b.size.width - bs.width) / 2), top + 4, bs.width, MAX(bs.height, 22));

    // Dòng debug (giữa dưới, giữa hai nút)
    self.debugLabel.frame = CGRectMake(left + 64, btnY + 10, right - left - 128, 40);

    [self updateGuides];
}

- (void)updateGuides {
    CGRect b = self.bounds;
    CGFloat yh = round(b.size.height * self.horizonY);
    UIBezierPath *h = [UIBezierPath bezierPath];
    [h moveToPoint:CGPointMake(0, yh)];
    [h addLineToPoint:CGPointMake(b.size.width, yh)];
    UIBezierPath *lane = [UIBezierPath bezierPath];
    [lane moveToPoint:CGPointMake(b.size.width * 0.25, b.size.height)];
    [lane addLineToPoint:CGPointMake(b.size.width * 0.45, yh)];
    [lane addLineToPoint:CGPointMake(b.size.width * 0.55, yh)];
    [lane addLineToPoint:CGPointMake(b.size.width * 0.75, b.size.height)];
    [lane closePath];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.horizonLayer.path = h.CGPath;
    self.laneLayer.path = lane.CGPath;
    self.horizonLayer.hidden = !self.showsGuides;
    self.laneLayer.hidden = !self.showsGuides;
    [CATransaction commit];
}

- (void)setShowsGuides:(BOOL)showsGuides {
    _showsGuides = showsGuides;
    [self updateGuides];
}

- (void)setHorizonY:(CGFloat)horizonY {
    _horizonY = MIN(MAX(horizonY, 0.05), 0.95);
    [self updateGuides];
}

#pragma mark - Values

- (void)setLabel:(UILabel *)label text:(NSString *)text {
    if (![label.text isEqualToString:text]) {
        label.text = text;
        [self setNeedsLayout];
    }
}

- (void)setDistanceMeters:(double)meters valid:(BOOL)valid approximate:(BOOL)approximate {
    NSString *t = @"—";
    if (valid) {
        NSString *num = meters < 10 ? KCFormatNumber(meters, 1) : KCFormatNumber(meters, 0);
        t = approximate ? [@"~" stringByAppendingString:num] : num;
    }
    [self setLabel:self.distanceLabel text:t];
}

- (void)setThresholdText:(NSString *)text {
    [self setLabel:self.thresholdLabel text:text ?: @""];
}

- (void)setSpeedKmh:(double)kmh valid:(BOOL)valid {
    [self setLabel:self.speedLabel text:valid ? KCFormatNumber(kmh, 0) : @"—"];
}

- (void)setGapSeconds:(double)seconds valid:(BOOL)valid {
    [self setLabel:self.gapLabel text:valid ? [NSString stringWithFormat:@"%@ s", KCFormatNumber(seconds, 1)] : @""];
}

- (void)setStatus:(KCStatus)status {
    if (_status == status) return;
    _status = status;
    UIColor *c;
    switch (status) {
        case KCStatusGreen:  c = KCColorGreen(); break;
        case KCStatusYellow: c = KCColorYellow(); break;
        case KCStatusRed:    c = KCColorRed(); break;
        default:             c = [UIColor colorWithWhite:0.3 alpha:0.6]; break;
    }
    self.statusBar.backgroundColor = c;
    [self.statusBar.layer removeAnimationForKey:@"blink"];
    if (status == KCStatusRed) {   // nhấp nháy 2 Hz
        CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"opacity"];
        a.fromValue = @1.0;
        a.toValue = @0.15;
        a.duration = 0.25;
        a.autoreverses = YES;
        a.repeatCount = HUGE_VALF;
        [self.statusBar.layer addAnimation:a forKey:@"blink"];
    }
}

- (void)setBadges:(NSArray<NSString *> *)badges {
    for (UIView *v in [self.badgeStack.arrangedSubviews copy]) {
        [self.badgeStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }
    for (NSString *s in badges) {
        UILabel *l = [[UILabel alloc] init];
        l.text = [NSString stringWithFormat:@"  %@  ", s];
        l.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
        l.textColor = [UIColor whiteColor];
        l.backgroundColor = [UIColor colorWithWhite:0 alpha:0.55];
        l.layer.cornerRadius = 6;
        l.layer.masksToBounds = YES;
        [self.badgeStack addArrangedSubview:l];
    }
    [self setNeedsLayout];
}

- (void)setDebugText:(NSString *)text {
    self.debugLabel.text = text ?: @"";
}

- (void)setAdverseWeatherActive:(BOOL)active {
    self.weatherButton.selected = active;
    self.weatherButton.backgroundColor = active ? [KCColorYellow() colorWithAlphaComponent:0.45] : [UIColor colorWithWhite:0 alpha:0.55];
    self.weatherButton.layer.borderColor = active ? KCColorYellow().CGColor : [UIColor colorWithWhite:1 alpha:0.6].CGColor;
}

@end
