#import "KCHUDView.h"
#import "KCCommon.h"

#pragma mark - Ô số liệu

/// Một ô nhỏ trong lưới: biểu tượng + nhãn ở trên, giá trị ở dưới.
@interface KCStatTile : UIView
@property (nonatomic, strong) UIImageView *iconView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title tint:(UIColor *)tint;
- (void)setValue:(NSString *)value;
@end

@implementation KCStatTile

- (instancetype)initWithSymbol:(NSString *)symbol title:(NSString *)title tint:(UIColor *)tint {
    if ((self = [super initWithFrame:CGRectZero])) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10
                                                                                          weight:UIImageSymbolWeightBold];
        UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:cfg];
        _iconView = [[UIImageView alloc] initWithImage:img];
        _iconView.tintColor = tint;
        _iconView.contentMode = UIViewContentModeScaleAspectFit;
        [self addSubview:_iconView];

        _titleLabel = [[UILabel alloc] init];
        _titleLabel.text = title;
        _titleLabel.font = KCRoundedFont(9.5, UIFontWeightSemibold);
        _titleLabel.textColor = KCColorMuted();
        [self addSubview:_titleLabel];

        _valueLabel = [[UILabel alloc] init];
        _valueLabel.font = KCRoundedDigitFont(16, UIFontWeightBold);
        _valueLabel.textColor = [UIColor whiteColor];
        _valueLabel.adjustsFontSizeToFitWidth = YES;
        _valueLabel.minimumScaleFactor = 0.7;
        _valueLabel.text = @"—";
        [self addSubview:_valueLabel];
    }
    return self;
}

- (void)setValue:(NSString *)value {
    NSString *v = value.length ? value : @"—";
    if (![self.valueLabel.text isEqualToString:v]) self.valueLabel.text = v;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width;
    self.iconView.frame = CGRectMake(0, 1, 13, 13);
    self.titleLabel.frame = CGRectMake(16, 0, w - 16, 14);
    self.valueLabel.frame = CGRectMake(0, 16, w, 21);
}

@end

#pragma mark - HUD

@interface KCHUDView ()
@property (nonatomic, strong) UIVisualEffectView *card;
@property (nonatomic, strong) CAGradientLayer *cardAccent;
@property (nonatomic, strong) UILabel *speedLabel;
@property (nonatomic, strong) UILabel *speedUnitLabel;
@property (nonatomic, strong) UIView *statusPill;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSArray<KCStatTile *> *tiles;
@property (nonatomic, strong) UIStackView *badgeStack;
@property (nonatomic, strong) UILabel *debugLabel;
@property (nonatomic, strong) CAShapeLayer *horizonLayer;
@property (nonatomic, strong) CAGradientLayer *topShade;
@property (nonatomic, strong) UIButton *weatherButton;
@property (nonatomic, strong) UIButton *mapButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, assign) KCStatus status;
@property (nonatomic, assign) CGFloat cardTopY;
@end

@implementation KCHUDView

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _showsGuides = YES;
        _horizonY = 0.42;

        // Nền mờ dần ở mép trên để chữ và nút luôn đọc được trên nền trời sáng.
        _topShade = [CAGradientLayer layer];
        _topShade.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.55].CGColor,
                             (id)[UIColor clearColor].CGColor];
        [self.layer addSublayer:_topShade];

        _horizonLayer = [CAShapeLayer layer];
        _horizonLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        _horizonLayer.lineWidth = 1.0;
        _horizonLayer.lineDashPattern = @[@8, @8];
        [self.layer addSublayer:_horizonLayer];

        _weatherButton = [self makeGlassButtonWithSymbol:@"cloud.rain.fill"];
        _mapButton = [self makeGlassButtonWithSymbol:@"map.fill"];
        _settingsButton = [self makeGlassButtonWithSymbol:@"slider.horizontal.3"];
        [self addSubview:_weatherButton];
        [self addSubview:_mapButton];
        [self addSubview:_settingsButton];

        _badgeStack = [[UIStackView alloc] init];
        _badgeStack.axis = UILayoutConstraintAxisHorizontal;
        _badgeStack.spacing = 6;
        _badgeStack.alignment = UIStackViewAlignmentCenter;
        [self addSubview:_badgeStack];

        [self buildCard];

        _debugLabel = [[UILabel alloc] init];
        _debugLabel.font = [UIFont monospacedSystemFontOfSize:9 weight:UIFontWeightRegular];
        _debugLabel.textColor = [UIColor colorWithWhite:1 alpha:0.75];
        _debugLabel.numberOfLines = 3;
        _debugLabel.textAlignment = NSTextAlignmentCenter;
        _debugLabel.hidden = YES;
        [self addSubview:_debugLabel];
    }
    return self;
}

