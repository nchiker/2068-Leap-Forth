; ============================================================================
; core/beep.asm — real, semitone/seconds BEEP
;
; Builds on core/dict.asm, core/interp.asm, core/float.asm (FPUSH/FPOP/
; F_SHRA), core/floatmul.asm (W_FSTAR), and core/floatdiv.asm
; (W_FSLASH, F_UDIV32BY16, and its F_DIVID_HI/F_DIVID_LO/F_PROD_HI/
; F_PROD_LO scratch — see BEEP_COMPUTE's own comment for why the final
; pitch_param step is plain 32-bit integer arithmetic, not float) — all
; must be INCLUDEd first, chaining through DICT_CHAIN_POINT the same
; way every other float file has. Also needs kernel/sound/sound.asm
; (SOUND_BEEP). No dependency on core/floattrig.asm's own code, but
; this file is wired in right after it in rom/forth_boot.asm's own
; chain, purely for phase ordering.
;
; WHY THIS EXISTS: core/ts2068.asm's original BEEP (Phase 5) exposed
; kernel/sound's own SOUND_BEEP mechanism directly — raw per-half-cycle
; busy-wait counts and raw waveform-cycle counts, not musical units.
; The user asked directly why 2068-Forth's BEEP doesn't behave like the
; real 2068's, then asked for a real attempt. THIS file is that
; attempt: `BEEP ( n-semitones fduration -- )` takes an INTEGER
; semitone number (0 = middle C, matching the well-documented Sinclair
; BASIC convention) on the DATA stack and a REAL duration in SECONDS on
; the FLOAT stack — the same units the real command uses, not
; kernel/sound's own raw ones. The original word is preserved,
; unchanged, as core/rawbeep.asm (see its own header) purely for
; rom/forth_smoke_p5.asm's historical checkpoint — this file replaces
; it under the same name everywhere else, starting with
; rom/forth_boot.asm.
;
; THE REAL ROM'S OWN ALGORITHM (confirmed directly from the actual
; Timex Sinclair 2068 ROM disassembly, "Beeper Subroutine" and "BEEP
; Command Routine" sections, not guessed or half-remembered):
;   1. Split the semitone pitch number into a note-within-octave (0-11)
;      and an octave count, via a repeated-subtract-12 loop starting 6
;      octaves below middle C.
;   2. Look the note up in a 12-entry table of frequency RATIOS for one
;      octave (relative to middle C), multiply, then apply the octave
;      count as a DIRECT SHIFT of the resulting float's own exponent
;      field — exact, no rounding, the classic "multiply by 2^N is just
;      add N to the exponent" trick, not a real multiplication.
;   3. Convert the resulting frequency into a hardware timing PERIOD via
;      `437500/f - 30.125`, and the duration into a CYCLE COUNT via
;      `f * duration`.
;   4. Hand both integers to the real BEEPER routine.
;
; THIS FILE REPLICATES STEPS 1-2 (the genuinely reusable, ROM-agnostic
; musical math) EXACTLY, including the same "0 = middle C, 12 units per
; octave" convention and the same octave-via-exponent-shift trick. Step
; 3's own constants (437500, 30.125) are SPECIFIC to the real ROM's own
; BEEPER timing loop (a self-modifying IX-relative NOP sled — see that
; disassembly section's own header: "HL contains the waveform period
; (8*HL+236 to 8*HL+246 t-states)") — kernel/sound's own SOUND_BEEP is a
; STRUCTURALLY DIFFERENT loop (plain DEC-BC countdown, no NOP sled), so
; reusing the real ROM's constants unchanged on a different loop shape
; would silently produce the WRONG frequency while looking authentic.
; Instead, THIS file's own step 3 is calibrated from first principles
; against SOUND_BEEP's own actual instructions:
;
;   SOUND_BEEP's .half_cycle body (kernel/sound/sound.asm) is a fixed
;   76 T-states (LD A,(nn) 13 + XOR n 7 + OR n 7 + LD (nn),A 13 +
;   OUT (n),A 11 + PUSH IX 15 + POP BC 10) before its own .delay loop
;   (DEC BC 6 + LD A,B 4 + OR C 4 + JR NZ 12-taken/7-not-taken, run
;   `pitch` times: 26*pitch-5 T-states total) plus a final RET (10) and
;   the CALL that reaches it (17) — total 98+26*pitch T-states per
;   half-cycle, charged at the call site. Two half-cycles plus the
;   outer .cycle loop's own overhead (DEC DE 6 + LD A,D 4 + OR E 4 +
;   JR NZ 12) gives 222+52*pitch T-states per full waveform cycle — all
;   standard, published Z80 instruction timings, not measured or
;   guessed. Solving for the `pitch` value that produces a target
;   frequency f: `pitch = (CPU_CLOCK/f - 222) / 52`.
;
;   CPU_CLOCK is 3,528,000 Hz — the TS2068's own REAL, confirmed clock
;   speed (libspectrum's own machine timing table, `timings.c`:
;   `{ 3528000, 1764000, &timings_frame_timex_scld_60hz }` for TS2068 —
;   notably NOT the Sinclair Spectrum's own 3.5MHz; the TS2068 runs
;   slightly faster).
;
; Duration is handled exactly as the real ROM does: `cycles = f *
; duration` (frequency times seconds = a plain cycle count).
;
; PITCH_PARAM IS CLAMPED TO A MINIMUM OF 1 — pitch 0 would make
; SOUND_BEEP's own `.delay` loop wrap DEC BC from 0 to 65535 and count
; all the way back down (see that routine's own header), producing an
; extremely LOW, not high, pitch — the opposite of what a pitch_param
; near zero (a very high requested frequency) is trying to achieve.
; This is also this file's own real, quantified HARDWARE CEILING: the
; fastest SOUND_BEEP's own loop can possibly toggle is pitch_param=1,
; giving 222+52 = 274 T-states/cycle, i.e. 3528000/274 ≈ 12876 Hz — ANY
; requested frequency above that clamps to 12876 Hz instead, a real,
; audible-if-it-could-be-heard error (about -8.5% for the real ROM's
; own highest note, +69 semitones, ≈14080 Hz), not a rounding
; artifact. Ordinary musical use (a few octaves around middle C) is
; nowhere near this ceiling.
;
; ACCURACY, HAND-VERIFIED IN PYTHON BEFORE WRITING ANY Z80 (using the
; SAME bit-exact float model core/floattrig.asm's own design used,
; reusing its already-proven F+/F-/F*/F_UDIV32BY16 arithmetic exactly):
; typical notes land within 0.02%-0.6% of their true target frequency
; (a few cents, inaudible to most listeners) purely from truncating the
; computed pitch_param to an integer — the SAME truncate-not-round
; convention core/floatprint.asm's own F. already uses, not a new kind
; of imprecision. NONE of this has been (or can be, in this test
; environment) verified against an actual speaker — see
; kernel/sound/sound.asm's own header for why. What IS verified is that
; the MATH — the semitone decomposition, the octave-doubling identity
; (an input 12 semitones apart from another produces EXACTLY double or
; half the frequency, bit-for-bit, since the octave shift is an exact
; exponent add), and the final integer parameters — matches hand
; derivation exactly.
;
; SCOPE CUT, STATED HONESTLY: only INTEGER semitone pitches are
; supported. The real ROM also accepts a FRACTIONAL semitone (via a
; separate linear-interpolation constant applied to the fractional part
; of the pitch number) — not replicated here; a non-integer pitch
; simply isn't representable by this word's own `( n-semitones -- )`
; convention (n comes from the INTEGER data stack, which has no
; fractional part to begin with). Ordinary BASIC BEEP usage is
; overwhelmingly integer semitones anyway.
; ============================================================================

    IFNDEF CORE_BEEP_ASM
    DEFINE CORE_BEEP_ASM

; ---- Phase 31 RAM state. Starts right after core/floattrig.asm's own
; TRIG_TMP_E ($8855, ending $8856) — verified free by grepping every
; "EQU $8..." across core/, kernel/, include/, and rom/ first (nothing
; claims $8856-$885F before this). ----
BEEP_DUR_M        EQU $8856   ; 2 bytes: duration, popped from the float
                              ; stack at entry, held across the whole
                              ; computation (float stack is reused
                              ; heavily in between)
BEEP_DUR_E        EQU $8858   ; 1 byte
BEEP_FREQ_M       EQU $8859   ; 2 bytes: the computed note frequency
BEEP_FREQ_E       EQU $885B   ; 1 byte
BEEP_OCTAVE       EQU $885C   ; 1 byte: signed octave delta from
                              ; BEEP_DECOMPOSE, applied directly to
                              ; BEEP_FREQ_E
BEEP_GUARD        EQU $885D   ; 1 byte: BEEP_DECOMPOSE's own bounded-
                              ; loop safety counter (reset between its
                              ; two loops)
BEEP_PITCH_PARAM  EQU $885E   ; 2 bytes: holds the computed SOUND_BEEP
                              ; pitch argument across the later cycle-
                              ; count computation, which also needs the
                              ; float stack -- ends at $8860

BEEP_GUARD_MAX EQU 100   ; BEEP_DECOMPOSE's own loop cap -- 100 octaves
                         ; either way (>=1200 semitones) is already far
                         ; beyond any real pitch (the actual ROM's own
                         ; valid range is -60 to +69); also keeps
                         ; BEEP_OCTAVE safely inside a signed byte's own
                         ; -128..127 range even at the cap

; ---- constants, hand-derived the same careful way core/floattrig.asm's
; own SIN_TABLE/HALF_PI/etc. were ----
MIDDLE_C_M  EQU 16744
MIDDLE_C_E  EQU -6    ; 16744*2^-6 = 261.625  (true middle C = 261.6256)
CPU_CLOCK_M EQU 27562
CPU_CLOCK_E EQU 7     ; 27562*2^7 = 3527936  (true TS2068 clock =
                      ; 3528000 -- see this file's own header; a 15-bit
                      ; mantissa can't represent it exactly, off by
                      ; 0.0018%, utterly negligible here)
                      ; NOTE: the "222" and "52" T-state constants from
                      ; this file's own header are deliberately NOT
                      ; float constants here -- BEEP_COMPUTE applies
                      ; them as plain integer literals instead, see its
                      ; own comment for why (a real F_ALIGN bug, not a
                      ; style choice)

; ---- SEMITONE_TABLE: 12 entries, 2^(i/12) for i=0..11 (frequency
; ratios within one octave, relative to the note itself -- i=0 gives
; exactly 1.0). Same 3-byte-per-entry (DW mantissa, DB exponent) layout
; as core/floattrig.asm's own SIN_TABLE.
;   i= 0  (16384,-14)  1.0000000000  true 1.0000000000
;   i= 1  (17358,-14)  1.0594482422  true 1.0594630944
;   i= 2  (18390,-14)  1.1224365234  true 1.1224620483
;   i= 3  (19484,-14)  1.1892089844  true 1.1892071150
;   i= 4  (20643,-14)  1.2599487305  true 1.2599210499
;   i= 5  (21870,-14)  1.3348388672  true 1.3348398542
;   i= 6  (23170,-14)  1.4141845703  true 1.4142135624
;   i= 7  (24548,-14)  1.4982910156  true 1.4983070769
;   i= 8  (26008,-14)  1.5874023438  true 1.5874010520
;   i= 9  (27554,-14)  1.6817626953  true 1.6817928305
;   i=10  (29193,-14)  1.7817993164  true 1.7817974363
;   i=11  (30929,-14)  1.8877563477  true 1.8877486254
; ----
SEMITONE_TABLE:
    DW   16384  : DB -14
    DW   17358  : DB -14
    DW   18390  : DB -14
    DW   19484  : DB -14
    DW   20643  : DB -14
    DW   21870  : DB -14
    DW   23170  : DB -14
    DW   24548  : DB -14
    DW   26008  : DB -14
    DW   27554  : DB -14
    DW   29193  : DB -14
    DW   30929  : DB -14

; ============================================================================
; FLOAT_TO_INT16 (internal) — ( f -- ) HL=mantissa, A=exponent -> HL =
; truncated integer value (TRUNCATED toward zero on any fractional
; bits, same convention core/floatprint.asm's own F. already uses, not
; a new kind of imprecision). Handles both a negative exponent (shift
; HL right, reusing core/float.asm's own proven F_SHRA) and a positive
; one (shift HL left, a small new loop -- no existing helper does a
; plain 16-bit left shift by a variable count). Both shift counts are
; capped at 16, since beyond that the answer is unambiguous (0, for the
; magnitudes this file's own callers ever produce).
; Destroys: AF, B
; ============================================================================
FLOAT_TO_INT16:
    or   a
    ret  z
    jp   p, .grow
    neg
    cp   17
    jr   c, .shrink_go
    ld   a, 16
.shrink_go:
    ld   b, a
    call F_SHRA
    ret
.grow:
    cp   17
    jr   c, .grow_go
    ld   a, 16
.grow_go:
    ld   b, a
    or   a
    ret  z
.grow_loop:
    add  hl, hl
    djnz .grow_loop
    ret

; ============================================================================
; FLOAT_TO_UDIVID32 (internal) — HL=mantissa (assumed non-negative — a
; frequency or period, never negative in this file's own use), A =
; exponent -> populates core/floatdiv.asm's own F_DIVID_HI:F_DIVID_LO
; with the truncated value as an unsigned 32-BIT integer (landing it
; exactly where F_UDIV32BY16 already expects its own dividend).
;
; A REAL BUG FOUND AND FIXED HERE: BEEP_COMPUTE's own pitch_param
; formula needs `CPU_CLOCK/freq` as a plain integer before subtracting
; 222 and dividing by 52 (see that routine's own header for why this
; step is integer, not float, arithmetic). The FIRST version of this
; file used FLOAT_TO_INT16 for that conversion — wrong: for a
; low-pitched note (e.g. -60 semitones, a real, reachable value, not a
; contrived edge case), `CPU_CLOCK/freq` is 431504 — comfortably OVER
; 65535, so truncating it into a plain 16-bit HL silently wrapped
; (`ADD HL,HL` drops overflow bits with nowhere for them to go),
; corrupting the whole downstream computation (confirmed directly: the
; wrapped value produced a wrong pitch_param of 732 instead of the
; correct 8293, caught by rom/forth_smoke_p31.asm's own checkpoint 3).
; The FIX: widen the target to a genuine 32-bit integer first (this
; routine), matching the same "don't truncate to 16 bits before you
; have to" lesson core/floatmul.asm's own F_UMUL32 and
; core/floatdiv.asm's own F_UDIV32BY16 already encode — reusing the
; LATTER directly for the actual division, rather than writing a third
; 32-bit division routine.
; Destroys: AF, B, HL
; ============================================================================
FLOAT_TO_UDIVID32:
    ld   (F_DIVID_LO), hl
    ld   hl, 0
    ld   (F_DIVID_HI), hl
    or   a
    ret  z
    jp   p, .grow32
    neg
    cp   33
    jr   c, .shrink_cnt_ok
    ld   a, 32
.shrink_cnt_ok:
    ld   b, a
    ld   a, b
    or   a
    ret  z
.shrink_loop:
    ld   hl, (F_DIVID_HI)
    srl  h
    rr   l
    ld   (F_DIVID_HI), hl
    ld   hl, (F_DIVID_LO)
    rr   h
    rr   l
    ld   (F_DIVID_LO), hl
    djnz .shrink_loop
    ret
.grow32:
    cp   33
    jr   c, .grow_cnt_ok
    ld   a, 32
.grow_cnt_ok:
    ld   b, a
    ld   a, b
    or   a
    ret  z
.grow_loop:
    ld   hl, (F_DIVID_LO)
    add  hl, hl
    ld   (F_DIVID_LO), hl
    ld   hl, (F_DIVID_HI)
    adc  hl, hl
    ld   (F_DIVID_HI), hl
    djnz .grow_loop
    ret

; ============================================================================
; BEEP_DECOMPOSE (internal) — entry HL = pitch (signed semitone number,
; 0 = middle C). Splits it into a note-within-octave (0-11, returned in
; A) and an octave delta (BEEP_OCTAVE, signed byte) via the same
; repeated-subtract-12 idea the real ROM's own BEEP routine uses (see
; this file's own header) -- a bounded loop (BEEP_GUARD, capped at
; BEEP_GUARD_MAX each direction), not the real ROM's own fixed
; 6-octaves-below-middle-C starting point, since this version has no
; fixed valid range to assume.
; Destroys: AF, DE, HL
; ============================================================================
BEEP_DECOMPOSE:
    xor  a
    ld   (BEEP_OCTAVE), a
    xor  a
    ld   (BEEP_GUARD), a
.neg_loop:
    ld   a, h
    or   a
    jp   p, .neg_done
    ld   a, (BEEP_GUARD)
    cp   BEEP_GUARD_MAX
    jp   nc, .neg_done
    inc  a
    ld   (BEEP_GUARD), a
    ld   de, 12
    add  hl, de
    ld   a, (BEEP_OCTAVE)
    dec  a
    ld   (BEEP_OCTAVE), a
    jp   .neg_loop
.neg_done:
    xor  a
    ld   (BEEP_GUARD), a
.ge_loop:
    ld   a, h
    or   a
    jr   nz, .ge_need_sub
    ld   a, l
    cp   12
    jr   c, .ge_done
.ge_need_sub:
    ld   a, (BEEP_GUARD)
    cp   BEEP_GUARD_MAX
    jp   nc, .ge_done
    inc  a
    ld   (BEEP_GUARD), a
    ld   de, 12
    or   a
    sbc  hl, de
    ld   a, (BEEP_OCTAVE)
    inc  a
    ld   (BEEP_OCTAVE), a
    jp   .ge_loop
.ge_done:
    ld   a, l
    cp   12
    jr   c, .note_ok         ; defensive clamp -- only reachable if the
                              ; guard above was exhausted on a wildly
                              ; out-of-range input; see this file's own
                              ; BEEP_GUARD_MAX comment
    ld   a, 11
.note_ok:
    ret

; ============================================================================
; BEEP_COMPUTE (internal) — entry: HL = pitch (signed semitone number),
; BEEP_DUR_M/BEEP_DUR_E already populated by the caller. Exit: BC =
; SOUND_BEEP's own pitch argument (>=1), DE = SOUND_BEEP's own duration
; (cycle count, >=0). See this file's own header for the full
; derivation.
; Destroys: AF, BC, DE, HL
; ============================================================================
BEEP_COMPUTE:
    call BEEP_DECOMPOSE       ; a = note (0-11); BEEP_OCTAVE set
    ld   l, a
    ld   h, 0
    ld   d, h
    ld   e, l
    add  hl, hl
    add  hl, de               ; hl = note*3
    ld   de, SEMITONE_TABLE
    add  hl, de
    ld   c, (hl)
    inc  hl
    ld   b, (hl)
    inc  hl
    ld   a, (hl)               ; a = ratio exponent
    ld   l, c
    ld   h, b                  ; hl = ratio mantissa
    push hl
    push af
    ld   hl, MIDDLE_C_M
    ld   a, MIDDLE_C_E
    call FPUSH
    pop  af
    pop  hl
    call FPUSH
    call W_FSTAR                ; MIDDLE_C * ratio -> float stack
    call FPOP                   ; hl=mantissa, a=exponent
    ld   b, a
    ld   a, (BEEP_OCTAVE)
    add  a, b                   ; apply the octave shift directly to
                                 ; the exponent -- exact, see header
    ld   (BEEP_FREQ_M), hl
    ld   (BEEP_FREQ_E), a

    ; pitch_param = trunc((trunc(CPU_CLOCK/freq) - 222) / 52), clamped
    ; to >=1. THE DIVISION (CPU_CLOCK/freq) is done as a FLOAT (F/,
    ; which never calls F_ALIGN — division needs no exponent alignment
    ; at all), but the "- 222" and "/ 52" are done as PLAIN 32-BIT
    ; INTEGER arithmetic, deliberately NOT as floats. TWO real bugs
    ; were found and fixed here, not a stylistic choice:
    ;   (1) A "- 222" done as a FLOAT subtraction hits core/float.asm's
    ;       own F_ALIGN unsigned-comparison quirk (see the
    ;       2068forth-float-align-signed-cmp-quirk memory note): for a
    ;       low-pitched note, CPU_CLOCK/freq is a LARGE number
    ;       (hundreds of thousands), normalizing to a POSITIVE float
    ;       exponent, while 222.0 normalizes to a small NEGATIVE one —
    ;       F_ALIGN wrongly treated 222's own tiny negative exponent as
    ;       "larger", shifting the LARGE period's own mantissa down to
    ;       nothing and returning essentially -222 instead of
    ;       period-222 — confirmed directly (pitch -60, a real,
    ;       reachable note, not contrived): pitch_param came out as 1
    ;       (the clamp) instead of the correct 8293.
    ;   (2) Converting `CPU_CLOCK/freq` to a plain 16-BIT integer (via
    ;       FLOAT_TO_INT16, used for cycle_count just below, where it's
    ;       genuinely safe) is ALSO wrong here: for that same pitch -60
    ;       case, CPU_CLOCK/freq is 431504 — comfortably over 65535, so
    ;       truncating into 16 bits silently wrapped (`ADD HL,HL` drops
    ;       overflow bits with nowhere to go), corrupting the result a
    ;       SECOND, independent way (confirmed: gave pitch_param=732,
    ;       neither the buggy-F_ALIGN answer NOR the correct one).
    ; THE FIX for both: widen to a genuine 32-bit integer
    ; (FLOAT_TO_UDIVID32, above) before doing PLAIN 32-bit integer
    ; subtraction (two chained SBC HL,DE) and reusing
    ; core/floatdiv.asm's own already-proven F_UDIV32BY16 for the
    ; division — no float operation, so no F_ALIGN exposure, and no
    ; 16-bit ceiling either.
    ld   hl, CPU_CLOCK_M
    ld   a, CPU_CLOCK_E
    call FPUSH
    ld   hl, (BEEP_FREQ_M)
    ld   a, (BEEP_FREQ_E)
    call FPUSH
    call W_FSLASH                ; CPU_CLOCK/freq -> float stack
    call FPOP
    call FLOAT_TO_UDIVID32          ; F_DIVID_HI:F_DIVID_LO = period,
                                     ; truncated, as a genuine 32-bit
                                     ; unsigned integer
    ld   hl, (F_DIVID_LO)
    ld   de, 222
    or   a
    sbc  hl, de
    ld   (F_DIVID_LO), hl
    ld   hl, (F_DIVID_HI)
    ld   de, 0
    sbc  hl, de                     ; propagate the low word's own
                                     ; borrow into the high word
    ld   (F_DIVID_HI), hl
    jp   c, .pp_clamp                ; borrow out of the top -- the
                                      ; true period was < 222 (the note
                                      ; is too high for this loop to
                                      ; reach at all)
    ld   bc, 52
    call F_UDIV32BY16                 ; F_PROD_HI:F_PROD_LO = quotient
                                       ; (F_PROD_HI is always 0 for any
                                       ; pitch_param this file's own
                                       ; realistic range produces)
    ld   hl, (F_PROD_LO)
    ld   a, h
    or   l
    jr   nz, .pp_done
.pp_clamp:
    ld   hl, 1                        ; see this file's own header on
                                       ; why 1, never 0
.pp_done:
    ld   (BEEP_PITCH_PARAM), hl

    ; cycle_count = freq * duration
    ld   hl, (BEEP_FREQ_M)
    ld   a, (BEEP_FREQ_E)
    call FPUSH
    ld   hl, (BEEP_DUR_M)
    ld   a, (BEEP_DUR_E)
    call FPUSH
    call W_FSTAR
    ld   a, (iy+1)                     ; same sign-before-clobber trick
                                        ; as above -- a negative
                                        ; duration would otherwise
                                        ; truncate to a huge-looking
                                        ; unsigned value, not a small
                                        ; negative one
    or   a
    push af
    call FPOP
    call FLOAT_TO_INT16
    pop  af
    jp   p, .cc_done
    ld   hl, 0
.cc_done:
    ld   d, h
    ld   e, l                          ; de = cycle_count
    ld   hl, (BEEP_PITCH_PARAM)
    ld   b, h
    ld   c, l                          ; bc = pitch_param
    ret

; ============================================================================
; BEEP ( n-semitones fduration -- )
; ============================================================================
H_BEEP:
    DW   DICT_CHAIN_POINT   ; the including ROM must set this (DEFL,
                            ; not EQU) to whatever word chain this file
                            ; should extend, immediately before
                            ; INCLUDEing this file
    DB   4, "B", "E", "E", "P"
W_BEEP:
    call FPOP
    ld   (BEEP_DUR_M), hl
    ld   (BEEP_DUR_E), a
    call DPOP_HL              ; hl = pitch (signed semitone number)
    call BEEP_COMPUTE          ; -> bc = pitch_param, de = cycle_count
    call SOUND_BEEP
    ret

DICT_LATEST_INIT_BEEP EQU H_BEEP   ; head of the dictionary once this
                                    ; file's own word is included

    ENDIF
