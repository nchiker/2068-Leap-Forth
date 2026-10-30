; ============================================================================
; core/interp.asm — Phase 3: outer interpreter and colon compiler
;
; Builds on core/dict.asm (must be INCLUDEd first — this file uses
; DPUSH_HL/DPOP_HL, LATEST, HERE, and extends the dictionary chain
; starting from H_STORE). Still zero kernel/ dependency: input comes
; from a fixed in-memory source buffer (INTERPRET_RUN takes an address
; and length), not a live keyboard yet — see docs/PROJECT_PLAN.md
; Phase 3 for why that's still the right scope for this step.
;
; WHAT THIS ADDS, ANS-Forth-ish names in parentheses:
;   W_WORD     (WORD)   — parse the next blank-delimited token
;   FIND       (FIND)   — dictionary search, also reports the IMMEDIATE bit
;   NUMBER     (NUMBER) — parse a token as a signed decimal literal
;   DOLIT      (LIT)    — runtime support for a compiled numeric literal
;   W_COLON    (:)      — begin a new definition, switch to compile state
;   W_SEMICOLON (;)     — IMMEDIATE; end a definition, switch back
;   INTERPRET_RUN        — the outer interpreter's main loop
;
; DICTIONARY EXTENSION: `:` and `;` are real dictionary words, chained
; onto core/dict.asm's H_STORE (Phase 2's last entry), so FIND locates
; them exactly like any other word — no special-casing them in
; INTERPRET_RUN. DICT_LATEST_INIT_P3 (bottom of this file) is what a
; Phase-3-or-later ROM must seed LATEST with, NOT core/dict.asm's own
; DICT_LATEST_INIT (which stops at H_STORE and stays correct for Phase
; 2's own smoke ROM, unmodified).
;
; IMMEDIATE MECHANISM: LENFLAGS bit 7 (see core/dict.asm's header
; format comment). FIND reports it; INTERPRET_RUN is the only place
; that acts on it. This is deliberately the first and only IMMEDIATE
; word so far (`;`) — enough to prove the mechanism generalizes to
; future compiling words (IF/ELSE/THEN etc., Phase 4) without building
; more of it than Phase 3 needs to prove.
;
; ONE DELIMITER: a plain space ($20). Tabs/CR are not handled — every
; test source in this project's own smoke ROMs is a hand-written string
; literal, so this hasn't mattered yet; a live keyboard front end
; (later) will need to widen this.
;
; ONE ERROR PATH: an unrecognized token (not a dictionary word, not a
; valid number) is fatal for now — INTERPRET_RUN has no error recovery,
; it isn't a live REPL yet. See rom/forth_smoke_p3.asm for how a smoke
; ROM reports that case.
; ============================================================================

    IFNDEF CORE_INTERP_ASM
    DEFINE CORE_INTERP_ASM

; ============================================================================
; W_WORD ( -- addr )
; Skips leading whitespace (every byte from 0 to space: CR and TAB are
; delimiters too, audit step E1) from SRC_PTR, copies the next run of
; non-whitespace characters into WORD_BUF as a counted string (count byte, then the
; characters), advances SRC_PTR past what it consumed, and pushes
; WORD_BUF's address. An empty result (count byte = 0) means SRC_PTR
; had already reached SRC_END — the caller's signal that input is
; exhausted.
; ============================================================================
W_WORD:
.skip:
    ld   hl, (SRC_PTR)
    ld   de, (SRC_END)
    ld   a, h
    cp   d
    jr   nz, .skip_continue
    ld   a, l
    cp   e
    jr   z, .empty
.skip_continue:
    ld   a, (hl)
    cp   " " + 1             ; every byte from 0 to space is whitespace
    jr   nc, .foundstart     ; (CR and TAB included: the line store's CR-ended lines)
    inc  hl
    ld   (SRC_PTR), hl
    jr   .skip

.foundstart:
    ld   de, WORD_BUF+1
    ld   b, 0                ; count so far
.copyloop:
    ld   hl, (SRC_END)
    ld   a, h
    ld   c, l                ; c/a hold SRC_END briefly, freeing hl for SRC_PTR below
    ld   hl, (SRC_PTR)
    cp   h
    jr   nz, .copy_continue
    ld   a, c
    cp   l
    jr   z, .donecopy        ; SRC_PTR reached SRC_END: word ends here
.copy_continue:
    ld   a, (hl)
    cp   " " + 1
    jr   c, .donecopy_consume
    ; Uppercase a-z to A-Z before storing. REAL BUG, found only by a
    ; human typing at a live keyboard (rom/forth_boot.asm, confirmed
    ; via a real memory-dump snapshot showing WORD_BUF holding lowercase
    ; "border" after typing "5 BORDER"): every dictionary header this
    ; project has ever written is uppercase, and FIND (this file, below)
    ; is case-sensitive by design — a decision explicitly flagged back
    ; in Phase 3 as needing a real answer once live keyboard input
    ; existed ("a live REPL will need to decide a case-folding policy"),
    ; not caught until it did. Folding to uppercase here, once, is
    ; simpler than making FIND case-insensitive (would need to repeat
    ; the fold on every comparison, every call) or than uppercasing at
    ; the keyboard-scan layer (kernel/io is inherited, hardware-facing,
    ; and shared with 2068-Leap's own conventions -- not this project's
    ; to change for a language-level policy choice).
    cp   "a"
    jr   c, .not_lower
    cp   "z" + 1
    jr   nc, .not_lower
    sub  "a" - "A"
.not_lower:
    ld   (de), a
    inc  de
    inc  hl
    ld   (SRC_PTR), hl
    inc  b
    ld   a, b
    cp   32
    jr   nc, .donecopy       ; truncate at 32 chars, safety net
    jr   .copyloop
.donecopy_consume:
    inc  hl
    ld   (SRC_PTR), hl       ; consume the delimiter itself
.donecopy:
    ld   a, b
    ld   (WORD_BUF), a
    ld   hl, WORD_BUF
    rst RST_DPUSH
    ret

.empty:
    xor  a
    ld   (WORD_BUF), a
    ld   hl, WORD_BUF
    rst RST_DPUSH
    ret

; ============================================================================
; FIND ( addr -- code_addr imm found )
; addr must be a counted string in WORD_BUF's format. Searches the
; dictionary from LATEST backward. found=1 and imm=(0 or 1) on a match;
; found=0 (addr pushed back unchanged, imm not meaningful) otherwise.
; Case-sensitive — see this file's own header on why that's acceptable
; for now; every header this project writes and every smoke-test source
; string is already uppercase.
; ============================================================================
FIND:
    rst RST_DPOP
    ld   (FIND_SEARCH_ADDR), hl
    ld   hl, (LATEST)
.loop:
    ld   a, h
    or   l
    jr   z, .notfound
    ld   (FIND_HEADER_ADDR), hl
    ld   de, 2
    add  hl, de
    ld   a, (hl)                  ; raw LENFLAGS (length + IMMEDIATE bit)
    ld   (FIND_RAW_LENFLAGS), a
    and  $1F
    ld   c, a                     ; c = name length
    ld   hl, (FIND_SEARCH_ADDR)
    ld   a, (hl)
    cp   c
    jr   nz, .next
    inc  hl                       ; hl -> search string's chars
    ld   de, (FIND_HEADER_ADDR)
    inc  de
    inc  de
    inc  de                       ; de -> header's name chars
    ld   a, c
    or   a
    jr   z, .match                ; zero-length name: trivially equal
    ld   b, c
.cmploop:
    ld   a, (de)
    cp   (hl)
    jr   nz, .next
    inc  hl
    inc  de
    djnz .cmploop
.match:
    ld   hl, (FIND_HEADER_ADDR)
    ld   de, 3
    add  hl, de
    ld   d, 0
    ld   e, c
    add  hl, de                   ; hl = code address (header + 3 + namelen)
    rst RST_DPUSH
    ld   a, (FIND_RAW_LENFLAGS)
    and  $80
    ld   hl, 0
    jr   z, .notimm
    ld   hl, 1
.notimm:
    rst RST_DPUSH
    ld   hl, 1
    rst RST_DPUSH
    ret
.next:
    ld   hl, (FIND_HEADER_ADDR)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl                   ; hl = link (previous header)
    jr   .loop
.notfound:
    ld   hl, (FIND_SEARCH_ADDR)
    rst RST_DPUSH
    ld   hl, 0
    rst RST_DPUSH
    ret

; ============================================================================
; NUMBER ( addr -- n flag )
; addr must be a counted string. flag=1 and n=the parsed value on
; success; flag=0 (n=0, not meaningful) if the string is empty, is a
; lone "-", or contains any non-digit.
; With DECIMAL_NUMBER_ENABLED (core/fpparse.asm): a token with a point or an
; exponent is a float, pushed on the float stack, and the stack effect is
; ( addr -- 2 ); an integer outside -32768..65535 or a float beyond the
; float range is THROW -43 (docs/V2/FLOAT_SPEC.md section 6).
; ============================================================================
NUMBER:
    rst RST_DPOP
    ld   a, (hl)
    or   a
    jp   z, .fail                 ; JP, not JR: with and without
                                   ; DECIMAL_NUMBER_ENABLED the distance
                                   ; to .fail changes, and tools/
                                   ; check_z80_opcodes.py flags a JR
                                   ; within 10 bytes of its limit
    IFDEF DECIMAL_NUMBER_ENABLED
    jp   NUMBER_PARSE             ; core/fpparse.asm: integers, floats and
                                   ; their range errors in one routine
                                   ; (HL -> the token, A = its length);
                                   ; the integer loop below is not
                                   ; assembled. A ROM that does not
                                   ; define DECIMAL_NUMBER_ENABLED keeps
                                   ; this NUMBER byte for byte.
    ELSE
    ld   (NUM_COUNT), a
    inc  hl
    ld   (NUM_PTR), hl
    xor  a
    ld   (NUM_NEG), a
    ld   a, (hl)
    cp   "-"
    jr   nz, .noneg
    ld   a, 1
    ld   (NUM_NEG), a
    inc  hl
    ld   (NUM_PTR), hl
    ld   a, (NUM_COUNT)
    dec  a
    ld   (NUM_COUNT), a
    jr   z, .fail                 ; lone "-" is not a number
.noneg:
    ld   de, 0                    ; de = running magnitude
.digitloop:
    ld   a, (NUM_COUNT)
    or   a
    jr   z, .donedigits
    dec  a
    ld   (NUM_COUNT), a
    ld   hl, (NUM_PTR)
    ld   a, (hl)
    inc  hl
    ld   (NUM_PTR), hl
    cp   "0"
    jr   c, .fail
    cp   "9"+1
    jr   nc, .fail
    sub  "0"                      ; a = this digit, 0-9
    ld   l, a
    ld   h, 0
    push hl                       ; save the digit
    ld   h, d
    ld   l, e                     ; hl = old magnitude
    add  hl, hl                   ; *2
    ld   b, h
    ld   c, l                     ; bc = magnitude*2
    add  hl, hl                   ; *4
    add  hl, hl                   ; *8
    add  hl, bc                   ; magnitude*10
    pop  bc                       ; bc = digit
    add  hl, bc                   ; + digit
    ex   de, hl                   ; de = new magnitude
    jr   .digitloop
.donedigits:
    ld   a, (NUM_NEG)
    or   a
    jr   z, .positive
    xor  a
    sub  e
    ld   e, a
    ld   a, 0
    sbc  a, d
    ld   d, a
.positive:
    ex   de, hl                   ; hl = result
    rst RST_DPUSH
    ld   hl, 1
    rst RST_DPUSH
    ret
    ENDIF
.fail:
    ld   hl, 0
    rst RST_DPUSH
    ld   hl, 0
    rst RST_DPUSH
    ret

; ============================================================================
; DOLIT — runtime half of a compiled numeric literal.
; A compiled literal is 5 bytes: CALL DOLIT, then the 2-byte value.
; DOLIT reads those 2 bytes from its own return address, pushes the
; value onto the data stack, then corrects the return address to skip
; past them before returning — the standard inline-literal idiom for a
; subroutine/direct-threaded Forth. NOT a dictionary word; nothing ever
; FINDs it by name, only COMPILE_LITERAL ever CALLs it (indirectly, by
; compiling a CALL to it).
; ============================================================================
DOLIT:
    pop  hl                       ; hl = address of the 2-byte literal
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    inc  hl                       ; hl = real continuation address
    push hl
    ex   de, hl
    rst RST_DPUSH
    ret

; ============================================================================
; COMPILE_CALL ( HL = target address -- )  compiles "CALL target" (3
; bytes: $CD, target-low, target-high) at HERE, advancing HERE by 3.
; ============================================================================
COMPILE_CALL:
    ld   de, (HERE)
    ld   a, $CD
    ld   (de), a
    inc  de
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   (HERE), de
    ret

; ============================================================================
; COMPILE_LITERAL ( HL = value -- )  compiles a 5-byte inline literal
; (CALL DOLIT, then the value) at HERE — see DOLIT above.
; ============================================================================
COMPILE_LITERAL:
    push hl
    ld   hl, DOLIT
    call COMPILE_CALL
    pop  hl
    ld   de, (HERE)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   (HERE), de
    ret

; ============================================================================
; DICT_ROOM ( HL = n bytes about to be reserved -- ) the dictionary ceiling (audit step E2a).
; Returns, with HL unchanged, if HERE + n does not pass DICT_RAM_CEILING - 256; otherwise THROW -8.
; The 256 bytes below the ceiling are what a definition's body may still use before its `;`
; (a body is compiled with COMPILE_CALL/_BYTE/_WORD, which are not checked). Called at the top of
; every word that starts a definition or a data field (`:` CREATE VARIABLE CONSTANT ARRAY STRING;
; DICT_ROOM0 is n = 0) and by `,` `C,` ALLOT; it runs before the word changes HERE or LATEST.
; Unsigned: HERE + n carrying past $FFFF fails. Destroys: AF, DE. A ROM without THROW (the early
; smoke ROMs) gets a bare RET.
; ============================================================================
DICT_ROOM0:
    ld   hl, 0
DICT_ROOM:
    IFDEF THROW_CATCH_ENABLED
    push hl
    ld   de, (HERE)
    add  hl, de
    jr   c, .full
    ld   de, DICT_RAM_CEILING - 255
    sbc  hl, de                   ; carry clear from the add
    jr   nc, .full                ; HERE + n >= ceiling - 255
    pop  hl
    ret
.full:
    ld   hl, -8                   ; dictionary overflow (the SP left by the push is reset by THROW)
    rst  RST_DPUSH
    jp   W_THROW
    ELSE
    ret
    ENDIF

; ============================================================================
; COMPILE_BYTE ( A = byte -- )  compiles one raw byte at HERE. Used by
; `;` to compile a bare RET ($C9) — see W_SEMICOLON below.
; ============================================================================
COMPILE_BYTE:
    ld   hl, (HERE)
    ld   (hl), a
    inc  hl
    ld   (HERE), hl
    ret

; ============================================================================
; : ( "name" -- )
; Parses the next word as the new definition's name, builds a
; dictionary header for it at HERE (LINK = current LATEST, LENFLAGS =
; name length with the IMMEDIATE bit clear, then the name bytes),
; leaves HERE pointing just past the name (where the definition's own
; compiled code will start), updates LATEST to the new header, and
; switches to compile state. NOT itself IMMEDIATE — INTERPRET_RUN only
; ever executes `:`, never compiles a call to it (compiling one colon
; definition inside another isn't supported yet).
; ============================================================================
H_COLON:
    DW   H_STORE
    DB   1, ":"
W_COLON:
    call DICT_ROOM0
    call W_WORD
    rst RST_DPOP
    ld   (WORD_SRC_ADDR), hl

    ld   de, (HERE)
    ld   (NEW_HEADER_ADDR), de

    ld   hl, (LATEST)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de

    ld   hl, (WORD_SRC_ADDR)
    ld   a, (hl)                  ; name length (already <= 31, W_WORD truncates at 32)
    ld   (de), a
    inc  de
    inc  hl                       ; hl -> first name char

    ld   b, a
    ld   a, b
    or   a
    jr   z, .namedone
.namecopy:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .namecopy
.namedone:
    ld   (HERE), de
    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ld   a, 1
    ld   (STATE), a
    ret

; ============================================================================
; ; ( -- )  IMMEDIATE
; Compiles a bare RET, ending the current definition's straight-line
; CALL chain (subroutine threading — see core/dict.asm's own header),
; and switches back to interpret state. IMMEDIATE so INTERPRET_RUN
; executes it the instant it's read even while compiling, rather than
; compiling a call to it into the definition it's supposed to end.
; ============================================================================
H_SEMICOLON:
    DW   H_COLON
    DB   $81, ";"                 ; length 1, bit 7 set = IMMEDIATE
W_SEMICOLON:
    ld   a, $C9                   ; Z80 RET opcode
    call COMPILE_BYTE
    xor  a
    ld   (STATE), a
    ret

DICT_LATEST_INIT_P3 EQU H_SEMICOLON   ; head of the dictionary as of Phase 3;
                                      ; core/dict.asm's own DICT_LATEST_INIT
                                      ; (H_STORE) stays correct for Phase 2's
                                      ; own smoke ROM, unmodified

; ============================================================================
; INTERPRET_RUN ( HL = source address, DE = source length -- )
; Runs the outer interpreter over one fixed source buffer until W_WORD
; reports an empty token (input exhausted), then returns. This is a
; batch entry point, not a live REPL — see this file's own header.
;
; INTERPRET_NESTED is the same routine entered one instruction later: it
; does not snapshot THROW_ROOT_SP. THROW_ROOT_SP is therefore always the
; OUTERMOST run's SP, so an error in a nested run (LOAD-TEXT interpreting
; its text) unwinds (REPORT_INTERP_ERROR, THROW, ABORT, QUIT) all the way
; to the outermost caller, abandoning the nested text AND the rest of the
; outer line. A nested run that succeeds returns to its caller, which
; saves and restores SRC_PTR/SRC_END around it (core/loadtext.asm).
; ============================================================================
INTERPRET_RUN:
    IFDEF THROW_CATCH_ENABLED
    ld   (THROW_ROOT_SP), sp    ; Phase 45 -- core/throwcatch.asm's own
                                 ; THROW needs this to correctly unwind
                                 ; an UNCAUGHT throw from arbitrarily
                                 ; deep nested word calls back to
                                 ; exactly this same "one entry"
                                 ; invariant RUNTIME_ERROR_HOOK already
                                 ; requires (see that routine's own
                                 ; header, and STACK_CHECK's own
                                 ; violation path just below for the
                                 ; existing precedent this mirrors).
                                 ; Captured once, at the OUTERMOST
                                 ; INTERPRET_RUN's own entry (INTERPRET_NESTED
                                 ; skips it), not per-word: SP here is fixed
                                 ; for this entire call, since .loop's
                                 ; own dispatch always fully unwinds
                                 ; back to it between words.
    ENDIF
INTERPRET_NESTED:
    ld   (SRC_PTR), hl
    add  hl, de
    ld   (SRC_END), hl
    xor  a
    ld   (INTERP_ERROR_FLAG), a

.loop:
    IFDEF RUNTIME_ERROR_CHECK_ENABLED
    call STACK_CHECK    ; Phase 38 -- see this file's own header on why
                         ; this specific spot: every word this loop
                         ; dispatches returns control back to .loop
                         ; (either by falling through, or via the
                         ; pushed-return-address trick in .execute
                         ; below), so checking here catches the result
                         ; of EVERY word's own stack use without
                         ; touching any individual word's own code
    ENDIF
    call W_WORD
    rst RST_DPOP
    ld   a, (hl)
    or   a
    jr   z, .done                 ; empty word: input exhausted
    rst RST_DPUSH
    call FIND
    rst RST_DPOP                 ; hl = found flag
    ld   a, l
    or   a
    jr   z, .trynumber

    rst RST_DPOP                 ; hl = immediate flag
    ld   a, l
    ld   (INTERP_IMM_FLAG), a
    rst RST_DPOP                 ; hl = code address

    ld   a, (STATE)
    or   a
    jr   z, .execute               ; interpreting: always execute
    ld   a, (INTERP_IMM_FLAG)
    or   a
    jr   nz, .execute               ; compiling, but IMMEDIATE: execute anyway
    call COMPILE_CALL
    jr   .loop

.execute:
    ld   de, .loop
    push de
    jp   (hl)                      ; "call" HL; the callee's own RET lands at .loop

.trynumber:
    call NUMBER                    ; addr is already on top of stack (FIND
                                    ; pushed it back on a miss) -- ( n flag )
    rst RST_DPOP                  ; hl = numeric flag
    ld   a, l
    or   a
    jr   z, .badword
    IFDEF DECIMAL_NUMBER_ENABLED
    ; flag=2 means NUMBER already pushed a FLOAT onto the float stack
    ; (core/fpparse.asm), not an integer onto the data stack — nothing
    ; below this check applies to it. Gated the same way as NUMBER's own
    ; hook, for the same reason: a ROM without core/fpcore.asm INCLUDEd
    ; can't even resolve COMPILE_FLOAT_LITERAL.
    cp   2
    jr   z, .gotfloat
    ENDIF
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: leave n on the stack
    rst RST_DPOP                  ; compiling: take n back off ...
    call COMPILE_LITERAL           ; ... and compile it as a literal instead
    jr   .loop
    IFDEF DECIMAL_NUMBER_ENABLED
.gotfloat:
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: float already on the
                                    ; float stack, nothing more to do
    push iy                        ; compiling: compile the float on top of
    pop  hl                        ; the float stack as a literal instead
    call COMPILE_FLOAT_LITERAL     ; and drop it
    ld   bc, 5
    add  iy, bc
    jp   .loop                     ; -- JP, not JR:
                                    ; tools/check_z80_opcodes.py flagged
                                    ; this displacement within 10 bytes
                                    ; of JR's +-127 limit
    ENDIF

.badword:
    jp   INTERPRET_UNKNOWN_WORD    ; see rom/forth_smoke_p3.asm: this smoke
                                    ; ROM has no error recovery yet, so an
                                    ; unrecognized token is fatal and the
                                    ; ROM-level caller decides how to report it

.done:
    ret

    IFDEF RUNTIME_ERROR_CHECK_ENABLED
; ============================================================================
; STACK_CHECK (Phase 38, internal, not a dictionary word) — confirms IX
; (the integer stack) and IY (the float stack, core/fpcore.asm) both
; still sit within their own defined ranges (core/dict.asm's own
; DSTACK_TOP/DSTACK_LIMIT; core/fpcore.asm's own FSTACK_TOP/
; FSTACK_LIMIT), called once per word from INTERPRET_RUN's own .loop —
; see that routine's own comment on why that ONE spot catches every
; word's own stack misuse without touching any individual word's code.
;
; GATED behind DEFINE RUNTIME_ERROR_CHECK_ENABLED, the including ROM's
; own opt-in (exactly like core/fpparse.asm's own
; DECIMAL_NUMBER_ENABLED) — every existing ROM that doesn't define it
; gets this file's own compiled bytes byte-for-byte unchanged. A ROM
; that DOES define it MUST also INCLUDE core/fpcore.asm before
; INCLUDEing this file (for FSTACK_TOP/FSTACK_LIMIT to already be
; resolvable) and must itself define RUNTIME_ERROR_HOOK (exactly like
; INTERPRET_UNKNOWN_WORD, below) — reached the same proven way: a bare
; `jp`, with the stack depth first restored to exactly "INTERPRET_RUN's
; own caller, one entry" by discarding this routine's own return
; address first, so RUNTIME_ERROR_HOOK's own implementation can simply
; `ret` when it's done, exactly like INTERPRET_UNKNOWN_WORD already
; does.
;
; SCOPE, stated honestly: this catches a word that pops more than the
; stack currently holds, or pushes past the stack's own reserved
; region — the common, concrete failure (typing `+` or `DROP` with
; nothing on the stack) that would otherwise silently read/corrupt
; whatever memory happens to sit just past the stack's own boundary
; (DSTACK_LIMIT and FSTACK_TOP are adjacent, not coincidentally — see
; core/fpcore.asm's own header). It does NOT catch a word that pops
; garbage and then pushes something back, netting to an
; IN-RANGE-but-wrong stack depth — a real, narrower limitation, the
; same category of "can't verify what it can't observe" this project's
; own SOUND/STICK smoke-test headers already state plainly elsewhere.
;
; RECOVERY: both stacks are unconditionally reset to empty (IX=
; DSTACK_TOP, IY=FSTACK_TOP) before handing off to RUNTIME_ERROR_HOOK —
; there is no way to know how much of a corrupted expression's own
; state is still trustworthy, so this doesn't try to preserve any of
; it, matching INTERPRET_UNKNOWN_WORD's own "abandon the rest of this
; line" posture.
; Destroys: AF, BC, DE, HL (only on the error path -- a clean check
; destroys AF, DE, HL only, matching CHECK-style routines elsewhere)
; ============================================================================
STACK_CHECK:
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    or   a
    sbc  hl, de              ; hl = ix - DSTACK_TOP
    jr   c, .dstack_top_ok    ; ix < DSTACK_TOP -- fine, has items
    ld   a, h
    or   l
    jr   z, .dstack_top_ok    ; ix == DSTACK_TOP -- fine, empty
    jr   .violation            ; ix > DSTACK_TOP -- underflow
.dstack_top_ok:
    push ix
    pop  hl
    ld   de, DSTACK_LIMIT
    or   a
    sbc  hl, de               ; hl = ix - DSTACK_LIMIT
    jr   c, .violation          ; ix < DSTACK_LIMIT -- overflow
    push iy
    pop  hl
    ld   de, FSTACK_TOP
    or   a
    sbc  hl, de
    jr   c, .fstack_top_ok
    ld   a, h
    or   l
    jr   z, .fstack_top_ok
    jr   .violation
.fstack_top_ok:
    push iy
    pop  hl
    ld   de, FSTACK_LIMIT
    or   a
    sbc  hl, de
    jr   c, .violation
    ret                        ; both stacks in range
.violation:
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    pop  hl                    ; discard the return address into .loop
                               ; -- restores the "exactly one entry:
                               ; INTERPRET_RUN's own caller" depth
                               ; RUNTIME_ERROR_HOOK's own contract
                               ; expects (same contract
                               ; INTERPRET_UNKNOWN_WORD already relies
                               ; on, for the same reason)
    jp   RUNTIME_ERROR_HOOK
    ENDIF

; ============================================================================
; GATED behind DEFINE COMPILE_ONLY_CHECK_ENABLED, the including ROM's
; own opt-in (exactly like RUNTIME_ERROR_CHECK_ENABLED/
; DECIMAL_NUMBER_ENABLED above) — every existing ROM that doesn't
; define it gets every touched core/ file's own compiled bytes
; byte-for-byte unchanged. This matters concretely, not just
; stylistically: every rom/forth_smoke_pNN.asm regression ROM feeds a
; FIXED, hand-written, already-correct Forth source string through
; INTERPRET_RUN (or drives individual words directly from Z80 test
; harness code) — none of them ever exercise a compile-only word
; through a live, possibly-mistyped keyboard line the way
; rom/forth_boot.asm's EDITOR_LOOP_LIVE does, so this guard is pure
; dead weight in every one of them: zero behavioral benefit, nonzero
; bytes. Several are ALREADY right at their own fixed-size ROM image's
; edge (rom/forth_smoke_p52.asm had exactly 11 bytes of headroom before
; this guard existed, confirmed by a real build — this file's own
; unconditional bytes alone blew that budget by ~30, `DS $4000 - $, $FF`
; refusing to assemble a negative pad), so this is not a hypothetical
; concern. Only rom/forth_boot.asm (the genuine live, interactive REPL)
; defines COMPILE_ONLY_CHECK_ENABLED; rom/forth_demo_blackjack.asm
; doesn't need it either, for the same reason as the smoke ROMs — its
; own header says outright it feeds a fixed game script straight to
; INTERPRET_RUN, never through EDITOR_LOOP_LIVE.
; ============================================================================
    IFDEF COMPILE_ONLY_CHECK_ENABLED
; ============================================================================
; COMPILE_ONLY_CHECK — NOT a dictionary word. Call as the very first
; instruction of any IMMEDIATE compile-only word (core/control.asm's
; IF/ELSE/THEN/BEGIN/UNTIL, core/loop.asm's WHILE/REPEAT,
; core/doloop.asm's DO/LOOP/+LOOP/LEAVE, core/loopext.asm's EXIT, and
; core/dotquote.asm's `."`) to refuse it cleanly when typed directly at
; the interpreter prompt instead of silently doing damage.
;
; THE BUG THIS CLOSES: every word in that list is IMMEDIATE, so
; INTERPRET_RUN's own dispatch above runs its code unconditionally
; regardless of STATE (`.execute` is reached both when interpreting AND
; when compiling-but-immediate) -- but every one of them ALSO
; unconditionally compiles into the dictionary at HERE (a QBRANCH/
; BRANCH call plus a placeholder, a DO/LOOP hardware-stack frame
; reference, or DOSTR plus raw string bytes) and several ALSO push
; compile-time bookkeeping onto the borrowed data stack (core/
; control.asm's own header) or into core/doloop.asm's LEAVE_HEAD_TABLE.
; Typed at the prompt (STATE=0, no enclosing colon definition), that
; compiled code is never reached by anything -- there is no "later,
; when this definition runs" -- so it just sits as dead bytes,
; permanently advancing HERE, while any placeholder address IF/BEGIN/DO
; left on the data stack either gets silently consumed by a later word
; that happened to be typed on the same line (if the line balances,
; e.g. a stray `IF ... THEN` with nothing after), or leaks forever if
; it doesn't. This is the exact failure mode core/string.asm's own
; header documents finding and fixing in `S"` the same way (a real Fuse
; run measuring the data stack pointer before/after proved zero effect,
; not the expected one) -- this generalizes that fix to every other
; compile-only word, which have no sensible interpreted meaning at all
; (unlike `S"`, there's no live loop/branch structure at the top-level
; interpreter for IF or DO to hook into), so the right STATE=0 behavior
; here is to error, not to improvise an equivalent.
;
; CONTRACT: if STATE is nonzero (compiling), returns normally so the
; caller falls through into its own real body, completely unaffected --
; this is a plain `ret`, not a jump, so it costs one CALL/RET pair in
; the working case and changes nothing else about how these words
; behave once actually compiling. If STATE is 0 (interpreting), reports
; the SAME "WORD ?" error INTERPRET_UNKNOWN_WORD already gives for a
; genuinely unrecognized word (WORD_BUF still holds the just-parsed
; token untouched, exactly as INTERPRET_UNKNOWN_WORD's own header
; already relies on) rather than inventing a second error message and
; a second hook contract for what is, from the typist's point of view,
; the same kind of mistake: this word cannot be used here. Reused
; deliberately, matching this project's own standing practice of
; extending an established mechanism instead of adding a parallel one.
;
; RETURN-ADDRESS BOOKKEEPING ON THE ERROR PATH: every one of these
; words is reached via INTERPRET_RUN's `.execute` label above (`ld de,
; .loop / push de / jp (hl)`), so by the time this routine's own `call
; COMPILE_ONLY_CHECK` instruction runs inside the caller's body, the
; Z80 return-address stack holds, top to bottom: this call's own return
; address (back into the calling word, right after the `call`), then
; `.loop` (pushed by `.execute`, standing in for a normal call/ret so
; the calling word's own eventual `ret` resumes the interpreter loop),
; then whatever was on the stack before INTERPRET_RUN was entered
; (INTERPRET_RUN's own caller). Discarding the first two restores
; exactly the depth INTERPRET_UNKNOWN_WORD's own contract expects --
; one entry, INTERPRET_RUN's own caller -- the identical arithmetic
; STACK_CHECK's `.violation` path above already relies on for the same
; reason, just one `pop` further out (STACK_CHECK is entered by a
; direct `call` from `.loop` itself, with no intervening word to
; discard).
; ============================================================================
COMPILE_ONLY_CHECK:
    ld   a, (STATE)
    or   a
    ret  nz                    ; compiling: caller continues into its
                                ; own real body, unaffected
    pop  hl                    ; discard the return address into the
                                ; calling word
    pop  hl                    ; discard the calling word's own return
                                ; address into .loop -- now exactly one
                                ; entry left: INTERPRET_RUN's own caller
    jp   INTERPRET_UNKNOWN_WORD
    ENDIF

; ============================================================================
; COMPILE_WORD ( HL = value -- )  added for Phase 4. Compiles 2 raw bytes
; at HERE, advancing HERE by 2 -- unlike COMPILE_LITERAL, this does NOT
; wrap the value in "CALL DOLIT". core/control.asm's IF/ELSE/THEN/UNTIL
; use this to compile a branch-target placeholder (later patched, or
; already known) that QBRANCH/BRANCH read directly from their own
; return address, the same inline-data idiom DOLIT itself uses (see
; DOLIT's own header) -- a branch target is consumed by that mechanism
; alone, never pushed onto the data stack the way a literal's value is,
; so it must NOT go through COMPILE_LITERAL/DOLIT.
; ============================================================================
COMPILE_WORD:
    ld   de, (HERE)
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   (HERE), de
    ret

    ENDIF
