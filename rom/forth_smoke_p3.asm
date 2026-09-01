; ============================================================================
; rom/forth_smoke_p3.asm — Phase 3 smoke ROM: outer interpreter + colon
; compiler
;
; Proves core/interp.asm's WORD/FIND/NUMBER/INTERPRET_RUN and the `:`/`;`
; colon compiler all work together, on top of Phase 2's already-proven
; core/dict.asm primitives. Same shape as rom/forth_smoke.asm (Phase 2):
; one smoke ROM, a fixed self-test with known-correct results, border
; reports pass/fail. rom/forth_smoke.asm itself is untouched — Phase 2's
; proof stays independent and immutable, exactly like rom/main.asm did
; for Phase 2.
;
; INCLUDE ORDER: core/dict.asm and core/interp.asm are INCLUDEd AFTER
; DEVICE/ORG $0000 and the fixed RST vector table, not before — see
; docs/PROJECT_PLAN.md's Phase 2 section for why this bit twice on the
; first file that got it wrong (H_DROP landed at address 0 and was
; overwritten by the vector table's own padding). Not repeating that
; mistake here.
;
; SELF-TEST, run as two separate INTERPRET_RUN calls over fixed source
; strings (a real interactive REPL is later work — see core/interp.asm's
; own header):
;   1. "5 3 + " with STATE already 0 (interpreting) -> top of stack
;      should be 8 after WORD/NUMBER/FIND/EXECUTE all cooperate with no
;      compiling involved at all.
;   2. ": DOUBLE DUP + ; 4 DOUBLE " -> defines DOUBLE (a word that
;      doubles the top of the stack) via the colon compiler, then
;      interprets "4 DOUBLE" using the JUST-COMPILED word, found via
;      the ordinary FIND path (DOUBLE's header was appended onto LATEST
;      by W_COLON, same as any other dictionary entry) -> top of stack
;      should be 8.
;
; Border goes GREEN (4) if both checks pass; otherwise it shows which
; checkpoint (1 or 2) failed, matching rom/forth_smoke.asm's own
; diagnostic convention. A completely unrecognized token (a bug in this
; file's own test source, not expected in normal operation) is reported
; as border color 9-and-up is impossible (only 3 border bits exist), so
; INTERPRET_UNKNOWN_WORD below uses color 7 (white) instead, chosen to
; not collide with either real checkpoint number this test uses.
;
; Build:
;   sjasmplus rom/forth_smoke_p3.asm
;   (produces forth_smoke_p3_rom0.bin, 16K, per the SAVEBIN at the end)
;
; Run:
;   fuse --machine ts2068 --rom-ts2068-0 build/forth_smoke_p3_rom0.bin \
;        --rom-ts2068-1 <a real EXROM image> -- see rom/forth_smoke.asm's
;   own header for why a real image, not a blank placeholder, is what
;   this project's own Fuse setup needs for trustworthy results.
; ============================================================================

    INCLUDE "include/hardware.inc"     ; constants only -- see
                                        ; rom/forth_smoke.asm's own note on
                                        ; why this is safe before ORG, and
                                        ; core/*.asm is not

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
    ld   sp, $FF00              ; return stack -- see core/dict.asm's own
                                 ; provisional-address caveat
    ld   ix, DSTACK_TOP         ; data stack

    ld   hl, DICT_LATEST_INIT_P3
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a              ; start interpreting, not compiling

; ---- checkpoint 1: "5 3 + " with no compiling involved ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_A
    ld   de, TEST_SRC_A_LEN
    call INTERPRET_RUN
    ld   de, 8
    call CHECK_TOP
    call W_DROP                  ; stack: []

; ---- checkpoint 2: define DOUBLE, then use it ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, TEST_SRC_B
    ld   de, TEST_SRC_B_LEN
    call INTERPRET_RUN
    ld   de, 8
    call CHECK_TOP
    call W_DROP                  ; stack: []

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
    ld   a, 4                    ; green: both checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1 or 2) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:          ; core/interp.asm's hook for a token that's
                                  ; neither a known word nor a valid number --
                                  ; see this file's own header on the color
                                  ; choice
    ld   a, 7                    ; white: bug in this file's own test source,
                                  ; not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8114         ; 1 byte, alongside core/interp.asm's own
                                  ; Phase 3 scratch cells (see that file)

TEST_SRC_A:     DB "5 3 + "
TEST_SRC_A_LEN  EQU $ - TEST_SRC_A
TEST_SRC_B:     DB ": DOUBLE DUP + ; 4 DOUBLE "
TEST_SRC_B_LEN  EQU $ - TEST_SRC_B

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 -- see this file's own
; header on why that ordering is load-bearing, not stylistic ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p3_rom0.bin", $0000, $4000
