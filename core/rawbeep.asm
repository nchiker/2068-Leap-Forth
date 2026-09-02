; ============================================================================
; core/rawbeep.asm — the ORIGINAL Phase 5 BEEP, extracted verbatim
;
; This word used to live in core/ts2068.asm. It was extracted into its
; own file so core/ts2068.asm's own PLOT/LINE/CIRCLE/BORDER could keep
; their existing behavior completely unchanged while a NEW, real
; semitone/seconds-based BEEP (core/beep.asm) takes over the name
; "BEEP" in rom/forth_boot.asm and any future smoke ROM — two different
; global labels both named H_BEEP would collide if both files were ever
; INCLUDEd in the same ROM, so no ROM includes both; this file exists
; ONLY for rom/forth_smoke_p5.asm, whose own checkpoint 5 tests this
; exact historical behavior and shouldn't need to change just because
; a newer, better BEEP now exists elsewhere. See core/beep.asm's own
; header for the real thing.
;
; Builds on core/dict.asm, core/interp.asm, and core/ts2068.asm (all
; must be INCLUDEd first — chains via DICT_CHAIN_POINT, not hardcoded,
; matching core/floatmul.asm's own precedent for why). Needs
; kernel/sound/sound.asm for SOUND_BEEP.
; ============================================================================

    IFNDEF CORE_RAWBEEP_ASM
    DEFINE CORE_RAWBEEP_ASM

; ============================================================================
; BEEP ( pitch duration -- )
; Raw units, not musical ones — see kernel/sound/sound.asm's own
; SOUND_BEEP header. pitch is a per-half-cycle busy-wait length, not a
; frequency in Hz; duration is a count of full waveform cycles, not
; seconds.
; ============================================================================
H_BEEP:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   4, "B", "E", "E", "P"
W_BEEP:
    call DPOP_HL           ; hl = duration
    push hl                ; stashed briefly -- symmetric push/pop within
                            ; this one routine, safe (same pattern
                            ; core/control.asm's W_ELSE already uses)
    call DPOP_HL           ; hl = pitch
    ld   b, h
    ld   c, l               ; bc = pitch
    pop  de                 ; de = duration
    call SOUND_BEEP
    ret

DICT_LATEST_INIT_RAWBEEP EQU H_BEEP   ; head of the dictionary once this
                                       ; file's own word is included

    ENDIF
