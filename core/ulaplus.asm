; ============================================================================
; core/ulaplus.asm — Phase 48: ULAPLUS, PALETTE
;
; Builds on core/dict.asm (DPOP_HL) only — no kernel INCLUDE needed,
; pure port I/O.
;
; PORTED FROM 2068-LEAP'S OWN ALREADY-WORKING IMPLEMENTATION
; (~/ts2068rom/basic/basic.asm's BASIC_ULAPLUS_DISABLE and its EXROM
; body), not designed from scratch — same "recover proven, tested
; code" approach Phase 8's mode64 recovery used. The real hardware
; mechanics: ULAPlus is controlled by two 16-bit ports (both already
; declared in include/hardware.inc, inherited unchanged from that same
; project): write a register number to PORT_ULAPLUS_SELECT, then the
; data byte for that register to PORT_ULAPLUS_DATA.
;   - Register 64 (ULAPLUS_MODE_GROUP) is the enable/disable switch —
;     bit 0 of its data byte turns the whole extension on or off.
;   - Registers 0-63 are the palette itself, one GGGRRRBB byte each.
;
; ULAPlus REPLACES THE MEANING OF THE EXISTING ATTRIBUTE COLOR BITS,
; not a separate pixel-setting mechanism — 2068-Leap's own docs state
; this plainly ("A program still uses INK, PAPER, BRIGHT, and FLASH;
; ULAplus changes the [colors those bits map to]"). This is why this
; file adds ONLY these two words: every existing color/graphics word
; in this project (INK, PAPER, PLOT, LINE, CIRCLE, FILL, ...) already
; writes the same attribute bits ULAPlus reinterprets, so nothing else
; needs to change for ULAPlus to take effect once enabled.
;
; TEST-FIDELITY CAVEAT, carried over from this project's own backlog
; (docs/PROJECT_PLAN.md): the real Timex Sinclair 2068 almost
; certainly never had genuine ULAPlus hardware — it's a modern
; retrofit extension designed for later Sinclair-compatible machines,
; unofficially patched into this session's own Fuse build (and
; 2068-Leap's own docs note the same: "Upstream Fuse 1.9.1 does not
; expose ULAplus for the TS2068... requires the optional
; patches/0001-Add-ULAplus-support-for-Timex-machines.patch or
; ZEsarUX"). What CAN be confirmed here is that this project's own
; port writes match the same protocol 2068-Leap's own long-tested BASIC
; implementation uses, and that Fuse's ULAPlus patch visibly responds
; to them (screenshots, this file's own smoke ROM). Whether that
; matches genuine unpatched TS2068/SCLD silicon remains exactly as
; unconfirmed as it was before this phase — building this doesn't
; resolve that, it just gives 2068-Forth the same capability 2068-Leap
; already has under the identical caveat.
;
; WHAT THIS ADDS:
;   ULAPLUS ( flag -- )   nonzero enables the extended palette, zero
;             disables it (reverts to the standard 8-color ULA
;             palette). NO input validation beyond keeping bit 0 of
;             the flag — matching this project's own SOUND/STICK
;             convention, not 2068-Leap's own BASIC-level "INVALID
;             ARGUMENT" error (this project has no such mechanism to
;             raise it through, and THROW/CATCH exists but inventing a
;             new error code for this one word isn't warranted).
;   PALETTE ( index value -- )   writes value (0-255, GGGRRRBB) into
;             palette register index (0-63). Out-of-range index/value
;             pass straight to the hardware ports unguarded, same
;             convention.
; ============================================================================

    IFNDEF CORE_ULAPLUS_ASM
    DEFINE CORE_ULAPLUS_ASM

; ULAPLUS_MODE_GROUP (the mode/enable register's own index, 64) is
; already declared in include/hardware.inc, inherited unchanged from
; 2068-Leap along with the two port constants this file uses.

; ============================================================================
; ULAPLUS ( flag -- )
; ============================================================================
H_ULAPLUS:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this
                            ; file should extend, immediately before
                            ; INCLUDEing this file
    DB   7, "U","L","A","P","L","U","S"
W_ULAPLUS:
    call DPOP_HL             ; hl = flag
    ld   a, ULAPLUS_MODE_GROUP
    ld   bc, PORT_ULAPLUS_SELECT
    out  (c), a
    ld   a, l
    and  1                    ; keep only bit 0 (enable/disable)
    ld   bc, PORT_ULAPLUS_DATA
    out  (c), a
    ret

; ============================================================================
; PALETTE ( index value -- )
; ============================================================================
H_PALETTE:
    DW   H_ULAPLUS
    DB   7, "P","A","L","E","T","T","E"
W_PALETTE:
    call DPOP_HL              ; hl = value
    push hl                    ; stash it on the machine stack -- no
                                ; named scratch needed for two values
                                ; this short-lived
    call DPOP_HL                ; hl = index
    ld   a, l
    ld   bc, PORT_ULAPLUS_SELECT
    out  (c), a
    pop  hl                      ; hl = value, restored
    ld   a, l
    ld   bc, PORT_ULAPLUS_DATA
    out  (c), a
    ret

DICT_LATEST_INIT_ULAPLUS EQU H_PALETTE   ; head of the dictionary once
                                          ; this file's own words are
                                          ; included

    ENDIF
