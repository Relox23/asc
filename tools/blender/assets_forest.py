"""Eloria Wildwood: trees, the Elderheart world tree, bushes and the cottage."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rx, Rz, TAU

HALF = math.pi / 2


def _lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------------------------- trees
def canopy_tree(a, seed, H, trunk_r, branches, puffs, puff_r, leaf_styles, roots=4):
    rng = random.Random(seed)
    bark = a.bm("Bark")
    fork = Vector((rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5), H * 0.46))
    trunk = []
    for i in range(7):
        t = i / 6
        p = _lerp(Vector((0, 0, -1.5)), fork, t)
        p += Vector((math.sin(t * 3 + seed) * 0.5, math.cos(t * 2 + seed) * 0.5, 0))
        trunk.append(p)
    kit.tube(bark, I, trunk, [trunk_r * (1.35 if i == 0 else 1.0) * (1 - 0.3 * i / 6) for i in range(7)], 9)
    for k in range(roots):
        ang = k / roots * TAU + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        kit.tube(bark, I, [d * trunk_r * 0.4 + Vector((0, 0, 2.2)), d * trunk_r * 1.6 + Vector((0, 0, 0.3)), d * trunk_r * 2.6 + Vector((0, 0, -0.8))],
                 [trunk_r * 0.5, trunk_r * 0.35, trunk_r * 0.15], 6)
    tips = []
    for b in range(branches):
        ang = b / branches * TAU + rng.uniform(-0.4, 0.4)
        d = Vector((math.cos(ang), math.sin(ang), rng.uniform(0.7, 1.2))).normalized()
        p1 = fork + d * H * rng.uniform(0.2, 0.28)
        d2 = (d + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.4, 0.4), 0.3))).normalized()
        p2 = p1 + d2 * H * rng.uniform(0.14, 0.2)
        kit.tube(bark, I, [fork, p1, p2], [trunk_r * 0.6, trunk_r * 0.42, trunk_r * 0.2], 6)
        tips += [p2, p1 + Vector((0, 0, H * 0.05))]
    tips.append(fork + Vector((0, 0, H * 0.42)))
    for k in range(puffs):
        base = tips[k % len(tips)]
        off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.5))) * puff_r * 0.5
        style = leaf_styles[k % len(leaf_styles)]
        kit.blob(a.bm(style), I, base + off, puff_r * rng.uniform(0.75, 1.15), 2, 0.28, 1.3, seed * 10 + k, (1, 1, 0.82))


def broadleaf_a(a):
    canopy_tree(a, 1, 30, 1.9, 4, 7, 8, ["Leaves", "Leaves", "LeavesLight"])


def broadleaf_b(a):
    canopy_tree(a, 2, 26, 1.7, 3, 6, 7.5, ["Leaves", "LeavesLight"])


def broadleaf_c(a):
    canopy_tree(a, 3, 36, 2.2, 5, 8, 8.5, ["Leaves", "Leaves", "LeavesDark"])


def blossom_a(a):
    canopy_tree(a, 4, 24, 1.6, 4, 7, 6.8, ["Blossom", "Blossom", "Leaves"])


def blossom_b(a):
    canopy_tree(a, 5, 21, 1.5, 3, 6, 6.4, ["Blossom", "Blossom", "Blossom", "LeavesLight"])


def silver_tree(a):
    rng = random.Random(6)
    pale, dark, leaves = a.bm("BarkPale"), a.bm("Black"), a.bm("LeavesLight")
    H = 42
    pts = [Vector((math.sin(t * 2.4) * 0.8, 0, -1.5 + t * (H + 1.5))) for t in (i / 8 for i in range(9))]
    kit.tube(pale, I, pts, [1.3 - 0.8 * i / 8 for i in range(9)], 8)
    for k in range(12):
        z = rng.uniform(2, H * 0.75)
        ang = rng.uniform(0, TAU)
        r = 1.3 - 0.8 * z / H
        x = math.sin(z / (H + 1.5) * 2.4) * 0.8
        kit.box(dark, T(x, 0, z) @ Rz(ang), (rng.uniform(0.8, 1.4), 0.3, rng.uniform(0.2, 0.4)), (0, -r - 0.05, 0))
    for k in range(4):
        z = H * (0.5 + k * 0.13)
        kit.tube(pale, I, [Vector((0, 0, z)), Vector((math.cos(k * 2.1) * 4, math.sin(k * 2.1) * 4, z + 3))], [0.4, 0.15], 5)
    for k in range(4):
        kit.blob(leaves, I, (rng.uniform(-1.5, 1.5), rng.uniform(-1.5, 1.5), H * (0.58 + k * 0.12)), 6.2 - k * 0.8, 2, 0.3, 1.4, k + 60, (0.85, 0.85, 1.25))


def ancient_tree(a):
    rng = random.Random(7)
    bark, moss = a.bm("Bark"), a.bm("Moss")
    H = 82
    trunk = [Vector((math.sin(i * 0.6) * 2, math.cos(i * 0.5) * 2, -3 + i * H * 0.62 / 6)) for i in range(7)]
    kit.tube(bark, I, trunk, [8.5 - i * 0.6 for i in range(7)], 12)
    for k in range(7):
        ang = k / 7 * TAU + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        pts = [d * 5 + Vector((0, 0, 9)), d * 10 + Vector((0, 0, 4)), d * 16 + Vector((0, 0, 0.5)), d * 21 + Vector((0, 0, -1.5))]
        kit.tube(bark if k % 2 else moss, I, pts, [3.6, 2.6, 1.6, 0.6], 7)
    top = trunk[-1]
    tips = [top + Vector((0, 0, 12))]
    for b in range(6):
        ang = b / 6 * TAU + rng.uniform(-0.3, 0.3)
        d = Vector((math.cos(ang), math.sin(ang), rng.uniform(0.25, 0.6))).normalized()
        p0 = trunk[rng.randint(4, 6)]
        p1 = p0 + d * rng.uniform(18, 24)
        p2 = p1 + (d + Vector((0, 0, 0.3))).normalized() * rng.uniform(10, 14)
        kit.tube(bark, I, [p0, p1, p2], [3.4, 2.2, 1.0], 7)
        tips += [p2, p1 + Vector((0, 0, 6))]
    for k, tip in enumerate(tips):
        kit.blob(a.bm("Leaves" if k % 3 else "LeavesDark"), I, tip + Vector((rng.uniform(-4, 4), rng.uniform(-4, 4), rng.uniform(0, 5))),
                 rng.uniform(15, 21), 2, 0.25, 1.2, 70 + k, (1, 1, 0.75))
    for k in range(10):
        tip = tips[k % len(tips)]
        p = tip + Vector((rng.uniform(-8, 8), rng.uniform(-8, 8), -8))
        ln = rng.uniform(14, 26)
        kit.tube(moss, I, [p, p + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), -ln * 0.5)), p + Vector((0, 0, -ln))], [0.45, 0.35, 0.2], 5)
    for k in range(5):
        p = trunk[rng.randint(1, 4)]
        ang = rng.uniform(0, TAU)
        kit.blob(moss, I, p + Vector((math.cos(ang) * 7, math.sin(ang) * 7, 0)), 2.6, 1, 0.3, 2, k + 90, (1, 1, 0.6))


def world_tree(a):
    """Elderheart: six strands twisting into one trunk, huge roots and a glowing crown."""
    rng = random.Random(8)
    bark, moss = a.bm("Bark"), a.bm("Moss")
    H = 230
    for s in range(6):
        a0 = s / 6 * TAU
        pts, radii = [], []
        for k in range(12):
            t = k / 11
            ang = a0 + t * TAU * 0.55
            r = 30 - t * 17
            pts.append(Vector((math.cos(ang) * r, math.sin(ang) * r, -4 + t * H)))
            radii.append(17 - t * 9)
        kit.tube(moss if s % 3 == 0 else bark, I, pts, radii, 10)
    kit.lathe(bark, I, [(0, -6), (44, -6), (40, 2), (34, 12), (30, 30), (0, 30)], 24)
    for r in range(11):
        ang = r / 11 * TAU + rng.uniform(-0.15, 0.15)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        L = rng.uniform(100, 130)
        pts = [d * 26 + Vector((0, 0, 24)), d * 50 + Vector((0, 0, 14)), d * 76 + Vector((0, 0, 2)), d * L + Vector((0, 0, -8))]
        kit.tube(moss if r % 2 else bark, I, pts, [9, 7, 4.4, 1.6], 9)
    tips = []
    for b in range(9):
        ang = b / 9 * TAU + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        p0 = Vector((0, 0, rng.uniform(150, 215)))
        p1 = p0 + d * rng.uniform(50, 70) + Vector((0, 0, rng.uniform(20, 40)))
        p2 = p1 + d * rng.uniform(40, 60) + Vector((0, 0, rng.uniform(5, 25)))
        kit.tube(bark, I, [p0, p1, p2], [7, 4.6, 2.2], 8)
        side = Vector((-d.y, d.x, 0)) * (1 if b % 2 else -1)
        p3 = p1 + side * rng.uniform(20, 30) + Vector((0, 0, 18))
        kit.tube(bark, I, [p1, p3], [3.4, 1.4], 6)
        tips += [p2, p1 + Vector((0, 0, 20)), p3]
    tips.append(Vector((0, 0, H + 20)))
    for k, tip in enumerate(tips):
        size = 75 if k == len(tips) - 1 else rng.uniform(30, 48)
        style = "LeavesGold" if k % 5 == 3 else ("LeavesLight" if k % 2 else "Leaves")
        kit.blob(a.bm(style), I, tip + Vector((rng.uniform(-6, 6), rng.uniform(-6, 6), rng.uniform(-2, 8))), size, 2, 0.24, 1.1, 100 + k, (1, 1, 0.78))
    glow = a.bm("GlowGreen")
    for k in range(14):
        tip = tips[k % len(tips)]
        p = tip + Vector((rng.uniform(-18, 18), rng.uniform(-18, 18), -rng.uniform(30, 44)))
        kit.tube(moss, I, [tip + Vector((0, 0, -14)), (p + tip) / 2 + Vector((rng.uniform(-2, 2), 0, 0)), p + Vector((0, 0, 1.6))], [0.5, 0.4, 0.3], 5)
        kit.sphere(glow, T(*p), 1.6, 10, 6)


def bush(a, seed, flowers):
    rng = random.Random(seed)
    for k in range(rng.randint(3, 4)):
        kit.blob(a.bm("Leaves" if k % 2 == 0 else "LeavesLight"), I, (rng.uniform(-2.5, 2.5), rng.uniform(-2.5, 2.5), rng.uniform(1.2, 2.4)),
                 rng.uniform(2.6, 3.8), 2, 0.3, 1.6, seed * 7 + k, (1, 1, 0.85))
    if flowers:
        for k in range(10):
            ang = rng.uniform(0, TAU)
            r = rng.uniform(2.6, 4.2)
            kit.sphere(a.bm("Blossom" if k % 2 else "Flower2"), T(math.cos(ang) * r, math.sin(ang) * r, rng.uniform(2.6, 4.6)), 0.5, 6, 3)


def bush_a(a):
    bush(a, 21, False)


def bush_b(a):
    bush(a, 22, True)


# --------------------------------------------------------------------------- cottage
def cottage(a):
    """Timber-framed cottage, 24 x 18, front (door) facing -Y."""
    rng = random.Random(30)
    W, D, Hw = 24.0, 18.0, 11.6
    z0 = 1.4
    granite, plaster, beam, wood = a.bm("Granite"), a.bm("Plaster"), a.bm("WoodDark"), a.bm("Wood")
    glow, shingle = a.bm("Glow"), a.bm("Shingle")
    kit.box(granite, I, (W + 2, D + 2, 2.6), (0, 0, 0.1), bevel=0.3)
    for k in range(18):
        side = k % 4
        t = rng.uniform(-0.45, 0.45)
        if side < 2:
            x, y = t * (W + 2), (-1 if side == 0 else 1) * (D / 2 + 1.05)
        else:
            x, y = (-1 if side == 2 else 1) * (W / 2 + 1.05), t * (D + 2)
        kit.box(granite, T(x, y, rng.uniform(-0.4, 0.8)) @ Rz(rng.uniform(-0.1, 0.1)), (rng.uniform(1.4, 2.6), rng.uniform(1.0, 1.6), rng.uniform(0.8, 1.2)), bevel=0.2)
    kit.box(plaster, I, (W, D, Hw), (0, 0, z0 + Hw / 2))
    top = z0 + Hw
    # timber framing
    for M, L in ((T(0, -D / 2, 0), W), (T(0, D / 2, 0) @ Rz(math.pi), W), (T(-W / 2, 0, 0) @ Rz(-HALF), D), (T(W / 2, 0, 0) @ Rz(HALF), D)):
        for x in (-L / 2 + 0.5, -L / 6, L / 6, L / 2 - 0.5):
            kit.box(beam, M, (1, 0.5, Hw), (x, -0.15, z0 + Hw / 2))
        for z in (z0 + 0.4, z0 + Hw * 0.5, top - 0.4):
            kit.box(beam, M, (L, 0.5, 0.8), (0, -0.2, z))
        for x0, x1 in ((-L / 2 + 0.5, -L / 6), (L / 6, L / 2 - 0.5)):
            kit.beam(beam, M, Vector((x0, -0.25, z0 + 0.8)), Vector((x1, -0.25, z0 + Hw * 0.5)), 0.7, 0.4, Vector((0, -1, 0)))
    # windows with mullions, shutters and flower boxes
    def win(M, flowers):
        kit.box(glow, M, (3.6, 0.2, 3.6), (0, -0.3, 0))
        kit.box(wood, M, (4.4, 0.5, 0.5), (0, -0.4, 2.0))
        kit.box(wood, M, (4.4, 0.5, 0.5), (0, -0.4, -2.0))
        kit.box(wood, M, (0.5, 0.5, 4.4), (-2.0, -0.4, 0))
        kit.box(wood, M, (0.5, 0.5, 4.4), (2.0, -0.4, 0))
        kit.box(beam, M, (0.25, 0.5, 3.6), (0, -0.45, 0))
        kit.box(beam, M, (3.6, 0.5, 0.25), (0, -0.45, 0))
        for s in (-1, 1):
            kit.box(wood, M @ T(s * 2.2, -0.4, 0) @ Rz(s * 0.5), (2.0, 0.3, 4.0), (s * 1.0, 0, 0))
        if flowers:
            kit.box(wood, M, (4.8, 1.4, 1.0), (0, -0.9, -2.6))
            for k in range(5):
                kit.sphere(a.bm("Blossom" if k % 2 else "Flower2"), M @ T(-1.8 + k * 0.9, -0.9, -1.9), 0.55, 6, 3)
    for x in (-W / 3, W / 3):
        win(T(x, -D / 2, z0 + 6.4), True)
        win(T(x, D / 2, z0 + 6.4) @ Rz(math.pi), False)
    win(T(-W / 2, 0, z0 + 6.4) @ Rz(-HALF), False)
    win(T(W / 2, 0, z0 + 6.4) @ Rz(HALF), False)
    # door with a little canopy
    kit.box(wood, I, (4.4, 0.4, 8), (0, -D / 2 - 0.25, z0 + 4))
    for k in range(4):
        kit.box(beam, I, (0.15, 0.5, 7.6), (-1.6 + k * 1.07, -D / 2 - 0.3, z0 + 4))
    kit.box(beam, I, (5.4, 0.6, 0.7), (0, -D / 2 - 0.3, z0 + 8.3))
    kit.sphere(a.bm("Gold"), T(1.4, -D / 2 - 0.6, z0 + 3.8), 0.3, 6, 3)
    kit.gable_roof(shingle, T(0, -D / 2 - 1.6, z0 + 8.8) @ Rz(HALF), 3.6, 6.4, 1.6, 0.35, 0.4)
    for s in (-1, 1):
        kit.beam(beam, I, Vector((s * 2.6, -D / 2, z0 + 7)), Vector((s * 2.6, -D / 2 - 2.6, z0 + 9.0)), 0.4, 0.4)
    lantern = T(-3.4, -D / 2 - 0.9, z0 + 9.4)
    kit.box(glow, lantern, (0.9, 0.9, 1.3))
    kit.box(beam, lantern, (1.2, 1.2, 0.3), (0, 0, 0.8))
    # steep gable roof (ridge along X) with shingle courses, gable ends and a dormer
    rise = 10.0
    kit.gable_roof(shingle, T(0, 0, top), W + 1.2, D, rise, 0.8, 1.8)
    th = math.atan2(rise, D / 2)
    for s in (-1, 1):
        normal = Vector((0, s * math.sin(th), math.cos(th)))
        for k in range(0, 7):
            f = k / 7
            p = Vector((0, s * D / 2 * (1 - f), top + rise * f)) + normal * 0.95
            kit.box(shingle, T(*p) @ Rx(-s * th), (W + 4.4, 0.6, 0.3))
    for x in (-W / 2, W / 2):
        kit.gable_end(plaster, I, D, rise, 0.6, x, top)
        kit.box(beam, I, (0.7, 0.5, rise - 1), (x + (0.3 if x > 0 else -0.3), 0, top + (rise - 1) / 2))
        kit.box(beam, I, (0.7, D * 0.5, 0.5), (x + (0.3 if x > 0 else -0.3), 0, top + rise * 0.5))
    kit.box(beam, I, (W + 4.4, 1.2, 1.2), (0, 0, top + rise + 0.6))
    dx = -5.0
    kit.box(plaster, I, (5, 6, 5), (dx, -D / 2 + 4.4, top + 4.8))
    kit.box(glow, I, (2.6, 0.2, 2.4), (dx, -D / 2 + 1.3, top + 4.6))
    kit.box(wood, I, (3.2, 0.4, 0.4), (dx, -D / 2 + 1.3, top + 3.2))
    kit.gable_roof(shingle, T(dx, -D / 2 + 4.2, top + 7.2) @ Rz(HALF), 6.6, 5.6, 2.4, 0.4, 0.6)
    # stone chimney
    kit.box(granite, I, (3.4, 3.4, 16), (8, 4.5, top + 6), bevel=0.2)
    kit.box(granite, I, (4.2, 4.2, 0.8), (8, 4.5, top + 14.2))


ASSETS = [
    ("Broadleaf_A", broadleaf_a),
    ("Broadleaf_B", broadleaf_b),
    ("Broadleaf_C", broadleaf_c),
    ("Blossom_A", blossom_a),
    ("Blossom_B", blossom_b),
    ("SilverTree", silver_tree),
    ("AncientTree", ancient_tree),
    ("WorldTree", world_tree),
    ("Bush_A", bush_a),
    ("Bush_B", bush_b),
    ("Cottage", cottage),
]
