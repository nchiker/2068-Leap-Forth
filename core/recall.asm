; ============================================================================
; core/recall.asm -- the console's store append, STORE_TRIM, and LIST-DEFS
;
; Needs core/loadtext.asm (STORE_START, STORE_END, STORE_LIMIT) and core/forget.asm
; (FORGET_PRINT_MSG). core/editor.asm's EDITOR_LOOP_LIVE calls STORE_APPEND for every committed
; line, so the store holds the session's source, typed or loaded (docs/V2/EDITOR_SPEC.md section 3).
; `EDIT name` (core/edit.asm) edits the store in place.
;
; LIST-DEFS lists the first DEF_TABLE_MAX (16) top-level ":" ... ";" spans of the store, oldest
; first, numbered from 0, with a 20-character preview. The link field of H_LISTDEFS is
; DICT_CHAIN_POINT, which the including ROM sets (DEFL). Every word here may destroy all registers
; except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_RECALL_ASM
    DEFINE CORE_RECALL_ASM

DEF_TABLE_MAX  EQU 16
    ASSERT DEF_TABLE_MAX * 4 == 64      ; DEF_TABLE's size in include/forth_layout.inc

; ============================================================================
; STORE_APPEND -- the console's append (EDITOR_LOOP_LIVE, on ENTER): the line and a CR go at
; STORE_END. An empty line is not appended. A line that does not fit (STORE_END + len + 1 >
; STORE_LIMIT, an exact 16-bit test) is not appended and "STORE FULL" is printed on its own line;
; the caller interprets the line either way.
; In:  HL = the line, B = its length
; Out: STORE_END moved past the CR; STORE_LAST_LINE = where the line starts (0: nothing appended)
; Destroys: AF, BC, DE, HL
; ============================================================================
STORE_APPEND:
    ld   de, 0
    ld   (STORE_LAST_LINE), de      ; nothing appended for this line (yet)
    ld   a, b
    or   a
    ret  z                      ; empty line: nothing to append
    ld   c, a
    ld   b, 0                   ; BC = len
    ld   de, (STORE_END)
    push hl
    ld   hl, STORE_LIMIT
    or   a
    sbc  hl, de                 ; HL = the room (STORE_END never passes STORE_LIMIT)
    scf
    sbc  hl, bc                 ; room - len - 1: borrow if the line and its CR do not fit
    pop  hl
    jr   c, .full
    ld   (STORE_LAST_LINE), de
    ldir
    ld   a, 13
    ld   (de), a
    inc  de
    ld   (STORE_END), de
    ret
.full:
    ld   hl, STORE_FULL_MSG
    jp   FORGET_PRINT_MSG       ; the CR is a newline

STORE_FULL_MSG: DB "STORE FULL", 13, 0

; ============================================================================
; STORE_TRIM -- the console's line off the end of the store: a line holding SAVE-TEXT, VERIFY-TEXT,
; LOAD-TEXT or EDIT is a command, not source. STORE_END goes back to STORE_LAST_LINE, once.
; Out: STORE_LAST_LINE = 0
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
; AT_END -- has RECALL_SCAN_PTR reached STORE_END?
; Out: Z if so
; Destroys: AF, DE, HL
; ============================================================================
AT_END:
    ld   hl, (RECALL_SCAN_PTR)
    ld   de, (STORE_END)
    or   a
    sbc  hl, de
    ret

; ============================================================================
; SCAN_DEFS -- walk STORE_START..STORE_END word by word, as the interpreter reads it, for the top-level
; ":" ... ";" spans, and fill DEF_TABLE and DEF_COUNT, oldest first. The words ":" and ";" open
; and close a span (colon definitions do not nest: a ":" in an open span is ignored); the comments
; are skipped, so a ":" or ";" in one counts for nothing: "\" to the next CR (from its own
; delimiter, which may be that CR), "(" past the next ")". A word is delimited by any byte up to a
; space, as WORD does; the byte after a word's first is in the store (the last line ends with CR).
; Stops at DEF_TABLE_MAX.
; Destroys: AF, BC, DE, HL
; ============================================================================
SCAN_DEFS:
    xor  a
    ld   (DEF_COUNT), a
    ld   h, a
    ld   l, a
    ld   (RECALL_SPAN_START), hl      ; 0: no span open
    ld   hl, STORE_START
.next:                                ; HL = the scan position
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    ret  z
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    inc  hl
    cp   " " + 1
    jr   c, .next                     ; whitespace
    ld   c, a                         ; C = the word's first character
    ld   a, (hl)
    cp   " " + 1
    jr   nc, .rest                    ; two characters or more: none of the words below
    ld   a, c
    ld   b, 13
    cp   $5C
    jr   z, .comment                  ; \ : past the next CR
    ld   b, ")"
    cp   "("
    jr   z, .comment                  ; ( : past the next )
    ld   de, (RECALL_SPAN_START)
    cp   ":"
    jr   z, .colon
    cp   ";"
    jr   nz, .next
    ld   a, d                         ; ; : record the open span, if any
    or   e
    jr   z, .next
    ld   a, (DEF_COUNT)
    cp   DEF_TABLE_MAX
    ret  nc                           ; table full
    push hl                           ; past the ;
    or   a
    sbc  hl, de                       ; the span's length, with the ;
    push hl
    ld   hl, -STORE_START
    add  hl, de
    ex   de, hl                       ; DE = the span's start offset
    ld   l, a
    ld   h, 0
    add  hl, hl
    add  hl, hl
    ld   bc, DEF_TABLE
    add  hl, bc                       ; HL = DEF_TABLE + DEF_COUNT * 4
    ld   (hl), e
    inc  hl
    ld   (hl), d
    inc  hl
    pop  de
    ld   (hl), e
    inc  hl
    ld   (hl), d
    inc  a
    ld   (DEF_COUNT), a
    pop  hl
    ld   de, 0                        ; the span is closed: .colon stores 0
    jr   .store
.colon:
    ld   a, d
    or   e
    jr   nz, .next                    ; a span is open
    ld   d, h
    ld   e, l
    dec  de                           ; the span starts at the ":"
.store:
    ld   (RECALL_SPAN_START), de
    jr   .next
.comment:                             ; skip past the byte B, or to the end
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    ret  z
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    inc  hl
    cp   b
    jr   nz, .comment
    jr   .next
.rest:                                ; skip the rest of a longer word
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    ret  z
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   " " + 1
    jr   nc, .rest
    jp   .next                        ; a jp: out of jr's reach

; ============================================================================
; GET_DEF_SPAN -- one DEF_TABLE entry
; In:  C = the index (< DEF_COUNT)
; Out: DE = the span's start offset in the store, HL = its length
; Destroys: AF, B
; ============================================================================
GET_DEF_SPAN:
    ld   hl, DEF_TABLE
    ld   b, 0
    add  hl, bc
    add  hl, bc
    add  hl, bc
    add  hl, bc
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    inc  hl
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a
    ret

; ============================================================================
; LIST-DEFS ( -- ) -- scan the store afresh, then print each span as "N: " and up to 20 characters of
; its source (one 32-column row) and a newline
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
    ret  z                        ; index = DEF_COUNT: done
    ret  c                        ; index > DEF_COUNT: not reached, a safety net

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

    call GET_DEF_SPAN

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
    add  hl, de                   ; HL -> the span in the store
    pop  bc                       ; BC = the capped length
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

DICT_LATEST_INIT_LISTDEFS EQU H_LISTDEFS ; the chain head when this is the last file included

    ENDIF
