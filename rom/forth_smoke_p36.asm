; ============================================================================
; rom/forth_smoke_p36.asm — Phase 36 smoke ROM: CLS, KEY?, C@, C!
;
; SIX CHECKPOINTS:
;   1. C! stores only the LOW byte: C! 300 ($012C) at a scratch
;      address, read the raw byte back directly -- must be 44 ($2C),
;      not 300 and not $01.
;   2. C@ zero-extends: C! 200 (a byte with its own top bit set) then
;      C@ it back -- must be exactly 200 on the data stack, not
;      sign-extended to a negative cell.
;   3. CLS actually clears attribute memory: poison row 0 col 0's own
;      attribute byte with $FF, call CLS, confirm it now reads
;      ATTR_DEFAULT ($44) -- kernel/graphics's own GFX_CLS contract,
;      now reachable as a word for the first time.
;   4. KEY? is FALSE when nothing is latched (KBD_KEYHIT forced to 0
;      first -- cold RAM isn't guaranteed clear, matching this
;      project's own "no assumed default" convention elsewhere).
;   5. KEY? is TRUE once a key IS latched, AND stays TRUE on a SECOND
;      call -- the whole point of this word over the already-existing
;      IO_READ_KEY_NONBLOCK: a non-destructive lookahead must not
;      consume what it finds.
;   6. KEY (the ALREADY-existing blocking word) then actually consumes
;      that same latched key -- confirmed two ways at once: KEY itself
;      returns the right character, AND a follow-up KEY? now reads
;      FALSE, proving the key really is gone.
;
; Border goes GREEN (4) if all six pass; otherwise it shows the
; failing checkpoint's number.
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
    ei
    ret
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

    ld   hl, DICT_LATEST_INIT_BYTEMEM
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    call GFX_CLS

; ---- checkpoint 1: C! stores only the low byte ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 300
    call DPUSH_HL
    ld   hl, SCRATCH_BYTE_1
    call DPUSH_HL
    call W_CSTORE
    ld   a, (SCRATCH_BYTE_1)
    cp   44
    jp   nz, FAIL_TEST

; ---- checkpoint 2: C@ zero-extends ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 200
    call DPUSH_HL
    ld   hl, SCRATCH_BYTE_2
    call DPUSH_HL
    call W_CSTORE
    ld   hl, SCRATCH_BYTE_2
    call DPUSH_HL
    call W_CFETCH
    ld   de, 200
    call CHECK_ITOP

; ---- checkpoint 3: CLS actually clears attribute memory ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   a, $FF
    ld   (ATTR_ADDR), a
    call W_CLS
    ld   a, (ATTR_ADDR)
    cp   ATTR_DEFAULT
    jp   nz, FAIL_TEST

; ---- checkpoint 4: KEY? is FALSE when nothing is latched ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    xor  a
    ld   (KBD_KEYHIT), a
    call W_KEYQ
    ld   de, 0
    call CHECK_ITOP

; ---- checkpoint 5: KEY? is TRUE once latched, and stays TRUE on a
; second call -- doesn't consume it ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   a, 1
    ld   (KBD_KEYHIT), a
    ld   a, "X"
    ld   (KBD_LASTK), a
    call W_KEYQ
    ld   de, -1
    call CHECK_ITOP
    call W_KEYQ
    ld   de, -1
    call CHECK_ITOP

; ---- checkpoint 6: KEY actually consumes it -- both the returned
; character AND a follow-up KEY? going FALSE ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    call W_KEY
    ld   de, "X"
    call CHECK_ITOP
    call W_KEYQ
    ld   de, 0
    call CHECK_ITOP

    jp   PASS_TEST

; ============================================================================
; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch. Identical to
; rom/forth_smoke_p34.asm's own CHECK_ITOP.
; ============================================================================
CHECK_ITOP:
    call DPOP_HL
    ld   a, l
    cp   e
    jp   nz, FAIL_TEST
    ld   a, h
    cp   d
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all six checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM  EQU $8800
SCRATCH_BYTE_1  EQU $8801
SCRATCH_BYTE_2  EQU $8802

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/io/io.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/control.asm"
DICT_CHAIN_POINT DEFL H_UNTIL
    INCLUDE "core/ts2068.asm"
DICT_CHAIN_POINT DEFL H_CLS
    INCLUDE "core/key.asm"
DICT_CHAIN_POINT DEFL H_KEYQ
    INCLUDE "core/bytemem.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p36_rom0.bin", $0000, $4000
