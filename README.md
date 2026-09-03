# 2068-Forth

A from-scratch Forth for the Timex Sinclair 2068, built on the hardware
kernel proven out by **2068-Leap** (structured-BASIC ROM, same author,
separate local repository at `~/ts2068rom`). This project does not fork or
track 2068-Leap — it started by copying that project's hardware-facing
`kernel/` modules and a few build/test tools out of it, read-only, and
is free to diverge from its conventions from here on. See
[`docs/PROJECT_PLAN.md`](docs/PROJECT_PLAN.md) for exactly what was
inherited, what was deliberately left behind, and the phased build order.

## Status

- Milestone 0 (`rom/main.asm`, inherited verbatim from 2068-Leap's own
  Milestone 0): boot stub, border-cycle smoke test. Done.
- Phase 2 (`core/dict.asm` + `rom/forth_smoke.asm`): dictionary header
  format, the IX-based data stack, and eight subroutine-threaded CODE
  primitives (`DUP SWAP DROP OVER + - @ !`), self-checked and confirmed
  passing under Fuse.
- Phase 3 (`core/interp.asm` + `rom/forth_smoke_p3.asm`): the outer
  interpreter (`WORD`, `FIND`, `NUMBER`) and a real colon compiler
  (`:`, `;`). Confirmed passing under Fuse: interprets plain arithmetic,
  then defines a new word and calls it. Input is still a fixed buffer,
  not a live keyboard — see `docs/PROJECT_PLAN.md` Phase 3.
- Phase 4 (`core/control.asm` + `rom/forth_smoke_p4.asm`): control flow
  — `IF`/`ELSE`/`THEN` and `BEGIN`/`UNTIL`, plus `0=` (needed to give
  them a proper boolean flag to test). Confirmed passing under Fuse:
  both branches of an `IF`, and a loop confirmed to iterate the correct
  number of times. `WHILE`/`REPEAT` and `DO`/`LOOP` are follow-up work
  — see `docs/PROJECT_PLAN.md` Phase 4.
- Phase 5 (`core/ts2068.asm` + `rom/forth_smoke_p5.asm`): TS2068
  vocabulary — `PLOT`, `LINE`, `CIRCLE`, `BEEP`, `BORDER`, thin wrappers
  over `kernel/graphics`/`kernel/sound`. Confirmed passing under Fuse,
  including a real screenshot of a dot/line/circle drawn exactly where
  expected. This is also where a real, previously-invisible bug got
  found and fixed: this project's own Phase 3 scratch RAM aliased real
  2068-Leap kernel sysvars once `kernel/graphics`/`kernel/sound` were
  actually assembled alongside `core/` for the first time — see
  `docs/PROJECT_PLAN.md` Phase 5 for the full story and the probe
  method used to catch it. `FILL`, `AT-XY`, and hi-res `MODE` are
  follow-up work. `BEEP`'s own raw-hardware-units behavior was later
  replaced by a real, semitone/seconds `BEEP` — see Phase 31, below.
- Phase 6 (`core/editor.asm` + `rom/forth_smoke_p6.asm`): line editing
  — a single-line input buffer with insert, backspace-delete, and
  left/right cursor movement. Confirmed passing under Fuse: three
  canned key sequences (plain typing; cursor-left then a mid-buffer
  insert; cursor-left, delete, cursor-right) each committed via
  `INTERPRET_RUN` and checked against the correct final result. The
  real interactive entry point (`EDITOR_LOOP_LIVE`) is written but
  **not yet safely callable** — see `docs/PROJECT_PLAN.md` Phase 6 for
  a real precondition found while writing it (`kernel/io`'s
  `IO_READ_KEY` needs a live interrupt wired up first, which no ROM in
  this project sets up yet).
- Phase 7 (`core/storage.asm` + `rom/forth_smoke_p7.asm`): storage —
  `SAVE`/`LOAD` as whole-dictionary-image blobs on `STORAGE_SAVE`/
  `STORAGE_LOAD`, Jupiter-Ace-style. Calls only the documented public
  contract, never `kernel/storage`'s own internals — a deliberate
  design constraint from a real compatibility warning (the tape format
  is fragile; deviating from it breaks real emulator LOAD). Found and
  fixed two real integration bugs along the way (`IX` gets destroyed by
  the storage calls; `STORAGE_LOAD`'s filename match needs a real
  space-padded 10-byte buffer, not a raw shorter one) — see
  `docs/PROJECT_PLAN.md` Phase 7 for both. Confirmed passing against an
  in-memory fake tape transport (kernel/storage's own
  `STORAGE_TEST_FAKE_SEND`/`RECEIVE` hooks); a **real Fuse tape
  round-trip is still open, deliberately deferred** — this proves the
  wiring, not real wire-format compatibility in an actual emulator.
- Phase 8, stretch goals (`core/float.asm` + `rom/forth_smoke_p8.asm`;
  `kernel/mode64/mode64.asm` + `core/mode64.asm` + `rom/forth_smoke_p8b.asm`):
  - **Floating point** — `F+`/`F-`, a small native Forth float
    implementation (3-byte mantissa+exponent, its own `IY`-addressed
    stack), NOT a port of 2068-Leap's real `RST $28` calculator engine
    (assessed as multi-session-sized; this project is free to diverge).
    Confirmed passing under Fuse. `F*`/`F/`/`F.` remain open.
  - **64-column display** — `64COL`, `32COL`, `PALETTE64`, `PLOT64`.
    This is recovered, once-shipped 2068-Leap code (removed from that
    project 2026-08-20 for its own ROM-budget reasons), found in a
    pre-git backup tarball at the user's own suggestion — good thing:
    the ROM disassembly alone led to a real, wrong first attempt (bit 2
    alone, when the real hardware needs bits 1+2 together). Confirmed
    passing under Fuse; a genuine unexplained rendering observation
    (the whole visible area, border included, renders as one uniform
    color while this mode is active) is recorded, not resolved — see
    `docs/PROJECT_PLAN.md` Phase 8 for the full story.
- Phase 9 (`rom/forth_boot.asm` + `rom/forth_smoke_p9.asm`): **a real,
  live, bootable system.** Every phase's dictionary words spliced into
  one `FIND`-able chain (a real structural fix — `core/control.asm`,
  `core/storage.asm`, and `core/float.asm` were siblings of a tree, not
  links in one chain, until this phase); real `IM 1` interrupt wiring,
  confirmed against 2068-Leap's own working ROM files; a boot banner
  and startup sound (the tracked product requirement — done). Confirmed
  working by a human typing `5 BORDER` at the running system and
  watching the border turn cyan — the first genuine end-to-end proof in
  this project not based on a fixed test string. Getting there
  surfaced two real bugs no automated test could have caught (an
  accumulating-inverted-text redraw bug, and a case-folding bug — real
  keyboards produce lowercase letters, the whole dictionary is
  uppercase), both found live with the user typing at the keyboard and
  one diagnosed from a real Fuse memory-dump snapshot. See
  `docs/PROJECT_PLAN.md` Phase 9 for the full story.
- Phase 10 (`core/print.asm` + `rom/forth_smoke_p10.asm`): `EMIT` and
  `.` — the first words in this project that can show a computed value
  on screen. Includes a from-scratch unsigned divide-by-10
  (`kernel/math`'s divide is signed, which mishandles `-32768`'s
  magnitude) confirmed correct via a real property of two's-complement
  negation, not luck. Confirmed passing under Fuse (five checkpoints,
  including a real `GFX_READ_PIXEL` readback for `EMIT`). Wiring this
  into `rom/forth_boot.asm` surfaced one more real bug — `COLD_START`
  started the print cursor at `(0, 0)`, exactly where the boot banner's
  own text is, so `EMIT`'s first output silently overwrote it — found
  live by the user, isolated with a deterministic headless diagnostic,
  and fixed by starting the cursor below the banner instead. See
  `docs/PROJECT_PLAN.md` Phase 10 for the full story.
