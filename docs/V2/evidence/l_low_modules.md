<!-- Step L inventory, 2026-10-28: produced read-only by a delegated agent from the Forth listing at master 0d45a2f and a scratch build of Leap-C b918527 (`git archive b918527`, `make`). Paths under /tmp are that scratch area. Byte counts come from a listing sizer (per top-level label, emitted bytes); the claims that a recommendation rests on were re-checked by hand, see docs/V2/LEAPC_COMPARISON_AUDIT.md section 1. -->

# Step L: Leap-C comparison of the four low modules (read-only, measured)

Scope: Forth build `build/forth_boot.lst` (current HEAD `0d45a2f`, ROM `build/forth_boot_rom0.bin`, 16,384 B).
Leap-C export at `b918527`: `build/leapc_home.lst`, `build/leapc_exrom.lst`, ROM `leapc/build/leapc_home.bin`.
No build, no emulator, no edits to either repository. All byte counts come from the sizer; nothing is estimated.

Notation: "19 (5+14)" = 19 bytes total, of which 5 are the dictionary header (`DW` link + `DB` count and name) and 14 are code.
Rows marked `H_` in the sources are headers; `W_` labels are code. `(inferred)` marks an inference from names or structure.

## 0. Method, sizer caveat and reconciliation

### 0.1 Sizer caveat (measured)

`lst_routines.py` (the given sizer) skips listing lines whose byte field is truncated with `...`, e.g. `FF FF FF...` from a `DS` fill of more than four bytes. Those fills are therefore not counted. Forth's `forth_boot.asm` alone loses 234 B this way (RST pads 42, RST_38 pad 40, cart-ID pad 152).

Scratch copy with that one fix: `L/lst_routines_fixed.py` (counts such a line as next-emitted-address minus its address). All figures below use it. Validation:

- Forth HOME: sum over all files except `sysvars.inc` (RAM-only `DS`) = **16,384 B** exactly.
- Leap-C HOME: sum over all files except `sysvars.inc` (602, RAM) and `leapc_cells.inc` (507, RAM) = 16,373 B, plus **11 unfilled bytes** in page zero where `ORG` skips (0x07, 0x0D-0x0F, 0x16-0x17, 0x1E-0x1F, 0x25-0x27) = **16,384 B** exactly.

Raw (unfixed) and fixed outputs: `L/forth_all.txt`, `L/forth_fixed.txt`, `L/leapc_home_all.txt`, `L/leapc_home_fixed.txt`, `L/leapc_exrom_fixed.txt`.

### 0.2 Attribution artefacts (measured)

- A label-less `ORG` inherits the previous label's count: Leap-C `RT_MODU` 11 B = its own 5 B + the IM 1 vector at 0x0038 (6 B); Leap-C `RT_ERROR` 13 B = its own 11 B + the NMI `retn` at 0x0066 (2 B).
- Forth `COLD_CLEAR_END EQU ...` is taken as a label. Its "81 B" is the rest of `COLD_START` (17 + 81 = 98 B).
- Basename collisions checked by address: `v2_ay_beep.asm` (HOME 0x0C1C-0x0C6D; EXROM 0xD918) and `sysvars.inc` (RAM only). No other collision among the files used here.

### 0.3 Reconciliation with the audit brackets

Brackets are from `docs/V2/FORTH_V2_REUSE_AUDIT.md` section 4.5 (table at line ~353). The brackets could not be reproduced exactly from the current listing (see section 6).

| Module | Bracket | Measured now | Files counted | Difference |
|---|---:|---:|---|---:|
| 1 Integer words | ~703 | 680 | arith 159, compare 131, logic 122, mathfn 140, stackops 128 | -23 |
| 2 Sound words | ~185 | 183 | sound 30, soundext 153 (beep.asm 209 excluded, see 2.4) | -2 |
| 3 Boot | 599 | 597 | forth_boot.asm, address range 0x0000-0x0254 | -2 |
| 4 Misc I/O | 133 | 166 | portio 37, key 67, stick 18, bytemem 44 | +33 |

Module 4: no subset of the four files sums to 133 (portio+key+stick = 122; key+stick+bytemem = 129). `bytemem.asm` holds `C@` and `C!`, which are memory words, not port I/O. Its inclusion here follows the brief.

Module 1 is 680 when `kernel/math/math.asm` is left out. Kernel routines used by the integer words (ABS16 5, shared with float; SGN16 21, MOD16 27, SQRT16 81, RND16 88, RND_SEED 4) are listed in 1.2. Adding them gives 906; no combination reproduces 703.

### 0.4 Header/code split (measured)

| Module | Header B | Code B | Total |
|---|---:|---:|---:|
| 1 Integer (5 files) | 155 | 525 | 680 |
| 2 Sound (sound + soundext) | 51 | 132 | 183 |
| 4 Misc I/O (4 files) | 51 | 115 | 166 |

---

## 1. Integer words

