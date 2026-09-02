; ============================================================================
; rom/forth_smoke_p37.asm — Phase 37 smoke ROM: STICK
;
; TWO CHECKPOINTS. AUTOMATED VERIFICATION LIMIT, stated honestly, the
; same way core/sound.asm's own header already does for SOUND: no
; joystick is actually connected in this emulated environment, so this
; can't prove STICK reads a REAL joystick correctly -- only that it
; reaches real AY-3-8912 hardware without hanging, returns the value
; real Fuse's own AY register 14 gives with nothing pressed (confirmed
; live via a throwaway diagnostic before writing these checkpoints, not
; guessed), and consumes/produces exactly its own one argument/one
; result (a sentinel value placed BELOW the device number on the stack
; survives the call completely untouched).
;   1. STICK(1) = 0 (device 1: no direction bits set), sentinel intact.
;   2. STICK(2) = 0 (device 2: not pressed), sentinel intact.
;
; Border goes GREEN (4) if both pass; otherwise it shows the failing
; checkpoint's number.
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

    ld   hl, DICT_LATEST_INIT_STICK
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: STICK(1) = 0, sentinel intact ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, 1
    call DPUSH_HL
    call W_STICK
    ld   de, 0
    call CHECK_TOP
    call W_DROP
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: STICK(2) = 0, sentinel intact ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, 2
    call DPUSH_HL
    call W_STICK
    ld   de, 0
    call CHECK_TOP
    call W_DROP
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ============================================================================
; CHECK_TOP ( DE = expected -- )  checks the top of the data stack
; WITHOUT popping it (the caller drops separately once done).
; ============================================================================
CHECK_TOP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: both checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/stick.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p37_rom0.bin", $0000, $4000
