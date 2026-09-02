; ============================================================================
; core/bytemem.asm — Phase 36: C@ and C! (byte-level memory access)
;
; Builds on core/dict.asm (DPUSH_HL/DPOP_HL and this project's own
; cell-level @/! for the exact structural pattern this mirrors — both
; must be INCLUDEd first; this file's own first header chains through
; DICT_CHAIN_POINT).
;
; WHAT THIS ADDS: standard Forth's own byte-level counterparts to `@`/
; `!` — the equivalent of BASIC's `PEEK`/`POKE`, a real, previously-
; unfilled gap this project's own audit against the sibling 2068-Leap
; BASIC project and the real TS2068 ROM's own command set found: only
; cell-level (16-bit) memory access existed before this phase, with no
; way to read or write a single byte at all.
;
; C@ ( addr -- byte )  reads ONE byte at addr and ZERO-EXTENDS it into
; a full cell (the standard's own convention — the result is always
; non-negative, 0-255, regardless of the byte's own top bit).
; C! ( byte addr -- )  stores the LOW byte of `byte` at addr, silently
; discarding its own high byte — again the standard's own convention,
; not a shortcut invented here.
;
; Exactly `core/dict.asm`'s own `@`/`!` shape, byte-sized instead of
; cell-sized — no new design decisions, no hand-verification needed
; beyond that direct correspondence.
; ============================================================================

    IFNDEF CORE_BYTEMEM_ASM
    DEFINE CORE_BYTEMEM_ASM

; ============================================================================
; C@ ( addr -- byte )  fetch, zero-extended
; ============================================================================
H_CFETCH:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   2, "C", "@"
W_CFETCH:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    ld   a, (hl)       ; a = the byte at addr
    ld   (ix+0), a
    xor  a
    ld   (ix+1), a     ; zero-extend into the cell
    ret

; ============================================================================
; C! ( byte addr -- )  store, low byte only
; ============================================================================
H_CSTORE:
    DW   H_CFETCH
    DB   2, "C", "!"
W_CSTORE:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   a, (ix+0)     ; a = low byte of the value to store
    inc  ix
    inc  ix
    ld   (hl), a
    ret

DICT_LATEST_INIT_BYTEMEM EQU H_CSTORE   ; head of the dictionary once
                                         ; this file's own words are
                                         ; both included

    ENDIF