Files: `core/arith.asm`, `core/compare.asm`, `core/logic.asm`, `core/mathfn.asm`, `core/stackops.asm` (all five confirmed as the integer words; `stackops` holds ROT, 2DUP, 2DROP, ?DUP and PICK, which are stack words, not arithmetic).
Totals: 680 B (155 header + 525 code). Leap-C side: `src/runtime/helpers.asm` shifts and compare, `src/runtime/library.asm` LIB_ABS and LIB_ATOI, `platform/kernel/math/math.asm` (via D3), `src/rom/home.asm` RST_CMPLT.

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| `1+` (arith) | 19 (5+14) | adds 1 to the top cell | none | - | no counterpart | C's `++` is generated code, not a helper (inferred) |
| `1-` (arith) | 19 (5+14) | subtracts 1 from the top cell | none | - | no counterpart | as `1+` (inferred) |
| `NEGATE` (arith) | 29 (9+20) | two's-complement negate of top cell | MATH_NEGATE16 (math.asm) | 8 | same algorithm, different code | Forth inlines the same 7 instructions (`af 95 6f 3e 00 9c 67`, i.e. xor a / sub l / ld l,a / ld a,0 / sbc a,h / ld h,a) that MATH_NEGATE16 has before its `ret`; the 8-byte Leap routine itself is byte-identical to Forth's `MATH_NEGATE16` (kernel copy) |
| `MAX` (arith) | 46 (6+40) | signed max: sign test, then unsigned compare for same signs | none | - | no counterpart | the signed-compare method matches RST_CMPLT's (sign test, then compare) (inferred) |
| `MIN` (arith) | 46 (6+40) | signed min, mirror of MAX | none | - | no counterpart | as MAX |
| `=` (compare) | 43 (4+39) | -1 if top two cells equal, else 0 | none | - | no counterpart | C's `==` is generated code (inferred) |
| CMP_LESS_HL_DE (compare, helper) | 27 | signed a<b; HL = -1 or 0 | RST_CMPLT (home.asm) + RT_CMPLT_SAME (helpers.asm) | 8 + 5 = 13 | same algorithm, different code | both: if signs differ, the negative operand is smaller; if the same, compare the magnitudes. Forth tests the sign bit of `a-b` (no overflow for same signs); Leap-C uses the carry of `DE-HL`. Forth returns a flag word; Leap-C returns carry |
| `<` (compare) | 31 (4+27) | a<b via CMP_LESS_HL_DE | RST_CMPLT | 8 | same algorithm, different code | the RST returns carry; the Forth word stores a flag |
| `>` (compare) | 30 (4+26) | a>b via CMP_LESS_HL_DE with operands swapped | RST_CMPLT | 8 | same algorithm, different code | as `<` |
| `AND` (logic) | 33 (6+27) | bitwise AND of two cells | none | - | no counterpart | C's `&` is generated code (inferred) |
| `OR` (logic) | 32 (5+27) | bitwise OR of two cells | none | - | no counterpart | as AND (inferred) |
| `XOR` (logic) | 33 (6+27) | bitwise XOR of two cells | none | - | no counterpart | as AND (inferred) |
| `INVERT` (logic) | 24 (9+15) | complement both bytes of top cell | RT_CPL (helpers.asm) | 7 | same operation, different code | RT_CPL complements HL (two `cpl`); Forth complements the two bytes in the stack cell via IX |
| `ROT` (stackops) | 43 (6+37) | rotate top three cells | none | - | no counterpart | C has no stack words |
| `2DUP` (stackops) | 27 (7+20) | duplicate top two cells | none | - | no counterpart | - |
| `2DROP` (stackops) | 15 (8+7) | drop two cells | none | - | no counterpart | - |
| `?DUP` (stackops) | 20 (7+13) | duplicate top if non-zero | none | - | no counterpart | - |
| `PICK` (stackops) | 23 (7+16) | copy the u-th cell to the top | none | - | no counterpart | - |
| `ABS` (mathfn) | 16 (6+10) | absolute value via MATH_ABS16 | LIB_ABS (library.asm) -> MATH_ABS16 | 6 (+5 shared) | IDENTICAL routine (MATH_ABS16); different wrapper | MATH_ABS16 is byte-identical in both ROMs (`7c b7 f0 18 f3`); LIB_ABS = call LIB_ARGS + jp MATH_ABS16 |
| `SGN` (mathfn) | 16 (6+10) | sign via MATH_SGN16 (kernel, 21 B) | none | - | no counterpart | MATH_SGN16 deleted in Leap-C (platform D3: "SGN16 ... no Release 1 caller") |
| `MOD` (mathfn) | 20 (6+14) | remainder via MATH_MOD16 (kernel, 27 B; also used by RND16) | RT_MODS (helpers, 4) and RT_MODU (home.asm, 5 body) | 4 / 5 | same job, different code | division family (scheduled elsewhere, not compared); MATH_MOD16 deleted in Leap-C (D3) |
| `SQRT` (mathfn) | 17 (7+10) | integer sqrt via MATH_SQRT16 (kernel, 81 B) | none in ROM | - | no counterpart | MATH_SQRT16 deleted in Leap-C (D3). Leap-C's `isqrt` is in `libs/shapes.asm` (outside ROM, per commit message of c8eab8f; not opened) |
| `RND` (mathfn) | 16 (6+10) | random 0..n-1 via MATH_RND16 (kernel, 88 B; LFSR, scaled by MATH_MOD16) | LIB_RAND (library.asm) | 28 | different job (interface) and different algorithm | Forth: LFSR with MOD scaling, takes n. Leap-C: xorshift (shifts 7, 9, 8), no argument, returns 0..32767 |
| `RANDOMIZE` (mathfn) | 19 (12+7) | stores seed via MATH_RND_SEED (kernel, 4 B: `ld (RND_STATE),hl; ret`) | LIB_SRAND (library.asm) | 8 | same store, different generator | both store the seed as the state word; Leap-C maps state 0 to seed 1 (LIB_RAND), Forth seeds from R when state is 0 (MATH_RND16) |
| `*` (mathfn) | 18 (4+14) | multiply via MATH_MULTIPLY16 (kernel, 28 B) | RT_MUL, RT_UMUL (helpers) | 2, 17 | same job, different code; not compared | multiply family, scheduled elsewhere (O10) |
| `/` (mathfn) | 18 (4+14) | divide via MATH_DIVIDE16 (kernel, 27 B) | RT_SDIV, RT_DIVS, RT_UDIV (helpers) | 24, 6, 31 | same job, different code; not compared | divide family, scheduled elsewhere (O10) |

