"""
Bakes the Blender cutscene scene into src/IntroCutscene/IntroData.luau (docs/intro/DESIGN.md §8)
and writes the parity fixture tools/tests/intro_parity.luau (§9).

API (used by scene.py / build_intro.py)
---------------------------------------
    import export_intro
    report = export_intro.export(scene, out_path, parity_path=None, rate=30, fixture_samples=200,
                                 seed=1, budget_kb=700, verbose=True)
        Bakes `scene` (normally bpy.context.scene) and writes the Luau data module to out_path
        (export_intro.DATA_PATH is the runtime's file). parity_path (export_intro.PARITY_PATH is the
        one the test reads) also writes the parity fixture: Blender-evaluated values at
        `fixture_samples` random sub-frame times (rng seeded with `seed`). Returns a report dict
        {"bytes": total, "sections": {name: bytes}, "tracks": {name: {stage, rate, t0, n}},
         "character": {...} or None, "warnings": [...], "seconds": bake time}.
    data = export_intro.bake(scene, rate=30, rates=None)   the IntroData table as Python data
    text = export_intro.to_luau(data)                     its Luau source
    export_intro.vertical_fov(camera_data, scene) -> degrees

    command line (Blender's python):
        python tools/blender/intro/export_intro.py [scene.blend=assets/IntroScene.blend]
               [--out src/IntroCutscene/IntroData.luau] [--parity tools/tests/intro_parity.luau | --no-parity]
               [--rate 30] [--samples 200] [--seed 1]

What the exporter reads from the scene (the contract for scene.py)
------------------------------------------------------------------
* Time: frame f is t = (f - frame_start) / fps (DESIGN: frame_start 1, 30 fps). duration =
  (frame_end - frame_start) / fps. Everything is sampled with scene.frame_set (constraints,
  drivers, parenting all evaluated), so bake whatever is convenient in Blender.
* Tracks (DESIGN §3): the objects Camera, SoulCore, Planet, Rift, SkyRift, Sword, Shockwave,
  Blast, SlashArc, Starfield that exist, plus every object with the custom property
  export_track = 1 (track name = object name). Per sample: world location, world rotation
  (quaternion, hemisphere-continuous), uniform scale (written only when it is not always 1) and
  the channels.
    - channels = the object's custom properties named in TRACKS[name] (DESIGN §3) that exist on
      it; an export_track object exports all its numeric custom properties except the reserved
      ones below and names starting with "_". The custom property export_channels = "a,b,c"
      overrides the list on any object.
    - Camera: channel fov = vertical field of view in degrees computed from lens + sensor
      (sensor_fit VERTICAL, sensor_height 24 per DESIGN; other fits are converted with the
      render aspect). A "fov" custom property is never read.
    - visible (0/1, CONSTANT interpolation): the track covers the frames from the first to the
      last frame where visible >= 0.5, plus one sample of margin on each side (gaps in between
      stay in, visible = 0 there). A track that is never visible is skipped. Without a visible
      channel the track covers its stage's time: space = up to stageSwitch, world = from
      stageSwitch, camera = everything (each with the margin sample).
    - stage: custom property "stage" ("space" | "world" | "camera") or the TRACKS default;
      export_track objects without it get space / world / camera from the time they cover
      (camera = spans the stage switch: the runtime picks the origin by time, ctx.origin).
    - rate: `rate` samples per second (must divide the scene fps); the custom property
      export_rate overrides it per object. If the file is bigger than budget_kb, the slow tracks
      SLOW_TRACKS drop to rate / 2 (each track writes its own rate). Low-rate tracks align their
      sample grid to a cut inside their range when they can.
* Character: the armature object CharacterRig (rig.py; its world matrix is the HumanoidRootPart).
  Sampled every frame (rate = fps) from the first frame its custom property visible is >= 0.5
  (minus one margin frame) to frame_end: root = world location + quaternion, joints = rig.joint_transforms() (the
  Motor6D Transforms, joint space, hemisphere-continuous per joint), rootLoc = the Root bone's
  location, channels visible and form (custom properties of CharacterRig; 1 when missing).
* Markers: scene.timeline_markers sorted by frame (ties keep their creation order), names as in
  DESIGN §1. cuts = every "cut" marker, stageSwitch = the "stage:world" marker, world.windStart =
  the first "wind:*" marker.
* Scene custom properties: space_seed (int, the seed scene.py passed to space.generate, default
  7) -> starfield = space.generate(space_seed); landing_height (float, Blender z of the ground at
  the landing point, default 0) -> world.landingHeight.
* Reserved object properties (never channels): export_track, export_channels, export_rate, stage.

Output format: DESIGN §8. Numbers are rounded: positions 0.001, quaternions 1e-5, scalars 1e-4,
times 1e-6 (so sample times and cuts line up exactly in Timeline). The text is compact (no spaces
after commas, no leading zero: ".5"), both plain Luau.

Parity fixture (tools/tests/intro_parity.luau, a Luau module returning a table): at random
sub-frame times (never in the frame interval just before a cut, where the runtime holds the
pre-cut sample on purpose) the Blender-evaluated pos / quaternion / scale / channels of the
tracks PARITY_TRACKS, the character root + rootLoc + channels + PARITY_JOINTS, and for the
convention checks the camera's look/up and the sword's blade direction (world). It also records
the shape of the IntroData it belongs to (duration, track t0/n) so the test detects a stale pair.
Test: luau tools/tests/intro_parity_test.luau
"""
import math
import os
import random
import sys
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (_HERE, os.path.dirname(_HERE)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import bpy  # noqa: E402
from mathutils import Matrix, Quaternion, Vector  # noqa: E402

import rig as _rig  # noqa: E402
import space  # noqa: E402

ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))
DATA_PATH = os.path.join(ROOT, "src", "IntroCutscene", "IntroData.luau")
PARITY_PATH = os.path.join(ROOT, "tools", "tests", "intro_parity.luau")
SCENE_PATH = os.path.join(ROOT, "assets", "IntroScene.blend")

