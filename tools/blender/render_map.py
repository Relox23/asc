"""
Renders the generated map in Blender (Cycles), with the detailed meshes.

    python tools/blender/render_map.py <luau binary> <out dir>
        [--library assets/IslandAssets.obj] [--views a,b] [--samples 16] [--size 1280x720]

The map is built in the Roblox mock exactly like tools/render.py does (same
views, tools/render_views.json). With --library, the build first gets a
stand-in for the imported IslandAssets model made from the OBJ export
(tools/tests/library_fixture.py), and every MeshPart is drawn with that
mesh's real triangles. Without it, you see the parts-only version.
"""
import math
import os
import pathlib
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
sys.path.insert(0, str(HERE.parent / "tests"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import library_fixture  # noqa: E402
import render  # noqa: E402  (tools/render.py)

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
LUAU, OUT = argv[0], pathlib.Path(argv[1]).resolve()


def opt(name, default=None):
    return argv[argv.index(name) + 1] if name in argv else default


LIBRARY = opt("--library")
ONLY = opt("--views")
SAMPLES = int(opt("--samples", 16))
SIZE = tuple(int(x) for x in opt("--size", "1280x720").split("x"))

# Roblox (x, y, z) -> Blender (x, -z, y): Y-up to Z-up, a proper rotation
C = np.array([[1.0, 0, 0], [0, 0, -1.0], [0, 1.0, 0]])


def lin(rgb255):
    return tuple((max(c, 0) / 255) ** 2.2 for c in rgb255)


def make_mesh(name, verts, faces, smooth=False):
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in np.asarray(verts, float)], [], [tuple(f) for f in np.asarray(faces, int)])
    me.update()
    if smooth:
        me.shade_smooth()
    return me


def node_material(name, build):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    shader = build(nt)
    nt.links.new(shader.outputs[0], out.inputs["Surface"])
    return m


def object_color_bsdf(nt, roughness=0.75):
    info = nt.nodes.new("ShaderNodeObjectInfo")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = roughness
    nt.links.new(info.outputs["Color"], bsdf.inputs["Base Color"])
    return bsdf


def emission(nt):
    info = nt.nodes.new("ShaderNodeObjectInfo")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Strength"].default_value = 2.5
    nt.links.new(info.outputs["Color"], em.inputs["Color"])
    return em


def water_bsdf(nt):
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (0.02, 0.16, 0.22, 1)
    bsdf.inputs["Roughness"].default_value = 0.06
    return bsdf


def terrain_bsdf(nt):
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "Col"
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.95
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    return bsdf


class Library:
    """Mesh data for primitives and (lazily) for each library mesh."""

    def __init__(self, obj_path):
        self.mats = {
            "part": node_material("Part", object_color_bsdf),
            "neon": node_material("Neon", emission),
            "water": node_material("Water", water_bsdf),
            "terrain": node_material("Terrain", terrain_bsdf),
        }
        self.cache = {}
        self.objects = library_fixture.load(obj_path) if obj_path else {}

    def mesh(self, kind, material):
        key = (kind, material)
        if key not in self.cache:
            if kind.startswith("M:"):
                v, f = self.objects[kind[2:]]
                c, s = library_fixture.bounds(v)
                me = make_mesh(kind, (v - c) / s, f)
            else:
                v, f = render.MESH[kind]
                me = make_mesh(kind, v, f, smooth=kind in ("S", "E", "ball", "C", "cyl"))
            me.materials.append(self.mats[material])
            self.cache[key] = me
        return self.cache[key]


def part_matrix(cf, size):
    m = np.eye(4)
    m[:3, :3] = C @ cf[3:].reshape(3, 3) @ np.diag(np.maximum(size, 1e-3))
    m[:3, 3] = C @ cf[:3]
    return Matrix(m.tolist())


