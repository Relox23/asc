#!/usr/bin/env python3
"""Tiny software renderer to eyeball the generated map without Studio.

usage: render.py <luau binary> <out dir> [view,view,...]
Renders a set of camera views (parts + terrain heightmap + terrain fills).
tools/blender/render_map.py renders the same views in Blender, with the
detailed meshes.
"""
import json
import math
import pathlib
import subprocess
import sys

import numpy as np

ROOT = pathlib.Path(__file__).resolve().parent
W, H = 760, 430

MAT = {
    "Grass": (92, 156, 66), "LeafyGrass": (70, 128, 54), "Ground": (112, 88, 62),
    "Sand": (228, 194, 132), "Sandstone": (200, 150, 100), "Limestone": (230, 214, 178),
    "Pavement": (204, 184, 146), "Salt": (236, 237, 242), "Slate": (176, 180, 190),
    "Mud": (30, 28, 32), "Basalt": (56, 52, 54), "Snow": (242, 247, 255),
    "Glacier": (190, 222, 238), "Ice": (166, 208, 232), "Rock": (116, 117, 124),
    "Cobblestone": (128, 124, 118), "Water": (40, 150, 175),
}

# Layout constants are read from the Luau side through the view list below.
VIEWS = json.loads((ROOT / "render_views.json").read_text())


def luau_views(views=None):
    items = []
    for v in views or VIEWS:
        c = v["center"]
        items.append("{ center = Vector3.new(%f, 0, %f), radius = %f, step = %f }" % (c[0], c[1], v["radius"], v["step"]))
    return "{ " + ", ".join(items) + " }"


def run_luau(luau, out, prelude="", views=None):
    """Build the map in the mock and return the driver's dump (prelude = Luau run first)."""
    out = pathlib.Path(out)
    out.mkdir(parents=True, exist_ok=True)
    drv = out / "render.driver.luau"
    drv.write_text(prelude + "\n" + (ROOT / "render_driver.luau").read_text().replace("__VIEWS__", luau_views(views)))
    bundle = out / "render.bundle.luau"
    subprocess.run([sys.executable, str(ROOT / "bundle.py"), str(drv), str(bundle)], check=True)
    res = subprocess.run([luau, str(bundle)], capture_output=True, text=True)
    if res.returncode != 0:
        print(res.stdout[-2000:])
        print(res.stderr[-4000:])
        sys.exit(1)
    return res.stdout


# ---------------------------------------------------------------- meshes (unit, local space)
def box_mesh():
    v = np.array([[x, y, z] for x in (-.5, .5) for y in (-.5, .5) for z in (-.5, .5)])
    idx = lambda x, y, z: (x > 0) * 4 + (y > 0) * 2 + (z > 0)
    f = []
    for axis in range(3):
        for s in (-.5, .5):
            quad = []
            for a in (-.5, .5):
                for b in (-.5, .5):
                    p = [0, 0, 0]
                    p[axis] = s
                    o = [i for i in range(3) if i != axis]
                    p[o[0]] = a
                    p[o[1]] = b
                    quad.append(idx(*p))
            f += [(quad[0], quad[1], quad[3]), (quad[0], quad[3], quad[2])]
    return v, np.array(f)


def wedge_mesh():
    # Roblox wedge: full bottom, full back (+Z) face, slope facing front (-Z) and up.
    v = np.array([
        [-.5, -.5, -.5], [.5, -.5, -.5], [.5, -.5, .5], [-.5, -.5, .5],  # bottom
        [-.5, .5, .5], [.5, .5, .5],  # top back edge
    ])
    f = [(0, 1, 2), (0, 2, 3), (3, 2, 5), (3, 5, 4), (0, 1, 5), (0, 5, 4), (0, 3, 4), (1, 2, 5)]
    return v, np.array(f)


def sphere_mesh(n=10):
    v, f = [], []
    for i in range(n + 1):
        th = math.pi * i / n
        for j in range(n * 2):
            ph = 2 * math.pi * j / (n * 2)
            v.append([.5 * math.sin(th) * math.cos(ph), .5 * math.cos(th), .5 * math.sin(th) * math.sin(ph)])
    m = n * 2
    for i in range(n):
        for j in range(m):
            a, b = i * m + j, i * m + (j + 1) % m
            c, d = (i + 1) * m + j, (i + 1) * m + (j + 1) % m
            f += [(a, b, d), (a, d, c)]
    return np.array(v), np.array(f)


def cyl_mesh(n=14, axis=0):
    v, f = [], []
    for s in (-.5, .5):
        for j in range(n):
            a = 2 * math.pi * j / n
            p = [0, 0, 0]
            p[axis] = s
            o = [i for i in range(3) if i != axis]
            p[o[0]] = .5 * math.cos(a)
            p[o[1]] = .5 * math.sin(a)
            v.append(p)
    for j in range(n):
        a, b = j, (j + 1) % n
        f += [(a, b, n + b), (a, n + b, n + a)]
    for j in range(1, n - 1):
        f += [(0, j, j + 1), (n, n + j, n + j + 1)]
    return np.array(v), np.array(f)


