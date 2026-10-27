#import <Foundation/Foundation.h>

@interface LBLauncher : NSObject
+ (void)launchBundleID:(NSString *)bundleID;
+ (void)goHome; // kills the running app (replace mode) and shows the grid
@end
