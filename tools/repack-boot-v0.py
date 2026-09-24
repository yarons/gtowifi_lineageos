#!/usr/bin/env python3
"""Repack an Android boot image of header version 0 with another kernel and DTB.

    repack-boot-v0.py BASE.img IMAGE.gz DTB OUT.img [--cmdline-drop WORD ...] [--cmdline-add WORD ...]

Keeps everything of BASE (ramdisk, addresses, page size, os version, name, the rest of the command
line) and puts IMAGE.gz with DTB appended where the kernel was, the way lk2nd releases expect it.
The id is the SHA-1 mkbootimg computes for version 0 (kernel, ramdisk, second stage, each followed
by its size).
"""
import argparse
import hashlib
import struct
import sys


def pad(data, page):
    return data + b'\0' * ((page - len(data) % page) % page)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('base')
    ap.add_argument('kernel')
    ap.add_argument('dtb')
    ap.add_argument('out')
    ap.add_argument('--cmdline-drop', nargs='*', default=[])
    ap.add_argument('--cmdline-add', nargs='*', default=[])
    a = ap.parse_args()

    b = open(a.base, 'rb').read()
    if b[:8] != b'ANDROID!':
        sys.exit('not an Android boot image')
    ks, ka, rs, ra, ss, sa, ta, ps, hv, osv = struct.unpack('<10I', b[8:48])
    if hv != 0:
        sys.exit(f'header version {hv}, only 0 is handled')
    name = b[48:64]
    cmdline = b[64:576].split(b'\0')[0].decode()
    extra = b[608:1632].split(b'\0')[0].decode()
    full = (cmdline + extra).split()

    koff = ps
    roff = koff + len(pad(b[koff:koff + ks], ps))
    ramdisk = b[roff:roff + rs]
    soff = roff + len(pad(ramdisk, ps))
    second = b[soff:soff + ss]

    words = [w for w in full if w not in a.cmdline_drop] + a.cmdline_add
    new_cmdline = ' '.join(words).encode()
    if len(new_cmdline) > 512 + 1024 - 2:
        sys.exit('command line too long')
    cmd_main, cmd_extra = new_cmdline[:511], new_cmdline[511:]

    kernel = open(a.kernel, 'rb').read() + open(a.dtb, 'rb').read()

    sha = hashlib.sha1()
    for blob in (kernel, ramdisk, second):
        sha.update(blob)
        sha.update(struct.pack('<I', len(blob)))
    idv = sha.digest() + b'\0' * 12

    hdr = b'ANDROID!' + struct.pack('<10I', len(kernel), ka, len(ramdisk), ra, len(second), sa, ta,
                                    ps, 0, osv)
    hdr += name + cmd_main.ljust(512, b'\0') + idv + cmd_extra.ljust(1024, b'\0')
    out = pad(hdr, ps) + pad(kernel, ps) + pad(ramdisk, ps) + (pad(second, ps) if second else b'')
    open(a.out, 'wb').write(out)
    print(f'{a.out}: kernel {len(kernel)} (Image.gz + {len(open(a.dtb, "rb").read())} dtb), '
          f'ramdisk {len(ramdisk)}, {len(out)} bytes, id {sha.hexdigest()}')
    print('cmdline:', new_cmdline.decode())


if __name__ == '__main__':
    main()
