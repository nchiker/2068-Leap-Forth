; ============================================================================
; core/editor.asm — Phase 6 (line editing), rewritten for real multi-row
; word wrap
;
; Builds on core/interp.asm (INTERPRET_RUN) and needs kernel/io
; (IO_READ_KEY) and kernel/graphics (GFX_PUTCHAR, GFX_SET_ATTR,
; GFX_CLEAR_ROW, GFX_INVERT_ATTR, GFX_SCROLL_OUTPUT_UP) and
; core/print.asm (PRINT_ROW, read-only here — see below) INCLUDEd
; alongside it. Adds NO new dictionary words — a line editor is the
; shell that reads a line and hands it to INTERPRET_RUN, the same
; relationship INTERPRET_RUN itself has to WORD/FIND/NUMBER (Phase 3).
;
; WHAT CHANGED, AND WHY: originally single-line only, capped at 31
; characters on one fixed row (EDIT_ROW=23) — typing past that limit
; silently dropped every further keystroke with zero feedback, an
; honestly-documented but real limitation. The user asked directly for
; real multi-row word wrap. This file now wraps a much longer line
; (EDIT_MAX_LEN, 128 characters — matching the sibling ts2068rom
; project's own reference buffer size for exactly this purpose) across
; up to FWRAP_MAX_ROWS (4) screen rows, breaking at word boundaries
; (the last space at-or-before column 32 of each row) rather than
; mid-word, the same idea ts2068rom's own `EDITOR_WRAP_OFFSET_TO_ROWCOL`
; /`EDITOR_WRAP_CALC` use — studied there first (a proven, already-
; shipped reference implementation) rather than designed from scratch,
; though this file's own version is considerably simpler: no keyword
; highlighting, no multi-statement program view, no `VIEW_TOP_INDEX`,
; and (per this project's own established scope) no EXROM/Home split —
; just: word-wrap ONE line currently being typed, across as many rows
; as it needs, with a flashing cursor, scrolling the WHOLE screen when
; it grows past what's currently free at the bottom.
;
; THE KEY SIMPLIFICATION THAT MADE THIS TRACTABLE: input and output
; NEVER share the screen at the same moment. This project's REPL model
; is strictly sequential — type a line, press ENTER, the line runs
; (any `EMIT`/`.`/`."`/`F.` output happens here, using
; `core/print.asm`'s OWN separate `PRINT_ROW`/`PRINT_COL`), THEN a
; fresh empty input line starts. There is no moment where a
; multi-row-wrapped, actively-being-typed line and live program output
; are both changing on screen at once. This means the editor's own
; multi-row area doesn't need to negotiate screen space with
; `core/print.asm` in real time — it only needs to know, once, whether
; growing by one row would clobber RECENT (still-relevant) output
; sitting in the row it's about to claim, checked by comparing that
; row against `PRINT_ROW`'s own CURRENT (unchanging, since no program
; is running while the user types) value — see EDITOR_REDRAW's own
; header for exactly how.
;
; SCREEN LAYOUT: the input line's OWN LAST row is always anchored at
; EDIT_ROW (23, the physical bottom of the screen) — as it needs more
; rows, it grows UPWARD (row 22, 21, 20 as FWRAP_COUNT reaches 2,
; 3, 4), scrolling the whole screen up first via `GFX_SCROLL_OUTPUT_UP`
; whenever the newly-needed row still holds relevant output. This
; means the visible input area is NOT a fixed set of reserved rows —
; it's exactly as tall as the current line needs, from 1 row (the
; common case, unchanged from before) up to 4.
;
; TWO ENTRY POINTS, unchanged in shape from the original Phase 6
; design:
;   EDITOR_PROCESS_KEY  the actual editing logic (insert/delete/cursor
;                       move/detect ENTER) — this is what's proven by
;                       rom/forth_smoke_p6.asm (canned key sequences,
;                       single-row cases) and rom/forth_smoke_p33.asm
;                       (canned key sequences specifically exercising
;                       word-boundary wrap, hard-break wrap, and the
;                       capacity limit at 4 rows).
;   EDITOR_LOOP_LIVE    the real interactive shell — see its own header
;                       for the still-open "no deterministic live-
;                       keyboard test" gap, unchanged from before.
; ============================================================================

    IFNDEF CORE_EDITOR_ASM
    DEFINE CORE_EDITOR_ASM

EDIT_ROW       EQU 23      ; the input line's own LAST row — always
                           ; anchored here; EARLIER rows (if the line
                           ; has wrapped) sit above it, computed fresh
                           ; each redraw as (EDIT_ROW+1-FWRAP_COUNT)
EDIT_COL_START EQU 0
EDIT_MAX_LEN   EQU 128     ; physical buffer capacity — matches the
                           ; sibling ts2068rom project's own reference
                           ; buffer size for a wrapped input line
FWRAP_MAX_ROWS  EQU 4       ; hard cap on rows a single input line may
                           ; use — chosen so the input can never grow
                           ; tall enough to push its own TOP row above
                           ; screen row 20, leaving row 0 (the boot
                           ; banner) and everything above row 20
                           ; comfortably alone even in the worst case

; ---- Phase 6 RAM state, RELOCATED for this rewrite. The original
; 32-byte EDIT_BUF at $8550 could not simply grow in place — it sits
; directly against core/storage.asm's own SAVE_NAME_PTR at $8580 (that
; file's own header: "placed after core/editor.asm's own cells (ending
; at $8574)"), so a 128-byte buffer starting at $8550 would have run
; straight into storage.asm's own scratch. Verified by grepping every
; "EQU $8..." across core/, kernel/, include/, and rom/ first (the same
; method every phase since Phase 5 has used): $8860-$88F4 is free —
; comfortably past every existing core/ file's own scratch (the
; highest before this was core/beep.asm's own BEEP_PITCH_PARAM, ending
; $8860) and comfortably below core/float.asm's own FSTACK_LIMIT
; ($8C00). rom/forth_smoke_p3.asm/p4.asm/p5.asm/p6.asm's own
; CHECKPOINT_NUM cells (still at $8542/$8574, described in their own
; comments as sitting "right after core/editor.asm's own cells") are
; now stale in that ONE respect — those addresses are still genuinely
; free and still work, just no longer literally adjacent to this file's
; own (now relocated) scratch. ----
EDIT_BUF           EQU $8860   ; 128 bytes: the line being edited, not
                               ; null-terminated (EDIT_LEN is authoritative)
