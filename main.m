#import "LBPrivate.h"
#import "LBAppDelegate.h"
#import "LBApplication.h"
#import <execinfo.h>
#import <signal.h>

BOOL LBReplaceMode;
volatile int LBLaunched;

extern int lbunzip_extract(const char *ipa, const char *dest);

void LBLog(NSString *format, ...) {
	va_list ap;
	va_start(ap, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);
	fprintf(stderr, "[LiteBoard] %s (uid=%d pid=%d)\n", msg.UTF8String, getuid(), getpid());
	fflush(stderr);
}

// Crash diagnostics go to /var/log/liteboard.log with symbol names where the system exports them.
static void onFatalSignal(int sig) {
	void *frames[48];
	int n = backtrace(frames, 48);
	fprintf(stderr, "[LiteBoard] fatal signal %d, backtrace:\n", sig);
	fflush(stderr);
	backtrace_symbols_fd(frames, n, STDERR_FILENO);
	signal(sig, SIG_DFL);
	raise(sig);
}

static void onException(NSException *e) {
	LBLog(@"uncaught exception: %@\n%@", e, e.callStackSymbols);
}

int main(int argc, char **argv) {
	// `LiteBoard --unzip <ipa> <dir>`: used by ctl/setup.sh to install updates; no UI is started.
	if (argc == 4 && strcmp(argv[1], "--unzip") == 0) return lbunzip_extract(argv[2], argv[3]);
	// `LiteBoard --bundle-id`: lets ctl/setup.sh declare the right Mach service names.
	if (argc == 2 && strcmp(argv[1], "--bundle-id") == 0) {
		@autoreleasepool { printf("%s\n", [NSBundle mainBundle].bundleIdentifier.UTF8String); }
		return 0;
	}
	@autoreleasepool {
		BOOL daemon = getenv("LITEBOARD_REPLACE") != NULL;
		LBReplaceMode = daemon || [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"];
		if (daemon) {
			signal(SIGABRT, onFatalSignal);
			signal(SIGSEGV, onFatalSignal);
			signal(SIGBUS, onFatalSignal);
			NSSetUncaughtExceptionHandler(onException);
		}

		// Launched by launchd with no SpringBoard running, UIKit aborts in GraphicsServices
		// because it expects SpringBoard to serve the system event port. UIKit registers that
		// port itself when the main bundle is com.apple.springboard, so present that identity.
		// Set LITEBOARD_NO_SPOOF=1 in the daemon plist to turn this off.
		if (daemon && !getenv("LITEBOARD_NO_SPOOF")) {
			NSMutableDictionary *info = (NSMutableDictionary *)[NSBundle mainBundle].infoDictionary;
			if ([info isKindOfClass:[NSMutableDictionary class]]) {
				info[@"CFBundleIdentifier"] = @"com.apple.springboard";
			}
			LBLog(@"bundle id is now %@", [NSBundle mainBundle].bundleIdentifier);
		}

		if (daemon) {
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ LBRescueLaunch(); });
			// Log a heartbeat from a background thread. If UIKit never reaches
			// didFinishLaunching (blocked waiting on a service SpringBoard used to provide),
			// abort after ~24s (before the 30s watchdog grace ends) so the crash report shows what the main thread was waiting on.
			dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
				for (int i = 1; i <= 10; i++) {
					sleep(3);
					LBLog(@"tick %d: launched=%d", i, LBLaunched);
					if (i == 8 && !LBLaunched) {
						LBLog(@"UIKit never finished launching; aborting for a stack trace");
						abort();
					}
				}
			});
		}
		LBLog(@"main: replace=%d, calling UIApplicationMain", LBReplaceMode);
		// In daemon mode UIKit takes its SpringBoard path, so use our SpringBoard-compatible application class.
		NSString *appClass = LBReplaceMode ? NSStringFromClass([LBApplication class]) : nil;
		return UIApplicationMain(argc, argv, appClass, NSStringFromClass([LBAppDelegate class]));
	}
}
