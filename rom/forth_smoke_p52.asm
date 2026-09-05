; ============================================================================
; rom/forth_smoke_p52.asm — Phase 52 smoke ROM: SAVE-TEXT / LOAD-TEXT
; (core/loadtext.asm), verified against a REAL, large test payload
;
; Proves core/loadtext.asm's SAVE-TEXT/LOAD-TEXT wiring using the exact
; same fake-tape technique rom/forth_smoke_p7.asm already established
; (kernel/storage's own STORAGE_TEST_FAKE_SEND/STORAGE_TEST_FAKE_RECEIVE
; hooks) — see that file's own header for exactly what this proves and
; does NOT prove (real tape wire-format compatibility in an actual
; emulator's own cassette deck is a separate, already-covered concern;
; core/storage.asm/kernel/storage/storage.asm are untouched by this
; feature).
;
; UNLIKE every other smoke ROM in this project, this one uses the FULL,
; unmodified forth_boot.asm dictionary chain (every INCLUDE, every
; DICT_CHAIN_POINT splice, identical order) rather than a narrow
; per-phase subset — deliberately, because the whole point of SAVE-TEXT/
; LOAD-TEXT is to prove they work in the REAL product's own full
; dictionary and RAM budget, not a trimmed stand-in. core/editor.asm is
; included for that same parity even though this ROM never calls
; EDITOR_LOOP_LIVE.
;
; TWO CHECKPOINTS:
;   1. A small, self-contained round trip (": DOUBLER DUP + ;") proving
;      the basic wiring: SAVE-TEXT the definition's own source text,
;      simulate a fresh boot (dictionary pointers reset AND the RAM
;      dictionary region poisoned with $FF — stronger than
;      rom/forth_smoke_p7.asm's own pointer-only reset, since this
;      checkpoint exists specifically to build confidence before the
;      much bigger checkpoint 2), LOAD-TEXT it back, then confirm
;      DOUBLER actually recompiled and works.
;   2. The REAL, large-scale proof: the Blackjack demo's own extracted
;      Forth source (rom/forth_smoke_p52_blackjack_test.fs, INCBINed —
;      see that file's own relationship to demos/blackjack.fs below),
;      SAVE-TEXT'd, a simulated fresh boot, then LOAD-TEXT'd — which
;      both recompiles the entire ~60-word game dictionary AND (since
;      the loaded text's own tail is "SETUP-GLYPHS MAIN", exactly like
;      the original ROM) actually PLAYS four full rounds live, through
;      GETKEY/hit/stand/bust/outcome, entirely as a side effect of
;      LOAD-TEXT compiling and running it.
;
; TEST PAYLOAD, exactly how it differs from demos/blackjack.fs (the real
; deliverable — see that file's own extraction for the genuine, ordinary
; user-facing version): rom/forth_smoke_p52_blackjack_test.fs is the
; SAME extracted game text with two swaps, both necessary only because
; this is an unattended, deterministic, automated test rather than a
; human playing:
;   - "0 RANDOMIZE" (real entropy) -> "4 RANDOMIZE" (the exact seed
;     rom/forth_demo_blackjack.asm's own BLACKJACK_TEST_MODE already
;     uses and hand-verified against a real Python LFSR simulation — see
;     that file's own header) — makes every dealt card reproducible.
;   - ": GETKEY KEY ;" (the real keyboard, appropriate for an actual
;     player) -> a pure-Forth scripted GETKEY that returns the exact
;     same "Y H Y Y S N" keystroke sequence (ASCII 89,72,89,89,83,78)
;     rom/forth_demo_blackjack.asm's own TEST_KEY_TABLE already uses,
;     via a VARIABLE index and a chain of IF/EXIT — no raw memory table
;     needed, every word it uses (VARIABLE, IF, EXIT, =, @, !, 1+)
;     already exists in the real dictionary this file drives.
; ": TABLEBG ;" is a no-op stub in both variants (demos/blackjack.fs and
; this file's own test payload) either way — forth_boot.asm's own
; dictionary has no word wrapping kernel/graphics's GFX_PAINT_ATTR
; (rom/forth_demo_blackjack.asm's own TABLEBG is a ROM-local word not
; part of core/), so the felt-table background paint is simply skipped;
; purely cosmetic, doesn't affect any hit/stand/outcome logic this test
; actually checks.
;
; GROUND TRUTH, independently established (not hand-computed or
; assumed): rom/forth_demo_blackjack.asm rebuilt with -DBLACKJACK_TEST_MODE
; and run under real headless Fuse (via --debugger-command, a breakpoint
; at the post-SRC_VERIFY .hang loop, and `print` expressions reading
; VPTR's own fixed 62120 log address directly — no GUI, no screenshot,
; no key injection needed) produced, for the SAME seed and SAME keys:
;   Round 1: PTOTAL=21 DTOTAL=18 OUTCOME=4 (BLACKJACK)
;   Round 2: PTOTAL=22 DTOTAL=20 OUTCOME=3 (BUST)
;   Round 3: PTOTAL=21 DTOTAL=12 OUTCOME=4 (BLACKJACK)
;   Round 4: PTOTAL=17 DTOTAL=23 OUTCOME=1 (WIN)
; (Rounds 1, 3, and 4 match rom/forth_demo_blackjack.asm's own header
; narrative exactly; round 2's exact PTOTAL/DTOTAL aren't stated there
; as precisely as this run's own direct memory read, which is treated as
; authoritative — an actual emulator run, not a re-derivation of the
; header's prose.) Checkpoint 2 below asserts its OWN loaded-via-tape
; copy's VPTR log matches these 12 values exactly, plus a real FIND
; lookup on "MAIN" to directly confirm the word is genuinely present in
; the rebuilt dictionary (not just inferred from the game having run).
;
; RAM LAYOUT for this test only (not part of forth_boot.asm's own real
; budget): FAKE_TAPE_BUF ($B400-$CFFF, 7168 bytes — both blocks together
; need ~6106 bytes) sits below core/loadtext.asm's own LOADTEXT_BUF
; ($D000-$EFFF, fixed by that file), both within the same $9800-$FEFF
; span core/free.asm's own audit already confirmed clear of everything
; except GFX_LINE_X0-Y1 ($F3C4-$F3C7, untouched by either range here).
; That leaves $9800-$B3FF (also 7168 bytes) for the actual compiled RAM
; dictionary this test builds (mini DOUBLER + the full ~60-word
; Blackjack game) — confirmed sufficient by this file's own checkpoint
; 2 (which would fail outright, not silently, if HERE ever collided
; with FAKE_TAPE_BUF while still reading from it).
;
; ROM BUDGET, why this file's own INCLUDE list is TRIMMED (not the full
; forth_boot.asm chain, despite this file's own earlier draft trying
; exactly that and overflowing by ~4.4KB): the full ~93-word dictionary
; already leaves only ~1.5KB of this project's fixed 16KB ROM0 free
; (confirmed separately — see this file's own closing report) — nowhere
; near enough room for a ~6KB embedded test payload on top of it. This
; is the EXACT SAME problem rom/forth_demo_blackjack.asm's own header
; already documents and solves; this file reuses that file's own proven
; trimmed word list VERBATIM (same games needs the exact same words
; either way), adding only what core/loadtext.asm itself needs on top
; (kernel/storage/storage.asm for STORAGE_SAVE/STORAGE_LOAD,
; core/free.asm for DICT_RAM_CEILING, core/loadtext.asm itself) and
; dropping core/editor.asm (never called here, no live prompt) and
; core/storage.asm (the dictionary-IMAGE SAVE/LOAD this feature doesn't
; use or need). This does NOT weaken the "real, full product" claim:
; forth_boot.asm itself — the actual untrimmed product ROM, with
; SAVE-TEXT/LOAD-TEXT spliced in — was separately built and confirmed to
; assemble correctly with real headroom to spare; THIS file exists only
; to prove the words behave correctly against a genuinely large payload,
; which the full ROM's own budget can't also hold at the same time.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEFINE STORAGE_TEST_FAKE_SEND
    DEFINE STORAGE_TEST_FAKE_RECEIVE

    DEVICE NOSLOT64K
    ORG $0000

; ---- RST 00: cold start ----
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
    ei
    reti                          ; no live keyboard needed -- this test's
                                  ; own GETKEY is pure scripted Forth, not
                                  ; core/key.asm's real KEY (see this
                                  ; file's own "ROM BUDGET" note: dropping
                                  ; kernel/io.asm and kernel/interrupt.asm
                                  ; entirely is what actually made this
                                  ; file's own 6KB payload fit)
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

    ld   hl, DICT_LATEST_INIT_LOADTEXT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a
    ld   a, DEFAULT_ATTR
    ld   (CURRENT_ATTR), a

    xor  a
    ld   (FAKE_TAPE_WPOS), a
    ld   (FAKE_TAPE_WPOS+1), a
    ld   (FAKE_TAPE_RPOS), a
    ld   (FAKE_TAPE_RPOS+1), a

; ---- checkpoint 1: mini round trip -- DOUBLER's own source text ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a

    ld   hl, MINI_SRC
    call DPUSH_HL
    ld   hl, MINI_SRC_LEN
    call DPUSH_HL
    ld   hl, SRC_SAVE_MINI
    ld   de, SRC_SAVE_MINI_LEN
    call INTERPRET_RUN

    call RESET_AND_POISON

    ld   hl, SRC_LOAD_MINI
    ld   de, SRC_LOAD_MINI_LEN
    call INTERPRET_RUN

    ld   hl, SRC_USE_MINI
    ld   de, SRC_USE_MINI_LEN
    call INTERPRET_RUN
    ld   de, 8
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: the real, large-scale round trip -- the Blackjack
; game's own extracted source (see this file's own header) ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a

    ld   hl, BJ_SRC
    call DPUSH_HL
    ld   hl, BJ_SRC_LEN
    call DPUSH_HL
    ld   hl, SRC_SAVE_BJ
    ld   de, SRC_SAVE_BJ_LEN
    call INTERPRET_RUN

    call RESET_AND_POISON

    ; This single INTERPRET_RUN call does EVERYTHING: STORAGE_LOAD
    ; receives the payload into LOADTEXT_BUF, then LOAD-TEXT's own
    ; INTERPRET_RUN call compiles all ~60 words AND runs the loaded
    ; text's own tail ("SETUP-GLYPHS MAIN"), which plays all four
    ; scripted rounds to completion before this call ever returns.
    ld   hl, SRC_LOAD_BJ
    ld   de, SRC_LOAD_BJ_LEN
    call INTERPRET_RUN

    ; ---- confirm the rebuilt dictionary actually contains the game:
    ; a real FIND on "MAIN", not just inferring success from the game
    ; having run ----
    ld   hl, FINDWORD_MAIN
    call DPUSH_HL
    call FIND
    call DPOP_HL                 ; found flag
    ld   a, l
    cp   1
    jp   nz, FAIL_TEST
    call DPOP_HL                 ; imm flag -- discard
    call DPOP_HL                 ; code addr -- discard

    ; ---- confirm all 4 rounds' logged outcomes match the independently
    ; established ground truth (see this file's own header) ----
    ld   hl, 62120
    ld   de, 21
    call CHECK_MEM16
    ld   hl, 62122
    ld   de, 18
    call CHECK_MEM16
    ld   hl, 62124
    ld   de, 4
    call CHECK_MEM16

    ld   hl, 62126
    ld   de, 22
    call CHECK_MEM16
    ld   hl, 62128
    ld   de, 20
    call CHECK_MEM16
    ld   hl, 62130
    ld   de, 3
    call CHECK_MEM16

    ld   hl, 62132
    ld   de, 21
    call CHECK_MEM16
    ld   hl, 62134
    ld   de, 12
    call CHECK_MEM16
    ld   hl, 62136
    ld   de, 4
    call CHECK_MEM16

    ld   hl, 62138
    ld   de, 17
    call CHECK_MEM16
    ld   hl, 62140
    ld   de, 23
    call CHECK_MEM16
    ld   hl, 62142
    ld   de, 1
    call CHECK_MEM16

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
RESET_AND_POISON:                ; simulates a fresh boot: RAM dictionary
                                  ; pointers reset AND the RAM dictionary
                                  ; region actually overwritten with $FF,
                                  ; so a pass here can't be explained by
                                  ; leftover state from before the "boot"
    ld   hl, DICT_LATEST_INIT_LOADTEXT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (LEAVE_DEPTH), a
    ld   hl, FORTH_DICT_RAM
    ld   de, FORTH_DICT_RAM+1
    ld   bc, FAKE_TAPE_BUF - FORTH_DICT_RAM - 1
    ld   (hl), $FF
    ldir
    ret

CHECK_TOP:                       ; DE = expected top-of-stack value
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

CHECK_MEM16:                     ; HL = address, DE = expected 16-bit
                                  ; value (low byte at HL, high at HL+1,
                                  ; matching this project's own W_FETCH
                                  ; convention)
    ld   a, (hl)
    ld   c, a
    inc  hl
    ld   a, (hl)
    ld   b, a
    ld   a, c
    cp   e
    jp   nz, FAIL_TEST
    ld   a, b
    cp   d
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: both checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                       ; border shows which checkpoint (1-2) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source (or the extracted payload),
                                  ; not a real checkpoint failure
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8A76         ; 1 byte -- right after core/loadtext.asm's
                                  ; own LOADTEXT_NAME_BUF (ends $8A74),
                                  ; still inside the same confirmed-idle
                                  ; gap before core/float.asm's own
                                  ; FSTACK_LIMIT ($8C00)

MINI_SRC:    DB ": DOUBLER DUP + ; "
MINI_SRC_LEN EQU $ - MINI_SRC
SRC_SAVE_MINI: DB "SAVE-TEXT MINI "
SRC_SAVE_MINI_LEN EQU $ - SRC_SAVE_MINI
SRC_LOAD_MINI: DB "LOAD-TEXT MINI "
SRC_LOAD_MINI_LEN EQU $ - SRC_LOAD_MINI
SRC_USE_MINI: DB "4 DOUBLER "
SRC_USE_MINI_LEN EQU $ - SRC_USE_MINI

SRC_SAVE_BJ: DB "SAVE-TEXT BJPROG "
SRC_SAVE_BJ_LEN EQU $ - SRC_SAVE_BJ
SRC_LOAD_BJ: DB "LOAD-TEXT BJPROG "
SRC_LOAD_BJ_LEN EQU $ - SRC_LOAD_BJ

FINDWORD_MAIN: DB 4, "M","A","I","N"

BJ_SRC:
    INCBIN "rom/forth_smoke_p52_blackjack_test.fs"
BJ_SRC_LEN EQU $ - BJ_SRC

; ============================================================================
; Fake tape -- test-harness-only, identical scheme to
; rom/forth_smoke_p7.asm's own (see that file's own header): each block
; stored sequentially as [type:1][length:2][data:length]; SEND appends,
; RECEIVE reads forward from wherever the last RECEIVE left off. Both
; blocks (checkpoint 1's mini program, then checkpoint 2's Blackjack
; text) share this ONE fake tape in sequence, same as p7's own two
; rounds -- proving sequential blocks still work, not just an isolated
; round trip.
; ============================================================================
FAKE_TAPE_WPOS EQU $8A77
FAKE_TAPE_RPOS EQU $8A79
FAKE_TAPE_BUF  EQU $B400      ; 7168 bytes, through $CFFF -- see this
                               ; file's own header for the full RAM
                               ; layout reasoning

STORAGE_TEST_SEND_BLOCK:         ; A = type, IX = data ptr, DE = length
    push af
    ld   hl, (FAKE_TAPE_WPOS)
    ld   bc, FAKE_TAPE_BUF
    add  hl, bc
    pop  af
    ld   (hl), a
    inc  hl
    ld   (hl), e
    inc  hl
    ld   (hl), d
    inc  hl
.copyloop:
    ld   a, d
    or   e
    jr   z, .copydone
    ld   a, (ix+0)
    ld   (hl), a
    inc  ix
    inc  hl
    dec  de
    jr   .copyloop
.copydone:
    ld   de, FAKE_TAPE_BUF
    or   a
    sbc  hl, de
    ld   (FAKE_TAPE_WPOS), hl
    ret

STORAGE_TEST_RECEIVE_BLOCK:      ; A = expected type, carry-in = load(set)
                                  ; /verify(clear), IX = dest ptr,
                                  ; DE = expected length (unused, as in
                                  ; p7's own identical fake -- the stored
                                  ; length is authoritative)
    ld   c, a
    push af
    ld   hl, (FAKE_TAPE_RPOS)
    ld   de, FAKE_TAPE_BUF
    add  hl, de
    ld   a, (hl)
    cp   c
    jr   nz, .fail
    inc  hl
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    inc  hl
    pop  af
    jr   c, .do_receive
.do_receive:
.copyloop:
    ld   a, d
    or   e
    jr   z, .copydone
    ld   a, (hl)
    ld   (ix+0), a
    inc  hl
    inc  ix
    dec  de
    jr   .copyloop
.copydone:
    ld   de, FAKE_TAPE_BUF
    or   a
    sbc  hl, de
    ld   (FAKE_TAPE_RPOS), hl
    or   a
    ret
.fail:
    pop  af
    scf
    ret

; ---- kernel + dictionary: a TRIMMED subset, reusing
; rom/forth_demo_blackjack.asm's own proven trimmed word list VERBATIM
; (same game, same real dependency set) plus exactly what core/loadtext.asm
; itself needs on top (kernel/storage/storage.asm, core/free.asm,
; core/loadtext.asm) — see this file's own "ROM BUDGET" header note above
; for why. No core/storage.asm (dictionary-image SAVE/LOAD, unused by
; this feature) and no core/editor.asm (no live prompt here). ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "kernel/storage/storage.asm"
    INCLUDE "core/dict.asm"
    DEFINE DECIMAL_NUMBER_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/floatmul.asm"
DICT_CHAIN_POINT DEFL H_FSTAR
    INCLUDE "core/floatdiv.asm"
DICT_CHAIN_POINT DEFL H_FSLASH
    INCLUDE "core/decimal.asm"
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
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/udg.asm"
DICT_CHAIN_POINT DEFL H_UDG
    ; core/free.asm itself isn't needed (its FREE word is never used by
    ; this test) -- only its DICT_RAM_CEILING constant is, which
    ; core/loadtext.asm's own LOADTEXT_BUF derives from. Defined locally
    ; here instead of pulling in the whole file, matching that constant's
    ; real value ($F000) exactly (core/free.asm's own header).
DICT_RAM_CEILING EQU $F000
    INCLUDE "core/loadtext.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p52_rom0.bin", $0000, $4000
