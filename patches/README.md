# ZEsarUX TS2068 EXROM-mirroring patch

`0001-zesarux-mirror-ts2068-exrom.patch` fixes a real TS2068 emulation gap
in ZEsarUX: stock ZEsarUX only mirrors the 8K EXROM image into memory
chunks 0 and 1. Real TS2068/TC2068 hardware doesn't decode EXROM's
address lines A13-A15, so the physical ROM actually repeats across
**all eight** 8K chunks (0-7) of the EXROM bank. This project's own
graphics extension (`RECT`/`POLYGON`/`POLYGON-FILL`/`SPRITE-DEFINE`/
`SPRITE-SHOW`/`SPRITE-HIDE`, Phase 65) pages its EXROM code into chunk 5
(`$A000-$BFFF`) — invisible to stock ZEsarUX, correctly visible once
this patch is applied. See
[`../docs/zesarux_setup.md`](../docs/zesarux_setup.md) for the full
picture, including which parts of 2068-Leap-Forth need this patch and
which don't.

Confirmed by direct A/B test in this project's own development
environment: `rom/test_rect.asm` + `build/graphics_exrom.bin` reports
GREEN (pass) under a ZEsarUX build with this patch applied, and BLUE
(checkpoint 1 fail — EXROM not visible) under a stock build from the
immediate parent commit.

Applies cleanly to upstream tag `ZEsarUX-13.0`
(`https://github.com/chernandezba/zesarux`, commit `0bb4277`):

```sh
git clone https://github.com/chernandezba/zesarux.git
cd zesarux
git checkout ZEsarUX-13.0
git am /path/to/0001-zesarux-mirror-ts2068-exrom.patch
cd src
./configure
make -j"$(nproc)"
```

This produces `src/zesarux`. This patch modifies the GPL-licensed
ZEsarUX emulator and is distributed under the same license terms as
ZEsarUX itself (GNU GPL). The repository's MIT license applies to
2068-Leap-Forth, not to this patch or to ZEsarUX.

This is a different emulator and a different patch from the sibling
`ts2068rom` project's own `0001-Add-ULAplus-support-for-Timex-machines.patch`
(a *Fuse* patch, unrelated to ZEsarUX or to this EXROM-mirroring issue).
