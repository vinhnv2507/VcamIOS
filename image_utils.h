#import <CoreMedia/CoreMedia.h>
#import <Foundation/Foundation.h>

/// Preferences bundle identifier used to store runtime settings.
FOUNDATION_EXPORT NSString *const kVCamEnabledKey;
FOUNDATION_EXPORT NSString *const kVCamMediaPathKey;
FOUNDATION_EXPORT NSString *const kVCamOffsetXKey;
FOUNDATION_EXPORT NSString *const kVCamOffsetYKey;
FOUNDATION_EXPORT NSString *const kVCamZoomKey;
FOUNDATION_EXPORT NSString *const kVCamBrightnessKey;
FOUNDATION_EXPORT NSString *const kVCamRotationKey;
FOUNDATION_EXPORT NSString *const kVCamFlipHorizontalKey;
FOUNDATION_EXPORT NSString *const kVCamFlipVerticalKey;

/// (Re)loads replacement media from the current preference path.
/// Safe to call multiple times; frees previous media first.
void loadReplacementMedia(void);

/// Refreshes position, zoom and brightness without reloading the media file.
void reloadReplacementAdjustments(void);

/// Draws the currently-loaded replacement media onto targetBuffer,
/// preserving aspect ratio (letterbox). Returns YES on success.
BOOL drawReplacementOntoBuffer(CVPixelBufferRef targetBuffer);

/// Frees all PCI-retained media. Called automatically before each reload.
void unloadReplacementMedia(void);
