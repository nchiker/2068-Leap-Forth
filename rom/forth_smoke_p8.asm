; ============================================================================
; rom/forth_smoke_p8.asm — Phase 8 smoke ROM: floating point (F+, F-)
;
; Proves core/fpcore.asm's F+/F- both as real dictionary words (found
; and executed via the ordinary FIND/INTERPRET_RUN path, not called
; directly as assembly) and as correct arithmetic. This ROM seeds the
; float stack directly via FPUSH_HL before interpreting a source string
; containing just the operator itself ("F+ " or "F- ") — it proves the
; word is genuinely findable in the dictionary and that EXECUTE reaches
; the right code, not just that the underlying routine is correct in
; isolation.
;
; Regenerated for the 5-byte Sinclair float format in step F (docs/V2/
; FLOAT_SPEC.md): inputs are 5-byte cells, the expected results are 5-byte
; rows compared byte for byte; each row's comment is the tools/fpforth.py
; expression that produced it (enc = fpmodel.encode), not an emulator value.
;
; INCLUDE ORDER: same rule as every earlier smoke ROM. Only core/dict.asm,
; core/interp.asm and core/fpcore.asm are needed.
;
; SELF-TEST, four checkpoints (numbered 1, 2, 3, 5: see checkpoint 5):
;   1. F+, exponents differ (e2 > e1): 1.0 + 2.0 = 3.0.
;   2. F-, exponents equal: 5.0 - 2.0 = 3.0.
;   3. F+, exponents differ (e1 > e2): 4.0 + 1.0 = 5.0.
;   5. F+ with a carry out of the mantissa (see below).
;
; Border goes GREEN (4) if all pass; otherwise it shows the failing
; checkpoint's number, matching every earlier smoke ROM's convention.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

; ---- RST 00: cold start ----
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
    ld   hl, IN_1_0
    call FPUSH_HL
    ld   hl, IN_2_0
    call FPUSH_HL
    ld   hl, SRC_FPLUS
    ld   de, SRC_FPLUS_LEN
    call INTERPRET_RUN
    ld   hl, EXP_3_0
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 2: F-, equal exponents ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, IN_5_0
    call FPUSH_HL
    ld   hl, IN_2_0
    call FPUSH_HL
    ld   hl, SRC_FMINUS
    ld   de, SRC_FMINUS_LEN
    call INTERPRET_RUN
    ld   hl, EXP_3_0
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 3: F+, e1 > e2 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, IN_4_0
    call FPUSH_HL
    ld   hl, IN_1_0
    call FPUSH_HL
    ld   hl, SRC_FPLUS
    ld   de, SRC_FPLUS_LEN
    call INTERPRET_RUN
    ld   hl, EXP_5_0
    call CHECK_FTOP
    call FDROP_T

; ---- checkpoint 4 (border color 5, not 4 -- see
; rom/forth_smoke_p27.asm's own header for why a checkpoint literally
; numbered 4 would collide with PASS_TEST's own green): F+ carry out of
; the mantissa. 0.47139 + 0.07229: the two 32-bit mantissas add past
; 2^32 once aligned, so the sum is shifted right one bit and the
; exponent bumped (FDONE), giving 0.54368 -- the correctly rounded sum,
; not a wrapped value. ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, IN_CARRY_A
    call FPUSH_HL
    ld   hl, IN_CARRY_B
    call FPUSH_HL
    call W_FPLUS
    ld   hl, EXP_CARRY
    call CHECK_FTOP
    call FDROP_T

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_FTOP:                      ; HL -> 5 expected bytes; float stack NOT popped
    push iy
    pop  de
    ld   b, 5
.cmp:
    ld   a, (de)
    cp   (hl)
    jp   nz, FAIL_TEST
    inc  de
    inc  hl
    djnz .cmp
    ret

FDROP_T:                         ; drop the top float cell
    ld   bc, 5
    add  iy, bc
    ret

; ---- 5-byte cells: [exponent][sign | m0][m1][m2][m3]; the comment is the fpforth expression ----
IN_1_0:     DB   $81, $00, $00, $00, $00   ; enc(1.0)
IN_2_0:     DB   $82, $00, $00, $00, $00   ; enc(2.0)
IN_4_0:     DB   $83, $00, $00, $00, $00   ; enc(4.0)
IN_5_0:     DB   $83, $20, $00, $00, $00   ; enc(5.0)
IN_CARRY_A: DB   $7F, $71, $5A, $00, $00   ; enc(30893/65536)
IN_CARRY_B: DB   $7D, $14, $0C, $00, $00   ; enc(18950/2**18)
EXP_3_0:    DB   $82, $40, $00, $00, $00   ; add(enc(1.0), enc(2.0)) = sub(enc(5.0), enc(2.0)) = 3.0
EXP_5_0:    DB   $83, $20, $00, $00, $00   ; add(enc(4.0), enc(1.0))
EXP_CARRY:  DB   $80, $0B, $2E, $80, $00   ; add(enc(30893/65536), enc(18950/2**18))

PASS_TEST:
    ld   a, 4                    ; green: all checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1-3, 5) failed
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
    INCLUDE "core/fpcore.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p8_rom0.bin", $0000, $4000
