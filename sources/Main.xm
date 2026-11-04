// GPL-3.0-or-later
#import "../headers/Main.h"
#import <MediaPlayer/MediaPlayer.h>
#import <objc/runtime.h>

static void LFMRunSelectorProbe(void) {
    NSString *shortVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    NSString *buildVer = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"] ?: @"unknown";
    NSLog(@"YTM version=%@ (%@) iOS=%@", shortVer, buildVer, [[UIDevice currentDevice] systemVersion]);

    struct {
        const char *cls;
        const char *sel;
    } table[] = {
        {"YTPlayerViewController", "contentVideoID"},
        {"YTPlayerViewController", "currentVideoID"},
        {"YTPlayerViewController", "currentVideoMediaTime"},
        {"YTPlayerViewController", "currentVideoTotalMediaTime"},
        {"YTPlayerViewController", "setPlayerResponse:"},
        {"YTPlayerViewController", "playbackController:didActivateVideo:withPlaybackData:"},
        {"MLHAMPlayerItem", "playerStateDidChangeFrom:to:"},
        {"MLHAMPlayerItem", "totalMediaTime"},
        {"YTQueueController", "nowPlayingMusicQueueItem"},
        {"YTQueueController", "nowPlayingVideoMediaTime"},
        {"YTQueueItem", "videoRenderer"},
        {"YTMQueueModificationNotifier", NULL},
        {"YTMContentViewController", "loadView"},
        {"YTAlertView", "infoDialog"},
        {"YTMAvatarAccountView", "setAccountMenuUpperButtons:lowerButtons:"},
        {"YTMAccountButton", "initWithTitle:identifier:icon:actionBlock:"},
    };

    for (size_t i = 0; i < sizeof(table) / sizeof(table[0]); i++) {
        Class c = objc_getClass(table[i].cls);
        if (!c) {
            NSLog(@"probe %s: CLASS MISSING", table[i].cls);
            continue;
        }
        if (!table[i].sel) {
            NSLog(@"probe %s: class ok", table[i].cls);
            continue;
        }
        SEL s = sel_registerName(table[i].sel);
        BOOL inst = class_getInstanceMethod(c, s) != NULL;
        BOOL cls = class_getClassMethod(c, s) != NULL;
        NSLog(@"probe %s %s: instance=%d class=%d", table[i].cls, table[i].sel, inst, cls);
    }
}

%hook YTMContentViewController

- (void)viewDidLoad {
    %orig;
    NSLog(@"YTMContentViewController loaded.");
    if ([LFMClient hasSession]) {
        [LFMClient flushQueue];
    }
}

%end

%ctor {
    %init;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LFMRunSelectorProbe();
    });
}
