#import "LBGridController.h"
#import "LBLauncher.h"
#import "LBPrivate.h"

static NSString *const kCell = @"cell";

@interface LBCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *label;
@end

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
	self.collectionView.backgroundColor = [UIColor blackColor]; // opaque, no wallpaper/blur: cheap to composite
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
			if (!i) return;
			[self->_icons setObject:i forKey:bid];
			dispatch_async(dispatch_get_main_queue(), ^{
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