EDIT_LEN           EQU $88E0   ; 1 byte: current number of characters in EDIT_BUF
EDIT_CURSOR        EQU $88E1   ; 1 byte: cursor position within EDIT_BUF, 0..EDIT_LEN
SHIFT_COUNT        EQU $88E2   ; 1 byte: INSERT_CHAR/DELETE_CHAR_BEFORE_CURSOR's
                               ; own scratch (bytes remaining to shift)
INS_CHAR_TMP       EQU $88E3   ; 1 byte: INSERT_CHAR's own scratch (the char
                               ; being inserted, held across the shift loop)
FWRAP_COUNT    EQU $88E4   ; 1 byte: how many rows the CURRENT line
                               ; wraps across (1-FWRAP_MAX_ROWS), set
                               ; fresh by WRAP_CALC every redraw
FWRAP_START    EQU $88E5   ; 4 bytes: FWRAP_START+i = the
                               ; EDIT_BUF offset where wrapped row i's
                               ; own visible content starts
FWRAP_LEN      EQU $88E9   ; 4 bytes: FWRAP_LEN+i = how many
                               ; characters of visible content wrapped
                               ; row i shows (0-32)
FWRAP_SCAN_PTR EQU $88ED   ; 2 bytes: WRAP_CALC's own scratch (a
                               ; pointer to the row currently being
                               ; computed's own start in EDIT_BUF)
FWRAP_REMAIN   EQU $88EF   ; 1 byte: WRAP_CALC's own scratch
                               ; (characters not yet assigned to a row)
FWRAP_ROW_IDX  EQU $88F0   ; 1 byte: shared loop-index scratch —
                               ; WRAP_CALC's own "row being computed"
                               ; and (at a different time, never
                               ; concurrently) EDIT_CURSOR_TO_ROWCOL's
                               ; own "row being tested"
FWRAP_LAST_SPACE EQU $88F1 ; 1 byte: WRAP_CALC's own scratch — the
                               ; highest relative position (1-31) of a
                               ; space found in the current row's own
                               ; 32-column scan window, or $FF if none
FWRAP_TMP_LEN    EQU $88F2 ; 1 byte: WRAP_STORE_ROW's own scratch
FWRAP_TMP_OFFSET EQU $88F3 ; 1 byte: WRAP_STORE_ROW's own scratch
FWRAP_OLD_COUNT  EQU $88F4 ; 1 byte: FWRAP_COUNT's own value as
                               ; of the LAST redraw — compared against
                               ; the freshly-recomputed count every
                               ; redraw to decide whether the input
                               ; area just grew (scroll to make room)
                               ; or shrank (clear the rows it no longer
                               ; needs). MUST be initialized to 1 by
                               ; whatever ROM uses this file, once, at
                               ; cold start (`xor a` / `inc a` / `ld
                               ; (FWRAP_OLD_COUNT),a`, or just `ld
                               ; a,1`) — EDITOR_LOOP_LIVE deliberately
                               ; does NOT reset it on every fresh line
                               ; (see that routine's own header for
                               ; why), so its value is only ever correct
                               ; from the second line onward unless the
                               ; very first redraw is seeded explicitly,
                               ; the same "no assumed default" rule
                               ; core/print.asm's own PRINT_ROW/
                               ; PRINT_COL already follow.
FWRAP_OVERFLOW   EQU $88F5 ; 1 byte: set by WRAP_CALC — 0 normally, 1
                           ; if the CURRENT EDIT_BUF/EDIT_LEN genuinely
                           ; needs more than FWRAP_MAX_ROWS rows to show
                           ; it all. See WRAP_CALC's own header for why
                           ; this can't just be read off FWRAP_COUNT
                           ; (which never exceeds FWRAP_MAX_ROWS by
                           ; construction, cap or no cap) — a real bug
                           ; caught designing this file's own smoke ROM
                           ; test cases in Python first, not in Z80:
                           ; the original design checked FWRAP_COUNT
                           ; alone in EDITOR_PROCESS_KEY's own room
                           ; check, which could never actually fire,
                           ; silently accepting characters into EDIT_BUF
                           ; that would never appear in any row's own
                           ; wrap-table entry at all. Ends at $88F6.

; ============================================================================
; INSERT_CHAR ( A = character )
; Inserts A at EDIT_CURSOR, shifting everything from EDIT_CURSOR to the
; old end of the buffer up by one position first. Caller must already
; have checked EDIT_LEN < EDIT_MAX_LEN — unchanged algorithm from the
; original Phase 6 version, just operating on the bigger buffer. Does
; NOT check whether the result still fits within FWRAP_MAX_ROWS rows —
; see EDITOR_PROCESS_KEY's own header for why that check happens AFTER
; this, not before, and how a too-tall result gets undone.
; ============================================================================
INSERT_CHAR:
    ld   (INS_CHAR_TMP), a
    ld   a, (EDIT_LEN)
    ld   c, a                 ; c = len
    ld   a, (EDIT_CURSOR)
    ld   b, a                 ; b = cursor
    ld   a, c
    sub  b
    ld   (SHIFT_COUNT), a     ; bytes to shift = len - cursor
    or   a
    jr   z, .no_shift
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, c
    add  hl, de                ; hl = EDIT_BUF + len (new last slot, dest)
    push hl
    dec  hl                     ; hl = EDIT_BUF + len - 1 (old last char, source)
    ex   de, hl                  ; de = source
    pop  hl                       ; hl = dest
