ROOTLESS ?= 0

ifeq ($(ROOTLESS),1)
	THEOS_LAYOUT_DIR_NAME = layout-rootless
	THEOS_PACKAGE_SCHEME = rootless
endif
TARGET = iphone:clang:14.5:14.0
PACKAGE_VERSION = 1.2.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Amber
$(TWEAK_NAME)_FILES = Tweak.xm

SUBPROJECTS = AmberSpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
