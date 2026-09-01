.PHONY: all boot forth-smoke forth-smoke-p3 forth-smoke-p4 forth-smoke-p5 forth-smoke-p6 forth-smoke-p7 forth-smoke-p8 forth-smoke-p8b forth-smoke-p9 forth-smoke-p10 forth-smoke-p11 forth-smoke-p12 forth-smoke-p13 forth-smoke-p14 forth-smoke-p15 forth-smoke-p16 forth-boot check clean

all: boot forth-smoke forth-smoke-p3 forth-smoke-p4 forth-smoke-p5 forth-smoke-p6 forth-smoke-p7 forth-smoke-p8 forth-smoke-p8b forth-smoke-p9 forth-smoke-p10 forth-smoke-p11 forth-smoke-p12 forth-smoke-p13 forth-smoke-p14 forth-smoke-p15 forth-smoke-p16 forth-boot

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

check:
	python3 tools/check_asm.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py core/*.asm kernel/*/*.asm rom/*.asm

clean:
	rm -rf build
