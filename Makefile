.PHONY: all boot forth-smoke forth-smoke-p3 forth-smoke-p4 forth-smoke-p5 forth-smoke-p6 forth-smoke-p7 forth-smoke-p8 forth-smoke-p8b forth-smoke-p9 forth-smoke-p10 forth-smoke-p11 forth-smoke-p12 forth-smoke-p13 forth-smoke-p14 forth-smoke-p15 forth-smoke-p16 forth-smoke-p17 forth-smoke-p18 forth-smoke-p19 forth-smoke-p20 forth-smoke-p21 forth-smoke-p22 forth-smoke-p23 forth-smoke-p24 forth-smoke-p25 forth-smoke-p26 forth-smoke-p27 forth-smoke-p28 forth-smoke-p29 forth-smoke-p30 forth-smoke-p31 forth-smoke-p32 forth-smoke-p33 forth-smoke-p34 forth-smoke-p35 forth-smoke-p36 forth-smoke-p37 forth-boot check clean

all: boot forth-smoke forth-smoke-p3 forth-smoke-p4 forth-smoke-p5 forth-smoke-p6 forth-smoke-p7 forth-smoke-p8 forth-smoke-p8b forth-smoke-p9 forth-smoke-p10 forth-smoke-p11 forth-smoke-p12 forth-smoke-p13 forth-smoke-p14 forth-smoke-p15 forth-smoke-p16 forth-smoke-p17 forth-smoke-p18 forth-smoke-p19 forth-smoke-p20 forth-smoke-p21 forth-smoke-p22 forth-smoke-p23 forth-smoke-p24 forth-smoke-p25 forth-smoke-p26 forth-smoke-p27 forth-smoke-p28 forth-smoke-p29 forth-smoke-p30 forth-smoke-p31 forth-smoke-p32 forth-smoke-p33 forth-smoke-p34 forth-smoke-p35 forth-smoke-p36 forth-smoke-p37 forth-boot

# Milestone 0: boot stub only.
boot:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/main.sym --lst=build/main.lst rom/main.asm
	mv forth_rom0.bin build/forth_rom0.bin

# Phase 2: dictionary header format + subroutine-threaded primitives
# (DUP SWAP DROP OVER + - @ !) smoke ROM. Border goes green if every
# self-check passes; otherwise it shows the 1-7 checkpoint number of the
# first one that failed — see rom/forth_smoke.asm's own header for the
# full pass/fail contract and a real EXROM-placeholder gotcha hit during
# this ROM's own bring-up.
forth-smoke:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke.sym --lst=build/forth_smoke.lst rom/forth_smoke.asm
	mv forth_smoke_rom0.bin build/forth_smoke_rom0.bin

# Phase 3: outer interpreter (WORD/FIND/NUMBER) + colon compiler (: ;)
# smoke ROM. Runs two fixed source strings through INTERPRET_RUN: plain
# arithmetic, then defining and using a new word — see
# rom/forth_smoke_p3.asm's own header for the full pass/fail contract.
forth-smoke-p3:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p3.sym --lst=build/forth_smoke_p3.lst rom/forth_smoke_p3.asm
	mv forth_smoke_p3_rom0.bin build/forth_smoke_p3_rom0.bin

# Phase 4: control flow (IF/ELSE/THEN, BEGIN/UNTIL) smoke ROM. Defines
# and uses a word with both branches of an IF, then a word with a
# BEGIN/UNTIL loop whose result only comes out right if it looped the
# correct number of times — see rom/forth_smoke_p4.asm's own header.
forth-smoke-p4:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p4.sym --lst=build/forth_smoke_p4.lst rom/forth_smoke_p4.asm
	mv forth_smoke_p4_rom0.bin build/forth_smoke_p4_rom0.bin

