export ARCHS = armv7
export TARGET = iphone:clang:10.3:8.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LiteboardRemove

LiteboardRemove_FILES = main.m
LiteboardRemove_FRAMEWORKS = UIKit Foundation
LiteboardRemove_LDFLAGS = -undefined dynamic_lookup
LiteboardRemove_CFLAGS = -fobjc-arc -Os -Wno-error=deprecated-module-dot-map -Wno-deprecated-module-dot-map
LiteboardRemove_CODESIGN_FLAGS = -S../entitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
