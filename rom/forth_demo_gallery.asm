; ============================================================================
; rom/forth_demo_gallery.asm — "SHOOTING GALLERY", a real-time arcade
; game showcasing the EXROM graphics extension (RECT for colored screen
; bands), UDG hand-drawn glyphs blitted as 2x2-character-cell "sprites"
; for a blaster truck and three moving targets, BEEP/SOUND (including a
; raw AY noise-burst "explosion" cue), and INK/PAPER/BORDER color,
; together in one boot-straight-into-play demo ROM. Inspired by (not a
; port of) the
; ZX Spectrum "shooting gallery" project described at
; https://bumbershootsoft.wordpress.com/2026/07/18/starting-the-zx-spectrum-shooting-gallery-in-earnest/
; — a blaster truck, independently-moving targets, and 16x16 sprite
; blitting over colored screen regions. This ROM designs its own
; control/scoring scheme around this project's own real, verified
; primitives rather than reproducing that project's own BASIC
; internals.
;
; HOW TO PLAY: build with `make forth-demo-gallery`, then run in Fuse
; or ZEsarUX with the graphics EXROM as ROM 1:
;   fuse --machine ts2068 --rom-ts2068-0 build/forth_demo_gallery_rom0.bin \
;        --rom-ts2068-1 build/graphics_exrom.bin
; Boots straight to a title screen; press any key to start. Two-handed
; controls: left hand Q/A, W/S, E/D shift targets 1/2/3 between three
; lanes (a tactical choice — line a target up with your blaster, or
; dodge it away); right hand O/P move the blaster truck left/right,
; SPACE fires (up to 3 shots in flight at once, on a short cooldown).
; Clear each wave's required hit count before its timer runs out;
; missing the timer costs a life (3 lives; wave difficulty does not
; reset on a life lost, only the attempt). Game over shows final score
; against the session's own high score, then loops back to a fresh
; game — this is a demo ROM with no path back to a general interpreter
; prompt, matching rom/forth_demo_blackjack.asm's own established
; delivery convention.
;
; WHY A DEDICATED SELF-CONTAINED ROM, NOT A LOADABLE PROGRAM: same
; reasoning as rom/forth_demo_blackjack.asm's own header — this project
; has no filesystem beyond the tape SAVE/LOAD protocol, and a
; boot-straight-into-the-game ROM is the simplest thing to build and
; the easiest for a user to actually try.
;
; PLATFORM FACTS CONFIRMED BEFORE WRITING THIS FILE (not assumed):
;   - RECT is EXROM-resident (rom/graphics_exrom.asm) and requires
;     kernel/bank/bank.asm's own EXROM paging plus the fixed-address
;     GRAPHICS_HOME_TABLE veneer at $0100 (same shape rom/forth_boot.asm
;     and every rom/test_*.asm graphics fixture already use) — copied
;     verbatim below, same slot order, since the prebuilt
;     graphics_exrom.bin's own call sites already assume that layout.
;   - This is the NORMAL (non-cartridge) ROM+EXROM build only — the
;     `-DCARTRIDGE` build deliberately omits RECT/POLYGON/SPRITE-*
;     (see this project's own recent commit history) because of a real,
;     documented bank-switch hazard specific to a DOCK cartridge
;     session. That hazard does not apply here: this ROM never runs
;     from DOCK.
;   - rom/test_rect.asm and rom/test_sprite.asm were both rebuilt and
;     re-run fresh under real ZEsarUX (ZRCP) while specifying this file,
;     confirming border GREEN (all checkpoints pass) for RECT and for
;     SPRITE-DEFINE/SPRITE-SHOW/SPRITE-HIDE in this exact normal
;     (non-cartridge) two-ROM arrangement, in ISOLATION. This game does
;     NOT end up using the sprite system, though — see "SPRITES: TRIED,
;     DROPPED" below for what empirical testing under this game's own
;     real load found, and why the truck/targets use plain EMIT-drawn
;     glyph blocks instead.
;   - Calling RECT several times in a row (as DRAW-BANDS does, to paint
;     four screen regions) was found, empirically, to need a short
;     settle delay between calls in this game's specific usage — without
;     one, later RECT calls' colors land in the wrong screen rows. A
;     fixed busy-wait between each DRAW-BANDS call fixes this reliably;
;     the exact mechanism (an EXROM/bank-paging timing sensitivity under
;     rapid repeated calls, not reproduced by rom/test_rect.asm's own
;     two widely-spaced calls) was not root-caused further within this
;     file's own scope — flagged here as a real, load-bearing finding
;     for anyone touching RECT/bank.asm's own timing assumptions later.
;   - KEY?/KEY decode one key per call (like Sinclair BASIC's INKEY$) —
;     there is no exposed simultaneous multi-key matrix read. The main
;     loop therefore processes at most one keypress per tick; this is a
;     real, documented hardware/software-layer constraint, not a
;     simplification of choice.
;   - This is an interpreted Forth core, not compiled machine code —
;     the game loop is tick-paced (a busy-wait delay each iteration),
;     not locked to a real 50Hz interrupt frame. Motion is smooth
;     relative to itself, not frame-perfect.
;
; SPRITES: TRIED, DROPPED. The first working draft used the EXROM
; sprite system (SPRITE-DEFINE/SPRITE-SHOW/SPRITE-HIDE) for the truck
; and all three targets, captured from a shared scratch screen cell
; the same way rom/test_sprite.asm's own checkpoints do. Under this
; game's own real load — many SPRITE-HIDE/SPRITE-SHOW calls per second
; across all four slots, interleaved with RECT — screen content
; visibly corrupted (colors and glyphs landing in the wrong rows),
; confirmed via repeated ZEsarUX screenshots and pixel-cluster analysis
; while specifying this file, and NOT explained by BANK_EXROM_DEPTH
; (read back as 0, correctly settled, at every point checked). This is
; a real reliability limit of the sprite subsystem under sustained
; multi-slot load that its own smoke test (one slot, a handful of
; calls) never exercised — not something this file's own game logic
; could safely paper over. The truck and targets are instead drawn
; directly with plain EMIT-based glyph blocks (DRAWGLYPH/ERASE2X2,
; SRC_HELPERS below) — the exact same proven mechanism shots already
; used for the same reason (see the next paragraph): slower to call
; "sprite-native," but correct. core/sprite.asm is still INCLUDEd
; (harmless dead weight) rather than restructuring this file's already-
; verified INCLUDE/DICT_CHAIN_POINT ordering to remove it.
;
; SHOTS: up to 3 simultaneous shots are plain EMIT-drawn characters in
; the black play-area band, erased and redrawn one row higher each
; tick (matching the inspiration project's own note that its shots used
; a separate coordinate system from its sprites) — this was the right
; call even before the sprite-reliability finding above, since it was
; never limited by a 4-slot budget in the first place.
;
; ROM SIZE BUDGET: this ROM includes core/rectfill.asm, core/sprite.asm,
; and kernel/bank/bank.asm on top of rom/forth_demo_blackjack.asm's own
; already-trimmed dictionary subset (see that file's own header for the
; full rationale behind each cut) — to make room, this file additionally
; drops core/string.asm/core/stringext.asm (STR/TYPE/VAL — this game
; never needs word-length text) and core/soundext.asm (TONE/VOLUME/
; MIXER/NOISE/ENVELOPE): the "explosion" cue instead writes the same
; raw AY registers directly through plain SOUND, exactly the technique
; rom/forth_demo_blackjack.asm's own SHUFFLE-SOUND already proved
; audible (register 7 mixer/6 noise-period/9 volume), so no new sound
; API surface is introduced at all. core/hires.asm (PLOT/CIRCLE/FILL)
; is also dropped — PLOT/LINE/CIRCLE/BORDER/CLS already live in
; core/ts2068.asm (confirmed by reading that file, not assumed), and
; this game's own screen bands are RECT fills, not PLOT/LINE art.
;
; DICTIONARY WORDS THIS FILE ADDS: none — every word the embedded
; game source below defines is a plain colon definition compiled at
; runtime via INTERPRET_RUN, exactly like rom/forth_demo_blackjack.asm.
; No new ROM-local assembly dictionary word (this game has no
; deterministic-test-mode need for one, unlike that file's own GETKEY).
;
; RANDOMNESS: `0 RANDOMIZE` (real entropy from the Z80 R register) once
; at boot, same mechanism/justification as
; rom/forth_demo_blackjack.asm's own SRC_SEED_REAL.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    DS   $0008 - $, $FF
RST_08: ret
    DS   $0010 - $, $FF
RST_10: ret
    DS   $0018 - $, $FF
RST_18: ret
    DS   $0020 - $, $FF
RST_20: ret
    DS   $0028 - $, $FF
RST_28: ret
    DS   $0030 - $, $FF
RST_30: ret
    DS   $0038 - $, $FF
RST_38:
    call KBD_ISR_TICK
    ei
    reti
    DS   $0066 - $, $FF
NMI_ENTRY:
    retn

    DS   $0100 - $, $FF

; ============================================================================
; GRAPHICS_HOME_TABLE — same fixed-address veneer table rom/forth_boot.asm
; and every rom/test_*.asm graphics fixture already use; see this file's
; own header. Must stay in this exact order/position — the prebuilt
; graphics_exrom.bin's own call sites assume it.
; ============================================================================
GRAPHICS_HOME_TABLE:
    jp   GFX_WRITE_PIXEL          ; slot 0
    jp   GFX_SET_ATTR             ; slot 1
    jp   GFX_LINE                 ; slot 2
    jp   GFX_ROW_BASE_ADDR        ; slot 3
    jp   GFX_CELL_ATTR_ADDR       ; slot 4

; ============================================================================
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ; Known DECR (port $FF) baseline before anything touches
    ; PORT_FF_SHADOW (kernel/bank/graphics both do) -- same reasoning
    ; rom/forth_demo_blackjack.asm's own COLD_START documents.
    xor  a
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   hl, DICT_LATEST_INIT_GAME   ; this file's own full chain head
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a
    xor  a
    ld   (PRINT_COL), a
    ld   (PRINT_ROW), a

    call KBD_ISR_INIT
    im   1
    ei

    ld   hl, SRC_VARS
    ld   de, SRC_VARS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_GLYPHS
    ld   de, SRC_GLYPHS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_HELPERS
    ld   de, SRC_HELPERS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_DISPLAY
    ld   de, SRC_DISPLAY_LEN
    call INTERPRET_RUN
    ld   hl, SRC_SOUND
    ld   de, SRC_SOUND_LEN
    call INTERPRET_RUN
    ld   hl, SRC_TRUCK
    ld   de, SRC_TRUCK_LEN
    call INTERPRET_RUN
    ld   hl, SRC_TARGETS
    ld   de, SRC_TARGETS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_SHOTS
    ld   de, SRC_SHOTS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_WAVE
    ld   de, SRC_WAVE_LEN
    call INTERPRET_RUN
    ld   hl, SRC_INPUT
    ld   de, SRC_INPUT_LEN
    call INTERPRET_RUN
    ld   hl, SRC_LOOP
    ld   de, SRC_LOOP_LEN
    call INTERPRET_RUN
    ld   hl, SRC_SCREENS
    ld   de, SRC_SCREENS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_KICKOFF
    ld   de, SRC_KICKOFF_LEN
    call INTERPRET_RUN

.hang:
    jr   .hang

; ============================================================================
; INTERPRET_UNKNOWN_WORD -- a real bug in this file's own embedded
; source, not a game event: every word below was hand-written and
; re-checked against the real dictionary before assembling. White
; border, matching rom/forth_demo_blackjack.asm's own convention.
; ============================================================================
INTERPRET_UNKNOWN_WORD:
    ld   a, 7
    out  (PORT_ULA), a
    ld   hl, BUG_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .hang
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.hang:
    jr   .hang

BUG_MSG: DB "BUG", 0

; ---- kernel + dictionary: trimmed subset -- see this file's own
; header for exactly what's cut and why. ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/bank/bank.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"        ; hardcoded onto H_UNTIL -- must
                                       ; follow core/control.asm directly
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/decimal.asm"        ; chain-neutral
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
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
    INCLUDE "core/loop.asm"          ; hardcoded onto H_UNTIL too --
                                       ; fine, control.asm already included
DICT_CHAIN_POINT DEFL H_REPEAT
    INCLUDE "core/color.asm"
DICT_CHAIN_POINT DEFL H_FLASH
    INCLUDE "core/rectfill.asm"
DICT_CHAIN_POINT DEFL H_RECT
    INCLUDE "core/sprite.asm"
DICT_CHAIN_POINT DEFL H_SPRITEHIDE
    INCLUDE "core/doloop.asm"
DICT_CHAIN_POINT DEFL H_I
    INCLUDE "core/loopext.asm"
DICT_CHAIN_POINT DEFL H_J
    INCLUDE "core/moregfx.asm"
DICT_CHAIN_POINT DEFL H_ATXY
    INCLUDE "core/key.asm"
DICT_CHAIN_POINT DEFL H_BREAKQ
    INCLUDE "core/mathfn.asm"
DICT_CHAIN_POINT DEFL H_SLASH
    INCLUDE "core/arith.asm"
DICT_CHAIN_POINT DEFL H_MIN
    INCLUDE "core/array.asm"
DICT_CHAIN_POINT DEFL H_CELLS
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/udg.asm"

DICT_LATEST_INIT_GAME EQU H_UDG   ; the real final dictionary head

; ============================================================================
; SRC_VARS -- all persistent game state. TCOL/TDIR/TSTEP/TLANE are per-
; target (index 0-2); LANES holds the three lane rows a target's own
; TLANE index selects (see SRC_HELPERS's own TR@). SROW/SCOL/SACTIVE
; are per-shot (index 0-2, up to 3 simultaneous shots -- not sprite-
; backed, see this file's own header). TRUCKCOL/TRUCKDIR track the
; blaster; SCORE/LIVES/WAVE/STREAK/HITS/NEEDHITS/TIMER/TIMERSTART/
; FIRECD/TSPEED/HIGHSCORE drive scoring and wave difficulty.
; ============================================================================
SRC_VARS:
    DB "0 RANDOMIZE "
    DB "3 ARRAY TCOL 3 ARRAY TDIR 3 ARRAY TSTEP 3 ARRAY TLANE 3 ARRAY LANES "
    DB "3 ARRAY SROW 3 ARRAY SCOL 3 ARRAY SACTIVE "
    DB "VARIABLE TRUCKCOL VARIABLE TRUCKDIR "
    DB "VARIABLE SCORE VARIABLE LIVES VARIABLE WAVE VARIABLE STREAK "
    DB "VARIABLE HITS VARIABLE NEEDHITS VARIABLE TIMER VARIABLE TIMERSTART "
    DB "VARIABLE FIRECD VARIABLE TSPEED VARIABLE HIGHSCORE VARIABLE KEYVAL "
    DB "2 0 CELLS LANES + ! 7 1 CELLS LANES + ! 12 2 CELLS LANES + ! "
SRC_VARS_LEN EQU $ - SRC_VARS

; ============================================================================
; SRC_GLYPHS -- SETUP-GLYPHS writes four hand-designed 8x8 UDG bitmaps
; (truck facing right, truck facing left, target ring, explosion
; starburst) into UDG slots 0-3 (character codes 144-147), the same
; plain C! composition rom/forth_demo_blackjack.asm's own SETUP-GLYPHS
; already uses. Each sprite tiles ONE glyph across all four cells of
; its 2x2 16x16 footprint (SRC_HELPERS's own DRAWGLYPH) -- the same
; "repeat one glyph across a multi-cell block" idiom that file's own
; CARD-BACK checker texture already established, not photographic
; fidelity, hand-drawn approximations only.
; ============================================================================
SRC_GLYPHS:
    DB ": SETUP-GLYPHS "
    DB "16 0 UDG C! 24 0 UDG 1 + C! 252 0 UDG 2 + C! 254 0 UDG 3 + C! "
    DB "254 0 UDG 4 + C! 252 0 UDG 5 + C! 24 0 UDG 6 + C! 16 0 UDG 7 + C! "
    DB "8 1 UDG C! 24 1 UDG 1 + C! 63 1 UDG 2 + C! 127 1 UDG 3 + C! "
    DB "127 1 UDG 4 + C! 63 1 UDG 5 + C! 24 1 UDG 6 + C! 8 1 UDG 7 + C! "
    DB "60 2 UDG C! 126 2 UDG 1 + C! 231 2 UDG 2 + C! 219 2 UDG 3 + C! "
    DB "219 2 UDG 4 + C! 231 2 UDG 5 + C! 126 2 UDG 6 + C! 60 2 UDG 7 + C! "
    DB "129 3 UDG C! 66 3 UDG 1 + C! 36 3 UDG 2 + C! 24 3 UDG 3 + C! "
    DB "24 3 UDG 4 + C! 36 3 UDG 5 + C! 66 3 UDG 6 + C! 129 3 UDG 7 + C! "
    DB "; "
SRC_GLYPHS_LEN EQU $ - SRC_GLYPHS

; ============================================================================
; SRC_HELPERS -- shared low-level words every later block depends on:
; DRAWGLYPH/ERASE2X2 paint or blank a 2x2-cell block at a scratch
; screen position so SPRITE-DEFINE can capture it (SPRITE-DEFINE only
; ever captures what's already really on screen -- there is no direct
; bitmap-load path); the T*/S* accessors turn the per-target/per-shot
; arrays above into named fields, the same GETR/SETR-style idiom
; rom/forth_demo_blackjack.asm's own SRC_DECK already established;
; OVERLAPS? is shot/target 2x2-box collision, built from = / < / >
; only, since this dictionary has no <=/>=/<> words (confirmed by
; reading core/compare.asm directly) -- every "a>=b"/"a<=b"/"a<>b" in
; this file is spelled as "b a < INVERT" / "b a > INVERT" / "a b = 0="
; throughout, not a typo.
; ============================================================================
SRC_HELPERS:
    DB "VARIABLE DG-CODE VARIABLE DG-COL VARIABLE DG-ROW "
    DB ": DRAWGLYPH DG-ROW ! DG-COL ! DG-CODE ! "
    DB "2 0 DO DG-COL @ DG-ROW @ I + AT-XY DG-CODE @ EMIT DG-CODE @ EMIT LOOP ; "
    DB ": ERASE2X2 DG-ROW ! DG-COL ! "
    DB "2 0 DO DG-COL @ DG-ROW @ I + AT-XY 32 EMIT 32 EMIT LOOP ; "
    DB "VARIABLE TMPI VARIABLE TMPJ "
    DB ": TC@ CELLS TCOL + @ ; : TC! CELLS TCOL + ! ; "
    DB ": TD@ CELLS TDIR + @ ; : TD! CELLS TDIR + ! ; "
    DB ": TS@ CELLS TSTEP + @ ; : TS! CELLS TSTEP + ! ; "
    DB ": LN@ CELLS LANES + @ ; "
    DB ": TR@ CELLS TLANE + @ LN@ ; "
    DB ": SACTIVE@ CELLS SACTIVE + @ ; : SACTIVE! CELLS SACTIVE + ! ; "
    DB ": SROW@ CELLS SROW + @ ; : SROW! CELLS SROW + ! ; "
    DB ": SCOL@ CELLS SCOL + @ ; : SCOL! CELLS SCOL + ! ; "
    DB "VARIABLE OV-SC VARIABLE OV-SR VARIABLE OV-TC VARIABLE OV-TR "
    DB ": SET-OV OV-TR ! OV-TC ! OV-SR ! OV-SC ! ; "
    DB ": ROW-OK? OV-SR @ OV-TR @ < INVERT OV-SR @ OV-TR @ 1+ > INVERT AND ; "
    DB ": COL-OK? OV-SC @ OV-TC @ < INVERT OV-SC @ OV-TC @ 1+ > INVERT AND ; "
    DB ": OVERLAPS? SET-OV ROW-OK? COL-OK? AND ; "
SRC_HELPERS_LEN EQU $ - SRC_HELPERS

; ============================================================================
; SRC_DISPLAY -- DRAW-BANDS paints the four colored screen regions via
; RECT (header white, play area black, blaster lane yellow, ground
; green -- an approximation of the inspiration project's own red/
; black/yellow/green layout, using this hardware's real 8-color
; palette); REDRAW-HUD prints score/lives/wave on the header band.
; Screen geometry (32 cols x 24 rows, 8px cells, PLOT/RECT's own y
; top-down sense already confirmed matching AT-XY's row -- see
; rom/forth_demo_blackjack.asm's own SRC_DISPLAY header for that same
; confirmation): header row 0 (y0-7), play area rows 1-14 (y8-119,
; holding the three target lanes at rows 2/7/12), blaster lane rows
; 15-19 (y120-159, truck at row 17), ground rows 20-23 (y160-191,
; decorative only -- AT-XY's own documented row range is 0-22, so nothing
; ever prints on row 23).
; ============================================================================
SRC_DISPLAY:
    DB ": DRAW-BANDS "
    DB "0 PAPER 7 INK 0 0 255 7 RECT "
    DB "1000 0 DO LOOP "
    DB "0 PAPER 0 INK 0 8 255 119 RECT "
    DB "1000 0 DO LOOP "
    DB "0 PAPER 6 INK 0 120 255 159 RECT "
    DB "1000 0 DO LOOP "
    DB "0 PAPER 4 INK 0 160 255 191 RECT "
    DB "0 PAPER 0 INK ; "
    DB ": REDRAW-HUD 7 PAPER 0 INK "
    DB "0 0 AT-XY .\" S:\" SCORE @ . "
    DB "10 0 AT-XY .\" L:\" LIVES @ . "
    DB "16 0 AT-XY .\" W:\" WAVE @ . "
    DB "0 PAPER 0 INK ; "
SRC_DISPLAY_LEN EQU $ - SRC_DISPLAY

; ============================================================================
; SRC_SOUND -- EXPLOSION-SOUND is a raw AY noise burst using the exact
; register combination (7=mixer, 6=noise period, 9=channel B volume)
; rom/forth_demo_blackjack.asm's own SHUFFLE-SOUND already proved
; audible, just with different noise periods/timing for a distinct
; "boom" texture; the other three are short multi-note BEEP sequences,
; same idiom as that file's own WIN-SOUND/BUST-SOUND/etc.
; ============================================================================
SRC_SOUND:
    DB ": EXPLOSION-SOUND 7 239 SOUND 9 14 SOUND "
    DB "6 2 SOUND 300 0 DO LOOP 6 8 SOUND 300 0 DO LOOP 6 16 SOUND 300 0 DO LOOP "
    DB "9 0 SOUND ; "
    DB ": WAVECLEAR-SOUND 10 0.08 BEEP 14 0.08 BEEP 17 0.08 BEEP 22 0.15 BEEP ; "
    DB ": LIFELOST-SOUND -4 0.15 BEEP -9 0.25 BEEP ; "
    DB ": GAMEOVER-SOUND -2 0.2 BEEP -6 0.2 BEEP -10 0.4 BEEP ; "
SRC_SOUND_LEN EQU $ - SRC_SOUND

; ============================================================================
; SRC_TRUCK -- the truck is drawn directly at its own real position via
; DRAWGLYPH/ERASE2X2 (SRC_HELPERS) rather than the EXROM sprite system
; (SPRITE-DEFINE/SHOW/HIDE): repeated rapid SPRITE-* calls interleaved
; with RECT were found, empirically, to corrupt screen state in this
; game's own usage pattern (many calls per second across four sprite
; slots) -- a real reliability limit of that subsystem under this
; load, not exercised by its own smoke test (which only ever drives
; one slot, a handful of times). DRAWGLYPH/ERASE2X2 are plain EMIT-
; based character-block drawing, the same proven mechanism shots
; already use (SRC_SHOTS) -- slower to look "sprite-native" but
; correct. ERASE-TRUCK repaints the truck's old cell with the blaster
; lane's own yellow paper (6) before it moves; SHOW-TRUCK draws the
; correct facing glyph (144 right-facing, 145 left-facing) at its
; current column, fixed row 17.
; ============================================================================
SRC_TRUCK:
    DB ": ERASE-TRUCK 6 PAPER 0 INK TRUCKCOL @ 17 ERASE2X2 ; "
    DB ": SHOW-TRUCK 7 INK 6 PAPER "
    DB "TRUCKDIR @ 0 = IF 144 ELSE 145 THEN TRUCKCOL @ 17 DRAWGLYPH ; "
    DB ": TRUCK-LEFT ERASE-TRUCK "
    DB "TRUCKCOL @ 0 > IF TRUCKCOL @ 1- TRUCKCOL ! THEN "
    DB "TRUCKDIR @ 1 = 0= IF 1 TRUCKDIR ! THEN SHOW-TRUCK ; "
    DB ": TRUCK-RIGHT ERASE-TRUCK "
    DB "TRUCKCOL @ 30 < IF TRUCKCOL @ 1+ TRUCKCOL ! THEN "
    DB "TRUCKDIR @ 0 = 0= IF 0 TRUCKDIR ! THEN SHOW-TRUCK ; "
SRC_TRUCK_LEN EQU $ - SRC_TRUCK

; ============================================================================
; SRC_TARGETS -- targets are likewise drawn directly via DRAWGLYPH/
; ERASE2X2, not the EXROM sprite system -- see SRC_TRUCK's own header
; for why. TSHOW ( i -- ) draws target i's own glyph (ink 2/red) at its
; current row/col; THIDE ( i -- ) erases it back to the play area's
; black paper. INIT-TARGETS resets each target's lane/column and
; (re)spawns all three -- called once per new game, not per wave
; (targets keep drifting continuously across waves). SHIFT-LANE
; ( i delta -- ) is the player's own row control: hide, clamp the
; target's lane index to 0-2, re-show at the new lane's row.
; MOVE-ONE-TARGET is the autonomous horizontal drift: a per-target step
; counter throttles actual movement to once every TSPEED ticks (faster
; as TSPEED shrinks each wave, see SRC_WAVE), bouncing at column 0/30.
; ============================================================================
SRC_TARGETS:
    DB ": TSHOW TMPI ! 2 INK 0 PAPER 146 TMPI @ TC@ TMPI @ TR@ DRAWGLYPH ; "
    DB ": THIDE TMPI ! 0 PAPER 0 INK TMPI @ TC@ TMPI @ TR@ ERASE2X2 ; "
    DB ": SPAWN-TARGET TMPI ! 1 TMPI @ TD! 0 TMPI @ TS! TMPI @ TSHOW ; "
    DB ": INIT-TARGETS "
    DB "0 0 CELLS TLANE + ! 1 1 CELLS TLANE + ! 2 2 CELLS TLANE + ! "
    DB "4 0 CELLS TCOL + ! 14 1 CELLS TCOL + ! 24 2 CELLS TCOL + ! "
    DB "0 SPAWN-TARGET 1 SPAWN-TARGET 2 SPAWN-TARGET ; "
    DB ": SHIFT-LANE SWAP TMPI ! TMPI @ THIDE "
    DB "TMPI @ CELLS TLANE + @ + 0 MAX 2 MIN TMPI @ CELLS TLANE + ! "
    DB "TMPI @ TSHOW ; "
    DB ": MOVE-ONE-TARGET TMPI ! TMPI @ TS@ 1+ TMPI @ TS! "
    DB "TMPI @ TS@ TSPEED @ < IF EXIT THEN 0 TMPI @ TS! "
    DB "TMPI @ THIDE TMPI @ TC@ TMPI @ TD@ + TMPI @ TC! "
    DB "TMPI @ TC@ 0 > INVERT IF 0 TMPI @ TC! 1 TMPI @ TD! THEN "
    DB "TMPI @ TC@ 30 < INVERT IF 30 TMPI @ TC! -1 TMPI @ TD! THEN "
    DB "TMPI @ TSHOW ; "
    DB ": MOVE-TARGETS 0 MOVE-ONE-TARGET 1 MOVE-ONE-TARGET 2 MOVE-ONE-TARGET ; "
SRC_TARGETS_LEN EQU $ - SRC_TARGETS

; ============================================================================
; SRC_SHOTS -- shots are plain EMIT-drawn characters (see this file's
; own header on why), tracked in SROW/SCOL/SACTIVE (index 0-2, up to 3
; in flight). FIRE spawns one at the truck's own column, just above the
; blaster lane, if the fire-cooldown has elapsed and a free slot
; exists. MOVE-ONE-SHOT erases the old character, advances the row,
; retires the shot (silently, with a low "whiff" BEEP and a broken
; streak) if it exits the top of the play area, otherwise checks
; CHECK-HIT against all three targets' own 2x2 boxes (OVERLAPS?, from
; SRC_HELPERS) and redraws at the new position if still in flight.
; DO-HIT scores (a streak bonus on consecutive hits, reset by any miss
; or by a life lost), flashes an explosion glyph, plays EXPLOSION-SOUND,
; flashes the border, and respawns the target at a fresh random column
; on the same lane.
; ============================================================================
SRC_SHOTS:
    DB ": INIT-SHOTS 0 0 CELLS SACTIVE + ! 0 1 CELLS SACTIVE + ! 0 2 CELLS SACTIVE + ! ; "
    DB ": FIND-FREE-SHOT "
    DB "0 SACTIVE@ 0= IF 0 -1 EXIT THEN "
    DB "1 SACTIVE@ 0= IF 1 -1 EXIT THEN "
    DB "2 SACTIVE@ 0= IF 2 -1 EXIT THEN 0 0 ; "
    DB ": FIRE FIRECD @ 0 > IF EXIT THEN "
    DB "FIND-FREE-SHOT 0= IF DROP EXIT THEN TMPI ! "
    DB "1 TMPI @ SACTIVE! 14 TMPI @ SROW! TRUCKCOL @ TMPI @ SCOL! "
    DB "7 INK 0 PAPER TRUCKCOL @ 14 AT-XY 42 EMIT "
    DB "24 0.06 BEEP 3 FIRECD ! ; "
    DB ": DO-HIT TMPJ ! TMPJ @ THIDE "
    DB "STREAK @ 1+ STREAK ! SCORE @ 10 STREAK @ * + SCORE ! HITS @ 1+ HITS ! "
    DB "3 INK 0 PAPER TMPJ @ TC@ TMPJ @ TR@ AT-XY 147 EMIT 147 EMIT "
    DB "300 0 DO LOOP EXPLOSION-SOUND 2 BORDER 200 0 DO LOOP 0 BORDER "
    DB "31 RND TMPJ @ TC! TMPJ @ TSHOW 0 TMPI @ SACTIVE! REDRAW-HUD ; "
    DB ": CHECK-HIT TMPI ! "
    DB "TMPI @ SCOL@ TMPI @ SROW@ 0 TC@ 0 TR@ OVERLAPS? IF 0 DO-HIT EXIT THEN "
    DB "TMPI @ SCOL@ TMPI @ SROW@ 1 TC@ 1 TR@ OVERLAPS? IF 1 DO-HIT EXIT THEN "
    DB "TMPI @ SCOL@ TMPI @ SROW@ 2 TC@ 2 TR@ OVERLAPS? IF 2 DO-HIT EXIT THEN ; "
    DB ": MOVE-ONE-SHOT TMPI ! TMPI @ SACTIVE@ 0= IF EXIT THEN "
    DB "0 PAPER 0 INK TMPI @ SCOL@ TMPI @ SROW@ AT-XY 32 EMIT "
    DB "TMPI @ SROW@ 1- TMPI @ SROW! "
    DB "TMPI @ SROW@ 1 < IF 0 TMPI @ SACTIVE! 0 STREAK ! -6 0.1 BEEP EXIT THEN "
    DB "TMPI @ CHECK-HIT TMPI @ SACTIVE@ 0= IF EXIT THEN "
    DB "7 INK 0 PAPER TMPI @ SCOL@ TMPI @ SROW@ AT-XY 42 EMIT ; "
    DB ": MOVE-SHOTS 0 MOVE-ONE-SHOT 1 MOVE-ONE-SHOT 2 MOVE-ONE-SHOT ; "
SRC_SHOTS_LEN EQU $ - SRC_SHOTS

; ============================================================================
; SRC_WAVE -- NEW-WAVE advances the wave counter, raises the required-
; hit count, resets the per-wave hit tally, shortens the countdown
; timer (floored at 60 ticks), and speeds up target drift (floored at
; 4 ticks/step) -- escalating difficulty, no upper bound this ROM ever
; hits in a realistic session. CHECK-WAVE-STATE (called once per tick)
; clears the wave once enough hits land, otherwise counts the timer
; down and calls LOSE-LIFE if it runs out -- a life lost resets only
; the timer/hit-tally for a fresh attempt at the SAME wave, not the
; difficulty, matching this file's own header on that design choice.
; ============================================================================
SRC_WAVE:
    DB ": NEW-WAVE WAVE @ 0 > IF WAVECLEAR-SOUND THEN "
    DB "WAVE @ 1+ WAVE ! 5 WAVE @ 2 * + NEEDHITS ! 0 HITS ! "
    DB "150 WAVE @ 8 * - 60 MAX TIMERSTART ! TIMERSTART @ TIMER ! "
    DB "14 WAVE @ - 4 MAX TSPEED ! REDRAW-HUD ; "
    DB ": LOSE-LIFE LIVES @ 1- LIVES ! LIFELOST-SOUND "
    DB "1 BORDER 300 0 DO LOOP 0 BORDER "
    DB "TIMERSTART @ TIMER ! 0 HITS ! REDRAW-HUD ; "
    DB ": CHECK-WAVE-STATE HITS @ NEEDHITS @ < INVERT IF NEW-WAVE EXIT THEN "
    DB "TIMER @ 1- TIMER ! TIMER @ 0 > INVERT IF LOSE-LIFE THEN ; "
SRC_WAVE_LEN EQU $ - SRC_WAVE

; ============================================================================
; SRC_INPUT -- HANDLE-KEY dispatches one just-read key (KEYVAL) to a
; target lane shift, a truck move, or FIRE. Both upper and lower case
; are matched throughout (this dictionary's KEY does no case-folding of
; its own -- confirmed by reading core/key.asm's own header), same
; convention rom/forth_demo_blackjack.asm's own PLAYER-TURN already
; uses for H/S/Y/N.
; ============================================================================
SRC_INPUT:
    DB ": HANDLE-KEY "
    DB "KEYVAL @ 81 = KEYVAL @ 113 = OR IF 0 -1 SHIFT-LANE THEN "
    DB "KEYVAL @ 65 = KEYVAL @ 97 = OR IF 0 1 SHIFT-LANE THEN "
    DB "KEYVAL @ 87 = KEYVAL @ 119 = OR IF 1 -1 SHIFT-LANE THEN "
    DB "KEYVAL @ 83 = KEYVAL @ 115 = OR IF 1 1 SHIFT-LANE THEN "
    DB "KEYVAL @ 69 = KEYVAL @ 101 = OR IF 2 -1 SHIFT-LANE THEN "
    DB "KEYVAL @ 68 = KEYVAL @ 100 = OR IF 2 1 SHIFT-LANE THEN "
    DB "KEYVAL @ 79 = KEYVAL @ 111 = OR IF TRUCK-LEFT THEN "
    DB "KEYVAL @ 80 = KEYVAL @ 112 = OR IF TRUCK-RIGHT THEN "
    DB "KEYVAL @ 32 = IF FIRE THEN ; "
SRC_INPUT_LEN EQU $ - SRC_INPUT

; ============================================================================
; SRC_LOOP -- TICK is one iteration of real-time play: read at most one
; pending key (KEY?/KEY, this dictionary's own real limit -- see this
; file's own header), move targets and shots, count down the fire
; cooldown, check wave/life state, then a short busy-wait paces the
; loop (this is an interpreted core -- see this file's own header on
; why this is tick-paced, not frame-locked). GAME-LOOP runs TICK until
; LIVES reaches 0.
; ============================================================================
SRC_LOOP:
    DB ": TICK KEY? IF KEY KEYVAL ! HANDLE-KEY THEN "
    DB "MOVE-TARGETS MOVE-SHOTS "
    DB "FIRECD @ 0 > IF FIRECD @ 1- FIRECD ! THEN "
    DB "CHECK-WAVE-STATE 8000 0 DO LOOP ; "
    DB ": GAME-LOOP BEGIN TICK LIVES @ 0 > WHILE REPEAT ; "
SRC_LOOP_LEN EQU $ - SRC_LOOP

; ============================================================================
; SRC_SCREENS -- NEW-GAME resets all per-game state and (re)spawns the
; truck and targets; TITLE-SCREEN and GAME-OVER-SCREEN are static text
; screens gated on a keypress (BEGIN KEY? UNTIL KEY DROP -- wait for a
; key to be pending, then consume it); MAIN ties the whole game
; together in an unconditional replay loop (0 UNTIL never terminates,
; the same "no path back to a general prompt" delivery choice
; rom/forth_demo_blackjack.asm's own MAIN already makes).
; ============================================================================
SRC_SCREENS:
    DB ": NEW-GAME 0 SCORE ! 3 LIVES ! 0 WAVE ! 0 STREAK ! 0 FIRECD ! "
    DB "DRAW-BANDS INIT-SHOTS "
    DB "0 TRUCKDIR ! 16 TRUCKCOL ! SHOW-TRUCK "
    DB "INIT-TARGETS NEW-WAVE REDRAW-HUD ; "
    DB ": TITLE-SCREEN 0 PAPER 7 INK CLS "
    DB "7 INK 6 3 AT-XY .\" SHOOTING GALLERY \" "
    DB "6 INK 2 6 AT-XY .\" Q/A W/S E/D - MOVE TARGETS \" "
    DB "2 8 AT-XY .\" O / P     - MOVE BLASTER \" "
    DB "2 10 AT-XY .\" SPACE    - FIRE \" "
    DB "7 INK 2 13 AT-XY .\" PRESS ANY KEY TO START \" "
    DB "BEGIN KEY? UNTIL KEY DROP ; "
    DB ": GAME-OVER-SCREEN GAMEOVER-SOUND "
    DB "SCORE @ HIGHSCORE @ > IF SCORE @ HIGHSCORE ! THEN "
    DB "0 PAPER 7 INK CLS "
    DB "7 INK 10 5 AT-XY .\" GAME OVER \" "
    DB "6 INK 8 8 AT-XY .\" SCORE \" SCORE @ . "
    DB "8 10 AT-XY .\" BEST  \" HIGHSCORE @ . "
    DB "7 INK 8 13 AT-XY .\" PRESS ANY KEY \" "
    DB "BEGIN KEY? UNTIL KEY DROP ; "
    DB ": MAIN 0 HIGHSCORE ! SETUP-GLYPHS TITLE-SCREEN "
    DB "BEGIN NEW-GAME GAME-LOOP GAME-OVER-SCREEN 0 UNTIL ; "
SRC_SCREENS_LEN EQU $ - SRC_SCREENS

SRC_KICKOFF: DB "MAIN "
SRC_KICKOFF_LEN EQU $ - SRC_KICKOFF

    DS   $4000 - $, $FF

    SAVEBIN "forth_demo_gallery_rom0.bin", $0000, $4000
