#!/bin/sh
# tools/make_eightyone_exrom_dck.sh — wrap the 8K EXROM half of the
# forth_boot product ROM into a .dck cartridge EightyOne 1.41 will accept.
#
# Ported from the sibling ts2068rom project's own
# tools/make_eightyone_dck.sh (docs/eightyone_setup.md there): EightyOne
# v1.41 does not load a raw EXROM binary as a cartridge, and was
# confirmed working by a real EightyOne user against ts2068rom's own
# chunk-6 EXROM with this exact 9-byte header shape — bank id $FE (EXROM
# bank) followed by one presence-flag byte per chunk (0-7), the target
# chunk marked $02 (ROM present), every other chunk $00:
#
#   FE 00 00 00 00 00 00 02 00      (ts2068rom: chunk 6)
#
# 2068-Forth's own EXROM pages into CHUNK 5, not chunk 6 -- kernel/bank/
# bank.asm was retargeted there this project's own Phase 65 (see that
# file's own header and docs/PROJECT_PLAN.md's Phase 65 for the full
# chunk-by-chunk audit behind the choice), after this script was first
# ported. The chunk-6 header byte position was never updated to match,
# a real latent bug this fixes: chunk 5 shifts the $02 flag one byte
# earlier (byte index 6, not 7):
#
#   FE 00 00 00 00 00 02 00 00      (2068-Forth: chunk 5)
#
# Position math, not re-derived from scratch: ts2068rom's own header has
# exactly 8 flag bytes after the bank id, one per chunk 0-7 in order, so
# chunk N's own flag sits at byte index 1+N. This follows directly from
# that structure, but has NOT itself been independently confirmed against
# a real EightyOne install for chunk 5 specifically -- see
# docs/eightyone_setup.md's own "not yet independently confirmed" note.
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
printf '\376\000\000\000\000\000\002\000\000' > "$output"
cat "$input" >> "$output"

output_size=$(wc -c < "$output")
if [ "$output_size" -ne 8201 ]; then
    echo "make_eightyone_exrom_dck: generated file has unexpected size: $output_size" >&2
    exit 1
fi

echo "EightyOne EXROM cartridge: $output"
