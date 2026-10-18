"""Solkhar, the desert capital: palace, clock spire, gates, towers, houses, fountain, stall, palms, lamps."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rx, Ry, Rz, TAU

HALF = math.pi / 2


# --------------------------------------------------------------------------- shared details
def merlon(bm, M):
    """Moorish stepped merlon, 3.2 wide, 4.4 tall, standing on M's origin (faces -Y)."""
    kit.wall_prism(bm, M, [(-1.6, 0), (-1.6, 2.2), (-1.0, 2.2), (-1.0, 3.4), (-0.4, 3.4), (0, 4.4),
                           (0.4, 3.4), (1.0, 3.4), (1.0, 2.2), (1.6, 2.2), (1.6, 0)], -0.6, 0.6)


def merlon_ring(bm, w, d, z, step=7.0, scale=1.0, M=I):
    """Merlons along the edge of a w x d rectangle centred on M's origin."""
    S = kit.Sc(scale)
    n = max(1, int(w / step))
    for i in range(n + 1):
        x = -w / 2 + w * i / n
        for y, rot in ((-d / 2, 0.0), (d / 2, math.pi)):
            merlon(bm, M @ T(x, y, z) @ Rz(rot) @ S)
    n = max(1, int(d / step))
    for i in range(1, n):
        y = -d / 2 + d * i / n
        for x, rot in ((-w / 2, -HALF), (w / 2, HALF)):
            merlon(bm, M @ T(x, y, z) @ Rz(rot) @ S)


def window(dark, frame, M, w, h, sill=True, segs=6):
    """Pointed-arch window on a wall whose outside faces -Y in M's space."""
    kit.niche(dark, M, w, h, 0.2, True, segs)
    kit.arch_frame(frame, M, w, h, 0.7, 1.0, True, segs)
    if sill:
        kit.box(frame, M, (w + 1.6, 1.0, 0.6), (0, -0.3, -0.3))


def face_frames(w, d):
    """Matrices on the 4 outer wall faces of a w x d block: (M, wall length)."""
    return [
        (T(0, -d / 2, 0), w),
        (T(0, d / 2, 0) @ Rz(math.pi), w),
        (T(-w / 2, 0, 0) @ Rz(-HALF), d),
        (T(w / 2, 0, 0) @ Rz(HALF), d),
    ]


def onion(bm, M, r, h, base_r=None, segs=32):
    kit.lathe(bm, M, kit.onion_profile(r, h, base_r), segs)


def finial(bm, M, h=10.0):
    kit.lathe(bm, M, [(0, 0), (1.2, 0), (1.5, 0.8), (0.7, 1.8), (1.6, 2.8), (1.6, 3.4), (0.35, 4.6),
                      (0.25, h * 0.85), (0.9, h * 0.9), (0, h)], 12)


