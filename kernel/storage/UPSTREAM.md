# kernel/storage/tapeblock.asm: adopted code

`tapeblock.asm` is 2068-Leap-C's clean-room tape block I/O, adopted with its code unchanged (audit step S,
`docs/V2/STORAGE_SPEC.md` decision D1). Leap V2 adopted the same file the same way (2068-Leap `c2415f8`).

| | |
|---|---|
| Repository | 2068-Leap-C (local clone: `~/2068-Leap-C`), MIT, same author as this repository |
| File | `src/runtime/tapeblock.asm` |
| Commit | `d31d785da273d41812ed6204476116e4e5f364c6` (2026-10-22, the file's last change; 1.0.0-beta.2) |
| Code hash | `86c072a2b364cd78e4db9de6f2dd2e33e55e4111ee4aa12fd0f14852cf01d61e` |
| Code lines | 237 |
| Local modifications | the header comment (lines 1-23) is Forth's own; no code changes |
| Clean-room record | Leap-C `docs/TAPE_CLEANROOM.md`, `docs/TAPE_SIGNAL_SPEC.md` (not re-checked here) |

The code hash is sha256 over the file's code with comments and blank lines removed and whitespace collapsed, one
line per instruction (`tools/check_upstream.py`, in `make check`). The same hash comes from Leap-C's file at the
commit above and from Leap V2's `kernel/storage/tapeblock.asm`.

Rules:

- Do not edit the code here. A change made here is no longer covered by Leap-C's clean-room record. Change it in
  Leap-C, then copy the file's code over and record the new commit and hash in the same 2068-Forth commit.
- Comments may be edited; the hash ignores them.
- The callers' contract is `docs/V2/STORAGE_SPEC.md` section 3.