def build_terrain(coll, lib, terrain):
    x0, z0, step, hts, mats, water = terrain
    n = hts.shape[0]
    i, j = np.meshgrid(np.arange(n), np.arange(n))
    xs, zs = x0 + (i + 0.5) * step, z0 + (j + 0.5) * step
    quads = []
    for jj in range(n - 1):
        row = jj * n + np.arange(n - 1)
        quads.append(np.stack([row, row + 1, row + n + 1, row + n], 1))
    quads = np.concatenate(quads)

    def grid(name, heights, material):
        pts = np.stack([xs.ravel(), heights.ravel(), zs.ravel()], 1) @ C.T
        me = make_mesh(name, pts, quads, smooth=True)
        me.materials.append(lib.mats[material])
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        return me

    me = grid("Terrain", hts, "terrain")
    col = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
    rgb = (np.clip(mats.reshape(-1, 3), 0, 255) / 255) ** 2.2
    col.data.foreach_set("color", np.concatenate([rgb, np.ones((len(rgb), 1))], 1).ravel())
    wet = water > hts + 0.2
    if wet.any():
        grid("Water", np.where(wet, water, hts - 1.0), "water")


def render_view(view, sec, lib):
    scene = bpy.context.scene
    coll = bpy.data.collections.new("View")
    scene.collection.children.link(coll)
    t0 = time.time()
    build_terrain(coll, lib, render.terrain_arrays(sec))
    # the open sea beyond the sampled area
    sea = bpy.data.objects.new("Sea", lib.mesh("block", "water"))
    sea.matrix_world = part_matrix(np.array([0, -1.2, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1.0]), np.array([60000, 2, 60000.0]))
    coll.objects.link(sea)
    count = 0
    for kind, cf, size, color, mat in sec["parts"] + sec["fills"]:
        if kind.startswith("M:") and kind[2:] not in lib.objects:
            continue
        material = "neon" if mat == "Neon" else ("water" if mat == "Water" else "part")
        ob = bpy.data.objects.new("p", lib.mesh(kind, material))
        ob.matrix_world = part_matrix(cf, size)
        ob.color = (*lin(color), 1)
        coll.objects.link(ob)
        count += 1

    world = scene.world
    sky = lin(view.get("sky", [110, 160, 220]))
    night = sum(view.get("sky", [110, 160, 220])) < 150
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (*sky, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.0
    sun = bpy.data.objects["Sun"]
    sun.data.energy = 0.6 if night else 3.6
    sun.data.color = (0.75, 0.82, 1.0) if night else (1, 0.95, 0.88)

    cam = scene.camera
    eye = Vector((C @ np.array(view["eye"], float)).tolist())
    target = Vector((C @ np.array(view["target"], float)).tolist())
    cam.location = eye
    cam.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    cam.data.angle = math.radians(view.get("fov", 60))
    scene.render.filepath = str(OUT / f"{view['name']}.png")
    built = time.time() - t0
    bpy.ops.render.render(write_still=True)
    print(f"rendered {view['name']}: {count} objects, scene {built:.1f}s, render {time.time() - t0 - built:.1f}s", flush=True)
    bpy.data.batch_remove([o for o in coll.all_objects])
    bpy.data.collections.remove(coll)
    for me in [m for m in bpy.data.meshes if m.name.startswith(("Terrain", "Water")) and m.users == 0]:
        bpy.data.meshes.remove(me)


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = True
    scene.render.resolution_x, scene.render.resolution_y = SIZE
    scene.world = bpy.data.worlds.new("Sky")
    scene.world.use_nodes = True
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.angle = math.radians(3)
    d = C @ render.SUN
    sun.rotation_euler = Vector(d.tolist()).to_track_quat("Z", "Y").to_euler()
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
    cam.data.clip_end = 40000
    cam.data.sensor_fit = "HORIZONTAL"
    scene.collection.objects.link(cam)
    scene.camera = cam


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    views = [v for v in render.VIEWS if not ONLY or v["name"] in ONLY.split(",")]
    prelude = ""
    if LIBRARY:
        prelude = library_fixture.fixture_luau(library_fixture.load(LIBRARY)) + "\nmakeLibrary(CFrame.new(), 1)\n"
    t0 = time.time()
    dump = render.run_luau(LUAU, OUT, prelude, views)
    sections = render.parse(dump)
    print(f"map built in the mock in {time.time() - t0:.0f}s", flush=True)
    setup()
    lib = Library(LIBRARY)
    for view, sec in zip(views, sections):
        render_view(view, sec, lib)


main()
