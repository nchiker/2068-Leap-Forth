; ============================================================================
; rom/forth_smoke_p48.asm — Phase 48 smoke ROM: ULAPLUS, PALETTE
;
; NOT a border-color pass/fail smoke ROM like every other phase — this
; is a VISUAL test, matching the project's own established convention
; for color/palette features (Phase 8's PALETTE64 smoke ROM, which
; also hangs at a single final state for a screenshot rather than
; checking a register). There is no register-level way to confirm a
; palette swap actually changed what the hardware displays.
;
; WHAT IT DOES: draws a filled circle using INK 2 (the standard ULA
; palette's own red, already well-established by every earlier
; CIRCLE-drawing smoke ROM in this project, e.g. Phase 17's own).
; Then, WITHOUT EVER TOUCHING THAT CIRCLE'S OWN ATTRIBUTE BYTES AGAIN,
; reprograms palette register 2 to $FC (252 = bright yellow-ish, per
; this project's own GGGRRRBB documentation — see core/ulaplus.asm's
; own header) and enables ULAPLUS. Hangs forever with the border
; yellow (6).
;
; WHAT A CORRECT SCREENSHOT SHOULD SHOW: the SAME circle, never
; redrawn, now displaying in the NEW custom color instead of standard
; red — proof that ULAPlus genuinely changes what an EXISTING
; attribute value displays (a real display-time palette lookup, not
; something that only affects freshly-drawn pixels), matching how the
; real hardware/2068-Leap's own already-working implementation is
; documented to behave.
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

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_ULAPLUS
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    call GFX_CLS

    ld   hl, SRC_TEST
    ld   de, SRC_TEST_LEN
    call INTERPRET_RUN

    ld   a, 6                    ; yellow: done -- screenshot now
    out  (PORT_ULA), a
.hang:
    jr   .hang

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not the real result
    out  (PORT_ULA), a
.hang:
    jr   .hang

SRC_TEST: DB "2 INK 100 100 30 CIRCLE 100 100 FILL 2 252 PALETTE 1 ULAPLUS "
SRC_TEST_LEN EQU $ - SRC_TEST

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_BORDER
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/ulaplus.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p48_rom0.bin", $0000, $4000
