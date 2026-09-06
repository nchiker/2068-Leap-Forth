; ============================================================================
; rom/forth_smoke_p53_realtape.asm — real (non-fake) tape round trip for
; LOAD-TEXT, under real Fuse pulse-level cassette emulation
;
; CLOSES A GENUINELY OPEN GAP: core/loadtext.asm's own header and
; docs/PROJECT_PLAN.md's Phase 7 section have both said, since Phase 52,
; that the LOAD-TEXT/SAVE-LIB tape wire-format was only ever proven
; against kernel/storage's own STORAGE_TEST_FAKE_SEND/STORAGE_TEST_FAKE_
; RECEIVE hooks (rom/forth_smoke_p7.asm, rom/forth_smoke_p52.asm) — a
; real Fuse pulse-level round trip, decoding an actual .TAP file byte by
; byte through the real (non-fake) STORAGE_RECEIVE_BLOCK, was never
; done. This file is exactly that: UNLIKE rom/forth_smoke_p52.asm, this
; file does NOT define STORAGE_TEST_FAKE_SEND/STORAGE_TEST_FAKE_RECEIVE
; at all — kernel/storage/storage.asm's own real STORAGE_RECEIVE_BLOCK
; (the byte-for-byte port of the real ROM's LD-BYTES, toggling and
; sampling the real ULA port) is what runs here, against a real tape
; file built by tools/tape_gen_forth.py and played back by Fuse's own
; standard tape engine — see that tool's own header for why a plain
; .TAP file is already this project's exact real wire format (this
; project's protocol IS the stock Sinclair one, unlike ts2068rom's own
; from-scratch format, which needed a hand-built Direct Recording).
;
; SAVE is NOT exercised here — building the tape file directly (as this
; project's own real STORAGE_SAVE would produce it, verified byte-for-
; byte format-correct by tools/tape_gen_forth.py itself, and consumed by
; the SAME real STORAGE_RECEIVE_BLOCK this file's own checkpoints prove
; works) is the honest, achievable half of "real tape round trip these
; can only fake so far": Fuse's own real cassette *recording* (Media,
; Tape, Record Start) is a GUI-menu-only action with no CLI or debugger-
; command equivalent, and automating it was judged not worth the
; fragility for what it would additionally prove — STORAGE_SEND_BLOCK's
; own port-toggle logic is comparatively low-risk (no receiver-side
; timing ambiguity) and is already verified byte-for-byte against the
; real ROM's own SA-BYTES (see kernel/storage/storage.asm's own header).
; The receive side — genuinely ambiguous, timing-sensitive, and the
; actual source of every real SAVE/LOAD bug this project has ever hit —
; is what a real round trip needs to prove, and this file proves it.
;
; TWO CHECKPOINTS, same shape as rom/forth_smoke_p52.asm's own, both now
; reading from a REAL tape (build/realtape_test.tap, two named files in
; sequence — STORAGE_LOAD's own header search naturally continues
; forward from wherever the tape currently is, so both LOAD-TEXT calls
; below read the SAME tape object in order, exactly like a real two-
; program cassette):
;   1. LOAD-TEXT "MINI" — a tiny round trip (": DOUBLER DUP + ;"),
;      proving basic real-tape wiring before the bigger checkpoint.
;   2. LOAD-TEXT "BJPROG" — the Blackjack demo's own scripted test
;      payload (rom/forth_smoke_p52_blackjack_test.fs — same file p52
;      already uses for its own fake-tape checkpoint, so the SAME
;      independently-established ground truth applies here unchanged),
;      which recompiles the ~60-word game and plays all four scripted
;      rounds to completion as a side effect of LOAD-TEXT compiling and
;      running the loaded text's own "SETUP-GLYPHS MAIN" tail.
;
; HOW TO RUN:
;   make forth-smoke-p53-realtape
;   python3 tools/tape_gen_forth.py build/realtape_test.tap \
;       MINI:build/mini_src.fs BJPROG:rom/forth_smoke_p52_blackjack_test.fs
;   fuse --machine ts2068 --no-sound --no-traps \
;        --rom-ts2068-0 build/forth_smoke_p53_realtape_rom0.bin \
;        --rom-ts2068-1 build/stock_shaped_exrom.bin \
;        --tape build/realtape_test.tap \
;        --debugger-command "$(cat build/realtape_test.dbg)"
; (build/realtape_test.dbg sets a breakpoint at .hang and prints the
; border color plus the VPTR ground-truth log, then exits — see
; tools/run_realtape_test.sh for the whole pipeline scripted together.)
;
; RAM LAYOUT: no fake-tape buffer needed at all this time (the real port
; routines have no RAM buffer of their own — every byte comes from the
; real ULA port) — this file's own dictionary chain, RAM budget, and
; word list are otherwise IDENTICAL to rom/forth_smoke_p52.asm's own
; trimmed set (see that file's own "ROM BUDGET" header note); reused
; verbatim rather than re-derived.
; ============================================================================

    INCLUDE "include/hardware.inc"

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
    reti                          ; no live keyboard needed -- this
                                  ; test's own GETKEY (baked into the
                                  ; tape payload's own text, exactly
                                  ; like rom/forth_smoke_p52.asm's own
                                  ; BJPROG payload) is pure scripted
                                  ; Forth, not core/key.asm's real KEY
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

    ; poison the RAM dictionary region up front -- no earlier SAVE step
    ; exists in this file to "reset away from" (the tape is built
    ; offline, not recorded by this ROM), so this simply proves neither
    ; checkpoint below can be explained by leftover/incidental RAM state
    ld   hl, FORTH_DICT_RAM
    ld   de, FORTH_DICT_RAM+1
    ld   bc, LOADTEXT_BUF - FORTH_DICT_RAM - 1
    ld   (hl), $FF
    ldir

