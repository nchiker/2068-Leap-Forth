; ============================================================================
; rom/mode64_visual_check.asm — NOT a smoke ROM, no PASS/FAIL checkpoint.
; A one-off diagnostic image, kept as a reproducible tool, built for
; the ULAPlus visual-fidelity cross-check (docs/PROJECT_PLAN.md's
; "Future stretch goal" section, RESOLVED 2026-09-06). Draws two solid
; 20x20 pixel blocks in real 64-column ("Mode 6") mode, one inside the
; Primary Display File (x=50-69) and one inside the Second Display
; File (x=450-469), with a wide gap of untouched pixels between them,
; then halts forever.
;
; RESULT (already run, see PROJECT_PLAN.md for the full writeup): both
; blocks' bitmap data is confirmed byte-correct via ZRCP `read-memory`,
; but ZEsarUX 13.0 renders the whole interior as a single flat black
; rectangle regardless (tried palettes 0/3/5/7 — only the BORDER color
; tracks the palette, never the interior). Since ZEsarUX's own TS2068
; profile has zero ULAPlus involvement, this rules out "Fuse's ULAPlus
; patch is misinterpreting port $FF" — both emulators most likely just
; have an incomplete rendering path for this rare hardware mode.
; rom/hires_visual_check.asm is the HIRES-mode companion, which DOES
; render correctly in ZEsarUX -- worth running side by side with this
; one, not in isolation.
;
; Home-ROM only, no EXROM/Forth dictionary needed at all. To re-run:
; assemble, then concatenate with an 8KB EXROM (ZEsarUX's own TS2068
; --romfile format is the 16KB Home ROM immediately followed by an 8KB
; EXROM in ONE file -- unlike Fuse's separate --rom-ts2068-0/-1 flags):
;   cat mode64_visual_check_rom0.bin build/stock_shaped_exrom.bin \
;     > /tmp/combined.bin
;   zesarux --noconfigfile --machine TS2068 --romfile /tmp/combined.bin \
;     --enable-remoteprotocol --remoteprotocol-port 10111 --vo null \
;     --ao null &
; then connect a ZRCP client (e.g. a raw TCP socket) to 127.0.0.1:10111
; and send `save-screen /path/out.bmp` (also: `get-io-ports` shows the
; real port $FF value under "Timex FF port", `read-memory <addr>
; <len>` dumps raw bitmap bytes) -- must be run from ZEsarUX's own
; install directory, or it won't find its stock ROM-lookup files.
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

COLD_START:
    ld   sp, $FF00
    ld   a, 5                ; palette 5 -- a distinct, non-black ink/
    ld   (GFX_PALETTE64), a  ; paper pair, same choice
                             ; rom/forth_smoke_p8b.asm's own checkpoint
                             ; 2 already uses for exactly this reason
                             ; (GFX_PALETTE64 is uninitialized RAM
                             ; otherwise). Tried 0, 3, 5, and 7 during
                             ; the real ULAPlus-visual-fidelity cross-
                             ; check this file was built for
                             ; (docs/PROJECT_PLAN.md's own "Future
                             ; stretch goal" section) -- every value
                             ; changes the BORDER color but the
                             ; interior always renders as a flat black
                             ; rectangle in ZEsarUX regardless, so the
                             ; specific value here doesn't matter
    call MODE64_ON

    ; left block: x = 50..69, y = 80..99 (Primary Display File)
    ld   hl, 50
    ld   (BLOCK_X0), hl
    call DRAW_BLOCK

    ; right block: x = 450..469, y = 80..99 (Second Display File --
    ; 450 >= 256, so this whole block lives past the file boundary)
    ld   hl, 450
    ld   (BLOCK_X0), hl
    call DRAW_BLOCK

.hang:
    jr   .hang

; ---- DRAW_BLOCK: fills a 20x20 solid block at (BLOCK_X0, 80) ----
DRAW_BLOCK:
    ld   a, 80
    ld   (CURRENT_Y), a
    ld   b, 20              ; 20 rows
.row_loop:
    push bc
    ld   hl, (BLOCK_X0)
    ld   b, 20              ; 20 columns
.col_loop:
    push bc
    push hl
    ld   a, (CURRENT_Y)
    ld   c, a
    ld   d, 0               ; OVER=0: set, don't XOR-toggle
    call MODE64_WRITE_PIXEL ; HL=x, C=y, D=over -- destroys AF,BC,DE,HL
    pop  hl
    inc  hl
    pop  bc
    djnz .col_loop
    ld   a, (CURRENT_Y)
    inc  a
    ld   (CURRENT_Y), a
    pop  bc
    djnz .row_loop
    ret

BLOCK_X0  EQU $8800   ; 2 bytes
CURRENT_Y EQU $8802   ; 1 byte -- reset to 80 at the top of every
                      ; DRAW_BLOCK call

    INCLUDE "kernel/math/math.asm"
    INCLUDE "kernel/graphics/graphics.asm"
    INCLUDE "kernel/mode64/mode64.asm"

    DS   $4000 - $, $FF

    SAVEBIN "mode64_visual_check_rom0.bin", $0000, $4000
