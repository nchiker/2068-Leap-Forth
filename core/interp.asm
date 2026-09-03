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
; Phase 3 RAM state.
;
; RELOCATED for Phase 5 (2026-09-01): originally $8100-$8141ish, which
; turned out to collide with real, actively-used 2068-Leap kernel/BASIC
; sysvars (include/sysvars.inc's own ORG $8000 block is densely packed
; there — EDITOR_REDRAW_HOOK, HILITE_*, PORT_FE_SHADOW, and dozens more,
; confirmed by actually assembling kernel/graphics.asm + kernel/sound.asm
; together with this file and inspecting the resulting .sym). That
; collision was invisible through Phase 3/4 because neither of those
; phases' smoke ROMs ever INCLUDEs a kernel/ module that pulls
; sysvars.inc in — Phase 5 is the first phase where this file coexists
; in the same ROM image as real kernel/graphics + kernel/sound code, so
; it's the first place the bug could have actually bitten.
;
; The same probe confirmed $8426 (2068-Leap's own PROG_AREA_START — the
; start of ITS dynamic BASIC program/array/scalar pool, never written to
; by anything this project calls) through $8FFF is genuinely empty: not
; one sysvars.inc symbol lands there. This file's own scratch now lives
; at $8500, comfortably inside that gap, with margin on both sides
; before DSTACK_LIMIT ($9000, also confirmed collision-free by the same
; probe) and before core/dict.asm's own DSTACK_TOP/LATEST/HERE.
;
; If a future phase adds its own RAM state, verify it against a real
; probe the same way — see docs/PROJECT_PLAN.md's Phase 5 section for
; the exact method — rather than picking an address by inspection alone.
; ============================================================================
SRC_PTR           EQU $8500   ; 2 bytes: next unread source character
SRC_END           EQU $8502   ; 2 bytes: one past the last valid source byte
STATE             EQU $8504   ; 1 byte: 0 = interpreting, 1 = compiling
FIND_SEARCH_ADDR  EQU $8505   ; 2 bytes: FIND's own scratch
FIND_HEADER_ADDR  EQU $8507   ; 2 bytes: FIND's own scratch
FIND_RAW_LENFLAGS EQU $8509   ; 1 byte:  FIND's own scratch (pre-mask, for the IMMEDIATE bit)
NUM_PTR           EQU $850A   ; 2 bytes: NUMBER's own scratch
NUM_COUNT         EQU $850C   ; 1 byte:  NUMBER's own scratch
NUM_NEG           EQU $850D   ; 1 byte:  NUMBER's own scratch (1 = saw a leading '-')
WORD_SRC_ADDR     EQU $850E   ; 2 bytes: W_COLON's own scratch
NEW_HEADER_ADDR   EQU $8510   ; 2 bytes: W_COLON's own scratch
INTERP_IMM_FLAG   EQU $8512   ; 1 byte:  INTERPRET_RUN's own scratch (moved
                              ; up here from the file's tail, alongside
                              ; the rest of this relocated block)
WORD_BUF          EQU $8520   ; 34 bytes: 1 count byte + up to 32 name bytes
                              ; (header LENFLAGS only has 5 length bits, so
                              ; 32 is already more than a definition name
                              ; can ever use — generous on purpose)

    IFDEF THROW_CATCH_ENABLED
THROW_ROOT_SP     EQU $8542   ; 2 bytes: SP snapshotted at INTERPRET_RUN's
                              ; own entry -- see that routine's own
                              ; comment for why an uncaught THROW needs
                              ; this. Gated the same way STACK_CHECK is:
                              ; a ROM that doesn't define
                              ; THROW_CATCH_ENABLED gets no new symbol
                              ; and no new instruction here at all.
    ENDIF

