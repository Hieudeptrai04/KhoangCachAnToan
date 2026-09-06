PACKAGE_VERSION = 1.1.2
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = KhoangCachAnToan
KhoangCachAnToan_FILES = $(wildcard *.m)
KhoangCachAnToan_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-error
KhoangCachAnToan_FRAMEWORKS = UIKit Foundation AVFoundation CoreMedia CoreVideo CoreImage ImageIO Vision CoreML CoreLocation CoreMotion QuartzCore AudioToolbox
# -I: dat DINH DANH CHU KY bang chinh bundle id. Khong co co nay, ldid tu sinh
# ten kieu "KhoangCachAnToan.<hash>.unsigned"; mediaserverd tra cuu quyen camera
# theo dinh danh chu ky nen se khong khop, va phien camera chay ma khong co khung nao.
KhoangCachAnToan_CODESIGN_FLAGS = -Sentitlements.plist -Icom.khoangcachantoan.app

include $(THEOS_MAKE_PATH)/application.mk
