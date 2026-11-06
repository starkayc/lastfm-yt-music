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

#pragma mark - Artist / title split

// YouTube Music sets the uploader as the artist, so the track field arrives as "RealArtist - RealTitle".
// Rule tuned against 55,952 real scrobbles: 589 rows corrected, ~2% of the touched rows land wrong,
// which is why the suffix is rejected whenever it looks like a version/label descriptor.

typedef NS_ENUM(NSInteger, LFMSplitKind) {
    LFMSplitKindNone = 0,
    LFMSplitKindDedupe,
    LFMSplitKindReverse,
    LFMSplitKindChannel
};

static inline NSString *LFMNormalizedKey(NSString *string) {
    if (![string isKindOfClass:[NSString class]] || string.length == 0) return @"";
    NSString *lower = [string lowercaseStringWithLocale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    NSMutableString *out = [NSMutableString stringWithCapacity:lower.length];
    NSCharacterSet *alnum = [NSCharacterSet alphanumericCharacterSet];
    for (NSUInteger i = 0; i < lower.length; i++) {
        unichar c = [lower characterAtIndex:i];
        if ([alnum characterIsMember:c]) [out appendFormat:@"%C", c];
    }
    return [out copy];
}

static inline BOOL LFMSplitMatches(NSString *string, NSString *pattern) {
    // No static cache: one static local inside a static inline is shared by every call site,
    // so the first pattern compiled would be reused for all of them.
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                      options:NSRegularExpressionCaseInsensitive
                                                                        error:nil];
    if (!re || string.length == 0) return NO;
    return [re firstMatchInString:string options:0 range:NSMakeRange(0, string.length)] != nil;
}

static inline NSUInteger LFMSplitWordCount(NSString *string) {
    NSArray<NSString *> *parts = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSUInteger n = 0;
    for (NSString *part in parts) {
        if (part.length > 0) n++;
    }
    return n;
}

static inline BOOL LFMSplitSuffixIsDescriptor(NSString *suffix) {
    return LFMSplitMatches(suffix,
        @"\\b(live|remix(ed)?|version|ver|edit|mix|remaster(ed)?|acoustic|instrumental|demo|session|feat|featuring|ft|mono|stereo|extended|radio|explicit|clean|slowed|sped|cover|orchestral|a cappella|dub|bootleg|karaoke|commentary|interview|outro|intro|part|pt|video|lyric|lyrics|letra|audio|official|mv|hd|hq|4k|bonus|track|original|single|reimagined|reprise|soundtrack|unreleased|deluxe|edition|from|theme|excerpt|mashup|tapes?|vip|vocal|music|inst)\\b|\\d{4}\\s*ver\\.?");
}

static inline BOOL LFMSplitPrefixIsLabel(NSString *prefix) {
    return LFMSplitMatches(prefix, @"\\b(ost|soundtrack|music|theme|remix|edit|version|lyrics?|audio|video|full album|episode|season)\\b");
}

static inline LFMSplitKind LFMSplitArtistFromTitle(NSString *title, NSString *artist, NSString **outArtist, NSString **outTitle) {
    if (![title isKindOfClass:[NSString class]] || ![artist isKindOfClass:[NSString class]]) return LFMSplitKindNone;
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *t = [title stringByTrimmingCharactersInSet:ws];
    NSString *a = [artist stringByTrimmingCharactersInSet:ws];
    if (t.length < 5 || a.length < 1) return LFMSplitKindNone;

    NSRange sep = [t rangeOfString:@" - "];
    if (sep.location == NSNotFound) {
        for (NSString *dash in @[@" – ", @" — "]) {
            sep = [t rangeOfString:dash];
            if (sep.location != NSNotFound) break;
        }
    }
    if (sep.location == NSNotFound) return LFMSplitKindNone;

    NSString *prefix = [[t substringToIndex:sep.location] stringByTrimmingCharactersInSet:ws];
    NSString *suffix = [[t substringFromIndex:NSMaxRange(sep)] stringByTrimmingCharactersInSet:ws];
    if (prefix.length < 2 || suffix.length < 2) return LFMSplitKindNone;
    if (LFMSplitWordCount(prefix) > 6 || LFMSplitWordCount(suffix) > 12) return LFMSplitKindNone;

    // "Wings (Nu:Logic Remix)": the bracketed tail is part of the title, not a reject signal.
    NSString *suffixCore = suffix;
    NSRegularExpression *tailRe = [NSRegularExpression regularExpressionWithPattern:@"\\s*[\\(\\[【（][^)\\]】）]*[)\\]】）]$"
                                                                          options:0 error:nil];
    NSTextCheckingResult *tail = [tailRe firstMatchInString:suffixCore options:0 range:NSMakeRange(0, suffixCore.length)];
    if (tail) suffixCore = [suffixCore substringToIndex:tail.range.location];
    suffixCore = [suffixCore stringByTrimmingCharactersInSet:ws];
    if (suffixCore.length < 2) return LFMSplitKindNone;

    static NSString *const punctPrefix = @":,()[]【】（）「」*…";
    static NSString *const punctSuffix = @":()[]【】（）「」*…";
    NSCharacterSet *badPrefix = [NSCharacterSet characterSetWithCharactersInString:punctPrefix];
    NSCharacterSet *badSuffix = [NSCharacterSet characterSetWithCharactersInString:punctSuffix];
    if ([prefix rangeOfCharacterFromSet:badPrefix].location != NSNotFound) return LFMSplitKindNone;
    if ([suffixCore rangeOfCharacterFromSet:badSuffix].location != NSNotFound) return LFMSplitKindNone;
    if (LFMSplitMatches(suffixCore, @"\\b(19|20)\\d{2}\\b")) return LFMSplitKindNone;
    if (LFMSplitMatches(suffixCore, @"^#?\\d+$")) return LFMSplitKindNone;
    if (LFMSplitSuffixIsDescriptor(suffixCore)) return LFMSplitKindNone;
    if (LFMSplitPrefixIsLabel(prefix)) return LFMSplitKindNone;
    if (LFMSplitMatches(prefix, @"^#?\\d+$")) return LFMSplitKindNone;

    NSString *artistKey = LFMNormalizedKey(a);
    NSString *prefixKey = LFMNormalizedKey(prefix);
    NSString *suffixKey = LFMNormalizedKey(suffix);

    if (artistKey.length >= 2 && [prefixKey containsString:artistKey]) {
        if (outArtist) *outArtist = a;
        if (outTitle) *outTitle = suffix;
        return LFMSplitKindDedupe;
    }
    // "Title - Artist" order: keep the artist, drop its repeat from the end.
    if (artistKey.length >= 3 && [suffixKey containsString:artistKey]) {
        if (outArtist) *outArtist = a;
        if (outTitle) *outTitle = prefix;
        return LFMSplitKindReverse;
    }
    if (prefix.length < 3) return LFMSplitKindNone;

    if (outArtist) *outArtist = prefix;
    if (outTitle) *outTitle = suffix;
    return LFMSplitKindChannel;
}

#endif /* LFMCORE_H */
