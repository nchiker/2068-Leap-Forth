# EightyOne / TS-Pico setup

Ported from the sibling `ts2068rom` project's own `docs/eightyone_setup.md`,
which a real EightyOne user confirmed working (Windows, released version
1.41) — the header bytes below are reused unchanged, not re-derived.

## Build the emulator images

```sh
make forth-boot
tools/make_exrom_placeholder.sh
tools/make_eightyone_exrom_dck.sh build/stock_shaped_exrom.bin build/forth_exrom_eightyone.dck
```

This produces two files for EightyOne and TS-Pico:

- `build/forth_boot_rom0.bin` — the 16K Home ROM image.
- `build/forth_exrom_eightyone.dck` — the 8K EXROM placeholder packaged
  as an EightyOne/TS-Pico Timex cartridge. Since nothing in the base
  product ROM ever pages EXROM in (only the Phase 65 graphics words do
  — see below), this placeholder cartridge is enough to boot and use
  every word EXCEPT `RECT`/`POLYGON`/`POLYGON-FILL`/`SPRITE-DEFINE`/
  `SPRITE-SHOW`/`SPRITE-HIDE`.

EightyOne v1.41 does not load a raw EXROM binary as a cartridge. Its
`.dck` file is the raw EXROM preceded by these nine bytes:

```text
FE 00 00 00 00 00 02 00 00
```

(bank id `$FE` = EXROM bank, followed by one presence-flag byte per
chunk 0-7 in order; chunk 5 — the same `$A000-$BFFF` chunk
`kernel/bank/bank.asm` pages the real EXROM into as of this project's
own Phase 65 — marked `$02`, ROM present, every other chunk `$00`.)
`tools/make_eightyone_exrom_dck.sh` builds this deterministically and
verifies the input is exactly 8192 bytes and the output exactly 8201.
This byte position was originally ported from the sibling `ts2068rom`
project's own chunk-6 EXROM (`$02` one byte later, at index 7) and only
updated to chunk 5 once `kernel/bank/bank.asm` was itself retargeted
there — see that script's own header for the full position-math
reasoning, and "Not yet independently confirmed" below.

## Using the real graphics EXROM (RECT/POLYGON/POLYGON-FILL/sprites)

`RECT`, `POLYGON`, `POLYGON-FILL`, and `SPRITE-DEFINE`/`SPRITE-SHOW`/
`SPRITE-HIDE` (Phase 65) are dispatched through a second, real 8K EXROM
image, `build/graphics_exrom.bin` — the placeholder above has no real
code in it, so these six words will each silently do nothing against it
(the same magic/ABI mismatch guard every other word in this project
already uses instead of crashing). Build and package the real image
instead:

```sh
make forth-boot graphics-exrom
tools/make_eightyone_exrom_dck.sh build/graphics_exrom.bin build/graphics_exrom_eightyone.dck
```

Use `build/graphics_exrom_eightyone.dck` as the **ROM Cartridge** file
in step 4 below instead of `build/forth_exrom_eightyone.dck` — the two
are not interchangeable, and only one cartridge can be loaded at a time,
so a session using the placeholder cartridge won't have RECT/POLYGON/
POLYGON-FILL/sprites available, and vice versa.

## Configure EightyOne 1.41

1. Select the **Timex** tab and the **TS2068** machine.
2. Under **Advanced Settings**, set **ROM File** to `build/forth_boot_rom0.bin`.
3. Leave **Protect ROM from Writes** enabled.
4. Under **Interfaces**, set **ROM Cartridge** to **Timex** and select
   `build/forth_exrom_eightyone.dck` (or `build/graphics_exrom_
   eightyone.dck` — see above) as the cartridge file.
5. Apply the settings and perform a hard reset.

Do not select a raw `.bin` EXROM file in the ROM Cartridge field; use
the `.dck` file.

## Use on TS-Pico

The same `.dck` files are the correct cartridge images for TS-Pico —
load `build/forth_boot_rom0.bin` as the Home ROM and the appropriate
`.dck` as the cartridge, the same as above.

## Not yet independently confirmed for 2068-Leap-Forth

The header bytes and mechanism are reused from `ts2068rom`'s own
user-confirmed setup (that project's own EXROM pages into chunk 6, not
this project's chunk 5), and neither `forth_exrom_eightyone.dck` nor
`graphics_exrom_eightyone.dck` has itself been run against a real
EightyOne install — including the chunk-5 byte-position fix above,
which follows logically from the header's own documented structure but
hasn't been hardware/emulator-confirmed the way the original chunk-6
header was. Worth a real confirmation pass before relying on either,
the same way `ts2068rom`'s was confirmed by an actual user before being
documented as working.

This is unrelated to `docs/lros_cartridge.md`'s DOCK/LROS cartridge work:
that targets bank id `$0` (DOCK) with chunk 0 populated, a different
cartridge slot and convention from the EXROM (`$FE`) packaging here.
