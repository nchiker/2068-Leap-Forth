# 2068-Forth build.
#
# The ROM list, tools/rom_list.txt, is the single source of truth for which
# ROMs exist (its header documents the format). This Makefile parses it into
# per-kind variables; no smoke/test/visual/bench ROM name is typed here. Only
# the product, special and exrom kinds -- which need bespoke recipes or
# post-steps -- have explicit rules below, and a consistency check fails the
# parse if rom_list.txt and those rules ever disagree.
#
# Every ROM assembles with `--outprefix=build/`, which redirects the SAVEBIN
# lines inside rom/*.asm into build/ (the .asm files are untouched), so nothing
# is written to the repo root and no `mv` step is needed.
#
# Per-phase history comments for the forth_smoke*.asm ROMs were dropped from
# this file when it became list-driven: each rom/forth_smoke_pN.asm carries its
# own header with the phase description and pass/fail contract. (The old
# comments remain in git history.)

ROM_LIST := tools/rom_list.txt

# --- parse the ROM list ------------------------------------------------------
# stems of one kind, in list order (skips comments and blank lines)
rom_of_kind = $(shell awk -v k=$(1) '!/^[[:space:]]*\#/ && NF && $$2==k {print $$1}' $(ROM_LIST))
# forth_smoke_p3 -> forth-smoke-p3
dash = $(subst _,-,$(1))

ALL_STEMS    := $(shell awk '!/^[[:space:]]*\#/ && NF {print $$1}' $(ROM_LIST))
SMOKE_ROMS   := $(call rom_of_kind,smoke)
TEST_ROMS    := $(call rom_of_kind,test)
VISUAL_ROMS  := $(call rom_of_kind,visual)
BENCH_ROMS   := $(call rom_of_kind,bench)
PRODUCT_ROMS := $(call rom_of_kind,product)
SPECIAL_ROMS := $(call rom_of_kind,special)
EXROM_ROMS   := $(call rom_of_kind,exrom)

# Stems with explicit rules further down; must equal the list's
# product+special+exrom kinds, and every stem must have a known kind.
EXPLICIT_ROMS := main forth_boot forth_demo_blackjack forth_demo_gallery \
                 forth_lros graphics_exrom
ifeq ($(ALL_STEMS),)
$(error $(ROM_LIST) is missing or empty)
endif
ifneq ($(sort $(EXPLICIT_ROMS)),$(sort $(PRODUCT_ROMS) $(SPECIAL_ROMS) $(EXROM_ROMS)))
$(error $(ROM_LIST) product/special/exrom kinds do not match the explicit rules in the Makefile)
endif
ifneq ($(sort $(ALL_STEMS)),$(sort $(SMOKE_ROMS) $(TEST_ROMS) $(VISUAL_ROMS) $(BENCH_ROMS) $(EXPLICIT_ROMS)))
$(error $(ROM_LIST) contains a stem with an unknown kind)
endif

SMOKE_BINS  := $(patsubst %,build/%_rom0.bin,$(SMOKE_ROMS))
TEST_BINS   := $(patsubst %,build/%_rom0.bin,$(TEST_ROMS))
VISUAL_BINS := $(patsubst %,build/%_rom0.bin,$(VISUAL_ROMS))
BENCH_BINS  := $(patsubst %,build/%_rom0.bin,$(BENCH_ROMS))

# --- common pieces -----------------------------------------------------------
SJASM := tools/sjasmplus_strict.sh --outprefix=build/

