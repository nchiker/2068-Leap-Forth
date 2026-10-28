#!/usr/bin/env python3
"""edtest.py - the editor screen oracle (audit item T12, docs/V2/FORTH_V2_REUSE_AUDIT.md section 6.3), for step E.

Characterises the console editor of the build it is given: what the CURRENT code does, key by key, on the screen and in
memory, so that step E (a rebuild of the console and editor, audit section 4.3) can be checked against it.  Every case
asserts what the current build does, exactly (screen rows, edit line, cursor cell, memory); a case that looks like a
defect still asserts the current behaviour (the defects are listed in the report that came with this file, not fixed).
A rebuilt editor is expected to FAIL the cases that describe behaviour step E changes on purpose; each such failure is a
line to decide on, not a regression by itself.

RUN   python3 -I tools/edtest.py [--build DIR] [--workers N] [--port P] [--json OUT] [-v] [substring ...]
      DIR holds forth_boot_rom0.bin and graphics_exrom.bin (default: build/; DIR or DIR/build, as tools/fharness.py, so
      the images of an older build in a git worktree work).  Substrings select cases by name.  One PASS/FAIL line per
      case with its detail (a passing case's detail is cut short; -v prints it whole), then a summary.  JSON (default build/edtest.json): every case with its parts, the typing-cost
      numbers, the wall times.  Exit 0 = all cases pass, 1 = any case fails, 2 = harness error (bad build directory, port
      in use, no emulator could run a task).  Ports P .. P+workers-1, default 10900-10919 (fharness.py's range).

Derived from 2068-Leap-C tools/shelltest.py at its Phase 5 state: its case/expect registry, `full_reference` (after every
key the screen equals a full redraw) and the `redraw-oracle` and `typing-cost` cases are ported; copied and adapted, not
imported: nothing here reads or writes ~/2068-Leap-C.  Leap-C's other cases belong to its C shell and are not used.

What is real: the assembled images (booted as fharness does: forth_boot_rom0.bin and graphics_exrom.bin as one ROM file),
the editor (core/editor.asm), the interpreter, the workspace (core/recall.asm), the interrupt service and the keyboard
matrix scan.  What is substituted: every case runs from the snapshot of the booted machine (fharness.Machine.restore);
`key()` writes the interrupt routine's latch (KBD_LASTK, KBD_KEYHIT) and `press()` holds keys on the emulated matrix
(ISR, debounce and IO_DECODE_KEY real); the screen is read from RAM and decoded with the ROM's own font by the real
GFX_PUTCHAR / MODE64_PUTCHAR (fharness.screen_rows).  The cases run on fharness.run_pool: one ZEsarUX per worker, a
restored machine for every task; a case with several parts (widths, batches, scenarios) is several tasks.

HOW THE CURSOR IS SHOWN  32 columns: not in the bitmap.  EDITOR_REDRAW draws the line (GFX_PUTCHAR, then GFX_SET_ATTR
ATTR_DEFAULT on every cell of every input row, padded to column 31) and then GFX_INVERT_ATTR on the cursor cell: ink and
paper swapped and FLASH set, so ATTR_DEFAULT $44 (bright, black paper, green ink) becomes $E0; the ULA blinks it.  A cursor
column of 32 (the line fills its last row) is out of range: GFX_INVERT_ATTR does nothing and NO cursor is shown.  64
columns (GFX_MODE 2): the attribute byte does not exist; MODE64_PUTCHAR_XOR flips all 64 bits of the cell, a static block.
The screen reader shows it as INVERSE_MARK + the character under it, or as the block character (U+258F, code 143's glyph)
over a blank; `view()` below turns that back into a cursor cell and the plain text.

THE WRAP MODEL (wrap_model, cursor_model, Ed) is derived from core/editor.asm and confirmed on this build by the
wrap-model case.  WRAP_CALC / WRAP_CALC64: a row holds W = 32 (64) characters.  From the row's first character: if no more
than W characters remain, they are the last row.  Otherwise look at the characters at offsets W-1 down to 1 (offset 0 and
offset W are NOT looked at) for the last space: found at offset p -> the row shows p characters and p + 1 are consumed (the
space is never drawn); none found -> the row shows W characters and W are consumed (a hard break; a space that is the
(W+1)th character then starts the next row).  At most FWRAP_MAX_ROWS = 4 rows; if after the 4th row characters remain,
FWRAP_OVERFLOW = 1 (a 5th row would be needed) and FWRAP_COUNT is still 4.  EDIT_CURSOR_TO_ROWCOL: the cursor is on the
first row i for which i is the last row or EDIT_CURSOR < the start of row i + 1; its column is EDIT_CURSOR - start of row i
(so a cursor on a consumed space shows right after the row's last character, and a cursor at the end of a full hard-broken
row rolls onto the next row's column 0).  The screen row of row i is 24 - FWRAP_COUNT + i.  EDITOR_PROCESS_KEY: printable
codes 32-126 are inserted at EDIT_CURSOR if EDIT_LEN < EDIT_MAX_LEN (128); WRAP_CALC is run on the result, and if
FWRAP_OVERFLOW is set the insert is undone and the key ignored (the wrap table is then left describing the refused
line: FWRAP_OVERFLOW stays 1 until the next redraw).  DELETE (8) removes the character left of the cursor, LEFT (1) and
RIGHT (4) move it, ENTER (13) ends the line; every other code below 32 is ignored.  Grow: when the new FWRAP_COUNT is
larger than FWRAP_OLD_COUNT, for each new row the whole screen scrolls up one row (GFX_SCROLL_OUTPUT_UP, row 0 is lost)
and PRINT_ROW is decremented if PRINT_ROW >= 24 - old count, i.e. if the new row is not still blank (PRINT_ROW is the next
output row).  Shrink: the rows no longer used are cleared (GFX_CLEAR_ROW); nothing scrolls back.

THE FULL REDRAW (the reference of the redraw-oracle case; full_reference).  From the editor waiting for a key, with the
whole machine put on a checkpoint first (fharness.Machine.checkpoint / rollback), the reference screen is drawn by:
  1. call WRAP_CALC (WRAP_CALC64 in 64 columns) for the current EDIT_BUF / EDIT_LEN, which sets FWRAP_COUNT;
  2. FWRAP_OLD_COUNT := FWRAP_COUNT, so the redraw decides "no growth, no shrink": nothing scrolls, no row is cleared by it;
  3. rows 20-23 (the 4 rows the input can ever use, 24 - FWRAP_MAX_ROWS ... 23) are blanked directly: all 8 pixel lines
     of every cell zero (both display files in 64 columns) and, in 32 columns, every attribute byte of those rows set to
     ATTR_DEFAULT;
  4. call EDITOR_REDRAW (it dispatches on GFX_MODE to EDITOR_REDRAW64), which draws every wrapped row, blank-padded and
     with ATTR_DEFAULT, and the cursor;
  5. read the screen: $4000-$5AFF (32 columns: bitmap and attributes, 6912 bytes) or $4000-$77FF (64 columns: both display
     files and the attribute area, 14336 bytes), then roll the machine back.
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

CURRENT BEHAVIOURS THAT LOOK LIKE DEFECTS (asserted as they are; the case that shows each in brackets)
  * 64 columns: EDITOR_REDRAW64 hangs when the line grows onto a row that holds output and the screen must scroll (PRINT_ROW
    22, 2 -> 3 rows): it keeps FWRAP_OLD_COUNT's address in HL across MODE64_SCROLL_OUTPUT_UP, which destroys HL [wrap-scroll].
  * 64 columns: EDITOR_PROCESS_KEY's room check calls WRAP_CALC (32 columns), so a line that fits 3 rows of 64 is refused at the
    character that needs a 5th 32-column row [console-64col limit].
  * A line that exactly fills its last row (32, 64, 96, 128 characters) puts the cursor at column 32 (64): out of range, no
    cursor is shown [line-full hard, wrap-model].
  * WORKSPACE_APPEND tests the high byte of the new length against LOADTEXT_MAX_LEN / 256 + 1, so it writes up to 255 bytes
    past LOADTEXT_BUF + 8192 [workspace-append limit]; an empty line appends a separator space each time [workspace-append].
  * Forth has no BREAK check in the interpreter: only the word BREAK? sees the key [break-running].
  * After a refused key the wrap table keeps the refused line (FWRAP_OVERFLOW stays 1, 64 columns: 32-column rows) and the
    screen is not redrawn until the next accepted key; harmless as far as seen [line-full, console-64col].

EMULATOR LIMITS: there is no hardware here.  Every verdict is ZEsarUX's (its Z80, its ULA/SCLD and paging, its keyboard
matrix and its interrupt timing) running the ROM images; the screen is read from RAM, not from a display, so a colour,
FLASH-blink or timing effect that exists only on a real TV is not seen (the FLASH attribute bit is read, its blinking is
not), the border colour is read from the ROM's shadow of port $FE, and a real keyboard's contact bounce is not simulated.
A pass says what the emulator did, not that real hardware agrees.
"""
import argparse
import json
import os
import random
import sys
import time

