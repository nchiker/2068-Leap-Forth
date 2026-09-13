# TS-Pico setup

**No TS-Pico was available to test this against — everything below is
sourced directly from the TS-Pico project's own public firmware source
and wiki (`github.com/timex-sinclair-projects/TS-Pico`, its `Beta`
branch `src/TS/tspico.py`, and its wiki), not guessed.** It corrects an
assumption in this project's own earlier docs, and answers the
"can an LROS image replace both the Home ROM and EXROM?" question
directly: **no** — see "Why not LROS for everything" below.

## The two independent slots TS-Pico actually has

TS-Pico's firmware exposes exactly two kinds of loadable image, each
its own address space, selected independently:

| TS-Pico concept | Command | What it replaces | Size | Format |
|---|---|---|---|---|
| **ROM slot** (`ROM_SLOT`) | `LOAD "tpi:name.rom"` then `SAVE "tpi:memboot" CODE mem,slot` | TS2068 **Home ROM** ($0000-$3FFF) | 16K | Raw flat binary — no header |
| **DCK slot** (`DCK_SLOT`) | `LOAD "tpi:name.dck"` then `SAVE "tpi:memdock" CODE mem,slot` | TS2068 **DOCK** cartridge bank | up to 64K (8×8K chunks) | 9-byte chunk-descriptor header + chunk data — the same format this project's own `tools/pack_dck.sh` and `tools/make_eightyone_exrom_dck.sh` already produce |

**There is no third "EXROM slot."** TS-Pico's firmware source has no
EXROM-specific handling anywhere — confirmed by searching the actual
`tspico.py` source, not inferred. The TS2068's onboard EXROM chip stays
exactly what it always was; TS-Pico can only substitute the Home ROM
and/or the DOCK bank.

## What this means for 2068-Leap-Forth

Two independent ways to get the full base dictionary onto TS-Pico
today, both using files this project already builds:

- **ROM slot — replaces the Home ROM.** Plain 16K, exactly
  `build/forth_boot_rom0.bin`. Simplest, but it's a real replacement
  (Flash slots 0/1 are write-protected as a safety default, and a bad
  switch can hang the machine mid-boot — see "Loading the base
  product" below).
- **DCK slot — a DOCK cartridge, non-destructive.** `make
  forth-boot-cart` (from PR #1) builds `build/forth_boot.dck`: the
  same full 143-word dictionary, but as an LROS/DOCK cartridge that
  leaves the stock ROM untouched — the machine boots normally and
  hands off to it, the same mechanism real Timex Logo/Pascal cartridges
  would have used. This is confirmed booting under both Fuse and stock
  ZEsarUX with the genuine factory ROM (see `docs/lros_cartridge.md`);
  the file format is confirmed structurally compatible with TS-Pico's
  own DCK parser, but TS-Pico hardware itself hasn't been tried yet —
  see "Loading the full dictionary as a DOCK cartridge" below.

Either way, **the graphics extension
(`RECT`/`POLYGON`/`POLYGON-FILL`/`SPRITE-DEFINE`/`SPRITE-SHOW`/`SPRITE-HIDE`)
cannot currently reach a real TS-Pico.** This project's own graphics
dispatch pages the **EXROM** bank (chunk 5) — a bank TS-Pico has no way
to substitute, regardless of which slot the rest of the dictionary uses.
Making these six words work on TS-Pico would need the graphics code
retargeted to run from the **DOCK** bank instead, which is real,
unstarted follow-up work, not a docs gap.

## Why not LROS for everything

LROS ("Language ROM-Oriented Software") is a convention for code
running in the **DOCK** bank: the stock (or replacement) Home ROM
always boots and initializes the hardware first, then hands off
execution to the LROS image, which is "in total control" of the
machine *from that point on* — but it never physically occupies the
Home ROM or EXROM address space itself. It's a third, separate bank,
not a substitute for the other two. This matches what
`docs/lros_cartridge.md` already documented; the research here confirms
that model is correct, rather than finding it incomplete.

The Home-ROM-replacement path (`.rom` → `ROM_SLOT`) is a completely
independent TS-Pico mechanism, unrelated to LROS, and it's the one that
already does what you want for the full non-graphics 2068-Leap-Forth
system today.

## Loading the base product

```sh
make forth-boot
```

1. Copy `build/forth_boot_rom0.bin` to the TS-Pico's SD card (any
   directory TS-Pico can see).
2. On the TS2068: `LOAD "tpi:forth_boot_rom0.bin"` — TS-Pico stages the
   image and asks whether to keep it in SRAM or Flash, and which slot.
   **Flash slots 0 and 1 are write-protected** (TS-Pico's own safety
   default); use SRAM unless you specifically want it to survive a
   power cycle.
3. To activate immediately without a reboot:
   `SAVE "tpi:memboot" CODE mem,slot` — `mem` is `1` for SRAM or `2` for
   Flash, `slot` is `0`-`15` (whichever you picked in step 2).

TS-Pico's own documentation notes the ROM can occasionally hang the
machine mid-switch, with an automatic fallback to the stock ROM on the
next boot if that happens — a TS Reset (or power cycle) recovers.

## Loading the full dictionary as a DOCK cartridge

```sh
make forth-boot-cart
```

This builds `build/forth_boot.dck` — the complete 143-word dictionary
as an LROS/DOCK cartridge, non-destructive to the stock ROM. Confirmed
booting to a live Forth prompt under Fuse and stock ZEsarUX with the
genuine factory TS2068 ROM (see `docs/lros_cartridge.md`) — TS-Pico
hardware itself is the one thing this hasn't been tried against yet.

1. Copy `build/forth_boot.dck` to the SD card.
2. `LOAD "tpi:forth_boot.dck"`, then follow the prompts (SRAM/Flash,
   slot) or `SAVE "tpi:memdock" CODE mem,slot` afterward (`mem` 1=SRAM,
   2=Flash, `slot` an even number 0-14).
3. Per TS-Pico's own documentation, some cartridges activate
   automatically, some need `OUT 244,3`, and some need a physical
   reset — this project has not yet confirmed which applies to
   `forth_boot.dck` on real hardware.

The earlier experimental boot stub (`rom/forth_lros.asm`,
`build/forth_lros.dck`) is now superseded by this — same mechanism, but
a border-cycle smoke test instead of the real dictionary. See
`docs/lros_cartridge.md` for why it's kept around (mainly as header-
format reference) and what's still open about real-hardware handoff.

## Sources

- `github.com/timex-sinclair-projects/TS-Pico` — `commands.md`
  (user-facing command reference: `.rom`/`.dck`/`.tap` loading,
  `MEMBOOT`/`MEMDOCK`)
- `github.com/timex-sinclair-projects/TS-Pico`, `Beta` branch,
  `src/TS/tspico.py` — firmware source (`ROM_SLOT`/`DCK_SLOT`
  handling, `DCK_IMAGE()` header parsing, `MEMBOOT`/`MEMDOCK`)
- `github.com/timex-sinclair-projects/TS-Pico/wiki` —
  `ZX-Spectrum-Mode.md` (confirms port `$F4`/244 bank switching and
  the DCK/ROM slot model), `Exploring-the-TS-Pico.md`,
  `Using-the-TS-Pico.md`
