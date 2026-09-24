#!/bin/bash
# Kernel-only test set: build a kernel branch on its own and put it into the images of an installed
# release, so that it can be tried by RAM boot without an Android build. See README.md.
#
#   make-test-set.sh --kernel DIR --release DIR --out DIR [options]
#
#   --kernel DIR          kernel git tree (msm89x7-mainline with the gtowifi board)
#   --ref REF             build REF from that tree (exported with git archive, the tree is left alone);
#                         without it the working tree is built as it is
#   --release DIR         the installed release: boot-fastboot-v0.img and vendor_dlkm.img
#   --base-boot FILE      boot image whose ramdisk and command line to keep
#                         (default: RELEASE/boot-fastboot-v0.img)
#   --fixups FILE         last configuration fragment (default: kconfigs/fixups.config of this tree)
#   --stack-configs DIR   checkout of LineageOS/android_kernel_mainline_configs (default: cloned)
#   --android-base FILE   AOSP kernel/configs b/android-6.12/android-base.config (default: fetched)
#   --test-min-uv UV      also make a boot image whose battery declares UV as its minimum voltage
#                         (e.g. 3900000: the empty-battery rule then fires a minute after unplugging)
#   --work DIR            scratch directory (default: a new one under /tmp); about 3 GB
#
# Needs: bash, git, make, gcc for arm64 (aarch64-linux-gnu-gcc on other hosts), bc, bison, flex,
# libelf and libssl headers, python3, kmod (depmod), e2fsprogs (mke2fs, debugfs, e2fsck),
# simg2img/img2simg (android-sdk-libsparse-utils), dtc tools (fdtget, fdtput), curl.
set -euo pipefail

TOOLS=$(cd "$(dirname "$0")/.." && pwd)
DT=$(cd "$TOOLS/.." && pwd)

kernel= ref= release= base_boot= out= test_min_uv= work=
fixups=$DT/kconfigs/fixups.config
stack_configs= android_base=
while [ $# -gt 0 ]; do
	case "$1" in
	--kernel) kernel=$2 ;;
	--ref) ref=$2 ;;
	--release) release=$2 ;;
	--base-boot) base_boot=$2 ;;
	--out) out=$2 ;;
	--fixups) fixups=$2 ;;
	--stack-configs) stack_configs=$2 ;;
	--android-base) android_base=$2 ;;
	--test-min-uv) test_min_uv=$2 ;;
	--work) work=$2 ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift 2
done
[ -n "$kernel" ] && [ -n "$release" ] && [ -n "$out" ] || { sed -n '5,20p' "$0"; exit 2; }
base_boot=${base_boot:-$release/boot-fastboot-v0.img}
work=${work:-$(mktemp -d /tmp/kernel-test-set.XXXXXX)}
mkdir -p "$out" "$work"
out=$(cd "$out" && pwd)
work=$(cd "$work" && pwd)

cross=
[ "$(uname -m)" = aarch64 ] || cross=aarch64-linux-gnu-
kmake() { make -s ARCH=arm64 CROSS_COMPILE="$cross" "$@"; }

echo "== configuration fragments"
if [ -z "$stack_configs" ]; then
	stack_configs=$work/stack-configs
	[ -d "$stack_configs" ] || git clone -q --depth 1 --branch lineage-23.2 \
		https://github.com/LineageOS/android_kernel_mainline_configs "$stack_configs"
fi
if [ -z "$android_base" ]; then
	android_base=$work/android-base.config
	curl -fsSL 'https://android.googlesource.com/kernel/configs/+/refs/heads/main/b/android-6.12/android-base.config?format=TEXT' \
		| base64 -d > "$android_base"
fi
grep -q CONFIG_ "$android_base"
frag=$stack_configs/fragments

echo "== kernel source"
src=$kernel
if [ -n "$ref" ]; then
	src=$work/linux
	rm -rf "$src" && mkdir -p "$src"
	git -C "$kernel" archive "$ref" | tar -x -C "$src"
	git -C "$kernel" log -1 --format='%h %s' "$ref"
fi

echo "== build (the configuration list of BoardConfig.mk, in its order)"
o=$work/out
rm -rf "$o" "$work/staging" && mkdir -p "$o"
kmake -C "$src" O="$o" msm8916_defconfig >/dev/null
cp "$DT/kconfigs/config-postmarketos-qcom-msm89x7.aarch64" "$o/.config"
(cd "$o" && ARCH=arm64 CROSS_COMPILE="$cross" "$src/scripts/kconfig/merge_config.sh" -O "$o" "$o/.config" \
	"$frag/android-base-pre/common.config" \
	"$frag/android-base-pre/arm64.config" \
	"$android_base" \
	"$frag/android-base-conditional/CONFIG_ARM64-y.config" \
	"$frag/common.config" \
	"$frag/y/fbcon.config" \
	"$frag/n/disable-clang-hardening-features.config" \
	"$frag/n/faster-build-time.config" \
	"$fixups") > "$work/merge.log" 2>&1 || { tail -20 "$work/merge.log"; exit 1; }
