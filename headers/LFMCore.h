// GPL-3.0-or-later
// Pure Objective-C/C helpers for Last.fm signing, form encoding, and scrobble state machine.
// Zero YouTube Music dependencies so this header can be compiled in standalone unit tests.

#ifndef LFMCORE_H
#define LFMCORE_H

#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include <math.h>
#include <stdint.h>

typedef NS_ENUM(NSInteger, LFMTrackTickResult) {
    LFMTrackTickResultNone = 0,
    LFMTrackTickResultNewPlay = 1 << 0,
    LFMTrackTickResultShouldScrobble = 1 << 1
};

typedef struct {
    int64_t startTimestamp;
    double lastMediaTime;
    double accumulated;
    double duration;
    BOOL scrobbled;
    BOOL initialized;
} LFMTrackState;

static inline double LFMScrobbleThreshold(double duration) {
    if (duration <= 30.0) return INFINITY;
    double half = duration / 2.0;
    return half < 240.0 ? half : 240.0;
}

static inline BOOL LFMIsEligibleToScrobble(double duration, double accumulated) {
    if (duration <= 30.0 || accumulated <= 0.0) return NO;
    return accumulated >= LFMScrobbleThreshold(duration);
}

static inline void LFMTrackStateStart(LFMTrackState *state, double mediaTime, double duration, int64_t nowUtc) {
    if (!state) return;
    double clampedMedia = (isfinite(mediaTime) && mediaTime > 0.0) ? mediaTime : 0.0;
    state->startTimestamp = nowUtc - (int64_t)floor(clampedMedia);
    state->lastMediaTime = clampedMedia;
    state->accumulated = 0.0;
    state->duration = (isfinite(duration) && duration > 0.0) ? duration : 0.0;
    state->scrobbled = NO;
    state->initialized = YES;
}

static inline LFMTrackTickResult LFMTrackStateTick(
    LFMTrackState *state,
    BOOL isSameTrack,
    BOOL isPlaying,
    double mediaTime,
    double duration,
    int64_t nowUtc
) {
    if (!state) return LFMTrackTickResultNone;
    if (isfinite(duration) && duration > 0.0) {
        state->duration = duration;
    }
    if (!isfinite(mediaTime) || mediaTime < 0.0) {
        mediaTime = 0.0;
    }

    // Track change or initial play
    if (!state->initialized || !isSameTrack) {
        LFMTrackStateStart(state, mediaTime, state->duration, nowUtc);
        return LFMTrackTickResultNewPlay;
    }

    // Replay detection: mediaTime drops by > 5 s and lands below 2 s
    if ((state->lastMediaTime - mediaTime) > 5.0 && mediaTime < 2.0) {
        LFMTrackStateStart(state, mediaTime, state->duration, nowUtc);
        return LFMTrackTickResultNewPlay;
    }

    double delta = mediaTime - state->lastMediaTime;
    state->lastMediaTime = mediaTime;

    // Accumulate 1s only on normal playing ticks (ignore pauses and forward seeks > 3s)
    if (isPlaying && delta > 0.0 && delta <= 3.0) {
        state->accumulated += 1.0;
    }

    if (!state->scrobbled && LFMIsEligibleToScrobble(state->duration, state->accumulated)) {
        state->scrobbled = YES;
        return LFMTrackTickResultShouldScrobble;
    }

    return LFMTrackTickResultNone;
}

static inline NSString *LFMStringFromValue(id value) {
    if (!value || value == [NSNull null]) return @"";
    if ([value isKindOfClass:[NSString class]]) return (NSString *)value;
    if ([value respondsToSelector:@selector(stringValue)]) return [value stringValue];
    return [NSString stringWithFormat:@"%@", value];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static inline NSString *LFMMD5Hex(NSString *input) {
    if (!input) input = @"";
    const char *utf8 = [input UTF8String];
    CC_LONG len = (CC_LONG)strlen(utf8);
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(utf8, len, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hex appendFormat:@"%02x", (unsigned int)digest[i]];
    }
    return [hex copy];
}
#pragma clang diagnostic pop

static inline NSArray<NSString *> *LFMSortedParameterKeys(NSDictionary<NSString *, id> *parameters) {
    return [[parameters allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a, NSString *b) {
        return [a compare:b options:NSLiteralSearch];
    }];
}

static inline NSString *LFMMakeSignaturePayload(NSDictionary<NSString *, id> *parameters, NSString *secret) {
    NSArray<NSString *> *sortedKeys = LFMSortedParameterKeys(parameters);
    NSMutableString *payload = [NSMutableString string];
    for (NSString *key in sortedKeys) {
        if ([key isEqualToString:@"format"] || [key isEqualToString:@"callback"]) {
            continue;
        }
        [payload appendString:key];
        [payload appendString:LFMStringFromValue(parameters[key])];
    }
    if (secret) {
        [payload appendString:secret];
    }
    return [payload copy];
}

static inline NSString *LFMMakeSignature(NSDictionary<NSString *, id> *parameters, NSString *secret) {
    return LFMMD5Hex(LFMMakeSignaturePayload(parameters, secret));
}

static inline NSString *LFMFormEncodeString(NSString *input) {
    if (!input) return @"";
    static NSCharacterSet *unreserved = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unreserved = [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    });
    return [input stringByAddingPercentEncodingWithAllowedCharacters:unreserved] ?: @"";
}

static inline NSString *LFMBuildFormEncodedString(NSDictionary<NSString *, id> *parameters) {
    NSArray<NSString *> *sortedKeys = LFMSortedParameterKeys(parameters);
    NSMutableArray<NSString *> *pairs = [NSMutableArray arrayWithCapacity:sortedKeys.count];
    for (NSString *key in sortedKeys) {
        NSString *encodedKey = LFMFormEncodeString(key);
        NSString *encodedVal = LFMFormEncodeString(LFMStringFromValue(parameters[key]));
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedVal]];
    }
    return [pairs componentsJoinedByString:@"&"];
}

#endif /* LFMCORE_H */
