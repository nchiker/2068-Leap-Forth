#!/usr/bin/env python3
"""Set or check a ROM image's ROM_IDENTITY cell (audit step S, docs/V2/STORAGE_SPEC.md D3).

A SAVE-LIB image carries the identity of the ROM that saved it, and LOAD-LIB / VERIFY-LIB refuse an
image whose identity is not theirs. The identity is $8000 | the CRC-16/CCITT-FALSE of the whole
image with the 2-byte ROM_IDENTITY cell and the skip ranges zeroed: any other change to the ROM's
bytes changes it, and the value does not depend on itself. A skip range runs from a label named
ROM_ID_SKIP_x (or a local .rom_id_skip) to ROM_ID_SKIP_x_END (.rom_id_skip_end); the Home and
cartridge builds differ only inside them, so both get the same identity and share LIB tapes.
The assembler emits the cell as 0; --patch writes the value into the image (the .lst keeps
showing 0), --verify recomputes it (make check), and --shared checks that two images differ only
inside their (identical) skip ranges and have the same identity (make check, Home vs cartridge).

  tools/rom_identity.py --patch  build/forth_boot_rom0.bin build/forth_boot.sym
  tools/rom_identity.py --verify build/forth_boot_rom0.bin build/forth_boot.sym [...more pairs]
  tools/rom_identity.py --shared build/forth_boot_rom0.bin build/forth_boot.sym \
                                 build/forth_boot_cart.bin build/forth_boot_cart.sym
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


SYM = re.compile(r'^(\S+): EQU 0x([0-9A-Fa-f]+)$', re.M)


def symbols(sym_path):
    syms = {k: int(v, 16) for k, v in SYM.findall(open(sym_path).read())}
    if 'ROM_IDENTITY' not in syms:
        sys.exit(f'rom_identity: no ROM_IDENTITY in {sym_path}')
    return syms


def skips(syms):
    """The (start, end) ranges the identity leaves out, ROM_IDENTITY's cell first."""
    out = [(syms['ROM_IDENTITY'], syms['ROM_IDENTITY'] + 2)]
    for k, a in sorted(syms.items(), key=lambda kv: kv[1]):
        if re.search(r'(^ROM_ID_SKIP_\w+|\.rom_id_skip)$', k) and not k.endswith('_END'):
            end = syms.get(k + ('_end' if k.endswith('.rom_id_skip') else '_END'))
            if end is None or end < a:
                sys.exit(f'rom_identity: {k} has no end label after it')
            out.append((a, end))
    return out


def masked(img, ranges):
    z = bytearray(img)
    for a, e in ranges:
        z[a:e] = bytes(e - a)
    return z


def identity(img, ranges):
    return 0x8000 | crc16(masked(img, ranges))


def shared(pairs):
    (ba, sa), (bb, sb) = pairs
    ra, rb = skips(symbols(sa)), skips(symbols(sb))
    if ra != rb:
        print(f'rom_identity: FAIL {ba} and {bb} have different skip ranges')
        return 1
    ia, ib = open(ba, 'rb').read(), open(bb, 'rb').read()
    diff = [i for i, (x, y) in enumerate(zip(masked(ia, ra), masked(ib, rb))) if x != y]
    if len(ia) != len(ib) or diff:
        print(f'rom_identity: FAIL {ba} and {bb} differ outside the skip ranges, first at ${diff[0]:04X}'
              if diff else f'rom_identity: FAIL {ba} and {bb} differ in length')
        return 1
    if ia[ra[0][0]:ra[0][1]] != ib[rb[0][0]:rb[0][1]]:
        print(f'rom_identity: FAIL {ba} and {bb} have different ROM_IDENTITY cells')
        return 1
    n = sum(e - a for a, e in ra[1:])
    print(f'rom_identity: ok {ba} and {bb} share identity, {n} bytes skipped in {len(ra) - 1} ranges')
    return 0


def main(argv):
    if len(argv) < 3 or argv[0] not in ('--patch', '--verify', '--shared') or len(argv) % 2 == 0:
        sys.exit(__doc__)
    mode, pairs = argv[0], list(zip(argv[1::2], argv[2::2]))
    if mode == '--shared':
        if len(pairs) != 2:
            sys.exit(__doc__)
        return shared(pairs)
    bad = 0
    for bin_path, sym_path in pairs:
        ranges = skips(symbols(sym_path))
        at = ranges[0][0]
        img = bytearray(open(bin_path, 'rb').read())
        want = identity(img, ranges)
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
