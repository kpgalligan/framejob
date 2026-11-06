#!/usr/bin/env python3
"""Docs-bugs batch a3 (#469, #476, #471, #481, #485; spec §11 CI-17, CI-18): canvas selection and
the inspector around it; and batch a5's CI-19 rows (#469's second half).

    python3 tools/proof/docs_bugs_a3_proof.py [--only D1,N3,…] [--tree PATH] [--expect-red]
                                              [--mutant NAME]

The projects are made by the app under test over MCP (`proof_app.binary()`, `RC_PROOF_APP`) in
`work/docs_bugs_a3/`, saved and closed, from media ffmpeg makes in `work/docs_bugs_a3_media/`. A
recording with a camera lands through `land_recording`, the recording's own code. Every row runs
through `docs_bugs_a3_probe.swift`, the app's own sources on those packages: a drag, a click and a
key press can't be sent over MCP. D1 and N3 are also read back through the app under test: what D1
saved is rendered beside the undragged project, and `snapshot_ui` captures the preview with the
nest selected and with nothing selected. N1's click has no MCP door, so N3's capture is the app's
word for it. V1 is an MCP row on the app under test alone.

`--tree PATH` builds the probe from `PATH/app/Sources`, its bridging header and
`PATH/core/target/release/libframejob_core.a`. `--expect-red` is the run against the base: it
exits 0 only when every row not marked CONTROL fails and every CONTROL passes, and prints a row
that does neither.

    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_a3_proof.py \
        --tree <base tree> --expect-red

Red on the base unless marked CONTROL:
- #469 (CI-17). D1 a drag at 4 s moves the box and the state at frames 0, 1 and 4 s, one undo step
  "Move" that restores them all; the render differs where the camera went and where it left. D2 a
  corner scale. D3 a nudge. D4 clicked on the timeline first. D5 frame 0, the cut selected: frame 0
  moves too. D6 frame 0 after Esc. D8 (CONTROL) before the zoom: the base, the box follows. D9 (CONTROL) a plain clip. D10 (CONTROL) a rotate on a clip with a cut: the base, on
  every frame, the cut's end gains no key. D12 (CONTROL) a multi-selection: the base. D13
  (CONTROL) a shape's box scale on a clip with a cut: the base.
- #469's second half (batch a5, CI-19, the owner's "Refuse and explain"). "Refused" is the strip at
  the inspector's foot reading the exact sentence, no undo step, and the base and every action's
  end as stored before. D7 a drag past a finished zoom (5 s): refused naming action 1 and
  "position", the box unmoved. D11 a one-frame layout action past clip time 0 is not a cut: a drag
  at 4 s refused. D14 a corner scale past the zoom: "position and size", "resize". D15 a ← nudge.
  D16 C and a crop-handle drag past the late layout action: "crop". D17 (CONTROL) a rotate past the
  zoom, which holds no rotation: the base, "Rotate". D18 (CONTROL) a press and release with no
  travel: selected, silent. D19 two finished zooms: the later one, action 2, is named. D20 the
  landed camera with a zoom at 2–3 s, at 5 s: action 2 named, the cut untouched. D21 (CONTROL) the
  same at 1 s: CI-17, the cut and the base move together. D22 (CONTROL) the zoom selected: its end
  is written. D23 (CONTROL) inside the zoom after Esc: the base. D24 (CONTROL) a shape's box scale
  past a zoom: the box grows. D25 (CONTROL) a text clip's right edge past a zoom holding no width:
  the base width. D26 the same clip's corner: refused. D27 (CONTROL) a ⇧-press that takes A out of
  {A, B}, then a drag of A: A's base, B's zoom not named. V1 (CONTROL, MCP) `set_video {x: −400}`
  past the zoom: the base −400, the end x 100.
- #476. N1 a click on the picture selects the nest, a clip behind it. N2 nothing behind. N3 the
  outline and handles (`primaryBox`, a handle hit); `snapshot_ui` differs with the nest selected.
  N4 a drag moves the nest, not the clip behind, undo "Move". N5 scale and rotate. N6 Z arms and a
  drawn region adds an action to the nest, solved on the nest's rectangle. N7 the box follows an action on the nest. N8 (CONTROL) C
  refuses. N9 (CONTROL) Place on Canvas refuses. N10 (CONTROL) a plain clip's box and hit are
  unchanged. N11 a nest with a Motion preset, part-way through: the box is the nested layer's
  `clip_rect`, not `clip_state`'s rest position. N12 a full-canvas ⌘G nest of a corner clip over a
  clip behind: a click on the corner picture picks the nest, its outline the whole canvas. N13
  (CONTROL) the same nest: a click off the corner picture picks the clip behind.
- #471. P1 Assistant, a first click on the timeline: Clip. P2 on the canvas. P3 Transcript, a first
  click on B: B's first word at the top. P4 from nothing selected, the same. P5 Assistant, a marquee
  of four ticks: stays (the base moves to Clip on the second tick). P6 (CONTROL) a re-click on a
  selected clip from Media: Clip.
- #481 (CI-18). M1 every Shape-sub-tab row with a control reads ⊘ with an action selected, the
  gradient off and on. M2 the five sections `allNotAnimatable`, the note showing, Reset kept. M3 the
  tag visible on Add Filter, Add Region with Place on Canvas, and each Remove, none clipped. M4
  (CONTROL) no action: no ⊘ and every tag hidden. M5 (CONTROL) a filter's Amount stays animating.
- #485. S1 a drag to 138, 60 and 4 pt from the edge: held at 280, View "Hide Inspector", the key
  false. S2 ⌥⌘I hides, the key true, it survives a window resize, and ⌥⌘I shows it again at
  280–440 pt (the base comes back under 280).
  S3 ⌥⌘I, then a drag out: shown, the key false, a new window shown. S4 (CONTROL) ⌥⌘I, then a new
  window hidden.
- Z1 (CONTROL) `grep "Frame Job: "` on the log prints nothing.

`--mutant NAME` breaks one decision in a `tree_copy.py` copy, builds the probe from it and runs only
the row it must fail: CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits
2. `cut-any-key` D10, `cut-any-start` D11, `no-cut-base` D5, batch a5's nine (`held-any-time` D8
and D23, `held-cut-too` D21, `held-earliest` D19, `held-any-key` D17, `held-on-press` D18,
`held-shape-scale` D24, `held-no-nudge` D15, `held-width-as-scale` D25, `held-selection-first`
D27), `nest-no-motion` N11 (the core: the
copy gets a real `core/` and rebuilds its staticlib), `nest-whole-rect` N13, `nest-obscure-open`
N9, `pick-before-write` P1, `swept-is-pick` P5, `no-shape-path` M1, `collapse-true` S1,
`no-key-clear` S3, `no-show-clamp` S2. An instrument that cannot run is a scored failure, never an exit.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import editor_keys_undo_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import proof_defaults  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs_bugs_a3"
MEDIA = ROOT / "tools/proof/work/docs_bugs_a3_media"
FIXTURES = WORK / "fixtures"
PROBE = "docs_bugs_a3_probe"
SEC = 600_000
FRAME = SEC // 30
PROBE_BOUND = 540
CALL_BOUND = 300

PROBE_ROWS = ([f"D{i}" for i in range(1, 28)] + [f"N{i}" for i in range(1, 14)]
              + [f"P{i}" for i in range(1, 7)] + [f"M{i}" for i in range(1, 6)]
              + [f"S{i}" for i in range(1, 5)])
MCP_ROWS = ["V1"]
ROWS = PROBE_ROWS + MCP_ROWS + ["Z1"]
CONTROLS = {"D8", "D9", "D10", "D12", "D13", "D17", "D18", "D21", "D22", "D23", "D24", "D25",
            "D27", "V1", "N8", "N9", "N10", "N13", "P6", "M4", "M5", "S4", "Z1"}

TARGET = "app/Sources/CanvasEditTarget.swift"
CANVAS = "app/Sources/PreviewCanvasView.swift"
BOX = "app/Sources/CanvasLayerBox.swift"
REGION = "app/Sources/EditorViewController+ZoomRegion.swift"
TIMELINE = "app/Sources/EditorViewController+Timeline.swift"
MARKS = "app/Sources/InspectorMarks.swift"
EDITOR = "app/Sources/EditorViewController.swift"
PANES = "app/Sources/EditorViewController+Panes.swift"
RECIPE = "core/src/recipe.rs"
WRITE_THEN_PICK = ("        if changed { document.selection = ids }\n"
                   "        if !ids.isEmpty { inspector?.clipPicked() }\n")
SWEPT = ("        guard let document = document, document.selection != ids else { return }\n"
         "        document.selection = ids\n")
COLLAPSE = "canCollapseSubview subview: NSView) -> Bool {\n"
CLEAR_KEY = ("            if defaults.bool(forKey: inspectorCollapsedKey) {\n"
             "                defaults.set(false, forKey: inspectorCollapsedKey)\n"
             "            }\n")
SHOW_CLAMP = "        guard !inspector.isHidden else { return }\n"
MUTANTS = {
    "cut-any-key": (["D10"], [(
        TARGET, "              Self.holds(cut.end, gesture)\n",
        "              Self.holds(cut.end, gesture) || true\n")]),
    "cut-any-start": (["D11"], [(
        TARGET, "        action.start == 0 && action.duration <= frame && ",
        "        action.duration <= frame && ")]),
    "no-cut-base": (["D5"], [(
        TARGET, "        return [edit, .setVideo(clips: [clip], patch: patch)]\n",
        "        return [edit]\n")]),
    "nest-no-motion": (["N11"], [(
        RECIPE, "        let moved = self.nest_moved(&instance.inside, 0, t);\n",
        "        let moved = self\n"
        "            .evaluate_clip(outermost.clip, t.saturating_sub(outermost.origin))\n"
        "            .video;\n")]),
    "nest-whole-rect": (["N13"], [(
        BOX, "        guard let picture else { return true }\n"
             "        return picture.contains { $0.contains(point) }\n",
        "        return true\n")]),
    "nest-obscure-open": (["N9"], [(
        REGION, "           target.picture != nil || obscureRegions().count >= ObscureProps.max {\n",
        "           obscureRegions().count >= ObscureProps.max {\n")]),
    "pick-before-write": (["P1"], [(
        TIMELINE, WRITE_THEN_PICK,
        "        if !ids.isEmpty { inspector?.clipPicked() }\n"
        "        if changed { document.selection = ids }\n")]),
    "swept-is-pick": (["P5"], [(
        TIMELINE, SWEPT, SWEPT + "        if !ids.isEmpty { inspector?.clipPicked() }\n")]),
    "no-shape-path": (["M1"], [(MARKS, ', "set_shape": "shape",\n', ",\n")]),
    "collapse-true": (["S1"], [(
        EDITOR, COLLAPSE + "        false\n", COLLAPSE + "        subview === inspectorContainer\n")]),
    "no-key-clear": (["S3"], [(PANES, CLEAR_KEY, "")]),
    "no-show-clamp": (["S2"], [(PANES, SHOW_CLAMP, "        return\n")]),
    # Batch a5, CI-19: one per decision.
    "held-any-time": (["D8", "D23"], [(
        TARGET, "            .filter { !isCut($0, frame: frame) && $0.endTime <= clipTime }\n",
        "            .filter { !isCut($0, frame: frame) }\n")]),
    "held-cut-too": (["D21"], [(
        TARGET, "            .filter { !isCut($0, frame: frame) && $0.endTime <= clipTime }\n",
        "            .filter { $0.endTime <= clipTime }\n")]),
    "held-earliest": (["D19"], [(
        TARGET, "            .max { ($0.endTime, $0.id) < ($1.endTime, $1.id) }\n",
        "            .min { ($0.endTime, $0.id) < ($1.endTime, $1.id) }\n")]),
    "held-any-key": (["D17"], [(
        TARGET, "            .filter { !heldKeys($0.end, gesture).isEmpty }\n", "")]),
    "held-on-press": (["D18"], [(
        TARGET, "        return refusedGesture != nil\n",
        "        if let refused = refusedGesture { onRefuse?(refused.refusal) }\n"
        "        return refusedGesture != nil\n")]),
    "held-shape-scale": (["D24"], [(
        TARGET, "        if gesture == .scale, case .shape = clip.source { return nil }\n", "")]),
    "held-no-nudge": (["D15"], [(
        CANVAS, "        if let id = primaryBox?.id, let refusal = heldRefusal(.move, clip: id) {"
                " onRefuse?(refusal); return true }\n", "")]),
    "held-width-as-scale": (["D25"], [(
        TARGET, "        guard clip.text != nil, case .text = clip.source, handle.drivesX, "
                "!handle.isCorner\n        else { return .scale }\n        return .width\n",
        "        return .scale\n")]),
    "held-selection-first": (["D27"], [(
        TARGET, "        guard editTarget.selected == nil, selection == [id], "
                "let clip = snapshot.clip(id),\n",
        "        guard editTarget.selected == nil, selection.count == 1, let first = selection.first,"
        "\n              let clip = snapshot.clip(first),\n")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}  {detail}"[:600], flush=True)


# ---- the media and the fixtures -----------------------------------------------------

def make_media():
    """screen.mov, camera.mov, silence.m4a and silent-120.wav, kept between runs."""
    MEDIA.mkdir(parents=True, exist_ok=True)
    made = [
        ("screen.mov", ["-f", "lavfi", "-i", "testsrc=size=1920x1080:rate=30:duration=20",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p"]),
        ("camera.mov", ["-f", "lavfi", "-i", "testsrc2=size=640x360:rate=30:duration=8",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p"]),
        ("silence.m4a", ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "20",
                         "-c:a", "aac"]),
        ("silent-120.wav", ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "120",
                            "-c:a", "pcm_s16le"]),
    ]
    for name, arguments in made:
        path = MEDIA / name
        if not path.exists():
            part = MEDIA / f"part-{name}"
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", *arguments, str(part)], check=True)
            part.rename(path)


def fresh(c, name):
    path = str(FIXTURES / f"{name}.framejob")
    c.call_with("new_project", {"path": path})
    return {"project": path}


def track0(c, a):
    return c.call_with("get_project", a)["project"]["tracks"][0]["id"]


def imported(c, a, name):
    return c.call_with("import_media", {**a, "path": str(MEDIA / name)})["media"]


def clip_of(c, a, track, media, at=0):
    return c.call_with("add_clip", {**a, "track": track, "media": media, "at": at})["new_clips"][0]


def finish(c, a, ids):
    c.call_with("save_project", a)
    c.call_with("close_project", a)
    return {**ids, "path": a["project"]}


def layout_end(x=100, y=50, scale=0.5):
    """All six placement keys, which make an action a layout action (`action_class.rs`)."""
    return {"video": {"x": x, "y": y, "scale": scale, "corner_radius": 0, "opacity": 1,
                      "crop": {"l": 0, "t": 0, "r": 0, "b": 0}}}


def nest_fixture(c, name, after=None):
    """screen.mov 0–5 s behind, camera.mov 0–8 s nested in front, the nest at half size at x 300,
    y 100."""
    a = fresh(c, name)
    screen = imported(c, a, "screen.mov")
    camera = imported(c, a, "camera.mov")
    behind = clip_of(c, a, track0(c, a), screen)
    c.call_with("trim_end", {**a, "clip": behind, "to": 5 * SEC})
    top = c.call_with("add_track", a)["new_tracks"][0]
    front = clip_of(c, a, top, camera)
    nest = c.call_with("nest", {**a, "clips": [front]})["new_clips"][0]
    c.call_with("set_video", {**a, "clips": [nest], "patch": {"scale": 0.5, "x": 300, "y": 100}})
    if after:
        after(a, nest)
    return finish(c, a, {"behind": behind, "front": front, "nest": nest})


def make_fixtures(c):
    shutil.rmtree(FIXTURES, ignore_errors=True)
    FIXTURES.mkdir(parents=True)
    out = {}

    a = fresh(c, "cam")
    c.call_with("land_recording", {**a, "movie": str(MEDIA / "screen.mov"),
                                   "voice": [str(MEDIA / "silence.m4a")],
                                   "camera": str(MEDIA / "camera.mov")})
    clips = c.call_with("get_project", a)["project"]["clips"]
    # The screen clip takes a first-frame cut too (CO-80), so a camera is told by where it landed.
    camera = next(x for x in clips if (x.get("video") or {}).get("x") == 624)
    screen = next(x for x in clips if x["id"] != camera["id"])
    out["cam"] = finish(c, a, {"camera": camera["id"], "screen": screen["id"]})

    a = fresh(c, "zoom")
    clip = clip_of(c, a, track0(c, a), imported(c, a, "screen.mov"))
    action = c.call_with("add_action", {**a, "clip": clip, "at": 2 * SEC,
                                        "duration": SEC})["new_actions"][0]
    c.call_with("set_action_end", {**a, "clip": clip, "action": action,
                                   "patch": {"video": {"x": 100, "scale": 1.5}}})
    out["zoom"] = finish(c, a, {"clip": clip})

    a = fresh(c, "plain")
    out["plain"] = finish(c, a, {"clip": clip_of(c, a, track0(c, a),
                                                 imported(c, a, "screen.mov"))})

    a = fresh(c, "late")
    clip = clip_of(c, a, track0(c, a), imported(c, a, "screen.mov"))
    action = c.call_with("add_action", {**a, "clip": clip, "at": 2 * SEC,
                                        "duration": FRAME})["new_actions"][0]
    c.call_with("set_action_end", {**a, "clip": clip, "action": action, "patch": layout_end()})
    out["late"] = finish(c, a, {"clip": clip})

    # Batch a5's (CI-19).
    def zoomed(a, clip, end, at=2 * SEC, duration=SEC):
        action = c.call_with("add_action", {**a, "clip": clip, "at": at,
                                            "duration": duration})["new_actions"][0]
        c.call_with("set_action_end", {**a, "clip": clip, "action": action, "patch": end})

    zoom_end = {"video": {"x": 100, "scale": 1.5}}
    a = fresh(c, "twozoom")
    clip = clip_of(c, a, track0(c, a), imported(c, a, "screen.mov"))
    zoomed(a, clip, {"video": {"x": -200}}, SEC, SEC // 2)
    zoomed(a, clip, {"video": {"x": 100}})
    out["twozoom"] = finish(c, a, {"clip": clip})

    a = fresh(c, "camzoom")
    c.call_with("land_recording", {**a, "movie": str(MEDIA / "screen.mov"),
                                   "voice": [str(MEDIA / "silence.m4a")],
                                   "camera": str(MEDIA / "camera.mov")})
    clips = c.call_with("get_project", a)["project"]["clips"]
    camera = next(x for x in clips if (x.get("video") or {}).get("x") == 624)["id"]
    zoomed(a, camera, {"video": {"x": 400}})
    out["camzoom"] = finish(c, a, {"camera": camera})

    a = fresh(c, "shapezoom")
    clip = c.call_with("add_shape_clip", {**a, "track": track0(c, a), "at": 0,
                                          "duration": 8 * SEC})["new_clips"][0]
    zoomed(a, clip, zoom_end)
    out["shapezoom"] = finish(c, a, {"clip": clip})

    a = fresh(c, "textzoom")
    clip = c.call_with("add_text_clip", {**a, "track": track0(c, a), "at": 0,
                                         "duration": 8 * SEC, "text": "Frame Job"})["new_clips"][0]
    zoomed(a, clip, zoom_end)
    out["textzoom"] = finish(c, a, {"clip": clip})

    a = fresh(c, "pairzoom")
    screen = imported(c, a, "screen.mov")
    left = clip_of(c, a, track0(c, a), screen)
    c.call_with("set_video", {**a, "clips": [left], "patch": {"scale": 0.4, "x": -500}})
    top = c.call_with("add_track", a)["new_tracks"][0]
    right = clip_of(c, a, top, screen)
    c.call_with("set_video", {**a, "clips": [right], "patch": {"scale": 0.4, "x": 500}})
    zoomed(a, right, {"video": {"x": 600}})
    out["pairzoom"] = finish(c, a, {"a": left, "b": right})

    a = fresh(c, "shapecut")
    clip = c.call_with("add_shape_clip", {**a, "track": track0(c, a), "at": 0,
                                          "duration": 8 * SEC})["new_clips"][0]
    action = c.call_with("add_action", {**a, "clip": clip, "at": 0,
                                        "duration": FRAME})["new_actions"][0]
    c.call_with("set_action_end", {**a, "clip": clip, "action": action,
                                   "patch": layout_end(0, 0, 1)})
    out["shapecut"] = finish(c, a, {"clip": clip})

    out["nest"] = nest_fixture(c, "nest")

    def act(a, nest):
        action = c.call_with("add_action", {**a, "clip": nest, "at": SEC,
                                            "duration": SEC})["new_actions"][0]
        c.call_with("set_action_end", {**a, "clip": nest, "action": action,
                                       "patch": {"video": {"x": -300}}})
    out["nestact"] = nest_fixture(c, "nestact", act)

    def moved(a, nest):
        c.call_with("set_video", {**a, "clips": [nest], "patch": {
            "motion": {"in": {"kind": "slide_left", "duration": SEC}}}})
    out["nestmotion"] = nest_fixture(c, "nestmotion", moved)

    a = fresh(c, "corner")
    behind = clip_of(c, a, track0(c, a), imported(c, a, "screen.mov"))
    top = c.call_with("add_track", a)["new_tracks"][0]
    front = clip_of(c, a, top, imported(c, a, "camera.mov"))
    c.call_with("set_video", {**a, "clips": [front], "patch": {"scale": 0.75, "x": 624, "y": 351}})
    nest = c.call_with("nest", {**a, "clips": [front]})["new_clips"][0]
    out["corner"] = finish(c, a, {"behind": behind, "nest": nest})

    a = fresh(c, "pick")
    t = track0(c, a)
    first = clip_of(c, a, t, imported(c, a, "camera.mov"))
    second = clip_of(c, a, t, imported(c, a, "screen.mov"), 8 * SEC)
    out["pick"] = finish(c, a, {"first": first, "second": second})

    a = fresh(c, "words")
    media = imported(c, a, "silent-120.wav")
    t = track0(c, a)
    clip_a = clip_of(c, a, t, media)
    c.call_with("trim_end", {**a, "clip": clip_a, "to": 60 * SEC})
    clip_b = clip_of(c, a, t, media, 70 * SEC)
    c.call_with("trim_end", {**a, "clip": clip_b, "to": 130 * SEC})
    out["words"] = finish(c, a, {"clip_a": clip_a, "clip_b": clip_b, "media": media})

    a = fresh(c, "marks")
    t = track0(c, a)
    video = clip_of(c, a, t, imported(c, a, "screen.mov"))
    c.call_with("add_action", {**a, "clip": video, "at": 2 * SEC, "duration": SEC})
    c.call_with("set_video", {**a, "clips": [video], "patch": {
        "filters": [{"kind": "blur", "amount": 0.5}],
        "obscure": [{"kind": "pixelate", "x": 0.25, "y": 0.25, "width": 0.2, "height": 0.2}]}})
    top = c.call_with("add_track", a)["new_tracks"][0]
    shape = c.call_with("add_shape_clip", {**a, "track": top, "at": 5 * SEC,
                                           "duration": 4 * SEC})["new_clips"][0]
    c.call_with("set_shape", {**a, "clips": [shape], "patch": {"radius": 10}})
    out["marks"] = finish(c, a, {"video": video, "shape": shape})

    (FIXTURES / "fixtures.json").write_text(json.dumps(out, indent=1))
    return out


def with_app(binary, name, body):
    """`body(client)` in one launch of `binary`; False when it could not run. Scores Z1."""
    log = WORK / f"{name}.log"
    launched = mcp.launch(str(binary), ["-RCDevAppearance", "dark"], log_path=str(log),
                          timeout=CALL_BOUND)
    done = False
    try:
        if launched.client is None:
            print("  the app did not listen", flush=True)
            return False
        print(f"  instance PID {launched.child.pid}", flush=True)
        body(launched.client)
        done = True
    except Exception as error:  # noqa: BLE001 — a scored failure, never the run's
        print(f"  {name} failed: {type(error).__name__}: {error}", flush=True)
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return done


# ---- reading back through the app ---------------------------------------------------

def rgb(path):
    """A 1920 × 1080 picture file's pixels as raw RGB bytes, through ffmpeg."""
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1", "-f",
                           "rawvideo", "-pix_fmt", "rgb24", "-s", "1920x1080", "-"],
                          capture_output=True, check=True).stdout