# Coarse dependency tracking: any change under core/ kernel/ include/ (or to
# the assembler wrapper, or to data files the rom/*.asm sources INCBIN)
# rebuilds every ROM. Each ROM additionally depends on its own rom/<stem>.asm.
SRC_FILES := $(shell find core kernel include -type f | sort) \
             $(wildcard rom/*.fs rom/*.inc) tools/sjasmplus_strict.sh
SRC_STAMP := build/.src.stamp

.DEFAULT_GOAL := all

# --- target names ------------------------------------------------------------
# Phony aliases: forth_smoke_p3 -> forth-smoke-p3 (as before); the assemble-only
# kind=test ROMs are build-test-rect etc. (plain test-* names are now free);
# visual and bench ROMs get their dashed stem.
ALIASES := $(call dash,$(SMOKE_ROMS)) $(call dash,$(VISUAL_ROMS)) \
           $(call dash,$(BENCH_ROMS)) $(addprefix build-,$(call dash,$(TEST_ROMS))) \
           boot forth-boot forth-demo-blackjack forth-demo-gallery forth-lros \
           graphics-exrom forth-boot-cart forth-demo-blackjack-cart

define ALIAS_RULE
$(1): $(2)
endef
$(foreach r,$(SMOKE_ROMS) $(VISUAL_ROMS) $(BENCH_ROMS),\
  $(eval $(call ALIAS_RULE,$(call dash,$(r)),build/$(r)_rom0.bin)))
$(foreach r,$(TEST_ROMS),\
  $(eval $(call ALIAS_RULE,build-$(call dash,$(r)),build/$(r)_rom0.bin)))

# Everything `all` built before, plus the visual ROMs (assemble-only checks
# that were previously never built). Not forth-lros, not the bench ROMs.
ALL_IMAGES := build/forth_rom0.bin $(SMOKE_BINS) $(VISUAL_BINS) $(TEST_BINS) \
              build/forth_boot_rom0.bin build/forth_demo_blackjack_rom0.bin \
              build/forth_demo_gallery_rom0.bin build/graphics_exrom.bin \
              build/forth_boot.dck build/forth_demo_blackjack.dck

.PHONY: all product cart docs dist check clean test roms-for-test repro bench poweron audio cartdiff tapetest tapetol tapetol-fuse fusesave fusesave-cross harness edtest floattest shapetest \
        bench-roms $(ALIASES)

all: $(ALL_IMAGES)

build:
	mkdir -p $@

$(SRC_STAMP): $(SRC_FILES) | build
	touch $@

# --- generic rules: smoke, test, visual, bench -------------------------------
# build/<stem>_rom0.bin from rom/<stem>.asm; .sym/.lst land beside it.
$(SMOKE_BINS) $(TEST_BINS) $(VISUAL_BINS): build/%_rom0.bin: rom/%.asm $(SRC_STAMP) | build
	$(SJASM) --sym=build/$*.sym --lst=build/$*.lst $<

# Phase 2 benchmark drivers live in rom/bench/.
$(BENCH_BINS): build/%_rom0.bin: rom/bench/%.asm $(SRC_STAMP) | build
	$(SJASM) --sym=build/$*.sym --lst=build/$*.lst $<

# --- explicit rules: special / product / exrom -------------------------------

# Milestone 0: boot stub only (rom/main.asm SAVEBINs forth_rom0.bin).
boot: build/forth_rom0.bin
build/forth_rom0.bin: rom/main.asm $(SRC_STAMP) | build
	$(SJASM) --sym=build/main.sym --lst=build/main.lst $<

# The first real, live, bootable 2068-Forth product ROM -- not a smoke
# test. Boots, prints a banner, plays the startup sound (the product
# requirement tracked since Phase 4), and hands off to a real,
# interactive, keyboard-driven prompt (core/editor.asm's
# EDITOR_LOOP_LIVE). See docs/PROJECT_PLAN.md's Phase 9 section for two
# real bugs found only by a human actually typing at it.
forth-boot: build/forth_boot_rom0.bin
build/forth_boot_rom0.bin: rom/forth_boot.asm $(SRC_STAMP) | build
	$(SJASM) --sym=build/forth_boot.sym --lst=build/forth_boot.lst $<
	python3 -I tools/rom_identity.py --patch $@ build/forth_boot.sym
	python3 tools/build_stamp.py --write --target forth-boot

# Blackjack demo ROM: boots directly into a real, playable single-deck
# Blackjack game showcasing UDG (four hand-drawn suit glyphs), color
# (INK/PAPER/BORDER), and sound (BEEP/SOUND) together. See
# rom/forth_demo_blackjack.asm's own header for rules scope, screen
# layout, and how to play it in Fuse.
forth-demo-blackjack: build/forth_demo_blackjack_rom0.bin
build/forth_demo_blackjack_rom0.bin: rom/forth_demo_blackjack.asm $(SRC_STAMP) | build
	$(SJASM) --sym=build/forth_demo_blackjack.sym --lst=build/forth_demo_blackjack.lst $<
	python3 tools/build_stamp.py --write --target forth-demo-blackjack

# Shooting Gallery demo ROM: boots straight into a real, playable
# real-time arcade game showcasing RECT (colored screen bands), UDG
# glyph-block "sprites" (a blaster truck and three moving targets),
# and BEEP/SOUND (including a raw AY noise-burst explosion cue)
# together. Needs the graphics EXROM as ROM 1 alongside this ROM's own
# rom0 image (hence the graphics_exrom.bin prerequisite) -- see
# rom/forth_demo_gallery.asm's own header for how to play it and the
# platform/reliability findings behind its design.
forth-demo-gallery: build/forth_demo_gallery_rom0.bin
build/forth_demo_gallery_rom0.bin: rom/forth_demo_gallery.asm $(SRC_STAMP) build/graphics_exrom.bin | build
	$(SJASM) --sym=build/forth_demo_gallery.sym --lst=build/forth_demo_gallery.lst $<
	python3 tools/build_stamp.py --write --target forth-demo-gallery

# Generated from rom/forth_boot.asm's own GRAPHICS_HOME_TABLE -- see
# tools/export_home_symbols.py's own header and rom/graphics_exrom.asm's.
# Regenerated whenever its inputs change, never hand-edited or
# committed (build/ is gitignored).
build/graphics_home_table.inc: rom/forth_boot.asm tools/export_home_symbols.py | build
	python3 tools/export_home_symbols.py rom/forth_boot.asm $@

# EXROM-resident graphics services (chunk 5, $A000-$BFFF): RECT, POLYGON,
# POLYGON-FILL, SPRITE-DEFINE/SHOW/HIDE. See rom/graphics_exrom.asm's
# own header, and docs/PROJECT_PLAN.md's chunk-by-chunk audit for why
# chunk 5. Standalone 8K image, not concatenated with forth-boot's own
# source -- combine with build/forth_boot_rom0.bin for ZEsarUX the same
# way README.md's own "Try it" section already does for EXROM.
graphics-exrom: build/graphics_exrom.bin
build/graphics_exrom.bin: rom/graphics_exrom.asm build/graphics_home_table.inc $(SRC_STAMP) | build
	$(SJASM) --sym=build/graphics_exrom.sym --lst=build/graphics_exrom.lst $<
	python3 tools/build_stamp.py --write --target graphics-exrom

# LROS cartridge boot stub (EXPERIMENTAL) -- see rom/forth_lros.asm's own
# header. Deliberately NOT part of `all`: it's a separate, unverified
# distribution channel (DOCK cartridge), not a regression-tested phase of
# the Home-ROM product build. Pack with tools/pack_dck.sh afterward.
forth-lros: build/forth_lros_chunk0.bin
build/forth_lros_chunk0.bin: rom/forth_lros.asm $(SRC_STAMP) | build
	$(SJASM) --sym=build/forth_lros.sym --lst=build/forth_lros.lst $<
	python3 tools/build_stamp.py --write --target forth-lros

# The two ROMs people actually run: the live Forth and the Blackjack demo.
product: forth-boot forth-demo-blackjack

# DOCK-cartridge (LROS) builds of the same two ROMs: assembled with
# -DCARTRIDGE, which swaps the reset stub at $0000 for the 5-byte LROS
# header and adds a CART_START entry stub (see the IFDEF CARTRIDGE
# blocks in rom/forth_boot.asm). Every other byte is identical to the
# home-ROM build. tools/make_dck.py then wraps the raw image as a .dck
# for Fuse (--dock) and ZEsarUX; the raw *_cart.bin is what goes on an
# EPROM in a real cartridge. This covers only the base dictionary --
# RECT/POLYGON/POLYGON-FILL/sprites still need the graphics EXROM,
# which has no cartridge/DOCK path yet (see docs/lros_cartridge.md).
forth-boot-cart: build/forth_boot.dck
build/forth_boot_cart.bin: rom/forth_boot.asm $(SRC_STAMP) | build
	$(SJASM) -DCARTRIDGE --sym=build/forth_boot_cart.sym --lst=build/forth_boot_cart.lst $<
	python3 -I tools/rom_identity.py --patch $@ build/forth_boot_cart.sym
build/forth_boot.dck: build/forth_boot_cart.bin build/graphics_exrom.bin tools/make_dck.py
	python3 tools/make_dck.py build/forth_boot_cart.bin $@ build/graphics_exrom.bin
	python3 tools/build_stamp.py --write --target forth-boot-cart

forth-demo-blackjack-cart: build/forth_demo_blackjack.dck
build/forth_demo_blackjack_cart.bin: rom/forth_demo_blackjack.asm $(SRC_STAMP) | build
	$(SJASM) -DCARTRIDGE --sym=build/forth_demo_blackjack_cart.sym --lst=build/forth_demo_blackjack_cart.lst $<
build/forth_demo_blackjack.dck: build/forth_demo_blackjack_cart.bin tools/make_dck.py
	python3 tools/make_dck.py build/forth_demo_blackjack_cart.bin $@
	python3 tools/build_stamp.py --write --target forth-demo-blackjack-cart

cart: forth-boot-cart forth-demo-blackjack-cart

# PDF/DOCX renders of the user-facing docs -> build/docs/. Needs pandoc
# plus the weasyprint and python-docx Python packages; see
# tools/build_docs.sh's own header.
docs:
	tools/build_docs.sh

# The downloadable bundle -> dist/2068-Forth-<version>.zip: both product
# ROMs as home-ROM images and as DOCK cartridges (.dck), the graphics
# EXROM and its EightyOne/TS-Pico .dck wrapping, an EXROM placeholder,
# symbol listings, and the docs as Markdown, PDF, and DOCX. This is what
# the GitHub Actions workflow (.github/workflows/build.yml) attaches to
# every build and release.
dist: product cart graphics-exrom forth-lros docs
	tools/package_dist.sh

# --- tests and benchmarks (scripts live in tools/) ---------------------------
# Every self-checking ROM plus the three EXROM images tools/run_rom_tests.sh
# pairs them with (the script reads tools/rom_list.txt itself).
roms-for-test: $(SMOKE_BINS) $(TEST_BINS) build/graphics_exrom.bin \
               build/stock_shaped_exrom.bin build/exrom_a5.bin

# 8K of $00 (the stock-shaped EXROM placeholder); the script writes
# build/stock_shaped_exrom.bin relative to the repo root.
build/stock_shaped_exrom.bin: tools/make_exrom_placeholder.sh | build
	sh tools/make_exrom_placeholder.sh

# 8K of $A5, the EXROM image rom/test_exrom_isolation.asm expects.
build/exrom_a5.bin: | build
	head -c 8192 /dev/zero | tr '\000' '\245' > $@

# Every smoke/test ROM, then the power-on test (both always run; either failing fails the target).
test: roms-for-test build/forth_boot_rom0.bin
	tools/run_rom_tests.sh; r=$$?; python3 tools/poweron.py || r=1; exit $$r

# Boots the Home ROM from RAM and register power-on patterns and requires every byte the ROM defines to
# come out the same as from zeroed RAM (tools/poweron.py's header says what Forth defines). Own port
# range, 10820-10839.
poweron: build/forth_boot_rom0.bin build/stock_shaped_exrom.bin
	python3 tools/poweron.py

# What the emulated AY actually plays for BEEP: captures ZEsarUX's audio output while the product ROM plays a
# scale and compares each note's frequency with the formula and with the same period written through SOUND
# (tools/ay_audio.py's header). About two minutes, real-time; not part of `make test`. Ports 10880-10899.
audio: build/forth_boot_rom0.bin build/stock_shaped_exrom.bin
	python3 tools/ay_audio.py

# Differential test of the cartridge's EXROM paging (step R1, docs/V2/CARTRIDGE_EXROM_SPEC.md section 8): the same
# typed Forth program on the home build and on the cartridge build, on ZEsarUX and on TSRun's real core under Node
# (tools/cart_diff.py's header says what is compared). About 75 seconds (keys typed in emulated time, 4 ZEsarUX workers;
# --jobs N); not part of `make test`; needs a TSRun checkout (TSRUN_DIR, default ~/TSRun) and Node. Ports 10930-10949.
cartdiff: build/forth_boot_rom0.bin build/graphics_exrom.bin build/forth_boot.dck
	python3 tools/cart_diff.py --home-dir . --cart-dir .

# Tape oracle (audit step S, docs/V2/STORAGE_SPEC.md section 8): tapes played into ZEsarUX's real-tape input
# (realtape-open) and SAVE output captured as MIC edges, judged against the spec. About 5 minutes; not part of
# `make test`. Ports 10960-10979. TAPETEST_OLD=<build dir> runs it on another build instead.
tapetest: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/tapes.py --selftest
	python3 -I tools/tapetest.py --build $(or $(TAPETEST_OLD),build)

# Tape tolerance (T14): Leap-C's 71 distorted tapes on ZEsarUX. A report with one gate: no case the first build
# accepts may be refused by a later one. TAPETOL_BASE=<old build dir> compares against it. About 4 minutes per build.
# Ports 10980-10999.
tapetol: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/tapetol.py $(if $(TAPETOL_BASE),--build $(TAPETOL_BASE)) --build build --jobs 6

# The same 71 tapes on Fuse 1.9.1, headless (tools/tapetol.py --emu fuse): TZX direct recordings at 4 T a sample
# (ZEsarUX's are 224 T), tape traps off, auto-load off, no loader acceleration; keys typed through Fuse's keyboard
# matrix (tools/fusedrive.py, tools/fuse/fuseshim.c). Same report, same gate, TAPETOL_BASE as above. About 20 s a
# build; needs gcc and SDL2 headers (libsdl2-dev) for the shim, and /usr/local/bin/fuse 1.9.1 (FORTH_FUSE=<path>).
tapetol-fuse: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/tapetol.py --emu fuse $(if $(TAPETOL_BASE),--build $(TAPETOL_BASE)) --build build --jobs 6

# SAVE-TEXT and SAVE-LIB recorded by Fuse's tape deck, decoded by fuse-utils (tape2wav + audio2tape), compared with
# STORAGE_SPEC.md section 4, then loaded back into a fresh Fuse (tools/fusesave.py). FUSESAVE_BUILD=<dir> for
# another build. About 5 s (the last 2 s are the Home <-> cartridge half, also `make fusesave-cross`).
fusesave: build/forth_boot_rom0.bin build/graphics_exrom.bin build/forth_boot.dck
	python3 -I tools/fusesave.py --build $(or $(FUSESAVE_BUILD),build)

# Only the Home <-> DOCK cartridge half of fusesave (it is part of `make fusesave` too): SAVE-LIB on one build,
# LOAD-LIB on the other, both ways, plus a negative control with a patched ROM_IDENTITY. Needs the stock TS2068 ROMs
# (tools/fusedrive.py stock_roms: $$FORTH_STOCK_ROMS, ~/fuse-build/roms). About 2 s.
fusesave-cross: build/forth_boot_rom0.bin build/graphics_exrom.bin build/forth_boot.dck
	python3 -I tools/fusesave.py --cross --build $(or $(FUSESAVE_BUILD),build)

# Self-test of the symbol-based ZEsarUX harness every later oracle builds on (audit T11, tools/fharness.py's header):
# boot, snapshot restore, glyph table, screen reader, typed and matrix keys, memory assertions, and the worker pool
# (the same checks on 1 and on 3 emulators, which must agree). About 3 seconds; not part of `make test`.
# Ports 10900-10919.
harness: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/fharness.py --selftest

# Editor screen oracle (audit T12, tools/edtest.py's header): the current console editor characterised case by case (keys,
# wrapping, scrolling, the line store, RECALL retired, 64 columns, BREAK, colours), the redraw oracle (after every key the screen
# equals a full redraw) and the typing-cost baseline. About 45 s on 7 workers (3 minutes on 1); not part of `make test`. Ports
# 10900-10919. EDTEST_BUILD=<build dir> runs it on another build instead (an older one in a git worktree); the result
# is written to build/edtest.json. EDTEST_GROUP=old|new runs one group of cases (default both: the 19 that characterise the
# old console and step E's N1-N13, docs/V2/EDITOR_SPEC.md section 8).
edtest: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/edtest.py --build $(or $(EDTEST_BUILD),build) --group $(or $(EDTEST_GROUP),both)

# Float oracle (audit T13, docs/V2/FLOAT_SPEC.md section 13, tools/floattest.py's header): the ROM's float words, number
# parsing, F. and FS., errors and messages, integer * / MOD, RND and BEEP's frames checked against the bit-exact model
# (tools/fpforth.py on tools/fpmodel.py), and the speed table (T-states per word). Parallel emulators, ports 10840-10859.
# Written to build/floattest.json. FLOATTEST_BUILD=<build dir> runs it on another build (the old float implementation in a
# git worktree); FLOATTEST_GROUP=old|new|speed|all (default all). On the old build the old group passes and the new group
# fails (that run is the oracle's baseline). About 1 minute on 7 workers; not part of `make test`.
floattest: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/floattest.py --build $(or $(FLOATTEST_BUILD),build) --group $(or $(FLOATTEST_GROUP),all)

# FILL and CIRCLE oracle (audit T14, docs/V2/FILL_CIRCLE_SPEC.md section 9, tools/shapetest.py's header): the words FILL and
# CIRCLE checked against a Python model (screen, attributes, RAM outside the screen, return), and the speed table (T-states).
# Parallel emulators, ports 10860-10879. Written to build/shapetest.json. SHAPETEST_ARGS are extra arguments, e.g.
# "--group old", "--build <dir>" (another build in a git worktree) or "--compare <old build's shapetest.json>" (every speed case
# must be no slower). On the old build the old group passes and the new group fails (that run is the oracle's baseline).
# Not part of `make test`.
SHAPETEST_ARGS ?=
shapetest: build/forth_boot_rom0.bin build/graphics_exrom.bin
	python3 -I tools/shapetest.py --build build $(SHAPETEST_ARGS)

repro:
	tools/check_repro.sh

bench-roms: $(BENCH_BINS)

# Measures T-states to each benchmark's done-symbol -> build/bench.json and compares
# with tools/bench_baseline.json (the plan's Phase 2 baseline); a slowdown fails.
bench: bench-roms
	python3 tools/bench.py --baseline tools/bench_baseline.json

# Images the guards below measure (tools/budget.toml, tools/provenance.py): built first, so `make check`
# works from a clean tree.
CHECK_IMAGES := build/forth_boot_rom0.bin build/forth_boot_cart.bin build/forth_demo_blackjack_rom0.bin \
                build/forth_demo_blackjack_cart.bin build/forth_demo_gallery_rom0.bin build/graphics_exrom.bin

check: $(CHECK_IMAGES)
	python3 tools/check_asm.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/check_z80_opcodes.py core/*.asm kernel/*/*.asm rom/*.asm
	python3 tools/audit_layout.py
	# z80sim flag semantics + snapshot/replay (run in-directory: they import sim/snapshot as siblings)
	cd tools/z80sim && python3 -m unittest test_flags test_snapshot
	tools/check_test_list.sh
	# reserve ratchet: free space may not fall below the floors in tools/budget.toml (owner decision 1)
	python3 -I tools/budget.py
	# provenance: no 12-byte run shared with the stock ROMs except the recorded debt (exit 2: stock ROMs
	# not found in FORTH_STOCK_ROMS or ~/fuse-build/roms, scan skipped and said so)
	python3 -I tools/provenance.py; r=$$?; [ $$r -eq 0 ] || [ $$r -eq 2 ]
	python3 -I tools/check_upstream.py
	python3 -I tools/tapes.py --selftest
	# the product ROMs carry their own ROM_IDENTITY (STORAGE_SPEC.md D3)
	python3 -I tools/rom_identity.py --verify build/forth_boot_rom0.bin build/forth_boot.sym \
	    build/forth_boot_cart.bin build/forth_boot_cart.sym
	python3 -I tools/rom_identity.py --shared build/forth_boot_rom0.bin build/forth_boot.sym \
	    build/forth_boot_cart.bin build/forth_boot_cart.sym

clean:
	rm -rf build dist
