"""Shirayuki Vale: snowy pines, bare trees, minka houses, torii, stone lantern and Ryuudou Temple."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rx, Rz, TAU

HALF = math.pi / 2


# --------------------------------------------------------------------------- trees
def pine(a, seed, H, tiers, cover, slender=1.0):
    rng = random.Random(seed)
    kit.tube(a.bm("Bark"), I, [Vector((0, 0, -2)), Vector((0, 0, H * 0.8))], [H * 0.034, H * 0.012], 8)
    needles, snow = a.bm("LeavesDark"), a.bm("Snow")
    for k in range(tiers):
        t = k / max(tiers - 1, 1)
        z = H * (0.13 + 0.64 * t)
        r = H * (0.34 - 0.25 * t) * slender
        h = H * (0.34 - 0.1 * t)
        pts = rng.choice((9, 10, 11))
        M = Rz(rng.uniform(0, TAU))
        kit.star_cone(needles, M, r, h, pts, 0.62, r * 0.2, z, 0.1, rng)
        c = min(cover * (0.8 + 0.3 * t), 0.95)
        kit.star_cone(snow, M, r * c * 1.06, h * c, pts, 0.62, r * 0.2 * c, z + h * (1 - c) + 0.15, 0.0, rng, underside=False)
    kit.star_cone(snow, I, H * 0.035, H * 0.09, 5, 0.6, 0.0, H * 0.92, 0.0, rng)


def pine_a(a):
    pine(a, 31, 50, 6, 0.45)


def pine_b(a):
    pine(a, 32, 46, 6, 0.85)


def pine_c(a):
    pine(a, 33, 60, 7, 0.6, 0.78)


def bare_tree(a):
    rng = random.Random(34)
    bark, snow = a.bm("Bark"), a.bm("Snow")

    def branch(p, d, L, r, depth):
        q = p + d * L
        mid = (p + q) / 2 + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), 0)) * L * 0.08
        kit.tube(bark, I, [p, mid, q], [r, r * 0.85, r * 0.65], 6)
        if r > 0.45 and d.z < 0.95:
            up = Vector((0, 0, r * 0.8))
            kit.tube(snow, I, [p + up, mid + up, q + up], [r * 0.55, r * 0.5, r * 0.35], 5)
        if depth > 0:
            for _ in range(3 if depth > 1 else 2):
                nd = (d + Vector((rng.uniform(-0.9, 0.9), rng.uniform(-0.9, 0.9), rng.uniform(0.0, 0.6)))).normalized()
                branch(q, nd, L * 0.65, r * 0.6, depth - 1)

    branch(Vector((0, 0, -2)), Vector((0, 0, 1)), 16, 1.5, 3)


# --------------------------------------------------------------------------- small structures
def torii(a):
    """Myojin torii: pillars 16 apart, people walk through along Y."""
    verm, black, gold = a.bm("Vermilion"), a.bm("Black"), a.bm("Gold")
    W, H = 16.0, 18.0
    for x in (-W / 2, W / 2):
        kit.lathe(verm, T(x, 0, 0), [(0, 0), (0.85, 0), (0.74, H * 0.95), (0, H * 0.95)], 16)
        kit.lathe(black, T(x, 0, 0), [(0, -1), (1.15, -1), (1.15, 1.2), (0.9, 1.5), (0, 1.5)], 16)
    kit.box(verm, I, (W + 4.6, 1.0, 1.4), (0, 0, H * 0.74))
    for x in (-W / 2 - 1.3, W / 2 + 1.3):
        kit.box(verm, I, (0.6, 1.3, 1.7), (x, 0, H * 0.74))
    kit.box(verm, I, (1.2, 0.9, H * 0.15), (0, 0, H * 0.83))
    kit.box(gold, I, (2.9, 0.4, 3.5), (0, -0.4, H * 0.84))
    kit.box(black, I, (2.5, 0.5, 3.1), (0, -0.55, H * 0.84))
    kit.box(verm, I, (W + 6, 1.3, 1.1), (0, 0, H * 0.95))
    n = 14
    L = W / 2 + 4.4
    pts = [Vector((x, 0, H * 0.95 + 1.2 + 1.0 * (abs(x) / L) ** 2.6)) for x in (-L + 2 * L * i / n for i in range(n + 1))]
    kit.sweep(black, I, pts, lambda i, t: [(-0.6, -1.0), (0.9, -1.0), (0.9, 1.0), (-0.6, 1.0)], False, True)
    snow = [Vector((p.x * 0.97, 0, p.z + 0.95)) for p in pts]
    kit.sweep(a.bm("Snow"), I, snow, lambda i, t: [(-0.1, -0.9), (0.4, -0.9), (0.4, 0.9), (-0.1, 0.9)], True, True)


def stone_lantern(a):
    """Kasuga-style toro. The firebox (light) is at z = 7.8."""
    g, glow, snow = a.bm("Granite"), a.bm("Glow"), a.bm("Snow")
    kit.lathe(g, I, [(0, 0), (2.6, 0), (2.6, 0.9), (2.0, 1.3), (0, 1.3)], 6)
    kit.lathe(g, I, [(0, 1.2), (0.95, 1.2), (0.95, 5.6), (0, 5.6)], 12)
    kit.lathe(g, I, [(0.9, 3.2), (1.25, 3.2), (1.25, 3.6), (0.9, 3.6)], 12)
    kit.lathe(g, I, [(0, 5.4), (1.2, 5.4), (2.3, 6.2), (2.3, 6.7), (0, 6.7)], 6)
    for k in range(6):
        ang = k / 6 * TAU
        kit.box(g, Rz(ang), (0.5, 0.5, 2.2), (1.45, 0, 7.8))
    kit.lathe(glow, I, [(0, 6.7), (1.25, 6.7), (1.25, 8.9), (0, 8.9)], 6)
    kit.lathe(g, I, [(0, 8.8), (3.3, 8.8), (3.3, 9.2), (1.0, 10.4), (0, 10.4)], 6)
    for k in range(6):
        ang = k / 6 * TAU
        kit.sphere(g, T(math.cos(ang) * 3.3, math.sin(ang) * 3.3, 9.45), 0.45, 6, 3)
    kit.lathe(g, I, [(0, 10.3), (0.5, 10.3), (0.8, 10.8), (0.5, 11.4), (0.15, 11.9), (0, 12.1)], 8)
    kit.lathe(snow, I, [(0, 9.6), (3.15, 9.32), (3.15, 9.6), (0.95, 10.78), (0, 10.82)], 6)


# --------------------------------------------------------------------------- minka
def minka(a, thatched):
    """Farmhouse 22 x 16, veranda and paper screens on the front (-Y)."""
    W, D = 22.0, 16.0
    granite, wood, beam, plaster, shoji, snow = (a.bm(s) for s in ("Granite", "Wood", "WoodDark", "Plaster", "Shoji", "Snow"))
    kit.box(granite, I, (W + 3, D + 3, 1.8), (0, 0, 0.2), bevel=0.3)
    kit.box(wood, I, (W, D, 1.0), (0, 0, 2.2))
    for x in (-W / 2, -W / 6, W / 6, W / 2):
        for y in (-D / 2, D / 2):
            kit.box(beam, I, (1.1, 1.1, 10.6), (x, y, 7.6))
    for x in (-W / 2, W / 2):
        kit.box(beam, I, (1.1, 1.1, 10.6), (x, 0, 7.6))
    kit.box(plaster, I, (W - 0.6, D - 0.6, 9.6), (0, 0, 7.6))
    for M, L in ((T(0, D / 2, 0) @ Rz(math.pi), W), (T(-W / 2, 0, 0) @ Rz(-HALF), D), (T(W / 2, 0, 0) @ Rz(HALF), D)):
        kit.box(wood, M, (L - 1.2, 0.3, 2.6), (0, -0.2, 4.1))
        kit.box(beam, M, (L, 0.5, 0.6), (0, -0.25, 6.6))
    for y in (-D / 2, D / 2):
        kit.box(beam, I, (W + 1, 1.0, 0.9), (0, y, 12.4))
    for x in (-W / 2, W / 2):
        kit.box(beam, I, (1.0, D + 1, 0.9), (x, 0, 12.4))
    pw = W / 3 - 1.6
    for x in (-W / 3, 0, W / 3):
        kit.box(shoji, I, (pw, 0.25, 7.6), (x, -D / 2 - 0.05, 7.2))
        for k in range(4):
            kit.box(beam, I, (0.18, 0.3, 7.6), (x - pw / 2 + (k + 0.5) * pw / 4, -D / 2 - 0.25, 7.2))
        for k in range(5):
            kit.box(beam, I, (pw, 0.3, 0.18), (x, -D / 2 - 0.25, 3.8 + k * 1.7))
    kit.box(wood, I, (W + 2, 4, 0.5), (0, -D / 2 - 2.2, 2.6))
    kit.box(beam, I, (W + 2, 0.6, 0.8), (0, -D / 2 - 4.1, 2.3))
    for x in (-W / 2, 0, W / 2):
        kit.box(beam, I, (0.6, 0.6, 2.3), (x, -D / 2 - 3.8, 1.2))
    kit.box(granite, I, (4, 2.2, 1.0), (0, -D / 2 - 5.4, 0.6), bevel=0.2)
    z = 12.85
    if thatched:
        thatch = a.bm("Thatch")
        kit.jroof(thatch, T(0, 0, z), W + 8, D + 9, 11, curl=0.5, thick=2.8, sag=1.15)
        kit.jroof(snow, T(0, 0, z + 1.0), W + 7.2, D + 8.2, 11, curl=0.5, thick=1.2, sag=1.15)
        rl = max((W + 8 - (D + 9)) / 2, 0) + 2
        kit.tube(thatch, I, [Vector((-rl, 0, z + 11.6)), Vector((rl, 0, z + 11.6))], [2.0, 2.0], 10)
        kit.tube(snow, I, [Vector((-rl + 0.4, 0, z + 12.6)), Vector((rl - 0.4, 0, z + 12.6))], [1.5, 1.5], 10)
        for x in (-3, -1, 1, 3):
            kit.beam(beam, I, Vector((x, -2.6, z + 10.8)), Vector((x, 2.6, z + 13.8)), 0.4, 0.4)
            kit.beam(beam, I, Vector((x, 2.6, z + 10.8)), Vector((x, -2.6, z + 13.8)), 0.4, 0.4)
    else:
        tile = a.bm("Tile")
        kit.jroof(tile, T(0, 0, z), W + 8, D + 8, 8, curl=1.8, thick=1.0, sag=1.7)
        kit.jroof(snow, T(0, 0, z + 0.9), W + 7, D + 7, 8, curl=1.8, thick=0.7, sag=1.7)
        kit.ridge_caps(tile, T(0, 0, z + 1.5), W + 7, D + 7, 8, r=0.55, sag=1.7, curl=1.8)
        rl = max((W + 7 - (D + 7)) / 2, 0)
        for s in (-1, 1):
            kit.box(tile, I, (1.6, 1.8, 2.6), (s * (rl + 0.8), 0, z + 10.6))
    lantern = T(W / 2 - 1.5, -D / 2 - 3.6, 9.4)
    kit.lathe(a.bm("Lantern"), lantern, [(0, 0), (0.9, 0.1), (1.1, 0.9), (0.9, 1.7), (0, 1.8)], 12)
    kit.lathe(a.bm("Black"), lantern, [(0, -0.2), (0.7, -0.2), (0.7, 0.12), (0, 0.12)], 12)
    kit.lathe(a.bm("Black"), lantern @ T(0, 0, 1.7), [(0, 0), (0.7, 0), (0.7, 0.3), (0, 0.3)], 12)
    kit.beam(beam, I, Vector((W / 2 - 1.5, -D / 2 - 3.6, 11.4)), Vector((W / 2 - 1.5, -D / 2 - 3.6, 13.6)), 0.15, 0.15)
    for k in range(6):
        c = T(W / 2 + 2.2 + (k % 3) * 1.3, 1.5, 0.8 + (k // 3) * 1.2) @ Rx(HALF)
        kit.lathe(wood, c, [(0, -3), (0.6, -3), (0.6, 3), (0, 3)], 8)
    kit.box(snow, I, (4.6, 6.6, 0.6), (W / 2 + 3.5, 1.5, 3.1))
    kit.lathe(wood, T(-W / 2 - 2.6, -2, 0), [(0, 0), (1.4, 0), (1.6, 1.8), (1.4, 3.6), (0, 3.6)], 12)
    kit.lathe(snow, T(-W / 2 - 2.6, -2, 3.6), [(0, 0), (1.45, 0), (1.2, 0.5), (0, 0.6)], 12)


def minka_thatch(a):
    minka(a, True)


def minka_tile(a):
    minka(a, False)


# --------------------------------------------------------------------------- temple
def column(bm, base, h, r):
    kit.lathe(bm, T(*base), [(0, 0), (r * 1.25, 0), (r * 1.25, 0.6), (r, 1.0), (r * 0.92, h - 1), (r * 1.2, h - 0.4), (r * 1.2, h), (0, h)], 14)


def bracket(bm, x, y, z):
    kit.box(bm, I, (2.6, 2.6, 1.0), (x, y, z + 0.5))
    kit.box(bm, I, (6.4, 1.2, 0.9), (x, y, z + 1.45))
    kit.box(bm, I, (1.2, 6.4, 0.9), (x, y, z + 1.45))
    kit.box(bm, I, (2.4, 2.4, 1.0), (x, y, z + 2.4))


def snowy_roof(a, M, W, D, rise, curl, thick=1.4, segs_u=10, segs_t=6, caps=True, ridge=None):
    tile, snow = a.bm("Tile"), a.bm("Snow")
    kit.jroof(tile, M, W, D, rise, curl, thick, segs_u, segs_t, ridge=ridge)
    kit.jroof(snow, M @ T(0, 0, thick * 0.65), W - 2, D - 2, rise, curl, thick * 0.6, segs_u, segs_t, ridge=None if ridge is None else ridge - 2)
    if caps:
        kit.ridge_caps(tile, M @ T(0, 0, thick * 1.1), W - 2, D - 2, rise, r=0.7, curl=curl, ridge=None if ridge is None else ridge - 2)


def temple_hall(a):
    """Main hall: podium 96 x 70, building centred at y = +4, front (-Y)."""
    granite, verm, plaster, wood, beam, gold = (a.bm(s) for s in ("Granite", "Vermilion", "Plaster", "Wood", "WoodDark", "Gold"))
    kit.box(granite, I, (98, 72, 1.4), (0, 0, 0.7), bevel=0.2)
    kit.box(granite, I, (96, 70, 5.4), (0, 0, 3.3), bevel=0.4)
    for k in range(6):
        kit.box(granite, I, (30, 2, 1.0 + k), (0, -35 - (6 - k) * 2 + 1, (1.0 + k) / 2))
    kit.box(plaster, I, (72, 46, 24), (0, 4, 18))
    for z in (10, 24, 29.6):
        kit.box(beam, I, (73, 47, 1.0), (0, 4, z))
    for x in range(-36, 37, 9):
        for y in (-19.2, 27.2):
            kit.box(beam, I, (1.0, 0.8, 24), (x, y, 18))
    for y in range(-19, 28, 9):
        for x in (-36.2, 36.2):
            kit.box(beam, I, (0.8, 1.0, 24), (x, y, 18))
    for x in (-18, 0, 18):
        kit.box(wood, I, (12, 0.6, 16), (x, -19.6, 15))
        for k in range(5):
            kit.box(beam, I, (0.25, 0.4, 16), (x - 4.8 + k * 2.4, -19.95, 15))
        for k in range(6):
            kit.box(beam, I, (12, 0.4, 0.25), (x, -19.95, 7.8 + k * 2.9))
    for y in (-8, 16):
        for x in (-36.4, 36.4):
            kit.box(a.bm("Dark"), I, (0.4, 8, 4), (x, y, 19))
            for k in range(6):
                kit.box(wood, I, (0.6, 0.4, 4), (x * 1.005, y - 3.5 + k * 1.4, 19))
    kit.box(wood, I, (82, 10, 0.8), (0, -23.5, 6.8))
    for x in (-40, 40):
        kit.box(wood, I, (6, 50, 0.8), (x, 2, 6.8))
    for x in range(-36, 37, 9):
        column(verm, (x, -27, 6), 24, 1.3)
        bracket(beam, x, -27, 30)
    for x in (-36, 36):
        for y in (-19, -8, 5, 16, 27):
            bracket(beam, x * 1.04, y, 30)
    kit.box(verm, I, (76, 2.4, 2), (0, -27, 29.2))
    kit.railing(verm, verm, I, [(-41, -28.4, 7.2), (-17, -28.4, 7.2)], 3.0, 3.0, 0.5, 0.35, 2)
    kit.railing(verm, verm, I, [(17, -28.4, 7.2), (41, -28.4, 7.2)], 3.0, 3.0, 0.5, 0.35, 2)
    for k in range(3):
        kit.box(wood, I, (14, 1.2, 0.5), (0, -29 - k * 1.2, 6.6 - k * 1.1))
    kit.box(wood, I, (8, 4, 3.6), (0, -22, 9))
    for k in range(5):
        kit.box(beam, I, (8.2, 0.3, 0.3), (0, -23.9 + k * 0.9, 10.9))
    snowy_roof(a, T(0, 4, 30.6), 100, 74, 12, 3.2, 1.6)
    kit.box(plaster, I, (60, 34, 12), (0, 4, 40))
    kit.box(beam, I, (61, 35, 1.0), (0, 4, 45.6))
    for x in range(-28, 29, 8):
        bracket(beam, x, -13.4, 43.2)
    snowy_roof(a, T(0, 4, 46.4), 80, 54, 18, 4.0, 1.6)
    for s in (-1, 1):
        base = Vector((s * 12, 4, 66.2))
        kit.tube(gold, I, [base, base + Vector((s * 1.6, 0, 3.4)), base + Vector((s * 0.6, 0, 6.6)), base + Vector((-s * 1.4, 0, 7.6))], [1.3, 1.1, 0.8, 0.4], 8)
    lantern = T(0, -29.5, 19.5)
    kit.lathe(a.bm("Lantern"), lantern, [(0, 0), (2.4, 0.4), (3.1, 3), (3.1, 5.5), (2.4, 8), (0, 8.4)], 18)
    kit.lathe(a.bm("Black"), lantern, [(0, -0.5), (2.2, -0.5), (2.2, 0.4), (0, 0.4)], 18)
    kit.lathe(a.bm("Black"), lantern @ T(0, 0, 8), [(0, 0), (2.2, 0), (2.2, 0.9), (0, 0.9)], 18)
    kit.beam(beam, I, Vector((0, -29.5, 28.4)), Vector((0, -29.5, 31)), 0.3, 0.3)


def temple_gate(a):
    """Two-storey gate, 48 x 20, front (-Y). The name plaque sits at (0, -6.9, 27)."""
    granite, verm, plaster, beam, gold, black = (a.bm(s) for s in ("Granite", "Vermilion", "Plaster", "WoodDark", "Gold", "Black"))
    kit.box(granite, I, (50, 22, 1.6), (0, 0, 0.4), bevel=0.2)
    for y in (-12, 12):
        kit.box(granite, I, (26, 2.4, 0.8), (0, y, 0.2))
    for x in (-18, -6, 6, 18):
        for y in (-6, 6):
            column(verm, (x, y, 1.2), 19.8, 1.4)
    for y in (-6, 6):
        kit.box(verm, I, (40, 1.2, 1.6), (0, y, 19.6))
        kit.box(verm, I, (40, 1.0, 1.2), (0, y, 7.0))
    for x in (-18, 18):
        kit.box(verm, I, (1.2, 13, 1.6), (x, 0, 19.6))
    kit.box(beam, I, (42, 15, 1.0), (0, 0, 20.9))
    snowy_roof(a, T(0, 0, 21.6), 54, 28, 6, 2.2, 1.2)
    kit.box(beam, I, (36, 15, 0.6), (0, 0, 24.4))
    kit.railing(verm, verm, I, [(-18, -7.5, 24.7), (18, -7.5, 24.7), (18, 7.5, 24.7), (-18, 7.5, 24.7), (-18, -7.5, 24.7)], 2.4, 3, 0.4, 0.3, 2)
    kit.box(plaster, I, (30, 10, 9), (0, 0, 29.2))
    for x in (-15, -7.5, 0, 7.5, 15):
        for y in (-5.1, 5.1):
            kit.box(verm, I, (0.8, 0.6, 9), (x, y, 29.2))
    kit.box(verm, I, (31, 11, 1.0), (0, 0, 33.4))
    kit.box(gold, I, (11.2, 0.5, 5.2), (0, -6.6, 27))
    kit.box(black, I, (10.4, 0.6, 4.4), (0, -6.75, 27))
    snowy_roof(a, T(0, 0, 33.9), 46, 24, 9, 3.0, 1.2)
    for s in (-1, 1):
        base = Vector((s * 10, 0, 43.6))
        kit.tube(gold, I, [base, base + Vector((s * 1.0, 0, 2.4)), base + Vector((-s * 0.8, 0, 4.4))], [0.9, 0.6, 0.3], 6)


def pagoda(a):
    """Five storeys on a 28 x 28 base, about 100 studs tall."""
    granite, verm, plaster, beam, wood, gold = (a.bm(s) for s in ("Granite", "Vermilion", "Plaster", "WoodDark", "Wood", "Gold"))
    kit.box(granite, I, (28, 28, 3), (0, 0, 1.5), bevel=0.3)
    for k in range(3):
        kit.box(granite, I, (10, 2, 1 + k * 0.6), (0, -14 - (3 - k) * 1.6, (1 + k * 0.6) / 2))
    y0 = 3.0
    for i in range(5):
        s = 16 - 2 * i
        kit.box(plaster, I, (s, s, 9), (0, 0, y0 + 4.5))
        for x in (-s / 2, s / 2):
            for y in (-s / 2, s / 2):
                kit.box(verm, I, (1.2, 1.2, 9), (x, y, y0 + 4.5))
        for M in (T(0, -s / 2, 0), T(0, s / 2, 0) @ Rz(math.pi), T(-s / 2, 0, 0) @ Rz(-HALF), T(s / 2, 0, 0) @ Rz(HALF)):
            kit.box(wood, M, (s * 0.4, 0.4, 6), (0, -0.15, y0 + 3.5))
            kit.box(verm, M, (s, 0.6, 0.8), (0, -0.3, y0 + 8.2))
        kit.box(beam, I, (s + 2.4, s + 2.4, 1.2), (0, 0, y0 + 9.2))
        snowy_roof(a, T(0, 0, y0 + 9.8), s + 14, s + 14, 4.2, 2.4, 1.0, 6, 4, caps=True)
        y0 += 13
    top = y0 + 0.6
    prof = [(0, top - 2), (2.6, top - 2), (2.6, top), (0.7, top + 1)]
    for k in range(9):
        z = top + 3 + k * 2.4
        prof += [(0.7, z - 0.4), (1.8 - k * 0.07, z - 0.2), (1.8 - k * 0.07, z + 0.2), (0.7, z + 0.4)]
    prof += [(0.6, top + 26), (1.6, top + 27.5), (1.2, top + 29), (0.4, top + 30), (0.9, top + 31), (0, top + 32.4)]
    kit.lathe(gold, I, prof, 12)


def bell_pavilion(a):
    granite, verm, beam, bronze, wood = (a.bm(s) for s in ("Granite", "Vermilion", "WoodDark", "Bronze", "Wood"))
    kit.box(granite, I, (22, 22, 3), (0, 0, 1.5), bevel=0.3)
    for x in (-8, 8):
        for y in (-8, 8):
            column(verm, (x, y, 3), 17, 0.95)
    for y in (-8, 8):
        kit.box(verm, I, (18, 0.9, 1.2), (0, y, 19.6))
    for x in (-8, 8):
        kit.box(verm, I, (0.9, 18, 1.2), (x, 0, 19.6))
    for x in (-8, 8):
        for y in (-8, 8):
            bracket(beam, x, y, 19.4)
    kit.box(beam, I, (16, 1, 1), (0, 0, 19))
    snowy_roof(a, T(0, 0, 22.2), 28, 28, 7, 2.6, 1.2, 8, 5)
    bell = [(0, 8.6), (3.4, 8.6), (3.3, 9.4), (2.9, 11), (2.6, 14.5), (2.4, 16.4), (1.8, 17.4), (0.8, 17.9), (0, 18)]
    kit.lathe(bronze, I, bell, 20)
    for z in (11.4, 14.6):
        kit.lathe(bronze, I, [(2.6, z), (3.0, z), (3.0, z + 0.4), (2.6, z + 0.4)], 20)
    kit.lathe(bronze, I, [(0, 17.8), (0.5, 17.8), (0.5, 19), (0, 19)], 8)
    kit.lathe(wood, T(-7.6, 0, 11) @ Rx(HALF) @ Rz(0) @ T(0, 0, -3.5) @ kit.Ry(0), [(0, 0), (0.8, 0), (0.8, 7), (0, 7)], 10)
    for s in (-2.5, 2.5):
        kit.beam(a.bm("Rope"), I, Vector((-7.6, s, 11.6)), Vector((-7.6, s * 1.4, 19)), 0.2, 0.2)


ASSETS = [
    ("Pine_A", pine_a),
    ("Pine_B", pine_b),
    ("Pine_C", pine_c),
    ("BareTree", bare_tree),
    ("Torii", torii),
    ("StoneLantern", stone_lantern),
    ("Minka_Thatch", minka_thatch),
    ("Minka_Tile", minka_tile),
    ("TempleHall", temple_hall),
    ("TempleGate", temple_gate),
    ("Pagoda", pagoda),
    ("BellPavilion", bell_pavilion),
]
