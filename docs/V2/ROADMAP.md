# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

Last updated 2026-11-01. Free bytes: HOME 1,938, EXROM 3,208, the cartridge's HOME image 1,744 (`make budget`: per
component, `budget.toml`; `make inventory`: per routine). Dictionary: 16,128 bytes at power-on.

## Done

| Step | What it did |
|---|---|
| Tests and guards | Test tools, byte budgets per ROM image, power-on RAM test, licence notice |
| Recover | Dead code removed, small size savings in HOME |
| AY BEEP | BEEP plays on the AY sound chip; HOME bytes freed |
| Cartridge paging | The DOCK cartridge build could call the EXROM (the build was removed in Simplify) |
| Tape storage | SAVE/LOAD rebuilt: SAVE-TEXT, LOAD-TEXT, VERIFY-TEXT, libraries |
| Leap-C comparison | Read-only audit of what Leap-C does better; produced the items scheduled below |
| RST stack calls | Data-stack push/pop through RST vectors: about 500 B of HOME back, faster |
| Console and editor | New console redraw; full-screen editor (`EDIT`) in the EXROM; the line store |
| 64-column mode removed | 64COL and its code paths gone (HIRES colour mode kept) |
| Floats | 5-byte floats, 22 new float words, error messages, faster `*` `/` `MOD`, new RND |
| FILL and CIRCLE | Rebuilt in the EXROM, much faster, always complete (`milestones/O15.md`) |
| Simplify | Leap-C's conventions: two images, one test runner, one RAM layout file, budgets (`milestones/Simplify.md`) |
| Space | `make inventory`, dead code, the shrink pass, `FIND` twice as fast, the RAM cells packed (`milestones/Space.md`) |
| Words and keys | Comments, `[ ] LITERAL ['] CHAR [CHAR]`, Leap-C's keys, the font in ASCII order, text twice as fast (`milestones/Words_and_keys.md`) |
| Display look | Leap V2's screen: black on white, the version on the status bar, `EDIT`'s bar, Leap V2's chime (`milestones/Display_look.md`) |
| Display speed | LINE on signed 16-bit ends, about 5× faster; the view's store lookup from the line found last; a faster console scroll (`milestones/Display_speed.md`) |
| BREAK and timing | BREAK stops a running word (THROW -28 from the interrupt routine); recursion stops with RETURN STACK FULL; the interrupt routine's idle frame 2,010 → 207 T (`milestones/BREAK_and_timing.md`) |
| IDE hooks | The Leap IDE's questions answered; labels a host drives the prompt by and `LAST_ERROR` (`milestones/IDE_hooks.md`) |

## Now: Cartridge — done (`docs/V2/milestones/Cartridge.md`)

