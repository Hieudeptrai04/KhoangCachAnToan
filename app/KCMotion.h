#import <Foundation/Foundation.h>

/// Góc chúc của camera lấy từ cảm biến, đã lọc thông thấp và cộng offset "cân ngang" (mục 5.4).
///
/// Quy ước: `pitchRadians` > 0 nghĩa là ống kính chúc XUỐNG dưới đường chân trời.
/// Tính từ vector trọng lực trong hệ toạ độ thiết bị: trục quang của camera sau là −z,
/// nên sin(góc chúc) = −gravity.z. Cách này không phụ thuộc máy đang nằm ngang chiều nào.
@interface KCMotion : NSObject

@property (nonatomic, assign, readonly) BOOL available;
@property (nonatomic, assign, readonly) BOOL running;
/// Góc chúc đã lọc và đã cộng offset, radian.
@property (nonatomic, assign, readonly) double pitchRadians;
/// Góc chúc thô (chưa cộng offset), radian — dùng khi bấm "cân ngang".
@property (nonatomic, assign, readonly) double rawPitchRadians;
/// Offset cân ngang, radian. Đặt bằng −rawPitch để coi tư thế hiện tại là ngang bằng.
@property (nonatomic, assign) double pitchOffsetRadians;
/// Hằng số thời gian bộ lọc thông thấp, giây. Mặc định 0,5.
@property (nonatomic, assign) double smoothingSeconds;

- (void)start;
- (void)stop;
/// Lưu tư thế hiện tại làm mốc ngang bằng; trả về offset mới (radian).
- (double)levelNow;

@end
