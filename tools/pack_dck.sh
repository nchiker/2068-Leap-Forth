#!/bin/sh
# tools/pack_dck.sh — wrap a single 8K DOCK-chunk-0 ROM image into a Fuse
# .dck cartridge file.
#
# DCK bank-header format (9 bytes, per docs/lros_cartridge.md — sourced
# from published TS2068 cartridge/DCK format documentation, not guessed):
#   byte 0:     bank id (0 = DOCK)
#   bytes 1-8:  one descriptor per 8K chunk (0-7):
#                 0 = absent (no image follows)
#                 1 = uninitialized RAM (no image follows)
#                 2 = ROM (8192-byte image follows)
#                 3 = initialized RAM (8192-byte image follows)
# followed by the 8192-byte image for each descriptor 2/3 chunk, in
# chunk order.
#
# This project's LROS stub (rom/forth_lros.asm) only populates chunk 0,
# so this script always emits a single-chunk-0 DCK: header
# 0,2,0,0,0,0,0,0,0 followed by exactly one 8192-byte image.
#
# Usage: tools/pack_dck.sh <chunk0.bin> <output.dck>

set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 <chunk0.bin> <output.dck>" >&2
    exit 1
fi

chunk0="$1"
out="$2"

size=$(wc -c < "$chunk0")
if [ "$size" -ne 8192 ]; then
    echo "pack_dck: $chunk0 is $size bytes, expected exactly 8192" >&2
    exit 1
fi

printf '\000\002\000\000\000\000\000\000\000' > "$out"
cat "$chunk0" >> "$out"

echo "pack_dck: wrote $out ($(wc -c < "$out") bytes: 9-byte header + 8192-byte chunk 0)"
