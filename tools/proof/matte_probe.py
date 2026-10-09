#!/usr/bin/env python3
"""Road map "mattes", phase MT3 (#240; spec §11 MT-3, MT-6) — a matte under
View ▸ Preview Quality, through the app's own preview path; and (issue batch
B90 phase 4, #252, spec §11 MT-8) a routed dissolve and zoom the same way.

    python3 tools/proof/matte_probe.py
    python3 tools/proof/matte_probe.py --mutant coverage-destination-coords

`matte_probe.swift` is built as `main.swift` over every other file in
`app/Sources` through `swift_build.build` (reused when every input is
byte-identical), beside `Blank.mp4` and a `default.metallib` of the tree's
`Compositor.metal`, in `tools/proof/work/matte_probe/`. It renders each
fixture at Full, Half and Quarter as `phase8_chrome.py`'s section 9 does —
`CompositionBuilder.build`, `Playback.previewComposition` (called),
`AVAssetImageGenerator` — and answers each colour class's coverage and
bounding box as FRACTIONS of the frame. **A build failure is a scored
FAILURE (B0), never an exit.** No app is launched and nothing is written
outside the work folder; the probe binary has no bundle id and sets no
default.

The fixtures are 1920×1080, background black, every clip an unstroked
rectangle (a solid colour, so a lit pixel is a placement fact), packages
written by hand at the header's current format version:
- **Q1**: a full-canvas white card on track 10 under an `alpha` matte on
  track 11, an 800×400 window centred at (720, 400): at each quality the
  white class's box is the window, 320…1120 × 200…600 as fractions, and its
  coverage the window's area (phase 8's tolerances: a box edge within 1.5
  destination pixels, coverage within 0.4 % of the frame).
- **Q2**: phase 8's 400×300 white card at the canvas's quarter point with a
  hard red drop shadow (blur 0, 300 px at 315°), under an `alpha` window
  over the card's LEFT half (280…480 × 100…440): at each quality the card
  class is the cut card (280…480 × 120…420) and the red class the CUT
  shape offset by 212.13 px down and right — where Full's is. The shadow's
  silhouette pass is canvas-sized whatever the quality, so a coverage
  sampled in destination pixels there misplaces it at Half and Quarter.
- **Q3** (B90 phase 4): `matte_proof.py` D0's fixture written by hand — red
  then green full cards (0–1 s, 1–2 s) in a nest, shown by a nest clip at
  0–1.5 s and another at 1–2 s whose linear `cross_dissolve` makes the
  overlap — at tick 700000 (p = 1/3): the class "mix" (R within 255/3 ± 8,
  G within 170 ± 8) covers at least 99.5 % of the frame at each quality.
- **Q4** (B90 phase 4): D8's fixture, the same with a `zoom`: at each quality
  the "mix" class's box is the in-box, 1/12 … 11/12 of each axis (z_in =
  5/6), and the class "border" (G within 170 ± 8, R ≤ 8) covers 1 − (5/6)²
  of the frame within 0.4 %. A zoom anchor read in destination pixels
  misplaces the box at Half and Quarter.
- **Q0** (CONTROL): the destinations are 1920×1080, 960×540 and 480×270.

`--mutant coverage-destination-coords` compiles a copy of the shader whose
step 7c samples the coverage at `position / coverage size` (the
destination's) into its own folder beside a copy of the same binary, and
runs every row: Q2 must FAIL at Half and Quarter. Rule R: exit 0 = caught,
1 = survived, 2 = the control could not be performed.
"""

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/matte_probe"
PROBE_SOURCE = ROOT / "tools/proof/matte_probe.swift"
SHADER = ROOT / "app/Resources/Shaders/Compositor.metal"
HEADER = ROOT / "core/include/reelcut_core.h"
SEC = 600_000
W, H = 1920, 1080
BOX_SLOP = 1.5
COVERAGE_SLOP = 0.004
WHITE = [1.0, 1.0, 1.0, 1.0]
RED = [1.0, 0.0, 0.0, 1.0]
MUTANTS = {
    "coverage-destination-coords": (
        "    float matteCover = matte.sample(samp, canvasPixels(\n"
        "        in.position.xy, float2(u.canvasPerDestX, u.canvasPerDestY))\n"
        "        / max(float2(u.canvasWidth, u.canvasHeight), float2(1.0))).r;\n",
        "    float matteCover = matte.sample(samp,\n"
        "        in.position.xy / float2(matte.get_width(), matte.get_height())).r;\n",
        ["Q2"]),
}
CLASSES = [
    {"name": "white", "low": [200, 200, 200], "high": [255, 255, 255]},
    {"name": "shadow", "low": [100, 0, 0], "high": [255, 90, 90]},
]
# Q3 and Q4 (B90 phase 4): the mix of a green out half and a red in half at
# p = 1/3, and the out half alone at 1 − p.
MIX_CLASSES = [
    {"name": "mix", "low": [77, 162, 0], "high": [93, 178, 8]},
    {"name": "border", "low": [0, 162, 0], "high": [8, 178, 8]},
]
GREEN = [0.0, 1.0, 0.0, 1.0]
MIX_TICK = 700_000
IN_BOX = (W / 12, H / 12, 11 * W / 12, 11 * H / 12)
MIX_COVERAGE = 0.995
# Q1's window, Q2's card, window and shadow, in canvas pixels.
Q1_WINDOW = (320, 200, 1120, 600)
CARD = (280, 120, 680, 420)
Q2_WINDOW = (280, 100, 480, 440)
CUT = (280, 120, 480, 420)
OFFSET = 300 * 0.5 ** 0.5
SHADOW = (CUT[0] + OFFSET, CUT[1] + OFFSET, CUT[2] + OFFSET, CUT[3] + OFFSET)
rows = {}


