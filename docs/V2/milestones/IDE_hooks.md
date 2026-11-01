# IDE hooks — the Leap IDE's questions answered, the labels and the error cell it drives the prompt by: milestone report

**Date:** 2026-11-01. **Status: complete.** Branch `v2/step-ide-hooks` from master `7b39732` (PR #15, step BREAK and
timing, merged). The Leap IDE (`~/Projects/Leap-IDE`) asked seven questions before its Forth work
(`docs/requests/LEAP_FORTH_QUESTIONS.md` there). The answers are `LEAP_FORTH_ANSWERS.md` beside them; the owner
approved the recommendations (2026-11-01), and this step makes the ROM side of them.

## 1. What the questions found

- The IDE planned to interpret sent text from the line store. That is not safe: `LOAD-TEXT` loads into the store
  (over the text being run), `EDIT`'s view moves its lines, and the four command words trim "the last line" off it.
  One line at a time through `EDIT_BUF`, entering the console's own ENTER path, needs only a label.
- Telling the prompt's key wait from a program's needs no cell: `IO_READ_KEY` pushes nothing, so the word at SP is the
  caller's return address.
- After an error only `INTERP_ERROR_FLAG` was left: `RUNTIME_ERROR_HOOK` cleared `THROW_CODE`, an unknown word set no
  code, `ABORT` and `QUIT` passed through no common routine.
- Reading the error paths: `REPORT_INTERP_ERROR` reloaded SP without zeroing `CATCH_DEPTH` (a defect, section 3).

## 2. What changed

- **Labels (0 B):** `EDITOR_LOOP_LIVE.key_ret` (the prompt's key wait returns there), `EDITOR_LOOP_LIVE.enter` (the
  console's ENTER path: `EDIT_BUF` / `EDIT_LEN` hold the line), `INTERPRET_NESTED.token` (a token read: `WORD_BUF`,
  `SRC_PTR` past it and its delimiter, `HERE` where its code goes while `STATE` is 1).
- **`LAST_ERROR`** (2 B of cells): the code the last console line ended with. Every error now ends in
  `REPORT_INTERP_ERROR` with its code in HL, which stores it; the console sets it to 0 after a line that ends in `OK`.
  ANS numbers: -13 an unknown word, the THROW's code, -4 / -3 for `STACK?` (`STACK_CHECK` sets `THROW_CODE` for an
  underflow or an overflow, and `RUNTIME_ERROR_HOOK` prints `STACK?` for both, so `-3 THROW` and `-4 THROW` do too),
  -1 `ABORT`, -56 `QUIT`. `THROW_CODE` is no longer cleared (every jump to the hook sets it).
- **ABORT and QUIT** end in `REPORT_INTERP_ERROR` (-22 B): it does what their own tails did, and now also zeroes
  `CATCH_DEPTH`.
- **Docs:** `STORAGE_SPEC.md` section 6; the tutorial (`-3` / `-4 THROW` print `STACK?`); ROADMAP (this step; next
  the cartridge build, then the manual, then Blackjack, by the owner's order); HANDOFF (the names the IDE depends on).

## 3. Defects found and fixed

| Defect | Found by | Fix | Bytes |
|---|---|---|---:|
| An error that is not a THROW (an unknown word, `STACK?`, a compile-only word at the prompt) inside `CATCH` reloaded SP but left `CATCH_DEPTH` counting the dropped frame: the next uncaught THROW went back into it (`' IF CATCH`, then `-1 THROW` printed `THROW  ?`) | reading the error paths for Q2 | `REPORT_INTERP_ERROR` zeroes `CATCH_DEPTH` | +3 |
| `STORAGE_SPEC.md` section 6 gave `SAVE-TEXT` and `VERIFY-TEXT` as `( addr len "name" -- )` (they take the line store since step Console and editor) | the IDE (Q6.5) | the table | |

## 4. Tests

Each fails on the old build (master `7b39732`, a worktree, with master's own tools and the new test files):

| Test | On the old build |
|---|---|
| boot suite check p `host line`: at the prompt's key wait (`key_ret` at SP) `1 2 + .` written into `EDIT_BUF` and run from `.enter` prints `3 OK`, is in the store, `LAST_ERROR` 0; `: SQ DUP * ;` records (`DUP` 9 code+0, `*` 11 +3, `;` 12 +6) at `.token`; `NOSUCHWORD 5 .` gives -13 and `SRC_PTR` 11; `KEY DROP` waits with another return address, then a key brings back the prompt. `Console.host_line` is the IDE's protocol in the harness | no labels: fail |
| `tests/core/lasterror.fs`: `LAST_ERROR` after OK (0), an unknown word (-13), `-42 THROW`, `7 THROW`, `DROP` and `FDROP` on empty stacks (-4), 1,100 pushes (-3), `-3` / `-4 THROW` print `STACK?`, `IF` at the prompt (-13), `ABORT` (-1), `QUIT` (-56), an error in a definition | no cell: fail |
| `tests/io/break.fs`: `LAST_ERROR` -28 after BREAK | no cell: fail |
| `tests/core/catch.fs`: `' IF CATCH` leaves `CATCH_DEPTH` 0, and `-1 THROW` after it prints `ERROR -1` | `CATCH_DEPTH` 1: fail |

The harness's `Console.in_editor` now tests `EDITOR_LOOP_LIVE.key_ret` (the same address as `.keyloop` + 3).

### Results (`make test`, 2026-11-01, 530 s)

| Suite | Result |
|---|---|
| boot | 14/14 |
| forth | 60/60 |
| editor | 30/30 (old 19, new 11) |
| float | 66/66 |
| shape | 48/48 |
| bench | 6/6 |
| poweron | 7/7 |
| tape | 19/19 |

`make check` and `make repro` pass.

## 5. Sizes

| Image | Before | After |
|---|---:|---:|
| HOME free | 1,939 B | 1,938 B |
| EXROM free | 3,208 B | 3,208 B |

Ledger (`budget.toml`): interp −11 (ABORT and QUIT −22, `STACK_CHECK`'s codes +11), boot +7 (`LAST_ERROR` stored,
`CATCH_DEPTH` zeroed, the hook's codes; `THROW_CODE` no longer cleared), console +5 (`LAST_ERROR` 0 after `OK`).
RAM: 2 bytes of cells, 110 B of room left.

## 6. Emulator limits

The protocol is tested in ZEsarUX through ZRCP (registers set at a breakpoint), the way the IDE drives TSRun; TSRun
itself was not run. Fuse was not run.
