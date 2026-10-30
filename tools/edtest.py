#!/usr/bin/env python3
"""edtest.py - the editor screen oracle (audit item T12, docs/V2/FORTH_V2_REUSE_AUDIT.md section 6.3), for step E.

Characterises the console editor of the build it is given: what the CURRENT code does, key by key, on the screen and in
memory, so that step E (a rebuild of the console and editor, audit section 4.3) can be checked against it.  Every case
asserts what the current build does, exactly (screen rows, edit line, cursor cell, memory); a case that looks like a
defect still asserts the current behaviour (the defects are listed in the report that came with this file, not fixed).
Since step E item 5 (the merged redraw) the points of E10 -- the room check at the display width, the cursor on
a full row -- are asserted as the NEW build does them (cases 7, 8, 9, 10, 18; the old build fails them).  Step M6 removed the
64-column mode (docs/V2/MODE6_REMOVAL_SPEC.md): case 14 asserts that `64COL` is an unknown word, N11 is retired, and the
64-column parts of cases 8, 9, 10, 18 and 19 are gone; the 32-column parts are unchanged.
A rebuilt editor is expected to FAIL the cases that describe behaviour step E changes on purpose; each such failure is a
line to decide on, not a regression by itself.

RUN   python3 -I tools/edtest.py [--build DIR] [--group old|new|both] [--workers N] [--port P] [--json OUT] [-v] [--selftest] [substring ...]
      DIR holds forth_boot_rom0.bin and graphics_exrom.bin (default: build/; DIR or DIR/build, as tools/fharness.py, so
      the images of an older build in a git worktree work).  Substrings select cases by name.  One PASS/FAIL line per
      case with its detail (a passing case's detail is cut short; -v prints it whole), then a summary.  JSON (default build/edtest.json): every case with its parts, the typing-cost
      numbers, the wall times.  Exit 0 = all cases pass, 1 = any case fails, 2 = harness error (bad build directory, port
      in use, no emulator could run a task).  Ports P .. P+workers-1, default 10900-10919 (fharness.py's range).
      TWO GROUPS.  `old` = the 19 cases of T12 described below (what the console editor of the audit baseline does); `new` =
      the cases step E adds (docs/V2/EDITOR_SPEC.md section 8, second table: N1-N3, N5-N10 and N12-N13; N4 is case N4 of
      tools/tapetest.py) which describe what the REBUILT console, store and full-screen view must do and so FAIL on the old
      build, each with the detail of the first thing that differs.  Default: both.  Every output line and the JSON carry the
      group (`PASS old 7 line-full`, `FAIL new N5 dict-ceiling`); a substring may also be a case number (N5).  `--selftest` needs no
      emulator: it drives the new cases' key sequences against a model of the view (see STEP E CASES).

Derived from 2068-Leap-C tools/shelltest.py at its Phase 5 state: its case/expect registry, `full_reference` (after every
key the screen equals a full redraw) and the `redraw-oracle` and `typing-cost` cases are ported; copied and adapted, not
imported: nothing here reads or writes ~/2068-Leap-C.  Leap-C's other cases belong to its C shell and are not used.

What is real: the assembled images (booted as fharness does: forth_boot_rom0.bin and graphics_exrom.bin as one ROM file),
the editor (core/editor.asm), the interpreter, the workspace (core/recall.asm), the interrupt service and the keyboard
matrix scan.  What is substituted: every case runs from the snapshot of the booted machine (fharness.Machine.restore);
`key()` writes the interrupt routine's latch (KBD_LASTK, KBD_KEYHIT) and `press()` holds keys on the emulated matrix
(ISR, debounce and IO_DECODE_KEY real); the screen is read from RAM and decoded with the ROM's own font by the real
GFX_PUTCHAR (fharness.screen_rows).  The cases run on fharness.run_pool: one ZEsarUX per worker, a
restored machine for every task; a case with several parts (widths, batches, scenarios) is several tasks.

HOW THE CURSOR IS SHOWN  Not in the bitmap.  EDITOR_REDRAW draws the line (GFX_PUTCHAR, then GFX_SET_ATTR
ATTR_DEFAULT on every cell of every input row, padded to column 31) and then GFX_INVERT_ATTR on the cursor cell: ink and
paper swapped and FLASH set, so ATTR_DEFAULT $44 (bright, black paper, green ink) becomes $E0; the ULA blinks it.  The cursor
column is never W (E10, THE WRAP MODEL below): a cursor cell is always shown.
`view()` below reads the cursor cell from the FLASH attribute and the plain text from the bitmap.

THE WRAP MODEL (wrap_model, shown_rows, cursor_model, Ed) is the new build's (step E item 5, E10), asserted by the wrap-model
case.  A row holds W = 32 characters (the models keep W as a parameter; every case passes 32).  From the row's first character: if no more
than W characters remain, they are the last row.  Otherwise look at the characters at offsets W-1 down to 1 (offset 0 and
offset W are NOT looked at) for the last space: found at offset p -> the row shows p characters and p + 1 are consumed (the
space is never drawn); none found -> the row shows W characters and W are consumed (a hard break; a space that is the
(W+1)th character then starts the next row).  At most FWRAP_MAX_ROWS = 4 rows; if after the 4th row characters remain,
FWRAP_OVERFLOW = 1 (a 5th row would be needed) and FWRAP_COUNT is still 4.  wrap_model is exactly this rule (it is also the room
check's overflow test).  E10, the cursor on a full row (shown_rows): when EDIT_CURSOR = EDIT_LEN, the last row's length = W and
there are fewer than 4 rows, the wrap table in memory (FWRAP_COUNT, FWRAP_START, FWRAP_LEN) has one more row (start = EDIT_LEN,
length 0): the input area is a row taller and the cursor is at column 0 of that row; the grow, scroll and shrink rules treat it
as any other row.  With 4 rows and the last full there is no 5th row: the cursor is on the last character's cell (23, W - 1).  The
extension is made whenever WRAP_CALC runs for the edit line.  EDIT_CURSOR_TO_ROWCOL: the cursor is on the
first row i for which i is the last row or EDIT_CURSOR < the start of row i + 1; its column is EDIT_CURSOR - start of row i,
clamped to W - 1 (so a cursor on a consumed space shows right after the row's last character, and a cursor at the end of a full
hard-broken row is on the extension row's column 0; it is never W, so a cell always shows).  The screen row of row i is
24 - FWRAP_COUNT + i.  EDITOR_PROCESS_KEY: printable
codes 32-126 are inserted at EDIT_CURSOR if EDIT_LEN < EDIT_MAX_LEN (128); WRAP_CALC is run on the result at the width
(32; cursor after the inserted character), and if
FWRAP_OVERFLOW is set the insert is undone and the key ignored (the wrap table is then left describing the refused
line, at that width: FWRAP_OVERFLOW stays 1 until the next redraw; a refusal means 4 rows with overflow, so there is no extension).  DELETE (8) removes the character left of the cursor, LEFT (1) and
RIGHT (4) move it, ENTER (13) ends the line; every other code below 32 is ignored.  Grow: when the new FWRAP_COUNT is
larger than FWRAP_OLD_COUNT, for each new row the whole screen scrolls up one row (GFX_SCROLL_OUTPUT_UP, row 0 is lost)
and PRINT_ROW is decremented if PRINT_ROW >= 24 - old count, i.e. if the new row is not still blank (PRINT_ROW is the next
output row).  Shrink: the rows no longer used are cleared (GFX_CLEAR_ROW); nothing scrolls back.

THE FULL REDRAW (the reference of the redraw-oracle case; full_reference).  From the editor waiting for a key, with the
whole machine put on a checkpoint first (fharness.Machine.checkpoint / rollback), the reference screen is drawn by:
  1. call WRAP_CALC for the current EDIT_BUF / EDIT_LEN / EDIT_CURSOR, which
     sets FWRAP_COUNT (with E10's extra row);
  2. FWRAP_OLD_COUNT := FWRAP_COUNT, so the redraw decides "no growth, no shrink": nothing scrolls, no row is cleared by it;
  3. rows 20-23 (the 4 rows the input can ever use, 24 - FWRAP_MAX_ROWS ... 23) are blanked directly: all 8 pixel lines
     of every cell zero and every attribute byte of those rows set to
     ATTR_DEFAULT;
  4. call EDITOR_REDRAW, which draws every wrapped row, blank-padded and
     with ATTR_DEFAULT, and the cursor;
  5. read the screen: $4000-$5AFF (bitmap and attributes, 6912 bytes), then roll the machine back.
The rows above row 20 are the screen as the incremental editor left them: the oracle scenarios keep their output on the
upper rows (PRINT_ROW 2 or 3, no scroll), so a key that scrolls, or a stale cell above or below the input area, shows as
a difference.  The reference cannot predict a scroll; the cases where the editor scrolls (wrap-scroll) are asserted with
the Python model instead.  The oracle's own sensitivity is checked (part `control`): a stray pixel byte and a stray FLASH
attribute are each seen as a difference.

TYPING COST  T-states from the latch write (key delivery) to the next key wait (IO_READ_KEY), interrupts included
(fharness reset-tstates-partial / get-tstates-partial around Console.key).  Every figure is taken twice, each time from a
restored machine; the two must be equal (the emulation is deterministic: that is what makes the number a baseline).  No
threshold: the table is the baseline step E is measured against.  A figure includes the keyboard interrupt service
(KBD_ISR_TICK, about 2000 T, reported as isr_tstates) when one of the 50 Hz interrupts falls inside the key's processing;
which keys that is depends on the frame phase at the idle prompt, which depends on the length of the boot, so a rebuild
that changes the cold start moves the phase: compare figures within about one interrupt service (and the 20 ms-class
differences, not the small ones).

BEHAVIOURS THAT LOOK LIKE DEFECTS (the old build's; the first is fixed by step E item 5 and asserted fixed; the 64-column
defects of E10 died with the mode in step M6)
  * [fixed, E10] A line that exactly fills its last row (32, 64, 96, 128 characters) put the cursor at column W: no cursor shown
    [line-full hard, wrap-model].
  * WORKSPACE_APPEND tests the high byte of the new length against LOADTEXT_MAX_LEN / 256 + 1, so it writes up to 255 bytes
    past LOADTEXT_BUF + 8192 [workspace-append limit]; an empty line appends a separator space each time [workspace-append].
  * Forth has no BREAK check in the interpreter: only the word BREAK? sees the key [break-running].
  * After a refused key the wrap table keeps the refused line (FWRAP_OVERFLOW stays 1) and the
    screen is not redrawn until the next accepted key; harmless as far as seen [line-full].

STEP E CASES (group new; EDITOR_SPEC.md sections 3 and 5 are the specification of every assertion; a comment `READING:` in the
code marks each place where the text leaves a detail open and says which reading was taken, the strictest the text supports; where
the text allows several outcomes the case accepts exactly those and reports which one the build chose)
  N1 store-lines     committed lines are text + CR in the store at STORE_START (= LOADTEXT_BUF), STORE_END exact, an empty line
                     appends nothing, an error line does.  STORE_END is the new name of the cell WORKSPACE_END; the case uses
                     whichever the build has.
  N2 store-full      an append that does not fit (STORE_END + length + 1 > $F000) is refused: `STORE FULL` on its own row, the line
                     still runs, the store and $F000-$F0FF are unchanged; one that fits exactly is made; an empty line is no refusal.
  N3 cr-whitespace   INTERPRET_RUN called directly on sources whose words are separated by CR, TAB, LF, NUL, SOH, US (and mixed),
                     and LOAD-TEXT from a real tape (realtape-open: the emulator is reset by it and a worker whose emulator played a
                     tape gets a new one) with CR and TAB, a text without a final CR (a CR is added) and an 8,192-byte text (no
                     room: nothing added, nothing written at or above $F000).
  N5 dict-ceiling    HERE is poked near $D000 - 256 (= $CF00, the new ceiling less its 256-byte guard; the old build's own ceiling
                     is $F000) and: `: Wnn ;` in a loop is accepted only from HERE <= $CF00 and refused after, with HERE and
                     LATEST unchanged and the store at $D000 intact; VARIABLE, CONSTANT, CREATE, ARRAY, STRING refused past the
                     guard, an array that would pass it refused; `n ALLOT`, `,` and `C,` give THROW -8 under CATCH (to $CF00
                     exactly allowed, one more refused; 20000, 28672 and 32767 refused, the last two carry past $FFFF); a
                     200-byte definition below the guard is accepted and runs.  HOW A THROW SHOWS ON THIS BUILD: uncaught, it
                     prints its message (rom/forth_boot.asm RUNTIME_ERROR_HOOK: -8 is `DICTIONARY FULL`, since step F item 5); `' word CATCH .`
                     prints the code.  So -8 is asserted through CATCH, and `DICTIONARY FULL` for the uncaught form.
  N6-N9, N12, N13    the full-screen view.  It is detected by row 23 reading `LINE n/m` while the machine waits for a key; on the
                     old build `EDIT ...` gives `EDIT ?` and each case fails at once with that.  The cases keep a MODEL of the
                     view (class VModel: store lines with their session marks, the cursor line in a buffer, the cursor
                     offset; the key table of section 5 key by key; the console's word-wrap rule for the rows) and after every
                     key compare, with the model, the store bytes (from STORE_START to STORE_END), all 23 rows, the status row
                     and the one FLASH cell (the cursor).  `edtest.py --selftest` runs every sequence against the model
                     itself in place of the emulator, to find test bugs before the ROM exists.
  N6 edit-open       `EDIT SQ` opens on the last line where the words `:` and `SQ` follow each other (case-insensitive; not
                     `: SQRT`, not `: X SQ`, not a `:` line followed by an `SQ` line), cursor at its start; bare `EDIT`; a 60-line store.
  N7 edit-keys       the key table, 9 sequences (characters including all 95 printable codes, the limits, UP/DOWN, DELETE, ENTER,
                     delete-line, insert-line, BREAK, scrolling, the control keys through the keyboard matrix).
  N8 edit-commit     leaving: only marked lines run, in order, each with its mark cleared first (a line reads its own terminator);
                     an unchanged session runs nothing; an error stops at `LINE n`; no $8D left.
  N9 edit-redraw-oracle  after every key the 6,912-byte screen equals what the EXROM routine VIEW_REDRAW_ALL draws from the
                     same state (called at the key wait from a checkpoint onto a blank screen, as the redraw-oracle case does with
                     EDITOR_REDRAW), and the oracle sees a stray pixel, a stray FLASH cell and a missing cursor.  Fails with
                     `no VIEW_REDRAW_ALL` when the symbol is absent.
  N10 edit-refusals  NO EXROM (an EXROM of 8 KB of $00: fharness.stock_build makes a temporary copy of the build directory
                     for it), LONG LINE (a 199-character line in the store), `NOSUCH ?`: one message, nothing changed
                     (the store may gain the typed line), console still works.
  N11                retired in step M6 (`EDIT` in 64-column mode printed 32COL FIRST: there is no 64-column mode).
  N12 edit-typing-cost  T-states per key in the view (same method as typing-cost), 11 scenarios, each taken twice from a restored
                     machine; passes when the two are equal; no threshold (the first measurement sets the gate); printed as a table.
  N13 edit-store-full  with 0, 1 and 3 bytes of room: a change that would overflow the store (a grown line written back, a line
                     inserted) is refused with `STORE FULL` on the status row until the next key, store and line unchanged; a change
                     that fits exactly is made; delete-line gives room back.

EMULATOR LIMITS: there is no hardware here.  Every verdict is ZEsarUX's (its Z80, its ULA/SCLD and paging, its keyboard
matrix and its interrupt timing) running the ROM images; the screen is read from RAM, not from a display, so a colour,
FLASH-blink or timing effect that exists only on a real TV is not seen (the FLASH attribute bit is read, its blinking is
not), the border colour is read from the ROM's shadow of port $FE, and a real keyboard's contact bounce is not simulated.
A pass says what the emulator did, not that real hardware agrees.
"""
import argparse
import copy
import functools
import json
import os
import random
import re
import shutil
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE_DIR)                      # python3 -I does not put the script's directory on sys.path
import fharness as fh                                                       # noqa: E402
import tapes                                                                # noqa: E402
from fharness import CTRL_KEYS, INVERSE_MARK, KEY_ENTER, Z_CAPS, Z_SPACE    # noqa: E402

ROOT = fh.ROOT
BANNER = "2068-FORTH"                   # rom/forth_boot.asm BANNER
LEFT, DOWN, UP, RIGHT, DELETE, INSERT_LINE, DELETE_LINE, BREAK, ENTER = 1, 2, 3, 4, 8, 0x0B, 0x0F, 0x10, 13
MAX_LEN, MAX_ROWS = 128, 4              # EDIT_MAX_LEN, FWRAP_MAX_ROWS
LOADTEXT_BUF = 0xD000                   # LOADTEXT_BUF (checked against the symbol in the cases)
UNTYPEABLE = "[\\]^`{|}~"               # printable ASCII Forth's keyboard has no key for (audit step K)
GROW = "abcdefghi " * 10                # 100 characters, 4 rows at 32 columns
GROW97 = "a " + "b" * 64 + "  " + "c" * 29      # 97 characters, 4 rows at 32 columns (a line of the wrap-model set, and the typing cost's)


# ---------------------------------------------------------------------------------------------------- the models
def wrap_model(buf, w):
    """WRAP_CALC (the width w from GFX_MODE) for `buf` (a str): ([(start, length) ...], overflow).  See the header."""
    rows, pos, remain = [], 0, len(buf)
    while True:
        if remain <= w:
            rows.append((pos, remain))
            return rows, False
        last = None
        for rel in range(w - 1, 0, -1):         # offsets W-1 .. 1; offset 0 and offset W are not looked at
            if buf[pos + rel] == " ":
                last = rel
                break
        length, used = (w, w) if last is None else (last, last + 1)
        rows.append((pos, length))
        pos += used
        remain -= used
        if len(rows) == MAX_ROWS:
            return rows, remain != 0


def shown_rows(buf, cursor, w):
    """The wrap table in memory for the edit line `buf` with the cursor at `cursor` (WRAP_CALC with E10): wrap_model's
    rows, plus one empty row (start = len(buf), length 0) when the cursor is at the end of a last row that is full and the
    line has fewer than 4 rows, so that the cursor has a cell at column 0 of the next row.  With 4 full rows there is no
    fifth row (the cursor sits on the last character's cell, see cursor_model).  This is the number of rows the input area
    occupies; wrap_model alone is the pure WRAP_CALC rule (the room check's overflow test)."""
    rows = wrap_model(buf, w)[0]
    if cursor == len(buf) and rows[-1][1] == w and len(rows) < MAX_ROWS:
        rows = rows + [(len(buf), 0)]
    return rows


def cursor_model(rows, cursor, w):
    """EDIT_CURSOR_TO_ROWCOL: (screen row, column) of the cursor for a wrap table (shown_rows); the column is clamped to w - 1."""
    n, i = len(rows), 0
    while i != n - 1 and cursor >= rows[i + 1][0]:
        i += 1
    return 24 - n + i, min(cursor - rows[i][0], w - 1)


def screen_model(base, text, cursor, w):
    """(expected 24 rows, expected cursor cells) for a line `text` with the cursor at offset `cursor`, the output rows
    above the input area being `base` (24 rows; those the input area covers are replaced).  The cursor always has a cell."""
    rows = shown_rows(text, cursor, w)
    n = len(rows)
    exp = list(base)
    for r in range(24 - n, 24):
        exp[r] = ""
    for i, (s, ln) in enumerate(rows):
        exp[24 - n + i] = text[s:s + ln].rstrip(" ")
    return exp, [cursor_model(rows, cursor, w)]


