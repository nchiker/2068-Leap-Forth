\ paging the graphics EXROM in and out leaves the RAM under $A000 and at $C000 intact
\ kernel routines BANK_PAGE_EXROM_IN (3183) and _OUT (3210) are run by EXECUTE; the depth counter is at 33544 (addresses of this build)
90 {GRAPHICS_EXROM_TABLE} C! {GRAPHICS_EXROM_TABLE} C@ .                 \ expect: 90
{BANK_PAGE_EXROM_IN} EXECUTE {GRAPHICS_EXROM_TABLE} C@ .                \ expect: 195
198 49152 C! 49152 C@ .                \ expect: 198
{BANK_PAGE_EXROM_OUT} EXECUTE {GRAPHICS_EXROM_TABLE} C@ . {BANK_EXROM_DEPTH} C@ .     \ expect: 90 0
\ a graphics word pages in and back out by itself, leaving the RAM marker and the depth as they were
CLS 0 18 AT-XY 90 {GRAPHICS_EXROM_TABLE} C! 20 20 40 40 RECT      \ draws
{GRAPHICS_EXROM_TABLE} C@ . {BANK_EXROM_DEPTH} C@ .                  \ expect: 90 0
