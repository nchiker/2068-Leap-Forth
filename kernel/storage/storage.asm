; ============================================================================
; kernel/storage/storage.asm -- tape SAVE/LOAD: header logic over the block I/O
;
; STORAGE_SEND_BLOCK / STORAGE_RECEIVE_BLOCK are Leap-C's clean-room tape block I/O
; (kernel/storage/tapeblock.asm, adopted unchanged; docs/V2/STORAGE_SPEC.md D1 and section 3
; for the contract). This file holds the header logic above it: STORAGE_SAVE (a 17-byte header
; block, then the data block) and STORAGE_LOAD (header search, then the data block). The wire
; format is the standard one, so tapes made by the stock ROM's routines still load.
;
; Test hooks: a ROM that DEFINEs STORAGE_TEST_FAKE_SEND / STORAGE_TEST_FAKE_RECEIVE supplies
; STORAGE_TEST_SEND_BLOCK / STORAGE_TEST_RECEIVE_BLOCK with the same contract (an in-RAM tape,
; rom/forth_smoke_p7.asm, p52).
; ============================================================================

STORAGE_TYPE_HEADER EQU $00   ; SA-BYTES/LD-BYTES type-flag byte — this
                               ; is the value LD-LOOK-H's own real code
                               ; uses ("XOR A" before calling LD-BYTES
                               ; to search for a header); the book's own
                               ; prose describing SA-BYTES has this
                               ; backwards from its own actual code.
STORAGE_TYPE_DATA   EQU $FF

STORAGE_HEADER_TYPE_OFF      EQU 0
STORAGE_HEADER_NAME_OFF      EQU 1
STORAGE_HEADER_LENGTH_OFF    EQU 11
STORAGE_HEADER_AUTOSTART_OFF EQU 13
STORAGE_HEADER_PROGLEN_OFF   EQU 15
STORAGE_HEADER_PAYLOAD_LEN   EQU 17
STORAGE_LOAD_DATA_TOUCHED    EQU $FF     ; failure return marker: at least
                                         ; one destination byte was written
STORAGE_NO_AUTOSTART         EQU $8000

    ASSERT STORAGE_HEADER_NAME_OFF + STORAGE_HEADER_FILENAME_LEN = STORAGE_HEADER_LENGTH_OFF
    ASSERT STORAGE_HEADER_PROGLEN_OFF + 2 = STORAGE_HEADER_PAYLOAD_LEN

STORAGE_NZ_SENTINEL EQU $02   ; NOT a real type flag — see every "cp
                               ; STORAGE_NZ_SENTINEL" call site in
                               ; STORAGE_LOAD below. STORAGE_RECEIVE_
                               ; BLOCK's own .loop (".flag" branch)
                               ; tests the CALLER's Z flag at the
                               ; moment of the call (restored via its
                               ; own first "ex af,af'") to decide
                               ; whether to validate the just-received
                               ; type-flag byte. Z must be CLEAR (NZ)
                               ; at the call site for validation to
                               ; fire correctly; neither "ld a,type" nor
                               ; "scf" touch Z at all, so this sentinel
                               ; forces it explicitly without disturbing
                               ; A (it can never equal either real type
                               ; flag, $00 or $FF).

STORAGE_HEADER_ATTEMPTS_MAX EQU 15  ; STORAGE_LOAD's own .header_search
                               ; retry cap. STORAGE_ENTRY_RETRY_MAX
                               ; below is what actually provides real-
                               ; world dead-air tolerance for a single
                               ; attempt (a genuine signal can take
                               ; several real seconds to start); this
                               ; outer count only needs to cover a
                               ; handful of complete-but-wrong attempts
                               ; (found something, but wrong name/too
                               ; long/SPACE), not waiting through
                               ; silence. Worst case if every attempt
                               ; somehow burned its full inner budget:
    IFDEF STORAGE_TEST_FAKE_RECEIVE
STORAGE_RECEIVE_BLOCK EQU STORAGE_TEST_RECEIVE_BLOCK
    ELSE
STORAGE_RECEIVE_BLOCK EQU TAPE_RECV_BLOCK
    ENDIF
STORAGE_SEND_BLOCK EQU TAPE_SEND_BLOCK
    INCLUDE "kernel/storage/tapeblock.asm"