sys.dont_write_bytecode = True
HERE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE_DIR)                      # python3 -I does not put the script's directory on sys.path
import fharness as fh                                                       # noqa: E402
from fharness import CTRL_KEYS, INVERSE_MARK, KEY_ENTER, Z_CAPS, Z_SPACE    # noqa: E402

ROOT = fh.ROOT
BANNER = "2068-FORTH"                   # rom/forth_boot.asm BANNER
LEFT, DOWN, UP, RIGHT, DELETE, INSERT_LINE, DELETE_LINE, BREAK, ENTER = 1, 2, 3, 4, 8, 0x0B, 0x0F, 0x10, 13
MAX_LEN, MAX_ROWS = 128, 4              # EDIT_MAX_LEN, FWRAP_MAX_ROWS
CURSOR_BLOCK = "▏"                 # screen_rows' reading of an all-ones cell (the 64-column cursor over a blank)
LOADTEXT_BUF = 0xD000                   # LOADTEXT_BUF (checked against the symbol in the cases)
UNTYPEABLE = "[\\]^`{|}~"               # printable ASCII Forth's keyboard has no key for (audit step K)
GROW = "abcdefghi " * 10                # 100 characters, 4 rows at 32 columns
GROW64 = "a " + "b" * 64 + "  " + "c" * 29      # 97 characters, 3 rows at 64 columns (and 4 at 32: the room check's)


# ---------------------------------------------------------------------------------------------------- the models
def wrap_model(buf, w):
    """WRAP_CALC / WRAP_CALC64 for `buf` (a str): ([(start, length) ...], overflow).  See the header."""
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


def cursor_model(rows, cursor):
    """EDIT_CURSOR_TO_ROWCOL: (screen row, column) of the cursor for a wrap table."""
    n, i = len(rows), 0
    while i != n - 1 and cursor >= rows[i + 1][0]:
        i += 1
    return 24 - n + i, cursor - rows[i][0]