# Phase 5: TS2068 vocabulary (PLOT, LINE, CIRCLE, BEEP, BORDER) smoke
# ROM -- the first to pull in real kernel/ modules (kernel/math,
# kernel/graphics, kernel/sound) alongside core/. See
# rom/forth_smoke_p5.asm's own header for its verification strategy
# (GFX_READ_PIXEL readback, not just a stack check).
forth-smoke-p5:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p5.sym --lst=build/forth_smoke_p5.lst rom/forth_smoke_p5.asm
	mv forth_smoke_p5_rom0.bin build/forth_smoke_p5_rom0.bin

# Phase 6: line editing smoke ROM. Feeds core/editor.asm's
# EDITOR_PROCESS_KEY a canned sequence of key codes (no live keyboard,
# no Fuse keystroke injection needed) exercising insert, cursor
# left/right, and delete, then commits each line via INTERPRET_RUN --
# see rom/forth_smoke_p6.asm's own header for the exact sequences and
# core/editor.asm's own header for why EDITOR_LOOP_LIVE (the real
# interactive entry point) isn't exercised here.
forth-smoke-p6:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p6.sym --lst=build/forth_smoke_p6.lst rom/forth_smoke_p6.asm
	mv forth_smoke_p6_rom0.bin build/forth_smoke_p6_rom0.bin

# Phase 7: storage (SAVE, LOAD) smoke ROM. Verified against
# kernel/storage's own STORAGE_TEST_FAKE_SEND/RECEIVE hooks (an
# in-memory fake tape, not real cassette timing) -- proves this
# project's own wiring, NOT that the real tape wire format round-trips
# in a real emulator, which remains open. See rom/forth_smoke_p7.asm
# and core/storage.asm's own headers.
forth-smoke-p7:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p7.sym --lst=build/forth_smoke_p7.lst rom/forth_smoke_p7.asm
	mv forth_smoke_p7_rom0.bin build/forth_smoke_p7_rom0.bin

# Phase 8 (stretch goal, part A): floating point (F+, F-) smoke ROM.
# Native Forth floats, not a port of 2068-Leap's own RST $28 calculator
# -- see core/float.asm's own header. No kernel/ dependency.
forth-smoke-p8:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p8.sym --lst=build/forth_smoke_p8.lst rom/forth_smoke_p8.asm
	mv forth_smoke_p8_rom0.bin build/forth_smoke_p8_rom0.bin

# Phase 8 (stretch goal, part B): 64-column display smoke ROM.
# kernel/mode64/mode64.asm is recovered, once-shipped 2068-Leap code
# (removed from that project for its own ROM-budget reasons, not
# because it didn't work) -- see that file's own header for the real
# provenance and docs/PROJECT_PLAN.md's Phase 8 section for the full
# story, including a first attempt here that had the wrong port bit
# pattern before that code was found.
forth-smoke-p8b:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p8b.sym --lst=build/forth_smoke_p8b.lst rom/forth_smoke_p8b.asm
	mv forth_smoke_p8b_rom0.bin build/forth_smoke_p8b_rom0.bin

# Phase 9: full dictionary (every phase's words spliced into one
# LATEST chain via DICT_CHAIN_POINT -- see core/control.asm's own
# header) + real IM 1 interrupt wiring (RST $0038 -> KBD_ISR_TICK).
# Proves the chain and real interrupt firing; does not exercise a live
# keyboard (see forth-boot for that).
forth-smoke-p9:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p9.sym --lst=build/forth_smoke_p9.lst rom/forth_smoke_p9.asm
	mv forth_smoke_p9_rom0.bin build/forth_smoke_p9_rom0.bin

# The first real, live, bootable 2068-Forth product ROM -- not a smoke
# test. Boots, prints a banner, plays the startup sound (the product
# requirement tracked since Phase 4), and hands off to a real,
# interactive, keyboard-driven prompt (core/editor.asm's
# EDITOR_LOOP_LIVE). See docs/PROJECT_PLAN.md's Phase 9 section for two
# real bugs found only by a human actually typing at it.
forth-boot:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_boot.sym --lst=build/forth_boot.lst rom/forth_boot.asm
	mv forth_boot_rom0.bin build/forth_boot_rom0.bin

