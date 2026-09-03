; ============================================================================
; core/does.asm — Phase 50: DOES>
;
; Builds on core/dict.asm (LATEST, DPOP_HL) and core/create.asm (must be
; INCLUDEd first — this file patches the exact 6-byte "CALL DODOES / JP
; CREATE_DEFAULT_RET" runtime shape that file's own CREATE compiles; see
; that file's own header for the full mechanism this one completes).
;
; WHAT THIS ADDS: DOES> ( -- ), used inside a colon definition that
; itself calls CREATE, e.g.
;     : CONST CREATE , DOES> @ ;
;     5 CONST FIVE
;     FIVE .                 ( prints 5 )
;
; DOES> IS A PLAIN, NON-IMMEDIATE WORD, compiled inline like any other
; word CONST's own body calls (`: CONST CREATE , DOES> @ ;` compiles
; CALL W_CREATE, CALL W_COMMA, CALL W_DOES, CALL W_FETCH, then the RET
; `;` itself compiles) — it does NOT need to be IMMEDIATE, because its
; job only ever happens at CONST's own RUN time (when "5 CONST FIVE" is
; typed and CONST actually executes), never at CONST's own COMPILE time.
; This is the crux of the whole feature and worth stating plainly: DOES>
; patches the MOST RECENTLY CREATEd word (FIVE, in the example above)
; the instant CONST itself runs — NOT when FIVE itself is later invoked.
;
; HOW W_DOES FINDS "THE MOST RECENTLY CREATEd WORD": simply LATEST.
; core/dict.asm's own LATEST cell is already updated by CREATE the
; moment CREATE itself finishes running (see core/create.asm's own
; W_CREATE, its last real action before RET) — and nothing runs between
; CREATE's own return and DOES>'s own CALL within CONST's straight-line
; body that could touch LATEST again (COMMA/ALLOT/`,` never touch it).
; So by the time W_DOES executes, LATEST already points at exactly the
; word CREATE just built — no separate "last created" pointer needed,
; confirming the task's own suspicion that LATEST alone is sufficient.
;
; HOW W_DOES LOCATES THE PATCH SITE: LATEST's own header is
; LINK(2) + LENFLAGS(1) + NAME(namelen) + CALL DODOES(3) + JP nn(3) +
; <data field> — the exact same layout core/interp.asm's own FIND
; already computes (code_addr = header + 3 + namelen) to find any
; word's own code address. The JP instruction's own 2-byte OPERAND
; (the thing that actually needs patching) sits 4 bytes past that code
; address: 3 bytes for the CALL DODOES instruction, then 1 more byte
; for the JP opcode itself. W_DOES below computes exactly
; header + 3 + namelen + 4 and overwrites the 2 bytes there.
;
; HOW W_DOES FINDS "THE CODE THAT TEXTUALLY FOLLOWS DOES> IN THE
; DEFINING WORD'S OWN BODY": for free, via the Z80 CALL/RET mechanism
; itself. DOES> is compiled as `CALL W_DOES` inside CONST's own body,
; immediately followed by whatever comes next in CONST's source (`@` in
; the example, i.e. a compiled `CALL W_FETCH`). Z80's own CALL pushes
; the address of the NEXT instruction — which is exactly
; "the code that textually follows DOES>" — onto the hardware stack
; before transferring control to W_DOES. W_DOES only has to `pop` that
; address (into BC below) to have it; no separate bookkeeping or
; scanning of CONST's own compiled bytes is needed.
;
; WHAT HAPPENS AFTER THE PATCH — THE CRITICAL, EASY-TO-GET-WRONG PART:
; W_DOES must NOT return normally to the address it just popped and
; patched with (that would make CONST itself immediately execute "@"
; on its OWN just-finished work, which is nonsensical and wrong — the
; action part belongs to FIVE's FUTURE invocations, not to CONST's
; current one). Instead, after patching, W_DOES pops the NEXT item on
; the hardware stack — which is CONST's own return address, the one
; `CALL W_DOES` pushed UNDER the "action address" one, i.e. whatever
; called CONST in the first place (INTERPRET_RUN's own execute-dispatch,
; or an outer colon definition if CONST were itself invoked from inside
; one) — and jumps straight there. This is precisely "DOES>, at the
; point it executes, ends the calling defining word's own execution
; early," matching the task's own description exactly. CONST's own
; trailing `CALL W_FETCH` / RET (compiled after DOES> in ITS body) are
; never reached during CONST's own execution — they exist ONLY to be
; jumped into later, by FIVE's own runtime, via the JP mechanism
; core/create.asm's DODOES already documents.
;
; PROVEN NOT HARDCODED TO ONE SHAPE: rom/forth_smoke_p50.asm exercises
; TWO differently-shaped DOES> words — a scalar CONST-style one (above)
; and an array-style one using CELLS (core/array.asm, confirmed to
; already exist there before use) with a 3-argument action part
; (`SWAP CELLS + @`) — proving the patched JP target can be an
; arbitrarily long tail of compiled code, not just a single word.
; ============================================================================

    IFNDEF CORE_DOES_ASM
    DEFINE CORE_DOES_ASM

; ============================================================================
; DOES> ( -- )
; ============================================================================
H_DOES:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "D","O","E","S",">"
W_DOES:
    pop  bc                  ; bc = action address -- the code that
                              ; textually follows DOES> in the defining
                              ; word's own body (see this file's own
                              ; header for why a plain `pop` is enough)
    ld   hl, (LATEST)         ; hl = the most-recently-CREATEd word's
                                ; own header address
    ld   de, 2
    add  hl, de                 ; hl -> LENFLAGS byte
    ld   a, (hl)
    and  $1F                     ; name length (IMMEDIATE bit, bit 7,
                                   ; masked off -- irrelevant here)
    inc  hl                       ; hl -> first name char == header+3
    ld   e, a
    ld   d, 0
    add  hl, de                    ; hl = code_addr (header+3+namelen)
    ld   de, 4                      ; skip CALL DODOES (3 bytes) + the
    add  hl, de                      ; JP opcode itself (1 byte) to
                                       ; reach the JP's own 2-byte
                                       ; operand -- the patch site
    ld   (hl), c
    inc  hl
    ld   (hl), b                      ; patched: that word's own JP now
                                        ; targets the action address
    pop  hl                             ; hl = the DEFINING word's own
                                          ; return address (its caller)
    jp   (hl)                            ; return there directly --
                                           ; CONST's own remaining
                                           ; compiled body (the action
                                           ; part) is deliberately never
                                           ; reached from here; see this
                                           ; file's own header

DICT_LATEST_INIT_DOES EQU H_DOES   ; head of the dictionary once this
                                    ; file's own words are included

    ENDIF
