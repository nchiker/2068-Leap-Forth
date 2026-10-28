<!-- Step L inventory, 2026-10-28: produced read-only by a delegated agent from the Forth listing at master 0d45a2f and a scratch build of Leap-C b918527 (`git archive b918527`, `make`). Paths under /tmp are that scratch area. Byte counts come from a listing sizer (per top-level label, emitted bytes); the claims that a recommendation rests on were re-checked by hand, see docs/V2/LEAPC_COMPARISON_AUDIT.md section 1. -->

# Medium-module audit: Forth vs Leap-C, routine by routine (read-only)

Scope: four Forth modules in `/home/charlie.day/2068-forth` mapped to their nearest Leap-C routines in `/home/charlie.day/2068-Leap-C` (commit b918527). Nothing in either repository was edited, built or committed.

## 0. Method and conventions

- **Forth bytes:** `build/forth_boot.lst` as it exists (built 18:19; not rebuilt). Sizer: `scratchpad/lst_routines.py`.
- **Leap-C bytes:** `scratchpad/leapc/build/leapc_home.lst` (HOME build of b918527).
- **Basename collisions:** the listings record only basenames. Within the file sets below, each basename appears once in its listing (`io.asm`, `interrupt.asm`, `graphics.asm`, `library.asm`, `home.asm`, `helpers.asm` in Leap-C; the Forth core files and kernel `io.asm`/`interrupt.asm`/`graphics.asm`). Duplicated basenames exist but none is in these sets. Forth: `sysvars.inc`, `hardware.inc`, `keys.inc`, `tapeword.asm`, `storage.asm`, `mode64.asm`. Leap-C: `sysvars.inc`, `hardware.inc`, `keys.inc`, `leapc_decl.inc`.
- **Forth "B" = H + W.** An H_ label's bytes are the dictionary header (`DW` link, `DB` length, name). A W_ label's bytes are the code, including helper routines in the same file. Each Forth row gives `B (hdr/code)`.
- **Leap-C routines** are the sizer's label spans. Entry labels that share one body are grouped; the group total is stated and the grouping is in Notes. `LIB_ARGS` (26 B, the argument loader) is shared by most library functions and is not counted in any row.
- **Relationship labels.** IDENTICAL = same bytes. IDENTICAL SOURCE = same source text, bytes differ only in 16-bit address operands (verified by byte dump, see Section 4). SAME ALGO, DIFF CODE = same steps, different encoding or wrapper. SAME JOB, DIFF ALGO = same purpose, different steps or behaviour (I added this label because the four labels did not fit many rows). DIFFERENT JOB. NO COUNTERPART (in HOME).
- **Behaviour statements** come from reading source. Nothing was run; no emulator was used.
- **Sizer cross-check:** a second copy of the sizer, `scratchpad/L/lst_routines_fixed.py`, was already present in the scratch folder (I did not create it). It gives identical totals for every file in these four modules, so the numbers are not sensitive to its truncated-DB handling. I did not use its other outputs.

## 1. File-set reconciliation

| Module | Audit claim | Files counted | Measured (sum of file totals) | Result |
|---|---|---|---|---|
| 1 Graphics words | 766 | core/ts2068 172, color 115, moregfx 59, hires 28, rectfill 82, polygon 116, sprite 114, ulaplus 60, udg 20 | **766** | exact |
| 2 Strings | 989 | core/string 455, core/stringext 446 | **901** | **88 B unexplained** |
| 3 Output words | 327 | core/print 264, core/outwords 63 | **327** | exact |
| 4 Keyboard and interrupt | 625 | kernel/io/io.asm 481, kernel/interrupt/interrupt.asm 144 | **625** | exact |

Module 2 gap: the only single file in the Forth listing with exactly 88 bytes is `core/dotquote.asm` (the `."` word). Adding it gives 989. This is an inference, not confirmed. I found no other single-file or pair match that is more natural, and I did not check the audit's own source for its file set.

Forth totals by part (for the header/code split): Module 1 headers 203, code 563. Module 2 headers 108, code 793. Module 3 headers 33, code 294 (UDIV10 counted as code). Module 4 has no dictionary headers (625 code).

Leap-C totals for the counterpart sets: library.asm 1281 (whole file; set sums are in each table), io.asm 415, interrupt.asm 148, home.asm `IO_KEY_SCAN_ROW` 3, helpers.asm `RT_UDIV` 31, rtexit.asm `RT_BREAKREQ` 31 (+ `RT_BREAK` 3, `RT_BREAKAT` 5).

## 2. Module 1: graphics words (Forth 766 B)

