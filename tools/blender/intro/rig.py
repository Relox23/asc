"""
R15 character rig for the Awaken intro (docs/intro/DESIGN.md §4).

    rig = build_rig(collection, name="CharacterRig")   # armature object
    report = verify_axes(rig)                          # numeric proof of §4.2

The armature object's origin is the HumanoidRootPart centre, so animating the
object transform animates the HRP. Its 15 bones carry exactly the R15 Motor6D
names, with heads at the joint pivots of §4.1 and every bone pointing straight
up (+Z, length 0.25, roll 0). A bone along +Z with roll 0 has local axes
X = +X (right), Y = +Z (up), Z = -Y (back): exactly Roblox's character axes, so
`pose_bone.rotation_euler = (a, b, c)` (XYZ) is the Motor6D Transform
`CFrame.Angles(0,0,c) * CFrame.Angles(0,b,0) * CFrame.Angles(a,0,0)`, no axis
conversion (and the Root bone's `location` is the Transform's position).

The block mannequin (preview only) has one mesh object per R15 part, named like
the part, bone-parented to the bone that moves it.

Coordinates: Roblox character space (x, y, z) -> Blender (x, -z, y).
Run directly for a self-test:  python tools/blender/intro/rig.py
"""
import math
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (_HERE, os.path.dirname(_HERE)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import bpy  # noqa: E402
import bmesh  # noqa: E402
from mathutils import Euler, Matrix, Vector  # noqa: E402

import kit  # noqa: E402  (tools/blender/kit.py)

BONE_LENGTH = 0.25

# (bone = Motor6D, parent bone, part it moves, pivot in Roblox character space)  -- DESIGN §4.1
JOINTS = (
    ("Root", None, "LowerTorso", (0.0, -0.3, 0.0)),
    ("Waist", "Root", "UpperTorso", (0.0, -0.3, 0.0)),
    ("Neck", "Waist", "Head", (0.0, 1.3, 0.0)),
    ("LeftShoulder", "Waist", "LeftUpperArm", (-1.25, 1.1, 0.0)),
    ("LeftElbow", "LeftShoulder", "LeftLowerArm", (-1.5, -0.05, 0.0)),
    ("LeftWrist", "LeftElbow", "LeftHand", (-1.5, -0.95, 0.0)),
    ("RightShoulder", "Waist", "RightUpperArm", (1.25, 1.1, 0.0)),
    ("RightElbow", "RightShoulder", "RightLowerArm", (1.5, -0.05, 0.0)),
    ("RightWrist", "RightElbow", "RightHand", (1.5, -0.95, 0.0)),
    ("LeftHip", "Root", "LeftUpperLeg", (-0.5, -0.8, 0.0)),
    ("LeftKnee", "LeftHip", "LeftLowerLeg", (-0.5, -2.0, 0.0)),
    ("LeftAnkle", "LeftKnee", "LeftFoot", (-0.5, -2.85, 0.0)),
    ("RightHip", "Root", "RightUpperLeg", (0.5, -0.8, 0.0)),
    ("RightKnee", "RightHip", "RightLowerLeg", (0.5, -2.0, 0.0)),
    ("RightAnkle", "RightKnee", "RightFoot", (0.5, -2.85, 0.0)),
)
BONES = tuple(j[0] for j in JOINTS)
PARENT = {b: p for b, p, _, _ in JOINTS}
PART_OF = {b: part for b, _, part, _ in JOINTS}
BONE_OF = {part: b for b, _, part, _ in JOINTS}
PIVOT = {b: Vector(pv) for b, _, _, pv in JOINTS}          # Roblox character space

# part: (size, centre) in Roblox character space  -- DESIGN §4.1 (mannequin)
PARTS = {
    "LowerTorso": ((2.0, 0.5, 1.0), (0.0, -0.55, 0.0)),
    "UpperTorso": ((2.0, 1.6, 1.0), (0.0, 0.5, 0.0)),
    "Head": ((1.2, 1.2, 1.2), (0.0, 1.9, 0.0)),
    "LeftUpperArm": ((0.9, 1.2, 0.9), (-1.5, 0.55, 0.0)),
    "LeftLowerArm": ((0.85, 0.9, 0.85), (-1.5, -0.5, 0.0)),
    "LeftHand": ((0.8, 0.4, 0.8), (-1.5, -1.15, 0.0)),
    "RightUpperArm": ((0.9, 1.2, 0.9), (1.5, 0.55, 0.0)),
    "RightLowerArm": ((0.85, 0.9, 0.85), (1.5, -0.5, 0.0)),
    "RightHand": ((0.8, 0.4, 0.8), (1.5, -1.15, 0.0)),
    "LeftUpperLeg": ((0.9, 1.2, 0.9), (-0.5, -1.4, 0.0)),
    "LeftLowerLeg": ((0.85, 0.9, 0.85), (-0.5, -2.45, 0.0)),
    "LeftFoot": ((0.9, 0.15, 1.1), (-0.5, -2.93, -0.1)),
    "RightUpperLeg": ((0.9, 1.2, 0.9), (0.5, -1.4, 0.0)),
    "RightLowerLeg": ((0.85, 0.9, 0.85), (0.5, -2.45, 0.0)),
    "RightFoot": ((0.9, 0.15, 1.1), (0.5, -2.93, -0.1)),
}
FEET_Y = -3.0  # Roblox y of the soles (ground) relative to the HRP centre

# Blender -> Roblox for directions/positions (DESIGN §2); Roblox -> Blender is C.T
C = Matrix(((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, -1.0, 0.0)))
C4 = C.to_4x4()

# The bone that moves each hand (the "RightHand bone" of DESIGN §3 is RightWrist).
HAND_BONE = {"Right": "RightWrist", "Left": "LeftWrist"}

# Sword grip (DESIGN §4.3): RightHand.CFrame * CFrame.new(0,-0.15,0) * CFrame.Angles(-pi/2,0,0).
# In RightWrist bone space (= Roblox axes, origin at the wrist pivot): the hand centre
# is 0.2 below the wrist, the grip 0.15 further. Rotation: the asset convention of §2
# (Roblox asset frame = C * Blender object * C.T * Ry(pi)) turns Rx(-90) into Ry(180)
# for the Blender sword object, whose +Z (blade) then points along the hand's -Z.
GRIP_OFFSET = Matrix.Translation((0.0, -0.35, 0.0)) @ Matrix.Rotation(math.pi, 4, "Y")


def to_blender(v):
    """Roblox (x, y, z) -> Blender (x, -z, y)."""
    x, y, z = v
    return Vector((x, -z, y))


def to_roblox(v):
    """Blender (x, y, z) -> Roblox (x, z, -y)."""
    x, y, z = v
    return Vector((x, z, -y))


def euler_rbx(deg):
    """CFrame.Angles(0,0,c)*CFrame.Angles(0,b,0)*CFrame.Angles(a,0,0) as a 4x4 (degrees in)."""
    a, b, c = (math.radians(d) for d in deg)
    return Matrix.Rotation(c, 4, "Z") @ Matrix.Rotation(b, 4, "Y") @ Matrix.Rotation(a, 4, "X")


def fk(pose=None, root_loc=(0.0, 0.0, 0.0)):
    """Reference R15 forward kinematics in Roblox character space (HRP = identity), the way
    Motor6Ds compose: Part1 = Part0 * C0 * Transform * C1:Inverse() with identity-rotation
    C0/C1 at the pivots. pose: {bone: (x, y, z) degrees}. Returns ({bone: frame at its pivot},
    {part: part CFrame}) as 4x4 matrices."""
    pose = pose or {}
    frames, parts = {}, {}
    for bone, parent, part, pv in JOINTS:
        pv = Vector(pv)
        if parent is None:
            base = Matrix.Translation(pv) @ Matrix.Translation(Vector(root_loc))
        else:
            base = frames[parent] @ Matrix.Translation(pv - PIVOT[parent])
        frames[bone] = base @ euler_rbx(pose.get(bone, (0.0, 0.0, 0.0)))
        parts[part] = frames[bone] @ Matrix.Translation(Vector(PARTS[part][1]) - pv)
    return frames, parts


def grip_frame_rbx(frames):
    """Roblox-space CFrame of the held sword (asset frame) from fk() bone frames."""
    hand = frames["RightWrist"] @ Matrix.Translation(Vector(PARTS["RightHand"][1]) - PIVOT["RightWrist"])
    return hand @ Matrix.Translation((0.0, -0.15, 0.0)) @ Matrix.Rotation(-math.pi / 2, 4, "X")


# ----------------------------------------------------------------------------- look
_MATS = {
    # name: (sRGB 0-255, roughness, emission strength)
    "Skin": ((236, 196, 160), 0.55, 0.0),
    "Shirt": ((40, 48, 72), 0.7, 0.0),
    "Trim": ((150, 166, 200), 0.5, 0.0),
    "Pants": ((104, 92, 80), 0.8, 0.0),
    "Boots": ((44, 32, 28), 0.6, 0.0),
    "Belt": ((96, 64, 40), 0.6, 0.0),
    "Gold": ((214, 172, 74), 0.35, 0.0),
    "Hair": ((58, 40, 34), 0.6, 0.0),
    "Eyes": ((18, 22, 34), 0.3, 0.0),
    "EyeGlow": ((150, 220, 255), 0.3, 2.0),
    "Scarf": ((182, 44, 46), 0.75, 0.0),
}


def rig_material(key):
    name = "Rig_" + key
    m = bpy.data.materials.get(name)
    if m is not None:
        return m
    rgb, rough, emit = _MATS[key]
    lin = tuple((c / 255) ** 2.2 for c in rgb)
    m = bpy.data.materials.new(name)
    if m.node_tree is None:      # Blender < 5 needs use_nodes; 5.x always has a node tree
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    if key == "Gold":
        bsdf.inputs["Metallic"].default_value = 0.85
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*lin, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit
    m.diffuse_color = (*lin, 1.0)
    return m


def _bl_size(size):
    sx, sy, sz = size
    return (sx, sz, sy)


def _pieces(part):
    """Mannequin pieces of a part, in the part's Blender-local space (centre = origin,
    front = +Y, up = +Z): [(material, size, centre, bevel, rotation matrix or None)]."""
    w, d, h = _bl_size(PARTS[part][0])
    side = -1.0 if part.startswith("Left") else 1.0
    if part == "Head":
        out = [("Skin", (w, d, h), (0, 0, 0), 0.12, None),
               # eyes on the front face (+Y) with a small glint: facing reads at a glance
               ("Eyes", (0.17, 0.06, 0.27), (-0.25, 0.6, 0.0), 0.02, None),
               ("Eyes", (0.17, 0.06, 0.27), (0.25, 0.6, 0.0), 0.02, None),
               ("EyeGlow", (0.06, 0.03, 0.08), (-0.21, 0.635, 0.06), 0.0, None),
               ("EyeGlow", (0.06, 0.03, 0.08), (0.29, 0.635, 0.06), 0.0, None),
               # hair: cap with bangs, back, a few swept spikes
               ("Hair", (1.3, 1.3, 0.3), (0, -0.01, 0.5), 0.08, None),
               ("Hair", (1.3, 0.36, 1.0), (0, -0.48, 0.08), 0.08, None),
               ("Hair", (0.3, 0.16, 0.44), (-0.6, 0.12, 0.22), 0.04, None),
               ("Hair", (0.3, 0.16, 0.44), (0.6, 0.12, 0.22), 0.04, None)]
        for k, x in enumerate((-0.38, 0.0, 0.38)):
            rot = kit.Rx(math.radians(-55 - 8 * (k == 1))) @ kit.Ry(math.radians(x * 30))
            out.append(("Hair", (0.36, 0.26, 0.62), (x, -0.62, 0.42 + 0.06 * (k == 1)), 0.05, rot))
        return out
    if part == "UpperTorso":
        return [("Shirt", (w, d, h), (0, 0, 0), 0.1, None),
                ("Trim", (0.1, 0.04, 1.15), (0.0, 0.51, -0.12), 0.0, None),
                ("Trim", (2.04, 1.04, 0.14), (0, 0, -0.73), 0.03, None),
                ("Scarf", (1.4, 1.14, 0.3), (0, 0, 0.7), 0.08, None),
                ("Scarf", (0.36, 0.1, 0.95), (0.32, -0.57, 0.2), 0.03, kit.Ry(math.radians(-12)))]
    if part == "LowerTorso":
        return [("Pants", (w, d, h), (0, 0, 0), 0.07, None),
                ("Belt", (2.04, 1.04, 0.16), (0, 0, 0.13), 0.03, None),
                ("Gold", (0.32, 0.06, 0.2), (0, 0.52, 0.13), 0.02, None)]
    if part.endswith("UpperArm"):
        return [("Shirt", (w, d, h), (0, 0, 0), 0.08, None),
                ("Trim", (w + 0.04, d + 0.04, 0.1), (0, 0, -0.38), 0.02, None)]
    if part.endswith("LowerArm"):
        return [("Shirt", (w, d, h), (0, 0, 0), 0.07, None),
                ("Trim", (w + 0.06, d + 0.06, 0.2), (0, 0, -0.32), 0.03, None)]
    if part.endswith("Hand"):
        return [("Skin", (w, d, h), (0, 0, 0), 0.08, None)]
    if part.endswith("UpperLeg"):
        return [("Pants", (w, d, h), (0, 0, 0), 0.08, None)]
    if part.endswith("LowerLeg"):
        return [("Pants", (w, d, h), (0, 0, 0), 0.07, None),
                ("Boots", (w + 0.06, d + 0.06, 0.5), (0, 0, -0.2), 0.05, None),
                ("Boots", (w + 0.1, d + 0.1, 0.1), (0, 0, 0.06), 0.03, None)]
    if part.endswith("Foot"):
        return [("Boots", (w, d, h), (0, 0, 0), 0.04, None),
                ("Belt", (w - 0.1, 0.3, 0.06), (0, 0.38, 0.09), 0.02, None)]
    raise KeyError(part)


def _part_object(part, collection):
    bm = bmesh.new()
    keys = []
    for key, size, centre, bevel, rot in _pieces(part):
        if key not in keys:
            keys.append(key)
        before = set(bm.faces)
        M = Matrix.Translation(centre) @ (rot if rot is not None else Matrix())
        kit.box(bm, M, size, (0, 0, 0), bevel=bevel)
        idx = keys.index(key)
        for f in set(bm.faces) - before:
            f.material_index = idx
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(part)
    bm.to_mesh(me)
    bm.free()
    for key in keys:
        me.materials.append(rig_material(key))
    obj = bpy.data.objects.new(part, me)
    collection.objects.link(obj)
    return obj


# ----------------------------------------------------------------------------- build
def build_rig(collection=None, name="CharacterRig"):
    """Armature `name` (object origin = HRP centre) + mannequin parts. Returns the armature object."""
    scene = bpy.context.scene
    collection = collection or scene.collection
    arm = bpy.data.armatures.new(name)
    arm.display_type = "STICK"
    rig = bpy.data.objects.new(name, arm)
    collection.objects.link(rig)
    rig.show_in_front = True

    view_layer = bpy.context.view_layer
    in_scene = collection == scene.collection or collection in scene.collection.children_recursive
    temp_link = not in_scene
    if temp_link:
        scene.collection.objects.link(rig)
    prev_active = view_layer.objects.active
    if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")
    view_layer.objects.active = rig
    bpy.ops.object.mode_set(mode="EDIT")
    ebs = {}
    for bone, parent, _part, pv in JOINTS:
        eb = arm.edit_bones.new(bone)
        head = to_blender(pv)
        eb.head = head
        eb.tail = head + Vector((0.0, 0.0, BONE_LENGTH))
        eb.roll = 0.0
        eb.use_connect = False
        eb.use_deform = False
        if parent:
            eb.parent = ebs[parent]
        ebs[bone] = eb
    bpy.ops.object.mode_set(mode="OBJECT")
    if temp_link:
        scene.collection.objects.unlink(rig)
    view_layer.objects.active = prev_active

    for pb in rig.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)
        if pb.name != "Root":
            pb.lock_location = (True, True, True)

    # mannequin parts, bone-parented (Blender bone parenting is relative to the bone tail)
    for bone, _parent, part, _pv in JOINTS:
        obj = _part_object(part, collection)
        b = arm.bones[bone]
        parent_rest = b.matrix_local @ Matrix.Translation((0.0, b.length, 0.0))
        part_rest = Matrix.Translation(to_blender(PARTS[part][1]))
        obj.parent = rig
        obj.parent_type = "BONE"
        obj.parent_bone = bone
        obj.matrix_parent_inverse = Matrix()
        obj.matrix_basis = parent_rest.inverted() @ part_rest
        obj["r15_part"] = part
    rig["r15_rig"] = 1
    return rig


