; ============================================================================
; kernel/io/io.asm -- keyboard scanning, key decoding and the joystick read
;
; The matrix scan (IO_KEY_SCAN_ROW/ALL into IO_SCAN_TABLE), the single-key finder (IO_FIND_KEY,
; IO_KEY_STILL_DOWN), the decoder (IO_DECODE_KEY and its three 40-entry tables), and the consumers
; of the interrupt handler's latched key (IO_READ_KEY, IO_KEY_AVAILABLE). All scanning, debounce and
; repeat run every frame in KBD_ISR_TICK (kernel/interrupt/interrupt.asm), which calls the scan,
; find and decode routines here; the foreground only reads KBD_LASTK/KBD_KEYHIT.
;
; The keyboard is a stock Spectrum's: 8 rows of 5 bits read through port $FE, active low. CAPS
; SHIFT+digit gives the cursor, delete and delete-line codes, CAPS SHIFT+ENTER KEY_INSERT_LINE,
; CAPS SHIFT+SPACE KEY_BREAK (include/keys.inc), CAPS SHIFT+letter the uppercase letter. Unshifted
; letters are lowercase. SYMBOL SHIFT gives the punctuation in KEY_ASCII_TABLE_SYMBOL, with
; 2068-Leap-C's map for ~ | \ { } [ ] ^ (its delta D7); positions with no single-character meaning
; (the stock keyboard's compound tokens, SYMBOL SHIFT + Q W E X I) are left 0.
; ============================================================================

    INCLUDE "include/hardware.inc"
    INCLUDE "include/keys.inc"

; ---- keyboard matrix layout: row-select byte -> bits 0-4 of the byte read (active low) ----
; The row is selected by the value in A at the IN instruction (it goes on the high address lines).
;   Row $FE: bit0=CAPS SHIFT bit1=Z bit2=X bit3=C bit4=V
;   Row $FD: bit0=A bit1=S bit2=D bit3=F bit4=G
;   Row $FB: bit0=Q bit1=W bit2=E bit3=R bit4=T
;   Row $F7: bit0=1 bit1=2 bit2=3 bit3=4 bit4=5
;   Row $EF: bit0=0 bit1=9 bit2=8 bit3=7 bit4=6
;   Row $DF: bit0=P bit1=O bit2=I bit3=U bit4=Y
;   Row $BF: bit0=ENTER bit1=L bit2=K bit3=J bit4=H
;   Row $7F: bit0=SPACE bit1=SYMBOL SHIFT bit2=M bit3=N bit4=B
KEY_ROW_COUNT   EQU 8

; ============================================================================
; IO_KEY_SCAN_ROW -- read one keyboard row
; In:  A = row-select byte (one of the $FE/$FD/.../$7F values above)
; Out: A = bits 0-4 = key state for that row (0 = pressed), bits 5-7 undefined
; Destroys: AF
; ============================================================================
IO_KEY_SCAN_ROW:
    in   a, (PORT_ULA)
    ret

; ============================================================================
; IO_KEY_SCAN_ALL -- read all 8 rows into IO_SCAN_TABLE (one byte per row, in ROW_TABLE's order)
; In:  none
; Out: IO_SCAN_TABLE filled; HL = IO_SCAN_TABLE (start of the table)
; Destroys: AF, BC, HL
; ============================================================================
IO_KEY_SCAN_ALL:
    ld   hl, IO_SCAN_TABLE
    ld   b, KEY_ROW_COUNT
    ld   c, 0                    ; C = row index
.scan_loop:
    push bc
    push hl
    ld   hl, ROW_TABLE
    ld   b, 0
    add  hl, bc                   ; HL -> ROW_TABLE[C]
    ld   a, (hl)                  ; A = this row's select byte
    pop  hl
    call IO_KEY_SCAN_ROW
    ld   (hl), a
    inc  hl
    pop  bc
    inc  c
    djnz .scan_loop
    ld   hl, IO_SCAN_TABLE
    ret

; ============================================================================
; IO_FIND_KEY -- the one non-modifier key that is down, in a table filled by IO_KEY_SCAN_ALL
; CAPS SHIFT (row 0 bit 0) and SYMBOL SHIFT (row 7 bit 1) are never reported: IO_DECODE_KEY reads
; them from IO_SCAN_TABLE. With two or more other keys down it reports none, and KBD_ISR_TICK
; starts over on the next tick.
;
; In:  IO_SCAN_TABLE already filled (via IO_KEY_SCAN_ALL)
; Out: carry set + B = row (0-7), C = bit (0-4) if exactly one
;      non-modifier key is down; carry clear (B/C undefined) if zero
;      or 2+ are down
; Destroys: AF, BC, DE, HL
; ============================================================================
IO_FIND_KEY:
    ld   hl, IO_SCAN_TABLE
    ld   d, 0                       ; D = row index (0-7)
    ld   e, $FF                     ; E = the key's row*5+bit; $FF = none yet (a second one: ambiguous)
.row_loop:
    ld   a, (hl)
    and  $1F
    cp   $1F
    jr   z, .next_row                ; nothing down anywhere in this row
    ld   b, (hl)                     ; B = the row byte, shifted right per bit
    ld   c, 0                       ; C = bit index within row (0-4)
.bit_loop:
    bit  0, b
    jr   nz, .bit_next                ; bit set = not pressed
    ; pressed at (D,C): skip the two modifier positions
    ld   a, d
    or   a
    jr   nz, .chk_row7
    ld   a, c
    or   a
    jr   z, .bit_next                  ; row0 bit0 = CAPS SHIFT, skip
    jr   .chk_record
.chk_row7:
    cp   7
    jr   nz, .chk_record
    ld   a, c
    cp   1
    jr   z, .bit_next                  ; row7 bit1 = SYMBOL SHIFT, skip
.chk_record:
    ld   a, e
    cp   $FF
    jr   nz, .ambiguous                 ; already have one
    ld   a, d
    add  a, a
    add  a, a
    add  a, d                          ; A = row*5
    add  a, c                           ; A = row*5 + bit
    ld   e, a
.bit_next:
    srl  b
    inc  c
    ld   a, c
    cp   5
    jr   nz, .bit_loop
.next_row:
    inc  hl
    inc  d
    ld   a, d
    cp   8
    jr   nz, .row_loop
    ld   a, e
    cp   $FF
    jr   z, .none
    ld   a, e
    ld   b, 0
.divloop:
    cp   5
    jr   c, .divdone
    sub  5
    inc  b
    jr   .divloop
.divdone:
    ld   c, a
    scf
    ret
.none:
    or   a
    ret
.ambiguous:
    or   a
    ret

; ============================================================================
; IO_KEY_STILL_DOWN -- is one given key still held, whatever else is down
; In:  B = row (0-7), C = bit (0-4), IO_SCAN_TABLE already filled
; Out: carry set if that key is still down, carry clear if released; B and C unchanged (the
;      caller then passes them to IO_DECODE_KEY)
; Destroys: AF, DE, HL
; ============================================================================
IO_KEY_STILL_DOWN:
    ld   hl, IO_SCAN_TABLE
    ld   a, b
    add  a, l
    ld   l, a
    jr   nc, .no_carry
    inc  h
.no_carry:
    ld   d, (hl)               ; D = the row byte, shifted right E times
    ld   e, c                   ; E = the shift count (not B: B must survive)
.shift_loop:
    ld   a, e
    or   a
    jr   z, .test
    srl  d
    dec  e
    jr   .shift_loop
.test:
    bit  0, d
    jr   nz, .not_down
    scf
    ret
.not_down:
    or   a
    ret

; ============================================================================
; IO_DECODE_KEY -- translate a (row, bit) position from IO_FIND_KEY into a key code
; The CAPS SHIFT / SYMBOL SHIFT state is read from IO_SCAN_TABLE (filled by IO_KEY_SCAN_ALL). Priority:
; CAPS SHIFT combos (cursor, delete, delete-line, insert-line, BREAK), CAPS SHIFT + anything else
; (uppercase table), SYMBOL SHIFT table, plain table.
; In:  B = row (0-7), C = bit (0-4)
; Out: A = the code (KEY_CURSOR_*, KEY_DELETE, KEY_DELETE_LINE, KEY_INSERT_LINE, KEY_BREAK or
;      ASCII), or 0 if this position/shift combination is unmapped
; Destroys: AF, DE, HL
; ============================================================================
IO_DECODE_KEY:
    ld   a, (IO_SCAN_TABLE)          ; row 0: bit0 = CAPS SHIFT
    bit  0, a
    jr   nz, .check_symshift          ; CAPS SHIFT not held

    ; CAPS SHIFT + a combo key, by (row, bit)
    ld   a, b
    cp   3
    jr   nz, .not_row3_caps
    ld   a, c
    or   a
    jr   nz, .not_delline
    ld   a, KEY_DELETE_LINE           ; row3 bit0 = '1'
    ret
.not_delline:
    cp   4
    jr   nz, .not_row3_caps
    ld   a, KEY_CURSOR_LEFT            ; row3 bit4 = '5'
    ret
.not_row3_caps:
    ld   a, b
    cp   6
    jr   nz, .not_row6_caps
    ld   a, c
    or   a
    jr   nz, .not_row6_caps
    ld   a, KEY_INSERT_LINE            ; row6 bit0 = ENTER
    ret
.not_row6_caps:
    ld   a, b
    cp   4
    jr   nz, .not_row4_caps
    ld   a, c
    or   a
    jr   nz, .not_delete
    ld   a, KEY_DELETE                 ; row4 bit0 = '0'
    ret
.not_delete:
    cp   2
    jr   nz, .not_right
    ld   a, KEY_CURSOR_RIGHT             ; row4 bit2 = '8'
    ret
.not_right:
    cp   3
    jr   nz, .not_up
    ld   a, KEY_CURSOR_UP                 ; row4 bit3 = '7'
    ret
.not_up:
    cp   4
    jr   nz, .not_row4_caps
    ld   a, KEY_CURSOR_DOWN                ; row4 bit4 = '6'
    ret
.not_row4_caps:
    ; CAPS SHIFT + SPACE -> BREAK (row 7's SPACE is unmapped in the uppercase table)
    ld   a, b
    cp   7
    jr   nz, .not_row7_caps
    ld   a, c
    or   a
    jr   nz, .not_row7_caps
    ld   a, KEY_BREAK                  ; row7 bit0 = SPACE
    ret
.not_row7_caps:
    ; CAPS SHIFT + anything else: the uppercase table
    ld   hl, KEY_ASCII_TABLE_UPPER
    jr   .table_lookup

.check_symshift:
    ld   a, (IO_SCAN_TABLE+7)        ; row 7: bit1 = SYMBOL SHIFT
    bit  1, a
    jr   nz, .no_shift                ; neither shift held
    ld   hl, KEY_ASCII_TABLE_SYMBOL
    jr   .table_lookup

.no_shift:
    ld   hl, KEY_ASCII_TABLE

; the three tables' shared lookup (Leap-C's): HL = the table, A = (HL + row*5 + bit)
.table_lookup:
    ld   a, b
    add  a, a
    add  a, a
    add  a, b                        ; A = row*5
    add  a, c                         ; A = row*5 + bit
    ld   e, a
    ld   d, 0
    add  hl, de
    ld   a, (hl)
    ret

; ============================================================================
; IO_LATCH_AND_CLEAR -- IO_READ_KEY's tail: the latched key, KBD_KEYHIT cleared
; In:  none
; Out: A = KBD_LASTK; KBD_KEYHIT cleared
; Destroys: AF
; ============================================================================
IO_LATCH_AND_CLEAR:
    ld   a, (KBD_LASTK)
    push af
    xor  a
    ld   (KBD_KEYHIT), a
    pop  af
    ret

; ============================================================================
; IO_READ_KEY -- wait for a key and return it
; In:  none
; Out: A = the key code (as IO_DECODE_KEY gives it; 0 for an unmapped position); KBD_KEYHIT cleared
; Destroys: AF
; ============================================================================
IO_READ_KEY:
.wait_hit:
    ld   a, (KBD_KEYHIT)
    or   a
    jr   z, .wait_hit
    jr   IO_LATCH_AND_CLEAR

; ============================================================================
; IO_KEY_AVAILABLE -- is a key waiting (KEY?)
; In:  none
; Out: A = 0 (nothing latched) or nonzero (a key is waiting); KBD_KEYHIT unchanged
; Destroys: AF
; ============================================================================
IO_KEY_AVAILABLE:
    ld   a, (KBD_KEYHIT)
    ret

; ============================================================================
; STICK_READ -- read a joystick through the AY's I/O port A (register 14)
; Stick 1 gives a 4-bit direction nibble, stick 2 a single bit (bit 7 of the port).
; In:  HL = device (1 or 2; not validated)
; Out: HL = stick value (device 1: 0-15, one bit per direction, 0 if all four read set;
;      device 2: 0 or 1)
; Destroys: AF, BC, DE, HL
; ============================================================================
STICK_READ:
    ld   a, l
    ld   d, a                          ; D = device (1 or 2)
    ld   a, $0E
    out  (PORT_AY_REG), a               ; select AY register 14 (I/O port A)
    ld   c, PORT_AY_DATA
    in   a, (c)                          ; A = raw joystick lines
    cpl                                   ; active-low -> active-high
    ld   b, d
    djnz .stick2                          ; device 2 jumps
    and  $0F                              ; stick 1: the four direction bits
    cp   $0F
    jr   c, .done
    xor  a                                 ; all four set: no real input
    jr   .done
.stick2:
    rlca                                   ; stick 2: bit 7 -> bit 0
    and  $01
.done:
    ld   l, a
    ld   h, 0
    ret

; the row-select bytes, in IO_SCAN_TABLE order
ROW_TABLE:
    DB   $FE, $FD, $FB, $F7, $EF, $DF, $BF, $7F

; The three key tables: 40 entries (8 rows x 5 bits), index = row*5 + bit, ROW_TABLE's row order;
; 0 = unmapped.
; KEY_ASCII_TABLE -- plain keys; letters are lowercase
KEY_ASCII_TABLE:
    ; row 0 ($FE): CAPS SHIFT, z, x, c, v
    DB   0, "z", "x", "c", "v"
    ; row 1 ($FD): a, s, d, f, g
    DB   "a", "s", "d", "f", "g"
    ; row 2 ($FB): q, w, e, r, t
    DB   "q", "w", "e", "r", "t"
    ; row 3 ($F7): 1, 2, 3, 4, 5
    DB   "1", "2", "3", "4", "5"
    ; row 4 ($EF): 0, 9, 8, 7, 6
    DB   "0", "9", "8", "7", "6"
    ; row 5 ($DF): p, o, i, u, y
    DB   "p", "o", "i", "u", "y"
    ; row 6 ($BF): ENTER, l, k, j, h
    DB   KEY_ENTER, "l", "k", "j", "h"
    ; row 7 ($7F): SPACE, SYMBOL SHIFT, m, n, b
    DB   " ", 0, "m", "n", "b"

; KEY_ASCII_TABLE_UPPER -- CAPS SHIFT + letter; the digits are 0 because the combos in IO_DECODE_KEY
; take them first
KEY_ASCII_TABLE_UPPER:
    ; row 0: CAPS SHIFT, Z, X, C, V
    DB   0, "Z", "X", "C", "V"
    ; row 1: A, S, D, F, G
    DB   "A", "S", "D", "F", "G"
    ; row 2: Q, W, E, R, T
    DB   "Q", "W", "E", "R", "T"
    ; row 3: 1, 2, 3, 4, 5
    DB   0, 0, 0, 0, 0
    ; row 4: 0, 9, 8, 7, 6
    DB   0, 0, 0, 0, 0
    ; row 5: P, O, I, U, Y
    DB   "P", "O", "I", "U", "Y"
    ; row 6: ENTER (CAPS SHIFT+ENTER is KEY_INSERT_LINE, taken earlier), L, K, J, H
    DB   0, "L", "K", "J", "H"
    ; row 7: SPACE (CAPS SHIFT+SPACE is KEY_BREAK, taken earlier), SYMBOL SHIFT, M, N, B
    DB   0, 0, "M", "N", "B"

; KEY_ASCII_TABLE_SYMBOL -- SYMBOL SHIFT + key. Q/W/E of row 2 are two-character tokens on the stock
; keyboard (<= <> >=) and stay 0, as do X and I. Row 1, U, Y and H are 2068-Leap-C's (delta D7):
; ~ | \ { } on A-G, the Spectrum legends ] [ on U Y and the up arrow ^ on H.
KEY_ASCII_TABLE_SYMBOL:
    ; row 0: CAPS SHIFT, Z, X, C, V
    DB   0, ":", 0, "?", "/"
    ; row 1: A, S, D, F, G
    DB   "~", "|", $5C, "{", "}"
    ; row 2: Q, W, E, R, T
    DB   0, 0, 0, "<", ">"
    ; row 3: 1, 2, 3, 4, 5
    DB   "!", "@", "#", "$", "%"
    ; row 4: 0, 9, 8, 7, 6
    DB   "_", ")", "(", "'", "&"
    ; row 5: P, O, I, U, Y
    DB   '"', ";", 0, "]", "["
    ; row 6: ENTER, L, K, J, H
    DB   0, "=", "+", "-", "^"
    ; row 7: SPACE, SYMBOL SHIFT, M, N, B
    DB   0, 0, ".", ",", "*"

; ============================================================================
; IO_CHECK_BREAK -- is BREAK (CAPS SHIFT+SPACE) held right now
; Does its own scan and never waits; meant to be polled by a running program. BREAK is seen only if
; it is the one non-modifier key down.
; In:  none
; Out: carry set if BREAK is currently held, carry clear otherwise
; Destroys: AF, BC, DE, HL
; ============================================================================
IO_CHECK_BREAK:
    call IO_KEY_SCAN_ALL
    call IO_FIND_KEY
    ret  nc                       ; none, or 2+ keys down: not BREAK
    call IO_DECODE_KEY            ; B/C = the key found
    cp   KEY_BREAK
    jr   z, .found
    or   a                        ; some other key/combo — clear carry
    ret
.found:
    scf
    ret
