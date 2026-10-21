"""
Meshes of the intro cutscene "Awaken" (docs/intro/DESIGN.md §6) -> assets/IntroAssets.

Built like the island assets with tools/blender/kit.py: 1 unit = 1 stud, Z up,
front = -Y, the asset origin is its pivot, three marker meshes per asset
("<Asset>__Origin/__Up/__Front"), every piece named "<Asset>__<Style>[_n]".

Public API (also used by tools/blender/intro/scene.py):

  ASSETS                    [(name, fn(asset))] for SpaceDome, SoulCore, ShatteredPlanet, Rift,
                            ResonanceSword, Shockwave, SlashArc.
  STYLES                    {style: (r, g, b)} preview colours (0-255) of the intro styles.
  IntroAsset(name)          kit.Asset variant. a.bm(style) -> bmesh of that style;
                            a.bm(style, part=n) -> its own piece "<Style>_%02d" (Rift__Crack_01,
                            Rift__Shard_16, ...), never merged and never split.
  finish(asset, collection, offset=(0,0,0)) -> [objects]
                            kit.finish for intro assets: triangulate, repair, split at kit.MAX_TRIS,
                            materials, markers. Differences: numbered parts stay separate objects,
                            SpaceDome keeps its inward normals (no repair), CoreShell is flat shaded,
                            RiftView gets a planar UV (whole image on the disc), Shard objects have
                            their origin at their bbox centre (pivot for flinging them).
  build(name, collection, offset=(0,0,0)) -> [objects]   one asset, finished (incl. markers).
  material(style) -> bpy.types.Material  preview/export material (Principled BSDF). Animatable
                            controls are nodes in the material's tree:
                              nodes["tint"]      RGB   soul core colour (CoreGlow, CoreRing, Crystal, Wave, Arc)
                              nodes["glow"]      Value emission multiplier (1 = default look)
                              nodes["resonance"] Value 0 colourless crystal .. 1 glowing in the tint (Crystal)
                              nodes["opacity"]   Value alpha (Wave, Arc)
                            e.g. mat.node_tree.nodes["glow"].outputs[0].keyframe_insert("default_value", frame=f)
  RIFT_VIEW_IMAGE           path of docs/intro/rift_view.png (RiftView texture).

Piece names (binding, DESIGN §6):
  SpaceDome__Void
  SoulCore__CoreGlow, SoulCore__CoreShell, SoulCore__CoreRing
  ShatteredPlanet__Ocean_n, __Land_n, __LandDry_n, __Ice, __Cloud, __Crust, __Magma_n, __PlanetCore,
      __Debris_n   (_n only where a style needed more than one mesh)
  Rift__Crack_01..14 (01 nearest the centre), Rift__Shard_01..16, Rift__RiftEdge, Rift__RiftView
  ResonanceSword__Blade, __Crystal, __Guard, __Gold, __Grip
  Shockwave__Wave, SlashArc__Arc
"""
import math
import os
import random
import re

import bpy
import bmesh
from mathutils import Matrix, Vector, noise

import kit
from kit import I, T, Rx, Ry, Rz, TAU

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
RIFT_VIEW_IMAGE = os.path.join(ROOT, "docs", "intro", "rift_view.png")

TINT = (120, 200, 255)  # Config.TEST_COLOR, preview only

STYLES = {
    "Void": (0, 0, 0),
    "CoreGlow": TINT, "CoreShell": (225, 238, 255), "CoreRing": TINT,
    "Ocean": (28, 70, 140), "Land": (70, 120, 60), "LandDry": (150, 120, 80), "Ice": (230, 240, 250),
    "Cloud": (245, 245, 250), "Crust": (70, 55, 50), "Magma": (255, 110, 30), "PlanetCore": (255, 220, 140),
    "Debris": (85, 75, 70),
    "Crack": (230, 240, 255), "Shard": (200, 220, 255), "RiftEdge": (190, 140, 255), "RiftView": (255, 255, 255),
    "Blade": (210, 215, 225), "Crystal": (225, 235, 245), "Guard": (40, 40, 48), "Gold": (214, 172, 74),
    "Grip": (60, 40, 30),
    "Wave": (255, 255, 255), "Arc": TINT,
}
kit.STYLE_COLORS.update({k: v for k, v in STYLES.items() if k not in kit.STYLE_COLORS})

# preview emission strengths (Standard view transform); Roblox uses Neon for all of these
NEON = {"CoreGlow": 3.0, "CoreRing": 2.2, "Magma": 1.3, "PlanetCore": 1.1, "Crack": 3.0, "RiftEdge": 1.5,
        "Wave": 2.0, "Arc": 2.4}
TINTED = {"CoreGlow", "CoreRing", "Arc"}


def _lin(c):
    return tuple((x / 255) ** 2.2 for x in c)


def _lerp(a, b, t):
    return a + (b - a) * t


def _smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def fbm(p, octaves=5, lac=2.03, gain=0.5, seed=0.0):
    p = Vector(p) + Vector((seed * 17.3, seed * 9.1, seed * 5.7))
    s, a, norm = 0.0, 1.0, 0.0
    for _ in range(octaves):
        s += a * noise.noise(p)
        norm += a
        a *= gain
        p = p * lac
    return s / norm


# ----------------------------------------------------------------------------- asset container
class IntroAsset(kit.Asset):
    """kit.Asset with numbered parts and per-piece finishing options."""

    def __init__(self, name):
        super().__init__(name)
        self.raw = set()    # keys that keep their normals as built (no inside-out repair)
        self.flat = set()   # keys shaded flat (every edge sharp)
        self.uv = {}        # key -> fn(bm, uv_layer) instead of the box mapping
        self.pivot = set()  # keys whose object origin goes to the bbox centre
        self.single = set()  # keys that must stay one mesh (numbered parts)

    def bm(self, style, part=None):
        if style not in STYLES and style not in kit.STYLE_COLORS:
            raise KeyError(f"unknown style {style}")
        key = style if part is None else f"{style}_{part:02d}"
        b = self.pieces.get(key)
        if b is None:
            b = bmesh.new()
            self.pieces[key] = b
            if part is not None:
                self.single.add(key)
        return b


