#!/usr/bin/env python3
"""Render a shaded top-down preview of the island.

usage: preview.py <luau binary> <out.png> [resolution]
"""
import pathlib
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent
LUAU = sys.argv[1]
OUT = pathlib.Path(sys.argv[2])
RES = int(sys.argv[3]) if len(sys.argv) > 3 else 400

COLORS = {
    "Grass": (92, 156, 66), "LeafyGrass": (70, 128, 54), "Ground": (112, 88, 62),
    "Sand": (228, 194, 132), "Sandstone": (200, 150, 100), "Limestone": (230, 214, 178),
    "Pavement": (204, 184, 146), "Salt": (236, 237, 242), "Slate": (176, 180, 190),
    "Mud": (30, 28, 32), "Basalt": (56, 52, 54), "Snow": (242, 247, 255),
    "Glacier": (190, 222, 238), "Ice": (166, 208, 232), "Rock": (116, 117, 124),
    "Cobblestone": (128, 124, 118),
}

bundle = OUT.with_suffix(".bundle.luau")
driver = (ROOT / "preview_driver.luau").read_text().replace(
    "tonumber(_G.PREVIEW_RES) or 400", f"{RES}")
drv = OUT.with_suffix(".driver.luau")
drv.write_text(driver)
subprocess.run([sys.executable, str(ROOT / "bundle.py"), str(drv), str(bundle)], check=True)
res = subprocess.run([LUAU, str(bundle)], capture_output=True, text=True)
if res.returncode != 0:
    print(res.stdout[-3000:])
    print(res.stderr[-3000:])
    sys.exit(1)

rows, marks, info = [], [], []
for line in res.stdout.splitlines():
    if line.startswith("ROW "):
        rows.append([c.split(":") for c in line[4:].split(" ")])
    elif line.startswith("MARK "):
        _, name, x, z = line.split()
        marks.append((name, float(x), float(z)))
    elif line.startswith("INFO "):
        ext = float(line.split("ext=")[1].split()[0])
        info.append(line)
    else:
        info.append(line)

h = np.array([[float(c[0]) for c in r] for r in rows])
water = np.array([[float(c[2]) for c in r] for r in rows])
mats = [[c[1] for c in r] for r in rows]
n = len(rows)
img = np.zeros((n, n, 3))
gy, gx = np.gradient(h)
shade = np.clip(1.0 - (gx - gy) * 0.03, 0.55, 1.35)
for j in range(n):
    for i in range(n):
        if h[j, i] < water[j, i]:
            depth = water[j, i] - h[j, i]
            t = min(depth / 70, 1)
            img[j, i] = (40 * (1 - t) + 10 * t, 150 * (1 - t) + 60 * t, 170 * (1 - t) + 110 * t)
        else:
            img[j, i] = np.array(COLORS.get(mats[j][i], (255, 0, 255))) * shade[j, i]
im = Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((n * 2, n * 2), Image.NEAREST)
d = ImageDraw.Draw(im)
scale = n * 2 / (2 * ext)
for name, x, z in marks:
    px, pz = (x + ext) * scale, (z + ext) * scale
    d.ellipse([px - 4, pz - 4, px + 4, pz + 4], outline=(255, 0, 0), width=2)
    d.text((px + 6, pz - 6), name, fill=(255, 30, 30))
im.save(OUT)
print("\n".join(info))
