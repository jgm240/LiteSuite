#import "LBApplication.h"
#import "LBPrivate.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

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
		if (first) { first = NO; LBLog(@"first touch event received"); }
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
	static BOOL done;
	if (done) return;
	done = YES;
	[@"1\n" writeToFile:@"/var/run/liteboard.confirmed" atomically:NO encoding:NSUTF8StringEncoding error:nil];
	LBLog(@"confirmed usable");
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
		if (!overlay) return NO;
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
	LBLog(@"rescue: spinner overlay dismissed=%d", LBDismissSpinnerOverlay());
}
