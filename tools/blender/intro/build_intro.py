"""
Builds the "Awaken" intro cutscene (docs/intro/DESIGN.md §10): scene -> blend -> IntroData -> previews.

    python tools/blender/intro/build_intro.py [--stills] [--frames A-B] [--mp4 [PATH]] [--out DIR]
                                              [--size 640x360] [--samples 10] [--threads N] [--step N]
                                              [--no-export] [--no-save]

Run with Blender's python (bpy). Steps:
  1. scene.build() into an empty file (every object, keyframe, marker and camera of DESIGN §1-§5)
  2. saves assets/IntroScene.blend                                   (skip with --no-save)
  3. export_intro.export(): src/IntroCutscene/IntroData.luau + tools/tests/intro_parity.luau
                                                                      (skip with --no-export)
  4. previews with render_preview (Cycles CPU, 2D layer of the runtime burned in), into --out
     (default <tmp>/intro_preview):
       --stills        STILL_TIMES (about 30 stills spread over every shot) + <out>/stills/sheet.png
       --frames A-B    Blender frames A..B (inclusive) into <out>/frames
       --mp4 [PATH]    the whole animatic (every frame, or every --step-th frame held) as an MP4
                       (default <out>/intro.mp4); a long render
Verification afterwards: luau tools/tests/intro_parity_test.luau and the mock driver
(python3 tools/bundle.py tools/tests/intro_driver.luau d.luau && luau d.luau).
"""
import argparse
import os
import sys
import tempfile
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
for _p in (_HERE, os.path.dirname(_HERE)):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import bpy  # noqa: E402

ROOT = os.path.abspath(os.path.join(_HERE, "..", "..", ".."))
SCENE_PATH = os.path.join(ROOT, "assets", "IntroScene.blend")
DEFAULT_OUT = os.path.join(tempfile.gettempdir(), "intro_preview")

# one or more stills per shot / beat of the storyboard (DESIGN §1)
STILL_TIMES = [
    0.6, 1.4, 4.0, 7.5, 9.5,                    # S0 ignite, S1 deep space
    11.2, 12.4,                                 # S2 reveal (the swing)
    13.8, 15.6, 16.9, 17.6, 18.3,               # S3 approach, crack, rift, S4 enter
    19.2, 20.6, 21.3, 22.5,                     # W1 exit + morph, W2 notice
    24.2, 25.4, 27.0, 27.7,                     # W2 low angle, W3 struggle + grab
    28.05, 28.15, 29.15,                        # W4 impact frames, blast
    30.3, 31.3,                                 # W5 swing, mount
    32.4, 33.6, 34.9,                           # W6 surf, brake, stop
    35.5, 36.6,                                 # W7 shockwave, forest bending
    38.5, 39.4, 40.6, 42.0,                     # W8 step off, land, grab, hero
]


def _size(s):
    w, h = s.lower().split("x")
    return int(w), int(h)


def _frames(s):
    a, b = s.split("-")
    return list(range(int(a), int(b) + 1))


def main(argv):
    ap = argparse.ArgumentParser(description="Build the intro cutscene scene, export IntroData, render previews")
    ap.add_argument("--stills", action="store_true", help="render STILL_TIMES + a contact sheet")
    ap.add_argument("--frames", default=None, help="render Blender frames A-B")
    ap.add_argument("--mp4", nargs="?", const="", default=None, help="render the whole animatic as an MP4")
    ap.add_argument("--out", default=DEFAULT_OUT)
    ap.add_argument("--size", default="640x360")
    ap.add_argument("--samples", type=int, default=10)
    ap.add_argument("--threads", type=int, default=None)
    ap.add_argument("--step", type=int, default=1, help="--mp4: render every n-th frame (held in between)")
    ap.add_argument("--no-export", action="store_true")
    ap.add_argument("--no-save", action="store_true")
    a = ap.parse_args(argv)

    import scene as S
    import export_intro
    import render_preview as RP

    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    S.build(verbose=True)
    sc = bpy.context.scene
    if not a.no_save:
        bpy.ops.wm.save_as_mainfile(filepath=SCENE_PATH, compress=True)
        print("build_intro: saved %s (%.1f MB)" % (SCENE_PATH, os.path.getsize(SCENE_PATH) / 1e6))
    if not a.no_export:
        rep = export_intro.export(sc, export_intro.DATA_PATH, export_intro.PARITY_PATH, verbose=True)
        print("build_intro: IntroData.luau %.1f KB, %d warnings" % (rep["bytes"] / 1024, len(rep.get("warnings", []))))
        for w in rep.get("warnings", []):
            print("  warning:", w)
    size = _size(a.size)
    if a.stills:
        d = os.path.join(a.out, "stills")
        paths = RP.render(sc, d, times=STILL_TIMES, size=size, samples=a.samples, threads=a.threads)
        print("build_intro: sheet", RP.contact_sheet(paths, os.path.join(d, "sheet.png"), cols=4, width=1600))
    if a.frames:
        d = os.path.join(a.out, "frames")
        RP.render(sc, d, frames=_frames(a.frames), size=size, samples=a.samples, threads=a.threads)
        print("build_intro: frames in", d)
    if a.mp4 is not None:
        mp4 = a.mp4 or os.path.join(a.out, "intro.mp4")
        RP.render(sc, os.path.join(a.out, "mp4"), size=size, samples=a.samples, threads=a.threads, step=a.step, mp4=mp4)
        print("build_intro: animatic", mp4)
    print("build_intro: done in %.1f s" % (time.time() - t0))


if __name__ == "__main__":
    main(sys.argv[1:])
