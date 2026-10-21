#!/usr/bin/env python3
"""Write a small but format-correct src/IntroCutscene/IntroData.luau (DESIGN §8).

A stand-in for the real export (tools/blender/intro/export_intro.py) so the Roblox
runtime can run end to end before the Blender scene exists: 8 seconds, both
stages (space 0-4 s, world 4-8 s), cuts at 4.0 and 6.0, the camera, SoulCore,
Planet, Rift, Starfield, SkyRift, Sword, Blast, SlashArc, Shockwave, the R15
character with a few poses, every marker kind, and a tiny starfield.

usage: python3 tools/tests/make_intro_stub.py [out.luau]
"""
import math
import pathlib
import random
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
OUT = ROOT / "src" / "IntroCutscene" / "IntroData.luau"

FPS = 30
DURATION = 8.0
SWITCH = 4.0
CUTS = [4.0, 6.0]

JOINTS = ["Root", "Waist", "Neck", "LeftShoulder", "LeftElbow", "LeftWrist", "RightShoulder", "RightElbow",
          "RightWrist", "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle"]

# joint-space Euler XYZ degrees (DESIGN §4.2), unlisted joints = 0
POSES = {
    "stand": {},
    "fall_spread": {"LeftShoulder": (0, 0, -100), "RightShoulder": (0, 0, 100), "LeftElbow": (0, 0, -20),
                    "RightElbow": (0, 0, 20), "LeftHip": (0, 0, -25), "RightHip": (0, 0, 25),
                    "LeftKnee": (-30, 0, 0), "RightKnee": (-30, 0, 0), "Neck": (20, 0, 0), "Waist": (-10, 0, 0)},
    "reach_right": {"RightShoulder": (150, 0, 10), "RightElbow": (10, 0, 0), "LeftShoulder": (0, 0, -60),
                    "Waist": (0, 20, 0), "Neck": (25, 10, 0), "LeftHip": (20, 0, -10), "RightKnee": (-50, 0, 0)},
    "hold_sword_low": {"RightShoulder": (20, 0, 8), "RightElbow": (35, 0, 0), "LeftShoulder": (0, 0, -8)},
}


def lerp(a, b, u):
    return a + (b - a) * u


def smooth(u):
    u = min(max(u, 0.0), 1.0)
    return u * u * (3 - 2 * u)


# quaternion helpers (w, x, y, z) -------------------------------------------------------------------------
def qmul(a, b):
    aw, ax, ay, az = a
    bw, bx, by, bz = b
    return (aw * bw - ax * bx - ay * by - az * bz,
            aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw)


def qaxis(axis, angle):
    s = math.sin(angle / 2)
    return (math.cos(angle / 2), axis[0] * s, axis[1] * s, axis[2] * s)


def qeuler_xyz(deg):
    """Blender XYZ Euler: R = Rz * Ry * Rx."""
    x, y, z = (math.radians(d) for d in deg)
    return qmul(qaxis((0, 0, 1), z), qmul(qaxis((0, 1, 0), y), qaxis((1, 0, 0), x)))


def qslerp(a, b, u):
    dot = sum(p * q for p, q in zip(a, b))
    if dot < 0:
        b, dot = tuple(-v for v in b), -dot
    if dot > 0.9995:
        r = tuple(lerp(p, q, u) for p, q in zip(a, b))
    else:
        th = math.acos(dot)
        s = math.sin(th)
        k1, k2 = math.sin((1 - u) * th) / s, math.sin(u * th) / s
        r = tuple(p * k1 + q * k2 for p, q in zip(a, b))
    n = math.sqrt(sum(v * v for v in r))
    return tuple(v / n for v in r)


def qfrom_matrix(m):
    """m: rows of a 3x3 rotation matrix."""
    tr = m[0][0] + m[1][1] + m[2][2]
    if tr > 0:
        s = math.sqrt(tr + 1.0) * 2
        return (0.25 * s, (m[2][1] - m[1][2]) / s, (m[0][2] - m[2][0]) / s, (m[1][0] - m[0][1]) / s)
    if m[0][0] > m[1][1] and m[0][0] > m[2][2]:
        s = math.sqrt(1.0 + m[0][0] - m[1][1] - m[2][2]) * 2
        return ((m[2][1] - m[1][2]) / s, 0.25 * s, (m[0][1] + m[1][0]) / s, (m[0][2] + m[2][0]) / s)
    if m[1][1] > m[2][2]:
        s = math.sqrt(1.0 + m[1][1] - m[0][0] - m[2][2]) * 2
        return ((m[0][2] - m[2][0]) / s, (m[0][1] + m[1][0]) / s, 0.25 * s, (m[1][2] + m[2][1]) / s)
    s = math.sqrt(1.0 + m[2][2] - m[0][0] - m[1][1]) * 2
    return ((m[1][0] - m[0][1]) / s, (m[0][2] + m[2][0]) / s, (m[1][2] + m[2][1]) / s, 0.25 * s)


