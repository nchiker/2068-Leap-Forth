# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

Last updated 2026-10-31. Free bytes: HOME 2,226, EXROM 3,272 (`make budget`: per component, `budget.toml`;
`make inventory`: per routine). Dictionary: 16,128 bytes at power-on.

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

## Now: Words and keys — done (`docs/V2/milestones/Words_and_keys.md`)

Comments `\` and `(`; `[` `]` `LITERAL`; `[']` `CHAR` `[CHAR]`. Leap-C's keys for `~ | \ { } [ ] ^` and one key-table
lookup; the font in ASCII order with all of printable ASCII and Leap-C's `1`/`l`; text drawn twice as fast. Fixed on
the way: a missing name made a nameless word (now `MISSING NAME`, -16); `LIST-DEFS` and `EDIT name` skip comments. The
six defining words share one header builder. HOME 2,052 → 2,226 B free, EXROM 3,296 → 3,272.

## Next, in order

1. **Display speed**, and LINE on 16-bit coordinates with clipping (today it takes bytes: `-10 50 100 50 LINE`
   starts at x 246); it rebuilds `GFX_LINE`, whose cells POLYGON also uses through the EXROM.
2. **BREAK and timing**: BREAK in the interrupt routine, so long words can be stopped.
3. **Blackjack** rebuilt from its saved source (`demos/blackjack.fs`) as a program for the finished ROM; the Shooting
   Gallery's source is beside it (`demos/gallery.fs`).

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| LINE takes its coordinates as bytes (no 16-bit clipping) | O15 | Display speed (the `GFX_LINE` rebuild) |
| The editor's ENTER at the bottom of the view takes 406k T (the store is scanned from the start per key) | Editor | Display speed |
| Nothing checks the machine stack's depth ($F3C8-$FEFF, 2.8 KB) | Simplify | BREAK and timing (with the interrupt-side checks) |

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
