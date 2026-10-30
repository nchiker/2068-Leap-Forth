; ============================================================================
; kernel/graphics/graphics.asm — text-mode character output
;
; CURRENT STATUS: assembled into the working ROM and exercised under
; Fuse by the automated graphics and language regression tests. Glyph
; appearance still ultimately requires visual judgment; the addressing
; and drawing paths have executable coverage.
;
; CONFIDENCE LEVELS DIFFER within this file, worth being explicit about:
;   - Screen ADDRESSING (ROW_BASE_TABLE, GFX_PUTCHAR's address math) was
;     verified NUMERICALLY with a Python script before any assembly was
;     written — the standard Spectrum-family screen layout formula was
;     checked against 576 spot-check (row, col, scanline) combinations,
;     not just hand-traced. High confidence.
;   - The FONT DATA (FONT_TABLE) has no equivalent numerical check —
;     there's no formula to verify glyph shapes against, only human
;     judgement. Each glyph was designed deliberately as ASCII art (not
;     recalled from a specific ROM's font from memory, to avoid
;     transcription errors) and visually rendered for self-review before
;     conversion to hex, but this is NOT the same confidence level as
;     the addressing math. Treat glyph shapes as needing YOUR visual
;     confirmation once actually on screen — that's the one part of
;     this file I can't self-verify at all.
;
; Owns: the screen bitmap/attribute addressing scheme, and character
; output (GFX_PUTCHAR, GFX_CLS, GFX_PRINT_STRING, GFX_INVERT_ATTR).
; FONT_TABLE covers space, 0-9, A-Z, a-z, and 23 punctuation characters
; (86 glyphs total: " ! @ # $ % & ' ( ) _ : . , = + - ; / * < > ?) — grown
; as needed rather than up front. The quote character was added once
; PRINT "..." string literals made it a real blocker; most of the rest
; cover kernel/io's confirmed-confidence subset of SYMBOL SHIFT's
; punctuation table (see that module's header — the full real table is
; more complex, some keys give BASIC keyword tokens instead of symbols,
; only what's independently confirmed is implemented on either side).
; / and * were added once basic/'s expression evaluator actually needed
; them for division and multiplication — this project already shipped
; the "character typed correctly but invisible, no glyph for it" bug
; once (the quote character, early on); adding a SYMBOL SHIFT
; punctuation mapping without also adding its glyph would repeat that
; exact mistake, so both are always added together now.
; ============================================================================

    INCLUDE "include/hardware.inc"
    INCLUDE "include/sysvars.inc"

; ---- character grid ----
GFX_ROWS   EQU 24
GFX_COLS   EQU 32
ATTR_DEFAULT EQU $44     ; PAPER 0 (black), INK 4 (green), BRIGHT 1 —
                        ; this project's default attribute, used by
                        ; both GFX_CLS and GFX_CLEAR_ROW; previously a
                        ; bare $38 (PAPER 7 white / INK 0 black, the
                        ; classic Sinclair power-on default) until the
                        ; user asked for a more comfortable color
                        ; scheme — bright green on black, the familiar
                        ; phosphor-terminal look, chosen specifically
                        ; because this project's own border was never
                        ; set away from its own hardware-default black
                        ; (BORDER_DEFAULT below is defined but never
                        ; actually applied by rom/forth_boot.asm), so a
                        ; black PAPER also finally makes the visible
                        ; border and the 32x24 text screen match
                        ; seamlessly instead of the old black-border/
                        ; white-paper mismatch.
ATTR_STATUS_BAR EQU $07   ; PAPER 0 (black), INK 7 (white) — STALE
                          ; relative to the new ATTR_DEFAULT above (it
                          ; was ATTR_DEFAULT's own ink/paper swap back
                          ; when that was $38); left unchanged since
                          ; nothing in this project actually uses this
                          ; constant (confirmed by grep) — inherited
                          ; from 2068-Leap, never adopted here. Verified
                          ; against GFX_ATTR_SWAP's own bit logic
                          ; (ink bits shifted into paper position,
                          ; paper bits shifted into ink position)
                          ; rather than just asserted. Used by basic/'s
                          ; status bar to set the inverted attribute
                          ; directly (GFX_SET_ATTR) instead of clear-
                          ; then-toggle (GFX_CLEAR_ROW + GFX_INVERT_
                          ; ATTR_STATIC), eliminating a briefly-visible
                          ; non-inverted intermediate state that a
                          ; two-step clear-then-toggle sequence can't
                          ; avoid — found from the user reporting a
                          ; smaller, but still-present, flash even
                          ; after the toggle bug itself was fixed

; Status bar branding swatch — three solid-color cells in the status
; bar's reserved right-hand columns, echoing the red/green/blue bars
; under the real TS2068's "PERSONAL COLOR COMPUTER" logo. PAPER-only
; (INK bits left 0/black) since these attributes are applied to blank
; (space) cells — with no set pixels, only PAPER ever shows, so INK is
; irrelevant here. Standard Spectrum-family color numbering: 1=blue,
; 2=red, 4=green.
ATTR_SWATCH_RED   EQU $10   ; PAPER 2 (red),   INK 0
ATTR_SWATCH_GREEN EQU $20   ; PAPER 4 (green), INK 0
ATTR_SWATCH_BLUE  EQU $08   ; PAPER 1 (blue),  INK 0

BORDER_DEFAULT  EQU 7     ; white — matched ATTR_DEFAULT's own PAPER
                          ; color back when that was white ($38); now
                          ; stale relative to ATTR_DEFAULT's new black
                          ; PAPER, but harmless — never actually applied
                          ; anywhere in this project (confirmed by
                          ; grep), only in the inherited 2068-Leap
                          ; BASIC's own cold-boot setup and NEW (both
                          ; real "start fresh" moments there) —
                          ; deliberately NOT applied by GFX_CLS itself,
                          ; since real Sinclair BASIC's CLS clears only
                          ; the text screen and never touches the
                          ; border; folding a border reset into GFX_CLS
                          ; would incorrectly wipe a program's own
                          ; BORDER setting on every ordinary mid-program
                          ; CLS statement, not just at a genuine reset

; ============================================================================
; GFX_CLS
; Clears the screen bitmap to all-off and the attribute area to a
; default (black paper, bright green ink — INK 4, PAPER 0, BRIGHT 1 =
; $44).
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_CLS:
    call GFX_SPRITE_INVALIDATE
    ld   hl, SCREEN_ADDR
    ld   de, SCREEN_ADDR + 1
    ld   bc, 6144 - 1           ; bitmap is 6144 bytes ($4000-$57FF)
    xor  a
    ld   (hl), a
    ldir

    ld   a, ATTR_DEFAULT           ; PAPER 0, INK 4, BRIGHT 1 — falls
                                   ; straight into GFX_PAINT_ATTR below
                                   ; for the actual attribute-area fill,
                                   ; same loop, no ROM-budget cost for
                                   ; duplicating it here
; ============================================================================
; GFX_PAINT_ATTR
; Paints the whole attribute area (all 24 rows x 32 columns) to one
; caller-supplied attribute byte — the bitmap itself is untouched, so
; this is purely a re-color, not a clear. GFX_CLS falls straight through
; into this same code (having just set A = ATTR_DEFAULT) rather than
; duplicating the loop, so GFX_CLS's own contract (always resets to
; white paper/black ink, matching its existing callers throughout this
; project) is unchanged for every caller that only ever calls GFX_CLS;
; this label just gives BASIC_STMT_CLS a way to follow a real GFX_CLS
; with a repaint to whatever CURRENT_INK/CURRENT_PAPER (etc.) actually
; says, without touching GFX_CLS's own behavior.
; In:  A = attribute byte to fill every cell with
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PAINT_ATTR:
    ld   hl, ATTR_ADDR
    ld   de, ATTR_ADDR + 1
    ld   bc, 768 - 1
    ld   (hl), a
    ldir
    ret

; ============================================================================
; GFX_SPRITE_INVALIDATE
; Forget displayed/save-under state before a global screen transformation
; (CLS, mode switch) — the screen no longer shows whatever a SHOWn
; slot's own saved background/position described, so a later SPRITE-
; HIDE must not try to "restore" it. Captured images (SPRITE_SLOT_
; DEFINED) remain defined and may be SPRITE-SHOWn again.
;
; SPRITE_SLOT_MAX/SPRITE_SLOT_SHOWN are core/sprite.asm's own fresh
; 2068-Forth design (this session) — smaller (4 slots, not 8) than the
; inherited 2068-Leap scaffolding this routine originally reset, and
; that design's own SPRITE_DISPLAY_DEPTH z-order counter has no
; equivalent here: each slot restores its own single saved background
; directly, no overlap-ordering stack to unwind.
; In: none
; Out: SPRITE_SLOT_SHOWN[0..SPRITE_SLOT_MAX-1] = 0
; Destroys: AF, B, HL
; ============================================================================
GFX_SPRITE_INVALIDATE:
    xor  a
    ld   hl, SPRITE_SLOT_SHOWN
    ld   b, SPRITE_SLOT_MAX
.loop:
    ld   (hl), a
    inc  hl
    djnz .loop
    ret

; ============================================================================
; GFX_ROW_BASE_ADDR
; Looks up a text row's bitmap base address (scanline 0, column 0) —
; same ROW_BASE_TABLE[row] lookup GFX_PUTCHAR/GFX_CHAR_SETUP already do
; inline, factored out here so GFX_SCROLL_TEXT_UP/_DOWN (via GFX_COPY_
; ROW_BITMAP) don't duplicate it a third time.
; In:  A = row (0-23, caller's responsibility — no bounds check)
; Out: HL = that row's bitmap base address
; Destroys: AF, DE
; ============================================================================
GFX_ROW_BASE_ADDR:
    ld   h, 0
    ld   l, a
    add  hl, hl                    ; row * 2 (2 bytes per table entry)
    ld   de, ROW_BASE_TABLE
    add  hl, de
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl
    ret

; ============================================================================
; GFX_COPY_ROW_BITMAP
; Copies one text row's entire 8-scanline bitmap (256 bytes total) from
; one row to another. Non-linear addressing (see ROW_BASE_TABLE's own
; header) means this can't be a single LDIR — each of the 8 scanlines
; lives 256 bytes apart, so it's 8 separate 32-byte block copies,
; stepping both the source and destination base by 256 (one scanline)
; each time. Attribute memory IS linear ($5800 + row*32 + col), so
; GFX_SCROLL_TEXT_UP/_DOWN move it separately, in one shot, rather than
; needing this routine's own per-scanline approach.
; In:  (GFX_SCROLL_DST_ROW), (GFX_SCROLL_SRC_ROW) already set by the
;      caller
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_COPY_ROW_BITMAP:
    ld   a, (GFX_SCROLL_DST_ROW)
    call GFX_ROW_BASE_ADDR          ; HL = dst row base
    push hl
    ld   a, (GFX_SCROLL_SRC_ROW)
    call GFX_ROW_BASE_ADDR          ; HL = src row base
    pop  de                         ; DE = dst row base
    ld   b, 8                       ; 8 scanlines per text row
.scanline_loop:
    push bc
    push hl
    push de
    ld   bc, 32
    ldir
    pop  de
    pop  hl
    ld   a, h                       ; advance both base addresses by
    inc  a                          ; 256 (one scanline) — restoring
    ld   h, a                       ; the PRE-ldir bases from the stack
    ld   a, d                       ; above, then bumping the high byte,
    inc  a                          ; rather than trusting whatever
    ld   d, a                       ; ldir itself left HL/DE pointing at
    pop  bc
    djnz .scanline_loop
    ret

; ============================================================================
; GFX_SCROLL_TEXT_UP
; Scrolls the 23-row program-listing window (rows 0-22 — row 23 is
; always the separately-drawn status line, never touched here) up by
; exactly one text row: row 1's content becomes row 0's, row 2's
; becomes row 1's, ... row 22's becomes row 21's. Row 22 itself is left
; UNTOUCHED — the caller draws whatever newly-scrolled-into-view
; content belongs there. Moves real screen bytes (bitmap + attributes)
; instead of re-rendering characters, so this is much cheaper than a
; full BASIC_REDRAW_PROGRAM pass for the common "scroll by one line"
; case — see BASIC_REDRAW_PROGRAM's own use of this.
;
; Row-pair copies are processed in ASCENDING destination order (0, 1,
; 2, ...) deliberately: row 1's original content must be read (as the
; source for dst=0) before it's overwritten (as the destination when
; dst=1) — the classic memmove "copy forward when dst < src" rule.
; In:  none
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SCROLL_TEXT_UP:
    call GFX_SPRITE_INVALIDATE
    ld   hl, ATTR_ADDR + 32          ; row 1's attributes (linear memory
    ld   de, ATTR_ADDR               ; — the whole 22-row block moves in
    ld   bc, 22*32                   ; one shot, no per-row loop needed)
    ldir

    xor  a
    ld   (GFX_SCROLL_DST_ROW), a
