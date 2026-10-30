#!/usr/bin/env python3
"""Forth ZEsarUX test harness (persistent ZRCP session, symbol based, parallel workers).

Derived from 2068-Leap-C tools/lcharness.py and tools/run_tests.py at b918527; copied and adapted, not imported:
nothing here reads or writes ~/2068-Leap-C.  The same approach: one headless ZEsarUX per worker, a snapshot of the
booted machine restored before every case, routines called with SP = $FF00 and a return slot, the screen read
back with the ROM's own font rendered by the real GFX_PUTCHAR, memory compared byte for byte.  Audit item T11
(docs/V2/FORTH_V2_REUSE_AUDIT.md section 6.3); the base of the editor screen oracle (T12) and the float oracle (T13).

What is real: the assembled images (forth_boot_rom0.bin and graphics_exrom.bin, written as one 24 KB ROM file for
ZEsarUX's --romfile exactly as tools/tapetol.py does), cold start through the banner to the idle prompt's key wait
(IO_READ_KEY), the interrupt service (KBD_ISR_TICK scanning the keyboard matrix), banking, the editor and the
interpreter.  What is substituted: the machine is snapshotted at the first IO_READ_KEY and every case restores it
(RAM, registers and paging come back; the T-state phase within a frame is ZEsarUX's); Console.key() writes the
interrupt routine's latch (KBD_LASTK, KBD_KEYHIT) instead of pressing a key, test routines are called directly with
a return slot, and the glyph table is rendered by a small program written into RAM and removed again by the restore.
Console.press() is the one path that goes through the emulated keyboard matrix and the ISR's debounce.

The API (a library; `python3 -I tools/fharness.py --selftest` is its self-test):
  Machine(build, port, snapdir=None).start() / .stop()   boot, snapshot, glyph tables;  .restore()
  .sym(n) .xsym(n) .read .write .w16 .poke16 .setreg .regs .pc .run .run_to .call .tstates_reset .tstates
  .screen_rows(scr=None, nrows=24)                        the screen as text rows
  .expect_mem(where, data, what)  .ram_diff(before, after, base)
  .checkpoint(name) / .rollback(path)                     snapshot the live machine and put it back exactly (oracles)
  Console(machine)                                         key/type/press/wait/edit_line/rows (Forth's editor)
  run_pool(build, tasks, fn, workers=None, port0=10900)    one emulator per worker process; results in task order
`build` is a directory that holds forth_boot_rom0.bin (DIR or DIR/build, as tools/tapetol.py), so the images of an
older build in a git worktree work.  Symbols come from forth_boot.sym and, when the build has it, graphics_exrom.sym.

Ports: base 10900, allowed 10900-10919, 10840-10859, 10860-10879 and 10760-10779 (PORT_RANGES: this harness's own,
floattest's, shapetest's and tools/run_tests.py's; worker k uses base + k, all of a pool's ports in one range); other
harnesses own 10820-10839, 10880-10899 and 10960-10999.
A port outside the ranges, or one that something already listens on, is refused.  Needs ts2068-debug ($TS2068_DEBUG_DIR,
default ~/ts2068-debug; the ZRCP client and the process control), ZEsarUX 13.0 ($TS2068_DEBUG_ZESARUX_DIR, default
~/Applications/ZEsarUX-13.0) and sjasmplus (the glyph program).  ts2068-debug now acknowledges every segment at once
and starts ZEsarUX with --emulatorspeed 1000 --frameskip 49 itself; this file does both too (so an older ts2068-debug
behaves the same) and FORTH_REALTIME=1 runs at real speed.  Neither changes the emulated machine (T-states per
frame, interrupts), so every T-state figure is unchanged.

Memory the harness uses: $FF00 RET_SLOT, $FF02 STOP_ADDR, $FF10 GLYPH_PROG.  Forth's machine stack starts at
SP = $FF00 and grows down (rom/forth_boot.asm COLD_START `ld sp,$FF00`; include/forth_layout.inc asserts that
everything else it places ends at or below $FF00), so $FF00-$FFFF is not used by the ROM.  The restore puts them
back to the snapshot's contents.

EMULATOR LIMITS: there is no hardware here.  Every verdict is ZEsarUX's (its Z80, its ULA/SCLD and paging, its
keyboard matrix and its interrupt timing) running the ROM images; the screen is read from RAM, not from a display,
so a colour or timing effect that exists only on a real TV is not seen, and a real keyboard's contact bounce is not
simulated (Console.press holds a key until the ISR accepts it).  A pass says what the emulator did, not that real
hardware agrees.
"""
import argparse
import multiprocessing as mp
import os
import queue
import re
import shutil
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HOME = os.path.expanduser("~")
DEBUG_DIR = os.environ.get("TS2068_DEBUG_DIR", os.path.join(HOME, "ts2068-debug"))
ZESARUX = os.environ.get("TS2068_DEBUG_ZESARUX_DIR", os.path.join(HOME, "Applications", "ZEsarUX-13.0"))
sys.path.insert(0, DEBUG_DIR)
from ts2068_debug.zrcp import ZRCPClient, ZRCPError      # noqa: E402
from ts2068_debug.process import ZEsarUXProcess as _ZProcess, terminate_emulator  # noqa: E402

# ZEsarUX's own speed settings: --emulatorspeed shortens the real-time wait after each frame (10-1000 %) and
# --frameskip skips drawing frames; neither changes the emulated machine.  FORTH_REALTIME=1 runs at real speed.
FAST_ARGS = [] if os.environ.get("FORTH_REALTIME") else ["--emulatorspeed", "1000", "--frameskip", "49"]
PORT_LO, PORT_HI = 10900, 10919     # this harness's ports (run_tests 10760-10779, poweron 10820-10839,
                                    # ay_audio 10880-10899, tapetest 10960-10979, tapetol 10980-10999)
PORT_RANGES = ((10900, 10919), (10840, 10859), (10860, 10879), (10760, 10779))  # every range a Machine / run_pool accepts
                                    # (tools/floattest.py: the second; tools/shapetest.py: the third; tools/run_tests.py: the fourth)
