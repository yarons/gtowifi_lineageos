# Updating the kernel or LineageOS

What has to move when a newer kernel or a newer LineageOS branch comes along, and how a change is
tested before it goes on the tablet. Written 2026-09-22, after the first release (LineageOS 23.2,
kernel 7.1.3).

## Where things are

| | Where | Pinned by |
|---|---|---|
| Device tree | `yarons/gtowifi_lineageos`, branch `lineage-23.2` | `local_manifests/gtowifi_mainline.xml` |
| Kernel | `yarons/linux_msm89x7`, branch `gtowifi/android-7.1.3-r12` | same manifest |
| LineageOS mainline stack | `LineageOS/android_device_mainline_*`, `android_hardware_mainline_*`, `android_kernel_mainline_configs`, `android_external_lk2nd`, ... | `local_manifests/gtowifi_mainline_deps.xml`, branch `lineage-23.2` |
| Camera stack | `libcamera-org/libcamera` tag `v0.7.2`, `GloDroid/aospext` commit | `local_manifests/gtowifi_mainline.xml` |
| Platform patches | `patches/<project>/*.patch`, applied by `tools/apply-patches.sh` | |
| libcamera patches | `libcamera/patches/`, applied to a copy of libcamera during the build | `BoardConfig.mk`: `BOARD_LIBCAMERA_PATCHES_DIRS` |
| Kernel configuration | `kconfigs/config-postmarketos-qcom-msm89x7.aarch64` (postmarketOS's config for this kernel), the stack's fragments, `kconfigs/fixups.config` | `BoardConfig.mk`: `TARGET_KERNEL_CONFIG_EXT`, merged in that order |
| Kernel modules to load | `modprobe/modules.load.*` | |

## The kernel branch

`gtowifi/android-7.1.3-r12` is made of layers, from the bottom:

1. `msm89x7-mainline/linux` tag 7.1.3: mainline plus the msm89x7 family work.
2. The gtowifi board work (`gtowifi/display-v2` and the branches on top of it: cameras, Wi-Fi,
   backlight, the DRM fixes): `sdm429-samsung-gtowifi.dts`, the panel and PHY, the sensor drivers,
   CAMSS for SDM439, PMI632 charger, the AW87319 amplifier.
3. Three patches Android needs that are not in mainline: the `memfd-ashmem-shim` layer (two commits
   from the Android common kernel plus one to build it without the ashmem driver) and the USB configfs
   uevent. Everything else Android wants is configuration.
4. Fixes that were cherry-picked while they wait for their own branches (numbered `-rN`).

### Moving to a newer kernel

1. Rebase the board branches onto the new msm89x7 tag. Conflicts are almost always in
   `sdm429-samsung-gtowifi.dts` and in the SoC files it includes; compare against `sdm439.dtsi` /
   `msm8937.dtsi` of the new tag before resolving by hand.
2. Re-apply the Android patches. The shmem hunk is the one that moves (the `file_operations` of
   `mm/shmem.c` change between versions); the shim itself is self-contained.
3. Configuration: refresh `kconfigs/config-postmarketos-qcom-msm89x7.aarch64` from postmarketOS's
   `linux-postmarketos-qcom-msm89x7` package for the new version, keep `fixups.config` (every line there
   has a comment saying why), and run the merged configuration through
   `kernel/configs/android-*/android-base.config` of the new LineageOS branch: the stack's
   `android_kernel_mainline_configs` shows which base requirements the family cannot meet.
4. Compile the kernel and the DTB alone first, then the modules. Every module name in
   `modprobe/modules.load.*` must still exist.
5. Test from RAM (`fastboot boot`) with a `vendor_dlkm.img` from the same build, in this order: boot
   to the launcher, display and touch, Wi-Fi, sound (play something), sensors (rotate), both cameras,
   battery gauge, adb. Only then flash `product`, write the boot image behind lk2nd, and let the tablet
   restart on its own (the release notes explain why the boot image and `product` must match).
6. Bump the `revision` of the kernel project in `local_manifests/gtowifi_mainline.xml` and say in the
   commit message which tag it is based on.

### Power-management release gate

The published r12 release deliberately keeps `TARGET_SUPPORTS_SUSPEND := false`. Do not change it just
because the new kernel config exposes `s2idle`: Android will otherwise remove the permanent wake lock
and begin suspending a tablet that has not completed its resume validation.

For the first kernel release that carries the cpuidle and DRM suspend fixes, first test the candidate
kernel by RAM boot with the matching `vendor_dlkm.img`. Confirm repeated RTC wake-ups and that display,
touch, Wi-Fi, USB gadget, and ADSP audio all work after resume. Then make a separate Android test build
with `TARGET_SUPPORTS_SUSPEND := true`; verify alarm and power-key wake, the same post-resume checks,
and an unplugged overnight screen-off drain measurement. Only a build that passes those tests may enable
suspend in a published release. Update the README and release notes with the exact kernel revision and
measured limitations at that time.

## Moving to a newer LineageOS branch

1. `repo init -b lineage-XX`, and set the same branch for every project in
   `local_manifests/gtowifi_mainline_deps.xml`: the stack repositories are branched per release.
2. Read `device/mainline/generic/docs/patches.md` of the new branch: it names the platform changes the
   stack needs from Gerrit. For 23.2 there were none left (all abandoned as no longer needed).
3. `tools/apply-patches.sh`: what no longer applies has either landed (delete the patch) or moved
   (rebase it). `patches/hardware/libhardware` only matters for the framebuffer path
   (`TARGET_USES_FRAMEBUFFER_DISPLAY`), which the DRM driver made obsolete.
4. Check the things Android pins by version: `PRODUCT_SHIPPING_API_LEVEL` in `device.mk`,
   `target-level` in `vintf/manifest.xml`, the GNSS HAL's AIDL version in `gnss/Android.bp` and
   `gnss/android.hardware.gnss-service.qmiloc.xml` (must be one the framework of the new branch
   accepts; `hardware/interfaces/gnss/aidl/Android.bp` lists the frozen versions), the camera
   provider (`android.hardware.camera.provider@2.5-service_64`, HIDL, still shipped by LineageOS as long
   as the mainline stack uses it).
5. The camera stack is pinned independently of LineageOS. A newer libcamera needs the patches in
   `libcamera/patches/` rebased (they are plain `diff -urN` patches against v0.7.2, in order; the first
   ones touch the Android HAL, the later ones the software ISP and the `simple` IPA). Check whether
   `aospext` still builds Mesa the same way (`libcamera/Android.mk` borrows its `RUST_BIN_DIR` trick to
   get a recent meson).
6. Build `bootimage vendorimage vendor_dlkmimage systemimage`, test from RAM with the old `system` still
   installed where possible (a `system` of another branch usually does not run against the old
   `vendor`, so plan for a `userdata` format the first time a major branch changes), then flash.

## Building

A plain LineageOS build machine builds this tree with the sequence in `README.md`. The author builds
in a Docker container (Ubuntu 22.04 with the LineageOS build dependencies, `repo` and a recent meson),
with the tree, ccache and output on a separate disk; nothing of that is specific to this device. An
incremental build after a device-tree-only change takes a few minutes; a fresh tree with the camera
stack about an hour on a large machine. `repo manifest -r` after a good build gives a manifest with
every project pinned, which is what to keep next to the images of a release.

## Flashing, every time

    fastboot flash vendor vendor.img
    fastboot flash product vendor_dlkm.img
    fastboot boot boot-fastboot-v0.img          # test from RAM first
    # then the same boot image behind lk2nd in BOOT (release notes, "Install", step 6)

The boot image in BOOT and the modules in `product` have to be from the same build: a kernel loads only
its own modules, and without them there is no display driver, so Android restarts for ever while adb
still works. RECOVERY keeps lk2nd alone and is the way back to fastboot (Volume Up + Power).
