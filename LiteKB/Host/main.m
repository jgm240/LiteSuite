#import <UIKit/UIKit.h>

// Container app for the LiteKB-only IPA: iOS only installs a keyboard extension inside an app.
@interface KBHostDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation KBHostDelegate
- (BOOL)application:(UIApplication *)app didFinishLaunchingWithOptions:(NSDictionary *)opts {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	UIViewController *vc = [[UIViewController alloc] init];
	vc.view.backgroundColor = [UIColor whiteColor];
	UILabel *l = [[UILabel alloc] initWithFrame:CGRectInset(vc.view.bounds, 24, 24)];
	l.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	l.numberOfLines = 0;
	l.textAlignment = NSTextAlignmentCenter;
	l.text = @"LiteKB is installed.\n\nEnable it in Settings > General > Keyboard > Keyboards > Add New Keyboard.";
	[vc.view addSubview:l];
	self.window.rootViewController = vc;
	[self.window makeKeyAndVisible];
	return YES;
}
@end

int main(int argc, char *argv[]) {
	@autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([KBHostDelegate class])); }
}
