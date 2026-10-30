#!/usr/bin/env python3
"""Power-on RAM qualification for the Forth boot ROM (idea ported from 2068-Leap-C's
tools/poweron.py; it does not use Leap-C's Machine class, it drives the `ts2068-debug` CLI the way
tools/run_rom_tests.sh does).

A real TS2068 powers on with whatever its DRAM holds (and its reset button keeps the RAM); the
Z80 reset leaves AF BC DE HL IX IY SP and the shadow set undefined (the chip only guarantees
PC, I, R, IFF and IM).  Every other test boots ZEsarUX from zeroed RAM.  Here the machine boots
build/forth_boot_rom0.bin from a PATTERN written over $4000-$FFFF and over those registers,
written AFTER `reset-cpu` (which keeps ZEsarUX's RAM and BC/DE/HL/IX/IY/shadow registers, and
sets only PC=0, SP=$FFFF, AF=$FFFF, IM0, IFF off: measured in step G) and
before the first instruction runs.  Patterns:

  zero      all $00 (RAM and registers): the reference
  ones      all $FF
  alt       $55,$AA alternating (registers $55AA)
  addr      each byte = low byte of its address (a stale pointer reads as plausible data)
  random:N  N=1..4: bytes and registers from python random.Random(N), reproducible from N

The boot runs, in bounded chunks of opcodes (`run --until EDITOR_LOOP_LIVE.keyloop
--max-instructions CHUNK`, like the runner's chunked `run`), until PC reaches
EDITOR_LOOP_LIVE.keyloop, the idle prompt waiting for a key, or the opcode cap is spent
(TIMEOUT, exit 2).  Then $4000-$FFFF is dumped and compared with the zero pattern's dump.
T-states from reset to the prompt (ZRCP get-tstates-partial, reset just before the run) and SP
are recorded and shown; they are NOT asserted on (the startup chime waits on interrupt frames),
except that the zero pattern is booted a second time at the end and must reproduce the first
boot exactly (dump, SP, T-states): otherwise the harness is not deterministic and a pattern
difference cannot be trusted (exit 2).

WHAT FORTH DEFINES AND WHAT IT LEAVES UNDEFINED (DEFINED-REGIONS table, UNDEFINED_REGIONS
below).  The ROM "defines" a byte at the idle prompt if its cold start (rom/forth_boot.asm
COLD_START) writes it, or the editor writes it before the prompt: a byte whose value after the
boot depends on the power-on pattern is a bug (a program or the user can read it back, e.g.
UDG_TABLE is read by the UDG words and the graphics print routine without any initialisation).
COLD_START: SP=$FF00, IX=DSTACK_TOP ($9800), IY=FSTACK_TOP ($9000); zeroes $8000..
DICT_RAM_CEILING with MEM_FILL_ZERO (the dictionary, both Forth stacks, the workspace and most
cells in that range); GFX_CLS clears the bitmap and attributes ($4000-$5AFF); a handful of
cells are stored one by one (LATEST, WORKSPACE_END, HERE, STATE, LEAVE_DEPTH, CATCH_DEPTH,
CURRENT_ATTR, FWRAP_OLD_COUNT, PRINT_COL, PRINT_ROW); the editor and ISR init write theirs.
Everything NOT in UNDEFINED_REGIONS is classified DEFINED, so a difference there is a FAIL. The table
lists only regions with a recorded reason (checked by grep of core/ kernel/ rom/forth_boot.asm
rom/graphics_exrom.asm include/, step G, 2026-10-28):
  * the machine stack below the live SP ($F600..SP-1): a stack is written before it is read, and what is
    left below SP is the leftover of the boot's calls and PUSHes, including pushes of the (scrambled)
    registers.  The live stack (SP..$FEFF) is DEFINED.  $F600 is EXTENSION_MODULE_LIMIT, "genuine stack
    headroom starts at $F600" (the old include/sysvars.inc; the layout's lowest stack byte is MACHINE_STACK_LIMIT,
    $F3C8, in include/forth_layout.inc);
  * $FF00-$FFFF: above the initial SP, nothing allocates there (include/forth_layout.inc: MACHINE_STACK_TOP is $FF00);
  * $5B00-$7FFF: GFX_FILL_SHADOW / GFX_FILL_STACK (FILL_IMPL fills the first from the screen and sets its stack
    pointer on entry, rom/graphics_exrom.asm), display file 2 at $6000 (displayed only in HIRES, which
    clears it on entry: kernel/graphics .clear_highres) and ZX_SYSVAR_CHARS $5C36 (only
    written, core/printer.asm);
  * $F000-$F17F: no Forth symbol ($F000-$F0FF) and LABEL_TABLE ($F100-$F17F, BASIC labels): no reader;
  * $F228-$F3C3 and $F400-$F5FF: EDIT_LINE_BUF, DETOK_BUF, STR_FUNC_POOL, DEF_FN / extension state and the
    extension module window: free in include/forth_layout.inc (the old names are gone), no reader in the Forth sources;
  * $F3C4-$F3FF: GFX_LINE_X0..Y1 / ATTR / OVER, which the LINE word (core/ts2068.asm) and the EXROM's
    sprite code (rom/graphics_exrom.asm) set before every GFX_LINE call.
NOT in the table, so they must come out identical to the zero boot: the bitmap and attributes
($4000-$5AFF), everything COLD_START clears ($8000-DICT_RAM_CEILING) and UDG_TABLE ($F180-$F227, read by
W_UDG and the glyph lookup: audit O1).  A region added to the table needs the same kind of grep evidence;
the script never whitelists silently, and every differing range is always printed, with its symbol and
classification, in both modes (--report-only just exits 0).
Usage: tools/poweron.py [--report-only] [--json] [--pattern NAME]... [--port N]
       [--by-symbol] [--no-repeat] [--dump-dir DIR] [--chunk N] [--max-instr N]
Exit: 0 all patterns match (or --report-only), 1 a DEFINED region differs under some pattern,
2 harness error (ts2068-debug or a build file missing, boot timeout, session failure,
non-deterministic zero boot).
Ports: only --port N in 10820-10839 (default 10820); a private TS2068_DEBUG_STATE_DIR (mktemp)
per run, the ZEsarUX is stopped on exit, on exceptions and on SIGINT/SIGTERM.
"""
import argparse
import atexit
import json
import os
import random
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BUILD = os.path.join(ROOT, "build")
ROM0 = os.path.join(BUILD, "forth_boot_rom0.bin")
EXROM = os.path.join(BUILD, "graphics_exrom.bin")
SYM = os.path.join(BUILD, "forth_boot.sym")
TARGET = "EDITOR_LOOP_LIVE.keyloop"

