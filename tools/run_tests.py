#!/usr/bin/env python3
"""Leap-Forth test runner (make test, make test-fast): every suite on the production images in ZEsarUX.

Suites on one pool of emulators (ports 10760 up, one per worker):
  boot    the image boots to the prompt: the version on the status bar, the chime, the colours, glyph table, the harness's own checks (tools/fharness.py)
  forth   tests/**/*.fs typed at the prompt, each line against its `\\ expect:` (tools/forthtest.py)
  editor  the console and the full-screen editor, the redraw oracle, typing cost (tools/edtest.py)
  float   the float words against the bit-exact model, integer * / MOD, RND, speeds (tools/floattest.py)
  shape   FILL and CIRCLE against a model, speeds (tools/shapetest.py)
  bench   tests/bench/*.fs: the timed lines' T-states (recorded, not gated)
Then, on their own emulators:
  poweron the boot from power-on RAM patterns (tools/poweron.py, ports 10820-10839)
  tape    SAVE/LOAD/VERIFY on real tape signals (tools/tapetest.py, ports 10960-10979)

--fast (make test-fast): boot, forth, editor, float without its speed group and with fewer random cases, shape
without speeds.  Exit 0 when every suite passes; the results are also written to build/test_results.json.

Usage: run_tests.py [--fast] [--suite boot,forth,...] [--workers N] [--port N] [--build DIR] [only ...]"""
import argparse
import contextlib
import io
import json
import os
import subprocess
import sys
import time

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fharness as fh   # noqa: E402
import forthtest        # noqa: E402
import edtest           # noqa: E402
import floattest        # noqa: E402
import shapetest        # noqa: E402

ROOT = os.path.dirname(HERE)
POOL = ("boot", "forth", "editor", "float", "shape", "bench")
ALL = POOL + ("poweron", "tape")
FAST = ("boot", "forth", "editor", "float", "shape")


def boot_suite():
    checks = fh.CHECKS

    def report(res, wall):
        bad = 0
        for (tag, name, _), r in zip(checks, res):
            bad += not r["ok"]
            if not r["ok"]:
                print("boot: FAIL %s %s" % (name, r["detail"]))
        print("boot: %d/%d checks pass (%s)" % (len(checks) - bad, len(checks), res[0]["detail"]))
        return 1 if bad else 0
    return fh.Suite("boot", checks, lambda m, t: t[2](m, t), report)


def make(name, a, build, only):
    out = os.path.join(build, name + "test.json")
    if name == "boot":
        return boot_suite()
    if name == "forth":
        return forthtest.suite(None, only)
    if name == "bench":
        return forthtest.suite("bench", only)
    if name == "editor":
        return edtest.suite(build, only, out, workers=a.workers)
    if name == "float":
        if a.fast:
            return floattest.suite(build, only, out, group="gated", count=100, int_n=10000)
        return floattest.suite(build, only, out)
    if name == "shape":
        return shapetest.suite(build, only, out, group="gated" if a.fast else "all")
    raise ValueError(name)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--fast", action="store_true", help="make test-fast (see the header)")
    ap.add_argument("--suite", default=None, help="comma-separated: " + ",".join(ALL))
    ap.add_argument("--workers", type=int, default=None, help="emulators (default: CPUs less one, at most 8)")
    ap.add_argument("--port", type=int, default=10760, help="first ZRCP port of the pool (10760-10779)")
    ap.add_argument("--build", default=os.path.join(ROOT, "build"))
    ap.add_argument("only", nargs="*", help="only the cases whose name contains one of these")
    a = ap.parse_args()
    names = a.suite.split(",") if a.suite else list(FAST if a.fast else ALL)
    for n in names:
        if n not in ALL:
            ap.error("unknown suite %s" % n)
    build = fh.resolve_build(a.build)
    t0 = time.time()
    codes = {}
    suites = [make(n, a, build, a.only) for n in names if n in POOL]
    if suites:
        print("run_tests: %s: %d tasks" % (", ".join(s.name for s in suites), sum(len(s.tasks) for s in suites)), flush=True)
        res = fh.run_suites(suites, build, a.workers, a.port)
        wall = time.time() - t0
        for s, r in zip(suites, res):
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                codes[s.name] = s.report(r, wall)
            for line in buf.getvalue().splitlines():      # the suites' summaries, tables and failures
                if not line.startswith("PASS "):
                    print(line)
    for n, cmd in (("poweron", ["tools/poweron.py"]), ("tape", ["tools/tapetest.py", "--build", build])):
        if n in names:
            print("run_tests: %s" % n, flush=True)
            codes[n] = subprocess.call([sys.executable, "-I"] + cmd, cwd=ROOT)
    bad = [n for n, c in codes.items() if c]
    json.dump(dict(codes=codes, wall=round(time.time() - t0, 1), fast=a.fast),
              open(os.path.join(build, "test_results.json"), "w"), indent=1)
    print("run_tests: %s; wall %.0f s" % ("FAIL in " + ", ".join(bad) if bad else "every suite passes", time.time() - t0))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
