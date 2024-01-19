TARGET = iphone:clang:latest:14.0
PACKAGE_VERSION = 1.2.1

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Amber
$(TWEAK_NAME)_FILES = Tweak.xm

SUBPROJECTS = AmberSpringBoard

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
