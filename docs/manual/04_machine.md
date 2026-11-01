# Part 4 -- Words of the machine

The words that work the TS2068 itself, in ASCII order of their name: printing and the keyboard, colour and graphics,
the AY sound chip, the tape and the printer. The words of the language are in [Part 3](03_language.md), which also
says [how to read an entry](03_language.md#how-to-read-an-entry): the stack effects, kinds and examples here are
written the same way.

**The screen.** Text has 24 rows of 32 columns; row 0 is the top, column 0 the left. Rows 0 to 22 are for output and
row 23 is the line you type on. Printing starts at the *print position*, which moves one column right after each
character and to the next row after column 31; printing below row 22 scrolls the output up a row. Pixels have *x*
from 0 (left) to 255 and *y* from 0 (**top**) to 191, counted from the top left as text is (not as in Sinclair BASIC,
where *y* counts up from the bottom). A point off the screen is not drawn and is not an error. See
[Screen](05_concepts.md#screen) and [Graphics](05_concepts.md#graphics).

**Colours** are the TS2068's eight: 0 black, 1 blue, 2 red, 3 magenta, 4 green, 5 cyan, 6 yellow, 7 white. At
switch-on the ink is 0 and the paper 7, with bright and flash off.

**Frames.** A *frame* is one display refresh: 1/60 second on a TS2068, 1/50 second on ZEsarUX. Words that wait or
play for a time count frames.

## Summary

| Group | Words |
|---|---|
| **I/O** | `.` `."` `EMIT` `CR` `SPACE` `SPACES` `TYPE` `AT-XY` `CLS` `KEY` `KEY?` `BREAK?` `ACCEPT` `INPUT` `STICK` `IN` `OUT` |
| **graphics** | `INK` `PAPER` `BRIGHT` `FLASH` `BORDER` `PLOT` `LINE` `RECT` `FILL` `CIRCLE` `POLYGON` `POLYGON-FILL` `HIRES` `NORMAL` `UDG` `SPRITE-DEFINE` `SPRITE-SHOW` `SPRITE-HIDE` `ULAPLUS` `PALETTE` |
| **sound** | `BEEP` `SOUND` `TONE` `VOLUME` `MIXER` `NOISE` `ENVELOPE` |
| **storage** | `SAVE-TEXT` `VERIFY-TEXT` `LOAD-TEXT` `SAVE-LIB` `VERIFY-LIB` `LOAD-LIB` |
| **printer** | `LPRINT` `LLIST` |

---
