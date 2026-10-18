"""
Modelling toolkit for the island's Blender assets.

Conventions (all assets):
  * 1 Blender unit = 1 Roblox stud, Z up, the asset's front faces -Y,
    the asset's origin is its ground point.
  * Geometry is grouped by *style* (material). Each style becomes one mesh
    object named "<Asset>__<Style>" ("<Asset>__<Style>_2" ... when a style is
    split to stay under Roblox's per-mesh triangle limit).
  * Three tiny marker meshes per asset ("<Asset>__Origin", "__Up", "__Front")
    let the Roblox generator recover position, orientation and scale however
    Studio's importer converted the axes and units.
"""
import math
import random

import bpy  # noqa: F401  (must be imported before bmesh with the pip module)
import bmesh
from mathutils import Matrix, Quaternion, Vector, noise

TAU = math.pi * 2
MAX_TRIS = 9000
EXPORT_SCALE = 0.1
MARKER_LEN = 10.0
I = Matrix()

# Preview colours (Blender renders only; Roblox colours live in AssetLibrary.luau)
STYLE_COLORS = {
    "Marble": (244, 240, 230), "Stone": (232, 218, 190), "Plaster": (236, 226, 206),
    "Sandstone": (198, 156, 108), "Gold": (214, 172, 74), "Teal": (30, 116, 124),
    "Dark": (34, 28, 28), "Door": (92, 60, 40), "Wood": (132, 98, 66), "WoodDark": (70, 50, 38),
    "Fabric": (166, 46, 44), "Fabric2": (222, 152, 44), "Shingle": (70, 82, 104), "Thatch": (146, 120, 80),
    "Tile": (62, 60, 66), "Shoji": (252, 238, 210), "Vermilion": (178, 50, 38), "Black": (30, 28, 28),
    "Granite": (150, 148, 144), "Snow": (242, 247, 252), "Bark": (98, 74, 52), "BarkPale": (226, 222, 210),
    "Leaves": (84, 148, 62), "LeavesLight": (130, 186, 84), "LeavesDark": (34, 64, 48),
    "Blossom": (244, 170, 200), "Moss": (82, 120, 56), "Frond": (72, 134, 54), "Coconut": (92, 66, 38),
    "Quartz": (236, 240, 246), "Bone": (232, 226, 208), "Concrete": (98, 96, 94), "Glass": (30, 38, 46),
    "Rebar": (96, 58, 40), "Paint": (110, 58, 40), "Rubber": (24, 22, 22), "Metal": (60, 58, 56),
    "White": (240, 238, 232), "Red": (178, 44, 40), "Canvas": (214, 196, 168), "Bronze": (74, 64, 50),
    "Glow": (255, 214, 150), "GlowBlue": (150, 210, 255), "Lantern": (232, 80, 48), "Rope": (222, 200, 150),
    "Bastion": (236, 236, 240), "BastionTrim": (210, 212, 222), "GlassClear": (210, 235, 250),
    "Fruit": (232, 120, 40), "Fruit2": (200, 40, 50), "Clay": (176, 96, 60), "Iron": (50, 50, 54),
    "Hull": (92, 66, 46), "Trim": (222, 160, 104),
    "LeavesGold": (236, 206, 96), "GlowGreen": (170, 255, 220), "Flower2": (250, 220, 90),
}


# ----------------------------------------------------------------------------- matrices
def T(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def Rz(a):
    return Matrix.Rotation(a, 4, "Z")


def Rx(a):
    return Matrix.Rotation(a, 4, "X")


def Ry(a):
    return Matrix.Rotation(a, 4, "Y")


def Sc(x, y=None, z=None):
    return Matrix.Diagonal((x, x if y is None else y, x if z is None else z, 1.0))


def V(*a):
    return Vector(a)


# ----------------------------------------------------------------------------- asset container
class Asset:
    """Collects geometry per style. a.bm("Stone") returns that style's bmesh."""

    def __init__(self, name):
        self.name = name
        self.pieces = {}

    def bm(self, style):
        if style not in STYLE_COLORS:
            raise KeyError(f"unknown style {style}")
        b = self.pieces.get(style)
        if b is None:
            b = bmesh.new()
            self.pieces[style] = b
        return b

    def tris(self):
        return sum(sum(len(f.verts) - 2 for f in b.faces) for b in self.pieces.values())


def _face(bm, verts, smooth):
    f = bm.faces.new(verts)
    f.smooth = smooth
    return f


# ----------------------------------------------------------------------------- primitives
def box(bm, M=I, size=(1, 1, 1), center=(0, 0, 0), bevel=0.0, smooth=False):
    """Axis-aligned box (in M's space). Optional chamfered edges."""
    sx, sy, sz = (s / 2 for s in size)
    cx, cy, cz = center
    vs = []
    for x in (-sx, sx):
        for y in (-sy, sy):
            for z in (-sz, sz):
                vs.append(bm.verts.new(M @ Vector((cx + x, cy + y, cz + z))))
    idx = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    faces = [_face(bm, [vs[i] for i in q], smooth) for q in idx]
    if bevel > 0:
        edges = list({e for f in faces for e in f.edges})
        bmesh.ops.bevel(bm, geom=edges + vs, offset=min(bevel, min(size) * 0.45), segments=1,
                        affect="EDGES", profile=0.5)
    return faces


def lathe(bm, M, profile, segs=24, smooth=True, sharp=None, angle0=0.0):
    """Revolve (radius, z) points around Z. Corners sharper than `sharp` degrees stay crisp.
    Faces point to the right of the direction of travel along the profile, so a
    profile drawn bottom -> outside -> top gives an outward-facing solid."""
    def ring(r, z):
        if r < 1e-5:
            return [bm.verts.new(M @ Vector((0, 0, z)))]
        return [bm.verts.new(M @ Vector((math.cos(angle0 + k / segs * TAU) * r,
                                         math.sin(angle0 + k / segs * TAU) * r, z))) for k in range(segs)]

    def bridge(a, b):
        if len(a) == 1 and len(b) == 1:
            return
        if len(a) == 1:
            for k in range(len(b)):
                _face(bm, (a[0], b[(k + 1) % len(b)], b[k]), smooth)
        elif len(b) == 1:
            for k in range(len(a)):
                _face(bm, (a[k], a[(k + 1) % len(a)], b[0]), smooth)
        else:
            n = len(a)
            for k in range(n):
                _face(bm, (a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]), smooth)

    prev = None
    for r, z in profile:
        cur = ring(r, z)
        if prev is not None:
            bridge(prev, cur)
        prev = cur


def cylinder(bm, M, r0, h, r1=None, segs=16, z0=0.0, smooth=True):
    r1 = r0 if r1 is None else r1
    lathe(bm, M, [(0, z0), (r0, z0), (r1, z0 + h), (0, z0 + h)], segs, smooth)


def sphere(bm, M, r, segs=16, rings=8, smooth=True):
    prof = [(math.sin(math.pi * i / rings) * r, -math.cos(math.pi * i / rings) * r) for i in range(rings + 1)]
    lathe(bm, M, prof, segs, smooth, sharp=89)


def dome(bm, M, r, h=None, segs=24, rings=8, smooth=True, base_lip=0.0):
    h = r if h is None else h
    prof = [(r + base_lip, 0)] + [(math.cos(math.pi / 2 * i / rings) * r, math.sin(math.pi / 2 * i / rings) * h)
                                  for i in range(rings + 1)]
    lathe(bm, M, prof, segs, smooth, sharp=60)


def onion_profile(r, h, base_r=None, n=14, tip=0.05):
    """Bulbous onion dome profile from z=0 (base radius) to the tip at z=h."""
    base_r = r * 0.92 if base_r is None else base_r
    pts = []
    for i in range(n + 1):
        t = i / n
        # bulge peaks at t~0.3, then pinches into a point
        bulge = math.sin(min(t / 0.62, 1) * math.pi * 0.62 + 0.25) / math.sin(0.62 * math.pi * 0.62 + 0.25)
        rr = r * (1 - t) ** 0.85 * min(bulge, 1.12)
        if i == 0:
            rr = base_r
        pts.append((max(rr, tip if i < n else 0), t * h))
    pts[-1] = (0, h)
    return pts


