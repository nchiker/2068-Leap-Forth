#!/usr/bin/env python3
"""T-state benchmark runner for the rom/bench/*.asm driver ROMs (sieve, pixel, float, string).

Each driver ROM interprets a Forth benchmark at boot, times it with its own FRAMES counter, sets
the border to 4, prints FRAMES=/N=/RESULT= and parks in COLD_START.hang (`jr` to itself).  This
tool runs every ROM under ZEsarUX (via ts2068-debug / ZRCP), counts emulated T-states with the
ZRCP `reset-tstates-partial` / `get-tstates-partial` pair, and reports them.  The T-state count is
a property of the emulated machine, not the host: it does not depend on host speed or load.

Figures per benchmark
  tstates_total   T-states from CPU reset (PC=0) to the first arrival at COLD_START.hang.  Includes
                  boot, compiling the Forth source (INTERPRET_RUN) and the timed region.  This is
                  the primary, always-present figure and the one the baseline gate compares first.
  tstates_region  T-states from the first to the second entry of W_BORDER (the code of the Forth
                  word BORDER): `2 BORDER` opens the timed region and `4 BORDER` closes it.  It
                  therefore covers the body of BENCH only (plus the few instructions of the first
                  BORDER word itself and of the literal `4`), not boot or compilation.  It is
                  reported only when W_BORDER is entered exactly twice, otherwise null (never a
                  guess).  Entering W_BORDER is observed with a ZRCP breakpoint, which costs no
                  emulated T-states.
  frames_in_rom   the FRAMES=<n> value the ROM printed, captured from the characters passed to
                  GFX_PUTCHAR (breakpoint on its entry; A = character).  Cross-check:
                  tstates_region / FRAME_TSTATES ~= frames_in_rom (the ROM counts interrupts).
  result_ok       N= and RESULT= printed by the ROM compared with EXPECTED below (values taken from
                  ~/2068-rom-benchmarks/benchmarks/forth/*.fs headers); null if not captured.

Run image: the SAVEBIN files are 32 KiB but the code lies below $4000, and ZEsarUX wants one
concatenated image, 16 KiB Home ROM + 8 KiB EXROM.  The image is built here as the first 16384
bytes of build/bench_<name>_rom0.bin plus 8192 zero bytes, after checking that every byte at $4000
and above in the file is zero (nothing would be truncated) and that every symbol we use is below
$4000.

A run PASSES only if: PC is exactly COLD_START.hang, the border is 4, W_BORDER was entered exactly
twice (so border==4 cannot be stale), and the printed N/RESULT match.  Landing in
INTERPRET_UNKNOWN_WORD.hang2 (border 7, an unknown Forth word) is a FAIL, exhausting --max-instr is a
TIMEOUT, both with the evidence printed.

Determinism: ZEsarUX is a deterministic emulator, so repeats should be identical.  Each repeat is a
fresh emulator process.  If repeats differ, all values are recorded in "repeats", the reported
figure is the MINIMUM (the least perturbed by whatever caused the difference), a WARN is printed,
and the bench FAILS if (max-min)/min exceeds the tolerance (otherwise it only warns).

Usage: python3 tools/bench.py [--build-dir build] [--out build/bench.json] [--port 10780]
         [--only sieve,pixel] [--max-instr N] [--baseline FILE] [--tolerance PCT]
         [--repeat N] [--update-baseline FILE]
Exit status: 0 all pass (and no regression vs --baseline), 1 otherwise, 2 setup problem.
"""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

# Emulated machine constants.  CLOCK_HZ is only used for the "equivalent seconds" column (the real
# TS2068 CPU clock is 3.528 MHz; the round 3.5 MHz figure is what the project quotes).
CLOCK_HZ = 3_500_000
FRAME_TSTATES = 69888  # 224 T-states * 312 lines; the FRAMES counter ticks once per frame interrupt

