# Leap-Forth V2 — session handoff

Read this, then `docs/V2/ROADMAP.md` (done / next / known defects) and `CONTRIBUTING.md` (build, test, rules). Milestone
reports: `docs/V2/milestones/`.

## Where things stand (2026-11-01)

- **Master `7b39732`**: PR #15 (BREAK and timing) merged.
- **Branch `v2/step-ide-hooks`** (from master `7b39732`): step IDE hooks is complete
  (`docs/V2/milestones/IDE_hooks.md`): the Leap IDE's questions answered in
  `~/Projects/Leap-IDE/docs/requests/LEAP_FORTH_ANSWERS.md` (written there, not committed in that repository), the
  labels and `LAST_ERROR` the answers promise, a stale CATCH frame fixed. Pushed; PR #16 open.
- **Decided (2026-11-01):** the owner approved the answers' recommendations; the V2 manual is rewritten in the style
  of the Leap-C and Leap V2 manuals (a roadmap step); the cartridge build comes before Blackjack, and Blackjack (a
  demo) is one of the last steps.
- **Free bytes:** HOME 1,938, EXROM 3,208; per component in `budget.toml` (`make budget`), per routine
  `make inventory`. The dictionary starts at `$9100` (`FREE` 16,128 at power-on).
- **Next:** ROADMAP's *Cartridge build* (the answers' Q7 holds the design).

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
  is `$87`. Output is drawn in `CURRENT_ATTR` (EMIT's characters, CLS, EMIT's new row when output scrolls); the edit line
  in `ATTR_DEFAULT` (`GFX_CLEAR_ROW` takes the attribute in A). `Machine.boot_trace()` (fharness) boots again from reset and returns the chime's AY writes with their
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
- **LINE uses the alternate registers** (r, dmin, dmaj in HL', DE', BC') and nothing the interrupt runs touches them:
  keep it so (no EXX or AF' in `KBD_ISR_TICK`, `BRK_ACCEPTED`).
  LINE's coordinates are 2-byte cells (`GFX_LINE_X0` .. `_Y1`, consecutive, an `ASSERT` says so); `GFX_WRITE_PIXEL`
  keeps BC and takes no OVER flag.
- **BREAK is an asynchronous THROW -28** (`core/throwcatch.asm`): the interrupt routine may unwind any running word
  between two instructions. New code that updates two cells another word depends on must order the stores so either
  state is valid (as `FORGET`: LATEST before HERE), keep interrupts off for a few instructions (as `DOES>`'s patch;
  more than about 30 T loses a frame), or be a section: `NOBRK` +1, then `jp BRK_SECTION_END` (as
  `EXROM_CALL_NOBRK`, `GFX_SET_MODE`). A wait needs nothing: BREAK unwinds it. BREAK at the console and in `EDIT`'s view
  is their key (`NOBRK` held); anything else that wants BREAK as a key must hold `NOBRK` and clear `BRK_PEND` after.
- **Recursion stops at `MACHINE_STACK_GUARD`** (`STK_GUARD`, -5): compiled before a definition's call to itself, called
  by `EXECUTE` and `CATCH`. A new word that runs an xt must call it too. ROM routines use at most 36 B below the prompt
  in the Forth tests; the guard leaves 256 B.
- **forthtest's `\ break: at SYMBOL [N]` / `\ break: after N`** hold BREAK on the matrix for the next line (Leap-C's
  exectest directive); EXROM labels work while the dictionary is small (a breakpoint is by address).
- **CATCH keeps the input source** with its frame; THROW puts it back only when a nested run (LOAD-TEXT, EDIT) moved it,
  and `CATCH_SRC_HERE` (called when such a run starts) moves the frames' position past the name. A new word that runs
  `INTERPRET_NESTED` must call `CATCH_SRC_HERE` first. In the same source a caught THROW goes on after whatever the
  word read: `' LOAD-TEXT CATCH name` (the tutorial's idiom) depends on it.
- **The Leap IDE drives the prompt by names** (the answers, `~/Projects/Leap-IDE/docs/requests/`):
  `IO_READ_KEY` with `EDITOR_LOOP_LIVE.key_ret` at SP is the prompt; a line written into `EDIT_BUF` / `EDIT_LEN` /
  `EDIT_CURSOR` runs from `EDITOR_LOOP_LIVE.enter`; `LAST_ERROR` is the code the last line ended with;
  `INTERPRET_NESTED.token` maps compiled code to source; also `INTERPRET_RUN`, `STORE_APPEND`, the error routines and
  the cells `SRC_PTR`, `SRC_END`, `STORE_START`, `STORE_END`, `LATEST`, `HERE`, `STATE`, `THROW_CODE`, `WORD_BUF`,
  `INTERP_ERROR_FLAG`, `COLON_XT`. Do not rename them (a rename is a breaking change for the IDE: CHANGELOG); boot
  check `p host line` and `Console.host_line` drive them the IDE's way. Every error ends in `REPORT_INTERP_ERROR`
  with the code in HL.
- **Page zero holds 3 free bytes** before `$0100` (the interrupt routine and `IO_KEY_SCAN_ALL`).
- **The view's store lookup remembers a line** (`STORE_MARK_N`, `STORE_MARK_PTR`): every change to the store during a
  session must go through `STORE_GAP` (which keeps or resets the mark); a session starts it at line 0.
- **Profiling a ROM routine:** ZEsarUX's ZRCP `cpu-transaction-log` with `tstates yes`, `address yes` (a file of
  "T-states PC" lines) around one key or call, PCs attributed to the nearest label of both `.sym` files: the method
  this step's measurements used (about 30 lines of Python on fharness and edtest's helpers).
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
- **Speed ceilings:** a step that makes something faster gives it a ceiling the old build fails: the editor suite's
  `COST_CEIL` / `VCOST_CEIL`, the shape suite's `ceil=` on a speed case. A later change that slows one of them fails
  the suite: raise the ceiling only with the reason in the commit.
- **Emulator commands for people:** Fuse finds a ROM given by its name alone only in the current folder, then its own
  ROM folders; ZEsarUX runs from its own folder. The README and `docs/zesarux_setup.md` give full paths.
- **fusesave** counts 17 checks (the cartridge half is gone); Fuse 1.9.1 can abort in its own `tape_write` on some
  recorded signals (glibc assertion).
- **CI runs `make check`, `make repro`, `make dist`** (no pandoc locally): `tools/package_dist.sh` heredocs expand `$`,
  so write hex as `\$A000`.
