// GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#define NSLog(fmt, ...) NSLog((@"[LastFM] " fmt), ##__VA_ARGS__)

#import "./YouTube/YTMContentViewController.h"
#import "./YouTube/YTAlertView.h"
#import "./YouTube/MLHAMPlayerItem.h"

#import "Client.h"
#import "Scrobbler.h"
#import "Instances.h"
