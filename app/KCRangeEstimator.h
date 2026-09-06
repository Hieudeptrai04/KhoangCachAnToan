#import <Foundation/Foundation.h>
#import "KCDetection.h"
#import "KCCameraController.h"

/// Kết quả ước lượng khoảng cách cho một khung hình.
typedef struct {
    BOOL valid;                 // có ít nhất một phép đo hợp lệ
    double distanceMeters;      // giá trị hiển thị: k · D_hợp_nhất − d_front
    double fusedMeters;         // D hợp nhất (tính từ ống kính)
    double widthMeters;         // D theo bề rộng xe
    double groundMeters;        // D theo mặt đường
    BOOL widthValid;
    BOOL groundValid;
    double sigmaMeters;         // độ lệch chuẩn ước tính của D hợp nhất
    double closingSpeedMps;     // tốc độ thay đổi khoảng cách (âm = đang tiến sát)
    BOOL needsCalibration;      // hai phép đo lệch > 30 % kéo dài > 1 s
    BOOL approximate;           // từ 100 m trở lên: chỉ là ước lượng
} KCRangeResult;

/// Ước lượng khoảng cách bằng một mắt (mục 5.4): bề rộng xe, hình học mặt đường,
/// hợp nhất theo nghịch phương sai, lọc theo thời gian, rồi quy về đầu xe mình.
@interface KCRangeEstimator : NSObject

/// Góc chúc camera (radian, dương = chúc xuống). Bộ điều khiển cập nhật từ KCMotion.
@property (nonatomic, assign) double pitchRadians;
/// Tốc độ thay đổi khoảng cách hiện tại theo bộ lọc, m/s.
@property (nonatomic, assign, readonly) double closingSpeedMps;

- (KCRangeResult)estimateForDetection:(KCDetection *)detection
                           intrinsics:(KCIntrinsics)intrinsics
                        farRegionSize:(CGFloat)farRegionWidthFraction
                            timestamp:(NSTimeInterval)timestamp;

/// Hàng pixel của đường chân trời theo góc chúc hiện tại: y = cy − fy·tan(θ).
- (double)horizonRowForIntrinsics:(KCIntrinsics)intrinsics;

- (void)reset;

@end
