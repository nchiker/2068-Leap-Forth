# EightyOne setup

Ported from the sibling `ts2068rom` project's own `docs/eightyone_setup.md`,
which a real EightyOne user confirmed working (Windows, released version
1.41) — the header bytes below are reused unchanged, not re-derived.

## Build the emulator images

```sh
make forth-boot
tools/make_exrom_placeholder.sh
tools/make_eightyone_exrom_dck.sh build/stock_shaped_exrom.bin build/forth_exrom_eightyone.dck
```

This produces two files for EightyOne:

- `build/forth_boot_rom0.bin` — the 16K Home ROM image.
- `build/forth_exrom_eightyone.dck` — the 8K EXROM packaged as an
  EightyOne Timex cartridge.

EightyOne v1.41 does not load a raw EXROM binary as a cartridge. Its
`.dck` file is the raw EXROM preceded by these nine bytes:

```text
FE 00 00 00 00 00 00 02 00
```

(bank id `$FE` = EXROM bank; chunk 6 — the same `$C000-$DFFF` chunk
`kernel/bank/bank.asm` pages the real EXROM into — marked `$02`, ROM
present.) `tools/make_eightyone_exrom_dck.sh` builds this deterministically
and verifies the input is exactly 8192 bytes and the output exactly 8201.

## Configure EightyOne 1.41

1. Select the **Timex** tab and the **TS2068** machine.
2. Under **Advanced Settings**, set **ROM File** to `build/forth_boot_rom0.bin`.
3. Leave **Protect ROM from Writes** enabled.
4. Under **Interfaces**, set **ROM Cartridge** to **Timex** and select
   `build/forth_exrom_eightyone.dck` as the cartridge file.
5. Apply the settings and perform a hard reset.

Do not select the raw `stock_shaped_exrom.bin` in the ROM Cartridge field;
use the `.dck` file.

## Not yet independently confirmed for 2068-Forth

The header bytes and mechanism are reused from `ts2068rom`'s own
user-confirmed setup, and this project's EXROM pages into the identical
chunk 6 — but this specific `forth_exrom_eightyone.dck` has not itself
been run against a real EightyOne install. Worth a real confirmation pass
before relying on it, the same way `ts2068rom`'s was confirmed by an
actual user before being documented as working.

This is unrelated to `docs/lros_cartridge.md`'s DOCK/LROS cartridge work:
that targets bank id `$0` (DOCK) with chunk 0 populated, a different
cartridge slot and convention from the EXROM (`$FE`) packaging here.