def norm(v):
    n = math.sqrt(sum(c * c for c in v))
    return tuple(c / n for c in v)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def camera_look(eye, target):
    """Blender camera rotation looking from eye at target (camera -Z forward, +Y up)."""
    f = norm(tuple(t - e for t, e in zip(target, eye)))
    right = cross(f, (0, 0, 1))
    if math.sqrt(sum(c * c for c in right)) < 1e-6:
        right = (1, 0, 0)
    right = norm(right)
    up = cross(right, f)
    back = tuple(-c for c in f)
    m = [[right[i], up[i], back[i]] for i in range(3)]  # columns right, up, back
    return qfrom_matrix(m)


def continuous(quats):
    out = []
    for q in quats:
        if out and sum(a * b for a, b in zip(out[-1], q)) < 0:
            q = tuple(-v for v in q)
        out.append(q)
    return out


# the story ------------------------------------------------------------------------------------------
def core_space(t):
    return (math.sin(t * 0.7) * 0.6, 0.0, 40.0 - 9.0 * t)


SKY_RIFT = (0.0, 6.0, 110.0)


def core_world(t):
    u = smooth((t - SWITCH) / 0.7)
    return tuple(lerp(a, b, u) for a, b in zip(SKY_RIFT, char_root(4.7)))


def char_root(t):
    if t < 6.0:
        u = (t - SWITCH) / 2.0
        return (0.0, 6.0 * (1 - u), lerp(100.0, 3.0, 1 - (1 - u) ** 2))
    return (0.0, 0.0, 3.0)


def char_rot(t):
    if t < 6.0:
        return qmul(qaxis((0, 0, 1), 0.6 * (t - SWITCH)), qaxis((1, 0, 0), 0.5 * math.sin(2.0 * (t - SWITCH))))
    return (1.0, 0.0, 0.0, 0.0)


def char_pose(t):
    keys = [(4.0, "fall_spread"), (4.9, "fall_spread"), (5.4, "reach_right"), (5.95, "reach_right"),
            (6.0, "stand"), (7.0, "hold_sword_low"), (8.0, "hold_sword_low")]
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if ta <= t <= tb:
            u = smooth((t - ta) / (tb - ta)) if tb > ta else 0
            return {j: qslerp(qeuler_xyz(POSES[a].get(j, (0, 0, 0))), qeuler_xyz(POSES[b].get(j, (0, 0, 0))), u)
                    for j in JOINTS}
    return {j: qeuler_xyz(POSES["hold_sword_low"].get(j, (0, 0, 0))) for j in JOINTS}


def camera(t):
    if t < SWITCH:
        c = core_space(t)
        a = 0.35 * t + 0.4
        eye = (c[0] + math.cos(a) * 12, c[1] + math.sin(a) * 12, c[2] - 3.0)
        return eye, camera_look(eye, c)
    if t < 6.0:
        target = char_root(t) if t >= 4.6 else core_world(t)
        eye = (target[0] + 9.0, target[1] - 7.0, target[2] - 2.5)
        return eye, camera_look(eye, target)
    eye = (14.0, -60.0, 22.0)
    return eye, camera_look(eye, (0.0, 0.0, 4.0))


def times(t0, t1):
    n = int(round((t1 - t0) * FPS)) + 1
    return [t0 + i / FPS for i in range(n)]


def track(stage, t0, t1, pos_fn, rot_fn, channels=None, scale_fn=None):
    ts = times(t0, t1)
    d = {
        "stage": stage, "rate": FPS, "t0": t0, "n": len(ts),
        "pos": [c for t in ts for c in pos_fn(t)],
        "rot": [c for q in continuous([rot_fn(t) for t in ts]) for c in q],
        "channels": {name: [fn(t) for t in ts] for name, fn in (channels or {}).items()},
    }
    if scale_fn:
        d["scale"] = [scale_fn(t) for t in ts]
    return d


