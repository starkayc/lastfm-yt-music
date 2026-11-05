// GPL-3.0-or-later
#import "../headers/Client.h"
#import "../headers/LFMCore.h"
#import "../headers/Instances.h"
#import "../headers/YouTube/YTAlertView.h"
#import <SafariServices/SafariServices.h>
#import <objc/runtime.h>

static NSString *const LFMBaseURL = @"https://ws.audioscrobbler.com/2.0/";
static NSString *const LFMSessionDefaultsKey = @"lfmSessionKey";
static NSString *const LFMAPIKeyOverrideKey = @"lfm_api_key_override";
static NSString *const LFMAPISecretOverrideKey = @"lfm_api_secret_override";
static const NSTimeInterval LFMMaxScrobbleAgeSeconds = 14.0 * 86400.0;
static const NSUInteger LFMMaxBatchSize = 50;
static const NSUInteger LFMMaxQueueSize = 1000;

static dispatch_queue_t LFMNetQueue(void) {
    static dispatch_queue_t q = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.lfm.net", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *g_pendingAuthToken = nil;
static BOOL g_authInFlight = NO;
static BOOL g_autoAuthPromptedThisSession = NO;
static BOOL g_apiKeyStopped = NO;
static BOOL g_apiKeyAlertShown = NO;
static BOOL g_flushInFlight = NO;
static NSUInteger g_retryAttempt = 0;
static NSTimeInterval g_nextRetryNotBefore = 0;
static NSMutableArray<NSDictionary *> *g_scrobbleQueue = nil;

static UIViewController *LFMTopViewController(void) {
    UIViewController *root = [LFMYouTubeInstances rootViewController];
    if (!root) {
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                    if (window.isKeyWindow && window.rootViewController) {
                        root = window.rootViewController;
                        break;
                    }
                }
            }
            if (root) break;
        }
    }
    while (root.presentedViewController && !root.presentedViewController.isBeingDismissed) {
        root = root.presentedViewController;
    }
    return root;
}

static void LFMShowAlertOnMain(NSString *title, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        Class ytAlertCls = objc_getClass("YTAlertView");
        if (ytAlertCls && [ytAlertCls respondsToSelector:@selector(infoDialog)]) {
            YTAlertView *alertView = [ytAlertCls infoDialog];
            if ([alertView respondsToSelector:@selector(setTitle:)]) alertView.title = title;
            if ([alertView respondsToSelector:@selector(setSubtitle:)]) alertView.subtitle = message;
            if ([alertView respondsToSelector:@selector(show)]) {
                [alertView show];
                return;
            }
        }
        UIViewController *top = LFMTopViewController();
        if (top) {
            UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                        message:message
                                                                 preferredStyle:UIAlertControllerStyleAlert];
            [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [top presentViewController:ac animated:YES completion:nil];
        }
    });
}

static NSString *LFMQueueFilePath(void) {
    NSArray<NSString *> *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docs = paths.firstObject ?: NSTemporaryDirectory();
    return [docs stringByAppendingPathComponent:@"lfm_scrobble_queue.plist"];
}

static void LFMLoadQueueOnNetQueue(void) {
    if (g_scrobbleQueue) return;
    NSString *path = LFMQueueFilePath();
    NSArray *saved = [NSArray arrayWithContentsOfFile:path];
    if ([saved isKindOfClass:[NSArray class]]) {
        g_scrobbleQueue = [saved mutableCopy];
    } else {
        g_scrobbleQueue = [NSMutableArray array];
    }
}

static void LFMSaveQueueOnNetQueue(void) {
    if (!g_scrobbleQueue) return;
    [g_scrobbleQueue writeToFile:LFMQueueFilePath() atomically:YES];
}

