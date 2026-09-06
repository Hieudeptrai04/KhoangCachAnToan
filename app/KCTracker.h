#import <Foundation/Foundation.h>
#import "KCDetection.h"

/// Kết quả một lần cập nhật: danh sách xe đã gán mã bám, xe dẫn đầu, trạng thái mất dấu.
@interface KCTrackerResult : NSObject
@property (nonatomic, copy) NSArray<KCDetection *> *detections;
@property (nonatomic, strong) KCDetection *leader;     // nil khi không có xe dẫn đầu
@property (nonatomic, assign) BOOL leaderLost;         // đang giữ vị trí cũ vì mất dấu (≤ 1 s)
@property (nonatomic, assign) NSInteger leaderTrackID;
@end

/// Chọn xe dẫn đầu cùng làn và bám theo giữa các khung hình (mục 5.3).
///
/// Hành lang làn mình là hình thang: đáy khung rộng x 25–75 %, thu về x 45–55 % tại đường chân trời.
/// Một xe được coi là "cùng làn" khi ĐIỂM GIỮA CẠNH ĐÁY của khung bao nằm trong hình thang tại hàng y đó.
/// Xe dẫn đầu là xe cùng làn có cạnh đáy thấp nhất trong khung (gần nhất).
@interface KCTracker : NSObject

/// Đường chân trời, chuẩn hoá [0,1] theo chiều cao khung, gốc trên-trái. Mặc định 0,5.
@property (nonatomic, assign) CGFloat horizonY;
/// Nửa bề rộng hành lang tại đáy khung (mặc định 0,25) và tại chân trời (mặc định 0,05).
@property (nonatomic, assign) CGFloat laneHalfWidthBottom;
@property (nonatomic, assign) CGFloat laneHalfWidthTop;
/// Ngưỡng IoU để coi hai khung bao ở hai khung hình là cùng một xe (mặc định 0,3).
@property (nonatomic, assign) CGFloat matchIoU;
/// Số khung liên tiếp một ứng viên phải thắng thì mới đổi xe dẫn đầu (mặc định 5).
@property (nonatomic, assign) NSInteger leaderSwitchFrames;
/// Thời gian giữ xe dẫn đầu sau khi mất dấu, giây (mặc định 1,0).
@property (nonatomic, assign) NSTimeInterval leaderHoldSeconds;

- (KCTrackerResult *)updateWithDetections:(NSArray<KCDetection *> *)detections
                                timestamp:(NSTimeInterval)timestamp;
- (void)reset;

/// Nửa bề rộng hành lang làn tại hàng y (chuẩn hoá, gốc trên-trái) — dùng cả cho việc vẽ.
- (CGFloat)laneHalfWidthAtY:(CGFloat)y;

@end
