#import <Foundation/Foundation.h>

// Calls `handler` on the main thread whenever the home button is pressed.
void LBHomeStartListening(void (^handler)(void));
