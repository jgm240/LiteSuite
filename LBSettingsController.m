#import "LBSettingsController.h"
#import "LBUpdater.h"
#import "LBRun.h"
#import "LBPrivate.h"

// Same file LiteKB reads when its keyboard appears (see LiteKB/KeyboardViewController.m).
#define LK_CONFIG_PATH @"/var/mobile/Library/Preferences/com.liteboard.litekb.plist"

typedef struct { __unsafe_unretained NSString *key, *title, *suffix; float min, max, def, div; } LBSetting;

// min/max/def are in display units; the stored value is display / div (key size is a fraction).
static const LBSetting kSettings[3] = {
	{ @"cornerRadius", @"Corner radius", @" pt", 0,  24, 5,   1   },
	{ @"keySize",      @"Key size",      @"%",   60, 150, 100, 100 },
	{ @"fontSize",     @"Font size",     @" pt", 10, 40, 22,  1   },
};

@interface LBSliderCell : UITableViewCell
@property (nonatomic, strong) UILabel *name, *value;
@property (nonatomic, strong) UISlider *slider;
@end

@implementation LBSliderCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)rid {
	if ((self = [super initWithStyle:style reuseIdentifier:rid])) {
		self.selectionStyle = UITableViewCellSelectionStyleNone;
		_name = [[UILabel alloc] init];
		_value = [[UILabel alloc] init];
		_value.textAlignment = NSTextAlignmentRight;
		_value.textColor = [UIColor grayColor];
		_slider = [[UISlider alloc] init];
		_slider.continuous = NO; // write the plist once, on release
		[self.contentView addSubview:_name];
		[self.contentView addSubview:_value];
		[self.contentView addSubview:_slider];
	}
	return self;
}
- (void)layoutSubviews {
	[super layoutSubviews];
	CGFloat w = self.contentView.bounds.size.width, m = 16;
	_name.frame = CGRectMake(m, 6, w / 2, 24);
	_value.frame = CGRectMake(w / 2, 6, w / 2 - m, 24);
	_slider.frame = CGRectMake(m, 32, w - 2 * m, 28);
}
@end

@implementation LBSettingsController {
	NSString *_updateStatus;
	BOOL _busy;
}

- (instancetype)init { return [super initWithStyle:UITableViewStyleGrouped]; }

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"LiteSuite";
	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
}

- (void)done { [self dismissViewControllerAnimated:NO completion:nil]; }

#pragma mark - Config plist

- (NSMutableDictionary *)config {
	return [[NSDictionary dictionaryWithContentsOfFile:LK_CONFIG_PATH] mutableCopy] ?: [NSMutableDictionary dictionary];
}

- (float)displayValueFor:(int)i {
	id v = [self config][kSettings[i].key];
	return v ? [v floatValue] * kSettings[i].div : kSettings[i].def;
}

