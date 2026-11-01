#!/usr/bin/env python3
"""Pack a Forth program into a DOCK cartridge for a stock TS2068 (docs/cartridge.md; kernel/bank/cart.asm).

The program is a SAVE-LIB tape (.tap or .tzx) made on the release ROMs, or on the cartridge. The cartridge carries the
cartridge build's HOME image (DOCK chunks 0-1), the program image (chunks 2-3) and the EXROM (chunk 5); at power-on it
copies the dictionary to $9100 and the UDGs to the UDG table, then runs the start word as a line typed at the prompt.
Without --lib it is Forth alone (the prompt, as the release ROMs give it).

  forthcart.py [--cart DIR] [--lib PROG.tap --start WORD [--name NAME] [--udg FILE]] -o OUT.dck [--bin OUT.bin]

  --cart DIR    the cartridge build (make cart; default build/cart)
  --lib FILE    the SAVE-LIB tape; --name picks the file by its tape name when the tape holds more than one
  --start WORD  the word to run, defined in the program
  --udg FILE    the UDG table, 168 bytes (UDG_COUNT x 8), as in RAM; default all zero, as after a cold start
  -o OUT.dck    the cartridge as a Fuse/ZEsarUX/TSRun .dck (DOCK bank, chunks 0-3 and 5 as ROM)
  --bin OUT.bin the same as one flat 64 KB file, the chunks in address order, $FF where the DCK has none

The image format is kernel/bank/cart.asm's (offsets read from the build's symbols). As a module: read_lib(),
program_image(), dck(), flat_bin().
"""
import argparse
import os
import re
import struct
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import tapes  # noqa: E402

CHUNK = 0x2000


class CartError(Exception):
    pass


def symbols(path):
    return {m.group(1): int(m.group(2), 16)
            for m in re.finditer(r"^(\S+?):\s+EQU\s+0x([0-9A-Fa-f]+)$", open(path).read(), re.M)}


def read_tzx(data):
    """The standard-speed blocks (ID $10) of a .tzx file; pauses, groups, text and archive info are skipped."""
    if data[:8] != b"ZXTape!\x1a":
        raise CartError("not a TZX file")
    out, p = [], 10
    while p < len(data):
        bid = data[p]
        p += 1
        if bid == 0x10:
            n = data[p + 2] | data[p + 3] << 8
            out.append(bytes(data[p + 4:p + 4 + n]))
            p += 4 + n
        elif bid == 0x20:
            p += 2
        elif bid in (0x21, 0x30):
            p += 1 + data[p]
        elif bid == 0x22:
            pass
        elif bid == 0x32:
            p += 2 + (data[p] | data[p + 1] << 8)
        else:
            raise CartError(f"TZX block ${bid:02X} is not supported (save the tape as .tap, or at standard speed)")
    return out


def read_lib(path, name=None):
    """(dictionary, latest, identity, tape name) of the SAVE-LIB file on a .tap or .tzx tape."""
    data = open(path, "rb").read()
    blocks = read_tzx(data) if data[:8] == b"ZXTape!\x1a" else tapes.read_tap(data)
    found = []
    for i, block in enumerate(blocks[:-1]):
        flag, payload, ok = tapes.unframe(block)
        hdr = tapes.parse_header(payload) if flag == tapes.FLAG_HEADER and ok else None
        if hdr and hdr["type"] == tapes.TYPE_LIB and (name is None or hdr["name"].rstrip() == name):
            found.append((hdr, blocks[i + 1]))
    if not found:
        raise CartError(f"{path}: no SAVE-LIB file{' named ' + name if name else ''} on the tape")
    if len(found) > 1:
        raise CartError(f"{path}: {len(found)} SAVE-LIB files on the tape; pick one with --name")
    hdr, block = found[0]
    flag, body, ok = tapes.unframe(block)
    if flag != tapes.FLAG_DATA or not ok or len(body) != hdr["length"] or len(body) < 2:
        raise CartError(f"{path}: the data block of {hdr['name'].rstrip()} is damaged")
    dictionary, crc = body[:-2], body[-2] | body[-1] << 8
    if tapes.crc16(dictionary) != crc:
        raise CartError(f"{path}: the dictionary's CRC is wrong")
    return dictionary, hdr["param2"], hdr["param1"], hdr["name"].rstrip()


