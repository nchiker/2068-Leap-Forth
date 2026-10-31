; ============================================================================
; rom/forth_boot.asm -- the HOME ROM image (forth_boot_rom0.bin, 16 KB at $0000)
;
; Assembles the whole HOME image: the RST/NMI vectors, the fixed GRAPHICS_HOME_TABLE, COLD_START and
; the interactive loop's error hooks, then the kernel (kernel/), then the dictionary (core/*.asm),
; chained into one list by the DICT_CHAIN_POINT splices (each core file's first header links to the
; point set before its INCLUDE). The EXROM image (rom/graphics_exrom.asm) is built separately and
; reaches HOME only through GRAPHICS_HOME_TABLE.
;
; Interrupts are enabled before STARTUP_CHIME because the chime waits with HALT.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

    INCLUDE "include/forth_layout.inc"

; RST 00: cold start
RST_00:
    di
    jp   COLD_START

    INCLUDE "include/rst_vectors.inc"
; RST 38: the IM 1 interrupt
RST_38:
    call KBD_ISR_TICK
    ei
    reti

; the room up to the NMI vector and up to the table at $0100 holds two kernel files
    INCLUDE "kernel/memory/memory.asm"
    ASSERT $ <= $0066
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    INCLUDE "kernel/interrupt/interrupt.asm"
    ASSERT $ <= $0100
    DS   $0100 - $, $FF

; ============================================================================
; GRAPHICS_HOME_TABLE -- fixed-address JP veneers through which the EXROM calls into HOME
; The HOME routines move whenever the dictionary changes; the slots do not. Append-only: a slot's
; position never changes once an EXROM image is built against it (tools/export_home_symbols.py reads
; this table from the source: the `DS $0100 - $, $FF` pad above it fixes the base).
; ============================================================================
GRAPHICS_HOME_TABLE:
    jp   GFX_WRITE_PIXEL          ; slot 0: B=x, C=y, A=attr
    jp   GFX_SET_ATTR             ; slot 1: A=attr, B=row, C=col
    jp   GFX_LINE                 ; slot 2: no registers; reads GFX_LINE_X0/Y0/X1/Y1/ATTR
    jp   GFX_ROW_BASE_ADDR        ; slot 3: A=row -> HL=that row's bitmap base (scanline 0)
    jp   GFX_CELL_ATTR_ADDR       ; slot 4: B=row, C=col -> HL=addr
    jp   WRAP_CALC                ; slot 5: the edit line's wrap table
    jp   WRAP_CALC_AT             ; slot 6: HL=text, A=length, C=cursor/$FF
    jp   ED_DRAW_ROWS             ; slot 7: the table's rows from FWRAP_TOP
    jp   ED_DRAW_CURSOR           ; slot 8: the cursor from table, FWRAP_TOP
    jp   EDITOR_EDIT_KEY          ; slot 9: A=key; carry=ENTER, NZ=changed
    jp   IO_READ_KEY              ; slot 10: the key wait -> A
    jp   EDIT_CURSOR_TO_ROWCOL    ; slot 11: B=row, C=col
    jp   FORGET_PRINT_MSG         ; slot 12: HL=zero-terminated text
    jp   ED_STATUS_ROW            ; slot 13: B=23, HL=text, D=characters: the status bar

