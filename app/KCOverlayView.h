#import <UIKit/UIKit.h>
#import "KCDetection.h"

/// Dữ liệu hình học để vẽ thảm khoảng cách theo phối cảnh trên mặt đường.
typedef struct {
    BOOL valid;
    float fx, fy, cx, cy;
    int bufferWidth, bufferHeight;
    double pitchRadians;         // góc chúc camera, dương = chúc xuống
    double cameraHeightMeters;   // chiều cao ống kính so mặt đường
    double laneWidthMeters;      // bề rộng làn giả định
    double leadDistanceMeters;   // khoảng cách tới xe trước tính từ ống kính; 0 = chưa có
    double thresholdMeters;      // ngưỡng an toàn; 0 = chưa có
} KCLadderGeometry;

/// Lớp phủ trên preview: thảm khoảng cách đổi màu, khung bao xe, nhãn cự ly.
@interface KCOverlayView : UIView

/// Đổi hình chữ nhật chuẩn hoá (gốc trên-trái, toàn khung) sang toạ độ view.
@property (nonatomic, copy) CGRect (^rectConverter)(CGRect normalizedRect);
/// Đổi một điểm chuẩn hoá sang toạ độ view.
@property (nonatomic, copy) CGPoint (^pointConverter)(CGPoint normalizedPoint);

@property (nonatomic, strong) UIColor *leaderColor;
@property (nonatomic, assign) BOOL showsFarRegion;
@property (nonatomic, assign) CGRect farRegionTopLeft;
/// Vẽ thảm khoảng cách (mặc định bật).
@property (nonatomic, assign) BOOL showsLadder;
/// Không vẽ thảm bên dưới đường này (tránh chui xuống dưới thẻ số liệu).
@property (nonatomic, assign) CGFloat bottomLimitY;

- (void)updateWithDetections:(NSArray<KCDetection *> *)detections
                      leader:(KCDetection *)leader
                  leaderLost:(BOOL)leaderLost
              displayedMeters:(double)displayedMeters
              distanceIsValid:(BOOL)distanceIsValid
                     geometry:(KCLadderGeometry)geometry;

@end
