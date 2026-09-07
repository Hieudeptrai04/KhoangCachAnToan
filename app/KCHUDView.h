#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, KCStatus) {
    KCStatusNone = 0,
    KCStatusGreen,
    KCStatusYellow,
    KCStatusRed,
};

/// HUD màn dọc: thẻ kính mờ ở đáy với tốc độ lớn, nhãn trạng thái và sáu ô số liệu;
/// hai nút kính tròn ở trên; vạch chân trời mảnh.
@interface KCHUDView : UIView

@property (nonatomic, strong, readonly) UIButton *weatherButton;
@property (nonatomic, strong, readonly) UIButton *mapButton;
@property (nonatomic, strong, readonly) UIButton *settingsButton;

/// Vạch chân trời (mặc định bật) và vị trí của nó, chuẩn hoá 0–1 theo chiều cao.
@property (nonatomic, assign) BOOL showsGuides;
@property (nonatomic, assign) CGFloat horizonY;

/// Chiều cao thẻ đáy, để lớp phủ biết vùng nào bị che.
@property (nonatomic, assign, readonly) CGFloat cardTopY;

- (void)setSpeedKmh:(double)kmh valid:(BOOL)valid;
- (void)setDistanceMeters:(double)meters valid:(BOOL)valid approximate:(BOOL)approximate;
- (void)setGapSeconds:(double)seconds valid:(BOOL)valid;
- (void)setTimeToCollisionSeconds:(double)seconds valid:(BOOL)valid;
- (void)setThresholdMeters:(double)meters valid:(BOOL)valid legal:(BOOL)legal;
- (void)setInferenceFPS:(double)fps;
- (void)setStatus:(KCStatus)status text:(NSString *)text;
- (void)setBadges:(NSArray<NSString *> *)badges;
- (void)setDebugText:(NSString *)text;
- (void)setDebugVisible:(BOOL)visible;
- (void)setAdverseWeatherActive:(BOOL)active;

@end