def style_of(key):
    return re.sub(r"_\d+$", "", key)


# ----------------------------------------------------------------------------- materials
_mats = {}


def _valid(m):
    try:
        m.name
        return True
    except ReferenceError:
        return False


def _image():
    img = bpy.data.images.get("rift_view.png")
    if img is not None:
        return img
    if os.path.exists(RIFT_VIEW_IMAGE):
        img = bpy.data.images.load(RIFT_VIEW_IMAGE, check_existing=True)
    else:  # placeholder until docs/intro/rift_view.png exists
        img = bpy.data.images.new("rift_view.png", 64, 64)
        img.pixels = [0.2, 0.45, 0.25, 1.0] * (64 * 64)
    return img


def material(style):
    m = _mats.get(style)
    if m is not None and _valid(m):
        return m
    m = bpy.data.materials.new("Intro_" + style)
    m.use_nodes = True
    nt = m.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    col = _lin(STYLES[style])
    bsdf.inputs["Base Color"].default_value = (*col, 1)
    bsdf.inputs["Roughness"].default_value = 0.6

    def value(name, v, loc):
        n = nodes.new("ShaderNodeValue")
        n.name = n.label = name
        n.outputs[0].default_value = v
        n.location = loc
        return n

    def mul(a, b, loc):
        n = nodes.new("ShaderNodeMath")
        n.operation = "MULTIPLY"
        n.location = loc
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                links.new(x, n.inputs[i])
        return n.outputs[0]

    tint = None
    if style in TINTED or style == "Crystal":
        tint = nodes.new("ShaderNodeRGB")
        tint.name = tint.label = "tint"
        tint.outputs[0].default_value = (*_lin(TINT), 1)
        tint.location = (-600, 200)
    if style in NEON:
        glow = value("glow", 1.0, (-600, -200))
        ecol = tint.outputs[0] if tint else None
        if ecol is not None:
            links.new(ecol, bsdf.inputs["Base Color"])
            links.new(ecol, bsdf.inputs["Emission Color"])
        else:
            bsdf.inputs["Emission Color"].default_value = (*col, 1)
        links.new(mul(glow.outputs[0], NEON[style], (-400, -200)), bsdf.inputs["Emission Strength"])
        if style == "Wave":  # white -> tint toward the outside is done at runtime; preview: white core, tinted rim
            bsdf.inputs["Emission Color"].default_value = (0.85, 0.95, 1.0, 1)
        if style in ("Wave", "Arc"):
            op = value("opacity", 1.0, (-600, -400))
            links.new(op.outputs[0], bsdf.inputs["Alpha"])
    elif style == "CoreShell":
        bsdf.inputs["Roughness"].default_value = 0.04
        bsdf.inputs["IOR"].default_value = 1.45
        bsdf.inputs["Transmission Weight"].default_value = 1.0
        bsdf.inputs["Base Color"].default_value = (0.88, 0.95, 1.0, 1)
        bsdf.inputs["Coat Weight"].default_value = 0.3
    elif style == "Crystal":
        res = value("resonance", 0.0, (-600, -200))
        glow = value("glow", 1.0, (-600, -400))
        mix = nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.location = (-400, 200)
        mix.inputs["A"].default_value = (*col, 1)
        links.new(res.outputs[0], mix.inputs["Factor"])
        links.new(tint.outputs[0], mix.inputs["B"])
        links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
        links.new(tint.outputs[0], bsdf.inputs["Emission Color"])
        links.new(mul(mul(res.outputs[0], glow.outputs[0], (-400, -300)), 8.0, (-250, -300)),
                  bsdf.inputs["Emission Strength"])
        trans = nodes.new("ShaderNodeMapRange")
        trans.location = (-400, 0)
        links.new(res.outputs[0], trans.inputs["Value"])
        trans.inputs["To Min"].default_value = 1.0
        trans.inputs["To Max"].default_value = 0.3
        links.new(trans.outputs[0], bsdf.inputs["Transmission Weight"])
        bsdf.inputs["Roughness"].default_value = 0.02
        bsdf.inputs["IOR"].default_value = 1.6
    elif style == "Shard":
        bsdf.inputs["Roughness"].default_value = 0.03
        bsdf.inputs["Transmission Weight"].default_value = 0.85
        bsdf.inputs["IOR"].default_value = 1.5
        bsdf.inputs["Alpha"].default_value = 0.75
        bsdf.inputs["Emission Color"].default_value = (*col, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.12
    elif style == "RiftView":
        tex = nodes.new("ShaderNodeTexImage")
        tex.image = _image()
        tex.location = (-500, 100)
        links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        links.new(tex.outputs["Color"], bsdf.inputs["Emission Color"])
        bsdf.inputs["Emission Strength"].default_value = 1.2
        bsdf.inputs["Roughness"].default_value = 0.9
    elif style == "Void":
        bsdf.inputs["Base Color"].default_value = (0, 0, 0, 1)
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    elif style == "Ocean":
        bsdf.inputs["Roughness"].default_value = 0.45
    elif style == "Ice":
        bsdf.inputs["Roughness"].default_value = 0.35
    elif style == "Cloud":
        bsdf.inputs["Roughness"].default_value = 1.0
        bsdf.inputs["Alpha"].default_value = 0.85
    elif style in ("Land", "LandDry", "Crust", "Debris", "Grip"):
        bsdf.inputs["Roughness"].default_value = 0.9
    elif style in ("Blade", "Guard", "Gold"):
        bsdf.inputs["Metallic"].default_value = 1.0
        bsdf.inputs["Roughness"].default_value = {"Blade": 0.16, "Guard": 0.32, "Gold": 0.24}[style]
    _mats[style] = m
    return m


# ----------------------------------------------------------------------------- geometry helpers
def loft(bm, rings, start_tip=None, end_tip=None, caps=True, smooth=True, cyclic=False):
    """Skin rings of equal length (lists of Vectors). Tips close the ends with a fan,
    otherwise flat caps (unless caps=False). cyclic joins the last ring to the first."""
    vs = [[bm.verts.new(p) for p in r] for r in rings]
    m = len(vs[0])
    n = len(vs)
    for i in range(n if cyclic else n - 1):
        a, b = vs[i], vs[(i + 1) % n]
        for k in range(m):
            kit._face(bm, (a[k], a[(k + 1) % m], b[(k + 1) % m], b[k]), smooth)
    if cyclic:
        return vs
    if start_tip is not None:
        t = bm.verts.new(Vector(start_tip))
        for k in range(m):
            kit._face(bm, (vs[0][(k + 1) % m], vs[0][k], t), smooth)
    elif caps:
        kit._face(bm, list(reversed(vs[0])), False)
    if end_tip is not None:
        t = bm.verts.new(Vector(end_tip))
        for k in range(m):
            kit._face(bm, (vs[-1][k], vs[-1][(k + 1) % m], t), smooth)
    elif caps:
        kit._face(bm, vs[-1], False)
    return vs


def revolve(bm, M, section, segs=48, smooth=True, angle0=0.0):
    """Closed (r, z) section revolved about Z: a closed ring solid (torus-like)."""
    rings = []
    for k in range(segs):
        a = angle0 + k / segs * TAU
        c, s = math.cos(a), math.sin(a)
        rings.append([M @ Vector((c * r, s * r, z)) for r, z in section])
    loft(bm, rings, smooth=smooth, cyclic=True)


def torus(bm, M, R, r, segs=64, sides=8):
    revolve(bm, M, [(R + math.cos(k / sides * TAU) * r, math.sin(k / sides * TAU) * r) for k in range(sides)], segs)


def gem(bm, M, rx, rz, depth, n=8, table=0.55, crown=0.6):
    """Faceted gem through the XZ plane, facing +-Y: girdle ellipse rx x rz at y=0,
    crown rings at +-crown*depth, flat tables at +-depth."""
    girdle = [Vector((math.cos(k / n * TAU) * rx, 0, math.sin(k / n * TAU) * rz)) for k in range(n)]
    def ring(y, s):
        return [M @ Vector((p.x * s, y, p.z * s)) for p in girdle]
    loft(bm, [ring(-depth, table), ring(-depth * crown, 0.86), ring(0, 1.0), ring(depth * crown, 0.86), ring(depth, table)],
         smooth=False)


def bipyramid(bm, M, r, top, bottom, n=6, twist=0.0):
    """Crystal along Z: n-gon girdle of radius r at z=0, apexes at z=top and z=-bottom."""
    g = [M @ Vector((math.cos(k / n * TAU + twist) * r, math.sin(k / n * TAU + twist) * r, 0)) for k in range(n)]
    loft(bm, [g], start_tip=M @ Vector((0, 0, -bottom)), end_tip=M @ Vector((0, 0, top)), smooth=False)


def strip_outline(pts, widths):
    """Outline polygon of a strip of half-widths along a 2D polyline."""
    n = len(pts)
    left, right = [], []
    for i in range(n):
        d = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        d.normalize()
        nrm = Vector((-d.y, d.x))
        left.append(pts[i] + nrm * widths[i])
        right.append(pts[i] - nrm * widths[i])
    return [(p.x, p.y) for p in left] + [(p.x, p.y) for p in reversed(right)]


def clean_selection(faces, min_region=4):
    """Drop faces that touch the rest only at a vertex (would make non-manifold walls)
    and tiny islands."""
    sel = set(faces)
    for _ in range(12):
        changed = False
        for v in {v for f in sel for v in f.verts}:
            around = [f for f in v.link_faces if f in sel]
            if len(around) < 2:
                continue
            groups, seen = [], set()
            for f in around:
                if f in seen:
                    continue
                comp, stack = [], [f]
                seen.add(f)
                while stack:
                    g = stack.pop()
                    comp.append(g)
                    for e in g.edges:
                        if v in e.verts:
                            for h in e.link_faces:
                                if h in sel and h not in seen and h in around:
                                    seen.add(h)
                                    stack.append(h)
                groups.append(comp)
            if len(groups) > 1:
                groups.sort(key=len)
                for comp in groups[:-1]:
                    sel.difference_update(comp)
                changed = True
        if not changed:
            break
    out, seen = [], set()
    for f in sel:
        if f in seen:
            continue
        comp, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h in sel and h not in seen:
                        seen.add(h)
                        stack.append(h)
        if len(comp) >= min_region:
            out += comp
    return out


def shell_slab(bm, src, faces, r_in, r_out, center=Vector()):
    """Closed slab from a set of faces of a sphere bmesh `src` (centred at `center`):
    top at radius r_out, bottom at r_in, walls along the boundary."""
    faces = clean_selection(faces)
    sel = set(faces)
    top, bot = {}, {}

    def vt(v, table, r):
        nv = table.get(v)
        if nv is None:
            nv = bm.verts.new(center + (v.co - center).normalized() * r)
            table[v] = nv
        return nv

    for f in faces:
        vs = list(f.verts)
        kit._face(bm, [vt(v, top, r_out) for v in vs], True)
        kit._face(bm, [vt(v, bot, r_in) for v in reversed(vs)], True)
        for lp in f.loops:
            e = lp.edge
            if any(g in sel for g in e.link_faces if g is not f):
                continue
            a, b = lp.vert, lp.link_loop_next.vert
            kit._face(bm, (vt(a, top, r_out), vt(a, bot, r_in), vt(b, bot, r_in), vt(b, top, r_out)), False)


# ----------------------------------------------------------------------------- SpaceDome
def space_dome(a):
    """Black inverted sphere r 1000, 32 x 16, normals pointing inward."""
    bm = a.bm("Void")
    kit.sphere(bm, I, 1000.0, segs=32, rings=16, smooth=True)
    bmesh.ops.reverse_faces(bm, faces=bm.faces[:])
    a.raw.add("Void")


# ----------------------------------------------------------------------------- SoulCore
def soul_core(a):
    """Glowing orb (r 0.8) in a faceted crystal shell (r 1.3) with two orbit rings (r 1.9)."""
    glow = a.bm("CoreGlow")
    bmesh.ops.create_icosphere(glow, subdivisions=4, radius=0.8)
    for f in glow.faces:
        f.smooth = True

    shell = a.bm("CoreShell")
    rng = random.Random(11)
    res = bmesh.ops.create_icosphere(shell, subdivisions=2, radius=1.3)
    for v in res["verts"]:
        d = v.co.normalized()
        # slightly uneven facets read as cut crystal, a little taller than wide
        v.co = Vector((d.x, d.y, d.z * 1.06)) * 1.3 * (1 + rng.uniform(-0.025, 0.025))
    a.flat.add("CoreShell")

    # two orbit rings: a full one and a broken (three arcs) one, with small beads riding on them
    ring = a.bm("CoreRing")
    M1 = Rz(0.35) @ Rx(math.radians(72))
    torus(ring, M1, 1.9, 0.035, 72, 8)
    M2 = Rz(-0.9) @ Ry(math.radians(64)) @ Rx(math.radians(14))
    for k in range(3):
        a0 = k / 3 * TAU + 0.25
        pts = [M2 @ Vector((math.cos(a0 + t) * 1.9, math.sin(a0 + t) * 1.9, 0)) for t in (i / 14 * 1.75 for i in range(15))]
        kit.tube(ring, I, pts, [0.012 if i in (0, 14) else 0.035 for i in range(15)], 8)
    for M, t in ((M1, 0.4), (M1, 3.6), (M2, 2.25), (M2, 4.35)):
        p = M @ Vector((math.cos(t) * 1.9, math.sin(t) * 1.9, 0))
        bmesh.ops.create_icosphere(ring, subdivisions=2, radius=0.085, matrix=Matrix.Translation(p))


# ----------------------------------------------------------------------------- ShatteredPlanet
PLANET_R = 320.0
CUT_DIR = Vector((-0.86, -0.46, 0.22)).normalized()  # mostly -X, toward -Y: a crescent seen from the front (-Y)
SOLVER = "EXACT"
CUT_R = 300.0
CUT_D = 217.0  # removes ~45 % of the sphere; the crater floor passes ~83 studs beyond the centre
PLANET_CORE_R = 110.0
CONTINENT_DIR = Vector((0.6, -0.75, 0.25)).normalized()  # so the core bulges ~27 studs out of the crater floor


def contour_split(bm, field, thr=0.0, project=None):
    """Cut the faces of `bm` along the iso-line field(co) == thr so region borders are smooth
    instead of following the triangles. project(co) -> co places the new vertices."""
    val = {v: field(v.co) for v in bm.verts}
    cross = [e for e in bm.edges if (val[e.verts[0]] - thr) * (val[e.verts[1]] - thr) < 0]
    new = set()
    for e in cross:
        v0, v1 = e.verts
        t = (thr - val[v0]) / (val[v1] - val[v0])
        _, nv = bmesh.utils.edge_split(e, v0, t)
        if project:
            nv.co = project(nv.co)
        new.add(nv)
    for f in list(bm.faces):
        vs = [v for v in f.verts if v in new]
        if len(vs) == 2:
            bmesh.utils.face_split(f, vs[0], vs[1])
    return len(new)


def _carve(planet_bm, planet_styles, cutter_bm, cutter_styles):
    """Exact boolean DIFFERENCE of two bmeshes, face styles carried over by material index.
    Returns (vertex positions, [(style, [vertex indices]), ...])."""
    scene_coll = bpy.context.scene.collection
    objs, meshes = [], []
    for name, b, styles in (("_planet", planet_bm, planet_styles), ("_cutter", cutter_bm, cutter_styles)):
        me = bpy.data.meshes.new(name)
        b.to_mesh(me)
        for s in styles:
            me.materials.append(material(s))
        ob = bpy.data.objects.new(name, me)
        scene_coll.objects.link(ob)
        objs.append(ob)
        meshes.append(me)
    planet, cutter = objs
    mod = planet.modifiers.new("Carve", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = SOLVER
    mod.object = cutter
    mod.material_mode = "TRANSFER"
    dg = bpy.context.evaluated_depsgraph_get()
    res = bpy.data.meshes.new_from_object(planet.evaluated_get(dg))
    by_name = {material(s).name: s for s in planet_styles + cutter_styles}
    names = [m.name if m else "" for m in res.materials]
    rb = bmesh.new()
    rb.from_mesh(res)
    bmesh.ops.recalc_face_normals(rb, faces=rb.faces[:])  # consistent winding even around slivers
    rb.verts.index_update()
    co = [v.co.copy() for v in rb.verts]
    out = [(by_name[names[f.material_index]], [v.index for v in f.verts]) for f in rb.faces]
    rb.free()
    for ob in objs:
        bpy.data.objects.remove(ob)
    for me in meshes + [res]:
        bpy.data.meshes.remove(me)
    return co, out


def _elevation(d):
    w = Vector((fbm(d * 1.2, 3, seed=3.0), fbm(d * 1.2, 3, seed=5.0), fbm(d * 1.2, 3, seed=7.0)))
    # a continent bias toward the intact front-right so the front view shows land
    return (fbm(d * 1.05 + w * 0.7, 5, gain=0.5, seed=1.0) + 0.08 * fbm(d * 3.1, 2, seed=9.0)
            + 0.12 * d.dot(CONTINENT_DIR))


def shattered_planet(a):
    """Earth-like planet r 320 with ~45 % torn away: a crescent from the front (-Y) with crust and a
    glowing magma layer on the fracture, the glowing core exposed, a stream of debris drifting away."""
    R = PLANET_R
    cut_c = CUT_DIR * CUT_D
    rng = random.Random(42)
    sphere = lambda co: co.normalized() * R  # noqa: E731

    # --- surface: continents with smooth coastlines, deserts, polar ice
    surf = bmesh.new()
    bmesh.ops.create_icosphere(surf, subdivisions=6, radius=R)
    # sea level from the part that survives, so the visible side has ~38 % land
    hs = sorted(_elevation(f.calc_center_median().normalized()) for f in surf.faces
                if (f.calc_center_median() - cut_c).length > CUT_R)
    sea = hs[int(len(hs) * 0.62)]

    def land_f(co):
        return _elevation(co.normalized()) - sea

    def ice_f(co):
        d = co.normalized()
        landish = _smooth(-0.02, 0.05, _elevation(d) - sea)
        return abs(d.z) + 0.05 * fbm(d * 4.0, 3, seed=13.0) - (0.94 - 0.08 * landish)

    def dry_f(co):
        d = co.normalized()
        lat = abs(d.z)
        return min(fbm(d * 2.2, 4, seed=11.0) + 0.3 * (1 - abs(lat - 0.3) / 0.3) - 0.3, 0.6 - lat)

    for fn in (land_f, ice_f, dry_f):
        contour_split(surf, fn, 0.0, sphere)
    bmesh.ops.dissolve_degenerate(surf, dist=1e-3, edges=surf.edges[:])
    for v in surf.verts:
        d = v.co.normalized()
        h = land_f(v.co)
        lift = 1.8 * _smooth(0.0, 0.05, h) + 6.0 * max(0.0, h - 0.07) + 1.5 * _smooth(-0.05, 0.05, ice_f(v.co))
        v.co = d * (R + lift)
    styles = ["Ocean", "Land", "LandDry", "Ice"]
    for f in surf.faces:
        c = f.calc_center_median()
        if ice_f(c) > 0:
            f.material_index = 3
        elif land_f(c) > 0:
            f.material_index = 2 if dry_f(c) > 0 else 1
        else:
            f.material_index = 0
        f.smooth = True

    # --- cutter: big rough sphere; its faces inside the planet become the fracture face.
    # Crust down to ~50 studs (with magma veins), then the glowing magma layer (with cooled plates).
    cutter = bmesh.new()
    bmesh.ops.create_icosphere(cutter, subdivisions=6, radius=CUT_R)
    for v in cutter.verts:
        d = v.co.normalized()
        rough = 0.03 * fbm(d * 3.0, 5, seed=21.0) + 0.01 * noise.noise(d * 14)
        v.co = cut_c + d * CUT_R * (1 + rough)

    def heat(co):
        depth = R - co.length
        h = (depth - 52 - 16 * fbm(co / 60.0, 3, seed=33.0)) / 20.0
        # cooled dark plates float on the magma layer, fewer toward the core
        plates = _smooth(-0.05, 0.03, fbm(co / 46.0, 4, seed=35.0) - 0.0016 * max(0.0, 170 - co.length))
        veins = max(0.0, 1 - abs(fbm(co / 40.0, 4, seed=31.0)) / 0.04) * _smooth(6, 20, depth)
        return max(min(h, 1.0), -1.0) - 2.2 * plates * _smooth(30, 70, depth) + 2.4 * veins

    contour_split(cutter, heat, 0.0)
    for f in cutter.faces:
        f.material_index = 1 if heat(f.calc_center_median()) > 0 else 0
    co, faces = _carve(surf, styles, cutter, ["Crust", "Magma"])
    surf.free()
    cutter.free()

    maps = {}
    for style, idx in faces:
        bm = a.bm(style)
        vm = maps.setdefault(style, {})
        vs = []
        for i in idx:
            v = vm.get(i)
            if v is None:
                v = bm.verts.new(co[i])
                vm[i] = v
            vs.append(v)
        try:
            bm.faces.new(vs).smooth = True
        except ValueError:
            pass

    # --- the core, bulging out of the crater floor
    core = a.bm("PlanetCore")
    bmesh.ops.create_icosphere(core, subdivisions=4, radius=PLANET_CORE_R)
    for f in core.faces:
        f.smooth = True

    # --- clouds: a partial shell, kept off the torn side
    cl = bmesh.new()
    bmesh.ops.create_icosphere(cl, subdivisions=6, radius=R + 7)

    def cloud_v(co):
        d = co.normalized()
        warp = Vector((fbm(d * 1.5, 2, seed=41.0), fbm(d * 1.5, 2, seed=43.0), fbm(d * 1.5, 2, seed=47.0)))
        q = Vector((d.x * 2.0, d.y * 2.0, d.z * 3.0)) + warp * 1.8
        return fbm(q, 3, gain=0.45, seed=45.0) + 0.1 * math.cos(d.z * 9.0)

    cv = sorted(cloud_v(f.calc_center_median()) for f in cl.faces)
    cthr = cv[int(len(cv) * 0.77)]

    def cloud_f(co):
        away = ((co.normalized() * (R + 7)) - cut_c).length - CUT_R * 1.07
        return min(cloud_v(co) - cthr, away / 60.0)

    contour_split(cl, cloud_f, 0.0, lambda co: co.normalized() * (R + 7))
    keep = [f for f in cl.faces if cloud_f(f.calc_center_median()) > 0]
    shell_slab(a.bm("Cloud"), cl, keep, R + 6.0, R + 8.5)
    cl.free()

    # --- debris: chunks torn out of the missing half, streaming away in a curling arc
    deb, magma = a.bm("Debris"), a.bm("Magma")
    up = Vector((0, 0, 1))
    side = up.cross(CUT_DIR).normalized()
    placed = []

    def free_spot(p, size):
        inside_cut = (p - cut_c).length < CUT_R - size * 1.3 - 45 and p.length > R * 0.8
        outside = p.length > R + size * 1.4 + 10
        clear = all((p - q).length > (size + s) * 1.25 for q, s in placed)
        return (inside_cut or outside) and clear and p.length > PLANET_CORE_R + size + 30

    tries = 0
    while len(placed) < 42 and tries < 20000:
        tries += 1
        t = rng.random() ** 0.8
        ang = 1.25 * t + rng.gauss(0, 0.08)  # the stream curls toward +side as it drifts out
        base = (Matrix.Rotation(ang, 3, up) @ CUT_DIR).normalized()
        dist = R * (0.45 + 1.15 * t) + rng.gauss(0, 18)
        p = base * dist + up * (rng.gauss(0, 30 + 60 * t) + 70 * t) + side * rng.gauss(0, 20 + 40 * t)
        size = (6 + 30 * rng.random() ** 1.8) * (1.15 - 0.6 * t)
        if not free_spot(p, size):
            continue
        placed.append((p, size))
        rot = Matrix.Rotation(rng.uniform(0, TAU), 4, "Z") @ Matrix.Rotation(rng.uniform(0, TAU), 4, "X")
        sub = 3 if size > 9 else 2
        kit.blob(deb, T(*p) @ rot, (0, 0, 0), size, sub, 0.38, 1.7, rng.uniform(0, 50),
                 (1, rng.uniform(0.6, 0.9), rng.uniform(0.45, 0.75)))
        if size > 11 and rng.random() < 0.5:  # still molten on the side that faced the core
            toward = (-p).normalized()
            kit.blob(magma, T(*(p + toward * size * 0.42)) @ rot, (0, 0, 0), size * 0.55, 2, 0.3, 2.0,
                     rng.uniform(0, 50), (1, 0.8, 0.5))
    embers = 0
    while embers < 16 and tries < 40000:  # small glowing bits
        tries += 1
        t = rng.random()
        base = (Matrix.Rotation(1.2 * t, 3, up) @ CUT_DIR).normalized()
        p = base * R * (0.5 + 1.1 * t) + up * rng.gauss(0, 40) + side * rng.gauss(0, 30)
        size = rng.uniform(1.5, 3.5)
        if free_spot(p, size):
            placed.append((p, size))
            kit.blob(magma, T(*p), (0, 0, 0), size, 2, 0.3, 2.0, rng.uniform(0, 50))
            embers += 1



# ----------------------------------------------------------------------------- Rift
RIFT_R = 14.0


def _jagged(rng, p0, p1, n, amp):
    d = p1 - p0
    nrm = Vector((-d.y, d.x)).normalized()
    pts = [p0.copy()]
    for i in range(1, n):
        t = i / n
        pts.append(p0 + d * t + nrm * rng.uniform(-amp, amp) * (1 - 0.3 * t))
    pts.append(p1.copy())
    return pts


def rift(a):
    """Space tearing open: 14 cracks, 16 glass shards, torn glowing rim, the view through it."""
    rng = random.Random(7)
    R = RIFT_R
    n = 8
    ang = [k / n * TAU + rng.uniform(-0.2, 0.2) for k in range(n)]
    dirs = [Vector((math.cos(t), math.sin(t))) for t in ang]
    C = Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6)))  # impact point
    A = [C + (dirs[k] * R - C) * rng.uniform(0.36, 0.55) for k in range(n)]  # on each spoke
    B = [dirs[k] * R for k in range(n)]

    # shards: each wedge split by a diagonal A_k -> B_k+1 into two triangles (outer one has an arc edge)
    shards = []
    for k in range(n):
        k1 = (k + 1) % n
        a0, a1 = ang[k], ang[k1] if k1 else ang[k1] + TAU
        arc = [Vector((math.cos(_lerp(a0, a1, t)), math.sin(_lerp(a0, a1, t)))) * R for t in (i / 6 for i in range(7))]
        shards.append([C, A[k], B[k1]])
        shards.append([A[k]] + arc)
    shards.sort(key=lambda poly: (sum(poly, Vector((0, 0))) / len(poly)).length)
    for i, poly in enumerate(shards):
        c = sum(poly, Vector((0, 0))) / len(poly)
        inset = [c + (p - c) * (1 - 0.1 / max((p - c).length, 0.2)) for p in poly]
        z = rng.uniform(-0.03, 0.03)
        M = T(0, 0, z) @ Matrix.Rotation(rng.uniform(-0.03, 0.03), 4, Vector((-c.y, c.x, 0)).normalized()) if c.length > 0.1 else T(0, 0, z)
        kit.prism(a.bm("Shard", i + 1), M, [(p.x, p.y) for p in inset], -0.07, 0.07)
        a.pivot.add(f"Shard_{i + 1:02d}")

    # cracks: 8 spokes from the impact point past the rim, 6 diagonals
    cracks = []
    for k in range(n):
        end = dirs[k] * R * rng.uniform(1.12, 1.3)
        pts = _jagged(rng, C, end, 7, 0.45)
        w = [_lerp(0.3, 0.05, i / (len(pts) - 1)) for i in range(len(pts))]
        cracks.append((pts, w))
    skip = {2, 6}
    for k in range(n):
        if k in skip:
            continue
        pts = _jagged(rng, A[k], B[(k + 1) % n] * 1.04, 5, 0.35)
        w = [_lerp(0.2, 0.05, i / (len(pts) - 1)) for i in range(len(pts))]
        cracks.append((pts, w))

    def key(cr):
        pts = cr[0]
        return (round(min(p.length for p in pts), 1), sum((p.length for p in pts), 0.0) / len(pts))

    cracks.sort(key=key)
    for i, (pts, w) in enumerate(cracks):
        kit.prism(a.bm("Crack", i + 1), I, strip_outline(pts, w), -0.1, 0.12)

    # torn rim
    edge = a.bm("RiftEdge")
    N = 120
    spikes = [(rng.uniform(0, TAU), rng.uniform(0.9, 4.2), rng.uniform(0.05, 0.13)) for _ in range(16)]
    rings = []
    for k in range(N):
        t = k / N * TAU
        jag = 0.28 * math.sin(t * 23 + 1.3) * math.sin(t * 7) + 0.2 * noise.noise(Vector((math.cos(t), math.sin(t), 0.3)) * 6)
        r_in = R - 0.35 + jag
        r_out = R + 1.1 + 0.4 * noise.noise(Vector((math.cos(t), math.sin(t), 1.7)) * 4)
        for s0, L, wd in spikes:
            dd = abs((t - s0 + math.pi) % TAU - math.pi)
            r_out += L * max(0.0, 1 - dd / wd) ** 1.6
        zt = 0.32 + 0.2 * noise.noise(Vector((math.cos(t), math.sin(t), 2.9)) * 5)
        c, s = math.cos(t), math.sin(t)
        rings.append([Vector((c * r_in, s * r_in, -0.3)), Vector((c * r_out, s * r_out, -0.15)),
                      Vector((c * r_out, s * r_out, 0.12)), Vector((c * r_in, s * r_in, zt))])
    loft(edge, rings, smooth=False, cyclic=True)
    for _ in range(12):  # torn slivers drifting off the rim
        t = rng.uniform(0, TAU)
        r = R + rng.uniform(2.5, 6.5)
        c = Vector((math.cos(t), math.sin(t))) * r
        tang = Vector((-math.sin(t), math.cos(t)))
        L, W = rng.uniform(0.8, 2.2), rng.uniform(0.15, 0.4)
        poly = [c - tang * L, c + tang * L * 0.7 + Vector((math.cos(t), math.sin(t))) * W, c + Vector((math.cos(t), math.sin(t))) * -W]
        kit.prism(edge, T(0, 0, rng.uniform(-0.2, 0.3)), [(p.x, p.y) for p in poly], -0.08, 0.08)

    # the view through the rift: a disc below the shards, whole image mapped on it
    RV = R + 0.4
    kit.cylinder(a.bm("RiftView"), I, RV, 0.12, segs=64, z0=-0.42, smooth=False)

    def planar(bm, uv):
        for f in bm.faces:
            for lp in f.loops:
                lp[uv].uv = (0.5 + lp.vert.co.x / (2 * RV), 0.5 + lp.vert.co.y / (2 * RV))

    a.uv["RiftView"] = planar


