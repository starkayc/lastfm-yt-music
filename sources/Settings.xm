// GPL-3.0-or-later
#import "../headers/Main.h"
#import "../headers/Metadata.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

#ifndef TWEAK_VERSION
#define TWEAK_VERSION @"1.0.6"
#endif

#define LFM_RED_COLOR [UIColor colorWithRed:230.0/255.0 green:75.0/255.0 blue:75.0/255.0 alpha:1.0]
#define LFM_BLUE_SWITCH_COLOR [UIColor colorWithRed:30.0/255.0 green:150.0/255.0 blue:245.0/255.0 alpha:1.0]

@interface ABCSwitch : UIControl
@property (nonatomic, strong) UIColor *onTintColor;
@property (nonatomic, assign, readwrite, getter=isOn) BOOL on;
@end

@interface YTMAccountButton : UIButton
- (id)initWithTitle:(id)arg1 identifier:(id)arg2 icon:(id)arg3 actionBlock:(void (^)(BOOL finished))arg4;
@end

@interface YTMAvatarAccountView : UIView
@end

@interface UIView (LFMPrivateAncestor)
- (UIViewController *)_viewControllerForAncestor;
@end

static UIControl *LFMCreateSwitch(UIColor *tintColor, BOOL isOn, id target, SEL action, NSInteger tag) {
    Class abcClass = NSClassFromString(@"ABCSwitch");
    if (abcClass) {
        ABCSwitch *sw = [[abcClass alloc] init];
        sw.onTintColor = tintColor;
        sw.on = isOn;
        sw.tag = tag;
        [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
        return sw;
    }
    UISwitch *sw = [[UISwitch alloc] init];
    sw.onTintColor = tintColor;
    sw.on = isOn;
    sw.tag = tag;
    [sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
    return sw;
}

static BOOL LFMSwitchIsOn(id sender) {
    if ([sender respondsToSelector:@selector(isOn)]) {
        return [sender isOn];
    }
    return NO;
}

static void LFMSwitchSetOn(id sender, BOOL on) {
    if ([sender isKindOfClass:[UISwitch class]]) {
        [(UISwitch *)sender setOn:on animated:YES];
    } else if ([sender respondsToSelector:@selector(setOn:)]) {
        [(ABCSwitch *)sender setOn:on];
    }
}

static UILabel *LFMRightDetailLabel(NSString *text, UIColor *color) {
    UILabel *label = [[UILabel alloc] init];
    label.text = text ?: @"";
    label.textColor = color ?: [UIColor secondaryLabelColor];
    label.font = [UIFont systemFontOfSize:16.0];
    label.textAlignment = NSTextAlignmentRight;
    [label sizeToFit];
    return label;
}

static UITextField *LFMCredentialField(BOOL secure, NSString *placeholder, NSString *text) {
    UITextField *field = [[UITextField alloc] init];
    field.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    field.secureTextEntry = secure;
    field.placeholder = placeholder;
    field.text = text;
    field.textAlignment = NSTextAlignmentRight;
    field.font = [UIFont systemFontOfSize:16.0];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.returnKeyType = UIReturnKeyDone;
    // Without this the keyboard renders black-on-black over YTM's dark window.
    field.keyboardAppearance = UIKeyboardAppearanceLight;
    return field;
}

#pragma mark - Regex Filters Subcontroller (YTMusicUltimate InsetGrouped style)

@interface LFMRegularExpressionsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@interface LFMCredentialsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>
@end

@implementation LFMRegularExpressionsViewController {
    NSUserDefaults *_prefs;
    NSMutableArray<NSString *> *_regexes;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Regex Filters";
    _prefs = [NSUserDefaults standardUserDefaults];

    NSArray *saved = [_prefs arrayForKey:@"lfm_custom_regexes"];
    _regexes = saved ? [saved mutableCopy] : [[LFMMetadata defaultRegexes] mutableCopy];

    UIBarButtonItem *addButton = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"plus"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(addRegex)];
    UIBarButtonItem *resetButton = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"arrow.counterclockwise"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(resetDefaults)];
    self.navigationItem.rightBarButtonItems = @[addButton, resetButton];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];
}

