#!/bin/sh
# tools/make_dck.sh -- the EXROM image as a .dck cartridge (EightyOne 1.41, TS-Pico's DCK format): a 9-byte header,
# bank id $FE (the EXROM bank) and one flag byte per chunk 0-7, chunk 5 (where the EXROM pages in) marked $02 (ROM):
#   FE 00 00 00 00 00 02 00 00
# then the 8 KB image. Usage: tools/make_dck.sh [exrom.bin] [out.dck]   (default build/graphics_exrom.bin,
# build/graphics_exrom.dck)

set -eu

input=${1:-build/graphics_exrom.bin}
output=${2:-build/graphics_exrom.dck}

if [ ! -f "$input" ]; then
    echo "make_dck: input not found: $input" >&2
    exit 1
fi

size=$(wc -c < "$input")
if [ "$size" -ne 8192 ]; then
    echo "make_dck: expected an 8192-byte EXROM, got $size bytes" >&2
    exit 1
fi

mkdir -p "$(dirname "$output")"
printf '\376\000\000\000\000\000\002\000\000' > "$output"
cat "$input" >> "$output"

output_size=$(wc -c < "$output")
if [ "$output_size" -ne 8201 ]; then
    echo "make_dck: generated file has unexpected size: $output_size" >&2
    exit 1
fi

echo "EightyOne EXROM cartridge: $output"
