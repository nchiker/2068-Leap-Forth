; ============================================================================
; rom/forth_smoke_p4.asm — Phase 4 smoke ROM: control flow (IF/ELSE/THEN,
; BEGIN/UNTIL)
;
; Proves core/control.asm's QBRANCH/BRANCH mechanism and its four
; IMMEDIATE compiling words work together, on top of Phase 2 and Phase
; 3's already-proven core/dict.asm and core/interp.asm. Same shape as
; rom/forth_smoke.asm and rom/forth_smoke_p3.asm: a fixed self-test with
; known-correct results, border reports pass/fail. Neither earlier
; smoke ROM is touched — each phase's proof stays independent.
;
; INCLUDE ORDER: core/dict.asm, then core/interp.asm, then
; core/control.asm — all AFTER DEVICE/ORG $0000 and the fixed RST vector
; table, not before. See docs/PROJECT_PLAN.md's Phase 2 section for why
; this is load-bearing, not stylistic (it bit the first attempt at
; rom/forth_smoke.asm once already).
;
; SELF-TEST, three INTERPRET_RUN calls over fixed source strings:
;   1. ": IFTEST 0= IF 111 ELSE 222 THEN ; 0 IFTEST " -> 0 is the input,
;      0= makes it TRUE, IF takes the true branch -> top of stack 111.
;   2. "5 IFTEST " (IFTEST already defined by checkpoint 1) -> 5 is the
;      input, 0= makes it FALSE, IF takes the ELSE branch -> 222.
;   3. ": COUNTDOWN BEGIN 1 - DUP 0= UNTIL ; 5 COUNTDOWN " -> defines a
;      loop that decrements the top of the stack until it reaches
;      exactly 0, then stops -- this only ends with 0 on the stack if
;      the loop actually ran the correct number of times (5, here);
;      any wrong iteration count leaves a nonzero result instead.
;
; Border goes GREEN (4) if all three pass; otherwise it shows which
; checkpoint (1-3) failed, matching the earlier smoke ROMs' convention.
;
; Build:
;   sjasmplus rom/forth_smoke_p4.asm
;   (produces forth_smoke_p4_rom0.bin, 16K, per the SAVEBIN at the end)
; ============================================================================

    INCLUDE "include/hardware.inc"     ; constants only -- safe before ORG

    DEVICE NOSLOT64K
    ORG $0000

; ---- RST 00: cold start ----
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

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_P4
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: IF, true branch ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_A
    ld   de, TEST_SRC_A_LEN
    call INTERPRET_RUN
    ld   de, 111
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: IF, false branch (reusing IFTEST) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_B
    ld   de, TEST_SRC_B_LEN
    call INTERPRET_RUN
    ld   de, 222
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3: BEGIN/UNTIL loop ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_C
    ld   de, TEST_SRC_C_LEN
    call INTERPRET_RUN
    ld   de, 0
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_TOP:                       ; DE = expected top-of-stack value
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jr   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all three checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1-3) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:          ; core/interp.asm's hook -- see
                                  ; rom/forth_smoke_p3.asm's own use of
                                  ; this same hook for the color choice
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8542         ; 1 byte, alongside core/interp.asm's own
                                  ; Phase 3 scratch cells (see that file)

TEST_SRC_A:     DB ": IFTEST 0= IF 111 ELSE 222 THEN ; 0 IFTEST "
TEST_SRC_A_LEN  EQU $ - TEST_SRC_A
TEST_SRC_B:     DB "5 IFTEST "
TEST_SRC_B_LEN  EQU $ - TEST_SRC_B
TEST_SRC_C:     DB ": COUNTDOWN BEGIN 1 - DUP 0= UNTIL ; 5 COUNTDOWN "
TEST_SRC_C_LEN  EQU $ - TEST_SRC_C

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 -- see this file's own
; header ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
    INCLUDE "core/control.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p4_rom0.bin", $0000, $4000
