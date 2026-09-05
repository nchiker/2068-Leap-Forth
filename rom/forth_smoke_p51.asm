; ============================================================================
; rom/forth_smoke_p51.asm — Phase 51 smoke ROM: UDG (core/udg.asm)
;
; THREE checkpoints, numbered 0-2, reported by PRINTING the failing
; number (via `.`) rather than encoding it in the 3-bit border color —
; this project's own established convention since Phase 40/46/49/50
; (see rom/forth_smoke_p50.asm's own header for the aliasing history
; that made this the default now, even though 3 checkpoints alone would
; probably fit the border scheme safely).
;
;   0. Address arithmetic: 0 UDG == UDG_TABLE, 1 UDG == UDG_TABLE+8,
;      20 UDG (the last of the 21 slots) == UDG_TABLE+160.
;   1. Round trip via real Forth C!/C@: writes a hand-designed 8-byte
;      "spade" bitmap pattern into slot 0 one byte at a time using
;      `value 0 UDG offset + C!`, then reads every byte back with
;      `0 UDG offset + C@` and confirms it matches exactly — proves
;      UDG's own address arithmetic AND C@/C!'s byte-level access
;      compose correctly, not just that either works alone.
;   2. Real rendering round trip: EMITs character code 144
;      (UDG_CODE_BASE + slot 0) at PRINT_ROW/PRINT_COL (0,0) and reads
;      back all 64 pixels of the resulting 8x8 glyph via
;      kernel/graphics/graphics.asm's own GFX_READ_PIXEL, comparing
;      each one against the exact pattern bits written in checkpoint 1
;      (BIT_MASK_TABLE's own bit7-is-leftmost-pixel convention, which is
;      how GFX_PIXEL_ADDR_SETUP itself already decodes x&7 -- confirmed
;      by reading that table directly, not assumed) — proves
;      GFX_CHAR_TO_FONT_OFFSET really does route codes 144-164 to
;      UDG_TABLE and GFX_PUTCHAR really does draw whatever bytes are
;      there, not just that the address UDG computes happens to be
;      right.
;
; Border goes GREEN (4) if every checkpoint passes; on any failure the
; border goes RED (2) and the failing checkpoint's number prints via `.`
; before the ROM hangs. A bug in this file's OWN test source (an
; unrecognized word, or an uncaught runtime error) shows WHITE (7) and
; the literal text "BUG" instead, matching this project's own
; established convention.
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

    ld   hl, DICT_LATEST_INIT_UDG
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS                 ; start from a known-clear bitmap so a
                                  ; stray already-set pixel can't fake a pass

; ---- checkpoint 0: address arithmetic ----
    ld   a, 0
    ld   (CHECKPOINT_NUM), a

    ld   hl, SRC_ADDR0
    ld   de, SRC_ADDR0_LEN
    call INTERPRET_RUN            ; 0 UDG
    ld   de, UDG_TABLE
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_ADDR1
    ld   de, SRC_ADDR1_LEN
    call INTERPRET_RUN             ; 1 UDG
    ld   de, UDG_TABLE + 8
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_ADDR20
    ld   de, SRC_ADDR20_LEN
    call INTERPRET_RUN              ; 20 UDG (last of the 21 slots)
    ld   de, UDG_TABLE + 160
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 1: round trip via real Forth C!/C@ ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a

    ld   hl, SRC_WRITE
    ld   de, SRC_WRITE_LEN
    call INTERPRET_RUN               ; writes PATTERN_TABLE's 8 bytes into
                                       ; UDG slot 0, one C! per byte

    ld   hl, SRC_READ0
    ld   de, SRC_READ0_LEN
    call INTERPRET_RUN
    ld   de, 24                        ; %00011000
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ1
    ld   de, SRC_READ1_LEN
    call INTERPRET_RUN
    ld   de, 60                        ; %00111100
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ2
    ld   de, SRC_READ2_LEN
    call INTERPRET_RUN
    ld   de, 126                        ; %01111110
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ3
    ld   de, SRC_READ3_LEN
    call INTERPRET_RUN
    ld   de, 255                         ; %11111111
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ4
    ld   de, SRC_READ4_LEN
    call INTERPRET_RUN
    ld   de, 255                          ; %11111111
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ5
    ld   de, SRC_READ5_LEN
    call INTERPRET_RUN
    ld   de, 60                            ; %00111100
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ6
    ld   de, SRC_READ6_LEN
    call INTERPRET_RUN
    ld   de, 24                             ; %00011000
    call CHECK_TOP
    call W_DROP

    ld   hl, SRC_READ7
    ld   de, SRC_READ7_LEN
    call INTERPRET_RUN
    ld   de, 60                              ; %00111100
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: real rendering round trip via EMIT + GFX_READ_PIXEL ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a

    ld   hl, SRC_EMIT
    ld   de, SRC_EMIT_LEN
    call INTERPRET_RUN               ; 144 EMIT -- draws UDG slot 0's
                                       ; bitmap at char row 0, column 0
    call CHECK_UDG_RENDER

    jp   PASS_TEST

; ============================================================================
; CHECK_UDG_RENDER — no args. Walks all 8 rows x 8 columns of the glyph
; just EMITted at char cell (row 0, col 0) -- i.e. pixel rows/cols 0-7
; both axes -- comparing each pixel against PATTERN_TABLE's own bits via
; BIT_MASK_TABLE (kernel/graphics/graphics.asm), the SAME table
; GFX_PIXEL_ADDR_SETUP itself uses to decode x&7, confirmed by reading
; that routine directly (bit7 = leftmost pixel, i.e. column 0). Fails
; (jp FAIL_TEST) on the first mismatch.
; ============================================================================
CHECK_UDG_RENDER:
    xor  a
    ld   (CK_ROW), a
