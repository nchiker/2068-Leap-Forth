.PHONY: all boot forth-smoke forth-smoke-p3 forth-smoke-p4 forth-smoke-p5 check clean

all: boot forth-smoke forth-smoke-p3 forth-smoke-p4 forth-smoke-p5

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

check:
	python3 tools/check_asm.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py core/*.asm kernel/*/*.asm rom/*.asm

clean:
	rm -rf build
