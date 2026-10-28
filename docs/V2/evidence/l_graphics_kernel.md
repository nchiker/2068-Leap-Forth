<!-- Step L inventory, 2026-10-28: produced read-only by a delegated agent from the Forth listing at master 0d45a2f and a scratch build of Leap-C b918527 (`git archive b918527`, `make`). Paths under /tmp are that scratch area. Byte counts come from a listing sizer (per top-level label, emitted bytes); the claims that a recommendation rests on were re-checked by hand, see docs/V2/LEAPC_COMPARISON_AUDIT.md section 1. -->

# Graphics kernel inventory: Forth vs Leap-C (step L, read-only)

## Sources and method

- Forth: `/home/charlie.day/2068-forth/kernel/graphics/graphics.asm`, listing `/home/charlie.day/2068-forth/build/forth_boot.lst` (not rebuilt).
- Leap-C: `/tmp/claude-1000/-home-charlie-day-2068-forth/dfbfd3d4-c481-4774-be24-5d5057d38e7a/scratchpad/leapc/platform/kernel/graphics/graphics.asm`, home listing `.../scratchpad/leapc/build/leapc_home.lst` (the 2066 B total), exrom listing `.../scratchpad/leapc/build/leapc_exrom.lst` (used only for two routines the home build compiles out).
- Sizes: `lst_routines.py` on both listings. Totals match the expected values: Forth 2596 B (38 labels), Leap-C home 2066 B (35 labels). Each side's file has one `graphics.asm` open record, and the address span is contiguous (Forth 066D-1091 = 2596 B; Leap-C 034F-0B61 = 2066 B).
- Per-label bytes were compared from the listings' emitted hex. Address-only differences were classified mechanically (inferred): a differing instruction counts as ADDR when only its trailing 16-bit operand differs and that operand is a symbol.
- Source diffs: comment-stripped code text of each routine body, diffed with difflib.
- Build configuration that changes what the Leap-C listing contains: the home build defines `V2_PRODUCTION` and `GFX_NO_EDITOR_TEXT`; the exrom build defines `V2_PRODUCTION` and `GFX_EDITOR_TEXT_ONLY`.
  - Home build compiles out: `GFX_SCROLL_TEXT_DOWN` (source lines 286-305), `GFX_INVERT_ATTR_STATIC` (927-935), `GFX_PUTCHAR_BOLD` and `GFX_PRINT_STRING` (645-714).
  - Exrom build compiles in only `GFX_PUTCHAR_BOLD` (18 B) and `GFX_PRINT_STRING` (14 B).

## Routine table

Byte counts are from the sizer. "same" in the Leap-C column means the same name.

