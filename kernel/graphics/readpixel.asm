; ============================================================================
; kernel/graphics/readpixel.asm -- GFX_READ_PIXEL, for the test ROMs only
;
; Step O15 item 5: the product ROMs no longer read a pixel through the kernel
; (FILL does it in the EXROM), so this 10-byte helper left kernel/graphics/
; graphics.asm. The smoke and test ROMs that check pixels with it INCLUDE this
; file right after kernel/graphics/graphics.asm (it needs GFX_PIXEL_ADDR_SETUP).
; ============================================================================

    IFNDEF KERNEL_READPIXEL_ASM
    DEFINE KERNEL_READPIXEL_ASM

; ============================================================================
; GFX_READ_PIXEL
; Tests whether a pixel is currently set — the mechanism behind POINT(x,y).
; In:  B = x (0-255), C = y (0-191, caller clamps)
; Out: A = 1 if the pixel is set, 0 if not
; Destroys: AF, BC, DE, HL
; ============================================================================
GFX_READ_PIXEL:
    call GFX_PIXEL_ADDR_SETUP      ; HL = bitmap byte address, A = mask
    ld   b, a
    ld   a, (hl)
    and  b
    ret  z
    ld   a, 1
    ret

    ENDIF
