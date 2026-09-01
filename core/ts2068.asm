; ============================================================================
; core/ts2068.asm — Phase 5: TS2068 vocabulary (PLOT, LINE, CIRCLE, BEEP,
; BORDER)
;
; Builds on core/dict.asm, core/interp.asm, and core/control.asm (all
; must be INCLUDEd first — chains its own dictionary entries onto
; core/control.asm's H_UNTIL, and uses DPOP_HL). This is the first
; Phase to also require kernel/ modules: kernel/graphics/graphics.asm
; and kernel/sound/sound.asm must both be INCLUDEd too (their own
; internal INCLUDEs pull in include/sysvars.inc, which is why they
; matter for address planning — see the note below).
;
; WHAT THIS ADDS — thin wrappers, matching include/kernel_api.inc
; almost 1:1, exactly as docs/PROJECT_PLAN.md's Phase 5 description
; promised:
;   PLOT   ( x y -- )          GFX_WRITE_PIXEL
;   LINE   ( x1 y1 x2 y2 -- )  GFX_LINE (reads its args from sysvars)
;   CIRCLE ( xc yc r -- )      GFX_CIRCLE (reads its args from sysvars)
;   BEEP   ( pitch duration -- ) SOUND_BEEP
;   BORDER ( color -- )        GFX_SET_BORDER
;
; All five take plain 16-bit stack cells but only ever use the LOW
; BYTE of each — every TS2068 screen coordinate, radius, and color fits
; in 8 bits (kernel_api.inc's own comments already document x as 0-255,
; y as 0-191, color as 0-7), and GFX_LINE_X0/Y0/X1/Y1 and
; GFX_CIRCLE_XC/YC/R/ATTR/OVER (include/sysvars.inc) are all declared
; as single bytes, not words. No range checking is done — matching
; every earlier phase's "no error recovery yet" scope note, not an
; oversight specific to this file.
;
; A FIXED DEFAULT ATTRIBUTE: none of these words take an ink/paper
; color — 2068-Forth has no INK/PAPER words yet (BASIC's equivalent),
; so DEFAULT_ATTR below (white paper, black ink — the classic Spectrum
; power-on default) is used for every PLOT/LINE/CIRCLE call. Revisit
; once color words exist.
;
; RAM ADDRESS PLANNING — READ BEFORE ADDING SCRATCH HERE: this file
; needs none of its own RAM state (every word here just moves values
; between the data stack and kernel sysvars/registers), but the moment
; a future addition DOES need a scratch cell, don't guess an address —
; core/interp.asm's own header tells the story of a real collision this
; project already had between its own scratch and 2068-Leap's
; kernel/BASIC sysvars, found by literally assembling every kernel/
; module this ROM needs together and inspecting the resulting .sym
; file for the address range in question. Repeat that check, don't
; assume a gap is empty by inspection alone.
; ============================================================================

    IFNDEF CORE_TS2068_ASM
    DEFINE CORE_TS2068_ASM

DEFAULT_ATTR EQU $38   ; paper 7 (white), ink 0 (black), no bright/flash —
                       ; the classic Spectrum-family power-on default

; ============================================================================
; PLOT ( x y -- )
; ============================================================================
H_PLOT:
    DW   H_UNTIL
    DB   4, "P", "L", "O", "T"
W_PLOT:
    call DPOP_HL           ; hl = y
    ld   c, l
    call DPOP_HL           ; hl = x
    ld   b, l
    ld   a, DEFAULT_ATTR
    ld   d, 0              ; OVER=0: set the pixel, don't XOR-toggle it
    call GFX_WRITE_PIXEL
    ret

; ============================================================================
; LINE ( x1 y1 x2 y2 -- )
; ============================================================================
H_LINE:
    DW   H_PLOT
    DB   4, "L", "I", "N", "E"
W_LINE:
    call DPOP_HL           ; hl = y2
    ld   a, l
    ld   (GFX_LINE_Y1), a
    call DPOP_HL           ; hl = x2
    ld   a, l
    ld   (GFX_LINE_X1), a
    call DPOP_HL           ; hl = y1
    ld   a, l
    ld   (GFX_LINE_Y0), a
    call DPOP_HL           ; hl = x1
    ld   a, l
    ld   (GFX_LINE_X0), a
    ld   a, DEFAULT_ATTR
    ld   (GFX_LINE_ATTR), a
    xor  a
    ld   (GFX_LINE_OVER), a
    call GFX_LINE
    ret

; ============================================================================
; CIRCLE ( xc yc r -- )
; ============================================================================
H_CIRCLE:
    DW   H_LINE
    DB   6, "C", "I", "R", "C", "L", "E"
W_CIRCLE:
    call DPOP_HL           ; hl = r
    ld   a, l
    ld   (GFX_CIRCLE_R), a
    call DPOP_HL           ; hl = yc
    ld   a, l
    ld   (GFX_CIRCLE_YC), a
    call DPOP_HL           ; hl = xc
    ld   a, l
    ld   (GFX_CIRCLE_XC), a
    ld   a, DEFAULT_ATTR
    ld   (GFX_CIRCLE_ATTR), a
    xor  a
    ld   (GFX_CIRCLE_OVER), a
    call GFX_CIRCLE
    ret

; ============================================================================
; BEEP ( pitch duration -- )
; Raw units, not musical ones — see kernel/sound/sound.asm's own
; SOUND_BEEP header. pitch is a per-half-cycle busy-wait length, not a
; frequency in Hz; duration is a count of full waveform cycles, not
; seconds. No conversion exists yet; a future phase's job, not this
; one's.
; ============================================================================
H_BEEP:
    DW   H_CIRCLE
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

; ============================================================================
; BORDER ( color -- )
; ============================================================================
H_BORDER:
    DW   H_BEEP
    DB   6, "B", "O", "R", "D", "E", "R"
W_BORDER:
    call DPOP_HL
    ld   a, l
    call GFX_SET_BORDER
    ret

DICT_LATEST_INIT_P5 EQU H_BORDER   ; head of the dictionary as of Phase 5

    ENDIF
