; ============================================================================
; kernel/bank/cart.asm -- the DOCK cartridge build (-DCARTRIDGE, `make cart`; docs/cartridge.md)
;
; The cartridge runs Forth, and a program saved with SAVE-LIB, on a stock TS2068 (stock HOME ROM and
; EXROM, nothing replaced). The stock ROM finds the LROS header at DOCK $0000 (rom/forth_boot.asm's
; RST_00 under the flag) and jumps to CART_ENTRY. Every label of the release build keeps its address
; (tools/cart_check.py), so a dictionary compiled on the release ROMs runs here, and LIB tapes go both
; ways (this image carries the release's ROM_IDENTITY).
;
;   chunk  address  in the DOCK                     what the CPU sees
;   0-1    $0000    this HOME image (16 KB)         DOCK, always (HSR bits 0-1 never cleared)
;   2-3    $4000    the program image (optional)    HOME (screen, FILL's buffers); DOCK only in
;                                                   CART_START_PROGRAM, interrupts off
;   4      $8000    absent                          HOME: cells, stacks, dictionary
;   5      $A000    the EXROM (rom/graphics_exrom)  HOME (dictionary); DOCK while BANK_EXROM_DEPTH > 0
;   6-7    $C000    absent                          HOME: dictionary, line store, UDGs, machine stack
;
; Port $FF bit 7 is 0 from COLD_START on (DOCK, never the stock EXROM). The EXROM paging is
; kernel/bank/bank.asm's, under the flag: HSR CART_HSR_EXROM in, CART_HSR_HOME out, port $FF never
; written. The stock ROM's hand-off: interrupts may be on, IM 1, SP in its chunk-3 stack, HSR = the
; chunks the header marks used ($23). An interrupt before CART_ENTRY's `di` runs KBD_ISR_TICK on
; that stack, which only counts a frame and reads the keyboard into cells COLD_START then clears.
;
; The program image, at DOCK $4000 (tools/forthcart.py writes it; the offsets are CART_IMG_*):
;   +0    2    CART_MAGIC ("F1": a Forth program, format 1)
;   +2    2    ROM_IDENTITY of the ROM that compiled it (SAVE-LIB's header parameter 1)
;   +4    2    n, the dictionary's length (HERE - FORTH_DICT_RAM), at most DICT_RAM_CEILING - FORTH_DICT_RAM
;   +6    2    LATEST (SAVE-LIB's header parameter 2)
;   +8    32   the start word: its length (1-31), then its name, padded
;   +40   168  the UDG table (UDG_COUNT x 8 bytes)
;   +208  n    the dictionary, copied to FORTH_DICT_RAM
;   +208+n 2   CRC-16 (STORAGE_CRC) of bytes +0 .. +207+n, low byte first
; ============================================================================

    IFNDEF KERNEL_BANK_CART_ASM
    DEFINE KERNEL_BANK_CART_ASM

CART_HSR_HOME   EQU %00000011       ; chunks 0-1 DOCK (this ROM); the rest HOME
CART_HSR_EXROM  EQU %00100011       ; and chunk 5 DOCK (the EXROM)
CART_HSR_IMAGE  EQU %00001111       ; and chunks 2-3 DOCK (the program image); chunk 5 HOME
CART_CHUNK_SPEC EQU ~CART_HSR_EXROM & $FF   ; the LROS header's chunk byte: 0 = used (chunks 0, 1, 5)

CART_IMAGE      EQU $4000           ; DOCK chunk 2
CART_MAGIC      EQU "1" << 8 | "F"  ; "F1" in memory order
CART_IMG_IDENTITY EQU 2
CART_IMG_LENGTH EQU 4
CART_IMG_LATEST EQU 6
CART_IMG_START  EQU 8
CART_IMG_UDG    EQU 40
CART_IMG_DICT   EQU CART_IMG_UDG + UDG_COUNT * 8
CART_IMG_MAX    EQU DICT_RAM_CEILING - FORTH_DICT_RAM
    ASSERT CART_IMG_DICT + CART_IMG_MAX + 2 <= $4000     ; the largest image fits chunks 2-3

; ============================================================================
; CART_ENTRY -- the LROS entry: the stock ROM jumps here once it has found the header
; In:  HSR = CART_HSR_EXROM (the header's chunks), interrupts on or off
; Out: does not return (COLD_START)
; ============================================================================
CART_ENTRY:
    di
    ld   a, CART_HSR_HOME           ; chunk 5 back to HOME: the dictionary's RAM
    out  (PORT_BANK_HOME), a
    jp   COLD_START

; ============================================================================
; CART_START_PROGRAM -- COLD_START's call in place of STARTUP_CHIME: check the program image in DOCK
; chunks 2-3, copy it to FORTH_DICT_RAM and UDG_TABLE, and run its start word as a line typed at the
; prompt (EDITOR_LOOP_LIVE.enter): its output, then OK or the error, then the prompt
; In:  interrupts on; the screen cleared, the version on row 23
; Out: no image (no CART_MAGIC): the chime, then returns (COLD_START goes on to the prompt). An image
;      that fails a check (identity, length, start word, CRC): "BAD PROGRAM" on the output, the
;      chime, returns, the dictionary empty. A good image: does not return
; Destroys: all registers but IX, IY
; ============================================================================
CART_START_PROGRAM:
    di                              ; the screen and FILL's buffers are behind the image
    ld   a, CART_HSR_IMAGE
    out  (PORT_BANK_HOME), a
    ld   hl, (CART_IMAGE)
    ld   de, CART_MAGIC
    or   a
    sbc  hl, de
    jr   nz, .none
    ld   hl, (CART_IMAGE + CART_IMG_IDENTITY)
    ld   de, (ROM_IDENTITY)
    sbc  hl, de                     ; carry clear: the sbc above gave 0
    jr   nz, .bad
    ld   bc, (CART_IMAGE + CART_IMG_LENGTH)
    ld   hl, CART_IMG_MAX
    sbc  hl, bc
    jr   c, .bad                    ; longer than the dictionary's RAM
    ld   a, (CART_IMAGE + CART_IMG_START)
    dec  a
    cp   31
    jr   nc, .bad                   ; the start word's length is not 1-31
    ld   hl, CART_IMG_DICT
    add  hl, bc
    ld   b, h
    ld   c, l
    ld   hl, CART_IMAGE
    call STORAGE_CRC                ; DE = the CRC, HL = past the dictionary
    ld   a, (hl)
    cp   e
    jr   nz, .bad
    inc  hl
    ld   a, (hl)
    cp   d
    jr   z, .load
.bad:
    call .home
    ld   hl, CART_BAD_TEXT
    call FORGET_PRINT_MSG           ; on the output (row 0), before the prompt
    jp   STARTUP_CHIME
.none:
    call .home
    jp   STARTUP_CHIME
.home:
    ld   a, CART_HSR_HOME
    out  (PORT_BANK_HOME), a
    ei
    ret

.load:
    ld   hl, CART_IMAGE + CART_IMG_UDG
    ld   de, UDG_TABLE
    ld   bc, UDG_COUNT * 8
    ldir                            ; HL = the dictionary in the image
    ld   de, FORTH_DICT_RAM
    ld   bc, (CART_IMAGE + CART_IMG_LENGTH)
    ld   a, b
    or   c
    jr   z, .copied                 ; LDIR with BC = 0 would copy 64 KB
    ldir
.copied:
    ld   (HERE), de
    ld   hl, (CART_IMAGE + CART_IMG_LATEST)
    ld   (LATEST), hl
    ld   hl, CART_IMAGE + CART_IMG_START
    ld   c, (hl)                    ; B = 0 (the LDIR, or the length was 0)
    ld   a, c
    ld   (EDIT_LEN), a
    inc  hl
    ld   de, EDIT_BUF
    ldir
    call .home

    ld   hl, CHIME_REGS             ; the AY as the chime leaves it (SOUND's tones on), without it
    ld   b, 0
.ay:
    ld   c, (hl)
    call SOUND_WRITE                ; keeps B and C
    inc  hl
    inc  b
    ld   a, b
    cp   11
    jr   c, .ay
    call GFX_CLS                    ; the version off row 23: the program has the screen
    call WRAP_CALC                  ; the input line's rows, as COLD_START leaves them
    ld   a, EDIT_ROW
    ld   (FWRAP_TOP), a
    pop  hl                         ; COLD_START's return: the start word runs instead
    jp   EDITOR_LOOP_LIVE.enter

CART_BAD_TEXT:
    DB   "BAD PROGRAM", 13, 0

    ENDIF