; ============================================================================
; COLD_START -- reset entry: initialise the machine and the system cells, show the version on the
; status bar, chime, and enter the interactive loop with the version still up
; In:  none (RST 00, interrupts off)
; Out: does not return (jumps to EDITOR_LOOP_LIVE)
; ============================================================================
COLD_START:
    ld   sp, MACHINE_STACK_TOP
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ; Port $FF (DECR) is a hardware register with an arbitrary power-on state: write a known value
    ; before anything reads or read-modify-writes PORT_FF_SHADOW (kernel/graphics, kernel/bank)
    xor  a
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ; Power-on RAM is not guaranteed zero: clear $8000 up to COLD_CLEAR_END (core/free.asm's
    ; DICT_RAM_CEILING, then UDG_TABLE, which nothing else initialises; the gap between them is
    ; unused). One fill is smaller than two.
    ASSERT COLD_CLEAR_END > DICT_RAM_CEILING
    ld   hl, RAM_CELLS_BASE
    ld   bc, COLD_CLEAR_END - RAM_CELLS_BASE
    call MEM_FILL_ZERO

    ld   hl, DICT_LATEST_COLD          ; the head of the full chain
    ld   (LATEST), hl

    ; STORE_END must be STORE_START (an empty store) before the first typed line is appended
    ld   hl, STORE_START
    ld   (STORE_END), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a         ; core/doloop.asm: must start at 0
    ld   (CATCH_DEPTH), a         ; core/throwcatch.asm: must start at 0
    ld   a, ATTR_DEFAULT          ; the attribute GFX_CLS paints: EMIT stamps CURRENT_ATTR on every
    ld   (CURRENT_ATTR), a        ;   character
    ld   a, 4
    ld   (F_PLACES), a            ; core/fpprint.asm: F. prints 4 decimals
    ld   a, 1
    ld   (FWRAP_OLD_COUNT), a
    ld   (VERSION_UP), a          ; core/editor.asm: the first key takes the version off row 23

    ld   a, BORDER_DEFAULT        ; the border's power-on colour is the ULA's, not defined
    call GFX_SET_BORDER
    call GFX_CLS                  ; EMIT's output starts at row 0, column 0 (PRINT_ROW/PRINT_COL: the fill)
    ld   hl, FORTH_VERSION_TEXT   ; the version on the status bar (Leap V2's), up before the chime
    ld   bc, EDIT_ROW << 8 | 2
    call GFX_PRINT_STRING
    call GFX_STATUS_BAR

    call KBD_ISR_INIT               ; before EI
    im   1
    ei                              ; before the chime: it waits with HALT

    call STARTUP_CHIME

    ; the empty input line as EDITOR_LOOP_LIVE's redraw leaves it, but row 23 not redrawn: the cursor
    ; flashes in the bar's column 0 and the first key's redraw (EDITOR_PROCESS_KEY) clears the version
    call WRAP_CALC
    ld   a, EDIT_ROW
    ld   (FWRAP_TOP), a
    call ED_DRAW_CURSOR
    jp   EDITOR_LOOP_LIVE.keyloop

; ============================================================================
; STARTUP_CHIME -- a startup chord: C4/E4/G4 on the three AY channels, entering one after another
; with a stepped volume ramp (4, 8, 12, three frames each), held 22 frames, then faded out together
; (8, 4, 0, three frames each). Leap V2's chime C (~/2068-Leap rom/exrom_v2_shell.asm, MIT, same
; owner): the chord this ROM played from a register/value table, generated by loops.
; In:  interrupts on (the waits HALT)
; Out: all three channels silent; R0-R5 the three periods, R6 0, R7 $F8 (tones on, noise off)
; Destroys: AF, BC, HL
; ============================================================================
STARTUP_CHIME:
    ld   hl, CHIME_REGS
    ld   b, 0
.init:
    ld   c, (hl)
    call SOUND_WRITE                ; R0-R10 from CHIME_REGS (SOUND_WRITE keeps B and C)
    inc  hl
    inc  b
    ld   a, b
    cp   11
    jr   c, .init
    ld   b, 8                       ; attack: channel A, then B, then C
.chan:
    ld   c, 4
