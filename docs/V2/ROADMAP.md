# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

Last updated 2026-10-30. Free bytes: HOME 1,758, EXROM 3,296.

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

## Now: FILL and CIRCLE to the EXROM — done (`docs/V2/milestones/O15.md`)

FILL and CIRCLE rebuilt in the EXROM (CIRCLE about 2.6× faster, FILL 38-66× on large areas and always complete), the
EXROM table at 16 slots, `make shapetest`, and the four defects found during the step fixed. HOME 816 → 1,758 B free.

## Next, in order

1. **Simplify to Leap-C's conventions.**
   - **Images:** the HOME ROM, the EXROM, the EXROM `.dck` for emulators, and at most one test build of the same
     sources (`-DTEST` hooks only). Gone: the cartridge build (owner: the TS-Pico dock is being changed for the Leap
     ROMs), both demo ROMs (Blackjack's Forth source kept in `demos/blackjack.fs`, rebuilt as a program at the end;
     the Gallery's source kept beside it), the ~60 smoke ROMs, the EXROM test ROMs and the bench ROMs.
   - **Tests:** `make test-fast` (a few minutes, while working) and `make test` (every suite on one emulator pool, at
     a milestone), one runner (`tools/run_tests.py`) over the production image. A boot suite replaces the smoke ROMs;
     word tests are Forth files under `tests/` with `\ expect:` lines; today's oracles become its suites; benchmarks
     are programs run on the product ROM. Every behaviour change ships with tests that fail without it.
   - **RAM:** one layout file (as `include/leapc_layout.inc`), no literal RAM address outside it, checked by
     `make check` (as `check_ram_layout.py`).
   - **Code:** each file trimmed to Leap-C's style: a short file header; each routine's header In / Out / Destroys;
     no narrative. Checked by assembling to identical bytes.
   - **Paperwork:** one report per milestone (`docs/V2/milestones/`: sizes, test counts, speeds); `budget.toml` with
     per-component budgets and ledger entries only for reallocations; this roadmap; a short HANDOFF.
2. **Space** (Leap-C's order when a component is over budget: shrink, move cold code to the EXROM, reallocate, ask).
   Move large, rarely called code from HOME into the EXROM and bring it back as space is made; the size pass.
   Candidates to measure: float printing and the transcendentals, tape words, word listings, sound, ULAplus, the
   printer. Limits: an EXROM call costs about 400 T; EXROM code cannot read the dictionary at `$A000-$BFFF`.
3. **Words and keys**: `[']`, `[CHAR]`, `\`, `[ ]`; the shared key lookup; the `1`/`l` glyphs; faster text drawing.
4. **Display speed**, and LINE on 16-bit coordinates with clipping (today it takes bytes: `-10 50 100 50 LINE`
   starts at x 246); it rebuilds `GFX_LINE`, whose cells POLYGON also uses through the EXROM.
5. **BREAK and timing**: BREAK in the interrupt routine, so long words can be stopped.
6. **Blackjack** rebuilt from its saved source as a program for the finished ROM.

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| LINE takes its coordinates as bytes (no 16-bit clipping) | O15 | Display speed (the `GFX_LINE` rebuild) |
| cartdiff fails about 3% of runs (harness timing, both builds) | cartdiff speed-up | goes with the cartridge build (Simplify) |
| Integer literals parse 2.5× slower since floats (shared 32-bit digit loop; a 16-bit fast path costs about 40 B) | Floats | Space (it needs the bytes) |
| The editor's ENTER at the bottom of the view takes 421k T (the store is scanned from the start per key) | Editor | Display speed |
| `INT_GET_FRAMES` (4 B) may be unreachable | Recover | Space (dead code) |

Fixed in O15: FILL's holes and off-screen seeds, CIRCLE's byte arguments, HIRES colours on the wrong scanlines, PLOT
and LINE below the screen (a RAM write after O15's layout), the 8th nested CATCH overlapping SPACES, LATEST/HERE
inside the data stack.
