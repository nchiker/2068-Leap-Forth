# Float rebuild: specification (step F, with O10 and T13)

Step F of the audit (`FORTH_V2_REUSE_AUDIT.md` section 4.2, items 1-6), on branch `v2/step-f-float`. Owner decisions
behind it: decision 3 (2026-10-28: the 5-byte Sinclair format through Leap-C's `fpcore`, with its bit-exact
`tools/fpmodel.py` oracle; `bench_float` re-baselined only with the owner's OK if slower; SIN/COS/TAN to the EXROM if
HOME is short; the provenance scan in this step) and decision 4 (Leap V2's MIT position on `fpcore` goes in NOTICE if
the 12-byte scan is clean). O10 (integer multiply and divide) was added to F by the owner on 2026-10-28. Evidence tags
as in the audit: [M] measured, [S] source, [E] estimate, [L] from another project's records.

**The owner's decisions are in section 15** (decided 2026-10-29).

## 1. Why

Today's floats [S, `core/float.asm` header]: a 3-byte cell (16-bit signed mantissa, signed 8-bit exponent, value
m × 2^e, no normalisation), about 4.5 digits, truncating arithmetic, no overflow or division-by-zero error (`1.0 0.0
F/` returns a number), `F.` prints 4 decimals truncated toward zero, SIN/COS from a 17-entry table (worst error about
1e-3), FSQRT of a negative number returns 0. It was written as a "first slice", and its own header says it is not a
considered numeric design. The audit's verdict is to rebuild on Leap-C's `fpcore`: 5-byte Sinclair floats, about 9.6
digits, rounding to nearest, an error on overflow and on division by zero, and a model the ROM can be checked against
byte for byte.

## 2. References studied (before this design)

