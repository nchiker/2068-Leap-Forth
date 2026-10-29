# Console, line store and full-screen editor: specification (audit step E)

Audit section 4.3. Decisions E1-E10 decided by the owner on 2026-10-28 (section 2). Evidence tags: [M] measured, [S] source, [E] estimate, [L]
Leap-measured. Forth at `v2/step-e-console-editor` (master `0d45a2f` plus T11 `2340f26` and T12 `c93d817`).

## 1. What is there today, verified

**Sizes [M]** (HOME listing, per routine):

| Part | Routines | B |
|---|---|---:|
| Editing logic | `INSERT_CHAR` 69, `DELETE_CHAR_BEFORE_CURSOR` 56, `WRAP_STORE_ROW` 45, `WRAP_CALC` 7, `WRAP_CALC64` 7, `WRAP_CALC_SHARED` 151, `EDIT_CURSOR_TO_ROWCOL` 64, `EDITOR_PROCESS_KEY` 100, `EDITOR_LOOP_LIVE` 87 | 586 |
| Drawing | `EDITOR_REDRAW` 219, `EDITOR_REDRAW64` 191 (two near-copies, 32 and 64 columns) | 410 |
| Workspace and recall | `WORKSPACE_APPEND` 71, `AT_END` 11, `SCAN_DEFS` 143, `GET_DEF_SPAN` 18, `LIST-DEFS` 118, `RECALL` 74 | 435 |
| Text tapes | `SAVE-TEXT` 40, `VERIFY-TEXT` 54, `LOAD-TEXT` 68 | 162 |
| `ACCEPT`, `INPUT` | | 171 |
| **Total** | | **1,764** |

**The reference engine is not smaller.** Leap V2's `rom/exrom_editor.asm` measures 625 B [L] (its `build/exrom.lst`,
`b30ca0c`), but that is editing logic only: its `EDITOR_REDRAW_SCREEN` is 4 B and hands the drawing to a hook in the
caller. Against Forth's 586 B of editing logic it is 39 B larger, so the audit's "about −370 B" [E] compared a
drawing-free engine with an editor that draws. What V2's engine has and Forth's lacks: UP/DOWN between the rows of a
wrapped line (`EDITOR_WRAP_ROWCOL_TO_OFFSET`, 24 B), delete-line and insert-line keys, and a navigation hook.

**Behaviour** (T12 `tools/edtest.py`, every case passes on this build; section 8): one line of up to 128 characters,
word-wrapped over at most 4 rows that grow upward from row 23; LEFT, RIGHT, DELETE (left of the cursor) and ENTER;
UP, DOWN, delete-line and insert-line reach the latch (codes 3, 2, `$0F`, `$0B`) and the editor ignores them; BREAK
is latched as `$10` and ignored; 32 and 64 columns (the cursor is a FLASH attribute with ink and paper swapped in 32
columns, an XOR block in 64). ENTER appends the line to the workspace (a space before it) and interprets it.
`LIST-DEFS` lists the first 16 `: ... ;` spans, numbered; `n RECALL` copies span n (at most 128 characters) into the
edit line.

**Typing cost [M]** (T12 `typing-cost`: T-states from the key latched to the next key wait, interrupts included;
each repeatable to the T-state):

| Scenario | 32 columns | 64 columns |
|---|---:|---:|
| Key at the end of a short line | 40,632 | 60,316 |
| Key in the middle of a 100-character line | 172,440 | 138,840 |
| Key on a 3-row line | 131,554 | 200,745 |
| DELETE | 39,571 | 59,234 |
| LEFT | 40,657 | 60,184 |
| ENTER on `1 2 + .` | 168,712 | 187,446 |

Every key redraws the whole input area. One interrupt is about 2,000 T, and a build whose boot length differs moves
the frame phase, so figures compare to within one interrupt.

**Defects found [M]:**

- **The workspace overruns its buffer.** `WORKSPACE_APPEND`'s room check compares the high byte of the new length
  with `LOADTEXT_MAX_LEN/256 + 1`, so it accepts up to 8,447 bytes into the 8,192-byte buffer. Measured: committed
  lines took `WORKSPACE_END` to `$F0FC` (8,444 bytes), writing 252 bytes above `$F000`. Nothing lives at
  `$F000-$F0FF` today, so nothing breaks yet. An empty ENTER also appends a separator space each time.
- **The dictionary can overwrite the source.** The workspace is `$D000-$EFFF`, inside the dictionary's range
  (`FORTH_DICT_RAM` `$9800` up to `DICT_RAM_CEILING` `$F000`), and nothing that advances `HERE` checks it
  (`core/dictspace.asm` header; `HERE` is written in nine places in seven files [S]).
