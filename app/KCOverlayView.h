#import <UIKit/UIKit.h>
#import "KCDetection.h"

/// Lớp phủ vẽ khung bao xe lên trên preview camera (mục 5.8).
/// Nằm giữa preview layer và HUD; không nhận chạm.
@interface KCOverlayView : UIView

/// Chuyển hình chữ nhật chuẩn hoá (gốc trên-trái, toàn khung) sang toạ độ view.
/// Bộ điều khiển gán bằng `layerRectConvertedFromMetadataOutputRect:` của preview layer
/// để khớp đúng khi preview dùng resizeAspectFill.
@property (nonatomic, copy) CGRect (^rectConverter)(CGRect normalizedRect);

/// Màu khung xe dẫn đầu (theo trạng thái 3 màu ở các phase sau).
@property (nonatomic, strong) UIColor *leaderColor;
/// Hiện khung vùng quan tâm của kênh xa (để kiểm tra khi hiệu chỉnh).
@property (nonatomic, assign) BOOL showsFarRegion;
/// Vùng quan tâm kênh xa theo quy ước app (chuẩn hoá, gốc trên-trái).
@property (nonatomic, assign) CGRect farRegionTopLeft;

- (void)updateWithDetections:(NSArray<KCDetection *> *)detections
                      leader:(KCDetection *)leader
                  leaderLost:(BOOL)leaderLost;

@end
