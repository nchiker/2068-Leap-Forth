; ============================================================================
; core/editor.asm -- the console line editor: word-wrapped multi-row input and the live REPL loop
;
; Needs core/interp.asm (INTERPRET_RUN, INTERP_ERROR_FLAG), kernel/io (IO_READ_KEY), kernel/graphics
; (GFX_PUTCHAR, GFX_SET_ATTR, GFX_INVERT_ATTR, GFX_SCROLL_OUTPUT_UP) and core/print.asm (PRINT_ROW,
; read here, never written except to follow a scroll). No dictionary words.
;
; The line (EDIT_BUF, at most EDIT_MAX_LEN = 128 characters) wraps over up to FWRAP_MAX_ROWS (4)
; screen rows, breaking at the last space at or before column 32 of each row, so the input area is
; as tall as the line needs, anchored with its last row at EDIT_ROW (23) and growing upward.
; Input and output never share the screen at once (a line is typed, then run, then a fresh line
; starts), so growing needs one check: if PRINT_ROW lies in the row about to be claimed, the
; whole screen scrolls up first.
;
; Entry points: EDITOR_PROCESS_KEY, the editing logic (insert, delete, cursor, ENTER), and
; EDITOR_LOOP_LIVE, the interactive shell. Every routine here may destroy all registers except IX, IY
; and SP.
; ============================================================================

    IFNDEF CORE_EDITOR_ASM
    DEFINE CORE_EDITOR_ASM

EDIT_ROW       EQU 23      ; the last row of the input line; earlier rows sit above it
EDIT_COL_START EQU 0
EDIT_MAX_LEN   EQU 128     ; the buffer's capacity
    ASSERT EDIT_LEN == EDIT_BUF + EDIT_MAX_LEN   ; EDIT_BUF's size in include/forth_layout.inc
FWRAP_MAX_ROWS  EQU 4      ; the most rows an input line may use: its top row stays at row 20 or below

