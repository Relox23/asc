"""
The intro cutscene "Awaken" as a Blender scene (docs/intro/DESIGN.md §1-§5): every object of §3 with
its keyframes, the markers of §1, the camera of every shot and a preview-only environment (space
dust, comet tail, the forest around the landing point with the shockwave wind of §7.3).

    import scene
    ctx = scene.build()            # builds into the current (empty) Blender file, returns a dict
    python tools/blender/intro/build_intro.py   (saves assets/IntroScene.blend, exports, renders)

How it is made
--------------
Everything that moves is computed in Python as a function of time and baked into keyframes
(bake(): bulk F-curve writes), so the scene renders and exports the same at any (sub-)frame
without handlers or Python drivers:
  * the soul core, the camera and the character root follow Catmull-Rom splines (Barry-Goldman
    pyramid, time-parametrised) of authored keys; rotations use the same pyramid with slerp;
  * the camera is a small virtual cinematographer: per shot it orbits a (smoothed) subject at
    azimuth / elevation / distance keys and places the subject on the frame (rule of thirds) with
    screen-space framing keys; lens keys drive the FOV; shake comes only from shake markers;
  * the character is a pose performance: key poses from poses.py, interpolated per joint as
    quaternions (slerp pyramid = smooth arcs through the keys), per-joint lag (overlap /
    follow-through), optional jitter, body orientation from poses.BODY, and two-bone IK that
    pins the feet to the board / the ground (no foot sliding); baked every frame;
  * the sword is held by the Child Of grip (rig.add_grip_constraint) while `held` = 1, otherwise
    its world matrix is baked every frame (tumbling, board under the feet via
    poses.board_world_matrix, floating, ...); every hand-over is continuous;
  * the rift reveals its cracks and flings its shards exactly like SpaceStage.Rift (runtime);
  * the trees bend with the §7.3 formula, keyed per frame (axis-angle about their base).
Stages share Blender space: every object of one stage is hidden (hide_render keyed) during the
other; the world shader and the lights switch at the stage:world frame.
"""
import math
import os
import random
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (_HERE, os.path.dirname(_HERE)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Quaternion, Vector, noise  # noqa: E402

import rig as R  # noqa: E402
import poses as P  # noqa: E402
import space  # noqa: E402

ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))
INTRO_ASSETS = os.path.join(ROOT, "assets", "IntroAssets.blend")
ISLAND_ASSETS = os.path.join(ROOT, "assets", "IslandAssets.blend")

FPS = 30
DURATION = 42.5
FRAME_END = int(round(DURATION * FPS)) + 1          # 1276
T_SWITCH = 18.6
CUTS = (18.6, 23.0, 26.5, 35.1, 38.0)
CORE_RGB = (120, 200, 255)                         # Config.TEST_COLOR (preview)
SPACE_SEED = 7
LANDING_HEIGHT = 0.0
CIRCLE_CENTER = Vector((0.0, -14.0, 0.0))           # the landing point is 14 studs toward the hub (+Y)
WIND_SPEED, WIND_SETTLE, WIND_RADIUS = 160.0, 4.5, 320.0
MARKER_SUFFIXES = ("__Origin", "__Up", "__Front")


def F(t):
    """DESIGN §1: frame of time t (frame 1 = t 0)."""
    return int(round(t * FPS)) + 1


def T(f):
    return (f - 1) / FPS


F_SWITCH = F(T_SWITCH)


def lin(c):
    """sRGB 0-255 -> linear 0-1."""
    return tuple((x / 255.0) ** 2.2 for x in c)


CORE_LIN = lin(CORE_RGB)


# ============================================================================ maths
def clamp01(x):
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def smooth(x):
    x = clamp01(x)
    return x * x * (3 - 2 * x)


def smoother(x):
    x = clamp01(x)
    return x * x * x * (x * (x * 6 - 15) + 10)


def ease_out(x, p=2.0):
    return 1 - (1 - clamp01(x)) ** p


def ease_in(x, p=2.0):
    return clamp01(x) ** p


def lerp(a, b, u):
    return a + (b - a) * u


def remap(x, a, b):
    return clamp01((x - a) / (b - a)) if b != a else (1.0 if x >= b else 0.0)


def _hash(i, s):
    """Screen.luau / SpaceStage hash: deterministic pseudo random 0..1."""
    x = math.sin(i * 12.9898 + s * 78.233) * 43758.5453
    return x - math.floor(x)


def qslerp(a, b, u):
    """Slerp that also extrapolates (u outside 0..1), shortest arc."""
    if a.dot(b) < 0:
        b = -b
    d = a.rotation_difference(b)       # a @ d = b
    ang, ax = d.to_axis_angle()
    if ang > math.pi:
        ang -= 2 * math.pi
    return (a @ Quaternion(ax, ang * u)).normalized()


def _bg(keys, t, mix):
    """Barry-Goldman pyramid (non-uniform Catmull-Rom through keys [(t, value)]) with the given
    two-point mix(a, b, u) (lerp or slerp). Outside the key range: the end values."""
    n = len(keys)
    if n == 1 or t <= keys[0][0]:
        return keys[0][1]
    if t >= keys[-1][0]:
        return keys[-1][1]
    i = max(k for k in range(n - 1) if keys[k][0] <= t)
    t1, p1 = keys[i]
    t2, p2 = keys[i + 1]
    if i > 0:
        t0, p0 = keys[i - 1]
    else:
        t0, p0 = t1 - (t2 - t1), p1
    if i + 2 < n:
        t3, p3 = keys[i + 2]
    else:
        t3, p3 = t2 + (t2 - t1), p2
    a1 = mix(p0, p1, (t - t0) / (t1 - t0))
    a2 = mix(p1, p2, (t - t1) / (t2 - t1))
    a3 = mix(p2, p3, (t - t2) / (t3 - t2))
    b1 = mix(a1, a2, (t - t0) / (t2 - t0))
    b2 = mix(a2, a3, (t - t1) / (t3 - t1))
    return mix(b1, b2, (t - t1) / (t2 - t1))


def spline_vec(keys, t):
    return _bg([(k, Vector(v)) for k, v in keys], t, lambda a, b, u: a.lerp(b, u))


def spline_num(keys, t):
    return _bg(keys, t, lambda a, b, u: a + (b - a) * u)


def spline_quat(keys, t):
    """keys [(t, Quaternion)] made hemisphere-continuous first."""
    ks, prev = [], None
    for k, q in keys:
        q = Quaternion(q).normalized()
        if prev is not None and prev.dot(q) < 0:
            q = -q
        ks.append((k, q))
        prev = q
    return _bg(ks, t, qslerp)


