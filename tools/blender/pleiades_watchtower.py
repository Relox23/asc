"""
Builds the Pleiades-style watchtower in Blender and exports it for Roblox.

Run headless:
    blender --background --python tools/blender/pleiades_watchtower.py -- <out dir> [--render]
or with the bpy pip module:
    python tools/blender/pleiades_watchtower.py <out dir> [--render]

Modelled at 1 Blender unit = 1 stud (about 1150 studs tall), Z up. The export is
scaled to 1/10 and Y-up so Studio's 3D importer never hits the 2048-stud mesh
size limit; the map generator scales it back to full size.
Every object is a separate mesh under Roblox's per-mesh triangle limit.
Object names start with a style prefix the generator uses to colour them:
  Stone_ white stone, Trim_ warm sandstone edges, Gold_ gold, Dark_ doorways/windows, Glow_ light.
"""
import math
import os
import sys

import bpy  # must come before bmesh when using the pip bpy module
import bmesh
from mathutils import Matrix, Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]
OUT = os.path.abspath(argv[0] if argv else "assets")
RENDER = "--render" in argv
os.makedirs(OUT, exist_ok=True)

TAU = math.pi * 2
MAX_TRIS = 10000
EXPORT_SCALE = 0.1

# --------------------------------------------------------------------------- scene
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
collection = bpy.data.collections.new("PleiadesWatchtower")
scene.collection.children.link(collection)

MATERIALS = {
    "Stone": (0.93, 0.91, 0.87),
    "Trim": (0.86, 0.62, 0.40),
    "Gold": (0.85, 0.66, 0.28),
    "Dark": (0.09, 0.08, 0.08),
    "Glow": (0.65, 0.85, 1.0),
}


def material(prefix):
    name = "M_" + prefix
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    r, g, b = MATERIALS[prefix]
    bsdf.inputs["Base Color"].default_value = (r, g, b, 1)
    bsdf.inputs["Roughness"].default_value = 0.55
    if prefix == "Gold":
        bsdf.inputs["Metallic"].default_value = 0.9
        bsdf.inputs["Roughness"].default_value = 0.3
    if prefix == "Glow":
        bsdf.inputs["Emission Color"].default_value = (r, g, b, 1)
        bsdf.inputs["Emission Strength"].default_value = 4
    return m


def finish(name, bm, smooth=True):
    bm.normal_update()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    prefix = name.split("_")[0]
    if prefix in MATERIALS:
        obj.data.materials.append(material(prefix))
    return obj


# --------------------------------------------------------------------------- builders
def lathe(bm, profile, segments, matrix=Matrix(), sharp_angle=32):
    """Revolve a (radius, height) profile around Z. Corners sharper than
    sharp_angle degrees get split vertices so they shade crisply."""
    def ring(r, z):
        if r < 1e-4:
            return [bm.verts.new(matrix @ Vector((0, 0, z)))]
        return [bm.verts.new(matrix @ Vector((math.cos(a) * r, math.sin(a) * r, z)))
                for a in (k / segments * TAU for k in range(segments))]

    def bridge(a, b):
        if len(a) == 1 and len(b) == 1:
            return
        if len(a) == 1:
            for k in range(len(b)):
                bm.faces.new((a[0], b[k], b[(k + 1) % len(b)]))
        elif len(b) == 1:
            for k in range(len(a)):
                bm.faces.new((a[(k + 1) % len(a)], a[k], b[0]))
        else:
            n = len(a)
            for k in range(n):
                bm.faces.new((a[k], a[(k + 1) % n], b[(k + 1) % n], b[k]))

    prev = None
    for i, (r, z) in enumerate(profile):
        cur = ring(r, z)
        if prev is not None:
            bridge(prev, cur)
        sharp = False
        if 0 < i < len(profile) - 1:
            d0 = Vector((r - profile[i - 1][0], z - profile[i - 1][1])).normalized()
            d1 = Vector((profile[i + 1][0] - r, profile[i + 1][1] - z)).normalized()
            sharp = math.degrees(d0.angle(d1, 0)) > sharp_angle
        prev = ring(r, z) if sharp else cur
    return bm


def box(bm, center, size, rot=Matrix()):
    m = Matrix.Translation(Vector(center)) @ rot @ Matrix.Diagonal((*size, 1))
    bmesh.ops.create_cube(bm, size=1, matrix=m)


