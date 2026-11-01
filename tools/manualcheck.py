#!/usr/bin/env python3
"""The manual's word entries against the ROM's dictionary (make check).

Parts 3 and 4 of the manual (docs/manual/03_language.md, 04_machine.md) hold one entry per word, in the shape the Leap
IDE generates its help from (~/Projects/Leap-IDE/docs/requests/LEAP_FORTH_ANSWERS.md, Q5):

    ## NAME                                       the name as the ROM spells it
    <blank>
    `( stack -- effect )` -- **kind**, group      kind and group from the lists below
    <blank>
    a first paragraph of description
    ...
    ```forth                                      a first example (tools/docexamples.py makes it a test)

This checks that:
- the entries of the two parts name exactly the words of the HOME image's dictionary (the chain walked from its last
  header in build/forth_boot_rom0.bin), each once, in ASCII order within a part;
- every entry has that shape, a group of its part, and a ```forth example before the next entry;
- the kind is the ROM's: compile-only (the code starts with `call COMPILE_ONLY_CHECK`), immediate (the header's
  IMMEDIATE bit), EXROM (the word's code calls EXROM_CALL_SLOT or EXROM_CALL_NOBRK), defining (it calls HEADER_BUILD
  or VARIABLE_N), else word;
- each part's Summary table lists its entries under their groups.

Usage: manualcheck.py [BUILD_DIR]"""
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PARTS = {
    "docs/manual/03_language.md": ["stack", "arithmetic", "float", "memory", "strings", "control", "dictionary",
                                   "errors"],
    "docs/manual/04_machine.md": ["I/O", "graphics", "sound", "storage", "printer"],
}
KINDS = ["word", "immediate word", "compile-only word", "defining word", "EXROM word"]
NOT_ENTRIES = {"How to read an entry", "Summary"}
SIG = re.compile(r"^`(\(.*\))` -- \*\*([^*]+)\*\*, (\S+)$")


def rom_words(build):
    """[(name, immediate, header label)] in the order the ROM defines them."""
    rom = open(os.path.join(build, "forth_boot_rom0.bin"), "rb").read()
    sym = {}
    for line in open(os.path.join(build, "forth_boot.sym")):
        m = re.match(r"(\S+): EQU 0x([0-9A-F]+)", line)
        if m:
            sym[m.group(1)] = int(m.group(2), 16)
    heads = {v: k for k, v in sym.items() if k.startswith("H_") and "." not in k}
    linked = {rom[a] | rom[a + 1] << 8 for a in heads}
    last = [a for a in heads if a not in linked]
    assert len(last) == 1, "more than one last header: %s" % [heads[a] for a in last]
    out, a = [], last[0]
    cocheck = sym["COMPILE_ONLY_CHECK"]
    while a:
        n = rom[a + 2] & 31
        code = a + 3 + n
        compile_only = rom[code] == 0xCD and (rom[code + 1] | rom[code + 2] << 8) == cocheck
        out.append((rom[a + 3:code].decode("latin-1"), bool(rom[a + 2] & 0x80), compile_only, heads[a]))
        a = rom[a] | rom[a + 1] << 8
    return out[::-1]


def source_kinds():
    """{header label: 'EXROM word' | 'defining word'} from the words' code in core/."""
    kinds = {}
    for path in glob.glob(os.path.join(ROOT, "core", "*.asm")):
        text = open(path, encoding="latin-1").read()
        for m in re.finditer(r"^W_(\w+):\n(.*?)(?=^H_\w+:|\Z)", text, re.S | re.M):
            body = m.group(2)
            if re.search(r"\b(call|jp)\s+EXROM_CALL_(SLOT|NOBRK)\b", body):
                kinds["H_" + m.group(1)] = "EXROM word"
            elif re.search(r"\b(call|jp)\s+(HEADER_BUILD|VARIABLE_N)\b", body):
                kinds["H_" + m.group(1)] = "defining word"
    return kinds


