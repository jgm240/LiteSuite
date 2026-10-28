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

// Runs after launch in daemon mode. The rescue launch skips UIKit's scene setup, which is what normally
// binds each UIWindow to a CAContext on the display (the logs show contextId=0). Tries UIKit's own
// -[UIWindow _createContextAttached:], and if the window still has no context creates a CAContext by hand
// and hosts the window's layer in it. Also logs the context-related methods UIKit/CoreAnimation offer.
void LBAttachWindowContext(void);

// Logs GraphicsServices' and UIScreen's idea of the screen (pixel/point size, scale, orientation).
void LBLogScreenInfo(NSString *tag);

// The window renders at UIScreen scale 1.0 (bounds 768x1024) on a panel that is 2048x1536 pixels, so it
// covers only a quarter of the display. Scales the window layer up by (panel pixels / UIScreen points).
void LBFitWindowToScreen(void);

// Runs a block on the main thread in every run loop mode that exists. UIKit parks the main loop in a
// private mode (UIInitializationRunLoopMode) that the main dispatch queue is not serviced in.
void LBRunOnMain(void (^block)(void));

// Pops UIInitializationRunLoopMode, which UIKit pushes at startup and pops when launch completes; the
// rescue launch never completes it, so default-mode timers and the main queue never ran.
void LBPopInitMode(void);

// Logs whether the event-port Mach services we declared were really checked in, plus the app's
// activation state (UIKit does not deliver touches to an inactive app).
void LBProbeSystem(void);
void LBDumpHostingClasses(void);

// A tap at a point given as 0..1 fractions of the panel's native (landscape) orientation. Maps it through the
// window transform, hit-tests the window and activates the control or cell under it. Skipped once UIKit
// delivers touches itself.
void LBSyntheticTapAtNormalizedPoint(CGPoint p);
void LBScrollAtNormalizedPoint(CGPoint p, CGFloat dyNormalized);

// Sets contentScaleFactor on every view of every window so text and images render at the panel's 2x.
void LBRescaleViews(void);
