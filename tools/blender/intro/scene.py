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
    ax, ang = d.to_axis_angle()
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
    pw.inputs[1].default_value = 2.0
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.7
    face = nt.nodes.new("ShaderNodeMath")
    face.operation = "SUBTRACT"
    face.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], face.inputs[1])
    face2 = nt.nodes.new("ShaderNodeMath")
    face2.operation = "POWER"
    nt.links.new(face.outputs[0], face2.inputs[0])
    face2.inputs[1].default_value = 4.0
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
        tail_str.append(tl * (0.14 + 0.1 * min(g, 2) / 2))
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
PLANET_SCALE = 0.33
PLANET_SCREEN = (0.4, -0.36)     # where the planet sits in the frame at the end of the S2 swing (below the core)
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
    _PLANET["sun_dir"] = (right * 0.9 - back * 0.18 + up * 0.4).normalized()   # toward the sun: right, a bit behind
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
    """Black space until the stage switch, then the Sylverune sky: a gradient from a hazy horizon
    to a deep blue zenith with a warm glow around the sun (CONSTANT switch)."""
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
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    grad = nt.nodes.new("ShaderNodeValToRGB")
    cr = grad.color_ramp
    cr.interpolation = "B_SPLINE"
    cr.elements[0].position, cr.elements[0].color = 0.0, (*lin(SKY_HORIZON), 1)
    cr.elements[1].position, cr.elements[1].color = 0.55, (*lin(SKY_ZENITH), 1)
    e = cr.elements.new(0.12)
    e.color = (*lin(SKY_MID), 1)
    nt.links.new(sep.outputs["Z"], grad.inputs[0])
    sun = nt.nodes.new("ShaderNodeVectorMath")
    sun.operation = "DOT_PRODUCT"
    sun.inputs[1].default_value = sph(SUN_AZ, SUN_EL)
    nt.links.new(tc.outputs["Generated"], sun.inputs[0])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    mx = nt.nodes.new("ShaderNodeMath")
    mx.operation = "MAXIMUM"
    mx.inputs[1].default_value = 0.0
    nt.links.new(sun.outputs["Value"], mx.inputs[0])
    nt.links.new(mx.outputs[0], pw.inputs[0])
    pw.inputs[1].default_value = 6.0
    glow = nt.nodes.new("ShaderNodeMix")
    glow.data_type = "RGBA"
    glow.blend_type = "ADD"
    nt.links.new(pw.outputs[0], glow.inputs["Factor"])
    nt.links.new(grad.outputs[0], glow.inputs["A"])
    glow.inputs["B"].default_value = (*lin((120, 100, 60)), 1)
    bg = nt.nodes.new("ShaderNodeBackground")
    bg.inputs["Strength"].default_value = 1.0
    nt.links.new(glow.outputs["Result"], bg.inputs["Color"])
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.name = "stage"
    nt.links.new(black.outputs[0], mix.inputs[1])
    nt.links.new(bg.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    bake(nt, 'nodes["stage"].inputs[0].default_value', [1, F_SWITCH], [0.0, 1.0], interp="CONSTANT")
    ctx.world = w
    return w


SKY_HORIZON, SKY_MID, SKY_ZENITH = (200, 218, 234), (142, 182, 226), (58, 108, 186)
HAZE = (186, 206, 226)


def add_haze(mat, dist=1500.0, amount=0.62):
    """Aerial perspective for the preview: blend the surface toward the horizon haze with the
    distance from the camera."""
    nt = mat.node_tree
    if nt is None or nt.nodes.get("haze") is not None:
        return
    out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output), None)
    if out is None or not out.inputs[0].is_linked:
        return
    src = out.inputs[0].links[0].from_socket
    cd = nt.nodes.new("ShaderNodeCameraData")
    m1 = nt.nodes.new("ShaderNodeMath")
    m1.operation = "MULTIPLY"
    m1.inputs[1].default_value = -1.0 / dist
    nt.links.new(cd.outputs["View Distance"], m1.inputs[0])
    ex = nt.nodes.new("ShaderNodeMath")
    ex.operation = "EXPONENT"
    nt.links.new(m1.outputs[0], ex.inputs[0])
    fac = nt.nodes.new("ShaderNodeMath")
    fac.operation = "MULTIPLY_ADD"
    fac.inputs[1].default_value = -amount
    fac.inputs[2].default_value = amount
    nt.links.new(ex.outputs[0], fac.inputs[0])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*lin(HAZE), 1)
    mix = nt.nodes.new("ShaderNodeMixShader")
    mix.name = "haze"
    nt.links.new(fac.outputs[0], mix.inputs[0])
    nt.links.new(src, mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])


WORLD_SUN_ELEVATION = 38.0     # degrees (= SUN_EL)
WORLD_SUN_ROTATION = 15.0 - 90.0   # sky texture: sun azimuth = rotation + 90 deg (= SUN_AZ)


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
        for b in BONES:      # pose-bone matrix: bone-local axes = Roblox joint axes (rig.py)
            out[b] = Mroot @ CT @ frames[b]
        return out, Mroot

    def grip_matrix(self, t):
        """World matrix of the held sword (rig.grip_world_matrix) computed from the performance."""
        mats, _ = self.world_matrices(t)
        return mats["RightWrist"] @ R.GRIP_OFFSET

    def chest(self, t):
        pos, rot = self.root_at(t)
        return pos + rot @ CHEST


# ============================================================================ world stage: layout
# Blender world-stage coordinates: the landing point is the origin, ground z = 0, the character
# ends up facing +Y (the hub). The dive comes in along H and stops above the landing point; the
# fall column (and the sky rift above it) is DIVE_DH studs back along -H.
W_HEAD_YAW = 35.0                                   # deg: brake / landing heading (+Y turned left)
H = Vector((-math.sin(math.radians(W_HEAD_YAW)), math.cos(math.radians(W_HEAD_YAW)), 0.0))
SIDE = Vector((H.y, -H.x, 0.0))                     # to the right of H
HOVER = 4.0                                         # board top above the ground at the stop
STOP_XY = -H * 1.6                                  # board centre at the stop; the step off goes along H
DIVE_DH = 170.0
FALL_XY = STOP_XY - H * DIVE_DH
SKYRIFT_Z = 420.0
SKYRIFT_SCALE = 1.6
CHEST = Vector((0.0, 0.0, 0.8))                     # HRP -> chest (object space)
T_MORPH, T_FORM = 20.3, 21.0
T_SWORD = 21.6
T_GRAB, T_RELEASE, T_BOARD, T_SURF = 27.6, 31.0, 31.35, 31.6
T_BRAKE, T_STOP = 33.0, 35.0
T_STEP, T_JUMP, T_LAND, T_REGRAB = 38.05, 38.75, 39.2, 40.6
T_WIND = 35.1
YAW_W1 = -110.0                                     # faces the W1 camera (azimuth -20)
YAW_SURF = W_HEAD_YAW - 90.0                        # surf: the character's -X along H
BOARD_SPOT = 1.2                                    # feet on the board at +-1.2 along it
SUN_AZ, SUN_EL = 15.0, 38.0                         # world sun: azimuth from +X toward +Y, elevation
_W = {}                                             # world performance / board / sword state


def ramp(t, a, b):
    return smooth((t - a) / (b - a))


def yaw_q(deg):
    return Quaternion((0.0, 0.0, 1.0), math.radians(deg))


def body_q(yaw, rx=0.0, ry=0.0, rz=0.0):
    """Object rotation: yaw about Z on top of a poses.BODY-style XYZ Euler (degrees)."""
    return yaw_q(yaw) @ Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()


def sph(az, el):
    a, e = math.radians(az), math.radians(el)
    return Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))


def mat_from(rot, pos):
    M = rot.to_matrix().to_4x4() if isinstance(rot, Quaternion) else Matrix(rot).to_4x4()
    M.translation = pos
    return M


def blend_mat(A, B, u):
    """Interpolate two rigid 4x4 matrices (lerp translation, slerp rotation)."""
    qa, qb = A.to_quaternion(), B.to_quaternion()
    return mat_from(qslerp(qa, qb, u) if u < 1 else qb, A.translation.lerp(B.translation, u))


