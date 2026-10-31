# Leap-Forth build (CONTRIBUTING.md).
#   make              the images in build/: forth_boot_rom0.bin (HOME), graphics_exrom.bin (EXROM),
#                     forth_zesarux.bin (the two as one 24 KB file for ZEsarUX), graphics_exrom.dck, SHA256SUMS
#   make check        strict assembly, opcode and source checks, RAM layout guard, budgets, provenance, the
#                     adopted tape code, the tape tools' self-test, ROM_IDENTITY
#   make budget       free bytes per image against the floors (budget.toml)
#   make test         every suite in ZEsarUX (tools/run_tests.py): boot, the Forth tests in tests/, the editor,
#                     floats, FILL and CIRCLE, the benchmarks, power-on RAM, tape
#   make test-fast    the development subset (boot, Forth tests, editor, floats and shapes without speeds)
#   make tapetol      the tape receiver's tolerance on ZEsarUX (TAPETOL_BASE=<old build dir> compares)
#   make tapetol-fuse the same on Fuse 1.9.1, headless
#   make fusesave     SAVE-TEXT and SAVE-LIB on Fuse's tape deck, decoded and loaded back
#   make audio        what the emulated AY plays for BEEP (real time, about two minutes)
#   make repro        two clean builds must give identical hashes
#   make docs, dist   the PDF/DOCX documents; the download bundle (CI)
.PHONY: all check budget inventory test test-fast tapetol tapetol-fuse fusesave audio repro docs dist clean

SJASM := tools/sjasmplus_strict.sh --outprefix=build/
SRC := $(shell find core kernel include rom -name '*.asm' -o -name '*.inc' | sort) tools/sjasmplus_strict.sh
IMAGES := build/forth_boot_rom0.bin build/graphics_exrom.bin build/forth_zesarux.bin build/graphics_exrom.dck

all: build/SHA256SUMS

build/forth_boot_rom0.bin: $(SRC)
	mkdir -p build
	$(SJASM) --sym=build/forth_boot.sym --lst=build/forth_boot.lst rom/forth_boot.asm
	python3 -I tools/rom_identity.py --patch $@ build/forth_boot.sym

# The EXROM reads HOME's GRAPHICS_HOME_TABLE through an include generated from the HOME source.
build/graphics_home_table.inc: rom/forth_boot.asm tools/export_home_symbols.py
	mkdir -p build
	python3 tools/export_home_symbols.py rom/forth_boot.asm $@

build/graphics_exrom.bin: $(SRC) build/graphics_home_table.inc
	$(SJASM) --sym=build/graphics_exrom.sym --lst=build/graphics_exrom.lst rom/graphics_exrom.asm

build/forth_zesarux.bin: build/forth_boot_rom0.bin build/graphics_exrom.bin
	cat $^ > $@

build/graphics_exrom.dck: build/graphics_exrom.bin tools/make_dck.sh
	tools/make_dck.sh $< $@

build/SHA256SUMS: $(IMAGES)
	cd build && sha256sum $(notdir $(IMAGES)) > SHA256SUMS

check: all
	python3 tools/check_asm.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py core/*.asm kernel/*/*.asm rom/*.asm
	cd tools/z80sim && python3 -m unittest test_flags test_snapshot
	python3 -I tools/check_ram_layout.py
	python3 -I tools/check_ram_layout.py --negative
	python3 -I tools/budget.py
	python3 -I tools/provenance.py; r=$$?; [ $$r -eq 0 ] || [ $$r -eq 2 ]
	python3 -I tools/check_upstream.py
	python3 -I tools/tapes.py --selftest
	python3 -I tools/rom_identity.py --verify build/forth_boot_rom0.bin build/forth_boot.sym

budget: all
	python3 -I tools/budget.py

inventory: all
	python3 -I tools/rom_inventory.py
	python3 -I tools/rom_inventory.py --image exrom

test: all
	python3 -I tools/run_tests.py

test-fast: all
	python3 -I tools/run_tests.py --fast

tapetol: all
	python3 -I tools/tapetol.py $(if $(TAPETOL_BASE),--build $(TAPETOL_BASE)) --build build --jobs 6

tapetol-fuse: all
	python3 -I tools/tapetol.py --emu fuse $(if $(TAPETOL_BASE),--build $(TAPETOL_BASE)) --build build --jobs 6

fusesave: all
	python3 -I tools/fusesave.py --build build

audio: all
	python3 tools/ay_audio.py

repro:
	tools/check_repro.sh

docs:
	tools/build_docs.sh

dist: all docs
	tools/package_dist.sh

clean:
	rm -rf build dist
