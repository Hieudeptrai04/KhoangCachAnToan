#import <Foundation/Foundation.h>

/// Cài đặt của app, lưu thẳng vào plist (mục 5.9).
///
/// App chạy ngoài sandbox nên KHÔNG dựa vào NSUserDefaults: đọc/ghi trực tiếp
/// NSDictionary tại /var/mobile/Library/Preferences/com.khoangcachantoan.app.plist.
@interface KCSettings : NSObject

+ (instancetype)shared;

#pragma mark - Hiệu chỉnh (FR-6)

/// Chiều cao ống kính so với mặt đường, mét. Mặc định 1,25.
@property (nonatomic, assign) double cameraHeightMeters;
/// Khoảng cách từ điện thoại tới đầu xe mình, mét. Mặc định 1,5.
@property (nonatomic, assign) double frontOffsetMeters;
/// Hệ số chỉnh tay. Mặc định 1,0.
@property (nonatomic, assign) double calibrationFactor;
/// Offset góc chúc lưu khi bấm "cân ngang", radian. Mặc định 0.
@property (nonatomic, assign) double pitchOffsetRadians;

#pragma mark - Bề rộng thật của xe theo lớp (FR-8)

@property (nonatomic, assign) double widthCar;          // 1,80
@property (nonatomic, assign) double widthTruck;        // 2,50
@property (nonatomic, assign) double widthBus;          // 2,55
@property (nonatomic, assign) double widthMotorcycle;   // 0,80

/// Bề rộng thật (m) ứng với nhãn lớp; trả về widthCar nếu không nhận ra.
- (double)vehicleWidthForLabel:(NSString *)label;

#pragma mark - Vận hành

/// Số lần suy luận tối đa mỗi giây: 15 (thường) hoặc 10 (tiết kiệm).
@property (nonatomic, assign) double maxInferenceFPS;
/// Hệ số nhân ngưỡng khi bật chế độ thời tiết xấu. Mặc định 1,5.
@property (nonatomic, assign) double adverseFactor;
/// Hiện vạch chân trời và hình thang làn.
@property (nonatomic, assign) BOOL showsGuides;
/// Hiện khung vùng quan tâm của kênh xa.
@property (nonatomic, assign) BOOL showsFarRegion;

/// Ghi ngay xuống đĩa (cũng tự ghi sau mỗi lần đặt giá trị).
- (void)save;
/// Đưa mọi giá trị về mặc định.
- (void)resetToDefaults;

@end