static void LFMPruneExpiredOnNetQueue(void) {
    LFMLoadQueueOnNetQueue();
    int64_t cutoff = (int64_t)[[NSDate date] timeIntervalSince1970] - (int64_t)LFMMaxScrobbleAgeSeconds;
    NSIndexSet *expired = [g_scrobbleQueue indexesOfObjectsPassingTest:^BOOL(NSDictionary *item, NSUInteger idx, BOOL *stop) {
        int64_t ts = [item[@"timestamp"] longLongValue];
        return ts <= 0 || ts < cutoff;
    }];
    if (expired.count > 0) {
        NSLog(@"Dropping %lu expired scrobble(s) older than 14 days", (unsigned long)expired.count);
        [g_scrobbleQueue removeObjectsAtIndexes:expired];
        LFMSaveQueueOnNetQueue();
    }
}

@implementation LFMClient

+ (NSString *)makeSignature:(NSDictionary<NSString *, id> *)parameters secret:(NSString *)secret {
    return LFMMakeSignature(parameters, secret);
}

+ (NSString *)urlEncodedString:(NSString *)str {
    return LFMFormEncodeString(LFMStringFromValue(str));
}

+ (NSString *)apiKeyOverride {
    return [[NSUserDefaults standardUserDefaults] stringForKey:LFMAPIKeyOverrideKey] ?: @"";
}

+ (NSString *)apiSecretOverride {
    return [[NSUserDefaults standardUserDefaults] stringForKey:LFMAPISecretOverrideKey] ?: @"";
}

+ (BOOL)usingCustomCredentials {
    return [self apiKeyOverride].length > 0;
}

+ (NSString *)apiKey {
    NSString *override = [self apiKeyOverride];
    return override.length > 0 ? override : API_KEY;
}

+ (NSString *)apiSecret {
    NSString *override = [self apiSecretOverride];
    return override.length > 0 ? override : API_SECRET;
}

+ (void)setAPIKeyOverride:(NSString *)key secretOverride:(NSString *)secret {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    if (key.length > 0) {
        [prefs setObject:key forKey:LFMAPIKeyOverrideKey];
    } else {
        [prefs removeObjectForKey:LFMAPIKeyOverrideKey];
    }
    if (secret.length > 0) {
        [prefs setObject:secret forKey:LFMAPISecretOverrideKey];
    } else {
        [prefs removeObjectForKey:LFMAPISecretOverrideKey];
    }

    // A stored session key belongs to the old API key, and the error latch must reopen.
    [self clearSession];
    dispatch_async(LFMNetQueue(), ^{
        g_apiKeyStopped = NO;
        g_apiKeyAlertShown = NO;
    });
}

+ (NSString *)md5:(NSString *)string {
    return LFMMD5Hex(string);
}

+ (BOOL)hasSession {
    NSString *sk = [[NSUserDefaults standardUserDefaults] stringForKey:LFMSessionDefaultsKey];
    return sk.length > 0;
}

+ (void)clearSession {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:LFMSessionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"lfmToken"];
    dispatch_async(LFMNetQueue(), ^{
        g_pendingAuthToken = nil;
        g_authInFlight = NO;
        g_autoAuthPromptedThisSession = NO;
    });
}

+ (NSUInteger)pendingScrobbleCount {
    __block NSUInteger count = 0;
    dispatch_sync(LFMNetQueue(), ^{
        LFMPruneExpiredOnNetQueue();
        count = g_scrobbleQueue.count;
    });
    return count;
}

+ (void)postSignedParameters:(NSDictionary<NSString *, id> *)params
                     timeout:(NSTimeInterval)timeout
                  completion:(void (^)(NSDictionary *json, NSError *networkError))completion {
    if (g_apiKeyStopped) {
        if (completion) completion(nil, [NSError errorWithDomain:@"com.lfm.client" code:26 userInfo:nil]);
        return;
    }

    NSMutableDictionary<NSString *, id> *fullParams = [NSMutableDictionary dictionaryWithDictionary:params];
    fullParams[@"api_key"] = [self apiKey];
    fullParams[@"format"] = @"json";
    fullParams[@"api_sig"] = LFMMakeSignature(fullParams, [self apiSecret]);

    NSString *bodyString = LFMBuildFormEncodedString(fullParams);
    NSData *bodyData = [bodyString dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:LFMBaseURL]
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                       timeoutInterval:timeout];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = bodyData;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              dispatch_async(LFMNetQueue(), ^{
                  if (error || !data) {
                      if (completion) completion(nil, error ?: [NSError errorWithDomain:@"com.lfm.client" code:-1 userInfo:nil]);
                      return;
                  }
                  NSError *parseError = nil;
                  NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
                  if (![json isKindOfClass:[NSDictionary class]]) {
                      if (completion) completion(nil, parseError ?: [NSError errorWithDomain:@"com.lfm.client" code:-2 userInfo:nil]);
                      return;
                  }
                  if (completion) completion(json, nil);
              });
          }];
    [task resume];
}

