#!/usr/bin/env python3
"""The DOCK cartridge on the stock TS2068 ROMs (make cart; docs/cartridge.md; kernel/bank/cart.asm): make test's
`cart` suite.

Programs are compiled on the release ROMs in ZEsarUX (lines run the IDE's way, Console.host_line), their dictionary,
LATEST and UDG table read back, and packed by tools/forthcart.py (as a SAVE-LIB tape would give them: read_lib's
fields).  Each case then runs its cartridge in ZEsarUX on the stock ROM (fharness.Machine with dck=: smartload) and
checks what the start word did and the state at the prompt:

  plain     no program: the prompt with the version on row 23, nothing printed
  hello     the start word's output, then OK and the prompt; LAST_ERROR 0; HERE, LATEST and the dictionary as on the
            release ROMs; the start word in the line store; ports $F4 = $03, $FF bit 7 = 0; the word runs again; an
            EXROM word (CIRCLE) works from DOCK chunk 5
  udg       the UDG table is copied
  error     an error in the start word (F/ by zero) is reported as a typed line's (LAST_ERROR -42), then the prompt
  break     BREAK stops the start word (LAST_ERROR -28), then the prompt
  largest   a dictionary of CART_IMG_MAX bytes (to $D000) loads; the load's T-states, the CRC's included
  bad-*     an image with another ROM's identity, a wrong CRC, a length over CART_IMG_MAX, a start word of length 0:
            "BAD PROGRAM", the dictionary empty, the version on row 23, the prompt
  tsrun     the hello cartridge on TSRun's core (tools/cartrun.mjs): the hand-off state, an interrupt forced before
            CART_ENTRY's `di` is harmless, only DOCK mappings of chunks 0-1 written, and the screen at the prompt is
            ZEsarUX's byte for byte (skipped, and said so, without node or ~/TSRun)

Ports 10920-10939.  EMULATOR LIMITS: ZEsarUX's and TSRun's Z80, SCLD and DOCK models with the stock ROM images; no
hardware.

Usage: carttest.py [--build DIR] [--cart DIR] [--workers N] [only ...]     (default build, build/cart)
"""
import argparse
import concurrent.futures as cf
import json
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fharness as fh   # noqa: E402
import forthcart        # noqa: E402
import tapes            # noqa: E402

ROOT = os.path.dirname(HERE)
PORT0 = 10920

PROGRAMS = {
    "hello": [': GO CLS ." HELLO CART" CR 6 7 * . ;'],
    "udg": [': GO ." UDG" ;', ": U 168 0 DO I 3 * 255 AND 0 UDG I + C! LOOP ; U"],
    "error": [": GO 1.0 0.0 F/ ;"],
    "break": [": GO BEGIN 0 UNTIL ;"],
}


def compile_programs(build, port):
    """{name: dict(dictionary, latest, identity, udg)} for PROGRAMS, compiled on the release ROMs."""
    m = fh.Machine(build, port)
    out = {}
    try:
        m.start()
        S = m.sym
        c = fh.Console(m)
        for name, lines in PROGRAMS.items():
            c.boot()
            for line in lines:
                c.host_line(line)
                if m.w16(S("LAST_ERROR")):
                    raise fh.HarnessError("%s: %r ended in error %d" % (name, line, m.w16(S("LAST_ERROR"))))
            here = m.w16(S("HERE"))
            out[name] = dict(dictionary=m.read(S("FORTH_DICT_RAM"), here - S("FORTH_DICT_RAM")),
                             latest=m.w16(S("LATEST")), identity=m.w16(S("ROM_IDENTITY")),
                             udg=m.read(S("UDG_TABLE"), S("UDG_COUNT") * 8))
    finally:
        m.stop()
    return out


def recrc(img):
    body = bytes(img[:-2])
    return body + struct.pack("<H", tapes.crc16(body))


def cases(S, progs):
    """[(name, image or None, check options)]."""
    def image(p, start="GO", dictionary=None):
        q = progs[p]
        return forthcart.program_image(S, dictionary if dictionary is not None else q["dictionary"], q["latest"],
                                       q["identity"], start, q["udg"])
    hello = image("hello")
    pad = progs["hello"]["dictionary"] + bytes(S["CART_IMG_MAX"] - len(progs["hello"]["dictionary"]))
    longest = bytearray(image("hello", dictionary=pad))
    other = bytearray(hello)
    other[2] ^= 1                                           # another ROM's identity
    crc = bytearray(hello)
    crc[S["CART_IMG_DICT"]] ^= 0x40                         # a dictionary byte changed, the CRC not
    over = bytearray(hello)
    struct.pack_into("<H", over, 4, S["CART_IMG_MAX"] + 1)  # longer than the dictionary's RAM
    nostart = bytearray(hello)
    nostart[S["CART_IMG_START"]] = 0
    return [("plain", None, {}), ("hello", hello, {}), ("udg", image("udg"), {}), ("error", image("error"), {}),
            ("break", image("break"), dict(hold_break=True)), ("largest", bytes(longest), {}),
            ("bad-identity", recrc(other), {}), ("bad-crc", bytes(crc), {}), ("bad-length", recrc(over), {}),
            ("bad-start", recrc(nostart), {})]


