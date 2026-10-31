#!/usr/bin/env python3
"""
tools/tape_gen_forth.py — builds a real, standard .TAP file matching
2068-Forth's own tape wire format (kernel/storage/storage.asm), for real
(non-fake) LOAD-TEXT/LOAD-LIB testing under real Fuse tape emulation.

WHY THIS IS DIFFERENT FROM ts2068rom's tools/tape_gen.py: that project's
own protocol is a from-scratch, non-standard framing (many small
128-byte blocks, each sent twice), so it needed a hand-built Direct
Recording TZX with hand-tuned pulse widths. 2068-Forth's kernel/storage/
storage.asm sends and receives blocks through Leap-C's clean-room
kernel/storage/tapeblock.asm (since audit step S; written from a public
format description, not from the stock ROM's SA-BYTES/LD-BYTES) — one
header block (flag $00) + one data block (flag $FF), standard pilot/
sync/bit pulse widths, standard XOR checksum. The wire format is the
standard Sinclair one. That means a real,
plain .TAP file (the classic [len_lo][len_hi][flag][...data...]
[checksum] block framing) is *already* the exact real wire format —
Fuse's own standard tape engine generates the genuine pulse train from
it, no hand-rolled sample data needed, and no scale-fudging: this
project's receiver decodes the standard format (unlike ts2068rom's,
which needed empirical retuning for a genuinely new protocol).

Checksum convention (confirmed against kernel/storage/storage.asm's own
STORAGE_SEND_BLOCK: the running checksum in H starts as the type-flag
byte itself, then XORs in every payload byte) matches the standard
Sinclair block checksum exactly: checksum = flag ^ payload[0] ^ ... ^
payload[-1].

Header payload layout (STORAGE_HEADER_* offsets in kernel/storage/
storage.asm):
    byte 0      : file type (always 0 here, a text tape as SAVE-TEXT
                  writes it; SAVE-LIB tapes are type 3 and carry the
                  ROM identity, so this tool does not make them)
    bytes 1-10  : filename, space-padded to 10 characters
    bytes 11-12 : data length, little-endian
    bytes 13-14 : autostart word (STORAGE_NO_AUTOSTART = 0x8000), LE
    bytes 15-16 : "program length" (same as data length here), LE

Usage:
    python3 tools/tape_gen_forth.py <output.tap> <name>:<file> [<name>:<file> ...]

Each <name>:<file> becomes one header+data block pair on the tape, in
the order given (STORAGE_LOAD searches forward from the tape's current
position, so multiple named files on one tape load correctly in
sequence, exactly like a real multi-program cassette).

Example (what tools/tapetest.py case 2 plays):
    python3 tools/tape_gen_forth.py build/bj.tap BJPROG:tests/data/blackjack_rounds.txt
"""
import sys

HEADER_FILENAME_LEN = 10
TYPE_HEADER = 0x00
TYPE_DATA = 0xFF
NO_AUTOSTART = 0x8000


def checksum(flag: int, payload: bytes) -> int:
    c = flag
    for b in payload:
        c ^= b
    return c


def build_block(flag: int, payload: bytes) -> bytes:
    body = bytes([flag]) + payload + bytes([checksum(flag, payload)])
    length = len(body)
    return length.to_bytes(2, "little") + body


def build_header_payload(name: str, data_len: int) -> bytes:
    name_bytes = name.encode("ascii")
    if len(name_bytes) > HEADER_FILENAME_LEN:
        raise ValueError(f"filename {name!r} exceeds {HEADER_FILENAME_LEN} chars")
    name_bytes = name_bytes + b" " * (HEADER_FILENAME_LEN - len(name_bytes))
    payload = bytearray()
    payload.append(0)                                   # file type
    payload += name_bytes                                # 10 bytes
    payload += data_len.to_bytes(2, "little")            # data length
    payload += NO_AUTOSTART.to_bytes(2, "little")        # autostart
    payload += data_len.to_bytes(2, "little")            # "program length"
    assert len(payload) == 17
    return bytes(payload)


def build_tap(entries) -> bytes:
    out = bytearray()
    for name, data in entries:
        out += build_block(TYPE_HEADER, build_header_payload(name, len(data)))
        out += build_block(TYPE_DATA, data)
    return bytes(out)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)
    out_path = sys.argv[1]
    entries = []
    for spec in sys.argv[2:]:
        name, _, path = spec.partition(":")
        if not path:
            raise SystemExit(f"bad entry {spec!r}, expected NAME:FILE")
        with open(path, "rb") as f:
            data = f.read()
        entries.append((name, data))

    tap = build_tap(entries)
    with open(out_path, "wb") as f:
        f.write(tap)

    print(f"wrote {out_path}: {len(tap)} bytes, {len(entries)} program(s)")
    for name, data in entries:
        print(f"  {name!r}: {len(data)} data bytes")


if __name__ == "__main__":
    main()
