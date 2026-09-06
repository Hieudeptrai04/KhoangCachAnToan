#import <UIKit/UIKit.h>

@class KCMotion;

/// Màn cài đặt và hiệu chỉnh (FR-6, FR-8). Làm trước khi khởi hành, không dùng khi đang lái.
@interface KCSettingsViewController : UIViewController

/// Nguồn góc chúc để hiển thị và để bấm "cân ngang".
@property (nonatomic, weak) KCMotion *motion;
/// Trả về khoảng cách hợp nhất hiện tại (m, tính từ ống kính, chưa nhân k, chưa trừ d_front),
/// hoặc 0 nếu chưa đo được. Dùng cho chức năng đặt k từ khoảng cách thật.
@property (nonatomic, copy) double (^currentFusedDistance)(void);
/// Gọi mỗi khi có thay đổi cần áp dụng ngay.
@property (nonatomic, copy) void (^onChange)(void);

@end
