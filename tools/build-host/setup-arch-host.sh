#!/bin/bash
# One-time setup of an Arch/Manjaro machine with little RAM (tried with 16 GB) as the build host, for
# the user who will run the builds. Run as root, on that machine:
#   sudo bash setup-arch-host.sh
# The build itself runs in the Ubuntu container of the Dockerfile; this only prepares the host.
# Undo: pacman -Rns docker zram-generator; rm /etc/sudoers.d/90-lineage-docker
#   /etc/systemd/zram-generator.conf /etc/sysctl.d/99-lineage-zram.conf
#   /etc/polkit-1/rules.d/49-lineage-build-inhibit.rules; reboot
set -euo pipefail
U=${SUDO_USER:?run it with sudo, as the user who will build}

echo "== 1. Docker (the build runs in an Ubuntu 22.04 container) and zram-generator"
if ! pacman -S --needed --noconfirm docker zram-generator; then
	echo "pacman could not install them; bring the system up to date first (pacman -Syu), then run this again"
	exit 1
fi
systemctl enable --now docker.service
# The build scripts run "sudo -n docker": allow exactly that without a password. Note: whoever can run
# docker can do anything as root on this machine; this is the same power as the docker group.
echo "$U ALL=(root) NOPASSWD: /usr/bin/docker" > /etc/sudoers.d/90-lineage-docker
chmod 0440 /etc/sudoers.d/90-lineage-docker
visudo -cf /etc/sudoers.d/90-lineage-docker

echo "== 2. Compressed swap in RAM: 16 GB is below what an Android 16 build wants"
cat > /etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = ram
compression-algorithm = zstd
swap-priority = 100
EOF
cat > /etc/sysctl.d/99-lineage-zram.conf <<'EOF'
vm.swappiness = 180
vm.page-cluster = 0
EOF
systemctl daemon-reload
systemctl start systemd-zram-setup@zram0.service
sysctl --system >/dev/null

echo "== 3. No sleep while a build runs: $U may hold sleep/idle/lid inhibitors from SSH"
# The build takes an inhibitor for as long as its container runs; the rest of the time the laptop
# sleeps as it did before.
cat > /etc/polkit-1/rules.d/49-lineage-build-inhibit.rules <<EOF
polkit.addRule(function(action, subject) {
    if (subject.user == "$U" &&
        (action.id == "org.freedesktop.login1.inhibit-block-sleep" ||
         action.id == "org.freedesktop.login1.inhibit-block-idle" ||
         action.id == "org.freedesktop.login1.inhibit-handle-lid-switch")) {
        return polkit.Result.YES;
    }
});
EOF

echo "== 4. The build tree: /home/$U/lineage"
install -d -o "$U" -g "$U" "/home/$U/lineage"

echo "== result"
swapon --show
docker --version
echo "SETUP_RC=0"
