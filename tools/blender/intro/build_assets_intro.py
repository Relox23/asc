"""
Builds the intro cutscene meshes (tools/blender/intro/assets_intro.py) and exports them for Roblox.

    python tools/blender/intro/build_assets_intro.py [<out dir>=assets] [--assets SoulCore,Rift]
        [--render <dir>] [--size 420] [--samples 16] [--no-export]

Output: <out>/IntroAssets.fbx (RiftView texture embedded), .obj/.mtl and .blend.
--render writes one preview per asset to <dir>/tiles/<name>.png and the contact sheet
<dir>/IntroAssets_sheet.png (tools/blender/contact_sheet.py, needs Pillow in python3).
Every run prints per-asset triangle counts and the mesh checks (closed / consistent normals,
the dome's inward normals, <= kit.MAX_TRIS per mesh).
"""
import math
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
from mathutils import Quaternion, Vector  # noqa: E402

import kit  # noqa: E402
import exporter  # noqa: E402
import assets_intro  # noqa: E402
import space  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))


# ----------------------------------------------------------------------------- checks
def edge_report(objs):
    """(triangles, open edges, inconsistent edges) of the union of objs, welded by position."""
    directed = {}
    tris = 0
    for o in objs:
        mw = o.matrix_world
        co = [tuple(round(c, 4) for c in (mw @ v.co)) for v in o.data.vertices]
        for p in o.data.polygons:
            vs = [co[i] for i in p.vertices]
            tris += len(vs) - 2
            for k in range(len(vs)):
                e = (vs[k], vs[(k + 1) % len(vs)])
                directed[e] = directed.get(e, 0) + 1
    open_e = sum(1 for (a, b) in directed if (b, a) not in directed)
    bad = sum(1 for e, n in directed.items() if n > 1)
    return tris, open_e, bad


def check(name, objs, offset):
    pieces = [o for o in objs if not o.name.endswith(("__Origin", "__Up", "__Front"))]
    over = [o.name for o in pieces if sum(len(p.vertices) - 2 for p in o.data.polygons) > kit.MAX_TRIS]
    tris, open_e, bad = edge_report(pieces)
    msg = f"    check {name}: {tris} tris in {len(pieces)} meshes, open edges {open_e}, doubly used edges {bad}"
    if over:
        msg += f", OVER LIMIT: {over}"
    if name == "SpaceDome":
        dome = pieces[0]
        mw = dome.matrix_world
        inward = sum(1 for p in dome.data.polygons if (mw.to_3x3() @ p.normal).dot(mw @ p.center - offset) < 0)
        msg += f", normals inward {inward}/{len(dome.data.polygons)}"
    print(msg)
    return not over


# ----------------------------------------------------------------------------- preview renders
VIEWS = {
    # name: (camera direction from the target, lens mm, direction the sunlight comes from, world colour)
    "SpaceDome": None,  # special: from inside, normals debug colours
    "SoulCore": ((-0.55, -1.0, 0.32), 50, (-1.0, -0.6, 1.0), (0.01, 0.012, 0.02)),
    "ShatteredPlanet": ((0.0, -1.0, 0.15), 40, (1.0, -0.9, 0.45), (0.004, 0.005, 0.01)),
    "Rift": ((0.15, -0.55, 1.0), 40, (0.6, -0.4, 1.0), (0.01, 0.01, 0.02)),
    "ResonanceSword": ((-0.3, -1.0, 0.2), 80, (-0.8, -1.0, 0.9), (0.35, 0.38, 0.45)),
    "Shockwave": ((0.0, -0.7, 1.0), 40, (0.3, -0.5, 1.0), (0.01, 0.01, 0.02)),
    "SlashArc": ((0.2, -0.45, 1.0), 40, (0.3, -0.5, 1.0), (0.01, 0.01, 0.02)),
}


