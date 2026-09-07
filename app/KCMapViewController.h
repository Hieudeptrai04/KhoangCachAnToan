#import <UIKit/UIKit.h>

@class KCLocation;

/// Bản đồ trong app: xem mình đang ở đâu khi không cần đo khoảng cách.
///
/// Đây KHÔNG phải phần mềm dẫn đường. Không có chỉ đường từng chặng, không có tìm địa điểm,
/// không có giao thông thời gian thực. Cần dẫn đường thật thì bấm nút bàn giao sang Google Maps.
@interface KCMapViewController : UIViewController

/// Nguồn tốc độ, dùng chung với màn đo.
@property (nonatomic, weak) KCLocation *location;

@end
