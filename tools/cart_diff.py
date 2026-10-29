#!/usr/bin/env python3
"""cart_diff.py - differential test: the SAME typed Forth program on the HOME build and the CART build.

HOME build: build/forth_boot_rom0.bin (16K Home ROM) + build/graphics_exrom.bin (8K EXROM), symbols
            build/forth_boot.sym.  ZEsarUX boots the two as one 24K --romfile; TSRun gets m.homeRom/m.exRom.
CART build: stock TS2068 ROMs (~/fuse-build/roms/tc2068-0.rom + tc2068-1.rom) plus a .dck (LROS in DOCK
            chunks 0-1, graphics_exrom.bin in DOCK chunk 5), symbols build/forth_boot_cart.sym.

Each case = a list of Forth lines typed through the keyboard on a FRESH boot of each build, on each
emulator (ZEsarUX through ts2068_debug/ZRCP; TSRun headless under node through its keyMatrix).  A final
control line `1 2 + .` is always typed.  When the prompt is idle again the machine state is read and compared.

WHAT IS COMPARED (HOME vs CART, per emulator; any difference is a FAIL, nothing is tolerated silently)
 1. screen $4000-$5AFF (bitmap + attributes): byte-identical.  The control line's `3 OK` is part of it, and
    is also checked on its own by reading the screen text back (glyphs matched against the ROM font).
 2. data stack (IX, bytes IX..DSTACK_TOP) and float stack (IY, bytes IY..FSTACK_TOP): same register, same bytes.
 3. dictionary: HERE and LATEST, and the user dictionary bytes FORTH_DICT_RAM..HERE.  The ROM layouts differ
    (the cartridge's paging routines are a different size, so every ROM address after kernel/bank shifts), so
    compiled code legitimately contains different ROM addresses.  NORMALISATION: where the raw bytes differ and
    the differing byte lies in a 16-bit little-endian word that is a ROM address ($0100-$3FFF) in BOTH builds,
    the word is mapped to NAME+OFFSET (nearest preceding symbol of that build's own .sym) and the names must
    be equal.  Counted as `calls` (word follows CD/C3) or `words` (any other word: link fields, LATEST).  Every
    other byte must match raw.  The counts are printed so a vacuous pass (0 normalised operands in a case that
    compiles a call) is visible.
 4. EXROM-side state, raw: GFX_FILL_SP..POLY_FILL_ERR_ADDR (GFX_FILL, RECT_*, POLY_* cells), SPRITE_SLOT_DEFINED..
    BANK_EXROM_DEPTH (sprite slot cells, SPRITE_OP_*, the paging depth counter) and the sprite image/background
    buffers SPRITE_SLOT_IMG_BUF..+288.  Excluded on purpose: PORT_FF_SHADOW (its bit 7 is the HOME-vs-CART
    EXROM/DOCK select, differs by design) and the keyboard/ISR/FRAMES cells (host-timing dependent).
 5. at idle chunk 5 is paged out (BANK_EXROM_DEPTH == 0 and port $F4 bit 5 clear), and the machine is responsive:
    the control line printed `3 OK`.  A cart machine that never returns to its idle prompt is UNRESPONSIVE (exit 1).
Idle = PC parked in IO_READ_KEY.wait_hit (or in the interrupt entered from it) and EDIT_LEN == 0.  Before ENTER
the edit buffer is read back and compared with the line, so a dropped/duplicated keystroke is a harness
error (the case is retried on a fresh boot, up to 4 attempts, printed) and never a silent pass.
Informational: HOME screen bytes from ZEsarUX vs HOME screen bytes from TSRun.  TSRun also spies on writes to
BANK_EXROM_DEPTH (max value stored): 1 means page-ins never nested.

RUN:  python3 cart_diff.py --home-dir TREE --cart-dir TREE [--cart-dck FILE] [--emulators zesarux,tsrun]
        [--cases a,b] [--port 10930] [--json] [--selftest] [--dump DIR]      (TREE/build/ holds the build products; the cart
      .dck defaults to CART_DIR/build/forth_boot.dck; ~13 cases take ~12 min with ZEsarUX, ~35 s with TSRun only)

NESTED PAGE-IN (BANK_EXROM_DEPTH): BANK_PAGE_EXROM_IN has exactly one caller (EXROM_CALL_SLOT), which only the
Forth words RECT/POLYGON/POLYGON-FILL/SPRITE-* call; the HOME routines the EXROM code calls back through the
$0100 table (GFX_WRITE_PIXEL, GFX_SET_ATTR, GFX_LINE, GFX_ROW_BASE_ADDR, GFX_CELL_ATTR_ADDR) cannot reach it
(static check: tools/cart_nested_reach.py, a flow walk over the .lst; plus the TSRun depth spy printed per case).  So
no case can nest a page-in; a nested page-in only exists as a unit-level property of bank.asm itself.

EXIT: 0 every case/emulator identical; 1 any difference or the cart machine unresponsive; 2 harness error.
--selftest: runs one case on TSRun, then compares MUTATED copies of the cart result (one flipped screen bit, a
flipped data-stack cell, a flipped dictionary byte, a flipped EXROM-state byte, a call operand changed to
another symbol) which must each be reported as a difference, plus the unmutated pair, which must pass.
Exit 1 = every check behaved as expected (mutations detected: "a difference was reported"); exit 2 = the
comparator missed a mutation or failed the unmutated pair.

EMULATOR LIMITS (no hardware exists here; nothing below proves real cartridge behaviour): ZEsarUX runs 50 Hz
frames and, through ts2068_debug, with --emulatorspeed 1000 (host timing only); TSRun runs 60 Hz frames and its
DOCK/EXROM model is a re-implementation (insertDock: DOCK chunk N is what port $F4 bit N selects when port $FF
bit 7 is clear; with bit 7 set the stock EXROM answers instead).  Both agreeing is two emulators agreeing.
Ports: only --port (default 10930, must be within 10930-10949).  Each ZEsarUX run has a private
TS2068_DEBUG_STATE_DIR (mktemp) and is always terminated at the end (also on exceptions).
"""
import argparse, base64, bisect, copy, json, os, re, shutil, subprocess, sys, tempfile, time