def check(name, good, detail=""):
    key = name.split()[0]
    rows[key] = rows.get(key, True) and bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def video(x=0.0, y=0.0, shadow=None):
    return {
        "x": x, "y": y, "scale": 1.0, "rotation": 0.0, "opacity": 1.0,
        "crop": {"l": 0.0, "t": 0.0, "r": 0.0, "b": 0.0},
        "corner_radius": 0.0, "shadow": shadow,
        "color": {"brightness": 0.0, "contrast": 0.0, "saturation": 0.0, "hue": 0.0},
        "chroma": None, "filters": [], "reflection": None, "spotlight": None,
        "obscure": [], "blend": "normal",
    }


def shape_clip(cid, track, box, fill, shadow=None, start=0, duration=2 * SEC):
    """An unstroked rectangle filling `box` (canvas pixels): `x`/`y` are its
    centre's offset from the canvas centre (spec §5.3)."""
    x0, y0, x1, y1 = box
    return {
        "id": cid, "track": track, "start": start, "duration": duration,
        "source": {"kind": "shape"}, "enabled": {"video": True, "audio": True},
        "speed": 1.0,
        "video": video((x0 + x1) / 2 - W / 2, (y0 + y1) / 2 - H / 2, shadow),
        "audio": None, "text": None,
        "shape": {"kind": "rectangle", "width": float(x1 - x0), "height": float(y1 - y0),
                  "stroke": None, "fill": fill, "arrow_start": False, "arrow_end": False,
                  "radius": 0.0, "from": [0.0, 1.0], "to": [1.0, 0.0], "gradient": None},
        "actions": [], "transition_in": None, "name": None, "label": None,
    }


def nest_clip(cid, track, start, duration, kind=None):
    """A clip showing nest 40 (a `kind` transition in, linear, when given)."""
    return {
        "id": cid, "track": track, "start": start, "duration": duration,
        "source": {"kind": "nest", "project": 40}, "enabled": {"video": True, "audio": True},
        "speed": 1.0, "video": video(), "audio": None, "text": None, "shape": None,
        "actions": [], "name": None, "label": None,
        "transition_in": ({"kind": kind, "curve": "linear", "audio": False}
                          if kind else None),
    }


