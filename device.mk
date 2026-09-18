#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/samsung/gtowifi_mainline

# Inherit options from mainline/qcom-common
TARGET_QCOM_SOC := sdm429
## TODO: Bringup the corresponding hardware and remove the following definitions
# Audio: ADSP + PM8953 codec + 2x aw87319 amplifier are not described in the DTS yet
TARGET_AUDIO_HAL := default-aidl
# Battery: no PMI632 charger / fuel gauge driver in the kernel
TARGET_HEALTH_HAL := cuttlefish
TARGET_SUPPORTS_SUSPEND := false
# Display: 12nm DSI PHY is not in the kernel, lk2nd's framebuffer is all there is
TARGET_USES_FRAMEBUFFER_DISPLAY := true
include device/mainline/qcom-common/optional/options.mk

# Inherit from mainline/qcom-common
$(call inherit-product, device/mainline/qcom-common/mainline_qcom-common.mk)

# AAPT
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := hdpi

# Bluetooth
# Class of Device: service 0x1A (networking, capturing, object transfer), major 1 (computer),
# minor 0x1C (tablet)
PRODUCT_ODM_PROPERTIES += \
    bluetooth.device.class_of_device=26,1,28

# WCNSS answers Android's vendor-capabilities HCI command with a mangled opcode and the stack aborts
PRODUCT_ODM_PROPERTIES += \
    bluetooth.core.le.vendor_capabilities.enabled=false

# Boot animation
TARGET_SCREEN_HEIGHT := 1280
TARGET_SCREEN_WIDTH := 800
TARGET_BOOTANIMATION_HALF_RES := true

# Dalvik heap
$(call inherit-product, frameworks/native/build/tablet-7in-hdpi-1024-dalvik-heap.mk)

# HIDL
PRODUCT_PACKAGES += \
    vndservicemanager

# Init
ifeq ($(GTOWIFI_MAINLINE_SYSTEM_ON_SDCARD),true)
PRODUCT_PACKAGES += \
    fstab.gtowifi.sdcard \
    fstab.gtowifi.sdcard.ramdisk
else
PRODUCT_PACKAGES += \
    fstab.gtowifi \
    fstab.gtowifi.ramdisk
endif

PRODUCT_PACKAGES += \
    init.gtowifi.rc \
    init.recovery.gtowifi.rc \
    ueventd.gtowifi.rc

PRODUCT_PACKAGES += \
    use_memfd.rc \
    zram.rc

# Kernel
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

PRODUCT_PACKAGES += \
    modules.load.normal

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(DEVICE_PATH)/overlays/overlay

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/tablet_core_hardware.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/tablet_core_hardware.xml

# Scoped Storage
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Shipping API level
PRODUCT_SHIPPING_API_LEVEL := 33

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH) \
    kernel/mainline/configs
