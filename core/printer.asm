; ============================================================================
; core/printer.asm -- LPRINT and LLIST: the ZX Printer
;
; Needs core/dict.asm (LATEST, FORTH_DICT_RAM) and kernel/graphics/graphics.asm (GFX_CHAR_TO_FONT_OFFSET).
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
;
; The protocol, port PORT_PRINTER ($FB, include/hardware.inc), as the TS2068 ROM's COPY-LINE does it:
;   write bit 7 = stylus (1 = mark this dot); bit 2 = motor (1 = stop, 0 = run); bit 1 = speed (1 = slow)
;   read  bit 0 = the head has reached the next dot position (poll it; any write resets it)
;         bit 6 = printer not configured (COPY-LINE aborts; so does PRINT_RASTER_ROW)
;         bit 7 = start of paper: waited for once per raster row, after that row's setup write and
;                 before its pixel data
; A printed line is 256 dots (32 characters of 8 pixels) by 8 raster rows, each byte sent MSB first. Every
; row starts with an unconditional setup write of the speed bits (slow for the last two rows, as the ROM
; does), then the start-of-paper wait; the motor is stopped once, after the eighth row.
; LPRINT sets ZX_SYSVAR_CHARS to FONT_TABLE - 256 for each line, so that Fuse's printer text output reads
; the characters in Forth's own font (FONT_TABLE is printable ASCII in code order, as Fuse assumes). The
; .pbm output is correct to the dot except that Fuse's printer model lets the head position drift across
; the 8 rows of a line (the stock ROM shows the same).
; ============================================================================

    IFNDEF CORE_PRINTER_ASM
    DEFINE CORE_PRINTER_ASM

BLANK_GLYPH: DB 0, 0, 0, 0, 0, 0, 0, 0   ; for a character with no glyph, and for space padding

; ============================================================================
; PRINTER_MOTOR_STOP -- stop the printer motor (not a dictionary word)
; Destroys: AF
; ============================================================================
PRINTER_MOTOR_STOP:
    ld   a, %00000100
    out  (PORT_PRINTER), a
    ret

; ============================================================================
; PRINT_RASTER_ROW -- send one 256-dot raster row, MSB first (not a dictionary word)
; In:  HL = the 32-byte row buffer, A = 1 for slow speed, 0 for fast
; Out: returns early, with the row unsent, if the printer reports "not configured"
; Destroys: AF, BC, DE, HL
; ============================================================================
PRINT_RASTER_ROW:
    add  a, a               ; speed bit into position 1 (%00000010)
    ld   c, a                ; c = this row's baseline (motor run, speed, stylus off), ORed into every dot
    out  (PORT_PRINTER), a   ; the row's setup write: unconditional, no poll
.wait_paper:
    in   a, (PORT_PRINTER)
    bit  6, a
    ret  nz                   ; "printer not configured": give up, as the ROM does
    bit  7, a
    jr   z, .wait_paper          ; not yet start of paper
    ld   b, 32                     ; 32 bytes = 256 dot columns
.byteloop:
    ld   e, (hl)
    inc  hl
    ld   d, 8                  ; 8 bits in this byte
.bitloop:
    rlc  e                       ; original bit 7 of e -> carry (MSB first)
    ld   a, 0
    jr   nc, .stylus_off
    ld   a, %10000000
.stylus_off:
    or   c
    push af                        ; the byte to send; IN below overwrites A
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
; LPRINT_RENDER_LINE -- render a line into PRINT_LINE_BUF, space-padded (not a dictionary word)
; In:  PRINT_SRC_ADDR, PRINT_SRC_LEN (0-32, clamped by the caller)
; Out: PRINT_LINE_BUF = 8 rows of 32 bytes; nothing is sent to the printer
; Destroys: AF, BC, DE, HL
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
; LPRINT_SEND_LINE -- send PRINT_LINE_BUF to the printer: 8 raster rows (the last two slow), then stop
; the motor (not a dictionary word)
; In:  PRINT_LINE_BUF rendered by LPRINT_RENDER_LINE
; Out: ZX_SYSVAR_CHARS = FONT_TABLE - 256
; Destroys: AF, BC, DE, HL
; ============================================================================
LPRINT_SEND_LINE:
    ld   hl, FONT_TABLE - 256
    ld   (ZX_SYSVAR_CHARS), hl   ; see include/forth_layout.inc; set for every line
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
    jp   PRINTER_MOTOR_STOP

; ============================================================================
; LPRINT ( addr len -- ) -- print len characters from addr on the printer, 32 to a line (the last line
; space-padded); len = 0 prints one blank line
; ============================================================================
H_LPRINT:
    DW   DICT_CHAIN_POINT
    DB   6, "L","P","R","I","N","T"
W_LPRINT:
    rst RST_DPOP            ; hl = len
    ld   (PRINT_REMAINING), hl
    rst RST_DPOP             ; hl = addr
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
    jr   nz, .lineloop            ; more left; len=0 printed its one blank line and exits here
    ret

; ============================================================================
; LLIST ( -- ) -- print the name of each word in the RAM dictionary (at or above FORTH_DICT_RAM: the
; user's own definitions), newest first, one per printed line; the ROM's words are not listed
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
    jr   c, .done                   ; a ROM word: the RAM words are a newest-first prefix of the chain,
                                     ; so this is the end of the user's own definitions
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


    ENDIF
