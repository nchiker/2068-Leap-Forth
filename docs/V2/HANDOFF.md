# Leap-Forth V2 — session handoff (2026-10-28, step E items 1-4 done)

Read this first in a new session. Then `docs/V2/EDITOR_SPEC.md` (step E: decisions, line store contract, view
behaviour, oracle table, order), `docs/V2/LEAPC_COMPARISON_AUDIT.md` (step L) and `docs/V2/FORTH_V2_REUSE_AUDIT.md`
(section 8 sequence, section 9 ledger, section 10 owner decisions).

## Where things stand

- **master** is `af61e35`: PR #2 (T → G → R0 → A → R1 → S, `0d45a2f`) and PR #3 (a three-line edit of this file,
  merged 2026-10-29). When the E branch merges into master, this file conflicts with PR #3's version: keep this one.
- **Branches, none pushed** (push and open PRs only when the owner asks; merge step PRs with merge commits):

  | Branch | State |
  |---|---|
  | `v2/step-e-console-editor` | T11, T12, the E spec (decided), the E oracle (N1-N13), O13 merged in, E items 3 and 4. **Work continues here** |
  | `v2/step-o13-rst-stack` | O13 (`d7c2308`), already merged into the E branch (`9a1d570`) |
  | `v2/step-l-leapc-audit` | step L, docs only (`9391422`, decisions `f5a36c5`), from master |

  Merging L and E into master: both append rows to the audit's section 9 ledger (and L adds section 5 rows O13-O19
  and section 10 decisions 7-9), so the second merge conflicts there; keep both sides' rows, in step order.
- **Free space [M]:** HOME 1,050 B, DOCK cartridge 1,050, Blackjack 1,096/1,096, Gallery 1,021, EXROM 6,682. The floors
  in `tools/budget.toml` equal these.
- **All owner decisions are made:** audit section 10 decisions 1-9, and E1-E10 in `EDITOR_SPEC.md` section 2 (E2:
  fixed 8 KB store at `$D000`, dictionary ceiling `$D000`; E6: `EDIT` replaces `RECALL`; E7: leaving the view clears
  the screen; E9: `EDIT` refuses in 64-column mode). O15 (FILL/CIRCLE to the EXROM) is approved for after E; O19 merges
  to registers 0-15.
- **Last full run [M]** (E item 4's commit):
  - `make test`: 70 PASS, 0 FAIL, 1 SKIP; POWERON 7/7.
  - `make edtest`: old group 19/19; new group 4/12 (N1-N3, N5 pass; N6-N13 wait for items 6-7).
  - `make tapetest` 16/16 (with N4); `make harness` 0 failed; `make fusesave` 42 checks, 0 failed (see traps);
    `make cartdiff` 26/26; `make check` passes; `make bench` within 1% of the baseline (every row faster or equal).
  - `make repro` 266 files identical. `make tapetol`/`tapetol-fuse` last run at step S (the tape
    receiver has not changed since).

## Next work, in order

1. **Step E item 5: merged redraw** (`EDITOR_SPEC.md` E3, E10, section 9). `EDITOR_REDRAW` (219 B) and
   `EDITOR_REDRAW64` (191 B) become one width-parameterised routine (about −150 B [E]). It fixes, by construction, the
   64-column hang (HL lost across `MODE64_SCROLL_OUTPUT_UP`), the 64-column room check (uses the 32-column
   `WRAP_CALC`) and the missing cursor on a full row. Update T12 cases 7, 10 and 14 to the spec's "new build must"
   column in the same commit. Gate: typing cost (case 19) no worse than 1% plus one interrupt (2,000 T), the redraw
   oracle (case 18) still passing. Design it together with item 6's needs: the view calls this engine through veneers.
2. **Item 6: the full-screen view in the EXROM** (E3, E4, sections 3 and 5): store routines (find/replace/insert/delete
   line, count), view redraw, navigation, key table, session marks (`$8D`), engine veneers after `GRAPHICS_HOME_TABLE`
   at `$0100` (same length in HOME and cartridge builds). Budget 2.2-2.6 KB [E] of the EXROM's 6,682. Oracle hooks:
   `STORE_END`, `VIEW_REDRAW_ALL` (section 5). Several commits; N7, N9, N13 judge it.
3. **Item 7: `EDIT`** (E6, section 5's entry, refusals and leaving), `RECALL` retired (−74 B), docs and tutorial, the
   audit ledger row for step E. Done when plain `make edtest` passes all 31 cases, with `make test`, `make tapetest`,
   `make cartdiff`, `make fusesave`, `make bench`, `make repro`, `make check`.
4. **O15** (after E): FILL and CIRCLE kernels to the EXROM (about −820 B HOME).
5. **Step F: float rebuild** (audit section 4.2) with O10 and T13. Also: measure `UDIV10` as a call of Leap-C's
   `RT_UDIV` once O10 is in (L audit, output words).
6. **K** (with O16, O17; about +62 B + words), **D** (with O18, the PLOT/LINE clip), **B** (BREAK latch, pause word).
7. **Step Z** (audit section 4.4) with O14 (230 B of page-zero padding), O19, and `W_EMIT` through `rst $28` (about
   60 B; deferred from O13 because only 47 of the 75 ROMs include `core/print.asm`).

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

## Facts that cost time to find (new in this session; the older ones follow)

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
- **Until item 7,** `RECALL` copies a span containing CR into the edit line unchanged (harmless; retired in item 7).

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
