#!/usr/bin/env python3
"""Leap-Forth RAM layout guard (after 2068-Leap-C's tools/check_ram_layout.py).

A static census of every RAM address the two images reference, proved against the map of
include/forth_layout.inc. A name counts as referenced when it appears in an emitted code or data line of
build/forth_boot.lst (HOME, $0000-$3FFF) or build/graphics_exrom.lst (EXROM, $A000-$BFFF), or in the
definition of such a name (EQU closure). Every referenced name whose value is a RAM address ($4000-$FFFF) must be:
  - a display file 1 address ($4000 up to GFX_FILL_SHADOW: SCREEN_ADDR, ATTR_ADDR);
  - a cell: RAM_CELLS_BASE .. RAM_CELLS_END (the cells block);
  - a region or high-cell name the image may use (REGION_NAMES: HOME only, EXROM only or both), whose value is
    the map's;
  - a value or an address that is not RAM (VALUES: tape header parameter, I/O ports, EXROM image addresses).
Anything else -- a cell in a stack, the dictionary, the line store, FILL's areas for HOME, free space, the unused
top -- is an error. The tool also checks:
  (a) the map: the regions tile $4000-$FFFF in the order of the header of include/forth_layout.inc, with the
      documented overlaps (display file 2 and ZX_SYSVAR_CHARS inside FILL's areas);
  (c) every RAM-valued name of the two .sym files is defined in include/forth_layout.inc (SCREEN_ADDR and ATTR_ADDR
      in include/hardware.inc; VALUES where they say), found in the sources;
  (d) no source in core/ kernel/ rom/ include/ other than forth_layout.inc and hardware.inc has a literal RAM
      address ($4000-$FFFF as $xxxx, 0xxxxx or five decimal digits) in a code line;
  (s) the constants the EXROM keeps its own copy of (SHARED) have HOME's values.
--negative assembles the HOME image with each negative control of tests/layout_negctl.asm (-DLAYOUT_NEGCTL=n) and
requires the guard to report each one.

Usage: check_ram_layout.py [--build DIR] [--negative] [--quiet]
"""
import argparse
import glob
import os
import re
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAYOUT = "include/forth_layout.inc"
LINE = re.compile(r"^\s*\d+\+*\s*([0-9A-F]{4})\s?(~?)\s*((?:[0-9A-F]{2} )*)\s*(.*)$")
IDENT = re.compile(r"[A-Za-z_.][A-Za-z0-9_.]*")
EQU = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_.]*):?\s+(?i:equ)\s+(.*)")
DEFINITION = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*):?(\s|$)")

EXROM_BASE, EXROM_END = 0xA000, 0xC000      # the image, assembled at chunk 5

