"""A bit-exact model of the Leap-C float core (src/runtime/fpcore.asm; spec.md 4.9; Phase 8).

Floats are the Sinclair 5-byte format: [exponent][sign | mantissa bits 30-24][23-16][15-8][7-0],
value 0.1m x 2^(exponent - 128), 0 when the exponent is 0. Every function here follows the ROM's
algorithm step by step (the 40-bit working mantissa, the truncations, the round-to-nearest when
packing), so the ROM's results can be compared byte for byte; `value()` and `encode()` relate the
format to Python floats for checks against real arithmetic.

Errors are raised as FloatError("range") (overflow, division by 0) or FloatError("number")
(a malformed constant), as the ROM's F_ERR with E_RANGE / E_NUMBER.
"""
import math

M40 = (1 << 40) - 1
M32 = (1 << 32) - 1


class FloatError(Exception):
    pass


# ---------------------------------------------------------------- format
def unpack(b):
    """FUNPK: 5 bytes -> (sign 0/0x80, exponent, 40-bit mantissa: 32 bits and a zero guard byte). A
    zero (exponent 0) gets sign 0 and keeps its raw mantissa bytes, as in the ROM."""
    e = b[0]
    m = (b[1] | (0x80 if e else 0)) << 32 | b[2] << 24 | b[3] << 16 | b[4] << 8
    return (b[1] & 0x80 if e else 0, e, m)


def pack(s, e, m):
    """FPACK: round to nearest on the guard's top bit, then 5 bytes."""
    if e == 0:
        return bytes(5)
    m32 = m >> 8
    if m & 0x80:
        m32 += 1
        if m32 > M32:
            m32 = 1 << 31
            e += 1
            if e > 255:
                raise FloatError("range")
    return bytes([e, (m32 >> 24 & 0x7F) | s, m32 >> 16 & 255, m32 >> 8 & 255, m32 & 255])


def norm(s, e, m):
    """FNORM: shift left until bit 39 is set; 0 when the mantissa is 0 or e falls below 1."""
    if m == 0:
        return (0, 0, 0)
    while not m >> 39 & 1:
        e -= 1
        if e == 0:
            return (0, 0, 0)
        m = m << 1 & M40
    return (s, e, m)


# ---------------------------------------------------------------- arithmetic on unpacked values
def add(x, y):
    xs, xe, xm = x
    ys, ye, ym = y
    if ye == 0:
        return x
    if xe == 0:
        return y
    if (ye, ym) > (xe, xm):
        xs, xe, xm, ys, ye, ym = ys, ye, ym, xs, xe, xm
    d = xe - ye
    if d >= 40:
        return (xs, xe, xm)
    ym >>= d
    if xs == ys:
        m = xm + ym
        if m > M40:
            m = 1 << 39 | (m & M40) >> 1
            xe += 1
            if xe > 255:
                raise FloatError("range")
        return (xs, xe, m)
    return norm(xs, xe, xm - ym)


def _done(s, e, q):
    """FDONE: mantissa q (40 bits), one normalising step, the range."""
    if not q >> 39 & 1:
        e -= 1
        q = q << 1 & M40
    if e > 255:
        raise FloatError("range")
    if e <= 0:
        return (0, 0, 0)
    return (s, e, q)


def mul(x, y):
    xs, xe, xm = x
    ys, ye, ym = y
    if xe == 0:
        return x
    if ye == 0:
        return (0, 0, 0)
    s = xs ^ ys
    e = xe + ye
    x32 = xm >> 8
    mult = ym >> 8
    q = 0
    for _ in range(32):
        bit = mult & 1
        mult >>= 1
        carry = 0
        if bit:
            top = (q >> 8) + x32
            carry = top >> 32
            q = (top & M32) << 8 | (q & 0xFF)
        q = carry << 39 | q >> 1
    return _done(s, e - 128, q)


def div(x, y):
    xs, xe, xm = x
    ys, ye, ym = y
    if ye == 0:
        raise FloatError("range")
    if xe == 0:
        return x
    s = xs ^ ys
    e = xe - ye
    r = xm >> 8
    d = ym >> 8
    c = 0
    q = 0
    for _ in range(40):
        r2 = r - d
        if r2 >= 0 or c:
            r = r2 & M32
            bit = 1
        else:
            bit = 0
        q = (q << 1 | bit) & M40
        c = r >> 31 & 1
        r = r << 1 & M32
    return _done(s, e + 129, q)


def cmp(x, y):
    """-1, 0, 1 as the ROM's flags (C, Z, NC NZ)."""
    xs, xe, xm = x
    ys, ye, ym = y
    if xs != ys:
        return -1 if xs else 1
    a, b = (xe, xm >> 8), (ye, ym >> 8)
    if xs:
        a, b = b, a
    return (a > b) - (a < b)


