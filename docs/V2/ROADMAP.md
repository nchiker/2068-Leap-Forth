# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

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
4. **Display speed.**
5. **BREAK and timing**: BREAK in the interrupt routine, so long words can be stopped.
6. **Blackjack** rebuilt from its saved source as a program for the finished ROM.

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| HIRES colours land on the wrong scanlines: attributes written linearly, the SCLD reads them in the bitmap's interleaved layout (`FILL_CIRCLE_SPEC.md` 9.1) | O15 oracle | now (FILL and CIRCLE step) |
| PLOT and LINE do not clip: y 192-255 indexes past the row table | Leap-C comparison | now (FILL and CIRCLE step) |
| The 8th nested CATCH overwrites SPACES' count and the printer line buffer (`CATCH_STACK` reaches `$8945`) | Floats | now (FILL and CIRCLE step) |
| A data stack about 1,020 cells deep overwrites LATEST and HERE before the stack check sees it | Floats | now (FILL and CIRCLE step) |
| FILL can leave holes (seed stack overflow); off-screen FILL seeds fill the screen; CIRCLE takes byte arguments | O15 spec | now (the rebuild) |
| cartdiff fails about 3% of runs (harness timing, both builds) | cartdiff speed-up | goes with the cartridge build (Simplify) |
| Integer literals parse 2.5× slower since floats (shared 32-bit digit loop; a 16-bit fast path costs about 40 B) | Floats | Space (it needs the bytes) |
| The editor's ENTER at the bottom of the view takes 421k T (the store is scanned from the start per key) | Editor | Display speed |
| `INT_GET_FRAMES` (4 B) may be unreachable | Recover | Space (dead code) |
