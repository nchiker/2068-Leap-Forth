---
name: tsrun-headless
description: Run a TS2068 ROM against TSRun's real, unmodified core (github.com/josef-jelinek/TSRun) headlessly under Node — no browser needed — to get a genuine third-party cross-check of a ROM/EXROM/DCK image, independent of ZEsarUX and Fuse. Also covers publishing this project's own ROM to TSRun for a live, no-install browser demo link. Use when you need to verify a `.dck` header, confirm a ROM combination works, or want an authoritative pass/fail without any GUI or browser automation available.
---

# TSRun headless testing

TSRun is a real, open-source, browser-based TS2068 emulator
(`github.com/josef-jelinek/TSRun`) written as plain ES modules with no
DOM dependency in its core (`z80.js`, `machine.js`, `dock.js`). That
means its actual, unmodified emulation code can run headlessly under
Node — no browser, no `claude-in-chrome`, no X11 display needed. This
was how this project got a genuine third-party confirmation that its
own `.dck` EXROM-cartridge format was correct, when neither browser
automation nor a real EightyOne install were available to settle it.

## Getting the source

```sh
git clone --depth 1 https://github.com/josef-jelinek/TSRun.git /tmp/tsrun
cd /tmp/tsrun
echo '{"type":"module"}' > package.json
```

The `package.json` is required — TSRun's `.js` files are ES modules
(`export function ...`), but Node treats bare `.js` as CommonJS by
default and refuses `import`/`export` without either a `"type":
"module"` marker or a `.mjs` extension. This project's clone doesn't
ship one (it's meant to run in a browser via `<script type="module">`),
so add it yourself in the scratch clone — never commit it upstream.

## The headless API

The pieces you need are in `machine.js`:

```js
import { createMachine, resetMachine, runFrame, insertDock } from './machine.js';
import fs from 'fs';

const keyMatrix = new Uint8Array(8).fill(0xFF);
const joystick = new Uint8Array(2).fill(0xFF);
const m = createMachine(keyMatrix, joystick);

m.homeRom.set(new Uint8Array(fs.readFileSync('home_rom0.bin')));   // 16384 bytes

// Either a flat EXROM image (mirrors like Fuse's --rom-ts2068-1):
m.exRom.set(new Uint8Array(fs.readFileSync('exrom.bin')));         // 8192 bytes
// ...or a DCK cartridge (mirrors EightyOne's ROM Cartridge slot):
const err = insertDock(m, new Uint8Array(fs.readFileSync('cart.dck')));
if (err) { console.log('insertDock ERROR:', err); process.exit(1); }

resetMachine(m);
for (let i = 0; i < 250; i++) runFrame(m);   // ~5s at 50Hz — tune to your ROM

const names = ['black','blue','red','magenta','green','cyan','yellow','white'];
console.log('border:', m.border, names[m.border]);
```

Save as a `.mjs` file (or rely on the `package.json` above) and run
with plain `node file.mjs`. `m.border` holds the low 3 bits of the
last write to any even I/O port — the same border-color pass/fail
convention this project's own smoke ROMs and the `zesarux-zrcp` skill
use (green/4 = pass by this project's own convention).

**Always run a negative control alongside the real test** — the same
Home ROM with a known-bad/placeholder EXROM or cartridge should NOT
produce the pass color. Without this, a border read that happens to
already be green by coincidence (or because the harness silently
failed to load anything) looks identical to a real pass. This caught
nothing false in this project's own case, but it's what makes the
green result trustworthy rather than assumed.

## What `dock.js` confirms about the `.dck`/DCK format

`dock.js`'s `parseDck()` is a second, independent implementation of
the same 9-byte-header DCK convention this project's own
`tools/pack_dck.sh` and `tools/make_eightyone_exrom_dck.sh` produce:

- Byte 0 = bank id: `254` (`$FE`) = EXROM, `255` (`$FF`) = Home ROM,
  `0` = DOCK.
- Bytes 1-8 = one presence-flag byte per 8K chunk, 0-7 in order
  (`0`=absent, `1`=uninitialized RAM, `2`=ROM present, `3`=initialized
  RAM present, each followed by an 8192-byte image if 2 or 3).
- `machine.js`'s own memory-read path indexes `exCart[chunk]` (or
  `dock[chunk]`/`homeCart[chunk]`) directly by the Z80 address's own
  chunk number (`addr >>> 13`) — i.e. chunk N in the file lands at
  exactly the memory window port `$F4` bit N selects. No translation,
  no off-by-one.

If you need to check a `.dck` file's structure without running the
whole emulator, `parseDck()` alone will do it:

```js
import { parseDck } from './dock.js';
import fs from 'fs';
const result = parseDck(fs.readFileSync('cart.dck'));
console.log(result.err ?? result.blocks);
```

## Publishing this project's ROM for a live browser demo

TSRun's own `roms/` folder holds named ROM pairs it fetches by default
(`roms/<name>-0.rom` 16K, `roms/<name>-1.rom` 8K), selectable via
`?rom=<name>` in the URL — see TSRun's own `README.md` for the full
mechanics (`loadStartupRoms` in `boot.js`, name must match
`^[A-Za-z0-9]+$`).

This project already has both a merge request upstream and a
self-hosted fallback:

- Upstream PR: `github.com/josef-jelinek/TSRun/pull/2` (adds
  `roms/leapforth-0.rom`/`roms/leapforth-1.rom`)
- Self-hosted fork with GitHub Pages already enabled:
  `github.com/nchiker/TSRun` (branch `add-leapforth-rom`), live at
  `https://nchiker.github.io/TSRun/?rom=leapforth`

To update the bundled ROM after a product change:

```sh
git -C /tmp/tsrun-fork checkout add-leapforth-rom
cp build/forth_boot_rom0.bin /tmp/tsrun-fork/roms/leapforth-0.rom
cp build/graphics_exrom.bin  /tmp/tsrun-fork/roms/leapforth-1.rom
cd /tmp/tsrun-fork && git add roms/leapforth-*.rom && git commit -m "Update 2068-Leap-Forth ROM files" && git push
```

GitHub Pages rebuilds automatically on push to that branch — no
separate publish step. Opening/updating the PR to `josef-jelinek/TSRun`
and enabling Pages on a fork are both treated as "create public
surface" actions by this environment's auto-mode classifier and will
be blocked without an explicit go-ahead in the conversation; routine
ROM-file updates to an *already-open* PR branch or an *already-enabled*
Pages site are just ordinary pushes and aren't gated the same way.

## Cleanup

A headless Node run like the one above exits on its own (no server, no
background process) — nothing to kill. If you also start
`python3 -m http.server` or `go run server.go` to poke at TSRun
interactively in a real browser, stop it by PID (`ps aux | grep
http.server | grep -v grep | awk '{print $2}' | xargs -r kill`), not
`pkill -f` — see the `zesarux-zrcp` skill's own "Cleaning up" section
for why `pkill -f <pattern>` is unsafe when `<pattern>` also appears in
the command you're running it from.