# Phase 10: EMIT and . (print) smoke ROM. Five checkpoints: EMIT draws
# a real pixel and advances the print cursor; . prints positive,
# negative (including the -32768 signed-magnitude edge case), and zero
# values with the right trailing-space convention; EMIT's column-wrap
# arithmetic wraps at exactly column 32. See rom/forth_smoke_p10.asm
# and core/print.asm's own headers.
forth-smoke-p10:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p10.sym --lst=build/forth_smoke_p10.lst rom/forth_smoke_p10.asm
	mv forth_smoke_p10_rom0.bin build/forth_smoke_p10_rom0.bin

# Phase 11: comparisons (=, <, >) smoke ROM. No kernel/ dependency --
# pure Z80 logic. Signed < and > use a sign-bit case split, not the
# Z80's own P/V flag after SBC -- see core/compare.asm's own header for
# the six hand-verified cases, including both 16-bit extremes.
forth-smoke-p11:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p11.sym --lst=build/forth_smoke_p11.lst rom/forth_smoke_p11.asm
	mv forth_smoke_p11_rom0.bin build/forth_smoke_p11_rom0.bin

# Phase 12: VARIABLE and CONSTANT smoke ROM. No kernel/ dependency.
# Neither uses a real CREATE/DOES> (this project doesn't have one) --
# both are built on core/interp.asm's own DOLIT compiled-literal idiom
# plus a compiled RET -- see core/variable.asm's own header.
forth-smoke-p12:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p12.sym --lst=build/forth_smoke_p12.lst rom/forth_smoke_p12.asm
	mv forth_smoke_p12_rom0.bin build/forth_smoke_p12_rom0.bin

# Phase 13: ." (print a literal string) smoke ROM. Reuses
# core/interp.asm's own DOLIT inline-data idiom, generalized to a
# variable-length string -- see core/dotquote.asm's own header.
forth-smoke-p13:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p13.sym --lst=build/forth_smoke_p13.lst rom/forth_smoke_p13.asm
	mv forth_smoke_p13_rom0.bin build/forth_smoke_p13_rom0.bin

# Phase 14: BEGIN/WHILE/REPEAT smoke ROM. Reuses core/control.asm's own
# QBRANCH/BRANCH runtime routines directly rather than modifying that
# already-shared file -- see core/loop.asm's own header. DO/LOOP
# remains open (needs its own loop-control storage design).
forth-smoke-p14:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p14.sym --lst=build/forth_smoke_p14.lst rom/forth_smoke_p14.asm
	mv forth_smoke_p14_rom0.bin build/forth_smoke_p14_rom0.bin

# Phase 15: INK/PAPER smoke ROM. core/ts2068.asm's PLOT/LINE/CIRCLE now
# read their attribute from a settable CURRENT_ATTR cell instead of a
# hardcoded constant -- a shared-file change, re-verified against
# forth-smoke-p5 and forth-smoke-p9 (both already INCLUDE
# core/ts2068.asm) under real Fuse when this landed. See
# core/color.asm and core/ts2068.asm's own headers.
forth-smoke-p15:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p15.sym --lst=build/forth_smoke_p15.lst rom/forth_smoke_p15.asm
	mv forth_smoke_p15_rom0.bin build/forth_smoke_p15_rom0.bin

# Phase 16: DO/LOOP/I smoke ROM. The loop's own limit/index live on the
# real Z80 hardware stack itself -- this project's subroutine threading
# already uses it as a de facto return stack, so this reuses that same
# discipline rather than inventing a separate one. Verified including
# the critical nested-loop stack-discipline case. See
# core/doloop.asm's own header.
forth-smoke-p16:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p16.sym --lst=build/forth_smoke_p16.lst rom/forth_smoke_p16.asm
	mv forth_smoke_p16_rom0.bin build/forth_smoke_p16_rom0.bin

