; ============================================================================
; tests/layout_negctl.asm -- negative controls for the RAM layout guard
; (-DLAYOUT_NEGCTL=n; tools/check_ram_layout.py --negative, make check)
;
; Each control puts one deliberate violation in code appended after the production HOME code
; (rom/forth_boot.asm; the production bytes keep their addresses, and the control build is
; assembled into a temporary directory). The guard must report every one; the text in
; backquotes must appear in its report.
; ============================================================================

    IF LAYOUT_NEGCTL == 1               ; control 1: expect `in the line store`
NEGCTL_CELL     EQU STORE_START + $10
    ENDIF
    IF LAYOUT_NEGCTL == 2               ; control 2: expect `in the machine stack`
NEGCTL_CELL     EQU MACHINE_STACK_LIMIT + $100
    ENDIF
    IF LAYOUT_NEGCTL == 3               ; control 3: expect `in FILL's shadow plane`
NEGCTL_CELL     EQU GFX_FILL_SHADOW + $100
    ENDIF
    IF LAYOUT_NEGCTL == 4               ; control 4: expect `in the data stack`
NEGCTL_CELL     EQU DSTACK_LIMIT + $40
    ENDIF
    IF LAYOUT_NEGCTL == 5               ; control 5: expect `in the dictionary`
NEGCTL_CELL     EQU FORTH_DICT_RAM + $10
    ENDIF
    IF LAYOUT_NEGCTL == 6               ; control 6: expect `in the unused top`
NEGCTL_CELL     EQU MACHINE_STACK_TOP + 8
    ENDIF
    IF LAYOUT_NEGCTL == 7               ; control 7: expect `in free space`
NEGCTL_CELL     EQU UDG_TABLE + UDG_COUNT * 8 + 8
    ENDIF
    IF LAYOUT_NEGCTL == 8               ; control 8: expect `in the sprite buffers`
NEGCTL_CELL     EQU SPRITE_SLOT_IMG_BUF + 4
    ENDIF
    IF LAYOUT_NEGCTL == 9               ; control 9: expect `in the float stack`
NEGCTL_CELL     EQU FSTACK_LIMIT + 2
    ENDIF
    IF LAYOUT_NEGCTL == 10              ; control 10: expect `literal RAM address $8123`
    ENDIF
    IF LAYOUT_NEGCTL == 11              ; control 11: expect `defined outside include/forth_layout.inc`
NEGCTL_CELL     EQU RAM_CELLS_BASE + $10   ; a legitimate place for a cell; the fault is where it is defined
    ENDIF
    IF LAYOUT_NEGCTL == 12              ; control 12: expect `which only EXROM code may use`
    ENDIF

NEGCTL_CODE:
    IF LAYOUT_NEGCTL == 10
    ld   a, ($8123)
    ELSE
    IF LAYOUT_NEGCTL == 12
    ld   hl, GFX_FILL_STACK             ; FILL's seed stack belongs to the EXROM's FILL
    ELSE
    ld   (NEGCTL_CELL), a
    ENDIF
    ENDIF
    ret
