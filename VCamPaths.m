#import "VCamPaths.h"

BOOL VCamIsRootless(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:@"/var/jb"];
}

NSString *VCamSharedDirectory(void) {
    // /tmp is private/redirected for some rootless application processes.
    // postinst creates this shared directory before the rootless app starts.
    return VCamIsRootless() ? @"/var/mobile/Library/VCam" : @"/tmp";
}

NSString *VCamPreferencesFile(void) {
    return [VCamSharedDirectory() stringByAppendingPathComponent:@"com.yourcompany.vcam.plist"];
}

NSString *VCamStatusFile(void) {
    return [VCamSharedDirectory() stringByAppendingPathComponent:@"com.yourcompany.vcam.status.plist"];
}

NSString *VCamMediaFile(NSString *extension) {
    NSString *name = [NSString stringWithFormat:@"media-%@.%@",
        NSUUID.UUID.UUIDString, extension.length ? extension : @"dat"];
    return [VCamSharedDirectory() stringByAppendingPathComponent:name];
}
