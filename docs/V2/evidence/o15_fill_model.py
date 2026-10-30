#!/usr/bin/env python3
"""O15 FILL design model (docs/V2/FILL_CIRCLE_SPEC.md section 4.5): plane A (0 = fillable), spans, one seed per run on
the rows above/below, a bounded seed stack, and the recovery sweep when a push is dropped.  Checked against a
breadth-first fill.  Run: python3 -I docs/V2/evidence/o15_fill_model.py (about 1 minute)."""
# above/below, a bounded seed stack and a recovery sweep when a push is dropped.  Checked against a BFS.
import random, collections, sys
W, H = 256, 192
def bfs(scr, sx, sy):
    t = scr[sy][sx]; seen = {(sx, sy)}; q = collections.deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        for nx, ny in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
            if 0 <= nx < W and 0 <= ny < H and (nx,ny) not in seen and scr[ny][nx] == t:
                seen.add((nx,ny)); q.append((nx,ny))
    return seen
def newfill(scr, sx, sy, cap):
    t = scr[sy][sx]
    A = [[0 if p == t else 1 for p in row] for row in scr]
    orig = [r[:] for r in A]                                 # reference plane (B XOR K)
    st = []; ovf = [False]; peak = [0]; pushes = [0]
    def push(x, y):
        if len(st) >= cap: ovf[0] = True; return False
        st.append((x, y)); pushes[0] += 1; peak[0] = max(peak[0], len(st)); return True
    def scan(y, lx, rx):
        prev = False
        for x in range(lx, rx + 1):
            f = A[y][x] == 0
            if f and not prev: push(x, y)
            prev = f
    push(sx, sy); sweeps = 0
    while True:
        while st:
            x, y = st.pop()
            if A[y][x]: continue
            lx = x
            while lx > 0 and A[y][lx-1] == 0: lx -= 1
            rx = x
            while rx < W-1 and A[y][rx+1] == 0: rx += 1
            for i in range(lx, rx+1): A[y][i] = 1
            if y > 0: scan(y-1, lx, rx)
            if y < H-1: scan(y+1, lx, rx)
        if not ovf[0]: break
        ovf[0] = False; sweeps += 1
        painted = lambda x, y: A[y][x] == 1 and orig[y][x] == 0
        for y in range(H):
            prev = False
            for x in range(W):
                cand = A[y][x] == 0 and ((y > 0 and painted(x, y-1)) or (y < H-1 and painted(x, y+1)))
                if cand and not prev:
                    if not push(x, y): break
                prev = A[y][x] == 0 and cand
            if ovf[0]: break
    filled = {(x, y) for y in range(H) for x in range(W) if A[y][x] == 1 and orig[y][x] == 0}
    return filled, peak[0], sweeps, pushes[0]
def blank(): return [[0]*W for _ in range(H)]
def shapes():
    s = blank(); yield "blank", s, (100, 100)
    s = blank()
    for x in range(40, 200): s[30][x] = s[150][x] = 1
    for y in range(30, 151): s[y][40] = s[y][199] = 1
    yield "box", s, (100, 100)
    s = blank()
    for y in range(H):
        for x in range(W):
            if (x - 128)**2 + (y - 96)**2 <= 50*50: s[y][x] = 1
    yield "solid disc recolour", s, (128, 96)
    s = blank()                                              # serpentine: walls on odd columns, open at the
    for x in range(1, W, 2):                                 # bottom (x % 4 == 1) or the top (x % 4 == 3)
        for y in (range(0, H - 1) if x % 4 == 1 else range(1, H)): s[y][x] = 1
    yield "serpentine", s, (0, 0)
    s = blank(); r = random.Random(7)
    for _ in range(6000): s[r.randrange(H)][r.randrange(W)] = 1
    yield "noise 6000", s, (128, 96)
    s = blank(); r = random.Random(9)
    for _ in range(14000): s[r.randrange(H)][r.randrange(W)] = 1
    yield "noise 14000", s, next((x, y) for y in range(H) for x in range(W) if s[y][x] == 0)
    s = blank()
    for y in range(H):
        for x in range(W):
            s[y][x] = 1 if (x // 3 + y // 3) % 2 == 0 and (x % 3 == 0 or y % 3 == 0) else 0
    yield "lattice", s, (1, 1)
for cap in (512, 64, 8):
    for name, s, (sx, sy) in shapes():
        if s[sy][sx] not in (0, 1): continue
        ref = bfs(s, sx, sy)
        got, peak, sweeps, pushes = newfill(s, sx, sy, cap)
        print("cap %4d %-20s ref %6d got %6d %s peak %4d sweeps %3d pushes %6d" % (cap, name, len(ref), len(got), "OK " if got == ref else "BAD", peak, sweeps, pushes))
