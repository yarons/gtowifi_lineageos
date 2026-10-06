# LineageOS on the mainline kernel: Samsung Galaxy Tab A 8.0 (2019) Wi-Fi

Device tree for the SM-T290 (`gtowifi`, Qualcomm SDM429) running a **mainline Linux kernel** instead of
Samsung's 4.9 vendor kernel. Product name `gtowifi_mainline`. UNOFFICIAL, not affiliated with the
official `gtowifi` LineageOS builds.

> **State (2026-10-05): boots by itself from the eMMC (boot image behind lk2nd in BOOT), real display
> driver and GPU rendering, Wi-Fi, sound, sensors and both cameras work, SELinux enforcing, system
> suspend on: about 1 % battery per hour with the screen off (about 4 days on a charge), and a battery
> percentage that follows the battery while the tablet sleeps.** Derived
> from the `mi439_mainline` target of `LineageOS/android_device_xiaomi_mi89xx-mainline` (Xiaomi SDM439:
> same kernel fork, same lk2nd platform, same touchscreen and Wi-Fi/Bluetooth drivers). See the hardware
> table for what was actually seen working.

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
| `kernel/mainline/msm89x7-mainline` | https://github.com/msm89x7-mainline/linux 7.1.3 + the gtowifi board work in https://github.com/yarons/linux_msm89x7, branch `gtowifi/android-7.1.3-r20`, which is `gtowifi/display-v2` (`sdm429-samsung-gtowifi.dts`, PM8953 second SPMI slave, `aw87319` amplifier driver, sound card, PMI632 charger and fuel gauge, regulator loads, 12nm DSI PHY, ILI9881C panel, GPU) plus the cameras (sensor drivers, lens, CAMSS board nodes), the backlight, the 2.4 GHz Wi-Fi fix, the two DRM fixes named in the hardware table, the modem/GNSS and USB host (OTG) board parts, CPU idle states and suspend fixes, the empty-battery rule of the PMI632 gauge, the MDP flush-order fix, the charger's charging switch (`charge_behaviour`, `charging_enabled`) and state-change interrupt, a fuel gauge that counts the charge of a suspend from the PMI632 QG's FIFO, the vibrator, and the Android patches below | 7.1.3 |

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
| SD card | works | works: a 64 GB SDXC card (exFAT) is mounted as portable storage, 29 MB/s write and 71 MB/s read |
| Wi-Fi (WCN3660B) | firmware read from the tablet's `apnhlos` and `persist` partitions. 5 GHz and 2.4 GHz work. 2.4 GHz needs the kernel change that stops advertising 40 MHz channels on that band: the firmware rejects the join otherwise (`hal_join`/`hal_config_bss` -5), and the next 5 GHz link drops within seconds. `qcom,wcn3680` as iris variant is wrong for this unit | connects (WPA2); WPA2/WPA3 transition networks need the overlay in `rro_overlays/` that keeps Android from upgrading to SAE, because wcn36xx has no 802.11w |
| Bluetooth | works under postmarketOS. `btqcomsmd` only carries commands and ACL data: the chip sends call audio (SCO) over a separate PCM line to the audio DSP, which the sound card here does not route | pairs and connects; music to a Bluetooth headset (A2DP) works. The headset profile (HFP) connects, but calls and Bluetooth microphones cannot work until the kernel routes the chip's voice line. File transfer untested |
| Display | drm/msm MDP5 with a driver for the SDM429 12nm DSI PHY and the ILI9881C panel. The backlight is a `pwm-backlight` on the PM8953 PWM (`/sys/class/backlight/backlight`). Android needs two fixes: drm/msm leaked the GEM objects of clients without their own GPU address space (`msm_gem_close`), and `fence_to_crtc()` races with the signalling of a CRTC out-fence, a kernel BUG after a few hours because Android reads `SYNC_IOC_FILE_INFO` of every out-fence | drm_hwcomposer + minigbm; the brightness setting reaches the backlight through the stack's lights HAL. `mdp5_crtc_atomic_check: too many planes` in the kernel log is harmless (3 blend stages, the composer falls back to the GPU) |
| GPU (Adreno 504, driven as A505) | drm/msm | Mesa freedreno, OpenGL ES 3.1 (`FD505`) |
| Audio (ADSP, PM8953 codec, 2x `aw87319`) | sound card registers, both amplifiers probe; playback and the built-in microphone work; the jack reports headphones and microphones. The headset wiring switch (CTIA/OMTP, TLMM 63 per Samsung's device tree) is not driven | tinyhal, `audio/audio.gtowifi_mainline.xml`: speakers, the built-in microphone and wired headphones (detected, switched to, heard) work. Software noise suppression and gain control for the microphone are configured (`audio/audio_effects.xml`) but not verified; a wired headset microphone is untested |
| Battery, charging (PMI632) | SMB5 charger + fuel gauge (level, voltage, OCV, current, charge). A pack whose loaded voltage stays below its minimum while discharging is reported empty, so that Android shuts down before the pack cuts the power. The charger can stop charging while the tablet keeps running from USB (`charging_enabled`) | real level, voltage, temperature and charger state through this tree's health HAL (`health/`, empty battery reads 0 %). LineageOS charging control (Settings > Battery > Charging control) works: with a limit set, charging stops there and resumes below it. Android's charging status follows at once (r19: the charger's state-change interrupt; about 80 ms both ways) |
| Sensors (behind the ADSP) | accelerometer and proximity appear as IIO devices (`qcom_sns_reg` serves the registry from `persist`, then `qcom_smgr`); no gyroscope | IIO sensors HAL: both work, auto-rotate works. Needs the ueventd rules, the HAL restart after the ADSP is up and the axis properties of this tree |
| Vibrator (PMI632) | coin DC motor on the PMIC's vibrator peripheral, `pm8xxx-vibrator` (r20): a force-feedback input device | GloDroid's vibrator HAL, told where to find it by `ro.vendor.vibrator.input_path` (its fixed path fits only a platform device named `vibrator`; `patches/hardware/mainline/common`). Felt on the tablet with a direct force-feedback test (2026-10-06); through Android: build 38 |
| Suspend | s2idle with CPU idle states (WFI, power collapse). A screen-on after a resume used to start the MDP before its flush and could hang the tablet in an IOMMU fault storm; fixed in r17 (`drm/msm/mdp5: Flush before starting the video timing engine`, 0 faults in 1000+ suspends). The SoC itself does not power down (no RPM vlow/vmin) on this kernel | on (`TARGET_SUPPORTS_SUSPEND := true`): wake-ups by power key and alarm work, Wi-Fi disconnects during suspend (no WoWLAN set up) and reconnects within about 20 s of a screen-on. Measured 2026-10-04 with r19, whose gauge counts the charge of a suspend: **about 1 % per hour** (48.5 mA asleep) unplugged with the screen off and Wi-Fi on, about 4 days on a charge (1.7 % per hour without suspend); about 10 wake-ups an hour, all RTC alarms. Up to r18 the gauge did not count a suspend at all: the percentage stood still and caught up at the next rested OCV reading, and an earlier 0.43 % per hour was that artefact. WoWLAN (`iw phy0 wowlan enable any`) keeps Wi-Fi connected through a suspend but wakes the tablet about 100 times an hour: 1.55 % per hour, so it is not set up |
| Cameras (GC8034 rear with focus motor, GC2375H front, on CAMSS) | sensor and lens drivers from the board work; raw Bayer frames through V4L2 | libcamera 0.7.2: simple pipeline handler with the software ISP (CPU), its Android HAL under the legacy camera provider, and the patches in `libcamera/patches/` (the HAL did not work with this kind of camera as it is). Preview at 21 to 24 fps (rear in the binned 1624x1224 mode; the 8 MP mode gives about 5 fps and is switched off in `libcamera/camera_hal.yaml`), photos (rear 2 MP), video with sound, continuous autofocus and tap to focus, exposure compensation, camera ids pinned (rear 0, front 1). No colour correction matrix, no lens shading correction and no noise reduction: pure colours are pale and low light is noisy. Video records at up to 720p with AAC sound (`media/`), at about 14 frames per second: the software encoder and the software ISP share four cores |
| GNSS | the location engine runs on the modem DSP, which this Wi-Fi model has too: the modem boots and its QMI location service (LOC v2 over QRTR) comes up. A modem that has run once keeps the SoC out of its deepest sleep until the next restart | `gnss/`: an AIDL GNSS HAL that speaks QMI LOC over QRTR without any proprietary library, plus the modem bring-up (firmware from the tablet's `modem` partition, `rmtfs` read-only so that the EFS partitions are never written, `tqftpserv` for its configuration files). **Off by default** to save power: `setprop persist.vendor.gtowifi.gnss 1` (and a restart after switching it off again). A position fix under Android is untested |
| USB host (OTG) | micro-USB ID detection and the VBUS boost of the PMI632, `usb-storage` built in | untested under Android |
| SELinux | | **enforcing**: `sepolicy/vendor` for the device, `sepolicy/private` (system_ext) for the few rules that need platform-private types. Shared memory from libcutils is labelled `ashmem_compat_memfd` (a patch in `patches/system/core`), so it needs no rule per pair of processes |
| Time | the PM8953 RTC cannot be set | Sony's TimeKeep (from the stack) keeps the offset, so the clock is right after a restart without network |
| RAM | | tight (1.9 GB). zram (1 GB) needs the init script of this tree: `swapon_all` fails on current kernels |
| Hangs | `softlockup_panic=1` on the command line (`panic=5` restarts); hung tasks (300 s) panic through `ro.khungtask.*` and llkd's init script | a frozen tablet restarts by itself instead of waiting for the key combination (it froze twice in September: a GPU fault, the MDP fault storm); `/proc/sys/kernel/{softlockup,hung_task}_panic` = 1, `hung_task_timeout_secs` = 300 |

No proprietary files are part of the build. Radio, DSP and codec firmware is loaded from the tablet's
own partitions; GPU microcode comes from linux-firmware.

## Boot image

Samsung bootloader -> lk2nd (first image in the partition) -> Android boot image at 512 KiB.
Bootloaders with binary revision 4 or later want a `SignerVer02` block behind the first image and an AVB
footer at the end of the partition; `mkbootimg.mk` adds both (lk2nd with its block is 326160 bytes, so it
fits below the offset). Works on the author's tablet since 2026-09-21: it starts LineageOS by itself.

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
    git clone -b lineage-23.2 https://github.com/yarons/gtowifi_lineageos /tmp/gtowifi_lineageos
    mkdir -p .repo/local_manifests
    cp /tmp/gtowifi_lineageos/local_manifests/*.xml .repo/local_manifests/
    repo sync
    device/samsung/gtowifi_mainline/tools/apply-patches.sh
    source build/envsetup.sh && breakfast gtowifi_mainline userdebug
    mka bootimage vendorimage vendor_dlkmimage systemimage

The two manifests list everything that is not part of a plain LineageOS checkout: this tree, the
kernel, LineageOS's mainline-kernel stack, and for the cameras upstream libcamera v0.7.2 plus
GloDroid's `aospext` (meson inside the Android build, the same way the stack builds Mesa), both
pinned. `libcamera/patches/` is applied to a copy of libcamera at build time
(`BOARD_LIBCAMERA_PATCHES_DIRS`); `tools/apply-patches.sh` applies `patches/` to the platform
(libcutils memfd relabel, gralloc colour order, the vibrator HAL's input path).
Nothing has to be picked from Gerrit: the four `system/core` changes that
`device/mainline/generic/docs/patches.md` names were abandoned, the stack no longer needs them.

Install, from lk2nd's fastboot (the partition table stays Samsung's):

    fastboot flash system system.img
    fastboot flash vendor vendor.img
    fastboot flash product vendor_dlkm.img
    device/samsung/gtowifi_mainline/tools/make-fastboot-boot-img.sh $OUT boot-fastboot-v0.img
    fastboot boot boot-fastboot-v0.img

`vendor_dlkm.img` holds the kernel modules and has to come from the same build as the boot image.

How the tree is kept up to date with newer kernels and LineageOS branches: `docs/updating.md`.

## Credits

LineageOS mainline stack and the Xiaomi msm89xx targets this is derived from: 0xCAFEBABE and the
LineageOS contributors. Kernel: msm89x7-mainline (Barnabás Czémán and contributors). lk2nd:
msm8916-mainline. Samsung boot image trailer: LineageOS `android_device_samsung_gtowifi`
(lifehackerhansol) and TBM13's A20s fix tool.
