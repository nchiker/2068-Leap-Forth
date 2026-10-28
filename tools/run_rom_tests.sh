#!/usr/bin/env bash
# Headless ROM test runner: executes every smoke/test row of tools/rom_list.txt
# under ZEsarUX via ts2068-debug and compares the final border colour with the
# row's `expect` column.  No X11, no Fuse, no wall-clock sleeps guessing at ROM
# progress.
#
#   tools/run_rom_tests.sh [stem ...]
#
# With no stems: every row of kind smoke|test.  With stems: just those rows.
# Rows with expect=skip are reported SKIP (with the list's note) and counted
# separately; rows with expect '-' are never run.
#
# Output, one line per ROM in list order (even when workers finish out of
# order):  stem: border=N expect=M -> PASS|FAIL|SKIP|TIMEOUT|MISSING|ERROR
# then "ROM TESTS: PASS n  FAIL n  SKIP n".  FAIL in the tally includes
# TIMEOUT, MISSING and ERROR.  Exit status is non-zero iff any of those occurred.
# For each failure build/test-logs/<stem>.diagnose.json holds `ts2068-debug
# --json diagnose` (symbols from build/<stem>.sym), and its path is printed.
#
# FINISH DETECTION (how we know the ROM is done before reading the border):
# every verdict ROM ends in a tight hang (`jr $`, or a 2-3 instruction
# `ld a,N / out (fe),a / jr` loop), so the machine reaches a fixed point.  We
# run bounded chunks of ROM_TEST_CHUNK opcodes (default 500000; ts2068-debug
# `run` always carries an explicit limit) and after each chunk take a
# signature of the CPU state: every register/flag/interrupt field of `regs`
# EXCEPT PC, R and MEMPTR, plus the current border from `timex`.  The ROM is
# "settled" when the signature is identical at the end of two consecutive
# chunks; only then is the border read as the verdict.
# Why not just PC: ZEsarUX stops a chunk after exactly N opcodes, so in a
# 3-instruction hang loop the PC at chunk end rotates with N mod 3 and may
# never repeat on consecutive chunks (observed on forth_smoke_p36).  PC, R
# (refresh counter) and MEMPTR therefore carry only phase, not progress.
# Everything else (AF BC DE HL IX IY SP, shadow set, I, IM, IFF1/2) must be
# bit-identical across 500k opcodes, and the border must not move, which a
# ROM that is still doing work essentially never satisfies.  A ROM that has
# not settled after ROM_TEST_MAX_INSTR opcodes (default 30000000) is reported
# TIMEOUT (a FAIL) -- never a stale border.  Interrupt-driven ROMs (p9, p28:
# frame counting via the IM 1 interrupt) simply need more emulated time; the
# chunk loop gives it to them because the signature only stops changing once
# they reach their final hang.
#
# ISOLATION: a dedicated port range and a private TS2068_DEBUG_STATE_DIR per
# worker (own ZEsarUX each), so runs never collide with other sessions.
#   ROM_TEST_PORT       base port, default 10760 (worker k uses base+k)
#   ROM_TEST_JOBS       parallel workers, default 4
#   ROM_TEST_CHUNK      opcodes per chunk, default 500000
#   ROM_TEST_MAX_INSTR  total opcode cap per ROM, default 30000000
#   ROM_TEST_LIST       alternate list file (default tools/rom_list.txt)
# Workers claim rows dynamically (atomic mkdir), so slow ROMs don't stall a
# statically assigned queue.  All sessions are stopped by a trap on exit.
set -uo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
LIST="${ROM_TEST_LIST:-tools/rom_list.txt}"
BASE_PORT="${ROM_TEST_PORT:-10760}"
JOBS="${ROM_TEST_JOBS:-4}"
CHUNK="${ROM_TEST_CHUNK:-500000}"
MAX_INSTR="${ROM_TEST_MAX_INSTR:-30000000}"
LOGDIR="build/test-logs"

command -v ts2068-debug >/dev/null || { echo "run_rom_tests: ts2068-debug not found in PATH" >&2; exit 2; }
[ -f "$LIST" ] || { echo "run_rom_tests: $LIST not found" >&2; exit 2; }
case "$JOBS" in ''|*[!0-9]*|0) echo "run_rom_tests: ROM_TEST_JOBS must be a positive integer" >&2; exit 2;; esac

mkdir -p build "$LOGDIR"

# ---- shared ROM 1 images (created before any worker starts: no races) ----
[ -f build/stock_shaped_exrom.bin ] || sh tools/make_exrom_placeholder.sh
[ -f build/exrom_a5.bin ] || head -c 8192 /dev/zero | tr '\000' '\245' > build/exrom_a5.bin