`make cart` builds Forth as a DOCK cartridge for a stock TS2068 (`docs/cartridge.md`): the HOME image with
`-DCARTRIDGE` in DOCK chunks 0-1 (an LROS header in `RST_00`'s bytes), the release EXROM in chunk 5, and a program
saved with `SAVE-LIB` in chunks 2-3. At power-on the program is copied to `$9100` and its start word runs as a typed
line, then the `OK` prompt (the owner's choice). Every release label keeps its address and the cartridge carries the
release's `ROM_IDENTITY` (`tools/cart_check.py`); the release images are byte-identical. `tools/forthcart.py` packs a
`.tap`/`.tzx`; `make test` has a `cart` suite (ZEsarUX and TSRun on the stock ROM); `make test-cart` runs the other
suites on the cartridge. The cartridge's code is 194 B of the release's free space (within the 200 B floor).

## Next, in order

1. **Manual**: the V2 manual rewritten in the style of the Leap-C manual (`~/2068-Leap-C/docs/manual`) and the Leap V2
   manual: `docs/manual/` parts, one entry per word in the shape the Leap IDE generates its help from (the answers,
   Q5), every example run by the build, and a check that the manual and the ROM's headers name the same words. The
   cartridge guide (`docs/cartridge.md`) becomes one of its parts.
2. **Blackjack** rebuilt from its saved source (`demos/blackjack.fs`) as a program for the finished ROM; the Shooting
   Gallery's source is beside it (`demos/gallery.fs`). A demo: one of the last steps; `make cart` can ship it as a
   cartridge.

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| POLYGON and POLYGON-FILL take their vertices as bytes (an off-screen vertex wraps, as LINE's ends did) | Display speed | Not scheduled: the owner chose the least ROM space (2026-10-31); a fix is about +15 B and 48 B RAM for the outline, +100-150 B EXROM for POLYGON-FILL's clipping |
| A program cartridge's load checks the image with the ROM's CRC: about 0.15 s per 1,000 bytes of dictionary (2.7 s for the largest, 16,128 B) | Cartridge | Not scheduled: an unrolled CRC is about +60 B, over the 200 B the cartridge's own code is held to (it must fit whenever the release does); a sum would catch less. Spent once, at power-on |
| LINE with an end far off the screen walks to it at about 270 T a step (ends near ±32,768: about 10M T, 3 s) | Display speed | Not scheduled: an exact jump over the off-screen part (32-bit multiply and divide) was built: its routines 70 B, about 130 B with the code around them |

Fixed in IDE hooks: an error that is not a THROW (an unknown word, `STACK?`) under CATCH left `CATCH_DEPTH` counting a
frame the SP reload had dropped, and the next uncaught THROW went back into it (`-1 THROW` printed `THROW  ?`);
`STORAGE_SPEC.md` section 6 gave `SAVE-TEXT` and `VERIFY-TEXT` as `( addr len "name" -- )`.

Fixed in BREAK and timing: nothing checked the machine stack's depth (runaway recursion reset the machine); no running
word could be stopped (KEY returned BREAK as 16, ACCEPT stored it); a line that ended in an error left its `:` word
linked with half its code (running it reset the machine) and LEAVE_DEPTH raised (EXIT then compiled stray POPs); CATCH
did not put the input source back (a caught error in LOAD-TEXT's text went on with the rest of that text); output that
scrolled cleared its new rows in white, not the current colours (found by the owner).

Fixed in Display speed: LINE took its coordinates' low bytes; the view's ENTER at the bottom took 406k T; the README's
Fuse command and `docs/zesarux_setup.md`'s ZEsarUX command failed as written (relative ROM paths); `.` held a copy of
`PRINT_UDEC16`; `MATH_UDIV16`'s header did not state its divisor limit.

Fixed in Display look: the border was never set, so it showed whatever the ULA held at power-on (white in ZEsarUX);
`core/ts2068.asm`'s unused `DEFAULT_ATTR` said the cold start used it.

Fixed in Words and keys: `:` `CREATE` `VARIABLE` `CONSTANT` `ARRAY` `STRING` `FVARIABLE` `FCONSTANT` with no name made a
nameless word (`:` left the console compiling); `'` with no name said `UNDEFINED WORD`, `FORGET` `NOT FOUND`; a `:` or `;`
in a comment would have started or ended a `LIST-DEFS` span, and a commented-out `: name` line could be what `EDIT name`
opened.

Fixed in Space: `SEARCH`, `UPPER` and `LOWER` used a length's low byte; `INT_GET_FRAMES` was dead code; integer
literals compiled slowly (the cost was `FIND`, not the number parser: compiling is now a third faster; the 35 B
parser fast path was measured at 4% and not taken).

Fixed in Simplify: CLS left the print position where it was; a THROW left CATCH's xt cell on the stack; VAL of an
empty string left a stray cell; SOUND and LEFT/RIGHT read only the low byte of a register number or count; a 32-character
name could never be found; LIST-DEFS ended a definition at a `;` inside a word or string. cartdiff's 3% failure rate
went with the cartridge build.
