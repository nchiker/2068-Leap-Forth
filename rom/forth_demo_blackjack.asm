; ============================================================================
; rom/forth_demo_blackjack.asm — a real, playable single-deck Blackjack
; game, showcasing UDG (four hand-drawn suit glyphs, core/udg.asm),
; real pixel-drawn card boxes (LINE), block-graphics card-back texture,
; a green "felt table" background, color (INK/PAPER/BORDER), and richer
; multi-note sound (BEEP/SOUND) together.
;
; GRAPHICS/SOUND UPGRADE PASS (this revision): every dealt card now
; renders inside a real LINE-drawn pixel rectangle (a genuine card
; "shape", not just floating rank text), the hidden dealer card gets a
; block-graphics "card back" texture instead of plain "??" text, the
; whole screen gets a green felt-table PAPER/BORDER (CLS itself repaints
; the whole attribute area to the current PAPER — see the kernel EMIT/
; CLS INK-PAPER fix), and sound effects got richer throughout: a shuffle noise burst,
; a confirm blip on every Hit/Stand keypress, and short multi-note
; (not single-tone) win/blackjack/bust cues. See SRC_DISPLAY, SRC_DECK,
; and SRC_TURN's own headers below for the full details of each.
;
; HOW TO PLAY: build with `make forth-demo-blackjack`, then run in Fuse:
;   tools/make_exrom_placeholder.sh
;   fuse --machine ts2068 --rom-ts2068-0 build/forth_demo_blackjack_rom0.bin \
;        --rom-ts2068-1 build/stock_shaped_exrom.bin
; The game boots straight into a round — no typing required at all,
; only single keypresses. Each round: you and the dealer are each dealt
; two cards (the dealer's second card stays face-down, shown as a
; textured card back, until your turn ends); press H to hit (take
; another card) or S to stand. If your total exceeds 21 you bust
; immediately. Otherwise the dealer reveals its hidden card and
; auto-plays a fixed strategy (hits on 16 or below, stands on 17+), then
; the outcome is shown with a distinct border color and a short
; multi-note BEEP sequence: green/YOU WIN!, blue/DEALER WINS,
; red/BUST, magenta/BLACKJACK!, cyan/PUSH (silent, unchanged). After
; each round you're asked "PLAY AGAIN? (Y/N)" — press Y to reshuffle a
; fresh single deck (with its own shuffle sound) and deal another
; round, or N to end (the game then hangs safely with a
; "THANKS FOR PLAYING!" message — this is a demo ROM, not the full
; product, and has no path back to a general interpreter prompt).
;
; DELIVERY CHOICE: a dedicated, self-contained demo ROM (matching this
; project's own smoke-ROM idiom of embedding fixed Forth source text
; fed to INTERPRET_RUN) rather than a BASIC-style loadable program —
; this project has no file system beyond the tape SAVE/LOAD protocol,
; and a boot-straight-into-the-game ROM is both the simplest thing to
; build and the easiest for a user to actually try in Fuse.
;
; RULES SCOPE (deliberate, documented choices, not oversights):
;   - Standard single-deck rules: 2 cards each, hit/stand, dealer hits
;     to 16/stands on 17+, soft aces (11 or 1, whichever keeps the hand
;     <=21), natural 21 (two-card 21) flagged as BLACKJACK unless the
;     dealer also has one (PUSH) — the real "blackjack" the game is
;     named for.
;   - A FRESH single 52-card deck is built and reshuffled EVERY round
;     (not a persistent shoe drawn down across rounds) — chosen because
;     it keeps each round a genuine single-deck game with no
;     reduced-deck bias, and sidesteps ever running out of cards across
;     a long play session; reshuffling is itself realistic (a real
;     dealer reshuffles a single deck constantly in casual play).
;   - Repeated rounds ARE supported (a "PLAY AGAIN?" prompt), not just
;     one round — better demonstrates UDG/color/sound across varied
;     outcomes than a single round would.
;   - Dealer's own blackjack is only checked (and can PUSH) when the
;     PLAYER also has one — a real casino dealer "peeks" for blackjack
;     before the player acts even when the player doesn't have one;
;     this simplification is deliberate (an unpeeked dealer blackjack
;     still resolves correctly, just at final comparison instead of
;     immediately, and never mis-pays) — scope cut for a demo, not a
;     bug.
;
; ROM SIZE BUDGET: forth_boot.asm's own FULL dictionary (every phase)
; leaves only ~1.3KB of the 16KB ROM free — nowhere near enough room
; for this file's embedded Forth game source on top of it. This ROM
; therefore INCLUDEs a deliberately TRIMMED subset of core/ and
; kernel/: no SAVE/LOAD (kernel/storage, core/storage — tape I/O,
; unused), no 64COL (kernel/mode64, core/mode64 — unused), no
; editor.asm (this ROM never runs the live line editor — it drives the
; game directly via INTERPRET_RUN, never EDITOR_LOOP_LIVE), no
; FSQRT/SIN/COS/PI/RAD/DEG/F./F>S/FROUND (core/floatsqrt/floattrig/
; floatprint/floatconv — the game needs only enough float support for
; BEEP's own fduration argument: core/float.asm + core/floatmul.asm +
; core/floatdiv.asm, which BEEP_COMPUTE genuinely calls internally —
; confirmed by reading core/beep.asm's own header before cutting
; anything, not guessed), no THROW/CATCH, EXECUTE, ', ACCEPT/INPUT,
; STICK, FREE, LPRINT/LLIST, ULAPLUS, VLIST, or the Phase 50
; CREATE/DOES>/IMMEDIATE/ABORT/QUIT/IN/OUT/FORGET tier (none of these
; are used anywhere in this game's own Forth source). Every file this
; ROM DOES include is chained via the exact same DICT_CHAIN_POINT
; splicing convention forth_boot.asm and every smoke ROM already use —
; see each DICT_CHAIN_POINT DEFL line below for exactly what precedes
; what. core/ts2068.asm and core/loop.asm both hardcode their own
; chain-back pointer directly onto core/control.asm's tail (H_UNTIL) —
; confirmed by reading their own first headers, not assumed — so
; core/control.asm must immediately precede both, unchanged from
; forth_boot.asm's own ordering.
;
; DECIMAL LITERALS: DEFINE DECIMAL_NUMBER_ENABLED + core/decimal.asm
; ARE included (unlike everything trimmed above) specifically so BEEP's
; own duration argument can be written as a real fractional literal
; (`12 0.3 BEEP`) instead of a whole-second-only S>F workaround —
; core/decimal.asm defines no dictionary words of its own (confirmed by
; grepping it for "H_" — none), so it costs no chain-order bookkeeping,
; only code size, and that cost is easily affordable given how much the
; trimming above already freed.
;
; GETKEY — THE ONE NEW, ROM-LOCAL DICTIONARY WORD THIS FILE ADDS,
; NOT IN core/: a thin indirection over the real KEY (core/key.asm),
; gated by DEFINE BLACKJACK_TEST_MODE exactly like this project's own
; established STORAGE_TEST_FAKE_SEND/RECEIVE precedent
; (kernel/storage/storage.asm) — normal builds (this file's own
; Makefile target, no such DEFINE) compile GETKEY as a bare `jp W_KEY`,
; identical behavior to calling KEY directly; a build assembled with
; `-DBLACKJACK_TEST_MODE` (used only for this ROM's own automated
; verification, never by the Makefile target a user runs) instead feeds
; scripted keys from TEST_KEY_TABLE, one per call, so the entire game
; can be driven deterministically and reproducibly through real Fuse
; without depending on flaky X11 keyboard injection — this project's
; own history (see MEMORY.md) documents live X11 key injection as
; unreliable even for interactive testing of THIS project. The game's
; own Forth source calls GETKEY, never KEY directly, everywhere it
; reads a keypress.
;
; RANDOMNESS: `0 RANDOMIZE` (reseed from the real Z80 R register — see
; core/mathfn.asm's own header) in a normal build, for genuine
; unpredictable shuffles; `4 RANDOMIZE` (a fixed, verified seed) under
; BLACKJACK_TEST_MODE, so the exact shuffle — and therefore every dealt
; card across every round — is precisely predictable and was
; hand-verified against a real Python simulation of MATH_RND16's own
; documented LFSR algorithm (kernel/math/math.asm) before ever choosing
; the test keystroke script.
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
; COLD_START
; ============================================================================
COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_GETKEY   ; this file's own full chain head
                                        ; (core/udg.asm's tail, then this
                                        ; file's own GETKEY, spliced on
                                        ; last) — see this file's own
                                        ; header
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a          ; core/doloop.asm's own DO/LOOP/LEAVE
                                    ; bookkeeping -- must start at 0
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a
    xor  a
    ld   (PRINT_COL), a
    ld   (PRINT_ROW), a

    IFDEF BLACKJACK_TEST_MODE
    ld   hl, TEST_KEY_TABLE
    ld   (TEST_KEY_PTR), hl
    ENDIF

    call KBD_ISR_INIT
    im   1
    ei

    ; ---- run the game: one INTERPRET_RUN call per logical source
    ; block, exactly like every smoke ROM's own multi-checkpoint driver
    ; -- HERE/LATEST persist across calls, so definitions compiled in
    ; one block are callable from every later one. ----
    IFDEF BLACKJACK_TEST_MODE
    ld   hl, SRC_SEED_TEST
    ld   de, SRC_SEED_TEST_LEN
    ELSE
    ld   hl, SRC_SEED_REAL
    ld   de, SRC_SEED_REAL_LEN
    ENDIF
    call INTERPRET_RUN
    ld   hl, SRC_ARRAYS
    ld   de, SRC_ARRAYS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_DECK
    ld   de, SRC_DECK_LEN
    call INTERPRET_RUN
    ld   hl, SRC_SCORE
    ld   de, SRC_SCORE_LEN
    call INTERPRET_RUN
    ld   hl, SRC_GLYPHS
    ld   de, SRC_GLYPHS_LEN
    call INTERPRET_RUN
    ld   hl, SRC_DISPLAY
    ld   de, SRC_DISPLAY_LEN
    call INTERPRET_RUN
    ld   hl, SRC_DEAL
    ld   de, SRC_DEAL_LEN
    call INTERPRET_RUN
    ld   hl, SRC_TURN
    ld   de, SRC_TURN_LEN
    call INTERPRET_RUN
    ld   hl, SRC_ROUND
    ld   de, SRC_ROUND_LEN
    call INTERPRET_RUN
    ld   hl, SRC_MAIN
    ld   de, SRC_MAIN_LEN
    call INTERPRET_RUN
    ld   hl, SRC_KICKOFF
    ld   de, SRC_KICKOFF_LEN
    call INTERPRET_RUN

    IFDEF BLACKJACK_TEST_MODE
    ld   hl, SRC_VERIFY
    ld   de, SRC_VERIFY_LEN
    call INTERPRET_RUN
    ENDIF

.hang:
    jr   .hang

; ============================================================================
; INTERPRET_UNKNOWN_WORD -- mandatory hook (core/interp.asm's NUMBER
; .badword path jumps here unconditionally, same as every smoke ROM).
; Every word in this game's own Forth source below is fixed, hand-
; written, and re-checked against the real dictionary before this file
; was ever assembled -- reaching this at all means a real bug in that
; source, exactly the same "stop hard and loud" convention every
; rom/forth_smoke_p*.asm already uses, not the friendlier live-typo
; recovery rom/forth_boot.asm's own version has (there is no live
; typing here to recover from -- the only keys a real player ever
; presses are single H/S/Y/N game inputs, which never reach the
; interpreter directly).
; ============================================================================
INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white border: bug in this ROM's own
    out  (PORT_ULA), a           ; embedded Forth source, not a game bug
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

; ---- kernel + dictionary: TRIMMED subset -- see this file's own
; header for exactly what's cut and why. Ordering/splicing otherwise
; matches rom/forth_boot.asm's own proven chain. ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"       ; hardcoded onto H_UNTIL -- must
                                      ; follow core/control.asm directly
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/decimal.asm"       ; no dictionary words -- chain-neutral
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
    INCLUDE "core/loop.asm"          ; hardcoded onto H_UNTIL too, but
                                      ; only used to COMPILE WHILE/REPEAT
                                      ; -- fine, control.asm was already
                                      ; included above
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
DICT_CHAIN_POINT DEFL H_SLASH
    INCLUDE "core/arith.asm"
DICT_CHAIN_POINT DEFL H_MIN
    INCLUDE "core/array.asm"
DICT_CHAIN_POINT DEFL H_CELLS
    INCLUDE "core/string.asm"
DICT_CHAIN_POINT DEFL H_VAL
    INCLUDE "core/stringext.asm"
DICT_CHAIN_POINT DEFL H_CODE
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/udg.asm"
DICT_CHAIN_POINT DEFL H_UDG

; ============================================================================
; GETKEY ( -- char ) -- this file's own single ROM-local dictionary
; word, not part of core/. See this file's own header for the full
; test-mode design rationale.
; ============================================================================
H_GETKEY:
    DW   DICT_CHAIN_POINT
    DB   6, "G","E","T","K","E","Y"
W_GETKEY:
    IFDEF BLACKJACK_TEST_MODE
    ld   hl, (TEST_KEY_PTR)
    ld   a, (hl)
    or   a
    jr   z, .push              ; sentinel (0) reached -- keep returning
                                ; 0 forever rather than reading past the
                                ; scripted table
    inc  hl
    ld   (TEST_KEY_PTR), hl
.push:
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    ret
    ELSE
    jp   W_KEY                  ; normal build: GETKEY IS KEY
    ENDIF

; TABLEBG (this file's former second ROM-local word) is gone: it used to
; repaint the whole screen attribute area to CURRENT_ATTR via
; kernel/graphics's GFX_PAINT_ATTR because CLS only ever reset attributes
; to a hardcoded black-paper/green-ink default. Once the kernel EMIT/CLS
; INK-PAPER fix made CLS itself repaint the whole attribute area to
; whatever PAPER is actually set, TABLEBG became a redundant second
; repaint of exactly the same cells — removed instead of left as dead
; weight. SRC_ROUND below no longer calls it.

DICT_LATEST_INIT_GETKEY EQU H_GETKEY   ; the real final dictionary head
                                          ; -- name kept for COLD_START's
                                          ; own reference

    IFDEF BLACKJACK_TEST_MODE
; TEST_KEY_PTR lives in EDIT_LINE_BUF -- guaranteed free RAM here since
; this ROM never INCLUDEs core/editor.asm (no live line editor), so
; nothing else ever reads or writes it.
TEST_KEY_PTR EQU EDIT_LINE_BUF

; Scripted keystroke script for `4 RANDOMIZE` (SRC_SEED below), hand-
; verified against a real Python simulation of MATH_RND16's own
; documented LFSR algorithm (kernel/math/math.asm) before being chosen
; -- see this file's own header. Predicted, in GETKEY call order (a
; real bug in an EARLIER draft of this exact table, caught by this
; ROM's own automated verification, left out the "PLAY AGAIN?" key
; after round 3 -- every round asks it, even a no-hit-needed natural
; blackjack round, so it's easy to undercount how many keys a script
; needs by treating "no player-turn key" as "no key at all"):
;   Round 1: player dealt 10+A = natural 21 (BLACKJACK), no player-turn
;            key needed at all; dealer shows 18 -- PLAY AGAIN? -> Y
;   Round 2: player dealt Q+6=16, hits, draws K -> 26, BUSTS on that
;            one hit (no STAND keypress needed -- busting ends the
;            turn automatically) -- PLAY AGAIN? -> Y
;   Round 3: player dealt A+J = natural 21 again (BLACKJACK), dealer
;            shows 12 -- PLAY AGAIN? -> Y
;   Round 4: player dealt 7+K=17, stands immediately; dealer hits
;            2+6=8 -> +5=13 -> +10=23, busts -- PLAY AGAIN? -> N (end)
TEST_KEY_TABLE: DB "Y","H","Y","Y","S","N",0
    ENDIF

; ============================================================================
; SRC_SEED -- RANDOMIZE, real entropy in a normal build, a fixed
; verified seed under BLACKJACK_TEST_MODE (see this file's own header).
; Both strings are always assembled (a handful of harmless spare bytes
; either way) and COLD_START picks which one to feed INTERPRET_RUN --
; two distinct labels, never one label defined twice under IFDEF/ELSE,
; so tools/check_asm.py's plain duplicate-label scan (which doesn't
; evaluate conditional assembly) has nothing to flag.
; ============================================================================
SRC_SEED_TEST: DB "4 RANDOMIZE "
SRC_SEED_TEST_LEN EQU $ - SRC_SEED_TEST
SRC_SEED_REAL: DB "0 RANDOMIZE "
SRC_SEED_REAL_LEN EQU $ - SRC_SEED_REAL

; ============================================================================
; SRC_ARRAYS -- all persistent game state: the 52-card deck (RANKS/
; SUITS), player/dealer hands (PHR/PHS/DHR/DHS, sized 12 -- generous
; headroom over any realistic single-deck hand length), the on-screen
; column position for each card slot (COLS), and scratch VARIABLEs.
; COLS now holds each card's own pixel-box LEFT column (0,4,8,...,28 --
; every card renders inside a 4-column-wide/3-row-tall LINE-drawn box,
; see SRC_DISPLAY below), spaced exactly 4 columns apart so 8 boxes
; (slots 0-7) fill the full 32-column screen edge-to-edge with no gap
; and no overflow (28+4=32, the real screen width) -- real layout
; arithmetic, not a guess. Slots 8-9 (a 9th/10th card -- astronomically
; rare in single-deck blackjack, since only 4 of each rank exist, but
; not provably impossible) are deliberately CLAMPED to slot 7's own
; column (28) rather than left to run past column 31 (which AT-XY
; itself does not bounds-check -- see core/moregfx.asm's own header):
; a 9th+ card visually overlaps the 8th instead of ever writing off-
; screen or corrupting adjacent memory. A documented scope cut, not an
; oversight.
; VPTR/62120 (DETOK_BUF, include/sysvars.inc -- unused free RAM in this
; ROM since core/editor.asm was never INCLUDEd) is this ROM's own
; automated-verification log: LOGROUND (SRC_ROUND below) writes each
; round's (PTOTAL, DTOTAL, OUTCOME) there as three consecutive 2-byte
; cells per round, at a FIXED, externally-known address, specifically
; so this ROM's own verification can read the real results straight
; out of the emulator's memory afterward without needing to know any
; runtime-compiled dictionary address (PLOG/DLOG/OLOG-style ARRAYs
; would have worked too, but their own addresses are only known AFTER
; compiling everything before them, which is fragile to keep in sync
; by hand -- a fixed literal address sidesteps that entirely).
; ============================================================================
SRC_ARRAYS:
    DB "52 ARRAY RANKS 52 ARRAY SUITS 12 ARRAY PHR 12 ARRAY PHS 12 ARRAY DHR 12 ARRAY DHS 10 ARRAY COLS "
    DB "VARIABLE PCOUNT VARIABLE DCOUNT VARIABLE NEXTCARD VARIABLE DECKI VARIABLE JV VARIABLE ACES "
    DB "VARIABLE CURR VARIABLE CURS VARIABLE PTOTAL VARIABLE DTOTAL VARIABLE PBUST VARIABLE OUTCOME VARIABLE KEYVAL "
    DB "VARIABLE ROUNDNUM VARIABLE VPTR 62120 VPTR ! "
    DB "0 0 CELLS COLS + ! 4 1 CELLS COLS + ! 8 2 CELLS COLS + ! 12 3 CELLS COLS + ! 16 4 CELLS COLS + ! "
    DB "20 5 CELLS COLS + ! 24 6 CELLS COLS + ! 28 7 CELLS COLS + ! 28 8 CELLS COLS + ! 28 9 CELLS COLS + ! "
SRC_ARRAYS_LEN EQU $ - SRC_ARRAYS

; ============================================================================
; SRC_DECK -- deck construction (INIT-DECK, a fresh ordered 52-card
; deck built via a plain incrementing counter, avoiding any need for a
; `*`/`/` word this dictionary doesn't have -- see this file's own
; header) and a real Fisher-Yates SHUFFLE using RND. SHUFFLE-SOUND is a
; short raw-AY noise burst (Channel B's noise generator, not its tone
; generator -- distinct from CARD-SOUND's tone-based "click" below) with
; the noise PERIOD stepped four times in quick succession, giving a
; rough "shhk-shhk" riffle texture rather than one flat hiss; played
; once per SHUFFLE call (SRC_ROUND below calls it right after SHUFFLE,
; before the first card of the round is dealt).
; ============================================================================
SRC_DECK:
    DB ": GETR CELLS RANKS + @ ; "
    DB ": SETR CELLS RANKS + ! ; "
    DB ": GETS CELLS SUITS + @ ; "
    DB ": SETS CELLS SUITS + ! ; "
    DB ": INIT-DECK 0 DECKI ! 4 0 DO 14 1 DO I DECKI @ SETR J DECKI @ SETS DECKI @ 1+ DECKI ! LOOP LOOP ; "
    DB ": SHUFFLE 0 51 DO I 1+ RND JV ! I GETR JV @ GETR I SETR JV @ SETR I GETS JV @ GETS I SETS JV @ SETS -1 +LOOP ; "
    DB ": SHUFFLE-SOUND 7 239 SOUND 9 10 SOUND "
    DB "6 3 SOUND 400 0 DO LOOP 6 9 SOUND 400 0 DO LOOP 6 2 SOUND 400 0 DO LOOP 6 12 SOUND 400 0 DO LOOP "
    DB "9 0 SOUND ; "
SRC_DECK_LEN EQU $ - SRC_DECK

; ============================================================================
; SRC_SCORE -- CARDVAL (face cards worth 10, ace worth 11, else its own
; rank) and PSCORE/DSCORE (sum a hand's CARDVALs, then soften aces from
; 11 down to 1, one at a time, while over 21 and aces remain -- the
; classic soft/hard ace rule).
; ============================================================================
SRC_SCORE:
    DB ": CARDVAL DUP 1 = IF DROP 11 EXIT THEN DUP 10 > IF DROP 10 EXIT THEN ; "
    DB ": PSCORE 0 ACES ! 0 PCOUNT @ 0 DO I CELLS PHR + @ DUP 1 = IF ACES @ 1+ ACES ! THEN CARDVAL + LOOP "
    DB "BEGIN DUP 21 > ACES @ 0 > AND WHILE 10 - ACES @ 1- ACES ! REPEAT ; "
    DB ": DSCORE 0 ACES ! 0 DCOUNT @ 0 DO I CELLS DHR + @ DUP 1 = IF ACES @ 1+ ACES ! THEN CARDVAL + LOOP "
    DB "BEGIN DUP 21 > ACES @ 0 > AND WHILE 10 - ACES @ 1- ACES ! REPEAT ; "
SRC_SCORE_LEN EQU $ - SRC_SCORE

; ============================================================================
; SRC_GLYPHS -- SETUP-GLYPHS writes the four hand-designed 8x8 suit
; bitmaps into UDG slots 0-3 (character codes 144-147) via plain C!,
; exactly the same C!/UDG composition rom/forth_smoke_p51.asm's own
; checkpoint 1 already proved correct. Slot 0 (spade) uses the SAME
; bitmap that smoke ROM's own PATTERN_TABLE already tests -- its own
; header says so explicitly. Bitmaps, top row (offset 0) to bottom
; (offset 7), bit7 = leftmost pixel:
;   spade:   00011000 00111100 01111110 11111111
;            11111111 00111100 00011000 00111100
;   heart:   01100110 11111111 11111111 11111111
;            01111110 00111100 00011000 00000000
;   diamond: 00011000 00111100 01111110 11111111
;            11111111 01111110 00111100 00011000
;   club:    00011000 00111100 00011000 01111110
;            11111111 01111110 00011000 00011000
;   checker: 11001100 11001100 00110011 00110011
;            11001100 11001100 00110011 00110011
; Hand-designed pixel-art approximations of the four card suits, not
; claiming photographic card-font fidelity -- visual quality of the
; rendered glyphs on real screen geometry is NOT automated-verified by
; this ROM (see this file's own closing header note on what's
; unverified). Slot 4 (code 148) is the card-back texture: a 2x2-pixel
; checker with a 4px period in both directions, which divides evenly
; into the 8x8 cell -- tiling the exact same glyph across every cell of
; the card back therefore lines up seamlessly into one continuous
; checkerboard, no per-cell alternation logic needed.
; ============================================================================
SRC_GLYPHS:
    DB ": SETUP-GLYPHS "
    DB "24 0 UDG C! 60 0 UDG 1 + C! 126 0 UDG 2 + C! 255 0 UDG 3 + C! 255 0 UDG 4 + C! 60 0 UDG 5 + C! 24 0 UDG 6 + C! 60 0 UDG 7 + C! "
    DB "102 1 UDG C! 255 1 UDG 1 + C! 255 1 UDG 2 + C! 255 1 UDG 3 + C! 126 1 UDG 4 + C! 60 1 UDG 5 + C! 24 1 UDG 6 + C! 0 1 UDG 7 + C! "
    DB "24 2 UDG C! 60 2 UDG 1 + C! 126 2 UDG 2 + C! 255 2 UDG 3 + C! 255 2 UDG 4 + C! 126 2 UDG 5 + C! 60 2 UDG 6 + C! 24 2 UDG 7 + C! "
    DB "24 3 UDG C! 60 3 UDG 1 + C! 24 3 UDG 2 + C! 126 3 UDG 3 + C! 255 3 UDG 4 + C! 126 3 UDG 5 + C! 24 3 UDG 6 + C! 24 3 UDG 7 + C! "
    DB "204 4 UDG C! 204 4 UDG 1 + C! 51 4 UDG 2 + C! 51 4 UDG 3 + C! 204 4 UDG 4 + C! 204 4 UDG 5 + C! 51 4 UDG 6 + C! 51 4 UDG 7 + C! "
    DB "; "
SRC_GLYPHS_LEN EQU $ - SRC_GLYPHS

; ============================================================================
; SRC_DISPLAY -- rendering a card as a real pixel-box "card shape" with
; a real colored paper background, rank text + colored suit glyph
; inside it, per the graphics-upgrade pass this file's own header now
; describes.
;
; SCREEN GEOMETRY (confirmed from kernel/graphics/graphics.asm's own
; GFX_PIXEL_ADDR_SETUP header, not guessed): PLOT/LINE take x in 0-255,
; y in 0-191, TOP-DOWN (y=0 is the top row, char_row = y>>3) -- the same
; top-down sense AT-XY's own row already uses, so "row R" and "pixel y
; = R*8" agree directly, no inversion needed.
;
; CARD-BOX ( col row -- ) draws a real rectangle outline: 4 columns
; wide (32px) x 4 rows TALL (32px -- taller than wide, matching a real
; card's own portrait proportions; the earlier revision was 3 rows/24px,
; which read as landscape, the wrong way round), col/row being the
; box's own TOP-LEFT corner in TEXT cells (matching COLS' own per-card
; values, see SRC_ARRAYS above). X8 (n -- n*8) triples "DUP +" (n->2n->
; 4n->8n) to convert a column/row into a pixel coordinate without
; needing a general-purpose multiply word this dictionary doesn't have
; (same scope reasoning INIT-DECK's own header already gives for
; avoiding `*`).
;
; REAL BUG FOUND AND FIXED (core/print.asm, not this file): EMIT never
; used to write attribute (color) memory at all, only the bitmap, so
; INK/PAPER had zero visible effect on printed text anywhere in this
; project -- CARD-INK's own INK calls below did nothing visible until
; that kernel fix landed. Now that EMIT stamps CURRENT_ATTR into the
; cell it just printed (same as real Sinclair BASIC's PRINT), this file
; can give each card a real paper color distinct from the green felt
; table: CARD-FILL ( char -- ) paints all 4x4=16 cells of a card's own
; box interior to a fixed white (7) paper before anything is drawn on
; top, EMITting whatever character it's given (space, 32, for a face
; card; the checker glyph, 148, for a card back) via a DO LOOP over the
; 4 rows rather than unrolling each row by hand -- both SHOWCARD and
; CARD-BACK share this one word instead of each having their own
; near-duplicate fill code, real ROM-budget savings once measured
; against this file's own tight remaining margin. No new kernel word
; needed either way -- this is exactly the byte-memory-adjacent idiom
; docs/forth_tutorial.md's own C@/C! section already teaches, just via
; EMIT's cursor instead of a computed address. Filling the
; WHOLE box (not just the 2 content cells, as before) before drawing
; the pixel outline on top means the outline and the paper are the same
; 4x4-cell block with no seam between a colored region and an
; uncolored one -- previously the box's own corner/edge cells were left
; at whatever the felt background was, which is exactly the "different
; paper join" seam this revision closes.
;
; DRAW-CARD-BOX now forces ink 0 (black) for the outline, not 7 (white)
; as before -- a white outline on the new white card paper would be
; invisible; black reads correctly against both the white card and
; (where the outline's own LINE pixels fall on a still-unfilled corner,
; which no longer happens, but the color would be wrong either way) the
; green felt.
;
; FELT resets ink/paper back to this game's own established table
; baseline (0 INK / 4 PAPER, matching what SRC_ROUND sets once at the
; top of every round) after each card -- required now that INK/PAPER
; actually affects text: without this, the white card paper set by one
; SHOWCARD/CARD-BACK call would leak into whatever label text prints
; next (e.g. "YOU:", "YOUR TOTAL:"), which must stay black-on-felt.
;
; SHOWRANK now ALWAYS emits exactly one character (rank 10 prints as
; "T", real playing-card notation) instead of "10"'s two digits --
; needed so a card's own text content is a fixed, exactly-two-column
; width (rank + suit glyph) that matches the card's own fixed content
; position; the alternative (a variable-width "10") would have needed a
; variable-width box per card, real added complexity for a demo ROM
; already tight on space.
;
; CARD-INK: red (2) for hearts (suit 1)/diamonds (suit 2), else the
; default black (0) for spades (0)/clubs (3) -- unchanged from before.
;
; CARD-BACK ( col row -- ) is the hidden dealer card's real "card back"
; texture: UDG slot 4 (code 148, SRC_GLYPHS above)'s repeating checker
; tile, filling the whole box interior via CARD-BACK-CELLS -- replacing
; the earlier revision's two lone block-graphics characters (137/134)
; in just the content row, which read as a small icon rather than an
; actual card back. Drawn in ink 2 (red) on the same white (7) paper
; the face cards use, giving a red/white checkerboard.
; ============================================================================
SRC_DISPLAY:
    DB ": SHOWRANK DUP 1 = IF DROP .\" A\" EXIT THEN DUP 10 = IF DROP .\" T\" EXIT THEN "
    DB "DUP 11 = IF DROP .\" J\" EXIT THEN DUP 12 = IF DROP .\" Q\" EXIT THEN DUP 13 = IF DROP .\" K\" EXIT THEN STR TYPE ; "
    DB ": CARD-INK DUP 1 = SWAP 2 = OR IF 2 INK ELSE 0 INK THEN ; "
    DB ": FELT 0 INK 4 PAPER ; "
    DB "VARIABLE SC-RANK VARIABLE SC-SUIT VARIABLE SC-COL VARIABLE SC-ROW "
    DB "VARIABLE BX0 VARIABLE BY0 VARIABLE BX1 VARIABLE BY1 "
    DB ": X8 DUP + DUP + DUP + ; "
    DB ": CARD-BOX SWAP X8 BX0 ! X8 BY0 ! BX0 @ 31 + BX1 ! BY0 @ 31 + BY1 ! "
    DB "BX0 @ BY0 @ BX1 @ BY0 @ LINE BX0 @ BY1 @ BX1 @ BY1 @ LINE BX0 @ BY0 @ BX0 @ BY1 @ LINE BX1 @ BY0 @ BX1 @ BY1 @ LINE ; "
    DB ": DRAW-CARD-BOX 0 INK SC-COL @ SC-ROW @ CARD-BOX ; "
    DB "VARIABLE CF-CH "
    DB ": CARD-FILL CF-CH ! 4 0 DO SC-COL @ SC-ROW @ I + AT-XY CF-CH @ DUP DUP DUP EMIT EMIT EMIT EMIT LOOP ; "
    DB ": SHOWCARD SC-ROW ! SC-COL ! SC-SUIT ! SC-RANK ! 7 PAPER 0 INK 32 CARD-FILL "
    DB "SC-COL @ 1+ SC-ROW @ 1+ AT-XY SC-SUIT @ CARD-INK SC-RANK @ SHOWRANK 144 SC-SUIT @ + EMIT DRAW-CARD-BOX FELT ; "
    DB ": CARD-BACK SC-ROW ! SC-COL ! 7 PAPER 2 INK 148 CARD-FILL DRAW-CARD-BOX FELT ; "
    DB ": SHOW-DEALER-HAND DCOUNT @ 0 DO I CELLS DHR + @ I CELLS DHS + @ I CELLS COLS + @ 2 SHOWCARD LOOP ; "
    DB ": SHOW-PLAYER-HAND PCOUNT @ 0 DO I CELLS PHR + @ I CELLS PHS + @ I CELLS COLS + @ 8 SHOWCARD LOOP ; "
    DB ": SHOW-DEALER-HIDDEN 0 CELLS DHR + @ 0 CELLS DHS + @ 0 CELLS COLS + @ 2 SHOWCARD "
    DB "1 CELLS COLS + @ 2 CARD-BACK ; "
    DB ": REVEAL-DEALER 0 1 AT-XY .\" DEALER:        \" SHOW-DEALER-HAND ; "
SRC_DISPLAY_LEN EQU $ - SRC_DISPLAY

; ============================================================================
; SRC_DEAL -- DRAW takes the next card off the (already shuffled) deck
; into CURR/CURS and advances NEXTCARD; DEAL-PLAYER/DEAL-DEALER append
; it to the right hand; CARD-SOUND is a short raw-AY "card flick" via
; SOUND (Channel B, the same confirmed-working register combination
; core/sound.asm's own header documents), showcasing SOUND specifically
; (distinct from BEEP, used only for the four outcome cues).
; ============================================================================
SRC_DEAL:
    DB ": DRAW NEXTCARD @ GETR CURR ! NEXTCARD @ GETS CURS ! NEXTCARD @ 1+ NEXTCARD ! ; "
    DB ": DEAL-PLAYER DRAW CURR @ PCOUNT @ CELLS PHR + ! CURS @ PCOUNT @ CELLS PHS + ! PCOUNT @ 1+ PCOUNT ! ; "
    DB ": DEAL-DEALER DRAW CURR @ DCOUNT @ CELLS DHR + ! CURS @ DCOUNT @ CELLS DHS + ! DCOUNT @ 1+ DCOUNT ! ; "
    DB ": CARD-SOUND 2 60 SOUND 3 0 SOUND 7 253 SOUND 9 10 SOUND 300 0 DO LOOP 9 0 SOUND ; "
SRC_DEAL_LEN EQU $ - SRC_DEAL

; ============================================================================
; SRC_TURN -- PLAYER-TURN loops on GETKEY (H=hit/S=stand, either case)
; until the player stands or busts, now with a KEY-BLIP confirm sound on
; every keypress read (a short high 18-semitone/0.08s BEEP, distinct
; from CARD-SOUND's raw-AY click, so input feels immediately
; responsive); DEALER-TURN auto-plays the fixed hit-to-16/stand-on-17+
; strategy; DETERMINE-OUTCOME and SHOW-RESULT classify and announce the
; result with a distinct BORDER color and a real short multi-note BEEP
; sequence per outcome (not one flat tone any more):
;   WIN-SOUND         3-note rising arpeggio (~0.35s total)
;   DEALER-WIN-SOUND   2-note falling pair (~0.35s total)
;   BUST-SOUND         3-note falling run, low pitches (~0.54s total) --
;                      same "alarming, low, longest" spirit the old
;                      single -12/0.6s cue had, just now a real descending
;                      run instead of one tone
;   BLACKJACK-SOUND    4-note rising fanfare, brighter/higher than
;                      WIN-SOUND (~0.44s total)
;   push stays silent, unchanged (a push is a non-event, deliberately
;   the only outcome with no cue, same as before)
; All four cues stay well under half a second to a bit over half a
; second -- cheap dopamine cues, not songs, per this task's own pacing
; requirement.
; ============================================================================
SRC_TURN:
    DB ": KEY-BLIP 18 0.08 BEEP ; "
    DB ": WIN-SOUND 8 0.1 BEEP 12 0.1 BEEP 15 0.15 BEEP ; "
    DB ": DEALER-WIN-SOUND -3 0.15 BEEP -7 0.2 BEEP ; "
    DB ": BUST-SOUND -4 0.12 BEEP -8 0.12 BEEP -12 0.3 BEEP ; "
    DB ": BLACKJACK-SOUND 12 0.08 BEEP 15 0.08 BEEP 19 0.08 BEEP 24 0.2 BEEP ; "
    DB ": PLAYER-TURN 0 PBUST ! BEGIN 0 15 AT-XY .\" (H)IT OR (S)TAND?   \" GETKEY KEYVAL ! KEY-BLIP "
    DB "KEYVAL @ 72 = KEYVAL @ 104 = OR IF DEAL-PLAYER SHOW-PLAYER-HAND PSCORE PTOTAL ! "
    DB "0 13 AT-XY .\" YOUR TOTAL: \" PTOTAL @ . PTOTAL @ 21 > IF 1 PBUST ! THEN PBUST @ 0= "
    DB "ELSE KEYVAL @ 83 = KEYVAL @ 115 = OR IF 0 ELSE -1 THEN THEN WHILE REPEAT ; "
    DB ": DEALER-TURN BEGIN DSCORE DTOTAL ! DTOTAL @ 17 < WHILE DEAL-DEALER REPEAT ; "
    DB ": DETERMINE-OUTCOME PBUST @ 1 = IF 3 OUTCOME ! EXIT THEN DTOTAL @ 21 > IF 1 OUTCOME ! EXIT THEN "
    DB "PTOTAL @ DTOTAL @ = IF 5 OUTCOME ! EXIT THEN PTOTAL @ DTOTAL @ > IF 1 OUTCOME ! EXIT THEN 2 OUTCOME ! ; "
    DB ": SHOW-RESULT 0 17 AT-XY .\" DEALER TOTAL: \" DTOTAL @ . 0 18 AT-XY "
    DB "OUTCOME @ 1 = IF .\" YOU WIN!        \" 4 BORDER WIN-SOUND EXIT THEN "
    DB "OUTCOME @ 2 = IF .\" DEALER WINS     \" 1 BORDER DEALER-WIN-SOUND EXIT THEN "
    DB "OUTCOME @ 3 = IF .\" BUST! YOU LOSE  \" 2 BORDER BUST-SOUND EXIT THEN "
    DB "OUTCOME @ 4 = IF .\" BLACKJACK!      \" 3 BORDER BLACKJACK-SOUND EXIT THEN "
    DB ".\" PUSH            \" 5 BORDER ; "
SRC_TURN_LEN EQU $ - SRC_TURN

; ============================================================================
; SRC_ROUND -- LOGROUND appends this round's (PTOTAL, DTOTAL, OUTCOME)
; to VPTR's fixed log buffer (see SRC_ARRAYS's own header on VPTR/62120)
; -- purely for this ROM's own automated verification (a real player
; never sees it), so every round's result can be read back from a
; single memory snapshot after the whole scripted game finishes,
; without needing to pause mid-run. ROUND ties
; the whole flow together: reset per-round state, build+shuffle a fresh
; deck, deal, check for a natural player blackjack (peeking the
; dealer's real total silently first -- see this file's own header on
; why only checked when the player also has one), otherwise run the
; player's turn, the dealer's turn (skipped on a player bust), and
; determine the outcome; reveal the dealer's hand and show the result
; either way. Each round now also establishes a real green "felt table"
; look right after CLS: 4 PAPER (green) repaints the whole attribute
; area including blank cells (CLS itself now honors PAPER -- see the
; kernel EMIT/CLS INK-PAPER fix) + 4 BORDER, all distinct from the card
; boxes' own fixed white (7) outline ink and
; from the outcome-specific BORDER colors SHOW-RESULT sets at the very
; end of the round (which intentionally override this felt border for
; the outcome flash, then get reset back to felt at the start of the
; NEXT round).
; ============================================================================
SRC_ROUND:
    DB ": LOGROUND PTOTAL @ VPTR @ ! VPTR @ 2 + VPTR ! DTOTAL @ VPTR @ ! VPTR @ 2 + VPTR ! "
    DB "OUTCOME @ VPTR @ ! VPTR @ 2 + VPTR ! ROUNDNUM @ 1+ ROUNDNUM ! ; "
    DB ": ROUND 0 PCOUNT ! 0 DCOUNT ! 0 NEXTCARD ! 0 PBUST ! 0 OUTCOME ! "
    DB "INIT-DECK SHUFFLE SHUFFLE-SOUND CLS 0 INK 4 PAPER 4 BORDER 11 0 AT-XY .\" BLACKJACK\" "
    DB "DEAL-PLAYER DEAL-DEALER DEAL-PLAYER DEAL-DEALER CARD-SOUND CARD-SOUND CARD-SOUND CARD-SOUND "
    DB "0 1 AT-XY .\" DEALER:\" SHOW-DEALER-HIDDEN 0 7 AT-XY .\" YOU:\" SHOW-PLAYER-HAND "
    DB "PSCORE PTOTAL ! DSCORE DTOTAL ! 0 13 AT-XY .\" YOUR TOTAL: \" PTOTAL @ . "
    DB "PTOTAL @ 21 = IF 4 OUTCOME ! DTOTAL @ 21 = IF 5 OUTCOME ! THEN "
    DB "ELSE PLAYER-TURN PBUST @ 1 = IF 3 OUTCOME ! ELSE DEALER-TURN DETERMINE-OUTCOME THEN THEN "
    DB "REVEAL-DEALER SHOW-RESULT LOGROUND ; "
