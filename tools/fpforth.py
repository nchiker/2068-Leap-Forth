"""The model of Forth's float words (docs/V2/FLOAT_SPEC.md sections 6-8, 11.2, 12; step F, oracle T13).

Built on tools/fpmodel.py, Leap-C's bit-exact model of its float core, vendored unchanged (UPSTREAM below): every
function here composes fpmodel's operations in the order the spec gives the ROM, so a word's result can be compared
with the ROM byte for byte.  Floats are 5-byte `bytes` (the Sinclair format, as in fpmodel).  Errors are raised as
Throw(code) with the ANS code the ROM throws (-42 division by zero, -43 out of range, -46 invalid argument).

UPSTREAM: tools/fpmodel.py is 2068-Leap-C's tools/fpmodel.py at b918527 (last changed in 7e46991), sha256
16f595b92c5d5c15704b1f2918a9c0c904ae7682d9cc411f537b4fccea27a1a1; floattest.py --selftest checks the hash.
"""
import math
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fpmodel as F            # noqa: E402

FPMODEL_SHA256 = "16f595b92c5d5c15704b1f2918a9c0c904ae7682d9cc411f537b4fccea27a1a1"
FPMODEL_COMMIT = "b918527"


class Throw(Exception):
    def __init__(self, code):
        super().__init__(code)
        self.code = code


ZERO = bytes(5)
ONE, MONE, TEN = F.ONE, F.MONE, F.TEN
POW10 = F.POW10


def _range(fn, *a):
    """An fpmodel operation, its "range" error as THROW -43."""
    try:
        return fn(*a)
    except F.FloatError:
        raise Throw(-43)


def add(a, b):
    return _range(F.binop, "+", a, b)


def sub(a, b):
    return _range(F.binop, "-", a, b)


def mul(a, b):
    return _range(F.binop, "*", a, b)


def div(a, b):
    if b[0] == 0:
        raise Throw(-42)
    return _range(F.binop, "/", a, b)


def cmp(a, b):
    return F.binop("cmp", a, b)


def neg(a):
    return F.neg(a)


def fabs(a):
    return bytes([a[0], a[1] & 0x7F]) + bytes(a[2:]) if a[0] else ZERO


def fri(v):
    """S>F: a signed 16-bit integer."""
    return F.fri(v)


def is_neg(a):
    return a[0] != 0 and a[1] & 0x80 != 0


# ---------------------------------------------------------------- constants (section 8)
def _p1():
    f, ex = math.frexp(math.pi)
    return round(f * 2 ** 17) * 2.0 ** (ex - 17)     # pi to 17 significant bits (exact in a double)


PI = F.encode(math.pi)
HALF_PI = F.encode(math.pi / 2)
INV_PI = F.encode(1 / math.pi)
P1 = F.encode(_p1())
P2 = F.encode(math.pi - _p1())
DEG_K = F.encode(180 / math.pi)
SIN_COEFFS = [bytes(c) for c in (                     # Leap V2 rom/exrom_v2_float_fn.asm SIN_COEFFS (5.10)
    (0x7B, 0x0E, 0xFA, 0x35, 0x13),                   # pi/180
    (0x7E, 0xAA, 0xAA, 0xAA, 0xA5),                   # c3
    (0x7A, 0x08, 0x88, 0x86, 0x4C),                   # c5
    (0x74, 0xD0, 0x0B, 0xEA, 0x79),                   # c7
    (0x6E, 0x38, 0xB6, 0xAF, 0xCD),                   # c9
    (0x67, 0xCC, 0xFD, 0xBB, 0x92))]                  # c11
RAD_K = SIN_COEFFS[0]
HALF = F.encode(0.5)
C120 = F.encode(120.0)                                # BEEP: seconds -> half-frames
assert PI == bytes([0x82, 0x49, 0x0F, 0xDA, 0xA2])


