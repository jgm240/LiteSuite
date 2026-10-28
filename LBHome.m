#import "LBHome.h"
#import "LBApplication.h"
#import "LBPrivate.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <math.h>
#import <pthread.h>

// IOHIDEvent is private on iOS; resolve the few symbols we need at runtime.
typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDEventRef;
typedef void (*IOHIDEventCallback)(void *target, void *refcon, void *sender, IOHIDEventRef event);

static IOHIDEventSystemClientRef (*pCreate)(CFAllocatorRef);
static void (*pSchedule)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef);
static void (*pRegister)(IOHIDEventSystemClientRef, IOHIDEventCallback, void *, void *);
static int (*pType)(IOHIDEventRef);
static int (*pInt)(IOHIDEventRef, uint32_t);
static float (*pFloat)(IOHIDEventRef, uint32_t);   // IOHIDFloat is float on 32-bit ARM

enum { kEventTypeKeyboard = 3, kEventTypeDigitizer = 11 };
#define FIELD(type, n) (((type) << 16) | (n))
static const int kUsagePageConsumer = 0x0C, kUsageMenu = 0x40;

static void (^sHandler)(void);
static IOHIDEventSystemClientRef sClient;

static void onEvent(void *target, void *refcon, void *sender, IOHIDEventRef ev) {
	int type = pType(ev);

	if (type == kEventTypeKeyboard) {
		if (pInt(ev, FIELD(kEventTypeKeyboard, 0)) != kUsagePageConsumer) return;
		if (pInt(ev, FIELD(kEventTypeKeyboard, 1)) != kUsageMenu) return;
		if (!pInt(ev, FIELD(kEventTypeKeyboard, 2))) return; // key up
		LBLog(@"hid: home button");
		LBRunOnMain(sHandler);
		return;
	}

	if (type == kEventTypeDigitizer) {
		// Raw touches straight from the HID system: UIKit's own event path is not wired up in this mode.
		float x = pFloat(ev, FIELD(kEventTypeDigitizer, 0)), y = pFloat(ev, FIELD(kEventTypeDigitizer, 1));
		int range = pInt(ev, FIELD(kEventTypeDigitizer, 8)), touch = pInt(ev, FIELD(kEventTypeDigitizer, 9));
		static int logged;
		if (logged < 40) { logged++; LBLog(@"hid digitizer: x=%.3f y=%.3f range=%d touch=%d", x, y, range, touch); }

		static BOOL down;
		static float startX, startY, lastX, lastY;
		if (touch && !down) { down = YES; startX = x; startY = y; }
		static BOOL dragging;
		if (touch && down) {
			if (fabsf(y - startY) > 0.015f || fabsf(x - startX) > 0.015f) dragging = YES;
			if (dragging && lastY != y) { CGPoint p = CGPointMake(x, y); CGFloat d = y - lastY; LBRunOnMain(^{ LBScrollAtNormalizedPoint(p, d); }); }
		}
		if (touch) { lastX = x; lastY = y; }
		if (!touch && down) {
			down = NO;
			BOOL wasDrag = dragging; dragging = NO;
			if (!wasDrag && fabsf(lastX - startX) < 0.015f && fabsf(lastY - startY) < 0.015f) {   // a tap, not a drag
				CGPoint p = CGPointMake(lastX, lastY);
				LBRunOnMain(^{ LBSyntheticTapAtNormalizedPoint(p); });
			}
		}
	}
}

// Runs on its own thread: UIKit leaves the main run loop in a private mode, where a client scheduled
// on the main loop in the default mode would never be called.
static void *hidThread(void *arg) {
	@autoreleasepool {
		sClient = pCreate(kCFAllocatorDefault);
		if (!sClient) { LBLog(@"hid: could not create client"); return NULL; }
		pSchedule(sClient, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
		pRegister(sClient, onEvent, NULL, NULL);
		LBLog(@"hid: listening for home button and touches");
		CFRunLoopRun();
	}
	return NULL;
}

void LBHomeStartListening(void (^handler)(void)) {
	void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
	if (!h) { LBLog(@"hid: IOKit not loadable"); return; }
	pCreate = dlsym(h, "IOHIDEventSystemClientCreate");
	pSchedule = dlsym(h, "IOHIDEventSystemClientScheduleWithRunLoop");
	pRegister = dlsym(h, "IOHIDEventSystemClientRegisterEventCallback");
	pType = dlsym(h, "IOHIDEventGetType");
	pInt = dlsym(h, "IOHIDEventGetIntegerValue");
	pFloat = dlsym(h, "IOHIDEventGetFloatValue");
	if (!pCreate || !pSchedule || !pRegister || !pType || !pInt || !pFloat) { LBLog(@"hid: symbols missing"); return; }

	sHandler = [handler copy];
	pthread_t t;
	pthread_create(&t, NULL, hidThread, NULL);
	pthread_detach(t);
}
