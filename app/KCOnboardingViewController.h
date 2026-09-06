#import <UIKit/UIKit.h>

/// Ba trang hướng dẫn hiện ở lần mở đầu tiên: gắn máy, cân ngang, miễn trừ trách nhiệm.
/// Từ lần thứ hai vào thẳng màn đo (mục 2).
@interface KCOnboardingViewController : UIViewController

/// YES nếu người dùng chưa xem xong lần nào.
+ (BOOL)shouldShow;
/// Đánh dấu đã xem xong.
+ (void)markCompleted;

@property (nonatomic, copy) void (^onFinish)(void);

@end