def screen_model(base, text, cursor, w):
    """(expected 24 rows, expected cursor cells) for a line `text` with the cursor at offset `cursor`, the output rows
    above the input area being `base` (24 rows; those the input area covers are replaced).  A cursor column W is no cell."""
    rows, _ = wrap_model(text, w)
    n = len(rows)
    exp = list(base)
    for r in range(24 - n, 24):
        exp[r] = ""
    for i, (s, ln) in enumerate(rows):
        exp[24 - n + i] = text[s:s + ln].rstrip(" ")
    r, c = cursor_model(rows, cursor)
    return exp, ([(r, c)] if c < w else [])


class Ed:
    """The editor's state as the code above defines it: text, cursor, the display width, and the text (and width) the wrap
    table currently describes: it differs from `text` after a key refused because the line would need a 5th row.  The
    room check of EDITOR_PROCESS_KEY calls WRAP_CALC, the 32-column routine, in 64-column mode too (core/editor.asm
    `call WRAP_CALC` after INSERT_CHAR), so a key is accepted by the 32-column rule (ACCEPT_W) whatever the display width,
    and after a refusal the table holds the 32-column rows of the refused line."""
    ACCEPT_W = 32

    def __init__(self, w, text="", cursor=None):
        self.w, self.text = w, text
        self.cursor = len(text) if cursor is None else cursor
        self.table_text, self.table_w = text, w
        self.refused = None

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
            if wrap_model(nb, self.ACCEPT_W)[1]:
                self.refused, self.table_text, self.table_w = "rows", nb, self.ACCEPT_W
                return False
            self.text, self.cursor = nb, c + 1
        else:
            return False
        self.table_text, self.table_w = self.text, self.w
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


