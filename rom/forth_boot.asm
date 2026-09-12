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
; (DROP/DUP/SWAP/OVER/+/-, *, /, :/;, 0=/IF/ELSE/THEN/BEGIN/UNTIL/WHILE/
; REPEAT, PLOT/LINE/CIRCLE/BORDER/CLS, SAVE-LIB/LOAD-LIB/SAVE-TEXT/
; LOAD-TEXT, F+/F-, F*, F., F/, EMIT/., .", CR/SPACE/SPACES, FSQRT,
; S>F/F>S/FROUND, PI/SIN/COS/RAD/DEG, BEEP, SOUND, ULAPLUS/PALETTE,
; =/</>, VARIABLE/CONSTANT, INK/PAPER/BRIGHT/FLASH, HIRES/NORMAL,
; 64COL/32COL/PALETTE64/PLOT64, DO/LOOP/LEAVE/+LOOP/I/J, FILL/AT-XY,
; KEY/KEY?/BREAK?, ABS/SGN/MOD/SQRT/RND/RANDOMIZE, 1+/1-/NEGATE/MAX/MIN,
; ARRAY/CELLS, S"/TYPE/STRING/PLACE/COUNT/LEN/VAL, C@/C!, STICK,
; ACCEPT/INPUT, CHR/STR/UPPER/LOWER/LEFT/RIGHT/SEARCH/CODE, EXECUTE,
; HERE/,/C,/ALLOT/CREATE/DOES>/IMMEDIATE, FREE, THROW/CATCH,
; ROT/2DUP/2DROP/?DUP/PICK, AND/OR/XOR/INVERT, ' (TICK), LPRINT/LLIST,
; VLIST, ABORT/QUIT, IN/OUT, FORGET, UDG, TONE/VOLUME/MIXER/NOISE/
; ENVELOPE, LIST-DEFS, RECALL, EXIT — 150 words total.
; RE-DERIVED, NOT HAND-COUNTED: this comment's own earlier draft
; (claiming 93) had already gone stale twice over — once discovered
; during a Phase-24-era consolidation pass (missing the original Phase
; 2 primitives and most of Phases 24-32), and again silently after
; Phase 49/50 with nobody re-deriving it (the comment said so itself,
; rather than guess). Both times the number was hand-counted or hand-
; incremented from prose. This time (and again for Phase 60/61's
; BRIGHT/FLASH, Phase 62's BREAK?, and Phase 64's LIST-DEFS/RECALL —
; the count had again drifted silently at 148 real words when this
; comment still said 143, missing Phase 63's own TONE/VOLUME/MIXER/
; NOISE/ENVELOPE entirely) it's the result of actually assembling this
; file and walking the real dictionary's own LINK chain in the compiled
; binary, byte for byte, from LATEST's own seed (DICT_LATEST_INIT_RECALL)
; down to the LINK=0 sentinel — the same class of check that caught two
; real dictionary-orphaning bugs earlier in this project's history (a
; chain-point set to the wrong tail marker silently drops every word
; after it, which eyeballing headers can miss but walking the real chain
; cannot). 150 unique names, zero duplicates, zero shadowing, chained
; into one LATEST list via the same DICT_CHAIN_POINT splices
; rom/forth_smoke_p9.asm introduced and proved. Whoever next adds a
; phase: re-run this same walk (build this ROM, then follow
; DICT_LATEST_INIT_RECALL's own LINK chain through the assembled .bin)
; rather than incrementing this number by eye — that's exactly the habit
; that let it drift, repeatedly.
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
; GRAPHICS_HOME_TABLE — fixed-address JP veneers for EXROM-resident
; graphics code (rom/graphics_exrom.asm) to call into Home through.
; Real routines like GFX_WRITE_PIXEL move every time this ROM's own
; dictionary grows or shrinks; code assembled as a separate, standalone
; EXROM image has no way to track that automatically the way a single
; concatenated build would. Fixed slots at a fixed, low, never-moving
; address are the fix — same shape as 2068-Leap's own inherited EXT_
; SERVICE_TABLE veneers (include/sysvars.inc), reused here for the same
; reason rather than inventing a different mechanism. Append-only: an
; existing slot's position must never change once an EXROM image has
; been built against it.
; ============================================================================
GRAPHICS_HOME_TABLE:
    jp   GFX_WRITE_PIXEL          ; slot 0 — B=x, C=y, A=attr, D=OVER
    jp   GFX_SET_ATTR             ; slot 1 — A=attr, B=row, C=col
    jp   GFX_LINE                 ; slot 2 — no register args; reads
                                  ; GFX_LINE_X0/Y0/X1/Y1/ATTR/OVER
    jp   GFX_ROW_BASE_ADDR        ; slot 3 — A=row -> HL=that row's
                                  ; bitmap base address (scanline 0)
    jp   GFX_CELL_ATTR_ADDR       ; slot 4 — B=row, C=col -> HL=addr

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ; Real hardware and accuracy-oriented emulators don't guarantee RAM
    ; is zeroed at power-on -- only some emulators happen to pre-zero
    ; it, which is exactly the class of bug 2068-Leap's own MEM_COLD_
    ; INIT exists to prevent (see kernel/memory/memory.asm's header).
    ; Zero the whole dictionary/stack/workspace RAM range ($8000
    ; through DICT_RAM_CEILING, core/free.asm) before anything below
    ; reads or writes into it, so nothing here can show leftover
    ; power-on garbage instead of a clean, empty system.
    ld   hl, $8000
    ld   bc, DICT_RAM_CEILING - $8000
    call MEM_FILL_ZERO

    ld   hl, DICT_LATEST_INIT_RECALL   ; the full chain's own head —
                                    ; see this file's own header (Phase
                                    ; 64 -- core/recall.asm's LIST-DEFS/
                                    ; RECALL -- spliced on after
                                    ; core/loadtext.asm's own tail)
    ld   (LATEST), hl

    ; Phase 64 (core/recall.asm): WORKSPACE_END starts undefined RAM at
    ; cold boot -- must be LOADTEXT_BUF (an empty workspace) before the
    ; first live-typed line's own WORKSPACE_APPEND call (core/editor.asm's
    ; EDITOR_LOOP_LIVE), or that call reads garbage and can write outside
    ; LOADTEXT_BUF entirely. A later LOAD-TEXT resets it again to cover
    ; exactly what it received (core/loadtext.asm's own W_LOADTEXT).
    ld   hl, LOADTEXT_BUF
    ld   (WORKSPACE_END), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a         ; core/doloop.asm's own LEAVE
                                   ; bookkeeping -- must start at 0
    ld   (CATCH_DEPTH), a         ; core/throwcatch.asm's own CATCH
                                   ; bookkeeping -- must start at 0
    ld   a, ATTR_DEFAULT          ; required since Phase 15 -- see
    ld   (CURRENT_ATTR), a        ; core/ts2068.asm's own header.
                                   ; kernel/graphics/graphics.asm's
                                   ; ATTR_DEFAULT ($44, black paper/
                                   ; bright green ink), NOT core/
                                   ; ts2068.asm's own DEFAULT_ATTR ($38,
                                   ; white paper/black ink) -- GFX_CLS
                                   ; just cleared the whole screen to
                                   ; ATTR_DEFAULT above, and EMIT (core/
                                   ; print.asm) stamps CURRENT_ATTR onto
                                   ; every printed character, so seeding
                                   ; it from the stale $38 constant made
                                   ; the first typed character (and
                                   ; every one after, until INK/PAPER is
                                   ; used) render white-paper/black-ink
                                   ; against the green-on-black screen
                                   ; GFX_CLS had just painted -- found
                                   ; live: text appeared black-on-white
                                   ; instead of the intended green-on-
                                   ; black terminal look
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

    ; Table-driven: every remaining event is either a SOUND_WRITE
    ; (register, value) pair or a CHIME_DELAY (tick count), walked from
    ; CHIME_TABLE below rather than unrolled inline -- byte-identical
    ; event sequence, same order, same values, just data instead of 27
    ; repeated `ld b,N:ld c,N:call SOUND_WRITE` / 11 repeated
    ; `ld b,N:call CHIME_DELAY` blocks. $FF as the first byte of a pair
    ; means "the second byte is a CHIME_DELAY tick count, not a
    ; register" -- safe, since SOUND_WRITE's own real register range is
    ; 1-16 (see its own header) and never reaches 255. $FE marks the
    ; table's end.
    ld   hl, CHIME_TABLE
.loop:
    ld   a, (hl)
    inc  hl
    cp   $FE
    ret  z
    cp   $FF
    jr   z, .delay
    ld   b, a
    ld   a, (hl)
    inc  hl
    ld   c, a
    call SOUND_WRITE
    jr   .loop
.delay:
    ld   a, (hl)
    inc  hl
    ld   b, a
    push hl                         ; CHIME_DELAY destroys HL (see its
    call CHIME_DELAY                ; own header) -- protect the table
    pop  hl                         ; pointer across the call
    jr   .loop

CHIME_TABLE:
    ; Channel A tone period coarse (period 421, C4 ~262 Hz); Channel B
    ; tone period fine/coarse (period 334, E4 ~330 Hz); Channel C tone
    ; period fine/coarse (period 281, G4 ~392 Hz); mixer (all three
    ; tones on, all noise off); all three channels silent until their
    ; own staggered attack below.
    DB   1,1,  2,78,  3,1,  4,25,  5,1,  7,248,  8,0,  9,0,  10,0
    ; ---- staggered, ramped attack: A rolls in first, then B, then C,
    ; each fading up over 3 steps instead of snapping to full volume --
    ; a $FF,3 pair is CHIME_DELAY 3 ticks, same gap used throughout ----
    DB   8,4,  $FF,3,  8,8,  $FF,3,  8,12, $FF,3   ; gap before B enters
    DB   9,4,  $FF,3,  9,8,  $FF,3,  9,12, $FF,3   ; gap before C enters
    DB   10,4, $FF,3,  10,8, $FF,3,  10,12         ; full chord now sounding
    DB   $FF,22                      ; hold the full chord ~440ms
    ; ---- release: all three fade down together ----
    DB   8,8,  9,8,  10,8,  $FF,3
    DB   8,4,  9,4,  10,4,  $FF,3
    DB   8,0,  9,0,  10,0            ; the AY holds its last register
                                     ; state indefinitely otherwise
    DB   $FE,0                       ; end of table

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
REPORT_INTERP_ERROR:              ; shared tail with RUNTIME_ERROR_HOOK's
                                   ; own .msgdone below -- byte-identical,
                                   ; merged rather than duplicated
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
    ; same fix as INTERPRET_UNKNOWN_WORD's own STATE reset -- an
    ; IMMEDIATE word's runtime error while compiling could otherwise
    ; leave STATE stuck too. Byte-identical to that routine's own tail,
    ; so shared via REPORT_INTERP_ERROR instead of duplicated here.
    jp   REPORT_INTERP_ERROR

RUNTIME_ERROR_MSG: DB "STACK?", 0

; ---- kernel + dictionary: included here, after the vector table and
; the boot code above, not before ORG $0000. DICT_CHAIN_POINT splices
; match rom/forth_smoke_p9.asm's own, already proven under Fuse. ----
    INCLUDE "kernel/memory/memory.asm"
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "kernel/storage/storage.asm"
    INCLUDE "kernel/mode64/mode64.asm"
    INCLUDE "kernel/bank/bank.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    DEFINE RUNTIME_ERROR_CHECK_ENABLED
    DEFINE THROW_CATCH_ENABLED
    DEFINE COMPILE_ONLY_CHECK_ENABLED   ; this is the live, interactive
                                        ; REPL -- the one ROM where a
                                        ; mistyped IF/DO/."/etc. at the
                                        ; prompt is a real, reachable
                                        ; case, not just a smoke-test
                                        ; hypothetical (see core/
                                        ; interp.asm's own header on
                                        ; this flag)
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
    INCLUDE "core/soundext.asm"
DICT_CHAIN_POINT DEFL H_ENVELOPE
    INCLUDE "core/compare.asm"
DICT_CHAIN_POINT DEFL H_GREATER
    INCLUDE "core/variable.asm"
DICT_CHAIN_POINT DEFL H_CONSTANT
    INCLUDE "core/dotquote.asm"
DICT_CHAIN_POINT DEFL H_DOTQUOTE
    INCLUDE "core/loop.asm"
DICT_CHAIN_POINT DEFL H_REPEAT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_FLASH
    INCLUDE "core/doloop.asm"
DICT_CHAIN_POINT DEFL H_I
    INCLUDE "core/loopext.asm"
DICT_CHAIN_POINT DEFL H_J
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/hires.asm"
DICT_CHAIN_POINT DEFL H_NORMAL
    INCLUDE "core/rectfill.asm"
DICT_CHAIN_POINT DEFL H_RECT
    INCLUDE "core/polygon.asm"
DICT_CHAIN_POINT DEFL H_POLYGONFILL
    INCLUDE "core/sprite.asm"
DICT_CHAIN_POINT DEFL H_SPRITEHIDE
    INCLUDE "core/key.asm"
DICT_CHAIN_POINT DEFL H_BREAKQ
    INCLUDE "core/mathfn.asm"
DICT_CHAIN_POINT DEFL H_SLASH
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
    DEFINE TRACK_WORKSPACE_END   ; opt in to core/loadtext.asm's
                                 ; WORKSPACE_END tracking -- see that
                                 ; file's own W_LOADTEXT comment on why
                                 ; this must be a per-ROM opt-in, not
                                 ; unconditional
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
DICT_CHAIN_POINT DEFL H_LOADTEXT
    INCLUDE "core/recall.asm"
DICT_CHAIN_POINT DEFL H_RECALL
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_boot_rom0.bin", $0000, $4000
