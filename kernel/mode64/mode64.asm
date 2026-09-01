; ============================================================================
; kernel/mode64/mode64.asm — 64-column display mode
;
; Phase 8 stretch goal. PROVENANCE, stated plainly: this is NOT
; original-to-2068-Forth code, and it is NOT simply "inherited from
; 2068-Leap" the way the rest of kernel/ is either — it is real,
; working, once-shipped 2068-Leap code that was later REMOVED from
; that project (kernel/graphics/graphics.asm's own current comment:
; "Mode 2 (64-Column) was removed 2026-08-20 — real overhead vs. value
; trade-off"), for that project's own ROM-budget reasons, not because
; it didn't work. No trace of it survives in 2068-Leap's own git
; history (checked directly: `git log -S"64-Column"` on that repo
; finds only the baseline commit that already carries the removal
; comment). It was recovered from an OLDER pre-git backup tarball
; (~/Backup/ts2068rom.tar.gz "with full graphics", dated before the
; 2026-08-20 removal) at the user's own suggestion to check there
; before writing this from scratch — good thing: this project's own
; first attempt at this file, before that backup was found, had the
; wrong bit pattern (bit 2 alone, going only off the ROM disassembly's
; per-bit description) — the real, tested code below sets bits 1 AND 2
; together, which the disassembly's own bit-by-bit listing doesn't
; make obvious on its own.
;
; Ported here (not into kernel/graphics/graphics.asm, which stays
; exactly as inherited) with sysvars renumbered into this project's own
; probe-verified-empty $8426-$8FFF range (docs/PROJECT_PLAN.md's Phase
; 5 section) rather than the old backup's own addresses, which belong
; to a memory layout this project never had.
;
; HARDWARE FACT (real, tested, from the recovered code's own comments,
; itself checked against "the manual's own table" — cross-consistent
; with this project's own independent check against "Timex Sinclair
; 2068 ROM Disassembly," David Anderson 2023, which documents the same
; port $FF bit meanings without spelling out that 64-column mode needs
; BOTH bit 1 and bit 2 set together, not bit 2 alone):
;   port $FF (PORT_SCLD, the SCLD's Display Enhancement Control
;   Register) bits 0-2 = %110 is the 64-column mode marker; bits 3-5
;   hold an ink/paper palette (0-7); bits 6-7 are keyboard-interrupt-
;   disable and EXROM-enable, shared with kernel/bank and
;   kernel/interrupt — never touched here, only preserved, via the
;   same PORT_FF_SHADOW read-modify-write discipline kernel/graphics's
;   own GFX_SET_MODE/GFX_SET_BORDER already established.
;
; 64-column mode has no per-cell or per-pixel color the way normal
; mode's attribute bytes give it — the whole screen shares one
; ink/paper pair, chosen by MODE64_SET_PALETTE, not per shape or word.
;
; SMALLEST PROVABLE SLICE for this phase: MODE64_ON/OFF (the mode
; switch itself) and MODE64_WRITE_PIXEL/MODE64_READ_PIXEL (so
; rom/forth_smoke_p8b.asm can prove a pixel plotted in this mode is
; readable back at exactly the coordinate it was plotted at, the same
; GFX_READ_PIXEL-based verification technique Phase 5 already
; established for normal-mode PLOT). MODE64_SET_PALETTE is included
; since GFX_WRITE_PIXEL64's own real behavior depends on GFX_MODE being
; set correctly by SOME mode-select path, but line/circle/fill
; equivalents for this mode are not ported — real, further follow-up
; work, not silently folded into this slice.
; ============================================================================

    IFNDEF KERNEL_MODE64_ASM
    DEFINE KERNEL_MODE64_ASM

    INCLUDE "include/hardware.inc"
    INCLUDE "include/sysvars.inc"

SECOND_DISPLAY_DELTA_M64 EQU $2000   ; SECOND_DISPLAY_ADDR - SCREEN_ADDR;
                                     ; a plain constant (not a sysvar),
                                     ; safe to recompute locally rather
                                     ; than depend on the old backup's
                                     ; own include/hardware.inc entry

; ---- Phase 8 RAM state — same probe-verified $8426-$8FFF gap as every
; other core/ or kernel-addition file's own scratch (docs/PROJECT_PLAN.md
; Phase 5). The old backup's own addresses ($84AF+) belonged to a
; memory layout this project doesn't have and were not reused. ----
GFX_PALETTE64          EQU $87B0   ; 1 byte: 0-7, persists across mode switches
GFX_PIXEL64_MASK       EQU $87B1   ; 1 byte: GFX_PIXEL64_ADDR_SETUP's own scratch
GFX_PIXEL64_WHICH_FILE EQU $87B2   ; 1 byte: 0 = Primary Display File, 1 = Second
GFX_PIXEL64_BYTECOL    EQU $87B3   ; 1 byte: real byte-column within the row
GFX_PIXEL64_OVER       EQU $87B4   ; 1 byte: MODE64_WRITE_PIXEL's own scratch