RET_SLOT = 0xFF00                   # return address slot for routine calls (unused by the ROM: the header)
STOP_ADDR = 0xFF02                  # `jr $` written here; routine calls return to it
GLYPH_PROG = 0xFF10                 # the glyph rendering program and its code list
UNKNOWN = "░"                  # screen_rows: a cell that is no glyph
INVERSE_MARK = "\u2022"             # screen_rows: the next character is drawn inverse (every pixel flipped)
UDG_BASE = 0xE000                   # screen_rows: UDG code 144 + i reads as chr(UDG_BASE + i) (private use area)
UDG_CODE_BASE, UDG_COUNT = 144, 21  # kernel/graphics UDG_CODE_BASE; include/forth_layout.inc UDG_COUNT
Z_CAPS, Z_SYM, Z_SPACE, Z_ENTER = 135, 138, 128, 129    # ZEsarUX send-keys-event codes (letters and digits: their ASCII)
KEY_ENTER = 13                      # include/keys.inc
# Control codes that IO_DECODE_KEY makes from CAPS SHIFT + a key by code, not through a table (kernel/io/io.asm;
# values from include/keys.inc): code -> the ZEsarUX key events that produce it.
CTRL_KEYS = {0x01: [Z_CAPS, ord("5")],     # KEY_CURSOR_LEFT
             0x02: [Z_CAPS, ord("6")],     # KEY_CURSOR_DOWN
             0x03: [Z_CAPS, ord("7")],     # KEY_CURSOR_UP
             0x04: [Z_CAPS, ord("8")],     # KEY_CURSOR_RIGHT
             0x08: [Z_CAPS, ord("0")],     # KEY_DELETE
             0x0B: [Z_CAPS, Z_ENTER],      # KEY_INSERT_LINE
             0x0F: [Z_CAPS, ord("1")],     # KEY_DELETE_LINE
             0x10: [Z_CAPS, Z_SPACE]}      # KEY_BREAK


class HarnessError(Exception):
    pass


# ---------------------------------------------------------------------------------------------------- ZRCP, process
class _QuickAckSocket:
    """A socket that acknowledges every segment at once (TCP_QUICKACK, re-armed around each recv: Linux
    clears it).  ZEsarUX writes a reply and its prompt separately; with Nagle on its side and delayed
    ACKs on ours, the prompt waited for our ACK: 41 ms for every command with a reply, 0.04 ms with this.
    (Current ts2068-debug does this inside ZRCPClient; ZRCP below wraps only a client that does not.)"""

    def __init__(self, sock):
        self._s = sock

    def recv(self, n):
        self._quick()
        data = self._s.recv(n)
        self._quick()
        return data

    def _quick(self):
        if hasattr(socket, "TCP_QUICKACK"):
            try:
                self._s.setsockopt(socket.IPPROTO_TCP, socket.TCP_QUICKACK, 1)
            except OSError:
                pass

    def __getattr__(self, name):
        return getattr(self._s, name)


class ZRCP(ZRCPClient):
    """ts2068-debug's ZRCP client with the socket's delayed ACKs and Nagle off (_QuickAckSocket), if its own
    client lacks them (it has `_quickack` when it has them)."""

    def connect(self, *args, **kw):
        super().connect(*args, **kw)
        if not hasattr(self, "_quickack") and self._sock is not None and not isinstance(self._sock, _QuickAckSocket):
            self._sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self._sock = _QuickAckSocket(self._sock)


class ZEsarUXProcess(_ZProcess):
    """ts2068-debug's ZEsarUX launcher (the same arguments) with FAST_ARGS, whatever its own default is."""

    def start(self):
        args = ["./" + self.binary, "--noconfigfile", "--machine", self.machine, "--enable-remoteprotocol",
                "--remoteprotocol-port", str(self.port), "--vo", "null", "--ao", "null"] + FAST_ARGS
        if self.romfile:
            args += ["--romfile", os.path.abspath(self.romfile)]
        self._proc = subprocess.Popen(args, cwd=str(self.install_dir), stdout=subprocess.DEVNULL,
                                      stderr=subprocess.DEVNULL)


class InExrom(int):
    """A breakpoint address in the EXROM (Machine.xsym): it stops only while the EXROM is paged in.
    Chunk 5 ($A000-$BFFF) is the EXROM or dictionary RAM, so an EXROM label's address is also an address of
    the dictionary, where a plain PC breakpoint would fire while Forth runs there (BANK_EXROM_DEPTH
    is nonzero exactly while kernel/bank has the EXROM paged in)."""


# ---------------------------------------------------------------------------------------------------- files, symbols
def resolve_build(path):
    """The directory that holds forth_boot_rom0.bin (DIR or DIR/build)."""
    for d in (path, os.path.join(path, "build")):
        if os.path.isfile(os.path.join(d, "forth_boot_rom0.bin")):
            return os.path.abspath(d)
    raise FileNotFoundError("fharness: no forth_boot_rom0.bin in %s" % path)


def load_syms(*paths):
    out = {}
    for p in paths:
        for line in open(p):
            m = re.match(r"([A-Za-z_][A-Za-z0-9_.]*):\s+EQU\s+0x([0-9A-F]+)", line, re.I)
            if m:
                out.setdefault(m.group(1), int(m.group(2), 16))
    return out


def cell_from(scr, row, col):
    """The 8 bitmap bytes of character cell (row, col).  `scr` starts at $4000."""
    y0 = row * 8
    base = ((y0 & 0xC0) << 5) | ((y0 & 0x38) << 2) | (col & 31)
    return bytes(scr[base + 0x100 * k] for k in range(8))


def port_in_use(port):
    with socket.socket() as probe:                      # another emulator on the port would take the commands
        return probe.connect_ex(("127.0.0.1", port)) == 0