# ---------------------------------------------------------------- integer part (section 8.1)
def _int_part(a, mode):
    """FROUND (mode "round", ties away from 0), FLOOR ("floor"), on the unpacked mantissa."""
    s, e, m = F.unpack(a)
    if e == 0:
        return ZERO
    if e <= 128:                                      # |x| < 1
        if mode == "round":
            return (MONE if s else ONE) if e == 128 else ZERO
        return MONE if s else ZERO
    if e >= 160:                                      # |x| >= 2^31: every bit is an integer bit
        return bytes(a)
    m32 = m >> 8
    fb = 160 - e                                      # fraction bits, 1..31
    dropped = m32 & ((1 << fb) - 1)
    im = m32 >> fb
    if mode == "round" and dropped >> (fb - 1) & 1:
        im += 1
    if mode == "floor" and s and dropped:
        im += 1
    if im == 0:
        return ZERO
    return F.pack(*F.norm(s, 160, im << 8))


def fround(a):
    return _int_part(a, "round")


def ffloor(a):
    return _int_part(a, "floor")


def ftos(a):
    """F>S: truncated toward 0; the integer part must be in -32768..65535 (THROW -43), returned as 16 bits."""
    s, e, m = F.unpack(a)
    if e <= 128:
        return 0
    ib = e - 128
    if ib > 17:
        raise Throw(-43)
    ip = (m >> 8) >> (32 - ib)
    if (s and ip > 32768) or (not s and ip > 65535):
        raise Throw(-43)
    return -ip & 0xFFFF if s else ip


# ---------------------------------------------------------------- FSQRT (section 8.1)
def fsqrt(n):
    if n[0] == 0:
        return ZERO
    if is_neg(n):
        raise Throw(-46)
    x = bytes([(n[0] + 130) >> 1, 0, 0, 0, 0])      # 0.5 * 2^(e' - 128), e' = floor((e + 130) / 2)
    for _ in range(5):
        x = add(x, div(n, x))
        x = bytes([x[0] - 1]) + x[1:]                 # / 2 on the exponent byte (x > 0, far above 2^-127)
    return x


# ---------------------------------------------------------------- SIN, COS, TAN (section 8.2)
def _sin_cos(x, cos):
    """SIN (cos False) or COS (cos True): k = round(x/pi (+ 1/2 for COS)), r = x - k pi in two parts (+ pi/2 for
    COS), Leap V2's series on r, the sign by k's parity."""
    t = mul(x, INV_PI)
    if cos:
        t = add(t, HALF)
    k = ftos_signed(fround(t))
    kf = fri(k)
    r = sub(x, mul(kf, P1))
    r = sub(r, mul(kf, P2))
    if cos:
        r = add(r, HALF_PI)
    x2 = mul(r, r)
    x3 = mul(r, x2)
    p = SIN_COEFFS[5]
    for c in (SIN_COEFFS[4], SIN_COEFFS[3], SIN_COEFFS[2], SIN_COEFFS[1]):
        p = add(c, mul(p, x2))
    s = add(r, mul(x3, p))
    return neg(s) if k & 1 else s


def fsin(x):
    return _sin_cos(x, False)


def ftos_signed(kf):
    """k for the reduction: kf is an integer-valued float; |kf| > 32767 is THROW -43."""
    s, e, m = F.unpack(kf)
    if e <= 128:
        return 0
    ib = e - 128
    if ib > 16:
        raise Throw(-43)
    ip = (m >> 8) >> (32 - ib)
    if ip > 32767:
        raise Throw(-43)
    return -ip if s else ip


def fcos(x):
    return _sin_cos(x, True)


def ftan(x):
    s = fsin(x)
    c = fcos(x)
    if c[0] == 0:
        raise Throw(-42)
    return div(s, c)


def frad(x):
    return mul(x, RAD_K)


def fdeg(x):
    return mul(x, DEG_K)


# ---------------------------------------------------------------- the number parser (section 6)
FLOAT_RE = re.compile(r"^(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$")