def piecewise(keys, t, ease=smooth):
    """Eased piecewise interpolation of scalars keys [(t, v)] (stops at every key)."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (ta, va), (tb, vb) in zip(keys, keys[1:]):
        if t <= tb:
            return lerp(va, vb, ease((t - ta) / (tb - ta)) if tb > ta else 1.0)
    return keys[-1][1]


def look_quat(eye, target, roll=0.0, up=Vector((0, 0, 1))):
    """Camera rotation (looks along -Z, Y up) from eye to target with a roll (radians)."""
    d = (Vector(target) - Vector(eye)).normalized()
    if abs(d.dot(up)) > 0.999:
        up = Vector((0, 1, 0))
    z = -d
    x = up.cross(z).normalized()
    y = z.cross(x)
    q = Matrix((x, y, z)).transposed().to_quaternion()
    if roll:
        q = q @ Quaternion((0, 0, 1), roll)
    return q


def euler_deg_quat(e):
    """poses Euler (degrees, XYZ = Rz Ry Rx) -> Quaternion (joint space)."""
    return Euler([math.radians(v) for v in e], "XYZ").to_quaternion()


# ============================================================================ baking keyframes
_INTERP = {"CONSTANT": 0, "LINEAR": 1, "BEZIER": 2}
_HANDLE = {"FREE": 0, "ALIGNED": 1, "VECTOR": 2, "AUTO": 3, "AUTO_CLAMPED": 4}


def _channelbag(idb):
    from bpy_extras import anim_utils
    ad = idb.animation_data or idb.animation_data_create()
    if ad.action is None:
        ad.action = bpy.data.actions.new(idb.name + "Action")
    if ad.action_slot is None:
        slot = ad.action.slots.new(id_type=idb.id_type, name=idb.name)
        ad.action_slot = slot
    return anim_utils.action_ensure_channelbag_for_slot(ad.action, ad.action_slot)


def fcurve(idb, path, index=0):
    cb = _channelbag(idb)
    fc = cb.fcurves.find(path, index=index)
    if fc is None:
        fc = cb.fcurves.new(path, index=index)
    return fc


def bake(idb, path, frames, values, index=0, interp="LINEAR", handles="AUTO", clear=True):
    """Write keys (frame, value) to the F-curve idb.path[index] in one go. values may be bools."""
    fc = fcurve(idb, path, index)
    if clear:
        fc.keyframe_points.clear()
    n = len(frames)
    if n == 0:
        return fc
    start = len(fc.keyframe_points)
    fc.keyframe_points.add(n)
    kps = fc.keyframe_points
    for k, (f, v) in enumerate(zip(frames, values)):
        kp = kps[start + k]
        kp.co = (float(f), float(v))
        kp.interpolation = interp
        kp.handle_left_type = kp.handle_right_type = handles
    fc.update()
    return fc


def bake_vec(idb, path, frames, vecs, interp="LINEAR", handles="AUTO", size=None):
    size = size or len(vecs[0])
    for i in range(size):
        bake(idb, path, frames, [v[i] for v in vecs], index=i, interp=interp, handles=handles)


def key_prop(obj, name, keys, interp="BEZIER", handles="AUTO_CLAMPED"):
    """Custom property `name` keyed at [(t, value)] (times in seconds)."""
    obj[name] = float(keys[0][1])
    bake(obj, '["%s"]' % name, [F(t) for t, _ in keys], [v for _, v in keys], interp=interp, handles=handles)


def key_prop_frames(obj, name, frames, values, interp="LINEAR"):
    obj[name] = float(values[0])
    bake(obj, '["%s"]' % name, frames, values, interp=interp)


def key_hide(objs, keys):
    """hide_render keyed CONSTANT on objs at [(frame, hidden)] (never hide_viewport: hidden
    objects would drop out of the depsgraph the exporter samples)."""
    frames = [f for f, _ in keys]
    vals = [1.0 if h else 0.0 for _, h in keys]
    for o in objs:
        o.hide_render = bool(vals[0])
        bake(o, "hide_render", frames, vals, interp="CONSTANT")


def key_visible(obj, keys, extra=()):
    """DESIGN §3 `visible` channel (0/1, CONSTANT) at [(t, v)] + hide_render of obj, its
    descendants and `extra` objects."""
    key_prop(obj, "visible", keys, interp="CONSTANT")
    hk = [(F(t), v < 0.5) for t, v in keys]
    key_hide([obj] + list(obj.children_recursive) + list(extra), hk)


def stage_only(objs, stage):
    """Hide objects outside their stage (space: frames < F_SWITCH, world: from F_SWITCH)."""
    if stage == "space":
        key_hide(objs, [(1, False), (F_SWITCH, True)])
    else:
        key_hide(objs, [(1, True), (F_SWITCH, False)])


# ============================================================================ objects
def new_empty(name, coll, size=1.0, parent=None, display="PLAIN_AXES"):
    o = bpy.data.objects.new(name, None)
    o.empty_display_size = size
    o.empty_display_type = display
    coll.objects.link(o)
    if parent is not None:
        o.parent = parent
    return o


def new_collection(name, parent):
    c = bpy.data.collections.new(name)
    parent.children.link(c)
    return c


def emission_material(name, rgb_lin, strength=1.0, alpha=None, blend=False):
    """Emission-only material (optional alpha via a transparent mix). Returns the material."""
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.name = "emit"
    em.inputs["Color"].default_value = (*rgb_lin, 1.0)
    em.inputs["Strength"].default_value = strength
    if alpha is None:
        nt.links.new(em.outputs[0], out.inputs[0])
    else:
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        mix = nt.nodes.new("ShaderNodeMixShader")
        mix.name = "mix"
        mix.inputs[0].default_value = alpha
        nt.links.new(tr.outputs[0], mix.inputs[1])
        nt.links.new(em.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def bsdf_material(name, rgb, rough=0.6, metal=0.0, emit=0.0, emit_rgb=None):
    m = bpy.data.materials.new(name)
    b = m.node_tree.nodes.get("Principled BSDF")
    c = lin(rgb)
    b.inputs["Base Color"].default_value = (*c, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*(lin(emit_rgb) if emit_rgb else c), 1)
        b.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*c, 1)
    return m


def mesh_object(name, bm, coll, mats=(), parent=None, smooth=False):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    if smooth:
        for p in me.polygons:
            p.use_smooth = True
    o = bpy.data.objects.new(name, me)
    coll.objects.link(o)
    if parent is not None:
        o.parent = parent
    return o


# ============================================================================ assets
class AssetLib:
    """Meshes appended from a .blend in the kit convention (<Asset>__<Style>, markers): every
    asset's pieces moved so the asset origin (its __Origin marker) is at the world origin."""

    def __init__(self, path, names=None, keep=None):
        with bpy.data.libraries.load(path) as (src, dst):
            dst.objects = [n for n in src.objects if names is None or n.split("__")[0] in names]
        self.pieces = {}
        groups = {}
        for o in dst.objects:
            if o is not None:
                groups.setdefault(o.name.split("__")[0], []).append(o)
        for asset, objs in groups.items():
            mk = next((o for o in objs if o.name.endswith("__Origin")), None)
            org = Vector()
            if mk is not None:
                org = mk.matrix_world @ (sum((v.co for v in mk.data.vertices), Vector()) / len(mk.data.vertices))
            org.z = 0.0 if mk is None else org.z
            keep_list = []
            for o in objs:
                if o.name.endswith(MARKER_SUFFIXES):
                    bpy.data.objects.remove(o)
                    continue
                o.matrix_world = Matrix.Translation(-org) @ o.matrix_world
                keep_list.append(o)
            self.pieces[asset] = sorted(keep_list, key=lambda x: x.name)

    def place(self, asset, coll, parent, prefix=None, copy=True):
        """Copies (sharing mesh data) of an asset's pieces, parented to `parent` with their asset
        offsets as local transforms. Returns {piece name: object}."""
        out = {}
        for o in self.pieces[asset]:
            c = o.copy() if copy else o
            if prefix:
                c.name = prefix + "__" + o.name.split("__", 1)[1]
            coll.objects.link(c)
            local = o.matrix_world.copy()
            c.parent = parent
            c.matrix_parent_inverse = Matrix()
            c.matrix_basis = local
            out[o.name] = c
        return out


def _object_alpha(mat, emission=True):
    """Multiply a material's alpha (and emission strength) by the object's color alpha (Object
    Info), so obj.color[3] fades a single object."""
    nt = mat.node_tree
    if nt.nodes.get("obj_alpha") is not None:
        return
    bsdf = nt.nodes.get("Principled BSDF")
    oi = nt.nodes.new("ShaderNodeObjectInfo")
    oi.name = "obj_alpha"

    def mul_into(sock):
        m = nt.nodes.new("ShaderNodeMath")
        m.operation = "MULTIPLY"
        if sock.is_linked:
            src = sock.links[0].from_socket
            nt.links.new(src, m.inputs[0])
        else:
            m.inputs[0].default_value = sock.default_value
        nt.links.new(oi.outputs["Alpha"], m.inputs[1])
        nt.links.new(m.outputs[0], sock)

    mul_into(bsdf.inputs["Alpha"])
    if emission:
        mul_into(bsdf.inputs["Emission Strength"])


# ============================================================================ build context
class Ctx(dict):
    __getattr__ = dict.__getitem__

    def __setattr__(self, k, v):
        self[k] = v


def _scene_setup(scene):
    scene.render.fps = FPS
    scene.render.fps_base = 1.0
    scene.frame_start = 1
    scene.frame_end = FRAME_END
    scene.render.resolution_x, scene.render.resolution_y = 1280, 720
    scene["space_seed"] = SPACE_SEED
    scene["landing_height"] = LANDING_HEIGHT
    scene["core_color"] = [c / 255.0 for c in CORE_RGB]
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 12
    scene.cycles.use_denoising = True
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    space.configure_render(scene)


# ============================================================================ space stage
# Core fall speed (studs/s, downward) at times; the fall is integrated from these.
CORE_SPEED = [(0.0, 0.0), (1.5, 0.6), (4.0, 3.5), (10.0, 6.5), (12.5, 10.0), (15.0, 18.0), (16.6, 27.0),
              (17.6, 42.0), (18.0, 72.0), (18.3, 105.0), (18.6, 120.0)]
