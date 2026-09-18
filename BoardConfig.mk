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
# Development mode: every Android partition lives on the microSD card, eMMC is only read
GTOWIFI_BOOT_DEVICES := soc@0/7864900.mmc
else
GTOWIFI_BOOT_DEVICES := soc@0/7824900.mmc
endif

BOARD_KERNEL_CMDLINE := \
    $(MAINLINE_COMMON_ANDROIDBOOT_PARAMS) \
    $(MAINLINE_COMMON_KERNEL_PARAMS) \
    $(MAINLINE_QCOM_KERNEL_PARAMS) \
    $(MAINLINE_QCOM_SOC_KERNEL_PARAMS) \
    androidboot.boot_devices=$(GTOWIFI_BOOT_DEVICES) \
    androidboot.hardware=gtowifi \
    androidboot.verifiedbootstate=orange \
    console=tty0 \
    lk2nd.pass-ramoops=zap \
    lk2nd.pass-simplefb=xrgb8888,relocate

# TODO: write sepolicy for the mainline services, then drop this
BOARD_KERNEL_CMDLINE += \
    androidboot.selinux=permissive \
    audit=0

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

# VINTF
DEVICE_MANIFEST_FILE := \
    $(DEVICE_PATH)/vintf/manifest.xml
