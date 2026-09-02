; ============================================================================
; core/array.asm — Phase 26: ARRAY and CELLS
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT,
; same convention as every other core/ file) and reuses core/interp.asm's
; own COMPILE_LITERAL/COMPILE_BYTE/W_WORD/DPOP_HL/HERE/LATEST plumbing
; and header-construction shape, exactly as core/variable.asm's own
; VARIABLE/CONSTANT already do (the header-building steps are
; duplicated here rather than factored out, for the same reason
; core/variable.asm's own header gives: never modify an
; already-stable, widely-shared file for a later phase's convenience).
;
; WHAT THIS ADDS — a real gap found by a direct audit of 2068-Leap's
; own BASIC ROM (`~/ts2068rom`) against this project's dictionary:
; BASIC's DIM (numeric arrays) had no Forth equivalent at all.
;   ARRAY ( n "name" -- )   creates <name> such that
;             <name> ( -- addr ) pushes the address of a fresh,
;             zero-initialized block of n 2-byte CELLS — read/write
;             individual elements with plain @ and ! (Phase 2,
;             core/dict.asm) at addr + (index CELLS), the same address-
;             arithmetic idiom real Forth systems use for arrays; there
;             is no dedicated indexing word, matching ANS Forth's own
;             convention (CREATE/ALLOT-based arrays are always indexed
;             this way, not through a special operator)
;   CELLS ( n -- n*2 )      converts a cell COUNT into a byte OFFSET —
;             this project's own cell size is 2 bytes (every DPUSH_HL/
;             DPOP_HL moves 16 bits), so CELLS is just a left shift,
;             but writing `n CELLS` instead of `n 2 *` at every array
;             access site names the intent and would keep working
;             unchanged if the cell size ever did (it won't, but this
;             costs nothing and matches how real Forth code is written)
;
; USAGE: `10 ARRAY NUMS` reserves a 10-cell (20-byte) array; `3 CELLS
; NUMS + @` reads element 3; `99 3 CELLS NUMS + !` writes 99 to it.
; Like ARRAY itself, neither VARIABLE nor CONSTANT before it used a
; real CREATE/DOES> (this project doesn't have one) — ARRAY's own
; runtime is the identical compiled-literal-then-RET idiom, just with
; n*2 reserved bytes after it instead of a fixed 2.
;
; NO BOUNDS CHECKING, matching every other memory-touching word in this
; project (@, !, and now ARRAY's own elements) — see core/dict.asm's
; own established "no error recovery yet" scope note, unchanged here.
; ============================================================================

    IFNDEF CORE_ARRAY_ASM
    DEFINE CORE_ARRAY_ASM

; ============================================================================
; ARRAY ( n "name" -- )
; ============================================================================
H_ARRAY:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "A", "R", "R", "A", "Y"
W_ARRAY:
    call DPOP_HL            ; hl = n (cell count)
    push hl                 ; stashed briefly on the Z80 hardware stack
                             ; -- safe: symmetric push/pop within this
                             ; one routine's own body, and everything
                             ; between here and the matching pop below
                             ; only touches the IX-based data stack,
                             ; never SP (core/variable.asm's own
                             ; W_CONSTANT documents this same technique
                             ; for its own value-across-name-parsing
                             ; case)
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
                                    ; RET -- the array's own elements
                                    ; sit right after both
    add  hl, de                    ; hl = the array's own base address
    call COMPILE_LITERAL           ; compiles CALL DOLIT + that address
    ld   a, $C9                    ; Z80 RET opcode
    call COMPILE_BYTE

    pop  hl                        ; hl = n, restored (still the cell
                                    ; count from this routine's own
                                    ; entry -- nothing since the push
                                    ; above touched SP)
    add  hl, hl                    ; hl = n*2 -- byte count to zero
    ld   b, h
    ld   c, l                      ; bc = byte count
    ld   hl, (HERE)                ; hl == the array's own base address,
                                    ; exactly as computed above
    ld   a, b
    or   c
    jr   z, .noinit                ; n=0 -- nothing to zero
.zeroloop:
    xor  a
    ld   (hl), a
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, .zeroloop
.noinit:
    ld   (HERE), hl

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; CELLS ( n -- n*2 )
; ============================================================================
H_CELLS:
    DW   H_ARRAY
    DB   5, "C", "E", "L", "L", "S"
W_CELLS:
    call DPOP_HL
    add  hl, hl
    call DPUSH_HL
    ret

DICT_LATEST_INIT_ARRAY EQU H_CELLS   ; head of the dictionary once this
                                      ; file's own words are included

    ENDIF
