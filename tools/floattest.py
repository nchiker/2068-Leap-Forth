#!/usr/bin/env python3
"""floattest.py - the float oracle (audit item T13, docs/V2/FLOAT_SPEC.md section 13), for step F.

Checks the ROM's float words against the bit-exact Python model of the spec: tools/fpforth.py (Forth's words composed of
fpmodel operations) on tools/fpmodel.py (Leap-C's model, vendored unchanged).  Floats are the Sinclair 5-byte cells
of FLOAT_SPEC section 4 on the float stack (IY, growing down from FSTACK_TOP).

RUN   python3 -I tools/floattest.py [--build DIR] [--group old|new|speed|all] [--count N] [--seed S] [--workers N]
                                    [--port P] [--int-pairs N] [--json OUT] [-v] [--selftest] [substring ...]
      DIR holds forth_boot_rom0.bin and graphics_exrom.bin (default: build/; DIR or DIR/build, as tools/fharness.py, so
      the images of an older build in a git worktree work).  Substrings select checks by name (case-insensitive).
      --count N: random cases per operation (default 300; --int-pairs: pairs for the integer * / MOD checks, default
      40,000).  One PASS/FAIL line per check, then the speed table and a summary
          floattest: A/B checks pass (old x/y, new z/w); wall S s
      Exit 0 = every selected check passes, 1 = any fails, 2 = harness error (bad build directory, port in use, no
      emulator could run a task).  JSON (default build/floattest.json): every check with its detail and the speed
      figures (comparable between an old and a new build).  Ports P .. P+workers-1, default 10840-10859 (this tool's
      range; fharness.PORT_RANGES).  --selftest needs no emulator: fpforth's self-test, the sha256 of tools/fpmodel.py
      against fpforth.FPMODEL_SHA256, and the oracle's own generators and accuracy gates run on the model alone.

GROUPS (FLOAT_SPEC section 13)
  old    behaviour the spec keeps, typed at the console and read off the screen (exact strings where the 3-byte and
         the 5-byte formats agree): must pass on the old build and the new one.
  new    the spec: the engine bit for bit against the model, literals, F. and FS., the new words, the errors and their
         messages, the float stack's size, integer * / MOD (O10), RND (F8), BEEP's frames.  Fails on the old build (3-byte
         cells, missing words), except the checks whose subject did not change: `model vs Python floats` needs no ROM,
         and the integer * / MOD and the "0 RANDOMIZE reseeds" checks describe contracts the old code already keeps.
  speed  T-states per word on fixed operands; recorded, not gated.

HOW A WORD IS CALLED (white box).  The dictionary chain is walked from the value in LATEST (link, length/flags, name, code)
for the code address of a word, so words the symbol file does not name work too.  A case restores the booted machine,
writes the float cells (5 bytes each, the top at IY, growing down from FSTACK_TOP) and the integer arguments (2-byte cells
below DSTACK_TOP, IX), sets one CATCH frame (CATCH_DEPTH 1, frame 0 = SP at a slot that holds STOP_ADDR, IX, IY as set) so a
THROW lands at the harness's stop with the code on the data stack, calls the word with SP = $FF00 and reads IY, the
cells, IX, the data stack and SP.  SP tells a normal return ($FF02) from a THROW ($FF40).  Printed text (F., FS.):
CLS, PRINT_ROW/PRINT_COL = 0, call, the screen read back with the ROM's own font (fharness.screen_rows); the cursor
must have advanced over the trailing space.  Console-level checks (the old group, literals, uncaught THROW messages, the
float stack's size): fharness.Console types the lines and the rows are read off the screen.

Operand generators and the case mix of the engine checks are ported from 2068-Leap-C tools/floattest.py (b918527's
tree): `interesting` (zeros, powers of two, all-ones mantissas, both signs, exponents at the range's ends, random bit
patterns), `near` (close pairs for cancellation), the 20 constant texts (without the f/F/l/L suffixes: 18 remain) and the
random d.dEn texts; copied and adapted, not imported: nothing here reads or writes ~/2068-Leap-C.

EMULATOR LIMITS: there is no hardware here.  Every verdict is ZEsarUX's (its Z80, its interrupt timing, its screen RAM)
running the ROM image; T-states include any 50 Hz interrupt service that falls inside the measured call.
"""
import argparse
import decimal
import hashlib
import json
import math
import os
import random
import struct
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fharness as fh                                                     # noqa: E402
import fpforth as P                                                       # noqa: E402
import fpmodel as F                                                       # noqa: E402

ROOT = fh.ROOT
PORT0 = 10840

# Harness RAM: $FF00 RET_SLOT, $FF02 STOP_ADDR, $FF10 GLYPH_PROG (fharness).  Ours:
# READING: FLOAT_SPEC section 13 says the CATCH frame's SP "points at a slot that holds STOP_ADDR, e.g. $FF04 containing
# $FF02".  THROW then does `rst RST_DPUSH` with SP at the slot, which pushes a return address at slot - 2: with the slot
# at $FF04 that overwrites the stop instruction at $FF02 and the THROW would not land.  The slot is at THROW_SLOT, well
# above the stop and clear of the strings; the stack below it ($FF3C, $FF3D...) is scratch.
STOP_ADDR, RET_SLOT = fh.STOP_ADDR, fh.RET_SLOT
THROW_SLOT = 0xFF3E                     # [THROW_SLOT] = STOP_ADDR; after THROW's `ret`, SP = THROW_SLOT + 2
NORMAL_SP, THROWN_SP = RET_SLOT + 2, THROW_SLOT + 2
TEXT = 0xFF50                           # counted strings (NUMBER); up to 31 characters ($FF70)
MEMA = 0xFFA0                           # the cell F@ and F! use; $FF9C-$FFA8 guard bytes
GUARD = 0xA5
BANNER = "2068-FORTH"
FSTACK_TOP, DSTACK_TOP, LATEST = 0x9000, 0x9800, 0x8608
FSTACK_CELLS = 204
BEEP_PLAY_SYM = "BEEP_PLAY"

ZERO, ONE, MONE = bytes(5), F.ONE, F.MONE


class Missing(Exception):
    """A word (or symbol) the build does not have."""


class Stuck(Exception):
    """A call that did not return several times in a row: stop the chunk."""


# ---------------------------------------------------------------------------------------------------- generators
def interesting(rng):
    """A float worth testing (5 bytes).  Leap-C tools/floattest.py."""
    k = rng.randrange(10)
    if k == 0:
        return bytes(5)
    s = rng.choice((0, 0x80))
    if k == 1:
        e = rng.choice((1, 2, 127, 128, 129, 130, 254, 255))
    elif k == 2:
        e = rng.randrange(120, 150)
    else:
        e = rng.randrange(1, 256)
    if k == 3:
        m = rng.choice((0, 0x7FFFFFFF, 0x7FFFFF00, 1, 0x40000000))
    else:
        m = rng.getrandbits(31)
    return bytes([e, s | m >> 24 & 0x7F, m >> 16 & 255, m >> 8 & 255, m & 255])


def near(rng):
    """Two floats close in magnitude (subtraction's cancellation).  Leap-C tools/floattest.py."""
    a = interesting(rng)
    b = bytearray(a)
    b[4] ^= rng.getrandbits(3)
    if rng.random() < 0.5:
        b[1] ^= 0x80
    return a, bytes(b)


def enc(v):
    return F.encode(v)


def mid(rng):
    """A float of everyday size: a sign, an exponent e^-30..e^30, a random mantissa (encode of a Python float)."""
    return enc(rng.choice((-1, 1)) * math.exp(rng.uniform(-30, 30)))


# Leap-C's constant texts without the f/F/l/L suffixes ("1.5f", "2.5L" are not numbers here): 18 remain.
LIT_TEXTS = ["1.5", "0.1", "3.14159", "1e10", "2.5e-3", ".5", "1.", "100.0", "123456789012.5", "1e38", "1e-38",
             "1e-45", "0.0", "6.02E23", "1.0e+2", "007.25", "4294967295.0", "99999999999e-1"]
# more floats of the spec's grammar: signs, 10+ digit mantissas, the range's ends
LIT_MORE = ["-1.5", "-.5", "-1E3", "-2.5e-4", "-0.0", "3.", "12345678901.", "1234567890123.5", "0.000001",
            "9.999999999", "1.7E38", "2.9E-39", "1E-50", "65536.0", "40000.0", "-40000.0", "1E0", "5E+2", "0.10000"]
# not floats: integers (a 16-bit pattern, or -43 outside -32768..65535), non-numbers, out of range
INT_TEXTS = ["0", "1", "-1", "12345", "32767", "32768", "40000", "65535", "-32768", "-32767", "007", "-0",
             "65536", "100000", "-40000", "-32769", "99999999999999999999",
             "6399", "6400", "6409", "64009", "64010", "64019", "-6400", "0006400"]   # the 16-bit loop's hand-over
BAD_TEXTS = ["", "-", ".", "-.", "1.2.3", "1..2", "ABC", "1E", "1E+", "E5", "+5", "1.5f", "2.5L", "0x10", "1_000",
             "--1", "1e5e5", "1.5x", "1E39", "1E300", "-1E39", "2E38", "12a", "5-", "64009x"]


def random_texts(rng, n):
    out = []
    for _ in range(n):
        k = rng.randrange(6)
        if k == 0:
            t = "%d.%dE%d" % (rng.randrange(1000), rng.randrange(1000), rng.randrange(-20, 20))
        elif k == 1:
            t = "%d.%de%d" % (rng.randrange(1000), rng.randrange(1000), rng.randrange(-30, 30))
        elif k == 2:
            t = "%d.%d" % (rng.randrange(100000), rng.randrange(10 ** rng.randrange(1, 9)))
        elif k == 3:
            t = "%d." % rng.getrandbits(rng.randrange(10, 34))          # 10+ digit mantissa, a float by its point
        elif k == 4:
            t = "%dE%d" % (rng.randrange(1, 10 ** rng.randrange(1, 9)), rng.randrange(-30, 30))
        else:
            t = ".%d" % rng.randrange(10 ** rng.randrange(1, 10))
        if rng.random() < 0.3:
            t = "-" + t
        out.append(t)
    return out


