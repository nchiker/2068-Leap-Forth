; ============================================================================
; rom/test_blockgfx.asm -- self-test for the block-graphics glyphs (codes 128-143)
;
; GFX_CHAR_TO_FONT_OFFSET builds the glyph of code 128+n in BLOCK_GFX_SCRATCH from the low nibble n.
; The screen format fixes the glyph: the character cell is split into four 4x4 quarters,
;   bit 0 = top-right, bit 1 = top-left, bit 2 = bottom-right, bit 3 = bottom-left,
; a quarter is solid ink when its bit is set and blank when clear, never partial. So rows 0-3 of the
; glyph all equal TOP and rows 4-7 all equal BOTTOM, with
;   TOP    = (n bit 1 ? $F0 : 0) | (n bit 0 ? $0F : 0)
;   BOTTOM = (n bit 3 ? $F0 : 0) | (n bit 2 ? $0F : 0)
; Added in audit step R0 before the routine was rebuilt (O2), so the same ROM passes on the old and the
; new code: it is the oracle for the rebuild. Both orders (0..15, 15..0) are run so a glyph left over in
; the scratch from the previous call cannot pass.
;
; Border GREEN (4) = pass. Failures: 1 = carry set (no glyph), 2 = a top-half row is wrong,
; 3 = a bottom-half row is wrong, 5 = the 16 codes were not all visited.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START

    DS   $0008 - $, $FF
RST_08:
    ret

    DS   $0010 - $, $FF
RST_10:
    ret

    DS   $0018 - $, $FF
RST_18:
    ret

    DS   $0020 - $, $FF
RST_20:
    ret

    DS   $0028 - $, $FF
RST_28:
    ret

    DS   $0030 - $, $FF
RST_30:
    ret

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
    xor  a
    ld   (VISITED), a
    ld   d, 0                        ; D = n, ascending
.up:
    call CHECK_ONE
    inc  d
    ld   a, d
    cp   16
    jr   nz, .up
    ld   d, 15                       ; descending
.down:
    call CHECK_ONE
    ld   a, d
    or   a
    jr   z, .counted
    dec  d
    jr   .down
.counted:
    ld   a, (VISITED)
    cp   32
    ld   a, 5
    jr   nz, FAIL
PASS:
    ld   a, 4
    out  (PORT_ULA), a
    jr   PASS
FAIL:
    out  (PORT_ULA), a
    jr   FAIL

; ---- CHECK_ONE: glyph of code 128+D against the rule above. Keeps D. Falls into FAIL on a mismatch ----
CHECK_ONE:
    push de
    ld   a, d
    or   $80
    call GFX_CHAR_TO_FONT_OFFSET
    pop  de
    ld   a, 1
    jr   c, FAIL
    ; TOP into B, BOTTOM into C
    ld   b, 0
    ld   c, 0
    bit  1, d
    jr   z, .t1
    ld   b, $F0
.t1:
    bit  0, d
    jr   z, .t2
    ld   a, b
    or   $0F
    ld   b, a
.t2:
    bit  3, d
    jr   z, .b1
    ld   c, $F0
.b1:
    bit  2, d
    jr   z, .b2
    ld   a, c
    or   $0F
    ld   c, a
.b2:
    ld   e, 4
.top:
    ld   a, (hl)
    cp   b
    ld   a, 2
    jr   nz, FAIL
    inc  hl
    dec  e
    jr   nz, .top
    ld   e, 4
.bottom:
    ld   a, (hl)
    cp   c
    ld   a, 3
    jr   nz, FAIL
    inc  hl
    dec  e
    jr   nz, .bottom
    ld   a, (VISITED)
    inc  a
    ld   (VISITED), a
    ret

VISITED EQU $87B8                    ; 1 byte of scratch RAM, as the other smoke ROMs' CHECKPOINT_NUM

    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"

    DS   $4000 - $, $FF

    SAVEBIN "test_blockgfx_rom0.bin", $0000, $4000
