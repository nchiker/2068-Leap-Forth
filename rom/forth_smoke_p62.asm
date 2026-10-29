; ============================================================================
; rom/forth_smoke_p62.asm — Phase 62 smoke ROM: BREAK?
;
; TWO CHECKPOINTS, both real, neither needing a live keyboard --
; IO_CHECK_BREAK (kernel/io/io.asm) does its OWN fresh hardware
; keyboard-matrix scan on every call, unlike KEY/KEY?'s latched-sysvar
; mechanism (rom/forth_smoke_p36.asm's own checkpoints 4-6), so there
; is no sysvar to pre-seed for the "held" case the way KBD_KEYHIT/
; KBD_LASTK can be forced for KEY?. Confirming BREAK? actually reads
; TRUE when CAPS SHIFT+SPACE is really held needs a live or injected
; keyboard, same honest gap class as core/editor.asm's own
; EDITOR_LOOP_LIVE (see that file's header) -- not skipped here, just
; genuinely out of reach for an automated border-color smoke ROM.
;
;   1. BREAK? is FALSE on an idle bus (nothing pressed, real hardware
;      scan against Fuse's own unpressed keyboard state).
;   2. Calling BREAK? does not disturb KEY?'s own separate latched
;      state -- force KBD_KEYHIT=1 the same way rom/forth_smoke_p36.asm's
;      own checkpoint 5 does, call BREAK? (a real scan, discarded),
;      then confirm KEY? still reads TRUE afterward: proves the two
;      words' mechanisms are genuinely independent, not that one
;      silently consumes state the other relies on.
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
    INCLUDE "include/rst_vectors.inc"
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

    ld   hl, DICT_LATEST_INIT_KEYQ
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: BREAK? is FALSE on an idle bus ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call W_BREAKQ
    ld   de, 0
    call CHECK_ITOP

; ---- checkpoint 2: BREAK? doesn't disturb KEY?'s own latched state ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   a, 1
    ld   (KBD_KEYHIT), a
    ld   a, "X"
    ld   (KBD_LASTK), a
    call W_BREAKQ                 ; real scan, result discarded --
                                  ; only checking it leaves KEY?'s own
                                  ; state alone
    call W_KEYQ
    ld   de, -1
    call CHECK_ITOP

    jp   PASS_TEST

; ============================================================================
; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch. Identical to
; rom/forth_smoke_p36.asm's own CHECK_ITOP.
; ============================================================================
CHECK_ITOP:
    rst RST_DPOP
    ld   a, l
    cp   e
    jp   nz, FAIL_TEST
    ld   a, h
    cp   d
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

CHECKPOINT_NUM  EQU $8800

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
DICT_CHAIN_POINT DEFL H_UNTIL
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/key.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p62_rom0.bin", $0000, $4000
