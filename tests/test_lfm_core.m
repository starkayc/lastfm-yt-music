// GPL-3.0-or-later
// Unit tests for LFMCore.h (Spec section 7.4 acceptance fixtures).
// Compile & run on macOS:
//   clang -fobjc-arc -framework Foundation -Iheaders tests/test_lfm_core.m -o tests/test_lfm_core && ./tests/test_lfm_core

#import <Foundation/Foundation.h>
#include <assert.h>
#import "LFMCore.h"

static void testSignatureFixtures(void) {
    // (a) Signature against Last.fm documented format: exclude format & callback, ASCII sort, append secret, MD5
    NSDictionary *params = @{
        @"method": @"auth.getSession",
        @"api_key": @"my_api_key",
        @"token": @"my_token",
        @"format": @"json",
        @"callback": @"jsonp"
    };
    NSString *payload = LFMMakeSignaturePayload(params, @"my_secret");
    assert([payload isEqualToString:@"api_keymy_api_keymethodauth.getSessiontokenmy_secret"] == NO);
    assert([payload isEqualToString:@"api_keymy_api_keymethodauth.getSessiontokenmy_tokenmy_secret"]);

    NSString *sig = LFMMakeSignature(params, @"my_secret");
    assert(sig.length == 32);
    assert([sig isEqualToString:LFMMD5Hex(@"api_keymy_api_keymethodauth.getSessiontokenmy_tokenmy_secret")]);

    // UTF-8 track/artist signing
    NSDictionary *utf8Params = @{
        @"api_key": @"k",
        @"artist": @"Björk & Rosalía",
        @"format": @"json",
        @"method": @"track.scrobble",
        @"sk": @"s",
        @"timestamp": @1700000000,
        @"track": @"Jóga (Live)"
    };
    NSString *utf8Payload = LFMMakeSignaturePayload(utf8Params, @"sec");
    assert([utf8Payload isEqualToString:@"api_keykartistBjörk & Rosalíamethodtrack.scrobblesks" @"timestamp1700000000trackJóga (Live)sec"]);
}

static void testArrayOrdering(void) {
    // (b) Array-notation ordering with >= 11 items: artist[10] sorts before artist[1] in plain ASCII
    NSMutableDictionary *batch = [NSMutableDictionary dictionary];
    for (int i = 0; i < 12; i++) {
        batch[[NSString stringWithFormat:@"artist[%d]", i]] = [NSString stringWithFormat:@"A%d", i];
    }
    NSArray<NSString *> *sorted = LFMSortedParameterKeys(batch);
    NSUInteger idx1 = [sorted indexOfObject:@"artist[1]"];
    NSUInteger idx10 = [sorted indexOfObject:@"artist[10]"];
    NSUInteger idx11 = [sorted indexOfObject:@"artist[11]"];
    NSUInteger idx2 = [sorted indexOfObject:@"artist[2]"];
    assert(idx10 < idx11);
    assert(idx11 < idx1);
    assert(idx1 < idx2);

    NSString *payload = LFMMakeSignaturePayload(batch, @"sec");
    NSRange r10 = [payload rangeOfString:@"artist[10]A10"];
    NSRange r1 = [payload rangeOfString:@"artist[1]A1"];
    NSRange r2 = [payload rangeOfString:@"artist[2]A2"];
    assert(r10.location != NSNotFound && r1.location != NSNotFound && r2.location != NSNotFound);
    assert(r10.location < r1.location);
    assert(r1.location < r2.location);
}

static void testFormEncoding(void) {
    // RFC 3986 form encoding: escapes =, &, +, space, UTF-8; no duplicate format=json
    NSDictionary *params = @{
        @"format": @"json",
        @"artist": @"AC/DC & Friends + More=1",
        @"track": @"100% Pure"
    };
    NSString *body = LFMBuildFormEncodedString(params);
    assert([body isEqualToString:@"artist=AC%2FDC%20%26%20Friends%20%2B%20More%3D1&format=json&track=100%25%20Pure"]);
}

static void testEligibilityThresholds(void) {
    // (c) Eligibility at 29 s / 31 s / 100 s / 600 s tracks
    assert(!LFMIsEligibleToScrobble(0.0, 0.0));
    assert(!LFMIsEligibleToScrobble(0.0, 100.0));

    // 29 s track: never eligible (> 30 s required)
    assert(!LFMIsEligibleToScrobble(29.0, 15.0));
    assert(!LFMIsEligibleToScrobble(29.0, 29.0));
    assert(!LFMIsEligibleToScrobble(30.0, 30.0));

    // 31 s track: threshold = 15.5 s
    assert(!LFMIsEligibleToScrobble(31.0, 15.0));
    assert(LFMIsEligibleToScrobble(31.0, 15.5));
    assert(LFMIsEligibleToScrobble(31.0, 16.0));

    // 100 s track: threshold = 50 s
    assert(!LFMIsEligibleToScrobble(100.0, 49.0));
    assert(LFMIsEligibleToScrobble(100.0, 50.0));

    // 600 s track: threshold = min(300, 240) = 240 s
    assert(!LFMIsEligibleToScrobble(600.0, 239.0));
    assert(LFMIsEligibleToScrobble(600.0, 240.0));
}

