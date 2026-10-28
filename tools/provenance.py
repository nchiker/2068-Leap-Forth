#!/usr/bin/env python3
"""Provenance check of the production images against the stock ROMs.

Every run of MIN (12) or more bytes that a production image shares, byte for byte, with a stock ROM is
listed with its place in the image (the routine, from the sjasmplus listing's labels; and the source file the
listing says that address was assembled from) and in the stock ROM. A run is accepted only if it is recorded
in ALLOWED below with a reason and an owning step, or is mostly one byte repeated (fewer than MIN other
bytes: an $FF fill, which the stock ROMs have too; windows of one repeated byte are not compared at all).

The stock ROMs are read from the directory in $FORTH_STOCK_ROMS (default: ~/fuse-build/roms, Fuse's source
tree) and are never stored in this repository: 48.rom (the Spectrum 48K), tc2068-0.rom and tc2068-1.rom (the
TS2068's HOME ROM and EXROM). Only offsets and lengths are reported, never the stock bytes.

Address bases (what the listing's addresses mean for each image):
  * *_rom0.bin     HOME ROM image, assembled at ORG $0000: image offset == CPU address == listing address.
  * *_cart.bin     DOCK cartridge (-DCARTRIDGE) image: DOCK chunks 0-1, mapped at CPU $0000-$3FFF
                   (tools/make_dck.py wraps it as a .dck with header 00 02 02 00..., i.e. chunks 0 and 1).
                   The same source is assembled at the same ORG $0000 (rom/forth_boot.asm: "RST/NMI vectors
                   and COLD_START are at the same addresses in both builds"), so the base is $0000 too and
                   the listing's addresses are image offsets. The .lst used is the *_cart.lst, never the
                   HOME one (the two differ in the first 5 bytes, the LROS header, and in what -DCARTRIDGE
                   leaves out).
  * graphics_exrom.bin   EXROM image, assembled at ORG $A000 (its own listing); base $A000.

Exit status 0 when every run is accepted (or with --list-only), 1 otherwise, 2 when the stock ROMs are not
there (make skips the check then, saying so).

Usage: provenance.py [--build DIR] [--min N] [--roms DIR] [--list-only]
"""
import argparse
import bisect
import os
import re
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MIN = 12
STOCK = ("48.rom", "tc2068-0.rom", "tc2068-1.rom")

# (image, listing, base address of image offset 0, required)
IMAGES = (
    ("forth_boot_rom0.bin",             "forth_boot.lst",                0x0000, True),
    ("forth_boot_cart.bin",             "forth_boot_cart.lst",           0x0000, True),
    ("graphics_exrom.bin",              "graphics_exrom.lst",            0xA000, True),
    ("forth_demo_blackjack_rom0.bin",   "forth_demo_blackjack.lst",      0x0000, False),
    ("forth_demo_blackjack_cart.bin",   "forth_demo_blackjack_cart.lst", 0x0000, False),
    ("forth_demo_gallery_rom0.bin",     "forth_demo_gallery.lst",        0x0000, False),
)

# (top-level routine containing the run's first byte, length) -> {'reason': ..., 'owner': ...}
# The same source is assembled into several images, so a finding is recorded once, by routine, not per image.
# 'owner' is the step that owns the decision (e.g. the step that rewrites or justifies the routine).
# These are DEBT, not clearance: each entry is a stock-ROM-derived run that the owning step removes, and
# the entry is deleted in that step's commit (the "no longer found" note below reminds when it is stale).
_TAPE = {
    "reason": "tape block I/O: a port of the stock ROM's SA-BYTES / LD-BYTES (audit section 4.1, "
              "kernel/storage/storage.asm)",
    "owner": "step S (clean-room rebuild)",
}
ALLOWED = {
    ("STORAGE_SEND_BLOCK", 33): _TAPE,
    ("STORAGE_SEND_BLOCK", 19): _TAPE,
    ("STORAGE_SEND_BLOCK", 22): _TAPE,
    ("STORAGE_SEND_BLOCK", 13): _TAPE,
    ("STORAGE_RECEIVE_BLOCK", 45): _TAPE,
    ("STORAGE_RECEIVE_BLOCK", 31): _TAPE,
    ("STORAGE_RECEIVE_BLOCK", 32): _TAPE,
}

