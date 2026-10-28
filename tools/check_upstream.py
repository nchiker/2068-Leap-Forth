#!/usr/bin/env python3
"""Check that adopted clean-room code is still the upstream code (audit step S, STORAGE_SPEC.md D1).

kernel/storage/tapeblock.asm is Leap-C's src/runtime/tapeblock.asm with Forth's own header comment.
Its clean-room record only holds while the code is Leap-C's, so the code (comments and blank lines
removed, whitespace collapsed) must hash to the value kernel/storage/UPSTREAM.md records. When
~/2068-Leap-C is present, the recorded commit's file is hashed the same way and must agree too.

Exit 0 = ok, 1 = the code differs.
"""
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ADOPTED = ROOT / 'kernel/storage/tapeblock.asm'
RECORD = ROOT / 'kernel/storage/UPSTREAM.md'
LEAPC = Path.home() / '2068-Leap-C'
LEAPC_PATH = 'src/runtime/tapeblock.asm'


def code_hash(text):
    lines = []
    for line in text.splitlines():
        code = line.split(';', 1)[0].strip()   # the file has no string literals containing ';'
        if code:
            lines.append(' '.join(code.split()))
    return hashlib.sha256('\n'.join(lines).encode()).hexdigest(), len(lines)


def main():
    record = RECORD.read_text()
    want = re.search(r'Code hash \| `([0-9a-f]{64})`', record).group(1)
    commit = re.search(r'Commit \| `([0-9a-f]{7,40})`', record).group(1)
    got, n = code_hash(ADOPTED.read_text())
    ok = True
    if got != want:
        print(f'check_upstream: FAIL {ADOPTED.relative_to(ROOT)}: code hash {got} != recorded {want}')
        ok = False
    if (LEAPC / '.git').exists():
        try:
            up = subprocess.run(['git', '-C', str(LEAPC), 'show', f'{commit}:{LEAPC_PATH}'],
                                check=True, capture_output=True, text=True).stdout
            uh, _ = code_hash(up)
            if uh != want:
                print(f'check_upstream: FAIL Leap-C {commit}:{LEAPC_PATH} hashes {uh}, record says {want}')
                ok = False
        except subprocess.CalledProcessError as e:
            print(f'check_upstream: note: cannot read Leap-C {commit}: {e.stderr.strip()}')
    if ok:
        print(f'check_upstream: ok ({ADOPTED.relative_to(ROOT)}: {n} code lines = Leap-C {commit})')
    return 0 if ok else 1


if __name__ == '__main__':
    sys.exit(main())