# Phase 17: FILL/AT-XY smoke ROM. FILL wraps kernel/graphics's own
# proven GFX_FILL flood-fill, picking up CURRENT_ATTR (Phase 15) like
# PLOT/LINE/CIRCLE. AT-XY moves core/print.asm's own PRINT_ROW/
# PRINT_COL directly. A real GFX_READ_PIXEL B/C-argument-order bug was
# caught in the test itself before trusting it -- see
# core/moregfx.asm's own header.
forth-smoke-p17:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p17.sym --lst=build/forth_smoke_p17.lst rom/forth_smoke_p17.asm
	mv forth_smoke_p17_rom0.bin build/forth_smoke_p17_rom0.bin

# Phase 18: F* (float multiply) smoke ROM. Writes its own 32-bit
# widening multiply and normalization pass (kernel/math's own multiply
# only gives a 16-bit truncated result) -- a real design mistake (a
# fixed-position window instead of real normalization) was caught by
# hand-tracing before ever assembling. See core/floatmul.asm's own
# header for the three hand-verified cases.
forth-smoke-p18:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p18.sym --lst=build/forth_smoke_p18.lst rom/forth_smoke_p18.asm
	mv forth_smoke_p18_rom0.bin build/forth_smoke_p18_rom0.bin

# Phase 19: F/ (float divide) smoke ROM. Scales the dividend up by 2^16
# before a 32-bit/16-bit restoring division, then reuses
# core/floatmul.asm's own F_NORMALIZE32 unchanged -- the same
# normalization problem F* already solved, just approached from the
# division side. See core/floatdiv.asm's own header for the three
# hand-verified cases (shrink path twice, grow path once).
forth-smoke-p19:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p19.sym --lst=build/forth_smoke_p19.lst rom/forth_smoke_p19.asm
	mv forth_smoke_p19_rom0.bin build/forth_smoke_p19_rom0.bin

# Phase 20: KEY smoke ROM. Simulates a keypress by writing
# KBD_LASTK/KBD_KEYHIT directly (the same sysvars a real ISR tick would
# latch) rather than needing a live interrupt running -- see
# core/key.asm's own header.
forth-smoke-p20:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p20.sym --lst=build/forth_smoke_p20.lst rom/forth_smoke_p20.asm
	mv forth_smoke_p20_rom0.bin build/forth_smoke_p20_rom0.bin

# Phase 21: error feedback smoke ROM. Replicates rom/forth_boot.asm's
# own real (now-updated) INTERPRET_UNKNOWN_WORD hook verbatim, proving
# an unknown word prints "?" + newline AND that the interpreter
# recovers to run a subsequent line normally afterward.
forth-smoke-p21:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p21.sym --lst=build/forth_smoke_p21.lst rom/forth_smoke_p21.asm
	mv forth_smoke_p21_rom0.bin build/forth_smoke_p21_rom0.bin

# Phase 22: F. (print a float) smoke ROM. Scales by 10000 and reuses
# core/floatdiv.asm's own F_UDIV32BY16 to split into integer/fractional
# decimal digits. A real register-clobbering bug (UDIV10 destroys B,
# which a first draft also used as its own outer loop counter) was
# caught on the very first real Fuse run -- see core/floatprint.asm's
# own header.
forth-smoke-p22:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p22.sym --lst=build/forth_smoke_p22.lst rom/forth_smoke_p22.asm
	mv forth_smoke_p22_rom0.bin build/forth_smoke_p22_rom0.bin

# Phase 23: decimal number literal parsing smoke ROM. DEFINEs
# DECIMAL_NUMBER_ENABLED before INCLUDEing core/interp.asm -- the
# opt-in gate that keeps every OTHER ROM in this project byte-for-byte
# unaffected (verified directly by diffing rebuilt binaries, not just
# reasoned about). See core/decimal.asm's own header.
forth-smoke-p23:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p23.sym --lst=build/forth_smoke_p23.lst rom/forth_smoke_p23.asm
	mv forth_smoke_p23_rom0.bin build/forth_smoke_p23_rom0.bin

# Phase 24: LEAVE and +LOOP, added to core/doloop.asm.
forth-smoke-p24:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p24.sym --lst=build/forth_smoke_p24.lst rom/forth_smoke_p24.asm
	mv forth_smoke_p24_rom0.bin build/forth_smoke_p24_rom0.bin

