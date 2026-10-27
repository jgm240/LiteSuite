export ARCHS = armv7
export TARGET = iphone:clang:10.3:8.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LiteBoard

LiteBoard_FILES = main.m LBAppDelegate.m LBGridController.m LBLauncher.m LBHome.m LBRun.m LBApplication.m LBSettingsController.m LBUpdater.m helper/lbunzip.c
LiteBoard_FRAMEWORKS = UIKit Foundation CoreGraphics
LiteBoard_LDFLAGS = -undefined dynamic_lookup -lz
LiteBoard_CFLAGS = -fobjc-arc -Os -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map
LiteBoard_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
