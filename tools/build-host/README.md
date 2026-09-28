# Build host scripts

How the author builds this tree: on an x86-64 Linux machine, inside an Ubuntu 22.04 container, with the
tree, ccache and output on the host's disk, started and followed from a workstation over ssh. Nothing
here is needed for a plain LineageOS build machine (the README's build steps are enough); these scripts
are what makes a borrowed or small machine usable.

| Script | Where it runs | What it does |
|---|---|---|
| `check-host.sh` | build host | read-only check: x86-64, RAM, disk, file system, container runtime |
| `provision.sh` | build host (apt) | installs the build packages natively (Ubuntu/Debian) |
| `setup-arch-host.sh` | build host (Arch/Manjaro), as root | Docker, passwordless `sudo docker` for the user, zram swap the size of the RAM, a polkit rule so that a running build can keep the machine awake |
| `Dockerfile` | build host | the build container (LineageOS build packages, `repo`, a recent meson for Mesa) |
| `run-container.sh` | build host | starts that container with the tree, ccache and payload mounted; `DETACH=1` for long jobs |
| `sync-and-build.sh` | in the container | `sync` (repo init + sync), `sources` (device tree + kernel), `patches`, `build` |
| `make-payload.sh` | workstation | packs the checked-out device tree, a kernel bundle and these scripts |
| `start-build.sh` | workstation | ships the payload, builds the container image if needed, starts the steps, keeps the host awake |

## A new host

    ./check-host.sh                        # on the host
    sudo bash setup-arch-host.sh           # Arch/Manjaro; on Ubuntu/Debian install Docker instead
    cp host.env.example my-host.env        # on the workstation: HOST, BASE, MEM, BUILD_JOBS, ...
    ./make-payload.sh
    . my-host.env; NAME=lineage-build1 STEPS="sync sources patches build" ./start-build.sh
    ssh $HOST tail -f $BASE/logs/lineage-build1.log

The first sync downloads well over 100 GB. Later builds leave out `sync` (the default steps are
`sources patches build`).

## Little RAM

LineageOS asks for 64 GB of RAM. With 16 GB the build is attempted with zram and the disk swap behind it
(`setup-arch-host.sh`), no memory cap on the container (`MEM=none`) and few parallel jobs
(`BUILD_JOBS=4`). It is slow; if it is killed for lack of memory, run `STEPS=build` again with fewer jobs:
ccache and `out/` are kept.