# ---- select rows ----
ROWS=()            # "stem|kind|exrom|expect|note" in list order
declare -A SEEN=()
while read -r stem kind exrom expect note; do
    case "$stem" in ''|'#'*) continue;; esac
    SEEN[$stem]="$kind|$exrom|$expect"
    if [ $# -eq 0 ]; then
        case "$kind" in smoke|test) ;; *) continue;; esac
        [ "$expect" = "-" ] && continue
        ROWS+=("$stem|$kind|$exrom|$expect|$note")
    else
        for want in "$@"; do
            if [ "$want" = "$stem" ]; then
                if [ "$expect" = "-" ]; then
                    echo "run_rom_tests: $stem has expect '-' (no verdict); not runnable" >&2; exit 2
                fi
                ROWS+=("$stem|$kind|$exrom|$expect|$note")
            fi
        done
    fi
done < "$LIST"
for want in "$@"; do
    [ -n "${SEEN[$want]:-}" ] || { echo "run_rom_tests: no row for '$want' in $LIST" >&2; exit 2; }
done
N=${#ROWS[@]}
[ "$N" -gt 0 ] || { echo "run_rom_tests: nothing to run" >&2; exit 2; }
[ "$JOBS" -le "$N" ] || JOBS=$N

T="$(mktemp -d)"
WORKER_PIDS=()
cleanup() {
    trap - EXIT INT TERM
    local pid k
    for pid in "${WORKER_PIDS[@]:-}"; do [ -n "$pid" ] && kill "$pid" 2>/dev/null; done
    for ((k = 0; k < JOBS; k++)); do
        TS2068_DEBUG_STATE_DIR="$T/w$k" ts2068-debug --json stop >/dev/null 2>&1 || true
        TS2068_DEBUG_STATE_DIR="$T/w$k" ts2068-debug --json stop --port $((BASE_PORT + k)) >/dev/null 2>&1 || true
    done
    rm -rf "$T"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# ---- JSON helpers (python3 stdlib only) ----
# regs JSON -> "PC_HEX<TAB>SYMBOL<TAB>SIGNATURE<TAB>BRIEF"
regs_info() {
    python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    r = d["registers"]
    sig = {k: v for k, v in r.items() if k not in ("PC", "R", "MEMPTR")}
    sig["flags"] = d.get("flags")
    print("%04X\t%s\t%s\tSP=%04X AF=%04X BC=%04X DE=%04X HL=%04X IX=%04X IY=%04X IM%s IFF1=%s" % (
        r["PC"], d.get("symbol", "?"), json.dumps(sig, sort_keys=True),
        r["SP"], r["AF"], r["BC"], r["DE"], r["HL"], r["IX"], r["IY"], r.get("IM", "?"),
        (d.get("flags") or {}).get("IFF1", "?")))
except Exception as e:
    print("ERR\t%s\t\t" % e)
'
}
border_of() {
    python3 -c '
import json, sys
try:
    b = json.load(sys.stdin).get("border")
    print("?" if b is None else b)
except Exception:
    print("?")
'
}

# ---- one ROM; prints the result line on stdout ----
run_one() {
    local stem="$1" kind="$2" exrom="$3" expect="$4" note="$5" k="$6"
    local state="$T/w$k" port=$((BASE_PORT + k))
    local rom0="build/${stem}_rom0.bin" sym="build/${stem}.sym"
    local diag="$LOGDIR/${stem}.diagnose.json"
    rm -f "$diag"

    if [ "$expect" = "skip" ]; then
        echo "${stem}: border=- expect=skip -> SKIP  (${note})"
        return
    fi
    if [ ! -f "$rom0" ]; then
        echo "${stem}: border=- expect=${expect} -> MISSING  (${rom0} not built; run 'make roms-for-test')"
        return
    fi
    local exfile
    case "$exrom" in
        none) exfile=build/stock_shaped_exrom.bin;;
        gfx)  exfile=build/graphics_exrom.bin;;
        a5)   exfile=build/exrom_a5.bin;;
        *)    echo "${stem}: border=- expect=${expect} -> ERROR  (bad exrom column '${exrom}')"; return;;
    esac
    if [ ! -f "$exfile" ]; then
        echo "${stem}: border=- expect=${expect} -> MISSING  (${exfile} not built; run 'make roms-for-test')"
        return
    fi

    export TS2068_DEBUG_STATE_DIR="$state"
    mkdir -p "$state"
    local img="$state/${stem}_zesarux.bin"
    cat "$rom0" "$exfile" > "$img"      # ZEsarUX wants ONE concatenated image
    local symargs=()
    [ -f "$sym" ] && symargs=(--symbols "$sym")

    ts2068-debug --json stop >/dev/null 2>&1 || true
    local out
    if ! out="$(ts2068-debug --json start --rom "$img" "${symargs[@]}" --port "$port" 2>&1)" \
       || ! grep -q '"status": "ok"' <<<"$out"; then
        echo "${stem}: border=- expect=${expect} -> ERROR  (start failed on port ${port}: $(tr '\n' ' ' <<<"$out" | cut -c1-200))"
        ts2068-debug --json stop >/dev/null 2>&1 || true
        return
    fi

    local executed=0 prev_sig="" sig info pc symb brief border settled=0 runout tries
    while [ "$executed" -lt "$MAX_INSTR" ]; do
        tries=0
        while :; do
            runout="$(ts2068-debug --json run --max-instructions "$CHUNK" 2>&1)"
            grep -q '"status": "ok"' <<<"$runout" && break
            tries=$((tries + 1))
            if [ "$tries" -ge 2 ]; then
                echo "${stem}: border=- expect=${expect} -> ERROR  (run failed: $(tr '\n' ' ' <<<"$runout" | cut -c1-200))"
                ts2068-debug --json stop >/dev/null 2>&1 || true
                return
            fi
        done
        executed=$((executed + CHUNK))
        info="$(ts2068-debug --json regs 2>&1 | regs_info)"
        IFS=$'\t' read -r pc symb sig brief <<<"$info"
        if [ "$pc" = "ERR" ]; then
            echo "${stem}: border=- expect=${expect} -> ERROR  (regs unreadable: ${symb})"
            ts2068-debug --json stop >/dev/null 2>&1 || true
            return
        fi
        border="$(ts2068-debug --json timex 2>&1 | border_of)"
        sig="${sig}|border=${border}"
        if [ -n "$prev_sig" ] && [ "$sig" = "$prev_sig" ]; then settled=1; break; fi
        prev_sig="$sig"
    done

    local verdict
    if [ "$settled" -ne 1 ]; then
        verdict=TIMEOUT
    elif [ "$border" = "$expect" ]; then
        verdict=PASS
    else
        verdict=FAIL
    fi

    local extra=""
    if [ "$verdict" != PASS ]; then
        ts2068-debug --json diagnose > "$diag" 2>&1 || true
        extra="  pc=\$${pc} ${symb} ${brief}"
        [ "$verdict" = TIMEOUT ] && extra="${extra}  (not settled after ${executed} opcodes)"
        extra="${extra}  diagnose: ${diag}"
    fi
    ts2068-debug --json stop >/dev/null 2>&1 || true
    echo "${stem}: border=${border} expect=${expect} -> ${verdict}${extra}"
}