def cylinder(bm, base, height, radius, segments=16, rot=Matrix()):
    m = Matrix.Translation(Vector(base)) @ rot @ Matrix.Translation((0, 0, height / 2))
    bmesh.ops.create_cone(bm, cap_ends=True, segments=segments, radius1=radius, radius2=radius, depth=height, matrix=m)


def sample(fn, a, b, n):
    return [fn(a + (b - a) * i / n) for i in range(n + 1)]


# --------------------------------------------------------------------------- main body
def main_body():
    p = [(0, -8), (152, -8), (152, 4), (142, 4), (142, 12), (130, 12), (130, 22), (122, 22), (122, 26)]
    # trumpet flare from the ground to the shaft
    p += sample(lambda t: (44 + 78 * (1 - t) ** 2.6, 26 + 132 * t), 0.02, 1, 18)
    # cornice
    p += [(52, 158), (52, 166), (44, 168)]
    # long shaft with moulding rings every ~90 studs
    z, r0, r1, top = 168, 42, 25, 560
    for k in range(5):
        za, zb = z + k * (top - z) / 5, z + (k + 1) * (top - z) / 5
        ra = r0 + (r1 - r0) * ((za - z) / (top - z)) ** 0.8
        rb = r0 + (r1 - r0) * ((zb - z) / (top - z)) ** 0.8
        p += [(ra, za + 0.1), (rb, zb - 5), (rb + 3, zb - 4), (rb + 3, zb - 1), (rb, zb)]
    # balcony
    p += [(25, 560), (46, 563), (48, 568), (48, 572), (27, 575)]
    # upper shaft and the crown funnel
    p += [(26, 640)]
    p += sample(lambda t: (26 + 50 * t ** 2.2, 640 + 52 * t), 0.05, 1, 10)
    p += [(80, 696), (80, 702), (70, 704), (0, 704)]
    return finish("Stone_Body", lathe(bmesh.new(), p, 64))


def body_trim():
    bm = bmesh.new()
    # warm bands like the concept art
    for z, r, h in [(22, 123, 3), (150, 50, 2), (562, 46.5, 2), (690, 79, 3)]:
        lathe(bm, [(r - 1.5, z), (r + 0.6, z), (r + 0.6, z + h), (r - 1.5, z + h)], 64)
    return finish("Trim_Bands", bm)


def flare_ribs():
    # vertical ribs running up the flare
    bm = bmesh.new()
    for k in range(16):
        a = k / 16 * TAU + TAU / 32
        prev = None
        for i in range(13):
            t = i / 12
            r = 44 + 78 * (1 - t) ** 2.6 + 1.6
            z = 26 + 132 * t
            v = Vector((math.cos(a) * r, math.sin(a) * r, z))
            if prev is not None:
                d = v - prev
                mid = (v + prev) / 2
                rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
                box(bm, mid, (3.4, 3.4, d.length + 1), rot)
            prev = v
    return finish("Trim_Ribs", bm, smooth=False)


def windows():
    bm = bmesh.new()
    for z in (230, 330, 430, 520, 610):
        t = (z - 168) / (560 - 168)
        r = 42 + (25 - 42) * min(max(t, 0), 1) ** 0.8 if z < 560 else 26
        for k in range(6):
            a = k / 6 * TAU + (z % 7) * 0.2
            rot = Matrix.Rotation(a, 4, "Z")
            box(bm, (math.cos(a) * (r - 0.6), math.sin(a) * (r - 0.6), z), (2.4, 3.2, 12), rot)
    return finish("Dark_Windows", bm, smooth=False)


# --------------------------------------------------------------------------- crown
CROWN_PROFILE_CENTER = [
    (0, 702), (19, 702), (19, 792), (23, 794), (23, 800), (19, 802),
    (24, 808), (29, 818), (31, 828), (28, 840), (20, 850), (11, 858), (6, 864), (6, 868),
    (40, 869), (90, 871), (124, 874), (130, 877), (124, 880), (88, 883), (40, 885), (9, 886),
    (9, 904), (13, 908), (13, 912), (9, 914), (6, 930), (4, 970), (2, 1010), (0.8, 1040), (0, 1044),
]


def central_spire():
    return finish("Stone_Spire", lathe(bmesh.new(), CROWN_PROFILE_CENTER, 48))