kmake -C "$src" O="$o" -j"$(nproc)" Image.gz qcom/sdm429-samsung-gtowifi.dtb modules
kmake -C "$src" O="$o" INSTALL_MOD_PATH="$work/staging" INSTALL_MOD_STRIP=1 modules_install
rel=$(cat "$o/include/config/kernel.release")
cp "$o/.config" "$out/config"

echo "== vendor_dlkm: the release's, with these modules"
# Laid out the way the Android build does it: every module flat in /lib/modules, index files with
# /vendor_dlkm/lib/modules/ paths, the release's modules.load and etc/, root-owned, and the SELinux
# labels of the release (vendor_file; etc/ is vendor_configs_file)
old=$work/vendor_dlkm-release.raw
new=$work/vendor_dlkm.raw
tree=$work/dlkm-tree
simg2img "$release/vendor_dlkm.img" "$old"
rm -rf "$tree" && mkdir -p "$tree/lib/modules" "$tree/etc"
for f in $(debugfs -R 'ls -p /etc' "$old" 2>/dev/null | awk -F/ '$6 != "" && $6 != "." && $6 != ".." {print $6}'); do
	debugfs -R "dump /etc/$f $tree/etc/$f" "$old" 2>/dev/null
done
debugfs -R "dump /lib/modules/modules.load $tree/lib/modules/modules.load" "$old" 2>/dev/null
mods=$work/staging/lib/modules/$rel
find "$mods" -name '*.ko' -exec cp {} "$tree/lib/modules/" \;
n_built=$(find "$mods" -name '*.ko' | wc -l)
n_flat=$(find "$tree/lib/modules" -name '*.ko' | wc -l)
[ "$n_built" = "$n_flat" ] || { echo "two modules share a name: $n_built built, $n_flat flat"; exit 1; }
depmod -b "$work/staging" "$rel"
sed -E 's#[^ :]*/([^/ :]+\.ko)#/vendor_dlkm/lib/modules/\1#g' "$mods/modules.dep" > "$tree/lib/modules/modules.dep"
cp "$mods/modules.alias" "$mods/modules.softdep" "$tree/lib/modules/"
find "$tree" -type d -exec chmod 0755 {} +
find "$tree" -type f -exec chmod 0644 {} +
blocks=$(( $(stat -c %s "$old") / 4096 ))
rm -f "$new"
mke2fs -q -t ext4 -O ^has_journal,^metadata_csum,^64bit,^flex_bg,^resize_inode,uninit_bg \
	-I 256 -N "$blocks" -m 0 -L vendor_dlkm -b 4096 -E root_owner=0:0 -d "$tree" "$new" "$blocks"
printf 'u:object_r:vendor_file:s0\0' > "$work/label-vendor_file"
printf 'u:object_r:vendor_configs_file:s0\0' > "$work/label-vendor_configs_file"
(cd "$tree" && find . -mindepth 1 | sed 's#^\.##') | while read -r p; do
	case "$p" in
	/etc|/etc/*) label=$work/label-vendor_configs_file ;;
	*) label=$work/label-vendor_file ;;
	esac
	echo "sif $p uid 0"
	echo "sif $p gid 0"
	echo "ea_set -f $label $p security.selinux"
done > "$work/dlkm.cmd"
echo "ea_set -f $work/label-vendor_file / security.selinux" >> "$work/dlkm.cmd"
echo "ea_set -f $work/label-vendor_file /lost+found security.selinux" >> "$work/dlkm.cmd"
debugfs -w -f "$work/dlkm.cmd" "$new" >/dev/null 2>"$work/dlkm.err" || true
if grep -v '^debugfs' "$work/dlkm.err" | grep -q .; then
	head -5 "$work/dlkm.err"
	exit 1
fi
e2fsck -fn "$new" >/dev/null
img2simg "$new" "$out/vendor_dlkm.img"
echo "$n_flat modules"

echo "== boot images"
cp "$o/arch/arm64/boot/dts/qcom/sdm429-samsung-gtowifi.dtb" "$work/board.dtb"
python3 "$TOOLS/repack-boot-v0.py" "$base_boot" "$o/arch/arm64/boot/Image.gz" "$work/board.dtb" \
	"$out/boot-test.img"
if [ -n "$test_min_uv" ]; then
	cp "$work/board.dtb" "$work/board-min.dtb"
	fdtput -t i "$work/board-min.dtb" /battery voltage-min-design-microvolt "$test_min_uv"
	python3 "$TOOLS/repack-boot-v0.py" "$base_boot" "$o/arch/arm64/boot/Image.gz" "$work/board-min.dtb" \
		"$out/boot-test-min$test_min_uv.img"
fi

(cd "$out" && sha256sum -- *.img config > SHA256SUMS)
echo "== done: $out ($rel)"
ls -la "$out"