def chunks(lst, n):
    return [lst[i:i + n] for i in range(0, len(lst), n)] or [[]]


# ---------------------------------------------------------------------------------------------------- expectations
def th(code):
    return ("throw", code)


def okx(f=(), i=()):
    return ("ok", list(f), [v & 0xFFFF for v in i])


def model(fn, *a):
    """The model's value, or the Throw it raises (returned, not raised)."""
    try:
        return fn(*a)
    except P.Throw as t:
        return t


def flag(b):
    return 0xFFFF if b else 0


def s16(v):
    return v - 0x10000 if v & 0x8000 else v


def cellstr(c):
    try:
        return "%s(%.9g)" % (bytes(c).hex(), F.value(c))
    except Exception:                                       # noqa: BLE001
        return bytes(c).hex()


def cstr(cells):
    return "[" + " ".join(cellstr(c) for c in cells) + "]" if cells is not None else "?"


def describe(cs):
    d = cs["word"] if isinstance(cs["word"], str) else "$%04X" % cs["word"]
    if cs.get("text") is not None:
        d += " %r" % cs["text"]
    return "%s f=%s i=%s" % (d, " ".join(c.hex() for c in cs["f"]), [s16(v & 0xFFFF) for v in cs["i"]])


def std(word, f, i, exp, **kw):
    d = dict(word=word, f=list(f), i=[v & 0xFFFF for v in i], exp=exp)
    d.update(kw)
    return d


def un_case(word, fn, a, junk, acc=None):
    r = model(fn, a)
    exp = th(r.code) if isinstance(r, P.Throw) else okx([junk, r])
    return std(word, [junk, a], [], exp, acc=acc, x=a)


def bin_case(word, fn, a, b, junk):
    r = model(fn, a, b)
    exp = th(r.code) if isinstance(r, P.Throw) else okx([junk, r])
    return std(word, [junk, a, b], [], exp)


def cmp_case(word, test, a, b, junk):
    return std(word, [junk, a, b], [], okx([junk], [flag(test(P.cmp(a, b)))]))


# ---------------------------------------------------------------------------------------------------- accuracy gates
def acc_sincos(x, got, name):
    xv, gv = F.value(x), F.value(got)
    if name == "sin":
        want = math.sin(xv)
        if abs(xv) <= math.pi / 2:
            u = P.ulps(got, want)
            return None if u <= 3 else "SIN(%.9g) = %.12g, Python %.12g: %.2f ulp (gate 3)" % (xv, gv, want, u)
    else:
        want = math.cos(xv)
    err = abs(gv - want)
    return None if err <= 2.0 ** -30 else "%s(%.9g) = %.12g, Python %.12g: error %.3g (gate 2^-30)" % (
        name.upper(), xv, gv, want, err)


def acc_tan(x, got):
    xv, gv = F.value(x), F.value(got)
    s, c = math.sin(xv), math.cos(xv)
    t = s / c
    # READING: the spec gives no TAN accuracy; the gate is what the sine's and the cosine's absolute errors (3.8e-10,
    # 5.3e-10, section 8.2) and the final division allow: (sin err + |tan| cos err) / |cos| + 2^-30 |tan|.
    tol = (4e-10 + 5.5e-10 * abs(t)) * math.sqrt(1 + t * t) + 2.0 ** -30 * abs(t)
    return None if abs(gv - t) <= tol else "TAN(%.9g) = %.12g, Python %.12g: error %.3g (gate %.3g)" % (
        xv, gv, t, abs(gv - t), tol)


def acc_sqrt(x, got):
    # READING: FLOAT_SPEC 8.1 gives 0.75 ulp for the model against math.sqrt; the gate is 1 ulp (the reference is a double).
    u = P.ulps(got, math.sqrt(F.value(x)))
    return None if u <= 1.0 else "FSQRT(%.9g) = %.12g: %.2f ulp from math.sqrt (gate 1)" % (F.value(x), F.value(got), u)


def acc_scale(k, name):
    def f(x, got):
        want = F.value(x) * k
        err = abs(F.value(got) - want)
        # (a result under 1e-37 may have underflowed to 0 or lost bits to the exponent range's end: section 8.1)
        return None if err <= abs(want) * 2.0 ** -29 or abs(want) < 1e-37 else "%s(%.9g) = %.12g, Python %.12g" % (
            name, F.value(x), F.value(got), want)
    return f


ACC = {"sin": lambda x, g: acc_sincos(x, g, "sin"), "cos": lambda x, g: acc_sincos(x, g, "cos"), "tan": acc_tan,
       "sqrt": acc_sqrt, "rad": acc_scale(math.pi / 180, "RAD"), "deg": acc_scale(180 / math.pi, "DEG")}


# ---------------------------------------------------------------------------------------------------- the white-box caller
class R:
    """The state after a white-box call."""
    pass


class Fw:
    """Calls Forth words on a Machine (white box).  See the header."""

    def __init__(self, m):
        self.m = m
        self.syms = m.S
        self.cell = 5                                        # bytes per float cell (3 only for the old build's speed operands)
        self.words = {}
        a, n = m.w16(m.S.get("LATEST", LATEST)), 0
        while a and n < 4000:
            b = m.read(a, 36)
            ln = b[2] & 0x1F
            self.words.setdefault(b[3:3 + ln].decode("latin-1").upper(), a + 3 + ln)
            a = b[0] | b[1] << 8
            n += 1
        self.stuck = 0

    def addr(self, word):
        if isinstance(word, int):
            return word
        if word.upper() in self.words:
            return self.words[word.upper()]
        if word in self.syms:                                # an internal routine (NUMBER, BEEP_PLAY)
            return self.syms[word]
        raise Missing(word)

    def call(self, word, floats=(), ints=(), text=None, maxi=2_500_000, stops=(), catch=True, timed=False, regs=None):
        """floats: 5-byte cells, deepest first; ints: 16-bit values, deepest first; text: a counted string at TEXT.
        Returns R: ok (reached the stop), pc, sp, threw, code, iy, ix, f (cells deepest first, None when IY is not a
        whole number of cells under FSTACK_TOP), ints (deepest first, None when IX is wild), regs, tstates."""
        m = self.m
        code = self.addr(word)
        nf, ni = len(floats), len(ints)
        cw = self.cell
        iy0, ix0 = FSTACK_TOP - cw * nf, DSTACK_TOP - 2 * ni
        if nf:
            m.write(iy0, b"".join(reversed(floats)))                # the last cell is the top, at IY
        if ni:
            m.write(ix0, b"".join(struct.pack("<H", v & 0xFFFF) for v in reversed(ints)))
        if text is not None:
            m.write(TEXT, bytes([len(text)]) + text.encode("latin-1"))
        if catch:
            m.write(m.sym("CATCH_DEPTH"), bytes([1]))
            m.write(m.sym("CATCH_STACK"), struct.pack("<HHH", THROW_SLOT, ix0, iy0))   # frame 0 (not next to the depth)
            m.write(THROW_SLOT, struct.pack("<H", STOP_ADDR))
        m.write(STOP_ADDR, b"\x18\xFE")
        m.write(RET_SLOT, struct.pack("<H", STOP_ADDR))
        m.setreg("IX", ix0)
        m.setreg("IY", iy0)
        m.setreg("SP", RET_SLOT)
        for k, v in (regs or {}).items():
            m.setreg(k, v)
        m.setreg("PC", code)
        if timed:
            m.tstates_reset()
        pc = m.run_to([STOP_ADDR] + list(stops), maxi)
        r = R()
        r.tstates = m.tstates() if timed else None
        g = m.regs()
        r.regs, r.pc, r.sp, r.iy, r.ix = g, pc, g["SP"], g["IY"], g["IX"]
        r.ok = pc == STOP_ADDR
        r.threw = r.ok and r.sp == THROWN_SP
        nfl = (FSTACK_TOP - r.iy) // cw if r.iy <= FSTACK_TOP and (FSTACK_TOP - r.iy) % cw == 0 else None
        r.f = None
        if nfl is not None and nfl <= 210:
            raw = m.read(r.iy, cw * nfl) if nfl else b""
            r.f = [raw[cw * k:cw * k + cw] for k in range(nfl)][::-1]
        nin = (DSTACK_TOP - r.ix) // 2 if r.ix <= DSTACK_TOP and (DSTACK_TOP - r.ix) % 2 == 0 else None
        r.ints = None
        if nin is not None and nin <= 64:
            raw = m.read(r.ix, 2 * nin) if nin else b""
            r.ints = [raw[2 * k] | raw[2 * k + 1] << 8 for k in range(nin)][::-1]
        r.code = s16(r.ints[-1]) if r.threw and r.ints else None
        if not r.ok and pc not in stops:
            self.stuck += 1
            if self.stuck >= 3:
                raise Stuck("3 calls did not return (last: PC=$%04X)" % pc)
        else:
            self.stuck = 0
        return r


def fw_of(m):
    if getattr(m, "_fw", None) is None:
        m._fw = Fw(m)
    return m._fw


def settle(r):
    """Why a call did not end as a plain return (text), else None."""
    if not r.ok:
        return "did not return (PC=$%04X)" % r.pc
    if r.threw:
        return "THROW %s" % r.code
    if r.sp != NORMAL_SP:
        return "SP=$%04X after the return (wanted $%04X)" % (r.sp, NORMAL_SP)
    return None