# name: (default stage, channels) -- DESIGN §3
TRACKS = {
    "Camera": ("camera", ("fov",)),
    "SoulCore": ("camera", ("glow", "pulse", "tail", "visible")),
    "Planet": ("space", ("visible",)),
    "Rift": ("space", ("crack", "open", "visible")),
    "Starfield": ("space", ("stars", "nebula", "galaxies", "twinkle")),
    "SkyRift": ("world", ("crack", "open", "visible")),
    "Sword": ("world", ("resonance", "glow", "held", "visible")),
    "Shockwave": ("world", ("opacity", "visible")),
    "Blast": ("world", ("opacity", "visible")),
    "SlashArc": ("world", ("opacity", "visible")),
}
CHARACTER = "CharacterRig"
CHARACTER_CHANNELS = ("visible", "form")
SLOW_TRACKS = ("Planet", "Starfield", "Shockwave")
RESERVED = {"export_track", "export_channels", "export_rate", "stage"}
STAGES = ("space", "world", "camera")
PARITY_TRACKS = ("Camera", "SoulCore", "Sword")
PARITY_JOINTS = ("Root", "RightShoulder", "RightElbow", "LeftHip")

POS_DIGITS, QUAT_DIGITS, SCALAR_DIGITS, TIME_DIGITS = 3, 5, 4, 6


# ----------------------------------------------------------------------------- helpers
def _warn(warnings, msg):
    if msg not in warnings:
        warnings.append(msg)
        print("export_intro WARNING:", msg)


def scene_fps(scene):
    return scene.render.fps / scene.render.fps_base


def vertical_fov(cam_data, scene):
    """Vertical field of view (degrees) of a perspective camera, from lens and sensor."""
    r = scene.render
    aspect = (r.resolution_x * r.pixel_aspect_x) / max(1e-9, r.resolution_y * r.pixel_aspect_y)
    lens = cam_data.lens
    fit = cam_data.sensor_fit
    if fit == "VERTICAL":
        return math.degrees(2 * math.atan(cam_data.sensor_height / (2 * lens)))
    # HORIZONTAL, or AUTO (sensor_width spans the larger image side)
    half = cam_data.sensor_width / (2 * lens)
    if fit == "HORIZONTAL" or aspect >= 1:
        return math.degrees(2 * math.atan(half / aspect))
    return math.degrees(2 * math.atan(half))


def _is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, str)


def _channels_of(obj, name):
    """Channel names exported for an object (see the module docstring)."""
    spec = obj.get("export_channels")
    if isinstance(spec, str) and spec.strip():
        return [c.strip() for c in spec.split(",") if c.strip()]
    if name == "Camera":
        return ["fov"]              # computed from the lens, never read from a property
    if name in TRACKS:
        return [c for c in TRACKS[name][1] if c in obj.keys()]
    return sorted(k for k in obj.keys() if k not in RESERVED and not k.startswith("_") and _is_number(obj[k]))


def _decompose(M):
    loc, q, s = M.decompose()
    q.normalize()
    return loc, q, s


