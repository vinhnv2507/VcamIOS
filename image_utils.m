#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import "VCamPaths.h"
#include <stdlib.h>
#include <math.h>

// ---- Preferences bundle ----
NSString *const kVCamEnabledKey = @"enabled";
NSString *const kVCamMediaPathKey = @"mediaPath";
NSString *const kVCamOffsetXKey = @"offsetX";
NSString *const kVCamOffsetYKey = @"offsetY";
NSString *const kVCamZoomKey = @"zoom";
NSString *const kVCamBrightnessKey = @"brightness";
NSString *const kVCamRotationKey = @"rotation";
NSString *const kVCamFlipHorizontalKey = @"flipHorizontal";
NSString *const kVCamFlipVerticalKey = @"flipVertical";

typedef NS_ENUM(NSInteger, VCamMode) {
    VCamModeNone = 0,
    VCamModeImage,
    VCamModeVideo
};

// ---- State (all guarded by vcamLock) ----
static VCamMode currentMode = VCamModeNone;
static CGImageRef replacementImage = NULL;
static AVURLAsset *videoAsset = nil;
static AVAssetReader *videoReader = nil;
static AVAssetReaderTrackOutput *videoOutput = nil;
static CGAffineTransform videoPreferredTransform;
static CIContext *sharedCIContext = NULL;
static NSLock *vcamLock = NULL;

static void ensureVCamLock(void) {
    if (vcamLock == NULL) {
        vcamLock = [[NSLock alloc] init];
    }
}

// Cached preference values, refreshed on each (re)load.
static NSString *cachedMediaPath = nil;
static BOOL cachedEnabled = YES;
static CGFloat cachedOffsetX = 0.0;
static CGFloat cachedOffsetY = 0.0;
static CGFloat cachedZoom = 1.0;
static CGFloat cachedBrightness = 0.0;
static CGFloat cachedRotation = 0.0;
static BOOL cachedFlipHorizontal = NO;
static BOOL cachedFlipVertical = NO;

static void readAdjustmentPreferences(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesFile()];
    cachedOffsetX = MAX(-1.0, MIN(1.0, [prefs[kVCamOffsetXKey] doubleValue]));
    cachedOffsetY = MAX(-1.0, MIN(1.0, [prefs[kVCamOffsetYKey] doubleValue]));
    double zoom = [prefs[kVCamZoomKey] doubleValue];
    cachedZoom = MAX(0.5, MIN(3.0, zoom == 0.0 ? 1.0 : zoom));
    cachedBrightness = MAX(-1.0, MIN(1.0, [prefs[kVCamBrightnessKey] doubleValue]));
    cachedRotation = [prefs[kVCamRotationKey] doubleValue];
    cachedFlipHorizontal = [prefs[kVCamFlipHorizontalKey] boolValue];
    cachedFlipVertical = [prefs[kVCamFlipVerticalKey] boolValue];
}

static void writeLoadStatus(NSString *message, BOOL loaded) {
    NSDictionary *status = @{
        @"loaded": @(loaded),
        @"message": message ?: @"Unknown",
        @"timestamp": [NSDate date]
    };
    [status writeToFile:VCamStatusFile() atomically:YES];
}

static NSString *currentPrefsMediaPath(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesFile()];
    NSString *path = prefs[kVCamMediaPathKey];
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        return nil;
    }
    return path;
}

static BOOL currentPrefsEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:VCamPreferencesFile()];
    id enabled = prefs[kVCamEnabledKey];
    if (enabled == nil) return YES; // default enabled
    return [enabled boolValue];
}

/// Frees all retained media. Must be called with vcamLock held.
static void freeMedia(void) {
    if (replacementImage) {
        CGImageRelease(replacementImage);
        replacementImage = NULL;
    }
    [videoReader cancelReading];
    videoOutput = nil;
    videoReader = nil;
    videoAsset = nil;
    videoPreferredTransform = CGAffineTransformIdentity;
    currentMode = VCamModeNone;
}

