; ============================================================================
; core/ulaplus.asm -- ULAPLUS and PALETTE: the ULAplus palette
;
; ULAplus is set through two ports (include/hardware.inc): write a register number to
; PORT_ULAPLUS_SELECT, then its data byte to PORT_ULAPLUS_DATA. Register 64 (ULAPLUS_MODE_GROUP) bit 0
; switches the extension on or off; registers 0-63 are the palette, one GGGRRRBB byte each. ULAplus
; reinterprets the attribute bits INK, PAPER, BRIGHT and FLASH already write, so no other word changes.
; Neither word validates its arguments: an out-of-range index or value goes to the ports as it is.
; ULAplus is a later retrofit; a stock TS2068 almost certainly lacks it (the emulator patches provide it).
; Needs core/dict.asm only. Chained from DICT_CHAIN_POINT (set by the including ROM before the
; INCLUDE); every word may destroy all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_ULAPLUS_ASM
    DEFINE CORE_ULAPLUS_ASM

; ============================================================================
; ULAPLUS ( flag -- ) -- enable the extended palette if bit 0 of flag is set, else disable it
; ============================================================================
H_ULAPLUS:
    DW   DICT_CHAIN_POINT
    DB   7, "U","L","A","P","L","U","S"
W_ULAPLUS:
    rst RST_DPOP            ; hl = flag
    ld   a, ULAPLUS_MODE_GROUP
    ld   bc, PORT_ULAPLUS_SELECT
    out  (c), a
    ld   a, l
    and  1                    ; keep only bit 0 (enable/disable)
    ld   bc, PORT_ULAPLUS_DATA
    out  (c), a
    ret

; ============================================================================
; PALETTE ( index value -- ) -- write value (GGGRRRBB) to palette register index (0-63)
; ============================================================================
H_PALETTE:
    DW   H_ULAPLUS
    DB   7, "P","A","L","E","T","T","E"
W_PALETTE:
    rst RST_DPOP             ; hl = value
    push hl                    ; kept on the machine stack
    rst RST_DPOP               ; hl = index
    ld   a, l
    ld   bc, PORT_ULAPLUS_SELECT
    out  (c), a
    pop  hl                      ; hl = value
    ld   a, l
    ld   bc, PORT_ULAPLUS_DATA
    out  (c), a
    ret

DICT_LATEST_INIT_ULAPLUS EQU H_PALETTE

    ENDIF
