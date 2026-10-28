; ============================================================================
; core/soundext.asm — Phase 63: TONE, VOLUME, MIXER, NOISE, ENVELOPE
; (a channel-aware convenience layer over the raw AY-3-8912 register
; access core/sound.asm's own SOUND already provides)
;
; Builds on core/sound.asm (must be INCLUDEd first, with
; DICT_CHAIN_POINT left set to H_SOUND right before this file's own
; INCLUDE line — same chain-continuation convention as every other
; file in this project) and core/dict.asm/core/interp.asm (for
; DPOP_HL). Needs only include/hardware.inc (PORT_AY_REG/
; PORT_AY_DATA), like core/sound.asm itself.
;
; KEPT IN ITS OWN FILE, SEPARATE FROM core/sound.asm, deliberately:
; rom/forth_smoke_p52.asm's own embedded Blackjack test payload calls
; `SOUND` directly (several times) but none of the five words here —
; and that one ROM was already down to a single byte of headroom
; before this phase existed (see its own header). Folding these words
; into core/sound.asm itself would have forced every ROM that only
; ever needed `SOUND` to also pay for a whole convenience layer on top
; it never calls — exactly the situation core/floatmul.asm and core/
; floatdiv.asm already avoid by staying split from core/float.asm
; rather than folded in. rom/forth_smoke_p52.asm's own INCLUDE list
; stops at core/sound.asm; every ROM that wants the full layer
; (rom/forth_boot.asm, rom/forth_demo_blackjack.asm, and this phase's
; own rom/forth_smoke_p63.asm) INCLUDEs this file right after it.
;
; WHAT THIS ADDS: `TONE`/`VOLUME`/`MIXER`/`NOISE`/`ENVELOPE`, added
; directly (not derived) after the user asked whether raw register
; access "could be expanded to take better advantage of the
; hardware." Each of these five is a plain, mechanical wrapper around
; the AY-3-8912's own well-documented register map — no new design, no
; note/frequency tables, no sequencing: they're strictly shorthand for
; register writes `SOUND` could already do by hand. What they buy you:
; every caller of `SOUND` otherwise has to remember the fine/coarse
; split, which channel maps to which register pair, and which bits in a
; given register mean what. These don't.
;
; NOT a shared internal routine with SOUND_WRITE, deliberately: that
; routine's numbering is `SOUND`'s own, a straight port of the real BASIC
; ROM's command (0-16 since step R0; it rejected 0 before, see core/
; sound.asm's own header). Wrapper words that need genuine full-register
; reach route through their own native 0-15 AY_WRITE instead — matching
; the sibling `~/ts2068rom` project's own precedent: it keeps the
; identical two-layer split, its BASIC-compatible `SOUND_EXROM` alongside
; a separate native-numbered `AYREG` extension (0-15,
; rom/extensions/ayreg.asm).
;
; AY-3-8912 register map used below (standard for this chip, not
; project-specific): 0/1 = Channel A tone period fine/coarse, 2/3 =
; Channel B, 4/5 = Channel C (only the low 4 bits of an odd/coarse
; register are significant — the chip ignores the rest); 6 = noise
; period (low 5 bits significant); 7 = mixer/enable (see MIXER's own
; header below for the bit layout); 8/9/10 = Channel A/B/C amplitude
; (low 4 bits = fixed volume 0-15, bit 4 = route this channel through
; the shared envelope generator instead — VOLUME below always clears
; that bit; see ENVELOPE's own header for why); 11/12 = envelope
; period fine/coarse (a full 16-bit value, unlike a tone period); 13 =
; envelope shape (low 4 bits significant).
;
; SAME OUT-OF-RANGE CONVENTION AS SOUND_WRITE: an out-of-range channel
; is silently ignored (nothing written to either AY port), matching
; this project's established "no general error-reporting mechanism"
; scope decision (see core/sound.asm's own header). Channel validation
; only inspects the low byte of the popped cell, same lightweight
; convention `BRIGHT`/`FLASH`'s own `and $01` uses for their own
; single-bit inputs — not exhaustive 16-bit range checking.
; ============================================================================

    IFNDEF CORE_SOUNDEXT_ASM
    DEFINE CORE_SOUNDEXT_ASM

; ============================================================================
; AY_WRITE (internal, not a dictionary word) — B = native AY-3-8912
; register (0-15), C = data (0-255). Silently does nothing if the
; register is out of range. Destroys: AF
; ============================================================================
AY_WRITE:
    ld   a, b
    cp   16
    ret  nc                   ; register >=16 -- out of range, ignore
    out  (PORT_AY_REG), a
    ld   a, c
    out  (PORT_AY_DATA), a
    ret

; ============================================================================
; TONE ( channel period -- )
; channel: 0=A, 1=B, 2=C. period: a 12-bit tone period (0-4095) --
; fine byte to register channel*2, coarse nibble (period's top 4 bits
; only -- the rest of that register is meaningless on real hardware,
; masked off here rather than left to chance) to register channel*2+1.
; Reaches chip register 0 (Channel A's tone-period fine byte) for any
; channel by number.
; ============================================================================
H_TONE:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to H_SOUND, immediately before
                            ; INCLUDEing this file
    DB   4, "T", "O", "N", "E"
W_TONE:
    call DPOP_HL               ; hl = period
    ld   a, h
    and  $0F                   ; coarse nibble -- top 4 bits of the
                                ; register are unused on real hardware
    ld   d, a
    ld   e, l                  ; e = fine byte
    call DPOP_HL               ; hl = channel
    ld   a, l
    cp   3
    ret  nc                    ; channel not 0-2 -- ignore
    add  a, a                  ; a = channel*2 = fine-period register
    ld   b, a
    ld   c, e
    call AY_WRITE
    inc  b                     ; b = channel*2+1 = coarse-period register
    ld   c, d
    call AY_WRITE
    ret

; ============================================================================
; VOLUME ( channel level -- )
; channel: 0=A, 1=B, 2=C. level: 0-15 (only the low 4 bits of the
; popped cell are used). Always sets a FIXED volume -- bit 4 of the
; amplitude register (the "use the shared envelope generator instead"
; bit) is unconditionally cleared, so VOLUME can never leave a channel
; in envelope mode. Routing a channel through the envelope generator
; needs that bit set directly; ENVELOPE's own header below explains
; why that isn't wrapped here.
; ============================================================================
H_VOLUME:
    DW   H_TONE
    DB   6, "V", "O", "L", "U", "M", "E"
W_VOLUME:
    call DPOP_HL               ; hl = level
    ld   a, l
    and  $0F
    ld   c, a
    call DPOP_HL               ; hl = channel
    ld   a, l
    cp   3
    ret  nc                    ; channel not 0-2 -- ignore
    add  a, 8                  ; channel 0/1/2 -> register 8/9/10
    ld   b, a
    call AY_WRITE
    ret

; ============================================================================
; MIXER ( mask -- )
; A direct, unmodified write to register 7 -- the AY-3-8912's own
; mixer/enable register, ACTIVE LOW: bit=0 enables that source, bit=1
; disables it. Bits 0-2 = tone A/B/C enable, bits 3-5 = noise A/B/C
; enable, bits 6-7 = I/O port A/B direction (not sound-related; left
; alone by every other word here). No friendlier translation is
; applied -- this is the one register among these five where the
; project's own established preference for staying faithful to real
; hardware semantics (see core/sound.asm's own header: no offset
; applied even though one might read as friendlier) matters most,
; since inverting the bits here would silently disagree with every
; reference this chip has ever been documented against. Confirmed
; working exactly this way already: core/sound.asm's own SOUND header
; cites `7 253 SOUND` (mask $FD, only Channel B's tone enabled) as
; part of the user's own live, audible tone confirmation.
; ============================================================================
H_MIXER:
    DW   H_VOLUME
    DB   5, "M", "I", "X", "E", "R"
W_MIXER:
    call DPOP_HL                ; hl = mask
    ld   c, l
    ld   b, 7
    call AY_WRITE
    ret

; ============================================================================
; NOISE ( period -- )
; A direct write to register 6 (the single shared noise generator's
; own period), masked to the low 5 bits -- the only bits significant
; on real hardware. Still needs MIXER to route noise onto a channel
; (bits 3-5) before anything audible happens, same "several
; coordinated writes" reality SOUND's own header already documents for
; a clean tone.
; ============================================================================
H_NOISE:
    DW   H_MIXER
    DB   5, "N", "O", "I", "S", "E"
W_NOISE:
    call DPOP_HL                ; hl = period
    ld   a, l
    and  $1F
    ld   c, a
    ld   b, 6
    call AY_WRITE
    ret

; ============================================================================
; ENVELOPE ( period shape -- )
; period: a full 16-bit envelope period (registers 11 fine/12 coarse
; -- unlike a tone period, BOTH bytes are fully significant, no
; masking). shape: 0-15 (register 13, low 4 bits only) -- the AY-
; 3-8912's own four shape-control bits (continue/attack/alternate/
; hold); this word passes the value straight through rather than
; naming the eight resulting envelope curves, matching MIXER's own
; "faithful to the real register, not reinvented" choice above.
;
; DELIBERATELY DOES NOT ROUTE ANY CHANNEL THROUGH THIS ENVELOPE:
; on real AY-3-8912 hardware, there is exactly one shared envelope
; generator, and a channel only uses it if bit 4 of THAT channel's own
; amplitude register (8/9/10) is set -- VOLUME above always clears
; that same bit (fixed-volume mode), so ENVELOPE alone produces no
; audible change by itself. Setting bit 4 needs a raw register write
; this convenience layer doesn't offer, e.g. `8 16 SOUND` (register 8
; = Channel A's amplitude register, data 16 = $10 = bit 4 set, volume
; nibble 0) after calling ENVELOPE -- the same kind of "several
; coordinated writes, by hand" reality SOUND's own header already
; documents for a clean tone, not hidden here either.
; ============================================================================
H_ENVELOPE:
    DW   H_NOISE
    DB   8, "E", "N", "V", "E", "L", "O", "P", "E"
W_ENVELOPE:
    call DPOP_HL                ; hl = shape
    ld   a, l
    and  $0F
    ld   e, a                   ; e = shape byte -- survives the next
                                ; DPOP_HL (only IX/HL touched there)
                                ; and the AY_WRITE calls below (only AF)
    call DPOP_HL                 ; hl = period
    ld   b, 11
    ld   c, l                    ; fine byte
    call AY_WRITE
    ld   b, 12
    ld   c, h                    ; coarse byte -- full 8 bits significant
    call AY_WRITE
    ld   b, 13
    ld   c, e
    call AY_WRITE
    ret

DICT_LATEST_INIT_SOUNDEXT EQU H_ENVELOPE   ; head of the dictionary
                                           ; once this file's own words
                                           ; are all included

    ENDIF
