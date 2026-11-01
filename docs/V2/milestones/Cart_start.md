# Cart start — a program cartridge starts without the power-on CRC: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/step-cart-start` from `v2/step-polygon-edges` (PR #20). The
ROADMAP's known defect from step Cartridge: a program cartridge checked its image's CRC at power-on, about 0.15 s per
1,000 bytes (2.7 s for the largest, 16,128 B). The owner asked to follow Leap V2's cartridge, which is in production.

## 1. What was built

- **How Leap V2 does it.** Its runtime cartridge (`~/Projects/Leap-Cartridge`, `leap/rom/v2_cart_home.asm`,
  `CART_LOAD`) compares a 12-byte signature (`"LEAPPROG"`, the format, the build identity) and checks the length,
  then copies: no checksum over the program at power-on. Its packer (`tools/leap2cart.mjs`) refuses a program for
  another build; the image in ROM is trusted.
- **The same here.** `CART_START_PROGRAM` (`kernel/bank/cart.asm`) checks the magic, `ROM_IDENTITY`, the length and
  the start word's length, as before, and no longer runs `STORAGE_CRC` over the image. The image format is unchanged:
  `tools/forthcart.py` (and the Leap IDE, its answers' Q7 note) still writes the CRC and checks the SAVE-LIB tape's,
  so a damaged tape is refused when the cartridge is built.
- **The trade:** a cartridge whose ROM bytes were changed after packing is no longer caught at power-on. Leap V2 makes
  the same trade: a cartridge's bytes are written once, from a checked file.

## 2. Measured (ZEsarUX 13.0, stock ROM; TSRun's core for the hand-off)

| What | Before | After |
|---|---:|---:|
| `CART_ENTRY` to the start word, 42-byte dictionary | 1,128,777 T | 1,002,679 T |
| The same, 16,128-byte dictionary | 9,547,637 T (2.7 s) | 1,341,621 T (0.38 s) |
| The cartridge's own code | 194 B | 173 B |
| The cartridge's HOME image free | 1,730 B | 1,751 B |

The release images do not change (the cartridge's code is `-DCARTRIDGE` only).

## 3. Tests

`tools/carttest.py` (make test's `cart` suite): `largest` must load within `LOAD_CEIL` (2,000,000 T): it fails on the
previous build (9,547,637 T). `bad-crc` goes (the cartridge no longer checks it; `packer` already refuses a damaged
tape). Cart suite 11/11. `make check` passes (`cart_check`: every release label at its address).

Emulators only (ZEsarUX 13.0, TSRun); no cartridge hardware.
