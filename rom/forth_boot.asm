; ============================================================================
; rom/forth_boot.asm — the first real, live, bootable 2068-Forth ROM
;
; Distinct from every rom/forth_smoke_p*.asm file in this project: those
; are automated regression tests with no keyboard input and a
; border-color pass/fail signal; this is the actual product — it boots,
; prints a banner, plays the startup sound tracked as an open product
; requirement since Phase 4 (docs/PROJECT_PLAN.md, "Product requirement
; — startup screen plays a startup sound"), and hands control to
; core/editor.asm's EDITOR_LOOP_LIVE for real, live, interactive use —
; the same live interpreter loop Phase 6 built but could not safely
; call, because kernel/io's IO_READ_KEY only consumes a key already
; latched by a real IM 1 interrupt, and no ROM before this one ever
; turned interrupts on. See rom/forth_smoke_p9.asm's own header for the
; full story of what had to be fixed first (a dictionary-chain
; structural bug spanning core/control.asm, core/storage.asm, and
; core/float.asm) and how the real interrupt wiring below was confirmed
; against 2068-Leap's own working ROM files, not guessed.
;
; The full dictionary is assembled here: every word from every phase
; (DROP/DUP/SWAP/OVER/+/-/@/!, :/;, 0=/IF/ELSE/THEN/BEGIN/UNTIL,
; PLOT/LINE/CIRCLE/BORDER/CLS, SAVE-LIB/LOAD-LIB, F+/F-, 64COL/32COL/
; PALETTE64/PLOT64, F*, F/, EMIT/., F., FSQRT, S>F/F>S/FROUND,
; PI/SIN/COS, BEEP, SOUND, =/</>, VARIABLE/CONSTANT, ." , WHILE/REPEAT,
; INK/PAPER, DO/LOOP/LEAVE/+LOOP/I, FILL/AT-XY, KEY/KEY?,
; ABS/SGN/MOD/SQRT/RND/RANDOMIZE, ARRAY/CELLS,
; S"/TYPE/STRING/PLACE/COUNT/LEN/VAL, C@/C!, STICK, ACCEPT/INPUT,
; CHR/STR/UPPER/LOWER/LEFT/RIGHT/SEARCH/CODE, EXECUTE, RAD/DEG — 93
; words total (cross-checked directly against every H_*/DB header in
; this file's own INCLUDE chain during a code-consolidation pass rather than
; trusted from an earlier draft of this same comment, which had
; quietly drifted 34 words stale — missing everything from the
; original Phase 2 primitives (DROP/DUP/SWAP/OVER/+/-/@/!) it should
; have listed from the very start, through most of Phases 24-32),
; chained into one LATEST list via the same DICT_CHAIN_POINT splices
; rom/forth_smoke_p9.asm introduced and proved. NOTE: the "93 words"
; count above already went stale after Phase 49 (1+/1-/NEGATE/MAX/MIN/
; VLIST/EXIT/J) and is now further out of date after Phase 50's own
; architectural-tier additions (HERE, `,`, C,, ALLOT, CREATE, DOES>,
; IMMEDIATE, ABORT, QUIT, IN, OUT, FORGET) — recounting it correctly is
; left to whichever future pass actually re-derives it from the real
; INCLUDE chain, per this same comment's own stated method, rather than
; hand-incrementing a number this comment has already shown can drift.
; Phase 50's own new files are core/dictspace.asm, core/create.asm,
; core/does.asm, core/immediate.asm, core/abortquit.asm,
; core/portio.asm, and core/forget.asm — see each file's own header for
; what it adds and why. Phase 51 adds one more: core/udg.asm (UDG,
; n -- addr), spliced in after core/forget.asm/before core/editor.asm,
; with COLD_START's own LATEST seed updated to
; DICT_LATEST_INIT_UDG — see that file's own header.
; DECIMAL_NUMBER_ENABLED is also DEFINEd here (core/decimal.asm,
; Phase 23) — not a dictionary word, a NUMBER/INTERPRET_RUN parsing
; capability: typing a literal like `3.5` now pushes a real float
; directly, in both interpret and compile contexts.
;
; WHAT ISN'T HERE YET, stated plainly: no live automated test exercises
; the interactive loop this file actually boots into — by its nature,
; that needs a real or simulated keyboard, not a fixed source string.
; Manual confirmation in Fuse (or real hardware) with an actual keyboard
; remains the honest gap, exactly as core/editor.asm's own header
; already says for EDITOR_LOOP_LIVE.
;
; STARTUP SOUND (revised after real live-audio testing — see
; core/sound.asm's own header for the full "8 15 SOUND produced static,
; not a tone" story): no longer SOUND_BEEP's raw hardware-timing beeper.
; An old-Mac-style startup chord — C4/E4/G4 rung out together across
; all three AY channels and held ~800ms — picked by the user from
; several presented options (a single-channel rising arpeggio and a
; simpler two-note beep among them). Same clock/formula core/sound.asm's
; own header already uses for its own confirmed-clean tone; held via
; CHIME_DELAY (a frame-count wait via kernel/interrupt's own
; INT_GET_FRAMES, so interrupts must already be enabled —
; KBD_ISR_INIT/IM1/EI now run BEFORE the chime, not after).
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

; ---- RST 00: cold start ----
RST_00:
    di
    jp   COLD_START

    DS   $0008 - $, $FF
RST_08:
    ret

    DS   $0010 - $, $FF
RST_10:
    ret

    DS   $0018 - $, $FF
RST_18:
    ret

    DS   $0020 - $, $FF
RST_20:
    ret

    DS   $0028 - $, $FF
RST_28:
    ret

    DS   $0030 - $, $FF
RST_30:
    ret

    DS   $0038 - $, $FF
; ---- RST 38 / IM 1 maskable interrupt entry point — real wiring,
; confirmed from 2068-Leap's own working ROM files (e.g.
; rom/test_arr3.asm's own RST_38), not guessed. ----
RST_38:
    call KBD_ISR_TICK
    ei
    reti

    DS   $0066 - $, $FF
NMI_ENTRY:
    retn

    DS   $0100 - $, $FF

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_LOADTEXT   ; the full chain's own head —
                                    ; see this file's own header (Phase
                                    ; 52 -- core/loadtext.asm's SAVE-TEXT/
                                    ; LOAD-TEXT -- spliced on after
                                    ; core/udg.asm's own tail)
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a         ; core/doloop.asm's own LEAVE
                                   ; bookkeeping -- must start at 0
    ld   (CATCH_DEPTH), a         ; core/throwcatch.asm's own CATCH
                                   ; bookkeeping -- must start at 0
    ld   a, DEFAULT_ATTR          ; required since Phase 15 -- see
    ld   (CURRENT_ATTR), a        ; core/ts2068.asm's own header
    ld   a, 1
    ld   (FWRAP_OLD_COUNT), a ; required once at cold start -- see
                                  ; core/editor.asm's own header on this
                                  ; cell

    call GFX_CLS
    ld   hl, BANNER
    ld   b, 0
    ld   c, 0
    call GFX_PRINT_STRING

    ; EMIT/.'s own output position starts on the row right under the
    ; banner, not (0,0) -- (0,0) is where BANNER's own text just went,
    ; and PRINT_ROW/PRINT_COL have no idea the banner was ever printed
    ; (core/print.asm's own header: both cells must be initialized by
    ; whatever ROM uses it, no assumed default). Found live: typing
    ; "65 EMIT" silently overwrote the banner's own "2" with "A"
    ; instead of appearing as new, visible output.
    xor  a
    ld   (PRINT_COL), a
    ld   a, 1
    ld   (PRINT_ROW), a

    call KBD_ISR_INIT               ; must run before EI -- confirmed
                                    ; 2068-Leap ordering
    im   1
    ei                              ; must be on before CHIME_DELAY --
                                    ; it waits on FRAMES, which only the
                                    ; ISR ever advances

    call STARTUP_CHIME

    jp   EDITOR_LOOP_LIVE

; ============================================================================
; STARTUP_CHIME — an old-Mac-style startup chord: C4/E4/G4 across all
; three AY channels, echoing the classic System 7-era Macintosh boot
; chime (picked from several options presented to the user, including
; the original rising single-channel arpeggio this replaces). Periods
; use the same TS2068 AY clock (1,764,000 Hz) and
; period = clock/(16*freq) formula core/sound.asm's own header already
; derives its confirmed-clean tone from.
;
; REVISED after a real recording (WAV) of the first version was made
; and analyzed by FFT: the notes themselves were exactly right (261.7/
; 330.0/391.7 Hz measured against a 262/330/392 Hz target, no
; clipping), so the "didn't sound correct" report wasn't a wrong-pitch
; bug — it's the AY's raw square waves. Three of them snapping to full
; volume in the same instant produces a harsh click (an audible step
; discontinuity) plus a buzzy stack of clashing square-wave harmonics,
; quite unlike the real Mac's smooth SAMPLED synth chime. Two real
; fixes for that, neither changing the notes themselves: (1) a stepped
; volume ramp on attack/release instead of an instant on/off, so each
; note fades in/out rather than clicking; (2) a staggered entrance —
; Channel A rings first, then B, then C roll in on top of it (like an
; actual bell chime), rather than all three hitting at once.
;
; Channel A's tone-period FINE byte is chip register 0 — and
; core/sound.asm's own SOUND_WRITE (faithfully matching the real ROM's
; SOUND command) refuses register 0 as out-of-range, since SOUND's own
; documented range is 1-16 and can never reach it (see that file's own
; header). That restriction exists to keep SOUND itself authentic to
; the real ROM; it doesn't bind this boot code, which is free to write
; the AY ports directly for that one otherwise-unreachable register.
; ============================================================================
STARTUP_CHIME:
    ld   a, 0                       ; Channel A tone period, fine --
    out  (PORT_AY_REG), a           ; chip register 0, unreachable via
    ld   a, 165                     ; SOUND_WRITE/SOUND (see header
    out  (PORT_AY_DATA), a          ; above) -- written directly instead

    ld   b, 1                       ; Channel A tone period, coarse
    ld   c, 1                       ; -> period 421, C4 (~262 Hz)
    call SOUND_WRITE

    ld   b, 2                       ; Channel B tone period, fine
    ld   c, 78
    call SOUND_WRITE
    ld   b, 3                       ; Channel B tone period, coarse
    ld   c, 1                       ; -> period 334, E4 (~330 Hz)
    call SOUND_WRITE

    ld   b, 4                       ; Channel C tone period, fine
    ld   c, 25
    call SOUND_WRITE
    ld   b, 5                       ; Channel C tone period, coarse
    ld   c, 1                       ; -> period 281, G4 (~392 Hz)
    call SOUND_WRITE

    ld   b, 7                       ; mixer: all three tones enabled,
    ld   c, 248                     ; all three noise generators off
    call SOUND_WRITE                ; ($FF with bits 0-2 cleared)

    ld   b, 8                       ; all three silent until each
    ld   c, 0                       ; channel's own staggered attack
    call SOUND_WRITE                ; below brings it in
    ld   b, 9
    call SOUND_WRITE
    ld   b, 10
    call SOUND_WRITE

    ; ---- staggered, ramped attack: A rolls in first, then B, then C,
    ; each fading up over 3 steps instead of snapping to full volume ----
    ld   b, 8  : ld c, 4  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 8  : ld c, 8  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 8  : ld c, 12 : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY             ; gap before B enters

    ld   b, 9  : ld c, 4  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 9  : ld c, 8  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 9  : ld c, 12 : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY             ; gap before C enters

    ld   b, 10 : ld c, 4  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 10 : ld c, 8  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 10 : ld c, 12 : call SOUND_WRITE  ; full chord now sounding

    ld   b, 22                      ; hold the full chord ~440ms
    call CHIME_DELAY

    ; ---- release: all three fade down together ----
    ld   b, 8  : ld c, 8  : call SOUND_WRITE
    ld   b, 9  : ld c, 8  : call SOUND_WRITE
    ld   b, 10 : ld c, 8  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 8  : ld c, 4  : call SOUND_WRITE
    ld   b, 9  : ld c, 4  : call SOUND_WRITE
    ld   b, 10 : ld c, 4  : call SOUND_WRITE
    ld   b, 3  : call CHIME_DELAY
    ld   b, 8  : ld c, 0  : call SOUND_WRITE  ; the AY holds its last
    ld   b, 9  : ld c, 0  : call SOUND_WRITE  ; register state
    ld   b, 10 : ld c, 0  : call SOUND_WRITE  ; indefinitely otherwise
    ret

; ============================================================================
; CHIME_DELAY — busy-waits until FRAMES (kernel/interrupt.asm) has
; advanced by B ticks. In: B = frame count. Destroys: AF, HL, DE
; ============================================================================
CHIME_DELAY:
    ld   h, 0
    ld   l, b
    ex   de, hl                     ; de = frame count to wait
    call INT_GET_FRAMES             ; hl = current frames
    add  hl, de
    ex   de, hl                     ; de = target frame count
.wait:
    call INT_GET_FRAMES             ; only touches hl -- de (target)
                                    ; survives across this loop
    or   a
    sbc  hl, de
    jr   c, .wait                   ; current < target -- keep waiting
    ret

BANNER: DB "2068-FORTH", 0

; ============================================================================
; INTERPRET_UNKNOWN_WORD — core/interp.asm's hook for a token that's
; neither a known word nor a valid number. Every rom/forth_smoke_p*.asm
; file hangs here on purpose (a bug in fixed, hand-written test source
; should stop hard and loud). That's the wrong choice for a live,
; interactive system: a real typo would otherwise need a hardware
; reset to recover from. INTERPRET_RUN reaches this hook via a bare
; `jp`, not `call`, so the Z80 return-address stack at this point still
; holds exactly one entry — INTERPRET_RUN's own caller
; (EDITOR_LOOP_LIVE's `call INTERPRET_RUN`).
;
; Prints "?" followed by a newline (both via core/print.asm's own
; W_EMIT, called directly — safe to do mid-line, since EMIT's own data-
; stack use is self-contained: it pops exactly what it's given, however
; much of the interpreter's own expression-in-progress is sitting below
; that at this point) before returning straight to EDITOR_LOOP_LIVE,
; which starts a fresh prompt on the next line. A genuine typo now
; looks visibly different from one that happened to be typed slightly
; differently and got silently discarded — real, if minimal, error
; feedback, not just error recovery. Still real, open follow-up work:
; no distinction is made between "unknown word" and other possible
; failures (there's only one kind right now), and the rest of the
; current line is simply abandoned rather than reporting which word
; specifically wasn't understood.
; ============================================================================
INTERPRET_UNKNOWN_WORD:
    ; real bugs, found live (2026-09-03): (1) STATE was left stuck at 1
    ; forever after an unknown word hit mid-compile (e.g. a dropped
    ; keystroke merging two intended words into one during live typing),
    ; silently compiling every subsequent line typed instead of running
    ; it; (2) NUMBER's own .fail path (core/interp.asm) pushes a
    ; placeholder n=0 ahead of its flag, and .badword jumps here without
    ; ever popping it, leaving one stray value behind on the data stack.
    ; Both are this hook's own job to clean up -- core/interp.asm's own
    ; .badword comment says so, and STACK_CHECK's sibling error path
    ; (RUNTIME_ERROR_HOOK below) already resets both stacks the same way
    ; before reporting, so this now matches that same abort contract.
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP
    ; print the actual unrecognized word before the "?", not just a
    ; bare "?" with no clue which token failed -- WORD_BUF (core/
    ; interp.asm) still holds it untouched: INTERPRET_RUN's own .loop
    ; already proved it's nonzero-length before ever reaching FIND/
    ; NUMBER/here, and neither of those touches WORD_BUF itself. W_EMIT
    ; destroys BC (loads PRINT_ROW/PRINT_COL into it, core/print.asm),
    ; so both are saved/restored around every call, not trusted to
    ; survive.
    ld   a, (WORD_BUF)
    ld   b, a
    ld   hl, WORD_BUF+1
.printword:
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    djnz .printword
    ld   hl, " "
    call DPUSH_HL
    call W_EMIT
    ld   hl, "?"
    call DPUSH_HL
    call W_EMIT
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT
    xor  a
    ld   (STATE), a
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a   ; tells EDITOR_LOOP_LIVE not to print
                                   ; its own OK for this line -- see
                                   ; INTERP_ERROR_FLAG's own header
                                   ; (core/interp.asm)
    ret

; ============================================================================
; RUNTIME_ERROR_HOOK — Phase 38's own required hook for
; core/interp.asm's STACK_CHECK (see that routine's own header): called
; the same proven way INTERPRET_UNKNOWN_WORD already is (a bare `jp`,
; stack depth already restored to "INTERPRET_RUN's own caller, one
; entry" before this is reached), so a plain `ret` here correctly
; unwinds straight back to EDITOR_LOOP_LIVE, abandoning the rest of
; the current line exactly like an unknown word already does. Both
; data stacks are already reset to empty by the time this runs — this
; hook's only job is reporting.
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   hl, RUNTIME_ERROR_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .msgdone
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.msgdone:
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT
    xor  a
    ld   (STATE), a          ; same fix as INTERPRET_UNKNOWN_WORD's own
                              ; STATE reset above -- an IMMEDIATE word's
                              ; runtime error while compiling could
                              ; otherwise leave STATE stuck too
    ld   a, 1
    ld   (INTERP_ERROR_FLAG), a   ; same as INTERPRET_UNKNOWN_WORD's own
    ret

RUNTIME_ERROR_MSG: DB "STACK?", 0

; ---- kernel + dictionary: included here, after the vector table and
; the boot code above, not before ORG $0000. DICT_CHAIN_POINT splices
; match rom/forth_smoke_p9.asm's own, already proven under Fuse. ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "kernel/storage/storage.asm"
    INCLUDE "kernel/mode64/mode64.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    DEFINE RUNTIME_ERROR_CHECK_ENABLED
    DEFINE THROW_CATCH_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/storage.asm"
DICT_CHAIN_POINT DEFL H_LOADLIB
    INCLUDE "core/float.asm"
    INCLUDE "core/mode64.asm"
DICT_CHAIN_POINT DEFL H_PLOT64
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/decimal.asm"
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/floatprint.asm"
DICT_CHAIN_POINT DEFL H_FDOT
    INCLUDE "core/floatsqrt.asm"
DICT_CHAIN_POINT DEFL H_FSQRT
    INCLUDE "core/floatconv.asm"
DICT_CHAIN_POINT DEFL H_FROUND
    INCLUDE "core/floattrig.asm"
DICT_CHAIN_POINT DEFL H_DEG
    INCLUDE "core/beep.asm"
DICT_CHAIN_POINT DEFL H_BEEP
    INCLUDE "core/sound.asm"
DICT_CHAIN_POINT DEFL H_SOUND
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/variable.asm"
DICT_CHAIN_POINT DEFL H_CONSTANT
    INCLUDE "core/dotquote.asm"
DICT_CHAIN_POINT DEFL H_DOTQUOTE
    INCLUDE "core/loop.asm"
DICT_CHAIN_POINT DEFL H_REPEAT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_PAPER
    INCLUDE "core/doloop.asm"
DICT_CHAIN_POINT DEFL H_I
    INCLUDE "core/loopext.asm"
DICT_CHAIN_POINT DEFL H_J
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/key.asm"
DICT_CHAIN_POINT DEFL H_KEYQ
    INCLUDE "core/mathfn.asm"
DICT_CHAIN_POINT DEFL H_RANDOMIZE
    INCLUDE "core/arith.asm"
DICT_CHAIN_POINT DEFL H_MIN
    INCLUDE "core/array.asm"
DICT_CHAIN_POINT DEFL H_CELLS
    INCLUDE "core/string.asm"
DICT_CHAIN_POINT DEFL H_VAL
    INCLUDE "core/stringext.asm"
DICT_CHAIN_POINT DEFL H_CODE
    INCLUDE "core/execute.asm"
DICT_CHAIN_POINT DEFL H_EXECUTE
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/stick.asm"
DICT_CHAIN_POINT DEFL H_STICK
    INCLUDE "core/input.asm"
DICT_CHAIN_POINT DEFL H_INPUT
    INCLUDE "core/free.asm"
DICT_CHAIN_POINT DEFL H_FREE
    INCLUDE "core/throwcatch.asm"
DICT_CHAIN_POINT DEFL H_CATCH
    INCLUDE "core/stackops.asm"
DICT_CHAIN_POINT DEFL H_PICK
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/outwords.asm"
DICT_CHAIN_POINT DEFL H_SPACES
    INCLUDE "core/tick.asm"
DICT_CHAIN_POINT DEFL H_TICK
    INCLUDE "core/printer.asm"
DICT_CHAIN_POINT DEFL H_LLIST
    INCLUDE "core/ulaplus.asm"
DICT_CHAIN_POINT DEFL H_PALETTE
    INCLUDE "core/vlist.asm"
DICT_CHAIN_POINT DEFL H_VLIST
    INCLUDE "core/dictspace.asm"
DICT_CHAIN_POINT DEFL H_ALLOT
    INCLUDE "core/create.asm"
DICT_CHAIN_POINT DEFL H_CREATE
    INCLUDE "core/does.asm"
DICT_CHAIN_POINT DEFL H_DOES
    INCLUDE "core/immediate.asm"
DICT_CHAIN_POINT DEFL H_IMMEDIATE
    INCLUDE "core/abortquit.asm"
DICT_CHAIN_POINT DEFL H_QUIT
    INCLUDE "core/portio.asm"
DICT_CHAIN_POINT DEFL H_OUT
    INCLUDE "core/forget.asm"
DICT_CHAIN_POINT DEFL H_FORGET
    INCLUDE "core/udg.asm"
DICT_CHAIN_POINT DEFL H_UDG
    INCLUDE "core/loadtext.asm"
    ; core/storage.asm's own SAVE_LOAD_TEMP_BUF/SAVE_LOAD_MAX_DICT are
    ; literals that deliberately TIME-SHARE this exact same physical RAM
    ; (LOADTEXT_BUF/LOADTEXT_MAX_LEN) rather than referencing these
    ; symbols directly -- core/storage.asm must still assemble standalone
    ; in rom/forth_smoke_p7.asm, where neither of these exists (see that
    ; file's own header for why it can't be a live expression). This is
    ; the one place in the real product ROM where both sides of that
    ; literal duplication actually exist together -- if either ever
    ; drifts, this fires at assembly time instead of silently corrupting
    ; RAM the two mechanisms were supposed to be safely sharing.
    ASSERT SAVE_LOAD_TEMP_BUF == LOADTEXT_BUF
    ASSERT SAVE_LOAD_MAX_DICT == LOADTEXT_MAX_LEN - 2
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_boot_rom0.bin", $0000, $4000
