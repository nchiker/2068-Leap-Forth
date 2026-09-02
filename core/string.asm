; ============================================================================
; core/string.asm — Phase 27: string handling (S", TYPE, STRING, PLACE,
; COUNT, LEN, VAL)
;
; Builds on core/dict.asm, core/interp.asm (both must be INCLUDEd
; first) and core/print.asm (needs W_EMIT). Chains its own dictionary
; entries via DICT_CHAIN_POINT, same convention as every other core/
; file.
;
; WHAT THIS ADDS — the biggest single remaining gap found by a direct
; audit of 2068-Leap's own BASIC ROM (`~/ts2068rom`) against this
; project's dictionary: 2068-Forth had NO string handling at all before
; this phase (`."` prints a fixed literal, but there was no way to
; store, measure, or convert text). This phase adds a real, if
; deliberately scoped, slice of it:
;
;   S" text"  ( -- addr len )  IMMEDIATE, works BOTH interpreting and
;             compiling (unlike `."`, which is compile-only — see
;             core/dotquote.asm's own header for why no leading-space
;             skip is needed, a detail S" shares) — pushes the address
;             and length of a string literal, standard ANS Forth's own
;             STRING stack convention (addr first/deeper, len on top).
;             Unlike `."`, this does NOT print anything itself — it
;             just makes the string available on the stack for TYPE,
;             PLACE, VAL, or anything else that takes (addr len). A
;             REAL BUG CAUGHT HERE, not just designed around: an early
;             version always just compiled "CALL DOSSTR" plus the
;             string's own bytes and returned, exactly like `."` does —
;             correct ONLY when used inside a colon definition, where
;             the surrounding word's own later execution eventually
;             reaches and runs that compiled code. Used directly at the
;             interpreter prompt (STATE=0, no enclosing colon
;             definition), NOTHING ever calls the freshly-compiled
;             bytes, so NOTHING gets pushed — a real Fuse run proved
;             this by measuring the data stack pointer's own depth
;             before and after `S" AB"` at top level: zero change, not
;             the expected 4 bytes (addr, len). A SECOND attempt fixed
;             this by having W_SQUOTE check STATE and, when
;             interpreting, `jp` straight into the "CALL DOSSTR" just
;             compiled, reasoning that DOSSTR "pushes addr/len and
;             returns correctly no matter who called it" — true in
;             isolation, but wrong here: DOSSTR's own contract returns
;             to whatever code FOLLOWS its inline string data, correct
;             inside a colon definition's body (the next compiled
;             word), but at the top level there is no following code —
;             just blank, uninitialized dictionary space — and a real
;             Fuse run hung completely, executing that garbage as code.
;             The actual fix: when interpreting, W_SQUOTE pushes
;             (addr len) onto the data stack ITSELF (the same two
;             values DOSSTR would have pushed) and returns normally,
;             never invoking DOSSTR or its "return to what follows"
;             assumption at all — sidestepping the problem rather than
;             solving it cleverly. It also reclaims the dictionary
;             bytes "CALL DOSSTR" and the string's own data used in
;             this case (rolling HERE back), since none of it is needed
;             once the values are already on the stack — no wasted
;             dictionary space for typed string literals after all.
;   TYPE      ( addr len -- )   prints a string given as an (addr len)
;             pair — the standard way to print anything S" produced.
;   STRING    ( n "name" -- )   creates <name> such that
;             <name> ( -- caddr ) pushes the address of a fresh,
;             empty, mutable string buffer that can hold up to n
;             characters — a COUNTED string (1 length byte + n data
;             bytes), the same representation this project's own
;             WORD_BUF (core/interp.asm) and dictionary name fields
;             already use internally, not a new convention.
;   PLACE     ( addr len dest -- )   copies len bytes from addr into
;             dest's own data area and sets dest's count byte to len —
;             the standard way to fill a STRING buffer from an S"
;             literal, KEY-built text, or another string.
;   COUNT     ( caddr -- addr len )   the standard bridge from a
;             COUNTED string (STRING's own representation) to the
;             (addr len) pair every other word here expects.
;   LEN       ( caddr -- n )   BASIC-style convenience: just a counted
;             string's own length, without needing COUNT's full
;             (addr len) pair — reads the count byte directly.
;   VAL       ( addr len -- n )   parses a signed decimal integer out
;             of an (addr len) string, the exact same digit-
;             accumulation algorithm core/interp.asm's own NUMBER
;             already uses for typed literals, just reading from a
;             given span instead of a counted token buffer. Not a
;             general expression evaluator (BASIC's own VAL() isn't
;             either, in spirit — it parses A number) — an invalid or
;             empty string returns 0, no error signal, matching this
;             project's own established "no error recovery yet" scope
;             (core/dict.asm's own note) and kernel/math's own safe-
;             default convention (MATH_DIVIDE16's divide-by-zero).
;
; DELIBERATELY NOT INCLUDED THIS PHASE (a real, stated scope cut, not
; an oversight): CHR$, STR$, UPPER$/LOWER$, LEFT$/RIGHT$, INSTR, CODE.
; The six words above turn "no string handling at all" into "you can
; hold text in a variable, print it, measure it, and read a number out
; of it" — the part of the original gap that actually blocked writing
; real programs; the rest are conveniences layered on TOP of this same
; (addr len)/counted-string foundation, better done later once real
; programs reveal which ones are actually missed.
;
; STRING'S OWN BUFFER IS FIXED-SIZE, LIKE BASIC's OWN STRING VARIABLES:
; PLACE-ing more than n characters into an n-character STRING buffer
; overruns it — no bounds check exists, matching every other memory-
; touching word in this project (@, !, ARRAY's own elements before it).
; ============================================================================

    IFNDEF CORE_STRING_ASM
    DEFINE CORE_STRING_ASM

; Placed starting right at $87E9, the next free byte after
; core/doloop.asm's own LEAVE_HEAD_TABLE ($87D9, 16 bytes, ending at
; $87E9) -- verified free by grepping every existing "EQU $8.." across
; core/, kernel/, and include/ first, not assumed (core/doloop.asm's
; own +LOOP scratch collided with core/print.asm's PRINT_ROW/PRINT_COL
; by skipping exactly this check — see docs/PROJECT_PLAN.md's Phase 25
; section).
VAL_PTR   EQU $87E9   ; 2 bytes: VAL's own scratch, mirroring
                       ; core/interp.asm's NUM_PTR -- next unread
                       ; character while parsing
VAL_COUNT EQU $87EB   ; 1 byte: VAL's own scratch, mirroring NUM_COUNT
VAL_NEG   EQU $87EC   ; 1 byte: VAL's own scratch, mirroring NUM_NEG
DOSSTR_ADDR EQU $87ED ; 2 bytes: DOSSTR's own scratch (the string's
                       ; address, held across computing the
                       ; continuation address -- see DOSSTR's own
                       ; header)
DOSSTR_LEN  EQU $87EF ; 1 byte: DOSSTR's own scratch (the string's
                       ; length, held the same way)
SQUOTE_CODE_ADDR EQU $87F0 ; 2 bytes: W_SQUOTE's own scratch -- HERE's
                       ; own value from right before it starts
                       ; compiling, remembered so it can roll HERE back
                       ; to reclaim the compiled bytes when interpreting
                       ; (see W_SQUOTE's own header) -- ends at $87F2

; ============================================================================
; DOSSTR — NOT a dictionary word. Runtime half of a compiled S"
; string: reads a length byte and that many characters off its own
; return address (exactly core/dotquote.asm's own DOSTR idiom), but
; instead of printing them, pushes (addr, len) onto the DATA stack —
; addr being the inline string's own location, still live in the
; dictionary (never copied), so it stays valid only as long as the
; surrounding word's own compiled code does (true of every dictionary
; word already, not a new caveat).
; ============================================================================
DOSSTR:
    pop  hl                   ; hl = address of the length byte
    ld   a, (hl)
    ld   (DOSSTR_LEN), a
    inc  hl                    ; hl = the string's own address (first
                                ; char)
    ld   (DOSSTR_ADDR), hl
    ld   e, a
    ld   d, 0
    add  hl, de                 ; hl = continuation address (string
                                 ; address + length)
    push hl                      ; restore as the real return address
    ld   hl, (DOSSTR_ADDR)
    call DPUSH_HL                 ; push addr
    ld   a, (DOSSTR_LEN)
    ld   l, a
    ld   h, 0
    call DPUSH_HL                  ; push len
    ret

; ============================================================================
; S" ( -- addr len )  IMMEDIATE
; ============================================================================
H_SQUOTE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   $82, "S", '"'       ; length 2, IMMEDIATE (bit 7 set)
W_SQUOTE:
    ld   hl, (HERE)
    ld   (SQUOTE_CODE_ADDR), hl   ; remember where "CALL DOSSTR" itself
                                   ; starts, so it can be invoked
                                   ; directly below if interpreting
    ld   hl, DOSSTR
    call COMPILE_CALL

    ; identical scan loop to core/dotquote.asm's own W_DOTQUOTE -- see
    ; that word's own header for why no leading-space skip is needed
    ; here either (W_WORD already consumed it while tokenizing S"
    ; itself)
    ld   de, (HERE)
    push de                    ; stash the length byte's own address
    inc  de                    ; leave room for it; string chars start
                               ; right after
    ld   b, 0                  ; running character count
.scan:
    ld   hl, (SRC_END)
    ld   a, h
    ld   c, l
    ld   hl, (SRC_PTR)
    cp   h
    jr   nz, .scan_continue
    ld   a, c
    cp   l
    jr   z, .scandone          ; ran off the end of source with no
                               ; closing '"' -- safety net
.scan_continue:
    ld   a, (hl)
    cp   '"'
    jr   z, .scandone_consume
    ld   (de), a
    inc  hl
    ld   (SRC_PTR), hl
    inc  de
    inc  b
    jr   .scan
.scandone_consume:
    inc  hl
    ld   (SRC_PTR), hl         ; consume the closing '"'
.scandone:
    pop  hl                    ; hl = the length byte's own address
    ld   (hl), b
    ld   (HERE), de

    ld   a, (STATE)
    or   a
    ret  nz                     ; compiling: leave the compiled bytes
                                 ; in place, unchanged from before --
                                 ; the surrounding definition's own
                                 ; later execution will reach them in
                                 ; due course

    ; interpreting: push (addr len) OURSELVES instead of trying to
    ; invoke the "CALL DOSSTR" just compiled above. A first attempt at
    ; this fix did `jp` straight into that compiled call, reasoning
    ; that DOSSTR "returns correctly regardless of who called it" --
    ; true in isolation, but wrong here: DOSSTR's own contract is to
    ; return to whatever code FOLLOWS its inline string data, which is
    ; exactly right when that data sits inside a colon definition's
    ; body (the next compiled word), but at the top level there IS no
    ; following code -- just blank, uninitialized dictionary space --
    ; and DOSSTR's own RET landed straight in it, executing garbage as
    ; code. A real Fuse run hung completely, not just failed a check.
    ; Pushing the values directly here sidesteps the whole question by
    ; never running DOSSTR at all in this case; W_SQUOTE just RETs
    ; normally afterward, landing back at its own real caller no matter
    ; what called it.
    inc  hl                     ; hl = the string's own char data (hl
                                 ; still holds the length byte's own
                                 ; address from just above; the actual
                                 ; text starts right after it)
    call DPUSH_HL                ; push addr
    ld   a, b                    ; len -- still intact; nothing since
                                 ; the scan loop ended has touched B
    ld   l, a
    ld   h, 0
    call DPUSH_HL                 ; push len

    ; also reclaim the dictionary space "CALL DOSSTR" and the string's
    ; own inline bytes used -- none of it is needed when interpreting,
    ; since the values are already on the stack directly above
    ld   hl, (SQUOTE_CODE_ADDR)
    ld   (HERE), hl
    ret