.shiftloop:
    ld   a, (de)
    ld   (hl), a
    dec  hl
    dec  de
    ld   a, (SHIFT_COUNT)
    dec  a
    ld   (SHIFT_COUNT), a
    jr   nz, .shiftloop
.no_shift:
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, b                   ; e = cursor
    add  hl, de
    ld   a, (INS_CHAR_TMP)
    ld   (hl), a
    ld   a, (EDIT_LEN)
    inc  a
    ld   (EDIT_LEN), a
    ld   a, (EDIT_CURSOR)
    inc  a
    ld   (EDIT_CURSOR), a
    ret

; ============================================================================
; DELETE_CHAR_BEFORE_CURSOR ( -- )
; Backspace semantics: removes the character immediately before
; EDIT_CURSOR, shifting everything after it down by one position.
; Caller must already have checked EDIT_CURSOR > 0. Unchanged from the
; original Phase 6 version.
; ============================================================================
DELETE_CHAR_BEFORE_CURSOR:
    ld   a, (EDIT_LEN)
    ld   c, a                 ; c = len
    ld   a, (EDIT_CURSOR)
    ld   b, a                 ; b = cursor
    ld   a, c
    sub  b
    ld   (SHIFT_COUNT), a     ; bytes to shift = len - cursor
    or   a
    jr   z, .no_shift
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, b
    dec  e
    add  hl, de                ; hl = EDIT_BUF + cursor - 1 (dest)
    push hl
    inc  hl                     ; hl = EDIT_BUF + cursor (source)
    ex   de, hl                  ; de = source
    pop  hl                       ; hl = dest
.shiftloop:
    ld   a, (de)
    ld   (hl), a
    inc  hl
    inc  de
    ld   a, (SHIFT_COUNT)
    dec  a
    ld   (SHIFT_COUNT), a
    jr   nz, .shiftloop
.no_shift:
    ld   a, (EDIT_LEN)
    dec  a
    ld   (EDIT_LEN), a
    ld   a, (EDIT_CURSOR)
    dec  a
    ld   (EDIT_CURSOR), a
    ret

; ============================================================================
; WRAP_STORE_ROW (internal) — A = content length for the row currently
; being computed by WRAP_CALC. Stores FWRAP_SCAN_PTR's own current
; offset (from EDIT_BUF) into FWRAP_START[FWRAP_ROW_IDX], and A
; into FWRAP_LEN[FWRAP_ROW_IDX]. Offsets always fit one byte
; (EDIT_MAX_LEN is 128).
; Destroys: AF, BC, DE, HL
; ============================================================================
WRAP_STORE_ROW:
    ld   (FWRAP_TMP_LEN), a
    ld   hl, (FWRAP_SCAN_PTR)
    ld   de, EDIT_BUF
    or   a
    sbc  hl, de
    ld   a, l
    ld   (FWRAP_TMP_OFFSET), a
    ld   a, (FWRAP_ROW_IDX)
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (FWRAP_TMP_OFFSET)
    ld   (hl), a
    ld   a, (FWRAP_ROW_IDX)
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_LEN
    add  hl, de
    ld   a, (FWRAP_TMP_LEN)
    ld   (hl), a
    ret

; ============================================================================
; WRAP_CALC ( -- ) — populates FWRAP_COUNT/FWRAP_START/
; FWRAP_LEN from the CURRENT EDIT_BUF/EDIT_LEN. Each row holds up
; to 32 characters, breaking at the LAST space at or before column 32
; (the space itself is consumed but never drawn — matching
; ts2068rom's own EDITOR_WRAP_CALC exactly) so a word is never split
; across rows UNLESS a single word alone is too long to fit in one
; row's own 32-column window at all, in which case (and ONLY then) it
; hard-breaks at exactly column 32. Stops early, capped at
; FWRAP_MAX_ROWS, if content would need more rows than that — see
; EDITOR_PROCESS_KEY's own header for why a committed edit should never
; actually reach that cap.
; Destroys: AF, BC, DE, HL
; ============================================================================
WRAP_CALC:
    xor  a
    ld   (FWRAP_ROW_IDX), a
    ld   (FWRAP_OVERFLOW), a
    ld   hl, EDIT_BUF
    ld   (FWRAP_SCAN_PTR), hl
    ld   a, (EDIT_LEN)
    ld   (FWRAP_REMAIN), a
.row_loop:
    ld   a, (FWRAP_REMAIN)
    cp   33
    jr   c, .last_row              ; remain <= 32 -- this is the last row
    ; scan this row's own 32-column window (relative positions 31
    ; down to 1) for the LAST (highest-position) space
    ld   hl, (FWRAP_SCAN_PTR)
    ld   de, 31
    add  hl, de
    ld   b, 31
    ld   a, $FF
    ld   (FWRAP_LAST_SPACE), a
.scan_loop:
    ld   a, (hl)
    cp   " "
    jr   nz, .scan_next
    ld   a, b
    ld   (FWRAP_LAST_SPACE), a
    jr   .scan_done                 ; scanning high-to-low, so the FIRST
                                     ; space found is the highest one
.scan_next:
    dec  hl
    djnz .scan_loop
