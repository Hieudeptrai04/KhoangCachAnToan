#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

/// Một xe được phát hiện trong khung hình.
///
/// Quy ước toạ độ dùng THỐNG NHẤT trong app (khác quy ước gốc của Vision):
/// `nrect` là hình chữ nhật đã chuẩn hoá về [0,1] của TOÀN khung, gốc toạ độ ở GÓC TRÊN-TRÁI,
/// trục y hướng XUỐNG — giống UIKit và giống hệ toạ độ "metadata output" của
/// AVCaptureVideoPreviewLayer, nên đưa thẳng vào `layerRectConvertedFromMetadataOutputRect:`
/// là ra toạ độ trên màn hình. Vision trả về gốc dưới-trái và tương đối với vùng quan tâm (ROI),
/// việc quy đổi nằm trong KCDetector.
@interface KCDetection : NSObject <NSCopying>

@property (nonatomic, assign) CGRect nrect;        // chuẩn hoá toàn khung, gốc trên-trái
@property (nonatomic, copy) NSString *label;       // nhãn COCO: car, truck, bus, motorbike/motorcycle
@property (nonatomic, assign) float confidence;
@property (nonatomic, assign) BOOL fromFarChannel; // YES: kênh XA (ROI giữa khung), NO: kênh GẦN (cả khung)
@property (nonatomic, assign) NSInteger trackID;   // do KCTracker gán, -1 khi chưa bám
@property (nonatomic, assign) BOOL inLane;         // nằm trong hành lang làn mình
@property (nonatomic, assign) BOOL isLeader;       // xe dẫn đầu (gần nhất cùng làn)

/// Bề rộng bbox theo pixel của buffer.
- (CGFloat)widthPixelsForBufferWidth:(CGFloat)bufferWidth;
/// Hàng pixel của cạnh đáy bbox (y hướng xuống).
- (CGFloat)bottomPixelForBufferHeight:(CGFloat)bufferHeight;
/// Toạ độ x của điểm giữa cạnh đáy, chuẩn hoá [0,1].
- (CGFloat)bottomCenterX;
/// Tỉ lệ rộng/cao của bbox theo pixel thật (đã tính tỉ lệ khung hình).
- (CGFloat)aspectRatioForBufferWidth:(CGFloat)bufferWidth height:(CGFloat)bufferHeight;

@end

/// Tỉ lệ giao trên hợp của hai hình chữ nhật (dùng cho NMS và bám xe).
CGFloat KCRectIoU(CGRect a, CGRect b);