def saucer_trim():
    bm = bmesh.new()
    lathe(bm, [(122, 874.5), (131, 876.5), (131, 877.5), (122, 879.5)], 64)
    lathe(bm, [(22.5, 794.5), (23.6, 795), (23.6, 799), (22.5, 799.5)], 32)
    return finish("Gold_Rings", bm)


def satellites():
    bm = bmesh.new()
    profile = [
        (0, 468), (1.5, 480), (3.5, 510), (6, 552), (8.5, 600), (11, 650), (13, 692),
        (12, 704), (12, 764), (15, 766), (15, 771), (12, 773), (17, 782), (19.5, 792),
        (17, 803), (11, 811), (6, 817), (4, 822), (2.4, 840), (1, 862), (0, 866),
    ]
    for k in range(6):
        a = k / 6 * TAU
        m = Matrix.Translation((math.cos(a) * 54, math.sin(a) * 54, 0))
        lathe(bm, profile, 28, m)
    return finish("Stone_Satellites", bm)


def satellite_bands():
    bm = bmesh.new()
    for k in range(6):
        a = k / 6 * TAU
        m = Matrix.Translation((math.cos(a) * 54, math.sin(a) * 54, 0))
        lathe(bm, [(14.4, 766.5), (15.6, 767), (15.6, 770), (14.4, 770.5)], 24, m)
        lathe(bm, [(11.5, 690), (14, 690.5), (14, 693), (11.5, 693.5)], 24, m)
    return finish("Gold_SatelliteBands", bm)


# --------------------------------------------------------------------------- entrance
def portico():
    """Temple front at the foot of the flare, facing -Y."""
    bm = bmesh.new()
    y0 = -128
    box(bm, (0, y0 - 6, 6), (78, 34, 4))
    for k in range(3):
        box(bm, (0, y0 - 24 - k * 3, 2 - k * 1.5 + 1), (78 - k * 4, 3, 8 - k * 3))
    for x in (-30, -18, -6, 6, 18, 30):
        cylinder(bm, (x, y0 - 16, 8), 34, 2.6, 16)
        box(bm, (x, y0 - 16, 43), (7, 7, 2))
    box(bm, (0, y0 - 10, 46), (76, 22, 6))
    # pediment
    verts = []
    for y in (y0 - 22, y0 + 2):
        verts.append([bm.verts.new((-40, y, 49)), bm.verts.new((40, y, 49)), bm.verts.new((0, y, 64))])
    f, b = verts
    bm.faces.new(f)
    bm.faces.new(list(reversed(b)))
    for i in range(3):
        j = (i + 1) % 3
        bm.faces.new((f[i], b[i], b[j], f[j]))
    # side walls joining the portico to the flare
    for x in (-36, 36):
        box(bm, (x, y0 + 4, 26), (6, 40, 44))
    return finish("Stone_Portico", bm, smooth=False)


def doorway():
    bm = bmesh.new()
    box(bm, (0, -122, 24), (22, 14, 34))
    return finish("Dark_Door", bm, smooth=False)


# --------------------------------------------------------------------------- horn arches
def bezier(p0, p1, p2, p3, t):
    u = 1 - t
    return p0 * u ** 3 + p1 * 3 * u * u * t + p2 * 3 * u * t * t + p3 * t ** 3


def horn(side, prefix, inset=0.0, scale=1.0, depth_scale=1.0):
    """One giant curved leg rising beside the tower and ending in a point overhead."""
    bm = bmesh.new()
    s = side
    p0 = Vector((s * 285, 0, -20))
    p1 = Vector((s * 272, 0, 440))
    p2 = Vector((s * 222, 0, 860))
    p3 = Vector((s * 30, 0, 1130))
    n = 40
    rings = []
    for i in range(n + 1):
        t = i / n
        c = bezier(p0, p1, p2, p3, t)
        d = (bezier(p0, p1, p2, p3, min(t + 0.01, 1)) - bezier(p0, p1, p2, p3, max(t - 0.01, 0))).normalized()
        across = Vector((d.z, 0, -d.x)) * s  # in the arch plane, pointing outward
        w = (92 * (1 - t) ** 1.2 + 3) * scale  # width across the arch
        dep = (50 * (1 - t) ** 1.1 + 2) * depth_scale  # thickness front-to-back
        foot = max(0, 1 - t * 8) * 40  # flared foot
        w += foot * scale
        center = c + across * (inset * w)
        ring = []
        for a, b in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            ring.append(bm.verts.new(center + across * (a * w / 2) + Vector((0, b * dep / 2, 0))))
        rings.append(ring)
    for i in range(n):
        a, b = rings[i], rings[i + 1]
        for k in range(4):
            bm.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    return finish(f"{prefix}_Horn{'L' if s < 0 else 'R'}", bm, smooth=False)