def part_objects(rig):
    """{part name: mesh object} of a rig built by build_rig."""
    return {o["r15_part"]: o for o in rig.children if "r15_part" in o}


def reset_pose(rig):
    for pb in rig.pose.bones:
        pb.rotation_euler = (0.0, 0.0, 0.0)
        pb.location = (0.0, 0.0, 0.0)


def joint_transforms(rig):
    """{bone: (Quaternion (w, x, y, z), location Vector)}: every joint's Motor6D Transform in
    Roblox joint axes (DESIGN §4.2 / §8), read straight from the pose bones (no conversion).
    Reflects the current pose / frame (scene.frame_set first when sampling an animation)."""
    out = {}
    for b in BONES:
        mb = rig.pose.bones[b].matrix_basis
        out[b] = (mb.to_quaternion(), mb.translation.copy())
    return out


def grip_world_matrix(rig):
    """World matrix the Sword object has while held (DESIGN §4.3)."""
    return rig.matrix_world @ rig.pose.bones["RightWrist"].matrix @ GRIP_OFFSET


def add_grip_constraint(obj, rig, name="Grip"):
    """Child Of constraint to the RightWrist bone with the §4.3 grip offset as its inverse
    matrix: while its influence is 1 the object's own transform must be identity (location 0,
    rotation 0, scale 1) and its world matrix is grip_world_matrix(rig)."""
    con = obj.constraints.new("CHILD_OF")
    con.name = name
    con.target = rig
    con.subtarget = HAND_BONE["Right"]
    con.set_inverse_pending = False
    con.inverse_matrix = GRIP_OFFSET.copy()
    return con