def judge(fw, r, cs):
    """None when the call's outcome is the case's expectation, else the difference."""
    exp = cs["exp"]
    if exp[0] == "throw":
        if not r.ok:
            return "did not return (PC=$%04X), wanted THROW %d" % (r.pc, exp[1])
        if not r.threw:
            return "returned (floats %s ints %s), wanted THROW %d" % (cstr(r.f), r.ints, exp[1])
        if r.code != exp[1]:
            return "THROW %s, wanted %d" % (r.code, exp[1])
        return None
    why = settle(r)
    if why:
        return "%s, wanted %s %s" % (why, cstr(exp[1]), [s16(v) for v in exp[2]])
    if r.f is None:
        return "IY=$%04X is not a whole number of cells under $%04X (wanted %s)" % (r.iy, FSTACK_TOP, cstr(exp[1]))
    if r.f != exp[1]:
        return "float stack ROM %s, model %s" % (cstr(r.f), cstr(exp[1]))
    if r.ints != exp[2]:
        return "data stack ROM %s, model %s" % (None if r.ints is None else [s16(v) for v in r.ints],
                                                 [s16(v) for v in exp[2]])
    m = fw.m
    for a, data in cs.get("mem", ()):
        got = m.read(a, len(data))
        if got != data:
            return "memory at $%04X ROM %s, model %s" % (a, got.hex(), data.hex())
    if cs.get("acc") and exp[1]:
        msg = ACC[cs["acc"]](cs["x"], exp[1][-1])
        if msg:
            return msg
    return None


# ---------------------------------------------------------------------------------------------------- screen and console
def read_text(m, nrows=2):
    """The first rows of the screen as text (rstripped rows, joined)."""
    scr = m.read(0x4000, 2048)
    return "".join(m.screen_rows(scr, nrows=nrows))


def clear_print(fw):
    fw.call("CLS", catch=False)
    fw.m.write(fw.m.sym("PRINT_ROW"), b"\x00\x00")           # PRINT_ROW, PRINT_COL = 0, 0 (adjacent bytes)
    assert fw.m.sym("PRINT_COL") == fw.m.sym("PRINT_ROW") + 1


TYPE_MAXI = 1_000_000                       # instructions a typed line may take before the console counts as stuck


def typ(c, text):
    """Console.type with a limit (RuntimeError: no key wait) instead of fharness's 60 million instructions."""
    for ch in text:
        c.key(ord(ch), TYPE_MAXI)
    c.key(13, TYPE_MAXI)


def con_boot(m):
    c = fh.Console(m)
    c.boot()
    return c


def nonblank_rows(m):
    rows = m.screen_rows()
    if rows and rows[0] == BANNER:
        rows = rows[1:]
    return [r for r in rows if r]


def con_line(m, c, line):
    """Type one line; the text it printed: the new rows joined, a trailing OK dropped.
    READING: the interpreter's "OK" acknowledgement (printed after the output, on the same row) is not part of the
    output; a row that is just OK is dropped; a long output wraps at column 32 without a break, so the rows are joined
    with nothing between them."""
    before = nonblank_rows(m)
    typ(c, line)
    t = "".join(nonblank_rows(m)[len(before):])
    if t.endswith(" OK"):
        t = t[:-3]
    elif t == "OK":
        t = ""
    return t.strip()


def con_out(m, c, lines):
    """Type the lines; the text the LAST line printed.  READING: the setup lines (definitions, stores) print nothing
    when they work; one that prints something (an error) ends the run with that text instead of going on to run what it
    failed to define."""
    for ln in lines[:-1]:
        t = con_line(m, c, ln)
        if t:
            return "setup line %r printed %r" % (ln, t)
    return con_line(m, c, lines[-1])


def type_to_stop(m, c, text, stop):
    """Type text and ENTER, running to `stop` or the next key wait; (pc, regs)."""
    for ch in text:
        c.key(ord(ch), TYPE_MAXI)
    S = m.sym
    m.write(S("KBD_LASTK"), 13)
    m.write(S("KBD_KEYHIT"), 0xFF)
    m.cmd("cpu-step")
    pc = m.run_to([stop, S("IO_READ_KEY")], TYPE_MAXI)
    return pc, m.regs()


# ---------------------------------------------------------------------------------------------------- case handlers
def do_std(fw, cs):
    for a, data in cs.get("pre", ()):
        fw.m.write(a, data)
    r = fw.call(cs["word"], cs["f"], cs["i"], text=cs.get("text"), maxi=cs.get("maxi", 2_500_000))
    return judge(fw, r, cs)


