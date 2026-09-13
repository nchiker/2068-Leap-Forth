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

- **The base product (143-word dictionary, everything except the six
  Phase 65 graphics words) is fully usable today**, via the ROM slot —
  it's a plain 16K Home ROM replacement, exactly what
  `build/forth_boot_rom0.bin` already is. No LROS, no DOCK cartridge,
  no new file needed.
- **The graphics extension (`RECT`/`POLYGON`/`POLYGON-FILL`/
  `SPRITE-DEFINE`/`SPRITE-SHOW`/`SPRITE-HIDE`) cannot currently reach a
  real TS-Pico.** This project's own graphics dispatch pages the
  **EXROM** bank (chunk 5) — a bank TS-Pico has no way to substitute.
  Making these six words work on TS-Pico would need the graphics code
  retargeted to run from the **DOCK** bank instead, which is real,
  unstarted follow-up work, not a docs gap.
- **The experimental LROS/DOCK boot stub (`rom/forth_lros.asm`,
  `docs/lros_cartridge.md`) is a DOCK-slot payload**, loadable in
  principle via `LOAD "tpi:forth_lros.dck"` — its file *format* is now
  confirmed to match what TS-Pico's firmware actually parses (the same
  9-byte header, chunk-by-chunk), which was an open question before
  this research. What's still unconfirmed is everything past the file
  format: real hardware handoff behavior, and TS-Pico's own DOCK-bank
  timing/activation quirks — see `docs/lros_cartridge.md`'s own "Open
  work" section, still open.

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

## Loading the experimental LROS/DOCK stub

```sh
make forth-lros
tools/pack_dck.sh build/forth_lros_chunk0.bin build/forth_lros.dck
```

1. Copy `build/forth_lros.dck` to the SD card.
2. `LOAD "tpi:forth_lros.dck"`, then follow the prompts (SRAM/Flash,
   slot) or `SAVE "tpi:memdock" CODE mem,slot` afterward (`mem` 1=SRAM,
   2=Flash, `slot` an even number 0-14).
3. Per TS-Pico's own documentation, some cartridges activate
   automatically, some need `OUT 244,3`, and some need a physical
   reset — this project has not yet confirmed which applies to
   `forth_lros.dck` on real hardware.

Remember this is the **border-cycle smoke-test stub**, not the full
Forth dictionary — see `docs/lros_cartridge.md` for what it actually
proves and what's still open.

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