Leap-C kernel callees (HOME `kernel/graphics/graphics.asm`, sizes from the listing): GFX_PLOT_CLIPPED 31, GFX_WRITE_PIXEL 66, GFX_LINE 206, GFX_SET_BORDER 15, GFX_CLS 15, GFX_PAINT_ATTR 13, GFX_SET_MODE 49, GFX_SPRITE_* (see table). Forth kernel sizes for the same names: GFX_LINE 207, GFX_CLS 18, GFX_SET_MODE 54, GFX_PAINT_ATTR 13 (identical bytes), GFX_WRITE_PIXEL 66, GFX_PLOT_CLIPPED 31, GFX_SET_BORDER 15.

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| PLOT (ts2068) | 24 (7/17) | Pixel at (x,y) in CURRENT_ATTR; pops y then x, keeps low bytes, calls GFX_WRITE_PIXEL with OVER=0 | LIB_PLOT + LIB_PLOT_HL | 13 (3+10) | SAME JOB, DIFF ALGO | Leap: `call LIB_ARGS`, then LIB_OVATTR (print attr, over flag), then GFX_PLOT_CLIPPED (31) which drops off-screen points (`cp 192 / ret nc`) before GFX_WRITE_PIXEL (66). Forth has no clip: W_PLOT passes raw y to GFX_WRITE_PIXEL, whose header says "C = y (0-191, caller clamps)". Source reading only. |
| LINE (ts2068) | 49 (7/42) | Line (x0,y0)-(x1,y1) in CURRENT_ATTR, OVER forced to 0; stores low bytes into GFX_LINE_* then GFX_LINE | LIB_DRAW + LIB_CLAMPX + LIB_CLAMPY | 63 (46+11+6) | SAME JOB, DIFF ALGO | Leap clamps each coordinate (x to 0-255, y to 0-191, via HL/A tests) and takes OVER from over(); Forth sets GFX_LINE_OVER=0 always and truncates to 8 bits. Both call GFX_LINE (207 Forth / 206 Leap). |
| CIRCLE (ts2068) | 44 (9/35) | Circle (x,y,r) in CURRENT_ATTR via GFX_CIRCLE | none in HOME | - | NO COUNTERPART | Leap-C has circle only in the loadable library `libs/shapes.asm` (label `circle:`), not in the HOME listing. Not measured (inferred nearest). |
| BORDER (ts2068) | 17 (9/8) | Border colour from TOS; `call GFX_SET_BORDER` | LIB_BORDER | 7 | SAME ALGO, DIFF CODE | Both end in GFX_SET_BORDER (15 B each). Leap: `call LIB_ARGS`, `jp GFX_SET_BORDER`. Forth: DPOP, `call`. Kernel bytes differ only in the border-cell address operand (Leap `3A 09 5C` / `32 09 5C`, Forth `3A 87 81` / `32 87 81`). |
| CLS (ts2068) | 38 (6/32) | GFX_CLS; GFX_PAINT_ATTR with CURRENT_ATTR; if mode 1, fills $6000-$77FF (6144 B) with CURRENT_ATTR; resets PRINT_ROW/COL | LIB_CLS | 14 | SAME JOB, DIFF ALGO | Leap: GFX_CLS (15) + GFX_PAINT_ATTR (13) + `ld (LIB_COL),bc`. Leap LIB_CLS has no mode-1 branch and GFX_CLS (Leap) works on SCREEN_ADDR and does not reference $6000, so the second display is not cleared (source reading). Leap GFX_CLS is 15 B vs Forth 18 B (Leap deleted the sprite-invalidate call, delta D6). GFX_PAINT_ATTR is IDENTICAL bytes on both sides. |
| INK (color) | 23 (6/17) | ink = TOS & 7 into CURRENT_ATTR | LIB_INK (group LIB_INK+PAPER+BRIGHT+FLASH) | 34 (3+3+3+25) | SAME JOB, DIFF ALGO | Leap group writes LIB_ATTR (print attribute) through a shared body in LIB_FLASH (`ex af,af'`, `call LIB_ARGS`, shift loop). `DB $01` after `ld a,n` swallows the next `cp`. Both mask n & 7. |
| PAPER (color) | 28 (8/20) | paper = (TOS & 7) << 3 into CURRENT_ATTR | LIB_PAPER (group, above) | 34 | SAME JOB, DIFF ALGO | As INK. Forth shifts by three `add a,a`; Leap aligns the mask with a loop. |
| BRIGHT (color) | 32 (9/23) | bright = (TOS & 1) << 6 | LIB_BRIGHT (group, above) | 34 | SAME JOB, DIFF ALGO | Both mask n & 1. Forth shifts six times. |
| FLASH (color) | 32 (8/24) | flash = (TOS & 1) << 7 | LIB_FLASH (group, above) | 34 | SAME JOB, DIFF ALGO | Both mask n & 1. Forth shifts seven times. |
| FILL (moregfx) | 36 (7/29) | Flood fill from seed (x,y) with CURRENT_ATTR via GFX_FILL (HOME kernel, 241 B) | none | - | NO COUNTERPART | Leap-C has no GFX_FILL and no fill library function. |
| ATXY (moregfx) | 23 (8/15) | AT-XY ( col row -- ): sets PRINT_COL and PRINT_ROW, no range check | LIB_AT (+ LIB_TAB/LIB_TABL for column only) | 16 (+10) | SAME JOB, DIFF ALGO | Leap: row >= 24 becomes 23, column & 31. Forth: no check (header says so). Stack order: Forth ( col row ), C at(row,col). LIB_AT is in module 3's Leap set, listed here for the cursor job. |
| HIRES (hires) | 14 (8/6) | `ld a,1; call GFX_SET_MODE` | LIB_MODE (n=1 path) | 45 (shared with NORMAL) | SAME JOB, DIFF ALGO | Leap mode(1) first checks image region 4 (IMG_LIM limits) and raises RT_LIBERR / RTE_HIRES if it is in use, then GFX_SET_MODE. Forth has no such check (source reading). |
| NORMAL (hires) | 14 (9/5) | `xor a; call GFX_SET_MODE` | LIB_MODE (n=0 path, `jp z, GFX_SET_MODE`) | 45 (shared) | SAME JOB, DIFF ALGO | Leap checks n is 0 or 1 first (`RT_ERR_ARG` otherwise). Forth takes no argument. |
| RECT (rectfill) | 48 (7/41) | RECT ( x0 y0 x1 y1 -- ): stores coords, calls EXROM slot 0 at $A000 through EXROM_CALL_SLOT | none in HOME | - | NO COUNTERPART | Body is in the EXROM (not in forth_boot.lst; not measured). Leap-C `libs/shapes.asm` has `box:` (loadable library; not measured). Helpers EXROM_CALL_SLOT 32 and CALL_HL 2 are in this file's total. |
| POLYGON (polygon) | 27 (10/17) | POLYGON ( x1 y1 ... xn yn n -- ): pops vertices via POLY_POP_VERTICES, calls EXROM slot 1 | none | - | NO COUNTERPART | Body in EXROM, not measured. POLY_POP_VERTICES (57 B, below) is the shared vertex pop. |
| POLYGON-FILL (polygon) | 32 (15/17) | Same vertices, EXROM slot 5 | none | - | NO COUNTERPART | As POLYGON. |
| POLY_POP_VERTICES (polygon, helper) | 57 | Pops n (3..POLY_MAXPTS) then n coordinate pairs into POLY_VERTS; carry on bad count | none | - | NO COUNTERPART | Helper row. |
| SPRITE-DEFINE (sprite) | 44 (16/28) | ( slot row col -- ): stores three values, calls EXROM slot 2 | LIB_SPGET / LIB_SPPUT (nearest) | 2 / 36 | DIFFERENT JOB | Forth sprites are numbered slots in the EXROM (capture the screen at row,col). Leap sprite_get/sprite_put copy w x h cells between the screen and a caller buffer (`GFX_SPRITE_CAPTURE` / `GFX_SPRITE_DRAW`). Forth body not measured. |
| SPRITE-SHOW (sprite) | 42 (14/28) | ( slot row col -- ): EXROM slot 3 | LIB_SPPUT (nearest) | 36 | DIFFERENT JOB | As SPRITE-DEFINE. |
| SPRITE-HIDE (sprite) | 28 (14/14) | ( slot -- ): EXROM slot 4 | none | - | DIFFERENT JOB | No Leap-C slot hide; nearest is LIB_SPPUT (put). |
| ULAPLUS (ulaplus) | 29 (10/19) | ULA+ mode-group select with bit 0 of TOS to PORT_ULAPLUS_DATA | none | - | NO COUNTERPART | Leap-C has no ULA+ code (grep of src/platform/include found none). |
| PALETTE (ulaplus) | 31 (10/21) | ULA+ palette-entry write | none | - | NO COUNTERPART | As ULAPLUS. |
| UDG (udg) | 20 (6/14) | ( n -- addr ): UDG_TABLE + 8n | none | - | NO COUNTERPART | |

