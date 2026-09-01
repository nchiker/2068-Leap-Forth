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
; The header-construction steps `:` (core/interp.asm's W_COLON) already
; performs are repeated here rather than factored into a shared helper
; — this project's standing practice is to never modify an
; already-stable, widely-shared file for a later phase's convenience
; (core/interp.asm is INCLUDEd by every smoke ROM in this entire
; project); a little duplicated header-building code is the safer
; trade against a regression surface that wide.
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
; VARIABLE ( "name" -- )
; ============================================================================
H_VARIABLE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   8, "V", "A", "R", "I", "A", "B", "L", "E"
W_VARIABLE:
    call W_WORD
    call DPOP_HL
    ld   (WORD_SRC_ADDR), hl

    ld   de, (HERE)
    ld   (NEW_HEADER_ADDR), de
    ld   hl, (LATEST)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   hl, (WORD_SRC_ADDR)
    ld   a, (hl)                  ; name length (already <= 31, W_WORD
                                   ; truncates at 32)
    ld   (de), a
    inc  de
    inc  hl                       ; hl -> first name char
    ld   b, a
    ld   a, b
    or   a
    jr   z, .namedone
.namecopy:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .namecopy
.namedone:
    ld   (HERE), de                ; HERE now points to this word's own
                                    ; body, right where the compiled
                                    ; literal below will start

    ld   hl, (HERE)
    ld   de, 6                     ; 5-byte compiled literal (CALL
                                    ; DOLIT + 2-byte target) + 1-byte
                                    ; RET -- the data cell sits right
                                    ; after both
    add  hl, de                    ; hl = the data cell's own address
    call COMPILE_LITERAL           ; compiles CALL DOLIT + that address
    ld   a, $C9                    ; Z80 RET opcode
    call COMPILE_BYTE
    ld   hl, (HERE)                ; HERE now == the data cell's own
                                    ; address, exactly as computed above
    xor  a
    ld   (hl), a
    inc  hl
    ld   (hl), a
    inc  hl
    ld   (HERE), hl

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; CONSTANT ( n "name" -- )
; ============================================================================
H_CONSTANT:
    DW   H_VARIABLE
    DB   8, "C", "O", "N", "S", "T", "A", "N", "T"
W_CONSTANT:
    call DPOP_HL
    push hl                        ; stash the value across name
                                    ; parsing on the Z80 hardware stack
                                    ; -- safe: symmetric push/pop within
                                    ; this one routine's own body, and
                                    ; W_WORD/DPOP_HL only ever touch the
                                    ; IX-based data stack, never SP
                                    ; (core/control.asm's W_ELSE
                                    ; documents this same technique)
    call W_WORD
    call DPOP_HL
    ld   (WORD_SRC_ADDR), hl

    ld   de, (HERE)
    ld   (NEW_HEADER_ADDR), de
    ld   hl, (LATEST)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   hl, (WORD_SRC_ADDR)
    ld   a, (hl)
    ld   (de), a
    inc  de
    inc  hl
    ld   b, a
    ld   a, b
    or   a
    jr   z, .namedone
.namecopy:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .namecopy
.namedone:
    ld   (HERE), de

    pop  hl                        ; hl = the constant's own value
    call COMPILE_LITERAL
    ld   a, $C9
    call COMPILE_BYTE

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

DICT_LATEST_INIT_VARIABLE EQU H_CONSTANT   ; head of the dictionary once
                                            ; this file's own words are
                                            ; included

    ENDIF