BENCHES = ("sieve", "pixel", "float", "string")
# (N, RESULT) printed by the ROM, from ~/2068-rom-benchmarks/benchmarks/forth/*.fs headers.
EXPECTED = {
    "sieve": ("10", "551"),      # pi(4003)-1
    "pixel": ("3000", "302"),    # seeded by `26725 RANDOMIZE` (rom/bench/bench_pixel.asm); 302 since step F's RND (Leap-C's
                                 # xorshift, FLOAT_SPEC.md 11.2), 159 with the earlier LFSR
    "float": ("300", "-0.1453"),  # the exact sum is -0.1453125; -0.6523 was the 3-byte format's error (FLOAT_SPEC.md F10)
    "string": ("400", "15"),
}
SYM_DONE = "COLD_START.hang"
SYM_BUG = "INTERPRET_UNKNOWN_WORD.hang2"
SYM_BORDER = "W_BORDER"
SYM_PUTCHAR = "GFX_PUTCHAR"
HOME_SIZE, EXROM_SIZE = 0x4000, 0x2000
CHUNK = 2_000_000  # instructions per `run`
GOOD_BORDER = 4
REPO = Path(__file__).resolve().parent.parent


class BenchError(Exception):
    pass


def import_debug():
    try:
        import ts2068_debug  # noqa: F401
    except ImportError:
        sys.path.insert(0, os.environ.get("TS2068_DEBUG_DIR", str(Path.home() / "ts2068-debug")))
    from ts2068_debug.controller import Ts2068Debug
    from ts2068_debug.process import terminate_emulator
    return Ts2068Debug, terminate_emulator


def zesarux_dir():
    # same lookup as ts2068_debug/cli.py DEFAULT_ZESARUX_DIR
    return os.environ.get("TS2068_DEBUG_ZESARUX_DIR", str(Path.home() / "Applications" / "ZEsarUX-13.0"))


def emulator_version(zdir):
    try:
        out = subprocess.run(["./zesarux", "--version"], cwd=zdir, capture_output=True, text=True, timeout=20)
        line = (out.stdout + out.stderr).strip().splitlines()[0]
        m = re.match(r"(ZEsarUX\s+[\w.]+)", line)
        return m.group(1) if m else line
    except (OSError, subprocess.SubprocessError, IndexError):
        return "ZEsarUX"


def load_syms(path):
    syms = {}
    rx = re.compile(r"^(\S+):\s+EQU\s+0x([0-9A-Fa-f]+)")
    for line in Path(path).read_text().splitlines():
        m = rx.match(line)
        if m:
            syms[m.group(1)] = int(m.group(2), 16)
    return syms


def prepare(build_dir, name, tmp):
    """Validate the build outputs; return (run_image_path, syms, rom_sha256)."""
    binp = Path(build_dir) / f"bench_{name}_rom0.bin"
    symp = Path(build_dir) / f"bench_{name}.sym"
    for p in (binp, symp):
        if not p.is_file():
            raise BenchError(f"missing {p} (build the bench ROMs first)")
    data = binp.read_bytes()
    if len(data) < HOME_SIZE:
        raise BenchError(f"{binp}: only {len(data)} bytes, need at least {HOME_SIZE}")
    if any(data[HOME_SIZE:]):
        raise BenchError(f"{binp}: non-zero bytes at or above $4000 -- the 16 KiB+8 KiB run image "
                         f"would truncate real code")
    syms = load_syms(symp)
    for s in (SYM_DONE, SYM_BUG, SYM_BORDER, SYM_PUTCHAR):
        if s not in syms:
            raise BenchError(f"{symp}: symbol {s} not found")
        if syms[s] >= HOME_SIZE:
            raise BenchError(f"{symp}: {s} = ${syms[s]:04X} is at or above $4000, outside the run image")
    img = Path(tmp) / f"bench_{name}_run.bin"
    img.write_bytes(data[:HOME_SIZE] + bytes(EXROM_SIZE))
    return img, syms, hashlib.sha256(data).hexdigest()


def parse_report(text):
    m = re.search(r"FRAMES=(-?\d+)\s*N=(-?\d+)\s*RESULT=(\S+)", text)
    if not m:
        return None
    return int(m.group(1)), m.group(2), m.group(3)


