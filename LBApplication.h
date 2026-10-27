#import <UIKit/UIKit.h>

// UIApplication used when LiteBoard runs as the home screen. UIKit takes its SpringBoard
// code path (bundle id com.apple.springboard) and calls methods that only SpringBoard's own
// UIApplication subclass implements. Unknown selectors are logged once and ignored, which
// keeps startup going and records exactly which ones UIKit needs.
@interface LBApplication : UIApplication
@end

// Daemon mode only: UIKit's launch is normally started by SpringBoard, which is gone. If the
// app has not launched a few seconds after UIApplicationMain, log which launch-related methods
// UIKit's application class has, then call the delegate's launch method ourselves.
void LBRescueLaunch(void);
