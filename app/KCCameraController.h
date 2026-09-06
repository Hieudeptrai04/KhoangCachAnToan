#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

/// Thông số nội tại camera theo pixel của buffer (mục 5.1).
typedef struct {
    float fx, fy, cx, cy;
    int width, height;
    BOOL fromDelivery;   // YES: từ attachment CameraIntrinsicMatrix; NO: tính từ videoFieldOfView
} KCIntrinsics;

@class KCCameraController;

@protocol KCCameraFrameDelegate <NSObject>
/// Gọi trên hàng đợi camera (serial). Không giữ pixelBuffer quá thời gian callback nếu không retain.
- (void)cameraController:(KCCameraController *)controller
    didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer
              intrinsics:(KCIntrinsics)intrinsics
               timestamp:(CMTime)timestamp;
@end

@interface KCCameraController : NSObject
@property (nonatomic, weak) id<KCCameraFrameDelegate> delegate;
@property (nonatomic, strong, readonly) AVCaptureSession *session;
@property (nonatomic, strong, readonly) AVCaptureDevice *device;
@property (nonatomic, copy, readonly) NSString *deviceLabel;   // "tele" hoặc "wide"
@property (nonatomic, assign, readonly) KCIntrinsics lastIntrinsics;
@property (nonatomic, assign, readonly) double measuredFPS;
/// Tổng số khung hình đã nhận kể từ khi chạy phiên. 0 kéo dài nghĩa là output bị nghẽn.
@property (nonatomic, assign, readonly) NSUInteger totalFrames;
/// NO nghĩa là buffer KHÔNG được data output xoay theo chiều màn hình (chế độ dự phòng).
/// Khi đó bộ điều khiển phải tự bù hướng khi đưa vào Vision và khi vẽ khung bao.
@property (nonatomic, assign, readonly) BOOL buffersRotated;

- (BOOL)setupPreferTelephoto:(BOOL)preferTele use4K:(BOOL)use4K error:(NSError **)error;
- (void)startRunning;
- (void)stopRunning;
- (void)applyVideoOrientation:(AVCaptureVideoOrientation)orientation;
@end