.up:
    call SOUND_WRITE                ; level 4, 8, 12, three frames each
    call .wait3
    ld   a, c
    add  a, 4
    ld   c, a
    cp   16
    jr   c, .up
    inc  b
    ld   a, b
    cp   11
    jr   c, .chan
    ld   a, 19                      ; hold the full chord (22 frames after C's last step)
    call .wait
    ld   c, 8                       ; release: all three at 8, then 4, then 0
.rel:
    ld   b, 8
.relch:
    call SOUND_WRITE
    inc  b
    ld   a, b
    cp   11
    jr   c, .relch
    call .wait3
    ld   a, c
    sub  4
    ld   c, a
    jr   nc, .rel
    ret
.wait3:
    ld   a, 3
.wait:                              ; A frames, one HALT each
    halt
    dec  a
    jr   nz, .wait
    ret

CHIME_REGS:
    ; tone periods A 421 (C4, ~262 Hz), B 334 (E4, ~330 Hz), C 281 (G4, ~392 Hz); the noise period;
    ; the mixer (tones on, noise off); the three levels 0
    DB   165,1, 78,1, 25,1, 0, 248, 0,0,0

    INCLUDE "include/forth_version.inc"
    ASSERT $ - FORTH_VERSION_TEXT <= 28       ; 27 characters and the 0: columns 2-28

; ============================================================================
; INTERPRET_UNKNOWN_WORD -- core/interp.asm's hook for a token that is neither a word nor a number
; Reached by a bare `jp` from INTERPRET_RUN, so SP holds only INTERPRET_RUN's return address.
; Resets both stacks, prints the word and "?", and returns to EDITOR_LOOP_LIVE with the rest of the
; line abandoned (through REPORT_INTERP_ERROR).
; In:  WORD_BUF = the token
; Out: STATE = 0, INTERP_ERROR_FLAG = 1, both stacks empty; returns to the outermost INTERPRET_RUN's
;      caller
; Destroys: all registers
; ============================================================================
INTERPRET_UNKNOWN_WORD:
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    call EDIT_ERR_PREFIX          ; core/edit.asm: `LINE n ` while EDIT commits line n
    ; print the token before the "?" (W_EMIT destroys BC, so B and HL are saved around it)
    ld   a, (WORD_BUF)
    ld   b, a
    ld   hl, WORD_BUF+1
.printword:
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .printword
    ld   hl, " "
    rst RST_DPUSH
    call W_EMIT
    ld   hl, "?"
    rst RST_DPUSH
    call W_EMIT
    ld   hl, 13
    rst RST_DPUSH
    call W_EMIT

; ============================================================================
; REPORT_INTERP_ERROR -- the shared tail of INTERPRET_UNKNOWN_WORD and RUNTIME_ERROR_HOOK
; In:  none
; Out: STATE = 0, INTERP_ERROR_FLAG = 1 (EDITOR_LOOP_LIVE prints no OK); SP = THROW_ROOT_SP, then
;      `ret` to that frame's return address
; Destroys: AF
; ============================================================================
REPORT_INTERP_ERROR:
    xor  a
    ld   (STATE), a
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a   ; EDITOR_LOOP_LIVE prints no OK for this line
    ld   sp, (THROW_ROOT_SP)      ; back to the outermost INTERPRET_RUN's caller, even from a nested
    ret                           ;   run (LOAD-TEXT): the whole interpretation stops

; ============================================================================
; RUNTIME_ERROR_HOOK -- core/interp.asm's STACK_CHECK error hook, and the report of an uncaught THROW
; Reached like INTERPRET_UNKNOWN_WORD (a bare `jp`; both stacks already empty). Prints the message of
; THROW_CODE from RUNTIME_ERROR_TABLE, `ERROR n` for a code not in it, or `STACK?` when THROW_CODE
; is 0 (STACK_CHECK), then a newline, and ends through REPORT_INTERP_ERROR.
; In:  THROW_CODE (cleared here)
; Out: as REPORT_INTERP_ERROR
; Destroys: all registers
; ============================================================================
RUNTIME_ERROR_HOOK:
    call EDIT_ERR_PREFIX          ; core/edit.asm: `LINE n ` while EDIT commits line n
    ld   hl, (THROW_CODE)         ; core/throwcatch.asm: the code of an uncaught THROW; 0 from STACK_CHECK
    ld   de, 0
    ld   (THROW_CODE), de         ; used up
    ld   a, h
    or   l
    ex   de, hl                   ; DE = the code
    ld   hl, RUNTIME_ERROR_MSG
    jr   z, .msg                  ; no THROW: STACK?
    ld   a, d
    inc  a
    jr   nz, .other               ; the table's codes are -1 to -255
    ld   hl, RUNTIME_ERROR_TABLE
.find:
    ld   a, (hl)
    or   a
    jr   z, .other                ; end of the table
    inc  hl
    cp   e
    jr   z, .msg
.skip:
    ld   a, (hl)
    inc  hl
    or   a
    jr   nz, .skip
    jr   .find
.other:                           ; ERROR n, n signed
    ld   hl, RUNTIME_ERROR_PFX
    push de
    call FORGET_PRINT_MSG
    pop  hl
    rst  RST_DPUSH
    call W_DOT
    jr   .msgdone
.msg:
    call FORGET_PRINT_MSG
.msgdone:
    ld   hl, 13
    rst RST_DPUSH
    call W_EMIT
    jr   REPORT_INTERP_ERROR

RUNTIME_ERROR_MSG: DB "STACK?", 0
RUNTIME_ERROR_PFX: DB "ERROR ", 0

; The messages of an uncaught THROW (docs/V2/FLOAT_SPEC.md section 8.4): the code's low byte (all
; are -1 to -255), then the text, NUL-ended; a 0 byte ends the table.
RUNTIME_ERROR_TABLE:
    DB   -8, "DICTIONARY FULL", 0
    DB   -13, "UNDEFINED WORD", 0
    DB   -16, "MISSING NAME", 0
    DB   -28, "BREAK", 0
    DB   -37, "TAPE ERROR", 0
    DB   -42, "DIVISION BY ZERO", 0
    DB   -43, "OUT OF RANGE", 0
    DB   -46, "INVALID ARGUMENT", 0
    DB   0