.scan_done:
    ld   a, (FWRAP_LAST_SPACE)
    cp   $FF
    jr   z, .hard_break
    call WRAP_STORE_ROW              ; a = content length (last_space_rel)
    ld   a, (FWRAP_LAST_SPACE)
    inc  a                            ; consumed = last_space_rel + 1
    jr   .advance
.hard_break:
    ld   a, 32
    call WRAP_STORE_ROW
    ld   a, 32                        ; consumed = 32
.advance:
    ld   b, a                          ; b = consumed
    ld   hl, (FWRAP_SCAN_PTR)
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   (FWRAP_SCAN_PTR), hl
    ld   a, (FWRAP_REMAIN)
    sub  b
    ld   (FWRAP_REMAIN), a
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    ld   (FWRAP_ROW_IDX), a
    cp   FWRAP_MAX_ROWS
    jr   c, .row_loop                  ; still under the cap -- continue
    ; hit the cap exactly on this row -- anything left over means the
    ; TRUE content needs more than FWRAP_MAX_ROWS rows to show at all
    ld   a, (FWRAP_REMAIN)
    or   a
    jr   z, .done
    ld   a, 1
    ld   (FWRAP_OVERFLOW), a
    jr   .done
.last_row:
    ld   a, (FWRAP_REMAIN)
    call WRAP_STORE_ROW
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    ld   (FWRAP_ROW_IDX), a
.done:
    ld   a, (FWRAP_ROW_IDX)
    ld   (FWRAP_COUNT), a
    ret

    IFDEF KERNEL_MODE64_ASM         ; real 64-column TEXT mode only
                                    ; exists once kernel/mode64/mode64.asm
                                    ; is INCLUDEd -- guarded so this adds
                                    ; zero bytes to any ROM that doesn't
                                    ; use it, same convention as
                                    ; EDITOR_REDRAW64/core/print.asm's
                                    ; W_EMIT (confirmed via a binary diff
                                    ; against an unguarded first draft,
                                    ; which silently cost every editor.asm
                                    ; caller real bytes it never asked for)
; ============================================================================
; WRAP_CALC64 ( -- ) — WRAP_CALC's own algorithm verbatim, with the
; 32-column window widened to 64 throughout (33/32/31 -> 65/64/63) --
; a full sibling rather than a parameterized version of WRAP_CALC,
; matching this project's own established precedent for exactly this
; situation (kernel/graphics's own GFX_SET_ATTR_EXT header reasons
; through why a sibling beats parameterizing a tested routine). Used
; by EDITOR_REDRAW only when GFX_MODE=2 (core/hires.asm-style mode
; branch). FWRAP_MAX_ROWS/FWRAP_START/FWRAP_LEN need no changes here --
; EDIT_MAX_LEN (128) only ever needs 2 of the 4 available row slots at
; 64 characters/row, well under the existing cap.
; Destroys: AF, BC, DE, HL
; ============================================================================
WRAP_CALC64:
    xor  a
    ld   (FWRAP_ROW_IDX), a
    ld   (FWRAP_OVERFLOW), a
    ld   hl, EDIT_BUF
    ld   (FWRAP_SCAN_PTR), hl
    ld   a, (EDIT_LEN)
    ld   (FWRAP_REMAIN), a
.row_loop:
    ld   a, (FWRAP_REMAIN)
    cp   65
    jr   c, .last_row              ; remain <= 64 -- this is the last row
    ld   hl, (FWRAP_SCAN_PTR)
    ld   de, 63
    add  hl, de
    ld   b, 63
    ld   a, $FF
    ld   (FWRAP_LAST_SPACE), a
.scan_loop:
    ld   a, (hl)
    cp   " "
    jr   nz, .scan_next
    ld   a, b
    ld   (FWRAP_LAST_SPACE), a
    jr   .scan_done
.scan_next:
    dec  hl
    djnz .scan_loop
.scan_done:
    ld   a, (FWRAP_LAST_SPACE)
    cp   $FF
    jr   z, .hard_break
    call WRAP_STORE_ROW
    ld   a, (FWRAP_LAST_SPACE)
    inc  a
    jr   .advance
.hard_break:
    ld   a, 64
    call WRAP_STORE_ROW
    ld   a, 64
.advance:
    ld   b, a
    ld   hl, (FWRAP_SCAN_PTR)
    ld   d, 0
    ld   e, b
    add  hl, de
    ld   (FWRAP_SCAN_PTR), hl
    ld   a, (FWRAP_REMAIN)
    sub  b
    ld   (FWRAP_REMAIN), a
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    ld   (FWRAP_ROW_IDX), a
    cp   FWRAP_MAX_ROWS
    jr   c, .row_loop
    ld   a, (FWRAP_REMAIN)
    or   a
    jr   z, .done
    ld   a, 1
    ld   (FWRAP_OVERFLOW), a
    jr   .done
.last_row:
    ld   a, (FWRAP_REMAIN)
    call WRAP_STORE_ROW
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    ld   (FWRAP_ROW_IDX), a
.done:
    ld   a, (FWRAP_ROW_IDX)
    ld   (FWRAP_COUNT), a
    ret
    ENDIF

