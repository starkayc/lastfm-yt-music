// GPL-3.0-or-later
// Standalone sideload login/keychain fixes (ported from dayanch96/YTMusicUltimate).
// Default build excludes this file (companion mode with YTMusicUltimate).
// Only enable with `make SIDELOAD_FIXES=1` when NOT injecting YTMusicUltimate.

#import "../headers/YouTube/YTAlertView.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#import <substrate.h>

#define YT_BUNDLE_ID @"com.google.ios.youtubemusic"
#define YT_BUNDLE_NAME @"YouTubeMusic"
#define YT_NAME @"YouTube Music"

@interface InitWorkaround : UIViewController
@property (nonatomic, copy) void (^completion)(void);
@end

@interface SFAuthenticationViewController : UIViewController
- (void)remoteViewControllerWillDismiss:(id)remoteVC;
@end

@interface SSOConfiguration : NSObject
@end

static NSString *accessGroupID(void) {
    NSDictionary *query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrAccount: @"bundleSeedID",
        (__bridge id)kSecAttrService: @"",
        (__bridge id)kSecReturnAttributes: @YES
    };
    CFDictionaryRef result = nil;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
    if (status == errSecItemNotFound) {
        status = SecItemAdd((__bridge CFDictionaryRef)query, (CFTypeRef *)&result);
        if (status != errSecSuccess) {
            return nil;
        }
    }
    if (!result) return nil;
    NSDictionary *dict = (__bridge_transfer NSDictionary *)result;
    return dict[(__bridge NSString *)kSecAttrAccessGroup];
}

static void showSideloadAlert(NSString *title, NSString *subtitle) {
    Class alertCls = objc_getClass("YTAlertView");
    if (alertCls && [alertCls respondsToSelector:@selector(infoDialog)]) {
        YTAlertView *alertView = [alertCls infoDialog];
        if ([alertView respondsToSelector:@selector(setTitle:)]) alertView.title = title;
        if ([alertView respondsToSelector:@selector(setSubtitle:)]) alertView.subtitle = subtitle;
        if ([alertView respondsToSelector:@selector(show)]) [alertView show];
    }
}

%group SideloadingFixes

%hook SSOConfiguration
- (BOOL)shouldEnableSafariSignIn { return YES; }
- (BOOL)temporarilyDisableSafariSignIn { return NO; }
- (void)setTemporarilyDisableSafariSignIn:(BOOL)arg1 { %orig(NO); }
- (id)initWithClientID:(id)clientID supportedAccountServices:(id)supportedAccountServices {
    self = %orig;
    if (self) {
        @try {
            [self setValue:YT_NAME forKey:@"_shortAppName"];
            [self setValue:YT_BUNDLE_ID forKey:@"_applicationIdentifier"];
        } @catch (__unused NSException *e) {}
    }
    return self;
}
- (void)setShortAppName:(id)appName { %orig(YT_NAME); }
%end

%hook SSOKeychainHelper
+ (id)accessGroup { return accessGroupID(); }
+ (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook SSOFolsomKeychainUtils
- (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook GULKeychainStorage
- (void)getObjectForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    %orig(key, objectClass, accessGroupID(), handler);
}
- (void)setObject:(id)object forKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    %orig(object, key, accessGroupID(), handler);
}
- (void)removeObjectForKey:(id)key accessGroup:(id)accessGroup completionHandler:(id)handler {
    %orig(key, accessGroupID(), handler);
}
- (void)getObjectFromKeychainForKey:(id)key objectClass:(Class)objectClass accessGroup:(id)accessGroup completionHandler:(id)handler {
    %orig(key, objectClass, accessGroupID(), handler);
}
- (id)keychainQueryWithKey:(id)key accessGroup:(id)accessGroup {
    return %orig(key, accessGroupID());
}
%end

%hook SSOKeychainCore
+ (id)accessGroup { return accessGroupID(); }
+ (id)sharedAccessGroup { return accessGroupID(); }
%end

%hook SSOBundleIdServiceImpl
- (id)bundleId { return YT_BUNDLE_ID; }
%end

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    if (groupIdentifier != nil) {
        NSArray *paths = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
        NSURL *documentsURL = [paths lastObject];
        return [documentsURL URLByAppendingPathComponent:@"AppGroup"];
    }
    return %orig(groupIdentifier);
}
%end

%hook YTVersionUtils
- (id)appName { return YT_NAME; }
- (id)appID { return YT_BUNDLE_ID; }
%end

%hook CHRAppState
- (id)appName { return YT_NAME; }
%end

%hook GCKBUtils
- (id)appIdentifier { return YT_BUNDLE_ID; }
%end

%hook FIRInstallationsIIDTokenStore
- (id)IIDAppIdentifier { return YT_BUNDLE_ID; }
%end

%hook GPCDeviceInfo
- (id)bundleId { return YT_BUNDLE_ID; }
%end