+ (void)handleAPIErrorCode:(NSInteger)errorCode message:(NSString *)message {
    if (errorCode == 10 || errorCode == 26) {
        g_apiKeyStopped = YES;
        NSLog(@"Last.fm API key error (%ld): %@", (long)errorCode, message);
        if (!g_apiKeyAlertShown) {
            g_apiKeyAlertShown = YES;
            LFMShowAlertOnMain(@"Last.fm Error", [NSString stringWithFormat:@"API key error (%ld): %@", (long)errorCode, message ?: @"Invalid or suspended API key"]);
        }
    } else if (errorCode == 9) {
        NSLog(@"Last.fm session key invalid (error 9); clearing session and prompting re-auth once.");
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:LFMSessionDefaultsKey];
        [self startAuthUserInitiated:NO];
    } else {
        NSLog(@"Last.fm API error (%ld): %@", (long)errorCode, message);
    }
}

+ (void)startAuthIfNeeded {
    [self startAuthUserInitiated:NO];
}

+ (void)startAuthUserInitiated:(BOOL)userInitiated {
    dispatch_async(LFMNetQueue(), ^{
        if (g_apiKeyStopped) return;
        if (!userInitiated && [self hasSession]) return;
        if (g_authInFlight) return;
        if (!userInitiated && g_autoAuthPromptedThisSession) return;

        g_authInFlight = YES;
        if (!userInitiated) {
            g_autoAuthPromptedThisSession = YES;
        }

        // Remove any legacy persisted single-use token
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"lfmToken"];

        [self postSignedParameters:@{ @"method": @"auth.getToken" }
                           timeout:15.0
                        completion:^(NSDictionary *json, NSError *networkError) {
                            if (networkError || !json) {
                                g_authInFlight = NO;
                                NSLog(@"Failed to fetch Last.fm auth token: %@", networkError);
                                if (userInitiated) {
                                    LFMShowAlertOnMain(@"Last.fm", @"Network error while requesting Last.fm token.");
                                }
                                return;
                            }
                            NSNumber *errObj = json[@"error"];
                            if (errObj) {
                                g_authInFlight = NO;
                                [self handleAPIErrorCode:errObj.integerValue message:json[@"message"]];
                                if (userInitiated) {
                                    LFMShowAlertOnMain(@"Last.fm", [NSString stringWithFormat:@"Failed to get token: %@", json[@"message"] ?: errObj]);
                                }
                                return;
                            }
                            NSString *token = json[@"token"];
                            if (![token isKindOfClass:[NSString class]] || token.length == 0) {
                                g_authInFlight = NO;
                                NSLog(@"Last.fm auth.getToken returned empty token: %@", json);
                                return;
                            }
                            g_pendingAuthToken = [token copy];
                            [self presentSafariAuthWithToken:token];
                        }];
    });
}

+ (void)presentSafariAuthWithToken:(NSString *)token {
    NSString *encodedKey = LFMFormEncodeString([self apiKey]);
    NSString *encodedToken = LFMFormEncodeString(token);
    NSString *urlStr = [NSString stringWithFormat:@"https://www.last.fm/api/auth/?api_key=%@&token=%@", encodedKey, encodedToken];
    NSURL *url = [NSURL URLWithString:urlStr];
    if (!url) {
        g_authInFlight = NO;
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *presenter = LFMTopViewController();
        if (!presenter) {
            dispatch_async(LFMNetQueue(), ^{ g_authInFlight = NO; });
            NSLog(@"Cannot present Last.fm Safari auth: no active view controller.");
            return;
        }
        SFSafariViewController *safari = [[SFSafariViewController alloc] initWithURL:url];
        safari.modalPresentationStyle = UIModalPresentationFullScreen;
        YTMContentViewController *rootVC = [LFMYouTubeInstances rootViewController];
        if (rootVC && [rootVC respondsToSelector:@selector(safariViewControllerDidFinish:)]) {
            safari.delegate = rootVC;
        }
        [presenter presentViewController:safari animated:YES completion:nil];
    });
}