| Reference | What it is | What F takes |
|---|---|---|
| Leap-C `src/runtime/fpcore.asm` (`b918527`, 1,461 B [M] in `leapc_exrom.lst`) | The re-engineered V2 calculator: unpacked working form `[sign][exp][m0..m3][guard]` (40-bit mantissa), `FUNPK`/`FPACK` (round to nearest on the guard's top bit), `FNORM`, `FADD` (the larger magnitude first, alignment by bit shifts, 40-bit sum), `FMUL` (32 × 32 shift-and-add, the top 40 bits), `FDIV` (40 quotient bits, restoring, with a 33rd remainder bit), `FDONE` (one normalising step, the range), `FCMP`, `FRI`/`TOI`, `XF_FTOA` (128.32 fixed point, every integer digit, the decimals rounded half up), `XF_ATOF` (32-bit digit accumulator, a decimal exponent, scaling by exact powers 10^1..10^13) | The format, the unpacked form, every algorithm, so that `fpmodel.py` stays the oracle unchanged. Not taken: the `XF_OP` dispatch and its table, `FRU`, INC/DEC/PINC/PDEC and `F_OLD` (C operators), the `f F l L` suffixes, `PRINT_BUF`, `F_ERR`'s compile/run split |
| Leap-C `tools/fpmodel.py` (319 lines) | Bit-exact Python model of the above: `unpack`, `pack`, `norm`, `add`, `mul`, `div`, `cmp`, `fri`, `toi`, `neg`, `atof`, `ftoa`, `value`, `encode` | Vendored unchanged as `tools/fpmodel.py` (upstream commit recorded, checked like `tapeblock.asm` by `tools/check_upstream.py`) |
| Leap-C `tools/floattest.py` (227 lines) | Calls every operation through the ROM (`lcharness.Machine.call`) on operands chosen to cover the format (zeros, powers of two, all-ones mantissas, both signs, exponents at the range's ends, random patterns, near-equal pairs for cancellation, integer boundaries); checks the model against Python floats within 2^-30; error cases through a stop frame | T13's operand generators (`interesting`, `near`), its case mix and its error-frame method, rebuilt on `tools/fharness.py` and on Forth's words (section 13) |
| Leap V2 SQR (`rom/exrom_v2_vm_core.asm` `BUILTIN_FN_SQR`, `54cd877`) | Newton's method, 5 steps of x = (x + n/x)/2, the halving done by decrementing the exponent byte (exact, about 22 kT less than a divide); first guess 2^⌊(e+2)/2⌋ from the exponent; negative: an error; 0: 0 | The algorithm as is (section 8.1) |
| Leap V2 SIN/COS/TAN (`rom/exrom_v2_float_fn.asm`, 5.9-5.10) | Degrees: exact integer reduction mod 360 to [0°, 90°], then x = a·π/180 and the odd minimax series x + x³(c3 + c5x² + c7x⁴ + c9x⁶ + c11x⁸), coefficients fitted for \|x\| ≤ 91° (relative error 4.8e-11), within about 2 ulp; COS(x) = SIN(x + 90); TAN = SIN/COS with a division-by-zero guard; \|x\| ≥ 32768° is error 15 | The series and its 5 coefficients and π/180 (`SIN_COEFFS`, 30 B) as is. The reduction is rebuilt for radians (section 8.2): Forth's SIN/COS take radians, and RAD/DEG stay (audit 4.2 item 3) |
| Leap-C `src/runtime/helpers.asm` `RT_MUL`, `RT_UMUL`, `RT_DIVS`, `RT_MODS`, `RT_SDIV`, `RT_UDIV` (84 B [M] in `leapc_home.lst`) | Register-only 16-bit multiply (16 steps from the top bit) and restoring divide (16 steps, the remainder in DE); signed wrappers: quotient truncated toward 0, remainder with the dividend's sign, a divisor of 0 gives 0 | O10 (section 11): the same contract Forth's `MATH_*` routines have today [S], so `*`, `/`, `MOD` keep their results |
| Leap-C `src/runtime/library.asm` `LIB_RAND` | 16-bit xorshift (7, 9, 8), period 65535 | The generator behind `RND` (section 11.2, F8) |
| Today's `core/float.asm`, `floatmul.asm`, `floatdiv.asm`, `floatconv.asm`, `floatprint.asm`, `floatsqrt.asm`, `floattrig.asm`, `decimal.asm`, `core/beep.asm`, `core/interp.asm` (`NUMBER`, `.gotfloat`, `STACK_CHECK`), `kernel/math/math.asm` | Section 3 | What must keep working (section 10) |

## 3. Today [M] (re-measured on `b4a05b0`, `build/forth_boot.lst`)

| File | HOME B | Contents |
|---|---:|---|
| `core/floattrig.asm` | 508 | `PI`, `SIN`, `COS`, `RAD`, `DEG`, the table |
| `core/float.asm` | 309 | `FPUSH`, `FPOP`, `F_SHRA`, `F_ALIGN`, `F+`, `F-` |
| `core/floatsqrt.asm` | 285 | `FSQRT` (a 32-bit integer square root) |
| `core/floatmul.asm` | 256 | `F*`, `F_UMUL32`, `F_NORMALIZE32` |
| `core/decimal.asm` | 248 | `CHECK_FOR_DOT`, `DECIMAL_PARSE_AND_PUSH` 184, `DOFLIT` 15, `COMPILE_FLOAT_LITERAL` 27 |
| `core/floatprint.asm` | 214 | `F.` |
| `core/floatdiv.asm` | 198 | `F/`, `F_UDIV32BY16` |
| `core/floatconv.asm` | 82 | `S>F`, `F>S`, `FROUND` |
| **Float total** | **2,100** | 14 words (audit section 4.2 said 2,129; O13's `rst` calls and M6 moved it) |
| `kernel/math/math.asm` | 411 | of which O10's five routines 178: `MATH_UMUL16` 22, `MATH_UDIV16` 74, `MATH_MULTIPLY16` 28, `MATH_DIVIDE16` 27, `MATH_MOD16` 27 (the audit's "412 B" was the whole file) |

Also float-dependent outside these files: `BEEP` (`core/beep.asm`: `FLOAT_TO_INT16` and `W_BEEP`'s float part push
120 and call `F*`), `NUMBER`'s dot check and `INTERPRET_RUN`'s `.gotfloat` (`core/interp.asm`), `STACK_CHECK`'s IY
bounds, `THROW`/`CATCH` (save and restore IY). Section 10 lists the tests and documents.

Free space at the start: HOME 1,629 B, cartridge 1,629, EXROM 4,247 [M].

Baseline runs on `b4a05b0` (2026-10-29) [M]: `make test` 66/0/1, POWERON 7/7; `make edtest` 30/30; `make harness` 0
failed; `make cartdiff` 26/26 (1 min 16 s); `make check` passes. `make bench` (T-states, region): float 174,699,150;
pixel 54,339,227; sieve 143,773,830; string 1,969,307.

## 4. Format and float stack

- **Cell:** the Sinclair 5-byte float, always in the normalised form (Leap-C writes no small-integer form): byte 0
  the exponent e (0 means the value 0), byte 1 the sign in bit 7 and mantissa bits 30-24, bytes 2-4 mantissa bits
  23-0; value 0.1m × 2^(e − 128) with the leading 1 implicit. Range about ±1.7e38, smallest about 2.9e-39; 32
  mantissa bits, about 9.6 digits. The cell in memory is byte-identical to `fpmodel.py`'s 5 bytes.
- **Float stack:** IY as today, growing down from `FSTACK_TOP` `$9000`; the top of stack is `(iy+0)..(iy+4)`. The
  region stays `$8C00-$8FFF` (1 KB): 204 cells (today 341). `FSTACK_LIMIT` becomes `$8C04`, the lowest legal cell
  (`$9000 − 204 × 5`), so `STACK_CHECK`'s existing IY test (between words at the prompt, `STACK?`) works unchanged
  in form. A 205th push writes 5 bytes at `$8BFF-$8C03` before the check sees it, so `$8BFF` (the high byte of
  `STORE_LAST_LINE`, `$8BFE`) is the one cell outside the region an overflow can touch; today's 342nd push has the same
  reach (`$8BFD-$8BFF`). Unchanged class; no new check (the words do not test depth, as today).
- **Compiled literals:** `DOFLIT` followed by the 5 bytes inline (today 3). LIB images hold compiled code, but a LIB's
  identity is the ROM's CRC (STORAGE_SPEC D3), so no saved LIB from an older ROM loads anyway; SAVE-TEXT text is
  unaffected.
- **No IEEE features:** no infinities, NaN or negative zero (a zero always has sign 0, as `fpmodel.pack`).

## 5. Engine (`core/fpcore.asm`, HOME)

One new file holding the rebuilt `fpcore`, assembled into HOME (section 14: it fits). Called directly (no RST $28
dispatcher, no `XF_OP` table). Unchanged from Leap-C, so that `fpmodel.py` is the oracle unmodified:

- the working form and RAM layout `FX`, `FY` (7 B each: sign, exponent, m0-m3, guard), `FQ` (5 B), `FDEXP`/`FFLAGS`
  (ATOF), `FMT` (20 B, FTOA), as one 40-byte block `FP_RAM` (section 9);
- `FUNPK`, `FPACK` (round to nearest on the guard's top bit; a carry out of the mantissa raises the exponent; above
  255: error), `FNORM`, `FADD` (with `FSWAP`), `FDONE`, `FSIGN`, `FCMP`, `FFROM` (16-bit integer in), `TOI` (out:
  truncated toward 0, the low 16 bits), `NEG`, the byte helpers `FSHL`, `FSHR`, `FADDN`, `FSUBN`, `FZERO`, `FMUL10`,
  `FDIV10`, the table `POW10` (10^1..10^13, exact);
- `FTOA` and `ATOF` (sections 7 and 6), adapted at their ends only: FTOA emits its characters instead of filling
  `PRINT_BUF` (the integer digits, produced right to left, are pushed on the machine stack and popped in order: at
  most 39 digits, 78 B of stack); ATOF reads a counted token instead of a NUL-ended C string.

What changes around it:

- **The accumulator is the float stack's top.** Leap-C's `F_ACC` is a fixed cell; here `FPACK` writes to `(iy+0)`. A
  binary word unpacks `(iy+5)` (the left operand) to `FX` and `(iy+0)` (the right) to `FY`, drops one cell
  (`iy += 5`) and packs into the new top. No `F_ACC`, `F_OLD`, `TOK_BUF` or `PRINT_BUF`.
- **Errors** (section 8.4) leave through one entry, `F_THROW`: Leap-C's `F_ERR` with `E_RANGE` becomes `THROW` with
  −43, and the division by zero in `FDIV` gets its own entry with −42.
- **Multiply and divide kernels (F1).** `fpcore`'s `FMUL` and `FDIV` run their 32 and 40 steps
  through the byte-loop helpers (`FSHR`, `FADDN`, `FSUBN`, `FSHL` on RAM): about 19 kT per F* and 34 kT per F/ [E,
  counted from the instructions]. `bench_float` does 27 F* and 29 F/ per repetition (582 kT per repetition today, all
  words included [M]), so with them the benchmark would take about 3 times as long [E]. Alternative: the same two
  algorithms with the mantissas, the partial product or remainder and the counter in registers (the main and alternate
  sets). They compute the same numbers: `fpmodel.mul` is ⌊x32·y32 / 2^24⌋ exactly (the additions never reach the bits
  shifted out), and `fpmodel.div` is the exact restoring quotient, so any implementation of those two functions is
  bit-exact with the model, and T13 checks it. About 3.5 kT per F* and 4.5 kT per F/ [E], within ±30 B of `fpcore`'s
  `FMUL` + `FDIV` (160 B) [E]. Precondition: neither interrupt routine touches the alternate registers. Forth's
  own does not [S: no `exx` in kernel/ or core/]. The stock ROM's routine in the cartridge build is checked in
  ZEsarUX before the code is written (alternate registers set to a pattern, frames run, read back); if it does touch
  them, the kernels run with interrupts held off for at most about 5 kT (+4 B). **Decided: the register kernels.**
- **Alignment in FADD** shifts whole bytes first, then bits (the same ⌊y / 2^d⌋, so the same results): an exponent
  difference of 30 costs about 6 kT with bit shifts only [E]; whole bytes first, under 1.5 kT, for about +15 B [E].
  Done if the byte budget allows (it does on the section 14 estimate).

## 6. Number parsing (one parser for integers and floats)

`NUMBER` and today's `DECIMAL_PARSE_AND_PUSH` become one routine built on `ATOF`'s digit loop (audit 4.2 item 4):

1. An optional leading `-` (as today). Then `ATOF`'s grammar: digits, an optional `.` and digits, an optional exponent
   `E`/`e` with an optional sign and digits. At least one digit; the whole token must be consumed. `+` is not a sign,
   and there is no suffix (Leap-C's `f F l L` go).
2. **A float** when the token has a `.` or an exponent (F5: `1E3`, `2.5e-4`, `-1.5E+3`, `3.` and `.5` are floats).
   The value is ATOF's (rounded to nearest at each step, as `fpmodel.atof`), negated by the sign, pushed on the float
   stack (or compiled after `DOFLIT`), flag 2 as today.
3. **An integer** otherwise, if its value is in −32768..65535 (F5b): the 16-bit pattern (`40000` is −25536 as a
   signed number, as today, so addresses up to 65535 can be typed), flag 1. Outside that range (`100000`, `-40000`)
   THROW −43: today such a token silently wraps (`100000` gives 34464).
4. Not a number (no digit, a second `.`, letters, `E` without digits): flag 0, so the interpreter reports the unknown
   word as today. A float beyond the range (`1E39`): THROW −43. Below the range: 0 (as `fpmodel`).

This replaces `CHECK_FOR_DOT`, `DECIMAL_PARSE_AND_PUSH` and `NUMBER`'s own digit loop (about 300 B together [M:
decimal.asm 248, NUMBER's loop about 60 S]).

## 7. Output: `F.`, `FS.` and `PLACES`

- **`PLACES ( n -- )`** sets the number of decimals both words print, 0-9 (a RAM byte, 4 after the cold start);
  another n: THROW −43 (F4).
- **`F.`** prints `FTOA` with `PLACES` decimals rounded half up (as `fpmodel.ftoa`): every integer digit, then `.` and
  the decimals (none and no point when `PLACES` is 0), `-` for a negative value, then a space, as today. One change
  from the model: when every printed digit is 0, no `-` (`-0.00001 F.` prints `0.0000`, not C's `-0.0000`). With 4
  decimals, as today: `2.0 FSQRT F.` prints `1.4142` where today `1.4141`, and `1.0 SIN F.` `0.8415` where today
  `0.8408` (rounding and precision).
- **`FS.`** prints scientific notation (the ANS word): `[-]d.ddddEn` with `PLACES` decimals, the exponent n in decimal
  with a `-` when negative and no `+`, then a space: `1E-6 FS.` prints `1.0000E-6`, `-12345.678 FS.` `-1.2346E4`,
  `0.0 FS.` `0.0000E0`. Algorithm (all `fpcore` operations, so `tools/fpforth.py` models it bit for bit):
  1. a = \|x\| (0: print `0`, the decimals, `E0`).
  2. n = ⌊(e − 129) × 77 / 256⌋ from the exponent byte e (77/256 approximates log10 2; n is the decimal exponent or
     one less or more).
  3. a = a / 10^n: for n > 0 divide, for n < 0 multiply, by `POW10` entries in steps of at most 13 (as ATOF).
  4. If a ≥ 10: a = a / 10, n + 1; else if a < 1: a = a × 10, n − 1 (one step suffices: n is never off by two).
  5. The digits are FTOA(a, `PLACES`); if they read `10.`… (rounding carried), print `1.` and the zeros, n + 1.
  Scaling costs at most 3 roundings, so the printed digits can differ from the exact decimal in the last of 9 or so
  places; with 4 decimals never visibly [checked by T13 against Python's `%.4E`].
- Very large values print all their integer digits with `F.` (up to 39); `FS.` is the way to read them.

## 8. Words

### 8.1 Today's 14 words on the new format

| Word | Today | After F |
|---|---|---|
| `F+` `F-` `F*` `F/` | truncating, no errors | `fpmodel.add/mul/div`; overflow THROW −43, division by 0 THROW −42; underflow gives 0 |
| `F.` | 4 decimals truncated | section 7 |
| `S>F` | exact | exact (`FFROM`, signed) |
| `F>S` | floor (`-2.5 F>S` gives −3), high bits lost silently | truncation toward 0 (`fpmodel.toi`, ANS `F>D`'s rule; `-2.5 F>S` gives −2; `FLOOR` gives the floor); the integer part must be in −32768..65535 (the range a literal may have), else THROW −43 (F3) |
| `FROUND` | half up (−2.5 gives −2) | half away from 0 (−2.5 gives −3, 2.5 gives 3) (F3) |
| `FSQRT` | 32-bit integer root; negative gives 0 | Leap V2's Newton (`54cd877`): 0 gives 0, negative THROW −46; first guess: exponent byte 128 + ⌊(e − 126) / 2⌋ (arithmetic shift), mantissa bytes 0 (0.5); 5 steps of x = x + n/x with the exponent byte then decremented (the halving). Within 2 ulp of `math.sqrt` [checked by T13] |
| `PI` | 3-byte constant | the 5-byte π (`$82 $49 $0F $DA $A2`) |
| `SIN` `COS` | table, ~1e-3 | section 8.2 |
| `RAD` `DEG` | × 0.0174532 / × 57.294922 | × π/180 (Leap V2's `SIN_COEFFS` entry `$7B $0E $FA $35 $13`) / × 180/π (`fpmodel.encode(180/π)`) |

`FROUND` and `FLOOR` work on the unpacked mantissa, not by adding ½ (which `FPACK` could round up across an integer):
for \|x\| < 1, `FROUND` gives ±1 when \|x\| ≥ ½ else 0, `FLOOR` −1 for a negative x else 0; for \|x\| ≥ 2^31 the value
is already an integer; otherwise the fraction bits are cleared and the magnitude incremented by 1 when (`FROUND`) the
first cleared bit was set, or (`FLOOR`) x is negative and any cleared bit was set; then normalised and packed.

### 8.2 SIN, COS, TAN (radians)

Steps (each an `fpcore` operation: `tools/fpforth.py` follows the same steps, so the ROM is checked bit for bit):

1. t = x × `INV_PI` (1/π, `fpmodel.encode(1/π)`).
2. k = t rounded half away from 0 (as `FROUND`); \|t\| ≥ 32767.5 (\|x\| above about 102,940): THROW −43 (F6: no
   digit of a sine is right at that size in a 32-bit mantissa).
3. kf = k as a float (`FFROM`); r = (x − kf × P1) − kf × P2 (Cody-Waite), with P1 = π rounded to 17 significant bits
   (so kf × P1, at most 15 + 17 bits, is exact, and x − kf × P1 is exact by Sterbenz's lemma) and P2 = π − P1 to 32
   bits (`fpmodel.encode`). \|r\| ≤ π/2 plus rounding, inside the series' fitted range (\|r\| ≤ 1.588, 91°).
4. Leap V2's series on r, unchanged: x² = r × r, x³ = r × x², P = c3 + x²(c5 + x²(c7 + x²(c9 + x² c11))), s = r +
   x³ × P, coefficients `SIN_COEFFS` (5 × 5 B, Leap V2 5.10).
5. k odd: s = −s.

**COS** x = SIN(x + π/2) (`HALF_PI` constant; as today and as Leap V2's COS = SIN(x + 90)). **TAN** x = SIN x / COS x;
a cosine of exactly 0: THROW −42. Accuracy [E, checked by T13 against `math`]: about 2 ulp for \|x\| ≤ π/2, absolute
error under 2^-30 for \|x\| ≤ 100, growing to about 2^-29 at the range's end (P2's rounding, about \|k\| × 2^-49 plus
the series). 9 multiplies and 6 additions per SIN.

**Placement:** HOME (section 14 shows room). The EXROM fallback, used only if a measured step leaves HOME below its
floor plus the 200 B target: SQR, SIN, COS and TAN move to the EXROM behind service slot 7 (free since step E) with a
sub-function byte, calling HOME's engine through new veneers in `GRAPHICS_HOME_TABLE` (`FADD`, `FMUL`, `FDIV`, `FUNPK`,
`FPACK`, `FCMP`, `TOI`, `FFROM`: 8 × 3 B), the RAM cells they use copied into `include/exrom_home_ram.inc` and checked
by `tools/audit_layout.py`, and each word in HOME a 4-byte call through `EXROM_SERVICE`. Saves about −420 + 60 = −360
B of HOME [E], costs about 10 kT per call for the paging (both builds; the cartridge build pages DOCK chunk 5).

### 8.3 New words (F2)

Each costs its header (link 2, length 1, the name) plus code; estimates [E]. Flags are −1/0, as `<`.

| Word | Stack | B [E] | Note |
|---|---|---:|---|
| `FDUP` | ( r -- r r ) | 14 | audit item 5 |
| `FDROP` | ( r -- ) | 11 | |
| `FSWAP` | ( r1 r2 -- r2 r1 ) | 18 | |
| `FOVER` | ( r1 r2 -- r1 r2 r1 ) | 15 | shares `FDUP`'s copy |
| `FDEPTH` | ( -- n ) | 14 | floats on the float stack |
| `FNEGATE` | ( r -- −r ) | 14 | audit item 5 |
| `FABS` | ( r -- \|r\| ) | 12 | |
| `F<` `F>` `F=` | ( r1 r2 -- flag ) | 34 | audit item 5 (`F<`, `F=`); one `FCMP` path |
| `F0<` `F0=` | ( r -- flag ) | 20 | the sign bit / the exponent byte |
| `FMIN` `FMAX` | ( r1 r2 -- r3 ) | 30 | |
| `FLOOR` | ( r1 -- r2 ) | 25 | shares `FROUND`'s code (section 8.1) |
| `F@` `F!` | ( addr -- r ) ( r addr -- ) | 30 | audit item 5; 5-byte moves |
| `FVARIABLE` | ( "name" -- ) | 15 | audit item 5; `VARIABLE`'s header builder with 5 bytes |
| `FCONSTANT` | ( r "name" -- ) | 25 | a header and `DOFLIT` + 5 bytes |
| `TAN` | ( r1 -- r2 ) | 20 | section 8.2 |
| `PLACES` | ( n -- ) | 20 | section 7 |
| `FS.` | ( r -- ) | 140 | section 7 |

About 457 B together. With today's 14 words: 34 float words.

### 8.4 Errors and their messages (F7)

| Code | ANS meaning | Raised by |
|---:|---|---|
| −42 | floating-point divide by zero | `F/`, `TAN` (a zero cosine) |
| −43 | floating-point result out of range | `F+ F- F* F/` overflow, `FPACK`'s rounding carry, a float literal beyond the range, an integer literal outside −32768..65535, `F>S` outside it, SIN/COS/TAN beyond about ±102,940, `PLACES` outside 0-9 |
| −46 | floating-point invalid argument | `FSQRT` of a negative number |

`CATCH` already saves and restores IY, so a caught error leaves the float stack as it was at `CATCH`. Uncaught, every
THROW today ends in `RUNTIME_ERROR_HOOK`, which prints `STACK?` whatever the code. After F, an uncaught THROW prints a
message for each code the ROM raises itself, and `ERROR n` for any other (a user's `5 THROW` prints `ERROR 5`):

| Code | Message | Raised by (today's code) |
|---:|---|---|
| −8 | `DICTIONARY FULL` | `DICT_ROOM` (`core/interp.asm`) |
| −13 | `UNDEFINED WORD` | `'` (`core/tick.asm`) |
| −28 | `BREAK` | tape words (`core/tapeword.asm`) |
| −37 | `TAPE ERROR` | tape words |
| −42 | `DIVISION BY ZERO` | section 8.4 |
| −43 | `OUT OF RANGE` | section 8.4 |
| −46 | `INVALID ARGUMENT` | `FSQRT` |

`STACK_CHECK`'s violation (a stack under- or overflow found between words, not a THROW) keeps printing `STACK?`. The
`LINE n` prefix (`EDIT`'s commit) and the reset of both stacks are unchanged. About 115 B [E] (the texts 88, the code
table and lookup 27).

## 9. RAM

From a map of `$8000-$97FF` built from `build/forth_boot.sym` and the defining files (2026-10-29; the gaps re-checked:
no symbol of the build lies in them) [M]. Every gap is inside the cold start's zero fill (`$8000-$F227`).

| Range | B | Use after F |
|---|---:|---|
| `$8594-$85BE` | 43 | `FP_RAM`: `FX` 7, `FY` 7, `FQ` 5, `FDEXP` 2, `FFLAGS` 1, `FMT` 20 (from `FP_RAM + 20`, overlapping `FDEXP`/`FFLAGS` as in Leap-C: never live together), 1 spare; `fpcore`'s `ASSERT` on the layout kept |
| `$85BF-$85CB` | 13 | `FSQ_N` 5 (FSQRT's argument), `FTRIG_R2` 5 (r² in the series), `FTRIG_K` 2 (k, its parity is the sign), `F_PLACES` 1 (F4 b) |
| `$85CC-$879F` | 468 | still free |
| `$87A0-$87BE`, `$8840-$8855` | 31 + 22 | today's float cells: free after F |
| `$80DB-$80E0` | 6 | `DIV_DIVIDEND`, `DIV_QUOT`, `DIV_COUNTER`, `MATH_SIGN`: free after O10 |

The 524-byte gap `$8594-$879F` (between `STORAGE_NAME_BUF` and today's `F_M1`) is the largest; the others (`$8316-$84FF`
490 B, `$8B3A-$8BFD` 196 B, `$8544-$8588` 69 B, `$87FF-$883F` 65 B) stay untouched. The float stack stays
`$8C00-$8FFF` (section 4).

Two findings of the map, outside F (not changed here; recorded for the owner, HANDOFF open points):
- `CATCH_STACK` (`$8916`, 8 frames × 6 B, to `$8945`) overlaps `SPACES_COUNT` (`$8940`) and the first 4 bytes of
  `PRINT_LINE_BUF` (`$8942`): the 8th nested `CATCH` frame and `SPACES`/`LPRINT` share bytes [S].
- `LATEST` (`$9002`) and `HERE` (`$9004`) lie inside the data stack's legal range (`DSTACK_LIMIT` `$9000`,
  `DSTACK_TOP` `$9800`): a data stack about 1,020 cells deep overwrites them before `STACK_CHECK` objects
  (`core/dict.asm` says the stack is 1,024 bytes, which would put the floor at `$9400`) [S].

## 10. What else changes

Inventory of everything outside the float files that depends on floats (2026-10-29, checked by grep; the claims
used below re-checked by hand) [S].

### 10.1 Code

- **`core/beep.asm`:** section 12 (`ld a, (iy+1)` read as the sign; `FLOAT_TO_INT16`).
- **`core/interp.asm`:** `NUMBER` (section 6), `.gotfloat` (`FPOP` then `COMPILE_FLOAT_LITERAL`: becomes a 5-byte
  copy), `STACK_CHECK` (`FSTACK_LIMIT` `$8C04`, section 4). `core/throwcatch.asm` and `core/abortquit.asm` set IY to
  `FSTACK_TOP` only: unchanged.
- **`PRINT_UDEC16`** lives in `core/floatprint.asm` but `LIST-DEFS` (`core/recall.asm`) calls it; it moves to
  `core/print.asm` (smoke p64 stubs it today and keeps doing so).
- **Demo ROMs:** Blackjack and Gallery include `float`, `floatmul`, `floatdiv`, `decimal` and `beep` (no `F.`, no
  transcendentals) for their `n 0.08 BEEP` literals and the `F+ F- F* F/` words. They get the engine without FTOA,
  SQR and the series: about 1,300 B against today's 1,011 [E], so their free space falls by about 290 B (Blackjack
  1,096, Gallery 1,021 today): floors lowered with the ledger row. Their behaviour is unchanged (BEEP durations).
- **Bench ROMs:** `bench_pixel`, `bench_sieve`, `bench_string` include the same files for linking only; their
  programs use no float word.
- **`rom/graphics_exrom.asm`** asserts `VIEW_STOP + 2 <= $8C00` (the float region's bottom): unchanged, the region's
  bottom stays `$8C00`.

### 10.2 Smoke ROMs (`tools/rom_list.txt`)

Regenerated expectations (5-byte cells written and read with a 5-byte `CHECK_FTOP`, the expected cells computed with
`fpmodel`/`fpforth` and written as `DB` rows): **p8** (F+ F-), **p18** (F*), **p19** (F/), **p22** (F. text: `6.0000`,
`0.2500`, `-2.0000` keep their text), **p23** (literals `3.5`, `0.25`, and `DOUBLEIT` printing `7.0000`), **p29**
(FSQRT; its `F.` check prints `1.4142` instead of `1.4141`), **p30** (PI, SIN, COS; `1.0 SIN F.` `0.8415` instead of
`0.8408`, `2.0 COS F.` `-0.4161` instead of `-0.4156`), **p31** (BEEP's duration table, 3-byte cells today; the frame
counts stay), **p34** (S>F, F>S: the F>S results change only if F3 truncates instead of flooring, e.g. −0.5 gives 0
not −1), **p35** (FROUND: −2.5 gives −3 under F3's recommendation, today −2), **p38** (the float-stack check: three
`inc iy`/`dec iy` per cell become five), **p42** (RAD, DEG), **p50** (two dummy `FPUSH` values: 5-byte cells).
Unchanged in content: p9, p45, p46, p52, p53 (chain tails and BEEP text), and the rest.
The audit's list (p8, p18, p19, p22, p23, p29, p30, p34, p35, p42) missed p31, p38 and p50.

### 10.3 Tools

- **`tools/bench.py`:** `EXPECTED["float"]` is `-0.6523` today, which is the 3-byte format's error. The program sums
  the 5-term sine series over 300 points; the exact sum is −0.1453125 (Python doubles), and the 5-byte model of the
  same operations gives −0.14531255, printed `-0.1453` [M: `fpmodel` run of the bench program]. The new expected
  value is part of `bench_float`'s re-baseline (owner's OK).
- **`tools/cart_diff.py`** computes the float depth as bytes / 2 (`fstack_depth`, a report figure; the comparison of
  the stack bytes is unaffected): becomes / 5. Its `stack_kept` case types `5 S>F` (fine on either format).
  `NOT_ADDRESS` in `cart_diff.py` and `tools/poweron.py` names today's float constants (`PI_M`, `HALF_PI_M`, ...):
  updated to the new names.
- **`tools/ay_audio.py`** types `n 0.3 BEEP` (unchanged).
- **`tools/sync_blackjack_source.py`:** the BEEP literal text is unchanged, so `demos/blackjack.fs` and
  `rom/forth_smoke_p52_blackjack_test.fs` stay (`--check` run).

### 10.4 Documents

`docs/forth_tutorial.md` (float section lines 750-925: the printed values, F.'s truncation text, the 3-byte format
and the table-accuracy claims, the word list, the BEEP section unchanged) and its generated `.docx`; `README.md` (word
list, examples); `docs/CHANGELOG.md` (a new entry; history kept); `docs/numeric_model.md`; the audit (4.2, the ledger
row); HANDOFF. `docs/PROJECT_PLAN.md` is history and keeps its 3-byte text.

## 11. O10: integer multiply and divide

### 11.1 Multiply and divide

`MATH_UMUL16`, `MATH_UDIV16`, `MATH_MULTIPLY16`, `MATH_DIVIDE16`, `MATH_MOD16` (178 B [M]) are replaced by Leap-C's
register-only routines rebuilt under Forth's names and register contracts (callers: `*`, `/`, `MOD` in
`core/mathfn.asm`, `MATH_RND16` through `MATH_MOD16`; `core/floatdiv.asm`'s use goes with it; `include/kernel_api.inc`
exports `MATH_MULTIPLY16`/`MATH_DIVIDE16`):

- unsigned multiply 16 steps from the top bit (`RT_UMUL`), unsigned divide 16 restoring steps with the remainder in
  DE (`RT_UDIV`), both registers only: `DIV_DIVIDEND`, `DIV_QUOT`, `DIV_COUNTER` and `MATH_SIGN` (6 B of RAM) go;
- the signed forms through one sign routine (`RT_SDIV`'s pattern): the quotient truncated toward 0, the remainder
  with the dividend's sign, a divisor of 0 gives 0 and remainder 0. This is today's contract exactly [S, the math.asm
  headers], so `*`, `/` and `MOD` give the same results; T13's integer part checks them against Python on 40,000 pairs
  (the boundaries −32768, −1, 0, 1, 32767 and random).
- Size about 90 B for the five [E: Leap-C's 84 plus the register moves Forth's contracts need], −88 B. Speed [L]:
  60000/7 from 3,584 to 1,479 T. Gates: `make bench` sieve and string must hold (within 1%) or improve.

### 11.2 RND (F8: Leap-C's xorshift)

Today's `MATH_RND16` is a Fibonacci LFSR that advances one bit per call, so each value is the previous one shifted
right with one new top bit, and `RND n` is that value `MOD n`. Consecutive results are strongly related: in a Python
copy of the routine, `6 RND` over 60,000 calls never produces 12 of the 36 possible pairs of consecutive values
(each pair that does occur comes about 1.5 times as often as it should) [M, scratch simulation]; and `MOD` favours
small results when n does not divide 32768 (`10000 RND` gives 0-2767 about 25% more often than the rest).

After F (in O10's commit, `kernel/math/math.asm`):

- **The generator:** Leap-C's 16-bit xorshift (`LIB_RAND`: x ^= x << 7, x ^= x >> 9, x ^= x << 8; period 65535). The
  same simulation produces all 36 pairs, each within 6% of the fair rate.
- **The range:** `RND n` = ⌊x × n / 65536⌋ for n > 0 (the high word of the 16 × 16 product), so every result in 0..n−1
  comes from ⌊65535/n⌋ or one more states; n ≤ 0 gives 0, as today.
- **Seeding, as today:** `RANDOMIZE n` sets the state to n; a state of 0 (after the cold start or `0 RANDOMIZE`) is
  replaced at the next `RND` by a seed from the R register (low bit set, so never 0), so programs differ from run to
  run unless they seed.
- About −30 B [E]. Every `RND` sequence changes: the Blackjack and Gallery demos' play (accepted by the owner), any
  smoke ROM that checks an `RND` result (found and updated in O10's commit), and `bench_pixel`, whose work and
  `RESULT=159` follow its seeded `RND` calls: its expected RESULT and its baseline are reset in O10's commit (accepted
  by the owner with F8), with the before and after figures in the ledger row.

## 12. BEEP

`BEEP ( n fduration -- )` keeps its contract (AY_BEEP_SPEC: frames = round(60 × seconds), negative or under half a
frame plays nothing, 32,768 frames at most). The float part is rebuilt on the engine: push 120 (a 5-byte constant),
`F*`, then the half-frame count from the unpacked product (exponent above 144: the 65535 cap; negative: 0), halved
with rounding as today. `FLOAT_TO_INT16` and the `F_SHRA` use go. Smoke p31 (BEEP's oracle) keeps its expectations;
its float inputs change encoding.

## 13. T13: the float oracle (`tools/floattest.py`, `make floattest`)

Ports 10840-10859 (free). Built on `tools/fharness.py` (T11): `Machine` boots the build to the prompt, then each check
restores the snapshot, writes operands into float-stack cells (IY set to the cell), calls the word's code address
(`W_FPLUS`, `W_FSTAR`, ... from the `.sym`) with a stop return, and reads the result cells, IY, the data stack and the
screen. Error cases: a CATCH frame whose saved SP returns to the harness's stop slot (as Leap-C's `ERRSP`), so THROW
lands there with the code on the data stack. The model: `tools/fpmodel.py` (Leap-C's, unchanged) and
`tools/fpforth.py` (Forth's words composed of model operations, step for step as sections 6-8 give them: the
parser, `F.` and `FS.` text, `F>S`, `FROUND`, `FLOOR`, `FSQRT`, `SIN`, `COS`, `TAN`, `RAD`, `DEG`, `BEEP`'s frame
count; and `RND`'s generator and range).

| Group | Checks |
|---|---|
| **old** (behaviour the spec keeps; must pass on the old build too) | typed at the console and read off the screen: `2.0 3.0 F* F.` `6.0000`, `0.5 0.5 F* F.` `0.2500`, `-6.0 3.0 F/ F.` `-2.0000`, `1.5 2.25 F+ F.` `3.7500`, `7 S>F F.` `7.0000`, `7.9 F>S .` `7`, `2.5 FROUND F>S .` `3`, `4.0 FSQRT F.` `2.0000`, `0.0 SIN F.` `0.0000`, compiled literals in a colon definition, `BEEP`'s frame count for 0.5 s (30), floats in `CATCH`. Exact strings chosen where both formats agree |
| **new** (the spec; fail on the old build) | Engine, bit for bit against `fpmodel` on the generators of Leap-C's floattest (300 cases each): `F+ F- F* F/` (near pairs for cancellation), `F< F=` flags, `S>F` (all boundaries), `F>S`, `FROUND`, `FNEGATE`, `FABS`; literals (the 20 texts of Leap-C's list without suffixes, plus random `d.dEn`, signs, integers, 10+ digit integers); `F.` text on 300 values; `FSQRT`, `SIN`, `COS`, `TAN`, `RAD`, `DEG` bit for bit against `fpforth` and within the section 8 accuracy of Python's `math`; the model against Python's floats within 2^-30 (as Leap-C); errors −42, −43, −46 (the literal `1E39`, the integer literals `100000` and `-40000`, `40000.0 F>S`, `11 PLACES`); `F.` with `PLACES` 0-9 and the `-0.0000` rule; `FS.` text against `fpforth` and against Python's `%.<p>E` digits; `FLOOR`, `FMIN`, `FMAX`, `F>`, `F0<`, `F0=`, `FDEPTH`, `F@ F!`, `FVARIABLE`, `FCONSTANT` (typed and compiled); the float stack: 204 cells push and pop, the 205th push reported by `STACK?`; uncaught-THROW messages typed at the console (`1.0 0.0 F/` prints `DIVISION BY ZERO`, `5 THROW` `ERROR 5`, `' NOSUCHWORD` `UNDEFINED WORD`, `-1.0 FSQRT` `INVALID ARGUMENT`); integer `*` `/` `MOD` on 40,000 pairs against Python (O10); `RND`: 1,000 results after `n RANDOMIZE` equal the model's, `6 RND` gives all 36 consecutive pairs in 3,600 calls, `0 RANDOMIZE` reseeds from R (two boots give different first values) |
| **speed** (recorded, not gated) | T-states per word on fixed operands: `F+` (exponent difference 0, 8, 30), `F*`, `F/`, `F.`, `FS.`, a literal, `FSQRT`, `SIN`, `*`, `/` (60000 7), `MOD`, `RND`; old and new build side by side in the ledger row |

Run on the old build first (`make floattest FLOATTEST_BUILD=<old>`): the old group passes, the new group fails, and the
old speed figures are recorded. That run, with this spec, is the oracle commit.

## 14. Byte budget [E unless marked]

| | HOME B |
|---|---:|
| Removed: the float files and `decimal.asm` | −2,100 [M] |
| Removed: `NUMBER`'s digit loop, `BEEP`'s `FLOAT_TO_INT16` and float glue | about −110 |
| Removed (O10): the five math routines | −178 [M] |
| Engine (`fpcore`'s 1,461 B [L, M in `leapc_exrom.lst`] less FTOA 211, ATOF 338, `POW10` 65, the dispatch 39 and INC/DEC 35; register kernels; FADD's byte alignment) | about +800 |
| FTOA (emitting, with `FMUL10`/`FDIV10`) | about +260 |
| ATOF (counted token, sign, integer path) with `POW10` | about +440 |
| FSQRT, SIN/COS (reduction, series, 5 coefficients, π/180, 1/π, P1, P2), TAN | about +370 |
| Today's 14 words' headers and glue on the new engine, BEEP's float part, the error entries | about +230 |
| O10 routines | about +90 |
| **Net, before new words** | **about −200 (more free)** |
| New words (section 8.3, with `PLACES` and `FS.`) | about +457 |
| Error messages (section 8.4) | about +115 |
| Range checks (integer literals, `F>S`), the `-0.0000` rule | about +28 |
| `RND` (xorshift, multiply range, R seeding, against the LFSR's 88) | about −30 |
| **Net, as decided** | **about +370 B used: HOME 1,629 → about 1,260 free** |

The demos lose about 290 B each (section 10.1). The estimates are coarse (±250 B). Every code commit measures its own row; if HOME would fall below 1,000 B free, the
EXROM fallback for the transcendentals (section 8.2) is proposed to the owner before going on. Floors in
`tools/budget.toml` move only with a ledger row and a history line.

## 15. Owner decisions (decided 2026-10-29)

The owner's rule for all of them: what is best for the language and its users, not compatibility with today's
behaviour or sequences.

| # | Decision | Decided |
|---|---|---|
| F1 | Multiply/divide kernels | Register kernels, bit-exact with `fpmodel` (section 5) |
| F2 | New words | `FDUP FDROP FSWAP FOVER FDEPTH FNEGATE FABS F< F> F= F0< F0= FMIN FMAX FLOOR F@ F! FVARIABLE FCONSTANT TAN PLACES FS.` (section 8.3) |
| F3 | `F>S`, `FROUND` | `F>S` truncates toward 0, THROW −43 outside −32768..65535; `FROUND` ties away from 0; `FLOOR` for the floor |
| F4 | Output | `F.` with `PLACES` decimals (4 by default), no `-` on an all-zero result; `FS.` scientific (section 7) |
| F5 | Literals | `E`/`e` exponents, `1E3` a float; integer literals outside −32768..65535 THROW −43 (section 6) |
| F6 | SIN/COS/TAN beyond about ±102,940 | THROW −43 |
| F7 | Uncaught THROW | a message for each code the ROM raises, `ERROR n` for the rest; `STACK?` only for the stack check (section 8.4) |
| F8 | `RND` | Leap-C's xorshift, a multiply for the range, R seeding kept; demos' play and `bench_pixel` change (section 11.2) |
| F9 | Order | section 16 |
| F10 | `bench_float`'s RESULT | `-0.1453` in `tools/bench.py` (the exact value; today's `-0.6523` is the 3-byte error) |

Still the owner's at the time (decision 3): resetting `bench_float`'s T-state baseline if F's build is slower.

## 16. Order of work (each a commit with a measured ledger row)

1. **Spec** (this file) with the owner's answers.
2. **T13 oracle** (`tools/fpmodel.py` vendored, `tools/fpforth.py`, `tools/floattest.py`, `make floattest`), run on
   the old build: old group pass, new group fail, old speed figures.
3. **O10 and RND** (section 11): independent of the format, so they go first and the bench gates (sieve, string) are
   read alone; `bench_pixel`'s RESULT and baseline reset here (F8). Ledger row.
4. **Engine and today's 14 words on the 5-byte format**, with the parser, `F.`, BEEP, `FSQRT`, SIN/COS, the
   smoke ROMs and the tests that hard-code the old format (section 10), in one commit: the format changes everywhere at
   once. Ledger row; bench (float figure for the owner).
5. **New words** (F2) with `PLACES` and `FS.` (F4), the error messages (F7). Ledger row.
6. **Provenance scan** on the images (`make check`'s `tools/provenance.py`), NOTICE entry (decision 4), docs
   (`docs/forth_tutorial.md` float section, CHANGELOG, the audit's 4.2 and ledger, HANDOFF). Full run: `make edtest`,
   `test`, `harness`, `tapetest` (alone), `cartdiff`, `fusesave`, `bench`, `repro`, `check`, `floattest`.
