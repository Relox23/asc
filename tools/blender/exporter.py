"""Export (FBX/OBJ/.blend) and preview rendering shared by the asset scripts."""
import math
import os
import random

import bpy
from mathutils import Vector

import kit


def export(objects, base_path, save_blend=True):
    for o in bpy.data.objects:
        o.select_set(o in objects)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.fbx(
        filepath=base_path + ".fbx",
        use_selection=True,
        object_types={"MESH"},
        axis_forward="-Z",
        axis_up="Y",
        apply_unit_scale=True,
        global_scale=kit.EXPORT_SCALE,
        mesh_smooth_type="OFF",
    )
    bpy.ops.wm.obj_export(
        filepath=base_path + ".obj",
        export_selected_objects=True,
        forward_axis="NEGATIVE_Z",
        up_axis="Y",
        global_scale=kit.EXPORT_SCALE,
        export_materials=True,
        export_normals=True,
    )
    if save_blend:
        bpy.ops.wm.save_as_mainfile(filepath=base_path + ".blend")
    print("exported", base_path)


def _setup(sky=(0.62, 0.66, 0.85)):
    scene = bpy.context.scene
    if scene.world is None:
        scene.world = bpy.data.worlds.new("Sky")
    w = scene.world
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (*sky, 1)
    bg.inputs["Strength"].default_value = 0.9
    if "Sun" not in bpy.data.objects:
        sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
        sun.data.energy = 3.4
        sun.data.color = (1, 0.94, 0.86)
        sun.rotation_euler = (math.radians(48), math.radians(12), math.radians(-38))
        scene.collection.objects.link(sun)
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 20
    scene.cycles.use_denoising = True
    return scene


def _ground(z, size):
    import bmesh
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=size)
    me = bpy.data.meshes.new("PreviewGround")
    bm.to_mesh(me)
    bm.free()
    g = bpy.data.objects.new("PreviewGround", me)
    g.location.z = z
    m = bpy.data.materials.new("PreviewGroundMat")
    m.use_nodes = True
    m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.5, 0.42, 1)
    me.materials.append(m)
    bpy.context.scene.collection.objects.link(g)
    return g


def bounds(objects):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objects:
        for v in o.data.vertices:
            co = o.matrix_world @ v.co
            lo = Vector((min(lo.x, co.x), min(lo.y, co.y), min(lo.z, co.z)))
            hi = Vector((max(hi.x, co.x), max(hi.y, co.y), max(hi.z, co.z)))
    return lo, hi


def frame_camera(scene, lo, hi, direction=(-0.62, -1.0, 0.5), lens=35):
    c = (lo + hi) / 2
    radius = (hi - lo).length / 2
    cam = scene.camera
    if cam is None:
        cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
        scene.collection.objects.link(cam)
        scene.camera = cam
    cam.data.lens = lens
    cam.data.clip_end = 100000
    fov = 2 * math.atan(18 / lens)
    d = Vector(direction).normalized()
    cam.location = c + d * (radius / math.sin(fov / 2) * 1.02)
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()


def render_objects(objects, path, size=420, direction=(-0.62, -1.0, 0.5)):
    """Render only `objects` (others hidden) framed to fit."""
    scene = _setup()
    wanted = set(objects)
    for o in bpy.data.objects:
        if o.type == "MESH" and not o.name.startswith("Preview"):
            o.hide_render = o not in wanted or o.name.endswith(("__Origin", "__Up", "__Front"))
    lo, hi = bounds([o for o in objects if not o.hide_render])
    g = _ground(lo.z + 0.02, (hi - lo).length * 4)
    frame_camera(scene, lo, hi, direction)
    scene.render.resolution_x = size
    scene.render.resolution_y = size
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(g)


def render_scene(objects, path, clouds=False):
    """Hero render of the watchtower (used by pleiades_watchtower.py)."""
    scene = _setup()
    _ground(0, 8000)
    if clouds:
        cm = bpy.data.materials.new("Cloud")
        cm.use_nodes = True
        cb = cm.node_tree.nodes["Principled BSDF"]
        cb.inputs["Base Color"].default_value = (1, 0.97, 0.98, 1)
        cb.inputs["Roughness"].default_value = 1
        rng = random.Random(7)
        for k in range(22):
            a = rng.uniform(0, kit.TAU)
            if abs(((a - math.atan2(-1500, 520)) + math.pi) % kit.TAU - math.pi) < 0.35:
                continue
            r = rng.uniform(220, 1100)
            center = Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(560, 630)))
            size = rng.uniform(45, 85)
            for _ in range(rng.randint(6, 10)):
                off = Vector((rng.uniform(-1.4, 1.4), rng.uniform(-0.8, 0.8), rng.uniform(-0.15, 0.35))) * size
                bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=1, location=center + off)
                c = bpy.context.active_object
                k2 = rng.uniform(0.55, 1.0) * size
                c.scale = (k2, k2 * rng.uniform(0.8, 1.1), k2 * 0.62)
                c.data.materials.append(cm)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 26
    cam.data.clip_end = 20000
    cam.location = (560, -1650, 380)
    cam.rotation_euler = (Vector((0, 0, 590)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(cam)
    scene.camera = cam
    scene.render.resolution_x = 640
    scene.render.resolution_y = 960
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("rendered", path)