def run_once(name, build_dir, port, max_instr, Ts2068Debug, terminate_emulator, zdir):
    """One fresh emulator session.  Returns a dict; never raises for benchmark-level failures."""
    tmp = tempfile.mkdtemp(prefix=f"bench-{name}-")
    os.environ["TS2068_DEBUG_STATE_DIR"] = os.path.join(tmp, "state")  # private, never the shared one
    out = {"ok": False, "status": "ERROR", "evidence": ""}
    dbg = None
    t_wall = time.time()
    try:
        img, syms, sha = prepare(build_dir, name, tmp)
        out["rom_sha256"] = sha
        dbg = Ts2068Debug(zdir, port=port, romfile=str(img))
        dbg.start()
        dbg.load_symbols(str(Path(build_dir) / f"bench_{name}.sym"))
        z = dbg._zrcp
        regs = dbg.reset_to_known_state()
        if regs.values.get("PC") != 0:
            raise BenchError(f"reset did not land on PC=0000: {regs.raw!r}")
        # ZRCP reset-cpu only sets PC/SP/AF: BC/DE/HL/IX/IY and the refresh register R keep whatever
        # the free-running boot left behind (R and the frame phase differ run to run).  The pixel
        # benchmark used to seed RND from R (`0 RANDOMIZE`; it now passes a fixed seed), so without this
        # its work, RESULT and T-states changed from run to run.  Pin them to a fixed state.
        for reg in ("R", "BC", "DE", "HL", "IX", "IY"):
            z.command(f"set-register {reg}=0H")
        z.command("reset-tstates-partial")
        if int(z.command("get-tstates-partial").strip()) != 0:
            raise BenchError("reset-tstates-partial did not zero the counter")
        try:
            z.command("enable-breakpoints")
        except Exception as exc:  # noqa: BLE001 - "already enabled" is fine
            if "already" not in str(exc).lower():
                raise
        watch = {1: syms[SYM_DONE], 2: syms[SYM_BUG], 3: syms[SYM_BORDER], 4: syms[SYM_PUTCHAR]}
        for i, a in watch.items():
            z.command(f"set-breakpoint {i} PC={a:04X}H")
        addr_kind = {syms[SYM_DONE]: "done", syms[SYM_BUG]: "bug", syms[SYM_BORDER]: "border",
                     syms[SYM_PUTCHAR]: "putchar"}

        border_ts, chars = [], []
        spent = 0
        while True:
            if spent >= max_instr:
                final = "timeout"
                break
            z.command(f"run {CHUNK}", timeout=max(60.0, CHUNK / 20_000 + 10))
            r = dbg.get_registers().values
            kind = addr_kind.get(r["PC"])
            if kind is None:
                spent += CHUNK  # chunk ran out without reaching a watched address
                continue
            if kind in ("done", "bug"):
                final = kind
                break
            if kind == "border":
                border_ts.append(int(z.command("get-tstates-partial").strip()))
            else:  # putchar: A holds the character
                chars.append((r["AF"] >> 8) & 0xFF)
            z.command("cpu-step")  # leave the still-armed breakpoint (it would re-fire at once)
            spent += 1

        ts = int(z.command("get-tstates-partial").strip())
        border = dbg.timex_state().get("border")
        pc = dbg.get_registers().values["PC"]
        text = "".join(chr(c) if 32 <= c < 127 else "?" for c in chars)
        out.update(tstates_total=ts, border=border, screen_text=text, border_entries=len(border_ts))
        if final == "timeout":
            out.update(status="TIMEOUT", evidence=f"no arrival at {SYM_DONE} within {max_instr} instructions; "
                       f"PC=${pc:04X} border={border} T-states so far={ts}")
        elif final == "bug":
            out.update(status="FAIL", evidence=f"landed in {SYM_BUG} (unknown Forth word) PC=${pc:04X} "
                       f"border={border}; printed text: {text!r}")
        elif border != GOOD_BORDER:
            out.update(status="FAIL", evidence=f"at {SYM_DONE} but border={border}, expected {GOOD_BORDER}; "
                       f"printed text: {text!r}")
        else:
            out["tstates_region"] = border_ts[1] - border_ts[0] if len(border_ts) == 2 else None
            rep = parse_report(text)
            problems = []
            if len(border_ts) != 2:
                problems.append(f"W_BORDER entered {len(border_ts)} times, expected 2")
            if rep:
                out["frames_in_rom"] = rep[0]
                out["result_ok"] = (rep[1], rep[2]) == EXPECTED[name]
                if not out["result_ok"]:
                    problems.append(f"printed N={rep[1]} RESULT={rep[2]}, expected N={EXPECTED[name][0]} "
                                    f"RESULT={EXPECTED[name][1]}")
            else:
                problems.append(f"could not find FRAMES=/N=/RESULT= in printed text {text!r}")
            if problems:
                out.update(status="FAIL", evidence="; ".join(problems))
            else:
                out.update(ok=True, status="PASS", evidence=f"printed: {text}")
    except Exception as exc:  # noqa: BLE001 - report, don't crash the whole run
        out.update(status="ERROR", evidence=f"{type(exc).__name__}: {exc}")
    finally:
        pid = None
        try:
            if dbg is not None:
                pid = dbg._proc.pid
                dbg.stop()
        except Exception:  # noqa: BLE001
            pass
        if pid:
            try:
                terminate_emulator(pid, port, grace_s=2.0)
            except Exception:  # noqa: BLE001
                pass
        shutil.rmtree(tmp, ignore_errors=True)
        out["wall_s"] = round(time.time() - t_wall, 1)
    return out


