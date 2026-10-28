#!/usr/bin/env python3
"""ROM reserve guard (audit step G, T4; owner decision 1). After 2068-Leap-C's tools/budget.py, reserve
part only: Forth has no per-component symbol ranges, so there are no components here.

Reads tools/budget.toml. For every image listed there, measures the free space in build/ the way the
audit did (the image size minus its trailing run of pad bytes: the last non-pad byte marks the end of
code and data) and compares it with

  floor   the ratchet: free space below it fails (exit 1)
  target  the owner's reserve target (200 B HOME, 150 B EXROM): reported as a distance, never fails

A missing image is a failure (make check builds them first). Free space above the floor is reported as a
note: raise the floor in the commit that recovered the space (see budget.toml's header).

Usage: budget.py [--build DIR] [--config FILE] [--json OUT]
"""
import argparse
import json
import os
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def free_bytes(data, pad):
    n = len(data)
    while n and data[n - 1] == pad:
        n -= 1
    return len(data) - n, n - 1            # free bytes, offset of the last non-pad byte


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--config", default=os.path.join(ROOT, "tools", "budget.toml"))
    ap.add_argument("--json")
    a = ap.parse_args()
    with open(a.config, "rb") as f:
        cfg = tomllib.load(f)
    pad = cfg["pad"]
    rows, errors = [], []
    for img in cfg["image"]:
        path = os.path.join(a.build, img["file"])
        if not os.path.exists(path):
            errors.append("%s: not built" % img["file"])
            continue
        data = open(path, "rb").read()
        free, last = free_bytes(data, pad)
        rows.append(dict(file=img["file"], title=img["title"], size=len(data), last=last, free=free,
                         floor=img["floor"], target=img["target"]))
        if free < img["floor"]:
            errors.append("%s: %d B free is below the floor of %d B (%d B lost). Recover the space, or lower the "
                          "floor explicitly with a ledger row (tools/budget.toml header)"
                          % (img["file"], free, img["floor"], img["floor"] - free))
    w = max((len(r["file"]) for r in rows), default=10)
    print("budget: %-*s %6s %6s %6s %7s  %s" % (w, "image", "free", "floor", "target", "to go", "last byte"))
    for r in rows:
        gap = r["target"] - r["free"]
        print("budget: %-*s %6d %6d %6d %7s  $%04X%s" % (
            w, r["file"], r["free"], r["floor"], r["target"],
            ("%d B" % gap) if gap > 0 else "met", r["last"],
            ("   (note: %d B above the floor: raise it)" % (r["free"] - r["floor"])) if r["free"] > r["floor"] else ""))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(dict(images=rows, errors=errors), f, indent=1)
    for e in errors:
        print("budget: FAIL: " + e)
    print("budget: %s" % ("FAIL" if errors else "OK: every image is at or above its floor"))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
