"""Sea of Whispering Dunes: the Pleiades-style watchtower, the buried colossus and a lost caravan."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rx, Ry, Rz, TAU


# --------------------------------------------------------------------------- watchtower
def body_profile():
    p = [(0, -8), (152, -8), (152, 4), (142, 4), (142, 12), (130, 12), (130, 22), (122, 22), (122, 26)]
    p += [(44 + 78 * (1 - t) ** 2.6, 26 + 132 * t) for t in (0.02 + 0.98 * i / 18 for i in range(19))]
    p += [(52, 158), (52, 166), (44, 168)]
    z, r0, r1, top = 168, 42, 25, 560
    for k in range(5):
        za, zb = z + k * (top - z) / 5, z + (k + 1) * (top - z) / 5
        ra = r0 + (r1 - r0) * ((za - z) / (top - z)) ** 0.8
        rb = r0 + (r1 - r0) * ((zb - z) / (top - z)) ** 0.8
        p += [(ra, za + 0.1), (rb, zb - 5), (rb + 3, zb - 4), (rb + 3, zb - 1), (rb, zb)]
    p += [(25, 560), (46, 563), (48, 568), (48, 572), (27, 575), (26, 640)]
    p += [(26 + 50 * t ** 2.2, 640 + 52 * t) for t in (0.05 + 0.95 * i / 10 for i in range(11))]
    p += [(80, 696), (80, 702), (70, 704), (0, 704)]
    return p


SPIRE = [
    (0, 702), (19, 702), (19, 792), (23, 794), (23, 800), (19, 802),
    (24, 808), (29, 818), (31, 828), (28, 840), (20, 850), (11, 858), (6, 864), (6, 868),
    (40, 869), (90, 871), (124, 874), (130, 877), (124, 880), (88, 883), (40, 885), (9, 886),
    (9, 904), (13, 908), (13, 912), (9, 914), (6, 930), (4, 970), (2, 1010), (0.8, 1040), (0, 1044),
]
SATELLITE = [
    (0, 468), (1.5, 480), (3.5, 510), (6, 552), (8.5, 600), (11, 650), (13, 692),
    (12, 704), (12, 764), (15, 766), (15, 771), (12, 773), (17, 782), (19.5, 792),
    (17, 803), (11, 811), (6, 817), (4, 822), (2.4, 840), (1, 862), (0, 866),
]


def watchtower(add):
    """add(piece name, style) -> bmesh. Piece names match the standalone export."""
    kit.lathe(add("Stone_Body", "Stone"), I, body_profile(), 64)
    bands = add("Trim_Bands", "Trim")
    for z, r, h in [(22, 123, 3), (150, 50, 2), (562, 46.5, 2), (690, 79, 3)]:
        kit.lathe(bands, I, [(r - 1.5, z), (r + 0.6, z), (r + 0.6, z + h), (r - 1.5, z + h)], 64)
    ribs = add("Trim_Ribs", "Trim")
    for k in range(16):
        a = k / 16 * TAU + TAU / 32
        pts = []
        for i in range(13):
            t = i / 12
            r = 44 + 78 * (1 - t) ** 2.6 + 1.6
            pts.append(Vector((math.cos(a) * r, math.sin(a) * r, 26 + 132 * t)))
        kit.tube(ribs, I, pts, [1.9] * len(pts), 6)
    win = add("Dark_Windows", "Dark")
    for z in (230, 330, 430, 520, 610):
        t = min(max((z - 168) / (560 - 168), 0), 1)
        r = 42 + (25 - 42) * t ** 0.8 if z < 560 else 26
        for k in range(6):
            a = k / 6 * TAU + (z % 7) * 0.2
            kit.box(win, Rz(a), (2.4, 3.2, 12), (r - 0.6, 0, z))
    kit.lathe(add("Stone_Spire", "Stone"), I, SPIRE, 48)
    rings = add("Gold_Rings", "Gold")
    kit.lathe(rings, I, [(122, 874.5), (131, 876.5), (131, 877.5), (122, 879.5)], 64)
    kit.lathe(rings, I, [(22.5, 794.5), (23.6, 795), (23.6, 799), (22.5, 799.5)], 32)
    sats = add("Stone_Satellites", "Stone")
    bands2 = add("Gold_SatelliteBands", "Gold")
    for k in range(6):
        a = k / 6 * TAU
        M = T(math.cos(a) * 54, math.sin(a) * 54, 0)
        kit.lathe(sats, M, SATELLITE, 28)
        kit.lathe(bands2, M, [(14.4, 766.5), (15.6, 767), (15.6, 770), (14.4, 770.5)], 24)
        kit.lathe(bands2, M, [(11.5, 690), (14, 690.5), (14, 693), (11.5, 693.5)], 24)
    # temple entrance facing -Y
    por = add("Stone_Portico", "Stone")
    y0 = -128
    kit.box(por, I, (78, 34, 4), (0, y0 - 6, 6))
    for k in range(3):
        kit.box(por, I, (78 - k * 4, 3, 8 - k * 3), (0, y0 - 24 - k * 3, 3 - k * 1.5))
    for x in (-30, -18, -6, 6, 18, 30):
        kit.lathe(por, T(x, y0 - 16, 8), [(0, 0), (3.4, 0), (3.4, 1.2), (2.6, 2), (2.3, 30), (2.9, 32.5), (3.6, 34), (0, 34)], 16)
    kit.box(por, I, (76, 22, 6), (0, y0 - 10, 46))
    kit.wall_prism(por, I, [(-40, 49), (0, 64), (40, 49)], y0 - 22, y0 + 2)
    for x in (-36, 36):
        kit.box(por, I, (6, 40, 44), (x, y0 + 4, 26))
    kit.box(add("Dark_Door", "Dark"), I, (22, 14, 34), (0, -122, 24))
    for s in (-1, 1):
        horn(add("Stone_Horn" + ("L" if s < 0 else "R"), "Stone"), s, 0.0, 1.0, 1.0)
        horn(add("Trim_Horn" + ("L" if s < 0 else "R"), "Trim"), s, 0.42, 0.22, 1.06)


def horn(bm, s, inset, scale, depth_scale):
    pts = kit.bezier_pts((s * 285, 0, -20), (s * 272, 0, 440), (s * 222, 0, 860), (s * 30, 0, 1130), 40)

    def section(i, t):
        w = (92 * (1 - t) ** 1.2 + 3) * scale + max(0, 1 - t * 8) * 40 * scale
        dep = (50 * (1 - t) ** 1.1 + 2) * depth_scale
        off = s * inset * w / scale  # the stripe runs along the inner edge
        return [(-dep / 2, off - w / 2), (dep / 2, off - w / 2), (dep / 2, off + w / 2), (-dep / 2, off + w / 2)]

    kit.sweep(bm, I, pts, section, False, True, Vector((0, 1, 0)))


def build_watchtower(a):
    watchtower(lambda piece, style: a.bm(style))


# --------------------------------------------------------------------------- colossus
def colossus(a):
    st = a.bm("Sandstone")
    # head (front surface sits at y ~ -30 around the eyes)
    kit.blob(st, I, (0, 0, 14), 28, 3, 0.035, 1.2, 3.0, (1.0, 1.08, 1.25))
    kit.box(st, Rx(-0.15), (32, 6, 4.5), (0, -27.5, 28), bevel=1.2)  # brow
    kit.blob(st, I, (0, -25, -3), 10, 2, 0.05, 1.5, 1.0, (1.25, 0.85, 0.85))  # chin
    kit.prism(st, I, [(-6, -27), (0, -37.5), (6, -27)], 6, 23)  # nose
    kit.tube(st, I, [Vector((-8, -30.2, 6.5)), Vector((0, -32.2, 5.8)), Vector((8, -30.2, 6.5))], [1.7, 2.1, 1.7], 8)
    kit.tube(st, I, [Vector((-7, -29.6, 3.4)), Vector((0, -31.4, 2.8)), Vector((7, -29.6, 3.4))], [1.5, 1.9, 1.5], 8)
    dark = a.bm("Dark")
    for x in (-10.5, 10.5):
        kit.blob(dark, I, (x, -28.4, 18.5), 4.8, 2, 0.05, 1, x, (1.35, 0.5, 0.8))
        kit.blob(st, I, (x, -29.6, 18.5), 2.7, 2, 0.02, 1, x + 1, (1.2, 0.6, 0.85))
    # striped royal headdress with lappets and a sun disc
    gold = a.bm("Gold")
    kit.blob(st, I, (0, 3, 32), 31, 3, 0.02, 1, 7, (1.05, 1.12, 0.62))
    for k in range(7):
        z = 40 - k * 2.6
        kit.lathe(gold if k % 2 == 0 else st, T(0, 3, 0), [(30.5 - k * 0.2, z), (31.6 - k * 0.2, z), (31.6 - k * 0.2, z + 1.2), (30.5 - k * 0.2, z + 1.2)], 40)
    for x in (-27, 27):
        for k in range(8):
            z = 28 - k * 4
            kit.box(gold if k % 2 == 0 else st, Ry(-0.12 if x > 0 else 0.12), (7, 16, 4), (x + (1 if x > 0 else -1) * k * 0.4, -6, z))
    kit.lathe(gold, T(0, -30, 44) @ Rx(math.pi / 2), [(0, 0), (6, 0), (6.5, 1.2), (5, 2), (0, 2)], 24)
    for k in range(12):
        ang = k / 12 * TAU
        d = Vector((math.cos(ang), 0, math.sin(ang)))
        kit.beam(gold, I, Vector((0, -30.5, 44)) + d * 6.5, Vector((0, -30.5, 44)) + d * 10, 1.2, 0.6)
    # an enormous hand reaching out of the sand nearby
    hand = T(110, -10, 0) @ Rz(0.4) @ Rx(-0.5)
    kit.box(st, hand, (26, 10, 30), (0, 0, 10), bevel=3)
    for f in range(4):
        x = -9 + f * 6
        top = 38 - abs(f - 1.5) * 2
        pts = [Vector((x, 0, 24)), Vector((x, -1.5, top - 6)), Vector((x, -5, top)), Vector((x, -10, top + 4))]
        kit.tube(st, hand, pts, [2.9, 2.7, 2.5, 2.1], 8)
    kit.tube(st, hand, [Vector((13, 0, 10)), Vector((19, -3, 18)), Vector((22, -8, 25))], [3.2, 2.9, 2.4], 8)


# --------------------------------------------------------------------------- caravan
def wheel(wood, iron, M, r=3.0):
    pts = [Vector((0, math.cos(k / 16 * TAU) * r, math.sin(k / 16 * TAU) * r)) for k in range(17)]
    kit.tube(iron, M, pts, [0.35] * 17, 6, caps=False)
    kit.lathe(wood, M @ Ry(math.pi / 2), [(0, -0.6), (0.7, -0.6), (0.7, 0.6), (0, 0.6)], 10)
    for k in range(8):
        ang = k / 8 * TAU
        kit.beam(wood, M, Vector((0, 0, 0)), Vector((0, math.cos(ang) * r, math.sin(ang) * r)), 0.35, 0.35)


def caravan(a):
    wood, dark, canvas, iron = a.bm("Wood"), a.bm("WoodDark"), a.bm("Canvas"), a.bm("Iron")
    tilt = Ry(0.08)
    kit.box(wood, tilt, (9, 16, 1.4), (0, 0, 3.4), bevel=0.2)
    for x in (-4.3, 4.3):
        kit.box(dark, tilt, (0.5, 16, 2), (x, 0, 4.9))
    for y in (-5, 5):
        wheel(dark, iron, tilt @ T(-5.2, y, 2.8))
    wheel(dark, iron, tilt @ T(5.2, -5, 2.8))
    wheel(dark, iron, T(8, 9, 0.6) @ Ry(math.pi / 2 - 0.1))  # broken wheel in the sand
    kit.beam(dark, I, Vector((0, -8, 3)), Vector((0, -16, 1.2)), 0.6, 0.6)
    hoops = [-6.5, -2.2, 2.2, 6.5]
    for y in hoops:
        pts = [Vector((math.cos(k / 10 * math.pi) * 4.6, y, 4.6 + math.sin(k / 10 * math.pi) * 4.4)) for k in range(11)]
        kit.tube(dark, tilt, pts, [0.25] * 11, 5, caps=False)
    for i in range(len(hoops) - 1):
        if i == 1:
            continue  # torn open in the middle
        y0, y1 = hoops[i], hoops[i + 1]
        left, right = [], []
        for k in range(11):
            ang = k / 10 * math.pi
            x, z = math.cos(ang) * 4.7, 4.6 + math.sin(ang) * 4.5
            left.append(Vector((x, y0, z)))
            right.append(Vector((x, y1, z - 0.3 * math.sin(ang))))
        kit.ribbon(canvas, tilt, left, right)
    # torn flaps
    kit.ribbon(canvas, tilt, [Vector((4.7, -2.2, 4.6)), Vector((4.9, -2.2, 2.4))], [Vector((4.7, 0.3, 4.4)), Vector((5.4, 0.6, 1.4))])
    rng = random.Random(9)
    for k in range(4):
        p = Vector((rng.uniform(-9, 9), rng.uniform(-11, 11), 1.4))
        kit.box(wood, Rz(rng.uniform(0, TAU)) @ T(p.x, p.y, 0), (3, 3, 3), (0, 0, 1.4), bevel=0.2)
    for k in range(2):
        prof = [(0, 0), (1.3, 0), (1.6, 1.4), (1.65, 2), (1.6, 2.6), (1.3, 4), (0, 4)]
        M = T(-8 + k * 2.4, 8 + k, 0)
        kit.lathe(wood, M, prof, 12)
        for z in (0.6, 3.3):
            kit.lathe(iron, M, [(1.45, z), (1.75, z), (1.75, z + 0.35), (1.45, z + 0.35)], 12)
    for k in range(3):
        kit.blob(canvas, I, (rng.uniform(-3, 3), rng.uniform(-6, 6), 5.2), 1.4, 2, 0.15, 1.5, k, (1.4, 1.0, 0.8))


ASSETS = [
    ("Watchtower", build_watchtower),
    ("Colossus", colossus),
    ("Caravan", caravan),
]