def git_info():
    def g(*a):
        return subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, text=True).stdout.strip()
    # dirty = tracked files modified/staged; untracked files (scratch output etc.) don't count
    return g("rev-parse", "HEAD") or None, bool(g("status", "--porcelain", "--untracked-files=no"))


def run_bench(name, args, Ts2068Debug, terminate_emulator, zdir):
    reps = []
    for k in range(args.repeat):
        r = run_once(name, args.build_dir, args.port, args.max_instr, Ts2068Debug, terminate_emulator, zdir)
        reps.append(r)
        print(f"  [{name}] repeat {k + 1}/{args.repeat}: {r['status']} total={r.get('tstates_total')} "
              f"region={r.get('tstates_region')} wall={r['wall_s']}s", flush=True)
        if r["status"] in ("ERROR", "TIMEOUT"):
            break  # a missing build / hung ROM will not improve on repeat
    good = [r for r in reps if r["ok"]]
    res = {"status": "PASS", "evidence": "", "wall_s": [r["wall_s"] for r in reps]}
    if len(good) != len(reps):
        bad = next(r for r in reps if not r["ok"])
        res.update(status=bad["status"], evidence=bad["evidence"])
    ref = good[0] if good else reps[0]
    totals = [r["tstates_total"] for r in reps if "tstates_total" in r]
    entry = {
        "rom_sha256": ref.get("rom_sha256"),
        "tstates_total": min(totals) if totals else None,
        "tstates_region": None,
        "frames_in_rom": ref.get("frames_in_rom"),
        "result_ok": ref.get("result_ok"),
        "repeats": [{"tstates_total": r.get("tstates_total"), "tstates_region": r.get("tstates_region"),
                     "frames_in_rom": r.get("frames_in_rom")} for r in reps],
    }
    if good:
        regs = [r["tstates_region"] for r in good]
        entry["tstates_region"] = min(regs) if all(x is not None for x in regs) else None
        spread = max(totals) - min(totals)
        if spread:
            pct = 100.0 * spread / min(totals)
            note = f"NONDETERMINISTIC: totals {totals}, spread {spread} T-states ({pct:.4f}%), using the minimum"
            if pct > args.tolerance:
                res.update(status="FAIL", evidence=note)
            else:
                res["evidence"] = note
    res["entry"] = entry
    return res


def compare_baseline(results, baseline, tol):
    """Return (rows, regression:bool)."""
    rows, bad = [], False
    for name, res in results.items():
        cur = res["entry"]
        base = baseline.get("benches", {}).get(name)
        if base is None:
            rows.append((name, "total", cur["tstates_total"], None, None, "NEW (not in baseline)"))
            continue
        for key, label in (("tstates_total", "total"), ("tstates_region", "region")):
            c, b = cur.get(key), base.get(key)
            if c is None or b is None:
                if key == "tstates_total":  # the primary figure must be comparable
                    rows.append((name, label, c, b, None, "MISSING (cannot compare)"))
                    bad = True
                continue
            d = 100.0 * (c - b) / b
            note = "ok"
            if d > tol:
                note, bad = "SLOWER", True
            elif d < -tol:
                note = "faster"
            if c != b and cur.get("rom_sha256") == base.get("rom_sha256"):
                note += " (SAME ROM bytes: emulator/harness change?)"
            rows.append((name, label, c, b, d, note))
    return rows, bad