Module 1 counts: 22 Forth words (+3 helper rows). With a Leap-C counterpart of any kind: 11 words (PLOT, LINE, BORDER, CLS, INK, PAPER, BRIGHT, FLASH, ATXY, HIRES, NORMAL), plus 3 DIFFERENT JOB sprite words. No counterpart: CIRCLE, FILL, RECT, POLYGON, POLYGON-FILL, ULAPLUS, PALETTE, UDG, and helpers POLY_POP_VERTICES, EXROM_CALL_SLOT, CALL_HL.

Leap-C routines in the module 1 set with no Forth counterpart: LIB_POINT (19 + LIB_RET0 3 = 22, with GFX_READ_PIXEL 10 in kernel), LIB_ATTRF (17, with GFX_CELL_ATTR_ADDR 13), LIB_SPGET (2, sprite_get). LIB_SPPUT (36) has only a DIFFERENT JOB partner (SPRITE-SHOW). Forth has no POINT or ATTR word (grep of core/ and kernel/ for their names found no dictionary entry).

## 3. Module 2: strings (Forth 901 B, audit 989 B)

Leap-C set sizes: LIB_STRLEN 13 (3+LIB_STRLEN0 10, CPIR), LIB_STRCPY 14 (5+7+LIB_RETD 2), LIB_STRCAT 13, LIB_STRNCPY 19, LIB_MEMSET 14 (MEM_FILL), LIB_MEMMOVE 23 (LIB_MEMCPY is the same address and body), LIB_STRCHR 13 (10+LIB_NULL 3), LIB_STRCMP 21 (14+LIB_CMPNE 7), LIB_MEMCMP 16, LIB_RETA 4 (shared with STRCMP, MEMCMP, PUTCHAR).

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| S" (string.asm) | 87 (5/82) | IMMEDIATE; compiles CALL DOSSTR and the literal bytes; interpreted, leaves addr len | none in library.asm | - | NO COUNTERPART | Literal handling is in the Leap-C compiler, not checked. |
| DOSSTR (string.asm, helper) | 30 | Runtime for S": pops return address, pushes addr and len from inline count byte | none | - | NO COUNTERPART | |
| TYPE (string.asm) | 36 (7/29) | (addr len -- ): W_EMIT per byte | LIB_PRINT (3) + LIB_PUTS0 (11) (print family, module 3) | 14 | SAME JOB, DIFF ALGO | Counted string vs NUL-terminated string. Forth loop calls W_EMIT (157 B word); Leap loop calls LIB_PUTC (26). Cross-reference to module 3. |
| STRING (string.asm) | 105 (9/96) | Defining word: STRING n "name" makes a header plus n zeroed bytes (compile-time) | none | - | NO COUNTERPART | |
| PLACE (string.asm) | 36 (8/28) | (addr len dest -- ): copies counted string (len byte + chars) | LIB_STRCPY (+ LIB_RETD) | 14 | SAME JOB, DIFF ALGO | Forth copies count bytes; Leap copies until NUL and includes the NUL. Leap returns dest. Forth returns nothing. |
| COUNT (string.asm) | 23 (8/15) | (caddr -- addr len): reads count byte | none | - | NO COUNTERPART | C strings have no count byte. |
| LEN (string.asm) | 17 (6/11) | (caddr -- n): reads count byte | LIB_STRLEN (3) + LIB_STRLEN0 (10) | 13 | SAME JOB, DIFF ALGO | Forth O(1) count read (max 255). Leap CPIR scan to NUL, unbounded. |
| VAL (string.asm) | 121 (6/115) | (addr len -- n): optional leading '-' only, then decimal digits; any other character or empty string gives 0 | LIB_ATOI | 54 | SAME JOB, DIFF ALGO | Behaviour differs (source): VAL " 12" = 0, ATOI " 12" = 12 (ATOI skips leading control characters and spaces); VAL "+5" = 0, ATOI "+5" = 5; VAL "12x" = 0, ATOI "12x" = 12 (ATOI stops at the first non-digit). Both wrap at 16 bits. |
| CHR (stringext.asm) | 26 (6/20) | (code -- addr len): one-char string in CHR_BUF | none | - | NO COUNTERPART | |
| STR (stringext.asm) | 76 (6/70) | (n -- addr len): signed decimal text in STR_BUF using UDIV10 | LIB_ITOA (16) + LIB_ITOAS (21) + LIB_UTOA (37) | 74 | SAME ALGO, DIFF CODE | Both: repeated division with remainder, digits in reverse order. Forth fixed /10 (UDIV10, print.asm); Leap RT_UDIV (helpers.asm, 31 B) general divisor, base 2-36, NUL-terminated buffer, returns buf. Leap's group is module 3's set. |
| UPPER (stringext.asm) | 40 (8/32) | Uppercase in place via IX descriptor | none | - | NO COUNTERPART | |
| LOWER (stringext.asm) | 40 (8/32) | Lowercase in place via IX descriptor | none | - | NO COUNTERPART | |
| LEFT (stringext.asm) | 25 (7/18) | Truncate descriptor to n | none | - | NO COUNTERPART | |
| RIGHT (stringext.asm) | 45 (8/37) | Keep last n characters | none | - | NO COUNTERPART | |
| SEARCH (stringext.asm) | 173 (9/164) | ( addr1 len1 addr2 len2 -- ...): substring search (INSTR) | LIB_STRCHR (10) + LIB_NULL (3) | 13 | DIFFERENT JOB | strchr finds one character; SEARCH finds a substring. Nearest only. |
| CODE (stringext.asm) | 21 (7/14) | (addr len -- code): first character's byte (`DROP C@`) | none | - | NO COUNTERPART | |

