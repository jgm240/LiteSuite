#import "LBUpdater.h"
#import "LBRun.h"
#import <CommonCrypto/CommonDigest.h>

#define LB_RELEASE_API @"https://api.github.com/repos/jgm240/LiteSuite/releases/latest"
#define LB_ASSET_NAME  @"LiteSuite.ipa"
#define LB_STAGED_PATH @"/var/tmp/liteboard-update.ipa"

static NSString *FileSHA256(NSString *path) {
	NSData *d = [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil];
	if (!d) return nil;
	uint8_t h[CC_SHA256_DIGEST_LENGTH];
	CC_SHA256(d.bytes, (CC_LONG)d.length, h);
	NSMutableString *s = [NSMutableString string];
	for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [s appendFormat:@"%02x", h[i]];
	return s;
}

static void OnMain(void (^block)(void)) { dispatch_async(dispatch_get_main_queue(), block); }

@implementation LBUpdater

+ (NSString *)currentVersion {
	return [NSBundle mainBundle].infoDictionary[@"CFBundleShortVersionString"] ?: @"0";
}

+ (void)checkWithCompletion:(void (^)(NSDictionary *, NSString *))done {
	NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:LB_RELEASE_API] cachePolicy:NSURLRequestReloadIgnoringLocalCacheData timeoutInterval:20];
	[req setValue:@"application/vnd.github+json" forHTTPHeaderField:@"Accept"];
	[req setValue:@"LiteSuite-Updater" forHTTPHeaderField:@"User-Agent"];
	[[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *resp, NSError *err) {
		NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
		if (err || !data) { OnMain(^{ done(nil, err.localizedDescription ?: @"No response"); }); return; }
		if (code == 404) { OnMain(^{ done(nil, @"No release published yet"); }); return; }
		if (code != 200) { OnMain(^{ done(nil, [NSString stringWithFormat:@"GitHub returned HTTP %ld", (long)code]); }); return; }
		NSDictionary *rel = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
		NSString *tag = [rel[@"tag_name"] isKindOfClass:[NSString class]] ? rel[@"tag_name"] : nil;
		if (!tag) { OnMain(^{ done(nil, @"Unreadable release"); }); return; }
		NSString *version = [tag hasPrefix:@"v"] ? [tag substringFromIndex:1] : tag;
		if ([version compare:[self currentVersion] options:NSNumericSearch] != NSOrderedDescending) {
			OnMain(^{ done(nil, [NSString stringWithFormat:@"Up to date (%@)", [self currentVersion]]); });
			return;
		}
		NSString *url = nil, *sha = nil;
		for (NSDictionary *a in rel[@"assets"]) {
			if (![a[@"name"] isEqualToString:LB_ASSET_NAME]) continue;
			url = a[@"browser_download_url"];
			NSString *digest = [a[@"digest"] isKindOfClass:[NSString class]] ? a[@"digest"] : nil;
			if ([digest hasPrefix:@"sha256:"]) sha = [digest substringFromIndex:7];
		}
		if (!url) { OnMain(^{ done(nil, @"Release has no LiteSuite.ipa"); }); return; }
		NSMutableDictionary *info = [@{ @"version": version, @"url": url } mutableCopy];
		if (sha) info[@"sha256"] = sha;
		OnMain(^{ done(info, nil); });
	}] resume];
}

+ (void)installUpdate:(NSDictionary *)info status:(void (^)(NSString *))status completion:(void (^)(NSString *))done {
	NSURL *url = [NSURL URLWithString:info[@"url"]];
	if (!url || ![url.scheme isEqualToString:@"https"]) { done(@"Bad download URL"); return; }
	NSString *expected = [info[@"sha256"] lowercaseString];
	status(@"Downloading…");
	[[[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *loc, NSURLResponse *resp, NSError *err) {
		NSInteger code = [(NSHTTPURLResponse *)resp statusCode];
		if (err || !loc || code != 200) {
			OnMain(^{ done(err.localizedDescription ?: [NSString stringWithFormat:@"Download failed (HTTP %ld)", (long)code]); });
			return;
		}
		NSFileManager *fm = [NSFileManager defaultManager];
		[fm removeItemAtPath:LB_STAGED_PATH error:nil];
		NSError *mv = nil;
		if (![fm moveItemAtURL:loc toURL:[NSURL fileURLWithPath:LB_STAGED_PATH] error:&mv] &&
		    ![fm copyItemAtURL:loc toURL:[NSURL fileURLWithPath:LB_STAGED_PATH] error:&mv]) {
			OnMain(^{ done([NSString stringWithFormat:@"Cannot stage update: %@", mv.localizedDescription]); });
			return;
		}
		if (expected.length && ![[FileSHA256(LB_STAGED_PATH) lowercaseString] isEqualToString:expected]) {
			[fm removeItemAtPath:LB_STAGED_PATH error:nil];
			OnMain(^{ done(@"Checksum mismatch: update rejected"); });
			return;
		}
		OnMain(^{ status(expected.length ? @"Verified. Installing…" : @"Installing (no checksum available)…"); });
		int rc = LBRunRoot([NSBundle mainBundle].bundlePath, @"ctl/setup.sh", @"update");
		OnMain(^{ done(rc == 0 ? nil : [NSString stringWithFormat:@"Install failed (%d)\n%@", rc, LBRootLog()]); });
	}] resume];
}

@end