def region(raw, box, width=1920):
    x, y, w, h = box
    return b"".join(raw[((y + r) * width + x) * 3:((y + r) * width + x + w) * 3] for r in range(h))


def difference(a, b):
    """Mean absolute difference of two equal byte strings, sampled every 7th byte."""
    total = count = 0
    for p, q in zip(a[::7], b[::7]):
        total += abs(p - q)
        count += 1
    return round(total / max(count, 1), 2)


CORNER = (1344, 756, 480, 270)    # where the camera lands
AIMED = (220, 105, 480, 270)      # where D1's drag sends it: x −500, y −300


def read_back(c):
    out = WORK / "read-back"
    out.mkdir(parents=True, exist_ok=True)

    def render(project, tag, t):
        path = out / f"{tag}.png"
        c.call_with("render_frame", {"project": project, "t": t, "path": str(path)})
        return rgb(path)

    if "D1" in selected:
        dragged = WORK / "run/run-D1.framejob"
        base = out / "cam-undragged.framejob"
        shutil.copytree(FIXTURES / "cam.framejob", base)
        c.call_with("open_project", {"path": str(base)})
        c.call_with("open_project", {"path": str(dragged)})
        scores = []
        for tag, t in (("frame1", FRAME), ("t4", 4 * SEC)):
            a = render(str(base), f"base-{tag}", t)
            b = render(str(dragged), f"dragged-{tag}", t)
            scores.append((difference(region(a, CORNER), region(b, CORNER)),
                           difference(region(a, AIMED), region(b, AIMED))))
        for project in (base, dragged):
            c.call_with("close_project", {"project": str(project), "discard": True})
        check("D1", all(left > 5 and went > 5 for left, went in scores),
              f"render against the undragged project, (corner, aimed): {scores}")

    if "N3" in selected:
        nest = json.loads((FIXTURES / "fixtures.json").read_text())["nest"]
        a = {"project": str(out / "nest.framejob")}
        shutil.copytree(nest["path"], a["project"])
        c.call_with("open_project", {"path": a["project"]})
        c.call_with("set_playhead", {**a, "t": 2 * SEC})
        time.sleep(0.6)
        shots = []
        for tag, clips in (("none", []), ("nest", [nest["nest"]])):
            c.call_with("set_selection", {**a, "clips": clips})
            time.sleep(0.5)
            path = out / f"preview-{tag}.png"
            c.call_with("snapshot_ui", {**a, "window": "editor", "view": "preview",
                                        "path": str(path)})
            shots.append(path.read_bytes())
        c.call_with("close_project", {**a, "discard": True})
        check("N3", shots[0] != shots[1], "snapshot_ui of the preview differs with the nest selected: "
              f"{shots[0] != shots[1]}")


