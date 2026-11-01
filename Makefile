# Leap-Forth build (CONTRIBUTING.md).
#   make              the images in build/: forth_boot_rom0.bin (HOME), graphics_exrom.bin (EXROM),
#                     forth_zesarux.bin (the two as one 24 KB file for ZEsarUX), graphics_exrom.dck, SHA256SUMS
#   make check        strict assembly, opcode and source checks, RAM layout guard, budgets, provenance, the
#                     adopted tape code, the tape tools' self-test, ROM_IDENTITY, the manual (its examples
#                     in step with tests/doc/, one entry per word of the ROM)
#   make budget       free bytes per image against the floors (budget.toml)
#   make cart         the DOCK cartridge for a stock TS2068 in build/cart/ (manual Part 6): the HOME image
#                     assembled with -DCARTRIDGE (tools/cart_check.py), the EXROM, forth_cart.dck (Forth, no
#                     program); PROG=<SAVE-LIB tape> START=<word> [UDG=<168-byte file>] also packs that program
#                     into build/cart/program.dck and program.bin (tools/forthcart.py)
#   make test         every suite in ZEsarUX (tools/run_tests.py): boot, the Forth tests in tests/, the editor,
#                     floats, FILL and CIRCLE, the benchmarks, power-on RAM, tape, the cartridge
#   make test-cart    the boot, Forth, editor, float and shape suites on the cartridge (build/cart) in the stock
#                     ROM's DOCK
#   make test-fast    the development subset (boot, Forth tests, editor, floats and shapes without speeds)
#   make tapetol      the tape receiver's tolerance on ZEsarUX (TAPETOL_BASE=<old build dir> compares)
#   make tapetol-fuse the same on Fuse 1.9.1, headless
#   make fusesave     SAVE-TEXT and SAVE-LIB on Fuse's tape deck, decoded and loaded back
#   make audio        what the emulated AY plays for BEEP (real time, about two minutes)
#   make repro        two clean builds (the cartridge too) must give identical hashes
#   make manual       the Word edition of the manual, docs/2068_Leap-Forth_Users_Manual.docx (docs/manual/*.md)
#   make docs, dist   the PDF/DOCX documents; the download bundle (CI)
.PHONY: all cart check budget inventory test test-cart test-fast tapetol tapetol-fuse fusesave audio repro manual docs dist clean

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

# The cartridge: the same sources with -DCARTRIDGE (kernel/bank/cart.asm); the release images do not change.
CART := build/cart
$(CART)/forth_boot_rom0.bin: $(SRC) build/forth_boot_rom0.bin build/graphics_exrom.bin tools/cart_check.py budget.toml
	mkdir -p $(CART)
	$(SJASM:build/=$(CART)/) -DCARTRIDGE --sym=$(CART)/forth_boot.sym --lst=$(CART)/forth_boot.lst rom/forth_boot.asm
	cp build/graphics_exrom.bin build/graphics_exrom.sym $(CART)/
	python3 -I tools/cart_check.py --patch build $(CART)

$(CART)/forth_cart.dck: $(CART)/forth_boot_rom0.bin tools/forthcart.py tools/tapes.py
	python3 -I tools/forthcart.py --cart $(CART) -o $@

cart: $(CART)/forth_cart.dck
ifdef PROG
	python3 -I tools/forthcart.py --cart $(CART) --lib $(PROG) --start $(START) $(if $(UDG),--udg $(UDG)) \
	    -o $(CART)/program.dck --bin $(CART)/program.bin
endif

check: all cart
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
	python3 -I tools/cart_check.py build $(CART)
	python3 -I tools/docexamples.py --check
	python3 -I tools/manualcheck.py build

budget: all
	python3 -I tools/budget.py

inventory: all
	python3 -I tools/rom_inventory.py
	python3 -I tools/rom_inventory.py --image exrom

test: all cart
	python3 -I tools/run_tests.py

test-cart: cart
	python3 -I tools/run_tests.py --build $(CART) --suite boot,forth,editor,float,shape

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
	tools/check_repro.sh all cart

manual:
	python3 tools/build_manual_docx.py

docs:
	tools/build_docs.sh

dist: all cart docs
	tools/package_dist.sh

clean:
	rm -rf build dist
