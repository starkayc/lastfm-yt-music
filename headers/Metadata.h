// GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface LFMMetadataItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *album;
@property (nonatomic, assign) double duration;
@property (nonatomic, copy) NSString *source;
@end

@interface LFMMetadata : NSObject

+ (LFMMetadataItem *)readNowPlayingCenterMetadata;

+ (void)resolveForVideoID:(NSString *)videoID
           previousTitle:(NSString *)previousTitle
              completion:(void (^)(LFMMetadataItem *item))completion;

+ (NSString *)cleanString:(NSString *)string withRegexes:(NSArray<NSString *> *)regexes;
+ (NSArray<NSString *> *)defaultRegexes;

@end