def step(t, at, before=0.0, after=1.0):
    return after if t >= at - 1e-9 else before


IDQ = (1.0, 0.0, 0.0, 0.0)
DOWN = qaxis((1, 0, 0), math.pi)  # an asset facing +Z turned to face down


def build():
    tracks = {}

    def cam_pos(t):
        return camera(t)[0]

    def cam_rot(t):
        return camera(t)[1]

    tracks["Camera"] = track("camera", 0.0, DURATION, cam_pos, cam_rot,
                             {"fov": lambda t: 50 + 6 * math.sin(t * 0.9) if t < SWITCH else 60.0})
    tracks["SoulCore"] = track(
        "camera", 0.0, 4.8, lambda t: core_space(t) if t < SWITCH else core_world(t),
        lambda t: qaxis((0, 0, 1), 1.3 * t),
        {"glow": lambda t: min(3.0, 0.2 + 2.0 * t), "pulse": lambda t: 0.5 + 0.5 * math.sin(t * 6),
         "tail": lambda t: smooth((t - 1.0) / 2.0), "visible": lambda t: step(t, 4.7, 1.0, 0.0)})
    tracks["Planet"] = track("space", 0.0, SWITCH, lambda t: (60.0, 120.0, -700.0), lambda t: qaxis((0, 0, 1), 0.02 * t),
                             {"visible": lambda t: step(t, 1.0)})
    tracks["Rift"] = track("space", 0.0, SWITCH, lambda t: (0.0, 0.0, 6.0), lambda t: IDQ,
                           {"crack": lambda t: smooth((t - 2.0) / 1.0), "open": lambda t: smooth((t - 3.0) / 0.7),
                            "visible": lambda t: step(t, 2.0)})
    tracks["Starfield"] = track("space", 0.0, SWITCH, lambda t: core_space(t), lambda t: IDQ,
                                {"stars": lambda t: smooth(t / 3.0), "nebula": lambda t: smooth((t - 0.8) / 2.5),
                                 "galaxies": lambda t: smooth((t - 1.2) / 2.5), "twinkle": lambda t: 1.0})
    tracks["SkyRift"] = track("world", SWITCH, DURATION, lambda t: SKY_RIFT, lambda t: DOWN,
                              {"crack": lambda t: 1.0, "open": lambda t: 1.0 - smooth((t - 5.5) / 1.0),
                               "visible": lambda t: step(t, 6.5, 1.0, 0.0)})

    def sword_pos(t):
        r = char_root(t)
        u = smooth((t - 4.4) / 0.9)
        return (lerp(SKY_RIFT[0], r[0] + 1.6, u), lerp(SKY_RIFT[1], r[1] - 1.0, u), lerp(SKY_RIFT[2], r[2] + 1.5, u))

    tracks["Sword"] = track("world", SWITCH, DURATION, sword_pos, lambda t: qaxis(norm((1, 0.3, 0.2)), 7.0 * t),
                            {"resonance": lambda t: smooth((t - 5.3) / 0.5), "glow": lambda t: 2.0 * smooth((t - 5.3) / 0.5),
                             "held": lambda t: step(t, 5.0), "visible": lambda t: step(t, 4.4)})
    tracks["Blast"] = track("world", 5.3, 5.9, lambda t: char_root(t), lambda t: IDQ,
                            {"opacity": lambda t: 1.0 - smooth((t - 5.3) / 0.6), "visible": lambda t: step(t, 5.9, 1.0, 0.0)},
                            scale_fn=lambda t: 0.5 + 12 * smooth((t - 5.3) / 0.5))
    tracks["SlashArc"] = track("world", 5.6, 6.0, lambda t: char_root(t), lambda t: qaxis((0, 1, 0), -1.0 + 4.0 * (t - 5.6)),
                               {"opacity": lambda t: 1.0 - smooth((t - 5.6) / 0.4), "visible": lambda t: 1.0})
    tracks["Shockwave"] = track("world", 6.5, 8.0, lambda t: (0.0, 0.0, 0.2), lambda t: IDQ,
                                {"opacity": lambda t: 1.0 - smooth((t - 6.5) / 1.5), "visible": lambda t: step(t, 7.95, 1.0, 0.0)},
                                scale_fn=lambda t: 1.0 + 160 * (t - 6.5))

    ts = times(SWITCH, DURATION)
    poses = [char_pose(t) for t in ts]
    character = {
        "rate": FPS, "t0": SWITCH, "n": len(ts),
        "root": {"pos": [c for t in ts for c in char_root(t)],
                 "rot": [c for q in continuous([char_rot(t) for t in ts]) for c in q]},
        "joints": {j: [c for q in continuous([p[j] for p in poses]) for c in q] for j in JOINTS},
        "rootLoc": [0.0] * (3 * len(ts)),
        "channels": {"visible": [step(t, 4.6, 0.0, 1.0) for t in ts], "form": [smooth((t - 4.6) / 0.3) for t in ts]},
    }

    rng = random.Random(7)
    stars = []
    for _ in range(60):
        z = rng.uniform(-1, 1)
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(850, 960)
        s = math.sqrt(1 - z * z)
        warm = rng.random()
        stars += [math.cos(a) * s * r, math.sin(a) * s * r, z * r, rng.uniform(0.6, 3.2),
                  lerp(0.75, 1.0, warm), lerp(0.85, 0.95, warm), lerp(1.0, 0.8, warm), rng.uniform(0, 0.9),
                  rng.uniform(0, 2 * math.pi)]
    points = []
    for k in range(40):
        arm = k % 2
        u = k / 40
        ang = arm * math.pi + u * 5.0
        rr = 10 + u * 90
        points += [rng.uniform(-100, 100), rng.uniform(-100, 100), rng.uniform(-20, 20),
                   math.cos(ang) * rr, math.sin(ang) * rr, rng.uniform(-3, 3),
                   rng.uniform(2, 6), lerp(1.0, 0.6, u), lerp(0.95, 0.7, u), lerp(0.8, 1.0, u), rng.uniform(0, 0.3)]
    starfield = {
        "stars": stars,
        "galaxies": [{"center": [500.0, 600.0, 200.0], "normal": list(norm((-0.5, -0.6, 0.62))), "xaxis": [0.77, -0.64, 0.0],
                      "radius": 100.0, "arms": 2, "twist": 3.0, "points": points}],
        "nebulae": [{"center": [-400.0, 300.0, -200.0], "radius": 180.0, "color": [0.55, 0.3, 0.85], "appear": 0.1},
                    {"center": [300.0, -500.0, 100.0], "radius": 220.0, "color": [0.15, 0.55, 0.6], "appear": 0.4}],
    }

    markers = [
        (0.0, "bars:in:1.0"), (0.0, "fade:from_black:0.8"), (0.0, "sound:ignite"), (0.4, "flash:core:0.3"),
        (1.0, "speedlines:on"), (2.0, "shake:0.4:1.2"), (2.0, "sound:crack"), (3.0, "speedlines:off"),
        (3.9, "flash:white:0.3"), (SWITCH, "stage:world"), (SWITCH, "cut"), (4.6, "morph"), (4.75, "flash:white:0.2"),
        (5.0, "impact:white"), (5.1, "impact:black"), (5.2, "impact:white"), (5.3, "impact:off"),
        (5.3, "flash:core:0.4"), (5.3, "resonate"), (5.3, "shake:0.8:0.6"), (6.0, "cut"), (6.5, "shockwave"),
        (6.5, "wind:1.0"), (6.5, "sound:shockwave"), (7.0, "bars:out:1.0"), (DURATION, "end"),
    ]
    markers.sort(key=lambda m: m[0])
    return {
        "version": 1, "fps": FPS, "duration": DURATION,
        "markers": [{"t": t, "name": n} for t, n in markers],
        "cuts": CUTS, "stageSwitch": SWITCH, "tracks": tracks, "character": character,
        "starfield": starfield, "world": {"windStart": 6.5, "landingHeight": 0.0},
    }


