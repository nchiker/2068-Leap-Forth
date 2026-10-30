#!/usr/bin/env python3
"""cart_diff_dumpcmp.py - oracle for changes to tools/cart_diff.py's typing: compare two `--dump` directories.

  python3 tools/cart_diff_dumpcmp.py --home-dir TREE --cart-dir TREE OLD_DUMP NEW_DUMP [--cart-dck FILE]

For every run (CASE.EMU.KIND) present in either directory the RAM dumps ($4000-$FFFF) are compared.  The regions that
cart_diff.compare() reads must be byte-identical (the symbols are the build's own, as compare() uses them):
  screen $4000-$5AFF; IX and IY (same value) with the data stack IX..DSTACK_TOP and the float stack IY..FSTACK_TOP;
  the HERE and LATEST cells and the user dictionary FORTH_DICT_RAM..HERE; the EXROM-side regions Build.regions
  (GFX_FILL_SP.., SPRITE_SLOT_DEFINED..BANK_EXROM_DEPTH, the sprite buffers).
Every OTHER differing address is listed, grouped into ranges (gap <= 8 bytes joined) with the nearest preceding symbol
of the build's .sym, so each can be explained (expected: keyboard/ISR cells, FRAMES, the machine stack below SP,
scratch).  The typed lines, the attempt count and the register values are shown too.
Exit 0: every compared region identical in every pair; 1: a compared region differs (or a dump is missing); 2: error.
"""
import argparse, bisect, glob, json, os, re, sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import cart_diff as cd                                      # noqa: E402

RAM0 = cd.RAM0


def ram_syms(path):
    """[(addr, name)] of every symbol at $4000 and above, sorted (cart_diff.Syms keeps only the ROM ones)."""
    rows = []
    for line in open(path):
        m = re.match(r"^(\S+):\s+EQU\s+0x([0-9A-Fa-f]+)", line)
        if m and int(m.group(2), 16) >= RAM0 and m.group(1) not in cd.NOT_ADDRESS:
            rows.append((int(m.group(2), 16), m.group(1)))
    rows.sort()
    return rows


def sym_at(rows, addrs, a):
    i = bisect.bisect_right(addrs, a) - 1
    if i < 0:
        return "?"
    return rows[i][1] if rows[i][0] == a else "%s+%d" % (rows[i][1], a - rows[i][0])


def regions_of(b, ram, ix, iy):
    """The (name, lo, hi) regions compare() reads for build `b` from one result's RAM (ix/iy: its registers)."""
    mem = lambda a, n: ram[a - RAM0:a - RAM0 + n]
    word = lambda a: mem(a, 2)[0] | mem(a, 2)[1] << 8
    out = [("screen", 0x4000, 0x5B00)]
    if 0x8000 <= ix <= b.dstack_top:
        out.append(("data stack", ix, b.dstack_top))
    if 0x8000 <= iy <= b.fstack_top:
        out.append(("float stack", iy, b.fstack_top))
    here = word(b.here)
    out += [("HERE cell", b.here, b.here + 2), ("LATEST cell", b.latest, b.latest + 2)]
    if b.dict0 <= here <= 0xF000:
        out.append(("user dictionary", b.dict0, here))
    for n, lo, hi in b.regions:
        out.append((n, lo, hi))
    return out


