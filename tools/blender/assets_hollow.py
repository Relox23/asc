"""The Hollow Expanse: the Pale Bastion, needle towers, quartz trees and colossal remains."""
import math
import random

from mathutils import Vector

import kit
from kit import I, T, Rz, TAU

HALF = math.pi / 2
R, SINK = 450.0, 120.0  # dome sphere radius and how far its centre sits below the ground


def _dome_r(z):
    return math.sqrt(max(R * R - (z + SINK) ** 2, 0.0))


def bastion(a):
    """Colossal white dome, front (gate) facing -Y. Ground level is z = 0."""
    stone, trim, dark, glow = a.bm("Bastion"), a.bm("BastionTrim"), a.bm("Dark"), a.bm("GlowBlue")
    phi0 = math.asin((SINK - 20) / R)
    prof = [(0, -20)] + [(R * math.cos(phi0 + (HALF - phi0) * i / 24), -SINK + R * math.sin(phi0 + (HALF - phi0) * i / 24)) for i in range(25)]
    prof[-1] = (0, R - SINK)
    kit.lathe(stone, I, prof, 72)
    for y in (40, 130, 220, 290):
        r0, r1 = _dome_r(y), _dome_r(y + 5)
        kit.lathe(trim, I, [(r0 - 1, y), (r0 + 2.4, y), (r1 + 2.4, y + 5), (r1 - 1, y + 5)], 72)
    for k in range(24):
        ang = k / 24 * TAU
        pts = []
        for i in range(14):
            z = -10 + i * 300 / 13
            r = _dome_r(z) + 1.4
            pts.append(Vector((math.cos(ang) * r, math.sin(ang) * r, z)))
        kit.tube(trim, I, pts, [2.4] * len(pts), 6)
    for k in range(24):
        ang = k / 24 * TAU + TAU / 48
        kit.box(glow, Rz(ang), (3, 1.0, 10), (0, -_dome_r(175) - 0.2, 175))
    # crown spire
    top = R - SINK
    kit.lathe(stone, I, [(0, top - 30), (24, top - 30), (24, top - 18), (27, top - 16), (23, top - 12), (23, top + 116), (12, top + 128),
                         (11, top + 216), (7, top + 220), (6, top + 230), (3.2, top + 270), (1.2, top + 320), (0.3, top + 334), (0, top + 336)], 32)
    kit.lathe(trim, I, [(22, top + 116), (33, top + 118), (33, top + 126), (12, top + 128.4)], 32)
    kit.lathe(trim, I, [(10.8, top + 160), (12.6, top + 160), (12.6, top + 164), (10.8, top + 164)], 24)
    for k in range(8):
        kit.wall_prism(trim, Rz(k / 8 * TAU), [(23, top - 12), (40, top - 12), (23, top + 60)], -1.5, 1.5)
    kit.sphere(glow, T(0, 0, top + 338), 4.5, 12, 6)
    # the great gate
    gy = -(math.sqrt(R * R - SINK * SINK) - 18)
    kit.box(dark, I, (64, 60, 92), (0, gy, 46))
    for x in (-40, 40):
        kit.box(trim, I, (16, 18, 112), (x, gy - 26, 55), bevel=0.8)
    kit.box(trim, I, (98, 20, 16), (0, gy - 26, 116), bevel=0.8)
    for k, inset in enumerate((0, 6)):
        y = gy - 33.5 - k * 1.5
        kit.box(stone, I, (6, 3, 96 - inset), (-35 + inset, y, (96 - inset) / 2))
        kit.box(stone, I, (6, 3, 96 - inset), (35 - inset, y, (96 - inset) / 2))
        kit.box(stone, I, (76 - inset * 2, 3, 6), (0, y, 95 - inset))
    kit.box(glow, I, (64, 4, 3), (0, gy - 31, 100))


def needle_tower(a):
    """Thin white tower: 320 studs to the top disc, spike to ~412."""
    stone, trim, glow = a.bm("Bastion"), a.bm("BastionTrim"), a.bm("GlowBlue")
    H = 320.0
    kit.box(trim, I, (50, 50, 4), (0, 0, 0))
    kit.box(trim, I, (44, 44, 24), (0, 0, 8), bevel=1.0)
    kit.lathe(stone, I, [(0, 20), (15, 20), (13, 24), (13, H * 0.55), (18, H * 0.55 + 1), (18, H * 0.55 + 5), (13, H * 0.55 + 6),
                         (12, H), (24, H + 1), (24, H + 6), (6, H + 7), (6, H + 36), (3, H + 38), (0.4, H + 90), (0, H + 92)], 24)
    for k in range(4):
        kit.wall_prism(trim, Rz(k * HALF + math.pi / 4), [(13, 24), (24, 24), (13, 130)], -1.2, 1.2)
    kit.lathe(trim, I, [(12.6, H * 0.3), (13.8, H * 0.3), (13.8, H * 0.3 + 3), (12.6, H * 0.3 + 3)], 24)
    kit.sphere(glow, T(0, 0, H + 93), 3, 10, 5)


