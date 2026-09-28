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
BUNDLE=${KERNEL_BUNDLE:-kernel/export-r5/gtowifi-android-7.1.3-r5.bundle}
[ -f "$TOP/$BUNDLE" ] || { echo "no kernel bundle $TOP/$BUNDLE" >&2; exit 1; }

# The scripts go into the payload as build-host/, wherever this copy of them lives
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/build-host"
cp "$HERE"/check-host.sh "$HERE"/provision.sh "$HERE"/Dockerfile "$HERE"/sync-and-build.sh \
	"$HERE"/run-container.sh "$stage/build-host/"
if [ -n "${KERNEL_BASE:-}" ]; then
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
ls -l "$OUT"; echo "kernel: ${KERNEL_BASE:-default} / $BUNDLE"; echo "device tree at $(git -C "$DT" log --oneline -1)"