# ---------------------------------------------------------------------------- the core in the sky
CORE_W_V0, CORE_W_V1, CORE_W_TAU = 120.0, 12.0, 0.35


def core_world_free(t):
    """The core shooting out of the sky rift: fast, braking hard (studs below the rift)."""
    u = max(0.0, t - T_SWITCH)
    drop = CORE_W_V1 * u + (CORE_W_V0 - CORE_W_V1) * CORE_W_TAU * (1 - math.exp(-u / CORE_W_TAU))
    return Vector((FALL_XY.x, FALL_XY.y, SKYRIFT_Z - 1.0 - drop))


def core_world_pos(t):
    if t <= T_MORPH or "perf" not in _W:
        return core_world_free(t)
    return _W["perf"].chest(t)


# ---------------------------------------------------------------------------- fall + dive path
FALL_SPEED = [(21.0, 13.5), (23.0, 15.0), (25.0, 16.0), (27.6, 16.5), (28.0, 12.0), (28.9, 4.0), (29.3, 1.5),
              (29.9, 4.0), (30.6, 8.0), (31.3, 14.0), (31.6, 18.0), (32.0, 30.0)]


def _fall_table():
    dt = 1.0 / 120
    z = core_world_free(T_MORPH).z - CHEST.z
    v0 = CORE_W_V1 + (CORE_W_V0 - CORE_W_V1) * math.exp(-(T_MORPH - T_SWITCH) / CORE_W_TAU)
    sp = [(T_MORPH, v0)] + FALL_SPEED
    out, t = [], T_MORPH
    while t <= 32.0 + 1e-9:
        u = t - T_MORPH
        sway = SIDE * (0.7 * math.sin(0.8 * u)) + H * (0.5 * math.sin(0.55 * u + 0.4)) * smooth(u / 1.5)
        yank = SIDE * (1.4 * smooth((t - 27.6) / 0.5)) - H * (0.8 * smooth((t - 27.9) / 0.6))
        out.append(Vector((FALL_XY.x, FALL_XY.y, z)) + sway * smooth(u / 0.8) + yank)
        z -= piecewise(sp, t, ease=lambda x: x) * dt
        t += dt
    return out, dt


def fall_pos(t):
    if "fall" not in _W:
        _W["fall"] = _fall_table()
    tab, dt = _W["fall"]
    x = max(0.0, (t - T_MORPH) / dt)
    i = min(int(x), len(tab) - 2)
    return tab[i].lerp(tab[i + 1], x - i)


# root rotation while falling: (t, yaw, BODY rx, ry, rz)
FALL_ROT = [
    (20.3, YAW_W1, 0, 0, 0), (20.95, YAW_W1 + 2, -8, 0, 0), (21.5, -100, -62, 0, 10), (21.9, -95, -88, 0, -8),
    (22.3, -90, -84, 6, 12), (22.6, -86, -64, 0, 4), (22.95, -82, -32, 0, 0), (23.3, -79, 8, 0, -4),
    (23.7, -76, 25, 0, 0), (24.6, -72, 24, 0, 6), (25.0, -70, 18, 0, 0), (25.3, -74, 15, 0, -6),
    (25.6, -66, 10, 0, 8), (25.95, -76, 8, 0, -10), (26.3, -68, 12, 0, 6), (26.75, -72, 16, 0, -8),
    (27.05, -64, 10, 0, 10), (27.35, -66, 22, 0, 0), (27.6, -64, 20, 0, 0), (27.85, -58, 25, 0, -14),
    (28.2, -68, 10, 0, 18), (28.5, -60, 18, 0, -8), (28.8, -58, 0, 0, 0), (29.05, -56, -10, 0, 0),
    (29.5, -55, -6, 0, 0), (29.85, YAW_SURF, 0, 0, 0), (30.2, YAW_SURF - 6, 0, 0, 0), (30.5, YAW_SURF + 8, 0, 0, 0),
    (30.9, YAW_SURF + 3, 0, 0, 0), (31.35, YAW_SURF, 0, 0, 0)]

# the dive: board centre (t, fraction along the way, fraction of the drop) from T_SURF to T_STOP
DIVE = [(31.6, 0.0, 0.0), (32.0, 0.06, 0.088), (32.5, 0.33, 0.345), (33.0, 0.70, 0.73), (33.5, 0.885, 0.915),
        (34.0, 0.956, 0.973), (34.5, 0.991, 0.993), (35.0, 1.0, 1.0)]
BRAKE_LEAN = [(32.9, 0.0), (33.35, 16.0), (34.0, 22.0), (34.6, 16.0), (34.95, 2.0), (35.12, -6.0), (35.45, 0.0)]


def pose_feet(pose):
    """Blender object-space (x, y) of the feet of a POSE_SPECS pose ({side: Vector}) or {}."""
    spec = P.POSE_SPECS.get(pose, {}) if isinstance(pose, str) else {}
    return {side: Vector((x, -z)) for side, (x, z) in spec.get("feet", {}).items()}


def board_rel(pose, spots=None):
    """Root position in the board frame for a grounded pose: soles on the board top, the pose's
    feet over the board spots (one-footed poses use that foot only)."""
    feet = pose_feet(pose)
    spots = spots or {"Left": Vector((-BOARD_SPOT, 0.0)), "Right": Vector((BOARD_SPOT, 0.0))}
    if not feet:
        feet = {"Left": Vector((-0.52, 0.1)), "Right": Vector((0.52, 0.1))}
    d = sum((spots[s] - feet[s] for s in feet), Vector((0.0, 0.0))) / len(feet)
    return Vector((d.x, d.y, -R.FEET_Y))


# board phases: (t, pose name for the root offset) -> Rel(t) spline
BOARD_REL_KEYS = [(31.35, "mount_crouch"), (31.7, "surf_stance"), (33.0, "surf_stance"), (33.3, "brake_lean"),
                  (33.9, "brake_lean"), (34.3, "brake_strain"), (34.85, "brake_strain"), (35.05, "stop_impact"),
                  (35.5, "stop_impact"), (36.4, "mount_crouch"), (37.3, "stand"), (T_STEP, "stand"),
                  (38.3, "step_off"), (38.65, "step_off")]


def rel_at(t):
    if "rel" not in _W:
        _W["rel"] = [(k, board_rel(p)) for k, p in BOARD_REL_KEYS]
    return spline_vec(_W["rel"], t)


def _surf_rot(vel):
    """Board/body rotation while surfing: the character's -X along the travel, nose tilted down."""
    hz = Vector((vel.x, vel.y, 0.0))
    slope = math.atan2(-vel.z, max(hz.length, 1e-6))
    tilt = min(math.radians(30.0), 0.5 * max(0.0, slope) * clamp01(hz.length / 45.0))
    return Quaternion(Vector((0, 0, 1)).cross(H).normalized(), tilt) @ yaw_q(YAW_SURF)


def _brake_rot(t):
    lean = spline_num(BRAKE_LEAN, t)
    return Quaternion(SIDE, math.radians(lean)) @ yaw_q(W_HEAD_YAW)


def board_dive_keys():
    """(t, board centre) keys of the dive, continuous with the fall at T_SURF."""
    p0 = fall_pos(T_SURF) - _fall_rot(T_SURF) @ rel_at(T_SURF)
    p1 = Vector((STOP_XY.x, STOP_XY.y, HOVER))
    keys = []
    for t in (31.3, 31.45):       # before the dive: where the board would be under the falling feet
        keys.append((t, fall_pos(t) - _fall_rot(t) @ rel_at(t)))
    for t, fs, fz in DIVE:
        xy = p0.lerp(p1, fs)
        keys.append((t, Vector((xy.x, xy.y, lerp(p0.z, p1.z, fz)))))
    keys.append((35.4, p1))
    return keys


def _fall_rot(t):
    if "fall_rot" not in _W:
        _W["fall_rot"] = [(k[0], body_q(*k[1:])) for k in FALL_ROT]
    return spline_quat(_W["fall_rot"], t)


def board_dive_pos(t):
    if "dive" not in _W:
        _W["dive"] = board_dive_keys()
    return spline_vec(_W["dive"], t)


