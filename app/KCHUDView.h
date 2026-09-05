#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, KCStatus) {
    KCStatusNone = 0,
    KCStatusGreen,
    KCStatusYellow,
    KCStatusRed,
};

/// HUD màn ngang (mục 5.8): khoảng cách trái trên, tốc độ phải trên, dải màu đáy, 2 nút to, vạch chân trời + hình thang làn.
@interface KCHUDView : UIView
@property (nonatomic, strong, readonly) UIButton *weatherButton;
@property (nonatomic, strong, readonly) UIButton *settingsButton;
@property (nonatomic, assign) BOOL showsGuides;   // vạch chân trời + hình thang làn (mặc định bật)
@property (nonatomic, assign) CGFloat horizonY;   // 0..1 theo chiều cao view (0,5 = giữa)

- (void)setDistanceMeters:(double)meters valid:(BOOL)valid approximate:(BOOL)approximate;
- (void)setThresholdText:(NSString *)text;
- (void)setSpeedKmh:(double)kmh valid:(BOOL)valid;
- (void)setGapSeconds:(double)seconds valid:(BOOL)valid;
- (void)setStatus:(KCStatus)status;
- (void)setBadges:(NSArray<NSString *> *)badges;
- (void)setDebugText:(NSString *)text;
- (void)setAdverseWeatherActive:(BOOL)active;
@end