def main():
    ap = argparse.ArgumentParser(description="T-state benchmark runner (see the module docstring)")
    ap.add_argument("--build-dir", default="build")
    ap.add_argument("--out", default="build/bench.json")
    ap.add_argument("--port", type=int, default=10780)
    ap.add_argument("--only", default="", help="comma-separated subset of: " + ",".join(BENCHES))
    ap.add_argument("--max-instr", type=int, default=300_000_000,
                    help="instruction cap before TIMEOUT (default 300M; a sieve needs roughly 30M)")
    ap.add_argument("--baseline", help="compare against this JSON; exit 1 if any bench is slower than --tolerance")
    ap.add_argument("--tolerance", type=float, default=1.0, help="percent (default 1.0)")
    ap.add_argument("--repeat", type=int, default=2)
    ap.add_argument("--update-baseline", help="write the current numbers to this file (same schema)")
    args = ap.parse_args()

    names = [n for n in args.only.split(",") if n] or list(BENCHES)
    unknown = [n for n in names if n not in BENCHES]
    if unknown:
        ap.error(f"unknown bench {unknown}; choose from {','.join(BENCHES)}")
    names = sorted(names)
    Ts2068Debug, terminate_emulator = import_debug()
    zdir = zesarux_dir()
    if not Path(zdir).is_dir():
        print(f"ZEsarUX install dir not found: {zdir} (set TS2068_DEBUG_ZESARUX_DIR)", file=sys.stderr)
        return 2
    emu = emulator_version(zdir)

    results = {}
    for n in names:
        print(f"{n}:", flush=True)
        results[n] = run_bench(n, args, Ts2068Debug, terminate_emulator, zdir)

    commit, dirty = git_info()
    doc = {"schema": 1, "git_commit": commit, "git_dirty": dirty, "emulator": emu,
           "benches": {n: results[n]["entry"] for n in names}}
    text = json.dumps(doc, indent=2) + "\n"
    outp = Path(args.out)
    outp.parent.mkdir(parents=True, exist_ok=True)
    outp.write_text(text)

    print()
    print(f"{'bench':8s} {'tstates_total':>14s} {'seconds@3.5MHz':>15s} {'region':>13s} {'frames':>7s}  status")
    failed = False
    for n in names:
        r, e = results[n], results[n]["entry"]
        t = e["tstates_total"]
        secs = f"{t / CLOCK_HZ:.3f}" if t is not None else "-"
        print(f"{n:8s} {t if t is not None else '-':>14} {secs:>15s} {str(e['tstates_region']):>13s} "
              f"{str(e['frames_in_rom']):>7s}  {r['status']}")
        if r["status"] != "PASS":
            failed = True
        if r["evidence"] and (r["status"] != "PASS" or "NONDET" in r["evidence"]):
            print(f"         {r['evidence']}")
    print(f"(equivalent seconds = T-states / {CLOCK_HZ:,} Hz; one frame = {FRAME_TSTATES} T-states; {emu}; "
          "wall-clock per repeat: " + ", ".join(f"{n} {results[n]['wall_s']}" for n in names) + ")")
    print(f"wrote {outp}")

    if args.update_baseline:
        if failed:
            print("not updating baseline: a bench failed", file=sys.stderr)
        else:
            Path(args.update_baseline).write_text(text)
            print(f"wrote baseline {args.update_baseline}")
    if args.baseline:
        base = json.loads(Path(args.baseline).read_text())
        rows, regress = compare_baseline(results, base, args.tolerance)
        print(f"\nvs baseline {args.baseline} (tolerance {args.tolerance}%):")
        print(f"{'bench':8s} {'figure':7s} {'current':>13s} {'baseline':>13s} {'delta%':>8s}  note")
        for name, label, c, b, d, note in rows:
            print(f"{name:8s} {label:7s} {c if c is not None else '-':>13} {b if b is not None else '-':>13} "
                  f"{('%+.3f' % d) if d is not None else '-':>8s}  {note}")
        if regress:
            print("REGRESSION: at least one benchmark is slower than the baseline by more than the tolerance "
                  "(or could not be compared)")
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
