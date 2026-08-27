#import "VCamPaths.h"

BOOL VCamIsRootless(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
}

NSString *VCamSharedDirectory(void) {
    // mediaserverd is sandboxed away from /var/mobile/Library on newer iOS.
    // The global temporary directory is visible to both the platform app and
    // the camera daemons on rootful and rootless jailbreaks.
    return @"/private/var/tmp";
}

NSString *VCamPreferencesFile(void) {
    return [VCamSharedDirectory() stringByAppendingPathComponent:@"com.yourcompany.vcam.plist"];
}

NSString *VCamStatusFile(void) {
    return [VCamSharedDirectory() stringByAppendingPathComponent:@"com.yourcompany.vcam.status.plist"];
}

NSString *VCamMediaFile(NSString *extension) {
    NSString *name = [NSString stringWithFormat:@"media-%@.%@",
        [[NSUUID UUID] UUIDString], extension.length ? extension : @"dat"];
    return [VCamSharedDirectory() stringByAppendingPathComponent:name];
}
