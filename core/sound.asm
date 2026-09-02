; ============================================================================
; core/sound.asm — Phase 32: SOUND (real AY-3-8912 register access)
;
; Builds on core/dict.asm and core/interp.asm (both must be INCLUDEd
; first — chains its own dictionary entry onto whatever
; DICT_CHAIN_POINT the including ROM sets). Needs only
; include/hardware.inc (PORT_AY_REG/PORT_AY_DATA), already INCLUDEd by
; every ROM in this project before `DEVICE`/`ORG $0000` — no kernel/
; dependency at all, unlike BEEP.
;
; WHAT THIS ADDS: `SOUND ( register data -- )`, the AUTHENTIC
; register-level AY-3-8912 command — tracked since the original
; BASIC-gap audit as its own future phase (docs/PROJECT_PLAN.md, "AY-
; 3-8912 SOUND (real register-level sound access, distinct from the
; existing simple BEEP... never ported here)"), and DISTINCT from
; core/beep.asm's own musical-note `BEEP`: `SOUND` writes whatever byte
; you give it directly into a PSG register — tone period, volume,
; envelope shape, noise, mixer routing, any of the chip's 16 registers
; — not a computed note. Confirmed directly from the real TS2068 ROM
; disassembly's own `SOUND` routine (also independently confirmed
; already working in the sibling `~/ts2068rom` BASIC project's own
; `rom/exrom_sound.asm`, ported from the SAME disassembly source): the
; register number is written to port `$F5` (`PORT_AY_REG`) UNCHANGED —
; no subtraction, confirmed both from the real ROM disassembly's own
; `SOUND` routine (M2127: `OUT ($F5),A` uses the register value
; straight off the calculator stack, no `DEC A` before the `OUT`) and
; from the sibling project's own already-verified `SOUND_EXROM`, which
; matches — and the data byte to port `$F6` (`PORT_AY_DATA`). The real
; ROM validates the register to 1-16 inclusive (0 and 17+ both
; rejected). A real, worth-stating consequence of NO offset existing:
; the AY-3-8912 only has chip registers 0-15, so `SOUND`'s own valid
; range (1-16) can never reach chip register 0 (Channel A's tone-period
; FINE byte) at all — only its coarse byte (chip register 1) is
; reachable for that specific channel/field; every other register,
; including both halves of Channel B/C's own tone periods (chip
; registers 2-5), is fully reachable. Channel A can still be used for
; fine-grained tones by way of registers 2-5 belonging to B/C instead.
;
; ERROR HANDLING: the real ROM raises a genuine BASIC error
; ("INVALID SOUND REGISTER") for an out-of-range register — this
; project has no general error-reporting mechanism yet (every other
; word with an out-of-range input, e.g. `SOUND_BEEP`'s own zero-
; duration case or `MATH_UDIV16`'s divide-by-zero, silently no-ops on
; bad input instead of raising anything), so `SOUND` follows the SAME
; established convention here: an out-of-range register is silently
; ignored — nothing is written to EITHER port, not even a wrong
; register selection — rather than inventing a one-off error scheme
; for this single word.
;
; NOT REPLICATED: the real ROM's own `SOUND` also accepts a semicolon-
; chained list of register,data pairs on one line
; (`SOUND 8,15;0,200;...`) — not implemented, matching
; core/rawbeep.asm's own header note on the same scope cut (this
; dialect's `:`  statement separator already gives the same effect,
; `8 15 SOUND 0 200 SOUND`, and semicolon isn't recognized syntax
; anywhere else here).
;
; AUTOMATED VERIFICATION LIMIT, STATED HONESTLY: like `BEEP`, there is
; no way for a smoke ROM's own border-color pass/fail signal to confirm
; the AY-3-8912 chip actually PRODUCES the requested sound — this
; project's own `hardware_notes.md` (inherited from the sibling
; ts2068rom project) marks the AY port pair's own read-back behavior as
; "still open," unconfirmed even there. `rom/forth_smoke_p32.asm`
; verifies the same way the sibling project verified its own `SOUND`:
; valid register/data pairs (1-16) run to completion without hanging,
; and a sentinel value on the data stack survives a call untouched
; (proving `SOUND` consumes exactly its own two arguments and nothing
; else) — the same data-stack-hygiene proof shape `core/rawbeep.asm`'s
; own original `BEEP` checkpoint used. Unlike `BORDER`/`BEEP`, this
; project keeps no software shadow of the AY ports, so there is nothing
; else to check for the out-of-range (silently-ignored) case beyond
; that same stack-hygiene proof.
;
; REAL AUDIO CONFIRMED, LIVE, BY THE USER (something no automated
; check in this project can do) — and it took a real, corrected
; understanding of the AY chip to get there. The first live attempt
; (`8 15 SOUND` alone — the real ROM's own documented example, and this
; file's own original smoke-test choice) produced audible STATIC, not a
; tone. Not a bug in `SOUND` itself: register 8 only sets Channel A's
; volume — with the mixer register (7) and a tone period left at
; whatever the emulator's own AY starts them at, the chip has no reason
; to output a clean tone at all (most likely: noise routed to that
; channel, or a tone period near zero). A clean tone needs THREE
; coordinated writes, not one: a tone period, the mixer enabling that
; channel's tone (and disabling everything else), and the volume. Using
; Channel B specifically (its own tone-period registers, 2 and 3, are
; both directly reachable — Channel A's own fine-period register, chip
; register 0, never is; see this file's own note above) with the
; TS2068's own real AY clock (1,764,000 Hz — `libspectrum`'s own
; `timings.c`, the SAME source `core/beep.asm`'s own header already
; cites for the CPU clock) and the standard `period = clock/(16*freq)`
; formula for a ~439 Hz tone (period 251 — an exact fit is impossible,
; the period register is an integer):
;   2 251 SOUND   ( Channel B tone period, fine byte )
;   3   0 SOUND   ( Channel B tone period, coarse byte )
;   7 253 SOUND   ( mixer: only Channel B's tone enabled, everything
;                   else — both other tones, all three noise
;                   generators — disabled: $FF with bit 1 cleared )
;   9  15 SOUND   ( Channel B volume, fixed, maximum )
; Confirmed by the user, live, over real speakers: a real, steady,
; recognizable tone — not static, and not silence. To stop it:
; `9 0 SOUND` (volume back to zero; the AY holds its register state
; indefinitely, unlike `BEEP`'s own fixed-duration, self-terminating
; loop — nothing else stops a `SOUND`-driven tone automatically).
; ============================================================================

    IFNDEF CORE_SOUND_ASM
    DEFINE CORE_SOUND_ASM

; ============================================================================
; SOUND_WRITE (internal, not a dictionary word) — B = register (1-16),
; C = data (0-255). Silently does nothing if the register is out of
; range (see this file's own header on why silent, not an error).
; Destroys: AF
; ============================================================================
SOUND_WRITE:
    ld   a, b
    or   a
    ret  z                    ; register 0 -- out of range, ignore
    cp   17
    ret  nc                   ; register >=17 -- out of range, ignore
    out  (PORT_AY_REG), a
    ld   a, c
    out  (PORT_AY_DATA), a
    ret

; ============================================================================
; SOUND ( register data -- )
; ============================================================================
H_SOUND:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   5, "S", "O", "U", "N", "D"
W_SOUND:
    call DPOP_HL           ; hl = data
    ld   c, l
    call DPOP_HL           ; hl = register
    ld   b, l
    call SOUND_WRITE
    ret

DICT_LATEST_INIT_SOUND EQU H_SOUND   ; head of the dictionary once this
                                      ; file's own word is included

    ENDIF