def _continuous(quats):
    """Hemisphere-continuous copy of a list of Quaternions."""
    out = []
    for q in quats:
        q = q.copy()
        if out and out[-1].dot(q) < 0:
            q.negate()
        out.append(q)
    return out


# ----------------------------------------------------------------------------- sampling
class _Sampler:
    """Evaluates the scene at frames (cached) and sub-frames; snapshots every exported object."""

    def __init__(self, scene, objects, channels, character):
        self.scene = scene
        self.objects = objects          # {track name: object}
        self.channels = channels        # {track name: [channel names]}
        self.character = character      # armature object or None
        self.cache = {}
        self.evals = 0

    def _depsgraph(self):
        if self.scene == bpy.context.scene:
            return bpy.context.evaluated_depsgraph_get()
        dg = self.scene.view_layers[0].depsgraph
        dg.update()
        return dg

    def snapshot(self, frame, subframe=0.0):
        key = int(frame) if subframe == 0.0 else None
        if key is not None and key in self.cache:
            return self.cache[key]
        self.scene.frame_set(int(frame), subframe=float(subframe))
        self.evals += 1
        dg = self._depsgraph()
        snap = {}
        for name, obj in self.objects.items():
            ev = obj.evaluated_get(dg)
            ch = {}
            for c in self.channels[name]:
                if c == "fov" and obj.type == "CAMERA":
                    ch[c] = vertical_fov(ev.data, self.scene)
                else:
                    v = ev.get(c, obj.get(c, 0.0))
                    ch[c] = float(v) if _is_number(v) else 0.0
            snap[name] = (ev.matrix_world.copy(), ch)
        if self.character is not None:
            ev = self.character.evaluated_get(dg)
            jt = _rig.joint_transforms(ev)
            ch = {}
            for c in CHARACTER_CHANNELS:
                v = ev.get(c, self.character.get(c, 1.0))
                ch[c] = float(v) if _is_number(v) else 1.0
            snap[CHARACTER] = (ev.matrix_world.copy(), {b: q.copy() for b, (q, _t) in jt.items()},
                               jt["Root"][1].copy(), ch)
        if key is not None:
            self.cache[key] = snap
        return snap


def _markers(scene, fps):
    ms = [(m.frame, i, m.name) for i, m in enumerate(scene.timeline_markers)]
    ms.sort()
    return [((f - scene.frame_start) / fps, f, name) for f, _i, name in ms]


def _grid(lo, hi, step, align_frames, start):
    """Sample frames covering [lo, hi] every `step` frames; for step > 1 the grid is shifted so
    that as many align_frames (cuts) inside the range as possible are on it."""
    if step > 1:
        inside = [c for c in align_frames if lo <= c <= hi]
        best, best_n = lo % step, -1
        for off in range(step):
            n = sum(1 for c in inside if c % step == off)
            if n > best_n:
                best, best_n = off, n
        f0 = lo - ((lo - best) % step)
        if f0 < start:
            f0 += step
    else:
        f0 = lo
    frames = [f0]
    while frames[-1] < hi:
        frames.append(frames[-1] + step)
    return frames


