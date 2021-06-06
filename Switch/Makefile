TARGET = iphone:clang:latest:7.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AmberFS
$(BUNDLE_NAME)_FILES = Switch.xm
$(BUNDLE_NAME)_CFLAGS = -fobjc-arc
$(BUNDLE_NAME)_LIBRARIES = flipswitch
$(BUNDLE_NAME)_FRAMEWORKS = UIKit
$(BUNDLE_NAME)_INSTALL_PATH = /Library/Switches

include $(THEOS_MAKE_PATH)/bundle.mk