# --------------------------------------------------------------------------- palace
def palace(a):
    stone, sand, marble, gold = a.bm("Stone"), a.bm("Sandstone"), a.bm("Marble"), a.bm("Gold")
    dark, teal, door, fabric = a.bm("Dark"), a.bm("Teal"), a.bm("Door"), a.bm("Fabric")

    # plinth and the arcade platform
    kit.box(sand, I, (120, 90, 3), (0, 5, 1.5), bevel=0.4)
    kit.box(sand, I, (102, 18, 1.4), (0, -46, 0.7), bevel=0.2)
    for k in range(2):
        kit.box(sand, I, (96 - k * 6, 2.6, 0.8 + k * 0.1), (0, -56.3 - k * 2.4, 0.4))

    # main hall
    kit.box(stone, I, (110, 80, 42), (0, 6, 24), bevel=0.3)
    kit.box(sand, I, (111.6, 81.6, 4), (0, 6, 5))
    kit.box(sand, I, (111.2, 81.2, 1.4), (0, 6, 21))
    kit.box(gold, I, (111.5, 81.5, 0.5), (0, 6, 22))
    kit.box(teal, I, (110.5, 80.5, 3), (0, 6, 41.5))
    kit.box(sand, I, (114, 84, 1.6), (0, 6, 45.8))
    kit.box(stone, I, (113, 83, 1.6), (0, 6, 47.4))
    merlon_ring(stone, 110, 80, 48.2, M=T(0, 6, 0))

    # windows
    for z in (8, 27):
        for x in (-45, -32, -19, 19, 32, 45):
            window(dark, sand, T(x, -34, z), 4.6, 9)
        for x in (-45, -32, -19, -6, 6, 19, 32, 45):
            window(dark, sand, T(x, 46, z) @ Rz(math.pi), 4.6, 9)
        for y in (-27, 43):  # the wings cover the middle of the side walls
            window(dark, sand, T(-55, y, z) @ Rz(-HALF), 4.6, 9)
            window(dark, sand, T(55, y, z) @ Rz(HALF), 4.6, 9)

    # grand portal (pishtaq) with nested arches and a sun emblem
    kit.box(stone, I, (44, 8, 50), (0, -37.5, 25), bevel=0.3)
    kit.box(sand, I, (46, 9, 1.6), (0, -37.5, 50.6))
    for x in (-19.5, -13, -6.5, 0, 6.5, 13, 19.5):
        merlon(stone, T(x, -41, 51.4))
    kit.box(teal, I, (36, 0.4, 8), (0, -41.7, 45.5))
    # nested frames step forward like layered mouldings
    for w, h, y in ((30, 38, -41.5), (25, 34, -41.8), (20, 30, -42.1)):
        kit.arch_frame(gold if w == 25 else sand, T(0, y, 0), w, h, 1.2, 1.4, True, 8)
    kit.niche(dark, T(0, -41.5, 0), 18, 29, 0.35, True, 8)
    kit.box(door, I, (12, 0.6, 20), (0, -42.1, 10))
    kit.box(gold, I, (0.4, 0.8, 20), (0, -42.3, 10))
    for x in (-4.5, 4.5):
        for z in (4, 9, 14):
            kit.sphere(gold, T(x, -42.5, z), 0.45, 8, 4)
    kit.lathe(gold, T(0, -41.8, 45) @ Rx(HALF), [(0, 0), (3.4, 0), (3.8, 0.6), (3.0, 1.2), (0, 1.2)], 24)
    for k in range(12):
        ang = k / 12 * TAU
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        kit.beam(gold, I, Vector((0, -42.4, 45)) + d * 3.9, Vector((0, -42.4, 45)) + d * 5.6, 0.8, 0.5)

    # arcade of columns and pointed arches in front
    xs = [-42 + 12 * i for i in range(8)]
    col = [(0, 0), (3.0, 0), (3.0, 0.8), (2.5, 1.4), (2.3, 2), (2.25, 16), (2.1, 28), (2.5, 29),
           (3.2, 30.4), (3.5, 31.4), (3.5, 32.4), (0, 32.4)]
    for x in xs:
        kit.lathe(marble, T(x, -46, 1.4), col, 16)
    arcs = [kit.pointed_arc(xs[i], xs[i + 1], 33.8, 5.2, 6) for i in range(len(xs) - 1)]
    W = T(0, -46, 0)
    for arc in arcs:
        pts = [Vector((x, 0, z)) for x, z in arc]
        kit.sweep(sand, W, pts, lambda j, t: [(-1.6, -0.8), (1.6, -0.8), (1.6, 0.8), (-1.6, 0.8)], False, True, Vector((0, 1, 0)))
    # spandrels: the wall between neighbouring arches, up to the entablature
    for i in range(len(arcs) - 1):
        poly = arcs[i][6:] + arcs[i + 1][1:7] + [(arcs[i + 1][6][0], 40.4), (arcs[i][6][0], 40.4)]
        kit.wall_prism(stone, W, poly, -1.4, 1.4)
    kit.wall_prism(stone, W, [(xs[0] - 3, 33.8)] + arcs[0][:7] + [(arcs[0][6][0], 40.4), (xs[0] - 3, 40.4)], -1.4, 1.4)
    kit.wall_prism(stone, W, arcs[-1][6:] + [(xs[-1] + 3, 33.8), (xs[-1] + 3, 40.4), (arcs[-1][6][0], 40.4)], -1.4, 1.4)
    kit.box(stone, I, (92, 4, 3.6), (0, -46, 42.2), bevel=0.2)
    kit.box(teal, I, (90, 4.2, 1.4), (0, -46, 41.2))
    kit.box(sand, I, (94, 5, 1.0), (0, -46, 44.5))
    kit.box(stone, I, (92, 12, 1.0), (0, -40, 43.6))
    for x in range(-42, 43, 7):
        merlon(stone, T(x, -48, 45) @ kit.Sc(0.7))
    for x in (-36, -24, 24, 36):
        kit.box(fabric, I, (5, 0.3, 21), (x, -48.4, 29.5))
        kit.wall_prism(fabric, T(x, -48.4, 0), [(-2.5, 19), (0, 16.6), (2.5, 19)], -0.15, 0.15)
        kit.box(gold, I, (5.6, 0.5, 0.6), (x, -48.5, 39.6))

    # drum and great onion dome with gold ribs
    kit.lathe(stone, T(0, 6, 48), [(0, 0), (34, 0), (34, 2), (33, 2.4), (33, 16), (34.6, 16.4), (34.6, 18), (0, 18)], 48)
    for k in range(12):
        ang = k / 12 * TAU + TAU / 24
        window(dark, sand, T(0, 6, 48) @ Rz(ang) @ T(0, -33, 4), 3.4, 8, sill=False)
    kit.lathe(teal, T(0, 6, 48), [(33.2, 13), (33.6, 13), (33.6, 15), (33.2, 15)], 48)
    prof = kit.onion_profile(37, 54, 34)
    kit.lathe(marble, T(0, 6, 66), prof, 48)
    for k in range(12):
        ang = k / 12 * TAU
        pts = [Vector((math.cos(ang) * (r + 0.35), 6 + math.sin(ang) * (r + 0.35), 66 + z)) for r, z in prof[:-2]]
        kit.tube(gold, I, pts, [0.45] * len(pts), 5)
    finial(gold, T(0, 6, 119), 18)

    # corner towers
    tower = [(0, 0), (12.5, 0), (12.5, 3), (11, 4.5), (11, 44), (14.5, 45), (14.5, 47.4), (9.6, 48.4),
             (9.6, 68), (12.4, 69), (12.4, 70.8), (9, 71.6), (9, 78), (0, 78)]
    for x, y in ((-55, -34), (55, -34), (-55, 46), (55, 46)):
        M = T(x, y, 0)
        kit.lathe(stone, M, tower, 32)
        kit.lathe(teal, M, [(9.7, 63), (10.1, 63), (10.1, 65.4), (9.7, 65.4)], 32)
        kit.lathe(sand, M, [(11.1, 20), (11.7, 20), (11.7, 21.4), (11.1, 21.4)], 32)
        for k in range(12):
            ang = k / 12 * TAU
            kit.box(sand, M @ Rz(ang), (1.2, 2.0, 2.2), (0, -11.8, 43.6))
            kit.box(sand, M @ Rz(ang + TAU / 24), (0.5, 0.5, 2.6), (0, -13.9, 48.6))
        kit.lathe(sand, M, [(13.6, 50.6), (14.2, 50.6), (14.2, 51.2), (13.6, 51.2)], 32)
        for k in range(4):
            window(dark, sand, M @ Rz(k * HALF + math.pi / 4) @ T(0, -9.6, 53), 2.6, 7, sill=False)
        onion(marble, M @ T(0, 0, 78), 11.5, 27, 9.2)
        finial(gold, M @ T(0, 0, 104), 11)

    # side wings with small domes and arcades
    for sx in (-1, 1):
        cx = sx * 75
        kit.box(stone, T(cx, 10, 0), (40, 60, 30), (0, 0, 18), bevel=0.3)
        kit.box(sand, T(cx, 10, 0), (41.6, 61.6, 1.4), (0, 0, 33.6))
        kit.box(teal, T(cx, 10, 0), (40.4, 60.4, 2), (0, 0, 30.8))
        merlon_ring(stone, 40, 60, 34.3, 7, 0.8, T(cx, 10, 0))
        for y in (-12, 2, 16, 30):
            window(dark, sand, T(cx + sx * 20, y, 8) @ Rz(sx * HALF), 6, 14)
        kit.lathe(stone, T(cx, 10, 34), [(0, 0), (11, 0), (11, 6), (11.8, 6.4), (11.8, 7.4), (0, 7.4)], 8)
        onion(marble, T(cx, 10, 41.4), 12.5, 26, 10.5, 32)
        finial(gold, T(cx, 10, 66), 9)


