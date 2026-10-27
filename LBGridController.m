#import "LBGridController.h"
#import "LBLauncher.h"
#import "LBPrivate.h"
#import "LBApplication.h"

static NSString *const kCell = @"cell";

@interface LBCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@end

// Icon straight from the app bundle's PNGs, for when the system icon service has nothing (it did not in
// the daemon-launched process). Picks the largest icon file named in Info.plist or called AppIcon*.
static UIImage *LBIconFromBundle(NSString *bid) {
	LSApplicationProxy *p = [LSApplicationProxy applicationProxyForIdentifier:bid];
	NSString *dir = p.bundleURL.path;
	if (!dir) return nil;
	NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:[dir stringByAppendingPathComponent:@"Info.plist"]];
	NSMutableArray *names = [NSMutableArray array];
	for (NSString *k in @[@"CFBundleIcons~ipad", @"CFBundleIcons"]) {
		NSArray *files = info[k][@"CFBundlePrimaryIcon"][@"CFBundleIconFiles"];
		if ([files isKindOfClass:[NSArray class]]) [names addObjectsFromArray:files];
	}
	for (NSString *k in @[@"CFBundleIconFiles", @"CFBundleIconFile"]) {
		id v = info[k];
		if ([v isKindOfClass:[NSArray class]]) [names addObjectsFromArray:v];
		else if ([v isKindOfClass:[NSString class]]) [names addObject:v];
	}
	UIImage *best = nil;
	CGFloat bestArea = 0;
	for (NSString *f in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:nil]) {
		if (![f.pathExtension.lowercaseString isEqualToString:@"png"]) continue;
		BOOL match = [f hasPrefix:@"AppIcon"] || [f hasPrefix:@"Icon"];
		for (NSString *n in names) if ([f hasPrefix:n.stringByDeletingPathExtension]) { match = YES; break; }
		if (!match) continue;
		UIImage *im = [UIImage imageWithContentsOfFile:[dir stringByAppendingPathComponent:f]];
		CGFloat area = im.size.width * im.size.height * im.scale * im.scale;
		if (im && area > bestArea) { best = im; bestArea = area; }
	}
	return best;
}

@implementation LBCell
- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		_icon = [[UIImageView alloc] initWithFrame:CGRectMake((frame.size.width - 60) / 2, 4, 60, 60)];
		_label = [[UILabel alloc] initWithFrame:CGRectMake(0, 68, frame.size.width, 16)];
		_label.font = [UIFont systemFontOfSize:12];
		_label.textColor = [UIColor whiteColor];
		_label.textAlignment = NSTextAlignmentCenter;
		_label.lineBreakMode = NSLineBreakByTruncatingTail;
		[self.contentView addSubview:_icon];
		[self.contentView addSubview:_label];
	}
	return self;
}
@end

@implementation LBGridController {
	NSArray<NSDictionary *> *_apps;     // @{ @"id", @"name" }, sorted by name
	NSCache *_icons;
}

- (instancetype)init {
	UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
	layout.itemSize = CGSizeMake(100, 92);
	layout.minimumInteritemSpacing = 14;
	layout.minimumLineSpacing = 22;
	layout.sectionInset = UIEdgeInsetsMake(40, 30, 30, 30);
	return [super initWithCollectionViewLayout:layout];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	_icons = [[NSCache alloc] init];
	self.collectionView.backgroundColor = LBReplaceMode ? [UIColor colorWithRed:0.05 green:0.1 blue:0.4 alpha:1] : [UIColor blackColor]; // opaque, no wallpaper/blur: cheap to composite
	[self.collectionView registerClass:[LBCell class] forCellWithReuseIdentifier:kCell];
	[self reload];
}

- (void)reload {
	NSMutableArray *list = [NSMutableArray array];
	for (LSApplicationProxy *p in [[LSApplicationWorkspace defaultWorkspace] allInstalledApplications]) {
		NSString *bid = p.applicationIdentifier;
		if (!bid || [p.appTags containsObject:@"hidden"] || [bid isEqualToString:@"com.liteboard.app"]) continue;
		[list addObject:@{ @"id": bid, @"name": p.localizedName ?: bid }];
	}
	_apps = [list sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
		return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
	}];
	[self.collectionView reloadData];
}

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s { return _apps.count; }

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv cellForItemAtIndexPath:(NSIndexPath *)ip {
	LBCell *cell = [cv dequeueReusableCellWithReuseIdentifier:kCell forIndexPath:ip];
	NSDictionary *app = _apps[ip.item];
	cell.label.text = app[@"name"];
	UIImage *img = [_icons objectForKey:app[@"id"]];
	if (img) {
		cell.icon.image = img;
	} else {
		cell.icon.image = nil;
		NSString *bid = app[@"id"];
		dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
			UIImage *i = [UIImage _applicationIconImageForBundleIdentifier:bid format:2 scale:[UIScreen mainScreen].scale];
				if (!i) i = LBIconFromBundle(bid);
				if (!i) return;
				[self->_icons setObject:i forKey:bid];
				LBRunOnMain(^{
				if ([cv.indexPathsForVisibleItems containsObject:ip]) [(LBCell *)[cv cellForItemAtIndexPath:ip] icon].image = i;
			});
		});
	}
	return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
	[LBLauncher launchBundleID:_apps[ip.item][@"id"]];
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (void)didReceiveMemoryWarning { [super didReceiveMemoryWarning]; [_icons removeAllObjects]; }

@end
