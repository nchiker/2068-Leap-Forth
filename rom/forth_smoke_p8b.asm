; ============================================================================
; rom/forth_smoke_p8b.asm — Phase 8b smoke ROM: 64-column display
;
; Proves core/mode64.asm's four words (64COL, 32COL, PALETTE64, PLOT64)
; both as real dictionary words and as correct wiring into
; kernel/mode64/mode64.asm — see that file's own header for the real
; provenance (recovered, once-shipped 2068-Leap code, not new
; from-scratch hardware code) and docs/PROJECT_PLAN.md's Phase 8
; section for the full story, including a first attempt at this file
; that had the wrong port bit pattern before that recovery.
;
; A separate smoke ROM from rom/forth_smoke_p8.asm (floating point) —
; this one needs kernel/graphics + kernel/math, that one needs neither;
; keeping them apart matches every earlier phase's "only depend on
; what's actually needed" discipline.
;
; SELF-TEST, three checkpoints:
;   1. Enter 64-column mode and plot one pixel; verify via
;      MODE64_READ_PIXEL that exactly that pixel is set and a
;      neighboring one is not (same technique as Phase 5's PLOT check).
;   2. Select a palette; verify port $FF's bits 3-5 (and the still-set
;      64-column marker in bits 0-2) reflect it — checked via
;      PORT_FF_SHADOW readback, not the border, matching Phase 5's
;      BORDER-check precedent (this ROM's own pass/fail signal IS the
;      border color).
;   3. Return to Normal mode; verify port $FF's bits 0-2 are clear.
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
; failing checkpoint's number (1-3).
; ============================================================================

    INCLUDE "include/hardware.inc"

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

    ld   hl, DICT_LATEST_INIT_P8B
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: 64COL + PLOT64 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_1
    ld   de, SRC_1_LEN
    call INTERPRET_RUN
    ld   hl, 100
    ld   c, 50
    call MODE64_READ_PIXEL
    or   a
    jp   z, FAIL_TEST             ; the plotted pixel must be set
    ld   hl, 101
    ld   c, 50
    call MODE64_READ_PIXEL
    or   a
    jp   nz, FAIL_TEST            ; a neighboring pixel must NOT be set

; ---- checkpoint 2: PALETTE64 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_2
    ld   de, SRC_2_LEN
    call INTERPRET_RUN
    ld   a, (PORT_FF_SHADOW)
    and  %00111111
    cp   46                       ; palette 5: 5*8+6 = 46
    jp   nz, FAIL_TEST

; ---- checkpoint 3: 32COL ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_3
    ld   de, SRC_3_LEN
    call INTERPRET_RUN
    ld   a, (PORT_FF_SHADOW)
    and  %00000111
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
PASS_TEST:
    ld   a, 4                    ; green: all three checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1-3) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $87B8         ; 1 byte, right after
                                  ; kernel/mode64/mode64.asm's own
                                  ; scratch (see that file)

SRC_1:    DB "64COL 100 50 PLOT64 "
SRC_1_LEN EQU $ - SRC_1
SRC_2:    DB "5 PALETTE64 "
SRC_2_LEN EQU $ - SRC_2
SRC_3:    DB "32COL "
SRC_3_LEN EQU $ - SRC_3

; ---- kernel + dictionary: included here, after the vector table and
; the self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/mode64/mode64.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON   ; see core/control.asm's own header
    INCLUDE "core/float.asm"
    INCLUDE "core/mode64.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p8b_rom0.bin", $0000, $4000
