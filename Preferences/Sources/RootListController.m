// SPDX-License-Identifier: MIT
//
// Settings controller for Overachiever Reborn.

#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <objc/message.h>
#import <objc/runtime.h>

static id OASettingsSendId(id object, SEL selector) {
    if (object == nil || ![object respondsToSelector:selector]) {
        return nil;
    }
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}

static NSArray<NSDictionary<NSString *, NSString *> *> *OASettingsInstalledApplications(void) {
    Class workspaceClass = objc_getClass("LSApplicationWorkspace");
    id workspace = OASettingsSendId((id)workspaceClass, @selector(defaultWorkspace));
    NSArray *proxies = OASettingsSendId(workspace, @selector(allInstalledApplications));
    if (![proxies isKindOfClass:[NSArray class]]) {
        return @[];
    }

    NSMutableDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *unique =
        [NSMutableDictionary dictionary];
    for (id proxy in proxies) {
        NSString *bundleIdentifier = OASettingsSendId(proxy, @selector(applicationIdentifier));
        if (bundleIdentifier.length == 0) {
            bundleIdentifier = OASettingsSendId(proxy, @selector(bundleIdentifier));
        }
        if (bundleIdentifier.length == 0) {
            continue;
        }

        NSString *name = OASettingsSendId(proxy, @selector(localizedName));
        if (name.length == 0) {
            name = bundleIdentifier;
        }
        unique[bundleIdentifier] = @{
            @"identifier": bundleIdentifier,
            @"name": name,
        };
    }

    NSArray *applications = unique.allValues;
    return [applications sortedArrayUsingComparator:
        ^NSComparisonResult(NSDictionary<NSString *, NSString *> *first,
                            NSDictionary<NSString *, NSString *> *second) {
        NSComparisonResult result = [first[@"name"] localizedCaseInsensitiveCompare:second[@"name"]];
        if (result != NSOrderedSame) {
            return result;
        }
        return [first[@"identifier"] compare:second[@"identifier"]];
    }];
}

@interface OARootListController : PSListController
@end

@implementation OARootListController

- (NSArray *)specifiers {
    if (_specifiers == nil) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
        NSString *domain = [NSString stringWithUTF8String:APELIN_PACKAGE_ID];
        NSString *notification = [NSString stringWithFormat:@"%@/changed", domain];

        for (NSDictionary<NSString *, NSString *> *application in OASettingsInstalledApplications()) {
            NSString *bundleIdentifier = application[@"identifier"];
            NSString *key = [NSString stringWithFormat:@"ApplicationEnabled.%@", bundleIdentifier];
            NSString *label = [NSString stringWithFormat:@"%@ (%@)", application[@"name"], bundleIdentifier];
            PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:label
                                                                      target:self
                                                                         set:@selector(setPreferenceValue:specifier:)
                                                                         get:@selector(readPreferenceValue:)
                                                                      detail:nil
                                                                        cell:PSSwitchCell
                                                                        edit:nil];
            specifier.identifier = [NSString stringWithFormat:@"application.%@", bundleIdentifier];
            [specifier setProperty:key forKey:@"key"];
            [specifier setProperty:domain forKey:@"defaults"];
            [specifier setProperty:@YES forKey:@"default"];
            [specifier setProperty:notification forKey:@"PostNotification"];
            [_specifiers addObject:specifier];
        }
    }
    return _specifiers;
}

@end
