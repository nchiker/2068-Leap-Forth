; ============================================================================
; core/udg.asm — Phase 51: UDG
;
; Builds on core/dict.asm (DICT_CHAIN_POINT, DPOP_HL, DPUSH_HL) only —
; no kernel INCLUDE needed, matching core/free.asm's own minimal-
; dependency shape. A new, small file rather than editing an existing
; shared one, matching this project's own standing practice (see
; core/loopext.asm's or core/vlist.asm's own header for why).
;
; WHAT THIS ADDS: UDG ( n -- addr ), n = 0-20, leaving the absolute
; address of that UDG slot's 8-byte bitmap on the stack — the Forth
; equivalent of real Sinclair BASIC's `USR "a"` convention for locating
; a UDG's bitmap so a program can POKE/C! bytes into it directly.
;
; UDG_TABLE ($F180, include/sysvars.inc) is already real, working, plain
; RAM inherited from the same lineage as the sibling ~/ts2068rom BASIC
; project: 21 slots x 8 bytes for character codes 144-164, and
; kernel/graphics/graphics.asm's own GFX_CHAR_TO_FONT_OFFSET already
; routes those codes there automatically (confirmed by reading its own
; .is_udg path directly, not assumed) — so EMIT-ing 144-164 already
; renders whatever bitmap bytes live there. This word is the only
; missing piece: making UDG_TABLE something a running Forth program can
; address by slot number, since it was previously just an assembly-time
; EQU.
;
; NO BOUNDS CHECK on n, deliberately: every other simple address-
; arithmetic word already in this dictionary (@, !, C@, C!, +) trusts
; the caller's own address/offset math, and UDG_COUNT (21) is already
; enforced independently, at render time, by GFX_CHAR_TO_FONT_OFFSET's
; own range check on the CHARACTER CODE (144-164) — an out-of-range
; UDG argument here just computes an address nothing will ever read via
; GFX_PUTCHAR, no different from computing any other bad address by
; hand.
;
; ARITHMETIC: addr = UDG_TABLE + n*8. n*8 is a plain 3-bit left shift
; of the full 16-bit cell (n is documented 0-20, so no overflow risk:
; 20*8+168 = 328, nowhere near a 16-bit wrap).
; ============================================================================

    IFNDEF CORE_UDG_ASM
    DEFINE CORE_UDG_ASM

; ============================================================================
; UDG ( n -- addr )
; ============================================================================
H_UDG:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                             ; per this project's own established chain-
                             ; splice convention) before this INCLUDE
    DB   3, "U","D","G"
W_UDG:
    call DPOP_HL
    add  hl, hl              ; n*2
    add  hl, hl              ; n*4
    add  hl, hl              ; n*8
    ld   de, UDG_TABLE
    add  hl, de               ; UDG_TABLE + n*8
    call DPUSH_HL
    ret

DICT_LATEST_INIT_UDG EQU H_UDG   ; head of the dictionary once this
                                  ; file is the last one INCLUDEd

    ENDIF
