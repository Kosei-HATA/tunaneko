LOCAL_PATH := $(call my-dir)
ROOT := $(LOCAL_PATH)/../../../..

OC_TRIPLET ?= unused
ifeq ($(TARGET_ARCH_ABI),arm64-v8a)
OC_TRIPLET := aarch64-linux-android
endif
ifeq ($(TARGET_ARCH_ABI),x86_64)
OC_TRIPLET := x86_64-linux-android
endif
# public header is copied to android/ by scripts/build_core.sh
OC_INCLUDE := $(ROOT)/native-build/openconnect-9.21/android

# prebuilt libopenconnect + dependencies (produced by scripts/build_core.sh)
include $(CLEAR_VARS)
LOCAL_MODULE := openconnect
LOCAL_SRC_FILES := $(ROOT)/app/libs/$(TARGET_ARCH_ABI)/libopenconnect.so
LOCAL_EXPORT_C_INCLUDES := $(OC_INCLUDE)
include $(PREBUILT_SHARED_LIBRARY)

include $(CLEAR_VARS)
LOCAL_MODULE := tunaneko
LOCAL_SRC_FILES := tunaneko_jni.c
LOCAL_SHARED_LIBRARIES := openconnect
LOCAL_LDLIBS := -llog
include $(BUILD_SHARED_LIBRARY)
