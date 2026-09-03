; ============================================================================
; core/immediate.asm — Phase 50: IMMEDIATE
;
; Builds on core/dict.asm (LATEST, DPUSH_HL not needed — no stack
; effect) — must be INCLUDEd first, same convention as every other
; core/ file.
;
; WHAT THIS ADDS: IMMEDIATE ( -- ), marking the MOST RECENTLY DEFINED
; word (LATEST) as immediate by setting bit 7 of its own LENFLAGS byte
; — exactly the bit core/interp.asm's own header already documents
; ("IMMEDIATE MECHANISM: LENFLAGS bit 7") and `;` already hardcodes for
; itself (`DB $81, ";"`, core/interp.asm's H_SEMICOLON). This is a
; small, low-risk addition precisely because that mechanism is already
; proven load-bearing — IMMEDIATE just exposes it as a word a user
; definition can invoke, instead of only ever being baked into a
; hand-written header byte at assembly time.
;
; NOT ITSELF IMMEDIATE: the standard, sufficient idiom is
;     : FOO ... ; IMMEDIATE
; typed as one line (or even split across separate lines at the live
; prompt) — by the time the IMMEDIATE token is read, `;` has already
; run and set STATE back to 0 (interpreting), so INTERPRET_RUN's own
; .loop always EXECUTES a found word while interpreting regardless of
; that word's own immediate flag (core/interp.asm's own .loop:
; `ld a,(STATE): or a: jr z,.execute`) — IMMEDIATE does not need to be
; immediate itself for this to work. (A word marking itself immediate
; from INSIDE its own still-compiling body, e.g. `: BAR IMMEDIATE ... ;`,
; would need IMMEDIATE to carry the bit itself — the Jupiter Ace manual's
; own IMMEDIATE entry documents only the after-`;` idiom, matching what
; this file implements; the task's own verification plan asks for
; exactly that shape too.)
; ============================================================================

    IFNDEF CORE_IMMEDIATE_ASM
    DEFINE CORE_IMMEDIATE_ASM

; ============================================================================
; IMMEDIATE ( -- )
; ============================================================================
H_IMMEDIATE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   9, "I","M","M","E","D","I","A","T","E"
W_IMMEDIATE:
    ld   hl, (LATEST)
    ld   de, 2
    add  hl, de              ; hl -> LENFLAGS byte
    ld   a, (hl)
    or   $80                  ; set bit 7 -- IMMEDIATE
    ld   (hl), a
    ret

DICT_LATEST_INIT_IMMEDIATE EQU H_IMMEDIATE   ; head of the dictionary
                                              ; once this file's own
                                              ; words are included

    ENDIF
