THEOS_DEVICE_IP ?= localhost
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
# iOS 15–18: deployment target 15.0, build bằng SDK mới nhất của Theos.

TWEAK_NAME = TikTokPlus
TikTokPlus_FILES = Tweak.x
TikTokPlus_FRAMEWORKS = UIKit AVFoundation CoreMedia
TikTokPlus_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
# KHÔNG link Substrate: tweak chỉ dùng Logos hook trên class public +
# Objective-C runtime. Runtime hook của Feather (ElleKit-compatible) là đủ.
# Vì vậy không có dòng TikTokPlus_LIBRARIES = substrate ở đây — cố tình.

include $(THEOS)/makefiles/common.mk
include $(THEOS)/makefiles/tweak.mk
SUBPROJECTS += TikTokPlusPrefs
include $(THEOS)/makefiles/aggregate.mk
