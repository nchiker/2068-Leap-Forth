; ============================================================================
; rom/forth_smoke_p63.asm — Phase 63 smoke ROM: TONE, VOLUME, MIXER,
; NOISE, ENVELOPE
;
; SEVEN CHECKPOINTS, all data-stack-hygiene checks — same honest limit
; as core/sound.asm's own SOUND checkpoints (rom/forth_smoke_p32.asm):
; this project keeps no software shadow of the AY-3-8912's ports, and
; there is no way for a border-color smoke ROM to read back what the
; (emulated) chip's own registers actually hold, so "the right bytes
; reached the right registers" was hand-verified against the real
; AY-3-8912 register map instead (see each word's own header in
; core/sound.asm) rather than machine-checked here. What IS checked:
; every word consumes exactly its own stated stack arguments and
; nothing else, on both a representative valid input and (for TONE and
; VOLUME, the two words with an actual rejection path) an out-of-range
; channel.
;
;   1. TONE with a valid channel (1/Channel B) and period.
;   2. TONE with an out-of-range channel (3) — silently ignored.
;   3. VOLUME with a valid channel (2/Channel C) and level.
;   4. VOLUME with an out-of-range channel (200) — silently ignored.
;   5. MIXER with a representative mask — MIXER has no rejection path
;      (the mask is used as-is, not validated), so this is the only
;      checkpoint for it.
;   6. NOISE with a representative period — same reasoning, no
;      rejection path (masked, not validated).
;   7. ENVELOPE with a representative period and shape — same
;      reasoning, no rejection path.
;
; Border goes GREEN (4) if all seven pass; otherwise it shows the
; failing checkpoint's number.
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K
    ORG $0000

RST_00:
    di
    jp   COLD_START
    INCLUDE "include/rst_vectors.inc"
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

    ld   hl, DICT_LATEST_INIT_SOUNDEXT
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a

; ---- checkpoint 1: TONE, valid channel (1) ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 1                    ; channel = 1 (B)
    rst RST_DPUSH
    ld   hl, $0AB0                ; period
    rst RST_DPUSH
    call W_TONE
    ld   de, 4242
    call CHECK_ITOP

; ---- checkpoint 2: TONE, out-of-range channel (3) -- ignored ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 3                    ; channel = 3 -- out of range
    rst RST_DPUSH
    ld   hl, $0AB0
    rst RST_DPUSH
    call W_TONE
    ld   de, 4242
    call CHECK_ITOP

; ---- checkpoint 3: VOLUME, valid channel (2) ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 2                    ; channel = 2 (C)
    rst RST_DPUSH
    ld   hl, 15                   ; level
    rst RST_DPUSH
    call W_VOLUME
    ld   de, 4242
    call CHECK_ITOP

; ---- checkpoint 4: VOLUME, out-of-range channel (200) -- ignored ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 200                  ; channel = 200 -- out of range
    rst RST_DPUSH
    ld   hl, 15
    rst RST_DPUSH
    call W_VOLUME
    ld   de, 4242
    call CHECK_ITOP

; ---- checkpoint 5: MIXER, representative mask ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 253                  ; mask -- only Channel B's tone
                                  ; enabled, same value SOUND's own
                                  ; header cites as user-confirmed
    rst RST_DPUSH
    call W_MIXER
    ld   de, 4242
    call CHECK_ITOP

; ---- checkpoint 6: NOISE, representative period ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 31                   ; period
    rst RST_DPUSH
    call W_NOISE
    ld   de, 4242
    call CHECK_ITOP

; ---- checkpoint 7: ENVELOPE, representative period and shape ----
    ld   a, 7
    ld   (CHECKPOINT_NUM), a
    ld   hl, 4242
    rst RST_DPUSH
    ld   hl, 1000                 ; period
    rst RST_DPUSH
    ld   hl, 14                   ; shape
    rst RST_DPUSH
    call W_ENVELOPE
    ld   de, 4242
    call CHECK_ITOP

    jp   PASS_TEST

; ============================================================================
; CHECK_ITOP ( DE = expected -- )  pops the integer stack into HL and
; compares against DE; halts with the border showing the current
; checkpoint number on any mismatch. Identical to
; rom/forth_smoke_p62.asm's own CHECK_ITOP.
; ============================================================================
CHECK_ITOP:
    rst RST_DPOP
    ld   a, l
    cp   e
    jp   nz, FAIL_TEST
    ld   a, h
    cp   d
    jp   nz, FAIL_TEST
    ret

PASS_TEST:
    ld   a, 4                    ; green: all seven checkpoints passed
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

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "core/dict.asm"
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/sound.asm"
DICT_CHAIN_POINT DEFL H_SOUND
    INCLUDE "core/soundext.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p63_rom0.bin", $0000, $4000
