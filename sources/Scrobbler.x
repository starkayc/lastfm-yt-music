// GPL-3.0-or-later
#import "../headers/Scrobbler.h"
#import "../headers/Main.h"
#import "../headers/LFMCore.h"
#import "../headers/Metadata.h"
#import <objc/runtime.h>

static __weak id g_activePlayerVC = nil;
static NSTimer *g_pollTimer = nil;
static BOOL g_mlhamPlaying = NO;
static double g_mlhamTotalMediaTime = 0.0;

static NSString *g_currentVideoID = @"";
static LFMTrackState g_trackState = {0};
static LFMMetadataItem *g_cachedMetadata = nil;
static uint64_t g_playGeneration = 0;
static BOOL g_pendingScrobble = NO;
static NSUInteger g_idleTicks = 0;

static id LFMValue(id obj, NSString *key) {
    if (!obj || !key) return nil;
    if (![obj respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try {
        return [obj valueForKey:key];
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static double LFMDoubleValue(id obj, NSString *key) {
    id val = LFMValue(obj, key);
    if ([val respondsToSelector:@selector(doubleValue)]) {
        double d = [val doubleValue];
        return (isfinite(d) && d > 0.0) ? d : 0.0;
    }
    return 0.0;
}

@implementation LFMScrobbler

+ (void)ensureTimerRunning {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_pollTimer && [g_pollTimer isValid]) return;
        [g_pollTimer invalidate];
        g_idleTicks = 0;
        g_pollTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                      repeats:YES
                                                        block:^(__unused NSTimer *timer) {
                                                            [LFMScrobbler poll];
                                                        }];
    });
}

+ (void)stopTimer {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_pollTimer) {
            [g_pollTimer invalidate];
            g_pollTimer = nil;
        }
    });
}

+ (void)poll {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        if ([prefs objectForKey:@"lfm_scrobbler_enabled"] && ![prefs boolForKey:@"lfm_scrobbler_enabled"]) {
            return;
        }

        id playerVC = g_activePlayerVC;
        if (!playerVC) return;

        id rawID = LFMValue(playerVC, @"contentVideoID");
        if (![rawID isKindOfClass:[NSString class]] || [(NSString *)rawID length] == 0) {
            rawID = LFMValue(playerVC, @"currentVideoID");
        }
        NSString *videoID = [rawID isKindOfClass:[NSString class]] ? (NSString *)rawID : @"";
        if (videoID.length == 0) return;

        double mediaTime = LFMDoubleValue(playerVC, @"currentVideoMediaTime");
        double totalDuration = LFMDoubleValue(playerVC, @"currentVideoTotalMediaTime");
        if (totalDuration <= 0.0 && g_mlhamTotalMediaTime > 0.0) {
            totalDuration = g_mlhamTotalMediaTime;
        }
        if (totalDuration <= 0.0 && g_cachedMetadata.duration > 0.0) {
            totalDuration = g_cachedMetadata.duration;
        }

        BOOL isSameTrack = (g_currentVideoID.length > 0 && [g_currentVideoID isEqualToString:videoID]);
        BOOL timeAdvanced = (!isSameTrack) || (mediaTime > g_trackState.lastMediaTime && (mediaTime - g_trackState.lastMediaTime) <= 3.0);
        BOOL effectivePlaying = g_mlhamPlaying || timeAdvanced;

        if (!effectivePlaying) {
            g_idleTicks++;
            if (g_idleTicks >= 30 && !g_mlhamPlaying) {
                [self stopTimer];
            }
        } else {
            g_idleTicks = 0;
        }

        int64_t nowUtc = (int64_t)[[NSDate date] timeIntervalSince1970];
        LFMTrackTickResult tickResult = LFMTrackStateTick(
            &g_trackState,
            isSameTrack,
            effectivePlaying,
            mediaTime,
            totalDuration,
            nowUtc
        );

        if (tickResult & LFMTrackTickResultNewPlay) {
            NSString *previousTitle = g_cachedMetadata.title;
            g_currentVideoID = [videoID copy];
            g_cachedMetadata = nil;
            g_pendingScrobble = NO;
            uint64_t expectedGen = ++g_playGeneration;

            NSLog(@"Track started: videoID=%@ startTimestamp=%lld duration=%.1f",
                  videoID, (long long)g_trackState.startTimestamp, g_trackState.duration);

            [LFMMetadata resolveForVideoID:videoID
                             previousTitle:previousTitle
                                completion:^(LFMMetadataItem *item) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        if (expectedGen != g_playGeneration || ![g_currentVideoID isEqualToString:videoID]) {
                                            return;
                                        }
                                        if (!item || item.title.length == 0 || item.artist.length == 0) {
                                            NSLog(@"Skipping Now Playing / scrobble for %@: empty metadata", videoID);
                                            return;
                                        }
                                        g_cachedMetadata = item;
                                        if (g_trackState.duration <= 0.0 && item.duration > 0.0) {
                                            g_trackState.duration = item.duration;
                                        }

                                        NSLog(@"Now Playing [%@]: %@ - %@ (duration=%.0f)",
                                              item.source ?: @"unknown", item.artist, item.title, g_trackState.duration);
                                        [LFMClient setNowPlaying:item.title
                                                          artist:item.artist
                                                           album:item.album
                                                        duration:g_trackState.duration];

                                        if (g_pendingScrobble) {
                                            g_pendingScrobble = NO;
                                            NSLog(@"Scrobbling (deferred metadata): %@ - %@", item.artist, item.title);
                                            [LFMClient scrobble:item.title
                                                         artist:item.artist
                                                          album:item.album
                                                       duration:g_trackState.duration
                                                      timestamp:g_trackState.startTimestamp];
                                        }
                                    });
                                }];
        }

        if (tickResult & LFMTrackTickResultShouldScrobble) {
            if (g_cachedMetadata && g_cachedMetadata.title.length > 0 && g_cachedMetadata.artist.length > 0) {
                NSLog(@"Scrobbling: %@ - %@ (accumulated=%.0f/%.0f, start=%lld)",
                      g_cachedMetadata.artist,
                      g_cachedMetadata.title,
                      g_trackState.accumulated,
                      g_trackState.duration,
                      (long long)g_trackState.startTimestamp);
                [LFMClient scrobble:g_cachedMetadata.title
                             artist:g_cachedMetadata.artist
                              album:g_cachedMetadata.album
                           duration:g_trackState.duration
                          timestamp:g_trackState.startTimestamp];
            } else {
                g_pendingScrobble = YES;
            }
        }
    });
}

@end

%hook YTPlayerViewController

- (void)setPlayerResponse:(id)response {
    %orig;
    g_activePlayerVC = self;
    [LFMScrobbler ensureTimerRunning];
}

- (void)playbackController:(id)arg1 didActivateVideo:(id)arg2 withPlaybackData:(id)arg3 {
    %orig;
    g_activePlayerVC = self;
    [LFMScrobbler ensureTimerRunning];
}

%end

%hook MLHAMPlayerItem

- (void)playerStateDidChangeFrom:(NSInteger)from to:(NSInteger)to {
    %orig;

    double itemTotal = LFMDoubleValue(self, @"totalMediaTime");
    if (itemTotal > 0.0) {
        g_mlhamTotalMediaTime = itemTotal;
    }

    if (to == 3) {
        g_mlhamPlaying = YES;
        [LFMScrobbler ensureTimerRunning];
    } else {
        g_mlhamPlaying = NO;
        [LFMScrobbler stopTimer];
    }
}

%end
