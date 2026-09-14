#!/usr/bin/env python3
"""Bind a product ROM's binary/symbol/.dck artifacts to the exact source
tree and Makefile that produced them.

Modeled on the sibling `structured-basic-poc` project's own
`tools/build_stamp.py` (see NOTES_FROM_STRUCTURED_BASIC.md item 2). This
project has far more moving parts than that one -- normal ROM, DOCK
cartridge, graphics EXROM, and demo builds, all assembled from the same
shared rom/core/kernel/include tree with different flags -- which makes it
easy to run a regression against a stale or hand-mixed set of artifacts
(an old .bin with a freshly edited .sym, or a cartridge .dck built before
the last source edit) without any assembler error to catch it. `verify()`
turns that into a hard failure with an instruction to rebuild, instead of
a regression quietly passing or failing against the wrong build.

Only the "real product" targets people actually run regressions against
are covered -- not the ~60 disposable forth_smoke_p*.asm phase ROMs,
which are development history, not artifacts anyone re-verifies later.

Usage:
    python3 tools/build_stamp.py --write   --target forth-boot
    python3 tools/build_stamp.py --verify  --target forth-boot-cart
Called from the Makefile (--write, after a successful assemble) and from
regression tooling/skills (--verify, before trusting build/ artifacts).
"""
from pathlib import Path
import hashlib
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build'

# Shared across every target: the whole hand-written source tree (not
# each target's own actual transitive INCLUDE set -- coarser, but simple
# and matches the sibling project's own approach) plus the Makefile that
# turns it into artifacts.
SHARED_SOURCE_DIRS = ['rom', 'core', 'kernel', 'include']

TARGETS = {
    'forth-boot': [
        'build/forth_boot_rom0.bin',
        'build/forth_boot.sym',
    ],
    'forth-boot-cart': [
        'build/forth_boot_cart.bin',
        'build/forth_boot_cart.sym',
        'build/forth_boot.dck',
    ],
    'forth-demo-blackjack': [
        'build/forth_demo_blackjack_rom0.bin',
        'build/forth_demo_blackjack.sym',
    ],
    'forth-demo-blackjack-cart': [
        'build/forth_demo_blackjack_cart.bin',
        'build/forth_demo_blackjack_cart.sym',
        'build/forth_demo_blackjack.dck',
    ],
    'graphics-exrom': [
        'build/graphics_exrom.bin',
        'build/graphics_exrom.sym',
        'build/graphics_home_table.inc',
    ],
    'forth-lros': [
        'build/forth_lros_chunk0.bin',
        'build/forth_lros.sym',
    ],
}


def shared_source_files():
    files = [ROOT / 'Makefile']
    for d in SHARED_SOURCE_DIRS:
        files += sorted((ROOT / d).rglob('*.asm'))
        files += sorted((ROOT / d).rglob('*.inc'))
    return files


def fingerprints(target):
    files = shared_source_files() + [ROOT / p for p in TARGETS[target]]
    out = {}
    for p in files:
        try:
            out[str(p.relative_to(ROOT))] = hashlib.sha256(p.read_bytes()).hexdigest()
        except OSError as e:
            raise SystemExit(f'FAIL: {target}: cannot read {p}: {e}')
    return out


def stamp_path(target):
    return BUILD / f'{target}.build.json'


def write(target):
    stamp_path(target).write_text(json.dumps(fingerprints(target), indent=2) + '\n')


def verify(target):
    path = stamp_path(target)
    try:
        stamped = json.loads(path.read_text())
    except (OSError, ValueError):
        raise SystemExit(
            f"FAIL: {target}: no build stamp at {path.relative_to(ROOT)} -- "
            f"run `make {target}`")
    current = fingerprints(target)
    if current == stamped:
        return
    changed = sorted(set(current) | set(stamped))
    diffs = [f for f in changed if current.get(f) != stamped.get(f)]
    detail = '\n'.join(f'  {f}' for f in diffs)
    raise SystemExit(
        f"FAIL: {target}: build/ artifacts do not match the current source "
        f"tree -- run `make {target}` before trusting them. Changed:\n{detail}")


def main(argv):
    if '--target' not in argv:
        raise SystemExit(__doc__)
    target = argv[argv.index('--target') + 1]
    if target not in TARGETS:
        raise SystemExit(f'FAIL: unknown target {target!r}; known: {sorted(TARGETS)}')
    if '--write' in argv:
        write(target)
    elif '--verify' in argv:
        verify(target)
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main(sys.argv)