- (void)sliderChanged:(UISlider *)s {
	int i = (int)s.tag;
	float shown = roundf(s.value);
	NSMutableDictionary *c = [self config];
	c[kSettings[i].key] = @(shown / kSettings[i].div);
	if (![c writeToFile:LK_CONFIG_PATH atomically:YES]) {
		LBLog(@"could not write %@", LK_CONFIG_PATH);
		static BOOL warned;
		if (!warned) {
			warned = YES;
			[self alert:@"Could not save" message:@"This install is sandboxed and cannot write the shared settings file, so the keyboard will keep its default look. Installing an unsigned build with AppSync avoids this." handler:nil];
		}
	}
	LBSliderCell *cell = (LBSliderCell *)[self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
	cell.value.text = [NSString stringWithFormat:@"%.0f%@", shown, kSettings[i].suffix];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
	return s == 0 ? 4 : 2;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
	return @[@"LiteKB buttons", @"Updates", @"SpringBoard"][s];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
	if (s == 0) return @"Applies the next time the keyboard appears.";
	if (s == 1) return @"Checks the latest release of jgm240/LiteSuite on GitHub.";
	return nil;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
	return (ip.section == 0 && ip.row < 3) ? 66 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
	if (ip.section == 0 && ip.row < 3) {
		LBSliderCell *c = [[LBSliderCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		int i = (int)ip.row;
		c.name.text = kSettings[i].title;
		c.slider.minimumValue = kSettings[i].min;
		c.slider.maximumValue = kSettings[i].max;
		c.slider.value = [self displayValueFor:i];
		c.slider.tag = i;
		c.value.text = [NSString stringWithFormat:@"%.0f%@", c.slider.value, kSettings[i].suffix];
		[c.slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
		return c;
	}
	UITableViewCell *c = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	if (ip.section == 0) {
		c.textLabel.text = @"Reset to defaults";
		c.textLabel.textColor = [UIColor redColor];
	} else if (ip.section == 1 && ip.row == 0) {
		c.textLabel.text = @"Version";
		c.detailTextLabel.text = [LBUpdater currentVersion];
		c.selectionStyle = UITableViewCellSelectionStyleNone;
	} else if (ip.section == 1) {
		c.textLabel.text = _busy ? @"Working…" : @"Check for updates";
		c.detailTextLabel.text = _updateStatus;
	} else {
		c.textLabel.text = ip.row == 0 ? @"Replace SpringBoard…" : @"Save system info for debugging";
	}
	return c;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
	[tv deselectRowAtIndexPath:ip animated:NO];
	if (ip.section == 0 && ip.row == 3) {
		[[NSFileManager defaultManager] removeItemAtPath:LK_CONFIG_PATH error:nil];
		[tv reloadSections:[NSIndexSet indexSetWithIndex:0] withRowAnimation:UITableViewRowAnimationNone];
	} else if (ip.section == 1 && ip.row == 1 && !_busy) {
		[self checkForUpdate];
	} else if (ip.section == 2 && ip.row == 1) {
		[self dumpSystemInfo];
	} else if (ip.section == 2) {
		void (^cb)(void) = self.onReplace;
		[self dismissViewControllerAnimated:NO completion:^{ if (cb) cb(); }];
	}
}

#pragma mark - Updates

- (void)setStatus:(NSString *)s busy:(BOOL)busy {
	_updateStatus = s;
	_busy = busy;
	[self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:1]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)alert:(NSString *)title message:(NSString *)msg handler:(void (^)(void))handler {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:msg preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) { if (handler) handler(); }]];
	[self presentViewController:a animated:NO completion:nil];
}

- (void)dumpSystemInfo {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		int rc = LBRunRoot([NSBundle mainBundle].bundlePath, @"ctl/setup.sh", @"dump");
		dispatch_async(dispatch_get_main_queue(), ^{
			[self alert:rc == 0 ? @"Saved" : @"Could not save"
			    message:rc == 0 ? @"Connect the iPad to the Mac and run idevicecrashreport to read LiteBoard-system.ips and the SpringBoard and backboardd binaries."
			                    : [NSString stringWithFormat:@"%@", LBRootLog()]
			    handler:nil];
		});
	});
}

- (void)checkForUpdate {
	if (LBReplaceMode) {
		[self setStatus:@"Not while LiteBoard is the home screen" busy:NO];
		return;
	}
	[self setStatus:@"Checking…" busy:YES];
	[LBUpdater checkWithCompletion:^(NSDictionary *info, NSString *error) {
		if (!info) { [self setStatus:error busy:NO]; return; }
		[self setStatus:[NSString stringWithFormat:@"%@ available", info[@"version"]] busy:NO];
		UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"Update to %@?", info[@"version"]]
			message:@"LiteBoard and LiteKB will be replaced, then LiteBoard closes."
			preferredStyle:UIAlertControllerStyleAlert];
		[a addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
		[a addAction:[UIAlertAction actionWithTitle:@"Install" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
			[self install:info];
		}]];
		[self presentViewController:a animated:NO completion:nil];
	}];
}

- (void)install:(NSDictionary *)info {
	[self setStatus:@"Starting…" busy:YES];
	[LBUpdater installUpdate:info status:^(NSString *s) { [self setStatus:s busy:YES]; } completion:^(NSString *error) {
		if (error) {
			[self setStatus:@"Failed" busy:NO];
			[self alert:@"Update failed" message:error handler:nil];
		} else {
			[self alert:@"Updated" message:@"Open LiteBoard again to use the new version." handler:^{ exit(0); }];
		}
	}];
}

@end
