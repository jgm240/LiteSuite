#import "LBApplication.h"
#import "LBPrivate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/stat.h>

static BOOL sUIKitTouchSeen;

@implementation LBApplication {
	NSHashTable *_orientationObservers;
	NSMutableSet<NSString *> *_seen;
}

// Real implementations for the SpringBoard-only methods we know about.
- (void)addActiveOrientationObserver:(id)observer {
	if (!_orientationObservers) _orientationObservers = [NSHashTable weakObjectsHashTable];
	[_orientationObservers addObject:observer];
}

- (void)removeActiveOrientationObserver:(id)observer {
	[_orientationObservers removeObject:observer];
}

// Any touch means the display and the event path both work.
- (void)sendEvent:(UIEvent *)event {
	if (event.type == UIEventTypeTouches) {
		static BOOL first = YES;
		if (first) { first = NO; sUIKitTouchSeen = YES; LBLog(@"first touch event received (UIKit path)"); }
		LBConfirmUsable();
	}
	[super sendEvent:event];
}

// Everything else UIKit asks of "SpringBoard": log it once, return nil/0/NO.
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
	NSMethodSignature *known = [super methodSignatureForSelector:sel];
	if (known) return known;
	NSUInteger args = [[NSStringFromSelector(sel) componentsSeparatedByString:@":"] count] - 1;
	NSMutableString *types = [NSMutableString stringWithString:@"@@:"];
	for (NSUInteger i = 0; i < args; i++) [types appendString:@"@"];
	return [NSMethodSignature signatureWithObjCTypes:types.UTF8String];
}

- (void)forwardInvocation:(NSInvocation *)inv {
	NSString *name = NSStringFromSelector(inv.selector);
	if (!_seen) _seen = [NSMutableSet set];
	if (![_seen containsObject:name]) {
		[_seen addObject:name];
		LBLog(@"SpringBoard-only selector ignored: -[UIApplication %@]", name);
	}
	id nothing = nil;
	[inv setReturnValue:&nothing];
}

@end

void LBConfirmUsable(void) {
	extern char LBFBTryPath[160];
	if (LBFBTryPath[0]) unlink(LBFBTryPath);   // FrontBoard start-up worked: keep using it
	static BOOL done;
	if (done) return;
	done = YES;
	[@"1\n" writeToFile:@"/var/run/liteboard.confirmed" atomically:NO encoding:NSUTF8StringEncoding error:nil];
	LBLog(@"confirmed usable");
}

static id sSystemApp;   // BKSSystemApplication, kept alive for the life of the process

static BOOL LBCall(id target, NSString *selector) {
	SEL sel = NSSelectorFromString(selector);
	if (![target respondsToSelector:sel]) { LBLog(@"system app: %@ does not respond to %@", [target class], selector); return NO; }
	@try {
		((void (*)(id, SEL))objc_msgSend)(target, sel);
		LBLog(@"system app: %@ returned", selector);
		return YES;
	} @catch (NSException *e) {
		LBLog(@"system app: %@ threw %@", selector, e);
		return NO;
	}
}

void LBBecomeSystemApp(void) {
	static BOOL once;
	if (once) return;
	once = YES;
	dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
	Class cls = NSClassFromString(@"BKSSystemApplication");
	if (!cls) { LBLog(@"system app: BKSSystemApplication missing"); return; }
	@try {
		// A private queue: UIKit never leaves UIInitializationRunLoopMode here, so the main queue is not serviced.
		dispatch_queue_t q = dispatch_queue_create("com.liteboard.systemapp", DISPATCH_QUEUE_SERIAL);
		sSystemApp = ((id (*)(id, SEL, id))objc_msgSend)([cls alloc], NSSelectorFromString(@"initWithQueue:"), q);
		LBLog(@"system app: created %@", sSystemApp);
		LBCall(sSystemApp, @"bootstrap");
		LBCall(sSystemApp, @"start");
		LBCall(sSystemApp, @"finishBooting");
	} @catch (NSException *e) {
		LBLog(@"system app: exception %@", e);
	}
	// Older/alternate entry point; its signature is not known, so only call it if present.
	void *fn = dlsym(RTLD_DEFAULT, "BKSDisplayServicesStart");
	LBLog(@"system app: BKSDisplayServicesStart %s", fn ? "present (not called)" : "missing");
	LBDumpWindowState();
}