# ---- the probe ----------------------------------------------------------------------

def build_probe(tree):
    """(the binary, None) or (None, why)."""
    folder = WORK / "probe"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    entry = folder / "main.swift"
    shutil.copyfile(HERE / f"{PROBE}.swift", entry)
    tree = Path(tree)
    shader, why = editor_keys_undo_proof.build_shader(str(folder), str(tree))
    if shader is None:
        return None, why
    try:
        built = swift_build.build(
            sources=[str(p) for p in swift_build.app_sources(tree / "app/Sources")] + [str(entry)],
            output=folder / PROBE, defines=["FRAMEJOB_DEV_TOOLS"],
            bridging_header=tree / "app/Bridging/FrameJob-Bridging-Header.h",
            library=tree / "core/target/release/libframejob_core.a")
    except swift_build.SwiftBuildFailed as error:
        return None, str(error)[:600]
    print(f"  probe {built.key} reused {built.reused}, {built.seconds} s", flush=True)
    return folder / PROBE, None


def run_probe(binary, wanted):
    """Every row the probe printed, by id; (rows, why)."""
    run = WORK / "run"
    shutil.rmtree(run, ignore_errors=True)
    run.mkdir(parents=True)
    rows = {}
    command = [str(binary), str(FIXTURES / "fixtures.json"), str(run)]
    if set(wanted) != set(PROBE_ROWS):
        command.append(",".join(wanted))
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=PROBE_BOUND)
    except subprocess.TimeoutExpired as expired:
        out = expired.stdout or b""
        (WORK / "probe.out.txt").write_bytes(out if isinstance(out, bytes) else out.encode())
        for line in (out.decode(errors="replace") if isinstance(out, bytes) else out).splitlines():
            if line.startswith("{"):
                row = json.loads(line)
                rows[row.get("row")] = row
        return rows, f"no answer within {PROBE_BOUND} s"
    finally:
        left = proof_defaults.remove_domain(PROBE)
        if left:
            print(f"  the probe's defaults domain: {left}", flush=True)
    (WORK / "probe.out.txt").write_text(done.stdout + "\n--- stderr\n" + done.stderr)
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            row = json.loads(line)
            if "abort" in row:
                return rows, row["abort"]
            rows[row.get("row")] = row
    if done.returncode != 0:
        return rows, f"the probe exited {done.returncode}: {done.stderr[-300:]}"
    return rows, None