def _scene(size, samples):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.cycles.transparent_max_bounces = 32
    scene.render.resolution_x = scene.render.resolution_y = size
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    if scene.world is None:
        scene.world = bpy.data.worlds.new("IntroPreview")
    scene.world.use_nodes = True
    sun = bpy.data.objects.get("PreviewSun")
    if sun is None:
        sun = bpy.data.objects.new("PreviewSun", bpy.data.lights.new("PreviewSun", "SUN"))
        sun.data.energy = 4.0
        sun.data.angle = math.radians(1.0)
        scene.collection.objects.link(sun)
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        cam.data.clip_end = 20000
        scene.collection.objects.link(cam)
    scene.camera = cam
    return scene, sun, cam


def _only(objs):
    wanted = set(objs)
    for o in bpy.data.objects:
        if o.type == "MESH":
            o.hide_render = o not in wanted or o.name.endswith(("__Origin", "__Up", "__Front"))


def render_asset(name, objs, offset, path, size=420, samples=16):
    scene, sun, cam = _scene(size, samples)
    _only(objs)
    bg = scene.world.node_tree.nodes["Background"]
    if name == "SpaceDome":
        # debug look from inside: green = faces pointing at the camera (inward), red = outward
        dome = [o for o in objs if o.name == "SpaceDome__Void"][0]
        dbg = bpy.data.materials.new("DomeNormalsDebug")
        dbg.use_nodes = True
        nt = dbg.node_tree
        for n in list(nt.nodes):
            nt.nodes.remove(n)
        out = nt.nodes.new("ShaderNodeOutputMaterial")
        geo = nt.nodes.new("ShaderNodeNewGeometry")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.inputs["A"].default_value = (0.05, 0.6, 0.15, 1)
        mix.inputs["B"].default_value = (0.8, 0.05, 0.05, 1)
        nt.links.new(geo.outputs["Backfacing"], mix.inputs["Factor"])
        wire = nt.nodes.new("ShaderNodeWireframe")
        wire.inputs["Size"].default_value = 3.0
        wire.use_pixel_size = False
        mix2 = nt.nodes.new("ShaderNodeMix")
        mix2.data_type = "RGBA"
        nt.links.new(mix.outputs["Result"], mix2.inputs["A"])
        mix2.inputs["B"].default_value = (1, 1, 1, 1)
        nt.links.new(wire.outputs[0], mix2.inputs["Factor"])
        em = nt.nodes.new("ShaderNodeEmission")
        nt.links.new(mix2.outputs["Result"], em.inputs["Color"])
        nt.links.new(em.outputs[0], out.inputs["Surface"])
        old = dome.data.materials[0]
        dome.data.materials[0] = dbg
        cam.location = offset + Vector((0, -300, -150))
        cam.rotation_euler = (Vector((0, 600, 300)) + offset - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.lens = 14
        bg.inputs["Color"].default_value = (0, 0, 0, 1)
        sun.hide_render = True
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        dome.data.materials[0] = old
        sun.hide_render = False
        return
    direction, lens, sun_from, world = VIEWS[name]
    bg.inputs["Color"].default_value = (*world, 1)
    bg.inputs["Strength"].default_value = 1.0
    sun.rotation_euler = (-Vector(sun_from)).to_track_quat("-Z", "Y").to_euler()
    lo, hi = exporter.bounds([o for o in objs if not o.hide_render])
    exporter.frame_camera(scene, lo, hi, direction, lens)
    cam = scene.camera
    cam.data.clip_end = 20000
    if name == "ShatteredPlanet":
        # frame the planet itself from the front (-Y); debris may spill out of the picture
        c = Vector(offset)
        d = Vector(direction).normalized()
        cam.location = c + d * 1350
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    if name == "ResonanceSword":
        q = cam.rotation_euler.to_quaternion() @ Quaternion((0, 0, 1), math.radians(-42))
        cam.rotation_euler = q.to_euler()
        cam.location = Vector(offset) + Vector((0, 0, 1.9)) + Vector(direction).normalized() * 10.5
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    space.post_glow(path, strength=0.5)
    if name == "ResonanceSword":  # the same sword after the resonance (crystals glowing in the tint)
        crystal = assets_intro.material("Crystal")
        crystal.node_tree.nodes["resonance"].outputs[0].default_value = 1.0
        scene.render.filepath = path.replace(".png", "_resonant.png")
        bpy.ops.render.render(write_still=True)
        space.post_glow(scene.render.filepath, strength=0.5)
        crystal.node_tree.nodes["resonance"].outputs[0].default_value = 0.0
    if name == "Rift":  # opened: cracks and shards gone, the forest seen through the rim
        hidden = [o for o in objs if "__Crack_" in o.name or "__Shard_" in o.name]
        for o in hidden:
            o.hide_render = True
        scene.render.filepath = path.replace(".png", "_open.png")
        bpy.ops.render.render(write_still=True)
        space.post_glow(scene.render.filepath, strength=0.5)
        for o in hidden:
            o.hide_render = False


# ----------------------------------------------------------------------------- main
def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]

    def opt(name, default=None):
        return argv[argv.index(name) + 1] if name in argv else default

    out = os.path.abspath(argv[0] if argv and not argv[0].startswith("--") else os.path.join(ROOT, "assets"))
    names = set(opt("--assets").split(",")) if opt("--assets") else None
    render_dir = os.path.abspath(opt("--render")) if opt("--render") else None
    size = int(opt("--size", 420))
    samples = int(opt("--samples", 16))

    bpy.ops.wm.read_factory_settings(use_empty=True)
    collection = bpy.data.collections.new("IntroAssets")
    bpy.context.scene.collection.children.link(collection)

    built = []
    x = 0.0
    ok = True
    for name, fn in assets_intro.ASSETS:
        if names and name not in names:
            continue
        a = assets_intro.IntroAsset(name)
        fn(a)
        lo = Vector((1e9, 1e9, 1e9))
        hi = Vector((-1e9, -1e9, -1e9))
        for bm in a.pieces.values():
            for v in bm.verts:
                lo = Vector((min(lo.x, v.co.x), min(lo.y, v.co.y), min(lo.z, v.co.z)))
                hi = Vector((max(hi.x, v.co.x), max(hi.y, v.co.y), max(hi.z, v.co.z)))
        offset = Vector((x - lo.x, 0, 0))
        tris = a.tris()
        objs = assets_intro.finish(a, collection, offset)
        x += hi.x - lo.x + 60
        built.append((name, objs, offset))
        print(f"  {name:16s} {tris:7d} tris  {len(objs) - 3:3d} meshes")
        ok = check(name, objs, offset) and ok
    print(f"total {sum(edge_report(o)[0] for _, o, _ in built)} triangles, {len(built)} assets, "
          f"{kit.REPORT['flipped']} pieces flipped")
    if not ok:
        sys.exit("mesh over the triangle limit")

    if render_dir:
        tiles = os.path.join(render_dir, "tiles")
        os.makedirs(tiles, exist_ok=True)
        for name, objs, offset in built:
            render_asset(name, objs, offset, os.path.join(tiles, f"{name}.png"), size, samples)
            print("rendered", name, flush=True)
        py = shutil.which("python3")
        if py:
            subprocess.run([py, os.path.join(ROOT, "tools", "blender", "contact_sheet.py"), tiles,
                            os.path.join(render_dir, "IntroAssets_sheet.png"), "4"], check=False)
        for o in bpy.data.objects:  # do not leave preview state in the exported .blend
            if o.type == "MESH":
                o.hide_render = False
        for n in ("PreviewSun", "PreviewCam"):
            if n in bpy.data.objects:
                bpy.data.objects.remove(bpy.data.objects[n])

    if "--no-export" not in argv:
        os.makedirs(out, exist_ok=True)
        everything = [o for _, objs, _ in built for o in objs]
        exporter.export(everything, os.path.join(out, "IntroAssets"), embed_textures=True)


main()
