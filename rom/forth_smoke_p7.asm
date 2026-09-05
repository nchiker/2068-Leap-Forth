; ============================================================================
; rom/forth_smoke_p7.asm — Phase 7 smoke ROM: storage (SAVE-LIB, LOAD-LIB)
;
; Proves core/storage.asm's SAVE-LIB/LOAD-LIB wiring: filename handling,
; the LATEST-prefixed payload format, HERE/LATEST restoration after a
; simulated fresh boot, AND (added when SAVE/LOAD were renamed
; SAVE-LIB/LOAD-LIB and a real, live buffer-overflow bug was found and
; fixed in W_SAVELIB — see core/storage.asm's own header for the full
; writeup) the fix itself: a real round trip bigger than the OLD
; 512-byte ceiling, and a real refusal of a dictionary bigger than the
; NEW 8190-byte ceiling. Uses kernel/storage's own STORAGE_TEST_FAKE_SEND
; /STORAGE_TEST_FAKE_RECEIVE hooks (conditional-compilation switches
; already present in kernel/storage/storage.asm, unused until this
; phase) with this file's own fake in-memory "tape" standing in for
; real cassette timing — see core/storage.asm's own header for exactly
; what this does and does NOT prove (real tape wire-format
; compatibility in an actual emulator is a real, separate, still-open
; gap, not silently covered by this test).
;
; NEW DEPENDENCY: core/storage.asm's W_SAVELIB now THROWs -8 on
; overflow, so this file must also INCLUDE core/throwcatch.asm (with
; THROW_CATCH_ENABLED defined before core/interp.asm) — a real, new
; requirement this ROM didn't have before, exactly matching
; core/tick.asm's own precedent for its -13. core/throwcatch.asm's own
; uncaught path references FSTACK_TOP (core/float.asm), which this
; minimal ROM doesn't otherwise need — declared locally as a literal
; below (matching rom/forth_smoke_p52.asm's own precedent of locally
; redeclaring a constant rather than pulling in a whole extra file for
; one symbol) rather than INCLUDEing core/float.asm just for this.
;
; INCLUDE ORDER: same rule as every earlier smoke ROM. Only
; kernel/storage is needed — not kernel/math/io/graphics/sound, and not
; core/control.asm or core/ts2068.asm, since this test never uses IF,
; PLOT, or any other word from those files.
;
; SELF-TEST, FOUR checkpoints (numbered 1, 2, 3, 5 — deliberately
; skipping 4, since PASS_TEST's own border color IS 4/green; a failing
; checkpoint 4 would show the same border as a full pass, the exact
; "CHECKPOINT_NUM==4==PASS-color" trap this project has been bitten by
; before — see rom/forth_smoke_p46.asm's own identical numbering gap
; for the established precedent) sharing one fake tape (each SAVE-LIB
; appends after the previous one's; each LOAD-LIB reads from wherever
; the previous LOAD-LIB left the fake read position):
;   1. Define DOUBLER, SAVE-LIB it as "PROG1", reset the dictionary to a
;      simulated fresh-boot state (DOUBLER is now gone), LOAD-LIB
;      "PROG1" by its exact name, then call DOUBLER -> top of stack 8.
;      Proves an explicit-name LOAD-LIB finds and restores a real,
;      callable word.
;   2. Define TRIPLER, SAVE-LIB it as "PROG2", reset the dictionary
;      again, LOAD-LIB with no name at all (a wildcard), then call
;      TRIPLER -> top of stack 15. Proves the wildcard path.
;   3. THE FIX, positive case: define BIGDEF, a single word compiled to
;      well over 512 bytes (200 DUP/DROP pairs padding out its body,
;      6 bytes each = 1200 bytes, plus its literals/header — comfortably
;      past the OLD 512-byte ceiling, comfortably under the NEW
;      8190-byte one), SAVE-LIB it, poison the RAM dictionary region
;      with $FF (stronger than checkpoints 1/2's pointer-only reset,
;      matching rom/forth_smoke_p52.asm's own RESET_AND_POISON
;      technique), LOAD-LIB it back, and confirm BIGDEF still computes
;      the right answer (10) — direct proof the larger buffer actually
;      works end-to-end, not just that it's bigger on paper. Also reads
;      SAVE_DICT_LEN back directly and confirms it really was > 512,
;      so this checkpoint can't silently pass by accident with a
;      smaller-than-intended payload.
;   4. (checkpoint number 5) THE FIX, negative case: without spending
;      ROM budget compiling an 8KB+ real definition, HERE is set
;      directly to FORTH_DICT_RAM + SAVE_LOAD_MAX_DICT + 100 (a
;      deterministic, legitimate way to simulate "the dictionary has
;      grown past the ceiling" — the overflow check runs and refuses
;      BEFORE anything ever reads the FORTH_DICT_RAM..HERE span, so it
;      does not matter that this span isn't real compiled data). A
;      canary byte is planted immediately past SAVE_LOAD_TEMP_BUF's own
;      end, and the fake tape's write position is recorded. SAVE-LIB is
;      then attempted (wrapped in CATCH, the same technique
;      rom/forth_smoke_p46.asm's own checkpoint 6 already established
;      for a deliberately-throwing xt) and must produce -8; the canary
;      and the tape's write position must both be completely unchanged
;      afterward — direct proof the refusal touches neither adjacent
;      memory nor the tape, not just that *some* number came back.
;
; Border goes GREEN (4) if all four checkpoints pass; otherwise it
; shows the failing checkpoint's number (1, 2, 3, or 5), matching every
; earlier smoke ROM's convention. White (7) means a bug in this file's
; own test harness (an unknown word, or an uncaught throw that should
; have been caught), not a real checkpoint failure.
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
    ld   (CATCH_DEPTH), a        ; required once at cold start by
                                  ; core/throwcatch.asm's own header
    ld   (FAKE_TAPE_WPOS), a
    ld   (FAKE_TAPE_WPOS+1), a
    ld   (FAKE_TAPE_RPOS), a
    ld   (FAKE_TAPE_RPOS+1), a

; ---- checkpoint 1: define, SAVE-LIB, reset, LOAD-LIB by exact name, use ----
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

; ---- checkpoint 2: define, SAVE-LIB, reset, LOAD-LIB by wildcard, use ----
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

; ---- checkpoint 3: THE FIX, positive case -- a payload well over the
; OLD 512-byte ceiling round-trips correctly ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_3A
    ld   de, SRC_3A_LEN
    call INTERPRET_RUN

    ; confirm this checkpoint actually exercised a payload bigger than
    ; the OLD ceiling -- not just trusting SRC_3A's own byte count by
    ; eye
    ld   hl, (SAVE_DICT_LEN)
    ld   de, 512
    or   a
    sbc  hl, de
    jp   c, FAIL_TEST             ; SAVE_DICT_LEN <= 512: this
                                   ; checkpoint didn't test what it
                                   ; claims to
    jp   z, FAIL_TEST

    call RESET_AND_POISON

    ld   hl, SRC_3B
    ld   de, SRC_3B_LEN
    call INTERPRET_RUN
    ld   de, 10
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 5 (see this file's own header for why 4 is skipped):
; THE FIX, negative case -- a dictionary bigger than the NEW ceiling is
; refused cleanly, touching neither the canary just past
; SAVE_LOAD_TEMP_BUF's own end nor the tape ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a

    ld   hl, FORTH_DICT_RAM + SAVE_LOAD_MAX_DICT + 100
    ld   (HERE), hl

    ld   a, $42
    ld   (CANARY_ADDR), a

    ld   hl, (FAKE_TAPE_WPOS)
    ld   (SAVED_WPOS_CHECK), hl

    ld   hl, TEST_XT_SAVE_OVERFLOW
    call DPUSH_HL
    call W_CATCH
    ld   de, -8
    call CHECK_TOP
    call W_DROP

    ld   hl, (FAKE_TAPE_WPOS)
    ld   de, (SAVED_WPOS_CHECK)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST             ; the tape must be completely untouched

    ld   a, (CANARY_ADDR)
    cp   $42
    jp   nz, FAIL_TEST             ; memory just past the buffer must be
                                    ; completely untouched

    ld   hl, FORTH_DICT_RAM        ; restore sane state (not load-bearing
    ld   (HERE), hl                ; for this test, just good hygiene)

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
RESET_DICT:                      ; simulates a fresh boot: the RAM
                                  ; dictionary is gone, only the
                                  ; ROM-resident words remain (which now
                                  ; includes THROW/CATCH -- the true
                                  ; tail is H_CATCH, not
                                  ; DICT_LATEST_INIT_P7/H_LOADLIB, since
                                  ; core/throwcatch.asm is chained on
                                  ; after core/storage.asm below)
    ld   hl, H_CATCH
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ret

RESET_AND_POISON:                ; same as RESET_DICT, but also
                                  ; overwrites the RAM dictionary region
                                  ; with $FF first, so checkpoint 3's
                                  ; pass can't be explained by leftover
                                  ; state from before the "boot" --
                                  ; matches rom/forth_smoke_p52.asm's
                                  ; own RESET_AND_POISON technique
    ld   hl, FORTH_DICT_RAM
    ld   de, FORTH_DICT_RAM+1
    ld   bc, 4095
    ld   (hl), $FF
    ldir
    jp   RESET_DICT

CHECK_TOP:                       ; DE = expected top-of-stack value
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1/2/3/5) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

; ============================================================================
; RUNTIME_ERROR_HOOK -- required now that core/throwcatch.asm is
; INCLUDEd (THROW_CATCH_ENABLED). Checkpoint 5's own -8 throw is always
; wrapped in an active CATCH; reaching this at all means something
; escaped a CATCH that should have absorbed it, so it uses the same
; white "something's wrong" signal INTERPRET_UNKNOWN_WORD does, not a
; numbered checkpoint.
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   a, 7
    out  (PORT_ULA), a
.hang:
    jr   .hang

; ============================================================================
; TEST_XT_SAVE_OVERFLOW -- a raw "xt" (see core/throwcatch.asm's own
; header for why any code address ending in `ret` qualifies) that
; attempts SAVE-LIB while HERE is deliberately past the ceiling, letting
; W_SAVELIB's own -8 THROW escape up to checkpoint 5's own CATCH.
; ============================================================================
TEST_XT_SAVE_OVERFLOW:
    ld   hl, SRC_SAVE_TOOBIG
    ld   de, SRC_SAVE_TOOBIG_LEN
    call INTERPRET_RUN
    ret

CHECKPOINT_NUM     EQU $87A0    ; 1 byte
FAKE_TAPE_WPOS     EQU $87A2    ; 2 bytes
FAKE_TAPE_RPOS     EQU $87A4    ; 2 bytes
SAVED_WPOS_CHECK   EQU $87A6    ; 2 bytes -- checkpoint 5's own scratch,
                                ; right after the fake tape's own
                                ; read/write positions
CANARY_ADDR EQU SAVE_LOAD_TEMP_BUF + 8192   ; = $F000 given today's
                                ; SAVE_LOAD_TEMP_BUF ($D000) -- one byte
                                ; immediately past core/storage.asm's own
                                ; buffer, exactly where an unchecked
                                ; overflow would land first

SRC_1A:    DB ": DOUBLER DUP + ; SAVE-LIB PROG1 "
SRC_1A_LEN EQU $ - SRC_1A
SRC_1B:    DB "LOAD-LIB PROG1 4 DOUBLER "
SRC_1B_LEN EQU $ - SRC_1B
SRC_2A:    DB ": TRIPLER DUP DUP + + ; SAVE-LIB PROG2 "
SRC_2A_LEN EQU $ - SRC_2A
SRC_2B:    DB "LOAD-LIB "
SRC_2B_LEN EQU $ - SRC_2B
SRC_2C:    DB "5 TRIPLER "
SRC_2C_LEN EQU $ - SRC_2C

; ---- checkpoint 3's own payload: BIGDEF compiles to well over 512
; bytes (200 DUP/DROP pairs, 6 bytes each via COMPILE_CALL = 1200
; bytes, plus its own literals/header) purely to exceed the OLD
; ceiling -- the DUP/DROP pairs are net no-ops, so BIGDEF still
; deterministically leaves 10 on the stack (7, 200x no-op, then 3 +) ----
SRC_3A:    DB ": BIGDEF 7 "
    REPT 200
    DB "DUP DROP "
    ENDR
    DB "3 + ; SAVE-LIB PROG3 "
SRC_3A_LEN EQU $ - SRC_3A
SRC_3B:    DB "LOAD-LIB PROG3 BIGDEF "
SRC_3B_LEN EQU $ - SRC_3B

SRC_SAVE_TOOBIG: DB "SAVE-LIB TOOBIG "
SRC_SAVE_TOOBIG_LEN EQU $ - SRC_SAVE_TOOBIG

; ============================================================================
; Fake tape — test-harness-only, NOT part of core/storage.asm and NOT
; how this project's real SAVE-LIB/LOAD-LIB ever behaves. Each block is
; stored sequentially as [type:1][length:2][data:length bytes]; SEND
; appends, RECEIVE reads forward from wherever the last RECEIVE (or the
; initial reset above) left off. No end-of-tape detection, no support
; for skipping a non-matching block to search further — this smoke
; test's own sources never need either (each checkpoint's LOAD-LIB
; matches on its first and only attempt; see this file's own header for
; why searching past a mismatch isn't exercised here). Checkpoints 1-3
; share this one fake tape in sequence (checkpoint 5 never reaches
; STORAGE_SAVE at all, by design, so it adds nothing to it).
;
; PLACEMENT: NOT $8800 (the original Phase 7 value) any more. Checkpoint
; 3's own payload (~1.2KB, deliberately bigger than the OLD 512-byte
; ceiling) pushes the fake tape's real end well past $8800+1276 =
; ~$8CFC — which used to physically overlap core/throwcatch.asm's own
; CATCH_TMP_SP/IX/IY/CATCH_DEPTH/CATCH_STACK ($890F-$8945), a REAL bug
; caught by this file's own checkpoint 5 hanging (CATCH_DEPTH silently
; clobbered by checkpoint 3's own tape write, so checkpoint 5's later
; CATCH/THROW restored SP from garbage and crashed) — not guessed, root-
; caused with temporary border-color progress markers inserted at each
; checkpoint step until the hang's exact location narrowed down to
; "immediately after CATCH_STACK-region corruption, inside the very
; next CATCH/THROW"). $8950 sits comfortably past CATCH_STACK's own end
; ($8946), leaving $8950-$97FF (2736 bytes) for the fake tape -- more
; than double what checkpoints 1-3 combined actually need (~1.3KB).
; ============================================================================
FAKE_TAPE_BUF  EQU $8950

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
    DEFINE THROW_CATCH_ENABLED   ; core/storage.asm's own SAVE-LIB now
                                  ; THROWs -8 on overflow -- a real, new
                                  ; dependency on core/throwcatch.asm
                                  ; below, which needs this defined
                                  ; before core/interp.asm for
                                  ; THROW_ROOT_SP to exist (see
                                  ; core/storage.asm's own header)
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON   ; see core/control.asm's own header
    INCLUDE "core/storage.asm"
DICT_CHAIN_POINT DEFL H_LOADLIB
    ; core/throwcatch.asm's own uncaught-throw path references
    ; FSTACK_TOP (normally core/float.asm) -- declared locally as a
    ; literal instead of INCLUDEing that whole file for one symbol this
    ; minimal ROM otherwise has no use for, matching
    ; rom/forth_smoke_p52.asm's own precedent of locally redeclaring a
    ; constant it needs without pulling in its real owning file.
FSTACK_TOP EQU $9000
    INCLUDE "core/throwcatch.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p7_rom0.bin", $0000, $4000
