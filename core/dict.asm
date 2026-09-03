; ============================================================================
; core/dict.asm — dictionary header format, data stack, Phase 2 CODE
; primitives
;
; NOT a kernel/ module: this is language-layer code (the dictionary and
; the words that manipulate it), analogous to 2068-Leap's basic/ sitting
; above its kernel/ — see docs/PROJECT_PLAN.md's Phase 1 architecture
; decisions. Nothing in this file touches hardware directly; it doesn't
; INCLUDE anything from kernel/ or include/ on purpose, so it can be
; assembled and tested (rom/forth_smoke.asm) with zero dependencies,
; matching the same "smallest provable step" principle rom/main.asm
; itself was built on.
;
; THREADING MODEL: subroutine threading (docs/PROJECT_PLAN.md Phase 1).
; Every word's code field is plain Z80 code ending in RET. A colon
; definition (once Phase 3's compiler exists) is just a straight-line
; list of CALLs to other words' code fields, also ending in RET — there
; is no NEXT dispatcher and no separate DOCOL/DOES> indirection to write
; for CODE words. The Z80's own CALL/RET *is* the inner interpreter, and
; SP is the return stack for free. The cost of that simplicity is that
; the data stack cannot also live on SP — see DSTACK below.
;
; DICTIONARY HEADER FORMAT (fixed for the life of this project unless a
; real need forces a change — Phase 3's CREATE must match this exactly):
;   LINK     : 2 bytes, address of the previous entry's LINK field, or
;              0 for the first entry in the dictionary.
;   LENFLAGS : 1 byte. Bits 0-4 = name length (0-31). Bit 7 = IMMEDIATE
;              (unused until Phase 3's compiler checks it; must be 0 for
;              every entry below). Bits 5-6 reserved, must be 0.
;   NAME     : LENFLAGS & $1F bytes, the word's name, not null-terminated
;              (length is already known from LENFLAGS), no case folding
;              done here (Phase 3's FIND decides that policy).
;   code     : immediately follows NAME, no padding, no alignment. This
;              address is both the header's "code field" and the actual
;              CALL target — there's no separate indirection cell the
;              way indirect-threaded Forths need, because subroutine
;              threading calls code directly.
;
; Each entry below is hand-linked (LINK points at the literal previous
; header label) rather than built through a defining macro. Eight
; entries don't justify a macro yet — see this project's own
; "no premature abstraction" convention — and hand-linking makes the
; chain trivially readable for the one thing that most needs to be
; correct on the first attempt: proving the header format actually
; works end to end. A defining macro is worth writing once Phase 3
; needs to generate many headers at once (CREATE, or bulk-defining a
; vocabulary), not before.
; ============================================================================

    IFNDEF CORE_DICT_ASM
    DEFINE CORE_DICT_ASM

; ============================================================================
; Data stack (parameter stack)
;
; IX is the data stack pointer. It always points at the current
; top-of-stack cell (low byte at (ix+0), high byte at (ix+1)); pushing
; decrements IX by 2 first, popping reads then increments IX by 2. This
; is the standard convention used by other Z80 subroutine-threaded
; Forths (e.g. CamelForth-Z80) for exactly this reason: IX is otherwise
; unused by anything in kernel/'s public API, so claiming it here
; creates no conflict with kernel calls a later phase's words might
; wrap (kernel/graphics, kernel/io, etc. all use HL/DE/BC/AF).
;
; DSTACK_TOP/DSTACK_LIMIT are PROVISIONAL addresses, exactly like
; rom/main.asm's own placeholder SP value — this project hasn't done
; its Phase 0 memory-map audit yet (docs/PROJECT_PLAN.md), so these
; will move once that exists. They're chosen here only to be clearly
; out of the way of anything else: this file has zero INCLUDEs, so
; nothing else can claim these addresses out from under it *within
; this smoke ROM*, but a later phase that also pulls in kernel/io or
; kernel/graphics (and therefore include/sysvars.inc) MUST re-check
; these against that file's own address allocation before reuse — see
; docs/PROJECT_PLAN.md Phase 0, item 2.
; ============================================================================
DSTACK_TOP   EQU $9800   ; empty-stack value for IX; first push lands at $97FE
DSTACK_LIMIT EQU $9000   ; lowest legal stack address — 1024 bytes of stack
                         ; (512 cells); no overflow check yet (Phase 2 has
                         ; no recursion or user input that could exhaust it)

; ============================================================================
; LATEST / HERE — dictionary growth pointers
;
; LATEST holds the address of the most recently defined word's LINK
; field (the head of the linked list; FIND, once Phase 3 writes it,
; starts searching here). HERE holds the next free byte for a NEW
; definition.
;
; CRITICAL ASYMMETRY: the primitives below are hand-assembled into this
; ROM image (read-only once burned/loaded). Phase 3's CREATE cannot
; extend the dictionary into ROM — it must compile new headers into
; RAM. So LATEST starts by pointing at H_STORE (the last ROM-resident
; primitive below), but HERE starts at a SEPARATE RAM area
; (FORTH_DICT_RAM), not at the byte after H_STORE's code. The LINK
; chain doesn't care that it crosses the ROM/RAM boundary — a 16-bit
; address is a 16-bit address either way — but HERE must never be
; computed as "wherever the ROM assembly left off," only ever as
; FORTH_DICT_RAM the first time and self-updating from there.
; ============================================================================
LATEST       EQU $9002   ; 2 bytes: RAM cell holding the head-of-dictionary address
HERE         EQU $9004   ; 2 bytes: RAM cell holding the next free RAM-dictionary byte
FORTH_DICT_RAM EQU $9800 ; first free byte of the RAM dictionary area Phase 3's
                         ; CREATE will compile into. Was $A000 until Phase 43's
                         ; own FREE audit (see core/free.asm's header) found
                         ; $9800-$9FFF sitting completely idle: DSTACK_TOP is
                         ; only a sentinel value for empty IX, not a byte the
                         ; stack ever occupies (real cells live BELOW it, down
                         ; to DSTACK_LIMIT) -- confirmed via the real build's
                         ; own .sym table (no other symbol lands in that
                         ; range) before reclaiming it, not guessed. Moving
                         ; this down 2048 bytes recovers that gap for FREE
                         ; with zero risk (nothing else ever referenced the
                         ; literal $A000).

; ============================================================================
; DROP ( n -- )
; First entry in the dictionary: LINK = 0.
; ============================================================================
H_DROP:
    DW   0
    DB   4, "D","R","O","P"
W_DROP:
    inc  ix
    inc  ix
    ret

; ============================================================================
; DUP ( n -- n n )
; ============================================================================
H_DUP:
    DW   H_DROP
    DB   3, "D","U","P"
W_DUP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    dec  ix
    dec  ix
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; SWAP ( a b -- b a )
; ============================================================================
H_SWAP:
    DW   H_DUP
    DB   4, "S","W","A","P"
W_SWAP:
    ld   l, (ix+0)     ; l,h = b (top)
    ld   h, (ix+1)
    ld   e, (ix+2)     ; e,d = a (second)
    ld   d, (ix+3)
    ld   (ix+0), e
    ld   (ix+1), d
    ld   (ix+2), l
    ld   (ix+3), h
    ret

; ============================================================================
; OVER ( a b -- a b a )
; ============================================================================
H_OVER:
    DW   H_SWAP
    DB   4, "O","V","E","R"
W_OVER:
    ld   l, (ix+2)     ; copy a (second cell) ...
    ld   h, (ix+3)
    dec  ix
    dec  ix
    ld   (ix+0), l     ; ... onto a new top
    ld   (ix+1), h
    ret

; ============================================================================
; + ( a b -- a+b )
; ============================================================================
H_PLUS:
    DW   H_OVER
    DB   1, "+"
W_PLUS:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)
    add  hl, de        ; hl = a+b
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; - ( a b -- a-b )
; ============================================================================
H_MINUS:
    DW   H_PLUS
    DB   1, "-"
W_MINUS:
    ld   l, (ix+0)     ; hl = b
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = a
    ld   d, (ix+1)
    ex   de, hl        ; hl = a, de = b
    or   a             ; clear carry before sbc
    sbc  hl, de        ; hl = a-b
    ld   (ix+0), l
    ld   (ix+1), h
    ret

; ============================================================================
; @ ( addr -- n )  fetch
; ============================================================================
H_FETCH:
    DW   H_MINUS
    DB   1, "@"
W_FETCH:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    ld   e, (hl)       ; de = cell at addr, low byte first
    inc  hl
    ld   d, (hl)
    ld   (ix+0), e
    ld   (ix+1), d
    ret

; ============================================================================
; ! ( n addr -- )  store
; ============================================================================
H_STORE:
    DW   H_FETCH
    DB   1, "!"
W_STORE:
    ld   l, (ix+0)     ; hl = addr
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ld   e, (ix+0)     ; de = n
    ld   d, (ix+1)
    inc  ix
    inc  ix
    ld   (hl), e
    inc  hl
    ld   (hl), d
    ret

; ---- dictionary boundary, for the smoke test and for Phase 3's CREATE ----
DICT_LATEST_INIT EQU H_STORE       ; value LATEST must be seeded with at cold start

; ============================================================================
; DPUSH_HL / DPOP_HL — shared data-stack plumbing, added for Phase 3.
;
; NOT dictionary words themselves (no header, not findable) — just a
; push/pop pair factored out for core/interp.asm's larger routines
; (WORD, FIND, NUMBER, the colon compiler), which are text-processing
; code, not performance-critical hot paths. The eight primitives above
; predate these and deliberately stay fully inlined instead of calling
; them: each is only a handful of instructions, and inlining avoids a
; CALL/RET pair on what real Forth code runs constantly. That tradeoff
; doesn't apply to WORD/FIND/NUMBER, which are already dozens of
; instructions each — sharing this pair there is clearer, not slower
; in any way that matters.
; ============================================================================
DPUSH_HL:                  ; push HL onto the data stack
    dec  ix
    dec  ix
    ld   (ix+0), l
    ld   (ix+1), h
    ret

DPOP_HL:                   ; pop the data stack into HL
    ld   l, (ix+0)
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ret

    ENDIF
