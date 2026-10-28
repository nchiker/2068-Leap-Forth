#!/usr/bin/env python3
"""Wrap a 16K DOCK-cartridge ROM image (a CARTRIDGE build of rom/forth_boot.asm
or rom/forth_demo_blackjack.asm) as a .dck file for emulators, optionally with
the graphics EXROM image carried as DOCK chunk 5.

DCK is the Warajevo/Fuse Timex cartridge container: a 9-byte header --
bank id (0 = DOCK, 254 = EXROM, 255 = HOME) then one type byte per 8K chunk
(0 = absent, 1 = RAM, 2 = ROM data follows, 3 = RAM data follows) -- followed by
8K of data for every chunk marked 2 or 3. A 16K image at $0000 is DOCK chunks 0
and 1, so the header is 00 02 02 00 00 00 00 00 00.

With a third argument (an 8K image, build/graphics_exrom.bin) it becomes DOCK
chunk 5, header 00 02 02 00 00 00 02 00 00: that is how the cartridge build of
rom/forth_boot.asm reaches RECT, POLYGON, POLYGON-FILL and SPRITE-* (the
cartridge pages chunk 5 with one OUT to port $F4; see docs/V2/CARTRIDGE_EXROM_SPEC.md).
The LROS header byte (offset 4) still names only chunks 0-1: the OS never maps chunk 5.
The image's service-table trailer (magic, ABI version) is checked here, so a
wrong file cannot be packed as chunk 5.

Fuse:    fuse --machine ts2068 --dock forth_boot.dck
ZEsarUX: smartload the .dck, then hard reset.

Usage:  tools/make_dck.py build/forth_boot_cart.bin build/forth_boot.dck [build/graphics_exrom.bin]
"""
import sys

# include/graphics_exrom_abi.inc: GRAPHICS_EXROM_MAGIC, GRAPHICS_EXROM_ABI, and the trailer's
# offset ($A000 + MAX_SLOTS * 3 + 1 - $A000 = 8 * 3 + 1)
MAGIC, ABI, TRAILER = 0xF0, 1, 8 * 3 + 1

if len(sys.argv) not in (3, 4):
    sys.exit(__doc__)
src, dst = sys.argv[1], sys.argv[2]
img = open(src, 'rb').read()
if len(img) != 16384:
    sys.exit(f"{src}: expected a 16384-byte image, got {len(img)}")
if img[1] != 0x01:
    sys.exit(f"{src}: byte 1 is ${img[1]:02X}, not $01 -- this is not an LROS image "
             "(build with -DCARTRIDGE, e.g. make forth-boot-cart)")
chunk5 = b''
if len(sys.argv) == 4:
    chunk5 = open(sys.argv[3], 'rb').read()
    if len(chunk5) != 8192:
        sys.exit(f"{sys.argv[3]}: expected an 8192-byte chunk-5 image, got {len(chunk5)}")
    if chunk5[TRAILER:TRAILER + 2] != bytes([MAGIC, ABI]):
        sys.exit(f"{sys.argv[3]}: bytes {TRAILER}-{TRAILER + 1} are {chunk5[TRAILER:TRAILER + 2].hex()}, "
                 f"not the graphics EXROM trailer {MAGIC:02x}{ABI:02x}")
with open(dst, 'wb') as f:
    f.write(bytes([0x00, 2, 2, 0, 0, 0, 2 if chunk5 else 0, 0, 0]))
    f.write(img)
    f.write(chunk5)
print(f"wrote {dst} ({9 + len(img) + len(chunk5)} bytes; LROS start ${img[3]:02X}{img[2]:02X}, "
      f"chunk spec ${img[4]:02X}{', chunk 5 = ' + sys.argv[3] if chunk5 else ''})")
