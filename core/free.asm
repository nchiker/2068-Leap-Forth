; ============================================================================
; core/free.asm — Phase 43/44: FREE (dictionary space remaining)
;
; Builds on core/dict.asm (HERE, DPUSH_HL) only — no kernel INCLUDE
; needed, unlike STICK/CLS before it.
;
; WHAT THIS ADDS: FREE ( -- n ), the real ROM's own "how much room is
; left" query. Unlike every other Phase 34-42 addition, this one had a
; genuine open design question first: HERE (core/dict.asm) grows UPWARD
; from FORTH_DICT_RAM ($A000), but nothing in this project had ever
; established the correct UPPER ceiling for that growth — the low end
; of the $8000+ RAM region was probe-verified early on, but the high
; end never was (see docs/PROJECT_PLAN.md's own Backlog note this
; phase closes out).
;
; THE FLOOR is FORTH_DICT_RAM ($9800, see core/dict.asm's own header for
; why it moved down from an earlier $A000 — a confirmed-idle 2048-byte
; gap above the data stack, reclaimed after this file's own design
; review, not left on the table).
;
; THE CEILING WAS $C000 (Phase 43), then raised to $F000 (Phase 44,
; after the user asked for parity with the sibling 2068-Leap project's
; own 15,322 bytes free). Neither number is a guess.
;
; Phase 43's $C000 came from a real, confirmed hazard: core/moregfx.asm's
; FILL word calls the shared kernel/graphics/graphics.asm's own GFX_FILL
; routine, which unconditionally used GFX_FILL_VISITED/GFX_FILL_STACK as
; scratch on EVERY call. 2068-Forth's dictionary is PERMANENT RAM state
; sharing that same physical address space (unlike the sibling project,
; where that range is genuinely transient behind EXROM banking this
; project doesn't have) — so HERE could never be allowed to reach
; wherever that scratch lived.
;
; Phase 44 removed the hazard at its source instead of just documenting
; around it: GFX_FILL_VISITED/GFX_FILL_STACK were relocated out of
; 2068-Forth's own dictionary range entirely, into the idle "second
; display file" video-RAM pool at $5B00-$7FFF (see include/sysvars.inc's
; own GFX_FILL_VISITED header for the full relocation writeup, including
; the new 64-column-mode hazard that move creates and how
; core/moregfx.asm's own FILL guards against it). With that hazard gone,
; the only other live thing found in $C000-$FEFF (via the same
; grep-the-real-build's-own-.sym-table method Phase 43 used) is
; GFX_LINE_X0-Y1 (4 bytes at $F3C4-$F3C7, this project's own LINE word)
; — everything else there (sprite capture buffers, and BASIC-only state
; this project never uses: label table, UDGs, DEF FN, the loadable-
; extension registry) is confirmed dead weight. $F000 sits with
; comfortable margin below that one live cell.
;
; This gives HERE 22,528 bytes of real headroom ($9800-$EFFF) before
; FREE reports empty — the honest number for what this project's actual
; RAM topology supports today, better than the sibling project's own
; 15,322 bytes, not a round guess.
;
; STILL LEFT ON THE TABLE, ON PURPOSE: $F000-$F3C3 (964 bytes) is
; deliberately unclaimed margin below the one live LINE cell, not
; pushed to the exact byte — a small, cheap safety buffer against this
; analysis having missed something, worth more than ~1K of extra
; headroom at this scale.
; ============================================================================

    IFNDEF CORE_FREE_ASM
    DEFINE CORE_FREE_ASM

DICT_RAM_CEILING EQU $F000   ; Phase 44: raised from $C000 once FILL's
                             ; own scratch was relocated out of the way
                             ; (include/sysvars.inc) — sits with margin
                             ; below GFX_LINE_X0-Y1 ($F3C4), the one
                             ; remaining live cell found in this range;
                             ; see this file's own header for the full
                             ; writeup

; ============================================================================
; FREE ( -- n )  bytes remaining before HERE reaches DICT_RAM_CEILING
; ============================================================================
H_FREE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                             ; per this project's own established chain-
                             ; splice convention) before this INCLUDE
    DB   4, "F","R","E","E"
W_FREE:
    ld   hl, DICT_RAM_CEILING
    ld   de, (HERE)
    or   a               ; clear carry before sbc
    sbc  hl, de          ; hl = ceiling - HERE
    call DPUSH_HL
    ret

DICT_LATEST_INIT_FREE EQU H_FREE   ; head of the dictionary once this
                                    ; file is the last one INCLUDEd

    ENDIF