def port_range(lo, hi=None):
    """The (lo, hi) range of PORT_RANGES that holds lo..hi (hi defaults to lo), else ValueError."""
    hi = lo if hi is None else hi
    for r in PORT_RANGES:
        if r[0] <= lo and hi <= r[1]:
            return r
    raise ValueError("ports %d-%d are outside this harness's ranges %s" % (
        lo, hi, ", ".join("%d-%d" % r for r in PORT_RANGES)))


def check_port(port):
    port_range(port)
    if port_in_use(port):
        raise RuntimeError("port %d is in use (an emulator left running?)" % port)


def key_map(rom, S):
    """Forth's keyboard as {code: [ZEsarUX key events]}, derived from the three tables in the ROM image itself
    (kernel/io/io.asm KEY_ASCII_TABLE, KEY_ASCII_TABLE_UPPER, KEY_ASCII_TABLE_SYMBOL: 40 bytes each, index
    row * 5 + bit, the rows $FE ... $7F) plus CTRL_KEYS.  The unshifted table names the key at each position (a
    letter or digit; ENTER, SPACE); a code in the CAPS SHIFT table is CAPS SHIFT + that key, one in the SYMBOL
    SHIFT table SYMBOL SHIFT + it.  `rom` is the home ROM image (the tables are below $4000)."""
    tabs = [bytes(rom[S[n]:S[n] + 40]) for n in ("KEY_ASCII_TABLE", "KEY_ASCII_TABLE_UPPER", "KEY_ASCII_TABLE_SYMBOL")]
    base = {}
    for pos, code in enumerate(tabs[0]):
        if code == KEY_ENTER:
            base[pos] = Z_ENTER
        elif code == ord(" "):
            base[pos] = Z_SPACE
        elif code:
            base[pos] = code                # a lower case letter or a digit: ZEsarUX takes its ASCII
    out = {}
    for shift, tab in ((None, tabs[0]), (Z_CAPS, tabs[1]), (Z_SYM, tabs[2])):
        for pos, code in enumerate(tab):
            if code and pos in base:
                out.setdefault(code, ([shift] if shift else []) + [base[pos]])
    for code, ev in CTRL_KEYS.items():
        out.setdefault(code, ev)
    return out