def bake(scene, rate=30, rates=None, verbose=True, _state=None):
    """The IntroData table (DESIGN §8) as Python data. rates: {track name: samples per second}
    overrides (on top of export_rate properties). Returns (data, info)."""
    t_start = time.time()
    warnings = [] if _state is None else _state["warnings"]
    fps = scene_fps(scene)
    fs, fe = scene.frame_start, scene.frame_end
    if abs(fps - 30) > 1e-6 or fs != 1:
        _warn(warnings, "DESIGN expects 30 fps and frame_start 1 (got %.3f fps, start %d)" % (fps, fs))

    markers = _markers(scene, fps)
    cuts = [t for t, _f, n in markers if n == "cut"]
    cut_frames = [f for _t, f, n in markers if n == "cut"]
    switch = next(((t, f) for t, f, n in markers if n == "stage:world"), None)
    if switch is None:
        _warn(warnings, "no stage:world marker: stageSwitch is left out (everything is the space stage)")
    elif not any(abs(c - switch[0]) < 1e-9 for c in cuts):
        _warn(warnings, "no cut marker at the stage switch (t %.4f): camera tracks would blend across it" % switch[0])
    wind = next((t for t, _f, n in markers if n.split(":")[0] == "wind"), None)

    # objects ------------------------------------------------------------------------------------
    objects, channels = {}, {}
    for name in TRACKS:
        obj = scene.objects.get(name)
        if obj is not None:
            objects[name] = obj
    for obj in scene.objects:
        if obj.name not in objects and obj.get("export_track") and obj.name != CHARACTER:
            objects[obj.name] = obj
    for name, obj in objects.items():
        channels[name] = _channels_of(obj, name)
        if name in TRACKS:
            missing = [c for c in TRACKS[name][1] if c not in channels[name]]
            if missing:
                _warn(warnings, "%s has no custom propert%s %s" % (name, "y" if len(missing) == 1 else "ies", ", ".join(missing)))
    cam = objects.get("Camera")
    if cam is None:
        _warn(warnings, "no Camera object")
    elif cam.type == "CAMERA":
        if cam.data.type != "PERSP":
            _warn(warnings, "Camera is not a perspective camera")
        if cam.data.sensor_fit != "VERTICAL":
            _warn(warnings, "Camera sensor_fit is %s, DESIGN says VERTICAL (fov converted with the render aspect)" % cam.data.sensor_fit)
    character = scene.objects.get(CHARACTER)
    if character is not None and character.type != "ARMATURE":
        _warn(warnings, "%s is not an armature: no character exported" % CHARACTER)
        character = None

    sampler = _Sampler(scene, objects, channels, character) if _state is None else _state["sampler"]
    saved_frame = (scene.frame_current, scene.frame_subframe)
    # pass 1: every frame (visibility ranges, and most samples come from here)
    for f in range(fs, fe + 1):
        sampler.snapshot(f)
        if verbose and (f - fs) % 200 == 0 and _state is None:
            print("export_intro: evaluating frame %d / %d" % (f, fe))

    def frame_time(f):
        return (f - fs) / fps

    def stage_range(stage, step):
        if switch is None or stage == "camera":
            return fs, fe
        if stage == "space":
            return fs, min(fe, switch[1] - 1 + step)
        return max(fs, switch[1] - step), fe

    tracks, info = {}, {}
    for name, obj in objects.items():
        r = (rates or {}).get(name) or obj.get("export_rate") or rate
        step = fps / r
        if abs(step - round(step)) > 1e-6 or step < 1:
            raise ValueError("%s: rate %s does not divide %s fps" % (name, r, fps))
        step = int(round(step))
        has_vis = "visible" in channels[name]
        if has_vis:
            vis = [f for f in range(fs, fe + 1) if sampler.snapshot(f)[name][1]["visible"] >= 0.5]
            if not vis:
                _warn(warnings, "%s is never visible: not exported" % name)
                continue
            odd = [f for f in range(fs, fe + 1) if 1e-6 < sampler.snapshot(f)[name][1]["visible"] < 1 - 1e-6]
            if odd:
                _warn(warnings, "%s.visible is not 0/1 at frame %d (key it with CONSTANT interpolation)" % (name, odd[0]))
            lo, hi = max(fs, vis[0] - step), min(fe, vis[-1] + step)
        stage = obj.get("stage") if isinstance(obj.get("stage"), str) else None
        if stage is not None and stage not in STAGES:
            _warn(warnings, "%s: unknown stage %r, using the default" % (name, stage))
            stage = None
        if stage is None:
            if name in TRACKS:
                stage = TRACKS[name][0]
            elif not has_vis or switch is None:
                stage = "camera" if switch is not None else "space"
            else:
                stage = "space" if vis[-1] < switch[1] else ("world" if vis[0] >= switch[1] else "camera")
        if not has_vis:
            lo, hi = stage_range(stage, step)
        frames = _grid(lo, hi, step, cut_frames, fs)
        mats, quats, chans = [], [], {c: [] for c in channels[name]}
        for f in frames:
            M, ch = sampler.snapshot(f)[name]
            mats.append(M)
            for c in channels[name]:
                chans[c].append(ch[c])
        pos, scales = [], []
        aniso = 0.0
        for M in mats:
            loc, q, s = _decompose(M)
            pos.append(tuple(loc))
            quats.append(q)
            su = (abs(s.x) + abs(s.y) + abs(s.z)) / 3
            aniso = max(aniso, max(abs(abs(s.x) - su), abs(abs(s.y) - su), abs(abs(s.z) - su)) / max(su, 1e-9))
            scales.append(su)
        if aniso > 0.01:
            _warn(warnings, "%s has non-uniform scale (%.1f %%): exported as the mean" % (name, aniso * 100))
        quats = _continuous(quats)
        tr = {"stage": stage, "rate": r, "t0": frame_time(frames[0]), "n": len(frames),
              "pos": [c for p in pos for c in p], "rot": [c for q in quats for c in (q.w, q.x, q.y, q.z)],
              "channels": chans}
        if any(abs(s - 1) > 0.5 * 10 ** -SCALAR_DIGITS for s in scales):
            tr["scale"] = scales
        tracks[name] = tr
        info[name] = {"stage": stage, "rate": r, "t0": tr["t0"], "n": tr["n"], "frames": (frames[0], frames[-1])}

    # character ------------------------------------------------------------------------------------
    char = None
    if character is not None:
        vis = [f for f in range(fs, fe + 1) if sampler.snapshot(f)[CHARACTER][3]["visible"] >= 0.5]
        if not vis:
            _warn(warnings, "%s is never visible: exporting the world stage range" % CHARACTER)
            lo = switch[1] if switch else fs
        else:
            lo = max(fs, vis[0] - 1)
        for c in CHARACTER_CHANNELS:
            if c not in character.keys():
                _warn(warnings, "%s has no custom property %s (exported as 1)" % (CHARACTER, c))
        frames = list(range(lo, fe + 1))
        snaps = [sampler.snapshot(f)[CHARACTER] for f in frames]
        root_pos, root_q = [], []
        for M, _j, _l, _c in snaps:
            loc, q, _s = _decompose(M)
            root_pos.append(tuple(loc))
            root_q.append(q)
        root_q = _continuous(root_q)
        joints = {}
        for b in _rig.BONES:
            qs = _continuous([s[1][b].normalized() for s in snaps])
            joints[b] = [c for q in qs for c in (q.w, q.x, q.y, q.z)]
        char = {"rate": fps, "t0": frame_time(lo), "n": len(frames),   # always every frame
                "root": {"pos": [c for p in root_pos for c in p], "rot": [c for q in root_q for c in (q.w, q.x, q.y, q.z)]},
                "joints": joints, "rootLoc": [c for s in snaps for c in s[2]],
                "channels": {c: [s[3][c] for s in snaps] for c in CHARACTER_CHANNELS}}

    seed = scene.get("space_seed")
    if seed is None:
        _warn(warnings, "scene has no custom property space_seed: starfield from space.generate(7)")
        seed = 7
    starfield = space.generate(int(seed))
    landing = scene.get("landing_height", 0.0)

    data = {
        "version": 1, "fps": fps, "duration": (fe - fs) / fps,
        "markers": [{"t": t, "name": n} for t, _f, n in markers],
        "cuts": cuts, "tracks": tracks, "character": char, "starfield": starfield,
        "world": {"landingHeight": float(landing)},
    }
    if switch is not None:
        data["stageSwitch"] = switch[0]
    if wind is not None:
        data["world"]["windStart"] = wind
    else:
        _warn(warnings, "no wind:* marker: world.windStart is left out")
    if _state is None:
        scene.frame_set(saved_frame[0], subframe=saved_frame[1])
    return data, {"tracks": info, "warnings": warnings, "sampler": sampler, "seconds": time.time() - t_start,
                  "cut_frames": cut_frames, "objects": objects, "character": character}


