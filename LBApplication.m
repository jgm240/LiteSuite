#import "LBApplication.h"
#import "LBPrivate.h"

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
