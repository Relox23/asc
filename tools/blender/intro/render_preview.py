"""
Animatic renderer of the intro cutscene (docs/intro/DESIGN.md §9): Cycles stills / MP4 of the Blender
scene with the 2D layer of the Roblox runtime burned in (Screen.luau rules): cinematic bars, black
fades, colour flashes, screen speed lines and the impact frames of §7.4.

API (Blender's python; used by build_intro.py / scene.py)
---------------------------------------------------------
    import render_preview
    paths = render_preview.render(scene, out_dir, frames=None, times=None, size=(640, 360), samples=8,
                                  mp4=None, impact=True, step=1, glow=True, overlays=True, threads=None,
                                  core_color=None, keep_passes=False, shake=True)
        Renders the given frames (frame numbers) or times (seconds, frame = round(t * fps) + frame_start);
        neither = every frame of the scene. Writes <out_dir>/frame_NNNN.png (NNNN = Blender frame) and
        returns their paths in order. Cycles on the CPU, `samples` samples + OpenImageDenoise,
        view transform Standard (what the intro materials and space.py's emission strengths are tuned
        for, + space.configure_render), then space.post_glow (cheap bloom) unless glow=False.
          mp4="x.mp4"   also encodes the frames with the system ffmpeg: 30 fps, h264, yuv420p, crf 23.
          step=n        renders only every n-th frame (plus the first frame of every shot, so holds
                        never cross a cut) and holds it for the frames in between; bars, fades, flashes,
                        speed lines and impact frames are still drawn for every output frame. A cheap
                        full-length animatic: render(scene, d, step=3, mp4=d + "/intro.mp4").
          impact=False  renders impact-frame times like any other frame.
          overlays=False  no 2D layer at all (raw renders + glow, no shake).
          shake=False   no camera shake (shake:<magnitude>:<s> markers; see below).
          core_color    soul core colour for flash:core (sRGB 0..1); default the scene custom property
                        core_color, else Config.TEST_COLOR (120, 200, 255).
          threads       Cycles CPU threads (None = all).
          keep_passes   keep <out_dir>/raw (beauty renders) and <out_dir>/sil (silhouette masks).
        Everything it changes on the scene (render settings, frame, camera) is restored.
        What it expects from the scene: scene.camera = the Camera; the silhouettes are CharacterRig
        and Sword with all their children (mannequin parts, sword pieces); the scene's own world and
        lights are used as they are; markers as in DESIGN §1; optional scene custom property
        core_color = (r, g, b) sRGB 0..1 for flash:core.
    render_preview.KEY_TIMES     stills at the storyboard beats (DESIGN §1), e.g.
                                 render(scene, d, times=render_preview.KEY_TIMES)
    render_preview.encode_mp4(paths, mp4, fps=30) -> mp4   h264 / yuv420p / crf 23 with the system ffmpeg
    render_preview.contact_sheet(paths, out_path, cols=4, width=1600, labels=None) -> out_path
        Labelled grid of stills (labels default to "t 12.50 s  f 376" from frame_NNNN names; system
        python3 + Pillow, called through a subprocess when Pillow is missing in Blender's python).
    render_preview.screen_state(markers, t) -> dict   the runtime's 2D state at t (pure python):
        {"bars", "fade", "flash": (rgb, alpha) or None, "impact": "off"|"white"|"black", "speed"}
    render_preview.shake_offset(markers, t) -> (x, y, roll)   Screen.luau's camera shake at t
        (camera-local studs right / up, radians about the view axis); markers = [(t, name)].

How the 2D layer is made
------------------------
Pure python (numpy + Pillow) in a system python3 subprocess (`render_preview.py --composite job.json`),
mirroring Screen.luau: marker state machine and timing curves (smoothstep ramps for bars / fades,
flash alpha (1 - p)^2), the same pseudo-random hash for the speed lines and the 32 impact lines
(re-randomised every 1/60 s), thicknesses scaled from 720p. Impact frames (impact:white / impact:black
until the next impact:* marker): the beauty render is skipped; a silhouette pass renders only
CharacterRig (+ its mannequin parts) and Sword (+ descendants) in the scene itself (everything else made
invisible to camera rays, a white emission material override, transparent film; so animation,
constraints and visibility evaluate exactly as in the beauty pass); its alpha becomes black-on-white
(or white-on-black) silhouettes under the radial lines.
Layer order as in the runtime: impact frame, impact lines, speed lines, flash, bars, fade.
Camera shake is 3D, like the runtime's (camera.CFrame = track CFrame * ShakeOffset): while a shake
marker is active the frame is rendered through a temporary camera parented to Camera with the
camera-local offset of Screen.luau (same decay and frequencies; Perlin noise instead of
math.noise, so the same character but not the same numbers).

Command line
------------
    python tools/blender/intro/render_preview.py [scene.blend=assets/IntroScene.blend] --out DIR
        [--times 0.5,12,28.05 | --frames 16,361 | --key | --all] [--step 3] [--size 640x360]
        [--samples 8] [--threads 2] [--mp4 DIR/intro.mp4] [--sheet DIR/sheet.png] [--no-impact]
        [--no-glow] [--no-overlays] [--no-shake] [--keep-passes]
    python3 tools/blender/intro/render_preview.py --sheet out.png a.png b.png ...   (contact sheet only)
"""
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))
SCENE_PATH = os.path.join(ROOT, "assets", "IntroScene.blend")