static void testSeekAndPauseBehavior(void) {
    // (d) Seek-to-middle does not scrobble
    LFMTrackState state = {0};
    LFMTrackTickResult res = LFMTrackStateTick(&state, NO, YES, 0.0, 200.0, 1700000000);
    assert(res == LFMTrackTickResultNewPlay);
    assert(state.startTimestamp == 1700000000);

    for (int t = 1; t <= 5; t++) {
        res = LFMTrackStateTick(&state, YES, YES, (double)t, 200.0, 1700000000 + t);
        assert(res == LFMTrackTickResultNone);
    }
    assert(state.accumulated == 5.0);

    // User seeks from 5 s to 120 s (past 50% of 200 s track)
    res = LFMTrackStateTick(&state, YES, YES, 120.0, 200.0, 1700000006);
    assert(res == LFMTrackTickResultNone);
    assert(!state.scrobbled);
    assert(state.accumulated == 5.0);

    // (e) Pause time does not count
    for (int p = 0; p < 60; p++) {
        res = LFMTrackStateTick(&state, YES, NO, 120.0, 200.0, 1700000010 + p);
        assert(res == LFMTrackTickResultNone);
    }
    assert(state.accumulated == 5.0);
    assert(state.startTimestamp == 1700000000);

    // Play 94 more seconds (accumulated = 99 s < 100 s threshold)
    for (int t = 1; t <= 94; t++) {
        res = LFMTrackStateTick(&state, YES, YES, 120.0 + t, 200.0, 1700000100 + t);
        assert(res == LFMTrackTickResultNone);
    }
    assert(state.accumulated == 99.0);
    assert(!state.scrobbled);

    // 95th second reaches accumulated = 100 s -> scrobbles once!
    res = LFMTrackStateTick(&state, YES, YES, 215.0, 200.0, 1700000195);
    assert(res == LFMTrackTickResultShouldScrobble);
    assert(state.scrobbled);
    assert(state.startTimestamp == 1700000000);

    // Subsequent ticks do not double-scrobble
    res = LFMTrackStateTick(&state, YES, YES, 216.0, 200.0, 1700000196);
    assert(res == LFMTrackTickResultNone);

    // Replay detection: mediaTime jumps back from 216 s to 0.5 s
    res = LFMTrackStateTick(&state, YES, YES, 0.5, 200.0, 1700000200);
    assert(res == LFMTrackTickResultNewPlay);
    assert(!state.scrobbled);
    assert(state.accumulated == 0.0);
    assert(state.startTimestamp == 1700000200);
}

// Fixtures taken from 55,952 real Last.fm scrobbles of YT Music. Every 'channel' case below was
// observed in the data; the reject cases are the wrong splits that measurement exposed.
static void assertSplit(NSString *title, NSString *artist, LFMSplitKind expected,
                        NSString *expectedArtist, NSString *expectedTitle) {
    NSString *outArtist = nil;
    NSString *outTitle = nil;
    LFMSplitKind kind = LFMSplitArtistFromTitle(title, artist, &outArtist, &outTitle);
    if (kind != expected) {
        printf("FAIL kind for [%s] / [%s]: got %ld want %ld\n",
               artist.UTF8String, title.UTF8String, (long)kind, (long)expected);
        assert(kind == expected);
    }
    if (expected != LFMSplitKindNone) {
        if (![outArtist isEqualToString:expectedArtist] || ![outTitle isEqualToString:expectedTitle]) {
            printf("FAIL split for [%s] / [%s]: got [%s] / [%s]\n",
                   artist.UTF8String, title.UTF8String, outArtist.UTF8String, outTitle.UTF8String);
            assert(NO);
        }
    }
}