- (void)addRegex {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Regex Filter"
                                                                   message:@"Enter a case-insensitive regular expression to remove from track and artist names."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"\\s[([]Remastered[)\\]]";
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Add"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
                                                NSString *text = alert.textFields.firstObject.text;
                                                if (text.length > 0) {
                                                    [self->_regexes insertObject:text atIndex:0];
                                                    [self->_prefs setObject:self->_regexes forKey:@"lfm_custom_regexes"];
                                                    [self.tableView reloadData];
                                                }
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetDefaults {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Reset Regex Filters"
                                                                   message:@"Restore the default regex filter list?"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                              style:UIAlertActionStyleDestructive
                                            handler:^(__unused UIAlertAction *action) {
                                                self->_regexes = [[LFMMetadata defaultRegexes] mutableCopy];
                                                [self->_prefs setObject:self->_regexes forKey:@"lfm_custom_regexes"];
                                                [self.tableView reloadData];
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (CGFloat)tableView:(__unused UITableView *)tableView heightForRowAtIndexPath:(__unused NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 1;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section {
    return @"Swipe left on any pattern to delete it, or tap + to add a custom regular expression.";
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return (NSInteger)_regexes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RegexCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"RegexCell"];
    }
    cell.textLabel.text = _regexes[(NSUInteger)indexPath.row];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightRegular];
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}

- (BOOL)tableView:(__unused UITableView *)tableView shouldHighlightRowAtIndexPath:(__unused NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView
    commitEditingStyle:(UITableViewCellEditingStyle)editingStyle
     forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [_regexes removeObjectAtIndex:(NSUInteger)indexPath.row];
        [_prefs setObject:_regexes forKey:@"lfm_custom_regexes"];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end

#pragma mark - Main Settings Controller (YTMusicUltimate UI/UX style)

@interface LFMSettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@end

@implementation LFMSettingsViewController {
    NSUserDefaults *_prefs;
}

- (NSString *)title {
    return @"YTMusic Last.fm";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    _prefs = [NSUserDefaults standardUserDefaults];

    UIBarButtonItem *closeButton = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark"]
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(closeButtonTapped:)];
    self.navigationItem.leftBarButtonItem = closeButton;

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)closeButtonTapped:(__unused id)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource & UITableViewDelegate

- (CGFloat)tableView:(__unused UITableView *)tableView heightForRowAtIndexPath:(__unused NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 4;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 1) return @"Metadata & Filters";
    if (section == 2) return @"Account & Queue";
    return nil;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"Scrobbles tracks longer than 30 seconds after 50% or 4 minutes of accumulated playback.";
    }
    if (section == 2) {
        return @"API Credentials override the values baked into the build. Saving clears the stored session, so you have to sign in again.";
    }
    if (section == 3) {
        NSDictionary *infoDictionary = [[NSBundle mainBundle] infoDictionary];
        NSString *appVersion = infoDictionary[@"CFBundleShortVersionString"] ?: @"unknown";
        return [NSString stringWithFormat:@"\nYouTubeMusic: v%@\nYTMusic Last.fm: v%@", appVersion, TWEAK_VERSION];
    }
    return nil;
}

- (void)tableView:(__unused UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
    if (section == 3 && [view isKindOfClass:[UITableViewHeaderFooterView class]]) {
        UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
        footer.textLabel.textAlignment = NSTextAlignmentCenter;
    }
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0:
            return 1; // Master Enabled switch
        case 1:
            return [_prefs boolForKey:@"lfm_musicbrainz_enabled"] ? 6 : 5;
        case 2:
            return 5; // Authenticate, Send Test Now Playing, Flush Offline Queue, Clear Session, API Credentials
        case 3:
            return 1; // Source Code link
        default:
            return 0;
    }
}

- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Section 0: Master Enable switch (identical to YTMUltimateSettingsController section 0)
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"masterSection"];
        cell.textLabel.text = @"Enabled";
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
        cell.textLabel.textColor = LFM_RED_COLOR;
        cell.imageView.image = [UIImage systemImageNamed:@"power"];
        cell.imageView.tintColor = LFM_RED_COLOR;
        cell.accessoryView = LFMCreateSwitch(LFM_RED_COLOR,
                                             [_prefs boolForKey:@"lfm_scrobbler_enabled"],
                                             self,
                                             @selector(toggleMasterSwitch:),
                                             0);
        return cell;
    }

    // Section 1: Metadata & Filters (PlayerSettingsController subtitle + blue ABCSwitch style)
    if (indexPath.section == 1) {
        if (indexPath.row < 4) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"boolsCell"];
            NSArray<NSDictionary *> *toggleItems = @[
                @{
                    @"title": @"Prefer oEmbed Metadata",
                    @"desc": @"Fetch original English track and channel titles from YouTube oEmbed instead of localized Now Playing info.",
                    @"key": @"lfm_prefer_oembed"
                },
                @{
                    @"title": @"Regex Title Cleanup",
                    @"desc": @"Strip tags like (Remastered), [Explicit], and (Official Video) before scrobbling.",
                    @"key": @"lfm_regex_cleanup_enabled"
                },
                @{
                    @"title": @"Artist/Title Split",
                    @"desc": @"Turn \"Channel Name - Real Song\" into the real artist and song when YouTube passes the uploader as the artist.",
                    @"key": @"lfm_artist_split_enabled"
                },
                @{
                    @"title": @"MusicBrainz Correction",
                    @"desc": @"Query MusicBrainz for canonical artist and track capitalization.",
                    @"key": @"lfm_musicbrainz_enabled"
                }
            ];
            NSDictionary *data = toggleItems[(NSUInteger)indexPath.row];
            cell.textLabel.text = data[@"title"];
            cell.textLabel.adjustsFontSizeToFitWidth = YES;
            cell.detailTextLabel.text = data[@"desc"];
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.accessoryView = LFMCreateSwitch(LFM_BLUE_SWITCH_COLOR,
                                                 [_prefs boolForKey:data[@"key"]],
                                                 self,
                                                 @selector(toggleFeatureSwitch:),
                                                 indexPath.row);
            return cell;
        }

        if (indexPath.row == 4) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"navCell"];
            cell.textLabel.text = @"Regex Filters";
            cell.detailTextLabel.text = @"View, add, or reset regular expression patterns";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"slider.horizontal.3"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            return cell;
        }

        if (indexPath.row == 5) {
            UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"mbEmailCell"];
            cell.textLabel.text = @"MusicBrainz Contact Email";
            cell.detailTextLabel.text = @"Required in User-Agent header for MusicBrainz API requests";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"envelope"];
            NSString *email = [_prefs stringForKey:@"lfm_musicbrainz_email"];
            cell.accessoryView = LFMRightDetailLabel(email.length > 0 ? email : @"Not Set", nil);
            return cell;
        }
    }

    // Section 2: Account & Offline Queue
    if (indexPath.section == 2) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"accountSection"];
        if (indexPath.row == 0) {
            BOOL connected = [LFMClient hasSession];
            cell.textLabel.text = connected ? @"Re-authenticate Last.fm" : @"Authenticate Last.fm";
            cell.detailTextLabel.text = connected ? @"Session active — tap to sign in again" : @"Sign in with your Last.fm account in Safari";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:connected ? @"Checkmark.seal" : @"person.crop.circle.badge.checkmark"];
            if (!cell.imageView.image) {
                cell.imageView.image = [UIImage systemImageNamed:@"person.crop.circle"];
            }
            cell.accessoryView = LFMRightDetailLabel(connected ? @"Connected" : @"Not Connected",
                                                     connected ? [UIColor systemGreenColor] : [UIColor secondaryLabelColor]);
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Send Test Now Playing";
            cell.detailTextLabel.text = @"Verify your Last.fm API key and active session";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            NSUInteger pending = [LFMClient pendingScrobbleCount];
            cell.textLabel.text = @"Flush Offline Queue";
            cell.detailTextLabel.text = @"Retry queued scrobbles stored while offline";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"arrow.clockwise.icloud"];
            cell.accessoryView = LFMRightDetailLabel([NSString stringWithFormat:@"%lu pending", (unsigned long)pending], nil);
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Clear Session";
            cell.detailTextLabel.text = @"Log out and remove stored Last.fm session key";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"trash"];
            cell.imageView.tintColor = [UIColor redColor];
        } else {
            cell.textLabel.text = @"API Credentials";
            cell.detailTextLabel.text = @"Override the Last.fm API key and secret on this device";
            cell.detailTextLabel.numberOfLines = 0;
            cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
            cell.imageView.image = [UIImage systemImageNamed:@"key"];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        return cell;
    }

    // Section 3: Links (YTMUltimateSettingsController section 3 style)
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"linkSection"];
    cell.textLabel.text = @"Source Code";
    cell.textLabel.textColor = [UIColor systemBlueColor];
    cell.textLabel.adjustsFontSizeToFitWidth = YES;
    cell.detailTextLabel.text = @"StarKayC/lastfm-yt-music on GitHub";
    cell.detailTextLabel.numberOfLines = 0;
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.imageView.image = [UIImage systemImageNamed:@"chevron.left.forwardslash.chevron.right"];
    cell.imageView.tintColor = [UIColor systemBlueColor];
    return cell;
}

