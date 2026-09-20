#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Cameras: upstream libcamera (simple pipeline handler on CAMSS + software ISP + its Android camera
# HAL) cross-compiled with meson through GloDroid's aospext, the same way mainline/common builds Mesa.
# The copy of libcamera in external/libcamera only builds the virtual and ipu7 pipelines and has no
# software ISP.
#
#   vendor/aospext                 https://github.com/GloDroid/aospext
#   external/libcamera-upstream    https://git.libcamera.org/libcamera/libcamera.git (v0.7.2)
#
# aospext's own meson_libcamera.mk stays off (BOARD_BUILD_AOSPEXT_LIBCAMERA is not set): it wants a
# libudev that AOSP does not have and does not know about libyaml/libyuv.

ifeq ($(TARGET_DEVICE),gtowifi_mainline)
ifneq ($(wildcard vendor/aospext/aospext_cross_compile.mk),)

LOCAL_PATH := vendor/aospext
include $(LOCAL_PATH)/aospext_cleanup.mk

AOSPEXT_PROJECT_NAME := LIBCAMERA
AOSPEXT_BUILD_SYSTEM := meson

# libcamera needs meson >= 1.0.1. aospext puts RUST_BIN_DIR first into PATH; the Mesa build brings a
# recent meson in prebuilts/mesa-build-dep/bin, and nothing here is written in Rust.
RUST_BIN_DIR := prebuilts/mesa-build-dep/bin

LOCAL_SHARED_LIBRARIES := libc libdl libexif libjpeg libevent libcrypto libyuv
# AOSP only has a static libyaml
LOCAL_STATIC_LIBRARIES := libyaml
AOSPEXT_GEN_PKGCONFIGS := libexif libjpeg dl libevent_pthreads libcrypto yaml-0.1 libyuv

MESON_BUILD_ARGUMENTS := \
    -Dwerror=false                                                       \
    -Dandroid=enabled                                                    \
    -Dandroid_platform=generic                                           \
    -Dipas=$(subst $(space),$(comma),$(BOARD_LIBCAMERA_IPAS))            \
    -Dpipelines=$(subst $(space),$(comma),$(BOARD_LIBCAMERA_PIPELINES))  \
    -Dsysconfdir=/vendor/etc                                             \
    -Dudev=disabled                                                      \
    -Dv4l2=disabled                                                      \
    -Dgstreamer=disabled                                                 \
    -Dqcam=disabled                                                      \
    -Dpycamera=disabled                                                  \
    -Ddocumentation=disabled                                             \
    -Dtracing=disabled                                                   \
    -Dlibdw=disabled                                                     \
    -Dlibunwind=disabled                                                 \
    -Dtest=false                                                         \
    -Dlc-compliance=disabled                                             \
    -Dcam=enabled

# Format: TYPE:REL_PATH_TO_INSTALL_ARTIFACT:VENDOR_SUBDIR:MODULE_NAME:SYMLINK_SUFFIX
# "libetc" installs into the library directory without stripping: the IPA module is signed, a
# stripped copy would fail the signature check and libcamera would want to run it in a separate
# process.
AOSPEXT_GEN_TARGETS := \
    lib:libcamera.so::libcamera:                                                     \
    lib:libcamera-base.so::libcamera-base:                                           \
    lib:libcamera-hal.so:hw:camera.libcamera:                                        \
    libetc:libcamera/ipa/ipa_soft_simple.so:libcamera/ipa:ipa_soft_simple.so:        \
    libetc:libcamera/ipa/ipa_soft_simple.so.sign:libcamera/ipa:ipa_soft_simple.so.sign: \
    etc:shared/libcamera/ipa/simple/uncalibrated.yaml:shared/libcamera/ipa/simple:uncalibrated.yaml: \
    bin:cam::libcamera-cam:

AOSPEXT_TARGETS_SO_DEPS := \
    camera.libcamera=libcamera:libcamera-base \
    libcamera=libcamera-base

LOCAL_MULTILIB := first
include $(LOCAL_PATH)/aospext_cross_compile.mk
include $(LOCAL_PATH)/aospext_gen_targets.mk

endif # vendor/aospext
endif # TARGET_DEVICE
