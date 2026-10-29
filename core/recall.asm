; ============================================================================
; core/recall.asm — the console's store append and LIST-DEFS (Phase 64;
; RECALL retired at audit step E item 7, docs/V2/EDITOR_SPEC.md E6)
;
; Builds on core/loadtext.asm (STORE_START, STORE_END, STORE_LIMIT) and
; core/editor.asm (EDITOR_LOOP_LIVE calls STORE_APPEND for every committed
; line, so the store holds the session's source, typed or loaded).
;
; Phase 64's RECALL copied a definition into the edit line and left the old
; copy in the store; `EDIT name` (core/edit.asm, the full-screen view in the
; graphics EXROM) now edits the store in place and runs only the changed
; lines, so RECALL (74 B) and its RECALL_PENDING hand-off to the console are
; gone. LIST-DEFS stays: it lists the first DEF_TABLE_MAX (16) top-level
; ":" ... ";" spans of the store, oldest first, numbered from 0, with a
; 20-character preview. Its scratch cells keep their Phase 64 names.
; ============================================================================

    IFNDEF CORE_RECALL_ASM
    DEFINE CORE_RECALL_ASM

; ---- DEF_COUNT/DEF_TABLE: same confirmed-idle gap as STORE_END
; (core/loadtext.asm), continuing right after it ($8A74-$8A75). ----
STORE_LAST_LINE EQU $8BFE  ; 2 bytes: STORE_APPEND's last append (0: none), for STORE_TRIM;
                           ; the top of the free $8ABD-$8BFF (the view's RAM starts at $8AC0)
DEF_TABLE_MAX  EQU 16
DEF_COUNT      EQU $8A76   ; 1 byte: how many spans SCAN_DEFS found
                           ; (0-DEF_TABLE_MAX)
DEF_TABLE      EQU $8A77   ; DEF_TABLE_MAX*4 bytes: per entry, 2-byte
                           ; start offset from STORE_START + 2-byte
                           ; length. Ends $8AB7, still well before
                           ; core/float.asm's own FSTACK_LIMIT ($8C00).

RECALL_SCAN_PTR   EQU $8AB7   ; 2 bytes: SCAN_DEFS's own scratch
RECALL_SPAN_START EQU $8AB9   ; 2 bytes: SCAN_DEFS's own scratch

; ============================================================================
; STORE_APPEND ( HL = addr, B = len -- )
; The console's append (core/editor.asm's EDITOR_LOOP_LIVE, ENTER): the line's B bytes at HL and a CR go
; at STORE_END (docs/V2/EDITOR_SPEC.md section 3). An empty line is not appended. A line that does not fit
; (STORE_END + len + 1 > STORE_LIMIT, an exact 16-bit test) is not appended and "STORE FULL" is printed on
; its own line; the caller goes on to interpret the line either way.
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_APPEND:
    ld   de, 0
    ld   (STORE_LAST_LINE), de      ; nothing appended for this line (yet)
    ld   a, b
    or   a
    ret  z                      ; empty line: nothing to append
    ld   c, a
    ld   b, 0                   ; bc = len
    ld   de, (STORE_END)
    push hl
    ld   hl, STORE_LIMIT
    or   a
    sbc  hl, de                 ; hl = room (STORE_END never passes STORE_LIMIT)
    scf
    sbc  hl, bc                 ; room - len - 1: borrow if the line and its CR do not fit
    pop  hl
    jr   c, .full
    ld   (STORE_LAST_LINE), de      ; where this line starts, for STORE_TRIM
    ldir
    ld   a, 13
    ld   (de), a
    inc  de
    ld   (STORE_END), de
    ret
.full:
    ld   hl, STORE_FULL_MSG
    jp   FORGET_PRINT_MSG       ; core/forget.asm: prints the message (its CR is a newline) and returns

STORE_FULL_MSG: DB "STORE FULL", 13, 0

; ============================================================================
; STORE_TRIM -- the console's line off the end of the store (EDITOR_SPEC.md section 3: a line holding SAVE-TEXT,
; VERIFY-TEXT, LOAD-TEXT or EDIT is a command, not source). STORE_APPEND records where it put the line being run
; (STORE_LAST_LINE, 0 when it appended nothing); STORE_END goes back there, once.
; Destroys: AF, HL
; ============================================================================
STORE_TRIM:
    ld   hl, (STORE_LAST_LINE)
    ld   a, h
    or   l
    ret  z                              ; nothing appended for this line, or trimmed already
    ld   (STORE_END), hl
    ld   hl, 0
    ld   (STORE_LAST_LINE), hl
    ret

; ============================================================================
; SCAN_DEFS ( -- )
; Walks STORE_START..STORE_END for top-level ":"..";" spans (each
; delimiter-bounded, the same way core/interp.asm's own WORD treats
; every byte from 0 to space as a delimiter) and populates DEF_TABLE/DEF_COUNT, oldest
; first. Forth doesn't nest colon definitions, so no depth tracking is
; needed: a ":" starts a span, the next ";" ends it.
; ============================================================================
; AT_END (internal) -- Z set if RECALL_SCAN_PTR has reached STORE_END.
; Factored out of SCAN_DEFS's own three identical inline checks (one per
; scan state below) -- pure dedup, no behavior change. Destroys HL/DE,
; which every call site below already reloads fresh afterward anyway.
AT_END:
    ld   hl, (RECALL_SCAN_PTR)
    ld   de, (STORE_END)
    or   a
    sbc  hl, de
    ret

