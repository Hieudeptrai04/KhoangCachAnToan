#import <Foundation/Foundation.h>

/// Nhật ký kỹ thuật: /var/mobile/Documents/KhoangCachAnToan/log.txt, xoay vòng 1 MB (FR-11).
@interface KCLog : NSObject
+ (instancetype)shared;
/// Thư mục dữ liệu của app (tự tạo nếu chưa có).
+ (NSString *)dataDirectory;
- (void)write:(NSString *)line;
@end

void KCLogf(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