# ----------------------------------------------------------------------------- Luau writer
def _num(v, digits):
    r = round(float(v), digits)
    if r == 0 or r != r:
        return "0"
    if r == int(r) and abs(r) < 1e15:
        return str(int(r))
    s = ("%." + str(digits) + "f") % r
    s = s.rstrip("0").rstrip(".")
    if s.startswith("0."):
        s = s[1:]
    elif s.startswith("-0."):
        s = "-" + s[2:]
    return s


def _arr(values, digits, indent, per_line=24):
    if not values:
        return "{}"
    parts = [_num(v, digits) for v in values]
    if len(parts) <= per_line:
        return "{" + ",".join(parts) + "}"
    pad = "\t" * (indent + 1)
    lines = [pad + ",".join(parts[i:i + per_line]) + "," for i in range(0, len(parts), per_line)]
    return "{\n" + "\n".join(lines) + "\n" + "\t" * indent + "}"


def _key(k):
    if k.isidentifier() and k not in ("and", "break", "do", "else", "elseif", "end", "false", "for", "function",
                                      "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true",
                                      "until", "while", "continue"):
        return k
    return "[%s]" % _str(k)


def _str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def _track_luau(d, indent):
    pad = "\t" * (indent + 1)
    out = ["{"]
    out.append('%sstage = "%s", rate = %s, t0 = %s, n = %d,' % (pad, d["stage"], _num(d["rate"], 6), _num(d["t0"], TIME_DIGITS), d["n"]))
    out.append("%spos = %s," % (pad, _arr(d["pos"], POS_DIGITS, indent + 1, 24)))
    out.append("%srot = %s," % (pad, _arr(d["rot"], QUAT_DIGITS, indent + 1, 24)))
    if "scale" in d:
        out.append("%sscale = %s," % (pad, _arr(d["scale"], SCALAR_DIGITS, indent + 1, 24)))
    out.append("%schannels = {" % pad)
    for name in sorted(d["channels"]):
        out.append("%s\t%s = %s," % (pad, _key(name), _arr(d["channels"][name], SCALAR_DIGITS, indent + 2, 30)))
    out.append("%s}," % pad)
    out.append("\t" * indent + "}")
    return "\n".join(out)


