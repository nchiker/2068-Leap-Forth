"""Fuse 1.9.1, headless, as a second and independent emulator for the Leap-Forth V2 ROM (tape tests).

Ported from 2068-Leap-C's tools/fusedrive.py (same owner), adapted to the Forth ROM: its labels come from
build/forth_boot.sym, its screen is decoded with the glyphs of its own FONT_TABLE (read from the ROM image, not
rendered by an emulator), and nothing depends on Leap-C's lcharness.

Fuse runs headless (SDL's dummy video driver, no sound; --speed 20000: about 130 times a real machine) with the
build's images as its TS2068 ROMs (--rom-ts2068-0 HOME = forth_boot_rom0.bin, --rom-ts2068-1 EXROM =
graphics_exrom.bin), and is driven through tools/fuse/fuseshim.c, an LD_PRELOAD library that answers commands on
a Unix socket once per emulated frame (see its header).  Only Fuse's own emulation is used: keys go into its
keyboard matrix as a person would press them, the debugger's breakpoints observe, tapes go through its tape deck
as signals (tape traps off, so the ROM's own receiver reads the EAR bit).  Nothing in the ROM is test-only.

The key handshake (as Leap-C's, and the ZEsarUX harnesses' Shell.press): the shim presses a chord only while the
machine waits for a key (its PC, or at the frame's interrupt the PC it interrupted, in IO_READ_KEY's wait loop,
kernel/io/io.asm: `.wait_hit`, 6 bytes), and holds it until IO_LATCH_AND_CLEAR has run: a debugger breakpoint set
before the emulation starts counts those runs in RAM the ROM leaves unused (ACC, $FFF1: the Forth ROM puts SP at
$FF00 and nothing lives above it).  So typing is paced by the machine, not by the clock, at any Fuse speed.  The
Forth ROM's key labels are the same ones Leap-C has (IO_READ_KEY, IO_LATCH_AND_CLEAR), so the shim's arguments
are unchanged; the chord map differs and is read from the ROM's own three key tables (KEY_ASCII_TABLE, _UPPER,
_SYMBOL), so a character the ROM cannot type is an error here, never a silent miss.
"""
import glob
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
FUSE = os.environ.get("FORTH_FUSE", "/usr/local/bin/fuse")
SHIM_SRC = os.path.join(HERE, "fuse", "fuseshim.c")
SHIM_SO = os.path.join(ROOT, "build", "fuse", "fuseshim.so")
SHIM_SYMS = ("memory_map_read", "z80", "frames_since_reset", "tstates", "keyboard_press", "keyboard_release",
             "debugger_command_evaluate", "writebyte_internal", "tape_open", "tape_write", "tape_record_start",
             "tape_record_stop", "tape_is_playing", "tape_toggle_play")
MEMORY_PAGE_SIZE = 32       # sizeof(memory_page) in fuseshim.c (x86-64)
PROCESSOR_SIZE = 52         # sizeof(processor) (z80/z80.h) with SP and PC at 26 and 28, as fuseshim.c reads them
CPU_HZ = 3_528_000          # Fuse's TS2068 clock
TPF = 224 * 262             # Fuse's TS2068 frame: 224 T a line, 262 lines (libspectrum timings.c)
ACC = 0xFFF1                # the handshake's key-acceptance counter
K_ENTER, K_CAPS, K_SYM = 0x100, 0x101, 0x102     # Fuse keyboard_key_name values (letters, digits, space: their ASCII)
# The keyboard matrix's rows as io.asm's tables index them (row*5 + bit): the Fuse key at each position.
MATRIX = [[K_CAPS, "z", "x", "c", "v"], ["a", "s", "d", "f", "g"], ["q", "w", "e", "r", "t"],
          ["1", "2", "3", "4", "5"], ["0", "9", "8", "7", "6"], ["p", "o", "i", "u", "y"],
          [K_ENTER, "l", "k", "j", "h"], [" ", K_SYM, "m", "n", "b"]]
DELETE = [K_CAPS, ord("0")]        # CAPS SHIFT + 0
BREAK = [K_CAPS, 0x20]             # CAPS SHIFT + SPACE


def load_syms(path):
    syms = {}
    for line in open(path):
        if ": EQU" in line:
            n, _, v = line.partition(": EQU")
            syms[n.strip()] = int(v.strip(), 0)
    return syms


def _kc(k):
    return k if isinstance(k, int) else ord(k)