; ============================================================================
; INSERT_CHAR -- insert a character at EDIT_CURSOR, shifting the rest up one. The caller has checked
; EDIT_LEN < EDIT_MAX_LEN; whether the result fits FWRAP_MAX_ROWS rows is checked after (see
; EDITOR_EDIT_KEY)
; In:  A = the character
; Out: EDIT_LEN and EDIT_CURSOR advanced by 1
; Destroys: AF, BC, DE, HL, and the cells INS_CHAR_TMP and SHIFT_COUNT
; ============================================================================
INSERT_CHAR:
    ld   (INS_CHAR_TMP), a
    ld   a, (EDIT_LEN)
    ld   c, a                 ; C = len
    ld   a, (EDIT_CURSOR)
    ld   b, a                 ; B = cursor
    ld   a, c
    sub  b
    ld   (SHIFT_COUNT), a     ; bytes to shift = len - cursor
    or   a
    jr   z, .no_shift
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, c
    add  hl, de                ; HL = EDIT_BUF + len, the new last slot (dest)
    push hl
    dec  hl                     ; the old last character (source)
    ex   de, hl                  ; DE = source
    pop  hl                       ; HL = dest
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
    ld   e, b                   ; E = cursor
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
; DELETE_CHAR_BEFORE_CURSOR -- backspace: remove the character before EDIT_CURSOR, shifting the rest
; down one. The caller has checked EDIT_CURSOR > 0
; Out: EDIT_LEN and EDIT_CURSOR decreased by 1
; Destroys: AF, BC, DE, HL, and the cell SHIFT_COUNT
; ============================================================================
DELETE_CHAR_BEFORE_CURSOR:
    ld   a, (EDIT_LEN)
    ld   c, a                 ; C = len
    ld   a, (EDIT_CURSOR)
    ld   b, a                 ; B = cursor
    ld   a, c
    sub  b
    ld   (SHIFT_COUNT), a     ; bytes to shift = len - cursor
    or   a
    jr   z, .no_shift
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, b
    dec  e
    add  hl, de                ; HL = EDIT_BUF + cursor - 1 (dest)
    push hl
    inc  hl                     ; the character after it (source)
    ex   de, hl                  ; DE = source
    pop  hl                       ; HL = dest
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
; WRAP_STORE_ROW -- record one row of the wrap table: FWRAP_SCAN_PTR's offset from FWRAP_BASE into
; FWRAP_START[FWRAP_ROW_IDX] and the length into FWRAP_LEN[FWRAP_ROW_IDX] (offsets fit one byte)
; In:  A = the row's content length
; Destroys: AF, BC, DE, HL
; ============================================================================
WRAP_STORE_ROW:
    ld   (FWRAP_TMP_LEN), a
    ld   hl, (FWRAP_SCAN_PTR)
    ld   de, (FWRAP_BASE)
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
; WRAP_CALC -- the wrap table of the edit line (EDIT_BUF, EDIT_LEN, EDIT_CURSOR)
; WRAP_CALC_AT -- the wrap table of any text
; In:  (WRAP_CALC_AT) HL = the text, A = its length (0-128), C = the cursor offset ($FF: none)
; Out: FWRAP_COUNT, FWRAP_START and FWRAP_LEN (offsets from FWRAP_BASE = HL), FWRAP_OVERFLOW = 1 if
;      the text needs more than FWRAP_MAX_ROWS rows (the table then stops at that cap)
; Destroys: AF, BC, DE, HL
;
; A row holds up to W = 32 characters; the width and the row drawer (ED_ROW_JP) are set here, so
; the room check, the drawing and the cursor all use the same width. A row breaks at the last
; space at or before its column limit (the space is consumed, never drawn), so a word is split
; only when it alone is too long for a row: then it breaks at exactly W.
;
; Cursor on a full row: when the last row holds exactly W characters and the cursor is at the end
; of the text, that row is stored as a hard break and the table gets one more row (start =
; length, 0 characters), the cursor at its column 0, as for a text one character longer. Only
; under the cap: a line already on FWRAP_MAX_ROWS rows gets no further row (EDIT_CURSOR_TO_ROWCOL
; then clamps the cursor to the last character's cell). The overflow test ignores that extra row.
;
; The full-screen view (EXROM) wraps its other lines with WRAP_CALC_AT in place in the store (C =
; $FF) and its cursor line, copied to EDIT_BUF, with WRAP_CALC; then FWRAP_TOP, ED_DRAW_ROWS and
; ED_DRAW_CURSOR draw them.
; ============================================================================
WRAP_CALC:
    ld   hl, EDIT_BUF
    ld   a, (EDIT_CURSOR)
    ld   c, a
    ld   a, (EDIT_LEN)
WRAP_CALC_AT:
    ld   (FWRAP_BASE), hl
    ld   (FWRAP_SCAN_PTR), hl
    ld   (FWRAP_REMAIN), a
    sub  c
    ld   (FWRAP_CURSOR_AT_END), a   ; 0: the cursor is at the end
    ld   a, $C3                     ; JP: ED_ROW_JP is a RAM veneer
    ld   (ED_ROW_JP), a
    ld   hl, ED_ROW32
    ld   a, 31
    ld   (ED_ROW_JP + 1), hl
    ld   (FWRAP_WIDTH_MINUS1), a
    xor  a
    ld   (FWRAP_ROW_IDX), a
    ld   (FWRAP_OVERFLOW), a
.row_loop:
    ld   a, (FWRAP_WIDTH_MINUS1)
    inc  a                             ; A = WIDTH (32)
    ld   c, a
    ld   a, (FWRAP_REMAIN)
    cp   c
    jr   c, .last_row                  ; remain < WIDTH
    jr   z, .full_row                  ; remain = WIDTH: the last row, unless the cursor needs a row
    ; scan the row's window, positions WIDTH-1 down to 1, for the last space
    ld   a, (FWRAP_WIDTH_MINUS1)
    ld   hl, (FWRAP_SCAN_PTR)
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   b, a
    ld   a, $FF
    ld   (FWRAP_LAST_SPACE), a
.scan_loop:
    ld   a, (hl)
    cp   " "
    jr   nz, .scan_next
    ld   a, b
    ld   (FWRAP_LAST_SPACE), a
    jr   .scan_done                 ; scanning downward: the first space found is the last one
.scan_next:
    dec  hl
    djnz .scan_loop
.scan_done:
    ld   a, (FWRAP_LAST_SPACE)
    cp   $FF
    jr   z, .hard_break
    call WRAP_STORE_ROW              ; A = the content length, up to the space
    ld   a, (FWRAP_LAST_SPACE)
    inc  a                            ; consumed: the content and the space
    jr   .advance
.full_row:
    ld   a, (FWRAP_CURSOR_AT_END)
    or   a
    jr   nz, .last_row
.hard_break:
    ld   a, (FWRAP_WIDTH_MINUS1)
    inc  a                             ; A = WIDTH
    call WRAP_STORE_ROW
    ld   a, (FWRAP_WIDTH_MINUS1)
    inc  a                             ; consumed = WIDTH
.advance:
    ld   b, a                          ; B = consumed
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
    jr   c, .row_loop                  ; under the cap
    ; at the cap: text left over needs more than FWRAP_MAX_ROWS rows
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

; ============================================================================
; EDIT_CURSOR_TO_ROWCOL -- the screen position of EDIT_CURSOR, from the wrap table WRAP_CALC filled
; for the current line and FWRAP_TOP (the screen row of the line's first row)
; Out: B = the screen row, C = the screen column
; Destroys: AF, BC, DE, HL
;
; For each row but the last the cursor is compared with where the NEXT row starts, not with this
; row's length. A cursor on a consumed space between two wrapped rows is below the next start and
; stays on this row, in the column after its last visible character. A cursor at the end of a full,
; hard-broken row equals the next start and rolls onto the next row at column 0 (WRAP_CALC gives a
; full last row such a row). Column WIDTH is left only for a line on FWRAP_MAX_ROWS full rows with
; the cursor at its end; it is clamped to WIDTH-1.
; ============================================================================
EDIT_CURSOR_TO_ROWCOL:
    xor  a
    ld   (FWRAP_ROW_IDX), a
.loop:
    ld   a, (FWRAP_COUNT)
    dec  a
    ld   hl, FWRAP_ROW_IDX
    cp   (hl)
    jr   z, .found                      ; the last row always matches
    ld   a, (hl)
    inc  a
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_START
    add  hl, de
    ld   a, (EDIT_CURSOR)
    cp   (hl)
    jr   c, .found                        ; cursor < the next row's start
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
    sub  (hl)                             ; A = the column
    ld   hl, FWRAP_WIDTH_MINUS1
    cp   (hl)
    jr   c, .col_ok
    ld   a, (hl)                          ; WIDTH -> WIDTH-1
.col_ok:
    ld   c, a
    ld   a, (FWRAP_TOP)
    add  a, e                             ; plus this row's index
    ld   b, a
    ret

; ============================================================================
; EDITOR_REDRAW -- redraw the whole input line: WRAP_CALC, grow or shrink the input area, draw the
; rows from FWRAP_TOP = EDIT_ROW + 1 - FWRAP_COUNT, then the cursor
; Destroys: AF, BC, DE, HL
;
; FWRAP_COUNT is compared with FWRAP_OLD_COUNT (the count at the last redraw) one row at a time,
; both read afresh each pass: the scroll destroys every register, and keeping an address in HL
; across it hung.
;   Grew: the claimed row 24 - old may hold recent output. If PRINT_ROW is at that row or below, the
;   whole screen scrolls up one row and PRINT_ROW follows it.
;   Shrank (backspace over a row boundary): the unneeded rows are cleared, top first; nothing is
;   scrolled back down.
; ============================================================================
EDITOR_REDRAW:
    call WRAP_CALC
.resize:
    ld   a, (FWRAP_OLD_COUNT)
    ld   c, a
    ld   a, EDIT_ROW + 1
    sub  c
    ld   b, a                            ; B = 24 - old, the row a growth claims
    ld   a, c
    ld   hl, FWRAP_COUNT
    cp   (hl)
    jr   z, .count_settled
    jr   c, .grow                        ; old < new
    ld   d, 0                            ; shrank: clear that row
    call ED_ROW_JP
    ld   hl, FWRAP_OLD_COUNT
    dec  (hl)
    jr   .resize
.grow:
    ld   a, (PRINT_ROW)
    cp   b
    jr   c, .no_scroll                   ; output ends above the new row
    call ED_SCROLL_UP
    ld   hl, PRINT_ROW
    dec  (hl)
.no_scroll:
    ld   hl, FWRAP_OLD_COUNT
    inc  (hl)
    jr   .resize
.count_settled:
    ld   a, b                            ; 24 - FWRAP_COUNT
    ld   (FWRAP_TOP), a
    call ED_DRAW_ROWS                    ; falls into ED_DRAW_CURSOR

; ============================================================================
; ED_DRAW_CURSOR -- draw the edit line's cursor, from the wrap table and FWRAP_TOP: a FLASH cell
; with ink and paper swapped
; Destroys: AF, BC, DE, HL
; ============================================================================
ED_DRAW_CURSOR:
    call EDIT_CURSOR_TO_ROWCOL
    jp   GFX_INVERT_ATTR

; ED_SCROLL_UP -- the whole screen up one row
ED_SCROLL_UP:
    jp   GFX_SCROLL_OUTPUT_UP

; ============================================================================
; ED_DRAW_ROWS -- draw the FWRAP_COUNT rows of the wrap table from screen row FWRAP_TOP down, each
; blank-padded to the width WRAP_CALC set
; Destroys: AF, BC, DE, HL
; ED_ROW_JP (JP ED_ROW32, written by WRAP_CALC) draws one row.
; In:  B = the screen row, HL = the text, D = the characters (0: a blank row)
; Out: B kept; destroys AF, C, DE, HL
; ============================================================================
ED_DRAW_ROWS:
    ld   a, (FWRAP_TOP)
    ld   b, a
    xor  a
.row:
    ld   (FWRAP_ROW_IDX), a
    ld   hl, FWRAP_COUNT
    cp   (hl)
    ret  nc
    ld   e, a
    ld   d, 0
    ld   hl, FWRAP_LEN
    add  hl, de
    ld   a, (hl)                         ; A = this row's length
    ld   hl, FWRAP_START
    add  hl, de
    ld   e, (hl)
    ld   hl, (FWRAP_BASE)
    add  hl, de                          ; HL = this row's text
    ld   d, a
    call ED_ROW_JP
    inc  b
    ld   a, (FWRAP_ROW_IDX)
    inc  a
    jr   .row

ED_ROW32:                             ; the row drawer behind ED_ROW_JP
    ld   c, EDIT_COL_START
.char:
    ld   a, d
    or   a
    jr   z, .pad
    ld   a, (hl)
    push hl
    push de
    call ED_CELL32
    pop  de
    pop  hl
    inc  hl
    inc  c
    dec  d
    jr   .char
.pad:
    ld   a, c
    cp   32
    ret  nc
    ld   a, " "
    call ED_CELL32
    inc  c
    jr   .pad

; ED_CELL32 -- A = the character at (B, C) with ATTR_DEFAULT; keeps BC
ED_CELL32:
    push bc
    call GFX_PUTCHAR
    pop  bc
    ld   a, ATTR_DEFAULT
    jp   GFX_SET_ATTR                    ; keeps BC

; ============================================================================
; EDITOR_EDIT_KEY -- the console's editing without a redraw (the full-screen view edits its line
; with this)
; In:  A = the key code
; Out: carry set if A was ENTER (a line is ready in EDIT_BUF / EDIT_LEN; not handled here);
;      otherwise carry clear and NZ = the line or the cursor changed, Z = nothing changed (DELETE
;      or LEFT at 0, RIGHT at the end, a refused or ignored key)
; Destroys: AF, BC, DE, HL
;
; A character is inserted speculatively and WRAP_CALC re-run, because where a wrap falls depends on
; the spaces: if the result would need more than FWRAP_MAX_ROWS rows the insert is undone and the
; key ignored ("buffer full").
;
; EDITOR_PROCESS_KEY -- EDITOR_EDIT_KEY and, when something changed, EDITOR_REDRAW. No error is
; raised here.
; In:  A = the key code
; Out: carry set if A was ENTER
; ============================================================================
EDITOR_EDIT_KEY:
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
    jr   .changed
.not_delete:
    cp   KEY_CURSOR_LEFT
    jr   nz, .not_left
    ld   a, (EDIT_CURSOR)
    or   a
    jr   z, .done
    dec  a
    ld   (EDIT_CURSOR), a
    jr   .changed
.not_left:
    cp   KEY_CURSOR_RIGHT
    jr   nz, .not_right
    ld   hl, EDIT_LEN
    ld   a, (EDIT_CURSOR)
    cp   (hl)
    jr   nc, .done             ; already at or past the end
    inc  a
    ld   (EDIT_CURSOR), a
    jr   .changed
.not_right:
    cp   " "
    jr   c, .done              ; below space: unmapped/control, ignore
    cp   $7F
    jr   nc, .done              ; DEL and above: ignore
    push af                     ; the key code
    ld   a, (EDIT_LEN)
    cp   EDIT_MAX_LEN
    jr   c, .room
    pop  af                       ; the buffer is full: ignore the key
    jr   .done
.room:
    pop  af
    call INSERT_CHAR
    call WRAP_CALC
    ld   a, (FWRAP_OVERFLOW)
    or   a
    jr   z, .changed               ; still fits FWRAP_MAX_ROWS rows
    call DELETE_CHAR_BEFORE_CURSOR  ; too tall: undo the insert (the character just before the cursor)
.done:
    xor  a                      ; NC, Z: nothing changed
    ret
.changed:
    or   1                      ; NC, NZ
    ret

EDITOR_PROCESS_KEY:
    call EDITOR_EDIT_KEY
    ret  c
    ret  z
    call EDITOR_REDRAW
    or   a
    ret

; ============================================================================
; EDITOR_LOOP_LIVE -- the interactive shell: read a line, append it to the store, run it, print "OK"
; unless it raised an error, repeat forever
;
; Precondition (not set up here): IO_READ_KEY only consumes a key latched by kernel/interrupt's
; KBD_ISR_TICK, so interrupts must be enabled with RST $0038 vectoring to KBD_ISR_TICK (IM 1),
; or the first key wait hangs.
; ============================================================================
EDITOR_LOOP_LIVE:
    xor  a
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a
    ; FWRAP_OLD_COUNT is deliberately not reset: it must hold the row count of the line just
    ; submitted, so EDITOR_REDRAW's shrink clears that line's leftover rows above EDIT_ROW
    call EDITOR_REDRAW
.keyloop:
    call IO_READ_KEY
    call EDITOR_PROCESS_KEY
    jr   nc, .keyloop
    ; the line goes to the store before it runs, so it is kept even if the run never returns
    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   b, a
    call STORE_APPEND

    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   d, 0
    ld   e, a
    call INTERPRET_RUN
    ld   a, (VIEW_RESULT)           ; EDIT ran, and an error may have left changed-line
    or   a                          ; marks in the store
    call nz, EDIT_CLEAR_MARKS
    ; an error prints its own message and sets INTERP_ERROR_FLAG: "OK" only without one
    ld   a, (INTERP_ERROR_FLAG)
    or   a
    jr   nz, .no_ok
    ld   hl, "O"
    rst RST_DPUSH
    call W_EMIT
    ld   hl, "K"
    rst RST_DPUSH
    call W_EMIT
    ld   hl, 13
    rst RST_DPUSH
    call W_EMIT
.no_ok:
    jp   EDITOR_LOOP_LIVE

    ENDIF
