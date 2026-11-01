#!/usr/bin/env node
// tools/cartrun.mjs -- run a Forth cartridge (.dck) on TSRun's emulator core with the stock TS2068 ROMs, headless:
// a second emulator beside ZEsarUX for tools/carttest.py (after ~/Projects/Leap-Cartridge's tests/harness.mjs).
//
//   node tools/cartrun.mjs --dck CART.dck --sym build/cart/forth_boot.sym [--frames 600] [--irq-at-entry]
//
// Runs to the stock ROM's hand-off (the first instruction at CART_ENTRY with chunk 0 DOCK), optionally takes an
// interrupt there (as if INT were active at that instruction, before its `di`), then on to the console's key wait
// (IO_READ_KEY with EDITOR_LOOP_LIVE.key_ret at SP). Prints one JSON object: the hand-off state (PC, IFF1, IM, SP,
// ports $F4 and $FF), whether the interrupt was taken and came back, whether and at which frame the prompt was
// reached, every write to ports $F4/$FF after the hand-off that leaves chunks 0-1 HOME or sets $FF bit 7 (EXROM, not
// DOCK), and the screen ($4000-$5AFF) as hex.
//
// TSRun is imported read-only from $TSRUN (default ~/TSRun), the stock ROMs from $TSRUN/roms/ts2068-{0,1}.rom.
// EMULATOR LIMITS: TSRun's Z80, ULA/SCLD and DOCK model; no hardware.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const args = process.argv.slice(2);
const opt = { frames: 600 };
for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a === "--dck") opt.dck = args[++i];
    else if (a === "--sym") opt.sym = args[++i];
    else if (a === "--frames") opt.frames = parseInt(args[++i], 10);
    else if (a === "--irq-at-entry") opt.irq = true;
    else { console.error("cartrun: unknown option " + a); process.exit(2); }
}
if (!opt.dck || !opt.sym) { console.error("cartrun: --dck and --sym are required"); process.exit(2); }

const tsrun = process.env.TSRUN || join(homedir(), "TSRun");
const M = await import(pathToFileURL(join(tsrun, "machine.js")).href);
const Z = await import(pathToFileURL(join(tsrun, "z80.js")).href);

const sym = {};
for (const line of readFileSync(resolve(opt.sym), "utf8").split("\n")) {
    const m = /^(\S+): EQU 0x([0-9A-Fa-f]+)/.exec(line);
    if (m) sym[m[1]] = parseInt(m[2], 16);
}

const m = M.createMachine(new Uint8Array(9).fill(0x1F), new Uint8Array(2).fill(0xFF));
const fail = (e) => { if (e) { console.error("cartrun: " + e); process.exit(2); } };
fail(M.setHomeRom(m, readFileSync(join(tsrun, "roms/ts2068-0.rom"))));
fail(M.setExRom(m, readFileSync(join(tsrun, "roms/ts2068-1.rom"))));
fail(M.insertDock(m, readFileSync(resolve(opt.dck))));
M.resetMachine(m);

let handedOff = false;
const outs = [];
const io = m.bus.ioWrite;
m.bus.ioWrite = (port, v) => {
    if (handedOff && ((port & 0xFF) === 0xF4 || (port & 0xFF) === 0xFF)) outs.push([port & 0xFF, v, m.cpu.pc]);
    io(port, v);
};

const hex = (v, w = 4) => "$" + v.toString(16).toUpperCase().padStart(w, "0");
const dock0 = () => (m.portF4 & 1) !== 0 && (m.portFF & 0x80) === 0;
const peek16 = (a) => m.bus.read(a) | m.bus.read((a + 1) & 0xFFFF) << 8;
let frame = 0;

// Instruction by instruction until pred() or the frame budget runs out (the HALT of a frame wait runs to its end).
function runUntil(pred, maxFrame) {
    for (; frame < maxFrame; frame++) {
        const end = m.frameStart + M.tStatesPerFrame;
        while (m.tstates < end) {
            if (pred()) return true;
            if (m.cpu.halted) { if (end - m.tstates < 4) break; Z.runZ80(m.cpu, m.bus, end - m.tstates, m); continue; }
            Z.runZ80(m.cpu, m.bus, 1, m);
        }
        M.runFrame(m);
    }
    return false;
}

const out = { dck: opt.dck };
if (!runUntil(() => m.cpu.pc === sym.CART_ENTRY && dock0(), 400)) {
    out.handoff = null;
} else {
    out.handoff = { pc: hex(m.cpu.pc), iff1: !!m.cpu.iff1, im: m.cpu.im, sp: hex(m.cpu.sp),
        portF4: hex(m.portF4, 2), portFF: hex(m.portFF, 2), frame };
    handedOff = true;
    if (opt.irq) {
        out.irqTaken = Z.irqZ80(m.cpu, m.bus) > 0;
        out.irqReturned = out.irqTaken && runUntil(() => m.cpu.pc === sym.CART_ENTRY, frame + 5);
    }
    const atPrompt = () => m.cpu.pc === sym.IO_READ_KEY && dock0() && peek16(m.cpu.sp) === sym["EDITOR_LOOP_LIVE.key_ret"];
    out.prompt = runUntil(atPrompt, frame + opt.frames);
    out.promptFrame = frame;
}
out.portF4 = hex(m.portF4, 2);
out.portFF = hex(m.portFF, 2);
out.badPaging = outs.filter(([p, v]) => (p === 0xF4 && (v & 3) !== 3) || (p === 0xFF && (v & 0x80) !== 0))
    .map(([p, v, pc]) => `out ${hex(p, 2)},${hex(v, 2)} at ${hex(pc)}`);
out.f4Values = [...new Set(outs.filter(([p]) => p === 0xF4).map(([, v]) => hex(v, 2)))];
out.screen = Buffer.from(Array.from({ length: 6912 }, (_, i) => m.bus.read(0x4000 + i))).toString("hex");
console.log(JSON.stringify(out));
