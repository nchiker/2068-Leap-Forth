#!/usr/bin/env python3
"""tapes.py - tape blocks, files and signals for the Forth tape oracle (tools/tapetest.py, tools/tapetol.py).

A port of 2068-Leap-C's tools/tapes.py (itself derived from 2068-Leap's tape_synth.py), kept to what 2068-Forth
needs.  Everything here is host-side Python (stdlib only); nothing touches an emulator.

BLOCKS AND FILES
  framed(flag, payload)            a tape block as the ROM sends it: flag, payload, XOR checksum of both
  unframe(block)                   (flag, payload, checksum_ok)
  header_payload(type, name, length, param1, param2)
                                   the 17-byte header payload (docs/V2/STORAGE_SPEC.md section 4): type, name
                                   (10 chars, space padded, truncated), data length, param 1, param 2 (all LE)
  parse_header(payload)            the same fields back, as a dict
  text_file(name, text)            TEXT (type 0): header param 1 = $8000, param 2 = length; data = the text
  lib_image(dict, latest, identity)  LIB data block payload (type 3): the dictionary bytes + CRC-16 low, high
  lib_file(name, dict, latest, identity)
                                   the two framed blocks of a LIB file (header type 3: length = dict + 2,
                                   param 1 = identity, param 2 = LATEST)
  v1_lib_file(name, dict, latest)  the old (V1) SAVE-LIB tape: type 0, payload = LATEST (LE) + dictionary bytes
  crc16(data)                      CRC-16/CCITT-FALSE: poly $1021, init $FFFF, MSB first, no final XOR
FILES
  tap(blocks), read_tap(data)      .tap bytes (2-byte length + block each) and back
  tzx(items, lead_ms)              .tzx bytes: a leading Pause (ID $20) of lead_ms (split in chunks of at most
                                   65 s), then the items: bytes = a standard-speed block (ID $10, 1 s pause after),
                                   ("pause", ms) = Pause block (ID $20), ("pulses", [T, ...]) = Pulse sequence
                                   (ID $13, 255 pulses per block; used for tapes with a dropout)
SIGNALS
  Tape                             an EAR signal as (level, T-states) runs at the standard widths (pilot 2168,
                                   syncs 667/735, bits 855/1710); block(data, pilot=, dropout=, truncate_after=)
                                   builds one block; pulses() the merged pulse widths; edges() the edge times
  edges_from_capture(values)       a capture (ZEsarUX `printe TSTATESP*16+(A&8)` at each `out ($FE),a`) as
                                   [(T-state, MIC level)] at the level changes; the 32-bit counter is unwrapped
                                   (it wraps at 2^32, 76 s of emulated time) and samples that are not an edge
                                   (same level as the one before: the sender's border-restore `out`) are dropped
  decode(edges)                    the blocks in an edge list (ported from Leap-C tapes.decode)

`python3 tools/tapes.py --selftest` round-trips a synthetic tape (header + data) through edges, a wrapped capture
and the decoder, and checks the writers and the CRC check value; it prints `tapes: selftest ok`.
"""
import struct
import sys
from functools import reduce
from operator import xor

sys.dont_write_bytecode = True

CPU_HZ = 3_528_000              # TS2068 CPU clock
PILOT_T, SYNC1_T, SYNC2_T, ZERO_T, ONE_T = 2168, 667, 735, 855, 1710       # the standard half-pulse widths
HEADER_PILOT, DATA_PILOT = 8063, 3223                                        # pilot half-pulses: flag < $80 / >= $80
TYPE_TEXT, TYPE_LIB = 0, 3      # header types (STORAGE_SPEC.md section 4)
NO_AUTOSTART = 0x8000           # TEXT header param 1
FLAG_HEADER, FLAG_DATA = 0x00, 0xFF
NAME_LEN = 10


# ----------------------------------------------------------------------------------------------- blocks
def framed(flag, payload):
    body = bytes([flag]) + bytes(payload)
    return body + bytes([reduce(xor, body, 0)])


def unframe(block):
    """(flag, payload, checksum_ok) of a framed block."""
    block = bytes(block)
    if len(block) < 2:
        return (block[0] if block else None), b"", False
    return block[0], block[1:-1], reduce(xor, block, 0) == 0


def name_bytes(name):
    nm = name.encode("latin-1") if isinstance(name, str) else bytes(name)
    return nm[:NAME_LEN].ljust(NAME_LEN, b" ")


def header_payload(htype, name, length, param1, param2):
    return bytes([htype]) + name_bytes(name) + struct.pack("<HHH", length & 0xFFFF, param1 & 0xFFFF, param2 & 0xFFFF)