BOOL LBDismissSpinnerOverlay(void) {
	static BOOL loaded;
	if (!loaded) {
		loaded = YES;
		dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
	}
	@try {
		Class displayClass = NSClassFromString(@"CADisplay");
		Class overlayClass = NSClassFromString(@"BKSDisplayRenderOverlay");
		if (!displayClass || !overlayClass) { LBLog(@"overlay: classes missing (CADisplay=%@ overlay=%@)", displayClass, overlayClass); return NO; }
		id display = ((id (*)(id, SEL))objc_msgSend)(displayClass, NSSelectorFromString(@"mainDisplay"));
		id overlay = ((id (*)(id, SEL, id))objc_msgSend)(overlayClass, NSSelectorFromString(@"existingOverlayForDisplay:"), display);
		if (!overlay) {
			static BOOL said;
			if (!said) { said = YES; LBLog(@"overlay: none for display %@", display); }
			return NO;
		}
		LBLog(@"overlay: found %@, dismissing", overlay);
		((void (*)(id, SEL))objc_msgSend)(overlay, NSSelectorFromString(@"dismiss"));
		return YES;
	} @catch (NSException *e) {
		LBLog(@"overlay: exception %@", e);
		return NO;
	}
}

void LBRescueLaunch(void) {
	if (LBLaunched) return;
	UIApplication *app = [UIApplication sharedApplication];
	LBLog(@"rescue: not launched after 3s (app=%@ delegate=%@ state=%ld)", app, app.delegate, (long)app.applicationState);

	NSArray *keys = @[@"aunch", @"cene", @"orkspace", @"pringBoard", @"inishLaunching", @"ctivat", @"ransaction"];
	for (Class c = [app class]; c && c != [NSObject class]; c = class_getSuperclass(c)) {
		unsigned n = 0;
		Method *ms = class_copyMethodList(c, &n);
		for (unsigned i = 0; i < n; i++) {
			NSString *name = NSStringFromSelector(method_getName(ms[i]));
			for (NSString *k in keys) {
				if ([name rangeOfString:k].location != NSNotFound) { LBLog(@"  %s  -%@", class_getName(c), name); break; }
			}
		}
		free(ms);
	}

	@try {
		BOOL ok = [app.delegate application:app didFinishLaunchingWithOptions:@{}];
		LBLog(@"rescue: delegate returned %d, launched=%d", ok, LBLaunched);
	} @catch (NSException *e) {
		LBLog(@"rescue: exception %@\n%@", e, e.callStackSymbols);
	}
	LBBecomeSystemApp();
	LBLog(@"rescue: spinner overlay dismissed=%d", LBDismissSpinnerOverlay());
	LBPopInitMode();
}

void LBDumpWindowState(void) {
	UIApplication *app = [UIApplication sharedApplication];
	LBLog(@"windows: %@", app.windows);
	for (UIWindow *w in app.windows) {
		unsigned ctx = 0;
		SEL cs = NSSelectorFromString(@"_contextId");
		if ([w respondsToSelector:cs]) ctx = ((unsigned (*)(id, SEL))objc_msgSend)(w, cs);
		LBLog(@"  window %p level=%.0f contextId=%u hidden=%d alpha=%.1f layer=%@ rootVC=%@", w, w.windowLevel, ctx, w.hidden, w.alpha, w.layer, w.rootViewController);
	}
	Class ca = NSClassFromString(@"CAContext");
	SEL all = NSSelectorFromString(@"allContexts");
	if ([ca respondsToSelector:all]) LBLog(@"CAContext allContexts: %@", ((id (*)(id, SEL))objc_msgSend)(ca, all));
	LBLog(@"screen: %@ scale=%.1f", [UIScreen mainScreen], [UIScreen mainScreen].scale);
}

extern CGSize GSMainScreenPixelSize(void);
extern CGSize GSMainScreenPointSize(void);
extern CGFloat GSMainScreenScaleFactor(void);
extern int GSMainScreenOrientation(void);
extern CGAffineTransform GSMainScreenWindowTransform(void);

extern void GSEventPopRunLoopMode(CFStringRef mode);
extern kern_return_t bootstrap_look_up(mach_port_t bp, const char *name, mach_port_t *sp);
extern mach_port_t bootstrap_port;

static CGAffineTransform sFit = {1, 0, 0, 1, 0, 0};   // portrait points -> native panel pixels
static CGSize sPanel;                                  // native (landscape) panel size in pixels

static id sManualContext;   // keeps a hand-made CAContext alive