def near(a, b, slack=0.01):
    return a is not None and b is not None and abs(a - b) <= slack


def together(values, wanted, slack=14):
    """Every frame's value at one number, within the snapper's reach of `wanted`."""
    return (all(v is not None for v in values) and max(values) - min(values) < 0.001
            and abs(values[0] - wanted) <= slack)


def moved_box(x, dx=-1124, dy=-651, slack=14):
    b, a = x["before"], x["after"]
    return (len(a) == 4 and len(b) == 4 and abs(a[0] - b[0] - dx) <= slack
            and abs(a[1] - b[1] - dy) <= slack)


def camera_moved(x):
    return together(x["xs"], -500) and together(x["ys"], -300) and moved_box(x)


def sentence(n, what, noun):
    """CI-19's strip, exactly."""
    return (f"Refused: action {n} on this clip's lane holds its {what} at the playhead, so a "
            f"{noun} here would show only before it. Select action {n} first.")


def refused(x, n, what, noun):
    """CI-19's refusal: the sentence at the inspector's foot, no undo step, and the base and every
    action's end as stored before."""
    return (x["strip"] == sentence(n, what, noun) and x["undo"] == "" and bool(x["before"])
            and x["before"] == x["after"])


def silent(x, undo):
    """No refusal shown, and `undo` the step the gesture made."""
    return x["strip"] is None and x["undo"] == undo