# ---------------------------------------------------------------------------------------------------- the machine
class Machine:
    """One ZEsarUX running a Forth image.  `build`: a directory with forth_boot_rom0.bin (resolve_build).
    `snapdir` (default a private temp dir, removed by stop) holds the ROM file and the boot snapshot."""
    power_on = None             # f(machine) after reset-cpu, before the boot (a RAM / register pattern)

    def __init__(self, build, port, snapdir=None):
        port_range(port)
        self.build = resolve_build(build)
        self.port = port
        syms = [os.path.join(self.build, "forth_boot.sym"), os.path.join(self.build, "graphics_exrom.sym")]
        self.S = load_syms(*[p for p in syms if os.path.exists(p)])
        self.rom_home = open(os.path.join(self.build, "forth_boot_rom0.bin"), "rb").read()
        self.rom_exrom = open(os.path.join(self.build, "graphics_exrom.bin"), "rb").read()
        self._own_snapdir = snapdir is None
        self.snapdir = snapdir or tempfile.mkdtemp(prefix="fh%d-" % port)
        os.makedirs(self.snapdir, exist_ok=True)
        self.rom = os.path.join(self.snapdir, "image.bin")
        with open(self.rom, "wb") as f:
            f.write(self.rom_home + self.rom_exrom)
        self.snap = os.path.join(self.snapdir, "boot.zsf")
        self.proc = None
        self.c = None
        self.glyphs = None          # {8-byte cell: char} of the 32-column text screen
        self.plain_cells = {}       # {char: cell} for every character GFX_PUTCHAR draws
        self.keys = key_map(self.rom_home, self.S)
        self.boot = {}
        self.restore_wall = None    # seconds the last restore took

    # ------------------------------------------------------------- low level
    def sym(self, n):
        return self.S[n]

    def xsym(self, n):
        """An EXROM label as a breakpoint address that ignores the dictionary RAM at the same addresses (InExrom)."""
        return InExrom(self.S[n])

    def cmd(self, line, timeout=None):
        return self.c.command(line, timeout=timeout)

    def read(self, addr, n):
        out = b""
        while n > 0:
            k = min(n, 4096)
            out += bytes.fromhex(self.cmd("read-memory %d %d" % (addr, k)).strip())
            addr += k
            n -= k
        return out

    def w16(self, addr):
        b = self.read(addr, 2)
        return b[0] | b[1] << 8

    def write(self, addr, data):
        if isinstance(data, int):
            data = bytes([data])
        for i in range(0, len(data), 2048):
            self.cmd("write-memory-raw %d %s" % (addr + i, data[i:i + 2048].hex()))

    def poke16(self, addr, v):
        self.write(addr, struct.pack("<H", v & 0xFFFF))

    def setreg(self, r, v):
        self.cmd("set-register %s=%04XH" % (r, v & 0xFFFF))

    def regs(self):
        out = {}
        for tok in self.cmd("get-registers").split():
            if "=" in tok:
                k, v = tok.split("=", 1)
                try:
                    out[k] = int(v, 16)
                except ValueError:
                    pass
        return out

    def pc(self):
        return self.regs()["PC"]

    def _enable_bp(self):
        try:
            self.cmd("enable-breakpoints")
        except ZRCPError as e:
            if "already" not in str(e).lower():
                raise

    def set_bps(self, addrs):
        """Arm breakpoints 1..n at the given PCs; clear 1..8 beyond.  An InExrom address stops only
        with the EXROM paged in (BANK_EXROM_DEPTH nonzero)."""
        self._enable_bp()
        for i in range(1, 9):
            if i <= len(addrs):
                a = addrs[i - 1]
                if isinstance(a, InExrom):
                    self.cmd("set-breakpoint %d PC=%04XH and PEEK(%04XH)<>0" % (i, a, self.S["BANK_EXROM_DEPTH"]))
                else:
                    self.cmd("set-breakpoint %d PC=%04XH" % (i, a))
            else:
                self.cmd("set-breakpoint %d" % i)

    def run(self, maxi):
        return self.cmd("run %d" % maxi, timeout=max(30, maxi / 150_000 + 30))

    def run_to(self, addrs, maxi):
        """Run until PC is one of `addrs` (breakpoints) or maxi instructions pass; returns PC."""
        self.set_bps(list(addrs))
        self.run(maxi)
        return self.pc()

    def tstates_reset(self):
        self.cmd("reset-tstates-partial")

    def tstates(self):
        return int(self.cmd("get-tstates-partial").strip())

    # ------------------------------------------------------------- lifecycle
    def start(self, boot_max=20_000_000):
        if not os.path.exists(self.rom):
            raise FileNotFoundError(self.rom)
        check_port(self.port)
        try:
            self.proc = ZEsarUXProcess(ZESARUX, port=self.port, romfile=self.rom)
            self.proc.start()
            self.c = ZRCP(port=self.port, timeout=60)
            self.c.connect(retries=100)
            self.cmd("enter-cpu-step")
            self.cmd("reset-cpu")
            # ZRCP reset-cpu sets PC/SP/AF only: BC, DE, HL, IX, IY, the alternate set and the refresh register R
            # keep what the free-running boot left (step T found this; RANDOMIZE seeds from R).  Pin them.
            for r in ("R", "BC", "DE", "HL", "IX", "IY", "AF'", "BC'", "DE'", "HL'"):
                self.cmd("set-register %s=0H" % r)
            if self.power_on:
                self.power_on(self)
            self.tstates_reset()
            t0 = time.time()
            pc = self.run_to([self.sym("IO_READ_KEY")], boot_max)
            self.boot = dict(pc=pc, reached=pc == self.sym("IO_READ_KEY"), tstates=self.tstates(),
                             wall=time.time() - t0)
            if not self.boot["reached"]:
                raise AssertionError("boot did not reach IO_READ_KEY (PC=%04X)" % pc)
            self.cmd("snapshot-save " + self.snap)
            self.glyphs, self.plain_cells = self._glyph_table(self.sym("GFX_PUTCHAR"))
            self.restore()
        except BaseException:
            self.stop()
            raise
        return self

    def stop(self):
        try:
            if self.c:
                self.c.quit()
        except Exception:
            pass
        finally:
            if self.proc and self.proc.pid:
                pid = self.proc.pid
                self.proc.stop()
                terminate_emulator(pid, self.port, grace_s=3.0)     # (only if still a ZEsarUX on our port)
            self.proc = self.c = None
            if self._own_snapdir:
                shutil.rmtree(self.snapdir, ignore_errors=True)

    def restore(self):
        t0 = time.time()
        self.cmd("snapshot-load " + self.snap)
        self._enable_bp()
        self.restore_wall = time.time() - t0

    def checkpoint(self, name="checkpoint"):
        """Snapshot the live machine (RAM, registers, paging, the T-state phase as ZEsarUX keeps it) into the
        private snapshot directory and return the path.  A routine called on the machine (call) may then change
        anything, the stack and $FF00-$FF1F included; rollback(path) puts everything back.  The boot snapshot that
        restore() loads is not touched."""
        path = os.path.join(self.snapdir, name + ".zsf")
        self.cmd("snapshot-save " + path)
        return path

    def rollback(self, path):
        """Load a checkpoint() back (and re-enable breakpoints, which a snapshot load clears)."""
        self.cmd("snapshot-load " + path)
        self._enable_bp()

    # ------------------------------------------------------------- the screen
    def _glyph_table(self, putchar):
        """Render chars 32..143 with the real putchar routine (A=char, B=row, C=col; GFX_PUTCHAR, 32 columns) and map
        each 8x8 cell bitmap back to its character (as lcharness).  GFX_PUTCHAR draws a
        glyph for space, 0-9, A-Z, a-z, the 23 PUNCT_CHAR_TABLE characters and 128-143 (block graphics); any other
        code is drawn as a space, so those cells read blank and `[ \\ ] ^ ` { | } ~` have no cell (plain_cells
        lacks them).  Codes 128-143 map to U+2580 + (code - 128).  UDG codes 144-164 are not rendered: UDG_TABLE
        is zero at boot and a program may redefine them; screen_rows matches an unknown cell against the live
        UDG_TABLE instead.  Returns (table, plain_cells)."""
        codes = list(range(32, 144))
        d = tempfile.mkdtemp(prefix="fhglyph-")
        src = ["    DEVICE ZXSPECTRUM48", "    ORG $%04X" % GLYPH_PROG, "    ld   hl,codes", "    ld   b,0", "    ld   c,0",
               "    ld   d,%d" % len(codes), "loop:", "    push de", "    push bc", "    push hl", "    ld   a,(hl)",
               "    call $%04X" % putchar, "    pop  hl", "    pop  bc", "    pop  de", "    inc  hl", "    inc  c",
               "    ld   a,c", "    cp   32", "    jr   nz,nx", "    ld   c,0", "    inc  b",
               "nx: dec  d", "    jr   nz,loop", "done: jr done",
               "codes: DB " + ",".join(str(c) for c in codes),
               '    SAVEBIN "%s/g.bin", $%04X, $-$%04X' % (d, GLYPH_PROG, GLYPH_PROG)]
        open(d + "/g.asm", "w").write("\n".join(src) + "\n")
        r = subprocess.run(["sjasmplus", "--nologo", "--sym=" + d + "/g.sym", d + "/g.asm"],
                           capture_output=True, text=True)
        assert r.returncode == 0, r.stdout + r.stderr
        done = [int(l.split()[2], 16) for l in open(d + "/g.sym") if l.startswith("done:")][0]
        self.write(GLYPH_PROG, open(d + "/g.bin", "rb").read())
        self.write(RET_SLOT, struct.pack("<H", done))
        self.setreg("SP", RET_SLOT)
        self.setreg("PC", GLYPH_PROG)
        assert self.run_to([done], 5_000_000) == done, "glyph render did not finish"
        scr = self.read(0x4000, 6144)
        table, plain = {}, {}
        for i, ch in enumerate(codes):
            cell = cell_from(scr, i // 32, i % 32)
            table.setdefault(cell, chr(ch) if ch < 128 else chr(0x2580 + ch - 128))
            if ch < 127 and any(cell):
                plain[chr(ch)] = cell
        table[bytes(8)] = " "
        plain[" "] = bytes(8)
        shutil.rmtree(d, ignore_errors=True)
        return table, plain

    def screen(self):
        """The bitmap screen_rows reads: $4000-$57FF."""
        return self.read(0x4000, 6144)

    def screen_rows(self, scr=None, nrows=24):
        """The screen's text rows (trailing spaces dropped).  A cell that is no glyph reads as UNKNOWN; an inverse
        glyph (every pixel flipped) reads as INVERSE_MARK followed by its character (Forth has a real lower case font,
        so lcharness's inverse-as-lower-case would be ambiguous here); a cell equal to a nonblank
        entry of the live UDG_TABLE reads as chr(UDG_BASE + i) for UDG code 144 + i.  `scr` from screen(); the UDG_TABLE is
        read when needed, from the machine as it is now."""
        table = self.glyphs
        scr = scr if scr is not None else self.screen()
        udg = None
        rows = []
        for r in range(nrows):
            s = ""
            for col in range(32):
                cell = cell_from(scr, r, col)
                ch = table.get(cell)
                if ch is None:
                    if udg is None:
                        raw = self.read(self.sym("UDG_TABLE"), UDG_COUNT * 8)
                        udg = {raw[i * 8:i * 8 + 8]: chr(UDG_BASE + i) for i in reversed(range(UDG_COUNT))
                               if any(raw[i * 8:i * 8 + 8])}
                    ch = udg.get(cell)
                if ch is None:
                    ch = table.get(bytes(255 - b for b in cell))
                    ch = UNKNOWN if ch is None else INVERSE_MARK + ch
                s += ch
            rows.append(s.rstrip())
        return rows

    # ------------------------------------------------------------- memory assertions
    def expect_mem(self, where, data, what=None):
        """Assert that memory at `where` (a symbol name or an address) holds `data`.  AssertionError names
        the address and shows a hex diff: the first differing byte and up to 16 bytes on from it, expected and got."""
        addr = self.sym(where) if isinstance(where, str) else where
        label = what or (where if isinstance(where, str) else "memory")
        got = self.read(addr, len(data))
        if got == bytes(data):
            return
        bad = [i for i in range(len(data)) if got[i] != data[i]]
        i = bad[0]
        k = min(16, len(data) - i)
        raise AssertionError("%s at $%04X: %d of %d bytes differ; first at $%04X (offset %d)\n  expected %s\n  got      %s" % (
            label, addr, len(bad), len(data), addr + i, i, bytes(data[i:i + k]).hex(" "), got[i:i + k].hex(" ")))

    @staticmethod
    def ram_diff(before, after, base=0):
        """The ranges that changed between two equal-length memory images starting at `base`: [(lo, hi)], hi
        inclusive, both addresses (base + offset), in ascending order."""
        if len(before) != len(after):
            raise ValueError("ram_diff: %d bytes against %d" % (len(before), len(after)))
        out, i, n = [], 0, len(before)
        while i < n:
            if before[i] != after[i]:
                j = i
                while j + 1 < n and before[j + 1] != after[j + 1]:
                    j += 1
                out.append((base + i, base + j))
                i = j
            i += 1
        return out

    # ------------------------------------------------------------- Forth level
    def call(self, routine, maxi=50_000_000, t0=None, t1=None, regs=None):
        """Call `routine` (name or address) with SP = RET_SLOT and run until it returns to
        STOP_ADDR.  With t0/t1 (symbol names), also measure T-states from t0 to t1.  regs: {"AF": v, "BC": v ...}
        set before the call.  Returns dict(ok, pc, tstates)."""
        self.write(STOP_ADDR, b"\x18\xFE")
        self.write(RET_SLOT, struct.pack("<H", STOP_ADDR))
        self.setreg("SP", RET_SLOT)
        for r, v in (regs or {}).items():
            self.setreg(r, v)
        self.setreg("PC", self.sym(routine) if isinstance(routine, str) else routine)
        t = None
        if t0:
            if self.run_to([self.sym(t0)], maxi) != self.sym(t0):
                return dict(ok=False, pc=self.pc(), tstates=None)
            self.tstates_reset()
            if self.run_to([self.sym(t1)], maxi) != self.sym(t1):
                return dict(ok=False, pc=self.pc(), tstates=None)
            t = self.tstates()
        pc = self.run_to([STOP_ADDR], maxi)
        return dict(ok=pc == STOP_ADDR, pc=pc, tstates=t)


# ---------------------------------------------------------------------------------------------------- the console
class Console:
    """Forth's console and editor driven from outside: keys into the idle prompt's key wait (IO_READ_KEY).

    Start from a restored machine (boot()).  key()/type() write the ISR's latch; press() holds keys on the
    emulated matrix.  Each runs on to the next key wait and records its caller, the return address at SP
    (self.caller; in_editor() is true when the editor's EDITOR_LOOP_LIVE is the one waiting).

    What press() can type: the characters in Forth's own key tables (key_map: unshifted letters and digits, SPACE and
    ENTER; CAPS SHIFT + letter = upper case; SYMBOL SHIFT + key: ! @ # $ % & ' ( ) _ : ? / < > " ; = + - . , *), and the
    control codes of CTRL_KEYS.  Forth cannot type, at this build: [ \\ ] ^ ` { | } ~ (Forth draws none of them
    either; audit step K).  key() and type() can latch any code, typeable or not."""

    def __init__(self, m):
        self.m = m
        self.S = m.sym
        self.caller = None

    def boot(self):
        """Restore the booted machine (it sits at its first key wait)."""
        self.m.restore()
        self.caller = self.m.w16(self.m.regs()["SP"])

    def wait(self, maxi=60_000_000):
        """Run to the next key wait; records the caller.  RuntimeError if the machine does not get there."""
        pc = self.m.run_to([self.S("IO_READ_KEY")], maxi)
        if pc != self.S("IO_READ_KEY"):
            raise RuntimeError("no key wait: PC=%04X" % pc)
        self.caller = self.m.w16(self.m.regs()["SP"])

    def key(self, code, maxi=60_000_000):
        """A key code through the ISR's latch (KBD_LASTK, KBD_KEYHIT), then on to the next key wait."""
        self.m.write(self.S("KBD_LASTK"), code)
        self.m.write(self.S("KBD_KEYHIT"), 0xFF)
        self.m.cmd("cpu-step")
        self.wait(maxi)

    def type(self, text, enter=True):
        for ch in text:
            self.key(ord(ch))
        if enter:
            self.key(KEY_ENTER)

    def press(self, ch, maxi=60_000_000):
        """`ch` (a character or a key code) typed on the keyboard matrix: held until the ISR accepts it (debounce:
        IO_LATCH_AND_CLEAR), released, then on to the next key wait."""
        code = ord(ch) if isinstance(ch, str) else ch
        if code not in self.m.keys:
            raise KeyError("Forth cannot type %r on its keyboard" % (ch,))
        self.press_code(self.m.keys[code], maxi, ch)

    def press_code(self, events, maxi=60_000_000, what=None):
        """ZEsarUX key events `events` held until the ISR accepts the key, released, then on to the next key wait."""
        m, S = self.m, self.S
        for e in events:
            m.cmd("send-keys-event %d 1" % e)
        try:
            pc = m.run_to([S("IO_LATCH_AND_CLEAR")], 2_000_000)
        finally:
            for e in reversed(events):
                m.cmd("send-keys-event %d 0" % e)
        if pc != S("IO_LATCH_AND_CLEAR"):
            raise RuntimeError("key %r not accepted (PC=%04X)" % (what or events, pc))
        self.wait(maxi)

    def in_editor(self):
        return self.caller == self.S("EDITOR_LOOP_LIVE.keyloop") + 3

    def edit_line(self):
        n = self.m.read(self.S("EDIT_LEN"), 1)[0]
        return self.m.read(self.S("EDIT_BUF"), n).decode("latin-1")

    def rows(self):
        return self.m.screen_rows()


# ---------------------------------------------------------------------------------------------------- the pool
def _worker(build, port, tq, rq, fn, tasks, restore):
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))   # (the finally below stops the emulator)
    m = None
    try:
        while True:
            idx = tq.get()
            if idx is None:
                break
            rq.put(("take", idx, port))
            t0 = time.time()
            try:
                if m is None:
                    m = Machine(build, port)
                    m.start()
                    rq.put(("pid", port, m.proc.pid))
                if restore:
                    m.restore()
                r = dict(fn(m, tasks[idx]))
                if "ok" not in r or "detail" not in r:
                    raise HarnessError("fn returned %r: ok and detail are required" % (r,))
            except Exception as e:                  # noqa: BLE001 -- a task that crashes fails; new emulator
                r = dict(ok=False, detail="TASK FAILED %s: %s" % (type(e).__name__, e))
                try:
                    if m is not None:
                        m.stop()
                except Exception:                   # noqa: BLE001
                    pass
                m = None
            r["wall"], r["worker"] = time.time() - t0, port
            rq.put(("done", idx, r))
    finally:
        if m is not None:
            m.stop()
        rq.put(("exit", port, None))


