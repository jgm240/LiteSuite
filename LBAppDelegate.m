#import "LBAppDelegate.h"
#import "LBGridController.h"
#import "LBLauncher.h"
#import "LBHome.h"
#import "LBRun.h"
#import "LBSettingsController.h"
#import "LBApplication.h"
#import "LBUpdater.h"
#import "LBPrivate.h"

#define LB_HEARTBEAT_PATH "/var/run/liteboard.alive"

@implementation LBAppDelegate {
	NSTimer *_heartbeat;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
	LBLaunched = 1;
	LBLog(@"didFinishLaunching reached");
	self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
	self.window.backgroundColor = LBReplaceMode ? [UIColor colorWithRed:0.05 green:0.1 blue:0.4 alpha:1] : [UIColor blackColor]; // navy: recognisable if it ever reaches the screen
	if (LBReplaceMode) self.window.windowLevel = 100000; // above any boot/overlay layer
	self.window.rootViewController = [[LBGridController alloc] init];
	[self.window makeKeyAndVisible];
	LBLog(@"window: frame=%@ hidden=%d key=%d screen=%@", NSStringFromCGRect(self.window.frame), self.window.hidden, self.window.isKeyWindow, [UIScreen mainScreen]);
	[self addGearButton];

	if (LBReplaceMode) {
		// The watchdog restores SpringBoard if this stops being refreshed.
		[self beat];
		_heartbeat = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(beat) userInfo:nil repeats:YES];
		LBHomeStartListening(^{ LBConfirmUsable(); [LBLauncher goHome]; });
	} else if (![[[NSUserDefaults standardUserDefaults] stringForKey:@"promptShownFor"] isEqualToString:[LBUpdater currentVersion]]) {
		// Once per version (a reinstall keeps the data, and the daemon's copy must be refreshed
		// by running setup again); the gear button (Settings > SpringBoard) offers it any time.
		[[NSUserDefaults standardUserDefaults] setObject:[LBUpdater currentVersion] forKey:@"promptShownFor"];
		dispatch_async(dispatch_get_main_queue(), ^{ [self offerReplace]; });
	}
	return YES;
}

// Opened from stock SpringBoard: offer to take its place.
- (void)offerReplace {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Replace SpringBoard?"
		message:@"Temporary: LiteBoard takes over until you reboot or run Remove LiteBoard. If it fails to start, SpringBoard comes back after about 30 seconds.\n\nPermanent: also swaps at every boot where the jailbreak is active. The root filesystem is not modified."
		preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"Not now" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"Temporary" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
		[self runRoot:@"enable"];
	}]];
	[a addAction:[UIAlertAction actionWithTitle:@"Permanent…" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
		[self confirmPermanent];
	}]];
	[self.window.rootViewController presentViewController:a animated:NO completion:nil];
}

- (void)confirmPermanent {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"WARNING"
		message:@"!!! THIS STARTS LITEBOARD AT EVERY BOOT !!!\n!!! THIS ONLY WORKS ON UNTETHERED JBS, E.G SOCKET !!!\n\nThe rootfs is NOT modified: without the jailbreak, stock SpringBoard boots. If LiteBoard fails to start, the watchdog turns it off. Run Remove LiteBoard to undo it."
		preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"I understand, install" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
		[self runRoot:@"permanent"];
	}]];
	[self.window.rootViewController presentViewController:a animated:NO completion:nil];
}

- (void)runRoot:(NSString *)action {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		int rc = LBRunRoot([NSBundle mainBundle].bundlePath, @"ctl/setup.sh", action);
		if (rc == 0) return; // SpringBoard is going away
		dispatch_async(dispatch_get_main_queue(), ^{
			UIAlertController *e = [UIAlertController alertControllerWithTitle:@"Could not get root"
				message:[NSString stringWithFormat:@"%@\nOver SSH as root run:\nsh %@/ctl/setup.sh %@", LBRootLog(), [NSBundle mainBundle].bundlePath, action]
				preferredStyle:UIAlertControllerStyleAlert];
			[e addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
			[self.window.rootViewController presentViewController:e animated:NO completion:nil];
		});
	});
}

- (void)addGearButton {
	UIButton *gear = [UIButton buttonWithType:UIButtonTypeCustom];
	gear.frame = CGRectMake(self.window.bounds.size.width - 52, 8, 44, 44);
	gear.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleBottomMargin;
	[gear setTitle:@"⚙" forState:UIControlStateNormal];
	gear.titleLabel.font = [UIFont systemFontOfSize:28];
	[gear addTarget:self action:@selector(openSettings) forControlEvents:UIControlEventTouchUpInside];
	[self.window addSubview:gear];
}

- (void)openSettings {
	LBSettingsController *vc = [[LBSettingsController alloc] init];
	vc.onReplace = ^{ [self offerReplace]; };
	UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
	nav.modalPresentationStyle = UIModalPresentationFormSheet;
	[self.window.rootViewController presentViewController:nav animated:NO completion:nil];
}

- (void)beat {
	NSString *now = [NSString stringWithFormat:@"%ld\n", (long)time(NULL)];
	NSError *err = nil;
	if (![now writeToFile:@LB_HEARTBEAT_PATH atomically:NO encoding:NSUTF8StringEncoding error:&err]) {
		static BOOL warned;
		if (!warned) { warned = YES; LBLog(@"heartbeat write failed: %@", err); }
	}
}

- (void)showHome { self.window.hidden = NO; [self.window makeKeyAndVisible]; }
- (void)hideHome { self.window.hidden = YES; }

@end