sys.dont_write_bytecode = True
HOME = os.path.expanduser("~")
ZDIR = os.environ.get("TS2068_DEBUG_ZESARUX_DIR", HOME + "/Applications/ZEsarUX-13.0")
TSRUN_SRC = os.environ.get("TSRUN_DIR", HOME + "/TSRun")
STOCK0, STOCK1 = HOME + "/fuse-build/roms/tc2068-0.rom", HOME + "/fuse-build/roms/tc2068-1.rom"
NOT_ADDRESS = {"PI_M", "TWO_PI_M", "HALF_PI_M", "TABLE_STEP_M", "DEG_CONST_M", "CPU_CLOCK_M"}
CONTROL = "1 2 + ."
RAM0, RAMLEN = 0x4000, 0xC000


class HarnessError(Exception):
    pass


# ----------------------------------------------------------------------------------------------- cases
# (name, [lines][, (row, col)]).  Decimal numbers.  Stack effects from core/rectfill.asm, core/polygon.asm, core/sprite.asm.
BIGPOLY = ["128 5 170 20 220 60 240 110 220 160 170 185", "128 188 80 185 30 160 10 110 30 60 80 20 12"]
CASES = [
    ("rect_basic", ["10 10 30 30 RECT"]),
    ("rect_reversed_colour", ["2 INK 6 PAPER", "150 120 110 90 RECT", "5 INK 1 PAPER 200 20 180 60 RECT"]),
    ("rect_span_cells", ["1 INK 3 PAPER 3 5 77 41 RECT", "6 INK 0 PAPER 7 100 8 101 RECT",
                         "4 INK 2 PAPER 250 180 255 191 RECT"]),
    ("polygon", ["4 INK 100 40 140 40 100 80 3 POLYGON", "2 INK 150 100 200 90 230 130 210 170 170 160 5 POLYGON"]),
    ("polygon_fill", ["100 40 140 40 100 80 3 POLYGON-FILL", "6 INK 50 50 90 70 50 90 65 70 4 POLYGON-FILL"]),
    ("sprite_define", ["2 INK 40 40 55 55 RECT", "0 5 5 SPRITE-DEFINE", "5 INK 100 60 115 75 RECT",
                       "1 7 12 SPRITE-DEFINE"]),
    ("sprite_show", ["2 INK 40 40 55 55 RECT", "0 5 5 SPRITE-DEFINE", "CLS", "0 10 10 SPRITE-SHOW"]),
    ("sprite_hide", ["2 INK 40 40 55 55 RECT", "0 5 5 SPRITE-DEFINE", "CLS", "0 10 10 SPRITE-SHOW",
                     "0 SPRITE-HIDE"], (10, 10)),   # 3rd item: the 2x2 cells (row, col) that must be blank again
    ("stack_kept", ["1 2 3 10 10 30 30 RECT 5 S>F"]),
    ("nested_big_polygon", ["3 INK 20 20 230 20 230 170 20 170 4 POLYGON",
                            "5 INK " + BIGPOLY[0], BIGPOLY[1] + " POLYGON-FILL",
                            "1 INK " + BIGPOLY[0], BIGPOLY[1] + " POLYGON"]),
    ("loop_rect", [": BARS 240 0 DO I 7 AND INK I I 63 AND 2 * I 7 + I 63 AND 2 * 9 + RECT LOOP ;", "BARS"]),
    ("loop_all_six", ["VARIABLE K",
                      ": R1 K @ 5 * 10 K @ 5 * 30 + 50 RECT ;",
                      ": P1 K @ 5 * 4 + 100 K @ 5 * 40 + 100 K @ 5 * 20 + 140 3 POLYGON ;",
                      ": P2 K @ 5 * 4 + 120 K @ 5 * 40 + 120 K @ 5 * 20 + 160 3 POLYGON-FILL ;",
                      ": S1 0 2 2 SPRITE-DEFINE 0 12 K @ SPRITE-SHOW 0 SPRITE-HIDE ;",
                      ": ALL 30 0 DO I K ! K @ 7 AND INK R1 P1 P2 S1 LOOP ;", "ALL"]),
    ("compiled_rect_twice", [": SQ 2DUP 40 + SWAP 40 + SWAP RECT ;", "20 20 SQ", "3 INK 1 PAPER 100 80 SQ"]),
]
SELFTEST_CASE = ("selftest", [": SQ 2DUP 40 + SWAP 40 + SWAP RECT ;", "1 2 3", "20 20 SQ", "5 S>F",
                              "4 INK 0 5 5 SPRITE-DEFINE"])


