#!/usr/bin/env python3
"""Set or check a ROM image's ROM_IDENTITY cell (audit step S, docs/V2/STORAGE_SPEC.md D3).

A SAVE-LIB image carries the identity of the ROM that saved it, and LOAD-LIB / VERIFY-LIB refuse an
image whose identity is not theirs. The identity is $8000 | the CRC-16/CCITT-FALSE of the whole
image with the 2-byte ROM_IDENTITY cell zeroed: any change to the ROM's bytes changes it, and the
value does not depend on itself. The assembler emits the cell as 0; --patch writes the value into
the image (the .lst keeps showing 0), --verify recomputes it (make check).

  tools/rom_identity.py --patch  build/forth_boot_rom0.bin build/forth_boot.sym
  tools/rom_identity.py --verify build/forth_boot_rom0.bin build/forth_boot.sym [...more pairs]
"""
import re
import sys


def crc16(data, crc=0xFFFF):
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


assert crc16(b"123456789") == 0x29B1


def cell(sym_path):
    m = re.search(r'^ROM_IDENTITY: EQU 0x([0-9A-Fa-f]+)$', open(sym_path).read(), re.M)
    if not m:
        sys.exit(f'rom_identity: no ROM_IDENTITY in {sym_path}')
    return int(m.group(1), 16)


def identity(img, at):
    z = bytearray(img)
    z[at:at + 2] = b'\0\0'
    return 0x8000 | crc16(z)


def main(argv):
    if len(argv) < 3 or argv[0] not in ('--patch', '--verify') or len(argv) % 2 == 0:
        sys.exit(__doc__)
    mode, pairs = argv[0], list(zip(argv[1::2], argv[2::2]))
    bad = 0
    for bin_path, sym_path in pairs:
        at = cell(sym_path)
        img = bytearray(open(bin_path, 'rb').read())
        want = identity(img, at)
        have = img[at] | img[at + 1] << 8
        if mode == '--patch':
            img[at], img[at + 1] = want & 0xFF, want >> 8
            open(bin_path, 'wb').write(img)
            print(f'rom_identity: {bin_path}: ROM_IDENTITY (${at:04X}) = ${want:04X}')
        elif have != want:
            print(f'rom_identity: FAIL {bin_path}: ROM_IDENTITY (${at:04X}) is ${have:04X}, should be ${want:04X}')
            bad += 1
        else:
            print(f'rom_identity: ok {bin_path}: ${want:04X}')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
