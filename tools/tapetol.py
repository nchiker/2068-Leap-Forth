#!/usr/bin/env python3
"""The Forth tape receiver's tolerance envelope (storage rebuild, step S, T14; docs/V2/STORAGE_SPEC.md section 8).

A port of 2068-Leap-C's tools/tapetol.py (same 71 cases, same synthesiser, same comparison) from Fuse to ZEsarUX.
A text tape (a header block, type 0, name TOL, and a data block with a short program) is synthesised with a
distortion, written as a raw `.rwa` file (8 bits a sample, one sample per scan line = 224 T of ZEsarUX's TS2068
clock, $C8 high / $38 low / $80 idle) behind 30 s of idle samples, and inserted with ZRCP `realtape-open` (which
resets the machine and plays at once; the idle lead is the time in which the harness types `LOAD-TEXT TOL`).
A case is ACCEPTED when the program's effect is observed: the screen shows the program's output (12345).
Anything else is REFUSED.

Why not Leap-C's TZX direct recording ($15)?  Measured on ZEsarUX 13.0: `realtape-open` converts a TZX to a
temporary .rwa, and for block $15 it writes one RWA sample per TZX sample and ignores the sample period, so a
4 T sample plays back 54 times too slow (the receiver never sees a pilot).  So the pulse widths here are quantised
to whole scan lines: every edge lands on a multiple of 224 T, up to one sample (224 T, 26% of a 0-bit half-pulse,
13% of a 1-bit half-pulse, 10% of a pilot pulse) from where Leap-C puts it.  The edge times are the exact running
sum (no drift), so the widths average right, but a scale of +-5% is below the noise: read the table as a coarse
envelope, not as Fuse's 4 T figures.

The distortions (stock widths and pilots otherwise):
  scale-all/pilot/sync/bits S   those pulse widths times 1 + S (S = -25%..+25% in 5% steps)
  jitter J                      every pulse's width times a uniform 1 +- J (seeded)
  scale+jitter                  combinations
  bit-skew K                    each bit's first half-pulse times 1 + K, the second times 1 - K
  pilot-short N                 N pilot pulses before each block instead of 8,063 / 3,223
  pilot-missing / -extra        one edge missing in the middle of each pilot (a 4,336 T pulse) / one more
                                pilot pulse (the sync and data inverted)
  pilot-missing-end             one edge missing 4 pulses before the sync
  inverted                      the whole signal inverted
  pilot-dropout D               D ms without an edge in the middle of each pilot
  data-dropout D                D ms without an edge in the data block (a LOAD that must fail)

Usage: python3 -I tools/tapetol.py [--emu zesarux|fuse] --build DIR [--build DIR2 ...] [--case NAME ...] [--jobs N] [--out FILE]
  With two or more --build directories (the old images first, then the new), the report compares them: every case
  the first accepts must be accepted by each later one; otherwise NARROWER lines are printed and the exit status
  is 1.  A DIR holds forth_boot_rom0.bin, graphics_exrom.bin and forth_boot.sym (DIR/build is tried too).
  Workers run on ZRCP ports 10980 and up (one emulator per worker, --port0 to move them, 10980-10999 only).

--emu fuse (default zesarux): the same 71 cases on Fuse 1.9.1 headless, as Leap-C runs them (tools/fusedrive.py,
tools/fuse/fuseshim.c).  The tape is a TZX direct recording (block $15) at 4 T a sample, so every pulse width is
exact to 4 T (against ZEsarUX's 224 T), Fuse's CPU clock is 3,528,000 Hz, tape traps are off, auto-load is off and
`--no-accelerate-loader` is set, so the ROM's own receiver measures every pulse.  Fuse starts the tape by itself when it
sees the ROM listen to the EAR bit (loader detection).  Each case runs in a fresh Fuse (a refused load can leave
the dictionary half written, and a leftover 12345 on the screen would read as an accept); the command is typed
through the emulated keyboard, paced by the machine (IO_READ_KEY / IO_LATCH_AND_CLEAR), and the case ends when the
ROM is back in its key wait with an empty edit line.  Workers are plain processes (no ZRCP ports).

EMULATOR LIMITS: there is no hardware here.  The verdicts are those of ZEsarUX (224 T per sample) or Fuse (4 T per
sample) running the ROM's own receiver; they say nothing about a real cassette recorder, a real EAR comparator or a
real clock.
"""
import argparse
import json
import multiprocessing as mp
import os
import random
import shutil
import struct
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
HOME = os.path.expanduser("~")
ZDIR = os.environ.get("TS2068_DEBUG_ZESARUX_DIR", os.path.join(HOME, "Applications", "ZEsarUX-13.0"))

