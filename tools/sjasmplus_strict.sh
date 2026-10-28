#!/usr/bin/env bash
# Strict sjasmplus wrapper: any assembler error or ANY warning fails the build.
# Usage: tools/sjasmplus_strict.sh [sjasmplus args...]   (all args pass through untouched)
# Adds --msg=war (warnings + errors only) unless the caller already passed a --msg option.
# Ported from 2068-Leap-C's tools/sjasm_strict.sh; the old V2 wrapper rejected only the
# 'Negative BLOCK' / 'shortblock' truncation warnings, which are covered by the general rule.
set -euo pipefail

log_file="$(mktemp)"
trap 'rm -f "$log_file"' EXIT

msg_arg=(--msg=war)
for arg in "$@"; do
    case "$arg" in
        --msg|--msg=*) msg_arg=(); break ;;
    esac
done

set +e
sjasmplus ${msg_arg[@]+"${msg_arg[@]}"} "$@" 2>&1 | tee "$log_file"
assembler_rc=${PIPESTATUS[0]}
set -e

if [ "$assembler_rc" -ne 0 ]; then
    exit "$assembler_rc"
fi

# sjasmplus formats these as 'file(line): warning: ...' or 'file(line): warning[tag]: ...'.
warning_count="$(grep -Eic 'warning(\[[^]]*\])?:' "$log_file" || true)"
if [ "$warning_count" -ne 0 ]; then
    echo "sjasmplus_strict: $warning_count assembler warning(s); warnings are errors in this build" >&2
    exit 1
fi