.row_loop:
    ld   a, (GFX_SCROLL_DST_ROW)
    inc  a
    ld   (GFX_SCROLL_SRC_ROW), a
    call GFX_COPY_ROW_BITMAP
    ld   a, (GFX_SCROLL_DST_ROW)
    inc  a
    ld   (GFX_SCROLL_DST_ROW), a
    cp   22
    jr   c, .row_loop
    ret

; Scroll all 24 program-output rows up, then clear the new bottom row.
; The editor primitive above deliberately protects its status row, so reuse
; it for rows 0-21 and finish the additional row here.
GFX_SCROLL_OUTPUT_UP:
    call GFX_SCROLL_TEXT_UP
    ld   a, 22
    ld   (GFX_SCROLL_DST_ROW), a
    ld   a, 23
    ld   (GFX_SCROLL_SRC_ROW), a
    call GFX_COPY_ROW_BITMAP
    ld   hl, ATTR_ADDR + 23*32
    ld   de, ATTR_ADDR + 22*32
    ld   bc, 32
    ldir
    ld   b, 23
    jp   GFX_CLEAR_ROW

; ============================================================================
; GFX_SET_BORDER
; Sets the screen border colour via the ULA port ($FE) — same
; Spectrum-family hardware convention every other screen routine in
; this file already assumes (see GFX_CLS's attribute-byte layout for
; the sibling INK/PAPER encoding). Only bits 0-2 of the port select
; the border colour; the EAR/MIC bits (used by kernel/storage's tape
; routines) live higher up in the same byte and must NOT be
; disturbed here. REAL BUG FOUND AND FIXED: this used to just mask
; its own colour and write straight to the port, silently zeroing
; bits 3+ every time — the comment promised not to disturb EAR/MIC
; but there was no shadow anywhere for it to preserve them FROM, so
; the promise wasn't actually kept. Now reads PORT_FE_SHADOW
; (updated by both this routine and STORAGE_PULSE), replaces only
; the colour bits, and writes the merged byte back to both the port
; and the shadow.
; In:  A = colour (0-7; only the low 3 bits are used, same 0=black..
;      7=white encoding as every other colour value in this project)
; Out: none
; Destroys: AF, B (B holds the colour bits while the shadow byte is
;      read and merged — checked against all three current call
;      sites, none rely on B surviving, but this must stay accurate
;      for any future caller)
; ============================================================================
GFX_SET_BORDER:
    and  $07                     ; keep only the colour bits — never
                                 ; let stray high bits from the
                                 ; caller reach EAR/MIC
    ld   b, a                    ; stash the new colour bits
    ld   a, (PORT_FE_SHADOW)
    and  $F8                     ; clear the old colour bits, keep
                                 ; everything else (EAR/MIC) as-is
    or   b
    ld   (PORT_FE_SHADOW), a
    out  (PORT_ULA), a
    ret

