# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

Last updated 2026-10-31. Free bytes: HOME 2,052, EXROM 3,296 (`make budget`: per component, `budget.toml`;
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

## Now: Space — done (`docs/V2/milestones/Space.md`)

`make inventory`; dead code removed; the shrink pass (page zero's gaps, tail and relative jumps); `FIND` about twice
as fast per header, so compiling is a third faster; `SEARCH`, `UPPER`, `LOWER` on 16-bit lengths; the RAM cells packed,
so the dictionary starts at `$9100` (1,792 bytes more). HOME 1,732 → 2,052 B free.

**Owner decision pending:** moving cold code to the EXROM. Measured (report section 5): float functions 422 B, float
printing 561 B, BEEP and the AY words 303 B, most of the printer; tape and the word listings cannot move. The
recommendation is to move nothing now (no component is over budget; HOME has 2 KB free) and use the list when a
step runs short.

## Next, in order

1. **Words and keys**: `[']`, `[CHAR]`, `\`, `[ ]`; the shared key lookup; the `1`/`l` glyphs; faster text drawing.
2. **Display speed**, and LINE on 16-bit coordinates with clipping (today it takes bytes: `-10 50 100 50 LINE`
   starts at x 246); it rebuilds `GFX_LINE`, whose cells POLYGON also uses through the EXROM.
3. **BREAK and timing**: BREAK in the interrupt routine, so long words can be stopped.
4. **Blackjack** rebuilt from its saved source (`demos/blackjack.fs`) as a program for the finished ROM; the Shooting
   Gallery's source is beside it (`demos/gallery.fs`).

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| LINE takes its coordinates as bytes (no 16-bit clipping) | O15 | Display speed (the `GFX_LINE` rebuild) |
| The editor's ENTER at the bottom of the view takes 421k T (the store is scanned from the start per key) | Editor | Display speed |
| Nothing checks the machine stack's depth ($F3C8-$FEFF, 2.8 KB) | Simplify | BREAK and timing (with the interrupt-side checks) |

Fixed in Space: `SEARCH`, `UPPER` and `LOWER` used a length's low byte; `INT_GET_FRAMES` was dead code; integer
literals compiled slowly (the cost was `FIND`, not the number parser: compiling is now a third faster; the 35 B
parser fast path was measured at 4% and not taken).

Fixed in Simplify: CLS left the print position where it was; a THROW left CATCH's xt cell on the stack; VAL of an
empty string left a stray cell; SOUND and LEFT/RIGHT read only the low byte of a register number or count; a 32-character
name could never be found; LIST-DEFS ended a definition at a `;` inside a word or string. cartdiff's 3% failure rate
went with the cartridge build.