static void LBLogMethods(Class cls, BOOL meta, NSArray *keys, NSString *tag, int limit) {
	Class target = meta ? object_getClass(cls) : cls;
	unsigned n = 0;
	Method *ms = class_copyMethodList(target, &n);
	int shown = 0;
	for (unsigned i = 0; i < n && shown < limit; i++) {
		NSString *name = NSStringFromSelector(method_getName(ms[i]));
		for (NSString *k in keys) {
			if ([name rangeOfString:k options:NSCaseInsensitiveSearch].location != NSNotFound) {
				LBLog(@"  %@ %c%@", tag, meta ? '+' : '-', name);
				shown++;
				break;
			}
		}
	}
	free(ms);
}

void LBAttachWindowContext(void) {
	static BOOL once;
	if (once) return;
	once = YES;
	UIApplication *app = [UIApplication sharedApplication];
	UIWindow *w = app.windows.firstObject;
	if (!w) { LBLog(@"attach: no window"); return; }

	LBLogMethods([UIWindow class], NO, @[@"context"], @"UIWindow", 40);
	LBLogMethods([UIScreen class], NO, @[@"context", @"binder", @"display"], @"UIScreen", 30);
	Class ca = NSClassFromString(@"CAContext");
	LBLogMethods(ca, YES, @[@"context", @"display"], @"CAContext", 20);
	LBLogMethods(ca, NO, @[@"layer", @"level", @"display", @"contextId"], @"CAContext", 20);
	Class binder = NSClassFromString(@"_UIContextBinder");
	LBLog(@"attach: _UIContextBinder=%@", binder);
	if (binder) LBLogMethods(binder, NO, @[@""], @"_UIContextBinder", 40);

	SEL cid = NSSelectorFromString(@"_contextId");
	unsigned (^ctxId)(void) = ^unsigned {
		return [w respondsToSelector:cid] ? ((unsigned (*)(id, SEL))objc_msgSend)(w, cid) : 0u;
	};
	LBLog(@"attach: contextId before = %u", ctxId());

	// A. UIKit's own
	SEL create = NSSelectorFromString(@"_createContextAttached:");
	if ([w respondsToSelector:create]) {
		@try { ((void (*)(id, SEL, BOOL))objc_msgSend)(w, create, YES); }
		@catch (NSException *e) { LBLog(@"attach: _createContextAttached: threw %@", e); }
		LBLog(@"attach: after _createContextAttached: contextId = %u", ctxId());
	} else {
		LBLog(@"attach: UIWindow has no _createContextAttached:");
	}
	if (ctxId() != 0) return;

	// B. by hand: a remote CAContext hosting the window's layer. Needs com.apple.QuartzCore.displayable-context.
	@try {
		id ctx = ((id (*)(id, SEL, id))objc_msgSend)(ca, NSSelectorFromString(@"remoteContextWithOptions:"), @{});
		if (!ctx) { LBLog(@"attach: remoteContextWithOptions: returned nil"); return; }
		[ctx setValue:w.layer forKey:@"layer"];
		[ctx setValue:@(100000) forKey:@"level"];
		sManualContext = ctx;
		LBLog(@"attach: manual CAContext %@ contextId=%@ level=%@", ctx, [ctx valueForKey:@"contextId"], [ctx valueForKey:@"level"]);
	} @catch (NSException *e) {
		LBLog(@"attach: manual CAContext threw %@", e);
	}
}

void LBLogScreenInfo(NSString *tag) {
	CGSize px = GSMainScreenPixelSize(), pt = GSMainScreenPointSize();
	CGAffineTransform wt = GSMainScreenWindowTransform();
	LBLog(@"screen[%@]: GS pixel=%.0fx%.0f point=%.0fx%.0f scale=%.2f orientation=%d windowTransform=%@", tag, px.width, px.height, pt.width, pt.height, GSMainScreenScaleFactor(), GSMainScreenOrientation(), NSStringFromCGAffineTransform(wt));
	// Touching UIScreen before UIKit has launched would create it with default values; GS getters only until then.
	if (!LBLaunched || ![NSThread isMainThread]) return;
	UIScreen *sc = [UIScreen mainScreen];
	LBLog(@"screen[%@]: UIScreen bounds=%@ nativeBounds=%@ scale=%.2f nativeScale=%.2f mode=%@", tag, NSStringFromCGRect(sc.bounds), NSStringFromCGRect(sc.nativeBounds), sc.scale, sc.nativeScale, sc.currentMode);
}