def board_frame(t):
    """World 4x4 of the board (origin = top centre between the feet spots, X along the board toward
    the right foot, Z up) for T_BOARD <= t < T_JUMP + (it then hovers on, see sword_matrix)."""
    if t < T_STOP:
        pos = board_dive_pos(t)
        vel = (board_dive_pos(t + 0.03) - board_dive_pos(t - 0.03)) / 0.06
        rs, rb = _surf_rot(vel), _brake_rot(t)
        w = ramp(t, T_BRAKE - 0.05, T_BRAKE + 0.4)
        if t < T_SURF:     # mounting: from the falling body's yaw to the surf
            rs = qslerp(_fall_rot(t), rs, ramp(t, T_BOARD, T_SURF))
        rot = qslerp(rs, rb, w) if w > 0 else rs
        return mat_from(rot, pos)
    bob = 0.1 * math.sin((t - T_STOP) * 2.2) * ramp(t, T_STOP + 0.3, T_STOP + 1.2)
    return mat_from(_brake_rot(t), Vector((STOP_XY.x, STOP_XY.y, HOVER + bob)))


# ground phase after the jump: root keys (t, pos, yaw)
def ground_keys():
    so = board_frame(38.7) @ rel_at(38.7)
    p_land = Vector((0.0, 0.0, -R.FEET_Y))
    keys = [(38.55, board_frame(38.55) @ rel_at(38.55)), (38.7, so)]
    # ballistic hop off the board: up a little, then down to the ground (g ~ 51 studs/s^2)
    t0, z0, vz, g = 38.78, so.z + 0.05, 1.0, 51.0
    for t in (38.85, 38.95, 39.05, 39.13):
        u = t - t0
        xy = so.lerp(p_land, ramp(t, 38.7, T_LAND) * 0.15 + 0.85 * clamp01((t - 38.7) / (T_LAND - 38.7)))
        keys.append((t, Vector((xy.x, xy.y, z0 + vz * u - 0.5 * g * u * u))))
    keys += [(T_LAND, p_land), (39.27, p_land + Vector((0, 0, -0.2))), (39.42, p_land + Vector((0, 0, -0.26))),
             (39.9, p_land), (40.3, p_land + Vector((0.08, 0.05, 0))), (40.6, p_land + Vector((0.1, 0.12, 0.02))),
             (41.0, p_land + Vector((0.05, 0.02, 0))), (41.7, p_land), (42.5, p_land)]
    return keys


GROUND_YAW = [(38.6, W_HEAD_YAW), (T_LAND, W_HEAD_YAW - 4), (40.0, W_HEAD_YAW - 6), (40.45, 2.0), (40.7, -1.0),
              (41.2, 0.0), (42.5, 0.0)]


def root_pos_world(t):
    if t < T_SURF:
        return fall_pos(t)
    if t < 38.6:
        B = board_frame(t)
        return B @ rel_at(t)
    if "ground" not in _W:
        _W["ground"] = ground_keys()
    return spline_vec(_W["ground"], t)


def root_rot_world(t):
    if t < T_BOARD:
        return _fall_rot(t)
    if t < 38.6:
        return board_frame(t).to_quaternion()
    q0 = board_frame(38.6).to_quaternion()
    keys = [(38.45, board_frame(38.45).to_quaternion()), (38.6, q0)] + [(k, yaw_q(y)) for k, y in GROUND_YAW[1:]]
    return spline_quat(keys, t)


# ---------------------------------------------------------------------------- the performance
# (t, pose, weight, blend)  weight/blend as poses.key_pose
POSE_KEYS = [
    (20.3, "resonance_brace", 1.0, None), (20.7, "resonance_burst", 0.55, "resonance_brace"),
    (20.95, "resonance_burst", 1.0, None), (21.45, "fall_spread", 0.75, "resonance_burst"),
    (21.9, "fall_spread", 1.0, None), (22.2, "fall_tumble_a", 0.3, "fall_spread"), (22.6, "look_around", 1.0, None),
    (22.9, "look_around", 0.8, "look_up_reach"), (23.35, "look_up_reach", 0.85, "fall_spread"),
    (23.7, "look_up_reach", 1.0, None), (24.6, "look_up_reach", 0.9, "reach_right"),
    (25.0, "reach_right", 0.7, "look_up_reach"), (25.28, "reach_right", 1.0, None), (25.6, "flail_a", 1.0, None),
    (25.95, "flail_b", 1.0, None), (26.3, "flail_a", 0.75, "reach_right"), (26.72, "reach_right", 1.0, None),
    (27.05, "flail_b", 0.9, None), (27.35, "look_up_reach", 1.0, None), (T_GRAB, "grab_blade", 1.0, None),
    (27.85, "struggle_a", 1.0, None), (28.2, "struggle_b", 1.0, None), (28.5, "struggle_a", 0.7, "resonance_brace"),
    (28.8, "resonance_brace", 1.0, None), (29.05, "resonance_burst", 1.0, None),
    (29.45, "resonance_burst", 0.85, "sword_ready"), (29.85, "sword_ready", 1.0, None), (30.12, "swing_wind", 1.0, None),
    (30.42, "swing_follow", 1.0, None), (30.75, "swing_follow", 0.9, "sword_ready"),
    (31.05, "mount_crouch", 0.55, "swing_follow"), (T_BOARD, "mount_crouch", 1.0, None),
    (31.7, "surf_stance", 1.0, None), (32.4, "surf_stance", 1.0, None), (T_BRAKE, "surf_stance", 1.0, None),
    (33.3, "brake_lean", 1.0, None), (33.9, "brake_lean", 1.0, None), (34.3, "brake_strain", 1.0, None),
    (34.85, "brake_strain", 1.0, None), (35.05, "stop_impact", 1.0, None), (35.5, "stop_impact", 1.0, None),
    (36.4, "mount_crouch", 1.0, None), (37.3, "stand", 1.0, None), (T_STEP, "stand", 1.0, None),
    (38.3, "step_off", 1.0, None), (38.65, "step_off", 1.0, None), (38.95, "land_crouch", 0.45, "stand"),
    (T_LAND, "land_crouch", 1.0, None), (39.45, "land_crouch", 1.0, None), (39.9, "stand", 1.0, None),
    (40.25, "reach_sword", 0.5, "stand"), (T_REGRAB, "reach_sword", 1.0, None), (41.05, "hold_sword_low", 1.0, None),
    (41.4, "hero", 0.65, "hold_sword_low"), (41.75, "hero", 1.0, None), (42.5, "hero", 1.0, None)]
JITTER = [(25.0, 27.55, 4.0, 3.0), (27.6, 28.55, 7.0, 5.0), (31.7, 33.0, 2.5, 6.0), (33.0, 35.0, 3.5, 7.0)]


def _foot_plants():
    """Ground plants after the landing: per side [(t_on, t_off, sole centre (world), yaw deg)];
    between two plants the foot steps (lifted arc)."""
    def at(yaw, local):
        return yaw_q(yaw) @ Vector((local.x, local.y, 0.0))
    land = {s: at(W_HEAD_YAW - 4, v) for s, v in pose_feet("land_crouch").items()}
    reach = pose_feet("reach_sword")
    hero = pose_feet("hero")
    return {
        "Right": [(T_LAND, 40.05, land["Right"], W_HEAD_YAW - 4), (40.33, 40.75, at(0, reach["Right"]), 0.0),
                  (41.02, 99.0, at(0, hero["Right"]), 0.0)],
        "Left": [(T_LAND, 40.2, land["Left"], W_HEAD_YAW - 4), (40.42, 41.12, at(0, reach["Left"]), -4.0),
                 (41.42, 99.0, at(0, hero["Left"]), 0.0)],
    }


def _sole_to_ankle(rot3, sole):
    return sole + rot3 @ Vector((0.0, -0.1, -(R.FEET_Y - (-2.85))))


