; ============================================================================
; core/edit.asm -- EDIT ( "name" -- ): the full-screen view (audit step E item
; 6, docs/V2/EDITOR_SPEC.md sections 5 and 5.1)
;
; The view itself lives in the graphics EXROM (rom/graphics_exrom.asm,
; VIEW_SESSION, service slot 6). EDIT parses the name after it into WORD_BUF
; (no name: bare EDIT), calls the session through EXROM_CALL_SLOT, and then, if
; the session ran, clears the screen and interprets the lines the session
; changed. Needs core/interp.asm (W_WORD, INTERPRET_NESTED), core/rectfill.asm
; (EXROM_CALL_SLOT), core/forget.asm (FORGET_PRINT_MSG), core/loadtext.asm
; (STORE_START, STORE_END) and core/print.asm first.
;
; The session's answer is VIEW_RESULT: Home sets it to 0 before the call, the
; EXROM to 1 (name not found), 2 (refused; it printed the message) or 3 (the
; session ran). A stock EXROM, or one whose slot 6 is still the 1-byte RET,
; leaves 0 (or answers with carry): NO EXROM.
; ============================================================================

    IFNDEF CORE_EDIT_ASM
    DEFINE CORE_EDIT_ASM

VIEW_RESULT EQU $8AC0       ; 1 byte; the EXROM's copy is include/exrom_home_ram.inc
EDIT_LINE_NO EQU $8AF1      ; 2 bytes: the number of the line the commit loop is running
                            ; (0: none); EDIT_ERR_PREFIX reports it. After the EXROM's
                            ; view cells $8AC1-$8AF0 (rom/graphics_exrom.asm; its row shadow follows at $8AF3)

H_EDIT:
    DW   DICT_CHAIN_POINT   ; the including ROM sets this (DEFL)
    DB   4, "E","D","I","T"
W_EDIT:
    call W_WORD
    rst  RST_DPOP                   ; the name is in WORD_BUF
    call STORE_TRIM                 ; the EDIT line is not source (core/recall.asm); also
                                    ; retires its append position before the session moves lines
    xor  a
    ld   (VIEW_RESULT), a           ; no view, until the EXROM says otherwise
    ld   hl, $A000 + (6 * 3)        ; slot 6 = VIEW_SESSION
    call EXROM_CALL_SLOT
    jr   c, .noexrom
    ld   a, (VIEW_RESULT)
    or   a
    jr   z, .noexrom
    dec  a
    jp   z, INTERPRET_UNKNOWN_WORD  ; 1: `name ?`, as for an unknown word
    dec  a
    ret  z                          ; 2: refused (the EXROM printed why)
    call GFX_CLS                    ; 3: the session ran
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, (SRC_END)              ; the console line goes on afterwards
    push hl
    ld   hl, (SRC_PTR)
    push hl
.next:
    call EDIT_NEXT_MARK             ; the first changed line, its mark cleared (the
    jr   z, .end                    ; search starts afresh: a run line may change the store)
    ld   (EDIT_LINE_NO), bc
    call INTERPRET_NESTED
    jr   .next
.end:
    ld   hl, 0                      ; no line running: an error in the rest of the
    ld   (EDIT_LINE_NO), hl         ; console line gets no LINE n
    pop  hl
    ld   (SRC_PTR), hl
    pop  hl
    ld   (SRC_END), hl
    ret
.noexrom:
    ld   hl, .msg
    jp   FORGET_PRINT_MSG
.msg:
    DB   "NO EXROM", 13, 0

; ============================================================================
; EDIT_NEXT_MARK -- the first changed line in the store: its mark ($8D) back to
; $0D. Shared by EDIT's commit loop and EDIT_CLEAR_MARKS.
; Out: NZ, HL = the line's text, DE = its length, BC = its number (from 1);
;      Z if no line is marked
; Destroys: AF
; ============================================================================
EDIT_NEXT_MARK:
    ld   hl, STORE_START
    ld   bc, 0
.line:
    ld   de, (STORE_END)
    or   a
    sbc  hl, de
    add  hl, de
    jr   nc, .none                  ; at (or, after a store change by a run line, past) STORE_END
    inc  bc
    push hl                         ; this line's start
.byte:
    ld   a, (hl)
    inc  hl
    cp   13
    jr   z, .plain
    cp   $8D
    jr   nz, .byte
    dec  hl
    ld   (hl), 13
    pop  de
    or   a
    sbc  hl, de
    ex   de, hl                     ; hl = the text, de = its length
    or   a                          ; NZ (A = $8D)
    ret
.plain:
    pop  de
    jr   .line
.none:
    xor  a
    ret

; ============================================================================
; EDIT_CLEAR_MARKS -- every changed-line mark ($8D) in the store back to $0D;
; EDITOR_LOOP_LIVE calls it when EDIT was the last thing to run (VIEW_RESULT
; not 0): the commit loop above clears a line's mark just before it runs, so
; marks are left only when a line raised an error (or ABORT/QUIT) and the
; whole run unwound to the console, and they must not outlive the session.
; Out: VIEW_RESULT = 0, EDIT_LINE_NO = 0
; Destroys: AF, BC, DE, HL
; ============================================================================
EDIT_CLEAR_MARKS:
    xor  a
    ld   (VIEW_RESULT), a
    ld   h, a
    ld   l, a
    ld   (EDIT_LINE_NO), hl         ; the run unwound past the commit loop's own reset
.next:
    call EDIT_NEXT_MARK
    jr   nz, .next
    ret

; ============================================================================
; EDIT_ERR_PREFIX -- `LINE n ` before an error's message while the commit loop
; runs line n (EDITOR_SPEC.md section 5, Leaving). Called by rom/forth_boot.asm's
; INTERPRET_UNKNOWN_WORD and RUNTIME_ERROR_HOOK (an uncaught THROW goes there
; too), with the data stack already reset. The marks after line n are cleared
; when the unwound console line ends (EDIT_CLEAR_MARKS).
; Destroys: AF, BC, DE, HL
; ============================================================================
EDIT_ERR_PREFIX:
    ld   hl, (EDIT_LINE_NO)
    ld   a, h
    or   l
    ret  z
    rst  RST_DPUSH
    ld   hl, .msg
    call FORGET_PRINT_MSG
    jp   W_DOT                      ; the number and a space
.msg:
    DB   "LINE ", 0

DICT_LATEST_INIT_EDIT EQU H_EDIT    ; head of the dictionary once this file is the last one INCLUDEd

    ENDIF