class Suite:
    """A suite's tasks and how to report their results: tools/run_tests.py runs every suite's tasks on one pool.
    run(machine, task) -> dict(ok, detail, ...) as run_pool's fn; report(results, wall) prints the suite's lines and
    returns 0 (pass), 1 (a check failed) or 2 (harness error).  stock: indices of the tasks that need the stock-shaped
    EXROM (8 KB of $00; run on a copy of the build, stock_build)."""

    def __init__(self, name, tasks, run, report, stock=()):
        self.name, self.tasks, self.run, self.report, self.stock = name, list(tasks), run, report, set(stock)

    def run_alone(self, build, workers=None, port0=PORT_LO):
        """The suite on its own pools (the standalone tools)."""
        t0 = time.time()
        res = run_suites([self], build, workers, port0)[0]
        return self.report(res, time.time() - t0)


def stock_build(build):
    """A temporary copy of the build (the files the harness reads) whose graphics_exrom.bin is 8 KB of $00: what a Home
    ROM fitted alone sees at the EXROM address.  Returns the directory (the caller removes it)."""
    d = tempfile.mkdtemp(prefix="forth-stock-")
    for f in ("forth_boot_rom0.bin", "forth_boot.sym"):
        shutil.copy(os.path.join(build, f), d)
    with open(os.path.join(d, "graphics_exrom.bin"), "wb") as f:
        f.write(bytes(os.path.getsize(os.path.join(build, "graphics_exrom.bin"))))
    return d