# ----------------------------------------------------------------------------- self-test
def _rot_err_deg(A, B):
    """Angle (degrees) of the rotation between two rotation matrices (small-angle accurate:
    |A - B|_F = 2*sqrt(2)*sin(angle/2))."""
    A, B = A.to_3x3(), B.to_3x3()
    f = math.sqrt(sum((A[i][j] - B[i][j]) ** 2 for i in range(3) for j in range(3)))
    return math.degrees(2.0 * math.asin(min(1.0, f / (2.0 * math.sqrt(2.0)))))


def _rbx_part_frames(rig):
    """Part CFrames in Roblox character space (relative to the rig object = HRP), from Blender."""
    inv = rig.matrix_world.inverted()
    return {part: C4 @ (inv @ o.matrix_world) @ C4.transposed() for part, o in part_objects(rig).items()}


def verify_axes(rig, trials=6, seed=1, verbose=True):
    """Numerically prove DESIGN §4.2 on `rig` (pose is restored to rest afterwards):
      1. per bone: rotation_euler (a,b,c) rotates its part relative to the parent part by
         Rz(c)Ry(b)Rx(a) in Roblox character axes (Rrbx = C Rbl C^T), about the pivot;
      2. a random full pose (incl. Root location, random object transform) matches the
         Roblox Motor6D forward kinematics fk() for every part;
      3. the sword grip (GRIP_OFFSET) matches §4.3 through the asset convention of §2.
    Returns {"rot_err_deg", "pos_err", "grip_rot_err_deg", "grip_pos_err"} (max values)."""
    import random
    rng = random.Random(seed)
    view_layer = bpy.context.view_layer
    saved = rig.matrix_world.copy()
    parts = part_objects(rig)
    max_rot = max_pos = 0.0

    def rand_euler():
        return tuple(rng.uniform(-170, 170) for _ in range(3))

    # 1. one bone at a time, relative to the parent part (or the HRP = rig object)
    for t in range(trials):
        rig.matrix_world = Matrix.LocRotScale(Vector([rng.uniform(-50, 50) for _ in range(3)]),
                                              Euler([rng.uniform(-3, 3) for _ in range(3)]), None)
        for bone, parent, part, pv in JOINTS:
            reset_pose(rig)
            deg = rand_euler()
            rig.pose.bones[bone].rotation_euler = [math.radians(d) for d in deg]
            view_layer.update()
            W_child = parts[part].matrix_world
            W_parent = parts[PART_OF[parent]].matrix_world if parent else rig.matrix_world
            rel = W_parent.to_3x3().inverted() @ W_child.to_3x3()
            R_rbx = C @ rel @ C.transposed()
            max_rot = max(max_rot, _rot_err_deg(R_rbx, euler_rbx(deg)))
            # the pivot stays put: the child's pivot point coincides with the parent's
            piv_child = W_child @ (to_blender(pv) - to_blender(PARTS[part][1]))
            if parent:
                piv_parent = W_parent @ (to_blender(pv) - to_blender(PARTS[PART_OF[parent]][1]))
            else:
                piv_parent = rig.matrix_world @ to_blender(pv)
            max_pos = max(max_pos, (piv_child - piv_parent).length)

    # 2. full random poses vs Roblox forward kinematics
    grip_rot = grip_pos = 0.0
    for t in range(trials):
        rig.matrix_world = Matrix.LocRotScale(Vector([rng.uniform(-50, 50) for _ in range(3)]),
                                              Euler([rng.uniform(-3, 3) for _ in range(3)]), None)
        pose = {b: rand_euler() for b in BONES}
        loc = tuple(rng.uniform(-1, 1) for _ in range(3))
        for b in BONES:
            rig.pose.bones[b].rotation_euler = [math.radians(d) for d in pose[b]]
        rig.pose.bones["Root"].location = loc
        view_layer.update()
        frames, ref = fk(pose, loc)
        got = _rbx_part_frames(rig)
        for b, (q, t) in joint_transforms(rig).items():     # exporter view of the same pose
            max_rot = max(max_rot, _rot_err_deg(q.to_matrix(), euler_rbx(pose[b])))
            max_pos = max(max_pos, (t - Vector(loc if b == "Root" else (0, 0, 0))).length)
        for part, M in ref.items():
            max_rot = max(max_rot, _rot_err_deg(M, got[part]))
            max_pos = max(max_pos, (M.translation - got[part].translation).length)
        # 3. grip: Blender sword world -> Roblox asset CFrame (§2) vs §4.3
        S = rig.matrix_world.inverted() @ grip_world_matrix(rig)
        asset_rot = C @ S.to_3x3() @ C.transposed() @ Matrix.Rotation(math.pi, 3, "Y")
        exp = grip_frame_rbx(frames)
        grip_rot = max(grip_rot, _rot_err_deg(asset_rot, exp))
        grip_pos = max(grip_pos, (C @ S.translation - exp.translation).length)

    reset_pose(rig)
    rig.matrix_world = saved
    view_layer.update()
    res = {"rot_err_deg": max_rot, "pos_err": max_pos, "grip_rot_err_deg": grip_rot, "grip_pos_err": grip_pos}
    if verbose:
        print("verify_axes: max rotation error %.2e deg, max position error %.2e studs, "
              "grip %.2e deg / %.2e studs" % (max_rot, max_pos, grip_rot, grip_pos))
    return res


