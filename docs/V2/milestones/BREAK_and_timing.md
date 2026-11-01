# BREAK and timing — BREAK stops a running word, recursion stops before the stack runs out, a faster interrupt: milestone report

**Date:** 2026-10-31. **Status: complete.** Branch `v2/step-break-timing` from master `0e9ebd0` (PR #14, step Display
speed, merged; `make test` passed on it, 510 s). The model is `~/2068-Leap-C`'s (`spec.md` 5.8, `src/runtime/rtexit.asm`
`RT_BREAKREQ` / `RT_NOBRK_END`, platform delta D4): native code has no dispatch loop to poll, so the interrupt routine
unwinds the running program when it accepts BREAK, unless a section defers it. Leap V2 is a bytecode VM whose loop
polls a flag the ISR sets (`VM_HALTED`); not applicable.

## 1. What was measured first (master `0e9ebd0`)

| What | Result |
|---|---|
| `KBD_ISR_TICK`, an idle frame | 2,010 T (+31 T entry, EI, RETI): 2.9% of a 69,893 T frame. `IO_KEY_SCAN_ALL` about 1,300 T (a push, pop and table lookup per row), `IO_FIND_KEY` over 8 empty rows about 580 T |
| ... a key held | 1,685 T a frame; 2,458 on the frame that accepts it |
| Where BREAK was seen | only `BREAK?` (its own scan), the tape words (SPACE), `EDIT`'s view (its leave key) |
| What could not be stopped | `: L BEGIN 0 UNTIL ; L` with BREAK held (never returns); BEEP's wait (up to 65,535 frames); `KEY` returned BREAK as 16, `ACCEPT` stored it; FILL's worst case (45.7M T) |
| `: R R ; R` | the machine stack ran down through the free RAM, the UDG table, the line store and the dictionary (SP `$9107` at the end), then the machine reset: the line store was lost |
| `: X 1 FOO ;` then `X` | `FOO ?`, then `X` reset the machine (the word was linked with half its code and no RET) |

The owner approved the recommendations (2026-10-31): Leap-C's model; the shapes stop at once, the sprites and `EDIT`
defer; `KEY`/`ACCEPT` stop rather than return 16; BREAK silences the AY; the recursion guard with -5; the scan
rewrite; the open `:` definition dropped after an error.

## 2. What changed

- **The interrupt routine** (`kernel/interrupt/interrupt.asm`). With no key tracked, one read of port `$FE` with
  every row selected ends an idle frame; otherwise `IO_KEY_SCAN_ALL` reads the rows with `IN A,(C)` / `RLC B` (no
  `ROW_TABLE`, no `IO_KEY_SCAN_ROW`), in page zero's room. `KBD_ISR_INIT` is gone (the cold start's RAM clear zeroes
  the keyboard cells; it sets `KBD_CUR_ROW` itself). On the frame that accepts a key it calls `BRK_ACCEPTED` (3 B;
  nothing on other frames). It uses no alternate register: LINE keeps its state there.
- **BREAK** (`core/throwcatch.asm`). `BRK_ACCEPTED`: not BREAK, return; a section defers it (`NOBRK` > 0), set
  `BRK_PEND` and return; else `EI` and `BRK_STOP`, dropping the interrupt's frame with the interrupted code's.
  `BRK_STOP` pages the EXROM out (depth forced to 1, then `BANK_PAGE_EXROM_OUT`), sets the AY's three volumes to 0,
  clears the latched key and `BRK_PEND`, and throws -28 (`W_THROW_HL`): CATCH sees -28; uncaught, the console prints
  `BREAK`. It is the same as `-28 THROW` at the interrupted instruction.