; ============================================================================
; MODE64_ON ( -- )
; Enters 64-column mode: sets port $FF bits 0-2 to %110 (preserving
; bits 3-7, but bits 3-5 are then immediately set to the current
; palette by the same write), sets GFX_MODE = 2 (kernel/graphics's own
; inherited sysvar; other inherited routines that check GFX_MODE will
; now see it), and clears the Second Display File's bitmap to zero
; (raw zero, not ATTR_DEFAULT — this is pixel data, not an attribute
; byte; leaving old attribute bytes or power-on garbage there would
; show as speckling the moment this mode is entered).
; ============================================================================
MODE64_ON:
    ld   a, 2
    ld   (GFX_MODE), a

    ld   a, (GFX_PALETTE64)
    add  a, a
    add  a, a
    add  a, a
    or   6
    ld   b, a                    ; b = new bits 0-5 combined
    ld   a, (PORT_FF_SHADOW)
    and  %11000000               ; keep only bits 6-7 (EXROM enable,
                                  ; keyboard-interrupt disable) — this
                                  ; mode's own bits occupy 0-5 entirely
    or   b
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a

    ld   hl, SECOND_DISPLAY_ADDR
    ld   de, SECOND_DISPLAY_ADDR + 1
    ld   bc, 6144 - 1
    xor  a
    ld   (hl), a
    ldir
    ret

; ============================================================================
; MODE64_OFF ( -- )
; Returns to Normal mode — delegates to kernel/graphics's own inherited
; GFX_SET_MODE(0), which is completely unchanged from 2068-Leap and
; still handles Normal mode correctly; no need to duplicate that path.
; ============================================================================
MODE64_OFF:
    xor  a
    jp   GFX_SET_MODE

; ============================================================================
; MODE64_SET_PALETTE ( A = palette 0-7 -- )
; Selects the ink/paper pair. Stores the choice regardless of the
; currently active mode (so entering 64-column mode later remembers
; the last palette picked), and updates the port immediately too if
; 64-column mode is already active.
; ============================================================================
MODE64_SET_PALETTE:
    and  %00000111
    ld   (GFX_PALETTE64), a

    ld   a, (GFX_MODE)
    cp   2
    ret  nz

    ld   a, (GFX_PALETTE64)
    add  a, a
    add  a, a
    add  a, a
    or   6
    ld   b, a
    ld   a, (PORT_FF_SHADOW)
    and  %11000000
    or   b
    ld   (PORT_FF_SHADOW), a
    out  (PORT_SCLD), a
    ret

; ============================================================================
; GFX_PIXEL64_ADDR_SETUP (internal, not a public entry point) — shared
; address computation for MODE64_WRITE_PIXEL/MODE64_READ_PIXEL. Reuses
; kernel/graphics's own already-verified BIT_MASK_TABLE/ROW_BASE_TABLE
; and GFX_PIXEL_ROW/GFX_PIXEL_SCANLINE scratch for the row/scanline
; part — identical to the single-file case, only the column math and
; the choice of which display file differ.
; In:  HL = x (0-511, caller masks/clamps), C = y (0-191, caller clamps)
; Out: HL = bitmap byte address, A = bit mask (bit7 = leftmost)
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_PIXEL64_ADDR_SETUP:
    ld   a, l
    and  7
    ld   e, a
    ld   d, 0
    push hl
    ld   hl, BIT_MASK_TABLE
    add  hl, de
    ld   a, (hl)
    ld   (GFX_PIXEL64_MASK), a
    pop  hl

    srl  h
    rr   l
    srl  h
    rr   l
    srl  h
    rr   l

    ld   a, l
    and  1
    ld   (GFX_PIXEL64_WHICH_FILE), a

    srl  l
    ld   a, l
    ld   (GFX_PIXEL64_BYTECOL), a

    ld   a, c
    and  7
    ld   (GFX_PIXEL_SCANLINE), a
    ld   a, c
    rrca
    rrca
    rrca
    and  %00011111
    ld   (GFX_PIXEL_ROW), a

    ld   a, (GFX_PIXEL_ROW)
    ld   l, a
    ld   h, 0
    add  hl, hl
    ld   de, ROW_BASE_TABLE
    add  hl, de
    ld   e, (hl)
    inc  hl
    ld   d, (hl)
    ld   a, (GFX_PIXEL64_BYTECOL)
    add  a, e
    ld   e, a
    jr   nc, .no_col_carry
    inc  d
.no_col_carry:
    ld   a, (GFX_PIXEL_SCANLINE)
    add  a, d
    ld   d, a

    ld   h, d
    ld   l, e
    ld   a, (GFX_PIXEL64_WHICH_FILE)
    or   a
    jr   z, .no_delta
    ld   de, SECOND_DISPLAY_DELTA_M64
    add  hl, de
.no_delta:
    ld   a, (GFX_PIXEL64_MASK)
    ret

; ============================================================================
; MODE64_WRITE_PIXEL ( HL = x 0-511, C = y 0-191, D = OVER flag -- )
; Sets or XOR-toggles one pixel in 64-column mode. No attribute step —
; see this file's own header on the single shared palette.
; ============================================================================
MODE64_WRITE_PIXEL:
    ld   a, d
    ld   (GFX_PIXEL64_OVER), a
    call GFX_PIXEL64_ADDR_SETUP
    ld   b, a
    ld   a, (GFX_PIXEL64_OVER)
    or   a
    jr   z, .set
    ld   a, (hl)
    xor  b
    jr   .write
.set:
    ld   a, (hl)
    or   b
.write:
    ld   (hl), a
    ret

; ============================================================================
; MODE64_READ_PIXEL ( HL = x 0-511, C = y 0-191 -- A = 1 or 0 )
; ============================================================================
MODE64_READ_PIXEL:
    call GFX_PIXEL64_ADDR_SETUP
    ld   b, a
    ld   a, (hl)
    and  b
    ret  z
    ld   a, 1
    ret

    ENDIF
