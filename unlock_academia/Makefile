TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = Academia

ARCHS = arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = unlock_academia
unlock_academia_FILES = unlock_academia.m
unlock_academia_CFLAGS = -fobjc-arc
unlock_academia_FRAMEWORKS = UIKit Foundation
unlock_academia_PRIVATE_FRAMEWORKS =

include $(THEOS_MAKE_PATH)/tweak.mk