- (BOOL)tableView:(__unused UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) return NO;
    if (indexPath.section == 1 && indexPath.row < 4) return NO;
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        if (indexPath.row == 4) {
            LFMRegularExpressionsViewController *vc = [[LFMRegularExpressionsViewController alloc] init];
            [self.navigationController pushViewController:vc animated:YES];
        } else if (indexPath.row == 5) {
            [self promptForEmailWithSwitch:nil];
        }
        return;
    }

    if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            [self dismissViewControllerAnimated:YES completion:^{
                [LFMClient startAuthUserInitiated:YES];
            }];
        } else if (indexPath.row == 1) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            spinner.color = [UIColor labelColor];
            [spinner startAnimating];
            cell.accessoryView = spinner;

            [LFMClient sendTestScrobbleWithCompletion:^(__unused BOOL success, NSString *message) {
                cell.accessoryView = nil;
                cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Test Now Playing"
                                                                               message:message
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        } else if (indexPath.row == 2) {
            UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
            spinner.color = [UIColor labelColor];
            [spinner startAnimating];
            cell.accessoryView = spinner;

            [LFMClient flushQueue];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
            });
        } else if (indexPath.row == 3) {
            [LFMClient clearSession];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
        } else if (indexPath.row == 4) {
            [self.navigationController pushViewController:[[LFMCredentialsViewController alloc] init] animated:YES];
        }
        return;
    }

    if (indexPath.section == 3 && indexPath.row == 0) {
        NSURL *url = [NSURL URLWithString:@"https://github.com/StarKayC/lastfm-yt-music"];
        if (url && [[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
}

#pragma mark - Switch Actions

- (void)toggleMasterSwitch:(id)sender {
    [_prefs setBool:LFMSwitchIsOn(sender) forKey:@"lfm_scrobbler_enabled"];
}

- (void)toggleFeatureSwitch:(UIControl *)sender {
    BOOL on = LFMSwitchIsOn(sender);
    if (sender.tag == 0) {
        [_prefs setBool:on forKey:@"lfm_prefer_oembed"];
    } else if (sender.tag == 1) {
        [_prefs setBool:on forKey:@"lfm_regex_cleanup_enabled"];
    } else if (sender.tag == 2) {
        [_prefs setBool:on forKey:@"lfm_artist_split_enabled"];
    } else if (sender.tag == 3) {
        if (on) {
            NSString *email = [_prefs stringForKey:@"lfm_musicbrainz_email"];
            if (email.length == 0) {
                [self promptForEmailWithSwitch:sender];
                return;
            }
        }
        [_prefs setBool:on forKey:@"lfm_musicbrainz_enabled"];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)promptForEmailWithSwitch:(id)toggle {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"MusicBrainz Contact Email"
                                                                   message:@"MusicBrainz requires a contact email in the User-Agent header."
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = @"email@example.com";
        textField.keyboardType = UIKeyboardTypeEmailAddress;
        textField.text = [self->_prefs stringForKey:@"lfm_musicbrainz_email"];
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                              style:UIAlertActionStyleCancel
                                            handler:^(__unused UIAlertAction *action) {
                                                if (toggle) LFMSwitchSetOn(toggle, NO);
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
                                                NSString *email = alert.textFields.firstObject.text;
                                                if (email.length > 0) {
                                                    [self->_prefs setObject:email forKey:@"lfm_musicbrainz_email"];
                                                    if (toggle) [self->_prefs setBool:YES forKey:@"lfm_musicbrainz_enabled"];
                                                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                                                                  withRowAnimation:UITableViewRowAnimationAutomatic];
                                                } else if (toggle) {
                                                    LFMSwitchSetOn(toggle, NO);
                                                }
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - API Credentials Subcontroller

@implementation LFMCredentialsViewController {
    UITextField *_keyField;
    UITextField *_secretField;
    UITableView *_tableView;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"API Credentials";

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                                             style:UIBarButtonItemStyleDone
                                                                            target:self
                                                                            action:@selector(save)];

    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    _tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:_tableView];
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];

    NSString *keyOverride = [LFMClient apiKeyOverride];
    _keyField = LFMCredentialField(NO,
                                   keyOverride.length > 0 ? @"" : @"Using build value",
                                   keyOverride);
    // The stored secret is never shown back; typing replaces it, leaving it blank keeps it.
    _secretField = LFMCredentialField(YES,
                                      [LFMClient apiSecretOverride].length > 0 ? @"Saved - type to replace" : @"Using build value",
                                      @"");
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForFooterInSection:(__unused NSInteger)section {
    return @"Create a key at last.fm/api/account/create. Empty fields fall back to the values baked into the build. Saving clears the stored Last.fm session.";
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return 3;
}

- (void)tableView:(__unused UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row == 2) [self resetToBuildDefaults];
}

- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (indexPath.row == 2) {
        cell.textLabel.text = @"Reset to Build Defaults";
        cell.textLabel.textColor = [UIColor systemRedColor];
        return cell;
    }
    BOOL isSecret = indexPath.row == 1;
    cell.textLabel.text = isSecret ? @"API Secret" : @"API Key";
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UITextField *field = isSecret ? _secretField : _keyField;
    field.delegate = self;
    UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 180.0, 34.0)];
    field.frame = box.bounds;
    [box addSubview:field];
    cell.accessoryView = box;
    return cell;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (NSString *)trimmedTextOf:(UITextField *)field {
    NSString *text = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return text ?: @"";
}