RIFT_SCALE = 1.6
T_RIFT_PASS = 18.25           # the core passes the space rift's plane


def _core_space_table():
    """Core position every 1/120 s over the space stage (integrated speed + a lazy drift)."""
    dt = 1.0 / 120
    out, z = [], 0.0
    n = int(round(T_SWITCH / dt)) + 1
    for i in range(n):
        t = i * dt
        v = piecewise(CORE_SPEED, t, ease=lambda u: u)
        if i:
            z -= v * dt
        drift = smooth(t / 12.0)
        out.append(Vector((1.6 * math.sin(0.33 * t) * drift, 0.9 * math.sin(0.21 * t + 0.8) * drift, z)))
    return out, dt


_CORE_TABLE = None


def core_space_pos(t):
    global _CORE_TABLE
    if _CORE_TABLE is None:
        _CORE_TABLE = _core_space_table()
    tab, dt = _CORE_TABLE
    x = clamp01(t / T_SWITCH) * (len(tab) - 1)
    i = min(int(x), len(tab) - 2)
    return tab[i].lerp(tab[i + 1], x - i)


def rift_space_z():
    return core_space_pos(T_RIFT_PASS).z


def core_glow(t):
    """SoulCore channels (glow 0-3, pulse 0-1, tail 0-1) over the whole cutscene."""
    # S0 heartbeat: three beats growing to full brightness at 1.5
    beats = [(0.25, 0.35), (0.75, 0.6), (1.18, 1.0)]
    pulse = 0.0
    for tb, amp in beats:
        u = t - tb
        if u > -0.06:
            pulse = max(pulse, amp * math.exp(-max(u, 0) / 0.16) * smooth((u + 0.06) / 0.06))
    if t > 1.5:   # slow breathing pulse afterwards
        pulse = max(pulse, 0.18 * (0.5 + 0.5 * math.sin((t - 1.5) * 2 * math.pi / 1.4 - math.pi / 2)) * (1 - remap(t, 16.0, 18.0)))
    glow = piecewise([(0.0, 0.04), (0.3, 0.12), (0.8, 0.35), (1.25, 0.7), (1.5, 1.0), (10.0, 1.15), (15.0, 1.3),
                      (17.6, 1.8), (18.4, 2.6), (18.6, 2.4), (19.3, 2.2), (20.3, 1.4), (20.75, 2.6), (20.9, 3.0),
                      (21.0, 3.0)], t)
    if t >= 20.3:
        pulse = max(pulse, 0.5 + 0.5 * math.sin((t - 20.3) * 2 * math.pi * 3.0)) * remap(t, 20.3, 20.6)
    tail = piecewise([(0.0, 0.0), (3.0, 0.0), (9.0, 1.0), (18.6, 1.0), (19.3, 1.0), (20.0, 0.35), (20.3, 0.0)], t)
    return glow, pulse, tail


def _cone_mesh(name, r0, segs=24, rings=12):
    """Tapered cone along +Z (0..1), base radius r0, with a 'u' attribute 0 (base) .. 1 (tip)."""
    bm = bmesh.new()
    rows = []
    for k in range(rings + 1):
        u = k / rings
        r = r0 * (0.55 + 1.9 * u ** 0.75) if k < rings else 0.0
        if k == rings:
            rows.append([bm.verts.new((0, 0, 1.04))])
            break
        rows.append([bm.verts.new((math.cos(a) * r, math.sin(a) * r, u)) for a in (j / segs * math.tau for j in range(segs))])
    for k in range(len(rows) - 1):
        a, b = rows[k], rows[k + 1]
        for j in range(segs):
            j1 = (j + 1) % segs
            if len(b) == 1:
                bm.faces.new((a[j], a[j1], b[0]))
            else:
                bm.faces.new((a[j], a[j1], b[j1], b[j]))
    bm.faces.new(list(reversed(rows[0])))
    return bm