Module 2 counts: 16 rows (15 words + DOSSTR). With a counterpart: TYPE, PLACE, LEN, VAL, STR (SAME JOB or SAME ALGO), SEARCH (DIFFERENT JOB). No counterpart: S", DOSSTR, STRING, COUNT, CHR, UPPER, LOWER, LEFT, RIGHT, CODE.

Leap-C routines in the module 2 set with no Forth counterpart: LIB_STRCAT 13, LIB_STRNCPY 19, LIB_MEMSET 14, LIB_MEMMOVE/LIB_MEMCPY 23, LIB_STRCMP 21, LIB_MEMCMP 16. LIB_STRCHR is listed only as the nearest partner of SEARCH, and LIB_RETA 4 is shared. LIB_MEMMOVE/MEMCPY share one body (MEM_SHIFT_UP/DOWN in HOME memory.asm).

## 4. Module 3: output words (Forth 327 B)

Leap-C set (print family, requested names first): LIB_PRINT 14 (3+11), LIB_ITOA 16, LIB_UTOA 37, LIB_PRINTF 202, LIB_AT 16, LIB_TAB 10 (3+7). Supporting: LIB_ITOAS 21, LIB_PUTC 26, LIB_NEWLINE 23, LIB_PUTS 10, LIB_PUTCHAR 4, LIB_PUTCA 5, LIB_BACK 12, LIB_OVATTR 16. The requested six sum to 295, or 316 with ITOAS.

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| UDIV10 (print.asm, helper) | 15 | HL = HL / 10, A = remainder; restoring, 16 steps | RT_UDIV (helpers.asm, outside the set) | 31 | SAME ALGO, DIFF CODE | Both restoring 16-step division. RT_UDIV takes any divisor in BC and returns HL = quotient, DE = remainder. Leap's LIB_UTOA/ITOAS call it. |
| EMIT (print.asm) | 164 (7/157) | Prints one character at PRINT_ROW/COL: GFX_PUTCHAR and GFX_SET_ATTR(CURRENT_ATTR); mode 2 uses MODE64_PUTCHAR; code 13 = newline; wraps at column 32; scrolls at row 23 (GFX_SCROLL_TEXT_UP) | LIB_PUTC (+ LIB_PUTCHAR 4) | 30 | SAME JOB, DIFF ALGO | Leap: code 10 = newline (LIB_NEWLINE 23); other characters through GFX_PRINT_STRING_ATTR (64, HOME) with LIB_OVATTR (16) for attribute and over. Forth's newline is 13; Leap's is 10. Forth's 157 B includes the MODE64 branch under IFDEF. |
| . (dot) (print.asm) | 85 (4/81) | Prints signed decimal and one trailing space (via W_EMIT) | LIB_ITOA (16) + LIB_ITOAS (21) + LIB_UTOA (37) | 74 | SAME JOB, DIFF ALGO | Leap returns a buffer (no output, no trailing space), base 2-36. Forth prints digits by EMIT. Forth's digits come from UDIV10; Leap's from RT_UDIV. |
| CR (outwords.asm) | 15 (5/10) | EMIT 13 (newline) | LIB_NEWLINE | 23 | SAME JOB, DIFF ALGO | Leap LIB_NEWLINE moves LIB_COL/ROW itself and scrolls with GFX_SCROLL_OUTPUT_UP (32). Forth goes through EMIT. |
| SPACE (outwords.asm) | 18 (8/10) | EMIT 32 | none | - | NO COUNTERPART | Leap prints spaces with LIB_PUTC inside LIB_PRINTF's padding loop. |
| SPACES (outwords.asm) | 30 (9/21) | Loop calling SPACE n times | none | - | NO COUNTERPART | LIB_PRINTF's `.pad` loop does a similar job inside its 202 B. |