# ----------------------------------------------------------------------------- ResonanceSword
BLADE_Z0, BLADE_Z1 = 0.62, 4.50   # blade 3.88 + guard/grip/pommel -> 5.2 total (-0.70 .. 4.50)


def _blade_dims(s):
    w = 0.205 - 0.04 * s + 0.028 * math.exp(-((s - 0.76) / 0.12) ** 2)
    tip = 1.0 if s < 0.82 else ((1 - s) / 0.18) ** 0.8
    t = 0.052 * (1 - 0.35 * s)
    fuller = 1.0 - _smooth(0.6, 0.76, s)
    return w * tip, t * max(tip, 0.0) ** 0.5, fuller


def _blade_section(w, t, f):
    up = [(w, 0), (0.62 * w, 0.7 * t), (0.36 * w, t), (0.27 * w, t * (1 - 0.42 * f)), (0, t * (1 - 0.48 * f)),
          (-0.27 * w, t * (1 - 0.42 * f)), (-0.36 * w, t), (-0.62 * w, 0.7 * t)]
    down = [(-w, 0)] + [(x, -y) for x, y in reversed(up[1:])]
    return up + down


def resonance_sword(a):
    """Elegant crystal sword: grip centre at the origin, blade up +Z, edges toward +-X."""
    blade, crystal, guard, gold, grip = (a.bm(s) for s in ("Blade", "Crystal", "Guard", "Gold", "Grip"))

    # blade with a fuller, slight leaf swell and a fine point
    rings = []
    nz = 46
    for i in range(nz):
        s = (i / (nz - 1)) ** 0.9 * 0.985
        z = _lerp(BLADE_Z0 - 0.06, BLADE_Z1, s)
        w, t, f = _blade_dims(s)
        rings.append([Vector((u, v, z)) for u, v in _blade_section(w, t, f)])
    loft(blade, rings, end_tip=(0, 0, BLADE_Z1), smooth=True)

    # crystal inlays along the fuller (through the blade, visible on both faces)
    for k, s in enumerate((0.09, 0.2, 0.31, 0.42, 0.52)):
        z = _lerp(BLADE_Z0, BLADE_Z1, s)
        gem(crystal, T(0, 0, z), 0.052, 0.15 - 0.012 * k, 0.062, n=10)

    # guard: lozenge block, swept quillons, gold trim, a large crystal in the middle
    zc = 0.51
    sec = []
    for k in range(16):
        th = k / 16 * TAU
        x, y = math.cos(th), math.sin(th)
        sec.append((math.copysign(abs(x) ** 0.8, x) * 0.3, math.copysign(abs(y) ** 0.9, y) * 0.13))
    loft(guard, [[Vector((x * sc, y * sc, z)) for x, y in sec] for sc, z in ((0.82, 0.40), (1.0, 0.45), (1.0, 0.58), (0.86, 0.63))],
         smooth=True)
    for sx in (-1, 1):
        pts = kit.bezier_pts((sx * 0.22, 0, zc), (sx * 0.5, 0, zc - 0.05), (sx * 0.74, 0, zc + 0.0), (sx * 0.84, 0, zc + 0.17), 10)
        kit.tube(guard, I, pts, [_lerp(0.068, 0.03, i / 10) for i in range(11)], 10)
        tip = pts[-1] + Vector((sx * 0.01, 0, 0.05))
        bipyramid(gold, T(*tip), 0.045, 0.1, 0.05, 6)
        # gold trim along the top of each quillon
        tpts = [p + Vector((0, 0, _lerp(0.06, 0.028, i / 10))) for i, p in enumerate(pts)]
        kit.tube(gold, I, tpts[1:-1], [0.018] * (len(tpts) - 2), 6)
    revolve(gold, T(0, 0, 0.405) @ kit.Sc(1.0, 0.5, 1.0), [(0.25, -0.02), (0.29, 0.0), (0.25, 0.02)], 24)
    for sy in (-1, 1):  # langets reaching onto the blade
        kit.wall_prism(gold, I, [(-0.15, 0.6), (0.15, 0.6), (0.05, 0.78), (0, 0.9), (-0.05, 0.78)],
                       *sorted((sy * 0.028, sy * 0.06)))
        torus(gold, T(0, sy * 0.125, zc) @ Rx(math.pi / 2), 0.118, 0.022, 24, 6)
    gem(crystal, T(0, 0, zc), 0.1, 0.1, 0.17, n=8, table=0.5)

    # grip: oval core wrapped with overlapping leather bands, gold ferrules
    g_rings = []
    nzg, nth = 52, 18
    for i in range(nzg):
        z = _lerp(-0.4, 0.4, i / (nzg - 1))
        r0 = 0.112 + 0.012 * math.cos(z / 0.4 * math.pi / 2)
        ring = []
        for k in range(nth):
            th = k / nth * TAU
            saw = ((z / 0.095 + th / TAU) % 1.0) ** 1.6
            r = r0 * (1 + 0.075 * saw)
            ring.append(Vector((math.cos(th) * r * 1.06, math.sin(th) * r * 0.92, z)))
        g_rings.append(ring)
    loft(grip, g_rings, smooth=True)
    for z in (-0.4, 0.38):
        revolve(gold, T(0, 0, z), [(0.105, -0.04), (0.14, -0.035), (0.148, 0.0), (0.14, 0.035), (0.105, 0.04)], 24)

    # pommel: dark cap, gold collar and claws, a crystal pointing down
    kit.lathe(guard, I, [(0, -0.43), (0.12, -0.43), (0.165, -0.47), (0.17, -0.52), (0.14, -0.575), (0.09, -0.6), (0, -0.6)], 20)
    revolve(gold, T(0, 0, -0.52), [(0.155, -0.018), (0.182, 0.0), (0.155, 0.018)], 24)
    bipyramid(crystal, T(0, 0, -0.59), 0.085, 0.07, 0.11, 6, twist=math.pi / 6)
    for k in range(3):
        th = k / 3 * TAU + math.pi / 6
        d = Vector((math.cos(th), math.sin(th), 0))
        kit.tube(gold, I, [d * 0.13 + Vector((0, 0, -0.56)), d * 0.1 + Vector((0, 0, -0.62)), d * 0.07 + Vector((0, 0, -0.645))],
                 [0.02, 0.016, 0.01], 5)


