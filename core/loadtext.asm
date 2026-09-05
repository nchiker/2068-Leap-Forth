; ============================================================================
; core/loadtext.asm — SAVE-TEXT / LOAD-TEXT: plain Forth *source* over tape
;
; Builds on core/dict.asm (DPUSH_HL/DPOP_HL, DICT_CHAIN_POINT), core/interp.asm
; (W_WORD, INTERPRET_RUN) and kernel/storage/storage.asm (STORAGE_SAVE/
; STORAGE_LOAD) — all must already be INCLUDEd. Also depends on
; core/free.asm's own DICT_RAM_CEILING already being defined (see
; LOADTEXT_BUF's own comment below) — the including ROM must INCLUDE
; core/free.asm before this file.
;
; WHAT PROBLEM THIS SOLVES: this project's existing SAVE/LOAD (core/
; storage.asm) transport a COMPILED DICTIONARY IMAGE — LATEST plus the raw
; compiled bytes from FORTH_DICT_RAM to HERE — through a provisional
; 512-byte ceiling (SAVE_LOAD_MAX_DICT), explicitly documented there as
; "not a considered real limit." That's the wrong shape for what the user
; actually wants: writing a real Forth *program* as ordinary source text,
; saving it to tape, and loading it back into a freshly-booted ROM where
; it gets RE-PARSED and compiled live — the same relationship real
; Sinclair BASIC's LOAD/SAVE have to BASIC program text, and exactly the
; relationship this project's own SAVE/LOAD does NOT have to Forth source.
; Named SAVE-TEXT/LOAD-TEXT (not e.g. LOAD"") specifically to avoid any
; confusion with real Sinclair BASIC's `LOAD "" SCREEN$` (an unrelated
; feature loading raw pixel data into video memory) — per the user's own
; explicit request.
;
; THE WIRE FORMAT IS NOT NEW: both words call STORAGE_SAVE/STORAGE_LOAD's
; documented public contract directly (include/kernel_api.inc: filename
; pointer+length, IX=data pointer, DE=data length) — the exact same real,
; byte-compatible tape protocol core/storage.asm's own SAVE/LOAD already
; use, unmodified. core/storage.asm's own header explains why that
; protocol must never vary even slightly (2068-Leap's own hard-won
; experience: an emulator/hardware round-trip failure that isn't visible
; as an assembly or logic error); this file takes that warning at face
; value and doesn't touch kernel/storage/storage.asm or core/storage.asm
; at all, additive-only.
;
; WHAT'S ACTUALLY DIFFERENT FROM SAVE/LOAD: no LATEST-prefixed payload
; wrapping. SAVE/LOAD need that wrapping because a compiled dictionary
; image isn't self-describing (LATEST, the head of a backward-linked
; list, can't be recovered from a byte count alone — see core/storage.asm's
; own header). Raw Forth SOURCE TEXT has no such problem: it's just bytes,
; verbatim, in and out. SAVE-TEXT hands STORAGE_SAVE the caller's own
; addr/len directly (no scratch copy needed at all — the caller's buffer
; already IS the payload); LOAD-TEXT receives into its own fixed
; LOADTEXT_BUF, then hands the received (address, actual length) straight
; to INTERPRET_RUN — the exact same outer interpreter every line typed at
; the live prompt already goes through (core/interp.asm), so `:`
; definitions and top-level code in the loaded text get compiled and run
; live, on the real dictionary, exactly like typing them would.
;
; LOADTEXT_BUF SIZING — not an arbitrary small number: core/free.asm's own
; audit (see that file's header) established DICT_RAM_CEILING ($F000) as
; the real, confirmed-safe upper bound for RAM dictionary growth above
; FORTH_DICT_RAM ($9800) — 22,528 bytes total. LOAD-TEXT's own received
; text has to live SOMEWHERE OTHER than that growth region while
; INTERPRET_RUN is simultaneously compiling new definitions INTO it (both
; SRC_PTR, walking the received text, and HERE, growing the dictionary,
; are live at once) — placing the receive buffer inside the same range
; HERE grows into would risk HERE overtaking the very text still being
; read from, corrupting a program while it's mid-load. This file instead
; reserves the TOP 8192 bytes of that same already-audited-safe range
; (LOADTEXT_BUF = DICT_RAM_CEILING - LOADTEXT_MAX_LEN, i.e. $D000-$EFFF)
; purely for the receive buffer, leaving the remaining 14,336 bytes
; ($9800-$CFFF) for actual compiled dictionary growth. 8192 bytes was
; picked to comfortably exceed the largest real test payload available
; (the Blackjack demo's own extracted source, ~5.8KB, itself a
; dozens-of-colon-definitions real program) with real margin to spare,
; while still leaving the large majority of the dictionary's own budget
; free for what actually gets compiled from it.
;
; HONEST LIMIT, stated plainly (same spirit as SAVE_LOAD_MAX_DICT's own
; caveat): this trades away part of the dictionary's own growth budget
; for LOAD-TEXT's receive buffer. If a caller's dictionary has already
; grown past $D000 (14KB+ of previously compiled RAM-resident
; definitions) before calling LOAD-TEXT, a large enough newly-loaded
; program could in principle grow HERE up into LOADTEXT_BUF's own range
; while still reading from it — not fenced off with a runtime guard here,
; matching this project's own established practice of documenting a real,
; narrow risk rather than guarding against every scenario the RAM budget
; itself doesn't yet call for guarding against (core/free.asm's own
; "STILL LEFT ON THE TABLE, ON PURPOSE" note is the same posture). Fine
; for this file's own verification (a fresh boot with an otherwise-empty
; dictionary), worth revisiting if a future caller's real usage pattern
; ever approaches it.
;
; ONE-LINE-INPUT CAVEAT: LOAD-TEXT calls INTERPRET_RUN a SECOND time,
; nested inside whatever INTERPRET_RUN call is already running the line
; that contains the word LOAD-TEXT itself (e.g. typed at the live
; prompt). That inner call overwrites the same global SRC_PTR/SRC_END
; core/interp.asm's own outer call was using. Harmless when LOAD-TEXT is
; (as expected) the last word on its own input line — the outer loop
; finds nothing left to read either way once LOAD-TEXT returns — but
; anything typed AFTER "... LOAD-TEXT" on the very same line is silently
; abandoned rather than read afterward. Matches how a real LOAD
; effectively hands control to a whole new program in practice; not
; fenced off, exactly the same class of documented-not-guarded scope note
; as SAVE/LOAD's own filename-length truncation above.
; ============================================================================

    IFNDEF CORE_LOADTEXT_ASM
    DEFINE CORE_LOADTEXT_ASM