# The stock signal (docs/V2/STORAGE_SPEC.md section 3; the standard ROM figures).
CPU_HZ = 3_494_400                  # ZEsarUX's TS2068 CPU clock (Leap-C: 3,528,000; deviation noted in the docstring)
SAMPLE_T = 224                      # T-states per .rwa sample (one scan line; 15,600 samples a second)
PILOT_T, SYNC1_T, SYNC2_T, ZERO_T, ONE_T = 2168, 667, 735, 855, 1710        # the stock ROM's half-pulses
HEADER_PILOT, DATA_PILOT = 8063, 3223                                        # pilot half-pulses

PROG = ": T1 12345 ; T1 ."          # the text on the tape; its output is the verdict
EXPECT = "12345"
NAME = "TOL"
LOAD_CMD = "LOAD-TEXT TOL"
SAMPLE = 4                          # the narrowest pulse a case may ask for, in T-states (as in Leap-C)
LEAD_S = 30                         # idle samples that open every tape: the typing time
PORT_LO, PORT_HI = 10980, 10999
WIDTHS = dict(pilot=PILOT_T, sync1=SYNC1_T, sync2=SYNC2_T, zero=ZERO_T, one=ONE_T)
FUSE_CPU_HZ = 3_528_000             # Fuse's TS2068 clock (Leap-C's figure too)
FUSE_SAMPLE = 4                     # T-states a TZX direct-recording sample (block $15)
EMU = "zesarux"                     # set by main() before the workers start (they inherit it)


# ---------------------------------------------------------------------------------------------------- the tape
def block(flag, payload):
    """One tape block, flag byte first, XOR checksum last (no TAP length word)."""
    c = flag
    for b in payload:
        c ^= b
    return bytes([flag]) + bytes(payload) + bytes([c])


def text_blocks(name, text):
    """The header block (type 0, the layout of STORAGE_SPEC section 4 / tools/tape_gen_forth.py) and the data block."""
    data = text.encode("ascii")
    hdr = bytearray([0]) + name.encode("ascii").ljust(10)[:10]
    hdr += struct.pack("<HHH", len(data), 0x8000, len(data))
    assert len(hdr) == 17
    return [block(0x00, hdr), block(0xFF, data)]


def synth(blocks, scale=None, jitter=0.0, skew=0.0, pilot=None, missing=None, extra=False, invert=False,
          pilot_dropout=0.0, data_dropout=0.0, seed=1):
    """The blocks' EAR signal as [(level, T)] runs, distorted (the module docstring)."""
    scale = scale or {}
    rnd = random.Random(seed)
    runs, level = [], 1 if invert else 0

    def w(kind, f=1.0):
        t = WIDTHS[kind] * (1 + scale.get(kind if kind in ("pilot",) else
                                          "sync" if kind.startswith("sync") else "bits", 0.0)) * f
        if jitter:
            t *= 1 + rnd.uniform(-jitter, jitter)
        return max(SAMPLE, int(round(t)))

    def pulse(t):
        nonlocal level
        runs.append((level, t))
        level ^= 1

    def flat(t):
        runs.append((level, t))

    flat(CPU_HZ)                                            # 1 s of silence first
    for data in blocks:
        n = (HEADER_PILOT if data[0] < 0x80 else DATA_PILOT) if pilot is None else pilot
        n += 1 if extra else 0
        for i in range(n):
            if missing == "mid" and i == n // 2:
                runs[-1] = (runs[-1][0], runs[-1][1] + w("pilot"))        # no edge: two widths at one level
                continue
            if missing == "end" and i == n - 4:
                runs[-1] = (runs[-1][0], runs[-1][1] + w("pilot"))
                continue
            if pilot_dropout and i == n // 2:
                flat(int(pilot_dropout * CPU_HZ / 1000))
            pulse(w("pilot"))
        pulse(w("sync1"))
        pulse(w("sync2"))
        bits = [v >> k & 1 for v in data for k in range(7, -1, -1)]
        for j, b in enumerate(bits):
            if data_dropout and data[0] >= 0x80 and j == len(bits) // 2:
                flat(int(data_dropout * CPU_HZ / 1000))
            kind = "one" if b else "zero"
            pulse(w(kind, 1 + skew))
            pulse(w(kind, 1 - skew))
        pulse(w("zero"))
        flat(CPU_HZ)                                        # 1 s between the blocks and after the last
    return runs