- **64-column hang** (T12 `wrap-scroll`, part `pr22-64`). `EDITOR_REDRAW64` keeps `FWRAP_OLD_COUNT`'s address in HL
  across `MODE64_SCROLL_OUTPUT_UP`, which does not preserve HL. With output down to row 21 and a line growing from 2
  to 3 rows, the editor never returns to the key wait (PC stays in `.grow_loop64`) [M, S].
- **64-column room check.** `EDITOR_PROCESS_KEY` checks room with the 32-column `WRAP_CALC`, so in 64 columns a line
  is refused at its 106th character although it would fit 3 rows of 64 [M].
- **No cursor on a full row.** A line that exactly fills its last row (32, 64, 96 or 128 characters) puts the cursor
  at column 32, which is off the row, so no cursor shows [M].
- **BREAK does not stop a running program** (`: L BEGIN 0 UNTIL ; L` runs on with BREAK held): no interpreter poll.
  That is step B (O6), not E.
- **An error in `LOAD-TEXT`'s text is mishandled** [M, oracle N3]. The unknown word is reported, but the handler
  returns from the inner `INTERPRET_RUN` to the end of `LOAD-TEXT` and into the outer interpreter, which goes on
  reading the `SRC_PTR`/`SRC_END` the inner run left: the rest of the text runs (a second `?` follows). When the
  unknown word hits in compile state (`: SQ DUP *` CR `;` ...), the outer run ends one stack word off and the machine
  restarts at `$0000`. `INTERPRET_RUN` also stores `THROW_ROOT_SP` on every entry, so after the nested run the outer
  interpreter keeps the inner run's deeper SP [S]. E's `LOAD-TEXT` must stop at the error and leave the machine
  intact (section 3).
- After a refused key the wrap table keeps the refused line until the next redraw (`FWRAP_OVERFLOW` stays 1);
  nothing visible follows from it [M].

**No line structure.** `WORKSPACE_APPEND` separates committed lines with a space, and `INTERPRET_RUN`'s `WORD`
treats only a space as a delimiter (`core/interp.asm`, two `cp " "` tests [S]). The text is one long line.

## 2. Decisions (decided 2026-10-28)

The owner accepted the recommendations: E1, E2 option (a), E3-E8 and E10 as written, and E9 changed to a refusal in
64-column mode. O13 (`LEAPC_COMPARISON_AUDIT.md`) runs as its own step before E's code.

