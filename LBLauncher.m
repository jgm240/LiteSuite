#import "LBLauncher.h"
#import "LBAppDelegate.h"
#import "LBPrivate.h"
#import "LBHosting.h"
#import <dlfcn.h>
#import <spawn.h>
#import <signal.h>
#import <unistd.h>
#import <sys/wait.h>

static const uid_t kMobileUID = 501;
static pid_t sChild;
static dispatch_source_t sExitWatch;

extern char **environ;

@implementation LBLauncher

+ (void)launchBundleID:(NSString *)bundleID {
	if (!LBReplaceMode) {
		// Running on top of stock SpringBoard (stage-1 testing): let it do the launch.
		[[LSApplicationWorkspace defaultWorkspace] openApplicationWithBundleID:bundleID];
		return;
	}
	LBLog(@"launch: %@ (child=%d)", bundleID, sChild);
	// Nothing hosts an app's window without SpringBoard (a forked app froze the screen on a spinner), so hand
	// the screen back to SpringBoard and have it open the app. A reboot brings LiteBoard back (Permanent).
	if (LBHostLaunch(bundleID)) return;
	{
		[bundleID writeToFile:@"/var/tmp/liteboard.open" atomically:YES encoding:NSUTF8StringEncoding error:nil];
		pid_t hp = 0;
		char *hargv[] = { "/usr/bin/liteboardctl", "handoff", NULL };
		int rc = posix_spawn(&hp, hargv[0], NULL, NULL, hargv, environ);
		LBLog(@"launch: handoff to SpringBoard for %@ rc=%d pid=%d", bundleID, rc, hp);
		return;
	}
	if (sChild > 0) return;

	LSApplicationProxy *proxy = [LSApplicationProxy applicationProxyForIdentifier:bundleID];
	NSString *exe = [proxy.bundleURL.path stringByAppendingPathComponent:proxy.bundleExecutable];
	NSString *home = proxy.dataContainerURL.path ?: @"/var/mobile";
	if (!proxy || !proxy.bundleExecutable) { LBLog(@"launch: no executable for %@", bundleID); return; }

	// Build everything the child needs before fork(); no ObjC after it.
	const char *cexe = strdup(exe.fileSystemRepresentation);
	const char *chome = strdup(home.fileSystemRepresentation);
	NSMutableArray *env = [NSMutableArray arrayWithObjects:
		[@"HOME=" stringByAppendingString:home],
		[@"CFFIXED_USER_HOME=" stringByAppendingString:home],
		[@"TMPDIR=" stringByAppendingPathComponent:[home stringByAppendingString:@"/tmp/"]],
		@"PATH=/usr/bin:/bin:/usr/sbin:/sbin", @"USER=mobile", nil];
	char *envp[16] = { 0 };
	for (NSUInteger i = 0; i < env.count && i < 15; i++) envp[i] = strdup([env[i] UTF8String]);
	char *argv[2] = { (char *)cexe, NULL };

	// fork() is marked unavailable in the iOS SDK headers but works for root platform binaries.
	pid_t (*sys_fork)(void) = dlsym(RTLD_DEFAULT, "fork");
	if (!sys_fork) return;
	pid_t pid = sys_fork();
	if (pid == 0) {
		setgid(kMobileUID);
		setuid(kMobileUID);
		chdir(chome);
		execve(cexe, argv, envp);
		_exit(127);
	}
	if (pid < 0) return;

	sChild = pid;
	LBLog(@"launch: forked pid %d for %@", pid, exe);
	[(LBAppDelegate *)[UIApplication sharedApplication].delegate hideHome];

	sExitWatch = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, pid, DISPATCH_PROC_EXIT, dispatch_get_main_queue());
	dispatch_source_set_event_handler(sExitWatch, ^{
		int st; waitpid(sChild, &st, WNOHANG);
		LBLog(@"launch: child exited status=0x%x", st);
		sChild = 0;
		dispatch_source_cancel(sExitWatch);
		sExitWatch = nil;
		[(LBAppDelegate *)[UIApplication sharedApplication].delegate showHome];
	});
	dispatch_resume(sExitWatch);
}

+ (void)goHome {
	if (LBHostIsShowing()) { LBHostClose(); return; }
	if (sChild > 0) {
		pid_t p = sChild;
		kill(p, SIGTERM);
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			if (sChild == p) kill(p, SIGKILL);
		});
	} else {
		[(LBAppDelegate *)[UIApplication sharedApplication].delegate showHome];
	}
}

@end
