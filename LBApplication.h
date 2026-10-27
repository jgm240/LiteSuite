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

// backboardd covers the screen with a progress spinner while no SpringBoard is running. Looks up
// that render overlay for the main display and dismisses it. Returns YES once it was dismissed.
BOOL LBDismissSpinnerOverlay(void);

// Touching the screen proves the UI is usable: creates /var/run/liteboard.confirmed so the
// watchdog keeps LiteBoard. Without it the watchdog reverts to SpringBoard after ~2 minutes.
void LBConfirmUsable(void);

// Registers this process with backboardd as the system app the way SpringBoard does
// (BKSSystemApplication: bootstrap, start, finishBooting). backboardd keeps its boot spinner
// up until a system app announces it has finished booting.
void LBBecomeSystemApp(void);

// Logs what UIKit/CoreAnimation know about the windows (context id, level, layer) and screen,
// to work out why the key window is not shown on screen.
void LBDumpWindowState(void);