def _tail_material():
    """Comet tail: emissive core colour fading along the cone (Generated Z) and at grazing angles."""
    m = bpy.data.materials.new("Preview_CometTail")
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(sep.outputs["Z"], inv.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    nt.links.new(inv.outputs[0], pw.inputs[0])
    pw.inputs[1].default_value = 2.4
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.7
    face = nt.nodes.new("ShaderNodeMath")
    face.operation = "SUBTRACT"
    face.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], face.inputs[1])
    face2 = nt.nodes.new("ShaderNodeMath")
    face2.operation = "POWER"
    nt.links.new(face.outputs[0], face2.inputs[0])
    face2.inputs[1].default_value = 2.5
    a = nt.nodes.new("ShaderNodeMath")
    a.operation = "MULTIPLY"
    nt.links.new(pw.outputs[0], a.inputs[0])
    nt.links.new(face2.outputs[0], a.inputs[1])
    strength = nt.nodes.new("ShaderNodeValue")
    strength.name = strength.label = "tail_strength"
    strength.outputs[0].default_value = 1.0
    a2 = nt.nodes.new("ShaderNodeMath")
    a2.operation = "MULTIPLY"
    nt.links.new(a.outputs[0], a2.inputs[0])
    nt.links.new(strength.outputs[0], a2.inputs[1])
    a3 = nt.nodes.new("ShaderNodeMath")
    a3.operation = "MINIMUM"
    nt.links.new(a2.outputs[0], a3.inputs[0])
    a3.inputs[1].default_value = 1.0
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*[min(1.0, c * 1.15 + 0.05) for c in CORE_LIN], 1)
    em.inputs["Strength"].default_value = 3.0
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(a3.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def _halo_material(name, rgb_lin):
    """Soft glow shell: emission strongest where the surface faces the camera."""
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    nt.links.new(inv.outputs[0], pw.inputs[0])
    pw.inputs[1].default_value = 4.0
    amt = nt.nodes.new("ShaderNodeValue")
    amt.name = amt.label = "alpha"
    amt.outputs[0].default_value = 0.3
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(pw.outputs[0], mul.inputs[0])
    nt.links.new(amt.outputs[0], mul.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb_lin, 1)
    em.inputs["Strength"].default_value = 2.5
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(mul.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def build_soul_core(ctx):
    """SoulCore (track, both stages until the morph) + preview halo, light and comet tail."""
    coll = ctx.colls["core"]
    core = new_empty("SoulCore", coll, 1.5, display="SPHERE")
    ctx.intro.place("SoulCore", coll, core)
    core.rotation_mode = "QUATERNION"
    halo_bm = bmesh.new()
    bmesh.ops.create_uvsphere(halo_bm, u_segments=32, v_segments=16, radius=1.0)
    halo = mesh_object("SoulCoreHalo", halo_bm, coll, [_halo_material("Preview_CoreHalo", CORE_LIN)], smooth=True)
    halo.visible_shadow = False
    light = bpy.data.objects.new("SoulCoreLight", bpy.data.lights.new("SoulCoreLight", "POINT"))
    light.data.color = CORE_LIN
    light.data.shadow_soft_size = 1.0
    coll.objects.link(light)
    tail = mesh_object("SoulCoreTail", _cone_mesh("SoulCoreTail", 0.62), coll, [_tail_material()], smooth=True)
    tail.visible_shadow = False
    tail.rotation_mode = "QUATERNION"
    ctx.core = core
    ctx.core_fx = {"halo": halo, "light": light, "tail": tail}
    return core


def bake_soul_core(ctx, pos_fn, rot_fn, frames, visible_keys):
    """Bake the core's transform + channels + preview FX for the given frames.
    pos_fn(t) / rot_fn(t): world position / Quaternion. visible_keys: [(t, 0/1)]."""
    core, fx = ctx.core, ctx.core_fx
    pos = [pos_fn(T(f)) for f in frames]
    rots, prev = [], None
    for f in frames:
        q = rot_fn(T(f))
        if prev is not None and prev.dot(q) < 0:
            q = -q
        rots.append(q)
        prev = q
    bake_vec(core, "location", frames, pos, interp="BEZIER")
    bake_vec(core, "rotation_quaternion", frames, rots, interp="BEZIER")
    chans = [core_glow(T(f)) for f in frames]
    for i, name in enumerate(("glow", "pulse", "tail")):
        key_prop_frames(core, name, frames, [c[i] for c in chans], interp="LINEAR")
    # cuts: hold the last pre-cut key (the exporter's convention)
    _hold_before_cuts(core)
    key_visible(core, visible_keys, extra=[fx["halo"], fx["light"], fx["tail"]])

    # preview look: glow node, tint toward white when hot, halo size/alpha, light, tail
    glow_mat = bpy.data.materials.get("Intro_CoreGlow")
    ring_mat = bpy.data.materials.get("Intro_CoreRing")
    gv, tint, halo_s, halo_a, light_e, tail_q, tail_s, tail_l, tail_str = [], [], [], [], [], [], [], [], []
    for k, f in enumerate(frames):
        g, p, tl = chans[k]
        level = clamp01(g) ** 0.8
        hot = clamp01((g - 1) / 2) * 0.55 + clamp01(p) * 0.15
        gv.append(level * (1 + 0.35 * p) * (1 + 0.6 * max(0.0, g - 1)))
        tint.append(tuple(lerp(c, 1.0, hot) for c in CORE_LIN))
        d = (2.9 + 1.1 * min(g, 3)) * (1 + 0.35 * p)
        halo_s.append(d / 2)
        halo_a.append(min(0.55, 0.05 + 0.09 * g + 0.22 * p) * level)
        light_e.append((0.8 * g + 1.6 * p) * 400.0)
        # tail along the anti-velocity
        t = T(f)
        v = (pos_fn(t + 0.02) - pos_fn(t - 0.02)) / 0.04
        dirn = (-v).normalized() if v.length > 0.5 else Vector((0, 0, 1))
        tail_q.append(Vector((0, 0, 1)).rotation_difference(dirn))
        L = max(tl * 18.0, 0.01)
        tail_l.append(L)
        tail_s.append(min(1.0, 0.45 + 0.55 * tl))
        tail_str.append(tl * (0.22 + 0.16 * min(g, 2) / 2))
    for m in (glow_mat, ring_mat):
        if m is not None:
            nt = m.node_tree
            bake(nt, 'nodes["glow"].outputs[0].default_value', frames, gv)
            for i in range(3):
                bake(nt, 'nodes["tint"].outputs[0].default_value', frames, [c[i] for c in tint], index=i)
    halo, light, tail = fx["halo"], fx["light"], fx["tail"]
    for o in (halo, light, tail):
        o.parent = None
    bake_vec(halo, "location", frames, pos, interp="BEZIER")
    bake_vec(halo, "scale", frames, [(s, s, s) for s in halo_s])
    bake(halo.active_material.node_tree, 'nodes["alpha"].outputs[0].default_value', frames, halo_a)
    bake_vec(light, "location", frames, pos, interp="BEZIER")
    bake(light.data, "energy", frames, light_e)
    bake_vec(tail, "location", frames, pos, interp="BEZIER")
    bake_vec(tail, "rotation_quaternion", frames, tail_q)
    bake_vec(tail, "scale", frames, [(s, s, l) for s, l in zip(tail_s, tail_l)])
    bake(tail.active_material.node_tree, 'nodes["tail_strength"].outputs[0].default_value', frames, tail_str)


def _hold_before_cuts(idb, cut_frames=None):
    """Keys on the frame before a cut become CONSTANT (hold the old shot through the last
    interval) with vector handles on both sides of the jump (DESIGN cuts / exporter docstring)."""
    cut_frames = cut_frames or [F(c) for c in CUTS]
    ad = idb.animation_data
    if not ad or not ad.action:
        return
    for fc in _channelbag(idb).fcurves:
        for kp in fc.keyframe_points:
            f = int(round(kp.co.x))
            if f + 1 in cut_frames:
                kp.interpolation = "CONSTANT"
                kp.handle_left_type = kp.handle_right_type = "VECTOR"
            elif f in cut_frames:
                kp.handle_left_type = kp.handle_right_type = "VECTOR"
        fc.update()


def build_sky(ctx):
    """SkyAnchor (Copy Location of the Camera) with the SpaceDome and the Starfield preview."""
    coll = ctx.colls["sky"]
    anchor = new_empty("SkyAnchor", coll, 5)
    con = anchor.constraints.new("COPY_LOCATION")
    con.target = ctx.camera
    dome = ctx.intro.place("SpaceDome", coll, anchor)
    for o in dome.values():
        o.visible_shadow = False
        o.name = "SpaceDome" if o.name.endswith("Void") else o.name
    data = space.generate(SPACE_SEED)
    h = space.build_preview(coll, data, parent=anchor)
    # S1: first a few stars, then thousands (2-7), nebulae bloom (3-8), galaxies swirl together (4-9.5)
    space.key_channels(h, 1, stars=0.0, nebula=0.0, galaxies=0.0, twinkle=0.75)
    space.key_channels(h, F(2.0), stars=0.0)
    space.key_channels(h, F(3.2), stars=0.12)
    space.key_channels(h, F(5.0), stars=0.45)
    space.key_channels(h, F(7.0), stars=1.0)
    space.key_channels(h, F(3.0), nebula=0.0)
    space.key_channels(h, F(8.0), nebula=1.0)
    space.key_channels(h, F(4.0), galaxies=0.0)
    space.key_channels(h, F(9.5), galaxies=1.0)
    space.key_channels(h, F(18.6), stars=1.0, nebula=1.0, galaxies=1.0, twinkle=0.75)
    sf = h["starfield"]
    for fc in _channelbag(sf).fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "BEZIER"
            kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
        fc.update()
    ctx.sky = {"anchor": anchor, "starfield": h}
    stage_only([anchor] + list(anchor.children_recursive), "space")
    return anchor


# ---------------------------------------------------------------------------- planet
PLANET_SCALE = 0.27
PLANET_SCREEN = (0.5, 0.06)      # where the planet sits in the frame at the end of the S2 swing
PLANET_DIST = (640.0, 600.0, 430.0)  # distance from the camera at 10.0 / 12.5 / 18.6


def _space_axes(t):
    """Camera right / up / toward-camera axes (world) of the space camera at t."""
    eye, q, lns = space_cam(t)
    return eye, q, lns, q @ Vector((1, 0, 0)), q @ Vector((0, 1, 0)), q @ Vector((0, 0, 1))


_PLANET = {}


def planet_setup():
    """Planet placement from the composition at the end of the swing (12.5): centre on the ray
    through PLANET_SCREEN, destroyed side turned to screen-left and a little toward the camera,
    sunlight from screen-right and slightly behind it (a lit crescent + a glowing fracture face)."""
    if _PLANET:
        return _PLANET
    eye, q, lns, right, up, back = _space_axes(12.5)
    ray = screen_ray(eye, q, lns, *PLANET_SCREEN)
    c125 = eye + ray * PLANET_DIST[1]
    _PLANET["center"] = c125
    _PLANET["cut"] = (-right * 0.95 + back * 0.22 - up * 0.1).normalized()
    _PLANET["sun_dir"] = (right * 0.6 + back * 0.3 + up * 0.55).normalized()   # toward the sun
    _PLANET["eye125"] = eye
    return _PLANET


def planet_pos(t):
    """Planet centre: on the composition ray, drifting closer from 12.5 on (it looms larger)."""
    ps = planet_setup()
    c = ps["center"]
    eye = ps["eye125"]
    ray = (c - eye).normalized()
    d = spline_num([(0.0, PLANET_DIST[0] + 20.0), (10.0, PLANET_DIST[0]), (12.5, PLANET_DIST[1]),
                    (18.6, PLANET_DIST[2])], t)
    # keep it on the same ray from the falling camera so it stays put in the frame while it looms
    cam_drop = core_space_pos(t) - core_space_pos(12.5)
    return eye + cam_drop * (1.0 if t > 12.5 else 0.0) + ray * d


def build_planet(ctx):
    import assets_intro
    coll = ctx.colls["space"]
    planet = new_empty("Planet", coll, 60, display="SPHERE")
    ctx.intro.place("ShatteredPlanet", coll, planet)
    planet.rotation_mode = "QUATERNION"
    ps = planet_setup()
    base = Vector(assets_intro.CUT_DIR).rotation_difference(ps["cut"])
    frames = sorted(set(list(range(1, F_SWITCH + 1, 3)) + [F_SWITCH - 1]))
    axis = (base @ Vector((0.15, 0.2, 1.0))).normalized()
    pos, rot = [], []
    for f in frames:
        t = T(f)
        pos.append(planet_pos(t))
        rot.append(Quaternion(axis, math.radians(-0.5 * (t - 12.5))) @ base)
    bake_vec(planet, "location", frames, pos, interp="BEZIER")
    bake_vec(planet, "rotation_quaternion", frames, rot, interp="BEZIER")
    s = PLANET_SCALE
    planet.scale = (s, s, s)
    key_visible(planet, [(0.0, 1), (T_SWITCH, 0)])
    for o in planet.children:
        if "Debris" in o.name or "Cloud" in o.name:
            o.visible_shadow = False
    ctx.planet = planet
    return planet


# ---------------------------------------------------------------------------- rift
def _rift_pieces(objs):
    cracks = sorted([o for n, o in objs.items() if "__Crack_" in n], key=lambda o: o.name)
    shards = sorted([o for n, o in objs.items() if "__Shard_" in n], key=lambda o: o.name)
    rims = [o for n, o in objs.items() if n.endswith("__RiftEdge")]
    views = [o for n, o in objs.items() if n.endswith("__RiftView")]
    return cracks, shards, rims, views


def build_rift(ctx, name, coll, far_side=False):
    """A Rift track object (empty) with copies of the asset pieces. far_side: the view becomes a
    dark violet hole (SkyRift, like the runtime)."""
    rift = new_empty(name, coll, 14, display="CIRCLE")
    objs = ctx.intro.place("Rift", coll, rift, prefix=name)
    for m in ("Intro_Crack", "Intro_Shard"):
        mat = bpy.data.materials.get(m)
        if mat is not None:
            _object_alpha(mat)
    cracks, shards, rims, views = _rift_pieces(objs)
    for o in cracks + shards + rims + views:
        o.visible_shadow = False
    if far_side:
        hole = bpy.data.materials.get("Preview_RiftHole") or emission_material("Preview_RiftHole", lin((24, 10, 46)), 1.6)
        for v in views:
            v.material_slots[0].link = "OBJECT"
            v.material_slots[0].material = hole
    rng = random.Random(1009 + len(name))
    roles = []
    for k, o in enumerate(shards):
        c = o.matrix_basis.translation.copy()
        flat = Vector((c.x, c.y, 0.0))
        a = rng.uniform(0, math.tau)
        roles.append({
            "dir": flat.normalized() if flat.length > 0.3 else Vector((math.cos(a), math.sin(a), 0)),
            "dist": rng.uniform(9, 24), "lift": rng.uniform(0.5, 5),
            "axis": Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized(),
            "spin": rng.uniform(2.5, 7.5), "fade": rng.uniform(0.4, 0.62),
        })
    return {"obj": rift, "cracks": cracks, "shards": shards, "rims": rims, "views": views, "roles": roles,
            "base": {o.name: o.matrix_basis.copy() for o in cracks + shards + rims + views}}


def bake_rift(rift, frames, crack_fn, open_fn):
    """Per-frame look of the rift pieces from crack/open, mirroring SpaceStage.Rift:Update:
    cracks revealed in order with flicker and faded out as it opens, shards flung outward
    (eased), tumbling, shrinking and fading, rim and view scaled in."""
    n = len(rift["cracks"])
    data = {o.name: {"a": [], "loc": [], "rot": [], "s": []} for o in rift["cracks"] + rift["shards"] + rift["rims"] + rift["views"]}
    for f in frames:
        t = T(f)
        crack, opn = crack_fn(t), open_fn(t)
        frame = math.floor(t * 30)
        openE = 1 - (1 - opn) ** 2.2
        rimS = 0.22 + 0.78 * smooth(opn / 0.7)
        viewS = smooth((opn - 0.04) / 0.6)
        crackFade = 1 - smooth(opn / 0.35)
        for k, o in enumerate(rift["cracks"]):
            r = k / max(n, 1) * 0.9
            lvl = clamp01((crack - r) / 0.05)
            fresh = 1 - clamp01((crack - r) / 0.18)
            flick = 1.0 if _hash(k + 1, frame) > 0.45 else 0.2
            vis = lvl * (1 - fresh * (1 - flick)) * crackFade
            b = rift["base"][o.name]
            d = data[o.name]
            d["a"].append(vis)
            d["loc"].append(b.translation)
            d["rot"].append(b.to_quaternion())
            d["s"].append(1.0)
        for o, role in zip(rift["shards"], rift["roles"]):
            b = rift["base"][o.name]
            glass = 1.0 if opn > 0.001 else smooth((crack - 0.55) / 0.45) * 0.55
            vis = glass * (1 - smooth((opn - role["fade"]) / (1 - role["fade"])))
            loc, q, s = b.translation, b.to_quaternion(), 1.0
            if opn > 0.001:
                loc = b.translation + role["dir"] * (role["dist"] * openE) + Vector((0, 0, role["lift"] * openE))
                q = Quaternion(role["axis"], role["spin"] * opn) @ q
                s = 1 - 0.35 * opn
            d = data[o.name]
            d["a"].append(vis)
            d["loc"].append(loc)
            d["rot"].append(q)
            d["s"].append(s)
        for o in rift["rims"]:
            b = rift["base"][o.name]
            d = data[o.name]
            d["a"].append(1.0 if opn > 0.005 else 0.0)
            d["loc"].append(b.translation * rimS)
            d["rot"].append(b.to_quaternion())
            d["s"].append(rimS)
        for o in rift["views"]:
            b = rift["base"][o.name]
            d = data[o.name]
            d["a"].append(1.0 if viewS > 0.02 else 0.0)
            d["loc"].append(b.translation * viewS)
            d["rot"].append(b.to_quaternion())
            d["s"].append(max(viewS, 0.02))
    for o in rift["cracks"] + rift["shards"] + rift["rims"] + rift["views"]:
        d = data[o.name]
        o.rotation_mode = "QUATERNION"
        fade = o in rift["cracks"] or o in rift["shards"]
        if fade:
            bake(o, "color", frames, d["a"], index=3)
            bake(o, "hide_render", frames, [1.0 if a < 0.01 else 0.0 for a in d["a"]], interp="CONSTANT")
        else:
            bake(o, "hide_render", frames, [1.0 if a < 0.5 else 0.0 for a in d["a"]], interp="CONSTANT")
        if any((l - d["loc"][0]).length > 1e-6 for l in d["loc"]) or any(abs(s - d["s"][0]) > 1e-6 for s in d["s"]):
            bake_vec(o, "location", frames, d["loc"])
            bake_vec(o, "rotation_quaternion", frames, d["rot"])
            bake_vec(o, "scale", frames, [(s, s, s) for s in d["s"]])


def build_space_rift(ctx):
    coll = ctx.colls["space"]
    rift = build_rift(ctx, "Rift", coll)
    obj = rift["obj"]
    obj.location = (0.0, 0.0, rift_space_z())
    obj.scale = (RIFT_SCALE,) * 3
    ck = [(0.0, 0.0), (15.0, 0.0), (16.6, 1.0)]
    ok = [(0.0, 0.0), (16.6, 0.0), (17.6, 1.0)]
    key_prop(obj, "crack", ck, interp="LINEAR")
    key_prop(obj, "open", ok, interp="BEZIER")

    def crack_fn(t):
        return piecewise(ck, t, ease=lambda u: u)

    def open_fn(t):
        return piecewise(ok, t, ease=smooth)
    frames = list(range(F(14.8), F_SWITCH + 1))
    bake_rift(rift, frames, crack_fn, open_fn)
    key_visible(obj, [(0.0, 0), (14.8, 1), (T_SWITCH, 0)])
    # visible keys rewrote hide_render of the pieces: re-bake the per-frame piece visibility
    bake_rift(rift, frames, crack_fn, open_fn)
    for o in [obj] + list(obj.children_recursive):
        fc = fcurve(o, "hide_render")
        pts = {int(round(k.co.x)): k.co.y for k in fc.keyframe_points}
        pts[1] = 1.0
        pts[F_SWITCH] = 1.0
        fs = sorted(pts)
        bake(o, "hide_render", fs, [pts[f] for f in fs], interp="CONSTANT")
    ctx.rift = rift
    return rift


# ---------------------------------------------------------------------------- dust
def build_space_dust(ctx):
    """Preview only: specks hanging in space along the fall (they stream upward past the camera)."""
    coll = ctx.colls["space"]
    rng = random.Random(5)
    bm = bmesh.new()
    z_top, z_bot = 25.0, rift_space_z() + 4.0
    n = 1400
    for _ in range(n):
        z = rng.uniform(z_bot, z_top)
        a = rng.uniform(0, math.tau)
        r = 2.5 + 45.0 * rng.random() ** 1.4
        p = Vector((math.cos(a) * r, math.sin(a) * r, z))
        s = rng.uniform(0.018, 0.05)
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=s, matrix=Matrix.Translation(p))
    mat = emission_material("Preview_Dust", (0.75, 0.82, 1.0), 1.6)
    dust = mesh_object("SpaceDust", bm, coll, [mat])
    dust.visible_shadow = False
    return dust


def build_space_lights(ctx):
    coll = ctx.colls["space"]
    sun = bpy.data.objects.new("SpaceSun", bpy.data.lights.new("SpaceSun", "SUN"))
    sun.data.energy = 4.0
    sun.data.angle = math.radians(1.0)
    sun.data.color = (1.0, 0.96, 0.9)
    d = -planet_setup()["sun_dir"]                    # the light travels this way
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(d)
    coll.objects.link(sun)
    return sun


# ============================================================================ camera
SENSOR = 24.0
ASPECT = 16.0 / 9.0


def lens_of_fov(vfov_deg):
    return SENSOR / 2 / math.tan(math.radians(vfov_deg) / 2)


def fov_of_lens(lens):
    return math.degrees(2 * math.atan(SENSOR / 2 / lens))


def frame_subject(eye, subject, vfov, sx=0.0, sy=0.0, roll=0.0, up=Vector((0, 0, 1))):
    """Camera rotation from eye that shows `subject` at screen position (sx, sy) (-1..1, x right,
    y up; e.g. sy = -1/3 puts it on the lower third line), with a roll (radians)."""
    q = look_quat(eye, subject, up=up)
    th = math.tan(math.radians(vfov) / 2)
    ax = math.atan(sx * th * ASPECT)
    ay = -math.atan(sy * th)
    return q @ Quaternion((0, 1, 0), ax) @ Quaternion((1, 0, 0), ay) @ Quaternion((0, 0, 1), roll)


def orbit_eye(center, az, el, dist):
    """Point at azimuth az (deg from +X toward +Y), elevation el (deg), distance dist from center."""
    a, e = math.radians(az), math.radians(el)
    return Vector(center) + Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))) * dist


