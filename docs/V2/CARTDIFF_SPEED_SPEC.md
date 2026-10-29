# cartdiff speed-up: specification (test infrastructure, no ROM change)

Approved by the owner on 2026-10-29 as the step after M6. Evidence tags as in the audit: [M] measured, [S] source,
[E] estimate. Nothing in a ROM image changes; the ledger row is a speed note with 0 bytes.

## 1. Why [M]

`make cartdiff` (`tools/cart_diff.py`) takes about 16 minutes alone (step M6: 15 min 52 s), so agents' timeouts kill
healthy runs and every step pays the wait. One ZEsarUX case profiled (`loop_all_six`, both builds, 186 s wall):

| Where the time goes | s |
|---|---:|
| ZRCP commands, nearly all `send-keys-string 80` (80 ms of host time per key, blocking) | 115.8 |
| fixed `time.sleep` after each line and after ENTER (0.08 s a key + 0.4, then 0.4) | 70.2 |
| stepping the paused emulator (`dbg.run`, boot and idle waits) | 6.4 |
| emulator start, memory and register reads | 0.5 |

So 96% of the time is host-time waiting for typing, not emulation. The 13 cases also run one after another although
the port range 10930-10949 is reserved for cartdiff. TSRun's half takes about 35 s for all cases (`cart_diff.py`
header) and is not changed.

## 2. What changes

1. **Keys in emulated time, on the real matrix.** For each character, the ZEsarUX key events of the ROM's own key
   tables (as `tools/fharness.py` `key_map` / `Console.press_code`) are held with `send-keys-event` while the paused
   machine is stepped (`dbg.run` in instruction chunks) until the key is accepted, then released, and the machine is
   stepped on until the key is up again for the interrupt routine (so a repeated character, as in `ALL`, is a new key).
   No host-time sleeps. The keyboard path stays real in both builds: the interrupt, the matrix scan, debounce and decode
   run as on a typed key, which matters because the cartridge build takes interrupts through the stock ROM.
2. **Acceptance is read from RAM, not from a PC breakpoint.** In the cartridge build the stock ROM occupies the same
   addresses when the DOCK is paged out (it runs during interrupts), so a bare PC breakpoint on a HOME routine can fire
   in the wrong ROM. Acceptance of a character is `EDIT_LEN` growing by one; of ENTER, `EDIT_LEN` going to 0; the
   existing `wait_idle` (PC in `IO_READ_KEY.wait_hit`, `EDIT_LEN` 0) stays the idle test. Key-up is judged by frames:
   step until `FRAMES` has advanced by enough frames for the interrupt routine to see the matrix empty (the count is a
   READING the implementation measures and states).
3. **Cases in parallel.** Cases run in worker processes, one ZEsarUX each on its own port within 10930-10949 and its own
   `TS2068_DEBUG_STATE_DIR` (the current code sets that in `os.environ`, so threads would share it). Output is printed in
   case order; `--jobs N` sets the workers (default 4); `--port` stays the first port.
4. **Unchanged:** the cases, `compare()` and everything it compares, the typing-error check (the edit line is read back
   before ENTER; a mismatch is a harness error, retried on a fresh boot up to 4 attempts), TSRun's path, exit codes,
   `--selftest`, `--json`.

## 3. Oracle (written and run on the old typing before the change)

- A `--dump DIR` option writes, per case, emulator and build, the RAM the comparison reads (`$4000-$FFFF`, as
  `Result.ram`) and the registers it uses (IX, IY). Added and run first with the old typing (`send-keys-string`).
- After the change, the regions `compare()` reads (screen, data and float stacks, dictionary, EXROM-side state) must
  agree with the old dumps byte for byte, case by case and build by build; any difference there fails the oracle.
  Every other differing address is listed and explained (expected: the keyboard and interrupt cells, `FRAMES`, the
  machine stack below SP).
- `make cartdiff`: 26 pairs, 0 FAIL; `--selftest` behaves as before (every mutation reported).

## 4. Budget

0 bytes in every image (`make check`, `make repro`). Wall time [E]: typing in emulated time is a few ZRCP round trips
per key, about 10-20 s a case instead of 30-190 s, then 4 workers: 16 min → 2-3 min.

## 5. Order (one commit each)

1. This spec.
2. Oracle: `--dump`, run on the old typing; the dumps kept as evidence outside the repo, their hashes in
   `docs/V2/evidence/`.
3. The change (keys in emulated time, the worker pool), with the dump comparison, the wall times and the ledger row.

## 6. Limits

ZEsarUX and TSRun only. Typing in emulated time removes host-timing jitter from the ZEsarUX runs; it does not model
a real keyboard's contact bounce (neither did `send-keys-string`).
