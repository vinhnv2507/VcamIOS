#import <Foundation/Foundation.h>

FOUNDATION_EXPORT BOOL VCamIsRootless(void);
FOUNDATION_EXPORT NSString *VCamSharedDirectory(void);
FOUNDATION_EXPORT NSString *VCamPreferencesFile(void);
FOUNDATION_EXPORT NSString *VCamStatusFile(void);
FOUNDATION_EXPORT NSString *VCamMediaFile(NSString *extension);
