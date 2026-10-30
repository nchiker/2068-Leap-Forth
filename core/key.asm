; ============================================================================
; core/key.asm -- KEY, KEY?, BREAK?: keyboard input
;
; Needs kernel/io/io.asm. KEY blocks until IO_READ_KEY returns a key that the IM 1 keyboard interrupt
; (RST $0038 -> KBD_ISR_TICK) has latched, so the interrupt must be running. KEY returns the code as
; decoded (ASCII, or KEY_CURSOR_* / KEY_DELETE etc.); there is no case folding.
; Chained from DICT_CHAIN_POINT (set by the including ROM before the INCLUDE); every word may destroy
; all registers except IX (the data stack pointer), IY and SP.
; ============================================================================

    IFNDEF CORE_KEY_ASM
    DEFINE CORE_KEY_ASM

; ============================================================================
; KEY ( -- char ) -- wait for a key and push its code
; ============================================================================
H_KEY:
    DW   DICT_CHAIN_POINT
    DB   3, "K", "E", "Y"
W_KEY:
    call IO_READ_KEY
    ld   l, a
    ld   h, 0
    rst RST_DPUSH
    ret

DICT_LATEST_INIT_KEY EQU H_KEY   ; the chain head with KEY alone, not this file's head

; ============================================================================
; KEY? ( -- flag ) -- true (-1) if a key is waiting; the key is not consumed, so KEY? IF KEY ... THEN works
; ============================================================================
H_KEYQ:
    DW   H_KEY
    DB   4, "K", "E", "Y", "?"
W_KEYQ:
    call IO_KEY_AVAILABLE
    or   a
    jr   z, .false
    ld   hl, -1
    rst RST_DPUSH
    ret
.false:
    ld   hl, 0
    rst RST_DPUSH
    ret

; ============================================================================
; BREAK? ( -- flag ) -- true (-1) while CAPS SHIFT+SPACE is held
; It scans the keyboard matrix itself, so it neither uses nor disturbs the key KEY? and KEY see.
; ============================================================================
H_BREAKQ:
    DW   H_KEYQ
    DB   6, "B", "R", "E", "A", "K", "?"
W_BREAKQ:
    call IO_CHECK_BREAK
    ld   hl, 0
    jr   nc, .push
    ld   hl, -1
.push:
    rst RST_DPUSH
    ret

DICT_LATEST_INIT_KEYQ EQU H_BREAKQ

    ENDIF
