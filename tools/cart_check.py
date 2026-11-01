#!/usr/bin/env python3
"""Check the cartridge build against the release build (kernel/bank/cart.asm, CONTRIBUTING.md "The cartridge build"); `make cart`.

The cartridge's HOME image (assembled with -DCARTRIDGE) must keep every label of the release image at its address, so
a dictionary compiled on the release ROMs runs on the cartridge and LIB tapes go both ways. This checks, on every
`make cart`:
  - every release symbol has the same value in the cartridge's .sym, except the local labels inside the two paging
    routines (BANK_PAGE_EXROM_IN, _OUT), which have the cartridge's own bodies in the same bytes;
  - the images differ only in the LROS header ($0000-$0004), COLD_START's call at COLD_START.chime, the two paging
    routines, ROM_IDENTITY and the release's free space, where the cartridge's own code goes;
  - that code is no larger than the HOME reserve floor (budget.toml, with its ledger), so the cartridge still fits
    whenever the release keeps its floor;
  - the cartridge's EXROM is the release's, byte for byte.
--patch first writes the release's ROM_IDENTITY into the cartridge image (the cartridge's bytes differ only where no
compiled code can call, so the two share LIB images: docs/V2/STORAGE_SPEC.md D3).

Usage: cart_check.py [--patch] RELEASE_BUILD CART_BUILD      (e.g. build build/cart)
"""
import os
import re
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PAGING = {"BANK_PAGE_EXROM_IN": 27, "BANK_PAGE_EXROM_OUT": 16}   # the release routines' sizes


def symbols(path):
    return {m.group(1): int(m.group(2), 16)
            for m in re.finditer(r"^(\S+?):\s+EQU\s+0x([0-9A-Fa-f]+)$", open(path).read(), re.M)}


def code_end(img):
    return max(i for i, b in enumerate(img) if b != 0xFF) + 1


def home_floor():
    cfg = tomllib.load(open(os.path.join(ROOT, "budget.toml"), "rb"))
    return cfg["home"]["reserve_floor"] + sum(e["delta"] for e in cfg.get("ledger", [])
                                              if e["image"] == "home" and e["component"] == "reserve_floor")


def main(argv):
    patch = "--patch" in argv
    argv = [a for a in argv if a != "--patch"]
    if len(argv) != 2:
        sys.exit(__doc__)
    rel, cart = argv
    rs, cs = symbols(os.path.join(rel, "forth_boot.sym")), symbols(os.path.join(cart, "forth_boot.sym"))
    rimg = open(os.path.join(rel, "forth_boot_rom0.bin"), "rb").read()
    cpath = os.path.join(cart, "forth_boot_rom0.bin")
    cimg = bytearray(open(cpath, "rb").read())
    errors = []

    ident = rs["ROM_IDENTITY"]
    if patch:
        cimg[ident:ident + 2] = rimg[ident:ident + 2]
        open(cpath, "wb").write(cimg)

    local = tuple(name + "." for name in PAGING)
    for name, value in rs.items():
        if name.startswith(local):
            continue
        if name not in cs:
            errors.append(f"{name} (${value:04X}) is missing from the cartridge build")
        elif cs[name] != value:
            errors.append(f"{name} is ${cs[name]:04X} in the cartridge build, ${value:04X} in the release")

    end = code_end(rimg)
    allowed = [(0, 5), (rs["COLD_START.chime"] + 1, rs["COLD_START.chime"] + 3), (ident, ident + 2), (end, 0x4000)]
    allowed += [(rs[name], rs[name] + size) for name, size in PAGING.items()]
    for i in range(0x4000):
        if rimg[i] != cimg[i] and not any(a <= i < b for a, b in allowed):
            errors.append(f"byte ${i:04X} differs (release ${rimg[i]:02X}, cartridge ${cimg[i]:02X}) outside the "
                          "cartridge's places")
            break
    if cimg[ident:ident + 2] != rimg[ident:ident + 2]:
        errors.append("ROM_IDENTITY differs from the release's (run with --patch)")
    if cimg[rs["COLD_START.chime"]] != 0xCD:
        errors.append("COLD_START.chime is not a CALL")

    own = code_end(cimg) - end
    floor = home_floor()
    if own > floor:
        errors.append(f"the cartridge's own code is {own} B, more than the HOME reserve floor ({floor} B): shrink it")

    rex = open(os.path.join(rel, "graphics_exrom.bin"), "rb").read()
    cex = open(os.path.join(cart, "graphics_exrom.bin"), "rb").read()
    if rex != cex:
        errors.append("the cartridge's EXROM is not the release's")

    for e in errors:
        print("cart_check: FAIL " + e)
    if errors:
        return 1
    print(f"cart_check: ok: every release label at its address, ROM_IDENTITY ${rimg[ident] | rimg[ident + 1] << 8:04X}, "
          f"the EXROM identical; the cartridge's code {own} B (floor {floor} B), {0x4000 - code_end(cimg)} B free")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
