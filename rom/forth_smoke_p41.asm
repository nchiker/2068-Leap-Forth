; ============================================================================
; rom/forth_smoke_p41.asm — Phase 41 smoke ROM: EXECUTE
;
; TWO CHECKPOINTS, proving core/execute.asm's own central claim --
; EXECUTE works identically on a PRIMITIVE and on a user-defined COLON
; DEFINITION, because this project's subroutine-threaded model gives
; both the exact same shape of "code address":
;   1. EXECUTE(W_PLUS's own code address) with (5 3) on the stack -> 8
;      -- a primitive, its xt taken directly at assembly time (no FIND
;      needed to prove the mechanism itself).
;   2. Compile `: DOUBLE DUP + ;` for real, through the actual
;      INTERPRET_RUN/colon-compiler pipeline (not faked), look its own
;      code address up via the real FIND (not a compile-time label --
;      DOUBLE doesn't have one, it's compiled into the RAM dictionary
;      at runtime), then EXECUTE(that xt) with 21 on the stack -> 42.
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

    ld   hl, DICT_LATEST_INIT_EXECUTE
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: EXECUTE(W_PLUS) with (5 3) -> 8 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 5
    call DPUSH_HL
    ld   hl, 3
    call DPUSH_HL
    ld   hl, W_PLUS
    call DPUSH_HL
    call W_EXECUTE
    ld   de, 8
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: compile ": DOUBLE DUP + ;" for real, FIND it,
; EXECUTE(that xt) with 21 -> 42 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, DEFINE_DOUBLE_SRC
    ld   de, DEFINE_DOUBLE_SRC_LEN
    call INTERPRET_RUN

    ld   hl, DOUBLE_NAME
    call DPUSH_HL
    call FIND
    call DPOP_HL                 ; hl = found flag
    ld   a, l
    or   a
    jp   z, FAIL_TEST             ; DOUBLE must have been found
    call DPOP_HL                 ; hl = immediate flag (discarded --
                                  ; DOUBLE isn't IMMEDIATE)
    call DPOP_HL                 ; hl = DOUBLE's own real code address
                                  ; (found via FIND, not a compile-time
                                  ; label -- it doesn't have one)
    push hl                       ; stash the xt on the Z80 hardware
                                  ; stack while pushing DOUBLE's own
                                  ; argument onto the FORTH stack first
    ld   hl, 21
    call DPUSH_HL
    pop  hl                        ; hl = xt again
    call DPUSH_HL                   ; NOW push it -- stack is ( 21 xt ),
                                    ; xt on top, exactly EXECUTE's own
                                    ; ( xt -- ) signature
    call W_EXECUTE
    ld   de, 42
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

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

DEFINE_DOUBLE_SRC:     DB ": DOUBLE DUP + ;"
DEFINE_DOUBLE_SRC_LEN  EQU $ - DEFINE_DOUBLE_SRC
DOUBLE_NAME:           DB 6, "D", "O", "U", "B", "L", "E"

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
DICT_CHAIN_POINT DEFL H_UNTIL
    INCLUDE "core/execute.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p41_rom0.bin", $0000, $4000