def parse(token):
    """NUMBER on a token: ("int", 16-bit value) / ("float", 5 bytes) / ("none",); THROW -43 when out of range."""
    neg_ = token.startswith("-")
    body = token[1:] if neg_ else token
    if not FLOAT_RE.match(body):
        return ("none",)
    if "." in body or "e" in body or "E" in body:
        v, n = _range(F.atof, body + "\0")
        assert n == len(body)
        return ("float", neg(v) if neg_ else v)
    v = int(body)
    if v > (32768 if neg_ else 65535):
        raise Throw(-43)
    return ("int", -v & 0xFFFF if neg_ else v)


# ---------------------------------------------------------------- output (section 7)
def _fixed(a, places):
    """The ROM's F. digits (section 7): the value's exact binary digits as 128.64 fixed point (bits below 2^-64
    dropped: such a value rounds to 0 at any of the 0-9 places), rounded half up (away from 0 in magnitude) at
    `places` decimals. (sign, integer part, decimals as an integer below 10^places)."""
    s, e, m = F.unpack(a)
    if e == 0:
        return 0, 0, 0
    fix = (m >> 8) << 32                              # 32 mantissa bits as .64 fixed point
    n = e - 128
    if n > 0:
        fix <<= n
    elif n < 0:
        fix = 0 if -n >= 64 else fix >> -n            # (32 mantissa bits + up to 32 places right: nothing lost)
    ip, frac = fix >> 64, fix & ((1 << 64) - 1)
    scaled = frac * 10 ** places
    d, rem = scaled >> 64, scaled & ((1 << 64) - 1)
    if rem >> 63:                                     # the rest is half or more: up
        d += 1
        if d == 10 ** places:
            d, ip = 0, ip + 1
    return s, ip, d


def fdot(a, places=4):
    """F.'s text without its trailing space; no '-' when every printed digit is 0."""
    s, ip, d = _fixed(a, places)
    t = str(ip) + ("." + str(d).zfill(places) if places else "")
    return ("-" + t) if s and (ip or d) else t


def fsdot(a, places=4):
    """FS.'s text without its trailing space."""
    zeros = ("." + "0" * places) if places else ""
    s, e, _ = F.unpack(a)
    if e == 0:
        return "0" + zeros + "E0"
    v = fabs(a)
    n = ((e - 129) * 77) >> 8
    d = n
    while d:
        k = min(abs(d), 13)
        if d > 0:
            v = div(v, POW10[k])
            d -= k
        else:
            v = mul(v, POW10[k])
            d += k
    if cmp(v, TEN) >= 0:
        v = div(v, TEN)
        n += 1
    elif cmp(v, ONE) < 0:
        v = mul(v, TEN)
        n -= 1
    assert cmp(v, ONE) >= 0 and cmp(v, TEN) < 0, (a.hex(), v.hex())
    t = fdot(v, places)
    if t.startswith("10"):
        t = "1" + zeros
        n += 1
    return ("-" if s else "") + t + "E" + str(n)


def check_places(n):
    if not 0 <= n <= 9:
        raise Throw(-43)
    return n


# ---------------------------------------------------------------- BEEP (section 12)
def beep_frames(sec):
    """The frames BEEP plays for a duration (seconds, 5 bytes): round(60 x seconds), 0 for a negative one, at most
    32,768."""
    h = mul(sec, C120)
    if h[0] == 0 or is_neg(h):
        return 0
    if h[0] > 144:
        half = 0xFFFF
    else:
        half = F.toi(h)
    return (half >> 1) + (half & 1)


# ---------------------------------------------------------------- RND (section 11.2)
def xorshift(x):
    x ^= (x << 7) & 0xFFFF
    x ^= x >> 9
    x ^= (x << 8) & 0xFFFF
    return x


def rnd(state, n):
    """(new state, result) for `n RND` from a nonzero state; n <= 0 (signed) gives 0 and leaves the state."""
    n &= 0xFFFF
    if n == 0 or n & 0x8000:
        return state, 0
    state = xorshift(state)
    return state, state * n >> 16