# --------------------------------------------------------------------------- clock spire
def clock_spire(a):
    stone, sand, marble, gold, dark = a.bm("Stone"), a.bm("Sandstone"), a.bm("Marble"), a.bm("Gold"), a.bm("Dark")
    kit.box(sand, I, (34, 34, 1.6), (0, 0, 0.8))
    kit.box(sand, I, (32, 32, 6), (0, 0, 3.4), bevel=0.4)
    kit.box(stone, I, (24, 24, 120), (0, 0, 66))
    for x in (-12, 12):
        for y in (-12, 12):
            kit.box(sand, I, (3.4, 3.4, 120), (x, y, 66))
    for z in (30, 54, 78, 102):
        kit.box(sand, I, (26, 26, 1.6), (0, 0, z))
    for M, _ in face_frames(24, 24):
        for z in (16, 40, 64, 88, 110):
            window(dark, sand, M @ T(0, 0, z), 3.2, 8)
    kit.box(stone, I, (30, 30, 30), (0, 0, 141), bevel=0.3)
    kit.box(sand, I, (31, 31, 1.4), (0, 0, 127))
    kit.box(sand, I, (33, 33, 2), (0, 0, 157))
    kit.box(gold, I, (33.4, 33.4, 0.6), (0, 0, 155.8))
    for M, _ in face_frames(30, 30):
        F = M @ T(0, 0, 141) @ Rx(HALF)
        kit.lathe(gold, F, [(0, 0), (12.6, 0), (12.6, 0.9), (11.2, 1.2), (0, 1.2)], 40)
        kit.lathe(marble, F, [(0, 0), (11.2, 0), (11.2, 1.5), (0, 1.5)], 40)
        for h in range(12):
            ang = h / 12 * TAU
            ln = 2.4 if h % 3 == 0 else 1.2
            kit.box(dark, M @ T(math.sin(ang) * 9, -1.7, 141 + math.cos(ang) * 9) @ Ry(ang), (0.6, 0.3, ln))
        for ang, ln, wd in ((-math.pi / 3, 5.6, 1.0), (math.pi / 3, 7.8, 0.6)):
            kit.box(dark, M @ T(0, -1.9, 141) @ Ry(ang), (wd, 0.3, ln), (0, 0, ln / 2))
    # belfry
    for x in (-12, 12):
        for y in (-12, 12):
            kit.box(stone, I, (4.2, 4.2, 21), (x, y, 168.5))
    for M, _ in face_frames(24, 24):
        arc = kit.pointed_arc(-10, 10, 168, 7, 6)
        kit.sweep(sand, M, [Vector((x, 0, z)) for x, z in arc], lambda j, t: [(-1, -0.7), (1, -0.7), (1, 0.7), (-1, 0.7)], False, True, Vector((0, 1, 0)))
    kit.box(sand, I, (30, 30, 2), (0, 0, 180))
    bell = [(0, 160), (4.6, 160), (4.4, 161), (3.6, 163), (3.2, 167), (2.6, 170), (1.6, 171.6), (0.6, 172.4), (0, 172.6)]
    kit.lathe(gold, I, bell, 20)
    kit.lathe(gold, I, [(0, 172.4), (0.4, 172.4), (0.4, 179.2), (0, 179.2)], 6)
    onion(marble, T(0, 0, 181), 13.5, 27, 12)
    for k in range(8):
        ang = k / 8 * TAU
        d = Vector((math.cos(ang), math.sin(ang), 0.35))
        kit.beam(gold, I, Vector((0, 0, 205)), Vector((0, 0, 205)) + d * 5.5, 0.5, 0.5)
    finial(gold, T(0, 0, 207), 8)


