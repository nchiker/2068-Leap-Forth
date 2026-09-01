; ============================================================================
; rom/forth_smoke_p18.asm — Phase 18 smoke ROM: F* (float multiply)
;
; Same testing approach as rom/forth_smoke_p8.asm (F+/F-): no float
; literal syntax exists, so this ROM seeds the float stack directly via
; FPUSH before interpreting a source string containing just "F* ",
; then checks the result on the float stack directly (CHECK_FTOP,
; copied from forth_smoke_p8.asm's own helper).
;
; FOUR CHECKPOINTS, each hand-verified in core/floatmul.asm's own
; header before this ROM was written, covering every distinct code
; path in F_NORMALIZE32:
;   1. 2.0 (m=256,e=-7) * 3.0 (m=384,e=-7) = 6.0 -> (m=24576, e=-12).
;      Shrink path, two iterations.
;   2. 0.5 (m=256,e=-9) * 0.5 (m=256,e=-9) = 0.25 -> (m=16384, e=-16).
;      Shrink path again, a different starting shape (squaring).
;   3. 1.0 (m=1,e=0) * 1.0 (m=1,e=0) = 1.0 -> (m=16384, e=-14). The
;      GROW path -- a product small enough to need shifting UP, not
;      down, to reach a normalized magnitude.
;   4. -2.0 (m=-256,e=-7) * 3.0 (m=384,e=-7) = -6.0 ->
;      (m=-24576, e=-12). Sign handling: same magnitude as checkpoint
;      1, opposite sign.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
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

    ld   hl, DICT_LATEST_INIT_FLOATMUL
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: 2.0 * 3.0 = 6.0 (shrink path) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 256
    ld   a, -7
    call FPUSH
    ld   hl, 384
    ld   a, -7
    call FPUSH
    ld   hl, SRC_FSTAR
    ld   de, SRC_FSTAR_LEN
    call INTERPRET_RUN
    ld   hl, 24576
    ld   a, -12
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 2: 0.5 * 0.5 = 0.25 (shrink path, squaring) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 256
    ld   a, -9
    call FPUSH
    ld   hl, 256
    ld   a, -9
    call FPUSH
    ld   hl, SRC_FSTAR
    ld   de, SRC_FSTAR_LEN
    call INTERPRET_RUN
    ld   hl, 16384
    ld   a, -16
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 3: 1.0 * 1.0 = 1.0 (grow path) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 1
    ld   a, 0
    call FPUSH
    ld   hl, 1
    ld   a, 0
    call FPUSH
    ld   hl, SRC_FSTAR
    ld   de, SRC_FSTAR_LEN
    call INTERPRET_RUN
    ld   hl, 16384
    ld   a, -14
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 4: -2.0 * 3.0 = -6.0 (sign handling) ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, -256
    ld   a, -7
    call FPUSH
    ld   hl, 384
    ld   a, -7
    call FPUSH
    ld   hl, SRC_FSTAR
    ld   de, SRC_FSTAR_LEN
    call INTERPRET_RUN
    ld   hl, -24576
    ld   a, -12
    call CHECK_FTOP
    call FPOP

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_FTOP:                      ; HL = expected mantissa, A = expected
                                  ; exponent; float stack NOT popped
    push af
    ld   a, (iy+0)
    cp   l
    jp   nz, FAIL_TEST
    ld   a, (iy+1)
    cp   h
    jp   nz, FAIL_TEST
    pop  af
    ld   l, a
    ld   a, (iy+2)
    cp   l
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all four checkpoints passed
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

SRC_FSTAR: DB "F* "
SRC_FSTAR_LEN EQU $ - SRC_FSTAR

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p18_rom0.bin", $0000, $4000