+ (void)handleBrowserExit {
    dispatch_async(LFMNetQueue(), ^{
        NSString *token = g_pendingAuthToken;
        g_pendingAuthToken = nil;
        if (!token || token.length == 0) {
            g_authInFlight = NO;
            return;
        }

        [self postSignedParameters:@{
            @"method": @"auth.getSession",
            @"token": token
        }
                           timeout:15.0
                        completion:^(NSDictionary *json, NSError *networkError) {
                            g_authInFlight = NO;
                            if (networkError || !json) {
                                NSLog(@"Failed to exchange Last.fm token for session: %@", networkError);
                                return;
                            }
                            NSNumber *errObj = json[@"error"];
                            if (errObj) {
                                [self handleAPIErrorCode:errObj.integerValue message:json[@"message"]];
                                LFMShowAlertOnMain(@"Last.fm", [NSString stringWithFormat:@"Failed to create session: %@", json[@"message"] ?: errObj]);
                                return;
                            }
                            NSString *sk = json[@"session"][@"key"];
                            if ([sk isKindOfClass:[NSString class]] && sk.length > 0) {
                                [[NSUserDefaults standardUserDefaults] setObject:sk forKey:LFMSessionDefaultsKey];
                                NSLog(@"Last.fm session established.");
                                [self flushQueueOnNetQueue];
                            }
                        }];
    });
}

+ (void)setNowPlaying:(NSString *)track artist:(NSString *)artist duration:(double)duration {
    [self setNowPlaying:track artist:artist album:nil duration:duration];
}

+ (void)setNowPlaying:(NSString *)track
               artist:(NSString *)artist
                album:(NSString *)album
             duration:(double)duration {
    if (track.length == 0 || artist.length == 0) return;

    dispatch_async(LFMNetQueue(), ^{
        if (g_apiKeyStopped) return;
        NSString *sk = [[NSUserDefaults standardUserDefaults] stringForKey:LFMSessionDefaultsKey];
        if (sk.length == 0) {
            [self startAuthUserInitiated:NO];
            return;
        }

        NSMutableDictionary<NSString *, id> *params = [NSMutableDictionary dictionaryWithDictionary:@{
            @"method": @"track.updateNowPlaying",
            @"artist": artist,
            @"track": track,
            @"sk": sk
        }];
        if (album.length > 0) {
            params[@"album"] = album;
        }
        NSInteger durSec = (NSInteger)llround(duration);
        if (durSec > 0) {
            params[@"duration"] = @(durSec);
        }

        // Spec section 4: Now-playing failures must NOT be retried.
        [self postSignedParameters:params
                           timeout:10.0
                        completion:^(NSDictionary *json, NSError *networkError) {
                            if (networkError) {
                                NSLog(@"updateNowPlaying network error (not retrying): %@", networkError.localizedDescription);
                                return;
                            }
                            NSNumber *errObj = json[@"error"];
                            if (errObj) {
                                [self handleAPIErrorCode:errObj.integerValue message:json[@"message"]];
                                return;
                            }
                            NSLog(@"Updated Now Playing: %@ - %@", artist, track);
                        }];
    });
}

+ (void)scrobble:(NSString *)track artist:(NSString *)artist duration:(double)duration elapsed:(double)elapsed {
    int64_t nowUtc = (int64_t)[[NSDate date] timeIntervalSince1970];
    int64_t startTs = nowUtc - (int64_t)floor(fmax(0.0, elapsed));
    [self scrobble:track artist:artist album:nil duration:duration timestamp:startTs];
}

