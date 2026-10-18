"""
Builds the whole island asset library in Blender and exports it for Roblox.

    python tools/blender/build_assets.py <out dir> [--only hub,snow] [--render <dir>] [--no-export]

Output: <out>/IslandAssets.fbx (+ .obj, .blend). Import the FBX into Studio once
(Home > Import 3D); the generator finds every asset in it by name.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import kit  # noqa: E402
import exporter  # noqa: E402
import assets_coast  # noqa: E402
import assets_dunes  # noqa: E402
import assets_forest  # noqa: E402
import assets_hollow  # noqa: E402
import assets_hub  # noqa: E402
import assets_ruins  # noqa: E402
import assets_snow  # noqa: E402

GROUPS = {
    "hub": assets_hub.ASSETS,
    "forest": assets_forest.ASSETS,
    "snow": assets_snow.ASSETS,
    "hollow": assets_hollow.ASSETS,
    "ruins": assets_ruins.ASSETS,
    "dunes": assets_dunes.ASSETS,
    "coast": assets_coast.ASSETS,
}

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = os.path.abspath(argv[0] if argv and not argv[0].startswith("--") else "assets")
only = None
render_dir = None
if "--only" in argv:
    only = argv[argv.index("--only") + 1].split(",")
if "--render" in argv:
    render_dir = os.path.abspath(argv[argv.index("--render") + 1])
    os.makedirs(render_dir, exist_ok=True)
names = None
if "--assets" in argv:
    names = set(argv[argv.index("--assets") + 1].split(","))
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
collection = bpy.data.collections.new("IslandAssets")
bpy.context.scene.collection.children.link(collection)

built = []
row_y = 0.0
for group, assets in GROUPS.items():
    if only and group not in only:
        continue
    x = 0.0
    row_depth = 0.0
    for name, fn in assets:
        if names and name not in names:
            continue
        a = kit.Asset(name)
        fn(a)
        # lay assets out in rows so the imported model is easy to browse
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for bm in a.pieces.values():
            for v in bm.verts:
                lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
                hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
        width = hi.x - lo.x
        offset = Vector((x - lo.x, row_y, 0))
        tris = a.tris()
        objs = kit.finish(a, collection, offset)
        x += width + 40
        row_depth = max(row_depth, hi.y - lo.y)
        built.append((group, name, objs, tris))
        print(f"  {group:7s} {name:18s} {tris:7d} tris  {len(objs) - 3:3d} meshes")
    row_y += row_depth + 80

total = sum(t for _, _, _, t in built)
print(f"total {total} triangles, {len(built)} assets, {kit.REPORT['flipped']} pieces flipped")

if render_dir:
    for group, name, objs, _ in built:
        exporter.render_objects(objs, os.path.join(render_dir, f"{name}.png"))
        print("rendered", name)

if "--no-export" not in argv:
    everything = [o for _, _, objs, _ in built for o in objs]
    exporter.export(everything, os.path.join(OUT, "IslandAssets"))