def run_suites(suites, build, workers=None, port0=PORT_LO):
    """Every suite's tasks on one pool (long tasks first), the stock-EXROM tasks on a second pool after it.  Returns
    each suite's results in its task order."""
    build = resolve_build(build)
    main, stock = [], []
    for si, s in enumerate(suites):
        for ti, t in enumerate(s.tasks):
            (stock if ti in s.stock else main).append((si, ti))
    weight = lambda k: -(suites[k[0]].tasks[k[1]].get("weight", 1) if isinstance(suites[k[0]].tasks[k[1]], dict) else 1)
    main.sort(key=weight)
    fn = lambda m, k: suites[k[0]].run(m, suites[k[0]].tasks[k[1]])
    out = [[None] * len(s.tasks) for s in suites]
    if main:
        for k, r in zip(main, run_pool(build, main, fn, workers, port0)):
            out[k[0]][k[1]] = r
    if stock:
        d = stock_build(build)
        try:
            for k, r in zip(stock, run_pool(d, stock, fn, min(workers or default_workers(), 2), port0)):
                out[k[0]][k[1]] = r
        finally:
            shutil.rmtree(d, ignore_errors=True)
    return out


def default_workers():
    return max(1, min(8, (os.cpu_count() or 4) - 1))


def run_pool(build, tasks, fn, workers=None, port0=PORT_LO):
    """Run fn(machine, task) for every task on `workers` processes, one started Machine each (worker k on port
    port0 + k).  fn returns a dict with at least ok (bool) and detail (str); the pool adds wall (seconds) and worker
    (port).  The machine is restored before each task (restore=True; tasks do not depend on their order or their
    worker).  A task that raises counts as failed with the exception text, and that worker's emulator is restarted.
    Results come back in task order.  Every emulator is stopped on the way out, SIGTERM and exceptions included."""
    tasks = list(tasks)
    workers = max(1, min(workers or default_workers(), len(tasks) or 1))
    port_range(port0, port0 + workers - 1)
    build = resolve_build(build)
    for k in range(workers):
        check_port(port0 + k)
    ctx = mp.get_context("fork")                    # (fn may be a closure; the workers inherit it)
    tq, rq = ctx.Queue(), ctx.Queue()
    for i in range(len(tasks)):
        tq.put(i)
    for _ in range(workers):
        tq.put(None)
    results = [None] * len(tasks)
    procs, pids, running = {}, {}, {}
    old = signal.signal(signal.SIGTERM, lambda *_: sys.exit(1))
    try:
        for k in range(workers):
            p = ctx.Process(target=_worker, args=(build, port0 + k, tq, rq, fn, tasks, True), daemon=True)
            p.start()
            procs[port0 + k] = p
        live = set(procs)
        while live:
            try:
                kind, a, b = rq.get(timeout=1)
            except queue.Empty:
                for port in list(live):             # a worker that died: its task failed, it takes no more
                    if not procs[port].is_alive():
                        live.discard(port)
                        if port in running:
                            results[running.pop(port)] = dict(ok=False, detail="worker on port %d died" % port,
                                                              wall=0.0, worker=port)
                continue
            if kind == "take":
                running[b] = a
            elif kind == "pid":
                pids[a] = b
            elif kind == "done":
                results[a] = b
                running.pop(b["worker"], None)
            elif kind == "exit":
                live.discard(a)
        for p in procs.values():
            p.join()
    finally:                                        # never leave workers (and their emulators) behind
        signal.signal(signal.SIGTERM, old)
        for p in procs.values():
            if p.is_alive():
                p.terminate()
        for p in procs.values():
            p.join(10)
        for port, pid in pids.items():              # (a worker killed hard could not stop its own)
            if pid:
                terminate_emulator(pid, port, grace_s=3.0)
    for i, r in enumerate(results):
        if r is None:
            results[i] = dict(ok=False, detail="never ran (no worker left)", wall=0.0, worker=None)
    return results


