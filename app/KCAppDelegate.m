#import "KCAppDelegate.h"
#import "KCMainViewController.h"
#import "KCCommon.h"
#import "KCLog.h"
#import <sys/utsname.h>

static NSString *KCDeviceModel(void) {
    struct utsname u;
    if (uname(&u) != 0) return @"?";
    NSString *s = [NSString stringWithCString:u.machine encoding:NSUTF8StringEncoding];
    return s ?: @"?";
}

@implementation KCAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    KCLogf(@"=== Khoang Cach An Toan v%@ khoi dong | device=%@ iOS=%@ | bundle=%@",
           kAppVersion, KCDeviceModel(), [UIDevice currentDevice].systemVersion, [NSBundle mainBundle].bundlePath);
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.backgroundColor = [UIColor blackColor];
    self.window.rootViewController = [[KCMainViewController alloc] init];
    [self.window makeKeyAndVisible];
    application.idleTimerDisabled = YES;   // FR-9: giữ màn hình sáng khi đo
    return YES;
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    return UIInterfaceOrientationMaskLandscape;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    application.idleTimerDisabled = YES;
    KCLogf(@"app: active");
}

- (void)applicationWillResignActive:(UIApplication *)application {
    KCLogf(@"app: resign active");
}

@end
