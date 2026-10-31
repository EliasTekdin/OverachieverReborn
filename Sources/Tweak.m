// SPDX-License-Identifier: MIT
//
// Community rebuild of Overachiever for Apelin's rootless and roothide
// tweak projects. The implementation intentionally stays in Objective-C and
// installs its small integration hook with MSHookMessageEx.

#import <Foundation/Foundation.h>
#import <GameKit/GameKit.h>
#import <os/log.h>
#import <substrate.h>
#import <objc/runtime.h>

static NSString * const kOverachieverPreferencesPath =
    @"/var/mobile/Library/Preferences/de.ingmarstein.overachiever.plist";
static NSString * const kOverachieverEnabledKey = @"OverachieverEnabled";

static os_log_t OverachieverLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create(APELIN_PACKAGE_ID, "tweak");
    });
    return log;
}

static dispatch_queue_t OverachieverQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = dispatch_queue_create("com.ilyastekdin.overachieverreborn.sync",
                                      DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

static NSMutableSet<NSString *> *OverachieverSubmittedIdentifiers(void) {
    static NSMutableSet<NSString *> *identifiers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        identifiers = [NSMutableSet set];
    });
    return identifiers;
}

static BOOL OverachieverIsEnabled(void) {
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:kOverachieverPreferencesPath];
    NSNumber *enabled = preferences[kOverachieverEnabledKey];
    return enabled == nil || enabled.boolValue;
}

static void OverachieverRequestSync(NSString *reason);

static void (*OriginalSetAuthenticateHandler)(id self, SEL _cmd, id handler);
static BOOL gOverachieverProcessing;
static BOOL gOverachieverRetryPending;
// The notification below is the primary retry path; this hook also covers
// hosts that install or replace their authentication handler without posting a
// notification at the same point in their startup sequence.
static void HookedSetAuthenticateHandler(id self, SEL _cmd, id handler) {
    if (OriginalSetAuthenticateHandler != NULL) {
        OriginalSetAuthenticateHandler(self, _cmd, handler);
    }
    OverachieverRequestSync(@"authenticateHandlerChanged");
}

