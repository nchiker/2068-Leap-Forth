# LROS cartridge build (EXPERIMENTAL)

## What this is

`rom/forth_lros.asm` is a proof-of-concept boot stub for the TS2068
**LROS** (Language ROM-Oriented Software) cartridge convention — the same
mechanism Timex's own plans for Logo and Pascal cartridges would have
used. It is a **separate, additive distribution channel**, not a
replacement for `rom/forth_boot.asm`:

| | `rom/forth_boot.asm` | `rom/forth_lros.asm` |
|---|---|---|
| Loading mechanism | Home ROM replacement (`--rom-ts2068-0`, or flashes over U19) | DOCK cartridge port |
| Owns `$0000`? | Yes, entirely — it *is* the system ROM | No — stock Home ROM boots first, hands off |
| Status | The real product, hardware/emulator-confirmed (see `PROJECT_PLAN.md`) | Boot-stub proof of concept, **not yet run on real hardware or verified against a real DOCK/TS-Pico loader** |
| Size | 24K (16K Home + 8K EXROM) | One 8K DOCK chunk (chunk 0) |
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
format used here are sourced from published TS2068 cartridge/DCK format
documentation — cross-checked across two independent write-ups (a
community TS2068 hardware reference and a TS2068 cartridge-development
skill/tooling collection) that agree on the same byte layout. Neither
source is an official Timex specification; **this format has not been
independently confirmed against real hardware or a real TS-Pico unit**.

LROS header (chunk 0, offset $0000):

| Offset | Meaning |
|---:|---|
| 0 | unused |
| 1 | cartridge type: `$01` = LROS |
| 2-3 | entry address, little-endian |
| 4 | chunk-in-use flags (bit 3 must stay set — keeps the stock OS's own chunk-3 transfer/stack code available during handoff) |

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
loading, if/when a locally available Fuse build supports it (see "Open
work" — this could not be confirmed in this environment).

## Open work

- **Not run on real hardware.** No TS-Pico or physical DOCK cartridge was
  available to test against.
- **Not confirmed in an emulator either.** The Fuse 1.9.1 build available
  in this environment does not advertise a DOCK/`.dck`-loading option in
  its own `--help` output (unlike the documented `--rom-ts2068-0`/`-1`
  flags `forth_boot.asm` relies on), and this environment has no display
  to drive it interactively. ZEsarUX (already used elsewhere in this
  project for independent hardware cross-checks) may support DOCK/DCK
  loading — worth checking before trusting this format further.
  Note: EightyOne 1.41 IS confirmed (by a real user, on the sibling
  `ts2068rom` project) to load a `.dck`-wrapped cartridge — see
  `docs/eightyone_setup.md`. That confirms the general 9-byte-header +
  chunk-image DCK container mechanics used by `tools/pack_dck.sh` are
  real and correctly understood. It does NOT confirm the LROS-specific
  bank id (`$0`, DOCK) or in-ROM 5-byte header used here — the confirmed
  case uses bank id `$FE` (EXROM) instead, a different cartridge slot.
- **The handoff-state assumption is unverified.** `COLD_START` assumes
  the stock ROM has already set up a live stack and doesn't touch `SP` —
  reasonable per the sourced convention, but not proven against real
  handoff behaviour.
- **No path yet for the full dictionary.** See "Why it's a stub" above.
- **TS-Pico's own expected image format is still unconfirmed.** No
  published TS-Pico format spec was found; this stub assumes it accepts
  either the flat 8192-byte chunk-0 image or a standard DCK file, but
  that's an assumption, not a confirmed fact.

Treat everything above the "Source of the format" citations as reviewed-
by-eye only, in keeping with this project's own standard for hardware
claims (see `PROJECT_PLAN.md`'s repeated "hardware-confirmed, not
guessed" bar) — this file does not meet that bar yet.
