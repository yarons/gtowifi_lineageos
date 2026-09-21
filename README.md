# LineageOS on the mainline kernel: Samsung Galaxy Tab A 8.0 (2019) Wi-Fi

Device tree for the SM-T290 (`gtowifi`, Qualcomm SDM429) running a **mainline Linux kernel** instead of
Samsung's 4.9 vendor kernel. Product name `gtowifi_mainline`. UNOFFICIAL, not affiliated with the
official `gtowifi` LineageOS builds.

> **State: boots to the launcher from the eMMC (first boot 2026-09-20), real display driver and GPU
> rendering, Wi-Fi, sound, sensors and both cameras work, SELinux permissive. Not a daily driver.** Derived from the `mi439_mainline` target of
> `LineageOS/android_device_xiaomi_mi89xx-mainline` (Xiaomi SDM439: same kernel fork, same lk2nd
> platform, same touchscreen and Wi-Fi/Bluetooth drivers). Started with `fastboot boot` from lk2nd; the
> combined boot image in the BOOT partition is still untried. See the hardware table for what was
> actually seen working.

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
| `kernel/mainline/msm89x7-mainline` | https://github.com/msm89x7-mainline/linux 7.1.3 + the gtowifi board work in https://github.com/yarons/linux_msm89x7, branch `gtowifi/display-v2` (`sdm429-samsung-gtowifi.dts`, PM8953 second SPMI slave, `aw87319` amplifier driver, sound card, PMI632 charger and fuel gauge, regulator loads, 12nm DSI PHY, ILI9881C panel, GPU). Not pushed there yet: the cameras (sensor drivers, lens, CAMSS board nodes), the 2.4 GHz Wi-Fi fix and the two DRM fixes named in the hardware table | 7.1.3 |

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

Seen on the tablet on 2026-09-20 and 2026-09-21 unless marked otherwise.

| | Kernel | Android |
|---|---|---|
| Boot, eMMC, USB gadget (adb, MTP), touchscreen, keys | works | works |
| SD card | works | untested |
| Wi-Fi (WCN3660B) | firmware read from the tablet's `apnhlos` and `persist` partitions. 5 GHz and 2.4 GHz work. 2.4 GHz needs the kernel change that stops advertising 40 MHz channels on that band: the firmware rejects the join otherwise (`hal_join`/`hal_config_bss` -5), and the next 5 GHz link drops within seconds. `qcom,wcn3680` as iris variant is wrong for this unit | connects (WPA2); WPA2/WPA3 transition networks need the overlay in `rro_overlays/` that keeps Android from upgrading to SAE, because wcn36xx has no 802.11w |
| Bluetooth | works under postmarketOS | untested |
| Display | drm/msm MDP5 with a driver for the SDM429 12nm DSI PHY and the ILI9881C panel. The backlight is a `pwm-backlight` on the PM8953 PWM (`/sys/class/backlight/backlight`), tested from an initramfs. Android needs two fixes: drm/msm leaked the GEM objects of clients without their own GPU address space (`msm_gem_close`), and `fence_to_crtc()` races with the signalling of a CRTC out-fence, a kernel BUG after a few hours because Android reads `SYNC_IOC_FILE_INFO` of every out-fence | drm_hwcomposer + minigbm; brightness control through the stack's lights HAL is untested. `mdp5_crtc_atomic_check: too many planes` in the kernel log is harmless (3 blend stages, the composer falls back to the GPU) |
| GPU (Adreno 504, driven as A505) | drm/msm | Mesa freedreno, OpenGL ES 3.1 (`FD505`) |
| Audio (ADSP, PM8953 codec, 2x `aw87319`) | sound card registers, both amplifiers probe; playback and the built-in microphone work | tinyhal, `audio/audio.gtowifi_mainline.xml`: speakers and the built-in microphone work (videos have sound). Software noise suppression and gain control for the microphone are configured (`audio/audio_effects.xml`) but not verified; headphone jack and headset untested |
| Battery, charging (PMI632) | SMB5 charger + fuel gauge (level, voltage, OCV, current, charge) | real level, voltage, temperature and charger state through the default health AIDL HAL |
| Sensors (behind the ADSP) | accelerometer and proximity appear as IIO devices (`qcom_sns_reg` serves the registry from `persist`, then `qcom_smgr`); no gyroscope | IIO sensors HAL: both work, auto-rotate works. Needs the ueventd rules, the HAL restart after the ADSP is up and the axis properties of this tree |
| Suspend | off | off |
| Cameras (GC8034 rear with focus motor, GC2375H front, on CAMSS) | sensor and lens drivers from the board work; raw Bayer frames through V4L2 | libcamera 0.7.2: simple pipeline handler with the software ISP (CPU), its Android HAL under the legacy camera provider, and the patches in `libcamera/patches/` (the HAL did not work with this kind of camera as it is). Preview at 21 to 24 fps (rear in the binned 1624x1224 mode; the 8 MP mode gives about 5 fps and is switched off in `libcamera/camera_hal.yaml`), photos (rear 2 MP), video 640x480 with sound, continuous autofocus and tap to focus, exposure compensation. No colour correction matrix and no noise reduction: pure colours are pale and low light is noisy. 720p video untested |
| GNSS | bring-up in progress | nothing |
| SELinux | | permissive |
| RAM | | tight (1.9 GB). zram needs the init script of this tree: `swapon_all` fails on current kernels |

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
    sudo device/samsung/gtowifi_mainline/tools/partition-sdcard.sh /dev/sdX
    fastboot boot $OUT/boot.img.mkbootimg

No Linux machine for `partition-sdcard.sh`? `tools/make-sdcard-image.sh <image dir>` assembles the same layout
into one raw file (7.2 GiB, fits any 8 GB card) that can be written with `dd` from any OS.

`boot.img.mkbootimg` is header v2 and needs an lk2nd built with `OSVERSION_IN_BOOTIMAGE=1` (the one this
tree builds). lk2nd release binaries only read header v0 with an appended DTB:
`tools/make-fastboot-boot-img.sh` repacks the image for them.

**On the eMMC.** Samsung's partition table stays as it is: `vendor_dlkm` goes to `product`, `metadata` to
`logdump`. `userdata` must be formatted: the official build encrypts it with keys held by the QSEE
keymaster, which a mainline kernel cannot reach. The same applies on the way back.

## Build

    repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs
    cp device/samsung/gtowifi_mainline/local_manifests/gtowifi_mainline.xml .repo/local_manifests/
    repo sync
    # platform patches: device/mainline/generic/docs/patches.md
    source build/envsetup.sh && breakfast gtowifi_mainline userdebug && mka bacon

## Credits

LineageOS mainline stack and the Xiaomi msm89xx targets this is derived from: 0xCAFEBABE and the
LineageOS contributors. Kernel: msm89x7-mainline (Barnabás Czémán and contributors). lk2nd:
msm8916-mainline. Samsung boot image trailer: LineageOS `android_device_samsung_gtowifi`
(lifehackerhansol) and TBM13's A20s fix tool.
