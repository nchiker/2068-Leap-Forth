#!/usr/bin/env python3
"""Per-component ROM budgets and the reserve (after 2068-Leap-C's tools/budget.py; CONTRIBUTING.md).

Reads budget.toml and the production listings and symbols in build/. Every byte from an image's start to its
last non-pad byte belongs to the source file that emitted it (the listing's `# file opened:` marks); a component is a
list of files and/or [start_label, end_label) ranges (a range takes its bytes away from its file; "$end" is the end of
the code). It prints each image's components against their budgets (the base budget plus the ledger's changes) and the
reserve (the free bytes after the last non-pad byte). Exit 1 when a component is over its budget, a byte belongs to
no component or a file to two, or a reserve is below its floor.

Usage: budget.py [--build DIR] [--json OUT]"""
import argparse
import collections
import json
import os
import re
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LINE = re.compile(r"^\s*\d+\+*\s+([0-9A-F]{4})\s?(~?)\s*((?:[0-9A-F]{2} )*)")


def symbols(path):
    out = {}
    for line in open(path):
        m = re.match(r"(\S+?):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
        if m:
            out.setdefault(m.group(1), int(m.group(2), 16))
    return out


def owners(listing, base, end):
    """The source file (basename) of every byte base..end-1, from the listing."""
    stack, rows = [], []
    for raw in open(listing, errors="replace"):
        if raw.startswith("# file opened: "):
            stack.append(raw[15:].strip())
        elif raw.startswith("# file closed: "):
            stack.pop()
        else:
            m = LINE.match(raw)
            if m and stack:
                rows.append((int(m.group(1), 16), stack[-1]))
    own = [None] * (end - base)
    for (a, f), (b, _) in zip(rows, rows[1:]):
        if base <= a < b <= base + 0x10000 and a < end:
            for x in range(a, min(b, end)):
                own[x - base] = f
    return own


def image_report(name, cfg, build, ledger):
    data = open(os.path.join(build, cfg["image"]), "rb").read()
    n = len(data)
    while n and data[n - 1] == cfg.get("pad", 0xFF):
        n -= 1
    base, free = cfg["base"], len(data) - n
    syms = symbols(os.path.join(build, cfg["symbols"]))
    own = owners(os.path.join(build, cfg["listing"]), base, base + n)
    errors, comp_of = [], [None] * n
    file_comp = {}
    for c in cfg["component"]:
        for f in c.get("files", ()):
            if f in file_comp:
                errors.append("%s: file %s is in components %s and %s" % (name, f, file_comp[f], c["id"]))
            file_comp[f] = c["id"]
    for i, f in enumerate(own):
        comp_of[i] = file_comp.get(f)
    for c in cfg["component"]:
        for a, b in c.get("ranges", ()):
            lo = syms[a] - base
            hi = n if b == "$end" else syms[b] - base
            for i in range(lo, hi):
                comp_of[i] = c["id"]
    sizes = collections.Counter(x for x in comp_of if x)
    loose = collections.Counter(own[i] for i, x in enumerate(comp_of) if x is None)
    for f, k in loose.items():
        errors.append("%s: %d byte(s) of %s belong to no component" % (name, k, f))
    rows = []
    for c in cfg["component"]:
        delta = sum(e["delta"] for e in ledger if e["image"] == name and e["component"] == c["id"])
        budget = c["budget"] + delta
        size = sizes.get(c["id"], 0)
        rows.append(dict(id=c["id"], title=c["title"], size=size, budget=budget))
        if size > budget:
            errors.append("%s: component %s is %d B, %d B over its budget of %d B: shrink it, move cold code to the "
                          "EXROM, or reallocate with a ledger entry (budget.toml)" % (name, c["id"], size, size - budget,
                                                                                      budget))
    floor = cfg["reserve_floor"] + sum(e["delta"] for e in ledger if e["image"] == name and e["component"] == "reserve_floor")
    if free < floor:
        errors.append("%s: %d B free, below the reserve floor of %d B" % (name, free, floor))
    return dict(image=cfg["image"], free=free, floor=floor, end=base + n, components=rows), errors


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--json")
    a = ap.parse_args()
    with open(os.path.join(ROOT, "budget.toml"), "rb") as f:
        cfg = tomllib.load(f)
    ledger = cfg.get("ledger", [])
    reports, errors = [], []
    for name in ("home", "exrom"):
        r, e = image_report(name, cfg[name], a.build, ledger)
        reports.append(r)
        errors += e
        print("budget: %s (%s): code ends $%04X, %d B free, reserve floor %d B" % (name, r["image"], r["end"], r["free"],
                                                                               r["floor"]))
        for c in r["components"]:
            print("budget:   %-12s %5d / %5d B  %s%s" % (c["id"], c["size"], c["budget"], c["title"],
                                                     "  OVER" if c["size"] > c["budget"] else ""))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(dict(images=reports, errors=errors), f, indent=1)
    for e in errors:
        print("budget: FAIL: " + e)
    print("budget: %s" % ("FAIL" if errors else "OK: every component within its budget, every reserve at or above its floor"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
