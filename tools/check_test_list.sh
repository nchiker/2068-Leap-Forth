#!/usr/bin/env bash
# Structural guard run from `make check`: keeps tools/rom_list.txt honest and
# keeps the default test path headless.  Launches nothing (dry-run make only).
# Model: 2068-Leap/tools/check_test_targets.sh.
#
#   1. every rom/*.asm (and rom/bench/*.asm) has a row in tools/rom_list.txt,
#      and every row's stem has its source: rom/<stem>.asm, or
#      rom/bench/<stem>.asm for kind bench
#   2. no duplicate stems
#   3. kind / exrom / expect come from the sets documented in the list header;
#      smoke/test rows additionally need a real exrom (none|gfx|a5) and a
#      verdict (0-7 or skip), not '-'
#   4. headless: `make -n test` and `make -n check` must not mention
#      fuse / Xvfb / xdotool / DISPLAY (the real-tape runner needs Fuse and
#      must never be reachable from `make test`).  If the Makefile has no
#      `test` target yet, that part is skipped with a message.
# Every failure prints what is wrong; exit status 1 if any check failed.
set -uo pipefail
cd "$(dirname "$0")/.."

LIST=tools/rom_list.txt
fail=0
bad() { echo "check_test_list: $*" >&2; fail=1; }

[ -f "$LIST" ] || { echo "check_test_list: $LIST missing" >&2; exit 1; }

declare -A KIND=() COUNT=()
nrows=0
while read -r stem kind exrom expect note; do
    case "$stem" in ''|'#'*) continue;; esac
    nrows=$((nrows + 1))
    COUNT[$stem]=$(( ${COUNT[$stem]:-0} + 1 ))
    KIND[$stem]="$kind"

    # (3) value sets
    case "$kind" in
        smoke|test|visual|bench|product|special|exrom) ;;
        *) bad "$stem: kind '$kind' not one of smoke|test|visual|bench|product|special|exrom";;
    esac
    case "$exrom" in
        none|gfx|a5|-) ;;
        *) bad "$stem: exrom '$exrom' not one of none|gfx|a5|-";;
    esac
    case "$expect" in
        [0-7]|skip|-) ;;
        '') bad "$stem: row has fewer than 4 columns (stem kind exrom expect)";;
        *) bad "$stem: expect '$expect' not one of 0-7|skip|-";;
    esac
    case "$kind" in
        smoke|test)
            case "$expect" in
                [0-7]|skip) ;;
                *) bad "$stem: kind $kind needs expect 0-7 or skip (got '$expect')";;
            esac
            case "$exrom" in
                none|gfx|a5) ;;
                *) bad "$stem: kind $kind needs exrom none|gfx|a5 (got '$exrom')";;
            esac
            if [ "$expect" = skip ] && [ -z "${note:-}" ]; then
                bad "$stem: expect=skip needs a note saying why"
            fi
            ;;
    esac

    # (1b) row -> source file
    if [ "$kind" = bench ]; then
        [ -f "rom/bench/$stem.asm" ] || bad "$stem: row has no rom/bench/$stem.asm"
    else
        [ -f "rom/$stem.asm" ] || bad "$stem: row has no rom/$stem.asm"
    fi
done < "$LIST"

[ "$nrows" -gt 0 ] || bad "$LIST has no rows"

# (2) duplicates
for s in "${!COUNT[@]}"; do
    [ "${COUNT[$s]}" -le 1 ] || bad "$s: duplicate stem (${COUNT[$s]} rows in $LIST)"
done

# (1a) source file -> row
for f in rom/*.asm; do
    [ -e "$f" ] || continue
    s="$(basename "$f" .asm)"
    [ -n "${KIND[$s]:-}" ] || bad "$f has no row in $LIST"
done
for f in rom/bench/*.asm; do
    [ -e "$f" ] || continue
    s="$(basename "$f" .asm)"
    if [ -z "${KIND[$s]:-}" ]; then
        bad "$f has no row in $LIST (kind bench)"
    elif [ "${KIND[$s]}" != bench ]; then
        bad "$f: row '$s' must be kind bench (is ${KIND[$s]})"
    fi
done

# (4) headless guard.  MAKEFLAGS/MAKELEVEL are cleared so this behaves the
# same whether run by hand or from inside `make check`.  Each dry run is
# captured before it is searched (piping make into grep -q can SIGPIPE make).
forbidden='(^|[^[:alnum:]])fuse([^[:alnum:]]|$)|xvfb|xdotool|DISPLAY'
tested=0
for t in test check; do
    plan="$(env -u MAKEFLAGS -u MAKELEVEL -u MFLAGS make -n "$t" 2>&1)"
    rc=$?
    if [ "$rc" -ne 0 ] && grep -q "No rule to make target '$t'" <<<"$plan"; then
        echo "check_test_list: note: Makefile has no '$t' target yet; headless guard skipped for it" >&2
        continue
    fi
    if [ "$rc" -ne 0 ]; then
        bad "'make -n $t' failed (exit $rc), cannot verify it is headless: $(tail -3 <<<"$plan" | tr '\n' ' ')"
        continue
    fi
    tested=$((tested + 1))
    hits="$(grep -Eiv '^[[:space:]]*#' <<<"$plan" | grep -Ei "$forbidden" || true)"
    if [ -n "$hits" ]; then
        bad "'make $t' reaches a Fuse/X11 test (must stay headless):"
        echo "$hits" >&2
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "check_test_list: FAILED" >&2
    exit 1
fi
echo "check_test_list: ok ($nrows rows; rom/*.asm all listed; make test/check headless [$tested dry runs checked])"
