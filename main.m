#import "LBPrivate.h"
#import "LBAppDelegate.h"

BOOL LBReplaceMode;

void LBLog(NSString *format, ...) {
	va_list ap;
	va_start(ap, format);
	NSString *msg = [[NSString alloc] initWithFormat:format arguments:ap];
	va_end(ap);
	fprintf(stderr, "[LiteBoard] %s (uid=%d pid=%d)\n", msg.UTF8String, getuid(), getpid());
	fflush(stderr);
}

int main(int argc, char **argv) {
	@autoreleasepool {
		LBReplaceMode = getenv("LITEBOARD_REPLACE") != NULL
			|| [[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"];
		LBLog(@"main: replace=%d, calling UIApplicationMain", LBReplaceMode);
		return UIApplicationMain(argc, argv, nil, NSStringFromClass([LBAppDelegate class]));
	}
}
