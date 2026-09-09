; ============================================================================
; rom/forth_lros.asm — 2068-Forth LROS cartridge boot stub (EXPERIMENTAL)
;
; NOT a replacement for rom/forth_boot.asm. forth_boot.asm is a Home ROM
; replacement (loaded via Fuse's --rom-ts2068-0, or flashed to physically
; replace U19): it owns $0000 outright, as if it WERE the machine's system
; ROM. This file targets a completely different loading mechanism — the
; TS2068 cartridge/DOCK port — where the stock Timex Home ROM stays
; resident, boots and initializes the machine first, and THEN hands off
; execution to this code. Real hardware and TS-Pico users who don't want
; to replace their system ROM load this instead.
;
; Per the LROS (Language ROM-Oriented Software) cartridge convention (see
; docs/lros_cartridge.md for full citations and format details — sourced
; from published TS2068 cartridge/DCK format documentation, cross-checked
; against two independent write-ups, not guessed), a 5-byte header sits at
; the very start of chunk 0 ($0000 once the cartridge is paged in):
;   offset 0: unused
;   offset 1: cartridge type ($01 = LROS)
;   offset 2-3: entry address, little-endian
;   offset 4: chunk-in-use flags (bit 3 must stay set — keeps the stock
;             OS's own chunk-3 transfer/stack code available during
;             handoff, per the same sourced convention)
;
; This is a Milestone-0-equivalent stub, NOT the full 2068-Forth
; dictionary: the complete interpreter (rom/forth_boot.asm) is a 24K
; image (16K Home + 8K EXROM) and does not fit in a single 8K DOCK chunk.
; Fitting the real dictionary into the LROS/DOCK model is follow-up work
; (see docs/lros_cartridge.md's own "Open work" section) — this stub only
; proves the header format and handoff entry point are correct, the same
; incremental-proof approach this project used for its own Milestone 0
; (rom/main.asm) before any Forth-specific code existed.
;
; NOT YET VERIFIED ON REAL HARDWARE OR AGAINST A REAL TS-PICO — only
; buildable and packageable into a .dck file for Fuse's DOCK-cartridge
; loading (`fuse --machine ts2068 --dck build/forth_lros.dck`). Treat the
; border-cycle behaviour as reviewed-by-eye only until confirmed running.
;
; Build:
;   make forth-lros            # assembles build/forth_lros_chunk0.bin
;   tools/pack_dck.sh build/forth_lros_chunk0.bin build/forth_lros.dck
;
; Run (Fuse, DOCK cartridge slot):
;   fuse --machine ts2068 --dck build/forth_lros.dck
; ============================================================================

    INCLUDE "include/hardware.inc"

    DEVICE NOSLOT64K

    ORG $0000

; ---- LROS header (5 bytes, chunk 0 offset $0000-$0004) ----
LROS_HEADER:
    DB   $00                ; offset 0: unused
    DB   $01                ; offset 1: cartridge type = LROS
    DW   COLD_START          ; offset 2-3: entry address, little-endian
    DB   %00001000          ; offset 4: chunk-in-use flags — bit 3 set
                             ; (chunk 3 / OS transfer+stack stays available)

; ============================================================================
; COLD_START
; Runs after the stock Home ROM hands off control. Cycles the border
; through all 8 colours — the same isolated, dependency-free smoke test
; rom/main.asm used for the Home-ROM boot chain, applied here to prove the
; LROS handoff entry point itself, before anything more complex is built
; on top of it.
; ============================================================================
COLD_START:
    ; Deliberately does NOT touch SP: under real LROS handoff the stock
    ; Home ROM has already set up a live stack (that's the whole point of
    ; keeping chunk 3 available per the header above) — reinitializing it
    ; here would fight the very handoff contract this stub exists to
    ; prove. Confirm this assumption against real hardware/Fuse DOCK
    ; behaviour before building anything stateful on top of this stub.
    xor  a
    ld   (BORDER_COUNTER), a

BORDER_LOOP:
    ld   a, (BORDER_COUNTER)
    and  $07
    out  (PORT_ULA), a

    ld   hl, BORDER_COUNTER
    inc  (hl)

    ld   bc, $4000
DELAY_LOOP:
    dec  bc
    ld   a, b
    or   c
    jr   nz, DELAY_LOOP

    jr   BORDER_LOOP

; RAM scratch, not ROM data — see rom/main.asm's own BORDER_COUNTER note
; for why (INC (HL) against ROM-resident data silently fails on real
; hardware). $8000 is arbitrary scratch, chosen only to stay clear of the
; low chunk-0/chunk-3 handoff area this stub is actually testing.
BORDER_COUNTER EQU $8000

    DS   $2000 - $, $FF      ; pad to one full 8K DOCK chunk

    SAVEBIN "forth_lros_chunk0.bin", $0000, $2000
