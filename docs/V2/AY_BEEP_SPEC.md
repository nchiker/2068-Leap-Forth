# BEEP on the AY-3-8912: specification (audit step A, item O5)

Written before the code. Reference and oracle, not source: 2068-Leap `rom/v2_ay_beep.asm` and its study
(`docs/V2_AY_BEEP_STUDY.md`, commit `6493615`). Approved by the owner on 2026-10-28 (audit §10, decision 2).

## Contract

`BEEP ( n-semitones fduration -- )`: the stack effect and the units are unchanged. `n` is an integer
number of semitones from middle C (0 = middle C, 12 per octave); `fduration` is a float in seconds.

| | |
|---|---|
| Sound | AY channel A: tone period in R0/R1, R7 = tone A on and noise A off (other bits kept), R8 = 15 (fixed level, no envelope), then R8 = 0 when the note ends |
| Left behind | channel A silent; R0/R1 hold the note's period; R7 as above. Channels B and C, the noise period, the envelope and the I/O ports are untouched, so `SOUND`/`TONE` music on B or C carries on under a `BEEP`. A program that uses channel A must write its settings again after a `BEEP` |
| Period | `110250 / f`, `f = 261.63 * 2^(n/12)` (AY clock 1.764 MHz = CPU 3.528 MHz / 2; tone = clock / 16 / period), rounded to the nearest. From a 12-entry table of `16 * 110250 / f` for the notes of the octave starting at A0 (n = -39, 27.5 Hz), shifted right by the octave with the last bit rounding |
| Pitch range | n = -60..69 (as the stock ROM). The 12-bit period cannot go below 27.5 Hz: n = -60..-40 play n = -39 (A0). Outside -60..69 nothing happens (no sound, no wait), the project's convention for out-of-range input (see `core/sound.asm`) |
| Duration | `seconds * 60` display frames (the TS2068's 60 Hz), rounded to the nearest frame, waited with `HALT`. Under half a frame, or negative: nothing. Above 32,768 frames (546 s) it plays 32,768 |
| Interrupts | on. `BEEP` executes `EI` first (the old `BEEP` ended with `EI`, so a program never saw interrupts left off), the frame interrupt keeps counting `FRAMES` and the keyboard keeps being scanned. A program that has switched the frame interrupt off waits forever (as `PAUSE`-style waits do) |
| No start-of-note sync | no `HALT` before the first frame: notes played one after another follow each other with no gap; an isolated note's first frame is partial (n-1 to n frames) |
| Placement | HOME (the cartridge build cannot page the EXROM until step R1) |
| RAM | none (stack only; the old `BEEP_*` cells at `$8856-$885E` are released) |

Not replicated, as before: fractional semitones (the pitch is an integer from the data stack).

## Why this changes behaviour

The old `BEEP` toggled the loudspeaker bit of port `$FE` in a busy loop with interrupts disabled for the whole
note, and needed the float calculator for the pitch (about 440 bytes plus `SOUND_BEEP`'s 55). The AY version is
audible through the AY output, not the beeper; it leaves interrupts and the keyboard running; and durations are
whole frames. The loudspeaker code is not deleted: `kernel/sound/sound.asm` (`SOUND_BEEP`) and
`core/rawbeep.asm` stay in the tree as an optional package (the raw-units word, still tested by
`rom/forth_smoke_p5.asm`), left out of the product ROMs.

## Oracle (`rom/test_ay_beep.asm`)

Independent of the table in the code, it checks against the formula:
1. every n in -60..69: R0/R1 after `n BEEP` are within 1 count of `round(110250 / (261.6256 * 2^(max(n,-39)/12)))`,
   R8 = 0 afterwards, R7 bit 0 = 0 and bit 3 = 1;
2. frames: `FRAMES` advances by exactly `round(60 * seconds)` for 0.5 s, 0.1 s and 1/60 s, and by 0 for 0 s,
   0.001 s and a negative duration;
3. out of range (`70 BEEP`, `-61 BEEP`): R0/R1 unchanged, no wait;
4. R7 bits other than 0 and 3, and channels B and C (R2-R5, R9, R10), survive a `BEEP`;
5. interrupts are enabled on return, the data and float stacks are balanced.
