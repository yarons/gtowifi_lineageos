#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/samsung/gtowifi_mainline

# Inherit options from mainline/qcom-common
TARGET_QCOM_SOC := sdm429
## TODO: Bringup the corresponding hardware and remove the following definitions
# Audio: tinyhal (the default of mainline/qcom-common) on the ADSP + PM8953 codec + 2x aw87319 sound
# card; mixer paths in audio/audio.gtowifi_mainline.xml
# Battery: PMI632 SMB5 charger + simple-battery (kernel gtowifi/integration) show up as
# /sys/class/power_supply/pmi632-battery and pmi632-charger; capacity is voltage/OCV based
TARGET_HEALTH_HAL := default-aidl
TARGET_SUPPORTS_SUSPEND := false
# Display: mdp5 + 12nm DSI PHY + ILI9881C panel and the Adreno 504 (as FD505) from kernel branch
# gtowifi/display-v2 -> the defaults of mainline/common apply: Mesa freedreno, gbm, drm_hwcomposer.
# No backlight node yet: brightness stays where the boot loader left it.
# Sensors: accelerometer and proximity sit behind the ADSP; the kernel exposes them as IIO devices through
# IIO_QCOM_SMGR_* once the ADSP runs and has its registry (persist/sensors/sns.reg)
TARGET_SENSORS_HAL := iio
include device/mainline/qcom-common/optional/options.mk

# Inherit from mainline/qcom-common
$(call inherit-product, device/mainline/qcom-common/mainline_qcom-common.mk)

# AAPT
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := hdpi

# Audio
PRODUCT_PACKAGES += \
    audio.gtowifi_mainline.xml

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
# Both layouts are installed; the kernel command line picks one (androidboot.fstab_suffix)
PRODUCT_PACKAGES += \
    fstab.gtowifi \
    fstab.gtowifi.ramdisk \
    fstab.gtowifi_sdcard \
    fstab.gtowifi_sdcard.ramdisk

PRODUCT_PACKAGES += \
    init.gtowifi.rc \
    init.recovery.gtowifi.rc \
    ueventd.gtowifi.rc

PRODUCT_PACKAGES += \
    use_memfd.rc

# Kernel
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

PRODUCT_PACKAGES += \
    modules.load.normal

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(DEVICE_PATH)/overlays/overlay

# Overlays (runtime): the Wi-Fi resources live in an APEX, a static overlay does not reach them
PRODUCT_PACKAGES += \
    WifiOverlayGtowifiMainline

# Permissions
PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.touchscreen.multitouch.jazzhand.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/android.hardware.touchscreen.multitouch.jazzhand.xml \
    frameworks/native/data/etc/tablet_core_hardware.xml:$(TARGET_COPY_OUT_ODM)/etc/permissions/tablet_core_hardware.xml

# Scoped Storage
$(call inherit-product, $(SRC_TARGET_DIR)/product/emulated_storage.mk)

# Sensors
PRODUCT_PACKAGES += \
    android.hardware.sensor.accelerometer.prebuilt.xml

# Shipping API level
PRODUCT_SHIPPING_API_LEVEL := 33

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(DEVICE_PATH) \
    kernel/mainline/configs