# Region and high-cell names by who may reference them: H = HOME code, X = EXROM code. Their values are the map's.
REGION_NAMES = {
    "GFX_FILL_SHADOW": "X", "GFX_FILL_STACK": "X",                      # FILL's areas: the EXROM only
    "ZX_SYSVAR_CHARS": "H", "SECOND_DISPLAY_ADDR": "H",                 # the printer's CHARS, HIRES (FILL does nothing there)
    "FSTACK_LIMIT": "H", "FSTACK_TOP": "H", "DSTACK_LIMIT": "H", "DSTACK_TOP": "H",
    "FORTH_DICT_RAM": "H", "DICT_RAM_CEILING": "H",
    "STORE_START": "HX", "LOADTEXT_BUF": "H", "STORE_LIMIT": "HX",
    "SPRITE_SLOT_IMG_BUF": "X", "SPRITE_SLOT_BG_BUF": "X",
    "UDG_TABLE": "H", "COLD_CLEAR_END": "H",
    "GFX_LINE_X0": "HX", "GFX_LINE_Y0": "HX", "GFX_LINE_X1": "HX", "GFX_LINE_Y1": "HX",
    "MACHINE_STACK_TOP": "H",
}
# Names whose value is not a RAM address although it is $4000 or more, with the file that defines them.
VALUES = {
    "STORAGE_NO_AUTOSTART": ("kernel/storage/storage.asm", "tape header parameter 1 (bit 15 set: do not autostart)"),
    "PORT_ULAPLUS_SELECT": ("include/hardware.inc", "I/O port $BF3B"),
    "PORT_ULAPLUS_DATA": ("include/hardware.inc", "I/O port $FF3B"),
    "GRAPHICS_EXROM_BASE": ("include/graphics_exrom_abi.inc", "EXROM image address"),
    "GRAPHICS_EXROM_MAGIC_ADDR": ("include/graphics_exrom_abi.inc", "EXROM image address"),
}
# RAM addresses that are hardware, not layout
HARDWARE = {"SCREEN_ADDR", "ATTR_ADDR"}
# constants the EXROM copies from HOME (rom/graphics_exrom.asm): HOME's value must equal the copy
SHARED = ("EDIT_MAX_LEN",)
# literal values that are not RAM addresses, with the reason; (file, value) or (None, value) for any file
LITERAL_VALUES = {
    (None, 0xFFFF): "all ones: a 16-bit -1, an 'unknown' marker or a count to the end of the address space",
    (None, 0xFFFE): "a 16-bit -2: the EXROM view's 'unknown row' marker",
    ("kernel/math/math.asm", 0x4000): "the fixed-point 'one' (2^14)",
}
# lines whose numbers are not code operands: directives and data (as 2068-Leap-C's guard)
DIRECTIVE = re.compile(r"\s*([A-Za-z_][A-Za-z0-9_.]*:?\s+)?(?i:equ|assert|org|ds|defs|db|dw|defb|defw|savebin|device)\b")


