# z80sim: vendored copy

`tools/z80sim/` carries a copy of the standalone simulator, which is the **authoritative source**:

| | |
|---|---|
| Repository | https://github.com/nchiker/z80sim (local clone: `~/z80sim`) |
| Version used here | commit `13c9bce9901e7c6dbce28840a232b4580fa8d953` (`main`, 2026-10-27) |
| Vendored files | `sim.py`, `extract_routine.py`, `snapshot.py`, `replay_snapshot.py`, `test_flags.py`, `test_snapshot.py`, `README.md` (byte-identical to that commit, except README's LICENSE link, which points at this repository's `../../LICENSE`) |
| Not vendored | upstream `LICENSE` (identical to this repository's root `LICENSE`, MIT, Charlie Day), `.gitignore`, `__pycache__/` |
| This repo only | this file |
| Local modifications | none |

Rules:

- Change the simulator **in the z80sim repository**, test it there (`python3 -m unittest -v test_flags test_snapshot`),
  commit, then sync it here. Do not edit the vendored files in this directory.
- Sync, then run `make check` (it runs `test_flags`/`test_snapshot` from `tools/z80sim`), and update the
  commit above in the same 2068-Forth commit:

  ```sh
  cd ~/z80sim && git status --short && git rev-parse HEAD   # clean tree; the commit to record above
  for f in sim.py extract_routine.py snapshot.py replay_snapshot.py test_flags.py test_snapshot.py README.md; do
      cp ~/z80sim/$f ~/2068-forth/tools/z80sim/$f
  done
  sed -i 's#(LICENSE)#(../../LICENSE)#' ~/2068-forth/tools/z80sim/README.md   # restore the local LICENSE link
  ```

  If `~/z80sim` is not clean or not at the target commit, export from the commit instead:
  `git -C ~/z80sim show <commit>:<file> > tools/z80sim/<file>`.
- Check that the vendored files still match the recorded commit (clean z80sim clone checked out at it):
  `for f in sim.py extract_routine.py snapshot.py replay_snapshot.py test_flags.py test_snapshot.py; do cmp ~/z80sim/$f tools/z80sim/$f; done`
  (no output means identical; README differs only on its LICENSE link line).
- The previous copy here was a September snapshot of 2068-Leap's `sim.py` (1,033 lines) with no Forth-specific
  changes; this refresh replaces it wholesale.
