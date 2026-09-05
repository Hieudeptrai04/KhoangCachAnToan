#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// Phiên bản app — tăng đồng bộ với app/control, app/Makefile (PACKAGE_VERSION), Info.plist.
#define kAppVersion      @"0.1.0"
#define kAppBundleID     @"com.khoangcachantoan.app"
#define kKCDataDirectory @"/var/mobile/Documents/KhoangCachAnToan"
#define kKCPrefsPath     @"/var/mobile/Library/Preferences/com.khoangcachantoan.app.plist"

UIColor *KCColorGreen(void);    // #30D158
UIColor *KCColorYellow(void);   // #FFD60A
UIColor *KCColorRed(void);      // #FF453A

/// Định dạng số kiểu Việt Nam: dấu phẩy thập phân ("2,4").
NSString *KCFormatNumber(double value, int decimals);
