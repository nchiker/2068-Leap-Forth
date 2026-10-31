# Leap-Forth V2 — session handoff

Read this, then `docs/V2/ROADMAP.md` (done / next / known defects) and `CONTRIBUTING.md` (build, test, rules). Milestone
reports: `docs/V2/milestones/`.

## Where things stand (2026-10-31)

- **Branch `v2/step-display-look`** (from master `85d727a`, PR #12 Words and keys merged; `make test` passed on master
  first): step Display look is complete (`docs/V2/milestones/Display_look.md`); `make test`, `make check` and
  `make repro` pass on it. Not pushed; no PR yet: push and open it only when the owner asks.
- **Decided (2026-10-31):** the screen follows Leap V2: black on white, white border, no banner, the version
  `2068 FORTH V2.0` on the status bar of row 23 until the first key (the owner's option A), `EDIT`'s status bar, Leap
  V2's chime C. Kept as Forth's: errors printed in the console, the colours a program sets survive (no reset on
  return), no keyword bolding, the chime not stopped by BREAK. Nothing moves to the EXROM now; Space report section 5
  is the measured list for when a step runs short.
- **Free bytes:** HOME 2,232, EXROM 3,272; per component in `budget.toml` (`make budget`), per routine
  `make inventory`. The dictionary starts at `$9100` (`FREE` 16,128 at power-on).
- **Next:** ROADMAP step 1, *Display speed* (and LINE on 16-bit coordinates), then *BREAK and timing*.

## How the owner wants the work done

- **Follow `~/2068-Leap-C`** for tests, paperwork, code style, RAM layout and images: check how Leap-C does a thing
  before designing a process, a test or a document.
- **Best solution for the language and its users**, not compatibility; proportionate effort (a replacement ROM for a
  40-year-old computer, not a rocket launch).
- **Fix problems in the session they are found**; anything pushed forward goes in the roadmap with its reason.
- **Every behaviour change ships with tests that fail without it** (a line in `tests/` with `\ expect:`, or a suite
  case); check the failure on the old build (a worktree, below).
- **Budgets:** a component over budget: shrink, move cold code to the EXROM, reallocate with a ledger entry in
  `budget.toml`, then ask.
- **No hardware:** never propose hardware checks; state the emulator limits (ZEsarUX, Fuse, TSRun).
- Commit at the end of each piece (Co-Authored-By line). Push and open PRs only when the owner asks; Claude merges,
  with merge commits.
- **Orchestration:** Haiku for inventories and running suites, Sonnet for well-specified code, tool and doc changes
  (reviewed), design and byte checks in the main session. Parallel agents each get their own worktree
  (`git worktree add -b <branch> <scratch>/wt-x HEAD`) and disjoint files; identical bytes is the gate for a trim.

## Facts that cost time to find

- **Never run anything that opens an emulator window** (Fuse needs an X display). The ZEsarUX on port 10330 belongs to
  another project.
- **Ports:** run_tests' pool 10760-10779 (two agents can split it: `--port 10760 --workers 4`, `--port 10770`),
  poweron 10820-10839, floattest 10840-10859, shapetest 10860-10879, ay_audio 10880-10899, fharness self-test
  10900-10919, tapetest 10960-10979, tapetol 10980-10999.
- **Suite times:** `make test` ~9 min (pool ~3, poweron 0.5, tape ~5.5), `make test-fast` ~2 min,
  `python3 tools/forthtest.py` (the Forth tests alone) ~30 s.
- **The boot screen:** output starts on row 0; row 23 holds the version on the status bar (`fh.STATUS_BAR`, the cursor
  `$B8` in its column 0) from the boot snapshot until the first key (`VERSION_UP`; `EDITOR_REDRAW` clears it), so a
  tool that reads row 23 before typing sees `  2068 FORTH V2.0`. Output rows are 0-22 (`floattest.nonblank_rows`). The
  version text is `include/forth_version.inc` (`fh.version_text()`), edited by hand at each release.
- **Colours are `include/hardware.inc`'s** (`ATTR_DEFAULT` `$38`, the status bar's), shared by both images; the cursor
  is `$87`. `Machine.boot_trace()` (fharness) boots again from reset and returns the chime's AY writes with their
  frames and the screen at the chime's start and at the key wait (`border=` sets the ULA's border before the reset).
- **The font is printable ASCII in code order** (`FONT_TABLE + (code - 32) * 8`); `PUNCT_CHAR_TABLE` is gone. The screen
  decoders tell an old build by that symbol. Every printable character except the backtick has a key now, so tests can
  type `[ ] \ { } | ~ ^`; a test line that *starts* with `\` is still a harness comment, never typed (put code before
  it). Comments in LOAD-TEXT's CR-ended text are tape case C.
- **Defining words share `HEADER_BUILD`** (`core/interp.asm`), which takes the name through `WORD_NAME` (THROW -16 on
  none); `ARRAY`, `STRING`, `FVARIABLE` are `VARIABLE_N` with BC data bytes. A new defining word should use them.
- **Forth tests:** `{NAME}` in a test line is a ROM symbol's value (never a literal RAM address in a test). A line's
  output must fit the screen; a line that clears the screen must print something new; `\ keys:` feeds
  KEY/ACCEPT/INPUT; `\ draws` for picture lines. A full screen scrolls: put `CLS 0 0 AT-XY` before a long block. A
  timing test reads `FRAMES` just after a tick (`tests/sound/ay.fs`'s `TICK`): any change in speed moves where a line
  starts in the frame.
- **ZEsarUX's tape autoload** types J "" ENTER when the PC reaches `$11F8` with the HOME ROM paged in. Data (the font)
  must cover `$11F8`: `rom/forth_boot.asm` ASSERTs it. When HOME shrinks and the ASSERT fails, move includes ahead of
  the font, never the ASSERT.
- **HIRES is the SCLD's 8×1 colour mode**: the attribute of bitmap byte `$4000+n` is at `$6000+n`.
- **The EXROM hides `$A000-$BFFF`** (dictionary RAM) while paged in; EXROM code reaches HOME only through
  `GRAPHICS_HOME_TABLE`, and HOME cells through `include/forth_layout.inc`.
- **The layout file is packed** (Space): a cell no code references is removed, and new cells go in the room at the
  end of the cells block (128 B: `RAM_CELLS_END - VIEW_SH_END`). Addresses move whenever cells change, so tools read `.sym` names and tests use
  `{NAME}`; `tests/core/free.fs` holds the dictionary size on purpose.
- **z80sim** (`tools/z80sim/`) is a vendored copy: change it upstream (`~/z80sim`), never here; its `SYSVARS` table is
  from the BASIC project.
- **Whole-flow tests carry their own expected values** (the Blackjack round log in tapetest case 2): after a change to
  RND or anything they replay, grep for the old values.
- **Old-build comparisons:** `git worktree add --detach <scratch>/old <commit> && make -C <scratch>/old`, then
  `python3 tools/forthtest.py --build <scratch>/old/build`, or `--build` for the edtest/floattest/shapetest tools,
  `TAPETOL_BASE=`.
- **fusesave** counts 17 checks (the cartridge half is gone); Fuse 1.9.1 can abort in its own `tape_write` on some
  recorded signals (glibc assertion).
- **CI runs `make check`, `make repro`, `make dist`** (no pandoc locally): `tools/package_dist.sh` heredocs expand `$`,
  so write hex as `\$A000`.