Module 3 counts: 6 rows (5 words + UDIV10). With a counterpart: EMIT, ., CR; UDIV10 has an outside-set counterpart (RT_UDIV). No counterpart: SPACE, SPACES.

Leap-C routines in the module 3 set with no Forth counterpart: LIB_PRINTF 202 (`%d %u %x %c %s %f %%` with width; %f uses the float core F_X), LIB_AT 16 (Forth's AT-XY is in module 1), LIB_TAB 10, LIB_PUTS 10 (puts adds newline), LIB_PUTCHAR 4, LIB_PUTCA 5, LIB_BACK 12, LIB_OVATTR 16 (note: LIB_PRINT matches TYPE in module 2).

## 5. Module 4: keyboard and interrupt kernel (Forth 625 B)

Leap-C set: io.asm 415 + interrupt.asm 148 + home.asm IO_KEY_SCAN_ROW 3 = **566**. Forth 625 = io.asm 481 (includes its own IO_KEY_SCAN_ROW 3) + interrupt.asm 144.

Byte comparison method: each same-named label was dumped from both listings (`scratchpad/L/bytes_dump.py`) and compared position by position (`scratchpad/L/cmp.py`). Diff positions that come in 16-bit pairs are address operands (for example ld hl,IO_SCAN_TABLE). The sources were also diffed on comment-stripped code (`scratchpad/L/strip.py`).

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| IO_KEY_SCAN_ROW (io.asm) | 3 | `in a,(PORT_ULA)` then ret: reads one matrix row (A = row select) | IO_KEY_SCAN_ROW (home.asm, page zero $0004) | 3 | IDENTICAL | Bytes DB FE C9 on both sides. Leap-C places it in page zero under V2_PRODUCTION (io.asm's copy is IFNDEF'd). |
| IO_KEY_SCAN_ALL (io.asm) | 30 | Scans 8 rows into IO_SCAN_TABLE | IO_KEY_SCAN_ALL (io.asm) | 30 | IDENTICAL SOURCE | Source diff empty. Bytes differ at positions 1-2, 10-11, 18-19, 27-28 (ld hl,IO_SCAN_TABLE; ld hl,ROW_TABLE; etc.). |
| IO_FIND_KEY (io.asm) | 90 | Finds the one pressed (row,bit), or none, or ambiguous; returns B=row, C=bit, carry | IO_FIND_KEY (io.asm) | 90 | IDENTICAL SOURCE | Bytes differ at 1-2 only (IO_SCAN_TABLE address). |
| IO_KEY_STILL_DOWN (io.asm) | 28 | Tests one (row,bit) still held | IO_KEY_STILL_DOWN (io.asm) | 28 | IDENTICAL SOURCE | Bytes differ at 1-2 only. |
| IO_DECODE_KEY (io.asm) | 132 | (row,bit) plus CAPS/SYMBOL SHIFT state to key code | IO_DECODE_KEY (io.asm) | 114 | SAME ALGO, DIFF CODE | Same decision tree. Forth copies the "row*5+bit" table lookup three times (upper, symbol, plain); Leap shares it at `.table_lookup` (`jr`). Leap's symbol table differs (D7, Section 6). Forth has no SYMBOL SHIFT + A/S error-navigation branch (none in kernel/io), matching the code removal in D7. |
| IO_LATCH_AND_CLEAR (io.asm) | 10 | Returns KBD_LASTK and clears KBD_KEYHIT | IO_LATCH_AND_CLEAR (io.asm) | 10 | IDENTICAL SOURCE | Bytes differ at 1-2 and 6-7 (sysvar addresses). |
| IO_READ_KEY (io.asm) | 8 | Waits for KBD_KEYHIT, then latches (KEY) | IO_READ_KEY (io.asm) | 8 | IDENTICAL SOURCE | Bytes differ at 1-2 only. |
| IO_KEY_AVAILABLE (io.asm) | 4 | Returns KBD_KEYHIT without clearing (KEY?, non-consuming) | IO_READ_KEY_NONBLOCK (io.asm) | 7 | DIFFERENT JOB | Leap's version consumes: `or a / ret z / jr IO_LATCH_AND_CLEAR`, so it is Forth's INKEY-like read. core/key.asm's header says a consuming KEY? would swallow the key a following KEY expects; Leap's LIB_INKEY uses the consuming form. |
| STICK_READ (io.asm) | 30 | Joystick read through AY register 14 | none | - | NO COUNTERPART | Removed in V2 itself (R10.7 dormant-ROM audit), comment at Leap-C platform/kernel/io/io.asm line 513. Not a Leap-C UPSTREAM.md delta. |
| IO_CHECK_BREAK (io.asm) | 18 | Own matrix scan; carry if CAPS SHIFT+SPACE (KEY_BREAK) is down (BREAK?) | none | - | NO COUNTERPART | Removed in V2 itself (R10.7), comment at platform io.asm line 652. Leap-C BREAK goes through the ISR (D4). |
| ROW_TABLE (io.asm) | 8 | Row-select bytes FE FD FB F7 EF DF BF 7F | ROW_TABLE (io.asm) | 8 | IDENTICAL (bytes) | |
| KEY_ASCII_TABLE (io.asm) | 40 | Key to lowercase/digit/space table | KEY_ASCII_TABLE (io.asm) | 40 | IDENTICAL (bytes) | |
| KEY_ASCII_TABLE_UPPER (io.asm) | 40 | CAPS SHIFT table | KEY_ASCII_TABLE_UPPER (io.asm) | 40 | IDENTICAL (bytes) | |
| KEY_ASCII_TABLE_SYMBOL (io.asm) | 40 | SYMBOL SHIFT table | KEY_ASCII_TABLE_SYMBOL (io.asm) | 40 | SAME LAYOUT, DIFF DATA | Leap D7 fills 8 slots that are zero in Forth: row 1 `~ \| \\ { }` (A-G), row 5 `] [` (U, Y), row 6 `^` (H). Byte differences at 5-9, 28-29, 34. Forth: `DB 0,0,0,0,0` (row 1), `DB '"', ";", 0, 0, 0` (row 5), `DB 0, "=", "+", "-", 0` (row 6). |
| KBD_ISR_INIT (interrupt.asm) | 22 | Clears KBD_* cells; KBD_CUR_ROW = $FF | KBD_ISR_INIT (interrupt.asm) | 22 | IDENTICAL SOURCE | Source diff empty. Bytes differ only in sysvar address operands. |
| KBD_ISR_TICK (interrupt.asm) | 118 | Per-frame: FRAMES++, scan, track one key, debounce, repeat; accepted key goes to KBD_LASTK/KBD_KEYHIT. No BREAK action | KBD_ISR_TICK (interrupt.asm) | 126 | IDENTICAL SOURCE except D4 | Source diff is only the D4 block (8 B). Leap's accept path adds: `sub KEY_BREAK / ld b,a` before the latch and `ld a,b / or a / call z,RT_BREAKREQ` after it. Forth has none of this. |
| INT_GET_FRAMES (interrupt.asm) | 4 | `ld hl,(FRAMES); ret` | LIB_FRAMES (library.asm) | 4 | IDENTICAL (opcodes) | Bytes 2A nn nn C9 on both sides; the address differs (Forth FRAMES $82EB, Leap $5C75). Leap's interrupt.asm copy is IFNDEF V2_PRODUCTION, so the function lives in library.asm. |

Module 4 counts: 17 labels. With a counterpart: 15 (14 rows that are IDENTICAL, IDENTICAL SOURCE, IDENTICAL (opcodes) or SAME ALGO / SAME LAYOUT, plus IO_KEY_AVAILABLE as DIFFERENT JOB). No counterpart: STICK_READ, IO_CHECK_BREAK.

Leap-C routines in the module 4 set with no Forth counterpart: IO_READ_KEY_NONBLOCK (7). Also called from KBD_ISR_TICK under D4 and outside the set: RT_BREAKREQ 31 (+ RT_BREAK 3, RT_BREAKAT 5) in rtexit.asm; the Forth ISR has no call to any such routine.

Byte accounting, Forth 625 minus Leap 566 = 59: STICK_READ +30, IO_CHECK_BREAK +18, IO_KEY_AVAILABLE +4, INT_GET_FRAMES +4, IO_DECODE_KEY +18, KBD_ISR_TICK -8, IO_READ_KEY_NONBLOCK -7 (Leap side). 30+18+4+4+18-8-7 = 59.

### 5.1 UPSTREAM.md deltas touching io or interrupt

The platform MANIFEST lists exactly two deltas for these files, D4 (interrupt.asm) and D7 (io.asm). Deltas that touch shared inputs are listed too.

| Delta | File | Forth has the same change? | Evidence |
|---|---|---|---|
| D4 | kernel/interrupt/interrupt.asm: BREAK accept path calls RT_BREAKREQ (8 B) | **No.** Forth has no BREAK action in the ISR at all. | Forth KBD_ISR_TICK accept path: `call IO_DECODE_KEY` / `ld (KBD_LASTK),a` / `ld a,$FF` / `ld (KBD_KEYHIT),a` / `ld a,KBD_REPDEL` / `ld (KBD_REPEAT),a` / `jr .done`. Compared with the V2 tag (~/2068-Leap, `v2.0.1-emu.1`), Forth's interrupt.asm differs from it only by the removal of the IFDEF V2_PRODUCTION BREAK-latch block (the one containing `cp KEY_BREAK`) and the INT_GET_FRAMES IFNDEF guard, which Forth does not have (its INT_GET_FRAMES is unconditional). So Forth matches V2's non-production ISR without any BREAK latch. Leap-C's D4 replaced the V2 latch with a call; Forth has neither. Forth BREAK is handled by polling in BREAK? (IO_CHECK_BREAK). |
| D7 | kernel/io/io.asm: SYMBOL-table additions (~ \| \\ { } ] [ ^) and removal of SYMBOL+A/S error-navigation codes (-19 B) | **Partly.** The navigation code is absent in Forth; the table additions are absent too. | Removal: V2 tag io.asm lines 428-440 contain `.sym_table_lookup` / `.chk_prev_error` / KEY_NEXT_ERROR; Forth kernel/io/io.asm has no NEXT_ERROR or PREV_ERROR reference. Additions: Forth row 1 `DB 0, 0, 0, 0, 0`, row 5 `DB '"', ";", 0, 0, 0`, row 6 `DB 0, "=", "+", "-", 0`. |
| D1 | include/sysvars.inc: `ORG LEAPC_SYSVARS_BASE` (system variables at $5B00) | **No.** Forth keeps its own layout. | FRAMES is $82EB in Forth (INT_GET_FRAMES bytes) and $5C75 in Leap (LIB_FRAMES bytes). Every KBD_* address operand differs for this reason. |

Other deltas that touch the same behaviour but not these files: D14 (kernel/bank/bank.asm, removes `di` from BANK_PAGE_EXROM_IN/OUT so frame interrupts are not lost while paged; a Fuse-found defect). Forth's kernel/bank/bank.asm contains no `di` (grep), and its `BANK_PAGE_EXROM_IN` / `OUT` end with `ei` (lines 162, 200), so the defect's precondition is not present in Forth's bank.asm. Not a module-4 file; not compared further.

### 5.2 Leap-C git history (`git log -- platform/kernel/io platform/kernel/interrupt src/runtime/library.asm`)

| Commit | Date | Subject | Touches in these paths | Bug fix of a routine in these modules? |
|---|---|---|---|---|
| c8eab8f | 2026-10-22 | Phase 10: recommended fixes and library loading | library.asm +3 (entry labels LIB_PLOT_HL, LIB_MALLOC_HL, LIB_FREE_HL) | No. Entry points for a loaded library; the commit's "Fixes 1-5" are in other files. |
| 7e46991 | 2026-10-21 | Phase 8: floating point, language and library completion | library.asm +51/-18 (printf %f, width parsing rewritten to `.num`) | No. Feature (%f, precision). |
| 4d79538 | 2026-10-20 | Phase 7: cassette SAVE/LOAD/VERIFY | library.asm +38 | No. Feature (tape_save/tape_load). |
| fe8147b | 2026-10-20 | Phase 5: editor and C punctuation | io.asm (D7 table and removal of SS+A/S branch); library.asm four `jp LIB_RETA` changed to `jr LIB_RETA` | No. D7 is a key-map change. The jp to jr change is a size change (no behaviour change, same target). |
| e38a6bc | 2026-10-20 | Phase 4: memory layout, banking and capacity | library.asm: LIB_MODE region-4 check for `#pragma hires` | No. Feature: mode(1) accepts a reserved region. |
| 3ba2fac | 2026-10-13 | Phase 3: runtime and library | interrupt.asm (V2 BREAK latch block replaced by the D4 call); library.asm +983 | No. D4 is a feature (BREAK stops a running program). Forth does not have it (Section 5.1). |
| f88eeb0 | 2026-10-13 | Phase 2 step 1 | library.asm +47 (rand) | No. |
| 5a8e35b | 2026-10-13 | M1.1: foundation and lexer | io.asm and interrupt.asm (initial import of the vendored copies) | No. |

No commit in the path-limited log is a bug fix of a routine in these three files. The closest items are the D4 and D7 changes above, which are behaviour changes for the new design, not defect fixes. The Leap-C defect fix in the same area is D14 (outside these paths), discussed in 5.1.

## 6. Behaviour differences noticed while reading (source only, not run)

- **PLOT / LINE:** Forth does not clip. Its coordinate words keep only low bytes, and GFX_WRITE_PIXEL's header requires the caller to clamp y to 0-191 (`kernel/graphics/graphics.asm`, "C = y (0-191, caller clamps)"). Leap clips or clamps. Forth LINE forces OVER=0.
- **CLS:** Forth clears the hi-res second display ($6000-$77FF, filled with CURRENT_ATTR) in mode 1. Leap's LIB_CLS does not touch it.
- **HIRES:** Forth has no image-region-4 check; Leap's mode(1) refuses when region 4 is in use.
- **ATXY:** Forth has no row/column range check; Leap clamps row to 23 and masks column with 31.
- **VAL vs ATOI:** VAL returns 0 for any invalid text; ATOI skips leading spaces and stops at the first non-digit (examples in Section 3).
- **EMIT:** Forth's newline is code 13; Leap's is 10.
- **"." vs ITOA:** Forth's `.` prints a trailing space; Leap's ITOA returns a buffer with no space.
- **KEY? vs INKEY:** Forth KEY? does not consume; Leap's INKEY does.
- **BREAK:** Forth latches the BREAK code as a key and polls BREAK?; it does not stop a running program. Leap's ISR also latches it, then calls RT_BREAKREQ.
- **Forth EXROM bodies:** RECT, POLYGON, POLYGON-FILL and SPRITE-* run EXROM code at $A000 slots. Their HOME stubs are measured here; the bodies are not.

## 7. What I could not determine

- The 88 B difference in Module 2 (989 claimed vs 901 measured). I could not see which file set the audit used. dotquote.asm (88 B) matches exactly but is not confirmed.
- Sizes of EXROM-resident Forth bodies (RECT, POLYGON, POLYGON-FILL, SPRITE-*, and the EXROM-side code those stubs call). These are not in forth_boot.lst and I did not locate a Forth EXROM listing.
- Sizes of Leap-C's loadable `libs/shapes.asm` (circle, box), which are the nearest counterparts of CIRCLE and RECT. Not in HOME; not measured.
- Leap-C's compiler handling of string literals (counterpart of S"). Not checked.
- Whether the Forth listing (built 18:19) matches the current Forth source. I checked that the header sizes equal the DB counts in source on a sample, not all.
- Whether Leap-C's listing (b918527 export) was built from exactly the committed sources. SHA256SUMS exists in the export; I did not verify it.
- Behaviour statements are source readings. No emulator run was done (read-only task).
- Whether Forth's io.asm was copied from V2 and later edited, or written separately. The scaffold commit 96aea38 copied kernel/io/io.asm from 2068-Leap; I did not diff the scaffold against the current file for every routine.
- Whether any Leap-C commit outside the path-limited log fixed a defect in these routines (for example through renames). The log was taken with the paths as given.
