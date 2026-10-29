# Mode 6 removal: specification (step M6)

Decided by the owner on 2026-10-29: "drop 64 layout - remove the code, it isn't worth the effort", scope "all of Mode
6", and HIRES/NORMAL kept (they are the TS2068 high-colour mode, not Mode 6). Evidence tags as in the audit: [M]
measured, [S] source, [E] estimate. Inventory from the step E branch after item 7 (listing sizes [M], to be re-measured
on the branch this step starts from).

## 1. Why

The ROM's 64-column text and its 512-pixel graphics (`PLOT64`, `PALETTE64`) write columns 0-31 to the first display
file and 32-63 to the second (`MODE64_CHAR_ADDR_SETUP`, `GFX_PIXEL64_ADDR_SETUP`), and every test reads the screen the
same way. Nothing here can check how a real hi-res display presents those bytes: ZEsarUX's headless `save-screen`
draws only the standard screen, and there is no hardware. The owner judged the feature not worth the effort of
proving. The console, `EMIT` and the editor also carry a second code path for it, which every change has had to keep
working (the 64-column hang and room-check defects of step E lived there).

## 2. What goes (HOME [M] from the item-7 listing)

| Part | HOME B |
|---|---:|
| `kernel/mode64/mode64.asm`, the whole file (`MODE64_ON/OFF`, palette, pixel and char address set-up, put/XOR char, row copy, scrolls, clear row; 5 B of RAM at `$87BF-$87C3`) | 394 |
| `core/mode64.asm`: `64COL`, `32COL`, `PALETTE64`, `PLOT64` | 60 |
| `core/editor.asm`: the `GFX_MODE` = 2 width choice, `ED_ROW64`, the 64-column cursor and scroll branches | 65 |
| `core/print.asm` (`EMIT`): the 64-column branches, `.emit_64col`, `.advance64`/`.nextrow64` | 70 |
| **Total** | **about 589** |

EXROM: the `32COL FIRST` refusal and its message (about 23 B). With them goes the editor's ED_ROW_JP choice between
two drawers: `ED_ROW_JP` stays (the view calls it) but always holds `ED_ROW32`.

## 3. What stays

- `HIRES`/`NORMAL` (`core/hires.asm`), `GFX_SET_MODE` 0 and 1, `GFX_SET_ATTR_EXT`, the `GFX_WRITE_PIXEL` branch for
  any nonzero mode, the CLS block for mode 1, and `FILL`'s guard (`core/moregfx.asm`, any nonzero mode: the HIRES
  attribute file shares FILL's relocated scratch RAM).
- Port `$FF` handling: `GFX_SET_MODE`'s bits 0-2, the bank's bit 7, the cold-start baseline. Bits 3-5 (Mode 6's
  palette) are simply never written again.
- ULAplus `PALETTE` (`core/ulaplus.asm`): unrelated despite the name.

## 4. Changes outside the deleted code

- **Dictionary chain.** `rom/forth_boot.asm`: the chain point before `core/floatmul.asm` becomes `H_FMINUS` (was
  `H_PLOT64`; `floatmul.asm`'s header warns about this anchor). Smoke `p9` uses `DICT_LATEST_INIT_P8B`: re-pointed
  or the ROM retired with p8b.
- **Smoke ROMs retired:** `p8b` (the four words), `p56` (MODE64 primitives), `p57` (mode-aware EMIT), `p58` (the editor
  in 64 columns), `rom/mode64_visual_check.asm`; their rows in `tools/rom_list.txt` (`check_test_list` requires both
  directions). `p44` tests FILL's guard by poking `GFX_MODE` = 2: it pokes 1 (HIRES) instead.
- **Test tools.** `tools/edtest.py`: the 64-column parts of cases 8, 9, 10, 18, 19 go, case 14 (`console-64col`)
  becomes "`64COL` is an unknown word", N11 (`edit-64col`) is retired (no 64-column mode to refuse), and the
  64-column helpers go. `tools/fharness.py`: check `i` (`_check_mode64`) and the `mode64` screen reader go (the reader
  is conditional on `MODE64_PUTCHAR` today; check `i` is not and would fail).
- **Docs.** Tutorial section 13 ("A wider screen") goes and sections 14-17 renumber (anchors at the lines the
  inventory lists), the EDIT refusal row and limit bullet for 64 columns, the appendix rows for `64COL`, `32COL`,
  `PALETTE64`, `PLOT64`. Stale comments that already claim Mode 6 was removed (`kernel/graphics/graphics.asm`,
  `include/hardware.inc`, `include/sysvars.inc`) are corrected. `EDITOR_SPEC.md` E9 is superseded.

## 5. Order (one commit each)

1. This spec.
2. Oracle: the test-tool and smoke-list changes above, run on the step's starting build (the 64-column cases that now
   assert absence fail there; everything else passes).
3. The code removal, in one commit (the chain re-pointing makes a partial removal unbuildable), with the measured
   ledger row and raised floors.
4. Docs: tutorial, CHANGELOG, HANDOFF.

Done when `make edtest` (31 cases less N11, so 30), `make test`, `make harness`, `make tapetest`, `make cartdiff`,
`make fusesave`, `make bench`, `make repro` and `make check` pass.

## 6. Verification limits

ZEsarUX, Fuse and TSRun only. The removal makes the ROM 32-column only; a program that used `64COL` or `PLOT64` gets
`64COL ?` / `PLOT64 ?`.

## 7. As built [M]

Re-measured on the step's starting build (`832ac09`, `build/forth_boot.lst`): the section 2 figures held. The editor's
65 B are gross: its `ELSE` branch (`ld a, 31`, 2 B) becomes unconditional, so the editor saves 63 and the total is
**587 B** HOME (394 + 60 + 63 + 70), the same in the DOCK cartridge build; EXROM **23 B** (the refusal 10, the message
13). HOME 1,042 → 1,629 free, EXROM 4,224 → 4,247; the demo images are byte-identical (they never included the mode).

- **Removal only.** The old and new listings (HOME, cartridge, EXROM), paired line by line on their emitted source,
  differ only by deleted lines: no instruction was added or changed.
- **Spec points that did not match:** `include/exrom_home_ram.inc` held no `GFX_MODE` copy, and the 5 B of RAM at
  `$87BF-$87C3` were declared in `kernel/mode64/mode64.asm` itself, so neither needed a change elsewhere. Smoke `p9`
  stays: it seeds `LATEST` with `H_FMINUS` and no longer includes the mode's files (the oracle commit).
- **Test changes beyond the spec:** case 14 (`no-64col`) also checks that `32COL`, `PALETTE64` and `PLOT64` are unknown
  words (section 6). `make test` has 66 ROMs (70 less p8b, p56, p57, p58).
