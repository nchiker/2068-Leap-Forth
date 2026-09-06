; ============================================================================
; rom/forth_smoke_p56.asm — Phase 56 smoke ROM: MODE64_PUTCHAR,
; MODE64_PUTCHAR_XOR, MODE64_SCROLL_TEXT_UP, MODE64_CLEAR_ROW
; (kernel/mode64/mode64.asm's new real-64-column-TEXT primitives)
;
; No Forth interpreter needed for this phase -- these are pure kernel
; routines with no dictionary word wrapping them yet (that's Phase E,
; core/print.asm's mode-aware EMIT). This ROM calls them directly, the
; same "test the kernel routine before any Forth wrapper exists"
; approach rom/forth_smoke_p8b.asm's own MODE64_READ_PIXEL checkpoint
; already established.
;
; FIVE CHECKPOINTS, each verified by comparing real screen bytes
; against the REAL font table's own glyph bytes (via
; GFX_CHAR_TO_FONT_OFFSET) -- no glyph shape is ever hardcoded/guessed
; here, only compared against the same lookup the drawing routines
; themselves use:
;   1. MODE64_PUTCHAR('A', row 5, col 5) -- column 5 is in the Primary
;      Display File; verify the 8 screen bytes at that exact address
;      match 'A''s real glyph bytes.
;   2. MODE64_PUTCHAR('A', row 5, col 40) -- column 40 (>=32) is in the
;      Second Display File; verify the 8 bytes there match too --
;      proves the file-selection half of the addressing, not just the
;      row/column math the Primary-file case alone could pass by luck.
;   3. MODE64_PUTCHAR('B', row 6, col 5 and col 40), then
;      MODE64_SCROLL_TEXT_UP: verify row 5 now shows 'B' (moved up from
;      row 6) and row 4 now shows 'A' (moved up from row 5,
;      checkpoints 1/2's own content) -- in BOTH display files, proving
;      the scroll moves both together, not just one.
;   4. MODE64_PUTCHAR_XOR at row 10, col 20, twice in a row: after the
;      first call the 8 bytes must be the bitwise complement of
;      whatever was there before; after the second call (same
;      position) they must be back to the ORIGINAL bytes exactly --
;      proves the cursor XOR is genuinely self-inverting, not just
;      "looks different."
;   5. Draw into row 15 (both files), then MODE64_CLEAR_ROW(15);
;      spot-check columns 0, 31 (Primary) and 32, 63 (Second, the two
;      file boundaries) all match the space glyph's own real bytes.
;
; Border goes GREEN (4) if all five pass; otherwise it shows the
; failing checkpoint's number.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    DS   $0008 - $, $FF
RST_08: ret
    DS   $0010 - $, $FF
RST_10: ret
    DS   $0018 - $, $FF
RST_18: ret
    DS   $0020 - $, $FF
RST_20: ret
    DS   $0028 - $, $FF
RST_28: ret
    DS   $0030 - $, $FF
RST_30: ret
    DS   $0038 - $, $FF
RST_38:
    ei
    ret
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

COLD_START:
    ld   sp, $FF00
    call MODE64_ON

; ---- checkpoint 1: MODE64_PUTCHAR, Primary Display File (col < 32) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   a, "A"
    ld   b, 5
    ld   c, 5
    call MODE64_PUTCHAR
    ld   a, "A"
    call GFX_CHAR_TO_FONT_OFFSET  ; hl = 'A''s real glyph pointer --
                                  ; MUST run before the address math
                                  ; below: this routine's own header
                                  ; documents that it destroys DE (E
                                  ; holds the character internally
                                  ; throughout its dispatch), which
                                  ; would silently clobber an
                                  ; already-computed expected address
                                  ; if called the other way around --
                                  ; a real bug this checkpoint's own
                                  ; first draft actually had, caught by
                                  ; a direct Fuse register/memory peek,
                                  ; not by inspection
    push hl
    ld   a, 5
    call GFX_ROW_BASE_ADDR      ; hl = row 5's base, Primary-relative
    ld   a, l
    add  a, 5
    ld   l, a
    jr   nc, .cp1_noc
    inc  h
.cp1_noc:
    ex   de, hl                  ; de = expected screen address
    pop  hl                      ; hl = glyph pointer, restored
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

; ---- checkpoint 2: MODE64_PUTCHAR, Second Display File (col >= 32) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   a, "A"
    ld   b, 5
    ld   c, 40
    call MODE64_PUTCHAR
    ld   a, "A"
    call GFX_CHAR_TO_FONT_OFFSET  ; hl = glyph ptr -- before the DE-
                                  ; clobbering address math, same fix
                                  ; as checkpoint 1
    push hl
    ld   a, 5
    call GFX_ROW_BASE_ADDR
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de                  ; hl = row 5's base, Second-file
    ld   a, l
    add  a, 8                    ; col 40 & 31 = 8
    ld   l, a
    jr   nc, .cp2_noc
    inc  h
.cp2_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

; ---- checkpoint 3: MODE64_SCROLL_TEXT_UP moves both display files ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   a, "B"
    ld   b, 6
    ld   c, 5
    call MODE64_PUTCHAR
    ld   a, "B"
    ld   b, 6
    ld   c, 40
    call MODE64_PUTCHAR
    call MODE64_SCROLL_TEXT_UP

    ld   a, "B"
    call GFX_CHAR_TO_FONT_OFFSET  ; hl = glyph ptr first, same fix
    push hl
    ld   a, 5                    ; row 5 should now show 'B' (Primary)
    call GFX_ROW_BASE_ADDR
    ld   a, l
    add  a, 5
    ld   l, a
    jr   nc, .cp3a_noc
    inc  h
.cp3a_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ld   a, "B"
    call GFX_CHAR_TO_FONT_OFFSET
    push hl
    ld   a, 5                    ; row 5 should now show 'B' (Second)
    call GFX_ROW_BASE_ADDR
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
    ld   a, l
    add  a, 8
    ld   l, a
    jr   nc, .cp3b_noc
    inc  h
.cp3b_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ld   a, "A"
    call GFX_CHAR_TO_FONT_OFFSET
    push hl
    ld   a, 4                    ; row 4 should now show 'A' (Primary) --
    call GFX_ROW_BASE_ADDR       ; proves the SHIFT, not just "some B
    ld   a, l                    ; showed up somewhere"
    add  a, 5
    ld   l, a
    jr   nc, .cp3c_noc
    inc  h
.cp3c_noc:
    ex   de, hl
    pop  hl
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

; ---- checkpoint 4: MODE64_PUTCHAR_XOR round trip ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   a, 10
    call GFX_ROW_BASE_ADDR
    ld   a, l
    add  a, 20
    ld   l, a
    jr   nc, .cp4_noc
    inc  h
.cp4_noc:
    ld   (CP4_ADDR), hl           ; stash the address for reuse below
    ld   de, CP4_BEFORE
    ld   b, 8
.cp4_capture:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    ld   a, h
    inc  a
    ld   h, a
    inc  de
    djnz .cp4_capture

    ld   b, 10
    ld   c, 20
    call MODE64_PUTCHAR_XOR
    ld   hl, (CP4_ADDR)
    ld   de, CP4_BEFORE
    ld   b, 8
.cp4_check_xored:
    ld   a, (de)
    cpl                           ; a = NOT(before) -- what the byte
                                  ; should be after ONE xor with $FF
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  hl
    ld   a, h
    inc  a
    ld   h, a
    inc  de
    djnz .cp4_check_xored

    ld   b, 10
    ld   c, 20
    call MODE64_PUTCHAR_XOR       ; second XOR -- must restore original
    ld   hl, (CP4_ADDR)
    ld   de, CP4_BEFORE
    ld   b, 8
.cp4_check_restored:
    ld   a, (de)
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  hl
    ld   a, h
    inc  a
    ld   h, a
    inc  de
    djnz .cp4_check_restored

; ---- checkpoint 5: MODE64_CLEAR_ROW ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   a, "C"
    ld   b, 15
    ld   c, 0
    call MODE64_PUTCHAR
    ld   a, "C"
    ld   b, 15
    ld   c, 63
    call MODE64_PUTCHAR
    ld   b, 15
    call MODE64_CLEAR_ROW

    ld   a, " "
    call GFX_CHAR_TO_FONT_OFFSET  ; hl = space's real glyph pointer --
                                  ; computed ONCE, stashed in memory
                                  ; (not a register) so it survives
                                  ; every GFX_ROW_BASE_ADDR call below
                                  ; unscathed, same DE-clobber fix as
                                  ; every earlier checkpoint
    ld   (SPACE_GLYPH_PTR), hl

    ld   a, 15
    call GFX_ROW_BASE_ADDR        ; col 0 -- Primary file start
    ex   de, hl
    ld   hl, (SPACE_GLYPH_PTR)
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ld   a, 15
    call GFX_ROW_BASE_ADDR        ; col 31 -- Primary file end
    ld   a, l
    add  a, 31
    ld   l, a
    jr   nc, .cp5a_noc
    inc  h
.cp5a_noc:
    ex   de, hl
    ld   hl, (SPACE_GLYPH_PTR)
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ld   a, 15
    call GFX_ROW_BASE_ADDR        ; col 32 -- Second file start
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
    ex   de, hl
    ld   hl, (SPACE_GLYPH_PTR)
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    ld   a, 15
    call GFX_ROW_BASE_ADDR        ; col 63 -- Second file end
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
    ld   a, l
    add  a, 31
    ld   l, a
    jr   nc, .cp5b_noc
    inc  h
.cp5b_noc:
    ex   de, hl
    ld   hl, (SPACE_GLYPH_PTR)
    call COMPARE_GLYPH_AT
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helper: NOT a dictionary word ----
; COMPARE_GLYPH_AT: compares 8 consecutive screen bytes (DE, stride
; 256) against 8 consecutive glyph bytes (HL, stride 1).
; In:  HL = glyph pointer, DE = screen address
; Out: Z set if all 8 bytes match, Z clear (A=1) on the first mismatch
; Destroys: AF, BC, DE, HL
COMPARE_GLYPH_AT:
    ld   b, 8
.loop:
    ld   a, (de)
    cp   (hl)
    jr   nz, .mismatch
    inc  hl
    ld   a, d
    inc  a
    ld   d, a
    djnz .loop
    xor  a
    ret
.mismatch:
    ld   a, 1
    or   a
    ret

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

CHECKPOINT_NUM EQU $8800
CP4_ADDR       EQU $8801   ; 2 bytes
CP4_BEFORE     EQU $8803   ; 8 bytes
SPACE_GLYPH_PTR EQU $880B  ; 2 bytes

; ---- kernel: included here, after the vector table and the self-test
; code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/mode64/mode64.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p56_rom0.bin", $0000, $4000