%hook OGLBundle
- (id)shortAppName { return YT_NAME; }
%end

%hook GVROverlayView
- (id)appName { return YT_NAME; }
%end

%hook OGLGM2AccountSelectorViewController
- (id)shortAppName { return YT_NAME; }
%end

%hook OGLPhenotypeFlagServiceImpl
- (NSString *)bundleId { return YT_BUNDLE_ID; }
%end

%hook APMAEU
- (BOOL)isFAS { return YES; }
%end

%hook ASWApp
- (id)bundleIdentifier { return YT_BUNDLE_ID; }
- (id)exp_productionBundleIdentifier { return YT_BUNDLE_ID; }
%end

%hook GULAppEnvironmentUtil
- (BOOL)isFromAppStore { return YES; }
%end

%hook APMIdentity
- (BOOL)isFromAppStore { return YES; }
%end

%hook NSBundle
- (NSString *)bundleIdentifier {
    NSArray *address = [NSThread callStackReturnAddresses];
    if (address.count < 3) return %orig;
    Dl_info info = {0};
    if (dladdr((void *)[address[2] longLongValue], &info) == 0 || !info.dli_fname)
        return %orig;
    NSString *path = [NSString stringWithUTF8String:info.dli_fname];
    if ([path hasPrefix:NSBundle.mainBundle.bundlePath])
        return YT_BUNDLE_ID;
    return %orig;
}
- (id)objectForInfoDictionaryKey:(NSString *)key {
    if ([key isEqualToString:@"CFBundleIdentifier"])
        return YT_BUNDLE_ID;
    if ([key isEqualToString:@"CFBundleDisplayName"])
        return YT_NAME;
    if ([key isEqualToString:@"CFBundleName"])
        return YT_BUNDLE_NAME;
    return %orig;
}
%end

%hook ASWUtilities
- (id)productionBundleIdentifier { return YT_BUNDLE_ID; }
- (id)lowercaseProductionBundleIdentifier { return YT_BUNDLE_ID; }
%end

%hook EXPApp
- (id)bundleIdentifier { return YT_BUNDLE_ID; }
%end

%hook CHRInfoPlistUtil
- (id)mainAppBundleID { return YT_BUNDLE_ID; }
%end

%hook FIROptions
- (id)bundleID { return YT_BUNDLE_ID; }
%end

%hook FIRApp
- (id)actualBundleID { return YT_BUNDLE_ID; }
%end

%hook GAZAppInfo
- (id)currentBundleIdentifier { return YT_BUNDLE_ID; }
%end

%end

static NSDictionary *(*orig_infoDictionary)(id self, SEL _cmd);
static NSDictionary *replaceInfoDict(id self, SEL _cmd) {
    NSDictionary *originalInfoDictionary = orig_infoDictionary(self, _cmd);
    NSString *bundleIdentifier = originalInfoDictionary[@"CFBundleIdentifier"];
    if (![bundleIdentifier isEqualToString:YT_BUNDLE_ID]) {
        NSMutableDictionary *newInfoDictionary = [NSMutableDictionary dictionaryWithDictionary:originalInfoDictionary];
        [newInfoDictionary setValue:YT_BUNDLE_ID forKey:@"CFBundleIdentifier"];
        return newInfoDictionary;
    }
    return originalInfoDictionary;
}

static BOOL isFirstTime = YES;

@implementation InitWorkaround
- (void)viewDidLoad {
    [super viewDidLoad];
    isFirstTime = NO;
    UIActivityIndicatorView *activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    activityIndicator.color = [UIColor whiteColor];
    activityIndicator.center = self.view.center;
    [self.view addSubview:activityIndicator];
    [activityIndicator startAnimating];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        MSHookMessageEx(objc_getClass("NSBundle"), @selector(infoDictionary), (IMP)replaceInfoDict, (IMP *)&orig_infoDictionary);
        [self dismissViewControllerAnimated:YES completion:^{
            if (self.completion) {
                self.completion();
            }
        }];
    });
}
@end

%hook SFAuthenticationViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (isFirstTime) {
        InitWorkaround *workaround = [[InitWorkaround alloc] init];
        workaround.completion = ^{
            [self dismissViewControllerAnimated:YES completion:^{
                if ([self respondsToSelector:@selector(remoteViewControllerWillDismiss:)]) {
                    #pragma clang diagnostic push
                    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [self performSelector:@selector(remoteViewControllerWillDismiss:) withObject:nil];
                    #pragma clang diagnostic pop
                }
                showSideloadAlert(@"Warning", @"Workaround activated.\n\nPlease try again.");
            }];
        };
        [self presentViewController:workaround animated:YES completion:nil];
    }
}
%end

%hook YTMFirstTimeSignInViewController
- (void)viewDidDisappear:(bool)arg1 {
    %orig;
    showSideloadAlert(@"Warning", @"An app restart is required after a successful sign in.");
}
%end

%ctor {
    %init;
    %init(SideloadingFixes);
}
