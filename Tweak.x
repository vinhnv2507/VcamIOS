#import <CoreMedia/CoreMedia.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import "image_utils.h"
#import "VCamPaths.h"
#include <sys/stat.h>
#include <stdint.h>

// Track whether media was loaded for the current prefs; reload when it changes.
static BOOL vcam_needsLoad = YES;
static uint64_t vcam_liveStamp = 0;

static void vcam_ensureLoaded(void) {
    // Live video updates a single JPEG many times per second.  Do not make the
    // app rewrite preferences (and post a Darwin notification) for every
    // frame; detect the file's nanosecond mtime directly from the camera hook.
    if (!vcam_needsLoad) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesFile()];
        NSString *path = prefs[@"mediaPath"];
        NSString *livePath = [VCamSharedDirectory() stringByAppendingPathComponent:@"media-live.jpg"];
        if ([path isEqualToString:livePath]) {
            struct stat st;
            if (stat(path.fileSystemRepresentation, &st) == 0) {
                uint64_t stamp = ((uint64_t)st.st_mtimespec.tv_sec << 32) ^
                    (uint64_t)st.st_mtimespec.tv_nsec;
                if (stamp != vcam_liveStamp) {
                    vcam_liveStamp = stamp;
                    vcam_needsLoad = YES;
                }
            }
        }
    }
    if (vcam_needsLoad) {
        // Reset the flag before loading so a failure doesn't busy-loop every frame.
        vcam_needsLoad = NO;
        loadReplacementMedia();
    }
}

// Darwin notification callback: trigger a media reload when prefs change.
static void vcamPrefsChanged(CFNotificationCenterRef center, void *observer,
                             CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    vcam_needsLoad = YES;
    vcam_liveStamp = 0;
}

static void vcamAdjustmentsChanged(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    reloadReplacementAdjustments();
}

%hook BWNodeOutput

- (void)emitSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    unsigned int mediaType = ((unsigned int (*)(id, SEL))objc_msgSend)(self, sel_registerName("mediaType"));
    if (mediaType != 'vide') {
        %orig(sampleBuffer);
        return;
    }

    CVPixelBufferRef originalImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (originalImageBuffer == NULL) {
        %orig(sampleBuffer);
        return;
    }

    // First frame: (re)load media from preferences.
    vcam_ensureLoaded();

    // Camera callbacks may run without a short-lived autorelease pool. Core
    // Image creates temporary objects for every frame, so drain them here and
    // never let an unsupported buffer exception terminate the camera daemon.
    @autoreleasepool {
        @try {
            drawReplacementOntoBuffer(originalImageBuffer);
        } @catch (NSException *exception) {
            // Leave the real camera frame untouched when Core Image rejects a
            // transient/auxiliary pixel-buffer format.
        }
    }

    %orig(sampleBuffer);
}

%end

%ctor {
    // Watch for preference changes so media hot-reloads without a respring.
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        vcamPrefsChanged,
        (__bridge CFStringRef)@"com.yourcompany.vcam.prefs.changed",
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        vcamAdjustmentsChanged,
        (__bridge CFStringRef)@"com.yourcompany.vcam.adjustments.changed",
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately);
}
