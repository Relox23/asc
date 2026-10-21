"""
Pose library for the Awaken intro character (docs/intro/DESIGN.md §4.5).

Data
    POSES[name]    = {bone: (x_deg, y_deg, z_deg)}  joint rotations = pose_bone.rotation_euler
                     (XYZ) = Motor6D Transform angles (§4.2); unlisted bones = 0
    ROOT_LOC[name] = (x, y, z)  Root bone location (joint space = HRP axes, studs); missing = 0
    BODY[name]     = ((rx, ry, rz), text)  the whole-body orientation the pose is designed for:
                     Blender XYZ Euler (degrees) of the armature object (= HRP) relative to
                     "upright, facing +Y", plus a description. Poses never contain it: the
                     scene animates the object transform (BODY is what the sheet uses).
    SWORD[name]    = where the sword is meant to be: "held" (Child Of grip, §4.3), "board"
                     (flat under both feet, see board_world_matrix), "board_left" (under the
                     left foot only), "float" (floating at the grip of this pose, about to be
                     grabbed), "above" (tumbling above the head); missing = not involved
    GROUNDED       poses whose soles sit at Roblox y = -3.0 relative to the HRP (ROOT_LOC
                   compensates crouches), so with an upright object the ground / board top is
                   always at HRP - 3.0, like the stand pose (§4.4)
    TWO_HANDED     held poses with the left hand on the grip LEFT_GRIP_SPACING below the right

API
    key_pose(rig, frame, name, blend=None, weight=1.0, jitter=0.0, seed=0, interpolation="BEZIER")
    blend_pose(a, b, w) -> pose dict          mirror_pose(name) -> pose dict
    apply_pose(rig, pose)                     full_pose(name or dict) -> pose dict
    board_world_matrix(rig, mode="board")     sword world matrix for the board poses
A "pose dict" maps every bone to (x, y, z) degrees plus the key "_loc" (Root location).
Wherever a pose is expected, a POSES name or a (partial) pose dict works.

Sign conventions (Roblox character axes: X right, Y up, Z back; measured on the Blender rig
by turning each bone +30 deg and watching its part):

  bone             +X                          +Y                          +Z
  Root / Waist     lean back (chest up)        twist to own left           lean to own left
  Neck             look up                     look to own left            tilt head to left shoulder
  Right/LeftShoulder  arm swings forward/up    twist: front of the arm     arm swings toward +X: RIGHT arm
                                               turns to the left           raises sideways, LEFT arm swings
                                                                           across the body (raise left: -Z)
  Right/LeftElbow  forearm bends forward/up = flexion; only X, always 0..150 (never negative)
  Right/LeftWrist  fingers swing forward/up;   hand turns left; the held   rolls the held sword about
                   the held blade tilts toward blade turns left           its blade (edge direction)
                   the elbow (-X: toward the fingertips, along the forearm)
  Right/LeftHip    leg swings forward (flex)   twist: toes turn left       leg swings toward +X: RIGHT leg
                                                                           out, LEFT leg in (left out: -Z)
  Right/LeftKnee   -X bends the knee (foot goes back) = flexion; only X, always -150..0
  Right/LeftAnkle  toes up (-X: toes point)    toes turn left              sole turns to face right

Extrinsic XYZ (R = Rz*Ry*Rx): with the limb hanging, Y is its own twist, so (0, y, z) =
"twist by y, then raise sideways by z" and (x, 0, 0) swings through the front. Mirroring
left <-> right maps (x, y, z) to (x, -y, -z) and the Root location x to -x.

How the poses are made: POSE_SPECS below describes each pose by limb directions and IK goals
(feet flat on the ground, hand on the grip, blade direction, ...); `python poses.py --author`
solves them (aim_arm / aim_leg + a small pattern-search IK) and rewrites the generated POSES /
ROOT_LOC block. The numbers in that block are the source of truth at runtime; edit them
directly or edit the spec and re-author.

    python tools/blender/intro/poses.py [--check] [--author] [--sheet out.png [--only a,b]
                                        [--tile 260] [--cols 6] [--view x,y,z]]
"""
import math
import os
import random
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (_HERE, os.path.dirname(_HERE)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

try:
    from . import rig as _rig
except ImportError:
    import rig as _rig

from mathutils import Euler, Matrix, Vector  # noqa: E402  (bpy is imported by rig)

BONES = _rig.BONES
LOC_KEY = "_loc"
LEFT_GRIP_SPACING = 0.62   # two-handed: left grip point this far below the right one (studs)

# ============================================================================ pose design
# Directions are Roblox character axes (x right, y up, z back; forward = -z). Arms: (upper arm,
# forearm[, bend hint]) in the torso (Waist) frame; legs: (thigh, shin[, bend hint]) in the
# pelvis (Root) frame. root/waist/neck/wrists/ankles: Euler degrees. IK goals (HRP space):
#   feet={side: (x, z)}        sole flat at y = -3 with the foot centre at (x, z) (+ ROOT_LOC y)
#   foot_target={side: ((x, y, z), toe_pitch_deg)}   free foot placement
#   blade=(dx, dy, dz)         right-hand sword direction (keeps the hand where it is)
#   grip=((x, y, z), blade)    right-hand grip position + blade direction
#   two_hand=True              left hand on the grip, LEFT_GRIP_SPACING below the right hand
#   hand_target={side: (x, y, z)}   hand centre;  hand_down={side: (x, z)}  palm on y = -3
POSE_SPECS = {}


def _spec(name, body, note, sword=None, grounded=False, two_hand=False, **kw):
    kw.update(body=body, note=note, sword=sword, grounded=grounded, two_hand=two_hand)
    POSE_SPECS[name] = kw


_spec("stand", (0, 0, 0), "upright, feet on the ground (relaxed reference)", grounded=True,
      rarm=((0.07, -1, 0.0), (0.05, -1, -0.12)), larm=((-0.07, -1, 0.0), (-0.05, -1, -0.12)),
      rleg=((0.03, -1, 0), (0.03, -1, 0.02)), lleg=((-0.03, -1, 0), (-0.03, -1, 0.02)),
      feet={"Right": (0.52, -0.1), "Left": (-0.52, -0.1)})

_spec("fall_spread", (-90, 0, 0), "body horizontal, face down (belly to the ground), head toward the travel "
      "direction: spread-eagle skydiver arch",
      waist=(14, 0, 0), neck=(38, 0, 0),
      rarm=((1, 0.45, 0.25), (0.55, 1, 0.05)), larm=((-1, 0.45, 0.25), (-0.55, 1, 0.05)),
      rwrist=(-12, 0, 0), lwrist=(-12, 0, 0),
      rleg=((0.5, -1, 0.22), (0.3, -0.7, 0.78)), lleg=((-0.5, -1, 0.22), (-0.3, -0.7, 0.78)),
      rankle=(-35, 0, 0), lankle=(-35, 0, 0))

_spec("fall_tumble_a", (-45, 0, 20), "any orientation: tumbling key A (the scene rolls the object); "
      "sheet shows it pitched 45 deg",
      waist=(-22, 20, 10), neck=(-20, -25, 12),
      rarm=((0.8, 0.75, -0.45), (0.15, 0.5, -1.0)), larm=((-1, -0.25, 0.55), (-0.55, -0.75, 0.6)),
      rleg=((0.15, -0.35, -1), (0.1, -1, 0.25)), lleg=((-0.3, -1, 0.35), (-0.2, -0.45, 1)),
      rankle=(-25, 0, 0), lankle=(-40, 0, 0))

_spec("fall_tumble_b", (-130, 0, -25), "any orientation: tumbling key B (alternate with fall_tumble_a "
      "while the object rolls); sheet shows it upside down",
      waist=(22, -18, -10), neck=(25, 18, -8),
      rarm=((0.95, 0.55, 0.6), (0.3, 1, -0.1)), larm=((-0.45, 1, 0.45), (-0.65, 0.45, 0.9)),
      rleg=((0.3, -1, 0.65), (0.15, -0.35, 1)), lleg=((-0.35, -0.75, -0.65), (-0.25, -1, -0.05)),
      rankle=(-35, 0, 0), lankle=(-20, 0, 0))

_spec("look_around", (-60, 0, 0), "falling chest-down, body pitched ~30 deg up from horizontal; "
      "twists and looks over the left shoulder",
      waist=(8, 28, 4), neck=(5, 55, 6),
      rarm=((1, 0.25, 0.1), (0.85, 0.5, -0.25)), larm=((-1, 0.05, 0.25), (-0.8, 0.55, -0.1)),
      rleg=((0.4, -1, 0.15), (0.28, -0.7, 0.65)), lleg=((-0.3, -1, 0.05), (-0.2, -0.55, 0.8)),
      rankle=(-30, 0, 0), lankle=(-30, 0, 0))

_spec("look_up_reach", (25, 0, 0), "falling feet-first, leaning back ~25 deg: looks up and reaches the right "
      "hand toward the sword above", sword="above",
      waist=(18, 0, -4), neck=(50, 0, -5),
      rarm=((0.45, 1, -0.25), (0.35, 1, -0.3)), larm=((-1, -0.15, 0.25), (-0.85, -0.45, 0.35)),
      rwrist=(-10, 0, 0),
      rleg=((0.25, -1, -0.2), (0.15, -1, 0.35)), lleg=((-0.25, -1, 0.15), (-0.2, -0.75, 0.65)),
      rankle=(-30, 0, 0), lankle=(-30, 0, 0))

_spec("reach_right", (15, 0, 0), "falling roughly upright: right arm stretched out/up toward the sword at "
      "the right, torso stretched after it",
      waist=(8, -18, -14), neck=(18, -35, -8),
      rarm=((0.85, 0.5, -0.35), (0.85, 0.55, -0.4)), larm=((-0.75, -0.55, 0.45), (-0.55, -0.6, -0.3)),
      rwrist=(-15, 0, 0),
      rleg=((0.35, -1, 0.15), (0.25, -0.65, 0.7)), lleg=((-0.2, -0.85, -0.5), (-0.15, -1, 0.25)),
      rankle=(-30, 0, 0), lankle=(-20, 0, 0))

_spec("flail_a", (10, 0, 0), "falling roughly upright, windmilling (alternate with flail_b)",
      waist=(-10, -22, 12), neck=(12, -30, -12),
      rarm=((0.6, 0.85, 0.5), (0.15, 0.55, 0.95)), larm=((-0.55, -0.25, -0.9), (-0.05, 0.4, -1)),
      rleg=((0.25, -0.5, -0.9), (0.2, -1, 0.1)), lleg=((-0.3, -1, 0.45), (-0.2, -0.35, 1)),
      rankle=(-20, 0, 0), lankle=(-35, 0, 0))

_spec("flail_b", (10, 0, 0), "falling roughly upright, windmilling (alternate with flail_a)",
      waist=(10, 22, -10), neck=(-5, 25, 10),
      rarm=((0.65, -0.35, -0.8), (0.15, 0.45, -1)), larm=((-0.85, 0.75, 0.25), (-0.35, 1, 0.35)),
      rleg=((0.3, -1, 0.5), (0.2, -0.3, 1)), lleg=((-0.25, -0.55, -0.85), (-0.2, -1, 0.05)),
      rankle=(-35, 0, 0), lankle=(-20, 0, 0))

_spec("grab_blade", (20, 0, 0), "falling, leaning back ~20 deg: the right hand has just closed on the grip "
      "overhead, blade up", sword="held",
      waist=(15, -8, -6), neck=(40, -10, -5),
      rarm=((0.25, 0.75, -0.65), (0.2, 0.8, -0.6)), blade=(0.1, 1, -0.1),
      larm=((-1, 0.2, 0.3), (-0.7, 0.65, 0.3)),
      rleg=((0.25, -1, -0.25), (0.15, -0.9, 0.45)), lleg=((-0.3, -1, 0.2), (-0.2, -0.6, 0.8)),
      rankle=(-30, 0, 0), lankle=(-30, 0, 0))

_spec("struggle_a", (25, 0, -10), "falling: the spinning sword yanks the right arm up-right, the body is "
      "dragged after it, left arm flung back", sword="held",
      waist=(-5, -25, -14), neck=(22, -35, -10),
      rarm=((0.85, 0.5, -0.4), (0.85, 0.55, -0.3)), blade=(0.6, 0.3, -0.75),
      larm=((-0.9, -0.1, 0.45), (-0.6, 0.4, 0.6)),
      rleg=((0.3, -0.6, -0.75), (0.2, -1, 0.15)), lleg=((-0.25, -1, 0.35), (-0.2, -0.4, 0.9)),
      rankle=(-25, 0, 0), lankle=(-35, 0, 0))

_spec("struggle_b", (10, 0, 15), "falling: the sword drags down-left, knees pulled up, both hands fight "
      "for the grip", sword="held", two_hand=True,
      waist=(-25, 25, 10), neck=(-20, 20, 5),
      rarm=((-0.15, -0.5, -0.85), (-0.45, -0.45, -0.8)), grip=((-0.8, -0.75, -1.85), (-0.5, -0.6, -0.6)),
      larm=((-0.3, -0.6, -0.7), (0.2, -0.5, -0.8)),
      rleg=((0.25, -0.3, -0.95), (0.15, -1, 0.25)), lleg=((-0.3, -0.55, -0.75), (-0.2, -1, 0.35)),
      rankle=(-30, 0, 0), lankle=(-30, 0, 0))

_spec("resonance_brace", (0, 0, 0), "mid-air, curled: clutching the sword upright to the chest with both "
      "hands as the energy builds", sword="held", two_hand=True,
      waist=(-20, 0, 0), neck=(-18, 0, 0),
      rarm=((0.2, -0.6, -0.75), (-0.35, 0.75, -0.4)), grip=((0.6, 0.1, -1.5), (0.2, 1, 0.05)),
      larm=((-0.2, -0.6, -0.75), (0.35, 0.6, -0.6)),
      rleg=((0.2, -0.2, -1), (0.1, -1, 0.15)), lleg=((-0.2, -0.25, -1), (-0.1, -1, 0.25)),
      rankle=(-30, 0, 0), lankle=(-30, 0, 0))

_spec("resonance_burst", (-10, 0, 0), "mid-air, upright: arms flung wide, chest up, head back, sword thrust "
      "out and up to the right", sword="held",
      waist=(22, 0, 0), neck=(30, 0, 0),
      rarm=((1, 0.55, 0.35), (1, 0.6, 0.35)), blade=(0.65, 0.75, 0.0),
      larm=((-1, 0.55, 0.35), (-1, 0.6, 0.35)), lwrist=(-20, 0, 0),
      rleg=((0.5, -1, 0.25), (0.45, -1, 0.4)), lleg=((-0.5, -1, 0.25), (-0.45, -1, 0.4)),
      rankle=(-35, 0, 0), lankle=(-35, 0, 0))

_spec("sword_ready", (0, 0, 0), "upright (mid-air or standing): two-handed grip in front of the belly, "
      "blade up-forward", sword="held", two_hand=True,
      waist=(-4, 0, 0), neck=(-5, 0, 0),
      rarm=((0.25, -0.55, -0.8), (-0.25, 0.15, -1)), grip=((0.25, -0.3, -1.65), (0.0, 0.75, -0.66)),
      larm=((-0.25, -0.55, -0.8), (0.3, 0.1, -1)),
      rleg=((0.3, -1, 0.25), (0.25, -0.85, 0.5)), lleg=((-0.25, -1, -0.35), (-0.2, -1, 0.1)),
      rankle=(-25, 0, 0), lankle=(-10, 0, 0))

_spec("swing_wind", (0, 0, 0), "upright: wind-up, sword cocked high behind the right shoulder, torso coiled "
      "right, left arm aimed forward", sword="held",
      waist=(8, -35, -8), neck=(0, 32, 5),
      rarm=((0.85, 0.55, 0.2), (0.05, 0.9, 0.35)), blade=(0.45, 0.55, 0.7),
      larm=((-0.4, 0.15, -1), (-0.35, 0.22, -1)), lwrist=(-15, 0, 0),
      rleg=((0.35, -1, 0.3), (0.2, -0.75, 0.6)), lleg=((-0.3, -1, -0.35), (-0.25, -1, 0.0)),
      rankle=(-25, 0, 0), lankle=(-10, 0, 0))

_spec("swing_follow", (0, 0, 0), "upright: follow-through of a one-handed diagonal slash ending low-left, "
      "torso uncoiled left, left arm flung back", sword="held",
      waist=(-15, 40, 10), neck=(-12, -25, 0),
      rarm=((-0.3, -0.55, -0.8), (-0.6, -0.45, -0.65)), blade=(-0.6, -0.55, -0.58),
      larm=((-0.6, 0.1, 0.8), (-0.4, 0.4, 0.8)),
      rleg=((0.35, -1, 0.45), (0.25, -0.5, 0.85)), lleg=((-0.35, -0.8, -0.6), (-0.25, -1, 0.05)),
      rankle=(-30, 0, 0), lankle=(-10, 0, 0))

_spec("mount_crouch", (0, 0, 0), "upright: crouched, feet level about to plant on the sword-board right "
      "under them (soles at -3)", sword="board", grounded=True,
      root=(-10, 0, 0), waist=(-25, 0, 0), neck=(-12, 0, 0),
      rarm=((0.7, -0.5, -0.5), (0.5, -0.7, -0.45)), larm=((-0.85, -0.3, 0.45), (-0.75, 0.15, 0.6)),
      rleg=((0.35, -0.25, -1), (0.2, -1, 0.4)), lleg=((-0.35, -0.25, -1), (-0.2, -1, 0.4)),
      feet={"Right": (0.85, -0.1), "Left": (-0.85, -0.1)}, loc=(0, -1.0, 0))

_spec("surf_stance", (0, 0, 0), "upright on the sword-board: side-on stance, travel direction = the "
      "character's left (-X): yaw the object so -X points along the flight; board along X under the "
      "feet, tip toward the left foot, soles at -3", sword="board", grounded=True,
      waist=(-14, 25, 8), neck=(0, 50, 4),
      rarm=((0.85, 0.15, 0.5), (0.55, 0.6, 0.55)), larm=((-0.9, 0.0, -0.45), (-0.85, 0.25, -0.4)),
      rleg=((0.55, -0.7, -0.5), (0.15, -1, 0.45)), lleg=((-0.55, -0.7, -0.5), (-0.15, -1, 0.45)),
      feet={"Right": (1.2, 0.0), "Left": (-1.2, 0.0)}, loc=(0, -0.9, 0))

_spec("brake_lean", (0, 0, 0), "on the sword-board turned across the motion (board along X, travel = "
      "forward -Z): heel-side brake leaning back hard, arms forward; the scene may tilt object + "
      "board back further", sword="board", grounded=True,
      root=(20, 0, 0), waist=(6, 0, 0), neck=(-18, 0, 0),
      rarm=((0.35, -0.15, -0.95), (0.2, 0.15, -1)), larm=((-0.35, -0.15, -0.95), (-0.2, 0.15, -1)),
      rleg=((0.45, -0.7, -0.6), (0.25, -1, 0.3)), lleg=((-0.45, -0.7, -0.6), (-0.25, -1, 0.3)),
      feet={"Right": (1.15, -0.9), "Left": (-1.15, -0.9)}, loc=(0, -1.0, 0))

_spec("brake_strain", (0, 0, 0), "like brake_lean but harder: deeper, more lean back, right arm thrown "
      "back, left arm forward, head forward straining", sword="board", grounded=True,
      root=(30, 0, 0), waist=(2, 15, 0), neck=(-24, -12, 0),
      rarm=((0.6, 0.3, 0.75), (0.4, 0.6, 0.7)), larm=((-0.3, 0.1, -1), (-0.15, 0.35, -1)),
      rleg=((0.5, -0.55, -0.7), (0.25, -1, 0.35)), lleg=((-0.5, -0.55, -0.7), (-0.25, -1, 0.35)),
      feet={"Right": (1.25, -1.15), "Left": (-1.25, -1.15)}, loc=(0, -1.4, 0))

_spec("stop_impact", (0, 0, 0), "on the sword-board (along X): deep impact crouch, right hand slammed down "
      "on the board, left arm flung up-back, head up", sword="board", grounded=True,
      root=(-24, 0, 0), waist=(-34, -12, 0), neck=(55, 8, 0),
      rarm=((0.1, -0.8, -0.55), (0.0, -1, -0.1)), larm=((-0.8, 0.1, 0.6), (-0.6, 0.55, 0.6)),
      rleg=((0.75, -0.35, -0.55), (0.35, -1, 0.15)), lleg=((-0.75, -0.35, -0.55), (-0.35, -1, 0.15)),
      feet={"Right": (1.3, 0.1), "Left": (-1.3, 0.1)}, loc=(0, -1.5, 0),
      hand_down={"Right": (0.2, 0.1)})

_spec("step_off", (0, 0, 0), "upright: standing on the board with the left foot (soles at -3), right "
      "leg swung forward off the edge, toes pointing down, looking down at the landing", sword="board_left", grounded=True,
      root=(4, 0, 0), waist=(0, 0, 0), neck=(-30, 0, 0),
      rarm=((0.65, -0.75, 0.0), (0.55, -0.55, -0.45)), larm=((-0.65, -0.75, 0.1), (-0.55, -0.5, -0.4)),
      rleg=((0.12, -0.6, -0.8), (0.1, -0.85, -0.45)), lleg=((-0.05, -1, 0.1), (-0.05, -1, 0.2)),
      feet={"Left": (-0.55, 0.35)}, foot_target={"Right": ((0.6, -2.75, -1.35), -45)}, loc=(0, -0.1, 0))

_spec("land_crouch", (0, 0, 0), "upright: landing crouch on the ground (soles at -3), arms out for balance",
      grounded=True,
      root=(-10, 0, 0), waist=(-18, 0, 0), neck=(18, 0, 0),
      rarm=((0.6, -0.6, -0.55), (0.45, -0.3, -0.85)), larm=((-0.6, -0.55, -0.45), (-0.45, -0.25, -0.85)),
      rleg=((0.3, -0.55, -0.8), (0.15, -1, 0.45)), lleg=((-0.3, -0.55, -0.8), (-0.15, -1, 0.45)),
      feet={"Right": (0.8, 0.05), "Left": (-0.8, 0.05)}, loc=(0, -1.0, 0))

_spec("reach_sword", (0, 0, 0), "standing: right arm reaching forward-right to the sword floating upright "
      "at chest height; the hand is exactly at the grip (switch held to 1 here)", sword="float",
      grounded=True,
      waist=(-8, -14, 0), neck=(-5, -14, 0),
      rarm=((0.55, 0.05, -1), (0.5, 0.1, -1), (0, 1, 0)), blade=(0, 1, 0),
      larm=((-0.25, -0.95, 0.2), (-0.2, -0.9, -0.25)),
      rleg=((0.15, -1, -0.3), (0.12, -1, 0.0)), lleg=((-0.15, -1, 0.2), (-0.12, -1, 0.3)),
      feet={"Right": (0.6, -0.8), "Left": (-0.6, 0.45)})

_spec("hold_sword_low", (0, 0, 0), "standing: sword held down at the right side, tip low and forward",
      sword="held", grounded=True,
      waist=(0, 0, 0), neck=(-8, 0, 0),
      rarm=((0.25, -1, -0.1), (0.25, -0.95, -0.3)), blade=(0.25, -0.6, -0.75),
      larm=((-0.15, -1, 0.05), (-0.12, -1, -0.15)),
      rleg=((0.05, -1, 0), (0.05, -1, 0.05)), lleg=((-0.05, -1, 0), (-0.05, -1, 0.05)),
      feet={"Right": (0.62, -0.1), "Left": (-0.62, -0.05)})

_spec("hero", (0, 0, 0), "standing: confident wide stance, chest up, chin up, left fist on the hip, sword "
      "angled down-out to the right", sword="held", grounded=True,
      waist=(6, 8, -3), neck=(6, -14, 3),
      rarm=((0.55, -0.85, -0.05), (0.55, -0.8, -0.25)), blade=(0.6, -0.45, -0.65),
      larm=((-0.75, -0.65, 0.25), (0.75, -0.55, -0.1)), hand_target={"Left": (-1.38, -0.5, 0.05)},
      rleg=((0.25, -1, 0.0), (0.2, -1, 0.1)), lleg=((-0.25, -1, 0.0), (-0.2, -1, 0.1)),
      feet={"Right": (0.98, -0.15), "Left": (-0.98, 0.1)})

BODY = {n: (tuple(s["body"]), s["note"]) for n, s in POSE_SPECS.items()}
SWORD = {n: s["sword"] for n, s in POSE_SPECS.items() if s["sword"]}
GROUNDED = {n for n, s in POSE_SPECS.items() if s["grounded"]}
TWO_HANDED = {n for n, s in POSE_SPECS.items() if s["two_hand"]}

# ============================================================================ generated poses
# Written by `python poses.py --author` from POSE_SPECS (degrees, joint space).
# <POSES>
POSES = {
    "stand": {
        "LeftShoulder": (0, -3.5, -4),
        "LeftElbow": (6.9, 0, 0),
        "RightShoulder": (0, 3.5, 4),
        "RightElbow": (6.9, 0, 0),
        "LeftHip": (0, 0, -0.6),
        "LeftAnkle": (0, 0, 0.6),
        "RightHip": (0, 0, 0.6),
        "RightAnkle": (0, 0, -0.6),
    },
    "fall_spread": {
        "Waist": (14, 0, 0),
        "Neck": (38, 0, 0),
        "LeftShoulder": (-23.7, 56.5, -134.4),
        "LeftElbow": (38, 0, 0),
        "LeftWrist": (-12, 0, 0),
        "RightShoulder": (-23.7, -56.5, 134.4),
        "RightElbow": (38, 0, 0),
        "RightWrist": (-12, 0, 0),
        "LeftHip": (-11.1, 2.3, -27),
        "LeftKnee": (-34.7, 0, 0),
        "LeftAnkle": (-35, 0, 0),
        "RightHip": (-11.1, -2.3, 27),
        "RightKnee": (-34.7, 0, 0),
        "RightAnkle": (-35, 0, 0),
    },
    "fall_tumble_a": {
        "Waist": (-22, 20, 10),
        "Neck": (-20, -25, 12),
        "LeftShoulder": (-88, -61.9, 11.8),
        "LeftElbow": (34.4, 0, 0),
        "RightShoulder": (24.5, -23.6, 122.8),
        "RightElbow": (45, 0, 0),
        "LeftHip": (-18.6, -3.9, -15.4),
        "LeftKnee": (-45.5, 0, 0),
        "LeftAnkle": (-40, 0, 0),
        "RightHip": (70, -5.9, 7.4),
        "RightKnee": (-84, 0, 0),
        "RightAnkle": (-25, 0, 0),
    },
    "fall_tumble_b": {
        "Waist": (22, -18, -10),
        "Neck": (25, 18, -8),
        "LeftShoulder": (-147.8, -44.6, 0.4),
        "LeftElbow": (36.1, 0, 0),
        "RightShoulder": (-36.9, -37, 144.4),
        "RightElbow": (53.8, 0, 0),
        "LeftHip": (39.3, 12.6, -14.9),
        "LeftKnee": (-36.8, 0, 0),
        "LeftAnkle": (-20, 0, 0),
        "RightHip": (-32, 3.4, 14.6),
        "RightKnee": (-37.4, 0, 0),
        "RightAnkle": (-35, 0, 0),
    },
    "look_around": {
        "Waist": (8, 28, 4),
        "Neck": (5, 55, 6),
        "LeftShoulder": (-19, 41.8, -105.8),
        "LeftElbow": (37.2, 0, 0),
        "RightShoulder": (-6.1, -25, 106.6),
        "RightElbow": (25.6, 0, 0),
        "LeftHip": (-2.7, -2.1, -16.6),
        "LeftKnee": (-51.1, 0, 0),
        "LeftAnkle": (-30, 0, 0),
        "RightHip": (-7.9, 0.4, 21.7),
        "RightKnee": (-32.8, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "look_up_reach": {
        "Waist": (18, 0, -4),
        "Neck": (50, 0, -5),
        "LeftShoulder": (-49.4, -71.6, -33.5),
        "LeftElbow": (19.5, 0, 0),
        "RightShoulder": (22.2, -54, 137.5),
        "RightElbow": (5.6, 0, 0),
        "RightWrist": (-10, 0, 0),
        "LeftHip": (-8.3, -1.2, -13.9),
        "LeftKnee": (-31.7, 0, 0),
        "LeftAnkle": (-30, 0, 0),
        "RightHip": (11.1, -7.6, 12.5),
        "RightKnee": (-30.6, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "reach_right": {
        "Waist": (8, -18, -14),
        "Neck": (18, -35, -8),
        "LeftShoulder": (-26.5, -12.7, -47.5),
        "LeftElbow": (47.3, 0, 0),
        "RightShoulder": (23.8, -34.2, 106.5),
        "RightElbow": (3, 0, 0),
        "RightWrist": (-15, 0, 0),
        "LeftHip": (29.9, 5.1, -10.3),
        "LeftKnee": (-43.9, 0, 0),
        "LeftAnkle": (-20, 0, 0),
        "RightHip": (-8.1, 1.9, 19),
        "RightKnee": (-37.1, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "flail_a": {
        "Waist": (-10, -22, 12),
        "Neck": (12, -30, -12),
        "LeftShoulder": (60.4, 17.2, -38.1),
        "LeftElbow": (44.9, 0, 0),
        "RightShoulder": (25.7, -181.4, 145.5),
        "RightElbow": (36.2, 0, 0),
        "LeftHip": (-23.4, -5.6, -14.3),
        "LeftKnee": (-45.4, 0, 0),
        "LeftAnkle": (-35, 0, 0),
        "RightHip": (59.2, -8.6, 12.5),
        "RightKnee": (-64.9, 0, 0),
        "RightAnkle": (-20, 0, 0),
    },
    "flail_b": {
        "Waist": (10, 22, -10),
        "Neck": (-5, 25, 10),
        "LeftShoulder": (121.1, 104.6, -9.5),
        "LeftElbow": (28.8, 0, 0),
        "RightShoulder": (-128.1, -159.1, 217.3),
        "RightElbow": (52.1, 0, 0),
        "LeftHip": (55.5, 8.6, -12.2),
        "LeftKnee": (-58.4, 0, 0),
        "LeftAnkle": (-20, 0, 0),
        "RightHip": (-25.8, 6.4, 13.6),
        "RightKnee": (-45.7, 0, 0),
        "RightAnkle": (-35, 0, 0),
    },
    "grab_blade": {
        "Waist": (15, -8, -6),
        "Neck": (40, -10, -5),
        "LeftShoulder": (134.4, 113.3, 35.6),
        "LeftElbow": (30.2, 0, 0),
        "RightShoulder": (-49.7, -140.8, 204.3),
        "RightWrist": (-64.1, 0, 3.5),
        "LeftHip": (-10.8, -1.6, -16.4),
        "LeftKnee": (-40.9, 0, 0),
        "LeftAnkle": (-30, 0, 0),
        "RightHip": (13.7, -5.1, 12.8),
        "RightKnee": (-40.1, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "struggle_a": {
        "Waist": (-5, -25, -14),
        "Neck": (22, -35, -10),
        "LeftShoulder": (59.3, 121.2, -28.4),
        "LeftElbow": (35.7, 0, 0),
        "RightShoulder": (-152.5, -151.1, 287.8),
        "RightWrist": (-40.6, 0, -1.5),
        "LeftHip": (-18.9, -6.2, -11.9),
        "LeftKnee": (-45.6, 0, 0),
        "LeftAnkle": (-35, 0, 0),
        "RightHip": (49.4, -11.1, 13.9),
        "RightKnee": (-58.1, 0, 0),
        "RightAnkle": (-25, 0, 0),
    },
    "struggle_b": {
        "Waist": (-25, 25, 10),
        "Neck": (-20, 20, 5),
        "LeftShoulder": (-86.1, 234.6, 120.5),
        "LeftElbow": (21.1, 0, 0),
        "LeftWrist": (75.1, 0, 41.3),
        "RightShoulder": (-119.8, -195.2, 131.8),
        "RightWrist": (-63.1, 0, 8.2),
        "LeftHip": (51.3, 10.6, -15.7),
        "LeftKnee": (-70.7, 0, 0),
        "LeftAnkle": (-30, 0, 0),
        "RightHip": (70.4, -10.9, 11.8),
        "RightKnee": (-84.6, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "resonance_brace": {
        "Waist": (-20, 0, 0),
        "Neck": (-18, 0, 0),
        "LeftShoulder": (-100, 237.4, 157.8),
        "LeftElbow": (6.1, 0, 0),
        "LeftWrist": (7.1, 0, 1.4),
        "RightShoulder": (-152.4, -215.5, 199.9),
        "RightElbow": (98, 0, 0),
        "RightWrist": (6.5, 0, -24.3),
        "LeftHip": (74.7, 9.1, -8.5),
        "LeftKnee": (-88.9, 0, 0),
        "LeftAnkle": (-30, 0, 0),
        "RightHip": (77.5, -9.7, 7.9),
        "RightKnee": (-86.2, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "resonance_burst": {
        "Waist": (22, 0, 0),
        "Neck": (30, 0, 0),
        "LeftShoulder": (-197.9, 197.3, 66.7),
        "LeftElbow": (2.1, 0, 0),
        "LeftWrist": (-20, 0, 0),
        "RightShoulder": (-188.9, -159.9, 302.4),
        "RightWrist": (-55.1, 0, 7.5),
        "LeftHip": (-12.6, 4.7, -27.6),
        "LeftKnee": (-7.8, 0, 0),
        "LeftAnkle": (-35, 0, 0),
        "RightHip": (-12.6, -4.7, 27.6),
        "RightKnee": (-7.8, 0, 0),
        "RightAnkle": (-35, 0, 0),
    },
    "sword_ready": {
        "Waist": (-4, 0, 0),
        "Neck": (-5, 0, 0),
        "LeftShoulder": (-106, 243.5, 145.5),
        "LeftElbow": (1.6, 0, 0),
        "LeftWrist": (7.7, 0, 8),
        "RightShoulder": (-141.7, -199.8, 158.3),
        "RightElbow": (22.2, 0, 0),
        "RightWrist": (-13.4, 0, -19.2),
        "LeftHip": (18.8, 4.9, -12.4),
        "LeftKnee": (-24.5, 0, 0),
        "LeftAnkle": (-10, 0, 0),
        "RightHip": (-13.5, 0.3, 16.6),
        "RightKnee": (-16, 0, 0),
        "RightAnkle": (-25, 0, 0),
    },
    "swing_wind": {
        "Waist": (8, -35, -8),
        "Neck": (0, 32, 5),
        "LeftShoulder": (-92.5, 157, 153),
        "LeftElbow": (4.5, 0, 0),
        "LeftWrist": (-15, 0, 0),
        "RightShoulder": (-95.1, -77.8, 239.6),
        "RightWrist": (-79.2, 0, 3.9),
        "LeftHip": (18.6, 5.9, -14.7),
        "LeftKnee": (-18.7, 0, 0),
        "LeftAnkle": (-10, 0, 0),
        "RightHip": (-15.9, -4.9, 20.7),
        "RightKnee": (-22.2, 0, 0),
        "RightAnkle": (-25, 0, 0),
    },
    "swing_follow": {
        "Waist": (-15, 40, 10),
        "Neck": (-12, -25, 0),
        "LeftShoulder": (-95.9, 36.8, 160.7),
        "LeftElbow": (20.9, 0, 0),
        "RightShoulder": (-115.9, -197.2, 150),
        "RightWrist": (-71.8, 0, 13.6),
        "LeftHip": (35.3, 11.2, -15.8),
        "LeftKnee": (-38.3, 0, 0),
        "LeftAnkle": (-10, 0, 0),
        "RightHip": (-23.1, 5.8, 16.8),
        "RightKnee": (-34.1, 0, 0),
        "RightAnkle": (-30, 0, 0),
    },
    "mount_crouch": {
        "Root": (-10, 0, 0),
        "Waist": (-25, 0, 0),
        "Neck": (-12, 0, 0),
        "LeftShoulder": (-109.6, 61.7, 177.4),
        "LeftElbow": (28.3, 0, 0),
        "RightShoulder": (-135.6, -224.1, 268.7),
        "RightElbow": (16.7, 0, 0),
        "LeftHip": (45.5, 4.4, -10.4),
        "LeftKnee": (-72.4, 0, 0),
        "LeftAnkle": (35.4, 0, 13.4),
        "RightHip": (45.5, -4.4, 10.4),
        "RightKnee": (-72.4, 0, 0),
        "RightAnkle": (35.4, 0, -13.4),
    },
    "surf_stance": {
        "Waist": (-14, 25, 8),
        "Neck": (0, 50, 4),
        "LeftShoulder": (-129.4, 125.3, 134.8),
        "LeftElbow": (15, 0, 0),
        "RightShoulder": (-88, -59.9, 187.7),
        "RightElbow": (31.8, 0, 0),
        "LeftHip": (18.2, 2, -20.5),
        "LeftKnee": (-48.1, 0, 0),
        "LeftAnkle": (27.1, 0, 23.1),
        "RightHip": (18.2, -2, 20.5),
        "RightKnee": (-48.1, 0, 0),
        "RightAnkle": (27.1, 0, -23.1),
    },
    "brake_lean": {
        "Root": (20, 0, 0),
        "Waist": (6, 0, 0),
        "Neck": (-18, 0, 0),
        "LeftShoulder": (-106.3, 165.2, 154.3),
        "LeftElbow": (19, 0, 0),
        "RightShoulder": (-106.3, -165.2, 205.7),
        "RightElbow": (19, 0, 0),
        "LeftHip": (30, 2, -20.4),
        "LeftKnee": (-63.5, 0, 0),
        "LeftAnkle": (11, 0, 18.7),
        "RightHip": (30, -2, 20.4),
        "RightKnee": (-63.5, 0, 0),
        "RightAnkle": (11, 0, -18.7),
    },
    "brake_strain": {
        "Root": (30, 0, 0),
        "Waist": (2, 15, 0),
        "Neck": (-24, -12, 0),
        "LeftShoulder": (-92.1, 162.6, 154.7),
        "LeftElbow": (15.8, 0, 0),
        "RightShoulder": (-72.5, -38.6, 179.8),
        "RightElbow": (20.9, 0, 0),
        "LeftHip": (30.3, 2.9, -23.8),
        "LeftKnee": (-68.2, 0, 0),
        "LeftAnkle": (4.5, 0, 18.9),
        "RightHip": (30.3, -2.9, 23.8),
        "RightKnee": (-68.2, 0, 0),
        "RightAnkle": (4.5, 0, -18.9),
    },
    "stop_impact": {
        "Root": (-24, 0, 0),
        "Waist": (-34, -12, 0),
        "Neck": (55, 8, 0),
        "LeftShoulder": (-75.3, 51.9, 191.3),
        "LeftElbow": (28.3, 0, 0),
        "RightShoulder": (-234.5, -5.3, 175.3),
        "RightElbow": (3.5, 0, 0),
        "RightWrist": (6.8, 0, 6.7),
        "LeftHip": (43.4, 13.7, -19.7),
        "LeftKnee": (-47.2, 0, 0),
        "LeftAnkle": (22.2, 0, 25.2),
        "RightHip": (43.4, -13.7, 19.7),
        "RightKnee": (-47.2, 0, 0),
        "RightAnkle": (22.2, 0, -25.2),
    },
    "step_off": {
        "Root": (4, 0, 0),
        "Neck": (-30, 0, 0),
        "LeftShoulder": (-5.8, 7.2, 318.4),
        "LeftElbow": (34.7, 0, 0),
        "RightShoulder": (-360, -5, 40.9),
        "RightElbow": (30.3, 0, 0),
        "LeftHip": (-14.2, -0.6, -1.6),
        "LeftKnee": (-13.6, 0, 0),
        "LeftAnkle": (23.9, 0, 1.8),
        "RightHip": (37.8, -0.3, 2.8),
        "RightKnee": (-15.6, 0, 0),
        "RightAnkle": (-47.3, 0, -1.2),
    },
    "land_crouch": {
        "Root": (-10, 0, 0),
        "Waist": (-18, 0, 0),
        "Neck": (18, 0, 0),
        "LeftShoulder": (29.6, 11.6, 319),
        "LeftElbow": (31.3, 0, 0),
        "RightShoulder": (-326.3, -11.7, 37.3),
        "RightElbow": (25.8, 0, 0),
        "LeftHip": (34.6, 1.8, -8.9),
        "LeftKnee": (-60.6, 0, 0),
        "LeftAnkle": (35.2, 0, 11.1),
        "RightHip": (34.6, -1.8, 8.9),
        "RightKnee": (-60.6, 0, 0),
        "RightAnkle": (35.2, 0, -11.1),
    },
    "reach_sword": {
        "Waist": (-8, -14, 0),
        "Neck": (-5, -14, 0),
        "LeftShoulder": (-11.5, -3.7, 346),
        "LeftElbow": (26.8, 0, 0),
        "RightShoulder": (-265.5, -28, -3.9),
        "RightElbow": (5.5, 0, 0),
        "RightWrist": (-1, 0, 0.1),
        "LeftHip": (-17.4, 0.5, -3.5),
        "LeftAnkle": (17.4, 0, 3.7),
        "RightHip": (21.3, -1.1, 2.2),
        "RightKnee": (-10, 0, 0),
        "RightAnkle": (-11.3, 0, -2.2),
    },
    "hold_sword_low": {
        "Neck": (-8, 0, 0),
        "LeftShoulder": (-2.8, -4.3, 351.7),
        "LeftElbow": (11.4, 0, 0),
        "RightShoulder": (-344.7, -3.5, 13.1),
        "RightWrist": (-50.6, 0, 3.8),
        "LeftHip": (-1.2, -0.1, -3.3),
        "LeftKnee": (-0.3, 0, 0),
        "LeftAnkle": (1.5, 0, 3.3),
        "RightHip": (0, 0.1, 3.4),
        "RightKnee": (-0.1, 0, 0),
        "RightAnkle": (0.1, 0, -3.4),
    },
    "hero": {
        "Waist": (6, 8, -3),
        "Neck": (6, -14, 3),
        "LeftShoulder": (-28.3, -105.6, 339.8),
        "LeftElbow": (88, 0, 0),
        "RightShoulder": (-343.1, -27.8, 27.4),
        "RightWrist": (-60.2, 0, 7),
        "LeftHip": (-5.1, 2.2, -12.8),
        "LeftKnee": (-0.1, 0, 0),
        "LeftAnkle": (4.5, 0, 12.8),
        "RightHip": (2.6, -2.8, 13.3),
        "RightKnee": (-2.6, 0, 0),
        "RightAnkle": (-0.6, 0, -13.2),
    },
}
ROOT_LOC = {
    "mount_crouch": (0.000, -0.428, 0.000),
    "surf_stance": (0.000, -0.286, 0.000),
    "brake_lean": (0.000, -0.582, 0.000),
    "brake_strain": (0.000, -0.803, 0.000),
    "stop_impact": (0.000, -0.362, 0.000),
    "step_off": (0.000, -0.091, 0.000),
    "land_crouch": (0.000, -0.296, 0.000),
    "reach_sword": (0.000, -0.094, 0.000),
    "hero": (0.000, -0.052, 0.000),
}
# </POSES>


# ============================================================================ pose dicts
def full_pose(pose):
    """Name or (partial) pose dict -> full pose dict (all 15 bones + "_loc")."""
    if isinstance(pose, str):
        src, loc = POSES[pose], ROOT_LOC.get(pose, (0.0, 0.0, 0.0))
    else:
        src, loc = pose, pose.get(LOC_KEY, (0.0, 0.0, 0.0))
    out = {b: tuple(float(v) for v in src.get(b, (0.0, 0.0, 0.0))) for b in BONES}
    out[LOC_KEY] = tuple(float(v) for v in loc)
    return out


def blend_pose(a, b, w):
    """Per-angle linear blend of two poses (names or dicts): w = 0 -> a, w = 1 -> b."""
    pa, pb = full_pose(a), full_pose(b)
    return {k: tuple(x + (y - x) * w for x, y in zip(pa[k], pb[k])) for k in pa}


def mirror_pose(pose):
    """Left <-> right mirror image: (x, y, z) -> (x, -y, -z) with Left/Right bones swapped,
    Root location x -> -x. Note: in mirrored sword poses the sword would be in the LEFT hand."""
    p = full_pose(pose)
    out = {}
    for b in BONES:
        src = b.replace("Left", "#").replace("Right", "Left").replace("#", "Right")
        x, y, z = p[src]
        out[b] = (x, -y, -z)
    lx, ly, lz = p[LOC_KEY]
    out[LOC_KEY] = (-lx, ly, lz)
    return out


def scale_pose(pose, k):
    """Every angle and the Root location times k (k = 0 -> rest)."""
    p = full_pose(pose)
    return {key: tuple(v * k for v in val) for key, val in p.items()}


def apply_pose(rig, pose):
    """Set the rig's pose bones (rotation_euler, Root location) without keying. Returns the dict."""
    p = full_pose(pose)
    for b in BONES:
        rig.pose.bones[b].rotation_euler = [math.radians(v) for v in p[b]]
    rig.pose.bones["Root"].location = p[LOC_KEY]
    return p


def _channelbag(rig):
    from bpy_extras import anim_utils
    ad = rig.animation_data
    if ad is None or ad.action is None:
        return None
    return anim_utils.action_get_channelbag_for_slot(ad.action, ad.action_slot)


def key_pose(rig, frame, name, blend=None, weight=1.0, jitter=0.0, seed=0, interpolation="BEZIER"):
    """Key all 15 bones (rotation_euler; plus location for Root) at `frame`.

    name:    pose name or pose dict.
    blend, weight: keys blend_pose(blend, name, weight), i.e. `weight` is how much of `name`
             you get and the rest (1 - weight) comes from `blend` (a pose name/dict), or from
             the rest pose (all zero) when blend is None. Defaults: exactly `name`.
             e.g. key_pose(rig, f, "fall_spread", blend="fall_tumble_a", weight=0.7)
    jitter:  +-degrees of noise on every angle (half on Root/Waist), deterministic for
             (seed, frame) -- for handheld-ish wobble keys.
    interpolation: "BEZIER" | "LINEAR" | "CONSTANT" for the inserted keys.
    Returns the pose dict that was keyed."""
    p = blend_pose(blend if blend is not None else {}, name, weight)
    if jitter:
        rng = random.Random("%s:%s" % (seed, frame))
        for b in BONES:
            k = 0.5 if b in ("Root", "Waist") else 1.0
            p[b] = tuple(v + rng.uniform(-jitter, jitter) * k for v in p[b])
    apply_pose(rig, p)
    for b in BONES:
        rig.pose.bones[b].keyframe_insert("rotation_euler", frame=frame, group=b)
    rig.pose.bones["Root"].keyframe_insert("location", frame=frame, group="Root")
    cb = _channelbag(rig)
    if cb is not None:
        for fc in cb.fcurves:
            if fc.data_path.startswith("pose.bones["):
                for kp in fc.keyframe_points:
                    if abs(kp.co.x - frame) < 1e-4:
                        kp.interpolation = interpolation
    return p


# ============================================================================ geometry helpers
def _basis(cols):
    x, y, z = cols
    return Matrix(((x[0], y[0], z[0]), (x[1], y[1], z[1]), (x[2], y[2], z[2])))


def _swing(u):
    """Minimal rotation taking the rest limb direction (0,-1,0) to u."""
    return Vector((0.0, -1.0, 0.0)).rotation_difference(Vector(u).normalized()).to_matrix()


def _perp(v, u, hint):
    """Bend direction: the part of v across u; the hint takes over as the limb straightens."""
    p = v - u * v.dot(u)
    h = hint - u * hint.dot(u)
    h = h.normalized() if h.length > 1e-6 else Vector((0.0, 0.0, 0.0))
    return (p + h * 0.2).normalized()


def aim_arm(upper_dir, fore_dir, bend_hint=None):
    """Shoulder Euler + elbow Euler (degrees) pointing the upper arm along upper_dir and the
    forearm along fore_dir (torso = Waist frame, Roblox axes). The elbow is a hinge about the
    upper arm's X; bend_hint (default: the twist-free bend direction) picks the bend plane when
    the arm is (nearly) straight. Works for both sides."""
    u = Vector(upper_dir).normalized()
    f = Vector(fore_dir).normalized()
    hint = Vector(bend_hint) if bend_hint is not None else _swing(u) @ Vector((0.0, 0.0, -1.0))
    n = _perp(f, u, hint)                        # where the forearm bends to = arm's local -Z
    R = _basis((u.cross(n), -u, -n))             # local X, Y (= -arm), Z (= -bend)
    e = R.to_euler("XYZ", Euler((0.0, 0.0, 0.0)))
    return tuple(math.degrees(a) for a in e), (math.degrees(u.angle(f)), 0.0, 0.0)


def aim_leg(thigh_dir, shin_dir, bend_hint=None):
    """Hip Euler + knee Euler (degrees) for thigh/shin directions in the pelvis (Root) frame.
    The knee bends the shin toward the leg's local +Z (back), so the knee angle is negative."""
    u = Vector(thigh_dir).normalized()
    f = Vector(shin_dir).normalized()
    hint = Vector(bend_hint) if bend_hint is not None else _swing(u) @ Vector((0.0, 0.0, 1.0))
    n = _perp(f, u, hint)                        # where the shin bends to = leg's local +Z
    R = _basis((-u.cross(n), -u, n))
    e = R.to_euler("XYZ", Euler((0.0, 0.0, 0.0)))
    return tuple(math.degrees(a) for a in e), (-math.degrees(u.angle(f)), 0.0, 0.0)


def hand_grip(frames, side):
    """Grip frame (sword asset frame, Roblox character space) of a hand, from rig.fk() frames."""
    b = _rig.HAND_BONE[side]
    hand = frames[b] @ Matrix.Translation(Vector(_rig.PARTS[side + "Hand"][1]) - _rig.PIVOT[b])
    return hand @ Matrix.Translation((0.0, -0.15, 0.0)) @ Matrix.Rotation(-math.pi / 2, 4, "X")


def _swing_refs(u):
    """Twist-free ways to reach direction u: the minimal swing, and swings through the front /
    the back (Rz(c)*Rx(a)); overhead/behind limbs are ambiguous (Codman), so all count."""
    u = Vector(u).normalized()
    refs = [_swing(u)]
    a = math.asin(max(-1.0, min(1.0, -u.z)))
    for aa in (a, math.pi - a):
        ca = math.cos(aa)
        if abs(ca) < 1e-6:
            continue
        c = math.atan2(u.x / ca, -u.y / ca)
        refs.append(Matrix.Rotation(c, 3, "Z") @ Matrix.Rotation(aa, 3, "X"))
    return refs


def limb_twist(euler_deg):
    """Twist (degrees) of a shoulder/hip rotation about the limb's own axis, relative to the
    closest twist-free swing. Natural range roughly +-100 (arms), +-50 (legs)."""
    R = _rig.euler_rbx(euler_deg).to_3x3()
    u = R @ Vector((0.0, -1.0, 0.0))
    best = None
    for ref in _swing_refs(u):
        q = (ref.transposed() @ R).to_quaternion()
        t = (math.degrees(2.0 * math.atan2(-q.y, q.w)) + 180.0) % 360.0 - 180.0
        if best is None or abs(t) < abs(best):
            best = t
    return best


def _obb_pen(A, sa, B, sb):
    """Penetration depth of two oriented boxes (4x4 frame at the centre, full sizes); <= 0 apart."""
    ax = [A.col[i].to_3d().normalized() for i in range(3)]
    bx = [B.col[i].to_3d().normalized() for i in range(3)]
    ha = [s / 2 for s in sa]
    hb = [s / 2 for s in sb]
    d = B.translation - A.translation
    best = 1e9
    for L in ax + bx + [a.cross(b) for a in ax for b in bx]:
        if L.length < 1e-6:
            continue
        L = L.normalized()
        ra = sum(ha[i] * abs(ax[i].dot(L)) for i in range(3))
        rb = sum(hb[i] * abs(bx[i].dot(L)) for i in range(3))
        best = min(best, ra + rb - abs(d.dot(L)))
        if best <= 0:
            return best
    return best


SWORD_BOX = {  # placeholder sword pieces in the sword's asset frame (Roblox axes, blade +Y)
    "blade": ((0.3, 3.9, 0.1), (0.0, 0.62 + 1.95, 0.0)),
    "guard": ((1.25, 0.2, 0.3), (0.0, 0.52, 0.0)),
    "grip": ((0.22, 1.0, 0.22), (0.0, -0.08, 0.0)),
}
_ADJACENT = {frozenset((_rig.PART_OF[b], _rig.PART_OF[p])) for b, p, _, _ in _rig.JOINTS if p} | {
    frozenset(("LowerTorso", "LeftUpperLeg")), frozenset(("LowerTorso", "RightUpperLeg")),
    frozenset(("UpperTorso", "LeftUpperArm")), frozenset(("UpperTorso", "RightUpperArm")),
    frozenset(("UpperTorso", "LeftUpperLeg")), frozenset(("UpperTorso", "RightUpperLeg"))}


def analyse(pose, sword=None):
    """Numbers for one pose (FK in Roblox space): sole heights, part penetrations (non-adjacent
    parts deeper than 0.08; the blade too when sword is "held"/"float"), two-hand grip error,
    blade direction, joint sanity (hinges, limb twists)."""
    p = full_pose(pose)
    frames, parts = _rig.fk(p, p[LOC_KEY])
    out = {"soles": {}}
    for side in ("Left", "Right"):
        F = parts[side + "Foot"]
        sx, sy, sz = _rig.PARTS[side + "Foot"][0]
        ys = [(F @ Vector((x * sx / 2, -sy / 2, z * sz / 2))).y for x in (-1, 1) for z in (-1, 1)]
        out["soles"][side] = (min(ys), max(ys))
    pens = []
    names = list(parts)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            if frozenset((a, b)) in _ADJACENT:
                continue
            pen = _obb_pen(parts[a], _rig.PARTS[a][0], parts[b], _rig.PARTS[b][0])
            if pen > 0.08:
                pens.append((round(pen, 2), a, b))
    grip = hand_grip(frames, "Right")
    blade = grip.col[1].to_3d()
    out["two_hand_err"] = (hand_grip(frames, "Left").translation - (grip.translation - blade * LEFT_GRIP_SPACING)).length
    out["blade_dir"] = tuple(round(v, 2) for v in blade)
    out["grip_pos"] = tuple(round(v, 2) for v in grip.translation)
    if sword in ("held", "float"):
        size, centre = SWORD_BOX["blade"]
        M = grip @ Matrix.Translation(centre)
        for part in names:
            if not part.endswith("Hand"):
                pen = _obb_pen(M, size, parts[part], _rig.PARTS[part][0])
                if pen > 0.05:
                    pens.append((round(pen, 2), "Sword", part))
    out["penetrations"] = sorted(pens, reverse=True)
    bad = []
    for side in ("Left", "Right"):
        ex, kx = p[side + "Elbow"], p[side + "Knee"]
        if not (0.0 <= ex[0] <= 150.0) or abs(ex[1]) > 1e-6 or abs(ex[2]) > 1e-6:
            bad.append("%sElbow %s" % (side, ex))
        if not (-150.0 <= kx[0] <= 0.0) or abs(kx[1]) > 1e-6 or abs(kx[2]) > 1e-6:
            bad.append("%sKnee %s" % (side, kx))
        out[side + "ArmTwist"] = ts = limb_twist(p[side + "Shoulder"])
        out[side + "LegTwist"] = th = limb_twist(p[side + "Hip"])
        if abs(ts) > 110:
            bad.append("%sShoulder twist %.0f" % (side, ts))
        if abs(th) > 55:
            bad.append("%sHip twist %.0f" % (side, th))
    out["bad_joints"] = bad
    return out


def check(verbose=True):
    """analyse() every pose; prints a line per pose. Returns (results, ok) where ok means: all
    required poses exist, hinges bend the right way, twists are anatomical, grounded soles sit
    at -3 (+-0.03), two-handed grips within 0.3 and no deep (> 0.3) body penetrations."""
    res, ok = {}, True
    missing = [n for n in REQUIRED if n not in POSES]
    if missing:
        ok = False
        print("MISSING poses:", missing)
    for name in POSES:
        a = analyse(name, SWORD.get(name))
        res[name] = a
        problems = []
        s = a["soles"]
        msg = "soles L %.2f..%.2f R %.2f..%.2f" % (*s["Left"], *s["Right"])
        msg += " | twist arms L%.0f R%.0f legs L%.0f R%.0f" % (
            a["LeftArmTwist"], a["RightArmTwist"], a["LeftLegTwist"], a["RightLegTwist"])
        if SWORD.get(name) in ("held", "float"):
            msg += " | blade %s" % (a["blade_dir"],)
        if name in TWO_HANDED:
            msg += " | two-hand err %.2f" % a["two_hand_err"]
            if a["two_hand_err"] > 0.3:
                problems.append("left hand off the grip")
        if name in GROUNDED and not any(all(abs(v - _rig.FEET_Y) < 0.03 for v in s[sd]) for sd in s):
            problems.append("no sole flat at %.1f" % _rig.FEET_Y)
        problems += a["bad_joints"]
        if a["penetrations"]:
            msg += " | contact " + ", ".join("%s/%s %.2f" % (x, y, p) for p, x, y in a["penetrations"][:3])
            deep = [(x, y) for d, x, y in a["penetrations"] if d > 0.3 and not (x.endswith("Hand") and y.endswith("Hand"))]
            if deep:
                problems.append("deep penetration %s" % deep)
        if problems:
            ok = False
            msg += " | PROBLEM " + "; ".join(problems)
        if verbose:
            print("%-16s %s" % (name, msg))
    if verbose:
        print("poses check:", "OK" if ok else "PROBLEMS")
    return res, ok


REQUIRED = ("stand", "fall_spread", "fall_tumble_a", "fall_tumble_b", "look_around", "look_up_reach",
            "reach_right", "flail_a", "flail_b", "grab_blade", "struggle_a", "struggle_b",
            "resonance_brace", "resonance_burst", "sword_ready", "swing_wind", "swing_follow",
            "mount_crouch", "surf_stance", "brake_lean", "brake_strain", "stop_impact", "step_off",
            "land_crouch", "reach_sword", "hold_sword_low", "hero")


# ============================================================================ sword placement
def board_world_matrix(rig, mode="board"):
    """World matrix of the Sword object lying flat under the feet (SWORD modes "board" /
    "board_left"): blade along the line between the feet (character X), tip toward the left
    foot, flat side up, top surface at the soles (y = -3), grip toward the right foot."""
    parts = _rig.part_objects(rig)
    a = parts["LeftFoot"].matrix_world.translation
    b = parts["RightFoot"].matrix_world.translation
    R3 = rig.matrix_world.to_3x3()
    if mode == "board_left":   # only the left foot is on it
        b = a + R3 @ Vector((1.6, 0, 0))
        a = a - R3 @ Vector((0.6, 0, 0))
    up = (R3 @ Vector((0, 0, 1))).normalized()
    along = a - b
    along = (along - up * along.dot(up)).normalized()
    M = _basis((up.cross(along), up, along)).to_4x4()
    mid = (a + b) / 2
    sole = rig.matrix_world @ Vector((0, 0, _rig.FEET_Y))
    M.translation = mid - up * (mid - sole).dot(up) - up * 0.05 - along * 1.2
    return M


def sword_world_matrix(rig, mode):
    """Contact-sheet placement of the sword for a SWORD mode (None = not shown)."""
    if mode in ("held", "float"):
        return _rig.grip_world_matrix(rig)
    if mode in ("board", "board_left"):
        return board_world_matrix(rig, mode)
    if mode == "above":
        M = Matrix.Translation(rig.matrix_world @ Vector((0.6, 0.6, 6.0))) @ Matrix.Rotation(math.radians(160), 4, "X")
        return M @ Matrix.Rotation(math.radians(25), 4, "Y")
    return None


# ============================================================================ contact sheet
SHEET_VIEW = (0.62, 1.0, 0.36)   # Blender direction from the character to the camera: 3/4 front-right


def _mat(name, rgb, emit=0.0, rough=0.5, metal=0.0):
    import bpy
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if m.node_tree is None:      # Blender < 5 needs use_nodes; 5.x always has a node tree
        m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    lin = tuple((c / 255) ** 2.2 for c in rgb)
    bsdf.inputs["Base Color"].default_value = (*lin, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*lin, 1)
        bsdf.inputs["Emission Strength"].default_value = emit
    return m


def placeholder_sword(collection, name="SwordPlaceholder"):
    """Sword stand-in in the asset convention: grip centre at the origin, blade along +Z,
    edges along X (blade 0.3 x 0.1 x 3.9 from the guard, guard bar, grip, pommel)."""
    import bpy
    import bmesh
    import kit
    bm = bmesh.new()
    mats = [_mat("Sheet_Blade", (215, 222, 235), rough=0.25, metal=0.6),
            _mat("Sheet_Guard", (214, 172, 74), rough=0.35, metal=0.8),
            _mat("Sheet_Grip", (70, 44, 32)), _mat("Sheet_Crystal", (120, 200, 255), emit=1.5)]

    def add(mi, size, centre, bevel=0.0):
        before = set(bm.faces)
        kit.box(bm, Matrix(), size, centre, bevel=bevel)
        for f in set(bm.faces) - before:
            f.material_index = mi

    add(0, (0.3, 0.1, 3.5), (0, 0, 0.62 + 1.75), 0.02)
    tip = [bm.verts.new(v) for v in ((-0.15, -0.05, 4.12), (0.15, -0.05, 4.12), (0.15, 0.05, 4.12),
                                     (-0.15, 0.05, 4.12), (0, 0, 4.52))]
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
        bm.faces.new((tip[a], tip[b], tip[4])).material_index = 0
    add(1, (1.25, 0.3, 0.2), (0, 0, 0.52), 0.04)
    add(3, (0.16, 0.12, 2.6), (0, 0, 2.0))
    add(2, (0.22, 0.22, 1.0), (0, 0, -0.08), 0.03)
    add(1, (0.34, 0.34, 0.22), (0, 0, -0.66), 0.06)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    for m in mats:
        me.materials.append(m)
    obj = bpy.data.objects.new(name, me)
    collection.objects.link(obj)
    return obj


def render_sheet(out_path, names=None, tile=260, cols=6, samples=12, threads=2, view=SHEET_VIEW):
    """Contact sheet: one labelled tile per pose (orthographic 3/4 view, body as in BODY,
    placeholder sword per SWORD, ground disc for GROUNDED). Resets the Blender session.
    Tiles are kept in <out dir>/tiles."""
    import bpy
    import bmesh
    import numpy as np
    names = list(names or POSES)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    col = bpy.data.collections.new("Sheet")
    scene.collection.children.link(col)
    rig = _rig.build_rig(col)
    sword = placeholder_sword(col)
    bm = bmesh.new()
    bmesh.ops.create_circle(bm, cap_ends=True, radius=3.2, segments=40)
    me = bpy.data.meshes.new("SheetGround")
    bm.to_mesh(me)
    bm.free()
    ground = bpy.data.objects.new("SheetGround", me)
    me.materials.append(_mat("Sheet_Ground", (150, 156, 150), rough=0.9))
    col.objects.link(ground)

    scene.world = bpy.data.worlds.new("SheetWorld")
    if scene.world.node_tree is None:
        scene.world.use_nodes = True
    bg = scene.world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.62, 0.66, 0.72, 1)
    bg.inputs["Strength"].default_value = 0.8
    sun = bpy.data.objects.new("SheetSun", bpy.data.lights.new("SheetSun", "SUN"))
    sun.data.energy = 3.2
    sun.data.angle = math.radians(8)
    sun.rotation_euler = (math.radians(40), math.radians(-10), math.radians(150))
    col.objects.link(sun)
    cam = bpy.data.objects.new("SheetCam", bpy.data.cameras.new("SheetCam"))
    cam.data.type = "ORTHO"
    cam.data.clip_start = 0.1
    cam.data.clip_end = 200
    col.objects.link(cam)
    scene.camera = cam
    font = bpy.data.curves.new("SheetLabel", "FONT")
    label = bpy.data.objects.new("SheetLabel", font)
    font.materials.append(_mat("Sheet_Text", (10, 10, 14), rough=1.0))
    col.objects.link(label)
    label.visible_shadow = False

    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_denoising = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x = scene.render.resolution_y = tile
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = "Standard"
    scene.render.image_settings.file_format = "PNG"

    d = Vector(view).normalized()
    rot = (-d).to_track_quat("-Z", "Y")
    right = rot @ Vector((1, 0, 0))
    upv = rot @ Vector((0, 1, 0))
    tmp = os.path.join(os.path.dirname(os.path.abspath(out_path)), "tiles")
    os.makedirs(tmp, exist_ok=True)
    files = []
    view_layer = bpy.context.view_layer
    for i, name in enumerate(names):
        _rig.reset_pose(rig)
        apply_pose(rig, name)
        rig.rotation_euler = [math.radians(v) for v in BODY.get(name, ((0, 0, 0), ""))[0]]
        rig.location = (0, 0, 0)
        view_layer.update()
        M = sword_world_matrix(rig, SWORD.get(name))
        sword.hide_render = M is None
        if M is not None:
            sword.matrix_world = M
        ground.hide_render = name not in GROUNDED
        ground.matrix_world = rig.matrix_world @ Matrix.Translation((0, 0, _rig.FEET_Y - 0.01))
        view_layer.update()
        pts = []
        for o in list(_rig.part_objects(rig).values()) + ([sword] if M is not None else []):
            mw = o.matrix_world
            pts += [mw @ v.co for v in o.data.vertices]
        xs = [p.dot(right) for p in pts]
        ys = [p.dot(upv) for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        scale = max(max(xs) - min(xs), (max(ys) - min(ys)) * 1.12, 7.0) * 1.12
        cam.data.ortho_scale = scale
        cam.location = right * cx + upv * (cy + scale * 0.03) + d * 60
        cam.rotation_euler = rot.to_euler()
        font.body = name
        font.size = scale * 0.075
        label.rotation_euler = rot.to_euler()
        label.location = cam.location - d * 5 + right * (-scale * 0.47) + upv * (scale * 0.41)
        scene.render.filepath = os.path.join(tmp, "%02d_%s.png" % (i, name))
        bpy.ops.render.render(write_still=True)
        files.append(scene.render.filepath)

    rows = (len(files) + cols - 1) // cols
    sheet = np.ones((rows * tile, cols * tile, 4), dtype=np.float32)
    sheet[..., :3] = 0.12
    for i, f in enumerate(files):
        img = bpy.data.images.load(f)
        px = np.empty(tile * tile * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        r, c = i // cols, i % cols
        y0 = (rows - 1 - r) * tile          # Blender images are stored bottom-up
        sheet[y0:y0 + tile, c * tile:(c + 1) * tile] = px.reshape(tile, tile, 4)
        sheet[y0:y0 + tile, c * tile, :3] = 0.12
        sheet[y0, c * tile:(c + 1) * tile, :3] = 0.12
        bpy.data.images.remove(img)
    out = bpy.data.images.new("PoseSheet", cols * tile, rows * tile, alpha=False)
    out.pixels.foreach_set(sheet.ravel())
    out.filepath_raw = out_path
    out.file_format = "PNG"
    out.save()
    print("sheet", out_path, len(files), "poses")
    return out_path


# ============================================================================ authoring (dev tool)
_HINGE = {"Elbow": (0.0, 150.0), "Knee": (-150.0, 0.0)}
_SOFT = {"Wrist": ((-75, 75), None, (-40, 40)), "Ankle": ((-60, 35), (-25, 25), (-25, 25)),
         "Hip": (None, (-30, 30), None)}
_BODY_PARTS = ("UpperTorso", "LowerTorso", "Head", "LeftUpperLeg", "RightUpperLeg")


def _limit_pen(p):
    pen = 0.0
    for b in BONES:
        for key, lims in _SOFT.items():
            if b.endswith(key):
                for ax, lim in enumerate(lims):
                    if lim:
                        pen += max(0.0, lim[0] - p[b][ax], p[b][ax] - lim[1]) ** 2
    return pen * 0.02


def _get(p, var):
    return p[var[0]][var[1]]


def _set(p, var, val):
    b, ax = var
    for key, (lo, hi) in _HINGE.items():
        if ax == 0 and b.endswith(key):
            val = min(max(val, lo), hi)
    t = list(p[b])
    t[ax] = val
    p[b] = tuple(t)


def _solve(p, vars_, cost, step=12.0, min_step=0.01):
    """Hooke-Jeeves pattern search over pose variables (degrees; Root location in studs/30)."""
    f = cost(p)
    x = [_get(p, v) for v in vars_]
    while step > min_step:
        improved = False
        for i, v in enumerate(vars_):
            s = step / 30.0 if v[0] == LOC_KEY else step
            for d in (s, -s):
                _set(p, v, x[i] + d)
                fn = cost(p)
                if fn < f - 1e-12:
                    x[i] = _get(p, v)
                    f = fn
                    improved = True
                    break
                _set(p, v, x[i])
        if not improved:
            step *= 0.5
    return f


def _fk(p):
    return _rig.fk(p, p[LOC_KEY])


def _reg(p, ref, vars_, k):
    return k * sum((_get(p, v) - _get(ref, v)) ** 2 for v in vars_ if v[0] != LOC_KEY)


def _arm_pen(parts, sides, grip=None):
    """Squared penetrations of the arms (and the blade) into the body / the other arm."""
    c = 0.0
    arms = {s: (s + "UpperArm", s + "LowerArm", s + "Hand") for s in ("Left", "Right")}
    for side in sides:
        other = "Right" if side == "Left" else "Left"
        for a in arms[side]:
            for b in _BODY_PARTS:
                if not (a.endswith("UpperArm") and b == "UpperTorso"):
                    c += max(0.0, _obb_pen(parts[a], _rig.PARTS[a][0], parts[b], _rig.PARTS[b][0]) - 0.04) ** 2
            for b in arms[other]:
                if not (a.endswith("Hand") and b.endswith("Hand")):
                    c += 0.5 * max(0.0, _obb_pen(parts[a], _rig.PARTS[a][0], parts[b], _rig.PARTS[b][0]) - 0.06) ** 2
    if grip is not None:
        size, centre = SWORD_BOX["blade"]
        Mb = grip @ Matrix.Translation(centre)
        for b in _BODY_PARTS + ("LeftUpperArm", "RightUpperArm"):
            c += max(0.0, _obb_pen(Mb, size, parts[b], _rig.PARTS[b][0]) - 0.02) ** 2
    return c


def _arm_vars(side, wrist=True):
    v = [(side + "Shoulder", 0), (side + "Shoulder", 1), (side + "Shoulder", 2), (side + "Elbow", 0)]
    return v + ([(side + "Wrist", 0), (side + "Wrist", 2)] if wrist else [])


def build_pose(spec):
    """Solve one POSE_SPECS entry into a full pose dict."""
    p = full_pose({})
    for key, bone in (("root", "Root"), ("waist", "Waist"), ("neck", "Neck"), ("rwrist", "RightWrist"),
                      ("lwrist", "LeftWrist"), ("rankle", "RightAnkle"), ("lankle", "LeftAnkle")):
        if key in spec:
            p[bone] = tuple(float(v) for v in spec[key])
    for key, side in (("rarm", "Right"), ("larm", "Left")):
        if key in spec:
            p[side + "Shoulder"], p[side + "Elbow"] = aim_arm(*spec[key])
    for key, side in (("rleg", "Right"), ("lleg", "Left")):
        if key in spec:
            p[side + "Hip"], p[side + "Knee"] = aim_leg(*spec[key])
    p[LOC_KEY] = tuple(float(v) for v in spec.get("loc", (0.0, 0.0, 0.0)))

    feet, free_feet = spec.get("feet") or {}, spec.get("foot_target") or {}
    if feet or free_feet:   # soles flat at -3 (planted feet), free foot targets
        ref = dict(p)
        vars_ = [(LOC_KEY, 1)] if feet else []
        for side in list(feet) + list(free_feet):
            vars_ += [(side + "Hip", 0), (side + "Hip", 1), (side + "Hip", 2), (side + "Knee", 0),
                      (side + "Ankle", 0), (side + "Ankle", 2)]

        def cost(q):
            _, parts = _fk(q)
            c = _limit_pen(q) + _reg(q, ref, vars_, 2e-4)
            for side, (tx, tz) in feet.items():
                F = parts[side + "Foot"]
                sx, sy, sz = _rig.PARTS[side + "Foot"][0]
                c += 400 * sum(((F @ Vector((x * sx / 2, -sy / 2, z * sz / 2))).y - _rig.FEET_Y) ** 2
                              for x in (-1, 1) for z in (-1, 1))
                c += 8 * ((F.translation.x - tx) ** 2 + (F.translation.z - tz) ** 2)
                c += 2 * F.col[2].to_3d().x ** 2           # toes keep pointing forward
            for side, (tgt, pitch) in free_feet.items():
                F = parts[side + "Foot"]
                c += 30 * (F.translation - Vector(tgt)).length_squared
                want = Vector((0, math.sin(math.radians(pitch)), -math.cos(math.radians(pitch))))
                c += 3 * (1 + F.col[2].to_3d().dot(want))
            return c
        _solve(p, vars_, cost)

    if "blade" in spec:     # right-hand blade direction, hand stays roughly where it is
        want = Vector(spec["blade"]).normalized()
        ref = dict(p)
        hand0 = hand_grip(_fk(p)[0], "Right").translation.copy()
        vars_ = _arm_vars("Right")

        def cost(q):
            g = hand_grip(_fk(q)[0], "Right")
            c = 40 * (1 - g.col[1].to_3d().dot(want)) + 6 * (g.translation - hand0).length_squared
            return c + _limit_pen(q) + _reg(q, ref, vars_, 1e-4) + 4e-4 * (q["RightWrist"][0] ** 2 + q["RightWrist"][2] ** 2)
        _solve(p, vars_, cost)

    for side, tgt in (spec.get("hand_target") or {}).items():
        ref = dict(p)
        vars_ = _arm_vars(side, wrist=False)

        def cost(q, side=side, tgt=tgt):
            _, parts = _fk(q)
            c = 30 * (parts[side + "Hand"].translation - Vector(tgt)).length_squared
            return c + _limit_pen(q) + _reg(q, ref, vars_, 1e-4)
        _solve(p, vars_, cost)

    for side, (tx, tz) in (spec.get("hand_down") or {}).items():
        ref = dict(p)
        vars_ = _arm_vars(side)

        def cost(q, side=side, tx=tx, tz=tz):
            _, parts = _fk(q)
            H = parts[side + "Hand"]
            low = H @ Vector((0, -0.2, 0))
            c = 40 * (low.y - _rig.FEET_Y - 0.02) ** 2 + 10 * ((low.x - tx) ** 2 + (low.z - tz) ** 2)
            c += 2 * (1 - H.col[1].to_3d().y)
            return c + _limit_pen(q) + _reg(q, ref, vars_, 1e-4) + 25 * _arm_pen(parts, (side,))
        _solve(p, vars_, cost)

    if "grip" in spec:      # right-hand grip pose, then the left hand below it
        tpos, want = Vector(spec["grip"][0]), Vector(spec["grip"][1]).normalized()
        ref = dict(p)
        rv = _arm_vars("Right")

        def cost_r(q):
            fr, parts = _fk(q)
            g = hand_grip(fr, "Right")
            c = 40 * (g.translation - tpos).length_squared + 30 * (1 - g.col[1].to_3d().dot(want))
            c += _limit_pen(q) + _reg(q, ref, rv, 3e-5) + 2e-4 * (q["RightWrist"][0] ** 2 + q["RightWrist"][2] ** 2)
            return c + 25 * _arm_pen(parts, ("Right",), g)
        for _ in range(3):
            _solve(p, rv, cost_r, step=24)
    if spec.get("two_hand"):
        ref = dict(p)
        lv = _arm_vars("Left")

        def cost_l(q):
            fr, parts = _fk(q)
            g = hand_grip(fr, "Right")
            blade = g.col[1].to_3d()
            lg = hand_grip(fr, "Left")
            c = 40 * (lg.translation - (g.translation - blade * LEFT_GRIP_SPACING)).length_squared
            c += 4 * (1 - lg.col[1].to_3d().dot(blade))
            c += _limit_pen(q) + _reg(q, ref, lv, 3e-5) + 2e-4 * (q["LeftWrist"][0] ** 2 + q["LeftWrist"][2] ** 2)
            return c + 25 * _arm_pen(parts, ("Left",))
        for _ in range(3):
            _solve(p, lv, cost_l, step=24)
    return p


def _euler_detour(a, b):
    """Max angle (deg) between per-angle linear Euler interpolation a -> b and the slerp."""
    qa, qb = _rig.euler_rbx(a).to_quaternion(), _rig.euler_rbx(b).to_quaternion()
    worst = 0.0
    for t in (0.25, 0.5, 0.75):
        e = tuple(x + (y - x) * t for x, y in zip(a, b))
        d = _rig.euler_rbx(e).to_quaternion().rotation_difference(qa.slerp(qb, t))
        worst = max(worst, math.degrees(min(d.angle, 2 * math.pi - d.angle)))
    return worst


def _euler_toward(e, ref):
    """The Euler triple (degrees) for the same rotation as e that interpolates best from ref:
    both XYZ solutions, each angle wrapped to within 180 of ref; least detour, then nearest."""
    x, y, z = e
    best = None
    for cand in ((x, y, z), (x + 180.0, 180.0 - y, z + 180.0)):
        c = tuple(v - 360.0 * round((v - r) / 360.0) for v, r in zip(cand, ref))
        key = (round(_euler_detour(ref, c), 1), sum((v - r) ** 2 for v, r in zip(c, ref)))
        if best is None or key < best[0]:
            best = (key, c)
    return best[1]


def author(path=__file__):
    """Solve every POSE_SPECS entry and rewrite the generated POSES / ROOT_LOC block of `path`."""
    def fmt(v):
        r = round(v, 1)
        return ("%d" % r) if r == int(r) else ("%.1f" % r)

    lines, locs = ["POSES = {"], []
    prev = None
    for name, spec in POSE_SPECS.items():
        p = build_pose(spec)
        if prev is not None:
            # same rotations, but each Euler triple chosen so that keyed Euler interpolation
            # from the previous pose (story order) stays close to the shortest rotation
            for b in BONES:
                p[b] = _euler_toward(p[b], prev[b])
        prev = p
        lines.append('    "%s": {' % name)
        for b in BONES:
            if any(abs(round(v, 1)) >= 0.05 for v in p[b]):
                lines.append('        "%s": (%s),' % (b, ", ".join(fmt(v) for v in p[b])))
        lines.append("    },")
        if any(abs(v) >= 0.01 for v in p[LOC_KEY]):
            locs.append('    "%s": (%s),' % (name, ", ".join("%.3f" % v for v in p[LOC_KEY])))
    lines += ["}", "ROOT_LOC = {"] + locs + ["}"]
    src = open(path).read()
    src = re.sub(r"# <POSES>\n.*?# </POSES>\n", lambda m: "# <POSES>\n" + "\n".join(lines) + "\n# </POSES>\n",
                 src, count=1, flags=re.S)
    with open(path, "w") as f:
        f.write(src)
    print("authored", len(POSE_SPECS), "poses ->", path)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]

    def opt(k, default):
        return argv[argv.index(k) + 1] if k in argv else default

    if "--author" in argv:
        author()
        sys.exit(0)        # re-run (without --author) to check/render the new numbers
    ok = True
    if "--check" in argv or not argv:
        ok = check()[1]
    if "--sheet" in argv:
        names = opt("--only", None)
        render_sheet(os.path.abspath(opt("--sheet", "sheet.png")), names=names.split(",") if names else None,
                     tile=int(opt("--tile", 260)), cols=int(opt("--cols", 6)),
                     view=tuple(float(v) for v in opt("--view", "0.62,1,0.36").split(",")))
    sys.exit(0 if ok else 1)
