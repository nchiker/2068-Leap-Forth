; ============================================================================
; rom/forth_smoke_p5.asm — Phase 5 smoke ROM: TS2068 vocabulary (PLOT,
; LINE, CIRCLE, BEEP, BORDER)
;
; Proves core/ts2068.asm's five words correctly wire data-stack values
; into the kernel/graphics and kernel/sound calls they wrap. This is
; the first smoke ROM in the project to include real kernel/ modules
; (kernel/math, kernel/graphics, kernel/sound) alongside core/ — see
; core/interp.asm's own header for why that matters: this ROM's very
; existence is what forced fixing a real RAM-address collision between
; this project's own Phase 3 scratch cells and 2068-Leap's inherited
; kernel/BASIC sysvars, found by assembling them together for the first
; time (see docs/PROJECT_PLAN.md's Phase 5 section for the full story).
;
; INCLUDE ORDER: same rule as every earlier smoke ROM — kernel/ and
; core/ modules are INCLUDEd AFTER DEVICE/ORG $0000 and the fixed RST
; vector table, never before.
;
; VERIFICATION STRATEGY: PLOT/LINE/CIRCLE don't leave anything on the
; data stack to check (their whole job is a side effect on the screen
; bitmap), so this smoke ROM verifies them a different way: it calls
; kernel/graphics's own GFX_READ_PIXEL directly (not through a Forth
; word -- there isn't one yet) to confirm the exact pixels each word
; was supposed to set are actually set, and that a nearby pixel that
; should NOT have been touched wasn't. This tests THIS project's own
; wiring (did the right coordinates reach the kernel call), not
; kernel/graphics's drawing algorithms themselves, which are already
; 2068-Leap's own tested and proven code.
;
; BORDER is checked by reading back PORT_FE_SHADOW (kernel/graphics's
; own shadow copy of the ULA port) rather than the border color itself
; -- this smoke ROM's OWN pass/fail signal IS the border color, so
; checking BORDER's effect that way would be ambiguous.
;
; BEEP has no way to verify actual sound output in this environment (a
; deliberate, stated limitation, not an oversight -- see this file's
; own checkpoint 5 comment). It's checked for data-stack hygiene
; instead: a sentinel value is pushed before BEEP consumes its two
; arguments, and confirmed still correctly in place afterward.
;
; Five checkpoints; border goes GREEN (4) if all pass, otherwise shows
; the failing checkpoint's number (1-5), matching every earlier smoke
; ROM's convention.
;
; Build:
;   sjasmplus rom/forth_smoke_p5.asm
;   (produces forth_smoke_p5_rom0.bin, 16K, per the SAVEBIN at the end)
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

    ld   hl, DICT_LATEST_INIT_P5
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR          ; required since Phase 15 -- see
    ld   (CURRENT_ATTR), a        ; core/ts2068.asm's own header

    call GFX_CLS                 ; start from a known-clear bitmap so a
                                  ; stray already-set pixel can't fake a pass

; ---- checkpoint 1: PLOT ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_PLOT
    ld   de, TEST_SRC_PLOT_LEN
    call INTERPRET_RUN
    ld   b, 10
    ld   c, 20
    call GFX_READ_PIXEL
    or   a
    jp   z, FAIL_TEST             ; the plotted pixel must be set
    ld   b, 11
    ld   c, 20
    call GFX_READ_PIXEL
    or   a
    jp   nz, FAIL_TEST            ; a neighboring pixel must NOT be set

; ---- checkpoint 2: LINE ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_LINE
    ld   de, TEST_SRC_LINE_LEN
    call INTERPRET_RUN
    ld   b, 60
    ld   c, 5
    call GFX_READ_PIXEL
    or   a
    jp   z, FAIL_TEST             ; the line's start point must be set
    ld   b, 100
    ld   c, 45
    call GFX_READ_PIXEL
    or   a
    jp   z, FAIL_TEST             ; the line's end point must be set

; ---- checkpoint 3: CIRCLE ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_CIRCLE
    ld   de, TEST_SRC_CIRCLE_LEN
    call INTERPRET_RUN
    ld   b, 150
    ld   c, 80
    call GFX_READ_PIXEL           ; top
    or   a
    jp   z, FAIL_TEST
    ld   b, 150
    ld   c, 120
    call GFX_READ_PIXEL           ; bottom
    or   a
    jp   z, FAIL_TEST
    ld   b, 130
    ld   c, 100
    call GFX_READ_PIXEL           ; left
    or   a
    jp   z, FAIL_TEST
    ld   b, 170
    ld   c, 100
    call GFX_READ_PIXEL           ; right
    or   a
    jp   z, FAIL_TEST

; ---- checkpoint 4: BORDER ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_BORDER
    ld   de, TEST_SRC_BORDER_LEN
    call INTERPRET_RUN
    ld   a, (PORT_FE_SHADOW)
    and  $07
    cp   5
    jp   nz, FAIL_TEST

; ---- checkpoint 5: BEEP (stack hygiene only -- see file header) ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, TEST_SRC_BEEP
    ld   de, TEST_SRC_BEEP_LEN
    call INTERPRET_RUN
    ld   de, 4242
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_TOP:                       ; DE = expected top-of-stack value
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

FAIL_TEST:                       ; border shows which checkpoint (1-5) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8542         ; 1 byte, right after core/interp.asm's
                                  ; own WORD_BUF (see that file)

TEST_SRC_PLOT:    DB "10 20 PLOT "
TEST_SRC_PLOT_LEN EQU $ - TEST_SRC_PLOT
TEST_SRC_LINE:    DB "60 5 100 45 LINE "
TEST_SRC_LINE_LEN EQU $ - TEST_SRC_LINE
TEST_SRC_CIRCLE:    DB "150 100 20 CIRCLE "
TEST_SRC_CIRCLE_LEN EQU $ - TEST_SRC_CIRCLE
TEST_SRC_BORDER:    DB "5 BORDER "
TEST_SRC_BORDER_LEN EQU $ - TEST_SRC_BORDER
TEST_SRC_BEEP:    DB "100 5 BEEP "
TEST_SRC_BEEP_LEN EQU $ - TEST_SRC_BEEP

; ---- kernel + dictionary: included here, after the vector table and
; the self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON   ; see core/control.asm's own header
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p5_rom0.bin", $0000, $4000
