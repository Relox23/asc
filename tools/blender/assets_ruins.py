"""Ashen Remnant: broken skyscrapers and burnt-out cars."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rx, Ry, Rz, TAU

HALF = math.pi / 2


def faces(w, d):
    return [(T(0, -d / 2, 0), w, 0), (T(0, d / 2, 0) @ Rz(math.pi), w, 1), (T(-w / 2, 0, 0) @ Rz(-HALF), d, 2), (T(w / 2, 0, 0) @ Rz(HALF), d, 3)]


def rebar(bm, rng, p, n=5, spread=3.0):
    for _ in range(n):
        q = p + Vector((rng.uniform(-spread, spread), rng.uniform(-spread, spread), 0))
        tip = q + Vector((rng.uniform(-2.5, 2.5), rng.uniform(-2.5, 2.5), rng.uniform(4, 12)))
        kit.tube(bm, I, [q, (q + tip) / 2 + Vector((rng.uniform(-1, 1), 0, 0)), tip], [0.28, 0.25, 0.2], 4)


def skyscraper_glass(a):
    """60 x 60 glass tower, 300 tall at its highest corner, broken in a stepped way."""
    rng = random.Random(41)
    W = D = 60.0
    glass, conc, dark, steel = a.bm("Glass"), a.bm("Concrete"), a.bm("Dark"), a.bm("Rebar")
    heights = {(-1, -1): 300.0, (1, -1): 258.0, (-1, 1): 279.0, (1, 1): 216.0}
    for (sx, sy), h in heights.items():
        cx, cy = sx * W / 4, sy * D / 4
        kit.box(glass, I, (W / 2 - 0.4, D / 2 - 0.4, h), (cx, cy, h / 2))
        z = 6.0
        while z < h - 2:
            kit.box(conc, I, (W / 2 + 0.3, D / 2 + 0.3, 1.3), (cx, cy, z))
            z += 12
        kit.box(conc, I, (2.6, 2.6, h + 2), (sx * (W / 2 - 0.5), sy * (D / 2 - 0.5), h / 2 + 1))
        for _ in range(3):
            sw, sd, sh = rng.uniform(6, 13), rng.uniform(6, 13), rng.uniform(3, 14)
            kit.box(conc, I, (sw, sd, sh), (cx + rng.uniform(-8, 8), cy + rng.uniform(-8, 8), h + sh / 2 - 1))
        kit.box(conc, T(cx, cy, h + 1.5) @ Rx(rng.uniform(-0.5, 0.5)) @ Ry(rng.uniform(-0.5, 0.5)), (W * 0.32, D * 0.22, 1.3))
        rebar(steel, rng, Vector((cx, cy, h)), 6, 10)

    def height_at(face, x):
        sx = 1 if x > 0 else -1
        if face == 0:
            return heights[(sx, -1)]
        if face == 1:
            return heights[(-sx, 1)]
        if face == 2:
            return heights[(-1, -sx)]
        return heights[(1, sx)]

    for M, L, f in faces(W, D):
        for i in range(1, 10):
            x = -L / 2 + i * L / 10
            h = height_at(f, x) - 3
            kit.box(conc, M, (0.7, 0.7, h), (x, -0.25, h / 2))
        for _ in range(2):
            x = rng.uniform(-L / 3, L / 3)
            z = rng.uniform(20, height_at(f, x) - 30)
            kit.box(dark, M, (rng.uniform(9, 18), 0.6, rng.uniform(10, 22)), (x, -0.5, z))


def skyscraper_office(a):
    """Concrete office tower with setbacks and ribbon windows; its top is sheared off."""
    rng = random.Random(42)
    conc, dark, steel, iron = a.bm("Concrete"), a.bm("Dark"), a.bm("Rebar"), a.bm("Iron")
    for w, d, z0, z1 in ((70, 50, 0, 80), (60, 42, 80, 150)):
        kit.box(conc, I, (w, d, z1 - z0), (0, 0, (z0 + z1) / 2))
        z = z0 + 6
        while z < z1 - 3:
            kit.box(dark, I, (w + 0.3, d + 0.3, 4.2), (0, 0, z))
            z += 9
        kit.box(conc, I, (w + 1.6, d + 1.6, 1.6), (0, 0, z1))
    kit.wall_prism(conc, I, [(-25, 150), (-25, 196), (2, 196), (25, 166), (25, 150)], -17, 17)
    for z in (156, 165):
        kit.box(dark, I, (50.3, 34.3, 4.2), (0, 0, z))
    for k in range(6):
        t = k / 5
        p = Vector((2 + 23 * t, rng.uniform(-14, 14), 196 - 30 * t))
        kit.box(conc, T(*p) @ Ry(0.9) @ Rz(rng.uniform(-0.4, 0.4)), (rng.uniform(4, 8), rng.uniform(4, 9), rng.uniform(2, 4)))
        rebar(steel, rng, p, 3, 2)
    kit.tube(iron, I, [Vector((-14, 6, 196)), Vector((-13, 6, 214)), Vector((-9, 7, 226))], [0.9, 0.7, 0.4], 6)
    for M, L, f in faces(70, 50):
        x = rng.uniform(-L / 3, L / 3)
        kit.box(dark, M, (rng.uniform(10, 16), 0.6, rng.uniform(10, 18)), (x, -0.4, rng.uniform(15, 60)))


def skyscraper_frame(a):
    """Gutted concrete frame: floor plates on columns, partly collapsed."""
    rng = random.Random(43)
    conc, steel, glass = a.bm("Concrete"), a.bm("Rebar"), a.bm("Glass")
    W = 56.0
    fh = 11.0
    floors = 7
    grid = (-26, -9, 9, 26)
    for f in range(floors + 1):
        z = f * fh
        if f == 5:
            kit.box(conc, T(0, 6, z - 3) @ Rx(0.22), (W, W * 0.7, 1.4))
            kit.box(conc, I, (W, W * 0.3, 1.4), (0, -W * 0.35, z))
        elif f == floors:
            kit.box(conc, I, (W / 2, W, 1.4), (-W / 4, 0, z))
        else:
            kit.box(conc, I, (W, W, 1.4), (0, 0, z))
    for x in grid:
        for y in grid:
            top = floors * fh
            if x > 0 and rng.random() < 0.5:
                top = rng.uniform(3, 6) * fh
            kit.box(conc, I, (2.2, 2.2, top), (x, y, top / 2))
            if top < floors * fh:
                rebar(steel, rng, Vector((x, y, top)), 3, 0.6)
    for x in grid[:2]:
        kit.box(glass, I, (16, 0.5, fh - 1.6), (x + 8.5, -W / 2, fh / 2))
    for _ in range(10):
        f = rng.randint(1, 4)
        kit.box(conc, T(rng.uniform(-24, 24), rng.uniform(-24, 24), f * fh + 1) @ Rz(rng.uniform(0, TAU)) @ Rx(rng.uniform(-0.3, 0.3)),
                (rng.uniform(2, 5), rng.uniform(2, 5), rng.uniform(1, 2.5)))


def wheel(rubber, metal, M):
    kit.lathe(rubber, M @ Ry(HALF), [(0, -0.55), (1.45, -0.55), (1.6, 0), (1.45, 0.55), (0, 0.55)], 14)
    kit.lathe(metal, M @ Ry(HALF), [(0, -0.62), (0.85, -0.62), (0.85, 0.62), (0, 0.62)], 10)


def car_sedan(a):
    paint, glass, rubber, metal, rust, red = (a.bm(s) for s in ("Paint", "Glass", "Rubber", "Metal", "Rebar", "Lantern"))
    kit.box(paint, I, (7, 15, 2.6), (0, 0, 2.5), bevel=0.6)
    cabin = [(-3.6, 3.7), (-1.8, 6.1), (2.8, 6.1), (4.6, 3.7)]
    kit.wall_prism(glass, Rz(HALF), cabin, -3.0, 3.0)
    kit.box(paint, I, (6.3, 4.8, 0.4), (0, 0.5, 6.2), bevel=0.15)
    for s in (-3.05, 3.05):
        for p0, p1 in (((-3.6, 3.7), (-1.8, 6.1)), ((0.6, 3.7), (0.6, 6.1)), ((4.6, 3.7), (2.8, 6.1))):
            kit.beam(paint, I, Vector((s, p0[0], p0[1])), Vector((s, p1[0], p1[1])), 0.45, 0.45, Vector((1, 0, 0)))
    for x in (-3.2, 3.2):
        for y in (-4.6, 4.6):
            wheel(rubber, metal, T(x, y, 1.5))
    for y in (-7.6, 7.6):
        kit.box(metal, I, (7.2, 0.6, 0.9), (0, y, 1.8))
    for x in (-2.4, 2.4):
        kit.box(glass, I, (1.4, 0.2, 0.7), (x, -7.55, 2.9))
        kit.box(red, I, (1.2, 0.2, 0.6), (x, 7.55, 2.9))
    for p, s in (((-1.0, -5.0, 3.82), (2.6, 2.0)), ((2.0, 3.0, 3.82), (1.6, 2.4)), ((3.52, -1.0, 2.6), (0.08, 2.4))):
        kit.box(rust, I, (s[0], s[1], 0.08) if p[2] > 3 else (0.08, s[1], 1.6), p)


def car_van(a):
    paint, glass, rubber, metal, rust = (a.bm(s) for s in ("Paint", "Glass", "Rubber", "Metal", "Rebar"))
    kit.box(paint, I, (7.4, 16, 4.4), (0, 0, 3.4), bevel=0.5)
    kit.box(paint, I, (7.2, 11.6, 3.4), (0, 2, 7.2), bevel=0.4)
    kit.box(glass, I, (7.5, 9.4, 1.8), (0, 2.6, 7.4))
    kit.wall_prism(glass, Rz(HALF), [(-8.0, 5.6), (-5.6, 8.6), (-3.8, 8.6), (-3.8, 5.6)], -3.3, 3.3)
    kit.wall_prism(paint, Rz(HALF), [(-8.0, 5.4), (-5.4, 8.9), (-3.8, 8.9), (-3.8, 8.6), (-5.6, 8.6), (-8.0, 5.6)], -3.6, 3.6)
    for x in (-3.4, 3.4):
        for y in (-5.2, 5.2):
            wheel(rubber, metal, T(x, y, 1.5))
    for y in (-8.1, 8.1):
        kit.box(metal, I, (7.6, 0.6, 1.0), (0, y, 1.8))
    for x in (-2.6, 2.6):
        kit.tube(metal, I, [Vector((x, -2.5, 9.1)), Vector((x, 7.5, 9.1))], [0.18, 0.18], 5)
    kit.box(rust, I, (0.08, 5, 2), (3.74, -2, 3.6))
    kit.box(rust, I, (3, 4, 0.08), (-1, 4, 8.94))


ASSETS = [
    ("Skyscraper_A", skyscraper_glass),
    ("Skyscraper_B", skyscraper_office),
    ("Skyscraper_C", skyscraper_frame),
    ("Car_A", car_sedan),
    ("Car_B", car_van),
]