# --------------------------------------------------------------------------- build
objects = [
    main_body(), body_trim(), flare_ribs(), windows(),
    central_spire(), saucer_trim(), satellites(), satellite_bands(),
    portico(), doorway(),
    horn(-1, "Stone"), horn(1, "Stone"),
    horn(-1, "Trim", inset=-0.42, scale=0.22, depth_scale=1.06), horn(1, "Trim", inset=-0.42, scale=0.22, depth_scale=1.06),
]

total = 0
for o in objects:
    tris = sum(len(p.vertices) - 2 for p in o.data.polygons)
    total += tris
    assert tris <= MAX_TRIS, f"{o.name} has {tris} triangles (limit {MAX_TRIS})"
    print(f"  {o.name:22s} {tris:6d} tris")
print(f"total {total} triangles in {len(objects)} meshes")

# --------------------------------------------------------------------------- export
for o in bpy.data.objects:
    o.select_set(o in objects)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.export_scene.fbx(
    filepath=os.path.join(OUT, "PleiadesWatchtower.fbx"),
    use_selection=True,
    object_types={"MESH"},
    axis_forward="-Z",
    axis_up="Y",
    apply_unit_scale=True,
    global_scale=EXPORT_SCALE,
    mesh_smooth_type="FACE",
)
bpy.ops.wm.obj_export(
    filepath=os.path.join(OUT, "PleiadesWatchtower.obj"),
    export_selected_objects=True,
    forward_axis="NEGATIVE_Z",
    up_axis="Y",
    global_scale=EXPORT_SCALE,
    export_materials=True,
)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "PleiadesWatchtower.blend"))
print("exported to", OUT)

# --------------------------------------------------------------------------- preview render
if RENDER:
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.66, 0.85, 1)
    bg.inputs["Strength"].default_value = 0.9

    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.data.color = (1, 0.93, 0.85)
    sun.rotation_euler = (math.radians(50), math.radians(10), math.radians(-35))
    scene.collection.objects.link(sun)

    # desert ground and a sea of clouds just under the crown (preview only)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=4000)
    ground = finish("Preview_Ground", bm)
    ground.data.materials.clear()
    gm = bpy.data.materials.new("Sand")
    gm.use_nodes = True
    gm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.85, 0.68, 0.45, 1)
    ground.data.materials.append(gm)

    cm = bpy.data.materials.new("Cloud")
    cm.use_nodes = True
    cb = cm.node_tree.nodes["Principled BSDF"]
    cb.inputs["Base Color"].default_value = (1, 0.97, 0.98, 1)
    cb.inputs["Roughness"].default_value = 1
    import random
    random.seed(7)
    for k in range(22):
        a = random.uniform(0, TAU)
        if abs(((a - math.atan2(-1500, 520)) + math.pi) % TAU - math.pi) < 0.35:
            continue  # keep the camera's line of sight clear
        r = random.uniform(220, 1100)
        center = Vector((math.cos(a) * r, math.sin(a) * r, random.uniform(560, 630)))
        size = random.uniform(45, 85)
        for _ in range(random.randint(6, 10)):
            off = Vector((random.uniform(-1.4, 1.4), random.uniform(-0.8, 0.8), random.uniform(-0.15, 0.35))) * size
            bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=1, location=center + off)
            c = bpy.context.active_object
            k = random.uniform(0.55, 1.0) * size
            c.scale = (k, k * random.uniform(0.8, 1.1), k * 0.62)
            c.data.materials.append(cm)

    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 26
    cam.location = (560, -1650, 380)
    direction = Vector((0, 0, 590)) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    cam.data.clip_end = 20000
    scene.collection.objects.link(cam)
    scene.camera = cam

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 640
    scene.render.resolution_y = 960
    scene.render.filepath = os.path.join(OUT, "PleiadesWatchtower_preview.png")
    bpy.ops.render.render(write_still=True)
    print("rendered preview")