# ---------------------------------------------------------------------------------------------------------
# the byte-run search (as in 2068-Leap-C's tools/provenance.py)


def runs(img, rom, n):
    """[(image offset, rom offset, length)] of the maximal common runs of at least n bytes."""
    index = {}
    for j in range(len(rom) - n + 1):
        w = rom[j:j + n]
        if w.count(w[0]) != n:                              # (one byte repeated: fill, see trimmed())
            index.setdefault(w, []).append(j)
    out, seen = [], set()
    for i in range(len(img) - n + 1):
        for j in index.get(img[i:i + n], ()):
            if (i - j) in seen and i > 0 and j > 0 and img[i - 1] == rom[j - 1]:
                continue                                    # (inside a run already found)
            k = n
            while i + k < len(img) and j + k < len(rom) and img[i + k] == rom[j + k]:
                k += 1
            if i > 0 and j > 0 and img[i - 1] == rom[j - 1]:
                continue
            out.append((i, j, k))
            seen.add(i - j)
    return out


def trimmed(data):
    """The run without the repeated bytes at either end (the image's or the stock ROM's fill)."""
    a, z = 0, len(data)
    while a + 1 < z and data[a] == data[a + 1]:
        a += 1
    while z - 1 > a and data[z - 1] == data[z - 2]:
        z -= 1
    return data[a:z]


# ---------------------------------------------------------------------------------------------------------
# the listing: labels and source files
#
# sjasmplus listing lines look like  "  42+ 0270 AF               xor  a"  (line number, '+' per include
# nesting level, address, up to 4 bytes, source text); a "~" after the address marks a line in a skipped
# (IFNDEF-false) region. "# file opened: NAME" / "# file closed: NAME" bracket each included file, with the
# basename only; the full path comes from the INCLUDE "path" line that precedes the "opened" line.

LINE = re.compile(r"^\s*\d+\+*\s+([0-9A-F]{4})(\s~)?(?: ((?:[0-9A-F]{2} ?)+))?")
LABEL = re.compile(r"^\s*\d+\+*\s+([0-9A-F]{4})\s+(?:(?:[0-9A-F]{2} ?)+\s+)?(\.?[A-Za-z_][A-Za-z0-9_.]*):")
INCLUDE = re.compile(r'\bINCLUDE\s+"([^"]+)"', re.I)
OPENED = re.compile(r"^# file opened: (.+?)\s*$")
CLOSED = re.compile(r"^# file closed: (.+?)\s*$")


def read_listing(lst, lo, hi):
    """(labels, spans) for the listing `lst`, restricted to addresses in [lo, hi).

    labels: sorted [(address, top-level label, full label)], listing order kept for equal addresses; code
            labels only (`NAME:` at an address; EQU constants dropped). A local label `.x` is attached to
            the previous top-level label, as sjasmplus does: full label `TOP.x`.
    spans:  sorted [(address, source file)] of the lines that emit bytes (so a comment never claims an
            address), in listing order for equal addresses."""
    labels, spans = [], []
    stack, pending = [], None
    top = "?"
    for raw in open(lst, encoding="latin-1"):
        m = OPENED.match(raw)
        if m:
            base = m.group(1)
            path = pending if pending and os.path.basename(pending) == base else base
            if path == base:
                for cand in (os.path.join("rom", base), base):
                    if os.path.exists(os.path.join(ROOT, cand)):
                        path = cand
                        break
            stack.append(path)
            pending = None
            continue
        if CLOSED.match(raw):
            if stack:
                stack.pop()
            continue
        m = LINE.match(raw)
        if not m:
            continue
        src = raw.split(";", 1)[0]
        inc = INCLUDE.search(src)
        if inc:
            pending = inc.group(1)
        addr = int(m.group(1), 16)
        if m.group(2):
            continue                                        # (skipped region)
        if not lo <= addr < hi:
            continue
        if m.group(3) and stack:
            spans.append((addr, stack[-1]))
        lm = LABEL.match(raw)
        if lm and not re.search(r":\s+EQU\b", raw, re.I):
            name = lm.group(2)
            if name.startswith("."):
                labels.append((addr, top, top + name))
            else:
                top = name
                labels.append((addr, name, name))
    labels.sort(key=lambda x: x[0])                         # (stable)
    spans.sort(key=lambda x: x[0])
    return labels, spans


