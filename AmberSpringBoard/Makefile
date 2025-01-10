ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET = iphone:clang:latest:15.0
else
TARGET = iphone:clang:latest:14.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AmberSpringBoard
$(TWEAK_NAME)_FILES = AmberSpringBoard.x
$(TWEAK_NAME)_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