def feet_targets(t, Mroot, q, loc):
    out = {}
    # on the board
    if T_BOARD < t < T_JUMP + 0.06:
        B = board_frame(t)
        w_in = ramp(t, 31.4, 31.56)
        wl = w_in * (1 - ramp(t, T_JUMP - 0.03, T_JUMP + 0.05))
        wr = w_in * (1 - ramp(t, T_STEP - 0.02, T_STEP + 0.12))
        rot3 = B.to_3x3()
        for side, w, x in (("Left", wl, -BOARD_SPOT), ("Right", wr, BOARD_SPOT)):
            if w > 1e-4:
                sole = B @ Vector((x, 0.0, 0.0))
                out[side] = (w, _sole_to_ankle(rot3, sole), rot3)
    # on the ground
    if t > T_LAND - 0.08:
        plants = _W.setdefault("plants", _foot_plants())
        w_in = ramp(t, T_LAND - 0.08, T_LAND)
        for side, lst in plants.items():
            sole, yaw = None, 0.0
            for k, (t_on, t_off, pos, yw) in enumerate(lst):
                if t_on <= t <= t_off or (k == 0 and t < t_on):
                    sole, yaw = pos, yw
                    break
                nxt = lst[k + 1] if k + 1 < len(lst) else None
                if nxt is not None and t_off < t < nxt[0]:
                    u = smooth((t - t_off) / (nxt[0] - t_off))
                    sole = pos.lerp(nxt[2], u) + Vector((0, 0, 0.35 * math.sin(math.pi * u)))
                    yaw = lerp(yw, nxt[3], u)
                    break
            if sole is None:
                continue
            rot3 = yaw_q(yaw).to_matrix()
            out[side] = (w_in, _sole_to_ankle(rot3, sole), rot3)
    return out


def build_performance(rig):
    perf = Performance(rig)
    for t, pose, w, blend in POSE_KEYS:
        perf.pose(t, pose, weight=w, blend=blend)
    perf.jitter = list(JITTER)
    perf.root_pos_fn = root_pos_world
    perf.root_rot_fn = root_rot_world
    perf.feet = feet_targets
    _W["perf"] = perf
    return perf


# ---------------------------------------------------------------------------- the sword
# sword object matrix in the board frame (poses.board_world_matrix convention: blade along the
# board toward the left foot, flat side up, grip centre under the right foot, top at the soles)
BOARD_LOCAL = Matrix(((0.0, 0.0, -1.0, BOARD_SPOT), (-1.0, 0.0, 0.0, 0.0), (0.0, 1.0, 0.0, -0.05), (0.0, 0.0, 0.0, 1.0)))
BLADE_TIP = 4.4


def fall_yaw(t):
    return spline_num([(k[0], k[1]) for k in FALL_ROT], t)


def _yaw_frame(t):
    return yaw_q(fall_yaw(t))


def _sword_keys(perf):
    """Positions (world) of the tumbling sword: out of the rift, catching up with the falling
    player, two near misses past the right hand, then into the hand at T_GRAB."""
    def chest_rel(t, v):
        return perf.chest(t) + _yaw_frame(t) @ Vector(v)

    def hand(t, v):
        mats, _ = perf.world_matrices(t)
        return mats["RightWrist"].translation + _yaw_frame(t) @ Vector(v)

    rift = Vector((SKYRIFT_POS.x, SKYRIFT_POS.y, SKYRIFT_POS.z - 1.5))
    c0 = perf.chest(T_SWORD)
    keys = [(T_SWORD - 0.3, rift + Vector((0, 0, 3.0))), (T_SWORD, rift)]
    for t, gap, side in ((22.1, None, 0.0), (22.7, 52.0, 0.3), (23.3, 31.0, 0.6), (23.9, 16.0, 1.0), (24.4, 8.5, 1.3),
                         (24.8, 5.0, 1.5)):
        c = perf.chest(t)
        if gap is None:   # still decelerating out of the rift, then accelerating after the player
            p = rift + Vector((0, 0, -4.5))
        else:
            p = c + _yaw_frame(t) @ Vector((side, 0.5, gap))
        keys.append((t, p))
    keys += [
        (25.1, hand(25.1, (0.5, 0.2, 1.7))),
        (25.32, hand(25.32, (1.0, -0.5, 0.5))),         # near miss 1: just past the fingertips
        (25.6, chest_rel(25.6, (2.6, -1.4, -0.4))),
        (25.95, chest_rel(25.95, (0.6, -2.7, -1.2))),
        (26.3, chest_rel(26.3, (-2.3, -1.0, 0.9))),
        (26.55, chest_rel(26.55, (-0.8, 0.8, 3.0))),
        (26.75, hand(26.75, (0.7, 0.6, 0.9))),           # near miss 2
        (27.0, chest_rel(27.0, (2.4, -0.2, 2.2))),
        (27.3, chest_rel(27.3, (1.6, -0.6, 2.4))),
        (T_GRAB, perf.grip_matrix(T_GRAB).translation),
        (T_GRAB + 0.1, perf.grip_matrix(T_GRAB + 0.1).translation),
    ]
    del c0
    return keys


def _tumble_rot(t):
    """Free tumbling: spin about a slowly wandering axis (rad), slowing down toward the grab."""
    spin = 8.5 * (t - T_SWORD) + 1.2 * math.sin(1.3 * (t - T_SWORD))
    ax = Vector((math.sin(0.7 * t + 0.3), 0.35 + 0.3 * math.cos(0.45 * t), math.cos(0.7 * t + 0.3))).normalized()
    return Quaternion(ax, spin) @ Euler((0.4, 0.0, 0.9), "XYZ").to_quaternion()


def sword_free_matrix(t):
    """World matrix of the sword whenever it is not held (bake input)."""
    perf = _W["perf"]
    if t < T_GRAB + 1e-6:
        keys = _W.setdefault("sword_keys", _sword_keys(perf))
        pos = spline_vec(keys, t)
        M = mat_from(_tumble_rot(t), pos)
        u = ramp(t, T_GRAB - 0.32, T_GRAB)
        if u > 0:
            M = blend_mat(M, perf.grip_matrix(t), u)
        return M
    if t < T_BOARD + 1e-6:     # released at T_RELEASE: flips flat under the feet
        u = smoother((t - T_RELEASE) / (T_BOARD - T_RELEASE))
        G = perf.grip_matrix(t)
        B = board_frame(t) @ BOARD_LOCAL
        return blend_mat(G, B, u)
    if t < 39.25:
        return board_frame(t) @ BOARD_LOCAL
    target = _W.setdefault("regrab", perf.grip_matrix(T_REGRAB))
    if t < 40.15:              # rises off the board, turns upright and floats to the hand
        u = smoother((t - 39.25) / 0.9)
        B = board_frame(t) @ BOARD_LOCAL
        M = blend_mat(B, target, u)
        lift = Vector((0, 0, 0.9 * math.sin(math.pi * u)))
        spin = Matrix.Rotation((1 - u) * math.tau * 0.5, 4, "Z")
        R3 = (spin @ M).to_3x3()
        return mat_from(R3.to_quaternion(), M.translation + lift)
    u = 1 - ramp(t, 40.15, T_REGRAB)
    bob = Vector((0, 0, 0.06 * math.sin((t - 40.15) * 9.0) * u))
    return mat_from(target.to_quaternion(), target.translation + bob)


def held_at(t):
    return 1.0 if (T_GRAB <= t < T_RELEASE) or t >= T_REGRAB else 0.0


SWORD_GLOW = [(21.6, 0.3), (27.6, 0.45), (28.0, 0.8), (28.9, 3.0), (29.15, 3.0), (29.6, 1.6), (30.1, 1.5), (30.4, 2.4),
              (30.9, 1.6), (31.6, 1.8), (33.0, 2.2), (34.9, 2.8), (35.05, 3.0), (35.6, 1.5), (38.0, 1.2), (40.6, 2.2),
              (41.2, 1.3), (42.5, 1.2)]


