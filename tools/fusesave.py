#!/usr/bin/env python3
"""SAVE-TEXT and SAVE-LIB recorded by Fuse 1.9.1 and decoded by an independent decoder (storage rebuild, step S).

A port of the `save` case of 2068-Leap-C's tools/fusetest.py to the Forth ROM.  For each word a headless Fuse
(tools/fusedrive.py) boots the build, a short definition is typed, Fuse's tape deck starts recording, the word is
run (`S" : DBL DUP + ; 21 DBL ." SAVE-TEXT TXTSAVE`; `SAVE-LIB LIBA` after `: SQ DUP * ; : CUBE DUP SQ * ;`) and
the recording is written as a TZX.  The ROM's own MIC edges are then decoded by fuse-utils, not by this project:
`tape2wav` renders the recording as audio and `audio2tape` decodes the audio back into blocks.  Those blocks are
compared with what docs/V2/STORAGE_SPEC.md section 4 says they must be:

  header block   flag $00, 17-byte payload, XOR checksum good: type (0 TEXT / 3 LIB), name (10, space padded),
                 data length (TEXT: the text length; LIB: dictionary length + 2), param 1 ($8000 / ROM_IDENTITY),
                 param 2 (text length / LATEST)
  data block     flag $FF, XOR checksum good: TEXT: the text bytes; LIB: the dictionary $9800..HERE-1 read from
                 Fuse's memory, then CRC-16/CCITT-FALSE of it, low byte then high byte

and SAVE-LIB must leave HERE and LATEST alone.  Then the recording is played into a fresh Fuse (tape traps off) with
LOAD-TEXT / LOAD-LIB, and so is the tape audio2tape made from the audio: the text must run (42), the library
must give back HERE, LATEST and the dictionary bytes and its word CUBE must work (5 CUBE . = 125).

Usage: fusesave.py [--build DIR] [--out FILE]      exit 0 = every check passed, 1 = any failed
LIMITS: Fuse's emulation of the ROM's own MIC writes, a software decoder; there is no hardware here.
"""
import argparse
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)                # (python3 -I does not put the script's directory on sys.path)
import fusedrive                        # noqa: E402
import tapes                            # noqa: E402

ROOT = os.path.dirname(HERE)
TEXT = b": DBL DUP + ; 21 DBL ."
LIB_SETUP = ": SQ DUP * ; : CUBE DUP SQ * ;"


def tzx_blocks(data):
    """The data blocks of a TZX file, as bytes: standard ($10), turbo ($11) and pure data ($14); pauses ($20), tones
    ($12) and pulse blocks ($13) are skipped; anything else is an error."""
    if data[:8] != b"ZXTape!\x1a":
        raise ValueError("not a TZX file")
    p, out = 10, []
    while p < len(data):
        t = data[p]
        p += 1
        if t == 0x10:
            n = struct.unpack_from("<H", data, p + 2)[0]
            out.append(bytes(data[p + 4:p + 4 + n]))
            p += 4 + n
        elif t == 0x11:
            n = int.from_bytes(data[p + 15:p + 18], "little")
            out.append(bytes(data[p + 18:p + 18 + n]))
            p += 18 + n
        elif t == 0x14:
            n = int.from_bytes(data[p + 7:p + 10], "little")
            out.append(bytes(data[p + 10:p + 10 + n]))
            p += 10 + n
        elif t == 0x20:
            p += 2
        elif t == 0x12:
            p += 4
        elif t == 0x13:
            p += 1 + 2 * data[p]
        else:
            raise ValueError("TZX block $%02X at %d is not one audio2tape writes" % (t, p - 1))
    return out


def independent_decode(tzx, work):
    """fuse-utils: tape2wav (recording -> audio), audio2tape (audio -> blocks).  Returns (blocks, decoded tzx path)."""
    wav, dec = os.path.join(work, "recorded.wav"), os.path.join(work, "decoded.tzx")
    for cmd in (["tape2wav", tzx, wav], ["audio2tape", wav, dec]):
        r = subprocess.run(cmd, capture_output=True, text=True)
        if r.returncode or not os.path.exists(cmd[-1]):
            raise RuntimeError("%s failed (status %d): %s" % (cmd[0], r.returncode, (r.stdout + r.stderr).strip()))
    return tzx_blocks(open(dec, "rb").read()), dec


def fields(h):
    return "type %d name %r length %d param1 $%04X param2 $%04X" % (h["type"], h["name"], h["length"], h["param1"], h["param2"])