def chord_map(rom, S):
    """{character: [Fuse keys]} from the ROM's key tables: plain, CAPS SHIFT + key (letters), SYMBOL SHIFT + key."""
    out = {}
    for table, shift in (("KEY_ASCII_TABLE", []), ("KEY_ASCII_TABLE_UPPER", [K_CAPS]), ("KEY_ASCII_TABLE_SYMBOL", [K_SYM])):
        base = S[table]
        for i in range(40):
            ch = rom[base + i]
            key = MATRIX[i // 5][i % 5]
            if ch == 0 or key in (K_CAPS, K_SYM):
                continue
            c = chr(ch)
            if shift and not (c.isalpha() or table.endswith("SYMBOL")):
                continue
            out.setdefault(c, shift + [_kc(key)])
    return out


def glyph_map(rom, S):
    """{8 glyph bytes: character} from FONT_TABLE: space, 0-9, A-Z, a-z, then PUNCT_CHAR_TABLE's (char, index) pairs."""
    ft = S["FONT_TABLE"]
    chars = {0: " "}
    for i, c in enumerate("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"):
        chars[i + 1] = c
    pt = S["PUNCT_CHAR_TABLE"]
    for i in range(S["PUNCT_CHAR_COUNT"]):
        chars[rom[pt + 2 * i + 1]] = chr(rom[pt + 2 * i])
    return {bytes(rom[ft + n * 8:ft + n * 8 + 8]): c for n, c in chars.items()}


def build_shim():
    """build/fuse/fuseshim.so, compiled from tools/fuse/fuseshim.c (once: workers must not race to make it).
    The shim only uses SDL2's declarations (SDL_Event, SDL_PollEvent, key constants), never links SDL: SDL's
    headers come from sdl2-config, or pkg-config, or FUSE_SDL2_INCLUDE (the directory that holds SDL2/SDL.h), or
    a flatpak SDK's copy (searched after the system's headers: it also holds copies of libc's)."""
    out = SHIM_SO
    if os.path.exists(out) and os.path.getmtime(out) >= os.path.getmtime(SHIM_SRC):
        return out
    cflags = []
    for cmd in (["sdl2-config", "--cflags"], ["pkg-config", "--cflags", "sdl2"]):
        try:
            r = subprocess.run(cmd, capture_output=True, text=True)
        except OSError:
            continue
        if r.returncode == 0 and r.stdout.strip():
            cflags = r.stdout.split()
            break
    if not cflags:
        inc = os.environ.get("FUSE_SDL2_INCLUDE")
        if not inc:
            found = sorted(glob.glob(os.path.expanduser(
                "~/.local/share/flatpak/runtime/org.freedesktop.Sdk/x86_64/*/*/files/include/SDL2/SDL.h")))
            inc = os.path.dirname(os.path.dirname(found[0])) if found else None
        if not inc:
            raise RuntimeError("no SDL2 headers (sdl2-config, pkg-config sdl2): install libsdl2-dev or set FUSE_SDL2_INCLUDE")
        cflags = ["-idirafter", inc]
    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".%d" % os.getpid()
    subprocess.run(["gcc", "-shared", "-fPIC", "-O2", "-Wall"] + cflags + ["-o", tmp, SHIM_SRC, "-ldl"], check=True)
    os.replace(tmp, out)
    return out


def fuse_syms():
    """Offsets of the shim's Fuse entry points (nm of the unstripped binary), and the check that the
    shim's memory_page is Fuse's (memory_map_read holds 32 of them: 2 KB pages over 64 K)."""
    out, sizes = {}, {}
    for l in subprocess.run(["nm", "-S", FUSE], capture_output=True, text=True, check=True).stdout.split("\n"):
        p = l.split()
        if len(p) == 4:
            out[p[3]], sizes[p[3]] = p[0], int(p[1], 16)
        elif len(p) == 3:
            out.setdefault(p[2], p[0])
    missing = [n for n in SHIM_SYMS if n not in out]
    if missing:
        raise RuntimeError("Fuse binary lacks %s (not 1.9.1, or stripped)" % missing)
    if sizes.get("memory_map_read") != 32 * MEMORY_PAGE_SIZE or sizes.get("z80") != PROCESSOR_SIZE:
        raise RuntimeError("Fuse's memory_page or processor is not the shim's (%r, %r B)" % (
            sizes.get("memory_map_read"), sizes.get("z80")))
    return ",".join("%s=%s" % (n, out[n]) for n in SHIM_SYMS)


def stock_roms():
    """(rom0, rom1) of the genuine TS2068 ROMs, for the cartridge runs: $FORTH_STOCK_ROMS (a directory holding
    tc2068-0.rom and tc2068-1.rom), else ~/fuse-build/roms (where tools/cart_diff.py looks), else Fuse's own
    data directories."""
    dirs = [os.environ.get("FORTH_STOCK_ROMS"), os.path.expanduser("~/fuse-build/roms"),
            "/usr/local/share/fuse/roms", "/usr/share/spectrum-roms", "/usr/share/fuse/roms"]
    for d in dirs:
        if d and all(os.path.isfile(os.path.join(d, n)) for n in ("tc2068-0.rom", "tc2068-1.rom")):
            return os.path.join(d, "tc2068-0.rom"), os.path.join(d, "tc2068-1.rom")
    raise RuntimeError("no stock tc2068-0.rom + tc2068-1.rom in %s (set FORTH_STOCK_ROMS)" % [d for d in dirs if d])


def fuse_version():
    r = subprocess.run([FUSE, "--version"], capture_output=True, text=True)
    m = re.search(r"version (\S+)\.", r.stdout + r.stderr)
    return m.group(1) if m else "?"


class Fuse:
    """One headless Fuse running the Forth images in `build`, its files in `wdir`."""

    def __init__(self, build, wdir, speed=20000, extra=None, dck=None):
        """dck: a DOCK cartridge file (build/forth_boot.dck, or a patched copy): the machine then keeps the STOCK
        TS2068 ROMs (stock_roms()) and boots into the cartridge, whose labels are build/forth_boot_cart.sym and
        whose image (for the key tables) is build/forth_boot_cart.bin.  None: the Home build, as always."""
        self.build = os.path.abspath(build)
        self.wdir = os.path.abspath(wdir)
        self.speed = speed
        self.extra = extra or []
        self.dck = os.path.abspath(dck) if dck else None
        self.S = load_syms(os.path.join(self.build, "forth_boot_cart.sym" if dck else "forth_boot.sym"))
        self.rom = open(os.path.join(self.build, "forth_boot_cart.bin" if dck else "forth_boot_rom0.bin"), "rb").read()
        self.chords_for = chord_map(self.rom, self.S)
        self.glyph = glyph_map(self.rom, self.S)
        self.proc = self.sock = None
        self.boot = None

    # ------------------------------------------------------------------ process
    def start(self, timeout=60):
        os.makedirs(self.wdir, exist_ok=True)
        home = os.path.join(self.wdir, "home")
        os.makedirs(home, exist_ok=True)
        self.sock_path = "\0forth-fuse-%d-%d" % (os.getpid(), id(self))   # (abstract: no path length limit)
        self.out_path = os.path.join(self.wdir, "fuse.out")
        S = self.S
        # before the emulation starts: the handshake counter, and the boot's first key wait printed once
        # (Fuse's parser refuses a newline after the last command)
        dbg = ("break 0x%04x\ncommands 1\nset 0x%04x ([0x%04x]+1)&255\ncontinue\nend\n"
               "tbreak 0x%04x\ncommands 2\nprint 0xb0070\nprint spectrum:frames\nprint ula:tstates\ncontinue\nend" % (
                   S["IO_LATCH_AND_CLEAR"], ACC, ACC, S["IO_READ_KEY"]))
        env = dict(os.environ, SDL_VIDEODRIVER="dummy", SDL_AUDIODRIVER="dummy", LD_PRELOAD=build_shim(),
                   LEAPC_FUSE_SOCK="@" + self.sock_path[1:], LEAPC_FUSE_SYMS=fuse_syms(), HOME=home, XDG_CONFIG_HOME=home)
        if self.dck:
            rom0, rom1 = stock_roms()
            roms = ["--rom-ts2068-0", rom0, "--rom-ts2068-1", rom1, "--dock", self.dck]
        else:
            roms = ["--rom-ts2068-0", os.path.join(self.build, "forth_boot_rom0.bin"),
                    "--rom-ts2068-1", os.path.join(self.build, "graphics_exrom.bin")]
        args = [FUSE, "--machine", "ts2068"] + roms + ["--no-sound", "--speed", str(self.speed),
                "--no-auto-load", "--no-traps", "--no-confirm-actions", "--no-autosave-settings",
                "--debugger-command", dbg] + self.extra
        self.out = open(self.out_path, "w")
        self.proc = subprocess.Popen(args, env=env, stdout=self.out, stderr=subprocess.STDOUT, cwd=self.wdir)
        t0 = time.time()
        while True:
            try:
                self.sock = socket.socket(socket.AF_UNIX)
                self.sock.connect(self.sock_path)
                break
            except OSError:
                self.sock.close()
                if self.proc.poll() is not None or time.time() - t0 > timeout:
                    self.stop()
                    raise RuntimeError("Fuse did not start: %s" % open(self.out_path).read()[-500:])
                time.sleep(0.05)
        self.f = self.sock.makefile("rw")
        try:
            self.wait(lambda: self.prints(0xB0070), timeout, "the boot's first key wait")
        except Exception:
            self.stop()
            raise
        frames, t = self.prints(0xB0070)[0]
        self.boot = dict(frames=frames, tstates=t, total=frames * TPF + t)
        return self

    def stop(self):
        try:
            if self.sock:
                self.f.write("quit\n")
                self.f.flush()
        except OSError:
            pass
        if self.proc:
            try:
                self.proc.wait(5)
            except subprocess.TimeoutExpired:
                self.proc.kill()                    # (SIGKILL: a halted Fuse ignores SIGTERM)
                self.proc.wait()
        if self.sock:
            self.sock.close()
        self.sock = None

    # ------------------------------------------------------------------ shim
    def cmd(self, line):
        self.f.write(line + "\n")
        self.f.flush()
        r = self.f.readline().strip()
        if not r.startswith("ok"):
            raise RuntimeError("fuseshim: %r -> %r" % (line, r))
        return r[3:]

    def ping(self):
        a, b = self.cmd("ping").split()
        return int(a), int(b)

    def peek(self, a, n):
        return bytes.fromhex(self.cmd("peek %d %d" % (a, n)))

    def w16(self, a):
        b = self.peek(a, 2)
        return b[0] | b[1] << 8

    def poke(self, a, data):
        for i in range(0, len(data), 4096):
            self.cmd("poke %d %s" % (a + i, data[i:i + 4096].hex()))

    def dbg(self, text):
        self.cmd("dbg " + text.replace("\n", "\\n"))

    def output(self):
        """Fuse's standard output so far (the debugger's prints, as 0x... lines)."""
        self.out.flush()
        return open(self.out_path, encoding="latin-1").read()

    def prints(self, marker):
        """The groups of values printed after each `print MARKER` line: [(v1, v2, ...)]."""
        vals = [int(l, 16) for l in self.output().split() if re.fullmatch(r"0x[0-9a-f]+", l)]
        out, i = [], 0
        while i < len(vals):
            if vals[i] == marker:
                j = i + 1
                while j < len(vals) and vals[j] < 0xB0000:
                    j += 1
                out.append(tuple(vals[i + 1:j]))
                i = j
            else:
                i += 1
        return out

    def wait(self, cond, timeout, what):
        t0 = time.time()
        while not cond():
            if self.proc.poll() is not None:
                raise RuntimeError("Fuse exited waiting for %s" % what)
            if time.time() - t0 > timeout:
                raise TimeoutError("Fuse: %s not reached in %d s" % (what, timeout))
            time.sleep(0.01)

    def wait_frames(self, n, timeout=120):
        f0 = self.ping()[0]
        self.wait(lambda: self.ping()[0] >= f0 + n, timeout, "%d frames" % n)

    # ------------------------------------------------------------------ keyboard
    def chord(self, ch):
        """The keys that type `ch` on the Forth ROM's key map (kernel/io/io.asm's tables)."""
        if ch == "\n":
            return [K_ENTER]
        try:
            return self.chords_for[ch]
        except KeyError:
            raise ValueError("the Forth ROM's keyboard cannot type %r" % ch)

    def chords(self, seq, timeout=300, settle=True):
        """Type the chords in `seq` (lists of key codes) with the handshake; returns when the last one was
        accepted and (settle) the machine has come back to a key wait."""
        lo = self.S["IO_READ_KEY"]
        for i in range(0, len(seq), 200):
            part = seq[i:i + 200]
            self.cmd("chords %d %d %d %s" % (ACC, lo, lo + 6, " ".join("+".join(str(k) for k in c) for c in part)))
            last = settle or i + 200 < len(seq)
            self.wait(lambda: self.cmd("queue") == "0 1" if last else self.cmd("queue").startswith("0 "),
                      timeout, "the keys typed")

    def type(self, text, enter=True, timeout=300):
        self.chords([self.chord(c) for c in text] + ([[K_ENTER]] if enter else []), timeout)

    def key(self, ch=" ", timeout=300):
        self.chords([self.chord(ch)], timeout)

    def hold(self, keys, frames):
        """Keys held for `frames` frames, then released (no handshake)."""
        for k in keys:
            self.cmd("press %d" % k)
        try:
            self.wait_frames(frames)
        finally:
            for k in reversed(keys):
                self.cmd("release %d" % k)

    def at_key_wait(self):
        return self.cmd("queue").split()[1] == "1"

    def idle(self):
        """At the prompt: in the key wait with an empty edit line."""
        return self.at_key_wait() and self.peek(self.S["EDIT_LEN"], 1)[0] == 0

    # ------------------------------------------------------------------ screen
    def screen(self):
        return self.peek(0x4000, 6912)

    def rows(self, scr=None):
        """The 24 text rows of the 32-column screen, decoded with the ROM's glyphs ('~' = a glyph not in the font)."""
        scr = scr if scr is not None else self.screen()
        rows = []
        for r in range(24):
            cells = [bytes(scr[((r >> 3) << 11) + (ln << 8) + ((r & 7) << 5) + c] for ln in range(8)) for c in range(32)]
            rows.append("".join(self.glyph.get(x, "~") for x in cells).rstrip())
        return rows

    def edit_line(self):
        n = self.peek(self.S["EDIT_LEN"], 1)[0]
        return self.peek(self.S["EDIT_BUF"], n).decode("latin-1")