def do_print(fw, cs):
    """F. or FS. (cs["word"]) on cs["f"][-1]; PLACES set to cs["places"] first; the text and the cursor."""
    m = fw.m
    # READING: the text is read from the first rows of the screen after CLS; "the words print a trailing space" is checked
    # on the cursor (PRINT_ROW/PRINT_COL advanced over text + one space, EMIT wrapping eagerly at column 32).
    if cs.get("places") is not None:
        r = fw.call("PLACES", ints=[cs["places"]])
        why = settle(r)
        if why:
            return "PLACES %d: %s" % (cs["places"], why)
    clear_print(fw)
    r = fw.call(cs["word"], cs["f"], [])
    why = settle(r)
    if why:
        return why
    if r.f != []:
        return "float stack after: %s (IY=$%04X), wanted empty" % (cstr(r.f), r.iy)
    want = cs["text"] + " "
    n = len(want)
    got = read_text(m, 3).rstrip()
    if cs.get("python") is not None and got != cs["python"]:
        return "text ROM %r, Python (exact decimal, half up) %r, model %r" % (got, cs["python"], cs["text"])
    row, col = m.read(m.sym("PRINT_ROW"), 2)
    if got != cs["text"]:
        return "text ROM %r, model %r" % (got, cs["text"])
    if (row, col) != (n // 32, n % 32):
        return "text right but no trailing space? cursor (%d,%d), wanted (%d,%d)" % (row, col, n // 32, n % 32)
    return None


def do_number(fw, cs):
    tok = cs["text"]
    ex = cs["exp"]
    r = fw.call("NUMBER", [], [TEXT], text=tok)
    if ex[0] == "throw":
        if not r.ok:
            return "did not return (PC=$%04X), wanted THROW %d" % (r.pc, ex[1])
        if not r.threw:
            return "returned (floats %s ints %s), wanted THROW %d" % (cstr(r.f), r.ints, ex[1])
        return None if r.code == ex[1] else "THROW %s, wanted %d" % (r.code, ex[1])
    why = settle(r)
    if why:
        return why
    if r.ints is None or not r.ints:
        return "no flag on the data stack (IX=$%04X)" % r.ix
    kind = ex[0]
    top = r.ints[-1]
    if kind == "none":
        return None if top == 0 and r.f == [] else "flag %d floats %s, wanted flag 0 (not a number)" % (top, cstr(r.f))
    if kind == "int":
        if top != 1 or r.ints[-2:-1] != [ex[1]] or r.f != []:
            return "ints %s floats %s, wanted ( %d 1 )" % (r.ints, cstr(r.f), ex[1])
        return None
    # READING: for a float the data stack holds just the flag 2 (core/decimal.asm: "nothing on the data stack for it").
    if r.ints != [2] or r.f != [ex[1]]:
        return "ints %s floats %s, wanted ( 2 ) and %s" % (r.ints, cstr(r.f), cellstr(ex[1]))
    return None


def do_beep(fw, cs):
    m = fw.m
    # READING: BEEP_PLAY is where the frame count is read (spec section 13: "run to BEEP_PLAY and read DE"), and BEEP_PLAY
    # waits `frames` display frames, so the call is not run on from there.  The float and the integer argument must already
    # be popped when BEEP_PLAY is entered (today's W_BEEP: FPOP, then DPOP, then `jp BEEP_PLAY`).  A duration that plays
    # nothing (negative, under half a frame) may or may not reach BEEP_PLAY: a normal return counts as 0 frames.
    r = fw.call("BEEP", cs["f"], cs["i"], stops=[m.sym(BEEP_PLAY_SYM)])
    if not r.ok and r.pc != m.sym(BEEP_PLAY_SYM):
        return "BEEP did not return (PC=$%04X)" % r.pc
    if r.pc == m.sym(BEEP_PLAY_SYM):
        g = r.regs
        frames, hl = g["DE"], g["HL"]
        if g["IY"] != FSTACK_TOP or g["IX"] != DSTACK_TOP:
            return "stacks at BEEP_PLAY: IX=$%04X IY=$%04X, wanted $%04X $%04X" % (g["IX"], g["IY"], DSTACK_TOP, FSTACK_TOP)
        if hl != cs["i"][0] & 0xFFFF:                       # (a negative semitone count is the 16-bit pattern in HL)
            return "semitones at BEEP_PLAY %d, wanted %d" % (s16(hl), s16(cs["i"][0] & 0xFFFF))
    else:
        why = settle(r)
        if why:
            return why
        frames = 0                                          # BEEP_PLAY not reached: nothing to play
        if r.f != [] or r.ints != []:
            return "stacks after BEEP: floats %s ints %s" % (cstr(r.f), r.ints)
    want = cs["frames"]
    return None if frames == want else "BEEP %s s: %d frames, model %d" % (cellstr(cs["f"][-1]), frames, want)


HANDLERS = {"std": do_std, "print": do_print, "number": do_number, "beep": do_beep}


# ---------------------------------------------------------------------------------------------------- task functions
def t_cases(m, fw, a):
    """Run a chunk of cases (a["cases"]); restore the machine before each (a["every"]: every k-th)."""
    # READING: "restore before each case" is every case here (3 ms); the integer checks restore every 32 pairs (pure words).
    cases, every = a["cases"], a.get("every", 1)
    fails, n = [], 0
    try:
        for k, cs in enumerate(cases):
            if k % every == 0:
                m.restore()
                fw.stuck = 0
            msg = HANDLERS[cs.get("kind", "std")](fw, cs)
            n += 1
            if msg:
                fails.append("%s: %s" % (describe(cs) if cs.get("kind", "std") != "number" else "NUMBER %r" % cs["text"], msg))
    except Stuck as e:
        fails.append(str(e))
    return result(n, len(cases), fails)


def result(n, total, fails):
    if not fails:
        return dict(ok=True, detail="%d cases" % n, n=n, nfail=0)
    return dict(ok=False, detail="%d of %d cases fail; first: %s%s" % (
        len(fails), total, fails[0], (" | " + fails[1]) if len(fails) > 1 else ""), n=n, nfail=len(fails))


def t_words(m, fw, a):
    miss = [w for w in a["names"] if w.upper() not in fw.words]
    return dict(ok=not miss, detail=("all %d present" % len(a["names"])) if not miss else
                "%d of %d missing: %s" % (len(miss), len(a["names"]), " ".join(miss)))


def t_int(m, fw, a):
    """Integer * / MOD (O10): pairs (b top), the contract of core/mathfn.asm: truncation toward 0, the remainder with the
    dividend's sign, a divisor of 0 gives 0."""
    # READING: 40,000 pairs for each of the three words (120,000 calls), called without a CATCH frame (they cannot throw).
    word, pairs = a["word"], a["pairs"]
    fails = []
    try:
        for k, (x, y) in enumerate(pairs):
            if k % 32 == 0:
                m.restore()
                fw.stuck = 0
            r = fw.call(word, ints=[x, y], catch=False)
            want = int_model(word, x, y)
            why = settle(r)
            if why:
                fails.append("%d %d %s: %s" % (x, y, word, why))
            elif r.ints != [want]:
                fails.append("%d %d %s: ROM %s, model %d" % (x, y, word, None if r.ints is None else [s16(v) for v in r.ints], s16(want)))
    except Stuck as e:
        fails.append(str(e))
    return result(len(pairs), len(pairs), fails)


def int_model(word, x, y):
    if word == "*":
        return (x * y) & 0xFFFF
    if y == 0:
        return 0
    q = abs(x) // abs(y)
    if (x < 0) != (y < 0):
        q = -q
    if word == "/":
        return q & 0xFFFF
    return (x - q * y) & 0xFFFF


def int_pairs(rng, n):
    B = [-32768, -32767, -2, -1, 0, 1, 2, 32766, 32767]
    out = [(x, y) for x in B for y in B]
    while len(out) < n:
        k = rng.randrange(6)
        if k == 0:
            x, y = rng.randrange(-32768, 32768), rng.randrange(-32768, 32768)
        elif k == 1:
            x, y = rng.randrange(-30, 31), rng.randrange(-30, 31)
        elif k == 2:
            x, y = rng.randrange(-32768, 32768), rng.randrange(-300, 301)
        elif k == 3:
            x, y = rng.randrange(-300, 301), rng.randrange(-32768, 32768)
        elif k == 4:
            y = rng.randrange(-200, 201) or 1
            x = y * rng.randrange(-160, 161) + rng.choice((0, 0, 1, -1))
            x = max(-32768, min(32767, x))
        else:
            x, y = rng.choice(B), rng.randrange(-32768, 32768)
        out.append((x, y))
    return out[:n]


# ---- console tasks
def t_console(m, fw, a):
    """a["lines"]: [(setup lines, line, expected text), ...]; every entry on a freshly booted machine."""
    fails, n, outs = [], 0, []
    for setup, line, want in a["lines"]:
        c = con_boot(m)
        got = con_out(m, c, list(setup) + [line])
        n += 1
        outs.append(got)
        if got != want:
            fails.append("%s%s -> %r, wanted %r" % ("; ".join(setup) + "; " if setup else "", line, got, want))
    r = result(n, n, fails)
    if not fails:
        r["detail"] = "typed -> " + " | ".join(repr(o) for o in outs)
    return r


def t_beep_typed(m, fw, a):
    c = con_boot(m)
    pc, g = type_to_stop(m, c, a["line"], m.sym(BEEP_PLAY_SYM))
    if pc != m.sym(BEEP_PLAY_SYM):
        return dict(ok=False, detail="%s: BEEP_PLAY not reached (PC=$%04X)" % (a["line"], pc))
    ok = g["DE"] == a["frames"]
    return dict(ok=ok, detail="%s: BEEP_PLAY called with DE=%d frames%s" % (
        a["line"], g["DE"], "" if ok else ", wanted %d" % a["frames"]))


def top_cell(m):
    iy = m.regs()["IY"]
    d = FSTACK_TOP - iy
    return m.read(iy, 5) if 5 <= d <= 5 * FSTACK_CELLS and d % 5 == 0 else None, iy


def t_lit(m, fw, a):
    """Typed or compiled float literals: each token on the console, the float stack's top against the model."""
    mode = a["mode"]
    c = con_boot(m)
    fails = []
    for k, tok in enumerate(a["tokens"]):
        want = P.parse(tok)[1]
        m.setreg("IY", FSTACK_TOP)
        if mode == "typed":
            typ(c, tok)
        else:
            out = con_line(m, c, ": T%d %s ;" % (k, tok))
            if out:                                  # the definition failed: do not run what was not defined
                fails.append("compiled %r: the definition printed %r" % (tok, out))
                c = con_boot(m)
                continue
            typ(c, "T%d" % k)
        cell, iy = top_cell(m)
        if cell != want or iy != FSTACK_TOP - 5:
            fails.append("%s %r: float stack top %s (IY=$%04X), model %s" % (mode, tok, cellstr(cell) if cell else None, iy, cellstr(want)))
    return result(len(a["tokens"]), len(a["tokens"]), fails)


def t_stack(m, fw, a):
    c = con_boot(m)
    if a["mode"] == "204":
        o1 = con_out(m, c, [": T 204 0 DO 1.5 LOOP ;", "T FDEPTH ."])
        iy = m.regs()["IY"]
        o2 = con_out(m, c, [": U 204 0 DO FDROP LOOP ;", "U FDEPTH ."])
        iy2 = m.regs()["IY"]
        ok = o1 == "204" and o2 == "0" and iy2 == FSTACK_TOP
        return dict(ok=ok, detail="204 pushes: FDEPTH %r, IY=$%04X (FSTACK_LIMIT $8C04); 204 drops: FDEPTH %r, IY=$%04X" % (o1, iy, o2, iy2))
    o = con_out(m, c, [": T 205 0 DO 1.5 LOOP ;", "T"])
    return dict(ok=o == "STACK?", detail="205 pushes: %r (IY=$%04X)" % (o, m.regs()["IY"]))


def t_rnd_seq(m, fw, a):
    seed, ns = a["seed"], a["ns"]
    r = fw.call("RANDOMIZE", ints=[seed])
    why = settle(r)
    if why:
        return dict(ok=False, detail="%d RANDOMIZE: %s" % (seed, why))
    state, bad, seen, prev = seed, [], set(), None
    for k, n in enumerate(ns):
        r = fw.call("RND", ints=[n], catch=False)
        state, want = P.rnd(state, n)
        why = settle(r)
        if why:
            bad.append("call %d (%d RND): %s" % (k, s16(n), why))
            break
        if r.ints != [want]:
            bad.append("call %d (%d RND): ROM %s, model %d" % (k, s16(n), r.ints, want))
            break
        if a.get("pairs"):
            if prev is not None:
                seen.add((prev, want))
            prev = want
    if not bad:
        st = m.w16(m.sym("RND_STATE"))
        if st != state:
            bad.append("RND_STATE $%04X after %d calls, model $%04X" % (st, len(ns), state))
    if not bad and a.get("pairs") and len(seen) != a["pairs"]:
        bad.append("%d different consecutive pairs of %d RND calls, wanted %d" % (len(seen), len(ns), a["pairs"]))
    return dict(ok=not bad, detail=bad[0] if bad else "seed %d: %d results equal the model's%s" % (
        seed, len(ns), (", %d consecutive pairs" % len(seen)) if a.get("pairs") else ""))


def t_rnd_reseed(m, fw, a):
    # READING: "two boots give different first values" is not testable (restores are deterministic).  The machine is run a
    # different number of instructions (the delays) before `0 RANDOMIZE` + the first RND, which moves R; the seed taken from R
    # must make RND_STATE differ between at least two delays, and never be 0.
    states, vals, bad = [], [], []
    for delay in a["delays"]:
        m.restore()
        fw.stuck = 0
        m.set_bps([])
        if delay:
            m.run(delay)
        for step in (lambda: fw.call("RANDOMIZE", ints=[0]), lambda: fw.call("RND", ints=[1000], catch=False)):
            why = settle(step())
            if why:
                bad.append(why)
        st = m.w16(m.sym("RND_STATE"))
        states.append(st)
        if st == 0:
            bad.append("RND_STATE is 0 after the first RND (delay %d)" % delay)
    if len(set(states)) < 2:
        bad.append("0 RANDOMIZE then RND: the same RND_STATE $%04X after %s instructions of delay" % (states[0], a["delays"]))
    return dict(ok=not bad, detail=bad[0] if bad else "RND_STATE after the reseeding RND: %s (%d different), never 0" % (
        " ".join("%04X" % s for s in states[:6]), len(set(states))))


def t_uncaught(m, fw, a):
    fails = []
    for line, want in a["lines"]:
        c = con_boot(m)
        got = con_out(m, c, [line])
        if got != want:
            fails.append("%s -> %r, wanted %r" % (line, got, want))
    return result(len(a["lines"]), len(a["lines"]), fails)


def legacy_cell(c):
    """The old build's 3-byte cell (core/float.asm: 16-bit signed mantissa, then an 8-bit exponent, value m * 2^e) for the
    value of the 5-byte c: the mantissa scaled into 16384..32767 in magnitude."""
    v = F.value(c)
    if v == 0:
        return bytes(3)
    e = math.frexp(abs(v))[1] - 15
    mm = int(round(v / 2.0 ** e))
    return struct.pack("<hb", mm, e)


def t_speed(m, fw, a):
    """T-states of one call on fixed operands: the least of 3 runs (a frame interrupt may fall inside a run)."""
    runs = []
    legacy = fw.syms.get("FSTACK_LIMIT") == 0x8C00   # READING: the old build (3-byte cells, FSTACK_LIMIT $8C00); its operands are
    fw.cell = 3 if legacy else 5                #   written in that format (same values) so that the old figures are real
    f = [legacy_cell(x) for x in a.get("f", ())] if legacy else a.get("f", ())
    try:
        for _ in range(3):
            m.restore()
            fw.stuck = 0
            if a.get("seed") is not None:
                fw.call("RANDOMIZE", ints=[a["seed"]])
            if a.get("places") is not None:
                fw.call("PLACES", ints=[a["places"]])
            if a.get("print"):
                clear_print(fw)
            r = fw.call(a["word"], f, a.get("i", ()), text=a.get("text"), timed=True, catch=a.get("catch", True))
            why = settle(r)
            if why:
                return dict(ok=False, detail="%s: %s" % (a["name"], why), data=dict(name=a["name"], tstates=None))
            runs.append(r.tstates)
    except Missing as e:
        return dict(ok=False, detail="%s: word %s missing in this build" % (a["name"], e), data=dict(name=a["name"], tstates=None))
    return dict(ok=True, detail="%s: %d T-states" % (a["name"], min(runs)),
                data=dict(name=a["name"], tstates=min(runs), runs=runs))


FUNCS = {"cases": t_cases, "words": t_words, "int": t_int, "console": t_console, "beep_typed": t_beep_typed,
         "lit": t_lit, "stack": t_stack, "rnd_seq": t_rnd_seq, "rnd_reseed": t_rnd_reseed, "uncaught": t_uncaught,
         "speed": t_speed}


def run_task(m, task):
    fw = fw_of(m)
    fw.cell, fw.stuck = 5, 0
    try:
        r = FUNCS[task["func"]](m, fw, task["args"])
    except Missing as e:
        return dict(ok=False, detail="word %s is not in this build's dictionary" % e)
    except Stuck as e:
        return dict(ok=False, detail=str(e))
    except RuntimeError as e:                    # the console did not get back to its key wait (a build that cannot run the line)
        return dict(ok=False, detail="console stuck: %s" % e)
    return r


# ---------------------------------------------------------------------------------------------------- the checks
class Check:
    def __init__(self, name, group, tasks, parent=None):
        self.name, self.group, self.tasks, self.parent = name, group, tasks, parent


def task(func, args, weight=1):
    return dict(func=func, args=args, weight=weight)


def case_check(name, group, cases, chunk=60, every=1):
    return Check(name, group, [task("cases", dict(cases=c, every=every), len(c)) for c in chunks(cases, chunk)])


def console_check(name, group, lines):
    return Check(name, group, [task("console", dict(lines=lines), 2 * len(lines))])


# ---- the old group
def old_checks():
    L = []

    def con(name, line, want, setup=()):
        L.append(console_check(name, "old", [(list(setup), line, want)]))

    con("2.0 3.0 F* F.", "2.0 3.0 F* F.", "6.0000")
    con("0.5 0.5 F* F.", "0.5 0.5 F* F.", "0.2500")
    con("-6.0 3.0 F/ F.", "-6.0 3.0 F/ F.", "-2.0000")
    con("1.5 2.25 F+ F.", "1.5 2.25 F+ F.", "3.7500")
    con("2.0 4.0 F- F.", "2.0 4.0 F- F.", "-2.0000")
    con("7 S>F F.", "7 S>F F.", "7.0000")
    con("-3 S>F F.", "-3 S>F F.", "-3.0000")
    con("7.9 F>S .", "7.9 F>S .", "7")
    con("2.5 FROUND F>S .", "2.5 FROUND F>S .", "3")
    con("4.0 FSQRT F.", "4.0 FSQRT F.", "2.0000")
    con("0.0 SIN F.", "0.0 SIN F.", "0.0000")
    L.append(console_check("compiled float literals", "old", [
        ([": T1 1.5 2.25 F+ ;"], "T1 F.", "3.7500"),
        ([": T2 0.25 F. ;"], "T2", "0.2500"),
        ([": T3 -6.0 3.0 F/ F. ;"], "T3", "-2.0000")]))
    L.append(Check("BEEP 0.5 s plays 30 frames", "old", [task("beep_typed", dict(line="0 0.5 BEEP", frames=30))]))
    L.append(console_check("floats in CATCH", "old", [
        ([], "1.5 2.5 ' F+ CATCH . F.", "0 4.0000"),
        ([": T 2.5 7 THROW ;"], "1.5 ' T CATCH . F.", "7 1.5000")]))
    return L


# ---- the new group
NEW_WORDS = ("F+ F- F* F/ F. S>F F>S FROUND FSQRT PI SIN COS RAD DEG "
             "FDUP FDROP FSWAP FOVER FDEPTH FNEGATE FABS F< F> F= F0< F0= FMIN FMAX FLOOR F@ F! FVARIABLE FCONSTANT "
             "TAN PLACES FS.").split()

UNCAUGHT = [("1.0 0.0 F/", "DIVISION BY ZERO"), ("5 THROW", "ERROR 5"), ("' NOSUCHWORD", "UNDEFINED WORD"),
            ("-1.0 FSQRT", "INVALID ARGUMENT"), ("1E39", "OUT OF RANGE"), ("100000", "OUT OF RANGE"),
            ("-40000", "OUT OF RANGE"), ("1.5E38 1.5E38 F+", "OUT OF RANGE"), ("-8 THROW", "DICTIONARY FULL"),
            ("-13 THROW", "UNDEFINED WORD"), ("-28 THROW", "BREAK"), ("-37 THROW", "TAPE ERROR"),
            ("-42 THROW", "DIVISION BY ZERO"), ("-43 THROW", "OUT OF RANGE"), ("-46 THROW", "INVALID ARGUMENT"),
            ("-1 THROW", "ERROR -1"), ("DROP", "STACK?")]


def fixed_floats():
    return [ZERO, ONE, MONE, enc(2.0), enc(0.5), enc(-0.5), enc(3.0), enc(10.0), enc(math.pi), P.PI, enc(1e-5),
            enc(123456.789), enc(-98765.4321), bytes([255, 0x7F, 255, 255, 255]), bytes([255, 0xFF, 255, 255, 255]),
            bytes([1, 0, 0, 0, 0]), bytes([1, 0x80, 0, 0, 0]), bytes([0x90, 0x7F, 255, 255, 255])]


def new_checks(count, seed, int_n):
    L = []
    C = count

    def rngf(name):
        return random.Random("%s:%s" % (seed, name))

    # ---- the word list
    L.append(Check("float words present (34)", "new", [task("words", dict(names=NEW_WORDS))]))

    # ---- binary arithmetic, bit for bit
    for word, fn, sym in (("F+", P.add, "+"), ("F-", P.sub, "-"), ("F*", P.mul, "*"), ("F/", P.div, "/")):
        rng = rngf(word)
        cs = []
        fx = fixed_floats()
        for a in fx:
            for b in (ZERO, ONE, MONE, enc(2.0), bytes([255, 0x7F, 255, 255, 255]), bytes([1, 0, 0, 0, 0])):
                cs.append(bin_case(word, fn, a, b, interesting(rng)))
        for i in range(C):
            if sym in "+-" and i % 3 == 0:
                a, b = near(rng)
            else:
                a, b = interesting(rng), interesting(rng)
            cs.append(bin_case(word, fn, a, b, interesting(rng)))
        for i in range(C // 3):                                  # everyday sizes: results, not errors
            cs.append(bin_case(word, fn, mid(rng), mid(rng), interesting(rng)))
        L.append(case_check("%s bit for bit" % word, "new", cs))

    # ---- comparisons
    rng = rngf("cmp")
    cs = []
    for word, test in (("F<", lambda c: c < 0), ("F=", lambda c: c == 0), ("F>", lambda c: c > 0)):
        for i in range(C):
            a = interesting(rng)
            b = a if i % 7 == 0 else (near(rng)[1] if i % 3 == 0 else interesting(rng))
            cs.append(cmp_case(word, test, a, b, interesting(rng)))
        for a in fixed_floats():
            for b in fixed_floats()[:6]:
                cs.append(cmp_case(word, test, a, b, ZERO))
    L.append(case_check("F< F= F> flags", "new", cs, chunk=120))

    # ---- conversions
    rng = rngf("s>f")
    ints = [0, 1, -1, 2, -2, 255, 256, 32767, -32768, -32767, 12345, -12345, 0x4000, -0x4000, 0x7FFF - 1, 0xFF, 0x100] + \
        [s16(rng.getrandbits(16)) for _ in range(C)]
    cs = [std("S>F", [j], [v], okx([j, F.fri(v)])) for v in ints for j in (interesting(rng),)]
    L.append(case_check("S>F", "new", cs, chunk=120))

    rng = rngf("f>s")
    vals = [enc(v) for v in (0.5, -0.5, 0.9999, 1.5, -1.5, 7.9, -7.9, 32767.0, 32767.5, 32767.9, 32768.0, 32768.9, -32768.0,
                              -32768.5, -32768.9, -32769.0, 40000.0, 65535.0, 65535.99, 65536.0, -40000.0, 1e10, -1e10, 1e30)]
    vals += [ZERO] + [interesting(rng) for _ in range(C)] + [enc(rng.uniform(-70000, 70000)) for _ in range(C)]
    cs = []
    for a in vals:
        j = interesting(rng)
        r = model(P.ftos, a)
        cs.append(std("F>S", [j, a], [], th(r.code) if isinstance(r, P.Throw) else okx([j], [r])))
    L.append(case_check("F>S", "new", cs, chunk=120))

    # ---- unary words
    def unary(name, word, fn, vals, acc=None, chunk=60):
        rng = rngf(name)
        L.append(case_check(name, "new", [un_case(word, fn, a, interesting(rng), acc) for a in vals], chunk=chunk))

    rng = rngf("round-values")
    frac = [enc(v) for v in (0.5, -0.5, 0.49999, -0.49999, 1.5, -1.5, 2.5, -2.5, 3.5, 0.25, -0.75, 7.9, -7.9, 65535.5, 2147483647.5,
                              2147483648.0, -2147483649.0, 1e10, 0.999999999, 4194303.5)]
    frac += [enc(rng.uniform(-100, 100)) for _ in range(C)] + [enc(rng.randrange(-200, 200) + rng.choice((0.5, 0.25, 0.75, 0.0)))
                                                                for _ in range(C // 2)]
    frac += [interesting(rng) for _ in range(C)]
    unary("FROUND", "FROUND", P.fround, frac)
    unary("FLOOR", "FLOOR", P.ffloor, frac)
    rng = rngf("neg")
    nv = [interesting(rng) for _ in range(C)] + fixed_floats()
    unary("FNEGATE", "FNEGATE", P.neg, nv)
    unary("FABS", "FABS", P.fabs, nv)

    # ---- FSQRT, SIN, COS, TAN, RAD, DEG: bit for bit and within the section 8 accuracy
    rng = rngf("fsqrt")
    sq = [enc(4.0), enc(2.0), enc(0.25), enc(1e-30), enc(1e30), ZERO, ONE, enc(-1.0), enc(-1e-30), bytes([1, 0, 0, 0, 0]),
          bytes([255, 0x7F, 255, 255, 255]), bytes([254, 0x7F, 255, 255, 255]), bytes([127, 0, 0, 0, 0]), bytes([128, 0, 0, 0, 0]),
          bytes([129, 0, 0, 0, 0])]
    sq += [interesting(rng) for _ in range(C // 2)] + [P.fabs(interesting(rng)) for _ in range(C // 2)]
    sq += [enc(math.exp(rng.uniform(-80, 80))) for _ in range(C)] + [enc(rng.uniform(0, 1e6)) for _ in range(C // 3)]
    unary("FSQRT", "FSQRT", P.fsqrt, sq, "sqrt")

    rng = rngf("trig")
    tv = [ZERO, ONE, MONE, enc(0.5), enc(-0.5), P.PI, P.HALF_PI, enc(-math.pi), enc(math.pi / 2), enc(2 * math.pi), enc(100.0),
          enc(1e-30), enc(-1e-38), enc(1e5), enc(102940.0), enc(103000.0), enc(-102940.0), enc(-103000.0), enc(1e6), enc(1e10),
          enc(1e30), enc(3.14159), enc(1.5707963), enc(45.0), enc(-90.0), bytes([255, 0x7F, 255, 255, 255]), bytes([1, 0, 0, 0, 0])]
    for lim in (math.pi / 2, 100.0, 102000.0):
        tv += [enc(rng.uniform(-lim, lim)) for _ in range(C // 2)]
    tv += [interesting(rng) for _ in range(C // 3)]
    for name, fn, acc in (("SIN", P.fsin, "sin"), ("COS", P.fcos, "cos")):
        unary(name, name, fn, tv, acc)
    tt = [v for v in tv if True] + [enc(rng.uniform(-1.57, 1.57)) for _ in range(C // 2)]
    unary("TAN", "TAN", P.ftan, tt, "tan")

    rng = rngf("raddeg")
    rv = [ZERO, ONE, MONE, enc(180.0), enc(360.0), enc(90.0), enc(-45.0), enc(math.pi), enc(1e30), enc(-1e38), bytes([255, 0x7F, 255, 255, 255]),
          enc(1e-30), bytes([1, 0, 0, 0, 0])]
    rv += [enc(rng.uniform(-1000, 1000)) for _ in range(C)] + [interesting(rng) for _ in range(C // 2)]
    unary("RAD", "RAD", P.frad, rv, "rad")
    unary("DEG", "DEG", P.fdeg, rv, "deg")

    # ---- the stack words, FDEPTH, tests against zero, min and max, memory
    rng = rngf("stackwords")
    cs = []
    for _ in range(C // 2):
        a, b, j = interesting(rng), interesting(rng), interesting(rng)
        cs += [std("FDUP", [j, a], [], okx([j, a, a])), std("FDROP", [j, a], [], okx([j])),
               std("FSWAP", [j, a, b], [], okx([j, b, a])), std("FOVER", [j, a, b], [], okx([j, a, b, a]))]
    L.append(case_check("FDUP FDROP FSWAP FOVER", "new", cs, chunk=120))
    cs = []
    for n in list(range(0, 8)) + [50, 100, 203, 204]:
        cs.append(std("FDEPTH", [interesting(rng) for _ in range(n)], [], None))
        cs[-1]["exp"] = okx(cs[-1]["f"], [n])
    L.append(case_check("FDEPTH", "new", cs))
    cs = []
    for _ in range(C):
        a, b, j = interesting(rng), (interesting(rng) if rng.random() < 0.6 else None), interesting(rng)
        b = a if b is None else b
        lo = a if P.cmp(a, b) <= 0 else b
        hi = b if P.cmp(a, b) <= 0 else a
        cs += [std("FMIN", [j, a, b], [], okx([j, lo])), std("FMAX", [j, a, b], [], okx([j, hi]))]
    L.append(case_check("FMIN FMAX", "new", cs, chunk=120))
    cs = []
    for a in fixed_floats() + [interesting(rng) for _ in range(C)]:
        j = interesting(rng)
        cs += [std("F0<", [j, a], [], okx([j], [flag(P.is_neg(a))])), std("F0=", [j, a], [], okx([j], [flag(a[0] == 0)]))]
    L.append(case_check("F0< F0=", "new", cs, chunk=120))
    cs = []
    pre_guard = bytes([GUARD] * 4)
    for _ in range(C // 2):
        a, j = interesting(rng), interesting(rng)
        cs.append(std("F@", [j], [MEMA], okx([j, a]), pre=[(MEMA - 4, pre_guard + a + pre_guard)]))
        cs.append(std("F!", [j, a], [MEMA], okx([j]), pre=[(MEMA - 4, pre_guard + bytes(5) + pre_guard)],
                      mem=[(MEMA - 4, pre_guard + a + pre_guard)]))
    L.append(case_check("F@ F!", "new", cs, chunk=120))

    # ---- numbers in: NUMBER white box, then typed and compiled at the console
    rng = rngf("lits")
    toks = LIT_TEXTS + LIT_MORE + INT_TEXTS + BAD_TEXTS + random_texts(rng, C)
    cs = []
    for t in toks:
        r = model(P.parse, t)
        cs.append(dict(kind="number", word="NUMBER", text=t, f=[], i=[], exp=th(r.code) if isinstance(r, P.Throw) else r))
    L.append(case_check("literals: NUMBER", "new", cs, chunk=120))
    ftoks = [t for t in LIT_TEXTS + LIT_MORE if P.parse(t)[0] == "float"]
    ftoks_r = [t for t in random_texts(rng, max(8, C // 4)) if isinstance(model(P.parse, t), tuple) and P.parse(t)[0] == "float"]
    for mode in ("typed", "compiled"):
        toks_m = ftoks + ftoks_r
        L.append(Check("literals: %s" % mode, "new", [task("lit", dict(mode=mode, tokens=c), 3 * len(c)) for c in chunks(toks_m, 24)]))

    # ---- errors
    # Defects fixed in step O15 (ROADMAP.md): the 8th nested CATCH frame overlapped SPACES' count (a THROW to it then
    # restored a wrong SP), and a data stack deeper than about 1,020 cells overwrote LATEST and HERE
    L.append(console_check("8 nested CATCH frames, SPACES in the innermost", "new", [
        ([': C0 3 SPACES 99 THROW ;', "' C0 CONSTANT K0", ': C1 K0 CATCH ;', "' C1 CONSTANT K1", ': C2 K1 CATCH ;', "' C2 CONSTANT K2", ': C3 K2 CATCH ;', "' C3 CONSTANT K3", ': C4 K3 CATCH ;', "' C4 CONSTANT K4", ': C5 K4 CATCH ;', "' C5 CONSTANT K5", ': C6 K5 CATCH ;', "' C6 CONSTANT K6", ': C7 K6 CATCH ;', "' C7 CONSTANT K7"], "K7 CATCH . . . . . . . .", "0 0 0 0 0 0 0 99")]))
    L.append(console_check("a 1,100-cell data stack leaves the dictionary intact", "new", [
        ([": DEEP 1100 0 DO I LOOP 1100 0 DO DROP LOOP ;", "DEEP"], ": SQ DUP * ; 7 SQ .", "49")]))
    L.append(console_check("errors under CATCH (-42 -43 -46)", "new", [
        ([], "1.0 0.0 ' F/ CATCH .", "-42"),
        ([], "1E38 1E38 ' F* CATCH .", "-43"),
        ([], "1.5E38 1.5E38 ' F+ CATCH .", "-43"),
        ([], "-1.0 ' FSQRT CATCH .", "-46"),
        ([], "65536.0 ' F>S CATCH .", "-43"),   # READING: 40000.0 is inside -32768..65535 (spec 8.1), 65536.0 is not
        ([], "-32769.0 ' F>S CATCH .", "-43"),
        ([], "11 ' PLACES CATCH .", "-43"),
        ([], "-1 ' PLACES CATCH .", "-43"),
        ([], "200000.0 ' SIN CATCH .", "-43"),
        ([], "9 ' PLACES CATCH .", "0"),
        ([], "0 ' PLACES CATCH .", "0")]))
    cs = []
    for p in (10, 11, 255, 0xFFFF, 0x8000):
        cs.append(std("PLACES", [], [p], th(-43)))
    for p in range(10):
        cs.append(std("PLACES", [], [p], okx()))
    L.append(case_check("PLACES range", "new", cs, chunk=30))

    # ---- text out
    rng = rngf("fdot")
    vals = [enc(v) for v in (0.0, 1.0, -1.0, 0.5, 6.0, 0.25, -2.0, -0.00001, 0.99995, 99999.99995, 0.00005, 1e38, 1.7e38, 123456789.123456,
                              2.0 ** 31, 0.00004, -0.00004, -0.00005, 3.14159265, 1e-30)]
    vals += [interesting(rng) for _ in range(C)] + [enc(rng.uniform(-1e5, 1e5)) for _ in range(C // 3)] + [mid(rng) for _ in range(C // 3)]
    cs = [dict(kind="print", word="F.", f=[a], i=[], text=P.fdot(a, 4)) for a in vals]
    L.append(case_check("F. text (4 places)", "new", cs, chunk=40))
    cs = []
    for p in range(10):
        pv = [enc(v) for v in (0.0, 1.0, -1.0, 0.5, -0.5, 2.5, 0.99999999999, 9.5, 99999.99999, 123.456789012, -7.123456789, 1e-5, -1e-5,
                                4e-10, -4e-10, 0.00004, -0.00004, -0.00006, 5e-10, -5e-10, 1e15)]
        pv += [mid(rng) for _ in range(max(6, C // 15))]
        cs += [dict(kind="print", word="F.", f=[a], i=[], places=p, text=P.fdot(a, p)) for a in pv]
    L.append(case_check("F. PLACES 0-9", "new", cs, chunk=50))
    cs = []
    for v, p, t in ((-0.00001, 4, "0.0000"), (-0.00004, 4, "0.0000"), (-0.00006, 4, "-0.0001"), (-0.4, 0, "0"), (-0.5, 0, "-1"),
                    (-1e-10, 4, "0.0000"), (-4e-10, 9, "0.000000000"), (-0.0, 4, "0.0000"),
                    (-0.0004, 3, "0.000"), (-0.0006, 3, "-0.001"), (-1e-30, 2, "0.00")):
        a = enc(v)
        assert P.fdot(a, p) == t, (v, p, t, P.fdot(a, p))
        cs.append(dict(kind="print", word="F.", f=[a], i=[], places=p, text=t))
    L.append(case_check("F. no -0.0000", "new", cs, chunk=30))
    cs = []                                     # exact ties round half up (away from 0); 9 places resolved (spec 7)
    for v, p, t in ((0.25, 1, "0.3"), (-0.25, 1, "-0.3"), (0.03125, 4, "0.0313"), (0.5, 0, "1"), (2.5, 0, "3"),
                    (0.125, 2, "0.13"), (9.99996, 4, "10.0000"), (-6e-10, 9, "-0.000000001"), (5.1e-10, 9, "0.000000001"),
                    (1.5e-9, 9, "0.000000002"), (0.999999999, 9, "0.999999999")):
        a = enc(v)
        assert P.fdot(a, p) == t, (v, p, t, P.fdot(a, p))
        cs.append(dict(kind="print", word="F.", f=[a], i=[], places=p, text=t))
    L.append(case_check("F. exact ties and 9 places", "new", cs, chunk=30))
    rng = rngf("fsdot")
    sv = [enc(v) for v in (1e-6, -12345.678, 0.0, 1.0, 9.99995, 99999.5, 10.0, 0.1, 1.7e38, 3e-39, 123456789012.0, -1e-10, 3.14159265, 0.9999999999)]
    sv += [interesting(rng) for _ in range(C)] + [enc(rng.choice((-1, 1)) * math.exp(rng.uniform(-87, 87))) for _ in range(C)]
    cs = []
    for a in sv:
        p = rng.randrange(10) if rng.random() < 0.5 else 4
        t = P.fsdot(a, p)
        d = dict(kind="print", word="FS.", f=[a], i=[], places=p, text=t)
        # READING: against Python only for 0-4 decimals (spec 7: "with 4 decimals never visibly"; at more decimals the
        # three roundings of the scaling can show), and the model's tie rule leaves exact ties out (python_sci).
        if p <= 4 and a[0]:
            d["python"] = python_sci(a, p)             # (None for an exact tie)
        cs.append(d)
    L.append(case_check("FS. text", "new", cs, chunk=40))

    # ---- stack and variables at the console
    L.append(Check("float stack: 204 cells", "new", [task("stack", dict(mode="204"))]))
    L.append(Check("float stack: the 205th push", "new", [task("stack", dict(mode="205"))]))
    L.append(console_check("FVARIABLE typed", "new", [
        (["FVARIABLE FA", "FVARIABLE FB", "2.5 FA F!", "-7.25 FB F!"], "FA F@ F. FB F@ F. FA F@ FB F@ F+ F.", "2.5000 -7.2500 -4.7500")]))
    L.append(console_check("FVARIABLE compiled", "new", [
        (["FVARIABLE FA", ": TV 1.25 FA F! FA F@ FA F@ F+ F. ;"], "TV", "2.5000")]))
    L.append(console_check("FCONSTANT typed", "new", [
        (["3.25 FCONSTANT FK"], "FK F. FK FK F* F.", "3.2500 10.5625"),
        (["-0.5 FCONSTANT FK2"], "FK2 FK2 F- F. FK2 F.", "0.0000 -0.5000")]))
    L.append(console_check("FCONSTANT compiled", "new", [
        (["3.25 FCONSTANT FK", ": TT FK 2.0 F* F. ;"], "TT", "6.5000")]))
    L.append(Check("uncaught THROW messages", "new", [task("uncaught", dict(lines=UNCAUGHT), len(UNCAUGHT))]))

    # ---- integer * / MOD (O10)
    rng = rngf("ints")
    pairs = int_pairs(rng, int_n)
    for word in ("*", "/", "MOD"):
        L.append(Check("integer %s" % word, "new", [task("int", dict(word=word, pairs=c), len(c) // 8) for c in chunks(pairs, 1500)]))

    # ---- RND (F8)
    rng = rngf("rnd")
    for seed in (1, 0x1234, 0xFFFF):
        ns = [rng.choice((6, 10, 100, 1000, 32767, 1, 2, 3, 7, 12345, 0, 0xFFFF, 0x8000, 0xFFFB, rng.randrange(1, 32768))) for _ in range(1000)]
        L.append(Check("RND 1000 results (seed %d)" % seed, "new", [task("rnd_seq", dict(seed=seed, ns=ns), 40)]))
    L.append(Check("RND 6: all 36 consecutive pairs", "new", [task("rnd_seq", dict(seed=1, ns=[6] * 3600, pairs=36), 120)]))
    L.append(Check("0 RANDOMIZE reseeds from R", "new", [task("rnd_reseed", dict(delays=[0, 1, 2, 3, 5, 8, 13, 21, 34, 55]), 10)]))

    # ---- BEEP
    rng = rngf("beep")
    durs = [0.5, 0.25, 1.0, 2.5, 0.0083, 0.0084, 0.0082, 0.01, 0.0166667, 0.1, 0.08, 0.3, 546.1, 546.2, 546.0, 10000.0, 1e6, 1e30,
            -1.0, -0.001, 0.0, 1e-5, 1e-30, 0.02, 0.0249, 0.025, 5.0, 60.0, 109.0]
    durs = [enc(d) for d in durs] + [enc(rng.uniform(0, 3)) for _ in range(C // 10)]
    cs = []
    for d in durs:
        n = rng.choice((0, 12, -5, 69, -60, 30))
        cs.append(dict(kind="beep", word="BEEP", f=[d], i=[n], frames=P.beep_frames(d)))
    L.append(case_check("BEEP frames", "new", cs, chunk=60))

    # ---- the model against Python's floats (no ROM)
    # READING: spec section 13 lists this under "new"; it needs no ROM, so it also passes on the old build.
    L.append(Check("model vs Python floats (2^-30)", "new", [], parent=("model_py", C)))
    return L


def python_sci(a, p):
    """Python's scientific text of the 5-byte a with p decimals: the exact decimal value rounded half up, or None for an
    exact tie.  READING: %.pE would round ties half even; FS. rounds its scaled value half up, and the scaling can move
    a value on or off a tie, so exact ties are left out of the comparison with Python."""
    up = decimal.Context(prec=p + 1, rounding=decimal.ROUND_HALF_UP)
    down = decimal.Context(prec=p + 1, rounding=decimal.ROUND_HALF_DOWN)
    d = up.create_decimal(F.value(a))
    if d != down.create_decimal(F.value(a)):
        return None
    mant, ex = ("%.*E" % (p, d)).split("E")
    return mant + "E" + str(int(ex))


def model_py(rng, count):
    """fpmodel against Python's own floats (32-bit mantissa: relative 2^-31); Leap-C tools/floattest.py."""
    bad = []
    for _ in range(count):
        x, y = rng.uniform(-1e6, 1e6), rng.uniform(-1e6, 1e6)
        a, b = enc(x), enc(y)
        for sym, real in (("+", lambda p, q: p + q), ("-", lambda p, q: p - q), ("*", lambda p, q: p * q), ("/", lambda p, q: p / q)):
            want = real(F.value(a), F.value(b))
            got = F.value(F.binop(sym, a, b))
            tol = 2.0 ** -30 * (abs(want) if sym in "*/" else max(abs(F.value(a)), abs(F.value(b))))
            if abs(got - want) > tol:
                bad.append("model %r %s %r = %r, real %r" % (F.value(a), sym, F.value(b), got, want))
    return result(count * 4, count * 4, bad)


# ---- the speed group
def speed_tasks():
    p3 = enc(3.14159)
    e2 = enc(2.71828)
    big = lambda k: enc(1.5 * 2.0 ** k)                                  # noqa: E731
    items = [
        ("F+ exponent difference 0", dict(word="F+", f=[enc(1.5), enc(1.25)])),
        ("F+ exponent difference 8", dict(word="F+", f=[big(8), enc(1.5)])),
        ("F+ exponent difference 30", dict(word="F+", f=[big(30), enc(1.5)])),
        ("F* 3.14159 2.71828", dict(word="F*", f=[p3, e2])),
        ("F/ 3.14159 2.71828", dict(word="F/", f=[p3, e2])),
        ("F. 3.14159", dict(word="F.", f=[p3], print=True)),
        ("FS. 3.14159", dict(word="FS.", f=[p3], print=True)),
        ("literal 3.14159 (NUMBER)", dict(word="NUMBER", i=[TEXT], text="3.14159")),
        ("literal 12345 (NUMBER)", dict(word="NUMBER", i=[TEXT], text="12345")),
        ("FSQRT 2.0", dict(word="FSQRT", f=[enc(2.0)])),
        ("SIN 1.0", dict(word="SIN", f=[ONE])),
        ("* 1234 567", dict(word="*", i=[1234, 567], catch=False)),
        ("/ 60000 7", dict(word="/", i=[60000, 7], catch=False)),
        ("MOD 60000 7", dict(word="MOD", i=[60000, 7], catch=False)),
        ("RND 6 (seed 1)", dict(word="RND", i=[6], seed=1, catch=False)),
    ]
    return [Check(n, "speed", [task("speed", dict(name=n, **kw))]) for n, kw in items]


def build_checks(group, count, seed, int_n, only):
    L = []
    if group in ("old", "gated", "all"):
        L += old_checks()
    if group in ("new", "gated", "all"):
        L += new_checks(count, seed, int_n)
    if group in ("speed", "all"):
        L += speed_tasks()
    if only:
        L = [c for c in L if any(s.lower() in c.name.lower() or s.lower() == c.group for s in only)]
    names = [c.name for c in L]
    assert len(names) == len(set(names)), "duplicate check names: %s" % sorted({n for n in names if names.count(n) > 1})
    return L


# ---------------------------------------------------------------------------------------------------- the run
def cut(s, n):
    return s if len(s) <= n else s[:n - 3] + "..."


def suite(build, only=(), json_out=None, verbose=False, group="all", count=300, seed="13", int_n=40000):
    """The checks as one fharness.Suite (tools/run_tests.py; run_all runs it alone)."""
    checks = build_checks(group, count, seed, int_n, only)
    if not checks:
        raise ValueError("floattest: no check matches %r" % (only,))
    flat = [t for c in checks for t in c.tasks]
    return fh.Suite("float", flat, run_task, lambda res, wall: report(checks, res, wall, build, json_out, verbose, group,
                                                                       count, seed, int_n))


def run_all(build, workers, port0, only, json_out, verbose, group, count, seed, int_n):
    return suite(build, only, json_out, verbose, group, count, seed, int_n).run_alone(build, workers, port0)


def report(checks, res, wall, build, json_out, verbose, group, count, seed, int_n):
    results = dict(enumerate(res))
    flat = res
    parent = {}
    for ci, c in enumerate(checks):
        if c.parent:
            kind, cnt = c.parent
            parent[ci] = model_py(random.Random("%s:model" % seed), cnt)
    out, tally = [], {}
    speed = {}
    pos = 0
    for ci, c in enumerate(checks):
        rs = []
        for _ in c.tasks:
            rs.append(results[pos])
            pos += 1
        if ci in parent:
            rs.append(dict(parent[ci], wall=0.0))
        ok = all(r["ok"] for r in rs)
        if c.group == "speed":
            d = rs[0].get("data") or dict(name=c.name, tstates=None)
            speed[c.name] = d
            ok = rs[0]["ok"]
        n = sum(r.get("n", 0) for r in rs)
        nfail = sum(r.get("nfail", 0) for r in rs)
        if ok:
            detail = rs[0]["detail"] if len(rs) == 1 else "%d cases in %d tasks" % (n, len(rs))
        else:
            bad = [r for r in rs if not r["ok"]]
            detail = bad[0]["detail"]
            if nfail and len(bad) > 0:
                total = sum(r.get("n", 0) for r in rs)
                detail = "%d of %d cases fail; first: %s" % (nfail, total, bad[0]["detail"].split("first: ", 1)[-1])
        wall_c = sum(r["wall"] for r in rs)
        out.append(dict(check=c.name, group=c.group, ok=ok, detail=detail, wall=round(wall_c, 2), tasks=len(rs)))
        if c.group != "speed":
            tally.setdefault(c.group, [0, 0])
            tally[c.group][0] += ok
            tally[c.group][1] += 1
        line = detail if verbose else cut(detail, 230)
        verdict = "PASS" if ok else "FAIL"
        if c.group == "speed" and not ok and " missing in this build" in detail:
            verdict = "SKIP"
        print("%s %-5s %-34s %s  [%.1f s]" % (verdict, c.group, c.name, line, wall_c), flush=True)
    if speed:
        print_speed(speed)
    total = sum(t[1] for t in tally.values())
    passed = sum(t[0] for t in tally.values())
    harness_error = bool(flat) and (all(r["detail"].startswith("TASK FAILED") for r in results.values()) or any(
        r["detail"].startswith(("worker on port", "never ran")) for r in results.values()))
    print("floattest: %d/%d checks pass (%s); wall %.1f s" % (
        passed, total, ", ".join("%s %d/%d" % (g, t[0], t[1]) for g, t in sorted(tally.items(), reverse=True)) or "no gated group", wall))
    if json_out:
        os.makedirs(os.path.dirname(os.path.abspath(json_out)), exist_ok=True)
        json.dump(dict(build=build, group=group, count=count, seed=seed, int_pairs=int_n, passed=passed, total=total,
                       groups={g: dict(passed=t[0], total=t[1]) for g, t in tally.items()}, checks=out, speed=speed,
                       wall=round(wall, 2)), open(json_out, "w"), indent=1)
    failed = total - passed
    return 2 if harness_error else (1 if failed else 0)


def print_speed(speed):
    print("speed, T-states per call on fixed operands (least of 3 runs; recorded, not gated):")
    for name, d in speed.items():
        t = d.get("tstates")
        print("  %-30s %12s" % (name, "%d" % t if t is not None else "missing/failed"))


# ---------------------------------------------------------------------------------------------------- self-test
def selftest(count, seed, int_n):
    t0 = time.time()
    bad = []
    sha = hashlib.sha256(open(os.path.join(HERE, "fpmodel.py"), "rb").read()).hexdigest()
    sha_ok = sha == P.FPMODEL_SHA256
    print("fpmodel.py sha256 %s: %s" % (sha[:16], "matches fpforth.FPMODEL_SHA256 (Leap-C %s)" % P.FPMODEL_COMMIT if sha_ok else "DIFFERS from " + P.FPMODEL_SHA256[:16]))
    if not sha_ok:
        bad.append("fpmodel.py sha256")
    fbad, worst = P.selftest()
    for k, v in sorted(worst.items()):
        print("  fpforth worst %-22s %.3g" % (k, v))
    print("fpforth selftest: %d failure(s)" % len(fbad))
    bad += ["fpforth: " + b for b in fbad[:10]]
    checks = build_checks("all", count, seed, int_n, [])
    ntask = sum(len(c.tasks) for c in checks)
    # the generators ran (expected values computed by the model for every case); the accuracy gates on the model's own results
    ncase = nacc = 0
    for c in checks:
        for t in c.tasks:
            for cs in t["args"].get("cases", ()):
                ncase += 1
                if cs.get("acc") and cs["exp"][0] == "ok":
                    nacc += 1
                    msg = ACC[cs["acc"]](cs["x"], cs["exp"][1][-1])
                    if msg:
                        bad.append("model fails its own gate: " + msg)
                if cs.get("python"):
                    if P.fsdot(cs["f"][-1], cs["places"]) != cs["python"]:
                        bad.append("FS. model %s vs Python %s" % (P.fsdot(cs["f"][-1], cs["places"]), cs["python"]))
    for c in checks:
        if c.parent:
            r = model_py(random.Random("%s:model" % seed), c.parent[1])
            print("model vs Python floats: %s" % r["detail"])
            if not r["ok"]:
                bad.append(r["detail"])
    names = {c.group: 0 for c in checks}
    for c in checks:
        names[c.group] += 1
    print("generators: %d checks (%s), %d tasks, %d cases, %d accuracy gates on the model; %.1f s" % (
        len(checks), ", ".join("%s %d" % kv for kv in sorted(names.items())), ntask, ncase, nacc, time.time() - t0))
    for b in bad[:20]:
        print("FAIL", b)
    print("floattest selftest: %d failure(s)" % len(bad))
    return 0 if not bad else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"), help="directory with forth_boot_rom0.bin (DIR or DIR/build)")
    ap.add_argument("--group", choices=("old", "new", "speed", "gated", "all"), default="all", help="old: kept behaviour; new: the spec; speed: T-states; gated: old and new; all (default)")
    ap.add_argument("--count", type=int, default=300, help="random cases per operation (default 300)")
    ap.add_argument("--int-pairs", type=int, default=40000, help="pairs for the integer * / MOD checks (default 40000)")
    ap.add_argument("--seed", default="13", help="seed of the random cases (default 13)")
    ap.add_argument("--workers", type=int, default=None, help="emulators in parallel (default: fharness.default_workers())")
    ap.add_argument("--port", type=int, default=PORT0, help="first ZRCP port (default %d; 10840-10859)" % PORT0)
    ap.add_argument("--json", default=os.path.join(ROOT, "build", "floattest.json"), help="write the results here (default build/floattest.json)")
    ap.add_argument("--selftest", action="store_true", help="no emulator: fpforth's self-test, the fpmodel.py hash, the generators")
    ap.add_argument("-v", "--verbose", action="store_true", help="print the full detail of every check")
    ap.add_argument("only", nargs="*", help="run the checks whose name contains one of these (or whose group is this)")
    a = ap.parse_args()
    if a.selftest:
        return selftest(a.count, a.seed, a.int_pairs)
    try:
        build = fh.resolve_build(a.build)
        return run_all(build, a.workers, a.port, a.only, a.json, a.verbose, a.group, a.count, a.seed, a.int_pairs)
    except (FileNotFoundError, ValueError, RuntimeError) as e:
        print("floattest: harness error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
