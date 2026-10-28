; rom/bench/bench_sieve.asm -- SIEVE OF ERATOSTHENES benchmark driver.
; Boilerplate copied from rom/forth_demo_blackjack.asm's own proven
; COLD_START/include chain (same kernel+core subset, same DICT_CHAIN_POINT
; splice order) -- this is scaffolding for
; ~/2068-rom-benchmarks/benchmarks/forth/sieve.fs, not a product ROM.
; Build:  ../../sjasmplus/build/sjasmplus rom/bench/bench_sieve.asm  (from repo root)
; Run under ZEsarUX with a stock-shaped EXROM, same as any other rom/ build.

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

COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   iy, FSTACK_TOP

    xor  a
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   hl, DICT_LATEST_INIT_STACKOPS
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

    ld   hl, SRC_BENCH
    ld   de, SRC_BENCH_LEN
    call INTERPRET_RUN

.hang:
    jr   .hang

INTERPRET_UNKNOWN_WORD:
    ld   a, 7
    out  (PORT_ULA), a
    ld   hl, BUG_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .hang2
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.hang2:
    jr   .hang2

BUG_MSG: DB "BUG", 0

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
    INCLUDE "core/bytemem.asm"
DICT_CHAIN_POINT DEFL H_CSTORE
    INCLUDE "core/logic.asm"
DICT_CHAIN_POINT DEFL H_INVERT
    INCLUDE "core/udg.asm"
DICT_CHAIN_POINT DEFL H_UDG
    INCLUDE "core/stackops.asm"

; ============================================================================
; SRC_BENCH -- the actual sieve.fs benchmark text, adapted inline
; (kept a straight-line string here rather than #INCLUDE'd from the
; .fs file, since INTERPRET_RUN wants one contiguous DB block with a
; length, and comments/newlines in the .fs file aren't meaningful to
; it anyway -- semantics match benchmarks/forth/sieve.fs exactly).
; ============================================================================
SRC_BENCH:
    DB "3000 CONSTANT REPS 3 ARRAY XV 3 ARRAY YV "
    DB "VARIABLE AX VARIABLE BY VARIABLE T0 VARIABLE T1 "
    DB ": GET-FRAMES 33515 @ ; "
    DB ": SETUP "
    DB "128 0 CELLS XV + ! 8 0 CELLS YV + ! "
    DB "16 1 CELLS XV + ! 184 1 CELLS YV + ! "
    DB "240 2 CELLS XV + ! 184 2 CELLS YV + ! "
    DB "128 AX ! 96 BY ! ; "
    DB ": RUN-PIXEL REPS 0 DO "
    DB "3 RND "
    DB "DUP CELLS XV + @ AX @ + 2 / AX ! "
    DB "DUP CELLS YV + @ BY @ + 2 / BY ! "
    DB "1+ INK AX @ BY @ PLOT "
    DB "LOOP ; "
    DB "0 RANDOMIZE SETUP CLS "
    DB ": BENCH 2 BORDER GET-FRAMES T0 ! RUN-PIXEL GET-FRAMES T1 ! "
    DB "4 BORDER 0 INK "
    DB ".\" FRAMES=\" T1 @ T0 @ - . .\" N=\" REPS . .\" RESULT=\" AX @ BY @ + . ; "
    DB "BENCH "
SRC_BENCH_LEN EQU $ - SRC_BENCH

    SAVEBIN "bench_pixel_rom0.bin", $0000, $8000