# ---------------------------------------------------------------------------------------------------- self-test
def banner_text():
    """The banner the ROM prints, from rom/forth_boot.asm (`BANNER: DB "...", 0`)."""
    src = open(os.path.join(ROOT, "rom", "forth_boot.asm")).read()
    return re.search(r'^BANNER:\s+DB\s+"([^"]*)"\s*,\s*0', src, re.M).group(1)


def drawn_chars(m):
    """The characters GFX_PUTCHAR has a glyph for in 32-126, from the ROM's own PUNCT_CHAR_TABLE (pairs: char, font index)."""
    n, a = m.sym("PUNCT_CHAR_COUNT"), m.sym("PUNCT_CHAR_TABLE")
    punct = {chr(m.rom_home[a + 2 * i]) for i in range(n)}
    return set(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz") | punct


def _check_boot(m, _):
    b = m.boot
    return dict(ok=b["reached"] and b["pc"] == m.sym("IO_READ_KEY"),
                detail="reached IO_READ_KEY ($%04X), %d T-states" % (b["pc"], b["tstates"]),
                info="boot wall %.1f s" % b["wall"])


def _check_glyphs(m, _):
    want = drawn_chars(m)
    cells = m.plain_cells
    drawn = {c for c in map(chr, range(32, 127)) if any(cells.get(c, b""))}
    blank = sorted(chr(c) for c in range(32, 127) if chr(c) not in drawn)
    distinct = len({cells[c] for c in drawn}) == len(drawn)
    ok = (drawn == want - {" "}) and distinct and [c for c in blank if c != " "] == sorted(set(map(chr, range(32, 127))) - want) \
        and blank[0] == " " and all(m.glyphs.get(cells[c]) == c for c in drawn)
    return dict(ok=ok, detail="space blank, %d other glyphs in 33-126 all distinct and nonblank; %d undrawn codes render blank: %s"
                % (len(drawn), len(blank) - 1, "".join(c for c in blank if c != " ")),
                info="")


def _check_banner(m, _):
    want = banner_text()
    rows = m.screen_rows()
    return dict(ok=rows[0] == want and not any(rows[1:]), detail="row 0 = %r, rows 1-23 blank" % rows[0])


def _check_restore(m, _):
    snap = m.read(0x4000, 0xC000)
    m.restore()
    first = m.read(0x4000, 0xC000)
    walls = [m.restore_wall]
    m.call("GFX_CLS")
    after = m.read(0x4000, 0xC000)
    changed = m.ram_diff(snap, after, 0x4000)
    m.restore()
    walls.append(m.restore_wall)
    again = m.read(0x4000, 0xC000)
    return dict(ok=first == snap and again == snap and bool(changed),
                detail="$4000-$FFFF identical over restores; a call changed %d range(s), first $%04X-$%04X" % (
                    len(changed), *changed[0]) if changed else "the probe call changed nothing",
                info="restore %.0f ms, %.0f ms" % (walls[0] * 1000, walls[1] * 1000))


def _check_call(m, _):
    r = m.call("GFX_CLS")
    bitmap = m.read(0x4000, 0x1800)
    return dict(ok=r["ok"] and not any(bitmap), detail="GFX_CLS returned to STOP_ADDR (PC=%04X); bitmap $4000-$57FF all zero" % r["pc"])


def _check_type(m, _):
    con = Console(m)
    con.boot()
    con.type("1 2 + .")
    rows = con.rows()
    shown = [r for r in rows[1:23] if r]
    ok = shown == ["3 OK"] and con.edit_line() == "" and con.in_editor()
    return dict(ok=ok, detail="rows 1-22 = %r, edit line %r, editor waiting=%s" % (shown, con.edit_line(), con.in_editor()))


def _check_press(m, _):
    con = Console(m)
    con.boot()
    for ch in "2 3 * .":
        con.press(ch)
    con.press("\r")
    shown = [r for r in con.rows()[1:23] if r]
    line = "Ab:?(+"                                  # CAPS SHIFT + a letter, SYMBOL SHIFT + Z, C, 8, K
    for ch in line:
        con.press(ch)
    got, last = con.edit_line(), con.rows()[23]
    ok = shown == ["6 OK"] and got == line and last == line and con.in_editor()
    return dict(ok=ok, detail="matrix: rows 1-22 = %r; edit line %r (row 23 %r)" % (shown, got, last))


def _check_checkpoint(m, _):
    con = Console(m)
    con.boot()
    con.type("1 2", enter=False)
    before = m.read(0x4000, 0xC000)
    regs = m.regs()
    cp = m.checkpoint("probe")
    m.call("GFX_CLS")
    m.write(0xF000, b"\x55")
    changed = m.ram_diff(before, m.read(0x4000, 0xC000), 0x4000)
    m.rollback(cp)
    after = m.read(0x4000, 0xC000)
    now = m.regs()
    con.key(ord("+"))
    ok = after == before and bool(changed) and (now["PC"], now["SP"]) == (regs["PC"], regs["SP"]) \
        and con.in_editor() and con.edit_line() == "1 2+"
    return dict(ok=ok, detail="a call and a poke changed %d range(s); rollback gave back $4000-$FFFF byte for byte, "
                              "and the editor takes keys again" % len(changed))


def _check_mem(m, _):
    ft = m.sym("FONT_TABLE")
    m.expect_mem("FONT_TABLE", m.rom_home[ft:ft + 16], "font")
    try:
        m.expect_mem(ft, m.rom_home[ft:ft + 15] + b"\xAA", "font")
        return dict(ok=False, detail="a wrong byte was not caught")
    except AssertionError as e:
        msg = str(e)
    a = m.read(0xF000, 12)
    m.write(0xF004, b"\x01\x02")
    m.poke16(0xF008, 0xBEEF)
    b = m.read(0xF000, 12)
    d = m.ram_diff(a, b, 0xF000)
    ok = d == [(0xF004, 0xF005), (0xF008, 0xF009)] and m.w16(0xF008) == 0xBEEF and "$%04X" % (ft + 15) in msg
    return dict(ok=ok, detail="expect_mem diff names $%04X; ram_diff %s" % (ft + 15, ["$%04X-$%04X" % x for x in d]))


# (letter i, the 64-column screen, was retired in step M6 with the mode; the letters are not renumbered)
CHECKS = [("a", "boot", _check_boot), ("b", "glyph table", _check_glyphs), ("c", "banner", _check_banner),
          ("d", "restore determinism", _check_restore), ("e", "call GFX_CLS", _check_call),
          ("f", "Console.type", _check_type), ("g", "Console.press", _check_press),
          ("j", "memory assertions", _check_mem),
          ("k", "checkpoint/rollback", _check_checkpoint)]


def _run_checks(build, workers, port0):
    t0 = time.time()
    res = run_pool(build, CHECKS, lambda m, task: task[2](m, task), workers, port0)
    return res, time.time() - t0


def selftest(build, workers, port0):
    t_all = time.time()
    res, wall = _run_checks(build, workers, port0)
    n_fail = 0
    for (tag, name, _), r in zip(CHECKS, res):
        n_fail += not r["ok"]
        print("%s %s %-20s %s%s  [%.1f s, port %s]" % ("PASS" if r["ok"] else "FAIL", tag, name, r["detail"],
                                                         (" (%s)" % r["info"]) if r.get("info") else "", r["wall"], r["worker"]))
    if workers > 1:
        one, wall1 = _run_checks(build, 1, port0)
        same = [(a["ok"], a["detail"]) for a in res] == [(a["ok"], a["detail"]) for a in one]
        n_fail += not same
        print("%s h %-20s the results with --workers 1 and --workers %d are %s  [%.1f s and %.1f s]" % (
            "PASS" if same else "FAIL", "pool", workers, "identical" if same else "DIFFERENT", wall1, wall))
        if not same:
            for (tag, _, _), a, b in zip(CHECKS, res, one):
                if (a["ok"], a["detail"]) != (b["ok"], b["detail"]):
                    print("     %s: %r vs %r" % (tag, a["detail"], b["detail"]))
    else:
        print("SKIP h pool                 --workers 1: nothing to compare")
    print("%d check(s) failed; self-test wall %.1f s" % (n_fail, time.time() - t_all))
    return n_fail == 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--selftest", action="store_true", help="run the self-test")
    ap.add_argument("--build", default=ROOT, help="a directory with forth_boot_rom0.bin (DIR or DIR/build)")
    ap.add_argument("--workers", type=int, default=3, help="workers of the parallel run (the self-test also runs 1)")
    ap.add_argument("--port", type=int, default=PORT_LO, help="first ZRCP port (%d-%d)" % (PORT_LO, PORT_HI))
    a = ap.parse_args()
    if not a.selftest:
        ap.error("nothing to do: this is a library; --selftest runs its self-test")
    try:
        build = resolve_build(a.build)
        return 0 if selftest(build, a.workers, a.port) else 1
    except (FileNotFoundError, ValueError, RuntimeError) as e:
        print("fharness: %s" % e, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
