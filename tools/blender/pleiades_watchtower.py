"""
Builds the Pleiades-style watchtower on its own and exports it for Roblox
(assets/PleiadesWatchtower.fbx/.obj/.blend). The same tower is also part of
the full asset library (build_assets.py -> IslandAssets.fbx).

Run:
    python tools/blender/pleiades_watchtower.py <out dir> [--render]
(needs the `bpy` module: pip install bpy)

Modelled at 1 unit = 1 stud (about 1150 studs tall), Z up; exported at 1/10
scale and Y-up so Studio's 3D importer never hits the 2048-stud mesh limit.
Object names start with a style prefix the generator uses to colour them.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
import kit  # noqa: E402
import assets_dunes  # noqa: E402
import exporter  # noqa: E402

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = os.path.abspath(argv[0] if argv else "assets")
os.makedirs(OUT, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
collection = bpy.data.collections.new("PleiadesWatchtower")
bpy.context.scene.collection.children.link(collection)

pieces = {}


def add(piece, style):
    if piece not in pieces:
        pieces[piece] = (style, kit.bmesh.new())
    return pieces[piece][1]


assets_dunes.watchtower(add)
objects = kit.finish_named(pieces, collection)
total = 0
for o in objects:
    tris = len(o.data.polygons)
    total += tris
    print(f"  {o.name:24s} {tris:6d} tris")
print(f"total {total} triangles in {len(objects)} meshes, {kit.REPORT['flipped']} pieces flipped")
exporter.export(objects, os.path.join(OUT, "PleiadesWatchtower"))
if "--render" in argv:
    exporter.render_scene(objects, os.path.join(OUT, "PleiadesWatchtower_preview.png"), clouds=True)
