#!/usr/bin/env python3
"""Forth source tests (tests/**/*.fs): each file typed line by line at the production ROM's prompt.

A case is a Forth file.  Each line is typed at the console and ENTER pressed; what the line printed (the rows from
where the line was typed to the cursor, trailing blanks stripped, joined with "|", the interpreter's final " OK"
dropped) must be what the line expects (the text after `expect: `, leading blanks kept):

    LINE                      typed; it must print nothing (only OK)
    LINE  \\ expect: TEXT      typed (the part before the backslash); it must print TEXT
    LINE  \\ expect-end: TEXT  typed; what it printed must end with TEXT (output longer than the screen)
    LINE  \\ draws            typed; it draws on the screen, so what it printed is not read
    \\ anything else           a comment, not typed
    \\ exrom: stock            (anywhere) run the case with the stock-shaped EXROM (8 KB of $00) in place of the graphics EXROM
    \\ bench: NAME             (tests/bench) the next typed line is timed: T-states from ENTER to the next key wait
    \\ keys: TEXT             the next typed line reads keys (KEY, ACCEPT, INPUT): TEXT is given one key at a time
                              whenever it waits outside the editor; \\r is ENTER, \\b DELETE, \\xNN any code

{NAME} in a typed line is replaced by the decimal value of the ROM symbol NAME (build/forth_boot.sym, then
graphics_exrom.sym), so a test reads a ROM cell by name: `{CATCH_DEPTH} C@ .`.  Screen and attribute addresses are
hardware and are written as numbers.

An error prints the word and " ?" (`FOO ?`) and no OK.  A line's output must fit on the screen (23 rows).  A case stops at its first difference.  Every case starts from
the booted machine (fharness's snapshot at the first key wait)."""
import glob
import re
import os
import sys

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fharness as fh   # noqa: E402

ROOT = os.path.dirname(HERE)
TESTS = os.path.join(ROOT, "tests")
MAXI = 100_000_000                          # instructions a line may take before the console counts as stuck
EXPECT = "\\ expect:"
EXPECT_END = "\\ expect-end:"
DRAWS = object()


def parse(path):
    """-> dict(lines=[(lineno, text, expect or None, bench name or None, keys)], stock=bool)."""
    lines, stock, bench, keys = [], False, None, ""
    for n, raw in enumerate(open(path, encoding="latin-1").read().splitlines(), 1):
        s = raw.strip()
        if not s:
            continue
        if s.startswith("\\"):
            if s.startswith("\\ exrom:"):
                stock = s.split(":", 1)[1].strip() == "stock"
            elif s.startswith("\\ bench:"):
                bench = s.split(":", 1)[1].strip()
            elif s.startswith("\\ keys: "):
                keys = s[len("\\ keys: "):].encode("latin-1").decode("unicode_escape")
            continue
        exp = None
        if EXPECT_END in raw:
            raw, e = raw.split(EXPECT_END, 1)
            exp = ("end", e[1:].rstrip() if e.startswith(" ") else e.rstrip())
        elif EXPECT in raw:
            raw, exp = raw.split(EXPECT, 1)
            exp = exp[1:].rstrip() if exp.startswith(" ") else exp.rstrip()
        elif raw.rstrip().endswith("\\ draws"):
            raw, exp = raw.rstrip()[:-len("\\ draws")], DRAWS
        lines.append((n, raw.rstrip(), exp, bench, keys))
        bench, keys = None, ""
    return dict(lines=lines, stock=stock)


def cases(area=None, only=None):
    """Every test file under tests/ (tests/bench only when area is 'bench'), sorted, as paths relative to the repo."""
    paths = sorted(glob.glob(os.path.join(TESTS, "**", "*.fs"), recursive=True))
    paths = [os.path.relpath(p, ROOT) for p in paths]
    isbench = lambda p: p.startswith(os.path.join("tests", "bench") + os.sep)
    paths = [p for p in paths if isbench(p) == (area == "bench")]
    if only:
        paths = [p for p in paths if any(o in p for o in only)]
    return paths


