#import <UIKit/UIKit.h>
#import "../LBRun.m"

static int runHelper(void) {
	return LBRunRoot([NSBundle mainBundle].bundlePath, @"ctl/remove.sh", @"remove");
}

@interface RMController : UIViewController
@end

@implementation RMController {
	UILabel *_label;
}
- (void)viewDidLoad {
	[super viewDidLoad];
	self.view.backgroundColor = [UIColor blackColor];
	_label = [[UILabel alloc] initWithFrame:CGRectInset(self.view.bounds, 40, 0)];
	_label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	_label.numberOfLines = 0;
	_label.textAlignment = NSTextAlignmentCenter;
	_label.textColor = [UIColor whiteColor];
	_label.font = [UIFont systemFontOfSize:22];
	_label.text = @"Removing LiteBoard…";
	[self.view addSubview:_label];
}
- (void)viewDidAppear:(BOOL)animated {
	[super viewDidAppear:animated];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		int rc = runHelper();
		dispatch_async(dispatch_get_main_queue(), ^{
			_label.text = rc == 0
				? @"Done.\nSpringBoard restored, LiteBoard removed.\nThis app deletes itself in a few seconds."
				: [NSString stringWithFormat:@"Could not get root.\n%@\nOver SSH run:\nsh %@/ctl/remove.sh remove\n(or just reboot to get stock SpringBoard back)", LBRootLog(), [NSBundle mainBundle].bundlePath];
		});
	});
}
- (BOOL)prefersStatusBarHidden { return YES; }
@end

@interface RMDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation RMDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o {
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.rootViewController = [[RMController alloc] init];
	[self.window makeKeyAndVisible];
	return YES;
}
@end

int main(int argc, char **argv) {
	@autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass([RMDelegate class])); }
}
