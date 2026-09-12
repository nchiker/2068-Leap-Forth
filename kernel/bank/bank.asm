; ============================================================================
; kernel/bank/bank.asm — EXROM paging trampoline
;
; INHERITED FROM 2068-LEAP, THEN RETARGETED FOR 2068-FORTH'S OWN CHUNK
; CHOICE (this session): the original file paged chunk 6 ($C000-$DFFF),
; hardware-confirmed for 2068-Leap's own memory model on real hardware/
; Fuse via `rom/test_exrom_isolation.asm` — a file that lived in that
; sibling project, never copied here, and was never actually wired into
; any 2068-Forth ROM (confirmed by grep: zero callers of BANK_PAGE_
; EXROM_IN/OUT/BANK_CALL_EXROM anywhere in this repo before this
; session). Its own chunk-6 choice doesn't transfer cleanly: 2068-
; Forth's dictionary ceiling (`DICT_RAM_CEILING`, `core/free.asm`) was
; later raised to $F000, deep into chunk 6, and `LOADTEXT_BUF`
; (`core/loadtext.asm`) — persistent SAVE-TEXT/LOAD-TEXT workspace
; `RECALL`/`LIST-DEFS` read from — also lives there.
;
; Retargeted to CHUNK 5 ($A000-$BFFF) instead: a full chunk-by-chunk
; audit (this session) found it's the one chunk with NO competing use
; at all in 2068-Forth's own memory map — not the machine stack, not
; either CPU stack (those are chunk 4), not video RAM, not a fixed
; persistent buffer, nothing `KBD_ISR_TICK` touches. The only thing
; that can ever live there is dictionary content, and paging is real
; bank-switched hardware, not a RAM-address collision the way FILL's
; old scratch was — the underlying RAM is never touched by paging it
; out, only made briefly invisible, so this holds regardless of how
; far the dictionary has grown into chunk 5 at the moment of a call.
; See docs/PROJECT_PLAN.md's chunk-by-chunk audit for the full
; per-chunk reasoning (why chunks 0/1/2/3/4/7 are each disqualified).
;
; The retargeting itself is a one-bit change (chunk N = bit N on
; PORT_BANK_HOME, confirmed in include/hardware.inc's own citation of
; the real port $F4 description) — everything else below (the nesting-
; safe depth counter, the DI/EI discipline, the shadow-preserving
; PORT_FF_SHADOW read-modify-write) is chunk-agnostic and unchanged
; from the original, still-sound design. What is NOT yet true: this
; specific chunk-5 retargeting has NOT been hardware/emulator-confirmed
; the way chunk 6 once was for 2068-Leap — see rom/test_exrom_
; isolation.asm (this project's own fresh confirmation, written this
; session) for that proof, not this file's own doc comments alone.
;
; WHY THIS EXISTS: Home bank is hard-capped at 16K. EXROM gives 8K
; more, paged into chunk 5 ($A000-$BFFF) only.
;
; INTERRUPT SAFETY — the one thing this file gets right or wrong for
; everything built on top of it: interrupts are disabled ONLY across
; the two port writes that actually change the paging state (a few
; instructions), never across the caller's subsequent use of the
; paged window. Holding DI for the whole window would reintroduce
; exactly the keyboard-lag problem this project already fixed once
; (see kernel/interrupt's own history) for anything nontrivial running
; from EXROM. It's safe to re-enable immediately because this
; project's real interrupt handler, KBD_ISR_TICK, never touches chunk
; 5 — its own sysvars all live in chunk 4, which stays Home-mapped
; the entire time chunk 5 is paged to EXROM. If kernel/interrupt ever
; grows a handler that DOES need chunk-5 data, this reasoning needs
; re-deriving, not assumed to still hold.
;
; EXROM's own entry convention: execution starts at the very first
; byte of the 8K image (i.e. $A000 once paged in), same as a ROM's own
; reset vector. Multiple services are reached via a fixed service
; table at that entry point (see rom/graphics_exrom.asm), not by
; changing these paging primitives.
; ============================================================================

    IFNDEF KERNEL_BANK_ASM
    DEFINE KERNEL_BANK_ASM

; ============================================================================
; BANK_PAGE_EXROM_IN
; Pages chunk 5 ($A000-$BFFF) to EXROM. Every other chunk stays Home.
; See this file's own header for the DI/EI reasoning — interrupts are
; back on before this returns.
; In:  none
; Out: none
; Destroys: AF
; ============================================================================
; Nesting-safe via BANK_EXROM_DEPTH (include/sysvars.inc — see that
; sysvar's own comment for the full bug story this fixes, 2026-08-22):
; the real port writes only happen on the 0->1 depth transition — a
; call made while chunk 5 is ALREADY paged to EXROM (i.e. from code
; that's itself running as a nested call from within EXROM) just bumps
; the counter and leaves the paging alone. The single, non-nested case
; every caller before this fix used — page in, do one thing, page
; out — is completely unchanged: depth goes 0->1 here (real page-in
; happens) and 1->0 in BANK_PAGE_EXROM_OUT (real page-out happens).
BANK_PAGE_EXROM_IN:
    di
    ld   a, (BANK_EXROM_DEPTH)
    inc  a
    ld   (BANK_EXROM_DEPTH), a
    cp   1
    jr   nz, .already_paged_in       ; depth was already >=1 — chunk 5
                                     ; is already EXROM (an outer,
                                     ; still-active caller put it
                                     ; there) — nothing to do
    ld   a, (PORT_FF_SHADOW)
    or   %10000000                   ; bit 7 only — EXROM, not Dock;
                                     ; bits 0-6 (video mode, INTEN) are
                                     ; not this routine's to touch —
                                     ; same shadow-preserving discipline
                                     ; GFX_SET_MODE already established
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   a, %00100000                ; bit 5 = chunk 5 only; every
                                     ; other chunk's bit stays 0 (Home)
    out  (PORT_BANK_HOME), a
.already_paged_in:
    ei
    ret

; ============================================================================
; BANK_PAGE_EXROM_OUT
; Restores chunk 5 to Home — but only once BANK_EXROM_DEPTH's nesting
; counter (see BANK_PAGE_EXROM_IN just above, and that sysvar's own
; comment) actually reaches back to 0; a nested call just decrements it
; and leaves chunk 5 paged to EXROM for whichever outer caller is still
; using it. PORT_SCLD's bit 7 is deliberately left exactly as BANK_
; PAGE_EXROM_IN set it, not cleared — once PORT_BANK_HOME selects Home
; for every chunk, bit 7 is moot (nothing reads EXROM/Dock for any
; chunk any more), so touching it here would only be an unneeded extra
; read-modify-write through PORT_FF_SHADOW for no observable effect.
; In:  none
; Out: none
; Destroys: AF
; ============================================================================
BANK_PAGE_EXROM_OUT:
    di
    ld   a, (BANK_EXROM_DEPTH)
    or   a
    jr   z, .depth_already_zero       ; defensive: an unbalanced OUT
                                      ; with no matching IN — nothing
                                      ; to unpage, don't underflow the
                                      ; counter
    dec  a
    ld   (BANK_EXROM_DEPTH), a
    jr   nz, .still_nested             ; still >=1 after decrementing —
                                       ; an outer caller is still
                                       ; relying on chunk 5 staying
                                       ; EXROM-mapped
    xor  a
    out  (PORT_BANK_HOME), a         ; all chunks back to Home
.still_nested:
.depth_already_zero:
    ei
    ret

; ============================================================================
; BANK_CALL_EXROM
; Convenience wrapper: pages chunk 5 in, calls its fixed entry point
; ($A000), pages back out. The EXROM payload itself runs with
; interrupts enabled throughout — see this file's header.
; In:  none
; Out: whatever the EXROM payload's own contract defines
; Destroys: whatever the EXROM payload's own contract defines, plus AF
; ============================================================================
BANK_CALL_EXROM:
    call BANK_PAGE_EXROM_IN
    call $A000
    jr BANK_PAGE_EXROM_OUT

    ENDIF
