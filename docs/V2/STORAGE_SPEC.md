# Tape storage rebuild: specification (audit step S)

Written before the code, as `AY_BEEP_SPEC.md` and `CARTRIDGE_EXROM_SPEC.md` were. Scope: audit section 4.1,
items 1-5, and T14. Every claim is tagged [M] measured in this step, [S] read from source, [L] quoted from 2068-Leap
or 2068-Leap-C, [E] estimate. There is no hardware: every verification limit is an emulator limit (section 10).

## 1. What is wrong today, verified

The storage section is `kernel/storage/storage.asm` (720 B in HOME) plus the words in `core/storage.asm` (252 B)
and `core/loadtext.asm` (169 B): 1,141 B [M, `build/forth_boot.lst` at `ce1579d`].

1. **Failed loads are reported as successes [S].** `STORAGE_RECEIVE_BLOCK` documents carry set as failure
   (`storage.asm:383`). Its exits for a wrong flag byte (`xor l / ret nz`, `:498`), a verify mismatch (`:510`), SPACE
   (`rra / ret nc`, `:564`) and a dropout (`and a` then `inc b / ret z`, `:557-560`) all return carry **clear**; the
   shared `.exit` only does `ld` and `out`, so the clear carry reaches `STORAGE_LOAD`, which takes the block as good
   (`jr c,.data_failed`, `:873`). Only the search timeout and a checksum error set carry. This is the stock routine's
   polarity (carry set = success) with only the final test inverted. Leap V2 had the same bug (its R10.9 D1/D2,
   recorded in the pre-`c2415f8` header).
2. **A short header length corrupts RAM [S].** `STORAGE_LOAD` bounds the header's length from above only
   (`storage.asm:841-851`). `LOAD-LIB` then computes `len - 2` (`core/storage.asm:394-395`): a length of 1 gives
   `$FFFF` and the `LDIR` copies 64 KB over RAM from `$9800`. A length of 0 makes the receiver count DE down from 0
   and read 65,536 bytes.
3. **No identity check [S].** A `SAVE-LIB` image is LATEST plus raw dictionary bytes. The dictionary holds ROM
   addresses, so an image from another build loads and then crashes.
4. **SAVE ignores SPACE [S].** `STORAGE_SAVE` ignores the sender's result and always sends the data block
   (`storage.asm:668-682`), the bug Leap V2 fixed as `67c7137` item 2.1. SPACE during the header search does return
   to the prompt quickly (0.5 s emulated [M, ZEsarUX]), but silently and through item 1's path (the aborted receive
   reads as a success), not by design. With no tape and no SPACE the search gives up after 15 receive attempts of
   about 8.6 s each: 136.8 s emulated [M].
5. **Failures are silent [S].** `LOAD-LIB` and `LOAD-TEXT` return quietly on failure (`core/storage.asm:305-307`
   says "no error reporting yet"). There is no VERIFY.
6. **Provenance [M].** The block I/O is "a direct, verified port of the real ROM's SA-BYTES/LD-BYTES"
   (`storage.asm:10`). `tools/provenance.py` finds 16 runs of 12 bytes or more in `STORAGE_SEND_BLOCK` and 8 in
   `STORAGE_RECEIVE_BLOCK` shared with the stock ROMs, carried as allowed debt owned by this step.
7. **Dead code [S].** `STORAGE_REPORT_PROGRESS` (24 B) calls `STORAGE_PROGRESS_HOOK`, which nothing writes (cold
   start zeroes it). The `STORAGE_REQUEST_TYPE == 4` autostart path (`storage.asm:644-650`) has no caller.
   `include/kernel_api.inc:170-176` still describes a removed two-copy design.
8. **The 8,190-byte limit.** `SAVE-LIB` copies the dictionary to `$D000` first, so it refuses a dictionary over
   8,190 B, although the dictionary may grow to `DICT_RAM_CEILING` (`$F000`, 22,528 B).

## 2. Decisions

**D1. Block I/O: adopt Leap-C's clean-room `tapeblock.asm`, code unchanged** (Leap-C `d31d785`, sha256
`4188efa0...a9`), as Leap V2 did in `c2415f8`. It becomes `kernel/storage/tapeblock.asm`, and `STORAGE_SEND_BLOCK` and
`STORAGE_RECEIVE_BLOCK` are `EQU` aliases of `TAPE_SEND_BLOCK` and `TAPE_RECV_BLOCK`.