; ---- SAVE-TEXT's own scratch, and LOAD-TEXT's own filename-padding
; scratch — confirmed-idle gap (core/interp.asm's own header: the same
; 2068-Leap PROG_AREA_START scalar-pool gap every other phase's own small
; scratch cells already live in), placed right after core/forget.asm's own
; FORGET_TARGET_ADDR (ends $8A62) with room to spare before core/float.asm's
; own FSTACK_LIMIT ($8C00) — confirmed via the same "grep every core/*.asm
; EQU in this range" method used throughout this project, not guessed. ----
SAVETEXT_NAME_PTR  EQU $8A62   ; 2 bytes: SAVE-TEXT's own scratch (filename chars ptr)
SAVETEXT_NAME_LEN  EQU $8A64   ; 1 byte:  SAVE-TEXT's own scratch (filename length)
SAVETEXT_DATA_PTR  EQU $8A65   ; 2 bytes: SAVE-TEXT's own scratch (the caller's addr)
SAVETEXT_DATA_LEN  EQU $8A67   ; 2 bytes: SAVE-TEXT's own scratch (the caller's len)
LOADTEXT_NAME_LEN  EQU $8A69   ; 1 byte:  LOAD-TEXT's own scratch (actual,
                               ; pre-padding filename length)
LOADTEXT_NAME_BUF  EQU $8A6A   ; 10 bytes: LOAD-TEXT's own scratch — a
                               ; space-padded, fixed-width copy of the
                               ; requested filename, built the same way
                               ; core/storage.asm's own W_LOAD already
                               ; does and for the same reason (see that
                               ; routine's own header: STORAGE_LOAD's
                               ; filename match is a fixed 10-byte
                               ; space-padded span, not caller-length-
                               ; bounded) — ends $8A74, still well inside
                               ; the confirmed-idle gap above

; ---- the receive buffer itself — see this file's own header for the
; full sizing rationale. Reserves the TOP of core/free.asm's own
; DICT_RAM_CEILING-bounded dictionary RAM range, not a separate pool. ----
LOADTEXT_MAX_LEN EQU 8192                          ; 8KB
LOADTEXT_BUF     EQU DICT_RAM_CEILING - LOADTEXT_MAX_LEN   ; $D000, given
                                                    ; today's $F000 ceiling

; ============================================================================
; SAVE-TEXT ( addr len "name" -- )
; Saves the `len` bytes of Forth source text at `addr` to tape under the
; parsed filename, via STORAGE_SAVE directly — no dictionary-image
; wrapping, the caller's own buffer is the payload verbatim.
; ============================================================================
H_SAVETEXT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL, per
                            ; this project's own established chain-splice
                            ; convention) immediately before this INCLUDE
    DB   9, "S","A","V","E","-","T","E","X","T"
