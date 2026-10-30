; ============================================================================
; core/control.asm -- control flow: 0=, IF / ELSE / THEN, BEGIN / UNTIL
;
; Needs core/dict.asm and core/interp.asm (COMPILE_CALL, COMPILE_WORD). Link fields: a word's DW
; is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the word extends. Every
; word here may destroy all registers except IX, IY and SP.
;
; The compiling words keep their branch addresses on the data stack, which is free during a
; compile: only immediate words touch it then. Mis-nested IF / THEN / BEGIN / UNTIL are not
; detected; a stray address stays on the stack.
;
; A compiled branch is `CALL QBRANCH` or `CALL BRANCH` followed by the 2-byte target. The routine
; reads the target through its own return address and returns either past it (QBRANCH, flag true)
; or to the target itself (the idiom of DOLIT in core/interp.asm).
; ============================================================================

    IFNDEF CORE_CONTROL_ASM
    DEFINE CORE_CONTROL_ASM

; ============================================================================
; 0= ( n -- flag ) -- -1 if n is 0, else 0
; ============================================================================
H_ZEROEQUALS:
    DW   DICT_CHAIN_POINT
    DB   2, "0", "="
W_ZEROEQUALS:
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   a, h
    or   l
    jr   nz, .nonzero
    ld   hl, -1
    jr   .done
.nonzero:
    ld   hl, 0
.done:
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; QBRANCH -- not a dictionary word: IF and UNTIL compile a CALL to it. Pop a flag; if it is 0,
; branch to the 2-byte target after the CALL, else continue past the target
; In:  ( flag -- ), the return address -> the inline target
; Destroys: AF, DE, HL
; ============================================================================
QBRANCH:
    pop  hl                            ; HL -> the inline target
    ld   e, (ix+0)
    ld   d, (ix+1)
    inc  ix
    inc  ix                            ; DE = the flag, popped
    ld   a, d
    or   e
    jr   nz, .true
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                       ; DE = the target
    push de
    ret
.true:
    inc  hl
    inc  hl                            ; skip the target
    push hl
    ret

; ============================================================================
; BRANCH -- not a dictionary word: always branch to the 2-byte target after the CALL (ELSE
; compiles it to skip the false branch)
; In:  the return address -> the inline target
; Destroys: DE, HL
; ============================================================================
BRANCH:
    pop  hl
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    push de
    ret

; ============================================================================
; IF ( flag -- ) IMMEDIATE -- compile QBRANCH and a placeholder target, whose address is left on
; the compile-time stack for ELSE or THEN to patch
; ============================================================================
H_IF:
    DW   H_ZEROEQUALS
    DB   $82, "I", "F"
W_IF:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK            ; refuses at the prompt (STATE = 0)
    ENDIF
    ld   hl, QBRANCH
    call COMPILE_CALL
    ld   hl, (HERE)                    ; the placeholder about to be written
    rst RST_DPUSH
    ld   hl, 0
    call COMPILE_WORD
    ret

; ============================================================================
; ELSE ( -- ) IMMEDIATE -- compile the branch that skips the false part, patch IF's placeholder to
; land after it, and leave the new placeholder for THEN
; ============================================================================
H_ELSE:
    DW   H_IF
    DB   $84, "E", "L", "S", "E"
W_ELSE:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    ld   hl, BRANCH
    call COMPILE_CALL
    ld   hl, (HERE)                    ; this BRANCH's placeholder
    push hl
    ld   hl, 0
    call COMPILE_WORD
    rst RST_DPOP                       ; HL = IF's placeholder
    ld   de, (HERE)
    ld   a, e
    ld   (hl), a
    inc  hl
    ld   a, d
    ld   (hl), a
    pop  hl
    rst RST_DPUSH                      ; leave it for THEN
    ret

; ============================================================================
; THEN ( -- ) IMMEDIATE -- patch the placeholder on top of the compile-time stack (IF's, or
; ELSE's) to land at HERE
; ============================================================================
H_THEN:
    DW   H_ELSE
    DB   $84, "T", "H", "E", "N"
W_THEN:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    rst RST_DPOP
    ld   de, (HERE)
    ld   a, e
    ld   (hl), a
    inc  hl
    ld   a, d
    ld   (hl), a
    ret

; ============================================================================
; BEGIN ( -- ) IMMEDIATE -- leave HERE, the loop start, on the compile-time stack
; ============================================================================
H_BEGIN:
    DW   H_THEN
    DB   $85, "B", "E", "G", "I", "N"
W_BEGIN:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    ld   hl, (HERE)
    rst RST_DPUSH
    ret

; ============================================================================
; UNTIL ( flag -- ) IMMEDIATE -- compile QBRANCH to the address BEGIN left: at run time a false
; flag loops back, a true one ends the loop
; ============================================================================
H_UNTIL:
    DW   H_BEGIN
    DB   $85, "U", "N", "T", "I", "L"
W_UNTIL:
    IFDEF COMPILE_ONLY_CHECK_ENABLED
    call COMPILE_ONLY_CHECK
    ENDIF
    ld   hl, QBRANCH
    call COMPILE_CALL
    rst RST_DPOP                       ; HL = BEGIN's loop start
    call COMPILE_WORD
    ret

DICT_LATEST_INIT_P4 EQU H_UNTIL        ; the chain head when this is the last file included

    ENDIF