Why this layer is adopted rather than rebuilt here:

- **It is already a rebuild of exactly this code against a spec.** Leap-C wrote `TAPE_SIGNAL_SPEC.md` from public
  format descriptions. A fresh author then wrote the code from that spec alone, without the old bodies, the stock ROM
  or a disassembly (`docs/TAPE_CLEANROOM.md`). The result is 316 B against the old 327 B [L], and it accepts 67 of
  71 distorted tapes, where the old stock-derived receiver accepted 54 [L].
- **A rewrite here would not be clean-room.** Everyone working on this tree has read both the old bodies and
  `tapeblock.asm`, so their code could not claim the Stage-B independence that Leap-C's has. An unchanged adoption
  keeps Leap-C's record intact and citable, as `NOTICE` section 3b already does for the glyph builder.
- **The rebuild is the layer above it.** Header logic, image format and words are rebuilt here against this spec
  (sections 4-6), with Leap V2's `kernel/storage/storage.asm` as reference and oracle.

`tools/check_upstream.py` (new, in `make check`) strips comments and blank lines from the adopted file and compares
the remaining code against a hash recorded in `kernel/storage/UPSTREAM.md`. A code edit in Forth then fails the
gate instead of silently forking the clean-room code; header comments may be Forth's own.

**D2. LIB images get their own header type and an identity word.** `SAVE-LIB` writes header type 3 (the standard
"bytes" type); `SAVE-TEXT` keeps type 0. The header's parameter 1 (bytes 13-14) carries `ROM_IDENTITY` and parameter
2 (bytes 15-16) carries LATEST. `LOAD-LIB` and `VERIFY-LIB` refuse a type-3 header whose identity is not this ROM's
before any data byte is received. The identity is enforced in both directions:

- **V1 tapes are rejected (owner decision 6).** V1 `SAVE-LIB` tapes are type 0, so `LOAD-LIB` never matches them,
  at zero code. This is the least-code option the owner allowed.
- **V1 compatibility is not a requirement** (owner, 2026-10-28). Text is not tied to ROM addresses, so text tapes
  carry no identity, and V1 `SAVE-TEXT` tapes happen to load because the TEXT format did not change. Nothing
  guarantees that; a later step may change the TEXT format without keeping it. `tools/tape_gen_forth.py` writes
  the current format and must follow any change.
- **A new LIB tape on a V1 ROM** is a type-3 header there, which the V1 LOAD-LIB also skips.

**D3. `ROM_IDENTITY` is a CRC of the ROM image, patched in after assembly.** `ROM_IDENTITY` is a 2-byte cell
assembled as `$0000`. `tools/rom_identity.py --patch` sets it to `$8000 | (CRC-16 of the 16 KB image with the cell
zeroed)` in the product images (`forth_boot_rom0.bin`, `forth_boot_cart.bin`, before `make_dck.py`). `--verify`
recomputes it, and `make check` runs that.

