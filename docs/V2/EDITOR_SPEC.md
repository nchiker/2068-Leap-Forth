# Console, line store and full-screen editor: specification (audit step E)

Audit section 4.3. Draft for the owner's review. Evidence tags: [M] measured, [S] source, [E] estimate, [L]
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
- After a refused key the wrap table keeps the refused line until the next redraw (`FWRAP_OVERFLOW` stays 1);
  nothing visible follows from it [M].

**No line structure.** `WORKSPACE_APPEND` separates committed lines with a space, and `INTERPRET_RUN`'s `WORD`
treats only a space as a delimiter (`core/interp.asm`, two `cp " "` tests [S]). The text is one long line.

## 2. Decisions (proposed; the owner decides)

**E1. One line store: plain text, lines ended by CR.** The `$D000` workspace becomes a sequence of lines, each ended
by CR (`$0D`), at most 127 characters, no length prefix. It is exactly what `SAVE-TEXT` writes and `LOAD-TEXT` reads,
so the tape format is unchanged and `tools/tape_gen_forth.py` tapes still load. `WORD` treats every byte up to space
as a delimiter (`cp " "+1` / `jr c` for `cp " "` / `jr z`, same size), so source with CRs interprets as before.
*Why not Leap-C's `[len:2][text][CR]` records:* they cost 2 B a line and a conversion on every tape; Forth's store
is at most 8 KB, so finding a line by scanning for CR costs at most a few thousand T on a keypress [E], and the
scan-based `RECALL`/`LIST-DEFS` already work this way.

**E2. Store and dictionary keep apart.** Two options, measured in the oracle before the code:
- (a) *Fixed store* (recommended): the store keeps `$D000-$EFFF`; the dictionary's ceiling becomes `$D000`, checked
  where a definition ends and in `ALLOT` (THROW -8, dictionary overflow). Dictionary space drops from 22 KB to
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
cursor on a full row goes to column 0 of a new row, as a line one character longer would. Each has a T12 case whose
expectation changes (section 8).

**E7. Leaving the view clears the screen** and returns to the prompt with `PRINT_ROW`/`PRINT_COL` reset. Restoring
the console screen (audit 4.3 item 6) would need a 6,912-byte buffer, which RAM does not have outside the store.

**E8. Zero cost to running programs.** The view is a separate session: no ISR, inner-interpreter or `EMIT` hooks.

**E9. 64 columns.** The console keeps both widths through the merged redraw (E3). The view is 32 columns in this
step; in 64-column mode `EDIT` switches to 32 and back on exit. A 64-column view is a later item.

## 3. Line store contract

To be filled from the oracle's measurements: the routines (find line n, line start/length, insert, delete, replace,
append), their registers, and the capacity rules (full store, line > 127 characters from a tape: shown wrapped and
editable up to 127, longer lines split at load).

## 4. Console

Unchanged keys and screen behaviour, except: CR-ended lines in the store (E1, E5) and the merged redraw (E3). Every
T12 case that passes today must pass afterwards, except those section 8 lists as changed.

## 5. Full-screen view

To be filled: screen layout (status row), keys (LEFT, RIGHT, UP, DOWN, DELETE, ENTER, delete-line, insert-line,
BREAK to leave), redraw rules (only what changed; the T12 full-redraw oracle applies after every key), changed-line
tracking for E6.

## 6. Words

`EDIT` (new), `RECALL` (retired), `LIST-DEFS`, `SAVE-TEXT`, `VERIFY-TEXT`, `LOAD-TEXT` (format unchanged, CRs kept).

## 7. Byte budget [E]

| Change | HOME | EXROM |
|---|---:|---:|
| Merged redraw (E3) | about −150 | |
| `RECALL` retired (E6) | −74 | |
| CR as whitespace (E1) | 0 | |
| Store room check, dictionary ceiling check (E2a, E5) | +20-40 | |
| Engine veneers for the view (E3) | +15-25 | |
| `EDIT` word and EXROM call | +40-60 | |
| View, navigation, redraw, store routines (E4) | | +2,200-2,600 |
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
| N1 | `store-lines` | committed lines are CR-ended records in `$D000`; `WORKSPACE_END` exact | (fails: space-separated) |
| N2 | `store-full` | an append that does not fit is refused with a message; nothing above `$EFFF` changes | (fails: overrun) |
| N3 | `cr-whitespace` | source with CR between words interprets as with spaces, `INTERPRET_RUN` and `LOAD-TEXT` | (fails: CR is part of a word) |
| N4 | `text-tape-roundtrip` | `SAVE-TEXT` captured, decoded, played back, `LOAD-TEXT`: store byte-identical (reuses `tools/tapetest.py`) | (passes, space-separated) |
| N5 | `dict-ceiling` | a dictionary growing to the store's start THROWs -8, store untouched (E2) | (fails: store overwritten) |
| N6 | `edit-open` | `EDIT SQ` shows the view with the cursor on `: SQ`; `EDIT` alone at the end | (fails: no `EDIT`) |
| N7 | `edit-keys` | view navigation: LEFT, RIGHT, UP, DOWN across wrapped rows and lines; DELETE; ENTER splits; delete-line; insert-line; BREAK leaves | (fails) |
| N8 | `edit-commit` | leaving the view interprets only changed lines; an unchanged session interprets nothing | (fails) |
| N9 | `edit-redraw-oracle` | after every key in the view the screen equals a full view redraw | (fails) |
| N10 | `edit-no-exrom` | with a stock-shaped EXROM `EDIT` reports an error and the console works | (fails: no `EDIT`) |
| N11 | `edit-64col` | `EDIT` in 64-column mode shows the 32-column view and restores 64 on exit (E9) | (fails) |
| N12 | `edit-typing-cost` | typing cost in the view recorded (no old figure; the gate is set from this first measurement) | (n/a) |

## 9. Implementation order (one commit each, ledger figures in the last)

1. This spec.
2. Oracle: the T12 cases plus E's new cases, run on the old build; results in `docs/V2/evidence/`.
   If the owner runs O13 (data-stack calls through RST vectors, `LEAPC_COMPARISON_AUDIT.md` section 4) before E's
   code, it lands here, and E's byte figures are measured after it.
3. CR as whitespace in `WORD`; the store's line contract in HOME; workspace room check (E1, E5).
4. Dictionary ceiling (E2).
5. Merged redraw (E3).
6. Engine veneers; the view in the EXROM (E4).
7. `EDIT`, `RECALL` retired (E6); docs, tutorial, audit ledger.

Each step: `make check`, `make test`, `make edtest`, `make harness`; `make tapetest` from step 3 on (text tapes).

## 10. Verification limits

- No hardware: every result is ZEsarUX running the ROM images. Key presses through `Console.press` are held until the
  ISR accepts them, so contact bounce and fast typing on a real keyboard are not exercised.
- The screen is read from video RAM; flicker is judged by the full-redraw oracle (no intermediate frame differs from
  a full redraw at the key wait), not by watching a display.