def tube(bm, M, pts, radii, segs=8, smooth=True, caps=True, up=Vector((0, 0, 1))):
    """Circle swept along a polyline with per-point radius."""
    sec = [(math.cos(k / segs * TAU), math.sin(k / segs * TAU)) for k in range(segs)]
    sweep(bm, M, pts, lambda i, t: [(x * radii[i], y * radii[i]) for x, y in sec], smooth, caps, up)


def _frames(pts, up):
    n = len(pts)
    tans = []
    for i in range(n):
        a = pts[max(i - 1, 0)]
        b = pts[min(i + 1, n - 1)]
        d = b - a
        tans.append(d.normalized() if d.length > 1e-9 else Vector((0, 0, 1)))
    normal = up - tans[0] * up.dot(tans[0])
    if normal.length < 1e-4:
        normal = Vector((1, 0, 0)) - tans[0] * tans[0].x
    normal.normalize()
    frames = []
    for i in range(n):
        if i > 0:
            q = tans[i - 1].rotation_difference(tans[i])
            normal = q @ normal
            normal = (normal - tans[i] * normal.dot(tans[i])).normalized()
        frames.append((tans[i], normal, tans[i].cross(normal)))
    return frames


def sweep(bm, M, pts, section, smooth=False, caps=True, up=Vector((0, 0, 1))):
    """Sweep a closed 2D section (section(i, t) -> [(u, v)]) along points.
    u runs along the frame normal, v along the binormal; list the section
    counter-clockwise in (u, v) so faces point outward."""
    pts = [Vector(p) for p in pts]
    frames = _frames(pts, Vector(up))
    rings = []
    n = len(pts)
    for i, (p, (t, nrm, bin_)) in enumerate(zip(pts, frames)):
        sec = section(i, i / max(n - 1, 1))
        rings.append([bm.verts.new(M @ (p + nrm * u + bin_ * v)) for u, v in sec])
    for i in range(n - 1):
        a, b = rings[i], rings[i + 1]
        m = len(a)
        for k in range(m):
            _face(bm, (a[k], a[(k + 1) % m], b[(k + 1) % m], b[k]), smooth)
    if caps:
        _face(bm, list(reversed(rings[0])), False)
        _face(bm, rings[-1], False)


def beam(bm, M, a, b, w, h, up=Vector((0, 0, 1)), smooth=False):
    """Rectangular beam from a to b, w across, h along `up`."""
    sweep(bm, M, [Vector(a), Vector(b)],
          lambda i, t: [(-h / 2, -w / 2), (h / 2, -w / 2), (h / 2, w / 2), (-h / 2, w / 2)], smooth, True, up)


def _signed_area(pts):
    return sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2


def prism(bm, M, outline, z0, z1, smooth=False):
    """Extrude a 2D outline (XY plane, either winding) from z0 to z1."""
    if _signed_area(outline) < 0:
        outline = list(reversed(outline))
    lo = [bm.verts.new(M @ Vector((x, y, z0))) for x, y in outline]
    hi = [bm.verts.new(M @ Vector((x, y, z1))) for x, y in outline]
    _face(bm, list(reversed(lo)), False)
    _face(bm, hi, False)
    n = len(outline)
    for k in range(n):
        _face(bm, (lo[k], lo[(k + 1) % n], hi[(k + 1) % n], hi[k]), smooth)


def wall_prism(bm, M, outline_xz, y0, y1, smooth=False):
    """Extrude an outline drawn in the XZ plane (x, z) through Y from y0 to y1 (either winding)."""
    prism(bm, M @ Rx(math.pi / 2), [(x, z) for x, z in outline_xz], -y1, -y0, smooth)


def pointed_arc(x0, x1, z, rise, segs=8):
    """Points of a pointed (two-centred) arch from (x0, z) over the apex to (x1, z)."""
    w = x1 - x0
    rad = w * 0.8
    cl = x0 + rad  # the left arc is centred on the spring line, right of x0
    apex_h = math.sqrt(max(rad * rad - (w / 2 - rad) ** 2, 1e-6))
    pts = []
    for i in range(segs + 1):
        x = x0 + w / 2 * i / segs
        h = math.sqrt(max(rad * rad - (x - cl) ** 2, 0.0))
        pts.append((x, z + h / apex_h * rise))
    for i in range(segs - 1, -1, -1):
        x, zz = pts[i]
        pts.append((x0 + x1 - x, zz))
    return pts


