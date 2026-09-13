; ============================================================================
; core/recall.asm — Phase 64: LIST-DEFS / RECALL, live-typo correction
;
; Builds on core/loadtext.asm (LOADTEXT_BUF, WORKSPACE_END — the latter
; set there, by LOAD-TEXT, on the same file's own reasoning) and
; core/editor.asm (EDIT_BUF/EDIT_LEN/EDIT_CURSOR, EDITOR_LOOP_LIVE).
;
; THE PROBLEM THIS SOLVES: EDITOR_LOOP_LIVE hands EDIT_BUF straight to
; INTERPRET_RUN and never keeps a copy (that file's own .keyloop, a few
; lines above the INTERPRET_RUN call) — once you press Enter on a typo'd
; definition, the broken source is simply gone. LOAD-TEXT's own
; LOADTEXT_BUF, by contrast, DOES stay resident after a load. This file
; makes both cases work the same way: every line committed at the live
; prompt gets appended into that same persistent buffer (WORKSPACE_APPEND,
; called from core/editor.asm's EDITOR_LOOP_LIVE — see that file's own
; updated header), so anything typed OR loaded can later be recalled.
;
; THE DESIGN DECISION THAT KEEPS THIS CHEAP: no in-place edit of the
; workspace. RECALL copies a definition's source span into EDIT_BUF for
; editing; committing the edited line runs it live (ordinary Forth
; shadowing — the corrected definition simply outranks the old one on
; lookup, same as retyping it) AND appends the corrected text to the END
; of the workspace, same as any freshly-typed line. The old, superseded
; copy of that definition is left sitting in the middle of the workspace,
; not spliced out — a real, honest limit, not silently unsafe: recalling
; that name again later shows both copies, oldest first, same "newest
; wins" convention the dictionary itself already uses. Avoids a
; variable-length in-place splice (block-shift with capacity checks)
; entirely, which is both the single most expensive and most bug-prone
; piece a full in-place editor would need. Deliberately does NOT FORGET
; and replay the whole program on every edit either — see this project's
; own design discussion for why that trades a typo fix for silently
; resetting every VARIABLE/CONSTANT and re-running any top-level side
; effects (RANDOMIZE, game-start loops, etc.) the program has.
;
; RECALL UNIT: one colon definition (":" through its matching ";"), not a
; line — INTERPRET_RUN's own single delimiter is a plain space
; (core/interp.asm's own header), so saved program text has no line/CR
; structure to recall by. ":"/";" are the only real structural boundary
; Forth source has.
;
; HONEST LIMITS, stated plainly rather than guarded against:
;   - a definition longer than EDIT_MAX_LEN (128 bytes) can't be
;     RECALLed — .too_long reports this rather than silently truncating.
;   - the workspace (LOADTEXT_MAX_LEN, 8192 bytes, shared with LOAD-TEXT's
;     own receive buffer) slowly fills with stale superseded copies over
;     a long editing session; WORKSPACE_APPEND simply stops appending
;     once full rather than overflowing into dictionary RAM above it —
;     same class of documented-not-guarded scope as LOAD-TEXT's own
;     buffer-overlap caveat.
;   - DEF_TABLE below caps at DEF_TABLE_MAX (16) definitions per scan;
;     LIST-DEFS/RECALL only see the first 16 found, oldest first.
; ============================================================================

    IFNDEF CORE_RECALL_ASM
    DEFINE CORE_RECALL_ASM

; ---- own scratch: confirmed-idle gap right after core/editor.asm's own
; FWRAP_OVERFLOW ($88F5), same "grep every core/*.asm EQU in this range"
; method as everywhere else in this project. RECALL_PENDING is read by
; core/editor.asm's EDITOR_LOOP_LIVE, which INCLUDEs after this file. ----
RECALL_PENDING EQU $88F6   ; 1 byte: set by W_RECALL, cleared by
                           ; EDITOR_LOOP_LIVE — tells it to skip its own
                           ; usual "zero EDIT_BUF for a fresh line"
                           ; reset just once, so the recalled text
                           ; survives past RECALL's own line finishing.

; ---- DEF_COUNT/DEF_TABLE: same confirmed-idle gap as WORKSPACE_END
; (core/loadtext.asm), continuing right after it ($8A74-$8A75). ----
DEF_TABLE_MAX  EQU 16
DEF_COUNT      EQU $8A76   ; 1 byte: how many spans SCAN_DEFS found
                           ; (0-DEF_TABLE_MAX)
DEF_TABLE      EQU $8A77   ; DEF_TABLE_MAX*4 bytes: per entry, 2-byte
                           ; start offset from LOADTEXT_BUF + 2-byte
                           ; length. Ends $8AB7, still well before
                           ; core/float.asm's own FSTACK_LIMIT ($8C00).

RECALL_SCAN_PTR   EQU $8AB7   ; 2 bytes: SCAN_DEFS's own scratch
RECALL_SPAN_START EQU $8AB9   ; 2 bytes: SCAN_DEFS's own scratch

; ============================================================================
; WORKSPACE_APPEND ( HL = addr, B = len -- )
; Appends B bytes at HL to the workspace at WORKSPACE_END, with a single
; leading space separator if the workspace is already non-empty (keeps
; INTERPRET_RUN's own space-delimited tokenizing from gluing the last
; word of the previous entry to the first word of this one). Stops
; silently, appending nothing, if it wouldn't fit — see this file's own
; header on why that's a documented limit, not a guarded one.
; ============================================================================
WORKSPACE_APPEND:
    push hl
    push bc
    ld   hl, (WORKSPACE_END)
    ld   de, LOADTEXT_BUF
    or   a
    sbc  hl, de                 ; hl = current workspace length
    ld   a, b
    inc  a                      ; +1 for the possible separator space
    add  a, l
    ld   e, a
    ld   a, 0
    adc  a, h
    ld   d, a                   ; de = length AFTER this append
    ld   a, d
    cp   LOADTEXT_MAX_LEN / 256 + 1
    pop  bc
    pop  hl
    ret  nc                     ; would overflow the workspace: no-op

    push hl
    ld   hl, (WORKSPACE_END)
    ld   de, LOADTEXT_BUF
    or   a
    sbc  hl, de
    ld   a, h
    or   l
    pop  hl
    jr   z, .no_sep              ; empty workspace: no separator needed
    push hl
    ld   hl, (WORKSPACE_END)
    ld   (hl), " "
    inc  hl
    ld   (WORKSPACE_END), hl
    pop  hl
.no_sep:
    ld   de, (WORKSPACE_END)
.copyloop:
    ld   a, b
    or   a
    jr   z, .done
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    dec  b
    jr   .copyloop
.done:
    ld   (WORKSPACE_END), de
    ret

; ============================================================================
; SCAN_DEFS ( -- )
; Walks LOADTEXT_BUF..WORKSPACE_END for top-level ":"..";" spans (each
; delimiter-bounded, the same way core/interp.asm's own WORD treats a
; space as the only delimiter) and populates DEF_TABLE/DEF_COUNT, oldest
; first. Forth doesn't nest colon definitions, so no depth tracking is
; needed: a ":" starts a span, the next ";" ends it.
; ============================================================================
; AT_END (internal) -- Z set if RECALL_SCAN_PTR has reached WORKSPACE_END.
; Factored out of SCAN_DEFS's own three identical inline checks (one per
; scan state below) -- pure dedup, no behavior change. Destroys HL/DE,
; which every call site below already reloads fresh afterward anyway.
AT_END:
    ld   hl, (RECALL_SCAN_PTR)
    ld   de, (WORKSPACE_END)
    or   a
    sbc  hl, de
    ret

SCAN_DEFS:
    xor  a
    ld   (DEF_COUNT), a
    ld   hl, LOADTEXT_BUF
    ld   (RECALL_SCAN_PTR), hl
.outer:
    call AT_END
    jp   z, .stop                ; reached the end: done -- jp not jr,
                                  ; real displacement was +126, only 1
                                  ; byte under the +-127 limit
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   " "
    jr   nz, .check_colon
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    jr   .outer
.check_colon:
    cp   ":"
    jr   nz, .skip_word
    ld   (RECALL_SPAN_START), hl
    ; found ":" -- now scan forward for the matching ";" word
.find_semi:
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    jr   z, .stop                ; ran off the end with no ";": stop scanning
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   " "
    jr   z, .find_semi
    cp   ";"
    jr   nz, .find_semi
    ; ";" found -- record the span (inclusive of the ";") if room remains
    ld   a, (DEF_COUNT)
    cp   DEF_TABLE_MAX
    jr   nc, .stop                ; table full: stop scanning (Phase 64's
                                   ; own documented DEF_TABLE_MAX limit)
    push af
    ld   hl, DEF_TABLE
    ld   d, 0
    ld   e, a
    add  hl, de
    add  hl, de
    add  hl, de
    add  hl, de                   ; hl = DEF_TABLE + a*4
    ex   de, hl
    ld   hl, (RECALL_SPAN_START)
    ld   bc, LOADTEXT_BUF
    or   a
    sbc  hl, bc                   ; hl = span start offset
    ld   a, l                     ; Z80 has no `ld (de),hl` -- store via A
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    inc  de
    ld   hl, (RECALL_SCAN_PTR)
    ld   bc, (RECALL_SPAN_START)
    or   a
    sbc  hl, bc
    inc  hl                       ; hl = span length, inclusive of ";"
    ld   a, l
    ld   (de), a
    inc  de
    ld   a, h
    ld   (de), a
    pop  af
    inc  a
    ld   (DEF_COUNT), a
    ld   hl, (RECALL_SCAN_PTR)
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    jr   .outer
.skip_word:
    ; not ":" -- skip to the next space (or end) and keep scanning
    inc  hl
    ld   (RECALL_SCAN_PTR), hl
    call AT_END
    jr   z, .stop
    ld   hl, (RECALL_SCAN_PTR)
    ld   a, (hl)
    cp   " "
    jr   nz, .skip_word
    jp   .outer
.stop:
    ret

; GET_DEF_SPAN (internal) ( C = index -- DE = span start offset, HL = span
; length ). Factored out of W_LISTDEFS and W_RECALL, which both did this
; identical DEF_TABLE index arithmetic and 4-byte read inline -- pure
; dedup, no behavior change. Caller must ensure index < DEF_COUNT.
GET_DEF_SPAN:
    ld   hl, DEF_TABLE
    ld   b, 0
    add  hl, bc
    add  hl, bc
    add  hl, bc
    add  hl, bc
    ld   e, (hl)
    inc  hl
    ld   d, (hl)                  ; de = span start offset
    inc  hl
    ld   a, (hl)
    inc  hl
    ld   h, (hl)
    ld   l, a                     ; hl = span length
    ret

; ============================================================================
; LIST-DEFS ( -- )
; Scans the workspace fresh, then prints each entry as "N: " followed by
; up to 20 preview characters of its source and a newline. 20 is a plain
; display choice (fits one 32-column row with the "N: " prefix and room
; to spare), not a stored/recall limit -- RECALL below copies the WHOLE
; span, not just the preview.
; ============================================================================
LISTDEFS_PREVIEW_LEN EQU 20

H_LISTDEFS:
    DW   DICT_CHAIN_POINT
    DB   9, "L","I","S","T","-","D","E","F","S"
W_LISTDEFS:
    call SCAN_DEFS
    xor  a
    ld   (RECALL_LIST_IDX), a
.loop:
    ld   a, (RECALL_LIST_IDX)
    ld   c, a
    ld   b, 0
    ld   a, (DEF_COUNT)
    cp   c
    ret  z                        ; RECALL_LIST_IDX == DEF_COUNT: done
    ret  c                        ; RECALL_LIST_IDX > DEF_COUNT: done
                                   ; (can't happen, kept as a safety net)

    push bc
    ld   l, c
    ld   h, b
    call PRINT_UDEC16
    ld   hl, ":"
    call DPUSH_HL
    call W_EMIT
    ld   hl, " "
    call DPUSH_HL
    call W_EMIT
    pop  bc

    call GET_DEF_SPAN              ; de = span start offset, hl = length

    ld   a, LISTDEFS_PREVIEW_LEN
    cp   l
    jr   c, .cap
    ld   a, h
    or   a
    jr   z, .nocap
.cap:
    ld   l, LISTDEFS_PREVIEW_LEN
    ld   h, 0
.nocap:
    push hl
    ld   hl, LOADTEXT_BUF
    add  hl, de                   ; hl -> span start in the workspace
    pop  bc                       ; bc = capped preview length
.printloop:
    ld   a, b
    or   c
    jr   z, .printdone
    ld   a, (hl)
    push hl
    push bc
    ld   l, a
    ld   h, 0
    call DPUSH_HL
    call W_EMIT
    pop  bc
    pop  hl
    inc  hl
    dec  bc
    jr   .printloop
.printdone:
    ld   hl, 13
    call DPUSH_HL
    call W_EMIT

    ld   a, (RECALL_LIST_IDX)
    inc  a
    ld   (RECALL_LIST_IDX), a
    jr   .loop

RECALL_LIST_IDX EQU RECALL_SPAN_START + 2   ; 1 byte: reuses SCAN_DEFS's
                                             ; own idle scratch -- LIST-DEFS
                                             ; never runs concurrently with
                                             ; SCAN_DEFS itself (it CALLS
                                             ; it first, then this loop
                                             ; runs after SCAN_DEFS has
                                             ; already returned).

; ============================================================================
; RECALL ( n -- )
; Copies DEF_TABLE entry n's full source span into EDIT_BUF and sets
; RECALL_PENDING, so core/editor.asm's EDITOR_LOOP_LIVE leaves it there
; (cursor at the end) instead of clearing it for a fresh empty line.
; Silently does nothing if n is out of range, or if the span is longer
; than EDIT_MAX_LEN can hold -- see this file's own header.
; ============================================================================
H_RECALL:
    DW   H_LISTDEFS
    DB   6, "R","E","C","A","L","L"
W_RECALL:
    call SCAN_DEFS
    call DPOP_HL
    ld   a, l
    ld   c, a
    ld   a, (DEF_COUNT)
    cp   c
    ret  z                         ; n == count or higher: out of range
    jr   c, .oor
    jr   .inrange
.oor:
    ret
.inrange:
    call GET_DEF_SPAN              ; de = span start offset, hl = length

    ld   a, h
    or   a
    ret  nz                        ; span > 255 bytes: definitely too long
    ld   a, l
    cp   EDIT_MAX_LEN + 1
    ret  nc                        ; span > EDIT_MAX_LEN: too long, no-op

    ld   (RECALL_LEN_TMP), a       ; a = l = span length here, still
    ld   c, a
    ld   hl, LOADTEXT_BUF
    add  hl, de                    ; hl -> span start in the workspace
    ld   de, EDIT_BUF
.copyloop:
    ld   a, c
    or   a
    jr   z, .copydone
    ld   a, (hl)
    ld   (de), a
    inc  hl
    inc  de
    dec  c
    jr   .copyloop
.copydone:
    ld   a, (RECALL_LEN_TMP)
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a          ; cursor at the end of the recalled text
    ld   a, 1
    ld   (RECALL_PENDING), a
    ret

RECALL_LEN_TMP  EQU RECALL_SPAN_START + 3   ; 1 byte: W_RECALL's own
                                             ; scratch (original span
                                             ; length, saved before the
                                             ; copy loop destroys C).
                                             ; RECALL_SPAN_START+2 is
                                             ; RECALL_LIST_IDX, see
                                             ; W_LISTDEFS above.

DICT_LATEST_INIT_RECALL EQU H_RECALL   ; head of the dictionary once this
                                       ; file is the last one INCLUDEd

    ENDIF