def rwa(runs, lead_s=LEAD_S):
    """The raw tape file: lead_s seconds of idle samples ($80), then `runs` point-sampled once per SAMPLE_T
    (level 1 -> $C8, level 0 -> $38; an edge lands on the sample that contains its time), then 1 s of idle.
    Returns (bytes, total T-states of the pulse train)."""
    lead = lead_s * CPU_HZ // SAMPLE_T
    out = bytearray(b"\x80" * lead)
    t = 0
    for level, dt in runs:
        t += dt
        n = lead + t // SAMPLE_T - len(out)
        if n > 0:
            out.extend(bytes([0xC8 if level else 0x38]) * n)
    out.extend(b"\x80" * (CPU_HZ // SAMPLE_T))
    return bytes(out), t


def tzx_direct(runs, sample=FUSE_SAMPLE):
    """A TZX file of one direct-recording block ($15), `sample` T-states a sample, the levels of `runs`
    (Leap-C's tools/tapetol.py writer)."""
    parts, t = [], 0
    for level, dt in runs:
        t1 = t + dt
        parts.append("01"[level] * (t1 // sample - t // sample))
        t = t1
    bits = "".join(parts)
    used = len(bits) % 8 or 8
    bits += "0" * (-len(bits) % 8)
    data = int("1" + bits, 2).to_bytes(len(bits) // 8 + 1, "big")[1:]
    return (b"ZXTape!\x1a" + bytes([1, 20]) + bytes([0x15]) + struct.pack("<HHB", sample, 0, used) +
            struct.pack("<I", len(data))[:3] + bytes(data))


def cases():
    out = []
    steps = [s / 100 for s in range(-25, 26, 5)]
    for part in ("all", "pilot", "sync", "bits"):
        for s in steps:
            if part != "all" and s == 0:
                continue
            sc = dict(pilot=s, sync=s, bits=s) if part == "all" else {part: s}
            out.append(("scale-%s %+d%%" % (part, round(s * 100)), dict(scale=sc)))
    for j in (0.05, 0.10, 0.15, 0.20, 0.25, 0.30):
        out.append(("jitter %d%%" % round(j * 100), dict(jitter=j)))
    for s in (-0.20, -0.10, 0.10, 0.20):
        out.append(("scale-all %+d%% jitter 10%%" % round(s * 100),
                    dict(scale=dict(pilot=s, sync=s, bits=s), jitter=0.10)))
    for k in (0.10, 0.20, 0.30):
        out.append(("bit-skew %d%%" % round(k * 100), dict(skew=k)))
    for n in (2000, 1500, 1000, 800, 600, 400):
        out.append(("pilot-short %d" % n, dict(pilot=n)))
    out.append(("pilot-missing", dict(missing="mid")))
    out.append(("pilot-missing-end", dict(missing="end")))
    out.append(("pilot-extra", dict(extra=True)))
    out.append(("inverted", dict(invert=True)))
    for d in (2, 10, 50, 200):
        out.append(("pilot-dropout %d ms" % d, dict(pilot_dropout=d)))
    for d in (1, 5, 20):
        out.append(("data-dropout %d ms" % d, dict(data_dropout=d)))
    return out


# ---------------------------------------------------------------------------------------------------- the emulator
class HarnessError(Exception):
    pass


def resolve_build(path):
    """The directory that holds forth_boot_rom0.bin (DIR or DIR/build)."""
    for d in (path, os.path.join(path, "build")):
        if os.path.isfile(os.path.join(d, "forth_boot_rom0.bin")):
            return os.path.abspath(d)
    raise SystemExit("tapetol: no forth_boot_rom0.bin in %s" % path)


class Syms(dict):
    def __init__(self, path):
        super().__init__()
        for line in open(path):
            if ": EQU" in line:
                n, _, v = line.partition(": EQU")
                self[n.strip()] = int(v.strip(), 0)


def import_debug():
    try:
        import ts2068_debug  # noqa: F401
    except ImportError:
        sys.path.insert(0, os.environ.get("TS2068_DEBUG_DIR", os.path.join(HOME, "ts2068-debug")))
    import ts2068_debug.process as proc
    from ts2068_debug.controller import Ts2068Debug
    return proc, Ts2068Debug


class Machine:
    """ZEsarUX through ts2068-debug on one ZRCP port, with its own state dir; always stop() it."""

    def __init__(self, build, port, tmp):
        self.proc, Dbg = import_debug()
        self.build, self.port = build, port
        self.state = tempfile.mkdtemp(prefix="state.%d." % port, dir=tmp)
        os.environ["TS2068_DEBUG_STATE_DIR"] = self.state
        self.rom = open(os.path.join(build, "forth_boot_rom0.bin"), "rb").read()
        img = os.path.join(self.state, "image.bin")
        with open(img, "wb") as f:
            f.write(self.rom + open(os.path.join(build, "graphics_exrom.bin"), "rb").read())
        self.S = Syms(os.path.join(build, "forth_boot.sym"))
        self.idle = (self.S["IO_READ_KEY.wait_hit"], self.S["IO_READ_KEY.wait_hit"] + 5)
        self.dbg = Dbg(ZDIR, port=port, romfile=img)
        self.pid = None
        self.dbg.start()
        self.pid = self.dbg._proc.pid
        self.z = self.dbg._zrcp
        ft = self.S["FONT_TABLE"]
        # FONT_TABLE: printable ASCII in code order; before step Words and keys, space, 0-9, A-Z first
        chars = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ" if "PUNCT_CHAR_TABLE" in self.S else \
            "".join(map(chr, range(32, 127)))
        self.glyph = {bytes(self.rom[ft + i * 8:ft + i * 8 + 8]): c for i, c in enumerate(chars)}

    def stop(self):
        try:
            self.dbg.stop()
        except Exception:
            pass
        if self.pid:
            self.proc.terminate_emulator(self.pid, self.port, grace_s=3.0)
        shutil.rmtree(self.state, ignore_errors=True)

    def rd(self, a, n):
        return self.dbg.read_memory(a, n)

    def is_idle(self):
        v = self.dbg.get_registers().values
        pc = v["PC"]
        if pc == 0x38:                                  # the interrupt entered from the wait loop
            pc = int.from_bytes(self.rd(v["SP"], 2), "little")
        return self.idle[0] <= pc < self.idle[1] and self.rd(self.S["EDIT_LEN"], 1)[0] == 0

    def wait_idle(self, budget=40_000_000):
        """Run in slices until the prompt is idle; leaves the machine paused."""
        self.dbg.pause()
        used, chunk = 0, 20_000
        while used < budget:
            if self.is_idle():
                return True
            self.dbg.run(max_instructions=chunk)
            used += chunk
            chunk = min(chunk * 2, 500_000)
        return False

    def edit(self):
        n = self.rd(self.S["EDIT_LEN"], 1)[0]
        return self.rd(self.S["EDIT_BUF"], n).decode("latin-1")

    def screen(self):
        scr = self.rd(0x4000, 0x1800)
        rows = []
        for r in range(24):
            cells = [bytes(scr[((r >> 3) << 11) + (ln << 8) + ((r & 7) << 5) + c] for ln in range(8)) for c in range(32)]
            rows.append("".join(self.glyph.get(x, "~") if any(x) else " " for x in cells).rstrip())
        return [r for r in rows if r.strip()]

    def tstates(self):
        r = self.z.command("get-tstates-partial").strip()
        return int(r) if r.isdigit() else 1 << 62         # ('OVERFLOW': the counter's limit is a long way past any tape)


def run_case(m, path, total_t, timeout_wall=900.0):
    """Insert `path`, type the load command in the lead, wait for the verdict.  Returns (accepted, note)."""
    m.dbg.pause()
    m.z.command("reset-tstates-partial")
    r = m.z.command("realtape-open " + path)
    if "rror" in r:
        raise HarnessError("realtape-open: %r" % r)
    m.z.command("reset-tstates-partial")                # (the insert reset the machine; count from there)
    if not m.wait_idle():
        raise HarnessError("no idle prompt after the insert")
    m.dbg.resume()
    m.z.command("send-keys-string 80 " + LOAD_CMD, timeout=15 + 0.2 * len(LOAD_CMD))
    time.sleep(0.08 * len(LOAD_CMD) + 0.4)
    m.dbg.pause()
    if m.edit() != LOAD_CMD:
        raise HarnessError("typing error: edit buffer %r" % m.edit())
    t_typed = m.tstates()
    if t_typed > CPU_HZ * LEAD_S * 0.9:
        raise HarnessError("typing overran the lead: %d T" % t_typed)
    m.dbg.resume()
    m.dbg.press_key("ENTER")
    time.sleep(0.4)
    m.dbg.pause()
    t_enter = m.tstates()
    deadline = CPU_HZ * LEAD_S + total_t + 2 * CPU_HZ       # the tape's end, and 2 s of margin
    wall0 = time.time()
    while True:
        m.dbg.resume()
        time.sleep(0.25)
        m.dbg.pause()
        now = m.tstates()
        idle = m.is_idle()
        if idle and now > t_enter + CPU_HZ // 2:
            scr = m.screen()
            return EXPECT in " ".join(scr), "idle at +%.1f s" % ((now - t_enter) / CPU_HZ)
        if now > deadline:
            scr = m.screen()
            return EXPECT in " ".join(scr), "tape ended"
        if time.time() - wall0 > timeout_wall:
            raise HarnessError("wall timeout")


def fuse_worker(build, k, todo, q, tmp, keep):
    """Fuse: one fresh Fuse a case (module docstring), the tape a TZX $15, the command typed on its keyboard."""
    import fusedrive
    blocks = text_blocks(NAME, PROG)
    wdir = tempfile.mkdtemp(prefix="case.%d." % k, dir=tmp)
    try:
        for name, kw in todo:
            path = os.path.join(wdir, "case.tzx")
            with open(path, "wb") as f:
                f.write(tzx_direct(synth(blocks, **kw)))
            for attempt in (1, 2, 3):           # (a harness failure, e.g. a lost key handshake: a new Fuse, again)
                f = None
                try:
                    f = fusedrive.Fuse(build, os.path.join(wdir, "fuse"), extra=["--no-accelerate-loader"]).start()
                    r = f.cmd("tape_open %s" % path)
                    if r != "0":
                        raise HarnessError("tape_open: %s" % r)
                    f.type(LOAD_CMD, timeout=600)
                    if not f.idle():
                        raise HarnessError("the prompt did not come back")
                    rows = [r for r in f.rows() if r.strip()]
                    q.put((name, EXPECT in " ".join(rows), "last row %r" % (rows[-1] if rows else "")))
                    break
                except Exception as e:
                    if attempt == 3:
                        q.put((None, False, "%r: %r" % (name, e)))
                finally:
                    if f:
                        f.stop()
    finally:
        shutil.rmtree(wdir, ignore_errors=True)


def worker(build, port, todo, q, tmp, keep):
    blocks = text_blocks(NAME, PROG)
    wdir = tempfile.mkdtemp(prefix="case.%d." % port, dir=tmp)
    m = None
    try:
        for name, kw in todo:
            data, total_t = rwa(synth(blocks, **kw))
            path = os.path.join(wdir, "case.rwa")
            with open(path, "wb") as f:
                f.write(data)
            for attempt in (1, 2, 3):           # (a harness failure, e.g. a lost key: a new emulator, again)
                try:
                    if m is None:
                        m = Machine(build, port, tmp)
                        if not m.wait_idle():
                            raise HarnessError("boot never reached the idle prompt")
                    ok, note = run_case(m, path, total_t)
                    q.put((name, ok, note))
                    break
                except Exception as e:
                    if m:
                        m.stop()
                    m = None
                    if attempt == 3:
                        q.put((None, False, "%r: %r" % (name, e)))
    finally:
        if m:
            m.stop()
        shutil.rmtree(wdir, ignore_errors=True)


def run(build, jobs, port0, only, tmp):
    todo = [c for c in cases() if not only or c[0] in only]
    q, procs = mp.Queue(), []
    for k in range(min(jobs, len(todo))):
        p = mp.Process(target=fuse_worker if EMU == "fuse" else worker,
                       args=(build, port0 + k, todo[k::jobs], q, tmp, False), daemon=True)
        p.start()
        procs.append(p)
    res = {}
    while any(p.is_alive() for p in procs) or not q.empty():
        try:
            name, ok, msg = q.get(timeout=1)
        except Exception:
            continue
        if name is None:
            print("tapetol: worker failed: %s" % msg, file=sys.stderr)
            continue
        res[name] = dict(ok=ok, msg=msg)
        print("tapetol: %-28s %s (%s)" % (name, "accept" if ok else "refuse", msg), file=sys.stderr, flush=True)
    for p in procs:
        p.join()
    return [(n, res.get(n)) for n, _ in todo]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", action="append", help="an image directory (default: build)")
    ap.add_argument("--case", action="append", help="run only this case (exact name; repeatable)")
    ap.add_argument("--emu", choices=("zesarux", "fuse"), default="zesarux", help="the emulator (default zesarux)")
    ap.add_argument("--jobs", type=int, default=None, help="parallel emulators (default 4; with ZEsarUX one ZRCP port each)")
    ap.add_argument("--port0", type=int, default=PORT_LO, help="first ZRCP port (10980-10999)")
    ap.add_argument("--out", help="write the report to this file as well as stdout")
    a = ap.parse_args()
    global EMU, CPU_HZ
    EMU = a.emu
    if a.jobs is None:
        a.jobs = 6 if EMU == "fuse" else 4
    if EMU == "fuse":
        CPU_HZ = FUSE_CPU_HZ                # (synth's silences and dropouts, in T-states of Fuse's clock)
        sys.path.insert(0, HERE)
        import fusedrive
        fusedrive.build_shim()              # (once, before the workers start)
    if a.jobs < 1 or (EMU == "zesarux" and (a.port0 < PORT_LO or a.port0 + a.jobs - 1 > PORT_HI)):
        raise SystemExit("tapetol: ports %d..%d must lie within %d-%d" % (a.port0, a.port0 + a.jobs - 1, PORT_LO, PORT_HI))
    known = [n for n, _ in cases()]
    for n in a.case or []:
        if n not in known:
            raise SystemExit("tapetol: unknown case %r" % n)
    builds = [resolve_build(b) for b in (a.build or [os.path.join(ROOT, "build")])]
    tmp = tempfile.mkdtemp(prefix="tapetol.")
    table, t0 = {}, time.time()
    lines = []
    try:
        for b in builds:
            table[b] = run(b, a.jobs, a.port0, a.case, tmp)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    names = [n for n, _ in table[builds[0]]]
    tag = lambda b: os.path.basename(os.path.normpath(os.path.dirname(b) if os.path.basename(b) == "build" else b))
    lines.append("%-28s %s" % ("case", "  ".join("%-14s" % tag(b) for b in builds)))
    narrower, missing = [], []
    for i, n in enumerate(names):
        cells = []
        for b in builds:
            r = table[b][i][1]
            cells.append("-- not run --" if r is None else ("accept" if r["ok"] else "refuse (%s)" % r["msg"][:20]))
            if r is None:
                missing.append((b, n))
        lines.append("%-28s %s" % (n, "  ".join("%-14s" % c for c in cells)))
        first = table[builds[0]][i][1]
        for b in builds[1:]:
            r = table[b][i][1]
            if first and first["ok"] and not (r and r["ok"]):
                narrower.append((b, n))
    for b in builds:
        acc = sum(1 for _, r in table[b] if r and r["ok"])
        lines.append("tapetol: %s accepts %d of %d" % (b, acc, len(names)))
    for b, n in narrower:
        lines.append("tapetol: NARROWER: %s refuses %r, which %s accepts" % (b, n, builds[0]))
    for b, n in missing:
        lines.append("tapetol: NOT RUN: %s %r" % (b, n))
    if EMU == "fuse":
        import fusedrive
        lines.append("tapetol: emulator Fuse %s, TZX $15 at %d T a sample, %d Hz, traps off, auto-load off, no loader acceleration"
                     % (fusedrive.fuse_version(), FUSE_SAMPLE, FUSE_CPU_HZ))
    lines.append("tapetol: %d jobs, %.0f s wall" % (a.jobs, time.time() - t0))
    text = "\n".join(lines) + "\n"
    sys.stdout.write(text)
    if a.out:
        with open(a.out, "w") as f:
            f.write(text)
    return 1 if narrower or missing else 0


if __name__ == "__main__":
    sys.exit(main())
