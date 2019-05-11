PACKAGE_VERSION = 0.0.3.1
TARGET = iphone:11.2:7.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Amber
Amber_FILES = Tweak.xm

SUBPROJECTS = CCModule Switch

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk