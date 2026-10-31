#!/usr/bin/env python3
"""shapetest.py - the FILL and CIRCLE oracle (audit item T14, docs/V2/FILL_CIRCLE_SPEC.md section 9), for step O15.

Checks the Forth words FILL ( x y -- ) and CIRCLE ( xc yc r -- ) against a Python model of the spec (sections 4.1 and 5):
the screen (bitmap and attributes; in HIRES the per-scanline attributes of the second display file) must be exactly what
the model says, nothing else in RAM may change except the scratch the words own, and the call must return.  Today the
words run in HOME (kernel/graphics GFX_FILL / GFX_CIRCLE); after step O15 they run in the EXROM behind HOME stubs.  The
tool works on both builds unchanged: it finds the words by walking the dictionary, never by kernel symbols.

RUN   python3 -I tools/shapetest.py [--build DIR] [--group old|new|speed|all] [--workers N] [--port P] [--json OUT]
                                    [--compare FILE] [-v] [--selftest] [substring ...]
      DIR holds forth_boot_rom0.bin and graphics_exrom.bin (default: build/; DIR or DIR/build, as tools/fharness.py, so
      the images of an older build in a git worktree work).  Substrings select checks by name (case-insensitive) or by
      group.  One PASS/FAIL line per check, then the speed table and a summary
          shapetest: N/M checks pass (old a/b, new c/d, speed e/f); wall S s
      Exit 0 = every selected check passes, 1 = any fails, 2 = harness error (bad build directory, port in use, no
      emulator could run a task).  JSON (default build/shapetest.json): every check with its detail, and the speed
      figures (T-states), the file --compare takes.  Ports P .. P+workers-1, default 10860-10879 (this tool's range;
      fharness.PORT_RANGES).  --selftest needs no emulator: the models on hand-checked pictures.
      --compare FILE: the JSON of an earlier run (e.g. the old build's).  Every speed case must then take no more
      T-states than FILE says, else it fails with "slower than old"; a table of old T / new T / ratio is printed.
      Without --compare a speed case passes when it ran and its screen is right.

GROUPS (FILL_CIRCLE_SPEC section 9)
  old    behaviour the spec keeps: FILL on a box, an octagon, a recolour, an L, a spiral, a blank screen, a lone pixel;
         FILL in HIRES does nothing; CIRCLE of radius 0, 1, 2, 5, 20, 90, cut by the right and bottom edges, with INK and
         PAPER, in HIRES.  Must pass on the old build and the new one.
  new    the spec: FILL on a noise screen that overflows the old 512-entry seed stack (the region must be complete), FILL
         seeds outside the screen (nothing changes), CIRCLE with a negative or beyond-the-screen centre, a radius above
         255, a negative radius (nothing).  Fails on the old build (low bytes, dropped seeds), passes on the new one.
  speed  T-states of FILL on a box, the full screen, a solid disc recoloured, a 3-pixel pocket and a worst-case serpentine;
         of CIRCLE at r 5, 40, 90, 200; recorded, gated only by --compare (new <= old).  The screen check still applies.
         `speed_repeat` runs one FILL case twice and requires the same T-states (the figures are deterministic).

HOW A CASE RUNS (white box).  The machine is restored to its booted state; the set-up lines are typed at the console
(fharness.Console.type: CLS INK PAPER PLOT LINE RECT HIRES NORMAL and numbers, words this step does not change).  The
lines print "OK" at the top of the text screen; those rows (0 .. PRINT_ROW) are cleared again so the drawing is the whole
picture.  A case whose picture is too big to type (a noise screen, a solid disc) writes the whole bitmap into screen RAM
with Machine.write instead.  Then for each call: bitmap, attributes, the second display file in HIRES, and RAM from $5B00
to $FDFF are read; the word's code address (found in the dictionary) is called with its arguments as ints on the data
stack (IX = DSTACK_TOP - 2 n), SP = RET_SLOT with STOP_ADDR as the return slot, timed with the emulator's partial
T-state counter (50 Hz interrupt service inside the call is included); then everything is read again and compared:
  1. screen against the model;
  2. RAM outside the screen: ram_diff of before and after.  Allowed to change: $5B00-$7FFF (the shadow plane and the seed
     stack; in HIRES it holds the second display file, whose bytes are checked against the model instead) and every
     label of forth_boot.sym (the HOME image's own symbols; the EXROM's labels are dictionary RAM addresses) whose name
     starts with GFX_FILL_, GFX_CIRCLE_, GFX_CLIP_, GFX_PIXEL_ (today's scratch cells) or FILL_, CIRCLE_ (the cells step
     O15 gives them), or is PORT_FF_SHADOW, BANK_EXROM_DEPTH, FRAMES or starts with KBD_, each up to the next label.
     $FE00-$FFFF is the machine stack and the harness slots.  IX back at DSTACK_TOP, SP at the normal return, and
     BANK_EXROM_DEPTH 0 at the end;
  3. the call returned to STOP_ADDR within the instruction budget (FILL: 800 million instructions, because today's FILL
     needs up to about 10^8 T-states; CIRCLE: 100 million).

EMULATOR LIMITS: there is no hardware here.  Every verdict is ZEsarUX's (its Z80, its screen RAM, its interrupt timing)
running the ROM image; the screen is read from RAM, not from a display.
"""
import argparse
import bisect
import json
import os
import random
import struct
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fharness as fh                                                     # noqa: E402

ROOT = fh.ROOT
PORT0 = 10860
STOP_ADDR, RET_SLOT = fh.STOP_ADDR, fh.RET_SLOT
NORMAL_SP = RET_SLOT + 2                # SP after a normal return (the `ret` pops the slot)
BITMAP, ATTRS, SCREEN_END = 0x4000, 0x5800, 0x5B00
HI_ATTRS, HI_SIZE = 0x6000, 0x1800      # include/hardware.inc SECOND_DISPLAY_ADDR; one attribute byte per scanline and column
POOL_LO, POOL_HI = 0x5B00, 0x7FFF       # the shadow plane and the seed stack (FILL_CIRCLE_SPEC section 7)
RAM_LO, RAM_HI = 0x5B00, 0xFDFF         # RAM compared outside the screen; $FE00-$FFFF: machine stack, harness slots
LATEST_DEFAULT, DSTACK_DEFAULT = 0x8608, 0x9800
BUDGET = dict(FILL=800_000_000, CIRCLE=100_000_000, PLOT=1_000_000, LINE=10_000_000)     # instructions; today's FILL can need ~10^8 T-states
TYPE_MAXI = 1_000_000                   # instructions a typed key may take before the console counts as stuck
LINE_MAX = 100                          # characters per typed line (EDIT_MAX_LEN is 128)
ALLOWED_PREFIX = ("GFX_FILL_", "GFX_CIRCLE_", "GFX_CLIP_", "GFX_PIXEL_", "GFX_LINE_", "FILL_", "CIRCLE_", "KBD_")
ALLOWED_NAMES = ("PORT_FF_SHADOW", "BANK_EXROM_DEPTH", "FRAMES")


class Missing(Exception):
    """A word the build does not have."""


class SetupError(Exception):
    """The set-up did not draw what the case assumes (a bug in the case, not in the ROM)."""


# ---------------------------------------------------------------------------------------------------- the model
def s16(v):
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def saddr(x, y):
    """Offset from $4000 of the bitmap byte of pixel (x, y)."""
    return ((y & 0xC0) << 5) | ((y & 7) << 8) | ((y & 0x38) << 2) | (x >> 3)


def getpix(bmp, x, y):
    return bmp[saddr(x, y)] >> (7 - (x & 7)) & 1


def setpix(bmp, x, y):
    bmp[saddr(x, y)] |= 0x80 >> (x & 7)


def attr_off(x, y):
    return (y >> 3) * 32 + (x >> 3)


def planes(bmp):
    """The bitmap as a flat list of pixel values, index y * 256 + x."""
    p = bytearray(256 * 192)
    for y in range(192):
        base = saddr(0, y)
        for xb in range(32):
            b = bmp[base + xb]
            if b:
                o = y * 256 + xb * 8
                for k in range(8):
                    p[o + k] = b >> (7 - k) & 1
    return p


def fill_region(bmp, x, y):
    """The 4-connected region of pixels equal to the seed (x, y), a list of (x, y); the seed must be on the screen."""
    p = planes(bmp)
    v = p[y * 256 + x]
    seen = bytearray(256 * 192)
    seen[y * 256 + x] = 1
    todo, out = [y * 256 + x], []
    while todo:
        i = todo.pop()
        out.append((i & 255, i >> 8))
        cx, cy = i & 255, i >> 8
        for nx, ny in ((cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)):
            if 0 <= nx < 256 and 0 <= ny < 192:
                j = ny * 256 + nx
                if not seen[j] and p[j] == v:
                    seen[j] = 1
                    todo.append(j)
    return out


def model_fill(bmp, attr, hi, x, y, cur, mode):
    """FILL_CIRCLE_SPEC 4.1.  Returns (bmp, attr, hi, n): copies after the call and the region's size (0 = nothing done)."""
    bmp, attr, hi = bytearray(bmp), bytearray(attr), bytearray(hi) if hi is not None else None
    x, y = s16(x), s16(y)
    # READING: "if GFX_MODE is nonzero (HIRES) nothing changes", checked before the seed's range (both do nothing).
    if mode or not (0 <= x <= 255 and 0 <= y <= 191):
        return bmp, attr, hi, 0
    region = fill_region(bmp, x, y)
    for px, py in region:
        setpix(bmp, px, py)
        attr[attr_off(px, py)] = cur
    return bmp, attr, hi, len(region)


def circle_points(xc, yc, r):
    """FILL_CIRCLE_SPEC 5 (the task's statement of it): the midpoint circle on signed values; the points, in order."""
    xc, yc, r = s16(xc), s16(yc), s16(r)
    pts = []
    if r < 0:
        return pts
    px, py, err = r, 0, 1 - r
    while py <= px:
        for dx, dy in ((px, py), (-px, py), (px, -py), (-px, -py), (py, px), (-py, px), (py, -px), (-py, -px)):
            pts.append((xc + dx, yc + dy))
        py += 1
        if err < 0:
            err += 2 * py + 1
        else:
            px -= 1
            err += 2 * (py - px) + 1
    return pts


def model_circle(bmp, attr, hi, xc, yc, r, cur, mode):
    """Returns (bmp, attr, hi, n): copies after the call, n = points on the screen.  Each point on the screen (0-255,
    0-191) is set (OR) and its attribute cell gets `cur` (in HIRES the per-scanline attribute of that column instead)."""
    bmp, attr, hi = bytearray(bmp), bytearray(attr), bytearray(hi) if hi is not None else None
    n = 0
    for x, y in circle_points(xc, yc, r):
        if 0 <= x <= 255 and 0 <= y <= 191:
            setpix(bmp, x, y)
            if mode:
                hi[saddr(x, y)] = cur           # the SCLD's 8x1 attribute: the bitmap byte + $2000
            else:
                attr[attr_off(x, y)] = cur
            n += 1
    return bmp, attr, hi, n


def model_plot_points(bmp, attr, hi, pts, cur, mode):
    """Each point on the screen (0-255, 0-191) set, its cell (HIRES: its 8x1 attribute) coloured."""
    bmp, attr, hi = bytearray(bmp), bytearray(attr), bytearray(hi) if hi is not None else None
    n = 0
    for x, y in pts:
        if 0 <= x <= 255 and 0 <= y <= 191:
            setpix(bmp, x, y)
            if mode:
                hi[saddr(x, y)] = cur
            else:
                attr[attr_off(x, y)] = cur
            n += 1
    return bmp, attr, hi, n


def line_points(x0, y0, x1, y1):
    """LINE takes its coordinates as bytes (0-255); only vertical lines are modelled (a READING: their pixels are the
    same for any line algorithm), the y range is clipped to the screen by the model's caller."""
    x0, y0, x1, y1 = x0 & 0xFF, y0 & 0xFF, x1 & 0xFF, y1 & 0xFF
    if x0 != x1:
        raise SetupError("only vertical LINEs are modelled")
    return [(x0, y) for y in range(min(y0, y1), max(y0, y1) + 1)]


# ---------------------------------------------------------------------------------------------------- the machine side
def dictionary(m):
    """{NAME: code address} by walking the chain from LATEST (link, length/flags, name, code), as tools/floattest.py."""
    words = getattr(m, "_shape_words", None)
    if words is None:
        words = {}
        a, n = m.w16(m.S.get("LATEST", LATEST_DEFAULT)), 0
        while a and n < 4000:
            b = m.read(a, 36)
            ln = b[2] & 0x1F
            words.setdefault(b[3:3 + ln].decode("latin-1").upper(), a + 3 + ln)
            a = b[0] | b[1] << 8
            n += 1
        m._shape_words = words
    return words


def home_syms(m):
    """(sorted [(address, name)] of forth_boot.sym's labels from $5B00 up, the allowed-to-change mask over RAM_LO..RAM_HI)."""
    cached = getattr(m, "_shape_syms", None)
    if cached is not None:
        return cached
    syms = fh.load_syms(os.path.join(m.build, "forth_boot.sym"))        # READING: not graphics_exrom.sym: its labels are
    lst = sorted({(a, n) for n, a in syms.items() if a >= POOL_LO})     # EXROM addresses, which are dictionary RAM at rest
    addrs = sorted({a for a, _ in lst} | {RAM_HI + 1})
    mask = bytearray(RAM_HI - RAM_LO + 1)
    for n, a in syms.items():
        if RAM_LO <= a <= RAM_HI and (n.startswith(ALLOWED_PREFIX) or n in ALLOWED_NAMES):
            end = addrs[bisect.bisect_right(addrs, a)]
            for i in range(a, min(end, RAM_HI + 1)):
                mask[i - RAM_LO] = 1
    m._shape_syms = (lst, mask)
    return m._shape_syms


def nearest(lst, addr):
    i = bisect.bisect_right([a for a, _ in lst], addr) - 1
    return "%s+%d" % (lst[i][1], addr - lst[i][0]) if i >= 0 else "?"


def snapshot(m):
    """Everything a call may change that is compared: the bitmap, the attributes, RAM from $5B00 to $FDFF, GFX_MODE,
    CURRENT_ATTR; the second display file when GFX_MODE is nonzero."""
    mem = m.read(BITMAP, RAM_HI + 1 - BITMAP)
    s = dict(scr=mem[:SCREEN_END - BITMAP], ram=mem[RAM_LO - BITMAP:], mem=mem)
    s["mode"] = mem[m.S["GFX_MODE"] - BITMAP]
    s["cur"] = mem[m.S["CURRENT_ATTR"] - BITMAP]
    s["bmp"], s["attr"] = s["scr"][:0x1800], s["scr"][0x1800:]
    s["hi"] = mem[HI_ATTRS - BITMAP:HI_ATTRS - BITMAP + HI_SIZE] if s["mode"] else None
    return s


def call_word(m, code, args, maxi):
    """Call a word's code address with `args` as ints on the data stack (the last is the top); (reached STOP, T-states,
    registers)."""
    dtop = m.S.get("DSTACK_TOP", DSTACK_DEFAULT)
    ix0 = dtop - 2 * len(args)
    m.write(ix0, b"".join(struct.pack("<H", v & 0xFFFF) for v in reversed(args)))
    m.write(STOP_ADDR, b"\x18\xFE")
    m.write(RET_SLOT, struct.pack("<H", STOP_ADDR))
    m.setreg("IX", ix0)
    m.setreg("SP", RET_SLOT)
    m.setreg("PC", code)
    m.tstates_reset()
    pc = m.run_to([STOP_ADDR], maxi)
    t = m.tstates()
    return pc == STOP_ADDR, pc, t, m.regs()


def typ(c, text):
    """Console.type with a limit (RuntimeError: no key wait) instead of fharness's 60 million instructions."""
    for ch in text:
        c.key(ord(ch), TYPE_MAXI)
    c.key(13, TYPE_MAXI)


