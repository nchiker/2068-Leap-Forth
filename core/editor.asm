; ============================================================================
; core/editor.asm — Phase 6: line editing
;
; Builds on core/interp.asm (INTERPRET_RUN) and needs kernel/io
; (IO_READ_KEY) and kernel/graphics (GFX_PUTCHAR, GFX_INVERT_ATTR_STATIC)
; INCLUDEd alongside it. Adds NO new dictionary words — a line editor is
; the shell that reads a line and hands it to INTERPRET_RUN, the same
; relationship INTERPRET_RUN itself has to WORD/FIND/NUMBER (Phase 3):
; it sits outside the language, not inside it. See
; docs/PROJECT_PLAN.md's Phase 6 section for why EMIT/KEY as real
; dictionary words are deliberately NOT part of this file even though
; the machinery (GFX_PUTCHAR, IO_READ_KEY) is right here.
;
; SCOPE: single-line only (docs/PROJECT_PLAN.md's own Phase 6
; description: "single-line (then multi-line, if needed)"), a fixed
; screen row, no visual cursor indicator moved by LEFT/RIGHT beyond
; where the next insert/delete lands (see EDITOR_REDRAW's own header),
; and only four keys handled: printable ASCII, ENTER, DELETE
; (backspace), and LEFT/RIGHT — no UP/DOWN, no CAPS SHIFT combinations.
; docs/loadable_basic_extensions.md's editor comparison in
; docs/PROJECT_PLAN.md still applies: this deliberately does NOT read
; or adopt anything from 2068-Leap's rom/exrom_editor.asm beyond having
; looked at its cursor arithmetic once for reference — no EXROM/Home
; split, no redraw hooks, no label table, none of which this project's
; own dictionary-based word model needs.
;
; TWO ENTRY POINTS:
;   EDITOR_PROCESS_KEY  the actual editing logic (insert/delete/cursor
;                       move/detect ENTER) — this is what's proven by
;                       rom/forth_smoke_p6.asm, fed a canned sequence of
;                       key codes instead of live keyboard input, so the
;                       test is deterministic and needs no Fuse
;                       keystroke injection.
;   EDITOR_LOOP_LIVE    the real interactive shell: reads real keys via
;                       IO_READ_KEY, calls EDITOR_PROCESS_KEY, and once
;                       a line is ready, runs it through INTERPRET_RUN
;                       and starts the next line. NOT exercised by the
;                       automated smoke test (there's no way to drive
;                       real keyboard timing deterministically here) —
;                       its correctness follows from EDITOR_PROCESS_KEY
;                       (proven) plus IO_READ_KEY (already proven by
;                       2068-Leap) being individually correct and
;                       composed in the obvious way. Manual confirmation
;                       in real Fuse (or real hardware) with an actual
;                       keyboard remains the honest gap here — noted,
;                       not hidden.
; ============================================================================

    IFNDEF CORE_EDITOR_ASM
    DEFINE CORE_EDITOR_ASM

EDIT_ROW       EQU 23      ; bottom row of the 24-row screen
EDIT_COL_START EQU 0
EDIT_MAX_LEN   EQU 31      ; leaves room for a cursor block at column 31
                           ; without ever addressing column 32 (off-screen)

; ---- Phase 6 RAM state — verified against the same probe method Phase
; 5 established (docs/PROJECT_PLAN.md's Phase 5 section): this range
; ($8550-$8573) sits inside the same confirmed-empty $8426-$8FFF gap
; core/interp.asm's own relocated scratch already uses, well clear of
; core/interp.asm's own cells (ending at $8541) and CHECKPOINT_NUM
; ($8542, smoke-ROM-only). ----
EDIT_BUF     EQU $8550   ; 32 bytes: the line being edited, not
                         ; null-terminated (EDIT_LEN is authoritative)
EDIT_LEN     EQU $8570   ; 1 byte: current number of characters in EDIT_BUF
EDIT_CURSOR  EQU $8571   ; 1 byte: cursor position within EDIT_BUF, 0..EDIT_LEN
SHIFT_COUNT  EQU $8572   ; 1 byte: INSERT_CHAR/DELETE_CHAR_BEFORE_CURSOR's
                         ; own scratch (bytes remaining to shift)
INS_CHAR_TMP EQU $8573   ; 1 byte: INSERT_CHAR's own scratch (the char
                         ; being inserted, held across the shift loop)

; ============================================================================
; INSERT_CHAR ( A = character )
; Inserts A at EDIT_CURSOR, shifting everything from EDIT_CURSOR to the
; old end of the buffer up by one position first. Caller must already
; have checked EDIT_LEN < EDIT_MAX_LEN.
; ============================================================================
INSERT_CHAR:
    ld   (INS_CHAR_TMP), a
    ld   a, (EDIT_LEN)
    ld   c, a                 ; c = len
    ld   a, (EDIT_CURSOR)
    ld   b, a                 ; b = cursor
    ld   a, c
    sub  b
    ld   (SHIFT_COUNT), a     ; bytes to shift = len - cursor
    or   a
    jr   z, .no_shift
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, c
    add  hl, de                ; hl = EDIT_BUF + len (new last slot, dest)
    push hl
    dec  hl                     ; hl = EDIT_BUF + len - 1 (old last char, source)
    ex   de, hl                  ; de = source
    pop  hl                       ; hl = dest
.shiftloop:
    ld   a, (de)
    ld   (hl), a
    dec  hl
    dec  de
    ld   a, (SHIFT_COUNT)
    dec  a
    ld   (SHIFT_COUNT), a
    jr   nz, .shiftloop
.no_shift:
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, b                   ; e = cursor
    add  hl, de
    ld   a, (INS_CHAR_TMP)
    ld   (hl), a
    ld   a, (EDIT_LEN)
    inc  a
    ld   (EDIT_LEN), a
    ld   a, (EDIT_CURSOR)
    inc  a
    ld   (EDIT_CURSOR), a
    ret

; ============================================================================
; DELETE_CHAR_BEFORE_CURSOR ( -- )
; Backspace semantics: removes the character immediately before
; EDIT_CURSOR, shifting everything after it down by one position.
; Caller must already have checked EDIT_CURSOR > 0.
; ============================================================================
DELETE_CHAR_BEFORE_CURSOR:
    ld   a, (EDIT_LEN)
    ld   c, a                 ; c = len
    ld   a, (EDIT_CURSOR)
    ld   b, a                 ; b = cursor
    ld   a, c
    sub  b
    ld   (SHIFT_COUNT), a     ; bytes to shift = len - cursor
    or   a
    jr   z, .no_shift
    ld   hl, EDIT_BUF
    ld   d, 0
    ld   e, b
    dec  e
    add  hl, de                ; hl = EDIT_BUF + cursor - 1 (dest)
    push hl
    inc  hl                     ; hl = EDIT_BUF + cursor (source)
    ex   de, hl                  ; de = source
    pop  hl                       ; hl = dest
.shiftloop:
    ld   a, (de)
    ld   (hl), a
    inc  hl
    inc  de
    ld   a, (SHIFT_COUNT)
    dec  a
    ld   (SHIFT_COUNT), a
    jr   nz, .shiftloop
.no_shift:
    ld   a, (EDIT_LEN)
    dec  a
    ld   (EDIT_LEN), a
    ld   a, (EDIT_CURSOR)
    dec  a
    ld   (EDIT_CURSOR), a
    ret

; ============================================================================
; EDITOR_REDRAW ( -- )
; Redraws the whole edit row from scratch: EDIT_BUF's current contents,
; then blanks (spaces) the rest of the row out to EDIT_MAX_LEN, then
; marks the cursor position with a static inverted cell. Simple and
; correct rather than fast — this project's own kernel/editor
; (2068-Leap) invested real effort in incremental/fast-scroll redraws
; for a much larger, multi-line editor; a single 32-column row redrawn
; in full on every keystroke has no comparable performance problem.
; KNOWN LIMITATION: the cursor indicator is redrawn fresh every call, so
; it's always visually correct, but there's no blink/flash — a static
; inverted cell only. Good enough to see where you are; not as visible
; as a blinking cursor would be.
; ============================================================================
EDITOR_REDRAW:
    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   e, a                  ; e = remaining chars to print
    ld   c, EDIT_COL_START
.printloop:
    ld   a, e
    or   a
    jr   z, .blank
    ld   a, (hl)
    push hl
    push bc
    push de
    ld   b, EDIT_ROW
    call GFX_PUTCHAR
    pop  de
    pop  bc
    pop  hl
    inc  hl
    inc  c
    dec  e
    jr   .printloop
.blank:
    ld   a, c
    cp   EDIT_MAX_LEN + 1
    jr   nc, .cursor
    push bc
    ld   a, " "
    ld   b, EDIT_ROW
    call GFX_PUTCHAR
    pop  bc
    inc  c
    jr   .blank
.cursor:
    ld   a, (EDIT_CURSOR)
    add  a, EDIT_COL_START
    ld   c, a
    ld   b, EDIT_ROW
    call GFX_INVERT_ATTR_STATIC
    ret

; ============================================================================
; EDITOR_PROCESS_KEY ( A = key code -- )
; Out: carry set if A was ENTER (a line is ready in EDIT_BUF/EDIT_LEN;
; caller decides what to do with it — see EDITOR_LOOP_LIVE below).
; Carry clear otherwise (key handled, or ignored if unmapped/out of
; range — no error is ever raised here, matching every earlier phase's
; scope: this is a shell, not something a Forth program can catch an
; exception from).
; ============================================================================
EDITOR_PROCESS_KEY:
    cp   KEY_ENTER
    jr   nz, .not_enter
    scf
    ret
.not_enter:
    cp   KEY_DELETE
    jr   nz, .not_delete
    ld   a, (EDIT_CURSOR)
    or   a
    jr   z, .done
    call DELETE_CHAR_BEFORE_CURSOR
    jr   .redraw_and_done
.not_delete:
    cp   KEY_CURSOR_LEFT
    jr   nz, .not_left
    ld   a, (EDIT_CURSOR)
    or   a
    jr   z, .done
    dec  a
    ld   (EDIT_CURSOR), a
    jr   .redraw_and_done
.not_left:
    cp   KEY_CURSOR_RIGHT
    jr   nz, .not_right
    ld   hl, EDIT_LEN
    ld   a, (EDIT_CURSOR)
    cp   (hl)
    jr   nc, .done             ; already at or past the end
    inc  a
    ld   (EDIT_CURSOR), a
    jr   .redraw_and_done
.not_right:
    cp   " "
    jr   c, .done              ; below space: unmapped/control, ignore
    cp   $7F
    jr   nc, .done              ; DEL and above: ignore
    push af                     ; save the key code -- checking EDIT_LEN
                                ; next needs A for itself
    ld   a, (EDIT_LEN)
    cp   EDIT_MAX_LEN
    jr   c, .room                ; len < max: proceed
    pop  af                       ; buffer already full: discard the
                                  ; saved key code and ignore it
    jr   .done
.room:
    pop  af                       ; a = the original key code again
    call INSERT_CHAR
    jr   .redraw_and_done

.redraw_and_done:
    call EDITOR_REDRAW
.done:
    or   a
    ret

; ============================================================================
; EDITOR_LOOP_LIVE ( -- )
; The real interactive shell — reads a line from a real keyboard, runs
; it, and repeats forever. NOT exercised by the automated smoke test;
; see this file's own header for why, and for what IS proven instead.
;
; REAL PRECONDITION, discovered writing this routine, not assumed away:
; kernel/io's IO_READ_KEY does NOT scan the keyboard matrix itself
; (a real change from earlier in 2068-Leap's own history) — it only
; consumes a key already latched by kernel/interrupt's KBD_ISR_TICK,
; which must run on every real IM 1 interrupt. Calling EDITOR_LOOP_LIVE
; with interrupts disabled, or without RST $0038 vectoring to
; KBD_ISR_TICK, hangs forever at the very first keypress wait — not a
; bug in this routine, but a setup step it depends on and does not
; perform itself (matching kernel/bank's own precedent of documenting a
; precondition rather than each routine re-establishing global machine
; state). rom/forth_smoke_p6.asm's own COLD_START deliberately leaves
; interrupts disabled, same as every earlier smoke ROM in this project
; — its automated test never calls this routine, only
; EDITOR_PROCESS_KEY directly, so this precondition doesn't apply to
; what's actually proven there. Whatever future ROM first boots to a
; live interactive prompt (see docs/PROJECT_PLAN.md's own startup-sound
; product requirement, which implies exactly such a ROM) must set up
; RST $0038 -> KBD_ISR_TICK, IM 1, and EI before calling this.
; ============================================================================
EDITOR_LOOP_LIVE:
    xor  a
    ld   (EDIT_LEN), a
    ld   (EDIT_CURSOR), a
    call EDITOR_REDRAW
.keyloop:
    call IO_READ_KEY
    call EDITOR_PROCESS_KEY
    jr   nc, .keyloop
    ld   hl, EDIT_BUF
    ld   a, (EDIT_LEN)
    ld   d, 0
    ld   e, a
    call INTERPRET_RUN
    jr   EDITOR_LOOP_LIVE

    ENDIF