# --------------------------------------------------------------------------- city gate & wall tower
def round_tower(stone, sand, marble, gold, dark, M, r=15.5, h=58, dome=14.0, merlons=12):
    prof = [(0, -6), (r + 2.2, -6), (r + 2.2, -2), (r, 10), (r, h), (r + 2, h + 1), (r + 2, h + 4.6), (r + 1, h + 4.6), (0, h + 4.6)]
    kit.lathe(stone, M, prof, 36)
    for k in range(16):
        ang = k / 16 * TAU
        kit.box(sand, M @ Rz(ang), (1.6, 2.2, 2.4), (0, -r - 0.8, h - 1.4))
    for k in range(merlons):
        ang = k / merlons * TAU
        merlon(stone, M @ Rz(ang) @ T(0, -r - 1.2, h + 4.6) @ kit.Sc(0.9))
    for k in range(3):
        kit.niche(dark, M @ Rz(-0.7 + k * 0.7) @ T(0, -r, 18 + k * 12), 1.4, 7, 0.2, True, 4)
    kit.lathe(sand, M, [(r - 0.2, 30), (r + 0.5, 30), (r + 0.5, 31.4), (r - 0.2, 31.4)], 36)
    onion(marble, M @ T(0, 0, h + 4.6), dome, dome * 2.1, dome * 0.86, 32)
    finial(gold, M @ T(0, 0, h + 4.6 + dome * 2.1 - 1), 9)


