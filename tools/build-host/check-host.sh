#!/bin/bash
# Read-only check: can this machine build LineageOS 23.2 (Android 16)?
# Changes nothing. Usage: ./check-host.sh [directory that will hold the source, default $HOME]
DIR=${1:-$HOME}
verdict=0
say() { printf '%-5s %s\n' "$1" "$2"; }
fail() { say FAIL "$1"; verdict=2; }
warn() { say WARN "$1"; [ "$verdict" -lt 1 ] && verdict=1; }

arch=$(uname -m)
cores=$(nproc)
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
swap_gb=$(awk '/SwapTotal/ {printf "%d", $2/1048576}' /proc/meminfo)
free_gb=$(df -BG --output=avail "$DIR" 2>/dev/null | tail -1 | tr -dc 0-9)
fs=$(df --output=fstype "$DIR" 2>/dev/null | tail -1)
. /etc/os-release 2>/dev/null

echo "host: $(hostname)  os: ${PRETTY_NAME:-unknown}  kernel: $(uname -r)"
echo "cpu:  $arch, $cores threads, $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
echo "ram:  ${mem_gb} GiB + ${swap_gb} GiB swap    disk: ${free_gb} GiB free on $DIR ($fs)"
echo

# AOSP's prebuilt clang, make, ninja, ... exist for linux-x86 only
[ "$arch" = x86_64 ] && say OK "x86-64 host" || fail "architecture is $arch: AOSP builds need an x86-64 Linux host (OCI Ampere/arm64 cannot do it)"

if   [ "$mem_gb" -ge 60 ]; then say OK "RAM ${mem_gb} GiB (LineageOS asks for 64 GB from lineage-21 on)"
elif [ "$mem_gb" -ge 14 ]; then warn "RAM ${mem_gb} GiB: builds with 32 GiB of zram + swap, MEM=none and BUILD_JOBS=8 (tested with 16 GiB: a first build compiles for about 13 hours, and soong's analysis alone peaks at ~9 GiB, so leave the machine alone meanwhile)"
else fail "RAM ${mem_gb} GiB: not enough for Android 16 (soong's analysis alone needs ~9 GiB)"; fi
if [ "$mem_gb" -lt 60 ] && [ "$swap_gb" -lt 30 ]; then warn "swap ${swap_gb} GiB: setup-arch-host.sh adds zram the size of the RAM; add disk swap for 30+ GiB in total"; fi

if   [ "${free_gb:-0}" -ge 400 ]; then say OK "disk ${free_gb} GiB free (LineageOS asks for 400 GB)"
elif [ "${free_gb:-0}" -ge 300 ]; then warn "disk ${free_gb} GiB free: enough only with a shallow sync (--depth=1), a small ccache and one target"
else fail "disk ${free_gb:-?} GiB free on $DIR: need about 300 GiB at the very least"; fi

[ "$cores" -ge 16 ] && say OK "$cores threads" || warn "$cores threads: first build will take many hours"
case "$fs" in ext4|xfs|btrfs|zfs) say OK "file system $fs (case sensitive)";; *) warn "file system $fs: must be case sensitive and support symlinks";; esac
if command -v apt-get >/dev/null; then say OK "apt-based distribution: provision.sh installs the packages natively"
elif command -v docker >/dev/null || command -v podman >/dev/null; then say OK "no apt, but a container runtime: build inside the Ubuntu container (Dockerfile)"
else warn "no apt and no docker/podman: install one of the container runtimes, then use the Dockerfile"; fi
for t in git git-lfs python3 curl; do command -v $t >/dev/null && say OK "$t present" || say INFO "$t missing (provision.sh installs it)"; done
[ "$(ulimit -n)" -ge 4096 ] || say INFO "open files limit $(ulimit -n): the build raises it itself where allowed"

echo
case $verdict in 0) echo "VERDICT: suitable";; 1) echo "VERDICT: usable with the limits above";; 2) echo "VERDICT: not suitable";; esac
exit $verdict
