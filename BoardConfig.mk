#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/samsung/gtowifi_mainline

# Inherit from mainline/qcom-common
include device/mainline/qcom-common/BoardConfigMainlineQcomCommon.mk

# A/B
AB_OTA_UPDATER := false

# Bootloader
# Samsung's bootloader starts lk2nd, lk2nd starts the Android boot image that follows it in the
# same partition. See mkbootimg.mk for the Samsung-specific trailer.
BOARD_BOOT_HEADER_VERSION := 2
BOARD_CUSTOM_BOOTIMG := true
BOARD_CUSTOM_BOOTIMG_MK := $(DEVICE_PATH)/mkbootimg.mk
BOARD_MKBOOTIMG_ARGS += --header_version $(BOARD_BOOT_HEADER_VERSION)
TARGET_LK2ND_MAKE_FLAGS := OSVERSION_IN_BOOTIMAGE=1

# Boot parameters
ifeq ($(GTOWIFI_MAINLINE_SYSTEM_ON_SDCARD),true)
# Development mode: every Android partition lives on the microSD card, eMMC is only read.
# Only the boot image differs between the two modes: system and vendor carry both fstabs.
GTOWIFI_BOOT_DEVICES := soc@0/7864900.mmc
GTOWIFI_FSTAB_SUFFIX := gtowifi_sdcard
else
GTOWIFI_BOOT_DEVICES := soc@0/7824900.mmc
GTOWIFI_FSTAB_SUFFIX := gtowifi
endif

BOARD_KERNEL_CMDLINE := \
    $(MAINLINE_COMMON_ANDROIDBOOT_PARAMS) \
    $(MAINLINE_COMMON_KERNEL_PARAMS) \
    $(MAINLINE_QCOM_KERNEL_PARAMS) \
    $(MAINLINE_QCOM_SOC_KERNEL_PARAMS) \
    androidboot.boot_devices=$(GTOWIFI_BOOT_DEVICES) \
    androidboot.fstab_suffix=$(GTOWIFI_FSTAB_SUFFIX) \
    androidboot.hardware=gtowifi \
    androidboot.verifiedbootstate=orange \
    lk2nd.pass-ramoops=zap \
    panic=5

# No console=tty0: the kernel log does not scroll over the screen at boot (this is a tablet for
# children); the serial console of mainline/qcom-common and ramoops still get it.
# panic=5: reboot five seconds after a panic. The default, 0, leaves a panicked kernel sitting there:
# the tablet looks frozen, still enumerates on USB, and only the Power + Volume Down combination gets
# it back. After the reboot it sits in lk2nd, where the ramoops console of the panic can be fetched
# (fastboot oem ramoops console, fastboot get_staged).

# Still permissive: sepolicy/vendor covers what one boot and a round of the apps logged, it has not
# run enforcing yet. The kernel's audit messages stay on so that the rest shows up in dmesg.
BOARD_KERNEL_CMDLINE += \
    androidboot.selinux=permissive

# Display
# 800x1280 on 8 inches; same density as the official LineageOS tree
TARGET_SCREEN_DENSITY := 213

# Filesystem
TARGET_USERIMAGES_USE_F2FS := true
TARGET_USERIMAGES_USE_EXT4 := true

# Kernel
BOARD_INCLUDE_DTB_IN_BOOTIMG := true
TARGET_KERNEL_SOURCE := kernel/mainline/msm89x7-mainline

TARGET_DTB_LIST_WILDCARD := \
    qcom/sdm429-samsung-gtowifi*

TARGET_KERNEL_CONFIG_EXT := \
    $(DEVICE_PATH)/kconfigs/config-postmarketos-qcom-msm89x7.aarch64 \
    kernel/mainline/configs/fragments/android-base-pre/common.config \
    kernel/mainline/configs/fragments/android-base-pre/arm64.config \
    kernel/configs/b/android-6.12/android-base.config \
    kernel/mainline/configs/fragments/android-base-conditional/CONFIG_ARM64-y.config \
    kernel/mainline/configs/fragments/common.config \
    kernel/mainline/configs/fragments/y/fbcon.config \
    kernel/mainline/configs/fragments/n/disable-clang-hardening-features.config \
    kernel/mainline/configs/fragments/n/faster-build-time.config \
    $(DEVICE_PATH)/kconfigs/fixups.config

