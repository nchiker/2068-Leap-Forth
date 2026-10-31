; ============================================================================
; core/forget.asm -- FORGET, and FORGET_PRINT_MSG
;
; Needs core/dict.asm (LATEST, HERE), core/interp.asm (WORD_NAME, WORD_SRC_ADDR, the scratch for
; the parsed name) and core/print.asm (W_EMIT). Link
; fields: a word's DW is DICT_CHAIN_POINT, which the including ROM sets (DEFL) to the chain the
; word extends. Every word here may destroy all registers except IX, IY and SP.
;
; The RAM dictionary is strictly append-only: HERE grows, and each new LATEST is above the one
; before. So walking from LATEST to a word's header, then setting LATEST to its LINK and HERE to
; its header address, removes exactly that word and everything defined after it.
;
; A ROM word (address below FORTH_DICT_RAM) is refused, with a message: rewinding LATEST into the
; ROM chain would silently delete every user word (FORGET DUP would reach H_DROP and wipe the user
; dictionary). Both failures print a message and return normally; they do not THROW.
; ============================================================================

    IFNDEF CORE_FORGET_ASM
    DEFINE CORE_FORGET_ASM

; ============================================================================
; FORGET_PRINT_MSG -- print a NUL-terminated string with W_EMIT (not a dictionary word)
; In:  HL -> the string
; Destroys: AF, BC, DE, HL
; ============================================================================
FORGET_PRINT_MSG:
    ld   a, (hl)
    or   a
    ret  z
    push hl
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  hl
    inc  hl
    jr   FORGET_PRINT_MSG

; ============================================================================
; FORGET ( "name" -- ) -- remove the word and every word defined after it, reclaiming their RAM;
; a ROM word is refused ("FORGET: BUILT-IN, REFUSED"), an unknown name prints "FORGET: NOT FOUND"
; ============================================================================
H_FORGET:
    DW   DICT_CHAIN_POINT
    DB   6, "F","O","R","G","E","T"
W_FORGET:
    call WORD_NAME
    rst RST_DPOP
    ld   (WORD_SRC_ADDR), hl

    ld   hl, (LATEST)
.searchloop:
    ld   a, h
    or   l
    jr   z, .notfound            ; past the oldest entry (LINK = 0)
    ld   (FORGET_TARGET_ADDR), hl  ; the candidate's header
    ld   de, 2
    add  hl, de                     ; HL -> its LENFLAGS
    ld   a, (hl)
    and  $1F                         ; its name length (bit 7 is IMMEDIATE)
    ld   c, a
    inc  hl                           ; HL -> its first character
    ld   de, (WORD_SRC_ADDR)
    ld   a, (de)                       ; the target's length
    cp   c
    jr   nz, .nomatch
    inc  de
    ld   a, c
    or   a
    jr   z, .matched
    ld   b, c
.cmploop:
    ld   a, (de)
    cp   (hl)
    jr   nz, .nomatch
    inc  hl
    inc  de
    djnz .cmploop
.matched:
    ld   hl, (FORGET_TARGET_ADDR)
    ld   de, FORTH_DICT_RAM
    or   a
    sbc  hl, de
    jr   c, .refuse_rom                   ; below FORTH_DICT_RAM: a ROM word
    ld   hl, (FORGET_TARGET_ADDR)
    ld   (HERE), hl                        ; HERE rewinds to the target's header
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                            ; DE = its LINK
    ld   (LATEST), de
    ret
.nomatch:
    ld   hl, (FORGET_TARGET_ADDR)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                             ; DE = the candidate's LINK
    ex   de, hl                               ; HL = the next older candidate
    jr   .searchloop
.refuse_rom:
    ld   hl, FORGET_MSG_ROM
    jr   FORGET_PRINT_MSG
.notfound:
    ld   hl, FORGET_MSG_NOTFOUND
    jr   FORGET_PRINT_MSG

FORGET_MSG_ROM:      DB "FORGET: BUILT-IN, REFUSED", 13, 0
FORGET_MSG_NOTFOUND: DB "FORGET: NOT FOUND", 13, 0


    ENDIF