def check_rest(rig):
    """Bone heads/axes and part centres at rest (Blender) vs the §4.1 table. Returns max error."""
    err = 0.0
    for bone, _parent, part, pv in JOINTS:
        b = rig.data.bones[bone]
        err = max(err, (b.head_local - to_blender(pv)).length)
        # bone local axes must be Roblox's: rest matrix = C^T (X right, Y up = +Z, Z back = -Y)
        D = b.matrix_local.to_3x3() - C.transposed()
        err = max(err, max(abs(x) for row in D for x in row))
    for part, o in part_objects(rig).items():
        err = max(err, (o.matrix_world.translation - rig.matrix_world @ to_blender(PARTS[part][1])).length)
    return err


if __name__ == "__main__":
    bpy.ops.wm.read_factory_settings(use_empty=True)
    col = bpy.data.collections.new("Character")
    bpy.context.scene.collection.children.link(col)
    r = build_rig(col)
    bpy.context.view_layer.update()
    print("bones:", len(r.pose.bones), [b.name for b in r.data.bones])
    print("rest error %.2e" % check_rest(r))
    res = verify_axes(r)
    ok = res["rot_err_deg"] < 1e-2 and res["pos_err"] < 1e-4 and res["grip_rot_err_deg"] < 1e-2 and res["grip_pos_err"] < 1e-4
    print("PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)