+ (void)scrobble:(NSString *)track
          artist:(NSString *)artist
           album:(NSString *)album
        duration:(double)duration
       timestamp:(int64_t)timestamp {
    if (track.length == 0 || artist.length == 0 || timestamp <= 0) return;

    dispatch_async(LFMNetQueue(), ^{
        LFMLoadQueueOnNetQueue();
        LFMPruneExpiredOnNetQueue();

        NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithDictionary:@{
            @"artist": artist,
            @"track": track,
            @"timestamp": @(timestamp)
        }];
        if (album.length > 0) {
            entry[@"album"] = album;
        }
        NSInteger durSec = (NSInteger)llround(duration);
        if (durSec > 0) {
            entry[@"duration"] = @(durSec);
        }

        if (g_scrobbleQueue.count >= LFMMaxQueueSize) {
            [g_scrobbleQueue removeObjectAtIndex:0];
        }
        [g_scrobbleQueue addObject:entry];
        LFMSaveQueueOnNetQueue();

        [self flushQueueOnNetQueue];
    });
}

+ (void)flushQueue {
    dispatch_async(LFMNetQueue(), ^{
        g_nextRetryNotBefore = 0;
        [self flushQueueOnNetQueue];
    });
}

+ (void)scheduleRetryWithMinimumDelay:(NSTimeInterval)minDelay {
    g_retryAttempt++;
    double expDelay = pow(2.0, (double)MIN(g_retryAttempt, (NSUInteger)8)) * 5.0;
    NSTimeInterval delay = fmax(minDelay, fmin(expDelay, 600.0));
    g_nextRetryNotBefore = [[NSDate date] timeIntervalSince1970] + delay;
    NSLog(@"Scheduled scrobble queue retry in %.0f s (pending=%lu)", delay, (unsigned long)g_scrobbleQueue.count);

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), LFMNetQueue(), ^{
        [self flushQueueOnNetQueue];
    });
}

