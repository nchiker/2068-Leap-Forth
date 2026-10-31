; ============================================================================
; include/forth_version.inc -- the ROM's version, shown on the status bar (row 23) at power-on
;
; From before the startup chime's first note until the first key (rom/forth_boot.asm COLD_START), as
; Leap V2 shows its own (~/2068-Leap include/v2_version.inc). Edit it at each release; it is not
; generated from git, so that a build stays reproducible (make repro). At most 27 characters: it starts
; at column 2 (the cursor is in column 0) and the bar's colour cells are columns 29-31.
; ============================================================================
FORTH_VERSION_TEXT: DB "2068 FORTH V2.0", 0