; ============================================================================
; TYPE ( addr len -- )
; ============================================================================
H_TYPE:
    DW   H_SQUOTE
    DB   4, "T", "Y", "P", "E"
W_TYPE:
    call DPOP_HL              ; hl = len
    ld   a, l
    ld   b, a                  ; b = len (this project's strings are
                                ; always well under 256 chars)
    call DPOP_HL                ; hl = addr
    ld   a, b
    or   a
    ret  z                       ; empty string -- nothing to print
.loop:
    ld   a, (hl)
    push hl                      ; W_EMIT (via GFX_PUTCHAR) destroys
                                  ; HL -- preserve our own string
                                  ; pointer (core/print.asm's W_DOT and
                                  ; core/dotquote.asm's DOSTR both
                                  ; document this same precaution)
    push bc
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .loop
    ret

; ============================================================================
; STRING ( n "name" -- )
; ============================================================================
H_STRING:
    DW   H_TYPE
    DB   6, "S", "T", "R", "I", "N", "G"
W_STRING:
    call DPOP_HL             ; hl = n (max characters)
    push hl                  ; stashed briefly on the Z80 hardware
                              ; stack -- safe: symmetric push/pop
                              ; within this one routine's own body,
                              ; matching core/array.asm's own W_ARRAY
                              ; (same technique, same justification)
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
    ld   a, (hl)                  ; name length (already <= 31, W_WORD
                                   ; truncates at 32)
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
    ld   (HERE), de                ; HERE now points to this word's own
                                    ; body, right where the compiled
                                    ; literal below will start

    ld   hl, (HERE)
    ld   de, 6                     ; 5-byte compiled literal (CALL
                                    ; DOLIT + 2-byte target) + 1-byte
                                    ; RET -- the buffer's own count
                                    ; byte and data sit right after
    add  hl, de                    ; hl = the buffer's own base address
                                    ; (its own count byte)
    call COMPILE_LITERAL           ; compiles CALL DOLIT + that address
    ld   a, $C9                    ; Z80 RET opcode
    call COMPILE_BYTE

    pop  hl                        ; hl = n, restored (still the max-
                                    ; character count from this
                                    ; routine's own entry)
    inc  hl                        ; +1 for the count byte itself
    ld   b, h
    ld   c, l                      ; bc = total bytes to zero
    ld   hl, (HERE)                ; hl == the buffer's own base
                                    ; address, exactly as computed above
    ld   a, b
    or   c
    jr   z, .noinit                ; n=0 -- nothing to zero
.zeroloop:
    xor  a
    ld   (hl), a
    inc  hl
    dec  bc
    ld   a, b
    or   c
    jr   nz, .zeroloop
.noinit:
    ld   (HERE), hl

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

; ============================================================================
; PLACE ( addr len dest -- )
; ============================================================================
H_PLACE:
    DW   H_STRING
    DB   5, "P", "L", "A", "C", "E"
W_PLACE:
    call DPOP_HL              ; hl = dest
    push hl                    ; stashed on the Z80 hardware stack --
                                ; safe, symmetric within this routine
    call DPOP_HL                 ; hl = len
    ld   a, l
    push af                       ; stash len the same way (this
                                   ; project's strings fit in a byte)
    call DPOP_HL                    ; hl = addr (source)
    pop  af
    ld   b, a                        ; b = len
    pop  de                           ; de = dest
    ld   a, b
    ld   (de), a                       ; dest's own count byte = len
    inc  de                             ; de -> dest's own data area
    ld   a, b
    or   a
    ret  z                                ; len=0 -- nothing more to copy
.copyloop:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .copyloop
    ret

; ============================================================================
; COUNT ( caddr -- addr len )
; ============================================================================
H_COUNT:
    DW   H_PLACE
    DB   5, "C", "O", "U", "N", "T"
W_COUNT:
    call DPOP_HL              ; hl = caddr
    ld   a, (hl)                ; a = the count byte (len) -- safe to
                                 ; hold across DPUSH_HL below, which
                                 ; never touches AF
    inc  hl                      ; hl = the data address
    call DPUSH_HL                 ; push addr
    ld   l, a
    ld   h, 0
    call DPUSH_HL                  ; push len
    ret

; ============================================================================
; LEN ( caddr -- n )
; ============================================================================
H_LEN:
    DW   H_COUNT
    DB   3, "L", "E", "N"
W_LEN:
    call DPOP_HL
    ld   a, (hl)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    ret

; ============================================================================
; VAL ( addr len -- n )
; Same digit-accumulation algorithm as core/interp.asm's own NUMBER
; (signed, *10+digit, truncating on the first non-digit) -- duplicated
; rather than shared, for the same reason core/variable.asm's own
; header already gives for its own duplicated header-building code:
; never modify an already-stable, widely-shared file (core/interp.asm)
; for a later phase's convenience. Unlike NUMBER, there is no dictionary
; lookup to try first -- VAL always parses, and an invalid or empty
; string simply returns 0 (no error signal, matching this project's own
; established scope).
; ============================================================================
H_VAL:
    DW   H_LEN
    DB   3, "V", "A", "L"
W_VAL:
    call DPOP_HL              ; hl = len
    ld   a, l
    or   a
    jr   z, .fail               ; empty string -- 0
    ld   (VAL_COUNT), a
    call DPOP_HL                  ; hl = addr
    ld   (VAL_PTR), hl
    xor  a
    ld   (VAL_NEG), a
    ld   a, (hl)
    cp   "-"
    jr   nz, .noneg
    ld   a, 1
    ld   (VAL_NEG), a
    inc  hl
    ld   (VAL_PTR), hl
    ld   a, (VAL_COUNT)
    dec  a
    ld   (VAL_COUNT), a
    jr   z, .fail                ; lone "-" is not a number
.noneg:
    ld   de, 0                    ; de = running magnitude
.digitloop:
    ld   a, (VAL_COUNT)
    or   a
    jr   z, .donedigits
    dec  a
    ld   (VAL_COUNT), a
    ld   hl, (VAL_PTR)
    ld   a, (hl)
    inc  hl
    ld   (VAL_PTR), hl
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
    ld   a, (VAL_NEG)
    or   a
    jr   z, .positive
    ex   de, hl
    call MATH_NEGATE16
    jr   .pushresult
.positive:
    ex   de, hl                   ; hl = result
.pushresult:
    call DPUSH_HL
    ret
.fail:
    ld   hl, 0
    call DPUSH_HL
    ret

DICT_LATEST_INIT_STRING EQU H_VAL   ; head of the dictionary once this
                                     ; file's own words are included

    ENDIF
