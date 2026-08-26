#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#include <stdlib.h>

// ---- Preferences bundle ----
NSString *const kVCamPreferencesPath = @"/var/mobile/Library/Preferences/com.yourcompany.vcam.plist";
NSString *const kVCamEnabledKey = @"enabled";
NSString *const kVCamMediaPathKey = @"mediaPath";

typedef NS_ENUM(NSInteger, VCamMode) {
    VCamModeNone = 0,
    VCamModeImage,
    VCamModeVideo
};

// ---- State (all guarded by vcamLock) ----
static VCamMode currentMode = VCamModeNone;
static CGImageRef replacementImage = NULL;
static CVPixelBufferRef *videoFrames = NULL;
static size_t videoFrameCount = 0;
static size_t currentFrameIndex = 0;
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

static NSString *currentPrefsMediaPath(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kVCamPreferencesPath];
    NSString *path = prefs[kVCamMediaPathKey];
    if (![path isKindOfClass:[NSString class]] || path.length == 0) {
        return nil;
    }
    return path;
}

static BOOL currentPrefsEnabled(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kVCamPreferencesPath];
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
    if (videoFrames) {
        for (size_t i = 0; i < videoFrameCount; i++) {
            if (videoFrames[i]) CVPixelBufferRelease(videoFrames[i]);
        }
        free(videoFrames);
        videoFrames = NULL;
    }
    videoFrameCount = 0;
    currentFrameIndex = 0;
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

/// Loads a video and extracts frames into a bounded ring-buffer of CVPixelBuffers.
/// Must be called with vcamLock held.
static BOOL loadVideoMedia(NSString *path, NSUInteger maxFrames) {
    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    NSArray *tracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (tracks.count == 0) return NO;
    AVAssetTrack *videoTrack = tracks[0];

    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    if (error) return NO;

    NSDictionary *outputSettings = @{ (NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA) };
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:videoTrack outputSettings:outputSettings];
    output.alwaysCopiesSampleData = NO;

    if (![reader canAddOutput:output]) return NO;
    [reader addOutput:output];
    if (![reader startReading]) return NO;

    // Pre-allocate the ring buffer.
    videoFrames = calloc(maxFrames, sizeof(CVPixelBufferRef));
    if (!videoFrames) { [reader cancelReading]; return NO; }

    size_t count = 0;
    while (reader.status == AVAssetReaderStatusReading && count < maxFrames) {
        CMSampleBufferRef sampleBuffer = [output copyNextSampleBuffer];
        if (!sampleBuffer) break;
        CVPixelBufferRef pb = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (pb) {
            CVPixelBufferRetain(pb);
            videoFrames[count++] = pb;
        }
        CFRelease(sampleBuffer);
    }
    [reader cancelReading];

    if (count > 0) {
        videoFrameCount = count;
        currentMode = VCamModeVideo;
        return YES;
    }
    for (size_t i = 0; i < count; i++) {
        if (videoFrames[i]) CVPixelBufferRelease(videoFrames[i]);
    }
    free(videoFrames);
    videoFrames = NULL;
    return NO;
}

void loadReplacementMedia(void) {
    ensureVCamLock();
    [vcamLock lock];

    // 1) Read (and cache) preferences.
    NSString *mediaPath = currentPrefsMediaPath();
    BOOL enabled = currentPrefsEnabled();
    if (![mediaPath isEqualToString:cachedMediaPath]) {
        cachedMediaPath = [mediaPath copy];
    }
    if (enabled != cachedEnabled) cachedEnabled = enabled;

    // 2) Always free the previous media first (fixes the memory leak).
    freeMedia();

    // 3) Nothing to do if disabled in preferences.
    if (!cachedEnabled || cachedMediaPath == nil) {
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
        // Keep the daemon's peak memory bounded while still providing a short loop.
        loaded = loadVideoMedia(cachedMediaPath, 30);
    }

    if (!loaded) {
        currentMode = VCamModeNone;
    }

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

    ensureVCamLock();
    [vcamLock lock];

    CIImage *replacementCIImage = nil;
    if (currentMode == VCamModeImage && replacementImage) {
        replacementCIImage = [CIImage imageWithCGImage:replacementImage];
    }
    else if (currentMode == VCamModeVideo && videoFrames && videoFrameCount > 0) {
        CVPixelBufferRef frame = videoFrames[currentFrameIndex];
        currentFrameIndex = (currentFrameIndex + 1) % videoFrameCount;
        replacementCIImage = [CIImage imageWithCVPixelBuffer:frame];
    }

    if (!replacementCIImage || !sharedCIContext) {
        [vcamLock unlock];
        return NO;
    }

    CGFloat targetWidth  = CVPixelBufferGetWidth(targetBuffer);
    CGFloat targetHeight = CVPixelBufferGetHeight(targetBuffer);
    if (targetWidth <= 0 || targetHeight <= 0) { [vcamLock unlock]; return NO; }

    CGRect extent = replacementCIImage.extent;
    if (extent.size.width <= 0 || extent.size.height <= 0) { [vcamLock unlock]; return NO; }

    // Aspect-fit (letterbox).
    CGFloat scale = MIN(targetWidth / extent.size.width, targetHeight / extent.size.height);
    CGAffineTransform scaleXform = CGAffineTransformMakeScale(scale, scale);
    CIImage *scaled = [replacementCIImage imageByApplyingTransform:scaleXform];
    CGRect scaledExtent = scaled.extent;

    CGFloat offX = (targetWidth  - scaledExtent.size.width)  / 2.0;
    CGFloat offY = (targetHeight - scaledExtent.size.height) / 2.0;
    CGAffineTransform translate = CGAffineTransformMakeTranslation(offX, offY);
    CIImage *final = [scaled imageByApplyingTransform:translate];

    [sharedCIContext render:final toCVPixelBuffer:targetBuffer];

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