def split_nest(kind):
    """`matte_proof.py` D0's construction by hand: red then green full cards
    in nest 40, one nest clip at 0–1.5 s and one at 1–2 s dissolving (`kind`)
    over the overlap."""
    nest = {"id": 40, "name": "Nest 40", "width": W, "height": H,
            "tracks": [{"id": 41, "name": "Track 1", "hidden": False, "muted": False,
                        "locked": False, "solo": False}],
            "clips": [shape_clip(42, 41, (0, 0, W, H), RED, duration=SEC),
                      shape_clip(43, 41, (0, 0, W, H), GREEN, start=SEC, duration=SEC)]}
    clips = [nest_clip(50, 10, 0, SEC + SEC // 2), nest_clip(51, 10, SEC, SEC, kind)]
    return clips, [nest]


def package(name, clips, nests=None):
    path = WORK / f"{name}.reelcut"
    path.mkdir(parents=True, exist_ok=True)
    project = {
        "version": format_version(),
        "canvas": {"width": W, "height": H, "fps": [30, 1],
                   "background": [0.0, 0.0, 0.0, 1.0], "fit_new_clips": True,
                   "timecode_frames": True},
        "media": [],
        "tracks": [
            {"id": 10, "name": "Track 1", "hidden": False, "muted": False,
             "locked": False, "solo": False},
            {"id": 11, "name": "Matte", "hidden": False, "muted": False,
             "locked": False, "solo": False, "matte": "alpha"},
        ],
        "clips": clips, "markers": [], "next_id": 100, "nests": nests or [],
    }
    (path / "project.json").write_text(json.dumps(project, indent=2) + "\n")
    return path


def build(mutant):
    """The probe binary beside `Blank.mp4` and a `default.metallib` — of
    the tree's shader, or of the mutant's copy in a folder of its own.
    (binary, "") or (None, why)."""
    WORK.mkdir(parents=True, exist_ok=True)
    built_dir = WORK / "probe"
    built_dir.mkdir(exist_ok=True)
    entry = built_dir / "main.swift"
    if not entry.exists() or entry.read_text() != PROBE_SOURCE.read_text():
        entry.write_text(PROBE_SOURCE.read_text())
    binary = built_dir / "matte_probe"
    try:
        made = swift_build.build(sources=swift_build.app_sources() + [entry], output=binary,
                                 defines=["REELCUT_DEV_TOOLS"], timeout=900)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc rc {error.rc if error.rc is not None else 'before running'}: "
                      f"{(error.diagnostics or ['(no output)'])[:6]}")
    print(f"  probe: {'up to date' if made.reused else f'built in {made.seconds:.0f} s'} — "
          f"{binary}", flush=True)
    run_dir = built_dir
    shader_text = SHADER.read_text()
    if mutant:
        anchor, replacement, _ = MUTANTS[mutant]
        if shader_text.count(anchor) != 1:
            return None, f"the mutant's anchor occurs {shader_text.count(anchor)} times"
        shader_text = shader_text.replace(anchor, replacement)
        run_dir = WORK / "mutant" / mutant
        run_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(binary, run_dir / "matte_probe")
    shader = run_dir / "Compositor.metal"
    shader.write_text(shader_text)
    air, library = run_dir / "Compositor.air", run_dir / "default.metallib"
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o",
                        str(air)], 300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                            str(library)], 300)
    if step["rc"] != 0 or not library.exists():
        return None, f"the shader did not build: {step['stderr'][-400:]}"
    blank = run_dir / "Blank.mp4"
    if not blank.exists():
        shutil.copy2(ROOT / "app/Resources/Blank.mp4", blank)
    return run_dir / "matte_probe", ""


def measurement(answer, tag, quality, klass):
    for row in (answer or {}).get("renders", []):
        if row.get("tag") == tag and row.get("quality") == quality:
            box = (row.get("classes") or {}).get(klass)
            if box is None:
                return None, row.get("error", f"no {klass} measurement")
            return dict(box, width=row.get("width", 1), height=row.get("height", 1)), ""
    return None, f"no {tag} render at quality {quality}"


def placed(answer, tag, quality, klass, box, coverage=None):
    """(ok, detail): a class's box at `box` (canvas pixels) as fractions of
    the frame, within BOX_SLOP destination pixels; and its coverage."""
    got, why = measurement(answer, tag, quality, klass)
    if got is None:
        return False, why
    rect = (box[0] / W, box[1] / H, box[2] / W, box[3] / H)
    if not got["count"]:
        return False, f"{tag} q{quality}: {klass} is EMPTY"
    measured = (got["x0"], got["y0"], got["x1"], got["y1"])
    tol = (BOX_SLOP / got["width"], BOX_SLOP / got["height"]) * 2
    ok = all(abs(a - b) <= t for a, b, t in zip(measured, rect, tol))
    if coverage is not None:
        ok = ok and abs(got["coverage"] - coverage) <= COVERAGE_SLOP
    return ok, (f"{tag} q{quality} {got['width']}x{got['height']}: {klass} "
                f"x {measured[0]:.4f}…{measured[2]:.4f} y {measured[1]:.4f}…{measured[3]:.4f} "
                f"coverage {got['coverage']:.4f}; wanted x {rect[0]:.4f}…{rect[2]:.4f} "
                f"y {rect[1]:.4f}…{rect[3]:.4f}"
                + (f" coverage {coverage:.4f}" if coverage is not None else ""))


def area(box):
    return (box[2] - box[0]) * (box[3] - box[1]) / (W * H)