def parse_header(payload):
    payload = bytes(payload)
    if len(payload) != 17:
        return None
    length, p1, p2 = struct.unpack_from("<HHH", payload, 11)
    return dict(type=payload[0], name=payload[1:11].decode("latin-1"), length=length, param1=p1, param2=p2)


def crc16(data, crc=0xFFFF):
    """CRC-16/CCITT-FALSE: polynomial $1021, init $FFFF, MSB first, no final XOR."""
    for b in bytes(data):
        crc ^= b << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if crc & 0x8000 else (crc << 1) & 0xFFFF
    return crc


def text_file(name, text):
    """The two framed blocks of a TEXT (type 0) file, as SAVE-TEXT / tools/tape_gen_forth.py write it."""
    data = text.encode("latin-1") if isinstance(text, str) else bytes(text)
    return [framed(FLAG_HEADER, header_payload(TYPE_TEXT, name, len(data), NO_AUTOSTART, len(data))),
            framed(FLAG_DATA, data)]


def lib_image(dictionary, latest=None, identity=None):
    """LIB data block payload: the dictionary bytes, then CRC-16 over them, low byte first (D4)."""
    d = bytes(dictionary)
    return d + struct.pack("<H", crc16(d))


def lib_file(name, dictionary, latest, identity, length=None, flag=FLAG_DATA, crc=None):
    """The two framed blocks of a LIB (type 3) file.  length / flag / crc override the header length, the data
    block flag and the CRC (to build malformed tapes)."""
    d = bytes(dictionary)
    body = d + struct.pack("<H", crc16(d) if crc is None else crc)
    ln = len(body) if length is None else length
    return [framed(FLAG_HEADER, header_payload(TYPE_LIB, name, ln, identity, latest)), framed(flag, body)]


def v1_lib_file(name, dictionary, latest):
    """The old (V1) SAVE-LIB tape: header type 0, data = LATEST (LE) + the dictionary bytes."""
    body = struct.pack("<H", latest) + bytes(dictionary)
    return [framed(FLAG_HEADER, header_payload(TYPE_TEXT, name, len(body), NO_AUTOSTART, len(body))),
            framed(FLAG_DATA, body)]


# ----------------------------------------------------------------------------------------------- files
def tap(blocks):
    return b"".join(struct.pack("<H", len(b)) + b for b in blocks)


def read_tap(data):
    """The blocks of a .tap file."""
    out, p = [], 0
    while p + 2 <= len(data):
        n = data[p] | data[p + 1] << 8
        out.append(bytes(data[p + 2:p + 2 + n]))
        p += 2 + n
    return out


def tzx(items, lead_ms=0, pause_ms=1000):
    """A .tzx file.  lead_ms: a leading Pause block (ID $20), split into chunks of at most 65 s (the field is 16 bit).
    items: bytes -> standard-speed block (ID $10, pause_ms after it); ("pause", ms) -> Pause block (ID $20);
    ("pulses", [T, ...]) -> Pulse sequence blocks (ID $13, up to 255 pulses each)."""
    out = bytearray(b"ZXTape!\x1a\x01\x14")
    while lead_ms > 0:
        n = min(lead_ms, 65000)
        out += b"\x20" + struct.pack("<H", n)
        lead_ms -= n
    for it in items:
        if isinstance(it, (bytes, bytearray)):
            out += b"\x10" + struct.pack("<HH", pause_ms, len(it)) + bytes(it)
        elif it[0] == "pause":
            ms = it[1]
            while ms > 0:
                n = min(ms, 65000)
                out += b"\x20" + struct.pack("<H", n)
                ms -= n
        elif it[0] == "pulses":
            w = list(it[1])
            for i in range(0, len(w), 255):
                part = w[i:i + 255]
                if any(not 0 < x <= 0xFFFF for x in part):
                    raise ValueError("pulse width out of the 16 bit range of ID $13")
                out += b"\x13" + bytes([len(part)]) + struct.pack("<%dH" % len(part), *part)
        else:
            raise ValueError("bad tzx item %r" % (it[0],))
    return bytes(out)


