; ============================================================================
; core/forget.asm — Phase 50: FORGET
;
; Builds on core/dict.asm (LATEST, HERE, DPUSH_HL, DPOP_HL) and
; core/interp.asm (W_WORD, WORD_SRC_ADDR — reused for the exact same
; "parse a name into a counted string" purpose core/create.asm's own
; CREATE and `:` already use it for, never concurrently with either,
; same convention core/variable.asm's own header already documents) and
; core/print.asm/core/outwords.asm (W_EMIT) for its own error messages
; — all must be INCLUDEd first.
;
; SCRATCH: FORGET_TARGET_ADDR ($8A60, 2 bytes) -- verified free by
; grepping every "$8A5x"/"$8Axx" literal across core/, kernel/,
; include/, and rom/ before picking it (the same method every phase
; since Phase 5 has used), landing in the open gap between
; core/printer.asm's own PRINT_LLIST_HDR (ends ~$8A51) and
; core/float.asm's own FSTACK_LIMIT ($8C00).
;
; WHAT THIS ADDS: FORGET ( "name" -- ), parses a name (via W_WORD, same
; convention as CREATE) and removes that word and every word defined
; AFTER it (i.e. every word between it and LATEST, inclusive) from the
; dictionary, reclaiming their RAM.
;
; THE REAL HAZARD, addressed head-on: this project's dictionary is a
; compile-time-fixed chain of ROM-resident built-in words (physically
; read-only, spliced together via DICT_CHAIN_POINT across many
; core/*.asm files) with a RAM-resident tail appended after cold start
; (FORTH_DICT_RAM, core/dict.asm). "Forgetting" a ROM-resident word
; can't reclaim any space (there's nothing to reclaim — the ROM image
; itself doesn't shrink) and rewinding LATEST into ROM territory would
; be a near-certain user mistake (typically "FORGET SOMEWORD" meant to
; typo-correct or reclaim space, when SOMEWORD turns out to already be
; a Phase-2-through-49 built-in). THE DECISION: REFUSE, with a clear
; printed message, rather than silently allowing it. Reasoning: the
; "harmless but pointless" alternative (allow it, LATEST ends up
; pointing partway through the ROM's own hand-linked chain, HERE
; untouched since there's nothing RAM-side to reclaim) is not actually
; harmless — it would silently delete every RAM-resident word the user
; defined MORE RECENTLY than cold start's own last splice point (e.g.
; "FORGET DUP" would legally walk clear back to H_DROP, LINK=0, wiping
; the ENTIRE user dictionary) while reporting nothing wrong, which is a
; strictly worse failure mode than a refused command with an error
; message. Refusing costs nothing a real program needs (nobody
; legitimately wants to erase every user word by naming a built-in).
;
; NOT IMPLEMENTED VIA THROW: a specific ANS Forth exception code exists
; for neither "word is ROM-resident" nor "FORGET target not found" —
; core/tick.asm's own -13 (undefined word) is the closest existing
; precedent but describes a different situation (no such word at all,
; not "found it, but it's not RAM-resident"). Rather than invent a new,
; arbitrary negative code with no ANS Forth meaning and no other user
; of it yet, both failure paths here print a short, specific message
; directly (the task's own stated minimum: "at minimum a clear printed
; message") and return NORMALLY (not aborting the rest of the current
; line) — a refused FORGET is a graceful no-op, not an exceptional
; unwind situation the way an uncaught arithmetic/stack error is.
;
; RAM DICTIONARY IS CONFIRMED STRICTLY APPEND-ONLY before this file
; relies on that assumption (per the task's own instruction to verify,
; not assume it): every existing HERE-advancing word this project has
; ever shipped (`:`, VARIABLE, CONSTANT, ARRAY, and this same phase's
; own CREATE/`,`/C,`/ALLOT) only ever READS the current HERE, appends
; forward, and WRITES HERE back larger (ALLOT's own signed add is the
; only exception, and only if a caller deliberately passes a negative
; count — confirmed by reading every one of those files' own code
; directly, not assumed). Likewise LATEST only ever advances to a
; strictly higher RAM address with each new definition (NEW_HEADER_ADDR
; is always the OLD HERE, which was always higher than the previous
; LATEST). This means walking the chain from LATEST down to a target's
; own header, then setting LATEST := target's own LINK field and
; HERE := target's own header address, correctly reclaims exactly "that
; word and everything defined after it" with no gaps and no dangling
; references, exactly as this file's own W_FORGET does below.
; ============================================================================

    IFNDEF CORE_FORGET_ASM
    DEFINE CORE_FORGET_ASM

FORGET_TARGET_ADDR EQU $8A60   ; 2 bytes: this file's own scratch, see
                                ; header above for why this address

; ============================================================================
; FORGET_PRINT_MSG ( HL = null-terminated message address -- )  NOT a
; dictionary word. Same per-character W_EMIT idiom rom/forth_boot.asm's
; own RUNTIME_ERROR_HOOK/INTERPRET_UNKNOWN_WORD and core/vlist.asm's own
; VLIST already use — reusing the IDIOM (this project has no shared,
; callable "print a string" routine to reuse directly; each existing
; user of the pattern duplicates it locally, same as here).
; ============================================================================
FORGET_PRINT_MSG:
    ld   a, (hl)
    or   a
    ret  z
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   FORGET_PRINT_MSG

; ============================================================================
; FORGET ( "name" -- )
; ============================================================================
H_FORGET:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   6, "F","O","R","G","E","T"
W_FORGET:
    call W_WORD
    call DPOP_HL
    ld   (WORD_SRC_ADDR), hl

    ld   hl, (LATEST)
.searchloop:
    ld   a, h
    or   l
    jr   z, .notfound            ; walked off the oldest entry (LINK=0)
                                   ; without a match
    ld   (FORGET_TARGET_ADDR), hl  ; candidate header addr, staged
    ld   de, 2
    add  hl, de                     ; hl -> candidate's LENFLAGS
    ld   a, (hl)
    and  $1F                         ; candidate name length (IMMEDIATE
                                       ; bit masked off)
    ld   c, a
    inc  hl                           ; hl -> candidate's first name char
    ld   de, (WORD_SRC_ADDR)
    ld   a, (de)                       ; a = target name's own length
    cp   c
    jr   nz, .nomatch
    inc  de                             ; de -> target name's own chars
    ld   a, c
    or   a
    jr   z, .matched                     ; zero-length: trivially equal
    ld   b, c
.cmploop:
    ld   a, (de)
    cp   (hl)
    jr   nz, .nomatch
    inc  hl
    inc  de
    djnz .cmploop
.matched:
    ld   hl, (FORGET_TARGET_ADDR)
    ld   de, FORTH_DICT_RAM
    or   a
    sbc  hl, de                          ; hl = target - FORTH_DICT_RAM
    jr   c, .refuse_rom                   ; target < FORTH_DICT_RAM:
                                            ; ROM-resident, refuse (see
                                            ; this file's own header)
    ld   hl, (FORGET_TARGET_ADDR)
    ld   (HERE), hl                        ; reclaim: HERE rewinds to
                                             ; the target's own header
                                             ; address
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                            ; de = target's own LINK
    ld   (LATEST), de                        ; ... becomes the new LATEST
    ret
.nomatch:
    ld   hl, (FORGET_TARGET_ADDR)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                             ; de = candidate's own LINK
    ex   de, hl                               ; hl = next-older candidate
    jr   .searchloop
.refuse_rom:
    ld   hl, FORGET_MSG_ROM
    call FORGET_PRINT_MSG
    ret
.notfound:
    ld   hl, FORGET_MSG_NOTFOUND
    call FORGET_PRINT_MSG
    ret

FORGET_MSG_ROM:      DB "FORGET: BUILT-IN, REFUSED", 13, 0
FORGET_MSG_NOTFOUND: DB "FORGET: NOT FOUND", 13, 0

DICT_LATEST_INIT_FORGET EQU H_FORGET   ; head of the dictionary once
                                        ; this file's own words are
                                        ; included

    ENDIF