BAR_RATIO = 2.39
SPEED_LINES = 36
IMPACT_LINES = 32
TEST_COLOR = (120 / 255, 200 / 255, 255 / 255)
EPS = 1e-6
SILHOUETTE_ROOTS = ("CharacterRig", "Sword")
MARKER_SUFFIXES = ("__Origin", "__Up", "__Front")

# storyboard beats (DESIGN §1): one still per shot / event
KEY_TIMES = [0.6, 1.4, 4.0, 7.5, 9.5, 11.2, 13.5, 15.6, 17.0, 17.9, 18.45, 19.2, 20.6, 21.2, 22.5, 24.0, 25.5,
             27.0, 27.7, 28.05, 28.15, 29.1, 30.3, 31.2, 32.5, 34.2, 35.6, 36.8, 38.6, 39.4, 40.6, 42.0]


# ============================================================================ the 2D layer (pure python)
def _clamp01(x):
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def _smooth(x):
    x = _clamp01(x)
    return x * x * (3 - 2 * x)


def _hash(i, s):
    """Screen.luau's deterministic pseudo random 0..1."""
    x = math.sin(i * 12.9898 + s * 78.233) * 43758.5453
    return x - math.floor(x)


def _ramp(st, t):
    if st["dur"] <= 0:
        return st["to"] if t >= st["t0"] else st["from"]
    return st["from"] + (st["to"] - st["from"]) * _smooth((t - st["t0"]) / st["dur"])


def _arg(args, k, default):
    try:
        return float(args[k])
    except (IndexError, ValueError):
        return default


def screen_state(markers, t, core_color=TEST_COLOR):
    """Screen.luau's state at time t from the markers [(time, name)] (sorted, ties in order)."""
    bars = {"from": 0.0, "to": 0.0, "t0": 0.0, "dur": 0.0}
    fade = {"from": 0.0, "to": 0.0, "t0": 0.0, "dur": 0.0}
    flash = None
    impact = "off"
    speed = {"on": False, "t0": -100.0}

    def speed_level(tt):
        if speed["on"]:
            return _clamp01((tt - speed["t0"]) / 0.25)
        return 1 - _clamp01((tt - speed["t0"]) / 0.35)

    for tm, name in markers:
        if tm > t + EPS:
            break
        parts = name.split(":")
        kind, args = parts[0], parts[1:]
        if kind == "bars" and args:
            b0 = _ramp(bars, tm)
            bars = {"from": b0, "to": 1.0 if args[0] == "in" else 0.0, "t0": tm, "dur": _arg(args, 1, 1.0)}
        elif kind == "fade" and args:
            f0 = _ramp(fade, tm)
            to_black = args[0] == "to_black"
            if not to_black and f0 < 1e-3:
                f0 = 1.0
            fade = {"from": f0, "to": 1.0 if to_black else 0.0, "t0": tm, "dur": _arg(args, 1, 1.0)}
        elif kind == "flash":
            color = tuple(core_color) if args and args[0] == "core" else (1.0, 1.0, 1.0)
            flash = (color, tm, max(_arg(args, 1, 0.3), 1 / 60))
        elif kind == "impact":
            impact = args[0] if args and args[0] in ("white", "black") else "off"
        elif kind == "speedlines" and args:
            on = args[0] == "on"
            if on != speed["on"]:
                level = speed_level(tm)
                speed = {"on": on, "t0": tm - level * 0.25 if on else tm - (1 - level) * 0.35}
    fl = None
    if flash:
        color, t0, dur = flash
        p = (t - t0) / dur
        if 0 <= p < 1:
            fl = (color, (1 - p) * (1 - p))
    return {"bars": _ramp(bars, t), "fade": _ramp(fade, t), "flash": fl, "impact": impact,
            "speed": max(0.0, speed_level(t))}