- **Why a ROM CRC.** Any change to ROM bytes changes the identity, so an image only loads into the exact ROM that
  saved it. A build stamp (the audit's suggestion) would also change on edits that leave the ROM byte-identical, for
  example a Makefile edit. A CRC computed at run time instead would cost about 1.9 s per SAVE and LOAD.
- **Bit 15 is set** so the word is still a legal "no autostart" value for a stock loader.
- **Test ROMs are not patched.** Their identity reads `$0000` and is self-consistent within one ROM.
- **Consequence for users.** Every new ROM release invalidates LIB tapes; source text (`SAVE-TEXT`) is the
  portable format. The docs say so.

**D4. LIB images are saved and loaded in place, with a CRC-16 trailer.**

- **On tape.** The data block is the dictionary bytes `$9800..HERE-1` followed by 2 bytes of CRC-16/CCITT-FALSE
  (polynomial `$1021`, init `$FFFF`, MSB first, no final XOR, stored low byte first) over those bytes. `SAVE-LIB`
  writes the CRC at `HERE` (free dictionary space) and sends `$9800..HERE+1` straight from RAM. LATEST travels in
  the header.
- **The `$D000` copy goes.** That removes the 8,190-byte limit. The new limit is `HERE + 2 <= DICT_RAM_CEILING`,
  else `THROW -8` before anything is sent.
- **On load.** `LOAD-LIB` receives into `$9800` directly. It checks the CRC, then sets `HERE = $9800 + len - 2` and
  `LATEST` from the header.
- **Why the CRC.** The XOR checksum misses an even number of errors in the same bit column; the CRC adds about 40 B
  [E] and about 400 T per byte [E] (2.6 s for a full 22 KB dictionary).
- **Not achieved: `$D000` is not freed for the editor.** `LOAD-TEXT` still needs a buffer to interpret from, and
  `core/recall.asm` keeps the loaded text in `LOADTEXT_BUF` (`$D000`). The audit's hope is met only for LIB images.
- **The "8 bytes below `$9800`" item is moot.** LATEST is in the header, so no in-place header trick is needed.
  Those bytes are the top four data-stack cells (`core/dict.asm:76-77`).

**D5. Errors are THROWn.** Abort by SPACE: `THROW -28` (user interrupt). Any other failure: `THROW -37` (file I/O
exception). Overflow on `SAVE-LIB`: `THROW -8`, as today.

- An uncaught THROW reaches `RUNTIME_ERROR_HOOK` as every other error does; a program can `CATCH` the code.
- **Behaviour change.** Failed loads were silent; they now print the standard error.

**D6. Placement: all HOME.** Every build needs the words, and HOME has 469 B free. The `-DCARTRIDGE` build keeps all
of it; the Blackjack and Gallery demos include no storage, before and after.

## 3. Block layer contract (adopted, `TAPE_SIGNAL_SPEC.md`; summarised [S] from `tapeblock.asm`)

| | `STORAGE_SEND_BLOCK` | `STORAGE_RECEIVE_BLOCK` |
|---|---|---|
| In | A = flag (pilot 8,063 half-pulses if < `$80`, else 3,223); IX = payload; DE = length (0: flag + checksum only) | A = expected flag; carry set = load, clear = verify; IX = destination; DE = length. Z is ignored |
| Out | carry set = sent whole; clear = SPACE stopped it after the current byte (no closing pulse) | carry clear = success, DE = 0. carry set = any failure (no pilot within ~8.6 s, SPACE, wrong flag, mismatch, dropout, checksum); DE = bytes not yet stored, equal to the entry DE iff nothing was stored |
| Interrupts | `di` on entry, left off | `di` on entry, left off |
| Border/MIC | stripes border and MIC; exit restores the border from `PORT_FE_SHADOW` and writes MIC into the shadow | stripes border only; exit writes `PORT_FE_SHADOW` to the port |
| Destroys | AF, AF', BC, DE, HL, IX | AF, AF', BC, DE, HL, IX, `STORAGE_ENTRY_RETRY` |
| Stack | 2 B | 8 B |

Signal: pilot 2,168 T, syncs 667 / 735 T, bits as two equal half-pulses of 855 T (0) or 1,710 T (1), MSB first, XOR
checksum, one closing half-pulse after a whole block. These are the standard figures, so stock tools (Fuse, fuse-utils,
`tools/tape_gen_forth.py`) read and write these tapes (TAPE_SIGNAL_SPEC R12).

The receiver returns while SPACE is still down, so the caller can tell an abort from a failure by re-reading the
keyboard (`ld a,$7F / in a,($FE) / rra`: carry clear = SPACE down).

`STORAGE_TEST_FAKE_SEND` and `STORAGE_TEST_FAKE_RECEIVE` keep working: the aliases point to the test ROM's fakes
instead, as in Leap V2. The fakes in `forth_smoke_p7.asm` and `p52.asm` change to the contract above.

## 4. Tape formats

Header block: flag `$00`, 17-byte payload, as today.

| Offset | Field | TEXT (type 0) | LIB (type 3) |
|---:|---|---|---|
| 0 | type | 0 | 3 |
| 1-10 | name | space-padded, truncated to 10 | same |
| 11-12 | data length | text length | dictionary length + 2 |
| 13-14 | param 1 | `$8000` | `ROM_IDENTITY` |
| 15-16 | param 2 | text length (as today) | LATEST |

TEXT data block: the text bytes, unchanged from V1 (not a requirement, D2). `SAVE-TEXT` writes param 1 = `$8000`
(today it is whatever the header buffer held), matching `tools/tape_gen_forth.py`.

LIB data block: dictionary bytes, then CRC-16 low byte, high byte (D4).

## 5. Header layer (`kernel/storage/storage.asm`, rebuilt)

### `STORAGE_SAVE`

- **In:** HL = name, B = name length, IX = data, DE = data length, C = header type, and for type 3 the two
  parameter words in `STORAGE_PARAM1` / `STORAGE_PARAM2` (or the existing header buffer cells).
- **Steps:**
  1. Build the header.
  2. Send it.
  3. If the header was stopped, return **without sending the data block**.
  4. Otherwise wait 50 frames (1 s at 50 Hz, `HALT`, interrupts on), as a stock tape has between its blocks, and send
     the data block. (Added after the oracle's first run on the new build [M]: with no gap, the data pilot followed the
     header's closing edge by about 2,400 T, and the test decoder, like other tape tools that end a block at a long
     pulse, read the pilot as more header bits. 8 B.)
- **Out:** carry clear = saved; carry set = stopped by SPACE (Leap V2's polarity, `LV storage.asm:88-91`).
- **Interrupts** are enabled on every exit.

### `STORAGE_LOAD`

- **In:** IX = destination, HL = name, B = name length (0 = first header of the type), DE = maximum length, C =
  expected header type, A = mode (0 load, 1 verify), and for type 3 the expected identity.
- **Header search:**
  1. Receive a header (always in load mode) into `STORAGE_HEADER_BUF`.
  2. **Skip and count an attempt** for a failed header, a header of another type, or a name mismatch. Up to 15
     attempts.
  3. **Stop at once** if SPACE is down after the receiver returns (V2's `.space_held`).
  4. Accept a header when:
     - its type matches;
     - its name matches, or B = 0;
     - for type 3, its identity matches;
     - `2 <= len <= max` for type 3, or `len <= max` for type 0, where `len` is the header's data length.
  5. A header that fails any of these is skipped and counted; nothing is written.
  6. **A receive that times out counts as an attempt**, as in V1, so with no tape the search gives up after about
     15 x 8.6 s. (The first draft ended the search at the first timeout. `tools/tapetol.py` refused all 71 cases
     on that build [M]: the tape started more than 8.6 s after ENTER, as it does when a user types the command
     and then presses play. Reverted before commit.)
- **Data block:** receive (mode 0) or verify (mode 1) exactly `len` bytes with flag `$FF` at IX.
- **Out:**
  - carry clear = success, DE = len, header buffer still holding the header (LATEST for the caller).
  - carry set = failure, with:
    - A = 0: nothing at IX was written;
    - A = `$FF`: the destination was written (DE on return ≠ len);
    - B = `$FF` if SPACE was down, else 0.
- **Interrupts** are enabled on every exit.

Removed: `STORAGE_REPORT_PROGRESS`, `STORAGE_PROGRESS_PCT`, `STORAGE_PROGRESS_HOOK`, the type-4 path, the stale
`kernel_api.inc` comments. Kept: `STORAGE_OP_STATE` only if a reader exists (none in ROM code [S]; `tools/z80sim/sim.py`
has a stale constant) — otherwise removed too.

## 6. Words

All six parse their name with one shared helper (today `core/storage.asm` and `core/loadtext.asm` each have their
own copy, and their own name cells at `$8580` and `$8A62`).

| Word | Stack | Behaviour |
|---|---|---|
| `SAVE-LIB` | `( "name" -- )` | `HERE + 2 > DICT_RAM_CEILING`: `THROW -8`. Else CRC over `$9800..HERE-1` into `HERE`, save type 3 with identity and LATEST. SPACE: `THROW -28` |
| `LOAD-LIB` | `( "name" -- )` | Load type 3 into `$9800`, max `DICT_RAM_CEILING - $9800`. CRC check. Success: `HERE`, `LATEST` set. Failure with nothing written: dictionary unchanged, `THROW -37` (or -28). Failure after writing, or CRC mismatch: **the user dictionary is reset to empty** (`LATEST = DICT_LATEST_INIT_RECALL`, `HERE = $9800`, as cold start does), then `THROW -37` (or -28) |
| `VERIFY-LIB` | `( "name" -- )` | CRC of the current dictionary into `HERE`; verify type 3 against `$9800..HERE+1`, requiring identity, length and LATEST to match. Nothing is written. Failure: `THROW -37` (or -28) |
| `SAVE-TEXT` | `( addr len "name" -- )` | As today; SPACE: `THROW -28` |
| `LOAD-TEXT` | `( "name" -- )` | As today (into `LOADTEXT_BUF`, max 8,192, then interpret); failure: `THROW -37` (or -28) instead of silence |
| `VERIFY-TEXT` | `( addr len "name" -- )` | Verify type 0 of exactly `len` bytes against `addr`. Failure: `THROW -37` (or -28) |

`LOAD-LIB` called from a word compiled in the dictionary overwrites the code it will return into; that is true today
and stays true. The docs say to call it from the prompt.

## 7. Byte budget [E]

| Part | Before [M] | After [E] |
|---|---:|---:|
| Block I/O | 327 | 316 [L] |
| Header layer (`STORAGE_SAVE`, `STORAGE_LOAD`, progress) | 393 | 280-330 |
| CRC-16 | 0 | 30-40 |
| Words + headers (4 → 6) | 421 | 330-400 |
| **Total** | **1,141** | **956-1,086 (−185 to −55)** |

**Measured after the step [M]:** block I/O 316 B, header layer 181 B (with the CRC and the 1 s gap), words 484 B
(`core/storage.asm` + `core/tapeword.asm` 322, `core/loadtext.asm` 162): **983 B, −158 B**. HOME 469 → 627 free,
cartridge 478 → 636. Audit section 6.10.

The ledger row records the measured figure. HOME floor: raised to whatever HOME free space is after the step; if
the step costs bytes instead, the floor is lowered with a ledger row, as R1 did for the cartridge.

RAM: the `$8580` and `$8A62` name cells merge (−13 B); two parameter cells may be added (+4 B).

## 8. Oracle (written and run against the old build before the ROM changes)

`tools/tapetest.py`, target `make tapetest`, own ports, ZEsarUX through ts2068-debug, tapes played into EAR with
raw ZRCP `realtape-open`. Tapes are built by a port of Leap-C's `tools/tapes.py`, kept to framing, `.tap` / `.rwa`
writers and the MIC-edge decoder. SAVE output is captured as MIC edges by breakpoint actions on the sender's `out`,
then decoded (Leap-C `lcharness.tape_capture`). TSRun cannot play a tape into a custom loader (Leap-C
`EMULATORS.md:180`), so ZEsarUX is the only emulator for this oracle.

Harness mechanics, measured by a probe on the current build [M, ZEsarUX 13.0]:

- **Inserting a tape resets the machine and starts it playing.** `realtape-open` resets the machine (PC `$0000`,
  dictionary wiped), and the ROM reboots to the prompt in about 0.75 s wall. The tape plays from that instant; ZRCP
  has no pause or rewind, and re-inserting the tape rewinds it (with another reset).
- **The stock autoload does not interfere.** Forth's ROM never reaches it; no disarm step is needed.
- **Every tape starts with a TZX Pause block (ID `$20`) of 20-30 s.** In that lead time the harness types its
  setup, then the command. A plain `.tap` leaves about 5 s of emulated time before the header has gone by, which
  typing at a safe 80 ms per key overruns.
- **Setup typed during the lead.** Cases that need an existing dictionary (5-10, 14) type its definitions during
  the lead, after the reset. The definitions are deterministic, so a re-typed dictionary is byte-identical to the
  one that was saved.
- **SPACE.** Held with `send-keys-event 128 1`; it must be released and the edit line cleared afterwards, or the
  space is typed into the editor.
- **SAVE capture.** A `printe TSTATESP*16+(A&8)` breakpoint action on each `out ($FE),a` of the sender
  (ZEsarUX's stdout captured to a file). The old sender has five such `out`s, the last of them the border restore,
  which is not an edge. `TSTATESP*16` wraps at 2^32, so the decoder unwraps it. A 4-byte `SAVE-TEXT` gave 11,467
  edges in 3.7 s wall.

Each case reports PASS/FAIL per build. The commit that lands the oracle records the old build's results, which must
show the defects of section 1.

| # | Case | New build must | Old build expected |
|---|---|---|---|
| 1 | `LOAD-TEXT` of a `tape_gen_forth.py` tape (DOUBLER) | prints 42 | pass |
| 2 | p53's Blackjack text, 12 round-log values (moves p53 off Fuse) | match | pass |
| 3 | `SAVE-TEXT` captured, decoded: header type 0, param 1 `$8000`, payload; then played back into a fresh machine, `LOAD-TEXT` | identical, runs | header param 1 differs |
| 4 | `SAVE-LIB` captured, decoded: type 3, identity, LATEST, CRC; played back into a fresh machine, `LOAD-LIB`; dictionary bytes, `HERE`, `LATEST` equal, a loaded word runs | pass | fails the format checks; round trip passes |
| 5 | `LOAD-LIB` of a type-3 tape with another identity | `-37`, dictionary byte-identical | n/a (loads as nothing; type 3 skipped) |
| 6 | `LOAD-LIB` of a V1-format (type 0) lib tape | rejected, dictionary unchanged | loads |
| 7 | LIB tape whose data is altered with the XOR checksum fixed up (CRC wrong) | dictionary reset, `-37` | loads the corrupt image |
| 8 | Header length 0 and 1 | rejected, nothing written | RAM corrupted / hang |
| 9 | Data block with the wrong flag byte | `-37`, nothing written | reports success |
| 10 | Dropout in the middle of the data block | dictionary reset, `-37` | reports success |
| 11 | SPACE during the header search | `-28` within a second | returns silently, no error |
| 11a | No tape at all | `-37` after about 2 minutes emulated | silent, after 136.8 s |
| 12 | SPACE during the SAVE header | one block captured, `-28` | header + data captured |
| 13 | Two headers: wrong name, then the right one | the second loads | pass |
| 14 | `VERIFY-LIB` / `VERIFY-TEXT` against a matching tape and a one-byte-different tape | no error / `-37`, memory untouched | n/a |
| 15 | Fake-transport ROMs p7, p52 (in `make test`), updated to the new contract | border 4 | border 4 (old contract) |

`--selftest` mutates one decoded byte, one compared dictionary byte and the expected THROW code and checks that each
is reported.

**Tape tolerance (T14):** `tools/tapetol.py`, target `make tapetol`. A port of Leap-C's 71-case `tapetol.py`
(scale, jitter, skew, short or broken pilot, dropouts), run on ZEsarUX realtape instead of Fuse. It is a report with
one gate: the new receiver must accept every case the old one accepts ("nothing narrower"). Leap-C measured 54 → 67
of 71 on Fuse [L]; the Forth figures are measured here.

Not in `make test`: both are minutes of emulated tape. `make test` keeps p7 and p52.

## 9. Implementation order (one commit each, ledger figures in the last)

1. This spec, and the R1 ledger row's commit hash.
2. Oracle (`tools/tapes.py`, `tools/tapetest.py`, `tools/tapetol.py`, make targets), run against the old build;
   results in `docs/V2/evidence/`.
3. `tapeblock.asm` adopted, aliases, `UPSTREAM.md`, `check_upstream.py`; header layer adapted to the new carry
   contract; provenance debt rows deleted; p7/p52 fakes updated.
4. Header layer rebuilt (section 5): SPACE stop, length bounds, dead code out.
5. Image format (D2-D4): type 3, identity patch tool, CRC, in-place LIB; p7 updated (new overflow limit).
6. VERIFY words, THROW codes, shared name helper.
7. Docs: NOTICE, README, tutorial, `tape_gen_forth.py` / p53 comments, audit ledger.

Each step: `make check`, `make test`, and `make tapetest` from step 3 on.

## 10. Verification limits

- **No hardware.** Every tape result is ZEsarUX's real-tape input sampling the ROM's own receiver, and ZEsarUX's
  `.tap` conversion or a `.rwa` written here generating the signal. ZEsarUX samples a `.rwa` once per scan line
  (about 224 T), so pulse widths carry up to one sample of jitter.
- **SAVE.** SAVE is checked by decoding the ROM's own MIC edges, not by recording an audio file.
- **Cassette decks.** Real cassette decks (wow, flutter, level, azimuth) are outside what this step shows; the
  tolerance sweep approximates some of them.
- **Fuse.** It remains available for a manual cross-check (`tools/run_realtape_test.sh`), not as a gate.
