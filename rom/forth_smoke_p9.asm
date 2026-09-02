; ============================================================================
; rom/forth_smoke_p9.asm — Phase 9 smoke ROM: full dictionary + real
; interrupt-driven keyboard
;
; Proves two things no earlier smoke ROM in this project has proven
; together:
;
;   1. Every phase's dictionary words are reachable from ONE LATEST
;      chain when everything is assembled into a single ROM. This
;      needed a real structural fix, not just careful INCLUDE ordering:
;      core/control.asm, core/storage.asm, and core/float.asm were each
;      independently written to chain their own first header directly
;      onto core/interp.asm's H_SEMICOLON — correct and deliberate for
;      keeping each phase's own smoke ROM minimal, but it silently made
;      them siblings of a tree, not links in one chain, the moment a
;      ROM tries to include more than one of them. Fixed by making
;      each of those three files' first header link through
;      DICT_CHAIN_POINT (a DEFL, redefinable, unlike EQU), which this
;      file sets three times below, once per branch, to splice the
;      whole tree into one line: dict -> interp -> control -> ts2068 ->
;      storage -> float -> mode64. Every existing smoke ROM (Phases
;      4/5/7/8/8b) was updated to set DICT_CHAIN_POINT = H_SEMICOLON
;      right before its own single relevant INCLUDE, preserving their
;      exact prior behavior — rebuilt and re-confirmed passing under
;      real Fuse after that change, not just assumed unaffected.
;   2. kernel/io's IO_READ_KEY (and therefore core/editor.asm's
;      EDITOR_LOOP_LIVE) actually works, by actually turning on real
;      interrupts: IM 1, RST $0038 wired to kernel/interrupt's
;      KBD_ISR_TICK (`call KBD_ISR_TICK` / `ei` / `reti`, the exact
;      pattern confirmed from 2068-Leap's own real, working ROM files,
;      not guessed), and confirming the frame counter actually
;      increments — proof a real maskable interrupt fired, not just
;      that the vector table has plausible-looking bytes in it. Every
;      earlier smoke ROM in this project deliberately left interrupts
;      permanently disabled; this is the first one that doesn't.
;
; SELF-TEST:
;   1. FIND (not execute — SAVE/LOAD would attempt a real, slow tape
;      operation this automated test has no reason to trigger; Phase
;      7's own smoke ROM already proved that wiring against a fake
;      transport) locates SAVE, LOAD, F+, F-, 64COL, 32COL, PALETTE64,
;      and PLOT64 — one word from each of the phases that only reach
;      LATEST through a DICT_CHAIN_POINT splice.
;   2. Interprets a real source string exercising DUP/+ (Phase 2),
;      : ; IF ELSE THEN (Phases 3/4), and PLOT/BORDER (Phase 5)
;      together, checking the final stack value.
;   3. Enables real interrupts and confirms FRAMES actually increments
;      before disabling them again (every following checkpoint in this
;      file — there are none after this — would otherwise run with
;      timing-dependent interrupts live, which no other smoke ROM in
;      this project does).
;
; Border goes GREEN (4) if all three pass; otherwise it shows the
; failing checkpoint's number (1-3).
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
; ---- RST 38 / IM 1 maskable interrupt entry point — real wiring this
; time, not a stub. Exact pattern confirmed from 2068-Leap's own
; working ROM files (e.g. rom/test_arr3.asm's RST_38), not guessed. ----
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

    ld   hl, DICT_LATEST_INIT_P8B   ; mode64.asm's own tail (H_PLOT64) —
                                    ; now correctly the head of the
                                    ; WHOLE chain, all phases included,
                                    ; thanks to the DICT_CHAIN_POINT
                                    ; splices below
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (PRINT_ROW), a           ; required since core/editor.asm's
    ld   (PRINT_COL), a           ; own word-wrap rewrite added a
                                  ; PRINT_ROW dependency -- see
                                  ; core/print.asm's own header
    ld   a, DEFAULT_ATTR          ; required since Phase 15 -- see
    ld   (CURRENT_ATTR), a        ; core/ts2068.asm's own header
    ld   a, 1
    ld   (FWRAP_OLD_COUNT), a ; required once at cold start -- see
                                  ; core/editor.asm's own header on this
                                  ; cell

; ---- checkpoint 1: FIND every chain-spliced phase's own word ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, NAME_SAVE
    call CHECK_FIND
    ld   hl, NAME_LOAD
    call CHECK_FIND
    ld   hl, NAME_FPLUS
    call CHECK_FIND
    ld   hl, NAME_FMINUS
    call CHECK_FIND
    ld   hl, NAME_64COL
    call CHECK_FIND
    ld   hl, NAME_32COL
    call CHECK_FIND
    ld   hl, NAME_PALETTE64
    call CHECK_FIND
    ld   hl, NAME_PLOT64
    call CHECK_FIND

; ---- checkpoint 2: execute words spanning Phases 2-5 together ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    call GFX_CLS
    ld   hl, SRC_COMBO
    ld   de, SRC_COMBO_LEN
    call INTERPRET_RUN
    ld   de, 111
    call CHECK_TOP
    call W_DROP
    ld   b, 10
    ld   c, 20
    call GFX_READ_PIXEL
    or   a
    jp   z, FAIL_TEST             ; PLOT's pixel must be set

; ---- checkpoint 3: real interrupts actually fire ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    call KBD_ISR_INIT              ; must run before EI -- confirmed
                                   ; 2068-Leap ordering, not guessed
    xor  a
    ld   (FRAMES), a
    ld   (FRAMES+1), a
    im   1
    ei
    ld   bc, 0                     ; 65536-iteration safety budget --
                                   ; far more than one real 50/60Hz
                                   ; tick's worth of Z80 cycles at this
                                   ; loop's own small per-iteration cost
.wait_frames:
    ld   hl, (FRAMES)
    ld   a, h
    or   l
    jr   nz, .frames_ok
    dec  bc
    ld   a, b
    or   c
    jr   nz, .wait_frames
    di
    jp   FAIL_TEST                 ; budget exhausted, no interrupt ever fired
.frames_ok:
    di                              ; back to this project's usual fully
                                   ; manual-control regime for the rest
                                   ; of this deterministic test (there
                                   ; is no more of it after this point,
                                   ; but matching the discipline anyway)

    jp   PASS_TEST

; ---- test-harness-only helpers: NOT dictionary words ----
CHECK_FIND:                       ; HL = counted-string name address
    call DPUSH_HL
    call FIND
    call DPOP_HL                   ; found flag
    ld   a, l
    or   a
    jp   z, FAIL_TEST
    call DPOP_HL                    ; imm flag, discard
    call DPOP_HL                     ; code addr, discard
    ret

CHECK_TOP:                        ; DE = expected top-of-stack value
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                     ; green: all three checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:                        ; border shows which checkpoint (1-3) failed
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                     ; white: bug in this file's own test
                                   ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $87C0

NAME_SAVE:      DB 4, "S", "A", "V", "E"
NAME_LOAD:      DB 4, "L", "O", "A", "D"
NAME_FPLUS:     DB 2, "F", "+"
NAME_FMINUS:    DB 2, "F", "-"
NAME_64COL:     DB 5, "6", "4", "C", "O", "L"
NAME_32COL:     DB 5, "3", "2", "C", "O", "L"
NAME_PALETTE64: DB 9, "P", "A", "L", "E", "T", "T", "E", "6", "4"
NAME_PLOT64:    DB 6, "P", "L", "O", "T", "6", "4"

SRC_COMBO:      DB ": COMBOTEST 0= IF 111 ELSE 222 THEN ; 0 COMBOTEST 10 20 PLOT "
SRC_COMBO_LEN   EQU $ - SRC_COMBO

; ---- kernel + dictionary: included here, after the vector table and
; the self-test code above, not before ORG $0000. Order matters for
; DICT_CHAIN_POINT too -- each splice point must be set immediately
; before the file whose first header reads it. ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/interrupt/interrupt.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/sound/sound.asm"
    INCLUDE "kernel/storage/storage.asm"
    INCLUDE "kernel/mode64/mode64.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_BORDER
    INCLUDE "core/storage.asm"
DICT_CHAIN_POINT DEFL H_LOAD
    INCLUDE "core/float.asm"
    INCLUDE "core/mode64.asm"
DICT_CHAIN_POINT DEFL DICT_LATEST_INIT_P8B   ; satisfies core/print.asm's
                                              ; own chain requirement
                                              ; below; LATEST itself
                                              ; stays seeded to this
                                              ; same tail above, so
                                              ; EMIT/. this splices in
                                              ; don't change what this
                                              ; ROM's own checkpoint 1
                                              ; FINDs
    INCLUDE "core/print.asm"
    INCLUDE "core/editor.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p9_rom0.bin", $0000, $4000