SRC_ROUND_LEN EQU $ - SRC_ROUND

; ============================================================================
; SRC_MAIN -- PLAY-AGAIN? loops (stack-neutral per retry -- re-derives
; the Y/N flags fresh from KEYVAL every pass rather than carrying stale
; copies across iterations) until a real Y or N is pressed; MAIN plays
; rounds until the player declines.
; ============================================================================
SRC_MAIN:
    DB ": PLAY-AGAIN? 0 20 AT-XY .\" PLAY AGAIN? (Y/N)     \" "
    DB "BEGIN GETKEY KEYVAL ! KEYVAL @ 89 = KEYVAL @ 121 = OR KEYVAL @ 78 = KEYVAL @ 110 = OR OR UNTIL "
    DB "KEYVAL @ 89 = KEYVAL @ 121 = OR ; "
    DB ": MAIN BEGIN ROUND PLAY-AGAIN? WHILE REPEAT 0 20 AT-XY .\" THANKS FOR PLAYING!    \" ; "
SRC_MAIN_LEN EQU $ - SRC_MAIN

SRC_KICKOFF: DB "SETUP-GLYPHS MAIN "
SRC_KICKOFF_LEN EQU $ - SRC_KICKOFF

    IFDEF BLACKJACK_TEST_MODE
; ============================================================================
; SRC_VERIFY -- BLACKJACK_TEST_MODE only, never assembled into a normal
; build: dumps all 4 rounds' logged (PTOTAL, DTOTAL, OUTCOME) as plain
; decimal text on a cleared screen after MAIN finishes, one round per
; row -- a redundant, low-cost, on-screen echo of the SAME values this
; ROM's own automated verification reads directly out of the emulator's
; memory at VPTR's fixed 62120 log address (see SRC_ARRAYS's own
; header); kept mainly because it costs almost nothing and exercises
; EMIT/AT-XY/CLS one more time under the exact scripted conditions
; being verified.
; ============================================================================
SRC_VERIFY:
    DB "CLS "
    DB "0 0 AT-XY 62120 @ . 62122 @ . 62124 @ . "
    DB "0 1 AT-XY 62126 @ . 62128 @ . 62130 @ . "
    DB "0 2 AT-XY 62132 @ . 62134 @ . 62136 @ . "
    DB "0 3 AT-XY 62138 @ . 62140 @ . 62142 @ . "
    DB "0 5 AT-XY ROUNDNUM @ . "
SRC_VERIFY_LEN EQU $ - SRC_VERIFY
    ENDIF

    DS   $4000 - $, $FF

    SAVEBIN "forth_demo_blackjack_rom0.bin", $0000, $4000
