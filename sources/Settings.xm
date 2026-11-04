// GPL-3.0-or-later
#import "../headers/Main.h"
#import "../headers/Metadata.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

@interface YTMAccountButton : UIButton
- (id)initWithTitle:(id)arg1 identifier:(id)arg2 icon:(id)arg3 actionBlock:(void (^)(BOOL finished))arg4;
@end

@interface YTMAvatarAccountView : UIView
@end

@interface UIView (LFMPrivateAncestor)
- (UIViewController *)_viewControllerForAncestor;
@end

@interface LFMRegularExpressionsViewController : UITableViewController
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

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                             target:self
                             action:@selector(addRegex)];
}

- (void)addRegex {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"New Regex"
                                                                   message:@"Enter a case-insensitive regular expression to strip from track/artist names."
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
                                                    [self->_regexes addObject:text];
                                                    [self->_prefs setObject:self->_regexes forKey:@"lfm_custom_regexes"];
                                                    [self.tableView reloadData];
                                                }
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return (NSInteger)_regexes.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RegexCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"RegexCell"];
        cell.textLabel.adjustsFontSizeToFitWidth = YES;
    }
    cell.textLabel.text = _regexes[(NSUInteger)indexPath.row];
    return cell;
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

@interface LFMSettingsViewController : UITableViewController
@end

@implementation LFMSettingsViewController {
    NSUserDefaults *_prefs;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Last.fm Scrobbler";
    _prefs = [NSUserDefaults standardUserDefaults];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Close"
                style:UIBarButtonItemStyleDone
               target:self
               action:@selector(closeTapped)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return 3;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return @"Last.fm Account";
    if (section == 1) return @"Metadata & Filters";
    if (section == 2) return @"MusicBrainz (Optional)";
    return nil;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 5; // Enable, Auth/Re-auth, Test Now Playing, Offline Queue, Clear Session
    if (section == 1) return 3; // Prefer oEmbed, Enable Regex Cleanup, Edit Regex Filters
    if (section == 2) {
        return [_prefs boolForKey:@"lfm_musicbrainz_enabled"] ? 2 : 1;
    }
    return 0;
}