/// Loads an image file (png/jpg/jpeg) into replacementImage. Returns YES on success.
/// Must be called with vcamLock held.
static BOOL loadImageMedia(NSString *path) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], NULL);
    if (!source) return NO;
    // Downsample for large images to bound memory usage (target <= ~4K).
    CGImageRef image = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)@{
        (id)kCGImageSourceCreateThumbnailFromImageAlways : @YES,
        (id)kCGImageSourceCreateThumbnailWithTransform : @YES,
        (id)kCGImageSourceShouldCacheImmediately : @YES,
        (id)kCGImageSourceThumbnailMaxPixelSize : @(3840)
    });
    if (image) {
        replacementImage = image; // takes ownership of +1 retain
        currentMode = VCamModeImage;
        CFRelease(source);
        return YES;
    }
    CFRelease(source);
    return NO;
}

/// Creates a streaming reader. Only the current decoded frame is held in RAM.
/// Must be called with vcamLock held.
static BOOL startVideoReader(void) {
    if (!videoAsset) return NO;
    NSArray *tracks = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
    if (tracks.count == 0) return NO;
    AVAssetTrack *videoTrack = tracks[0];

    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:videoAsset error:&error];
    if (!reader || error) return NO;
    NSDictionary *settings = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc]
        initWithTrack:videoTrack outputSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) return NO;
    [reader addOutput:output];
    if (![reader startReading]) return NO;
    videoReader = reader;
    videoOutput = output;
    return YES;
}

static BOOL loadVideoMedia(NSString *path) {
    videoAsset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    NSArray *tracks = [videoAsset tracksWithMediaType:AVMediaTypeVideo];
    if (tracks.count == 0) { videoAsset = nil; return NO; }
    videoPreferredTransform = ((AVAssetTrack *)tracks[0]).preferredTransform;
    if (!startVideoReader()) { videoAsset = nil; return NO; }
    currentMode = VCamModeVideo;
    return YES;
}

