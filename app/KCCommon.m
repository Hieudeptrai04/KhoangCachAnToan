#import "KCCommon.h"

UIColor *KCColorGreen(void)  { return [UIColor colorWithRed:0x30 / 255.0 green:0xD1 / 255.0 blue:0x58 / 255.0 alpha:1.0]; }
UIColor *KCColorYellow(void) { return [UIColor colorWithRed:0xFF / 255.0 green:0xD6 / 255.0 blue:0x0A / 255.0 alpha:1.0]; }
UIColor *KCColorRed(void)    { return [UIColor colorWithRed:0xFF / 255.0 green:0x45 / 255.0 blue:0x3A / 255.0 alpha:1.0]; }

NSString *KCFormatNumber(double value, int decimals) {
    NSString *s = [NSString stringWithFormat:@"%.*f", decimals, value];
    return [s stringByReplacingOccurrencesOfString:@"." withString:@","];
}
