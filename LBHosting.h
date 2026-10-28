#import <UIKit/UIKit.h>

// Experimental FrontBoard app hosting; see LBHosting.m.
void LBHostingInit(void);
BOOL LBHostLaunch(NSString *bundleID);   // YES if a launch was started (falls back to SpringBoard on its own)
BOOL LBHostIsShowing(void);
void LBHostClose(void);
