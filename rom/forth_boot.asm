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
; (0=/IF/ELSE/THEN/BEGIN/UNTIL, PLOT/LINE/CIRCLE/BEEP/BORDER,
; SAVE/LOAD, F+/F-/F*/F/, 64COL/32COL/PALETTE64/PLOT64, EMIT/., =/</>,
; VARIABLE/CONSTANT, .", WHILE/REPEAT, INK/PAPER, DO/LOOP/I,
; FILL/AT-XY, KEY, F.), chained into one LATEST list via the same
; DICT_CHAIN_POINT splices rom/forth_smoke_p9.asm introduced and
; proved. DECIMAL_NUMBER_ENABLED is also DEFINEd here (core/decimal.asm,
; Phase 23) — not a dictionary word, a NUMBER/INTERPRET_RUN parsing
; capability: typing a literal like `3.5` now pushes a real float
; directly, in both interpret and compile contexts.
;
; WHAT ISN'T HERE YET, stated plainly: no live automated test exercises
; the interactive loop this file actually boots into — by its nature,
; that needs a real or simulated keyboard, not a fixed source string.
; Manual confirmation in Fuse (or real hardware) with an actual keyboard
; remains the honest gap, exactly as core/editor.asm's own header
; already says for EDITOR_LOOP_LIVE. The startup sound is BEEP's own
; existing raw hardware-timing units (kernel/sound's SOUND_BEEP), not a
; considered musical choice — a real, open follow-up, not hidden.
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

    ld   hl, DICT_LATEST_INIT_KEY   ; the full chain's own head — see
                                    ; this file's own header
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   a, DEFAULT_ATTR          ; required since Phase 15 -- see
    ld   (CURRENT_ATTR), a        ; core/ts2068.asm's own header

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

    ld   bc, 100                    ; pitch: short, high-ish tone --
    ld   de, 30                     ; duration: brief, not a
    call SOUND_BEEP                 ; considered musical choice, see
                                    ; this file's own header

    call KBD_ISR_INIT               ; must run before EI -- confirmed
                                    ; 2068-Leap ordering
    im   1
    ei

    jp   EDITOR_LOOP_LIVE

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
    ld   hl, "?"
    call DPUSH_HL
    call W_EMIT
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT
    ret

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
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_BORDER
    INCLUDE "core/storage.asm"
DICT_CHAIN_POINT DEFL H_LOAD
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
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/key.asm"
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_boot_rom0.bin", $0000, $4000