def damp_path(samples, tau, dt=1.0 / FPS):
    """Critically damped follow of a sampled path (list of Vectors at dt): lag ~ tau seconds."""
    if tau <= 0:
        return [Vector(s) for s in samples]
    out = [Vector(samples[0])]
    x, v = Vector(samples[0]), Vector((0, 0, 0))
    w = 2.0 / tau
    sub = 4
    h = dt / sub
    for k in range(1, len(samples)):
        a0, a1 = Vector(samples[k - 1]), Vector(samples[k])
        for j in range(sub):
            target = a0.lerp(a1, (j + 1) / sub)
            acc = (target - x) * (w * w) - v * (2 * w)
            v = v + acc * h
            x = x + v * h
        out.append(x.copy())
    return out


class CameraTrack:
    """Per-frame camera samples (eye, rotation, lens), baked onto Camera at the end."""

    def __init__(self):
        self.samples = {}

    def put(self, f, eye, rot, lens):
        self.samples[f] = (Vector(eye), Quaternion(rot), float(lens))

    def bake(self, cam):
        frames = sorted(self.samples)
        eyes = [self.samples[f][0] for f in frames]
        quats, prev = [], None
        for f in frames:
            q = self.samples[f][1].normalized()
            if prev is not None and prev.dot(q) < 0:
                q = -q
            quats.append(q)
            prev = q
        cam.rotation_mode = "QUATERNION"
        bake_vec(cam, "location", frames, eyes, interp="BEZIER")
        bake_vec(cam, "rotation_quaternion", frames, quats, interp="BEZIER")
        bake(cam.data, "lens", frames, [self.samples[f][2] for f in frames], interp="BEZIER")
        _hold_before_cuts(cam)
        _hold_before_cuts(cam.data)


