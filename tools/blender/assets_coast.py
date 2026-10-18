"""The Endless Shore: the old lighthouse and a shipwreck."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rz, TAU

HALF = math.pi / 2


def lighthouse(a):
    """Lighthouse facing the sea (-Y); the keeper's house is inland (+Y). Lamp at z = 84.8."""
    granite, white, red, iron, glass, glow = (a.bm(s) for s in ("Granite", "White", "Red", "Iron", "GlassClear", "Glow"))
    rng = random.Random(61)
    for k in range(5):
        ang = k / 5 * TAU + 0.3
        kit.blob(granite, I, (math.cos(ang) * 16, math.sin(ang) * 16, -2), rng.uniform(6, 9), 2, 0.25, 1.2, k + 61, (1.3, 1.1, 0.7))
    kit.lathe(granite, I, [(0, -4), (15.2, -4), (15.2, 4), (13, 8), (0, 8)], 32)

    def r(z):
        return 11 - 3 * (z - 8) / 72

    for k in range(6):
        za, zb = 8 + 12 * k, 20 + 12 * k
        kit.lathe(white if k % 2 == 0 else red, I, [(0, za), (r(za), za), (r(zb), zb), (0, zb)], 28)
    kit.niche(a.bm("Door"), T(0, r(10) - 0.1, 8) @ Rz(math.pi), 4.2, 7.4, 0.3, False, 6)
    kit.arch_frame(granite, T(0, r(10) - 0.2, 8) @ Rz(math.pi), 4.2, 7.4, 0.8, 1.0, False, 6)
    for z, ang in ((30, math.pi), (50, math.pi + 1.2), (66, math.pi - 1.2)):
        kit.niche(a.bm("Dark"), Rz(ang) @ T(0, -r(z) + 0.1, z), 2.0, 3.4, 0.25, False, 5)
    kit.lathe(iron, I, [(0, 80), (12.6, 80), (12.6, 81.2), (0, 81.2)], 32)
    for k in range(16):
        ang = k / 16 * TAU
        kit.box(iron, T(math.cos(ang) * 12.1, math.sin(ang) * 12.1, 82.7), (0.35, 0.35, 3.0))
    ring = [Vector((math.cos(k / 24 * TAU) * 12.1, math.sin(k / 24 * TAU) * 12.1, 84.2)) for k in range(25)]
    kit.tube(iron, I, ring, [0.25] * 25, 5, caps=False)
    kit.lathe(glass, I, [(0, 81.2), (6.4, 81.2), (6.4, 88.4), (0, 88.4)], 16)
    for k in range(8):
        ang = k / 8 * TAU
        kit.box(iron, T(math.cos(ang) * 6.5, math.sin(ang) * 6.5, 84.8), (0.45, 0.45, 7.2))
    kit.sphere(glow, T(0, 0, 84.8), 2.4, 12, 6)
    kit.lathe(red, I, [(0, 88.2), (7.4, 88.2), (7.4, 88.8), (5.5, 91.2), (2, 93.6), (0, 94.2)], 28)
    kit.sphere(iron, T(0, 0, 95), 1.2, 10, 5)
    kit.tube(iron, I, [Vector((0, 0, 95)), Vector((0, 0, 100))], [0.2, 0.15], 5)
    # keeper's cottage inland
    hy = 32.0
    kit.box(granite, I, (17, 13, 1.4), (0, hy, 0.2))
    kit.box(white, I, (16, 12, 10), (0, hy, 5.6))
    kit.gable_roof(red, T(0, hy, 10.6), 16, 12, 5, 0.6, 1.2)
    for x in (-8, 8):
        kit.gable_end(white, T(0, hy, 0), 12, 5, 0.6, x, 10.6)
    kit.box(granite, I, (2.4, 2.4, 9), (5, hy + 3, 14), bevel=0.2)
    for x in (-4, 4):
        kit.box(glow, I, (2.6, 0.2, 2.6), (x, hy - 6.05, 5.6))
        kit.box(a.bm("Wood"), I, (3.2, 0.3, 0.4), (x, hy - 6.15, 4.1))
    kit.box(a.bm("Door"), I, (3, 0.3, 6), (0, hy + 6.05, 4))