class Report:
    def __init__(self, out):
        self.out, self.failed, self.n = out, 0, 0

    def line(self, text):
        self.out.append(text)
        print(text, flush=True)

    def check(self, label, ok, detail=""):
        self.n += 1
        self.failed += 0 if ok else 1
        self.line("fusesave: %-34s %s%s" % (label, "PASS" if ok else "FAIL", ("  " + detail) if detail else ""))
        return ok


def check_blocks(rep, label, blocks, want):
    """The decoded blocks against the expected framed blocks, field by field.  Returns True if both match."""
    if not rep.check(label + ": blocks decoded", len(blocks) == len(want),
                     "audio2tape found %d blocks of %s bytes, expected %d of %s bytes" % (
                         len(blocks), [len(b) for b in blocks], len(want), [len(b) for b in want])):
        return False
    ok = True
    for i, (b, w) in enumerate(zip(blocks, want)):
        flag, payload, xor_ok = tapes.unframe(b)
        wflag, wpayload, _ = tapes.unframe(w)
        ok &= rep.check("%s: block %d framing" % (label, i), flag == wflag and xor_ok,
                        "flag $%02X (want $%02X), XOR checksum %s, payload %d bytes" % (
                            flag if flag is not None else -1, wflag, "good" if xor_ok else "BAD", len(payload)))
        if i == 0:
            got, exp = tapes.parse_header(payload), tapes.parse_header(wpayload)
            ok &= rep.check("%s: header fields" % label, got == exp, "got  " + (fields(got) if got else "(not 17 bytes)"))
            rep.line("fusesave:   %-34s      want " % "" + fields(exp))
        else:
            same = payload == wpayload
            first = next((j for j in range(min(len(payload), len(wpayload))) if payload[j] != wpayload[j]), None)
            ok &= rep.check("%s: data bytes" % label, same,
                            "%d bytes" % len(payload) if same else "got %d bytes, want %d, first difference at %s" % (
                                len(payload), len(wpayload), first))
    return ok


def roundtrip(build, work, rep, label, tape, command, verify):
    """A fresh Fuse, `tape` in its deck, `command` typed; `verify(f)` returns (ok, detail) with Fuse still up."""
    f = fusedrive.Fuse(build, os.path.join(work, "rt"), extra=["--no-accelerate-loader"]).start()
    try:
        r = f.cmd("tape_open %s" % tape)
        if r != "0":
            return rep.check(label, False, "tape_open returned %s" % r)
        f.type(command, timeout=600)
        if not f.idle():
            return rep.check(label, False, "the prompt did not come back")
        ok, detail = verify(f)
        return rep.check(label, ok, detail)
    finally:
        f.stop()
        shutil.rmtree(os.path.join(work, "rt"), ignore_errors=True)


def screen_text(f):
    return " | ".join(r for r in f.rows() if r.strip())


def record(build, work, setup, command, snap):
    """Boot, type `setup`, record `command`, return (recording path, f.stop()ped state dict from snap(f))."""
    f = fusedrive.Fuse(build, os.path.join(work, "rec"), extra=["--no-accelerate-loader"]).start()
    try:
        for line in setup:
            f.type(line)
        before = snap(f)
        if f.cmd("tape_rec_start") != "0":
            raise RuntimeError("tape_rec_start failed")
        t0 = f.ping()
        f.type(command, timeout=600)
        t1 = f.ping()
        f.cmd("tape_rec_stop")
        rec = os.path.join(work, "recorded.tzx")
        if f.cmd("tape_write %s" % rec) != "0" or not os.path.exists(rec):
            raise RuntimeError("tape_write failed")
        returned = f.idle()
        after = snap(f)
        secs = ((t1[0] - t0[0]) * fusedrive.TPF + t1[1] - t0[1]) / fusedrive.CPU_HZ
        return rec, before, after, returned, secs, screen_text(f)
    finally:
        f.stop()
        shutil.rmtree(os.path.join(work, "rec"), ignore_errors=True)


