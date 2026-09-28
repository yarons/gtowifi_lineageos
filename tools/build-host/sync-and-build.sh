#!/bin/bash
# On the build host: LineageOS 23.2 + the gtowifi_mainline device tree + the Android kernel branch.
# Run inside tmux. Steps can be run one at a time:
#   ./sync-and-build.sh sync      repo init + sync (large download, hours)
#   ./sync-and-build.sh sources   device tree + kernel into the tree
#   ./sync-and-build.sh patches   platform patches the mainline stack needs
#   ./sync-and-build.sh build     images (eMMC layout; SDCARD=1 for the microSD development layout)
#   ./sync-and-build.sh all
# Environment: LINEAGE_DIR (default ~/android/lineage), PAYLOAD_DIR (default: where this script's
# payload was unpacked), SHALLOW=1 (default) syncs without history to save ~half the disk,
# JOBS for repo sync (default 4, the LineageOS default).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
PAYLOAD_DIR=${PAYLOAD_DIR:-$(dirname "$HERE")}
LINEAGE_DIR=${LINEAGE_DIR:-$HOME/android/lineage}
BRANCH=lineage-23.2
KERNEL_URL=https://github.com/yarons/linux_msm89x7.git
KERNEL_BASE=gtowifi/battery-v2       # public integration line: PM8953 USID fix, aw87319 + sound DT, PMI632
                                     # charger + QG battery (v2), regulator loads; its tip a1fb8b229 is the
                                     # bundle's prerequisite
KERNEL_BUNDLE=kernel/export-r5/gtowifi-android-7.1.3-r5.bundle   # the four ANDROID-only commits
KERNEL_BRANCH=gtowifi/android-7.1.3
# make-payload.sh can put another kernel line into the payload (KERNEL_BASE, KERNEL_BUNDLE)
# shellcheck disable=SC1091
[ -f "$HERE/kernel.env" ] && . "$HERE/kernel.env"
export PATH="$HOME/bin:$PATH"

step_sync() {
	mkdir -p "$LINEAGE_DIR" && cd "$LINEAGE_DIR"
	[ "${SHALLOW:-1}" = 1 ] && depth=--depth=1 || depth=
	repo init -u https://github.com/LineageOS/android.git -b "$BRANCH" --git-lfs --no-clone-bundle $depth
	repo sync -c -j"${JOBS:-4}" --no-tags --fail-fast
}

step_sources() {
	cd "$LINEAGE_DIR"
	# device tree: a plain git checkout next to repo's projects (not in a manifest until it is on GitHub)
	rm -rf device/samsung/gtowifi_mainline
	mkdir -p device/samsung
	git clone -q "$PAYLOAD_DIR/android_device_samsung_gtowifi_mainline" device/samsung/gtowifi_mainline
	# kernel: public base branch, then the four Android-only commits from the bundle
	if [ ! -d kernel/mainline/msm89x7-mainline/.git ]; then
		mkdir -p kernel/mainline
		git clone -q --depth 1 --branch "$KERNEL_BASE" "$KERNEL_URL" kernel/mainline/msm89x7-mainline
	else
		git -C kernel/mainline/msm89x7-mainline fetch -q --depth 1 "$KERNEL_URL" "$KERNEL_BASE"
	fi
	# re-runnable: never fetch into the branch that is checked out
	git -C kernel/mainline/msm89x7-mainline fetch -q "$PAYLOAD_DIR/$KERNEL_BUNDLE" \
		"$KERNEL_BRANCH"
	git -C kernel/mainline/msm89x7-mainline checkout -q -B "$KERNEL_BRANCH" FETCH_HEAD
	git -C kernel/mainline/msm89x7-mainline log --oneline -5
	# the mainline stack: roomservice cannot resolve lineage.dependencies for a device tree outside the
	# LineageOS organisation, and device.mk includes the stack before roomservice would run anyway
	mkdir -p .repo/local_manifests
	cp device/samsung/gtowifi_mainline/local_manifests/gtowifi_mainline_deps.xml .repo/local_manifests/
	# the camera stack (external/libcamera-upstream, vendor/aospext): gtowifi_mainline.xml without the device
	# tree and the kernel, which this step puts in place itself
	grep -v -e 'path="device/samsung/gtowifi_mainline"' -e 'path="kernel/mainline/msm89x7-mainline"' \
		device/samsung/gtowifi_mainline/local_manifests/gtowifi_mainline.xml > .repo/local_manifests/gtowifi_mainline.xml
	deps=$(sed -n 's/.*<project path="\([^"]*\)".*/\1/p' .repo/local_manifests/gtowifi_mainline_deps.xml \
		.repo/local_manifests/gtowifi_mainline.xml)
	# shellcheck disable=SC2086
	repo sync -c -j"${JOBS:-4}" --no-tags --force-sync $deps
	set +u; source build/envsetup.sh; breakfast gtowifi_mainline userdebug; set -u
}

