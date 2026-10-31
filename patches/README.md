# ZEsarUX TS2068 EXROM-mirroring patch

`0001-zesarux-mirror-ts2068-exrom.patch` fixes a TS2068 emulation gap in ZEsarUX: stock ZEsarUX mirrors the 8 KB
EXROM image into chunks 0 and 1 only. The real TS2068 does not decode the EXROM's address lines A13-A15, so the ROM
repeats across all eight chunks. Leap-Forth pages its EXROM into chunk 5 (`$A000-$BFFF`): without the patch the EXROM
words (`EDIT`, `FILL`, `CIRCLE`, `RECT`, `POLYGON`, `POLYGON-FILL`, the sprites) report `NO EXROM`, and `make test`
(which uses the EXROM) needs the patched build. See [`../docs/zesarux_setup.md`](../docs/zesarux_setup.md).

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
