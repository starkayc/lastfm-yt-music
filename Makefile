THEOS_PACKAGE_SCHEME = rootless
ARCHS := arm64 arm64e
TARGET := iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = YouTubeMusic

include $(THEOS)/makefiles/common.mk

LASTFM_API_KEY ?=
LASTFM_API_SECRET ?=
ifeq ($(strip $(LASTFM_API_KEY)),)
$(error Set LASTFM_API_KEY and LASTFM_API_SECRET, e.g. make package FINALPACKAGE=1 LASTFM_API_KEY=... LASTFM_API_SECRET=...)
endif
ifeq ($(strip $(LASTFM_API_SECRET)),)
$(error Set LASTFM_API_KEY and LASTFM_API_SECRET, e.g. make package FINALPACKAGE=1 LASTFM_API_KEY=... LASTFM_API_SECRET=...)
endif

TWEAK_NAME = LastFMYouTubeMusic

$(TWEAK_NAME)_FILES = $(wildcard sources/*.x sources/*.xm sources/*.m)
ifeq ($(SIDELOAD_FIXES),1)
$(TWEAK_NAME)_FILES += optional/Sideload.x
endif

$(TWEAK_NAME)_CFLAGS = -fobjc-arc -Iheaders -DAPI_KEY=@\"$(LASTFM_API_KEY)\" -DAPI_SECRET=@\"$(LASTFM_API_SECRET)\"
$(TWEAK_NAME)_FRAMEWORKS = UIKit Foundation MediaPlayer SafariServices Security CydiaSubstrate

include $(THEOS_MAKE_PATH)/tweak.mk