- (UITableViewCell *)tableView:(__unused UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"LFMCell"];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Enable Scrobbler";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [_prefs boolForKey:@"lfm_scrobbler_enabled"];
            [toggle addTarget:self action:@selector(scrobblerToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Authenticate Last.fm";
            cell.detailTextLabel.text = [LFMClient hasSession] ? @"Connected" : @"Not Connected";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Send Test Now Playing";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 3) {
            cell.textLabel.text = @"Flush Offline Queue";
            cell.detailTextLabel.text = [NSString stringWithFormat:@"%lu pending", (unsigned long)[LFMClient pendingScrobbleCount]];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        } else if (indexPath.row == 4) {
            cell.textLabel.text = @"Clear Session";
            cell.textLabel.textColor = [UIColor systemRedColor];
        }
    } else if (indexPath.section == 1) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Prefer oEmbed (English Titles)";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [_prefs boolForKey:@"lfm_prefer_oembed"];
            [toggle addTarget:self action:@selector(oembedToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Enable Regex Cleanup";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [_prefs boolForKey:@"lfm_regex_cleanup_enabled"];
            [toggle addTarget:self action:@selector(regexToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 2) {
            cell.textLabel.text = @"Edit Regex Filters";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    } else if (indexPath.section == 2) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"Enable MusicBrainz";
            UISwitch *toggle = [[UISwitch alloc] init];
            toggle.on = [_prefs boolForKey:@"lfm_musicbrainz_enabled"];
            [toggle addTarget:self action:@selector(mbToggled:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 1) {
            cell.textLabel.text = @"Contact Email";
            cell.detailTextLabel.text = [_prefs stringForKey:@"lfm_musicbrainz_email"] ?: @"None";
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (void)scrobblerToggled:(UISwitch *)sender {
    [_prefs setBool:sender.isOn forKey:@"lfm_scrobbler_enabled"];
}

- (void)oembedToggled:(UISwitch *)sender {
    [_prefs setBool:sender.isOn forKey:@"lfm_prefer_oembed"];
}

- (void)regexToggled:(UISwitch *)sender {
    [_prefs setBool:sender.isOn forKey:@"lfm_regex_cleanup_enabled"];
}

- (void)mbToggled:(UISwitch *)sender {
    if (sender.isOn) {
        NSString *email = [_prefs stringForKey:@"lfm_musicbrainz_email"];
        if (email.length == 0) {
            [self promptForEmailWithSwitch:sender];
            return;
        }
    }
    [_prefs setBool:sender.isOn forKey:@"lfm_musicbrainz_enabled"];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2] withRowAnimation:UITableViewRowAnimationAutomatic];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        if (indexPath.row == 1) {
            [self dismissViewControllerAnimated:YES completion:^{
                [LFMClient startAuthUserInitiated:YES];
            }];
        } else if (indexPath.row == 2) {
            [LFMClient sendTestScrobbleWithCompletion:^(__unused BOOL success, NSString *message) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Test Now Playing"
                                                                               message:message
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            }];
        } else if (indexPath.row == 3) {
            [LFMClient flushQueue];
            [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        } else if (indexPath.row == 4) {
            [LFMClient clearSession];
            [self.tableView reloadData];
        }
    } else if (indexPath.section == 1 && indexPath.row == 2) {
        LFMRegularExpressionsViewController *vc = [[LFMRegularExpressionsViewController alloc] init];
        [self.navigationController pushViewController:vc animated:YES];
    } else if (indexPath.section == 2 && indexPath.row == 1) {
        [self promptForEmailWithSwitch:nil];
    }
}

- (void)promptForEmailWithSwitch:(UISwitch *)toggle {
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
                                                if (toggle) [toggle setOn:NO animated:YES];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Save"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
                                                NSString *email = alert.textFields.firstObject.text;
                                                if (email.length > 0) {
                                                    [self->_prefs setObject:email forKey:@"lfm_musicbrainz_email"];
                                                    if (toggle) [self->_prefs setBool:YES forKey:@"lfm_musicbrainz_enabled"];
                                                    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                                                                  withRowAnimation:UITableViewRowAnimationAutomatic];
                                                } else if (toggle) {
                                                    [toggle setOn:NO animated:YES];
                                                }
                                            }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end

%hook YTMAvatarAccountView

- (void)setAccountMenuUpperButtons:(id)arg1 lowerButtons:(id)arg2 {
    Class btnCls = objc_getClass("YTMAccountButton");
    SEL initSel = @selector(initWithTitle:identifier:icon:actionBlock:);
    if (!btnCls || ![btnCls instancesRespondToSelector:initSel]) {
        %orig;
        return;
    }

    @try {
        UIImage *icon = [UIImage systemImageNamed:@"music.note.list"];
        YTMAccountButton *button = [[btnCls alloc]
            initWithTitle:@"Last.fm Scrobbler"
               identifier:@"lfm_scrobbler"
                     icon:icon
              actionBlock:^(__unused BOOL finished) {
                  LFMSettingsViewController *settingsVC = [[LFMSettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
                  UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
                  nav.modalPresentationStyle = UIModalPresentationFormSheet;

                  UIViewController *ancestorVC = nil;
                  if ([self respondsToSelector:@selector(_viewControllerForAncestor)]) {
                      ancestorVC = [self _viewControllerForAncestor];
                  }
                  if (!ancestorVC) {
                      ancestorVC = [LFMYouTubeInstances rootViewController];
                  }
                  [ancestorVC presentViewController:nav animated:YES completion:nil];
              }];
        button.tintColor = [UIColor systemRedColor];

        NSMutableArray *arrDown = [NSMutableArray array];
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
        @"lfm_musicbrainz_enabled": @NO,
        @"lfm_custom_regexes": [LFMMetadata defaultRegexes]
    }];
    %init;
}
