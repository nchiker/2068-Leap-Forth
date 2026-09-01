.PHONY: all boot check clean

all: boot

# Milestone 0: boot stub only. Later milestones add their own targets here
# (dictionary/inner-interpreter smoke ROM, outer-interpreter smoke ROM,
# etc.) as they land — see docs/PROJECT_PLAN.md.
boot:
	mkdir -p build
	tools/sjasmplus_strict.sh --sym=build/main.sym --lst=build/main.lst rom/main.asm
	mv forth_rom0.bin build/forth_rom0.bin

check:
	python3 tools/check_asm.py kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py kernel/*/*.asm rom/*.asm

clean:
	rm -rf build
