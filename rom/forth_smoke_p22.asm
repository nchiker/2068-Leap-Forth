; ============================================================================
; rom/forth_smoke_p22.asm — Phase 22 smoke ROM: F. (print a float)
;
; Same testing approach as rom/forth_smoke_p8.asm/p18.asm/p19.asm: no
; float literal syntax exists, so this ROM seeds the float stack
; directly via FPUSH before interpreting a source string containing
; just "F. ", then checks PRINT_COL advanced by the exact expected
; character count.
;
; THREE CHECKPOINTS, the exact three cases hand-verified in
; core/floatprint.asm's own header:
;   1. 6.0 (m=24576,e=-12) -> prints "6.0000 " (7 chars)
;   2. 0.25 (m=16384,e=-16) -> prints "0.2500 " (7 chars)
;   3. -2.0 (m=-16384,e=-13) -> prints "-2.0000 " (8 chars), sign
;      handling
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
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

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_FLOATPRINT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: 6.0 F. -> "6.0000 " (7 chars) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 24576
    ld   a, -12
    call FPUSH
    ld   hl, SRC_FDOT
    ld   de, SRC_FDOT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

; ---- checkpoint 2: 0.25 F. -> "0.2500 " (7 chars) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, 16384
    ld   a, -16
    call FPUSH
    ld   hl, SRC_FDOT
    ld   de, SRC_FDOT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

; ---- checkpoint 3: -2.0 F. -> "-2.0000 " (8 chars) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, -16384
    ld   a, -13
    call FPUSH
    ld   hl, SRC_FDOT
    ld   de, SRC_FDOT_LEN
    call INTERPRET_RUN
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   8
    jp   nz, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: all three checkpoints passed
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

SRC_FDOT: DB "F. "
SRC_FDOT_LEN EQU $ - SRC_FDOT

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/floatprint.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p22_rom0.bin", $0000, $4000
