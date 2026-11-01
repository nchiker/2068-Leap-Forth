# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

Last updated 2026-11-01. Free bytes: HOME 1,924, EXROM 3,136, the cartridge's HOME image 1,751 (`make budget`: per
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
| Cartridge | `make cart`: Forth, and a program saved with `SAVE-LIB`, as a DOCK cartridge for a stock TS2068 (`milestones/Cartridge.md`) |
| Manual | The user's manual in Leap-C's shape, every example a test, its entries held to the ROM's words; five defects fixed (`milestones/Manual.md`) |
| Polygon edges | POLYGON and POLYGON-FILL move an off-screen corner to the nearest edge, as Leap-C (`milestones/Polygon_edges.md`) |
| Cart start | A program cartridge starts without the power-on CRC, as Leap V2's: the largest in 0.38 s, not 2.7 s (`milestones/Cart_start.md`) |

## Now: Blackjack — done (`docs/V2/milestones/Blackjack.md`)

The Blackjack demo rebuilt for the finished ROM (`demos/blackjack.fs`: readable, the same rules, a title, a tally,
hands of up to 11 cards) and shipped as a cartridge by `make blackjack` (`tools/fs2lib.py` compiles a source on the
release ROMs and writes its SAVE-LIB tape; `make cart` packs it). `RND`'s own seed now comes from the frame counter
as well as R, and `tools/tape_gen_forth.py` puts a PC file's lines on tape ended by CR.

## Next, in order

1. **Shooting Gallery** (`demos/gallery.fs`, the old demo ROM's source, not yet rebuilt): proposed, for the owner to
   decide. It would be rebuilt as Blackjack was (a program for the finished ROM, `make gallery` as a cartridge). Its
   text has not been loaded or run on this ROM.

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| LINE with an end far off the screen walks to it at about 270 T a step (ends near ±32,768: about 10M T, 3 s) | Display speed | Not scheduled: an exact jump over the off-screen part (32-bit multiply and divide) was built: its routines 70 B, about 130 B with the code around them. 2068-Leap-C's `draw()` moves an off-screen end to the edge (fast, but not the line meant); Forth keeps the exact line |

Fixed in Blackjack: `RND` with no seed (or after `0 RANDOMIZE`) took it from the R register alone, 128 seeds, and a
cartridge's start word runs at the same moment after every switch-on; the seed is now the frame counter with R in its
high byte (as Leap-C advises, `srand(frames())` after a key; the manual says to `0 RANDOMIZE` after the first key).
`tools/tape_gen_forth.py` put a PC file's LF line ends on tape, so `LOAD-TEXT` saw one line and its first `\` comment
hid the rest (as Leap-C's `c2tape.py`, the lines now end in CR). The old demo cleared its first round to white, read
past its column table at an 11-card hand, and its test logged at a literal RAM address.

Fixed in Cart start: a program cartridge checked the image's CRC at power-on (2.7 s for the largest); it now checks
the magic, identity, length and start word only, as Leap V2's production cartridge does, and the packer checks the CRC
(the largest loads in 0.38 s).

Fixed in Polygon edges: POLYGON and POLYGON-FILL kept each corner's low byte (a corner off the screen wrapped); a
corner off the screen now moves to the nearest edge, as Leap-C's `draw()` and `box()` do (+11 B HOME).

Fixed in Manual: `RECT`, `FILL`, `CIRCLE`, `POLYGON`, `POLYGON-FILL` and the sprite words printed nothing with another
EXROM (the docs said `NO EXROM`); a word that took more than the data stack held (`.`, `SWAP` on an empty stack) wrote
over the first word of the dictionary, after which no ROM word was found; `RECT` took its corners' low bytes (300 drew
at 44) and did not check y; `SPRITE-DEFINE` and `SPRITE-SHOW` did not check that the 2x2 cells were on the screen;
the `g`, `p` and `q` glyphs sat a row high (`p` read as `P`; Leap-C's D24, #18); `core/string.asm`'s header said the
BASIC-style string words were missing; the tutorial gave `'` inside definitions where `[']` was meant, and called
`0 STARS` (start equal to limit) endless (it runs 65,536 times).

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