; ---- checkpoint 1: real-tape mini round trip -- DOUBLER ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a

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
; game's own scripted test payload, read from the SAME real tape ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a

    ; This single INTERPRET_RUN call does EVERYTHING: STORAGE_LOAD
    ; receives the payload from the real tape into LOADTEXT_BUF via
    ; genuine pulse-level decoding, then LOAD-TEXT's own INTERPRET_RUN
    ; call compiles all ~60 words AND runs the loaded text's own tail
    ; ("SETUP-GLYPHS MAIN"), which plays all four scripted rounds to
    ; completion before this call ever returns.
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

    ; ---- confirm all 4 rounds' logged outcomes match the SAME ground
    ; truth rom/forth_smoke_p52.asm's own header independently
    ; established (identical payload text, identical scripted keys and
    ; seed -- see that file's own header) ----
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
    jr   DONE

FAIL_TEST:                       ; border shows which checkpoint (1-2) failed
    ld   a, (CHECKPOINT_NUM)
    jr   DONE

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source (or the extracted payload),
                                  ; not a real checkpoint failure

; ---- single converged end state -- one stable breakpoint address for
; the debugger-driven test harness regardless of pass/fail/bug outcome
; (see tools/run_realtape_test.sh) ----
DONE:
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8A76         ; 1 byte -- right after core/loadtext.asm's
                                  ; own LOADTEXT_NAME_BUF (ends $8A74),
                                  ; same gap rom/forth_smoke_p52.asm's own
                                  ; identically-named constant already
                                  ; uses (that file is never assembled
                                  ; together with this one, no collision)

SRC_LOAD_MINI: DB "LOAD-TEXT MINI "
SRC_LOAD_MINI_LEN EQU $ - SRC_LOAD_MINI
SRC_USE_MINI: DB "4 DOUBLER "
SRC_USE_MINI_LEN EQU $ - SRC_USE_MINI

SRC_LOAD_BJ: DB "LOAD-TEXT BJPROG "
SRC_LOAD_BJ_LEN EQU $ - SRC_LOAD_BJ

FINDWORD_MAIN: DB 4, "M","A","I","N"

; ---- kernel + dictionary: IDENTICAL trimmed subset to
; rom/forth_smoke_p52.asm's own (see that file's own "ROM BUDGET" header
; note) -- reused verbatim rather than re-derived. No core/storage.asm
; (dictionary-image SAVE/LOAD, unused by this feature) and no
; core/editor.asm (no live prompt here). kernel/storage/storage.asm is
; INCLUDEd WITHOUT either STORAGE_TEST_FAKE_SEND or STORAGE_TEST_FAKE_
; RECEIVE defined -- the whole point of this file -- so it assembles its
; real STORAGE_SEND_BLOCK/STORAGE_RECEIVE_BLOCK bodies (only RECEIVE is
; actually exercised below; SEND assembles in but is dead code here). ----
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
    ; core/free.asm itself isn't needed (its FREE word is never used by
    ; this test) -- only its DICT_RAM_CEILING constant is, which
    ; core/loadtext.asm's own LOADTEXT_BUF derives from. Defined locally
    ; here instead of pulling in the whole file, matching that constant's
    ; real value ($F000) exactly (core/free.asm's own header).
DICT_RAM_CEILING EQU $F000
    INCLUDE "core/loadtext.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p53_realtape_rom0.bin", $0000, $4000
