#!/usr/bin/env python3
"""ROM inventory: every routine and table of an image, its size, its referrers, and whether anything reaches it
(after 2068-Leap-C's tools/rom_inventory.py; read-only, `make inventory`).

From the production listing: each byte up to the code end is code, data (DB/DW), or DS fill; bytes are grouped by
top-level label (a routine or a table), and the routines by budget.toml component (budget.py's attribution). A cross
reference over the operands of every assembled line, plus fall-through into the next label, gives each routine's
referrers. Reachability from the roots (HOME: the reset, RST and NMI vectors, COLD_START, GRAPHICS_HOME_TABLE, every
dictionary word's code; EXROM: the service table) marks the routines nothing reaches (UNR): dead code, or reached in a
way the scan cannot see (a computed jump; such a routine is named in KNOWN with the reason).

Usage: rom_inventory.py [--image home|exrom] [--md] [--json FILE] [--unreachable]"""
import argparse
import json
import os
import re
import sys
import tomllib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import budget   # noqa: E402

ROOT = os.path.dirname(HERE)
LINE_RE = re.compile(r"^\s*(\d+)(\+*)\s*([0-9A-F]{4})(.*)$")
LABEL_RE = re.compile(r"^([A-Za-z_][\w]*|\.[\w]+)\s*(:|\s|$)")
IDENT_RE = re.compile(r"[A-Za-z_][\w.]*")
DATA_OPS = {"DB", "DEFB", "BYTE", "DM", "DEFM", "DZ", "DC", "ABYTE", "DW", "DEFW", "WORD", "DEFD"}
FILL_OPS = {"DS", "DEFS", "BLOCK"}
NOT_LABEL = {"EQU", "DEFL", "=", "MACRO"}
END_OPS = re.compile(r"^(ret|reti|retn|halt)\s*$|^(jp|jr)\s+(?![a-z]{1,2}\s*,)|^(jp\s+\((hl|ix|iy)\))", re.I)
KNOWN = {}      # routine -> why the scan cannot see its caller (none today)


def strip_comment(text):
    out, q = [], None
    for ch in text:
        if q:
            out.append(ch)
            if ch == q:
                q = None
        elif ch in "\"'":
            if ch == "'" and "".join(out).rstrip().lower().endswith("af"):     # `af'` is a register
                out.append(ch)
                continue
            q = ch
            out.append(ch)
        elif ch == ";":
            break
        else:
            out.append(ch)
    return "".join(out)


def parse_listing(path, lo, hi):
    """Rows (addr, size, kind, statement) for the bytes in [lo, hi), and the label definitions."""
    raw = []
    for line in open(path, encoding="latin-1"):
        m = LINE_RE.match(line.rstrip("\n"))
        if m:
            raw.append([int(m.group(1)), int(m.group(3), 16), m.group(4).startswith(" ~"), m.group(4)[:14],
                        m.group(4)[14:]])
    rows, labels, last_src, parent = [], [], {}, None
    for i, (num, addr, skipped, field, src) in enumerate(raw):
        if skipped:
            continue
        hexb = re.findall(r"\b[0-9A-F]{2}\b", field)
        if src.strip() == "" and hexb and num in last_src:
            src_eff = last_src[num]
        else:
            src_eff = src
            last_src[num] = src
        stmt = strip_comment(src_eff)
        lm = LABEL_RE.match(stmt)
        if lm:
            name = lm.group(1)
            after = stmt[lm.end(1):].lstrip(": \t").split()
            if not (after and after[0].upper() in NOT_LABEL) and name.upper() not in DATA_OPS | FILL_OPS:
                if src == src_eff:
                    if name.startswith("."):
                        label = "%s%s" % (parent, name) if parent else name
                    else:
                        label, parent = name, name
                    if lo <= addr < hi:
                        labels.append((addr, label))
                stmt = stmt[lm.end(1):].lstrip(": \t")
        if not hexb or not lo <= addr < hi:
            continue
        size = (next((r[1] for r in raw[i + 1:] if not r[2]), addr) - addr) if "..." in field else len(hexb)
        op = stmt.strip().split()[0].upper() if stmt.strip() else ""
        kind = "data" if op in DATA_OPS else "fill" if op in FILL_OPS else "code"
        rows.append((addr, size, kind, stmt.strip()))
    return rows, labels


