#!/usr/bin/env python3
"""Audit the GRAPHICS_HOME_TABLE ABI contract between rom/graphics_exrom.asm
and every Home-side ROM that defines its own copy of that veneer table.

Modeled on the sibling `structured-basic-poc` project's own
`tools/audit_layout.py` (see NOTES_FROM_STRUCTURED_BASIC.md item 3), scoped
down to the one piece of that project's broader "RAM layout + EXROM
callback closure" audit that has a documented, previously-real failure
mode in THIS project: the zesarux-zrcp skill's own notes record that more
than one test ROM (rom/test_rect.asm, rom/test_polygon.asm,
rom/test_sprite.asm, rom/test_poly_fill.asm) carries its own literal copy
of GRAPHICS_HOME_TABLE (the authoritative one lives in rom/forth_boot.asm,
mechanically exported to build/graphics_home_table.inc by
tools/export_home_symbols.py) -- and that when an EXROM routine started
depending on a veneer slot one fixture's own table didn't yet have, the
call silently fell through into whatever code happened to follow that
fixture's shorter table (usually COLD_START itself), not a crash an
assembler or a border-color smoke test would catch.

This tool statically re-derives, from rom/graphics_exrom.asm's own source,
which GRAPHICS_HOME_* veneer slots each GRAPHICS_EXROM_TABLE entry (RECT,
POLYGON, SPRITE-DEFINE/SHOW/HIDE, POLYGON-FILL) actually calls -- directly
or through one level of internal helper calls (e.g. SPRITE_DEFINE_IMPL ->
SPRITE_TRANSFER_IMPL) -- then checks every ROM with its own
GRAPHICS_HOME_TABLE against the EXROM slots its own included core/*.asm
files actually invoke. A fixture whose table is too short for what it
exercises fails loudly, by name, instead of silently falling through.

Also checks the one other part of this ABI that's easy to get wrong
silently: every GRAPHICS_HOME_TABLE must sit at exactly the same fixed
address ($0100) build/graphics_home_table.inc's constants assume, since
graphics_exrom.asm is built ONCE and combined with whichever Home ROM at
test/run time -- a table at any other address would silently call into
the wrong bytes in every one of those combinations, not just a mismatched
one.

Usage: python3 tools/audit_layout.py
"""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
EXROM_SRC = ROOT / 'rom' / 'graphics_exrom.asm'

# Canonical GRAPHICS_HOME_TABLE slot order (rom/forth_boot.asm's own copy,
# the authoritative one) -- append-only, per that table's own header.
CANONICAL_VENEER_ORDER = [
    'GFX_WRITE_PIXEL', 'GFX_SET_ATTR', 'GFX_LINE',
    'GFX_ROW_BASE_ADDR', 'GFX_CELL_ATTR_ADDR',
    # step E item 6: the full-screen view's engine veneers (slots 5-12)
    'WRAP_CALC', 'WRAP_CALC_AT', 'ED_DRAW_ROWS', 'ED_DRAW_CURSOR',
    'EDITOR_EDIT_KEY', 'IO_READ_KEY', 'EDIT_CURSOR_TO_ROWCOL',
    'FORGET_PRINT_MSG',
]
VENEER_TO_HOME_CALL = {
    'GFX_WRITE_PIXEL': 'GRAPHICS_HOME_WRITE_PIXEL',
    'GFX_SET_ATTR': 'GRAPHICS_HOME_SET_ATTR',
    'GFX_LINE': 'GRAPHICS_HOME_LINE',
    'GFX_ROW_BASE_ADDR': 'GRAPHICS_HOME_ROW_BASE_ADDR',
    'GFX_CELL_ATTR_ADDR': 'GRAPHICS_HOME_CELL_ATTR_ADDR',
    'WRAP_CALC': 'GRAPHICS_HOME_WRAP_CALC',
    'WRAP_CALC_AT': 'GRAPHICS_HOME_WRAP_CALC_AT',
    'ED_DRAW_ROWS': 'GRAPHICS_HOME_ED_DRAW_ROWS',
    'ED_DRAW_CURSOR': 'GRAPHICS_HOME_ED_DRAW_CURSOR',
    'EDITOR_EDIT_KEY': 'GRAPHICS_HOME_EDITOR_EDIT_KEY',
    'IO_READ_KEY': 'GRAPHICS_HOME_IO_READ_KEY',
    'EDIT_CURSOR_TO_ROWCOL': 'GRAPHICS_HOME_EDIT_CURSOR_TO_ROWCOL',
    'FORGET_PRINT_MSG': 'GRAPHICS_HOME_FORGET_PRINT_MSG',
}
HOME_CALL_TO_VENEER = {v: k for k, v in VENEER_TO_HOME_CALL.items()}

