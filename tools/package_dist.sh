#!/usr/bin/env bash
# Assemble the downloadable release bundle: dist/2068-Forth-<version>.zip
#
# Contents:
#   roms/      forth_boot_rom0.bin (the product), forth_demo_blackjack_rom0.bin
#              (the demo), stock_shaped_exrom.bin (an inert EXROM placeholder
#              for emulators -- see tools/make_exrom_placeholder.sh)
#   cartridge/ the same two ROMs as DOCK cartridges: *.dck for emulators,
#              *_cart.bin raw LROS images for a real cartridge EPROM
#   symbols/   .sym/.lst listings for both ROMs, for anyone debugging
#   docs/      the tutorial (Markdown, PDF, DOCX) with its images, the
#              README (Markdown, PDF), hardware notes, numeric model
#   run_fuse.sh, README-FIRST.txt, LICENSE, BUILD_INFO.txt
#
# Expects the ROMs and docs to have been built already; `make dist`
# takes care of that ordering. VERSION can be passed in (the CI
# workflow passes the tag name); otherwise it's derived from git.
#
# Usage:  tools/package_dist.sh            # or:  VERSION=v1.0 tools/package_dist.sh
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${VERSION:-}" ]; then
  if tag=$(git describe --tags --exact-match 2>/dev/null); then
    VERSION="$tag"
  else
    VERSION="dev-$(git log -1 --format=%cd --date=format:%Y%m%d)-$(git rev-parse --short HEAD)"
  fi
fi
commit=$(git rev-parse HEAD)
date=$(git log -1 --format=%cI)

name="2068-Forth-$VERSION"
stage="dist/$name"
rm -rf "$stage" "dist/$name.zip" "dist/$name.zip.sha256"
mkdir -p "$stage/roms" "$stage/cartridge" "$stage/symbols" "$stage/docs/images"

# --- ROMs ---------------------------------------------------------------
for rom in forth_boot forth_demo_blackjack; do
  test -f "build/${rom}_rom0.bin" || { echo "missing build/${rom}_rom0.bin -- run make $(echo $rom | tr _ -) first" >&2; exit 1; }
  cp "build/${rom}_rom0.bin" "$stage/roms/"
  cp "build/${rom}.sym" "build/${rom}.lst" "$stage/symbols/"
done
tools/make_exrom_placeholder.sh
cp build/stock_shaped_exrom.bin "$stage/roms/"
cat build/forth_boot_rom0.bin build/stock_shaped_exrom.bin > "$stage/roms/forth_boot_combined_24k.bin"

# --- DOCK cartridge builds ------------------------------------------------
for rom in forth_boot forth_demo_blackjack; do
  test -f "build/$rom.dck" || { echo "missing build/$rom.dck -- run make cart first" >&2; exit 1; }
  cp "build/$rom.dck" "build/${rom}_cart.bin" "$stage/cartridge/"
done

# --- graphics EXROM (Phase 65: RECT/POLYGON/POLYGON-FILL/sprites) --------
# Base dictionary only -- the DOCK cartridge builds above don't include
# this; see docs/lros_cartridge.md for why there's no cartridge path for
# it yet. Also wrapped as EightyOne/TS-Pico .dck cartridges (bank $FE,
# chunk 5), alongside a placeholder wrapping of the same inert EXROM
# already staged above -- see docs/eightyone_setup.md.
mkdir -p "$stage/roms" "$stage/eightyone"
test -f "build/graphics_exrom.bin" || { echo "missing build/graphics_exrom.bin -- run make graphics-exrom first" >&2; exit 1; }
cp build/graphics_exrom.bin "$stage/roms/"
cat build/forth_boot_rom0.bin build/graphics_exrom.bin > "$stage/roms/forth_boot_graphics_combined_24k.bin"
tools/make_eightyone_exrom_dck.sh build/stock_shaped_exrom.bin build/forth_exrom_eightyone.dck
tools/make_eightyone_exrom_dck.sh build/graphics_exrom.bin build/graphics_exrom_eightyone.dck
cp build/forth_exrom_eightyone.dck build/graphics_exrom_eightyone.dck "$stage/eightyone/"

# --- experimental LROS/DOCK boot stub ------------------------------------
# NOT hardware-verified -- see docs/lros_cartridge.md before using.
mkdir -p "$stage/experimental-lros"
test -f "build/forth_lros_chunk0.bin" || { echo "missing build/forth_lros_chunk0.bin -- run make forth-lros first" >&2; exit 1; }
tools/pack_dck.sh build/forth_lros_chunk0.bin build/forth_lros.dck
cp build/forth_lros_chunk0.bin build/forth_lros.dck "$stage/experimental-lros/"

