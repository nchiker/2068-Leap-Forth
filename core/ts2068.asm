; ============================================================================
; core/ts2068.asm — Phase 5: TS2068 vocabulary (PLOT, LINE, CIRCLE,
; BORDER)
;
; Builds on core/dict.asm, core/interp.asm, and core/control.asm (all
; must be INCLUDEd first — chains its own dictionary entries onto
; core/control.asm's H_UNTIL, and uses DPOP_HL). This is the first
; Phase to also require kernel/ modules: kernel/graphics/graphics.asm
; must be INCLUDEd too (its own internal INCLUDEs pull in
; include/sysvars.inc, which is why it matters for address planning —
; see the note below).
;
; WHAT THIS ADDS — thin wrappers, matching include/kernel_api.inc
; almost 1:1, exactly as docs/PROJECT_PLAN.md's Phase 5 description
; promised:
;   PLOT   ( x y -- )          GFX_WRITE_PIXEL
;   LINE   ( x1 y1 x2 y2 -- )  GFX_LINE (reads its args from sysvars)
;   CIRCLE ( xc yc r -- )      GFX_CIRCLE (reads its args from sysvars)
;   BORDER ( color -- )        GFX_SET_BORDER
;
; BEEP originally lived here too (raw hardware-timing units, no
; conversion) — MOVED OUT as of the real, semitone/seconds BEEP
; (core/beep.asm, replacing it in rom/forth_boot.asm's own dictionary)
; and core/rawbeep.asm (the original word, byte-for-byte unchanged,
; kept only for rom/forth_smoke_p5.asm's own historical checkpoint).
; kernel/sound/sound.asm is therefore no longer a dependency of THIS
; file — see core/beep.asm's own header for where that dependency
; (and BEEP itself) now lives.
;
; All four remaining words take plain 16-bit stack cells but only ever
; use the LOW BYTE of each — every TS2068 screen coordinate, radius,
; and color fits in 8 bits (kernel_api.inc's own comments already
; document x as 0-255, y as 0-191, color as 0-7), and GFX_LINE_X0/Y0/
; X1/Y1 and GFX_CIRCLE_XC/YC/R/ATTR/OVER (include/sysvars.inc) are all
; declared as single bytes, not words. No range checking is done —
; matching every earlier phase's "no error recovery yet" scope note,
; not an oversight specific to this file.
;
; A SETTABLE CURRENT ATTRIBUTE, since Phase 15: PLOT/LINE/CIRCLE read
; their attribute byte from CURRENT_ATTR (below), not a hardcoded
; constant — core/color.asm's INK/PAPER (Phase 15) modify CURRENT_ATTR
; directly, and nothing here needs to know that file exists. Before
; Phase 15 this was a fixed compile-time constant (DEFAULT_ATTR, still
; the correct *initial* value — white paper, black ink, the classic
; Spectrum power-on default); now it's a REQUIRED runtime
; initialization, exactly like core/print.asm's own PRINT_ROW/PRINT_COL
; convention: whatever ROM INCLUDEs this file must set
; `ld a, DEFAULT_ATTR` / `ld (CURRENT_ATTR), a` at cold start, or
; PLOT/LINE/CIRCLE will draw with whatever garbage happens to be in
; that uninitialized RAM byte. Every ROM in this project that already
; included this file (rom/forth_smoke_p5.asm, rom/forth_smoke_p9.asm,
; rom/forth_boot.asm) was updated to do this and re-verified under real
; Fuse when this change landed — see docs/PROJECT_PLAN.md's Phase 15
; section.
;
; RAM ADDRESS PLANNING — READ BEFORE ADDING MORE SCRATCH HERE:
; CURRENT_ATTR's own address ($87CB) was placed by literally assembling
; every kernel/ module this ROM needs together and inspecting the
; resulting .sym file for a free byte, not guessed — core/interp.asm's
; own header tells the story of a real collision this project already
; had between its own scratch and 2068-Leap's kernel/BASIC sysvars.
; Repeat that check for anything added here later, don't assume a gap
; is empty by inspection alone.
; ============================================================================

    IFNDEF CORE_TS2068_ASM
    DEFINE CORE_TS2068_ASM

DEFAULT_ATTR EQU $38   ; paper 7 (white), ink 0 (black), no bright/flash —
                       ; the classic Spectrum-family power-on default;
                       ; the value CURRENT_ATTR must be initialized to
CURRENT_ATTR EQU $87CB ; 1 byte: the attribute PLOT/LINE/CIRCLE draw
                       ; with — see this file's own header

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
    ld   a, (CURRENT_ATTR)
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
    ld   a, (CURRENT_ATTR)
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
    ld   a, (CURRENT_ATTR)
    ld   (GFX_CIRCLE_ATTR), a
    xor  a
    ld   (GFX_CIRCLE_OVER), a
    call GFX_CIRCLE
    ret

; ============================================================================
; BORDER ( color -- )
; ============================================================================
H_BORDER:
    DW   H_CIRCLE
    DB   6, "B", "O", "R", "D", "E", "R"
W_BORDER:
    call DPOP_HL
    ld   a, l
    call GFX_SET_BORDER
    ret

DICT_LATEST_INIT_P5 EQU H_BORDER   ; head of the dictionary as of Phase
                                    ; 5 (PLOT/LINE/CIRCLE/BORDER) --
                                    ; a historical snapshot; must NOT be
                                    ; repointed at CLS below

; ============================================================================
; CLS ( -- )  Phase 36. Clears the screen -- kernel/graphics's own
; GFX_CLS has been called internally since the very first boot ROM
; (COLD_START, the editor's own line-shrink path, every smoke ROM's own
; setup), but nothing ever exposed it as a word a user could actually
; type, a real and simply-overlooked gap.
;
; REAL BUG FOUND AND FIXED: GFX_CLS alone always resets the whole
; attribute area to a hardcoded ATTR_DEFAULT, ignoring whatever PAPER/
; INK was actually set beforehand -- despite docs/forth_tutorial.md's
; own long-standing claim that "CLS honors the current PAPER". Real
; Sinclair BASIC doesn't work that way either: ts2068rom's own
; BASIC_STMT_CLS calls GFX_CLS, then repaints the attribute area with
; BASIC_COMPUTE_PRINT_ATTR's current ink/paper/bright/flash byte via
; GFX_PAINT_ATTR, then resets the print position to (0,0) -- CLS
; clears the screen, it doesn't reset your chosen colors. Mirrored
; here exactly, just against this project's own CURRENT_ATTR sysvar
; (core/color.asm's INK/PAPER already maintain it) instead of a
; separately-computed byte.
; ============================================================================
H_CLS:
    DW   H_BORDER
    DB   3, "C", "L", "S"
W_CLS:
    call GFX_CLS
    ld   a, (CURRENT_ATTR)
    call GFX_PAINT_ATTR

    IFDEF CORE_PRINT_ASM        ; PRINT_ROW/PRINT_COL only exist once
                                ; core/print.asm is included (a few
                                ; smoke ROMs use CLS without it)
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ENDIF
    ret

DICT_LATEST_INIT_CLS EQU H_CLS   ; head of the dictionary once this
                                  ; file's own word (CLS) is included

    ENDIF