def shipwreck(a):
    """Broken wooden ship, bow toward -Y, roughly 64 long."""
    rng = random.Random(62)
    hull, deck_wood, rib, canvas, rope = (a.bm(s) for s in ("Hull", "Wood", "WoodDark", "Canvas", "Rope"))
    stations = [30 - 64 * i / 13 for i in range(14)]

    def section(y):
        t = (y + 34) / 64
        width = 10 * math.sin(min(t * 1.6 + 0.08, 1) * HALF)
        depth = 8 + 2 * t
        deck = 10 + (1 - t) * 2.2
        return [(-math.cos(math.pi * k / 8) * width, deck - math.sin(math.pi * k / 8) * depth) for k in range(9)]

    secs = [section(y) for y in stations]
    for k in range(8):
        left = [Vector((s[k][0], y, s[k][1])) for s, y in zip(secs, stations)]
        right = [Vector((s[k + 1][0], y, s[k + 1][1])) for s, y in zip(secs, stations)]
        if k in (1, 2, 3):
            kit.ribbon(hull, I, left[:6], right[:6], gap=0.5)
            kit.ribbon(hull, I, left[9:], right[9:], gap=0.5)
        else:
            kit.ribbon(hull, I, left, right, gap=0.5)
    for j in (6, 7, 8):
        pts = [Vector((x, stations[j], z)) for x, z in secs[j]]
        kit.tube(rib, I, pts, [0.6] * len(pts), 5)
    kit.tube(rib, I, [Vector((0, y, s[4][1] - 0.4)) for s, y in zip(secs, stations)], [0.9] * len(stations), 6)
    for i, y in enumerate(stations[2:-2]):
        s = section(y)
        w = abs(s[0][0])
        x = -w + 1
        while x < w - 1:
            if rng.random() < 0.72:
                kit.box(deck_wood, I, (1.3, 64 / 13 + 0.2, 0.4), (x, y, s[0][1] - 0.2))
            x += 1.45
    kit.tube(deck_wood, I, [Vector((0, -4, 10)), Vector((0.8, -5, 26)), Vector((1.6, -6, 34))], [1.1, 0.9, 0.7], 8)
    kit.tube(deck_wood, I, [Vector((-9, -5.2, 28)), Vector((10, -6, 30))], [0.45, 0.45], 6)
    left = [Vector((-8 + i * 2, -5.4, 29 - 0.15 * i)) for i in range(10)]
    right = [Vector((p.x + rng.uniform(-0.4, 0.4), p.y - rng.uniform(0.2, 0.8), p.z - rng.uniform(6, 13))) for p in left]
    kit.ribbon(canvas, I, left, right, gap=0.08)
    kit.tube(deck_wood, I, [Vector((0, -33, 12.5)), Vector((0, -44, 17))], [0.8, 0.4], 6)
    for p, q in ((Vector((1.6, -6, 33)), Vector((9, 8, 10))), (Vector((1.6, -6, 33)), Vector((-8, 10, 10))), (Vector((0.8, -5, 26)), Vector((0, -40, 15)))):
        kit.tube(rope, I, [p, (p + q) / 2 - Vector((0, 0, 1.5)), q], [0.12] * 3, 4)
    for k in range(3):
        M = T(rng.uniform(-14, 14), rng.uniform(-30, 30), 0)
        kit.lathe(deck_wood, M, [(0, 0), (1.3, 0), (1.6, 1.4), (1.65, 2), (1.6, 2.6), (1.3, 4), (0, 4)], 12)


ASSETS = [
    ("Lighthouse", lighthouse),
    ("Shipwreck", shipwreck),
]