def build_sword(ctx, rig, frames):
    coll = ctx.colls["sword"]
    sword = new_empty("Sword", coll, 1.0)
    ctx.intro.place("ResonanceSword", coll, sword)
    sword.rotation_mode = "QUATERNION"
    con = R.add_grip_constraint(sword, rig)
    locs, rots, infl, held = [], [], [], []
    prev = None
    for f in frames:
        t = T(f)
        h = held_at(t)
        if h:
            loc, q = Vector(), Quaternion()
        else:
            M = sword_free_matrix(t)
            loc, q = M.translation, M.to_quaternion()
        if prev is not None and prev.dot(q) < 0:
            q = -q
        prev = q
        locs.append(loc)
        rots.append(q)
        infl.append(h)
        held.append(h)
    bake_vec(sword, "location", frames, locs, interp="BEZIER")
    bake_vec(sword, "rotation_quaternion", frames, rots, interp="BEZIER")
    # around the hold switches: CONSTANT keys so sub-frames never blend world and hand space
    sw = {f for k, f in enumerate(frames[1:], 1) if held[k] != held[k - 1]}
    for fc in _channelbag(sword).fcurves:
        for kp in fc.keyframe_points:
            f = int(round(kp.co.x))
            if f + 1 in sw:
                kp.interpolation = "CONSTANT"
            if f in sw or f + 1 in sw:
                kp.handle_left_type = kp.handle_right_type = "VECTOR"
        fc.update()
    con.influence = 0.0
    bake(sword, 'constraints["%s"].influence' % con.name, frames, infl, interp="CONSTANT")
    key_prop_frames(sword, "held", frames, held, interp="CONSTANT")
    key_prop(sword, "resonance", [(0.0, 0.0), (28.9, 0.0), (29.6, 1.0)], interp="BEZIER")
    key_prop(sword, "glow", SWORD_GLOW, interp="BEZIER")
    key_visible(sword, [(0.0, 0), (T_SWORD - 0.1, 1)])
    # preview materials follow the channels
    crys = bpy.data.materials.get("Intro_Crystal")
    if crys is not None:
        fs = list(range(F(T_SWORD - 0.2), FRAME_END + 1, 2))
        res = [piecewise([(28.9, 0.0), (29.6, 1.0)], T(f)) for f in fs]
        glw = [spline_num(SWORD_GLOW, T(f)) for f in fs]
        bake(crys.node_tree, 'nodes["resonance"].outputs[0].default_value', fs, res)
        bake(crys.node_tree, 'nodes["glow"].outputs[0].default_value', fs, glw)
    ctx.sword = sword
    return sword


# ---------------------------------------------------------------------------- blast / slash / shockwave
def _fx_material(name, rgb_lin, strength, rim=True):
    m = bpy.data.materials.new(name)
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    op = nt.nodes.new("ShaderNodeValue")
    op.name = op.label = "opacity"
    op.outputs[0].default_value = 1.0
    fac = op.outputs[0]
    if rim:
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.4
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        add = nt.nodes.new("ShaderNodeMath")
        add.operation = "MULTIPLY_ADD"
        nt.links.new(lw.outputs["Fresnel"], add.inputs[0])
        add.inputs[1].default_value = 0.6
        add.inputs[2].default_value = 0.4
        nt.links.new(add.outputs[0], mul.inputs[0])
        nt.links.new(op.outputs[0], mul.inputs[1])
        fac = mul.outputs[0]
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*rgb_lin, 1)
    em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(fac, mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def build_blast(ctx, perf):
    coll = ctx.colls["fx"]
    blast = new_empty("Blast", coll, 1.0, display="SPHERE")
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=40, v_segments=20, radius=1.0)
    hot = tuple(lerp(c, 1.0, 0.35) for c in CORE_LIN)
    mat = _fx_material("Preview_Blast", hot, 4.0)
    sph_o = mesh_object("BlastSphere", bm, coll, [mat], parent=blast, smooth=True)
    sph_o.visible_shadow = False
    t0, t1 = 28.9, 29.45
    frames = list(range(F(t0) - 1, F(t1) + 2))
    pos, sc, opa = [], [], []
    for f in frames:
        t = T(f)
        u = clamp01((t - t0) / (t1 - t0))
        pos.append(perf.chest(min(max(t, t0), t1)))
        r = 0.6 + 25.0 * (1 - (1 - u) ** 3)
        sc.append((r, r, r))
        opa.append(1 - u ** 1.8 if t >= t0 else 1.0)
    bake_vec(blast, "location", frames, pos)
    bake_vec(blast, "scale", frames, sc)
    key_prop_frames(blast, "opacity", frames, opa)
    bake(mat.node_tree, 'nodes["opacity"].outputs[0].default_value', frames, opa)
    key_visible(blast, [(0.0, 0), (t0, 1), (t1 + 0.04, 0)])
    return blast


def build_slash(ctx, perf):
    coll = ctx.colls["fx"]
    arc = new_empty("SlashArc", coll, 1.0)
    ctx.intro.place("SlashArc", coll, arc)
    arc.rotation_mode = "QUATERNION"
    ta, tb = 30.14, 30.44

    def tip(t):
        return perf.grip_matrix(t) @ Vector((0, 0, BLADE_TIP))
    mats, _ = perf.world_matrices(0.5 * (ta + tb))
    c = mats["RightShoulder"].translation
    a, b = tip(ta) - c, tip(tb) - c
    n = a.cross(b).normalized()
    eb = (b - n * b.dot(n)).normalized()
    x = Quaternion(n, math.radians(-25.0)) @ eb
    y = n.cross(x)
    rot = Matrix((x, y, n)).transposed().to_quaternion()
    s = 0.5 * (a.length + b.length) / 5.0
    arc.location = c
    arc.rotation_quaternion = rot
    arc.scale = (s, s, s)
    keys = [(0.0, 0.0), (30.18, 0.0), (30.3, 1.0), (30.46, 0.85), (30.8, 0.0)]
    key_prop(arc, "opacity", keys, interp="BEZIER")
    m = bpy.data.materials.get("Intro_Arc")
    if m is not None:
        fs = list(range(F(30.1), F(30.9) + 1))
        bake(m.node_tree, 'nodes["opacity"].outputs[0].default_value', fs, [piecewise(keys, T(f)) for f in fs])
    key_visible(arc, [(0.0, 0), (30.18, 1), (30.82, 0)])
    return arc


def shock_radius(t):
    return 0.5 + 7.5 * ramp(t, T_STOP, T_WIND) + 160.0 * max(0.0, t - T_WIND)


def build_shockwave(ctx):
    coll = ctx.colls["fx"]
    sw = new_empty("Shockwave", coll, 1.0, display="CIRCLE")
    ctx.intro.place("Shockwave", coll, sw)
    sw.location = (STOP_XY.x, STOP_XY.y, 0.25)
    t1 = 37.3
    frames = list(range(F(T_STOP) - 1, F(t1) + 2))
    sc = [shock_radius(T(f)) for f in frames]
    opa = [1.0 - smooth((T(f) - 36.0) / (t1 - 36.0)) for f in frames]
    bake_vec(sw, "scale", frames, [(s, s, s) for s in sc])
    key_prop_frames(sw, "opacity", frames, opa)
    m = bpy.data.materials.get("Intro_Wave")
    if m is not None:
        bake(m.node_tree, 'nodes["opacity"].outputs[0].default_value', frames, opa)
    key_visible(sw, [(0.0, 0), (T_STOP, 1), (t1, 0)])
    return sw


