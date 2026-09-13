# LROS cartridge build (EXPERIMENTAL, mostly superseded)

## Superseded by the real cartridge build

`rom/forth_boot.asm` now has its own `-DCARTRIDGE` build (`make
forth-boot-cart`, from PR #1) that does everything this file's stub set
out to prove — and does it with the **full 143-word dictionary**, not a
border-cycle smoke test. It's confirmed booting to a live Forth prompt
under both Fuse (`--dock`) and stock, unpatched ZEsarUX
(`smartload`/`hard-reset-cpu`), using the genuine factory TS2068 ROM —
see the README's "Or leave the stock ROM in place" section. **Use that
for anything real** — running on TS-Pico, real hardware, or an
emulator's DOCK slot. The rest of this file is now historical: the
header-format reference below is still accurate and worth keeping, but
`rom/forth_lros.asm` itself has no remaining purpose the real cartridge
build doesn't already cover better.

## What this was

`rom/forth_lros.asm` was a proof-of-concept boot stub for the TS2068
**LROS** (Language ROM-Oriented Software) cartridge convention — the same
mechanism Timex's own plans for Logo and Pascal cartridges would have
used. It was a **separate, additive distribution channel**, not a
replacement for `rom/forth_boot.asm`:

| | `rom/forth_boot.asm` (`-DCARTRIDGE`) | `rom/forth_lros.asm` |
|---|---|---|
| Loading mechanism | DOCK cartridge port | DOCK cartridge port |
| Owns `$0000`? | No — stock Home ROM boots first, hands off | No — stock Home ROM boots first, hands off |
| Status | The real product, confirmed booting under Fuse and ZEsarUX with the genuine stock ROM | Boot-stub proof of concept, **not yet run on real hardware or verified against a real DOCK/TS-Pico loader** |
| Size | 16K (DOCK chunks 0-1) | One 8K DOCK chunk (chunk 0) |
| Content | Full 143-word dictionary | Border-cycle smoke test only (same role as `rom/main.asm`'s own Milestone 0) |

## Why it's a stub, not the full interpreter

The full 2068-Leap-Forth dictionary is a 24K image. A single LROS chunk-0 image
is 8K. Those don't fit together without either (a) chaining multiple DOCK
chunks under one LROS cartridge, or (b) trimming the dictionary for this
target specifically — neither has been designed yet. This stub exists
only to prove the **header format and handoff entry point** are correct,
the same incremental, one-thing-at-a-time approach this project used for
its own `rom/main.asm` before any Forth-specific code existed. Growing it
into the real interpreter is open follow-up work — see "Open work" below.

## Source of the format

The 5-byte in-ROM LROS header and the 9-byte DCK bank-header container
format used here were originally sourced from published TS2068
cartridge/DCK format documentation — cross-checked across two
independent write-ups (a community TS2068 hardware reference and a
TS2068 cartridge-development skill/tooling collection) that agree on
the same byte layout. Neither was an official Timex specification at
the time. PR #1's own `-DCARTRIDGE` build cites the **TS2068 Technical
Manual §5.1.1 directly** for the same header — a better-sourced
confirmation than either original write-up, and now the one to trust.

LROS header (chunk 0, offset $0000):

| Offset | Meaning |
|---:|---|
| 0 | unused |
| 1 | cartridge type: `$01` = LROS |
| 2-3 | entry address, little-endian |
| 4 | chunk-in-use flags, **LOW-active**: bit N = 0 means chunk N is supplied by the cartridge, bit N = 1 means chunk N stays Home. Bit 3 must stay 1 (chunk 3 stays Home) so the stock OS's own `GOTO_BANK` handoff code, which runs from Home chunk 3, can finish running. This project's own stub sets only bit 3 (`%00001000`), which under this polarity claims chunks 0, 1, 2, 4-7 are all cartridge-supplied — inconsistent with the stub actually populating only chunk 0. `rom/forth_boot.asm`'s `-DCARTRIDGE` build gets this right: `%11111100` (chunks 0-1 cartridge-supplied, matching its own 16K image, 2-7 stay Home) — one more reason to prefer it over this stub. |

DCK bank-header container (9 bytes, precedes the chunk image(s)):

| Byte | Meaning |
|---:|---|
| 0 | bank id (`0` = DOCK) |
| 1-8 | one descriptor per 8K chunk 0-7: `0`=absent, `1`=uninitialized RAM, `2`=ROM (8192-byte image follows), `3`=initialized RAM (8192-byte image follows) |

This project's stub only populates chunk 0, so `tools/pack_dck.sh` always
emits `0,2,0,0,0,0,0,0,0` followed by one 8192-byte image.

## Build and package

```sh
make forth-lros
tools/pack_dck.sh build/forth_lros_chunk0.bin build/forth_lros.dck
```

`build/forth_lros_chunk0.bin` is the raw 8192-byte chunk-0 ROM image
(usable directly on hardware/tools that want a flat physical binary).
`build/forth_lros.dck` is the same image wrapped for Fuse's DOCK-cartridge
loading. Fuse's `--dock` flag genuinely works (confirmed this session,
using `rom/forth_boot.asm`'s `-DCARTRIDGE` build, not this stub) — it
just needs the genuine stock TS2068 ROM configured too (`--rom-ts2068-0
<stock rom>`), since `--dock` only supplies the cartridge, not the
Home ROM that boots first and hands off to it.

## Open work

- **Not run on real hardware.** No TS-Pico or physical DOCK cartridge was
  available to test against.
- **The outer 9-byte DCK container is confirmed by three independent
  implementations; the inner 5-byte LROS header only by one.** These
  are two different claims, and it matters which tool checked which:
  TS-Pico's real firmware (`tspico.py`'s `DCK_IMAGE()`, see
  `docs/ts_pico_setup.md`), TSRun's real `dock.js` (see the
  `tsrun-headless` skill), and EightyOne 1.41 (real-user-confirmed on
  the sibling `ts2068rom` project, bank id `$FE`/EXROM though, a
  different slot — see `docs/eightyone_setup.md`) all parse the outer
  bank-id-plus-chunk-descriptors container the same way. None of them
  interpret the *inner* LROS-specific header fields (type/entry/chunk
  flags) — that's a convention the OS reads, not something these
  DCK-container parsers care about. Only `inspect_dck.py` (from the
  locally vendored, not redistributed — see `.gitignore`
  — `ts2068-cartridge-development` skill) actually decodes it, and it
  parsed `build/forth_lros.dck` correctly: `"kind": "LROS"`, `"entry":
  5` (matching `COLD_START` sitting right after the 5-byte header), and
  `"chunk3_startup_safe": true`. So: outer container, three-way
  confirmed; inner LROS semantics, one tool's read of it — plus now
  PR #1's own Technical-Manual-cited implementation, which actually
  boots (see "Superseded" above). None of this runs real TS2068
  hardware or a physical DOCK connector.
