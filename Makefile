ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:16.5

# Sileo/Zebra reliably support gzip; Theos defaults to legacy raw LZMA.
THEOS_PLATFORM_DEB_COMPRESSION_TYPE = gzip

INSTALL_TARGET_PROCESSES = mediaserverd
THEOS_PACKAGE_SCHEME=rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = vcam

vcam_FILES = Tweak.x image_utils.m
vcam_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
vcam_FRAMEWORKS = AVFoundation CoreMedia CoreImage ImageIO Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
