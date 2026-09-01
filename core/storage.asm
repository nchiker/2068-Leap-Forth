; ============================================================================
; core/storage.asm — Phase 7: storage (SAVE, LOAD)
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — chains its own dictionary entries onto core/interp.asm's
; H_SEMICOLON) and needs kernel/storage/storage.asm INCLUDEd alongside
; it. Deliberately does NOT need core/control.asm or core/ts2068.asm —
; SAVE/LOAD are independent of control flow and graphics, matching
; every earlier phase's practice of only depending on what's actually
; needed.
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
; THE PROBLEM THAT DESIGN CONSTRAINT CREATES: SAVE needs to persist not
; just the compiled dictionary bytes ($FORTH_DICT_RAM through $HERE)
; but also LATEST (the head of the dictionary chain), since LATEST
; isn't recoverable purely from a byte count — dictionary headers are
; singly-linked BACKWARD (LINK points at the previous entry), so
; there's no way to walk forward from FORTH_DICT_RAM to find "the last
; header" without already knowing where it is.
;
; THE FIX: since STORAGE_SAVE/STORAGE_LOAD only care about a raw
; pointer and length — they transport whatever bytes they're given
; completely opaquely — this file builds its OWN small contiguous
; payload in a scratch buffer: 2 bytes for LATEST, followed by a copy
; of the actual dictionary bytes. That's a decision entirely within
; this file's own data format, invisible to and unconstrained by the
; tape wire protocol itself. LOAD reverses it: receive into the same
; scratch layout, restore LATEST from the first 2 bytes, copy the rest
; back to FORTH_DICT_RAM, and set HERE from the received length.
;
; TESTING: this file is verified against kernel/storage's own
; STORAGE_TEST_FAKE_SEND/STORAGE_TEST_FAKE_RECEIVE hooks (conditional
; compilation switches already present in kernel/storage/storage.asm,
; unused until this phase) rather than a real Fuse tape round-trip.
; rom/forth_smoke_p7.asm supplies the fake STORAGE_TEST_SEND_BLOCK/
; STORAGE_TEST_RECEIVE_BLOCK implementations those hooks call instead
; of the real tape-pulse routines. This proves this file's OWN wiring
; (filename handling, the LATEST-prefixed payload format, HERE/LATEST
; restoration) — it does NOT prove the real tape wire format actually
; round-trips in a real emulator, which is the exact risk the design
; constraint above exists to manage. That remains open, real, follow-up
; work, not silently treated as covered — see docs/PROJECT_PLAN.md's
; Phase 7 section.
; ============================================================================

    IFNDEF CORE_STORAGE_ASM
    DEFINE CORE_STORAGE_ASM

; ---- Phase 7 RAM state — same probe-verified $8426-$8FFF gap Phase 5
; and 6 already established as safe (docs/PROJECT_PLAN.md's Phase 5
; section), placed after core/editor.asm's own cells (ending at $8574)
; with a small margin. ----
SAVE_NAME_PTR      EQU $8580   ; 2 bytes: SAVE's own scratch (filename chars ptr)
SAVE_NAME_LEN      EQU $8582   ; 1 byte:  SAVE's own scratch (filename length)
SAVE_DICT_LEN      EQU $8583   ; 2 bytes: SAVE's own scratch (HERE - FORTH_DICT_RAM)
SAVE_PAYLOAD_LEN   EQU $8585   ; 2 bytes: SAVE's own scratch (SAVE_DICT_LEN + 2)
LOAD_DICT_LEN      EQU $8587   ; 2 bytes: LOAD's own scratch (received length - 2)
SAVE_LOAD_TEMP_BUF EQU $8589   ; 514 bytes: 2 (LATEST) + up to
                               ; SAVE_LOAD_MAX_DICT bytes of dictionary
                               ; content — see this file's own header
                               ; for why this exists instead of saving
                               ; FORTH_DICT_RAM directly
LOAD_NAME_LEN      EQU $878B   ; 1 byte:  LOAD's own scratch (actual,
                               ; pre-padding filename length)
LOAD_NAME_BUF      EQU $878C   ; 10 bytes: LOAD's own scratch — a
                               ; space-padded, fixed-width copy of the
                               ; requested filename; see W_LOAD's own
                               ; header for why this exists

SAVE_LOAD_MAX_DICT EQU 512     ; provisional ceiling, same caveat as
                               ; every other address/size constant in
                               ; this project pending the Phase 0
                               ; memory-map audit — plenty for the
                               ; small test definitions this phase
                               ; proves itself against, not a
                               ; considered real limit

; ============================================================================
; SAVE ( "name" -- )
; Parses the next word as a filename, builds the LATEST-prefixed
; payload described in this file's header, and calls STORAGE_SAVE.
; ============================================================================
H_SAVE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL) to
                            ; whatever word chain this file should
                            ; extend, immediately before INCLUDEing
                            ; this file — see core/control.asm's own
                            ; header for the full reasoning
    DB   4, "S", "A", "V", "E"
W_SAVE:
    call W_WORD
    call DPOP_HL
    ld   a, (hl)
    ld   (SAVE_NAME_LEN), a
    inc  hl
    ld   (SAVE_NAME_PTR), hl

    ld   hl, (LATEST)
    ld   (SAVE_LOAD_TEMP_BUF), hl

    ld   hl, (HERE)
    ld   de, FORTH_DICT_RAM
    or   a
    sbc  hl, de
    ld   (SAVE_DICT_LEN), hl

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
; LOAD ( "name" -- )
; Parses the next word as a filename (an empty word — end of input —
; naturally becomes a wildcard load, since W_WORD's empty result and
; STORAGE_LOAD's own "B=0 means wildcard" convention line up exactly).
; On success, restores LATEST from the received payload's first 2
; bytes and copies the rest back to FORTH_DICT_RAM. On failure, leaves
; the current dictionary completely untouched — no partial state, no
; error reporting yet (matching every earlier phase's "no error
; recovery yet" scope note).
; ============================================================================
H_LOAD:
    DW   H_SAVE
    DB   4, "L", "O", "A", "D"
W_LOAD:
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
                                ; pointer -- see W_SAVE's identical
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

DICT_LATEST_INIT_P7 EQU H_LOAD   ; head of the dictionary as of Phase 7

    ENDIF