def city_gate(a):
    stone, sand, marble, gold, dark = a.bm("Stone"), a.bm("Sandstone"), a.bm("Marble"), a.bm("Gold"), a.bm("Dark")
    fabric, iron = a.bm("Fabric"), a.bm("Iron")
    for x in (-38, 38):
        round_tower(stone, sand, marble, gold, dark, T(x, 0, 0))
    # gate block with a pointed archway
    arc = kit.pointed_arc(-19, 19, 26, 14, 8)
    outline = [(-23.5, -2), (-23.5, 50), (23.5, 50), (23.5, -2), (19, -2), (19, 26)] + arc[::-1][1:-1] + [(-19, 26), (-19, -2)]
    kit.wall_prism(stone, I, outline, -9, 9)
    for y in (-9.4, 9.4):
        pts = [Vector((x, y, z)) for x, z in kit.pointed_arc(-20.2, 20.2, 26, 15.4, 8)]
        kit.sweep(sand, I, pts, lambda j, t: [(-1.0, -1.3), (1.0, -1.3), (1.0, 1.3), (-1.0, 1.3)], False, True, Vector((0, 1, 0)))
        kit.box(gold, I, (3, 1.6, 4.6), (0, y, 41.8))
    kit.box(sand, I, (48, 19, 1.6), (0, 0, 49.4))
    # upper gallery
    kit.box(stone, I, (56, 18, 10), (0, 0, 55.6), bevel=0.3)
    kit.box(sand, I, (58, 20, 1.4), (0, 0, 61))
    for y, rot in ((-9, 0.0), (9, math.pi)):
        for x in (-20, -10, 0, 10, 20):
            kit.niche(dark, T(x, y, 52) @ Rz(rot), 3, 7, 0.2, True, 5)
        for x in range(-26, 27, 6):
            merlon(stone, T(x, y, 61.7) @ Rz(rot))
    kit.box(dark, I, (27, 0.5, 7.5), (0, -9.3, 45.2))
    kit.box(gold, I, (28.4, 0.6, 0.6), (0, -9.4, 49.2))
    kit.box(gold, I, (28.4, 0.6, 0.6), (0, -9.4, 41.2))
    # banners on the towers and brazier bowls
    for x in (-38, 38):
        kit.box(fabric, I, (8, 0.3, 28), (x, -16.3, 34))
        kit.wall_prism(fabric, T(x, -16.3, 0), [(-4, 20), (0, 16.5), (4, 20)], -0.15, 0.15)
        kit.box(gold, I, (8.6, 0.6, 1.0), (x, -16.5, 48))
        kit.lathe(iron, T(x, -19.5, 11), [(0, 0), (1.0, 0), (2.4, 1.6), (2.6, 2.2), (0, 2.2)], 12)
        kit.beam(iron, I, Vector((x, -16, 9)), Vector((x, -19.5, 11)), 0.5, 0.5)


def wall_tower(a):
    stone, sand, marble, gold, dark = a.bm("Stone"), a.bm("Sandstone"), a.bm("Marble"), a.bm("Gold"), a.bm("Dark")
    round_tower(stone, sand, marble, gold, dark, I, 13, 46, 11, 10)