def stored_video(state):
    return json.loads(state["video"])


def moved_x(x):
    return stored_video(x["after"])["x"] - stored_video(x["before"])["x"]


def end_x(state, index):
    return (json.loads(state["ends"][index]).get("video") or {}).get("x")


def text_width(state):
    return json.loads(state["text"]).get("width") if state["text"] else None


def score(r):
    def row(name):
        got = r.get(name)
        if got and "failed" in got:
            check(name, False, got["failed"])
            return None
        return got

    def told(name, ok):
        got = row(name)
        if got:
            shown = {k: v for k, v in got.items() if k != "row"}
            check(name, ok(got), json.dumps(shown, sort_keys=True, ensure_ascii=False))

    told("D1", lambda x: camera_moved(x) and x["undo"] == "Move" and x["selected"] is None
         and near(x["box_frame0"][0], x["after"][0]) and near(x["box_frame1"][0], x["after"][0])
         and together(x["undone"]["xs"], 624, 0.01) and together(x["undone"]["ys"], 351, 0.01)
         and x["undone_end_x"] == 624 and x["more_undo"] == "")
    told("D2", lambda x: len(x["after"]) == 4 and x["after"][2] > x["before"][2] + 40
         and len(set(x["scales"])) == 1 and x["scales"][0] > 0.75 + 0.05
         and max(x["xs"]) - min(x["xs"]) < 0.001 and max(x["ys"]) - min(x["ys"]) < 0.001
         and x["undo"] == "Scale")
    told("D3", lambda x: together(x["xs"], 623, 0.01) and together(x["ys"], 351, 0.01)
         and x["undo"] == "Nudge")
    told("D4", lambda x: camera_moved(x) and x["undo"] == "Move")
    told("D5", lambda x: x["held"] and camera_moved(x) and x["undo"] == "Move")
    told("D6", lambda x: x["held"] and x["cleared"] and camera_moved(x) and x["undo"] == "Move")
    told("D7", lambda x: refused(x, 1, "position", "move") and x["box_before"] == x["box_after"])
    told("D8", lambda x: near(x["base"], -400, 14) and x["end"] == x["end_before"] == 100
         and near(x["after"][0], x["before"][0] - 400, 14) and x["undo"] == "Move")
    told("D9", lambda x: near(x["base"], -400, 14) and x["end"] is None
         and near(x["after"][0], x["before"][0] - 400, 14) and x["undo"] == "Move")
    told("D10", lambda x: x["base"] not in (None, 0) and x["end_rotation"] is None
         and all(near(s, x["base"]) for s in x["states"]) and x["undo"] == "Rotate")
    told("D11", lambda x: refused(x, 1, "position", "move"))
    told("D12", lambda x: near(x["base_x"], -500, 14) and x["end_x"] == 624 and x["undo"] == "Move")
    told("D13", lambda x: x["width"] > x["width_before"] and x["end_scale"] == x["end_scale_before"]
         and x["end_x"] == x["end_x_before"] and x["undo"] == "Scale")

    # Batch a5, CI-19.
    told("D14", lambda x: refused(x, 1, "position and size", "resize")
         and x["hit"].startswith("handle("))
    told("D15", lambda x: refused(x, 1, "position", "move"))
    told("D16", lambda x: x["crop"] and x["hit"].startswith("cropHandle(")
         and refused(x, 1, "crop", "crop"))
    told("D17", lambda x: x["hit"].startswith("rotation(") and silent(x, "Rotate")
         and stored_video(x["after"])["rotation"] != stored_video(x["before"])["rotation"]
         and x["after"]["ends"] == x["before"]["ends"])
    zoom = FIXTURE_IDS["zoom"]["clip"]
    told("D18", lambda x: x["selection"] == [zoom] and silent(x, "") and x["before"] == x["after"])
    told("D19", lambda x: refused(x, 2, "position", "move"))
    told("D20", lambda x: refused(x, 2, "position", "move"))
    told("D21", lambda x: silent(x, "Move") and near(moved_x(x), -400, 14)
         and near(end_x(x["after"], 0), stored_video(x["after"])["x"])
         and x["after"]["ends"][1] == x["before"]["ends"][1])
    told("D22", lambda x: x["selected_before"] is not None and silent(x, "Move")
         and stored_video(x["after"]) == stored_video(x["before"])
         and near(end_x(x["after"], 0) - end_x(x["before"], 0), -400, 14))
    told("D23", lambda x: x["held"] and x["cleared"] and silent(x, "Move")
         and near(moved_x(x), -400, 14) and x["after"]["ends"] == x["before"]["ends"])
    told("D24", lambda x: x["hit"].startswith("handle(") and silent(x, "Scale")
         and json.loads(x["after"]["shape"])["width"] > json.loads(x["before"]["shape"])["width"]
         and x["after"]["ends"] == x["before"]["ends"])
    told("D25", lambda x: x["hit"].startswith("handle(") and silent(x, "Scale")
         and text_width(x["after"]) is not None and text_width(x["after"]) != text_width(x["before"])
         and x["after"]["ends"] == x["before"]["ends"])
    told("D26", lambda x: x["hit"].startswith("handle(")
         and refused(x, 1, "position and size", "resize"))
    told("D27", lambda x: x["pressed"] == [FIXTURE_IDS["pairzoom"]["b"]] and silent(x, "Move")
         and abs(moved_x(x)) > 50 and x["other_before"] == x["other_after"])

    nest = FIXTURE_IDS["nest"]["nest"]
    behind = FIXTURE_IDS["nest"]["behind"]
    told("N1", lambda x: x["selection"] == [nest])
    told("N2", lambda x: x["selection"] == [nest])
    told("N3", lambda x: x["primary"] == nest and x["handle"]
         and all(near(a, b) for a, b in zip(x["rect"], [780, 370, 960, 540])))
    told("N4", lambda x: x["selection"] == [nest] and near(x["nest_x"], 200, 14)
         and near(x["nest_y"], 50, 14) and x["behind_x"] == 0 and x["undo"] == "Move")
    told("N5", lambda x: x["scale"] is not None and x["scale"] > 0.55 and x["scaled"] == "Scale"
         and x["rotation"] not in (None, 0) and x["rotated"] == "Rotate")
    # A 400 × 230 band centred at canvas (1100, 575), inside a half-size nest at x 300, y 100: fit
    # takes it ×4.696 and its centre to the canvas's, so the zoom lands on the nest's own picture.
    told("N6", lambda x: x["armed"] and x["actions"] == 1 and x["undo"] == "Zoom to Region"
         and near(x["end_scale"], 2.348, 0.02) and near(x["end_x"], 751.3, 8)
         and near(x["end_y"], 305.2, 8))
    told("N7", lambda x: x["primary"] == FIXTURE_IDS["nestact"]["nest"]
         and near(x["mid_x"], 960 - 300) and x["base_x"] == 300)
    told("N8", lambda x: not x["crop"] and x["selection"] == [nest])
    told("N9", lambda x: not x["armed"] and x["selection"] == [nest])
    told("N10", lambda x: x["hit"] and all(near(a, b) for a, b in zip(x["rect"], [0, 0, 1920, 1080])))
    told("N11", lambda x: x["primary"] == FIXTURE_IDS["nestmotion"]["nest"]
         and len(x["clip_rect"]) == 3 and near(x["mid_x"], x["clip_rect"][0])
         and near(x["mid_y"], x["clip_rect"][1]) and near(x["width"], x["clip_rect"][2])
         and x["rest_x"] == 300 and abs(x["mid_x"] - (960 + 300)) > 1)
    told("N12", lambda x: x["selection"] == [FIXTURE_IDS["corner"]["nest"]]
         and all(near(a, b) for a, b in zip(x["rect"], [0, 0, 1920, 1080])) and len(x["rect"]) == 4)
    told("N13", lambda x: x["selection"] == [FIXTURE_IDS["corner"]["behind"]])

    first = FIXTURE_IDS["pick"]["first"]
    for name in ("P1", "P2"):
        told(name, lambda x: x["start"] == "Assistant" and x["tab"] == "Clip"
             and x["selection"] == [first])
    for name in ("P3", "P4"):
        told(name, lambda x: x["tab"] == "Transcript" and x["b_first"] > 0
             and x["top"] == x["b_first"])
    told("P5", lambda x: x["start"] == "Assistant" and x["tab"] == "Assistant"
         and sum(1 for t in x["ticks"] if t) >= 2)
    told("P6", lambda x: x["start"] == "Media" and x["tab"] == "Clip")

    def inert(marks):
        return bool(marks) and all(m.endswith(": notAnimatable") for m in marks)

    told("M1", lambda x: x["selected"] and inert(x["off"]) and inert(x["on"])
         and len(x["on"]) > len(x["off"]))
    told("M2", lambda x: x["sections"] == ["Shape", "Stroke", "Fill", "Gradient", "Arrowheads"]
         and all(x["all"]) and all(x["notes"]) and x["shape_button"] == "Reset")
    told("M3", lambda x: x["selected"] and all(v == 1 for v in x["tags"].values())
         and x["clipped"] == 0)
    told("M4", lambda x: x["none_selected"] and all(v == 0 for v in x["tags"].values())
         and x["video_marks"] and x["shape_marks"]
         and not any("notAnimatable" in m for m in x["video_marks"] + x["shape_marks"]))
    told("M5", lambda x: x["selected"] and x["animates"] and x["mark"] != "notAnimatable"
         and not x["section_all"])

    def held(facts):
        return (facts["width"] == 280 and not facts["hidden"] and facts["menu"] == "Hide Inspector"
                and not facts["key"])

    def shown(facts):
        return not facts["hidden"] and facts["menu"] == "Hide Inspector" and not facts["key"]

    def hidden(facts):
        return facts["hidden"] and facts["menu"] == "Show Inspector" and facts["key"]

    told("S1", lambda x: len(x["seen"]) == 3 and all(held(f) for f in x["seen"]))
    told("S2", lambda x: hidden(x["hidden"]) and hidden(x["resized"]) and shown(x["shown"])
         and 280 <= x["shown"]["width"] <= 440)
    told("S3", lambda x: hidden(x["hidden"]) and shown(x["out"]) and x["next"]
         and shown(x["next"]))
    told("S4", lambda x: hidden(x["hidden"]) and x["next"] and hidden(x["next"]))