**E1. One line store: plain text, lines ended by CR.** The `$D000` workspace becomes a sequence of lines, each ended
by CR (`$0D`), at most 128 characters (the console's line), no length prefix. It is exactly what `SAVE-TEXT` writes and `LOAD-TEXT` reads,
so the tape format is unchanged and `tools/tape_gen_forth.py` tapes still load. `WORD` treats every byte up to space
as a delimiter (`cp " "+1` / `jr c` for `cp " "` / `jr z`, same size), so source with CRs interprets as before.
*Why not Leap-C's `[len:2][text][CR]` records:* they cost 2 B a line and a conversion on every tape; Forth's store
is at most 8 KB, so finding a line by scanning for CR costs at most a few thousand T on a keypress [E], and the
scan-based `RECALL`/`LIST-DEFS` already work this way.

**E2. Store and dictionary keep apart.** Two options, measured in the oracle before the code:
- (a) *Fixed store* (**decided**): the store keeps `$D000-$EFFF`; the dictionary's ceiling becomes `$D000`, checked
  where definitions and data fields start, in `ALLOT`, `,` and `C,` (THROW -8, dictionary overflow; section 3). Dictionary space drops from 22 KB to
  14 KB. In-place LIB images (STORAGE_SPEC D4) are then limited to `$D000`.
- (b) *Shared region*: the store sits at the top and grows down; dictionary and store share `$9800-$EFFF` with one
  check (`HERE` + guard < store start). More flexible, more code, and the store moves.

**E3. Keep Forth's engine; merge its two redraws.** Forth's 586 B of editing logic stays in HOME as the one engine
for the console and the full-screen view. `EDITOR_REDRAW` and `EDITOR_REDRAW64` become one routine parameterised by
width, as `WRAP_CALC_SHARED` already is (about −150 B [E]). The view (E4) calls the engine through veneers added
after `GRAPHICS_HOME_TABLE` at `$0100`. From V2's engine, take only what the view needs: UP/DOWN between wrapped
rows (`EDITOR_WRAP_ROWCOL_TO_OFFSET`, 24 B [L]).

**E4. Full-screen view in the EXROM.** Leap-C `src/shell/shell.asm`'s redraw, navigation and view, with BASIC and C
removed (Leap-C measured 470 + 209 + 94 + 94 B [L], `docs/milestones/M5.md`), plus the store routines (insert, delete,
find line; Leap-C's are 166 B [L] for length-prefixed records). EXROM total 2.2-2.6 KB [E] of 6,682 B free. Both
builds carry the graphics EXROM (the cartridge as DOCK chunk 5 since R1), so the view works in both. With a stock
EXROM (the Forth HOME ROM fitted alone), `EDIT` reports an error and the console still works.

**E5. The console keeps appending committed lines** to the store, now each as a line (CR-ended), so the store holds
the session's source as today. A full store refuses the append with a message instead of overrunning (section 1).

**E6. `EDIT name`** opens the view on the newest `: name` line found by the existing scan; `EDIT` alone opens it at
the end. On leaving the view, only the lines changed in it are interpreted (ordinary redefinition, no `FORGET` and
replay). `n RECALL` is retired: `EDIT` does its job on the real source, and V1 compatibility is not required
(decision 6), which saves its 74 B. `LIST-DEFS` stays.

**E10. The console's defects are fixed by the rebuild**, not patched first: the merged redraw (E3) has one grow loop,
which must keep its pointer across the scroll (the 64-column hang); the room check uses the width in force; the
cursor on a full row goes to column 0 of a new row, as a line one character longer would; a 128-character line has
no fifth row, so its cursor sits on the last character's cell. Each has a T12 case whose
expectation changes (section 8).

**E7. Leaving the view clears the screen** and returns to the prompt with `PRINT_ROW`/`PRINT_COL` reset. Restoring
the console screen (audit 4.3 item 6) would need a 6,912-byte buffer, which RAM does not have outside the store.

**E8. Zero cost to running programs.** The view is a separate session: no ISR, inner-interpreter or `EMIT` hooks.

**E9. 64 columns.** The console keeps both widths through the merged redraw (E3). The view is 32 columns; in
64-column mode `EDIT` refuses with a message and changes nothing (decided: less code than switching modes and back).
A 64-column view is a later item.

## 3. Line store contract

**Layout.** `STORE_START` = `$D000`; `STORE_END` (the cell `WORKSPACE_END` today) is one past the last byte;
`STORE_LIMIT` = `$F000`, so the store holds at most 8,192 bytes and never writes at or above `$F000`. A line is 0-128
bytes of text (any byte but CR) followed by one CR; every line, the last included, ends with CR. An empty store has
`STORE_END` = `STORE_START`. Lines are numbered from 1 in store order.

**Session mark.** While the view is open, a line changed or inserted in it ends with `$8D` (CR with bit 7 set)
instead of `$0D`. Outside the view every terminator is `$0D` (E6's commit clears the marks).

**HOME routines** (the console and the tape words use them):
- *Append* (console ENTER): an empty line is not appended. A line that does not fit (`STORE_END` + length + 1 >
  `STORE_LIMIT`) is not appended: `STORE FULL` is printed on its own line, and the line is still interpreted.
  Otherwise the text and a CR go at `STORE_END`.
- *LOAD-TEXT*: the tape's data replaces the store (as today, up to 8,192 bytes); if its last byte is not CR, a CR is
  added when there is room. Then the store is interpreted, as today. An error in the loaded text (an unknown word,
  an uncaught THROW) stops the interpretation with the console's usual message and leaves the machine, the
  dictionary built so far and the store intact; `THROW_ROOT_SP` is the outer interpreter's again afterwards. On success, the
  rest of the console line after `LOAD-TEXT name` is interpreted (the outer run's `SRC_PTR`/`SRC_END` are kept). Lines longer than 128 characters (an old
  space-separated text) are kept as they are: the console interprets them, and `EDIT` refuses while one exists.
- *SAVE-TEXT*, *VERIFY-TEXT*: the bytes `STORE_START` to `STORE_END`, unchanged format.
- `WORD` treats every byte from 0 to space as a delimiter (E1).

**EXROM routines** (the view): line n's start and length (a scan counting terminators from `STORE_START`; n past the
last line gives `STORE_END`, length 0); replace line n's text; insert a line before line n; delete line n; count the
lines. Each moves the tail of the store with HOME's block-move routine (through a veneer), checks room first, and
reports a full store by carry without changing anything. Registers are set by the code and recorded in the
routines' headers.

**The sprite buffers moved** (found at item 4): `SPRITE_SLOT_IMG_BUF` and `SPRITE_SLOT_BG_BUF` (288 B, the graphics
EXROM's SPRITE words) were at `$E800-$E91F`, inside the store region, so a store over 6 KB and SPRITE-DEFINE/SHOW
overwrote each other (in the old build too). They are now at `$F000-$F11F`, between the store and `UDG_TABLE`, a
range nothing used (`LABEL_TABLE_TOP` there is BASIC scaffolding no Forth code references); the cold start still clears
them. Asserted in `include/sysvars.inc`. 0 B of code.

**Dictionary ceiling (E2a).** `DICT_RAM_CEILING` becomes `$D000`; `LOADTEXT_BUF` stays `$D000` and is defined on its
own, no longer as the ceiling minus 8 KB. Every place that starts a definition or a data field (the header builder
behind `:`, `CREATE`, `VARIABLE`, `CONSTANT`, `STRING`, `ARRAY`), `ALLOT`, `,` and `C,` refuses with THROW -8 when
`HERE` would pass `DICT_RAM_CEILING` - 256; the 256-byte guard covers a definition's body compiled before its `;`.
The code picks the fewest central points that cover these; the oracle (N5) checks the result. An uncaught THROW
prints the console's error text (today `STACK?` for every code), so N5 observes -8 through `CATCH` where it can
(`ALLOT`, `,`, `C,`) and, for the defining words, by the error, `HERE` staying below the guard and the store's bytes. In-place LIB images
(STORAGE_SPEC D4) are bounded by the same ceiling.

## 4. Console

Unchanged keys and screen behaviour, except: CR-ended lines in the store (E1, E5) and the merged redraw (E3). Every
T12 case that passes today must pass afterwards, except those section 8 lists as changed.

**The merged redraw as built (item 5) [M, S].** One `WRAP_CALC` for both widths: `WRAP_CALC_AT` takes HL = text, A =
length, C = cursor offset (`$FF`: none), keeps the table's offsets from `FWRAP_BASE`, and sets the width
(`FWRAP_WIDTH_MINUS1`) and the row drawer (`ED_ROW_JP`, a 3-byte RAM `JP` to `ED_ROW32` or `ED_ROW64`) from `GFX_MODE`;
`WRAP_CALC` is that for the edit line. A full last row with the cursor at its end is stored as a hard break, so the
table has the cursor's row (E10); `EDIT_CURSOR_TO_ROWCOL` places the cursor from `FWRAP_TOP` and clamps column W to
W - 1. `EDITOR_REDRAW` resizes the input area one row at a time, reading `FWRAP_OLD_COUNT` and `FWRAP_COUNT` afresh on
every pass (the 64-column hang), sets `FWRAP_TOP` = 24 - count and calls `ED_DRAW_ROWS` and `ED_DRAW_CURSOR`. These four
(`WRAP_CALC`, `WRAP_CALC_AT`, `ED_DRAW_ROWS`, `ED_DRAW_CURSOR`) with `FWRAP_TOP` are what the view needs to draw its
lines (item 6). The row drawer is chosen once per row, not per cell: a cell writer called through the veneer cost
64 columns up to 12,700 T a key. Sizes: wrap 165 → 196 B, drawing 410 → 199 B, HOME −178 B; RAM `$88F8-$88FE`.

## 5. Full-screen view

**Entry.** `EDIT name` finds the last line in the store in which the words `:` and `name` follow each other (words
separated by whitespace, compared without regard to case) and opens the view with the cursor at the start of that
line. `EDIT` with nothing after it opens it on a new empty line after the last line. Refusals, each printing one
message and changing nothing: no graphics EXROM (`NO EXROM`, detected as `EXROM_CALL_SLOT` does), 64-column mode
(`32COL FIRST`), a line over 128 characters in the store (`LONG LINE`), name not found (`name ?`, as an unknown word).

**Screen.** 32 columns. Rows 0-22 show store lines from the view's top line down, each wrapped by the console's
word-wrap rule (one rule, one routine: E3); row 23 is the status row, `LINE n/m` (cursor line, line count). The
cursor line is always wholly on screen; when a move would leave it partly off, the view scrolls by whole lines and
redraws. The cursor is the console's (FLASH, ink and paper swapped).

**Editing.** The cursor line is copied into `EDIT_BUF` and edited by the engine (E3), so its limits are the console's
(128 characters, 4 rows). Leaving the line by UP, DOWN, ENTER, delete-line, insert-line or BREAK writes it back if it
changed, and marks it (section 3).

**Keys.**

| Key | Effect |
|---|---|
| any character, LEFT, RIGHT | as in the console, within the line (LEFT at column 0 and RIGHT at the end do nothing) |
| UP, DOWN | to the previous or next screen row of a wrapped line; past its first or last row, to the previous or next line at the same column, or its end if shorter. Nothing above line 1; DOWN on the last line does nothing |
| DELETE | deletes the character left of the cursor; at column 0 of an empty line, deletes the line; at column 0 of a non-empty line, nothing |
| ENTER | writes the line back and inserts a new empty line after it, the cursor on it |
| delete-line (CAPS SHIFT + 1) | deletes the cursor line; the cursor goes to the line that took its place (or the new last line) |
| insert-line (CAPS SHIFT + ENTER) | inserts an empty line before the cursor line, the cursor on it |
| BREAK (CAPS SHIFT + SPACE) | writes the line back and leaves the view |

An empty line left by UP, DOWN or BREAK stays in the store (it is a CR, harmless to interpret). A full store refuses
the change that would overflow it: the line and the store stay as they were and `STORE FULL` shows on the status
row until the next key.

**Leaving (E6, E7).** The screen is cleared; every marked line is interpreted in store order, its mark cleared before
it runs; the first line that raises an error stops this, with the error's usual message preceded by `LINE n`, and
the remaining marks are cleared without interpreting. Then `PRINT_ROW`/`PRINT_COL` are reset and the console
prompt returns.

**Oracle hooks.** The oracle observes the view through the screen (row 23 shows `LINE n/m` while it is open) and the
store's bytes, and needs two symbols: `STORE_END` (the cell; the old build's `WORKSPACE_END`) and `VIEW_REDRAW_ALL`,
an EXROM routine that redraws rows 0-23 from the view's state and returns (the EXROM is paged in for the whole
session, so the oracle calls it directly at the view's key wait).

**Redraw.** A key that changes only the cursor line redraws that line's rows; one that changes the set of lines on
screen (scroll, insert, delete, a line changing its row count) redraws from the cursor line down, or the whole view
when it scrolls. After every key the screen equals a full view redraw from the same state (N9).

### 5.1 Design of item 6 (decided at item 5)

**Split.** HOME: the engine (item 5), its veneers, `EDIT` and the commit. EXROM (`rom/graphics_exrom.asm`, service
slot 6, `VIEW_SESSION`): the entry checks that need the store, the store routines, the view's layout, redraw, keys
and status row. The EXROM stays paged in for the whole session; it calls HOME only through `GRAPHICS_HOME_TABLE`
and the RAM veneer `ED_ROW_JP`. Item 6 brings a minimal `EDIT` (open by name or bare, leave, commit) so that N7,
N9 and N13 can run; item 7 adds the refusals, the error report `LINE n`, `RECALL`'s retirement and the docs.

**Veneers** appended to `GRAPHICS_HOME_TABLE` (slots 0-4 unchanged; same bytes in HOME and cartridge builds):

| Slot | Target | Contract |
|---|---|---|
| 5 | `WRAP_CALC` | the edit line's table, with E10's row (item 5) |
| 6 | `WRAP_CALC_AT` | HL = text, A = length, C = cursor or `$FF` |
| 7 | `ED_DRAW_ROWS` | the table's rows from `FWRAP_TOP` |
| 8 | `ED_DRAW_CURSOR` | the cursor from the table and `FWRAP_TOP` |
| 9 | `EDITOR_EDIT_KEY` | A = key; the console's editing without a redraw: carry = ENTER (not handled), NC + NZ = the line or cursor changed, NC + Z = nothing changed (DELETE or LEFT at 0, RIGHT at the end, a refused or ignored key). `EDITOR_PROCESS_KEY` becomes `call EDITOR_EDIT_KEY / ret c / ret z / call EDITOR_REDRAW / or a / ret` |
| 10 | `IO_READ_KEY` | the key wait (the oracle's "key wait" is this PC) |
| 11 | `EDIT_CURSOR_TO_ROWCOL` | B = `FWRAP_TOP` + row index, C = column |
| 12 | `FORGET_PRINT_MSG` | HL = zero-terminated text through `W_EMIT` (CR is a newline), core/forget.asm: the EXROM's messages (`32COL FIRST`, `LONG LINE`, `STORE FULL`) print from the EXROM while it is paged in |

**Store routines (EXROM).** A terminator is `$0D` or `$8D`. Each routine records its registers in its header.
`STORE_LINE` (line n → start, length; n = count gives `STORE_END`, 0), `STORE_COUNT`, and one gap routine
`STORE_GAP` (HL = position, signed delta: checks `STORE_END` + delta ≤ `STORE_LIMIT` first and returns carry with
nothing changed, else moves `[position, STORE_END)` with `LDIR`/`LDDR` and updates `STORE_END`); replace, insert and
delete are a gap plus a copy or a terminator write. (The spec's "HOME's block-move routine" does not exist; `LDIR`/`LDDR`
inline are smaller than a veneer.) A write-back stores `EDIT_BUF`'s text and `$8D`; an inserted line is a lone `$8D`.
"Changed" means the bytes differ (`EDIT_BUF`/`EDIT_LEN` against the store line), compared when the line is left.

**Entry (`VIEW_SESSION`).** In: `WORD_BUF` = the name (length 0: bare `EDIT`). Refusals in this order, each changing
nothing: 64-column mode (`32COL FIRST`); a line over 128 characters or one that needs a fifth row at 32 columns
(`LONG LINE`: neither can be the engine's line); the name not found (result 1: HOME jumps to
`INTERPRET_UNKNOWN_WORD`, which prints `name ?` from `WORD_BUF` as for an unknown word). Matching: per line, the
words `:` and the name adjacent, words split at bytes 0-32, compared without case. Bare `EDIT` inserts an empty
marked line after the last one at once (the line count includes it); with no room it refuses with `STORE FULL`. The
result is a RAM cell (`EXROM_CALL_SLOT` loses A).

**Layout.** View state in RAM `$8AC0` up (free: `$8ABD-$8BFF`): top line, cursor line, line count, message flag,
the cursor line's screen row and row count, the previous cursor cell. A line's rows are `WRAP_CALC_AT` on its text
in the store (C = `$FF`); the cursor line's are `WRAP_CALC` on `EDIT_BUF` (E10's row included). Scrolling is the
least that keeps the cursor line whole: top = min(top, cursor line), then top + 1 while the rows from top to the
cursor line exceed 23. A line below that does not fit is drawn as far as row 22 goes (both drawings are allowed).

**Redraw.** `VIEW_REDRAW_ALL` (the oracle's): rows 0-22 from the top line (each line `WRAP_CALC_AT` or `WRAP_CALC`,
then `FWRAP_TOP` and `ED_DRAW_ROWS`), blank rows below through `ED_ROW_JP` with D = 0, the status row, then the
cursor (`WRAP_CALC`, `FWRAP_TOP` = the cursor line's row, `ED_DRAW_CURSOR`). After a key: the top changed → all;
the cursor moved to another line, or the cursor line's row count changed, or lines were inserted or deleted → from
the upper of the old and new cursor lines down; else the cursor line's rows only. The status row (`LINE n/m`, or
`STORE FULL` until the next key) is drawn after every key. Every cell drawn through `ED_ROW32` gets `ATTR_DEFAULT`,
which also removes an old cursor; a cursor left on a row not redrawn is reset with slot 1 (`GFX_SET_ATTR`).

**Keys** as section 5's table, the view's own first (UP, DOWN, ENTER, delete-line, insert-line, BREAK, DELETE at
column 0), the rest to slot 9. Within a wrapped line UP/DOWN keep the column (the row's end if shorter) from slot
11's row and column and the table; into another line: UP to its last row, DOWN to its first, same rule. Deleting
the only line leaves it empty (marked) instead. After a delete the cursor is at column 0 of the line that took the
deleted one's place, or of the new last line.

**Leaving and commit (HOME, `EDIT`).** After the session: `GFX_CLS`, `PRINT_ROW`/`PRINT_COL` to 0, then until no
`$8D` is left: find the first marked line, clear its mark, run it with `INTERPRET_NESTED` (saving and restoring
`SRC_PTR`/`SRC_END`, as `LOAD-TEXT` does). The scan restarts from the store's start each time, so a line that
changes the store cannot leave a mark behind. Item 7 adds the error report: a cell holding the running line's
number, read by `INTERPRET_UNKNOWN_WORD` and `RUNTIME_ERROR_HOOK` before their message (`LINE n `, then clear every
remaining mark).

### 5.2 Item 6 as built [M, S]

Built to 5.1, with these departures (each judged by N6-N13 and the redraw oracle):

- **The `EDIT` command line is taken off the store** (`VIEW_TRIM`, EXROM). The console appends the line it is about
  to run (E5), so `EDIT SQ` would become source, and a text saved with it would open the view again when loaded. The
  session removes the store's last line when it is exactly the console's line after a terminator. With `NO EXROM`
  the line stays (the EXROM is not there to remove it); N10 and N11 accept both.
- **Marks left by an error are cleared after the console line**, not in the error hooks: `EDITOR_LOOP_LIVE` calls
  `EDIT_CLEAR_MARKS` (one `CPIR` pass) when `VIEW_RESULT` is non-zero, which covers an unknown word, an uncaught
  THROW, ABORT and QUIT alike. Item 7 adds only the `LINE n` prefix.
- **HOME cells the EXROM uses** are copies in `include/exrom_home_ram.inc`, compared with the HOME symbols in both
  builds by `tools/audit_layout.py` (`make check`).
- **Redraw:** LEFT, RIGHT and UP/DOWN inside a line move only the cursor cell; the status row is drawn when its text
  changes; `VIEW_BOTTOM` records the rows the last drawing used, so only those are blanked. The screen equals
  `VIEW_REDRAW_ALL` after every key (N9).
- **Refusals:** `LONG LINE` also covers a store whose last line has no terminator (an 8,192-byte text with no room
  for the closing CR). Refusals that the model leaves open: the only line deleted is emptied and marked; ENTER and
  insert-line are all-or-nothing when the store is full; BREAK with no room for the write-back stays in the view with
  `STORE FULL`; after a delete the cursor is at column 0.
- **Opening deep in a store** starts the fit from line n - 22, so it does not search from line 1.

Sizes: HOME +187 B (veneers 24, engine split 6, `EDIT` 118 with its header, `EDIT_CLEAR_MARKS` 31, the loop's hook
7, one `jr` to `jp` 1). EXROM +1,676 B: store routines 204, the view about 1,470 (`VIEW_KEY` 366, `VIEW_SESSION`
230, `VIEW_DRAW_FROM` 146, `VIEW_FIT` 115, `VIEW_POST` 113, `VIEW_LEAVE` 104, ...). View typing cost (N12, the gate
for later changes) [M]:

| Key | T | Key | T |
|---|---:|---|---:|
| at the end of a short line | 42,196 | ENTER | 162,633 |
| in the middle of a 100-character line | 173,378 | insert-line | 160,421 |
| at the end of a 3-row line | 176,302 | delete-line | 118,612 |
| DELETE | 38,250 | DOWN to the next line | 126,053 |
| LEFT | 3,300 | UP inside a line | 10,564 |
| scroll down one line (60-line store) | 1,032,460 | | |

A scroll redraws all 23 rows through `ED_ROW32` (no pixel scroll) and finds lines by scanning from `STORE_START`;
about 0.3 s a scrolled line at 3.5 MHz.

## 6. Words

`EDIT` (new), `RECALL` (retired), `LIST-DEFS`, `SAVE-TEXT`, `VERIFY-TEXT`, `LOAD-TEXT` (format unchanged, CRs kept).

## 7. Byte budget [E]

| Change | HOME | EXROM |
|---|---:|---:|
| Merged redraw (E3) | about −150 [E]; measured −178 (item 5) | |
| `RECALL` retired (E6) | −74 | |
| CR as whitespace (E1) | 0 | |
| Store room check, dictionary ceiling check (E2a, E5) | +20-40 [E]; measured +16 (item 3) and +66 (item 4) | |
| Engine veneers for the view (E3) | +15-25 [E]; measured +30 (item 6: 8 slots and the engine split) | |
| `EDIT` word and EXROM call | +40-60 [E]; measured +157 (item 6: `EDIT` and its commit loop 118, `EDIT_CLEAR_MARKS` 31, hook 8) | |
| View, navigation, redraw, store routines (E4) | | +2,200-2,600 [E]; measured +1,676 (item 6) |
| **Total** | **about −110 to −200** | **+2,200-2,600** |

## 8. Oracle (written and run against the old build before the ROM changes)

T12, `tools/edtest.py`, target `make edtest` (19 cases, 49 tasks, about 45 s on 7 workers; ports 10900-10919;
`EDTEST_BUILD=<dir>` for another build). Every case asserts what the old build does; it passes 19/19 on the step-E
base and on the audit baseline `fff5259` [M]. The commit that lands E's new cases records the old build's results
in `docs/V2/evidence/`.

| # | Case | Old build | New build must |
|---|---|---|---|
| 1 | `boot-console` | banner, empty edit line, cursor (23, 0) | same |
| 2 | `keys-charset` | every typeable character reaches line and screen | same |
| 3 | `keys-editing-matrix` | LEFT, RIGHT, DELETE, ENTER work; UP, DOWN, delete-line, insert-line ignored | same in the console |
| 4 | `break-key-console` | BREAK ignored at the prompt | same |
| 5 | `left-right-insert` | as the model | same |
| 6 | `delete` | as the model | same |
| 7 | `line-full` | 128 fit; the 129th refused; no cursor on a full row | 128 fit; 129th refused; **cursor shown** (E10) |
| 8 | `wrap-model` | screen equals the `WRAP_CALC` model, 32 and 64 columns | same model |
| 9 | `wrap-grow-shrink` | grows upward 1-4 rows, clears on shrink | same |
| 10 | `wrap-scroll` | output scrolls up; **64-column hang** at `pr22-64` | scrolls; **no hang** (E10) |
| 11 | `enter-interprets` | `3 OK`; `FOO ?`; `STACK?` | same |
| 12 | `workspace-append` | space-separated; overruns past `$F000` | **CR-ended lines; a full store refuses** (E1, E5) |
| 13 | `recall` | `n RECALL` edits a copy; both copies kept | **replaced by `EDIT`** cases (E6) |
| 14 | `console-64col` | wraps at 64; refused at the 106th character | wraps at 64; **refused only when 4 rows of 64 are full** (E10) |
| 15 | `scroll-output` | output scrolls, edit line on row 23 | same |
| 16 | `break-running` | not broken (no poll) | same (step B changes it) |
| 17 | `colour-state` | editor ignores INK/PAPER | same |
| 18 | `redraw-oracle` | after every key the screen equals a full redraw (11 scenarios and a control) | same, against the merged redraw |
| 19 | `typing-cost` | the table in section 1 | no scenario slower by more than 1% plus one interrupt (2,000 T); slower needs the owner's approval |

Cases E adds (written and run on the old build with the next commit; expected results there in brackets):

| # | Case | New build must | Old build |
|---|---|---|---|
| N1 | `store-lines` | committed lines are CR-ended in `$D000`, `STORE_END` exact; an empty ENTER appends nothing | (fails: space-separated) |
| N2 | `store-full` | an append that does not fit prints `STORE FULL`, the line still runs, nothing at or above `$F000` changes | (fails: overrun) |
| N3 | `cr-whitespace` | source with CR (and TAB) between words interprets as with spaces, through `INTERPRET_RUN` and `LOAD-TEXT`; a tape without a final CR gets one; an unknown word in loaded text stops it with `name ?`, machine and store intact, and a later `ABORT` still works | (fails: CR is part of a word; the machine restarts) |
| N4 | `text-tape-roundtrip` | in `tools/tapetest.py` (case N4, after case 3): nine CR-ended lines saved, decoded, played back, `LOAD-TEXT`: store byte-identical; prints 42, and 21 once CR is whitespace | (passes: the same bytes read as one long name there) |
| N5 | `dict-ceiling` | definitions in a loop, and a large `ALLOT`, THROW -8 before `HERE` passes `$D000` - 256; the store is untouched (E2a) | (fails: store overwritten) |
| N6 | `edit-open` | `EDIT SQ` shows the view on the last `: SQ` line (case-insensitive), status `LINE n/m`; `EDIT` alone opens a new line after the last | (fails: no `EDIT`) |
| N7 | `edit-keys` | every row of the key table in section 5, store and screen checked after each key | (fails) |
| N8 | `edit-commit` | leaving interprets only marked lines, in store order; an unchanged session interprets nothing; an error stops at `LINE n` and clears the marks; no `$8D` left in the store | (fails) |
| N9 | `edit-redraw-oracle` | after every key in the view the screen equals a full view redraw | (fails) |
| N10 | `edit-refusals` | `NO EXROM` (stock-shaped EXROM), `LONG LINE` (a 200-character line loaded), `name ?` (not found); nothing changes and the console works | (fails: no `EDIT`) |
| N11 | `edit-64col` | `EDIT` in 64-column mode prints `32COL FIRST` and changes nothing (E9) | (fails) |
| N12 | `edit-typing-cost` | typing cost in the view recorded (no old figure; the gate is set from this first measurement) | (n/a) |
| N13 | `edit-store-full` | in the view, a change that would overflow the store is refused, `STORE FULL` on the status row, store unchanged | (fails) |

## 9. Implementation order (one commit each, ledger figures in the last)

1. This spec.
2. Oracle: the T12 cases plus E's new cases, run on the old build; results in `docs/V2/evidence/`.
   Then step O13 (data-stack calls through RST vectors, `LEAPC_COMPARISON_AUDIT.md` section 4), its own branch and
   ledger row (decided); E's byte figures are measured after it.
3. CR as whitespace in `WORD`; the store's line contract in HOME; workspace room check (E1, E5).
4. Dictionary ceiling (E2).
5. Merged redraw (E3).
6. Engine veneers; the view in the EXROM (E4).
7. `EDIT`, `RECALL` retired (E6); docs, tutorial, audit ledger.

Each step: `make check`, `make test`, `make harness`, `make edtest EDTEST_GROUP=old` plus the new cases that step
implements (all of them by the last step, when plain `make edtest` must pass); `make tapetest` from step 3 on.

## 10. Verification limits

- No hardware: every result is ZEsarUX running the ROM images. Key presses through `Console.press` are held until the
  ISR accepts them, so contact bounce and fast typing on a real keyboard are not exercised.
- **Fuse 1.9.1 crash** (found at step E item 3): with one particular image layout (item 3's first draft, HOME 1,114 B
  free), `make fusesave-cross` dies: Fuse aborts with a glibc malloc assertion inside its own `tape_write` while
  recording `SAVE-LIB` of `: CUBE DUP DUP * * ;`. The same layout's `SAVE-LIB` captured on ZEsarUX decodes
  correctly and round-trips (`tools/tapetest.py --case 4`), and 1 or 3 bytes more or less make Fuse pass. At item 4
  it came back on two more layouts, and on the same ROM `: CUBE DUP DUP * * 0 + ;` records fine: the trigger is the
  recorded signal, inside Fuse's tape writer. `tools/fusesave.py`'s cross phase now prints the abort and records both
  machines again with that equivalent definition (`CROSS_SETUPS`). If another recording trips it, check
  `tapetest --case 4` on that build before suspecting the ROM.
- The screen is read from video RAM; flicker is judged by the full-redraw oracle (no intermediate frame differs from
  a full redraw at the key wait), not by watching a display.
