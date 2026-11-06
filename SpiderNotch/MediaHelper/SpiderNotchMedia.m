//
//  SpiderNotchMedia.m
//  SpiderNotch – the system "Now Playing" helper
//
//  macOS keeps one system-wide "Now Playing" record: what Control Center shows
//  for Music, Spotify, Safari, Chrome, Podcasts, VLC and every other app that
//  publishes what it plays. Apple only offers it through a private framework
//  (MediaRemote), and since macOS 15.4 it only answers Apple's own programs.
//
//  So SpiderNotch runs this small helper inside Apple's own /usr/bin/perl
//  (see now-playing.pl), which macOS still allows. The same approach is used by
//  the open-source mediaremote-adapter project (BSD-3-Clause, by Jonas van den
//  Berg); this is a smaller helper written for SpiderNotch.
//
//  Talking to SpiderNotch:
//    • It prints one line of JSON for every change:
//        {"type":"ready"}
//        {"type":"info","info":{...}}      or   {"type":"info","info":null}
//        {"type":"error","message":"..."}
//    • It reads commands, one per line: toggle, play, pause, next, previous,
//      seek <seconds>, refresh, quit. It quits when SpiderNotch closes its input.
//
//  It uses no CPU while nothing changes: macOS tells it about every change.
//

#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <stdio.h>
#import <stdlib.h>
#import <string.h>

typedef void (^SNInfoHandler)(CFDictionaryRef info);
typedef void (^SNClientHandler)(id client);
typedef void (^SNPlayingHandler)(Boolean playing);

typedef void (*SNGetNowPlayingInfo)(dispatch_queue_t queue, SNInfoHandler handler);
typedef void (*SNGetNowPlayingClient)(dispatch_queue_t queue, SNClientHandler handler);
typedef void (*SNGetIsPlaying)(dispatch_queue_t queue, SNPlayingHandler handler);
typedef CFStringRef (*SNClientGetString)(id client);
typedef void (*SNRegisterForNotifications)(dispatch_queue_t queue);
typedef Boolean (*SNSendCommand)(int command, CFDictionaryRef options);
typedef void (*SNSetElapsedTime)(double seconds);

static SNGetNowPlayingInfo getNowPlayingInfo;
static SNGetNowPlayingClient getNowPlayingClient;
static SNGetIsPlaying getIsPlaying;
static SNClientGetString clientBundleIdentifier;
static SNClientGetString clientParentBundleIdentifier;
static SNRegisterForNotifications registerForNotifications;
static SNSendCommand sendCommand;
static SNSetElapsedTime setElapsedTime;

static NSString *lastLine = nil;
static unsigned long long lastArtworkHash = 0;
static NSInteger refreshGeneration = 0;

// MediaRemote's command numbers.
enum {
    SNCommandPlay = 0,
    SNCommandPause = 1,
    SNCommandToggle = 2,
    SNCommandNext = 4,
    SNCommandPrevious = 5,
};

