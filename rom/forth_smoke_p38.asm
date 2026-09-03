; ============================================================================
; rom/forth_smoke_p38.asm — Phase 38 smoke ROM: runtime stack-error
; detection (STACK_CHECK / RUNTIME_ERROR_HOOK, core/interp.asm)
;
; FIVE CHECKPOINTS. STACK_CHECK is only ever CALLED by INTERPRET_RUN's
; own .loop in real use, so this test wraps each call the same way
; .loop does (a small helper subroutine, TEST_CALL_STACK_CHECK) --
; STACK_CHECK's own error path discards ITS caller's return address
; before jumping to RUNTIME_ERROR_HOOK, exactly mirroring how .loop's
; own iteration gets skipped on a real violation; testing it any other
; way wouldn't exercise the real contract.
;   1. Baseline: a legitimate push doesn't false-trigger the hook, and
;      the pushed value survives untouched.
;   2. Data-stack UNDERFLOW: IX pushed one cell past DSTACK_TOP
;      (simulating a word that popped from empty) -- hook fires, IX
;      resets to DSTACK_TOP.
;   3. Data-stack OVERFLOW: IX pushed one cell past DSTACK_LIMIT going
;      the other way -- hook fires, IX resets to DSTACK_TOP.
;   4. Float-stack UNDERFLOW: IY pushed one cell (3 bytes) past
;      FSTACK_TOP -- hook fires, IY resets to FSTACK_TOP.
;   5. Float-stack OVERFLOW: IY pushed one cell past FSTACK_LIMIT --
;      hook fires, IY resets to FSTACK_TOP.
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

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_P3
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

    ld   hl, 0
    ld   (HOOK_CALLED_COUNT), hl

; ---- checkpoint 1: baseline -- legitimate push, no false trigger ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    ld   hl, 4242
    call DPUSH_HL
    call TEST_CALL_STACK_CHECK
    ld   hl, (HOOK_CALLED_COUNT)
    ld   de, 0
    call CHECK_HL_DE
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: data-stack underflow ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    inc  ix
    inc  ix                  ; simulate an underflowing pop
    call TEST_CALL_STACK_CHECK
    ld   hl, (HOOK_CALLED_COUNT)
    ld   de, 1
    call CHECK_HL_DE
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    call CHECK_HL_DE

; ---- checkpoint 3: data-stack overflow ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_LIMIT
    dec  ix
    dec  ix                  ; simulate an over-pushed stack
    call TEST_CALL_STACK_CHECK
    ld   hl, (HOOK_CALLED_COUNT)
    ld   de, 2
    call CHECK_HL_DE
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    call CHECK_HL_DE

; ---- checkpoint 4: float-stack underflow ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    inc  iy
    inc  iy
    inc  iy                  ; simulate an underflowing FPOP
    call TEST_CALL_STACK_CHECK
    ld   hl, (HOOK_CALLED_COUNT)
    ld   de, 3
    call CHECK_HL_DE
    push iy
    pop  hl
    ld   de, FSTACK_TOP
    call CHECK_HL_DE

; ---- checkpoint 5: float-stack overflow ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   iy, FSTACK_LIMIT
    dec  iy
    dec  iy
    dec  iy                  ; simulate an over-pushed float stack
    call TEST_CALL_STACK_CHECK
    ld   hl, (HOOK_CALLED_COUNT)
    ld   de, 4
    call CHECK_HL_DE
    push iy
    pop  hl
    ld   de, FSTACK_TOP
    call CHECK_HL_DE

    jp   PASS_TEST

; ============================================================================
; TEST_CALL_STACK_CHECK -- mirrors INTERPRET_RUN's own .loop calling
; STACK_CHECK: on the error path, STACK_CHECK discards ITS OWN return
; address (into here) and jumps to RUNTIME_ERROR_HOOK, whose own `ret`
; then returns straight to THIS routine's own caller, skipping the
; `ret` below entirely -- exactly mirroring how a real violation skips
; the rest of .loop's own current iteration.
; ============================================================================
TEST_CALL_STACK_CHECK:
    call STACK_CHECK
    ret

; ============================================================================
; RUNTIME_ERROR_HOOK -- this test's own implementation of Phase 38's
; required hook. Just counts how many times it's been reached; the
; real recovery (resetting IX/IY) already happened inside STACK_CHECK
; itself before this was ever called.
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   hl, (HOOK_CALLED_COUNT)
    inc  hl
    ld   (HOOK_CALLED_COUNT), hl
    ret

; ============================================================================
; CHECK_HL_DE ( HL DE -- )  halts with the border showing the current
; checkpoint number if HL != DE.
; ============================================================================
CHECK_HL_DE:
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; CHECK_TOP ( DE = expected -- )  checks the top of the data stack
; WITHOUT popping it.
; ============================================================================
CHECK_TOP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
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

CHECKPOINT_NUM     EQU $8800
HOOK_CALLED_COUNT  EQU $8802     ; 2 bytes

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000. core/float.asm is
; REQUIRED before core/interp.asm when RUNTIME_ERROR_CHECK_ENABLED is
; defined -- see core/interp.asm's own STACK_CHECK header. ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    DEFINE RUNTIME_ERROR_CHECK_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/float.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p38_rom0.bin", $0000, $4000
