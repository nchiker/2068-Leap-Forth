; ============================================================================
; rom/forth_smoke.asm — Phase 2 smoke ROM: dictionary header format,
; subroutine-threaded primitives, data stack
;
; Purpose: prove core/dict.asm's dictionary header layout, the IX-based
; data stack convention, and the eight Phase 2 primitives (DUP SWAP DROP
; OVER + - @ !) all work together on real/emulated hardware, in exactly
; the spirit of rom/main.asm's own Milestone 0 — one smoke ROM, one
; visible pass/fail result, nothing else required to already exist. This
; file duplicates main.asm's RST-vector/stack-init boilerplate rather
; than including it, because main.asm is Milestone 0's own historical
; proof and is not meant to change; the two smoke ROMs are independent.
;
; No kernel/ dependency on purpose — this only needs core/dict.asm and
; the border port to report its result, matching main.asm's own
; "isolate the thing actually being proven" reasoning. EMIT/KEY (which
; DO need kernel/io and kernel/graphics) are the next increment, once
; this one is confirmed working — see docs/PROJECT_PLAN.md Phase 2.
;
; Self-test: runs a fixed sequence of pushes and primitive calls with
; known correct results (see inline commentary for the stack trace at
; each step), checking the top of the data stack after each stage.
; Border goes GREEN (4) and the machine halts in a tight loop once every
; check passes; if any check fails, the border instead shows that check's
; 1-7 checkpoint number (see CHECK_TOP/FAIL_TEST below) so a regression
; identifies itself without a debugger. No screen text output is needed
; to read the result.
;
; Build:
;   sjasmplus rom/forth_smoke.asm
;   (produces forth_smoke_rom0.bin, 16K, per the SAVEBIN line at the end)
;
; Run:
;   fuse --machine ts2068 --rom-ts2068-0 build/forth_smoke_rom0.bin \
;        --rom-ts2068-1 <any 8K file>
;   A content-free (e.g. all-$FF) 8K placeholder for --rom-ts2068-1
;   produced visibly different, seemingly-hung behavior from a real
;   EXROM image on this project's own Fuse 1.9.1/ts2068 setup during
;   this file's own bring-up, even though this ROM never pages EXROM in
;   at all -- root cause not yet isolated (see docs/PROJECT_PLAN.md
;   Phase 0 for where TS2068 memory-map surprises like this belong).
;
;   UPDATE 2026-09-04: investigated further by reading Fuse 1.9.1's own
;   real source (machines/ts2068.c, machine.c, peripherals/scld.c) and
;   ZEsarUX's own (machines/timex.c, cpu.c) -- neither does anything
;   content-dependent with the EXROM buffer; both do a plain length-
;   checked byte copy. Root cause of the original $FF misbehavior still
;   not confirmed (most likely something other than byte content, e.g.
;   a file-size mismatch during that historical bring-up), but a real,
;   non-degenerate placeholder is cheap insurance either way:
;   tools/make_exrom_placeholder.sh generates build/stock_shaped_exrom.bin
;   (8192 bytes, all $00/NOP rather than $FF/RST $38), visually confirmed
;   passing rom/forth_smoke_p50.asm in real Fuse. Use that instead of an
;   ad hoc all-$FF file.
; ============================================================================

    INCLUDE "include/hardware.inc"     ; constants only, no code emitted --
                                        ; safe before DEVICE/ORG are set.
                                        ; core/dict.asm is NOT included here:
                                        ; it emits real dictionary code, so
                                        ; it must land after ORG $0000 and
                                        ; the fixed RST vector table below,
                                        ; not before either exists -- see
                                        ; where it's INCLUDEd near the end
                                        ; of this file.

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
    ret                     ; unreached: COLD_START never executes EI

    DS   $0066 - $, $FF
NMI_ENTRY:
    retn

    DS   $0100 - $, $FF

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ; Return stack. Provisional placeholder, same status as main.asm's own
    ; SP value — see core/dict.asm's DSTACK_TOP comment on why none of
    ; these addresses are final yet.
    ld   sp, $FF00

    ; Data stack.
    ld   ix, DSTACK_TOP

    ; Seed LATEST/HERE for the benefit of Phase 3, even though nothing in
    ; this smoke test exercises dictionary growth yet — proving the seed
    ; values are reachable and correctly formed is cheap to do now and
    ; saves a surprise later.
    ld   hl, DICT_LATEST_INIT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl

; ============================================================================
; Self-test — see file header for the full rationale. Each stage's
; expected stack contents are noted inline; DE holds the expected
; top-of-stack value going into CHECK_TOP, which jumps to FAIL_TEST on
; any mismatch and never returns in that case.
; ============================================================================

    ; ---- +, DUP, chained + : (5 3 +) (4 DUP + +) -> 8, then 8+8 -> 16 ----
    ld   hl, 5
    call TEST_PUSH
    ld   hl, 3
    call TEST_PUSH
    call W_PLUS             ; stack: [8]
    ld   de, 8
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP

    ld   hl, 4
    call TEST_PUSH           ; stack: [8, 4]
    call W_DUP                ; stack: [8, 4, 4]
    call W_PLUS                ; stack: [8, 8]
    call W_PLUS                 ; stack: [16]
    ld   de, 16
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP

    ; ---- OVER, - : stack [16], push 100, OVER copies the 16 back to the
    ; top (a b -- a b a), then - computes second-minus-top (100-16=84)
    ld   hl, 100
    call TEST_PUSH           ; stack: [16, 100]
    call W_OVER               ; stack: [16, 100, 16]
    call W_MINUS               ; a=100 (second), b=16 (top): a-b = 84
    ld   de, 84
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP           ; stack: [16, 84]

    call W_DROP              ; stack: [16]
    ld   de, 16
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP

    call W_DROP              ; stack: []

    ; ---- SWAP ----
    ld   hl, 1
    call TEST_PUSH
    ld   hl, 2
    call TEST_PUSH           ; stack: [1, 2]
    call W_SWAP               ; stack: [2, 1]
    ld   de, 1
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP
    call W_DROP              ; stack: [2]
    ld   de, 2
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP
    call W_DROP              ; stack: []

    ; ---- @ and ! ----
    ld   hl, 1234
    call TEST_PUSH
    ld   hl, TEST_CELL
    call TEST_PUSH           ; stack: [1234, TEST_CELL]
    call W_STORE             ; stack: []; (TEST_CELL) = 1234
    ld   hl, TEST_CELL
    call TEST_PUSH           ; stack: [TEST_CELL]
    call W_FETCH              ; stack: [1234]
    ld   de, 1234
    ld   a, 7
    ld   (CHECKPOINT_NUM), a
    call CHECK_TOP
    call W_DROP              ; stack: []

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words, never CALLed by
; anything outside this file ----
TEST_PUSH:                  ; HL -> pushed onto the data stack
    dec  ix
    dec  ix
    ld   (ix+0), l
    ld   (ix+1), h
    ret

CHECK_TOP:                  ; DE = expected top-of-stack value (not popped).
                             ; (CHECKPOINT_NUM) must already hold the
                             ; calling site's checkpoint number (each call
                             ; site sets it just before CALLing here) --
                             ; FAIL_TEST shows it as the border color, so a
                             ; mismatch identifies exactly which stage
                             ; failed without needing a debugger. NOT
                             ; carried through A/push-af across the sbc
                             ; below: an earlier attempt at that clobbered
                             ; the very Z flag the jr nz needs, since AF
                             ; includes the flags register -- routing it
                             ; through memory instead sidesteps that
                             ; entirely.
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jr   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                ; green: every checkpoint passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                  ; border shows which checkpoint (1-7) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

TEST_CELL      EQU $9006     ; scratch RAM cell for the @/! check only —
                             ; same provisional-address caveat as
                             ; core/dict.asm's DSTACK_TOP/LATEST/HERE
CHECKPOINT_NUM EQU $9008     ; see CHECK_TOP/FAIL_TEST above

; ---- dictionary: included here, not at the top of the file, precisely so
; its code lands in real ROM space after the fixed vector table above
; instead of at whatever address happened to be current before ORG $0000
; was even set (that ordering mistake corrupted H_DROP/W_DROP under the
; vector table on the first attempt at this file -- RST_00's own `di`/`jp`
; bytes and the RST_08 DS-padding silently overwrote them, since nothing
; had asserted ORG $0000 yet when core/dict.asm's first bytes were
; emitted). Confirmed by comparing the .sym file's addresses (W_DROP
; landed at $0007, inside the RST vector region) against a real Fuse run
; failing at the very first arithmetic check -- while a z80sim run of the
; same routines in isolation (bypassing the real boot chain entirely)
; passed, which is what pointed at the boot chain itself as the actual
; site of the bug rather than the arithmetic.
    INCLUDE "core/dict.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_rom0.bin", $0000, $4000
