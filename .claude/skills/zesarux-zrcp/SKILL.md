---
name: zesarux-zrcp
description: Run a TS2068 ROM under real ZEsarUX and drive it over its Remote Control Protocol (ZRCP) — check border-color pass/fail, take screenshots, read memory, simulate keyboard input, or debug a running ROM. Use whenever a change needs confirming on real hardware emulation, not just a clean assemble, for this project or any other TS2068/ZX-Spectrum-family ROM built with sjasmplus. Do not use for the static checks (tools/check_asm.py, check_z80_opcodes.py) or the z80sim simulator — those don't need a running emulator at all.
---

# ZEsarUX ZRCP for TS2068 ROM testing

This project's own standing bar for "done" on any real feature is
"confirmed passing (border green) under real ZEsarUX" — a clean
assemble only proves the ROM built, not that it works. This skill is
the accumulated, working mechanics for that: launching ZEsarUX
headless, talking to it over ZRCP, and the handful of gotchas that
cost real time to discover the hard way.

## Launching ZEsarUX headless

Always combine a Home ROM with its EXROM half first if the ROM under
test pages one in — `cat home_rom0.bin exrom.bin > combined_24k.bin` —
then launch as a background process:

```sh
setsid nohup zesarux --noconfigfile --machine TS2068 \
    --romfile combined_24k.bin \
    --enable-remoteprotocol --remoteprotocol-port <PORT> \
    > /tmp/zesarux.log 2>&1 < /dev/null &
disown
sleep 4
```

