#!/usr/bin/env python3
"""Turn `jp` / `jp z|nz|c|nc` into `jr` wherever the assembled target is in relative range (audit O12; after
2068-Leap-C's tools/relax_jumps.py). A shrink aid, run by hand: it reads a listing, edits the given source
files in place and reports how many jumps changed. Rebuild and repeat until it reports 0 (shrinking only
moves targets closer, so a converted jump never goes out of range again; the strict assembler fails the
build if one does, e.g. in a ROM with a different layout).

A `jr` costs 12 T when taken (a `jp` 10) and 7 when a conditional one is not (a `jp` 10): it is smaller, not
faster. So this lists, with --list-only, every candidate with its file and line first; convert hot paths
only after the benchmarks (make bench) say it is free. Sites marked `; keep jp`, or whose comment says "JP, not JR", are
skipped (someone chose jp on purpose).

Usage: relax_jumps.py [--list build/forth_boot.lst] [--list-only] [--skip FILE:LINE ...] FILE.asm..."""
import argparse
import os
import re

OPS = {0xC3: "", 0xC2: "nz", 0xCA: "z", 0xD2: "nc", 0xDA: "c"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", default="build/forth_boot.lst")
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--margin", type=int, default=10,
                    help="stay this many bytes inside the +-127 range: tools/check_z80_opcodes.py flags "
                         "displacements within 10 bytes of the limit (default 10)")
    ap.add_argument("--skip", action="append", default=[], help="FILE:LINE to leave as jp")
    ap.add_argument("files", nargs="+")
    a = ap.parse_args()
    wanted = {f: f for f in a.files}
    skip = set(a.skip)
    stack = []                  # paths of the files being listed (from the INCLUDE line before each open)
    last_include = None
    edits = {}
    sites = []
    for line in open(a.list, encoding="latin-1"):
        m = re.match(r"# file opened: (.*)", line)
        if m:
            name = m.group(1).strip()
            # two files can share a basename (in different directories): the INCLUDE line
            # just before the open gives the path
            stack.append(last_include if last_include and last_include.endswith(name) else name)
            last_include = None
            continue
        m = re.match(r'\s*\d+\+*\s+(?:[0-9A-F]{4}\s+)?\s*INCLUDE\s+"([^"]+)"', line)
        if m:
            last_include = m.group(1)
        if re.match(r"# file closed", line):
            stack.pop()
            continue
        if not stack:
            continue
        m = re.match(r"\s*(\d+)\+*\s+([0-9A-F]{4})\s+((?:[0-9A-F]{2} )+)\s*(.*)$", line)
        if not m:
            continue
        # the listing names the file as the INCLUDE argument ("core/x.asm") or a bare name
        cur = stack[-1] if stack[-1] in wanted else (stack[-1] if stack[-1] == "forth_boot.asm" else None)
        if cur == "forth_boot.asm":
            cur = "rom/forth_boot.asm" if "rom/forth_boot.asm" in wanted else None
        if cur is None:
            continue
        lineno, addr = int(m.group(1)), int(m.group(2), 16)
        code = [int(x, 16) for x in m.group(3).split()]
        src = m.group(4)
        if len(code) != 3 or code[0] not in OPS or not re.match(r"\s*jp\s", src) or "keep jp" in src or re.search(r"not\s+JR", src, re.I):
            continue
        if "%s:%d" % (cur, lineno) in skip:
            continue
        d = (code[1] | code[2] << 8) - (addr + 2)
        if -128 + a.margin <= d <= 127 - a.margin:
            edits.setdefault(wanted[cur], set()).add(lineno)
            sites.append((cur, lineno, addr, src.strip()))
    for s in sites:
        print("relax_jumps: %s:%d $%04X %s" % s)
    if a.list_only:
        print("relax_jumps: %d candidates" % len(sites))
        return
    total = 0
    for f, lines in edits.items():
        src = open(f).read().split("\n")
        for n in lines:
            new = re.sub(r"\bjp(\s+)", r"jr\1", src[n - 1], count=1)
            if new != src[n - 1]:
                src[n - 1] = new
                total += 1
        open(f, "w").write("\n".join(src))
    print("relax_jumps: %d jumps changed to jr" % total)


if __name__ == "__main__":
    main()