# Luau writer ------------------------------------------------------------------------------------------
def num(v, digits):
    s = f"{v:.{digits}f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "", "-") else s


def arr(values, digits, indent, per_line=18):
    if not values:
        return "{}"
    parts = [num(v, digits) for v in values]
    if len(parts) <= per_line:
        return "{ " + ", ".join(parts) + " }"
    pad = "\t" * (indent + 1)
    lines = [pad + ", ".join(parts[i:i + per_line]) + "," for i in range(0, len(parts), per_line)]
    return "{\n" + "\n".join(lines) + "\n" + "\t" * indent + "}"


def key(k):
    return k if k.isidentifier() else f"[{k!r}]"


def write_track(d, indent, pos_digits=3):
    pad = "\t" * (indent + 1)
    out = ["{"]
    for k in ("stage", "rate", "t0", "n"):
        if k in d:
            v = d[k]
            out.append(f'{pad}{k} = ' + (f'"{v}"' if isinstance(v, str) else num(v, 4)) + ',')
    out.append(f"{pad}pos = {arr(d['pos'], pos_digits, indent + 1)},")
    out.append(f"{pad}rot = {arr(d['rot'], 5, indent + 1, 20)},")
    if "scale" in d:
        out.append(f"{pad}scale = {arr(d['scale'], 4, indent + 1)},")
    out.append(f"{pad}channels = {{")
    for name in sorted(d["channels"]):
        out.append(f"{pad}\t{key(name)} = {arr(d['channels'][name], 4, indent + 2)},")
    out.append(f"{pad}}},")
    out.append("\t" * indent + "}")
    return "\n".join(out)