def routine_at(labels, addr):
    """(top-level label, full label, address of the full label) of the label at or before addr."""
    keys = [x[0] for x in labels]
    k = bisect.bisect_right(keys, addr) - 1
    if k < 0:
        return "?", "?", addr
    return labels[k][1], labels[k][2], labels[k][0]


def files_of(spans, a, z):
    """The source files the bytes [a, z) were assembled from (the one holding a first), in address order."""
    keys = [x[0] for x in spans]
    k = max(bisect.bisect_right(keys, a) - 1, 0)
    out = []
    while k < len(spans) and spans[k][0] < z:
        if spans[k][1] not in out:
            out.append(spans[k][1])
        k += 1
    return out or ["?"]


# ---------------------------------------------------------------------------------------------------------


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--min", type=int, default=MIN)
    ap.add_argument("--roms", default=os.environ.get("FORTH_STOCK_ROMS", os.path.expanduser("~/fuse-build/roms")))
    ap.add_argument("-v", "--verbose", action="store_true", help="print every run, allowed ones too")
    ap.add_argument("--list-only", action="store_true",
                    help="print every run found (for triage) and exit 0 whatever the ALLOWED table says")
    a = ap.parse_args()
    roms = {}
    for r in STOCK:
        p = os.path.join(a.roms, r)
        if not os.path.exists(p):
            print("provenance: SKIPPED: the stock ROMs are not in %s (set FORTH_STOCK_ROMS)" % a.roms)
            return 2
        with open(p, "rb") as f:
            roms[r] = f.read()
    bad = total = scanned = 0
    allowed_n = {}
    used = set()
    for img_name, lst, base, required in IMAGES:
        ip = os.path.join(a.build, img_name)
        lp = os.path.join(a.build, lst)
        if not (os.path.exists(ip) and os.path.exists(lp)):
            if required:
                print("provenance: %s (or its listing %s) is missing from %s: not built" % (img_name, lst, a.build))
                bad += 1
            else:
                print("provenance: note: %s not built, not scanned" % img_name)
            continue
        with open(ip, "rb") as f:
            img = f.read()
        scanned += 1
        labs, spans = read_listing(lp, base, base + len(img))
        for rom_name, rom in roms.items():
            for i, j, k in runs(img, rom, a.min):
                total += 1
                addr = base + i
                top, full, laddr = routine_at(labs, addr)
                files = files_of(spans, addr, addr + k)
                fill = len(trimmed(img[i:i + k])) < a.min
                key = (top, k)
                ent = ALLOWED.get(key)
                if ent:
                    used.add(key)
                    why = "ALLOWED (owner: %s): %s" % (ent.get("owner", "?"), ent.get("reason", ""))
                elif fill:
                    why = "one byte repeated (fill)"
                else:
                    why = None
                    bad += 1
                place = top if full == top else "%s [%s]" % (top, full)
                if ent:
                    allowed_n[(top, ent.get("owner", "?"))] = allowed_n.get((top, ent.get("owner", "?")), 0) + 1
                if a.verbose or not (ent or fill):
                    print("provenance: %s $%04X (%s+%d) in %s = %s $%04X, %d bytes: %s" % (
                        img_name, addr, place, addr - laddr, "+".join(files[:4]) + ("+..." if len(files) > 4 else ""),
                        rom_name, j, k, why or "NOT ACCOUNTED FOR"))
    for (top, owner), n in sorted(allowed_n.items()):
        print("provenance: allowed debt: %d runs in %s (owner: %s)" % (n, top, owner))
    if not a.list_only:
        for key in ALLOWED:
            if key not in used:
                print("provenance: note: the recorded run %s (%d bytes) is no longer found in any image" % key)
    print("provenance: %d images, %d common runs of %d bytes or more, %d not accounted for" % (
        scanned, total, a.min, bad))
    return 0 if a.list_only else (1 if bad else 0)


if __name__ == "__main__":
    sys.exit(main())
