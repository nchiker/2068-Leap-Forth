# Leap-Forth V2 — session handoff (2026-10-28, end of step S)

Read this first in a new session. Then read `docs/V2/FORTH_V2_REUSE_AUDIT.md`: section 8 is the sequence,
section 9 the ledger, section 10 the owner decisions, and section 6 the per-step results.

## Where things stand

- **Branch `v2/step-s-storage`, pushed.** It holds the whole chain T → G → R0 → A → R1 → S plus the S follow-up.
  **PR #2** (https://github.com/nchiker/2068-Leap-Forth/pull/2) targets master, which is still the audit baseline
  `fff5259`. Not merged: the owner merges.
- **Free space [M]:** HOME 626 B, DOCK cartridge 626 B, Blackjack 797/797, Gallery 801, EXROM 6,682. The floors in
  `tools/budget.toml` equal these; raise them when a step recovers space.
- **All owner decisions 1-6 are decided** (audit section 10). Decision 3, the float format, is the 5-byte
  Sinclair format.
- **Last full run [M]** (`docs/V2/evidence/s_followup_shared_identity.txt`):
  - `make test`: 70 PASS, 0 FAIL, 1 SKIP; POWERON 7/7.
  - `make check`, `make repro` and `make bench` pass.
  - `make cartdiff`: 26/26.
  - `make tapetest`: 15/15.
  - `make tapetol`: 66/71; `make tapetol-fuse`: 67/71.
  - `make fusesave`: 41/41.

## Next work, in order

1. **Step E: console and editor rebuild** (audit section 4.3). Start with its test tools:
   - **T11:** a symbol-based harness (snapshot restore, memory assertions, parallel workers, a screen-text
     reader), from Leap-C `tools/lcharness.py` and `tools/run_tests.py`.
   - **T12:** the editor screen oracle, from Leap-C `tools/shelltest.py` (40 cases).

   Then E itself: line store at `$D000`, then the engine evaluation (can Leap V2's 625 B
   `rom/exrom_editor.asm` engine replace the 998 B `core/editor.asm`? about −370 B [E]), then the full-screen
   view in the EXROM (+2.2-2.6 KB [E]). Write a spec first (like `STORAGE_SPEC.md`), then the oracle on the old
   build, then the code.
2. **Step L: Leap-C comparison audit** (section 4.5). It is read-only, so it can run alongside E's harness work,
   and must finish before D, K, B and Z. Audit against Leap-C (`platform/` is Leap V2's kernel plus deltas;
   `src/runtime/library.asm` and `helpers.asm`) every HOME module never compared with Leap code. The value table
   in 4.5 says where it is worth it:
   - High: the graphics kernel.
   - Medium: graphics words, strings, output words, keyboard/interrupt.
   - Low: integer words, sound words, boot, misc I/O.
   - None: interpreter/compiler, DO/LOOP, errors, 64-column mode, printer.

   Each replacement found becomes an O-item placed in a step.
