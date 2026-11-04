// GPL-3.0-or-later
#import <Foundation/Foundation.h>

@interface LFMScrobbler : NSObject

+ (void)poll;
+ (void)ensureTimerRunning;
+ (void)stopTimer;

@end