- **The handoff-state assumption is unverified.** `COLD_START` assumes
  the stock ROM has already set up a live stack and doesn't touch `SP` —
  reasonable per the sourced convention (also independently stated by
  the vendored cartridge-development skill's own `aros-and-basic.md`:
  "Keep header bit 3 set so OS chunk-3 transfer code and stack remain
  available during handoff"), but not proven against real handoff
  behaviour.
- **The full dictionary now has a path — use `build/forth_boot.dck`,
  not this stub's `build/forth_lros.dck`.** PR #1's `-DCARTRIDGE` build
  is exactly this: the same LROS/DOCK mechanism, but with the complete
  143-word dictionary and confirmed booting under two emulators. This
  stub's own "grow it into the real interpreter" plan (chaining DOCK
  chunks, or trimming the dictionary) turned out to be unnecessary —
  the real dictionary already fits in 16K (chunks 0-1), the same size
  as the Home ROM.
- **TS-Pico should be able to load `build/forth_boot.dck` today** —
  its DOCK-slot loading (`LOAD "tpi:forth_boot.dck"`) is confirmed
  compatible with this file format at the structural level (see
  `docs/ts_pico_setup.md`), and the file itself now boots on two real
  emulators. What's still unconfirmed is real hardware itself: TS-Pico
  handoff behavior and DOCK-bank timing/activation quirks. The graphics
  extension still can't reach TS-Pico either way — it pages the EXROM
  bank, which TS-Pico has no way to substitute.

Treat everything above the "Source of the format" citations as reviewed-
by-eye only, in keeping with this project's own standard for hardware
claims (see `PROJECT_PLAN.md`'s repeated "hardware-confirmed, not
guessed" bar) — this file does not meet that bar yet.