# --------------------------------------------------------------------------- houses
def house(a, W, D, levels, variant, seed):
    rng = random.Random(seed)
    plaster, sand, wood, dark = a.bm("Plaster"), a.bm("Sandstone"), a.bm("Wood"), a.bm("Dark")
    door = a.bm("Door")
    H = levels * 12
    kit.box(sand, I, (W + 0.8, D + 0.8, 1.6), (0, 0, 0.3))
    kit.box(plaster, I, (W, D, H), (0, 0, H / 2), bevel=0.25)
    kit.box(sand, I, (W + 1.2, D + 1.2, 1.0), (0, 0, H + 0.4))
    for M, L in face_frames(W, D):
        kit.box(plaster, M, (L + 1.2, 0.8, 2.2), (0, 0.2, H + 2))
    for x in (-W / 2, W / 2):
        for y in (-D / 2, D / 2):
            merlon(plaster, T(x, y, H + 3.1) @ kit.Sc(0.6))
    # wooden roof beam ends
    for M, L in face_frames(W, D)[:2]:
        n = int(L / 2.6)
        for i in range(n):
            x = -L / 2 + 1.6 + i * (L - 3.2) / max(n - 1, 1)
            kit.lathe(wood, M @ T(x, 0, H - 1.3) @ Rx(HALF), [(0, -0.4), (0.38, -0.4), (0.38, 1.3), (0, 1.3)], 6)
    # door
    dx = rng.uniform(-W / 5, W / 5)
    kit.niche(door, T(dx, -D / 2, 0), 4.4, 7.6, 0.25, True, 6)
    kit.arch_frame(sand, T(dx, -D / 2, 0), 4.4, 7.6, 0.7, 1.0, True, 6)
    kit.box(sand, I, (5.6, 2, 0.5), (dx, -D / 2 - 1, 0.25))
    # windows with wooden lattice
    for lv in range(levels):
        z = lv * 12 + (4.6 if lv == 0 else 3.4)
        xs = [-W / 4, W / 4] if W > 21 else [0]
        for x in xs:
            if lv == 0 and abs(x - dx) < 4.5:
                continue
            M = T(x, -D / 2, z)
            window(dark, sand, M, 2.8, 4.4)
            for k in (-0.7, 0, 0.7):
                kit.box(wood, M, (0.18, 0.3, 3.2), (k, -0.35, 1.8))
            kit.box(wood, M, (2.4, 0.3, 0.18), (0, -0.35, 1.6))
            kit.box(wood, M, (2.4, 0.3, 0.18), (0, -0.35, 2.8))
        for M, L in face_frames(W, D)[2:]:
            if rng.random() < 0.7:
                window(dark, sand, M @ T(rng.uniform(-L / 5, L / 5), 0, z), 2.8, 4.4)

    if variant == "A":
        # rooftop dome on a drum and an outside staircase
        cx, cy = -W / 2 + 6, D / 2 - 6
        kit.lathe(sand, T(cx, cy, H + 0.9), [(0, 0), (4.6, 0), (4.6, 2), (0, 2)], 16)
        kit.lathe(a.bm("Marble"), T(cx, cy, H + 2.9), [(math.cos(i / 8 * HALF) * 4.4, math.sin(i / 8 * HALF) * 4.4) for i in range(9)], 24)
        finial(a.bm("Gold"), T(cx, cy, H + 7.2), 3.2)
        steps = 10
        for k in range(steps):
            z = (k + 1) * H / steps
            kit.box(plaster, I, (3.4, 2.4, z), (W / 2 + 1.7, -D / 2 + 2 + k * 2.2, z / 2))
        kit.box(plaster, I, (0.6, steps * 2.2, 1.4), (W / 2 + 3.6, -D / 2 + 1 + steps * 1.1, H / 2 + 1.8), bevel=0.1)
        # cloth awning over the door on two poles
        kit.wall_prism(a.bm("Fabric"), T(dx, -D / 2, 0) @ Rz(-HALF), [(0, 9.4), (4.6, 8.2), (4.6, 8.0), (0, 9.2)], -3.4, 3.4)
        for s in (-1, 1):
            kit.lathe(wood, T(dx + s * 3.2, -D / 2 - 4.4, 0), [(0, 0), (0.25, 0), (0.25, 8.2), (0, 8.2)], 6)
    elif variant == "B":
        # roof terrace with a shaded pergola and potted plants
        for x in (-W / 4, W / 4):
            for y in (-D / 4, D / 4):
                kit.lathe(wood, T(x, y, H + 1), [(0, 0), (0.3, 0), (0.3, 7), (0, 7)], 6)
        for y in (-D / 4, D / 4):
            kit.box(wood, I, (W / 2 + 2, 0.5, 0.5), (0, y, H + 8))
        left = [Vector((-W / 4 - 1, -D / 4 - 0.5 + i * (D / 2 + 1) / 4, H + 8.3 - math.sin(i / 4 * math.pi) * 0.8)) for i in range(5)]
        right = [Vector((W / 4 + 1, p.y, p.z)) for p in left]
        kit.ribbon(a.bm("Fabric"), I, left, right)
        clay, leaves = a.bm("Clay"), a.bm("Leaves")
        for k in range(3):
            x, y = rng.uniform(-W / 3, W / 3), rng.uniform(-D / 3, D / 3)
            kit.lathe(clay, T(x, y, H + 0.9), [(0, 0), (0.9, 0), (1.3, 1.4), (1.1, 1.8), (0, 1.8)], 10)
            kit.blob(leaves, I, (x, y, H + 3.2), 1.5, 1, 0.3, 2, k, (1, 1, 1.2))
        kit.box(wood, I, (6.4, 0.6, 0.7), (dx, -D / 2 - 0.3, 8.6))
    else:
        # tall house: wooden mashrabiya balcony and a wind-catcher tower
        M = T(0, -D / 2, 13)
        kit.box(wood, M, (8, 3, 8), (0, -1.5, 4))
        for i in range(6):
            kit.box(dark, M, (0.2, 0.2, 6.6), (-3.2 + i * 1.28, -3.1, 4))
        for i in range(5):
            kit.box(dark, M, (7.4, 0.2, 0.2), (0, -3.1, 1.2 + i * 1.4))
        kit.box(wood, M, (8.8, 3.8, 0.6), (0, -1.5, 8.2))
        for s in (-1, 1):
            kit.beam(wood, M, Vector((s * 3.4, 0, -2)), Vector((s * 3.4, -2.6, 0)), 0.5, 0.6)
        wx, wy = W / 2 - 3.5, D / 2 - 3.5
        kit.box(plaster, I, (5, 5, 9), (wx, wy, H + 5.5), bevel=0.2)
        for M2, _ in face_frames(5, 5):
            kit.niche(dark, T(wx, wy, H + 4.4) @ M2, 1.6, 5, 0.2, False, 4)
        kit.box(sand, I, (6, 6, 0.8), (wx, wy, H + 10.2))
        kit.lathe(a.bm("Teal"), T(-W / 2 + 4.5, -D / 2 + 4.5, H + 1), [(math.cos(i / 8 * HALF) * 3.4, math.sin(i / 8 * HALF) * 3.4) for i in range(9)], 20)


def house_a(a):
    house(a, 24, 24, 2, "A", 1)


def house_b(a):
    house(a, 28, 22, 1, "B", 2)