def _wake_material(life):
    """Ribbon whose vertices carry the time they were laid (UV x): shown for `life` seconds after
    that, fading, against the keyed `now` value (preview of the runtime's glowing wake)."""
    m = bpy.data.materials.new("Preview_Wake")
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    uv = nt.nodes.new("ShaderNodeUVMap")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(uv.outputs[0], sep.inputs[0])
    now = nt.nodes.new("ShaderNodeValue")
    now.name = now.label = "now"
    age = nt.nodes.new("ShaderNodeMath")
    age.operation = "SUBTRACT"
    nt.links.new(now.outputs[0], age.inputs[0])
    nt.links.new(sep.outputs["X"], age.inputs[1])
    fade = nt.nodes.new("ShaderNodeMapRange")
    fade.inputs["From Min"].default_value = 0.0
    fade.inputs["From Max"].default_value = life
    fade.inputs["To Min"].default_value = 1.0
    fade.inputs["To Max"].default_value = 0.0
    nt.links.new(age.outputs[0], fade.inputs["Value"])
    born = nt.nodes.new("ShaderNodeMath")
    born.operation = "GREATER_THAN"
    born.inputs[1].default_value = -0.001
    nt.links.new(age.outputs[0], born.inputs[0])
    edge = nt.nodes.new("ShaderNodeMath")       # soft edges across the ribbon (UV y 0..1)
    edge.operation = "PINGPONG"
    edge.inputs[1].default_value = 0.5
    nt.links.new(sep.outputs["Y"], edge.inputs[0])
    edge2 = nt.nodes.new("ShaderNodeMath")
    edge2.operation = "MULTIPLY"
    edge2.inputs[1].default_value = 2.0
    nt.links.new(edge.outputs[0], edge2.inputs[0])
    a = nt.nodes.new("ShaderNodeMath")
    a.operation = "MULTIPLY"
    nt.links.new(fade.outputs[0], a.inputs[0])
    nt.links.new(born.outputs[0], a.inputs[1])
    a2 = nt.nodes.new("ShaderNodeMath")
    a2.operation = "MULTIPLY"
    nt.links.new(a.outputs[0], a2.inputs[0])
    nt.links.new(edge2.outputs[0], a2.inputs[1])
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*CORE_LIN, 1)
    em.inputs["Strength"].default_value = 1.6
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(a2.outputs[0], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def build_wake(ctx, t0=T_SURF + 0.05, t1=T_STOP, life=0.3, width=0.3):
    """Preview only: the glowing wake behind the sword-board while surfing and braking."""
    coll = ctx.colls["fx"]
    bm = bmesh.new()
    uvl = bm.loops.layers.uv.new("UVMap")
    rows = []
    n = int((t1 - t0) * 120)
    for k in range(n + 1):
        t = lerp(t0, t1, k / n)
        B = board_frame(t)
        c = B @ Vector((0.0, 0.0, -0.12))
        x = B.to_3x3() @ Vector((1.0, 0.0, 0.0))
        w = width * (0.6 + 0.4 * ramp(t, T_BRAKE, T_BRAKE + 0.3))
        rows.append((t, bm.verts.new(c - x * w * 1.6), bm.verts.new(c + x * w * 1.6)))
    for (ta, a0, a1), (tb, b0, b1) in zip(rows, rows[1:]):
        f = bm.faces.new((a0, a1, b1, b0))
        for loop, (u, v) in zip(f.loops, ((ta, 0.0), (ta, 1.0), (tb, 1.0), (tb, 0.0))):
            loop[uvl].uv = (u, v)
    mat = _wake_material(life)
    wake = mesh_object("PreviewWake", bm, coll, [mat])
    wake.visible_shadow = False
    frames = list(range(F(t0) - 1, F(t1 + life) + 2))
    bake(mat.node_tree, 'nodes["now"].outputs[0].default_value', frames, [T(f) for f in frames])
    key_hide([wake], [(1, True), (F(t0) - 1, False), (F(t1 + life) + 1, True)])
    return wake


# ---------------------------------------------------------------------------- sky rift
SKYRIFT_POS = Vector((FALL_XY.x, FALL_XY.y, SKYRIFT_Z))


def build_sky_rift(ctx):
    coll = ctx.colls["world"]
    rift = build_rift(ctx, "SkyRift", coll, far_side=True)
    obj = rift["obj"]
    obj.location = SKYRIFT_POS
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Quaternion((1, 0, 0), math.pi) @ Quaternion((0, 0, 1), 0.6)
    obj.scale = (SKYRIFT_SCALE,) * 3
    key_prop(obj, "crack", [(0.0, 1.0)], interp="CONSTANT")
    key_prop(obj, "open", [(0.0, 1.0)], interp="CONSTANT")
    frames = [F_SWITCH - 1, F_SWITCH, F(29.0)]
    bake_rift(rift, frames, lambda t: 1.0, lambda t: 1.0)
    key_visible(obj, [(0.0, 0), (T_SWITCH, 1), (29.0, 0)])
    bake_rift(rift, frames, lambda t: 1.0, lambda t: 1.0)
    for o in [obj] + list(obj.children_recursive):
        fc = fcurve(o, "hide_render")
        pts = {int(round(k.co.x)): k.co.y for k in fc.keyframe_points}
        pts[1] = 1.0
        pts[F(29.0)] = 1.0
        pts[F_SWITCH - 1] = 1.0
        fs = sorted(pts)
        bake(o, "hide_render", fs, [pts[f] for f in fs], interp="CONSTANT")
    ctx.sky_rift = rift
    return rift


# ---------------------------------------------------------------------------- character look
def character_form_materials(rig, frames, form_fn):
    """Preview of `form`: the mannequin is a figure of light (core colour, see-through) at 0."""
    mats = {m for o in rig.children for m in (o.data.materials if o.data else []) if m}
    for m in mats:
        nt = m.node_tree
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        bsdf = out.inputs[0].links[0].from_node
        val = nt.nodes.new("ShaderNodeValue")
        val.name = val.label = "form"
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (*[lerp(c, 1.0, 0.3) for c in CORE_LIN], 1)
        em.inputs["Strength"].default_value = 6.0
        tr = nt.nodes.new("ShaderNodeBsdfTransparent")
        glowmix = nt.nodes.new("ShaderNodeMixShader")
        glowmix.inputs[0].default_value = 0.7
        nt.links.new(tr.outputs[0], glowmix.inputs[1])
        nt.links.new(em.outputs[0], glowmix.inputs[2])
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(val.outputs[0], mix.inputs[0])
        nt.links.new(glowmix.outputs[0], mix.inputs[1])
        nt.links.new(bsdf.outputs[0], mix.inputs[2])
        nt.links.new(mix.outputs[0], out.inputs[0])
        bake(nt, 'nodes["form"].outputs[0].default_value', frames, [form_fn(T(f)) for f in frames])


def form_at(t):
    return smooth((t - T_MORPH) / (T_FORM - T_MORPH)) ** 1.5


# ---------------------------------------------------------------------------- preview environment
TREE_TYPES = (("Broadleaf_A", 0.2), ("Broadleaf_B", 0.2), ("Broadleaf_C", 0.18), ("Blossom_A", 0.12),
              ("Blossom_B", 0.12), ("SilverTree", 0.18))
N_TREES = 120
TREE_R = (30.0, 380.0)
CLEARING_R = 64.0           # from the circle centre (the map keeps the forest ~90 studs away)


def wind_angle(d, t, t_wind=T_WIND):
    """DESIGN §7.3: bend angle (radians, + = away from the landing point) of a tree at distance d."""
    tau = t - t_wind - d / WIND_SPEED
    if tau < 0:
        return 0.0
    f = (1 - math.exp(-tau / 0.12)) * math.exp(-tau / 1.1) * math.cos(2 * math.pi * tau / 1.6)
    return 0.42 * min(1.0, max(0.15, 1 - d / 340.0)) * f


def _grass_material():
    m = bpy.data.materials.new("Preview_Grass")
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    nz = nt.nodes.new("ShaderNodeTexNoise")
    nz.inputs["Scale"].default_value = 0.012
    nz.inputs["Detail"].default_value = 6.0
    nt.links.new(tc.outputs["Object"], nz.inputs["Vector"])
    ramp_n = nt.nodes.new("ShaderNodeValToRGB")
    ramp_n.color_ramp.elements[0].color = (*lin((62, 104, 46)), 1)
    ramp_n.color_ramp.elements[1].color = (*lin((104, 140, 62)), 1)
    ramp_n.color_ramp.elements[0].position = 0.35
    ramp_n.color_ramp.elements[1].position = 0.68
    nt.links.new(nz.outputs["Fac"], ramp_n.inputs[0])
    nt.links.new(ramp_n.outputs[0], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    m.diffuse_color = (*lin((80, 120, 55)), 1)
    return m


def _box(bm, M, size):
    bmesh.ops.create_cube(bm, size=1.0, matrix=M @ Matrix.Diagonal((*size, 1.0)))


def build_ground(ctx, coll):
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, segments=96, radius=2600.0)
    ground = mesh_object("PreviewGround", bm, coll, [_grass_material()])
    ground.location = (0, 0, -0.02)
    # spawn circle (the map's WildwoodArrival): cobble disc, moss disc, rune ring, 12 standing stones,
    # the floating crystal (DESIGN §7.1: the landing point is 14 studs from its centre toward the hub)
    stone = bsdf_material("Preview_Stone", (128, 132, 126), rough=0.85)
    moss = bsdf_material("Preview_Moss", (78, 118, 60), rough=0.95)
    rune = emission_material("Preview_Rune", lin((120, 255, 190)), 3.0)
    crystal = emission_material("Preview_Crystal", lin((140, 255, 210)), 4.0)
    c = Vector((CIRCLE_CENTER.x, CIRCLE_CENTER.y, 0.0))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=34, radius2=34, depth=0.3,
                          matrix=Matrix.Translation(c + Vector((0, 0, -0.1))))
    mesh_object("PreviewCircleStone", bm, coll, [stone])
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, segments=64, radius1=26, radius2=26, depth=0.3,
                          matrix=Matrix.Translation(c + Vector((0, 0, -0.08))))
    mesh_object("PreviewCircleMoss", bm, coll, [moss])
    rng = random.Random(77)
    bs, bmm, br = bmesh.new(), bmesh.new(), bmesh.new()
    for k in range(24):
        a0, a1 = k / 24 * math.tau, (k + 0.6) / 24 * math.tau
        p0 = c + Vector((math.cos(a0), math.sin(a0), 0)) * 26
        p1 = c + Vector((math.cos(a1), math.sin(a1), 0)) * 26
        d = p1 - p0
        M = Matrix.Translation((p0 + p1) / 2 + Vector((0, 0, 0.12))) @ Matrix.Rotation(math.atan2(d.y, d.x), 4, "Z")
        _box(br, M, (d.length, 1.0, 0.3))
    for k in range(12):
        a = k / 12 * math.tau + 0.13
        p = c + Vector((math.cos(a), math.sin(a), 0)) * 40
        h = rng.uniform(12, 20)
        yaw = math.atan2((c - p).y, (c - p).x) - math.pi / 2
        M = Matrix.Translation(p) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(rng.uniform(-0.06, 0.06), 4, "X")
        _box(bs, M @ Matrix.Translation((0, 0, h / 2 - 1)), (6, 3.5, h + 2))
        _box(bmm, M @ Matrix.Translation((0, 0, h + 0.6)), (6.4, 3.9, 1.0))
        _box(br, M @ Matrix.Translation((0, 1.86, h / 2 + 1)), (0.7, 0.2, h * 0.5))
    mesh_object("PreviewStones", bs, coll, [stone])
    mesh_object("PreviewStoneMoss", bmm, coll, [moss])
    mesh_object("PreviewRunes", br, coll, [rune])
    bm = bmesh.new()
    _box(bm, Matrix.Translation(c + Vector((0, 0, 22))) @ Euler((math.pi / 4, 0, math.pi / 4)).to_matrix().to_4x4(), (4, 4, 4))
    cr = mesh_object("PreviewCircleCrystal", bm, coll, [crystal])
    cr.visible_shadow = False
    return [o for o in coll.objects]


