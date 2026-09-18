#!/bin/bash
# Repack the build's boot image for `fastboot boot` through an lk2nd that was built WITHOUT
# OSVERSION_IN_BOOTIMAGE=1 (every lk2nd release binary, and the one built by the kernel bring-up
# scripts). Such an lk2nd only understands header v0 with the DTB appended to the kernel.
#
# An lk2nd built by this device tree (in-tree, with the flag) takes boot.img.mkbootimg as it is.
#
#   tools/make-fastboot-boot-img.sh [out/target/product/gtowifi_mainline] [output.img]
#
# Needs unpack_bootimg and mkbootimg from the Android build (out/host/linux-x86/bin) on PATH.
set -euo pipefail
OUT=${1:-${ANDROID_PRODUCT_OUT:?run lunch first or pass the product out dir}}
DST=${2:-$OUT/boot-fastboot-v0.img}
SRC=$OUT/boot.img.mkbootimg
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

[ -f "$SRC" ] || { echo "$SRC not found: build bootimage first" >&2; exit 1; }

unpack_bootimg --boot_img "$SRC" --out "$TMP" --format=mkbootimg -0 > "$TMP/args"
[ -s "$TMP/dtb" ] || { echo "no dtb in $SRC (expected header v2)" >&2; exit 1; }
cat "$TMP/kernel" "$TMP/dtb" > "$TMP/kernel-dtb"

# Take everything from the original image except the version, the dtb and the kernel
args=()
skip=0
while IFS= read -r -d '' a; do
	if [ "$skip" = 1 ]; then skip=0; continue; fi
	case "$a" in
	--header_version|--dtb|--dtb_offset|--kernel) skip=1 ;;
	*) args+=("$a") ;;
	esac
done < "$TMP/args"

mkbootimg "${args[@]}" --header_version 0 --kernel "$TMP/kernel-dtb" --output "$DST"
ls -l "$DST"
echo "fastboot boot $DST"