void loadReplacementMedia(void) {
    ensureVCamLock();
    [vcamLock lock];

    // 1) Read (and cache) preferences.
    NSString *mediaPath = currentPrefsMediaPath();
    BOOL enabled = currentPrefsEnabled();
    readAdjustmentPreferences();
    if (![mediaPath isEqualToString:cachedMediaPath]) {
        cachedMediaPath = [mediaPath copy];
    }
    if (enabled != cachedEnabled) cachedEnabled = enabled;

    // 2) Always free the previous media first (fixes the memory leak).
    freeMedia();

    // 3) Nothing to do if disabled in preferences.
    if (!cachedEnabled || cachedMediaPath == nil) {
        writeLoadStatus(cachedEnabled ? @"No media selected" : @"VCam disabled", NO);
        [vcamLock unlock];
        return;
    }

    // 4) Ensure CIContext exists once.
    if (sharedCIContext == NULL) {
        sharedCIContext = [CIContext context];
    }

    // 5) Load based on extension.
    NSString *ext = [cachedMediaPath pathExtension].lowercaseString;
    BOOL loaded = NO;
    if ([ext isEqualToString:@"png"] || [ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"]) {
        loaded = loadImageMedia(cachedMediaPath);
    }
    else if ([ext isEqualToString:@"mp4"] || [ext isEqualToString:@"mov"] || [ext isEqualToString:@"m4v"]) {
        loaded = loadVideoMedia(cachedMediaPath);
    }

    if (!loaded) {
        currentMode = VCamModeNone;
        writeLoadStatus(@"Could not load selected media", NO);
    } else {
        writeLoadStatus(currentMode == VCamModeImage ? @"Image loaded" : @"Video loaded", YES);
    }

    [vcamLock unlock];
}

void reloadReplacementAdjustments(void) {
    ensureVCamLock();
    [vcamLock lock];
    readAdjustmentPreferences();
    [vcamLock unlock];
}

void unloadReplacementMedia(void) {
    ensureVCamLock();
    [vcamLock lock];
    freeMedia();
    [vcamLock unlock];
}

BOOL drawReplacementOntoBuffer(CVPixelBufferRef targetBuffer) {
    if (!targetBuffer) return NO;

    CGFloat targetWidth = CVPixelBufferGetWidth(targetBuffer);
    CGFloat targetHeight = CVPixelBufferGetHeight(targetBuffer);
    if (targetWidth <= 0 || targetHeight <= 0) return NO;

    ensureVCamLock();
    [vcamLock lock];

    CMSampleBufferRef activeVideoSample = NULL;
    CIImage *replacementCIImage = nil;
    if (currentMode == VCamModeImage && replacementImage) {
        replacementCIImage = [CIImage imageWithCGImage:replacementImage];
    }
    else if (currentMode == VCamModeVideo && videoOutput) {
        activeVideoSample = [videoOutput copyNextSampleBuffer];
        if (!activeVideoSample) {
            // End of file: create a fresh reader and loop from the first frame.
            [videoReader cancelReading];
            videoReader = nil;
            videoOutput = nil;
            if (startVideoReader()) activeVideoSample = [videoOutput copyNextSampleBuffer];
        }
        CVPixelBufferRef frame = activeVideoSample ? CMSampleBufferGetImageBuffer(activeVideoSample) : NULL;
        if (frame) {
            replacementCIImage = [CIImage imageWithCVPixelBuffer:frame];
            replacementCIImage = [replacementCIImage imageByApplyingTransform:videoPreferredTransform];
        }
    }

    if (!replacementCIImage || !sharedCIContext) {
        if (activeVideoSample) CFRelease(activeVideoSample);
        [vcamLock unlock];
        return NO;
    }

    if (fabs(cachedBrightness) > 0.001) {
        replacementCIImage = [replacementCIImage imageByApplyingFilter:@"CIColorControls"
            withInputParameters:@{kCIInputBrightnessKey: @(cachedBrightness)}];
    }

    CGRect extent = replacementCIImage.extent;
    if (extent.size.width <= 0 || extent.size.height <= 0) {
        if (activeVideoSample) CFRelease(activeVideoSample);
        [vcamLock unlock];
        return NO;
    }

    CGFloat radians = cachedRotation * (CGFloat)M_PI / 180.0;
    if (fabs(radians) > 0.0001 || cachedFlipHorizontal || cachedFlipVertical) {
        CGFloat centerX = CGRectGetMidX(extent);
        CGFloat centerY = CGRectGetMidY(extent);
        CGAffineTransform transform = CGAffineTransformIdentity;
        transform = CGAffineTransformTranslate(transform, centerX, centerY);
        transform = CGAffineTransformRotate(transform, radians);
        transform = CGAffineTransformScale(transform,
            cachedFlipHorizontal ? -1.0 : 1.0,
            cachedFlipVertical ? -1.0 : 1.0);
        transform = CGAffineTransformTranslate(transform, -centerX, -centerY);
        replacementCIImage = [replacementCIImage imageByApplyingTransform:transform];
        extent = replacementCIImage.extent;
    }

    // Normalize EXIF/transformed origins, then aspect-fill the entire camera frame.
    CIImage *normalized = [replacementCIImage imageByApplyingTransform:
        CGAffineTransformMakeTranslation(-extent.origin.x, -extent.origin.y)];
    CGRect normalizedExtent = normalized.extent;
    CGFloat scale = MAX(targetWidth / normalizedExtent.size.width,
                        targetHeight / normalizedExtent.size.height) * cachedZoom;
    CGAffineTransform scaleXform = CGAffineTransformMakeScale(scale, scale);
    CIImage *scaled = [normalized imageByApplyingTransform:scaleXform];
    CGRect scaledExtent = scaled.extent;

    CGFloat offX = (targetWidth  - scaledExtent.size.width)  / 2.0 + cachedOffsetX * targetWidth;
    CGFloat offY = (targetHeight - scaledExtent.size.height) / 2.0 + cachedOffsetY * targetHeight;
    CGAffineTransform translate = CGAffineTransformMakeTranslation(offX, offY);
    CGRect targetRect = CGRectMake(0, 0, targetWidth, targetHeight);
    CIImage *filled = [[scaled imageByApplyingTransform:translate] imageByCroppingToRect:targetRect];
    CIImage *background = [[CIImage imageWithColor:
        [CIColor colorWithRed:0 green:0 blue:0 alpha:1]] imageByCroppingToRect:targetRect];
    CIImage *final = [filled imageByCompositingOverImage:background];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    [sharedCIContext render:final
            toCVPixelBuffer:targetBuffer
                     bounds:targetRect
                 colorSpace:colorSpace];
    CGColorSpaceRelease(colorSpace);

    if (activeVideoSample) CFRelease(activeVideoSample);
    [vcamLock unlock];
    return YES;
}

// Lifelong state construction (safe on first use; we own it for process lifetime).
__attribute__((constructor))
static void vcamInit(void) {
    if (vcamLock == NULL) {
        vcamLock = [[NSLock alloc] init];
    }
}
