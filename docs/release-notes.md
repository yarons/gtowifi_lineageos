<!-- Release notes for .github/workflows/release.yml. @TAG@ and @RUN@ are filled in when a
     release is published; the checksums are appended from the build. -->

**UNOFFICIAL pre-release for testers, `@TAG@`.** Not affiliated with the official LineageOS `gtowifi`
builds (those stop at 22.2 on Samsung's 4.9 kernel). This one runs Linux 7.1.3 from the msm89x7-mainline
fork with a board port for the tablet, on LineageOS's own mainline-kernel device stack.

Built from https://github.com/yarons/gtowifi_lineageos branch `lineage-23.2` (commit `1f9870f`) and the
kernel https://github.com/yarons/linux_msm89x7 branch `gtowifi/android-7.1.3-r12` (commit `fe8e5b841`).
No proprietary files are in the images: Wi-Fi/Bluetooth, DSP and codec firmware is read from the
tablet's own partitions, GPU microcode comes from linux-firmware.

## Read this before you flash

- **userdebug build, test-keys, SELinux permissive, `adb root` works.** Do not keep anything sensitive
  on it. This is a bring-up build.
- **The battery drains fast when the tablet is idle.** System suspend is switched off and the CPUs have
  no idle states yet (kernel work in progress). Switch the tablet off when it is not used.
- Coming from Samsung's firmware or the official LineageOS build, **`userdata` has to be formatted**:
  the old data is encrypted with keys in Qualcomm's secure world, which a mainline kernel cannot reach.
  The same applies on the way back. Make a backup first.
- You need an **unlocked boot loader and lk2nd in the BOOT and RECOVERY partitions** first (see
  "Install"). Flashing a boot chain can leave a tablet that only starts in download mode; you should be
  comfortable restoring stock firmware with Odin. You do this at your own risk.

## What works (seen on the author's tablet)

Boot from the eMMC in under a minute, display with the real DRM driver, GPU (freedreno, OpenGL ES 3.1),
backlight control, touch, keys, Wi-Fi on 2.4 and 5 GHz (WPA2), speakers, built-in microphone,
accelerometer/auto-rotate and proximity, battery gauge and charging, USB (adb, MTP), Bluetooth pairing
(encrypted link to a computer; audio devices not tried), both cameras through
libcamera's software ISP (preview, photos, 720p video with AAC sound at about 14 fps, autofocus and tap to focus on the
rear camera, exposure compensation), boots by itself once the boot image sits behind lk2nd. This exact
set of images runs on the author's tablet.

## What does not, or was not tested

Suspend and CPU idle (see above), SELinux enforcing, GPS (the HAL is in the build, the kernel part is
not in this release), USB host/OTG (works with a newer kernel branch, not in this release), Bluetooth
audio devices and the headphone jack under Android (untested; the jack works at kernel level),
rear photos above 2 MP (the 8 MP sensor mode gives 5 fps through the CPU ISP and is switched off), no
colour correction matrix, lens shading correction or noise reduction in the cameras, microSD under
Android (untested; works at kernel level), hardware video codecs (none: software codecs only).

## Files

| File | Partition | Notes |
|---|---|---|
| `system.img.xz` | `system` | unpack first: `xz -d system.img.xz` (1.76 GB sparse image) |
| `vendor.img` | `vendor` | |
| `vendor_dlkm.img` | `product` | kernel modules; Samsung's partition table has no `vendor_dlkm`, `product` is used |
| `boot-fastboot-v0.img` | behind lk2nd in `boot`, or `fastboot boot` | Android boot image, header v0 with the DTB appended: what lk2nd releases understand |
| `boot.img.mkbootimg` | - | the same as header v2, for an lk2nd built with `OSVERSION_IN_BOOTIMAGE=1` |
| `lk2nd-gtowifi-64MiB.img.xz` | `recovery` and `boot` | the boot loader stage that gives fastboot and starts the Android boot image, see "Install" |
| `pinned-manifest-2026-09-21.xml` | - | `repo manifest -r` of the build: every LineageOS project at its exact commit |
| `SHA256SUMS` | | checksums, also of the two unpacked files |

The boot image and `vendor_dlkm.img` belong together: never mix them between releases.

## Install

What is marked **(done)** was done on the author's tablet: SM-T290, CSC XAR, boot loader
`T290UES5CWG5` (binary revision 5), coming from stock Android 11. Everything else is marked.

