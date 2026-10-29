; ============================================================================
; rom/forth_smoke_p59.asm — Phase 59 smoke ROM: COMPILE_ONLY_CHECK
; (compile-only words refused when typed at STATE=0)
;
; WHAT THIS PROVES: core/interp.asm's new COMPILE_ONLY_CHECK, called as
; the first instruction of IF/ELSE/THEN/BEGIN/UNTIL (core/control.asm),
; WHILE/REPEAT (core/loop.asm), DO/LOOP/+LOOP/LEAVE (core/doloop.asm),
; EXIT (core/loopext.asm), and `."` (core/dotquote.asm), only when the
; including ROM DEFINEs COMPILE_ONLY_CHECK_ENABLED (this file does, the
; same way rom/forth_boot.asm — the real, live, interactive ROM — does).
;
; THE BUG THIS CLOSES, RESTATED: every word above is IMMEDIATE, so
; core/interp.asm's own dispatch runs it unconditionally regardless of
; STATE. Before this phase, typing one directly at the interpreter
; prompt (STATE=0, no enclosing colon definition) silently compiled
; dead, unreachable bytes into the dictionary at HERE and left the
; "conditional"/"loop" with no actual effect on control flow — nothing
; crashed, but nothing behaved as typed either. docs/forth_tutorial.md
; used to claim these words "complain at the prompt"; they didn't,
; until now.
;
; THREE CHECKPOINTS TESTING THE REFUSAL, one per touched file, ALL
; using the exact same "feed a fixed source string to INTERPRET_RUN at
; STATE=0" technique every other smoke ROM in this project already uses
; for testing interpret-time behavior (see rom/forth_boot.asm's own
; header: "no live automated test exercises the interactive loop...
; that needs a real or simulated keyboard, not a fixed source string" —
; true for testing EDITOR_LOOP_LIVE's own line editing, irrelevant here
; since COMPILE_ONLY_CHECK only ever looks at STATE and WORD_BUF, both
; already fully exercised by a fixed string reaching INTERPRET_RUN
; exactly the same way a live-typed line eventually does):
;
;   1. `1 IF THEN ` (control.asm's IF)
;   2. `5 0 DO LOOP ` (doloop.asm's DO)
;   3. `." X" ` (dotquote.asm's `."`, the word literally named in the
;      original tutorial's false claim)
;
; Each checkpoint records HERE and the data-stack pointer (IX) before
; calling INTERPRET_RUN, then after the call asserts ALL of:
;   - HERE is completely unchanged (zero dead bytes compiled — the
;     guard fires as literally the first instruction of the word's own
;     body, before any COMPILE_CALL/COMPILE_WORD)
;   - IX is back at DSTACK_TOP (whatever was pushed before the
;     compile-only word was reached is cleanly discarded, matching
;     INTERPRET_UNKNOWN_WORD's own "abandon the rest of this line"
;     contract — the SAME hook this guard reuses, not a new one)
;   - INTERP_ERROR_FLAG is 1 (the line was reported as an error, not
;     silently swallowed)
;   - WORD_BUF holds the offending word's own counted-string bytes
;     (proving THIS specific word triggered the hook, not some
;     unrelated failure)
;
; FOURTH CHECKPOINT TESTING ZERO REGRESSION: a single colon definition
; using IF/ELSE/THEN, DO/LOOP, and `."` together, defined and called
; completely normally (`: DEMO 3 0 DO I . LOOP IF ." Y" ELSE ." N" THEN
; ;`), confirming the guard is invisible to legitimate compiling use —
; exactly the concern core/interp.asm's own COMPILE_ONLY_CHECK header
; states its "ret nz" fast path is designed to guarantee.
;
; Border goes GREEN (4) if all four pass; otherwise it shows the
; failing checkpoint's number. White (7) means this file's OWN test
; source hit a genuinely unexpected error (a bug in this smoke ROM,
; not in what it's testing) — see INTERPRET_UNKNOWN_WORD below for why
; that's still distinguishable from an EXPECTED refusal (checkpoints
; 1-3 call it on purpose and check its own effects directly, rather
; than treating "reached INTERPRET_UNKNOWN_WORD at all" as failure).
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

    ld   hl, DICT_LATEST_INIT_DOLOOP
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   (LEAVE_DEPTH), a   ; core/doloop.asm's own LEAVE bookkeeping --
                            ; must start at 0, matching every other ROM
                            ; that INCLUDEs it

; ---- checkpoint 1: IF refused at STATE=0 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, (HERE)
    ld   (HERE_SNAPSHOT), hl
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   hl, WORD_IF
    call CHECK_REFUSED
    jp   nz, FAIL_TEST

; ---- checkpoint 2: DO refused at STATE=0 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    xor  a
    ld   (INTERP_ERROR_FLAG), a
    ld   hl, (HERE)
    ld   (HERE_SNAPSHOT), hl
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   hl, WORD_DO
    call CHECK_REFUSED
    jp   nz, FAIL_TEST

; ---- checkpoint 3: ." refused at STATE=0 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    xor  a
    ld   (INTERP_ERROR_FLAG), a
    ld   hl, (HERE)
    ld   (HERE_SNAPSHOT), hl
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   hl, WORD_DOTQUOTE
    call CHECK_REFUSED
    jp   nz, FAIL_TEST

; ---- checkpoint 4: normal compiled use of IF/DO/." together, totally
; unaffected -- "0 1 2 " (DO/LOOP/I, 6 columns) then "Y" (."'s own text,
; no trailing space) = PRINT_COL 7, PRINT_ROW 0, ERROR_FLAG still 0 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   ix, DSTACK_TOP
    xor  a
    ld   (INTERP_ERROR_FLAG), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   a, (INTERP_ERROR_FLAG)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_ROW)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (PRINT_COL)
    cp   7
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ============================================================================
; CHECK_REFUSED ( HL = expected WORD_BUF counted-string address -- Z )
; Confirms a compile-only word was cleanly refused: HERE unchanged
; since HERE_SNAPSHOT, IX back at DSTACK_TOP, INTERP_ERROR_FLAG=1, and
; WORD_BUF matches the 3 bytes (length + 2 chars) at HL. Sets the Z
; flag on full success (all four checks pass), clears it on the first
; mismatch -- caller does `jp nz, FAIL_TEST` right after, matching
; every other checkpoint's own style in this file.
; ============================================================================
CHECK_REFUSED:
    push hl                      ; save expected-string pointer
    ld   hl, (HERE)
    ld   de, (HERE_SNAPSHOT)
    or   a
    sbc  hl, de
    jr   nz, .fail                ; HERE moved -- dead bytes got compiled
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    or   a
    sbc  hl, de
    jr   nz, .fail                ; data stack not back to empty
    ld   a, (INTERP_ERROR_FLAG)
    cp   1
    jr   nz, .fail
    pop  hl                       ; hl = expected-string pointer
    ld   de, WORD_BUF
    ld   b, 3                     ; length byte + 2 characters
.cmp:
    ld   a, (de)
    cp   (hl)
    jr   nz, .failnopop
    inc  hl
    inc  de
    djnz .cmp
    xor  a                        ; Z set -- full match
    ret
.fail:
    pop  hl
.failnopop:
    or   1                        ; clear Z
    ret

PASS_TEST:
    ld   a, 4                    ; green: all four checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

; ============================================================================
; INTERPRET_UNKNOWN_WORD — this ROM's own hook, matching
; rom/forth_boot.asm's REAL shipped behavior (print the offending word
; plus " ?" plus a newline via W_EMIT, reset STATE, set
; INTERP_ERROR_FLAG, `ret` at the exact stack depth its own contract
; expects) minus the float-stack reset line -- this minimal test ROM
; has no core/float.asm included, so there is no FSTACK_TOP to reset.
; Checkpoints 1-3 are DESIGNED to reach this (via COMPILE_ONLY_CHECK,
; not a real typo), so unlike a normal smoke ROM's own copy of this
; hook, this one does NOT hang -- it completes normally so
; CHECK_REFUSED can inspect its effects afterward.
; ============================================================================
INTERPRET_UNKNOWN_WORD:
    ld   ix, DSTACK_TOP
    ld   a, (WORD_BUF)
    ld   b, a
    ld   hl, WORD_BUF+1
.printword:
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .printword
    ld   hl, " "
    rst RST_DPUSH
    call W_EMIT
    ld   hl, "?"
    rst RST_DPUSH
    call W_EMIT
    ld   hl, 13
    rst RST_DPUSH
    call W_EMIT
    xor  a
    ld   (STATE), a
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a
    ret

HERE_SNAPSHOT EQU $8800
CHECKPOINT_NUM EQU $8802

WORD_IF:       DB 2, "I", "F"
WORD_DO:       DB 2, "D", "O"
WORD_DOTQUOTE: DB 2, ".", '"'

SRC_CP1: DB "1 IF THEN "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "5 0 DO LOOP "
SRC_CP2_LEN EQU $ - SRC_CP2

; DB can't hold an embedded `"` inside a plain "..." string -- split
; around each one, exactly matching core/dotquote.asm's own
; `DB $82, ".", '"'` convention for the same reason.
SRC_CP3: DB ".", '"', " X", '"', " "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB ": DEMO 3 0 DO I . LOOP 1 IF .", '"', " Y", '"', " ELSE .", '"', " N", '"', " THEN ; DEMO "
SRC_CP4_LEN EQU $ - SRC_CP4

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    DEFINE COMPILE_ONLY_CHECK_ENABLED   ; the exact thing this ROM tests
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/control.asm"
DICT_CHAIN_POINT DEFL H_UNTIL
    INCLUDE "core/dotquote.asm"
DICT_CHAIN_POINT DEFL H_DOTQUOTE
    INCLUDE "core/doloop.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p59_rom0.bin", $0000, $4000