def run_case(cart, tmp, port, S, progs, name, img, opts):
    dck = os.path.join(tmp, name + ".dck")
    S_home = open(os.path.join(cart, "forth_boot_rom0.bin"), "rb").read()
    exrom = open(os.path.join(cart, "graphics_exrom.bin"), "rb").read()
    open(dck, "wb").write(forthcart.dck(S_home, exrom, img))
    m = fh.Machine(cart, port, dck=dck)
    timing = {}

    def handoff(m):
        """From the smartload: time the load (CART_ENTRY to the start word's run); BREAK held for `break`."""
        if m.run_to([S["CART_ENTRY"]], 20_000_000) != S["CART_ENTRY"]:
            raise fh.HarnessError("no hand-off to CART_ENTRY")
        m.tstates_reset()
        if img is not None and name.startswith(("hello", "largest")):
            if m.run_to([S["EDITOR_LOOP_LIVE.enter"]], 20_000_000) == S["EDITOR_LOOP_LIVE.enter"]:
                timing["load_t"] = m.tstates()
        if opts.get("hold_break"):
            m.run_to([S["EDITOR_LOOP_LIVE.enter"]], 20_000_000)
            for e in (fh.Z_CAPS, fh.Z_SPACE):
                m.cmd("send-keys-event %d 1" % e)
    m.power_on = handoff
    fails = []
    try:
        m.start(boot_max=40_000_000)
        if opts.get("hold_break"):
            for e in (fh.Z_SPACE, fh.Z_CAPS):
                m.cmd("send-keys-event %d 0" % e)
        c = fh.Console(m)
        c.boot()
        rows = m.screen_rows()
        screen = m.read(0x4000, 6912)
        err = m.w16(S["LAST_ERROR"])
        err = err - 0x10000 if err & 0x8000 else err
        here, latest = m.w16(S["HERE"]), m.w16(S["LATEST"])
        base = S["FORTH_DICT_RAM"]
        ports = m.cmd("get-io-ports")
        f4 = ports.split("Timex F4 port:")[1].split()[0]
        ff = int(ports.split("Timex FF port:")[1].split()[0], 16)

        def want(ok, what):
            if not ok:
                fails.append(what)
        want(c.in_editor(), "not at the prompt (the key wait returns to %04X)" % c.caller)
        want(f4 == "03" and not ff & 0x80, "ports $F4=$%s $FF=$%02X at the prompt" % (f4, ff))
        version = fh.version_text()
        if name == "plain" or name.startswith("bad-"):
            want(here == base and latest == S["DICT_LATEST_COLD"], "dictionary not empty: HERE %04X LATEST %04X"
                 % (here, latest))
            want(rows[23].strip() == version.strip(), "row 23 %r, not the version" % rows[23])
            want(rows[0] == ("BAD PROGRAM" if img else ""), "row 0 %r" % rows[0])
        else:
            prog = progs["largest" in name and "hello" or name]
            n = len(prog["dictionary"]) if name != "largest" else S["CART_IMG_MAX"]
            want(here == base + n and latest == prog["latest"], "HERE %04X LATEST %04X, not %04X %04X"
                 % (here, latest, base + n, prog["latest"]))
            want(m.read(base, len(prog["dictionary"])) == prog["dictionary"], "dictionary differs from the release's")
            store = m.read(S["STORE_START"], m.w16(S["STORE_END"]) - S["STORE_START"])
            want(store == b"GO\r", "line store %r, not the start word's line" % store)
        if name in ("hello", "largest"):
            want(rows[0] == "HELLO CART" and rows[1] == "42 OK", "rows %r" % rows[:2])
            want(err == 0, "LAST_ERROR %d" % err)
        if name == "hello":
            c.host_line("CLS GO")
            want(m.screen_rows()[:2] == ["HELLO CART", "42 OK"], "GO again: %r" % m.screen_rows()[:2])
            c.host_line("CLS 128 88 40 CIRCLE")
            scr = m.screen()
            circle = any(scr[(y & 0xC0) << 5 | (y & 7) << 8 | (y & 0x38) << 2 | 21] for y in range(80, 97))
            store = m.read(S["STORE_START"], m.w16(S["STORE_END"]) - S["STORE_START"])
            want(m.screen_rows()[0] == "OK" and circle and store.startswith(b"GO\r"),
                 "CIRCLE (the EXROM): row 0 %r, its right edge drawn %s, store %r (a restart empties it)"
                 % (m.screen_rows()[0], circle, store[:20]))
        if name == "udg":
            want(m.read(S["UDG_TABLE"], S["UDG_COUNT"] * 8) == progs["udg"]["udg"], "UDG table not copied")
            want(rows[0] == "UDGOK", "rows %r" % rows[:1])        # (OK follows the output, as for a typed line)
        if name == "error":
            want(err == -42 and any("DIVISION BY ZERO" in r for r in rows), "error %d, rows %r" % (err, rows[:3]))
        if name == "break":
            want(err == -28 and any("BREAK" in r for r in rows), "error %d, rows %r" % (err, rows[:3]))
        detail = ", ".join(fails) or "ok"
        if timing:
            detail += "; dictionary %d B, load %s T" % (here - base, timing.get("load_t", "-"))
        return dict(ok=not fails, detail=detail, screen=screen.hex() if name == "hello" else None,
                    load_t=timing.get("load_t"))
    except Exception as e:                      # noqa: BLE001
        return dict(ok=False, detail="TASK FAILED %s: %s" % (type(e).__name__, e))
    finally:
        m.stop()


