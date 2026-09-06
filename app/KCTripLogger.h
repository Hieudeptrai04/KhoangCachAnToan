#import <Foundation/Foundation.h>

/// Nhật ký chuyến đi ra tệp CSV (FR-11).
///
/// Mỗi lần bật tạo một tệp `trip_YYYYMMDD_HHMM.csv` trong thư mục dữ liệu của app.
/// Cột: thời gian, tốc độ km/h, khoảng cách m, ngưỡng m, trạng thái.
@interface KCTripLogger : NSObject

@property (nonatomic, assign, readonly) BOOL recording;
@property (nonatomic, copy, readonly) NSString *currentPath;
@property (nonatomic, assign, readonly) NSUInteger rowCount;
/// Khoảng cách tối thiểu giữa hai dòng, giây. Mặc định 0,5.
@property (nonatomic, assign) NSTimeInterval minimumInterval;

- (BOOL)start;
- (void)stop;

/// Ghi một dòng nếu đang bật và đã quá khoảng cách tối thiểu.
- (void)logSpeedKmh:(double)speedKmh
      speedValid:(BOOL)speedValid
        distance:(double)distanceMeters
   distanceValid:(BOOL)distanceValid
       threshold:(double)thresholdMeters
          status:(NSString *)status;

/// Danh sách tệp CSV đã ghi, mới nhất trước.
+ (NSArray<NSString *> *)existingTripFiles;

@end
