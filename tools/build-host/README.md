# Build host scripts

How the author builds this tree: on a laptop (x86-64, 12 threads, 16 GB RAM, Manjaro), inside an Ubuntu
22.04 container, with the tree, ccache and output in `~/lineage` on the laptop's disk, started and
followed from a workstation over ssh. The scripts' defaults are that setup; a bigger machine only
changes a few settings (`host.env.example`). Nothing
here is needed for a plain LineageOS build machine (the README's build steps are enough); these scripts
are what makes a borrowed or small machine usable.

| Script | Where it runs | What it does |
|---|---|---|
| `check-host.sh` | build host | read-only check: x86-64, RAM, disk, file system, container runtime |
| `provision.sh` | build host (apt) | installs the build packages natively (Ubuntu/Debian) |
| `setup-arch-host.sh` | build host (Arch/Manjaro), as root | Docker, passwordless `sudo docker` for the user, zram swap the size of the RAM, a polkit rule so that a running build can keep the machine awake |
| `laptop-tune.sh` | the author's laptop (Manjaro, GRUB, btrfs root), as root | after `setup-arch-host.sh`: zswap off, a 32 GB swap file, earlier background reclaim, transparent huge pages on request only, lazy preemption, `noatime`, Wi-Fi power save off |
| `Dockerfile` | build host | the build container (LineageOS build packages, `repo`, a recent meson for Mesa) |
| `run-container.sh` | build host | starts that container with the tree, ccache and payload mounted; `DETACH=1` for long jobs |
| `sync-and-build.sh` | in the container | `sync` (repo init + sync), `sources` (device tree + kernel), `patches`, `build` |
| `make-payload.sh` | workstation | packs the checked-out device tree, the kernel (a bundle on a public base branch, or a patch series for a kernel.org stable tag) and these scripts |
| `start-build.sh` | workstation | ships the payload, builds the container image if needed, starts the steps, keeps the host awake |

## A new host

    ./check-host.sh                        # on the host
    sudo bash setup-arch-host.sh           # Arch/Manjaro; on Ubuntu/Debian install Docker instead
    cp host.env.example my-host.env        # on the workstation: HOST (the rest has laptop defaults)
    ./make-payload.sh
    . my-host.env; NAME=lineage-build1 STEPS="sync sources patches build" ./start-build.sh
    ssh $HOST tail -f $BASE/logs/lineage-build1.log

The first sync downloads well over 100 GB. Later builds leave out `sync` (the default steps are
`sources patches build`).

## Kernel

    # a public base branch plus a bundle of the Android commits (kernel r15 and earlier)
    KERNEL_BASE=gtowifi/display-v2 KERNEL_BUNDLE=kernel/export-r15/gtowifi-android-7.1.3-r15.bundle \
        KERNEL_BRANCH=gtowifi/android-7.1.3-r15 ./make-payload.sh
    # a kernel.org stable tag plus a patch series (a base that is not on GitHub, e.g. r16 on 7.2.8)
    KERNEL_STABLE_TAG=v7.2.8 KERNEL_PATCHES=kernel/export-72-r16/patches \
        KERNEL_BRANCH=gtowifi/android-7.2.8-r16 ./make-payload.sh

## 16 GB of RAM

LineageOS asks for 64 GB of RAM. The tested laptop has 16 GB with 15 GB of zram, 17 GB of disk swap and a
32 GB swap file behind it (`setup-arch-host.sh`, `laptop-tune.sh`), no memory cap on the container
(`MEM=none`) and 8 parallel jobs (`BUILD_JOBS=8`). What that took:

- A first build took about 13 hours of compiling (after a 30-minute sync of ~100 GB); later ones, from
  ccache and `out/`, 15 minutes to a few hours.
- soong's analysis of the tree alone peaks at about 9 GB. It runs whenever a makefile or a globbed
  directory changes (the `sources` step re-clones the device tree, so it always runs then) and takes up
  to two hours. Leave the machine alone meanwhile: a browser and a desktop file indexer (KDE's baloo,
  which also indexes the 100+ GB tree) were enough to get soong_build killed. Turn the indexer off.
- The one killed build (a browser open) had used all 33.6 GB of swap. Other builds logged page allocation
  failures with 9-27 GB of swap still free: Manjaro's kernel turns zswap on, and zswap sat in front of
  zram, writing its pages back into zram when memory was already short. `laptop-tune.sh` turns zswap off
  and adds the swap file; `run-container.sh` makes the out-of-memory killer take other programs before
  the build. If a build is killed, run `STEPS=build` again (fewer jobs if needed): ccache and `out/` are
  kept.
- 8 jobs compile about 16 % faster than 4 (libhwui's 385 steps, ccache off: 172 s against 206 s) and
  still left 4 GB of RAM free. soong's analysis runs alone either way.
- Enable sshd at boot (`systemctl enable sshd`), or the host is unreachable after a restart.
- A change that only touches the device tree's files (not its makefiles) can skip the re-clone: update
  the tree in place (`git -C device/samsung/gtowifi_mainline fetch <payload checkout> HEAD` + checkout)
  and run only the `build` step, which avoids the long analysis.