def covered(answer, tag, quality, klass, want, slop):
    """(ok, detail): a class's coverage within `slop` of `want`, or at least
    `want` when `slop` is None."""
    got, why = measurement(answer, tag, quality, klass)
    if got is None:
        return False, why
    ok = got["coverage"] >= want if slop is None else abs(got["coverage"] - want) <= slop
    return ok, (f"{tag} q{quality} {got['width']}x{got['height']}: {klass} coverage "
                f"{got['coverage']:.4f}; wanted " + (f"≥ {want:.4f}" if slop is None
                                                    else f"{want:.4f} ± {slop}"))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    named = MUTANTS[args.mutant][2] if args.mutant else []
    print(f"mattes MT3 — Preview Quality probe"
          + (f", the {args.mutant} MUTANT ({' '.join(named)} must FAIL)" if args.mutant else ""),
          flush=True)
    binary, why = build(args.mutant)
    check("B0 the probe builds over app/Sources and the shader compiles", binary is not None,
          why or str(binary))
    q1 = package("q1", [shape_clip(20, 10, (0, 0, W, H), WHITE),
                        shape_clip(21, 11, Q1_WINDOW, WHITE)])
    shadow = {"color": RED, "opacity": 1.0, "blur": 0.0, "angle": 315.0, "distance": 300.0}
    q2 = package("q2", [shape_clip(20, 10, CARD, WHITE, shadow),
                        shape_clip(21, 11, Q2_WINDOW, WHITE)])
    q3 = package("q3", *split_nest("cross_dissolve"))
    q4 = package("q4", *split_nest("zoom"))
    answer = None
    if binary is not None:
        request = {"renders": [
            {"tag": "q1", "package": str(q1), "tick": SEC // 2, "classes": CLASSES},
            {"tag": "q2", "package": str(q2), "tick": SEC // 2, "classes": CLASSES},
            {"tag": "q3", "package": str(q3), "tick": MIX_TICK, "classes": MIX_CLASSES},
            {"tag": "q4", "package": str(q4), "tick": MIX_TICK, "classes": MIX_CLASSES},
        ]}
        request_path, out = WORK / "request.json", WORK / "answer.json"
        request_path.write_text(json.dumps(request, indent=2))
        if out.exists():
            out.unlink()
        ran = bounded.run([str(binary), str(request_path), str(out)], 300)
        if out.exists():
            answer = json.loads(out.read_text())
        else:
            print(f"  the probe wrote no answer: rc {ran['rc']} expired {ran['expired']} "
                  f"{(ran['stdout'] + ran['stderr'])[-400:]}", flush=True)
    destinations = sorted({tuple(r.get("destination", [])) for r in
                           (answer or {}).get("renders", [])}, reverse=True)
    check("Q0 CONTROL: the probe answered at 1920x1080, 960x540 and 480x270",
          destinations == [(1920, 1080), (960, 540), (480, 270)], f"{destinations}")
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = placed(answer, "q1", quality, "white", Q1_WINDOW, area(Q1_WINDOW))
        check(f"Q1 {name}: the matte's window is at the same fraction of the frame", ok,
              detail)
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        card_ok, card = placed(answer, "q2", quality, "white", CUT, area(CUT))
        shadow_ok, cast = placed(answer, "q2", quality, "shadow", SHADOW, area(CUT))
        check(f"Q2 {name}: the matted card is the cut shape and its shadow the cut shape "
              "offset, where Full's is", card_ok and shadow_ok, f"{card}\n       {cast}")
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        ok, detail = covered(answer, "q3", quality, "mix", MIX_COVERAGE, None)
        check(f"Q3 {name}: a dissolve between nest clips is the exact mix (R 85 ± 8, G 170 ± 8) "
              "over the whole frame", ok, detail)
    for quality, name in ((0, "Full"), (1, "Half"), (2, "Quarter")):
        box_ok, box = placed(answer, "q4", quality, "mix", IN_BOX)
        rim_ok, rim = covered(answer, "q4", quality, "border", 1 - (5 / 6) ** 2,
                              COVERAGE_SLOP)
        check(f"Q4 {name}: a zoom between nest clips mixes inside the in-box (1/12 … 11/12) "
              "and shows the out half alone around it", box_ok and rim_ok,
              f"{box}\n       {rim}")
    scored = ["B0", "Q0", "Q1", "Q2", "Q3", "Q4"]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        if not rows.get("B0") or not rows.get("Q0"):
            print(f"mutant {args.mutant}: the control could not be performed")
            return 2
        survived = [name for name in named if rows.get(name)]
        print(f"{'MUTANT PASS' if not survived else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'}")
        return 0 if not survived else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