**Run ONE instance at a time.** Launch, check what you need, send
`exit-emulator` (or `pkill -9 -f zesarux` if the socket's already gone),
*then* launch the next ROM — don't launch a second instance on another
port while the first is still up "for convenience." `setsid` makes
each instance survive independently across tool calls, which means
nothing kills a forgotten one for you; stacking instances across
several ROMs/ports at once was flagged directly during this project's
own work as an unintended, un-tracked pile-up, not a deliberate
multiplexing strategy. If a command sequence gets interrupted mid-way,
run `ps aux | grep zesarux` before doing anything else and clean up any
orphans (`pkill -9 -f zesarux`) before starting fresh.

**Use `setsid`, not a bare `&`.** A plain background job (even with
`disown`) can get killed the moment the *launching* Bash tool call's
own timeout/wrapper exits — `setsid` detaches it into its own session
so it survives across separate tool calls. Always `sleep ~4s` after
launch before connecting; ZEsarUX needs a moment to bind the ZRCP
port. Pick a fresh `<PORT>` per emulator instance if more than one
might be running (leftover instances from a previous attempt are easy
to accumulate — `pkill -9 -f zesarux` cleans them all up, or send
`exit-emulator` over ZRCP to one specific instance first).

For a ROM with no EXROM at all, just pass the plain Home ROM binary as
`--romfile`.

## Talking to it: one command per connection

Every ZRCP interaction in practice looks like this — open the TCP
socket, wait for the banner, send one or more commands, read the
replies, close it:

```sh
exec 3<>/dev/tcp/127.0.0.1/<PORT>
sleep 1
printf 'get-io-ports\n' >&3
sleep 0.5
timeout 2 cat <&3
exec 3<&-; exec 3>&-
```

`timeout 2 cat <&3` is what actually drains the reply — without a
timeout, `cat` on a socket blocks forever since the connection never
closes on its own. Every command's reply is followed by a `command>`
prompt line; ignore it.

## Border-color pass/fail (the standard smoke-ROM convention)

This project's own smoke ROMs all set the border to green (4) on full
pass, or the failing checkpoint's own number otherwise, white (7) for
a bug in the test source itself. Read it back with:

```sh
printf 'get-io-ports\n' >&3
```

and look at the `Spectrum FE port:` line in the reply — that's the
last byte written to port `$FE` (`PORT_ULA`), whose low 3 bits are the
border color. `02` = red = checkpoint 2 failed, `04` = green = pass,
etc.

## Screenshots

```sh
printf 'save-screen /path/to/out.bmp\n' >&3
```

Then crop and convert, since ZEsarUX's BMP includes the border: a
352×304 image holds a 256×192 TS2068 playfield starting at pixel
`(48, 56)` — `im.crop((48,56,48+256,56+192))`. Convert BMP→PNG with
Pillow (`Image.open(...).save(..., 'PNG')`) since the image-viewing
tool doesn't read BMP directly:

```python
from PIL import Image
im = Image.open('/path/to/out.bmp')
im.crop((48, 56, 48 + 256, 56 + 192)).save('/path/to/out_crop.png')
```

## Reading memory directly

```sh
printf 'read-memory <decimal-addr> <decimal-len>\n' >&3
```

returns a plain hex-byte string, no separators (`FF0032...`). Get the
decimal address from a build's own `.sym` file (`grep MY_SYSVAR
build/foo.sym`, giving a hex `EQU`), then convert:
`python3 -c "print(0x81D3)"`. This is the reliable way to check a
sysvar's real runtime value — far more trustworthy than re-deriving
the arithmetic by eye a second time.

## Simulating keyboard input

```sh
printf 'send-keys-ascii <ms-between-keys> <code1> [<code2> ...]\n' >&3
```

**Send ONE key code per `send-keys-ascii` call, not a batch.** Batches
of roughly 6+ ASCII codes in a single call were repeatedly observed to
silently drop the entire batch — no error, nothing typed, and no
obvious pattern to when it happens. One key per call, each its own
`printf`/`sleep` pair (~100-150ms apart), is slow but reliably lands
every character, including `13` (Enter/CR) to submit a line. Confirm
what actually landed with a screenshot or `save-screen`, not just by
assuming the send succeeded — the ZRCP reply for `send-keys-ascii` is
just a blank acknowledgement either way.

## Debugging a routine that isn't behaving as expected

1. **Try a `PC=`-conditioned breakpoint first** (`set-breakpoint N
   PC=<hex>H`, `enable-breakpoints`, `enable-breakpoint N`, `run`,
   `get-registers`) — cheap when it works.
2. **If the breakpoint never fires even at an address you're certain
   executes** (confirmed happening for addresses inside a paged-in
   EXROM bank in this project — chunk 5, `$A000-$BFFF`), don't keep
   trying variations of the same breakpoint. Fall back to a temporary
   in-ROM debug log instead: pick a few bytes of genuinely idle RAM
   (a sysvar/buffer confirmed unused by whatever you're testing —
   check `include/sysvars.inc` for a comment saying so), write the
   values you want to inspect there at the point of interest, then
   read them back with `read-memory` after the run completes. Revert
   the instrumentation once the real bug is found and fixed — it's
   scaffolding, not a permanent change.
3. This is exactly how this project's own POLYGON-FILL Bresenham
   sign-comparison bug was root-caused: a per-row `(Y, NCROSS,
   crossings[0], crossings[1])` log written into an idle sprite
   buffer, read back after the fill ran, pinpointed exactly which rows
   went wrong before a single line of the fix was written.
4. **A single `get-registers` snapshot showing `PC=0038` (the
   interrupt vector) is not evidence of a hang by itself** — if
   interrupts fire often relative to how fast the main code loops,
   sampling once is likely to land mid-ISR by pure chance, and BC/HL/
   DE at that moment can look exactly like a runaway `LDIR` (a real
   `LDIR` is genuinely interruptible and resumable) even when nothing
   is actually wrong. Take at least two or three samples a fraction of
   a second apart and check whether BC/HL/DE are actually *changing*
   between them before concluding something is stuck — this project
   chased a phantom "runaway LDIR" for a while before checking that.
5. **Give every debug marker its own scratch byte, not one shared
   offset multiple stages overwrite.** Reusing the same address for
   "stage 1", "stage 2", "stage 3" markers means a later stage's write
   erases any evidence that an earlier one ran differently than
   expected — exactly what cost real time here before switching to
   one offset per checkpoint (`BLOCK_GFX_SCRATCH+0`, `+1`, `+2`, ...)
   in the same debug pass.
6. **In this project specifically, more than one test ROM (`rom/
   test_rect.asm`, `rom/test_polygon.asm`, `rom/test_sprite.asm`, `rom/
   test_poly_fill.asm`) each carries its OWN literal copy of the
   `GRAPHICS_HOME_TABLE` veneer table** (the real product ROM, `rom/
   forth_boot.asm`, carries the authoritative one). If EXROM-side code
   starts calling a veneer slot a given test fixture's own copy
   doesn't yet have, that call silently jumps into whatever code
   happens to follow the table in THAT fixture (usually `COLD_START`
   itself) — a real bug hit adding two new veneer calls to `RECT_
   FILL_IMPL` while `rom/test_rect.asm`'s own table still only had the
   original three. Check every test fixture's own copy against the
   real product ROM's whenever an EXROM routine starts depending on a
   veneer it didn't call before, not just `rom/forth_boot.asm`'s.

## Cleaning up

Always send `exit-emulator` over ZRCP (or `pkill -9 -f zesarux` if a
socket is already gone) when done with an instance — leftover
headless ZEsarUX processes accumulate quickly across a session of
repeated launches and hold their ZRCP ports open.