# ----------------------------------------------------------------------------------------------- symbols
class Syms:
    """One build's .sym: by_name, and addr -> NAME+OFF for ROM addresses ($0100-$3FFF)."""

    def __init__(self, path):
        self.by_name, rows = {}, []
        if not os.path.isfile(path):
            raise HarnessError("symbol file missing: " + path)
        for line in open(path):
            m = re.match(r"^(\S+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
            if m:
                a = int(m.group(2), 16)
                self.by_name[m.group(1)] = a
                if 0x100 <= a < 0x4000 and m.group(1) not in NOT_ADDRESS:
                    rows.append((a, "." in m.group(1), len(m.group(1)), m.group(1)))
        rows.sort()
        self.rows = [(r[0], r[3]) for r in rows]
        self.addrs = [r[0] for r in self.rows]

    def __getitem__(self, name):
        if name not in self.by_name:
            raise HarnessError("symbol %s not in .sym" % name)
        return self.by_name[name]

    def name(self, addr):
        i = bisect.bisect_right(self.addrs, addr) - 1
        if i < 0:
            return "?"
        a, n = self.rows[i]
        return n if a == addr else "%s+%d" % (n, addr - a)


class Build:
    def __init__(self, kind, dir_, dck=None):
        self.kind, self.dir = kind, os.path.abspath(dir_)
        b = self.dir + "/build/"
        if kind == "home":
            self.rom0, self.exrom, self.dck = b + "forth_boot_rom0.bin", b + "graphics_exrom.bin", None
            self.syms = Syms(b + "forth_boot.sym")
        else:
            self.rom0, self.exrom = STOCK0, STOCK1
            self.dck = os.path.abspath(dck) if dck else b + "forth_boot.dck"
            self.syms = Syms(b + "forth_boot_cart.sym")
        for f in (self.rom0, self.exrom) + ((self.dck,) if self.dck else ()):
            if not os.path.isfile(f):
                raise HarnessError("missing file " + f)
        s = self.syms
        self.idle = (s["IO_READ_KEY.wait_hit"], s["IO_READ_KEY.wait_hit"] + 5)
        self.dstack_top, self.fstack_top = s["DSTACK_TOP"], s["FSTACK_TOP"]
        self.dict0, self.here, self.latest = s["FORTH_DICT_RAM"], s["HERE"], s["LATEST"]
        self.depth_addr, self.edit_len, self.edit_buf = s["BANK_EXROM_DEPTH"], s["EDIT_LEN"], s["EDIT_BUF"]
        # raw-compared EXROM-side state.  Left out on purpose: PORT_FF_SHADOW (bit 7 = HOME pages the EXROM,
        # CART pages DOCK chunk 5: differs by design) and the keyboard/ISR/FRAMES cells ($829C-$82EC, host-timing).
        self.regions = [("gfx-fill/rect/poly cells", s["GFX_FILL_SP"], s["POLY_FILL_ERR_ADDR"] + 2),
                        ("sprite cells + paging depth", s["SPRITE_SLOT_DEFINED"], s["BANK_EXROM_DEPTH"] + 1),
                        ("sprite-bufs", s["SPRITE_SLOT_IMG_BUF"], s["SPRITE_SLOT_BG_BUF"] + 144)]


# ----------------------------------------------------------------------------------------------- run results
class Result:
    """What one emulator run of one build produced."""

    def __init__(self, build, emu):
        self.build, self.emu = build, emu
        self.ram = b""            # $4000-$FFFF
        self.ix = self.iy = 0
        self.alive = False
        self.page5_out = False
        self.depth_max = None
        self.attempts = 0
        self.typed = []
        self.notes = []

    def mem(self, a, n):
        return self.ram[a - RAM0:a - RAM0 + n]

    def word(self, a):
        m = self.mem(a, 2)
        return m[0] | m[1] << 8


# ----------------------------------------------------------------------------------------------- TSRun
DRIVER = r"""
// written by cart_diff.py.  arg1 = job.json, stdout = one JSON object.
import { createMachine, resetMachine, runFrame, insertDock } from './machine.js';
import fs from 'fs';
const job = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const rd = (p) => new Uint8Array(fs.readFileSync(p));
const km = new Uint8Array(8).fill(0xFF), js = new Uint8Array(2).fill(0xFF);
const m = createMachine(km, js);
m.homeRom.set(rd(job.rom0)); m.exRom.set(rd(job.exrom));
if (job.dck) { const e = insertDock(m, rd(job.dck)); if (e) { console.log(JSON.stringify({error: 'insertDock: ' + e})); process.exit(0); } }
resetMachine(m);
let depthMax = 0;                       // spy on stores to BANK_EXROM_DEPTH after boot
let spy = false;
const origWrite = m.bus.write;
m.bus.write = (a, v) => { if (spy && a === job.depthAddr && v > depthMax) depthMax = v; origWrite(a, v); };
// key matrix rows 0..7 (A8..A15), bit 0..4, active low.  \u0001 = CAPS SHIFT, \u0002 = SYMBOL SHIFT
const ROWS = ['\u0001zxcv', 'asdfg', 'qwert', '12345', '09876', 'poiuy', '\nlkjh', ' \u0002mnb'];
const POS = {};
ROWS.forEach((r, i) => [...r].forEach((c, b) => { POS[c] = [i, b]; }));
const SYM = {':':'z','?':'c','/':'v','<':'r','>':'t','!':'1','@':'2','#':'3','$':'4','%':'5','_':'0',')':'9','(':'8',"'":'7','&':'6','"':'p',';':'o','=':'l','+':'k','-':'j','.':'m',',':'n','*':'b'};
function keysFor(ch) {                  // [modifier..., key]; Forth words are upper case: CAPS SHIFT + letter
  if (SYM[ch]) return [POS['\u0002'], POS[SYM[ch]]];
  if (ch >= 'A' && ch <= 'Z') return [POS['\u0001'], POS[ch.toLowerCase()]];
  if (POS[ch]) return [POS[ch]];
  throw new Error('no key for ' + JSON.stringify(ch));
}
let nframes = 0;
const frames = (n) => { for (let i = 0; i < n; i++) runFrame(m); nframes += n; };
function press(keys) {                  // shift down, key down (hold), key up, shift up (gap), in frames
  const mods = keys.slice(0, -1), main = keys[keys.length - 1];
  for (const [r, b] of mods) km[r] &= ~(1 << b);
  frames(2);
  km[main[0]] &= ~(1 << main[1]); frames(job.hold);
  km[main[0]] |= (1 << main[1]); frames(2);
  for (const [r, b] of mods) km[r] |= (1 << b);
  frames(job.gap);
}
const u16 = (a) => m.ram[a] | (m.ram[a + 1] << 8);
function idle() {                       // a frame ends with the interrupt taken: PC=$0038, return address on the stack
  let pc = m.cpu.pc;
  if (pc === 0x38) pc = u16(m.cpu.sp);
  return pc >= job.idleLo && pc < job.idleHi && m.ram[job.editLen] === 0;
}
function waitIdle(maxFrames) {
  for (let n = 1; n <= maxFrames; n++) { frames(1); if (n >= 3 && idle()) return {ok: true, frames: n}; }
  return {ok: false, frames: maxFrames};
}
const out = {lines: [], boot: waitIdle(job.bootFrames)};
let alive = out.boot.ok;
spy = true;
for (const line of (alive ? job.lines : [])) {
  for (const ch of line) press(keysFor(ch));
  const len = m.ram[job.editLen];       // what the editor really holds, before ENTER
  const typed = String.fromCharCode(...m.ram.slice(job.editBuf, job.editBuf + len));
  press([POS['\n']]);
  const w = waitIdle(job.lineFrames);
  out.lines.push({line, typed, ok: w.ok, frames: w.frames});
  if (!w.ok) { alive = false; break; }
}
out.alive = alive;
out.ram = Buffer.from(m.ram.slice(0x4000)).toString('base64');
out.regs = {ix: m.cpu.xh << 8 | m.cpu.xl, iy: m.cpu.yh << 8 | m.cpu.yl, pc: m.cpu.pc, portF4: m.portF4, portFF: m.portFF};
out.depthMax = depthMax; out.frames = nframes;
console.log(JSON.stringify(out));
"""


def prepare_tsrun(tmp):
    """Private copy of TSRun (+ package.json marking it ES modules; ~/TSRun itself is not touched)."""
    d = tmp + "/tsrun"
    os.makedirs(d)
    if not os.path.isfile(TSRUN_SRC + "/machine.js"):
        raise HarnessError("TSRun source not found in " + TSRUN_SRC)
    for f in os.listdir(TSRUN_SRC):
        if f.endswith(".js"):
            shutil.copy(TSRUN_SRC + "/" + f, d)
    open(d + "/package.json", "w").write('{"type":"module"}')
    open(d + "/driver.mjs", "w").write(DRIVER)
    return d


def run_tsrun(b, lines, tsdir, tmp):
    node = shutil.which("node")
    if not node:
        raise HarnessError("node not found")
    job = dict(rom0=b.rom0, exrom=b.exrom, dck=b.dck, depthAddr=b.depth_addr, idleLo=b.idle[0], idleHi=b.idle[1],
               editLen=b.edit_len, editBuf=b.edit_buf, hold=4, gap=3, bootFrames=3000, lineFrames=6000, lines=lines)
    jf = tempfile.mktemp(prefix="job.", suffix=".json", dir=tmp)
    json.dump(job, open(jf, "w"))
    p = subprocess.run([node, "driver.mjs", jf], cwd=tsdir, capture_output=True, text=True, timeout=1800)
    try:
        d = json.loads(p.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError):
        raise HarnessError("TSRun driver failed: %s %s" % (p.stdout[-300:], p.stderr[-500:]))
    if "error" in d:
        raise HarnessError("TSRun: " + d["error"])
    r = Result(b, "tsrun")
    r.ram = base64.b64decode(d["ram"])
    r.ix, r.iy, r.alive = d["regs"]["ix"], d["regs"]["iy"], d["alive"] and d["boot"]["ok"]
    r.page5_out = not (d["regs"]["portF4"] & 0x20)
    r.depth_max = d["depthMax"]
    r.typed = [(x["line"], x["typed"]) for x in d["lines"]]
    r.notes.append("frames=%d" % d["frames"])
    if not d["boot"]["ok"]:
        r.notes.append("boot never reached the idle prompt")
    elif not r.alive:
        r.notes.append("no idle prompt after: " + d["lines"][-1]["line"][:50])
    return r


# ----------------------------------------------------------------------------------------------- ZEsarUX
def run_zesarux(b, lines, port, tmp):
    state = tempfile.mkdtemp(prefix="state.", dir=tmp)          # private TS2068_DEBUG_STATE_DIR per run
    os.environ["TS2068_DEBUG_STATE_DIR"] = state
    try:
        import ts2068_debug.process as proc
        from ts2068_debug.controller import Ts2068Debug
    except ImportError as e:
        raise HarnessError("ts2068_debug not importable: %s" % e)
    img = state + "/image.bin"
    with open(img, "wb") as f:
        f.write(open(b.rom0, "rb").read() + open(b.exrom, "rb").read())
    dbg = Ts2068Debug(ZDIR, port=port, romfile=img)
    dbg.start()
    pid = dbg._proc.pid
    try:
        z = dbg._zrcp
        if b.dck:
            z.command("smartload " + b.dck)
            z.command("hard-reset-cpu")
        r = Result(b, "zesarux")
        rd = lambda a, n: dbg.read_memory(a, n)

        def wait_idle(budget=40_000_000):
            dbg.pause()
            used, chunk = 0, 20_000
            while used < budget:
                v = dbg.get_registers().values
                pc = v["PC"]
                if pc == 0x38:
                    pc = int.from_bytes(rd(v["SP"], 2), "little")
                if b.idle[0] <= pc < b.idle[1] and rd(b.edit_len, 1)[0] == 0:
                    return True
                dbg.run(max_instructions=chunk)
                used += chunk
                chunk = min(chunk * 2, 500_000)
            return False

        r.alive = wait_idle()
        if not r.alive:
            r.notes.append("boot never reached the idle prompt")
        for line in (lines if r.alive else []):
            dbg.resume()
            z.command("send-keys-string 80 " + line, timeout=15 + 0.2 * len(line))   # blocks for len*80 ms
            time.sleep(0.08 * len(line) + 0.4)
            dbg.pause()
            n = rd(b.edit_len, 1)[0]
            r.typed.append((line, rd(b.edit_buf, n).decode("latin-1")))
            if r.typed[-1][1] != line:                              # harness typing error: stop, caller retries
                break
            dbg.resume()
            dbg.press_key("ENTER")
            time.sleep(0.4)
            if not wait_idle():
                r.alive = False
                r.notes.append("no idle prompt after: " + line[:50])
                break
        dbg.pause()
        r.ram = bytes(rd(RAM0, RAMLEN))
        v = dbg.get_registers().values
        r.ix, r.iy = v["IX"], v["IY"]
        r.page5_out = not (dbg.timex_state()["memory"]["port_f4"] & 0x20)
        return r
    finally:
        try:
            dbg.stop()
        except Exception:
            pass
        proc.terminate_emulator(pid, port, grace_s=3.0)
        shutil.rmtree(state, ignore_errors=True)


# ----------------------------------------------------------------------------------------------- screen text (OCR)
def font_glyphs(home):
    rom = open(home.rom0, "rb").read()
    ft = home.syms["FONT_TABLE"]
    return {bytes(rom[ft + i * 8:ft + i * 8 + 8]): c for i, c in enumerate(" 0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")}


def screen_text(scr, glyphs):
    rows = []
    for r in range(24):
        cells = [bytes(scr[((r >> 3) << 11) + (l << 8) + ((r & 7) << 5) + c] for l in range(8)) for c in range(32)]
        rows.append("".join(glyphs.get(x, "~") if any(x) else " " for x in cells))
    return rows


# ----------------------------------------------------------------------------------------------- comparison
def diff_count(a, b):
    return sum(1 for x, y in zip(a, b) if x != y) + abs(len(a) - len(b))


def cmp_dict(hb, cb, hs, cs):
    """Normalised dictionary compare -> (unexplained [(offset, h, c)], calls, words)."""
    bad, calls, words, i = [], 0, 0, 0
    n = min(len(hb), len(cb))
    while i < n:
        if hb[i] == cb[i]:
            i += 1
            continue
        for s in (i - 1, i):
            if s < 0 or s + 1 >= n:
                continue
            wh, wc = hb[s] | hb[s + 1] << 8, cb[s] | cb[s + 1] << 8
            if 0x100 <= wh < 0x4000 and 0x100 <= wc < 0x4000 and hs.name(wh) == cs.name(wc):
                if s >= 1 and hb[s - 1] == cb[s - 1] and hb[s - 1] in (0xCD, 0xC3):
                    calls += 1
                else:
                    words += 1
                i = s + 2
                break
        else:
            bad.append((i, hb[i], cb[i]))
            i += 1
    return bad, calls, words


def count_calls(d):
    """How many CD/C3 operands the dictionary holds that point into the ROM (context for the normalised count)."""
    return sum(1 for i in range(len(d) - 2) if d[i] in (0xCD, 0xC3) and 0x100 <= (d[i + 1] | d[i + 2] << 8) < 0x4000)


def blank_ok(R, area):
    """2x2 character cells at (row, col): bitmap all zero and the four attributes equal to the cell 4 columns on."""
    row, col = area
    scr = R.ram[:0x1B00]
    bm = [scr[((r >> 3) << 11) + (l << 8) + ((r & 7) << 5) + c] for r in (row, row + 1) for l in range(8) for c in (col, col + 1)]
    at = lambda r, c: scr[0x1800 + r * 32 + c]
    return not any(bm) and len({at(row, col), at(row, col + 1), at(row + 1, col), at(row + 1, col + 1), at(row, col + 4)}) == 1


def compare(case, H, C, glyphs, blank=None):
    """-> dict of metrics + verdict for one case/emulator pair (H, C = Result)."""
    hb, cb = H.build, C.build
    m = dict(case=case, emu=C.emu, problems=[])
    P = m["problems"]
    sh, sc = H.ram[:0x1B00], C.ram[:0x1B00]
    m["screen_diff"] = diff_count(sh, sc)
    m["screen_first"] = ["%04X:%02X/%02X" % (RAM0 + i, x, y) for i, (x, y) in enumerate(zip(sh, sc)) if x != y][:6]
    # stacks (cells are 2 bytes, stacks grow down from DSTACK_TOP / FSTACK_TOP)
    hd, cd = (hb.dstack_top - H.ix) // 2, (cb.dstack_top - C.ix) // 2
    hf, cf = (hb.fstack_top - H.iy) // 2, (cb.fstack_top - C.iy) // 2
    m["dstack_depth"], m["fstack_depth"] = (hd, cd), (hf, cf)
    sane = lambda r, top: 0x8000 <= r <= top
    sd = diff_count(H.mem(H.ix, hb.dstack_top - H.ix), C.mem(C.ix, cb.dstack_top - C.ix)) \
        if sane(H.ix, hb.dstack_top) and sane(C.ix, cb.dstack_top) else -1
    sf = diff_count(H.mem(H.iy, hb.fstack_top - H.iy), C.mem(C.iy, cb.fstack_top - C.iy)) \
        if sane(H.iy, hb.fstack_top) and sane(C.iy, cb.fstack_top) else -1
    m["stack_diff"] = (0 if (H.ix == C.ix and sd == 0) else max(sd, 1)) + (0 if (H.iy == C.iy and sf == 0) else max(sf, 1))
    # dictionary
    hh, ch = H.word(hb.here), C.word(cb.here)
    hl, cl = H.word(hb.latest), C.word(cb.latest)
    dh = H.mem(hb.dict0, max(0, hh - hb.dict0)) if hb.dict0 <= hh <= 0xF000 else b""
    dc = C.mem(cb.dict0, max(0, ch - cb.dict0)) if cb.dict0 <= ch <= 0xF000 else b""
    bad, calls, words = cmp_dict(dh, dc, hb.syms, cb.syms)
    m["dict_len"] = (len(dh), len(dc))
    m["dict_calls_total"] = count_calls(dh)
    latest_bad = not (hl == cl or (0x100 <= hl < 0x4000 and 0x100 <= cl < 0x4000 and hb.syms.name(hl) == cb.syms.name(cl)))
    words += hl != cl and not latest_bad          # LATEST pointing at a ROM word (nothing defined yet) is normalised too
    m["norm_calls"], m["norm_words"] = calls, words
    m["dict_diff"] = len(bad) + abs(len(dh) - len(dc)) + (hh != ch) + latest_bad
    m["dict_bad"] = ["+%04X:%02X/%02X" % x for x in bad[:6]]
    m["here"], m["latest"] = (hh, ch), (hl, cl)
    # EXROM-side state
    st = 0
    for (_, lo, hi), (_, lo2, hi2) in zip(hb.regions, cb.regions):
        st += diff_count(H.mem(lo, hi - lo), C.mem(lo2, hi2 - lo2))
    m["state_diff"] = st
    # paging + control line
    m["page5_out"] = H.page5_out and C.page5_out and H.mem(hb.depth_addr, 1) == b"\x00" == C.mem(cb.depth_addr, 1)
    ctl = lambda R: any(t.startswith("3 OK") for t in screen_text(R.ram[:0x1B00], glyphs))
    m["control_ok"] = (ctl(H), ctl(C))
    m["unresponsive"] = not C.alive
    m["restored"] = None if not blank else tuple(blank_ok(R, blank) for R in (H, C))
    # problems -> verdict
    if not C.alive:
        P.append("CART UNRESPONSIVE (" + "; ".join(C.notes) + ")")
    if m["screen_diff"]:
        P.append("screen differs in %d byte(s): %s" % (m["screen_diff"], " ".join(m["screen_first"])))
    if m["stack_diff"] or (hd, hf) != (cd, cf):
        P.append("stacks differ: data depth %d/%d float depth %d/%d IX %04X/%04X IY %04X/%04X" % (
            hd, cd, hf, cf, H.ix, C.ix, H.iy, C.iy))
    if m["dict_diff"]:
        P.append("dictionary differs: %d unexplained byte(s) %s HERE %04X/%04X LATEST %04X/%04X len %d/%d" % (
            len(bad), " ".join(m["dict_bad"]), hh, ch, hl, cl, len(dh), len(dc)))
    if st:
        P.append("EXROM-side state differs in %d byte(s)" % st)
    if not m["page5_out"]:
        P.append("chunk 5 still paged in / depth not 0 at idle")
    if not all(m["control_ok"]):
        P.append("control line did not print `3 OK` (home=%s cart=%s)" % m["control_ok"])
    if m["restored"] and not all(m["restored"]):
        P.append("sprite area %s not blank again after SPRITE-HIDE (home=%s cart=%s)" % ((blank,) + m["restored"]))
    m["verdict"] = "FAIL" if P else "PASS"
    return m


def fmt(m):
    s = "%s  %-22s %-8s screen=%d stack=%d dict=%d (normalised calls=%d words=%d, %d ROM calls in %dB) state=%d ctl=%s" % (
        m["verdict"], m["case"], m["emu"], m["screen_diff"], m["stack_diff"], m["dict_diff"], m["norm_calls"],
        m["norm_words"], m["dict_calls_total"], m["dict_len"][1], m["state_diff"], "ok" if all(m["control_ok"]) else "BAD")
    if m["restored"]:
        s += " restored=%s" % ("ok" if all(m["restored"]) else "BAD")
    return s + "".join("\n      - " + p for p in m["problems"])


# ----------------------------------------------------------------------------------------------- driver
def dump_result(dump, case, r):
    """--dump DIR: the RAM the comparison reads ($4000-$FFFF) and the registers/typing it used, one pair of files per
    run, named CASE.EMU.KIND.bin / .json so the dumps of two versions of this tool pair up (tools/cart_diff_dumpcmp.py)."""
    os.makedirs(dump, exist_ok=True)
    base = "%s/%s.%s.%s" % (dump, case, r.emu, r.build.kind)
    with open(base + ".bin", "wb") as f:
        f.write(r.ram)
    with open(base + ".json", "w") as f:
        json.dump(dict(case=case, emu=r.emu, kind=r.build.kind, ix=r.ix, iy=r.iy, alive=r.alive, page5_out=r.page5_out,
                       attempts=r.attempts, typed=r.typed, notes=r.notes), f, indent=1)


def run_pair(emu, case, lines, hb, cb, tmp, tsdir, port, dump=None):
    """Run one case on one emulator for both builds (fresh boot each), retrying keystroke errors."""
    out = []
    for b in (hb, cb):
        for attempt in range(1, 5):
            r = run_tsrun(b, lines + [CONTROL], tsdir, tmp) if emu == "tsrun" else run_zesarux(b, lines + [CONTROL], port, tmp)
            r.attempts = attempt
            bad = [(w, g) for w, g in r.typed if w != g]
            if not bad:
                break
            print("  (typing error on %s/%s/%s attempt %d: wanted %r got %r)" % (emu, b.kind, case, attempt, *bad[0]),
                  file=sys.stderr)
        else:
            raise HarnessError("keystrokes still wrong after 4 attempts on %s/%s/%s: %r" % (emu, b.kind, case, bad[0]))
        if b.kind == "home" and not r.alive:
            raise HarnessError("HOME build unresponsive on %s/%s: %s" % (emu, case, "; ".join(r.notes)))
        if dump:
            dump_result(dump, case, r)
        out.append(r)
    return out


def selftest(hb, cb, tmp, tsdir):
    """Comparator self-check on real TSRun results plus mutated copies of the cart result."""
    glyphs = font_glyphs(hb)
    H, C = run_pair("tsrun", SELFTEST_CASE[0], SELFTEST_CASE[1], hb, cb, tmp, tsdir, 0)
    here = C.word(cb.here)

    def mut(f):
        R = copy.copy(C)
        b = bytearray(C.ram)
        f(b)
        R.ram = bytes(b)
        return R

    def flip(a, bit):
        def f(b):
            b[a - RAM0] ^= bit
        return mut(f)

    def setw(a, w):
        def f(b):
            b[a - RAM0], b[a - RAM0 + 1] = w & 255, w >> 8
        return mut(f)

    # first CD operand in the user dictionary that points into the shifted ROM region
    d = C.mem(cb.dict0, here - cb.dict0)
    k = next(i for i in range(len(d) - 2) if d[i] == 0xCD and 0x1600 <= (d[i + 1] | d[i + 2] << 8) < 0x4000)
    tests = [
        ("unmutated cart (must PASS)", C, "PASS"),
        ("one flipped screen bit", flip(RAM0 + 0x100, 0x08), "FAIL"),
        ("flipped data-stack cell", flip(C.ix, 0x01), "FAIL"),
        ("flipped dictionary byte (a name byte)", flip(cb.dict0 + 3, 0x20), "FAIL"),
        ("CALL operand -> another symbol", setw(cb.dict0 + k + 1, (d[k + 1] | d[k + 2] << 8) + 3), "FAIL"),
        ("flipped EXROM-state byte (sprite buffer)", flip(cb.regions[2][1] + 4, 0x80), "FAIL"),
        ("HERE moved by one", setw(cb.here, here + 1), "FAIL"),
    ]
    bad = 0
    for name, R, want in tests:
        m = compare(SELFTEST_CASE[0], H, R, glyphs)
        bad += m["verdict"] != want
        print("selftest %-42s expected %s got %s  [%s]" % (name, want, m["verdict"], "ok" if m["verdict"] == want else "SELFTEST-MISS"))
        print("   " + fmt(m).replace("\n", "\n   "))
    print("selftest: %d/%d checks behaved as expected" % (len(tests) - bad, len(tests)))
    return 2 if bad else 1


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--home-dir", required=True)
    ap.add_argument("--cart-dir", required=True)
    ap.add_argument("--cart-dck", help="default: CART_DIR/build/forth_boot.dck")
    ap.add_argument("--emulators", default="zesarux,tsrun")
    ap.add_argument("--cases", help="comma list (default all): " + ",".join(c[0] for c in CASES))
    ap.add_argument("--port", type=int, default=10930, help="ZRCP port (10930-10949)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--dump", metavar="DIR", help="write every run's RAM ($4000-$FFFF) and IX/IY/typed lines to DIR "
                    "(CASE.EMU.KIND.bin/.json); compare two dumps with tools/cart_diff_dumpcmp.py")
    args = ap.parse_args()
    if not 10930 <= args.port <= 10949:
        print("port must be within 10930-10949", file=sys.stderr)
        return 2
    emus = [e for e in args.emulators.split(",") if e]
    if not set(emus) <= {"zesarux", "tsrun"}:
        print("--emulators: zesarux,tsrun", file=sys.stderr)
        return 2
    cases = CASES
    if args.cases:
        want = args.cases.split(",")
        cases = [c for c in CASES if c[0] in want]
        if len(cases) != len(want):
            print("unknown case in --cases", file=sys.stderr)
            return 2
    tmp = tempfile.mkdtemp(prefix="cart_diff.")
    try:
        hb, cb = Build("home", args.home_dir), Build("cart", args.cart_dir, args.cart_dck)
        glyphs = font_glyphs(hb)
        tsdir = prepare_tsrun(tmp)
        if args.selftest:
            return selftest(hb, cb, tmp, tsdir)
        results, infos, fails = [], [], 0
        for name, lines, *opt in cases:
            home_scr = {}
            for emu in emus:
                H, C = run_pair(emu, name, lines, hb, cb, tmp, tsdir, args.port, args.dump)
                m = compare(name, H, C, glyphs, opt[0] if opt else None)
                m["attempts"] = (H.attempts, C.attempts)
                m["tsrun_max_depth"] = (H.depth_max, C.depth_max) if emu == "tsrun" else None
                m["text_tail"] = [t for t in screen_text(C.ram[:0x1B00], glyphs) if t.strip()][-3:]
                results.append(m)
                fails += m["verdict"] != "PASS"
                home_scr[emu] = H.ram[:0x1B00]
                if not args.json:
                    print(fmt(m) + ("  [max BANK_EXROM_DEPTH home=%s cart=%s]" % (H.depth_max, C.depth_max) if emu == "tsrun" else "")
                          + ("  [attempts %d/%d]" % m["attempts"] if max(m["attempts"]) > 1 else ""), flush=True)
            if len(home_scr) == 2:
                n = diff_count(home_scr["zesarux"], home_scr["tsrun"])
                infos.append(dict(case=name, home_screen_zesarux_vs_tsrun_diff=n))
                if not args.json:
                    print("INFO  %-22s HOME screen ZEsarUX vs TSRun: %s" % (name, "identical" if not n else "%d byte(s) differ" % n))
        if args.json:
            print(json.dumps(dict(results=results, info=infos, failures=fails), indent=1, default=str))
        else:
            print("\n%d case/emulator pair(s), %d FAIL" % (len(results), fails))
        return 1 if fails else 0
    except HarnessError as e:
        print("HARNESS ERROR: %s" % e, file=sys.stderr)
        return 2
    except Exception as e:                    # ZRCP/transport/other tool failures are harness errors, never a verdict
        print("HARNESS ERROR: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 2
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