def _character_luau(c):
    L = ["{"]
    L.append("\t\trate = %s, t0 = %s, n = %d," % (_num(c["rate"], 6), _num(c["t0"], TIME_DIGITS), c["n"]))
    L.append("\t\troot = {")
    L.append("\t\t\tpos = " + _arr(c["root"]["pos"], POS_DIGITS, 3) + ",")
    L.append("\t\t\trot = " + _arr(c["root"]["rot"], QUAT_DIGITS, 3) + ",")
    L.append("\t\t},")
    L.append("\t\tjoints = {")
    for b in _rig.BONES:
        L.append("\t\t\t%s = %s," % (b, _arr(c["joints"][b], QUAT_DIGITS, 3)))
    L.append("\t\t},")
    L.append("\t\trootLoc = " + _arr(c["rootLoc"], POS_DIGITS, 2) + ",")
    L.append("\t\tchannels = {")
    for name in sorted(c["channels"]):
        L.append("\t\t\t%s = %s," % (_key(name), _arr(c["channels"][name], SCALAR_DIGITS, 3, 30)))
    L.append("\t\t},")
    L.append("\t}")
    return "\n".join(L)


def _starfield_luau(sf):
    L = ["{"]
    L.append("\t\tstars = " + _arr(sf["stars"], 5, 2, 27) + ",")
    L.append("\t\tgalaxies = {")
    for g in sf["galaxies"]:
        L.append("\t\t\t{")
        L.append("\t\t\t\tcenter = %s, normal = %s, xaxis = %s," % (_arr(g["center"], POS_DIGITS, 4), _arr(g["normal"], 5, 4), _arr(g["xaxis"], 5, 4)))
        L.append("\t\t\t\tradius = %s, arms = %d, twist = %s," % (_num(g["radius"], POS_DIGITS), g["arms"], _num(g["twist"], 5)))
        L.append("\t\t\t\tpoints = " + _arr(g["points"], 5, 4, 22) + ",")
        L.append("\t\t\t},")
    L.append("\t\t},")
    L.append("\t\tnebulae = {")
    for nb in sf["nebulae"]:
        L.append("\t\t\t{ center = %s, radius = %s, color = %s, appear = %s }," % (
            _arr(nb["center"], POS_DIGITS, 3), _num(nb["radius"], POS_DIGITS), _arr(nb["color"], SCALAR_DIGITS, 3),
            _num(nb["appear"], SCALAR_DIGITS)))
    L.append("\t\t},")
    L.append("\t}")
    return "\n".join(L)


def to_luau(data, source="", sections=None):
    """Luau source of an IntroData table. sections: dict that receives the byte size per part."""
    sections = {} if sections is None else sections
    L = ["-- IntroData: GENERATED by tools/blender/intro/export_intro.py%s. Never hand-edit." % (
            (" from " + source) if source else ""),
         "-- Format: docs/intro/DESIGN.md §8 (sampled by Timeline.luau).",
         "return {",
         "\tversion = %d," % data["version"],
         "\tfps = %s," % _num(data["fps"], 6),
         "\tduration = %s," % _num(data["duration"], TIME_DIGITS)]
    head = ["\tmarkers = {"]
    for m in data["markers"]:
        head.append("\t\t{ t = %s, name = %s }," % (_num(m["t"], TIME_DIGITS), _str(m["name"])))
    head.append("\t},")
    head.append("\tcuts = %s," % _arr(data["cuts"], TIME_DIGITS, 1, 12))
    if "stageSwitch" in data:
        head.append("\tstageSwitch = %s," % _num(data["stageSwitch"], TIME_DIGITS))
    w = data["world"]
    parts = ["landingHeight = %s" % _num(w["landingHeight"], POS_DIGITS)]
    if "windStart" in w:
        parts.insert(0, "windStart = %s" % _num(w["windStart"], TIME_DIGITS))
    head.append("\tworld = { %s }," % ", ".join(parts))
    text = "\n".join(head)
    sections["markers+meta"] = len(text) + 1
    L.append(text)
    L.append("\ttracks = {")
    for name in sorted(data["tracks"]):
        text = "\t\t%s = %s," % (_key(name), _track_luau(data["tracks"][name], 2))
        sections["track " + name] = len(text) + 1
        L.append(text)
    L.append("\t},")
    if data.get("character"):
        text = "\tcharacter = " + _character_luau(data["character"]) + ","
        sections["character"] = len(text) + 1
        L.append(text)
    text = "\tstarfield = " + _starfield_luau(data["starfield"]) + ","
    sections["starfield"] = len(text) + 1
    L.append(text)
    L.append("}")
    return "\n".join(L) + "\n"


