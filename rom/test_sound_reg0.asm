; ============================================================================
; rom/test_sound_reg0.asm -- SOUND must reach AY chip register 0 (audit O9)
;
; rom/forth_smoke_p32.asm only checks data-stack hygiene. This one reads the chip back: it selects a
; register through PORT_AY_REG and reads PORT_AY_DATA (the AY-3-8912 registers are readable), so it can
; tell whether `SOUND` really wrote the register. Chip register 0 is Channel A's tone-period fine byte.
; Until step R0 SOUND refused register 0 (a faithful copy of what Forth believed the real ROM did; the
; Leap V2 maintenance line, 6493615, takes 0-16, as does this tree now).
;
;   1. Preset chip register 0 to $00 directly, run `0 165 SOUND`, read register 0: must be 165.
;   2. `0 90 SOUND`, read register 0: must be 90 (so checkpoint 1 was not a coincidence).
;   3. `1 7 SOUND`, read register 1: must be 7 (a register that always worked still works).
;   4. `17 200 SOUND` (still rejected): chip register 0 must still be 90, and the data stack is balanced.
;
; Border GREEN (4) = pass, otherwise the failing checkpoint's number (1-4).
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

COLD_START:
    ld   sp, $FF00
    ld   ix, DSTACK_TOP
    ld   hl, DICT_LATEST_INIT_SOUND
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

    ; ---- 1 ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    xor  a
    out  (PORT_AY_REG), a            ; select chip register 0 ...
    out  (PORT_AY_DATA), a           ; ... and clear it
    ld   hl, SRC_1
    ld   de, SRC_1_LEN
    call INTERPRET_RUN
    ld   b, 0
    ld   c, 165
    call EXPECT_REG
    ; ---- 2 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_2
    ld   de, SRC_2_LEN
    call INTERPRET_RUN
    ld   b, 0
    ld   c, 90
    call EXPECT_REG
    ; ---- 3 ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_3
    ld   de, SRC_3_LEN
    call INTERPRET_RUN
    ld   b, 1
    ld   c, 7
    call EXPECT_REG
    ; ---- 4 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    call DPUSH_HL
    ld   hl, SRC_4
    ld   de, SRC_4_LEN
    call INTERPRET_RUN
    ld   l, (ix+0)
    ld   h, (ix+1)
    ld   de, 4242
    or   a
    sbc  hl, de
    jr   nz, FAIL_TEST               ; the rejected call must leave the stack balanced
    ld   b, 0
    ld   c, 90
    call EXPECT_REG

PASS_TEST:
    ld   a, 4
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

; EXPECT_REG: chip register B must read C, else FAIL_TEST
EXPECT_REG:
    ld   a, b
    out  (PORT_AY_REG), a
    in   a, (PORT_AY_DATA)
    cp   c
    jr   nz, FAIL_TEST
    ret

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                        ; white: a bug in this file's own test source
    out  (PORT_ULA), a
.hang:
    jr   .hang

CHECKPOINT_NUM EQU $8800

SRC_1: DB "0 165 SOUND "
SRC_1_LEN EQU $ - SRC_1
SRC_2: DB "0 90 SOUND "
SRC_2_LEN EQU $ - SRC_2
SRC_3: DB "1 7 SOUND "
SRC_3_LEN EQU $ - SRC_3
SRC_4: DB "17 200 SOUND "
SRC_4_LEN EQU $ - SRC_4

    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/sound.asm"

    DS   $4000 - $, $FF

    SAVEBIN "test_sound_reg0_rom0.bin", $0000, $4000