worker() {
    local k="$1" i
    for ((i = 0; i < N; i++)); do
        mkdir "$T/claim.$i" 2>/dev/null || continue
        IFS='|' read -r stem kind exrom expect note <<<"${ROWS[$i]}"
        run_one "$stem" "$kind" "$exrom" "$expect" "$note" "$k" > "$T/res.$i.tmp"
        mv "$T/res.$i.tmp" "$T/res.$i"
    done
}

for ((k = 0; k < JOBS; k++)); do
    worker "$k" &
    WORKER_PIDS+=("$!")
done

any_worker_alive() {
    local p
    for p in "${WORKER_PIDS[@]}"; do kill -0 "$p" 2>/dev/null && return 0; done
    return 1
}

# ---- print results in list order as they become available ----
PASS=0 FAIL=0 SKIP=0 TIMEOUT=0 MISSING=0 ERROR=0
for ((i = 0; i < N; i++)); do
    while [ ! -f "$T/res.$i" ]; do
        # a dead worker pool with a missing result would hang us forever
        if ! any_worker_alive && [ ! -f "$T/res.$i" ]; then
            echo "${ROWS[$i]%%|*}: border=- -> ERROR  (worker died before producing a result)" > "$T/res.$i"
        fi
        sleep 0.2
    done
    line="$(cat "$T/res.$i")"
    echo "$line"
    case "$line" in
        *"-> PASS"*)    PASS=$((PASS + 1));;
        *"-> SKIP"*)    SKIP=$((SKIP + 1));;
        *"-> TIMEOUT"*) FAIL=$((FAIL + 1)); TIMEOUT=$((TIMEOUT + 1));;
        *"-> MISSING"*) FAIL=$((FAIL + 1)); MISSING=$((MISSING + 1));;
        *"-> ERROR"*)   FAIL=$((FAIL + 1)); ERROR=$((ERROR + 1));;
        *)              FAIL=$((FAIL + 1));;
    esac
done
wait

echo "----------------------------------------"
echo "ROM TESTS: PASS ${PASS}  FAIL ${FAIL}  SKIP ${SKIP}"
if [ "$FAIL" -gt 0 ]; then
    echo "  (FAIL includes: TIMEOUT ${TIMEOUT}, MISSING ${MISSING}, ERROR ${ERROR})"
    [ "$MISSING" -eq 0 ] || echo "  hint: missing images -> run 'make roms-for-test' (or 'make test') first"
fi
[ "$FAIL" -eq 0 ]
