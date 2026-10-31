#!/usr/bin/env python3
"""Capture what the emulated AY actually plays (audit step A, after 2068-Leap's tools/maint/ay_audio_tests.py).

ZEsarUX writes its audio output to a raw file when started with --aofile (8-bit signed mono, 15,600 Hz,
emulated time). This starts the product ROM with that option, lets it boot (the startup chime is the first
sound), types a scale of `n 0.3 BEEP` lines at the prompt, and then measures the capture:

  * each BEEP's frequency, from the rising edges of the waveform, against 110250/period at ZEsarUX's own AY clock
    (1.7734 MHz; the real TS2068's is 1.764 MHz, so every note is 0.53 % lower there), where the period is the
    formula's, rounded (the ROM's table can differ by 1 count). The same periods are also written through plain
    `SOUND` and measured the same way, as the emulator's own rendering of each period, which BEEP must match;
  * each note's duration against the frames the spec asks for (ZEsarUX frames are 1/50 s, the real machine's
    1/60 s, so durations are 20 % longer here);
  * with --compare-chime ROM, the startup chime of another build against this one: which of C4/E4/G4 sounds in
    each 1/50 s window, to show a change to the chime's waits left the sound the same.

Notes above about 2.2 kHz are not measurable from a 15.6 kHz capture by edge counting and are left to the register
check in tests/sound/ay.fs. Nothing is listened to: this is the emulator's own sound output, as a file.

Usage: tools/ay_audio.py [--rom build/forth_boot_rom0.bin] [--sym build/forth_boot.sym] [--port 10880]
                         [--out DIR] [--compare-chime OTHER_ROM.bin]
Ports: 10880-10899 (this project's range). Exit status 0 = all measured notes within tolerance, 1 = not, 2 = setup.
"""
import argparse
import json
import math
import os
import struct
import subprocess
import sys
import tempfile
import time
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parent.parent
SAMPLE_RATE = 15_600
EMU_AY_CLOCK = 1_773_400          # what ZEsarUX 13.0 gives the AY
REAL_AY_CLOCK = 1_764_000
NOTES = (-39, -24, -12, 0, 4, 7, 9, 12, 24, 36)
SECONDS = 0.3                      # 36 half-frames -> 18 frames
FRAMES = 18


def ideal_period(n):
    return round(110250 / (261.6256 * 2 ** (max(n, -39) / 12)))


# ---------------------------------------------------------------------------- analysis
def load_raw(path):
    return [b - 256 if b > 127 else b for b in open(path, "rb").read()]


def segments(samples, min_len, gap):
    """Tone segments: runs where the signal moves away from the idle level, split at `gap` still samples."""
    idle = Counter(samples).most_common(1)[0][0] if samples else 0
    active = [abs(s - idle) > 2 for s in samples]
    segs, i, n = [], 0, len(samples)
    while i < n:
        if not active[i]:
            i += 1
            continue
        j, last = i, i
        while j < n and j - last <= gap:
            if active[j]:
                last = j
            j += 1
        if last - i >= min_len:
            segs.append((i, last + 1))
        i = last + 1
    return segs