PORT_LO, PORT_HI = 10820, 10839
RAM_BASE, RAM_SIZE = 0x4000, 0xC000
PATTERNS = ("zero", "ones", "alt", "addr", "random:1", "random:2", "random:3", "random:4")
FREE_REGS = ("AF", "BC", "DE", "HL", "IX", "IY", "SP", "AF'", "BC'", "DE'", "HL'")
# EQUs in the .sym file that are numbers, not addresses (core/beep.asm's clock constant); PORT_* are I/O port numbers.  Excluded from the address -> symbol map.
NOT_ADDRESS = {"CPU_CLOCK_M"}
CHUNK = 500000          # opcodes per `run`, as tools/run_rom_tests.sh
MAX_INSTR = 20000000    # generous opcode cap for the boot (the boot takes well under 1M)

# (name, lo, hi_exclusive, reason): bytes whose value after the boot may legitimately depend on
# the power-on pattern.  Anything not listed is DEFINED.  "SP" in a bound means the live SP.
UNDEFINED_REGIONS = [
    ("stack below live SP", 0xF600, "SP",
     "machine stack: written (CALL/PUSH) before read; leftovers of the boot's calls and pushes"),
    ("above initial SP", 0xFF00, 0x10000,
     "above COLD_START's SP=$FF00; nothing allocates here (include/forth_layout.inc: MACHINE_STACK_TOP is $FF00)"),
    ("GFX_FILL scratch, display file 2, ZX sysvar", 0x5B00, 0x8000,
     "FILL clears its visited map and resets its stack on entry; HIRES clears display file 2 on "
     "entry; $5C36 is write-only"),
    ("unreferenced / BASIC label table", 0xF000, 0xF180,
     "no Forth symbol at $F000-$F0FF; LABEL_TABLE has no reader in the Forth sources"),
    ("Leap leftovers (edit/detok/string/ext cells)", 0xF228, 0xF3C4,
     "free in include/forth_layout.inc; no reader in core/ kernel/ rom/"),
    ("GFX_LINE cells", 0xF3C4, 0xF400,
     "set by LINE (core/ts2068.asm) and the EXROM's sprite code before every GFX_LINE call"),
    ("extension module window", 0xF400, 0xF600,
     "free in include/forth_layout.inc; no reader in core/ kernel/ rom/"),
]


