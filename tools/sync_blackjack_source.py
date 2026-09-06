#!/usr/bin/env python3
"""Regenerates demos/blackjack.fs and rom/forth_smoke_p52_blackjack_test.fs
from rom/forth_demo_blackjack.asm's own embedded SRC_* DB blocks -- the
ROM's SRC_ARRAYS..SRC_KICKOFF text is the single source of truth for the
game's Forth source; these two other files are portable-text derivatives
of it (SAVE-TEXT/LOAD-TEXT payload and the p52 smoke test's own payload)
that must never be hand-edited out of sync with it again.

GETKEY and TABLEBG are NOT part of any SRC_* block -- in the real ROM
they're hand-written Z80 dictionary words (W_GETKEY/W_TABLEBG), so a
portable-text rendering of the game needs an explicit Forth-level stand-in
for each, which is why this script hardcodes them here rather than
extracting them.

Usage: python3 tools/sync_blackjack_source.py [--check]
  --check: don't write anything, just report whether the two generated
           files already match what this script would produce (exit 1 if
           not) -- for a pre-commit/CI-style drift check.
"""
import re
import sys

ROM_PATH = "rom/forth_demo_blackjack.asm"
REAL_OUT = "demos/blackjack.fs"
TEST_OUT = "rom/forth_smoke_p52_blackjack_test.fs"

# Blocks making up the actual game logic, in source order. GETKEY/TABLEBG/
# RANDOMIZE are handled separately (see below) since they're not plain
# SRC_* DB blocks.
BODY_BLOCKS = [
    "SRC_ARRAYS", "SRC_DECK", "SRC_SCORE", "SRC_GLYPHS", "SRC_DISPLAY",
    "SRC_DEAL", "SRC_TURN", "SRC_ROUND", "SRC_MAIN", "SRC_KICKOFF",
]

GETKEY_REAL = ": GETKEY KEY ; "
TABLEBG_STUB = ": TABLEBG ; "
GETKEY_TEST = (
    ": GETKEY KIDX @ 1+ KIDX ! KIDX @ 1 = IF 89 EXIT THEN KIDX @ 2 = IF 72 "
    "EXIT THEN KIDX @ 3 = IF 89 EXIT THEN KIDX @ 4 = IF 89 EXIT THEN "
    "KIDX @ 5 = IF 83 EXIT THEN KIDX @ 6 = IF 78 EXIT THEN 78 ; "
)
KIDX_DECL = "VARIABLE KIDX "


def extract_block(src: str, name: str) -> str:
    # SRC_KICKOFF is a single "NAME: DB ..." line; every other block is
    # "NAME:" followed by one or more DB lines -- handle both shapes.
    m = re.search(
        re.escape(name) + r":[ \t]*\n?(.*?)\n" + re.escape(name) + r"_LEN\s+EQU",
        src, re.DOTALL,
    )
    if not m:
        raise SystemExit(f"couldn't find block {name} in {ROM_PATH}")
    body = m.group(1)
    parts = []
    for line in body.splitlines():
        line = line.strip()
        if not line.startswith("DB "):
            continue
        # One DB "..." string literal per line in this file (verified
        # against every SRC_* block as of Phase 51/52) -- a raw regex
        # grab of the quoted content, unescaping \" -> ".
        sm = re.match(r'DB\s+"(.*)"\s*$', line)
        if not sm:
            raise SystemExit(f"unexpected DB line in {name}: {line!r}")
        parts.append(sm.group(1).replace('\\"', '"'))
    return "".join(parts)


def extract_seed(src: str, label: str) -> str:
    m = re.search(re.escape(label) + r':\s*DB\s+"([^"]*)"', src)
    if not m:
        raise SystemExit(f"couldn't find {label} in {ROM_PATH}")
    return m.group(1)


def build():
    with open(ROM_PATH) as f:
        src = f.read()

    seed_real = extract_seed(src, "SRC_SEED_REAL")
    seed_test = extract_seed(src, "SRC_SEED_TEST")
    body = "".join(extract_block(src, name) for name in BODY_BLOCKS)

    real_text = GETKEY_REAL + TABLEBG_STUB + seed_real + body
    test_text = TABLEBG_STUB + KIDX_DECL + GETKEY_TEST + seed_test + body
    return real_text, test_text


def main():
    check_only = "--check" in sys.argv
    real_text, test_text = build()

    results = []
    for path, text in ((REAL_OUT, real_text), (TEST_OUT, test_text)):
        try:
            with open(path) as f:
                current = f.read()
        except FileNotFoundError:
            current = None
        matches = current == text
        results.append((path, matches))
        if not check_only and not matches:
            with open(path, "w") as f:
                f.write(text)

    if check_only:
        drifted = [p for p, ok in results if not ok]
        if drifted:
            print("out of sync with " + ROM_PATH + ": " + ", ".join(drifted))
            sys.exit(1)
        print("both files match " + ROM_PATH + "'s own SRC_* blocks")
    else:
        for path, matches in results:
            print(("unchanged: " if matches else "regenerated: ") + path)


if __name__ == "__main__":
    main()
