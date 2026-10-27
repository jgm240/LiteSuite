#import "LBHome.h"
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

// IOHIDEvent is private on iOS; resolve the few symbols we need at runtime.
typedef void *IOHIDEventSystemClientRef;
typedef void *IOHIDEventRef;
typedef void (*IOHIDEventCallback)(void *target, void *refcon, void *sender, IOHIDEventRef event);

static IOHIDEventSystemClientRef (*pCreate)(CFAllocatorRef);
static void (*pSchedule)(IOHIDEventSystemClientRef, CFRunLoopRef, CFStringRef);
static void (*pRegister)(IOHIDEventSystemClientRef, IOHIDEventCallback, void *, void *);
static int (*pType)(IOHIDEventRef);
static int (*pInt)(IOHIDEventRef, uint32_t);

enum { kEventTypeKeyboard = 3 };
#define FIELD(type, n) (((type) << 16) | (n))
static const int kUsagePageConsumer = 0x0C, kUsageMenu = 0x40;

static void (^sHandler)(void);
static IOHIDEventSystemClientRef sClient;

static void onEvent(void *target, void *refcon, void *sender, IOHIDEventRef ev) {
	if (pType(ev) != kEventTypeKeyboard) return;
	if (pInt(ev, FIELD(kEventTypeKeyboard, 0)) != kUsagePageConsumer) return;
	if (pInt(ev, FIELD(kEventTypeKeyboard, 1)) != kUsageMenu) return;
	if (!pInt(ev, FIELD(kEventTypeKeyboard, 2))) return; // key up
	dispatch_async(dispatch_get_main_queue(), sHandler);
}

void LBHomeStartListening(void (^handler)(void)) {
	void *h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW);
	if (!h) return;
	pCreate = dlsym(h, "IOHIDEventSystemClientCreate");
	pSchedule = dlsym(h, "IOHIDEventSystemClientScheduleWithRunLoop");
	pRegister = dlsym(h, "IOHIDEventSystemClientRegisterEventCallback");
	pType = dlsym(h, "IOHIDEventGetType");
	pInt = dlsym(h, "IOHIDEventGetIntegerValue");
	if (!pCreate || !pSchedule || !pRegister || !pType || !pInt) return;

	sHandler = [handler copy];
	sClient = pCreate(kCFAllocatorDefault);
	if (!sClient) return;
	pSchedule(sClient, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
	pRegister(sClient, onEvent, NULL, NULL);
}
