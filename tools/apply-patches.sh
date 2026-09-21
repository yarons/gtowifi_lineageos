#!/bin/bash
#
# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: Apache-2.0
#
# Apply the platform patches this device tree carries: patches/<project path>/*.patch, each to the
# project named by its directory. Run from the top of the LineageOS tree after `repo sync`:
#
#     device/samsung/gtowifi_mainline/tools/apply-patches.sh
#
# Safe to run again: a patch that is already in the tree is skipped. `repo status` shows the
# patched projects as modified.
set -euo pipefail

top=$(cd "$(dirname "$0")/../../../.." && pwd)
root=device/samsung/gtowifi_mainline/patches
cd "$top"
[ -d "$root" ] || { echo "no patches directory: $top/$root" >&2; exit 1; }

while IFS= read -r patch; do
	project=$(dirname "${patch#"$root"/}")
	if git -C "$project" apply --reverse --check "$top/$patch" 2>/dev/null; then
		echo "already applied: $patch"
	elif git -C "$project" apply --check "$top/$patch"; then
		git -C "$project" apply "$top/$patch"
		echo "applied: $patch"
	else
		echo "DOES NOT APPLY: $patch" >&2
		exit 1
	fi
done < <(find "$root" -name '*.patch' | sort)