**1. Unlock the boot loader (done).** The way the LineageOS wiki describes it for `gtowifi`: remove
all accounts, Developer options -> OEM unlocking, power off, plug the USB cable in while holding Volume
Up + Volume Down, long-press Volume Up at the warning screen. This wipes the tablet and trips the Knox
fuse for good.

**2. Flash LineageOS's `vbmeta.img` to VBMETA (done)**, from download mode; the file is on the download
page of the official `gtowifi` build. Done with `samloader flash --partition VBMETA vbmeta.img`
([samloader-rs](https://github.com/topjohnwu/samloader-rs) 2.1.0 on macOS). Odin or Heimdall should do
the same; not tried here.

**3. Flash lk2nd to RECOVERY (done)**: `xz -d lk2nd-gtowifi-64MiB.img.xz`, then
`samloader flash --partition RECOVERY lk2nd-gtowifi-64MiB.img --no-reboot`. The file is
[lk2nd](https://github.com/msm8916-mainline/lk2nd) commit `dd6c1db`, target `lk2nd-msm8952`, unmodified,
wrapped the way boot loaders of binary revision 4 and later want it: `SEANDROIDENFORCE`, a 512-byte
`SignerVer02` block, zero padding to the partition size and a 64-byte `AVBf` footer. Nothing in it is
signed; without the wrapping an unlocked tablet still says "SECURE CHECK FAIL".
Start the recovery **at once** (Volume Up + Power; keep Power held and move from Volume Down to Volume
Up when the screen goes black): if the old system boots first, it may restore its own recovery
(LineageOS 22.2 does, `persist.vendor.recovery_update`). lk2nd's fastboot menu appears.

**4. Put lk2nd into BOOT as well (done, in two halves).** lk2nd's fastboot shows the partition it sits
in as two: `lk2nd` (the first 512 KiB) and `boot` (the rest).

    head -c 524288 lk2nd-gtowifi-64MiB.img > lk2nd-512k.img
    tail -c +524289 lk2nd-gtowifi-64MiB.img > boot-rest.img        # zeros and the footer
    fastboot flash lk2nd lk2nd-512k.img
    fastboot flash boot boot-rest.img

**5. Flash LineageOS (done).**

    xz -d system.img.xz
    fastboot flash system system.img
    fastboot flash vendor vendor.img
    fastboot flash product vendor_dlkm.img
    fastboot format:ext4 userdata          # first install only: erases everything

**6. Start it.** Once, from RAM **(done, this is how every build was tested)**:

    fastboot boot boot-fastboot-v0.img

For a tablet that starts LineageOS by itself, the boot image has to sit at the 512 KiB offset of
BOOT, behind lk2nd. On the author's tablet it was written there from the running system as root
(`dd if=boot-fastboot-v0.img of=/dev/block/by-name/boot bs=1024 seek=512 conv=notrunc,fsync`, read
back and compared) **(done)**: a plain power-on then boots LineageOS in under a minute.
`fastboot flash boot boot-fastboot-v0.img` from lk2nd should write the same place **(not verified by
reading back here)**.

**Later: fastboot again.** Volume Down + Power until the screen is black, release Power, keep Volume
Down through the Samsung logo. That key combination is the only way we know: `adb reboot bootloader`
is Samsung's download mode on this tablet (leave it with Volume Down + Power for ten seconds), and
`adb reboot recovery` boots Android again. RECOVERY keeps lk2nd with nothing behind it, so Volume Up +
Power always ends in fastboot, whatever is in BOOT.

**Updating to a newer release:** flash `vendor` and `product`, `fastboot boot` the new boot image, write
that same boot image behind lk2nd, and only then reboot. A boot image with the kernel modules of another
build loads no modules: no display, Android restarts for ever (adb still works).

**Back to Samsung's firmware: not tested by us.** Standard Samsung procedure: the full firmware for the
exact model and CSC at the same or a newer binary revision, from download mode with Odin. `userdata`
has to be formatted again.

## Source, licences

Device tree: Apache-2.0. Kernel: GPL-2.0, full history in the branch named above. libcamera v0.7.2
(LGPL-2.1-or-later) with the patches in `libcamera/patches/` of the device tree, built through
GloDroid's aospext. The exact revisions of all 1179 LineageOS projects of this build are in
`pinned-manifest-2026-09-21.xml` (attached).
