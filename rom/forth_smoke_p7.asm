; ============================================================================
; rom/forth_smoke_p7.asm — Phase 7 smoke ROM: storage (SAVE, LOAD)
;
; Proves core/storage.asm's SAVE/LOAD wiring: filename handling, the
; LATEST-prefixed payload format, and HERE/LATEST restoration after a
; simulated fresh boot. Uses kernel/storage's own STORAGE_TEST_FAKE_SEND
; /STORAGE_TEST_FAKE_RECEIVE hooks (conditional-compilation switches
; already present in kernel/storage/storage.asm, unused until now) with
; this file's own fake in-memory "tape" standing in for real cassette
; timing — see core/storage.asm's own header for exactly what this does
; and does NOT prove (real tape wire-format compatibility in an actual
; emulator is a real, separate, still-open gap, not silently covered by
; this test).
;
; INCLUDE ORDER: same rule as every earlier smoke ROM. Only
; kernel/storage is needed — not kernel/math/io/graphics/sound, and not
; core/control.asm or core/ts2068.asm, since this test never uses IF,
; PLOT, or any other word from those files.
;
; SELF-TEST, two independent save/load round-trips sharing one fake
; tape (the second's SAVE appends after the first's, and its LOAD reads
; from wherever the first's LOAD left the fake read position — proving
; sequential blocks on the same tape work, not just a single isolated
; round-trip):
;   1. Define DOUBLER, SAVE it as "PROG1", reset the dictionary to a
;      simulated fresh-boot state (DOUBLER is now gone), LOAD "PROG1"
;      by its exact name, then call DOUBLER -> top of stack 8. Proves
;      an explicit-name LOAD finds and restores a real, callable word.
;   2. Define TRIPLER, SAVE it as "PROG2", reset the dictionary again,
;      LOAD with no name at all (a wildcard), then call TRIPLER -> top
;      of stack 15. Proves the wildcard path.
;
; Border goes GREEN (4) if both round-trips pass; otherwise it shows
; the failing checkpoint's number (1-2), matching every earlier smoke
; ROM's convention.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEFINE STORAGE_TEST_FAKE_SEND
    DEFINE STORAGE_TEST_FAKE_RECEIVE

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

    call RESET_DICT
    xor  a
    ld   (FAKE_TAPE_WPOS), a
    ld   (FAKE_TAPE_WPOS+1), a
    ld   (FAKE_TAPE_RPOS), a
    ld   (FAKE_TAPE_RPOS+1), a

; ---- checkpoint 1: define, SAVE, reset, LOAD by exact name, use ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_1A
    ld   de, SRC_1A_LEN
    call INTERPRET_RUN

    call RESET_DICT

    ld   hl, SRC_1B
    ld   de, SRC_1B_LEN
    call INTERPRET_RUN
    ld   de, 8
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: define, SAVE, reset, LOAD by wildcard, use ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_2A
    ld   de, SRC_2A_LEN
    call INTERPRET_RUN

    call RESET_DICT

    ld   hl, SRC_2B
    ld   de, SRC_2B_LEN
    call INTERPRET_RUN
    ld   hl, SRC_2C
    ld   de, SRC_2C_LEN
    call INTERPRET_RUN
    ld   de, 15
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
RESET_DICT:                      ; simulates a fresh boot: the RAM
                                  ; dictionary is gone, only the
                                  ; ROM-resident words remain
    ld   hl, DICT_LATEST_INIT_P7
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ret

CHECK_TOP:                       ; DE = expected top-of-stack value
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: both round-trips passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1-2) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $87A0         ; 1 byte, right before FAKE_TAPE_WPOS/
                                  ; RPOS below (see those for the rest
                                  ; of this project's own address-safety
                                  ; discipline)

SRC_1A:    DB ": DOUBLER DUP + ; SAVE PROG1 "
SRC_1A_LEN EQU $ - SRC_1A
SRC_1B:    DB "LOAD PROG1 4 DOUBLER "
SRC_1B_LEN EQU $ - SRC_1B
SRC_2A:    DB ": TRIPLER DUP DUP + + ; SAVE PROG2 "
SRC_2A_LEN EQU $ - SRC_2A
SRC_2B:    DB "LOAD "
SRC_2B_LEN EQU $ - SRC_2B
SRC_2C:    DB "5 TRIPLER "
SRC_2C_LEN EQU $ - SRC_2C

