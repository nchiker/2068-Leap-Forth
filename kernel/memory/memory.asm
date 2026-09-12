; ============================================================================
; kernel/memory/memory.asm — generic memory-fill primitive
;
; Restores MEM_FILL_ZERO/MEM_FILL, the two generic primitives
; docs/PROJECT_PLAN.md's "What was deliberately left behind" section
; explicitly flagged as "still worth keeping" when the rest of this
; module (MEM_INIT/MEM_LINE_*/MEM_LABEL_*, the BASIC-only line-storage
; and label-table machinery this project has no use for) was deleted —
; the whole file was removed instead of just the BASIC-specific part,
; dropping these two along with it. include/kernel_api.inc never
; stopped declaring them EXTERN, which is what made the gap easy to
; miss: nothing failed to assemble, since nothing called them.
;
; WHY THIS MATTERS AT COLD START: real hardware and accuracy-oriented
; emulators do NOT guarantee RAM is zeroed at power-on — only some
; emulators happen to. 2068-Leap hit this exact class of bug in its own
; MEM_COLD_INIT (see that project's docs/programmers_reference.md):
; a test passed under an emulator that pre-zeros RAM even when the
; routine under test was completely broken, and real/accurate hardware
; would show whatever garbage was already sitting in RAM until
; something explicitly overwrites it. rom/forth_boot.asm's own
; COLD_START only ever set a handful of individual sysvars (HERE,
; WORKSPACE_END, STATE, ...) — it never zeroed the dictionary/stack/
; workspace RAM range those sysvars point into, so anything read before
; being explicitly written (e.g. scrolling into a dictionary entry
; that was never SAVE-TEXT/typed yet) could show leftover garbage on a
; real machine or an accurate emulator, even though this project's own
; day-to-day Fuse testing never surfaced it.
; ============================================================================

    IFNDEF KERNEL_MEMORY_ASM
    DEFINE KERNEL_MEMORY_ASM

; ============================================================================
; MEM_FILL_ZERO
; Zeroes BC bytes starting at HL.
; In:  HL = start address, BC = byte count
; Out: A = 0
; Destroys: AF, BC, DE, HL
; ============================================================================
MEM_FILL_ZERO:
    xor  a
; ============================================================================
; MEM_FILL
; As MEM_FILL_ZERO, but fills with A instead of always zero (falls
; through from MEM_FILL_ZERO with A already 0). Both entry points
; exposed since callers sometimes want a specific fill byte rather than
; always clearing to zero.
; In:  HL = start address, BC = byte count, A = fill byte
; Out: none
; Destroys: AF, BC, DE, HL
; ============================================================================
MEM_FILL:
    ld   (hl), a
    ld   d, h
    ld   e, l
    inc  de
    dec  bc
    ld   a, b
    or   c
    ret  z                  ; BC was 1: single byte already written above
    ldir                     ; copy the just-written byte forward across
                            ; the rest of the range
    ret

    ENDIF