; ============================================================================
; EDIT_CURSOR_TO_ROWCOL ( -- B=screen row, C=screen column ) — converts
; the linear EDIT_CURSOR offset into a screen position, using the wrap
; table WRAP_CALC must already have populated for the CURRENT EDIT_BUF/
; EDIT_LEN/EDIT_CURSOR.
;
; THE ALGORITHM: for each row (except the last), compare EDIT_CURSOR
; against the OFFSET WHERE THE NEXT ROW STARTS (FWRAP_START[row+1])
; rather than against this row's own content length. This single
; choice elegantly handles both real edge cases at once, with no
; separate special-casing needed (confirmed by hand-tracing both):
;   - A cursor sitting exactly on a CONSUMED (skipped, never-drawn)
;     space between two word-wrapped rows compares LESS than the next
;     row's own start (which is one further, past that space) — so it
;     stays on the CURRENT row, landing at column = this row's own
;     content length (i.e. right after the last visible character,
;     the natural place to show a cursor that's logically "before" an
;     invisible space) — exactly matching ts2068rom's own documented
;     convention for this case, arrived at here as a side effect of
;     the comparison rather than a separate rule.
;   - A cursor sitting exactly at the end of a FULL, hard-broken
;     32-column row (no consumed space, next row starts immediately at
;     +32) compares EQUAL to the next row's own start — so it rolls
;     forward onto the NEXT row at column 0, instead of computing an
;     out-of-range column 32. This is ts2068rom's own documented "Bug
;     B" (`GFX_ATTR_SWAP`'s out-of-range write, already fixed at that
;     layer in this project's own kernel/graphics.asm) avoided by
;     construction here rather than merely tolerated by that lower-
;     level safety net. Column 32 can still occur, but only in the
;     genuinely unavoidable case of the cursor sitting at the very end
;     of a maximally-long (all FWRAP_MAX_ROWS rows full, no trailing
;     space anywhere) line, where there is no next row to roll onto —
;     GFX_INVERT_ATTR's own bounds check (shared with GFX_SET_ATTR)
;     safely no-ops rather than corrupting anything in that rare case,
;     at the cost of simply not showing a cursor block there.
; Destroys: AF, BC, DE, HL
; ============================================================================
EDIT_CURSOR_TO_ROWCOL:
    xor  a
    ld   (FWRAP_ROW_IDX), a
.loop:
    ld   a, (FWRAP_COUNT)
    dec  a
    ld   hl, FWRAP_ROW_IDX
    cp   (hl)
    jr   z, .found                      ; last row -- always matches
    ld   a, (hl)
    inc  a
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (EDIT_CURSOR)
    cp   (hl)                            ; cursor - next_row_start
    jr   c, .found                        ; cursor < next row's start
    ld   hl, FWRAP_ROW_IDX
    ld   a, (hl)
    inc  a
    ld   (hl), a
    jr   .loop
.found:
    ld   a, (FWRAP_ROW_IDX)
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (EDIT_CURSOR)
    sub  (hl)
    ld   c, a                             ; c = column
    ld   a, EDIT_ROW + 1
    ld   hl, FWRAP_COUNT
    sub  (hl)                              ; a = (EDIT_ROW+1) - wrap_count
                                            ; = this line's own top row
    ld   hl, FWRAP_ROW_IDX
    add  a, (hl)                            ; + this row's own index
    ld   b, a                                ; b = screen row
    ret

; ============================================================================
; EDITOR_REDRAW ( -- )
; Redraws the whole (possibly multi-row) input line from scratch every
; time — simple and correct rather than incremental, the same choice
; the original single-row version made and for the same reason: even
; at up to 4 rows/128 columns, a full redraw on every keystroke has no
; real performance problem on this hardware.
;
; GROW/SHRINK HANDLING: compares the freshly-computed FWRAP_COUNT
; against FWRAP_OLD_COUNT (the value as of the LAST redraw).
;   - GREW (the line just wrapped onto a new row): that new row's own
;     screen position might still hold RECENT output from the program
;     that ran just before this input line started (see this file's
;     own top header on why input and output never change on screen at
;     the same moment, which is what makes this a one-time check rather
;     than an ongoing negotiation) — checked by comparing that row
;     against `core/print.asm`'s own PRINT_ROW, read-only, which
;     cannot change again until AFTER this input line is submitted and
;     interpreted. If PRINT_ROW reaches that row, the whole screen
;     scrolls up one row first (`GFX_SCROLL_OUTPUT_UP`) to preserve it,
;     and PRINT_ROW itself is adjusted down by one to stay consistent
;     for whatever this line's own eventual execution prints next.
;     Looped (not a single check) to stay correct even if a single
;     keystroke somehow grew the wrap count by more than one row,
;     though that shouldn't ordinarily happen.
;   - SHRANK (backspace crossed back over a row boundary): the row(s)
;     no longer needed are simply cleared — no attempt to "un-scroll"
;     whatever used to be above them, matching how real terminals never
;     restore scrolled-off content either.
; ============================================================================
EDITOR_REDRAW:
    IFDEF KERNEL_MODE64_ASM        ; real 64-column TEXT mode (Phase
                                    ; 56/57/58) only exists once
                                    ; kernel/mode64/mode64.asm is
                                    ; INCLUDEd (several smoke ROMs use
                                    ; the editor without it) -- guarded
                                    ; so this stays zero extra bytes
                                    ; everywhere else, same convention
                                    ; as core/print.asm's W_EMIT
    ld   a, (GFX_MODE)
    cp   2
    jp   z, EDITOR_REDRAW64
    ENDIF
    call WRAP_CALC
    ld   a, (FWRAP_COUNT)
    ld   hl, FWRAP_OLD_COUNT
    cp   (hl)
    jr   z, .count_settled
    jr   c, .shrank
.grow_loop:
    ld   a, (hl)                        ; current (not-yet-updated) old count
    ld   b, a
    ld   a, EDIT_ROW + 1
    sub  b                               ; a = row about to be newly claimed
    ld   c, a
    ld   a, (PRINT_ROW)
    cp   c
    jr   c, .no_scroll_needed             ; PRINT_ROW is above that row --
                                           ; already blank, nothing to save
    call GFX_SCROLL_OUTPUT_UP
    ld   a, (PRINT_ROW)
    dec  a
    ld   (PRINT_ROW), a
