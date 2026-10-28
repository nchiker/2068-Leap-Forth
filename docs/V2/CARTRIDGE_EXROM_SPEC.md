# EXROM paging in the cartridge build: specification (audit step R1)

Written before the code, as `AY_BEEP_SPEC.md` was. Scope: R1 only. Every claim is tagged [M] measured in an
emulator in this step, [S] read from emulator source, [E] estimate. There is no hardware: every verification limit is
an emulator limit (section 9).

## 1. The problem, verified

In the `-DCARTRIDGE` build the cartridge supplies chunks 0-1 (`$0000-$3FFF`), so port `$F4` has bits 0-1 set for
the whole run. `BANK_PAGE_EXROM_IN` (home variant) sets `$FF` bit 7 (DOCK vs EXROM) and then writes `$F4 = $20`.

* **Reproduced [M]** (ZEsarUX, stock `tc2068-0/1.rom` + `.dck`, own port 10900-10959): the cartridge build with the
  three `IFNDEF CARTRIDGE` guards removed and the old `bank.asm`, typed `10 10 30 30 RECT`: nothing is drawn, no `OK`
  is printed, the next typed line is not accepted, and the registers afterwards show the stock ROM's state
  (`PC=$03FD`, then `$0038`, `$F4=$F7`). The control run on the same build (`1 2 + .`, `5 6 + .`) prints `3 OK`,
  `11 OK`. The output is kept in the oracle commit message.
* **`$FF` bit 7 is global [M, S].** Setting a register from Home RAM and reading ZEsarUX's own map
  (`ts2068-debug timex`): `$FF=$00,$F4=$23` gives chunks 0,1,5 = DOCK; `$FF=$80,$F4=$23` gives chunks 0,1,5 = EXROM;
  `$FF=$80,$F4=$20` gives chunks 0,1 = HOME and 5 = EXROM; `$FF=$80,$F4=$03` gives chunks 0,1 = EXROM. No setting makes
  chunk 5 come from EXROM while chunks 0-1 come from DOCK. ZEsarUX's `timex_set_memory_pages` does the same
  (`if (timex_port_ff & 128) EX else DOCK`, per chunk whose `$F4` bit is set).
* **The Home-RAM trampoline cannot work here (the audit's reading is confirmed).** A trampoline in chunk 4 survives
  the swap of the code that called it, but (a) the EXROM code calls back into HOME through `GRAPHICS_HOME_TABLE` at
  `$0100` (`GFX_WRITE_PIXEL`, `GFX_SET_ATTR`, `GFX_LINE`, `GFX_ROW_BASE_ADDR`, `GFX_CELL_ATTR_ADDR`), and those
  veneers are in the cartridge's chunk 0. With `$FF` bit 7 set, either chunks 0-1 are EXROM (`$F4=$23`: the callback
  lands in EXROM bytes) or HOME (`$F4=$20`: it lands in the stock ROM at `$0100`). (b) the frame interrupt
  (`RST_38`, `KBD_ISR_TICK`) would run from the wrong chunk 0 for the whole window, so the window would need `DI`,
  which step R0 (O8) removed because it lost frames. The only variant that survives is a self-contained EXROM
  routine with no callbacks and interrupts off, which is not the code this project has.

## 2. The design

In the cartridge build **the EXROM-resident code travels inside the cartridge as DOCK chunk 5**, and paging chunk 5
is one `OUT` to `$F4` that sets bit 5 and keeps the cartridge's own chunk bits. Port `$FF` is never written by
the paging routines, so bit 7 stays 0 (DOCK) for the whole run: chunks 0-1 and 5 all come from the same bank, no swap,
no trampoline, no RAM. It also needs no EXROM substitution, which `docs/ts_pico_setup.md` says TS-Pico cannot do.

The chunk-5 payload is **`build/graphics_exrom.bin`, byte for byte** (the same 8,192-byte image the home build uses
as its EXROM, built once from `rom/graphics_exrom.asm`). It reaches HOME only through the fixed `$0100` veneers,
which sit at the same addresses in both builds, so the image does not depend on which build calls it.