def _dive_clear(p, top):
    """True if a tree of height `top` at p stays well below the dive path."""
    for k in range(60):
        t = lerp(T_SURF, T_STOP, k / 59)
        b = board_dive_pos(t)
        if (Vector((b.x, b.y)) - Vector((p.x, p.y))).length < 16 and b.z - 9 < top:
            return False
    return True


def build_forest(ctx, coll):
    lib = AssetLib(ISLAND_ASSETS, names=[n for n, _ in TREE_TYPES])
    heights = {}
    for name, objs in lib.pieces.items():
        heights[name] = max((o.matrix_world @ Vector(c)).z for o in objs for c in o.bound_box)
    rng = random.Random(4242)
    trees = []
    wsum = sum(w for _, w in TREE_TYPES)
    tries = 0
    c = Vector((CIRCLE_CENTER.x, CIRCLE_CENTER.y))
    while len(trees) < N_TREES and tries < 20000:
        tries += 1
        r = math.sqrt(rng.uniform(TREE_R[0] ** 2, TREE_R[1] ** 2))
        a = rng.uniform(0, math.tau)
        p = Vector((math.cos(a) * r, math.sin(a) * r))
        if (p - c).length < CLEARING_R:
            continue
        if any((p - q).length < 30 for q, *_ in trees):
            continue
        x = rng.uniform(0, wsum)
        for name, w in TREE_TYPES:
            x -= w
            if x <= 0:
                break
        s = rng.uniform(0.8, 1.35)
        if not _dive_clear(p, heights[name] * s):
            continue
        trees.append((p, name, s, rng.uniform(0, math.tau)))
    roots = []
    f0 = F(T_WIND) - 1
    for k, (p, name, s, yaw) in enumerate(trees):
        root = new_empty("Tree_%03d" % k, coll, 2.0)
        root.location = (p.x, p.y, 0.0)
        root.rotation_mode = "AXIS_ANGLE"
        d = p.length
        u = p.normalized()
        axis = Vector((0, 0, 1)).cross(Vector((u.x, u.y, 0)))
        root.rotation_axis_angle = (0.0, axis.x, axis.y, axis.z)
        holder = new_empty("Tree_%03d_Mesh" % k, coll, 1.0, parent=root)
        holder.rotation_euler = (0, 0, yaw)
        holder.scale = (s, s, s)
        for o in lib.place(name, coll, holder).values():
            o.visible_shadow = True
        t_on = T_WIND + d / WIND_SPEED
        fa, fb = max(f0, F(t_on) - 1), F(t_on + WIND_SETTLE) + 1
        frames = [1] + list(range(fa, fb + 1))
        bake(root, "rotation_axis_angle", frames, [wind_angle(d, T(f)) for f in frames], index=0)
        root["wind_distance"] = d
        roots.append(root)
    # the original (marker-free, origin-centred) pieces are templates only
    for objs in lib.pieces.values():
        for o in objs:
            for cl in list(o.users_collection):
                cl.objects.unlink(o)
    ctx.trees = roots
    return roots


