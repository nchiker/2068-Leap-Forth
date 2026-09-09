#!/bin/sh
# tools/make_eightyone_exrom_dck.sh — wrap the 8K EXROM half of the
# forth_boot product ROM into a .dck cartridge EightyOne 1.41 will accept.
#
# Ported from the sibling ts2068rom project's own
# tools/make_eightyone_dck.sh (docs/eightyone_setup.md there): EightyOne
# v1.41 does not load a raw EXROM binary as a cartridge, and was
# confirmed working by a real EightyOne user with this exact 9-byte
# header — bank id $FE (EXROM bank) + chunk 6 marked present ($02) —
# preceding the raw 8192-byte EXROM image, unchanged:
#
#   FE 00 00 00 00 00 00 02 00
#
# This applies as-is to 2068-Forth's own EXROM, which pages into the same
# chunk 6 ($C000-$DFFF) via kernel/bank/bank.asm — the identical
# mechanism ts2068rom's own EXROM uses. Reused, not re-derived.
#
# Usage: tools/make_eightyone_exrom_dck.sh <exrom.bin> <output.dck>

set -eu

input=${1:-build/stock_shaped_exrom.bin}
output=${2:-build/forth_exrom_eightyone.dck}

if [ ! -f "$input" ]; then
    echo "make_eightyone_exrom_dck: input not found: $input" >&2
    exit 1
fi

size=$(wc -c < "$input")
if [ "$size" -ne 8192 ]; then
    echo "make_eightyone_exrom_dck: expected an 8192-byte EXROM, got $size bytes" >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"
printf '\376\000\000\000\000\000\000\002\000' > "$output"
cat "$input" >> "$output"

output_size=$(wc -c < "$output")
if [ "$output_size" -ne 8201 ]; then
    echo "make_eightyone_exrom_dck: generated file has unexpected size: $output_size" >&2
    exit 1
fi

echo "EightyOne EXROM cartridge: $output"
