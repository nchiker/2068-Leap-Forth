; ============================================================================
; rom/forth_smoke_p55.asm — Phase 55 smoke ROM: HIRES and NORMAL (High
; Resolution Graphics mode, core/hires.asm)
;
; FIVE CHECKPOINTS:
;   1. HIRES clears the Second Display File to ATTR_DEFAULT ($44) —
;      peeked directly, before any pixel is plotted.
;   2. Two PLOTs with two different INK colors, same 8x8 character cell
;      but two different scanlines (y=20 and y=21, both col 1) — proves
;      REAL per-scanline color resolution: peeking both scanlines' own
;      attribute bytes in the Second Display File shows each keeps its
;      OWN ink color, no clash (Normal mode would force both onto one
;      shared 8x8-cell attribute byte instead).
;   3. FILL, called while HIRES is still active, must do nothing —
;      re-peeking the exact same two bytes from checkpoint 2 proves
;      FILL's widened GFX_MODE guard (core/moregfx.asm, this phase)
;      actually stopped it from clobbering the Second Display File with
;      its own relocated scratch (same RAM, see that file's header).
;   4. CLS, called while HIRES is still active, resets the Second
;      Display File to CURRENT_ATTR — proves core/ts2068.asm's W_CLS
;      fix (this phase) actually runs, not just GFX_SET_MODE's own
;      one-time mode-entry clear from checkpoint 1.
;   5. NORMAL switches back — a PLOT afterward lands in the ordinary
;      8x8-cell attribute area (GFX_CELL_ATTR_ADDR) with the right ink,
;      proving the mode switch is real, not just cosmetic.
;
; Border goes GREEN (4) if all five pass; otherwise it shows the
; failing checkpoint's number.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    DS   $0008 - $, $FF
RST_08: ret
    DS   $0010 - $, $FF
RST_10: ret
    DS   $0018 - $, $FF
RST_18: ret
    DS   $0020 - $, $FF
RST_20: ret
    DS   $0028 - $, $FF
RST_28: ret
    DS   $0030 - $, $FF
RST_30: ret
    DS   $0038 - $, $FF
RST_38:
    ei
    ret
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn
    DS   $0100 - $, $FF

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP

    ld   hl, DICT_LATEST_INIT_HIRES
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 1: HIRES clears the Second Display File ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP1
    ld   de, SRC_CP1_LEN
    call INTERPRET_RUN
    ld   a, (SECOND_DISPLAY_ADDR)
    cp   $44
    jp   nz, FAIL_TEST

; ---- checkpoint 2: real per-scanline color resolution ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP2
    ld   de, SRC_CP2_LEN
    call INTERPRET_RUN
    ld   b, 20                    ; y=20, col=1 (x=10 -> 10>>3=1)
    ld   c, 1
    call HIRES_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   1                        ; ink 1, set right before the first PLOT
    jp   nz, FAIL_TEST
    ld   b, 21                    ; y=21, same char cell (21>>3 == 20>>3),
    ld   c, 1                     ; but a different real scanline
    call HIRES_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   6                        ; ink 6, set right before the second PLOT
    jp   nz, FAIL_TEST

; ---- checkpoint 3: FILL while HIRES is active must be a no-op ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP3
    ld   de, SRC_CP3_LEN
    call INTERPRET_RUN
    ld   b, 20
    ld   c, 1
    call HIRES_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   1                        ; unchanged from checkpoint 2
    jp   nz, FAIL_TEST
    ld   b, 21
    ld   c, 1
    call HIRES_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   6                        ; unchanged from checkpoint 2
    jp   nz, FAIL_TEST

; ---- checkpoint 4: CLS while HIRES is active resets to CURRENT_ATTR ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP4
    ld   de, SRC_CP4_LEN
    call INTERPRET_RUN
    ld   b, 20
    ld   c, 1
    call HIRES_ATTR_ADDR
    ld   a, (hl)
    ld   b, a
    ld   a, (CURRENT_ATTR)         ; 2 INK just ran, so this is $3A
                                    ; (DEFAULT_ATTR $38 with ink bits
                                    ; replaced by 2)
    cp   b
    jp   nz, FAIL_TEST

; ---- checkpoint 5: NORMAL switches back to ordinary attribute cells ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_CP5
    ld   de, SRC_CP5_LEN
    call INTERPRET_RUN
    ld   a, (GFX_MODE)
    or   a
    jp   nz, FAIL_TEST
    ld   b, 0                     ; y=5 -> char row 5>>3=0
    ld   c, 0                     ; x=5 -> char col 5>>3=0
    call GFX_CELL_ATTR_ADDR
    ld   a, (hl)
    and  $07
    cp   3                        ; ink 3, set right before this PLOT
    jp   nz, FAIL_TEST

    jp   PASS_TEST

; ---- test-harness-only helper: NOT a dictionary word ----
; HIRES_ATTR_ADDR: B = real scanline y (0-191), C = char column (0-31)
; -> HL = the Second Display File address covering that pixel, same
; row*32+col formula kernel/graphics's own GFX_SET_ATTR_EXT uses
; internally (its own header has the from-scratch derivation and
; verification; not re-derived here, just reused for peeking).
HIRES_ATTR_ADDR:
    ld   h, 0
    ld   l, b
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl
    add  hl, hl                  ; y*32
    ld   de, SECOND_DISPLAY_ADDR
    add  hl, de
    ld   d, 0
    ld   e, c
    add  hl, de
    ret

PASS_TEST:
    ld   a, 4                    ; green: all five checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

SRC_CP1: DB "HIRES "
SRC_CP1_LEN EQU $ - SRC_CP1

SRC_CP2: DB "1 INK 10 20 PLOT 6 INK 10 21 PLOT "
SRC_CP2_LEN EQU $ - SRC_CP2

SRC_CP3: DB "10 20 FILL "
SRC_CP3_LEN EQU $ - SRC_CP3

SRC_CP4: DB "2 INK CLS "
SRC_CP4_LEN EQU $ - SRC_CP4

SRC_CP5: DB "NORMAL 3 INK 5 5 PLOT "
SRC_CP5_LEN EQU $ - SRC_CP5

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS         ; NOT H_BORDER: that's core/ts2068.asm's
                                     ; own Phase-5-only tail marker, which
                                     ; orphans CLS (added to that same file
                                     ; later) -- this ROM's own checkpoint 4
                                     ; needs real CLS, unlike
                                     ; forth_smoke_p17.asm's template (whose
                                     ; own test source never calls CLS, so
                                     ; it never surfaced there)
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/hires.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p55_rom0.bin", $0000, $4000