def arch_outline(w, h, pointed=True, segs=10, spring=None):
    """Opening outline in XZ: rectangle of width w rising to an arch, total height h."""
    hw = w / 2
    pts = [(-hw, 0.0)]
    if pointed:
        spring = h - w * 0.62 if spring is None else spring
        rad = w * 0.8
        # two arcs centred on the opposite sides meeting at the apex
        apex_z = h
        for i in range(segs + 1):
            t = i / segs
            x = -hw + t * hw
            cx = -hw + rad
            z = spring + math.sqrt(max(rad * rad - (x - cx) ** 2, 0)) * (apex_z - spring) / math.sqrt(max(rad * rad - (0 - cx) ** 2, 1e-6))
            pts.append((x, z))
        for i in range(1, segs + 1):
            x, z = pts[segs + 1 - i]
            pts.append((-x, z))
    else:
        spring = h - hw if spring is None else spring
        for i in range(segs + 1):
            a = math.pi - math.pi * i / segs
            pts.append((math.cos(a) * hw, spring + math.sin(a) * hw))
    pts.append((hw, 0.0))
    # dedupe consecutive duplicates
    out = []
    for p in pts:
        if not out or (abs(out[-1][0] - p[0]) > 1e-6 or abs(out[-1][1] - p[1]) > 1e-6):
            out.append(p)
    return out


def niche(bm, M, w, h, depth, pointed=True, segs=8):
    """Arched recess panel (a thin solid in XZ, extruded along -Y by `depth`)."""
    outline = arch_outline(w, h, pointed, segs)
    wall_prism(bm, M, outline, -depth, 0.0)


def arch_frame(bm, M, w, h, thick, depth, pointed=True, segs=8):
    """Moulding following an arch opening (open at the bottom)."""
    outline = arch_outline(w + thick, h + thick * 0.5, pointed, segs)
    pts = [Vector((x, 0, z)) for x, z in outline]
    sweep(bm, M, pts, lambda i, t: [(-depth / 2, -thick / 2), (depth / 2, -thick / 2),
                                    (depth / 2, thick / 2), (-depth / 2, thick / 2)],
          False, True, Vector((0, 1, 0)))


def blob(bm, M, center, radius, subdiv=2, amp=0.22, freq=1.4, seed=0.0, scale=(1, 1, 1), smooth=True):
    """Noisy icosphere: foliage clumps, rocks, clouds."""
    res = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    verts = res["verts"]
    c = Vector(center)
    off = Vector((seed * 13.1, seed * 7.7, seed * 3.3))
    for v in verts:
        d = v.co.normalized()
        n = noise.noise(d * freq + off)
        v.co = M @ (c + Vector((d.x * scale[0], d.y * scale[1], d.z * scale[2])) * radius * (1 + amp * n))
    for f in {f for v in verts for f in v.link_faces}:
        f.smooth = smooth


def star_cone(bm, M, r, h, points=9, notch=0.68, droop=0.0, z0=0.0, jitter=0.0, rng=None, underside=True, smooth=False):
    """Cone with a star-shaped base (pine tiers, snow caps). Tips droop by `droop`."""
    rng = rng or random.Random(1)
    base = []
    for k in range(points * 2):
        a = k / (points * 2) * TAU
        tip = k % 2 == 0
        rr = r * (1 if tip else notch) * (1 + rng.uniform(-jitter, jitter))
        z = z0 - (droop if tip else droop * 0.2)
        base.append(bm.verts.new(M @ Vector((math.cos(a) * rr, math.sin(a) * rr, z))))
    apex = bm.verts.new(M @ Vector((0, 0, z0 + h)))
    n = len(base)
    for k in range(n):
        _face(bm, (base[k], base[(k + 1) % n], apex), smooth)
    if underside:
        hub = bm.verts.new(M @ Vector((0, 0, z0 + h * 0.18)))
        for k in range(n):
            _face(bm, (base[(k + 1) % n], base[k], hub), smooth)


