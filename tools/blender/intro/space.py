"""
Space backdrop of the intro (docs/intro/DESIGN.md §5): stars, galaxies and nebulae.

Generation (pure Python, deterministic; the same numbers go to IntroData.starfield)
-----------------------------------------------------------------------------------
    generate(seed=7) -> {
        "stars":    [x, y, z, size, r, g, b, appear, phase, ...],      # 9 numbers per star, 1600 stars
        "galaxies": [{"center": [x, y, z], "normal": [x, y, z], "xaxis": [x, y, z], "radius": r,
                      "arms": n, "twist": a,
                      "points": [fx, fy, fz, tx, ty, tz, size, r, g, b, delay, ...]}, ...],   # 3 galaxies,
                                                                     # 350 points of 11 numbers each
        "nebulae":  [{"center": [x, y, z], "radius": r, "color": [r, g, b], "appear": a}, ...],  # 8
    }

Conventions: positions are Blender coordinates (studs, Z up) relative to SkyAnchor (convert with
DESIGN §2 R(x, y, z) = (x, z, -y)); stars lie on a shell r 850-960, galaxy centres ~790 away,
nebulae inside r 1000 (the dome). Colours are 0..1 (Color3.new). Sizes are diameters in studs.
phase is in radians. Galaxy frame: X = xaxis, Y = normal x xaxis, Z = normal; a galaxy-frame point
(fx, fy, fz) is at center + fx*X + fy*Y + fz*Z ("from" = scattered dust, "to" = spiral position).

Display rules (the Roblox runtime uses the same; channels are the Starfield object's custom
properties stars / nebula / galaxies / twinkle, t = cutscene time in seconds):
    star:    b = clamp((stars - appear) / STAR_FADE, 0, 1)
                 * (1 - TWINKLE_DEPTH * twinkle * (0.5 + 0.5 * sin(TWINKLE_SPEED * t + phase)))
    galaxy:  u = smoothstep(clamp((galaxies - delay) / GALAXY_SPAN, 0, 1))      (smoothstep = u*u*(3-2u))
             p = rotZ((1 - u) * twist) * lerp(from, to, u)   (galaxy frame, right-handed about the normal)
             brightness u
    nebula:  a = smoothstep(clamp((nebula - appear) / NEBULA_FADE, 0, 1))

Blender preview (used by scene.py)
----------------------------------
    handle = build_preview(collection, data, parent=None)
        Creates the Empty "Starfield" (child of `parent`, e.g. SkyAnchor) with the custom properties
        stars, nebula, galaxies, twinkle (0..1, default 1 = the fully formed sky) and its preview
        children: "Starfield_Stars" (points), "Starfield_Galaxy_1..3" (points, positions computed by
        Geometry Nodes), "Starfield_Nebula_1..8" (layered emissive cards facing the origin). The children read the Starfield
        properties through drivers, so only the Starfield properties need keys and the exporter
        exports them as channels. Everything is keyframable data (drivers, Geometry Nodes inputs,
        shader attributes): background renders at any frame show the right state, no frame handlers.
        Returns {"starfield": obj, "stars": obj, "galaxies": [obj], "nebulae": [obj], "data": data}.
    key_channels(handle, frame, stars=None, nebula=None, galaxies=None, twinkle=None, interpolation=None)
        Keys the given Starfield properties at `frame` (others untouched). interpolation e.g. "LINEAR".
    configure_render(scene)   raises Cycles transparent bounces for the overlapping star sprites
                              (build_preview does it for the current scene).
    post_glow(path, strength=0.55, radius=0.012)  cheap bloom on a rendered PNG (preview only).

    python tools/blender/intro/space.py --render <dir>   renders sky_still.png (fully formed sky from
        inside the dome) and sky_formation.png (4 frames of the galaxies forming) into <dir>.
"""
import math
import os
import random
import sys

TAU = math.pi * 2
N_STARS = 1600
N_GALAXY_POINTS = 350
STAR_FADE = 0.08
GALAXY_SPAN = 0.7
NEBULA_FADE = 0.35
TWINKLE_DEPTH = 0.45
TWINKLE_SPEED = 2.2  # radians per second
BAND_NORMAL = (0.28, -0.52, 0.81)  # the galactic band (denser stars) is the great circle normal to this