| Forth routine | Forth B | Leap-C routine | Leap-C B | Class | Notes |
|---|---:|---|---:|---|---|
| GFX_CLS | 18 | GFX_CLS | 15 | DIFFERS | Forth has an extra `call GFX_SPRITE_INVALIDATE` (3 B, Forth line 123). `ld a, ATTR_DEFAULT` is $44 on Forth (EQU at line 49) and $38 on Leap-C (line 52). Source otherwise identical. |
| GFX_PAINT_ATTR | 13 | GFX_PAINT_ATTR | 13 | IDENTICAL | |
| GFX_SPRITE_INVALIDATE | 11 | (none) | - | FORTH-ONLY | Clears `SPRITE_SLOT_SHOWN[0..SPRITE_SLOT_MAX-1]` and `SPRITE_DISPLAY_DEPTH`. Called from CLS, SCROLL_TEXT_UP and SET_MODE. Leap-C deleted it (commit e38a6bc, delta D6). |
| GFX_ROW_BASE_ADDR | 13 | GFX_ROW_BASE_ADDR | 13 | IDENTICAL-MODULO-ADDRESSES | Only `ld de, ROW_BASE_TABLE` differs (11 94 0D vs 11 5A 07). |
| GFX_COPY_ROW_BITMAP | 36 | GFX_COPY_ROW_BITMAP | 36 | IDENTICAL-MODULO-ADDRESSES | Differs only in RAM operands GFX_SCROLL_DST_ROW/SRC_ROW (0x8299/0x829A vs 0x5C69/0x5C6A) and the call to GFX_ROW_BASE_ADDR. |
| GFX_SCROLL_TEXT_UP | 40 | GFX_SCROLL_TEXT_UP | 37 | DIFFERS | Forth has an extra `call GFX_SPRITE_INVALIDATE` (3 B, Forth line 272). Otherwise identical. |
| GFX_SCROLL_OUTPUT_UP | 32 | GFX_SCROLL_OUTPUT_UP | 32 | IDENTICAL-MODULO-ADDRESSES | Call and jp targets and RAM operands differ. |
| GFX_SET_BORDER | 15 | GFX_SET_BORDER | 15 | IDENTICAL-MODULO-ADDRESSES | PORT_FE_SHADOW at 0x8187 (Forth) vs 0x5C09 (Leap-C). |
| GFX_CHAR_TO_FONT_OFFSET | 146 | GFX_CHAR_TO_FONT_OFFSET | 146 | DIFFERS | Source text identical. Bytes differ in `ld b, PUNCT_CHAR_COUNT` ($17 vs $1F; EQU 23 at Forth line 2185, EQU 31 at Leap-C line 1618) and in table/RAM address operands. Includes the D21 block-graphics body (36 B on both sides). |
| GFX_CHAR_SETUP | 39 | GFX_CHAR_SETUP | 39 | IDENTICAL-MODULO-ADDRESSES | Call and FONT_TABLE/ROW_BASE operands differ. |
| GFX_PUTCHAR | 15 | GFX_PUTCHAR | 15 | IDENTICAL-MODULO-ADDRESSES | Only `call GFX_CHAR_SETUP` differs. |
| (none) | - | GFX_PUTCHAR_OVER | 16 | LEAPC-ONLY | XOR-draws one glyph: GFX_CHAR_SETUP, then 8 scanlines XORed (Leap-C line 629). |
| GFX_PRINT_STRING | 14 | GFX_PRINT_STRING | 14 (exrom listing only; not in the 2066 home total) | IDENTICAL-MODULO-ADDRESSES | Matches by name. Forth 14 bytes equal the exrom copy except `call GFX_PUTCHAR` (CD D8 07 vs CD A9 04). Forth line 648. |
| (none) | - | GFX_PUTCHAR_BOLD | 18 (exrom listing only) | LEAPC-ONLY | Synthesized-bold glyph for the editor's keywords (delta D12). |
| (none) | - | GFX_PRINT_STRING_ATTR | 64 | LEAPC-ONLY | Prints a string with attribute: GFX_PUTCHAR_OVER when the OVER flag in D is set, else GFX_PUTCHAR, then GFX_SET_ATTR. Wraps at column 32 and scrolls via GFX_SCROLL_OUTPUT_UP (Leap-C line 755). No Forth routine of this name. Not the same routine as Forth's GFX_PRINT_STRING. |
| GFX_ATTR_SWAP | 26 | GFX_ATTR_SWAP | 26 | IDENTICAL-MODULO-ADDRESSES | Only the call to GFX_CELL_ATTR_ADDR differs. |
| GFX_INVERT_ATTR | 8 | GFX_INVERT_ATTR | 8 | IDENTICAL-MODULO-ADDRESSES | Only the call to GFX_ATTR_SWAP differs. |
| GFX_SET_ATTR | 11 | GFX_SET_ATTR | 11 | IDENTICAL-MODULO-ADDRESSES | Only the call to GFX_CELL_ATTR_ADDR differs. |
| GFX_SET_ATTR_EXT | 30 | GFX_SET_ATTR_EXT | 30 | IDENTICAL | |
| GFX_SET_MODE | 54 | GFX_SET_MODE | 49 | DIFFERS | Forth lines 942-944: `push af` / `call GFX_SPRITE_INVALIDATE` / `pop af` (5 B). Otherwise identical. |
| GFX_CLEAR_ROW | 23 | GFX_CLEAR_ROW | 23 | DIFFERS | Source text identical. Bytes differ at `ld a, ATTR_DEFAULT` ($44 vs $38) and the call operands. |
| GFX_PIXEL_ADDR_SETUP | 64 | GFX_PIXEL_ADDR_SETUP | 64 | IDENTICAL-MODULO-ADDRESSES | RAM operands (GFX_PIXEL_* at 0x81AB-0x81B0 vs 0x5C2E-0x5C31), BIT_MASK_TABLE and ROW_BASE operands. |
| GFX_WRITE_PIXEL | 66 | GFX_WRITE_PIXEL | 66 | IDENTICAL-MODULO-ADDRESSES | RAM operands, and jp/call targets (GFX_SET_ATTR, GFX_SET_ATTR_EXT, GFX_PIXEL_ADDR_SETUP). |
| GFX_READ_PIXEL | 10 | GFX_READ_PIXEL | 10 | IDENTICAL-MODULO-ADDRESSES | Only the call to GFX_PIXEL_ADDR_SETUP differs. |
| GFX_LINE | 207 | GFX_LINE | 206 | DIFFERS | Forth `jp .loop` (C3, 3 B; line 1362) vs Leap-C `jr .loop` (18, 2 B). The Forth comment says JP was used because the JR displacement was -126, 2 bytes from the -128 limit. Other differences are RAM and call operands. |
| GFX_PLOT_CLIPPED | 31 | GFX_PLOT_CLIPPED | 31 | IDENTICAL-MODULO-ADDRESSES | RAM operands and `jp GFX_WRITE_PIXEL`. |
| GFX_FILL_PUSH | 21 | (none) | - | FORTH-ONLY | Pushes an (x,y) seed onto GFX_FILL_STACK. |
| GFX_FILL_POP | 25 | (none) | - | FORTH-ONLY | Pops (x,y); carry set if the stack is empty. |
| GFX_FILL_VISITED_CHECK_SET | 49 | (none) | - | FORTH-ONLY | Tests and claims the visited bit for (x,y). |
| GFX_FILL_VISITED_CHECK | 43 | (none) | - | FORTH-ONLY | Read-only visited test. |
| GFX_FILL_SCAN_ROW | 108 | (none) | - | FORTH-ONLY | Scans a row span for runs to push. |
| GFX_FILL | 241 | (none) | - | FORTH-ONLY | Scanline flood fill from a seed (GFX_FILL_X/Y, GFX_FILL_ATTR). |
| GFX_CIRCLE_PLOT_OFFSET | 29 | (none) | - | FORTH-ONLY | Adds the centre to (dx,dy) and plots through GFX_PLOT_CLIPPED. |
| GFX_CIRCLE_PLOT_POLES | 54 | (none) | - | FORTH-ONLY | Plots the four distinct points at x=0. |
| GFX_CIRCLE_PLOT_GENERAL | 161 | (none) | - | FORTH-ONLY | Plots the 8-way symmetric points for x>=1. |
| GFX_CIRCLE | 124 | (none) | - | FORTH-ONLY | Circle main loop with a decision variable (midpoint-style; inferred from the header's decision-variable note). |
| BIT_MASK_TABLE | 8 | BIT_MASK_TABLE | 8 | IDENTICAL | Table. |
| PUNCT_CHAR_TABLE | 46 | PUNCT_CHAR_TABLE | 62 | DIFFERS | Table. Forth: 23 entries, `PUNCT_CHAR_COUNT EQU 23` (line 2185). Leap-C: 31 entries (`EQU 31`, line 1618). The same 23 characters keep the same font indices (63-85) in a different order, plus 8 entries (`[ ] { } | ~ ^ \`, indices 86-93). Delta D8. |
| ROW_BASE_TABLE | 48 | ROW_BASE_TABLE | 48 | IDENTICAL | Table. |
| FONT_TABLE | 688 | FONT_TABLE | 752 | DIFFERS | Table. Forth: 86 glyphs (header line 28). Leap-C: 94. Two glyphs change: '1' (D13) and 'l' (D13). Eight glyphs are added: `[ ] { } | ~ ^ \` (64 B). 688 + 64 = 752. |
| (none) | - | GFX_CELL_BITMAP_ADDR | 13 | LEAPC-ONLY | Row/col to bitmap address (scanline 0) with the same ROW_BASE_TABLE math as GFX_CHAR_SETUP. |
| GFX_CELL_ATTR_ADDR | 29 | GFX_CELL_ATTR_ADDR | 29 | IDENTICAL | |
| (none) | - | GFX_SPRITE_BOUNDS_CHECK | 28 | LEAPC-ONLY | Checks that a rectangle fits the 32x24 cell grid; shared by CAPTURE and DRAW. |
| (none) | - | GFX_SPRITE_CELL_ROWCOL | 17 | LEAPC-ONLY | Maps the current loop index to a screen cell. |
| (none) | - | GFX_SPRITE_SETUP | 28 | LEAPC-ONLY | Shared prologue: bounds check, then stages SPRITE_BUF_* variables. |
| (none) | - | GFX_SPRITE_TRANSFER | 95 | LEAPC-ONLY | Shared nested cell loop for CAPTURE and DRAW. |
| (none) | - | GFX_SPRITE_CAPTURE | 10 | LEAPC-ONLY | Saves a cell rectangle into the sprite buffer. |
| (none) | - | GFX_SPRITE_DRAW | 11 | LEAPC-ONLY | Draws a buffer back at a cell position. |

Compiled out of the Leap-C home build and not measured: `GFX_SCROLL_TEXT_DOWN` and `GFX_INVERT_ATTR_STATIC` (both under `IFNDEF V2_PRODUCTION`). Forth has neither, and its comment at line 752 says the static sibling was "removed as dead code".

### Class counts (27 name pairs)

- IDENTICAL: 5 (PAINT_ATTR, SET_ATTR_EXT, BIT_MASK_TABLE, ROW_BASE_TABLE, CELL_ATTR_ADDR).
- IDENTICAL-MODULO-ADDRESSES: 14 (includes PRINT_STRING, paired with the exrom copy).
- DIFFERS: 8 (CLS, SCROLL_TEXT_UP, CHAR_TO_FONT_OFFSET, SET_MODE, CLEAR_ROW, LINE, PUNCT_CHAR_TABLE, FONT_TABLE).
- FORTH-ONLY: 11 routines, 866 B.
- LEAPC-ONLY (home build): 9 routines, 282 B. Plus GFX_PUTCHAR_BOLD (18 B, exrom only).

Reconciliation: Forth 2596 = paired 1716 + Forth-only 880 (866 + PRINT_STRING 14). Leap-C 2066 = paired 1784 + Leap-C-only 282. Paired difference (Forth - Leap-C) = -68. Overall 2596 - 2066 = 530.

### Five largest byte differences (paired)

1. FONT_TABLE: Leap-C +64 (688 vs 752).
2. PUNCT_CHAR_TABLE: Leap-C +16 (46 vs 62).
3. GFX_SET_MODE: Forth +5 (54 vs 49).
4. GFX_CLS: Forth +3 (18 vs 15).
5. GFX_SCROLL_TEXT_UP: Forth +3 (40 vs 37).

One-sided: the largest Forth-only routine is GFX_FILL (241 B); the largest Leap-C-only routine is GFX_SPRITE_TRANSFER (95 B).

### Font and glyph data (separate from code)

| | Forth | Leap-C (home) |
|---|---:|---:|
| FONT_TABLE | 688 | 752 |
| PUNCT_CHAR_TABLE | 46 | 62 |
| Font/glyph total | 734 | 814 |
| BIT_MASK_TABLE + ROW_BASE_TABLE (tables, not glyphs) | 56 | 56 |
| Code (everything else) | 1806 | 1196 |

## Delta section (UPSTREAM.md, D1-D21)

Deltas whose file column names `kernel/graphics/graphics.asm`: D6, D8, D12, D13, D21. None of the other sixteen names that file (see the end of this section).

### D6 (deletions, 25 B): GFX_SPRITE_INVALIDATE and its calls

- Leap-C change: deletes GFX_SPRITE_INVALIDATE and its calls in GFX_CLS, GFX_SCROLL_TEXT_UP, GFX_SCROLL_TEXT_DOWN and GFX_SET_MODE.
- Forth: not applied. Forth still has the routine (line 178) and all three live call sites:
  - line 122-123: `GFX_CLS:` then `call GFX_SPRITE_INVALIDATE`
  - line 271-272: `GFX_SCROLL_TEXT_UP:` then `call GFX_SPRITE_INVALIDATE`
  - line 941-944: `GFX_SET_MODE:` then `push af` / `call GFX_SPRITE_INVALIDATE` / `pop af`
- Forth has no GFX_SCROLL_TEXT_DOWN. The 25 B figure therefore counts 3 B of a routine Forth does not have. The bytes Forth still carries that D6 removes are 3 + 3 + 5 + 11 = 22 B (inferred from the sizes).

### D8 (+8 punctuation entries, +8 glyphs, GFX_CLEAR_ROW_TEXT deleted, header count)

- Leap-C change: PUNCT_CHAR_TABLE gets 8 entries (indices 86-93) and is reordered by C frequency. FONT_TABLE gets 8 glyphs (64 B). GFX_CLEAR_ROW_TEXT is deleted (16 B). The header glyph count changes.
- Forth: not applied for the table or glyphs. Forth line 28: `(86 glyphs total: " ! @ # $ % & ' ( ) _ : . , = + - ; / * < > ?)`. Forth line 2185: `PUNCT_CHAR_COUNT EQU 23`. The Forth punctuation table starts `DB '"', 63`, the V2 order, and has none of the eight added characters.
- GFX_CLEAR_ROW_TEXT: absent from Forth graphics.asm (grep finds no match). Whether it was ever in the Forth code was not checked (inferred: it is not in this file).

### D12 (conditional assembly only)

- Leap-C change: `IFNDEF GFX_NO_EDITOR_TEXT` around GFX_PUTCHAR_BOLD and GFX_PRINT_STRING, and `IFNDEF GFX_EDITOR_TEXT_ONLY` around the rest.
- Forth: not applied. Forth graphics.asm has no IF/IFNDEF/ENDIF at all (grep count 0). Forth GFX_PRINT_STRING (line 648) is unconditional. Forth has no GFX_PUTCHAR_BOLD.

### D13 (FONT_TABLE: '1' and 'l' glyphs; no size change)

- Leap-C change: '1' becomes `$20,$60,$A0,$20,$20,$20,$F8,$00` (Leap-C line 1641). 'l' becomes `$60,$20,$20,$20,$20,$20,$18,$00` (Leap-C line 1735).
- Forth: not applied. Forth line 2208-2209: `; '1'` / `DB   $20, $60, $20, $20, $20, $20, $70, $00`. Forth line 2302-2303: `; 'l'` / `DB   $60, $20, $20, $20, $20, $20, $70, $00`. These are the V2 forms that D13 replaced.

### D21 (GFX_CHAR_TO_FONT_OFFSET.is_block_graphics rewritten, clean-room, 36 B)

- Leap-C change: V2's 54-line body replaced by a 36 B clean-room body.
- Forth: applied. Forth line 476 says: `Body from 2068-Leap-C delta D21, written clean-room from the screen format alone`. Forth `.is_block_graphics` (line 467) measures 36 B from the listing, the same as Leap-C (36 B). The comment-stripped source text of GFX_CHAR_TO_FONT_OFFSET is identical on both sides.

### Other deltas (do not name graphics.asm)

D1 (include/sysvars.inc), D2 and D5 and D11 (kernel/memory/memory.asm), D3 (kernel/math/math.asm), D4 and D14 (interrupt and bank), D7 (kernel/io/io.asm), D9, D18 and D20 (kernel/storage/storage.asm), D10 (rom/exrom_format.asm), D15, D16 and D17 (rom/exrom_editor.asm; D17 also rom/v2_ay_beep.asm), D19 (rom/exrom_sound.asm). Not checked against Forth.

## Fix section (Leap-C git log, platform/kernel/graphics)

`git -C /home/charlie.day/2068-Leap-C log --oneline -- platform/kernel/graphics` lists six commits, all on the graphics path. Only one looks like a bug fix. Commit subjects are phase names, so the classification is mine (inferred from messages and diffs).

| Commit | Subject | Graphics routine(s) touched | Bug fix? | Forth has the same change? |
|---|---|---|---|---|
| 5a8e35b | M1.1: foundation and lexer | whole file (import) | No (import) | n/a |
| e38a6bc | Phase 4: memory layout, banking and capacity | GFX_CLS, GFX_SCROLL_TEXT_UP, GFX_SCROLL_TEXT_DOWN, GFX_SET_MODE, GFX_SPRITE_INVALIDATE (D6) | No: "budget protocol", removes dead V2 stores | No (see D6) |
| fe8147b | Phase 5: editor and C punctuation | PUNCT_CHAR_TABLE, FONT_TABLE, GFX_CLEAR_ROW_TEXT (D8) | No: C character set, plus removal of an unused routine | No (see D8) |
| 7e46991 | Phase 8: floating point, language and library completion | conditional blocks around GFX_PUTCHAR_OVER/BOLD/PRINT_STRING (D12) | No: conditional assembly for budgets | No (see D12) |
| f209f21 | Phase 9: emulator qualification, power-on RAM, ROM coverage, hardware kit | FONT_TABLE '1' and 'l' (D13) | Yes: a glyph correction. The message says the owner approved it because '1' and 'l' were distinct in the editor. The other "defects found and fixed" in this commit (UDG table, SH_WAIT_KEY, float IRQ loss) are not in the graphics file. | No (see below) |
| d31d785 | Phase 11 (M11-tape): clean-room tape block I/O and block-graphics glyph | GFX_CHAR_TO_FONT_OFFSET.is_block_graphics (D21) | No: a licensing rewrite with the same contract and glyphs | Yes (see D21) |

### f209f21 (the one fix candidate): Forth lacks it

- Leap-C change: `'1'` changes byte index 2 ($20 -> $A0) and index 6 ($70 -> $F8), 0-based. `'l'` changes byte index 6 ($70 -> $18). Three bytes of data changed; no size change.
- Forth: has the pre-fix glyphs. Forth line 2208-2209: `DB   $20, $60, $20, $20, $20, $20, $70, $00` under `; '1'`. Forth line 2302-2303: `DB   $60, $20, $20, $20, $20, $20, $70, $00` under `; 'l'`.
- Consequence (computed from the Forth bytes): on Forth, '1' and 'l' differ in exactly two pixels, row 0 and row 1 at column 1 (the bit $40). '1' has that pixel in row 1 and 'l' in row 0. Leap-C's D13 change is what makes them distinct; Forth still has the pre-fix pair.

## Anything I could not determine

- The sizes of `GFX_SCROLL_TEXT_DOWN` and `GFX_INVERT_ATTR_STATIC` (compiled out under V2_PRODUCTION in both Leap-C builds) are not measured. Building them was not permitted.
- The removal of the FILL/CIRCLE code. `platform/kernel/graphics/graphics.asm:1561-1565` says `GFX_FILL...` and `GFX_CIRCLE...` were "all removed 2026-09-19 (Phase 0 P0.4)" and moved to `rom/extensions/shapes.asm`. That removal does not appear in the six graphics-path commits, UPSTREAM.md has no delta for it, and `git log -S "GFX_CIRCLE_PLOT_GENERAL:"` finds no commit. The file at 5a8e35b already lacks those routines. Which commit or step removed them is not determined.
- Where Forth implements SPRITE capture and draw. Forth's graphics.asm has none of the GFX_SPRITE_CAPTURE/DRAW/TRANSFER routines. Forth files under core/ and include/ reference the names, but I did not trace where they are defined.
- Whether Forth's `ATTR_DEFAULT` of $44 was intentional. Leap-C's $38 has been unchanged since the import (`git log -S "ATTR_DEFAULT EQU"` returns only 5a8e35b), and no UPSTREAM delta names ATTR_DEFAULT. The Forth comment at line 49 gives the value's meaning (PAPER 0, INK 4, BRIGHT 1). Whether it is a deliberate Forth choice is not determined.
- Whether Forth ever had GFX_CLEAR_ROW_TEXT. The Forth repository history was not queried.
- Whether Forth's GFX_PRINT_STRING serves the same callers as Leap-C's GFX_PRINT_STRING_ATTR. The Forth routine has no attribute or OVER handling.
- The ADDR classification is a symbol-operand heuristic (inferred). The RAM addresses differ between the two builds (Forth 0x81xx range, Leap-C 0x5Cxx range). I did not check either sysvars map.
- The FILL and CIRCLE descriptions are one-line summaries from the headers, not verified against a reference.
