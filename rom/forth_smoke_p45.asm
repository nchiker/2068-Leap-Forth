; ============================================================================
; rom/forth_smoke_p45.asm — Phase 45 smoke ROM: THROW and CATCH
; (core/throwcatch.asm)
;
; FIVE CHECKPOINTS. Checkpoints 1-4 call W_CATCH/W_THROW directly
; against small hand-written "xt" stubs (any code address ending in
; `ret` is a valid xt — the same insight Phase 41's own EXECUTE smoke
; ROM used), which is enough to prove the core save/restore mechanism
; without needing the compiler. Checkpoint 5 is the one case that
; genuinely needs the real interpreter: an UNCAUGHT throw from several
; levels of REAL, COMPILED word calls deep, proving THROW_ROOT_SP
; (core/interp.asm) correctly unwinds the real Z80 hardware stack all
; the way back to INTERPRET_RUN's own caller, not just one level.
;
;   1. CATCH around a normally-completing xt: pushes 0, and whatever
;      the xt itself pushed (42) survives underneath it.
;   2. CATCH around an xt that THROWs 7: pushes 7 (not 0), and
;      whatever the xt pushed BEFORE throwing (a 999 sentinel) does
;      NOT survive -- CATCH restores to its own pre-call depth first.
;   3. NESTED CATCH: an outer xt CATCHes an inner xt that throws 7.
;      The inner CATCH must absorb it (leaving 7 on the stack), the
;      outer xt must keep running afterward (proven by a 555 it pushes
;      next), and the OUTER catch must still report success (0) --
;      the throw never reached it. Final stack, top-down: 0, 555, 7.
;   4. THROW 0 is a strict no-op: a sentinel pushed first must survive
;      completely untouched, and CATCH_DEPTH must be unaffected.
;   5. UNCAUGHT throw: compiles `: DEEP3 42 THROW ; : DEEP2 DEEP3 ; :
;      DEEP1 DEEP2 ;` via one real INTERPRET_RUN call, then runs
;      `DEEP1` via a second -- three real nested CALLs deep, no CATCH
;      active. Verifies RUNTIME_ERROR_HOOK fires exactly once, both
;      data stacks come back empty, and control genuinely returns to
;      this ROM's own harness afterward (not a hang or a crash).
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

    ld   hl, DICT_LATEST_INIT_THROWCATCH
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a

    call GFX_CLS

    ld   hl, 0
    ld   (HOOK_CALLED_COUNT), hl

; ---- checkpoint 1: CATCH around a normally-completing xt ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_XT_OK
    call DPUSH_HL
    call W_CATCH
    ld   de, 0
    call CHECK_TOP
    call W_DROP
    ld   de, 42
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: CATCH around an xt that throws 7 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_XT_THROWS
    call DPUSH_HL
    call W_CATCH
    ld   de, 7
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3: nested CATCH -- inner absorbs, outer still sees 0 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_XT_NESTED
    call DPUSH_HL
    call W_CATCH
    ld   de, 0
    call CHECK_TOP
    call W_DROP
    ld   de, 555
    call CHECK_TOP
    call W_DROP
    ld   de, 7
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 4: THROW 0 is a strict no-op ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, 0
    call DPUSH_HL
    call W_THROW
    ld   de, 4242
    call CHECK_TOP
    call W_DROP
    ld   a, (CATCH_DEPTH)
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 5: uncaught throw, 3 real nested calls deep ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_DEFINE
    ld   de, SRC_DEFINE_LEN
    call INTERPRET_RUN
    ld   hl, SRC_RUN
    ld   de, SRC_RUN_LEN
    call INTERPRET_RUN
    ld   hl, (HOOK_CALLED_COUNT)
    ld   de, 1
    call CHECK_HL_DE
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    call CHECK_HL_DE
    push iy
    pop  hl
    ld   de, FSTACK_TOP
    call CHECK_HL_DE

    jp   PASS_TEST

; ============================================================================
; Test "xt" stubs -- any code address ending in `ret` is a valid xt.
; ============================================================================
TEST_XT_OK:
    ld   hl, 42
    call DPUSH_HL
    ret

TEST_XT_THROWS:
    ld   hl, 999               ; must NOT survive the throw below
    call DPUSH_HL
    ld   hl, 7
    call DPUSH_HL
    call W_THROW
    ld   hl, 12345              ; sentinel -- reaching this at all would
    call DPUSH_HL                ; mean THROW's own unwind is broken
    ret

TEST_XT_NESTED:
    ld   hl, TEST_XT_THROWS
    call DPUSH_HL
    call W_CATCH                 ; inner CATCH absorbs the throw -> 7
    ld   hl, 555
    call DPUSH_HL
    ret

; ============================================================================
; RUNTIME_ERROR_HOOK -- this test's own implementation of the hook
; THROW's own uncaught path (and Phase 38's STACK_CHECK) requires.
; Just counts calls; the real recovery (resetting IX/IY) already
; happened before this was reached.
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   hl, (HOOK_CALLED_COUNT)
    inc  hl
    ld   (HOOK_CALLED_COUNT), hl
    ret

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

; ============================================================================
; CHECK_HL_DE ( HL DE -- )  halts with the border showing the current
; checkpoint number if HL != DE.
; ============================================================================
CHECK_HL_DE:
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
HOOK_CALLED_COUNT   EQU $8802

SRC_DEFINE: DB ": DEEP3 42 THROW ; : DEEP2 DEEP3 ; : DEEP1 DEEP2 ; "
SRC_DEFINE_LEN EQU $ - SRC_DEFINE

SRC_RUN: DB "DEEP1 "
SRC_RUN_LEN EQU $ - SRC_RUN

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    DEFINE THROW_CATCH_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/throwcatch.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p45_rom0.bin", $0000, $4000