def to_luau(data):
    L = ["-- IntroData (STUB, written by tools/tests/make_intro_stub.py)",
         "-- Format of docs/intro/DESIGN.md §8. The real file is generated by",
         "-- tools/blender/intro/export_intro.py; never hand-edit either.",
         "return {",
         f"\tversion = {data['version']},", f"\tfps = {data['fps']},", f"\tduration = {num(data['duration'], 4)},",
         "\tmarkers = {"]
    for m in data["markers"]:
        L.append(f'\t\t{{ t = {num(m["t"], 4)}, name = "{m["name"]}" }},')
    L.append("\t},")
    L.append("\tcuts = " + arr(data["cuts"], 4, 1) + ",")
    L.append(f"\tstageSwitch = {num(data['stageSwitch'], 4)},")
    L.append("\ttracks = {")
    for name in sorted(data["tracks"]):
        L.append(f"\t\t{key(name)} = " + write_track(data["tracks"][name], 2) + ",")
    L.append("\t},")
    c = data["character"]
    L.append("\tcharacter = {")
    L.append(f"\t\trate = {c['rate']}, t0 = {num(c['t0'], 4)}, n = {c['n']},")
    L.append("\t\troot = {")
    L.append("\t\t\tpos = " + arr(c["root"]["pos"], 3, 3) + ",")
    L.append("\t\t\trot = " + arr(c["root"]["rot"], 5, 3, 20) + ",")
    L.append("\t\t},")
    L.append("\t\tjoints = {")
    for j in JOINTS:
        L.append(f"\t\t\t{j} = " + arr(c["joints"][j], 5, 3, 20) + ",")
    L.append("\t\t},")
    L.append("\t\trootLoc = " + arr(c["rootLoc"], 3, 2) + ",")
    L.append("\t\tchannels = {")
    for name in sorted(c["channels"]):
        L.append(f"\t\t\t{name} = " + arr(c["channels"][name], 4, 3) + ",")
    L.append("\t\t},")
    L.append("\t},")
    sf = data["starfield"]
    L.append("\tstarfield = {")
    L.append("\t\tstars = " + arr(sf["stars"], 3, 2, 18) + ",")
    L.append("\t\tgalaxies = {")
    for g in sf["galaxies"]:
        L.append("\t\t\t{")
        L.append("\t\t\t\tcenter = " + arr(g["center"], 3, 4) + ",")
        L.append("\t\t\t\tnormal = " + arr(g["normal"], 5, 4) + ",")
        L.append("\t\t\t\txaxis = " + arr(g["xaxis"], 5, 4) + ",")
        L.append(f"\t\t\t\tradius = {num(g['radius'], 3)}, arms = {g['arms']}, twist = {num(g['twist'], 4)},")
        L.append("\t\t\t\tpoints = " + arr(g["points"], 3, 4, 22) + ",")
        L.append("\t\t\t},")
    L.append("\t\t},")
    L.append("\t\tnebulae = {")
    for nb in sf["nebulae"]:
        L.append("\t\t\t{ center = " + arr(nb["center"], 3, 3) + f", radius = {num(nb['radius'], 3)}, color = "
                 + arr(nb["color"], 4, 3) + f", appear = {num(nb['appear'], 4)} }},")
    L.append("\t\t},")
    L.append("\t},")
    w = data["world"]
    L.append(f"\tworld = {{ windStart = {num(w['windStart'], 4)}, landingHeight = {num(w['landingHeight'], 3)} }},")
    L.append("}")
    return "\n".join(L) + "\n"


def main():
    out = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else OUT
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(to_luau(build()))
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
