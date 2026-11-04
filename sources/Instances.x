// GPL-3.0-or-later
#import "../headers/Instances.h"
#import "../headers/Client.h"

static __weak YTMContentViewController *g_ytRootViewController = nil;

@implementation LFMYouTubeInstances

+ (YTMContentViewController *)rootViewController {
    return g_ytRootViewController;
}

@end

%hook YTMContentViewController

- (void)loadView {
    %orig;
    if (self) {
        g_ytRootViewController = self;
    }
}

%new
- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller {
    [LFMClient handleBrowserExit];
}

%end
