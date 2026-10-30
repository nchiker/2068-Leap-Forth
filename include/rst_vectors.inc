; ============================================================================
; rst_vectors.inc — page zero from $0008 up to (not including) RST_38
;
; O13 (docs/V2/LEAPC_COMPARISON_AUDIT.md): the data-stack pop and push
; (DPOP_HL / DPUSH_HL, formerly 11-byte routines in core/dict.asm) live
; in the first two RST vectors, so every `call DPOP_HL` / `call DPUSH_HL`
; becomes a 1-byte `rst RST_DPOP` / `rst RST_DPUSH`. That is 242 call
; sites in the HOME image, 3 B -> 1 B each, and 17 T -> 11 T per use
; (RST 11 T instead of CALL 17 T; the body and its RET are unchanged).
; Behaviour is identical: same registers, same flags, same stack effect.
;
; Layout (each body is 11 bytes and fits in its 16-byte vector slot):
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
RST_08:
DPOP_HL:                   ; pop the data stack into HL
    ld   l, (ix+0)
    ld   h, (ix+1)
    inc  ix
    inc  ix
    ret
    ASSERT $ <= $0018
    ASSERT RST_08 == RST_DPOP

    DS   $0018 - $, $FF
RST_18:
DPUSH_HL:                  ; push HL onto the data stack
    dec  ix
    dec  ix
    ld   (ix+0), l
    ld   (ix+1), h
    ret
    ASSERT $ <= $0028
    ASSERT RST_18 == RST_DPUSH

    DS   $0028 - $, $FF
RST_28:
    ret

    DS   $0030 - $, $FF
RST_30:
    ret

    ASSERT $ <= $0038
    DS   $0038 - $, $FF
    ASSERT $ == $0038
