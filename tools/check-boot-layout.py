#!/usr/bin/env python3
"""Check that a boot.img/recovery.img built by mkbootimg.mk has the layout the SM-T290 needs.

    check-boot-layout.py <image> [--offset 524288] [--partition-size 67108864]

Verifies: lk2nd boot image at 0, "SEANDROIDENFORCE" + "SignerVer02" directly behind it and below
the offset, an Android boot image at the offset, an AVB footer in the last 64 bytes.
Exit status 0 when everything matches.
"""
import argparse
import struct
import sys

BOOT_MAGIC = b'ANDROID!'


def boot_image_size(buf, base):
    """Size of a header v0-v2 boot image from its header fields (page aligned sections)."""
    kernel, _, ramdisk, _, second, _, _, page = struct.unpack_from('<8I', buf, base + 8)
    version = struct.unpack_from('<I', buf, base + 40)[0]

    def pages(n):
        return (n + page - 1) // page * page

    size = page + pages(kernel) + pages(ramdisk) + pages(second)
    if version > 4:
        # Qualcomm v0 image with a QCDT: this slot holds dt_size instead of a version
        size += pages(version)
        version = 0
    if version in (1, 2):
        size += pages(struct.unpack_from('<I', buf, base + 1632)[0])  # recovery_dtbo_size
    if version == 2:
        size += pages(struct.unpack_from('<I', buf, base + 1648)[0])  # dtb_size
    return size, version


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('image')
    ap.add_argument('--offset', type=int, default=524288)
    ap.add_argument('--partition-size', type=int, default=67108864)
    args = ap.parse_args()

    buf = open(args.image, 'rb').read()
    problems = []

    def check(ok, text):
        print(('ok    ' if ok else 'FAIL  ') + text)
        if not ok:
            problems.append(text)

    check(len(buf) == args.partition_size, f'file size {len(buf)} == partition size {args.partition_size}')
    check(buf[:8] == BOOT_MAGIC, 'lk2nd boot image magic at 0')
    lk2nd_size, lk2nd_ver = boot_image_size(buf, 0)
    print(f'      lk2nd: header v{lk2nd_ver}, {lk2nd_size} bytes by header')
    check(buf[lk2nd_size:lk2nd_size + 16] == b'SEANDROIDENFORCE', f'SEANDROIDENFORCE at {lk2nd_size}')
    signer = lk2nd_size + 16
    check(buf[signer:signer + 11] == b'SignerVer02', f'SignerVer02 at {signer}')
    check(not any(buf[signer + 11:signer + 512]), 'rest of the 512-byte signer block is zero')
    check(signer + 512 <= args.offset, f'signer block ends at {signer + 512}, below offset {args.offset}')
    check(not any(buf[signer + 512:args.offset]), 'padding up to the offset is zero')
    check(buf[args.offset:args.offset + 8] == BOOT_MAGIC, f'Android boot image magic at {args.offset}')
    if buf[args.offset:args.offset + 8] == BOOT_MAGIC:
        size, ver = boot_image_size(buf, args.offset)
        print(f'      android: header v{ver}, {size} bytes by header')
        check(args.offset + size <= args.partition_size - 69632, 'Android image leaves room for the AVB footer')
    footer = buf[-64:]
    check(footer[:4] == b'AVBf', 'AVB footer magic in the last 64 bytes')
    if footer[:4] == b'AVBf':
        major, minor, orig, vb_off, vb_size = struct.unpack_from('>IIQQQ', footer, 4)
        print(f'      AVB footer v{major}.{minor}: original image size {orig}, vbmeta at {vb_off} (+{vb_size})')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