def find_word(dictionary, latest, base, name):
    """The name as the dictionary spells it, if `name` is one of the program's words (FIND matches either case)."""
    link, seen = latest, set()
    while base <= link < base + len(dictionary) - 2 and link not in seen:
        seen.add(link)
        at = link - base
        n = dictionary[at + 2] & 0x1F
        word = dictionary[at + 3:at + 3 + n].decode("latin-1")
        if word.upper() == name.upper():
            return word
        link = dictionary[at] | dictionary[at + 1] << 8
    return None


def program_image(S, dictionary, latest, identity, start, udg=None):
    """The program image (kernel/bank/cart.asm), checked as the cartridge will check it."""
    base, udg_len = S["FORTH_DICT_RAM"], S["UDG_COUNT"] * 8
    if identity != S["CART_ROM_IDENTITY"]:
        raise CartError(f"the program was saved by another ROM (identity ${identity:04X}; this build's is "
                        f"${S['CART_ROM_IDENTITY']:04X}): load its source on this build's ROMs and SAVE-LIB again")
    if len(dictionary) > S["CART_IMG_MAX"]:
        raise CartError(f"the dictionary is {len(dictionary)} bytes; at most {S['CART_IMG_MAX']} fit")
    word = find_word(dictionary, latest, base, start)
    if word is None:
        raise CartError(f"{start} is not one of the program's words")
    udg = bytes(udg_len) if udg is None else bytes(udg)
    if len(udg) != udg_len:
        raise CartError(f"the UDG table is {len(udg)} bytes, not {udg_len}")
    head = struct.pack("<HHHH", S["CART_MAGIC"], identity, len(dictionary), latest)
    head += bytes([len(word)]) + word.encode("latin-1").ljust(31, b" ")
    assert len(head) == S["CART_IMG_UDG"] and len(head) + udg_len == S["CART_IMG_DICT"]
    body = head + udg + bytes(dictionary)
    return body + struct.pack("<H", tapes.crc16(body))


def chunks(home, exrom, image=None):
    """{chunk: 8 KB} of the cartridge: HOME in 0-1, the image from 2, the EXROM in 5."""
    out = {0: home[:CHUNK], 1: home[CHUNK:], 5: exrom}
    if image:
        img = bytes(image) + b"\xff" * (-len(image) % CHUNK)
        for i in range(0, len(img), CHUNK):
            out[2 + i // CHUNK] = img[i:i + CHUNK]
    return out


def dck(home, exrom, image=None):
    """A .dck: bank 0 (DOCK), one descriptor per chunk (2 = ROM, 0 = none), then the ROM chunks in order."""
    c = chunks(home, exrom, image)
    return bytes([0] + [2 if i in c else 0 for i in range(8)]) + b"".join(c[i] for i in sorted(c))


def flat_bin(home, exrom, image=None):
    c = chunks(home, exrom, image)
    return b"".join(c.get(i, b"\xff" * CHUNK) for i in range(8))


def load_build(cart):
    S = symbols(os.path.join(cart, "forth_boot.sym"))
    home = open(os.path.join(cart, "forth_boot_rom0.bin"), "rb").read()
    exrom = open(os.path.join(cart, "graphics_exrom.bin"), "rb").read()
    S["CART_ROM_IDENTITY"] = home[S["ROM_IDENTITY"]] | home[S["ROM_IDENTITY"] + 1] << 8
    return S, home, exrom


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--cart", default="build/cart")
    ap.add_argument("--lib")
    ap.add_argument("--name")
    ap.add_argument("--start")
    ap.add_argument("--udg")
    ap.add_argument("-o", "--out", required=True)
    ap.add_argument("--bin")
    a = ap.parse_args(argv)
    if bool(a.lib) != bool(a.start):
        ap.error("--lib and --start go together")
    S, home, exrom = load_build(a.cart)
    image = None
    try:
        if a.lib:
            dictionary, latest, identity, tname = read_lib(a.lib, a.name)
            udg = open(a.udg, "rb").read() if a.udg else None
            image = program_image(S, dictionary, latest, identity, a.start, udg)
    except CartError as e:
        sys.exit(f"forthcart: {e}")
    open(a.out, "wb").write(dck(home, exrom, image))
    if a.bin:
        open(a.bin, "wb").write(flat_bin(home, exrom, image))
    what = f"{tname} ({len(dictionary)} B), start {a.start}" if image else "Forth, no program"
    print(f"forthcart: {a.out}: {what}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