## 3. Memory contract

### 3.1 Home-ROM build (unchanged, byte for byte)

| State | `$F4` | `$FF` bit 7 | chunks 0-3 | 4 | 5 | 6-7 |
|---|---|---|---|---|---|---|
| Normal | `$00` | whatever the shadow holds (bit 7 = 0 after COLD_START, 1 after the first page-in; moot while `$F4` = 0) | HOME ROM / RAM | RAM | RAM | RAM |
| Paged (depth ≥ 1) | `$20` | 1 | HOME | RAM | **EXROM** | RAM |

### 3.2 Cartridge build (new)

`CART_CHUNK_SPEC = %11111100` is the LROS header byte (LOW-active: bit N = 0 means the OS maps chunk N from the
cartridge). The stock ROM's handoff sets `$F4 = ~spec = $03` [M: `port_f4: 3, port_ff: 0` at the prompt, ZEsarUX].
`CART_HSR = ~CART_CHUNK_SPEC & $FF` is that baseline; the build asserts bit 3 of the spec is 1 (chunk 3 stays HOME
for the OS handoff) and bit 5 is 1 (chunk 5 stays HOME RAM: a 0 would map DOCK chunk 5 over the dictionary RAM at
`$A000-$BFFF` for the whole run).

| State | `$F4` | `$FF` bit 7 | chunks 0-1 | 2-3 | 4 | 5 | 6-7 |
|---|---|---|---|---|---|---|---|
| Normal | `CART_HSR` = `$03` | 0 | DOCK | HOME | HOME RAM | HOME RAM | HOME RAM |
| Paged (depth ≥ 1) | `CART_HSR \| $20` = `$23` | 0 | DOCK | HOME | HOME RAM | **DOCK chunk 5** | HOME RAM |

Measured map in the paged state [M, ZEsarUX]: `0:DOCK 1:DOCK 2:HOME 3:HOME 4:HOME 5:DOCK 6:HOME 7:HOME`.

### 3.3 Port writes and their order

| Event | Home build | Cartridge build |
|---|---|---|
| Depth 0 → 1 (`BANK_PAGE_EXROM_IN`) | `PORT_FF_SHADOW \|= $80`, `OUT ($FF)`, then `$F4 = $20` | `$F4 = CART_HSR \| $20`. **One write; `$FF` untouched** |
| Depth > 1 | counter only | counter only |
| Depth 1 → 0 (`BANK_PAGE_EXROM_OUT`) | `$F4 = $00` (`$FF` left as is) | `$F4 = CART_HSR` (`$FF` untouched) |

The depth counter `BANK_EXROM_DEPTH`, its nesting rule, the defensive underflow check and the final `EI` are the same
in both builds. Both routines still return with interrupts enabled and destroy only AF.

Source layout: `kernel/bank/bank.asm` keeps its home code as is and adds the cartridge variant under
`IFDEF CARTRIDGE ... ELSE ... ENDIF`, so a non-cartridge assembly sees byte-identical source output.
`CART_CHUNK_SPEC` and `CART_HSR` are defined once, inside `IFDEF CARTRIDGE`, in `include/hardware.inc` (so that no
non-cartridge `.sym` gains a line), and used by both the LROS header in the two product ROMs and `bank.asm`.

## 4. What the cartridge contains