- (void)save {
    [_keyField resignFirstResponder];
    [_secretField resignFirstResponder];

    NSString *key = [self trimmedTextOf:_keyField];
    NSString *typedSecret = [self trimmedTextOf:_secretField];
    NSString *secret = typedSecret.length > 0 ? typedSecret : [LFMClient apiSecretOverride];

    [LFMClient setAPIKeyOverride:key secretOverride:secret];
    _secretField.text = @"";
    _secretField.placeholder = secret.length > 0 ? @"Saved - type to replace" : @"Using build value";
    _keyField.placeholder = key.length > 0 ? @"" : @"Using build value";
    [self offerSignInWithMessage:@"Credentials saved. The stored Last.fm session was cleared."];
}

- (void)resetToBuildDefaults {
    [_keyField resignFirstResponder];
    [_secretField resignFirstResponder];

    [LFMClient setAPIKeyOverride:@"" secretOverride:@""];
    _keyField.text = @"";
    _keyField.placeholder = @"Using build value";
    _secretField.text = @"";
    _secretField.placeholder = @"Using build value";
    [self offerSignInWithMessage:@"Back to the build credentials. The stored Last.fm session was cleared."];
}

- (void)offerSignInWithMessage:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Credentials Updated"
                                                                  message:message
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Sign In"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self.navigationController dismissViewControllerAnimated:YES completion:^{
            [LFMClient startAuthUserInitiated:YES];
        }];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