def pack_lines(cmds):
    """The commands joined into lines of at most LINE_MAX characters, never splitting a command."""
    out, cur = [], ""
    for c in cmds:
        if cur and len(cur) + 1 + len(c) > LINE_MAX:
            out.append(cur)
            cur = ""
        cur = (cur + " " + c) if cur else c
    if cur:
        out.append(cur)
    return out


def wipe_text(m, ymin):
    """Clear the bitmap rows the set-up lines' "OK" text printed on (rows 0 .. PRINT_ROW)."""
    row = m.read(m.S["PRINT_ROW"], 1)[0]
    ytop = 8 * (row + 1)
    if ytop > ymin:
        raise SetupError("the set-up text reached row %d (y < %d) but the drawing starts at y %d" % (row, ytop, ymin))
    for y in range(ytop):
        m.write(BITMAP + saddr(0, y), bytes(32))


def describe_diff(name, got, want, what):
    """First differences between two byte images laid out as the screen (`what`: bitmap / attr / hires)."""
    bad = [i for i in range(len(want)) if got[i] != want[i]]
    if not bad:
        return None
    i = bad[0]
    if what == "bitmap":
        # find the first differing pixel in raster order for the message
        pix = [(y, x) for y in range(192) for xb in range(32) if got[saddr(0, y) + xb] != want[saddr(0, y) + xb]
               for x in [xb * 8 + k for k in range(8)] if getpix(got, x, y) != getpix(want, x, y)]
        npx = len(pix)
        y, x = pix[0]
        return "%s: %d pixels differ; first at x %d y %d (got %d, model %d)" % (
            name, npx, x, y, getpix(got, x, y), getpix(want, x, y))
    if what == "attr":
        return "%s: %d cells differ; first at row %d col %d (got %02X, model %02X)" % (
            name, len(bad), i // 32, i % 32, got[i], want[i])
    return "%s: %d bytes differ; first at scanline %d col %d (got %02X, model %02X)" % (
        name, len(bad), i // 32, i % 32, got[i], want[i])


def check_ram(m, pre, post, nargs):
    """RAM outside the screen (see the header): a message, or None.  The `nargs` cells under DSTACK_TOP are the arguments the
    harness wrote itself (the words consume them but leave them there)."""
    dtop = m.S.get("DSTACK_TOP", DSTACK_DEFAULT)
    lst, mask = home_syms(m)
    bad = []
    for lo, hi in m.ram_diff(pre["ram"], post["ram"], RAM_LO):
        for a in range(lo, hi + 1):
            if mask[a - RAM_LO] or dtop - 2 * nargs <= a < dtop:
                continue
            if POOL_LO <= a <= POOL_HI:     # (in HIRES the second display file in it is compared with the model)
                continue
            bad.append(a)
    if not bad:
        return None
    ranges, start = [], bad[0]
    for a, b in zip(bad, bad[1:] + [None]):
        if b is None or b != a + 1:
            ranges.append((start, a))
            start = b
    return "RAM changed outside the allowed cells: %d bytes in %d ranges: %s" % (len(bad), len(ranges), "; ".join(
        "$%04X-$%04X (%s)" % (lo, hi, nearest(lst, lo)) for lo, hi in ranges[:6]) + (" ..." if len(ranges) > 6 else ""))


def run_case(m, cs):
    """One case: set-up, then each call checked against the model.  Returns the pool's result dict."""
    S = m.S
    words = dictionary(m)
    c = fh.Console(m)
    c.boot()
    for line in pack_lines(cs.get("cmds", [])):
        typ(c, line)
    if cs.get("draw"):
        # READING: a picture that is too big to type is written over the whole bitmap (the typed lines' "OK" text goes
        # with the old bitmap), after the typed set-up (CLS, INK ...), so the attributes are the typed ones.
        bmp = bytearray(0x1800)
        cs["draw"](bmp)
        m.write(BITMAP, bytes(bmp))
    else:
        wipe_text(m, cs.get("ymin", 32))
    calls = cs["calls"]
    pre = snapshot(m)
    if callable(calls):
        calls = calls(pre["bmp"])
    msgs, tsum, first, failed = [], 0, True, False
    for word, args in calls:
        code = words.get(word)
        if code is None:
            raise Missing(word)
        if word == "FILL" and first and cs.get("seed_bit") is not None:
            x, y = s16(args[0]), s16(args[1])
            if cs["seed_bit"] != getpix(pre["bmp"], x, y):
                raise SetupError("the seed (%d, %d) is %d, the case needs %d" % (x, y, getpix(pre["bmp"], x, y), cs["seed_bit"]))
            lo, hi = cs.get("region", (1, None))
            n = len(fill_region(pre["bmp"], x, y))
            if n < lo or (hi is not None and n > hi):
                raise SetupError("the region at the seed has %d pixels, the case needs %s-%s" % (n, lo, hi))
        first = False
        ok, pc, t, regs = call_word(m, code, args, BUDGET[word])
        label = "%s %s" % (" ".join(str(s16(a)) for a in args), word)
        if not ok:
            msgs.append("%s: did not return within %d instructions (PC=$%04X)" % (label, BUDGET[word], pc))
            failed = True
            break
        post = snapshot(m)
        tsum += t
        if word == "FILL":
            want = model_fill(pre["bmp"], pre["attr"], pre["hi"], args[0], args[1], pre["cur"], pre["mode"])
        elif word == "PLOT":
            want = model_plot_points(pre["bmp"], pre["attr"], pre["hi"], [(s16(args[0]), s16(args[1]))], pre["cur"],
                                     pre["mode"])
        elif word == "LINE":
            want = model_plot_points(pre["bmp"], pre["attr"], pre["hi"], line_points(*args), pre["cur"], pre["mode"])
        else:
            want = model_circle(pre["bmp"], pre["attr"], pre["hi"], args[0], args[1], args[2], pre["cur"], pre["mode"])
        bad = []
        d = describe_diff("bitmap", post["bmp"], want[0], "bitmap")
        d2 = describe_diff("attributes", post["attr"], want[1], "attr")
        d3 = describe_diff("hires attributes", post["hi"], want[2], "hires") if want[2] is not None else None
        bad += [x for x in (d, d2, d3) if x]
        ram = check_ram(m, pre, post, len(args))
        if ram:
            bad.append(ram)
        if regs["IX"] != S.get("DSTACK_TOP", DSTACK_DEFAULT):
            bad.append("IX = $%04X afterwards, not DSTACK_TOP (arguments not consumed)" % regs["IX"])
        if regs["SP"] != NORMAL_SP:
            bad.append("SP = $%04X afterwards, not $%04X" % (regs["SP"], NORMAL_SP))
        depth = post["mem"][S["BANK_EXROM_DEPTH"] - BITMAP]
        if depth:
            bad.append("BANK_EXROM_DEPTH = %d afterwards" % depth)
        if bad:
            msgs.append("%s: %s" % (label, "; ".join(bad)))
            failed = True
            break                                # (the state is no longer the model's: later calls would only repeat it)
        msgs.append("%s: %s, %d T" % (label, ("%d pixels" if word == "FILL" else "%d points") % want[3] if want[3] else "no change" if word != "CIRCLE" else "no point on screen", t))
        pre = post
    good = not failed
    return dict(ok=good, detail="; ".join(msgs), data=dict(name=cs["name"], tstates=tsum if good else None))


def run_repeat(m, cs):
    """The same case twice (a restore between): the T-states must be equal."""
    a = run_case(m, cs)
    m.restore()
    b = run_case(m, cs)
    ta, tb = a["data"]["tstates"], b["data"]["tstates"]
    if not (a["ok"] and b["ok"]):
        return dict(ok=False, detail="a run failed: %s | %s" % (a["detail"], b["detail"]))
    return dict(ok=ta == tb, detail="%s: %d T and %d T (%s)" % (cs["name"], ta, tb, "equal" if ta == tb else "DIFFERENT"))


FUNCS = {"case": run_case, "repeat": run_repeat}


def run_task(m, tk):
    try:
        return FUNCS[tk["func"]](m, tk["args"])
    except Missing as e:
        return dict(ok=False, detail="word %s is not in this build's dictionary" % e)
    except SetupError as e:
        return dict(ok=False, detail="SETUP: %s" % e)
    except RuntimeError as e:                    # the console did not get back to its key wait
        return dict(ok=False, detail="console stuck: %s" % e)


# ---------------------------------------------------------------------------------------------------- set-up pictures
def lines(*pts, closed=False):
    """LINE commands through the points (x, y); closed: back to the first."""
    p = list(pts) + ([pts[0]] if closed else [])
    return ["%d %d %d %d LINE" % (a[0], a[1], b[0], b[1]) for a, b in zip(p, p[1:])]


def box(x0, y0, x1, y1):
    return lines((x0, y0), (x1, y0), (x1, y1), (x0, y1), closed=True)


OCTAGON = ((90, 60), (130, 60), (150, 80), (150, 120), (130, 140), (90, 140), (70, 120), (70, 80))
# READING: typed drawings stay above y 160: the editor redraws the bottom four character rows (its edit line area) after
# every key, which erases anything typed-and-drawn there.  Pictures that need the whole screen are written with m.write.
LSHAPE = ((30, 50), (80, 50), (80, 110), (200, 110), (200, 155), (30, 155))
SPIRAL = ((20, 65), (20, 40), (230, 40), (230, 155), (20, 155), (20, 65), (200, 65), (200, 125), (50, 125), (50, 90),
          (170, 90), (170, 105))


def draw_disc(cx, cy, r):
    def f(bmp):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                    setpix(bmp, x, y)
    return f


def draw_noise(bmp, n=6000):
    # READING: 6000 random dots written straight into the bitmap (RNG seed 15), not typed: ~6000 typed PLOTs would take
    # an hour of key presses.  Dots land anywhere, a dot may repeat (about 5,500 distinct pixels).
    rng = random.Random(15)
    for _ in range(n):
        setpix(bmp, rng.randrange(256), rng.randrange(192))


def draw_noise_inverted(bmp):
    """A solid screen with 4,500 random holes (RNG seed 15): a recolour (seed pixel 1) whose seeds overflow the
    1,664-entry stack (checked: with FILL_SWEEP disabled this case fails; at 6,000 or 9,000 holes it happens not to)."""
    draw_noise(bmp, 4500)
    for i in range(len(bmp)):
        bmp[i] ^= 0xFF


def noise_seed_set(bmp):
    """A set pixel nearest the centre of the screen (the inverted noise screen's seed)."""
    best = min(((x - 128) ** 2 + (y - 96) ** 2, x, y) for y in range(86, 107) for x in range(118, 139) if getpix(bmp, x, y))
    return [("FILL", [best[1], best[2]])]


def noise_seed(bmp):
    """A fillable (blank) pixel nearest the centre of the screen."""
    best = min(((x - 128) ** 2 + (y - 96) ** 2, x, y) for y in range(86, 107) for x in range(118, 139) if not getpix(bmp, x, y))
    return [("FILL", [best[1], best[2]])]


def draw_pocket(bmp):
    for x in range(99, 104):
        setpix(bmp, x, 99)
        setpix(bmp, x, 101)
    setpix(bmp, 99, 100)
    setpix(bmp, 103, 100)


def draw_serpentine(bmp):
    # Walls in every odd column, open alternately at the bottom (x % 4 == 1: y 0-190) and the top (x % 4 == 3: y 1-191).
    for x in range(1, 256, 2):
        for y in (range(0, 191) if x % 4 == 1 else range(1, 192)):
            setpix(bmp, x, y)


# ---------------------------------------------------------------------------------------------------- the checks
class Check:
    def __init__(self, name, group, tasks):
        self.name, self.group, self.tasks = name, group, tasks


def task(func, args, weight=1):
    return dict(func=func, args=args, weight=weight)


def case(name, group, cmds=(), calls=(), draw=None, weight=1, **kw):
    cs = dict(name=name, cmds=list(cmds), calls=calls, draw=draw, **kw)
    return Check(name, group, [task("case", cs, weight)])


def fill(*xy):
    return ("FILL", list(xy))


def circle(*a):
    return ("CIRCLE", list(a))


def old_checks():
    L = []
    L.append(case("fill_box", "old", ["CLS"] + box(40, 30, 200, 150), [fill(120, 90)], seed_bit=0, region=(100, None), ymin=30))
    L.append(case("fill_circle_inside", "old", ["CLS"] + lines(*OCTAGON, closed=True), [fill(110, 100)], seed_bit=0,
                  region=(100, 20000)))
    L.append(case("fill_recolour", "old", ["CLS", "2 INK", "30 40 90 100 RECT", "5 INK"], [fill(50, 60)], seed_bit=1,
                  region=(3000, 4000), ymin=40))
    L.append(case("fill_L_shape", "old", ["CLS"] + lines(*LSHAPE, closed=True), [fill(50, 100)], seed_bit=0, region=(100, 20000)))
    L.append(case("fill_spiral", "old", ["CLS"] + lines(*SPIRAL), [fill(100, 52)], seed_bit=0, region=(100, 29000), ymin=40))
    L.append(case("fill_blank_screen", "old", ["CLS"], [fill(128, 96)], seed_bit=0, region=(49152, 49152), weight=4))
    L.append(case("fill_lone_pixel", "old", ["CLS", "150 120 PLOT"], [fill(150, 120)], seed_bit=1, region=(1, 1), ymin=40))
    L.append(case("fill_hires_noop", "old", ["CLS"] + box(40, 40, 200, 150) + ["HIRES"], [fill(120, 90)]))
    for r in (0, 1, 2, 5, 20, 90):
        L.append(case("circle_r%d" % r, "old", ["CLS"], [circle(128, 96, r)]))
    L.append(case("circle_clip_right_bottom", "old", ["CLS"], [circle(240, 180, 30)]))
    L.append(case("circle_ink_paper", "old", ["CLS", "3 INK", "6 PAPER"], [circle(100, 80, 25)]))
    L.append(case("circle_hires", "new", ["CLS", "3 INK", "HIRES"], [circle(128, 96, 40)]))   # the SCLD's 8x1 layout
    L.append(case("plot_offscreen", "new", ["CLS", "2 INK"], [("PLOT", [300, 50]), ("PLOT", [-1, 50]), ("PLOT", [50, 192]),
                                                             ("PLOT", [50, 255]), ("PLOT", [50, -3]), ("PLOT", [255, 191])]))
    L.append(case("line_below_screen", "new", ["CLS", "4 INK"], [("LINE", [60, 180, 60, 250]), ("LINE", [70, 255, 70, 200])]))
    L.append(case("plot_hires", "new", ["CLS", "5 INK", "HIRES"], [("PLOT", [10, 9]), ("PLOT", [200, 77])]))
    return L


def new_checks():
    L = []
    L.append(case("fill_noise_overflow", "new", ["CLS"], noise_seed, draw=draw_noise, weight=6))
    L.append(case("fill_noise_recolour_overflow", "new", ["CLS", "5 INK"], noise_seed_set, draw=draw_noise_inverted,
                  weight=6))
    L.append(case("fill_seed_offscreen", "new", ["CLS"] + box(40, 40, 200, 150),
                  [fill(-1, 50), fill(300, 50), fill(50, 192), fill(50, -5)], ymin=40, weight=2))
    L.append(case("circle_negative_centre", "new", ["CLS"], [circle(-10, 50, 30)]))
    # READING: "300 100 60 and 128 250 80" are two calls on one screen (the second sees the first's circle).
    L.append(case("circle_big_centre", "new", ["CLS"], [circle(300, 100, 60), circle(128, 250, 80)]))
    # READING: 128 96 300 puts no point on the screen (the screen's corner is 160 away), so the case adds a second call, a
    # circle centred below the screen whose top arc crosses it (128 400 330), to make the exactness check non-trivial.
    L.append(case("circle_big_radius", "new", ["CLS"], [circle(128, 96, 300), circle(128, 400, 330)]))
    # READING: 128 96 -5 alone would pass on the old build by accident (low byte 251: a circle with no point on the screen),
    # so the case adds 128 96 -250 (low byte 6: the old build draws a small circle there, the spec draws nothing).
    L.append(case("circle_negative_radius", "new", ["CLS"], [circle(128, 96, -5), circle(128, 96, -250)]))
    return L


def speed_checks():
    L = []
    L.append(case("fill_speed_box160x120", "speed", ["CLS"] + box(48, 36, 207, 155), [fill(128, 96)], seed_bit=0,
                  region=(18000, 19000), ymin=36, weight=6))
    L.append(case("fill_speed_full", "speed", ["CLS"], [fill(128, 96)], seed_bit=0, region=(49152, 49152), weight=8))
    L.append(case("fill_speed_disc_recolour", "speed", ["CLS", "5 INK"], [fill(128, 96)], draw=draw_disc(128, 96, 50),
                  seed_bit=1, region=(7000, 9000), weight=6))
    L.append(case("fill_speed_pocket", "speed", ["CLS"], [fill(101, 100)], draw=draw_pocket, seed_bit=0, region=(3, 3),
                  weight=3))
    for r in (5, 40, 90, 150):                               # r 150: mostly off-screen, still plots
        L.append(case("circle_speed_r%d" % r, "speed", ["CLS"], [circle(128, 96, r)]))
    L.append(case("fill_speed_serpentine", "speed", ["CLS"], [fill(0, 0)], draw=draw_serpentine, seed_bit=0,
                  region=(24704, 24704), weight=8))
    rep = case("fill_speed_box160x120", "speed", ["CLS"] + box(48, 36, 207, 155), [fill(128, 96)], seed_bit=0,
               region=(18000, 19000), ymin=36)
    L.append(Check("speed_repeat", "speed", [task("repeat", rep.tasks[0]["args"], 12)]))
    return L


def build_checks(group, only):
    L = []
    if group in ("old", "gated", "all"):
        L += old_checks()
    if group in ("new", "gated", "all"):
        L += new_checks()
    if group in ("speed", "all"):
        L += speed_checks()
    if only:
        L = [c for c in L if any(s.lower() in c.name.lower() or s.lower() == c.group for s in only)]
    names = [c.name for c in L]
    assert len(names) == len(set(names)), "duplicate check names: %s" % sorted({n for n in names if names.count(n) > 1})
    return L


# ---------------------------------------------------------------------------------------------------- the run
def cut(s, n):
    return s if len(s) <= n else s[:n - 3] + "..."


def print_speed(speed, old):
    if old is not None:
        print("speed, T-states per case (old = %s):" % old.get("_file", "--compare file"))
        print("  %-28s %14s %14s %8s" % ("case", "old T", "new T", "ratio"))
        for name, d in speed.items():
            o, n = old.get(name), d.get("tstates")
            print("  %-28s %14s %14s %8s" % (name, "%d" % o if o else "-", "%d" % n if n else "failed",
                                              "%.3f" % (n / o) if o and n else "-"))
    else:
        print("speed, T-states per case (recorded; gated only with --compare):")
        for name, d in speed.items():
            t = d.get("tstates")
            print("  %-28s %14s" % (name, "%d" % t if t is not None else "failed"))


def suite(build, only=(), json_out=None, verbose=False, group="all", compare=None):
    """The checks as one fharness.Suite (tools/run_tests.py; run_all runs it alone)."""
    checks = build_checks(group, only)
    if not checks:
        raise ValueError("shapetest: no check matches %r" % (only,))
    old = None
    if compare:
        data = json.load(open(compare))
        old = {k: v.get("tstates") for k, v in data.get("speed", {}).items()}
        old["_file"] = compare
    flat = [t for c in checks for t in c.tasks]
    return fh.Suite("shape", flat, run_task, lambda res, wall: report(checks, res, wall, build, json_out, verbose, group,
                                                                       compare, old))


def run_all(build, workers, port0, only, json_out, verbose, group, compare):
    return suite(build, only, json_out, verbose, group, compare).run_alone(build, workers, port0)


def report(checks, res, wall, build, json_out, verbose, group, compare, old):
    results = dict(enumerate(res))
    out, tally, speed = [], {}, {}
    pos = 0
    for c in checks:
        rs = []
        for _ in c.tasks:
            rs.append(results[pos])
            pos += 1
        ok = all(r["ok"] for r in rs)
        detail = rs[0]["detail"] if len(rs) == 1 else "; ".join(r["detail"] for r in rs)
        if c.group == "speed" and c.name != "speed_repeat":
            d = rs[0].get("data") or dict(name=c.name, tstates=None)
            speed[c.name] = d
            o = old.get(c.name) if old else None
            if ok and old is not None and o and d["tstates"] is not None and d["tstates"] > o:
                ok = False
                detail += "; slower than old: %d T against %d T (x%.3f)" % (d["tstates"], o, d["tstates"] / o)
        wall_c = sum(r["wall"] for r in rs)
        out.append(dict(check=c.name, group=c.group, ok=ok, detail=detail, wall=round(wall_c, 2)))
        tally.setdefault(c.group, [0, 0])
        tally[c.group][0] += ok
        tally[c.group][1] += 1
        print("%s %-5s %-26s %s  [%.1f s]" % ("PASS" if ok else "FAIL", c.group, c.name, detail if verbose else cut(detail, 230), wall_c),
              flush=True)
    if speed:
        print_speed(speed, old)
    total = sum(t[1] for t in tally.values())
    passed = sum(t[0] for t in tally.values())
    harness_error = all(r["detail"].startswith("TASK FAILED") for r in results.values()) or any(
        r["detail"].startswith(("worker on port", "never ran")) for r in results.values())
    print("shapetest: %d/%d checks pass (%s); wall %.1f s" % (
        passed, total, ", ".join("%s %d/%d" % (g, tally[g][0], tally[g][1]) for g in ("old", "new", "speed") if g in tally), wall))
    if json_out:
        os.makedirs(os.path.dirname(os.path.abspath(json_out)), exist_ok=True)
        json.dump(dict(build=build, group=group, compare=compare, passed=passed, total=total,
                       groups={g: dict(passed=t[0], total=t[1]) for g, t in tally.items()}, checks=out, speed=speed,
                       wall=round(wall, 2)), open(json_out, "w"), indent=1)
    return 2 if harness_error else (1 if total - passed else 0)


# ---------------------------------------------------------------------------------------------------- self-test
def selftest():
    bad = []

    def expect(what, got, want):
        if got != want:
            bad.append("%s: got %r, want %r" % (what, got, want))

    blank = bytearray(0x1800)
    attr = bytearray([0x44]) * 0x300
    # screen addressing: the spec's formula against the three third / row / scanline cases
    expect("saddr(0,0)", saddr(0, 0), 0)
    expect("saddr(255,191)", saddr(255, 191), 0x17FF)
    expect("saddr(8,8)", saddr(8, 8), 0x20 + 1)
    # circle point sets: r 0 is the centre, r 1 the four neighbours, r 2 twelve distinct points
    expect("r0", set(circle_points(5, 5, 0)), {(5, 5)})
    expect("r1", set(circle_points(5, 5, 1)), {(4, 5), (6, 5), (5, 4), (5, 6)})
    expect("r2 points", len(set(circle_points(0, 0, 2))), 12)
    expect("r<0", circle_points(5, 5, -1), [])
    b, a, h, n = model_circle(blank, attr, None, 300, 100, 60, 0x47, 0)
    expect("circle off-screen centre sets pixels", n > 0, True)
    b, a, h, n = model_circle(blank, attr, None, 128, 96, 300, 0x47, 0)
    expect("circle r 300 at the centre: nothing on screen", n, 0)
    hi = bytearray([0x44]) * HI_SIZE
    b, a, h, n = model_circle(blank, attr, hi, 128, 96, 0, 0x47, 1)
    expect("hires attr", (a == attr, h[saddr(128, 96)]), (True, 0x47))
    # fill: a blank screen is one region; a box splits it; a serpentine is 24,704 pixels from (0, 0)
    expect("blank region", len(fill_region(blank, 0, 0)), 49152)
    bx = bytearray(0x1800)
    for x in range(40, 201):
        setpix(bx, x, 40)
        setpix(bx, x, 150)
    for y in range(40, 151):
        setpix(bx, 40, y)
        setpix(bx, 200, y)
    expect("box inside", len(fill_region(bx, 100, 100)), 159 * 109)
    expect("box seed on the wall", len(fill_region(bx, 40, 40)), 2 * 161 + 2 * 109)
    sp = bytearray(0x1800)
    draw_serpentine(sp)
    expect("serpentine", len(fill_region(sp, 0, 0)), 24704)
    b, a, h, n = model_fill(bx, attr, None, 100, 100, 0x47, 0)
    expect("fill sets bits and cells", (n, getpix(b, 100, 100), a[attr_off(100, 100)], a[0]), (159 * 109, 1, 0x47, 0x44))
    expect("fill off-screen seed", [model_fill(bx, attr, None, x, y, 0x47, 0)[3] for x, y in ((-1, 50), (300, 50), (50, 192), (50, -5))], [0] * 4)
    expect("fill in hires", model_fill(bx, attr, hi, 100, 100, 0x47, 1)[3], 0)
    # the case lists
    checks = build_checks("all", [])
    names = {c.group: 0 for c in checks}
    for c in checks:
        names[c.group] += 1
    print("checks: %s" % ", ".join("%s %d" % kv for kv in sorted(names.items())))
    for b_ in bad:
        print("FAIL", b_)
    print("shapetest selftest: %d failure(s)" % len(bad))
    return 0 if not bad else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"), help="directory with forth_boot_rom0.bin (DIR or DIR/build)")
    ap.add_argument("--group", choices=("old", "new", "speed", "gated", "all"), default="all", help="old: kept behaviour; new: the spec; speed: T-states; gated: old and new; all (default)")
    ap.add_argument("--workers", type=int, default=None, help="emulators in parallel (default: fharness.default_workers())")
    ap.add_argument("--port", type=int, default=PORT0, help="first ZRCP port (default %d; 10860-10879)" % PORT0)
    ap.add_argument("--json", default=os.path.join(ROOT, "build", "shapetest.json"), help="write the results here (default build/shapetest.json)")
    ap.add_argument("--compare", default=None, help="JSON of an earlier run: every speed case must take no more T-states")
    ap.add_argument("--selftest", action="store_true", help="no emulator: the models on hand-checked pictures")
    ap.add_argument("-v", "--verbose", action="store_true", help="print the full detail of every check")
    ap.add_argument("only", nargs="*", help="run the checks whose name contains one of these (or whose group is this)")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    try:
        build = fh.resolve_build(a.build)
        return run_all(build, a.workers, a.port, a.only, a.json, a.verbose, a.group, a.compare)
    except (FileNotFoundError, ValueError, RuntimeError, OSError) as e:
        print("shapetest: harness error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