- **Sections that defer BREAK** (`NOBRK`, a counter; `BRK_SECTION_END` decrements it and stops on a pending BREAK):
  the console between lines (`NOBRK` 1 from the cold start and after each line; `INTERPRET_RUN` sets it to 0 and
  clears `BRK_PEND`, so BREAK at the prompt stays the console's key); `EDIT`'s view (BREAK is its leave key, and the
  view moves the store's lines: the BREAK is discarded after it); the `SPRITE-*` words (`EXROM_CALL_NOBRK`: a slot's
  background, image and shown flag change together); `GFX_SET_MODE` (`GFX_MODE`, `PORT_FF_SHADOW` and the port).
  FILL, CIRCLE, RECT and POLYGON(-FILL) stop at once (nothing of theirs outlives the call; FILL can take 13 s).
- **Nothing half-made** when BREAK lands between two stores: `:` records its header (`COLON_HDR`) before linking it;
  `FORGET` sets `LATEST` before `HERE`; `DOES>` writes its jump's 2 bytes between `DI` and `EI`; `LOAD-TEXT` keeps
  interrupts off from the load until `STORE_END` is set. Tape SPACE stops through `BRK_STOP` (-28 as before, with the
  AY and paging put right). Every other HOME routine a running word reaches was read for a multi-store update another
  word depends on; the rest are single 16-bit stores, transient work cells, or the screen.
- **The machine stack** (`STK_GUARD`). Only recursion grows it without bound, and recursion is a definition calling
  itself, `EXECUTE` or `CATCH`: the interpreter compiles `CALL STK_GUARD` before a definition's call to itself
  (`COMPILE_CALL_GUARDED`, the definition's code address in `COLON_XT`), `EXECUTE` and `CATCH` call it first. Below
  `MACHINE_STACK_GUARD` (`MACHINE_STACK_LIMIT` + 256) it throws -5, `RETURN STACK FULL`. The Forth tests use at most
  36 B below the prompt's SP (a canary over `$F3C8`-`$FEFB`); `: R R ;` stops after about 1,300 levels.
  `check_ram_layout.py` lets HOME code name the guard line.

## 3. Defects found and fixed

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| Running a word whose definition ended in an error reset the machine (linked, half its code, no RET) | the study | `COLON_DROP`: a line that ends in an error (or ABORT, QUIT) drops the open `:` definition (LATEST, then HERE) | +33 |
| A compile error inside `DO` left `LEAVE_DEPTH` raised: `EXIT` in the next definition compiled POPs for loops that were not there (a crash); after eight, LEAVE slots past `LEAVE_HEAD_TABLE` | writing the fix above | `COLON_DROP` zeroes it; ABORT and QUIT no longer need to | −2 |
| A THROW caught around `LOAD-TEXT` or `EDIT` went on interpreting the rest of the loaded text and lost the console line (BREAK under the tutorial's `' LOAD-TEXT CATCH name` ran the rest of the program) | the study (read), then tapetest case CS | CATCH keeps the source with its frame; THROW puts it back when a nested run moved it; `CATCH_SRC_HERE` moves the frames' position past the name. A first fix that always restored it read the name again (`' ' CATCH FOO` → `FOO ?`): caught by a new `catch.fs` line | +83 |
| After `3 PAPER CLS`, output that scrolled (`VLIST`) cleared its new rows white (`ATTR_DEFAULT`) | the owner, in Fuse | `GFX_CLEAR_ROW` takes the attribute: EMIT's new row `CURRENT_ATTR`, the edit line's row `ATTR_DEFAULT` | +5 |
| The scheduled ones: nothing checked the machine stack's depth; no running word could be stopped | the roadmap | section 2 | |

## 4. Tests

Each change has tests that fail on the old build (master `0e9ebd0`, a worktree, `--build`):

| Test | On the old build |
|---|---|
| boot suite check o `interrupt cost`: an idle frame at most 300 T, a held key at most 1,000 T | 2,010 / 1,685 T: fail |
| `tests/io/break.fs`, with forthtest's new `\ break: at SYMBOL [N]` / `\ break: after N` (Leap-C exectest's): BREAK in `BEGIN 0 UNTIL` (uncaught: `BREAK`; under CATCH: `-28 2`), in `KEY`, `ACCEPT`, a 60 s `BEEP` (AY volume 0 after), FILL (EXROM depth 0 after), `HIRES` (deferred: the mode fully set), a BREAK pending in `SPRITE-SHOW` (stops at its end, the slot shown) | the loop never returns: fail |
| editor suite `break-running`, part plain: BREAK held stops `L`, `BREAK` printed, the latch used up | still looping: fail |
| `tests/core/rstack.fs`: `: R R ;`, `['] R2 EXECUTE`, `['] R3 CATCH` stop with `RETURN STACK FULL` / -5, a variable survives, `7 FAC` still 5040 | the machine resets: fail |
| `tests/core/colondrop.fs`: HERE back after `: X 1 FOO ;`, `X ?`, a definition over two lines, `[ -42 THROW ]`, `[ ABORT ]`, `LEAVE_DEPTH` 0 and `EXIT` after an error in `DO` | HERE 9 B on; `LEAVE_DEPTH` 1: fail |
| tapetest case CS: `' LOAD-TEXT CATCH THROWER . 88 .` on a text that prints 3 and throws 5 prints `3 5 88` | `3 77`: fail |
| `tests/core/catch.fs`: `' ' CATCH NOSUCHWORD . 99 .` prints `-13 99` | passes (a guard for the CATCH fix) |
| `tests/io/break.fs`: the tutorial's new example (section 13, Catching BREAK) prints `STOPPED`, the border white again | the loop never returns: fail |
| `tests/graphics/cls.fs`: after `0 INK 3 PAPER CLS` and output that scrolls, and after `VLIST`, row 21's last cell is 24 (paper 3) | 56: fail |

### Results (`make test`, 2026-10-31, 699 s on the final image)

The float suite's 12 THROW checks failed in that run: `tools/floattest.py` fakes a CATCH frame, which now holds the
input source under the return address; the tool was changed to match (the ROM was not) and the suite then passed
66/66.

| Suite | Result |
|---|---|
| boot | 13/13 |
| forth | 59/59 |
| editor | 30/30 (old 19, new 11) |
| float | 66/66 |
| shape | 48/48 |
| bench | 6/6 |
| poweron | 7/7 |
| tape | 19/19 |

`make check` and `make repro` pass.

## 5. Speed

| What | Before | After |
|---|---:|---:|
| Interrupt routine, idle frame | 2,010 T | 207 T |
| Interrupt routine, a key held | 1,685 T | 886 T |
| `bench sieve` | 143,709,356 T | 139,989,870 T (−2.6%) |
| `bench float` | 141,572,289 T | 137,906,860 T (−2.6%) |
| `bench pixel` | 33,116,550 T | 32,258,944 T (−2.6%) |
| `bench text` / `string` / `literals` | 3,074,966 / 2,001,365 / 590,305 T | 2,995,019 / 1,948,878 / 575,957 T |

Every program gains the 1,800 T a frame the idle interrupt no longer takes. BREAK is accepted after the keyboard's
two-frame debounce, as any key. A recursive call costs about 60 T more (the guard); `EXECUTE` and `CATCH` about 45 T.

## 6. Sizes

| Image | Before | After |
|---|---:|---:|
| HOME free | 2,188 B | 1,939 B |
| EXROM free | 3,208 B | 3,208 B |

Ledger (`budget.toml`): kernel −34 (the scan), +11 (the BREAK call, the mode change), +2 (the row clear); boot −8 (the
scan in page zero's padding), +19 (the -5 message); interp +28, −2 (the open definition, LEAVE_DEPTH), +70 (BREAK),
+43 (the stack guard), +77 (CATCH and the source); graphics +13 (the sprites' section); console +5, +16, +3; tape −3,
+3; text +3. RAM: 8 bytes of cells (`COLON_HDR`, `COLON_XT`, `BRK_PEND`, `NOBRK`), 112 B of room left.

## 7. Emulator limits

ZEsarUX runs 50 Hz frames (69,888 T); a 60 Hz TS2068's frame is about 58,800 T, so the interrupt's share was 3.5% there
and is 0.4% now. The canary measurement of the stack covers the Forth tests, not every word with every argument; the
256 B under the guard line is about seven times the deepest use seen. Fuse was not run (the owner's own check of the
white rows was in Fuse).
