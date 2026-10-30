#!/usr/bin/env python3
"""tapetest.py - the tape storage oracle (docs/V2/STORAGE_SPEC.md section 8, audit step S).

Runs the case table of spec section 8 (cases 1-14 and 11a) and case 15 (a SAVE-LIB over 512 bytes, loaded by a wildcard
LOAD-LIB) against a ROM build on
ZEsarUX (through ts2068-debug / ZRCP), judging every case against the NEW contract of the spec.  It is written before
the code: on the old build it is expected to FAIL several cases, and the failures are the defects of section 1.

SAVE-TEXT / VERIFY-TEXT contract (docs/V2/EDITOR_SPEC.md section 3, "The command line is not source"): `SAVE-TEXT name` saves
the line store, STORE_START .. the cell STORE_END, and `VERIFY-TEXT name` compares a tape with it (a different length is
refused as a different byte is); the console appends every committed line (text + CR) before running it and STORE_TRIM,
called first by both words, removes the last line when it is the console's current one, so the command line is not
saved.  The cases therefore build the store the natural way, by typing lines (setup lines; the same for fusesave.py),
and the saved bytes are those lines, each + CR, and never the SAVE-TEXT / VERIFY-TEXT line.  Against a build whose
SAVE-TEXT still takes `addr len` (before the 2026-10-29 change) cases 3, N4, 12 and 14 are expected to FAIL.

Step E adds case N4 (docs/V2/EDITOR_SPEC.md section 8, "text-tape-roundtrip"; ids: `--case N4`, run right after case 3):
a store of nine CR-ended lines is put into memory at LOADTEXT_BUF with the store's end cell set (STORE_END, or
WORKSPACE_END on the old build), `SAVE-TEXT N4TXT` writes it from there (the word takes the store, not `addr len`: the
console appends the command line after the poked text and STORE_TRIM removes it again), the capture is decoded
(header and payload must be the store bytes, CRs included), played into a fresh machine, `LOAD-TEXT N4TXT`: the store must
be byte-identical, no error, and the program must have run.  The old build interprets CR as part of a word and restarts
on an unknown word inside LOAD-TEXT's text, so the text (N4_TEXT, whose comment says how) has no unknown token for it: it
prints 42 there (first, space-separated line) and, on a build with STORE_END (CR is whitespace), 21 as well, from the
CR-separated lines.  The case passes on the old build; on a new build it also demands the second effect.

RUN   python3 -I tools/tapetest.py --build DIR [--case N ...] [--selftest] [--out FILE] [--jobs K] [--port P]
      DIR holds forth_boot_rom0.bin + graphics_exrom.bin (booted as one 24K --romfile) and forth_boot.sym.
      One line per case:  `case N <name>: PASS|FAIL <short reason>`,  then  `TAPETEST: PASS a FAIL b`.
      Exit 0 = no FAIL, 1 = any FAIL, 2 = harness error.  Ports: P .. P+jobs-1 (default 10960..10963, ZRCP 10960-10979
      only).  Every emulator has a private TS2068_DEBUG_STATE_DIR and is terminated at the end, also on exceptions.
      Cases run in worker processes (one `--case` child each), --jobs of them at a time.

HOW A CASE RUNS (probe findings, spec section 8)
  * `realtape-open FILE` resets the machine (dictionary wiped) and the tape plays at once.  Every tape therefore starts
    with a TZX Pause block (lead), long enough for the setup lines and the command to be typed (40 ms a key; ~0.4 s of
    emulated time a key).  The harness types, reads the edit line back and compares it (a dropped key retries the
    case), and presses ENTER about 3 s before the lead ends, so the receiver is searching when the first pilot starts.
  * Done = PC parked in IO_READ_KEY.wait_hit and EDIT_LEN = 0 (the prompt).  While SPACE is held the editor types
    spaces, so the SPACE cases use PC only.
  * Cases are independent (a fresh emulator each; tape re-insertion resets the machine anyway).
  * SPACE (cases 11, 12): ZEsarUX releases a held key when the emulator is paused or resumed (measured: a SPACE sent
    while running aborted only the first byte before the next poll), so the SPACE cases keep the emulator in step mode
    (`run N` chunks) while SPACE is down and measure emulated time from the partial T-state counter.  The SPACE cases
    work from the prompt back: PC in the idle loop.
  * SAVE capture: ZEsarUX's stdout goes to a pty (line buffered); through a plain file the last 4 KB of the capture
    stayed in the emulator's stdio buffer and the last bytes of a block were lost.
  * `S"` at the prompt copies its string to HERE+4 (measured), so commands that use it are compared below HERE only.

HOW THE THROW CODE IS READ
  An uncaught THROW goes to RUNTIME_ERROR_HOOK, which prints the fixed text `STACK?` for every code (rom/forth_boot.asm,
  RUNTIME_ERROR_MSG) and sets INTERP_ERROR_FLAG: it cannot tell -37 from -28.  [Correction since step F (docs/V2/
  FLOAT_SPEC.md section 8.4): the hook now prints a message per code (-37 TAPE ERROR, -28 BREAK, -8 DICTIONARY FULL, and
  so on, ERROR n for any other code), and STACK? only for a stack check.  The reading below is unchanged and still
  right: the harness takes the code from CATCH, not from the screen.]  So the failing commands are run as
  `' LL CATCH [name]` with `: LL LOAD-LIB ;` (likewise LOAD-TEXT, SAVE-TEXT, VERIFY-*) defined during the lead:  LOAD-LIB
  parses its name from the rest of the input line (CATCH runs it from the interpreter), CATCH leaves the thrown code (or
  0) on the data stack, and the harness reads the cell at IX when the prompt is back.  "No error" is 0, "silent" is 0.
  Code -37 is the cell $FFDB, -28 is $FFE4.  Passing paths (a load that must succeed) use the plain command.

HOW "UNCHANGED" IS JUDGED
  Before the command and after it the harness reads HERE, LATEST and the dictionary RAM $9800..LOADTEXT_BUF-1 (so a
  stray write beyond HERE, such as a 64 KB LDIR, shows up).  LOADTEXT_BUF..DICT_RAM_CEILING-1 is left out: it is
  core/recall.asm's workspace, where the editor appends every line typed at the prompt on ENTER (an earlier version
  compared it and reported the typed command as a change).  VERIFY-LIB may write its CRC at HERE, HERE + 1 (spec
  section 6); those two bytes are not compared.  "Dictionary reset" = HERE $9800 and LATEST = DICT_LATEST_COLD
  (cold start's values).

THE ROM IDENTITY
  The 2-byte cell ROM_IDENTITY of forth_boot.sym, read from forth_boot_rom0.bin.  An old build has none: identity $0000
  is used, and the cases that need a type-3 header with a good identity fail on the format.

EXTRA LINES (not in the tally)
  11L   case 11 with a wildcard LOAD-LIB (the old receiver returns "success" on SPACE with a zeroed header buffer, so the
        old LOAD-LIB takes length 0 and crashes): judged like a case, reported on the `extras` line.
  7L 8L 8Z 9L 10L   old build only (no ROM_IDENTITY): the V1 (type 0) tapes of cases 7-10, which an old build loads, so the
        defects of section 1 show; INFO lines with the observed behaviour, not judged.

LIMITS (no hardware exists here; docs/V2/STORAGE_SPEC.md section 10)
  The tapes are pulses played into ZEsarUX's EAR input; SAVE output is the ROM's own MIC edges decoded from breakpoint
  actions on the sender's `out ($FE),a`.  Timing is emulated time (ZEsarUX partial T-state counter), not wall time.
  Cases 7-10 use type-3 (new format) tapes, which an old build skips; the old-build behaviour of the same defects with
  V1 (type 0) tapes is reported by the extra `legacy` lines (INFO, not counted) when the build has no ROM_IDENTITY.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
import pty
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import threading
import time

sys.dont_write_bytecode = True
HERE_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE_DIR)                      # python3 -I does not put the script's directory on sys.path
import tapes                                      # noqa: E402

HOME = os.path.expanduser("~")
ZDIR = os.environ.get("TS2068_DEBUG_ZESARUX_DIR", HOME + "/Applications/ZEsarUX-13.0")
PORT_LO, PORT_HI = 10960, 10979
T_PER_S = 3_494_400                               # ZEsarUX TS2068: 224 T * 312 lines * 50 Hz
KEY_MS = 40                                       # send-keys-string delay (wall); the edit line is read back
REPO = os.path.dirname(HERE_DIR)

try:
    import ts2068_debug.process as _proc          # noqa: F401
except ImportError:                               # -I drops the user site-packages
    sys.path.insert(0, HOME + "/ts2068-debug")
    import ts2068_debug.process as _proc          # noqa: F401
from ts2068_debug.controller import Ts2068Debug   # noqa: E402


class HarnessError(Exception):
    pass


class HarnessRetry(Exception):
    """A typing slip or too short a lead: the case is run again from a fresh emulator."""

    def __init__(self, msg, lead_scale=1.0):
        Exception.__init__(self, msg)
        self.lead_scale = lead_scale


# ----------------------------------------------------------------------------------------------- build
class Build:
    def __init__(self, d):
        self.dir = os.path.abspath(d)
        self.rom0, self.exrom = self.dir + "/forth_boot_rom0.bin", self.dir + "/graphics_exrom.bin"
        self.symfile = self.dir + "/forth_boot.sym"
        for f in (self.rom0, self.exrom, self.symfile):
            if not os.path.isfile(f):
                raise HarnessError("missing file " + f)
        self.S = {}
        for line in open(self.symfile):
            m = re.match(r"^(\S+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
            if m:
                self.S[m.group(1)] = int(m.group(2), 16)
        self.rom = open(self.rom0, "rb").read()
        s = self.S
        for n in ("HERE", "LATEST", "EDIT_LEN", "EDIT_BUF", "DSTACK_TOP", "IO_READ_KEY.wait_hit", "FORTH_DICT_RAM",
                  "DICT_RAM_CEILING", "INTERP_ERROR_FLAG", "FONT_TABLE"):
            if n not in s:
                raise HarnessError("symbol %s not in %s" % (n, self.symfile))
        self.idle = (s["IO_READ_KEY.wait_hit"], s["IO_READ_KEY.wait_hit"] + 5)
        self.dict0, self.ceiling = s["FORTH_DICT_RAM"], s["DICT_RAM_CEILING"]
        # LOADTEXT_BUF ($D000) .. the ceiling is core/recall.asm's workspace: the editor appends every line typed at
        # the prompt there on ENTER, so the "dictionary unchanged" checks stop below it
        self.workspace = s.get("LOADTEXT_BUF", self.ceiling)
        self.init_latest = s.get("DICT_LATEST_COLD")
        self.has_identity = "ROM_IDENTITY" in s
        a = s.get("ROM_IDENTITY")
        self.identity = (self.rom[a] | self.rom[a + 1] << 8) if a is not None and a + 1 < len(self.rom) else 0
        names = ("TAPE_SEND_BLOCK", "TAPE_RECV_BLOCK") if "TAPE_RECV_BLOCK" in s and "TAPE_SEND_BLOCK" in s else \
            ("STORAGE_SEND_BLOCK", "STORAGE_RECEIVE_BLOCK")
        self.send_lo, self.send_hi = s[names[0]], s[names[1]]
        # glyph -> character, for reading the screen (FONT_TABLE: space, 0-9, A-Z, a-z, then PUNCT_CHAR_TABLE)
        ft = s["FONT_TABLE"]
        chars = " 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
        idx = {i: c for i, c in enumerate(chars)}
        if "PUNCT_CHAR_TABLE" in s and "PUNCT_CHAR_COUNT" in s:
            p = s["PUNCT_CHAR_TABLE"]
            for k in range(s["PUNCT_CHAR_COUNT"]):
                idx[self.rom[p + 2 * k + 1]] = chr(self.rom[p + 2 * k])
        self.glyphs = {bytes(self.rom[ft + i * 8:ft + i * 8 + 8]): c for i, c in idx.items()}


# ----------------------------------------------------------------------------------------------- the emulator
class Sess:
    """One ZEsarUX run of a build (private state dir), plus the typing / reading helpers."""

    def __init__(self, build, port, tmp, capture=False):
        if not PORT_LO <= port <= PORT_HI:
            raise HarnessError("port %d outside %d-%d" % (port, PORT_LO, PORT_HI))
        self.b, self.port, self.tmp, self.capture = build, port, tmp, capture
        self.dbg = self.z = self.pid = None
        self.state = tempfile.mkdtemp(prefix="state.", dir=tmp)
        self.out_path = self.state + "/zesarux.out"
        self.typed_chars = 0

    def start(self):
        os.environ["TS2068_DEBUG_STATE_DIR"] = self.state
        img = self.state + "/image.bin"
        with open(img, "wb") as f:
            f.write(open(self.b.rom0, "rb").read() + open(self.b.exrom, "rb").read())
        real = subprocess.Popen
        slave = None
        if self.capture:
            # ZEsarUX's stdout goes to a pty, not a file: through a file libc block-buffers it and the last <4 KB of
            # the capture would stay inside the emulator; a terminal is line-buffered.
            self.master, slave = pty.openpty()
            threading.Thread(target=self._pump, daemon=True).start()

            def popen(*a, **k):
                k["stdout"] = slave
                return real(*a, **k)
            _proc.subprocess.Popen = popen
        try:
            self.dbg = Ts2068Debug(ZDIR, port=self.port, romfile=img)
            self.dbg.start()
        finally:
            _proc.subprocess.Popen = real
            if slave is not None:
                os.close(slave)
        self.z = self.dbg._zrcp
        pr = self.dbg._proc
        self.pid = getattr(pr, "pid", None) or pr._proc.pid
        return self

    def _pump(self):
        with open(self.out_path, "wb") as f:
            while True:
                try:
                    d = os.read(self.master, 65536)
                except OSError:
                    return
                if not d:
                    return
                f.write(d)
                f.flush()

    def stop(self):
        try:
            if self.dbg:
                self.dbg.stop()
        except Exception:
            pass
        try:
            if self.pid:
                _proc.terminate_emulator(self.pid, self.port, grace_s=3.0)
        except Exception:
            pass
        if getattr(self, "master", None) is not None:
            try:
                os.close(self.master)
            except OSError:
                pass
        shutil.rmtree(self.state, ignore_errors=True)

    # ---- reading
    def rd(self, a, n):
        return self.dbg.read_memory(a, n)

    def rd16(self, a):
        return int.from_bytes(self.rd(a, 2), "little")

    def regs(self):
        return self.dbg.get_registers().values

    def T(self):
        return int(self.z.command("get-tstates-partial").strip())

    def is_idle(self, pc_only=False):
        v = self.regs()
        pc = v["PC"]
        if pc == 0x38:
            pc = int.from_bytes(self.rd(v["SP"], 2), "little")
        return self.b.idle[0] <= pc < self.b.idle[1] and (pc_only or self.rd(self.b.S["EDIT_LEN"], 1)[0] == 0)

    def wait_idle(self, budget=40_000_000, pc_only=False):
        """Run (in step mode) until the prompt; budget in instructions."""
        self.dbg.pause()
        used, chunk = 0, 20_000
        while used < budget:
            if self.is_idle(pc_only):
                return True
            self.dbg.run(max_instructions=chunk)
            used += chunk
            chunk = min(chunk * 2, 500_000)
        return False

    def edit(self):
        n = self.rd(self.b.S["EDIT_LEN"], 1)[0]
        return self.rd(self.b.S["EDIT_BUF"], n).decode("latin-1")

    def screen(self):
        scr = self.rd(0x4000, 0x1800)
        rows = []
        for r in range(24):
            cells = [bytes(scr[((r >> 3) << 11) + (l << 8) + ((r & 7) << 5) + c] for l in range(8)) for c in range(32)]
            rows.append("".join(self.b.glyphs.get(x, "~") if any(x) else " " for x in cells).rstrip())
        return [r for r in rows if r.strip()]

    def here(self):
        return self.rd16(self.b.S["HERE"])

    def latest(self):
        return self.rd16(self.b.S["LATEST"])

    def stack(self):
        ix = self.regs()["IX"]
        top = self.b.S["DSTACK_TOP"]
        n = max(0, min(16, (top - ix) // 2))
        raw = self.rd(ix, 2 * n) if n else b""
        return [struct.unpack_from("<h", raw, 2 * i)[0] for i in range(n)]      # signed cells, top first

    def err_flag(self):
        return self.rd(self.b.S["INTERP_ERROR_FLAG"], 1)[0]

    def snap(self):
        """HERE, LATEST and the whole dictionary RAM (paused)."""
        return dict(here=self.here(), latest=self.latest(), ram=bytes(self.rd(self.b.dict0, self.b.ceiling - self.b.dict0)))

    # ---- typing
    def type_text(self, text, enter=False):
        """Type `text` (not ENTER), read the edit line back, compare: a mismatch retries the case."""
        self.dbg.resume()
        self.z.command("send-keys-string %d %s" % (KEY_MS, text), timeout=15 + 0.2 * len(text))
        time.sleep(0.25)
        self.dbg.pause()
        got = self.edit()
        self.typed_chars += len(text)
        if got != text:
            raise HarnessRetry("typing slip: typed %r, edit line %r" % (text, got))

    def go(self):
        """Run freely (no settle sleep, unlike Ts2068Debug.resume)."""
        if self.z.in_step_mode:
            self.z.command("exit-cpu-step")

    def press_enter(self, tries=6):
        """ENTER, confirmed: ZEsarUX drops a key pressed just after resuming, so settle, press, and look (paused) at
        whether the edit line was taken; press again if not.  Returns the partial T counter when it was taken."""
        for _ in range(tries):
            self.go()
            time.sleep(0.25)
            self.dbg.press_key("ENTER")
            time.sleep(0.15)
            self.dbg.pause()
            if self.rd(self.b.S["EDIT_LEN"], 1)[0] == 0 or not self.is_idle(pc_only=True):
                return self.T()
        raise HarnessError("ENTER was never taken")

    def line(self, text, max_instr=40_000_000):
        """Type a line, ENTER, wait for the prompt; returns INTERP_ERROR_FLAG (1 = the line raised an error)."""
        self.type_text(text)
        self.press_enter()
        time.sleep(0.15)
        if not self.wait_idle(max_instr):
            raise HarnessError("no prompt after line %r" % text)
        return self.err_flag()

    def poll_idle(self, max_wall, poll=0.1, pc_only=False):
        """Run until the prompt (polling a paused/resumed emulator); returns (idle, partial T at detection)."""
        t_end = time.time() + max_wall
        while time.time() < t_end:
            self.go()
            time.sleep(poll)
            self.dbg.pause()
            if self.is_idle(pc_only):
                return True, self.T()
        return False, self.T()

    def run_to(self, t_target, poll=0.03, max_wall=120):
        """Run until the partial T-state counter reaches t_target (paused on return)."""
        t_end = time.time() + max_wall
        self.dbg.pause()
        while self.T() < t_target:
            if time.time() > t_end:
                raise HarnessError("run_to timeout")
            self.go()
            time.sleep(max(poll, 0.6 * (t_target - self.T()) / T_PER_S / 6.0) if poll >= 0.03 else poll)
            self.dbg.pause()

    def step_idle(self, chunk=20_000, budget=40_000_000, pc_only=True):
        """Single-step in chunks (the emulator stays in step mode: pausing or resuming it releases a held key) until the
        prompt; returns (idle, partial T)."""
        self.dbg.pause()
        used = 0
        while used < budget:
            self.dbg.run(max_instructions=chunk)
            used += chunk
            if self.is_idle(pc_only):
                return True, self.T()
        return False, self.T()

    def space(self, down):
        self.z.command("send-keys-event 128 %d" % (1 if down else 0))

    # ---- tape
    def insert(self, path):
        """realtape-open: resets the machine; the tape plays from now.  Partial T counter = tape time."""
        self.dbg.pause()
        self.z.command("reset-tstates-partial")
        self.z.command("realtape-open " + path)
        if not self.wait_idle():
            raise HarnessError("no prompt after realtape-open")

    # ---- SAVE capture
    def arm_capture(self):
        lo, hi = self.b.send_lo, self.b.send_hi
        code = self.rd(lo, hi - lo)
        outs = [lo + i for i in range(len(code) - 1) if code[i:i + 2] == b"\xD3\xFE"]
        if not 1 <= len(outs) <= 8:
            raise HarnessError("%d `out ($FE),a` in the sender" % len(outs))
        self.z.command("enable-breakpoints")
        self.slots = list(range(14, 14 + len(outs)))
        for slot, a in zip(self.slots, outs):
            self.z.command("set-breakpoint %d PC=%04XH" % (slot, a))
            self.z.command("set-breakpointaction %d printe TSTATESP*16+(A&8)" % slot)
        self.z.command("reset-tstates-partial")
        return outs

    def captured(self):
        """The printed values so far (breakpoints stay armed)."""
        self.z.command("noop")
        time.sleep(0.25)
        txt = open(self.out_path, errors="replace").read()
        return [int(l) for l in txt.split("\n") if l.strip().lstrip("-").isdigit()]

    def disarm_capture(self):
        for slot in self.slots:
            self.z.command("set-breakpoint %d" % slot)
            self.z.command("set-breakpointaction %d" % slot)


def sgn16(v):
    return v - 0x10000 if v >= 0x8000 else v


# ----------------------------------------------------------------------------------------------- verdicts
class Verdict:
    def __init__(self):
        self.fails, self.obs = [], []

    def check(self, ok, msg):
        if not ok:
            self.fails.append(msg)
        return ok

    def note(self, msg):
        self.obs.append(msg)


def chk_code(v, label, observed, expected):
    return v.check(observed == expected, "%s: THROW code %s, expected %s" % (label, observed, expected))


def chk_bytes(v, label, got, want):
    if got == want:
        return True
    n = next((i for i in range(min(len(got), len(want))) if got[i] != want[i]), min(len(got), len(want)))
    return v.check(False, "%s differs (len %d vs %d, first diff at %d)" % (label, len(got), len(want), n))


def chk_same(v, label, before, after, whole=True, workspace=0xD000, skip=()):
    """HERE, LATEST and the dictionary RAM identical: $9800 up to the recall workspace (whole), or only below HERE
    (whole=False: for commands that use S", which leaves its string just above HERE). skip: addresses allowed to change
    (VERIFY-LIB's CRC at HERE, HERE + 1)."""
    n = (workspace if whole else before["here"]) - 0x9800
    before, after = dict(before, ram=bytearray(before["ram"][:n])), dict(after, ram=bytearray(after["ram"][:n]))
    for a in skip:
        if 0 <= a - 0x9800 < n:
            after["ram"][a - 0x9800] = before["ram"][a - 0x9800]
    ok = True
    if before["here"] != after["here"]:
        ok = v.check(False, "%s: HERE %04X -> %04X" % (label, before["here"], after["here"]))
    if before["latest"] != after["latest"]:
        ok = v.check(False, "%s: LATEST %04X -> %04X" % (label, before["latest"], after["latest"]))
    if before["ram"] != after["ram"]:
        n = [i for i in range(len(before["ram"])) if before["ram"][i] != after["ram"][i]]
        ok = v.check(False, "%s: %d dictionary RAM bytes changed (first at $%04X)" % (label, len(n), 0x9800 + n[0]))
    return ok


def chk_reset(b, v, label, after):
    ok = v.check(after["here"] == b.dict0, "%s: HERE %04X, expected %04X (reset)" % (label, after["here"], b.dict0))
    if b.init_latest is not None:
        ok = v.check(after["latest"] == b.init_latest, "%s: LATEST %04X, expected %04X (reset)" %
                     (label, after["latest"], b.init_latest)) and ok
    return ok


def chk_header(v, label, blk, htype, name, length, p1, p2, flag=0x00):
    f, payload, ok = tapes.unframe(blk["data"])
    h = tapes.parse_header(payload)
    v.check(blk["ok"], "%s: header checksum bad" % label)
    v.check(f == flag, "%s: header flag %s" % (label, f))
    if h is None:
        return v.check(False, "%s: header payload %d bytes, not 17" % (label, len(payload)))
    r = True
    for k, want in (("type", htype), ("length", length), ("param1", p1), ("param2", p2)):
        if want is not None and h[k] != want:
            r = v.check(False, "%s: header %s = %s, expected %s" % (label, k, "$%04X" % h[k] if k.startswith("p") else h[k],
                                                                      "$%04X" % want if k.startswith("p") else want))
    if name is not None:
        r = v.check(h["name"].rstrip() == name, "%s: header name %r, expected %r" % (label, h["name"], name)) and r
    return r


# ----------------------------------------------------------------------------------------------- tape sessions
def lead_for(chars, extra_s=0):
    return int(10 + 0.55 * chars + extra_s)


class Ctx:
    def __init__(self, build, port, work):
        self.b, self.port, self.work = build, port, work
        self.n = 0
        self.scale = 1.0                 # lead multiplier, raised when a run found its lead too short

    def path(self, ext):
        self.n += 1
        return "%s/t%d_%d%s" % (self.work, os.getpid(), self.n, ext)

    def session(self, capture=False):
        return Sess(self.b, self.port, self.work, capture)


def play(ctx, items, setup, cmd, lead_s=None, capture=False):
    """New emulator; insert a tape (lead + items); type the setup lines; type `cmd`; ENTER ~3 s before the lead ends.
    Returns the paused Sess and dict(lead) (caller stops the session)."""
    chars = sum(len(s) + 1 for s in setup) + len(cmd)
    lead = (lead_s if lead_s is not None else lead_for(chars)) * ctx.scale
    s = ctx.session(capture).start()
    try:
        s.wait_idle()
        path = ctx.path(".tzx")
        open(path, "wb").write(tapes.tzx(items, lead_ms=int(lead * 1000)))
        s.insert(path)
        for ln in setup:
            if s.line(ln):
                raise HarnessError("setup line raised an error: %r" % ln)
            if s.T() > (lead - 4.0) * T_PER_S:
                raise HarnessRetry("lead too short after setup", 1.5)
        s.type_text(cmd)
        t_enter = int((lead - 5.0) * T_PER_S)
        if s.T() > t_enter - int(0.8 * T_PER_S):
            raise HarnessRetry("lead too short for the command (T=%.1fs, lead %.1fs)" % (s.T() / T_PER_S, lead), 1.5)
        s.run_to(t_enter)
        return s, dict(lead=lead)
    except BaseException:
        s.stop()
        raise


def finish(s, max_wall=400, pc_only=False):
    """ENTER and wait for the prompt.  Returns dict(idle, emu_s (ENTER -> prompt), wall)."""
    w0 = time.time()
    t0 = s.press_enter()
    idle, t1 = s.poll_idle(max_wall, pc_only=pc_only)
    return dict(idle=idle, emu_s=(t1 - t0) / T_PER_S, wall=time.time() - w0)


def catch_cmd(word, name=""):
    return ("' %s CATCH %s" % (word, name)).rstrip()


# ----------------------------------------------------------------------------------------------- cases
TEXT_DBL = ": DOUBLER DUP + ; 21 DOUBLER ."
LL_LINE = ": LL LOAD-LIB ;"
SYN_DICT = bytes((i * 7 + 3) & 0xFF for i in range(96))         # a synthetic dictionary image for the rejecting cases
SYN_LATEST = 0x9840


def foreign_identity(b):
    return ((b.identity ^ 0x5A5A) | 0x8000) & 0xFFFF


def screen_has(rows, pat):
    return any(re.search(pat, r) for r in rows)


def gen_tap_tape_gen_forth(work, entries):
    """tools/tape_gen_forth.py's own output for NAME:FILE entries -> its blocks."""
    args = []
    for name, data in entries:
        p = "%s/%s_%d.fs" % (work, name, os.getpid())
        open(p, "wb").write(data)
        args.append("%s:%s" % (name, p))
    out = "%s/gen_%d.tap" % (work, os.getpid())
    r = subprocess.run([sys.executable, "-I", REPO + "/tools/tape_gen_forth.py", out] + args, capture_output=True, text=True)
    if r.returncode:
        raise HarnessError("tape_gen_forth.py failed: " + r.stderr[-200:])
    return tapes.read_tap(open(out, "rb").read())


def case_1(ctx):
    v = Verdict()
    blocks = gen_tap_tape_gen_forth(ctx.work, [("MINI", TEXT_DBL.encode())])
    s, _ = play(ctx, blocks, [], "LOAD-TEXT MINI")
    try:
        r = finish(s)
        v.check(r["idle"], "no prompt after LOAD-TEXT")
        rows = s.screen()
        v.check(screen_has(rows, r"\b42\b"), "screen has no 42: %s" % rows[-3:])
        v.check(s.err_flag() == 0, "error reported by LOAD-TEXT")
        v.note("loaded in %.1f s emulated; screen %s" % (r["emu_s"], rows[-2:]))
    finally:
        s.stop()
    return v


BJ_FS = REPO + "/tests/data/blackjack_rounds.txt"   # demos/blackjack.fs with a log of each round at 62120
BJ_EXPECT = [21, 15, 4, 23, 12, 3, 21, 19, 4, 15, 23, 1]       # the round log at 62120.. (seed 15785)


def case_2(ctx):
    v = Verdict()
    text = open(BJ_FS, "rb").read()
    blocks = gen_tap_tape_gen_forth(ctx.work, [("BJPROG", text)])
    s, _ = play(ctx, blocks, [], "LOAD-TEXT BJPROG")
    try:
        r = finish(s, max_wall=600)
        v.check(r["idle"], "no prompt after the Blackjack text (%.0f s emulated)" % r["emu_s"])
        got = [s.rd16(62120 + 2 * i) for i in range(12)]
        v.check(got == BJ_EXPECT, "round log %s, expected %s" % (got, BJ_EXPECT))
        v.check(s.err_flag() == 0, "error reported while loading")
        v.note("%.0f s emulated; screen %s" % (r["emu_s"], s.screen()[-2:]))
    finally:
        s.stop()
    return v


def save_and_capture(ctx, setup, cmd, v, label, space_after_s=None, extra_wait=0, poke=None):
    """Fresh emulator, no tape: setup lines, then `cmd` with the sender's MIC edges captured.  poke(s): called with the
    paused session after the setup lines, to put bytes into memory.  Returns (Sess paused, blocks decoded, dict)."""
    s = ctx.session(capture=True).start()
    try:
        s.wait_idle()
        for ln in setup:
            if s.line(ln):
                raise HarnessError("setup line raised an error: %r" % ln)
        if poke:
            poke(s)
        pre = s.snap()
        s.arm_capture()
        s.type_text(cmd)
        t0 = s.press_enter()
        info = dict(pre=pre)
        if space_after_s:
            s.run_to(t0 + int(space_after_s * T_PER_S), poll=0.02)      # into the header pilot
            s.space(True)                                                  # paused: the key stays down while stepping
            info["space_at"] = len(s.captured())
            idle, t1 = s.step_idle(chunk=300_000, budget=60_000_000)
            s.space(False)
            time.sleep(0.3)
            s.dbg.pause()
        else:
            idle, t1 = s.poll_idle(200)
        info.update(idle=idle, emu_s=(t1 - t0) / T_PER_S)
        s.disarm_capture()
        vals = s.captured()
        info["edges"] = len(vals)
        info["blocks"] = tapes.decode(tapes.edges_from_capture(vals))
        return s, info
    except BaseException:
        s.stop()
        raise


def tape_from_blocks(blocks):
    return [b["data"] for b in blocks]


def case_3(ctx):
    v = Verdict()
    # The store is built by typing: both lines run (prints 42) and are appended to the store with their CRs; the SAVE-TEXT
    # line is appended too and trimmed by STORE_TRIM, so the tape holds exactly the two lines, not the command.
    lines = [": DBL DUP + ;", "21 DBL ."]
    text = b"".join(l.encode() + b"\r" for l in lines)
    s, info = save_and_capture(ctx, lines, "SAVE-TEXT TXTSAVE", v, "SAVE-TEXT")
    try:
        blks = info["blocks"]
        v.check(info["idle"], "SAVE-TEXT did not return")
        if not v.check(len(blks) == 2, "captured %d blocks, expected 2" % len(blks)):
            return v
        chk_header(v, "SAVE-TEXT", blks[0], 0, "TXTSAVE", len(text), 0x8000, len(text))
        f, payload, ok = tapes.unframe(blks[1]["data"])
        v.check(f == 0xFF and ok, "SAVE-TEXT data block flag/checksum (flag %s)" % f)
        chk_bytes(v, "SAVE-TEXT payload (the typed lines + CR, not the SAVE-TEXT line)", payload, text)
        v.note("%d edges, %d blocks, %.1f s emulated" % (info["edges"], len(blks), info["emu_s"]))
    finally:
        s.stop()
    if len(blks) != 2:
        return v
    # played back into a fresh machine
    s2, _ = play(ctx, tape_from_blocks(blks), [], "LOAD-TEXT TXTSAVE")
    try:
        r = finish(s2)
        v.check(r["idle"], "no prompt after LOAD-TEXT of the captured tape")
        v.check(screen_has(s2.screen(), r"\b42\b"), "round trip: no 42 on the screen %s" % s2.screen()[-3:])
        v.check(s2.err_flag() == 0, "round trip: error reported")
    finally:
        s2.stop()
    return v


# Step E (docs/V2/EDITOR_SPEC.md section 8, N4): the text tape round trip of a STORE of CR-ended lines.  The bytes are put into
# the store directly (STORE_START = LOADTEXT_BUF, end cell STORE_END, or WORKSPACE_END on the old build), SAVE-TEXT writes them
# from the store, the capture is decoded and played into a fresh machine, LOAD-TEXT puts them back: the store must hold
# the same bytes and the program must have run.  SAVE-TEXT takes no address and length: it saves the store, and the
# command line the console appended behind the poked text is trimmed (docs/V2/EDITOR_SPEC.md section 3).
#
# HOW THE TEXT SURVIVES THE OLD BUILD.  There CR is part of a word (core/interp.asm W_WORD splits at a space only), and an
# unknown word inside LOAD-TEXT's text does not return an error: the error path unwinds one level too far and the machine
# restarts at $0000 (measured by tools/edtest.py N3), losing the store and the screen.  So the text has no unknown token
# for the old build: its first line is ordinary space-separated Forth that ends with a lone colon, and every later line is
# a single token, so that the old tokenizer sees `: ` followed by ONE token (all the remaining lines glued with their CRs,
# 25 bytes, under WORD's 32-character limit) which the colon takes as the NAME of a new definition, and the text ends:
#     : DBL DUP + ; 21 DBL . :<space> CR TRI CR DUP CR DBL CR + CR ; CR 7 CR TRI CR . CR
# Old build: defines DBL, prints 42, defines a word with a name of 25 characters (CRs inside), no error.  A build in which
# CR is whitespace (it has STORE_END) defines TRI = DUP DBL +, runs `7 TRI .` and prints 21 as well.  Both: the tape
# carries the nine CR-ended lines byte for byte, SAVE-TEXT and LOAD-TEXT keep them, the store afterwards is identical, no
# error.  What is not checked on the old build is the only thing the spec says it cannot do (table N4: "passes with its
# space-separated text"): that lines run as lines.
N4_TEXT = b": DBL DUP + ; 21 DBL . : \rTRI\rDUP\rDBL\r+\r;\r7\rTRI\r.\r"


def case_n4(ctx):
    v = Verdict()
    b = ctx.b
    text = N4_TEXT
    end_cell = b.S["STORE_END"] if "STORE_END" in b.S else b.S["WORKSPACE_END"]
    crws = "STORE_END" in b.S                  # the build whose WORD takes CR as whitespace (step E) has the new end cell
    buf = b.S["LOADTEXT_BUF"]
    v.check(text.count(b"\r") == 9 and text.endswith(b"\r"), "test text: nine CR-ended lines")

    def poke(s):
        s.dbg.pause()
        s.z.command("write-memory-raw %d %s" % (buf, text.hex()))
        s.z.command("write-memory-raw %d %s" % (end_cell, struct.pack("<H", buf + len(text)).hex()))

    # The console appends "SAVE-TEXT N4TXT" + CR after the poked text; STORE_TRIM takes it off again, so the payload is
    # exactly the poked bytes.  (Old build: `<addr> <len> SAVE-TEXT N4TXT`, which saved from the buffer given.)
    cmd = "SAVE-TEXT N4TXT"
    s, info = save_and_capture(ctx, [], cmd, v, "SAVE-TEXT", poke=poke)
    try:
        blks = info["blocks"]
        v.check(info["idle"], "N4 SAVE-TEXT did not return")
        if not v.check(len(blks) == 2, "N4 captured %d blocks, expected 2" % len(blks)):
            return v
        chk_header(v, "N4 SAVE-TEXT", blks[0], 0, "N4TXT", len(text), 0x8000, len(text))
        f, payload, ok = tapes.unframe(blks[1]["data"])
        v.check(f == 0xFF and ok, "N4 SAVE-TEXT data block flag/checksum (flag %s)" % f)
        chk_bytes(v, "N4 SAVE-TEXT payload (the store bytes, CRs included)", payload, text)
        v.note("N4 %d edges, %d blocks, %.1f s emulated" % (info["edges"], len(blks), info["emu_s"]))
    finally:
        s.stop()
    s2, _ = play(ctx, tape_from_blocks(blks), [], "LOAD-TEXT N4TXT")
    try:
        r = finish(s2)
        v.check(r["idle"], "N4 no prompt after LOAD-TEXT of the captured tape")
        end = s2.rd16(end_cell)
        v.check(end == buf + len(text), "N4 store end %04X, expected %04X" % (end, buf + len(text)))
        chk_bytes(v, "N4 store after LOAD-TEXT", bytes(s2.rd(buf, max(0, min(end - buf, 8192)))), text)
        rows = s2.screen()
        v.check(screen_has(rows, r"\b42\b"), "N4 round trip: no 42 on the screen %s" % rows[-3:])
        v.check(s2.err_flag() == 0, "N4 round trip: error reported")
        if crws:
            v.check(screen_has(rows, r"\b21\b"), "N4 round trip: the CR-separated lines did not run (no 21) %s" % rows[-3:])
        v.note("N4 %s: expected 42%s on the screen, store %d bytes identical to the saved ones" % (
            "new build (CR is whitespace)" if crws else "old build (CR is part of a word)", " and 21" if crws else "", len(text)))
    finally:
        s2.stop()
    return v


def case_4(ctx):
    return lib_roundtrip(ctx, [LL_LINE, ": SQ DUP * ; : CUBE DUP SQ * ;"], "LIBA", "LOAD-LIB LIBA", "5 CUBE .", r"\b125\b")


def case_15(ctx):
    """A dictionary over 512 bytes (several tape bytes past one page) saved, then loaded by a wildcard LOAD-LIB."""
    return lib_roundtrip(ctx, [LL_LINE, "CREATE BIG 600 ALLOT : SQ DUP * ;"], "LIBB", "LOAD-LIB", "7 SQ .", r"\b49\b")


def lib_roundtrip(ctx, setup, name, load_cmd, probe, want_re):
    """SAVE-LIB `name` after `setup`: the captured header and data judged, then the captured tape loaded into a fresh
    machine with `load_cmd`: the dictionary must come back byte for byte and `probe` must print `want_re`."""
    v = Verdict()
    b = ctx.b
    s, info = save_and_capture(ctx, setup, "SAVE-LIB " + name, v, "SAVE-LIB")
    try:
        blks = info["blocks"]
        post = s.snap()
        dict_a = post["ram"][:post["here"] - b.dict0]
        v.check(info["idle"], "SAVE-LIB did not return")
        v.check(post["here"] == info["pre"]["here"] and post["latest"] == info["pre"]["latest"],
                "SAVE-LIB moved HERE/LATEST")
        if not v.check(len(blks) == 2, "captured %d blocks, expected 2" % len(blks)):
            return v
        chk_header(v, "SAVE-LIB", blks[0], 3, name, len(dict_a) + 2, b.identity if b.has_identity else None,
                   post["latest"])
        if not b.has_identity:
            v.check(False, "no ROM_IDENTITY in this build (header param 1 cannot carry it)")
        f, payload, ok = tapes.unframe(blks[1]["data"])
        v.check(f == 0xFF and ok, "SAVE-LIB data block flag/checksum (flag %s, ok %s)" % (f, ok))
        want = dict_a + struct.pack("<H", tapes.crc16(dict_a))
        chk_bytes(v, "SAVE-LIB data (dictionary + CRC-16)", payload, want)
        v.note("%d edges, dictionary %d B, header type %s" % (info["edges"], len(dict_a),
                                                               tapes.parse_header(tapes.unframe(blks[0]["data"])[1]) and
                                                               tapes.parse_header(tapes.unframe(blks[0]["data"])[1])["type"]))
    finally:
        s.stop()
    # round trip into a fresh machine (the tape = exactly what the ROM sent)
    s2, _ = play(ctx, tape_from_blocks(blks), [], load_cmd)
    try:
        r = finish(s2)
        v.check(r["idle"], "no prompt after LOAD-LIB of the captured tape")
        b2 = s2.snap()
        dict_b = b2["ram"][:max(0, b2["here"] - b.dict0)]
        v.check(b2["here"] == post["here"], "round trip: HERE %04X, expected %04X" % (b2["here"], post["here"]))
        v.check(b2["latest"] == post["latest"], "round trip: LATEST %04X, expected %04X" % (b2["latest"], post["latest"]))
        chk_bytes(v, "round trip: dictionary bytes", dict_b, dict_a)
        v.check(s2.err_flag() == 0, "round trip: error reported")
        if not s2.line(probe):
            v.check(screen_has(s2.screen(), want_re), "round trip: %r did not print %s %s" % (probe, want_re, s2.screen()[-2:]))
        else:
            v.check(False, "round trip: %r failed after the load" % probe)
    finally:
        s2.stop()
    return v


def lib_case(ctx, items, expect, label, setup=None, word="LL", name="", reset=False, lead_extra=0, max_wall=400):
    """Common body of cases 5-10: machine with `setup`, tape `items`, `' LL CATCH [name]`; expect a THROW code and an
    unchanged dictionary (or a reset one)."""
    v = Verdict()
    b = ctx.b
    setup = setup if setup is not None else [LL_LINE]
    s, _ = play(ctx, items, setup, catch_cmd(word, name), lead_s=lead_for(sum(len(x) + 1 for x in setup) + 20, lead_extra))
    try:
        before = s.snap()
        r = finish(s, max_wall=max_wall)
        v.check(r["idle"], "%s: no prompt after %.0f s emulated" % (label, r["emu_s"]))
        after = s.snap()
        st = s.stack()
        v.check(len(st) >= 1, "%s: no value left by CATCH (stack %s)" % (label, st))
        code = st[0] if st else None
        chk_code(v, label, code, expect)
        if reset:
            chk_reset(b, v, label, after)
        else:
            chk_same(v, label, before, after, workspace=b.workspace)
        v.note("%s: code %s, %.1f s emulated, HERE %04X->%04X LATEST %04X->%04X" % (
            label, code, r["emu_s"], before["here"], after["here"], before["latest"], after["latest"]))
    finally:
        s.stop()
    return v


def case_5(ctx):
    b = ctx.b
    items = tapes.lib_file("LIBF", SYN_DICT, SYN_LATEST, foreign_identity(b))
    return lib_case(ctx, items, -37, "foreign identity", name="LIBF")


def v1_image(ctx):
    """A V1 dictionary image that begins with the machine's own `: LL LOAD-LIB ;` (so the old loader returns into intact
    code) followed by synthetic bytes: (dictionary bytes, LATEST)."""
    _, _, d0, errs = prep_dict(ctx, [LL_LINE])
    if errs:
        raise HarnessError("the setup line %r failed" % LL_LINE)
    return d0 + SYN_DICT, 0x9800 + len(d0) + 0x20


def case_6(ctx):
    d, latest = v1_image(ctx)
    items = tapes.v1_lib_file("LIBV1", d, latest)
    return lib_case(ctx, items, -37, "V1 type-0 lib tape", name="LIBV1")


def case_7(ctx):
    b = ctx.b
    bad = bytearray(SYN_DICT)
    bad[40] ^= 0x04
    items = tapes.lib_file("LIBC", bytes(bad), SYN_LATEST, b.identity, crc=tapes.crc16(SYN_DICT))
    return lib_case(ctx, items, -37, "CRC mismatch (XOR fixed up)", name="LIBC", reset=True)


def case_8(ctx):
    b = ctx.b
    items = tapes.lib_file("LIBL0", b"", SYN_LATEST, b.identity, length=0)[:1] + [tapes.framed(0xFF, b"")] + \
        tapes.lib_file("LIBL1", b"", SYN_LATEST, b.identity, length=1)[:1] + [tapes.framed(0xFF, b"\x5A")]
    # a wildcard load: the first acceptable type-3 header wins, so a wrongly accepted length 0 or 1 would load
    return lib_case(ctx, items, -37, "header length 0 and 1", name="")


def case_9(ctx):
    b = ctx.b
    items = tapes.lib_file("LIBW", SYN_DICT, SYN_LATEST, b.identity, flag=0x55)
    return lib_case(ctx, items, -37, "data block with the wrong flag", name="LIBW")


def dropout_items(b, name, dropout_bytes=(10, 2), identity=None):
    hdr, data = tapes.lib_file(name, SYN_DICT, SYN_LATEST, b.identity if identity is None else identity)
    t = tapes.Tape().block(data, dropout=dropout_bytes, gap=0)
    return [hdr, ("pulses", t.pulses()), ("pause", 1000)]


def case_10(ctx):
    return lib_case(ctx, dropout_items(ctx.b, "LIBD"), -37, "dropout in the data block", name="LIBD", reset=True)


def timed_command(ctx, setup, cmd, label, space_after=None, expect=None, max_wall=400):
    """No tape.  Used by 11 (SPACE after `space_after` s) and 11a.  Returns (Verdict, code, dict)."""
    v = Verdict()
    s = ctx.session().start()
    try:
        s.wait_idle()
        for ln in setup:
            if s.line(ln):
                raise HarnessError("setup line raised an error: %r" % ln)
        pre = s.snap()
        s.type_text(cmd)
        t0 = s.press_enter()
        if space_after is not None:
            s.run_to(t0 + int(space_after * T_PER_S), poll=0.02)
            s.space(True)
            ts = s.T()
            idle, t1 = s.step_idle(chunk=20_000, budget=40_000_000)
            s.space(False)
            time.sleep(0.3)
            s.dbg.pause()
            emu = (t1 - ts) / T_PER_S
            d = dict(idle=idle, emu_s=emu, since="SPACE")
        else:
            idle, t1 = s.poll_idle(max_wall, poll=0.04)
            d = dict(idle=idle, emu_s=(t1 - t0) / T_PER_S, since="ENTER")
        st = s.stack()
        code = st[0] if st else None
        d["flag"] = s.err_flag()
        d["screen"] = s.screen()[-3:]
        if idle:
            after = s.snap()
            d["changed"] = sum(1 for x, y in zip(pre["ram"], after["ram"]) if x != y)
        return v, code, d
    finally:
        s.stop()


LT_LINE = ": LT LOAD-TEXT ;"


def case_11(ctx, word="LT", line=LT_LINE, label="SPACE during the header search"):
    v, code, d = timed_command(ctx, [line], catch_cmd(word), label, space_after=2.0)
    v.check(d["idle"], "%s: the prompt did not come back (%.0f s emulated after SPACE; screen %s)" % (
        label, d["emu_s"], d["screen"]))
    chk_code(v, label, code, -28)
    v.check(d["idle"] and d["emu_s"] <= 1.0, "%s: prompt %.2f s emulated after SPACE (limit 1 s)" % (label, d["emu_s"]))
    v.note("code %s, %.3f s emulated from SPACE to the prompt, idle %s, screen %s" % (code, d["emu_s"], d["idle"], d["screen"]))
    return v


def case_11l(ctx):
    """Extra: the same with LOAD-LIB (a wildcard LOAD-LIB takes SPACE's phantom 'header' as length 0)."""
    return case_11(ctx, "LL", LL_LINE, "SPACE during the header search (LOAD-LIB)")


def case_11a(ctx):
    v, code, d = timed_command(ctx, [LT_LINE], catch_cmd("LT"), "no tape", max_wall=500)
    v.check(d["idle"], "no prompt")
    chk_code(v, "no tape", code, -37)
    # 15 receive attempts of ~8.6 s each (STORAGE_SPEC.md section 5, step 6): about 129 s, plus the typing
    v.check(d["idle"] and 110 <= d["emu_s"] <= 160, "gave up after %.1f s emulated (expected about 2 minutes)" % d["emu_s"])
    v.note("code %s, %.1f s emulated from ENTER to the prompt; dictionary RAM bytes changed: %s" % (
        code, d["emu_s"], d.get("changed")))
    return v


def case_12(ctx):
    v = Verdict()
    # The store holds the two setup lines (the command line is trimmed); the case is about the SPACE (BREAK) during the
    # header, not about what is saved, so no payload is judged.
    s, info = save_and_capture(ctx, [": ST SAVE-TEXT ;", "1 2 + ."], catch_cmd("ST", "SPCX"), v, "SAVE-TEXT",
                               space_after_s=1.5)
    try:
        blks = info["blocks"]
        st = s.stack()
        code = st[0] if st else None
        v.check(info["idle"], "SAVE-TEXT did not return after SPACE")
        chk_code(v, "SPACE during the SAVE header", code, -28)
        v.check(len(blks) == 1, "captured %d blocks (header + data would be 2), expected 1" % len(blks))
        v.check(not any(bb["data"][:1] == b"\xff" for bb in blks), "a data block was sent after SPACE")
        rest = info["edges"] - sum(bb["pilot"] + 3 + 16 * len(bb["data"]) for bb in blks)
        v.note("code %s; %d edges, decoded blocks (bytes, checksum ok) %s, about %d further edges (a pilot that was cut "
               "short); SPACE down after %s edges (1.5 s into the header)" % (code, info["edges"], [(len(bb["data"]), bb["ok"]) for bb in blks],
                                                     rest, info.get("space_at")))
    finally:
        s.stop()
    return v


def case_13(ctx):
    v = Verdict()
    items = tapes.text_file("WRONG", ": ZZ 99 ;") + tapes.text_file("RIGHT", TEXT_DBL)
    s, _ = play(ctx, items, [], "LOAD-TEXT RIGHT")
    try:
        r = finish(s)
        v.check(r["idle"], "no prompt after LOAD-TEXT RIGHT")
        v.check(screen_has(s.screen(), r"\b42\b"), "second file did not load (no 42): %s" % s.screen()[-3:])
        v.check(s.err_flag() == 0, "error reported")
        if not s.line("ZZ"):
            v.check(False, "the wrong-named file was loaded too (ZZ is defined)")
        v.note("%.1f s emulated" % r["emu_s"])
    finally:
        s.stop()
    return v


def prep_dict(ctx, setup):
    """HERE, LATEST and the dictionary bytes after typing `setup` into a fresh machine (cached per build)."""
    key = hashlib.sha1((ctx.b.dir + "\n" + "\n".join(setup)).encode()).hexdigest()[:12]
    cf = "%s/prep_%s.json" % (ctx.work, key)
    if os.path.isfile(cf):
        d = json.load(open(cf))
        return d["here"], d["latest"], bytes.fromhex(d["dict"]), d["errors"]
    s = ctx.session().start()
    try:
        s.wait_idle()
        errs = [ln for ln in setup if s.line(ln)]
        sn = s.snap()
        d = sn["ram"][:sn["here"] - ctx.b.dict0]
        json.dump(dict(here=sn["here"], latest=sn["latest"], dict=d.hex(), errors=errs), open(cf, "w"))
        return sn["here"], sn["latest"], d, errs
    finally:
        s.stop()


def case_14(ctx):
    v = Verdict()
    b = ctx.b
    setup = [": VL VERIFY-LIB ; : VT VERIFY-TEXT ;", ": SQ DUP * ; : CUBE DUP SQ * ;"]
    here, latest, d, errs = prep_dict(ctx, setup)
    if errs:
        v.check(False, "VERIFY-LIB / VERIFY-TEXT unknown (setup line raised an error)")
        return v
    bad = bytearray(d)
    bad[len(d) // 2] ^= 0x01
    # VERIFY-TEXT compares with the store, which holds the typed setup lines (text + CR each; the VERIFY-TEXT command line
    # is trimmed by STORE_TRIM before the compare and is not part of it).  So the matching tape is those lines; a tape that
    # differs in one byte, or only in length (one byte short: a prefix of the store; one byte long), is refused (-37).
    store = b"".join(l.encode() + b"\r" for l in setup)
    bad_t = bytearray(store)
    bad_t[len(store) // 2] ^= 0x01
    runs = [("VERIFY-LIB match", tapes.lib_file("GOODLIB", d, latest, b.identity), [], catch_cmd("VL", "GOODLIB"), 0, False),
            ("VERIFY-LIB one byte differs", tapes.lib_file("BADLIB", bytes(bad), latest, b.identity), [],
             catch_cmd("VL", "BADLIB"), -37, False),
            ("VERIFY-TEXT match", tapes.text_file("GOODTXT", store), [], catch_cmd("VT", "GOODTXT"), 0, True),
            ("VERIFY-TEXT one byte differs", tapes.text_file("BADTXT", bytes(bad_t)), [], catch_cmd("VT", "BADTXT"), -37, True),
            ("VERIFY-TEXT tape one byte short", tapes.text_file("SHORTTXT", store[:-1]), [], catch_cmd("VT", "SHORTTXT"),
             -37, True),
            ("VERIFY-TEXT tape one byte long", tapes.text_file("LONGTXT", store + b"\r"), [], catch_cmd("VT", "LONGTXT"),
             -37, True)]
    for label, items, extra_setup, cmd, expect, is_text in runs:
        s, _ = play(ctx, items, setup + extra_setup, cmd)
        try:
            before = s.snap()
            r = finish(s)
            v.check(r["idle"], "%s: no prompt" % label)
            after = s.snap()
            st = s.stack()
            code = st[0] if st else None
            chk_code(v, label, code, expect)
            if not is_text:
                chk_same(v, label + " (memory untouched but the CRC at HERE)", before, after, workspace=b.workspace,
                         skip=(before["here"], before["here"] + 1))
            else:
                # VERIFY-TEXT must not write: the dictionary is untouched, and the store still holds the typed lines
                # (the command line was trimmed, whatever the verdict; STORE_END is absent in an old build)
                chk_same(v, label + " (dictionary untouched)", before, after, workspace=b.workspace)
                if "STORE_END" in b.S:
                    end = s.rd16(b.S["STORE_END"])
                    v.check(end == b.workspace + len(store), "%s: store end %04X, expected %04X (the VERIFY-TEXT line must be trimmed)" % (
                        label, end, b.workspace + len(store)))
                    chk_bytes(v, label + " store", bytes(s.rd(b.workspace, len(store))), store)
            v.note("%s: code %s" % (label, code))
        finally:
            s.stop()
    return v


# ---- legacy twins (old build only, INFO): the defects of spec section 1 with V1 (type 0) tapes, which an old build loads
def legacy_run(ctx, items, label, image=None, max_wall=60):
    v = Verdict()
    s, _ = play(ctx, items, [LL_LINE], catch_cmd("LL", "LIBV1"), lead_s=lead_for(len(LL_LINE) + 21))
    try:
        before = s.snap()
        r = finish(s, max_wall=max_wall)
        after = s.snap()
        st = s.stack() if r["idle"] else []
        changed = sum(1 for x, y in zip(before["ram"], after["ram"]) if x != y)
        txt = "%s: prompt back %s after %.1f s emulated; THROW code %s; HERE %04X -> %04X, LATEST %04X -> %04X; %d dictionary " \
              "RAM bytes changed" % (label, r["idle"], r["emu_s"], st[0] if st else None, before["here"], after["here"],
                                     before["latest"], after["latest"], changed)
        if image is not None:
            txt += "; the %d image bytes are at $9800: %s" % (len(image), after["ram"][:len(image)] == image)
        if not r["idle"]:
            txt += "; screen %s" % s.screen()[-3:]
        v.note(txt)
    finally:
        s.stop()
    return v


def v1_blocks(d, latest, length=None, flag=0xFF):
    body = struct.pack("<H", latest) + d
    ln = len(body) if length is None else length
    return [tapes.framed(0x00, tapes.header_payload(0, "LIBV1", ln, 0x8000, ln)), tapes.framed(flag, body)]


def legacy_7(ctx):
    d, latest = v1_image(ctx)
    bad = bytearray(d)
    bad[len(d) - 50] ^= 0x04
    return legacy_run(ctx, v1_blocks(bytes(bad), latest), "V1 image, one byte altered, XOR fixed up", image=bytes(bad))


def legacy_8(ctx):
    items = [tapes.framed(0x00, tapes.header_payload(0, "LIBV1", 1, 0x8000, 1)), tapes.framed(0xFF, b"\x5A")]
    return legacy_run(ctx, items, "V1 header length 1")


def legacy_8z(ctx):
    items = [tapes.framed(0x00, tapes.header_payload(0, "LIBV1", 0, 0x8000, 0)), tapes.framed(0xFF, b"")]
    return legacy_run(ctx, items, "V1 header length 0")


def legacy_9(ctx):
    d, latest = v1_image(ctx)
    return legacy_run(ctx, v1_blocks(d, latest, flag=0x55), "V1 image, data block flag $55", image=d)


def legacy_10(ctx):
    d, latest = v1_image(ctx)
    hdr, data = v1_blocks(d, latest)
    t = tapes.Tape().block(data, dropout=(40, 2), gap=0)
    return legacy_run(ctx, [hdr, ("pulses", t.pulses()), ("pause", 1000)], "V1 image, 2-byte dropout in the data block", image=d)


CASES = {
    "1": ("text_doubler", case_1, "pass"),
    "2": ("blackjack_p53", case_2, "pass"),
    "3": ("savetext_roundtrip", case_3, "header param 1 differs"),
    "N4": ("text_tape_roundtrip", case_n4, "passes (42 only: CR is part of a word, the text is built for that)"),
    "4": ("savelib_roundtrip", case_4, "fails the format checks; round trip passes"),
    "5": ("foreign_identity", case_5, "n/a (loads as nothing; type 3 skipped)"),
    "6": ("v1_lib_tape", case_6, "loads"),
    "7": ("crc_mismatch", case_7, "loads the corrupt image"),
    "8": ("header_length_0_1", case_8, "RAM corrupted / hang"),
    "9": ("wrong_flag", case_9, "reports success"),
    "10": ("dropout", case_10, "reports success"),
    "11": ("space_in_search", case_11, "returns silently, no error"),
    "11a": ("no_tape", case_11a, "silent, after 136.8 s"),
    "12": ("space_in_save", case_12, "header + data captured"),
    "13": ("two_headers", case_13, "pass"),
    "14": ("verify", case_14, "n/a"),
    "15": ("savelib_large_wildcard", case_15, "n/a"),
    "11L": ("space_in_search_loadlib", case_11l, "(extra) wildcard LOAD-LIB + SPACE: phantom header, length 0"),
    "7L": ("legacy_crc", legacy_7, "loads the corrupt image"),
    "8L": ("legacy_len1", legacy_8, "RAM corrupted / hang"),
    "8Z": ("legacy_len0", legacy_8z, "RAM corrupted / hang"),
    "9L": ("legacy_wrong_flag", legacy_9, "reports success"),
    "10L": ("legacy_dropout", legacy_10, "reports success"),
}
ORDER = ["1", "2", "3", "N4", "4", "15", "5", "6", "7", "8", "9", "10", "11", "11a", "12", "13", "14"]
EXTRA = ["11L"]                             # judged like the cases, tallied apart
LEGACY = ["7L", "8L", "8Z", "9L", "10L"]    # old build only (no ROM_IDENTITY): INFO lines, not judged


# ----------------------------------------------------------------------------------------------- run
def run_case(cid, build, port, work):
    name, fn, _ = CASES[cid]
    ctx = Ctx(build, port, work)
    for attempt in range(3):
        try:
            t0 = time.time()
            v = fn(ctx)
            return dict(id=cid, name=name, status="FAIL" if v.fails else "PASS", reason="; ".join(v.fails)[:400],
                        obs=v.obs, wall=time.time() - t0, attempts=attempt + 1)
        except HarnessRetry as e:
            last = "retry: " + str(e)
            ctx.scale *= e.lead_scale
        except Exception as e:                                  # noqa: BLE001 - reported as a harness failure
            import traceback
            return dict(id=cid, name=name, status="FAIL", reason="harness error: %s: %s" % (type(e).__name__, e),
                        obs=[traceback.format_exc().splitlines()[-3]], wall=0, attempts=attempt + 1)
    return dict(id=cid, name=name, status="FAIL", reason="harness error: " + last, obs=[], wall=0, attempts=3)


def worker_main(a):
    import faulthandler
    import signal
    faulthandler.register(signal.SIGUSR1, all_threads=True)     # kill -USR1 <pid>: where is the worker?
    b = Build(a.build)
    res = run_case(a.case[0], b, a.port, a.workdir)
    print("RESULT " + json.dumps(res))


def spawn(cid, a, port, work):
    cmd = [sys.executable, "-I", os.path.abspath(__file__), "--build", a.build, "--case", cid, "--port", str(port),
           "--workdir", work, "--worker"]
    outp = "%s/worker_%s.out" % (work, cid)
    with open(outp, "w") as f:                      # a file, not a pipe: the emulator child must not hold a pipe open
        subprocess.run(cmd, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, timeout=3600)
    txt = open(outp, errors="replace").read()
    for line in txt.splitlines():
        if line.startswith("RESULT "):
            return json.loads(line[7:])
    return dict(id=cid, name=CASES[cid][0], status="FAIL", reason="harness error: worker died: " +
                txt[-300:].replace("\n", " "), obs=[], wall=0, attempts=1)


def run_all(a):
    b = Build(a.build)
    ids = a.case or (ORDER + EXTRA + ([] if b.has_identity else LEGACY))
    for c in ids:
        if c not in CASES:
            raise HarnessError("unknown case %s (have %s)" % (c, ", ".join(ORDER)))
    work = tempfile.mkdtemp(prefix="tapetest.")
    t0 = time.time()
    results = {}
    try:
        jobs = max(1, min(a.jobs, PORT_HI - a.port + 1, len(ids)))
        with concurrent.futures.ThreadPoolExecutor(jobs) as ex:
            ports = list(range(a.port, a.port + jobs))
            futs, free = {}, list(ports)
            pending = list(ids)
            while pending or futs:
                while pending and free:
                    c, p = pending.pop(0), free.pop(0)
                    futs[ex.submit(spawn, c, a, p, work)] = (c, p)
                done, _ = concurrent.futures.wait(futs, return_when=concurrent.futures.FIRST_COMPLETED)
                for f in done:
                    c, p = futs.pop(f)
                    results[c] = f.result()
                    free.append(p)
                    print("  [%s done in %.0f s]" % (c, results[c]["wall"]), file=sys.stderr)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    lines = ["tapetest: build %s (ROM_IDENTITY %s)" % (b.dir, "$%04X" % b.identity if b.has_identity else "absent, $0000 used")]
    for c in ids:
        r = results[c]
        status = "INFO" if c in LEGACY else r["status"]
        lines.append("case %s %s: %s%s" % (c, r["name"], status, (" " + r["reason"]) if r["reason"] else ""))
        for o in r["obs"]:
            lines.append("    obs: " + o)
        if not b.has_identity:
            lines.append("    old-build table: " + CASES[c][2])
    main_ids = [c for c in ids if c not in EXTRA and c not in LEGACY]
    extra_ids = [c for c in ids if c in EXTRA]
    npass = sum(1 for c in main_ids if results[c]["status"] == "PASS")
    nfail = len(main_ids) - npass
    lines.append("TAPETEST: PASS %d FAIL %d" % (npass, nfail))
    if extra_ids:
        xp = sum(1 for c in extra_ids if results[c]["status"] == "PASS")
        lines.append("extras (not in the tally): PASS %d FAIL %d" % (xp, len(extra_ids) - xp))
    lines.append("wall %.0f s" % (time.time() - t0))
    out = "\n".join(lines)
    print(out)
    if a.out:
        open(a.out, "w").write(out + "\n")
    return 1 if nfail else 0


# ----------------------------------------------------------------------------------------------- selftest
def selftest(a):
    """One passing-path run (SAVE-TEXT capture, a CATCH of a real THROW, a dictionary read), then each judged again with
    one corrupted input, which must be reported as FAIL."""
    b = Build(a.build)
    work = tempfile.mkdtemp(prefix="tapetest.self.")
    ctx = Ctx(b, a.port, work)
    ok = True
    try:
        text = b": TT -37 THROW ;\r"            # the one typed line, + CR: the store (the SAVE-TEXT line is trimmed)
        s = ctx.session(capture=True).start()
        try:
            s.wait_idle()
            if s.line(": TT -37 THROW ;"):
                raise HarnessError("setup failed")
            before = s.snap()
            s.arm_capture()
            s.type_text("SAVE-TEXT STX")
            s.press_enter()
            idle, _ = s.poll_idle(120)
            s.disarm_capture()
            vals = s.captured()
            blks = tapes.decode(tapes.edges_from_capture(vals))
            if s.line(catch_cmd("TT")):
                raise HarnessError("CATCH of TT raised an error")
            st = s.stack()
            after = s.snap()
        finally:
            s.stop()
        code = st[0] if st else None
        print("selftest run: %d blocks captured, CATCH of -37 THROW left %s, dictionary %d B" %
              (len(blks), st, before["here"] - b.dict0))

        def judge(blks_, after_, code_, want_code):
            v = Verdict()
            v.check(len(blks_) == 2, "blocks %d" % len(blks_))
            if len(blks_) == 2:
                chk_bytes(v, "decoded payload", tapes.unframe(blks_[1]["data"])[1], text)
            chk_same(v, "dictionary", before, after_, whole=False)
            chk_code(v, "THROW", code_, want_code)
            return v

        base = judge(blks, after, code, -37)
        print("unmutated: %s %s" % ("PASS" if not base.fails else "FAIL", "; ".join(base.fails)))
        ok = ok and not base.fails
        import copy
        b_a = copy.deepcopy(blks)
        d = bytearray(b_a[1]["data"])
        d[2] ^= 0x01
        b_a[1]["data"] = bytes(d)
        a_b = dict(after, ram=bytearray(after["ram"]))
        a_b["ram"][3] ^= 0x01       # (below HERE: the compared part)
        a_b["ram"] = bytes(a_b["ram"])
        for label, v in (("(a) one decoded byte corrupted", judge(b_a, after, code, -37)),
                         ("(b) one compared dictionary byte corrupted", judge(blks, a_b, code, -37)),
                         ("(c) expected THROW code corrupted (-36)", judge(blks, after, code, -36))):
            rep = bool(v.fails)
            print("%s: %s -> %s" % (label, "reported as FAIL" if rep else "NOT REPORTED", "; ".join(v.fails)))
            ok = ok and rep
    finally:
        shutil.rmtree(work, ignore_errors=True)
    print("TAPETEST SELFTEST: %s" % ("ok" if ok else "FAILED"))
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", help="directory with forth_boot_rom0.bin, graphics_exrom.bin, forth_boot.sym")
    ap.add_argument("--case", action="append", help="case id (repeatable): 1-14, 11a; default all")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--out", help="also write the report to this file")
    ap.add_argument("--jobs", type=int, default=4, help="cases in parallel (ports PORT..PORT+jobs-1)")
    ap.add_argument("--port", type=int, default=PORT_LO)
    ap.add_argument("--workdir", help=argparse.SUPPRESS)
    ap.add_argument("--worker", action="store_true", help=argparse.SUPPRESS)
    a = ap.parse_args()
    if not a.build:
        ap.error("--build is required")
    try:
        if a.worker:
            worker_main(a)
            return 0
        if a.selftest:
            return selftest(a)
        return run_all(a)
    except HarnessError as e:
        print("tapetest: harness error: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
