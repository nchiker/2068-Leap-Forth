# ZEsarUX setup

## Can I run it without the patch?

**Yes, for the base 2068-Leap-Forth system — no, for the Phase 65
graphics extension.** This was confirmed by direct A/B testing in this
project's own environment, not assumed:

| What you're running | Stock ZEsarUX 13.0 | Patched ZEsarUX 13.0 |
|---|---|---|
| Base product (`forth_boot_rom0.bin` alone, or with the EXROM placeholder) | Works | Works |
| Graphics extension (`RECT`/`POLYGON`/`POLYGON-FILL`/`SPRITE-DEFINE`/`SPRITE-SHOW`/`SPRITE-HIDE`, Phase 65) | **Fails** — these six words silently do nothing | Works |

The base 143-word dictionary never pages EXROM in at all (only the six
Phase 65 graphics words do), so almost everything in 2068-Leap-Forth —
the whole interpreter, editor, floating point, storage, sound, 64-column
mode, ULAplus palette words — runs correctly under a completely
unmodified, stock ZEsarUX 13.0 download. Only the six graphics words
need the patch below.

### Why the graphics extension needs it

Real TS2068/TC2068 hardware doesn't decode the EXROM's upper address
lines (A13-A15), so the physical 8K EXROM chip repeats itself across
**all eight** 8K memory chunks (0-7), not just chunks 0-1. Stock
ZEsarUX 13.0 only mirrors chunk 0 into chunk 1, matching an older/
incomplete understanding of the hardware. This project's own graphics
code (`kernel/bank/bank.asm`, Phase 65) pages its EXROM in at chunk 5
(`$A000-$BFFF`) — invisible to stock ZEsarUX, correctly visible once
chunks 2-7 are also mirrored.

This was confirmed directly: `rom/test_rect.asm` combined with
`build/graphics_exrom.bin` reports a GREEN border (pass) under a
ZEsarUX built with the patch below, and a BLUE border (checkpoint 1
failure — the RECT dispatch sees no valid EXROM there) under a stock
build from the immediate pre-patch commit. Same ROM images, same
machine, only the EXROM-chunk-mirroring fix differs.

## Running the base product (no patch needed)

```sh
make forth-boot
tools/make_exrom_placeholder.sh
cat build/forth_boot_rom0.bin build/stock_shaped_exrom.bin \
    > build/forth_boot_combined_24k.bin
zesarux --noconfigfile --machine TS2068 \
    --romfile build/forth_boot_combined_24k.bin
```

Any stock ZEsarUX 13.0 (or newer) build works. `--enableulaplus` is
optional — recommended if you want to try the `ULAPLUS`/`PALETTE`
words, not required for anything else.

## Running the graphics extension (patch required)

```sh
make forth-boot graphics-exrom
cat build/forth_boot_rom0.bin build/graphics_exrom.bin \
    > build/forth_boot_graphics_combined_24k.bin
zesarux --noconfigfile --machine TS2068 \
    --romfile build/forth_boot_graphics_combined_24k.bin
```

This requires ZEsarUX built with
[`../patches/0001-zesarux-mirror-ts2068-exrom.patch`](../patches/0001-zesarux-mirror-ts2068-exrom.patch)
— see [`../patches/README.md`](../patches/README.md) for the exact
build steps (clone upstream ZEsarUX, `git am` the patch, `configure`
and `make`). Without it, `RECT`, `POLYGON`, `POLYGON-FILL`,
`SPRITE-DEFINE`, `SPRITE-SHOW`, and `SPRITE-HIDE` will each silently do
nothing (the same magic/ABI mismatch guard every other word in this
project uses instead of crashing) — every other word still works fine.

## Reporting problems

Include the exact ZEsarUX version (`zesarux --version`) and whether it
has the EXROM-mirroring patch applied, the ROM files and their sizes,
and the smallest program that reproduces the issue.