# ---------------------------------------------------------------- the operations (FOP_*)
def fri(v):
    v &= 0xFFFF
    s = 0
    if v & 0x8000:
        s, v = 0x80, -v & 0xFFFF if v != 0x8000 else 0x8000
    return pack(*norm(s, 144, v << 24))


def fru(v):
    return pack(*norm(0, 144, (v & 0xFFFF) << 24))


def toi(b):
    s, e, m = unpack(b)
    if e <= 128:
        return 0
    n = min(e - 128, 48)
    hl = 0
    for _ in range(n):
        hl = (hl << 1 | m >> 39 & 1) & 0xFFFF
        m = m << 1 & M40
    return -hl & 0xFFFF if s else hl


def neg(b):
    if b[0] == 0:
        return bytes(b)
    return bytes([b[0], b[1] ^ 0x80]) + bytes(b[2:])


ONE = bytes([0x81, 0, 0, 0, 0])
MONE = bytes([0x81, 0x80, 0, 0, 0])
TEN = bytes([0x84, 0x20, 0, 0, 0])
POW10 = {k: pack(*norm(0, 128 + (10 ** k).bit_length(), (10 ** k << 40) >> (10 ** k).bit_length()))
         for k in range(1, 14)}


def binop(op, left, right):
    """op: '+', '-', '*', '/' -> 5 bytes; 'cmp' -> -1/0/1. Operands as 5 bytes."""
    x, y = unpack(left), unpack(right)
    if op == "cmp":
        return cmp(x, y)
    if op == "-":
        y = (y[0] ^ 0x80, y[1], y[2])
    f = {"+": add, "-": add, "*": mul, "/": div}[op]
    return pack(*f(x, y))


def inc(b):
    return binop("+", ONE, b)


def dec(b):
    return binop("+", MONE, b)


# ---------------------------------------------------------------- decimal
def atof(text):
    """XF_ATOF on `text` (a str starting at the constant): (5 bytes, characters consumed)."""
    i = 0
    n = 0
    dexp = 0
    digit = frac = False
    t = text + "\0"
    while True:
        ch = t[i]
        if ch == ".":
            i += 1
            frac = not frac
            if frac:
                continue
            i -= 1
            break
        if not ch.isdigit():
            break
        i += 1
        digit = True
        if n >> 24 < 0x19:
            n = n * 10 + int(ch)
            if frac:
                dexp -= 1
        elif not frac:
            dexp += 1
    if not digit:
        raise FloatError("number")
    if t[i] in "eE":
        i += 1
        neg_e = False
        if t[i] in "+-":
            neg_e = t[i] == "-"
            i += 1
        ev = 0
        nd = 0
        while t[i].isdigit():
            ev = ev * 10 + int(t[i])
            i += 1
            nd += 1
            if ev >> 8 >= 4:
                ev = 999
        if nd == 0:
            raise FloatError("number")
        dexp += -ev if neg_e else ev
    if t[i] in "fFlL":
        i += 1
    if t[i] == "_" or t[i] == "." or t[i].isalnum():
        raise FloatError("number")
    acc = pack(*norm(0, 160, n << 8))
    while acc[0] != 0 and dexp != 0:               # by 10^k, k at most 13 (exact powers)
        k = min(abs(dexp), 13)
        if dexp > 0:
            acc = binop("*", POW10[k], acc)
            dexp -= k
        else:
            acc = binop("/", acc, POW10[k])
            dexp += k
    return acc, i


def ftoa(b, p):
    """XF_FTOA: the text of float b with p decimals (0-9)."""
    s, e, m = unpack(b)
    fix = 0                                     # 128.32 fixed point
    if e:
        fix = (m >> 8)
        n = e - 128
        if n > 0:
            fix = (fix << n) & ((1 << 160) - 1)
        elif n < 0:
            fix = 0 if -n >= 33 else fix >> -n
    r = 1 << 31
    for _ in range(p):
        r //= 10
    fix = (fix + r) & ((1 << 160) - 1)
    frac = fix & M32
    ip = fix >> 32
    out = ""
    for _ in range(p):
        frac *= 10
        out += chr(48 + (frac >> 32))
        frac &= M32
    txt = str(ip) + ("." + out if p else "")
    return ("-" if s else "") + txt


# ---------------------------------------------------------------- relation to Python floats
def value(b):
    s, e, m = unpack(b)
    if e == 0:
        return 0.0
    v = (m >> 8) / 2.0 ** 32 * 2.0 ** (e - 128)
    return -v if s else v


def encode(v):
    """The nearest 5-byte float to the Python float v (round half up on the 33rd bit)."""
    if v == 0:
        return bytes(5)
    s = 0x80 if v < 0 else 0
    f, ex = math.frexp(abs(v))                  # abs(v) = f * 2^ex, f in [0.5, 1)
    if not 0 < ex + 128 < 256:
        raise FloatError("range")
    return pack(s, ex + 128, int(f * 2 ** 40) & M40)