# ----------------------------------------------------------------------------------------------- signals
class Tape:
    """An EAR signal: (level, T-states) runs; each pulse flips the level; a flat run is no edge for a while."""

    def __init__(self):
        self.runs = []
        self.level = 0

    def pulse(self, t):
        self.runs.append((self.level, t))
        self.level ^= 1

    def flat(self, t):
        """No edge for t T-states (silence, a dropout): it is merged into the next pulse."""
        self.runs.append((self.level, t))

    def silence(self, seconds):
        self.flat(int(seconds * CPU_HZ))

    def block(self, data, pilot=None, dropout=None, truncate_after=None, gap=0.5):
        """One framed block (flag .. checksum in `data`): pilot, the two sync pulses, two half-pulses per bit (most
        significant first), a closing pulse, then `gap` seconds of silence.  dropout=(first, count): those bytes
        (0 = the flag) are a flat stretch of the same duration; truncate_after=n: only the first n bytes, then
        silence."""
        n = (HEADER_PILOT if data[0] < 0x80 else DATA_PILOT) if pilot is None else pilot
        for _ in range(n):
            self.pulse(PILOT_T)
        self.pulse(SYNC1_T)
        self.pulse(SYNC2_T)
        for i, v in enumerate(data):
            if truncate_after is not None and i >= truncate_after:
                break
            widths = []
            for k in range(7, -1, -1):
                w = ONE_T if v >> k & 1 else ZERO_T
                widths += [w, w]
            if dropout and dropout[0] <= i < dropout[0] + dropout[1]:
                self.flat(sum(widths))
            else:
                for w in widths:
                    self.pulse(w)
        self.pulse(ZERO_T)
        self.silence(gap)
        return self

    def pulses(self):
        """The pulse widths, runs of the same level merged (a flat stretch joins the pulse after it); trailing
        silence is dropped."""
        runs = list(self.runs)
        while runs and runs[-1][0] == self.level:       # trailing silence: no pulse follows it, no edge ends it
            runs.pop()
        out, lv = [], None
        for level, t in runs:
            if out and lv == level:
                out[-1] += t
            else:
                out.append(t)
            lv = level
        return out

    def edges(self, t0=0):
        """[(T-state, level)] at each edge, the level after the edge."""
        out, t, lv = [], t0, 0
        for w in self.pulses():
            t += w
            lv ^= 1
            out.append((t, lv))
        return out


def edges_from_capture(values):
    """ZEsarUX capture lines (`printe TSTATESP*16 + (A & 8)` at each `out ($FE),a`) -> [(T, MIC level)] at the level
    changes, the 32-bit counter unwrapped.  A sample at the level the signal already has (the sender's border
    restore) is not an edge and is dropped."""
    out, base, prev = [], 0, None
    for v in values:
        v &= 0xFFFFFFFF
        if prev is not None and v < prev:
            base += 1 << 32
        prev = v
        t, level = (base + v) >> 4, (v >> 3) & 1
        if not out or out[-1][1] != level:
            out.append((t, level))
    return out


def capture_values(edges, extra_same_level=(), wrap_at=None):
    """The capture lines for an edge list (the inverse of edges_from_capture, for the selftest): the counter value
    TSTATESP*16 + level*8 truncated to 32 bits; extra_same_level = indexes of edges after which a repeat sample at
    the same level is added (a border-restore `out`)."""
    vals = []
    for i, (t, lv) in enumerate(edges):
        vals.append(((t << 4) | (lv << 3)) & 0xFFFFFFFF)
        if i in extra_same_level:
            vals.append(((t + 20) << 4 | lv << 3) & 0xFFFFFFFF)
    return vals


def decode(edges):
    """The blocks in a MIC signal.  Returns [dict(data=framed bytes, ok=checksum, pilot=pulses, widths={"pilot",
    "sync1", "sync2", "zero", "one": (min, max)}, extra_bits=n, start=T-state of the first pilot edge)].  A block is
    pilot pulses (1,900-2,500 T), two sync pulses and bit pulses in pairs; a pulse over 2,500 T ends it."""
    w = [(t1 - t0) for (t0, _), (t1, _) in zip(edges, edges[1:])]
    blocks, i = [], 0

    def span(name, x, d):
        lo, hi = d.get(name, (x, x))
        d[name] = (min(lo, x), max(hi, x))

    while i < len(w):
        while i < len(w) and not 1900 <= w[i] <= 2500:
            i += 1
        start, n, widths = edges[i][0] if i < len(w) else 0, 0, {}
        while i < len(w) and 1900 <= w[i] <= 2500:
            span("pilot", w[i], widths)
            n += 1
            i += 1
        if i + 1 >= len(w) or n < 100:
            if n < 100:
                continue
            break
        span("sync1", w[i], widths)
        span("sync2", w[i + 1], widths)
        i += 2
        bits = []
        while i + 1 < len(w) and w[i] < 2500 and w[i + 1] < 2500:
            b = 1 if w[i] + w[i + 1] > 2 * (ZERO_T + ONE_T) / 2 else 0
            span("one" if b else "zero", w[i], widths)
            span("one" if b else "zero", w[i + 1], widths)
            bits.append(b)
            i += 2
        data = bytes(int("".join(map(str, bits[k:k + 8])), 2) for k in range(0, len(bits) - len(bits) % 8, 8))
        blocks.append(dict(data=data, ok=bool(data) and reduce(xor, data, 0) == 0, pilot=n, widths=widths,
                           extra_bits=len(bits) % 8, start=start))
    return blocks