def ribbon(bm, M, left, right, smooth=True, double=True, gap=0.06):
    """Surface strip between two point rows (leaves, cloth). Double-sided by default:
    the two layers sit `gap` apart so they never shadow each other."""
    left = [Vector(p) for p in left]
    right = [Vector(p) for p in right]
    n = len(left)
    normals = []
    for i in range(n):
        along = left[min(i + 1, n - 1)] - left[max(i - 1, 0)]
        nn = (right[i] - left[i]).cross(along)
        normals.append(nn.normalized() if nn.length > 1e-9 else Vector((0, 0, 1)))
    off = gap / 2 if double else 0.0
    L = [bm.verts.new(M @ (p + normals[i] * off)) for i, p in enumerate(left)]
    R = [bm.verts.new(M @ (p + normals[i] * off)) for i, p in enumerate(right)]
    for i in range(n - 1):
        _face(bm, (L[i], R[i], R[i + 1], L[i + 1]), smooth)
    if double:
        L2 = [bm.verts.new(M @ (p - normals[i] * off)) for i, p in enumerate(left)]
        R2 = [bm.verts.new(M @ (p - normals[i] * off)) for i, p in enumerate(right)]
        for i in range(n - 1):
            _face(bm, (L2[i + 1], R2[i + 1], R2[i], L2[i]), smooth)


def stairs(bm, M, width, steps, rise, run, z0=0.0):
    """Steps climbing toward +Y, first step at y=0."""
    for k in range(steps):
        top = z0 + (k + 1) * rise
        box(bm, M, (width, run, top - z0 + 0.4), (0, k * run + run / 2, (top + z0 - 0.4) / 2))


def railing(bm_post, bm_rail, M, pts, h=3.0, every=4.0, post=0.5, rail=0.3, rails=2):
    pts = [Vector(p) for p in pts]
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        d = (b - a)
        n = max(1, int(d.length / every))
        for k in range(n + (1 if i == len(pts) - 2 else 0)):
            p = a + d * (k / n)
            box(bm_post, M, (post, post, h), (p.x, p.y, p.z + h / 2))
        for r in range(rails):
            z = h * (0.45 + 0.55 * r / max(rails - 1, 1))
            beam(bm_rail, M, a + Vector((0, 0, z)), b + Vector((0, 0, z)), rail, rail)


def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3


def bezier_pts(p0, p1, p2, p3, n):
    p0, p1, p2, p3 = (Vector(p) for p in (p0, p1, p2, p3))
    return [bezier(p0, p1, p2, p3, i / n) for i in range(n + 1)]


# ----------------------------------------------------------------------------- roofs
def jroof(bm, M, W, D, rise, curl=2.0, thick=1.2, segs_u=10, segs_t=6, ridge=None, z0=0.0, sag=1.7, snow=False):
    """Japanese hip roof: concave slopes, corners curling upward.
    Eaves rectangle W x D at height z0; ridge (length W-D unless given) at z0+rise."""
    a, b = W / 2, D / 2
    rl = max(a - b, 0.0) if ridge is None else ridge / 2

    def height(t, edge):
        return z0 + rise * t ** sag + curl * (1 - t) ** 2 * edge ** 4

    def surface(P, nu, nt, offset):
        rows = []
        for j in range(nt + 1):
            t = j / nt
            row = []
            for i in range(nu + 1):
                u = -1 + 2 * i / nu
                x, y, edge = P(u, t)
                row.append(bm.verts.new(M @ Vector((x, y, height(t, edge) + offset))))
            rows.append(row)
        return rows

    def front(sign):
        def P(u, t):
            ex, ey = u * a, sign * b
            rx, ry = u * rl, 0.0
            return ex + (rx - ex) * t, ey + (ry - ey) * t, abs(u)
        return P

    def side(sign):
        def P(v, t):
            ex, ey = sign * a, v * b
            rx, ry = sign * rl, 0.0
            return ex + (rx - ex) * t, ey + (ry - ey) * t, abs(v)
        return P

    def quad(vs, flip, smooth):
        _face(bm, vs[::-1] if flip else vs, smooth)

    half = max(4, segs_u // 2)
    for P, nu, flip in ((front(-1), segs_u, False), (front(1), segs_u, True), (side(-1), half, True), (side(1), half, False)):
        top = surface(P, nu, segs_t, 0.0)
        bot = surface(P, nu, segs_t, -thick)
        for j in range(segs_t):
            for i in range(nu):
                quad((top[j][i], top[j][i + 1], top[j + 1][i + 1], top[j + 1][i]), flip, True)
                quad((bot[j][i], bot[j + 1][i], bot[j + 1][i + 1], bot[j][i + 1]), flip, True)
        for i in range(nu):  # eave edge band
            quad((bot[0][i], bot[0][i + 1], top[0][i + 1], top[0][i]), flip, False)


def ridge_caps(bm, M, W, D, rise, z0=0.0, r=0.6, sag=1.7, curl=2.0, ridge=None):
    """Round caps along the ridge and the four hips of a jroof."""
    a, b = W / 2, D / 2
    rl = max(a - b, 0.0) if ridge is None else ridge / 2
    top = z0 + rise
    if rl > 0.01:
        tube(bm, M, [Vector((-rl - r, 0, top + r * 0.6)), Vector((rl + r, 0, top + r * 0.6))], [r * 1.3, r * 1.3], 8)
    for sx in (-1, 1):
        for sy in (-1, 1):
            pts = []
            for j in range(7):
                t = j / 6
                x = sx * a + (sx * rl - sx * a) * t
                y = sy * b + (0 - sy * b) * t
                z = z0 + rise * t ** sag + curl * (1 - t) ** 2 + r * 0.5
                pts.append(Vector((x, y, z)))
            tube(bm, M, pts, [r] * len(pts), 6)


def gable_roof(bm, M, W, D, rise, thick=0.8, overhang=1.5, z0=0.0, smooth=False):
    """Straight gable roof, ridge along X: two slabs resting on the slope lines."""
    th = math.atan2(rise, D / 2)
    length = math.hypot(D / 2, rise) + overhang
    for s in (-1, 1):
        phi = -s * th
        down = Vector((0, s * math.cos(th), -math.sin(th)))
        nrm = Vector((0, -math.sin(phi), math.cos(phi)))
        c = Vector((0, 0, z0 + rise)) + down * (length / 2) + nrm * (thick / 2)
        box(bm, M @ Matrix.Translation(c) @ Rx(phi), (W + 2 * overhang, length, thick), smooth=smooth)


def gable_end(bm, M, D, rise, y_thickness, x, z0=0.0):
    """Triangular gable wall at x (plane YZ), thickness along X."""
    outline = [(-D / 2, z0), (D / 2, z0), (0, z0 + rise)]
    # draw in XZ then rotate so it sits in the YZ plane
    wall_prism(bm, M @ T(x, 0, 0) @ Rz(math.pi / 2), outline, -y_thickness / 2, y_thickness / 2)


# ----------------------------------------------------------------------------- finishing
def _box_uv(bm, scale=8.0):
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        n = f.normal
        ax = max(range(3), key=lambda i: abs(n[i]))
        for loop in f.loops:
            co = loop.vert.co
            if ax == 0:
                loop[uv].uv = (co.y / scale, co.z / scale)
            elif ax == 1:
                loop[uv].uv = (co.x / scale, co.z / scale)
            else:
                loop[uv].uv = (co.x / scale, co.y / scale)


def _split(bm, limit):
    faces = list(bm.faces)
    if len(faces) <= limit:
        return [bm]
    lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
    hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
    axis = max(range(3), key=lambda i: hi[i] - lo[i])
    faces.sort(key=lambda f: f.calc_center_median()[axis])
    out = []
    for start in range(0, len(faces), limit):
        nb = bmesh.new()
        vmap = {}
        for f in faces[start:start + limit]:
            vs = []
            for v in f.verts:
                nv = vmap.get(v)
                if nv is None:
                    nv = nb.verts.new(v.co)
                    vmap[v] = nv
                vs.append(nv)
            nf = nb.faces.new(vs)
            nf.smooth = f.smooth
        nb.normal_update()
        for e in nb.edges:
            lf = e.link_faces
            if len(lf) != 2 or lf[0].normal.angle(lf[1].normal, 0) > SHARP_ANGLE:
                e.smooth = False
        out.append(nb)
    bm.free()
    return out


_materials = {}


def material(style):
    m = _materials.get(style)
    if m:
        return m
    m = bpy.data.materials.new("M_" + style)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    r, g, b = (c / 255 for c in STYLE_COLORS[style])
    bsdf.inputs["Base Color"].default_value = (r ** 2.2, g ** 2.2, b ** 2.2, 1)
    bsdf.inputs["Roughness"].default_value = 0.6
    if style in ("Gold", "Bronze", "Metal", "Iron"):
        bsdf.inputs["Metallic"].default_value = 0.85
        bsdf.inputs["Roughness"].default_value = 0.35
    if style.startswith("Glow") or style == "Lantern":
        bsdf.inputs["Emission Color"].default_value = (r ** 2.2, g ** 2.2, b ** 2.2, 1)
        bsdf.inputs["Emission Strength"].default_value = 3
    if style in ("Glass", "GlassClear", "Quartz"):
        bsdf.inputs["Roughness"].default_value = 0.1
    _materials[style] = m
    return m


def _object(name, bm, collection, style, offset):
    for v in bm.verts:
        v.co += offset
    _box_uv(bm)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    if style:
        obj.data.materials.append(material(style))
    return obj


def _marker(name, pos, collection):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=1, radius=0.6, matrix=Matrix.Translation(pos))
    return _object(name, bm, collection, None, Vector())