| Item | Value |
|---|---|
| LROS header (chunk 0, offsets 0-4) | `00 01 <CART_START lo> <CART_START hi> $FC`: unchanged. Chunk spec stays `%11111100`: the OS enables chunks 0-1 only; chunk 5 is carried but **not enabled by the OS** |
| DCK header | `00 02 02 00 00 00 02 00 00`: bank id 0 (DOCK); descriptors for chunks 0-7: chunks 0, 1 and **5** type 2 (ROM, 8,192 bytes follow), the rest 0 |
| Data order | chunk 0, chunk 1 (the 16,384-byte `*_cart.bin`), then chunk 5 (`build/graphics_exrom.bin`) |
| `.dck` size | 9 + 16,384 + 8,192 = **24,585 bytes** (was 16,393) |
| `*_cart.bin` | still the 16,384-byte LROS image (chunks 0-1) but it is no longer a complete cartridge: a physical cartridge needs chunk 5 as well (`build/graphics_exrom.bin` at DOCK `$A000`); the dist bundle ships both |
| `tools/make_dck.py` | takes the chunk-5 image as a required argument, refuses an image that is not 8,192 bytes or whose service-table trailer is not `GRAPHICS_EXROM_MAGIC, GRAPHICS_EXROM_ABI` (`$F0, $01` at offset 25), and writes the header above |

The type byte 2 for chunk 5 is read by every DCK parser this project knows: ZEsarUX `timex_insert_dck_cartridge` reads
8,192 bytes for each descriptor of type 2 and rejects any other non-zero type [S], and chunk N lands at `N*$2000` [S];
TSRun's `dock.js` indexes chunks the same way (per the `tsrun-headless` skill, to be re-checked by the oracle run);
TS-Pico's `DCK_IMAGE()` is known only from `docs/ts_pico_setup.md`, not run.

**Cold start, chunk 5.** The stock ROM maps only the chunks named in the header, so at the first instruction of
`CART_START` chunk 5 is HOME RAM, exactly as in the home build, and `COLD_START` (which zeroes `$8000-DICT_RAM_CEILING`,
a range that includes chunk 5) runs unchanged. Nothing in `COLD_START` touches `$F4`; its existing `$FF` baseline write
(`xor a`, shadow and `OUT ($FF)`, `rom/forth_boot.asm` ~206) already puts bit 7 at 0 in both builds and stays; `BANK_EXROM_DEPTH` is zeroed by the same clear. The DOCK chunk-5 data is invisible until the
first page-in. Nothing needs to be added to cold start (a reset goes through the stock ROM, which sets `$F4` again).
What the stock ROM does inside its handoff with a DOCK chunk the header does not name was not disassembled; what was
measured is that the machine boots to the same prompt with and without the chunk-5 data in the `.dck` and `$F4` is
`$03` at the prompt.

## 5. Interrupts while paged (re-derived for the cartridge)

The home argument (step R0, O8) was: the frame interrupt handler touches none of the banking state and runs from
chunk 0, which stays Home, while only chunk 5 is paged. Here the handler runs from **DOCK** chunk 0, so it has to be
re-derived:

1. Both states of the table in 3.2 map chunks 0-1 to DOCK. The page-in and page-out are one `OUT` each, so at every
   instruction boundary the mapping is one of those two states, never a mixture. The window needs no `DI`: an
   interrupt can arrive between the counter update and the `OUT`, or while paged, and in every case sees chunks 0-1
   as DOCK. In particular `RST_38` (`$0038`), `KBD_ISR_TICK` and the key tables are in chunks 0-1.
2. The handler's data (`FRAMES`, the `KBD_*` cells) is in HOME RAM, chunks 4 and 7, which are never paged; the
   machine stack (`SP` ≈ `$FF00` downwards) is in chunk 7. No symbol of the image lies in `$A000-$BFFF` [M: none in
   `build/forth_boot_cart.sym`]; the only occupant of chunk 5 is dictionary growth, which the handler never reads.
3. The handler does not read or write `BANK_EXROM_DEPTH`, `PORT_FF_SHADOW`, `$F4` or `$FF`.
4. `$FF` bit 7 is never written, which removes the thing that made the original argument delicate (a global
   selector flipping under the handler).
5. NMI (`NMI_ENTRY`, `$0066`) is a `RETN` in chunk 0, mapped in both states.

Conclusion: no `DI`, the window is interruptible, interrupts are on at return (both routines still end in `EI`). If
the interrupt handler ever touches chunk 5, the depth counter, or `$F4`/`$FF`, this needs re-deriving.

## 6. Failure modes