# Kernel modules
BOARD_RECOVERY_RAMDISK_KERNEL_MODULES_LOAD := \
    $(strip $(shell cat $(DEVICE_PATH)/modprobe/modules.load.basic)) \
    $(strip $(shell cat $(DEVICE_PATH)/modprobe/modules.load.drm)) \
    $(strip $(shell cat $(DEVICE_PATH)/modprobe/modules.load.touchscreen))
BOARD_VENDOR_KERNEL_MODULES_LOAD := \
    $(BOARD_RECOVERY_RAMDISK_KERNEL_MODULES_LOAD)
RECOVERY_KERNEL_MODULES := \
    $(BOARD_RECOVERY_RAMDISK_KERNEL_MODULES_LOAD)

TARGET_AUTO_COLLECT_KERNEL_MODULE_DEPS := true

# OTA
TARGET_OTA_ASSERT_DEVICE := gtowifi,gtowifi_mainline

# Partitions
# Sizes from the device's PIT. Samsung's layout is kept as it is:
# vendor_dlkm lives in PRODUCT, metadata in LOGDUMP (see fstab/).
BOARD_FLASH_BLOCK_SIZE := 131072
BOARD_BOOTIMAGE_PARTITION_SIZE := 67108864
# CACHE is 312 MiB in the PIT; the image size is the one the official gtowifi tree uses
BOARD_CACHEIMAGE_PARTITION_SIZE := 317718528
BOARD_CACHEIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_RECOVERYIMAGE_PARTITION_SIZE := 67108864
BOARD_SYSTEMIMAGE_EXTFS_INODE_COUNT := -1
BOARD_SYSTEMIMAGE_PARTITION_SIZE := 4076863488
BOARD_VENDOR_DLKMIMAGE_EXTFS_INODE_COUNT := -1
BOARD_VENDOR_DLKMIMAGE_PARTITION_SIZE := 469762048
BOARD_VENDOR_DLKMIMAGE_FILE_SYSTEM_TYPE := ext4
BOARD_VENDORIMAGE_EXTFS_INODE_COUNT := -1
BOARD_VENDORIMAGE_PARTITION_SIZE := 796917760
BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE := ext4

BOARD_USES_METADATA_PARTITION := true
BOARD_USES_VENDOR_DLKMIMAGE := true
TARGET_COPY_OUT_VENDOR := vendor
TARGET_COPY_OUT_VENDOR_DLKM := vendor_dlkm

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/properties/vendor.prop

# Ramdisk
BOARD_RAMDISK_USE_LZ4 := true

# Recovery
TARGET_RECOVERY_DENSITY := hdpi
TARGET_RECOVERY_FSTAB := $(DEVICE_PATH)/fstab/fstab.gtowifi
TARGET_RECOVERY_PIXEL_FORMAT := BGRX_8888

# SELinux
BOARD_VENDOR_SEPOLICY_DIRS += \
    $(DEVICE_PATH)/sepolicy/vendor

# VINTF
DEVICE_MANIFEST_FILE := \
    $(DEVICE_PATH)/vintf/manifest.xml \
    $(DEVICE_PATH)/vintf/manifest_camera.xml

# Cameras: libcamera through aospext, see libcamera/Android.mk
BOARD_LIBCAMERA_SRC_DIR := external/libcamera-upstream
BOARD_LIBCAMERA_PATCHES_DIRS := $(DEVICE_PATH)/libcamera/patches
BOARD_LIBCAMERA_IPAS := simple
BOARD_LIBCAMERA_PIPELINES := simple
