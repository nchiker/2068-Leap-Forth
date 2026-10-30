; ============================================================================
; core/variable.asm — Phase 12: VARIABLE and CONSTANT
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT,
; same convention as core/control.asm/core/storage.asm/core/float.asm/
; core/print.asm/core/compare.asm) and reuses core/interp.asm's own
; COMPILE_LITERAL/COMPILE_BYTE/W_WORD/DPOP_HL/HERE/LATEST plumbing,
; including its WORD_SRC_ADDR/NEW_HEADER_ADDR scratch cells (documented
; there as "W_COLON's own scratch" — reused here for the exact same
; purpose, building a new dictionary header, never concurrently with
; `:` itself, since nothing in this project supports compiling one
; defining word inside another yet).
;
; The header-construction steps `:` (core/interp.asm's W_COLON) performs are
; repeated here, not factored into core/interp.asm (never modified for a later phase's
; convenience: every smoke ROM includes it), but only once: VAR_HEADER and VAR_END are
; shared by VARIABLE, CONSTANT and, in core/fpstack.asm, FVARIABLE and FCONSTANT (step F).
;
; WHAT THIS ADDS (the exact gap docs/forth_tutorial.md's "What's not
; here yet" section has named since Phase 4: "built on top of the @/!
; in section 4"):
;   VARIABLE ( "name" -- )    creates <name> such that
;             <name> ( -- addr ) pushes the address of a fresh,
;             zero-initialized 2-byte cell — read/write it with @ and
;             ! (Phase 2, core/dict.asm)
;   CONSTANT ( n "name" -- )  creates <name> such that
;             <name> ( -- n ) always pushes the value n had at
;             CONSTANT's own definition time — no data cell, and no way
;             to change it afterward (that's the whole point of
;             "constant" versus "variable")
;
; NEITHER USES A REAL CREATE/DOES> (this project doesn't have one — see
; core/dict.asm's own forward-looking "Phase 3's CREATE" comments,
; never actually built): VARIABLE's runtime is just a compiled literal
; (core/interp.asm's own DOLIT idiom, the same mechanism a typed number
; compiles to inside a colon definition) pushing the cell's OWN
; address, and CONSTANT's runtime is that exact same compiled-literal
; idiom pushing the value directly instead of an address. Both are
; followed by a compiled RET (the same byte `;` compiles) to return
; control normally — unlike an ordinary colon definition's body, where
; a compiled literal is followed by MORE compiled code it falls through
; into, here there isn't any more code, so that fallthrough must land
; on a real RET instead of whatever bytes happen to follow next
; (VARIABLE's own 2-byte data cell, specifically — landing there
; instead would try to execute the cell's stored VALUE as if it were
; code).
; ============================================================================

    IFNDEF CORE_VARIABLE_ASM
    DEFINE CORE_VARIABLE_ASM

; ============================================================================
; VAR_HEADER -- the header of a new word, shared by VARIABLE, CONSTANT, FVARIABLE and FCONSTANT (core/fpstack.asm):
; parses the next word, builds LINK + counted name at HERE (NEW_HEADER_ADDR = the header, HERE = past the name, where
; the code will start). Does not touch LATEST (VAR_END does, once the body is compiled).
; Destroys: AF, BC, DE, HL
; ============================================================================
VAR_HEADER:
    call W_WORD
    rst  RST_DPOP                 ; hl -> the counted name (<= 31 characters, W_WORD truncates)
    ex   de, hl                   ; de -> the name
    ld   hl, (HERE)
    ld   (NEW_HEADER_ADDR), hl
    ld   bc, (LATEST)
    ld   (hl), c
    inc  hl
    ld   (hl), b
    inc  hl
    ex   de, hl                   ; hl -> the name, de -> where it goes
    ld   c, (hl)
    ld   b, 0
    inc  bc                       ; the length byte and the name
    ldir
    ld   (HERE), de
    ret

; ============================================================================
; VAR_END -- compiles the RET that ends the word's code and links the word in (LATEST = NEW_HEADER_ADDR)
; Destroys: AF, HL
; ============================================================================
VAR_END:
    ld   a, $C9                   ; Z80 RET opcode
    call COMPILE_BYTE
    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; VARIABLE ( "name" -- )
; VARIABLE_N -- the same with A zeroed data bytes instead of 2 (FVARIABLE: 5)
; ============================================================================
H_VARIABLE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   8, "V", "A", "R", "I", "A", "B", "L", "E"
W_VARIABLE:
    ld   a, 2
VARIABLE_N:
    push af                       ; the data size (the machine stack: W_WORD and the header code use every register)
    call DICT_ROOM0
    call VAR_HEADER
    ld   hl, (HERE)
    ld   de, 6                    ; 5-byte compiled literal (CALL
                                  ; DOLIT + 2-byte target) + 1-byte
                                  ; RET -- the data cell sits right
                                  ; after both
    add  hl, de                   ; hl = the data cell's own address
    call COMPILE_LITERAL          ; compiles CALL DOLIT + that address
    call VAR_END
    pop  af
    ld   b, a
    ld   hl, (HERE)               ; HERE == the data cell's own address
    xor  a
.zero:
    ld   (hl), a
    inc  hl
    djnz .zero
    ld   (HERE), hl
    ret

; ============================================================================
; CONSTANT ( n "name" -- )
; ============================================================================
H_CONSTANT:
    DW   H_VARIABLE
    DB   8, "C", "O", "N", "S", "T", "A", "N", "T"
W_CONSTANT:
    call DICT_ROOM0
    rst RST_DPOP
    push hl                        ; stash the value across name
                                    ; parsing on the Z80 hardware stack
                                    ; -- safe: symmetric push/pop within
                                    ; this one routine's own body, and
                                    ; W_WORD/DPOP_HL only ever touch the
                                    ; IX-based data stack, never SP
                                    ; (core/control.asm's W_ELSE
                                    ; documents this same technique)
    call VAR_HEADER
    pop  hl                        ; hl = the constant's own value
    call COMPILE_LITERAL
    jp   VAR_END

DICT_LATEST_INIT_VARIABLE EQU H_CONSTANT   ; head of the dictionary once
                                            ; this file's own words are
                                            ; included

    ENDIF
