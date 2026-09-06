PACKAGE_VERSION = 0.2.0
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = KhoangCachAnToan
KhoangCachAnToan_FILES = $(wildcard *.m)
KhoangCachAnToan_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
KhoangCachAnToan_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo CoreImage ImageIO Vision CoreML CoreLocation CoreMotion QuartzCore AudioToolbox
KhoangCachAnToan_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