- (UIButton *)makeGlassButtonWithSymbol:(NSString *)symbol {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:19
                                                                                      weight:UIImageSymbolWeightSemibold];
    [b setImage:[UIImage systemImageNamed:symbol withConfiguration:cfg] forState:UIControlStateNormal];
    b.tintColor = [UIColor whiteColor];
    b.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.62];
    b.layer.cornerRadius = 25;
    b.layer.borderWidth = 1;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.22].CGColor;
    b.frame = CGRectMake(0, 0, 50, 50);
    return b;
}

- (void)buildCard {
    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
    self.card = [[UIVisualEffectView alloc] initWithEffect:blur];
    self.card.layer.cornerRadius = 26;
    self.card.layer.cornerCurve = kCACornerCurveContinuous;
    self.card.clipsToBounds = YES;
    self.card.layer.borderWidth = 1;
    self.card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    [self addSubview:self.card];

    UIView *content = self.card.contentView;

    // Dải màu trạng thái chạy dọc mép trên thẻ.
    self.cardAccent = [CAGradientLayer layer];
    self.cardAccent.startPoint = CGPointMake(0, 0.5);
    self.cardAccent.endPoint = CGPointMake(1, 0.5);
    [content.layer addSublayer:self.cardAccent];

    self.speedLabel = [[UILabel alloc] init];
    self.speedLabel.font = KCRoundedDigitFont(58, UIFontWeightHeavy);
    self.speedLabel.textColor = [UIColor whiteColor];
    self.speedLabel.text = @"—";
    self.speedLabel.adjustsFontSizeToFitWidth = YES;
    self.speedLabel.minimumScaleFactor = 0.6;
    [content addSubview:self.speedLabel];

    self.speedUnitLabel = [[UILabel alloc] init];
    self.speedUnitLabel.font = KCRoundedFont(14, UIFontWeightSemibold);
    self.speedUnitLabel.textColor = KCColorMuted();
    self.speedUnitLabel.text = @"km/h";
    [content addSubview:self.speedUnitLabel];

    self.statusPill = [[UIView alloc] init];
    self.statusPill.layer.cornerRadius = 13;
    self.statusPill.layer.cornerCurve = kCACornerCurveContinuous;
    self.statusPill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    [content addSubview:self.statusPill];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.font = KCRoundedFont(13, UIFontWeightBold);
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.text = @"Đang chờ";
    [self.statusPill addSubview:self.statusLabel];

    NSArray<NSArray *> *spec = @[
        @[@"speedometer",             @"TỐC ĐỘ",     KCColorGreen()],
        @[@"ruler",                   @"KHOẢNG CÁCH", [UIColor whiteColor]],
        @[@"clock",                   @"THỜI GIAN",  [UIColor whiteColor]],
        @[@"exclamationmark.triangle", @"VA CHẠM",   KCColorYellow()],
        @[@"waveform",                @"FPS",        KCColorMuted()],
        @[@"shield",                  @"NGƯỠNG LUẬT", KCColorGreen()],
    ];
    NSMutableArray<KCStatTile *> *tiles = [NSMutableArray array];
    for (NSArray *s in spec) {
        KCStatTile *t = [[KCStatTile alloc] initWithSymbol:s[0] title:s[1] tint:s[2]];
        [content addSubview:t];
        [tiles addObject:t];
    }
    self.tiles = tiles;
}

