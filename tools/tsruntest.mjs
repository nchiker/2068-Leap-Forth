#!/usr/bin/env node
// tools/tsruntest.mjs -- make test's `tsrun` suite: the release images on TSRun's emulator core, headless, for what
// ZEsarUX does not model. TSRun models both joystick connectors (A8 strobes joystick 1, A9 joystick 2, contacts
// active low) and the AY's port A direction (an output port reads back its latch, not the pins).
//
//   node tools/tsruntest.mjs [BUILD]        (default build; TSRun from $TSRUN, default ~/TSRun)
//
//   stick   STICK_READ after the mixer is set to $F8 (port A an output, as MIXER, SOUND and the boot sound leave
//           it), with each joystick's contacts set: each stick reads only its own connector, the directions in
//           bits 0-3, fire as 16, all four directions at once as 0, nothing pressed as 0
//
// Exit 0 when every case passes. EMULATOR LIMITS: TSRun's Z80, AY and joystick model; no hardware.

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const build = resolve(process.argv[2] || "build");
const tsrun = process.env.TSRUN || join(homedir(), "TSRun");
const M = await import(pathToFileURL(join(tsrun, "machine.js")).href);

const sym = {};
for (const line of readFileSync(join(build, "forth_boot.sym"), "utf8").split("\n")) {
    const x = /^(\S+): EQU 0x([0-9A-Fa-f]+)/.exec(line);
    if (x) sym[x[1]] = parseInt(x[2], 16);
}
const home = readFileSync(join(build, "forth_boot_rom0.bin"));
const exrom = readFileSync(join(build, "graphics_exrom.bin"));

// [device, joystick 1 contacts, joystick 2 contacts (active low: bit 7 fire, bits 0-3 directions), expected]
const CASES = [
    [1, 0xFF, 0xFF, 0], [2, 0xFF, 0xFF, 0],      // nothing pressed (an output port's latch $F8 read 1 for stick 2)
    [1, 0xFE, 0xFF, 1], [2, 0xFE, 0xFF, 0],      // joystick 1's bit 0: only STICK 1 sees it
    [1, 0x7F, 0xFF, 16],                          // joystick 1's fire
    [2, 0xFF, 0xF5, 10], [1, 0xFF, 0xF5, 0],     // joystick 2's bits 1 and 3: only STICK 2 sees them
    [2, 0xFF, 0x75, 26],                          // and its fire
    [1, 0xF0, 0xFF, 0],                           // all four directions at once: 0
];

let bad = 0;
for (const [n, j1, j2, want] of CASES) {
    const joy = Uint8Array.of(0xFF, 0xFF);
    const m = M.createMachine(new Uint8Array(9).fill(0x1F), joy);
    M.setHomeRom(m, home);
    M.setExRom(m, exrom);
    M.resetMachine(m);
    for (let i = 0; i < 200; i++) M.runFrame(m);             // to the prompt
    const sr = sym.STICK_READ;
    // di; ld a,7; out ($F5),a; ld a,$F8; out ($F6),a; ld hl,n; call STICK_READ; ld ($4100),hl; halt
    const stub = [0xF3, 0x3E, 0x07, 0xD3, 0xF5, 0x3E, 0xF8, 0xD3, 0xF6, 0x21, n, 0x00, 0xCD, sr & 0xFF, sr >> 8,
                  0x22, 0x00, 0x41, 0x76];
    stub.forEach((v, i) => m.bus.write(0x4000 + i, v));
    m.bus.write(0x4100, 0xAA); m.bus.write(0x4101, 0xAA);
    joy[0] = j1; joy[1] = j2;
    m.cpu.pc = 0x4000; m.cpu.halted = false;
    for (let i = 0; i < 3; i++) M.runFrame(m);
    const got = m.bus.read(0x4100) | (m.bus.read(0x4101) << 8);
    const what = `${n} STICK with joystick 1 $${j1.toString(16)}, joystick 2 $${j2.toString(16)}`;
    if (got !== want) { bad++; console.log(`tsrun: FAIL stick: ${what}: ${got}, expected ${want}`); }
}
console.log(`tsrun: ${CASES.length - bad}/${CASES.length} cases pass (stick)`);
process.exit(bad ? 1 : 0);