def house_c(a):
    house(a, 20, 20, 3, "C", 3)


# --------------------------------------------------------------------------- fountain (holds terrain water)
def fountain(a):
    """Square basin aligned to the 4-stud voxel grid: inner 24x24 (water surface +2),
    upper bowl inner 8x8 (water from +6 to +10). The generator fills both with terrain water."""
    marble, sand, gold, teal = a.bm("Marble"), a.bm("Sandstone"), a.bm("Gold"), a.bm("Teal")
    for y in (-13.3, 13.3):
        kit.box(marble, I, (29.2, 2.6, 4.6), (0, y, 1.3), bevel=0.25)
        kit.box(sand, I, (30.2, 3.4, 0.6), (0, y, 3.9))
        kit.box(teal, I, (27, 0.2, 1.4), (0, y + (1.35 if y > 0 else -1.35), 1.4))
    for x in (-13.3, 13.3):
        kit.box(marble, I, (2.6, 24, 4.6), (x, 0, 1.3), bevel=0.25)
        kit.box(sand, I, (3.4, 30.2, 0.6), (x, 0, 3.9))
        kit.box(teal, I, (0.2, 24, 1.4), (x + (1.35 if x > 0 else -1.35), 0, 1.4))
    for x in (-13.3, 13.3):
        for y in (-13.3, 13.3):
            kit.box(sand, I, (3.8, 3.8, 6), (x, y, 2), bevel=0.3)
            kit.sphere(gold, T(x, y, 5.9), 1.0, 10, 5)
    kit.box(teal, I, (24, 24, 0.4), (0, 0, -6.2))
    kit.lathe(marble, I, [(0, -6.4), (3.4, -6.4), (3.4, -5), (2.3, -4), (2.0, 2.6), (2.6, 3.4), (5.2, 5.4), (0, 5.4)], 24)
    for y in (-4.7, 4.7):
        kit.box(marble, I, (10.8, 1.4, 5.1), (0, y, 8.05), bevel=0.15)
    for x in (-4.7, 4.7):
        kit.box(marble, I, (1.4, 8, 5.1), (x, 0, 8.05), bevel=0.15)
    kit.box(marble, I, (10.8, 10.8, 0.6), (0, 0, 5.7))
    for x in (-5.4, 5.4):
        for y in (-5.4, 5.4):
            kit.sphere(gold, T(x, y, 10.9), 0.6, 8, 4)
    kit.lathe(gold, I, [(0, 6), (0.6, 6), (0.6, 10), (1.4, 10.2), (2.0, 11), (1.2, 12), (0.5, 13.2), (0, 13.5)], 12)
    for x, y in ((0, -5.5), (0, 5.5), (-5.5, 0), (5.5, 0)):
        kit.sphere(gold, T(x, y, 8.6), 0.9, 8, 5)


# --------------------------------------------------------------------------- market stall
def market_stall(a):
    wood, fabric, fabric2, canvas = a.bm("Wood"), a.bm("Fabric"), a.bm("Fabric2"), a.bm("Canvas")
    post = [(0, 0), (0.5, 0), (0.5, 0.4), (0.33, 0.8), (0.33, 1)]
    for x in (-5.2, 5.2):
        for y, h in ((-4.2, 9.2), (4.2, 10.6)):
            kit.lathe(wood, T(x, y, 0), post + [(0.33, h), (0, h)], 8)
    rows = []
    for j in range(6):
        t = j / 5
        y = -5.2 + t * 10.4
        rows.append([Vector((-6.2 + i * 12.4 / 8, y, 9.2 + t * 1.4 - math.sin(i / 8 * math.pi) * 0.5 - math.sin(t * math.pi) * 0.3)) for i in range(9)])
    for j in range(5):
        kit.ribbon(fabric, I, rows[j], rows[j + 1])
    top = [Vector((-6.2 + i * 12.4 / 16, -5.25, 9.2 - math.sin(i / 16 * math.pi) * 0.5)) for i in range(17)]
    bot = [Vector((p.x, p.y, p.z - (1.4 if i % 2 == 0 else 0.6))) for i, p in enumerate(top)]
    kit.ribbon(fabric2, I, top, bot)
    kit.box(wood, I, (10, 3, 3.6), (0, -2.6, 1.8), bevel=0.15)
    kit.box(a.bm("WoodDark"), I, (10.6, 3.4, 0.4), (0, -2.6, 3.8))
    rng = random.Random(5)
    for k, x in enumerate((-3.2, 0, 3.2)):
        kit.lathe(wood, T(x, -2.6, 4), [(0, 0), (1.0, 0), (1.4, 0.9), (1.45, 1.1), (0, 1.1)], 10)
        fruit = a.bm("Fruit" if k % 2 == 0 else "Fruit2")
        for _ in range(5):
            kit.sphere(fruit, T(x + rng.uniform(-0.6, 0.6), -2.6 + rng.uniform(-0.6, 0.6), 5.3 + rng.uniform(0, 0.4)), 0.5, 8, 4)
    for k in range(3):
        kit.blob(canvas, I, (rng.uniform(-5, 5), 3 + rng.uniform(-1, 1), 1.1), 1.2, 2, 0.15, 1.5, k, (1.2, 1, 1.0))
    clay = a.bm("Clay")
    for x in (-3, 3):
        kit.lathe(clay, T(x, 0, 7), [(0, 0), (0.7, 0.2), (0.9, 0.9), (0.4, 1.6), (0.5, 1.9), (0, 1.9)], 10)
        kit.beam(a.bm("Rope"), I, Vector((x, 0, 8.9)), Vector((x, 0, 9.8)), 0.12, 0.12)


