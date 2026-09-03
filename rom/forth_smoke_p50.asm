; ============================================================================
; rom/forth_smoke_p50.asm — Phase 50 smoke ROM: the "architectural tier"
; of the Jupiter Ace word-gap audit: HERE, , (COMMA), C,, ALLOT
; (core/dictspace.asm); CREATE, DOES> (core/create.asm/core/does.asm);
; IMMEDIATE (core/immediate.asm); ABORT, QUIT (core/abortquit.asm); IN,
; OUT (core/portio.asm); FORGET (core/forget.asm)
;
; ELEVEN checkpoints, numbered 0-10, reported by PRINTING the failing
; number (via `.`) rather than encoding it in the 3-bit border color —
; this project's own history (documented in core/vlist.asm's sibling
; smoke ROMs, Phase 40/46/49) already hit real aliasing bugs trying to
; cram more than 6 distinguishable values through PORT_ULA's border.
; Twelve genuinely different topics don't fit that scheme at all without
; awkward grouping, so this file uses the task's own suggested escape
; hatch instead: a real, unambiguous printed number.
;   0.  HERE / , / C, / ALLOT (core/dictspace.asm), including a negative
;       ALLOT to prove the dictionary can legitimately SHRINK too (two's
;       complement handles it for free, not a special case).
;   1.  CREATE with NO DOES> ever applied — the classic minimal runtime
;       (push data field address, RET).
;   2.  DOES> #1 — a scalar CONST-style word (`: CONST CREATE , DOES>
;       @ ;`), used TWICE (FIVE and SEVEN) to prove each fresh CREATE
;       gets its own independent patch, not one shared/hardcoded target.
;   3.  DOES> #2 — an array-style word using CELLS (core/array.asm,
;       confirmed present before use) with a THREE-word action part
;       (`SWAP CELLS + @`), proving the mechanism isn't hardcoded to a
;       single trailing word.
;   4.  IMMEDIATE — marks a plain word immediate after the fact, then
;       proves it executes (not compiles) by observing its side effect
;       land DURING another word's own compilation, and proves the
;       compiling word's own body ends up EMPTY of it (no double-effect
;       when that word is later invoked).
;   5.  ABORT — data stack AND float stack both wiped, and code after
;       ABORT on the same line never runs.
;   6.  QUIT — same "code after never runs" behavior, but data AND float
;       stack CONTENTS survive untouched — the actual point of having
;       two separate words, not just an alias.
;   7.  ABORT/QUIT's own judgment-call reset of CATCH_DEPTH/LEAVE_DEPTH
;       (core/abortquit.asm's own header, judgment call 2) — proven
;       directly by poisoning both cells with nonzero values first.
;   8.  IN / OUT — a real AY-3-8912 register round trip (select register
;       8 via OUT to PORT_AY_REG, write via OUT to PORT_AY_DATA, read
;       the same register back via IN) — a genuine hardware round trip,
;       not a simulated port.
;   9.  FORGET of a RAM-resident word — proves HERE/LATEST are rewound
;       EXACTLY to the forgotten word's own former header address (not
;       approximately), and that a redefinition afterward reuses that
;       exact reclaimed space (not merely that the name became findable
;       again).
;  10.  FORGET of a ROM-resident word (DUP) — refused: HERE/LATEST both
;       provably unchanged, and DUP itself still fully functional
;       afterward.
;
; Border goes GREEN (4) if every checkpoint passes; on any failure the
; border goes RED (2) and the failing checkpoint's number prints via `.`
; before the ROM hangs. A bug in this file's OWN test source (an
; unrecognized word, or an uncaught runtime error) shows WHITE (7) and
; the literal text "BUG" instead, matching this project's own
; established "distinguish a real checkpoint failure from a bug in the
; test itself" convention.
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
    ld   iy, FSTACK_TOP

    ld   hl, DICT_LATEST_INIT_FORGET
    ld   (LATEST), hl
    ld   hl, FORTH_DICT_RAM
    ld   (HERE), hl
    xor  a
    ld   (STATE), a
    ld   (CATCH_DEPTH), a
    ld   (LEAVE_DEPTH), a
    xor  a
    ld   (PRINT_ROW), a
    ld   (PRINT_COL), a

    call GFX_CLS

; ---- checkpoint 0: HERE / , / C, / ALLOT ----
    ld   a, 0
    ld   (CHECKPOINT_NUM), a

    ld   hl, (HERE)
    ex   de, hl
    call W_HERE
    call CHECK_TOP
    call W_DROP

    ld   hl, (HERE)
    ld   (CK_TMP1), hl
    ld   hl, $ABCD
    call DPUSH_HL
    call W_COMMA
    ld   hl, (CK_TMP1)
    ld   de, 2
    add  hl, de
    ex   de, hl                  ; de = expected HERE
    ld   hl, (HERE)
    call CHECK_HL_DE
    ld   hl, (CK_TMP1)
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ex   de, hl                  ; hl = word actually written
    ld   de, $ABCD
    call CHECK_HL_DE

    ld   hl, (HERE)
    ld   (CK_TMP1), hl
    ld   hl, $42
    call DPUSH_HL
    call W_CCOMMA
    ld   hl, (CK_TMP1)
    inc  hl
    ex   de, hl
    ld   hl, (HERE)
    call CHECK_HL_DE
    ld   hl, (CK_TMP1)
    ld   a, (hl)
    ld   l, a
    ld   h, 0
    ld   de, $42
    call CHECK_HL_DE

    ld   hl, (HERE)
    ld   (CK_TMP1), hl
    ld   hl, 10
    call DPUSH_HL
    call W_ALLOT
    ld   hl, (CK_TMP1)
    ld   de, 10
    add  hl, de
    ex   de, hl
    ld   hl, (HERE)
    call CHECK_HL_DE

    ld   hl, (HERE)               ; negative ALLOT: dictionary shrinks
    ld   (CK_TMP1), hl
    ld   hl, -4
    call DPUSH_HL
    call W_ALLOT
    ld   hl, (CK_TMP1)
    ld   de, -4
    add  hl, de
    ex   de, hl
    ld   hl, (HERE)
    call CHECK_HL_DE

; ---- checkpoint 1: CREATE with no DOES> -- classic minimal runtime ----
    ld   a, 1
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_C1_DEF
    ld   de, SRC_C1_DEF_LEN
    call INTERPRET_RUN            ; : T1 CREATE 1234 , ; T1 T1FOO
    ld   hl, SRC_C1_USE
    ld   de, SRC_C1_USE_LEN
    call INTERPRET_RUN            ; T1FOO @
    ld   de, 1234
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 2: DOES> #1 -- scalar CONST-style, used twice ----
    ld   a, 2
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_D1_DEF
    ld   de, SRC_D1_DEF_LEN
    call INTERPRET_RUN             ; : CONST CREATE , DOES> @ ;
    ld   hl, SRC_D1_MK1
    ld   de, SRC_D1_MK1_LEN
    call INTERPRET_RUN              ; 5 CONST FIVE
    ld   hl, SRC_D1_USE1
    ld   de, SRC_D1_USE1_LEN
    call INTERPRET_RUN               ; FIVE
    ld   de, 5
    call CHECK_TOP
    call W_DROP
    ld   hl, SRC_D1_MK2
    ld   de, SRC_D1_MK2_LEN
    call INTERPRET_RUN                ; 7 CONST SEVEN
    ld   hl, SRC_D1_USE2
    ld   de, SRC_D1_USE2_LEN
    call INTERPRET_RUN                 ; SEVEN
    ld   de, 7
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 3: DOES> #2 -- array-style, SWAP CELLS + @ ----
    ld   a, 3
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_D2_DEF
    ld   de, SRC_D2_DEF_LEN
    call INTERPRET_RUN     ; : ARR3 CREATE 10 , 20 , 30 , DOES> SWAP CELLS + @ ; ARR3 NUMS
    ld   hl, SRC_D2_USE0
    ld   de, SRC_D2_USE0_LEN
    call INTERPRET_RUN      ; 0 NUMS
    ld   de, 10
    call CHECK_TOP
    call W_DROP
    ld   hl, SRC_D2_USE1
    ld   de, SRC_D2_USE1_LEN
    call INTERPRET_RUN       ; 1 NUMS
    ld   de, 20
    call CHECK_TOP
    call W_DROP
    ld   hl, SRC_D2_USE2
    ld   de, SRC_D2_USE2_LEN
    call INTERPRET_RUN        ; 2 NUMS
    ld   de, 30
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 4: IMMEDIATE -- executes at compile time, not compiled ----
    ld   a, 4
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_IMM_DEF
    ld   de, SRC_IMM_DEF_LEN
    call INTERPRET_RUN         ; : FOO 42 ; IMMEDIATE
    ld   hl, SRC_IMM_USE
    ld   de, SRC_IMM_USE_LEN
    call INTERPRET_RUN          ; : BAR FOO ;  -- FOO runs NOW, pushing 42
    ld   de, 42
    call CHECK_TOP
    call W_DROP
    push ix
    pop  de
    ld   (CK_TMP1), de           ; IX depth before invoking BAR
    ld   hl, SRC_IMM_CALL
    ld   de, SRC_IMM_CALL_LEN
    call INTERPRET_RUN            ; BAR -- must be a no-op (just RET)
    push ix
    pop  hl
    ld   de, (CK_TMP1)
    call CHECK_HL_DE

; ---- checkpoint 5: ABORT -- clears data AND float stacks ----
    ld   a, 5
    ld   (CHECKPOINT_NUM), a
    ld   hl, $1234
    ld   a, 5
    call FPUSH                    ; seed the float stack with a dummy value
    ld   hl, SRC_ABORT
    ld   de, SRC_ABORT_LEN
    call INTERPRET_RUN             ; 42 ABORT 99
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    call CHECK_HL_DE                ; data stack empty -- 42 wiped, 99
                                      ; never pushed
    push iy
    pop  hl
    ld   de, FSTACK_TOP
    call CHECK_HL_DE                 ; float stack empty -- dummy wiped

; ---- checkpoint 6: QUIT -- data AND float stack CONTENTS survive ----
    ld   a, 6
    ld   (CHECKPOINT_NUM), a
    ld   hl, $5678
    ld   a, 3
    call FPUSH                      ; a fresh dummy float
    ld   hl, SRC_QUIT
    ld   de, SRC_QUIT_LEN
    call INTERPRET_RUN               ; 42 QUIT 99
    ld   de, 42
    call CHECK_TOP                    ; the 42 survived; 99 never ran
    call W_DROP
    push ix
    pop  hl
    ld   de, DSTACK_TOP
    call CHECK_HL_DE                    ; exactly one cell was there,
                                          ; nothing else
    push iy
    pop  hl
    ld   de, FSTACK_TOP
    dec  de
    dec  de
    dec  de
    call CHECK_HL_DE                     ; the dummy float is still there
    call FPOP                             ; tidy up

; ---- checkpoint 7: ABORT/QUIT also reset CATCH_DEPTH/LEAVE_DEPTH ----
    ld   a, 7
    ld   (CHECKPOINT_NUM), a
    ld   a, 3
    ld   (CATCH_DEPTH), a
    ld   a, 2
    ld   (LEAVE_DEPTH), a
    ld   hl, SRC_ABORT_BARE
    ld   de, SRC_ABORT_BARE_LEN
    call INTERPRET_RUN                     ; ABORT
    ld   a, (CATCH_DEPTH)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (LEAVE_DEPTH)
    or   a
    jp   nz, FAIL_TEST
    ld   a, 4
    ld   (CATCH_DEPTH), a
    ld   a, 1
    ld   (LEAVE_DEPTH), a
    ld   hl, SRC_QUIT_BARE
    ld   de, SRC_QUIT_BARE_LEN
    call INTERPRET_RUN                      ; QUIT
    ld   a, (CATCH_DEPTH)
    or   a
    jp   nz, FAIL_TEST
    ld   a, (LEAVE_DEPTH)
    or   a
    jp   nz, FAIL_TEST

; ---- checkpoint 8: IN / OUT -- real AY-3-8912 register round trip ----
    ld   a, 8
    ld   (CHECKPOINT_NUM), a
    ld   hl, SRC_PORT
    ld   de, SRC_PORT_LEN
    call INTERPRET_RUN        ; 8 245 OUT  12 246 OUT  8 245 OUT  246 IN
    ld   de, 12
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 9: FORGET a RAM-resident word -- exact rewind + reuse ----
    ld   a, 9
    ld   (CHECKPOINT_NUM), a
    ld   hl, (LATEST)
    ld   (CK_TMP2), hl            ; LATEST BEFORE defining ZZZ
    ld   hl, SRC_F1_DEF
    ld   de, SRC_F1_DEF_LEN
    call INTERPRET_RUN             ; : ZZZ 111 ;
    ld   hl, (LATEST)
    ld   (CK_TMP1), hl              ; ZZZ's own header address
    ld   hl, SRC_F1_FORGET
    ld   de, SRC_F1_FORGET_LEN
    call INTERPRET_RUN               ; FORGET ZZZ
    ld   hl, (HERE)
    ld   de, (CK_TMP1)
    call CHECK_HL_DE                  ; HERE rewound EXACTLY to ZZZ's
                                        ; own former header address
    ld   hl, (LATEST)
    ld   de, (CK_TMP2)
    call CHECK_HL_DE                    ; LATEST back to pre-ZZZ value
    ld   hl, SRC_F1_REDEF
    ld   de, SRC_F1_REDEF_LEN
    call INTERPRET_RUN                   ; : ZZZ 222 ;
    ld   hl, (LATEST)
    ld   de, (CK_TMP1)
    call CHECK_HL_DE                      ; new ZZZ landed EXACTLY where
                                            ; the old one did -- space
                                            ; really was reclaimed
    ld   hl, SRC_F1_USE
    ld   de, SRC_F1_USE_LEN
    call INTERPRET_RUN                      ; ZZZ
    ld   de, 222
    call CHECK_TOP
    call W_DROP

; ---- checkpoint 10: FORGET a ROM-resident word -- refused ----
    ld   a, 10
    ld   (CHECKPOINT_NUM), a
    ld   hl, (HERE)
    ld   (CK_TMP1), hl
    ld   hl, (LATEST)
    ld   (CK_TMP2), hl
    ld   hl, SRC_F2
    ld   de, SRC_F2_LEN
    call INTERPRET_RUN         ; FORGET DUP
    ld   hl, (HERE)
    ld   de, (CK_TMP1)
    call CHECK_HL_DE             ; unchanged -- refused
    ld   hl, (LATEST)
    ld   de, (CK_TMP2)
    call CHECK_HL_DE               ; unchanged -- refused
    ld   hl, SRC_F2_PROOF
    ld   de, SRC_F2_PROOF_LEN
    call INTERPRET_RUN               ; 5 DUP  -- DUP must still work
    ld   de, 5
    call CHECK_TOP
    call W_DROP
    ld   de, 5
    call CHECK_TOP
    call W_DROP

    jp   PASS_TEST

; ============================================================================
; CHECK_TOP ( DE = expected -- )  checks the top of the data stack
; WITHOUT popping it (the caller drops separately once done).
; ============================================================================
CHECK_TOP:
    ld   l, (ix+0)
    ld   h, (ix+1)
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; CHECK_HL_DE ( HL DE -- )  fails with the current checkpoint number if
; HL != DE.
; ============================================================================
CHECK_HL_DE:
    or   a
    sbc  hl, de
    jp   nz, FAIL_TEST
    ret

; ============================================================================
; PASS_TEST / FAIL_TEST — printed-number channel, not border-color-coded
; (see this file's own header on why: twelve topics don't fit PORT_ULA's
; 3 usable bits without an aliasing risk this project has already been
; bitten by twice).
; ============================================================================
PASS_TEST:
    ld   a, 4                    ; green: all checkpoints passed
    out  (PORT_ULA), a
    jr   PASS_TEST

FAIL_TEST:
    ld   a, 2                     ; red: something failed
    out  (PORT_ULA), a
    ld   a, (CHECKPOINT_NUM)
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_DOT                     ; prints the failing checkpoint number
.hang:
    jr   .hang

INTERPRET_UNKNOWN_WORD:
    ld   a, 7                    ; white: bug in this file's own test
                                  ; source, not a real checkpoint
    out  (PORT_ULA), a
    ld   hl, BUG_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .hang
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.hang:
    jr   .hang

; ============================================================================
; RUNTIME_ERROR_HOOK -- required by THROW_CATCH_ENABLED (core/interp.asm)
; for an uncaught THROW. Nothing in this test deliberately throws
; uncaught, so reaching this at all means a real bug in the words under
; test -- same white "something's wrong" signal as
; INTERPRET_UNKNOWN_WORD, not a numbered checkpoint (matching
; rom/forth_smoke_p46.asm's own precedent for this exact situation).
; ============================================================================
RUNTIME_ERROR_HOOK:
    ld   a, 7
    out  (PORT_ULA), a
    ld   hl, BUG_MSG
.msgloop:
    ld   a, (hl)
    or   a
    jr   z, .hang
    push hl
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  hl
    inc  hl
    jr   .msgloop
.hang:
    jr   .hang

BUG_MSG: DB "BUG", 0

CHECKPOINT_NUM EQU $8900   ; 1 byte: reused scratch -- safe, core/
                           ; string.asm/core/stringext.asm's own CHR_BUF
                           ; (which would otherwise live here) are not
                           ; INCLUDEd by this smoke ROM, matching
                           ; rom/forth_smoke_p49.asm's own precedent for
                           ; reusing this exact address the same way
CK_TMP1        EQU $8902   ; 2 bytes: scratch, reused across checkpoints
CK_TMP2        EQU $8904   ; 2 bytes: scratch, reused across checkpoints

SRC_C1_DEF: DB ": T1 CREATE 1234 , ; T1 T1FOO "
SRC_C1_DEF_LEN EQU $ - SRC_C1_DEF
SRC_C1_USE: DB "T1FOO @ "
SRC_C1_USE_LEN EQU $ - SRC_C1_USE

SRC_D1_DEF: DB ": CONST CREATE , DOES> @ ; "
SRC_D1_DEF_LEN EQU $ - SRC_D1_DEF
SRC_D1_MK1: DB "5 CONST FIVE "
SRC_D1_MK1_LEN EQU $ - SRC_D1_MK1
SRC_D1_USE1: DB "FIVE "
SRC_D1_USE1_LEN EQU $ - SRC_D1_USE1
SRC_D1_MK2: DB "7 CONST SEVEN "
SRC_D1_MK2_LEN EQU $ - SRC_D1_MK2
SRC_D1_USE2: DB "SEVEN "
SRC_D1_USE2_LEN EQU $ - SRC_D1_USE2

SRC_D2_DEF: DB ": ARR3 CREATE 10 , 20 , 30 , DOES> SWAP CELLS + @ ; ARR3 NUMS "
SRC_D2_DEF_LEN EQU $ - SRC_D2_DEF
SRC_D2_USE0: DB "0 NUMS "
SRC_D2_USE0_LEN EQU $ - SRC_D2_USE0
SRC_D2_USE1: DB "1 NUMS "
SRC_D2_USE1_LEN EQU $ - SRC_D2_USE1
SRC_D2_USE2: DB "2 NUMS "
SRC_D2_USE2_LEN EQU $ - SRC_D2_USE2

SRC_IMM_DEF: DB ": FOO 42 ; IMMEDIATE "
SRC_IMM_DEF_LEN EQU $ - SRC_IMM_DEF
SRC_IMM_USE: DB ": BAR FOO ; "
SRC_IMM_USE_LEN EQU $ - SRC_IMM_USE
SRC_IMM_CALL: DB "BAR "
SRC_IMM_CALL_LEN EQU $ - SRC_IMM_CALL

SRC_ABORT: DB "42 ABORT 99 "
SRC_ABORT_LEN EQU $ - SRC_ABORT
SRC_QUIT: DB "42 QUIT 99 "
SRC_QUIT_LEN EQU $ - SRC_QUIT
SRC_ABORT_BARE: DB "ABORT "
SRC_ABORT_BARE_LEN EQU $ - SRC_ABORT_BARE
SRC_QUIT_BARE: DB "QUIT "
SRC_QUIT_BARE_LEN EQU $ - SRC_QUIT_BARE

SRC_PORT: DB "8 245 OUT 12 246 OUT 8 245 OUT 246 IN "
SRC_PORT_LEN EQU $ - SRC_PORT

SRC_F1_DEF: DB ": ZZZ 111 ; "
SRC_F1_DEF_LEN EQU $ - SRC_F1_DEF
SRC_F1_FORGET: DB "FORGET ZZZ "
SRC_F1_FORGET_LEN EQU $ - SRC_F1_FORGET
SRC_F1_REDEF: DB ": ZZZ 222 ; "
SRC_F1_REDEF_LEN EQU $ - SRC_F1_REDEF
SRC_F1_USE: DB "ZZZ "
SRC_F1_USE_LEN EQU $ - SRC_F1_USE

SRC_F2: DB "FORGET DUP "
SRC_F2_LEN EQU $ - SRC_F2
SRC_F2_PROOF: DB "5 DUP "
SRC_F2_PROOF_LEN EQU $ - SRC_F2_PROOF

; ---- dictionary: included here, after the vector table and the
; self-test code above, not before ORG $0000 ----
    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "core/dict.asm"
    DEFINE THROW_CATCH_ENABLED
    INCLUDE "core/interp.asm"
DICT_CHAIN_POINT DEFL H_SEMICOLON
    INCLUDE "core/float.asm"
DICT_CHAIN_POINT DEFL H_FMINUS
    INCLUDE "core/print.asm"
DICT_CHAIN_POINT DEFL H_DOT
    INCLUDE "core/doloop.asm"
DICT_CHAIN_POINT DEFL H_I
    INCLUDE "core/throwcatch.asm"
DICT_CHAIN_POINT DEFL H_CATCH
    INCLUDE "core/array.asm"
DICT_CHAIN_POINT DEFL H_CELLS
    INCLUDE "core/dictspace.asm"
DICT_CHAIN_POINT DEFL H_ALLOT
    INCLUDE "core/create.asm"
DICT_CHAIN_POINT DEFL H_CREATE
    INCLUDE "core/does.asm"
DICT_CHAIN_POINT DEFL H_DOES
    INCLUDE "core/immediate.asm"
DICT_CHAIN_POINT DEFL H_IMMEDIATE
    INCLUDE "core/abortquit.asm"
DICT_CHAIN_POINT DEFL H_QUIT
    INCLUDE "core/portio.asm"
DICT_CHAIN_POINT DEFL H_OUT
    INCLUDE "core/forget.asm"

    DS   $4000 - $, $FF

    SAVEBIN "forth_smoke_p50_rom0.bin", $0000, $4000