- Phase 11 (`core/compare.asm` + `rom/forth_smoke_p11.asm`): `=`, `<`,
  `>` — signed comparisons, filling the gap `docs/forth_tutorial.md`
  had flagged since Phase 4. No `kernel/` dependency. Signed `<`/`>`
  use a sign-bit case split rather than the Z80's own overflow flag,
  hand-verified against six cases including both 16-bit extremes.
  Confirmed passing under Fuse (ten comparisons across three
  checkpoints) and re-verified wired into `rom/forth_boot.asm`'s full
  chain via a deterministic diagnostic. See `docs/PROJECT_PLAN.md`
  Phase 11 for the full story.
- Phase 12 (`core/variable.asm` + `rom/forth_smoke_p12.asm`):
  `VARIABLE` and `CONSTANT`, filling the last gap
  `docs/forth_tutorial.md` had flagged since Phase 4. Neither uses a
  real `CREATE`/`DOES>` (this project doesn't have one) — both reuse
  `core/interp.asm`'s own `DOLIT` compiled-literal idiom plus a
  compiled `RET`. Confirmed passing under Fuse (three checkpoints,
  including proof that two variables don't alias each other's storage)
  and re-verified wired into `rom/forth_boot.asm`'s full chain via a
  deterministic diagnostic. See `docs/PROJECT_PLAN.md` Phase 12 for the
  full story.
- Phase 13 (`core/dotquote.asm` + `rom/forth_smoke_p13.asm`): `."`
  (print a literal string), the last item on `docs/forth_tutorial.md`'s
  gap list except counted loops, more graphics/sound, and
  decimal-number multiply/divide. Compile-time only, like
  `IF`/`ELSE`/`THEN`. Generalizes `core/interp.asm`'s own `DOLIT`
  inline-data idiom from a fixed 2-byte literal to a variable-length
  string. A real design mistake (an unneeded extra space-skip that
  would have eaten the string's own first character) was caught by
  hand-tracing before ever assembling it. Confirmed passing under Fuse
  (three checkpoints, including the empty-string edge case and
  combination with `IF`/`ELSE`/`THEN`) and re-verified wired into
  `rom/forth_boot.asm`'s full chain. See `docs/PROJECT_PLAN.md` Phase
  13 for the full story.
- Phase 14 (`core/loop.asm` + `rom/forth_smoke_p14.asm`): `WHILE`/
  `REPEAT`, the pre-tested counterpart to Phase 4's post-tested
  `BEGIN`/`UNTIL`. Reuses `core/control.asm`'s own `QBRANCH`/`BRANCH`
  runtime directly rather than modifying that already-shared file.
  `DO`/`LOOP` remains open — it needs its own loop-control storage
  design, since this project's subroutine threading already uses the
  Z80 hardware stack for real return addresses. Confirmed passing
  under Fuse (three checkpoints, including the crucial case where the
  loop body must never run at all) and re-verified wired into
  `rom/forth_boot.asm`'s full chain. See `docs/PROJECT_PLAN.md` Phase
  14 for the full story.
- Phase 15 (`core/color.asm` + `rom/forth_smoke_p15.asm`): `INK`/
  `PAPER`. Unlike every phase since 12, this one genuinely required
  editing the already-shared `core/ts2068.asm` — `PLOT`/`LINE`/`CIRCLE`
  now read their attribute from a settable `CURRENT_ATTR` cell instead
  of a hardcoded constant, a deliberate, consciously-accepted exception
  to this project's "add a new file, don't touch a shared one"
  practice. Every existing consumer of `core/ts2068.asm`
  (`rom/forth_smoke_p5.asm`, `rom/forth_smoke_p9.asm`,
  `rom/forth_boot.asm`) got a one-line `COLD_START` addition and was
  rebuilt and re-verified passing under real Fuse with no regression.
  Confirmed passing under Fuse (three checkpoints, reading back the
  REAL screen attribute byte, not just internal state) and re-verified
  wired into `rom/forth_boot.asm`'s full chain. See
  `docs/PROJECT_PLAN.md` Phase 15 for the full story.
- Phase 16 (`core/doloop.asm` + `rom/forth_smoke_p16.asm`): `DO`/
  `LOOP`/`I` — the counted loop deferred since Phase 4, the item
  repeatedly flagged as the hardest one left. The loop's own
  limit/index live on the real Z80 hardware stack itself: this
  project's subroutine threading already uses that stack as a de facto
  return stack since Phase 2, so `DO`/`LOOP` just reuse that same
  discipline rather than inventing a separate one. A real bug was
  caught in the test, not the implementation (trying to use `DO`/`LOOP`
  outside a colon definition, where the compiled runtime calls never
  actually run) — fixed by wrapping it properly, the same restriction
  `IF`/`ELSE`/`THEN`/`BEGIN`/`WHILE`/`REPEAT` already have. Confirmed
  passing under Fuse (three checkpoints, including the critical
  nested-loop stack-discipline case) and re-verified wired into
  `rom/forth_boot.asm`'s full chain. See `docs/PROJECT_PLAN.md` Phase
  16 for the full story.
- Phase 17 (`core/moregfx.asm` + `rom/forth_smoke_p17.asm`): `FILL`/
  `AT-XY` — the rest of "More graphics" short of hi-res mode. `FILL`
  wraps `kernel/graphics`'s own proven `GFX_FILL`, picking up
  `CURRENT_ATTR` like `PLOT`/`LINE`/`CIRCLE` since Phase 15; `AT-XY`
  moves `core/print.asm`'s own print position directly. Another real
  bug caught in the test, not the implementation: a `GFX_READ_PIXEL`
  B/C argument-order mixup (a different convention from
  `GFX_CELL_ATTR_ADDR`, used earlier in the same test) — found and
  fixed before trusting the checkpoint. Confirmed passing under Fuse
  (three checkpoints, including a bounded-fill verification and a
  column-wrap-boundary check) and re-verified wired into
  `rom/forth_boot.asm`'s full chain. See `docs/PROJECT_PLAN.md` Phase
  17 for the full story.
- Phase 18 (`core/floatmul.asm` + `rom/forth_smoke_p18.asm`): `F*`
  (float multiply) — the first half of the decimal multiply/divide gap
  (`F/` remains open, deliberately not rushed alongside it). Writes its
  own 32-bit widening multiply and real normalization pass, since
  `kernel/math`'s own multiply only gives a 16-bit truncated result. A
  real design mistake (a fixed-position window instead of proper
  normalization) was caught by hand-tracing `2.0*3.0` before ever
  assembling it, and a second real structural bug (a hardcoded
  dictionary-chain anchor that would have collided with
  `core/mode64.asm`) was caught before wiring it into
  `rom/forth_boot.asm`. Confirmed passing under Fuse (four hand-verified
  cases, including sign handling) and re-verified wired into the full
  chain, including confirming the chain-anchor fix actually worked. See
  `docs/PROJECT_PLAN.md` Phase 18 for the full story.
- Phase 19 (`core/floatdiv.asm` + `rom/forth_smoke_p19.asm`): `F/`
  (float divide) — completes the decimal multiply/divide gap. Derived
  by direct analogy to `F*`'s already-solved normalization problem:
  scales the dividend up by 2^16 before a new 32-bit/16-bit restoring
  division, then reuses `core/floatmul.asm`'s own `F_NORMALIZE32`
  completely unchanged. The exponent formula and all three
  normalization paths were hand-verified before ever assembling it —
  and all four Fuse checkpoints passed on the first real run, no bugs
  found needing a fix this time. Wired into `rom/forth_boot.asm`'s full
  chain, using `DICT_CHAIN_POINT` correctly from the start (Phase 18's
  hardcoded-anchor mistake wasn't repeated). See `docs/PROJECT_PLAN.md`
  Phase 19 for the full story.
- Phase 20 (`core/key.asm` + `rom/forth_smoke_p20.asm`): `KEY` — the
  input counterpart to `EMIT`, deferred since Phase 2. Thin wrapper
  over `kernel/io`'s `IO_READ_KEY`. Tested by simulating a keypress
  (writing `KBD_LASTK`/`KBD_KEYHIT` directly) rather than needing a
  live interrupt. Wired into `rom/forth_boot.asm`'s full chain.
- Phase 21 (`rom/forth_boot.asm` update + `rom/forth_smoke_p21.asm`):
  error feedback — an unknown word at the live prompt now prints `"?"`
  and a newline instead of silently discarding the line. Verified both
  in isolation and against the real, complete dictionary chain, plus
  confirming the interpreter genuinely recovers for the next line, not
  just that it doesn't crash.
- Phase 22 (`core/floatprint.asm` + `rom/forth_smoke_p22.asm`): `F.`
  (print a float) — a fixed 4 decimal digits (e.g. `"6.0000"`,
  `"-2.0000"`), reusing `F*`'s widening multiply and `F/`'s division
  engine rather than duplicating either. A real register-clobbering bug
  was caught on the first real Fuse run (not by hand-tracing this
  time): a loop counter shared register `B` with `UDIV10`, which
  destroys `B` internally, causing a genuine hang confirmed by two
  screenshots seconds apart showing identical, frozen state. Fixed and
  re-verified against the real, complete dictionary chain.
- Phase 23 (`core/decimal.asm` + `rom/forth_smoke_p23.asm`): decimal
  number literal parsing — typing `3.5` now pushes a real float
  directly, completing what `F+`/`F-`/`F*`/`F/`/`F.` needed to be
  actually typeable. `core/interp.asm`'s `NUMBER`/`INTERPRET_RUN` (the
  single most shared routines in the project) are only changed behind
  an `IFDEF DECIMAL_NUMBER_ENABLED` opt-in — verified byte-for-byte
  identical for every ROM that doesn't opt in, not just reasoned about.
  Reuses `F*`'s `F_NORMALIZE32` and `F/`'s `F_UDIV32BY16` rather than
  inventing new conversion logic. A real, timely `JR` range warning
  (caught by the static checker, not by running anything) was fixed
  along the way. Confirmed passing under Fuse with a full combined test
  (a decimal literal typed directly, one compiled inside a word, `F*`,
  and `F.` together) and re-verified against the real, complete
  dictionary chain.
- Phase 24 (`core/doloop.asm` update + `rom/forth_smoke_p24.asm`):
  `LEAVE` (exit a `DO`/`+LOOP` loop early) and `+LOOP` (step by
  something other than 1, including negative). `+LOOP`'s runtime
  compares the SIGN of `(index - limit)` before and after adding the
  step rather than testing for exact equality, since a non-1 step can
  jump clean past `limit` without ever landing on it — the standard
  fix for the same reason real Forth systems need it. `LEAVE` threads
  its own placeholder branch targets into a linked list per loop
  nesting level (`LEAVE_HEAD_TABLE`, indexed by `LEAVE_DEPTH`), patched
  once `LOOP`/`+LOOP` finally know the real loop-exit address — a
  dedicated side table, not the borrowed compile-time stack `IF`/
  `BEGIN` already use, because `LEAVE` is normally written as
  `IF LEAVE THEN`, and at the moment `LEAVE` compiles, `IF`'s own
  still-open placeholder — not the loop's own bookkeeping — is what's
  sitting on top of that shared stack. Two more real, Fuse-reproduced
  bugs got caught and fixed along the way, not just reasoned past: new
  `+LOOP` scratch RAM addresses picked by extending the prior phase's
  own block turned out to alias `core/print.asm`'s `PRINT_ROW`/
  `PRINT_COL` (silently corrupting print position on every `+LOOP`
  pass), and a helper shared between `LOOP`/`+LOOP` clobbered `DE`
  after the caller had already loaded it with the real loop-exit
  address, sending every `LEAVE` into raw RAM data instead of past the
  loop. Confirmed passing under Fuse: `LEAVE` firing mid-loop, `+LOOP`
  stepping by 2, and nested `DO` loops where an inner `LEAVE` exits
  only the inner loop, all isolated individually before the combined
  smoke ROM.
- Phase 25 (`core/mathfn.asm` + `rom/forth_smoke_p25.asm`): `ABS`,
  `SGN`, `MOD`, `SQRT`, `RND`, `RANDOMIZE` — a direct audit of
  2068-Leap's own BASIC ROM against this project's dictionary (see
  `docs/PROJECT_PLAN.md`'s Phase 25 section) found these had no Forth
  equivalent at all. Every one is a thin wrapper around an
  already-verified `kernel/math/math.asm` routine this project
  inherited — no new algorithm, matching `core/ts2068.asm`'s own
  PLOT/LINE/CIRCLE precedent for wrapping kernel/ primitives. `RND`'s
  underlying LFSR was independently cross-checked: a fixed seed
  (`12345 RANDOMIZE`) produces a sequence hand-simulated in Python from
  the kernel routine's own documented algorithm, and the real Fuse run
  printed the exact predicted values. Along the way, a real,
  previously-undetected bug was found and fixed in the single most
  shared routine in the project: `core/interp.asm`'s `NUMBER` failed on
  ANY negative integer literal (`-5`, say) once `DECIMAL_NUMBER_ENABLED`
  (Phase 23) was active — `CHECK_FOR_DOT`'s own documented contract
  destroys `HL`, but `NUMBER`'s sign-check right after calling it never
  reloaded `HL` from `NUM_PTR`, so it read garbage instead of `-`. Only
  negative numbers were affected (positive tokens never triggered the
  broken branch by coincidence), and it had shipped undetected since
  Phase 23 because no prior smoke ROM combined `DECIMAL_NUMBER_ENABLED`
  with a negative whole number. Fixed with a one-line reload, gated the
  same way as every other Phase 23 hook so ROMs that don't opt in stay
  byte-for-byte identical (re-verified by diffing `forth_smoke_p3`,
  `forth_smoke_p9`, and `forth_smoke_p16` before/after).
- Phase 26 (`core/array.asm` + `rom/forth_smoke_p26.asm`): `ARRAY` and
  `CELLS` — closing the BASIC-audit's `DIM` gap. `n ARRAY name` creates
  a fresh, zero-initialized `n`-cell array whose name pushes its base
  address; elements are read/written with plain `@`/`!` at
  `index CELLS name +`, the same address-arithmetic convention real
  Forth systems use (no dedicated indexing word, matching ANS Forth's
  own `CREATE`/`ALLOT` idiom). Confirmed under Fuse: a fresh array
  reads back as zero, a `CELLS`-indexed write/read round-trips
  correctly, and every OTHER element stays zero after that write
  (proving the zero-init loop covers the whole block, not just element
  0, and the write didn't corrupt a neighboring cell).
- Phase 27 (`core/string.asm` + `rom/forth_smoke_p27.asm`): `S"`,
  `TYPE`, `STRING`, `PLACE`, `COUNT`, `LEN`, `VAL` — real string
  handling, closing the biggest single remaining BASIC-audit gap
  (2068-Forth had none at all before this: `."` prints a fixed literal,
  but there was no way to store, measure, or convert text). Strings are
  the standard Forth `(addr len)` pair on the stack, plus a counted-
  string representation (1 length byte + data) for mutable `STRING`
  buffers — not a new convention, the same one this project's own
  dictionary name fields already use internally. Deliberately does NOT
  include `CHR$`/`STR$`/`UPPER$`/`LOWER$`/`LEFT$`/`RIGHT$`/`INSTR`/
  `CODE` — a stated scope cut, not an oversight; the six words here
  turn "no string handling at all" into "hold text in a variable,
  print it, measure it, read a number out of it," which is the part
  that actually blocked writing real programs.
  Two real bugs were found and fixed during Fuse verification, not
  just designed around: `S"` originally only compiled its own runtime
  call and returned, correct inside a colon definition (where the
  surrounding word's later execution reaches that compiled code) but
  silently pushing NOTHING when used directly at the interpreter prompt
  — confirmed by literally measuring the data stack pointer's own depth
  before/after, not just eyeballing output. A first fix (jump straight
  into the just-compiled code) traded that bug for a worse one — a real
  hang, since the compiled runtime tries to return to "whatever comes
  next," which is blank dictionary space at the top level, not another
  word's body. Fixed properly by having `S"` push `(addr len)` directly
  itself when interpreting, never running the compiled code in that
  case at all. Separately, a review of every smoke ROM with 4+
  checkpoints found a real methodology footgun: `CHECKPOINT_NUM`'s own
  FAIL-path border color can numerically collide with `PASS_TEST`'s
  green (both use plain `4`), making a checkpoint 4 failure
  indistinguishable from genuine success by color alone — this project
  had actually shipped exactly that: Phase 27's own first draft smoke
  ROM showed a false all-green pass while checkpoint 4 was silently
  failing underneath it. Fixed here by renumbering border colors to
  avoid literal `4`; `forth_smoke_p18`/`p19` (also 4-checkpoint ROMs)
  were re-verified by temporarily relabeling their own checkpoint 4 and
  reconfirming a real, unambiguous pass — both genuinely correct, not
  affected in practice.
- Phase 28 (`core/input.asm` + `rom/forth_smoke_p28.asm`): `ACCEPT` and
  `INPUT` — line input, closing the last of the six real BASIC-audit
  gaps. `ACCEPT ( dest maxlen -- len )` is the standard ANS Forth line-
  reading word (echoing as it goes, `DELETE` supported, typing past
  `maxlen` silently ignored); `INPUT ( -- n )` is a BASIC-style
  convenience built on top of it, reading a line into a small internal
  buffer and parsing it with `VAL` (Phase 27) — the same shape as
  BASIC's own `INPUT A` for a numeric variable. Verification needed a
  different technique than every earlier phase's single-simulated-
  keypress trick (`KEY`'s own Phase 20 smoke ROM): `ACCEPT`'s internal
  loop calls the keyboard read routine many times in a row with no
  point to intervene in between, so this smoke ROM uses REAL `IM 1`
  interrupts with its own scripted fake keyboard ISR, feeding one
  character per real hardware tick — the same interrupt wiring
  `rom/forth_smoke_p9.asm` first proved, repurposed to drive a canned
  typing sequence instead of a live keyboard. Confirmed under Fuse:
  typing past a buffer's limit is correctly ignored, `DELETE` visually
  erases the right character, and `INPUT` correctly parses a typed
  number — plus a real duplicate-label collision caught immediately by
  the assembler (this project's own new `INPUT_BUF` name collided with
  an unrelated, pre-existing sysvar of the same name already defined in
  the inherited `include/sysvars.inc`) fixed by renaming.
- Phase 29 (`core/floatsqrt.asm` + `rom/forth_smoke_p29.asm`): `FSQRT`
  — float square root, following up on Phase 25's own note that "float
  versions of some of these... are a natural later addition." Widens
  `kernel/math`'s own `MATH_SQRT16` to a 32-bit input, 16-bit output
  routine (`F_SQRT32`) exactly the way `core/floatmul.asm`'s own
  `F_UMUL32` and `core/floatdiv.asm`'s own `F_UDIV32BY16` already
  widened `MATH_UMUL16`/`MATH_UDIV16` — the third time this project has
  made that exact move. Handles an odd exponent by exactly doubling the
  mantissa first (lossless, since the mantissa is always small enough
  to survive it) so the "divide the exponent by 2" step is always exact
  arithmetic on an even number, then reuses `F_NORMALIZE32`
  (`core/floatmul.asm`) unchanged to land the raw integer root back in
  this project's usual normalized mantissa shape. Negative input
  returns 0, matching `MATH_SQRT16`'s own convention (and, by
  extension, Phase 25's own integer `SQRT`). Hand-verified against
  three cases before ever assembling it — an even-exponent exact case
  (`sqrt(4.0)=2.0`), an odd-exponent exact case (`sqrt(9.0)=3.0`), and
  an odd-exponent irrational case (`sqrt(2.0)`) — all three confirmed
  matching exactly under real Fuse, down to `F.`'s own printed digits.
  Also re-verified against `rom/forth_boot.asm`'s own full dictionary
  chain using REAL typed decimal literals (`9.0 FSQRT F.` →
  `"3.0000"`, using the decimal-literal parser's own independently-
  computed representation of 9.0, not the hand-picked test value —
  confirming the algorithm generalizes correctly, not just for the
  specific inputs it was hand-verified against).
- **Foundational fix, its own commit** (`core/float.asm` +
  `rom/forth_smoke_p8.asm`): `F+`/`F-` had a silent 16-bit
  mantissa-overflow bug present since Phase 8, found while designing
  `SIN`/`COS` (Phase 30) — a Python simulation of the planned table
  interpolation caught it before any Z80 trig code was written. Adding
  two same-sign, already-normalized mantissas near the ~32767 ceiling
  (routine for table-driven math, not a contrived edge case) could
  silently wrap into a wrong-signed result with no error raised. Fixed
  with standard post-add signed-overflow detection: a same-sign-in,
  opposite-sign-out result triggers a fallback that redoes the add from
  the aligned mantissas each halved by one bit, with the exponent
  bumped by one to compensate — costing one bit of precision only on
  the inputs that actually need it. Re-verified with a new fourth
  checkpoint proving the exact overflow case now returns the correct
  answer under real Fuse, the original three checkpoints still passing
  unchanged, and every dependent smoke ROM (`p18`/`p19`/`p29`,
  `rom/forth_boot.asm`'s full chain) rebuilding clean with no visible
  regression. See `docs/PROJECT_PLAN.md`'s own "Foundational fix"
  section for the full story, including a separate, narrower,
  not-yet-fixed `F_ALIGN` signed-comparison quirk found and ruled out
  (but not fixed) during the same investigation.
- Phase 30 (`core/floattrig.asm` + `rom/forth_smoke_p30.asm`): `PI`,
  `SIN`, `COS` — the user's own direct follow-up to Phase 29.
  `COS(x) = SIN(x+HALF_PI)`, so one routine (`RAW_SIN`) does the real
  work: range-reduce into `[0,2*PI)`, quadrant-reduce into a reference
  angle in `[0,HALF_PI]` plus a sign, then look up and linearly
  interpolate a 17-entry `SIN` table. Designed in a bit-exact Python
  simulation before any Z80 was written — the same simulation that
  surfaced the F+/F- overflow bug above, since table interpolation adds
  two near-ceiling mantissas together. A second lesson from that same
  simulation: an "idealized," corrected `F_ALIGN` comparison broke
  `SIN(0.0)`/`COS(0.0)` in the model, because `SIN`/`COS` genuinely
  depend on the REAL (buggy) `F_ALIGN`'s own zero-safety (`SIN_TABLE[0]`
  is exact zero, and `SIN(0)`/`COS(HALF_PI)` are too) — so this file's
  own comparisons are deliberately built only from a direct
  mantissa-sign peek (against zero) or a real `F-` against a nonzero
  constant (against `PI`/`HALF_PI`/etc), never a comparison that would
  put a stray zero through `F_ALIGN` unsafely. Confirmed under real
  Fuse twice: `rom/forth_smoke_p30.asm`'s six checkpoints all pass
  (one needed a fix on the first run — `SIN(0.0)` legitimately returns
  a zero mantissa with a nonzero exponent, and the checkpoint was
  wrongly demanding an exact `(0,0)`, not a bug in `SIN` itself); and
  live, by typing `1.0 SIN F.`, `PI F.`, and `2.0 COS F.` at
  `rom/forth_boot.asm`'s own real keyboard-driven prompt, printing
  `0.8408`, `3.1416`, and `-0.4156` — proving all three words are
  genuinely reachable via `FIND`, not just callable as raw subroutines.
- Phase 31 (`core/beep.asm` + `rom/forth_smoke_p31.asm`): a real,
  semitone/seconds `BEEP`, replacing Phase 5's own raw-hardware-units
  version — the user asked directly why `BEEP` didn't behave like the
  real 2068's, then asked for a real attempt. `BEEP ( n-semitones
  fduration -- )` decomposes the semitone number into a note (0-11) and
  an octave via a repeated-subtract-12 loop (the same idea the real ROM
  disassembly's own `BEEP`/`BEEPER` routines use — confirmed directly
  from the actual ROM disassembly, not guessed), looks the note up in a
  12-entry frequency-ratio table, and applies the octave as a direct
  EXPONENT shift (exact, no multiply needed). The frequency-to-hardware
  conversion is calibrated from first principles against
  `kernel/sound`'s own `SOUND_BEEP` loop's real, published Z80
  instruction timings (NOT the real ROM's own BEEPER constants, which
  are specific to ITS OWN differently-shaped timing loop) and the
  TS2068's own real, confirmed 3,528,000 Hz clock (libspectrum's own
  machine timing table) — `222 + 52*pitch` T-states per waveform cycle.
  The original word is preserved unchanged as `core/rawbeep.asm`,
  purely for `rom/forth_smoke_p5.asm`'s own historical checkpoint —
  `core/ts2068.asm` itself no longer defines `BEEP` at all.
  **A second real, foundational bug found and fixed along the way**:
  the naive formula subtracts a small constant (222) from
  `CPU_CLOCK/freq`, which is a LARGE number for low-pitched notes —
  exactly `core/float.asm`'s own documented `F_ALIGN` large-magnitude
  hazard (see the `2068forth-float-align-signed-cmp-quirk` memory
  note), confirmed directly (pitch -60, a real note, not contrived):
  the buggy float subtraction silently zeroed the large operand. Fixed
  by doing that step in plain 32-bit integer arithmetic instead (which
  never touches `F_ALIGN` at all), reusing `core/floatdiv.asm`'s own
  already-proven `F_UDIV32BY16` for the division — a second, related
  bug (converting to a plain 16-bit integer first, which silently
  overflowed for that same low pitch) was caught the same way, by the
  smoke ROM's own hand-derived checkpoint failing, not by inspection.
  Confirmed correct under real Fuse (`rom/forth_smoke_p31.asm`'s four
  checkpoints, checking the computed hardware parameters directly since
  actual audio output can't be verified in this environment — same
  strategy Phase 5's own original `BEEP` checkpoint used) and live, by
  typing `0 1.0 BEEP` at `rom/forth_boot.asm`'s own real prompt and
  confirming it returns control normally after playing (no hang).
- Phase 32 (`core/sound.asm` + `rom/forth_smoke_p32.asm`): `SOUND
  ( register data -- )`, the authentic register-level AY-3-8912
  command, distinct from `BEEP`'s computed musical notes — writes one
  raw byte straight into one chip register (1-16; out of range is
  silently ignored), confirmed from the real ROM disassembly's own
  `SOUND` routine. A documentation bug in this phase's own first draft
  (claiming a "register 1 = chip register 0" offset that the real ROM
  disassembly doesn't actually have) was caught and fixed by
  re-reading the actual bytes rather than trusting a summary — the code
  itself never had the bug. Confirmed under real Fuse
  (`rom/forth_smoke_p32.asm`'s three checkpoints, the same data-stack-
  hygiene proof `core/rawbeep.asm`'s own original `BEEP` checkpoint
  used) and, for the first time in this project, confirmed with REAL
  AUDIO by the user listening live: `8 15 SOUND` alone (the real ROM's
  own documented example) produced static, not a bug but the expected
  result of setting only a volume register with no tone period or
  mixer routing configured; a proper four-register sequence (tone
  period, mixer, volume) on Channel B produced a real, steady,
  recognizable tone the user confirmed by ear, then silenced again —
  the strongest verification any sound word in this project has had.
- Phase 33 (`core/editor.asm` + `kernel/graphics/graphics.asm` +
  `rom/forth_smoke_p33.asm`): a better color scheme (black paper,
  bright green ink), a genuinely flashing cursor (the editor was
  calling the kernel's own non-flashing invert routine by mistake — one
  line to switch to the FLASH-setting one), real word-boundary-aware
  multi-row input wrapping (replacing Phase 6's single-row, 31-char,
  silently-truncating editor), and an old-Mac-style startup chord
  (picked from several options) replacing the old flat `SOUND_BEEP`
  tone. Three real bugs found along the way, the third the most
  interesting: a capacity-check design bug caught by Python simulation
  before any Z80 was trusted; a genuine stack-corruption hang in the
  new multi-row redraw code, found via a real Fuse hang and a
  border-color waypoint diagnostic; and — found live by the user, not
  by any automated test — backspacing a fully-typed line left several
  cells stuck flashing instead of going blank, because `EDITOR_REDRAW`'s
  blank-fill loop reused register `D` for a row parameter right after a
  call (`GFX_PUTCHAR`) documented to destroy it, silently no-oping the
  reset via `GFX_SET_ATTR`'s own bounds check. Root-caused with direct
  attribute-memory readback probes rather than guessed, then fixed and
  re-verified against the exact reported repro. +660 bytes total
  (`rom/forth_boot.asm`: 11364 -> 12024 of 16384).
- Phase 34 (`core/floatconv.asm` + `rom/forth_smoke_p34.asm`): `S>F`
  and `F>S`, the standard ANS Forth integer/float conversion words —
  asked about directly ("is that a standard Forth feature?"), confirmed
  yes, then added. `S>F` is exact (`mantissa=n, exponent=0`); `F>S`
  truncates, per the user's own explicit choice, via the exponent's
  sign shifting the mantissa left or right (reusing `core/float.asm`'s
  existing `F_SHRA` for the right-shift case). A real, documented
  caveat: reusing `F_SHRA` means `F>S` rounds toward negative infinity
  for negative fractional values, not toward zero (`F>S(-0.5) = -1`,
  not `0`) — whole numbers are unaffected either way. Confirmed via
  `rom/forth_smoke_p34.asm`'s five checkpoints AND via a throwaway
  diagnostic that fed `42 S>F F>S` through the real `forth_boot.asm`
  dictionary chain and `INTERPRET_RUN`, not just direct word calls —
  proving the dictionary splice itself is wired correctly. +52 bytes
  (`rom/forth_boot.asm`: 12024 -> 12076 of 16384).
- Phase 35 (`core/floatconv.asm` + `rom/forth_smoke_p35.asm`): `FROUND`,
  standard ANS Forth's "round a float to the nearest integer" word —
  asked for right after trying `2.0 FSQRT F>S .` live and getting the
  (correct, truncated) `1` for `sqrt(2)`, wanting rounding as an option
  too rather than a replacement. `FROUND` stays a float (composes with
  the existing `F>S` for a rounded integer: `FROUND F>S`). The obvious
  "add half, then shift" rounding technique risks overflowing the
  16-bit mantissa before the shift runs; avoided instead by reusing
  `F_SHRA` unchanged and reading the CARRY FLAG it already leaves
  behind (an existing side effect of its own `SRA`/`RR`/`DJNZ` shift
  loop) as the rounding-decision bit — no addition, no overflow risk.
  Round-half-up (ties move toward positive infinity), hand-verified via
  Python simulation before any Z80 was written:
  `FROUND(0.5)=1` but `FROUND(-0.5)=0`, genuinely disagreeing with
  plain `F>S(-0.5)=-1` on the exact same input — both smoke ROMs
  confirm this on purpose. +34 bytes (`rom/forth_boot.asm`: 12076 ->
  12110 of 16384).
- Phase 36 (`core/ts2068.asm` + `core/bytemem.asm` + `core/key.asm` +
  `kernel/io/io.asm` + `rom/forth_smoke_p36.asm`): `CLS`, `C@`/`C!`, and
  `KEY?` — the highest-value group from a fresh three-way audit against
  2068-Leap and the real TS2068 ROM's own command set. `CLS` wraps the
  already-existing `GFX_CLS` (called internally everywhere, never
  exposed as a word). `C@`/`C!` are the standard byte-level
  counterparts to the existing cell-level `@`/`!` (BASIC's own
  `PEEK`/`POKE`). `KEY?` is the interesting one: the obvious
  implementation (wrap the already-existing `IO_READ_KEY_NONBLOCK`,
  built for BASIC's `INKEY$`) would have been WRONG — that routine
  consumes whatever key it finds, but standard Forth's `KEY?` must be a
  non-destructive lookahead (`KEY? IF KEY ... THEN` only works if `KEY?`
  leaves the key for `KEY` to consume). Fixed with a genuinely new,
  tiny kernel routine (`IO_KEY_AVAILABLE`) instead of repurposing the
  consuming one. Confirmed via `rom/forth_smoke_p36.asm`'s six
  checkpoints, including `KEY?` reading TRUE twice in a row (proving it
  doesn't consume) before `KEY` itself finally does. +85 bytes
  (`rom/forth_boot.asm`: 12110 -> 12195 of 16384).
- Phase 37 (`core/stick.asm` + `rom/forth_smoke_p37.asm`): `STICK`, the
  real ROM's own joystick-read command — the cheapest of the three
  items left in the post-Phase-36 backlog, since `kernel/io/io.asm`'s
  own `STICK_READ` (AY-3-8912 register 14, real hardware asymmetry
  between the two devices) already existed and just needed a thin
  `STICK ( device -- value )` wrapper. Confirmed under real Fuse with
  the same honest limit `SOUND`'s own smoke test already states: no
  joystick is actually connected in this environment, so the two
  checkpoints confirm STICK reaches real hardware without hanging,
  returns the value Fuse's own AY register 14 gives with nothing
  pressed (`0` for both devices, confirmed live before writing the
  checkpoints), and leaves a sentinel value below the device number
  completely untouched. +18 bytes (`rom/forth_boot.asm`: 12195 ->
  12213 of 16384).
- Phase 38 (`core/interp.asm` + `rom/forth_boot.asm` +
  `rom/forth_smoke_p38.asm`): runtime stack-error detection — asked for
  directly, comparing to 2068-Leap's own line-entry + runtime error
  handling; 2068-Forth already had the line-entry half
  (`INTERPRET_UNKNOWN_WORD`, prints `?` and recovers), nothing for
  runtime conditions like a stack underflow silently reading past the
  stack's own boundary. A single `STACK_CHECK` call added to
  `core/interp.asm`'s own `INTERPRET_RUN.loop` — the ONE place every
  dispatched word's own result already passes through, whether that
  word touches the stack via `DPOP_HL`/`DPUSH_HL` or (like many words)
  manipulates `(ix+0)`/`(ix+1)` directly — catches all four violation
  shapes (data/float stack underflow/overflow) without touching any
  individual word's own code. Gated behind `DEFINE
  RUNTIME_ERROR_CHECK_ENABLED` exactly like Phase 23's own
  `DECIMAL_NUMBER_ENABLED`, confirmed byte-for-byte identical for every
  ROM that doesn't opt in. Confirmed via `rom/forth_smoke_p38.asm`'s
  five checkpoints AND live in the real product ROM: a throwaway
  diagnostic typed `DROP` on a genuinely empty stack (printed
  `STACK?`), then `1 2 + .` right after — correctly printed `3`,
  proving real recovery, not just "didn't crash." First of three steps
  the user laid out (runtime detection, then a code-consolidation pass,
  then a `THROW`/`CATCH` review). +110 bytes (`rom/forth_boot.asm`:
  12213 -> 12323 of 16384).
- Phase 39 (`kernel/mode64/mode64.asm` + `rom/forth_boot.asm`): code
  consolidation pass — step 2 of the user's three-step plan. Scoped by
  a fresh read-only survey of every `core/`/`kernel/` file (explicitly
  excluding the 38 frozen `rom/forth_smoke_p*.asm` fixtures, which stay
  untouched once passing). Found and fixed a real, if dormant, RAM
  collision: `kernel/mode64/mode64.asm`'s own 64-column pixel scratch
  ($87B0-$87B4) byte-for-byte overlapped `core/floatmul.asm`/
  `core/floatdiv.asm`'s own scratch, both INCLUDEd together in the real
  `rom/forth_boot.asm` — confirmed dormant (the two code paths are
  never nested) but a real violation of this project's own address-map
  discipline, moved to a freshly-reverified free 9-byte gap. Also fixed
  a stale dictionary word-list comment in `rom/forth_boot.asm`'s own
  header, missing 34 real, shipped words (verified against a full
  extraction of the actual dictionary chain). Both fixes are pure
  renumbering/comment changes — confirmed via the specific ROMs
  exercising the affected code (`p8b`, `p18`, `p19`, `p9`) plus a full
  `make clean && make all` across every ROM in the project, zero
  errors, ROM size unchanged.
- Phase 40 (`core/stringext.asm` + `rom/forth_boot.asm` +
  `rom/forth_smoke_p40.asm`): `CHR`, `STR`, `UPPER`, `LOWER`, `LEFT`,
  `RIGHT`, `SEARCH`, `CODE` — closes `core/string.asm`'s own Phase 27
  scope cut. `INSTR` becomes `SEARCH` (ANS Forth's own STRING word-set
  name for the same job, real semantics: on a match, returns the
  REMAINDER of the haystack, not just the matched substring).
  `LEFT`/`RIGHT` are substring BY REFERENCE (Forth strings are already
  just an (addr len) view into memory, so nothing ever copies).
  `CODE` is directly composable as `DROP C@` (Phase 36), added anyway
  for the real ROM's own direct name. A real bug caught by this
  phase's own smoke ROM, not a design flaw: `UPPER`/`LOWER` mutate IN
  PLACE (genuinely necessary for their signature), and the first smoke
  ROM draft ran them against a ROM-embedded string literal — a silent,
  un-crashing no-op, since writes to ROM simply don't take effect on
  this hardware. Root-caused with a diagnostic dumping the actual
  resulting bytes (the code itself was already correct); fixed on the
  TEST side (copy into a real RAM buffer first) and documented as a
  stated requirement in `core/stringext.asm`'s own header. Also caught
  a second methodology bug before it shipped: numbering all 14
  hand-verified cases as checkpoints 1-14 directly would have made
  checkpoint 12 show the exact same green as `PASS_TEST` (the ULA
  border port only decodes 3 bits, so 12 truncates to color 4) —
  fixed by grouping into 6 checkpoint numbers instead. +451 bytes
  (`rom/forth_boot.asm`: 12323 -> 12774 of 16384).
- Phase 41 (`core/execute.asm` + `rom/forth_boot.asm` +
  `rom/forth_smoke_p41.asm`): `EXECUTE ( xt -- )` — standard Forth's
  own counterpart to BASIC's `USR(addr)`. Trivial in this project's own
  subroutine-threaded model: a colon definition compiles directly to
  real `CALL`s ending in `RET`, so there's no indirection layer between
  an execution token and directly-jumpable machine code for either a
  primitive or a user-defined word — the whole word is `call DPOP_HL`
  then `jp (hl)`, a plain jump so the target's own `RET` naturally
  returns to whoever called `EXECUTE`. Confirmed via
  `rom/forth_smoke_p41.asm`'s two checkpoints, the second one real
  end-to-end proof, not just assertion: compiles `: DOUBLE DUP + ;`
  through the actual colon-compiler at runtime, looks its own code
  address up through the real `FIND` (it has no compile-time label),
  then `EXECUTE`s that xt — proving the mechanism works identically on
  a primitive and a freshly-compiled word. +14 bytes (`rom/forth_boot.asm`:
  12774 -> 12788 of 16384).
- **`docs/forth_tutorial.md`** teaches the Forth
  *language* to a reader who doesn't already know it — from the
  standpoint of someone using the finished product, not this project's
  own build/test process. It assumes BASIC familiarity but not
  assembly, is organized the way Forth is actually taught (stack first,
  then defining words, then control flow and data, then the screen and
  keyboard) rather than the order features were built in, and includes
  real screenshots taken from a live Fuse session plus a
  forth-standard.org-style word-reference appendix.
- The language core is integer-only by design; see
  `docs/numeric_model.md` for why floating point is a deferred, optional
  addition rather than something the language is built on.

## Layout

```
core/       language-layer code, not hardware-facing:
              dict.asm    (Phase 2 — dictionary header format, data stack)
              interp.asm  (Phase 3 — outer interpreter, colon compiler)
              control.asm (Phase 4 — IF/ELSE/THEN, BEGIN/UNTIL)
              ts2068.asm  (Phase 5 — PLOT/LINE/CIRCLE/BORDER)
              editor.asm  (Phase 6 — line editing)
              storage.asm (Phase 7 — SAVE/LOAD)
              float.asm   (Phase 8 stretch — F+/F-)
              mode64.asm  (Phase 8 stretch — 64COL/32COL/PALETTE64/PLOT64)
              print.asm   (Phase 10 — EMIT/.)
              compare.asm (Phase 11 — =/</>)
              variable.asm (Phase 12 — VARIABLE/CONSTANT)
              dotquote.asm (Phase 13 — .")
              loop.asm    (Phase 14 — WHILE/REPEAT)
              color.asm   (Phase 15 — INK/PAPER)
              doloop.asm  (Phase 16 — DO/LOOP/I; Phase 24 — LEAVE/+LOOP)
              moregfx.asm (Phase 17 — FILL/AT-XY)
              floatmul.asm (Phase 18 — F*)
              floatdiv.asm (Phase 19 — F/)
              key.asm     (Phase 20 — KEY)
              floatprint.asm (Phase 22 — F.)
              decimal.asm (Phase 23 — decimal literals)
              mathfn.asm  (Phase 25 — ABS/SGN/MOD/SQRT/RND/RANDOMIZE)
              array.asm   (Phase 26 — ARRAY/CELLS)
              string.asm  (Phase 27 — S"/TYPE/STRING/PLACE/COUNT/LEN/VAL)
              input.asm   (Phase 28 — ACCEPT/INPUT)
              floatsqrt.asm (Phase 29 — FSQRT)
              floattrig.asm (Phase 30 — PI/SIN/COS)
              rawbeep.asm (Phase 5's original raw-units BEEP, kept for
                          rom/forth_smoke_p5.asm's own history)
              beep.asm    (Phase 31 — real, semitone/seconds BEEP)
              sound.asm   (Phase 32 — real, register-level SOUND)
kernel/     hardware-facing modules: inherited from 2068-Leap (memory,
            io, graphics, interrupt, math, sound, storage, bank) plus
            2068-Forth's own addition, mode64/ (recovered, once-shipped
            2068-Leap code — see that module's own header)
include/    hardware/keyboard constants and the inherited kernel API
            contract (include/kernel_api.inc)
rom/        ROM image assembly:
              main.asm            Milestone 0 boot stub
              forth_smoke.asm     Phase 2 smoke ROM
              forth_smoke_p3.asm  Phase 3 smoke ROM
              forth_smoke_p4.asm  Phase 4 smoke ROM
              forth_smoke_p5.asm  Phase 5 smoke ROM
              forth_smoke_p6.asm  Phase 6 smoke ROM
              forth_smoke_p7.asm  Phase 7 smoke ROM
              forth_smoke_p8.asm  Phase 8 stretch smoke ROM (floating point)
              forth_smoke_p8b.asm Phase 8 stretch smoke ROM (64-column)
              forth_smoke_p9.asm  Phase 9 smoke ROM (dictionary + interrupts)
              forth_smoke_p10.asm Phase 10 smoke ROM (EMIT/.)
              forth_smoke_p11.asm Phase 11 smoke ROM (=/</>)
              forth_smoke_p12.asm Phase 12 smoke ROM (VARIABLE/CONSTANT)
              forth_smoke_p13.asm Phase 13 smoke ROM (.")
              forth_smoke_p14.asm Phase 14 smoke ROM (WHILE/REPEAT)
              forth_smoke_p15.asm Phase 15 smoke ROM (INK/PAPER)
              forth_smoke_p16.asm Phase 16 smoke ROM (DO/LOOP/I)
              forth_smoke_p17.asm Phase 17 smoke ROM (FILL/AT-XY)
              forth_smoke_p18.asm Phase 18 smoke ROM (F*)
              forth_smoke_p19.asm Phase 19 smoke ROM (F/)
              forth_smoke_p20.asm Phase 20 smoke ROM (KEY)
              forth_smoke_p21.asm Phase 21 smoke ROM (error feedback)
              forth_smoke_p22.asm Phase 22 smoke ROM (F.)
              forth_smoke_p23.asm Phase 23 smoke ROM (decimal literals)
              forth_smoke_p24.asm Phase 24 smoke ROM (LEAVE/+LOOP)
              forth_smoke_p25.asm Phase 25 smoke ROM (ABS/SGN/MOD/SQRT/RND/RANDOMIZE)
              forth_smoke_p26.asm Phase 26 smoke ROM (ARRAY/CELLS)
              forth_smoke_p27.asm Phase 27 smoke ROM (string handling)
              forth_smoke_p28.asm Phase 28 smoke ROM (ACCEPT/INPUT)
              forth_smoke_p29.asm Phase 29 smoke ROM (FSQRT)
              forth_smoke_p30.asm Phase 30 smoke ROM (PI/SIN/COS)
              forth_smoke_p31.asm Phase 31 smoke ROM (real BEEP)
              forth_smoke_p32.asm Phase 32 smoke ROM (SOUND)
              forth_smoke_p33.asm Phase 33 smoke ROM (multi-row word wrap)
              forth_smoke_p34.asm Phase 34 smoke ROM (S>F/F>S)
              forth_smoke_p35.asm Phase 35 smoke ROM (FROUND)
              forth_smoke_p36.asm Phase 36 smoke ROM (CLS/C@/C!/KEY?)
              forth_smoke_p37.asm Phase 37 smoke ROM (STICK)
              forth_smoke_p38.asm Phase 38 smoke ROM (runtime stack-error detection)
              forth_smoke_p40.asm Phase 40 smoke ROM (string functions)
              forth_smoke_p41.asm Phase 41 smoke ROM (EXECUTE)
              forth_boot.asm      the real, live, bootable product ROM
tools/      build wrapper (sjasmplus_strict.sh) and static/simulated
            Z80 checks (check_asm.py, check_z80_opcodes.py, z80sim/)
docs/       PROJECT_PLAN.md (read this first, project/build-facing),
            forth_tutorial.md (learn the Forth language itself,
            user-facing — no assembly or build content), numeric_model.md
            (integer-core decision), hardware_notes.md (confirmed
            hardware facts, inherited from 2068-Leap)
```

## Quick start

Requires GNU Make, Python 3, and
[SjASMPlus 1.23.1](https://github.com/z00m128/sjasmplus/releases/tag/v1.23.1)
or a compatible newer release.

```sh
make boot             # assembles rom/main.asm -> build/forth_rom0.bin
make forth-smoke      # Phase 2 dictionary/primitives smoke ROM
make forth-smoke-p3   # Phase 3 outer interpreter/colon compiler smoke ROM
make forth-smoke-p4   # Phase 4 control-flow smoke ROM
make forth-smoke-p5   # Phase 5 TS2068 vocabulary smoke ROM
make forth-smoke-p6   # Phase 6 line-editing smoke ROM
make forth-smoke-p7   # Phase 7 storage (SAVE/LOAD) smoke ROM
make forth-smoke-p8   # Phase 8 stretch: floating point smoke ROM
make forth-smoke-p8b  # Phase 8 stretch: 64-column display smoke ROM
make forth-smoke-p9   # Phase 9 smoke ROM: full dictionary + real interrupts
make forth-smoke-p10  # Phase 10 smoke ROM: EMIT/.
make forth-smoke-p11  # Phase 11 smoke ROM: =/</>
make forth-smoke-p12  # Phase 12 smoke ROM: VARIABLE/CONSTANT
make forth-smoke-p13  # Phase 13 smoke ROM: ."
make forth-smoke-p14  # Phase 14 smoke ROM: WHILE/REPEAT
make forth-smoke-p15  # Phase 15 smoke ROM: INK/PAPER
make forth-smoke-p16  # Phase 16 smoke ROM: DO/LOOP/I
make forth-smoke-p17  # Phase 17 smoke ROM: FILL/AT-XY
make forth-smoke-p18  # Phase 18 smoke ROM: F*
make forth-smoke-p19  # Phase 19 smoke ROM: F/
make forth-smoke-p20  # Phase 20 smoke ROM: KEY
make forth-smoke-p21  # Phase 21 smoke ROM: error feedback
make forth-smoke-p22  # Phase 22 smoke ROM: F.
make forth-smoke-p23  # Phase 23 smoke ROM: decimal literals
make forth-smoke-p24  # Phase 24 smoke ROM: LEAVE/+LOOP
make forth-smoke-p25  # Phase 25 smoke ROM: ABS/SGN/MOD/SQRT/RND/RANDOMIZE
make forth-smoke-p26  # Phase 26 smoke ROM: ARRAY/CELLS
make forth-smoke-p27  # Phase 27 smoke ROM: string handling
make forth-smoke-p28  # Phase 28 smoke ROM: ACCEPT/INPUT
make forth-smoke-p29  # Phase 29 smoke ROM: FSQRT
make forth-smoke-p30  # Phase 30 smoke ROM: PI/SIN/COS
make forth-smoke-p31  # Phase 31 smoke ROM: real BEEP
make forth-smoke-p32  # Phase 32 smoke ROM: SOUND
make forth-smoke-p33  # Phase 33 smoke ROM: real multi-row word wrap
make forth-smoke-p34  # Phase 34 smoke ROM: S>F/F>S
make forth-smoke-p35  # Phase 35 smoke ROM: FROUND
make forth-smoke-p36  # Phase 36 smoke ROM: CLS/C@/C!/KEY?
make forth-smoke-p37  # Phase 37 smoke ROM: STICK
make forth-smoke-p38  # Phase 38 smoke ROM: runtime stack-error detection
make forth-smoke-p40  # Phase 40 smoke ROM: string functions
make forth-smoke-p41  # Phase 41 smoke ROM: EXECUTE
make forth-boot       # the real, live, bootable product ROM
make check            # static asm checks over core/, kernel/, and rom/
```

## Try it

`make forth-boot` builds the real, live product — not a smoke test.
Run it in Fuse with a real EXROM image (see `rom/forth_smoke.asm`'s own
header on why a real image, not a blank placeholder, matters here):

```sh
fuse --machine ts2068 --rom-ts2068-0 build/forth_boot_rom0.bin \
     --rom-ts2068-1 <a real EXROM image>
```

It boots to a banner, plays a short startup sound, and drops you at a
real keyboard-driven prompt. Try `5 BORDER` and press Enter, `5 3 + .`
to see `.` print `8` on the row below the banner, `5 3 > .` to see `-1`
(Forth's TRUE) printed, `VARIABLE FOO 42 FOO ! FOO @ .` to see `42`,
`: GREET ." HI" ; GREET` to see `."` print a literal string, `: FIVE 5 0 DO I . LOOP ; FIVE` to see
`0 1 2 3 4` printed, `100 100 30 CIRCLE 2 INK 100 100 FILL` to see a
red-filled circle, type a nonsense word like `FOOBAR` to see `?`
printed and the prompt recover cleanly, `3.5 2.5 F+ F.` to see a
real decimal literal expression print `6.0000`, or
`: EVENS 10 0 DO I . 2 +LOOP ; EVENS` to see `+LOOP` step by 2 and
print `0 2 4 6 8`, `12345 RANDOMIZE 100 RND .` to see a reproducible
pseudo-random number in `[0, 100)`, `5 ARRAY NUMS 99 3 CELLS NUMS + !
3 CELLS NUMS + @ .` to see a real array round-trip a value, or
`S" HELLO WORLD" TYPE` to print a string literal directly, or
`INPUT .` to type a number and have it printed back, or
`9.0 FSQRT F.` to see a float square root print `3.0000`.

## License

MIT — see [LICENSE](LICENSE).
