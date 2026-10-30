# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); a few basic boot smoke ROMs, everything else in test harnesses.

Last updated 2026-10-29. Free bytes: HOME 1,220, EXROM 3,984.

## Done

| Step | What it did |
|---|---|
| Tests and guards | Test tools, byte budgets per ROM image, power-on RAM test, licence notice |
| Recover | Dead code removed, small size savings in HOME |
| AY BEEP | BEEP plays on the AY sound chip; HOME bytes freed |
| Cartridge paging | The DOCK cartridge build could call the EXROM (being removed, see below) |
| Tape storage | SAVE/LOAD rebuilt: SAVE-TEXT, LOAD-TEXT, VERIFY-TEXT, libraries |
| Leap-C comparison | Read-only audit of what Leap-C does better; produced the items scheduled below |
| RST stack calls | Data-stack push/pop through RST vectors: about 500 B of HOME back, faster |
| Console and editor | New console redraw; full-screen editor (`EDIT`) in the EXROM; the line store |
| 64-column mode removed | 64COL and its code paths gone (HIRES colour mode kept) |
| Floats | 5-byte floats, 22 new float words, error messages, faster `*` `/` `MOD`, new RND |

## Now: FILL and CIRCLE to the EXROM (`FILL_CIRCLE_SPEC.md`)

| Part | State |
|---|---|
| Spec and owner decisions | done |
| Oracle (`make shapetest`) and cartdiff cases, run on the old build | done |
| EXROM service table 8 → 16 slots | done |
| CIRCLE rebuilt in the EXROM (16-bit, clipped, about 2.6× faster; HOME +404 B) | done |
| FILL rebuilt in the EXROM (byte-level, always complete, tens of times faster) | in progress |
| Defects found during this step, fixed in it (below) | after FILL |
| Docs | last |

## Next, in order

1. **Drop the cartridge build** (owner, 2026-10-29: the TS-Pico dock is being changed to work with the Leap ROMs).
   Ship the HOME ROM and the EXROM, and the EXROM as a `.dck` for emulators, as Leap-C does. Goes: the `-DCARTRIDGE`
   builds, the cartridge paging variant, the shared-identity rule, `make cartdiff`, the demo cartridges.
2. **Space.** Move large, rarely called code from HOME into the EXROM (moved back as space is made), and the size
   pass over HOME. Candidates to measure first: float printing and the transcendentals, tape words, word listings,
   sound, ULAplus, the printer. Limits: each EXROM call costs about 400 T (whole words, not per-character paths);
   EXROM code cannot read the dictionary at `$A000-$BFFF` in the HOME build.
3. **Tests, on Leap-C's model** (the owner's direction from the start of V2; `~/2068-Leap-C` `tools/run_tests.py`):
   `make test` is one runner with suites on one pool of emulators, all against the production image (plus, only if a
   hook is needed, one test build of the same sources). Boot suite: the image reaches the prompt with its memory
   layout; it replaces the ~60 smoke ROMs and the EXROM test ROMs. Word tests are Forth source files under `tests/`
   with `\ expect:` lines (output text, stack, screen) checked against host models; today's separate oracles
   (`floattest`, `shapetest`, `edtest`, `harness`, `tapetest`, `poweron`) become suites of that runner. A coverage
   report of the ROM as in Leap-C's `romcov.py`. `make check` stays the static checks.
4. **Words and keys**: `[']`, `[CHAR]`, `\`, `[ ]`; the shared key lookup; the `1`/`l` glyphs; faster text drawing.
5. **Display speed.**
6. **BREAK and timing**: BREAK in the interrupt routine, so long words can be stopped.

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| HIRES colours land on the wrong scanlines: attributes written linearly, the SCLD reads them in the bitmap's interleaved layout (`FILL_CIRCLE_SPEC.md` 9.1) | O15 oracle | now (FILL and CIRCLE step) |
| PLOT and LINE do not clip: y 192-255 indexes past the row table | Leap-C comparison | now (FILL and CIRCLE step) |
| The 8th nested CATCH overwrites SPACES' count and the printer line buffer (`CATCH_STACK` reaches `$8945`) | Floats | now (FILL and CIRCLE step) |
| A data stack about 1,020 cells deep overwrites LATEST and HERE before the stack check sees it | Floats | now (FILL and CIRCLE step) |
| FILL can leave holes (seed stack overflow); off-screen FILL seeds fill the screen; CIRCLE takes byte arguments | O15 spec | now (the rebuild) |
| cartdiff fails about 3% of runs (harness timing, both builds) | cartdiff speed-up | goes with the cartridge build (step 1) |
| Integer literals parse 2.5× slower since floats (shared 32-bit digit loop; a 16-bit fast path costs about 40 B) | Floats | Space (it needs the bytes) |
| The editor's ENTER at the bottom of the view takes 421k T (the store is scanned from the start per key) | Editor | Display speed |
| `INT_GET_FRAMES` (4 B) may be unreachable | Recover | Space (dead code) |
