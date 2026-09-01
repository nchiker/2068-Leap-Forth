.PHONY: all boot forth-smoke forth-smoke-p3 check clean

all: boot forth-smoke forth-smoke-p3

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

check:
	python3 tools/check_asm.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py core/*.asm kernel/*/*.asm rom/*.asm

clean:
	rm -rf build