# ----------------------------------------------------------------------------- Shockwave / SlashArc
def shockwave(a):
    """Flat ring of radius 1 in the XY plane (scaled at runtime): thin bright lip, soft inner fade."""
    revolve(a.bm("Wave"), I, [(0.72, 0.0), (0.9, -0.012), (0.985, -0.02), (1.0, 0.0), (0.985, 0.03), (0.9, 0.035)], 96)


def slash_arc(a):
    """Crescent trail of a sword swing in the XY plane, radius ~5, centred on the front (-Y),
    thick at the leading end (+X side), tapering to points."""
    arc = a.bm("Arc")
    n = 64
    a0, a1 = math.radians(-205), math.radians(25)
    rings = []
    for i in range(1, n):
        s = i / n
        th = _lerp(a0, a1, s)
        w = 1.45 * math.sin(math.pi * s) ** 0.75 * (0.55 + 0.45 * s)
        t = 0.035 + 0.05 * w / 1.45
        r_out = 5.0
        r_mid = r_out - w * 0.45
        r_in = r_out - w
        c, sn = math.cos(th), math.sin(th)
        rings.append([Vector((c * r, sn * r, z)) for r, z in ((r_out, 0.0), (r_mid, t), (r_in, 0.0), (r_mid, -t))])
    p0 = Vector((math.cos(a0) * 5, math.sin(a0) * 5, 0))
    p1 = Vector((math.cos(a1) * 5, math.sin(a1) * 5, 0))
    loft(arc, rings, start_tip=p0, end_tip=p1, smooth=True)


