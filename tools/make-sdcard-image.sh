#!/bin/bash
# Assemble ONE raw image of the microSD development layout, so that the card can be written from
# any OS with a plain dd (or an image writer) instead of tools/partition-sdcard.sh on Linux.
#
#   tools/make-sdcard-image.sh <dir with system.img vendor.img vendor_dlkm.img> [total MiB, default 7200]
#
# Layout (GPT names are what fstab.gtowifi_sdcard expects):
#   system 3888M, vendor 760M, vendor_dlkm 448M, metadata 64M (ext4), cache 312M (ext4), userdata rest (ext4)
# The default total fits every "8 GB" card. On a larger card userdata simply stays that size; the
# kernel only warns that the backup GPT is not at the end of the disk.
#
# Needs sgdisk, simg2img, mke2fs, file. No root, no loop devices: everything is done on the file.
set -euo pipefail
SRC=${1:?usage: $0 <image dir> [total MiB]}
TOTAL=${2:-7200}
IMG=$SRC/sdcard-gtowifi_mainline.img
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for t in sgdisk simg2img mke2fs file truncate; do command -v "$t" >/dev/null || { echo "$t not found" >&2; exit 1; }; done
for f in system vendor vendor_dlkm; do [ -f "$SRC/$f.img" ] || { echo "$SRC/$f.img missing" >&2; exit 1; }; done

rm -f "$IMG"
truncate -s "${TOTAL}M" "$IMG"
sgdisk -a 2048 \
	-n 1:0:+3888M -c 1:system \
	-n 2:0:+760M  -c 2:vendor \
	-n 3:0:+448M  -c 3:vendor_dlkm \
	-n 4:0:+64M   -c 4:metadata \
	-n 5:0:+312M  -c 5:cache \
	-n 6:0:0      -c 6:userdata \
	"$IMG" >/dev/null

start() { sgdisk -i "$1" "$IMG" | awk '/First sector/ {print $3}'; }
sectors() { sgdisk -i "$1" "$IMG" | awk '/Partition size/ {print $3}'; }

n=1
for f in system vendor vendor_dlkm; do
	raw=$SRC/$f.img
	if file "$raw" | grep -q 'Android sparse'; then
		simg2img "$raw" "$TMP/$f.raw"
		raw=$TMP/$f.raw
	fi
	size=$(stat -c%s "$raw")
	[ "$size" -le $(( $(sectors $n) * 512 )) ] || { echo "$f.img ($size bytes) does not fit its partition" >&2; exit 1; }
	dd if="$raw" of="$IMG" bs=1M seek=$(( $(start $n) / 2048 )) conv=notrunc status=none
	rm -f "$TMP/$f.raw"
	echo "wrote $f at sector $(start $n) ($size bytes)"
	n=$((n + 1))
done

# Android does not format a partition that holds leftovers of something else, so give it clean ext4
for spec in 4:metadata 5:cache 6:userdata; do
	n=${spec%%:*}; label=${spec##*:}
	mke2fs -q -F -t ext4 -L "$label" -E offset=$(( $(start $n) * 512 )) "$IMG" "$(( $(sectors $n) / 2 ))k"
	echo "formatted $label ($(( $(sectors $n) / 2048 )) MiB)"
done

sgdisk -p "$IMG" | tail -8
sgdisk -v "$IMG" | tail -2
ls -l "$IMG"
