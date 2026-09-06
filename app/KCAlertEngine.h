#import <Foundation/Foundation.h>

/// Cảnh báo khi bám quá gần (FR-4).
///
/// Bíp được tổng hợp tại chỗ (880 Hz, 120 ms) nên không cần file âm thanh trong gói.
/// Phiên âm thanh dùng chế độ trộn và giảm nhẹ âm nền, chỉ kích hoạt lúc phát, để không
/// cướp âm thanh của nhạc hay của ứng dụng dẫn đường.
@interface KCAlertEngine : NSObject

/// Bật tiếng bíp. Mặc định bật.
@property (nonatomic, assign) BOOL beepEnabled;
/// Bật rung. Mặc định bật.
@property (nonatomic, assign) BOOL hapticEnabled;
/// Bật giọng đọc tiếng Việt. Mặc định bật.
@property (nonatomic, assign) BOOL speechEnabled;
/// Khoảng cách tối thiểu giữa hai lần cảnh báo, giây. Mặc định 3.
@property (nonatomic, assign) NSTimeInterval minimumInterval;

/// Phát cảnh báo nếu đã quá khoảng cách tối thiểu kể từ lần trước. Trả về YES nếu thực sự phát.
- (BOOL)fireAlertWithSpokenText:(NSString *)text;
/// Phát thử ngay, bỏ qua giới hạn thời gian (dùng ở màn cài đặt).
- (void)testAlert;

@end