# ----------------------------------------------------------------------------------------------- selftest
def selftest():
    assert crc16(b"123456789") == 0x29B1, "CRC-16/CCITT-FALSE check value is %04X, expected 29B1" % crc16(b"123456789")
    assert crc16(b"") == 0xFFFF
    # framing / header / lib image
    hp = header_payload(TYPE_LIB, "DEMO", 0x1234, 0x8ABC, 0x9999)
    assert len(hp) == 17 and hp[:1] == b"\x03" and hp[1:11] == b"DEMO      "
    assert parse_header(hp) == dict(type=3, name="DEMO      ", length=0x1234, param1=0x8ABC, param2=0x9999)
    assert header_payload(0, "ABCDEFGHIJKLMNO", 1, 2, 3)[1:11] == b"ABCDEFGHIJ"
    blk = framed(0xFF, b"\x01\x02\x03")
    assert blk == b"\xff\x01\x02\x03" + bytes([0xFF ^ 1 ^ 2 ^ 3]) and unframe(blk) == (0xFF, b"\x01\x02\x03", True)
    assert unframe(blk[:-1] + b"\x00")[2] is False
    d = bytes(range(40))
    img = lib_image(d)
    assert img[:40] == d and img[40:] == struct.pack("<H", crc16(d)) and crc16(img) == crc16(d + struct.pack("<H", crc16(d)))
    h, data = lib_file("LIBX", d, 0x9C00, 0x8123)
    assert parse_header(unframe(h)[1])["length"] == 42 and unframe(data)[1] == img
    # .tap / .tzx writers
    blocks = text_file("T", "1 2 +")
    assert read_tap(tap(blocks)) == blocks
    z = tzx(blocks + [("pause", 70000), ("pulses", [2168] * 300)], lead_ms=130000)
    assert z[:10] == b"ZXTape!\x1a\x01\x14" and z[10] == 0x20 and z.count(b"\x20") >= 3
    # a synthetic tape (header + data, standard widths) -> edges -> decode
    t = Tape()
    for b in blocks:
        t.block(b)
    edges = t.edges()
    got = decode(edges)
    assert [g["data"] for g in got] == blocks and all(g["ok"] for g in got), "decode of the synthetic tape differs"
    # (the first pilot pulse of a block is measured from the silence before it: not counted)
    assert got[0]["pilot"] in (HEADER_PILOT, HEADER_PILOT - 1) and got[1]["pilot"] in (DATA_PILOT, DATA_PILOT - 1)
    assert got[0]["widths"]["zero"] == (ZERO_T, ZERO_T) and got[0]["widths"]["one"] == (ONE_T, ONE_T)
    # through a capture: counter wrapping at 2^32 (starts 3 s before the wrap), repeat samples at the same level
    wrap_t = (1 << 32) // 16
    shifted = [(tt + wrap_t - 3 * CPU_HZ, lv) for tt, lv in t.edges()]
    vals = capture_values(shifted, extra_same_level={len(shifted) // 3, len(shifted) - 1})
    assert max(vals) > (1 << 31) and vals[-1] < (1 << 31), "the capture did not wrap"
    again = decode(edges_from_capture(vals))
    assert [g["data"] for g in again] == blocks, "decode through a wrapped capture differs"
    assert len(edges_from_capture(vals)) == len(edges)
    # a dropout is a flat stretch: the block is cut short and its checksum fails
    t2 = Tape()
    t2.block(blocks[0]).block(blocks[1], dropout=(2, 2))
    g2 = decode(t2.edges())
    assert g2[0]["data"] == blocks[0] and g2[1]["ok"] is False and len(g2[1]["data"]) < len(blocks[1])
    # a truncated block
    g3 = decode(Tape().block(blocks[0], truncate_after=5).edges())
    assert len(g3) == 1 and len(g3[0]["data"]) == 5
    # the tzx pulse export of a tape with a dropout parses back to the same pulses
    t4 = Tape().block(blocks[1], dropout=(2, 2), gap=0)
    zp = tzx([("pulses", t4.pulses())])
    p, pulses = 10, []
    while p < len(zp):
        assert zp[p] == 0x13
        n = zp[p + 1]
        pulses += struct.unpack_from("<%dH" % n, zp, p + 2)
        p += 2 + 2 * n
    assert pulses == t4.pulses() and max(pulses) > 2 * ONE_T * 8
    print("tapes: selftest ok")


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        selftest()
    else:
        print(__doc__)
        sys.exit(2)