static void emitObject(NSDictionary *object) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (data == nil) {
        return;
    }
    fwrite(data.bytes, 1, data.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static void emitError(NSString *message) {
    emitObject(@{ @"type": @"error", @"message": message ?: @"unknown" });
}

static unsigned long long hashBytes(NSData *data) {
    // FNV-1a: a quick fingerprint, so unchanged artwork isn't sent again.
    unsigned long long hash = 1469598103934665603ULL;
    const unsigned char *bytes = data.bytes;
    for (NSUInteger index = 0; index < data.length; index++) {
        hash ^= bytes[index];
        hash *= 1099511628211ULL;
    }
    return hash == 0 ? 1 : hash;
}

static id jsonValue(id value) {
    if (value == nil || value == [NSNull null]) {
        return [NSNull null];
    }
    if ([value isKindOfClass:[NSString class]] || [value isKindOfClass:[NSNumber class]]) {
        return value;
    }
    if ([value isKindOfClass:[NSDate class]]) {
        return @([(NSDate *)value timeIntervalSince1970]);
    }
    return [value description];
}

static void emitInfo(NSDictionary *info, NSString *bundle, NSString *parent, BOOL playing) {
    NSString *title = info[@"kMRMediaRemoteNowPlayingInfoTitle"];
    if (info.count == 0 || ![title isKindOfClass:[NSString class]] || title.length == 0) {
        NSString *line = @"null";
        if (![line isEqualToString:lastLine]) {
            lastLine = line;
            lastArtworkHash = 0;
            emitObject(@{ @"type": @"info", @"info": [NSNull null] });
        }
        return;
    }

    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"bundleID"] = jsonValue(bundle);
    out[@"parentBundleID"] = jsonValue(parent);
    out[@"title"] = title;
    out[@"artist"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoArtist"]);
    out[@"album"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoAlbum"]);
    out[@"duration"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoDuration"]);
    out[@"elapsed"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoElapsedTime"]);
    out[@"rate"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"]);
    out[@"timestamp"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoTimestamp"]);
    out[@"uid"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoUniqueIdentifier"]
                            ?: info[@"kMRMediaRemoteNowPlayingInfoContentItemIdentifier"]);
    out[@"playing"] = @(playing);

    NSData *artwork = info[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
    unsigned long long artworkHash = 0;
    if ([artwork isKindOfClass:[NSData class]] && artwork.length > 0) {
        artworkHash = hashBytes(artwork);
    }
    out[@"artworkHash"] = [NSString stringWithFormat:@"%llx", artworkHash];

    // Only send the (big) artwork when it's new.
    NSData *withoutArtwork = [NSJSONSerialization dataWithJSONObject:out options:NSJSONWritingSortedKeys error:nil];
    NSString *line = withoutArtwork ? [[NSString alloc] initWithData:withoutArtwork encoding:NSUTF8StringEncoding] : @"";
    BOOL artworkIsNew = artworkHash != 0 && artworkHash != lastArtworkHash;
    if ([line isEqualToString:lastLine] && !artworkIsNew) {
        return;
    }
    lastLine = line;
    if (artworkIsNew) {
        out[@"artwork"] = [artwork base64EncodedStringWithOptions:0];
        out[@"artworkMime"] = jsonValue(info[@"kMRMediaRemoteNowPlayingInfoArtworkMIMEType"]);
        lastArtworkHash = artworkHash;
    } else if (artworkHash == 0) {
        lastArtworkHash = 0;
    }
    emitObject(@{ @"type": @"info", @"info": out });
}

static void refreshNow(void) {
    getNowPlayingInfo(dispatch_get_main_queue(), ^(CFDictionaryRef cfInfo) {
        NSDictionary *info = cfInfo ? [(__bridge NSDictionary *)cfInfo copy] : @{};
        void (^finish)(NSString *, NSString *) = ^(NSString *bundle, NSString *parent) {
            if (getIsPlaying != NULL) {
                getIsPlaying(dispatch_get_main_queue(), ^(Boolean playing) {
                    NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                    BOOL isPlaying = playing || ([rate isKindOfClass:[NSNumber class]] && rate.doubleValue > 0);
                    emitInfo(info, bundle, parent, isPlaying);
                });
            } else {
                NSNumber *rate = info[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
                emitInfo(info, bundle, parent, [rate isKindOfClass:[NSNumber class]] && rate.doubleValue > 0);
            }
        };
        if (getNowPlayingClient != NULL && clientBundleIdentifier != NULL) {
            getNowPlayingClient(dispatch_get_main_queue(), ^(id client) {
                NSString *bundle = nil;
                NSString *parent = nil;
                if (client != nil) {
                    CFStringRef value = clientBundleIdentifier(client);
                    bundle = value ? [(__bridge NSString *)value copy] : nil;
                    if (clientParentBundleIdentifier != NULL) {
                        CFStringRef parentValue = clientParentBundleIdentifier(client);
                        parent = parentValue ? [(__bridge NSString *)parentValue copy] : nil;
                    }
                }
                finish(bundle, parent);
            });
        } else {
            finish(nil, nil);
        }
    });
}

/// Many changes arrive in a burst: wait a moment and read everything once.
static void scheduleRefresh(double delay) {
    NSInteger generation = ++refreshGeneration;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (generation == refreshGeneration) {
            refreshNow();
        }
    });
}

static void runCommand(NSString *line) {
    NSArray<NSString *> *parts = [line componentsSeparatedByString:@" "];
    NSString *name = parts.firstObject ?: @"";
    if ([name isEqualToString:@"quit"]) {
        exit(0);
    } else if ([name isEqualToString:@"refresh"]) {
        scheduleRefresh(0);
        return;
    } else if ([name isEqualToString:@"seek"] && parts.count > 1) {
        if (setElapsedTime != NULL) {
            setElapsedTime(MAX(parts[1].doubleValue, 0));
        }
    } else {
        int command = -1;
        if ([name isEqualToString:@"toggle"]) command = SNCommandToggle;
        else if ([name isEqualToString:@"play"]) command = SNCommandPlay;
        else if ([name isEqualToString:@"pause"]) command = SNCommandPause;
        else if ([name isEqualToString:@"next"]) command = SNCommandNext;
        else if ([name isEqualToString:@"previous"]) command = SNCommandPrevious;
        if (command >= 0) {
            sendCommand(command, NULL);
        }
    }
    // Read the new state soon after a command (and once more a little later).
    scheduleRefresh(0.25);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        scheduleRefresh(0);
    });
}

static void readCommands(void) {
    char buffer[512];
    while (fgets(buffer, sizeof buffer, stdin) != NULL) {
        NSString *line = [[NSString stringWithUTF8String:buffer]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (line.length == 0) {
            continue;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            runCommand(line);
        });
    }
    // SpiderNotch closed our input (it quit): stop too.
    exit(0);
}

static void *symbol(void *library, const char *name) {
    return dlsym(library, name);
}

/// Called from now-playing.pl. Never returns.
__attribute__((visibility("default")))
void spidernotch_media_main(void) {
    @autoreleasepool {
        setvbuf(stdout, NULL, _IOLBF, 0);
        void *library = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        if (library == NULL) {
            emitError(@"MediaRemote is missing on this Mac.");
            exit(3);
        }
        getNowPlayingInfo = (SNGetNowPlayingInfo)symbol(library, "MRMediaRemoteGetNowPlayingInfo");
        getNowPlayingClient = (SNGetNowPlayingClient)symbol(library, "MRMediaRemoteGetNowPlayingClient");
        getIsPlaying = (SNGetIsPlaying)symbol(library, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        clientBundleIdentifier = (SNClientGetString)symbol(library, "MRNowPlayingClientGetBundleIdentifier");
        clientParentBundleIdentifier = (SNClientGetString)symbol(library, "MRNowPlayingClientGetParentAppBundleIdentifier");
        registerForNotifications = (SNRegisterForNotifications)symbol(library, "MRMediaRemoteRegisterForNowPlayingNotifications");
        sendCommand = (SNSendCommand)symbol(library, "MRMediaRemoteSendCommand");
        setElapsedTime = (SNSetElapsedTime)symbol(library, "MRMediaRemoteSetElapsedTime");
        if (getNowPlayingInfo == NULL || registerForNotifications == NULL || sendCommand == NULL) {
            emitError(@"This version of macOS changed MediaRemote.");
            exit(3);
        }

        registerForNotifications(dispatch_get_main_queue());
        NSArray<NSString *> *names = @[
            @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange",
            @"kMRNowPlayingPlaybackQueueChangedNotification",
        ];
        for (NSString *name in names) {
            [[NSNotificationCenter defaultCenter] addObserverForName:name
                                                              object:nil
                                                               queue:[NSOperationQueue mainQueue]
                                                          usingBlock:^(NSNotification *note) {
                scheduleRefresh(0.06);
            }];
        }

        // A slow safety check, in case an app forgets to announce a change.
        dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
        dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), 5 * NSEC_PER_SEC, NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer, ^{
            scheduleRefresh(0);
        });
        dispatch_resume(timer);

        [NSThread detachNewThreadWithBlock:^{
            readCommands();
        }];

        emitObject(@{ @"type": @"ready" });
        scheduleRefresh(0);
        CFRunLoopRun();
    }
    exit(0);
}