# ROMs that define their own GRAPHICS_HOME_TABLE and call into
# rom/graphics_exrom.asm's shared, single build/graphics_exrom.bin image.
HOME_TABLE_ROMS = [
    'rom/forth_boot.asm',
    'rom/test_rect.asm',
    'rom/test_polygon.asm',
    'rom/test_sprite.asm',
    'rom/test_poly_fill.asm',
    'rom/test_shapes.asm',
]

LABEL_RE = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*):')
CALL_RE = re.compile(r'\bcall\s+([A-Za-z_][A-Za-z0-9_]*)')
SLOT_INVOKE_RE = re.compile(r'\$A000\s*\+\s*\(\s*(\d+)\s*\*\s*3\s*\)')
INCLUDE_RE = re.compile(r'^\s*INCLUDE\s+"([^"]+)"', re.IGNORECASE | re.MULTILINE)


def fail(msg):
    raise SystemExit(f'FAIL: {msg}')


def label_ranges(lines):
    """Map each top-level label to the (start, end) line-index range of its
    body, up to (not including) the next top-level label."""
    labels = [(i, m.group(1)) for i, line in enumerate(lines)
              for m in [LABEL_RE.match(line)] if m]
    ranges = {}
    for idx, (start, name) in enumerate(labels):
        end = labels[idx + 1][0] if idx + 1 < len(labels) else len(lines)
        ranges.setdefault(name, (start, end))  # first definition wins
    return ranges


def calls_in_range(lines, start, end):
    calls = set()
    for line in lines[start:end]:
        code = line.split(';', 1)[0]
        for m in CALL_RE.finditer(code):
            calls.add(m.group(1))
    return calls


def veneers_needed(label, ranges, lines, cache, stack):
    if label in cache:
        return cache[label]
    if label not in ranges or label in stack:
        return frozenset()
    stack.add(label)
    start, end = ranges[label]
    needed = set()
    for called in calls_in_range(lines, start, end):
        if called in HOME_CALL_TO_VENEER:
            needed.add(HOME_CALL_TO_VENEER[called])
        elif called in ranges:
            needed |= veneers_needed(called, ranges, lines, cache, stack)
    stack.discard(label)
    cache[label] = frozenset(needed)
    return cache[label]


def parse_exrom_dispatch():
    """slot number -> IMPL label, from GRAPHICS_EXROM_TABLE's own jp list."""
    lines = EXROM_SRC.read_text().splitlines()
    try:
        table_start = next(i for i, l in enumerate(lines)
                            if l.strip() == 'GRAPHICS_EXROM_TABLE:')
    except StopIteration:
        fail(f'{EXROM_SRC}: no GRAPHICS_EXROM_TABLE label found')
    dispatch = {}
    slot_re = re.compile(r'^\s*jp\s+(\S+)\s*;\s*slot\s+(\d+)')
    for line in lines[table_start + 1:]:
        m = slot_re.match(line)
        if not m:
            break
        dispatch[int(m.group(2))] = m.group(1)
    if not dispatch:
        fail(f'{EXROM_SRC}: GRAPHICS_EXROM_TABLE parsed to zero slots')
    ranges = label_ranges(lines)
    cache = {}
    return {slot: veneers_needed(impl, ranges, lines, cache, set())
            for slot, impl in dispatch.items()}, dispatch


def home_table_slots(text, rom_name):
    """This ROM's own GRAPHICS_HOME_TABLE veneer order, and whether it's
    positioned at the fixed $0100 ABI address."""
    lines = text.splitlines()
    try:
        idx = next(i for i, l in enumerate(lines)
                   if l.strip() == 'GRAPHICS_HOME_TABLE:')
    except StopIteration:
        return None
    # Walk backward over blank/comment lines to find the DS that pads to
    # the fixed $0100 address this whole ABI assumes.
    j = idx - 1
    while j >= 0 and (lines[j].strip() == '' or lines[j].strip().startswith(';')):
        j -= 1
    if j < 0 or '$0100' not in lines[j] or 'DS' not in lines[j]:
        fail(f'{rom_name}: GRAPHICS_HOME_TABLE is not preceded by a '
             f'`DS $0100 - $, $FF` pad -- it will not land at the fixed '
             f'$0100 address build/graphics_home_table.inc assumes')
    slots = []
    jp_re = re.compile(r'^\s*jp\s+(\S+)')
    for line in lines[idx + 1:]:
        stripped = line.strip()
        if stripped == '' or stripped.startswith(';'):
            continue
        m = jp_re.match(line)
        if not m:
            break
        slots.append(m.group(1))
    return slots