3. **Step F: float rebuild** (section 4.2), with the 5-byte Sinclair format and Leap-C `fpcore`.
   - **Includes O10:** integer multiply and divide go to Leap-C's register-only `src/runtime/helpers.asm`
     routines (1.4-2.3× faster [L]). Keep `MATH_SQRT16`, `SGN16` and `RND16`, which Leap-C deleted, or take
     Leap-C's xorshift `rand`, whichever measures smaller. The sieve and string benchmarks must hold or improve.
   - Oracle T13: Leap-C `tools/fpmodel.py` and `tools/floattest.py`.
   - Conditions: if `bench_float` gets slower, its baseline reset needs the owner's OK; if HOME is short,
     SIN/COS/TAN move to the EXROM.
   - Run the provenance scan on `fpcore` before adopting it (decision 4's condition).
   - Smoke ROMs p8, p18, p19, p22, p23, p29, p30, p34, p35 and p42 need regenerating.
4. **Small steps, after L:** K (keys and glyphs `[ ] \ { } | ~ ^`, +~100 B), D (`GFX_CLEAR_ROW` speed),
   B (BREAK latch and a pause word, +~35 B).
5. **Step Z: size pass on the retained code**, after E, F and L (section 4.4). Tools: the z80-skills `shrink-z80`
   skill and its scripts.

## How the owner wants the work done

- **Rebuild, not drop-in.** Each section is rebuilt from a spec, with Leap V2 and Leap-C as reference and oracle,
  and a measured byte ledger row. Evidence tags: [M] measured, [S] source, [E] estimate, [L] Leap-measured.
- **One branch per step**, from the previous step's branch: `v2/step-<x>-<name>`. Commit at the end of each piece.
  Commit messages end with the Co-Authored-By line. Push and open PRs only when the owner asks.
- **No hardware.** Never propose hardware checks; state the emulator limits instead (ZEsarUX, Fuse, TSRun).
- **Orchestration** (the owner's standing brief): delegate routine work.
  - Haiku: inventories, running suites, summarising.
  - Sonnet: porting scripts, drafting Makefile changes.
  - Keep for yourself: design decisions, Makefile review, byte-identical checks.
  - Verify any subagent claim a decision rests on.
  - Agents with `isolation: worktree` start on **master**, so tell them to `git reset --hard <commit>` first.
- **Budget floors:** never lower one without a ledger row and a history line in `tools/budget.toml`.
- **The tape block I/O** (`kernel/storage/tapeblock.asm`) is Leap-C's code, unchanged and hash-checked by
  `tools/check_upstream.py`. The owner allows a rewrite if needed; none is needed now.

## Facts that cost time to find

- **Builds.**
  - HOME build: `forth_boot_rom0.bin`, which replaces the TS2068 HOME ROM.
  - DOCK cartridge build: `make cart`, `-DCARTRIDGE`, giving `forth_boot.dck`. It runs with the stock ROM kept
    in the machine, for real hardware or TS-Pico.
  - The EightyOne workaround is a different thing: `eightyone/*.dck`, the graphics EXROM only, bank `$FE`, used
    with the HOME ROM.
  - HOME and cartridge share every address and the ROM identity. Only 25 bytes differ, in the `ROM_ID_SKIP_*`
    and `.rom_id_skip` ranges, and `tools/rom_identity.py --shared` in `make check` proves it. **Keep any new
    `IFDEF CARTRIDGE` code the same length in both builds**, or LIB tapes stop crossing between them.
- **LIB identity** (`STORAGE_SPEC.md` D3): a CRC of the exact ROM, patched in after assembly, so every release
  invalidates LIB tapes. Relinking and ABI versions were weighed and rejected. V1 compatibility is not required.
- **ZEsarUX.**
  - `realtape-open` resets the machine and plays at once.
  - TZX `$15` plays 54 times too slow, so tapes there are `.rwa` at 224 T a sample.
  - A held key is released while the emulator is paused.
  - Each harness has its own ZRCP port range: tapetol 10980-10999; see each tool's header.
- **Fuse 1.9.1** (`/usr/local/bin/fuse`) runs headless through `tools/fuse/fuseshim.c` (LD_PRELOAD) and
  `tools/fusedrive.py`.
  - No SDL2 dev headers are installed; `build_shim` falls back to the flatpak SDK headers with `-idirafter`.
  - The stock TS2068 ROMs are in `~/fuse-build/roms` (`FORTH_STOCK_ROMS` overrides).
  - fuse-utils `tape2wav` and `audio2tape` are installed.
- **Old-build comparisons:** `git worktree add <scratch>/old <commit> && make -C <scratch>/old`, then
  `TAPETOL_BASE=` or `TAPETEST_OLD=`.
- **z80-skills scripts** (`~/z80-skills/skills/shrink-z80/scripts`): run them with plain `python3`, not
  `python3 -I`, because they import `scan_common`.
- **Leftover lead, unchecked:** `production_reachability.py` reports `INT_GET_FRAMES` (4 B) as unreachable in the
  HOME image. Look at it in step Z.
- **CI runs `make dist`, which nothing local runs** (pandoc is not installed here). It failed on PR #2 from step R1
  on: `tools/package_dist.sh` heredocs expand `$`, so write hex as `\$A000`. Fixed in the handoff commit. For a
  local check, run `tools/package_dist.sh` with placeholder files in `build/docs/`.
- **Deferred from S:** a static storage-contract check (Leap V2 `check_storage_contract.py`).