def build_camera(ctx):
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.sensor_fit = "VERTICAL"
    cam.data.sensor_height = SENSOR
    cam.data.sensor_width = SENSOR * ASPECT
    cam.data.clip_start = 0.1
    cam.data.clip_end = 6000.0
    ctx.colls["root"].objects.link(cam)
    bpy.context.scene.camera = cam
    ctx.camera = cam
    ctx.camtrack = CameraTrack()
    return cam


# ---------------------------------------------------------------------------- space camera
VISIBLE_H = (16.0 / 9.0) / 2.39          # the part of the frame height between the cinematic bars
THIRD = VISIBLE_H / 3                    # screen y of the thirds lines (full-frame units)

SPACE_ORBIT = [  # (t, azimuth, elevation, distance) around the core
    (0.0, -96.0, 4.0, 13.0), (1.5, -98.0, -2.0, 12.6), (4.0, -112.0, -16.0, 12.2), (7.0, -132.0, -24.0, 12.0),
    (10.0, -150.0, -24.0, 12.0), (12.5, 30.0, 70.0, 15.0), (15.0, 36.0, 74.0, 13.5), (16.6, 40.0, 77.0, 11.0),
    (17.6, 44.0, 80.0, 9.5), (18.2, 46.0, 84.0, 7.5), (18.6, 46.0, 86.0, 6.5)]
SPACE_FRAMING = [  # (t, sx, sy) screen position of the core
    (0.0, 0.0, 0.0), (1.5, 0.0, 0.0), (3.5, 0.1, -THIRD * 0.9), (7.0, 0.3, -THIRD), (10.0, 0.3, -THIRD), (12.5, 0.05, THIRD * 1.15),
    (15.0, 0.0, THIRD * 1.2), (17.6, 0.0, THIRD * 0.9), (18.15, 0.0, 0.0)]
SPACE_LENS = [(0.0, 40.0), (1.5, 38.0), (4.0, 30.0), (6.5, 28.5), (8.5, 30.0), (10.0, 29.0), (12.5, 28.0),
              (15.0, 28.0), (16.6, 31.0), (17.6, 21.0), (18.3, 17.0), (18.6, 16.0)]
SPACE_ROLL = [(0.0, 0.0), (10.0, 0.0), (11.3, -7.0), (12.5, -2.5), (15.0, -1.5), (17.6, 0.0), (18.6, 5.0)]


def space_cam(t):
    """(eye, rotation, lens) of the space shots S0-S4 at time t: one continuous move."""
    rz = rift_space_z()
    c = core_space_pos(t)
    if 10.0 <= t <= 12.5:      # S2: one continuous eased swing, 180 deg orbit + rise
        u = smoother((t - 10.0) / 2.5)
        az = lerp(SPACE_ORBIT[4][1], SPACE_ORBIT[5][1], u)
        el = lerp(SPACE_ORBIT[4][2], SPACE_ORBIT[5][2], smooth((t - 10.25) / 2.25))
        dist = lerp(SPACE_ORBIT[4][3], SPACE_ORBIT[5][3], u) + 2.5 * math.sin(math.pi * u)
    else:
        az = spline_num([(k[0], k[1]) for k in SPACE_ORBIT], t)
        el = spline_num([(k[0], k[2]) for k in SPACE_ORBIT], t)
        dist = spline_num([(k[0], k[3]) for k in SPACE_ORBIT], t)
    eye = orbit_eye(c, az, el, dist)
    if t < 1.5:   # S0: static with a tiny drift
        eye = eye + Vector((0.08 * math.sin(t * 1.7), 0.06 * math.cos(t * 1.3), 0.05 * math.sin(t * 2.1)))
    if t > 17.6:   # S4: follow it into the rift, never closer than ~3.5 studs to the view disc
        eye.z = max(eye.z, rz + lerp(16.0, 3.4, smooth((t - 17.6) / 0.95)))
    lns = spline_num(SPACE_LENS, t)
    if 1.5 < t < 10.0:   # gentle FOV breathing
        lns *= 1.0 + 0.035 * math.sin((t - 1.5) * 2 * math.pi / 4.2) * smooth((t - 1.5) / 1.5) * smooth((10.0 - t) / 1.0)
    if 10.0 <= t <= 12.5:
        u = smoother((t - 10.0) / 2.5)
        sx, sy = lerp(0.3, 0.05, u), lerp(-THIRD, THIRD * 1.15, smooth((t - 10.2) / 2.1))
    else:
        sx = spline_num([(k[0], k[1]) for k in SPACE_FRAMING], t)
        sy = spline_num([(k[0], k[2]) for k in SPACE_FRAMING], t)
    subject = c
    if t > 18.15:   # the core is gone into the rift: keep looking into it
        subject = c.lerp(Vector((c.x, c.y, rz)), smooth((t - 18.15) / 0.3))
    roll = math.radians(spline_num(SPACE_ROLL, t))
    q = frame_subject(eye, subject, fov_of_lens(lns), sx, sy, roll)
    return eye, q, lns