SHARP_ANGLE = math.radians(38)
REPORT = {"flipped": 0}


def _components(bm):
    seen = set()
    for f in bm.faces:
        if f in seen:
            continue
        comp, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            comp.append(g)
            for v in g.verts:
                for h in v.link_faces:
                    if h not in seen:
                        seen.add(h)
                        stack.append(h)
        yield comp


def _repair(bm):
    """Flip closed pieces that came out inside-out (negative signed volume)."""
    for comp in _components(bm):
        cs = set(comp)
        closed = all(sum(1 for lf in e.link_faces if lf in cs) == 2 for f in comp for e in f.edges)
        if not closed:
            continue
        vol = 0.0
        for f in comp:
            v0 = f.verts[0].co
            for k in range(1, len(f.verts) - 1):
                vol += v0.dot(f.verts[k].co.cross(f.verts[k + 1].co))
        if vol < 0:
            bmesh.ops.reverse_faces(bm, faces=comp)
            REPORT["flipped"] += 1


def _sharpen(bm):
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        lf = e.link_faces
        if len(lf) != 2 or lf[0].normal.angle(lf[1].normal, 0) > SHARP_ANGLE:
            e.smooth = False


def _prepare(bm, limit):
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    _repair(bm)
    bm.normal_update()
    _sharpen(bm)
    return _split(bm, limit)


def finish_named(pieces, collection, limit=MAX_TRIS):
    """pieces: {object name: (style, bmesh)} -> objects (no markers)."""
    objs = []
    for name, (style, bm) in pieces.items():
        chunks = _prepare(bm, limit)
        for i, chunk in enumerate(chunks):
            objs.append(_object(name + (f"_{i + 1}" if len(chunks) > 1 else ""), chunk, collection, style, Vector()))
    return objs


def finish(asset, collection, offset=Vector((0, 0, 0)), limit=MAX_TRIS):
    """Turn an Asset into Blender objects (+ markers). Returns the objects."""
    objs = []
    offset = Vector(offset)
    for style, bm in asset.pieces.items():
        chunks = _prepare(bm, limit)
        for i, chunk in enumerate(chunks):
            name = f"{asset.name}__{style}" + (f"_{i + 1}" if len(chunks) > 1 else "")
            chunk.normal_update()
            objs.append(_object(name, chunk, collection, style, offset))
    objs.append(_marker(f"{asset.name}__Origin", offset, collection))
    objs.append(_marker(f"{asset.name}__Up", offset + Vector((0, 0, MARKER_LEN)), collection))
    objs.append(_marker(f"{asset.name}__Front", offset + Vector((0, -MARKER_LEN, 0)), collection))
    return objs
