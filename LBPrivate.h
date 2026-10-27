#import <UIKit/UIKit.h>

@interface LSBundleProxy : NSObject
@property (nonatomic, readonly) NSString *bundleIdentifier;
@property (nonatomic, readonly) NSURL *bundleURL;
@property (nonatomic, readonly) NSString *bundleExecutable;
@property (nonatomic, readonly) NSURL *dataContainerURL;
@end

@interface LSApplicationProxy : LSBundleProxy
@property (nonatomic, readonly) NSString *applicationIdentifier;
@property (nonatomic, readonly) NSString *localizedName;
@property (nonatomic, readonly) NSArray *appTags;
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@end

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
- (BOOL)openApplicationWithBundleID:(NSString *)bundleID;
@end

@interface UIImage (LBPrivate)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)bundleID format:(int)format scale:(CGFloat)scale;
@end

extern BOOL LBReplaceMode; // YES when running as the SpringBoard replacement

// Writes a tagged line to stderr (-> /var/log/liteboard.log when run as the daemon).
void LBLog(NSString *format, ...);
