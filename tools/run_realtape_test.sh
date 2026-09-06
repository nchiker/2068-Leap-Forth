#!/usr/bin/env bash
# tools/run_realtape_test.sh — runs rom/forth_smoke_p53_realtape.asm's own
# two checkpoints against a REAL .TAP file under real Fuse pulse-level
# tape emulation (no fake-tape hook anywhere in this path) and reports
# PASS/FAIL. See that ROM's own header for what this proves and why.
#
# REQUIRES A REAL X DISPLAY (Fuse's SDL/X11 backend needs one even though
# this script never looks at the window) and Fuse's own saved settings
# (~/.fuserc) to have `detectloader` overridable -- this script passes
# --detect-loader explicitly on the command line either way, so a
# from-scratch ~/.fuserc works too.
#
# WHY `script`, not plain redirection: Fuse fully block-buffers its
# stdout when it isn't a real terminal, so a plain `> logfile` redirect
# can lose every debugger `print` if the process is ever killed before
# a clean exit. `script` allocates a real pseudo-terminal for Fuse's
# stdout, which makes libc use line buffering instead -- confirmed the
# hard way this session (silent, fully-empty logs from bare redirection
# even after a real, successful pass).
#
# WHY --detect-loader is passed explicitly: this machine's own
# ~/.fuserc has `<detectloader>0</detectloader>` saved, which means the
# emulated tape deck never starts playing on its own -- STORAGE_LOAD's
# own real LD-BYTES-derived routine then just burns its whole
# STORAGE_ENTRY_RETRY_MAX budget over and over finding pure silence,
# never completing. Confirmed via a `breakpoint event tape:play`/
# `tape:stop` diagnostic: with detect-loader off, neither event ever
# fired in 30+ real seconds; with it on, play/stop cycled repeatedly and
# the real test completed in under a minute.
set -euo pipefail
cd "$(dirname "$0")/.."

ROM_ASM="rom/forth_smoke_p53_realtape.asm"
ROM_BIN="build/forth_smoke_p53_realtape_rom0.bin"
EXROM="${FUSE_EXROM:-build/stock_shaped_exrom.bin}"
TAPE="build/realtape_test.tap"
MINI_SRC="build/mini_src.fs"
BJ_SRC="rom/forth_smoke_p52_blackjack_test.fs"
DBG_SCRIPT="build/realtape_test.dbg"
TYPESCRIPT="build/realtape_test.typescript"
RUNNER="build/run_realtape_test_inner.sh"

mkdir -p build

if [[ ! -f "$EXROM" ]]; then
    echo "run_realtape_test: EXROM not found: $EXROM" >&2
    echo "Run tools/make_exrom_placeholder.sh first, or set FUSE_EXROM." >&2
    exit 2
fi
if ! command -v fuse >/dev/null 2>&1; then
    echo "run_realtape_test: fuse executable not found" >&2
    exit 2
fi
if ! command -v script >/dev/null 2>&1; then
    echo "run_realtape_test: 'script' (bsdutils/util-linux) is required" >&2
    exit 2
fi

echo "run_realtape_test: assembling $ROM_ASM"
tools/sjasmplus_strict.sh --sym=build/forth_smoke_p53_realtape.sym \
    --lst=build/forth_smoke_p53_realtape.lst "$ROM_ASM"
mv forth_smoke_p53_realtape_rom0.bin "$ROM_BIN"

printf '%s' ': DOUBLER DUP + ; ' > "$MINI_SRC"

echo "run_realtape_test: building real tape file $TAPE"
python3 tools/tape_gen_forth.py "$TAPE" "MINI:$MINI_SRC" "BJPROG:$BJ_SRC"

# DONE.hang's address is re-derived from the fresh .sym file every run,
# never hardcoded -- this file's own address can move as the ROM changes.
DONE_ADDR="$(awk -F'0x' '/^DONE\.hang:/{print $2}' build/forth_smoke_p53_realtape.sym)"
if [[ -z "$DONE_ADDR" ]]; then
    echo "run_realtape_test: couldn't find DONE.hang in the .sym file" >&2
    exit 2
fi

# VPTR (62120 decimal = 0xF2A8) log: 4 rounds x (PTOTAL, DTOTAL, OUTCOME),
# each a 2-byte cell -- see rom/forth_smoke_p52.asm's own header for how
# this ground truth was independently established.
python3 - "$DONE_ADDR" "$DBG_SCRIPT" <<'PY'
import sys
done_addr, out_path = sys.argv[1], sys.argv[2]
base = 62120
lines = [f"breakpoint 0x{done_addr}", "commands 1", "print ula:last", "print [0x8a76]"]
for i in range(12):
    addr = base + i * 2
    lines.append(f"print [0x{addr:04x}]+([0x{addr+1:04x}]<<8)")
lines += ["exit 0", "end", ""]
with open(out_path, "w") as f:
    f.write("\n".join(lines))
PY

cat > "$RUNNER" <<EOF
#!/usr/bin/env bash
set -u
cd "$(pwd)"
exec env DISPLAY="\${DISPLAY:-:1}" fuse --no-sound --machine ts2068 --detect-loader \\
  --rom-ts2068-0 "$ROM_BIN" \\
  --rom-ts2068-1 "$EXROM" \\
  --tape "$TAPE" \\
  --debugger-command "\$(cat $DBG_SCRIPT)"
EOF
chmod +x "$RUNNER"

pkill -KILL -x fuse 2>/dev/null || true
sleep 0.3
rm -f "$TYPESCRIPT"

echo "run_realtape_test: running under real Fuse (real-time tape decode, ~60-90s)..."
script -qefc "$RUNNER" "$TYPESCRIPT" > /dev/null 2>&1 || true

echo "--- raw debugger output ---"
tail -n +14 "$TYPESCRIPT" | head -n 14

# `script` records a real terminal session (CRLF line endings) -- strip
# the \r before matching, or the trailing-CR line breaks the $ anchor.
values="$(tr -d '\r' < "$TYPESCRIPT" | grep -E '^0x[0-9a-fA-F]+$' || true)"
mapfile -t vals <<< "$values"

if [[ ${#vals[@]} -lt 14 ]]; then
    echo "run_realtape_test: FAIL -- expected 14 printed values, got ${#vals[@]}" >&2
    echo "run_realtape_test: full typescript at $TYPESCRIPT" >&2
    exit 1
fi

border_val=${vals[0]}
checkpoint_val=${vals[1]}
expected=(0x15 0x12 0x4 0x16 0x14 0x3 0x15 0xc 0x4 0x11 0x17 0x1)
ok=1
for i in "${!expected[@]}"; do
    got="${vals[$((i+2))]}"
    if [[ "$((got))" -ne "$((${expected[$i]}))" ]]; then
        echo "run_realtape_test: VPTR mismatch at index $i: got $got, expected ${expected[$i]}" >&2
        ok=0
    fi
done

if [[ "$((border_val))" -eq 4 && "$ok" -eq 1 ]]; then
    echo "run_realtape_test: PASS -- real .TAP file, real STORAGE_RECEIVE_BLOCK, all 4 rounds match ground truth"
    exit 0
else
    echo "run_realtape_test: FAIL -- border=$border_val checkpoint=$checkpoint_val" >&2
    exit 1
fi
