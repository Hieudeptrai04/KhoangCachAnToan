#import <Foundation/Foundation.h>

/// Tốc độ xe lấy từ GPS (mục 5.5).
///
/// Dùng `location.speed` (m/s, −1 nghĩa là không hợp lệ), làm mượt bằng trung bình trượt mũ 1 giây.
/// Dưới 5 km/h coi như đứng yên: khi đó phần "luật" trên HUD bị ẩn (FR-2).
@interface KCLocation : NSObject

@property (nonatomic, assign, readonly) BOOL authorized;
@property (nonatomic, assign, readonly) BOOL running;
/// Tốc độ đã làm mượt, km/h. Chỉ có nghĩa khi speedValid = YES.
@property (nonatomic, assign, readonly) double speedKmh;
/// GPS đã khoá và cho tốc độ hợp lệ.
@property (nonatomic, assign, readonly) BOOL speedValid;
/// Đang di chuyển (≥ 5 km/h).
@property (nonatomic, assign, readonly) BOOL moving;
/// Sai số ngang gần nhất, mét (âm nếu không rõ).
@property (nonatomic, assign, readonly) double horizontalAccuracy;

- (void)start;
- (void)stop;

@end
