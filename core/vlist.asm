; ============================================================================
; core/vlist.asm — Phase 49: VLIST
;
; Builds on core/dict.asm (LATEST) and core/print.asm/core/outwords.asm
; (W_EMIT, W_SPACE) — all three must be INCLUDEd first, same convention
; as every other core/ file that extends the chain via DICT_CHAIN_POINT.
;
; WHAT THIS ADDS:
;   VLIST ( -- )   prints every word name currently in the dictionary,
;              newest (LATEST) first, walking the SAME linked list
;              core/interp.asm's own FIND walks (confirmed by reading
;              FIND itself, not guessed) all the way back to the oldest
;              ROM-resident primitive (LINK = 0) — unlike core/printer.
;              asm's own LLIST, which deliberately STOPS at the ROM/RAM
;              boundary because it's meant to list only the user's own
;              program. VLIST is a live-REPL discovery aid, so the
;              whole dictionary (built-ins included) is the point.
;
; SCREEN WRAPPING: deliberately does NOT invent its own pagination.
; Every name's characters are printed one at a time via W_EMIT, exactly
; the same per-character idiom rom/forth_boot.asm's own
; INTERPRET_UNKNOWN_WORD already uses to echo an unrecognized word back
; — W_EMIT's own column/row wrap-and-scroll logic (core/print.asm) is
; what already makes 32-column output "just work" for every other
; multi-character output in this project (`.`, `."`, the unknown-word
; echo above); reusing it here rather than adding a second wrapping
; scheme keeps VLIST's own screen behavior identical to everything else
; already on screen. A single SPACE (core/outwords.asm) separates each
; name from the next.
;
; DATA STACK: VLIST pushes and pops nothing net — DPUSH_HL/W_EMIT are
; used per character but always paired 1:1, so IX returns to exactly
; where it started (verified directly by rom/forth_smoke_p49.asm's own
; checkpoint, not just asserted here).
;
; THE PER-CHARACTER PRINT LOOP uses the exact same "djnz .charloop with
; no leading zero-guard" idiom rom/forth_boot.asm's own
; INTERPRET_UNKNOWN_WORD.printword loop already uses, on the same
; already-accepted assumption that a name's own length is never zero
; (every LENFLAGS byte this project has ever written encodes a real,
; nonzero name) — not a new risk introduced here.
; ============================================================================

    IFNDEF CORE_VLIST_ASM
    DEFINE CORE_VLIST_ASM

; ============================================================================
; VLIST ( -- )
; ============================================================================
H_VLIST:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "V","L","I","S","T"
W_VLIST:
    ld   hl, (LATEST)
.wordloop:
    ld   a, h
    or   l
    ret  z                       ; walked off the oldest entry -- done
    push hl                       ; save this entry's header address
                                   ; (also where its own LINK field lives)
    ld   de, 2
    add  hl, de                    ; hl -> LENFLAGS
    ld   a, (hl)
    and  $1F                       ; name length (bit 7 IMMEDIATE flag
                                    ; masked off -- irrelevant here)
    ld   b, a
    inc  hl                        ; hl -> first name character
.charloop:
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .charloop
    call W_SPACE
    pop  hl                         ; hl = this entry's header address
                                     ; again
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                    ; de = LINK (the next-older entry)
    ex   de, hl
    jr   .wordloop

DICT_LATEST_INIT_VLIST EQU H_VLIST   ; head of the dictionary once this
                                       ; file's own words are included

    ENDIF
