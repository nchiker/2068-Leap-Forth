# Leap-Forth V2 — session handoff (2026-10-29, step E complete)

Read this first in a new session. Then `docs/V2/EDITOR_SPEC.md` (step E: decisions, line store contract, view
behaviour, sections 4 and 5.1-5.3 as built, oracle table), `docs/V2/LEAPC_COMPARISON_AUDIT.md` (on branch
`v2/step-l-leapc-audit`) and `docs/V2/FORTH_V2_REUSE_AUDIT.md` (section 8 sequence, section 9 ledger, section 10 owner
decisions).

## Where things stand

- **master** is `af61e35`: PR #2 (T → G → R0 → A → R1 → S, `0d45a2f`) and PR #3 (a three-line edit of this file).
  When the E branch merges into master, this file conflicts with PR #3's version: keep the E branch's.
- **Step E is done** on `v2/step-e-console-editor` (items 1-7; all of `EDITOR_SPEC.md` section 9). Not pushed; no PR
  yet (push and open PRs only when the owner asks; merge step PRs with merge commits).

  | Branch | State |
  |---|---|
  | `v2/step-e-console-editor` | **Step E complete**: T11, T12, spec, oracle, O13 merged in, items 3-7. Ready for a PR to master |
  | `v2/e-item6-wip` | item 6's four commits, merged into the E branch (`7ddc7d6`); can be deleted |
  | `v2/step-o13-rst-stack` | O13, already merged into the E branch (`9a1d570`) |
  | `v2/step-l-leapc-audit` | step L, docs only (`9391422`, decisions `f5a36c5`), from master |

  Merging L and E into master: both append rows to the audit's section 9 ledger (and L adds section 5 rows O13-O19
  and section 10 decisions 7-9), so the second merge conflicts there; keep both sides' rows, in step order.
- **Free space [M]:** HOME 1,078 B, DOCK cartridge 1,078, Blackjack 1,096/1,096, Gallery 1,021, EXROM 5,006. The floors
  in `tools/budget.toml` equal these.
- **Step E in bytes [M]:** items 3-7 cost HOME +54 B (1,132 → 1,078 free, after O13's −506) against an estimate of
  −110 to −200; the overrun is `EDIT` and its commit loop (+157 against +40-60). EXROM +1,676 B (estimate 2,200-2,600).
  Item 5's merged redraw saved 178 B; RECALL's retirement 84.
- **Last full run [M]** (item 7's commit): `make edtest` **31/31** (old 19/19, new 12/12); `make test` 70 PASS, 0
  FAIL, 1 SKIP, POWERON 7/7; `make tapetest` 16/16; `make harness` 0 failed; `make cartdiff` 26/26; `make fusesave`
  41 checks, 0 failed; `make bench` within 1% (sieve −1.6%, string −1.2%, the rest faster); `make repro` 266 files
  identical; `make check` passes.

## What step E built (details in EDITOR_SPEC.md 4, 5.1-5.3)

- **Console:** one width-parameterised redraw (`WRAP_CALC_AT`, `ED_DRAW_ROWS`, `ED_DRAW_CURSOR`, the RAM `JP`
  `ED_ROW_JP` at `$88FC` choosing `ED_ROW32`/`ED_ROW64` per row); E10 fixed (64-column hang, 64-column room check,
  cursor on a full row: its own row, or the last cell on a 4th full row).
- **View:** `EDIT name` / `EDIT` (core/edit.asm, HOME) calls `VIEW_SESSION`, EXROM service slot 6
  (`rom/graphics_exrom.asm`); veneers 5-12 in `GRAPHICS_HOME_TABLE`; HOME cells the EXROM uses are copies in
  `include/exrom_home_ram.inc`, checked by `tools/audit_layout.py`. The view's RAM is `$8AC0-$8AF2`. Leaving runs
  the marked (`$8D`) lines with `INTERPRET_NESTED`; an error prints `LINE n` first (`EDIT_ERR_PREFIX`), and
  `EDITOR_LOOP_LIVE` clears any marks left after the console line (`EDIT_CLEAR_MARKS`).
- **The `EDIT ...` command line is taken off the store** when the view opens (`VIEW_TRIM`), so saved texts never
  reopen the editor.
- **RECALL retired**; `LIST-DEFS` is the dictionary head; 158 words (counted by walking the chain).
- **View typing cost (N12) is now a gate:** key at end 42,198 T, DOWN 126,049, ENTER 162,624, a scroll in a 60-line
  store 1,032,460 (0.3 s: all 23 rows redrawn, lines found by scanning from `STORE_START`).

## Next work, in order

1. **Owner:** review step E and ask for the PR (E branch → master), and decide on L's PR. Open points for the owner
   are in the next section.
2. **O15** (after E): FILL and CIRCLE kernels to the EXROM (about −820 B HOME). The EXROM now has 5,006 B free.
3. **Step F: float rebuild** (audit section 4.2) with O10 and T13. Also: measure `UDIV10` as a call of Leap-C's
   `RT_UDIV` once O10 is in (L audit, output words).
4. **K** (with O16, O17; about +62 B + words), **D** (with O18, the PLOT/LINE clip), **B** (BREAK latch, pause word).
5. **Step Z** (audit section 4.4) with O14 (230 B of page-zero padding), O19, and `W_EMIT` through `rst $28`.

## Open points for the owner (not blocking)

- **Step E's HOME total is over its estimate** (+54 B against −110 to −200): `EDIT` and the commit loop are 157 B.
  Candidates if HOME gets tight: share one `$8D` search between the commit loop and `EDIT_CLEAR_MARKS` (about −10 B);
  move the bare-`EDIT`/refusal messages' handling further into the EXROM.
- **The view's scroll is slow** (about 1 M T a scrolled line). A pixel scroll of rows 0-22 plus one new line, and a
  remembered line pointer instead of scanning from `STORE_START`, would cut it to a small fraction; not specified, so
  not done.
- **64-column screen layout:** the ROM writes columns 0-31 to the first display file and 32-63 to the second
  (`MODE64_CHAR_ADDR_SETUP`), and T12 reads it the same way. ZEsarUX's headless `save-screen` cannot capture the
  512-pixel mode, so nothing here has checked how a real hi-res display presents those bytes. Unchanged by step E.
- `SAVE-TEXT` still takes `addr len` (tutorial section 12), and no word gives the store's address and length, so
  what `EDIT` edits cannot be saved to tape directly. A word for that (or `SAVE-TEXT` with no arguments saving the
  store) was not in step E's scope; worth deciding before users rely on `EDIT`.

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