step_patches() {
	# device/mainline/generic docs/patches.md lists four system/core changes (442536 471113 471112
	# 471111). Checked on review.lineageos.org on 2026-09-18: all four are ABANDONED on every branch;
	# the pause-on-fatal-error / console-boot aids moved into the stack's own generic_init, and the
	# ZRAM max_comp_streams fix only matters for an fstab that sets max_comp_streams (ours does not).
	# The external/mesa chain is only needed for TARGET_GRAPHICS := mesa, not for the framebuffer +
	# SwiftShader bring-up. So nothing to pick from Gerrit.
	#
	# The device tree carries its own platform patches: patches/<project path>/*.patch. Re-runnable:
	# a patch that is already in the tree is skipped. `repo sync` will report these projects as dirty.
	cd "$LINEAGE_DIR"
	local root=device/samsung/gtowifi_mainline/patches patch project
	[ -d "$root" ] || { echo "no device patches"; return 0; }
	while IFS= read -r patch; do
		project=$(dirname "${patch#"$root"/}")
		if git -C "$project" apply --reverse --check "$PWD/$patch" 2>/dev/null; then
			echo "already applied: $patch"
		elif git -C "$project" apply --check "$PWD/$patch"; then
			git -C "$project" apply "$PWD/$patch"
			echo "applied: $patch"
		else
			echo "PATCH DOES NOT APPLY: $patch" >&2
			return 1
		fi
	done < <(find "$root" -name '*.patch' | sort)
}

step_build() {
	cd "$LINEAGE_DIR"
	# eMMC layout by default; SDCARD=1 builds the boot image for the microSD development layout
	if [ "${SDCARD:-0}" = 1 ]; then export GTOWIFI_MAINLINE_SYSTEM_ON_SDCARD=true; fi
	set +u; source build/envsetup.sh; breakfast gtowifi_mainline userdebug; set -u
	ccache -M 30G >/dev/null 2>&1 || true
	# raw images for tools/partition-sdcard.sh, not an OTA zip. BUILD_JOBS limits the parallel jobs on a
	# host with little RAM (mka uses every thread)
	if [ -n "${BUILD_JOBS:-}" ]; then build=(m -j"$BUILD_JOBS"); else build=(mka); fi
	"${build[@]}" bootimage systemimage vendorimage vendor_dlkmimage 2>&1 | tee "$LINEAGE_DIR/build-gtowifi_mainline.log"
	rc=${PIPESTATUS[0]}
	echo "BUILD_RC=$rc" | tee -a "$LINEAGE_DIR/build-gtowifi_mainline.log"
	[ "$rc" = 0 ] || exit "$rc"
	out=out/target/product/gtowifi_mainline
	ls -la $out/boot.img $out/boot.img.mkbootimg $out/system.img $out/vendor.img $out/vendor_dlkm.img
	python3 device/samsung/gtowifi_mainline/tools/check-boot-layout.py $out/boot.img
	# header v0 + appended DTB for an lk2nd built without OSVERSION_IN_BOOTIMAGE=1
	PATH=$PWD/out/host/linux-x86/bin:$PATH device/samsung/gtowifi_mainline/tools/make-fastboot-boot-img.sh $out
}

case "${1:-}" in
sync) step_sync ;;
sources) step_sources ;;
patches) step_patches ;;
build) step_build ;;
all) step_sync; step_sources; step_patches; step_build ;;
*) sed -n '2,12p' "$0"; exit 1 ;;
esac
