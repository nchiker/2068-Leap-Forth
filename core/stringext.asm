; ============================================================================
; core/stringext.asm — Phase 40: CHR, STR, UPPER, LOWER, LEFT, RIGHT,
; SEARCH, CODE (the string-function backlog)
;
; Builds on core/dict.asm (DPOP_HL/DPUSH_HL), core/print.asm (UDIV10,
; reused unchanged from W_DOT's own digit-extraction algorithm — both
; must be INCLUDEd first), and core/string.asm's own (addr len)/counted-
; string conventions (must be INCLUDEd first too — this file's own
; first header chains onto its tail, H_VAL).
;
; WHAT THIS ADDS: the six BASIC functions core/string.asm's own header
; explicitly deferred as "a real, stated scope cut, not an oversight"
; (CHR$, STR$, UPPER$/LOWER$, LEFT$/RIGHT$, INSTR, CODE) — flagged
; again by a later audit, then confirmed still genuinely missing when
; the user asked directly. Eight words total (UPPER$/LOWER$ and
; LEFT$/RIGHT$ each split into two), named the way this project always
; drops BASIC's own `$` sigil (`TYPE` not `PRINT$`, `S"` not `$"..."`)
; and, where a real ANS Forth standard word already exists for the
; exact same operation, using ITS name instead of inventing one:
; `INSTR` becomes `SEARCH` (ANS Forth's own STRING word-set name for
; "find one string inside another"), same job, real standard name.
;
;   CHR    ( code -- addr len )   the reverse of C@ + CODE below: writes
;          code's own low byte into a fixed 1-byte buffer and returns
;          it as a 1-character string.
;   STR    ( n -- addr len )   converts a signed integer to its decimal
;          string form, into a fixed 6-byte buffer (sign + up to 5
;          digits — "-32768" is the longest possible result). Shares
;          core/print.asm's own W_DOT digit-extraction algorithm
;          UNCHANGED (same UDIV10 division loop, same hardware-stack
;          digit buffering, even the same $8000-safe negate sequence
;          W_DOT's own header already documents) — this word only
;          differs in the LAST step, writing digits into a buffer
;          instead of EMITting them.
;   UPPER, LOWER   ( addr len -- addr len )   case-fold IN PLACE,
;          returning the SAME (addr len) unchanged — implemented by
;          PEEKING both stack cells directly ((ix+0..3), never popping
;          them at all, since the return value is identical to the
;          input), the simplest possible implementation once you
;          notice the signature doesn't actually need a round trip.
;          A REAL REQUIREMENT worth stating plainly, found via this
;          phase's own smoke ROM: because these two mutate IN PLACE,
;          addr must point at genuine, WRITABLE RAM — a `STRING`
;          buffer, `S"`'s own already-noted mutable case, or a `PLACE`
;          destination all qualify, but a plain ROM-resident string
;          literal (this project's own smoke ROMs' usual DB-declared
;          test data) does not: on this hardware a write to ROM is
;          simply discarded, no error, no crash, just no effect — and
;          neither UPPER/LOWER nor anything else in this project has
;          any way to detect that from the caller's own side. Every
;          OTHER word in this file only READS the given (addr len), so
;          this caveat is specific to these two.
;   LEFT, RIGHT   ( addr len n -- addr len' | addr' len' )   substring
;          by reference, not copy: Forth strings are already just an
;          (addr len) VIEW into existing memory, so "the first n
;          characters" is just a shorter len at the same addr (LEFT),
;          and "the last n characters" is a later addr with a shorter
;          len (RIGHT) — n > len clamps to the whole string unchanged
;          in both directions, never a read past the string's own end.
;   SEARCH   ( addr1 len1 addr2 len2 -- addr3 len3 flag )   real ANS
;          Forth STRING word-set semantics, not simplified: on a match,
;          addr3/len3 is the REMAINDER of the haystack starting at the
;          match (not just the matched substring itself) and flag is
;          true; on no match, addr3/len3 is the ORIGINAL addr1/len1
;          unchanged and flag is false. An empty needle (len2=0) is
;          treated as always NOT FOUND — a real, stated choice (the
;          ANS standard itself doesn't pin this down), the simpler and
;          more conservative of the two defensible answers.
;   CODE   ( addr len -- code )   the first character's own ASCII code
;          — directly composable from existing words as `DROP C@`
;          (Phase 36), so this word adds no new capability, only the
;          real ROM's own direct name for it.
;
; HAND-VERIFIED before any of this was trusted (this project's own
; established discipline):
;   STR(42) = "42" (len 2); STR(-5) = "-5" (len 2); STR(0) = "0"
;     (len 1) — the digit-extraction loop's own "nothing to extract"
;     path, checked separately from the general case.
;   RIGHT with addr=$8000,len=10,n=3: diff=len-n=7, new addr=$8007,
;     new len=3 — the last 3 bytes of a 10-byte string starting at
;     $8000 are exactly $8007-$8009.
;   SEARCH("HELLO WORLD","WORLD") finds pos=6 (0-indexed: H-E-L-L-O-
;     space-W...), giving addr3=addr1+6, len3=11-6=5, flag=true.
;   SEARCH("HELLO","XYZ"): maxpos=len1-len2=2, all three starting
;     positions (0,1,2) checked and rejected, flag=false, addr3/len3
;     unchanged.
;   SEARCH with len2>len1 (e.g. needle longer than haystack): the
;     maxpos subtraction itself borrows, caught and rejected before
;     the search loop ever runs a single comparison.
; ============================================================================

    IFNDEF CORE_STRINGEXT_ASM
    DEFINE CORE_STRINGEXT_ASM

; ---- Phase 40 RAM state — verified free by the same whole-tree
; "grep every EQU" pass Phase 39's own consolidation fix used, not
; assumed. Placed at $8900, comfortably past core/editor.asm's own
; tail ($88F5) and below core/float.asm's own FSTACK_LIMIT ($8C00). ----
CHR_BUF      EQU $8900   ; 1 byte: CHR's own one-character result
STR_BUF      EQU $8901   ; 6 bytes: STR's own result ("-32768" longest)
SRCH_ADDR1   EQU $8907   ; 2 bytes: SEARCH's own scratch (haystack addr)
SRCH_LEN1    EQU $8909   ; 1 byte:  haystack length
SRCH_ADDR2   EQU $890A   ; 2 bytes: needle addr
SRCH_LEN2    EQU $890C   ; 1 byte:  needle length
SRCH_POS     EQU $890D   ; 1 byte:  current starting offset being tried
SRCH_MAXPOS  EQU $890E   ; 1 byte:  last valid starting offset (len1-len2)

; ============================================================================
; CHR ( code -- addr len )
; ============================================================================
H_CHR:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   3, "C", "H", "R"
W_CHR:
    call DPOP_HL             ; hl = code
    ld   a, l
    ld   (CHR_BUF), a
    ld   hl, CHR_BUF
    call DPUSH_HL
    ld   hl, 1
    call DPUSH_HL
    ret

; ============================================================================
; STR ( n -- addr len )
; ============================================================================
H_STR:
    DW   H_CHR
    DB   3, "S", "T", "R"
W_STR:
    call DPOP_HL              ; hl = n
    ld   de, STR_BUF
    ld   a, h
    and  $80
    jr   z, .positive
    ld   a, "-"
    ld   (de), a
    inc  de
    xor  a                     ; negate hl -- correct even for $8000,
    sub  l                     ; same sequence core/print.asm's own
    ld   l, a                  ; W_DOT already uses and its own header
    ld   a, 0                  ; already confirms safe for that case
    sbc  a, h
    ld   h, a
.positive:
    ld   a, h
    or   l
    jr   nz, .hasdigits
    ld   a, "0"
    ld   (de), a
    inc  de
    jr   .done
.hasdigits:
    ld   c, 0
.divloop:
    ld   a, h
    or   l
    jr   z, .writedigits
    call UDIV10                ; hl = hl/10, a = digit (0-9) --
    push af                    ; core/print.asm's own routine, reused
    inc  c                     ; unchanged
    jr   .divloop
.writedigits:
    ld   b, c
.writeloop:
    pop  af
    add  a, "0"
    ld   (de), a
    inc  de
    djnz .writeloop
.done:
    ld   hl, STR_BUF
    call DPUSH_HL
    ex   de, hl                 ; hl = one past the last byte written
    ld   de, STR_BUF
    or   a
    sbc  hl, de                  ; hl = length = end - start
    call DPUSH_HL
    ret

; ============================================================================
; UPPER ( addr len -- addr len )  in place -- see this file's own
; header on why no pop/push round trip is needed at all.
; ============================================================================
H_UPPER:
    DW   H_STR
    DB   5, "U", "P", "P", "E", "R"
W_UPPER:
    ld   a, (ix+0)
    or   (ix+1)
    ret  z                      ; len == 0 -- nothing to do (also
                                 ; avoids DJNZ's own "0 means 256" trap)
    ld   b, (ix+0)
    ld   l, (ix+2)
    ld   h, (ix+3)
.loop:
    ld   a, (hl)
    cp   "a"
    jr   c, .skip
    cp   "z" + 1
    jr   nc, .skip
    sub  32                      ; lowercase -> uppercase
    ld   (hl), a
.skip:
    inc  hl
    djnz .loop
    ret

; ============================================================================
; LOWER ( addr len -- addr len )  in place -- mirror of UPPER above.
; ============================================================================
H_LOWER:
    DW   H_UPPER
    DB   5, "L", "O", "W", "E", "R"
W_LOWER:
    ld   a, (ix+0)
    or   (ix+1)
    ret  z
    ld   b, (ix+0)
    ld   l, (ix+2)
    ld   h, (ix+3)
.loop:
    ld   a, (hl)
    cp   "A"
    jr   c, .skip
    cp   "Z" + 1
    jr   nc, .skip
    add  a, 32                   ; uppercase -> lowercase
    ld   (hl), a
.skip:
    inc  hl
    djnz .loop
    ret

; ============================================================================
; LEFT ( addr len n -- addr len' )  the first n characters, clamped to
; len if n >= len (the whole string, unchanged).
; ============================================================================
H_LEFT:
    DW   H_LOWER
    DB   4, "L", "E", "F", "T"
W_LEFT:
    call DPOP_HL                ; hl = n
    ld   a, l
    ld   d, (ix+0)               ; d = current len (low byte)
    cp   d
    jr   nc, .keep                ; n >= len -- keep len as-is
    ld   (ix+0), a                 ; n < len -- new len = n
    ld   (ix+1), 0
.keep:
    ret

; ============================================================================
; RIGHT ( addr len n -- addr' len' )  the last n characters, clamped to
; len if n >= len (the whole string, unchanged).
; ============================================================================
H_RIGHT:
    DW   H_LEFT
    DB   5, "R", "I", "G", "H", "T"
W_RIGHT:
    call DPOP_HL                 ; hl = n
    ld   a, l
    ld   c, (ix+0)                ; c = current len (low byte)
    cp   c
    jr   nc, .keep                  ; n >= len -- keep addr/len as-is
    ld   b, a                        ; b = n (saved for the len write
                                     ; below, before it's overwritten)
    ld   a, c
    sub  b                            ; a = len - n = how far to advance
    ld   l, (ix+2)                     ; hl = current addr
    ld   h, (ix+3)
    ld   d, 0
    ld   e, a
    add  hl, de                         ; hl = addr + (len-n)
    ld   (ix+2), l
    ld   (ix+3), h
    ld   (ix+0), b                       ; len = n
    ld   (ix+1), 0
.keep:
    ret

; ============================================================================
; SEARCH ( addr1 len1 addr2 len2 -- addr3 len3 flag )  see this file's
; own header for the exact ANS Forth semantics this follows.
; ============================================================================
H_SEARCH:
    DW   H_RIGHT
    DB   6, "S", "E", "A", "R", "C", "H"
W_SEARCH:
    call DPOP_HL                  ; hl = len2
    ld   a, l
    ld   (SRCH_LEN2), a
    call DPOP_HL                   ; hl = addr2
    ld   (SRCH_ADDR2), hl
    ld   a, (ix+0)                  ; peek len1 -- addr1/len1 stay on
    ld   (SRCH_LEN1), a              ; the stack, popped only once the
    ld   l, (ix+2)                    ; final result is known (see the
    ld   h, (ix+3)                     ; .found/.notfound tails below)
    ld   (SRCH_ADDR1), hl

    ld   a, (SRCH_LEN2)
    or   a
    jp   z, .notfound                   ; empty needle -- see header

    ld   a, (SRCH_LEN1)
    ld   b, a
    ld   a, (SRCH_LEN2)
    ld   c, a
    ld   a, b
    sub  c                                ; a = len1 - len2
    jp   c, .notfound                      ; borrow -- needle longer
                                           ; than haystack, can't fit
    ld   (SRCH_MAXPOS), a
    xor  a
    ld   (SRCH_POS), a
.outer:
    ld   a, (SRCH_POS)
    ld   b, a
    ld   a, (SRCH_MAXPOS)
    cp   b
    jp   c, .notfound                       ; pos > maxpos -- exhausted
    ld   hl, (SRCH_ADDR1)
    ld   a, (SRCH_POS)
    ld   d, 0
    ld   e, a
    add  hl, de                              ; hl = addr1 + pos
    ld   de, (SRCH_ADDR2)
    ld   a, (SRCH_LEN2)
    ld   b, a
.inner:
    ld   a, (de)
    cp   (hl)
    jr   nz, .nomatch
    inc  hl
    inc  de
    djnz .inner
    jp   .found                                ; all len2 bytes matched
.nomatch:
    ld   a, (SRCH_POS)
    inc  a
    ld   (SRCH_POS), a
    jp   .outer
.found:
    call DPOP_HL                                ; discard len1 (already
    call DPOP_HL                                 ; captured); discard
                                                 ; addr1 too
    ld   hl, (SRCH_ADDR1)
    ld   a, (SRCH_POS)
    ld   d, 0
    ld   e, a
    add  hl, de
    call DPUSH_HL                                 ; addr3
    ld   a, (SRCH_LEN1)
    sub  e                                          ; len3 = len1 - pos
                                                    ; (e still holds pos
                                                    ; -- DPUSH_HL never
                                                    ; touches DE)
    ld   l, a
    ld   h, 0
    call DPUSH_HL                                    ; len3
    ld   hl, -1
    call DPUSH_HL                                     ; flag = true
    ret
.notfound:
    call DPOP_HL                                       ; discard len1
    call DPOP_HL                                        ; discard addr1
    ld   hl, (SRCH_ADDR1)
    call DPUSH_HL                                         ; addr3 = addr1
    ld   a, (SRCH_LEN1)
    ld   l, a
    ld   h, 0
    call DPUSH_HL                                           ; len3 = len1
    ld   hl, 0
    call DPUSH_HL                                            ; flag = false
    ret

; ============================================================================
; CODE ( addr len -- code )  directly composable as `DROP C@` (Phase
; 36) -- see this file's own header on why it's still provided.
; ============================================================================
H_CODE:
    DW   H_SEARCH
    DB   4, "C", "O", "D", "E"
W_CODE:
    call DPOP_HL                 ; hl = len (discarded)
    call DPOP_HL                  ; hl = addr
    ld   a, (hl)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    ret

DICT_LATEST_INIT_STRINGEXT EQU H_CODE   ; head of the dictionary once
                                          ; this file's own words are
                                          ; all included

    ENDIF
