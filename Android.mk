#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

LOCAL_PATH := $(call my-dir)

ifeq ($(TARGET_DEVICE),gtowifi_mainline)

# The build stops looking for makefiles below a directory that has one
include $(LOCAL_PATH)/libcamera/Android.mk

endif
