; ============================================================================
; core/input.asm — Phase 28: ACCEPT and INPUT (line input)
;
; Builds on core/dict.asm, core/interp.asm, core/print.asm (needs
; W_EMIT), core/string.asm (INPUT needs VAL), and kernel/io/io.asm
; (needs IO_READ_KEY and, via its own INCLUDE, include/keys.inc's
; KEY_ENTER/KEY_DELETE) — core/key.asm already depends on all of this,
; so any ROM with `KEY` already has everything this file needs too.
; Chains its own dictionary entries via DICT_CHAIN_POINT, same
; convention as every other core/ file.
;
; WHAT THIS ADDS — the last of the six real gaps found by a direct
; audit of 2068-Leap's own BASIC ROM (`~/ts2068rom`) against this
; project's dictionary: `KEY` (Phase 20) reads a single raw keypress,
; but there was no way to read a whole LINE of typed text, the way
; BASIC's own INPUT statement does.
;
;   ACCEPT ( dest maxlen -- len )   reads characters from the keyboard
;             (via KEY's own IO_READ_KEY, blocking) into `dest`,
;             echoing each one as it's typed, until ENTER — returning
;             the actual number of characters typed (which may be less
;             than maxlen). DELETE removes the last character typed
;             (both from the buffer and visually from the screen).
;             Typing past maxlen is silently ignored (the key is
;             consumed, matching every other "no error signal, safe
;             default" convention in this project — kernel/math's
;             divide-by-zero, ARRAY's own lack of bounds checking) —
;             ENTER and DELETE still work normally once at the limit.
;             This is the standard ANS Forth word of the same name and
;             stack effect, not a name invented for this project.
;   INPUT  ( -- n )   BASIC-style convenience: reads a line via ACCEPT
;             into a small fixed internal buffer, then parses it with
;             core/string.asm's own VAL, returning the integer
;             directly — the exact shape of BASIC's own
;             `INPUT A` for a numeric variable. Lines longer than the
;             internal buffer (8 characters — enough for any signed
;             16-bit integer, "-32768", with a little room to spare)
;             are truncated at ACCEPT's own level, same as any other
;             ACCEPT caller with a small buffer.
;
; ACCEPT'S OWN VISUAL DELETE IS SCOPED, NOT FULLY GENERAL: it moves the
; print cursor back one column, blanks it, and moves back again —
; correct within a single row of typing, but not tracked across a row
; wrap (if the typed line is long enough to wrap past column 31,
; DELETE's own column arithmetic doesn't know to also move up a row).
; core/editor.asm's own EDITOR_PROCESS_KEY has the same class of
; limitation already, documented there — this isn't a new gap, just a
; new place it shows up.
; ============================================================================

    IFNDEF CORE_INPUT_ASM
    DEFINE CORE_INPUT_ASM

ACCEPT_DEST EQU $87F2   ; 2 bytes: ACCEPT's own scratch -- the
                        ; destination buffer's address
ACCEPT_MAX  EQU $87F4   ; 1 byte: ACCEPT's own scratch -- the maximum
                        ; character count
ACCEPT_LEN  EQU $87F5   ; 1 byte: ACCEPT's own scratch -- the running
                        ; (and, at the end, final) character count
ACCEPT_CHAR EQU $87F6   ; 1 byte: ACCEPT's own scratch -- the character
                        ; just read, held across the length check
FINPUT_BUF  EQU $87F7   ; 8 bytes: INPUT's own fixed internal buffer --
                        ; named FINPUT_BUF, not INPUT_BUF, because
                        ; include/sysvars.inc already has its own
                        ; unrelated INPUT_BUF (a real, caught duplicate-
                        ; label assembly error, not a style choice) --
                        ; ends at $87FF, the last free byte before
                        ; $8800 (informally reserved across this
                        ; project's own smoke ROMs for their own
                        ; CHECKPOINT_NUM scratch -- see e.g.
                        ; rom/forth_smoke_p27.asm)

; ============================================================================
; ACCEPT ( dest maxlen -- len )
; ============================================================================
H_ACCEPT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   6, "A", "C", "C", "E", "P", "T"
W_ACCEPT:
    call DPOP_HL             ; hl = maxlen
    ld   a, l
    ld   (ACCEPT_MAX), a
    call DPOP_HL              ; hl = dest
    ld   (ACCEPT_DEST), hl
    xor  a
    ld   (ACCEPT_LEN), a
.loop:
    call IO_READ_KEY           ; a = the next key (blocks until one
                                ; arrives)
    cp   KEY_ENTER
    jr   z, .done
    cp   KEY_DELETE
    jr   z, .del

    ld   (ACCEPT_CHAR), a
    ld   a, (ACCEPT_LEN)
    ld   b, a
    ld   a, (ACCEPT_MAX)
    cp   b
    jr   z, .loop              ; already at the limit -- silently
                                ; ignore this character, keep waiting

    ld   hl, (ACCEPT_DEST)
    ld   a, (ACCEPT_LEN)
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (ACCEPT_CHAR)
    ld   (hl), a                ; store the character

    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT                  ; echo it

    ld   a, (ACCEPT_LEN)
    inc  a
    ld   (ACCEPT_LEN), a
    jr   .loop

.del:
    ld   a, (ACCEPT_LEN)
    or   a
    jr   z, .loop               ; nothing typed yet -- nothing to
                                 ; delete
    dec  a
    ld   (ACCEPT_LEN), a

    ld   a, (PRINT_COL)
    or   a
    jr   z, .loop                ; already at column 0 -- see this
                                  ; file's own header on ACCEPT's
                                  ; scoped (not row-aware) visual delete
    dec  a
    ld   (PRINT_COL), a
    ld   hl, ' '
    call DPUSH_HL
    call W_EMIT                   ; blank the character on screen --
                                   ; W_EMIT's own advance leaves
                                   ; PRINT_COL one past where it should
                                   ; end up, corrected below
    ld   a, (PRINT_COL)
    dec  a
    ld   (PRINT_COL), a
    jr   .loop

.done:
    ld   a, (ACCEPT_LEN)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    ret

; ============================================================================
; INPUT ( -- n )
; ============================================================================
H_INPUT:
    DW   H_ACCEPT
    DB   5, "I", "N", "P", "U", "T"
W_INPUT:
    ld   hl, FINPUT_BUF
    call DPUSH_HL              ; push dest
    ld   hl, 8
    call DPUSH_HL               ; push maxlen
    call W_ACCEPT                 ; ( -- len )
    call DPOP_HL                    ; hl = len
    push hl                           ; stashed briefly on the Z80
                                       ; hardware stack -- safe:
                                       ; symmetric push/pop within this
                                       ; one routine's own body, same
                                       ; technique core/array.asm's own
                                       ; W_ARRAY uses
    ld   hl, FINPUT_BUF
    call DPUSH_HL                       ; push addr
    pop  hl                               ; hl = len, restored
    call DPUSH_HL                           ; push len -- stack is now
                                             ; (addr len), VAL's own
                                             ; expected order
    call W_VAL
    ret

DICT_LATEST_INIT_INPUT EQU H_INPUT   ; head of the dictionary once this
                                      ; file's own words are included

    ENDIF