MESH = {"B": box_mesh(), "W": wedge_mesh(), "S": sphere_mesh(), "E": sphere_mesh(), "C": cyl_mesh(),
        "ball": sphere_mesh(), "cyl": cyl_mesh(axis=1), "block": box_mesh()}

SUN = np.array([0.45, 0.8, 0.35])
SUN /= np.linalg.norm(SUN)


class Camera:
    def __init__(self, eye, target, fov=60):
        self.eye = np.array(eye, float)
        f = np.array(target, float) - self.eye
        self.f = f / np.linalg.norm(f)
        r = np.cross(self.f, [0, 1, 0])
        self.r = r / np.linalg.norm(r)
        self.u = np.cross(self.r, self.f)
        self.k = (W / 2) / math.tan(math.radians(fov) / 2)

    def project(self, pts):
        d = pts - self.eye
        x, y, z = d @ self.r, d @ self.u, d @ self.f
        z = np.maximum(z, 1e-3)
        return np.stack([W / 2 + self.k * x / z, H / 2 - self.k * y / z, z], axis=1), (d @ self.f)

    def ray(self):
        xs = (np.arange(W) + .5 - W / 2) / self.k
        ys = -(np.arange(H) + .5 - H / 2) / self.k
        X, Y = np.meshgrid(xs, ys)
        d = self.f[None, None, :] + X[..., None] * self.r + Y[..., None] * self.u
        return d / np.linalg.norm(d, axis=2, keepdims=True)


def render_view(view, parts, fills, terrain):
    from PIL import Image

    cam = Camera(view["eye"], view["target"], view.get("fov", 60))
    sky_top, sky_bot = np.array(view.get("sky", [110, 160, 220])), np.array([215, 225, 235])
    img = np.zeros((H, W, 3))
    t = np.linspace(0, 1, H)[:, None, None]
    img[:] = sky_top * (1 - t) + sky_bot * t
    zbuf = np.full((H, W), np.inf)

    # terrain: ray-march the heightmap
    x0, z0, step, hts, mats, water = terrain
    n = hts.shape[0]
    dirs = cam.ray()
    o = cam.eye
    tmax = view.get("tmax", 6000)
    hit_t = np.full((H, W), np.inf)
    prev = np.zeros((H, W))
    active = np.ones((H, W), bool)

    def sample(arr, px, pz):
        fx = np.clip((px - x0) / step - .5, 0, n - 1.001)
        fz = np.clip((pz - z0) / step - .5, 0, n - 1.001)
        i, j = fx.astype(int), fz.astype(int)
        ax, az = fx - i, fz - j
        return (arr[j, i] * (1 - ax) * (1 - az) + arr[j, i + 1] * ax * (1 - az)
                + arr[j + 1, i] * (1 - ax) * az + arr[j + 1, i + 1] * ax * az)

    surf = np.maximum(hts, water)
    tt = 1.0
    while tt < tmax and active.any():
        dt = max(step * 0.5, tt * 0.004)
        p = o + dirs * tt
        inside = ((p[..., 0] > x0) & (p[..., 0] < x0 + n * step) & (p[..., 2] > z0) & (p[..., 2] < z0 + n * step))
        h = sample(surf, p[..., 0], p[..., 2])
        hitm = active & inside & (p[..., 1] < h)
        hit_t[hitm] = tt
        active &= ~hitm
        tt += dt
    hm = np.isfinite(hit_t)
    p = o + dirs * hit_t[..., None]
    px, pz = p[..., 0][hm], p[..., 2][hm]
    fx = np.clip(((px - x0) / step).astype(int), 0, n - 1)
    fz = np.clip(((pz - z0) / step).astype(int), 0, n - 1)
    col = mats[fz, fx]
    hgt = hts[fz, fx]
    wl = water[fz, fx]
    gx = sample(hts, px + step, pz) - sample(hts, px - step, pz)
    gz = sample(hts, px, pz + step) - sample(hts, px, pz - step)
    nrm = np.stack([-gx, np.full_like(gx, 2 * step), -gz], 1)
    nrm /= np.linalg.norm(nrm, axis=1, keepdims=True)
    shade = np.clip(nrm @ SUN, 0, 1) * 0.65 + 0.4
    c = col * shade[:, None]
    wet = wl > hgt + 0.2
    depth = np.clip((wl - hgt) / 40, 0, 1)[:, None]
    c[wet] = (np.array([40, 150, 175]) * (1 - depth) + np.array([12, 60, 110]) * depth)[wet]
    img[hm] = c
    zbuf[hm] = (hit_t[hm, None] * dirs[hm] @ cam.f)

    # parts and fills
    tris = []
    for kind, cf, size, color, mat in parts + fills:
        v, f = MESH[kind]
        pos, rot = cf[:3], cf[3:].reshape(3, 3)
        world = (v * size) @ rot.T + pos
        tris.append((world, f, color, mat))
    for world, f, color, mat in tris:
        proj, depth = cam.project(world)
        if (depth < 1).all():
            continue
        for a, b, cc in f:
            if depth[a] < 1 or depth[b] < 1 or depth[cc] < 1:
                continue
            pa, pb, pc = proj[a], proj[b], proj[cc]
            minx = int(max(min(pa[0], pb[0], pc[0]), 0))
            maxx = int(min(max(pa[0], pb[0], pc[0]) + 1, W))
            miny = int(max(min(pa[1], pb[1], pc[1]), 0))
            maxy = int(min(max(pa[1], pb[1], pc[1]) + 1, H))
            if minx >= maxx or miny >= maxy:
                continue
            nrm = np.cross(world[b] - world[a], world[cc] - world[a])
            ln = np.linalg.norm(nrm)
            if ln == 0:
                continue
            nrm /= ln
            if mat == "Neon":
                c = np.array(color)
            else:
                c = np.array(color) * (abs(nrm @ SUN) * 0.6 + 0.4)
            xs = np.arange(minx, maxx) + .5
            ys = np.arange(miny, maxy) + .5
            X, Y = np.meshgrid(xs, ys)
            d = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
            if abs(d) < 1e-9:
                continue
            l1 = ((pb[1] - pc[1]) * (X - pc[0]) + (pc[0] - pb[0]) * (Y - pc[1])) / d
            l2 = ((pc[1] - pa[1]) * (X - pc[0]) + (pa[0] - pc[0]) * (Y - pc[1])) / d
            l3 = 1 - l1 - l2
            m = (l1 >= -1e-3) & (l2 >= -1e-3) & (l3 >= -1e-3)
            if not m.any():
                continue
            z = 1 / (l1 / pa[2] + l2 / pb[2] + l3 / pc[2])
            sub = zbuf[miny:maxy, minx:maxx]
            upd = m & (z < sub)
            sub[upd] = z[upd]
            img[miny:maxy, minx:maxx][upd] = c
    # distance fog
    fog = np.clip((zbuf - view.get("fog", 1500)) / view.get("fogLen", 5000), 0, 0.7)
    fog[~np.isfinite(zbuf)] = 0
    img = img * (1 - fog[..., None]) + np.array([210, 220, 230]) * fog[..., None]
    return Image.fromarray(np.clip(img, 0, 255).astype(np.uint8))