# hand-placed for the composition: azimuth from +X toward +Y, elevation (degrees)
GALAXIES = [  # az, el, radius, arms, tilt (deg from face-on), twist (rad)
    (38.0, 30.0, 132.0, 2, 38.0, 3.2),
    (152.0, 46.0, 96.0, 3, 60.0, 2.7),
    (262.0, 14.0, 78.0, 4, 48.0, 2.4),
]
NEBULAE = [  # az, el, radius, colour, appear
    (56.0, 22.0, 235.0, "violet", 0.0),
    (16.0, 40.0, 170.0, "magenta", 0.22),
    (118.0, 8.0, 210.0, "deep_blue", 0.1),
    (178.0, 30.0, 190.0, "teal", 0.32),
    (222.0, -6.0, 250.0, "violet", 0.18),
    (296.0, 30.0, 160.0, "magenta", 0.42),
    (330.0, -20.0, 220.0, "deep_blue", 0.28),
    (86.0, -34.0, 140.0, "teal", 0.5),
]
NEBULA_COLORS = {
    "violet": (0.52, 0.28, 0.95),
    "deep_blue": (0.14, 0.24, 0.85),
    "teal": (0.1, 0.62, 0.68),
    "magenta": (0.86, 0.2, 0.62),
}
STAR_COLORS = [(0.72, 0.82, 1.0), (1.0, 0.98, 0.94), (1.0, 0.8, 0.58)]  # blue-white, white, warm
CORE_COLOR = (1.0, 0.88, 0.66)
ARM_COLOR = (0.55, 0.68, 1.0)
KNOT_COLOR = (1.0, 0.5, 0.78)


# ----------------------------------------------------------------------------- small vector maths
def _add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]


def _mul(a, s):
    return [a[0] * s, a[1] * s, a[2] * s]


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]


def _norm(a):
    n = math.sqrt(_dot(a, a))
    return [a[0] / n, a[1] / n, a[2] / n]


def _dir(az, el):
    az, el = math.radians(az), math.radians(el)
    return [math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)]


def _unit(rng):
    z = rng.uniform(-1, 1)
    t = rng.uniform(0, TAU)
    r = math.sqrt(1 - z * z)
    return [r * math.cos(t), r * math.sin(t), z]


def _lerp3(a, b, t):
    return [a[i] + (b[i] - a[i]) * t for i in range(3)]