.rowloop:
    ld   a, (CK_ROW)
    cp   8
    jr   z, .done
    ld   e, a
    ld   d, 0
    ld   hl, PATTERN_TABLE
    add  hl, de
    ld   a, (hl)
    ld   (CK_ROWBYTE), a

    xor  a
    ld   (CK_COL), a
.colloop:
    ld   a, (CK_COL)
    cp   8
    jr   z, .rownext

    ld   e, a
    ld   d, 0
    ld   hl, BIT_MASK_TABLE
    add  hl, de
    ld   a, (hl)
    ld   b, a                    ; b = this column's bit mask
    ld   a, (CK_ROWBYTE)
    and  b
    ld   c, 0
    jr   z, .expect_ready
    ld   c, 1
.expect_ready:                    ; c = 1 if this pixel should be SET

    ld   a, (CK_COL)
    ld   b, a                     ; b = x (column -- pixel coords match
                                    ; char-cell coords 1:1 at row/col 0)
    ld   a, (CK_ROW)
    push bc
    ld   c, a                     ; c = y
    call GFX_READ_PIXEL            ; destroys AF/BC/DE/HL -- A = 0 or 1
    pop  bc                        ; recover c = expected (b unused after)
    cp   c
    jp   nz, FAIL_TEST

    ld   a, (CK_COL)
    inc  a
    ld   (CK_COL), a
    jr   .colloop
.rownext:
    ld   a, (CK_ROW)
    inc  a
    ld   (CK_ROW), a
    jr   .rowloop
.done:
    ret

; ============================================================================
; CHECK_TOP ( DE = expected -- )  checks the top of the data stack
; WITHOUT popping it (the caller drops separately once done).
; ============================================================================
CHECK_TOP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; PASS_TEST / FAIL_TEST
; ============================================================================
PASS_TEST:
    ld   a, 4                    ; green: all checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, 2                     ; red: something failed
    out  (PORT_ULA), a
    ld   a, (CHECKPOINT_NUM)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_DOT                     ; prints the failing checkpoint number
.hang:
    jr   .hang

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
    ld   hl, BUG_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .hang
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.hang:
    jr   .hang

; ============================================================================
; RUNTIME_ERROR_HOOK -- required unconditionally by core/interp.asm
; (see rom/forth_smoke_p50.asm's own header on this). Nothing in this
; test deliberately throws uncaught, so reaching this at all means a
; real bug in the words under test.
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   a, 7
    out  (PORT_ULA), a
    ld   hl, BUG_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .hang
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.hang:
    jr   .hang

BUG_MSG: DB "BUG", 0

CHECKPOINT_NUM EQU $8900   ; 1 byte: reused scratch -- verified free
                           ; (matches rom/forth_smoke_p50.asm's own
                           ; precedent: core/string.asm/stringext.asm's
                           ; CHR_BUF, which would otherwise land here,
                           ; is not INCLUDEd by this smoke ROM either)
CK_ROW      EQU $8901       ; 1 byte: scratch
CK_COL      EQU $8902       ; 1 byte: scratch
CK_ROWBYTE  EQU $8903       ; 1 byte: scratch

; The "spade" bitmap: a teardrop bulb tapering to a narrow stem with a
; flared base -- the same design used for real UDG slot 0 (character
; code 144) in the Blackjack demo (rom/forth_demo_blackjack.asm).
PATTERN_TABLE:
    DB   %00011000     ; 24
    DB   %00111100     ; 60
    DB   %01111110     ; 126
    DB   %11111111     ; 255
    DB   %11111111     ; 255
    DB   %00111100     ; 60
    DB   %00011000     ; 24
    DB   %00111100     ; 60

SRC_ADDR0:   DB "0 UDG "
SRC_ADDR0_LEN EQU $ - SRC_ADDR0
SRC_ADDR1:   DB "1 UDG "
SRC_ADDR1_LEN EQU $ - SRC_ADDR1
SRC_ADDR20:  DB "20 UDG "
SRC_ADDR20_LEN EQU $ - SRC_ADDR20

SRC_WRITE:   DB "24 0 UDG C! 60 0 UDG 1 + C! 126 0 UDG 2 + C! 255 0 UDG 3 + C! 255 0 UDG 4 + C! 60 0 UDG 5 + C! 24 0 UDG 6 + C! 60 0 UDG 7 + C! "
SRC_WRITE_LEN EQU $ - SRC_WRITE

SRC_READ0:   DB "0 UDG C@ "
SRC_READ0_LEN EQU $ - SRC_READ0
SRC_READ1:   DB "0 UDG 1 + C@ "
SRC_READ1_LEN EQU $ - SRC_READ1
SRC_READ2:   DB "0 UDG 2 + C@ "
SRC_READ2_LEN EQU $ - SRC_READ2
SRC_READ3:   DB "0 UDG 3 + C@ "
SRC_READ3_LEN EQU $ - SRC_READ3
SRC_READ4:   DB "0 UDG 4 + C@ "
SRC_READ4_LEN EQU $ - SRC_READ4
SRC_READ5:   DB "0 UDG 5 + C@ "
SRC_READ5_LEN EQU $ - SRC_READ5
SRC_READ6:   DB "0 UDG 6 + C@ "
SRC_READ6_LEN EQU $ - SRC_READ6
SRC_READ7:   DB "0 UDG 7 + C@ "
SRC_READ7_LEN EQU $ - SRC_READ7

SRC_EMIT:    DB "144 EMIT "
SRC_EMIT_LEN EQU $ - SRC_EMIT

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/udg.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p51_rom0.bin", $0000, $4000