; ---- the kernel and the dictionary (after the boot code) ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/storage/storage.asm"
    ; The font (included below) must cover $11F8: ZEsarUX's tape autoload types J "" ENTER into the
    ; machine when the PC reaches $11F8 with the HOME ROM paged in (the stock ROM's key wait), which
    ; any code starting there would trigger (during LOAD-TEXT). Data is never executed. The files
    ; before it only set where the font falls; the ASSERT below checks it.
    INCLUDE "kernel/bank/bank.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "kernel/graphics/font.asm"
    ASSERT FONT_TABLE <= $11F8 && FONT_TABLE_END > $11F8   ; move the font if this fails (data must cover $11F8)
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/storage.asm"
DICT_CHAIN_POINT DEFL H_LOADLIB
    INCLUDE "core/fpcore.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/fpparse.asm"
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/fpprint.asm"
DICT_CHAIN_POINT DEFL H_FSDOT
    INCLUDE "core/fpconv.asm"
DICT_CHAIN_POINT DEFL H_FLOOR
    INCLUDE "core/fpmath.asm"
DICT_CHAIN_POINT DEFL H_DEG
    INCLUDE "core/beep.asm"
DICT_CHAIN_POINT DEFL H_BEEP
    INCLUDE "core/sound.asm"
DICT_CHAIN_POINT DEFL H_SOUND
    INCLUDE "core/soundext.asm"
DICT_CHAIN_POINT DEFL H_ENVELOPE
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/variable.asm"
DICT_CHAIN_POINT DEFL H_CONSTANT
    INCLUDE "core/fpstack.asm"
DICT_CHAIN_POINT DEFL H_FCONSTANT
    INCLUDE "core/dotquote.asm"
DICT_CHAIN_POINT DEFL H_DOTQUOTE
    INCLUDE "core/loop.asm"
DICT_CHAIN_POINT DEFL H_REPEAT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_FLASH
    INCLUDE "core/doloop.asm"
DICT_CHAIN_POINT DEFL H_I
    INCLUDE "core/loopext.asm"
DICT_CHAIN_POINT DEFL H_J
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/hires.asm"
DICT_CHAIN_POINT DEFL H_NORMAL
    INCLUDE "core/rectfill.asm"
DICT_CHAIN_POINT DEFL H_RECT
    INCLUDE "core/shapes.asm"           ; CIRCLE: a stub into the EXROM
DICT_CHAIN_POINT DEFL H_CIRCLE
    INCLUDE "core/polygon.asm"
DICT_CHAIN_POINT DEFL H_POLYGONFILL
    INCLUDE "core/sprite.asm"
DICT_CHAIN_POINT DEFL H_SPRITEHIDE
    INCLUDE "core/key.asm"
DICT_CHAIN_POINT DEFL H_BREAKQ
    INCLUDE "core/mathfn.asm"
DICT_CHAIN_POINT DEFL H_SLASH
    INCLUDE "core/arith.asm"
DICT_CHAIN_POINT DEFL H_MIN
    INCLUDE "core/array.asm"
DICT_CHAIN_POINT DEFL H_CELLS
    INCLUDE "core/string.asm"
DICT_CHAIN_POINT DEFL H_VAL
    INCLUDE "core/stringext.asm"
DICT_CHAIN_POINT DEFL H_CODE
    INCLUDE "core/execute.asm"
DICT_CHAIN_POINT DEFL H_EXECUTE
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/stick.asm"
DICT_CHAIN_POINT DEFL H_STICK
    INCLUDE "core/input.asm"
DICT_CHAIN_POINT DEFL H_INPUT
    INCLUDE "core/free.asm"
DICT_CHAIN_POINT DEFL H_FREE
    INCLUDE "core/throwcatch.asm"
DICT_CHAIN_POINT DEFL H_CATCH
    INCLUDE "core/stackops.asm"
DICT_CHAIN_POINT DEFL H_PICK
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/outwords.asm"
DICT_CHAIN_POINT DEFL H_SPACES
    INCLUDE "core/tick.asm"
DICT_CHAIN_POINT DEFL H_RBRACKET
    INCLUDE "core/comment.asm"
DICT_CHAIN_POINT DEFL H_PAREN
    INCLUDE "core/printer.asm"
DICT_CHAIN_POINT DEFL H_LLIST
    INCLUDE "core/ulaplus.asm"
DICT_CHAIN_POINT DEFL H_PALETTE
    INCLUDE "core/vlist.asm"
DICT_CHAIN_POINT DEFL H_VLIST
    INCLUDE "core/dictspace.asm"
DICT_CHAIN_POINT DEFL H_ALLOT
    INCLUDE "core/create.asm"
DICT_CHAIN_POINT DEFL H_CREATE
    INCLUDE "core/does.asm"
DICT_CHAIN_POINT DEFL H_DOES
    INCLUDE "core/immediate.asm"
DICT_CHAIN_POINT DEFL H_IMMEDIATE
    INCLUDE "core/abortquit.asm"
DICT_CHAIN_POINT DEFL H_QUIT
    INCLUDE "core/portio.asm"
DICT_CHAIN_POINT DEFL H_OUT
    INCLUDE "core/forget.asm"
DICT_CHAIN_POINT DEFL H_FORGET
    INCLUDE "core/udg.asm"
DICT_CHAIN_POINT DEFL H_UDG
    INCLUDE "core/loadtext.asm"
DICT_CHAIN_POINT DEFL H_LOADTEXT
    INCLUDE "core/edit.asm"
DICT_CHAIN_POINT DEFL H_EDIT
    INCLUDE "core/recall.asm"
DICT_LATEST_COLD EQU DICT_LATEST_INIT_LISTDEFS ; LATEST of an empty user dictionary (cold start;
                                              ;   core/storage.asm's LOAD-LIB after a failure)
DICT_CHAIN_POINT DEFL H_LISTDEFS
    INCLUDE "core/editor.asm"

    IFDEF LAYOUT_NEGCTL                 ; the RAM layout guard's negative controls (nothing is saved)
    INCLUDE "tests/layout_negctl.asm"
    ENDIF

    DS   $4000 - $, $FF

    SAVEBIN "forth_boot_rom0.bin", $0000, $4000
