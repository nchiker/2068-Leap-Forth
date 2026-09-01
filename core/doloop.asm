; ============================================================================
; core/doloop.asm — Phase 16: DO/LOOP and I
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT,
; same convention as core/control.asm and the rest). Does NOT need
; core/control.asm itself — DO/LOOP use their own custom runtime
; routines (DO_RT/LOOP_RT below), not QBRANCH/BRANCH.
;
; WHAT THIS ADDS — the counted loop this project has deferred since
; Phase 4, comparable to BASIC's FOR/NEXT:
;   DO   ( limit start -- )  IMMEDIATE   starts a counted loop from
;             start up to (but not including) limit
;   LOOP ( -- )               IMMEDIATE   increments the loop index and
;             branches back to DO if it hasn't reached limit yet
;   I    ( -- index )                     pushes the current (innermost)
;             loop's index
;
; No `LEAVE` (early exit) and no `+LOOP` (custom step) — the smallest
; provable slice, matching this project's own established practice
; (core/loop.asm's WHILE/REPEAT explicitly deferred LEAVE-equivalent
; functionality the same way).
;
; WHERE THE LOOP'S OWN LIMIT/INDEX LIVE — THE REAL DESIGN QUESTION THIS
; PHASE WAS DEFERRED OVER SINCE PHASE 14: real Forth systems keep a
; loop's limit/index on a SEPARATE return stack, safe from disturbance
; because ordinary CALL/RET-based execution inside the loop body always
; pushes and pops its own return addresses in balanced pairs, never
; touching what's underneath. This project doesn't have a separate
; return stack — but it doesn't need one, either: this whole codebase's
; subroutine-threading model already uses the real Z80 hardware stack
; (SP) as ITS OWN return stack, in exactly that same sense, for every
; CALL/RET pair since Phase 2. DO/LOOP below just push the loop's own
; limit/index onto that SAME hardware stack, underneath whatever the
; loop body's own CALLs push and pop on top of them — which is safe for
; the identical reason it's always been safe for QBRANCH/BRANCH
; (core/control.asm) and DOLIT/DOSTR (core/interp.asm/core/dotquote.asm)
; to manipulate their own return addresses directly: every dictionary
; word in this project, without exception, is CALLed and RETs exactly
; once, so anything pushed before a balanced stretch of such calls is
; still there, undisturbed, once that stretch finishes. This also means
; nested DO loops work correctly with no special handling: an inner
; loop's limit/index sit ABOVE an outer loop's own, and are fully
; removed by the inner loop's own LOOP before the outer loop's LOOP
; ever runs again — verified directly, not just reasoned about, by
; rom/forth_smoke_p16.asm's own checkpoint 2.
;
; A REAL, KNOWN FORTH GOTCHA, NOT A BUG HERE: plain DO (unlike ANS
; Forth's separate ?DO) never checks whether start already equals limit
; before running the body — the body always runs at least once, and if
; start and limit are EQUAL going in, LOOP's own index will increment
; past limit and keep looping for a full 65536-count wraparound before
; ever exactly matching it again. This is standard, well-documented
; Forth behavior, not a defect introduced here, and this project has no
; ?DO — avoid ever writing `n n DO ... LOOP` (matching, not exceeding,
; the limit on the same value as the start).
; ============================================================================

    IFNDEF CORE_DOLOOP_ASM
    DEFINE CORE_DOLOOP_ASM

; ============================================================================
; DO_RT — NOT a dictionary word. Runtime half of DO: pops (limit,
; start) off the DATA stack and pushes them onto the Z80 hardware stack
; instead, in the order LOOP_RT/I both expect (index on top, limit
; underneath it) — see this file's own header for why the hardware
; stack is the right place for them. Must pop and re-push its OWN
; return address around this, exactly like DOLIT/DOSTR already do
; around their own inline data, so RET still resumes in the right
; place (the loop body, right after DO's own compiled call).
; ============================================================================
DO_RT:
    pop  hl                  ; hl = our own return address (continues
                              ; into the loop body once we RET)
    ld   e, (ix+0)            ; de = start (the loop's initial index) --
    ld   d, (ix+1)            ; TOS, per "limit start DO"
    inc  ix
    inc  ix
    ld   c, (ix+0)            ; bc = limit -- NOS
    ld   b, (ix+1)
    inc  ix
    inc  ix
    push bc                  ; limit, deeper
    push de                  ; index, on top
    push hl                  ; restore our own return address on top,
                              ; so RET continues correctly
    ret

; ============================================================================
; LOOP_RT — NOT a dictionary word. Runtime half of LOOP: reads its own
; inline branch-back target (the same idiom QBRANCH/BRANCH already
; use), increments the loop index sitting on the hardware stack, and
; either restores (index, limit) and branches back to DO if the
; incremented index hasn't reached limit yet, or leaves them popped and
; falls through past the inline target — ending the loop — if it has.
; ============================================================================
LOOP_RT:
    pop  hl                  ; hl = address of the inline 2-byte
                              ; branch-back target DO's own compile-time
                              ; address was compiled into
    pop  de                  ; de = current index
    pop  bc                  ; bc = limit
    inc  de                  ; de = incremented index
    ld   a, d
    cp   b
    jr   nz, .continue
    ld   a, e
    cp   c
    jr   nz, .continue
    ; incremented index == limit: loop is finished. index/limit stay
    ; popped (not restored) -- fall through past the inline target.
    inc  hl
    inc  hl
    push hl
    ret
.continue:
    push bc                  ; limit, restored to its original depth
    push de                  ; incremented index, back on top
    ld   e, (hl)
    inc  hl
    ld   d, (hl)              ; de = the branch-back target (DO's own
                              ; loop-start address)
    push de
    ret

; ============================================================================
; DO ( limit start -- )  IMMEDIATE
; ============================================================================
H_DO:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   $82, "D", "O"        ; length 2, IMMEDIATE
W_DO:
    ld   hl, DO_RT
    call COMPILE_CALL
    ld   hl, (HERE)            ; remember the loop-start address (right
                                ; after DO_RT's own compiled call) for
                                ; LOOP to branch back to
    call DPUSH_HL
    ret

; ============================================================================
; LOOP ( -- )  IMMEDIATE
; ============================================================================
H_LOOP:
    DW   H_DO
    DB   $84, "L", "O", "O", "P"   ; length 4, IMMEDIATE
W_LOOP:
    ld   hl, LOOP_RT
    call COMPILE_CALL
    call DPOP_HL                ; hl = DO's remembered loop-start address
    call COMPILE_WORD
    ret

; ============================================================================
; I ( -- index )
; Reads the innermost loop's current index directly off the Z80
; hardware stack (SP+2/SP+3, skipping I's own 2-byte return address),
; non-destructively — ADD HL,SP copies SP into HL without disturbing
; anything, so nothing here needs its own pop/push pair around a peek.
; ============================================================================
H_I:
    DW   H_LOOP
    DB   1, "I"
W_I:
    ld   hl, 0
    add  hl, sp
    inc  hl
    inc  hl
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl
    call DPUSH_HL
    ret

DICT_LATEST_INIT_DOLOOP EQU H_I   ; head of the dictionary once this
                                   ; file's own words are included

    ENDIF
