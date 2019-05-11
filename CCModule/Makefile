TARGET = iphone:clang:11.2:11.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AmberCCModule
AmberCCModule_BUNDLE_EXTENSION = bundle
AmberCCModule_FILES = AmberCCModule.m
AmberCCModule_PRIVATE_FRAMEWORKS = ControlCenterUIKit
AmberCCModule_INSTALL_PATH = /Library/ControlCenter/Bundles/

include $(THEOS_MAKE_PATH)/bundle.mk