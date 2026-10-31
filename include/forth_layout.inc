; ============================================================================
; include/forth_layout.inc -- the Leap-Forth RAM map
;
; The only file that defines a RAM address. Everything else reaches RAM through the symbols
; below (SCREEN_ADDR and ATTR_ADDR, which are hardware, are in include/hardware.inc). Both
; images include this file first: rom/forth_boot.asm (HOME) and rom/graphics_exrom.asm (EXROM).
; tools/check_ram_layout.py (make check) proves from the listings that every RAM name the code
; of either image references lies where this map allows it, and that no source holds a literal
; RAM address.
;
;   $4000-$5AFF  display file 1 (bitmap, attributes)              SCREEN_ADDR, ATTR_ADDR
;   $5B00-$72FF  FILL's shadow plane (EXROM, Normal mode only)    GFX_FILL_SHADOW
;   $7300-$7FFF  FILL's seed stack                                GFX_FILL_STACK .. GFX_FILL_STACK_END
;   $6000-$77FF  display file 2 (HIRES), over the two FILL areas  SECOND_DISPLAY_ADDR .. SECOND_DISPLAY_END
;                (FILL does nothing in HIRES)
;   $8000-$8503  the cells                                        RAM_CELLS_BASE .. RAM_CELLS_END
;   $8504-$88FF  float stack, 204 cells of 5 bytes                FSTACK_LIMIT .. FSTACK_TOP
;   $8900-$90FF  data stack                                       DSTACK_LIMIT .. DSTACK_TOP
;   $9100-$CFFF  dictionary ($A000-$BFFF is hidden while the      FORTH_DICT_RAM .. DICT_RAM_CEILING
;                EXROM is paged in)
;   $D000-$EFFF  line store                                       STORE_START .. STORE_LIMIT
;   $F000-$F17F  sprite buffers, then free                        SPRITE_SLOT_IMG_BUF, SPRITE_SLOT_BG_BUF
;   $F180-$F227  UDG table                                        UDG_TABLE
;   $F228-$F3C7  free
;   $F3C8-$FEFF  machine stack, top MACHINE_STACK_TOP, grows down (nothing in the ROM checks its depth)
;   $FF00-$FFFF  not used by the ROM (the test harness's return slot)
;
; Region symbols come first, then the cells block ($8000 up, assembler-computed: a name and
; its size, packed; the room left for new cells is at its end), then the cells above it. A cell
; the code no longer references is removed.
; ============================================================================

    IFNDEF FORTH_LAYOUT_INC
    DEFINE FORTH_LAYOUT_INC

; ---- regions ----
GFX_FILL_SHADOW     EQU $5B00       ; 6144 bytes: FILL's copy of the bitmap
ZX_SYSVAR_CHARS     EQU $5C36       ; stock CHARS, for Fuse's printer text output; the printer sets it before each line, FILL clears the shadow first
GFX_FILL_STACK      EQU $7300       ; 3328 bytes: FILL's seeds
GFX_FILL_STACK_END  EQU $8000
SECOND_DISPLAY_ADDR EQU $6000       ; HIRES attributes: byte $6000+n belongs to the bitmap byte at $4000+n
SECOND_DISPLAY_END  EQU $7800
RAM_CELLS_BASE      EQU $8000
RAM_CELLS_END       EQU $8504
FSTACK_LIMIT        EQU $8504       ; lowest legal IY
FSTACK_TOP          EQU $8900       ; empty-stack value of IY; the first push lands at $88FB
DSTACK_LIMIT        EQU $8900       ; lowest legal IX
DSTACK_TOP          EQU $9100       ; empty-stack value of IX; the first push lands at $90FE
FORTH_DICT_RAM      EQU $9100       ; first byte of the RAM dictionary
DICT_RAM_CEILING    EQU $D000       ; the dictionary ends where the line store begins
STORE_START         EQU $D000
LOADTEXT_BUF        EQU STORE_START ; LOAD-TEXT receives here
STORE_LIMIT         EQU $F000       ; the store never writes at or above it
MACHINE_STACK_LIMIT EQU $F3C8       ; lowest byte the layout leaves the stack
MACHINE_STACK_TOP   EQU $FF00       ; initial SP

; ---- sizes the cells are built from ----
POLY_MAXPTS         EQU 12          ; POLYGON vertices at most
SPRITE_SLOT_MAX     EQU 4           ; sprite slots (0-3)
SPRITE_CELLS        EQU 2           ; a sprite is 2 x 2 character cells
SPRITE_SLOT_BYTES   EQU SPRITE_CELLS * SPRITE_CELLS * 9   ; 36
UDG_COUNT           EQU 21          ; user-defined graphics
STORAGE_HEADER_FILENAME_LEN EQU 10  ; the tape header's name field

; ---- cells above the cells block ----
SPRITE_SLOT_IMG_BUF EQU $F000       ; 144 bytes: the captured sprites, 36 per slot
SPRITE_SLOT_BG_BUF  EQU SPRITE_SLOT_IMG_BUF + SPRITE_SLOT_MAX * SPRITE_SLOT_BYTES   ; 144 bytes: the saved backgrounds
UDG_TABLE           EQU $F180       ; UDG_COUNT x 8 bytes
COLD_CLEAR_END      EQU UDG_TABLE + UDG_COUNT * 8   ; the cold start zeroes RAM_CELLS_BASE up to here

; ---- the map tiles RAM (assembly time) ----
    ASSERT GFX_FILL_SHADOW == ATTR_ADDR + 768
    ASSERT GFX_FILL_SHADOW + 6144 == GFX_FILL_STACK
    ASSERT GFX_FILL_STACK_END == RAM_CELLS_BASE
    ASSERT SECOND_DISPLAY_ADDR >= GFX_FILL_SHADOW && SECOND_DISPLAY_END <= GFX_FILL_STACK_END
    ASSERT SECOND_DISPLAY_END - SECOND_DISPLAY_ADDR == 6144
    ASSERT ZX_SYSVAR_CHARS >= GFX_FILL_SHADOW && ZX_SYSVAR_CHARS + 2 <= GFX_FILL_STACK
    ASSERT RAM_CELLS_END == FSTACK_LIMIT && FSTACK_TOP - FSTACK_LIMIT == 204 * 5
    ASSERT FSTACK_TOP == DSTACK_LIMIT && DSTACK_TOP - DSTACK_LIMIT == 2048
    ASSERT DSTACK_TOP == FORTH_DICT_RAM && DICT_RAM_CEILING == STORE_START
    ASSERT (STORE_LIMIT & $FF) == 0     ; LOAD-TEXT's room test looks at the high byte only
    ASSERT STORE_LIMIT <= SPRITE_SLOT_IMG_BUF
    ASSERT SPRITE_SLOT_BG_BUF + SPRITE_SLOT_MAX * SPRITE_SLOT_BYTES <= UDG_TABLE
    ASSERT COLD_CLEAR_END <= MACHINE_STACK_LIMIT
    ASSERT MACHINE_STACK_LIMIT < MACHINE_STACK_TOP && MACHINE_STACK_TOP <= $FF00

; ---- the cells block: RAM_CELLS_BASE .. RAM_CELLS_END ----
LAYOUT_RETURN_ORG   EQU $
    ORG RAM_CELLS_BASE
IO_SCAN_TABLE:            DEFS 8                        ; keyboard matrix scan, one byte per row
PORT_FE_SHADOW:           DEFS 1                        ; last byte written to port $FE (border colour, MIC)
STORAGE_HEADER_BUF:       DEFS 17                       ; tape header payload: type, name (10), length, parameter 1, parameter 2
STORAGE_REQUEST_TYPE:     DEFS 1                        ; header type a SAVE or LOAD asks for
STORAGE_ENTRY_RETRY:      DEFS 2                        ; tape receive: pilot search budget
SQRT_OP:                  DEFS 2                        ; SQRT: working copy of the operand
SQRT_RES:                 DEFS 2                        ; SQRT: result so far
SQRT_COUNTER:             DEFS 1                        ; SQRT: loop count
RND_STATE:                DEFS 2                        ; RND: xorshift state, never 0
GFX_LINE_X0:              DEFS 2                        ; LINE: start x (signed)
GFX_LINE_Y0:              DEFS 2                        ; LINE: start y
GFX_LINE_X1:              DEFS 2                        ; LINE: end x
GFX_LINE_Y1:              DEFS 2                        ; LINE: end y
GFX_LINE_ATTR:            DEFS 1                        ; LINE and PLOT: attribute byte
GFX_LINE_N:               DEFS 2                        ; LINE: steps left
GFX_CIRCLE_XC:            DEFS 2                        ; CIRCLE: centre x
GFX_CIRCLE_YC:            DEFS 2                        ; CIRCLE: centre y
GFX_CIRCLE_R:             DEFS 2                        ; CIRCLE: radius; the octant's x offset while drawing
GFX_CIRCLE_ATTR:          DEFS 1                        ; CIRCLE: attribute byte
GFX_CIRCLE_PY:            DEFS 2                        ; CIRCLE: the octant's y offset
GFX_CIRCLE_ERR:           DEFS 2                        ; CIRCLE: midpoint error term
GFX_MODE:                 DEFS 1                        ; video mode: 0 Normal, 1 HIRES
PORT_FF_SHADOW:           DEFS 1                        ; last byte written to port $FF (video mode, EXROM select)
GFX_FILL_SP:              DEFS 2                        ; FILL: seed stack pointer (next free entry)
GFX_FILL_ATTR:            DEFS 1                        ; FILL: attribute byte
GFX_FILL_X:               DEFS 2                        ; FILL: seed x; then the span's left byte pointer
GFX_FILL_LPTR             EQU GFX_FILL_X                ; the span's left byte pointer
GFX_FILL_Y:               DEFS 2                        ; FILL: seed y; then the span's row (low) and byte count - 1 (high)
GFX_FILL_SY               EQU GFX_FILL_Y                ; the span's row
GFX_FILL_SN               EQU GFX_FILL_Y + 1            ; the span's byte count - 1
GFX_FILL_OVF:             DEFS 1                        ; FILL: nonzero when a seed was dropped (stack full)
GFX_FILL_AOFF:            DEFS 1                        ; FILL: work plane offset in pages (0 screen, $1B shadow)
GFX_FILL_EL:              DEFS 1                        ; FILL: span's left edge mask
GFX_FILL_ER:              DEFS 1                        ; FILL: span's right edge mask
RECT_X0:                  DEFS 1                        ; RECT: corner x0, as given
RECT_Y0:                  DEFS 1                        ; RECT: corner y0, as given
RECT_X1:                  DEFS 1                        ; RECT: corner x1, as given
RECT_Y1:                  DEFS 1                        ; RECT: corner y1, as given
RECT_ATTR:                DEFS 1                        ; RECT: fill attribute
RECT_CUR_X:               DEFS 1                        ; POLYGON fill: span x cursor
RECT_CUR_Y:               DEFS 1                        ; POLYGON fill: span y cursor
RECT_COL0:                DEFS 1                        ; RECT: x0 >> 3, the first byte column
RECT_COL1:                DEFS 1                        ; RECT: x1 >> 3, the last byte column
RECT_BIT0:                DEFS 1                        ; RECT: x0 & 7
RECT_BIT1:                DEFS 1                        ; RECT: x1 & 7
RECT_ROWBASE:             DEFS 2                        ; RECT: bitmap address of the scanline at column 0
RECT_ATTR_ROW:            DEFS 1                        ; RECT attribute pass: row
RECT_ATTR_ROW1:           DEFS 1                        ; RECT attribute pass: last row
RECT_ATTR_COL:            DEFS 1                        ; RECT attribute pass: column
POLY_COUNT:               DEFS 1                        ; POLYGON: vertex count (3-12)
POLY_VERTS:               DEFS POLY_MAXPTS * 2          ; POLYGON: vertices, (x, y) bytes in the order given
POLY_ATTR:                DEFS 1                        ; POLYGON: attribute byte
POLY_IDX:                 DEFS 1                        ; POLYGON: edge walk cursor
POLY_FILL_EDGE_Y0:        DEFS POLY_MAXPTS              ; POLYGON fill, per edge: top y
POLY_FILL_EDGE_Y1:        DEFS POLY_MAXPTS              ; POLYGON fill, per edge: bottom y
POLY_FILL_EDGE_X:         DEFS POLY_MAXPTS              ; POLYGON fill, per edge: current x
POLY_FILL_EDGE_DX:        DEFS POLY_MAXPTS              ; POLYGON fill, per edge: dx
POLY_FILL_EDGE_DY:        DEFS POLY_MAXPTS              ; POLYGON fill, per edge: dy
POLY_FILL_EDGE_SX:        DEFS POLY_MAXPTS              ; POLYGON fill, per edge: x step
POLY_FILL_EDGE_ERR:       DEFS POLY_MAXPTS * 2          ; POLYGON fill, per edge: running error, 2 bytes each
POLY_FILL_NEDGES:         DEFS 1                        ; POLYGON fill: edges in use (horizontal ones are skipped)
POLY_FILL_YMIN:           DEFS 1                        ; POLYGON fill: lowest y any edge starts at
POLY_FILL_YMAX:           DEFS 1                        ; POLYGON fill: highest y any edge ends at
POLY_FILL_Y:              DEFS 1                        ; POLYGON fill: the scanline being filled
POLY_FILL_CROSSINGS:      DEFS POLY_MAXPTS              ; POLYGON fill: this scanline's edge crossings, sorted
POLY_FILL_NCROSS:         DEFS 1                        ; POLYGON fill: valid crossings
POLY_FILL_I:              DEFS 1                        ; POLYGON fill: loop cursor
POLY_FILL_J:              DEFS 1                        ; POLYGON fill: inner loop cursor of the sort
POLY_FILL_PASS:           DEFS 1                        ; POLYGON fill: sort passes left
POLY_FILL_ERR_ADDR:       DEFS 2                        ; POLYGON fill: address of the current edge's error
GFX_SCROLL_DST_ROW:       DEFS 1                        ; scroll: destination row (0-22)
GFX_SCROLL_SRC_ROW:       DEFS 1                        ; scroll: source row (0-22)
KBD_LASTK:                DEFS 1                        ; last accepted key code
KBD_KEYHIT:               DEFS 1                        ; nonzero: KBD_LASTK holds a key not yet read
KBD_CUR_ROW:              DEFS 1                        ; matrix row of the key being tracked ($FF: none)
KBD_CUR_BIT:              DEFS 1                        ; its bit in that row (0-4)
KBD_DEBOUNCE:             DEFS 1                        ; ticks until a newly seen key is accepted
KBD_REPEAT:               DEFS 1                        ; ticks until the next auto-repeat
FRAMES:                   DEFS 2                        ; frame counter, one per interrupt
SPRITE_SLOT_DEFINED:      DEFS SPRITE_SLOT_MAX          ; per sprite slot: defined
SPRITE_SLOT_SHOWN:        DEFS SPRITE_SLOT_MAX          ; per sprite slot: drawn on the screen
SPRITE_SLOT_ROW:          DEFS SPRITE_SLOT_MAX          ; per sprite slot: top-left character row it was shown at
SPRITE_SLOT_COL:          DEFS SPRITE_SLOT_MAX          ; per sprite slot: top-left character column
SPRITE_OP_SLOT:           DEFS 1                        ; sprite transfer: slot
SPRITE_OP_ROW:            DEFS 1                        ; sprite transfer: top-left character row
SPRITE_OP_COL:            DEFS 1                        ; sprite transfer: top-left character column
SPRITE_OP_DIR:            DEFS 1                        ; sprite transfer: 0 capture (screen to buffer), nonzero blit
SPRITE_OP_BUF:            DEFS 2                        ; sprite transfer: buffer address (slot applied)
SPRITE_OP_CELL:           DEFS 1                        ; sprite transfer: cell in progress (0-3)
SPRITE_OP_PTR:            DEFS 2                        ; sprite transfer: next buffer byte
SPRITE_CELL_ROW:          DEFS 1                        ; sprite transfer: the cell's character row
SPRITE_CELL_COL:          DEFS 1                        ; sprite transfer: the cell's character column
BANK_EXROM_DEPTH:         DEFS 1                        ; EXROM page-in nesting depth (0: chunk 5 is HOME)
BLOCK_GFX_SCRATCH:        DEFS 8                        ; block graphics: glyph being built
SRC_PTR:                  DEFS 2                        ; interpreter: next unread source character
SRC_END:                  DEFS 2                        ; interpreter: one past the last source byte
STATE:                    DEFS 1                        ; 0 interpreting, 1 compiling
FIND_SEARCH_ADDR:         DEFS 2                        ; FIND: scratch
NUM_NEG:                  DEFS 1                        ; NUMBER: leading minus seen
WORD_SRC_ADDR:            DEFS 2                        ; FORGET: the parsed name
NEW_HEADER_ADDR:          DEFS 2                        ; HEADER_BUILD: the new header's address
INTERP_IMM_FLAG:          DEFS 1                        ; INTERPRET_RUN: scratch
INTERP_ERROR_FLAG:        DEFS 1                        ; set to 1 by an error; cleared on entry to INTERPRET_RUN
WORD_BUF:                 DEFS 34                       ; the word being looked up: count byte, up to 32 upper-case characters
THROW_ROOT_SP:            DEFS 2                        ; SP at the outermost INTERPRET_RUN, where an uncaught THROW returns
STORAGE_NAME_LEN:         DEFS 1                        ; tape name length (0: any name on LOAD)
STORAGE_NAME_BUF:         DEFS STORAGE_HEADER_FILENAME_LEN; tape name, space padded
FP_RAM:                   DEFS 66                       ; float scratch, one area; the names below overlay it
FX                        EQU FP_RAM                    ; 7 B unpacked float: [sign $80/0][exponent][m0 m1 m2 m3][guard]
FY                        EQU FP_RAM + 7                ; 7 B unpacked float
FQ                        EQU FP_RAM + 14               ; 5 B: a product or quotient being built, big-endian; N in ATOF
FDEXP                     EQU FP_RAM + 19               ; 2 B: ATOF's decimal exponent
FFLAGS                    EQU FP_RAM + 21               ; 1 B: ATOF flags: bit 0 a digit seen, bit 1 after the point, bit 2 a float
FMT                       EQU FP_RAM + 20               ; 24 B: F.'s 128.64 fixed point, big-endian; overlaps FDEXP and FFLAGS (never live together)
FDIG                      EQU FP_RAM + 44               ; 9 B: F.'s decimal digits, one per byte
FSQ_N                     EQU FP_RAM + 53               ; 5 B: FSQRT's argument; SIN and COS keep k, then r, here
FTRIG_R2                  EQU FP_RAM + 58               ; 5 B: r squared in the series
FTRIG_K                   EQU FP_RAM + 63               ; 2 B: k's low byte (its parity is the sign), 1 for COS
F_PLACES                  EQU FP_RAM + 65               ; 1 B: decimals F. prints (0-9; the cold start sets 4)
THROW_CODE:               DEFS 2                        ; code of an uncaught THROW, for the error message
CATCH_STACK:              DEFS 48                       ; CATCH frames: 8 x (SP, IX, IY)
LATEST:                   DEFS 2                        ; head of the dictionary chain
HERE:                     DEFS 2                        ; next free dictionary byte
PRINT_ROW:                DEFS 1                        ; EMIT: next row (0-22)
PRINT_COL:                DEFS 1                        ; EMIT: next column (0-31)
CURRENT_ATTR:             DEFS 1                        ; attribute PLOT, LINE and CIRCLE draw with
PL_TARGET:                DEFS 2                        ; +LOOP: pointer to the inline branch target
PL_INDEX:                 DEFS 2                        ; +LOOP: index before the step
PL_LIMIT:                 DEFS 2                        ; +LOOP: limit
PL_NEWIDX:                DEFS 2                        ; +LOOP: index after the step
PL_DOLD:                  DEFS 2                        ; +LOOP: index - limit before the step
PL_DNEW:                  DEFS 2                        ; +LOOP: index - limit after the step
LEAVE_DEPTH:              DEFS 1                        ; DO nesting depth (0: none open)
LEAVE_HEAD_TABLE:         DEFS 16                       ; per DO level: head of the pending LEAVE chain, 8 x 2
VAL_PTR:                  DEFS 2                        ; VAL: next character
VAL_COUNT:                DEFS 1                        ; VAL: scratch
VAL_NEG:                  DEFS 1                        ; VAL: leading minus seen
DOSSTR_ADDR:              DEFS 2                        ; string literal: address of the string
DOSSTR_LEN:               DEFS 1                        ; string literal: its length
SQUOTE_CODE_ADDR:         DEFS 2                        ; S" : HERE before compiling, to roll back when interpreting
ACCEPT_DEST:              DEFS 2                        ; ACCEPT: destination buffer
ACCEPT_MAX:               DEFS 1                        ; ACCEPT: maximum count
ACCEPT_LEN:               DEFS 1                        ; ACCEPT: count so far
ACCEPT_CHAR:              DEFS 1                        ; ACCEPT: character just read
FINPUT_BUF:               DEFS 8                        ; INPUT: number buffer
EDIT_BUF:                 DEFS 128                      ; the line being edited; EDIT_LEN is its length
EDIT_LEN:                 DEFS 1                        ; characters in EDIT_BUF
EDIT_CURSOR:              DEFS 1                        ; cursor position in EDIT_BUF, 0 to EDIT_LEN
SHIFT_COUNT:              DEFS 1                        ; editor: bytes left to shift on insert or delete
INS_CHAR_TMP:             DEFS 1                        ; editor: character being inserted
FWRAP_COUNT:              DEFS 1                        ; wrap table: rows the line spans (1-4)
FWRAP_START:              DEFS 4                        ; wrap table, per row: offset of its first character
FWRAP_LEN:                DEFS 4                        ; wrap table, per row: characters shown (0-32)
FWRAP_SCAN_PTR:           DEFS 2                        ; wrap: start of the row being computed
FWRAP_REMAIN:             DEFS 1                        ; wrap: characters not yet in a row
FWRAP_ROW_IDX:            DEFS 1                        ; wrap: row index scratch
FWRAP_LAST_SPACE:         DEFS 1                        ; wrap: last space in the row's window ($FF: none)
FWRAP_TMP_LEN:            DEFS 1                        ; wrap: scratch
FWRAP_TMP_OFFSET:         DEFS 1                        ; wrap: scratch
FWRAP_OLD_COUNT:          DEFS 1                        ; FWRAP_COUNT at the last redraw (1 from the cold start)
FWRAP_OVERFLOW:           DEFS 1                        ; 1: the line needs more rows than the table holds
FWRAP_WIDTH_MINUS1:       DEFS 1                        ; wrap width - 1
FWRAP_TOP:                DEFS 1                        ; screen row of the table's first row
FWRAP_CURSOR_AT_END:      DEFS 1                        ; wrap: 0 when the cursor is at the end of the text
FWRAP_BASE:               DEFS 2                        ; the text the wrap table describes
ED_ROW_JP:                DEFS 3                        ; RAM JP to the row drawer for the width
CHR_BUF:                  DEFS 1                        ; CHR: the one-character result
STR_BUF:                  DEFS 6                        ; STR: the result
CATCH_TMP_SP:             DEFS 2                        ; CATCH: staging cell for SP
CATCH_TMP_IX:             DEFS 2                        ; CATCH: staging cell for IX
CATCH_TMP_IY:             DEFS 2                        ; CATCH: staging cell for IY
CATCH_DEPTH:              DEFS 1                        ; active CATCH frames (0: none)
SPACES_COUNT:             DEFS 2                        ; SPACES: count left
PRINT_LINE_BUF:           DEFS 256                      ; printer: one line of dots, 8 raster rows x 32 bytes
PRINT_COL_IDX:            DEFS 1                        ; printer: column (0-31)
PRINT_SRC_ADDR:           DEFS 2                        ; printer: source of the current line
PRINT_SRC_LEN:            DEFS 1                        ; printer: real characters in the line (0-32)
PRINT_GLYPH_PTR:          DEFS 2                        ; printer: glyph byte pointer
PRINT_DEST_PTR:           DEFS 2                        ; printer: pointer into PRINT_LINE_BUF
PRINT_ROW_IDX:            DEFS 1                        ; printer: raster row (0-7)
PRINT_REMAINING:          DEFS 2                        ; LPRINT: characters left
PRINT_CUR_ADDR:           DEFS 2                        ; LPRINT: current source pointer
PRINT_LLIST_HDR:          DEFS 2                        ; LLIST: current header
FORGET_TARGET_ADDR:       DEFS 2                        ; FORGET: candidate header address
STORE_END:                DEFS 2                        ; line store: one past the last byte, the append cursor
DEF_COUNT:                DEFS 1                        ; LIST-DEFS: spans found (0-16)
DEF_TABLE:                DEFS 64                       ; LIST-DEFS spans: 16 x (offset from STORE_START, length)
RECALL_SCAN_PTR:          DEFS 2                        ; SCAN_DEFS: scratch
RECALL_SPAN_START:        DEFS 2                        ; SCAN_DEFS: scratch
RECALL_LIST_IDX:          DEFS 1                        ; LIST-DEFS: index of the span being listed
VIEW_RESULT:              DEFS 1                        ; what VIEW_SESSION reports
VIEW_CUR:                 DEFS 2                        ; view: the cursor line (its text is in EDIT_BUF)
VIEW_TOP:                 DEFS 2                        ; view: the first line on screen
VIEW_COUNT:               DEFS 2                        ; view: lines in the store
VIEW_OLDCUR:              DEFS 2                        ; view: VIEW_CUR / VIEW_TOP / VIEW_CROW before the key
VIEW_OLDTOP:              DEFS 2                        ; view: VIEW_TOP before the key
VIEW_PTR:                 DEFS 2                        ; view: a line's address, walking the store
VIEW_IDX:                 DEFS 2                        ; view: its index
VIEW_CELL:                DEFS 2                        ; view: the cursor cell last drawn (column, row)
VIEW_MSG:                 DEFS 1                        ; view: STORE FULL is on the status row
VIEW_OLDMSG:              DEFS 1                        ; view: VIEW_MSG before the key
VIEW_CROW:                DEFS 1                        ; view: screen row of the cursor line's first row
VIEW_CROWS:               DEFS 1                        ; view: its rows (the wrap table's count)
VIEW_OLDROW:              DEFS 1                        ; view: VIEW_CROW before the key
VIEW_ROW:                 DEFS 1                        ; view: screen row a walk has reached
VIEW_LEVEL:               DEFS 1                        ; view: what the key changed: 0 nothing, 1 cursor, 2 cursor line text, 3 lines
VIEW_COL:                 DEFS 1                        ; view: column UP and DOWN carry to a line
VIEW_KEYCODE:             DEFS 1                        ; view: key code
VIEW_EXTRA:               DEFS 1                        ; view: bytes a caller adds after VIEW_LEAVE
VIEW_FOUND:               DEFS 2                        ; view: 1 + the last line the name matched, or 0
VIEW_T1:                  DEFS 2                        ; view: scratch
VIEW_T2:                  DEFS 2                        ; view: scratch
VIEW_FLAG:                DEFS 1                        ; view: scratch
VIEW_TEXT:                DEFS 14                       ; view: the status row's text
EDIT_LINE_NO:             DEFS 2                        ; number of the line the commit loop is running (0: none)
VIEW_SH:                  DEFS 69                       ; view: row shadow, rows 0-22 x (line index 2, row in line 1); index $FFFF blank, $FFFE unknown
VIEW_SH_END:                                            ; one past VIEW_SH
VIEW_STOP:                DEFS 2                        ; view: VIEW_RENDER may stop after this line once the shadow agrees
STORE_LAST_LINE:          DEFS 2                        ; last line STORE_APPEND appended (0: none), for STORE_TRIM
VERSION_UP:               DEFS 1                        ; 1: the version is on row 23 (cold start to the first key)
STORE_MARK_N:             DEFS 2                        ; view: the line STORE_LINE found last ...
STORE_MARK_PTR:           DEFS 2                        ; ... and its address (line 0 at STORE_START: none yet)
    DEFS RAM_CELLS_END - $                              ; free: room for new cells
    ASSERT $ == RAM_CELLS_END
    ASSERT FP_RAM + 66 == THROW_CODE && FMT + 24 == FDIG && FDIG + 9 == FSQ_N && FQ + 8 == FFLAGS + 1
    ASSERT GFX_LINE_Y0 == GFX_LINE_X0 + 2 && GFX_LINE_X1 == GFX_LINE_X0 + 4 && GFX_LINE_Y1 == GFX_LINE_X0 + 6
    ASSERT VIEW_SH_END == VIEW_SH + 69 && VIEW_TEXT + 14 <= EDIT_LINE_NO && (VIEW_TEXT & $FF) + 14 < $100
    ORG LAYOUT_RETURN_ORG

    ENDIF
