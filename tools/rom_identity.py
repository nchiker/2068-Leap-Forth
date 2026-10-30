#!/usr/bin/env python3
"""Set or check the HOME image's ROM_IDENTITY cell (docs/V2/STORAGE_SPEC.md D3).

A SAVE-LIB image carries the identity of the ROM that saved it, and LOAD-LIB / VERIFY-LIB refuse an image whose
identity is not theirs. The identity is $8000 | the CRC-16/CCITT-FALSE of the whole image with the 2-byte
ROM_IDENTITY cell zeroed, so any other change to the ROM's bytes changes it. The assembler emits the cell as 0;
--patch writes the value into the image (the .lst keeps showing 0), --verify recomputes it (make check).
  tools/rom_identity.py --patch  build/forth_boot_rom0.bin build/forth_boot.sym
  tools/rom_identity.py --verify build/forth_boot_rom0.bin build/forth_boot.sym
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


def main(argv):
    if len(argv) != 3 or argv[0] not in ('--patch', '--verify'):
        sys.exit(__doc__)
    mode, bin_path, sym_path = argv
    m = re.search(r'^ROM_IDENTITY: EQU 0x([0-9A-Fa-f]+)$', open(sym_path).read(), re.M)
    if not m:
        sys.exit(f'rom_identity: no ROM_IDENTITY in {sym_path}')
    at = int(m.group(1), 16)
    img = bytearray(open(bin_path, 'rb').read())
    have = img[at] | img[at + 1] << 8
    img[at:at + 2] = b'\0\0'
    want = 0x8000 | crc16(img)
    if mode == '--patch':
        img[at], img[at + 1] = want & 0xFF, want >> 8
        open(bin_path, 'wb').write(img)
        print(f'rom_identity: {bin_path}: ROM_IDENTITY (${at:04X}) = ${want:04X}')
        return 0
    if have != want:
        print(f'rom_identity: FAIL {bin_path}: ROM_IDENTITY (${at:04X}) is ${have:04X}, should be ${want:04X}')
        return 1
    print(f'rom_identity: ok {bin_path}: ${have:04X}')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
