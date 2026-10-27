#import <Foundation/Foundation.h>

// Runs `<appPath>/<scriptRel> <arg>` as root, trying in order: the setuid helper
// `<appPath>/lbroot`, then `su root` with the default password "alpine".
// Returns the script's exit status, or -1 if no method got root.
int LBRunRoot(NSString *appPath, NSString *scriptRel, NSString *arg);

// What each attempt printed/returned during the last LBRunRoot call, for error dialogs.
NSString *LBRootLog(void);