void LBFitWindowToScreen(void) {
	UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
	UIScreen *sc = [UIScreen mainScreen];
	if (!w) return;
	// GraphicsServices has the real geometry: portrait pixels, scale 2, and a window transform that rotates
	// portrait into the panel's native landscape framebuffer. UIScreen reports scale 1.0 in this mode.
	CGSize px = GSMainScreenPixelSize();
	CGAffineTransform rot = GSMainScreenWindowTransform();
	CGRect b = sc.bounds;
	CGFloat f = b.size.width > 0 ? px.width / b.size.width : 1;
	CGAffineTransform t = CGAffineTransformConcat(CGAffineTransformMakeScale(f, f), rot);
	CGRect r = CGRectApplyAffineTransform(CGRectMake(0, 0, b.size.width, b.size.height), t);
	t.tx -= r.origin.x;   // bring the rotated rect back into the positive quadrant
	t.ty -= r.origin.y;
	w.layer.anchorPoint = CGPointMake(0, 0);
	w.layer.position = CGPointMake(0, 0);
	w.layer.affineTransform = t;
	sFit = t;
	sPanel = CGSizeMake(MAX(px.width, px.height), MIN(px.width, px.height));
	LBLog(@"fit: scale %.2f, GS window transform %@ -> layer transform %@, panel %.0fx%.0f", f, NSStringFromCGAffineTransform(rot), NSStringFromCGAffineTransform(t), sPanel.width, sPanel.height);
	LBRescaleViews();
}

void LBRunOnMain(void (^block)(void)) {
	CFArrayRef modes = CFRunLoopCopyAllModes(CFRunLoopGetMain());
	CFRunLoopPerformBlock(CFRunLoopGetMain(), modes, block);
	CFRunLoopWakeUp(CFRunLoopGetMain());
	if (modes) CFRelease(modes);
}

void LBPopInitMode(void) {
	GSEventPopRunLoopMode(CFSTR("UIInitializationRunLoopMode"));
	LBLog(@"popped UIInitializationRunLoopMode");
}

void LBProbeSystem(void) {
	const char *names[] = { "PurpleSystemAppPort", "com.apple.springboard.gsEvents", "com.apple.UIKit.statusbarserver",
	                        "com.apple.UIKit.KeyboardManagement.hosted", "com.apple.springboard.UIKit.migserver", "com.apple.springboard", NULL };
	for (int i = 0; names[i]; i++) {
		mach_port_t p = MACH_PORT_NULL;
		kern_return_t kr = bootstrap_look_up(bootstrap_port, names[i], &p);
		LBLog(@"probe: %s -> kr=%d port=%u", names[i], kr, p);
	}
	UIApplication *app = [UIApplication sharedApplication];
	SEL act = NSSelectorFromString(@"_isActivated"), acting = NSSelectorFromString(@"_isActivating");
	BOOL a = [app respondsToSelector:act] ? ((BOOL (*)(id, SEL))objc_msgSend)(app, act) : NO;
	BOOL b = [app respondsToSelector:acting] ? ((BOOL (*)(id, SEL))objc_msgSend)(app, acting) : NO;
	LBLog(@"probe: applicationState=%ld _isActivated=%d _isActivating=%d", (long)app.applicationState, a, b);
}

static void LBRescale(UIView *v, CGFloat s) {
	if (v.contentScaleFactor != s) v.contentScaleFactor = s;
	for (UIView *sub in v.subviews) LBRescale(sub, s);
}

void LBRescaleViews(void) {
	CGFloat s = GSMainScreenScaleFactor();
	if (s < 1.01) return;
	for (UIWindow *w in [UIApplication sharedApplication].windows) LBRescale(w, s);
}