static void OverachieverRequestSync(NSString *reason) {
    dispatch_async(OverachieverQueue(), ^{
        if ([reason isEqualToString:@"authenticationChanged"]) {
            [OverachieverSubmittedIdentifiers() removeAllObjects];
        }

        if (gOverachieverProcessing) {
            gOverachieverRetryPending = YES;
            return;
        }

        if (!OverachieverIsEnabled()) {
            os_log(OverachieverLog(), "Overachiever disabled by preferences");
            return;
        }

        GKLocalPlayer *player = GKLocalPlayer.local;
        if (!player.isAuthenticated) {
            os_log(OverachieverLog(), "Local player not authenticated");
            return;
        }

        gOverachieverProcessing = YES;
        os_log(OverachieverLog(), "Authenticated player; starting achievement sync (%{public}s)",
               reason.UTF8String);

        [GKAchievementDescription loadAchievementDescriptionsWithCompletionHandler:
            ^(NSArray<GKAchievementDescription *> *descriptions, NSError *descriptionError) {
            dispatch_async(OverachieverQueue(), ^{
                if (descriptionError != nil || descriptions == nil) {
                    os_log_error(OverachieverLog(),
                                 "Failed to load achievement descriptions: %{public}s",
                                 (descriptionError.localizedDescription ?: @"unknown error").UTF8String);
                    gOverachieverProcessing = NO;
                    if (gOverachieverRetryPending) {
                        gOverachieverRetryPending = NO;
                        OverachieverRequestSync(@"pendingRetry");
                    }
                    return;
                }

                os_log(OverachieverLog(), "Loaded achievement descriptions: %lu",
                       (unsigned long)descriptions.count);

                [GKAchievement loadAchievementsWithCompletionHandler:
                    ^(NSArray<GKAchievement *> *achievements, NSError *achievementError) {
                    dispatch_async(OverachieverQueue(), ^{
                        if (achievementError != nil) {
                            os_log_error(OverachieverLog(),
                                         "Failed to load achievements: %{public}s",
                                         (achievementError.localizedDescription ?: @"unknown error").UTF8String);
                            gOverachieverProcessing = NO;
                            if (gOverachieverRetryPending) {
                                gOverachieverRetryPending = NO;
                                OverachieverRequestSync(@"pendingRetry");
                            }
                            return;
                        }

                        os_log(OverachieverLog(), "Loaded achievements: %lu",
                               (unsigned long)(achievements ?: @[]).count);

                        NSMutableDictionary<NSString *, GKAchievement *> *existingAchievements =
                            [NSMutableDictionary dictionary];
                        for (GKAchievement *achievement in achievements ?: @[]) {
                            if (achievement.identifier.length > 0) {
                                existingAchievements[achievement.identifier] = achievement;
                            }
                        }

                        NSMutableArray<GKAchievement *> *toSubmit = [NSMutableArray array];
                        NSMutableArray<NSString *> *submittedIdentifiers = [NSMutableArray array];
                        NSMutableSet<NSString *> *knownSubmissions = OverachieverSubmittedIdentifiers();

                        for (GKAchievementDescription *description in descriptions) {
                            NSString *identifier = description.identifier;
                            if (identifier.length == 0) {
                                continue;
                            }

                            GKAchievement *existing = existingAchievements[identifier];
                            if (existing.isCompleted || existing.percentComplete >= 100.0 ||
                                [knownSubmissions containsObject:identifier]) {
                                continue;
                            }

                            GKAchievement *achievement = [[GKAchievement alloc] initWithIdentifier:identifier];
                            achievement.percentComplete = 100.0;
                            achievement.showsCompletionBanner = NO;
                            [toSubmit addObject:achievement];
                            [submittedIdentifiers addObject:identifier];
                            [knownSubmissions addObject:identifier];
                            os_log(OverachieverLog(), "Submitting achievement %{public}s", identifier.UTF8String);
                        }

                        if (toSubmit.count == 0) {
                            os_log(OverachieverLog(), "No need to submit achievement");
                            gOverachieverProcessing = NO;
                            if (gOverachieverRetryPending) {
                                gOverachieverRetryPending = NO;
                                OverachieverRequestSync(@"pendingRetry");
                            }
                            return;
                        }

                        [GKAchievement reportAchievements:toSubmit
                            withCompletionHandler:^(NSError *reportError) {
                            dispatch_async(OverachieverQueue(), ^{
                                if (reportError != nil) {
                                    for (NSString *identifier in submittedIdentifiers) {
                                        [knownSubmissions removeObject:identifier];
                                    }
                                    os_log_error(OverachieverLog(),
                                                 "Failed to submit achievements: %{public}s",
                                                 (reportError.localizedDescription ?: @"unknown error").UTF8String);
                                } else {
                                    os_log(OverachieverLog(), "Submitted achievements: %lu",
                                           (unsigned long)toSubmit.count);
                                }

                                gOverachieverProcessing = NO;
                                if (gOverachieverRetryPending) {
                                    gOverachieverRetryPending = NO;
                                    OverachieverRequestSync(@"pendingRetry");
                                }
                            });
                        }];
                    });
                }];
            });
        }];
    });
}

__attribute__((constructor)) static void OverachieverInitialize(void) {
    // Apelin's confirm_loaded looks for this exact marker and build id under
    // the package id's subsystem. Keep the line, and keep it public.
    os_log(OverachieverLog(), "ApelinLoaded %{public}s in %{public}s", APELIN_BUILD_ID, getprogname());
    os_log(OverachieverLog(), "Loaded Overachiever");

    Class localPlayerClass = objc_getClass("GKLocalPlayer");
    if (localPlayerClass != Nil) {
        MSHookMessageEx(localPlayerClass,
                        @selector(setAuthenticateHandler:),
                        (IMP)HookedSetAuthenticateHandler,
                        (IMP *)&OriginalSetAuthenticateHandler);
    }

    [[NSNotificationCenter defaultCenter]
        addObserverForName:GKPlayerAuthenticationDidChangeNotificationName
                    object:nil
                     queue:nil
                usingBlock:^(__unused NSNotification *notification) {
        OverachieverRequestSync(@"authenticationChanged");
    }];

    // Delay the first GameKit query until the host has completed its initial
    // setup; all GameKit work and state changes remain off the main thread.
    dispatch_async(OverachieverQueue(), ^{
        OverachieverRequestSync(@"initialLoad");
    });
}