FIXTURE_IDS = {}


def probe_rows(tree):
    wanted = [r for r in PROBE_ROWS if r in selected]
    if not wanted:
        return False
    binary, why = build_probe(tree)
    if binary is None:
        for row in wanted:
            check(row, False, f"the probe did not build: {why}")
        return False
    rows, why = run_probe(binary, wanted)
    if why:
        print(f"  the probe stopped: {why}", flush=True)
    try:
        score(rows)
    except (KeyError, TypeError, IndexError) as error:
        print(f"  a reading was not what the score expected: {error!r}", flush=True)
    for row in wanted:
        if row not in results:
            check(row, False, f"the probe printed no such row ({why or 'it finished'})")
    return True


def v1(c):
    """CI-19 leaves `set_video` alone: past the finished zoom, `x: −400` is the base's, and the
    zoom's end keeps its x."""
    zoom = FIXTURE_IDS["zoom"]
    a = {"project": str(WORK / "v1.framejob")}
    shutil.rmtree(a["project"], ignore_errors=True)
    shutil.copytree(zoom["path"], a["project"])
    c.call_with("open_project", {"path": a["project"]})
    c.call_with("set_playhead", {**a, "t": 5 * SEC})
    c.call_with("set_video", {**a, "clips": [zoom["clip"]], "patch": {"x": -400}})
    clip = next(x for x in c.call_with("get_project", a)["project"]["clips"]
                if x["id"] == zoom["clip"])
    c.call_with("close_project", {**a, "discard": True})
    base = (clip.get("video") or {}).get("x")
    ends = [((x.get("end") or {}).get("video") or {}).get("x") for x in clip.get("actions") or []]
    check("V1", base == -400 and ends == [100], f"base x {base}, the actions' end x {ends}")


