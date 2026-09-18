#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#

PRODUCT_MAKEFILES := \
    aosp_gtowifi_mainline:$(LOCAL_DIR)/aosp_gtowifi_mainline.mk \
    lineage_gtowifi_mainline:$(LOCAL_DIR)/lineage_gtowifi_mainline.mk

$(foreach build_type, user userdebug eng, \
    $(eval COMMON_LUNCH_CHOICES += aosp_gtowifi_mainline-$(build_type)) \
    $(eval COMMON_LUNCH_CHOICES += lineage_gtowifi_mainline-$(build_type)))
