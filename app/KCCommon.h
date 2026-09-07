#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Phiên bản app — tăng đồng bộ với app/control, app/Makefile (PACKAGE_VERSION), Info.plist.
#define kAppVersion      @"1.2.0"
#define kAppBundleID     @"com.khoangcachantoan.app"
#define kKCDataDirectory @"/var/mobile/Documents/KhoangCachAnToan"
#define kKCPrefsPath     @"/var/mobile/Library/Preferences/com.khoangcachantoan.app.plist"

UIColor *KCColorGreen(void);    // #30D158
UIColor *KCColorYellow(void);   // #FFD60A
UIColor *KCColorRed(void);      // #FF453A
UIColor *KCColorInk(void);      // nền thẻ kính mờ
UIColor *KCColorMuted(void);    // chữ phụ

/// Định dạng số kiểu Việt Nam: dấu phẩy thập phân ("2,4").
NSString *KCFormatNumber(double value, int decimals);

/// Phông chữ bo tròn của hệ thống (SF Rounded) — dùng cho toàn bộ số liệu trên HUD.
UIFont *KCRoundedFont(CGFloat size, UIFontWeight weight);
/// Phông chữ bo tròn, chữ số cùng bề rộng để số không nhảy khi thay đổi.
UIFont *KCRoundedDigitFont(CGFloat size, UIFontWeight weight);
