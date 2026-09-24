# Kernel-only test set

Try a kernel branch on the tablet without an Android build. `make-test-set.sh` builds the kernel with
the configuration the Android build would use, then puts it into the images of the release that is
installed: the release's boot image gets the new kernel and DTB (its ramdisk and command line stay),
and the release's `vendor_dlkm` gets the new modules. Nothing on the Android side changes, so this
tests kernel work only: drivers, the device tree, power management.

A LineageOS build needs an x86-64 Linux host; this does not. It runs on any Linux with the tools listed
at the top of the script, natively on arm64 (an Apple silicon Mac in a Linux VM or container is fine)
or with an `aarch64-linux-gnu-` cross compiler elsewhere. It is built with GCC, where the Android
build uses clang; for a test that does not matter, kernel and modules come from the same build.

    tools/kernel-test-set/make-test-set.sh \
        --kernel ~/src/linux_msm89x7 --ref gtowifi/android-7.1.3-r15 \
        --release ~/Downloads/23.2-20260921 \
        --fixups <kconfigs/fixups.config with the options the kernel needs> \
        --test-min-uv 3900000 \
        --out ~/r15-test

The configuration fragments of the LineageOS mainline stack and AOSP's `android-base.config` are
fetched when `--stack-configs` and `--android-base` do not point at local copies. Kernel r13 and
later need the USB host options (`EXTCON_QCOM_PMIC_UUSB`, `REGULATOR_QCOM_USB_VBUS` built in):
without them USB never comes up, and with it adb. Pass a `fixups.config` that has them.

The result:

| File | |
|---|---|
| `boot-test.img` | for `fastboot boot` only |
| `boot-test-minUV.img` | with `--test-min-uv`: the battery declares UV as its minimum voltage. With 3900000 a kernel that has the empty-battery rule (qcom_smbx, r15 and later) calls the pack empty a minute after the cable goes, and Android shuts down (`shutdown,battery`) |
| `vendor_dlkm.img` | for the `product` partition |
| `config` | the kernel configuration that was built |

## Trying it

From lk2nd's fastboot (Volume Down + Power until the screen is black, release Power, keep Volume Down):

    fastboot flash product vendor_dlkm.img
    fastboot boot boot-test.img

The boot image and the modules in `product` have to come from the same build. BOOT still holds the
release's kernel, so while the test modules are in `product` a normal restart (or plugging a charger
into a switched-off tablet) boots the release kernel against the test modules: no display, and Android
restarts for ever (adb still works). Go back to lk2nd and `fastboot boot boot-test.img` again, or
flash the release's `vendor_dlkm.img` to `product` to be back on the release.

## How the images are made

- Kernel: the configuration list of `BoardConfig.mk` in its order (postmarketOS's configuration, the
  stack's fragments, AOSP's `android-base.config`, then `--fixups`), `Image.gz`, the gtowifi DTB and
  the modules.
- `vendor_dlkm`: the layout of the Android build. Every module flat in `/lib/modules`,
  `modules.dep` with `/vendor_dlkm/lib/modules/` paths, the release's `modules.load` and `etc/`,
  everything owned by root, and the release's SELinux labels (`vendor_file`, `etc/` is
  `vendor_configs_file`). Same size and ext4 features as the release's image, without a journal.
- Boot image: `tools/repack-boot-v0.py` keeps everything of the base image but the kernel, which
  becomes `Image.gz` with the DTB appended, the way lk2nd releases expect it. Repacking a release
  image with its own kernel and DTB reproduces it byte for byte.

First used on 2026-09-24 for kernel r15 on top of release b30, on the author's tablet: display,
touch, Wi-Fi, sound, sensors, cpuidle and the modem came up, and the 3.9 V image shut Android down
one minute after unplugging.