# --------------------------------------------------------------------------- palms and lamps
def palm(a, seed, height, lean, fronds):
    rng = random.Random(seed)
    bark, frond, nut = a.bm("Bark"), a.bm("Frond"), a.bm("Coconut")
    pts, radii = [], []
    n = 14
    for i in range(n + 1):
        t = i / n
        pts.append(Vector((lean * t * t, 0, -1.5 + (height + 1.5) * t)))
        radii.append((1.35 - 0.55 * t) * (1.08 if i % 2 == 0 else 0.94))
    kit.tube(bark, I, pts, radii, 9)
    top = pts[-1]
    kit.sphere(bark, T(*top), 1.3, 10, 5)
    for k in range(fronds):
        ang = k / fronds * TAU + rng.uniform(-0.2, 0.2)
        d = Vector((math.cos(ang), math.sin(ang), 0))
        length = rng.uniform(11, 15)
        lift = rng.uniform(1.5, 3.5)
        mid, left, right = [], [], []
        m = 9
        for i in range(m + 1):
            t = i / m
            p = top + d * length * t + Vector((0, 0, lift * math.sin(t * math.pi * 0.8) - t * t * rng.uniform(4, 7)))
            side = Vector((-d.y, d.x, 0))
            w = (0.4 + 2.6 * math.sin(min(t * 1.2, 1) * math.pi * 0.9)) * (1 if i % 2 == 0 else 0.72)
            droop = Vector((0, 0, -0.6 * w))
            left.append(p + side * w + droop)
            right.append(p - side * w + droop)
            mid.append(p + Vector((0, 0, 0.15)))
        kit.ribbon(frond, I, left, mid)
        kit.ribbon(frond, I, mid, right)
    for k in range(4):
        ang = k / 4 * TAU + 0.4
        kit.sphere(nut, T(top.x + math.cos(ang) * 1.3, top.y + math.sin(ang) * 1.3, top.z - 1.6), 0.75, 8, 5)


def palm_a(a):
    palm(a, 11, 30, 5, 10)


def palm_b(a):
    palm(a, 12, 36, 9, 9)


def street_lamp(a):
    iron, glow, gold = a.bm("Iron"), a.bm("Glow"), a.bm("Gold")
    kit.lathe(iron, I, [(0, 0), (1.6, 0), (1.6, 0.6), (1.1, 1.2), (0.9, 2.4), (0.55, 3), (0.5, 12.6),
                        (0.9, 13.2), (1.3, 13.4), (0, 13.4)], 8)
    kit.lathe(iron, T(0, 0, 13.4), [(0, 0), (0.9, 0), (1.2, 0.4), (1.2, 0.6), (0, 0.6)], 6)
    kit.lathe(glow, T(0, 0, 14), [(0, 0), (1.0, 0), (1.3, 1.8), (1.0, 2.8), (0, 2.8)], 6)
    for k in range(6):
        ang = k / 6 * TAU
        kit.beam(iron, I, Vector((math.cos(ang) * 1.05, math.sin(ang) * 1.05, 14)),
                 Vector((math.cos(ang) * 1.35, math.sin(ang) * 1.35, 15.8)), 0.18, 0.18)
    kit.lathe(iron, T(0, 0, 16.7), [(0, 0), (1.9, 0), (1.5, 0.6), (0.4, 1.6), (0, 1.6)], 6)
    kit.sphere(gold, T(0, 0, 18.6), 0.35, 8, 4)


ASSETS = [
    ("Palace", palace),
    ("ClockSpire", clock_spire),
    ("CityGate", city_gate),
    ("WallTower", wall_tower),
    ("House_A", house_a),
    ("House_B", house_b),
    ("House_C", house_c),
    ("Fountain", fountain),
    ("MarketStall", market_stall),
    ("Palm_A", palm_a),
    ("Palm_B", palm_b),
    ("StreetLamp", street_lamp),
]