def quartz_tree(a, seed):
    rng = random.Random(seed)
    q = a.bm("Quartz")

    def branch(p, d, L, r, depth):
        e = p + d * L
        kit.tube(q, I, [p, e], [r, r * 0.62], 6)
        if depth > 0:
            for _ in range(rng.randint(2, 3)):
                nd = (d + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.1, 0.5))) * 0.8).normalized()
                branch(e, nd, L * rng.uniform(0.55, 0.75), r * 0.6, depth - 1)
        else:
            M = T(*e) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
            kit.lathe(q, M, [(0, -0.2), (r * 1.8, L * 0.18), (0, L * 0.6)], 6)

    lean = Vector((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), 1)).normalized()
    branch(Vector((0, 0, -3)), lean, rng.uniform(15, 21), rng.uniform(2.4, 3.2), 2)


def quartz_a(a):
    quartz_tree(a, 51)


def quartz_b(a):
    quartz_tree(a, 52)


def skeleton(a):
    """Colossal remains, 140 studs long, skull toward -Y."""
    rng = random.Random(53)
    bone, dark = a.bm("Bone"), a.bm("Dark")
    n = 20
    spine = [Vector((0, 70 - t * 140, 4 + math.sin(t * math.pi) * 10)) for t in (i / n for i in range(n + 1))]
    for s, p in enumerate(spine):
        t = s / n
        r = 2.8 + 2.4 * math.sin(t * math.pi)
        d = (spine[min(s + 1, n)] - spine[max(s - 1, 0)]).normalized()
        M = T(*p) @ d.to_track_quat("Z", "Y").to_matrix().to_4x4()
        kit.lathe(bone, M, [(0, -1.6), (r * 0.8, -1.6), (r, -0.6), (r, 0.6), (r * 0.8, 1.6), (0, 1.6)], 10)
        kit.box(bone, T(*p), (1.2, 2.2, r * 1.5), (0, 0, r * 0.95))
    for s in range(4, 14):
        L = 36 - abs(s - 8.5) * 3.2
        for side in (-1, 1):
            if rng.random() < 0.12:
                continue
            k_max = 7 if rng.random() > 0.2 else 4
            pts, radii = [], []
            for k in range(k_max):
                ang = k / 6 * math.pi * 0.92
                pts.append(spine[s] + Vector((side * math.sin(ang) * L * 0.55, 0, (math.cos(ang) - 1) * L * 0.48)))
                radii.append(1.7 - k * 0.15)
            kit.tube(bone, I, pts, radii, 6)
    head = spine[-1] + Vector((0, -15, -2))
    kit.blob(bone, I, head, 12, 2, 0.08, 1.2, 5, (0.95, 1.35, 0.85))
    kit.blob(bone, I, head + Vector((0, -9, -6)), 7, 2, 0.1, 1.5, 6, (0.8, 1.45, 0.45))
    for x in (-5.6, 5.6):
        kit.blob(dark, I, head + Vector((x, -10.4, 3)), 3.2, 1, 0.05, 1, 7, (1, 0.6, 0.9))
    for k in range(8):
        x = -4.2 + k * 1.2
        kit.lathe(bone, T(head.x + x, head.y - 17.5, head.z - 3.6), [(0, 0), (0.45, 0), (0, 2.2)], 4)
    for side in (-1, 1):
        b = head + Vector((side * 7, 2, 6))
        kit.tube(bone, I, [b, b + Vector((side * 6, 6, 10)), b + Vector((side * 10, 16, 12)), b + Vector((side * 9, 26, 9))], [2.6, 2.0, 1.2, 0.3], 8)


ASSETS = [
    ("Bastion", bastion),
    ("NeedleTower", needle_tower),
    ("QuartzTree_A", quartz_a),
    ("QuartzTree_B", quartz_b),
    ("Skeleton", skeleton),
]
