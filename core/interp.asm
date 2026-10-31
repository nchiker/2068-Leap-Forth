; ============================================================================
; core/interp.asm -- the outer interpreter and the colon compiler
;
; Needs core/dict.asm first: it uses RST_DPUSH / RST_DPOP, LATEST and HERE, and extends the chain
; from H_STORE. The words here are `:` and `;` (FIND finds them like any other); the rest are
; routines: WORD_SKIP, W_WORD and WORD_NAME (parse a token), FIND, NUMBER, DOLIT (the run-time half
; of a literal), the COMPILE_* helpers, DICT_ROOM, the HEADER_* routines every defining word builds
; its header with, and INTERPRET_RUN, the interpreter loop. DICT_LATEST_INIT_P3 is
; the value LATEST is seeded with (H_SEMICOLON; core/dict.asm's DICT_LATEST_INIT stops at H_STORE).
;
; IMMEDIATE is LENFLAGS bit 7 (core/dict.asm). FIND reports it and INTERPRET_RUN is the only place
; that acts on it. Whitespace is every byte from 0 to space (CR and TAB included, for the line
; store's CR-ended lines). FIND is case-sensitive: W_WORD folds a-z to upper case, as every header
; is upper case.
;
; Errors: an unknown token goes to INTERPRET_UNKNOWN_WORD and a stack range violation to
; RUNTIME_ERROR_HOOK, both supplied by the including ROM (rom/forth_boot.asm), each entered with the
; hardware stack at exactly one entry, INTERPRET_RUN's caller, so they can simply RET.
; Every word here may destroy all registers except IX, IY and SP.
; ============================================================================

    IFNDEF CORE_INTERP_ASM
    DEFINE CORE_INTERP_ASM

; ============================================================================
; WORD_SKIP -- skip the whitespace from SRC_PTR to the next token (SRC_PTR is left at it)
; Out: A = the token's first character, as typed (not folded), and NZ; A = 0 and Z if SRC_PTR
;      reached SRC_END (the input is exhausted). HL = SRC_PTR
; Destroys: AF, DE, HL
; ============================================================================
WORD_SKIP:
    ld   hl, (SRC_PTR)
    ld   de, (SRC_END)
.loop:
    ld   a, h
    cp   d
    jr   nz, .more
    ld   a, l
    cp   e
    jr   z, .end
.more:
    ld   a, (hl)
    cp   " " + 1             ; every byte from 0 to space is whitespace
    jr   nc, .found          ; (CR and TAB included: the line store's CR-ended lines)
    inc  hl
    jr   .loop
.end:
    xor  a
.found:
    ld   (SRC_PTR), hl
    or   a
    ret

; ============================================================================
; W_WORD ( -- addr ) -- parse the next token from SRC_PTR into WORD_BUF as a counted string, folding
; a-z to upper case; advance SRC_PTR past it and the delimiter. A count of 0 means SRC_PTR had
; reached SRC_END: the input is exhausted. At most 31 characters are kept (a header's length field
; holds 0-31); the rest of a longer token is skipped.
; Destroys: AF, BC, DE, HL
; ============================================================================
W_WORD:
    call WORD_SKIP
    jr   z, .empty

.foundstart:
    ld   de, WORD_BUF+1
    ld   b, 0                ; count so far
.copyloop:
    ld   hl, (SRC_END)
    ld   a, h
    ld   c, l                ; A, C hold SRC_END while HL takes SRC_PTR
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
    ; fold a-z to A-Z: every header is upper case and FIND is case-sensitive
    cp   "a"
    jr   c, .not_lower
    cp   "z" + 1
    jr   nc, .not_lower
    sub  "a" - "A"
.not_lower:
    inc  hl
    ld   (SRC_PTR), hl
    ld   c, a
    ld   a, b
    cp   31
    jr   nc, .copyloop       ; past 31 characters (a header's length field): skipped
    ld   a, c
    ld   (de), a
    inc  de
    inc  b
    jr   .copyloop
.donecopy_consume:
    inc  hl
    ld   (SRC_PTR), hl       ; the delimiter is consumed
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
; WORD_NAME ( -- addr ) -- W_WORD for a word that takes a name (`:` CREATE VARIABLE ' CHAR ...): the
; input must hold one, else THROW -16 (MISSING NAME)
; Destroys: AF, BC, DE, HL
; ============================================================================
WORD_NAME:
    call W_WORD
    ld   a, (WORD_BUF)
    or   a
    ret  nz
    ld   hl, -16                  ; the standard's "zero-length string as a name"
    rst  RST_DPUSH                ; (THROW resets the stack W_WORD's push left)
    jp   W_THROW

; ============================================================================
; FIND ( addr -- code_addr imm found | addr 0 ) -- search the dictionary from LATEST back. addr is a
; counted string in WORD_BUF's format. On a match: the code address, imm = 1 if the word is
; immediate else 0, found = 1. Otherwise addr is pushed back and found = 0.
; Destroys: AF, BC, DE, HL, the cell FIND_SEARCH_ADDR
; ============================================================================
FIND:
    rst RST_DPOP
    ld   (FIND_SEARCH_ADDR), hl
    ld   c, (hl)                  ; C = the length searched for
    ld   hl, (LATEST)
.loop:                            ; a header whose length differs costs 82 T
    ld   a, h
    or   l
    jr   z, .notfound
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                  ; DE = the previous header
    inc  hl
    ld   a, (hl)                  ; LENFLAGS
    and  $1F
    cp   c
    jr   z, .same
    ex   de, hl
    jr   .loop
.same:
    push de
    push hl                       ; -> LENFLAGS
    ld   de, (FIND_SEARCH_ADDR)
    ld   b, c
    inc  b
    jr   .cmpin
.cmp:
    inc  hl
    inc  de
    ld   a, (de)
    cp   (hl)
    jr   nz, .differ
.cmpin:
    djnz .cmp
    inc  hl                       ; the code address: after the name
    rst RST_DPUSH
    pop  hl
    pop  de
    ld   a, (hl)
    rlca
    and  1                        ; the IMMEDIATE bit
    ld   l, a
    ld   h, b
    rst RST_DPUSH
    ld   hl, 1
    rst RST_DPUSH
    ret
.differ:
    pop  hl
    pop  hl
    jr   .loop
.notfound:
    ld   hl, (FIND_SEARCH_ADDR)
    rst RST_DPUSH
    ld   hl, 0
    rst RST_DPUSH
    ret

; ============================================================================
; NUMBER ( addr -- n 1 | 2 | 0 0 ) -- parse a counted string as a number (core/fpparse.asm has the
; grammar): an integer is pushed with flag 1, a float goes on the float stack with only the flag
; 2, anything else gives 0 0. An integer outside -32768..65535 or a float beyond the float range is
; THROW -43.
; Destroys: AF, BC, DE, HL (and what NUMBER_PARSE does)
; ============================================================================
NUMBER:
    rst RST_DPOP
    ld   a, (hl)
    or   a
    jr   z, .fail
    jp   NUMBER_PARSE             ; HL -> the token, A = its length
.fail:
    ld   hl, 0
    rst RST_DPUSH
    ld   hl, 0
    rst RST_DPUSH
    ret

; ============================================================================
; DOLIT -- not a dictionary word: the run-time half of a compiled literal, which is 5 bytes: CALL
; DOLIT and the 2-byte value. Push the value and return past it.
; In:  the return address -> the value
; Out: ( -- value )
; Destroys: DE, HL
; ============================================================================
DOLIT:
    pop  hl                       ; HL -> the value
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    inc  hl                       ; HL = the continuation
    push hl
    ex   de, hl
    rst RST_DPUSH
    ret

; ============================================================================
; COMPILE_CALL -- compile CALL target (3 bytes) at HERE
; In:  HL = the target
; Out: HERE += 3
; Destroys: AF, DE
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
; COMPILE_LITERAL -- compile a 5-byte literal at HERE: CALL DOLIT and the value
; In:  HL = the value
; Out: HERE += 5
; Destroys: AF, DE, HL
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
; DICT_ROOM -- the dictionary ceiling check. Return, HL unchanged, if HERE + n does not pass
; DICT_RAM_CEILING - 256, else THROW -8. The last 256 bytes are for the body of a definition
; before its `;` (a body is compiled with COMPILE_CALL, _BYTE and _WORD, which are not checked).
; Called first by every word that starts a definition or data field (`:` CREATE VARIABLE
; CONSTANT ARRAY STRING; DICT_ROOM0 is n = 0) and by `,` `C,` ALLOT, before they change HERE or
; LATEST. Unsigned: HERE + n carrying past $FFFF fails.
; In:  HL = the bytes about to be reserved
; Destroys: AF, DE
; ============================================================================
DICT_ROOM0:
    ld   hl, 0
DICT_ROOM:
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
    ld   hl, -8                   ; dictionary overflow (THROW resets the SP the push left)
    rst  RST_DPUSH
    jp   W_THROW

; ============================================================================
; COMPILE_BYTE -- compile one raw byte at HERE
; In:  A = the byte
; Out: HERE += 1
; Destroys: HL
; ============================================================================
COMPILE_BYTE:
    ld   hl, (HERE)
    ld   (hl), a
    inc  hl
    ld   (HERE), hl
    ret

; ============================================================================
; HEADER_BUILD -- the header of a new word at HERE: parse its name (WORD_NAME), build LINK =
; LATEST and the counted name. LATEST is not changed (HEADER_LINK does that).
; Out: NEW_HEADER_ADDR = the header, HERE = past the name, where the code starts
; Destroys: AF, BC, DE, HL
; ============================================================================
HEADER_BUILD:
    call WORD_NAME
    rst  RST_DPOP                 ; HL -> the counted name
    ex   de, hl                   ; DE -> the name
    ld   hl, (HERE)
    ld   (NEW_HEADER_ADDR), hl
    ld   bc, (LATEST)
    ld   (hl), c
    inc  hl
    ld   (hl), b
    inc  hl
    ex   de, hl                   ; HL -> the name, DE -> where it goes
    ld   c, (hl)
    ld   b, 0
    inc  bc                       ; the length byte and the name
    ldir
    ld   (HERE), de
    ret

; ============================================================================
; HEADER_END -- compile the RET that ends a word's code, then HEADER_LINK
; HEADER_LINK -- link the word HEADER_BUILD made into the dictionary: LATEST = NEW_HEADER_ADDR
; Destroys: AF, HL
; ============================================================================
HEADER_END:
    ld   a, $C9                   ; RET
    call COMPILE_BYTE
HEADER_LINK:
    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; : ( "name" -- ) -- build a header at HERE (HEADER_BUILD), link it (LATEST) and set STATE to 1.
; HERE is left past the name, where the code starts. Not immediate: a `:` inside a definition is
; not supported.
; ============================================================================
H_COLON:
    DW   H_STORE
    DB   1, ":"
W_COLON:
    call DICT_ROOM0
    call HEADER_BUILD
    call HEADER_LINK
    jp   W_RBRACKET               ; STATE = 1 (core/tick.asm)

; ============================================================================
; ; ( -- ) IMMEDIATE -- compile a RET, ending the definition's CALL chain, and set STATE to 0.
; Immediate so that it runs even while compiling.
; ============================================================================
H_SEMICOLON:
    DW   H_COLON
    DB   $81, ";"
W_SEMICOLON:
    ld   a, $C9                   ; RET
    call COMPILE_BYTE
    xor  a
    ld   (STATE), a
    ret


; ============================================================================
; INTERPRET_RUN -- run the outer interpreter over one source buffer until W_WORD reports the
; input exhausted
; In:  HL = the source, DE = its length
; Out: returns when the source is consumed
; Destroys: all registers except IX, IY, SP
;
; INTERPRET_NESTED is the same routine entered one instruction later: it does not save
; THROW_ROOT_SP, which therefore stays the outermost run's SP. An error in a nested run (LOAD-TEXT
; interpreting its text) unwinds (REPORT_INTERP_ERROR, THROW, ABORT, QUIT) to the outermost
; caller, abandoning the nested text and the rest of the outer line. A nested run that succeeds
; returns to its caller, which restores SRC_PTR / SRC_END (core/loadtext.asm).
; ============================================================================
INTERPRET_RUN:
    ld   (THROW_ROOT_SP), sp    ; where an uncaught THROW unwinds to (core/throwcatch.asm)
INTERPRET_NESTED:
    ld   (SRC_PTR), hl
    add  hl, de
    ld   (SRC_END), hl
    xor  a
    ld   (INTERP_ERROR_FLAG), a

.loop:
    call STACK_CHECK    ; here, so every word's stack use is checked: each returns to .loop
    call W_WORD
    rst RST_DPOP
    ld   a, (hl)
    or   a
    jr   z, .done                 ; empty word: input exhausted
    rst RST_DPUSH
    call FIND
    rst RST_DPOP                 ; HL = the found flag
    ld   a, l
    or   a
    jr   z, .trynumber

    rst RST_DPOP                 ; HL = the immediate flag
    ld   a, l
    ld   (INTERP_IMM_FLAG), a
    rst RST_DPOP                 ; HL = the code address

    ld   a, (STATE)
    or   a
    jr   z, .execute               ; interpreting: always
    ld   a, (INTERP_IMM_FLAG)
    or   a
    jr   nz, .execute               ; compiling, but immediate
    call COMPILE_CALL
    jr   .loop

.execute:
    ld   de, .loop
    push de
    jp   (hl)                      ; "call" HL; the callee's own RET lands at .loop

.trynumber:
    call NUMBER                    ; the address is on the stack, pushed back by FIND
    rst RST_DPOP                  ; HL = the flag
    ld   a, l
    or   a
    jr   z, .badword
    ; flag 2: NUMBER left a float on the float stack, not an integer on the data stack
    cp   2
    jr   z, .gotfloat
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: n stays on the stack
    rst RST_DPOP                  ; compiling: compile n as a literal instead
    call COMPILE_LITERAL
    jr   .loop
.gotfloat:
    ld   a, (STATE)
    or   a
    jr   z, .loop                  ; interpreting: the float stays on the float stack
    push iy                        ; compiling: compile the float on top as a literal
    pop  hl
    call COMPILE_FLOAT_LITERAL     ; and drop it
    ld   bc, 5
    add  iy, bc
    jp   .loop                     ; a JP: tools/check_z80_opcodes.py flags a JR this near its limit

.badword:
    jp   INTERPRET_UNKNOWN_WORD

.done:
    ret

; ============================================================================
; STACK_CHECK -- INTERPRET_RUN calls it once per word: are IX and IY still within the data stack's
; and the float stack's ranges (DSTACK_TOP / DSTACK_LIMIT, FSTACK_TOP / FSTACK_LIMIT)? Needs
; core/fpcore.asm before this file, and RUNTIME_ERROR_HOOK from the ROM. It catches a word that
; pops more than the stack holds or pushes past its region (`+` or `DROP` on an empty stack), not
; one that nets to a wrong depth within range.
; Out: returns if both are in range. Otherwise both stacks are reset to empty (IX = DSTACK_TOP,
;      IY = FSTACK_TOP), its return address into .loop is discarded, and it jumps to
;      RUNTIME_ERROR_HOOK, leaving the hardware stack at one entry
; Destroys: AF, DE, HL (and BC on the error path)
; ============================================================================
STACK_CHECK:
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    or   a
    sbc  hl, de
    jr   c, .dstack_top_ok    ; IX < DSTACK_TOP: has items
    ld   a, h
    or   l
    jr   z, .dstack_top_ok    ; empty
    jr   .violation            ; IX > DSTACK_TOP: underflow
.dstack_top_ok:
    push ix
    pop  hl
    ld   de, DSTACK_LIMIT
    or   a
    sbc  hl, de
    jr   c, .violation          ; IX < DSTACK_LIMIT: overflow
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
    pop  hl                    ; the return address into .loop: one entry is left
    jp   RUNTIME_ERROR_HOOK

; ============================================================================
; COMPILE_ONLY_CHECK -- not a dictionary word: the first instruction of every immediate
; compile-only word (IF ELSE THEN BEGIN UNTIL WHILE REPEAT DO LOOP +LOOP LEAVE EXIT, `."`). They
; are immediate, so they run even at the prompt, where they would compile dead bytes at HERE and
; leave placeholders on the data stack. Returns if STATE is 1. If STATE is 0 it reports the same
; error as an unknown word (WORD_BUF still holds the token) and does not return to the caller.
; Out: returns when compiling; else jumps to INTERPRET_UNKNOWN_WORD with the hardware stack at one
;      entry: the two return addresses above it (into the word, and the .loop that .execute pushed
;      for the word's own RET) are discarded
; Destroys: AF, HL
; ============================================================================
COMPILE_ONLY_CHECK:
    ld   a, (STATE)
    or   a
    ret  nz
    pop  hl                    ; the return address into the calling word
    pop  hl                    ; the word's return address into .loop
    jp   INTERPRET_UNKNOWN_WORD

; ============================================================================
; COMPILE_WORD -- compile 2 raw bytes at HERE (not wrapped in CALL DOLIT: a branch target is read
; inline by QBRANCH / BRANCH, never pushed)
; In:  HL = the value
; Out: HERE += 2
; Destroys: AF, DE
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
