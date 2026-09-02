; ============================================================================
; core/stick.asm — Phase 37: STICK (joystick read)
;
; Builds on core/dict.asm (DPOP_HL/DPUSH_HL) and needs kernel/io/io.asm
; INCLUDEd alongside it, for its own STICK_READ (both must be INCLUDEd
; first — this file's own first header chains through DICT_CHAIN_POINT).
;
; WHAT THIS ADDS: STICK ( device -- value ), the real ROM's own
; joystick-read command — flagged in the fresh three-way audit against
; the sibling 2068-Leap BASIC project and the real TS2068 ROM's own
; command set as missing here, but genuinely CHEAP to add: unlike
; KEY?/CLS before this phase, the underlying kernel routine
; (`kernel/io/io.asm`'s own `STICK_READ`) was already ported from the
; real ROM disassembly's own READ-STICK routine — confirmed hardware
; behavior, including the real asymmetry between the two devices
; (device 1 reports a full 4-bit direction nibble; device 2 reports
; only a single bit) — and simply never had a dictionary word wrapping
; it. This file adds nothing new to the joystick-reading logic itself,
; only the thin Forth-visible wrapper.
;
; NO INPUT VALIDATION, matching STICK_READ's own stated contract ("the
; caller's own job to validate; this routine trusts it") and this
; project's established no-error-mechanism convention (see
; core/sound.asm's own header for the same posture stated explicitly):
; a device value other than 1 or 2 is passed straight through to real
; hardware with whatever result that produces — not guarded against,
; not silently rejected, exactly as candid about that as `SOUND`'s own
; out-of-range register handling.
; ============================================================================

    IFNDEF CORE_STICK_ASM
    DEFINE CORE_STICK_ASM

; ============================================================================
; STICK ( device -- value )  device is 1 or 2; value is 0-15 for
; device 1 (one bit per direction), 0 or 1 for device 2 — see
; kernel/io/io.asm's own STICK_READ header for the exact bit meanings.
; ============================================================================
H_STICK:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "S", "T", "I", "C", "K"
W_STICK:
    call DPOP_HL           ; hl = device
    call STICK_READ        ; hl = value
    call DPUSH_HL
    ret

DICT_LATEST_INIT_STICK EQU H_STICK   ; head of the dictionary once this
                                       ; file's own word is included

    ENDIF