def typed(m, c, text, timed=False, keys=""):
    """Type one line and ENTER; what it printed (see the header) and the T-states when timed."""
    S = m.sym
    text = re.sub(r"\{([A-Za-z_][A-Za-z0-9_.]*)\}", lambda mm: str(m.sym(mm.group(1))), text)
    before = m.screen_rows()
    r0 = m.read(S("PRINT_ROW"), 1)[0]
    for ch in text:
        c.key(ord(ch), MAXI)
    if timed:
        m.write(S("KBD_LASTK"), fh.KEY_ENTER)
        m.write(S("KBD_KEYHIT"), 0xFF)
        m.tstates_reset()
        m.cmd("cpu-step")
        c.wait(MAXI)
        t = m.tstates()
    else:
        c.key(fh.KEY_ENTER, MAXI)
        t = None
    keys = list(keys)
    while keys and not c.in_editor():
        c.key(ord(keys.pop(0)), MAXI)
    if not c.in_editor():
        raise RuntimeError("the line waits for a key (%s)" % ("no keys left" if not keys else "?"))
    if keys:
        raise RuntimeError("%d key(s) not read" % len(keys))
    after = m.screen_rows()
    r1 = m.read(S("PRINT_ROW"), 1)[0]
    k = 0                                   # rows scrolled off the top while the line ran (none when it cleared them)
    while k < r0 and any(after[:r0]) and after[:r0 - k] != before[k:r0]:
        k += 1
    rows = [r.rstrip() for r in after[r0 - k:r1 + 1]]
    while rows and not rows[-1]:
        rows.pop()
    out = "|".join(rows)
    if out.endswith("OK"):                  # the console's OK follows the output directly
        out = out[:-2].rstrip(" |")
    return out, t


def run_case(m, path):
    case = parse(os.path.join(ROOT, path))
    c = fh.Console(m)
    c.boot()
    bench = {}
    for n, text, exp, name, keys in case["lines"]:
        try:
            got, t = typed(m, c, text, timed=bool(name), keys=keys)
        except RuntimeError as e:
            return dict(ok=False, detail="%s:%d %r: %s" % (path, n, text, e))
        if name:
            bench[name] = t
        want = exp if exp is not None else ""
        if isinstance(want, tuple):
            if not got.endswith(want[1]):
                return dict(ok=False, detail="%s:%d %r printed %r, expected it to end with %r" % (path, n, text, got, want[1]))
        elif want is not DRAWS and got != want:
            return dict(ok=False, detail="%s:%d %r printed %r, expected %r" % (path, n, text, got, want))
    return dict(ok=True, detail="%s: %d lines" % (path, len(case["lines"])), bench=bench)


def suite(area=None, only=None):
    """tests/**/*.fs (area None) or tests/bench (area 'bench') as one fharness.Suite."""
    paths = cases(area, only)
    stock = [i for i, p in enumerate(paths) if parse(os.path.join(ROOT, p))["stock"]]
    name = "bench" if area == "bench" else "forth"

    def report(res, wall):
        failed = 0
        bench = {}
        for p, r in zip(paths, res):
            failed += not r["ok"]
            if not r["ok"]:
                print("%s: FAIL %s" % (name, r["detail"]))
            bench.update(r.get("bench") or {})
        for k, t in sorted(bench.items()):
            print("bench %-24s %12s T" % (k, t))
        print("%s: %d/%d cases pass" % (name, len(paths) - failed, len(paths)))
        harness = res and all(r["detail"].startswith(("TASK FAILED", "worker on port", "never ran")) for r in res)
        report.data = dict(cases=len(paths), passed=len(paths) - failed, bench=bench,
                           failures=[r["detail"] for r in res if not r["ok"]])
        return 2 if harness else (1 if failed else 0)
    return fh.Suite(name, paths, run_case, report, stock=stock)


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("--port", type=int, default=10760)
    ap.add_argument("--workers", type=int, default=None)
    ap.add_argument("--bench", action="store_true", help="tests/bench instead of the other tests")
    ap.add_argument("only", nargs="*")
    a = ap.parse_args()
    sys.exit(suite("bench" if a.bench else None, a.only).run_alone(a.build, a.workers, a.port))