def view(m, mode64=False):
    """The screen as text with the cursor taken out: View(rows, cursor cells, odd attributes).  32 columns: rows are
    plain text (an inverse or unknown cell would show in them), cursor cells are those with FLASH set (their attribute must
    be the swapped ATTR_DEFAULT; `odd` lists any other attribute that is not ATTR_DEFAULT).  64 columns: the cursor is
    the XOR block (INVERSE_MARK + character, or the block over a blank), taken out of the text; `odd` is empty."""
    if not mode64:
        attrs = m.read(0x5800, 768)
        dflt = m.S.get("ATTR_DEFAULT", 0x44)
        cur = [(i // 32, i % 32) for i, a in enumerate(attrs) if a & 0x80]
        want = ((dflt & 7) << 3 | (dflt >> 3) & 7 | (dflt & 0x40) | 0x80)       # ink and paper swapped, FLASH
        odd = [(i // 32, i % 32, a) for i, a in enumerate(attrs)
               if (a & 0x80 and a != want) or (not a & 0x80 and a != dflt)]
        return View(m.screen_rows(), cur, odd)
    rows, cur = [], []
    for r, s in enumerate(m.screen_rows(mode64=True)):
        out, i = "", 0
        while i < len(s):
            ch = s[i]
            if ch == INVERSE_MARK and i + 1 < len(s):
                cur.append((r, len(out)))
                out += s[i + 1]
                i += 2
                continue
            if ch == CURSOR_BLOCK:
                cur.append((r, len(out)))
                ch = " "
            out += ch
            i += 1
        rows.append(out.rstrip(" "))
    return View(rows, cur, [])


def row_cell(m, row, col):
    """The 8 bitmap bytes of character cell (row, col) of the 32-column screen."""
    return fh.cell_from(m.read(0x4000, 6144), row, col)


def wrap_table(m):
    """(FWRAP_COUNT, [(start, length) ...], FWRAP_OVERFLOW) from memory."""
    S = m.sym
    n = m.read(S("FWRAP_COUNT"), 1)[0]
    st, ln = m.read(S("FWRAP_START"), 4), m.read(S("FWRAP_LEN"), 4)
    return n, [(st[i], ln[i]) for i in range(min(n, 4))], m.read(S("FWRAP_OVERFLOW"), 1)[0]


def read_screen(m, mode64=False):
    """The bytes the oracle compares: $4000-$5AFF, or $4000-$77FF in 64 columns."""
    return m.read(0x4000, 0x3800 if mode64 else 6912)


def first_diff(a, b, mode64=False):
    """Describe the first difference of two read_screen images."""
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            addr = 0x4000 + i
            if addr >= 0x5800 and addr < 0x5B00:
                return "attribute row %d col %d: %02X, reference %02X (%d byte(s) differ)" % (
                    (addr - 0x5800) // 32, (addr - 0x5800) % 32, x, y, sum(p != q for p, q in zip(a, b)))
            second = addr >= 0x6000
            a0 = addr - 0x2000 if second else addr
            line = (a0 >> 8) & 7
            row = ((a0 >> 11) & 3) * 8 + ((a0 >> 5) & 7)
            col = (a0 & 31) + (32 if second else 0)
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

    def boot(self, w=32):
        """The booted machine; w=64: after `64COL`.  Returns the base rows (the output rows above the input area)."""
        self.con.boot()
        if w == 64:
            self.con.type("64COL")
            if not self.con.in_editor():
                raise RuntimeError("no editor after 64COL")
            return [BANNER, "OK"] + [""] * 22
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
        v = view(m, ed.w == 64)
        if v.rows != exp:
            bad = [(r, v.rows[r], exp[r]) for r in range(24) if v.rows[r] != exp[r]]
            ck.true(label + " screen rows", False, "row %d got %s, want %s (%d rows differ)" % (
                bad[0][0], _short(bad[0][1]), _short(bad[0][2]), len(bad)))
        ck.eq(label + " cursor cell", v.cursor, cells)
        ck.eq(label + " stray attributes", v.odd, [])
        if wrap:
            rows, ov = wrap_model(ed.table_text, ed.table_w)
            ck.eq(label + " wrap table", wrap_table(m), (len(rows), rows, int(ov)))


def screen_sig(m, w=32):
    return m.read(0x4000, 0x3800 if w == 64 else 6912)


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


def case(name, title, parts=("-",)):
    def deco(fn):
        CASES.append((name, title, fn, list(parts)))
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
    ck.eq("WORKSPACE_END", m.w16(env.S("WORKSPACE_END")), env.S("LOADTEXT_BUF"))
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


@case("line-full", "128 characters without spaces fit (hard breaks, 4 rows, no cursor shown); the 129th is refused, line and screen "
                   "unchanged; a word-wrapped line that would need a 5th row refuses the character that would (FWRAP_OVERFLOW "
                   "stays set), also in the middle of the line", parts=("hard", "words", "middle"))
def line_full(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    ed = Ed(32)
    if part == "hard":
        type_keys(env, ed, "a" * 127)
        env.check_view(ck, "127 chars", base, ed)
        env.con.key(ord("a"))
        ed.key(ord("a"))
        env.check_view(ck, "128 chars", base, ed)
        ck.eq("rows used", wrap_table(m)[0], 4)
        ck.eq("cursor cells at 128", view(m).cursor, [])
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
        ck.note("127 + 1 = 128 'a' fit in 4 hard-broken rows (no cursor cell at column 32); the 129th 'b' leaves the screen "
                "bytes unchanged; DELETE frees one place and 'b' goes in at the cursor")
    elif part == "words":
        type_keys(env, ed, _words_text())
        env.check_view(ck, "95 chars", base, ed)
        ck.eq("rows, overflow", wrap_table(m)[0::2], (4, 0))
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
        ck.note("3 words of 20 + the 4th and 11 more = 95 characters fill the 4th row; the 96th (z or space) needs a 5th row "
                "and is refused, FWRAP_OVERFLOW stays 1 and the screen is not redrawn until the next accepted key")
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
    out += [("w" * (w // 2)) + " " + ("v" * (w // 2)) + " " + ("u" * (w // 2)) + " tail", GROW, GROW64]
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


@case("wrap-model", "the Python model of WRAP_CALC (word-boundary rule, 32 and 64 columns) predicts the wrap table, the screen rows "
                    "and the cursor cell of every line of a set (assorted words, a word longer than a row, trailing spaces, "
                    "exactly 32 / 64 characters), and of a seeded random walk of keys", parts=("lines32a", "lines32b", "lines64a", "lines64b", "walk32", "walk64"))
def wrap_model_case(env, part):
    ck, m = Check(), env.m
    w = 32 if "32" in part else 64
    base = env.boot(w)
    if part.startswith("lines"):
        lines, shapes = [], []
        for line in model_lines(w):
            ed = Ed(w)
            ed.type(line)
            if ed.text == line:                  # (at 64 columns the 32-column room check refuses some lines: console-64col)
                lines.append(line)
        ck.true("lines the room check accepts", len(lines) >= 25, "only %d" % len(lines))
        lines = lines[0::2] if part.endswith("a") else lines[1::2]
        for line in lines:
            base = env.boot(w)
            ed = Ed(w)
            type_keys(env, ed, line)
            ck.eq("accepted line %r" % line[:24], env.edit_state()[0], line)
            env.check_view(ck, "line %r" % line[:30], base, ed)
            shapes.append(len(wrap_model(line, w)[0]))
        ck.note("%d lines at %d columns, rows used %s; wrap table, rows and cursor cell equal the model" % (
            len(lines), w, " ".join(str(n) for n in shapes)))
    else:
        ed = Ed(w)
        keys = walk_keys(w)
        for code in keys:
            step(env, ck, "walk", base, ed, code)
        ck.note("%d seeded keys at %d columns, final line %r (%d chars, %d rows)" % (
            len(keys), w, ed.text[-30:], len(ed.text), len(wrap_model(ed.text, w)[0])))
    return ck.result()


# ===================================================================== 9 grow / shrink
GS_TEXT = ("alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega")


@case("wrap-grow-shrink", "the input area grows upward row by row as the line wraps (hard breaks and word wrap, 32 and 64 "
                          "columns), the rows above stay as they were, and deleting back clears the rows it no longer uses "
                          "(bitmap and attributes)", parts=("hard32", "words32", "words64"))
def wrap_grow_shrink(env, part):
    ck, m = Check(), env.m
    w = 64 if part.endswith("64") else 32
    base = env.boot(w)
    ed = Ed(w)
    text = "a" * 100 if part == "hard32" else (GS_TEXT if w == 32 else GROW64)
    counts = []
    for ch in text:
        env.con.key(ord(ch))
        ed.key(ord(ch))
        env.check_view(ck, "grow %d" % len(ed.text), base, ed)
        counts.append(len(wrap_model(ed.text, w)[0]))
    ck.eq("growth steps", sorted(set(counts)), list(range(1, max(counts) + 1)))
    ck.eq("rows grow one at a time", [b - a for a, b in zip(counts, counts[1:]) if b != a and b - a != 1], [])
    ck.eq("PRINT_ROW untouched", env.print_pos(), (1 if w == 32 else 2, 0))
    shrink = []
    for _ in range(len(ed.text)):
        env.con.key(DELETE)
        ed.key(DELETE)
        env.check_view(ck, "shrink %d" % len(ed.text), base, ed)
        shrink.append(len(wrap_model(ed.text, w)[0]))
    ck.eq("empty again", env.edit_state(), ("", 0))
    ck.eq("rows 20-23 blank, banner intact", [r for r in view(m, w == 64).rows[2:] if r], [])
    ck.note("%d chars, rows used 1..%d on the way up, back to 1 on the way down; every key checked against the model" % (
        len(text), max(counts)))
    return ck.result()


# ===================================================================== 10 scroll
@case("wrap-scroll", "with output on the rows just above the edit line, a line growing to 2-4 rows scrolls the whole screen up "
                     "(row 0, the banner, is lost) only when the row it claims is not blank, PRINT_ROW follows; shrinking "
                     "does not scroll back; the next output starts at PRINT_ROW.  In 64 columns the same scroll HANGS the editor "
                     "(EDITOR_REDRAW64 keeps FWRAP_OLD_COUNT's address in HL across MODE64_SCROLL_OUTPUT_UP, which destroys HL): "
                     "asserted as the current behaviour",
      parts=("pr3-32", "pr20-32", "pr22-32", "pr3-64", "pr22-64"))
def wrap_scroll(env, part):
    ck, m = Check(), env.m
    scen, w = part.split("-")
    w = int(w)
    start_pr = int(scen[2:])
    base = env.boot(w)
    for i in range(start_pr - (1 if w == 32 else 2)):          # PRINT_ROW starts at 1 (32) or 2 (64: the OK of 64COL)
        env.con.type("%d ." % i)
    pr = env.print_pos()[0]
    ck.eq("PRINT_ROW before", pr, start_pr)
    base = list(view(m, w == 64).rows)
    ed = Ed(w)
    text = "a" * 97 if w == 32 else GROW64
    old, log, hung = 1, [], None
    for ch in text:
        nxt = Ed(w, ed.text, ed.cursor)
        nxt.key(ord(ch))
        new = len(wrap_model(nxt.text, w)[0])
        scrolls = new > old and pr >= 24 - old
        if w == 64 and scrolls:
            try:
                env.con.key(ord(ch), maxi=2_000_000)
            except RuntimeError:
                hung = (len(ed.text) + 1, m.pc())
                break
            ck.true("the 64-column scroll hangs", False, "the key returned")
            break
        env.con.key(ord(ch))
        ed.key(ord(ch))
        if new > old:
            base, pr = grow_scroll(base, pr, old, new)
            log.append((len(ed.text), new, pr))
        old = max(old, new)
        env.check_view(ck, "grow %d" % len(ed.text), base, ed)
        ck.eq("PRINT_ROW at %d" % len(ed.text), env.print_pos()[0], pr)
    if w == 64 and part.endswith("pr22-64"):
        ck.true("the editor hung in EDITOR_REDRAW64's grow loop", hung is not None)
        if hung:
            lo, hi = env.S("EDITOR_REDRAW64.grow_loop64"), env.S("EDITOR_REDRAW64.count_settled64")
            ck.true("PC inside EDITOR_REDRAW64.grow_loop64 .. count_settled64", lo <= hung[1] < hi, "PC=%04X" % hung[1])
            ck.eq("HL is no longer FWRAP_OLD_COUNT's address", m.regs()["HL"] != env.S("FWRAP_OLD_COUNT"), True)
            ck.eq("FWRAP_OLD_COUNT, FWRAP_COUNT, PRINT_ROW at the hang", (env.u8("FWRAP_OLD_COUNT"), env.u8("FWRAP_COUNT"),
                                                                       env.u8("PRINT_ROW")), (2, 3, pr - 1))
            ck.note("%s: the %dth character grows the line from 2 to 3 rows with PRINT_ROW 22: the scroll is done (PRINT_ROW 21), "
                    "then HL (clobbered by MODE64_SCROLL_OUTPUT_UP) is used as FWRAP_OLD_COUNT's address and the loop never "
                    "ends (PC in grow_loop64); the machine never returns to the key wait" % (part, hung[0]))
        return ck.result()
    ck.true("no hang", hung is None)
    for _ in range(len(ed.text) - 1):
        env.con.key(DELETE)
        ed.key(DELETE)
        env.check_view(ck, "shrink %d" % len(ed.text), base, ed)
    ck.eq("PRINT_ROW after shrinking", env.print_pos()[0], pr)
    env.con.key(KEY_ENTER)
    base = list(base)
    base[pr] = "A ?"
    ck.eq("after ENTER: rows", view(m, w == 64).rows[:pr + 2], base[:pr + 2])
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
    n = m.w16(m.sym("WORKSPACE_END")) - m.sym("LOADTEXT_BUF")
    return m.read(m.sym("LOADTEXT_BUF"), n).decode("latin-1")


@case("workspace-append", "each committed line (an error line and an empty line included) is appended to the workspace at LOADTEXT_BUF "
                          "with one space before it if the workspace is not empty; WORKSPACE_END follows; the bytes beyond stay "
                          "zero; a line of 128 characters is appended whole; the length test looks at the high byte only (an append "
                          "may run past LOADTEXT_BUF + 8192 by up to 255 bytes)", parts=("append", "limit"))
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
            model = model + (" " if model else "") + line
            ck.eq("workspace after %r" % line, ws_text(m), model)
            ck.eq("WORKSPACE_END after %r" % line, m.w16(env.S("WORKSPACE_END")), buf + len(model))
        ck.eq("zero beyond", m.read(buf + len(model), 32), bytes(32))
        long = ("a" * 7 + " ") * 16
        con.type(long)
        model = model + " " + long
        ck.eq("128-character line appended whole", ws_text(m), model)
        ck.note("workspace %r, 128-char line appended whole (workspace %d bytes); an empty line adds just its separator" % (
            model[:44], len(model)))
    else:
        end = buf + 8192 - 16
        m.poke16(env.S("WORKSPACE_END"), end)
        con.type("1234567890123456789012")
        ck.eq("22-char line at 16 bytes from the end: WORKSPACE_END", m.w16(env.S("WORKSPACE_END")), end + 1 + 22)
        ck.eq("the line, a space before it, from the old end", m.read(end, 23), b" 1234567890123456789012")
        ck.eq("its last 7 characters are in $F000-$F006, past LOADTEXT_BUF + 8192", m.read(buf + 8192, 7), b"6789012")
        env.boot()
        m.poke16(env.S("WORKSPACE_END"), buf + 8432)
        con.type("A" * 100)
        ck.eq("refused when the high byte of (length + line + 1) reaches 33", m.w16(env.S("WORKSPACE_END")), buf + 8432)
        ck.note("current behaviour: an append that ends at workspace length 8193-8447 is written ($F000-$F0FE, past the "
                "end of the workspace); only length >= 8448 is refused")
    return ck.result()


# ===================================================================== 13 recall
@case("recall", "after `: SQ DUP * ;`, `0 RECALL` (RECALL takes a definition NUMBER, not a name) puts the definition in the edit line "
                "with the cursor at its end; editing it and ENTER redefines SQ and appends the new text to the workspace; "
                "LIST-DEFS lists both copies; a number out of range and a definition longer than 128 characters are no-ops")
def recall(env, part):
    ck, m = Check(), env.m
    base = env.boot()
    con = env.con
    con.type(": SQ DUP * ;")
    con.type("3 SQ .")
    ck.eq("old SQ: 3 SQ .", view(m).rows[:4], [BANNER, "OK", "9 OK", ""])
    con.type("0 RECALL")
    ed = Ed(32, ": SQ DUP * ;")
    ck.eq("recalled: edit line, cursor", env.edit_state(), (": SQ DUP * ;", 12))
    ck.eq("recalled: rows", view(m).rows[:4], [BANNER, "OK", "9 OK", "OK"])
    base = view(m).rows
    base[23] = ""
    env.check_view(ck, "recalled", base, ed)
    ck.eq("RECALL_PENDING after the editor took it", env.u8("RECALL_PENDING"), 0)
    for code in [LEFT, LEFT]:
        step(env, ck, "edit", base, ed, code)
    type_keys(env, ed, " DUP *", ck, "edit", base)
    ck.eq("edited line", env.edit_state(), (": SQ DUP * DUP * ;", 16))
    con.key(ENTER)
    ck.eq("after ENTER: edit line", env.edit_state(), ("", 0))
    ck.eq("after ENTER: rows", view(m).rows[:6], [BANNER, "OK", "9 OK", "OK", "OK", ""])
    ws = ws_text(m)
    ck.eq("workspace", ws, ": SQ DUP * ; 3 SQ . 0 RECALL : SQ DUP * DUP * ;")
    con.type("3 SQ .")
    ck.eq("new SQ: 3 SQ .", view(m).rows[5], "81 OK")
    con.type("LIST-DEFS")
    rows = view(m).rows
    ck.eq("LIST-DEFS", rows[6:9], ["0: : SQ DUP * ;", "1: : SQ DUP * DUP * ;", "OK"])
    con.type("2 RECALL")
    ck.eq("out of range: edit line", env.edit_state(), ("", 0))
    ck.eq("out of range: rows", view(m).rows[9:12], ["OK", "", ""])
    # a definition longer than 128 characters (two lines)
    env.boot()
    con.type(": LD " + "1 DROP " * 14)
    con.type("1 DROP " * 14 + ";")
    ck.true("long definition: more than 128 characters in the workspace", len(ws_text(m)) > MAX_LEN)
    con.type("0 RECALL")
    ck.eq("long definition: RECALL does nothing", env.edit_state(), ("", 0))
    con.type("LIST-DEFS")
    ck.eq("long definition: LIST-DEFS shows 20 characters", view(m).rows[4], "0: : LD 1 DROP 1 DROP 1")
    ck.note("recalled ': SQ DUP * ;' cursor 12; edited to ': SQ DUP * DUP * ;'; 3 SQ . gave 9 before, 81 after; both copies listed; "
            "workspace %r" % ws)
    return ck.result()


# ===================================================================== 14 64 columns
@case("console-64col", "after `64COL` the editor wraps at 64 columns (the screen equals the model; the cursor is the XOR block); output "
                       "goes on in 64 columns; `32COL` returns to 32 columns with the screen kept; the room check still counts "
                       "32-column rows, so a line of three 40-character words (3 rows of 64) is refused at its 106th character",
      parts=("type", "mode", "limit"))
def console_64col(env, part):
    ck, m = Check(), env.m
    con = env.con
    con.boot()
    ck.eq("GFX_MODE before", env.u8("GFX_MODE"), 0)
    con.type("64COL")
    ck.eq("GFX_MODE after 64COL", env.u8("GFX_MODE"), 2)
    rows64 = m.screen_rows(mode64=True)
    ck.eq("64-column rows 0-2", rows64[:3], [BANNER, "OK", ""])
    v = view(m, True)
    ck.eq("cursor at row 23 column 0", v.cursor, [(23, 0)])
    ck.true("editor waiting", con.in_editor())
    base = [BANNER, "OK"] + [""] * 22
    if part == "type":
        ed = Ed(64)
        text = "the quick brown fox jumps over the lazy dog " + "and then it sleeps in the sun until it is dark outside. ok"
        type_keys(env, ed, text, ck, "64", base)
        ck.eq("rows used", len(wrap_model(ed.text, 64)[0]), 2)
        for code in [LEFT] * 20 + [ord("Q"), DELETE, DELETE]:
            step(env, ck, "64 edit", base, ed, code)
        ck.note("%d characters typed, 2 rows of up to 64 columns; wrap table, rows and cursor block equal the model" % len(text))
    elif part == "limit":
        ed = Ed(64)
        text = ("x" * 40 + " ") * 2 + "x" * 40
        ck.eq("the 64-column wrap of the whole line", len(wrap_model(text, 64)[0]), 3)
        ck.eq("the 32-column wrap of it overflows", wrap_model(text, 32)[1], True)
        type_keys(env, ed, text, ck, "limit", base)
        ck.eq("accepted characters", len(env.edit_state()[0]), 105)
        ck.eq("refused: FWRAP_OVERFLOW, FWRAP_COUNT", (env.u8("FWRAP_OVERFLOW"), env.u8("FWRAP_COUNT")), (1, 4))
        ck.note("the 106th character of 'x'*40 + ' ' twice + 'x'*40 (122 characters, 3 rows of 64) is refused: WRAP_CALC (32 columns) "
                "is what the room check runs; the table is left with the 32-column rows (count 4, overflow 1)")
    else:
        con.type("1 2 + .")
        ck.eq("output in 64 columns", m.screen_rows(mode64=True)[:4], [BANNER, "OK", "3 OK", ""])
        con.type("32COL")
        ck.eq("GFX_MODE after 32COL", env.u8("GFX_MODE"), 0)
        ck.eq("32-column rows 0-4", m.screen_rows()[:5], [BANNER, "OK", "3 OK", "OK", ""])
        ck.eq("32-column cursor", view(m).cursor, [(23, 0)])
        ck.eq("32-column attributes", view(m).odd, [])
        ed = Ed(32)
        type_keys(env, ed, "x" * 40, ck, "32 again", [BANNER, "OK", "3 OK", "OK"] + [""] * 20)
        ck.note("64COL: GFX_MODE 2 and the screen redrawn in 64 columns (banner, OK); 32COL back to GFX_MODE 0 with rows "
                "[banner, OK, '3 OK', OK] kept; typing wraps at 32 again")
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
def blank_rows(m, r0, r1, mode64):
    """Rows r0..r1-1 blanked directly: all pixel lines zero (both display files in 64 columns), 32 columns: attributes
    ATTR_DEFAULT."""
    for r in range(r0, r1):
        y0 = r * 8
        base = 0x4000 + (((y0 & 0xC0) << 5) | ((y0 & 0x38) << 2))
        for k in range(8):
            m.write(base + 0x100 * k, bytes(32))
            if mode64:
                m.write(base + 0x100 * k + 0x2000, bytes(32))
        if not mode64:
            m.write(0x5800 + r * 32, bytes([m.S.get("ATTR_DEFAULT", 0x44)]) * 32)


def full_reference(m, mode64):
    """The screen a full redraw draws from the current editor state (header, THE FULL REDRAW); the machine is put back
    exactly as it was.  Returns the bytes of read_screen."""
    S = m.sym
    cp = m.checkpoint("oracle")
    try:
        r = m.call("WRAP_CALC64" if mode64 else "WRAP_CALC")
        if not r["ok"]:
            raise RuntimeError("WRAP_CALC did not return (PC=%04X)" % r["pc"])
        m.write(S("FWRAP_OLD_COUNT"), m.read(S("FWRAP_COUNT"), 1))
        blank_rows(m, 24 - MAX_ROWS, 24, mode64)
        r = m.call("EDITOR_REDRAW")
        if not r["ok"]:
            raise RuntimeError("EDITOR_REDRAW did not return (PC=%04X)" % r["pc"])
        return read_screen(m, mode64)
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
        "short64": (64, k("hello world") + [DELETE] * 3 + [LEFT] * 2 + [RIGHT, RIGHT, RIGHT] + k("!"), []),
        "middle64": (64, k("abcdef ghi") + [LEFT] * 6 + k("XYZ ") + [DELETE] * 2 + [RIGHT] * 3 + k("!"), []),
        "wrap3-grow64": (64, k(GROW64), []),
        "wrap3-shrink64": (64, [DELETE] * 128, k(GROW64)),
        "boundary64": (64, [LEFT] * 12 + [LEFT] * 6 + [RIGHT] * 4 + [DELETE, DELETE] + [RIGHT] * 6 + [LEFT] * 25 + [DELETE]
                       + [RIGHT] * 4, k("a" * 60 + " " + "b" * 14 + "d" * 60)),
    }


@case("redraw-oracle", "after EVERY key of the scenarios (a short line; typing into the middle; a line wrapping to 4 rows and back; "
                       "DELETE, LEFT and RIGHT across a wrap boundary; the same in 64 columns) the whole screen (bitmap and "
                       "attributes, 6912 bytes; both display files in 64 columns) equals the screen a full redraw draws from the "
                       "same editor state; and the oracle sees a stray pixel and a stray FLASH attribute",
      parts=list(oracle_scenarios()) + ["control"])
def redraw_oracle(env, part):
    ck, m = Check(), env.m
    if part == "control":
        env.boot()
        env.con.type("1 2 + .")
        for ch in "ab":
            env.con.key(ord(ch))
        now, ref = read_screen(m), full_reference(m, False)
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
    mode64 = w == 64
    env.boot(w)
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
        now, ref = read_screen(m, mode64), full_reference(m, mode64)
        d = first_diff(now, ref, mode64)
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


def cost_once(env, which, w):
    """T-states from the latch write to the next key wait for one key, after its setup."""
    m, con = env.m, env.con
    env.boot(w)
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
        for ch in ("a" * 70 if w == 32 else GROW64):
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
                     "`1 2 + .`, in 32 and 64 columns; each figure taken twice and equal; the baseline, no threshold",
      parts=("32", "64"))
def typing_cost(env, part):
    ck = Check()
    w = int(part)
    table = {}
    for which, what in COST_CASES:
        a = cost_once(env, which, w)
        b = cost_once(env, which, w)
        table[which] = [a, b]
        ck.eq("%s repeatable" % which, a, b)
    env.boot(w)
    env.m.tstates_reset()
    env.m.call("KBD_ISR_TICK")
    isr = env.m.tstates()
    ck.data = {"columns": w, "t_states": table, "what": dict(COST_CASES), "isr_tstates": isr}
    ck.note("%d columns: %s (one KBD_ISR_TICK call with no key down: %d T)" % (
        w, ", ".join("%s %d" % (k, v[0]) for k, v in table.items()), isr))
    return ck.result()


# ---------------------------------------------------------------------------------------------------- the runner
def run_task(m, task):
    name, part = task
    for n, _, fn, _ in CASES:
        if n == name:
            t0 = time.time()
            r = fn(Env(m), part)
            r["wall"] = time.time() - t0
            return r
    raise KeyError(name)


def select(only):
    return [c for c in CASES if not only or any(o in c[0] for o in only)]


def _cut(text, n):
    return text if len(text) <= n else text[:n - 3] + "..."


def run_all(build, workers, port0, only, json_out, verbose=False):
    cases = select(only)
    if not cases:
        raise ValueError("no case matches %r" % (only,))
    tasks = [(c[0], p) for c in cases for p in c[3]]
    t0 = time.time()
    res = fh.run_pool(build, tasks, run_task, workers, port0)
    wall = time.time() - t0
    out, failed = [], 0
    by = {}
    for (name, part), r in zip(tasks, res):
        by.setdefault(name, []).append((part, r))
    for name, title, _, parts in cases:
        rs = by[name]
        ok = all(r["ok"] for _, r in rs)
        failed += not ok
        if len(rs) == 1:
            detail = rs[0][1]["detail"]
        elif ok:
            detail = "%d parts: %s" % (len(rs), " | ".join("[%s] %s" % (p, r["detail"]) for p, r in rs))
        else:
            detail = " | ".join("[%s] %s" % (p, r["detail"]) for p, r in rs if not r["ok"])
        wall_case = sum(r["wall"] for _, r in rs)
        out.append(dict(case=name, title=title, ok=ok, detail=detail, wall=round(wall_case, 2),
                        parts=[dict(part=p, ok=r["ok"], detail=r["detail"], wall=round(r["wall"], 2), port=r["worker"],
                                    data=r.get("data") or None) for p, r in rs]))
        line = detail
        if ok and not verbose:                  # (the full text of every part is in the JSON, and with --verbose)
            first = rs[0][1]["detail"]
            line = _cut(first, 150 if len(rs) == 1 else 110)
            if len(rs) > 1:
                line = "%d parts (%s): %s" % (len(rs), ", ".join(p for p, _ in rs), line)
        print("%s %-22s %s  [%.1f s]" % ("PASS" if ok else "FAIL", name, line, wall_case), flush=True)
    typing = None
    for c in out:
        if c["case"] == "typing-cost":
            typing = {p["part"]: p["data"] for p in c["parts"] if p.get("data")}
    if typing:
        print_typing(typing)
    harness_error = all(r["detail"].startswith("TASK FAILED") for r in res) or any(
        r["detail"].startswith(("worker on port", "never ran")) for r in res)
    print("edtest: %d/%d cases pass; %d tasks; wall %.1f s (%d worker(s))" % (len(out) - failed, len(out), len(tasks), wall,
                                                                            min(workers or fh.default_workers(), len(tasks))))
    if json_out:
        os.makedirs(os.path.dirname(os.path.abspath(json_out)), exist_ok=True)
        json.dump(dict(build=build, failed=failed, cases=out, typing=typing, wall=round(wall, 2), workers=workers or fh.default_workers()),
                  open(json_out, "w"), indent=1)
    return (2 if harness_error else (1 if failed else 0))


def print_typing(typing):
    print("typing cost, T-states from key delivery to the next key wait (two runs each, equal):")
    names = [k for k, _ in COST_CASES]
    print("  %-14s %12s %12s    %s" % ("", "32 columns", "64 columns", "what"))
    for k in names:
        c = [typing.get(w, {}).get("t_states", {}).get(k, [None])[0] for w in ("32", "64")]
        print("  %-14s %12s %12s    %s" % (k, c[0], c[1], dict(COST_CASES)[k]))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"), help="directory with forth_boot_rom0.bin (DIR or DIR/build)")
    ap.add_argument("--workers", type=int, default=None, help="emulators in parallel (default: fharness.default_workers())")
    ap.add_argument("--port", type=int, default=fh.PORT_LO, help="first ZRCP port (%d-%d)" % (fh.PORT_LO, fh.PORT_HI))
    ap.add_argument("--json", default=os.path.join(ROOT, "build", "edtest.json"), help="write the results here (default build/edtest.json)")
    ap.add_argument("-v", "--verbose", action="store_true", help="print the full detail of passing cases too")
    ap.add_argument("only", nargs="*", help="run the cases whose name contains one of these")
    a = ap.parse_args()
    try:
        build = fh.resolve_build(a.build)
        return run_all(build, a.workers, a.port, a.only, a.json, a.verbose)
    except (FileNotFoundError, ValueError, RuntimeError) as e:
        print("edtest: harness error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