def edge_frequency(samples, a, b):
    """Mean rising-edge interval of the intervals within 20 % of the median (the emulator's null audio driver
    inserts idle samples when its buffer runs dry, which makes the odd interval long)."""
    seg = samples[a:b]
    mid = (max(seg) + min(seg)) / 2.0
    ups = [k for k in range(1, len(seg)) if seg[k - 1] < mid <= seg[k]]
    iv = [y - x for x, y in zip(ups, ups[1:])]
    if len(iv) < 2:
        return 0.0
    med = sorted(iv)[len(iv) // 2]
    good = [v for v in iv if abs(v - med) <= 0.2 * med]
    return SAMPLE_RATE * len(good) / sum(good)


def goertzel(samples, a, b, f):
    n = b - a
    k = 2 * math.cos(2 * math.pi * f / SAMPLE_RATE)
    s1 = s2 = 0.0
    mean = sum(samples[a:b]) / max(1, n)
    for x in samples[a:b]:
        s0 = (x - mean) + k * s1 - s2
        s2, s1 = s1, s0
    return (s1 * s1 + s2 * s2 - k * s1 * s2) / max(1, n * n)


def write_wav(path, samples):
    data = bytes((s + 128) & 0xFF for s in samples)
    hdr = b"RIFF" + struct.pack("<I", 36 + len(data)) + b"WAVEfmt " + struct.pack(
        "<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE, 1, 8) + b"data" + struct.pack("<I", len(data))
    open(path, "wb").write(hdr + data)


def chime_profile(samples, a, b):
    """Power of C4/E4/G4 (periods 421/334/281) in each 1/50 s window of the chime, scaled to its loudest."""
    freqs = [EMU_AY_CLOCK / 16 / p for p in (421, 334, 281)]
    win = SAMPLE_RATE // 50
    rows = [[goertzel(samples, w, min(b, w + win), f) for f in freqs] for w in range(a, b, win)]
    top = max(max(r) for r in rows) or 1
    return [[round(x / top, 2) for x in r] for r in rows]


# ---------------------------------------------------------------------------- the emulator
def start_emulator(rom0, exrom, sym, port, aofile, tmp):
    try:
        import ts2068_debug.process as proc
        from ts2068_debug.controller import Ts2068Debug
    except ImportError:
        print("ay_audio: ts2068_debug is not importable (see the 2068-debug skill)", file=sys.stderr)
        sys.exit(2)
    os.environ["TS2068_DEBUG_STATE_DIR"] = os.path.join(tmp, "state")
    os.environ["TS2068_DEBUG_ZESARUX_FAST"] = "0"      # real-time speed: the audio buffer never runs dry
    img = os.path.join(tmp, "image.bin")
    with open(img, "wb") as f:
        f.write(rom0 + exrom)
    orig = proc.subprocess.Popen

    def popen(args, **kw):
        return orig(list(args) + ["--aofile", aofile], **kw)

    proc.subprocess.Popen = popen
    zdir = os.environ.get("TS2068_DEBUG_ZESARUX_DIR", str(Path.home() / "Applications" / "ZEsarUX-13.0"))
    dbg = Ts2068Debug(zdir, port=port, romfile=img)
    try:
        dbg.start()
    finally:
        proc.subprocess.Popen = orig
    dbg.load_symbols(sym)
    return dbg, proc


def capture(rom_path, sym, port, lines, boot_wait=3.0, gap=0.6):
    """Boot the ROM under ZEsarUX with audio capture, type `lines`, return (samples, boot_len)."""
    tmp = tempfile.mkdtemp(prefix="ay_audio.")
    raw = os.path.join(tmp, "audio.raw")
    exrom = (ROOT / "build" / "graphics_exrom.bin").read_bytes()
    dbg, proc = start_emulator(Path(rom_path).read_bytes(), exrom, sym, port, raw, tmp)
    try:
        time.sleep(boot_wait)                           # boot and the chime (about 1.1 s of emulated time)
        boot_len = os.path.getsize(raw)
        for ln in lines:
            text, g = ln if isinstance(ln, tuple) else (ln, gap)
            dbg.type_line(text)
            time.sleep(g)
        time.sleep(1.0)
    finally:
        pid = dbg.pid if hasattr(dbg, "pid") else None
        dbg.stop()
        if pid:
            proc.terminate_emulator(pid, port, grace_s=2.0)
    return load_raw(raw), boot_len


# ---------------------------------------------------------------------------- main
def reference_lines():
    """`SOUND` writes the same periods straight to the chip and holds them with a counted loop: the reference the
    emulator's own rendering of a given period is measured against."""
    out = [(": HOLD 0 DO LOOP ;", 0.6)]
    for n in NOTES:
        p = ideal_period(n)
        f = EMU_AY_CLOCK / 16 / p
        loops = int(4000 * max(1.0, 14 / (f * 0.24)))      # at least 14 cycles, 4000 loops being about 0.24 s
        out.append(("7 254 SOUND 0 %d SOUND 1 %d SOUND 8 15 SOUND %d HOLD 8 0 SOUND" % (p & 255, p >> 8, loops),
                    max(2.0, loops / 4000 * 0.24 / 0.9 + 1.5)))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--rom", default=str(ROOT / "build" / "forth_boot_rom0.bin"))
    ap.add_argument("--sym", default=str(ROOT / "build" / "forth_boot.sym"))
    ap.add_argument("--port", type=int, default=10880)
    ap.add_argument("--out", default=str(ROOT / "build" / "audio"))
    ap.add_argument("--chime-only", action="store_true", help="boot only: measure the startup chime, skip the scale")
    ap.add_argument("--compare-chime", metavar="ROM", help="another build's rom0.bin: compare its startup chime")
    a = ap.parse_args()
    if not 10880 <= a.port <= 10899:
        print("ay_audio: --port must be in 10880-10899", file=sys.stderr)
        return 2
    os.makedirs(a.out, exist_ok=True)
    lines = [] if a.chime_only else [("%d %s BEEP" % (n, SECONDS), 0.8) for n in NOTES] + reference_lines()
    smp, boot_len = capture(a.rom, a.sym, a.port, lines)
    chime = segments(smp[:boot_len], SAMPLE_RATE // 20, SAMPLE_RATE // 10)
    res = {"emu_ay_clock": EMU_AY_CLOCK}
    ok = True
    if not a.chime_only:
        scale = smp[boot_len:]
        segs = segments(scale, SAMPLE_RATE // 10, SAMPLE_RATE // 10)
        write_wav(os.path.join(a.out, "scale.wav"), scale)
        want_n = 2 * len(NOTES)
        ok = len(segs) == want_n
        print("ay_audio: %d segments found, %d expected (%d BEEP notes, then %d SOUND references)"
              % (len(segs), want_n, len(NOTES), len(NOTES)))
        res.update(segments=len(segs), expected_segments=want_n, notes=[])
        print("ay_audio: %-4s %-6s %-9s %-9s %-9s %-8s %-8s %s" % (
            "n", "period", "formula", "SOUND ref", "BEEP", "vs ref %", "vs form %", "BEEP seconds"))
        if len(segs) == want_n:
            for i, n in enumerate(NOTES):
                (sa, sb), (ra, rb) = segs[i], segs[len(NOTES) + i]
                p = ideal_period(n)
                formula = EMU_AY_CLOCK / 16 / p
                beep, ref = edge_frequency(scale, sa, sb), edge_frequency(scale, ra, rb)
                vs_ref = 100 * (beep / ref - 1) if beep and ref else None
                vs_form = 100 * (beep / formula - 1) if beep else None
                secs = (sb - sa) / SAMPLE_RATE
                # Two tests. BEEP must sound as the emulator renders the same period written by plain SOUND
                # (0.2 %), and must lie near the formula: within 0.5 % plus 0.0007 % per count of period, because
                # the emulator renders long periods low (the reference shows it: -2.3 % at period 4009, the
                # same as BEEP). The first frame of an isolated note is partial: n-1 to n frames.
                dur_ok = (FRAMES - 1.5) / 50 <= secs <= (FRAMES + 0.5) / 50
                good = (vs_ref is not None and abs(vs_ref) <= 0.2 and abs(vs_form) <= 0.5 + 0.0007 * p and dur_ok)
                ok = ok and good
                res["notes"].append({"n": n, "period": p, "formula_hz": round(formula, 2), "sound_ref_hz": round(ref, 2),
                                     "beep_hz": round(beep, 2), "vs_ref_pct": round(vs_ref, 3), "vs_formula_pct": round(vs_form, 3),
                                     "beep_seconds": round(secs, 3), "ok": good})
                print("ay_audio: %-4d %-6d %-9.1f %-9.1f %-9.1f %-+8.2f %-+8.2f %.3f  %s" % (
                    n, p, formula, ref, beep, vs_ref, vs_form, secs, "ok" if good else "FAIL"))
    if a.compare_chime:
        other, olen = capture(a.compare_chime, a.sym, a.port + 1, [])
        mine = chime_profile(smp, chime[0][0], chime[-1][1]) if chime else []
        theirs_segs = segments(other[:olen], SAMPLE_RATE // 20, SAMPLE_RATE // 10)
        theirs = chime_profile(other, theirs_segs[0][0], theirs_segs[-1][1]) if theirs_segs else []
        n = min(len(mine), len(theirs))
        worst = max((abs(x - y) for r, s in zip(mine[:n], theirs[:n]) for x, y in zip(r, s)), default=1.0)
        res["chime"] = {"windows_this": len(mine), "windows_other": len(theirs), "worst_profile_diff": round(worst, 2)}
        print("ay_audio: chime: %d windows here, %d in the other build, worst per-window power difference %.2f"
              % (len(mine), len(theirs), worst))
        print("ay_audio: here   %s" % " ".join("".join("#" if x > 0.3 else "." for x in r) for r in mine))
        print("ay_audio: other  %s" % " ".join("".join("#" if x > 0.3 else "." for x in r) for r in theirs))
    res["pass"] = ok
    json.dump(res, open(os.path.join(a.out, "audio.json"), "w"), indent=1)
    print("ay_audio: %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
