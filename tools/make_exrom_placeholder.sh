#!/bin/sh
# Generates build/stock_shaped_exrom.bin: an 8192-byte, all-$00 (Z80 NOP)
# EXROM placeholder for Fuse's --rom-ts2068-1.
#
# Why this exists: rom/forth_smoke.asm's own header (and
# docs/PROJECT_PLAN.md's Phase 2 section) documents a real, never-fully-
# root-caused Fuse 1.9.1 quirk from this project's own bring-up: a
# content-free, all-$FF 8K placeholder produced visibly different
# behavior than a real EXROM image, even for ROMs (like every ROM in
# this project) that never page EXROM in at all.
#
# Investigated further on 2026-09-04: reading Fuse 1.9.1's own real
# machines/ts2068.c + machine.c + peripherals/scld.c, and separately
# ZEsarUX's own machines/timex.c + cpu.c, found no content-dependent
# handling of the EXROM buffer in either emulator's actual ROM-loading
# or paging code -- both do a plain length-checked byte copy. ZEsarUX's
# own source additionally documents a real hardware fact: the stock
# TS2068's physical EXROM has its A13-A15 address lines undecoded, so
# the identical ROM content appears in every 8K chunk regardless of
# which one port $F4 selects -- chunk/slot number is content-irrelevant
# on real hardware too. The original $FF placeholder's misbehavior was
# most likely something other than EXROM byte content (e.g. a file-size
# mismatch during that historical bring-up), never fully confirmed.
#
# This script produces an inert but well-defined replacement anyway, as
# cheap insurance: $00 (Z80 NOP) instead of $FF (Z80 RST $38, a real
# instruction that jumps to the interrupt vector) is the strictly safer
# byte if anything ever executes from this buffer unexpectedly, even
# though nothing in this project's own ROMs ever pages EXROM in.
# Visually confirmed passing rom/forth_smoke_p50.asm in real Fuse under
# this file, identically to the old all-$FF build/blank_exrom.bin.

set -e
mkdir -p build
dd if=/dev/zero of=build/stock_shaped_exrom.bin bs=8192 count=1 status=none
