#import <Foundation/Foundation.h>

/// Loại ngưỡng đang áp dụng.
typedef NS_ENUM(NSInteger, KCThresholdKind) {
    KCThresholdNone = 0,      // chưa có tốc độ hợp lệ
    KCThresholdAdvisory,      // dưới ngưỡng luật: tài xế chủ động, app gợi ý theo số giây
    KCThresholdLegal,         // có số cứng trong thông tư
};

typedef struct {
    KCThresholdKind kind;
    double meters;            // ngưỡng đã nhân hệ số thời tiết xấu nếu có
    double baseMeters;        // ngưỡng gốc chưa nhân hệ số
    BOOL adverseApplied;
    BOOL overSpeed;           // vượt quá mốc cao nhất trong bảng
} KCThreshold;

/// Bảng khoảng cách an toàn và mức phạt, nạp từ legal.json (mục 3).
///
/// KHÔNG hard-code ngưỡng trong mã: toàn bộ số liệu nằm trong legal.json đóng gói theo bản,
/// và app tự tải bản mới về tối đa 1 lần mỗi 7 ngày. Lỗi tải hoặc JSON hỏng thì giữ bản cũ.
@interface KCLegalRules : NSObject

+ (instancetype)shared;

@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, copy, readonly) NSString *source;
@property (nonatomic, copy, readonly) NSString *disclaimer;
@property (nonatomic, copy, readonly) NSString *originLabel;      // "trong app" hoặc "tải về"
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *brackets;
@property (nonatomic, copy, readonly) NSArray<NSDictionary *> *penalties;
@property (nonatomic, copy, readonly) NSArray<NSString *> *notes;
@property (nonatomic, assign, readonly) double legalFromKmh;
@property (nonatomic, assign, readonly) double advisorySeconds;
@property (nonatomic, assign, readonly) double adverseFactorDefault;

/// Nạp bản trong bundle, rồi đè bằng bản tải về nếu bản đó mới hơn và hợp lệ.
- (void)load;

/// Ngưỡng THÔ theo tốc độ, không có độ trễ. Dùng cho kiểm thử và cho hiển thị màn Luật.
- (KCThreshold)rawThresholdForSpeedKmh:(double)kmh adverseFactor:(double)factor;

/// Ngưỡng CÓ ĐỘ TRỄ 2 km/h giữ trong 1 giây, để số không nhấp nháy quanh 60/80/100/120.
- (KCThreshold)thresholdForSpeedKmh:(double)kmh
                       adverseFactor:(double)factor
                           timestamp:(NSTimeInterval)timestamp;

- (void)resetHysteresis;

/// Tải bản mới từ máy chủ nếu đã quá 7 ngày kể từ lần thử gần nhất. Không chặn luồng gọi.
- (void)updateFromServerIfDue;

/// Tự kiểm tra bảng ngưỡng và độ trễ (mục 10.4). Ghi PASS/FAIL ra log, trả về số phép thử hỏng.
- (NSInteger)runSelfTest;

@end