def _smooth(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def _r(x, nd=3):
    return round(x, nd)


def frame_axes(normal):
    """Deterministic X axis of a galaxy frame for a normal (also stored as 'xaxis')."""
    helper = [0.0, 0.0, 1.0] if abs(normal[2]) < 0.9 else [1.0, 0.0, 0.0]
    x = _norm(_cross(helper, normal))
    return x, _cross(normal, x)


# ----------------------------------------------------------------------------- generation
def _stars(rng):
    band = _norm(list(BAND_NORMAL))
    bx, by = frame_axes(band)
    stars = []
    for i in range(N_STARS):
        if rng.random() < 0.32:  # galactic band
            t = rng.uniform(0, TAU)
            d = _norm(_add(_add(_mul(bx, math.cos(t)), _mul(by, math.sin(t))), _mul(band, rng.gauss(0, 0.13))))
        else:
            d = _unit(rng)
        r = rng.uniform(850, 960)
        # truncated power law 0.6 .. 3.2: many small, few big
        a = 2.3
        lo, hi = 0.6, 3.2
        u = rng.random()
        size = lo / (1 - u * (1 - (lo / hi) ** a)) ** (1 / a)
        big = (size - lo) / (hi - lo)
        k = rng.random()
        ci = 0 if k < 0.34 + 0.2 * big else (1 if k < 0.8 else 2)
        c = STAR_COLORS[ci]
        j = rng.uniform(-0.04, 0.04)
        col = [min(1.0, max(0.0, c[0] + j)), min(1.0, max(0.0, c[1] + j)), min(1.0, c[2])]
        stars.append([d, r, size, col, rng.random(), rng.uniform(0, TAU)])
    # appear: the brightest first, then thousands (visible count grows ~ stars^2)
    order = sorted(range(N_STARS), key=lambda i: -stars[i][2])
    out = [0.0] * (N_STARS * 9)
    for rank, i in enumerate(order):
        d, r, size, col, noise_, phase = stars[i]
        x = min(1.0, 0.72 * rank / (N_STARS - 1) + 0.28 * noise_)
        appear = (1 - STAR_FADE) * math.sqrt(x)
        p = _mul(d, r)
        out[i * 9:(i + 1) * 9] = [_r(p[0]), _r(p[1]), _r(p[2]), _r(size), _r(col[0]), _r(col[1]), _r(col[2]),
                                  _r(appear, 4), _r(phase, 4)]
    return out


def _galaxy(rng, az, el, radius, arms, tilt, twist):
    d = _dir(az, el)
    center = _mul(d, 790.0)
    toward = _mul(d, -1.0)  # faces the viewer at tilt 0
    side = _norm(_cross(toward, [0.0, 0.0, 1.0]))
    t = math.radians(tilt)
    normal = _norm(_add(_mul(toward, math.cos(t)), _mul(side, math.sin(t))))
    xaxis, _ = frame_axes(normal)
    pts = []
    n_core = int(N_GALAXY_POINTS * 0.18)
    n_haze = int(N_GALAXY_POINTS * 0.12)
    wind = rng.uniform(3.0, 3.6)  # radians of winding from the core to the rim
    for i in range(N_GALAXY_POINTS):
        if i < n_core:  # bulge
            r = radius * 0.2 * min(abs(rng.gauss(0, 0.6)), 1.4)
            th = rng.uniform(0, TAU)
            to = [r * math.cos(th), r * math.sin(th), rng.gauss(0, radius * 0.035) * (1 - r / (radius * 0.3))]
            col = _lerp3(CORE_COLOR, [1.0, 1.0, 0.95], rng.random() * 0.4)
            size = rng.uniform(14.0, 26.0) * (1 - 0.45 * r / (radius * 0.28)) * radius / 120
            delay = 0.3 * 0.25 * rng.random()
            tt = r / radius
        elif i < n_core + n_haze:  # dim, big puffs filling the disc between the arms
            tt = 0.15 + 0.75 * rng.random() ** 0.7
            r = radius * tt
            th = rng.uniform(0, TAU)
            to = [r * math.cos(th), r * math.sin(th), rng.gauss(0, radius * 0.02)]
            col = _mul(_lerp3(CORE_COLOR, ARM_COLOR, _smooth(0.0, 0.8, tt)), 0.3)
            size = radius * rng.uniform(0.28, 0.4)
            delay = 0.3 * (0.5 * tt + 0.5 * rng.random())
        else:
            arm = i % arms
            tt = 0.12 + 0.88 * rng.random() ** 0.85
            r = radius * tt + rng.gauss(0, radius * 0.06)
            th = arm / arms * TAU + wind * tt + rng.gauss(0, 0.26)
            to = [r * math.cos(th), r * math.sin(th), rng.gauss(0, radius * 0.022)]
            knot = rng.random() < 0.14
            if knot:
                col = list(KNOT_COLOR)
                size = rng.uniform(8.0, 14.0) * radius / 120
            else:
                col = _mul(_lerp3(CORE_COLOR, ARM_COLOR, _smooth(0.1, 0.7, tt)), rng.uniform(0.55, 0.9))
                size = rng.uniform(12.0, 22.0) * (1.15 - 0.4 * tt) * radius / 120
            delay = 0.3 * (0.65 * tt + 0.35 * rng.random())
        dd = _unit(rng)
        rr = radius * 1.5 * rng.random() ** (1 / 3)
        frm = [dd[0] * rr, dd[1] * rr, dd[2] * rr * 0.6]
        pts += [_r(frm[0]), _r(frm[1]), _r(frm[2]), _r(to[0]), _r(to[1]), _r(to[2]), _r(size),
                _r(col[0]), _r(col[1]), _r(col[2]), _r(min(delay, 0.3), 4)]
    return {"center": [_r(c) for c in center], "normal": [_r(c, 5) for c in normal],
            "xaxis": [_r(c, 5) for c in xaxis], "radius": radius, "arms": arms, "twist": twist, "points": pts}


def generate(seed=7):
    rng = random.Random(seed)
    stars = _stars(rng)
    galaxies = [_galaxy(rng, *g) for g in GALAXIES]
    nebulae = []
    for az, el, radius, cname, appear in NEBULAE:
        d = _dir(az + rng.uniform(-3, 3), el + rng.uniform(-3, 3))
        dist = 975.0 - 0.9 * radius
        nebulae.append({"center": [_r(c) for c in _mul(d, dist)], "radius": radius,
                        "color": list(NEBULA_COLORS[cname]), "appear": appear})
    return {"stars": stars, "galaxies": galaxies, "nebulae": nebulae}


# ----------------------------------------------------------------------------- Blender preview
STAR_STRENGTH = 9.0
GALAXY_STRENGTH = 1.0
NEBULA_STRENGTH = 0.75
NEBULA_CARDS = 3
SPRITE = 1.7  # preview sprite radius / star radius (room for the soft halo)
CHANNELS = ("stars", "nebula", "galaxies", "twinkle")


def _bpy():
    import bpy
    return bpy


def _lin(c):
    return tuple(max(x, 0.0) ** 2.2 for x in c)


def configure_render(scene):
    scene.cycles.transparent_max_bounces = max(scene.cycles.transparent_max_bounces, 64)


def _prop(obj, name, value):
    obj[name] = float(value)
    ui = obj.id_properties_ui(name)
    ui.update(min=0.0, max=1.0, soft_min=0.0, soft_max=1.0)


def _drive(target, path, source, prop, expr="v"):
    fc = target.driver_add(path)
    drv = fc.driver
    drv.type = "SCRIPTED"
    v = drv.variables.new()
    v.name = "v"
    v.type = "SINGLE_PROP"
    v.targets[0].id = source
    v.targets[0].data_path = f'["{prop}"]'
    drv.expression = expr
    return fc


def _drive_time(target, prop="time"):
    target[prop] = 0.0
    fc = target.driver_add(f'["{prop}"]')
    fc.driver.type = "SCRIPTED"
    fc.driver.expression = "(frame - 1) / 30"  # seconds: frame 1 = t 0 (DESIGN §1)


def _mesh_points(name, n, attrs):
    """Mesh with n loose vertices and point attributes {name: (type, flat values)}."""
    bpy = _bpy()
    me = bpy.data.meshes.new(name)
    me.vertices.add(n)
    for aname, (atype, values) in attrs.items():
        if aname == "position":
            me.vertices.foreach_set("co", values)
            continue
        a = me.attributes.new(aname, atype, "POINT")
        key = {"FLOAT": "value", "FLOAT_VECTOR": "vector", "FLOAT_COLOR": "color"}[atype]
        a.data.foreach_set(key, values)
    me.update()
    return me


def _emission_points_material(name, strength_inputs, color_attr="col", falloff=3.0):
    """Additive soft sprite: emission = col * product(strength_inputs) * facing falloff."""
    bpy = _bpy()
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    N, L = nt.nodes, nt.links.new
    out = N.new("ShaderNodeOutputMaterial")
    col = N.new("ShaderNodeAttribute")
    col.attribute_name = color_attr
    lw = N.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    inv = N.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    L(lw.outputs["Facing"], inv.inputs[1])
    fall = N.new("ShaderNodeMath")
    fall.operation = "POWER"
    L(inv.outputs[0], fall.inputs[0])
    fall.inputs[1].default_value = falloff
    s = fall.outputs[0]
    for x in strength_inputs:
        mm = N.new("ShaderNodeMath")
        mm.operation = "MULTIPLY"
        L(s, mm.inputs[0])
        if isinstance(x, (int, float)):
            mm.inputs[1].default_value = x
        else:
            L(x(nt), mm.inputs[1])
        s = mm.outputs[0]
    em = N.new("ShaderNodeEmission")
    L(col.outputs["Color"], em.inputs["Color"])
    L(s, em.inputs["Strength"])
    tr = N.new("ShaderNodeBsdfTransparent")
    add = N.new("ShaderNodeAddShader")
    L(tr.outputs[0], add.inputs[0])
    L(em.outputs[0], add.inputs[1])
    L(add.outputs[0], out.inputs["Surface"])
    return m


def _attr(name, kind="GEOMETRY", out="Fac"):
    def make(nt):
        a = nt.nodes.new("ShaderNodeAttribute")
        a.attribute_name = name
        a.attribute_type = kind
        return a.outputs[out]
    return make


def _star_brightness(nt):
    """clamp((stars - appear)/fade) * (1 - depth * twinkle * (0.5 + 0.5 sin(speed t + phase)))"""
    N, L = nt.nodes, nt.links.new

    def math_node(op, a, b=None):
        m = N.new("ShaderNodeMath")
        m.operation = op
        for i, x in enumerate((a, b)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                m.inputs[i].default_value = x
            else:
                L(x, m.inputs[i])
        return m.outputs[0]

    stars = _attr("stars", "OBJECT")(nt)
    appear = _attr("appear")(nt)
    fade = N.new("ShaderNodeClamp")
    L(math_node("DIVIDE", math_node("SUBTRACT", stars, appear), STAR_FADE), fade.inputs["Value"])
    t = _attr("time", "OBJECT")(nt)
    phase = _attr("phase")(nt)
    wave = math_node("SINE", math_node("ADD", math_node("MULTIPLY", t, TWINKLE_SPEED), phase))
    wave = math_node("MULTIPLY_ADD", wave, 0.5)  # 0.5*sin + 0.5 (third input below)
    wave.node.inputs[2].default_value = 0.5
    tw = _attr("twinkle", "OBJECT")(nt)
    dip = math_node("SUBTRACT", 1.0, math_node("MULTIPLY", math_node("MULTIPLY", tw, wave), TWINKLE_DEPTH))
    return math_node("MULTIPLY", fade.outputs[0], dip)


def _gn_points(name, radius_scale, material, galaxy=None):
    """Geometry Nodes: (galaxy formation) -> points with radius size/2 * radius_scale -> material."""
    bpy = _bpy()
    ng = bpy.data.node_groups.new(name, "GeometryNodeTree")
    ng.interface.new_socket("Geometry", in_out="INPUT", socket_type="NodeSocketGeometry")
    ng.interface.new_socket("Geometry", in_out="OUTPUT", socket_type="NodeSocketGeometry")
    N, L = ng.nodes, ng.links.new
    gi, go = N.new("NodeGroupInput"), N.new("NodeGroupOutput")

    def named(attr, dtype="FLOAT"):
        n = N.new("GeometryNodeInputNamedAttribute")
        n.data_type = dtype
        n.inputs["Name"].default_value = attr
        return n.outputs["Attribute"]

    def vmath(op, a, b=None, scale=None):
        n = N.new("ShaderNodeVectorMath")
        n.operation = op
        L(a, n.inputs[0])
        if b is not None:
            L(b, n.inputs[1])
        if scale is not None:
            L(scale, n.inputs["Scale"])
        return n.outputs[0]

    def fmath(op, a, b):
        n = N.new("ShaderNodeMath")
        n.operation = op
        for i, x in enumerate((a, b)):
            if isinstance(x, (int, float)):
                n.inputs[i].default_value = x
            else:
                L(x, n.inputs[i])
        return n.outputs[0]

    geo = gi.outputs["Geometry"]
    sockets = {}
    if galaxy is not None:
        sockets["g"] = ng.interface.new_socket("galaxies", in_out="INPUT", socket_type="NodeSocketFloat")
        sockets["twist"] = ng.interface.new_socket("twist", in_out="INPUT", socket_type="NodeSocketFloat")
        g = gi.outputs["galaxies"]
        mr = N.new("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        mr.clamp = True
        L(fmath("SUBTRACT", g, named("delay")), mr.inputs["Value"])
        mr.inputs["From Min"].default_value = 0.0
        mr.inputs["From Max"].default_value = GALAXY_SPAN
        u = mr.outputs["Result"]
        frm, to = named("from", "FLOAT_VECTOR"), named("to", "FLOAT_VECTOR")
        pos = vmath("ADD", frm, vmath("SCALE", vmath("SUBTRACT", to, frm), scale=u))
        rot = N.new("ShaderNodeVectorRotate")
        rot.rotation_type = "Z_AXIS"
        L(pos, rot.inputs["Vector"])
        L(fmath("MULTIPLY", fmath("SUBTRACT", 1.0, u), gi.outputs["twist"]), rot.inputs["Angle"])
        sp = N.new("GeometryNodeSetPosition")
        L(geo, sp.inputs["Geometry"])
        L(rot.outputs["Vector"], sp.inputs["Position"])
        st = N.new("GeometryNodeStoreNamedAttribute")
        st.data_type = "FLOAT"
        st.inputs["Name"].default_value = "u"
        L(sp.outputs["Geometry"], st.inputs["Geometry"])
        L(u, st.inputs["Value"])
        geo = st.outputs["Geometry"]
    m2p = N.new("GeometryNodeMeshToPoints")
    L(geo, m2p.inputs["Mesh"])
    L(fmath("MULTIPLY", named("size"), 0.5 * radius_scale), m2p.inputs["Radius"])
    sm = N.new("GeometryNodeSetMaterial")
    sm.inputs["Material"].default_value = material
    L(m2p.outputs["Points"], sm.inputs["Geometry"])
    L(sm.outputs["Geometry"], go.inputs["Geometry"])
    return ng, sockets


def _nebula_material():
    """Additive layered cards: wispy 4D noise (seed per card) in a soft irregular mask, fading in by
    smoothstep((nebula - appear) / NEBULA_FADE); colour = object colour, denser parts whiter."""
    bpy = _bpy()
    m = bpy.data.materials.new("SF_Nebula")
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    N, L = nt.nodes, nt.links.new

    def math_node(op, a, b=None, c=None):
        mm = N.new("ShaderNodeMath")
        mm.operation = op
        for i, x in enumerate((a, b, c)):
            if x is None:
                continue
            if isinstance(x, (int, float)):
                mm.inputs[i].default_value = x
            else:
                L(x, mm.inputs[i])
        return mm.outputs[0]

    def noise(vec, w, scale, detail, rough, dist=0.0):
        nz = N.new("ShaderNodeTexNoise")
        nz.noise_dimensions = "4D"
        nz.inputs["Scale"].default_value = scale
        nz.inputs["Detail"].default_value = detail
        nz.inputs["Roughness"].default_value = rough
        nz.inputs["Distortion"].default_value = dist
        L(vec, nz.inputs["Vector"])
        L(w, nz.inputs["W"])
        return nz

    def ramp(x, a, b, interp="SMOOTHSTEP"):
        mr = N.new("ShaderNodeMapRange")
        mr.interpolation_type = interp
        L(x, mr.inputs["Value"])
        mr.inputs["From Min"].default_value = a
        mr.inputs["From Max"].default_value = b
        return mr.outputs["Result"]

    out = N.new("ShaderNodeOutputMaterial")
    uv = N.new("ShaderNodeUVMap")
    seed = N.new("ShaderNodeAttribute")
    seed.attribute_name = "seed"
    w = math_node("MULTIPLY", seed.outputs["Fac"], 7.3)
    # domain-warped coordinates (centred card space, -1..1)
    cen = N.new("ShaderNodeVectorMath")
    cen.operation = "MULTIPLY_ADD"
    L(uv.outputs["UV"], cen.inputs[0])
    cen.inputs[1].default_value = (2.0, 2.0, 0.0)
    cen.inputs[2].default_value = (-1.0, -1.0, 0.0)
    wn = noise(cen.outputs[0], w, 1.1, 2.0, 0.5)
    off = N.new("ShaderNodeVectorMath")
    off.operation = "SUBTRACT"
    L(wn.outputs["Color"], off.inputs[0])
    off.inputs[1].default_value = (0.5, 0.5, 0.5)
    bent = N.new("ShaderNodeVectorMath")
    bent.operation = "MULTIPLY_ADD"
    L(off.outputs[0], bent.inputs[0])
    bent.inputs[1].default_value = (1.6, 1.6, 0.0)
    L(cen.outputs[0], bent.inputs[2])
    ln = N.new("ShaderNodeVectorMath")
    ln.operation = "LENGTH"
    L(bent.outputs[0], ln.inputs[0])
    mask = ramp(ln.outputs["Value"], 0.9, 0.05)
    patch = noise(cen.outputs[0], math_node("ADD", w, 5.7), 0.8, 1.0, 0.5)
    mask = math_node("MULTIPLY", mask, ramp(patch.outputs["Fac"], 0.35, 0.65))
    rim = N.new("ShaderNodeVectorMath")  # never reach the card's edges
    rim.operation = "LENGTH"
    L(cen.outputs[0], rim.inputs[0])
    mask = math_node("MULTIPLY", mask, ramp(rim.outputs["Value"], 0.98, 0.55))
    body = noise(bent.outputs[0], w, 1.4, 4.0, 0.5, 0.25)
    billow = math_node("POWER", ramp(body.outputs["Fac"], 0.4, 0.75, "LINEAR"), 1.6)
    fil = noise(bent.outputs[0], math_node("ADD", w, 3.1), 2.2, 3.0, 0.5)
    ridge = math_node("SUBTRACT", 1.0, math_node("ABSOLUTE", math_node("MULTIPLY_ADD", fil.outputs["Fac"], 2.0, -1.0)))
    ridge = math_node("POWER", ridge, 8.0)
    haze = math_node("MULTIPLY", math_node("POWER", mask, 2.0), 0.18)
    dens = math_node("ADD", math_node("MULTIPLY", mask, math_node("ADD", billow, math_node("MULTIPLY", ridge, 0.25))), haze)
    # fade-in
    neb = N.new("ShaderNodeAttribute")
    neb.attribute_type = "OBJECT"
    neb.attribute_name = "nebula"
    app = N.new("ShaderNodeAttribute")
    app.attribute_type = "OBJECT"
    app.attribute_name = "appear"
    fade = ramp(math_node("SUBTRACT", neb.outputs["Fac"], app.outputs["Fac"]), 0.0, NEBULA_FADE)
    strength = math_node("MULTIPLY", math_node("MULTIPLY", dens, fade), NEBULA_STRENGTH)
    info = N.new("ShaderNodeObjectInfo")
    mix = N.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    L(info.outputs["Color"], mix.inputs["A"])
    mix.inputs["B"].default_value = (1.0, 0.92, 1.0, 1)
    L(math_node("MULTIPLY", dens, 0.3), mix.inputs["Factor"])
    em = N.new("ShaderNodeEmission")
    L(mix.outputs["Result"], em.inputs["Color"])
    L(strength, em.inputs["Strength"])
    tr = N.new("ShaderNodeBsdfTransparent")
    add = N.new("ShaderNodeAddShader")
    L(tr.outputs[0], add.inputs[0])
    L(em.outputs[0], add.inputs[1])
    L(add.outputs[0], out.inputs["Surface"])
    return m


def _nebula_cards(name, nb, rng):
    """Mesh: NEBULA_CARDS layered square cards around the nebula centre, all facing the
    SkyAnchor origin (where the camera always is), with UVs and a per-card 'seed'."""
    bpy = _bpy()
    import bmesh
    from mathutils import Matrix, Vector

    c0 = Vector(nb["center"])
    n = (-c0).normalized()
    u0 = n.cross(Vector((0, 0, 1)))
    u0 = u0.normalized() if u0.length > 1e-4 else Vector((1, 0, 0))
    v0 = n.cross(u0)
    b = bmesh.new()
    uvl = b.loops.layers.uv.new("UVMap")
    seeds = []
    for k in range(NEBULA_CARDS):
        rot = Matrix.Rotation(rng.uniform(0, math.tau), 3, n)
        u, v = rot @ u0, rot @ v0
        s = nb["radius"] * rng.uniform(0.75, 1.15) * (1.0 if k == 0 else 0.8)
        c = c0 + u * rng.uniform(-0.25, 0.25) * nb["radius"] + v * rng.uniform(-0.2, 0.2) * nb["radius"] - n * (k - 1) * 12
        corners = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        vs = [b.verts.new(c + u * (x * s) + v * (y * s)) for x, y in corners]
        f = b.faces.new(vs)
        for lp, (x, y) in zip(f.loops, corners):
            lp[uvl].uv = ((x + 1) / 2, (y + 1) / 2)
        seeds.append(rng.uniform(0, 100))
    me = bpy.data.meshes.new(name)
    b.to_mesh(me)
    b.free()
    a = me.attributes.new("seed", "FLOAT", "FACE")
    a.data.foreach_set("value", seeds)
    return me


def build_preview(collection, data, parent=None):
    """Blender objects showing `data` (from generate()). See the module docstring."""
    bpy = _bpy()
    from mathutils import Matrix, Vector

    configure_render(bpy.context.scene)
    sf = bpy.data.objects.new("Starfield", None)
    sf.empty_display_size = 60
    collection.objects.link(sf)
    if parent is not None:
        sf.parent = parent
    for ch in CHANNELS:
        _prop(sf, ch, 1.0)

    def child(name, me):
        o = bpy.data.objects.new(name, me)
        collection.objects.link(o)
        o.parent = sf
        return o

    # stars
    s = data["stars"]
    n = len(s) // 9
    rows = [s[i * 9:(i + 1) * 9] for i in range(n)]
    me = _mesh_points("Starfield_Stars", n, {
        "position": ("", [c for r in rows for c in r[0:3]]),
        "size": ("FLOAT", [r[3] for r in rows]),
        "col": ("FLOAT_COLOR", [c for r in rows for c in (*_lin(r[4:7]), 1.0)]),
        "appear": ("FLOAT", [r[7] for r in rows]),
        "phase": ("FLOAT", [r[8] for r in rows]),
    })
    stars = child("Starfield_Stars", me)
    for ch in ("stars", "twinkle"):
        stars[ch] = 1.0
        _drive(stars, f'["{ch}"]', sf, ch)
    _drive_time(stars)
    smat = _emission_points_material("SF_Stars", [STAR_STRENGTH, _star_brightness])
    ng, _ = _gn_points("SF_StarPoints", SPRITE, smat)
    stars.modifiers.new("Points", "NODES").node_group = ng

    # galaxies
    gmat = _emission_points_material("SF_Galaxy", [GALAXY_STRENGTH, _attr("u")], falloff=8.0)
    gal_objs = []
    for gi, g in enumerate(data["galaxies"]):
        p = g["points"]
        k = len(p) // 11
        rows = [p[i * 11:(i + 1) * 11] for i in range(k)]
        me = _mesh_points(f"Starfield_Galaxy_{gi + 1}", k, {
            "position": ("", [c for r in rows for c in r[3:6]]),
            "from": ("FLOAT_VECTOR", [c for r in rows for c in r[0:3]]),
            "to": ("FLOAT_VECTOR", [c for r in rows for c in r[3:6]]),
            "size": ("FLOAT", [r[6] for r in rows]),
            "col": ("FLOAT_COLOR", [c for r in rows for c in (*_lin(r[7:10]), 1.0)]),
            "delay": ("FLOAT", [r[10] for r in rows]),
        })
        o = child(f"Starfield_Galaxy_{gi + 1}", me)
        X, Z = Vector(g["xaxis"]), Vector(g["normal"])
        Y = Z.cross(X)
        M = Matrix((X, Y, Z)).transposed().to_4x4()
        M.translation = Vector(g["center"])
        o.matrix_basis = M
        ng, sockets = _gn_points(f"SF_Galaxy_{gi + 1}", 1.9, gmat, galaxy=g)
        mod = o.modifiers.new("Galaxy", "NODES")
        mod.node_group = ng
        inputs = mod.properties.inputs
        getattr(inputs, sockets["twist"].identifier).value = g["twist"]
        _drive(o, f'modifiers["Galaxy"].properties.inputs.{sockets["g"].identifier}.value', sf, "galaxies")
        gal_objs.append(o)

    # nebulae: layered wispy cards facing the camera (cheap; volumes cost a minute per frame)
    nmat = _nebula_material()
    neb_objs = []
    rng = random.Random(97)
    for ni, nb in enumerate(data["nebulae"]):
        me = _nebula_cards(f"Starfield_Nebula_{ni + 1}", nb, rng)
        me.materials.append(nmat)
        o = child(f"Starfield_Nebula_{ni + 1}", me)
        o.color = (*_lin(nb["color"]), 1.0)
        o["appear"] = float(nb["appear"])
        o["nebula"] = 1.0
        _drive(o, '["nebula"]', sf, "nebula")
        o.visible_shadow = False
        neb_objs.append(o)
    return {"starfield": sf, "stars": stars, "galaxies": gal_objs, "nebulae": neb_objs, "data": data}


def key_channels(handle, frame, stars=None, nebula=None, galaxies=None, twinkle=None, interpolation=None):
    """Key the Starfield channels (custom properties) at `frame`; None leaves a channel alone."""
    sf = handle["starfield"]
    for name, v in (("stars", stars), ("nebula", nebula), ("galaxies", galaxies), ("twinkle", twinkle)):
        if v is None:
            continue
        sf[name] = float(v)
        sf.keyframe_insert(f'["{name}"]', frame=frame)
        if interpolation and sf.animation_data and sf.animation_data.action:
            for fc in _fcurves(sf):
                if fc.data_path == f'["{name}"]':
                    for kp in fc.keyframe_points:
                        if abs(kp.co[0] - frame) < 1e-6:
                            kp.interpolation = interpolation


def _fcurves(obj):
    act = obj.animation_data.action
    if hasattr(act, "fcurves") and act.fcurves is not None:
        try:
            return list(act.fcurves)
        except Exception:  # noqa: BLE001  (slotted actions)
            pass
    out = []
    for layer in getattr(act, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out += list(bag.fcurves)
    return out


def post_glow(path, strength=0.55, radius=0.012, threshold=0.62):
    """Cheap bloom on a rendered PNG (preview only): blurred highlights added back."""
    bpy = _bpy()
    import numpy as np

    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    rgb = a[..., :3]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)
    hi = rgb * np.clip((lum - threshold) / (1 - threshold), 0, 1)[..., None]

    def blur(x, r):
        r = max(1, int(r))
        for _ in range(3):
            for axis in (0, 1):
                c = np.cumsum(np.pad(x, [(r + 1, r) if i == axis else (0, 0) for i in range(3)], mode="edge"), axis=axis)
                x = (np.take(c, range(2 * r + 1, c.shape[axis]), axis=axis) - np.take(c, range(0, c.shape[axis] - 2 * r - 1), axis=axis)) / (2 * r + 1)
        return x

    glow = blur(hi, radius * w) * 0.6 + blur(hi, radius * w * 4) * 0.4
    a[..., :3] = 1 - (1 - rgb) * (1 - np.clip(glow * strength * 2, 0, 1))  # screen blend
    img.pixels[:] = a.ravel()
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


# ----------------------------------------------------------------------------- preview renders
def _render_main(out_dir, size=(640, 400), samples=16):
    bpy = _bpy()
    from mathutils import Vector

    here = os.path.dirname(os.path.abspath(__file__))
    sys.path.insert(0, os.path.dirname(here))
    sys.path.insert(0, here)
    import assets_intro
    import numpy as np

    os.makedirs(out_dir, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"
    scene.world = bpy.data.worlds.new("Space")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0, 0, 0, 1)
    coll = bpy.data.collections.new("Sky")
    scene.collection.children.link(coll)
    anchor = bpy.data.objects.new("SkyAnchor", None)
    coll.objects.link(anchor)
    for o in assets_intro.build("SpaceDome", coll):
        if o.name.endswith(("__Origin", "__Up", "__Front")):
            bpy.data.objects.remove(o)
        else:
            o.parent = anchor
    data = generate()
    h = build_preview(coll, data, anchor)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.sensor_height = 24
    cam.data.clip_end = 5000
    coll.objects.link(cam)
    scene.camera = cam

    def look(target, fov):
        cam.location = (0, 0, 0)
        cam.rotation_euler = Vector(target).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 12 / math.tan(math.radians(fov) / 2)

    g0, n0 = Vector(data["galaxies"][0]["center"]), Vector(data["nebulae"][0]["center"])
    # still: the fully formed sky (frame 1 has every channel at 1)
    key_channels(h, 1, stars=1, nebula=1, galaxies=1, twinkle=0.6)
    look(g0.normalized() * 0.65 + n0.normalized() * 0.35, 62)
    scene.frame_set(1)
    scene.render.filepath = os.path.join(out_dir, "sky_still.png")
    bpy.ops.render.render(write_still=True)
    post_glow(scene.render.filepath)

    # formation strip: galaxy 1 forming (stars/nebula fading in too)
    steps = [(0.12, 0.25, 0.2), (0.4, 0.55, 0.5), (0.65, 0.8, 0.75), (1.0, 1.0, 1.0)]
    for i, (g, s, n) in enumerate(steps):
        key_channels(h, 10 + i, stars=s, nebula=n, galaxies=g, twinkle=0.6)
    look(g0, 30)
    scene.render.resolution_x, scene.render.resolution_y = 400, 400
    tiles = []
    for i in range(len(steps)):
        scene.frame_set(10 + i)
        p = os.path.join(out_dir, f"sky_formation_{i + 1}.png")
        scene.render.filepath = p
        bpy.ops.render.render(write_still=True)
        post_glow(p)
        img = bpy.data.images.load(p)
        tiles.append(np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4))
        bpy.data.images.remove(img)
    strip = np.concatenate(tiles, axis=1)
    out = bpy.data.images.new("strip", strip.shape[1], strip.shape[0], alpha=True)
    out.pixels[:] = strip.ravel()
    out.filepath_raw = os.path.join(out_dir, "sky_formation.png")
    out.file_format = "PNG"
    out.save()
    print("rendered", out_dir)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
    if "--render" in argv:
        _render_main(os.path.abspath(argv[argv.index("--render") + 1]))
    else:
        d = generate()
        print(len(d["stars"]) // 9, "stars,", [len(g["points"]) // 11 for g in d["galaxies"]], "galaxy points,",
              len(d["nebulae"]), "nebulae")
