#!/bin/bash
# Tune Yaron's laptop (ThinkPad L14 Gen 4, i5-1335U, 16 GB RAM) as the LineageOS build host, after
# setup-arch-host.sh. Run as root, on the laptop:   sudo bash ~/lineage-host-tune.sh
# Assumes what that laptop has: Manjaro, GRUB, a btrfs root, Intel Wi-Fi under NetworkManager.
# Every change is applied now and persisted; re-runnable; no reboot needed. Sleep behaviour is untouched.
# Not here because it is user config: the AC power profile, ~/.config/powerdevilrc [AC][Performance]
# PowerProfile=performance ([Battery] balanced): 88 instead of 78 gcc -O2 compiles in 120 s on 12 threads.
# Undo that one: rm ~/.config/powerdevilrc (it did not exist before).
# Undo: cp /etc/default/grub.pre-tune /etc/default/grub; update-grub; swapoff /swap/swapfile;
#   cp /etc/fstab.pre-tune /etc/fstab; btrfs subvolume delete /swap; rm /etc/sysctl.d/98-build-host.conf
#   /etc/NetworkManager/conf.d/90-wifi-powersave-off.conf /etc/makepkg.conf.d/jobs.conf; reboot
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root: sudo bash $0" >&2; exit 1; }
cp -n /etc/fstab /etc/fstab.pre-tune
cp -n /etc/default/grub /etc/default/grub.pre-tune

echo "== 1. zswap off: it sat in front of zram and took every swapped page (Zswapped 300 MB, zram 4 KB);"
echo "      its write-back into zram failed 22 times for lack of memory during builds (page allocation failures)"
echo 0 > /sys/module/zswap/parameters/enabled

echo "== 2. 32 GiB more swap on the SSD: build 31d was OOM-killed with all 33.6 GB of swap in use"
btrfs subvolume show /swap >/dev/null 2>&1 || btrfs subvolume create /swap
[ -f /swap/swapfile ] || btrfs filesystem mkswapfile --size 32g /swap/swapfile
grep -q '^/swap/swapfile ' /etc/fstab || echo '/swap/swapfile none swap defaults,pri=10 0 0' >> /etc/fstab
swapon --show=NAME --noheadings | grep -qx /swap/swapfile || swapon -p 10 /swap/swapfile
# The partition stays ahead of the file (zram 100 > partition 20 > file 10): systemd hibernates to the
# highest-priority disk swap, and resume= on the kernel command line names the partition
part=$(awk '$3 == "swap" && $1 ~ /^UUID=/ {print $1}' /etc/fstab)
sed -i -E "s|^(${part}[[:space:]]+swap[[:space:]]+swap[[:space:]]+)defaults([[:space:]])|\1defaults,pri=20\2|" /etc/fstab
dev=$(findfs "$part")
if [ "$(swapon --show=NAME,PRIO --noheadings | awk -v d="$dev" '$1 == d {print $2}')" != 20 ]; then
	if [ "$(swapon --show=NAME,USED --bytes --noheadings | awk -v d="$dev" '$1 == d {print $2}')" = 0 ]; then
		swapoff "$dev" && swapon -p 20 "$dev"
	else
		echo "partition swap is in use: its priority 20 applies at the next boot"
	fi
fi

echo "== 3. kswapd reclaims earlier (1.25 % instead of 0.1 % between watermarks): fewer direct-reclaim stalls"
cat > /etc/sysctl.d/98-build-host.conf <<'EOF'
# LineageOS build host: background reclaim starts earlier, no watermark boost (the Arch wiki's zram
# settings, from Pop!_OS); 99-lineage-zram.conf keeps swappiness and page-cluster
vm.watermark_scale_factor = 125
vm.watermark_boost_factor = 0
EOF
sysctl -q -p /etc/sysctl.d/98-build-host.conf

echo "== 4. Transparent huge pages only where a program asks for them (madvise): less memory held when it is short"
echo madvise > /sys/kernel/mm/transparent_hugepage/enabled

echo "== 5. Lazy preemption: full preemption's latency for the desktop, fewer preemptions in compile jobs"
add="zswap.enabled=0 transparent_hugepage=madvise"
if [ -w /sys/kernel/debug/sched/preempt ] && echo lazy > /sys/kernel/debug/sched/preempt 2>/dev/null &&
	grep -q '(lazy)' /sys/kernel/debug/sched/preempt; then
	add="$add preempt=lazy"
else
	echo "this kernel cannot switch to lazy preemption: left as it is"
fi

echo "== 6. Kernel command line for the next boots: $add"
set -f
cur=$(. /etc/default/grub; echo "$GRUB_CMDLINE_LINUX_DEFAULT")
new=
for w in $cur; do
	case "$w" in zswap.enabled=*|transparent_hugepage=*|preempt=*) ;; *) new="$new${new:+ }$w" ;; esac
done
new="${new:+$new }$add"
set +f
case "$new" in *"'"*|*"|"*) echo "unexpected quote or | in the command line: not editing /etc/default/grub" >&2; exit 1 ;; esac
if [ "$new" != "$cur" ]; then
	sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT='$new'|" /etc/default/grub
	update-grub
fi

echo "== 7. noatime on btrfs: reading the source tree no longer rewrites its metadata once a day"
sed -i -E '/[[:space:]]btrfs[[:space:]]/{/noatime/!s/(subvol=[^,[:space:]]+,defaults)/\1,noatime/}' /etc/fstab
findmnt --verify --tab-file /etc/fstab
systemctl daemon-reload
for m in $(findmnt -rno TARGET -t btrfs); do mount -o remount,noatime "$m"; done

echo "== 8. Wi-Fi power save off: the build host is reached over Wi-Fi only"
cat > /etc/NetworkManager/conf.d/90-wifi-powersave-off.conf <<'EOF'
[connection]
# 2 = disable
wifi.powersave = 2
EOF
for i in $(iw dev | awk '/Interface/ {print $2}'); do iw dev "$i" set power_save off; done

echo "== 9. makepkg (AUR builds) on all 12 threads instead of 2"
install -d /etc/makepkg.conf.d
echo 'MAKEFLAGS="-j$(nproc)"' > /etc/makepkg.conf.d/jobs.conf

echo "== result"
grep '^GRUB_CMDLINE_LINUX_DEFAULT=' /etc/default/grub
swapon --show
echo "zswap enabled: $(cat /sys/module/zswap/parameters/enabled)"
echo "THP: $(cat /sys/kernel/mm/transparent_hugepage/enabled)"
echo "preempt: $(cat /sys/kernel/debug/sched/preempt)"
sysctl vm.watermark_scale_factor vm.watermark_boost_factor vm.swappiness
findmnt -rno TARGET,OPTIONS -t btrfs | cut -d, -f1-3
for i in $(iw dev | awk '/Interface/ {print $2}'); do echo "$i: $(iw dev "$i" get power_save)"; done
echo "TUNE_RC=0"
