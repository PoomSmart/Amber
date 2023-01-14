PACKAGE_VERSION = 1.2.0
TARGET = iphone:clang:14.5:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Amber
$(TWEAK_NAME)_FILES = Tweak.xm

SUBPROJECTS = AmberSpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
