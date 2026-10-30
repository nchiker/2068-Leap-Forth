# Leap-Forth V2 — session handoff (2026-10-29: step F done, PR #8 open; PR #7 merged)

Read this first in a new session. **Step F (the 5-byte float rebuild, O10, T13) is complete** on `v2/step-f-float`
(pushed; **PR #8** open, waiting for the owner's review; Claude merges it with a merge commit when approved).
**Next: O15** (section "Next work") on its own branch from master once #8 merges (or from `v2/step-f-float`). Specs: `docs/V2/FLOAT_SPEC.md` (step F as built, decisions F1-F10 in section 15),
`docs/V2/EDITOR_SPEC.md`, `docs/V2/MODE6_REMOVAL_SPEC.md`, `docs/V2/LEAPC_COMPARISON_AUDIT.md`,
`docs/V2/FORTH_V2_REUSE_AUDIT.md` (section 8 sequence, section 9 ledger, section 10 owner decisions).

## Where things stand

- **master** is `1ba4881`: PRs #5 (M6), #6 (L) and #7 (cartdiff speed-up) merged with merge commits on 2026-10-29.
- **PR #8** `v2/step-f-float` (pushed; a trial merge onto master is clean): `63cfdc4`/`4371d18` spec, `9310c87` T13 oracle, `31260a1` O10 + RND, `91b05ce` ledger, `38e318b` the engine and
  today's 14 words, `7dd20d8` the font over `$11F8` (ZEsarUX autoload) and O10's seed in the tape tests, `470f8f4` item
  5 (22 words, PLACES, FS., TAN, FLOOR, the THROW messages), then the docs/NOTICE/HANDOFF commit.

  | Branch | State |
  |---|---|
  | `v2/step-f-float` | PR #8 open |
  | `v2/t-cartdiff-speed` | merged (PR #7) |
  | `v2/f-step5-wip` | work branch, its commit cherry-picked as `470f8f4`; can be deleted |
  | `v2/step-m6-mode6-removal`, `v2/step-l-leapc-audit`, `v2/step-e-console-editor` | merged |
  | `v2/t-cartdiff-wip`, `v2/m6-*-wip`, `v2/e-*-wip`, `v2/step-o13-rst-stack` | merged work branches; can be deleted |

- **Free space [M]:** HOME 816 B, DOCK cartridge 816, Blackjack 876/876, Gallery 805, EXROM 4,247. Floors equal these.
  Step F used 813 B of HOME (engine, 36 float words, messages); the owner kept the transcendentals in HOME (2026-10-29).
- **Last full run [M]** (`470f8f4`): `make floattest` **64/64**; `make test` 66/0/1, POWERON 7/7; edtest 30/30;
  harness 0 failed; cartdiff 28/28; fusesave 41/0; tapetest 16/16; bench float region 141,529,251
  (−19.1%), sieve −1.6%, string −1.3%, pixel ±0 (reset at O10); repro 251 files; check passes (provenance 0 runs).

## Owner decisions (2026-10-29)

- **Step F (FLOAT_SPEC.md section 15, F1-F10):** decide by what is best for the language and its users, not by
  compatibility with old behaviour or sequences (the owner's rule for every decision). Register kernels; 22 new words;
  F>S truncating with a range error; FROUND ties away from 0; F. with PLACES and exact rounding, FS.; E exponents;
  integer literals outside -32768..65535 an error; messages for the ROM's THROW codes; RND on xorshift; bench_float's
  RESULT -0.1453. The transcendentals stay in HOME at 816 B free.
- **Mode 6 dropped entirely** (64COL, 32COL, PALETTE64, PLOT64, the 64-column kernel and every 64-column path):
  the layout is unverifiable here and not worth the effort. **HIRES/NORMAL stay** (the TS2068 high-colour mode, not
  Mode 6). Done in step M6 (`docs/V2/MODE6_REMOVAL_SPEC.md`, −587 B HOME).
- **HOME bytes** may be spent when a ledger row justifies them.
- **One authoritative source:** the line store. `SAVE-TEXT name`/`VERIFY-TEXT name` save and check it (the `addr len`
  forms were a defect left from before step E; spec section 3 had required the store). Command lines (`SAVE-TEXT`,
  `VERIFY-TEXT`, `LOAD-TEXT`, `EDIT`) are never stored (`STORE_TRIM`).
- **The view's redraw** was rebuilt from Leap V2's row shadow after the owner asked whether Leap-C/Leap V2's redraw
  logic had been used (it had not: a process miss; references named in a spec are to be studied before designing).

## What step E built (details in EDITOR_SPEC.md 3, 4, 5.1-5.5)

- **Console:** one width-parameterised redraw (`WRAP_CALC_AT`, `ED_DRAW_ROWS`, `ED_DRAW_CURSOR`, the RAM `JP`
  `ED_ROW_JP` at `$88FC`); E10 fixed (64-column hang, 64-column room check, cursor on a full row; the 64-column paths went in M6).
- **View:** `EDIT name` / `EDIT` (core/edit.asm, HOME) calls `VIEW_SESSION`, EXROM service slot 6; veneers 5-12 in
  `GRAPHICS_HOME_TABLE`; HOME cells the EXROM uses are copies in `include/exrom_home_ram.inc`, checked by
  `tools/audit_layout.py`. View RAM `$8AC0-$8B39` (row shadow `$8AF3-$8B37`). Leaving runs the marked (`$8D`) lines
  (`EDIT_NEXT_MARK`, `INTERPRET_NESTED`); an error prints `LINE n` first; `EDITOR_LOOP_LIVE` clears marks left by an
  unwound line.
- **Redraw on a row shadow** (5.4, 5.5): rows remember (line, row); a moved view is shifted by pixels and only rows
  that differ are drawn. N12 (T): scroll 270,769, DOWN mid-screen 76,914, UP scroll 242,624, ENTER at the bottom
  421,116, DOWN 56,894, typing 40,324.
- **The store is the source:** `STORE_APPEND` records where it put the line being run (`STORE_LAST_LINE`, `$8BFE`);
  `STORE_TRIM` takes it off for the four commands.
- **RECALL retired**; `LIST-DEFS` is the dictionary head; 158 words (counted by walking the chain).

## Next work, in order

1. **Owner:** review PR #8 (step F); Claude merges it with a merge commit, then runs the full `make test` on master.
2. **O15:** FILL and CIRCLE kernels to the EXROM (about −820 B HOME; the EXROM has 4,247 B free). Now worth more:
   HOME has 816 B free.
3. **K** (with O16, O17; the text-drawing speed-up), **D** (O18), **B**.
4. **Step Z** (audit section 4.4) with O14, O19, `W_EMIT` through `rst $28`; and a size pass over the float code
   (candidates: FINT 134 B, FADD 169, FS. 193, the shared parser 404, FDEPTH 32).

## Step F: what was built (details in FLOAT_SPEC.md)

- **Format:** 5-byte Sinclair floats on the IY stack (204 cells, `FSTACK_LIMIT` `$8C04`); engine `core/fpcore.asm`
  (Leap-C's fpcore rebuilt; register multiply/divide kernels with `exx`, bit-exact with `fpmodel`), `fpparse.asm`
  (one parser for integers and floats), `fpprint.asm` (F. on 128.64 fixed point, exact half-up; FS.; PLACES),
  `fpconv.asm` (S>F F>S FROUND FLOOR), `fpmath.asm` (FSQRT 4 Newton steps, SIN/COS Cody-Waite with COS shifted inside the
  reduction, TAN, PI, RAD, DEG), `fpstack.asm` (18 words). RAM `$8594-$85D6`.
- **Oracle T13:** `make floattest` (`tools/floattest.py`, ports 10840-10859) against `tools/fpforth.py` on
  `tools/fpmodel.py` (Leap-C's, vendored unchanged, sha256 in fpforth). `python3 -I tools/fpforth.py` is the model's
  self-test (accuracy against Python's math).
- **O10:** `kernel/math/math.asm` multiply/divide register-only (Leap-C), RND on xorshift with a multiply for the range.
- **Errors:** an uncaught THROW prints a message (`THROW_CODE` `$85D6`), `STACK?` only for the stack check.

## Open points (not blocking)

- **cartdiff intermittent harness failure** (about 3%, both the old and new builds, HOME or cartridge side): host
  timing reaches the run (no failure repeats with the key timing fixed). The ZEsarUX autoload trigger below was another
  such harness-meets-emulator effect; read ZEsarUX's source (`~/zesarux-source`) first next time.
- **Integer literals parse about 2.5× slower** (4,797 T for `12345`, was 1,926: the shared parser's 32-bit digit
  loop); a 16-bit fast path would cost about 40 B.

- **`CATCH_STACK` overlap** (found by step F's RAM map, not fixed): `CATCH_STACK` `$8916` + 8 × 6 B reaches `$8945`, over
  `SPACES_COUNT` (`$8940`) and `PRINT_LINE_BUF`'s first 4 bytes (`$8942`): the 8th nested CATCH and SPACES/LPRINT share
  bytes. A free 48 B gap exists (`$8316-$84FF` and others, `FLOAT_SPEC.md` section 9).
- **`LATEST`/`HERE` inside the data stack's range** (`$9002`/`$9004`, `DSTACK_LIMIT` `$9000`): a data stack about 1,020
  cells deep overwrites them before `STACK_CHECK` objects; `core/dict.asm`'s comment says 1,024 B (floor `$9400`).

- **The view's ENTER at the bottom** is still 421k T: about 122k is `STORE_LINE` scanning a 60-line store from
  `STORE_START` per key; a cached cursor-line address would cut it. An insert or delete mid-screen redraws the rows
  below (no partial shift). Both outside spec 5.4.
- **Text drawing** costs about 1,000 T a cell in HOME's `GFX_PUTCHAR` (the per-character font lookup and attribute
  address); see K above.

## How the owner wants the work done

- **Rebuild, not drop-in:** spec first, then an oracle run on the old build, then the code, each with a measured
  ledger row. Evidence tags [M] [S] [E] [L].
- **One branch per step**; commit at the end of each piece, with the Co-Authored-By line.
- **No hardware:** never propose hardware checks; state the emulator limits (ZEsarUX, Fuse, TSRun).
- **Orchestration:** Haiku for inventories and running suites; Sonnet for porting scripts, drafting Makefile changes,
  and (this session) implementing well-specified ROM items, which you then review line by line; keep design
  decisions, Makefile review and byte-identical checks for yourself; verify every subagent claim a decision rests on.
- **Budget floors:** never lower one without a ledger row and a history line in `tools/budget.toml`.
- **Keep `IFDEF CARTRIDGE` code the same length in both builds** (`rom_identity.py --shared` in `make check`).

## Facts that cost time to find (step F; then M6, E and O13; the older ones follow)

- **Step F.**
  - **ZEsarUX's tape autoload** (on by default; `realtape-open` arms it, resets the machine and starts the tape) types
    J "" ENTER as soon as the PC equals `$11F8` with the HOME ROM paged (the stock ROM's key wait;
    `~/zesarux-source/src/storage/tape.c`, `MACHINE_ID_TIMEX_TS2068`), feeding the keys to the next keyboard-port reads
    (`operaciones.c` `envia_jload_pp_spectrum`). `--noautoload` also stops the tape from playing (no ZRCP command
    plays it; the F-key function needs the GUI). Fix: data (the font, `kernel/graphics/font.asm`) covers `$11F8` in
    the boot ROM, with an ASSERT in `rom/forth_boot.asm`. If that ASSERT fails, move the font include, not the code.
  - **`tools/run_realtape_test.sh` opens a Fuse window** (it needs an X display). Do not run it or hand it to an agent
    (owner, 2026-10-29); `make tapetest` case 2 covers the same text headlessly.
  - **`make` stops at the first ROM that fails to assemble**: use `make -k` when some smoke ROMs are broken on
    purpose, or the product image stays stale (that cost a wrong speed figure once).
  - **z80sim** (`tools/z80sim/sim.py`) runs a routine from a scratch `.asm` file: push `('HALT',)` on its stack and
    catch `Halt` ("clean stop") for the outermost `ret`; it supports `exx`. Used for the kernels (5,698 cases).
  - **The stock ROM's interrupt routine keeps BC', DE', HL'** (ZEsarUX; AF' changes in the stock ROM's own main code,
    which never runs in the cartridge build): the kernels use `exx`, never `ex af, af'`.
  - Tests that run whole flows (tapetest, the realtape script, smoke p53) carry their own copies of expected values
    (the Blackjack log): after a change to RND or anything they replay, grep for the old values.

- **Step M6.**
  - **Suite times:** `make cartdiff` about 75 s since the speed-up (it was 16 min); `make tapetest` about 5 min, `make
    test` about 4, `make edtest` about 2. With edtest, test and bench running at the same time, tapetest case 3 once
    dropped two typed characters ("typing slip", a harness error, not a ROM failure); run tapetest alone.
  - **cartdiff types in emulated time** (`tools/cart_diff.py`): keys held on the matrix with `send-keys-event` while the
    paused machine is stepped; accepted when `EDIT_LEN` grows (ENTER: the ISR latch, `KBD_CUR_ROW` tracked and
    `KBD_DEBOUNCE` 0), 2 frames key-up. No PC breakpoints on HOME routines: in the cartridge build the stock ROM shares
    those addresses. `--dump DIR` and `tools/cart_diff_dumpcmp.py` compare runs byte for byte.
  - **fusesave's count** is 41 checks when Fuse records the first cross tape, 42 when Fuse aborts in `tape_write` and
    the retry repeats the boot check.
  - **What is gone:** `GFX_MODE` 2, port `$FF` bits 3-5 (never written now), `fharness` check `i` and its 64-column
    screen reader, edtest's 64-column parts and N11, smoke p8b/p56/p57/p58 and `mode64_visual_check`. RAM
    `$87BF-$87C3` (the mode's 5 B) is unused. Smoke p9 seeds `LATEST` with `H_FMINUS`.
  - **Byte check for a removal:** pair the old and new listings on their emitted source lines (difflib over
    (file, instruction)); a pure removal shows only `delete` blocks.

- **Test tools.**
  - `tools/fharness.py` (T11): Machine (boot to the first `IO_READ_KEY`, snapshot, restore 3-5 ms, `call`,
    `checkpoint`/`rollback`, `screen_rows` (32 columns since M6), `expect_mem`, `ram_diff`), Console (keys through the
    ISR latch, or `press` on the matrix with the map read from the ROM's key tables), `run_pool`. Ports 10900-10919.
    RAM it uses: `$FF00` return slot, `$FF02` stop, `$FF10` glyph program (above the machine stack).
    It boots only images that reach `IO_READ_KEY`; the demo ROMs do not.
  - `tools/edtest.py` (T12; 30 cases since M6): `--group old|new|both`, case numbers or name substrings to select, `--selftest` (the
    view model, no emulator), `--build DIR` for an old build. Open spec details it chose are marked `READING:` in the
    code. Make: `make edtest EDTEST_GROUP=old`.
  - Other ports: `make test` 10760 up, bench 10780, poweron 10820-10839, ay_audio 10880-10899, harness/edtest
    10900-10919, cartdiff 10930-10949, tapetest 10960-10979 (`--port` to move it), tapetol 10980-10999. Two agents
    running suites at once must not share a range.
- **Fuse 1.9.1 tape writer abort.** Some recorded tapes make Fuse abort (glibc malloc assertion) inside its own
  `tape_write`; it depends on the recorded bytes, not the ROM (the same ROM records an equivalent word fine; ZEsarUX
  decodes the tape that crashed Fuse). `tools/fusesave.py`'s cross phase prints the abort and records again with an
  equivalent definition (`CROSS_SETUPS`). If another recording trips it, run
  `python3 -I tools/tapetest.py --build build --case 4 --port 10970` before suspecting the ROM (spec section 10).
- **Agents with `isolation: worktree` start on master.** Easier: create the worktree yourself
  (`git worktree add -b <branch> <scratch>/wt <commit>`) and give the agent its path; remove it afterwards.
- **Byte checks for mechanical refactors** (method in `docs/V2/evidence/o13_listing_equivalence.txt`): pair the
  emitted lines of the old and new listings in order, build the old→new address map from the pairing, and allow only
  the intended substitution plus operands that map; check label expressions by hand. Per-routine sizes: attribute each
  emitted listing byte to its file and last top-level label (both scripts were scratch, not committed).
- **Memory map changes this session.** Page zero `$0008`/`$0018` hold `DPOP_HL`/`DPUSH_HL` (`include/rst_vectors.inc`,
  included by all 75 ROMs; `$0028`, `$0030`, `$003E-$0065`, `$006C-$00FF` still free). Dictionary `$9800-$CFFF`
  (THROW -8 at `$D000` - 256, `DICT_ROOM`). Line store `$D000-$EFFF`, CR-ended lines, `STORE_END`. Sprite buffers
  moved to `$F000-$F11F` (they were inside the store). `UDG_TABLE` `$F180`.
- **Interpreter nesting.** `INTERPRET_NESTED` (an entry one instruction into `INTERPRET_RUN`) keeps `THROW_ROOT_SP`
  the outermost run's; `REPORT_INTERP_ERROR` unwinds to it. `LOAD-TEXT` uses it and keeps the outer `SRC_PTR`/`SRC_END`.

## Older facts (from the steps before E)

- **Builds.** HOME build `forth_boot_rom0.bin` replaces the TS2068 HOME ROM. DOCK cartridge build: `make cart`,
  `-DCARTRIDGE`, `forth_boot.dck`, for the stock ROM kept in the machine (hardware, TS-Pico); it carries the graphics
  EXROM as DOCK chunk 5. The EightyOne workaround is different: `eightyone/*.dck`, the graphics EXROM only, bank `$FE`.
  HOME and cartridge share every address and the ROM identity; only 25 bytes differ, in the `ROM_ID_SKIP_*` ranges.
- **LIB identity** (`STORAGE_SPEC.md` D3): a CRC of the exact ROM, so every release invalidates LIB tapes. V1
  compatibility is not required.
- **ZEsarUX:** `realtape-open` resets the machine and plays at once; TZX `$15` plays 54 times too slow (use `.rwa` at
  224 T a sample); a held key is released while the emulator is paused; a second `realtape-open` in the same ZEsarUX
  plays nothing, and parallel workers need different tape file names.
- **Fuse 1.9.1** (`/usr/local/bin/fuse`) runs headless through `tools/fuse/fuseshim.c` (LD_PRELOAD) and
  `tools/fusedrive.py`; no SDL2 dev headers here (the shim builds against the flatpak SDK headers); stock ROMs in
  `~/fuse-build/roms` (`FORTH_STOCK_ROMS`).
- **Old-build comparisons:** `git worktree add <scratch>/old <commit> && make -C <scratch>/old`, then
  `TAPETOL_BASE=`, `TAPETEST_OLD=` or `EDTEST_BUILD=`.
- **z80-skills scripts** (`~/z80-skills/skills/shrink-z80/scripts`): run with plain `python3`, not `-I`.
- **CI runs `make dist`**, which nothing local runs (no pandoc): `tools/package_dist.sh` heredocs expand `$`, so
  write hex as `\$A000`.
- **Leftover lead, unchecked:** `INT_GET_FRAMES` (4 B) reported unreachable in the HOME image; look at it in Z.
- **Deferred from S:** a static storage-contract check (Leap V2 `check_storage_contract.py`).