def parse(out):
    sections = []
    cur = None
    for line in out.splitlines():
        if line.startswith("VIEW "):
            cur = {"parts": [], "fills": [], "rows": []}
            sections.append(cur)
        elif cur is None:
            if line.startswith("[") or "MOCK" in line:
                print(line)
            continue
        elif line.startswith("P "):
            s = line.split()
            kind = s[1]
            cf = np.array([float(x) for x in s[2:14]])
            size = np.array([float(x) for x in s[14:17]])
            color = [float(x) * 255 for x in s[17:20]]
            cur["parts"].append((kind, cf, size, color, s[21]))
        elif line.startswith("F "):
            s = line.split()
            kind = s[1]
            cf = np.array([float(x) for x in s[2:14]])
            size = np.array([float(x) for x in s[14:17]])
            cur["fills"].append((kind, cf, size, list(MAT.get(s[17], (255, 0, 255))), s[17]))
        elif line.startswith("T "):
            s = line.split()
            cur["t"] = (float(s[1]), float(s[2]), float(s[3]), int(s[4]))
        elif line.startswith("R "):
            cur["rows"].append([c.split(":") for c in line[2:].split(" ")])
    return sections


def terrain_arrays(sec):
    x0, z0, step, n = sec["t"]
    hts = np.array([[float(c[0]) for c in r] for r in sec["rows"]])
    water = np.array([[float(c[2]) for c in r] for r in sec["rows"]])
    mats = np.array([[MAT.get(c[1], (255, 0, 255)) for c in r] for r in sec["rows"]], float)
    return x0, z0, step, hts, mats, water


def main():
    luau, out = sys.argv[1], pathlib.Path(sys.argv[2])
    only = sys.argv[3].split(",") if len(sys.argv) > 3 else None
    views = [v for v in VIEWS if not only or v["name"] in only]
    sections = parse(run_luau(luau, out, views=views))
    for view, sec in zip(views, sections):
        im = render_view(view, sec["parts"], sec["fills"], terrain_arrays(sec))
        im.save(out / f"{view['name']}.png")
        print("rendered", view["name"], len(sec["parts"]), "parts")


if __name__ == "__main__":
    main()
