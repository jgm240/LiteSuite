#import "LBPrivate.h"
#import "LBAppDelegate.h"
#import <execinfo.h>
#import <signal.h>

BOOL LBReplaceMode;

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

		LBLog(@"main: replace=%d, calling UIApplicationMain", LBReplaceMode);
		return UIApplicationMain(argc, argv, nil, NSStringFromClass([LBAppDelegate class]));
	}
}
