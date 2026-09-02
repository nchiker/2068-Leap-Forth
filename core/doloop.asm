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
;   LEAVE ( -- )              IMMEDIATE   compiled inside a DO...LOOP
;             (or DO...+LOOP) body, exits the loop immediately once
;             reached, skipping the rest of the body and any remaining
;             passes
;   +LOOP ( step -- )         IMMEDIATE   like LOOP, but increments the
;             index by `step` (which may be negative) instead of
;             always 1, ending the loop once that crosses the boundary
;             between limit-1 and limit rather than testing for exact
;             equality
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
;
; LEAVE'S OWN DESIGN QUESTION: LEAVE must compile an unconditional
; branch to wherever the loop ends — but LEAVE is always compiled
; BEFORE that address is known (LOOP/+LOOP, which is what fixes it,
; hasn't been reached yet). This is the same forward-reference problem
; IF and WHILE already solve (core/control.asm/core/loop.asm) by
; leaving a placeholder address on the borrowed compile-time stack for
; a later word to patch — but LEAVE can occur any number of times
; inside one loop body (including zero), and DO/WHILE/IF's own
; one-placeholder-per-word bookkeeping has no way to track "some
; unknown number of pending patches." The fix: thread the placeholders
; together into a LINKED LIST, using each placeholder's own still-blank
; inline bytes as the "next" pointer (exactly how DICT_CHAIN_POINT
; threads dictionary headers together, just applied to compiled code
; instead), so only a single value -- the list's head -- needs to be
; tracked per loop nesting level.
;
; A REAL BUG CAUGHT HERE, NOT JUST REASONED AROUND: the obvious place
; to keep that one head value is the SAME borrowed compile-time stack
; IF/WHILE/DO already use (push it once, on top of DO's own
; loop-start address, and expect it to still be on top when LOOP
; reads it back) -- and an early version of this file did exactly
; that. It's wrong, and a real Fuse run proved it wrong (garbage
; PRINT_ROW, zero output, execution never reaching PASS/FAIL at all):
; LEAVE is essentially always written as `IF LEAVE THEN`, and at the
; exact moment LEAVE compiles, IF's own not-yet-patched placeholder is
; what's actually sitting on top of that shared stack, not the loop's
; own head -- IF hasn't reached its own THEN yet, so nothing has
; popped it. LEAVE would silently steal and corrupt IF's placeholder
; instead of reading the loop's real state. The borrowed stack works
; for DO/LOOP and IF/THEN and BEGIN/WHILE/REPEAT individually because
; each pair opens and fully closes with nothing of a DIFFERENT kind
; interleaved on top in between -- LEAVE breaks that assumption by
; design, since it's meant to be used nested inside a still-open IF.
;
; THE FIX: give LEAVE's own bookkeeping a SEPARATE home, immune to
; whatever IF/BEGIN placeholders happen to be sitting on the shared
; stack at the time -- a small fixed-size side table (LEAVE_HEAD_TABLE
; below), indexed by loop nesting depth (LEAVE_DEPTH), not by stack
; position. DO increments LEAVE_DEPTH and clears its new slot to 0
; (empty chain); LEAVE reads/writes ONLY the slot for the CURRENT
; depth (LEAVE_DEPTH-1), regardless of anything else compiling around
; it; LOOP/+LOOP patch that slot's whole chain once the true exit
; address is known, then decrement LEAVE_DEPTH -- which, since an
; outer loop's own slot is never touched while an inner one is open,
; automatically "restores" the outer loop's own pending chain with no
; explicit save/restore needed. DO's own loop-start address still
; lives on the ordinary borrowed stack (unchanged from before LEAVE
; existed) -- that value alone was never the problem, since IF/THEN
; always fully closes before LOOP is reached in well-formed code; only
; LEAVE's own bookkeeping needed to move out.
;
; LEAVE_DEPTH must start at 0 -- every ROM that INCLUDEs this file
; must zero it once in its own COLD_START, the same way STATE/LATEST/
; HERE already are (see rom/forth_boot.asm and rom/forth_smoke_p16.asm
; and rom/forth_smoke_p24.asm's own COLD_START for the one extra line
; this required). LEAVE_HEAD_TABLE is sized for 8 levels of loop
; nesting, generously beyond anything this project's own code uses --
; like every other structural assumption in this file (matching start/
; limit on a plain DO, balanced IF/THEN), exceeding it is not checked
; at runtime.
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
; LEAVE_RT — NOT a dictionary word. Runtime half of LEAVE: by the time
; this runs, LOOP/+LOOP has already patched its inline target to the
; real loop-exit address (compilation always finishes the whole
; DO...LOOP before any of it runs). Discards the current loop's
; index/limit from the hardware stack -- safe to do unconditionally,
; for the same reason `I` can safely peek them non-destructively
; (nothing between DO and here has disturbed them, this file's own
; header explains why) -- then branches to that now-resolved target.
; ============================================================================
LEAVE_RT:
    pop  hl                  ; hl = address of the inline 2-byte target
    ld   e, (hl)
    inc  hl
    ld   d, (hl)              ; de = the resolved loop-exit address
    pop  hl                  ; discard the current loop's index
    pop  hl                  ; discard the current loop's limit
    push de
    ret