static void testArtistTitleSplit(void) {
    // channel name in the artist field -> real artist comes out of the title
    assertSplit(@"Keane - Somewhere Only We Know", @"Dan Music", LFMSplitKindChannel,
                @"Keane", @"Somewhere Only We Know");
    assertSplit(@"Clara La San - Want U", @"Ghosty", LFMSplitKindChannel,
                @"Clara La San", @"Want U");
    assertSplit(@"Aphex Twin - Stone In Focus", @"Jack Assir", LFMSplitKindChannel,
                @"Aphex Twin", @"Stone In Focus");
    assertSplit(@"Yot Club - down bad", @"David Dean Burkhart", LFMSplitKindChannel,
                @"Yot Club", @"down bad");
    assertSplit(@"XXXTentacion ft. Lil Uzi Vert - I\u2019m Not Human", @"RileyTaugor", LFMSplitKindChannel,
                @"XXXTentacion ft. Lil Uzi Vert", @"I\u2019m Not Human");

    // the artist already sits in the title -> just drop the repeat
    assertSplit(@"Pinegrove - Need 2", @"Pinegrove", LFMSplitKindDedupe, @"Pinegrove", @"Need 2");
    assertSplit(@"EYEDRESS - JEALOUS", @"Eyedress", LFMSplitKindDedupe, @"Eyedress", @"JEALOUS");
    assertSplit(@"Ian Van Dahl - Will I", @"Ian van Dahl", LFMSplitKindDedupe, @"Ian van Dahl", @"Will I");
    assertSplit(@"Spandau Ballet - True", @"Spandau Ballet", LFMSplitKindDedupe, @"Spandau Ballet", @"True");

    // "Title - Artist" order
    assertSplit(@"Need 2 - slow pinegrove", @"Pinegrove", LFMSplitKindReverse, @"Pinegrove", @"Need 2");
    assertSplit(@"Red Red Wine - Bob Marley", @"Bob Marley", LFMSplitKindReverse, @"Bob Marley", @"Red Red Wine");

    // reject: suffix is a version descriptor, never an artist
    assertSplit(@"Ghost Assassin - VIP", @"Maduk", LFMSplitKindNone, nil, nil);
    assertSplit(@"I Just Want You - From 'Castle'", @"Mercuzio Pianist", LFMSplitKindNone, nil, nil);
    assertSplit(@"Nothing Compares - Bonus Track", @"The Weeknd", LFMSplitKindNone, nil, nil);
    assertSplit(@"The Morning - Original", @"The Weeknd", LFMSplitKindNone, nil, nil);
    assertSplit(@"Can't Help Falling in Love - Single", @"Haley Reinhart", LFMSplitKindNone, nil, nil);
    assertSplit(@"Gnossienne No. 1 - Excerpt", @"Erik Satie", LFMSplitKindNone, nil, nil);
    assertSplit(@"you - 2012Ver.", @"Dai", LFMSplitKindNone, nil, nil);
    assertSplit(@"Freeze Time vs Dare You - Hardwell Mashup", @"Manse", LFMSplitKindNone, nil, nil);
    assertSplit(@"Wish I Never Met You - Prison Tapes", @"Tory Lanez", LFMSplitKindNone, nil, nil);
    assertSplit(@"Ella Y Yo - Featuring Don Omar", @"Aventura", LFMSplitKindNone, nil, nil);
    assertSplit(@"Sunflower - Spider-Man: Into the Spider-Verse", @"Post Malone", LFMSplitKindNone, nil, nil);
    assertSplit(@"I'll Be Missing You - *Every Breath You Take*", @"Puff Daddy", LFMSplitKindNone, nil, nil);

    // reject: prefix is a track number or a soundtrack label, not an artist
    assertSplit(@"03 - Love Sensation", @"Air Gear OST", LFMSplitKindNone, nil, nil);
    assertSplit(@"#3 - Before Every Load", @"Quark", LFMSplitKindNone, nil, nil);
    assertSplit(@"Sonic The Hedgehog OST - Green Hill Zone", @"Hanternos", LFMSplitKindNone, nil, nil);
    assertSplit(@"Terraria Music - Day", @"Lhiandrow", LFMSplitKindNone, nil, nil);

    // reject: no separator, or a one-word title, or a blank side
    assertSplit(@"Bohemian Rhapsody", @"Queen", LFMSplitKindNone, nil, nil);
    assertSplit(@"A - B", @"Someone", LFMSplitKindNone, nil, nil);

    // title with a hyphen but no spaces must stay untouched (C418-Cat, T-Pain, blink-182)
    assertSplit(@"C418-Cat", @"C418", LFMSplitKindNone, nil, nil);
    assertSplit(@"Buy U a Drank (Shawty Snappin')", @"T-Pain", LFMSplitKindNone, nil, nil);

    // normalized key ignores case, punctuation and spacing
    assert([LFMNormalizedKey(@"  Ian van Dahl ") isEqualToString:@"ianvandahl"]);
    assert([LFMNormalizedKey(@"EYEDRESS") isEqualToString:@"eyedress"]);
}

int main(void) {
    @autoreleasepool {
        testSignatureFixtures();
        testArrayOrdering();
        testFormEncoding();
        testEligibilityThresholds();
        testSeekAndPauseBehavior();
        testArtistTitleSplit();
        printf("All LFMCore fixture tests passed.\n");
    }
    return 0;
}
