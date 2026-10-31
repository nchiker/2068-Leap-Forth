; ============================================================================
; kernel/interrupt/interrupt.asm -- the IM 1 handler: frame counter and keyboard scan/debounce/repeat
;
; KBD_ISR_INIT is called once from COLD_START before EI; KBD_ISR_TICK runs from RST_38 on every
; frame interrupt (50 or 60 Hz) whatever the foreground is doing. It scans the matrix
; (IO_KEY_SCAN_ALL), then tracks ONE key: while a key is tracked only that key is checked
; (IO_KEY_STILL_DOWN), so a second key going down alongside it (two-key rollover) cannot reset its
; debounce; only when nothing is tracked does IO_FIND_KEY search for a new one. A new key must hold
; for KBD_DEBOUNCE_TICKS ticks before it is decoded (IO_DECODE_KEY) and latched into
; KBD_LASTK/KBD_KEYHIT; held further, it repeats after KBD_REPDEL ticks and then every KBD_REPPER.
; The state is KBD_CUR_ROW/KBD_CUR_BIT/KBD_DEBOUNCE/KBD_REPEAT (include/forth_layout.inc).
;
; The tick constants assume the ULA's frame interrupt rate. A latched key not yet consumed is
; overwritten by the next (one slot, no queue).
; ============================================================================

    INCLUDE "include/hardware.inc"
    INCLUDE "include/keys.inc"

KBD_DEBOUNCE_TICKS   EQU 2    ; ticks a new key must hold before it is accepted. Short on purpose: the
                              ;   shift state is decoded fresh at acceptance (IO_DECODE_KEY), so no
                              ;   settle window is needed, and a membrane's bounce ends within a tick
KBD_REPDEL           EQU 35   ; ticks held before auto-repeat starts (the stock ROM's REPDEL, $23)
KBD_REPPER           EQU 5    ; ticks between repeats after that (the stock ROM's REPPER)

; ============================================================================
; KBD_ISR_INIT -- clear the keyboard state: nothing latched, nothing tracked
; Power-on RAM cannot be trusted to be zero; KBD_CUR_ROW = $FF (not 0) means no key is tracked.
; In:  none
; Out: none
; Destroys: AF
; ============================================================================
KBD_ISR_INIT:
    xor  a
    ld   (KBD_LASTK), a
    ld   (KBD_KEYHIT), a
    ld   (KBD_CUR_BIT), a
    ld   (KBD_DEBOUNCE), a
    ld   (KBD_REPEAT), a
    ld   a, $FF
    ld   (KBD_CUR_ROW), a           ; $FF = no key currently tracked
    ret

; ============================================================================
; KBD_ISR_TICK -- one interrupt: count the frame, scan the keyboard, run the debounce/repeat machine
; Per tick: nothing tracked -> IO_FIND_KEY; a key found starts tracking (KBD_DEBOUNCE counts down
; from KBD_DEBOUNCE_TICKS - 1). Tracked -> only that key is tested: still down continues the
; debounce or repeat; released clears the tracking and looks for a new key in the same tick.
; In:  none
; Out: FRAMES + 1; KBD_LASTK/KBD_KEYHIT set when a key is accepted or repeats
; Destroys: none (all registers preserved)
; ============================================================================
KBD_ISR_TICK:
    push af
    push bc
    push de
    push hl

    ld   hl, (FRAMES)                  ; every interrupt counts once, before any early exit
    inc  hl
    ld   (FRAMES), hl

    call IO_KEY_SCAN_ALL

    ld   a, (KBD_CUR_ROW)
    cp   $FF
    jr   z, .look_for_new           ; nothing currently tracked

    ; something is tracked: test only that key
    ld   b, a
    ld   a, (KBD_CUR_BIT)
    ld   c, a
    call IO_KEY_STILL_DOWN
    jr   c, .still_down

    ; released: stop tracking, look for a replacement this same tick
    ld   a, $FF
    ld   (KBD_CUR_ROW), a

.look_for_new:
    call IO_FIND_KEY
    jr   nc, .done                  ; nothing new (or ambiguous) found
    jr   .new_key                   ; B = row, C = bit

.still_down:
    ld   a, (KBD_DEBOUNCE)
    or   a
    jr   z, .already_accepted

    dec  a
    ld   (KBD_DEBOUNCE), a
    jr   nz, .done                    ; not time to accept yet

    ; debounce reached 0: accept and latch, start the repeat timer
    call IO_DECODE_KEY
    ld   (KBD_LASTK), a
    ld   a, $FF
    ld   (KBD_KEYHIT), a
    ld   a, KBD_REPDEL
    ld   (KBD_REPEAT), a
    jr   .done

.already_accepted:
    ld   a, (KBD_REPEAT)
    dec  a
    ld   (KBD_REPEAT), a
    jr   nz, .done

    ; repeat fires
    call IO_DECODE_KEY
    ld   (KBD_LASTK), a
    ld   a, $FF
    ld   (KBD_KEYHIT), a
    ld   a, KBD_REPPER
    ld   (KBD_REPEAT), a
    jr   .done

.new_key:
    ld   a, b
    ld   (KBD_CUR_ROW), a
    ld   a, c
    ld   (KBD_CUR_BIT), a
    ld   a, KBD_DEBOUNCE_TICKS - 1     ; this tick is the first sighting: N - 1 more ticks make N
    ld   (KBD_DEBOUNCE), a
    ; KBD_REPEAT is only read after the debounce reaches 0, which sets it: not touched here

.done:
    pop  hl
    pop  de
    pop  bc
    pop  af
    ret