def run(build, work, rep):
    S = fusedrive.load_syms(os.path.join(build, "forth_boot.sym"))
    rom = open(os.path.join(build, "forth_boot_rom0.bin"), "rb").read()
    ident = (rom[S["ROM_IDENTITY"]] | rom[S["ROM_IDENTITY"] + 1] << 8) if "ROM_IDENTITY" in S else None
    dict0 = S["FORTH_DICT_RAM"]

    def snap(f):
        here = f.w16(S["HERE"])
        return dict(here=here, latest=f.w16(S["LATEST"]), dict=f.peek(dict0, max(0, here - dict0)))

    rep.line("fusesave: build %s%s" % (build, "" if ident is not None else " (no ROM_IDENTITY: an old build)"))
    # ------------------------------------------------------------------------------------ SAVE-TEXT
    wd = os.path.join(work, "text")
    os.makedirs(wd)
    rec, before, after, returned, secs, screen = record(
        build, wd, [], 'S" %s" SAVE-TEXT TXTSAVE' % TEXT.decode(), snap)
    rep.check("SAVE-TEXT: returned", returned, "%.1f s emulated, screen: %s" % (secs, screen))
    try:
        blocks, dec = independent_decode(rec, wd)
    except Exception as e:
        rep.check("SAVE-TEXT: tape2wav + audio2tape", False, str(e))
        blocks = None
    if blocks is not None:
        check_blocks(rep, "SAVE-TEXT", blocks, tapes.text_file("TXTSAVE", TEXT))
        for what, tape in (("Fuse's recording", rec), ("audio2tape's tape", dec)):
            roundtrip(build, wd, rep, "SAVE-TEXT: LOAD-TEXT of %s" % what, tape, "LOAD-TEXT TXTSAVE",
                      lambda f: (" 42 " in " " + screen_text(f).replace("|", " ") + " ", "screen: " + screen_text(f)))
    # ------------------------------------------------------------------------------------ SAVE-LIB
    wd = os.path.join(work, "lib")
    os.makedirs(wd)
    rec, before, after, returned, secs, screen = record(build, wd, [LIB_SETUP], "SAVE-LIB LIBA", snap)
    rep.check("SAVE-LIB: returned", returned, "%.1f s emulated, screen: %s" % (secs, screen))
    rep.check("SAVE-LIB: HERE, LATEST, dictionary kept", before == after,
              "HERE $%04X LATEST $%04X, %d dictionary bytes (before: $%04X $%04X %d)" % (
                  after["here"], after["latest"], len(after["dict"]), before["here"], before["latest"], len(before["dict"])))
    try:
        blocks, dec = independent_decode(rec, wd)
    except Exception as e:
        rep.check("SAVE-LIB: tape2wav + audio2tape", False, str(e))
        blocks = None
    if blocks is not None:
        d = after["dict"]
        want = tapes.lib_file("LIBA", d, after["latest"], ident if ident is not None else 0)
        if ident is None:
            rep.check("SAVE-LIB: ROM_IDENTITY in the build", False,
                      "no ROM_IDENTITY symbol: header param 1 cannot carry the identity (checked against $0000)")
        check_blocks(rep, "SAVE-LIB", blocks, want)
        for what, tape in (("Fuse's recording", rec), ("audio2tape's tape", dec)):
            def verify(f, d=d):
                now = snap(f)
                bad = []
                if now["here"] != after["here"]:
                    bad.append("HERE $%04X, want $%04X" % (now["here"], after["here"]))
                if now["latest"] != after["latest"]:
                    bad.append("LATEST $%04X, want $%04X" % (now["latest"], after["latest"]))
                if now["dict"] != d:
                    bad.append("dictionary bytes differ")
                f.type("5 CUBE .")
                scr = screen_text(f)
                if " 125 " not in " " + scr.replace("|", " ") + " ":
                    bad.append("5 CUBE . did not print 125")
                return not bad, "; ".join(bad) or "HERE $%04X LATEST $%04X, %d bytes equal, 5 CUBE . -> 125" % (
                    now["here"], now["latest"], len(d))
            roundtrip(build, wd, rep, "SAVE-LIB: LOAD-LIB of %s" % what, tape, "LOAD-LIB LIBA", verify)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build"), help="image directory (default: build)")
    ap.add_argument("--out", help="write the report to this file as well as stdout")
    a = ap.parse_args()
    for tool in ("tape2wav", "audio2tape"):
        if not shutil.which(tool):
            raise SystemExit("fusesave: %s (fuse-utils) not found" % tool)
    build = os.path.abspath(a.build)
    for d in (build, os.path.join(build, "build")):
        if os.path.isfile(os.path.join(d, "forth_boot_rom0.bin")):
            build = d
            break
    else:
        raise SystemExit("fusesave: no forth_boot_rom0.bin in %s" % a.build)
    fusedrive.build_shim()
    work = tempfile.mkdtemp(prefix="fusesave.")
    out, t0 = [], time.time()
    rep = Report(out)
    try:
        run(build, work, rep)
    finally:
        shutil.rmtree(work, ignore_errors=True)
    rep.line("fusesave: emulator Fuse %s, tape traps off, loader acceleration off; decoder fuse-utils tape2wav + audio2tape" %
             fusedrive.fuse_version())
    rep.line("fusesave: %d checks, %d failed, %.0f s wall" % (rep.n, rep.failed, time.time() - t0))
    if a.out:
        with open(a.out, "w") as f:
            f.write("\n".join(out) + "\n")
    return 1 if rep.failed else 0


if __name__ == "__main__":
    sys.exit(main())