; ============================================================================
; W_WORD ( -- addr )
; Skips leading spaces from SRC_PTR, copies the next run of non-space
; characters into WORD_BUF as a counted string (count byte, then the
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
    cp   " "
    jr   nz, .foundstart
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
    cp   " "
    jr   z, .donecopy_consume
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
    call DPUSH_HL
    ret

.empty:
    xor  a
    ld   (WORD_BUF), a
    ld   hl, WORD_BUF
    call DPUSH_HL
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
    call DPOP_HL
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
    call DPUSH_HL
    ld   a, (FIND_RAW_LENFLAGS)
    and  $80
    ld   hl, 0
    jr   z, .notimm
    ld   hl, 1
.notimm:
    call DPUSH_HL
    ld   hl, 1
    call DPUSH_HL
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
    call DPUSH_HL
    ld   hl, 0
    call DPUSH_HL
    ret

; ============================================================================
; NUMBER ( addr -- n flag )
; addr must be a counted string. flag=1 and n=the parsed value on
; success; flag=0 (n=0, not meaningful) if the string is empty, is a
; lone "-", or contains any non-digit.
; ============================================================================
NUMBER:
    call DPOP_HL
    ld   a, (hl)
    or   a
    IFDEF DECIMAL_NUMBER_ENABLED
    jp   z, .fail                 ; JP, not JR -- gated the same as the
                                   ; rest of Phase 23's own hook below:
                                   ; that IFDEF block pushed this
                                   ; displacement within 10 bytes of
                                   ; JR's +-127 limit (flagged by
                                   ; tools/check_z80_opcodes.py) only
                                   ; when it's actually compiled in; a
                                   ; ROM that doesn't opt in never grew
                                   ; NUMBER, so its own JR was never at
                                   ; risk and stays byte-for-byte
                                   ; unchanged
    ELSE
    jr   z, .fail
    ENDIF
    ld   (NUM_COUNT), a
    inc  hl
    ld   (NUM_PTR), hl
    IFDEF DECIMAL_NUMBER_ENABLED
    ; Phase 23 (core/decimal.asm) hook: a token containing '.' is a
    ; decimal literal, parsed and pushed onto the FLOAT stack entirely
    ; by DECIMAL_PARSE_AND_PUSH, not by any of the plain-integer code
    ; below. Gated behind DECIMAL_NUMBER_ENABLED (the including ROM
    ; must DEFINE it before this INCLUDE) so that every ROM which
    ; doesn't opt in gets this NUMBER completely unchanged, byte for
    ; byte — confirmed directly by diffing a rebuilt
    ; rom/forth_smoke_p3.asm against its own pre-Phase-23 output, not
    ; just reasoned about.
    call CHECK_FOR_DOT
    or   a
    jp   nz, DECIMAL_PARSE_AND_PUSH
    ld   hl, (NUM_PTR)          ; REQUIRED: CHECK_FOR_DOT's own header
                                 ; says plainly "Destroys: ... HL" (it
                                 ; walks its OWN copy of HL to scan the
                                 ; whole token) -- the very next lines
                                 ; below read (hl) expecting it to still
                                 ; point at the token's first character,
                                 ; an assumption this call just broke. A
                                 ; real bug, not a hypothetical: without
                                 ; this reload, a negative integer like
                                 ; "-5" reads garbage instead of '-' for
                                 ; its sign check, silently skips the
                                 ; sign-consuming step, and then fails
                                 ; in the digit loop on the unconsumed
                                 ; '-' itself -- found via a real Fuse
                                 ; run, not by inspection (positive
                                 ; integers never triggered it: the
                                 ; garbage byte only needed to not
                                 ; equal '-' by coincidence, which is
                                 ; overwhelmingly likely, so the sign
                                 ; check's wrong answer happened to be
                                 ; harmless for them).
    ENDIF
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
    call DPUSH_HL
    ld   hl, 1
    call DPUSH_HL
    ret
.fail:
    ld   hl, 0
    call DPUSH_HL
    ld   hl, 0
    call DPUSH_HL
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
    call DPUSH_HL
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
    call W_WORD
    call DPOP_HL
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
                                 ; Captured once, at INTERPRET_RUN's own
                                 ; entry, not per-word: SP here is fixed
                                 ; for this entire call, since .loop's
                                 ; own dispatch always fully unwinds
                                 ; back to it between words.
    ENDIF
    ld   (SRC_PTR), hl
    add  hl, de
    ld   (SRC_END), hl

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
    call DPOP_HL
    ld   a, (hl)
    or   a
    jr   z, .done                 ; empty word: input exhausted
    call DPUSH_HL
    call FIND
    call DPOP_HL                  ; hl = found flag
    ld   a, l
    or   a
    jr   z, .trynumber

    call DPOP_HL                  ; hl = immediate flag
    ld   a, l
    ld   (INTERP_IMM_FLAG), a
    call DPOP_HL                  ; hl = code address

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
    call DPOP_HL                   ; hl = numeric flag
    ld   a, l
    or   a
    jr   z, .badword
    IFDEF DECIMAL_NUMBER_ENABLED
    ; Phase 23 (core/decimal.asm): flag=2 means NUMBER already pushed a
    ; FLOAT onto the float stack (DECIMAL_PARSE_AND_PUSH), not an
    ; integer onto the data stack — nothing below this check applies to
    ; it. Gated the same way as NUMBER's own hook, for the same reason:
    ; a ROM without core/float.asm INCLUDEd can't even resolve FPOP.
    cp   2
    jr   z, .gotfloat
    ENDIF
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: leave n on the stack
    call DPOP_HL                   ; compiling: take n back off ...
    call COMPILE_LITERAL           ; ... and compile it as a literal instead
    jr   .loop
    IFDEF DECIMAL_NUMBER_ENABLED
.gotfloat:
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: float already on the
                                    ; float stack, nothing more to do
    call FPOP                      ; compiling: take the float back off
    call COMPILE_FLOAT_LITERAL     ; the float stack and compile it as
    jr   .loop                     ; a literal instead
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
; (the integer stack) and IY (the float stack, core/float.asm) both
; still sit within their own defined ranges (core/dict.asm's own
; DSTACK_TOP/DSTACK_LIMIT; core/float.asm's own FSTACK_TOP/
; FSTACK_LIMIT), called once per word from INTERPRET_RUN's own .loop —
; see that routine's own comment on why that ONE spot catches every
; word's own stack misuse without touching any individual word's code.
;
; GATED behind DEFINE RUNTIME_ERROR_CHECK_ENABLED, the including ROM's
; own opt-in (exactly like core/decimal.asm's own
; DECIMAL_NUMBER_ENABLED) — every existing ROM that doesn't define it
; gets this file's own compiled bytes byte-for-byte unchanged. A ROM
; that DOES define it MUST also INCLUDE core/float.asm before
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
; core/float.asm's own header). It does NOT catch a word that pops
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
