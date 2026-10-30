; ============================================================================
; include/hardware.inc -- symbolic constants for the TS2068 hardware
;
; Every module includes this instead of hard-coding ports and addresses.
; ============================================================================

    IFNDEF HARDWARE_INC
    DEFINE HARDWARE_INC

; ---- ULA / display ----
PORT_ULA            EQU $FE     ; border/EAR/MIC, keyboard read (Spectrum-compatible)

PORT_ULAPLUS_SELECT EQU $BF3B   ; ULAplus register select (16-bit port)
PORT_ULAPLUS_DATA   EQU $FF3B   ; ULAplus register data (16-bit port)
ULAPLUS_MODE_GROUP EQU 64       ; bit 0 enables the standard palette

; ---- AY-3-8912 sound (TS2068 port pair) ----
PORT_AY_REG         EQU $F5     ; select AY register
PORT_AY_DATA        EQU $F6     ; write/read AY register data

; ---- TS2068 banking (Home / Exrom / Dock) ----
; Horizontal Select Register: one bit per 8K chunk of the 64K address space (chunk N =
; N * $2000; A13-A15 decode). 0 = the chunk comes from Home, 1 = from the alternate bank that
; PORT_SCLD bit 7 selects (EXROM or Dock). Only chunk 5 ($A000-$BFFF) is ever paged; the only
; writers are BANK_PAGE_EXROM_IN/OUT (kernel/bank/bank.asm).
PORT_BANK_HOME      EQU $F4

; ---- SCLD Display Enhancement Control (port $FF) ----
; A shared register: bits 0-2 select the video mode, bit 6 is INTEN, bit 7 selects Extension
; ROM vs. cartridge for the chunks PORT_BANK_HOME marks "not Home". Its writers (GFX_SET_MODE,
; BANK_PAGE_EXROM_IN) go through PORT_FF_SHADOW (include/forth_layout.inc) and never OUT
; directly, so one caller's bits are not zeroed by the other's. Mode values written: 0 =
; Normal, 2 = High Resolution Graphics. Bits 3-5 (64-column ink/paper) are never written.
PORT_SCLD           EQU $FF

; ---- Screen geometry ----
SCREEN_ADDR         EQU $4000
ATTR_ADDR           EQU $5800
SCREEN_WIDTH_CHARS  EQU 32
SCREEN_HEIGHT_CHARS EQU 24

; ZX Printer / TS2040 printer port (bit meanings: core/printer.asm)
PORT_PRINTER        EQU $FB

    ENDIF
