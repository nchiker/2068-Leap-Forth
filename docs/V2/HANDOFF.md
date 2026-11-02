# Leap-Forth V2 — session handoff

Read this, then `docs/V2/ROADMAP.md` (done / next / known defects) and `CONTRIBUTING.md` (build, test, rules). Milestone
reports: `docs/V2/milestones/`.

## Where things stand (2026-11-01)

- **Release v2.0.1 (2026-11-01):** step STICK (PR #24: `STICK` makes port A an input and selects its connector, as
  Leap V2 v2.1.1, `milestones/STICK.md`; a `tsrun` suite in `make test`), then the version text `2068 FORTH V2.0.1`,
  tagged `v2.0.1` (CI publishes the release); the TSRun demo serves it.
- **V2 is complete. Master `24a5bf2`**: PRs #19 (Manual), #20 (Polygon edges), #21 (Cart start) and #22 (Blackjack)
  merged 2026-11-01, in that order, with merge commits; no PR open, every other branch merged. The ROADMAP has nothing
  scheduled. The step reports are `docs/V2/milestones/`; the last is `Blackjack.md`.
- **The owner (2026-11-01):** for a remaining defect, look first at how Leap-C (and Leap V2, whose cartridge is in
  production) handled the same problem. The one left (LINE far off the screen) is compared in the Polygon edges
  report: Forth keeps the exact line.
- **Decided (2026-11-01):** the manual has Leap-C's eight parts, the words split into Part 3 (the language) and Part 4
  (the machine) by the IDE's groups; the tutorial is folded in as Part 2 (the owner). Earlier: after the cartridge's
  start word, the `OK` prompt.
- **Free bytes:** HOME 1,913, EXROM 3,136, the cartridge's HOME image 1,740; per component in `budget.toml`
  (`make budget`), per routine `make inventory`. The dictionary starts at `$9100` (`FREE` 16,128 at power-on); the data
  stack is 896 cells under a 256-byte guard (`$9000-$90FF`).
- **Next:** nothing scheduled; the Shooting Gallery is not wanted now (the owner, 2026-11-01). A new step starts
  from master. Leap V2 (`~/2068-Leap`, `kernel/math/math.asm`) seeds `RND` from R alone, the defect fixed here
  in step Blackjack; that is Leap V2's to fix, not this repo's.

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
  carttest 10920-10939, poweron 10820-10839, floattest 10840-10859, shapetest 10860-10879, ay_audio 10880-10899,
  fharness self-test 10900-10919, tapetest 10960-10979, tapetol 10980-10999.
- **Suite times:** `make test` ~9 min (pool ~3, poweron 0.5, tape ~5.5, cart 0.1), `make test-fast` ~2 min,
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
- **The manual** (`docs/manual/`): a word added, removed or changed needs its entry in Part 3 or 4 in the IDE's shape
  (`tools/manualcheck.py`, in `make check`, says what is wrong); after editing any part run `tools/docexamples.py`
  (regenerates `tests/doc/manual_*.fs`, which the forth suite runs) and `make manual` (the `.docx`). Example lines are
  typed: keep each under 31 characters (forthtest misreads a line that wraps the input area; the screen is right),
  give `\ expect:` two spaces for output that starts with a space, and keep picture lines `\ draws` (text typed over a
  picture reads as garbage). Tape commands are ```text blocks. The answers' Q5 has an as-built section for the IDE.
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
- **tapetest case 2 plays `demos/blackjack.fs` itself** between the lines of `tests/data/blackjack_rounds.txt` (a
  scripted `KEY` before it, 8 rounds from seed 15785 after it) and compares the stack with `bj_model` (tapetest: the
  demo's rules on `fpforth.rnd`). A change to the demo's rules needs the same change in `bj_model`; a change to `RND`
  needs it in `fpforth.rnd` (floattest checks that against the ROM).
- **A Forth source as a program:** `tools/fs2lib.py` compiles it on the release ROMs (ZEsarUX, port 10900 by default:
  fharness's self-test range) and writes its SAVE-LIB tape; `make blackjack` = that + `make cart ... OUT=blackjack`.
  carttest compiles its programs with `fs2lib.compile_lines`. `tools/tape_gen_forth.py` (a source as a text tape for
  LOAD-TEXT) turns LF into CR: without it a `\` comment hides the rest of the file.
- **`RND`'s own seed** (`MATH_RND16`, no `RANDOMIZE` or `0 RANDOMIZE`) is `FRAMES` with R XORed into its high byte,
  bit 0 set. A program that starts by itself seeds after the first key (`demos/blackjack.fs`'s start word).
- **Old-build comparisons:** `git worktree add --detach <scratch>/old <commit> && make -C <scratch>/old`, then
  `python3 tools/forthtest.py --build <scratch>/old/build`, or `--build` for the edtest/floattest/shapetest tools,
  `TAPETOL_BASE=`.
- **Speed ceilings:** a step that makes something faster gives it a ceiling the old build fails: the editor suite's
  `COST_CEIL` / `VCOST_CEIL`, the shape suite's `ceil=` on a speed case. A later change that slows one of them fails
  the suite: raise the ceiling only with the reason in the commit.
- **Emulator commands for people:** Fuse finds a ROM given by its name alone only in the current folder, then its own
  ROM folders; ZEsarUX runs from its own folder. The README and `docs/zesarux_setup.md` give full paths.
- **fusesave** counts 17 checks (it does not run the cartridge: `make cart`'s tests are ZEsarUX's and TSRun's); Fuse 1.9.1 can abort in its own `tape_write` on some
  recorded signals (glibc assertion).
- **The cartridge build (`-DCARTRIDGE`) must keep every release label at its address** (`tools/cart_check.py`, in
  `make check`): cartridge-only code goes in `kernel/bank/cart.asm` (assembled after everything, in the free space),
  and a flagged variant inside a release routine must fit its bytes (`BANK_PAGE_EXROM_IN` 27, `_OUT` 16). The
  cartridge's own code (173 B) must stay within the HOME reserve floor (200 B), so the cartridge fits whenever the
  release does. It carries the release's `ROM_IDENTITY` (copied, not computed). A change to COLD_START's tail keeps the
  call at `COLD_START.chime`.
- **Cartridge tests:** `fharness.Machine` runs a build with `forth_cart.dck` (or `dck=`) on ZEsarUX's stock
  `ts2068.rom` by `smartload`, every breakpoint guarded by `PEEK(1)=1` (the stock ROM has `$AF` there); any tool's
  `--build build/cart` works (`make test-cart`, about 6 min; the no-EXROM cases are reported as not run).
  `tools/carttest.py` (ports 10920-10939, about 6 s) is `make test`'s `cart` suite; `tools/cartrun.mjs` is the TSRun
  cross-check (Node and `~/TSRun`, stock ROMs in `~/TSRun/roms`). The stock ROM hands over at frame 103 with
  interrupts on, SP `$61FE`, HSR `$23`.
- **The program image format** (`kernel/bank/cart.asm`'s header, `tools/forthcart.py`, the IDE's answers Q7 "as
  built") is what the Leap IDE packs: change it only with the IDE (a CHANGELOG line, as for the labels).
- **CI runs `make check`, `make repro`, `make dist`** (no pandoc locally): `tools/package_dist.sh` heredocs expand `$`,
  so write hex as `\$A000`.
