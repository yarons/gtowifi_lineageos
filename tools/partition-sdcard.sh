#!/bin/bash
# Development layout for GTOWIFI_MAINLINE_SYSTEM_ON_SDCARD := true: put every Android partition on
# a microSD card so that nothing on the tablet's eMMC is written.
#
#   sudo tools/partition-sdcard.sh /dev/sdX [out/target/product/gtowifi_mainline]
#
# DESTROYS everything on /dev/sdX. Linux only (sgdisk, lsblk). Minimum card size 8 GB.
set -euo pipefail
DEV=${1:?usage: $0 /dev/sdX [product out dir]}
OUT=${2:-${ANDROID_PRODUCT_OUT:-}}

[ -b "$DEV" ] || { echo "$DEV is not a block device" >&2; exit 1; }
if [ "$(lsblk -dno RM "$DEV")" != 1 ] && [ "$(lsblk -dno TRAN "$DEV")" != usb ] && [ "$(lsblk -dno TRAN "$DEV")" != mmc ]; then
	echo "$DEV is neither removable, USB nor an SD slot: refusing" >&2
	exit 1
fi
if lsblk -no MOUNTPOINT "$DEV" | grep -q .; then
	echo "$DEV has mounted partitions: unmount them first" >&2
	exit 1
fi

lsblk -o NAME,SIZE,MODEL,TRAN,RM "$DEV"
read -r -p "Erase $DEV completely? Type the device name to confirm: " answer
[ "$answer" = "$DEV" ] || { echo aborted; exit 1; }

sgdisk --zap-all "$DEV"
sgdisk \
	-n 1:0:+3888M -c 1:system \
	-n 2:0:+760M  -c 2:vendor \
	-n 3:0:+448M  -c 3:vendor_dlkm \
	-n 4:0:+64M   -c 4:metadata \
	-n 5:0:+312M  -c 5:cache \
	-n 6:0:0      -c 6:userdata \
	"$DEV"
partprobe "$DEV" || true
sleep 2

part() { lsblk -lnpo NAME "$DEV" | sed -n "$(( $1 + 1 ))p"; }

if [ -n "$OUT" ]; then
	for spec in 1:system 2:vendor 3:vendor_dlkm; do
		n=${spec%%:*}; name=${spec##*:}; img=$OUT/$name.img
		[ -f "$img" ] || { echo "skip $name: $img missing"; continue; }
		if file "$img" | grep -q 'Android sparse'; then
			simg2img "$img" "$(part "$n")"
		else
			dd if="$img" of="$(part "$n")" bs=4M conv=fsync status=progress
		fi
	done
fi
mkfs.ext4 -q -L metadata "$(part 4)"
mkfs.ext4 -q -L cache "$(part 5)"
# userdata is formatted by Android on first boot (fstab: formattable)
sync
lsblk -o NAME,SIZE,PARTLABEL "$DEV"