def slots_invoked_by(rom_path, rom_name):
    """Which GRAPHICS_EXROM_TABLE slot numbers this ROM's own transitively
    INCLUDEd core/*.asm files actually invoke via `$A000 + (N * 3)`."""
    seen_files = set()
    slots = set()

    def walk(path):
        if path in seen_files or not path.exists():
            return
        seen_files.add(path)
        text = path.read_text()
        for n in SLOT_INVOKE_RE.finditer(text):
            slots.add(int(n.group(1)))
        for m in INCLUDE_RE.finditer(text):
            inc = m.group(1)
            if inc.startswith('include/'):
                continue  # ABI/hardware constants only, not dictionary code
            walk(ROOT / inc)

    walk(rom_path)
    return slots


def check_home_ram():
    """include/exrom_home_ram.inc copies Home RAM cells and constants for the EXROM's view; each must equal the
    symbol of that name in build/forth_boot.sym (and in the cartridge build's)."""
    inc = ROOT / 'include' / 'exrom_home_ram.inc'
    want = {}
    for m in re.finditer(r'^([A-Z][A-Z0-9_]*)\s+EQU\s+(\$[0-9A-Fa-f]+|\d+)', inc.read_text(), re.MULTILINE):
        v = m.group(2)
        want[m.group(1)] = int(v[1:], 16) if v[0] == '$' else int(v)
    bad = []
    for sym_name in ('forth_boot.sym', 'forth_boot_cart.sym'):
        path = ROOT / 'build' / sym_name
        if not path.exists():
            fail(f'{path.relative_to(ROOT)} missing: build the Forth images first (make)')
        have = {}
        for line in path.read_text().splitlines():
            m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*):\s+EQU\s+0x([0-9A-Fa-f]+)', line)
            if m:
                have[m.group(1)] = int(m.group(2), 16)
        for name, value in want.items():
            if have.get(name) != value:
                got = 'missing' if name not in have else f'${have[name]:04X}'
                bad.append(f'{inc.relative_to(ROOT)}: {name} = ${value:04X} but {sym_name} has {got}')
    if bad:
        for b in bad:
            print(f'FAIL: {b}')
        raise SystemExit(1)
    print(f'PASS: include/exrom_home_ram.inc: {len(want)} Home cell(s)/constant(s) agree with the Home symbols')


def audit():
    veneers_by_slot, dispatch = parse_exrom_dispatch()
    print(f'GRAPHICS_EXROM_TABLE: {len(dispatch)} slots parsed from '
          f'{EXROM_SRC.relative_to(ROOT)}')
    for slot in sorted(dispatch):
        names = sorted(veneers_by_slot[slot], key=CANONICAL_VENEER_ORDER.index) \
            if veneers_by_slot[slot] else []
        print(f'  slot {slot} ({dispatch[slot]}): needs {names or "(no Home callback)"}')

    failures = []
    for rel in HOME_TABLE_ROMS:
        path = ROOT / rel
        text = path.read_text()
        table = home_table_slots(text, rel)
        if table is None:
            failures.append(f'{rel}: has no GRAPHICS_HOME_TABLE of its own '
                             f'(expected one -- update HOME_TABLE_ROMS if this '
                             f'ROM genuinely no longer needs it)')
            continue
        if table != CANONICAL_VENEER_ORDER[:len(table)]:
            failures.append(f'{rel}: GRAPHICS_HOME_TABLE slot order {table} '
                             f'does not match the canonical prefix '
                             f'{CANONICAL_VENEER_ORDER[:len(table)]} -- '
                             f'reordering/removing an existing slot is not safe')
            continue

        invoked = slots_invoked_by(path, rel)
        required_veneers = set()
        for slot in invoked:
            required_veneers |= veneers_by_slot.get(slot, frozenset())
        required_len = (max(CANONICAL_VENEER_ORDER.index(v)
                             for v in required_veneers) + 1) if required_veneers else 0

        if len(table) < required_len:
            missing = CANONICAL_VENEER_ORDER[len(table):required_len]
            failures.append(
                f'{rel}: GRAPHICS_HOME_TABLE has only {len(table)} slot(s) '
                f'{table}, but the EXROM slot(s) it invokes ({sorted(invoked)}) '
                f'need {missing} too -- a call to one of those would fall '
                f'through into whatever code follows this table')
        else:
            print(f'PASS: {rel}: GRAPHICS_HOME_TABLE has {len(table)} slot(s), '
                  f'covers EXROM slot(s) {sorted(invoked) or "(none)"} '
                  f'(needs >= {required_len})')

    if failures:
        for f in failures:
            print(f'FAIL: {f}')
        raise SystemExit(1)
    print('PASS: every GRAPHICS_HOME_TABLE ROM is at the fixed $0100 ABI '
          'address and covers what it actually invokes')
    check_home_ram()


if __name__ == '__main__':
    audit()
