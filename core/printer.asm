; ============================================================================
; core/printer.asm — Phase 47: LPRINT, LLIST
;
; Builds on core/dict.asm (DPOP_HL, LATEST, FORTH_DICT_RAM) and needs
; kernel/graphics/graphics.asm's GFX_CHAR_TO_FONT_OFFSET already
; INCLUDEd (true in every existing ROM — that file is included for
; GFX_CLS/GFX_PUTCHAR long before this one would be).
;
; VERIFICATION STATUS (2026-09-03, settled): the full 8-row protocol fix
; below (per-row setup write + start-of-paper gate, found via the real
; verbatim ROM disassembly at ~/Downloads/Timex Sinclair 2068 ROM
; Disassembly.pdf) was confirmed via a real Fuse retest — a full, correct
; 256x8 .pbm now comes out every time.
;
; Two SEPARATE issues were found investigating why the printed pixel
; content still looked wrong and why the companion .txt file was empty:
;
; 1. PIXEL-LEVEL GEOMETRY CORRUPTION IN THE .pbm, early rows of every
;    character: root-caused (Codex review, this session) to a genuine
;    Fuse printer-emulation bug in ~/fuse-build/peripherals/printer.c —
;    it models the print head's X position as continuous real-T-state-
;    derived state that only resets to a fresh 256-dot line when the
;    motor fully stops (zxpspeed returns to 0), but neither this file's
;    PRINT_RASTER_ROW nor the real ROM's own COPY-BUFF/COPY-LINE stop the
;    motor between the 8 rows of one character line (only once, at the
;    very end) — so Fuse's internal line position silently drifts across
;    all 8 per-row calls instead of resetting each time. Confirmed NOT a
;    bug in this file: (a) our OUT-byte bit-merge math was checked
;    byte-for-byte identical to the real ROM's own RL D/RL E/RR D trick
;    via Python simulation; (b) a throwaway diagnostic ROM proved
;    PRINT_LINE_BUF's RAM content is rendered correctly before any port
;    I/O; (c) the real, UNMODIFIED 48K Spectrum ROM's own LPRINT, run
;    through the identical Fuse setup, garbles the same way. Per the
;    user (2026-09-03): not a priority — present with the stock ROM too,
;    not something to chase further here.
;
; 2. THE COMPANION .txt FILE CAME OUT EMPTY (just a blank line). Root
;    cause: Fuse's text-OCR (printer.c's printer_zxp_output_as_text)
;    doesn't use any built-in reference font — it reads the CURRENTLY
;    RUNNING MACHINE'S OWN real ZX system variable CHARS ($5C36/$5C37) to
;    find a font table, then byte-compares printed dots against THAT.
;    This project never set CHARS (it isn't used anywhere in this
;    project's own code — see hardware.inc's ZX_SYSVAR_CHARS), so Fuse's
;    OCR was comparing our printed dots against garbage/ROM bytes and
;    never matched a single character. Fixed: LPRINT_SEND_LINE now sets
;    CHARS = FONT_TABLE-256 (the real convention) before every printed
;    line — confirmed via a real Fuse retest: the OCR now finds exact
;    byte matches instead of nothing.
;
;    BUT the resulting .txt still shows the WRONG characters (e.g.
;    LPRINT of "HI" produces "23" in the file) — this is NOT the pixel
;    geometry issue from #1 above, and NOT still-broken; it's a separate,
;    fully understood, deterministic mismatch: Fuse's OCR assumes a
;    DENSE, ASCII-code-ordered font table (entry N = code 32+N, no
;    gaps), but this project's own FONT_TABLE is packed in DEFINITION
;    order to save ROM (space, then '0'-'9', then 'A'-'Z', then 'a'-'z',
;    then 23 punctuation characters via a separate scan table,
;    PUNCT_CHAR_TABLE) — 'H' is FONT_TABLE's entry #18, 'I' is entry #19,
;    so Fuse's dense-indexed OCR reports code 18+32=50='2' and
;    19+32=51='3' instead. Deliberately NOT fixed: the real printer
;    output is the .pbm graphics file (confirmed correct — see #1), not
;    this OCR convenience, which has no counterpart on real hardware at
;    all (a real ZX Printer only ever produces dots on paper, never
;    text); a proper fix needs a dense 96-entry ASCII-indexed table
;    (~768 bytes of this project's historically tight ROM budget) purely
;    to make an emulator's debug convenience show the right label. Per
;    the user (2026-09-03): not worth it — noted here, left alone.
;
; THE REAL PROTOCOL (port PORT_PRINTER = $FB, include/hardware.inc) —
; now checked against the REAL, VERBATIM ROM disassembly found locally
; (~/Downloads/Timex Sinclair 2068 ROM Disassembly.pdf, COPY-LINE at
; M0A4A), not just secondhand summaries. Two earlier secondhand sources
; (the real Fuse emulator's own printer.c, and skoolkid's own Spectrum
; ROM disassembly) had already independently agreed on the same three
; WRITE bits below, correctly, while a third (the Sinclair community
; wiki) disagreed and was discarded — but neither secondhand source
; mentioned the per-row setup write or the start-of-paper wait gate
; documented below, which only turned up once the real verbatim source
; was found and read directly.
;
; WRITE to PORT_PRINTER:
;   bit 7 (%10000000) = stylus: 1 = mark/print this dot, 0 = don't
;   bit 2 (%00000100) = motor: 1 = stop, 0 = run
;   bit 1 (%00000010) = speed: 1 = slow, 0 = fast
; READ from PORT_PRINTER:
;   bit 0 (%00000001) = 1 once the print head has reached the next dot
;                       position (poll this; writing ANY value resets
;                       it, per the real hardware's own latch behavior)
;   bit 6             = "printer not configured" if set — the real ROM
;                       (COPY-LINE, COPY-L-2) aborts immediately if
;                       this is set; PRINT_RASTER_ROW does the same
;   bit 7             = "start of paper" — the real ROM waits for this
;                       to become set, once per scan line, AFTER its
;                       own per-row setup write and BEFORE sending any
;                       real pixel data for that row. Missing this gate
;                       entirely was the real bug behind an earlier
;                       measured symptom (7 of 8 rows reaching a real
;                       Fuse output file) — see PRINT_RASTER_ROW's own
;                       header for the full history, including two
;                       other theories that were tried and refuted by
;                       direct evidence before this one was found.
;
; RASTER FORMAT: one printed line is 256 dot columns (32 characters x
; 8 pixels), 8 dot ROWS tall (one character cell's height), MSB-first
; within each byte — the real ROM's own COPY-LINE pulls bit 7 first.
; The LAST TWO of the 8 raster rows go out at SLOW motor speed
; (verbatim: `LD A,B / CP $03 / SBC A,A / AND $02`, B holding the
; scan-line countdown 8..1) — presumably to let the paper-feed
; mechanism settle before the next character row begins.
;
; WHAT THIS ADDS:
;   LPRINT ( addr len -- )   prints len characters starting at addr,
;             wrapped into as many 32-column printed lines as needed
;             (the last space-padded if shorter than 32, and len=0
;             still prints exactly one blank line) — not a truncating
;             one-liner.
;   LLIST  ( -- )   prints the name of every word CURRENTLY IN THE RAM
;             DICTIONARY (addresses >= FORTH_DICT_RAM — i.e. defined
;             by the user since cold start), one name per printed
;             line, newest-defined first. Deliberately does NOT print
;             the ~100 ROM-resident primitive names too: real BASIC's
;             own LLIST only ever showed YOUR OWN program, never the
;             ROM's own routines, and dumping the whole permanent
;             vocabulary on every LLIST would be noise, not a listing.
; ============================================================================

    IFNDEF CORE_PRINTER_ASM
    DEFINE CORE_PRINTER_ASM

PRINT_LINE_BUF   EQU $8942   ; 256 bytes: 8 raster rows x 32 columns,
                             ; one printed line's worth of dot data
PRINT_COL_IDX    EQU $8A42   ; 1 byte: LPRINT_RENDER_LINE's own column
                             ; counter (0-31)
PRINT_SRC_ADDR   EQU $8A43   ; 2 bytes: source string for the CURRENT
                             ; printed line
PRINT_SRC_LEN    EQU $8A45   ; 1 byte: how many of this line's 32
                             ; columns are real characters (0-32); the
                             ; rest are space-padded
PRINT_GLYPH_PTR  EQU $8A46   ; 2 bytes: LPRINT_RENDER_LINE's own
                             ; source-glyph-byte pointer
PRINT_DEST_PTR   EQU $8A48   ; 2 bytes: LPRINT_RENDER_LINE's own
                             ; destination pointer into PRINT_LINE_BUF
PRINT_ROW_IDX    EQU $8A4A   ; 1 byte: LPRINT_SEND_LINE's own raster
                             ; row counter (0-7)
PRINT_REMAINING  EQU $8A4B   ; 2 bytes: W_LPRINT's own remaining
                             ; character count across multiple lines
PRINT_CUR_ADDR   EQU $8A4D   ; 2 bytes: W_LPRINT's own current source
                             ; pointer across multiple lines
PRINT_LLIST_HDR  EQU $8A4F   ; 2 bytes: W_LLIST's own current header
                             ; pointer while walking the chain
                             ;
                             ; ALL of the above are kept in NAMED
                             ; MEMORY, not registers, on purpose:
                             ; GFX_CHAR_TO_FONT_OFFSET destroys
                             ; AF/BC/DE/HL (this project's own fix to
                             ; that routine's header — found while
                             ; writing this very file), and nothing
                             ; but memory reliably survives repeated
                             ; calls into it, the same lesson Phase
                             ; 46's own SPACES bug already taught.

BLANK_GLYPH: DB 0, 0, 0, 0, 0, 0, 0, 0   ; used when a character has
                                          ; no glyph at all (GFX_CHAR_
                                          ; TO_FONT_OFFSET's own carry
                                          ; contract) or for space-
                                          ; padding past a line's real
                                          ; text

; ============================================================================
; PRINTER_MOTOR_STOP -- NOT a dictionary word.
; ============================================================================
PRINTER_MOTOR_STOP:
    ld   a, %00000100
    out  (PORT_PRINTER), a
    ret

; ============================================================================
; PRINT_RASTER_ROW ( HL = 32-byte row buffer, A = 1 for slow speed
; else 0 -- NOT a dictionary word ) -- bit-bangs one 256-dot raster
; row, MSB-first within each byte. Destroys: AF, BC, DE, HL.
;
; THIRD VERSION, this one checked against the REAL, VERBATIM ROM
; disassembly (~/Downloads/Timex Sinclair 2068 ROM Disassembly.pdf,
; found locally after the first two attempts were both reasoned guesses
; from secondhand summaries) -- specifically COPY-LINE, M0A4A. Two
; earlier attempts were tried and REFUTED by direct evidence rather
; than assumed correct:
;   1. Original: one throwaway "start the motor" write before row 0's
;      own real data. A clean, isolated single-LPRINT test showed
;      exactly 7 of 8 rows reaching the output file.
;   2. Made row 0's own first real bit double as that unconditional
;      first write instead of following a throwaway one (reasoning:
;      the real protocol retroactively paints using the PREVIOUS
;      write's value, so a content-free first write donates real
;      budget to nothing). A re-test with the SAME clean methodology
;      produced byte-for-byte IDENTICAL output (still 7 of 8, same
;      file size) -- cleanly refuting this theory rather than leaving
;      it ambiguous.
; The real COPY-LINE reveals what both guesses missed: a SEPARATE
; speed/motor-status write happens ONCE PER ROW (not once per job, and
; not folded into the first pixel) -- verbatim: `LD A,B / CP $03 /
; SBC A,A / AND $02 / OUT ($FB),A` (B holds the scan-line countdown
; 8..1; this produces $02 for the last two lines, $00 otherwise, and
; is written UNCONDITIONALLY, no poll, since the read side can't report
; "ready" until a write has told it to start) -- AND a "wait for start
; of paper" gate right after it (`IN A,($FB) / ADD A,A / RET M / JR
; NC,COPY-L-1`, testing bit 6 as an abort-if-set "printer not
; configured" signal and bit 7 as "loop until set" the real start-of-
; line signal) that this file never implemented in either earlier
; attempt. The per-pixel bit0-ready poll further down (COPY-L-5: `IN
; A,($FB) / RRA / JR NC,COPY-L-5`) DOES match what this file already
; had from the start -- that part was correct.
;
; Not yet re-confirmed against a fresh Fuse run as of this fix (see
; docs/PROJECT_PLAN.md's own Phase 47 section for the live status) --
; but this is now checked against the real, verbatim source code
; itself, not a secondhand paraphrase or a guess.
; ============================================================================
PRINT_RASTER_ROW:
    add  a, a               ; speed bit into position 1 (%00000010)
    ld   c, a                ; c = this row's own combined baseline
                              ; (bit2=0 run, bit1=speed, bit7=0) --
                              ; reused below for every real pixel too
    out  (PORT_PRINTER), a   ; the per-row setup write -- unconditional,
                              ; no poll (matches COPY-LINE's own LD A,B
                              ; / CP $03 / SBC A,A / AND $02 / OUT
                              ; ($FB),A, done once per scan line)
.wait_paper:
    in   a, (PORT_PRINTER)
    bit  6, a
    ret  nz                   ; "printer not configured" -- the real
                                ; ROM aborts here too (RET M); this
                                ; project doesn't try to recover or
                                ; signal it any further than that
    bit  7, a
    jr   z, .wait_paper          ; not yet "start of paper" -- keep
                                   ; waiting (matches COPY-L-1/COPY-L-2)
    ld   b, 32                     ; 32 bytes = 256 dot columns
.byteloop:
    ld   e, (hl)
    inc  hl
    ld   d, 8                  ; 8 bits in this byte
.bitloop:
    rlc  e                       ; original bit 7 of e -> carry
                                  ; (MSB-first, matching the real ROM)
    ld   a, 0
    jr   nc, .stylus_off
    ld   a, %10000000
.stylus_off:
    or   c
    push af                        ; save the byte to send -- IN below
                                     ; will overwrite A
.waitready:
    in   a, (PORT_PRINTER)
    and  1
    jr   z, .waitready
    pop  af
    out  (PORT_PRINTER), a
    dec  d
    jr   nz, .bitloop
    djnz .byteloop
    ret

; ============================================================================
; LPRINT_RENDER_LINE ( -- ) -- NOT a dictionary word. Renders exactly
; PRINT_SRC_LEN characters (already clamped 0-32 by the caller) from
; PRINT_SRC_ADDR into PRINT_LINE_BUF, space-padding the remaining
; columns. Does NOT send anything to the printer -- see
; LPRINT_SEND_LINE for that.
; ============================================================================
LPRINT_RENDER_LINE:
    xor  a
    ld   (PRINT_COL_IDX), a
.colloop:
    ld   a, (PRINT_COL_IDX)
    cp   32
    ret  z
    ld   c, a                    ; c = this column (0-31)
    ld   a, (PRINT_SRC_LEN)
    cp   c                        ; a - c: z if len==c, carry if len<c
    jr   z, .usespace              ; len==c: column c is past the end
    jr   c, .usespace                ; len<c: also past the end
    ld   hl, (PRINT_SRC_ADDR)
    ld   b, 0
    add  hl, bc
    ld   a, (hl)                     ; a = this column's real character
    jr   .havechar
.usespace:
    ld   a, " "
.havechar:
    call GFX_CHAR_TO_FONT_OFFSET
    jr   nc, .haveglyph
    ld   hl, BLANK_GLYPH
.haveglyph:
    ld   (PRINT_GLYPH_PTR), hl
    ld   a, (PRINT_COL_IDX)
    ld   e, a
    ld   d, 0
    ld   hl, PRINT_LINE_BUF
    add  hl, de
    ld   (PRINT_DEST_PTR), hl        ; row 0's slot for this column
    ld   b, 8
.rowcopy:
    ld   hl, (PRINT_GLYPH_PTR)
    ld   a, (hl)
    inc  hl
    ld   (PRINT_GLYPH_PTR), hl
    ld   hl, (PRINT_DEST_PTR)
    ld   (hl), a
    ld   de, 32
    add  hl, de
    ld   (PRINT_DEST_PTR), hl
    djnz .rowcopy
    ld   a, (PRINT_COL_IDX)
    inc  a
    ld   (PRINT_COL_IDX), a
    jr   .colloop

; ============================================================================
; LPRINT_SEND_LINE ( -- ) -- NOT a dictionary word. Bit-bangs the
; already-rendered PRINT_LINE_BUF out over PORT_PRINTER: sends all 8
; raster rows (the last two at slow speed; PRINT_RASTER_ROW's own
; per-row setup write and start-of-paper wait handle starting the
; motor fresh for each row, matching the real ROM's own COPY-BUFF/
; COPY-LINE split — see that routine's own header), then stops the
; motor once at the end (matching COPY-BUFF's own COPY-END).
; ============================================================================
LPRINT_SEND_LINE:
    ld   hl, FONT_TABLE - 256
    ld   (ZX_SYSVAR_CHARS), hl   ; see hardware.inc's own header on this
                                  ; constant -- needed for Fuse's printer
                                  ; text-OCR to recognize anything at all;
                                  ; re-set every line, safe re: GFX_FILL
    xor  a
    ld   (PRINT_ROW_IDX), a
.rowloop:
    ld   a, (PRINT_ROW_IDX)
    ld   l, a
    ld   h, 0
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl                  ; hl = row * 32
    ld   de, PRINT_LINE_BUF
    add  hl, de                   ; hl = this row's buffer address
    ld   a, (PRINT_ROW_IDX)
    cp   6
    jr   c, .fastspeed
    ld   a, 1                      ; rows 6-7: slow
    jr   .callrow
.fastspeed:
    xor  a
.callrow:
    call PRINT_RASTER_ROW
    ld   a, (PRINT_ROW_IDX)
    inc  a
    ld   (PRINT_ROW_IDX), a
    cp   8
    jr   c, .rowloop
    call PRINTER_MOTOR_STOP
    ret

; ============================================================================
; LPRINT ( addr len -- )
; ============================================================================
H_LPRINT:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   6, "L","P","R","I","N","T"
W_LPRINT:
    call DPOP_HL             ; hl = len
    ld   (PRINT_REMAINING), hl
    call DPOP_HL              ; hl = addr
    ld   (PRINT_CUR_ADDR), hl
.lineloop:
    ld   hl, (PRINT_REMAINING)
    ld   a, h
    or   a
    jr   nz, .chunk32           ; remaining >= 256: definitely >= 32
    ld   a, l
    cp   32
    jr   nc, .chunk32
    ld   (PRINT_SRC_LEN), a      ; remaining < 32: chunk = remaining
    jr   .havechunk
.chunk32:
    ld   a, 32
    ld   (PRINT_SRC_LEN), a
.havechunk:
    ld   hl, (PRINT_CUR_ADDR)
    ld   (PRINT_SRC_ADDR), hl
    call LPRINT_RENDER_LINE
    call LPRINT_SEND_LINE
    ld   a, (PRINT_SRC_LEN)
    ld   e, a
    ld   d, 0
    ld   hl, (PRINT_CUR_ADDR)
    add  hl, de
    ld   (PRINT_CUR_ADDR), hl
    ld   hl, (PRINT_REMAINING)
    or   a
    sbc  hl, de
    ld   (PRINT_REMAINING), hl
    ld   a, h
    or   l
    jr   nz, .lineloop            ; more left: another full-or-partial
                                    ; line; len=0 already printed its
                                    ; one blank line above and exits
                                    ; here on the first pass
    ret

; ============================================================================
; LLIST ( -- )
; ============================================================================
H_LLIST:
    DW   H_LPRINT
    DB   5, "L","L","I","S","T"
W_LLIST:
    ld   hl, (LATEST)
.walkloop:
    ld   a, h
    or   l
    ret  z                        ; end of the whole chain
    ld   (PRINT_LLIST_HDR), hl
    ld   de, FORTH_DICT_RAM
    or   a
    sbc  hl, de                    ; carry set if header < FORTH_DICT_RAM
    jr   c, .done                   ; reached a ROM-resident primitive:
                                     ; RAM words are a contiguous
                                     ; newest-first prefix of the
                                     ; chain, so this is the end of the
                                     ; user's own program
    ld   hl, (PRINT_LLIST_HDR)
    ld   de, 2
    add  hl, de                     ; hl -> LENFLAGS
    ld   a, (hl)
    and  $1F
    ld   (PRINT_SRC_LEN), a
    inc  hl                          ; hl -> name's first character
    ld   (PRINT_SRC_ADDR), hl
    call LPRINT_RENDER_LINE
    call LPRINT_SEND_LINE
    ld   hl, (PRINT_LLIST_HDR)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl                      ; hl = LINK (previous header)
    jr   .walkloop
.done:
    ret

DICT_LATEST_INIT_PRINTER EQU H_LLIST   ; head of the dictionary once
                                        ; this file's own words are
                                        ; included

    ENDIF