| Case | Behaviour | Checked by |
|---|---|---|
| `.dck` / cartridge without chunk 5 (a 16K `.dck` from before R1, or a 16K EPROM) | an absent DOCK chunk reads `$FF` [M]; `EXROM_CALL_SLOT`'s magic check (`$F0, $01` at `$A019`) fails, it pages out and returns carry set, and the six words silently do nothing, the project's convention for unavailable services. The machine stays responsive | oracle, "no chunk 5" case |
| LROS spec with bit 5 = 0 | would hide the dictionary RAM in chunk 5 from cold start | `ASSERT` at assembly |
| LROS spec with bit 3 = 0 | breaks the stock handoff (documented) | `ASSERT` at assembly |
| Unbalanced `OUT` without `IN` | depth stays 0, no port write (existing check) | unchanged code |
| Nested page-in | counter only | oracle, nested case, if a path exists |
| Hardware that does not map DOCK chunk 5 although the DCK says so | same as the first row | not testable here |

## 7. What changes in the images (expected)

* Only `forth_boot_cart.bin`, `forth_demo_blackjack_cart.bin` (if it includes the guarded words; to be confirmed by
  the build), their `.dck`, `.lst`, `.sym` and `*.build.json`. Every other file in `build/` is byte-identical to the
  recorded baseline.
* The cartridge dictionary gains `RECT`, `POLYGON`, `POLYGON-FILL`, `SPRITE-DEFINE`, `SPRITE-SHOW`, `SPRITE-HIDE`
  (about 312 B [E], the current gap between the two product images), less the cartridge variant's smaller `IN`
  (one `OUT`, about 10 B fewer than the home variant) and plus its 1 B longer `OUT`.
* The three `IFNDEF CARTRIDGE` guards in `rom/forth_boot.asm` are removed. `rom/graphics_exrom.asm` and
  `include/graphics_exrom_abi.inc` carry no cartridge guard (the audit's list is wrong about them; confirmed by
  grep), so they are not edited beyond comments.

## 8. Oracle (differential, `tools/cart_diff.py`, `make cartdiff`)

Same typed program on the home build (`forth_boot_rom0.bin` + `graphics_exrom.bin`) and the cartridge build (stock
ROMs + `.dck`), on two independent emulators (ZEsarUX through `ts2068-debug`; TSRun's real core headless under Node).
Required equal afterwards: the screen bytes `$4000-$5AFF` exactly, the data stack and float stack, `HERE` / `LATEST`
and the user dictionary bytes up to `HERE` (ROM addresses compiled into definitions differ between the builds because
the paging routines differ in size, so call/jump operands that equal a ROM symbol are compared by symbol name, the
count of such operands is printed so a vacuous pass is visible), and a control line `1 2 + .` must still print `3 OK`.
Cases: each of the six words; reversed corners and colours; a big `POLYGON` / `POLYGON-FILL` (many `$0100` callbacks
from inside the paged window); a compiled word using `RECT`, run twice; a loop that pages 200-300 times and one that
mixes the six words; the nested case if a code path exists; the no-chunk-5 `.dck` (words do nothing, machine alive).

The oracle must catch the original failure: run against the cartridge build with the guards removed and the old
`bank.asm` (no chunk 5, home-variant `IN`), it must fail, and that output is kept. `--selftest` flips one screen bit and
one stack cell and requires the comparator to report them.

Not part of `make test` (needs a Node TSRun checkout and about two minutes): own target `make cartdiff`, ports
10930-10949, like `make audio`.

## 9. Emulator limits

No hardware was used or is proposed. ZEsarUX and TSRun both model the DOCK as eight 8K chunks selected by `$F4` and
`$FF` bit 7; the TS-Pico firmware and a real cartridge connector were not run. The stock ROM's handoff was observed, not
disassembled. ZEsarUX runs 50 Hz frames; timing-sensitive claims (lost frames) are measured in ZEsarUX only.
A real cartridge PCB whose address decoding differs from the emulators' model is outside what this step can show.
