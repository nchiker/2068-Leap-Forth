; ============================================================================
; rom/forth_smoke_p8.asm — Phase 8 smoke ROM: floating point (F+, F-)
;
; Proves core/float.asm's F+/F- both as real dictionary words (found
; and executed via the ordinary FIND/INTERPRET_RUN path, not called
; directly as assembly) and as correct arithmetic. Since there's no
; float literal syntax yet (see core/float.asm's own header), this ROM
; seeds the float stack directly via FPUSH before interpreting a
; source string containing just the operator itself ("F+ " or "F- ") —
; a narrower test than earlier phases could manage (it doesn't prove a
; user could type a float expression, because they can't yet), but a
; real one: it still proves the word is genuinely findable in the
; dictionary and that EXECUTE reaches the right code, not just that the
; underlying routine is correct in isolation.
;
; INCLUDE ORDER: same rule as every earlier smoke ROM. Only core/dict.asm
; and core/interp.asm are needed — core/float.asm doesn't touch
; kernel/, and this test doesn't need control flow, graphics, the
; editor, or storage.
;
; SELF-TEST, three checkpoints, each hand-picked so aligning the two
; mantissas never loses a bit (this test proves the alignment mechanism
; works, not how much precision survives a lossy shift — see
; core/float.asm's own header on that stated, separate limitation):
;   1. F+, exponents differ (e2 > e1): 1.0 (m=256,e=-8) + 2.0 (m=256,e=-7)
;      = 3.0 -> expect (m=384, e=-7). Exercises F_ALIGN's "shift F_M1" path.
;   2. F-, exponents equal: 5.0 (m=640,e=-7) - 2.0 (m=256,e=-7) = 3.0 ->
;      expect (m=384, e=-7). Exercises F_ALIGN's "no shift" path.
;   3. F+, exponents differ (e1 > e2): 4.0 (m=256,e=-6) + 1.0 (m=256,e=-8)
;      = 5.0 -> expect (m=320, e=-6). Exercises F_ALIGN's "shift F_M2" path.
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
; failing checkpoint's number (1-3), matching every earlier smoke ROM's
; convention.
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
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_P8
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: F+, e2 > e1 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 256
    ld   a, -8
    call FPUSH
    ld   hl, 256
    ld   a, -7
    call FPUSH
    ld   hl, SRC_FPLUS
    ld   de, SRC_FPLUS_LEN
    call INTERPRET_RUN
    ld   hl, 384
    ld   a, -7
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 2: F-, equal exponents ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 640
    ld   a, -7
    call FPUSH
    ld   hl, 256
    ld   a, -7
    call FPUSH
    ld   hl, SRC_FMINUS
    ld   de, SRC_FMINUS_LEN
    call INTERPRET_RUN
    ld   hl, 384
    ld   a, -7
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 3: F+, e1 > e2 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 256
    ld   a, -6
    call FPUSH
    ld   hl, 256
    ld   a, -8
    call FPUSH
    ld   hl, SRC_FPLUS
    ld   de, SRC_FPLUS_LEN
    call INTERPRET_RUN
    ld   hl, 320
    ld   a, -6
    call CHECK_FTOP
    call FPOP

; ---- checkpoint 4 (border color 5, not 4 -- see
; rom/forth_smoke_p27.asm's own header for why a checkpoint literally
; numbered 4 would collide with PASS_TEST's own green): F+ mantissa
; overflow. (30893,-16) + (18950,-18) aligns to (30893,-16) +
; (4737,-16) -- a direct add overflows (35630 > 32767, wrapping
; negative); the fix halves both aligned mantissas, adds (17814),
; and bumps the exponent by 1, giving (17814,-15) ~ 0.5436 -- close to
; the true sum ~0.5440, not a wrapped, wrong-signed nonsense value.
; See core/float.asm's own W_FPLUS header for the full story. ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, 30893
    ld   a, -16
    call FPUSH
    ld   hl, 18950
    ld   a, -18
    call FPUSH
    call W_FPLUS
    ld   hl, 17814
    ld   a, -15
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

CHECKPOINT_NUM EQU $8800

SRC_FPLUS:      DB "F+ "
SRC_FPLUS_LEN   EQU $ - SRC_FPLUS
SRC_FMINUS:     DB "F- "
SRC_FMINUS_LEN  EQU $ - SRC_FMINUS

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON   ; see core/control.asm's own header
    INCLUDE "core/float.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p8_rom0.bin", $0000, $4000