class Ed:
    """The editor's state as the code above defines it: text, cursor, the display width, and the text, cursor and width the
    wrap table currently describes: they differ from `text`, `cursor` and `w` after a key refused because the line would need
    a 5th row.  The room check of EDITOR_PROCESS_KEY runs WRAP_CALC at the width in force (GFX_MODE), on the line with the
    character inserted and the cursor after it; after a refusal the table holds that refused line."""

    def __init__(self, w, text="", cursor=None):
        self.w, self.text = w, text
        self.cursor = len(text) if cursor is None else cursor
        self.table_text, self.table_cursor, self.table_w = text, self.cursor, w
        self.refused = None

    def rows(self):
        """The rows the input area shows now (shown_rows)."""
        return shown_rows(self.text, self.cursor, self.w)

    def nrows(self):
        return len(self.rows())

    def table(self):
        """(FWRAP_COUNT, [(start, length) ...], FWRAP_OVERFLOW) the wrap table in memory must hold."""
        rows = shown_rows(self.table_text, self.table_cursor, self.table_w)
        return len(rows), rows, int(wrap_model(self.table_text, self.table_w)[1])

    def key(self, code):
        """Apply a key code; returns True if the editor took it (False: refused or ignored)."""
        t, c = self.text, self.cursor
        self.refused = None
        if code == DELETE:
            if c == 0:
                return False
            self.text, self.cursor = t[:c - 1] + t[c:], c - 1
        elif code == LEFT:
            if c == 0:
                return False
            self.cursor = c - 1
        elif code == RIGHT:
            if c >= len(t):
                return False
            self.cursor = c + 1
        elif 32 <= code < 127:
            if len(t) >= MAX_LEN:
                self.refused = "full"
                return False
            nb = t[:c] + chr(code) + t[c:]
            if wrap_model(nb, self.w)[1]:
                self.refused, self.table_text, self.table_cursor, self.table_w = "rows", nb, c + 1, self.w
                return False
            self.text, self.cursor = nb, c + 1
        else:
            return False
        self.table_text, self.table_cursor, self.table_w = self.text, self.cursor, self.w
        return True

    def type(self, s):
        for ch in s:
            self.key(ord(ch))


def grow_scroll(base, print_row, old, new):
    """EDITOR_REDRAW's growth rule: (base rows, PRINT_ROW) after the line goes from `old` to `new` rows."""
    base = list(base)
    for c in range(old, new):
        if print_row >= 24 - c:
            base = base[1:] + [""]
            print_row -= 1
    return base, print_row


# ---------------------------------------------------------------------------------------------------- reading the machine
class View:
    def __init__(self, rows, cursor, odd):
        self.rows, self.cursor, self.odd = rows, cursor, odd


