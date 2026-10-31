#!/usr/bin/env bash
# The download bundle: dist/2068-Forth-<version>.zip (make dist; CI publishes it).
#
# Contents: roms/ (the HOME ROM, the graphics EXROM, the two as one 24 KB file for ZEsarUX, the EXROM as a .dck for
# EightyOne and TS-Pico, SHA256SUMS), symbols/ (.sym/.lst), docs/ (the tutorial as Markdown, PDF and DOCX, the README,
# hardware notes, the numeric model), demos/ (Forth sources), run_fuse.sh, README-FIRST.txt, LICENSE, BUILD_INFO.txt.
# VERSION may be passed in (CI passes the tag); otherwise it comes from git.
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
mkdir -p "$stage/roms" "$stage/symbols" "$stage/docs/images" "$stage/demos"

# --- ROMs ---------------------------------------------------------------
for f in forth_boot_rom0.bin graphics_exrom.bin forth_zesarux.bin graphics_exrom.dck SHA256SUMS; do
  test -f "build/$f" || { echo "missing build/$f -- run make first" >&2; exit 1; }
  cp "build/$f" "$stage/roms/"
done
cp build/forth_boot.sym build/forth_boot.lst build/graphics_exrom.sym build/graphics_exrom.lst "$stage/symbols/"
cp demos/*.fs "$stage/demos/"

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
  --rom-ts2068-1 roms/graphics_exrom.bin "$@"
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
roms/forth_boot_rom0.bin    The 16 KB HOME ROM: boots to a live Forth prompt.
roms/graphics_exrom.bin     The 8 KB EXROM: the editor (EDIT), FILL, CIRCLE, RECT, POLYGON, POLYGON-FILL
                            and the sprites. Without it those words report NO EXROM.
roms/forth_zesarux.bin      The two as one 24 KB file, for ZEsarUX --romfile.
roms/graphics_exrom.dck     The EXROM as a cartridge for EightyOne and TS-Pico (bank \$FE, chunk 5);
                            see docs/eightyone_setup.md.
roms/SHA256SUMS             The images' hashes.
symbols/                    Assembler .sym/.lst listings.
demos/                      Forth programs (Blackjack, Shooting Gallery) as source text.
docs/forth_tutorial.{md,pdf,docx}  Learning Forth on 2068-Forth -- start here.
docs/README.{md,pdf}        The project README.
docs/hardware_notes.md      TS2068 hardware facts.
docs/numeric_model.md       Integers and floats.

Running it in Fuse
------------------
    ./run_fuse.sh
which is the same as:
    fuse --machine ts2068 --rom-ts2068-0 roms/forth_boot_rom0.bin \\
         --rom-ts2068-1 roms/graphics_exrom.bin

It boots to a white screen with its version on the status bar at the bottom,
plays a short startup chord, and drops you at a keyboard-driven prompt. Try:   5 BORDER      5 3 + .      : GREET ." HI" ; GREET

Running it in ZEsarUX
---------------------
ZEsarUX runs from its own folder, so give the ROM's full path:
    FORTH="\$PWD/roms"
    cd <ZEsarUX's folder> && ./zesarux --noconfigfile --machine TS2068 --romfile "\$FORTH/forth_zesarux.bin"
The EXROM words need ZEsarUX built with the EXROM patch (docs/zesarux_setup.md
in the source repository).

roms/forth_boot_rom0.bin is a raw 16384-byte image for the TS2068's HOME ROM
slot and roms/graphics_exrom.bin an 8192-byte image for the EXROM slot (checked
in emulators only).

Build details are in BUILD_INFO.txt. Licence: MIT (see LICENSE).
TXT

# --- zip ----------------------------------------------------------------
( cd dist && rm -f "$name.zip" && zip -q -r -X "$name.zip" "$name" )
( cd dist && shasum -a 256 "$name.zip" > "$name.zip.sha256" )
rm -rf "$stage"
echo "wrote dist/$name.zip"
cat "dist/$name.zip.sha256"