#pragma mark - Bố cục

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect b = self.bounds;
    UIEdgeInsets in = self.safeAreaInsets;

    self.topShade.frame = CGRectMake(0, 0, b.size.width, in.top + 74);

    CGFloat top = in.top + 10;
    self.weatherButton.frame = CGRectMake(16, top, 50, 50);
    self.settingsButton.frame = CGRectMake(b.size.width - 16 - 50, top, 50, 50);
    self.mapButton.frame = CGRectMake(b.size.width - 16 - 50 - 8 - 50, top, 50, 50);

    CGSize bs = [self.badgeStack systemLayoutSizeFittingSize:UILayoutFittingCompressedSize];
    CGFloat badgeW = MIN(bs.width, b.size.width - 210);
    self.badgeStack.frame = CGRectMake(floor((b.size.width - badgeW) / 2), top + 12, badgeW, MAX(bs.height, 24));

    // Thẻ đáy
    CGFloat cardH = 168;
    CGFloat cardX = 12;
    CGFloat cardW = b.size.width - 24;
    CGFloat cardY = b.size.height - in.bottom - 10 - cardH;
    self.card.frame = CGRectMake(cardX, cardY, cardW, cardH);
    self.cardTopY = cardY;

    self.cardAccent.frame = CGRectMake(0, 0, cardW, 3);

    CGFloat pad = 16;
    CGFloat leftW = floor(cardW * 0.36);
    self.speedLabel.frame = CGRectMake(pad, pad - 4, leftW - 8, 62);
    CGSize us = [self.speedUnitLabel sizeThatFits:CGSizeMake(80, 20)];
    self.speedUnitLabel.frame = CGRectMake(pad + 2, CGRectGetMaxY(self.speedLabel.frame) - 4, us.width, 18);
    self.statusPill.frame = CGRectMake(pad, cardH - pad - 26, leftW - 10, 26);
    self.statusLabel.frame = self.statusPill.bounds;

    // Lưới 3 cột × 2 hàng bên phải
    CGFloat gridX = pad + leftW + 6;
    CGFloat gridW = cardW - gridX - pad;
    CGFloat colW = floor((gridW - 16) / 3.0);
    CGFloat rowH = 40;
    CGFloat gridY = pad + 2;
    for (NSUInteger i = 0; i < self.tiles.count; i++) {
        NSUInteger row = i / 3, col = i % 3;
        self.tiles[i].frame = CGRectMake(gridX + col * (colW + 8), gridY + row * (rowH + 18), colW, rowH);
    }

    self.debugLabel.frame = CGRectMake(12, cardY - 42, b.size.width - 24, 38);

    [self updateGuides];
}