def view(m):
    """The screen as text with the cursor taken out: View(rows, cursor cells, odd attributes).  Rows are plain text (an
    inverse or unknown cell would show in them), cursor cells are those with FLASH set (their attribute must be the
    swapped ATTR_DEFAULT; `odd` lists any other attribute that is not ATTR_DEFAULT)."""
    attrs = m.read(0x5800, 768)
    dflt = m.S.get("ATTR_DEFAULT", 0x44)
    cur = [(i // 32, i % 32) for i, a in enumerate(attrs) if a & 0x80]
    want = ((dflt & 7) << 3 | (dflt >> 3) & 7 | (dflt & 0x40) | 0x80)       # ink and paper swapped, FLASH
    odd = [(i // 32, i % 32, a) for i, a in enumerate(attrs)
           if (a & 0x80 and a != want) or (not a & 0x80 and a != dflt)]
    return View(m.screen_rows(), cur, odd)


def row_cell(m, row, col):
    """The 8 bitmap bytes of character cell (row, col) of the 32-column screen."""
    return fh.cell_from(m.read(0x4000, 6144), row, col)


def wrap_table(m):
    """(FWRAP_COUNT, [(start, length) ...], FWRAP_OVERFLOW) from memory."""
    S = m.sym
    n = m.read(S("FWRAP_COUNT"), 1)[0]
    st, ln = m.read(S("FWRAP_START"), 4), m.read(S("FWRAP_LEN"), 4)
    return n, [(st[i], ln[i]) for i in range(min(n, 4))], m.read(S("FWRAP_OVERFLOW"), 1)[0]


def read_screen(m):
    """The bytes the oracle compares: $4000-$5AFF (bitmap and attributes)."""
    return m.read(0x4000, 6912)


def first_diff(a, b):
    """Describe the first difference of two read_screen images."""
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            addr = 0x4000 + i
            if addr >= 0x5800 and addr < 0x5B00:
                return "attribute row %d col %d: %02X, reference %02X (%d byte(s) differ)" % (
                    (addr - 0x5800) // 32, (addr - 0x5800) % 32, x, y, sum(p != q for p, q in zip(a, b)))
            line = (addr >> 8) & 7
            row = ((addr >> 11) & 3) * 8 + ((addr >> 5) & 7)
            col = addr & 31
            return "bitmap row %d col %d line %d: %02X, reference %02X (%d byte(s) differ)" % (
                row, col, line, x, y, sum(p != q for p, q in zip(a, b)))
    return None


class Check:
    """Collects assertion failures; result() is the (ok, detail) of a part."""

    def __init__(self):
        self.fails, self.notes, self.data, self.nfail = [], [], {}, 0

    def eq(self, label, got, want):
        if got != want:
            self.nfail += 1
            if len(self.fails) < 6:
                self.fails.append("%s: got %s, want %s" % (label, _short(got), _short(want)))
        return got == want

    def true(self, label, cond, info=""):
        if not cond:
            self.nfail += 1
            if len(self.fails) < 6:
                self.fails.append("%s%s" % (label, (": " + info) if info else ""))
        return bool(cond)

    def note(self, text):
        self.notes.append(text)

    def result(self):
        if self.nfail:
            more = (" (+%d more)" % (self.nfail - len(self.fails))) if self.nfail > len(self.fails) else ""
            return dict(ok=False, detail="; ".join(self.fails) + more, data=self.data)
        return dict(ok=True, detail="; ".join(self.notes), data=self.data)


def _short(v, n=170):
    s = repr(v)
    return s if len(s) <= n else s[:n - 3] + "..."


# ---------------------------------------------------------------------------------------------------- the environment
class Env:
    """The machine of one task and the helpers every case uses."""

    def __init__(self, m):
        self.m = m
        self.S = m.sym
        self.con = fh.Console(m)

    def boot(self):
        """The booted machine.  Returns the base rows (the output rows above the input area)."""
        self.con.boot()
        return [BANNER] + [""] * 23

    def u8(self, name):
        return self.m.read(self.S(name), 1)[0]

    def edit_state(self):
        return self.con.edit_line(), self.u8("EDIT_CURSOR")

    def print_pos(self):
        return self.u8("PRINT_ROW"), self.u8("PRINT_COL")

    def press_ctrl(self, code):
        self.con.press_code(CTRL_KEYS[code], what=code)

    def check_view(self, ck, label, base, ed, wrap=True):
        """The editor must show `ed`: edit line, cursor offset, screen rows (model), cursor cell, no stray attribute, and
        the wrap table."""
        m = self.m
        text, cur = self.edit_state()
        ck.eq(label + " edit line", text, ed.text)
        ck.eq(label + " EDIT_CURSOR", cur, ed.cursor)
        exp, cells = screen_model(base, ed.text, ed.cursor, ed.w)
        v = view(m)
        if v.rows != exp:
            bad = [(r, v.rows[r], exp[r]) for r in range(24) if v.rows[r] != exp[r]]
            ck.true(label + " screen rows", False, "row %d got %s, want %s (%d rows differ)" % (
                bad[0][0], _short(bad[0][1]), _short(bad[0][2]), len(bad)))
        ck.eq(label + " cursor cell", v.cursor, cells)
        ck.eq(label + " stray attributes", v.odd, [])
        if wrap:
            ck.eq(label + " wrap table", wrap_table(m), ed.table())


def screen_sig(m):
    return m.read(0x4000, 6912)


def type_keys(env, ed, text, ck=None, label="", base=None):
    """Type `text` through the latch, mirroring it into `ed`; with ck/base, check the view after every key."""
    for ch in text:
        env.con.key(ord(ch))
        ed.key(ord(ch))
        if ck is not None:
            env.check_view(ck, "%s after %r" % (label, ed.text[-12:]), base, ed)


def step(env, ck, label, base, ed, code):
    env.con.key(code)
    ed.key(code)
    env.check_view(ck, "%s key %d (%r)" % (label, code, ed.text[max(0, ed.cursor - 6):ed.cursor + 3]), base, ed)


# ---------------------------------------------------------------------------------------------------- the registry
CASES = []          # (name, title, fn, parts)
GROUPS = {}         # case name -> (group, number): "old" = the 19 cases of T12 (numbered in order), "new" = step E's N1-N3, N5-N10, N12-N13


def case(name, title, parts=("-",), group="old", num=None):
    def deco(fn):
        CASES.append((name, title, fn, list(parts)))
        GROUPS[name] = (group, num or str(1 + sum(1 for g, _ in GROUPS.values() if g == group)))
        return fn
    return deco


# ===================================================================== 1 boot
@case("boot-console", "the cold start ends at the idle prompt: the banner on row 0, rows 1-22 blank, an empty edit line on row 23, "
                      "the cursor (FLASH, swapped colours) at row 23 column 0, the editor waiting for a key")
def boot_console(env, part):
    ck, m = Check(), env.m
    env.boot()
    v = view(m)
    ck.eq("row 0", v.rows[0], BANNER)
    ck.eq("rows 1-23", [r for r in v.rows[1:] if r], [])
    ck.eq("cursor cell", v.cursor, [(23, 0)])
    ck.eq("stray attributes", v.odd, [])
    cur_attr = m.read(0x5800 + 23 * 32, 1)[0]
    ck.eq("cursor attribute", cur_attr, 0xE0)
    ck.eq("row 23 bitmap", any(any(row_cell(m, 23, c)) for c in range(32)), False)
    ck.eq("edit line, cursor", env.edit_state(), ("", 0))
    ck.eq("in_editor", env.con.in_editor(), True)
    ck.eq("PRINT_ROW, PRINT_COL", env.print_pos(), (1, 0))
    ck.eq("wrap table", wrap_table(m), (1, [(0, 0)], 0))
    ck.eq("FWRAP_OLD_COUNT", env.u8("FWRAP_OLD_COUNT"), 1)
    ck.eq("GFX_MODE", env.u8("GFX_MODE"), 0)
    ck.eq(end_name(env), m.w16(env.S(end_name(env))), env.S("LOADTEXT_BUF"))
    ck.note("row 0 %r, rows 1-23 blank, cursor (23, 0) attribute $%02X, other attributes $%02X, PRINT_ROW 1, workspace empty" % (
        BANNER, cur_attr, m.S.get("ATTR_DEFAULT", 0x44)))
    return ck.result()


# ===================================================================== 2 charset
def _typeable(m):
    return [c for c in sorted(m.keys) if 32 <= c < 127]


@case("keys-charset", "every character Forth can type (its key map: letters, digits, space, SYMBOL SHIFT punctuation) pressed on "
                      "the keyboard matrix reaches the edit line and the screen, in batches of 30 on one row; the characters "
                      "it has no key for are exactly [ \\ ] ^ ` { | } ~", parts=("0", "1", "2"))
def keys_charset(env, part):
    ck, m = Check(), env.m
    chars = _typeable(m)
    ck.eq("typeable printable characters", len(chars), 86)
    ck.eq("untypeable printable characters", "".join(chr(c) for c in range(32, 127) if c not in m.keys), UNTYPEABLE)
    k = int(part)
    batch = "".join(chr(c) for c in chars[30 * k:30 * k + 30])
    base = env.boot()
    ed = Ed(32)
    for ch in batch:
        env.con.press(ch)
        ed.key(ord(ch))
    env.check_view(ck, "batch %d" % k, base, ed)
    ck.note("batch %d: %r" % (k, batch))
    return ck.result()


# ===================================================================== 3 editing keys on the matrix
@case("keys-editing-matrix", "CAPS SHIFT+5 / 8 move left / right, CAPS SHIFT+0 deletes, ENTER commits, all typed on the matrix; "
                             "CAPS SHIFT+6 / 7 / 1 and CAPS SHIFT+ENTER reach the latch as codes 2, 3, $0F, $0B and the editor "
                             "ignores them (current behaviour: nothing)")
def keys_editing_matrix(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    ed = Ed(32)
    for ch in "abc":
        env.con.press(ch)
        ed.key(ord(ch))
    env.check_view(ck, "abc", base, ed)
    for code, name in ((LEFT, "CAPS+5"), (LEFT, "CAPS+5")):
        env.press_ctrl(code)
        ed.key(code)
        ck.eq(name + " latch", m.read(env.S("KBD_LASTK"), 1)[0], code)
    env.check_view(ck, "two LEFT", base, ed)
    ck.eq("cursor", ed.cursor, 1)
    seen = {}
    for code, name in ((DOWN, "CAPS+6"), (UP, "CAPS+7"), (DELETE_LINE, "CAPS+1"), (INSERT_LINE, "CAPS+ENTER")):
        before = screen_sig(m)
        env.press_ctrl(code)
        seen[name] = m.read(env.S("KBD_LASTK"), 1)[0]
        ck.eq(name + " latch", seen[name], code)
        env.check_view(ck, name + " ignored", base, ed)
        ck.eq(name + " screen bytes", screen_sig(m) == before, True)
        ck.true(name + " editor waiting", env.con.in_editor())
    env.con.press("x")
    ed.key(ord("x"))
    env.check_view(ck, "insert x", base, ed)
    env.press_ctrl(RIGHT)
    ed.key(RIGHT)
    env.check_view(ck, "RIGHT", base, ed)
    env.press_ctrl(DELETE)
    ed.key(DELETE)
    env.check_view(ck, "DELETE", base, ed)
    ck.eq("line before ENTER", env.edit_state(), ("axc", 2))
    env.con.press("\r")
    ck.eq("ENTER: edit line, cursor", env.edit_state(), ("", 0))
    ck.eq("ENTER: rows", view(m).rows[:3], [BANNER, "AXC ?", ""])
    ck.true("in_editor after ENTER", env.con.in_editor())
    ck.note("matrix: LEFT LEFT insert RIGHT DELETE ENTER as the model; codes seen for CAPS+6/7/1/ENTER: %s, all ignored" %
            ", ".join("%s=%d" % kv for kv in seen.items()))
    return ck.result()


# ===================================================================== 4 BREAK at the prompt
@case("break-key-console", "BREAK (CAPS SHIFT+SPACE) at the prompt reaches the latch as code $10 and inserts nothing, with an empty "
                           "line and in the middle of a line; the screen is unchanged")
def break_key_console(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    ed = Ed(32)
    sig = screen_sig(m)
    env.press_ctrl(BREAK)
    ck.eq("latch", m.read(env.S("KBD_LASTK"), 1)[0], BREAK)
    ck.eq("screen bytes unchanged", screen_sig(m) == sig, True)
    env.check_view(ck, "empty line", base, ed)
    for ch in "abcd":
        env.con.press(ch)
        ed.key(ord(ch))
    for _ in range(2):
        env.press_ctrl(LEFT)
        ed.key(LEFT)
    sig = screen_sig(m)
    env.press_ctrl(BREAK)
    ck.eq("screen bytes unchanged in a line", screen_sig(m) == sig, True)
    env.check_view(ck, "mid-line", base, ed)
    env.con.press("z")
    ed.key(ord("z"))
    env.check_view(ck, "typing after", base, ed)
    ck.eq("line", ed.text, "abzcd")
    ck.true("editor waiting", env.con.in_editor())
    ck.note("BREAK latched as $10, ignored by EDITOR_PROCESS_KEY (code below 32), no redraw")
    return ck.result()


# ===================================================================== 5 left / right / insert
@case("left-right-insert", "typing inserts at the cursor after LEFT / RIGHT; RIGHT stops at the end of the line, LEFT at 0")
def left_right_insert(env, part):
    ck = Check()
    base = env.boot()
    ed = Ed(32)
    seq = ([ord(c) for c in "ace"] + [LEFT, LEFT, ord("b"), RIGHT, ord("d"), RIGHT, RIGHT, RIGHT, RIGHT, ord("f")]
           + [LEFT] * 10 + [ord("z"), LEFT, LEFT, RIGHT, ord("!")])
    for code in seq:
        step(env, ck, "lri", base, ed, code)
    ck.eq("final line, cursor", env.edit_state(), ("z!abcdef", 2))
    ck.note("ace <-<- b -> d ->->->-> f, <-x10 z <-<- -> !  gives %r, cursor %d; checked after every key" % (ed.text, ed.cursor))
    return ck.result()


# ===================================================================== 6 delete
@case("delete", "DELETE at column 0 does nothing; elsewhere it deletes the character left of the cursor, also in the middle and "
                "across a row boundary")
def delete(env, part):
    ck = Check()
    base = env.boot()
    ed = Ed(32)
    for code in [DELETE]:
        step(env, ck, "empty", base, ed, code)
    seq = [ord(c) for c in "abcdef"] + [DELETE] + [LEFT] * 3 + [DELETE, DELETE, DELETE, DELETE] + [RIGHT] * 3 + [DELETE] * 3
    for code in seq:
        step(env, ck, "del", base, ed, code)
    ck.eq("left empty", env.edit_state(), ("", 0))
    ed = Ed(32)
    env.boot()
    for ch in "abcdef":
        env.con.key(ord(ch))
        ed.key(ord(ch))
    for code in [LEFT, LEFT, LEFT, DELETE, DELETE]:
        step(env, ck, "mid", base, ed, code)
    ck.eq("mid-line result", env.edit_state(), ("adef", 1))
    ck.note("abcdef: DELETE x1, LEFT x3, DELETE x4 (the 4th at column 0 does nothing), RIGHT x3, DELETE x3: emptied; "
            "abcdef LEFT x3 DELETE x2 -> 'adef', cursor 1 (the second at column 0)")
    return ck.result()


# ===================================================================== 7 line full
def _words_text():
    return ("x" * 20 + " ") * 3 + "x" * 20 + " " + "y" * 11        # 95 characters, 4 rows with the last exactly full


def _refusal_candidate():
    """(cursor, char) of an insert in the middle of _words_text() the model refuses (a 5th row), found once with the model."""
    t = _words_text()
    for c in range(0, len(t) + 1):
        for ch in " Z":
            if wrap_model(t[:c] + ch + t[c:], 32)[1]:
                return c, ch
    return None


@case("line-full", "128 characters without spaces fit (hard breaks, 4 rows) and the cursor is shown: on a full last row it is at column 0 "
                   "of one more row (32, 64, 96 characters: the area is a row taller than the wrap) and on the last character's "
                   "cell (23, 31) at 128; the 129th is refused, line and screen unchanged; a word-wrapped line that would need a "
                   "5th row refuses the character that would (FWRAP_OVERFLOW stays set), also in the middle of the line",
      parts=("hard", "words", "middle"))
def line_full(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    ed = Ed(32)
    if part == "hard":
        rows_at = {31: 1, 32: 2, 33: 2, 63: 2, 64: 3, 65: 3, 95: 3, 96: 4, 97: 4, 127: 4, 128: 4}     # FWRAP_COUNT, cursor at the end
        for n in range(1, 129):
            env.con.key(ord("a"))
            ed.key(ord("a"))
            if n in rows_at:
                env.check_view(ck, "%d chars" % n, base, ed)
                ck.eq("rows used at %d" % n, wrap_table(m)[0], rows_at[n])
                ck.eq("model rows at %d" % n, ed.nrows(), rows_at[n])
        ck.eq("cursor cells at 128", view(m).cursor, [(23, 31)])
        sig = screen_sig(m)
        env.con.key(ord("b"))
        ed.key(ord("b"))
        ck.eq("129th: edit line", env.edit_state(), ("a" * 128, 128))
        ck.eq("129th: screen bytes", screen_sig(m) == sig, True)
        env.check_view(ck, "after the refusal", base, ed)
        step(env, ck, "LEFT", base, ed, LEFT)
        step(env, ck, "DELETE", base, ed, DELETE)
        step(env, ck, "type b", base, ed, ord("b"))
        env.con.key(ord("c"))
        ck.eq("128 again, c refused", env.edit_state(), ("a" * 126 + "ba", 127))
        ck.note("128 'a' fit in 4 hard-broken rows; at 32 / 64 / 96 characters the area is one row taller (cursor at column 0 of "
                "it), at 128 the cursor is on the last character's cell (23, 31); the 129th 'b' leaves the screen "
                "bytes unchanged; DELETE frees one place and 'b' goes in at the cursor")
    elif part == "words":
        type_keys(env, ed, _words_text())
        env.check_view(ck, "95 chars", base, ed)
        ck.eq("rows, overflow", wrap_table(m)[0::2], (4, 0))
        ck.eq("4th row full, no 5th row: cursor on its last cell", view(m).cursor, [(23, 31)])
        sig = screen_sig(m)
        env.con.key(ord("z"))
        ed.key(ord("z"))
        ck.eq("refused: edit line", env.edit_state(), (_words_text(), 95))
        ck.eq("refused: screen bytes", screen_sig(m) == sig, True)
        ck.eq("refused: FWRAP_OVERFLOW", env.u8("FWRAP_OVERFLOW"), 1)
        ck.eq("refused: FWRAP_COUNT", env.u8("FWRAP_COUNT"), 4)
        env.check_view(ck, "refused", base, ed)
        env.con.key(ord(" "))
        ed.key(ord(" "))
        ck.eq("a space is refused too", env.edit_state(), (_words_text(), 95))
        step(env, ck, "DELETE", base, ed, DELETE)
        ck.eq("overflow cleared by the redraw", env.u8("FWRAP_OVERFLOW"), 0)
        step(env, ck, "type z", base, ed, ord("z"))
        ck.note("3 words of 20 + the 4th and 11 more = 95 characters fill the 4th row (cursor on (23, 31), no 5th row); the 96th "
                "(z or space) needs a 5th row and is refused, FWRAP_OVERFLOW stays 1 and the screen is not redrawn until the "
                "next accepted key")
    else:
        t = _words_text()
        cand = _refusal_candidate()
        ck.true("the model finds a refused insert", cand is not None)
        type_keys(env, ed, t)
        for _ in range(len(t) - cand[0]):
            env.con.key(LEFT)
            ed.key(LEFT)
        env.check_view(ck, "cursor %d" % cand[0], base, ed)
        sig = screen_sig(m)
        env.con.key(ord(cand[1]))
        ed.key(ord(cand[1]))
        ck.eq("refused in the middle: edit line, cursor", env.edit_state(), (t, cand[0]))
        ck.eq("refused in the middle: screen bytes", screen_sig(m) == sig, True)
        ck.eq("refused in the middle: FWRAP_OVERFLOW", env.u8("FWRAP_OVERFLOW"), 1)
        env.check_view(ck, "after", base, ed)
        ck.note("insert of %r at offset %d of the 95-character line is refused (model and build agree)" % (cand[1], cand[0]))
    return ck.result()


# ===================================================================== 8 wrap model
def model_lines(w):
    """Lines for the wrap-model case (width w): words of assorted lengths, a word longer than a row, trailing and leading
    spaces, exactly w and w +- 1 characters, a space at offsets w-2, w-1, w and w+1, three short words per row, and 8
    seeded random sentences of 1-14 letter words.  (The caller drops the lines the room check would refuse.)"""
    a = lambda n: "a" * n      # noqa: E731
    out = ["hello world", "a bb ccc dddd eeeee ffffff ggggggg hhhhhhhh iiiiiiiii jjjjjjjjjj kkkkkkkkkkk",
           "the quick brown fox jumps over the lazy dog and keeps running far far away"]
    out += [a(w - 1), a(w), a(w + 1), a(2 * w - 1), a(2 * w)]
    out += [a(w - 1) + " b", a(w) + " b", a(w + 1) + " b", a(w - 2) + " " + a(5), a(w - 3) + " " + a(w - 3)]
    out += ["see " + a(w + 8) + " end", a(w + 8) + " tail", "x " + a(2 * w - 10), a(w + 20), a(w + 8) + " " + a(w + 8)]
    out += ["word" + " " * 5, a(w) + "   ", a(w - 1) + "   ", " " * (w + 8) + "x", " " * (w + 8), "foo  bar   baz    qux", " lead"]
    out += [("w" * (w // 2)) + " " + ("v" * (w // 2)) + " " + ("u" * (w // 2)) + " tail", GROW, GROW97]
    rnd = random.Random(2068 + w)
    for _ in range(8):
        words, n = [], 0
        target = rnd.randint(w, 110)
        while n < target:
            words.append("".join(rnd.choice("abcdefghijklmnopqrstuvwxyz") for _ in range(rnd.randint(1, 14))))
            n += len(words[-1]) + 1
        out.append(" ".join(words)[:128])
    return out


def walk_keys(w, n=130):
    """A seeded pseudo-random key sequence: mostly characters (letters and spaces so that words re-wrap), some LEFT /
    RIGHT / DELETE."""
    rnd = random.Random(1968 + w)
    alphabet = "abcdefghij klm nopq rstu vwxyz  "
    keys = []
    for _ in range(n):
        r = rnd.random()
        keys.append(rnd.choice([LEFT, LEFT, RIGHT, RIGHT, DELETE]) if r < 0.3 else ord(rnd.choice(alphabet)))
    return keys


@case("wrap-model", "the Python model of WRAP_CALC (word-boundary rule, 32 columns; the cursor on a full last row gets a row "
                    "of its own) predicts the wrap table, the screen rows and the cursor cell of every line of a set (assorted "
                    "words, a word longer than a row, trailing spaces, exactly 32 characters), and of a seeded random walk "
                    "of keys", parts=("lines32a", "lines32b", "walk32"))
def wrap_model_case(env, part):
    ck, m = Check(), env.m
    w = 32
    base = env.boot()
    if part.startswith("lines"):
        lines, shapes = [], []
        for line in model_lines(w):
            ed = Ed(w)
            ed.type(line)
            if ed.text == line:                  # (the room check, at the display width, refuses the lines that need a 5th row)
                lines.append(line)
        ck.true("lines the room check accepts", len(lines) >= 25, "only %d" % len(lines))
        lines = lines[0::2] if part.endswith("a") else lines[1::2]
        for line in lines:
            base = env.boot()
            ed = Ed(w)
            type_keys(env, ed, line)
            ck.eq("accepted line %r" % line[:24], env.edit_state()[0], line)
            env.check_view(ck, "line %r" % line[:30], base, ed)
            shapes.append(ed.nrows())
        ck.note("%d lines at %d columns, rows used (cursor at the end) %s; wrap table, rows and cursor cell equal the model" % (
            len(lines), w, " ".join(str(n) for n in shapes)))
    else:
        ed = Ed(w)
        keys = walk_keys(w)
        for code in keys:
            step(env, ck, "walk", base, ed, code)
        ck.note("%d seeded keys at %d columns, final line %r (%d chars, %d rows)" % (
            len(keys), w, ed.text[-30:], len(ed.text), ed.nrows()))
    return ck.result()


# ===================================================================== 9 grow / shrink
GS_TEXT = ("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega")


@case("wrap-grow-shrink", "the input area grows upward row by row as the line wraps (hard breaks and word wrap, 32 "
                          "columns), the rows above stay as they were, and deleting back clears the rows it no longer uses "
                          "(bitmap and attributes)", parts=("hard32", "words32"))
def wrap_grow_shrink(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    ed = Ed(32)
    text = "a" * 100 if part == "hard32" else GS_TEXT
    counts = []
    for ch in text:
        env.con.key(ord(ch))
        ed.key(ord(ch))
        env.check_view(ck, "grow %d" % len(ed.text), base, ed)
        counts.append(ed.nrows())
    ck.eq("growth steps", sorted(set(counts)), list(range(1, max(counts) + 1)))
    ck.eq("rows grow one at a time", [b - a for a, b in zip(counts, counts[1:]) if b != a and b - a != 1], [])
    ck.eq("PRINT_ROW untouched", env.print_pos(), (1, 0))
    shrink = []
    for _ in range(len(ed.text)):
        env.con.key(DELETE)
        ed.key(DELETE)
        env.check_view(ck, "shrink %d" % len(ed.text), base, ed)
        shrink.append(ed.nrows())
    ck.eq("empty again", env.edit_state(), ("", 0))
    ck.eq("rows 20-23 blank, banner intact", [r for r in view(m).rows[2:] if r], [])
    ck.note("%d chars, rows used 1..%d on the way up, back to 1 on the way down; every key checked against the model" % (
        len(text), max(counts)))
    return ck.result()


# ===================================================================== 10 scroll
@case("wrap-scroll", "with output on the rows just above the edit line, a line growing to 2-4 rows scrolls the whole screen up "
                     "(row 0, the banner, is lost) only when the row it claims is not blank, PRINT_ROW follows; shrinking "
                     "does not scroll back; the next output starts at PRINT_ROW",
      parts=("pr3-32", "pr20-32", "pr22-32"))
def wrap_scroll(env, part):
    ck, m = Check(), env.m
    start_pr = int(part.split("-")[0][2:])
    base = env.boot()
    for i in range(start_pr - 1):                              # PRINT_ROW starts at 1
        env.con.type("%d ." % i)
    pr = env.print_pos()[0]
    ck.eq("PRINT_ROW before", pr, start_pr)
    base = list(view(m).rows)
    ed = Ed(32)
    text = "a" * 97
    old, log = 1, []
    for ch in text:
        nxt = Ed(32, ed.text, ed.cursor)
        nxt.key(ord(ch))
        new = nxt.nrows()
        env.con.key(ord(ch))
        ed.key(ord(ch))
        if new > old:
            base, pr = grow_scroll(base, pr, old, new)
            log.append((len(ed.text), new, pr))
        old = max(old, new)
        env.check_view(ck, "grow %d" % len(ed.text), base, ed)
        ck.eq("PRINT_ROW at %d" % len(ed.text), env.print_pos()[0], pr)
    for _ in range(len(ed.text) - 1):
        env.con.key(DELETE)
        ed.key(DELETE)
        env.check_view(ck, "shrink %d" % len(ed.text), base, ed)
    ck.eq("PRINT_ROW after shrinking", env.print_pos()[0], pr)
    env.con.key(KEY_ENTER)
    base = list(base)
    base[pr] = "A ?"
    ck.eq("after ENTER: rows", view(m).rows[:pr + 2], base[:pr + 2])
    ck.eq("after ENTER: PRINT_ROW", env.print_pos()[0], pr + 1)
    ck.true("editor waiting", env.con.in_editor())
    ck.note("%s: PRINT_ROW %d at the start; growth steps (chars, rows, PRINT_ROW after; a scroll shows as PRINT_ROW falling): %s; the next output went to "
            "row %d" % (part, start_pr, log, pr))
    return ck.result()


# ===================================================================== 11 ENTER interprets
@case("enter-interprets", "`1 2 + .` shows `3 OK` on the first output row and a fresh empty edit line; an unknown word shows the word "
                          "(upper case) and ?, no OK, and the editor is intact; a stack error shows STACK?; the error state ends "
                          "with the next line")
def enter_interprets(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    con = env.con
    con.type("1 2 + .")
    v = view(m)
    ck.eq("rows 0-2", v.rows[:3], [BANNER, "3 OK", ""])
    ck.eq("edit line", env.edit_state(), ("", 0))
    ck.eq("cursor", v.cursor, [(23, 0)])
    ck.eq("PRINT_ROW", env.print_pos(), (2, 0))
    ck.eq("INTERP_ERROR_FLAG", env.u8("INTERP_ERROR_FLAG"), 0)
    ck.true("editor waiting", con.in_editor())
    con.type("foo")
    v = view(m)
    ck.eq("unknown word: rows 0-3", v.rows[:4], [BANNER, "3 OK", "FOO ?", ""])
    ck.eq("INTERP_ERROR_FLAG", env.u8("INTERP_ERROR_FLAG"), 1)
    ck.eq("no OK, edit line", env.edit_state(), ("", 0))
    ck.true("editor waiting", con.in_editor())
    ed = Ed(32)
    base = list(v.rows)
    type_keys(env, ed, "ab")
    env.check_view(ck, "typing after the error", base, ed)
    con.key(ENTER)
    con.type("drop")
    ck.eq("stack error: rows 0-5", view(m).rows[:6], [BANNER, "3 OK", "FOO ?", "AB ?", "STACK?", ""])
    con.type("1 .")
    ck.eq("error flag cleared by the next line", (env.u8("INTERP_ERROR_FLAG"), view(m).rows[5]), (0, "1 OK"))
    ck.note("`1 2 + .` -> '3 OK'; `foo` -> 'FOO ?' (no OK), `drop` -> 'STACK?'; typing and ENTER still work")
    return ck.result()


# ===================================================================== 12 workspace append
def ws_text(m):
    end = "STORE_END" if "STORE_END" in m.S else "WORKSPACE_END"
    n = m.w16(m.sym(end)) - m.sym("LOADTEXT_BUF")
    return m.read(m.sym("LOADTEXT_BUF"), n).decode("latin-1")


@case("workspace-append", "each committed line (an error line included, an empty line not) is appended to the store at LOADTEXT_BUF "
                          "as its text and one CR; STORE_END follows; the bytes beyond stay zero; a line of 128 characters is "
                          "appended whole; the room test is exact: a line whose text and CR end exactly at $F000 is appended, one "
                          "byte more is refused with STORE FULL on its own row (the line still runs) and nothing at or above $F000 "
                          "changes (EDITOR_SPEC E1, E5, section 3)", parts=("append", "limit"))
def workspace_append(env, part):
    ck, m = Check(), env.m
    buf = env.S("LOADTEXT_BUF")
    ck.eq("LOADTEXT_BUF", buf, LOADTEXT_BUF)
    env.boot()
    con = env.con
    if part == "append":
        model = ""
        for line in ["1 2 + .", "5 6 *", "", "foo", "DROP", "7 ."]:
            con.type(line)
            if line:
                model = model + line + "\r"
            ck.eq("store after %r" % line, ws_text(m), model)
            ck.eq("%s after %r" % (end_name(env), line), store_end(env), buf + len(model))
        ck.eq("zero beyond", m.read(buf + len(model), 32), bytes(32))
        long = ("a" * 7 + " ") * 16
        con.type(long)
        model = model + long + "\r"
        ck.eq("128-character line appended whole", ws_text(m), model)
        ck.note("store %r, 128-char line appended whole (store %d bytes); an empty line appends nothing" % (model[:44], len(model)))
    else:
        pat = seed_above_limit(env)
        end = buf + 8192 - 16
        m.poke16(env.S(end_name(env)), end)
        con.type("1 2 + . 3 DROP ")                                     # 15 characters + CR = 16 bytes: fits exactly
        ck.eq("15-char line at 16 bytes from the end: %s" % end_name(env), store_end(env), STORE_LIMIT)
        ck.eq("the line and its CR from the old end", m.read(end, 16), b"1 2 + . 3 DROP \r")
        ck.eq("no STORE FULL", count_row(env, "STORE FULL"), 0)
        env.boot()
        pat = seed_above_limit(env)
        m.poke16(env.S(end_name(env)), end)
        con.type("1 2 + .  3 DROP ")                                    # 16 characters + CR = 17 bytes: one too many
        ck.eq("16-char line at 16 bytes from the end: %s unchanged" % end_name(env), store_end(env), end)
        ck.eq("STORE FULL on its own row", count_row(env, "STORE FULL"), 1)
        ck.true("the refused line still ran (3 on the screen)", "3" in digits(out_rows(env)), str(out_rows(env)[-3:]))
        ck.eq("bytes from the end still zero", m.read(end, 16), bytes(16))
        eq_bytes(ck, "$F000-$F0FF untouched", read_above_limit(env), pat)
        ck.note("a line ending exactly at $F000 is appended; one byte more is refused with STORE FULL and still runs")
    return ck.result()


# ===================================================================== 13 recall (retired)
@case("recall", "RECALL is retired (E6): `0 RECALL` answers `RECALL ?` and leaves the edit line empty; LIST-DEFS still lists the "
                "definitions; `EDIT SQ` fixes the definition in place (one copy in the store, the EDIT line not kept), the "
                "commit redefines SQ, and LIST-DEFS then shows the edited text")
def recall(env, part):
    ck, m = Check(), env.m
    env.boot()
    con = env.con
    con.type(": SQ DUP * ;")
    con.type("3 SQ .")
    ck.eq("old SQ: 3 SQ .", view(m).rows[:4], [BANNER, "OK", "9 OK", ""])
    con.type("0 RECALL")
    ck.eq("0 RECALL: an unknown word", view(m).rows[3], "RECALL ?")
    ck.eq("0 RECALL: edit line", env.edit_state(), ("", 0))
    con.type("LIST-DEFS")
    ck.eq("LIST-DEFS", view(m).rows[4:6], ["0: : SQ DUP * ;", "OK"])
    for ch in "EDIT SQ":
        con.key(ord(ch), maxi=VIEW_MAXI)
    con.key(KEY_ENTER, maxi=VIEW_MAXI * 3)
    ck.eq("the view is open on line 1", m.screen_rows()[SCREEN_ROWS], "LINE 1/4")
    for code in [RIGHT] * 10 + [ord(c) for c in " DUP *"]:
        con.key(code, maxi=VIEW_MAXI)
    con.key(BREAK, maxi=VIEW_MAXI * 3)
    ck.eq("store after the session", ws_text(m), ": SQ DUP * DUP * ;\r3 SQ .\r0 RECALL\rLIST-DEFS\r")
    con.type("3 SQ .")
    con.type("LIST-DEFS")
    rows = [r for r in view(m).rows if r]
    ck.true("new SQ: 81", "81 OK" in rows, str(rows))
    ck.true("LIST-DEFS: one definition, edited", "0: : SQ DUP * DUP * ;" in rows and not any(r.startswith("1:") for r in rows),
            str(rows))
    ck.note("0 RECALL -> 'RECALL ?'; EDIT SQ, ' DUP *' inserted, BREAK: SQ redefined in place (3 SQ . gives 81), one copy listed")
    return ck.result()


# ===================================================================== 14 no 64 columns
@case("no-64col", "the 64-column mode was removed in step M6: `64COL` is an unknown word (the console answers `64COL ?`, no OK), "
                  "the screen stays 32 columns (GFX_MODE 0, the editor and its cursor as before, typing wraps at 32) and "
                  "`32COL`, `PALETTE64` and `PLOT64` are unknown too",
      parts=("64col", "others"))
def no_64col(env, part):
    ck, m = Check(), env.m
    con = env.con
    con.boot()
    ck.eq("GFX_MODE before", env.u8("GFX_MODE"), 0)
    words = ["64COL"] if part == "64col" else ["32COL", "PALETTE64", "PLOT64"]
    rows = [BANNER]
    for w in words:
        con.type(w)
        rows.append("%s ?" % w)              # the console prints an unknown word in upper case, then ` ?` and no OK
        ck.eq("%s: GFX_MODE" % w, env.u8("GFX_MODE"), 0)
        ck.eq("%s: rows" % w, view(m).rows[:len(rows) + 1], rows + [""])
        ck.eq("%s: INTERP_ERROR_FLAG" % w, env.u8("INTERP_ERROR_FLAG"), 1)
        ck.eq("%s: edit line" % w, env.edit_state(), ("", 0))
        ck.true("%s: editor waiting" % w, con.in_editor())
    v = view(m)
    ck.eq("cursor at row 23 column 0", v.cursor, [(23, 0)])
    ck.eq("stray attributes", v.odd, [])
    ed = Ed(32)
    type_keys(env, ed, "x" * 40, ck, "32 columns", rows + [""] * (24 - len(rows)))
    ck.note("%s: answered '%s ?' (no OK), GFX_MODE 0, the screen and the editor still 32 columns" % (
        ", ".join(words), words[-1]))
    return ck.result()


# ===================================================================== 15 scroll output
@case("scroll-output", "enough output lines to scroll: the edit line stays on row 23 (cursor at column 0), row 22 stays blank, the "
                       "banner scrolls away and the last 22 lines are on rows 0-21")
def scroll_output(env, part):
    ck, m = Check(), env.m
    env.boot()
    con = env.con
    n = 30
    rows_at = {}
    for i in range(n):
        con.type("%d ." % i)
        if i in (19, 20, 21, 22):
            rows_at[i] = (env.print_pos()[0], view(m).rows[:2])
    v = view(m)
    ck.eq("rows 0-21", v.rows[:22], ["%d OK" % (n - 22 + i) for i in range(22)])
    ck.eq("rows 22, 23", v.rows[22:], ["", ""])
    ck.eq("cursor", v.cursor, [(23, 0)])
    ck.eq("PRINT_ROW", env.print_pos(), (22, 0))
    ck.eq("banner gone", BANNER in v.rows, False)
    ck.eq("PRINT_ROW and rows 0-1 after 20..23 lines", rows_at,
          {19: (21, [BANNER, "0 OK"]), 20: (22, [BANNER, "0 OK"]), 21: (22, ["0 OK", "1 OK"]), 22: (22, ["1 OK", "2 OK"])})
    ck.true("editor waiting", con.in_editor())
    ck.note("%d lines: rows 0-21 = '%d OK'..'%d OK', PRINT_ROW 22 (the last output row is 21); the banner is lost with the 22nd "
            "line" % (n, n - 22, n - 1))
    return ck.result()


# ===================================================================== 16 BREAK while running
def _go(env, text):
    """Type `text`, then ENTER through the latch without waiting for the next key wait."""
    m = env.m
    for ch in text:
        env.con.key(ord(ch))
    m.write(env.S("KBD_LASTK"), ENTER)
    m.write(env.S("KBD_KEYHIT"), 0xFF)
    m.cmd("cpu-step")


def _hold_break(m, on):
    for e in ((Z_CAPS, Z_SPACE) if on else (Z_SPACE, Z_CAPS)):
        m.cmd("send-keys-event %d %d" % (e, 1 if on else 0))


@case("break-running", "a running loop `: L BEGIN 0 UNTIL ; L` is NOT stopped by BREAK held on the matrix (the interpreter never "
                       "polls it: the ISR latches $10 and nothing reads it); a loop that polls `BREAK?` ends and returns to the "
                       "prompt with OK; the editor is intact afterwards", parts=("plain", "polled"))
def break_running(env, part):
    ck, m = Check(), env.m
    S = env.S
    env.boot()
    con = env.con
    if part == "plain":
        con.type(": L BEGIN 0 UNTIL ;")
        _go(env, "L")
        pc = m.run_to([S("IO_READ_KEY")], 1_500_000)
        ck.true("the loop runs", pc != S("IO_READ_KEY"), "PC=%04X" % pc)
        _hold_break(m, True)
        try:
            pc = m.run_to([S("IO_READ_KEY")], 3_000_000)
            latch = (m.read(S("KBD_LASTK"), 1)[0], m.read(S("KBD_KEYHIT"), 1)[0])
        finally:
            _hold_break(m, False)
        ck.true("BREAK held for 3M instructions: still looping", pc != S("IO_READ_KEY"), "PC=%04X" % pc)
        ck.eq("ISR latch (KBD_LASTK, KBD_KEYHIT)", latch, (BREAK, 0xFF))
        pc = m.run_to([S("IO_READ_KEY")], 2_000_000)
        ck.true("BREAK released: still looping", pc != S("IO_READ_KEY"), "PC=%04X" % pc)
        ck.eq("screen: the typed L is still on row 23", view(m).rows[:2] + view(m).rows[23:], [BANNER, "OK", "L"])
        ck.note("the loop was never broken: Forth has no BREAK check in the interpreter (only the word BREAK?); the key stays "
                "latched (KBD_LASTK $10, KBD_KEYHIT $FF) and would reach the editor after a loop that ends")
    else:
        con.type(": L BEGIN BREAK? UNTIL ;")
        _go(env, "L")
        pc = m.run_to([S("IO_READ_KEY")], 1_500_000)
        ck.true("the loop runs until BREAK", pc != S("IO_READ_KEY"), "PC=%04X" % pc)
        _hold_break(m, True)
        try:
            pc = m.run_to([S("IO_READ_KEY")], 3_000_000)
        finally:
            _hold_break(m, False)
        ck.eq("BREAK? ends the loop: back at the key wait", pc, S("IO_READ_KEY"))
        con.wait()
        ck.eq("rows 0-3", view(m).rows[:4], [BANNER, "OK", "OK", ""])
        ck.true("editor waiting", con.in_editor())
        ck.eq("edit line", env.edit_state(), ("", 0))
        # the BREAK key was latched meanwhile; the editor ignores it
        ed = Ed(32)
        env.con.key(ord("a"))
        ed.key(ord("a"))
        env.check_view(ck, "typing after", [BANNER, "OK", "OK"] + [""] * 21, ed)
        ck.note("`BEGIN BREAK? UNTIL` returns to the prompt with 'OK' (no error message) once BREAK is held")
    return ck.result()


# ===================================================================== 17 colour state
@case("colour-state", "after `2 INK 6 PAPER 1 BORDER`: CURRENT_ATTR is $72 and output (OK) is drawn in it, the border shadow is 1, "
                      "but the editor draws the edit line and its blank cells in ATTR_DEFAULT $44 (cursor $E0) and the next typed "
                      "line still shows")
def colour_state(env, part):
    ck, m = Check(), env.m
    env.boot()
    con = env.con
    ck.eq("CURRENT_ATTR before", env.u8("CURRENT_ATTR"), 0x44)
    con.type("2 INK 6 PAPER 1 BORDER")
    ck.eq("CURRENT_ATTR", env.u8("CURRENT_ATTR"), 0x72)
    ck.eq("border (PORT_FE_SHADOW & 7)", env.u8("PORT_FE_SHADOW") & 7, 1)
    attrs = m.read(0x5800, 768)
    ck.eq("OK on row 1 (cells 0-1) and the rest of row 1", (list(attrs[32:34]), set(attrs[34:64])), ([0x72, 0x72], {0x44}))
    ck.eq("edit row 23 after the command", (attrs[23 * 32], set(attrs[23 * 32 + 1:])), (0xE0, {0x44}))
    ck.eq("banner row attributes", set(attrs[:32]), {0x44})
    ed = Ed(32)
    base = view(m).rows
    type_keys(env, ed, "abc")
    attrs = m.read(0x5800, 768)
    ck.eq("edit row attributes with 'abc'", list(attrs[23 * 32:23 * 32 + 32]), [0x44, 0x44, 0x44, 0xE0] + [0x44] * 28)
    ck.eq("the line shows", view(m).rows[23], "abc")
    con.key(ENTER)
    con.type("1 .")
    attrs = m.read(0x5800, 768)
    ck.eq("rows", view(m).rows[:4], [BANNER, "OK", "ABC ?", "1 OK"])
    ck.eq("output attributes: 'ABC ?' (5 cells), '1 OK' (4 cells)", (list(attrs[64:70]), list(attrs[96:101])),
          ([0x72] * 5 + [0x44], [0x72] * 4 + [0x44]))
    ck.eq("border still", env.u8("PORT_FE_SHADOW") & 7, 1)
    ck.note("INK/PAPER change CURRENT_ATTR ($44 -> $72) which output (OK, error text) uses; the editor ignores it "
            "(ATTR_DEFAULT $44, cursor $E0); the border is port $FE bits 0-2 = 1 (shadow)")
    return ck.result()


# ===================================================================== 18 redraw oracle
def blank_rows(m, r0, r1):
    """Rows r0..r1-1 blanked directly: all pixel lines zero and the attributes ATTR_DEFAULT."""
    for r in range(r0, r1):
        y0 = r * 8
        base = 0x4000 + (((y0 & 0xC0) << 5) | ((y0 & 0x38) << 2))
        for k in range(8):
            m.write(base + 0x100 * k, bytes(32))
        m.write(0x5800 + r * 32, bytes([m.S.get("ATTR_DEFAULT", 0x44)]) * 32)


def full_reference(m):
    """The screen a full redraw draws from the current editor state (header, THE FULL REDRAW); the machine is put back
    exactly as it was.  Returns the bytes of read_screen."""
    S = m.sym
    cp = m.checkpoint("oracle")
    try:
        r = m.call("WRAP_CALC")
        if not r["ok"]:
            raise RuntimeError("WRAP_CALC did not return (PC=%04X)" % r["pc"])
        m.write(S("FWRAP_OLD_COUNT"), m.read(S("FWRAP_COUNT"), 1))
        blank_rows(m, 24 - MAX_ROWS, 24)
        r = m.call("EDITOR_REDRAW")
        if not r["ok"]:
            raise RuntimeError("EDITOR_REDRAW did not return (PC=%04X)" % r["pc"])
        return read_screen(m)
    finally:
        m.rollback(cp)


def oracle_scenarios():
    k = lambda s: [ord(c) for c in s]            # noqa: E731
    return {
        "short32": (32, k("hello world") + [DELETE] * 3 + [LEFT] * 2 + [RIGHT, RIGHT, RIGHT] + k("!"), []),
        "middle32": (32, k("abcdef ghi") + [LEFT] * 6 + k("XYZ ") + [DELETE] * 2 + [RIGHT] * 3 + k("!"), []),
        "wrap4-grow32": (32, k(GROW), []),
        "wrap4-shrink32": (32, [DELETE] * 100, k(GROW)),
        "boundary32": (32, [LEFT] * 14 + [LEFT, LEFT, LEFT] + [RIGHT] * 4 + [LEFT] * 12 + [DELETE, DELETE] + [RIGHT] * 6
                       + [ord("c")] + [LEFT] * 20 + [DELETE] + [RIGHT] * 4, k("a" * 28 + " " + "b" * 12 + "d" * 31)),
    }


@case("redraw-oracle", "after EVERY key of the scenarios (a short line; typing into the middle; a line wrapping to 4 rows and back; "
                       "DELETE, LEFT and RIGHT across a wrap boundary) the whole screen (bitmap and "
                       "attributes, 6912 bytes) equals the screen a full redraw draws from the "
                       "same editor state; and the oracle sees a stray pixel and a stray FLASH attribute",
      parts=list(oracle_scenarios()) + ["control"])
def redraw_oracle(env, part):
    ck, m = Check(), env.m
    if part == "control":
        env.boot()
        env.con.type("1 2 + .")
        for ch in "ab":
            env.con.key(ord(ch))
        now, ref = read_screen(m), full_reference(m)
        ck.eq("clean screen equals its reference", first_diff(now, ref), None)
        stray = bytearray(now)
        stray[0x0000 + ((21 * 8 & 0xC0) << 5) + ((21 * 8 & 0x38) << 2) + 0x100 * 3 + 5] ^= 0x10     # row 21, line 3, col 5
        ck.true("a stray pixel byte in row 21 is a difference", first_diff(bytes(stray), ref) is not None)
        stray = bytearray(now)
        stray[0x1800 + 22 * 32 + 7] |= 0x80
        ck.true("a stray FLASH attribute in row 22 is a difference", first_diff(bytes(stray), ref) is not None)
        stray = bytearray(now)
        stray[0x1800 + 23 * 32 + 2] = 0x44
        ck.true("a missing cursor is a difference", first_diff(bytes(stray), ref) is not None)
        ck.note("control: the reference of a clean screen matches; a stray pixel, a stray FLASH cell and a missing cursor each differ")
        return ck.result()
    w, keys, setup = oracle_scenarios()[part]
    env.boot()
    env.con.type("1 2 + .")
    for code in setup:
        env.con.key(code)
    ed = Ed(w)
    for code in setup + keys:
        ed.key(code)
    n, bad = 0, []
    for code in keys:
        env.con.key(code)
        n += 1
        now, ref = read_screen(m), full_reference(m)
        d = first_diff(now, ref)
        if d:
            bad.append("key %d (code %d): %s" % (n, code, d))
    ck.eq("the scenario ends as the model says", env.edit_state(), (ed.text, ed.cursor))
    ck.true("%d keys: screen equals the full redraw after every key" % n, not bad, "; ".join(bad[:3]) + (" (+%d)" % (len(bad) - 3) if len(bad) > 3 else ""))
    ck.note("%s: %d keys, %d bytes compared after each, all equal the full redraw" % (part, n, len(now)))
    return ck.result()


# ===================================================================== 19 typing cost
COST_CASES = [("key-end-short", "a key at the end of a short line"), ("key-mid-100", "a key in the middle of a 100-character line"),
              ("key-3row", "a key at the end of a 3-row wrapped line"), ("delete", "DELETE at the end of a short line"),
              ("left", "LEFT in the middle of a short line"), ("enter", "ENTER on `1 2 + .`")]


def cost_once(env, which):
    """T-states from the latch write to the next key wait for one key, after its setup."""
    m, con = env.m, env.con
    env.boot()
    if which == "key-end-short":
        for ch in "hello":
            con.key(ord(ch))
        key = ord("x")
    elif which == "key-mid-100":
        for ch in GROW:
            con.key(ord(ch))
        for _ in range(50):
            con.key(LEFT)
        key = ord("x")
    elif which == "key-3row":
        for ch in "a" * 70:
            con.key(ord(ch))
        key = ord("x")
    elif which == "delete":
        for ch in "hello":
            con.key(ord(ch))
        key = DELETE
    elif which == "left":
        for ch in "hello world":
            con.key(ord(ch))
        for _ in range(4):
            con.key(LEFT)
        key = LEFT
    else:
        for ch in "1 2 + .":
            con.key(ord(ch))
        key = ENTER
    m.tstates_reset()
    con.key(key)
    return m.tstates()


@case("typing-cost", "T-states from key delivery (latch write) to the next key wait, interrupts included, for a key at the end of a "
                     "short line, in the middle of a 100-character line, on a 3-row wrapped line, DELETE, LEFT and ENTER on "
                     "`1 2 + .`; each figure taken twice and equal; the baseline, no threshold",
      parts=("32",))
def typing_cost(env, part):
    ck = Check()
    w = int(part)
    table = {}
    for which, what in COST_CASES:
        a = cost_once(env, which)
        b = cost_once(env, which)
        table[which] = [a, b]
        ck.eq("%s repeatable" % which, a, b)
    env.boot()
    env.m.tstates_reset()
    env.m.call("KBD_ISR_TICK")
    isr = env.m.tstates()
    ck.data = {"columns": w, "t_states": table, "what": dict(COST_CASES), "isr_tstates": isr}
    ck.note("%d columns: %s (one KBD_ISR_TICK call with no key down: %d T)" % (
        w, ", ".join("%s %d" % (k, v[0]) for k, v in table.items()), isr))
    return ck.result()


# ====================================================================================================================
# STEP E: THE NEW CASES (group "new", EDITOR_SPEC.md section 8, second table, N1-N3, N5-N10 and N12-N13; N4 is in tapetest.py)
# ====================================================================================================================
# Written from the spec before the ROM code exists: they FAIL on the old build, each with the detail of the first thing
# that differs.  Where the spec leaves a detail open the strictest reading its text supports is asserted and a comment
# "READING:" says which; where the text allows several outcomes the case accepts exactly those and reports which one the
# build chose (a note), so the choice is visible and can be turned into a rule.
STORE_LIMIT = 0xF000                    # STORE_LIMIT: the store never writes at or above it (spec section 3)
STORE_CAP = STORE_LIMIT - LOADTEXT_BUF  # 8,192 bytes
DICT_CEIL = 0xD000                      # the new DICT_RAM_CEILING (E2a).  The contract is relative to this value, whatever
GUARD = 256                             # symbol the build under test has (the old build's DICT_RAM_CEILING is $F000)
CR, CRM = 0x0D, 0x8D                    # a line's terminator, and the session mark (CR with bit 7 set)
STATUS_RE = re.compile(r"^LINE (\d+)/(\d+)")        # the view's status row (row 23)
VIEW_MAXI = 10_000_000                  # instructions a key in the view may take before the harness calls it a hang
SCREEN_ROWS = 23                        # rows 0-22 show lines, row 23 is the status row


class ViewFail(Exception):
    """The view (or the machine) did not behave: the part stops here and fails with this detail."""


class ModelAmbiguous(Exception):
    """A test sequence reached a state the spec leaves open (or a line needing a 5th row): a bug in the test sequence,
    found by `edtest.py --selftest` before the ROM exists."""


def guarded(fn):
    """fn(env, part, ck): a ViewFail ends the part as a failure with its detail; so does a machine that stops answering."""
    @functools.wraps(fn)
    def run(env, part):
        ck = Check()
        try:
            fn(env, part, ck)
        except ViewFail as e:
            ck.true("view", False, str(e))
        except RuntimeError as e:
            ck.true("machine", False, "%s" % e)
        except ModelAmbiguous as e:
            ck.true("TEST BUG", False, "%s" % e)
        return ck.result()
    return run


def new_case(name, num, title, parts=("-",)):
    return case(name, title, parts, group="new", num=num)


# ---------------------------------------------------------------------------------------------------- store access
def end_name(env):
    """The store's end cell: STORE_END on the new build, WORKSPACE_END on the old one."""
    return "STORE_END" if "STORE_END" in env.m.S else "WORKSPACE_END"


def store_end(env):
    return env.m.w16(env.S(end_name(env)))


def store_read(env):
    """The store's bytes: STORE_START (LOADTEXT_BUF) up to the end cell."""
    end = store_end(env)
    n = end - env.S("LOADTEXT_BUF")
    if not 0 <= n <= STORE_CAP + 512:
        raise ViewFail("%s = $%04X is not inside the store" % (end_name(env), end))
    return env.m.read(env.S("LOADTEXT_BUF"), n) if n else b""


def store_set(env, data):
    """Put `data` into the store and set the end cell (the store as a loaded text would leave it)."""
    buf = env.S("LOADTEXT_BUF")
    if data:
        env.m.write(buf, data)
    env.m.poke16(env.S(end_name(env)), buf + len(data))


def store_bytes(texts, marked=()):
    """CR-ended lines (marked ones end with $8D)."""
    return b"".join(t.encode("latin-1") + bytes([CRM if i in marked else CR]) for i, t in enumerate(texts))


def digits(rows):
    return re.findall(r"-?\d+", " ".join(rows[:SCREEN_ROWS]))


def out_rows(env):
    """The non-blank output rows (rows 0-22)."""
    return [r for r in env.m.screen_rows()[:SCREEN_ROWS] if r]


def last_out_row(env):
    """The row the last console line printed its result on (PRINT_ROW is the next output row)."""
    pr = env.print_pos()[0]
    return env.m.screen_rows()[pr - 1] if pr >= 1 else ""


def count_row(env, text):
    return sum(1 for r in out_rows(env) if r == text)


def seed_above_limit(env):
    """A pattern in $F000-$F0FF (nothing lives there today; EDITOR_SPEC section 1): the case that must not touch it."""
    pat = bytes((0xA5 ^ (i * 7)) & 0xFF for i in range(256))
    env.m.write(STORE_LIMIT, pat)
    return pat


def read_above_limit(env):
    return env.m.read(STORE_LIMIT, 256)


def eq_bytes(ck, label, got, want):
    """ck.eq for byte strings that may be kilobytes long: the first difference only."""
    if got == want:
        return True
    n = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), min(len(got), len(want)))
    ck.true(label, False, "differs at byte %d (got %d bytes, want %d): got %s, want %s" % (n, len(got), len(want), got[n:n + 14], want[n:n + 14]))
    return False


def typed_line_variants(before, cmd):
    """The store a refused or otherwise harmless console command may leave: unchanged, or with the typed line appended as
    a line (E5: the console appends every committed line; whether `EDIT ...` itself is appended is not specified, so both
    are accepted)."""
    return [before, before + cmd.encode("latin-1") + bytes([CR])]


def tape_load(env, data, name="CRTXT", maxi=250_000_000, seed=False, pre=()):
    """LOAD-TEXT of a text tape holding `data` (tapes.text_file) on the machine `env`: realtape-open resets the machine
    and plays at once (tools/tapetest.py header), so the tape starts with a 4 s pause; boot and typing take about 1 s of
    emulated time.  Returns the seed pattern (written once the prompt is back) when seed=True."""
    m, con = env.m, env.con
    d = tempfile.mkdtemp(prefix="edtest-tape-")
    # ZEsarUX converts the tape to /tmp/zesarux-UID/tmp_<basename>.rwa, one name for every emulator that opens a file of
    # that name: parallel workers must open files with different names
    base = "edtest_%d_%s.tzx" % (os.getpid(), os.path.basename(d))
    try:
        path = os.path.join(d, base)
        with open(path, "wb") as f:
            f.write(tapes.tzx(tapes.text_file(name, data), lead_ms=4000))
        con.boot()
        m.cmd("realtape-open " + path)
        pc = m.run_to([m.sym("IO_READ_KEY")], 60_000_000)
        if pc != m.sym("IO_READ_KEY"):
            raise ViewFail("no prompt after realtape-open (PC=%04X)" % pc)
        con.caller = m.w16(m.regs()["SP"])
        pat = seed_above_limit(env) if seed else None
        for line in pre:                            # lines typed before the load (0.2 s of emulated time each)
            con.type(line)
        con.type("LOAD-TEXT " + name, enter=False)
        con.key(KEY_ENTER, maxi=maxi)
        return pat
    finally:
        shutil.rmtree(d, ignore_errors=True)
        try:
            os.remove("/tmp/zesarux-%d/tmp_%s.rwa" % (os.getuid(), base))
        except OSError:
            pass


# ---------------------------------------------------------------------------------------------------- the view's model
def wrows(text):
    """The console's word-wrap rows of a line (spec section 5: one rule); a line needing a 5th row is a test bug."""
    rows, overflow = wrap_model(text, 32)
    if overflow:
        raise ModelAmbiguous("line %r needs a 5th row" % text[:40])
    return rows


def row_index(rows, cursor):
    """(row index, column) of an offset in a line's rows (EDIT_CURSOR_TO_ROWCOL, as cursor_model)."""
    i = 0
    while i != len(rows) - 1 and cursor >= rows[i + 1][0]:
        i += 1
    return i, cursor - rows[i][0]


def row_texts(text):
    return [text[s:s + ln].rstrip(" ") for s, ln in wrows(text)]


KEYNAME = {LEFT: "LEFT", RIGHT: "RIGHT", UP: "UP", DOWN: "DOWN", DELETE: "DELETE", ENTER: "ENTER",
           INSERT_LINE: "insert-line", DELETE_LINE: "delete-line", BREAK: "BREAK"}


def keyname(code):
    return KEYNAME.get(code, repr(chr(code)) if 32 <= code < 127 else "code %d" % code)


def K(*parts):
    """A key sequence: a str is typed, an int is a key code, (code, n) repeats it n times."""
    out = []
    for p in parts:
        if isinstance(p, str):
            out += [ord(c) for c in p]
        elif isinstance(p, tuple):
            out += [p[0]] * p[1]
        else:
            out.append(p)
    return out


class VModel:
    """The view as the spec defines it (sections 3 and 5): store lines (text, marked), the cursor line copied into a buffer
    (EDIT_BUF: edited by the console's engine, written back only when the line is left), the cursor offset in it.

    READING: the store changes only when a line is left (UP/DOWN/ENTER/insert-line/BREAK write the line back if it changed
    and mark it), when a line is inserted (ENTER, insert-line: a marked empty line) or deleted (delete-line, DELETE on an
    empty line); characters, LEFT, RIGHT and DELETE inside a line change the buffer only.
    A step returns the possible outcomes (a fork per choice the text leaves open):
      * delete-line, DELETE on an empty line: the cursor goes to the line that took the deleted one's place (the new
        last line if it was the last): its column is not specified (0 or the end); DELETE on an empty line may also go
        to the end of the previous line;
      * a line edited back to its old text, or an edit that touches the line without changing it, is `ambiguous`
        (does `changed` mean different bytes or touched?): the test sequences never do it.
    UP/DOWN: to the previous/next screen row of a wrapped line, at the same column or the row's end if shorter (the
    cursor's current column, not a remembered one); past the first/last row to the previous/next line (the last row /
    the first row of it), same rule.  A wrapped line entered by DOWN whose first row is shorter than the column is
    ambiguous (row end or line end?): not used.  `cap`: the store's size limit in bytes (None: no limit): a write that
    would pass it is refused, nothing changes, msg = "STORE FULL" until the next key."""

    def __init__(self, texts, cur=0, col=0, marked=(), cap=None):
        self.lines = [[t, i in marked] for i, t in enumerate(texts)]
        self.cur, self.col = cur, col
        self.buf = texts[cur] if texts else ""
        self.touched = False
        self.top = 0
        self.exited = False
        self.msg = None
        self.cap = cap

    def clone(self):
        return copy.deepcopy(self)

    # ---- what the machine must show
    def n(self):
        return len(self.lines)

    def shown(self):
        return [self.buf if i == self.cur else t for i, (t, _) in enumerate(self.lines)]

    def store_bytes(self):
        return b"".join(t.encode("latin-1") + bytes([CRM if (mk and not self.exited) else CR]) for t, mk in self.lines)

    def store_len(self):
        return sum(len(t) + 1 for t, _ in self.lines)

    # ---- the keys
    def step(self, code):
        m = self.clone()
        m.msg = None
        return m._step(code)

    def _fits(self, delta):
        if self.cap is not None and delta > 0 and self.store_len() + delta > self.cap:
            self.msg = "STORE FULL"
            return False
        return True

    def _leave(self, extra=0):
        """Write the cursor line back if it changed (marking it); False if the store has no room (nothing changed)."""
        t, _ = self.lines[self.cur]
        changed = self.buf != t
        if not changed and self.touched:
            raise ModelAmbiguous("a line edited back to its old text (changed or touched?): %r" % t[:30])
        if not self._fits((len(self.buf) - len(t) if changed else 0) + extra):
            return False
        if changed:
            self.lines[self.cur] = [self.buf, True]
        self.touched = False
        return True

    def _goto(self, idx, col):
        self.cur, self.buf, self.col, self.touched = idx, self.lines[idx][0], col, False

    def _after_delete(self, idx, prev_end):
        del self.lines[idx]
        if not self.lines:
            raise ModelAmbiguous("the only line deleted")
        cands = []
        if idx < len(self.lines):
            cands = [(idx, 0), (idx, len(self.lines[idx][0]))]
        else:
            cands = [(idx - 1, 0), (idx - 1, len(self.lines[idx - 1][0]))]
        if prev_end and 0 < idx < len(self.lines):
            cands.append((idx - 1, len(self.lines[idx - 1][0])))
        outs, seen = [], set()
        for c, col in cands:
            if (c, col) in seen:
                continue
            seen.add((c, col))
            f = self.clone()
            f._goto(c, col)
            outs.append(f)
        return outs

    def _step(self, code):
        buf, col = self.buf, self.col
        if 32 <= code < 127:
            if len(buf) >= MAX_LEN:
                return [self]
            nb = buf[:col] + chr(code) + buf[col:]
            if wrap_model(nb, 32)[1]:
                return [self]
            self.buf, self.col, self.touched = nb, col + 1, True
        elif code == LEFT:
            self.col = max(0, col - 1)
        elif code == RIGHT:
            self.col = min(len(buf), col + 1)
        elif code == DELETE:
            if col > 0:
                self.buf, self.col, self.touched = buf[:col - 1] + buf[col:], col - 1, True
            elif buf == "":
                return self._after_delete(self.cur, True)
        elif code in (UP, DOWN):
            self._updown(code == UP)
        elif code in (ENTER, INSERT_LINE):
            changed = self.buf != self.lines[self.cur][0]
            if self._leave(1):
                at = self.cur + 1 if code == ENTER else self.cur
                self.lines.insert(at, ["", True])
                self._goto(at, 0)
            elif changed:
                raise ModelAmbiguous("write-back plus insertion refused together: partial outcome not specified")
        elif code == DELETE_LINE:
            return self._after_delete(self.cur, False)
        elif code == BREAK:
            if not self._leave():
                raise ModelAmbiguous("BREAK with a write-back that does not fit: leaving or staying is not specified")
            self.exited = True
        return [self]

    def _updown(self, up):
        rows = wrows(self.buf)
        i, c = row_index(rows, self.col)
        if c >= 32:
            raise ModelAmbiguous("UP/DOWN from the cursor at the end of a full row")
        if up and i > 0:
            self.col = rows[i - 1][0] + min(c, rows[i - 1][1])
        elif not up and i < len(rows) - 1:
            self.col = rows[i + 1][0] + min(c, rows[i + 1][1])
        elif (up and self.cur == 0) or (not up and self.cur == self.n() - 1):
            pass
        elif self._leave():
            self._goto(self.cur + (-1 if up else 1), 0)
            r2 = wrows(self.buf)
            if up:
                self.col = r2[-1][0] + min(c, r2[-1][1])
            else:
                if len(r2) > 1 and c > r2[0][1]:
                    raise ModelAmbiguous("DOWN into a wrapped line whose first row is shorter than the column")
                self.col = min(c, r2[0][1])


def layout23(shown, top, partial):
    """Rows 0-22 for the displayed lines from `top` down; a last line that does not fit is drawn as far as it goes
    (partial) or not at all.  READING: the spec says the cursor line is always wholly on screen and nothing about a line
    below it that does not fit, so both drawings are accepted."""
    rows = []
    for t in shown[top:]:
        tr = row_texts(t)
        if len(rows) + len(tr) <= SCREEN_ROWS:
            rows += tr
        else:
            if partial:
                rows += tr[:SCREEN_ROWS - len(rows)]
            break
    return rows + [""] * (SCREEN_ROWS - len(rows))


class Obs:
    """What the oracle sees of the view: the store, its end cell, the 24 screen rows and the FLASH cells."""

    def __init__(self, store, end, rows, flash):
        self.store, self.end, self.rows, self.flash = store, end, rows, flash


def check_view(model, obs, prev_top):
    """Compare an observation with the model.  Returns (errors, top line shown).
    READING (scrolling): the spec fixes that the cursor line is wholly on screen and that the view scrolls "when a move
    would leave it partly off", by whole lines; the new top line is not specified, so any top that shows the cursor line
    wholly is accepted, but only when the old top would no longer do (the view does not scroll without need)."""
    errs = []
    want_store = model.store_bytes()
    if obs.store != want_store:
        n = next((i for i in range(min(len(obs.store), len(want_store))) if obs.store[i] != want_store[i]),
                 min(len(obs.store), len(want_store)))
        errs.append("store differs at byte %d (len %d, want %d): got %s, want %s" % (
            n, len(obs.store), len(want_store), obs.store[n:n + 12], want_store[n:n + 12]))
    shown = model.shown()
    cur = model.cur
    nrows = [len(wrows(t)) for t in shown]
    status = obs.rows[SCREEN_ROWS]
    if model.msg:
        if model.msg not in status:
            errs.append("status row %r should show %r" % (status, model.msg))
    elif status != "LINE %d/%d" % (cur + 1, len(shown)):
        errs.append("status row %r, want %r" % (status, "LINE %d/%d" % (cur + 1, len(shown))))
    prev = min(prev_top, cur)
    fits_prev = sum(nrows[prev:cur + 1]) <= SCREEN_ROWS
    cands = []
    for t in range(cur + 1):
        if sum(nrows[t:cur + 1]) > SCREEN_ROWS or (fits_prev and t != prev):
            continue
        if any(layout23(shown, t, p) == obs.rows[:SCREEN_ROWS] for p in (False, True)):
            cands.append(t)
    if not cands:
        t0 = prev
        if not fits_prev:
            t0 = cur
            while t0 > 0 and sum(nrows[t0 - 1:cur + 1]) <= SCREEN_ROWS:
                t0 -= 1
        want = layout23(shown, t0, False)
        bad = [r for r in range(SCREEN_ROWS) if want[r] != obs.rows[r]]
        errs.append("screen rows %s do not match the lines from top line %d%s: row %d reads %r, want %r" % (
            bad[:6], t0 + 1, "" if fits_prev else " (the view had to scroll; any top showing the cursor line is allowed)",
            bad[0], obs.rows[bad[0]], want[bad[0]]))
        return errs, prev
    top = cands[0]
    i, c = row_index(wrows(model.buf), model.col)
    if c >= 32:
        # READING: a cursor at the end of a full row is shown (E10) at column 0 of a row that may not exist (4 rows
        # already, or the next line in the way); the cell is not asserted there, only that at most one cell flashes.
        if len(obs.flash) > 1:
            errs.append("cursor cells %s, want at most one" % obs.flash)
    else:
        want_cell = (sum(nrows[top:cur]) + i, c)
        if obs.flash != [want_cell]:
            errs.append("cursor (FLASH) cells %s, want %s" % (obs.flash, [want_cell]))
    return errs, top


# ---------------------------------------------------------------------------------------------------- driving the view
class RealIO:
    """The view on a real machine: keys through the latch (or the keyboard matrix), observations from memory."""

    def __init__(self, env):
        self.env = env

    def key(self, code, via=None):
        con = self.env.con
        try:
            if via == "matrix":
                if code in CTRL_KEYS:
                    con.press_code(CTRL_KEYS[code], maxi=VIEW_MAXI, what=code)
                else:
                    con.press(code, maxi=VIEW_MAXI)
            else:
                con.key(code, maxi=VIEW_MAXI)
        except RuntimeError as e:
            raise ViewFail("%s did not return to a key wait: %s" % (keyname(code), e))

    def observe(self):
        env, m = self.env, self.env.m
        attrs = m.read(0x5800, 768)
        flash = [(i // 32, i % 32) for i, a in enumerate(attrs) if a & 0x80]
        return Obs(store_read(env), store_end(env), m.screen_rows(), flash)


class FakeIO:
    """A view that is the model itself (policy: scroll the least that shows the cursor line): drives the case sequences in
    `--selftest` without an emulator, to find test bugs (a sequence the model finds ambiguous, a typo) before the ROM exists."""

    def __init__(self, model):
        self.model, self.top = model, 0
        self._fit()

    def _fit(self):
        m = self.model
        if m.exited:
            return
        nrows = [len(wrows(t)) for t in m.shown()]
        self.top = min(self.top, m.cur)
        if sum(nrows[self.top:m.cur + 1]) > SCREEN_ROWS:
            t = m.cur
            while t > 0 and sum(nrows[t - 1:m.cur + 1]) <= SCREEN_ROWS:
                t -= 1
            self.top = t

    def pick(self, forks):
        return forks[0]

    def key(self, code, via=None):
        self.model = self.pick(self.model.step(code))
        self._fit()

    def observe(self):
        m = self.model
        shown = m.shown()
        nrows = [len(wrows(t)) for t in shown]
        rows = layout23(shown, self.top, False) + [m.msg or "LINE %d/%d" % (m.cur + 1, m.n())]
        i, c = row_index(wrows(m.buf), m.col)
        flash = [] if c >= 32 else [(sum(nrows[self.top:m.cur]) + i, c)]
        st = m.store_bytes()
        return Obs(st, LOADTEXT_BUF + len(st), rows, flash)


class VS:
    """A view session: sends keys and checks the whole state (store bytes, screen rows, status row, cursor cell) against
    the model after every one.  A mismatch raises ViewFail naming the key and what differs."""

    def __init__(self, io, model, label):
        self.io, self.model, self.label = io, model, label
        self.n, self.hist, self.choices = 0, [], []

    def check_now(self, what="opened"):
        errs, top = check_view(self.model, self.io.observe(), self.model.top)
        if errs:
            raise ViewFail("%s %s: %s" % (self.label, what, "; ".join(errs[:3])))
        self.model.top = top

    def key(self, code, via=None):
        self.n += 1
        self.hist.append(keyname(code))
        try:
            forks = self.model.step(code)
        except ModelAmbiguous as e:
            raise ViewFail("TEST BUG at key %d (%s): %s" % (self.n, keyname(code), e))
        self.io.key(code, via)
        if forks[0].exited:
            self.model = forks[0]
            return self.model
        obs = self.io.observe()
        first = None
        for f in forks:
            errs, top = check_view(f, obs, self.model.top)
            if not errs:
                if len(forks) > 1:
                    self.choices.append("key %d (%s): outcome %d of %d: cursor line %d offset %d" % (
                        self.n, keyname(code), forks.index(f) + 1, len(forks), f.cur + 1, f.col))
                f.top = top
                self.model = f
                return f
            first = first or errs
        raise ViewFail("%s key %d (%s) after %s: %s" % (self.label, self.n, keyname(code), " ".join(self.hist[-6:-1]) or "open",
                                                          "; ".join(first[:3])))

    def keys(self, seq, via=None):
        for code in seq:
            if self.key(code, via).exited:
                break
        return self.model


def open_view(env, ck, cmd):
    """Type `cmd` (an EDIT command) and ENTER.  Returns the status row's (n, m) when the view is open; otherwise records
    the failure (quickly: on the old build the console answers `EDIT ?`) and returns None."""
    m, con = env.m, env.con
    try:
        for ch in cmd:
            con.key(ord(ch), maxi=VIEW_MAXI)
        con.key(KEY_ENTER, maxi=VIEW_MAXI * 3)
    except RuntimeError as e:
        ck.true("%r returned to a key wait" % cmd, False, str(e))
        return None
    mt = STATUS_RE.match(m.screen_rows()[SCREEN_ROWS])
    if mt:
        return int(mt.group(1)), int(mt.group(2))
    rows = out_rows(env)
    if "EDIT ?" in rows:
        ck.true("no EDIT", False, "the console answers 'EDIT ?'")
    else:
        ck.true("no view", False, "no view after %r: row 23 reads %r, output rows %s" % (
            cmd, m.screen_rows()[SCREEN_ROWS], _short(rows[-3:])))
    return None


def start_view(env, ck, texts, name, idx, cap=None):
    """Boot, load `texts` as the store, open `EDIT name`; returns a VS on the line idx (0-based) or None."""
    env.boot()
    store_set(env, store_bytes(texts))
    if open_view(env, ck, "EDIT " + name) is None:
        return None
    vs = VS(RealIO(env), VModel(texts, cur=idx, cap=cap), name)
    vs.check_now()
    return vs


def check_left(env, ck, label, want_store):
    """After BREAK: the view is gone, the screen cleared and the console is back, the store holds `want_store` with every
    terminator $0D."""
    m = env.m
    rows = m.screen_rows()
    ck.true(label + ": row 23 no longer a status row", STATUS_RE.match(rows[SCREEN_ROWS]) is None, repr(rows[SCREEN_ROWS]))
    ck.true(label + ": console waiting in the editor", env.con.in_editor())
    got = store_read(env)
    eq_bytes(ck, label + ": store", got, want_store)
    ck.true(label + ": no $8D left in the store", CRM not in got)
    ck.eq(label + ": edit line, cursor", env.edit_state(), ("", 0))
    return rows


# ===================================================================== N1 store lines
@new_case("store-lines", "N1", "every committed line is appended to the store as its text followed by one CR ($0D), an empty line "
                               "appends nothing, an error line is appended, a 128-character line is appended whole, STORE_END "
                               "(the old build's WORKSPACE_END) follows exactly and nothing is written beyond it")
@guarded
def store_lines(env, part, ck):
    m, con = env.m, env.con
    buf = env.S("LOADTEXT_BUF")
    env.boot()
    ck.eq("%s at the start" % end_name(env), store_end(env), buf)
    model = b""
    # READING: "the console keeps appending committed lines" (E5): an error line and a line of blanks are committed lines
    # too, so they are appended; only a line of length 0 is not (spec section 3, Append).  Text is kept as typed.
    lines = ["1 2 + .", "5 6 *", "", "foo", "DROP", "  7 .", ("a" * 7 + " ") * 16]
    for line in lines:
        con.type(line)
        if line:
            model += line.encode("latin-1") + bytes([CR])
        got = store_read(env)
        ok = ck.eq("store after %r" % line[:24], got, model)
        ok = ck.eq("%s after %r" % (end_name(env), line[:24]), store_end(env), buf + len(model)) and ok
        if not ok:
            return
    ck.eq("zero beyond the end", m.read(buf + len(model), 32), bytes(32))
    ck.note("%d bytes: lines CR-ended, the empty line absent, STORE_END = $%04X" % (len(model), buf + len(model)))


# ===================================================================== N2 store full
@new_case("store-full", "N2", "an append that does not fit (STORE_END + length + 1 > STORE_LIMIT $F000) is not made: STORE FULL is printed "
                              "on its own line, the line still runs, the store and everything at and above $F000 stay as they were; "
                              "one that fits exactly is made; an empty line is never a refusal", parts=("exact", "over", "edge"))
@guarded
def store_full(env, part, ck):
    m, con = env.m, env.con
    buf = env.S("LOADTEXT_BUF")
    env.boot()
    pat = seed_above_limit(env)
    line22 = "1 2 + .".ljust(22)                                     # 22 characters + CR = 23 bytes, prints 3
    if part == "exact":
        end0 = STORE_LIMIT - 23
    elif part == "over":
        end0 = STORE_LIMIT - 16
    else:
        end0 = STORE_LIMIT - 2
    fill = bytes([0x40 + (i % 26) if i % 31 != 30 else CR for i in range(end0 - buf)])
    store_set(env, fill)
    before = store_read(env)

    def msgs():
        return count_row(env, "STORE FULL")

    # READING: "STORE FULL is printed on its own line": a row that reads exactly that.  Whether it comes before or after
    # the line's own output is not specified: the case accepts both, and asserts the line ran (its output is there).
    if part == "exact":
        con.type(line22)
        ck.eq("22 characters at 23 bytes from the limit: no refusal", msgs(), 0)
        eq_bytes(ck, "store: the line and a CR at the old end", store_read(env), before + line22.encode() + bytes([CR]))
        ck.eq(end_name(env), store_end(env), STORE_LIMIT)
        ck.true("the line ran (3 on the screen)", "3" in digits(out_rows(env)), str(out_rows(env)[-3:]))
        full = store_read(env)
        con.type("5 .")
        ck.eq("STORE FULL printed once on its own row", msgs(), 1)
        ck.true("the refused line still ran (5 on the screen)", "5" in digits(out_rows(env)), str(out_rows(env)[-3:]))
        eq_bytes(ck, "store unchanged by the refusal", store_read(env), full)
        ck.eq(end_name(env), store_end(env), STORE_LIMIT)
    elif part == "over":
        con.type(line22)
        ck.eq("STORE FULL printed once on its own row", msgs(), 1)
        ck.true("the line ran (3 on the screen)", "3" in digits(out_rows(env)), str(out_rows(env)[-3:]))
        eq_bytes(ck, "store unchanged", store_read(env), before)
        ck.eq(end_name(env), store_end(env), end0)
    else:
        con.type("5")
        ck.eq("1 character + CR into 2 free bytes: no refusal", msgs(), 0)
        eq_bytes(ck, "store", store_read(env), before + b"5\r")
        con.type("6")
        ck.eq("one more: STORE FULL once", msgs(), 1)
        eq_bytes(ck, "store unchanged", store_read(env), before + b"5\r")
        con.key(KEY_ENTER)
        ck.eq("an empty ENTER in a full store is not a refusal", msgs(), 1)
        eq_bytes(ck, "store unchanged by it", store_read(env), before + b"5\r")
    eq_bytes(ck, "$F000-$F0FF untouched", read_above_limit(env), pat)
    ck.note("%s: store end $%04X, nothing at or above $F000 written" % (part, store_end(env)))


# ===================================================================== N3 CR (and TAB) are whitespace
@new_case("cr-whitespace", "N3", "source with CR, TAB, LF and other bytes up to space between its words interprets as with spaces: "
                                 "through INTERPRET_RUN called directly, and through LOAD-TEXT from a tape (CR and TAB; a tape "
                                 "without a final CR gets one when there is room, none when the store is full)",
          parts=("interp", "mixed", "load-cr", "load-nocr", "load-full", "load-error"))
@guarded
def cr_whitespace(env, part, ck):
    m, con = env.m, env.con
    buf = env.S("LOADTEXT_BUF")
    if part in ("interp", "mixed"):
        # READING: spec section 3: "WORD treats every byte from 0 to space as a delimiter".  Every byte of that range is
        # not tried; CR, TAB, LF, NUL, SOH and US stand for it.
        if part == "interp":
            variants = [("space", b" "), ("CR", b"\r"), ("TAB", b"\t"), ("LF", b"\n"), ("NUL", b"\x00"), ("SOH", b"\x01"),
                        ("US", b"\x1f")]
            toks = [b":", b"SQ", b"DUP", b"*", b";", b"7", b"SQ", b"."]
            sources = [(n, d.join(toks) + d) for n, d in variants]
        else:
            sources = [("mixed", b" \r\t: SQ\r\r DUP\t*\n;\r 7\tSQ\r.")]
        for name, src in sources:
            env.boot()
            store_set(env, src)
            r = m.call("INTERPRET_RUN", regs={"HL": buf, "DE": len(src)})
            if not ck.true("%s: INTERPRET_RUN returned" % name, r["ok"], "PC=%04X" % r["pc"]):
                return
            rows = m.screen_rows()
            ck.eq("%s-separated source: row 1" % name, rows[1], "49")
            ck.eq("%s-separated source: INTERP_ERROR_FLAG" % name, env.u8("INTERP_ERROR_FLAG"), 0)
        ck.note("%d sources: `: SQ DUP * ; 7 SQ .` with each delimiter prints 49" % len(sources))
        return
    if part == "load-error":
        # An unknown word in the loaded text (spec section 3, LOAD-TEXT): the first line runs (`1 .`), `FOO ?` is the usual
        # message, the second line (`3 .`) does not run, and the machine stays intact: a word defined before the load still
        # runs, the store is the tape's data, and an uncaught THROW and an ABORT typed afterwards return to the prompt
        # normally (THROW_ROOT_SP is the outer interpreter's again).
        data = b"1 . FOO 2 .\r3 .\r"
        pat = tape_load(env, data, seed=True, pre=[": KEEP 7 ;"])
        rows = m.screen_rows()
        if store_end(env) == buf and read_above_limit(env)[:4] == bytes(4):
            ck.true("the machine kept running", False, "LOAD-TEXT restarted the machine (cold start: seed, store, KEEP gone); "
                    "screen %s" % _short(rows[:5]))
            return
        # (`1 .` leaves the print column after "1 ", so the message follows it on the same row: '1 FOO ?')
        ck.true("FOO ? on the screen", any(r == "FOO ?" or r.endswith(" FOO ?") for r in rows), _short(rows[:6]))
        ck.eq("1 printed by the first line, nothing from the rest (rows below the banner)", digits(rows[1:]), ["1"])
        ck.eq("banner kept", rows[0], BANNER)
        ck.true("back at the console key wait", env.con.in_editor() and env.edit_state() == ("", 0))
        eq_bytes(ck, "store after LOAD-TEXT", store_read(env), data)
        eq_bytes(ck, "$F000-$F0FF untouched", read_above_limit(env), pat)
        env.con.type("KEEP .")
        ck.eq("KEEP, defined before the load, still runs", last_out_row(env), "7 OK")
        env.con.type("-8 THROW")
        ck.eq("an uncaught THROW prints", last_out_row(env), "DICTIONARY FULL")
        ck.true("and returns to the prompt", env.con.in_editor())
        env.con.type("5 .")
        ck.eq("the console works after the THROW", last_out_row(env), "5 OK")
        env.con.type("ABORT")
        ck.true("ABORT returns to the prompt", env.con.in_editor())
        env.con.type("6 .")
        ck.eq("the console works after ABORT", last_out_row(env), "6 OK")
        ck.note("FOO ? shown, machine intact, store = tape data, THROW and ABORT return normally")
        return
    if part == "load-cr":
        data = b": SQ\tDUP\t*\t;\r7\tSQ\t.\r"
        want = data
    elif part == "load-nocr":
        data = b": SQ DUP *\r;\r7 SQ ."
        want = data + b"\r"                                         # "if its last byte is not CR, a CR is added when there is room"
    else:
        head = b": SQ DUP * ;\r: Z ;\r7 SQ .\r"
        pairs = (STORE_CAP - len(head) - 1) // 2
        data = head + b"Z\r" * pairs + b" " * (STORE_CAP - len(head) - 2 * pairs)
        want = data                                                 # no room: nothing is added, nothing is written past $F000
        ck.eq("the tape text is 8,192 bytes ending in a space", (len(data), data[-1]), (STORE_CAP, 0x20))
    pat = tape_load(env, data, maxi=400_000_000 if part == "load-full" else 250_000_000, seed=True)
    rows = m.screen_rows()
    if store_end(env) == buf and read_above_limit(env)[:4] == bytes(4):
        # (the seed written after the boot is gone and the store is empty: a cold start.  The old build does this when
        # LOAD-TEXT's text has an unknown word: the error path unwinds as if INTERPRET_RUN had been called from the prompt
        # loop, one level too far)
        ck.true("the machine kept running", False, "LOAD-TEXT restarted the machine (cold start: seed and store gone); screen %s" % _short(rows[:5]))
        return
    ck.eq("49 printed by the loaded program (rows below the banner)", digits(rows[1:]), ["49"])
    ck.eq("INTERP_ERROR_FLAG", env.u8("INTERP_ERROR_FLAG"), 0)
    eq_bytes(ck, "store after LOAD-TEXT", store_read(env), want)
    ck.eq(end_name(env), store_end(env), buf + len(want))
    eq_bytes(ck, "$F000-$F0FF untouched", read_above_limit(env), pat)
    ck.note("%s: %d tape bytes, store %d bytes, 49 printed" % (part, len(data), len(want)))


# ===================================================================== N5 dictionary ceiling
@new_case("dict-ceiling", "N5", "the dictionary stops 256 bytes below $D000 (E2a): definitions in a loop (`: Wnn ;`), data words, and a "
                                "large `n ALLOT`, `,` and `C,` are refused with THROW -8 before HERE passes $D000 - 256 "
                                "(uncaught it prints DICTIONARY FULL; CATCH shows -8), HERE and LATEST stay, and the store at "
                                "$D000 is not written; what is allowed below the guard is accepted",
          parts=("defs", "data", "allot", "body"))
@guarded
def dict_ceiling(env, part, ck):
    m, con, S = env.m, env.con, env.S
    buf = S("LOADTEXT_BUF")
    guard_top = DICT_CEIL - GUARD                                  # $CF00
    env.boot()
    prefix = bytes([0x41 + (i % 26) if i % 50 != 49 else CR for i in range(600)])
    store_set(env, prefix)

    def here():
        return m.w16(S("HERE"))

    def latest():
        return m.w16(S("LATEST"))

    def poke_here(v):
        m.poke16(S("HERE"), v)

    def line(text):
        con.type(text)
        return last_out_row(env), env.u8("INTERP_ERROR_FLAG")

    def store_ok(label):
        return eq_bytes(ck, label + ": store bytes at $D000", m.read(buf, len(prefix)), prefix)

    def refused(label, text):
        h0, l0 = here(), latest()
        row, flag = line(text)
        ck.eq(label + ": refused (row, error flag)", (row, flag), ("DICTIONARY FULL", 1))
        ck.eq(label + ": HERE, LATEST unchanged", (here(), latest()), (h0, l0))

    if part == "defs":
        # READING: "refuses when HERE would pass DICT_RAM_CEILING - 256" at "every place that starts a definition": a
        # definition is accepted only if HERE was at or below $CF00 where it started, and is refused once it was past it
        # (by at most the size of a header: the check may be made after the header is built, so a refusal is allowed from
        # 16 bytes below $CF00); the body compiled after the start may pass $CF00 (that is what the guard is for) but
        # never $D000.  A refusal leaves HERE and LATEST as they were; the refused name is not defined.
        poke_here(guard_top - 30)
        first_refusal, passed, log = None, None, []
        for i in range(40):
            h0, l0 = here(), latest()
            row, flag = line(": W%02d ;" % i)
            h1, l1 = here(), latest()
            log.append((h0, h1, flag))
            if flag:
                first_refusal = i
                ck.eq("refusal %d: DICTIONARY FULL row" % i, row, "DICTIONARY FULL")
                ck.eq("refusal %d: HERE, LATEST unchanged" % i, (h1, l1), (h0, l0))
                ck.true("refusal %d: HERE $%04X is not near $%04X" % (i, h0, guard_top), h0 > guard_top - 16)
                break
            ck.true("accepted definition %d started at HERE $%04X, past $%04X (ceiling - 256)" % (i, h0, guard_top), h0 <= guard_top)
            ck.true("accepted definition %d ended at HERE $%04X, past $%04X" % (i, h1, DICT_CEIL), h1 <= DICT_CEIL)
            if h1 > DICT_CEIL:
                break
        ck.true("a definition is refused within 40 lines (HERE $%04X)" % here(), first_refusal is not None)
        if first_refusal is not None:
            for j in range(2):
                refused("after the first refusal, line %d" % j, ": X%d ;" % j)
            line("W%02d" % first_refusal)
            ck.eq("the refused name is not defined", last_out_row(env), "W%02d ?" % first_refusal)
        store_ok("defs")
        ck.note("%d definitions, first refusal at line %s, HERE $%04X" % (len(log), first_refusal, here()))
    elif part == "data":
        poke_here(guard_top + 8)
        for text in ("VARIABLE V1", "1 CONSTANT K1", "CREATE C1", "10 ARRAY A1", "3 STRING S1"):
            refused("past the guard: " + text, text)
        # READING: a data field that would carry HERE past the guard is refused ("HERE would pass"), whatever its size: an
        # array of 200 cells (400 bytes) started 4 bytes below $CF00 would end past $D000.
        poke_here(guard_top - 4)
        refused("`200 ARRAY` 4 bytes below the guard", "200 ARRAY AX")
        refused("`300 STRING` 4 bytes below the guard", "300 STRING SX")
        poke_here(guard_top - 200)
        row, flag = line("VARIABLE VOK")
        ck.eq("VARIABLE 200 bytes below the guard is accepted (row, flag)", (row, flag), ("OK", 0))
        line("5 VOK ! VOK @ .")
        ck.eq("and works", last_out_row(env), "5 OK")
        store_ok("data")
    elif part == "allot":
        # How the build reports a THROW to the console (rom/forth_boot.asm RUNTIME_ERROR_HOOK, core/throwcatch.asm): an
        # uncaught THROW prints the message of its code (-8: DICTIONARY FULL, since step F item 5); CATCH leaves the code, which
        # `.` prints.  The control below checks that on this build before the guard cases rely on it.
        for t in (": T9 -8 THROW ;", ": A40 40 ALLOT ;", ": A1 1 ALLOT ;", ": B1 65 C, ;", ": B2 1234 , ;",
                  ": A20K 20000 ALLOT ;", ": A28K 28672 ALLOT ;", ": A32K 32767 ALLOT ;"):
            line(t)
        line("T9")
        ck.eq("control: an uncaught THROW -8 prints", last_out_row(env), "DICTIONARY FULL")
        line("' T9 CATCH .")
        ck.eq("control: CATCH leaves -8, `.` prints", last_out_row(env), "-8 OK")
        natural = here()

        def code(word):
            h0 = here()
            row, _ = line("' %s CATCH ." % word)
            mt = re.match(r"^(-?\d+) OK$", row)
            return (int(mt.group(1)) if mt else row), h0

        def expect(label, word, want, hwant):
            c, h0 = code(word)
            ck.eq("%s: THROW code" % label, c, want)
            ck.eq("%s: HERE after" % label, here(), hwant if hwant is not None else h0)

        # READING: the check is on the new HERE, so reaching $CF00 exactly is allowed and one byte more is refused.
        poke_here(guard_top - 40)
        expect("40 ALLOT up to the guard", "A40", 0, guard_top)
        expect("1 ALLOT past the guard", "A1", -8, None)
        expect("C, past the guard", "B1", -8, None)
        expect(", past the guard", "B2", -8, None)
        h = here()
        line("A1")
        ck.eq("uncaught 1 ALLOT past the guard prints", (last_out_row(env), here()), ("DICTIONARY FULL", h))
        poke_here(guard_top - 1)
        expect("C, to the guard exactly", "B1", 0, guard_top)
        expect("C, one past", "B1", -8, None)
        poke_here(guard_top - 1)
        expect(", needs 2 bytes, 1 left", "B2", -8, None)
        poke_here(natural)
        expect("20000 ALLOT from HERE $%04X" % natural, "A20K", -8, None)
        expect("28672 ALLOT (HERE + n carries past $FFFF)", "A28K", -8, None)
        expect("32767 ALLOT (HERE + n carries past $FFFF)", "A32K", -8, None)
        store_ok("allot")
    else:
        poke_here(guard_top - 12)
        h0 = here()
        row, flag = line(": BIG")
        ck.eq("`: BIG` 12 bytes below the guard is accepted (row, flag)", (row, flag), ("OK", 0))
        for _ in range(6):
            row, flag = line("1 DROP 2 DROP 3 DROP 4 DROP")
            if flag:
                break
        ck.eq("a body of about 200 bytes typed in parts: last row, flag", (row, flag), ("OK", 0))
        line(";")
        body = here() - h0
        ck.true("HERE $%04X after the definition is not past $%04X" % (here(), DICT_CEIL), here() <= DICT_CEIL)
        line("BIG")
        ck.eq("BIG runs", (last_out_row(env), env.u8("INTERP_ERROR_FLAG")), ("OK", 0))
        store_ok("body")
        # READING: a definition that starts past the guard is refused (`:` is a place that starts a definition).
        env.boot()
        store_set(env, prefix)
        poke_here(guard_top + 4)
        refused("`: BIG2 ;` past the guard", ": BIG2 ;")
        store_ok("body, second half")
        ck.note("a %d-byte definition from %d bytes below the guard is accepted and runs" % (body, 12))


# ===================================================================== the stores the view cases use
N6_STORE = [": SQ DUP * ;", ": CUBE DUP SQ * ;", "3 : sq 1 + ;", ": SQRT DROP ;", ": X SQ ;", ": SQUARE ;", ":", "SQ ."]
N6_OPENS = [("SQ", 2), ("cube", 1), ("Sqrt", 3), ("x", 4), ("square", 5)]
WRAP71 = "one two three four five six seven eight nine ten eleven twelve thirteen"       # 3 rows: 27, 27, 15
WRAP70 = "the quick brown fox jumps over the lazy dog and keeps running far away"          # 3 rows: 30, 30, 8


def big_store():
    """60 one-row lines `: Wnn n ;`, two of them (W20, W40) wrapped to 3 rows."""
    t = [": W%02d %d ;" % (i, i) for i in range(1, 61)]
    t[19] = ": W20 " + "one two three four five six seven eight nine ten eleven twelve"
    t[39] = ": W40 " + "the quick brown fox jumps over the lazy dog and keeps running far"
    return t


# ===================================================================== N6 EDIT opens the view
@new_case("edit-open", "N6", "`EDIT SQ` opens the view on the last line in the store where the words `:` and `SQ` follow each other "
                             "(case-insensitive; not `: SQRT`, not `: X SQ`, not across a line break), cursor at the line's start, "
                             "status row `LINE n/m`, every line on screen; `EDIT` alone opens a new line after the last; in a "
                             "60-line store the cursor line is on screen",
          parts=("name", "bare", "scroll"))
@guarded
def edit_open(env, part, ck):
    m = env.m
    if part == "name":
        # READING (spec section 5, Entry): "the last line in the store in which the words : and name follow each other",
        # words separated by whitespace, case-insensitive: the match is per line, so `:` ending one line and `SQ` starting
        # the next is not a match (N6_STORE lines 7 and 8), and `: X SQ` (both words, not adjacent) is not.
        for name, idx in N6_OPENS:
            vs = start_view(env, ck, N6_STORE, name, idx)
            if vs is None:
                return
        ck.note("EDIT %s -> lines %s of %d, cursor at the line start, all lines on screen" % (
            "/".join(n for n, _ in N6_OPENS), "/".join(str(i + 1) for _, i in N6_OPENS), len(N6_STORE)))
    elif part == "bare":
        env.boot()
        orig = store_bytes(N6_STORE)
        store_set(env, orig)
        st = open_view(env, ck, "EDIT")
        if st is None:
            return
        n = len(N6_STORE)
        # READING: the new empty line is line m+1; the total is m+1 if the line exists in the store at once, m if it is only
        # in the buffer until it is left (the spec's "n past the last line gives STORE_END, length 0" allows both).
        ck.eq("cursor line number", st[0], n + 1)
        ck.true("line count %d is %d or %d" % (st[1], n, n + 1), st[1] in (n, n + 1))
        obs = RealIO(env).observe()
        ck.eq("rows 0-22: the %d lines, then the empty new line" % n, obs.rows[:SCREEN_ROWS], layout23(N6_STORE + [""], 0, False))
        ck.eq("cursor cell on the new line", obs.flash, [(n, 0)])
        ck.true("store unchanged, or with the new empty line's mark ($8D)", obs.store in (orig, orig + bytes([CRM])), _short(obs.store[-12:]))
        for ch in "5 .":
            env.con.key(ord(ch), maxi=VIEW_MAXI)
        obs = RealIO(env).observe()
        ck.eq("the typed text is on the new line", obs.rows[n], "5 .")
        env.con.key(BREAK, maxi=VIEW_MAXI * 3)
        rows = check_left(env, ck, "BREAK", orig + b"5 .\r")
        ck.eq("the new line's program ran: digits on screen", digits(rows), ["5"])
    else:
        big = big_store()
        for name, idx in (("W55", 54), ("W01", 0), ("W60", 59), ("W40", 39)):
            vs = start_view(env, ck, big, name, idx)
            if vs is None:
                return
        ck.note("EDIT W55/W01/W60/W40 in a 60-line store (two wrapped lines): the cursor line is wholly on screen each time")


# ===================================================================== N7 the key table, key by key
def seq_chars():
    """READING: only characters the font draws (GFX_PUTCHAR draws `[ \\ ] ^ ` { | } ~` as blanks, so the screen could not show
    them: UNTYPEABLE is also the list of the undrawn codes); the typed lines are the last line of the store, because a cursor
    at the end of a full row may claim a row of its own (E10) which would move the lines below it."""
    store = [": AA 1 ;", ": BB 2 ;", ": CC 3 ;", ": DD 4 ;"]
    drawn = "".join(chr(c) for c in range(32, 127) if chr(c) not in UNTYPEABLE)
    keys = K(LEFT, RIGHT, RIGHT, RIGHT, "7 ", (LEFT, 2), "5", (RIGHT, 40), " 8", DOWN, (LEFT, 3), "q", (RIGHT, 3),
             "()+-*/<>=;:,.?!@#$%&'\"_", ENTER, drawn, BREAK)
    return store, "CC", 2, keys


def seq_limits():
    """Typing into a line until the console's limits refuse (4 rows, 128 characters), then room again."""
    store = [": LL ;"]
    word = "w" * 25
    keys = K(ENTER, ((word + " ") * 3 + word), "w" * 9, " ", DELETE, (DELETE, 12), "k", (LEFT, 20), " ", "zz", (RIGHT, 99), BREAK)
    return store, "LL", 0, keys


def seq_updown():
    store = [": UA 1 ;", WRAP71, "x", WRAP70, "", "tail"]
    keys = K(UP, DOWN, (RIGHT, 20), (DOWN, 3), UP, (RIGHT, 2), (DOWN, 2), (DOWN, 2), (RIGHT, 28), (DOWN, 3), (DOWN, 2), (RIGHT, 4),
             DOWN, (UP, 3), (UP, 4), (RIGHT, 1), (UP, 3), (UP, 2), UP, (DOWN, 2), (UP, 6), BREAK)
    return store, "UA", 0, keys


def seq_delete():
    store = [": DA ;", "", "abc", "", "end", WRAP71]
    keys = K(DELETE, (RIGHT, 3), DELETE, DOWN, DOWN, (RIGHT, 3), (DELETE, 3), DELETE,
             DELETE, (RIGHT, 5), (DELETE, 2), (DOWN, 3), (RIGHT, 28), (DELETE, 2), (RIGHT, 10), DELETE, BREAK)
    return store, "DA", 0, keys


def seq_enter():
    store = [": EA 1 ;", "second", "third"]
    keys = K(ENTER, "x", ENTER, ENTER, (UP, 3), (DOWN, 4), (RIGHT, 3), ENTER, "z", DOWN, (RIGHT, 5), "9", ENTER, BREAK)
    return store, "EA", 0, keys


def seq_delete_line():
    store = [": XA 1 ;", "b1", "b2", "b3", "b4", "b5"]
    keys = K((DOWN, 2), DELETE_LINE, "q", DELETE_LINE, DOWN, DELETE_LINE, (UP, 2), DELETE_LINE, DOWN, BREAK)
    return store, "XA", 0, keys


def seq_insert_line():
    store = [": IA 1 ;", "c1", "c2"]
    keys = K(INSERT_LINE, "5", INSERT_LINE, (DOWN, 4), (RIGHT, 2), "!", INSERT_LINE, DOWN, BREAK)
    return store, "IA", 0, keys


def seq_scroll():
    store = big_store()
    keys = K((DOWN, 30), DOWN, ENTER, "end", (UP, 62), INSERT_LINE, "top", (DOWN, 25), DELETE_LINE, DELETE_LINE, (DOWN, 20), ENTER,
             "mid", (UP, 3), BREAK)
    return store, "W30", 29, keys


def seq_matrix():
    store = [": AA 1 ;", ": BB 2 ;", ": CC 3 ;"]
    keys = K("ab", LEFT, RIGHT, DELETE, DOWN, UP, ENTER, "c", INSERT_LINE, DELETE_LINE, BREAK)
    return store, "AA", 0, keys


N7_SEQS = {"chars": seq_chars, "limits": seq_limits, "updown": seq_updown, "delete": seq_delete, "enter": seq_enter,
           "delete-line": seq_delete_line, "insert-line": seq_insert_line, "scroll": seq_scroll, "matrix": seq_matrix}


def run_seq(env, ck, seq, via=None, io_factory=None):
    """Open the view for a sequence, send its keys with the check after each, and check the state left by BREAK."""
    store, name, idx, keys = seq
    vs = start_view(env, ck, store, name, idx)
    if vs is None:
        return None
    vs.keys(keys, via)
    if not vs.model.exited:
        raise ViewFail("the sequence did not end with BREAK")
    check_left(env, ck, "BREAK", vs.model.store_bytes())
    return vs


@new_case("edit-keys", "N7", "every row of the key table (spec section 5), the store bytes and the whole screen (rows, status row, cursor cell) "
                            "checked against a model after each key: characters (all 95 printable codes), LEFT, RIGHT, the limits "
                            "(4 rows, 128 characters), UP and DOWN inside a wrapped line and between lines and at the ends, DELETE "
                            "(character, empty line, column 0), ENTER, delete-line, insert-line, BREAK, scrolling in a 60-line store, "
                            "and the control keys through the keyboard matrix",
          parts=tuple(N7_SEQS))
@guarded
def edit_keys(env, part, ck):
    vs = run_seq(env, ck, N7_SEQS[part](), "matrix" if part == "matrix" else None)
    if vs is not None:
        ck.note("%d keys checked%s; %s" % (vs.n, "" if not vs.choices else ", outcomes the spec leaves open: " + "; ".join(vs.choices[:4]),
                                         "store left: %d lines" % vs.model.n()))


# ===================================================================== N8 leaving: what is interpreted
N8_BASE = [": SQ DUP * ;", "1 .", "2 SQ .", "3 ."]
# `marked`: L1 redefined (SQ becomes n*n+1), L2 and L3 untouched, L4 gets more words, a new line 5 uses the new SQ: if the marked
# lines ran in another order, or an unmarked one ran, the digits differ (L3 would print 5, `9 SQ .` 81).
N8_MARKED = K((RIGHT, 11), "1 + ", DOWN, DOWN, DOWN, " 4 .", ENTER, "9 SQ .", BREAK)
N8_UNCHANGED = K(DOWN, DOWN, UP, RIGHT, LEFT, DOWN, DOWN, BREAK)
# `error`: L2 -> `11 .`, L3 -> `FOO 2 SQ .` (an unknown word), L4 -> `13 .`: L2 runs and prints 11, L3 stops it with LINE 3 and FOO ?,
# L4 is not run (13 must not appear) but its mark is cleared.
N8_ERROR = K(DOWN, "1", DOWN, LEFT, "FOO ", DOWN, (LEFT, 3), "1", BREAK)


def n8_selfmark():
    """(head line, the line that reads its own terminator, keys): the new line 2 holds `<address of its own CR> C@ .`: its
    mark must be cleared before it runs (prints 13, not 141)."""
    head = ": T8 ;"
    start = LOADTEXT_BUF + len(head) + 1
    text = ""
    for _ in range(3):
        text = "%d C@ ." % (start + len(text))
    assert text == "%d C@ ." % (start + len(text)), "the address does not settle"
    return head, text, K(ENTER, text, BREAK)


@new_case("edit-commit", "N8", "leaving interprets only the lines changed in the session, in store order, each with its mark cleared before "
                               "it runs; an unchanged session interprets nothing; the first error stops it with `LINE n` before the "
                               "error's message and the remaining marks are cleared without interpreting; no $8D is left in the store",
          parts=("marked", "unchanged", "error", "selfmark"))
@guarded
def edit_commit(env, part, ck):
    m = env.m
    base = N8_BASE
    if part == "marked":
        vs = start_view(env, ck, base, "SQ", 0)
        if vs is None:
            return
        vs.keys(N8_MARKED)
        want = [": SQ DUP * 1 + ;", "1 .", "2 SQ .", "3 . 4 .", "9 SQ ."]
        ck.eq("model's lines", [t for t, _ in vs.model.lines], want)
        rows = check_left(env, ck, "after BREAK", store_bytes(want))
        ck.eq("only the marked lines ran, in order (digits on screen)", digits(rows), ["3", "4", "82"])
        env.con.type("5 SQ .")
        ck.eq("SQ was redefined by the session", last_out_row(env), "26 OK")
        ck.note("marked lines 1, 4, 5 ran in store order; lines 2, 3 did not; no $8D left")
    elif part == "unchanged":
        vs = start_view(env, ck, base, "SQ", 0)
        if vs is None:
            return
        h0, l0 = m.w16(env.S("HERE")), m.w16(env.S("LATEST"))
        vs.keys(N8_UNCHANGED)
        rows = check_left(env, ck, "after BREAK", store_bytes(base))
        # READING: "returns to the prompt" may print OK (the EDIT command line finishing); nothing else may be on screen,
        # and nothing was defined or run.
        ck.true("the screen shows nothing but an optional OK", [r for r in rows[:SCREEN_ROWS] if r] in ([], ["OK"]), _short(rows[:4]))
        ck.eq("HERE, LATEST unchanged (nothing interpreted)", (m.w16(env.S("HERE")), m.w16(env.S("LATEST"))), (h0, l0))
        ck.true("PRINT_COL 0, PRINT_ROW reset (0, or 1 after OK)", env.print_pos()[1] == 0 and env.print_pos()[0] in (0, 1), str(env.print_pos()))
    elif part == "error":
        vs = start_view(env, ck, base + ["4 ."], "SQ", 0)
        if vs is None:
            return
        vs.keys(N8_ERROR)
        want = [": SQ DUP * ;", "11 .", "FOO 2 SQ .", "13 .", "4 ."]
        ck.eq("model's lines", [t for t, _ in vs.model.lines], want)
        rows = check_left(env, ck, "after BREAK", store_bytes(want))
        text = " ".join(r for r in rows[:SCREEN_ROWS] if r)
        # READING: "the error's usual message preceded by LINE n": `LINE 3` then `FOO ?`, on one row or on two.
        ck.true("LINE 3 then FOO ? on screen", re.search(r"LINE 3\s+FOO \?", text) is not None, _short(text))
        ck.eq("digits: 11 ran, LINE 3, nothing after", digits(rows), ["11", "3"])
        env.con.type("7 .")
        ck.eq("the console works afterwards", last_out_row(env), "7 OK")
        ck.note("error at line 3 stopped the commit; line 4 not run; marks cleared: %s" % _short(text, 60))
    else:
        head, text, keys = n8_selfmark()
        vs = start_view(env, ck, [head], "T8", 0)
        if vs is None:
            return
        vs.keys(keys)
        rows = check_left(env, ck, "after BREAK", store_bytes([head, text]))
        ck.eq("the line read its own terminator (digits on screen)", digits(rows), ["13"])


# ===================================================================== N9 the redraw oracle for the view
def blank_screen(m):
    """Rows 0-23 of the 32-column screen blank: all pixels zero, every attribute ATTR_DEFAULT."""
    for i in range(3):
        m.write(0x4000 + 2048 * i, bytes(2048))
    m.write(0x5800, bytes([m.S.get("ATTR_DEFAULT", 0x44)]) * 768)


def view_reference(env):
    """The screen a full view redraw draws from the view's state (EXROM routine VIEW_REDRAW_ALL, called at the key wait with
    the machine put on a checkpoint first and the screen blanked, so that nothing of the live screen can leak into the
    reference); the machine is put back exactly as it was."""
    m = env.m
    cp = m.checkpoint("oracle")
    try:
        blank_screen(m)
        r = m.call("VIEW_REDRAW_ALL")
        if not r["ok"]:
            raise ViewFail("VIEW_REDRAW_ALL did not return (PC=%04X)" % r["pc"])
        return read_screen(m)
    finally:
        m.rollback(cp)


def o9_small():
    return ([": AA 1 ;", ": BB 2 ;", ": CC 3 ;", ": DD 4 ;", ": EE 5 ;"], "CC",
            K("hello", (LEFT, 3), "XY", (DELETE, 2), (RIGHT, 4), DOWN, "abc", UP, ENTER, "new", INSERT_LINE, "ins", DELETE_LINE,
              (DOWN, 3), (UP, 5), DELETE, (RIGHT, 2), DELETE, DELETE_LINE, (UP, 2), DELETE_LINE))


def o9_wrap():
    grow = " alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi"
    return ([": AA 1 ;", ": BB 2 ;", ": CC 3 ;", ": DD 4 ;"], "BB",
            K((RIGHT, 8), grow, (UP, 2), (DOWN, 3), (LEFT, 40), (UP, 1), (RIGHT, 30), DELETE, (DELETE, 60), (DOWN, 1), ENTER, "mid",
              (LEFT, 3), ENTER, "Z", (UP, 3), (DOWN, 6), (DELETE, 3)))


def o9_scroll():
    return (big_store(), "W30",
            K((DOWN, 24), (UP, 8), ENTER, "x", (DOWN, 3), INSERT_LINE, DELETE_LINE, DELETE_LINE, (UP, 45), (DOWN, 50), INSERT_LINE,
              "ins", (UP, 40), DELETE_LINE, (DOWN, 60), (UP, 30)))


O9_SCENARIOS = {"small": o9_small, "wrap": o9_wrap, "scroll": o9_scroll}


@new_case("edit-redraw-oracle", "N9", "after every key in the view the whole screen (bitmap and attributes, 6,912 bytes) equals the screen a "
                                     "full redraw draws from the same state (VIEW_REDRAW_ALL called from a checkpoint onto a blank "
                                     "screen), in scenarios that type, wrap, shift lines, insert, delete and scroll; and the oracle "
                                     "sees a stray pixel, a stray FLASH attribute and a missing cursor",
          parts=tuple(O9_SCENARIOS) + ("control",))
@guarded
def edit_redraw_oracle(env, part, ck):
    m = env.m
    if "VIEW_REDRAW_ALL" not in m.S:
        ck.true("no VIEW_REDRAW_ALL", False, "the EXROM routine the oracle calls is not in the symbols (the old build has no view)")
        return
    if part == "control":
        vs = start_view(env, ck, [": AA 1 ;", ": BB 2 ;"], "BB", 1)
        if vs is None:
            return
        vs.keys(K("ab", DOWN))
        now, ref = read_screen(m), view_reference(env)
        ck.eq("a clean view equals its reference", first_diff(now, ref), None)
        stray = bytearray(now)
        stray[((21 * 8 & 0xC0) << 5) + ((21 * 8 & 0x38) << 2) + 0x100 * 3 + 5] ^= 0x10     # row 21, line 3, column 5
        ck.true("a stray pixel byte is a difference", first_diff(bytes(stray), ref) is not None)
        stray = bytearray(now)
        stray[0x1800 + 22 * 32 + 7] |= 0x80
        ck.true("a stray FLASH attribute is a difference", first_diff(bytes(stray), ref) is not None)
        stray = bytearray(now)
        cells = [i for i in range(768) if now[0x1800 + i] & 0x80]
        ck.true("the view shows a cursor cell", len(cells) == 1, str(cells))
        for i in cells:
            stray[0x1800 + i] = m.S.get("ATTR_DEFAULT", 0x44)
        ck.true("a missing cursor is a difference", first_diff(bytes(stray), ref) is not None)
        ck.note("control: a clean view matches; a stray pixel, a stray FLASH cell and a missing cursor each differ")
        return
    store, name, keys = O9_SCENARIOS[part]()
    idx = next(i for i, t in enumerate(store) if re.match(r"^(\d+ )?: %s\b" % name, t))
    vs = start_view(env, ck, store, name, idx)
    if vs is None:
        return
    io, bad, n = vs.io, [], 0
    for code in keys:
        io.key(code)
        n += 1
        if STATUS_RE.match(m.screen_rows()[SCREEN_ROWS]) is None:
            raise ViewFail("the view was left at key %d (%s)" % (n, keyname(code)))
        d = first_diff(read_screen(m), view_reference(env))
        if d:
            bad.append("key %d (%s): %s" % (n, keyname(code), d))
    ck.true("%d keys: the screen equals a full redraw after every key" % n, not bad,
            "; ".join(bad[:3]) + (" (+%d)" % (len(bad) - 3) if len(bad) > 3 else ""))
    ck.note("%s: %d keys, 6912 bytes compared after each" % (part, n))


# ===================================================================== N10 / N11 refusals
def refusal(env, ck, cmd, msg):
    """`cmd` (an EDIT command that must be refused): exactly the message `msg` is printed (an OK after it is allowed), no view
    opens, the store, HERE, LATEST and the display mode are as they were, and the console works afterwards.  Returns False
    when the console does not know EDIT (the old build): the failure is recorded and the case ends quickly."""
    m, con, S = env.m, env.con, env.S
    before = store_read(env)
    h0, l0, g0 = m.w16(S("HERE")), m.w16(S("LATEST")), env.u8("GFX_MODE")
    rows0 = out_rows(env)
    for ch in cmd:
        con.key(ord(ch), maxi=VIEW_MAXI)
    con.key(KEY_ENTER, maxi=VIEW_MAXI * 3)
    new = out_rows(env)[len(rows0):]
    if new == ["EDIT ?"]:
        ck.true("no EDIT", False, "the console answers 'EDIT ?'")
        return False
    ck.true("%s: output is %r (an OK after it is allowed)" % (cmd, msg), new in ([msg], [msg, "OK"]), "got %s" % _short(new))
    ck.true("%s: no view opened" % cmd, STATUS_RE.match(m.screen_rows()[SCREEN_ROWS]) is None)
    # READING: the console appends every committed line (E5); "changing nothing" is read as: the store's bytes are what they
    # were, with the typed `EDIT ...` line at the end if the console appended it (the spec does not say if it does).
    ck.true("%s: store unchanged" % cmd, store_read(env) in typed_line_variants(before, cmd), _short(store_read(env)[-30:]))
    ck.eq("%s: HERE, LATEST, GFX_MODE" % cmd, (m.w16(S("HERE")), m.w16(S("LATEST")), env.u8("GFX_MODE")), (h0, l0, g0))
    ck.true("%s: console waiting in the editor, empty line" % cmd, con.in_editor() and env.edit_state() == ("", 0))
    con.type("1 2 + .")
    ck.eq("%s: the console still works" % cmd, last_out_row(env), "3 OK")
    return True


@new_case("edit-refusals", "N10", "`EDIT` is refused with one message and nothing changed: NO EXROM (a stock-shaped EXROM, 8 KB of $00, in a "
                                 "temporary copy of the build), LONG LINE (a 199-character line in the store, for `EDIT SQ` and `EDIT`), "
                                 "and `NOSUCH ?` for a name that is not in the store; the console works afterwards",
          parts=("noexrom", "longline", "notfound"))
@guarded
def edit_refusals(env, part, ck):
    env.boot()
    if part == "longline":
        texts = [": SQ DUP * ;", ("abcdefgh " * 23)[:199], ": CUBE DUP SQ * ;"]
        store_set(env, store_bytes(texts))
        ok = refusal(env, ck, "EDIT SQ", "LONG LINE") and refusal(env, ck, "EDIT", "LONG LINE")
        names = "EDIT SQ / EDIT with a 199-character line in the store"
    else:
        store_set(env, store_bytes(N6_STORE))
        if part == "noexrom":
            ok = refusal(env, ck, "EDIT SQ", "NO EXROM") and refusal(env, ck, "EDIT", "NO EXROM")
            names = "EDIT SQ / EDIT with the stock-shaped EXROM"
        else:
            ok = all(refusal(env, ck, "EDIT " + n, n.upper() + " ?") for n in ("nosuch", "sq2", "dup"))
            names = "EDIT nosuch / sq2 / dup (no `: name` line)"
    if ok:
        ck.note("%s: refused, store/HERE/LATEST unchanged, console works" % names)


# ===================================================================== N12 typing cost in the view
def vcost_spec(which):
    """(store texts, EDIT name, line index, setup keys, measured key) of a typing-cost scenario in the view."""
    short = [": AA 1 ;", ": BB 2 ;", ": CC 3 ;"]
    if which == "key-end-short":
        return short, "BB", 1, K((RIGHT, 8)), ord("x")
    if which == "key-mid-100":
        return [": AA ;", ": BB " + GROW[:95], "tail"], "BB", 1, K((RIGHT, 50)), ord("x")
    if which == "key-3row":
        return [": AA ;", ": BB " + "a" * 65, "tail"], "BB", 1, K((RIGHT, 70)), ord("x")
    if which == "delete":
        return short, "BB", 1, K((RIGHT, 8)), DELETE
    if which == "left":
        return short, "BB", 1, K((RIGHT, 8)), LEFT
    if which == "up-in-line":
        return [": AA ;", ": BB " + WRAP71, "tail"], "BB", 1, K((RIGHT, 60)), UP
    if which == "down-line":
        return short, "BB", 1, K((RIGHT, 3)), DOWN
    if which == "enter":
        return short, "BB", 1, K((RIGHT, 8)), ENTER
    if which == "insert-line":
        return short, "BB", 1, K((RIGHT, 3)), INSERT_LINE
    if which == "delete-line":
        return short, "BB", 1, K((RIGHT, 3)), DELETE_LINE
    if which == "scroll-down":
        return big_store(), "W01", 0, K((DOWN, 22)), DOWN
    # spec section 5.4: the cases item 6's set hid (a full 60-line store)
    if which == "down-mid-full":
        return big_store(), "W10", 9, K((DOWN, 2)), DOWN
    if which == "up-scroll":
        return big_store(), "W40", 39, K((UP, 30)), UP
    if which == "enter-bottom":
        return big_store(), "W60", 59, K((RIGHT, 12)), ENTER
    raise KeyError(which)


VCOST_CASES = [("key-end-short", "a key at the end of a short line"), ("key-mid-100", "a key in the middle of a 100-character line"),
               ("key-3row", "a key at the end of a 3-row line"), ("delete", "DELETE at the end of a short line"),
               ("left", "LEFT in a short line"), ("up-in-line", "UP inside a wrapped line"),
               ("down-line", "DOWN to the next line"), ("enter", "ENTER at the end of a line (a line is inserted)"),
               ("insert-line", "insert-line"), ("delete-line", "delete-line"),
               ("scroll-down", "DOWN that scrolls a 60-line store"),
               ("down-mid-full", "DOWN between two lines mid-screen, 60-line store"),
               ("up-scroll", "UP that scrolls the view up, 60-line store"),
               ("enter-bottom", "ENTER on the last line of a full screen")]


def vcost_once(env, ck, which):
    m, con = env.m, env.con
    texts, name, idx, setup, key = vcost_spec(which)
    env.boot()
    store_set(env, store_bytes(texts))
    if open_view(env, ck, "EDIT " + name) is None:
        return None
    for code in setup:
        con.key(code, maxi=VIEW_MAXI)
    m.tstates_reset()
    con.key(key, maxi=VIEW_MAXI)
    return m.tstates()


@new_case("edit-typing-cost", "N12", "T-states from key delivery (latch write) to the next key wait, interrupts included, for a key at the end "
                                    "of a short line, in the middle of a 100-character line, on a 3-row line, DELETE, LEFT, UP in a "
                                    "wrapped line, DOWN, ENTER, insert-line, delete-line and a DOWN that scrolls, in the view; each figure "
                                    "taken twice and equal; recorded, no threshold (the gate is set from this first measurement)",
          parts=("a", "b"))
@guarded
def edit_typing_cost(env, part, ck):
    names = VCOST_CASES[0::2] if part == "a" else VCOST_CASES[1::2]
    table = {}
    for which, what in names:
        a = vcost_once(env, ck, which)
        if a is None:
            return
        b = vcost_once(env, ck, which)
        table[which] = [a, b]
        ck.eq("%s repeatable" % which, a, b)
    ck.data = {"t_states": table, "what": dict(VCOST_CASES)}
    ck.note(", ".join("%s %d" % (k, v[0]) for k, v in table.items()))


# ===================================================================== N13 store full in the view
def full_store(room, tail):
    """Store texts: one-row filler lines and then `tail`, with `room` bytes left below STORE_LIMIT."""
    fill = STORE_CAP - room - sum(len(t) + 1 for t in tail)
    lines = []
    while fill >= 32:
        lines.append("f%03d " % len(lines) + "x" * 26)             # 31 characters + CR = 32 bytes
        fill -= 32
    if fill:
        lines.append("y" * (fill - 1))
    return lines + tail


N13_SEQS = {
    # READING (section 5, last paragraph before Leaving): "A full store refuses the change that would overflow it: the line and
    # the store stay as they were and STORE FULL shows on the status row until the next key."  The change is the write-back of a
    # grown line when it is left, and the insertion of a line by ENTER or insert-line (1 byte: the terminator).  The sequences
    # never ask for a write-back and an insertion together, and never BREAK with a write-back that does not fit: the text does not
    # say what happens then.
    "enter": (1, [": NF 1 ;"], "NF", K(ENTER, ENTER, INSERT_LINE, "x", UP, DELETE_LINE, ENTER, BREAK)),
    "grow": (3, [": NG 1 ;", "tail"], "NG", K("abcde", DOWN, (DELETE, 2), DOWN, UP, UP, BREAK)),
    "full": (0, [": NF 1 ;", "last"], "NF", K(ENTER, INSERT_LINE, "ab", DOWN, DELETE_LINE, ENTER, "z", BREAK)),
}


@new_case("edit-store-full", "N13", "in the view, a change that would overflow the store is refused: the line and the store stay as they were, "
                                    "STORE FULL shows on the status row until the next key, nothing at or above $F000 changes; a change that "
                                    "fits exactly is made; freeing space (delete-line) allows the change again",
          parts=tuple(N13_SEQS))
@guarded
def edit_store_full(env, part, ck):
    room, tail, name, keys = N13_SEQS[part]
    texts = full_store(room, tail)
    env.boot()
    pat = seed_above_limit(env)
    store_set(env, store_bytes(texts))
    if open_view(env, ck, "EDIT " + name) is None:
        return
    model = VModel(texts, cur=len(texts) - len(tail), cap=STORE_CAP)
    ck.eq("the test store leaves %d byte(s)" % room, STORE_CAP - model.store_len(), room)
    vs = VS(RealIO(env), model, name)
    vs.check_now()
    vs.keys(keys)
    ck.true("the sequence ends with BREAK", vs.model.exited)
    check_left(env, ck, "BREAK", vs.model.store_bytes())
    ck.true("STORE_END %04X is not past STORE_LIMIT" % store_end(env), store_end(env) <= STORE_LIMIT)
    eq_bytes(ck, "$F000-$F0FF untouched", read_above_limit(env), pat)
    ck.note("room %d: %d keys, refusals showed STORE FULL on the status row" % (room, vs.n))


# ---------------------------------------------------------------------------------------------------- the model's self-test
def selftest():
    """No emulator: the sequences of the view cases are driven through VS against FakeIO (a view that is the model itself,
    taking each fork of an open outcome in turn), which finds test bugs before the ROM exists: a typo, a key sequence that
    reaches a state the spec leaves open (ModelAmbiguous), a line needing a 5th row, an address that does not settle.  Then the
    checker is shown to see a wrong store, a wrong row, a wrong cursor cell and a missing STORE FULL."""
    import random
    seqs = []
    for name, fn in N7_SEQS.items():
        store, nm, idx, keys = fn()
        seqs.append(("N7 " + name, store, idx, keys, None))
    seqs.append(("N8 marked", N8_BASE, 0, N8_MARKED, None))
    seqs.append(("N8 unchanged", N8_BASE, 0, N8_UNCHANGED, None))
    seqs.append(("N8 error", N8_BASE + ["4 ."], 0, N8_ERROR, None))
    head, text, keys = n8_selfmark()
    seqs.append(("N8 selfmark", [head], 0, keys, None))
    for name, (room, tail, nm, keys) in N13_SEQS.items():
        texts = full_store(room, tail)
        assert STORE_CAP - sum(len(t) + 1 for t in texts) == room, "full_store(%d) is off" % room
        seqs.append(("N13 " + name, texts, len(texts) - len(tail), keys, STORE_CAP))
    for text in N6_STORE + big_store() + [": BB " + GROW[:95], ": BB " + "a" * 65, ": BB " + WRAP71, WRAP70]:
        wrows(text)
    ok, total = True, 0
    for label, store, idx, keys, cap in seqs:
        for seed in range(25):
            rng = random.Random(seed)

            class Pick(FakeIO):
                def pick(self, forks):
                    return forks[rng.randrange(len(forks))]

            vs = VS(Pick(VModel(store, cur=idx, cap=cap)), VModel(store, cur=idx, cap=cap), label)
            try:
                vs.check_now()
                vs.keys(keys)
                if not vs.model.exited:
                    raise ViewFail("no BREAK")
                total += vs.n
            except (ViewFail, ModelAmbiguous) as e:
                print("selftest FAIL %s (seed %d): %s" % (label, seed, e))
                ok = False
                break
    # the checker must see differences
    store = [": AA 1 ;", ": BB 2 ;", ": CC 3 ;"]
    model = VModel(store, cur=1)
    good = FakeIO(VModel(store, cur=1)).observe()
    checks = [("a wrong store byte", lambda o: setattr(o, "store", o.store[:-1] + b"\x00")),
              ("a wrong screen row", lambda o: o.rows.__setitem__(1, "XX")),
              ("a wrong status row", lambda o: o.rows.__setitem__(23, "LINE 9/3")),
              ("a wrong cursor cell", lambda o: setattr(o, "flash", [(0, 0)])),
              ("two cursor cells", lambda o: setattr(o, "flash", o.flash + [(5, 5)]))]
    errs, _ = check_view(model, good, 0)
    if errs:
        print("selftest FAIL: the good observation was refused: %s" % errs)
        ok = False
    for what, mutate in checks:
        o = FakeIO(VModel(store, cur=1)).observe()
        mutate(o)
        errs, _ = check_view(model, o, 0)
        if not errs:
            print("selftest FAIL: %s was not seen" % what)
            ok = False
    full = VModel(full_store(0, [": NF 1 ;"]), cur=len(full_store(0, [": NF 1 ;"])) - 1, cap=STORE_CAP)
    refused = full.step(ENTER)[0]
    o = FakeIO(refused).observe()
    o.rows[23] = "LINE %d/%d" % (refused.cur + 1, refused.n())
    errs, _ = check_view(refused, o, 0)
    if not errs:
        print("selftest FAIL: a missing STORE FULL was not seen")
        ok = False
    print("edtest selftest: %s (%d sequences x 25 seeds, %d keys checked, checker sensitivity %d cases)" % (
        "ok" if ok else "FAILED", len(seqs), total, len(checks) + 1))
    return 0 if ok else 1


# ---------------------------------------------------------------------------------------------------- the runner
ALT_BUILD = {("edit-refusals", "noexrom"): "stock-shaped EXROM"}    # parts that run on a copy of the build with another EXROM
TAPE_PARTS = {("cr-whitespace", p) for p in ("load-cr", "load-nocr", "load-full", "load-error")}   # parts that play a tape (realtape-open)


def reboot_emulator(m):
    """A new ZEsarUX process for the same Machine object.  A second `realtape-open` in the same emulator plays nothing
    (measured: the second LOAD-TEXT found no tape, and the machine was reset as the open does), so a part that played a tape
    leaves the worker with a fresh emulator for the next task."""
    m._own_snapdir = False                          # (stop() would remove the ROM file and the snapshot start() needs)
    try:
        m.stop()
    finally:
        m._own_snapdir = True
    m.start()


def run_task(m, task):
    name, part = task
    for n, _, fn, _ in CASES:
        if n == name:
            t0 = time.time()
            try:
                r = fn(Env(m), part)
            finally:
                if task in TAPE_PARTS:
                    reboot_emulator(m)
            r["wall"] = time.time() - t0
            return r
    raise KeyError(name)


def select(only, group="both"):
    return [c for c in CASES if (group == "both" or GROUPS[c[0]][0] == group)
            and (not only or any(o in c[0] or o == GROUPS[c[0]][1] for o in only))]


def _cut(text, n):
    return text if len(text) <= n else text[:n - 3] + "..."


def suite(build, only=(), json_out=None, verbose=False, group="both", workers=None):
    """The cases as one fharness.Suite (tools/run_tests.py; run_all runs it alone).  The ALT_BUILD parts run on the
    stock-shaped EXROM."""
    cases = select(only, group)
    if not cases:
        raise ValueError("no case matches %r in group %s" % (only, group))
    tasks = [(c[0], p) for c in cases for p in c[3]]
    return fh.Suite("editor", tasks, run_task,
                    lambda res, wall: report(cases, tasks, res, wall, build, json_out, verbose, group, workers),
                    stock=[i for i, t in enumerate(tasks) if t in ALT_BUILD])


def run_all(build, workers, port0, only, json_out, verbose=False, group="both"):
    return suite(build, only, json_out, verbose, group, workers).run_alone(build, workers, port0)


def report(cases, tasks, res, wall, build, json_out, verbose, group, workers):
    out, failed = [], 0
    by = {}
    for (name, part), r in zip(tasks, res):
        by.setdefault(name, []).append((part, r))
    tally = {}
    for name, title, _, parts in cases:
        group_of, num = GROUPS[name]
        rs = by[name]
        ok = all(r["ok"] for _, r in rs)
        failed += not ok
        tally.setdefault(group_of, [0, 0])[0] += ok
        tally[group_of][1] += 1
        if len(rs) == 1:
            detail = rs[0][1]["detail"]
        elif ok:
            detail = "%d parts: %s" % (len(rs), " | ".join("[%s] %s" % (p, r["detail"]) for p, r in rs))
        else:
            detail = " | ".join("[%s] %s" % (p, r["detail"]) for p, r in rs if not r["ok"])
        wall_case = sum(r["wall"] for _, r in rs)
        out.append(dict(case=name, group=group_of, num=num, title=title, ok=ok, detail=detail, wall=round(wall_case, 2),
                        parts=[dict(part=p, ok=r["ok"], detail=r["detail"], wall=round(r["wall"], 2), port=r["worker"],
                                    data=r.get("data") or None) for p, r in rs]))
        line = detail
        if ok and not verbose:                  # (the full text of every part is in the JSON, and with --verbose)
            first = rs[0][1]["detail"]
            line = _cut(first, 150 if len(rs) == 1 else 110)
            if len(rs) > 1:
                line = "%d parts (%s): %s" % (len(rs), ", ".join(p for p, _ in rs), line)
        elif not ok and not verbose:                # (a failing case: the first thing that differs in each failing part)
            bad = [(p, r["detail"]) for p, r in rs if not r["ok"]]
            firsts = [(p, d.split("; ")[0]) for p, d in bad]
            if len(firsts) > 1 and len({d for _, d in firsts}) == 1:
                line = "%d of %d parts: %s" % (len(firsts), len(rs), firsts[0][1])
            elif len(rs) == 1:
                line = firsts[0][1]
            else:
                line = " | ".join("[%s] %s" % fd for fd in firsts)
            line = _cut(line, 300)
        print("%s %-3s %-3s %-22s %s  [%.1f s]" % ("PASS" if ok else "FAIL", group_of, num or "", name, line, wall_case), flush=True)
    typing, vtyping = None, None
    for c in out:
        if c["case"] == "typing-cost":
            typing = {p["part"]: p["data"] for p in c["parts"] if p.get("data")}
        if c["case"] == "edit-typing-cost":
            vtyping = {p["part"]: p["data"] for p in c["parts"] if p.get("data")}
    if typing:
        print_typing(typing)
    if vtyping:
        print_view_typing(vtyping)
    harness_error = all(r["detail"].startswith("TASK FAILED") for r in res) or any(
        r["detail"].startswith(("worker on port", "never ran")) for r in res)
    print("edtest: %d/%d cases pass (%s); %d tasks; wall %.1f s (%d worker(s))" % (
        len(out) - failed, len(out), ", ".join("%s %d/%d" % (g, t[0], t[1]) for g, t in sorted(tally.items(), reverse=True)),
        len(tasks), wall, min(workers or fh.default_workers(), len(tasks))))
    if json_out:
        os.makedirs(os.path.dirname(os.path.abspath(json_out)), exist_ok=True)
        json.dump(dict(build=build, failed=failed, group=group, groups={g: dict(passed=t[0], total=t[1]) for g, t in tally.items()},
                       cases=out, typing=typing, view_typing=vtyping, wall=round(wall, 2), workers=workers or fh.default_workers()),
                  open(json_out, "w"), indent=1)
    return (2 if harness_error else (1 if failed else 0))


def print_typing(typing):
    print("typing cost, T-states from key delivery to the next key wait (two runs each, equal):")
    names = [k for k, _ in COST_CASES]
    print("  %-14s %12s    %s" % ("", "32 columns", "what"))
    for k in names:
        c = typing.get("32", {}).get("t_states", {}).get(k, [None])[0]
        print("  %-14s %12s    %s" % (k, c, dict(COST_CASES)[k]))


def print_view_typing(vtyping):
    print("typing cost in the view, T-states from key delivery to the next key wait (two runs each, equal):")
    for k, what in VCOST_CASES:
        c = next((d["t_states"][k][0] for d in vtyping.values() if k in d.get("t_states", {})), None)
        print("  %-14s %12s    %s" % (k, c, what))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"), help="directory with forth_boot_rom0.bin (DIR or DIR/build)")
    ap.add_argument("--group", choices=("old", "new", "both"), default="both",
                    help="old: the 19 cases that characterise the console editor; new: the step-E cases N1-N3, N5-N10, N12-N13; both (default)")
    ap.add_argument("--workers", type=int, default=None, help="emulators in parallel (default: fharness.default_workers())")
    ap.add_argument("--port", type=int, default=fh.PORT_LO, help="first ZRCP port (%d-%d)" % (fh.PORT_LO, fh.PORT_HI))
    ap.add_argument("--json", default=os.path.join(ROOT, "build", "edtest.json"), help="write the results here (default build/edtest.json)")
    ap.add_argument("--selftest", action="store_true", help="no emulator: run the new cases' key sequences against the model of the view")
    ap.add_argument("-v", "--verbose", action="store_true", help="print the full detail of passing cases too")
    ap.add_argument("only", nargs="*", help="run the cases whose name contains one of these (or whose number, N5, is this)")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    try:
        build = fh.resolve_build(a.build)
        return run_all(build, a.workers, a.port, a.only, a.json, a.verbose, a.group)
    except (FileNotFoundError, ValueError, RuntimeError) as e:
        print("edtest: harness error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
