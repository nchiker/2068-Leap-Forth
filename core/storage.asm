; ============================================================================
; core/storage.asm — Phase 7: storage (SAVE-LIB, LOAD-LIB)
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — chains its own dictionary entries onto core/interp.asm's
; H_SEMICOLON) and needs kernel/storage/storage.asm INCLUDEd alongside
; it. Deliberately does NOT need core/control.asm or core/ts2068.asm —
; SAVE-LIB/LOAD-LIB are independent of control flow and graphics,
; matching every earlier phase's practice of only depending on what's
; actually needed.
;
; NEW DEPENDENCY (the overflow fix below): also needs core/throwcatch.asm
; INCLUDEd first, with THROW_CATCH_ENABLED already DEFINEd before
; core/interp.asm is INCLUDEd (that file's own header/core/interp.asm's
; own header state the exact requirement) — W_SAVELIB's own bounds
; check THROWs a real ANS Forth exception code rather than silently
; corrupting memory. Exactly the same real, plainly-stated new
; dependency core/tick.asm's own header already added for its own -13.
;
; RENAMED FROM SAVE/LOAD TO SAVE-LIB/LOAD-LIB: this file's own words
; persist the compiled RAM DICTIONARY IMAGE — the user's currently
; RAM-resident word "library", as a raw binary snapshot tied to the
; exact ROM build it was saved against (see THE PROBLEM/THE FIX below)
; — as opposed to core/loadtext.asm's SAVE-TEXT/LOAD-TEXT, which
; persists portable plain Forth SOURCE TEXT instead. Both mechanisms
; are kept, deliberately (see core/loadtext.asm's own header for the
; full tradeoff); the -LIB suffix lets each word's real behavior be
; identified by name alone, rather than requiring a reader to already
; know which of the two mechanisms bare "SAVE"/"LOAD" meant.
;
; DESIGN CONSTRAINT, stated up front because it shaped every decision
; below: kernel/storage's tape protocol is ported from the real TS2068
; ROM's own cassette routines specifically so it's byte-compatible with
; real hardware and real emulators. 2068-Leap's own hard-won experience
; (SAVE/LOAD bugs that only showed up as real emulator LOAD failures,
; not assembly or logic errors) is that this format is NOT safe to vary
; even slightly, or LOAD stops working in real emulators. Consequently:
; this file calls ONLY STORAGE_SAVE/STORAGE_LOAD's documented public
; contract (include/kernel_api.inc: filename pointer+length, IX=data
; pointer, DE=data length) and never reads or writes any of
; kernel/storage's own internal buffers (STORAGE_HEADER_BUF and
; friends) directly — those are private to kernel/storage, not part of
; the contract this file is allowed to depend on (see
; include/kernel_api.inc's own header: "Nothing outside kernel/ touches
; ... system variable addresses directly"). An earlier draft of this
; file considered smuggling extra metadata through the tape header's
; own "autostart" field; that idea was dropped for exactly this reason
; before being written, not caught by testing afterward.
;
; THE PROBLEM THAT DESIGN CONSTRAINT CREATES: SAVE-LIB needs to persist
; not just the compiled dictionary bytes ($FORTH_DICT_RAM through
; $HERE) but also LATEST (the head of the dictionary chain), since
; LATEST isn't recoverable purely from a byte count — dictionary
; headers are singly-linked BACKWARD (LINK points at the previous
; entry), so there's no way to walk forward from FORTH_DICT_RAM to find
; "the last header" without already knowing where it is.
;
; THE FIX: since STORAGE_SAVE/STORAGE_LOAD only care about a raw
; pointer and length — they transport whatever bytes they're given
; completely opaquely — this file builds its OWN small contiguous
; payload in a scratch buffer: 2 bytes for LATEST, followed by a copy
; of the actual dictionary bytes. That's a decision entirely within
; this file's own data format, invisible to and unconstrained by the
; tape wire protocol itself. LOAD-LIB reverses it: receive into the
; same scratch layout, restore LATEST from the first 2 bytes, copy the
; rest back to FORTH_DICT_RAM, and set HERE from the received length.
;
; TESTING: this file is verified against kernel/storage's own
; STORAGE_TEST_FAKE_SEND/STORAGE_TEST_FAKE_RECEIVE hooks (conditional
; compilation switches already present in kernel/storage/storage.asm,
; unused until this phase) rather than a real Fuse tape round-trip.
; rom/forth_smoke_p7.asm supplies the fake STORAGE_TEST_SEND_BLOCK/
; STORAGE_TEST_RECEIVE_BLOCK implementations those hooks call instead
; of the real tape-pulse routines. This proves this file's OWN wiring
; (filename handling, the LATEST-prefixed payload format, HERE/LATEST
; restoration, and — since the overflow fix below — both the
; over-512-byte round trip and the clean-refusal path) — it does NOT
; prove the real tape wire format actually round-trips in a real
; emulator, which is the exact risk the design constraint above exists
; to manage. That remains open, real, follow-up work, not silently
; treated as covered — see docs/PROJECT_PLAN.md's Phase 7 section.
; ============================================================================

    IFNDEF CORE_STORAGE_ASM
    DEFINE CORE_STORAGE_ASM

; ---- Phase 7 RAM state — same probe-verified $8426-$8FFF gap Phase 5
; and 6 already established as safe (docs/PROJECT_PLAN.md's Phase 5
; section), placed after core/editor.asm's own cells (ending at $8574)
; with a small margin. This layout is now MORE compact than it used to
; be, not less: the 514-byte SAVE_LOAD_TEMP_BUF that used to live right
; here between LOAD_DICT_LEN and LOAD_NAME_LEN has been relocated
; entirely (see that constant's own comment far below for why) — these
; small per-call scratch cells stay right where they always were,
; verified still clear of anything else in this gap (core/editor.asm's
; own EDIT_BUF starts at $8860, comfortably clear). ----
SAVE_NAME_PTR      EQU $8580   ; 2 bytes: SAVE-LIB's own scratch (filename chars ptr)
SAVE_NAME_LEN      EQU $8582   ; 1 byte:  SAVE-LIB's own scratch (filename length)
SAVE_DICT_LEN      EQU $8583   ; 2 bytes: SAVE-LIB's own scratch (HERE - FORTH_DICT_RAM)
SAVE_PAYLOAD_LEN   EQU $8585   ; 2 bytes: SAVE-LIB's own scratch (SAVE_DICT_LEN + 2)
LOAD_DICT_LEN      EQU $8587   ; 2 bytes: LOAD-LIB's own scratch (received length - 2)
LOAD_NAME_LEN      EQU $8589   ; 1 byte:  LOAD-LIB's own scratch (actual,
                               ; pre-padding filename length)
LOAD_NAME_BUF      EQU $858A   ; 10 bytes: LOAD-LIB's own scratch — a
                               ; space-padded, fixed-width copy of the
                               ; requested filename; see W_LOADLIB's own
                               ; header for why this exists — ends
                               ; $8594, still well inside the gap above

; ============================================================================
; THE OVERFLOW BUG (found and independently re-confirmed this session
; before being fixed — the original code really did have this hole,
; not just "in theory"): the ORIGINAL W_SAVE computed
; SAVE_DICT_LEN = HERE - FORTH_DICT_RAM and unconditionally LDIR'd that
; many bytes into a fixed 514-byte SAVE_LOAD_TEMP_BUF, with NO
; comparison against the old SAVE_LOAD_MAX_DICT (512) anywhere before
; that copy. Any user dictionary bigger than ~510 bytes — trivially
; easy in real use, and far below what this project's own dictionary
; ceiling (core/free.asm's DICT_RAM_CEILING) actually allows — silently
; overflowed the LDIR past SAVE_LOAD_TEMP_BUF into whatever RAM
; followed it (LOAD_NAME_LEN, LOAD_NAME_BUF, and beyond), corrupting
; adjacent state with no error reported at all.
;
; THE FIX: W_SAVELIB now compares SAVE_DICT_LEN against
; SAVE_LOAD_MAX_DICT BEFORE touching SAVE_LOAD_TEMP_BUF, LATEST, or the
; tape in any way, and THROWs -8 (ANS Forth's own real, standard
; "dictionary overflow" exception code — chosen because that's exactly
; what this condition is, not picked at random, matching the same
; standard-code discipline core/tick.asm's own -13 already established)
; if the dictionary doesn't fit. On overflow, execution never reaches
; the LATEST/LDIR/STORAGE_SAVE code at all — the save is refused
; cleanly, nothing is corrupted, and the tape is never touched.
;
; THE CEILING ITSELF — real RAM-budget research, not another round
; guess (the old 512 was explicitly documented as exactly that kind of
; placeholder; this replaces it with real arithmetic, not a bigger
; placeholder):
;   - core/free.asm's own audit established DICT_RAM_CEILING ($F000) as
;     the confirmed-safe top of RAM dictionary growth above
;     FORTH_DICT_RAM ($9800) — 22,528 bytes total.
;   - core/loadtext.asm's own LOADTEXT_BUF already reserves the TOP
;     8192 bytes of that exact range ($D000-$EFFF) for its own receive
;     buffer, leaving $9800-$CFFF (14,336 bytes) as the real remaining
;     budget for actual compiled dictionary growth — both numbers
;     straight from that file's own header, not re-derived here.
;   - Raising SAVE_LOAD_TEMP_BUF's ceiling enough to matter needs real
;     space carved from that SAME large region. Reserving ANOTHER
;     separate multi-KB chunk on top of LOADTEXT_BUF's own reservation
;     would eat further into the 14,336-byte dictionary-growth budget
;     for no good reason, given that SAVE-LIB/LOAD-LIB and LOAD-TEXT
;     can never be in use at the same instant — this is a
;     single-threaded interpreter (one word runs to completion before
;     the next starts), and neither of these words calls the other.
;     So SAVE_LOAD_TEMP_BUF TIME-SHARES the exact same physical bytes
;     LOADTEXT_BUF already owns ($D000-$EFFF) instead of claiming any
;     new RAM of its own — zero additional cost to the
;     dictionary-growth budget, which stays exactly 14,336 bytes
;     ($9800-$CFFF) either way, with or without this file's own words.
;
; WHY THE ADDRESS BELOW IS A LITERAL, NOT A REFERENCE TO LOADTEXT_BUF:
; this file must still assemble completely standalone —
; rom/forth_smoke_p7.asm includes ONLY core/dict.asm, core/interp.asm,
; kernel/storage, core/throwcatch.asm, and this file, never
; core/free.asm or core/loadtext.asm — so SAVE_LOAD_TEMP_BUF can't be
; written as an expression depending on DICT_RAM_CEILING or
; LOADTEXT_BUF, both simply undefined symbols in that build (the same
; reason rom/forth_smoke_p52.asm's own header gives for locally
; re-declaring DICT_RAM_CEILING EQU $F000 rather than pulling in the
; whole of core/free.asm). $D000 below is today's real LOADTEXT_BUF
; value ($F000 - 8192) written out as a literal instead, with an
; explicit ASSERT in rom/forth_boot.asm itself (placed after BOTH this
; file's and core/loadtext.asm's own INCLUDEs, where both symbols
; genuinely exist together) catching the two values ever silently
; drifting apart — check that ASSERT hasn't fired before trusting this
; literal again after any future change to DICT_RAM_CEILING or
; LOADTEXT_MAX_LEN.
;
; HONEST LIMIT this creates (same spirit as LOADTEXT_BUF's own honest-
; limit paragraph, not silently glossed over): the dictionary can still
; genuinely grow up to 14,336 bytes ($9800-$CFFF) before running out of
; room outright (FREE still reports against the real $F000 ceiling,
; completely unchanged by this file) — but SAVE-LIB can only actually
; persist up to SAVE_LOAD_MAX_DICT (8190) bytes of it in one piece. A
; dictionary that's grown bigger than 8190 bytes but smaller than
; FREE's own ceiling can no longer be SAVE-LIB'd whole; it now THROWs
; -8 instead of silently corrupting memory, which is the actual
; improvement this phase makes, but it is still a real, stated
; boundary, not a claim of unlimited saving. 8190 is a >16x
; improvement over the old 512-byte ceiling and comfortably larger than
; any real definition set this project has ever tested against.
; ============================================================================
SAVE_LOAD_TEMP_BUF EQU $D000   ; 8192 bytes: 2 (LATEST) + up to
                               ; SAVE_LOAD_MAX_DICT bytes of dictionary
                               ; content — see the block comment above
                               ; for the full sizing/placement reasoning
                               ; and rom/forth_boot.asm's own ASSERT
                               ; that cross-checks this literal
SAVE_LOAD_MAX_DICT EQU 8192 - 2   ; = 8190; see the block comment above
                               ; for the real research behind this
                               ; number — not a round guess, and not
                               ; the same kind of placeholder 512 was

; ============================================================================
; SAVE-LIB ( "name" -- )
; Parses the next word as a filename, builds the LATEST-prefixed
; payload described in this file's header, and calls STORAGE_SAVE —
; but only after confirming the current dictionary actually fits (see
; THE OVERFLOW BUG/THE FIX above); THROWs -8 and touches nothing else
; if it doesn't.
; ============================================================================
H_SAVELIB:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL) to
                            ; whatever word chain this file should
                            ; extend, immediately before INCLUDEing
                            ; this file — see core/control.asm's own
                            ; header for the full reasoning
    DB   8, "S", "A", "V", "E", "-", "L", "I", "B"
W_SAVELIB:
    call W_WORD
    call DPOP_HL
    ld   a, (hl)
    ld   (SAVE_NAME_LEN), a
    inc  hl
    ld   (SAVE_NAME_PTR), hl

    ld   hl, (HERE)
    ld   de, FORTH_DICT_RAM
    or   a
    sbc  hl, de
    ld   (SAVE_DICT_LEN), hl

    ; ---- overflow guard: refuse cleanly, don't touch anything else,
    ; if the current dictionary doesn't fit SAVE_LOAD_TEMP_BUF ----
    ld   de, SAVE_LOAD_MAX_DICT
    or   a
    sbc  hl, de              ; hl = SAVE_DICT_LEN - SAVE_LOAD_MAX_DICT;
                              ; carry set means SAVE_DICT_LEN was
                              ; smaller (fits), Z set means exactly
                              ; equal (also fits) — an unsigned 16-bit
                              ; compare, same idiom core/free.asm's own
                              ; FREE word already uses
    jr   z, .size_ok
    jr   c, .size_ok
    ld   hl, -8               ; ANS Forth's own real "dictionary
                              ; overflow" exception code
    call DPUSH_HL
    call W_THROW
    ret                       ; unreachable if uncaught (THROW jumps
                              ; away); reached only if some active
                              ; CATCH unwinds past this call anyway —
                              ; either way, SAVE_LOAD_TEMP_BUF, LATEST,
                              ; HERE, and the tape are all still
                              ; completely untouched at this point
.size_ok:

    ld   hl, (LATEST)
    ld   (SAVE_LOAD_TEMP_BUF), hl

    ld   bc, (SAVE_DICT_LEN)
    ld   a, b
    or   c
    jr   z, .no_dict_copy
    ld   hl, FORTH_DICT_RAM
    ld   de, SAVE_LOAD_TEMP_BUF + 2
    ldir
.no_dict_copy:

    ld   hl, (SAVE_DICT_LEN)
    ld   de, 2
    add  hl, de
    ld   (SAVE_PAYLOAD_LEN), hl

    xor  a
    ld   (STORAGE_REQUEST_TYPE), a
    ld   hl, (SAVE_NAME_PTR)
    ld   a, (SAVE_NAME_LEN)
    ld   b, a
    push ix                    ; IX is 2068-Forth's OWN data stack
                                ; pointer, not this call's business --
                                ; STORAGE_SEND_BLOCK's own header says
                                ; plainly it destroys IX (it uses IX as
                                ; ITS data pointer, walking/incrementing
                                ; it), so the real caller's IX must be
                                ; saved here and restored below, or the
                                ; data stack is left pointing into
                                ; SAVE_LOAD_TEMP_BUF after this returns
    ld   ix, SAVE_LOAD_TEMP_BUF
    ld   de, (SAVE_PAYLOAD_LEN)
    call STORAGE_SAVE
    pop  ix
    ret

; ============================================================================
; LOAD-LIB ( "name" -- )
; Parses the next word as a filename (an empty word — end of input —
; naturally becomes a wildcard load, since W_WORD's empty result and
; STORAGE_LOAD's own "B=0 means wildcard" convention line up exactly).
; On success, restores LATEST from the received payload's first 2
; bytes and copies the rest back to FORTH_DICT_RAM. On failure, leaves
; the current dictionary completely untouched — no partial state, no
; error reporting yet (matching every earlier phase's "no error
; recovery yet" scope note). No separate overflow guard is needed here
; beyond what already existed: STORAGE_LOAD's own documented contract
; (include/kernel_api.inc) already refuses (carry set) if the tape
; header's claimed length exceeds the caller's own DE bound, and this
; routine already passes SAVE_LOAD_MAX_DICT + 2 as that bound — raising
; SAVE_LOAD_MAX_DICT above automatically raised this guard too, no code
; change required.
; ============================================================================
H_LOADLIB:
    DW   H_SAVELIB
    DB   8, "L", "O", "A", "D", "-", "L", "I", "B"
W_LOADLIB:
    ; STORAGE_LOAD's own filename match always compares a FIXED
    ; STORAGE_HEADER_FILENAME_LEN-byte (10) span, space-padded on the
    ; saved side (STORAGE_SAVE does that padding itself) -- it does NOT
    ; use the caller's B as a comparison length, only as a 0-means-
    ; wildcard flag. Passing WORD_BUF's raw, unpadded tail directly (an
    ; earlier version of this routine did exactly that) reads past the
    ; real filename into whatever garbage happens to follow it in
    ; WORD_BUF, which almost never matches the saved header's own
    ; space-padded name -- found by a real Fuse run reporting "unknown
    ; word" for a name that WAS actually on the (fake) tape, traced to
    ; STORAGE_LOAD reporting failure via a temporary debug flag, not
    ; guessed from reading the code alone. LOAD_NAME_BUF below is built
    ; space-padded to exactly 10 bytes before every call, matching what
    ; STORAGE_SAVE itself produces.
    call W_WORD
    call DPOP_HL
    ld   a, (hl)
    cp   STORAGE_HEADER_FILENAME_LEN + 1
    jr   c, .len_ok
    ld   a, STORAGE_HEADER_FILENAME_LEN    ; truncate an over-length
                                            ; filename rather than let
                                            ; the pad-length math below
                                            ; underflow
.len_ok:
    ld   (LOAD_NAME_LEN), a
    inc  hl                     ; hl -> filename chars

    ld   de, LOAD_NAME_BUF
    ld   a, (LOAD_NAME_LEN)
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
    ld   a, (LOAD_NAME_LEN)
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
    push ix                    ; save 2068-Forth's own data stack
                                ; pointer -- see W_SAVELIB's identical
                                ; comment above on why this is required,
                                ; not optional
    ld   hl, LOAD_NAME_BUF
    ld   a, (LOAD_NAME_LEN)
    ld   b, a
    ld   ix, SAVE_LOAD_TEMP_BUF
    ld   de, SAVE_LOAD_MAX_DICT + 2
    call STORAGE_LOAD
    pop  ix
    jr   c, .fail

    push de                    ; de = actual payload length received
    ld   hl, (SAVE_LOAD_TEMP_BUF)
    ld   (LATEST), hl
    pop  hl                    ; hl = payload length again
    ld   de, 2
    or   a
    sbc  hl, de                ; hl = dictionary length
    ld   (LOAD_DICT_LEN), hl

    ld   bc, (LOAD_DICT_LEN)
    ld   a, b
    or   c
    jr   z, .no_dict_copy
    ld   hl, SAVE_LOAD_TEMP_BUF + 2
    ld   de, FORTH_DICT_RAM
    ldir
.no_dict_copy:
    ld   hl, FORTH_DICT_RAM
    ld   de, (LOAD_DICT_LEN)
    add  hl, de
    ld   (HERE), hl
    ret
.fail:
    ret

DICT_LATEST_INIT_P7 EQU H_LOADLIB   ; head of the dictionary as of Phase 7

    ENDIF