void LBSyntheticTapAtNormalizedPoint(CGPoint n) {
	if (sUIKitTouchSeen) return;   // UIKit is delivering touches itself
	UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
	if (!w || sPanel.width <= 0) return;
	// The digitizer reports 0..1 in the upright portrait orientation (log: a tap on the top-right gear read x=.95 y=.03).
	CGPoint pt = CGPointMake(n.x * w.bounds.size.width, n.y * w.bounds.size.height);
	UIView *hit = [w hitTest:pt withEvent:nil];
	LBLog(@"tap: norm=(%.3f,%.3f) point=(%.0f,%.0f) hit=%@", n.x, n.y, pt.x, pt.y, hit);
	LBConfirmUsable();
	for (UIView *v = hit; v; v = v.superview) {
		if ([v isKindOfClass:[UIControl class]]) { [(UIControl *)v sendActionsForControlEvents:UIControlEventTouchUpInside]; return; }
		if ([v isKindOfClass:[UICollectionViewCell class]]) {
			UIView *p = v.superview;
			while (p && ![p isKindOfClass:[UICollectionView class]]) p = p.superview;
			UICollectionView *cv = (UICollectionView *)p;
			NSIndexPath *ip = [cv indexPathForCell:(UICollectionViewCell *)v];
			if (ip && [cv.delegate respondsToSelector:@selector(collectionView:didSelectItemAtIndexPath:)])
				[cv.delegate collectionView:cv didSelectItemAtIndexPath:ip];
			return;
		}
		if ([v isKindOfClass:[UITableViewCell class]]) {
			UIView *p = v.superview;
			while (p && ![p isKindOfClass:[UITableView class]]) p = p.superview;
			UITableView *tv = (UITableView *)p;
			NSIndexPath *ip = [tv indexPathForCell:(UITableViewCell *)v];
			if (ip && [tv.delegate respondsToSelector:@selector(tableView:didSelectRowAtIndexPath:)])
				[tv.delegate tableView:tv didSelectRowAtIndexPath:ip];
			return;
		}
	}
}

// Finger drag: scroll the scroll view under the finger by dy points (positive = content moves up).
void LBScrollAtNormalizedPoint(CGPoint n, CGFloat dyNormalized) {
	if (sUIKitTouchSeen) return;
	UIWindow *w = [UIApplication sharedApplication].windows.firstObject;
	if (!w) return;
	CGPoint pt = CGPointMake(n.x * w.bounds.size.width, n.y * w.bounds.size.height);
	for (UIView *v = [w hitTest:pt withEvent:nil]; v; v = v.superview) {
		if (![v isKindOfClass:[UIScrollView class]]) continue;
		UIScrollView *sv = (UIScrollView *)v;
		CGFloat maxY = MAX(0, sv.contentSize.height - sv.bounds.size.height + sv.contentInset.bottom);
		CGFloat y = sv.contentOffset.y - dyNormalized * w.bounds.size.height;
		sv.contentOffset = CGPointMake(sv.contentOffset.x, MIN(MAX(y, -sv.contentInset.top), maxY));
		return;
	}
}

// Writes every class (with methods) from the frameworks SpringBoard uses to host apps to a file next to the
// crash reports, so the app-hosting design can be worked out from the device's real private API.
void LBDumpHostingClasses(void) {
	const char *fw[] = { "FrontBoard", "FrontBoardServices", "BackBoardServices", "AssertionServices", "SpringBoardServices", "BaseBoard", "BaseBoardUI", "FrontBoardUI", NULL };
	for (int i = 0; fw[i]; i++) {
		char path[256];
		snprintf(path, sizeof path, "/System/Library/PrivateFrameworks/%s.framework/%s", fw[i], fw[i]);
		void *h = dlopen(path, RTLD_NOW);
		LBLog(@"classes: dlopen %s -> %s", fw[i], h ? "ok" : "no");
	}
	FILE *f = fopen("/var/mobile/Library/Logs/CrashReporter/LiteBoard-classes.ips", "w");
	if (!f) return;
	unsigned n = 0;
	Class *cs = objc_copyClassList(&n);
	for (unsigned i = 0; i < n; i++) {
		const char *img = class_getImageName(cs[i]);
		if (!img) continue;
		BOOL want = NO;
		for (int k = 0; fw[k]; k++) { char m[128]; snprintf(m, sizeof m, "/%s.framework/", fw[k]); if (strstr(img, m)) want = YES; }
		if (!want) continue;
		Class sup = class_getSuperclass(cs[i]);
		fprintf(f, "@interface %s : %s  // %s\n", class_getName(cs[i]), sup ? class_getName(sup) : "-", img);
		for (int meta = 1; meta >= 0; meta--) {
			Class c = meta ? object_getClass(cs[i]) : cs[i];
			unsigned mc = 0;
			Method *ms = class_copyMethodList(c, &mc);
			for (unsigned j = 0; j < mc; j++)
				fprintf(f, "%s %s  %s\n", meta ? "+" : "-", sel_getName(method_getName(ms[j])), method_getTypeEncoding(ms[j]) ?: "");
			free(ms);
		}
		fprintf(f, "@end\n");
	}
	free(cs);
	fclose(f);
	chmod("/var/mobile/Library/Logs/CrashReporter/LiteBoard-classes.ips", 0644);
	LBLog(@"classes: dumped %u classes total scanned", n);
}