# --- docs ---------------------------------------------------------------
cp README.md docs/forth_tutorial.md docs/hardware_notes.md docs/numeric_model.md "$stage/docs/"
cp docs/images/*.png "$stage/docs/images/"
for f in forth_tutorial.pdf forth_tutorial.docx README.pdf; do
  if [ -f "build/docs/$f" ]; then
    cp "build/docs/$f" "$stage/docs/"
  else
    echo "note: build/docs/$f not found (run tools/build_docs.sh); skipping" >&2
  fi
done
cp LICENSE "$stage/"

# --- helpers ------------------------------------------------------------
cat > "$stage/run_fuse.sh" <<'SH'
#!/bin/sh
# Boot 2068-Forth in the Fuse emulator (https://fuse-emulator.sourceforge.net/).
# Usage: ./run_fuse.sh            (any extra arguments are passed on to fuse)
cd "$(dirname "$0")"
exec fuse --machine ts2068 \
  --rom-ts2068-0 roms/forth_boot_rom0.bin \
  --rom-ts2068-1 roms/stock_shaped_exrom.bin "$@"
SH
chmod +x "$stage/run_fuse.sh"

cat > "$stage/BUILD_INFO.txt" <<TXT
2068-Forth $VERSION
commit:  $commit
date:    $date
sjasmplus: $(sjasmplus --version 2>&1 | head -1 | sed 's/ (.*//')
TXT

cat > "$stage/README-FIRST.txt" <<TXT
2068-Forth $VERSION
===================

A from-scratch Forth for the Timex Sinclair 2068, as a 16K home-ROM image.
Source and issue tracker: https://github.com/nchiker/2068-Leap-Forth

What's in this bundle
---------------------
roms/forth_boot_rom0.bin           The product: boots to a live Forth prompt.
roms/forth_demo_blackjack_rom0.bin A ROM that boots straight into the
                                   Blackjack demo (UDG, colour and sound).
roms/stock_shaped_exrom.bin        An inert 8K EXROM placeholder, for
                                   emulators that insist on a second ROM
                                   file. Use a real EXROM dump if you have one.
cartridge/forth_boot.dck           The same two ROMs built as DOCK cartridges
cartridge/forth_demo_blackjack.dck (LROS format, chunks 0-1). Plug in instead
                                   of replacing the home ROM -- see below.
cartridge/*_cart.bin               The raw 16K LROS images inside those .dck
                                   files, for burning to a cartridge EPROM.
roms/graphics_exrom.bin            8K EXROM (Phase 65): RECT, POLYGON,
                                   POLYGON-FILL, SPRITE-DEFINE/SHOW/HIDE.
                                   Use instead of stock_shaped_exrom.bin as
                                   --rom-ts2068-1 to get these six words --
                                   NOT part of either cartridge build above.
roms/forth_boot_graphics_combined_24k.bin
                                   forth_boot_rom0.bin + graphics_exrom.bin
                                   concatenated, for ZEsarUX --romfile.
roms/forth_boot_combined_24k.bin  forth_boot_rom0.bin + the inert placeholder,
                                   for ZEsarUX --romfile without graphics.
eightyone/*.dck                   forth_exrom_eightyone.dck (placeholder) and
                                   graphics_exrom_eightyone.dck (real graphics),
                                   EXROM wrapped for EightyOne's cartridge slot
                                   (bank \$FE, a different slot from the DOCK
                                   cartridges above) -- see docs/eightyone_setup.md
                                   for confirmed-working vs. still-broken cases.
experimental-lros/                EXPERIMENTAL DOCK-cartridge boot stub, NOT
                                   the full dictionary and NOT hardware-verified
                                   -- read docs/lros_cartridge.md before using.
symbols/                           Assembler .sym/.lst listings for both ROMs.
docs/forth_tutorial.{md,pdf,docx}  Learning Forth on 2068-Forth -- start here.
docs/README.{md,pdf}               The project README (status, word list).
docs/hardware_notes.md             Confirmed TS2068 hardware facts.
docs/numeric_model.md              Why the core is 16-bit integer.

Running it in Fuse
------------------
    ./run_fuse.sh
which is the same as:
    fuse --machine ts2068 --rom-ts2068-0 roms/forth_boot_rom0.bin \\
         --rom-ts2068-1 roms/stock_shaped_exrom.bin

It boots to a banner, plays a short startup sound, and drops you at a
keyboard-driven prompt. Try:   5 BORDER      5 3 + .      : GREET ." HI" ; GREET

Each roms/*.bin is a raw 16384-byte image for the TS2068's home-bank ROM
slot (the "rom0" boot ROM), so it can also be burned to an EPROM or
loaded by any TS2068 emulator or ROM-replacement hardware that accepts a
raw 16K home ROM.

Running it as a cartridge
-------------------------
The cartridge/ builds leave the stock ROMs in place: the machine boots
normally, finds the cartridge in the DOCK slot, and hands control to
2068-Forth. In Fuse:
    fuse --machine ts2068 --dock cartridge/forth_boot.dck
In ZEsarUX: select the TS2068, smartload the .dck, then hard reset.
For real hardware, burn cartridge/forth_boot_cart.bin to a 16K (27128)
EPROM on a DOCK cartridge board mapped to chunks 0-1 (addresses 0000h-3FFFh).

Build details are in BUILD_INFO.txt. Licence: MIT (see LICENSE).
TXT

# --- zip ----------------------------------------------------------------
( cd dist && rm -f "$name.zip" && zip -q -r -X "$name.zip" "$name" )
( cd dist && shasum -a 256 "$name.zip" > "$name.zip.sha256" )
rm -rf "$stage"
echo "wrote dist/$name.zip"
cat "dist/$name.zip.sha256"