def fixtures_by(binary):
    def body(client):
        FIXTURE_IDS.update(make_fixtures(client))
        print(f"  fixtures: {sorted(FIXTURE_IDS)}", flush=True)
        if "V1" in selected:
            v1(client)
    return with_app(binary, "fixtures", body)


def run_rows(binary, tree):
    make_media()
    if not fixtures_by(binary):
        for row in PROBE_ROWS + MCP_ROWS:
            if row not in results:
                check(row, False, "the fixtures were not made")
        return
    if probe_rows(tree) and selected & {"D1", "N3"}:
        if not with_app(binary, "read-back", read_back):
            for row in selected & {"D1", "N3"}:
                check(row, False, "the read-back did not finish")


# ---- mutants ------------------------------------------------------------------------

def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def real_core(made):
    """A copy's own `core/`, its target copied on write, so a core edit stays in the copy. A
    `tree_copy` copy's `core` is a link to the tree's."""
    link = Path(made) / "core"
    if link.is_symlink():
        link.unlink()
    subprocess.run(["cp", "-cR", str(ROOT / "core"), str(link)], check=True)


def build_core(made):
    """The copy's staticlib; None or why not."""
    done = subprocess.run(["cargo", "build", "--release"], cwd=Path(made) / "core",
                          capture_output=True, text=True)
    return None if done.returncode == 0 else done.stderr[-400:]