def symbols(path):
    out = {}
    for line in open(path):
        m = re.match(r"(\S+?):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
        if m:
            out.setdefault(m.group(1), int(m.group(2), 16))
    return out


def census(listing, lo, hi):
    """(referenced names with the first address that uses them, EQU-defined names)"""
    used, deps, equs = {}, {}, set()
    for raw in open(listing, errors="replace"):
        m = LINE.match(raw)
        if not m or m.group(2):
            continue
        addr, code = int(m.group(1), 16), m.group(4).split(";", 1)[0]
        d = EQU.match(code)
        if d:
            equs.add(d.group(1))
            deps.setdefault(d.group(1), set()).update(IDENT.findall(d.group(2)))
            continue
        if m.group(3).strip() and lo <= addr < hi:
            for t in IDENT.findall(re.sub(r"^\s*[A-Za-z_.][A-Za-z0-9_.]*:", "", code)):
                used.setdefault(t, addr)
    work = list(used)
    while work:
        n = work.pop()
        for t in deps.get(n, ()):
            if t not in used:
                used[t] = used[n]
                work.append(t)
    return used, equs


def source_files(extra=()):
    files = []
    for pat in ("core/*.asm", "kernel/*/*.asm", "rom/*.asm", "include/*.inc"):
        files += sorted(glob.glob(os.path.join(ROOT, pat)))
    files = [os.path.relpath(f, ROOT) for f in files]
    return files + list(extra)


def strip_comment(line):
    """The line without its ; comment (a ; inside a quoted string or character does not start one)."""
    q = None
    for i, c in enumerate(line):
        if q:
            if c == q:
                q = None
        elif c in "\"'":
            q = c
        elif c == ";":
            return line[:i]
    return line


def literals(extra=()):
    """Literal RAM addresses in code lines (d)."""
    errs = []
    num = re.compile(r"(\$[0-9A-Fa-f]{4}\b|0x[0-9A-Fa-f]{4}\b|\b[1-9][0-9]{4}\b)")
    for f in source_files(extra):
        if f in (LAYOUT, "include/hardware.inc"):
            continue
        for i, raw in enumerate(open(os.path.join(ROOT, f), errors="replace"), 1):
            code = strip_comment(raw.rstrip("\n"))
            if not code.strip() or DIRECTIVE.match(code):
                continue
            code = re.sub(r"\"[^\"]*\"|'[^']*'", "", code)
            for mm in num.finditer(code):
                t = mm.group(1)
                v = int(t[1:], 16) if t[0] == "$" else int(t, 0)
                if 0x4000 <= v <= 0xFFFF and (f, v) not in LITERAL_VALUES and (None, v) not in LITERAL_VALUES:
                    errs.append("%s:%d: literal RAM address %s" % (f, i, t))
    return errs


def definitions(extra=()):
    """name -> [(file, line)] for every name defined at column 0 of a source (a label, EQU, DEFS, DEFL)."""
    defs = {}
    for f in source_files(extra):
        for i, raw in enumerate(open(os.path.join(ROOT, f), errors="replace"), 1):
            m = DEFINITION.match(raw)
            if m:
                defs.setdefault(m.group(1), []).append((f, i))
    return defs


def check(build, quiet=False, extra=()):
    S = symbols(os.path.join(build, "forth_boot.sym"))
    X = symbols(os.path.join(build, "graphics_exrom.sym"))
    errors = []
    need = ["GFX_FILL_SHADOW", "GFX_FILL_STACK", "GFX_FILL_STACK_END", "SECOND_DISPLAY_ADDR", "SECOND_DISPLAY_END",
            "ZX_SYSVAR_CHARS", "RAM_CELLS_BASE", "RAM_CELLS_END", "FSTACK_LIMIT", "FSTACK_TOP", "DSTACK_LIMIT",
            "DSTACK_TOP", "FORTH_DICT_RAM", "DICT_RAM_CEILING", "STORE_START", "STORE_LIMIT", "SPRITE_SLOT_IMG_BUF",
            "SPRITE_SLOT_BG_BUF", "SPRITE_SLOT_MAX", "SPRITE_SLOT_BYTES", "UDG_TABLE", "UDG_COUNT", "COLD_CLEAR_END",
            "GFX_LINE_X0", "GFX_LINE_Y0", "GFX_LINE_X1", "GFX_LINE_Y1", "MACHINE_STACK_LIMIT", "MACHINE_STACK_TOP",
            "SCREEN_ADDR", "ATTR_ADDR"]
    gone = [n for n in need if n not in S]
    if gone:
        return 1, ["the HOME symbols lack %s" % ", ".join(gone)]
    g = lambda n: S[n]
    sprite_end = g("SPRITE_SLOT_BG_BUF") + g("SPRITE_SLOT_MAX") * g("SPRITE_SLOT_BYTES")
    # ---- (a) the map: tiles in order; each ends where the next begins
    tiles = [("display file 1", g("SCREEN_ADDR"), g("ATTR_ADDR") + 768),
             ("FILL's shadow plane", g("GFX_FILL_SHADOW"), g("GFX_FILL_STACK")),
             ("FILL's seed stack", g("GFX_FILL_STACK"), g("GFX_FILL_STACK_END")),
             ("the cells block", g("RAM_CELLS_BASE"), g("RAM_CELLS_END")),
             ("the float stack", g("FSTACK_LIMIT"), g("FSTACK_TOP")),
             ("the data stack", g("DSTACK_LIMIT"), g("DSTACK_TOP")),
             ("the dictionary", g("FORTH_DICT_RAM"), g("DICT_RAM_CEILING")),
             ("the line store", g("STORE_START"), g("STORE_LIMIT")),
             ("the sprite buffers", g("SPRITE_SLOT_IMG_BUF"), sprite_end),
             ("free space", sprite_end, g("UDG_TABLE")),
             ("the UDG table", g("UDG_TABLE"), g("UDG_TABLE") + g("UDG_COUNT") * 8),
             ("free space", g("UDG_TABLE") + g("UDG_COUNT") * 8, g("GFX_LINE_X0")),
             ("LINE's cells", g("GFX_LINE_X0"), g("GFX_LINE_Y1") + 1),
             ("the machine stack", g("MACHINE_STACK_LIMIT"), g("MACHINE_STACK_TOP")),
             ("the unused top", g("MACHINE_STACK_TOP"), 0x10000)]
    if tiles[0][1] != 0x4000:
        errors.append("the map: display file 1 starts at $%04X, not $4000" % tiles[0][1])
    for (n1, _, e1), (n2, b2, _) in zip(tiles, tiles[1:]):
        if e1 != b2:
            errors.append("the map: %s ends at $%04X, %s starts at $%04X" % (n1, e1, n2, b2))
    for n, b, e in tiles:
        if not b < e:
            errors.append("the map: %s is empty or reversed ($%04X-$%04X)" % (n, b, e - 1))
    if g("GFX_FILL_SHADOW") + 6144 != g("GFX_FILL_STACK"):
        errors.append("the map: FILL's shadow plane is not 6144 bytes")
    if g("GFX_LINE_Y0") != g("GFX_LINE_X0") + 1 or g("GFX_LINE_X1") != g("GFX_LINE_X0") + 2 or \
            g("GFX_LINE_Y1") != g("GFX_LINE_X0") + 3:
        errors.append("the map: GFX_LINE_X0, _Y0, _X1, _Y1 are not four consecutive bytes")
    d2, d2end = g("SECOND_DISPLAY_ADDR"), g("SECOND_DISPLAY_END")
    if not (g("GFX_FILL_SHADOW") <= d2 and d2end <= g("GFX_FILL_STACK_END") and d2end - d2 == 6144):
        errors.append("the map: display file 2 ($%04X-$%04X) is not 6144 bytes inside FILL's areas" % (d2, d2end - 1))
    if not (g("GFX_FILL_SHADOW") <= g("ZX_SYSVAR_CHARS") and g("ZX_SYSVAR_CHARS") + 2 <= g("GFX_FILL_STACK")):
        errors.append("the map: ZX_SYSVAR_CHARS is not inside FILL's shadow plane")
    if g("STORE_LIMIT") & 0xFF:
        errors.append("STORE_LIMIT $%04X is not page aligned (LOAD-TEXT compares the high byte)" % g("STORE_LIMIT"))
    if g("COLD_CLEAR_END") != tiles[10][2]:
        errors.append("COLD_CLEAR_END is $%04X, the UDG table ends at $%04X" % (g("COLD_CLEAR_END"), tiles[10][2]))
    where = lambda v: next((n for n, b, e in tiles if b <= v < e), "?")
    # ---- (s) the constants the EXROM copies
    for n in SHARED:
        if S.get(n) is None or X.get(n) != S[n]:
            errors.append("%s is %s in HOME and %s in the EXROM" % (n, S.get(n), X.get(n)))
    # ---- (b) the census
    rows = []
    for name, listing, lo, hi, own, who in (("HOME", "forth_boot.lst", 0, 0x4000, S, "H"),
                                            ("EXROM", "graphics_exrom.lst", EXROM_BASE, EXROM_END, X, "X")):
        used, _ = census(os.path.join(build, listing), lo, hi)
        for n, at in sorted(used.items()):
            v = own.get(n, S.get(n, X.get(n)))
            if v is None or v < 0x4000:
                continue
            if n in VALUES:
                kind = "value or port"
            elif who == "X" and EXROM_BASE <= v < EXROM_END and n not in REGION_NAMES:
                kind = "EXROM label"                     # (code and tables of the image itself)
            elif n in REGION_NAMES:
                if who not in REGION_NAMES[n]:
                    errors.append("%s code at $%04X references %s = $%04X, which only %s code may use"
                                  % (name, at, n, v, "HOME" if REGION_NAMES[n] == "H" else "EXROM"))
                    continue
                kind = "region or high cell"
            elif n in HARDWARE or g("SCREEN_ADDR") <= v < g("GFX_FILL_SHADOW"):
                kind = "display file 1"
            elif g("RAM_CELLS_BASE") <= v < g("RAM_CELLS_END"):
                kind = "cell"
            else:
                errors.append("%s code at $%04X references %s = $%04X %s %s"
                              % (name, at, n, v, "in" if where(v) != "?" else "outside the map:", where(v)))
                continue
            rows.append((name, n, v, kind))
    # ---- (c) every RAM-valued name is defined in the layout
    defs = definitions(extra)
    names = {}
    for img, D in (("HOME", S), ("EXROM", X)):
        for n, v in D.items():
            if v >= 0x4000 and "." not in n:
                names.setdefault(n, (v, img))
    nlayout = 0
    for n, (v, img) in sorted(names.items()):
        sites = defs.get(n, [])
        files = {f for f, _ in sites}
        if n in VALUES:
            if VALUES[n][0] not in files:
                errors.append("%s ($%04X, %s) is not defined in %s" % (n, v, VALUES[n][1], VALUES[n][0]))
            continue
        if n in HARDWARE:
            if "include/hardware.inc" not in files:
                errors.append("%s = $%04X is not defined in include/hardware.inc" % (n, v))
            continue
        if img == "EXROM" and EXROM_BASE <= v < EXROM_END and LAYOUT not in files:
            continue                                     # an EXROM image label or EQU
        if LAYOUT in files:
            nlayout += 1
            outside = [f for f in files if f != LAYOUT]
            if outside:
                errors.append("%s = $%04X is also defined outside %s: %s:%d" % (n, v, LAYOUT, *next(s for s in sites if s[0] != LAYOUT)))
            continue
        errors.append("%s = $%04X is a RAM address defined outside %s: %s"
                      % (n, v, LAYOUT, ", ".join("%s:%d" % s for s in sites[:3]) or "(definition not found)"))
    # ---- (d) no literal RAM address in code
    errors += literals(extra)
    if errors:
        if not quiet:
            for e in errors:
                print("check_ram_layout: " + e, file=sys.stderr)
        return 1, errors
    if not quiet:
        kinds = {}
        for _, _, _, k in rows:
            kinds[k] = kinds.get(k, 0) + 1
        nh = len({n for r, n, _, _ in rows if r == "HOME"})
        nx = len({n for r, n, _, _ in rows if r == "EXROM"})
        print("check_ram_layout: OK: %d RAM names referenced by HOME code and %d by EXROM code (%s); map tiles "
              "$4000-$FFFF; cells end $%04X; %d RAM names, all defined in %s; no literal RAM addresses"
              % (nh, nx, ", ".join("%d %s" % (v, k) for k, v in sorted(kinds.items())), g("RAM_CELLS_END"), nlayout, LAYOUT))
    return 0, []


def negative():
    """Each negative control must be reported."""
    srcname = "tests/layout_negctl.asm"
    src = open(os.path.join(ROOT, srcname)).read()
    ids = sorted(set(int(x) for x in re.findall(r"LAYOUT_NEGCTL\s*==\s*(\d+)", src)))
    expect = dict((int(a), b) for a, b in re.findall(r";\s*control (\d+): expect `([^`]+)`", src))
    bad = []
    for k in ids:
        with tempfile.TemporaryDirectory() as t:
            r = subprocess.run([os.path.join(ROOT, "tools", "sjasmplus_strict.sh"), "--nologo", "--outprefix=%s/" % t,
                                "-DLAYOUT_NEGCTL=%d" % k, "--sym=%s/forth_boot.sym" % t, "--lst=%s/forth_boot.lst" % t,
                                "rom/forth_boot.asm"], cwd=ROOT, capture_output=True, text=True)
            if r.returncode != 0:
                bad.append("control %d does not assemble: %s" % (k, (r.stdout + r.stderr)[-300:]))
                continue
            for f in ("graphics_exrom.sym", "graphics_exrom.lst"):
                os.symlink(os.path.join(ROOT, "build", f), os.path.join(t, f))
            code, errs = check(t, quiet=True, extra=[srcname])
            hit = [e for e in errs if expect.get(k, "\0") in e]
            if code == 0 or not hit:
                bad.append("control %d (%s) was not reported: %s" % (k, expect.get(k), errs))
            else:
                print("check_ram_layout: negative control %d reported: %s" % (k, hit[0]))
    for b in bad:
        print("check_ram_layout: NEGATIVE CONTROL FAILED: " + b, file=sys.stderr)
    if not bad:
        print("check_ram_layout: all %d negative controls reported" % len(ids))
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--negative", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    if a.negative:
        return negative()
    return check(a.build, a.quiet)[0]


if __name__ == "__main__":
    sys.exit(main())