def screen_ray(eye, q, lens, sx, sy):
    """World direction through screen point (sx, sy) of a camera (eye, q, lens)."""
    th = math.tan(math.radians(fov_of_lens(lens)) / 2)
    return (q @ Vector((sx * th * ASPECT, sy * th, -1.0))).normalized()


def space_camera(ctx):
    """S0-S4: one continuous move from the ignition close-up to the dive into the rift."""
    for f in range(1, F_SWITCH):
        eye, q, lns = space_cam(T(f))
        ctx.camtrack.put(f, eye, q, lns)


# ============================================================================ world shader / stage lights
def build_world_shader(ctx):
    """Black space until the stage switch, then the Sylverune sky (CONSTANT switch)."""
    scene = bpy.context.scene
    w = bpy.data.worlds.new("IntroWorld")
    scene.world = w
    nt = w.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputWorld")
    black = nt.nodes.new("ShaderNodeBackground")
    black.inputs["Color"].default_value = (0, 0, 0, 1)
    black.inputs["Strength"].default_value = 0.0
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "MULTIPLE_SCATTERING" if "MULTIPLE_SCATTERING" in [e.identifier for e in sky.bl_rna.properties["sky_type"].enum_items] else sky.sky_type
    sky.sun_disc = False
    sky.sun_elevation = math.radians(WORLD_SUN_ELEVATION)
    sky.sun_rotation = math.radians(WORLD_SUN_ROTATION)
    sky.altitude = 400.0
    sky.air_density = 1.0
    sky.aerosol_density = 1.2
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 0.32
    nt.links.new(sky.outputs[0], bg.inputs["Color"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.name = "stage"
    nt.links.new(black.outputs[0], mix.inputs[1])
    nt.links.new(bg.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    bake(nt, 'nodes["stage"].inputs[0].default_value', [1, F_SWITCH], [0.0, 1.0], interp="CONSTANT")
    ctx.world = w
    return w


WORLD_SUN_ELEVATION = 38.0     # degrees
WORLD_SUN_ROTATION = -35.0     # sky texture sun rotation (degrees, from +Y? see build_world_lights)


# ============================================================================ build
def _collections(scene):
    root = new_collection("Intro", scene.collection)
    colls = {"root": root}
    for name in ("sky", "space", "core", "world", "env", "trees", "character", "sword", "fx"):
        colls[name] = new_collection("Intro_" + name.capitalize(), root)
    return colls


def build(parts=("space", "world"), verbose=True):
    """Build the whole cutscene into the current file (call on an empty file). Returns the ctx."""
    import time
    t0 = time.time()
    scene = bpy.context.scene
    _scene_setup(scene)
    ctx = Ctx()
    ctx.colls = _collections(scene)
    ctx.intro = AssetLib(INTRO_ASSETS)
    ctx.intro_materials = {m.name for m in bpy.data.materials}
    build_camera(ctx)
    build_world_shader(ctx)
    build_soul_core(ctx)

    def log(msg):
        if verbose:
            print("scene: %-40s %6.1f s" % (msg, time.time() - t0))

    if "space" in parts:
        build_sky(ctx)
        build_planet(ctx)
        build_space_rift(ctx)
        dust = build_space_dust(ctx)
        sun = build_space_lights(ctx)
        stage_only([dust, sun], "space")
        space_camera(ctx)
        log("space stage")
    if "world" in parts:
        build_world(ctx)
        log("world stage")
    # soul core over both stages
    core_frames = list(range(1, F(21.0) + 1))
    bake_soul_core(ctx, core_position, core_rotation, core_frames, [(0.0, 1), (20.9, 0)])
    ctx.camtrack.bake(ctx.camera)
    build_markers(scene)
    log("baked")
    scene.frame_set(1)
    return ctx


def core_position(t):
    if t < T_SWITCH:
        return core_space_pos(t)
    return core_world_pos(t)


def core_rotation(t):
    spin = 0.55 * t + 0.35 * max(0.0, t - 15.0) ** 2 if t < T_SWITCH else 1.6 * (t - T_SWITCH) + 4.0
    return Quaternion((0.0, 0.0, 1.0), spin) @ Quaternion((1.0, 0.0, 0.0), 0.35 * math.sin(0.4 * t))


def build_world(ctx):
    raise NotImplementedError


def core_world_pos(t):
    return Vector((0.0, 0.0, 400.0))


# ============================================================================ markers
MARKERS = [
    # S0-S4 (space)
    (0.0, "bars:in:1.0"), (0.0, "fade:from_black:1.0"), (0.0, "sound:ignite"), (1.45, "flash:core:0.35"),
    (10.0, "sound:whoosh"), (12.5, "shake:0.12:2.5"), (15.0, "sound:crack"), (15.0, "shake:0.4:1.6"),
    (16.6, "sound:rift"), (16.6, "flash:white:0.15"), (16.6, "shake:0.6:1.0"), (17.6, "speedlines:on"),
    (17.6, "sound:whoosh"), (18.5, "flash:white:0.35"), (18.6, "speedlines:off"),
    # W1-W8 (world)
    (18.6, "stage:world"), (18.6, "cut"), (18.7, "sound:whoosh"), (20.3, "morph"), (20.9, "flash:white:0.3"),
    (23.0, "cut"), (25.4, "shake:0.25:0.6"), (26.5, "cut"), (26.6, "shake:0.3:0.8"), (27.6, "shake:0.35:0.5"),
    (28.0, "sound:impact"),
    # impact frames 28.0-28.9 (alternating every 2 frames) are added by build_markers
    (28.9, "resonate"), (28.9, "sound:resonance"), (28.9, "shake:0.8:0.8"), (29.0, "flash:white:0.4"),
    (30.2, "sound:whoosh"), (31.6, "speedlines:on"), (31.6, "sound:wind"), (33.0, "shake:0.25:1.2"),
    (34.0, "shake:0.5:1.0"), (35.0, "speedlines:off"), (35.0, "shockwave"), (35.0, "sound:shockwave"),
    (35.0, "shake:1.2:0.7"), (35.0, "flash:white:0.2"), (35.1, "cut"), (35.1, "wind:1.0"),
    (38.0, "cut"), (39.2, "sound:land"), (39.2, "shake:0.12:0.3"), (41.5, "bars:out:1.0"), (42.5, "end"),
]
IMPACT_FRAMES = (F(28.0), F(28.9))     # impact:white / black every 2 frames, then impact:off


def build_markers(scene):
    scene.timeline_markers.clear()
    ms = [(F(t), n) for t, n in MARKERS]
    f0, f1 = IMPACT_FRAMES
    k = 0
    for f in range(f0, f1, 2):
        ms.append((f, "impact:white" if k % 2 == 0 else "impact:black"))
        k += 1
    ms.append((f1, "impact:off"))
    ms.sort(key=lambda m: m[0])      # stable: same-frame markers keep the authored order
    for f, n in ms:
        scene.timeline_markers.new(n, frame=f)


# ============================================================================ character performance
BONES = R.BONES
C3 = R.C                     # Blender -> Roblox (3x3)
L_THIGH, L_SHIN = 1.2, 0.85  # hip -> knee, knee -> ankle (DESIGN §4.1)
ANKLE_ABOVE_SOLE = 0.15
# per-joint lag in seconds: overlapping action / follow-through (the core leads, limbs follow)
LAG = {"Root": 0.0, "Waist": 0.015, "Neck": 0.05, "LeftShoulder": 0.035, "RightShoulder": 0.035,
       "LeftElbow": 0.07, "RightElbow": 0.07, "LeftWrist": 0.1, "RightWrist": 0.1,
       "LeftHip": 0.02, "RightHip": 0.02, "LeftKnee": 0.045, "RightKnee": 0.045,
       "LeftAnkle": 0.07, "RightAnkle": 0.07}


def pose_quats(pose):
    """Pose (name / dict) -> ({bone: Quaternion}, root loc Vector)."""
    p = P.full_pose(pose)
    return {b: euler_deg_quat(p[b]) for b in BONES}, Vector(p[P.LOC_KEY])


def fk_q(q, loc):
    """Roblox character-space joint frames (4x4, HRP = identity) of joint quaternions + Root loc."""
    frames = {}
    for bone, parent, _part, pv in R.JOINTS:
        pv = Vector(pv)
        if parent is None:
            base = Matrix.Translation(pv + Vector(loc))
        else:
            base = frames[parent] @ Matrix.Translation(pv - R.PIVOT[parent])
        frames[bone] = base @ q[bone].to_matrix().to_4x4()
    return frames


def root_matrix(pos, rot):
    return Matrix.Translation(pos) @ rot.to_matrix().to_4x4()


def to_char(Mroot, p_world):
    """World (Blender) point -> Roblox character space of a root matrix."""
    return C3 @ (Mroot.inverted() @ Vector(p_world))


def to_world(Mroot, p_char):
    return Mroot @ (C3.transposed() @ Vector(p_char))


def rot_to_char(Mroot, R_world):
    """World (Blender) 3x3 orientation of a part -> Roblox character space (rest = identity)."""
    return C3 @ Mroot.to_3x3().inverted() @ R_world @ C3.transposed()


def solve_leg(q, loc, side, ankle_target, foot_rot):
    """Two-bone IK in Roblox character space: hip + knee put the ankle pivot on ankle_target, the
    knee keeps pointing where the pose's knee points, the ankle gives the foot foot_rot (3x3).
    Returns {bone: Quaternion} for the three leg joints."""
    hip, knee, ankle = side + "Hip", side + "Knee", side + "Ankle"
    frames = fk_q(q, loc)
    H0 = frames["Root"] @ Matrix.Translation(R.PIVOT[hip] - R.PIVOT["Root"])
    H0r = H0.to_3x3()
    a_t = H0r.inverted() @ (Vector(ankle_target) - H0.translation)
    d = max(0.35, min(a_t.length, L_THIGH + L_SHIN - 1e-3))
    cosk = (L_THIGH ** 2 + L_SHIN ** 2 - d * d) / (2 * L_THIGH * L_SHIN)
    thk = math.pi - math.acos(max(-1.0, min(1.0, cosk)))          # knee flexion
    a0 = Vector((0.0, -L_THIGH - L_SHIN * math.cos(thk), L_SHIN * math.sin(thk)))
    k0 = Vector((0.0, -L_THIGH, 0.0))

    def frame_of(u, v_hint):
        u = u.normalized()
        v = v_hint - u * v_hint.dot(u)
        if v.length < 1e-6:
            v = Vector((0, 0, -1)) - u * (-u.z)
        v.normalize()
        return Matrix((u, v, u.cross(v))).transposed()

    M0 = frame_of(a0, k0)
    pole = q[hip].to_matrix() @ Vector((0.0, -0.25, -1.0))       # the pose's knee direction (forward)
    M1 = frame_of(a_t, pole)
    Rh = M1 @ M0.transposed()
    Rk = Matrix.Rotation(-thk, 3, "X")
    shin = H0r @ Rh @ Rk
    Ra = shin.inverted() @ Matrix(foot_rot)
    return {hip: Rh.to_quaternion(), knee: Rk.to_quaternion(), ankle: Ra.to_quaternion()}


class Performance:
    """Key poses -> per-frame joint quaternions, body path + orientation -> root transform,
    feet pinned by IK while grounded. Baked onto the rig every frame."""

    def __init__(self, rig):
        self.rig = rig
        self.keys = []           # (t, {bone: Quaternion}, loc)
        self.jitter = []         # (t0, t1, degrees, frequency)
        self.root_pos = []       # (t, Vector)
        self.root_rot = []       # (t, Quaternion)
        self.root_pos_fn = None
        self.root_rot_fn = None
        self.feet = None         # fn(t, Mroot) -> {side: (weight, ankle_world, foot_rot_world)}
        self.extra = []          # fn(t, q, loc) -> None, edits the pose in place (look-at, ...)

    def pose(self, t, pose, weight=1.0, blend=None):
        q, loc = pose_quats(P.blend_pose(blend if blend is not None else {}, pose, weight)
                            if (blend is not None or weight != 1.0) else pose)
        self.keys.append((t, q, loc))

    def sample_pose(self, t, lag=True):
        keys = sorted(self.keys, key=lambda k: k[0])
        out = {}
        for b in BONES:
            tb = t - (LAG[b] if lag else 0.0)
            out[b] = spline_quat([(k[0], k[1][b]) for k in keys], tb)
        loc = spline_vec([(k[0], k[2]) for k in keys], t)
        for t0, t1, amp, freq in self.jitter:
            if t0 <= t <= t1:
                env = smooth((t - t0) / 0.15) * smooth((t1 - t) / 0.15) * amp
                for i, b in enumerate(BONES):
                    k = 0.5 if b in ("Root", "Waist") else 1.0
                    e = Euler([math.radians(env * k * noise.noise(Vector((t * freq, i * 3.1, j * 7.7))))
                               for j in range(3)], "XYZ")
                    out[b] = out[b] @ e.to_quaternion()
        return out, loc

    def root_at(self, t):
        pos = self.root_pos_fn(t) if self.root_pos_fn else spline_vec(self.root_pos, t)
        rot = self.root_rot_fn(t) if self.root_rot_fn else spline_quat(self.root_rot, t)
        return pos, rot

    def evaluate(self, t):
        """(root pos, root rot, {bone: Quaternion}, root loc) at t, IK applied."""
        pos, rot = self.root_at(t)
        q, loc = self.sample_pose(t)
        for fn in self.extra:
            fn(t, q, loc)
        if self.feet is not None:
            Mroot = root_matrix(pos, rot)
            for side, (w, ankle_w, foot_w) in self.feet(t, Mroot, q, loc).items():
                if w <= 1e-4:
                    continue
                sol = solve_leg(q, loc, side, to_char(Mroot, ankle_w), rot_to_char(Mroot, foot_w))
                for b, qq in sol.items():
                    q[b] = qslerp(q[b], qq, w) if w < 1 else qq
        return pos, rot, q, loc

    def bake(self, frames):
        rig = self.rig
        rig.rotation_mode = "QUATERNION"
        pos_l, rot_l, eul = [], [], {b: [] for b in BONES}
        locs = []
        prev_rot = None
        prev_e = {b: Euler((0, 0, 0)) for b in BONES}
        for f in frames:
            pos, rot, q, loc = self.evaluate(T(f))
            if prev_rot is not None and prev_rot.dot(rot) < 0:
                rot = -rot
            prev_rot = rot
            pos_l.append(pos)
            rot_l.append(rot)
            locs.append(loc)
            for b in BONES:
                e = q[b].to_euler("XYZ", prev_e[b])
                prev_e[b] = e
                eul[b].append(e)
        bake_vec(rig, "location", frames, pos_l, interp="BEZIER")
        bake_vec(rig, "rotation_quaternion", frames, rot_l, interp="BEZIER")
        for b in BONES:
            pb = rig.pose.bones[b]
            pb.rotation_mode = "XYZ"
            bake_vec(rig, 'pose.bones["%s"].rotation_euler' % b, frames, eul[b], interp="BEZIER")
        bake_vec(rig, 'pose.bones["Root"].location', frames, locs, interp="BEZIER")
        _hold_before_cuts(rig)

    def world_matrices(self, t):
        """Blender world matrices {bone: 4x4 pose-bone world matrix} at t (no Blender evaluation):
        armature space = C^T-rest bones posed in Roblox joint axes."""
        pos, rot, q, loc = self.evaluate(t)
        Mroot = root_matrix(pos, rot)
        frames = fk_q(q, loc)
        out = {}
        CT = C3.transposed().to_4x4()
        for b in BONES:
            out[b] = Mroot @ CT @ frames[b] @ C3.to_4x4()
        return out, Mroot

    def grip_matrix(self, t):
        """World matrix of the held sword (rig.grip_world_matrix) computed from the performance."""
        mats, _ = self.world_matrices(t)
        return mats["RightWrist"] @ R.GRIP_OFFSET
