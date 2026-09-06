#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <ImageIO/ImageIO.h>
#import "KCDetection.h"

@class KCDetector;

@protocol KCDetectorDelegate <NSObject>
/// Gọi trên hàng đợi suy luận (KHÔNG phải main queue).
- (void)detector:(KCDetector *)detector
 didFindVehicles:(NSArray<KCDetection *> *)detections
   inferenceTime:(NSTimeInterval)seconds;
@end

/// Phát hiện xe bằng Core ML (YOLOv3-Tiny Int8 của Apple) + Vision, hai kênh suy luận (mục 5.2).
///
/// Kênh XA: đặt regionOfInterest ở giữa khung (x 25–75 %, y 30–80 % theo hệ Vision gốc dưới-trái)
/// nên Vision chỉ thu nhỏ vùng đó về 416 px — xe ở 55–100 m to gấp đôi so với suy luận cả khung.
/// Kênh GẦN: cả khung, chạy 1 trên mỗi 3 lần suy luận, để bắt xe tạt đầu.
@interface KCDetector : NSObject

@property (nonatomic, weak) id<KCDetectorDelegate> delegate;
@property (nonatomic, assign, readonly) BOOL ready;
@property (nonatomic, assign, readonly) double inferenceFPS;
@property (nonatomic, assign, readonly) NSTimeInterval lastInferenceSeconds;
@property (nonatomic, copy, readonly) NSString *statusText;   // mô tả ngắn để hiện lên HUD/log

/// Số lần suy luận tối đa mỗi giây (mục 5.7: mặc định 15, tiết kiệm 10).
@property (nonatomic, assign) double maxInferenceFPS;
/// Ngưỡng tin cậy và IoU đưa vào model (nếu model nhận hai đầu vào tuỳ chọn này).
@property (nonatomic, assign) float confidenceThreshold;      // 0.30
@property (nonatomic, assign) float iouThreshold;             // 0.45
/// Vùng quan tâm của kênh xa, hệ Vision (gốc dưới-trái).
@property (nonatomic, assign) CGRect farRegionOfInterest;

/// Nạp model từ bundle. Trả về NO và điền error nếu hỏng; log toàn bộ mô tả model.
- (BOOL)loadModelWithError:(NSError **)error;

/// Nhận một khung hình từ hàng đợi camera. Tự bỏ khung khi đang bận hoặc vượt hạn mức fps.
- (void)submitPixelBuffer:(CVPixelBufferRef)pixelBuffer
              orientation:(CGImagePropertyOrientation)orientation;

@end
