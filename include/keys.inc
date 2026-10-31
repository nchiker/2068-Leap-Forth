; ============================================================================
; include/keys.inc -- symbolic key/ASCII constants
;
; The keyboard is laid out as the Spectrum's, so the standard CAPS SHIFT + 5/6/7/8/0 cursor
; combos apply. The values come from the control-code range below $20, clear of every printable
; value in KEY_ASCII_TABLE (kernel/io/io.asm) and of KEY_ENTER. kernel/io only reports a key;
; the editor acts on it.
; ============================================================================

    IFNDEF KEYS_INC
    DEFINE KEYS_INC

KEY_ENTER         EQU $0D   ; = LINE_TERMINATOR (kernel/memory/memory.asm)
KEY_CURSOR_LEFT   EQU $01
KEY_CURSOR_DOWN   EQU $02
KEY_CURSOR_UP     EQU $03
KEY_CURSOR_RIGHT  EQU $04
KEY_DELETE        EQU $08   ; CAPS SHIFT + 0 (ASCII backspace)
KEY_INSERT_LINE   EQU $0B   ; CAPS SHIFT + ENTER: insert a blank statement before the current one
KEY_NEXT_ERROR    EQU $0C   ; SYMBOL SHIFT + A: jump to the next flagged statement (SYMBOL SHIFT
                            ; row 1 is otherwise unmapped, see kernel/io)
KEY_PREV_ERROR    EQU $0E   ; SYMBOL SHIFT + S: the previous one
KEY_DELETE_LINE   EQU $0F   ; CAPS SHIFT + 1: delete the whole current line (KEY_DELETE only
                            ; does that once the line's buffer is empty)
KEY_BREAK         EQU $10   ; CAPS SHIFT + SPACE (row 7, bit 0): the standard Spectrum BREAK combo

    ENDIF