ASSETS = [
    ("SpaceDome", space_dome),
    ("SoulCore", soul_core),
    ("ShatteredPlanet", shattered_planet),
    ("Rift", rift),
    ("ResonanceSword", resonance_sword),
    ("Shockwave", shockwave),
    ("SlashArc", slash_arc),
]


# ----------------------------------------------------------------------------- finishing
def _prepare(asset, key, bm):
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.normal_update()
    if key not in asset.raw:
        kit._repair(bm)
        bm.normal_update()
    kit._sharpen(bm)
    if key in asset.flat:
        for e in bm.edges:
            e.smooth = False
    if key in asset.single:
        n = len(bm.faces)
        if n > kit.MAX_TRIS:
            raise ValueError(f"{asset.name}__{key} has {n} triangles (> {kit.MAX_TRIS}) but must stay one mesh")
        return [bm]
    return kit._split(bm, kit.MAX_TRIS)


def _object(asset, name, key, bm, collection, offset):
    uv = bm.loops.layers.uv.verify()
    fn = asset.uv.get(key)
    if fn:
        fn(bm, uv)
    else:
        kit._box_uv(bm)
    for v in bm.verts:
        v.co += offset
    center = None
    if key in asset.pivot:
        lo = Vector((min(v.co.x for v in bm.verts), min(v.co.y for v in bm.verts), min(v.co.z for v in bm.verts)))
        hi = Vector((max(v.co.x for v in bm.verts), max(v.co.y for v in bm.verts), max(v.co.z for v in bm.verts)))
        center = (lo + hi) / 2
        for v in bm.verts:
            v.co -= center
    if key in asset.flat:
        for f in bm.faces:
            f.smooth = False
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    if center is not None:
        obj.location = center
    collection.objects.link(obj)
    obj.data.materials.append(material(style_of(key)))
    return obj


def finish(asset, collection, offset=Vector((0, 0, 0))):
    """Objects for an IntroAsset (+ the three markers)."""
    offset = Vector(offset)
    objs = []
    for key, bm in asset.pieces.items():
        chunks = _prepare(asset, key, bm)
        for i, chunk in enumerate(chunks):
            name = f"{asset.name}__{key}" + (f"_{i + 1}" if len(chunks) > 1 else "")
            chunk.normal_update()
            objs.append(_object(asset, name, key, chunk, collection, offset))
    objs.append(kit._marker(f"{asset.name}__Origin", offset, collection))
    objs.append(kit._marker(f"{asset.name}__Up", offset + Vector((0, 0, kit.MARKER_LEN)), collection))
    objs.append(kit._marker(f"{asset.name}__Front", offset + Vector((0, -kit.MARKER_LEN, 0)), collection))
    return objs


def make(name):
    """The IntroAsset (bmesh pieces, not finished) for an asset name."""
    fn = dict(ASSETS)[name]
    a = IntroAsset(name)
    fn(a)
    return a


def build(name, collection, offset=Vector((0, 0, 0))):
    return finish(make(name), collection, offset)