class HarnessError(Exception):
    """tool/harness problem (exit 2), as opposed to a pattern difference (exit 1)."""


# ---------------------------------------------------------------------------- ts2068-debug
class Session:
    """One ZEsarUX under a private state dir, driven through the `ts2068-debug --json` CLI."""

    def __init__(self, port):
        self.port = port
        self.state = tempfile.mkdtemp(prefix="poweron.")
        self.env = dict(os.environ, TS2068_DEBUG_STATE_DIR=self.state)
        self.started = False

    def cli(self, *args, timeout=300):
        try:
            p = subprocess.run(["ts2068-debug", "--json", *args], env=self.env, capture_output=True,
                               text=True, timeout=timeout)
        except FileNotFoundError:
            raise HarnessError("ts2068-debug not found in PATH")
        except subprocess.TimeoutExpired:
            raise HarnessError("ts2068-debug %s timed out" % " ".join(args[:2]))
        try:
            d = json.loads(p.stdout.strip().splitlines()[-1])
        except (ValueError, IndexError):
            raise HarnessError("ts2068-debug %s: unparsable output %r %r" % (args[0], p.stdout[-200:], p.stderr[-200:]))
        if d.get("status") != "ok":
            raise HarnessError("ts2068-debug %s: %s" % (" ".join(args[:2]), d.get("error", d)))
        return d

    def start(self, rom0, exrom, sym):
        img = os.path.join(self.state, "forth_boot_zesarux.bin")    # ZEsarUX wants ONE image
        with open(img, "wb") as f:
            for part in (rom0, exrom):
                f.write(part)
        self.started = True   # from here on stop() must run, even if start fails half way
        self.cli("start", "--rom", img, "--symbols", sym, "--port", str(self.port))

    def stop(self):
        if not self.started and not os.path.isdir(self.state):
            return
        for extra in ((), ("--port", str(self.port))):
            try:
                subprocess.run(["ts2068-debug", "--json", "stop", *extra], env=self.env,
                               capture_output=True, timeout=30)
            except Exception:
                pass
        self.started = False
        shutil.rmtree(self.state, ignore_errors=True)

    # -- operations
    def reset(self):
        d = self.cli("reset-known-state")        # pause first, then reset-cpu
        if d["registers"]["PC"] != 0:
            raise HarnessError("reset-cpu did not give PC=0000 (PC=%04X)" % d["registers"]["PC"])
        return d

    def regs(self):
        return self.cli("regs")["registers"]

    def setreg(self, name, value):
        self.cli("set-register", name, "0x%04X" % value)

    def write(self, addr, data):
        self.cli("mem-write", "0x%04X" % addr, data.hex())

    def read(self, addr, n):
        h = self.cli("mem", "0x%04X" % addr, str(n))["hex"]
        data = bytes.fromhex(h)
        if len(data) != n:
            raise HarnessError("read of %d bytes at %04X returned %d" % (n, addr, len(data)))
        return data

    def zrcp(self, *cmds):
        """Raw ZRCP (the CLI has no get-tstates): returns the replies, or None if the module
        cannot be imported/connected (T-states are then simply not reported)."""
        try:
            from ts2068_debug.zrcp import ZRCPClient
            c = ZRCPClient(port=self.port, timeout=10.0)
            c.connect(retries=5)
            try:
                return [c.command(x) for x in cmds]
            finally:
                c.close()
        except Exception:
            return None


