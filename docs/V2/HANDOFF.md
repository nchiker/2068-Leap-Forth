# Leap-Forth V2 — session handoff

Read this, then `docs/V2/ROADMAP.md` (done / next / known defects). Milestone reports: `docs/V2/milestones/`.

## Where things stand (2026-10-30)

- **master** `df391e6` (PR #8, step F, merged 2026-10-29).
- **`v2/step-o15-fill-circle`** (not pushed): step O15 complete, `docs/V2/milestones/O15.md`. The owner reviews it
  before the next session; open its PR when the owner asks, merge with a merge commit, run `make test` on master.
- **Free bytes:** HOME 1,758, EXROM 3,296 (floors equal them, `tools/budget.toml`).
- **Next:** ROADMAP step 1, *Simplify to Leap-C's conventions*: drop the cartridge build, the demo ROMs (sources kept
  in `demos/`), the smoke/test/bench ROMs; one test runner over the production image with tests under `tests/`; one
  RAM layout file; files trimmed to Leap-C's comment style; milestone reports instead of per-item ledger rows.

## How the owner wants the work done

- **Follow `~/2068-Leap-C`** (`CONTRIBUTING.md`, `project_plan.md` section 1) for tests, paperwork, code style, RAM
  layout and images. Check how Leap-C does a thing before designing a process, a test or a document.
- **Best solution for the language and its users**, not compatibility; but proportionate effort (a replacement ROM
  for a 40-year-old computer, not a rocket launch).
- **Fix problems in the session they are found**; anything pushed forward goes in the roadmap with its reason.
- **Rebuild, not drop-in:** study the Leap code a change touches before designing; every behaviour change ships with
  tests that fail without it.
- **No hardware:** never propose hardware checks; state the emulator limits (ZEsarUX, Fuse, TSRun).
- Commit at the end of each piece (Co-Authored-By line). Push and open PRs only when the owner asks; Claude merges,
  with merge commits.
- **Orchestration:** Haiku for inventories and running suites, Sonnet for well-specified code and tool changes
  (reviewed line by line); design and byte checks stay with the main session. Create worktrees yourself
  (`git worktree add -b <branch> <scratch>/wt HEAD`) and give agents the path.

## Facts that cost time to find

- **Never run `tools/run_realtape_test.sh`** or anything that opens an emulator window (Fuse needs an X display).
  The ZEsarUX on port 10330 belongs to another project.
- **ZEsarUX's tape autoload** types J "" ENTER when the PC reaches `$11F8` with the HOME ROM paged in. Data (the
  font) must cover `$11F8`: `rom/forth_boot.asm` ASSERTs it. When HOME shrinks and the ASSERT fails, move includes
  ahead of the font (O15 moved bank, dict, interp and control), never the ASSERT.
- **HIRES is the SCLD's 8×1 colour mode** (port `$FF` = `010`): the attribute of bitmap byte `$4000+n` is at
  `$6000+n`. The 512-column mode (`110`) was removed in M6.
- **The EXROM in the HOME build hides `$A000-$BFFF`** (dictionary RAM) while paged in. Its RAM cells live in
  `include/sysvars.inc`; some HOME cells are still hard-coded EQUs (`CURRENT_ATTR $87CB`, `LATEST $8608`,
  `CATCH_STACK $85D8`, `include/exrom_home_ram.inc`) until the single layout file exists: when a block of sysvars
  grows, everything after it moves (O15 kept block sizes and ASSERTed the next label).
- **Tools that set up machine state by address** must use the `.sym` names (floattest's CATCH frame broke when
  `CATCH_STACK` moved away from `CATCH_DEPTH`).
- `make` stops at the first ROM that fails to assemble: use `make -k` when some are broken on purpose.
- **z80sim** (`tools/z80sim/sim.py`) runs a routine from a scratch `.asm`; push `('HALT',)` and catch `Halt` for the
  outermost `ret`; supports `exx`. The stock ROM's interrupt routine keeps BC', DE', HL' (not AF').
- **Whole-flow tests carry their own expected values** (the Blackjack log in tapetest and smoke p53): after a change
  to RND or anything they replay, grep for the old values.
- **Suite times:** `make test` ~4 min, `edtest` ~3, `floattest` ~1-6, `shapetest` ~0.5, `cartdiff` ~2, `tapetest`
  ~5 (run it alone: under load it once dropped typed characters), `bench` ~3.
- **Ports:** test 10760 up, bench 10780, poweron 10820-10839, floattest 10840-10859, shapetest 10860-10879, ay_audio
  10880-10899, harness/edtest 10900-10919, cartdiff 10930-10949, tapetest 10960-10979, tapetol 10980-10999.
- **fusesave** counts 41 checks, or 42 when Fuse 1.9.1 aborts in its own `tape_write` (glibc assertion, depends on
  the recorded bytes) and the retry repeats the boot check.
- **Old-build comparisons:** `git worktree add --detach <scratch>/old <commit> && make -C <scratch>/old`, then
  `--build <scratch>/old/build` (shapetest, floattest, edtest) or `TAPETEST_OLD=`.
- **z80-skills scripts** (`~/z80-skills/skills/shrink-z80/scripts`): plain `python3`, not `-I`.
- **CI runs `make dist`** (no pandoc locally): `tools/package_dist.sh` heredocs expand `$`, so write hex as `\$A000`.