; ============================================================================
; Fake tape — test-harness-only, NOT part of core/storage.asm and NOT
; how this project's real SAVE/LOAD ever behaves. Each block is stored
; sequentially as [type:1][length:2][data:length bytes]; SEND appends,
; RECEIVE reads forward from wherever the last RECEIVE (or the initial
; reset above) left off. No end-of-tape detection, no support for
; skipping a non-matching block to search further — this smoke test's
; own sources never need either (checkpoint 1's LOAD matches on its
; first and only attempt; see this file's own header for why searching
; past a mismatch isn't exercised here).
; ============================================================================
FAKE_TAPE_WPOS EQU $87A2
FAKE_TAPE_RPOS EQU $87A4
FAKE_TAPE_BUF  EQU $8800

STORAGE_TEST_SEND_BLOCK:         ; A = type, IX = data ptr, DE = length
    push af
    ld   hl, (FAKE_TAPE_WPOS)
    ld   bc, FAKE_TAPE_BUF
    add  hl, bc
    pop  af
    ld   (hl), a
    inc  hl
    ld   (hl), e
    inc  hl
    ld   (hl), d
    inc  hl
.copyloop:
    ld   a, d
    or   e
    jr   z, .copydone
    ld   a, (ix+0)
    ld   (hl), a
    inc  ix
    inc  hl
    dec  de
    jr   .copyloop
.copydone:
    ld   de, FAKE_TAPE_BUF
    or   a
    sbc  hl, de
    ld   (FAKE_TAPE_WPOS), hl
    ret

STORAGE_TEST_RECEIVE_BLOCK:      ; A = expected type, carry-in = load(set)
                                  ; /verify(clear), IX = dest ptr,
                                  ; DE = expected length (unused by
                                  ; this fake -- the stored length
                                  ; is authoritative instead, since
                                  ; this harness always sends exactly
                                  ; what it means to receive)
    ld   c, a
    push af                       ; preserve entry carry across the
                                  ; comparisons below (push/pop af is
                                  ; safe here: no early pop-before-push,
                                  ; unlike the real bug this exact
                                  ; mistake caused in rom/forth_smoke.asm's
                                  ; own debug instrumentation once —
                                  ; see docs/PROJECT_PLAN.md's Phase 2
                                  ; section. Different here because
                                  ; nothing between this push and its
                                  ; matching pop below sets a flag this
                                  ; routine's own caller still needs.)
    ld   hl, (FAKE_TAPE_RPOS)
    ld   de, FAKE_TAPE_BUF
    add  hl, de
    ld   a, (hl)
    cp   c
    jr   nz, .fail
    inc  hl
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    inc  hl
    pop  af
    jr   c, .do_receive
    ; "verify" mode is never exercised by this project's own callers
    ; (STORAGE_LOAD always loads) -- treated identically to load here
    ; rather than implemented separately, since it would otherwise be
    ; dead code with no way to confirm it's even correct.
.do_receive:
.copyloop:
    ld   a, d
    or   e
    jr   z, .copydone
    ld   a, (hl)
    ld   (ix+0), a
    inc  hl
    inc  ix
    dec  de
    jr   .copyloop
.copydone:
    ld   de, FAKE_TAPE_BUF
    or   a
    sbc  hl, de
    ld   (FAKE_TAPE_RPOS), hl
    or   a
    ret
.fail:
    pop  af
    scf
    ret

; ---- kernel + dictionary: included here, after the vector table and
; the self-test code above, not before ORG $0000 ----
    INCLUDE "include/sysvars.inc"    ; kernel/storage/storage.asm, unlike
                                      ; every other kernel/ module this
                                      ; project has included so far,
                                      ; does NOT INCLUDE this itself --
                                      ; it assumes its own includer
                                      ; already has
    INCLUDE "kernel/storage/storage.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
    INCLUDE "core/storage.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p7_rom0.bin", $0000, $4000