W_SAVETEXT:
    call W_WORD
    call DPOP_HL
    ld   a, (hl)
    ld   (SAVETEXT_NAME_LEN), a
    inc  hl
    ld   (SAVETEXT_NAME_PTR), hl

    call DPOP_HL               ; hl = len (top of stack: addr len, "--" order)
    ld   (SAVETEXT_DATA_LEN), hl
    call DPOP_HL               ; hl = addr
    ld   (SAVETEXT_DATA_PTR), hl

    xor  a
    ld   (STORAGE_REQUEST_TYPE), a
    ld   hl, (SAVETEXT_NAME_PTR)
    ld   a, (SAVETEXT_NAME_LEN)
    ld   b, a
    push ix                    ; IX is 2068-Forth's OWN data stack
                                ; pointer -- STORAGE_SAVE's own header
                                ; says plainly it destroys IX (uses IX as
                                ; ITS OWN data pointer), so the real
                                ; caller's IX must be saved/restored here,
                                ; exactly like core/storage.asm's W_SAVE
                                ; already does
    ld   ix, (SAVETEXT_DATA_PTR)
    ld   de, (SAVETEXT_DATA_LEN)
    call STORAGE_SAVE
    pop  ix
    ret

; ============================================================================
; LOAD-TEXT ( "name" -- )
; Loads a filename's payload from tape via STORAGE_LOAD into LOADTEXT_BUF,
; then feeds the received (address, actual length) straight to
; INTERPRET_RUN — compiling and running whatever `:` definitions and
; top-level code the text contains, live, on the real dictionary. On
; failure (STORAGE_LOAD's own carry set), does nothing further — no
; partial INTERPRET_RUN call, matching core/storage.asm's own LOAD
; "leaves current state untouched on failure" posture.
; ============================================================================
H_LOADTEXT:
    DW   H_SAVETEXT
    DB   9, "L","O","A","D","-","T","E","X","T"
W_LOADTEXT:
    ; Same fixed-10-byte space-padded filename convention core/storage.asm's
    ; own W_LOAD uses, for the same reason (see that routine's own header
    ; and LOADTEXT_NAME_BUF's own comment above) -- STORAGE_LOAD's match
    ; always compares a fixed STORAGE_HEADER_FILENAME_LEN-byte span.
    call W_WORD
    call DPOP_HL
    ld   a, (hl)
    cp   STORAGE_HEADER_FILENAME_LEN + 1
    jr   c, .len_ok
    ld   a, STORAGE_HEADER_FILENAME_LEN    ; truncate an over-length
                                            ; filename rather than let the
                                            ; pad-length math below underflow
.len_ok:
    ld   (LOADTEXT_NAME_LEN), a
    inc  hl                     ; hl -> filename chars

    ld   de, LOADTEXT_NAME_BUF
    ld   a, (LOADTEXT_NAME_LEN)
    or   a
    jr   z, .pad_all             ; empty word (wildcard): nothing to copy
    ld   b, a
.copyname:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .copyname
.pad_all:
    ld   a, STORAGE_HEADER_FILENAME_LEN
    ld   b, a
    ld   a, (LOADTEXT_NAME_LEN)
    ld   c, a
    ld   a, b
    sub  c
    ld   b, a                    ; b = bytes of padding still needed
    or   a
    jr   z, .name_ready
    ld   a, " "
.padloop:
    ld   (de), a
    inc  de
    djnz .padloop
.name_ready:

    xor  a
    ld   (STORAGE_REQUEST_TYPE), a
    push ix                    ; save 2068-Forth's own data stack pointer
                                ; -- see W_SAVETEXT's identical comment
                                ; above on why this is required
    ld   hl, LOADTEXT_NAME_BUF
    ld   a, (LOADTEXT_NAME_LEN)
    ld   b, a
    ld   ix, LOADTEXT_BUF
    ld   de, LOADTEXT_MAX_LEN
    call STORAGE_LOAD
    pop  ix
    jr   c, .fail

    ; DE already holds the actual received length on success -- exactly
    ; what INTERPRET_RUN's own ( HL = source address, DE = source length )
    ; contract wants, no repackaging needed.
    ld   hl, LOADTEXT_BUF
    call INTERPRET_RUN
.fail:
    ret

DICT_LATEST_INIT_LOADTEXT EQU H_LOADTEXT   ; head of the dictionary once
                                           ; this file is the last one
                                           ; INCLUDEd

    ENDIF
