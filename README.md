# LineageOS on the mainline kernel: Samsung Galaxy Tab A 8.0 (2019) Wi-Fi

Device tree for the SM-T290 (`gtowifi`, Qualcomm SDM429) running a **mainline Linux kernel** instead of
Samsung's 4.9 vendor kernel. Product name `gtowifi_mainline`. UNOFFICIAL, not affiliated with the
official `gtowifi` LineageOS builds.

> **State: skeleton. Never built, never booted.** Written on 2026-09-18 from the `mi439_mainline`
> target of `LineageOS/android_device_xiaomi_mi89xx-mainline` (Xiaomi SDM439: same kernel fork, same
> lk2nd platform, same touchscreen and Wi-Fi/Bluetooth drivers). The only parts exercised so far are
> the kernel configuration (resolved with kconfig) and the boot image layout (built with the real
> `avbtool`, checked with `tools/check-boot-layout.py`).

It sits on LineageOS's mainline-kernel stack and adds nothing generic of its own:

| Path | Repository |
|---|---|
| `device/mainline/common` | `LineageOS/android_device_mainline_common` |
| `device/mainline/qcom-common` | `LineageOS/android_device_mainline_qcom-common` (SoC family `msm8937` covers `sdm429`) |
| `kernel/mainline/configs` | `LineageOS/android_kernel_mainline_configs` |
| `hardware/mainline/qcom` | `LineageOS/android_hardware_mainline_qcom` |
| `external/lk2nd` | `LineageOS/android_external_lk2nd` (knows `samsung,gtowifi`) |

Branch: `lineage-23.2` (Android 16). The official `gtowifi` build stops at 22.2 because Android 16 needs
eBPF features its 4.9 kernel does not have.

## Kernel

| Path | URL | Branch |
|---|---|---|
| `kernel/mainline/msm89x7-mainline` | https://github.com/msm89x7-mainline/linux + `arch/arm64/boot/dts/qcom/sdm429-samsung-gtowifi.dts` (https://github.com/yarons/linux_msm89x7, `gtowifi/7.1.3`) | 7.1.3 |

Patches needed on top, from `kernel/common-patches` (`main-kernel/android-mainline`), exactly as for the
other msm89x7 targets of the stack:

| Patch | Purpose |
|---|---|
| `ANDROID: usb: gadget: configfs: Add Uevent to notify userspace` | USB state in normal mode |
| `ANDROID: mm/memfd-ashmem-shim: Introduce shim layer` | Android 16 libcutils refuses memfd without it; nothing starts |
| `ANDROID: mm: shmem: Use memfd-ashmem-shim ioctl handler` | same |

Then remove the `ASHMEM_C` dependency of `MEMFD_ASHMEM_SHIM` in `mm/Kconfig`.

`kconfigs/config-postmarketos-qcom-msm89x7.aarch64` is postmarketOS's 7.1.3 configuration, copied from
the `lineage-24.0` branch of the Xiaomi tree (the `lineage-23.2` copy is for 6.19). With the stack's
fragments and `kconfigs/fixups.config` it satisfies 248 of the 260 Android 16 base requirements; the
other 12 are clang-only or exist only in the Android common kernel.

## Hardware

| | Kernel | Android |
|---|---|---|
| Boot, eMMC, SD, USB gadget, touchscreen, keys | works | untested |
| Wi-Fi, Bluetooth (WCN3660B) | works, firmware read from the tablet's `apnhlos` and `persist` partitions | untested |
| Display | bootloader framebuffer only; the SDM429 DSI needs a 12nm PHY driver that is not merged anywhere | software rendering (`TARGET_USES_FRAMEBUFFER_DISPLAY`) |
| GPU (Adreno 504, driven as A505) | not enabled | - |
| Audio (ADSP, PM8953 codec, 2x `aw87319`) | not described in the DTS; no `aw87319` driver | dummy HAL |
| Battery, charging (PMI632) | no driver | fake battery |
| Sensors (behind the ADSP) | `qcom_smgr` exists, needs the ADSP | - |
| Suspend | off | off |
| Camera, GNSS | nothing | nothing |
| SELinux | | permissive |

No proprietary files are part of the build. Radio, DSP and codec firmware is loaded from the tablet's
own partitions; GPU microcode comes from linux-firmware.

## Boot image

Samsung bootloader -> lk2nd (first image in the partition) -> Android boot image at 512 KiB.
Bootloaders with binary revision 4 or later want a `SignerVer02` block behind the first image and an AVB
footer at the end of the partition; `mkbootimg.mk` adds both (lk2nd with its block is 326160 bytes, so it
fits below the offset). **This combined image has not been tried on hardware.**

    tools/check-boot-layout.py $OUT/boot.img

## Two ways to run it

**From a microSD card (development, writes nothing to the eMMC).** Build with
`GTOWIFI_MAINLINE_SYSTEM_ON_SDCARD := true`, write the card with `tools/partition-sdcard.sh`, start lk2nd
and run `fastboot boot`. The installed OS is not touched.

    export GTOWIFI_MAINLINE_SYSTEM_ON_SDCARD=true
    breakfast gtowifi_mainline userdebug && mka bootimage systemimage vendorimage vendor_dlkmimage
    sudo device/samsung/gtowifi-mainline/tools/partition-sdcard.sh /dev/sdX
    fastboot boot $OUT/boot.img.mkbootimg

`boot.img.mkbootimg` is header v2 and needs an lk2nd built with `OSVERSION_IN_BOOTIMAGE=1` (the one this
tree builds). lk2nd release binaries only read header v0 with an appended DTB:
`tools/make-fastboot-boot-img.sh` repacks the image for them.

**On the eMMC.** Samsung's partition table stays as it is: `vendor_dlkm` goes to `product`, `metadata` to
`logdump`. `userdata` must be formatted: the official build encrypts it with keys held by the QSEE
keymaster, which a mainline kernel cannot reach. The same applies on the way back.

## Build

    repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
    cp device/samsung/gtowifi-mainline/local_manifests/gtowifi_mainline.xml .repo/local_manifests/
    repo sync
    # platform patches: device/mainline/generic/docs/patches.md
    source build/envsetup.sh && breakfast gtowifi_mainline userdebug && mka bacon

## Credits

LineageOS mainline stack and the Xiaomi msm89xx targets this is derived from: 0xCAFEBABE and the
LineageOS contributors. Kernel: msm89x7-mainline (Barnabás Czémán and contributors). lk2nd:
msm8916-mainline. Samsung boot image trailer: LineageOS `android_device_samsung_gtowifi`
(lifehackerhansol) and TBM13's A20s fix tool.