.no_scroll_needed:
    ld   a, (hl)
    inc  a
    ld   (hl), a
    ld   a, (FWRAP_COUNT)
    cp   (hl)
    jr   nz, .grow_loop
    jr   .count_settled
.shrank:
    ld   a, EDIT_ROW + 1
    sub  (hl)                            ; a = old top row
    ld   b, a
.clear_loop:
    push bc
    call GFX_CLEAR_ROW
    pop  bc
    inc  b
    ld   a, EDIT_ROW + 1
    ld   c, a
    ld   a, (FWRAP_COUNT)
    ld   hl, FWRAP_OLD_COUNT
    ; fallthrough uses hl below, so reload after the compare
    ld   hl, FWRAP_COUNT
    ld   a, c
    sub  (hl)                            ; a = new top row
    cp   b
    jr   nz, .clear_loop
    ld   hl, FWRAP_OLD_COUNT
.count_settled:
    ld   a, (FWRAP_COUNT)
    ld   (FWRAP_OLD_COUNT), a

    ; draw each wrapped row's own content, then blank-pad to column 31
    xor  a
    ld   (FWRAP_ROW_IDX), a
.row_draw_loop:
    ld   a, (FWRAP_ROW_IDX)
    ld   e, a
    ld   d, 0
    push de
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (hl)
    ld   e, a
    ld   d, 0
    ld   hl, EDIT_BUF
    add  hl, de                          ; hl = ptr to this row's own content
    pop  de
    push hl
    ld   hl, FWRAP_LEN
    add  hl, de
    ld   a, (hl)
    ld   e, a                            ; e = this row's own content length
    pop  hl                              ; hl = ptr to this row's own content
    push hl                              ; RE-STASH IT: a real bug lived
                                          ; here — the code below reuses
                                          ; HL (for FWRAP_COUNT's own
                                          ; address) before this row's
                                          ; content pointer was needed
                                          ; again, and the original
                                          ; version tried to "restore" it
                                          ; via an extra `pop hl` with NO
                                          ; matching push at that point —
                                          ; popping one level too many,
                                          ; corrupting the stack (in
                                          ; practice, EDITOR_REDRAW's own
                                          ; return address) on every
                                          ; single row drawn. Caught by
                                          ; rom/forth_smoke_p33.asm's own
                                          ; checkpoint 1 hanging under
                                          ; real Fuse, isolated with a
                                          ; waypoint-marker diagnostic
                                          ; ROM, not by inspection.
    ld   a, (FWRAP_ROW_IDX)
    ld   d, EDIT_ROW + 1
    push af
    ld   a, d
    ld   hl, FWRAP_COUNT
    sub  (hl)
    pop  bc                              ; b = row_idx (from the earlier af push)
    add  a, b
    ld   d, a                            ; d = this row's own screen row
    pop  hl                              ; hl = ptr to this row's own content
                                          ; -- correctly restored now,
                                          ; matching the push just above
    ld   c, EDIT_COL_START
.printloop:
    ld   a, e
    or   a
    jr   z, .blank
    ld   a, (hl)
    push hl
    push de
    push bc
    ld   b, d
    call GFX_PUTCHAR
    pop  bc
    pop  de
    push de
    push bc
    ld   a, ATTR_DEFAULT
    ld   b, d
    call GFX_SET_ATTR
    pop  bc
    pop  de
    pop  hl
    inc  hl
    inc  c
    dec  e
    jr   .printloop
.blank:
    ld   a, c
    cp   32
    jr   nc, .row_done
    push de
    push bc
    ld   a, " "
    ld   b, d
    call GFX_PUTCHAR
    pop  bc
    pop  de                    ; RESTORE d (row) before reusing it below --
    push de                    ; GFX_PUTCHAR destroys DE (it ends up
                                ; holding a leftover screen-bitmap
                                ; address byte, not the row), so without
                                ; this restore GFX_SET_ATTR silently got
                                ; called with a garbage row and no-opped,
                                ; permanently leaking every past cursor
                                ; position's own FLASH attribute (found
                                ; via a real live-typed "console" then
                                ; backspaced-to-empty, reported by the
                                ; user, reproduced with a deterministic
                                ; smoke ROM, and root-caused with direct
                                ; attribute-memory readback probes, not
                                ; guessed) — .printloop just above
                                ; already does this correctly, this loop
                                ; was just missing the matching restore
    push bc
    ld   a, ATTR_DEFAULT
    ld   b, d
    call GFX_SET_ATTR
    pop  bc
    pop  de
    inc  c
    jr   .blank
.row_done:
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    ld   (FWRAP_ROW_IDX), a
    ld   hl, FWRAP_COUNT
    cp   (hl)
    jr   c, .row_draw_loop

    call EDIT_CURSOR_TO_ROWCOL
    call GFX_INVERT_ATTR
    ret

    IFDEF KERNEL_MODE64_ASM
