; ============================================================================
; rom/test_exrom_isolation.asm — fresh chunk-5 EXROM paging isolation test
;
; kernel/bank/bank.asm was retargeted from chunk 6 (2068-Leap's own,
; hardware-confirmed choice) to chunk 5 (this project's own chunk-by-
; chunk audit — see that file's own header) this session. The chunk-6
; proof doesn't transfer to chunk 5 automatically — this file is the
; fresh, from-scratch confirmation for THIS project's own choice, not
; a rebuild of the inherited one (that file, rom/test_exrom_
; isolation.asm in 2068-Leap, was never copied into this repo).
;
; FOUR CHECKPOINTS, run against a real EXROM image (see tools/
; make_test_exrom.sh) filled entirely with $A5 — a value that can't be
; mistaken for either RAM's own $00 power-on-adjacent contents or the
; $FF this project's other placeholder EXROM images use:
;   1. Sanity: write $5A to $A000 (chunk 5's own first byte) as plain
;      Home RAM, read it back — must be $5A. Proves ordinary RAM works
;      at this address BEFORE any paging is involved, so a later
;      mismatch can only mean paging actually did something.
;   2. BANK_PAGE_EXROM_IN, then read $A000 again — must now be $A5 (the
;      EXROM image's own marker byte), not $5A. Proves chunk 5 really
;      did switch to EXROM content.
;   3. Control: WHILE still paged in, read a byte at $C000 (chunk 6,
;      never paged by this project's own choice) — must still read
;      back as plain RAM (write a marker there first, same as
;      checkpoint 1), proving paging is chunk-5-SPECIFIC, not
;      accidentally wider.
;   4. BANK_PAGE_EXROM_OUT, then read $A000 one more time — must be
;      $5A again, the exact byte checkpoint 1 wrote. Proves paging is
;      non-destructive: the underlying chunk-5 RAM was never touched,
;      only briefly made invisible.
;
; A fifth check folded into checkpoint 4: BANK_EXROM_DEPTH must read
; back 0 once fully unpaged — confirms the nesting counter itself
; balances correctly for the simple, non-nested single call this test
; makes (nested-call behavior is documented, not separately proven
; here — this test's job is confirming the chunk-5 retargeting itself,
; not re-proving nesting logic that didn't change).
;
; Border goes GREEN (4) if all four checkpoints pass; otherwise it
; shows the failing checkpoint's number. White (7) is reserved the
; same way every other smoke ROM in this project uses it.
; ============================================================================

    INCLUDE "include/hardware.inc"
    INCLUDE "include/sysvars.inc"

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
    xor  a                       ; explicit, not assumed: every chunk
    out  (PORT_BANK_HOME), a     ; starts Home-mapped, matching this
                                 ; project's own "no assumed cold-boot
                                 ; default" convention rather than
                                 ; trusting hardware reset state

; ---- checkpoint 1: plain RAM sanity at $A000, before any paging ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   a, $5A
    ld   ($A000), a
    ld   a, ($A000)
    cp   $5A
    jp   nz, FAIL_TEST

; ---- checkpoint 2: page chunk 5 to EXROM, $A000 must now read $A5 ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    call BANK_PAGE_EXROM_IN
    ld   a, ($A000)
    cp   $A5
    jp   nz, FAIL_TEST

; ---- checkpoint 3: chunk 6 must stay plain Home RAM while chunk 5
;      is paged -- proves the paging is chunk-5-specific ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   a, $C6
    ld   ($C000), a
    ld   a, ($C000)
    cp   $C6
    jp   nz, FAIL_TEST

; ---- checkpoint 4: page back out -- $A000 must be exactly the
;      checkpoint-1 byte again, and BANK_EXROM_DEPTH must be 0 ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    call BANK_PAGE_EXROM_OUT
    ld   a, ($A000)
    cp   $5A
    jp   nz, FAIL_TEST
    ld   a, (BANK_EXROM_DEPTH)
    or   a
    jp   nz, FAIL_TEST

    jp   PASS_TEST

PASS_TEST:
    ld   a, 4                    ; green: all four checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, (CHECKPOINT_NUM)
    out  (PORT_ULA), a
    jr   FAIL_TEST

CHECKPOINT_NUM EQU $8800

    INCLUDE "kernel/bank/bank.asm"

    DS   $4000 - $, $FF

    SAVEBIN "test_exrom_isolation_rom0.bin", $0000, $4000