; ============================================================================
; GFX_CHAR_TO_FONT_OFFSET
; Translates an ASCII character to an absolute pointer to its 8-byte
; glyph bitmap. Despite the name (kept for callers/history), this no
; longer always returns a FONT_TABLE offset — codes 128-143 (block
; graphics) and 144-164 (UDGs) resolve to RAM instead of ROM, so the
; FONT_TABLE base is now folded in here rather than left for the
; caller to add, uniformly across every case (2026-08-22, added
; alongside block-graphics/UDG support).
; In:  A = ASCII character
; Out: carry clear + HL = absolute pointer to the character's 8-byte
;      glyph (FONT_TABLE+offset for ROM glyphs, BLOCK_GFX_SCRATCH for
;      a freshly-generated block-graphics glyph, or UDG_TABLE+offset
;      for a UDG); carry set if the character has no glyph at all
;      (caller's choice what to do — GFX_PUTCHAR treats it as a space)
; Destroys: AF, BC, DE, HL — the punctuation-table scan uses B as its
;      loop counter, so B is NOT preserved; this was documented wrong
;      for a while (claimed only AF/HL) and caused a real bug in
;      GFX_PUTCHAR, which read B (its row parameter) after this call
;      without saving it first — fixed in GFX_PUTCHAR by protecting BC
;      around this call, not by changing what this routine touches.
;      DE is ALSO destroyed (E holds the input character internally
;      throughout the routine's own dispatch, D is used as temporary
;      storage in the block-graphics/UDG paths) — found while writing
;      2068-Forth's own Phase 47 printer support, which needed to call
;      this in a loop and would have silently corrupted its own column
;      counter had it trusted this comment instead of reading the
;      routine's actual body first (core/dict.asm's own "no premature
;      abstraction" convention on comments applies here too: this one
;      was simply wrong, not stale, and had already caused one real
;      bug before this second one was caught on paper, not in Fuse).
; ============================================================================
GFX_CHAR_TO_FONT_OFFSET:
    ld   e, a                      ; E = input char, preserved across
                                   ; the punctuation table scan below
    cp   " "
    jr   z, .is_space
    cp   "0"
    jr   c, .try_punct             ; below '0' and not space: might be
                                   ; punctuation
    cp   "9" + 1
    jr   c, .is_digit
    cp   "A"
    jr   c, .try_punct              ; between '9' and 'A': might be
                                    ; punctuation
    cp   "Z" + 1
    jr   c, .is_upper
    cp   "a"
    jr   c, .try_punct               ; between 'Z' and 'a': might be
                                     ; punctuation
    cp   "z" + 1
    jr   c, .is_lower
    ; falls through toward .try_punct for anything above 'z' too, but
    ; codes 128-164 are intercepted first — block graphics (128-143)
    ; and UDGs (144-164) are never in PUNCT_CHAR_TABLE
    cp   128
    jr   c, .try_punct
    cp   UDG_CODE_BASE                  ; 144
    jr   c, .is_block_graphics
    cp   UDG_CODE_BASE + UDG_COUNT      ; 165
    jr   c, .is_udg
    ; 165+: unmapped, falls through to the punctuation scan same as
    ; any other unrecognized code (.not_found -> render as space)

.try_punct:
    ; Linear scan of PUNCT_CHAR_TABLE (char, index) pairs — cleaner and
    ; less error-prone than a long chain of individual cp/jr z checks
    ; once the punctuation set grew past a handful of characters.
    ld   hl, PUNCT_CHAR_TABLE
    ld   b, PUNCT_CHAR_COUNT
.punct_loop:
    ld   a, (hl)
    cp   e
    jr   z, .punct_found
    inc  hl
    inc  hl                          ; each entry is 2 bytes: char, index
    djnz .punct_loop
    jr   .not_found

.punct_found:
    inc  hl
    ld   a, (hl)                      ; A = this character's font index
    jr   .to_offset

.is_space:
    ld   hl, FONT_TABLE                ; offset 0 -> now an absolute
                                       ; pointer, same as every other
                                       ; case below (see this routine's
                                       ; header)
    or   a
    ret
.is_digit:
    sub  "0"
    add  a, 1                      ; index 0 is space; digits start at 1
    jr   .to_offset
.is_upper:
    sub  "A"
    add  a, 11                      ; index 0=space, 1-10=digits, 11-36=upper
    jr   .to_offset
.is_lower:
    sub  "a"
    add  a, 37                       ; 37-62=lowercase, added alongside
                                    ; upper — see FONT_TABLE's new tail
.to_offset:
    ; N*8 via three doublings. An earlier draft here tried to be clever
    ; with an extra add (aiming for x2,x4,x5,x8) and actually computed
    ; x10 — caught by re-deriving the arithmetic with a script rather
    ; than trusting the inline comment. Three plain doublings is both
    ; simpler and correct.
    ld   l, a
    ld   h, 0
    add  hl, hl                      ; x2
    add  hl, hl                      ; x4
    add  hl, hl                      ; x8
    ld   bc, FONT_TABLE                ; fold the ROM base in here so
    add  hl, bc                        ; every path out of this routine
                                       ; returns an absolute pointer
                                       ; uniformly (see header)
    or   a
    ret