; ============================================================================
; PATCH_LEAVE_CHAIN — NOT a dictionary word. Shared compile-time helper
; for LOOP and +LOOP (see this file's own header for the linked-list
; design). Entry: HL = the loop's LEAVE chain head (0 if no LEAVEs were
; compiled), DE = the resolved loop-exit address. Walks the chain,
; overwriting each node's own inline placeholder (which up to now held
; the address of the PREVIOUS node -- its "next" link) with DE instead,
; until it reaches a node whose own link is 0.
; ============================================================================
PATCH_LEAVE_CHAIN:
    ld   a, h
    or   l
    ret  z                   ; head == 0 -- chain empty (or exhausted)
    ld   c, (hl)
    inc  hl
    ld   b, (hl)              ; bc = this node's own "next" link
    dec  hl                   ; hl back to this node's own start address
    ld   (hl), e
    inc  hl
    ld   (hl), d              ; overwrite this node with the real target
    ld   h, b
    ld   l, c                 ; hl = next node -- continue the walk
    jr   PATCH_LEAVE_CHAIN

; ============================================================================
; PLUSLOOP_RT — NOT a dictionary word. Runtime half of +LOOP. Unlike
; LOOP_RT, which can test for exact equality because it always
; increments by 1 and therefore can never step past `limit` without
; landing on it first, +LOOP's step can be any value (including
; negative), so the index can jump clean OVER `limit` without ever
; equaling it. The standard fix (used by real Forth systems for the
; same reason): compare the SIGN of (index - limit) before and after
; adding the step. Once that sign flips, the index has crossed from
; "before limit" to "at-or-past limit" (or vice versa, for a negative
; step counting down through it) -- which is exactly the crossing
; +LOOP is specified to detect, without needing an exact match. A step
; of 0 never changes the sign and therefore never terminates -- an
; ambiguous case by the same standard, not a defect here (matching
; DO's own already-documented start-equals-limit gotcha).
; ============================================================================
; NOT placed right after core/decimal.asm's own DIVISOR10 ($87BD,
; ending at $87BF) -- that range is NOT actually free: core/print.asm's
; PRINT_ROW/PRINT_COL/EMIT_CHAR_TMP occupy $87C8-$87CA, and a real
; +LOOP body almost always prints on every pass (as this project's own
; smoke test does), so its scratch is LIVE at the same time as
; PRINT_ROW/PRINT_COL, unlike the float/mode64 scratch blocks earlier
; in this same $87xx range, which safely overlap each other only
; because those features never run interleaved with one another. This
; block instead starts right after core/ts2068.asm's own CURRENT_ATTR
; ($87CB, 1 byte) -- the last claimed byte in the whole $87xx range as
; of this writing (verified directly, not assumed, by grepping every
; existing "EQU $87.." across core/, kernel/, and include/ before
; picking this address -- the earlier, wrong assumption cost a real,
; reproduced bug: see this file's own PROJECT_PLAN.md entry).
PL_TARGET EQU $87CC   ; 2 bytes: pointer to +LOOP's inline branch target
PL_INDEX  EQU $87CE   ; 2 bytes: the loop's index before this step
PL_LIMIT  EQU $87D0   ; 2 bytes: the loop's limit
PL_NEWIDX EQU $87D2   ; 2 bytes: index after adding the step
PL_DOLD   EQU $87D4   ; 2 bytes: (index - limit) before stepping
PL_DNEW   EQU $87D6   ; 2 bytes: (new index - limit) after stepping --
                       ; ends at $87D8
PLUSLOOP_RT:
    pop  hl
    ld   (PL_TARGET), hl
    pop  hl
    ld   (PL_INDEX), hl
    pop  hl
    ld   (PL_LIMIT), hl
    ld   e, (ix+0)             ; step, from the DATA stack (TOS)
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   hl, (PL_INDEX)
    add  hl, de                ; hl = index + step
    ld   (PL_NEWIDX), hl
    ld   hl, (PL_INDEX)
    ld   de, (PL_LIMIT)
    or   a
    sbc  hl, de                ; hl = index - limit (before stepping)
    ld   (PL_DOLD), hl
    ld   hl, (PL_NEWIDX)
    ld   de, (PL_LIMIT)
    or   a
    sbc  hl, de                ; hl = new index - limit (after stepping)
    ld   (PL_DNEW), hl
    ld   a, (PL_DOLD+1)         ; high byte -- its top bit is the sign
    ld   hl, PL_DNEW+1
    xor  (hl)
    and  $80
    jr   nz, .terminate         ; sign bits differ -- boundary crossed
.continue:
    ld   hl, (PL_LIMIT)
    push hl                     ; limit, restored to its original depth
    ld   hl, (PL_NEWIDX)
    push hl                     ; stepped index, back on top
    ld   hl, (PL_TARGET)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                ; de = the branch-back target (DO's own
                                ; loop-start address)
    push de
    ret
.terminate:
    ; boundary crossed: index/limit stay popped (not restored) -- fall
    ; through past the inline target, ending the loop.
    ld   hl, (PL_TARGET)
    inc  hl
    inc  hl
    push hl
    ret

; ============================================================================
; DO ( limit start -- )  IMMEDIATE
; ============================================================================
LEAVE_DEPTH      EQU $87D8   ; 1 byte: current DO nesting depth (0 =
                              ; no loop open). MUST be zeroed once by
                              ; every including ROM's own COLD_START --
                              ; see this file's own header.
LEAVE_HEAD_TABLE EQU $87D9   ; 8 slots x 2 bytes = 16 bytes: this
                              ; nesting level's own pending-LEAVE chain
                              ; head, indexed by LEAVE_DEPTH-1 -- ends
                              ; at $87E9

; ============================================================================
; LEAVE_SLOT_ADDR_CALC — NOT a dictionary word. Returns in HL the
; address of LEAVE_HEAD_TABLE's slot for the CURRENT innermost loop
; (index LEAVE_DEPTH-1). Shared by LEAVE (to thread a new placeholder
; into that loop's own chain) and LOOP/+LOOP (to read the finished
; chain for patching) -- see this file's own header for why this
; lives in its own side table rather than the borrowed compile-time
; (data) stack IF/BEGIN/DO's own loop-start address still use.
; ============================================================================
LEAVE_SLOT_ADDR_CALC:
    ld   a, (LEAVE_DEPTH)
    dec  a
    ld   l, a
    ld   h, 0
    add  hl, hl                 ; hl = (LEAVE_DEPTH-1) * 2 -- byte offset
    ld   de, LEAVE_HEAD_TABLE
    add  hl, de
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
                                ; LOOP/+LOOP to branch back to
    call DPUSH_HL
    ; open a fresh, empty LEAVE chain for this (possibly nested) loop
    ld   a, (LEAVE_DEPTH)
    inc  a
    ld   (LEAVE_DEPTH), a
    call LEAVE_SLOT_ADDR_CALC   ; hl = &LEAVE_HEAD_TABLE[LEAVE_DEPTH-1]
    xor  a
    ld   (hl), a
    inc  hl
    ld   (hl), a
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
    call LEAVE_SLOT_ADDR_CALC    ; hl = &LEAVE_HEAD_TABLE[LEAVE_DEPTH-1]
                                  ; -- MUST run before the (HERE) read
                                  ; just below: it clobbers DE as part
                                  ; of its own address arithmetic (a
                                  ; real bug, caught by a genuinely
                                  ; erratic Fuse run, not just review --
                                  ; the old order left DE holding
                                  ; LEAVE_HEAD_TABLE's own address
                                  ; instead of the loop-exit address,
                                  ; so every LEAVE jumped into RAM data
                                  ; instead of past the loop)
    ld   c, (hl)
    inc  hl
    ld   b, (hl)                 ; bc = this loop's own chain head
    ld   de, (HERE)               ; de = the true loop-exit address, now
                                   ; that everything above is compiled
    push bc
    pop  hl                      ; hl = chain head (PATCH_LEAVE_CHAIN's
                                  ; own entry register)
    call PATCH_LEAVE_CHAIN
    ld   a, (LEAVE_DEPTH)        ; this loop is done -- back out to
    dec  a                       ; whatever nesting level was open
    ld   (LEAVE_DEPTH), a        ; before it (its own slot, untouched
                                  ; while this one was open, is exactly
                                  ; where it left it)
    ret

; ============================================================================
; LEAVE ( -- )  IMMEDIATE
; Compiles a call to LEAVE_RT followed by a placeholder branch target,
; and threads that placeholder into the CURRENT innermost loop's own
; pending-LEAVE chain (LEAVE_HEAD_TABLE, indexed by LEAVE_DEPTH -- see
; this file's own header) so LOOP/+LOOP can patch it once the real
; loop-exit address is known.
; ============================================================================
H_LEAVE:
    DW   H_LOOP
    DB   $85, "L", "E", "A", "V", "E"   ; length 5, IMMEDIATE
W_LEAVE:
    ld   hl, LEAVE_RT
    call COMPILE_CALL
    call LEAVE_SLOT_ADDR_CALC    ; hl = &LEAVE_HEAD_TABLE[LEAVE_DEPTH-1]
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                 ; de = the chain's OLD head
    dec  hl                      ; hl = the slot's own address again
    push hl                      ; stashed briefly on the Z80 hardware
                                  ; stack -- safe: symmetric push/pop
                                  ; within this one routine's own body,
                                  ; not crossing any CALL/RET boundary
                                  ; (core/control.asm's W_ELSE documents
                                  ; this same technique)
    ld   hl, (HERE)               ; hl = this new chain node's own
                                   ; address (the placeholder about to
                                   ; be written)
    push hl
    ex   de, hl                   ; hl = the OLD head, to compile as
                                   ; this node's own "next" link
    call COMPILE_WORD             ; threads the chain
    pop  de                       ; de = this new node's own address
    pop  hl                       ; hl = the slot's own address
    ld   (hl), e
    inc  hl
    ld   (hl), d                  ; LEAVE_HEAD_TABLE[LEAVE_DEPTH-1] =
                                   ; this new node -- the chain's new head
    ret

; ============================================================================
; +LOOP ( step -- )  IMMEDIATE
; Like LOOP, but its runtime half (PLUSLOOP_RT) increments the index by
; `step` (which may be negative) instead of always 1, and tests for
; crossing the limit rather than exact equality — see PLUSLOOP_RT's own
; header for why exact equality isn't safe once the step isn't 1.
; ============================================================================
H_PLUSLOOP:
    DW   H_LEAVE
    DB   $85, "+", "L", "O", "O", "P"   ; length 5, IMMEDIATE
W_PLUSLOOP:
    ld   hl, PLUSLOOP_RT
    call COMPILE_CALL
    call DPOP_HL                ; hl = DO's remembered loop-start address
    call COMPILE_WORD
    call LEAVE_SLOT_ADDR_CALC    ; must run before the (HERE) read below
                                  ; -- see W_LOOP's own note on why
    ld   c, (hl)
    inc  hl
    ld   b, (hl)
    ld   de, (HERE)
    push bc
    pop  hl
    call PATCH_LEAVE_CHAIN
    ld   a, (LEAVE_DEPTH)
    dec  a
    ld   (LEAVE_DEPTH), a
    ret

; ============================================================================
; I ( -- index )
; Reads the innermost loop's current index directly off the Z80
; hardware stack (SP+2/SP+3, skipping I's own 2-byte return address),
; non-destructively — ADD HL,SP copies SP into HL without disturbing
; anything, so nothing here needs its own pop/push pair around a peek.
; ============================================================================
H_I:
    DW   H_PLUSLOOP
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
