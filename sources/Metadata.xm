// GPL-3.0-or-later
#import "../headers/Metadata.h"
#import "../headers/Main.h"
#import "../headers/LFMCore.h"
#import <MediaPlayer/MediaPlayer.h>

@implementation LFMMetadataItem
@end

static NSCache<NSString *, NSDictionary *> *g_oembedCache = nil;
static NSCache<NSString *, NSDictionary *> *g_mbCache = nil;

static dispatch_queue_t LFMMetadataQueue(void) {
    static dispatch_queue_t q = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        q = dispatch_queue_create("com.lfm.metadata", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSString *LFMStripTopicSuffix(NSString *artist) {
    if (!artist) return @"";
    NSString *trimmed = [artist stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([trimmed hasSuffix:@" - Topic"] && trimmed.length > 8) {
        trimmed = [trimmed substringToIndex:trimmed.length - 8];
    }
    return trimmed;
}

@implementation LFMMetadata

+ (NSArray<NSString *> *)defaultRegexes {
    return @[
        @"\\s[([]Explicit[)\\]]",
        @"\\s[([]Clean[)\\]]",
        @"\\s[([]feat\\. [^)\\]]+[)\\]]",
        @"\\s[([]ft\\. [^)\\]]+[)\\]]",
        @"\\s-\\sLive(\\s.+)?$",
        @"\\s[([]Live[)\\]]$",
        @"\\s\\(Parody of \".*\" by .*\\)$",
        @"\\s\\(Lyrical Adaption of \".*\"\\)$",
        @"\\sRe-?issue$",
        @"\\s\\[.*?Re-?issue.*?\\]",
        @"\\s\\(.*?Re-?issue.*?\\)",
        @"Live\\s\\/\\sRemastered",
        @"\\s[([][^)\\]]*Re-?[Mm]aster(ed)?[^)\\]]*[)\\]]$",
        @"\\s-\\s\\d{4}(\\s-)?\\s.*Re-?[Mm]aster(ed)?.*$",
        @"\\s-\\sRe-?[Mm]aster(ed)?.*$",
        @"\\s\\[Remastered\\]\\s\\(Remastered\\sVersion\\)$",
        @"\\s[([]Album Version[)\\]]$",
        @"\\s[([]Re-?recorded[)\\]]$",
        @"\\s[([]Single Version[)\\]]$",
        @"\\s[([]Edit[)\\]]$",
        @"\\s-\\sMono Version$",
        @"\\s-\\sStereo Version$",
        @"\\s\\(Deluxe Edition\\)$",
        @"\\s[([]Expanded.*[)\\]]$",
        @"\\s-\\sExpanded Edition$",
        @"\\s[([]Explicit Version[)\\]]",
        @"\\s[([]Bonus Track Edition[)\\]]",
        @"\\s[([]\\d+th\\sAnniversary.*[)\\]]",
        @"\\s-\\sOriginal$",
        @"\\s-\\sOriginal.*Version(\\s\\d{4})?$",
        @"\\*+\\s?\\S+\\s?\\*+$",
        @"\\[[^\\]]+\\]",
        @"【[^】]+】",
        @"（[^）]+）",
        @"\\([^)]*version\\)$",
        @"\\.(avi|wmv|mpg|mpeg|flv)$",
        @"\\(.*lyrics?\\s*(video)?\\)",
        @"\\((of+icial\\s*)?(track\\s*)?stream\\)",
        @"\\((of+icial\\s*)?((music|hd)\\s*)?(video|audio)\\)",
        @"-\\s(of+icial\\s*)?(music\\s*)?(video|audio)$",
        @"\\(.*Album\\sTrack\\)",
        @"\\(\\s*of+icial\\s*\\)",
        @"\\(\\s*[0-9]{4}\\s*\\)",
        @"\\(\\s*(HD|HQ)\\s*\\)$",
        @"(HD|HQ)\\s?$",
        @"(vid[ée]o)?\\s?clip\\sof+ici[ae]l",
        @"of+iziel+es\\s*video",
        @"vid[ée]o\\s?clip",
        @"\\sclip",
        @"full\\s*album",
        @"\\(live.*?\\)$",
        @"\\|.*$",
        @"\\(.*[0-9]{1,2}\\/[0-9]{1,2}\\/[0-9]{2,4}.*\\)",
        @"sub\\s*español",
        @"\\s\\(Letra\\)",
        @"\\s\\(En\\svivo\\)",
        // yt video cruft, space tolerant
        @"\\s*[([]\\s*(of+icial\\s*)?(music\\s*)?(video|audio)\\s*[)\]]$",
        @"\\s*[([]\\s*(of+icial\\s*)?(mv|m/v|visuali[sz]er|lyric\\s*video)s?\\s*[)\]]$",
        @"\\s*[-–—]\\s*(of+icial\\s*)?(music\\s*)?(video|audio)\\s*$",
        @"\\s*[([]\\s*(of+icial\\s*)?(hd|hq|4k|8k|1080p|720p)\\s*(video|audio|mv|remaster(ed)?)?\\s*[)\]]$",
        // slowed / sped up / nightcore edits
        @"\\s*[(\\[]?\\s*[-–—]?\\s*(super\\s*)?(slowed|sped\\s*up|speed\\s*up)(\\s*(\\+|n|&|and)\\s*reverb)?(\\s*(up\\s*)?version)?\\s*[)\]]?$",
        @"^\\s*nightcore\\s*[-–—]\\s*",
        @"\\s*[([]?\\s*nightcore\\s*[)\]]?$",
        @"\\s*[([]?\\s*bass\\s*boost(ed)?\\s*[)\]]?$",
        // lyrics residues
        @"\\s+with\\s+lyrics?$",
        @"\\s*//\\s*(letra|lyrics?)$",
        @"^\\s*@\\S+\\s*[-–—]\\s*",
        // emoji + dangling opener
        @"^[🎵🎶]\\s*",
        @"\\s*[🎵🎶]\\s*$",
        @"\\s+[(\\[]\\s*$"
    ];
}

+ (NSString *)cleanString:(NSString *)string withRegexes:(NSArray<NSString *> *)regexes {
    if (!string || string.length == 0) return @"";
    NSString *cleaned = [string copy];
    if (regexes.count > 0) {
        for (NSString *pattern in regexes) {
            if (![pattern isKindOfClass:[NSString class]] || pattern.length == 0) continue;
            NSError *err = nil;
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                                   options:NSRegularExpressionCaseInsensitive
                                                                                     error:&err];
            if (!regex || err) continue;
            cleaned = [regex stringByReplacingMatchesInString:cleaned
                                                      options:0
                                                        range:NSMakeRange(0, cleaned.length)
                                                 withTemplate:@""];
        }
    }
    return [cleaned stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

+ (LFMMetadataItem *)readNowPlayingCenterMetadata {
    NSDictionary *info = [[MPNowPlayingInfoCenter defaultCenter] nowPlayingInfo];
    if (![info isKindOfClass:[NSDictionary class]] || info.count == 0) {
        return nil;
    }
    NSString *rawTitle = [info[MPMediaItemPropertyTitle] isKindOfClass:[NSString class]] ? info[MPMediaItemPropertyTitle] : @"";
    NSString *rawArtist = [info[MPMediaItemPropertyArtist] isKindOfClass:[NSString class]] ? info[MPMediaItemPropertyArtist] : @"";
    NSString *rawAlbum = [info[MPMediaItemPropertyAlbumTitle] isKindOfClass:[NSString class]] ? info[MPMediaItemPropertyAlbumTitle] : @"";
    double duration = [info[MPMediaItemPropertyPlaybackDuration] respondsToSelector:@selector(doubleValue)]
        ? [info[MPMediaItemPropertyPlaybackDuration] doubleValue]
        : 0.0;

    NSString *title = [rawTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *artist = LFMStripTopicSuffix(rawArtist);
    NSString *album = [rawAlbum stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if (title.length == 0 || artist.length == 0) {
        return nil;
    }

    LFMMetadataItem *item = [[LFMMetadataItem alloc] init];
    item.title = title;
    item.artist = artist;
    item.album = album.length > 0 ? album : nil;
    item.duration = duration > 0.0 ? duration : 0.0;
    item.source = @"MPNowPlayingInfoCenter";
    return item;
}

+ (void)fetchOEmbedForVideoID:(NSString *)videoID completion:(void (^)(LFMMetadataItem *item))completion {
    if (videoID.length == 0) {
        if (completion) completion(nil);
        return;
    }

    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        g_oembedCache = [[NSCache alloc] init];
        g_oembedCache.countLimit = 200;
    });

    NSDictionary *cached = [g_oembedCache objectForKey:videoID];
    if (cached) {
        LFMMetadataItem *item = [[LFMMetadataItem alloc] init];
        item.title = cached[@"title"];
        item.artist = cached[@"artist"];
        item.source = @"oEmbed(cache)";
        if (completion) completion(item);
        return;
    }

    NSString *encodedID = LFMFormEncodeString(videoID);
    NSString *watchURL = [NSString stringWithFormat:@"https://www.youtube.com/watch?v=%@", encodedID];
    NSString *urlString = [NSString stringWithFormat:@"https://www.youtube.com/oembed?url=%@&format=json", LFMFormEncodeString(watchURL)];
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        if (completion) completion(nil);
        return;
    }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                       cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                   timeoutInterval:10.0];
    [req setValue:@"en-US,en;q=0.9" forHTTPHeaderField:@"Accept-Language"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:req
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
              if (error || !data) {
                  NSLog(@"oEmbed request failed for %@: %@", videoID, error.localizedDescription);
                  if (completion) completion(nil);
                  return;
              }
              NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
              if (![json isKindOfClass:[NSDictionary class]]) {
                  if (completion) completion(nil);
                  return;
              }
              NSString *rawTitle = [json[@"title"] isKindOfClass:[NSString class]] ? json[@"title"] : @"";
              NSString *rawAuthor = [json[@"author_name"] isKindOfClass:[NSString class]] ? json[@"author_name"] : @"";
              NSString *title = [rawTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
              NSString *artist = LFMStripTopicSuffix(rawAuthor);

              if (title.length == 0 || artist.length == 0) {
                  if (completion) completion(nil);
                  return;
              }
              [g_oembedCache setObject:@{ @"title": title, @"artist": artist } forKey:videoID];

              LFMMetadataItem *item = [[LFMMetadataItem alloc] init];
              item.title = title;
              item.artist = artist;
              item.source = @"oEmbed";
              if (completion) completion(item);
          }];
    [task resume];
}

+ (void)applyOptionalPostProcessingToItem:(LFMMetadataItem *)item
                               completion:(void (^)(LFMMetadataItem *processed))completion {
    if (!item) {
        if (completion) completion(nil);
        return;
    }

    dispatch_async(LFMMetadataQueue(), ^{
        NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
        BOOL regexEnabled = [prefs boolForKey:@"lfm_regex_cleanup_enabled"];
        BOOL mbEnabled = [prefs boolForKey:@"lfm_musicbrainz_enabled"];
        NSString *mbEmail = [prefs stringForKey:@"lfm_musicbrainz_email"];

        if (regexEnabled) {
            NSArray<NSString *> *regexes = [prefs arrayForKey:@"lfm_custom_regexes"] ?: [self defaultRegexes];
            NSString *cleanTitle = [self cleanString:item.title withRegexes:regexes];
            NSString *cleanArtist = [self cleanString:item.artist withRegexes:regexes];
            if (cleanTitle.length > 0) item.title = cleanTitle;
            if (cleanArtist.length > 0) item.artist = cleanArtist;
        }

        // Uploader leaked into the artist field: pull the real artist out of "Artist - Title".
        NSString *splitArtist = nil;
        NSString *splitTitle = nil;
        LFMSplitKind kind = LFMSplitArtistFromTitle(item.title, item.artist, &splitArtist, &splitTitle);
        if (kind != LFMSplitKindNone && splitArtist.length > 0 && splitTitle.length > 0) {
            NSLog(@"Artist/title split (%ld): %@ - %@", (long)kind, splitArtist, splitTitle);
            item.artist = splitArtist;
            item.title = splitTitle;
        }

        if (!mbEnabled || mbEmail.length == 0) {
            if (completion) completion(item);
            return;
        }

        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            g_mbCache = [[NSCache alloc] init];
            g_mbCache.countLimit = 200;
        });

        NSString *cacheKey = [NSString stringWithFormat:@"%@|||%@", item.artist, item.title];
        NSDictionary *cached = [g_mbCache objectForKey:cacheKey];
        if (cached) {
            item.title = cached[@"title"] ?: item.title;
            item.artist = cached[@"artist"] ?: item.artist;
            if (completion) completion(item);
            return;
        }

        NSString *escRec = [item.title stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *escArt = [item.artist stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
        NSString *query = [NSString stringWithFormat:@"recording:\"%@\" AND artist:\"%@\"", escRec, escArt];
        NSString *urlString = [NSString stringWithFormat:@"https://musicbrainz.org/ws/2/recording/?query=%@&fmt=json&limit=1",
                               LFMFormEncodeString(query)];
        NSURL *url = [NSURL URLWithString:urlString];
        if (!url) {
            if (completion) completion(item);
            return;
        }

        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:6.0];
        [req setValue:[NSString stringWithFormat:@"YTMLastFM/1.0 ( %@ )", mbEmail] forHTTPHeaderField:@"User-Agent"];

        NSURLSessionDataTask *task = [[NSURLSession sharedSession]
            dataTaskWithRequest:req
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                  if (!error && data) {
                      NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                      NSArray *recordings = [json isKindOfClass:[NSDictionary class]] ? json[@"recordings"] : nil;
                      NSDictionary *top = [recordings isKindOfClass:[NSArray class]] ? recordings.firstObject : nil;
                      if ([top isKindOfClass:[NSDictionary class]] && [top[@"score"] intValue] >= 85) {
                          NSString *mbTitle = top[@"title"];
                          NSArray *credits = top[@"artist-credit"];
                          NSString *mbArtist = ([credits isKindOfClass:[NSArray class]] && credits.count > 0)
                              ? credits.firstObject[@"name"]
                              : nil;
                          if ([mbTitle isKindOfClass:[NSString class]] && mbTitle.length > 0) {
                              item.title = mbTitle;
                          }
                          if ([mbArtist isKindOfClass:[NSString class]] && mbArtist.length > 0) {
                              item.artist = mbArtist;
                          }
                      }
                  }
                  [g_mbCache setObject:@{ @"title": item.title ?: @"", @"artist": item.artist ?: @"" } forKey:cacheKey];
                  if (completion) completion(item);
              }];
        [task resume];
    });
}