.is_block_graphics:
    ; Codes 128-143. The glyph is built in BLOCK_GFX_SCRATCH from the low
    ; nibble of the code, top half first (bit0 = top-right, bit1 =
    ; top-left, bit2 = bottom-right, bit3 = bottom-left; each quarter is
    ; a solid 4x4 block, filled or blank, never partial). Each half is
    ; four identical rows made from two bits of the code: the low bit
    ; selects the right-hand nibble ($0F), the next bit the left ($F0).
    ; E is shifted down two bits between halves (top = bits 1,0 of the
    ; code, bottom = bits 3,2).
    ; Body from 2068-Leap-C delta D21, written clean-room from the screen
    ; format alone (2068-Leap-C docs/TAPE_CLEANROOM.md); oracle:
    ; rom/test_blockgfx.asm.
    ld   hl, BLOCK_GFX_SCRATCH
    ld   b, 2                        ; two halves
.bg_half:
    ld   a, e
    rra                              ; carry = right quarter
    sbc  a, a                        ; $FF if ink, else $00
    and  $0F
    ld   c, a                        ; right nibble
    ld   a, e
    rra
    rra                              ; carry = left quarter
    sbc  a, a
    and  $F0
    or   c                           ; A = row pattern for this half
    ld   c, 4
.bg_row:
    ld   (hl), a
    inc  hl
    dec  c
    jr   nz, .bg_row
    srl  e
    srl  e                           ; next pair of quarters
    djnz .bg_half
    ld   hl, BLOCK_GFX_SCRATCH
    or   a                           ; carry clear = success
    ret

.is_udg:
    ; Codes 144-164: real hardware stores these as plain RAM, POKE-
    ; defined (PO-T&UDG in the disassembly) — no font data lives in
    ; ROM at all for this range. UDG_TABLE + (code-UDG_CODE_BASE)*8,
    ; same offset math as the ROM FONT_TABLE case above.
    ld   a, e
    sub  UDG_CODE_BASE
    ld   l, a
    ld   h, 0
    add  hl, hl                        ; x2
    add  hl, hl                        ; x4
    add  hl, hl                        ; x8
    ld   bc, UDG_TABLE
    add  hl, bc
    or   a
    ret

.not_found:
    scf
    ret

; ============================================================================
; GFX_CHAR_SETUP (internal — not in kernel_api.inc)
; Shared address computation for GFX_PUTCHAR (and, once, GFX_PUTCHAR_OVER,
; removed in step R0 as dead code) —
; written once here rather than duplicated in both, given how much
; trouble duplicated addressing logic has already caused in this
; project (the GFX_PUTCHAR/GFX_CHAR_TO_FONT_OFFSET row-clobbering bug).
; Screen addressing verified numerically (see file header) —
; ROW_BASE_TABLE gives the bitmap address of (row, col=0, scanline=0);
; column adds 1 per column (verified), and each scanline down within a
; character adds 256 to the address (verified).
;
; Bounds-checks row/col itself now — previously didn't (this exact gap
; is what let `BASIC_PRINT_LINE_HIGHLIGHTED`'s own missing check corrupt
; memory for any LIST line >=32 columns; that call site got its own fix
; at the time, but this shared routine — PRINT's real runtime path, not
; just LIST's redraw — never did, and a >=32-column PRINT string would
; still walk column past 31 here with nothing to catch it). A caller
; that hits this now gets carry set and simply doesn't draw that
; character, rather than writing past the intended row's own memory
; into whatever's adjacent — same "silently clip rather than corrupt"
; precedent GFX_PLOT_CLIPPED already established for pixel graphics.
; In:  A = ASCII character, B = row (0-23), C = column (0-31)
; Out: carry clear + HL = pointer to the glyph's 8 font bytes, DE =
;      screen address of the character cell's top-left pixel; carry
;      set (HL/DE undefined) if row>=24 or col>=32 — caller must not
;      draw in that case
; Destroys: AF, BC
; ============================================================================
GFX_CHAR_SETUP:
    ld   d, a                      ; stash the character — A is about
                                   ; to be scratch for the bounds check
    ld   a, b
    cp   24
    jr   nc, .out_of_range
    ld   a, c
    cp   32
    jr   nc, .out_of_range
    ld   a, d                      ; restore the character
    push bc                        ; preserve row/col — GFX_CHAR_TO_
                                   ; FONT_OFFSET's punctuation-table
                                   ; scan uses B as its own loop counter
                                   ; internally, which clobbered the row
                                   ; parameter for any punctuation
                                   ; character before this was fixed —
                                   ; see docs/programmers_reference.md's
                                   ; kernel/graphics "Bugs caught" entry
    call GFX_CHAR_TO_FONT_OFFSET
    jr   nc, .have_offset
    ld   hl, FONT_TABLE             ; unmapped character -> render as
                                    ; space (index 0, now an absolute
                                    ; pointer like every other case —
                                    ; see GFX_CHAR_TO_FONT_OFFSET's
                                    ; header, 2026-08-22)
.have_offset:
    pop  bc                          ; restore row/col
    push hl                            ; save glyph pointer

    ; row_base = ROW_BASE_TABLE[B] (2 bytes per entry)
    ld   a, b
    call GFX_ROW_BASE_ADDR
    ex   de, hl                       ; DE = row_base
    ld   a, c
    add  a, e
    ld   e, a
    jr   nc, .no_carry
    inc  d
.no_carry:                             ; DE = row_base + column

    pop  hl                                ; HL = pointer to this
                                          ; glyph's 8 bytes — already
                                          ; absolute (GFX_CHAR_TO_FONT_
                                          ; OFFSET folds in FONT_TABLE/
                                          ; UDG_TABLE/BLOCK_GFX_SCRATCH
                                          ; itself now, 2026-08-22)
    or   a                                ; explicitly clear carry —
                                          ; success
    ret

.out_of_range:
    scf
    ret

; ============================================================================
; GFX_PUTCHAR
; Plots one character at a given character-grid position.
; In:  A = ASCII character, B = row (0-23), C = column (0-31)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PUTCHAR:
    call GFX_CHAR_SETUP
    ret  c                                 ; out of range — GFX_CHAR_
                                          ; SETUP's own bounds check;
                                          ; silently don't draw rather
                                          ; than write past the
                                          ; intended row's memory
    ld   b, 8                              ; 8 scanlines
.scanline_loop:
    ld   a, (hl)                            ; A = this scanline's font byte
    ex   de, hl                              ; HL = screen address, DE = font ptr
    ld   (hl), a                              ; write font byte to screen
    inc  h                                     ; screen address += 256 (next
                                              ; scanline — verified this is
                                              ; exactly +256, see file header)
    ex   de, hl                                ; HL = font ptr, DE = screen
                                              ; address (advanced)
    inc  hl                                    ; advance font ptr to next byte
    djnz .scanline_loop
    ret

; ============================================================================
; GFX_PRINT_STRING
; Prints a null-terminated string starting at a character-grid position,
; advancing one column per character. Does not wrap at end of line or
; scroll — caller's responsibility to stay in bounds (TODO for a real
; PRINT statement implementation later).
; In:  HL = pointer to null-terminated string, B = row, C = column
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PRINT_STRING:
.loop:
    ld   a, (hl)
    or   a
    ret  z
    push hl
    push bc                  ; GFX_PUTCHAR destroys BC entirely (see its
                             ; own header) — without saving it here, the
                             ; row in B would be garbage after the first
                             ; character, corrupting every one after it.
                             ; Caught by checking GFX_PUTCHAR's contract
                             ; against what this loop assumed, not by
                             ; running it.
    call GFX_PUTCHAR
    pop  bc
    pop  hl
    inc  hl
    inc  c
    jr   .loop

