#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

# boot.img / recovery.img layout for the SM-T290:
#
#   0          lk2nd.img (an Android boot image itself; its build appends "SEANDROIDENFORCE")
#   +lk2nd     512-byte "SignerVer02" block
#   ...        zero padding
#   512 KiB    the real Android boot image; lk2nd looks for it at this offset
#   ...        zero padding
#   end        AVB footer at the end of the 64 MiB partition
#
# Samsung bootloaders with binary revision 4 and later refuse ("SECURE CHECK FAIL") any boot or
# recovery image without the SignerVer02 block behind the first image and without an AVB footer at
# the end of the partition, even when unlocked. Both checks are structural; nothing is verified.
# Same trick as mkbootimg.mk in LineageOS/android_device_samsung_gtowifi, moved behind lk2nd.
#
# UNTESTED on hardware in this combined form. What is known to pass on a rev-5 unit: lk2nd alone
# with the same block and a footer whose image size covered lk2nd only.

ifneq ($(INSTALLED_LK2NDIMAGE_TARGET),)
MKBOOTIMG_LK2ND_IMAGE_PATH := $(INSTALLED_LK2NDIMAGE_TARGET)
else
MKBOOTIMG_LK2ND_IMAGE_PATH := $(DEVICE_PATH)/prebuilts/lk2nd-$(TARGET_LK2ND_PLATFORM).img
endif

# MAX_VBMETA_SIZE + MAX_FOOTER_SIZE of avbtool. get-hash-image-max-size only reserves this when
# BOARD_AVB_ENABLE is set, and the mainline stack leaves AVB off.
SAMSUNG_AVB_FOOTER_RESERVE := 69632

# strlen("SignerVer02") = 11
SAMSUNG_SIGNER_BLOCK_PADDING := 501

# $(1): output image
# $(2): mkbootimg image
# $(3): lk2nd image
# $(4): partition name
# $(5): partition size
define build-gtowifi-lk2nd-boot-image
	cp $(3) $(1)
	printf 'SignerVer02' >> $(1)
	truncate -s +$(SAMSUNG_SIGNER_BLOCK_PADDING) $(1)
	$(call assert-max-image-size,$(1),$(TARGET_LK2ND_ACTUAL_BOOTIMG_OFFSET))
	truncate -s $(TARGET_LK2ND_ACTUAL_BOOTIMG_OFFSET) $(1)
	cat $(2) >> $(1)
	$(call assert-max-image-size,$(1),$(5)-$(SAMSUNG_AVB_FOOTER_RESERVE))
	$(AVBTOOL) add_hash_footer \
		--image $(1) \
		--partition_size $(5) \
		--partition_name $(4) \
		--algorithm NONE
endef

$(foreach b,$(INSTALLED_BOOTIMAGE_TARGET), $(eval $(call add-dependency,$(b),$(call bootimage-to-kernel,$(b)))))

# $@.mkbootimg is kept: it is the image to use with `fastboot boot` from lk2nd
$(INSTALLED_BOOTIMAGE_TARGET): $(MKBOOTIMG) $(AVBTOOL) $(INTERNAL_BOOTIMAGE_FILES) $(BOOTIMAGE_EXTRA_DEPS) $(MKBOOTIMG_LK2ND_IMAGE_PATH)
	$(call pretty,"Target boot image with lk2nd: $@")
	$(MKBOOTIMG) --kernel $(call bootimage-to-kernel,$@) $(INTERNAL_BOOTIMAGE_ARGS) $(INTERNAL_MKBOOTIMG_VERSION_ARGS) $(BOARD_MKBOOTIMG_ARGS) --output $@.mkbootimg
	$(call build-gtowifi-lk2nd-boot-image,$@,$@.mkbootimg,$(MKBOOTIMG_LK2ND_IMAGE_PATH),boot,$(BOARD_BOOTIMAGE_PARTITION_SIZE))

$(INSTALLED_RECOVERYIMAGE_TARGET): $(AVBTOOL) $(recoveryimage-deps) $(RECOVERYIMAGE_EXTRA_DEPS) $(MKBOOTIMG_LK2ND_IMAGE_PATH)
	$(call pretty,"Target recovery image with lk2nd: $@")
	$(call build-recoveryimage-target,$@.mkbootimg,$(recovery_kernel))
	$(call build-gtowifi-lk2nd-boot-image,$@,$@.mkbootimg,$(MKBOOTIMG_LK2ND_IMAGE_PATH),recovery,$(BOARD_RECOVERYIMAGE_PARTITION_SIZE))