def _write(path, text):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        fh.write(text)
    os.replace(tmp, path)


# ----------------------------------------------------------------------------- parity fixture
def _fixture_times(data, n, seed):
    rng = random.Random(seed)
    fps = data["fps"]
    windows = [(c - 1.0 / fps, c) for c in data["cuts"]]
    out = []
    while len(out) < n:
        t = rng.uniform(0.0, data["duration"])
        if any(a - 1e-9 < t < b - 1e-9 for a, b in windows):
            continue
        out.append(t)
    out.sort()
    return out


def _parity(scene, data, info, n, seed):
    sampler = info["sampler"]
    fps = data["fps"]
    entries = []
    blade = None
    for t in _fixture_times(data, n, seed):
        fl = t * fps + scene.frame_start
        frame = int(math.floor(fl))
        sub = fl - frame
        snap = sampler.snapshot(frame, sub)
        for name in PARITY_TRACKS:
            d = data["tracks"].get(name)
            if d is None or not (d["t0"] - 1e-9 <= t <= d["t0"] + (d["n"] - 1) / d["rate"] + 1e-9):
                continue
            M, ch = snap[name]
            loc, q, s = _decompose(M)
            e = {"t": t, "track": name, "pos": tuple(loc), "rot": (q.w, q.x, q.y, q.z),
                 "scale": (abs(s.x) + abs(s.y) + abs(s.z)) / 3, "channels": dict(ch)}
            R = M.to_3x3().normalized()
            if name == "Camera":
                e["look"] = tuple(R @ Vector((0, 0, -1)))
                e["up"] = tuple(R @ Vector((0, 1, 0)))
            elif name == "Sword":
                e["blade"] = tuple(R @ Vector((0, 0, 1)))
            entries.append(e)
        c = data.get("character")
        if c and CHARACTER in snap and c["t0"] - 1e-9 <= t <= c["t0"] + (c["n"] - 1) / c["rate"] + 1e-9:
            M, joints, loc_root, ch = snap[CHARACTER]
            loc, q, _s = _decompose(M)
            entries.append({"t": t, "track": "character", "pos": tuple(loc), "rot": (q.w, q.x, q.y, q.z),
                            "rootLoc": tuple(loc_root), "channels": dict(ch),
                            "joints": {b: tuple(joints[b].normalized()) for b in PARITY_JOINTS}})
    return entries


def _parity_luau(data, entries, source=""):
    def v(vals):
        return "{" + ", ".join("%.7g" % x for x in vals) + "}"

    L = ["-- Parity fixture: GENERATED by tools/blender/intro/export_intro.py%s." % ((" from " + source) if source else ""),
         "-- Blender-evaluated values at random sub-frame times, checked against Timeline sampling of",
         "-- src/IntroCutscene/IntroData.luau by tools/tests/intro_parity_test.luau (DESIGN §9).",
         "return {",
         "\tdata = {",
         "\t\tduration = %s, fps = %s," % (_num(data["duration"], TIME_DIGITS), _num(data["fps"], 6)),
         "\t\ttracks = {"]
    for name in sorted(data["tracks"]):
        d = data["tracks"][name]
        L.append("\t\t\t%s = { t0 = %s, n = %d, rate = %s }," % (_key(name), _num(d["t0"], TIME_DIGITS), d["n"], _num(d["rate"], 6)))
    L.append("\t\t},")
    c = data.get("character")
    if c:
        L.append("\t\tcharacter = { t0 = %s, n = %d, rate = %s }," % (_num(c["t0"], TIME_DIGITS), c["n"], _num(c["rate"], 6)))
    L.append("\t},")
    L.append("\tsamples = {")
    for e in entries:
        parts = ["t = %.7f" % e["t"], 'track = "%s"' % e["track"], "pos = " + v(e["pos"]), "rot = " + v(e["rot"])]
        if "scale" in e:
            parts.append("scale = %.7g" % e["scale"])
        for k in ("look", "up", "blade", "rootLoc"):
            if k in e:
                parts.append("%s = %s" % (k, v(e[k])))
        parts.append("channels = {" + ", ".join("%s = %.7g" % (_key(k), x) for k, x in sorted(e["channels"].items())) + "}")
        if "joints" in e:
            parts.append("joints = {" + ", ".join("%s = %s" % (b, v(q)) for b, q in e["joints"].items()) + "}")
        L.append("\t\t{ " + ", ".join(parts) + " },")
    L.append("\t},")
    L.append("}")
    return "\n".join(L) + "\n"


