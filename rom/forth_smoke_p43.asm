; ============================================================================
; rom/forth_smoke_p43.asm — Phase 43/44 smoke ROM: FREE
;
; TWO CHECKPOINTS:
;   1. FREE right after cold start = DICT_RAM_CEILING ($F000, raised
;      from Phase 43's $C000 by Phase 44's FILL-scratch relocation)
;      minus FORTH_DICT_RAM ($9800) = $5800 = 22528 exactly — the
;      honest number for this project's real RAM topology (see
;      core/free.asm's own header for the full ceiling/floor history).
;   2. After HERE is advanced by 100 bytes (simulating dictionary growth
;      from a real CREATE/compile), FREE tracks it exactly: 22528-100 =
;      22428. Proves FREE re-reads HERE live rather than caching the
;      cold-start value.
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

    ld   hl, DICT_LATEST_INIT_FREE
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: FREE = 22528 right after cold start ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call W_FREE
    ld   de, 22528
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: FREE tracks HERE after it advances ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, (HERE)
    ld   de, 100
    add  hl, de
    ld   (HERE), hl
    call W_FREE
    ld   de, 22428
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
    INCLUDE "core/free.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p43_rom0.bin", $0000, $4000