def _impact_mode_at(markers, t):
    mode = "off"
    for tm, name in markers:
        if tm > t + EPS:
            break
        parts = name.split(":")
        if parts[0] == "impact":
            mode = parts[1] if len(parts) > 1 and parts[1] in ("white", "black") else "off"
    return mode


# Perlin's improved noise (a look-alike of Roblox's math.noise: same character, not the same numbers)
_PERM = list(range(256))
__import__("random").Random(1985).shuffle(_PERM)
_PERM += _PERM


def _fade_curve(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def _grad(h, x, y, z):
    h &= 15
    u = x if h < 8 else y
    v = y if h < 4 else (x if h in (12, 14) else z)
    return (u if h & 1 == 0 else -u) + (v if h & 2 == 0 else -v)


def noise3(x, y, z):
    """Gradient noise in about [-1, 1], 0 on the integer lattice (like math.noise)."""
    fx, fy, fz = math.floor(x), math.floor(y), math.floor(z)
    X, Y, Z = int(fx) & 255, int(fy) & 255, int(fz) & 255
    x, y, z = x - fx, y - fy, z - fz
    u, v, w = _fade_curve(x), _fade_curve(y), _fade_curve(z)
    P = _PERM
    A, B = P[X] + Y, P[X + 1] + Y
    AA, AB, BA, BB = P[A] + Z, P[A + 1] + Z, P[B] + Z, P[B + 1] + Z

    def lerp(t, a, b):
        return a + t * (b - a)

    return lerp(w, lerp(v, lerp(u, _grad(P[AA], x, y, z), _grad(P[BA], x - 1, y, z)),
                        lerp(u, _grad(P[AB], x, y - 1, z), _grad(P[BB], x - 1, y - 1, z))),
                lerp(v, lerp(u, _grad(P[AA + 1], x, y, z - 1), _grad(P[BA + 1], x - 1, y, z - 1)),
                     lerp(u, _grad(P[AB + 1], x, y - 1, z - 1), _grad(P[BB + 1], x - 1, y - 1, z - 1))))


def shake_offset(markers, t):
    """Screen.luau's ShakeOffset at t from the shake:<magnitude>:<seconds> markers: camera-local
    (x, y, roll) -- studs right / up and radians about the view axis (Blender camera axes are the
    same: X right, Y up, looking along -Z)."""
    shakes = []
    for tm, name in markers:
        if tm > t + EPS:
            break
        parts = name.split(":")
        if parts[0] != "shake":
            continue
        live = [sh for sh in shakes if tm < sh[2] + sh[1]]     # the runtime prunes finished ones
        mag, dur = _arg(parts[1:], 0, 0.5), max(_arg(parts[1:], 1, 0.5), 1e-3)
        shakes = live + [(mag, dur, tm, len(live) * 7.31 + tm)]
    x = y = roll = 0.0
    for mag, dur, t0, seed in shakes:
        p = (t - t0) / dur
        if 0 <= p < 1:
            k = mag * (1 - p) * (1 - p)
            tt = (t - t0) * 17
            x += noise3(tt, seed, 0.5) * 2 * k
            y += noise3(seed, tt, 1.5) * 2 * k
            roll += noise3(tt, 2.5, seed) * k * 0.02
    return x, y, roll


def _line(img, cx, cy, ang, mid, length, width, color, alpha_fn, opacity=1.0):
    """Draw one tapered line (Screen.luau taperedLine) into img (h, w, 3 float): centre at distance
    `mid` from the screen centre along `ang`, rotated to the radial direction, inner end transparent."""
    import numpy as np
    h, w, _ = img.shape
    dx, dy = math.cos(ang), math.sin(ang)
    x0, y0 = cx + dx * (mid - length / 2), cy + dy * (mid - length / 2)
    x1, y1 = cx + dx * (mid + length / 2), cy + dy * (mid + length / 2)
    pad = width + 2
    xa, xb = int(max(0, math.floor(min(x0, x1) - pad))), int(min(w, math.ceil(max(x0, x1) + pad)))
    ya, yb = int(max(0, math.floor(min(y0, y1) - pad))), int(min(h, math.ceil(max(y0, y1) + pad)))
    if xa >= xb or ya >= yb:
        return
    ys, xs = np.mgrid[ya:yb, xa:xb].astype(np.float32)
    px, py = xs + 0.5 - x0, ys + 0.5 - y0
    u = px * dx + py * dy                       # along the line, 0 = inner end
    d = np.abs(-px * dy + py * dx)              # across
    cover = np.clip(width / 2 + 0.5 - d, 0, 1) * np.clip(u + 0.5, 0, 1) * np.clip(length - u + 0.5, 0, 1)
    a = cover * alpha_fn(np.clip(u / max(length, 1e-6), 0, 1)) * opacity
    region = img[ya:yb, xa:xb]
    region[:] = region * (1 - a[..., None]) + np.asarray(color, dtype=np.float32) * a[..., None]


def _taper(u):
    """UIGradient transparency (0: 1, 0.55: 0.35, 1: 0) as opacity along the line."""
    import numpy as np
    tr = np.where(u < 0.55, 1 - (1 - 0.35) * (u / 0.55), 0.35 * (1 - (u - 0.55) / 0.45))
    return 1 - tr


def composite_frame(job, fr):
    """One output frame of a composite job (see _composite_main). Returns the RGB uint8 array."""
    import numpy as np
    from PIL import Image
    w, h = job["size"]
    t = fr["t"]
    markers = [tuple(m) for m in job["markers"]]
    st = screen_state(markers, t, job.get("core_color", TEST_COLOR)) if job.get("overlays", True) else None
    k = h / 720.0                                # runtime line widths are pixels at ~720p
    cx, cy = w / 2, h / 2
    R = 0.5 * math.sqrt(w * w + h * h)
    mode = fr.get("mode", "off")
    if mode in ("white", "black") and fr.get("sil"):
        sil = np.asarray(Image.open(fr["sil"]).convert("RGBA").resize((w, h)), dtype=np.float32) / 255
        mask = sil[..., 3:4]
        bg = 1.0 if mode == "white" else 0.0
        img = np.full((h, w, 3), bg, dtype=np.float32) * (1 - mask) + (1 - bg) * mask
        seed = math.floor(t * 60)
        line_color = (1 - bg,) * 3
        for i in range(1, IMPACT_LINES + 1):
            a = _hash(i, seed) * 2 * math.pi
            length = R * (0.3 + 0.45 * _hash(i, seed + 0.5))
            mid = R * 1.05 - length / 2
            width = (2 + 7 * _hash(i, seed + 0.25) ** 2) * k
            _line(img, cx, cy, a, mid, length, max(width, 0.8), line_color, _taper)
    elif fr.get("src"):
        img = np.asarray(Image.open(fr["src"]).convert("RGB").resize((w, h)), dtype=np.float32) / 255
    else:
        img = np.zeros((h, w, 3), dtype=np.float32)
    if st is not None:
        level = st["speed"]
        if level > 0:
            for i in range(1, SPEED_LINES + 1):
                a = (i - 1 + _hash(i, 1) * 0.8) / SPEED_LINES * 2 * math.pi
                speed = 1.4 + _hash(i, 2) * 1.6
                phase = (t * speed + _hash(i, 3)) % 1
                r_out = R * (1.12 - 0.6 * phase)
                length = R * (0.16 + 0.26 * _hash(i, 4))
                alpha = level * math.sin(math.pi * phase) * 0.75
                if alpha > 0.02:
                    _line(img, cx, cy, a, r_out - length / 2, length, max((1.5 + 2 * _hash(i, 5)) * k, 0.6),
                          (1.0, 1.0, 1.0), _taper, alpha)
        if st["flash"]:
            color, a = st["flash"]
            img = img * (1 - a) + np.asarray(color, dtype=np.float32) * a
        b = st["bars"]
        bar_h = max(0.0, (h - w / BAR_RATIO) / 2) * b
        if bar_h > 0.01:
            full = int(math.floor(bar_h))
            frac = bar_h - full
            img[:full] = 0
            img[h - full:] = 0
            if frac > 0 and full < h:
                img[full] *= 1 - frac
                img[h - full - 1] *= 1 - frac
        if st["fade"] > 1e-3:
            img = img * (1 - st["fade"])
    return (np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)


def _composite_main(job_path):
    from PIL import Image
    with open(job_path) as fh:
        job = json.load(fh)
    for fr in job["frames"]:
        Image.fromarray(composite_frame(job, fr)).save(fr["out"])
    print("composited %d frames" % len(job["frames"]))


def _font(size):
    from PIL import ImageFont
    for name in ("DejaVuSans.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "Arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _label_for(path, fps=30.0, start=1):
    stem = os.path.splitext(os.path.basename(path))[0]
    if stem.startswith("frame_"):
        try:
            f = int(stem[6:])
            return "t %.2f s  f %d" % ((f - start) / fps, f)
        except ValueError:
            pass
    return stem


def _sheet_pil(paths, out_path, cols=4, width=1600, labels=None):
    from PIL import Image, ImageDraw
    ims = [Image.open(p).convert("RGB") for p in paths]
    tw = max(1, (width - (cols + 1) * 6) // cols)
    th = int(round(tw * ims[0].size[1] / ims[0].size[0]))
    lab = 20
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * 6, rows * (th + lab + 6) + 6), (22, 22, 26))
    d = ImageDraw.Draw(sheet)
    font = _font(13)
    for i, im in enumerate(ims):
        x = 6 + (i % cols) * (tw + 6)
        y = 6 + (i // cols) * (th + lab + 6)
        sheet.paste(im.resize((tw, th), Image.LANCZOS), (x, y + lab))
        d.text((x + 2, y + 3), labels[i] if labels else _label_for(paths[i]), fill=(235, 235, 240), font=font)
    sheet.save(out_path)
    return out_path


def _python3():
    """A python3 with numpy + Pillow for the 2D work (INTRO_PREVIEW_PYTHON overrides)."""
    cands = [os.environ.get("INTRO_PREVIEW_PYTHON"), "/usr/bin/python3", shutil.which("python3"), "python3"]
    for c in cands:
        if not c:
            continue
        try:
            r = subprocess.run([c, "-c", "import numpy, PIL"], capture_output=True)
        except OSError:
            continue
        if r.returncode == 0:
            return c
    raise RuntimeError("render_preview needs a python3 with numpy and Pillow (set INTRO_PREVIEW_PYTHON)")


def contact_sheet(paths, out_path, cols=4, width=1600, labels=None):
    """Labelled grid of the given stills -> out_path."""
    paths = list(paths)
    if not paths:
        raise ValueError("contact_sheet: no images")
    try:
        import PIL  # noqa: F401
        import numpy  # noqa: F401
        return _sheet_pil(paths, out_path, cols, width, labels)
    except ImportError:
        args = [_python3(), os.path.abspath(__file__), "--sheet", out_path, "--cols", str(cols), "--width", str(width)]
        if labels:
            args += ["--labels", json.dumps(labels)]
        subprocess.run(args + paths, check=True, stdout=subprocess.DEVNULL)
        return out_path


# ============================================================================ Blender side
def _save_settings(scene):
    r, c, v = scene.render, scene.cycles, scene.view_settings
    return {
        "engine": r.engine, "res": (r.resolution_x, r.resolution_y, r.resolution_percentage),
        "filepath": r.filepath, "fmt": (r.image_settings.file_format, r.image_settings.color_mode),
        "film_transparent": r.film_transparent, "threads": (r.threads_mode, r.threads),
        "cycles": (c.samples, c.use_denoising, c.device, c.use_adaptive_sampling),
        "view": (v.view_transform, v.look, v.exposure, v.gamma),
        "frame": (scene.frame_current, scene.frame_subframe),
    }


def _restore_settings(scene, s):
    r, c, v = scene.render, scene.cycles, scene.view_settings
    r.engine = s["engine"]
    r.resolution_x, r.resolution_y, r.resolution_percentage = s["res"]
    r.filepath = s["filepath"]
    r.image_settings.file_format, r.image_settings.color_mode = s["fmt"]
    r.film_transparent = s["film_transparent"]
    r.threads_mode, r.threads = s["threads"]
    c.samples, c.use_denoising, c.device, c.use_adaptive_sampling = s["cycles"]
    try:
        v.view_transform, v.look = s["view"][0], s["view"][1]
    except TypeError:
        pass
    v.exposure, v.gamma = s["view"][2], s["view"][3]
    scene.frame_set(s["frame"][0], subframe=s["frame"][1])


def _configure(scene, size, samples, threads, transparent=False, denoise=True):
    import space
    r = scene.render
    r.engine = "CYCLES"
    r.resolution_x, r.resolution_y = int(size[0]), int(size[1])
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA" if transparent else "RGB"
    r.film_transparent = transparent
    if threads:
        r.threads_mode, r.threads = "FIXED", int(threads)
    else:
        r.threads_mode = "AUTO"
    c = scene.cycles
    c.device = "CPU"
    c.samples = int(samples)
    c.use_adaptive_sampling = False
    c.use_denoising = denoise
    if denoise:
        try:
            c.denoiser = "OPENIMAGEDENOISE"
        except TypeError:
            pass
    v = scene.view_settings
    try:
        v.view_transform = "Standard"
        v.look = "None"
    except TypeError:
        pass
    v.exposure, v.gamma = 0.0, 1.0
    space.configure_render(scene)


def _render_still(scene, path):
    import bpy
    scene.render.filepath = path
    if scene == bpy.context.scene:
        bpy.ops.render.render(write_still=True)
    else:
        bpy.ops.render.render(write_still=True, scene=scene.name)


def _silhouette_objects(scene):
    objs = []
    for name in SILHOUETTE_ROOTS:
        o = scene.objects.get(name)
        if o is None:
            continue
        for x in [o] + list(o.children_recursive):
            if x.type in ("MESH", "CURVE", "SURFACE", "META", "FONT", "ARMATURE", "EMPTY") and not x.name.endswith(MARKER_SUFFIXES):
                objs.append(x)
    return objs


class _ShakeCamera:
    """A temporary camera parented to the scene camera (sharing its data, so lens keys apply) that
    carries the camera-local shake offset; it is the render camera while a shake is active."""

    def __init__(self, scene):
        import bpy
        from mathutils import Matrix
        self.scene = scene
        self.src = scene.camera
        self.obj = bpy.data.objects.new("PreviewShakeCamera", self.src.data)
        scene.collection.objects.link(self.obj)
        self.obj.parent = self.src
        self.obj.matrix_parent_inverse = Matrix()

    def apply(self, scene, offset):
        x, y, roll = offset
        self.obj.location = (x, y, 0.0)
        self.obj.rotation_euler = (0.0, 0.0, roll)
        scene.camera = self.obj if (x or y or roll) else self.src

    def close(self):
        import bpy
        self.scene.camera = self.src
        bpy.data.objects.remove(self.obj)


class _Silhouettes:
    """The silhouette pass, in the scene itself (so constraints, parents and drivers evaluate exactly
    as in the beauty pass): every object except CharacterRig + Sword and their children is made
    invisible to camera rays (instancers hide their instances too), the view layer gets a white
    emission material override, no world, transparent film, no bounces. Everything is put back by
    close()."""

    def __init__(self, scene, size, threads, shaker=None):
        import bpy
        self.scene = scene
        self.shaker = shaker
        keep = set(_silhouette_objects(scene))
        self.vis = {}
        for o in scene.objects:
            if o not in keep and o.type != "CAMERA":
                self.vis[o.name] = o.visible_camera
                o.visible_camera = False
        self.mat = bpy.data.materials.new("PreviewSilhouette")
        nt = self.mat.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        em = nt.nodes.new("ShaderNodeEmission")
        em.inputs["Color"].default_value = (1, 1, 1, 1)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(em.outputs[0], out.inputs[0])
        vl = bpy.context.view_layer if scene == bpy.context.scene else scene.view_layers[0]
        self.view_layer = vl
        c = scene.cycles
        self.saved = {"override": vl.material_override, "world": scene.world,
                      "bounces": (c.max_bounces, c.transparent_max_bounces),
                      "film": scene.render.film_transparent, "mode": scene.render.image_settings.color_mode,
                      "cycles": (c.samples, c.use_denoising)}
        vl.material_override = self.mat
        scene.world = None
        _configure(scene, size, 16, threads, transparent=True, denoise=False)
        c.max_bounces = 0
        c.transparent_max_bounces = 8

    def render(self, frame, path, offset=None):
        self.scene.frame_set(frame)
        if self.shaker is not None:
            self.shaker.apply(self.scene, offset or (0.0, 0.0, 0.0))
        _render_still(self.scene, path)

    def close(self):
        import bpy
        sc, s = self.scene, self.saved
        for name, v in self.vis.items():
            o = sc.objects.get(name)
            if o is not None:
                o.visible_camera = v
        self.view_layer.material_override = s["override"]
        sc.world = s["world"]
        sc.cycles.max_bounces, sc.cycles.transparent_max_bounces = s["bounces"]
        sc.render.film_transparent = s["film"]
        sc.render.image_settings.color_mode = s["mode"]
        sc.cycles.samples, sc.cycles.use_denoising = s["cycles"]
        bpy.data.materials.remove(self.mat)


def _scene_markers(scene):
    fps = scene.render.fps / scene.render.fps_base
    ms = sorted(((m.frame, i, m.name) for i, m in enumerate(scene.timeline_markers)))
    return [((f - scene.frame_start) / fps, n) for f, _i, n in ms]


def render(scene=None, out_dir="preview", frames=None, times=None, size=(640, 360), samples=8, mp4=None,
           impact=True, step=1, glow=True, overlays=True, threads=None, core_color=None, keep_passes=False,
           shake=True, verbose=True):
    """Render the animatic frames. See the module docstring."""
    import time
    import bpy
    sys.path.insert(0, _HERE)
    import space

    scene = scene or bpy.context.scene
    fps = scene.render.fps / scene.render.fps_base
    fs, fe = scene.frame_start, scene.frame_end
    size = (int(size[0]) // 2 * 2, int(size[1]) // 2 * 2)    # even, for yuv420p
    if frames is None and times is None:
        out_frames = list(range(fs, fe + 1))
    else:
        out_frames = list(frames or []) + [int(round(t * fps)) + fs for t in (times or [])]
        out_frames = sorted(set(int(f) for f in out_frames))
    if core_color is None:
        cc = scene.get("core_color")
        core_color = tuple(float(x) for x in cc) if cc is not None and len(cc) >= 3 else TEST_COLOR
    markers = _scene_markers(scene)
    cut_frames = {int(round(t * fps)) + fs for t, n in markers if n == "cut"}
    out_dir = os.path.abspath(out_dir)
    raw_dir, sil_dir = os.path.join(out_dir, "raw"), os.path.join(out_dir, "sil")
    os.makedirs(raw_dir, exist_ok=True)

    def t_of(f):
        return (f - fs) / fps

    modes = {f: (_impact_mode_at(markers, t_of(f)) if impact else "off") for f in out_frames}
    # beauty renders: every step-th frame of the output, plus the first frame of every shot
    beauty = []
    last = None
    for f in out_frames:
        if modes[f] != "off":
            continue
        if last is None or f - last >= step or f in cut_frames or any(last < c <= f for c in cut_frames):
            beauty.append(f)
            last = f
    sil_frames = [f for f in out_frames if modes[f] != "off"]

    saved = _save_settings(scene)
    t_start = time.time()
    sil = shaker = None
    try:
        _configure(scene, size, samples, threads)
        if shake and overlays and scene.camera is not None and any(n.startswith("shake:") for _t, n in markers):
            shaker = _ShakeCamera(scene)
        for k, f in enumerate(beauty):
            t0 = time.time()
            scene.frame_set(f)
            if shaker is not None:
                shaker.apply(scene, shake_offset(markers, t_of(f)))
            p = os.path.join(raw_dir, "frame_%04d.png" % f)
            _render_still(scene, p)
            if glow:
                space.post_glow(p)
            if verbose:
                print("render_preview: frame %d (t %.2f) %d/%d  %.1f s" % (f, t_of(f), k + 1, len(beauty), time.time() - t0))
        if sil_frames:
            os.makedirs(sil_dir, exist_ok=True)
            sil = _Silhouettes(scene, size, threads, shaker)
            for f in sil_frames:
                sil.render(f, os.path.join(sil_dir, "frame_%04d.png" % f), shake_offset(markers, t_of(f)))
            if verbose:
                print("render_preview: %d impact frames (silhouette pass)" % len(sil_frames))
    finally:
        if sil is not None:
            sil.close()
        if shaker is not None:
            shaker.close()
        _restore_settings(scene, saved)

    # 2D layer -------------------------------------------------------------------------------------
    job = {"size": list(size), "fps": fps, "markers": [list(m) for m in markers], "core_color": list(core_color),
           "overlays": overlays, "frames": []}
    outs = []
    src = None
    for f in out_frames:
        if f in beauty:
            src = os.path.join(raw_dir, "frame_%04d.png" % f)
        out = os.path.join(out_dir, "frame_%04d.png" % f)
        job["frames"].append({"frame": f, "t": t_of(f), "src": src, "mode": modes[f],
                              "sil": os.path.join(sil_dir, "frame_%04d.png" % f) if modes[f] != "off" else None,
                              "out": out})
        outs.append(out)
    job_path = os.path.join(out_dir, "composite_job.json")
    with open(job_path, "w") as fh:
        json.dump(job, fh)
    subprocess.run([_python3(), os.path.abspath(__file__), "--composite", job_path], check=True)
    os.remove(job_path)
    if not keep_passes:
        shutil.rmtree(raw_dir, ignore_errors=True)
        shutil.rmtree(sil_dir, ignore_errors=True)
    if mp4:
        encode_mp4(outs, mp4, fps)
    if verbose:
        print("render_preview: %d frames (%d rendered, %d impact) in %.1f s -> %s" % (
            len(outs), len(beauty), len(sil_frames), time.time() - t_start, out_dir))
    return outs


def encode_mp4(paths, mp4, fps=30):
    """h264 yuv420p crf 23 MP4 of the PNGs (in order) with the system ffmpeg."""
    ffmpeg = shutil.which("ffmpeg") or "/usr/bin/ffmpeg"
    tmp = tempfile.mkdtemp(prefix="intro_mp4_")
    try:
        for i, p in enumerate(paths):
            os.symlink(os.path.abspath(p), os.path.join(tmp, "%05d.png" % i))
        os.makedirs(os.path.dirname(os.path.abspath(mp4)), exist_ok=True)
        subprocess.run([ffmpeg, "-y", "-loglevel", "error", "-framerate", "%g" % fps, "-i", os.path.join(tmp, "%05d.png"),
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "23", "-r", "%g" % fps, mp4], check=True)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return mp4


# ============================================================================ command line
def _floats(s):
    return [float(x) for x in s.split(",") if x.strip()]


def _main(argv):
    import argparse
    if "--composite" in argv:
        _composite_main(argv[argv.index("--composite") + 1])
        return
    if argv and argv[0] == "--sheet":
        ap = argparse.ArgumentParser()
        ap.add_argument("--sheet")
        ap.add_argument("--cols", type=int, default=4)
        ap.add_argument("--width", type=int, default=1600)
        ap.add_argument("--labels")
        ap.add_argument("images", nargs="+")
        a = ap.parse_args(argv)
        print(_sheet_pil(a.images, a.sheet, a.cols, a.width, json.loads(a.labels) if a.labels else None))
        return
    ap = argparse.ArgumentParser(description="Render the intro animatic (stills / mp4)")
    ap.add_argument("blend", nargs="?", default=SCENE_PATH)
    ap.add_argument("--out", required=True)
    ap.add_argument("--times")
    ap.add_argument("--frames")
    ap.add_argument("--key", action="store_true", help="the storyboard stills KEY_TIMES")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--step", type=int, default=1)
    ap.add_argument("--size", default="640x360")
    ap.add_argument("--samples", type=int, default=8)
    ap.add_argument("--threads", type=int)
    ap.add_argument("--mp4")
    ap.add_argument("--sheet")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--no-impact", action="store_true")
    ap.add_argument("--no-glow", action="store_true")
    ap.add_argument("--no-overlays", action="store_true")
    ap.add_argument("--keep-passes", action="store_true")
    ap.add_argument("--no-shake", action="store_true")
    a = ap.parse_args(argv)
    import bpy
    bpy.ops.wm.open_mainfile(filepath=a.blend)
    times = _floats(a.times) if a.times else (KEY_TIMES if a.key else None)
    frames = [int(x) for x in _floats(a.frames)] if a.frames else None
    if a.all:
        times = frames = None
    elif times is None and frames is None:
        times = KEY_TIMES
    w, h = (int(x) for x in a.size.lower().split("x"))
    outs = render(bpy.context.scene, a.out, frames=frames, times=times, size=(w, h), samples=a.samples, mp4=a.mp4,
                  impact=not a.no_impact, step=a.step, glow=not a.no_glow, overlays=not a.no_overlays,
                  threads=a.threads, keep_passes=a.keep_passes, shake=not a.no_shake)
    if a.sheet:
        print(contact_sheet(outs, a.sheet, cols=a.cols))


if __name__ == "__main__":
    _main(sys.argv[1:])
