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
; Phase 3 RAM state — provisional addresses, same caveat as core/dict.asm's
; DSTACK_TOP/LATEST/HERE (docs/PROJECT_PLAN.md Phase 0 hasn't run yet).
; Deliberately NOT inside [DSTACK_LIMIT, DSTACK_TOP] ($9000-$9800) or at
; FORTH_DICT_RAM ($A000+) — this is its own separate scratch area so a
; deep data stack or a growing compiled dictionary can never collide
; with it.
; ============================================================================
SRC_PTR           EQU $8100   ; 2 bytes: next unread source character
SRC_END           EQU $8102   ; 2 bytes: one past the last valid source byte
STATE             EQU $8104   ; 1 byte: 0 = interpreting, 1 = compiling
FIND_SEARCH_ADDR  EQU $8105   ; 2 bytes: FIND's own scratch
FIND_HEADER_ADDR  EQU $8107   ; 2 bytes: FIND's own scratch
FIND_RAW_LENFLAGS EQU $8109   ; 1 byte:  FIND's own scratch (pre-mask, for the IMMEDIATE bit)
NUM_PTR           EQU $810A   ; 2 bytes: NUMBER's own scratch
NUM_COUNT         EQU $810C   ; 1 byte:  NUMBER's own scratch
NUM_NEG           EQU $810D   ; 1 byte:  NUMBER's own scratch (1 = saw a leading '-')
WORD_SRC_ADDR     EQU $810E   ; 2 bytes: W_COLON's own scratch
NEW_HEADER_ADDR   EQU $8110   ; 2 bytes: W_COLON's own scratch
WORD_BUF          EQU $8120   ; 34 bytes: 1 count byte + up to 32 name bytes
                              ; (header LENFLAGS only has 5 length bits, so
                              ; 32 is already more than a definition name
                              ; can ever use — generous on purpose)

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
    jr   z, .fail
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
    ld   (SRC_PTR), hl
    add  hl, de
    ld   (SRC_END), hl

.loop:
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
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: leave n on the stack
    call DPOP_HL                   ; compiling: take n back off ...
    call COMPILE_LITERAL           ; ... and compile it as a literal instead
    jr   .loop

.badword:
    jp   INTERPRET_UNKNOWN_WORD    ; see rom/forth_smoke_p3.asm: this smoke
                                    ; ROM has no error recovery yet, so an
                                    ; unrecognized token is fatal and the
                                    ; ROM-level caller decides how to report it

.done:
    ret

INTERP_IMM_FLAG EQU $8112          ; 1 byte: INTERPRET_RUN's own scratch

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
