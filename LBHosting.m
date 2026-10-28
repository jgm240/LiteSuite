#import "LBHosting.h"
#import "LBApplication.h"
#import "LBPrivate.h"
#import <objc/message.h>
#import <objc/runtime.h>
#import <spawn.h>

// Experimental: host apps inside LiteBoard with FrontBoard (the framework SpringBoard uses for it) instead of
// handing the screen back to SpringBoard. Every step is logged; if no app scene shows up within 20s the caller
// falls back to the SpringBoard handoff.

#define SEND(ret, obj, sel, ...) ((ret (*)(id, SEL, ...))objc_msgSend)((obj), NSSelectorFromString(sel), ##__VA_ARGS__)

static id sProcess;
static UIView *sHostContainer, *sHostView;
static NSString *sHostBID;
static BOOL sHosting;

static void LBHostTearDown(void) {
	[sHostView removeFromSuperview]; sHostView = nil;
	[sHostContainer removeFromSuperview]; sHostContainer = nil;
	sHosting = NO;
}

void LBHostingInit(void) {
	@try {
		const char *names[] = { "FBSystemService", "FBProcessManager", "FBSceneManager", "FBApplicationLibrary", "FBDisplayManager", "FBWorkspaceConnectionListener", "FBSystemServiceServer", NULL };
		for (int i = 0; names[i]; i++) {
			Class c = objc_getClass(names[i]);
			id o = c ? SEND(id, c, @"sharedInstance") : nil;
			LBLog(@"hosting: %s sharedInstance -> %@", names[i], o ? [o description] : @"nil");
		}
	} @catch (NSException *e) { LBLog(@"hosting: init exception %@", e); }
}

static void LBHostFallback(NSString *bid) {
	LBHostTearDown();
	[bid writeToFile:@"/var/tmp/liteboard.open" atomically:YES encoding:NSUTF8StringEncoding error:nil];
	pid_t hp = 0;
	char *hargv[] = { "/usr/bin/liteboardctl", "handoff", NULL };
	extern char **environ;
	int rc = posix_spawn(&hp, hargv[0], NULL, NULL, hargv, environ);
	LBLog(@"hosting: falling back to SpringBoard handoff for %@ rc=%d", bid, rc);
}

static void LBHostPoll(int n) {
	if (!sHostBID) return;
	if (sHosting) return;
	@try {
		__block id found = nil;
		id sm = SEND(id, objc_getClass("FBSceneManager"), @"sharedInstance");
		void (^blk)(id) = ^(id scene) {
			NSString *ident = SEND(id, scene, @"identifier");
			LBLog(@"hosting: scene %@ client=%@", ident, SEND(id, scene, @"clientProcess"));
			if ([ident containsString:sHostBID]) found = scene;
		};
		SEND(void, sm, @"enumerateScenesWithBlock:", blk);
		if (found) {
			id hm = SEND(id, found, @"contextHostManager") ?: SEND(id, found, @"hostManager");
			UIView *v = SEND(id, hm, @"hostViewForRequester:enableAndOrderFront:", @"liteboard", YES);
			LBLog(@"hosting: host view %@ for %@", v, hm);
			UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
			if (v && w) {
				sHostContainer = [[UIView alloc] initWithFrame:w.bounds];
				sHostContainer.backgroundColor = [UIColor blackColor];
				v.frame = sHostContainer.bounds;
				[sHostContainer addSubview:v];
				[w addSubview:sHostContainer];
				sHostView = v; sHosting = YES;
				LBLog(@"hosting: showing hosted app %@", sHostBID);
				return;
			}
		}
	} @catch (NSException *e) { LBLog(@"hosting: poll exception %@", e); }
	if (n >= 20) { NSString *b = sHostBID; sHostBID = nil; LBHostFallback(b); return; }
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ LBRunOnMain(^{ LBHostPoll(n + 1); }); });
}

BOOL LBHostLaunch(NSString *bid) {
	@try {
		LBHostTearDown();
		id pm = SEND(id, objc_getClass("FBProcessManager"), @"sharedInstance");
		id ctx = [[objc_getClass("FBMutableProcessExecutionContext") alloc] init];
		sProcess = SEND(id, pm, @"createApplicationProcessForBundleID:withExecutionContext:", bid, ctx);
		LBLog(@"hosting: process for %@ -> %@", bid, sProcess);
		if (!sProcess) return NO;
		SEND(void, sProcess, @"bootstrapWithContext:", ctx);
		LBLog(@"hosting: bootstrapWithContext returned");
		sHostBID = bid;
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ LBRunOnMain(^{ LBHostPoll(1); }); });
		return YES;
	} @catch (NSException *e) { LBLog(@"hosting: launch exception %@", e); return NO; }
}

BOOL LBHostIsShowing(void) { return sHosting || sHostBID != nil; }

void LBHostClose(void) {
	@try {
		if (sProcess) SEND(void, sProcess, @"killForReason:andReport:withDescription:", 1, NO, @"liteboard home");
	} @catch (NSException *e) { LBLog(@"hosting: kill exception %@", e); }
	sProcess = nil; sHostBID = nil;
	LBHostTearDown();
}
