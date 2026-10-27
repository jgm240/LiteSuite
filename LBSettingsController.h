#import <UIKit/UIKit.h>

// LiteBoard settings: LiteKB key style, LiteSuite updates, SpringBoard replacement.
@interface LBSettingsController : UITableViewController
@property (nonatomic, copy) void (^onReplace)(void);
@end
