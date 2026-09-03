; ============================================================================
; core/create.asm — Phase 50: CREATE
;
; Builds on core/dict.asm (LATEST, HERE, DPUSH_HL) and core/interp.asm
; (W_WORD, DPOP_HL, WORD_SRC_ADDR/NEW_HEADER_ADDR, COMPILE_CALL,
; COMPILE_BYTE) — both must be INCLUDEd first. Also needs
; core/dictspace.asm's own H_ALLOT chained in immediately before this
; file (this file's own header links to it), though CREATE's own code
; does not call any of that file's words directly.
;
; HEADER-BUILDING CODE IS DUPLICATED FROM core/variable.asm/core/array.asm
; RATHER THAN FACTORED OUT — same established reason those two files
; already give: never modify an already-stable, widely-shared file
; (core/interp.asm) for a later phase's convenience; a little duplicated
; header-building code is the safer trade against a regression surface
; that wide.
;
; WHAT THIS ADDS: CREATE ( "name" -- ), the classic minimal Forth
; defining primitive. Parses the next word as the new definition's name
; (via W_WORD, exactly like `:`/VARIABLE/ARRAY already do) and builds a
; dictionary header for it, but UNLIKE VARIABLE/CONSTANT/ARRAY (which
; each compile their own fixed, non-patchable runtime), CREATE's own
; compiled runtime is deliberately built so that core/does.asm's DOES>
; can rewrite it later. When the new word is later invoked, with no
; DOES> ever having touched it, it does exactly the classic minimal
; CREATE thing: push the address of its own data field (the bytes
; immediately following its own 6-byte runtime, exactly where HERE sits
; the moment CREATE returns) and RET. Nothing is ALLOTted automatically
; — `10 CELLS ALLOT` (or a bare `,` per field) after CREATE is how a
; caller reserves the data field's own contents, matching real Forth's
; own CREATE...ALLOT idiom.
;
; THE PATCHABLE RUNTIME, exactly 6 bytes, compiled at the code address
; (right after the header's own name bytes, same position `:`/VARIABLE/
; ARRAY already put their own runtime at):
;     CALL DODOES              ; 3 bytes: $CD, DODOES-lo, DODOES-hi
;     JP   CREATE_DEFAULT_RET  ; 3 bytes: $C3, target-lo, target-hi
;   <data field starts here>
;
; DODOES (shared plumbing below, NOT a dictionary word — same category
; as core/dict.asm's own DPUSH_HL/DPOP_HL or core/interp.asm's own
; DOLIT) is what every CREATE'd word's own "CALL DODOES" actually calls.
; Z80's own CALL pushes the address of the NEXT instruction — which, for
; this exact 6-byte layout, is the JP instruction's own address, not
; some unrelated return point. DODOES:
;   1. pops that address into HL (call it JP_ADDR — literally where the
;      3-byte JP instruction's own bytes live in memory);
;   2. pushes JP_ADDR back onto the Z80 hardware stack immediately (SP
;      untouched net, just staged so step 4 below can retrieve it after
;      step 3 uses HL for something else);
;   3. computes JP_ADDR+3 (skipping over the JP instruction's own 3
;      bytes) — this is exactly the data field's own address, since the
;      JP instruction is the last thing before the data field in the
;      6-byte layout above — and pushes THAT onto the FORTH data stack
;      (DPUSH_HL) as the word's own single visible result so far;
;   4. pops JP_ADDR back off the Z80 stack into HL, then does `jp (hl)`
;      — the Z80 "jump to the address held in HL" instruction, which
;      sets PC := HL WITHOUT dereferencing memory at that address. Since
;      HL now holds JP_ADDR itself (the exact address where a real,
;      physical "JP nn" opcode and its 2-byte operand are stored), this
;      lands the CPU's own instruction fetch cycle right on top of that
;      JP instruction, which the Z80 then decodes and executes NORMALLY,
;      as real code, exactly as if control had simply fallen through
;      from the CALL DODOES straight into the JP that follows it. This
;      is the whole mechanism: DODOES doesn't need to know or care what
;      the JP's own 2-byte operand currently is, because it never reads
;      it — it just re-enters the instruction stream at the JP's own
;      address and lets the real Z80 CPU execute whatever is physically
;      written there right now.
;
; This is what makes the runtime PATCHABLE: CREATE_DEFAULT_RET is a
; SHARED, single, one-byte (`ret`) routine every fresh CREATE'd word's
; JP operand points at until something rewrites it. core/does.asm's
; DOES>, running once per DEFINING-word invocation, overwrites JUST
; those 2 operand bytes (at JP_ADDR+1) — nowhere else in the 6-byte
; runtime ever needs to change — with the address of whatever code
; should run AFTER the data-field address has already been pushed. See
; core/does.asm's own header for that half of the mechanism.
;
; WHY THIS SPECIFIC SHAPE AND NOT SOMETHING SIMPLER: a naive alternative
; ("CALL DODOES" alone, with DODOES itself doing the RET) can't be
; patched at all without either self-modifying the CALL's own 2-byte
; operand (which would change WHICH shared routine every CREATE'd word
; calls, not what happens per-word) or growing the runtime to carry a
; separate patchable data cell DODOES would have to read indirectly
; (extra indirection, extra bytes, no benefit). Compiling a REAL,
; directly-executable JP instruction into each word's own runtime and
; landing on it via `jp (hl)` needs no indirection at all: the "patch
; site" IS the operand of a real instruction the CPU will execute
; exactly as written, which is both the simplest and the fastest correct
; option for a subroutine-threaded Forth already built around "the Z80's
; own CALL/RET IS the inner interpreter" (core/dict.asm's own header).
;
; VARIABLE/CONSTANT LEFT UNCHANGED, DELIBERATELY NOT REWRITTEN ON TOP OF
; CREATE/,/ALLOT: their own current runtime (a compiled literal via
; DOLIT, then a bare RET — see core/variable.asm's own header) is
; simpler and one byte SHORTER per word (5+1=6 bytes, same total, but no
; DODOES indirection on every future invocation) than routing through
; DODOES's own extra CALL/pop/push/jp overhead for a case that never
; needs to be patched. Rewriting them for the sake of "sharing code with
; CREATE" would mean touching two already-stable, already-tested,
; already-widely-INCLUDEd files for a purely cosmetic consistency gain,
; with a real (if small) regression-and-performance-surface cost and NO
; behavior anyone asked for — this project's own established practice
; (stated in both of their own file headers already) is exactly to
; avoid this kind of edit. Left alone.
; ============================================================================

    IFNDEF CORE_CREATE_ASM
    DEFINE CORE_CREATE_ASM

; ============================================================================
; CREATE_DEFAULT_RET — NOT a dictionary word. The shared "do nothing
; more" action every freshly CREATE'd word's own JP instruction targets
; until core/does.asm's DOES> (if ever) repoints it elsewhere. A single
; `ret` is correct because DODOES has ALREADY pushed the data field
; address onto the FORTH data stack by the time this runs (see this
; file's own header) — the classic minimal CREATE runtime needs nothing
; further.
; ============================================================================
CREATE_DEFAULT_RET:
    ret

; ============================================================================
; DODOES — NOT a dictionary word. See this file's own header for the
; full mechanism. Destroys AF (not preserved across DPUSH_HL; matches
; this project's own established convention of not promising more than
; the individual word headers already state).
; ============================================================================
DODOES:
    pop  hl                  ; hl = JP_ADDR (address of the JP
                             ; instruction physically following the
                             ; CALL DODOES that got us here)
    push hl                   ; stage it back on the Z80 stack -- HL is
                                ; about to be reused for the data-field
                                ; address computation below
    ld   de, 3
    add  hl, de                 ; hl = JP_ADDR + 3 = the data field's
                                  ; own address (the JP instruction is
                                  ; exactly 3 bytes: opcode + 2-byte
                                  ; operand)
    call DPUSH_HL                 ; push the data field address onto
                                    ; the FORTH data stack -- this is
                                    ; the one visible effect of every
                                    ; CREATE'd word's own runtime, DOES>
                                    ; or not
    pop  hl                         ; hl = JP_ADDR again
    jp   (hl)                        ; land on the JP instruction's own
                                       ; bytes and let the real CPU
                                       ; execute it -- see this file's
                                       ; own header for why this is not
                                       ; a memory dereference

; ============================================================================
; CREATE ( "name" -- )
; ============================================================================
H_CREATE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   6, "C","R","E","A","T","E"
W_CREATE:
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
                                    ; code field, right where the
                                    ; 6-byte patchable runtime below
                                    ; will be compiled

    ld   hl, DODOES
    call COMPILE_CALL               ; compiles "CALL DODOES" (3 bytes),
                                      ; advances HERE by 3
    ld   a, $C3                      ; Z80 JP opcode
    call COMPILE_BYTE
    ld   hl, CREATE_DEFAULT_RET
    ld   a, l
    call COMPILE_BYTE
    ld   hl, CREATE_DEFAULT_RET      ; RELOADED -- COMPILE_BYTE's own
                                       ; body does `ld hl,(HERE)` and
                                       ; `inc hl` internally, destroying
                                       ; whatever HL held on entry (see
                                       ; its own header); a first, buggy
                                       ; draft read the operand's high
                                       ; byte from the clobbered HL left
                                       ; behind by the LOW byte's own
                                       ; COMPILE_BYTE call instead of
                                       ; from CREATE_DEFAULT_RET itself
                                       ; -- confirmed via a real Fuse
                                       ; hang (a freshly CREATEd word's
                                       ; own default runtime jumped into
                                       ; whatever HERE's own high byte
                                       ; happened to be instead of
                                       ; CREATE_DEFAULT_RET), not
                                       ; spotted by inspection alone
    ld   a, h
    call COMPILE_BYTE                ; JP CREATE_DEFAULT_RET now fully
                                       ; compiled (3 bytes); HERE sits
                                       ; exactly at the data field's own
                                       ; address, matching DODOES's own
                                       ; JP_ADDR+3 computation above

    ld   hl, (NEW_HEADER_ADDR)
    ld   (LATEST), hl
    ret

DICT_LATEST_INIT_CREATE EQU H_CREATE   ; head of the dictionary once
                                        ; this file's own words are
                                        ; included

    ENDIF