def run_mutant(name):
    global selected
    rows, edits = MUTANTS[name]
    print(f"docs bugs a3: the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    before = {path: digest(path) for path, _, _ in edits}
    selected = set(rows) | {"Z1"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"), agent=False)
    core = any(path.startswith("core/") for path, _, _ in edits)
    if not why and core:
        real_core(made)
    if not why:
        for path, anchor, replacement in edits:
            target = Path(made) / path
            text = target.read_text()
            if text.count(anchor) != 1:
                why = f"the anchor occurs {text.count(anchor)} times in {path}"
                break
            target.write_text(text.replace(anchor, replacement))
    if not why and core:
        why = build_core(made)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    make_media()
    if not fixtures_by(proof_app.binary()):
        print(f"mutant {name}: the control could not be performed — no fixtures")
        return 2
    probe_rows(made)
    after = {path: digest(path) for path, _, _ in edits}
    print(f"  the tree's files unchanged by SHA-256: {before == after}")
    if not all(row in results for row in rows):
        print(f"mutant {name}: the control could not be performed — {rows} never scored")
        return 2
    caught = any(not all(ok for ok, _ in results[row]) for row in rows)
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if caught else 'passed'}", flush=True)
    tree_copy.remove_tree(made)
    return 1 if caught else 0


def scores():
    failed = [n for n in ROWS if n in results and not all(ok for ok, _ in results[n])]
    passed = [n for n in ROWS if n in results and n not in failed]
    return passed, failed


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--tree", default=str(ROOT))
    parser.add_argument("--expect-red", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    if args.mutant:
        return run_mutant(args.mutant)
    print(f"docs bugs a3 ({proof_app.config()} build), tree {args.tree}", flush=True)
    run_rows(proof_app.binary(), args.tree)
    passed, failed = scores()
    print(f"\nscores: {len(passed)}/{len(passed) + len(failed)}"
          + (f"; failed {failed}" if failed else ""), flush=True)
    if args.expect_red:
        wrong = [r for r in failed if r in CONTROLS] + [r for r in passed if r not in CONTROLS]
        print("expected red, every row not marked CONTROL failing and every CONTROL passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