#pragma mark - Account Menu Entry Hook (matches YTMusicUltimate Source/Settings.x)

%hook YTMAvatarAccountView

- (void)setAccountMenuUpperButtons:(id)arg1 lowerButtons:(id)arg2 {
    Class btnCls = objc_getClass("YTMAccountButton");
    SEL initSel = @selector(initWithTitle:identifier:icon:actionBlock:);
    if (!btnCls || ![btnCls instancesRespondToSelector:initSel]) {
        %orig;
        return;
    }

    @try {
        UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(24, 24)];
        UIImage *icon = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            UIImage *noteImage = [UIImage systemImageNamed:@"music.note.list"];
            UIView *imageView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 24, 24)];
            UIImageView *noteImageView = [[UIImageView alloc] initWithImage:noteImage];
            noteImageView.contentMode = UIViewContentModeScaleAspectFit;
            noteImageView.clipsToBounds = YES;
            noteImageView.tintColor = [UIColor redColor];
            noteImageView.frame = imageView.bounds;

            [imageView addSubview:noteImageView];
            [imageView.layer renderInContext:rendererContext.CGContext];
        }];

        YTMAccountButton *button = [[btnCls alloc]
            initWithTitle:@"YTMusic Last.fm"
               identifier:@"ytmlastfm"
                     icon:icon
              actionBlock:^(__unused BOOL finished) {
                  UINavigationController *nav = [[UINavigationController alloc]
                      initWithRootViewController:[[LFMSettingsViewController alloc] init]];
                  nav.modalPresentationStyle = UIModalPresentationFullScreen;

                  UIViewController *ancestorVC = nil;
                  if ([self respondsToSelector:@selector(_viewControllerForAncestor)]) {
                      ancestorVC = [self _viewControllerForAncestor];
                  }
                  if (!ancestorVC) {
                      ancestorVC = [LFMYouTubeInstances rootViewController];
                  }
                  [ancestorVC presentViewController:nav animated:YES completion:nil];
              }];
        button.tintColor = [UIColor redColor];

        NSMutableArray *arrDown = [[NSMutableArray alloc] init];
        if ([arg2 isKindOfClass:[NSArray class]]) {
            [arrDown addObjectsFromArray:arg2];
        }
        if (button) {
            [arrDown addObject:button];
        }
        %orig(arg1, arrDown);
    } @catch (NSException *e) {
        NSLog(@"Failed to attach settings button: %@", e);
        %orig;
    }
}

%end

%ctor {
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
        @"lfm_scrobbler_enabled": @YES,
        @"lfm_prefer_oembed": @NO,
        @"lfm_regex_cleanup_enabled": @NO,
        @"lfm_artist_split_enabled": @YES,
        @"lfm_musicbrainz_enabled": @NO,
        @"lfm_custom_regexes": [LFMMetadata defaultRegexes]
    }];
    %init;
}
