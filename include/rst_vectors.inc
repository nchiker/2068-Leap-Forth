; ============================================================================
; include/rst_vectors.inc -- page zero from $0008 up to (not including) RST_38
;
; The data-stack pop and push live in the first two RST vectors, so `rst RST_DPOP` /
; `rst RST_DPUSH` (1 byte, 11 T) replace `call DPOP_HL` / `call DPUSH_HL` (3 bytes, 17 T).
; Each body is 11 bytes and fits its 16-byte slot:
;   $0008  DPOP_HL  (RST_08)   pop the data stack into HL
;   $0018  DPUSH_HL (RST_18)   push HL onto the data stack
;   $0028  RST_28              ret (unused)
;   $0030  RST_30              ret (unused)
;   $0038  RST_38 follows, defined by the including ROM
;
; rom/forth_boot.asm INCLUDEs this file at $0008, straight after the RST_00 stub.
; ============================================================================

RST_DPOP    EQU $08
RST_DPUSH   EQU $18

    ASSERT $ <= $0008
    DS   $0008 - $, $FF
; ============================================================================
; DPOP_HL (RST_DPOP) -- pop the data stack into HL
; In:  IX = the data stack pointer
; Out: HL = the popped cell, IX += 2
; Destroys: HL
; ============================================================================
RST_08:
DPOP_HL:
    ld   l, (ix+0)
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ret
    ASSERT $ <= $0018
    ASSERT RST_08 == RST_DPOP

    DS   $0018 - $, $FF
; ============================================================================
; DPUSH_HL (RST_DPUSH) -- push HL onto the data stack
; In:  HL = the cell, IX = the data stack pointer
; Out: IX -= 2, the cell stored at (IX)
; Destroys: nothing
; ============================================================================
RST_18:
DPUSH_HL:
    dec  ix
    dec  ix
    ld   (ix+0), l
    ld   (ix+1), h
    ret
    ASSERT $ <= $0028
    ASSERT RST_18 == RST_DPUSH

    DS   $0028 - $, $FF
; RST_28, RST_30 -- unused vectors: just return
RST_28:
    ret

    DS   $0030 - $, $FF
RST_30:
    ret

    ASSERT $ <= $0038
    DS   $0038 - $, $FF
    ASSERT $ == $0038
