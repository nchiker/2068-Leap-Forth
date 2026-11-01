#!/usr/bin/env python3
"""Compile a Forth source file on the release ROMs and write the SAVE-LIB tape it gives (the manual's Part 6; make
blackjack).

The source's lines are run at the prompt in ZEsarUX, headless (fharness.Console.host_line: the Leap IDE's way, as if
typed), from a fresh boot; then the dictionary, LATEST and the ROM's identity are read back and written as SAVE-LIB
writes them (tapes.lib_file: a type-3 header and the dictionary with its CRC), so `make cart PROG=OUT START=word` packs
it. The same as typing the source and saving it with SAVE-LIB, without a person or a tape deck.

  fs2lib.py [--build DIR] [--port P] [--name NAME] SRC.fs OUT.tap|OUT.tzx

  --build  the release build (default build)        --port  ZEsarUX's ZRCP port (default 10900, fharness's own)
  --name   the tape name, 1-10 characters (default the source's base name, upper case)

A line longer than the prompt takes (128 characters), a line that ends in an error, or a definition left open at the
end is refused, with its line number. EMULATOR LIMITS: ZEsarUX's Z80 and TS2068 model; no hardware.
"""
import argparse
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fharness as fh   # noqa: E402
import tapes            # noqa: E402

LINE_MAX = 128          # EDIT_BUF


class SourceError(Exception):
    pass


def compile_lines(m, lines):
    """Run `lines` at the prompt of the booted Machine m, from its boot snapshot; dict(dictionary, latest, identity,
    udg) as SAVE-LIB (and forthcart.read_lib) see them."""
    S = m.sym
    c = fh.Console(m)
    c.boot()
    for n, line in lines:
        if len(line) > LINE_MAX:
            raise SourceError("line %d: %d characters, more than the %d a line holds" % (n, len(line), LINE_MAX))
        c.host_line(line)
        err = m.w16(S("LAST_ERROR"))
        if err:
            raise SourceError("line %d ended in error %d: %r" % (n, err - 0x10000 if err & 0x8000 else err, line))
    if m.read(S("STATE"), 1)[0]:
        raise SourceError("a definition is still open at the end (no ;)")
    here = m.w16(S("HERE"))
    return dict(dictionary=m.read(S("FORTH_DICT_RAM"), here - S("FORTH_DICT_RAM")), latest=m.w16(S("LATEST")),
                identity=m.w16(S("ROM_IDENTITY")), udg=m.read(S("UDG_TABLE"), S("UDG_COUNT") * 8))


def source_lines(text):
    """[(line number, line)] of a source text, its blank lines left out."""
    return [(n, l.rstrip("\r")) for n, l in enumerate(text.split("\n"), 1) if l.strip()]


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default="build")
    ap.add_argument("--port", type=int, default=10900)
    ap.add_argument("--name")
    ap.add_argument("src")
    ap.add_argument("out")
    a = ap.parse_args(argv)
    name = a.name or os.path.splitext(os.path.basename(a.src))[0].upper()
    if not 1 <= len(name) <= 10:
        ap.error("the tape name must be 1-10 characters (%r)" % name)
    m = fh.Machine(fh.resolve_build(a.build), a.port)
    m.start()
    try:
        prog = compile_lines(m, source_lines(open(a.src).read()))
    except SourceError as e:
        sys.exit("fs2lib: %s: %s" % (a.src, e))
    finally:
        m.stop()
    blocks = tapes.lib_file(name, prog["dictionary"], prog["latest"], prog["identity"])
    with open(a.out, "wb") as f:
        f.write(tapes.tzx(blocks) if a.out.endswith(".tzx") else tapes.tap(blocks))
    print("fs2lib: %s: %s, a %d-byte dictionary" % (a.out, name, len(prog["dictionary"])))


if __name__ == "__main__":
    main(sys.argv[1:])
