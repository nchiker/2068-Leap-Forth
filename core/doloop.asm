; ============================================================================
; core/doloop.asm -- DO, LOOP, +LOOP, LEAVE and I, the counted loop
;
; Needs core/dict.asm and core/interp.asm (COMPILE_CALL, COMPILE_WORD). Not core/control.asm: the
; loops have their own run-time routines. Link fields: a word's DW is DICT_CHAIN_POINT, which the
; including ROM sets (DEFL) to the chain the word extends. Every word here may destroy all
; registers except IX, IY and SP.
;
; The loop's limit and index live on the hardware stack, which is the return stack here: DO_RT
; pushes limit, then index on top, under whatever the body's balanced CALLs and RETs push. Nested
; loops stack the same way, the inner one's frame above the outer's. EXIT (core/loopext.asm)
; discards open frames and J reads the second.
;
; Plain DO never tests start against limit: the body runs once, and with start = limit the index
; wraps through 65536 passes before it meets the limit again (there is no ?DO).
;
; LEAVE compiles a branch to the loop's end, which is not known yet, and may occur any number of
; times in a body. Its pending placeholders form a linked list through their own blank operands
; (each holds the previous one's address), headed in LEAVE_HEAD_TABLE[LEAVE_DEPTH - 1], one slot
; per open loop (8 levels, not checked at run time). A table, not the compile-time data stack,
; because LEAVE is usually inside an IF whose placeholder is on top of that stack. DO opens a slot
; (LEAVE_DEPTH + 1, chain empty); LOOP and +LOOP patch the whole chain to the loop end and
; close it. LEAVE_DEPTH must be 0 at cold start.
; ============================================================================

    IFNDEF CORE_DOLOOP_ASM
    DEFINE CORE_DOLOOP_ASM

; ============================================================================
; DO_RT -- not a dictionary word: the run-time half of DO
; In:  ( limit start -- ), the return address -> the loop body
; Out: the hardware stack holds index on top, limit under it, then the return address
; Destroys: BC, DE, HL
; ============================================================================
DO_RT:
    pop  hl                  ; HL = the return address, pushed back last
    ld   e, (ix+0)            ; DE = start, the initial index
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   c, (ix+0)            ; BC = limit
    ld   b, (ix+1)
    inc  ix
    inc  ix
    push bc
    push de
    push hl
    ret

; ============================================================================
; LOOP_RT -- not a dictionary word: the run-time half of LOOP. Increment the index; if it has not
; reached the limit, restore the frame and branch to the inline target (DO's loop start), else
; drop the frame and continue past the target
; In:  the return address -> the inline 2-byte target, then the index and limit frame
; Destroys: AF, BC, DE, HL
; ============================================================================
LOOP_RT:
    pop  hl                  ; HL -> the inline target
    pop  de                  ; the index
    pop  bc                  ; the limit
    inc  de
    ld   a, d
    cp   b
    jr   nz, .continue
    ld   a, e
    cp   c
    jr   nz, .continue
    inc  hl                  ; finished: the frame stays popped
    inc  hl
    push hl
    ret
.continue:
    push bc
    push de
    ld   e, (hl)
    inc  hl
    ld   d, (hl)             ; DE = the loop start
    push de
    ret

; ============================================================================
; LEAVE_RT -- not a dictionary word: the run-time half of LEAVE. LOOP has patched the inline target
; to the loop end; drop the current frame and branch there
; In:  the return address -> the inline 2-byte target, then the index and limit frame
; Destroys: DE, HL
; ============================================================================
LEAVE_RT:
    pop  hl                  ; HL -> the inline target
    ld   e, (hl)
    inc  hl
    ld   d, (hl)             ; DE = the loop end
    pop  hl                  ; the index
    pop  hl                  ; the limit
    push de
    ret

; ============================================================================
; PATCH_LEAVE_CHAIN -- not a dictionary word: LOOP's and +LOOP's patching of a LEAVE chain. Each
; node holds the previous node's address (0 ends the chain); it is overwritten with DE
; In:  HL = the chain head (0: no LEAVEs), DE = the loop end
; Destroys: AF, BC, HL
; ============================================================================
PATCH_LEAVE_CHAIN:
    ld   a, h
    or   l
    ret  z
    ld   c, (hl)
    inc  hl
    ld   b, (hl)              ; BC = this node's link
    dec  hl
    ld   (hl), e
    inc  hl
    ld   (hl), d
    ld   h, b
    ld   l, c                 ; the next node
    jr   PATCH_LEAVE_CHAIN

; ============================================================================
; PLUSLOOP_RT -- not a dictionary word: the run-time half of +LOOP. A step other than 1 can jump
; over the limit, so the test is whether the sign of (index - limit) changes when the step is
; added: if it does, drop the frame and continue past the inline target, else restore the frame
; with the stepped index and branch to the target. A step of 0 never ends the loop.
; In:  ( step -- ), the return address -> the inline 2-byte target, then the index and limit frame
; Destroys: AF, DE, HL, and the cells PL_TARGET, PL_INDEX, PL_LIMIT, PL_NEWIDX, PL_DOLD, PL_DNEW
; ============================================================================
PLUSLOOP_RT:
    pop  hl
    ld   (PL_TARGET), hl
    pop  hl
    ld   (PL_INDEX), hl
    pop  hl
    ld   (PL_LIMIT), hl
    ld   e, (ix+0)             ; DE = step
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   hl, (PL_INDEX)
    add  hl, de
    ld   (PL_NEWIDX), hl
    ld   hl, (PL_INDEX)
    ld   de, (PL_LIMIT)
    or   a
    sbc  hl, de                ; index - limit, before the step
    ld   (PL_DOLD), hl
    ld   hl, (PL_NEWIDX)
    ld   de, (PL_LIMIT)
    or   a
    sbc  hl, de                ; and after it
    ld   (PL_DNEW), hl
    ld   a, (PL_DOLD+1)         ; the high bytes' top bits are the signs
    ld   hl, PL_DNEW+1
    xor  (hl)
    and  $80
    jr   nz, .terminate         ; the signs differ: the limit was crossed
.continue:
    ld   hl, (PL_LIMIT)
    push hl
    ld   hl, (PL_NEWIDX)
    push hl
    ld   hl, (PL_TARGET)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                ; DE = the loop start
    push de
    ret
.terminate:
    ld   hl, (PL_TARGET)        ; the frame stays popped
    inc  hl
    inc  hl
    push hl
    ret

; ============================================================================
; LEAVE_SLOT_ADDR_CALC -- not a dictionary word: the LEAVE_HEAD_TABLE slot of the innermost open
; loop
; Out: HL = LEAVE_HEAD_TABLE + (LEAVE_DEPTH - 1) * 2
; Destroys: AF, DE
; ============================================================================
LEAVE_SLOT_ADDR_CALC:
    ld   a, (LEAVE_DEPTH)
    dec  a
    ld   l, a
    ld   h, 0
    add  hl, hl
    ld   de, LEAVE_HEAD_TABLE
    add  hl, de
    ret

; ============================================================================
; DO ( limit start -- ) IMMEDIATE -- compile CALL DO_RT, leave the loop start (HERE) on the
; compile-time stack for LOOP, and open an empty LEAVE chain for this loop
; ============================================================================
H_DO:
    DW   DICT_CHAIN_POINT
    DB   $82, "D", "O"
W_DO:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK            ; refuses at the prompt (STATE = 0)
    ENDIF
    ld   hl, DO_RT
    call COMPILE_CALL
    ld   hl, (HERE)            ; the loop start, after the compiled call
    rst RST_DPUSH
    ld   a, (LEAVE_DEPTH)
    inc  a
    ld   (LEAVE_DEPTH), a
    call LEAVE_SLOT_ADDR_CALC
    xor  a
    ld   (hl), a
    inc  hl
    ld   (hl), a
    ret

; ============================================================================
; LOOP ( -- ) IMMEDIATE -- compile CALL LOOP_RT and DO's loop start, patch this loop's LEAVE chain
; to HERE, and close the loop's LEAVE slot
; ============================================================================
H_LOOP:
    DW   H_DO
    DB   $84, "L", "O", "O", "P"
W_LOOP:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    ld   hl, LOOP_RT
    call COMPILE_CALL
    rst RST_DPOP               ; HL = DO's loop start
    call COMPILE_WORD
    call LEAVE_SLOT_ADDR_CALC  ; before the (HERE) read: it clobbers DE
    ld   c, (hl)
    inc  hl
    ld   b, (hl)               ; BC = this loop's chain head
    ld   de, (HERE)            ; the loop end
    push bc
    pop  hl
    call PATCH_LEAVE_CHAIN
    ld   a, (LEAVE_DEPTH)
    dec  a                     ; the enclosing loop's slot is as it was left
    ld   (LEAVE_DEPTH), a
    ret

; ============================================================================
; LEAVE ( -- ) IMMEDIATE -- compile CALL LEAVE_RT and a placeholder target, threaded onto the
; innermost loop's LEAVE chain for LOOP or +LOOP to patch
; ============================================================================
H_LEAVE:
    DW   H_LOOP
    DB   $85, "L", "E", "A", "V", "E"
W_LEAVE:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    ld   hl, LEAVE_RT
    call COMPILE_CALL
    call LEAVE_SLOT_ADDR_CALC
    ld   e, (hl)
    inc  hl
    ld   d, (hl)               ; DE = the chain's old head
    dec  hl
    push hl                    ; the slot
    ld   hl, (HERE)            ; the new node, the placeholder about to be written
    push hl
    ex   de, hl                ; HL = the old head, compiled as the node's link
    call COMPILE_WORD
    pop  de                    ; DE = the new node
    pop  hl                    ; HL = the slot
    ld   (hl), e
    inc  hl
    ld   (hl), d               ; the new head
    ret

; ============================================================================
; +LOOP ( step -- ) IMMEDIATE -- as LOOP, but compile CALL PLUSLOOP_RT
; ============================================================================
H_PLUSLOOP:
    DW   H_LEAVE
    DB   $85, "+", "L", "O", "O", "P"
W_PLUSLOOP:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    ld   hl, PLUSLOOP_RT
    call COMPILE_CALL
    rst RST_DPOP               ; HL = DO's loop start
    call COMPILE_WORD
    call LEAVE_SLOT_ADDR_CALC  ; before the (HERE) read: it clobbers DE
    ld   c, (hl)
    inc  hl
    ld   b, (hl)
    ld   de, (HERE)
    push bc
    pop  hl
    call PATCH_LEAVE_CHAIN
    ld   a, (LEAVE_DEPTH)
    dec  a
    ld   (LEAVE_DEPTH), a
    ret

; ============================================================================
; I ( -- index ) -- the innermost loop's index, read off the hardware stack at SP+2 (past I's
; return address) without popping
; ============================================================================
H_I:
    DW   H_PLUSLOOP
    DB   1, "I"
W_I:
    ld   hl, 0
    add  hl, sp
    inc  hl
    inc  hl
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl
    rst RST_DPUSH
    ret

DICT_LATEST_INIT_DOLOOP EQU H_I        ; the chain head when this is the last file included

    ENDIF