+ (void)resolveForVideoID:(NSString *)videoID
           previousTitle:(NSString *)previousTitle
              completion:(void (^)(LFMMetadataItem *item))completion {
    BOOL preferOEmbed = [[NSUserDefaults standardUserDefaults] boolForKey:@"lfm_prefer_oembed"];

    if (preferOEmbed) {
        [self fetchOEmbedForVideoID:videoID completion:^(LFMMetadataItem *oembedItem) {
            if (oembedItem) {
                // Supplement album/duration from MPNowPlayingInfoCenter if available
                LFMMetadataItem *mpItem = [self readNowPlayingCenterMetadata];
                if (mpItem) {
                    if (oembedItem.album.length == 0 && mpItem.album.length > 0) {
                        oembedItem.album = mpItem.album;
                    }
                    if (oembedItem.duration <= 0.0 && mpItem.duration > 0.0) {
                        oembedItem.duration = mpItem.duration;
                    }
                }
                [self applyOptionalPostProcessingToItem:oembedItem completion:completion];
                return;
            }
            // Fallback to MPNowPlayingInfoCenter (e.g. uploaded library tracks without oEmbed)
            LFMMetadataItem *mpFallback = [self readNowPlayingCenterMetadata];
            if (mpFallback) {
                [self applyOptionalPostProcessingToItem:mpFallback completion:completion];
            } else {
                NSLog(@"Metadata unavailable from both oEmbed and MPNowPlayingInfoCenter for videoID=%@", videoID);
                if (completion) completion(nil);
            }
        }];
        return;
    }

    // Default (Spec 7.5): MPNowPlayingInfoCenter primary, oEmbed fallback
    // Delay briefly (0.35s) if MPNowPlayingInfoCenter is empty or still holds previousTitle right at track switch
    LFMMetadataItem *mpImmediate = [self readNowPlayingCenterMetadata];
    BOOL looksStale = (mpImmediate && previousTitle.length > 0 && [mpImmediate.title isEqualToString:previousTitle]);
    if (mpImmediate && !looksStale) {
        NSLog(@"Metadata [MPNowPlayingInfoCenter]: %@ - %@ (album=%@)",
              mpImmediate.artist, mpImmediate.title, mpImmediate.album ?: @"none");
        [self applyOptionalPostProcessingToItem:mpImmediate completion:completion];
        return;
    }

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        LFMMetadataItem *mpDelayed = [self readNowPlayingCenterMetadata];
        BOOL stillStale = (mpDelayed && previousTitle.length > 0 && [mpDelayed.title isEqualToString:previousTitle]);
        if (mpDelayed && !stillStale) {
            NSLog(@"Metadata [MPNowPlayingInfoCenter delayed]: %@ - %@ (album=%@)",
                  mpDelayed.artist, mpDelayed.title, mpDelayed.album ?: @"none");
            [self applyOptionalPostProcessingToItem:mpDelayed completion:completion];
            return;
        }
        [self fetchOEmbedForVideoID:videoID completion:^(LFMMetadataItem *oembedItem) {
            if (oembedItem) {
                NSLog(@"Metadata [oEmbed fallback]: %@ - %@", oembedItem.artist, oembedItem.title);
                [self applyOptionalPostProcessingToItem:oembedItem completion:completion];
            } else if (mpDelayed) {
                // Better to use MPNowPlayingInfoCenter (e.g. same-title replay) than drop completely
                [self applyOptionalPostProcessingToItem:mpDelayed completion:completion];
            } else {
                NSLog(@"Metadata unavailable from both MPNowPlayingInfoCenter and oEmbed for videoID=%@", videoID);
                if (completion) completion(nil);
            }
        }];
    });
}

@end