SCAN_DEFS:
    xor  a
    ld   (DEF_COUNT), a
    ld   hl, STORE_START
    ld   (RECALL_SCAN_PTR), hl
.outer:
    call AT_END
    jp   z, .stop                ; reached the end: done -- jp not jr,
                                  ; real displacement was +126, only 1
                                  ; byte under the +-127 limit
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   " " + 1
    jr   nc, .check_colon
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    jr   .outer
.check_colon:
    cp   ":"
    jr   nz, .skip_word
    ld   (RECALL_SPAN_START), hl
    ; found ":" -- now scan forward for the matching ";" word
.find_semi:
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    jr   z, .stop                ; ran off the end with no ";": stop scanning
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   ";"
    jr   nz, .find_semi         ; (whitespace is never ";")
    ; ";" found -- record the span (inclusive of the ";") if room remains
    ld   a, (DEF_COUNT)
    cp   DEF_TABLE_MAX
    jr   nc, .stop                ; table full: stop scanning (Phase 64's
                                   ; own documented DEF_TABLE_MAX limit)
    push af
    ld   hl, DEF_TABLE
    ld   d, 0
    ld   e, a
    add  hl, de
    add  hl, de
    add  hl, de
    add  hl, de                   ; hl = DEF_TABLE + a*4
    ex   de, hl
    ld   hl, (RECALL_SPAN_START)
    ld   bc, STORE_START
    or   a
    sbc  hl, bc                   ; hl = span start offset
    ld   a, l                     ; Z80 has no `ld (de),hl` -- store via A
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   hl, (RECALL_SCAN_PTR)
    ld   bc, (RECALL_SPAN_START)
    or   a
    sbc  hl, bc
    inc  hl                       ; hl = span length, inclusive of ";"
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    pop  af
    inc  a
    ld   (DEF_COUNT), a
    ld   hl, (RECALL_SCAN_PTR)
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    jr   .outer
.skip_word:
    ; not ":" -- skip to the next space (or end) and keep scanning
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    jr   z, .stop
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   " " + 1
    jr   nc, .skip_word
    jp   .outer
.stop:
    ret

; GET_DEF_SPAN (internal) ( C = index -- DE = span start offset, HL = span
; length ). Factored out of W_LISTDEFS and Phase 64's W_RECALL, which both did this
; identical DEF_TABLE index arithmetic and 4-byte read inline -- pure
; dedup, no behavior change. Caller must ensure index < DEF_COUNT.
GET_DEF_SPAN:
    ld   hl, DEF_TABLE
    ld   b, 0
    add  hl, bc
    add  hl, bc
    add  hl, bc
    add  hl, bc
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                  ; de = span start offset
    inc  hl
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a                     ; hl = span length
    ret

; ============================================================================
; LIST-DEFS ( -- )
; Scans the workspace fresh, then prints each entry as "N: " followed by
; up to 20 preview characters of its source and a newline. 20 is a plain
; display choice (fits one 32-column row with the "N: " prefix and room
; to spare), not a stored/recall limit -- RECALL below copies the WHOLE
; span, not just the preview.
; ============================================================================
LISTDEFS_PREVIEW_LEN EQU 20

H_LISTDEFS:
    DW   DICT_CHAIN_POINT
    DB   9, "L","I","S","T","-","D","E","F","S"
W_LISTDEFS:
    call SCAN_DEFS
    xor  a
    ld   (RECALL_LIST_IDX), a
.loop:
    ld   a, (RECALL_LIST_IDX)
    ld   c, a
    ld   b, 0
    ld   a, (DEF_COUNT)
    cp   c
    ret  z                        ; RECALL_LIST_IDX == DEF_COUNT: done
    ret  c                        ; RECALL_LIST_IDX > DEF_COUNT: done
                                   ; (can't happen, kept as a safety net)

    push bc
    ld   l, c
    ld   h, b
    call PRINT_UDEC16
    ld   hl, ":"
    rst RST_DPUSH
    call W_EMIT
    ld   hl, " "
    rst RST_DPUSH
    call W_EMIT
    pop  bc

    call GET_DEF_SPAN              ; de = span start offset, hl = length

    ld   a, LISTDEFS_PREVIEW_LEN
    cp   l
    jr   c, .cap
    ld   a, h
    or   a
    jr   z, .nocap
.cap:
    ld   l, LISTDEFS_PREVIEW_LEN
    ld   h, 0
.nocap:
    push hl
    ld   hl, STORE_START
    add  hl, de                   ; hl -> span start in the workspace
    pop  bc                       ; bc = capped preview length
.printloop:
    ld   a, b
    or   c
    jr   z, .printdone
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    dec  bc
    jr   .printloop
.printdone:
    ld   hl, 13
    rst RST_DPUSH
    call W_EMIT

    ld   a, (RECALL_LIST_IDX)
    inc  a
    ld   (RECALL_LIST_IDX), a
    jr   .loop

RECALL_LIST_IDX EQU RECALL_SPAN_START + 2   ; 1 byte: reuses SCAN_DEFS's
                                             ; own idle scratch -- LIST-DEFS
                                             ; never runs concurrently with
                                             ; SCAN_DEFS itself (it CALLS
                                             ; it first, then this loop
                                             ; runs after SCAN_DEFS has
                                             ; already returned).

DICT_LATEST_INIT_LISTDEFS EQU H_LISTDEFS   ; head of the dictionary once
                                           ; this file is the last one INCLUDEd

    ENDIF