# ---------------------------------------------------------------------------- patterns
def pattern(name):
    """-> (48 K of RAM bytes, {register: value}) for pattern `name`."""
    n = len(FREE_REGS)
    if name == "zero":
        return bytes(RAM_SIZE), {r: 0 for r in FREE_REGS}
    if name == "ones":
        return b"\xff" * RAM_SIZE, {r: 0xFFFF for r in FREE_REGS}
    if name == "alt":
        return b"\x55\xaa" * (RAM_SIZE // 2), {r: 0x55AA for r in FREE_REGS}
    if name == "addr":
        return (bytes(a & 0xFF for a in range(RAM_BASE, RAM_BASE + RAM_SIZE)),
                {r: 0x4000 + 0x0111 * i for i, r in enumerate(FREE_REGS)})
    if name.startswith("random:"):
        rng = random.Random(int(name.split(":", 1)[1]))
        data = bytes(rng.getrandbits(8) for _ in range(RAM_SIZE))   # not randbytes: python < 3.9 ok
        return data, {r: rng.randrange(0x10000) for r in FREE_REGS}
    raise HarnessError("unknown pattern %r (one of %s)" % (name, ", ".join(PATTERNS)))


# ---------------------------------------------------------------------------- symbols
def load_symbols(path):
    """build/forth_boot.sym lines `NAME: EQU 0x0000XXXX` -> (sorted [(addr, name)], {name: addr})."""
    by_name, rows = {}, []
    rx = re.compile(r"^(\S+):\s+EQU\s+0x([0-9A-Fa-f]+)")
    with open(path) as f:
        for line in f:
            m = rx.match(line)
            if m:
                a = int(m.group(2), 16)
                by_name[m.group(1)] = a
                if RAM_BASE <= a < 0x10000 and m.group(1) not in NOT_ADDRESS and not m.group(1).startswith("PORT_"):
                    rows.append((a, m.group(1)))
    rows.sort(key=lambda r: (r[0], "." in r[1], len(r[1]), r[1]))
    return rows, by_name


class SymMap:
    def __init__(self, rows):
        self.rows = rows
        self.addrs = [a for a, _ in rows]

    def at(self, addr):
        """'NAME' or 'NAME+off': the nearest symbol at or below addr (non-local names first)."""
        import bisect
        i = bisect.bisect_right(self.addrs, addr) - 1
        if i < 0:
            return "?"
        while i > 0 and self.rows[i - 1][0] == self.rows[i][0]:
            i -= 1                      # several names at one address: the first (non-local, shortest)
        a, name = self.rows[i]
        return name if a == addr else "%s+%d" % (name, addr - a)

    def within(self, lo, hi, limit=6):
        """names of symbols whose address lies in [lo, hi)."""
        import bisect
        i = bisect.bisect_left(self.addrs, lo)
        out = []
        while i < len(self.rows) and self.addrs[i] < hi:
            out.append(self.rows[i][1])
            i += 1
        return out if len(out) <= limit else out[:limit] + ["...(%d more)" % (len(out) - limit)]


# ---------------------------------------------------------------------------- classification
def undefined_map(sp):
    """[(lo, hi, name)] for this boot's SP."""
    out = []
    for name, lo, hi, _ in UNDEFINED_REGIONS:
        hi = sp if hi == "SP" else hi
        if hi > lo:
            out.append((lo, hi, name))
    return out


def diff_ranges(ref, got, base):
    """[(lo, hi_exclusive)] where two equal-length byte strings differ."""
    out, start = [], None
    for i in range(len(ref) + 1):
        d = i < len(ref) and ref[i] != got[i]
        if d and start is None:
            start = i
        elif not d and start is not None:
            out.append((base + start, base + i))
            start = None
    return out


def split_classified(ranges, sp, extra_cuts=()):
    """split each differing range at undefined-region boundaries (and at extra_cuts, e.g. every
    symbol address with --by-symbol): [(lo, hi, 'DEFINED'|'UNDEFINED', region)]."""
    um = undefined_map(sp)
    cuts = sorted({b for lo, hi, _ in um for b in (lo, hi)} | set(extra_cuts))
    out = []
    for lo, hi in ranges:
        pts = [lo] + [c for c in cuts if lo < c < hi] + [hi]
        for a, b in zip(pts, pts[1:]):
            reg = next((n for ulo, uhi, n in um if ulo <= a < uhi), None)
            out.append((a, b, "UNDEFINED" if reg else "DEFINED", reg or ""))
    return out


# ---------------------------------------------------------------------------- one boot
def boot(sess, name, target, chunk, max_instr):
    """reset, write pattern `name`, run to the idle prompt. Returns dict(reached, ...)."""
    sess.reset()
    data, regs = pattern(name)
    # written AFTER reset-cpu, before any instruction runs
    for off in range(0, RAM_SIZE, 0x4000):
        sess.write(RAM_BASE + off, data[off:off + 0x4000])
    for r in FREE_REGS:
        sess.setreg(r, regs[r])
    back = b"".join(sess.read(RAM_BASE + off, 0x4000) for off in range(0, RAM_SIZE, 0x4000))
    if back != data:
        raise HarnessError("pattern %s: RAM readback after the write differs (%d bytes)" %
                           (name, sum(a != b for a, b in zip(back, data))))
    r0 = sess.regs()
    for r in FREE_REGS:
        if r0[r] != regs[r]:
            raise HarnessError("pattern %s: register %s reads %04X after set to %04X" % (name, r, r0[r], regs[r]))
    if r0["PC"] != 0:
        raise HarnessError("pattern %s: PC=%04X before the run" % (name, r0["PC"]))
    sess.zrcp("reset-tstates-partial")
    done, r = 0, r0
    while done < max_instr:
        d = sess.cli("run", "--until", TARGET, "--max-instructions", str(chunk), timeout=600)
        done += chunk
        r = d["registers"]
        if r["PC"] == target:
            break
    reached = r["PC"] == target
    ts = sess.zrcp("get-tstates-partial")
    out = dict(pattern=name, reached=reached, pc=r["PC"], sp=r["SP"], regs=r, opcode_cap_used=done,
               tstates=int(ts[0]) if ts and ts[0].strip().isdigit() else None)
    if reached:
        out["dump"] = b"".join(sess.read(RAM_BASE + off, 0x1000) for off in range(0, RAM_SIZE, 0x1000))
    return out


def check_reset_keeps_ram(sess):
    """marker test: does reset-cpu keep RAM and BC (it must, for the patterns to be written after it)?"""
    marker = bytes(range(256))
    sess.reset()
    sess.write(0x8000, marker)
    sess.setreg("BC", 0xBEEF)
    sess.setreg("IX", 0x1357)
    d = sess.reset()["registers"]
    return dict(ram_kept=sess.read(0x8000, 256) == marker, bc_kept=d["BC"] == 0xBEEF, ix_kept=d["IX"] == 0x1357,
                pc=d["PC"], sp=d["SP"], af=d["AF"], im=d["IM"])


# ---------------------------------------------------------------------------- main
def fmt_range(lo, hi):
    return "$%04X-$%04X" % (lo, hi - 1) if hi - lo > 1 else "$%04X" % lo


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pattern", action="append", help="one pattern (repeatable); default all of: " + ", ".join(PATTERNS))
    ap.add_argument("--report-only", action="store_true", help="print every differing range, exit 0")
    ap.add_argument("--json", action="store_true", help="one JSON document on stdout instead of text")
    ap.add_argument("--port", type=int, default=PORT_LO, help="ZRCP port, %d-%d (default %d)" % (PORT_LO, PORT_HI, PORT_LO))
    ap.add_argument("--dump-dir", help="write each pattern's $4000-$FFFF dump here as <pattern>.bin")
    ap.add_argument("--chunk", type=int, default=CHUNK, help="opcodes per run (default %d)" % CHUNK)
    ap.add_argument("--max-instr", type=int, default=MAX_INSTR, help="opcode cap to reach the prompt (default %d)" % MAX_INSTR)
    ap.add_argument("--by-symbol", action="store_true", help="also split every differing range at each symbol's address (triage view)")
    ap.add_argument("--no-repeat", action="store_true", help="skip the final second zero boot (determinism check)")
    a = ap.parse_args()

    names = a.pattern or [p for p in PATTERNS]
    out = dict(patterns={}, errors=[])
    log = (lambda *x: None) if a.json else (lambda *x: print(*x, flush=True))
    sess = None

    def finish(code):
        if a.json:
            print(json.dumps(out, indent=1))
        return code

    try:
        if not PORT_LO <= a.port <= PORT_HI:
            raise HarnessError("--port must be in %d-%d" % (PORT_LO, PORT_HI))
        if shutil.which("ts2068-debug") is None:
            raise HarnessError("ts2068-debug not found in PATH")
        for p in names:
            if p != "zero" and p not in PATTERNS and not re.fullmatch(r"random:\d+", p):
                raise HarnessError("unknown pattern %r" % p)
        for f in (ROM0, SYM):
            if not os.path.isfile(f):
                raise HarnessError("%s not built (run make)" % os.path.relpath(f, ROOT))
        rows, by_name = load_symbols(SYM)
        if TARGET not in by_name:
            raise HarnessError("%s not in %s" % (TARGET, SYM))
        target = by_name[TARGET]
        smap = SymMap(rows)
        with open(ROM0, "rb") as f:
            rom0 = f.read()
        exrom = open(EXROM, "rb").read()
        if len(rom0) != 0x4000 or len(exrom) != 0x2000:
            raise HarnessError("ROM0 must be 16384 bytes and the EXROM 8192")

        sess = Session(a.port)
        atexit.register(sess.stop)
        def _sig(signum, frame):
            raise HarnessError("interrupted by signal %d" % signum)
        signal.signal(signal.SIGINT, _sig)
        signal.signal(signal.SIGTERM, _sig)

        t0 = time.time()
        sess.start(rom0, exrom, SYM)
        out["reset_cpu"] = rk = check_reset_keeps_ram(sess)
        log("reset-cpu: RAM kept=%s, BC kept=%s, IX kept=%s; after it PC=%04X SP=%04X AF=%04X IM%d" %
            (rk["ram_kept"], rk["bc_kept"], rk["ix_kept"], rk["pc"], rk["sp"], rk["af"], rk["im"]))

        # the reference first (the diff base), the others after it; the zero boot is repeated at the end
        todo = ["zero"] + [n for n in names if n != "zero"]
        boots = {}
        for n in todo:
            b = boots[n] = boot(sess, n, target, a.chunk, a.max_instr)
            if not b["reached"]:
                raise HarnessError("TIMEOUT: %s boot did not reach %s ($%04X) in %d opcodes (PC=%04X)" %
                                   (n, TARGET, target, b["opcode_cap_used"], b["pc"]))
            log("boot %-9s reached %s: SP=%04X T-states=%s" % (n, TARGET, b["sp"], b["tstates"]))
            if a.dump_dir:
                os.makedirs(a.dump_dir, exist_ok=True)
                with open(os.path.join(a.dump_dir, n.replace(":", "_") + ".bin"), "wb") as f:
                    f.write(b["dump"])
        ref = boots["zero"]
        if not a.no_repeat:
            again = boot(sess, "zero", target, a.chunk, a.max_instr)
            if not again["reached"]:
                raise HarnessError("TIMEOUT: second zero boot did not reach %s" % TARGET)
            det = dict(dump=again["dump"] == ref["dump"], sp=again["sp"] == ref["sp"],
                       tstates=again["tstates"] == ref["tstates"], tstates_first=ref["tstates"],
                       tstates_second=again["tstates"])
            out["determinism"] = det
            log("zero booted twice: dump %s, SP %s, T-states %s (%s, %s)" % (
                *("identical" if det[k] else "DIFFERENT" for k in ("dump", "sp", "tstates")),
                det["tstates_first"], det["tstates_second"]))
            if not (det["dump"] and det["sp"]):
                raise HarnessError("non-deterministic: the zero boot differs from itself; results untrustworthy")

        total_pass = total_fail = 0
        bad_patterns = 0
        for n in todo:
            b = boots[n]
            ranges = diff_ranges(ref["dump"], b["dump"], RAM_BASE)
            classified = split_classified(ranges, ref["sp"], smap.addrs if a.by_symbol else ())   # zero boot's SP: the live-stack boundary
            rec = dict(sp=b["sp"], tstates=b["tstates"], sp_same_as_zero=b["sp"] == ref["sp"],
                       tstates_same_as_zero=b["tstates"] == ref["tstates"], diffs=[])
            for lo, hi, cls, reg in classified:
                rec["diffs"].append(dict(lo=lo, hi=hi - 1, bytes=hi - lo, symbol=smap.at(lo), end_symbol=smap.at(hi - 1),
                                         symbols_inside=smap.within(lo, hi), cls=cls, region=reg))
            nfail = sum(d["cls"] == "DEFINED" for d in rec["diffs"])
            nund = len(rec["diffs"]) - nfail
            rec["fail"], rec["undefined_diffs"] = nfail, nund
            out["patterns"][n] = rec
            if n == "zero":
                continue
            log("")
            log("== %s: SP %04X (zero %04X), T-states %s (zero %s): %d differing range(s), %d DEFINED, %d undefined" % (
                n, b["sp"], ref["sp"], b["tstates"], ref["tstates"], len(rec["diffs"]), nfail, nund))
            for d in rec["diffs"]:
                span = fmt_range(d["lo"], d["hi"] + 1)
                end = "" if d["symbol"] == d["end_symbol"] or d["bytes"] == 1 else " .. %s" % d["end_symbol"]
                inside = "" if len(d["symbols_inside"]) < 2 else "  [%s]" % ", ".join(d["symbols_inside"])
                log("  %-10s %-11s %5d B  %s%s%s%s" % (d["cls"], span, d["bytes"], d["symbol"], end, inside,
                                                      "  (" + d["region"] + ")" if d["region"] else ""))
            if b["sp"] != ref["sp"]:
                log("  note: SP differs from the zero boot")
            total_fail += nfail
            total_pass += 0 if nfail else 1
            bad_patterns += 1 if nfail else 0
            log("POWERON %s: PASS %d FAIL %d  (%d DEFINED range(s) differ, %d undefined-by-design)" % (
                n, 0 if nfail else 1, 1 if nfail else 0, nfail, nund))
        npat = len([n for n in todo if n != "zero"])
        out["summary"] = dict(patterns=npat, pass_=npat - bad_patterns, fail=bad_patterns, defined_ranges_differing=total_fail,
                              seconds=round(time.time() - t0, 1))
        log("")
        log("POWERON: PASS %d FAIL %d  (patterns; %d DEFINED range(s) differ; %.0f s)" % (
            npat - bad_patterns, bad_patterns, total_fail, time.time() - t0))
        if a.report_only:
            return finish(0)
        return finish(1 if bad_patterns else 0)
    except HarnessError as e:
        out["errors"].append(str(e))
        print("poweron: ERROR: %s" % e, file=sys.stderr)
        return finish(2)
    finally:
        if sess is not None:
            sess.stop()


if __name__ == "__main__":
    sys.exit(main())
