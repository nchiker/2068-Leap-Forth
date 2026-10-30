#!/usr/bin/env bash
# Reproducible-build check (after 2068-Leap's tools/check_repro.sh): builds the working tree twice, in two fresh copies
# at different paths and depths, and requires every file in build/ to hash the same. The working tree's build/ is not
# touched.
#
# Usage: tools/check_repro.sh [make-target ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/.."

targets=("$@")
[ "${#targets[@]}" -eq 0 ] && targets=(all)
jobs="$(nproc 2>/dev/null || echo 4)"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Different parent paths and depths: the images must not depend on where the tree lives.
tree1="$tmp/a/forth"
tree2="$tmp/bb/deeper/forth-copy"
for tree in "$tree1" "$tree2"; do
    mkdir -p "$tree"
    rsync -a --exclude .git --exclude build --exclude dist --exclude __pycache__ ./ "$tree/"
done

n=0
for tree in "$tree1" "$tree2"; do
    n=$((n + 1))
    ( cd "$tree" && make -j"$jobs" "${targets[@]}" >"$tmp/build$n.log" 2>&1 ) \
        || { echo "repro: build $n FAILED (log tail follows)" >&2; tail -20 "$tmp/build$n.log" >&2; exit 1; }
    ( cd "$tree/build" && find . -type f | LC_ALL=C sort | xargs sha256sum ) >"$tmp/sums$n"
done

if cmp -s "$tmp/sums1" "$tmp/sums2"; then
    echo "repro: OK ($(wc -l <"$tmp/sums1") files identical across two trees)"
else
    echo "repro: FAILED, builds differ:" >&2
    diff "$tmp/sums1" "$tmp/sums2" >&2 || true
    exit 1
fi