- (void)updateGuides {
    CGRect b = self.bounds;
    CGFloat yh = round(b.size.height * self.horizonY);
    UIBezierPath *h = [UIBezierPath bezierPath];
    [h moveToPoint:CGPointMake(18, yh)];
    [h addLineToPoint:CGPointMake(b.size.width - 18, yh)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.horizonLayer.path = h.CGPath;
    self.horizonLayer.hidden = !self.showsGuides;
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

#pragma mark - Giá trị

- (void)setSpeedKmh:(double)kmh valid:(BOOL)valid {
    NSString *t = valid ? KCFormatNumber(kmh, 0) : @"—";
    if (![self.speedLabel.text isEqualToString:t]) self.speedLabel.text = t;
    [self.tiles[0] setValue:valid ? [NSString stringWithFormat:@"%@ km/h", KCFormatNumber(kmh, 0)] : @"—"];
}

- (void)setDistanceMeters:(double)meters valid:(BOOL)valid approximate:(BOOL)approximate {
    NSString *v = @"—";
    if (valid) {
        NSString *num = meters < 10 ? KCFormatNumber(meters, 1) : KCFormatNumber(meters, 0);
        v = [NSString stringWithFormat:@"%@%@ m", approximate ? @"~" : @"", num];
    }
    [self.tiles[1] setValue:v];
}

- (void)setGapSeconds:(double)seconds valid:(BOOL)valid {
    [self.tiles[2] setValue:valid ? [NSString stringWithFormat:@"%@ s", KCFormatNumber(seconds, 1)] : @"—"];
}

- (void)setTimeToCollisionSeconds:(double)seconds valid:(BOOL)valid {
    [self.tiles[3] setValue:valid ? [NSString stringWithFormat:@"%@ s", KCFormatNumber(seconds, 1)] : @"—"];
}

- (void)setThresholdMeters:(double)meters valid:(BOOL)valid legal:(BOOL)legal {
    [self.tiles[5] setValue:valid ? [NSString stringWithFormat:@"%@ m", KCFormatNumber(meters, 0)] : @"—"];
    self.tiles[5].titleLabel.text = legal ? @"NGƯỠNG LUẬT" : @"KHUYẾN NGHỊ";
}

- (void)setInferenceFPS:(double)fps {
    [self.tiles[4] setValue:fps > 0 ? KCFormatNumber(fps, 0) : @"—"];
}

- (void)setStatus:(KCStatus)status text:(NSString *)text {
    UIColor *c;
    switch (status) {
        case KCStatusGreen:  c = KCColorGreen(); break;
        case KCStatusYellow: c = KCColorYellow(); break;
        case KCStatusRed:    c = KCColorRed(); break;
        default:             c = [UIColor colorWithWhite:1 alpha:0.45]; break;
    }
    if (![self.statusLabel.text isEqualToString:text]) self.statusLabel.text = text ?: @"";

    if (_status != status) {
        _status = status;
        self.statusPill.backgroundColor = [c colorWithAlphaComponent:status == KCStatusNone ? 0.16 : 0.28];
        self.statusLabel.textColor = status == KCStatusNone ? [UIColor whiteColor] : c;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self.cardAccent.colors = @[(id)[c colorWithAlphaComponent:0.15].CGColor,
                                   (id)c.CGColor,
                                   (id)[c colorWithAlphaComponent:0.15].CGColor];
        [CATransaction commit];

        // Đỏ thì thẻ thở nhẹ theo nhịp 2 Hz, đủ để lọt vào tầm mắt mà không chói.
        [self.card.layer removeAnimationForKey:@"alert"];
        self.card.layer.borderColor = (status == KCStatusRed ? c : [UIColor colorWithWhite:1 alpha:0.14]).CGColor;
        if (status == KCStatusRed) {
            CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"borderColor"];
            a.fromValue = (id)c.CGColor;
            a.toValue = (id)[c colorWithAlphaComponent:0.15].CGColor;
            a.duration = 0.25;
            a.autoreverses = YES;
            a.repeatCount = HUGE_VALF;
            [self.card.layer addAnimation:a forKey:@"alert"];
        }
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
        l.font = KCRoundedFont(11, UIFontWeightSemibold);
        l.textColor = [UIColor whiteColor];
        l.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.62];
        l.layer.cornerRadius = 11;
        l.layer.borderWidth = 1;
        l.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.18].CGColor;
        l.layer.masksToBounds = YES;
        l.textAlignment = NSTextAlignmentCenter;
        [self.badgeStack addArrangedSubview:l];
        // Đặt sau khi thêm vào stack: lúc đó view mới chuyển sang Auto Layout.
        [l.heightAnchor constraintEqualToConstant:22].active = YES;
    }
    [self setNeedsLayout];
}

- (void)setDebugText:(NSString *)text {
    self.debugLabel.text = text ?: @"";
}

- (void)setDebugVisible:(BOOL)visible {
    self.debugLabel.hidden = !visible;
}

- (void)setAdverseWeatherActive:(BOOL)active {
    self.weatherButton.tintColor = active ? [UIColor blackColor] : [UIColor whiteColor];
    self.weatherButton.backgroundColor = active ? KCColorYellow() : [UIColor colorWithWhite:0.08 alpha:0.62];
    self.weatherButton.layer.borderColor = (active ? KCColorYellow() : [UIColor colorWithWhite:1 alpha:0.22]).CGColor;
}

@end
