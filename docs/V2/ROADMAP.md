# Leap-Forth V2 roadmap

One page: what is done, what is being done now, what comes next, and every known defect with the step that fixes it.
Kept current at the end of every session (the session log and working facts are in `HANDOFF.md`). The owner's rules:
the best solution for the language and its users; fix a problem in the session it is found unless there is a real
reason not to (the reason is written here); **follow Leap-C's conventions** (`~/2068-Leap-C` `CONTRIBUTING.md` and
`project_plan.md` section 1) for testing, paperwork, code style and RAM layout.

Last updated 2026-10-30. Free bytes: HOME 1,732, EXROM 3,296 (`make budget`: per component, `budget.toml`).

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

## Now: Simplify to Leap-C's conventions — done (`docs/V2/milestones/Simplify.md`)

Two images and their `.dck`; one test runner (`make test`, `make test-fast`) with the Forth tests in `tests/`; one RAM
layout file with its guard; the sources trimmed to Leap-C's style; per-component budgets; CONTRIBUTING.md. Seven
defects found on the way, all fixed (CLS, CATCH, VAL, SOUND, LEFT/RIGHT, long names, LIST-DEFS).

## Next, in order

1. **Space** (Leap-C's order when a component is over budget: shrink, move cold code to the EXROM, reallocate, ask).
   Move large, rarely called code from HOME into the EXROM and bring it back as space is made; the size pass.
   Candidates to measure: float printing and the transcendentals, tape words, word listings, sound, ULAplus, the
   printer. Limits: an EXROM call costs about 400 T; EXROM code cannot read the dictionary at `$A000-$BFFF`. Also:
   compact the RAM cells (`include/forth_layout.inc` keeps the dead cells' space as `DEFS n ; free` so the trim kept
   every address).
2. **Words and keys**: `[']`, `[CHAR]`, `\`, `[ ]`; the shared key lookup; the `1`/`l` glyphs; faster text drawing.
3. **Display speed**, and LINE on 16-bit coordinates with clipping (today it takes bytes: `-10 50 100 50 LINE`
   starts at x 246); it rebuilds `GFX_LINE`, whose cells POLYGON also uses through the EXROM.
4. **BREAK and timing**: BREAK in the interrupt routine, so long words can be stopped.
5. **Blackjack** rebuilt from its saved source (`demos/blackjack.fs`) as a program for the finished ROM; the Shooting
   Gallery's source is beside it (`demos/gallery.fs`).

## Known defects

| Defect | Found | Fixed in |
|---|---|---|
| LINE takes its coordinates as bytes (no 16-bit clipping) | O15 | Display speed (the `GFX_LINE` rebuild) |
| Integer literals parse 2.5× slower since floats (shared 32-bit digit loop; a 16-bit fast path costs about 40 B) | Floats | Space (it needs the bytes) |
| The editor's ENTER at the bottom of the view takes 421k T (the store is scanned from the start per key) | Editor | Display speed |
| `INT_GET_FRAMES` (4 B) may be unreachable | Recover | Space (dead code) |
| `SEARCH`, `UPPER`, `LOWER` take their lengths as bytes (a string word's lengths are 0-255 by construction; only a hand-made `addr len` over 255 is affected) | Simplify | Space (the bytes) |
| Nothing checks the machine stack's depth ($F3C8-$FEFF, 2.8 KB) | Simplify | BREAK and timing (with the interrupt-side checks) |

Fixed in Simplify: CLS left the print position where it was; a THROW left CATCH's xt cell on the stack; VAL of an
empty string left a stray cell; SOUND and LEFT/RIGHT read only the low byte of a register number or count; a 32-character
name could never be found; LIST-DEFS ended a definition at a `;` inside a word or string. cartdiff's 3% failure rate
went with the cartridge build.