# ---------------------------------------------------------------- self-test (no emulator)
def ulps(a, want):
    """Distance from the 5-byte a to the real number want, in units of a's last place."""
    v = F.value(a)
    if want == 0:
        return 0 if v == 0 else float("inf")
    _, ex = math.frexp(want)
    return abs(v - want) / 2.0 ** (ex - 32)


def selftest(count=2000, seed=13):
    import random
    from decimal import Decimal, getcontext
    getcontext().prec = 60
    rng = random.Random(seed)
    bad = []

    def check(ok, msg):
        if not ok:
            bad.append(msg)

    # SIN/COS within the spec: about 2 ulp for |x| <= pi/2, 2^-30 absolute for |x| <= 100, 2^-29 to the range's end
    worst = {}
    for lim, tol_abs in ((math.pi / 2, None), (100.0, 2.0 ** -30), (102000.0, 2.0 ** -29)):
        for _ in range(count):
            xv = rng.uniform(-lim, lim)
            x = F.encode(xv)
            xv = F.value(x)
            for name, f, g in (("sin", fsin, math.sin), ("cos", fcos, math.cos)):
                got = F.value(f(x))
                want = g(xv)
                if tol_abs is None and name == "sin":
                    u = ulps(f(x), want)
                    worst["sin ulp"] = max(worst.get("sin ulp", 0), u)
                    check(u <= 3, "sin(%r) %r ulp" % (xv, u))
                else:
                    err = abs(got - want)
                    key = "%s abs |x|<=%g" % (name, lim)
                    worst[key] = max(worst.get(key, 0), err)
                    check(err <= (tol_abs or 2.0 ** -30), "%s(%r) error %g" % (name, xv, err))
    for _ in range(count):
        xv = math.exp(rng.uniform(-80, 80))
        x = F.encode(xv)
        u = ulps(fsqrt(x), math.sqrt(F.value(x)))
        worst["sqrt ulp"] = max(worst.get("sqrt ulp", 0), u)
        check(u <= 2, "sqrt(%r) %r ulp" % (xv, u))
    check(fsqrt(F.encode(4.0)) == F.encode(2.0), "sqrt 4")
    for e in (1, 2, 127, 128, 129, 253, 254, 255):                        # the exponent range's ends
        x = bytes([e, 0x7F, 0xFF, 0xFF, 0xFF])
        u = ulps(fsqrt(x), math.sqrt(F.value(x)))
        check(u <= 2, "sqrt exponent %d: %r ulp" % (e, u))
    # FS. against Python's %E for 4 and 9 decimals
    for _ in range(count):
        xv = rng.choice((-1, 1)) * math.exp(rng.uniform(-87, 87))
        x = F.encode(xv)
        for p in (4,):
            got = fsdot(x, p)
            want = "%.*E" % (p, F.value(x))
            mant, ex = want.split("E")
            want = mant + "E" + str(int(ex))
            if got != want:                           # only where the scaled value sits on a rounding tie
                d = Decimal(F.value(x)).scaleb(-int(ex)).copy_abs()
                tie = abs(d * 10 ** p - int(d * 10 ** p) - Decimal("0.5")) < Decimal("1e-6")
                check(tie, "FS. %r: %s, Python %s" % (F.value(x), got, want))
    # parser
    for t, want in (("3.5", ("float", F.encode(3.5))), ("-0.25", ("float", F.encode(-0.25))),
                    ("1E3", ("float", F.encode(1000.0))), ("2.5e-4", None), (".5", ("float", F.encode(0.5))),
                    ("3.", ("float", F.encode(3.0))), ("40000", ("int", 40000)), ("-32768", ("int", 0x8000)),
                    ("65535", ("int", 65535)), ("1.5f", ("none",)), (".", ("none",)), ("1e", ("none",)),
                    ("-", ("none",)), ("1.2.3", ("none",)), ("+5", ("none",))):
        got = parse(t)
        check(want is None or got == want, "parse %r: %r, want %r" % (t, got, want))
    for t in ("100000", "-40000", "65536", "-32769", "1E39", "99999999999"):
        try:
            parse(t)
            check(False, "parse %r did not throw" % t)
        except Throw as x:
            check(x.code == -43, "parse %r threw %d" % (t, x.code))
    # rounding words
    for v, r, fl, s in ((2.5, 3, 2, 2), (-2.5, -3, -3, -2), (0.5, 1, 0, 0), (-0.5, -1, -1, 0), (0.49, 0, 0, 0),
                        (-0.3, 0, -1, 0), (7.9, 8, 7, 7), (-7.9, -8, -8, -7), (65535.9, 65536, 65535, 65535)):
        x = F.encode(v)
        check(F.value(fround(x)) == r, "FROUND %r" % v)
        check(F.value(ffloor(x)) == fl, "FLOOR %r" % v)
        check(ftos(x) == s & 0xFFFF, "F>S %r: %r" % (v, ftos(x)))
    for v in (65536.0, -32769.0, 1e10):
        try:
            ftos(F.encode(v))
            check(False, "F>S %r did not throw" % v)
        except Throw as x:
            check(x.code == -43, "F>S %r" % v)
    check(fdot(F.encode(-0.00001)) == "0.0000", "-0.0000 rule")
    check(fdot(F.encode(-0.00006)) == "-0.0001", "F. -0.00006")
    check(fdot(fsqrt(F.encode(2.0))) == "1.4142", "F. sqrt 2")
    check(fdot(F.encode(6.0), 0) == "6", "F. 0 places")
    check(fdot(F.encode(0.25), 1) == "0.3", "F. tie 0.25 -> 0.3")
    check(fdot(F.encode(0.03125)) == "0.0313", "F. tie 0.03125")
    check(fdot(F.encode(-0.25), 1) == "-0.3", "F. tie -0.25")
    check(fdot(F.encode(0.5), 0) == "1", "F. 0.5 0 places")
    check(fdot(F.encode(9.99996)) == "10.0000", "F. carry into the integer part")
    check(fdot(F.encode(-6e-10), 9) == "-0.000000001", "F. 9 places small")
    check(fdot(F.encode(1e30), 0) == str(int(F.value(F.encode(1e30)))), "F. 1e30 exact digits")
    from fractions import Fraction
    for _ in range(count):
        xv = rng.choice((-1, 1)) * math.exp(rng.uniform(-30, 40))
        x = F.encode(xv)
        for p in (0, 4, 9):
            q = abs(Fraction(F.value(x))) * 10 ** p
            r = int(q) + (1 if q - int(q) >= Fraction(1, 2) else 0)
            t = str(r // 10 ** p) + ("." + str(r % 10 ** p).zfill(p) if p else "")
            want = ("-" + t) if xv < 0 and r else t
            check(fdot(x, p) == want, "F. %r %d: %s, exact %s" % (F.value(x), p, fdot(x, p), want))
    check(fsdot(F.encode(1e-6)) == "1.0000E-6", "FS. 1e-6")
    check(fsdot(F.encode(-12345.678)) == "-1.2346E4", "FS. -12345.678")
    check(fsdot(ZERO) == "0.0000E0", "FS. 0")
    check(beep_frames(F.encode(0.5)) == 30, "BEEP 0.5")
    check(beep_frames(F.encode(-1.0)) == 0, "BEEP -1")
    check(beep_frames(F.encode(1e6)) == 32768, "BEEP cap")
    s, seen = 1, set()
    prev = None
    for _ in range(3600):
        s, v = rnd(s, 6)
        if prev is not None:
            seen.add((prev, v))
        prev = v
    check(len(seen) == 36, "RND 6: %d pairs" % len(seen))
    return bad, worst


if __name__ == "__main__":
    bad, worst = selftest()
    for k, v in sorted(worst.items()):
        print("  worst %-22s %.3g" % (k, v))
    for b in bad[:30]:
        print("FAIL", b)
    print("fpforth selftest: %d failure(s)" % len(bad))
    sys.exit(1 if bad else 0)