def ranges(idx, gap=8):
    out = []
    for i in idx:
        if out and i - out[-1][1] <= gap + 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--home-dir", required=True)
    ap.add_argument("--cart-dir", required=True)
    ap.add_argument("--cart-dck")
    ap.add_argument("old")
    ap.add_argument("new")
    ap.add_argument("--quiet", action="store_true", help="only the per-pair line and the summary")
    a = ap.parse_args()
    try:
        builds = {"home": cd.Build("home", a.home_dir), "cart": cd.Build("cart", a.cart_dir, a.cart_dck)}
    except cd.HarnessError as e:
        print("ERROR:", e, file=sys.stderr)
        return 2
    syms = {k: ram_syms(os.path.join(b.dir, "build", "forth_boot.sym" if k == "home" else "forth_boot_cart.sym"))
            for k, b in builds.items()}
    names = lambda d: {os.path.basename(f)[:-5] for f in glob.glob(d + "/*.json")}
    old, new = names(a.old), names(a.new)
    bad_pairs, total = 0, 0
    other_summary = {}                                      # (kind, range text) -> runs it appears in
    for key in sorted(old | new):
        if key not in old or key not in new:
            print("MISSING  %-44s only in %s" % (key, "OLD" if key in old else "NEW"))
            bad_pairs += 1
            continue
        total += 1
        kind = key.rsplit(".", 1)[1]
        b = builds[kind]
        meta = {k: json.load(open("%s/%s.json" % (d, key))) for k, d in (("old", a.old), ("new", a.new))}
        ram = {k: open("%s/%s.bin" % (d, key), "rb").read() for k, d in (("old", a.old), ("new", a.new))}
        problems = []
        if len(ram["old"]) != len(ram["new"]):
            problems.append("RAM dump sizes differ %d/%d" % (len(ram["old"]), len(ram["new"])))
        for r in ("ix", "iy"):
            if meta["old"][r] != meta["new"][r]:
                problems.append("%s differs %04X/%04X" % (r.upper(), meta["old"][r], meta["new"][r]))
        if [tuple(t) for t in meta["old"]["typed"]] != [tuple(t) for t in meta["new"]["typed"]]:
            problems.append("typed lines differ")
        regs = regions_of(b, ram["old"], meta["old"]["ix"], meta["old"]["iy"])
        regs_new = regions_of(b, ram["new"], meta["new"]["ix"], meta["new"]["iy"])
        if regs != regs_new:
            problems.append("region layout differs (HERE moved?): %s vs %s" % (regs, regs_new))
        covered = bytearray(len(ram["old"]))
        for n, lo, hi in regs:
            o, w = ram["old"][lo - RAM0:hi - RAM0], ram["new"][lo - RAM0:hi - RAM0]
            for i in range(lo - RAM0, min(hi - RAM0, len(covered))):
                covered[i] = 1
            if o != w:
                first = next(i for i in range(len(o)) if o[i] != w[i])
                problems.append("REGION %s %04X-%04X differs in %d byte(s), first at %04X (%02X/%02X)" % (
                    n, lo, hi, sum(x != y for x, y in zip(o, w)), lo + first, o[first], w[first]))
        n = min(len(ram["old"]), len(ram["new"]))
        other = [i for i in range(n) if ram["old"][i] != ram["new"][i] and not covered[i]]
        rows = syms[kind]
        addrs = [r[0] for r in rows]
        print("%s  %-44s regions=%d compared-bytes=%d other-differing-bytes=%d attempts old/new %s/%s" % (
            "FAIL" if problems else "SAME", key, len(regs), sum(covered), len(other),
            meta["old"]["attempts"], meta["new"]["attempts"]))
        for p in problems:
            print("      - " + p)
        bad_pairs += bool(problems)
        for lo, hi in ranges(other):
            lo, hi = lo + RAM0, hi + RAM0
            txt = "%04X-%04X (%d)  %s .. %s" % (lo, hi, sum(1 for i in other if lo <= i + RAM0 <= hi),
                                              sym_at(rows, addrs, lo), sym_at(rows, addrs, hi))
            other_summary.setdefault((kind, txt.split("  ", 1)[1].split(" .. ")[0].split("+")[0]), []).append(key)
            if not a.quiet:
                print("      other  " + txt)
    print("\n%d run(s) compared, %d with a compared-region difference or missing" % (total, bad_pairs))
    print("other differing ranges, by the symbol they start in (kind, symbol): number of runs")
    for (kind, s), keys in sorted(other_summary.items()):
        print("   %-5s %-28s %d" % (kind, s, len(keys)))
    return 1 if bad_pairs else 0


if __name__ == "__main__":
    sys.exit(main())
