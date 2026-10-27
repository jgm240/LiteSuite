#import <Foundation/Foundation.h>

// Self-updater for LiteSuite: reads the latest GitHub release of jgm240/LiteSuite,
// downloads its LiteSuite.ipa, verifies the SHA-256 when GitHub provides one, then has
// ctl/setup.sh (as root) swap the installed bundle for the new one.
@interface LBUpdater : NSObject
+ (NSString *)currentVersion;

// info has @"version", @"url" and (when available) @"sha256"; or error is set
// ("Up to date" is reported as an error string with info == nil).
+ (void)checkWithCompletion:(void (^)(NSDictionary *info, NSString *error))done;

+ (void)installUpdate:(NSDictionary *)info
               status:(void (^)(NSString *status))status
           completion:(void (^)(NSString *error))done;
@end
