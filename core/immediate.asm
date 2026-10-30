; ============================================================================
; core/immediate.asm -- IMMEDIATE
;
; Needs core/dict.asm. Link fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets
; (DEFL) to the chain the word extends. Every word here may destroy all registers except IX, IY
; and SP.
;
; IMMEDIATE is not itself immediate: it works as `: FOO ... ; IMMEDIATE`, where `;` has already
; set STATE to 0, so the interpreter executes it whatever its flag. Inside a definition
; (`: BAR IMMEDIATE ... ;`) it would be compiled, not run.
; ============================================================================

    IFNDEF CORE_IMMEDIATE_ASM
    DEFINE CORE_IMMEDIATE_ASM

; ============================================================================
; IMMEDIATE ( -- ) -- mark the latest definition immediate (bit 7 of its LENFLAGS byte)
; ============================================================================
H_IMMEDIATE:
    DW   DICT_CHAIN_POINT
    DB   9, "I","M","M","E","D","I","A","T","E"
W_IMMEDIATE:
    ld   hl, (LATEST)
    ld   de, 2
    add  hl, de                        ; HL -> the LENFLAGS byte
    ld   a, (hl)
    or   $80
    ld   (hl), a
    ret

DICT_LATEST_INIT_IMMEDIATE EQU H_IMMEDIATE ; the chain head when this is the last file included

    ENDIF