def tsrun_case(cart, tmp, zscreen):
    tsrun = os.environ.get("TSRUN", os.path.expanduser("~/TSRun"))
    if not shutil.which("node") or not os.path.isfile(os.path.join(tsrun, "machine.js")):
        return dict(ok=True, skipped=True, detail="SKIPPED: needs node and TSRun at %s" % tsrun)
    r = subprocess.run(["node", os.path.join(HERE, "cartrun.mjs"), "--dck", os.path.join(tmp, "hello.dck"),
                        "--sym", os.path.join(cart, "forth_boot.sym"), "--irq-at-entry"],
                       capture_output=True, text=True, timeout=300)
    if r.returncode:
        return dict(ok=False, detail="cartrun: " + r.stderr.strip())
    d = json.loads(r.stdout)
    fails = []
    h = d.get("handoff") or {}
    if h.get("portF4") != "$23" or h.get("sp") is None:
        fails.append("hand-off %r" % h)
    if not (d.get("irqTaken") and d.get("irqReturned")):
        fails.append("the interrupt at the hand-off was not taken and returned")
    if not d.get("prompt"):
        fails.append("no prompt")
    if d["badPaging"]:
        fails.append("paging " + "; ".join(d["badPaging"][:3]))
    if zscreen and d["screen"] != zscreen:
        diff = sum(a != b for a, b in zip(bytes.fromhex(d["screen"]), bytes.fromhex(zscreen)))
        fails.append("screen differs from ZEsarUX's in %d bytes" % diff)
    return dict(ok=not fails, detail=", ".join(fails) or "ok: hand-off at frame %s (IFF1 %s, SP %s), prompt at frame %s, "
                "$F4 written %s" % (h.get("frame"), h.get("iff1"), h.get("sp"), d.get("promptFrame"),
                                    "/".join(d["f4Values"])))


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--cart", default=os.path.join(ROOT, "build", "cart"))
    ap.add_argument("--workers", type=int, default=None)
    ap.add_argument("only", nargs="*")
    a = ap.parse_args(argv)
    t0 = time.time()
    if not os.path.isfile(os.path.join(a.cart, "forth_cart.dck")):
        print("cart: FAIL no cartridge build in %s (make cart)" % a.cart)
        return 1
    S, _, _ = forthcart.load_build(a.cart)
    progs = compile_programs(a.build, PORT0)
    todo = [t for t in cases(S, progs) if not a.only or any(o in t[0] for o in a.only)]
    tmp = tempfile.mkdtemp(prefix="carttest-")
    workers = max(1, min(a.workers or fh.default_workers(), len(todo), 19))
    results = {}
    try:
        with cf.ThreadPoolExecutor(workers) as ex:
            free = list(range(PORT0 + 1, PORT0 + 1 + workers))
            futs = {}

            def submit(t):
                port = free.pop()
                f = ex.submit(run_case, a.cart, tmp, port, S, progs, *t)
                futs[f] = (t[0], port)
            pending = list(todo)
            while pending and free:
                submit(pending.pop(0))
            while futs:
                done, _ = cf.wait(list(futs), return_when=cf.FIRST_COMPLETED)
                for f in done:
                    name, port = futs.pop(f)
                    results[name] = f.result()
                    free.append(port)
                    if pending:
                        submit(pending.pop(0))
        if "hello" in results:                      # TSRun runs the hello case's cartridge
            results["tsrun"] = tsrun_case(a.cart, tmp, results["hello"].get("screen"))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    bad = 0
    for name, r in results.items():
        bad += not r["ok"]
        print("cart: %s %-12s %s" % ("ok  " if r["ok"] else "FAIL", name, r["detail"]))
    print("cart: %d/%d cases pass; wall %.0f s" % (len(results) - bad, len(results), time.time() - t0))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
