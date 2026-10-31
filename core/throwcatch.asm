; ============================================================================
; core/throwcatch.asm -- THROW and CATCH
;
; Needs core/dict.asm, core/interp.asm (THROW_ROOT_SP, THROW_CODE) and
; the including ROM's RUNTIME_ERROR_HOOK, where an uncaught THROW ends. Link fields: a word's DW
; is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the word extends. Every
; word here may destroy all registers except IX, IY and SP.
;
; The hardware stack is the return stack, so THROW unwinds SP directly, like longjmp. CATCH saves
; SP, IX and IY (the data and float stacks) in a frame of the bounded CATCH_STACK, indexed by
; CATCH_DEPTH, and then calls xt. If xt returns, CATCH drops its frame and pushes 0. THROW with
; n <> 0 restores SP, IX and IY from the innermost frame, pushes n and RETs: SP is back at CATCH's
; entry, so the RET goes to CATCH's caller as if xt had returned, and the unwound calls run no
; cleanup.
;
; SP, IX and IY can only be stored to or loaded from fixed addresses, so both words go through the
; staging cells CATCH_TMP_SP / _IX / _IY: CATCH stages them and LDIRs them into the frame slot;
; THROW copies the slot into them by hand (LDIR would clobber BC, which keeps n) and loads from
; them.
;
; An uncaught THROW (CATCH_DEPTH = 0) reloads SP from THROW_ROOT_SP, which INTERPRET_RUN saved on
; entry, resets both stacks, leaves n in THROW_CODE and jumps to RUNTIME_ERROR_HOOK, whose
; contract is that the hardware stack holds exactly INTERPRET_RUN's caller's entry.
;
; Nested deeper than CATCH_MAX_DEPTH, a CATCH records no frame and runs xt unguarded: 0 is still
; pushed on a normal return, and a THROW inside escapes to the next outer CATCH or the uncaught
; path.
; ============================================================================

    IFNDEF CORE_THROWCATCH_ASM
    DEFINE CORE_THROWCATCH_ASM

CATCH_MAX_DEPTH EQU 8
    ASSERT CATCH_MAX_DEPTH * 6 == 48    ; CATCH_STACK's size in include/forth_layout.inc

; ============================================================================
; JUMP_HL -- run the code at HL; its RET returns to the caller of JUMP_HL (not a dictionary word;
; EXECUTE would need xt back on the data stack)
; In:  HL = the code address
; ============================================================================
JUMP_HL:
    jp   (hl)

; ============================================================================
; THROW ( n -- ) -- n = 0: nothing. Otherwise unwind to the innermost CATCH, which then returns n
; (stacks restored to their CATCH-time depth); with none, the uncaught path (file header)
; ============================================================================
H_THROW:
    DW   DICT_CHAIN_POINT
    DB   5, "T","H","R","O","W"
W_THROW:
    rst RST_DPOP            ; HL = n
    ld   a, h
    or   l
    ret  z
    ld   b, h                ; BC = n, kept across the unrolled copy below
    ld   c, l
    ld   a, (CATCH_DEPTH)
    or   a
    jr   z, .uncaught
    dec  a
    ld   (CATCH_DEPTH), a
    ld   l, a                 ; HL = the frame slot, CATCH_STACK + a * 6
    ld   h, 0
    add  hl, hl
    ld   d, h
    ld   e, l
    add  hl, hl
    add  hl, de
    ld   de, CATCH_STACK
    add  hl, de
    ld   a, (hl)
    ld   (CATCH_TMP_SP), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_SP+1), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IX), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IX+1), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IY), a
    inc  hl
    ld   a, (hl)
    ld   (CATCH_TMP_IY+1), a
    ld   sp, (CATCH_TMP_SP)
    ld   ix, (CATCH_TMP_IX)
    ld   iy, (CATCH_TMP_IY)
    ld   h, b
    ld   l, c
    rst RST_DPUSH             ; n, onto the restored stack
    ret                        ; to CATCH's caller (file header)
.uncaught:
    ld   (THROW_CODE), bc       ; n, for the hook's message
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    ld   sp, (THROW_ROOT_SP)
    jp   RUNTIME_ERROR_HOOK

; ============================================================================
; CATCH ( xt -- 0 | n ) -- execute xt: 0 if it returned, else the n of a THROW inside it
; ============================================================================
H_CATCH:
    DW   H_THROW
    DB   5, "C","A","T","C","H"
W_CATCH:
    rst RST_DPOP                ; HL = xt, popped before the frame records IX: a THROW
                                 ; restores the stack without it
    ld   a, (CATCH_DEPTH)
    cp   CATCH_MAX_DEPTH
    jr   nc, .no_room
    ld   (CATCH_TMP_SP), sp     ; stage SP, IX, IY (file header)
    ld   (CATCH_TMP_IX), ix
    ld   (CATCH_TMP_IY), iy
    push hl                      ; xt, pushed after SP was staged
    ld   l, a
    ld   h, 0
    add  hl, hl
    ld   d, h
    ld   e, l
    add  hl, hl
    add  hl, de                  ; a * 6
    ld   de, CATCH_STACK
    add  hl, de
    ex   de, hl                  ; DE = the frame slot
    ld   hl, CATCH_TMP_SP
    ld   bc, 6
    ldir                         ; SP, IX, IY into the frame slot
    ld   a, (CATCH_DEPTH)
    inc  a
    ld   (CATCH_DEPTH), a
    pop  hl                      ; HL = xt
    call JUMP_HL                 ; returns here only if no THROW unwound it
    ld   a, (CATCH_DEPTH)
    dec  a
    ld   (CATCH_DEPTH), a
    ld   hl, 0
    rst RST_DPUSH
    ret
.no_room:                        ; CATCH_MAX_DEPTH reached: no frame (file header)
    call JUMP_HL
    ld   hl, 0
    rst RST_DPUSH
    ret


    ENDIF
