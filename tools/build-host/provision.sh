#!/bin/bash
# Prepare an apt-based x86-64 Linux host (Ubuntu 22.04/24.04, Debian 12+) for building LineageOS 23.2.
# Package list = LineageOS wiki (build instructions, "Install the build packages") plus what Mesa's
# build wants. Idempotent. Needs sudo for apt only; everything else is per-user.
#   ./provision.sh
set -euo pipefail
[ "$(uname -m)" = x86_64 ] || { echo "x86-64 host required" >&2; exit 1; }
command -v apt-get >/dev/null || { echo "not an apt system: use the Dockerfile instead" >&2; exit 1; }

sudo apt-get update
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
	bc bison build-essential ccache curl erofs-utils flex g++-multilib gcc-multilib git git-lfs gnupg \
	gperf imagemagick protobuf-compiler python3-protobuf lib32readline-dev lib32z1-dev libdw-dev \
	libelf-dev libgnutls28-dev lz4 libsdl1.2-dev libssl-dev libxml2 libxml2-utils lzop pngcrush rsync \
	schedtool squashfs-tools xsltproc xxd zip zlib1g-dev \
	meson glslang-tools python3-mako python3-yaml python3-pycparser python3-jinja2 python3-ply \
	python3 python-is-python3 openssh-client tmux android-sdk-libsparse-utils gdisk \
	unzip cpio kmod file

mkdir -p "$HOME/bin" "$HOME/android/lineage"
if [ ! -x "$HOME/bin/repo" ]; then
	curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo -o "$HOME/bin/repo"
	chmod a+x "$HOME/bin/repo"
fi
git lfs install --skip-repo
# repo and repopick make local commits; any identity does, nothing is pushed from here
git config --global user.name  >/dev/null || git config --global user.name  "Yaron Shahrabani"
git config --global user.email >/dev/null || git config --global user.email "yarons@users.noreply.github.com"
git config --global color.ui false

grep -q 'lineage build env' "$HOME/.profile" 2>/dev/null || cat >> "$HOME/.profile" <<'PROFILE'
# lineage build env
export PATH="$HOME/bin:$PATH"
export USE_CCACHE=1
export CCACHE_EXEC=/usr/bin/ccache
PROFILE
ccache -M 30G >/dev/null
ccache -o compression=true >/dev/null
echo "done. Log out and in again (PATH), then run sync-and-build.sh inside tmux."
