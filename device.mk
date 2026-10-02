#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

DEVICE_PATH := device/samsung/gtowifi_mainline

# Audio effects with microphone pre-processing. PRODUCT_COPY_FILES: the first rule for a destination
# wins, so this has to come before mainline/common's tinyhal option copies the platform default.
PRODUCT_COPY_FILES += \
    device/samsung/gtowifi_mainline/audio/audio_effects.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio_effects.xml

# Inherit options from mainline/qcom-common
TARGET_QCOM_SOC := sdm429
## TODO: Bringup the corresponding hardware and remove the following definitions
# Audio: tinyhal (the default of mainline/qcom-common) on the ADSP + PM8953 codec + 2x aw87319 sound
# card; mixer paths in audio/audio.gtowifi_mainline.xml
# Battery: PMI632 SMB5 charger + simple-battery (kernel gtowifi/integration) show up as
# /sys/class/power_supply/pmi632-battery and pmi632-charger; the kernel counts the charge. Our own
# health HAL (health/) instead of mainline/common's default-aidl one: see "Health" below
TARGET_HEALTH_HAL := gtowifi
# Suspend (s2idle): ON, with kernel r15-mdpfix or later. Older kernels start the MDP's timing engine
# before its flush on the screen-on after a resume: the first frame is fetched from iova 0, the IOMMU
# fault interrupt storms and the tablet can hang (fixed by "drm/msm/mdp5: Flush before starting the video
# timing engine", verified 2026-09-30: 40 suspends, 0 faults). A release still needs the gate in
# docs/updating.md: repeated wake-ups by alarm and power key with display, touch, Wi-Fi, USB and audio
# working afterwards, and an unplugged overnight measurement.
TARGET_SUPPORTS_SUSPEND := true
# Display: mdp5 + 12nm DSI PHY + ILI9881C panel and the Adreno 504 (as FD505) from kernel branch
# gtowifi/display-v2 -> the defaults of mainline/common apply: Mesa freedreno, gbm, drm_hwcomposer.
# Backlight: pwm-backlight on the PM8953 PWM, /sys/class/backlight/backlight, which the stack's lights
# HAL looks for first (in the kernel since export r9; the slider has not been tried under Android).
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

# tinyhal reports its default capture period to AudioFlinger before the PCM is open. The default
# (256 frames) makes the record thread a "fast capture" one, and those refuse software effects
# ("non HW effect Noise Suppression on record thread ... in fast mode"): 1024 frames = 21 ms.
$(call soong_config_set,tinyhal,in_period_size_default,1024)

# Bluetooth
# Class of Device: service 0x1A (networking, capturing, object transfer), major 1 (computer),
# minor 0x1C (tablet)
PRODUCT_ODM_PROPERTIES += \
    bluetooth.device.class_of_device=26,1,28

# WCNSS answers Android's vendor-capabilities HCI command with a mangled opcode and the stack aborts
PRODUCT_ODM_PROPERTIES += \
    bluetooth.core.le.vendor_capabilities.enabled=false

# Cameras: GC8034 (rear) and GC2375H (front) on CAMSS deliver raw Bayer frames; libcamera's simple
# pipeline handler with the software ISP turns them into pictures, its camera HAL module is loaded by
# the legacy camera provider
PRODUCT_PACKAGES += \
    android.hardware.camera.provider@2.5-service_64 \
    camera.libcamera \
    libcamera \
    libcamera-base \
    ipa_soft_simple.so \
    ipa_soft_simple.so.sign \
    uncalibrated.yaml \
    libcamera-cam

PRODUCT_VENDOR_PROPERTIES += \
    ro.hardware.camera=libcamera

PRODUCT_COPY_FILES += \
    $(DEVICE_PATH)/libcamera/camera_hal.yaml:$(TARGET_COPY_OUT_VENDOR)/etc/libcamera/camera_hal.yaml \
    $(DEVICE_PATH)/libcamera/gc8034.yaml:$(TARGET_COPY_OUT_VENDOR)/etc/shared/libcamera/ipa/simple/gc8034.yaml \
    $(DEVICE_PATH)/libcamera/gc2375h.yaml:$(TARGET_COPY_OUT_VENDOR)/etc/shared/libcamera/ipa/simple/gc2375h.yaml \
    frameworks/native/data/etc/android.hardware.camera.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.xml \
    frameworks/native/data/etc/android.hardware.camera.front.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.camera.front.xml

# Boot animation
TARGET_SCREEN_HEIGHT := 1280
TARGET_SCREEN_WIDTH := 800
TARGET_BOOTANIMATION_HALF_RES := true

# Dalvik heap
$(call inherit-product, frameworks/native/build/tablet-7in-hdpi-1024-dalvik-heap.mk)

# GNSS: the location engine runs on the modem DSP. rmtfs (read-only, see init.gtowifi.rc) has to
# serve the modem before it boots; tqftpserv serves the files it asks for over TFTP (its MCFG
# configuration); the HAL speaks QMI LOC over QRTR
PRODUCT_PACKAGES += \
    android.hardware.gnss-service.qmiloc \
    init.gtowifi.modem.sh \
    rmtfs \
    rmtfs.rc \
    tqftpserv \
    tqftpserv.rc

PRODUCT_VENDOR_PROPERTIES += \
    vendor.remoteproc.4080000_remoteproc.ignore=1

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.location.gps.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.location.gps.xml

# Health: AOSP's default HAL, plus a battery that stays below its declared minimum voltage while
# discharging reads 0 %, so that Android shuts down before the pack cuts the power (health/)
PRODUCT_PACKAGES += \
    android.hardware.health-service.gtowifi

# Charging control (LineageOS Settings > Battery > Charging control): LineageOS' health HAL in toggle
# mode on the charger's charging_enabled (kernel "qcom_smbx: Add charge_behaviour and charging_enabled";
# 0 stops charging, the tablet keeps running from USB). A kids' tablet sits on its charger for days;
# held below full the pack ages more slowly.
PRODUCT_PACKAGES += \
    vendor.lineage.health-service.default
$(call soong_config_set,lineage_health,charging_control_charging_path,/sys/class/power_supply/pmi632-charger/charging_enabled)
$(call soong_config_set,lineage_health,charging_control_charging_enabled,1)
$(call soong_config_set,lineage_health,charging_control_charging_disabled,0)
$(call soong_config_set_bool,lineage_health,charging_control_supports_bypass,false)

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

# Shared memory through memfd: there is no ashmem driver. mainline's use_memfd.rc sets it from vendor_init,
# which SELinux does not allow for a platform property.
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    sys.use_memfd=true

# Hang safety net: Android's llkd.rc turns the kernel's hung-task detector on with
# ro.khungtask.enable and sets hung_task_panic, so a task stuck in uninterruptible sleep for five
# minutes panics and panic=5 restarts the tablet (BoardConfig.mk), instead of a frozen tablet
# that only the key combination brings back. Five minutes rather than a shorter time so that a long
# write to the slow eMMC (a large app install) is not mistaken for a hang.
PRODUCT_SYSTEM_EXT_PROPERTIES += \
    ro.khungtask.enable=true \
    ro.khungtask.timeout=300

# Kernel
PRODUCT_OTA_ENFORCE_VINTF_KERNEL_REQUIREMENTS := false

PRODUCT_PACKAGES += \
    modules.load.normal

# Media: camcorder profiles up to 720p with AAC audio instead of mainline/qcom-common's 480p ones
PRODUCT_PACKAGES += \
    media_profiles_gtowifi.xml

PRODUCT_VENDOR_PROPERTIES += \
    ro.media.xml_variant.profiles=_gtowifi

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
