# STICK — port A an input, a connector selected, fire for both sticks: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/stick-fix` from master (`50170f2`). The Leap IDE reported
that Leap V2's `STICK` reads the AY's port A while it is an output; Leap V2 fixed it in v2.1.1 (`~/2068-Leap`,
branch `maint/v2.1.1`, `ec2ee7e`; its answers: `~/Projects/Leap-IDE/docs/requests/LEAP_V2_ANSWERS.md` section 1).
Forth's `STICK_READ` (`kernel/io/io.asm`) was the same V1 routine, with the same two faults.

## 1. The faults

- **Direction.** Register 7 bits 7 and 6 set the direction of the AY's I/O ports B and A (the AY-3-8910/8912 data
  sheet: "determined by the state of bits B7 and B6 of R7"; 1 = output). After boot the mixer is `$F8`, and `MIXER`,
  `SOUND` and the boot sound leave port A an output. A read of register 14 then gives the port's latch on TSRun and
  the pins on ZEsarUX and Fuse; the data sheet does not say which. It recommends input mode for reading switches.
- **No connector selected.** The TS2068 enables joystick 1 while A8 is high during the read and joystick 2 while A9
  is high; the stock ROM's `STICK` (HOME ROM, about `$2902`) loads B with the stick number before `in a,(c)`.
  `STICK_READ` left B as it was. TSRun models this (`machine.js`, `readJoysticks`): with B = 0 no stick is read at all.
- **The result** was the stock ROM's two questions folded into one argument: stick 1 the directions, "stick 2" the
  fire line of whichever stick was enabled (none). On TSRun `2 STICK .` printed 1 with nothing connected (the latch's
  bit 7), and no direction or fire button was ever seen.

## 2. What was built

`STICK_READ`, as Leap V2's v2.1.1: select register 7, read it, clear bit 6, write it back with B = 0 (no stick
enabled while writing); select register 14, B = *device*, read, invert. The result is 0-31 for both sticks: bits 0-3
the directions (all four at once reads 0, as before), +16 while fire (bit 7) is pressed. Bit 6 stays clear afterwards:
the tones and noise use bits 0-5 only, and `BEEP` changes only channel A's bits. *device* is still not checked (its
low byte goes to A8-A15).

The manual: `STICK` (the result, the direction, the selection, the change, the hardware caveat), `MIXER` (bits 6 and
7 are the ports' directions; any value is safe, `STICK` clears bit 6 itself), `SOUND` (register 7's note).

## 3. Tests

- `tests/io/keys.fs` and the manual's `STICK` example: `248 MIXER  1 STICK DROP  7 AY@ .` gives 184 (bit 6 cleared);
  on master it gives 248 (ZEsarUX). A second line does the same with `255 MIXER` and stick 2.
- A new suite, `tsrun` (`tools/tsruntest.mjs`, `make test`): the release images on TSRun's core with each joystick's
  contacts set, after the mixer is set to `$F8`. Nine cases: nothing pressed, a direction or fire on each stick seen
  only by its own `STICK`, all four directions at once. On master 3 of 9 pass (`2 STICK` gives 1 whatever is
  pressed; stick 1's direction and fire read 0). Skipped, and said so, without node or `~/TSRun`.

## 4. Sizes

| Image | Before | After |
|---|---:|---:|
| HOME free | 1,924 B | 1,915 B (+9 B, ledger entry `kernel`) |
| EXROM free | 3,136 B | 3,136 B |
| The cartridge's HOME image free | 1,751 B | 1,742 B |

Emulators only (ZEsarUX 13.0, TSRun). The selection by A8/A9 is TSRun's model and the stock ROM's code, not a
schematic; no hardware.
