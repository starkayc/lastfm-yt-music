// GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

@interface LFMClient : NSObject

+ (NSString *)makeSignature:(NSDictionary<NSString *, id> *)parameters secret:(NSString *)secret;
+ (NSString *)urlEncodedString:(NSString *)str;
+ (NSString *)md5:(NSString *)string;

// Runtime credential override (Settings → Account & Queue). Empty override = built-in build values.
+ (NSString *)apiKey;
+ (NSString *)apiSecret;
+ (NSString *)apiKeyOverride;
+ (NSString *)apiSecretOverride;
+ (void)setAPIKeyOverride:(NSString *)key secretOverride:(NSString *)secret;
+ (BOOL)usingCustomCredentials;

+ (BOOL)hasSession;
+ (void)startAuthIfNeeded;
+ (void)startAuthUserInitiated:(BOOL)userInitiated;
+ (void)handleBrowserExit;
+ (void)clearSession;

+ (void)setNowPlaying:(NSString *)track
               artist:(NSString *)artist
                album:(NSString *)album
             duration:(double)duration;

+ (void)scrobble:(NSString *)track
          artist:(NSString *)artist
           album:(NSString *)album
        duration:(double)duration
       timestamp:(int64_t)timestamp;

// Legacy convenience signatures kept for compatibility
+ (void)setNowPlaying:(NSString *)track artist:(NSString *)artist duration:(double)duration;
+ (void)scrobble:(NSString *)track artist:(NSString *)artist duration:(double)duration elapsed:(double)elapsed;

+ (NSUInteger)pendingScrobbleCount;
+ (void)flushQueue;
+ (void)sendTestScrobbleWithCompletion:(void (^)(BOOL success, NSString *message))completion;

@end
