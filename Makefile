ARCHS = arm64 arm64e

TARGET = iphone:clang:latest:14.0

THEOS_PACKAGE_SCHEME = rootless

THEOS_BUILD_DIR = .theos

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = APIClient

support_SRC = $(shell find support -name "*.m" -o -name "*.mm")

support_INC = $(addprefix -I,$(shell find support -type d))

headers_INC = $(addprefix -I,$(shell find headers -type d))

APIClient_FILES += $(wildcard sources/*.mm sources/*.m) $(support_SRC)

APIClient_CFLAGS = -fobjc-arc

APIClient_CFLAGS += $(support_INC) $(headers_INC)

APIClient_CCFLAGS = -std=c++17

APIClient_INSTALL_PATH = /usr/lib

include $(THEOS_MAKE_PATH)/tweak.mk