### 1.2 `kernel/math/math.asm` (411 B, all routines listed)

| Routine | B | Class | Used by (Forth) | Leap-C | Relationship |
|---|---:|---|---|---|---|
| MATH_UMUL16 | 22 | multiply (excluded) | MATH_MULTIPLY16 | RT_UMUL 17 | not compared (O10) |
| MATH_UDIV16 | 74 | divide (excluded) | MATH_DIVIDE16, MATH_MOD16 | RT_UDIV 31 | not compared (O10) |
| MATH_MULTIPLY16 | 28 | multiply (excluded) | `*` | RT_MUL 2 + RT_UMUL | same job, not compared |
| MATH_DIVIDE16 | 27 | divide (excluded) | `/` | RT_SDIV 24 / RT_DIVS 6 | same job, not compared |
| MATH_MOD16 | 27 | division family | `MOD`, MATH_RND16 | RT_MODS 4 / RT_MODU | same job, not compared; deleted in Leap-C (D3) |
| MATH_COMPARE16 | 26 | integer compare, used by graphics (line/circle, graphics.asm lines 1326, 1345) | - | MATH_COMPARE16 26 | IDENTICAL after relocation: the same 26 bytes except three absolute jumps (`jp po`, `jp m`, `jp m`) whose targets differ by the constant 0x0869 (= 0x0B61 - 0x02F8) |
| MATH_NEGATE16 | 8 | negate, used by decimal, string, graphics, floatdiv, floatmul, floattrig | - | MATH_NEGATE16 8 | IDENTICAL (same 8 bytes) |
| MATH_ABS16 | 5 | abs, used by the ABS word and by floatdiv, floatmul, floatprint | LIB_ABS | MATH_ABS16 5 | IDENTICAL (same 5 bytes) |
| MATH_SGN16 | 21 | `SGN` | - | deleted (D3) | no counterpart |
| MATH_SQRT16 | 81 | `SQRT` | - | deleted (D3) | no counterpart |
| MATH_RND16 | 88 | `RND` | LIB_RAND 28 | - | different algorithm (see 1 table) |
| MATH_RND_SEED | 4 | `RANDOMIZE` | LIB_SRAND 8 | - | same store (see 1 table) |

Sum check: 22+74+28+27+26+8+5+21+27+81+88+4 = 411.

### 1.4 Leap-C side for this module (`helpers.asm`, `library.asm`, `home.asm`)

| Leap-C routine | B | Does | Forth counterpart | Relationship |
|---|---:|---|---|---|
| RT_SHL | 8 | HL = DE << HL (count capped at 16) | none (no shift word in Forth) | no counterpart |
| RT_SHR | 11 | logical right shift | none | no counterpart |
| RT_SAR | 11 | arithmetic right shift | none | no counterpart |
| RT_SHCNT | 15 | shift count helper | none | no counterpart |
| RT_CMPLT_SAME | 5 | same-sign unsigned compare, carry = DE<HL | CMP_LESS_HL_DE | see table 1 |
| RST_CMPLT (home.asm) | 8 | signed compare entry (RST $28) | CMP_LESS_HL_DE | see table 1 |
| RT_CPL | 7 | HL = ~HL | W_INVERT | see table 1 |
| LIB_ABS | 6 | abs wrapper | W_ABS | see table 1 |
| LIB_ATOI | 54 | text to int: skip spaces, sign, digits x10 | W_VAL (string.asm, 6 + 115 B; outside this module set, not compared) | same job (inferred) |

