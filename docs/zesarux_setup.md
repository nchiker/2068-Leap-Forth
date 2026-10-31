# ZEsarUX setup

## Which ZEsarUX

ZEsarUX 13.0. Everything except the EXROM words runs on a stock build. The EXROM words (`EDIT`, `FILL`, `CIRCLE`,
`RECT`, `POLYGON`, `POLYGON-FILL`, `SPRITE-DEFINE`, `SPRITE-SHOW`, `SPRITE-HIDE`) need a build with
[`../patches/0001-zesarux-mirror-ts2068-exrom.patch`](../patches/0001-zesarux-mirror-ts2068-exrom.patch).

| What you run | Stock ZEsarUX 13.0 | ZEsarUX 13.0 with the patch |
|---|---|---|
| `forth_zesarux.bin` | everything works except the EXROM words, which report `NO EXROM` | everything works |

### Why the EXROM words need the patch

The TS2068 does not decode the EXROM's upper address lines (A13-A15), so the one 8 KB EXROM chip repeats across all
eight 8 KB chunks (0-7). Stock ZEsarUX 13.0 mirrors it into chunk 0 and chunk 1 only. The ROM pages its EXROM in at
chunk 5 (`$A000-$BFFF`, `kernel/bank/bank.asm`), which a stock build leaves empty. With the patch, chunks 2-7 mirror it
too.

## Build the images

```sh
make
```

This writes `build/forth_boot_rom0.bin` (the 16 KB HOME ROM), `build/graphics_exrom.bin` (the 8 KB EXROM) and
`build/forth_zesarux.bin` (the two as one 24 KB file). See [CONTRIBUTING.md](../CONTRIBUTING.md) for the prerequisites.
The images are also in the release zip.

## Run

ZEsarUX runs from its own folder (it reads its data files from there), so the ROM file needs its full path. From
this repository's folder, after `make` (for the release zip, set `FORTH` to the zip's `roms/` folder instead):

```sh
FORTH="$PWD/build"
cd ~/Applications/ZEsarUX-13.0 && ./zesarux --noconfigfile --machine TS2068 --romfile "$FORTH/forth_zesarux.bin"
```

`~/Applications/ZEsarUX-13.0` is where the test tools expect ZEsarUX (`TS2068_DEBUG_ZESARUX_DIR`,
[CONTRIBUTING.md](../CONTRIBUTING.md)); use the folder you built or unpacked it in. `--enableulaplus` is optional; add
it to use the `ULAPLUS` and `PALETTE` words.

For the patched build, see [`../patches/README.md`](../patches/README.md): clone upstream ZEsarUX, `git am` the patch,
then `configure` and `make`. Without the patch, `EDIT`, `FILL`, `CIRCLE`, `RECT`, `POLYGON`, `POLYGON-FILL` and the
`SPRITE` words each print `NO EXROM`; every other word works.

## Reporting problems

Include the exact ZEsarUX version (`zesarux --version`), whether the EXROM patch is applied, the image files with their
sizes, and the smallest program that reproduces the issue.
