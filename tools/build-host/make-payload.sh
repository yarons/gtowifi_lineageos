#!/bin/bash
# On the workstation: pack what the build host needs and GitHub may not have yet (the checked-out device
# tree, a kernel bundle, these scripts) into one file. Nothing is uploaded by this script.
#   ./make-payload.sh            -> gtowifi-mainline-payload.tar.gz next to this script
# Expects the author's layout: the device tree checked out as android_device_samsung_gtowifi_mainline,
# next to kernel/export-*/ with the kernel bundles (TOP, default: found from where this script is).
# start-build.sh ships the file and starts the build.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
if [ -z "${TOP:-}" ]; then
	TOP=$(cd "$HERE/.." && pwd)                                    # a copy in <workspace>/build-host
	[ -d "$TOP/android_device_samsung_gtowifi_mainline" ] || TOP=$(cd "$HERE/../../.." && pwd)   # the repo's tools/build-host
fi
OUT=${OUT:-$HERE/gtowifi-mainline-payload.tar.gz}
DT=$TOP/android_device_samsung_gtowifi_mainline
[ -d "$DT" ] || { echo "no device tree at $DT (set TOP)" >&2; exit 1; }
[ -z "$(git -C "$DT" status --porcelain)" ] || { echo "device tree has uncommitted changes" >&2; exit 1; }
# Kernel line of this payload. Default: the stable one in sync-and-build.sh. Example:
#   KERNEL_BASE=gtowifi/display-v2 KERNEL_BUNDLE=kernel/export-r15/gtowifi-android-7.1.3-r15.bundle \
#   KERNEL_BRANCH=gtowifi/android-7.1.3-r15 ./make-payload.sh
# Or a kernel.org stable tag plus a patch series for `git am` (a kernel line on a base that is not on
# GitHub, e.g. the 7.2.8 rebase):
#   KERNEL_STABLE_TAG=v7.2.8 KERNEL_PATCHES=kernel/export-72-r16/patches KERNEL_BRANCH=gtowifi/android-7.2.8-r16 \
#   ./make-payload.sh
if [ -n "${KERNEL_PATCHES:-}" ]; then
	[ -n "${KERNEL_STABLE_TAG:-}" ] || { echo "KERNEL_PATCHES needs KERNEL_STABLE_TAG" >&2; exit 1; }
	ls "$TOP/$KERNEL_PATCHES"/*.patch >/dev/null 2>&1 || { echo "no patches in $TOP/$KERNEL_PATCHES" >&2; exit 1; }
	BUNDLE=$KERNEL_PATCHES
else
	BUNDLE=${KERNEL_BUNDLE:-kernel/export-r5/gtowifi-android-7.1.3-r5.bundle}
	[ -f "$TOP/$BUNDLE" ] || { echo "no kernel bundle $TOP/$BUNDLE" >&2; exit 1; }
fi

# The scripts go into the payload as build-host/, wherever this copy of them lives
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/build-host"
cp "$HERE"/check-host.sh "$HERE"/provision.sh "$HERE"/Dockerfile "$HERE"/sync-and-build.sh \
	"$HERE"/run-container.sh "$stage/build-host/"
if [ -n "${KERNEL_PATCHES:-}" ]; then
	printf 'KERNEL_STABLE_TAG=%s\nKERNEL_PATCHES=%s\nKERNEL_BRANCH=%s\n' "$KERNEL_STABLE_TAG" "$KERNEL_PATCHES" \
		"${KERNEL_BRANCH:-gtowifi/android-${KERNEL_STABLE_TAG#v}}" > "$stage/build-host/kernel.env"
elif [ -n "${KERNEL_BASE:-}" ]; then
	printf 'KERNEL_BASE=%s\nKERNEL_BUNDLE=%s\n' "$KERNEL_BASE" "$BUNDLE" > "$stage/build-host/kernel.env"
	# the branch name inside the bundle, when it is not gtowifi/android-7.1.3
	[ -z "${KERNEL_BRANCH:-}" ] || printf 'KERNEL_BRANCH=%s\n' "$KERNEL_BRANCH" >> "$stage/build-host/kernel.env"
else
	: > "$stage/build-host/kernel.env"   # empty file: overwrite a kernel.env left on the host by an earlier payload
fi
# no macOS extended attributes: GNU tar on the host warns about every one of them
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata -czf "$OUT" \
	-C "$TOP" --exclude='.DS_Store' --exclude='gtowifi-mainline-payload.tar.gz' --exclude='android_device_samsung_gtowifi_mainline/tools/build-host/*.env' \
	android_device_samsung_gtowifi_mainline "$BUNDLE" \
	-C "$stage" build-host
ls -l "$OUT"; echo "kernel: ${KERNEL_STABLE_TAG:-${KERNEL_BASE:-default}} / $BUNDLE"; echo "device tree at $(git -C "$DT" log --oneline -1)"