; ============================================================================
; STORAGE_SAVE
; In:  HL = filename pointer, B = filename length, IX = data pointer,
;      DE = data length
; Out: carry always clear (this project's own caller ignores it anyway
;      — see rom/exrom_storage.asm's own header)
; Destroys: AF, BC, DE, HL, IX
; ============================================================================
STORAGE_SAVE:
    di
    ld   a, b
    cp   STORAGE_HEADER_FILENAME_LEN + 1
    jr   c, .name_len_ok
    ld   b, STORAGE_HEADER_FILENAME_LEN   ; transport field is fixed-width
.name_len_ok:
    push ix
    push de
    ld   (STORAGE_SEND_LEN), de           ; stash the caller's own data
                                         ; ptr/length before HL/BC get
                                         ; reused building the header —
                                         ; STORAGE_SEND_LEN is scratch
                                         ; here (not the running-
                                         ; countdown role it had in the
                                         ; archived design; renamed
                                         ; comment, same sysvar slot)

    ld   a, (STORAGE_REQUEST_TYPE)
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_TYPE_OFF), a
    ld   de, STORAGE_HEADER_BUF + STORAGE_HEADER_NAME_OFF
    ld   a, b
    or   a
    jr   z, .name_done                    ; zero-length name — leave
                                         ; the buffer's own default
                                         ; padding as-is (BASIC_DO_SAVE
                                         ; always supplies a real name
                                         ; today, kept defensive)
    push bc
    ld   b, a
.name_copy:
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    djnz .name_copy
    pop  bc
.name_done:
    ld   a, STORAGE_HEADER_FILENAME_LEN
    sub  b
    jr   z, .len_set
    ld   b, a
    ld   a, ' '
.pad:
    ld   (de), a
    inc  de
    djnz .pad
.len_set:
    ld   hl, (STORAGE_SEND_LEN)
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF), hl
    ld   a, (STORAGE_REQUEST_TYPE)
    cp   STORAGE_EXTENSION_TYPE
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_AUTOSTART_OFF)
    jr   nz, .autostart_ready
    ld   de, EXT_SERVICE_ABI_VERSION
.autostart_ready:
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_AUTOSTART_OFF), de
    ; The stock BASIC header's second parameter is the program portion
    ; length. This ROM serializes program text only (never variables),
    ; so it is identical to the data length.
    ld   (STORAGE_HEADER_BUF + STORAGE_HEADER_PROGLEN_OFF), hl

    xor  a
    ld   (STORAGE_PROGRESS_PCT), a
    ld   a, 1
    ld   (STORAGE_OP_STATE), a            ; SAVING
    call STORAGE_REPORT_PROGRESS

    ld   a, STORAGE_TYPE_HEADER
    ld   ix, STORAGE_HEADER_BUF
    ld   de, STORAGE_HEADER_PAYLOAD_LEN
    IFDEF STORAGE_TEST_FAKE_SEND
    call STORAGE_TEST_SEND_BLOCK
    ELSE
    call STORAGE_SEND_BLOCK
    ENDIF

    ld   a, 10
    ld   (STORAGE_PROGRESS_PCT), a
    call STORAGE_REPORT_PROGRESS          ; safe inter-block update;
                                         ; never draw inside a tape block

    pop  de                               ; caller's real data length
    pop  ix                               ; caller's real data pointer
    ld   a, STORAGE_TYPE_DATA
    IFDEF STORAGE_TEST_FAKE_SEND
    call STORAGE_TEST_SEND_BLOCK
    ELSE
    call STORAGE_SEND_BLOCK               ; stock format: one data block
    ENDIF

    ld   a, 2
    ld   (STORAGE_OP_STATE), a            ; SAVED
    ld   a, 100
    ld   (STORAGE_PROGRESS_PCT), a
    call STORAGE_REPORT_PROGRESS          ; BASIC_DRAW_STATUS_LINE is
                                         ; only ever reached through
                                         ; this hook, not the normal
                                         ; editor redraw cycle, so
                                         ; without this call SAVED would
                                         ; never actually reach the
                                         ; screen
    or   a
    ei                                     ; re-enable interrupts before
                                         ; returning -- STORAGE_SAVE's own
                                         ; entry `di` above must not
                                         ; outlive this call, or the
                                         ; keyboard ISR (KBD_ISR_TICK)
                                         ; never fires again and
                                         ; IO_READ_KEY's blocking wait
                                         ; hangs the live editor forever
    ret