; ============================================================================
; EDITOR_REDRAW64 — EDITOR_REDRAW's own algorithm, for real 64-column
; TEXT mode (GFX_MODE=2). A full sibling rather than a mode-branch
; threaded through EDITOR_REDRAW's own body, matching this project's
; established precedent for exactly this situation (see WRAP_CALC64's
; own header) -- especially warranted here given this exact routine's
; own history of subtle stack-discipline bugs (the two incidents
; documented in the comments above), which a shared, more tangled body
; would only make easier to reintroduce.
;
; Three real differences from EDITOR_REDRAW, beyond the obvious
; 32-vs-64 width:
;   - WRAP_CALC64 instead of WRAP_CALC; MODE64_SCROLL_OUTPUT_UP/
;     MODE64_CLEAR_ROW instead of the GFX_ equivalents.
;   - MODE64_PUTCHAR instead of GFX_PUTCHAR, with NO attribute-stamping
;     call at all afterward (Mode 6 has no per-cell attribute byte to
;     stamp -- core/hires.asm's own EMIT precedent) -- this also
;     removes the extra push/pop round EDITOR_REDRAW's own printloop/
;     blank loop need solely to survive that now-absent second call.
;   - The cursor is a STATIC (non-blinking) MODE64_PUTCHAR_XOR block
;     instead of GFX_INVERT_ATTR -- Mode 6 has no hardware FLASH bit to
;     drive a blink the way the 32-column cursor gets for free; a real
;     blink would need new ISR timing and a rewrite of the live
;     keystroke-wait loop, deliberately out of scope (agreed with the
;     user before writing any of this file).
; ============================================================================
EDITOR_REDRAW64:
    call WRAP_CALC64
    ld   a, (FWRAP_COUNT)
    ld   hl, FWRAP_OLD_COUNT
    cp   (hl)
    jr   z, .count_settled64
    jr   c, .shrank64
.grow_loop64:
    ld   a, (hl)
    ld   b, a
    ld   a, EDIT_ROW + 1
    sub  b
    ld   c, a
    ld   a, (PRINT_ROW)
    cp   c
    jr   c, .no_scroll_needed64
    call MODE64_SCROLL_OUTPUT_UP
    ld   a, (PRINT_ROW)
    dec  a
    ld   (PRINT_ROW), a
.no_scroll_needed64:
    ld   a, (hl)
    inc  a
    ld   (hl), a
    ld   a, (FWRAP_COUNT)
    cp   (hl)
    jr   nz, .grow_loop64
    jr   .count_settled64
.shrank64:
    ld   a, EDIT_ROW + 1
    sub  (hl)
    ld   b, a
.clear_loop64:
    push bc
    call MODE64_CLEAR_ROW
    pop  bc
    inc  b
    ld   a, EDIT_ROW + 1
    ld   c, a
    ld   a, (FWRAP_COUNT)
    ld   hl, FWRAP_OLD_COUNT
    ld   hl, FWRAP_COUNT
    ld   a, c
    sub  (hl)
    cp   b
    jr   nz, .clear_loop64
    ld   hl, FWRAP_OLD_COUNT
.count_settled64:
    ld   a, (FWRAP_COUNT)
    ld   (FWRAP_OLD_COUNT), a

    xor  a
    ld   (FWRAP_ROW_IDX), a
.row_draw_loop64:
    ld   a, (FWRAP_ROW_IDX)
    ld   e, a
    ld   d, 0
    push de
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (hl)
    ld   e, a
    ld   d, 0
    ld   hl, EDIT_BUF
    add  hl, de                          ; hl = ptr to this row's own content
    pop  de
    push hl
    ld   hl, FWRAP_LEN
    add  hl, de
    ld   a, (hl)
    ld   e, a                            ; e = this row's own content length
    pop  hl                              ; hl = ptr to this row's own content
    push hl                              ; RE-STASH IT -- see EDITOR_REDRAW's
                                          ; own header for the real
                                          ; stack-corruption bug this
                                          ; exact shape once had; kept
                                          ; identical here on purpose
    ld   a, (FWRAP_ROW_IDX)
    ld   d, EDIT_ROW + 1
    push af
    ld   a, d
    ld   hl, FWRAP_COUNT
    sub  (hl)
    pop  bc                              ; b = row_idx (from the earlier af push)
    add  a, b
    ld   d, a                            ; d = this row's own screen row
    pop  hl                              ; hl = ptr to this row's own content
    ld   c, EDIT_COL_START
.printloop64:
    ld   a, e
    or   a
    jr   z, .blank64
    ld   a, (hl)
    push hl
    push de
    push bc
    ld   b, d
    call MODE64_PUTCHAR
    pop  bc
    pop  de
    pop  hl
    inc  hl
    inc  c
    dec  e
    jr   .printloop64
.blank64:
    ld   a, c
    cp   64
    jr   nc, .row_done64
    push de
    push bc
    ld   a, " "
    ld   b, d
    call MODE64_PUTCHAR
    pop  bc
    pop  de
    inc  c
    jr   .blank64
.row_done64:
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    ld   (FWRAP_ROW_IDX), a
    ld   hl, FWRAP_COUNT
    cp   (hl)
    jr   c, .row_draw_loop64

    call EDIT_CURSOR_TO_ROWCOL
    call MODE64_PUTCHAR_XOR         ; static (non-blinking) cursor block
                                    ; -- EDIT_CURSOR_TO_ROWCOL's own B=row/
                                    ; C=col output matches MODE64_PUTCHAR_
                                    ; XOR's contract directly, no shuffling
    ret
    ENDIF

; ============================================================================
; EDITOR_PROCESS_KEY ( A = key code -- )
; Out: carry set if A was ENTER (a line is ready in EDIT_BUF/EDIT_LEN;
; caller decides what to do with it — see EDITOR_LOOP_LIVE below).
; Carry clear otherwise (key handled, or ignored if unmapped/out of
; range — no error is ever raised here, matching every earlier phase's
; scope: this is a shell, not something a Forth program can catch an
; exception from).
;
; ROOM CHECK, CHANGED FOR WORD WRAP: the raw "EDIT_LEN < EDIT_MAX_LEN"
; check alone is no longer sufficient — the buffer might have physical
; room left but the wrapped RESULT could still need a 5th row, past
; FWRAP_MAX_ROWS. Rather than trying to predict this in advance (word-
; boundary wrap depends on exactly where existing spaces fall, not a
; simple arithmetic bound), the new character is inserted SPECULATIVELY
; first, WRAP_CALC re-run, and if the result would need more than
; FWRAP_MAX_ROWS rows, the insert is undone (a plain
; DELETE_CHAR_BEFORE_CURSOR-shaped reversal) and the keystroke is
; silently ignored — the same user-visible outcome ("buffer full") the
; original single-row version had, just at a much higher real capacity.
; ============================================================================
EDITOR_PROCESS_KEY:
    cp   KEY_ENTER
    jr   nz, .not_enter
    scf
    ret
.not_enter:
    cp   KEY_DELETE
    jr   nz, .not_delete
    ld   a, (EDIT_CURSOR)
    or   a
    jr   z, .done
    call DELETE_CHAR_BEFORE_CURSOR
    jr   .redraw_and_done
.not_delete:
    cp   KEY_CURSOR_LEFT
    jr   nz, .not_left
    ld   a, (EDIT_CURSOR)
    or   a
    jr   z, .done
    dec  a
    ld   (EDIT_CURSOR), a
    jr   .redraw_and_done
.not_left:
    cp   KEY_CURSOR_RIGHT
    jr   nz, .not_right
    ld   hl, EDIT_LEN
    ld   a, (EDIT_CURSOR)
    cp   (hl)
    jr   nc, .done             ; already at or past the end
    inc  a
    ld   (EDIT_CURSOR), a
    jr   .redraw_and_done
.not_right:
    cp   " "
    jr   c, .done              ; below space: unmapped/control, ignore
    cp   $7F
    jr   nc, .done              ; DEL and above: ignore
    push af                     ; save the key code -- checking EDIT_LEN
                                ; next needs A for itself
    ld   a, (EDIT_LEN)
    cp   EDIT_MAX_LEN
    jr   c, .room                ; len < physical max: proceed
    pop  af                       ; buffer already at physical capacity:
                                  ; discard the saved key code and ignore it
    jr   .done
.room:
    pop  af                       ; a = the original key code again
    call INSERT_CHAR
    call WRAP_CALC
    ld   a, (FWRAP_OVERFLOW)
    or   a
    jr   z, .fits                  ; the whole line still fits in
                                    ; FWRAP_MAX_ROWS rows -- keep it
    call DELETE_CHAR_BEFORE_CURSOR  ; undo the speculative insert --
                                    ; the just-inserted char is
                                    ; immediately before EDIT_CURSOR,
                                    ; exactly DELETE_CHAR_BEFORE_CURSOR's
                                    ; own contract
    jr   .done
.fits:
    jr   .redraw_and_done

.redraw_and_done:
    call EDITOR_REDRAW
.done:
    or   a
    ret

; ============================================================================
; EDITOR_LOOP_LIVE ( -- )
; The real interactive shell — reads a line from a real keyboard, runs
; it, and repeats forever. NOT exercised by the automated smoke test;
; see this file's own header for why, and for what IS proven instead.
;
; REAL PRECONDITION, discovered writing this routine, not assumed away:
; kernel/io's IO_READ_KEY does NOT scan the keyboard matrix itself
; (a real change from earlier in 2068-Leap's own history) — it only
; consumes a key already latched by kernel/interrupt's KBD_ISR_TICK,
; which must run on every real IM 1 interrupt. Calling EDITOR_LOOP_LIVE
; with interrupts disabled, or without RST $0038 vectoring to
; KBD_ISR_TICK, hangs forever at the very first keypress wait — not a
; bug in this routine, but a setup step it depends on and does not
; perform itself (matching kernel/bank's own precedent of documenting a
; precondition rather than each routine re-establishing global machine
; state). rom/forth_smoke_p6.asm's own COLD_START deliberately leaves
; interrupts disabled, same as every earlier smoke ROM in this project
; — its automated test never calls this routine, only
; EDITOR_PROCESS_KEY directly, so this precondition doesn't apply to
; what's actually proven there. Whatever future ROM first boots to a
; live interactive prompt (see docs/PROJECT_PLAN.md's own startup-sound
; product requirement, which implies exactly such a ROM) must set up
; RST $0038 -> KBD_ISR_TICK, IM 1, and EI before calling this.
; ============================================================================
EDITOR_LOOP_LIVE:
    xor  a
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a
    ; deliberately NOT resetting FWRAP_OLD_COUNT here -- it must
    ; still hold whatever the JUST-SUBMITTED line's own final row count
    ; was, so EDITOR_REDRAW's own shrink-detection (comparing that
    ; against the fresh line's own count, always 1 for an empty
    ; buffer) correctly clears away any leftover wrapped rows above
    ; EDIT_ROW the previous line left on screen. Resetting it to 1
    ; here would suppress that cleanup and leave stale text on screen
    ; from a previous multi-row line whenever the new one stays at 1
    ; row itself.
    call EDITOR_REDRAW
.keyloop:
    call IO_READ_KEY
    call EDITOR_PROCESS_KEY
    jr   nc, .keyloop
    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   d, 0
    ld   e, a
    call INTERPRET_RUN
    ; found live by the user: a successfully-run line gave no visible
    ; confirmation at all -- it just vanished, indistinguishable from
    ; nothing having happened. An error already prints "?"/"STACK?"
    ; (INTERP_ERROR_FLAG, set by those same hooks -- core/interp.asm's
    ; own header on it), so only print "OK" when neither fired.
    ld   a, (INTERP_ERROR_FLAG)
    or   a
    jr   nz, .no_ok
    ld   hl, "O"
    call DPUSH_HL
    call W_EMIT
    ld   hl, "K"
    call DPUSH_HL
    call W_EMIT
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT
.no_ok:
    jr   EDITOR_LOOP_LIVE

    ENDIF