---

## 2. Sound words

Files: `core/sound.asm` (30 B: SOUND_WRITE 10, SOUND 20), `core/soundext.asm` (153 B: AY_WRITE 10 plus TONE, VOLUME, MIXER, NOISE, ENVELOPE). `kernel/sound/` is not in the Forth build.

Leap-C side: `library.asm` LIB_SOUND (17) and LIB_BEEP (25), `platform/rom/exrom_sound.asm` SOUND_EXROM (7, in EXROM), `platform/rom/v2_ay_beep.asm`, `src/shell/shell.asm` STARTUP_CHIME (75) and CHIME_REGS (11).

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| SOUND_WRITE (sound.asm) | 10 | B = register (0-16 accepted, 17 and above ignored silently), C = value; two `out`s | LIB_SOUND (library.asm) | 17 (incl. call LIB_ARGS 3) | same algorithm, different range rule | Leap-C: register 0-15, otherwise runtime error 4 (RT_ERR_ARG). Forth accepts register 16 |
| SOUND_EXROM (exrom_sound.asm, EXROM) | - | (EXROM counterpart) | SOUND_EXROM | 7 | same algorithm, no range check | D19: the check was removed in Leap-C; its only caller writes registers 0-10 |
| SOUND (sound.asm, H 8 + W 12) | 20 (8+12) | pops register and value, calls SOUND_WRITE | LIB_SOUND | 17 | same job, different code | arguments come from the stack (Forth) or the C frame (Leap-C) |
| AY_WRITE (soundext.asm) | 10 | like SOUND_WRITE, but register 0-15 (`cp 16`), silent ignore | LIB_SOUND | 17 | same algorithm, different range rule | as SOUND_WRITE; the two Forth files both write `PORT_AY_REG` then `PORT_AY_DATA` |
| TONE (H 7 + W 27) | 34 (7+27) | channel period: fine byte to reg 2c, coarse nibble to reg 2c+1; channel 0-2 else ignored | none | - | no counterpart | Leap-C: user computes register values and calls sound(reg,value) (inferred from LIB_SOUND's contract) |
| VOLUME (H 9 + W 21) | 30 (9+21) | level 0-15 to reg 8/9/10 | none | - | no counterpart | as TONE |
| MIXER (H 8 + W 10) | 18 (8+10) | mask to reg 7 | none | - | no counterpart | as TONE |
| NOISE (H 8 + W 13) | 21 (8+13) | noise period (low 5 bits) to reg 6 | none | - | no counterpart | as TONE |
| ENVELOPE (H 11 + W 29) | 40 (11+29) | period to regs 11-12, shape (low 4 bits) to reg 13 | none | - | no counterpart | as TONE |

### 2.4 How `core/beep.asm` relates (not in this module set; for context)

| Forth routine | Forth B | Leap-C routine | Leap-C B | Relationship |
|---|---:|---|---:|---|
| BEEP_TABLE (beep.asm) | 24 | AY_BEEP_TABLE (v2_ay_beep.asm) | 24 | IDENTICAL values: 64145, 60545, 57147, 53940, 50912, 48055, 45358, 42812, 40409, 38141, 36000, 33980 in both |
| H_BEEP + W_BEEP | 64 (7+57) | LIB_BEEP (library.asm) | 25 | same job, different interface (Forth: semitones and float seconds; Leap-C: frames and semitone) |
| BEEP_PLAY (+ FLOAT_TO_INT16 31) | 121 (90+31) | AY_BEEP_PERIOD (HOME, 46) + AY_BEEP_PLAY (EXROM, 42) + AY_WAIT_FRAMES (HOME, 12) | 100 | same job, not compared at the instruction level |

Total Forth beep.asm: 209 B. Leap-C beep path: 25 + 46 + 24 + 42 + 12 = 149 B (inferred to be the path; the trampoline LEAPC_EXROM_BEEP is in home.asm, not counted here).

### 2.5 The startup chime (Leap-C counterpart of Forth's STARTUP_CHIME)

Covered in section 3 (cold start). Register values match for R0-R5 and R7-R10 (Forth's CHIME_TABLE and Leap-C's CHIME_REGS: 165, 1, 78, 1, 25, 1, [R6 not written by Forth; Leap-C writes 0], 248, 0, 0, 0).

---

## 3. Boot (`rom/forth_boot.asm`) and `src/rom/home.asm`

### 3.1 Forth boot region (0x0000-0x0254, 597 B)

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---:|---|---|---:|---|---|
| RST_00 | 8 (4 code + 4 pad) | `di`; `jp COLD_START` (non-cart build) | RST_00 (page zero, home.asm: `di`; `jp COLD_START`) | 4 | IDENTICAL instructions | Forth: `FF` pad to 0x0008 |
| RST_08 .. RST_30 (6 labels) | 8 each (1 code + 7 pad) | `ret` stub, $FF pad | RST_LDI, RST_STI, RST_ENTER, RST_LEAVE, RST_CMPLT, RST_LEX_NEXT | 5, 6, 6, 5, 8, 3 | different job | Forth stubs are empty (`ret`); Leap-C vectors hold runtime helper bodies (sec. 3.4) |
| RST_38 (IM 1) | 46 (6 code + 40 pad) | `call KBD_ISR_TICK`; `ei`; `reti` | IM 1 vector (home.asm 0x0038) | 6 | IDENTICAL instructions | Forth ISR body is 118 B, Leap-C 126 B: the 8 extra bytes are the D4 BREAK latch |
| NMI_ENTRY | 2 | `retn` | NMI (home.asm 0x0066) | 2 | IDENTICAL | - |
| ROM_ID_SKIP_CART_END (cart-ID pad) | 152 | $FF fill from 0x0068 to 0x00FF (cartridge build would put the LROS header and CART_START here) | none | - | no counterpart | Leap-C page zero has no pad here (COLD_CLEAR follows the NMI at 0x0068) |
| GRAPHICS_HOME_TABLE | 15 | 5 `jp` veneers for EXROM graphics (slots 0-4) | LX_SLOT_N (home.asm, 16 slots at 0x3FD0) and CX_* trampolines (66 B) | 48 + 66 | different job (different slot tables) | Forth veneers serve EXROM graphics; Leap-C slots serve a loaded library, trampolines serve compiler and EXROM |
| COLD_START (17 + 81) | 98 | sets SP, IX, IY; clears RAM; initialises pointers, attributes, banner and chime; enters the interpreter | COLD_START (home.asm) + COLD_CLEAR | 27 + 12 = 39 | same role, different sequence (3.2) | Leap-C: 39 B in HOME, then shell SHELL_COLD (6) + STARTUP_CHIME (75) + CHIME_REGS (11) in EXROM |
| STARTUP_CHIME (code) | 29 | walks CHIME_TABLE: writes via SOUND_WRITE, waits with HALT | STARTUP_CHIME (shell.asm, EXROM) | 75 | same sequence, different code | Leap-C loops over R0-R10 and waits with AY_WAIT_FRAMES; Forth is table-driven |
| CHIME_TABLE | 80 (data) | register/value pairs, $FF frame waits, $FE end | CHIME_REGS (shell.asm, EXROM) | 11 | same register values | Forth 80 B of pairs and waits; Leap-C 11 B of initial register values, ramp coded as loops |
| BANNER | 11 (data) | "2068-FORTH", 0 | none found | - | no counterpart | grep for DB banners in src/shell and src/rom/exrom.asm found nothing (not exhaustive) |
| INTERPRET_UNKNOWN_WORD | 59 | resets stacks, prints the bad word and "?", resets STATE, returns to editor | none | - | different job | Leap-C reports errors through RT_ERROR (11 B, home.asm) and its shell |
| REPORT_INTERP_ERROR | 10 | clears STATE, sets INTERP_ERROR_FLAG | none | - | different job | - |
| RUNTIME_ERROR_HOOK | 32 | prints "STACK?" and CR, jumps to REPORT_INTERP_ERROR | RT_ERR_STACK (2) + RT_ERROR (11) | 13 | different job | Leap-C: unwinds to RT_RUN with the error code (RTE_STACK) |
| RUNTIME_ERROR_MSG | 7 (data) | "STACK?", 0 | none | - | no counterpart | - |

Forth boot bytes by class (597 B total):

| Class | B |
|---|---:|
| vector code (RST_00 4, RST_08-30 6, RST_38 6, NMI 2) | 18 |
| vector padding ($FF; RST_00 4, RST_08-30 42, RST_38 40) | 86 |
| cart-ID padding ($FF, 0x0068-0x00FF) | 152 |
| veneers (GRAPHICS_HOME_TABLE) | 15 |
| cold start code | 98 |
| startup chime code (29) and table (80) | 109 |
| banner text | 11 |
| error hook code | 101 |
| error message text | 7 |
| **total** | **597** |

Padding total: 86 + 152 = 238 B ($FF).

### 3.2 Cold-start sequence, side by side

Forth order (`rom/forth_boot.asm` COLD_START):

| Step | Forth action | Leap-C action (home.asm COLD_START, then EXROM SHELL_COLD) | Note |
|---|---|---|---|
| F1 | `ld sp,$FF00`; `ld ix,DSTACK_TOP`; `ld iy,FSTACK_TOP` | L1 `ld sp,LEAPC_STACK_TOP` (= $FF00) | Leap-C sets no IX/IY in HOME |
| F2 | `xor a`; `ld (PORT_FF_SHADOW),a`; `out (PORT_SCLD),a` (DECR baseline; normal video; EXROM select clear) | L3 same three instructions, after the RAM clear | order differs: Forth before the clear, Leap-C after |
| F3 | `ld hl,$8000`; `ld bc,COLD_CLEAR_END-$8000` ($7228, i.e. $8000-$F227 incl. UDG table); `call MEM_FILL_ZERO` | L2 `COLD_CLEAR`: zero UDG table (`UDG_COUNT*8`), then `jp MEM_COLD_INIT`: zero $5B00 to PROG_AREA_MAX-1 ($C000-1, i.e. 25,856 B) | RAM maps differ (Forth $8000, Leap-C $5B00). Both clear UDG |
| F4 | `LATEST` = DICT_LATEST_COLD | - | Forth dictionary head |
| F5 | `WORKSPACE_END` = LOADTEXT_BUF | - | Forth workspace |
| F6 | `HERE` = FORTH_DICT_RAM | - | Forth dictionary pointer |
| F7 | `STATE`, `LEAVE_DEPTH`, `CATCH_DEPTH` = 0 | - | Forth interpreter/loop/catch state |
| F8 | `CURRENT_ATTR` = ATTR_DEFAULT ($44) | - | Forth print attribute |
| F9 | `FWRAP_OLD_COUNT` = 1 | - | Forth editor wrap |
| F10 | `call GFX_CLS`; `GFX_PRINT_STRING` of BANNER at (0,0) | - | Forth banner |
| F11 | `PRINT_COL` = 0, `PRINT_ROW` = 1 | - | Forth EMIT cursor |
| - | - | L4 `call MEM_INIT`: PROG_END, ARRAYS_END = PROG_AREA_START; VARS_START = PROG_AREA_MAX | Leap-C program area; Forth has no line store here |
| F12 | `call KBD_ISR_INIT` (22 B) | L5 `call KBD_ISR_INIT` (22 B) | IDENTICAL instruction sequence (cell addresses differ) |
| F13 | `im 1`; `ei` | L6 `im 1`; `ei` | IDENTICAL |
| F14 | `call STARTUP_CHIME` (HOME; HALT waits, interrupts on) | L7 `call BANK_PAGE_EXROM_IN` (chunk 6 = EXROM, depth 1) | Forth chime runs in HOME; Leap-C pages in EXROM first |
| F15 | `jp EDITOR_LOOP_LIVE` | L8 `jp LEAPC_EXROM_SHELL`: SHELL_COLD: `call SH_RESET_EDIT`; `call STARTUP_CHIME` (EXROM, SOUND_EXROM per write, AY_WAIT_FRAMES waits); SH_LOOP: border 7, EDITOR_INIT, hooks, SH_LOAD_EDIT, EDITOR_ENTER | Leap-C chime and shell run in EXROM |

Observed in both: stack set first, the RAM clear covering UDG, the PORT_FF_SHADOW and PORT_SCLD baseline, KBD_ISR_INIT before EI, IM 1, EI, then the chime. The chime's register writes (R0-R5, R7-R10 values) and wait sequence (3-frame steps, a hold of 22 frames, then the release) match in both (inferred from reading; frame timing not measured).

Only in Forth: IX/IY, dictionary pointers, STATE and loop/catch counters, attribute, FWRAP, GFX_CLS, banner, print cursor.
Only in Leap-C: MEM_INIT (program-area pointers), paging EXROM in before the shell, the shell's border and editor setup.

### 3.3 Leap-C HOME page zero (src/rom/home.asm, 0x0000-0x0073, 116 B)

| Class | B | Routines |
|---|---:|---|
| RST_00 (`di`; `jp COLD_START`) | 4 | RST_00 |
| RST helper bodies (in their vector slots) | 33 | RST_LDI 5, RST_STI 6, RST_ENTER 6, RST_LEAVE 5, RST_CMPLT 8, RST_LEX_NEXT 3 |
| IM 1 vector | 6 | call KBD_ISR_TICK; ei; reti |
| NMI | 2 | retn |
| page-zero helpers in padding | 21 | IO_KEY_SCAN_ROW 3, RT_MODU 5, RT_ERR_STACK 2, RT_ERROR 11 |
| cold start | 39 | COLD_START 27, COLD_CLEAR 12 |
| unfilled `ORG` gaps (not emitted by the assembler) | 11 | 0x07, 0x0D-0x0F, 0x16-0x17, 0x1E-0x1F, 0x25-0x27 |
| **total** | **116** | |

Leap-C HOME veneers and tail (not boot, for comparison): CX_FOLD 11, CX_XCALL 14, LEX_KEYWORD 5, TY_EQUAL 5, LIB_BIND 5, SH_COMPILE 12, TAPE_BLOCK 14 (66 B trampolines); LX_SLOT_N 48 B (library jump table at 0x3FD0); LEAPC_HOME_CODE_END 482 B of $FF padding (0x3DEE-0x3FCF). home.asm total: 701 B (sizer's own count; the 11 gap bytes are outside it).

### 3.4 Vector and veneer comparison

- Forth RST 08-30 are bare `ret` stubs. Leap-C RST 08-30 hold the helper bodies (LDI, STI, ENTER, LEAVE, CMPLT, LEX_NEXT): different job.
- Leap-C RST_00 and IM 1 and NMI are instruction-identical to Forth's (only the call and jump targets differ).

---

## 4. Misc I/O

Files: `core/portio.asm` (37), `core/key.asm` (67), `core/stick.asm` (18), `core/bytemem.asm` (44; memory words, not port I/O). Plus the kernel routines they call, from `kernel/io/io.asm`: IO_READ_KEY 8, IO_KEY_AVAILABLE 4, STICK_READ 30, IO_CHECK_BREAK 18.

| Forth routine | Forth B | Does | Leap-C routine | Leap-C B | Relationship | Notes |
|---|---|---|---|---|---|---|
| IN (portio.asm, H 5 + W 14) | 19 (5+14) | pops port, `in a,(c)`, pushes byte zero-extended | LIB_INP (library.asm) | 9 | same algorithm, different code | both: `ld b,h; ld c,l; in a,(c)`; LIB_INP returns through LIB_RETA (zero-extend) |
| OUT (portio.asm, H 6 + W 12) | 18 (6+12) | pops port and value, `out (c),a` | LIB_OUTP (library.asm) | 8 | same algorithm, different code | Leap-C: `ld b,h; ld c,l; out (c),e`; not in the brief's list, included as the matching routine |
| KEY (key.asm, H 6 + W 10) | 16 (6+10) | blocking key via IO_READ_KEY | LIB_GETKEY (library.asm) -> IO_READ_KEY | 8 + 8 | same job; IO_READ_KEY IDENTICAL | IO_READ_KEY is the same 8 instructions in both ROMs (`3a ?? ?? b7 28 fa 18 ee`): the KBD_KEYHIT operand differs ($829D Forth, $5C6C Leap-C) |
| KEY? (key.asm, H 7 + W 20) | 27 (7+20) | non-consuming test via IO_KEY_AVAILABLE (4 B) | none (LIB_INKEY 5 is the consuming read, via IO_READ_KEY_NONBLOCK 7) | 5 + 7 | different job | Forth's IO_READ_KEY_NONBLOCK was removed as dead code (io.asm comment); Leap-C keeps it for inkey() |
| BREAK? (key.asm, H 9 + W 15) | 24 (9+15) | calls IO_CHECK_BREAK (18 B); W_BREAKQ pushes -1 if carry is set, else 0 | none | - | no counterpart | Leap-C has no BREAK word; BREAK is latched in KBD_ISR_TICK (D4) and handled by RT_BREAKREQ (rtexit.asm, per the 3ba2fac message) |
| STICK (stick.asm, H 8 + W 10) | 18 (8+10) | pops device, STICK_READ (30 B), pushes value | none | - | no counterpart (routine removed in Leap-C) | Leap-C io.asm comment: "STICK_READ removed ... 30 bytes recovered" (V2 had no BASIC feature for it) |
| C@ (bytemem.asm, H 5 + W 15) | 20 (5+15) | byte fetch, zero-extended | none | - | no counterpart | C's byte access is generated code (inferred) |
| C! (bytemem.asm, H 5 + W 19) | 24 (5+19) | byte store | none | - | no counterpart | as C@ (inferred) |
| IO_READ_KEY (io.asm, kernel) | 8 | blocking consume of KBD_KEYHIT | IO_READ_KEY (io.asm) | 8 | IDENTICAL (instructions; one operand address differs) | see KEY |
| IO_KEY_AVAILABLE (io.asm, kernel) | 4 | `ld a,(KBD_KEYHIT); ret` | none | - | no counterpart | - |
| STICK_READ (io.asm, kernel) | 30 | joystick via AY port A | none | - | no counterpart | removed in Leap-C |
| IO_CHECK_BREAK (io.asm, kernel) | 18 | BREAK flag | none | - | no counterpart | see BREAK? |

Forth totals: portio 37 (H 11 + C 26), key 67 (H 22 + C 45), stick 18 (H 8 + C 10), bytemem 44 (H 10 + C 34). Sum 166 (H 51 + C 115). Kernel io routines above: 60 B (not in the 166).

---

## 5. Leap-C bug-fix commits in the three-file log, and Forth's status

Command run: `git -C /home/charlie.day/2068-Leap-C log --oneline -- src/runtime/helpers.asm src/rom/home.asm platform/rom/exrom_sound.asm` (Leap-C at `b918527`):

```
d31d785 Phase 11 (M11-tape): clean-room tape block I/O and block-graphics glyph; 1.0.0-beta.2
c8eab8f Phase 10: recommended fixes and library loading
f209f21 Phase 9: emulator qualification, power-on RAM, ROM coverage, hardware kit
7e46991 Phase 8: floating point, language and library completion
4d79538 Phase 7: cassette SAVE/LOAD/VERIFY and tape_save/tape_load
fe8147b Phase 5: editor and C punctuation
e38a6bc Phase 4: memory layout, banking and capacity
3ba2fac Phase 3: runtime and library
348db7f Phase 2: statements, functions, preprocessor
f88eeb0 Phase 2 step 1: safe shrink, math rationalisation, rand()
5b062b3 M1.3: typed expressions and native code generation
b18e317 M1.2: declarations, types and scoped symbols
5a8e35b M1.1: foundation and lexer
```

Commit subjects are phase names; the bug content is in the bodies. Per commit, files touched in the three paths: d31d785 home.asm (5+/7-); c8eab8f exrom_sound.asm, home.asm, helpers.asm; f209f21 home.asm (10+/1-); 7e46991 home.asm; 4d79538 home.asm; fe8147b home.asm; e38a6bc home.asm, helpers.asm; 3ba2fac home.asm; 348db7f home.asm, helpers.asm; f88eeb0 home.asm, helpers.asm; 5b062b3 home.asm, helpers.asm; b18e317 home.asm; 5a8e35b exrom_sound.asm, home.asm.

Bug-like commits with a Forth counterpart:

**5.1 f209f21 (Phase 9), COLD_START clears UDG table.** Leap-C commit body: "Defects found and fixed: the UDG table was never cleared at power-on". Diff in home.asm: `call MEM_COLD_INIT` replaced by `call COLD_CLEAR` (clears UDG table, then MEM_COLD_INIT).
- Forth had the same bug. Audit O1 (`FORTH_V2_REUSE_AUDIT.md` section 5): "Cold start does not clear UDG_TABLE ($F180 is above the $8000-$F000 clear)".
- Fixed in Forth commit `861a823` ("O1: cold start clears UDG_TABLE ..."): "COLD_START zeroed $8000..DICT_RAM_CEILING ($F000) only, but UDG_TABLE ($F180-$F227) lies above it and nothing else initialised it".
- Current `rom/forth_boot.asm`: `COLD_CLEAR_END EQU UDG_TABLE + UDG_COUNT * 8` and the fill runs to it. Status: fixed in the current listing.

**5.2 f209f21 (Phase 9), bank switch and frame interrupts (platform D14).** The f209f21 body says: "float code lost about 1% of the frame interrupts because the bank switch ran ~120 T with interrupts off against the TS2068's 32 T INT (platform delta D14)". The D14 change is in `platform/kernel/bank/bank.asm`, not in the three files, so it does not appear in the `git log` above. Included because the commit is in the list.
- Forth had the same bug: `kernel/bank/bank.asm` BANK_PAGE_EXROM_IN/OUT had `di`.
- Fixed in Forth commit `684065f` ("O8: EXROM paging no longer disables interrupts (-2 B)"): "BANK_PAGE_EXROM_IN/OUT ran about 120 T with interrupts off; the TS2068's INT is asserted for 32 T, so a frame interrupt arriving inside was lost (Leap-C delta D14)".
- Current `kernel/bank/bank.asm`: no `di` in the file; `ei` at lines 162 and 200. Status: fixed. (The audit's section 3 row "Banking ... −2 B" is stale.)

**5.3 e38a6bc (Phase 4), RT_ENTER stack floor.** Body: "pending call arguments had no bound (1,220 B pushed before any frame check)"; helpers.asm RT_ENTER now "checked before SP moves, so the frame is never made (the floor is page-aligned: a high-byte compare)". Forth counterpart: none. Forth has no ENTER prologue; its stack check is in core/interp.asm (STACK_CHECK), not compared. Status: no counterpart.

**5.4 Not bug fixes (listed for completeness):**
- c8eab8f (Phase 10): exrom_sound.asm range check removed (D19), and "RT_UDIV's unreachable branch removed: 112 T less per division" (helpers.asm). Cleanup and speed, not a defect. The Forth SOUND_WRITE keeps its own 0-16 check, and MATH_UDIV16 (74 B) is in the excluded family.
- f88eeb0 and fe8147b: size work ("RST $30 is LEX_NEXT", "RT_MODU ... page-zero padding"). Not defects.
- d31d785 (Phase 11): licensing-driven rewrite; not a defect.

---

## 6. What I could not determine

- Origin of the audit brackets. 703 (integer), 185 (sound), 599 (boot) and 133 (misc I/O) do not match the current listing (680, 183, 597, 166). The audit section 4.5 numbers may come from an older HEAD (the audit predates steps G, R0, A, R1, S and T) or from a different attribution. Not determined.
- Whether the audit's own table used the same sizer: the sizer's DS-truncation undercount (about 234 B in the Forth boot region alone) would affect any total taken from it. Not determined which figures were affected.
- Algorithm-level comparison was not done for: VAL (string.asm) against LIB_ATOI; MOD (MATH_MOD16) against RT_MODS/RT_MODU; `*` and `/` against the Leap-C multiply and divide helpers (out of scope, O10); RND16 and RND_SEED internals beyond the seed store.
- Banner: no string found in Leap-C shell or EXROM by grep (not exhaustive).
- Chime timing: register values and wait pattern match by reading; frame counts were not measured.
- No runtime behaviour was observed (read-only; no emulator run).
- `IO_LATCH_AND_CLEAR` and `IO_KEY_SCAN_ALL` (kernel io, not in the module set) were not compared.
- `tools/fharness.py` is untracked in the Forth repo (`git status`); not read, not touched.