+ (void)flushQueueOnNetQueue {
    if (g_apiKeyStopped || g_flushInFlight) return;

    LFMLoadQueueOnNetQueue();
    LFMPruneExpiredOnNetQueue();
    if (g_scrobbleQueue.count == 0) return;

    NSString *sk = [[NSUserDefaults standardUserDefaults] stringForKey:LFMSessionDefaultsKey];
    if (sk.length == 0) {
        [self startAuthUserInitiated:NO];
        return;
    }

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now < g_nextRetryNotBefore) return;

    NSUInteger batchCount = MIN(g_scrobbleQueue.count, LFMMaxBatchSize);
    NSArray<NSDictionary *> *batch = [g_scrobbleQueue subarrayWithRange:NSMakeRange(0, batchCount)];

    NSMutableDictionary<NSString *, id> *params = [NSMutableDictionary dictionary];
    params[@"method"] = @"track.scrobble";
    params[@"sk"] = sk;

    if (batchCount == 1) {
        NSDictionary *item = batch[0];
        params[@"artist"] = item[@"artist"];
        params[@"track"] = item[@"track"];
        params[@"timestamp"] = item[@"timestamp"];
        if ([item[@"album"] length] > 0) {
            params[@"album"] = item[@"album"];
        }
        if ([item[@"duration"] integerValue] > 0) {
            params[@"duration"] = item[@"duration"];
        }
    } else {
        for (NSUInteger i = 0; i < batchCount; i++) {
            NSDictionary *item = batch[i];
            params[[NSString stringWithFormat:@"artist[%lu]", (unsigned long)i]] = item[@"artist"];
            params[[NSString stringWithFormat:@"track[%lu]", (unsigned long)i]] = item[@"track"];
            params[[NSString stringWithFormat:@"timestamp[%lu]", (unsigned long)i]] = item[@"timestamp"];
            if ([item[@"album"] length] > 0) {
                params[[NSString stringWithFormat:@"album[%lu]", (unsigned long)i]] = item[@"album"];
            }
            if ([item[@"duration"] integerValue] > 0) {
                params[[NSString stringWithFormat:@"duration[%lu]", (unsigned long)i]] = item[@"duration"];
            }
        }
    }

    g_flushInFlight = YES;
    [self postSignedParameters:params
                       timeout:10.0
                    completion:^(NSDictionary *json, NSError *networkError) {
                        g_flushInFlight = NO;

                        if (networkError || !json) {
                            NSLog(@"Scrobble network error (keeping %lu item(s) in queue): %@",
                                  (unsigned long)batchCount, networkError.localizedDescription);
                            [self scheduleRetryWithMinimumDelay:15.0];
                            return;
                        }

                        NSNumber *errObj = json[@"error"];
                        if (errObj) {
                            NSInteger code = errObj.integerValue;
                            [self handleAPIErrorCode:code message:json[@"message"]];

                            if (code == 11 || code == 16) {
                                // Temporary service error: keep in queue and retry with backoff
                                [self scheduleRetryWithMinimumDelay:15.0];
                            } else if (code == 29) {
                                // Rate limit: keep in queue and back off longer
                                [self scheduleRetryWithMinimumDelay:60.0];
                            } else if (code == 9 || code == 10 || code == 26) {
                                // Session or API key issue: keep queued scrobbles until re-authenticated
                            } else {
                                // 4, 6, 13, others: permanent parameter/signature rejection -> drop batch
                                NSLog(@"Dropping %lu scrobble(s) due to unrecoverable error %ld", (unsigned long)batchCount, (long)code);
                                if (g_scrobbleQueue.count >= batchCount) {
                                    [g_scrobbleQueue removeObjectsInRange:NSMakeRange(0, batchCount)];
                                } else {
                                    [g_scrobbleQueue removeAllObjects];
                                }
                                LFMSaveQueueOnNetQueue();
                            }
                            return;
                        }

                        // Success: inspect ignored count and advance queue
                        g_retryAttempt = 0;
                        g_nextRetryNotBefore = 0;

                        NSDictionary *attr = json[@"scrobbles"][@"@attr"];
                        NSInteger accepted = [attr[@"accepted"] integerValue];
                        NSInteger ignored = [attr[@"ignored"] integerValue];
                        NSLog(@"Scrobble batch complete: accepted=%ld ignored=%ld", (long)accepted, (long)ignored);
                        if (ignored > 0) {
                            NSLog(@"Last.fm ignored scrobble details: %@", json[@"scrobbles"]);
                        }

                        if (g_scrobbleQueue.count >= batchCount) {
                            [g_scrobbleQueue removeObjectsInRange:NSMakeRange(0, batchCount)];
                        } else {
                            [g_scrobbleQueue removeAllObjects];
                        }
                        LFMSaveQueueOnNetQueue();

                        if (g_scrobbleQueue.count > 0) {
                            [self flushQueueOnNetQueue];
                        }
                    }];
}

+ (void)sendTestScrobbleWithCompletion:(void (^)(BOOL success, NSString *message))completion {
    dispatch_async(LFMNetQueue(), ^{
        NSString *sk = [[NSUserDefaults standardUserDefaults] stringForKey:LFMSessionDefaultsKey];
        if (sk.length == 0) {
            if (completion) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    completion(NO, @"Not logged in to Last.fm. Please authenticate first.");
                });
            }
            return;
        }
        int64_t nowUtc = (int64_t)[[NSDate date] timeIntervalSince1970];
        [self postSignedParameters:@{
            @"method": @"track.updateNowPlaying",
            @"artist": @"Rick Astley",
            @"track": @"Never Gonna Give You Up",
            @"duration": @213,
            @"sk": sk
        }
                           timeout:10.0
                        completion:^(NSDictionary *json, NSError *networkError) {
                            if (networkError || !json) {
                                if (completion) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        completion(NO, networkError.localizedDescription ?: @"Network error");
                                    });
                                }
                                return;
                            }
                            NSNumber *errObj = json[@"error"];
                            if (errObj) {
                                [self handleAPIErrorCode:errObj.integerValue message:json[@"message"]];
                                if (completion) {
                                    dispatch_async(dispatch_get_main_queue(), ^{
                                        completion(NO, json[@"message"] ?: @"Last.fm API error");
                                    });
                                }
                                return;
                            }
                            if (completion) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    completion(YES, [NSString stringWithFormat:@"Now Playing test sent at %lld.", (long long)nowUtc]);
                                });
                            }
                        }];
    });
}

@end