def entries(path, groups, errs):
    """[(name, kind, group, line)] of a part; shape errors appended to errs."""
    lines = open(os.path.join(ROOT, path), encoding="utf-8").read().split("\n")
    heads = [i for i, l in enumerate(lines) if l.startswith("## ")] + [len(lines)]
    out = []
    for h, nxt in zip(heads, heads[1:]):
        name = lines[h][3:]
        body = lines[h + 1:nxt]
        where = "%s:%d %s" % (path, h + 1, name)
        if name in NOT_ENTRIES:
            if out:
                errs.append("%s: must come before the first entry" % where)
            continue
        text = [l for l in body if l.strip()]
        m = SIG.match(text[0]) if text else None
        if not m or body[0] != "" or body[1] != text[0]:
            errs.append("%s: the line after the heading must be `( effect )` -- **kind**, group" % where)
            continue
        kind, group = m.group(2), m.group(3)
        if kind not in KINDS:
            errs.append("%s: kind %r is not one of %s" % (where, kind, KINDS))
        if group not in groups:
            errs.append("%s: group %r does not belong in this part (%s)" % (where, group, ", ".join(groups)))
        if len(text) < 2 or text[1].startswith(("```", "|", "**", "*", "#")):
            errs.append("%s: no description paragraph after the stack effect" % where)
        if "```forth" not in [l.strip() for l in body]:
            errs.append("%s: no ```forth example" % where)
        out.append((name, kind, group, h + 1))
    return out, lines


def summary(lines, path, part, errs):
    """The Summary table: | **group** | `A` `B` ... | lists every entry of the part under its group."""
    listed = {}
    for l in lines:
        m = re.match(r"^\| \*\*([^*]+)\*\* \| (.*) \|$", l)
        if m:
            for w in re.findall(r"`([^`]+)`", m.group(2)):
                listed.setdefault(w, []).append(m.group(1))
    for name, kind, group, line in part:
        if listed.get(name) != [group]:
            errs.append("%s:%d %s: the Summary lists it under %s, not once under %s"
                        % (path, line, name, listed.get(name), group))
    names = {e[0] for e in part}
    for w in sorted(set(listed) - names):
        errs.append("%s: the Summary lists %s, which has no entry here" % (path, w))


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build")
    rom = rom_words(build)
    src = source_kinds()
    errs, seen = [], {}
    for path, groups in PARTS.items():
        if not os.path.exists(os.path.join(ROOT, path)):
            errs.append("%s: missing" % path)
            continue
        part, lines = entries(path, groups, errs)
        names = [e[0] for e in part]
        if names != sorted(names, key=lambda n: n.encode("latin-1")):
            first = next(a for a, b in zip(names, sorted(names, key=lambda n: n.encode("latin-1"))) if a != b)
            errs.append("%s: entries not in ASCII order (first out of place: %s)" % (path, first))
        summary(lines, path, part, errs)
        for e in part:
            if e[0] in seen:
                errs.append("%s:%d %s: also an entry at %s" % (path, e[3], e[0], seen[e[0]]))
            seen[e[0]] = (path, e[3], e[1])
    for name, imm, compile_only, label in rom:
        if name not in seen:
            errs.append("%s (%s): in the ROM, no entry in the manual" % (name, label))
            continue
        want = ("compile-only word" if compile_only else "immediate word" if imm else src.get(label, "word"))
        path, line, kind = seen[name]
        if kind != want:
            errs.append("%s:%d %s: kind %s, the ROM's is %s" % (path, line, name, kind, want))
    for name in sorted(set(seen) - {w[0] for w in rom}):
        errs.append("%s:%d %s: an entry for a word the ROM does not have" % (seen[name][0], seen[name][1], name))
    for e in errs:
        print("manualcheck: " + e)
    if errs:
        sys.exit(1)
    print("manualcheck: %d words, the manual's entries and the ROM's dictionary agree" % len(rom))


if __name__ == "__main__":
    main()
