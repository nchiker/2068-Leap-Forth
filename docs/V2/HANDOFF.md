# Leap-Forth V2 — session handoff (2026-10-29, step E complete with the review follow-up)

Read this first in a new session. Then `docs/V2/EDITOR_SPEC.md` (step E: decisions, line store contract in section 3,
view behaviour, sections 4 and 5.1-5.5 as built, oracle table), `docs/V2/MODE6_REMOVAL_SPEC.md` (the next step),
`docs/V2/LEAPC_COMPARISON_AUDIT.md` (on branch `v2/step-l-leapc-audit`) and `docs/V2/FORTH_V2_REUSE_AUDIT.md`
(section 8 sequence, section 9 ledger, section 10 owner decisions).

## Where things stand

- **master** is `af61e35`: PR #2 (T → G → R0 → A → R1 → S, `0d45a2f`) and PR #3 (a three-line edit of this file).
  When the E branch merges into master, this file conflicts with PR #3's version: keep the E branch's.
- **Step E is done** on `v2/step-e-console-editor`, including the owner-review follow-up (the view's row-shadow
  redraw, `SAVE-TEXT` on the line store). Not pushed; no PR yet (push and open PRs only when the owner asks; merge step
  PRs with merge commits).

  | Branch | State |
  |---|---|
  | `v2/step-e-console-editor` | **Step E complete** with the follow-up. Ready for a PR to master |
  | `v2/e-item6-wip`, `v2/e-shadow-wip`, `v2/e-savetext-wip` | work branches, merged into the E branch; can be deleted |
  | `v2/step-o13-rst-stack` | O13, already merged into the E branch (`9a1d570`) |
  | `v2/step-l-leapc-audit` | step L, docs only (`9391422`, decisions `f5a36c5`), from master |

  Merging L and E into master: both append rows to the audit's section 9 ledger (and L adds section 5 rows O13-O19
  and section 10 decisions 7-9), so the second merge conflicts there; keep both sides' rows, in step order.
- **Free space [M]:** HOME 1,042 B, DOCK cartridge 1,042, Blackjack 1,096/1,096, Gallery 1,021, EXROM 4,224. The floors
  in `tools/budget.toml` equal these.
- **Step E in bytes [M]:** items 3-7 and the follow-up cost HOME +90 B (1,132 → 1,042 free, after O13's −506; the
  owner accepts HOME bytes that a ledger row justifies) and EXROM +2,458 B (6,682 → 4,224: the view 1,676, its
  row-shadow redraw +841 against an estimate of about 0, less `VIEW_TRIM` 56).
- **Last full run [M]** (the follow-up's commit): `make edtest` **31/31**; `make test` 70 PASS, 0 FAIL, 1 SKIP,
  POWERON 7/7; `make tapetest` 16/16; `make harness` 0 failed; `make cartdiff` 26/26;
  `make fusesave` 42 checks, 0 failed (the Fuse tape_write abort and retry, as known); `make bench` within 1% (sieve
  −1.6%, string −1.2%, the rest faster); `make repro` 266 files identical; `make check` passes.

## Owner decisions this session (2026-10-29)

- **Mode 6 dropped entirely** (64COL, 32COL, PALETTE64, PLOT64, the 64-column kernel and every 64-column path):
  the layout is unverifiable here and not worth the effort. **HIRES/NORMAL stay** (the TS2068 high-colour mode, not
  Mode 6). Plan: `docs/V2/MODE6_REMOVAL_SPEC.md` (about −589 B HOME).
- **HOME bytes** may be spent when a ledger row justifies them.
- **One authoritative source:** the line store. `SAVE-TEXT name`/`VERIFY-TEXT name` save and check it (the `addr len`
  forms were a defect left from before step E; spec section 3 had required the store). Command lines (`SAVE-TEXT`,
  `VERIFY-TEXT`, `LOAD-TEXT`, `EDIT`) are never stored (`STORE_TRIM`).
- **The view's redraw** was rebuilt from Leap V2's row shadow after the owner asked whether Leap-C/Leap V2's redraw
  logic had been used (it had not: a process miss; references named in a spec are to be studied before designing).

## What step E built (details in EDITOR_SPEC.md 3, 4, 5.1-5.5)

- **Console:** one width-parameterised redraw (`WRAP_CALC_AT`, `ED_DRAW_ROWS`, `ED_DRAW_CURSOR`, the RAM `JP`
  `ED_ROW_JP` at `$88FC`); E10 fixed (64-column hang, 64-column room check, cursor on a full row).
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

1. **Owner:** review step E and ask for the PR (E branch → master), and decide on L's PR.
2. **Step M6: Mode 6 removal** (`docs/V2/MODE6_REMOVAL_SPEC.md`), its own branch from the E branch's tip: spec,
   oracle (edtest's 64-column parts and N11, fharness check `i`, smoke ROMs p8b/p56/p57/p58 and the visual check,
   p44 to HIRES), the code in one commit (re-point the chain before `floatmul.asm` to `H_FMINUS`), docs (tutorial
   section 13 goes, 14-17 renumber).
3. **O15:** FILL and CIRCLE kernels to the EXROM (about −820 B HOME; the EXROM has 4,224 B free).
4. **Step F: float rebuild** (audit section 4.2) with O10 and T13.
5. **K** (with O16, O17; also the text-drawing speed-up the owner may approve: an ASCII-indexed font, about
   byte-neutral against K's planned +80 B, and a row text primitive, about 2x on every redraw), **D** (O18), **B**.
6. **Step Z** (audit section 4.4) with O14, O19, and `W_EMIT` through `rst $28`.

## Open points (not blocking)

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

## Facts that cost time to find (steps E and O13; the older ones follow)

- **Test tools.**
  - `tools/fharness.py` (T11): Machine (boot to the first `IO_READ_KEY`, snapshot, restore 3-5 ms, `call`,
    `checkpoint`/`rollback`, `screen_rows` incl. 64 columns, `expect_mem`, `ram_diff`), Console (keys through the
    ISR latch, or `press` on the matrix with the map read from the ROM's key tables), `run_pool`. Ports 10900-10919.
    RAM it uses: `$FF00` return slot, `$FF02` stop, `$FF10` glyph program (above the machine stack).
    It boots only images that reach `IO_READ_KEY`; the demo ROMs do not.
  - `tools/edtest.py` (T12): `--group old|new|both`, case numbers or name substrings to select, `--selftest` (the
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