def build_world_lights(ctx, coll):
    sun = bpy.data.objects.new("WorldSun", bpy.data.lights.new("WorldSun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(2.0)
    sun.data.color = (1.0, 0.95, 0.86)
    d = sph(SUN_AZ, SUN_EL)
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = Vector((0, 0, -1)).rotation_difference(-d)
    coll.objects.link(sun)
    return sun


# ---------------------------------------------------------------------------- world cameras
# (t, azimuth, elevation, distance) of the camera around the subject; framing (t, sx, sy);
# lens as vertical FOV (t, deg); roll (t, deg). Azimuth: degrees from +X toward +Y (world).
W1_ORBIT = [(20.2, -20, -25, 20), (20.9, -16, -8, 18), (21.6, 5, 22, 15.0), (22.2, 45, 26, 13.5), (22.7, 80, 16, 13.0),
            (23.0, 92, 12, 12.5)]
W1_FRAME = [(18.6, 0.0, 0.3), (19.4, 0.0, 0.1), (20.3, 0.0, 0.0), (21.5, 0.08, -0.05), (22.5, 0.12, 0.0), (23.0, 0.12, 0.0)]
W1_FOV = [(18.6, 62), (19.6, 52), (20.3, 44), (21.0, 40), (23.0, 38)]
W1_ROLL = [(18.6, -4), (20.3, 0), (22.0, 3), (23.0, 2)]

W2_ORBIT = [(23.0, 10, -46, 11.5), (24.3, 20, -42, 11.0), (24.8, 28, -30, 10.5), (25.3, 35, -15, 11.0), (26.5, 45, -8, 11.0)]
W2_FRAME = [(23.0, 0.0, -0.16), (24.4, 0.0, -0.14), (25.0, -0.05, -0.06), (25.4, -0.1, 0.0), (26.5, -0.1, 0.0)]
W2_FOV = [(23.0, 72), (24.4, 68), (25.0, 56), (25.4, 50), (26.5, 48)]
W2_ROLL = [(23.0, 6), (24.5, 3), (25.4, -2), (26.5, 2)]

# the long shot 26.5-35.1: grab, impact, blast, swing, chase, whip round to the front for the brake
W3_KEYS = [  # t, az, el, dist, sx, sy, vfov, roll
    (26.5, 75, 6, 11.0, -0.12, 0.02, 48, -2), (27.2, 66, 7, 10.5, -0.08, -0.02, 46, 1), (27.6, 60, 8, 12.0, -0.04, -0.12, 46, 0),
    (28.0, 58, 8, 9.5, 0.0, -0.08, 42, 0), (28.9, 58, 8, 9.5, 0.0, -0.08, 42, 0), (29.2, 64, 13, 17.0, 0.0, 0.04, 56, 6),
    (29.6, 70, 8, 15.0, 0.0, 0.0, 50, 1), (30.4, 78, 5, 13.0, 0.05, 0.0, 46, 0), (31.0, 75, 6, 12.0, 0.0, 0.0, 46, 0),
    (31.5, 25, 14, 11.0, 0.0, 0.02, 54, 0), (31.9, 2, 22, 9.5, 0.12, 0.0, 62, -3), (32.5, -8, 24, 9.0, 0.15, -0.02, 70, -5),
    (33.0, -5, 18, 9.5, 0.1, -0.02, 68, -2), (33.35, 50, 4, 12.0, 0.0, 0.04, 60, 0), (33.7, 112, -7, 15.0, 0.0, 0.1, 52, 2),
    (34.4, 122, -10, 14.0, 0.0, 0.15, 48, 0), (35.0, 125, -12, 12.5, 0.0, 0.15, 46, 0), (35.04, 125, -12, 12.0, 0.0, 0.15, 54, 0)]

W7_KEYS = [(35.1, -36, 248, 125, 31), (38.0, -31, 240, 118, 27)]   # t, az, distance, height, vfov

W8_KEYS = [  # t, az, el, dist, sx, sy, vfov, roll
    (38.0, 160, 6, 13.0, 0.12, 0.1, 42, 0), (38.7, 156, 6, 12.5, 0.1, 0.1, 42, 0), (39.2, 150, 8, 12.0, 0.08, 0.08, 42, 0),
    (40.0, 140, 8, 11.0, 0.04, 0.06, 42, 0), (T_REGRAB, 135, 9, 10.5, 0.0, 0.05, 42, 0), (41.3, 150, 11, 11.0, 0.0, 0.04, 46, 0),
    (42.0, 185, 13, 13.0, 0.0, 0.0, 56, 0), (42.5, 205, 14, 14.0, 0.0, -0.02, 62, 0)]


def _col(keys, i):
    return [(k[0], k[i]) for k in keys]


def _cam(eye, subject, sx, sy, roll_deg, vfov):
    q = frame_subject(eye, subject, vfov, sx, sy, math.radians(roll_deg))
    return eye, q, lens_of_fov(vfov)


def world_cam(t, perf, subj=None):
    """(eye, rotation, lens) of the world shots W1-W8 at t."""
    if t < 23.0:                      # W1 + W2: below the rift, track the core, orbit the falling player
        subject = core_world_pos(t) if subj is None else subj
        fixed = Vector((FALL_XY.x, FALL_XY.y, 0)) + sph(-20, 0) * 18 + Vector((0, 0, 356.0 - 4.0 * (t - T_SWITCH)))
        az, el, dist = (spline_num(_col(W1_ORBIT, i), t) for i in (1, 2, 3))
        orbit = subject + sph(az, el) * dist
        eye = fixed.lerp(orbit, ramp(t, 20.2, 21.4))
        sx, sy = spline_num(_col(W1_FRAME, 1), t), spline_num(_col(W1_FRAME, 2), t)
        return _cam(eye, subject, sx, sy, spline_num(W1_ROLL, t), spline_num(W1_FOV, t))
    if t < 26.5:                      # W2b / W3: worm's eye up at player + sword + rift, then in close
        subject = perf.chest(t) if subj is None else subj
        az, el, dist = (spline_num(_col(W2_ORBIT, i), t) for i in (1, 2, 3))
        drift = Vector((0.25 * math.sin(1.3 * t), 0.2 * math.sin(1.7 * t + 1), 0.15 * math.sin(1.1 * t + 2))) * ramp(t, 24.6, 25.2)
        eye = subject + sph(az, el) * dist + drift
        sx, sy = spline_num(_col(W2_FRAME, 1), t), spline_num(_col(W2_FRAME, 2), t)
        return _cam(eye, subject, sx, sy, spline_num(W2_ROLL, t), spline_num(W2_FOV, t))
    if t < 35.1:                      # the long shot
        subject = perf.chest(t) if subj is None else subj
        vals = [spline_num(_col(W3_KEYS, i), t) for i in range(1, 8)]
        az, el, dist, sx, sy, fov, roll = vals
        drift = Vector((0.18 * math.sin(1.1 * t), 0.15 * math.sin(1.5 * t + 1), 0.12 * math.sin(0.9 * t + 2)))
        drift *= (1 - ramp(t, 27.9, 28.0)) + ramp(t, 29.6, 30.2) * (1 - ramp(t, 31.0, 31.4))
        eye = subject + sph(az, el) * dist + drift
        if t > 33.5:                  # front low: never below 2.2 studs above the ground
            eye.z = max(eye.z, 2.2)
        return _cam(eye, subject, sx, sy, roll, fov)
    if t < 38.0:                      # W7: far wide, elevated
        az, dist, h, fov = (spline_num(_col(W7_KEYS, i), t) for i in (1, 2, 3, 4))
        target = Vector((STOP_XY.x, STOP_XY.y, 8.0))
        eye = Vector((STOP_XY.x, STOP_XY.y, 0)) + sph(az, 0) * dist + Vector((0, 0, h))
        return _cam(eye, target, 0.0, -0.08, 0.0, fov)
    subject = perf.chest(t) if subj is None else subj
    subject = subject + Vector((0, 0, 0.6 * ramp(t, 41.0, 42.5)))
    vals = [spline_num(_col(W8_KEYS, i), t) for i in range(1, 8)]
    az, el, dist, sx, sy, fov, roll = vals
    eye = subject + sph(az, el) * dist
    eye.z = max(eye.z, 2.5)
    return _cam(eye, subject, sx, sy, roll, fov)


def world_camera(ctx, perf):
    frames = list(range(F_SWITCH, FRAME_END + 1))
    # damped subject per shot (no interpolation across cuts): soft, weighty follow
    raw = {f: (core_world_pos(T(f)) if T(f) < 21.0 else perf.chest(T(f))) for f in frames}
    taus = {0: 0.0, 1: 0.03, 2: 0.0, 3: 0.0, 4: 0.1}
    bounds = [F_SWITCH, F(23.0), F(26.5), F(35.1), F(38.0), FRAME_END + 1]
    subj = {}
    for s in range(5):
        fs = [f for f in frames if bounds[s] <= f < bounds[s + 1]]
        if not fs:
            continue
        damped = damp_path([raw[f] for f in fs], taus[s])
        subj.update(zip(fs, damped))
    for f in frames:
        t = T(f)
        s = subj[f]
        if t < 21.0:
            s = raw[f]
        eye, q, lns = world_cam(t, perf, subj=s)
        ctx.camtrack.put(f, eye, q, lns)


# ---------------------------------------------------------------------------- world build
def build_world(ctx):
    rig = R.build_rig(ctx.colls["character"], "CharacterRig")
    ctx.rig = rig
    perf = build_performance(rig)
    frames = list(range(F(T_MORPH) - 1, FRAME_END + 1))
    perf.bake(frames)
    key_prop_frames(rig, "form", frames, [form_at(T(f)) for f in frames])
    key_visible(rig, [(0.0, 0), (T_MORPH, 1)])
    character_form_materials(rig, list(range(F(T_MORPH) - 1, F(T_FORM) + 2)), form_at)
    build_sword(ctx, rig, list(range(F(T_SWORD) - 4, FRAME_END + 1)))
    build_blast(ctx, perf)
    build_slash(ctx, perf)
    build_shockwave(ctx)
    build_wake(ctx)
    build_sky_rift(ctx)
    env = ctx.colls["env"]
    build_ground(ctx, env)
    build_forest(ctx, ctx.colls["trees"])
    sun = build_world_lights(ctx, env)
    for m in {m for o in list(env.objects) + list(ctx.colls["trees"].objects) if o.type == "MESH" for m in o.data.materials if m}:
        add_haze(m)
    stage_only(list(env.objects) + list(ctx.colls["trees"].objects), "world")
    world_camera(ctx, perf)
    ctx.perf = perf
    return perf
