# TS-Pico setup

Nothing here has been tried on a real TS-Pico. It is taken from the TS-Pico project's public firmware source and wiki
(`github.com/timex-sinclair-projects/TS-Pico`, its `Beta` branch `src/TS/tspico.py`, and its wiki).

## The slots TS-Pico has

TS-Pico's firmware loads two kinds of image, each into its own slot:

| Slot | Command | What it replaces | Size | Format |
|---|---|---|---|---|
| ROM slot (`ROM_SLOT`) | `LOAD "tpi:name.rom"`, then `SAVE "tpi:memboot" CODE mem,slot` | the TS2068 HOME ROM (`$0000-$3FFF`) | 16 KB | raw flat binary, no header |
| DCK slot (`DCK_SLOT`) | `LOAD "tpi:name.dck"`, then `SAVE "tpi:memdock" CODE mem,slot` | the DOCK cartridge bank | up to 64 KB (8 chunks of 8 KB) | 9-byte chunk-descriptor header and chunk data |

There is no EXROM slot: the firmware source has no EXROM handling anywhere (checked by searching `tspico.py`). The
TS2068's own EXROM chip stays as it is.

## What runs on TS-Pico today

The HOME ROM in the ROM slot: `build/forth_boot_rom0.bin`, built by `make` (also in the release zip). Without the
EXROM, `EDIT`, `FILL`, `CIRCLE`, `RECT`, `POLYGON`, `POLYGON-FILL` and the `SPRITE` words report `NO EXROM`; everything
else works. The EXROM (`build/graphics_exrom.dck`) has no slot to go in on TS-Pico.

1. Copy `build/forth_boot_rom0.bin` to the TS-Pico's SD card.
2. On the TS2068: `LOAD "tpi:forth_boot_rom0.bin"`. TS-Pico stages the image and asks whether to keep it in SRAM or
   Flash, and which slot. Flash slots 0 and 1 are write-protected (TS-Pico's own safety default); use SRAM unless you
   want it to survive a power cycle.
3. To switch to it without a reboot: `SAVE "tpi:memboot" CODE mem,slot`, where `mem` is `1` for SRAM or `2` for Flash
   and `slot` is `0`-`15` (the one you picked in step 2).

TS-Pico's documentation notes that a ROM switch can hang the machine, with a fall-back to the stock ROM on the next
boot; a TS Reset or a power cycle recovers.

## Sources

- `github.com/timex-sinclair-projects/TS-Pico`: `commands.md` (command reference: `.rom`, `.dck` and `.tap` loading,
  `MEMBOOT`, `MEMDOCK`).
- Its `Beta` branch, `src/TS/tspico.py`: the firmware (`ROM_SLOT` and `DCK_SLOT` handling, `DCK_IMAGE()` header parsing,
  `MEMBOOT`, `MEMDOCK`).
- Its wiki: `ZX-Spectrum-Mode.md` (port `$F4` bank switching, the DCK and ROM slot model), `Exploring-the-TS-Pico.md`,
  `Using-the-TS-Pico.md`.