# ----------------------------------------------------------------------------- export
def export(scene=None, out_path=None, parity_path=None, rate=30, fixture_samples=200, seed=1, budget_kb=700,
           verbose=True):
    """Bake `scene` into out_path (+ the parity fixture at parity_path). See the module docstring."""
    scene = scene or bpy.context.scene
    out_path = out_path or DATA_PATH
    source = os.path.basename(bpy.data.filepath) if bpy.data.filepath else ""
    saved = (scene.frame_current, scene.frame_subframe)
    try:
        data, info = bake(scene, rate=rate, verbose=verbose)
        sections = {}
        text = to_luau(data, source, sections)
        if len(text) > budget_kb * 1000:
            slow = [n for n in SLOW_TRACKS if n in data["tracks"] and data["tracks"][n]["rate"] == rate
                    and not info["objects"][n].get("export_rate")]
            if slow and rate % 2 == 0:
                print("export_intro: %.0f KB > %d KB, slow tracks %s drop to rate %d" % (
                    len(text) / 1000, budget_kb, ", ".join(slow), rate // 2))
                first = info["seconds"]
                data, info = bake(scene, rate=rate, rates={n: rate // 2 for n in slow}, verbose=verbose,
                                  _state={"sampler": info["sampler"], "warnings": info["warnings"]})
                info["seconds"] += first
                sections = {}
                text = to_luau(data, source, sections)
            if len(text) > budget_kb * 1000:
                _warn(info["warnings"], "IntroData is %.0f KB, over the %d KB budget" % (len(text) / 1000, budget_kb))
        _write(out_path, text)
        entries = None
        if parity_path:
            entries = _parity(scene, data, info, fixture_samples, seed)
            _write(parity_path, _parity_luau(data, entries, source))
    finally:
        scene.frame_set(saved[0], subframe=saved[1])

    report = {"bytes": len(text.encode("utf-8")), "sections": sections, "tracks": info["tracks"],
              "character": ({k: data["character"][k] for k in ("rate", "t0", "n")} if data.get("character") else None),
              "warnings": info["warnings"], "seconds": info["seconds"], "evaluations": info["sampler"].evals,
              "fixture": len(entries) if entries is not None else 0}
    if verbose:
        print("export_intro: wrote %s (%.1f KB, %d scene evaluations, %.1f s)" % (
            out_path, report["bytes"] / 1000, report["evaluations"], report["seconds"]))
        for name, b in sorted(sections.items(), key=lambda kv: -kv[1]):
            extra = ""
            tr = info["tracks"].get(name[6:]) if name.startswith("track ") else None
            if tr:
                extra = "  %-6s rate %-3s t0 %7.3f  n %4d" % (tr["stage"], _num(tr["rate"], 3), tr["t0"], tr["n"])
            elif name == "character" and report["character"]:
                c = report["character"]
                extra = "  world  rate %-3s t0 %7.3f  n %4d" % (_num(c["rate"], 3), c["t0"], c["n"])
            print("  %-22s %8.1f KB%s" % (name, b / 1000, extra))
        if parity_path:
            print("export_intro: wrote %s (%d fixture entries)" % (parity_path, report["fixture"]))
        if info["warnings"]:
            print("export_intro: %d warning(s)" % len(info["warnings"]))
    return report


def _main(argv):
    import argparse
    ap = argparse.ArgumentParser(description="Bake the intro scene into IntroData.luau (+ parity fixture)")
    ap.add_argument("blend", nargs="?", default=SCENE_PATH)
    ap.add_argument("--out", default=DATA_PATH)
    ap.add_argument("--parity", default=PARITY_PATH)
    ap.add_argument("--no-parity", action="store_true")
    ap.add_argument("--rate", type=int, default=30)
    ap.add_argument("--samples", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=a.blend)
    export(bpy.context.scene, a.out, None if a.no_parity else a.parity, rate=a.rate, fixture_samples=a.samples, seed=a.seed)


if __name__ == "__main__":
    _main(sys.argv[1:])