# Phase 25: ABS, SGN, MOD, SQRT, RND, RANDOMIZE -- thin wrappers around
# kernel/math/math.asm's own already-verified integer routines.
forth-smoke-p25:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p25.sym --lst=build/forth_smoke_p25.lst rom/forth_smoke_p25.asm
	mv forth_smoke_p25_rom0.bin build/forth_smoke_p25_rom0.bin

# Phase 26: ARRAY and CELLS -- a real Forth array, closing the
# BASIC-audit's DIM gap.
forth-smoke-p26:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p26.sym --lst=build/forth_smoke_p26.lst rom/forth_smoke_p26.asm
	mv forth_smoke_p26_rom0.bin build/forth_smoke_p26_rom0.bin

# Phase 27: S", TYPE, STRING, PLACE, COUNT, LEN, VAL -- real string
# handling, closing the BASIC-audit's biggest remaining gap.
forth-smoke-p27:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p27.sym --lst=build/forth_smoke_p27.lst rom/forth_smoke_p27.asm
	mv forth_smoke_p27_rom0.bin build/forth_smoke_p27_rom0.bin

# Phase 28: ACCEPT and INPUT -- line input, closing the last of the
# BASIC-audit's six real gaps. Uses real IM 1 interrupts (a scripted
# fake keyboard ISR), not simulated single-keypress sysvar writes --
# see rom/forth_smoke_p28.asm's own header for why.
forth-smoke-p28:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p28.sym --lst=build/forth_smoke_p28.lst rom/forth_smoke_p28.asm
	mv forth_smoke_p28_rom0.bin build/forth_smoke_p28_rom0.bin

# Phase 29: FSQRT -- float square root, the float-side counterpart to
# Phase 25's own integer SQRT.
forth-smoke-p29:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p29.sym --lst=build/forth_smoke_p29.lst rom/forth_smoke_p29.asm
	mv forth_smoke_p29_rom0.bin build/forth_smoke_p29_rom0.bin

forth-smoke-p30:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p30.sym --lst=build/forth_smoke_p30.lst rom/forth_smoke_p30.asm
	mv forth_smoke_p30_rom0.bin build/forth_smoke_p30_rom0.bin

forth-smoke-p31:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p31.sym --lst=build/forth_smoke_p31.lst rom/forth_smoke_p31.asm
	mv forth_smoke_p31_rom0.bin build/forth_smoke_p31_rom0.bin

forth-smoke-p32:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p32.sym --lst=build/forth_smoke_p32.lst rom/forth_smoke_p32.asm
	mv forth_smoke_p32_rom0.bin build/forth_smoke_p32_rom0.bin

forth-smoke-p33:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p33.sym --lst=build/forth_smoke_p33.lst rom/forth_smoke_p33.asm
	mv forth_smoke_p33_rom0.bin build/forth_smoke_p33_rom0.bin

forth-smoke-p34:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p34.sym --lst=build/forth_smoke_p34.lst rom/forth_smoke_p34.asm
	mv forth_smoke_p34_rom0.bin build/forth_smoke_p34_rom0.bin

forth-smoke-p35:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p35.sym --lst=build/forth_smoke_p35.lst rom/forth_smoke_p35.asm
	mv forth_smoke_p35_rom0.bin build/forth_smoke_p35_rom0.bin

forth-smoke-p36:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p36.sym --lst=build/forth_smoke_p36.lst rom/forth_smoke_p36.asm
	mv forth_smoke_p36_rom0.bin build/forth_smoke_p36_rom0.bin

forth-smoke-p37:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/forth_smoke_p37.sym --lst=build/forth_smoke_p37.lst rom/forth_smoke_p37.asm
	mv forth_smoke_p37_rom0.bin build/forth_smoke_p37_rom0.bin

check:
	python3 tools/check_asm.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py core/*.asm kernel/*/*.asm rom/*.asm

clean:
	rm -rf build
