ARCHS = arm64
TARGET := iphone:clang:16.5:15.0

# Sileo/Zebra reliably support gzip; Theos defaults to legacy raw LZMA.
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip
# Use Debian's native packager instead of Theos' dm.pl archive writer.
_THEOS_PLATFORM_DPKG_DEB = dpkg-deb

INSTALL_TARGET_PROCESSES = mediaserverd

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = vcam VCamOverlay

vcam_FILES = Tweak.x image_utils.m VCamPaths.m
vcam_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
vcam_FRAMEWORKS = AVFoundation CoreMedia CoreImage ImageIO Foundation

VCamOverlay_FILES = VCamOverlay.m VCamPaths.m
VCamOverlay_CFLAGS = -fobjc-arc
VCamOverlay_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk

APPLICATION_NAME = VCam

VCam_FILES = VCamApp/main.m VCamPaths.m
VCam_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
VCam_FRAMEWORKS = UIKit Foundation Photos AVFoundation CoreImage CoreMedia
VCam_RESOURCE_DIRS = VCamApp/Resources
VCam_CODESIGN_FLAGS = -SVCamApp/VCam.entitlements

include $(THEOS_MAKE_PATH)/application.mk