def inventory(name, cfg, build):
    data = open(os.path.join(build, cfg["image"]), "rb").read()
    n = len(data)
    while n and data[n - 1] == cfg.get("pad", 0xFF):
        n -= 1
    base = cfg["base"]
    end = base + n
    rows, labels = parse_listing(os.path.join(build, cfg["listing"]), base, end)
    syms = budget.symbols(os.path.join(build, cfg["symbols"]))
    own = budget.owners(os.path.join(build, cfg["listing"]), base, end)
    file_comp = {f: c["id"] for c in cfg["component"] for f in c.get("files", ())}
    comp = [file_comp.get(f) for f in own]
    for c in cfg["component"]:
        for a, b in c.get("ranges", ()):
            for i in range(syms[a] - base, n if b == "$end" else syms[b] - base):
                comp[i] = c["id"]
    tops = {}
    for addr, lab in labels:
        if "." not in lab:
            tops[addr] = lab                     # the last label at an address names the routine
    starts = sorted(a for a in tops if a < end)
    if not starts or starts[0] != base:
        starts.insert(0, base)
        tops[base] = "(start)"
    kind_of = {}
    for addr, size, kind, _ in rows:
        for a in range(addr, addr + size):
            kind_of[a] = kind

    def owner(addr):
        best = None
        for s in starts:
            if s <= addr:
                best = s
            else:
                break
        return best
    names = {lab: owner(addr) for addr, lab in labels if base <= addr < end}
    for line in open(os.path.join(build, cfg["listing"]), encoding="latin-1"):    # NAME EQU LABEL counts as LABEL
        m = LINE_RE.match(line.rstrip("\n"))
        e = m and re.match(r"^([A-Za-z_]\w*)\s+EQU\s+([A-Za-z_]\w*)\s*(;|$)", m.group(4)[14:])
        if e and e.group(2) in names:
            names.setdefault(e.group(1), names[e.group(2)])
    edges = {}
    for addr, size, kind, stmt in rows:
        if kind == "fill":
            continue
        parts = stmt.split(None, 1)
        operands = parts[1] if len(parts) > 1 else ""
        if kind == "code" or parts and parts[0].upper() in ("DW", "DEFW"):
            for ident in IDENT_RE.findall(re.sub(r'"[^"]*"', "", operands)):
                if ident in names and names[ident] != owner(addr):
                    edges.setdefault(names[ident], set()).add(owner(addr))
    last = {}
    for addr, size, kind, stmt in sorted(rows):
        last[owner(addr)] = (kind, stmt)
    for a, b in zip(starts, starts[1:]):
        k = last.get(a)
        if k and k[0] == "code" and not END_OPS.match(k[1]):
            edges.setdefault(b, set()).add(a)
    if name == "home":
        vectors = set(range(0, 0x40, 8)) | {0x0066}           # reset, the RST vectors (IM 1 at $38), NMI
        roots = {s for s in starts if s in vectors}
        roots |= {names[x] for x in ("COLD_START", "GRAPHICS_HOME_TABLE") if x in names}
        roots |= {names[lab] for lab in names if lab.startswith(("W_", "H_"))}   # every word: the chain reaches it
    else:
        roots = {names["GRAPHICS_EXROM_TABLE"]}
    roots |= {names[k] for k in KNOWN if k in names}
    callees = {}
    for dst, srcs in edges.items():
        for s in srcs:
            callees.setdefault(s, set()).add(dst)
    live, todo = set(), list(roots)
    while todo:
        x = todo.pop()
        if x not in live:
            live.add(x)
            todo.extend(callees.get(x, ()))
    out = []
    for a, b in zip(starts, starts[1:] + [end]):
        k = {"code": 0, "data": 0, "fill": 0}
        for x in range(a, b):
            k[kind_of.get(x, "fill")] += 1
        out.append(dict(name=tops[a], start=a, size=b - a, comp=comp[a - base], reachable=a in live,
                        refs=sorted(tops[s] for s in edges.get(a, ()) if s in tops), **k))
    return dict(image=cfg["image"], end=end, free=len(data) - n, routines=out)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--image", default="home", choices=("home", "exrom"))
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--md", action="store_true", help="markdown tables")
    ap.add_argument("--json", help="write the inventory as JSON")
    ap.add_argument("--unreachable", action="store_true", help="list only the routines nothing reaches")
    a = ap.parse_args()
    cfg = tomllib.load(open(os.path.join(ROOT, "budget.toml"), "rb"))
    inv = inventory(a.image, cfg[a.image], a.build)
    if a.json:
        json.dump(inv, open(a.json, "w"), indent=1)
    rs = inv["routines"]
    if a.unreachable:
        rs = [r for r in rs if not r["reachable"]]
    print("%s: code ends $%04X, %d B free; %d routines, %d unreachable (%d B)" % (
        inv["image"], inv["end"], inv["free"], len(inv["routines"]),
        sum(not r["reachable"] for r in inv["routines"]), sum(r["size"] for r in inv["routines"] if not r["reachable"])))
    for c in cfg[a.image]["component"]:
        sel = [r for r in rs if r["comp"] == c["id"]]
        if not sel:
            continue
        if a.md:
            print("\n#### `%s` — %s: %d B\n\n| Address | Bytes | Routine | Code/data | Referenced by |\n|---|---:|---|---|---|"
                  % (c["id"], c["title"], sum(r["size"] for r in sel)))
            for r in sel:
                refs = r["refs"]
                print("| `$%04X` | %d | `%s`%s | %d/%d%s | %s |" % (
                    r["start"], r["size"], r["name"], "" if r["reachable"] else " **unreachable**", r["code"], r["data"],
                    " +%d fill" % r["fill"] if r["fill"] else "",
                    ", ".join("`%s`" % x for x in refs[:5]) + (" +%d" % (len(refs) - 5) if len(refs) > 5 else "") or "—"))
        else:
            print("\n[%s] %d B" % (c["id"], sum(r["size"] for r in sel)))
            for r in sel:
                refs = r["refs"]
                print("  $%04X %5d %-3s %-30s <- %s" % (r["start"], r["size"], "" if r["reachable"] else "UNR", r["name"],
                                                       ", ".join(refs[:5]) + (" +%d" % (len(refs) - 5) if len(refs) > 5 else "")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