; ============================================================================
; GFX_ATTR_SWAP (internal — not in kernel_api.inc)
; Address computation and ink/paper bit-swap for GFX_INVERT_ATTR,
; split out as its own routine rather than inlined, given how much
; trouble duplicated addressing logic has already caused in this
; project. The bit-swap instruction
; sequence was verified numerically against all 256 possible attribute
; byte values before being trusted — see docs/programmers_reference.md's
; kernel/graphics section.
;
; REAL BUG FOUND AND FIXED (word-wrap cursor investigation): this had
; no bounds check at all, unlike GFX_SET_ATTR's own row*32+col address
; computation (see that routine's own comment — it already documents
; this exact class of gap). EDITOR_WRAP_OFFSET_TO_ROWCOL (kernel/
; editor) legitimately returns column 32 — one past the valid 0-31
; range — whenever the cursor sits exactly at the end of a full 32-
; character wrapped row (a real, ordinary case, not a rare edge
; condition: it happens on every line whose content is ever an exact
; multiple of 32 chars at the cursor's position). Column 32 fed
; straight into row*32+col addressing lands exactly on (row+1,
; column 0) instead — one cell into the START of the next physical
; screen row, silently corrupting whatever's shown there. Traced from
; a real debug.bin dump (word-wrap "phantom cursor block" report):
; row+1's bitmap was blank (correctly cleared) but its column-0
; attribute byte was stuck inverted — exactly what an out-of-range
; write here produces, and exactly why it persisted even after the
; row's own leftover-row cleanup ran earlier in the same redraw pass
; (this call happens AFTER that cleanup, re-dirtying the cell it had
; just cleared). Fixed with the same bounds check GFX_SET_ATTR already
; has, returning early with carry SET on out-of-range — the caller
; below now checks `ret c` immediately after this call, before doing
; anything else, so an out-of-range request is a clean no-op instead
; of a silent corruption, matching this project's now-consistent "clip
; rather than corrupt" answer to this class of bug.
; In:  B = row (0-23), C = column (0-31)
; Out: HL = address of the attribute byte, A = swapped ink/paper with
;      FLASH/BRIGHT preserved unchanged (caller decides whether to
;      force FLASH on before writing it back). Carry SET and nothing
;      else valid if B/C were out of range — caller must check this
;      before using HL/A.
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_ATTR_SWAP:
    call GFX_CELL_ATTR_ADDR
    ret  c

    ld   a, (hl)
    ld   b, a                     ; B = original attribute byte

    and  %00000111                 ; A = ink bits (low position)
    rlca
    rlca
    rlca                             ; shift into paper's bit position
    ld   c, a                         ; C = ink bits, now in paper position

    ld   a, b
    and  %00111000                     ; A = paper bits
    rrca
    rrca
    rrca                                 ; shift into ink's bit position
    or   c                                ; combine with the shifted ink
    ld   c, a                              ; C = swapped ink/paper (bits 5-0)

    ld   a, b
    and  %11000000                          ; A = FLASH/BRIGHT, unchanged
    or   c                                    ; A = swapped attribute,
                                             ; FLASH/BRIGHT as they were
    or   a                                    ; explicit carry clear —
                                             ; the last op above (or) is
                                             ; already guaranteed to
                                             ; clear carry, but spelled
                                             ; out for anyone reading
                                             ; this contract without
                                             ; re-deriving it
    ret

; ============================================================================
; GFX_INVERT_ATTR
; Swaps ink and paper in the attribute byte at one character cell AND
; sets the hardware FLASH bit — the ULA itself then auto-blinks that
; cell between inverted and normal colors, ~1.5Hz, entirely in hardware.
; No interrupt or timer code needed on our end (kernel/interrupt doesn't
; exist yet, but this doesn't need it) — offloading blink timing to the
; ULA is the standard Spectrum-family way to do this. Used as the
; editor's cursor indicator specifically. (A GFX_INVERT_ATTR_STATIC
; sibling once existed for a non-blinking static highlight — inherited
; from 2068-Leap's status-bar use, which 2068-Forth has no equivalent
; of; removed as dead code, never called here. The address/swap logic
; still lives in its own GFX_ATTR_SWAP below rather than inlined here,
; from when the two shared it.)
; In:  B = row (0-23), C = column (0-31)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_INVERT_ATTR:
    call GFX_ATTR_SWAP
    ret  c                                    ; out of range — GFX_ATTR_
                                             ; SWAP's own bounds check
                                             ; already fired; nothing to
                                             ; write, HL/A aren't valid
    or   %10000000                            ; force FLASH on — the ULA
                                             ; hardware itself blinks any
                                             ; cell with this bit set,
                                             ; ~1.5Hz, entirely in
                                             ; hardware — no interrupt or
                                             ; timer code needed on our
                                             ; end at all. Combined with
                                             ; the ink/paper swap above,
                                             ; this alternates between
                                             ; inverted and normal colors
                                             ; automatically.
    ld   (hl), a
    ret

; ============================================================================
; GFX_SET_ATTR
; Sets the attribute byte at one character cell to a specific value
; outright — unlike GFX_INVERT_ATTR, which swaps ink/paper relative to
; whatever's already there, this replaces it.
; Built for red-highlighted error lines (basic/'s
; BASIC_REDRAW_PROGRAM), but deliberately general — any caller that
; needs a specific, known color at a specific cell can use this rather
; than reasoning about what to swap from.
;
; Duplicates the same small address-computation sequence
; GFX_ATTR_SWAP already has (row*32+col+ATTR_ADDR), rather than
; refactoring that already-working routine to share it — the
; computation is short enough (5 shifts, two adds) that the
; duplication is cheap, and this project's established preference is
; to leave working, tested code alone rather than touch it for a
; small amount of shared logic.
; In:  A = new attribute byte, B = row (0-23), C = column (0-31)
; Out: none
; Destroys: AF, BC, DE, HL
;
; Bounds-checks row/col itself now — same gap GFX_CHAR_SETUP had and
; got fixed for (see that routine's own comment): nothing stopped a
; caller from passing an out-of-range column here, and unlike the
; bitmap write, there was no separate fix covering this path. Found
; via a real, reproducible case: an earlier BASIC-attribute-printing
; routine (since removed as dead code — see this file's own recent
; history) called this unconditionally for every character of a
; string, including ones GFX_PUTCHAR correctly skips once GFX_CHAR_
; SETUP's own bounds check kicks in past column 31 — so a too-long
; PRINT string's attribute-
; painting kept walking past column 31 even after the bitmap fix
; landed, and since attribute memory is a flat row*32+col array,
; walking col past 31 spills into the NEXT row's attribute bytes,
; silently recoloring cells that belong to a completely different
; line. Verified in Python before writing this fix: a 31-character
; string starting at column 20 lands its overflow at row+1, columns
; 0-18 — a real, traceable corruption, not a hypothetical one.
; Silently does nothing on out-of-range, matching this project's now-
; consistent "clip rather than corrupt" answer to this exact class of
; bug (GFX_PLOT_CLIPPED, GFX_CHAR_SETUP) — no callers currently check
; a return status from this routine, so a silent no-op needs no
; changes anywhere else, unlike GFX_CHAR_SETUP's carry-flag fix.
; ============================================================================
GFX_SET_ATTR:
    push af
    call GFX_CELL_ATTR_ADDR
    jr   c, .discard_attr
    pop  af
    ld   (hl), a
    ret
.discard_attr:
    pop  af
    ret

; ============================================================================
; GFX_SET_MODE
; Switches between Normal and High Resolution Graphics video modes —
; MODE's mechanism. Real port $FF write, done safely: $FF is a shared,
; multi-function register (see hardware.inc's PORT_SCLD comment for
; the full bit layout), so this always reads PORT_FF_SHADOW, replaces
; only the video-mode bits (0-2), and writes the merged byte back to
; both the shadow and the port — same established pattern as GFX_SET_
; BORDER already uses for port $FE, adopted here from the start rather
; than repeating the bug that pattern exists to prevent (an earlier
; version of GFX_SET_BORDER had no shadow and silently zeroed bits it
; didn't mean to touch).
;
; Entering High Resolution Graphics mode clears its attribute region
; (SECOND_DISPLAY_ADDR, 6144 bytes) to ATTR_DEFAULT first — that
; memory has never been written by anything in this ROM before (real
; hardware-topology consequence of the RAM migration: this region is
; now genuinely unused by anything except this mode, not just
; "probably zero"), so its content is whatever was there at power-on,
; not necessarily zero. Left uninitialized, the first real pixels
; drawn there would render with an unpredictable — possibly identical
; ink/paper — color. Clearing to ATTR_DEFAULT (PAPER 7/INK 0, the same
; default GFX_CLS already uses) rather than to raw zero deliberately
; avoids repeating the exact "invisible white-on-white" class of
; confusion a real test program already hit once with INK/PAPER (see
; docs/programmers_reference.md's Tier-2 session writeup) — zero would
; decode as PAPER 0/INK 0 here, black-on-black, same trap.
; In:  A = mode (0 = Normal, 1 = High Resolution Graphics — this
;      project's own friendly numbering, NOT the raw port $FF value;
;      caller (BASIC_STMT_MODE) validates this is 0 or 1 first)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
; ============================================================================
; GFX_SET_MODE
; Switches video mode via port $FF (PORT_SCLD) — 0 (Normal) or 1 (High
; Resolution Graphics). Mode 2 (64-Column) was removed at step M6
; (docs/V2/MODE6_REMOVAL_SPEC.md); the mode value 2 is not used.
; In:  A = mode (0 or 1 — BASIC_STMT_MODE validates this before
;      calling)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_SET_MODE:
    push af
    call GFX_SPRITE_INVALIDATE
    pop  af
    ld   (GFX_MODE), a
    cp   1
    jr   z, .highres

    ; Normal (or any other value — BASIC_STMT_MODE validates 0-1, so
    ; this path is really just "0"): video byte = 0, bits 0-2 clear
    ld   a, (PORT_FF_SHADOW)
    and  %11111000
    jr   .write_port

.highres:
    ld   a, (PORT_FF_SHADOW)
    and  %11111000                 ; clear bits 0-2, keep 3-7 (ink/
                                   ; paper select, INTEN, EXROM —
                                   ; none of them this project's to
                                   ; disturb)
    or   2

.write_port:
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   a, (GFX_MODE)
    cp   1
    jr   z, .clear_highres
    ret                              ; Normal mode needs no memory
                                    ; initialization — the primary
                                    ; screen is already maintained by
                                    ; every existing routine

.clear_highres:
    ; clear the High Resolution Graphics attribute region to
    ; ATTR_DEFAULT
    ld   hl, SECOND_DISPLAY_ADDR
    ld   de, SECOND_DISPLAY_ADDR + 1
    ld   bc, 6144 - 1
    ld   a, ATTR_DEFAULT
    ld   (hl), a
    ldir
    ret

; ============================================================================
; GFX_CLEAR_ROW
; Clears one character row (all 32 columns) — bitmap AND attribute —
; back to blank/default, without touching any other row. Built for the
; screen-flicker fix: redrawing the whole screen on every keystroke
; (GFX_CLS + full re-render) is the main source of visible flicker;
; clearing just the one row that actually changed is the first piece
; needed to avoid that.
;
; Reuses GFX_PUTCHAR (a space character, for the bitmap) and
; GFX_SET_ATTR (for the attribute), rather than reimplementing the
; Spectrum-family interleaved screen addressing from scratch — both
; are already proven, tested primitives, and a character row isn't
; contiguous in bitmap memory (it's 8 scanlines spread across the
; standard third-of-screen interleaving), so hand-rolling this
; addressing again here would just be duplicating logic that already
; exists and already works.
;
; Both GFX_PUTCHAR and GFX_SET_ATTR destroy B/C (row/column) per their
; own documented contracts, so each is wrapped in its own push/pop —
; this project's most recurring mistake is assuming a register
; survives a call without checking its "Destroys:" line first.
; In:  B = row (0-23)
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_CLEAR_ROW:
    ld   c, 0
.loop:
    push bc
    ld   a, " "
    call GFX_PUTCHAR
    pop  bc

    push bc
    ld   a, ATTR_DEFAULT
    call GFX_SET_ATTR
    pop  bc

    inc  c
    ld   a, c
    cp   GFX_COLS
    jr   c, .loop
    ret

; ============================================================================
; Pixel graphics: GFX_PIXEL_ADDR_SETUP / GFX_WRITE_PIXEL / GFX_READ_PIXEL /
; GFX_LINE
;
; Screen addressing verified two independent ways before any Z80 was
; written: (1) this file's own already-tested ROW_BASE_TABLE plus a
; row/col/scanline decomposition, and (2) the canonical, independently-
; known ZX Spectrum-family screen address formula
; ($4000 | (y&$C0)<<5 | (y&$07)<<8 | (y&$38)<<2 | x>>3). Checked against
; all 49152 (x,y) pixel positions in the 256x192 space, zero mismatches
; between the two methods, and confirmed every resulting address stays
; within the real 6144-byte bitmap and 768-byte attribute ranges.
;
; PLOT also sets the covering 8x8 attribute cell to the current INK/
; PAPER/FLASH/INVERSE (via GFX_SET_ATTR, called from GFX_WRITE_PIXEL) —
; this is real Sinclair-family hardware behavior (attribute clash is the
; hardware, not a choice this ROM makes), not something invented here.
; ============================================================================

; ============================================================================
; GFX_PIXEL_ADDR_SETUP (internal — not in kernel_api.inc)
; Shared address computation for GFX_WRITE_PIXEL and GFX_READ_PIXEL —
; written once here rather than duplicated in both, same reasoning as
; GFX_CHAR_SETUP/GFX_ATTR_SWAP above: duplicated addressing logic is this
; project's single most common source of real bugs.
; In:  B = x (0-255), C = y (0-191, caller's responsibility to clamp —
;      an out-of-range y indexes past ROW_BASE_TABLE)
; Out: HL = bitmap byte address, A = bit mask (bit7 = leftmost pixel in
;      the byte, matching this file's font glyph convention); also
;      leaves GFX_PIXEL_ROW/GFX_PIXEL_COL set, for a caller that also
;      needs the attribute-cell address
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PIXEL_ADDR_SETUP:
    ld   a, c
    and  %00000111                 ; scanline = y & 7
    ld   (GFX_PIXEL_SCANLINE), a

    ld   a, c
    rrca
    rrca
    rrca
    and  %00011111                 ; char_row = y >> 3 (three RRCAs
                                   ; rotate the low 3 bits into the top
                                   ; of the byte; the mask discards
                                   ; them, leaving a clean 0-23)
    ld   (GFX_PIXEL_ROW), a

    ld   a, b
    and  %00000111                 ; bit_in_byte = x & 7
    ld   e, a
    ld   d, 0
    ld   hl, BIT_MASK_TABLE
    add  hl, de
    ld   a, (hl)
    ld   (GFX_PIXEL_MASK), a

    ld   a, b
    rrca
    rrca
    rrca
    and  %00011111                 ; col = x >> 3, same trick as row
    ld   (GFX_PIXEL_COL), a

    ; bitmap address = ROW_BASE_TABLE[char_row] + col; scanline adds
    ; directly to the high byte (each scanline down = +256, verified —
    ; see this file's header and GFX_CHAR_SETUP's own comment)
    ld   a, (GFX_PIXEL_ROW)
    call GFX_ROW_BASE_ADDR
    ex   de, hl                   ; DE = ROW_BASE_TABLE[char_row]
    ld   a, (GFX_PIXEL_COL)
    add  a, e
    ld   e, a
    jr   nc, .no_col_carry
    inc  d
.no_col_carry:
    ld   a, (GFX_PIXEL_SCANLINE)
    add  a, d
    ld   d, a                      ; DE = final bitmap byte address
    ld   h, d
    ld   l, e
    ld   a, (GFX_PIXEL_MASK)
    ret

; ============================================================================
; GFX_WRITE_PIXEL -- set (OVER 0) or XOR (OVER 1) one pixel and colour it: Normal mode its 8x8 cell, HIRES
; (8x1 colour) its own attribute byte at the bitmap byte + $2000, where the SCLD reads it. y >= 192 draws nothing.
; In:  B = x (0-255), C = y, A = attribute byte, D = OVER flag
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_WRITE_PIXEL:
    ld   (GFX_PIXEL_ATTR), a
    ld   a, c
    cp   192
    ret  nc                        ; below the screen: nothing
    ld   a, d
    ld   (GFX_PIXEL_OVER), a

    call GFX_PIXEL_ADDR_SETUP      ; HL = bitmap byte address, A = mask;
                                   ; GFX_PIXEL_ROW/COL also now set
    ld   b, a                      ; B = mask — x/y (the original B/C)
                                   ; are no longer needed past this point
    ld   a, (GFX_PIXEL_OVER)
    or   a
    jr   z, .plot_set
    ld   a, (hl)
    xor  b
    jr   .plot_write
.plot_set:
    ld   a, (hl)
    or   b
.plot_write:
    ld   (hl), a

    ; colour it: Normal mode its 8x8 cell, HIRES its own 8x1 attribute byte
    ld   a, (GFX_MODE)
    or   a
    jr   nz, .ext_attr

    ld   a, (GFX_PIXEL_ROW)
    ld   b, a
    ld   a, (GFX_PIXEL_COL)
    ld   c, a
    ld   a, (GFX_PIXEL_ATTR)
    jp GFX_SET_ATTR

.ext_attr:
    ld   a, h
    add  a, $20
    ld   h, a                      ; HL = the bitmap byte + $2000: its 8x1 attribute
    ld   a, (GFX_PIXEL_ATTR)
    ld   (hl), a
    ret

; ============================================================================
; GFX_LINE
; Draws a line between two points via Bresenham's algorithm — integer
; only, matching this project's pure-integer BASIC. Absolute coordinates
; for BOTH endpoints (QL SuperBASIC style), deliberately not classic
; Sinclair BASIC's relative-only DRAW — no "current position" to track
; before drawing the next segment.
;
; The exact planned register-level arithmetic (byte-sized dx/dy
; magnitudes, a signed 16-bit error term with truncating add, MATH_
; COMPARE16-style three-way branch tests) was verified via Python
; simulation against a textbook reference Bresenham implementation
; before any Z80 was written: 512 lines (every degenerate/edge case —
; a single point, pure horizontal, pure vertical, both screen corners —
; plus 500 random endpoint pairs across the full 256x192 space), zero
; mismatches.
;
; Takes all six of its inputs from memory, not registers — GFX_LINE_X0/
; Y0/X1/Y1/ATTR/OVER — there are more live values here than survive a
; loop that itself calls GFX_WRITE_PIXEL and MATH_COMPARE16 (both
; destroy registers freely per their own contracts) every iteration.
; Same "value that must survive a destructive call lives in memory"
; reasoning as DELETE_START/DELETE_END and IF_SCAN_POS elsewhere in this
; project, just with more values in play. BASIC_STMT_LINE fills these in
; directly before calling — see sysvars.inc's own comment on this block.
; In:  GFX_LINE_X0/Y0/X1/Y1/ATTR/OVER, all pre-set by the caller
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_LINE:
    ; ---- dx = abs(x1-x0), sx = sign ----
    ld   a, (GFX_LINE_X1)
    ld   b, a
    ld   a, (GFX_LINE_X0)
    ld   c, a
    sub  b                        ; A = x0 - x1; carry set means x0 < x1
    jr   nc, .x0_ge_x1
    ld   a, b
    sub  c                        ; A = x1 - x0
    ld   (GFX_LINE_DX), a
    ld   a, 1
    ld   (GFX_LINE_SX), a
    jr   .dx_done
.x0_ge_x1:
    ld   (GFX_LINE_DX), a         ; A already = x0 - x1, from the SUB
                                  ; above
    ld   a, $FF                   ; -1 (two's complement)
    ld   (GFX_LINE_SX), a
.dx_done:

    ; ---- dy_abs = abs(y1-y0), sy = sign — same shape as dx/sx above ----
    ld   a, (GFX_LINE_Y1)
    ld   b, a
    ld   a, (GFX_LINE_Y0)
    ld   c, a
    sub  b
    jr   nc, .y0_ge_y1
    ld   a, b
    sub  c
    ld   (GFX_LINE_DY_ABS), a
    ld   a, 1
    ld   (GFX_LINE_SY), a
    jr   .dy_done
.y0_ge_y1:
    ld   (GFX_LINE_DY_ABS), a
    ld   a, $FF
    ld   (GFX_LINE_SY), a
.dy_done:

    ; ---- err = dx - dy_abs (signed 16-bit; dx and dy_abs are always
    ; non-negative bytes, zero-extended here, so a plain 16-bit
    ; subtract is exact — no separate negation needed for this one) ----
    ld   a, (GFX_LINE_DX)
    ld   l, a
    ld   h, 0
    ld   a, (GFX_LINE_DY_ABS)
    ld   e, a
    ld   d, 0
    or   a
    sbc  hl, de
    ld   (GFX_LINE_ERR), hl

.loop:
    ld   a, (GFX_LINE_X0)
    ld   b, a
    ld   a, (GFX_LINE_Y0)
    ld   c, a
    ld   a, (GFX_LINE_OVER)
    ld   d, a
    ld   a, (GFX_LINE_ATTR)
    call GFX_WRITE_PIXEL

    ; ---- termination: current point == end point ----
    ld   a, (GFX_LINE_X0)
    ld   b, a
    ld   a, (GFX_LINE_X1)
    cp   b
    jr   nz, .not_done
    ld   a, (GFX_LINE_Y0)
    ld   b, a
    ld   a, (GFX_LINE_Y1)
    cp   b
    jr   nz, .not_done
    ret
.not_done:

    ; ---- e2 = err + err (16-bit, truncating add — same operation as
    ; MATH_ADD16's own body, done inline here to avoid a CALL inside
    ; this already CALL-heavy per-pixel loop) — saved to memory since
    ; BOTH branch decisions below need it, and it must survive the
    ; first MATH_COMPARE16 call (which destroys HL) to reach the second
    ld   hl, (GFX_LINE_ERR)
    add  hl, hl
    ld   (GFX_LINE_E2), hl

    ; ---- if e2 >= -dy_abs: err += -dy_abs; x0 += sx ----
    ld   a, (GFX_LINE_DY_ABS)
    ld   l, a
    ld   h, 0
    call MATH_NEGATE16             ; HL = -dy_abs
    ex   de, hl                    ; DE = -dy_abs, preserved across the
                                   ; compare below (MATH_COMPARE16 never
                                   ; writes DE, only reads it)
    ld   hl, (GFX_LINE_E2)
    call MATH_COMPARE16            ; A: 0 if equal, 1 if e2>DE, $FF if
                                   ; e2<DE
    cp   $FF
    jr   z, .skip_x_step           ; e2 < -dy_abs -> condition false
    ld   hl, (GFX_LINE_ERR)
    add  hl, de                    ; DE still = -dy_abs
    ld   (GFX_LINE_ERR), hl
    ld   a, (GFX_LINE_X0)
    ld   b, a
    ld   a, (GFX_LINE_SX)
    add  a, b
    ld   (GFX_LINE_X0), a
.skip_x_step:

    ; ---- if e2 <= dx: err += dx; y0 += sy ----
    ld   a, (GFX_LINE_DX)
    ld   e, a
    ld   d, 0
    ld   hl, (GFX_LINE_E2)
    call MATH_COMPARE16             ; A: 0 if equal, 1 if e2>dx, $FF if
                                    ; e2<dx
    cp   1
    jr   z, .skip_y_step            ; e2 > dx -> condition false
    ld   hl, (GFX_LINE_ERR)
    ld   a, (GFX_LINE_DX)
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   (GFX_LINE_ERR), hl
    ld   a, (GFX_LINE_Y0)
    ld   b, a
    ld   a, (GFX_LINE_SY)
    add  a, b
    ld   (GFX_LINE_Y0), a
.skip_y_step:

    jp   .loop                     ; JP, not JR: tools/
                                    ; check_z80_opcodes.py flagged this
                                    ; displacement at -126, only 2 bytes
                                    ; of real margin before JR's -128
                                    ; hard limit -- confirmed directly
                                    ; from the assembled .lst, not just
                                    ; the tool's own estimate

; FILL and CIRCLE no longer live here (step O15): their code is FILL_IMPL
; and CIRCLE_IMPL in rom/graphics_exrom.asm (chunk 5), reached through the Home
; words in core/shapes.asm. GFX_READ_PIXEL is kernel/graphics/readpixel.asm.

BIT_MASK_TABLE:
    DB   %10000000, %01000000, %00100000, %00010000
    DB   %00001000, %00000100, %00000010, %00000001

; ---- screen-row base addresses, computed and verified numerically
; (see file header) rather than derived by hand from the bit-shuffle
; formula ----
; ---- punctuation character -> font index lookup, used by
; GFX_CHAR_TO_FONT_OFFSET's table scan. Only the double-quote character
; needs single-quote delimiters here (to avoid self-conflict); every
; other character, including the apostrophe, safely uses double-quote
; delimiters instead — mirrors the convention already proven working
; for the standalone quote check this replaced. ----
PUNCT_CHAR_TABLE:
    DB   '"', 63
    DB   "!", 64
    DB   "@", 65
    DB   "#", 66
    DB   "$", 67
    DB   "%", 68
    DB   "&", 69
    DB   "'", 70
    DB   "(", 71
    DB   ")", 72
    DB   "_", 73
    DB   ":", 74
    DB   ".", 75
    DB   ",", 76
    DB   "=", 77
    DB   "+", 78
    DB   "-", 79
    DB   ";", 80
    DB   "/", 81
    DB   "*", 82
    DB   "<", 83
    DB   ">", 84
    DB   "?", 85
PUNCT_CHAR_COUNT EQU 23

; Block-graphics (128-143) and UDG (144-164) character-code ranges —
; see GFX_CHAR_TO_FONT_OFFSET's .is_block_graphics/.is_udg. UDG_COUNT
; itself lives in include/sysvars.inc alongside UDG_TABLE (it sizes
; that RAM block, not just this code-range check); UDG_CODE_BASE is
; purely a character-code constant, so it stays here with the rest of
; this file's character-range logic instead.
UDG_CODE_BASE EQU 144

ROW_BASE_TABLE:
    DW   $4000, $4020, $4040, $4060, $4080, $40A0, $40C0, $40E0
    DW   $4800, $4820, $4840, $4860, $4880, $48A0, $48C0, $48E0
    DW   $5000, $5020, $5040, $5060, $5080, $50A0, $50C0, $50E0

    IFNDEF FONT_PLACED_LATER
    INCLUDE "kernel/graphics/font.asm"   ; the font (rom/forth_boot.asm places it after kernel/storage)
    ENDIF

; ============================================================================
; GFX_CELL_ATTR_ADDR
; Row/col -> attribute byte address. Shared by GFX_ATTR_SWAP, GFX_SET_ATTR,
; and the sprite paths so the bounds and address formula have one owner.
; In:  B = row (0-23), C = col (0-31)
; Out: carry clear + HL = attribute byte address; carry set if out of range
; Destroys: AF, DE
; ============================================================================
GFX_CELL_ATTR_ADDR:
    ld   a, b
    cp   24
    jr   nc, .out_of_range
    ld   a, c
    cp   32
    jr   nc, .out_of_range
    ld   h, 0
    ld   l, b
    add  hl, hl                      ; x2
    add  hl, hl                      ; x4
    add  hl, hl                      ; x8
    add  hl, hl                      ; x16
    add  hl, hl                      ; x32 -> row*32
    ld   de, ATTR_ADDR
    add  hl, de
    ld   d, 0
    ld   e, c
    add  hl, de                       ; HL = ATTR_ADDR + row*32 + col
    ret
.out_of_range:
    scf
    ret