; ============================================================================
; STORAGE_LOAD
; In:  IX = destination pointer, HL = filename pointer, B = filename
;      length (0 = wildcard, LOAD ""), DE = max allowed data length
; Out: DE = actual data length received (only meaningful if carry
;          clear), A = 0 on success or a clean failure,
;          STORAGE_LOAD_DATA_TOUCHED on failure after destination writes
;      Carry set = total failure (no matching header, or header's own
;          claimed length exceeds the caller's bound, or the data block
;          failed). A distinguishes whether destination bytes were written.
; Destroys: AF, BC, DE, HL, IX
; ============================================================================
STORAGE_LOAD:
    di
    ld   (STORAGE_MAX_LEN), de
    push hl                               ; caller's filename pointer
    push bc                               ; caller's filename length
    push ix                               ; caller's real destination
                                         ; pointer — IX gets reused for
                                         ; STORAGE_HEADER_BUF below

    xor  a
    ld   (STORAGE_PROGRESS_PCT), a
    ld   a, 3
    ld   (STORAGE_OP_STATE), a            ; LOADING
    call STORAGE_REPORT_PROGRESS

    ld   b, STORAGE_HEADER_ATTEMPTS_MAX
.header_search:
    push bc                               ; B = attempts remaining —
                                         ; STORAGE_RECEIVE_BLOCK
                                         ; destroys BC, so this must be
                                         ; saved/restored around each
                                         ; attempt, same pattern as the
                                         ; entry-pushed HL/BC/IX below
    ld   a, STORAGE_TYPE_HEADER
    cp   STORAGE_NZ_SENTINEL              ; force Z clear — see that
                                         ; constant's own header
    scf
    ld   ix, STORAGE_HEADER_BUF
    ld   de, STORAGE_HEADER_PAYLOAD_LEN       ; the receive loop
                                         ; naturally reads and
                                         ; checksums the trailing
                                         ; checksum byte too, on top of
                                         ; this real length — no +1
                                         ; needed here (verified via
                                         ; z80sim, see STORAGE_HEADER_
                                         ; BUF's own header)
    call STORAGE_RECEIVE_BLOCK
    pop  bc
    jr   nc, .header_found
    djnz .header_search
    ; exhausted every attempt — give up cleanly instead of retrying
    ; forever. Rebalance the entry-pushed IX/BC/HL (never consumed on
    ; this path) before falling into .total_failure.
    pop  ix
    pop  bc
    pop  hl
    jp   .total_failure                   ; JP not JR — out of JR's
                                         ; +-127 range from here

.header_found:
    ; Keep the outer header-search budget before restoring the caller's
    ; registers.  A nonmatching header is not a LOAD failure: it may be
    ; an earlier file on a multi-file (or appended) tape, so .name_mismatch
    ; must be able to resume .header_search with this same remaining count.
    ; STORAGE_CHECKSUM is otherwise unused by the current real-ROM-derived
    ; protocol (its running XOR lives in H), making it safe scratch here.
    ld   a, b
    ld   (STORAGE_CHECKSUM), a
    ld   a, (STORAGE_HEADER_BUF + STORAGE_HEADER_TYPE_OFF)
    ld   c, a
    ld   a, (STORAGE_REQUEST_TYPE)
    cp   c
    jr   nz, .header_rejected
    pop  ix                               ; caller's real destination
                                         ; pointer, restored
    pop  bc                               ; caller's filename length
    pop  hl                               ; caller's filename pointer
    ld   a, b
    or   a
    jr   z, .name_ok                      ; wildcard — LOAD ""
    ; Preserve the original inputs while the fixed-width comparison
    ; consumes HL/B.  They are needed if this is a different file and
    ; the search continues at the following header.
    push bc
    push hl
    push ix
    ld   de, STORAGE_HEADER_BUF + STORAGE_HEADER_NAME_OFF
    ld   b, STORAGE_HEADER_FILENAME_LEN
.name_cmp:
    ld   a, (de)
    cp   (hl)
    jr   nz, .name_mismatch
    inc  hl
    inc  de
    djnz .name_cmp
    pop  ix
    pop  hl
    pop  bc
    jr   .name_ok
.name_mismatch:
    pop  ix
    pop  hl
    pop  bc
    push hl                               ; restore STORAGE_LOAD's
    push bc                               ; entry stack shape so a later
    push ix                               ; matching header gets its
                                         ; original destination/name
    ld   a, (STORAGE_CHECKSUM)
    ld   b, a
    djnz .header_search
    pop  ix
    pop  bc
    pop  hl
    jr   .total_failure

.header_rejected:
    ; A valid standard header for another file type is not corruption;
    ; continue looking for a BASIC-program header on the tape.
    pop  ix
    pop  bc
    pop  hl
    push hl
    push bc
    push ix
    ld   a, (STORAGE_CHECKSUM)
    ld   b, a
    djnz .header_search
    pop  ix
    pop  bc
    pop  hl
    jr   .total_failure

.name_ok:
    ld   hl, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   de, (STORAGE_MAX_LEN)
    or   a
    sbc  hl, de
    jr   c, .length_ok                    ; header length < max — fine
    ld   a, h
    or   l
    jr   z, .length_ok                    ; header length == max — fine
    jp   .total_failure                   ; JP not JR — out of range;
                                         ; header length > max

.length_ok:
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   a, 10
    ld   (STORAGE_PROGRESS_PCT), a
    ld   a, 7
    ld   (STORAGE_OP_STATE), a            ; PROGRAM: <name> — matching
                                         ; header confirmed, about to
                                         ; receive the data block. Real
                                         ; ROM's own LOAD shows the
                                         ; found program's name at
                                         ; exactly this point, not just
                                         ; at final completion.
    call STORAGE_REPORT_PROGRESS
    push ix
    push de
    ld   a, STORAGE_TYPE_DATA
    cp   STORAGE_NZ_SENTINEL              ; force Z clear — see that
                                         ; constant's own header
    scf
    call STORAGE_RECEIVE_BLOCK
    jr   c, .data_failed
.data_ok:
    pop  de                               ; discard the saved retry
                                         ; state — reload the real
                                         ; length below instead, since
                                         ; STORAGE_RECEIVE_BLOCK's own
                                         ; DE counts DOWN to 0 on
                                         ; success, not what our own
                                         ; caller needs
    pop  ix
    ld   de, (STORAGE_HEADER_BUF + STORAGE_HEADER_LENGTH_OFF)
    ld   a, 4
    ld   (STORAGE_OP_STATE), a            ; LOADED
    ld   a, 100
    ld   (STORAGE_PROGRESS_PCT), a
.success_done:
    call STORAGE_REPORT_PROGRESS          ; without this, LOADED would never
                                         ; actually reach the screen —
                                         ; see STORAGE_SAVE's own
                                         ; matching comment for why
    xor  a
    ei                                     ; re-enable interrupts before
                                         ; returning -- see STORAGE_SAVE's
                                         ; own matching comment for why;
                                         ; `ei` touches no flags/registers,
                                         ; so A and the carry flag set
                                         ; just above survive intact
    ret

.data_failed:
    ; DE is the receiver's remaining byte count; the stack holds the
    ; original length. If they differ, part (or all) of the destination
    ; has already been overwritten and the caller must not retain the old
    ; program as though it were still trustworthy.
    pop  hl
    pop  ix
    ld   a, d
    cp   h
    jr   nz, .data_touched
    ld   a, e
    cp   l
    jr   nz, .data_touched
.total_failure:
    xor  a                               ; clean failure: no program bytes
                                         ; were written
    jr   .report_failure
.data_touched:
    ld   a, STORAGE_LOAD_DATA_TOUCHED
.report_failure:
    push af                              ; preserve clean/dirty result marker
    ld   a, 6
    ld   (STORAGE_OP_STATE), a            ; LOAD FAILED
    call STORAGE_REPORT_PROGRESS          ; without this, LOAD FAILED
                                         ; would never actually reach
                                         ; the screen — see STORAGE_
                                         ; SAVE's own matching comment
                                         ; for why
    pop  af
    scf
    ei                                     ; re-enable interrupts on the
                                         ; failure path too -- a failed
                                         ; LOAD must not leave the
                                         ; keyboard ISR permanently
                                         ; masked any more than a
                                         ; successful one; `ei` touches
                                         ; no flags/registers, so A and
                                         ; the carry flag set just above
                                         ; survive intact
    ret

; ============================================================================
; STORAGE_REPORT_PROGRESS
; Calls STORAGE_PROGRESS_HOOK if one is set, so BASIC can redraw its
; own status bar to reflect the current STORAGE_OP_STATE live, mid-
; operation. This ROM has no interrupts during SAVE/LOAD (see this
; file's own top header), so there is no other way for a live status
; update to reach the screen during a block transfer.
; In:  none
; Out: none
; Destroys: nothing the hook itself doesn't (the hook's own contract is
;      "no input, no output" — callers of THIS routine should still
;      preserve their own live registers across it defensively, same
;      as the archived design's own convention)
; ============================================================================
STORAGE_REPORT_PROGRESS:
    push af
    push bc
    push de
    push hl
    push ix
    ld   hl, (STORAGE_PROGRESS_HOOK)
    ld   a, h
    or   l
    jr   z, .none
    call .call_hl
.none:
    pop  ix
    pop  hl
    pop  de
    pop  bc
    pop  af
    ret
.call_hl:
    jp   (hl)
