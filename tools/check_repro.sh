#!/usr/bin/env bash
# Reproducible-build check (after 2068-Leap's tools/check_repro.sh). Builds the working tree twice, in
# two fresh copies at different paths and depths, and requires every file in build/ to hash the same:
# the ROM images, .dck cartridges, .sym/.lst files and the tools/build_stamp.py *.build.json stamps.
# Each tree then has its stamps re-verified, so a build that is reproducible but whose stamps do not
# match its own sources fails too. The working tree's own build/ is never touched.
#
# Usage: tools/check_repro.sh [make-target ...]   (default: all product cart forth-lros, plus bench-roms
# when the Makefile has that target)
set -euo pipefail
cd "$(dirname "$0")/.."

targets=("$@")
if [ "${#targets[@]}" -eq 0 ]; then
    targets=(all product cart forth-lros)
    make -n bench-roms >/dev/null 2>&1 && targets+=(bench-roms)
fi
stamp_targets=(forth-boot forth-boot-cart forth-demo-blackjack forth-demo-blackjack-cart
               forth-demo-gallery graphics-exrom forth-lros)
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
    # Only sha256 and the relative name: the stamps already pin each tree's sources.
    ( cd "$tree/build" && find . -type f | LC_ALL=C sort | xargs sha256sum ) >"$tmp/sums$n"
    if [ -f "$tree/tools/build_stamp.py" ]; then
        for t in "${stamp_targets[@]}"; do
            [ -f "$tree/build/$t.build.json" ] || continue
            ( cd "$tree" && python3 tools/build_stamp.py --verify --target "$t" ) \
                || { echo "repro: build $n: stamp for $t does not match its own tree" >&2; exit 1; }
        done
    fi
done

if cmp -s "$tmp/sums1" "$tmp/sums2"; then
    echo "repro: OK ($(wc -l <"$tmp/sums1") files identical across two trees; stamps verified)"
else
    echo "repro: FAILED, builds differ:" >&2
    diff "$tmp/sums1" "$tmp/sums2" >&2 || true
    exit 1
fi
