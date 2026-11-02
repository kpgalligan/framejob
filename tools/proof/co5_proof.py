#!/usr/bin/env python3
"""Road map "creator-jobs" CO5 — Text Behind Subject (spec §11 CO-50…CO-56).

    python3 tools/proof/co5_proof.py [--only P1,B1,…] [--mutant NAME] [--app PATH]

**Probe row** (`co5_probe.swift`, built from every `app/Sources` file but `main.swift`, the probe
as `main.swift`, `FRAMEJOB_DEV_TOOLS`, through `swift_build.py`, into `WORK/probe`; no app):
- P1 `BehindSubjectPlan`: the pick order, min(4 s, the rest), the new track's index above a
  matte pair (2) and above `[V, M1→V, M2]` (3, not 2), the three refusals' sentences, three ops
  with a cutout and four without and what they make once applied, and `isCutBySubject`. A probe
  that does not build is a scored FAIL of P1.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME`, each document closed after its row, in two launches. The canned launch
(`-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`, `co2a_proof`'s: no job may land beside a
canned marker) builds `co2a_probe.swift` as `co4_proof` does for `co2a_proof.install_pack` and
`barcode_fixtures`. Its projects are 640 × 360, 30 fps, on a transparent canvas: the cut-out
camera is `barcode.mov` at scale 1/3 on the back track, so the canned bar-code pack (512 × 288:
rows 35–65 % 255, a coded band at 75–95 %, the rest 0) covers the canvas; the SHAPE is a full-canvas
opaque red rectangle on the track in front with `behind_subject`. A pixel is "all-255" or "all-0"
by the 3 × 3 mask-texel neighbourhood around it (`co2a_proof.neighbourhood`), read from the pack
through the probe's `mask` mode.
- B1 at 1 s: every all-255 pixel equals the frame with the shape hidden (opacity 0), every all-0
  pixel the frame with the camera hidden, byte for byte (each class over 1,000 pixels, and the
  all-255 pixels differ from the flag-off frame).
- B2 a second cut-out camera on a track IN FRONT of the shape at opacity 0.5, 100 px lower: where
  the back camera's neighbourhood is all-0 and the front camera's all-255, the frame equals the
  flag-off frame (the front camera does not cut the shape).
- B3 a split of the camera, its undo, a move onto a new back track and its undo each leave B1's
  frame byte-identical.
- B4 `background: keep`: the shape-hidden frame is opaque everywhere (the camera whole), and B1's
  two classes hold.
- B5 blur-0 shadows 20 px down on the camera and the shape: all-0 pixels (and the pixel 20 px
  above) equal the camera-hidden frame (the copy has no shadow), and all-255 pixels whose pixel
  20 px above is all-255 equal the shape-hidden frame (the shape's shadow is cut with it).
- B8 twin projects, the camera uncut, playhead 1 s: Insert ▸ Text Behind Subject
  (`perform_menu_item`) on one and `text_behind_subject {}` on the other give equal
  `get_project` projects (one track and one clip more, the camera cut out with `keep`), and one
  `undo` returns each to its start.
- B9 a pack whose coverage [200, 299] misses frame 60: the frame at 2 s with the flag is
  byte-identical to the flag-off frame (the copy draws nothing); control: at frame 250 they
  differ.
- B10 the cut-out camera on [0, 4 s) cross-dissolves into a second `barcode.mov` clip at 3 s with
  no cutout, the shape behind it: at 3.5 s (p = 0.5) every all-255 pixel's channels are within ±3
  of the mean of the flag-off and shape-hidden frames (a copy weighed with its partner's
  correction would give the shape-hidden frame).
The no-flag launch:
- B7 `push_1080.mov` (`co2a_proof.person_fixtures()`) on a 1920 × 1080 canvas, a title from
  `text_behind_subject {at: 0}` (which turns the cutout on with `keep`), masks made by
  `get_media_analysis` over 0–4 s; `play_preview` 4 s from 0, three runs with the flag on and
  three with it off: the median frames composed with it on is at least 95 % of the median off.
- Z1 each launch's `grep "Frame Job: "` prints nothing.

`--mutant NAME`: CO5's decision broken in a tree copy (`tree_copy.py`; a `core/` edit through
`hevc_alpha_proof.own_core`), the copy built as the proof's configuration (P1's mutant builds
only the probe from the copy's `app/Sources`), and only its rows run; CAUGHT (exit 0) when one of
them fails. The tree's mutated files' SHA-256 are read before and after and must be unchanged.
The seventh mutant, listed-uncut, is `core/tests/behind_subject.rs`'s `b6` run on a mutated copy
of `core/` (spec §11 CO-56).

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import hashlib
import json
import shutil
import statistics
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "cutout_spike"))
sys.path.insert(0, str(HERE / "creator_spike"))
import bounded  # noqa: E402
import co2a_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/co5"
HOME = WORK / "home"
SEC = 600_000
FRAME = 20_000
W, H = 640, 360
CALL_BOUND = 300
BUILD_BOUND = 1500
T = SEC
SHIFT = 20
FRONT_Y = 100
RED = [1.0, 0.0, 0.0, 1.0]
INSERT = ["Insert", "Text Behind Subject"]
CANNED = ["-RCDevAnalysisCanned", "YES", "-RCDevAnalysisHold", "3600"]
MIX_TOLERANCE = 3
PLAY_SECONDS = 4
PLAY_RUNS = 3
PLAY_FLOOR = 0.95

PROBE_ROWS = ["P1"]
CANNED_ROWS = ["B1", "B2", "B3", "B4", "B5", "B8", "B9", "B10"]
REAL_ROWS = ["B7"]
APP_ROWS = CANNED_ROWS + REAL_ROWS + ["Z1"]
ROWS = PROBE_ROWS + APP_ROWS

SUBJECT = "core/src/recipe_subject.rs"
EFFECTS = "app/Sources/CompositorEffects.swift"
MUTANTS = {
    "front-subjects": (["B2"], [(
        SUBJECT, "(Some(subject_index), Some(behind_index)) => subject_index < behind_index,",
        "(Some(subject_index), Some(behind_index)) => subject_index != behind_index,")]),
    "copy-shadow": (["B5"], [(
        SUBJECT, "        object.insert(\"shadow\".to_string(), Value::Null);\n", "")]),
    "three-steps": (["B8"], [(
        "app/Sources/AgentServer+BehindSubject.swift",
        "        _ = try performGroupedEdit(\n"
        "            document, BehindSubjectPlan.actionName,\n"
        "            BehindSubjectPlan.ops(plan, content: content))\n",
        "        for op in BehindSubjectPlan.ops(plan, content: content) {\n"
        "            _ = try performGroupedEdit(document, BehindSubjectPlan.actionName, [op])\n"
        "        }\n")]),
    "miss-whole": (["B9"], [(
        EFFECTS,
        "        if layer.cutout?.subjectCopy == true, uniforms.cutoutEnabled < 0.5 "
        "{ return nil }\n", "")]),
    "copy-partner": (["B10"], [(
        EFFECTS, "        let partner = layer.cutout?.subjectCopy == true\n",
        "        let partner = false\n")]),
    "one-matte-skip": (["P1"], [(
        "app/Sources/BehindSubjectPlan.swift",
        "        while index < tracks.count, tracks[index].matte != .none { index += 1 }\n",
        "        if index < tracks.count, tracks[index].matte != .none { index += 1 }\n")]),
}

results = {}
selected = set(ROWS)
built = False


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def app_sources(tree):
    return sorted(str(p) for p in (Path(tree) / "app/Sources").glob("*.swift")
                  if p.name != "main.swift")


# ---- P1: the planner probe ------------------------------------------------------------------

def p1(tree=ROOT):
    out = WORK / "probe5"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co5_probe.swift", entry)
    binary = out / "co5-probe"
    try:
        swift_build.build(sources=app_sources(tree) + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        check("P1", False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    run = bounded.run([str(binary)], 300)
    lines = [line for line in (run.get("stdout") or "").splitlines() if line.strip()]
    try:
        answer = json.loads(lines[-1])
    except (IndexError, ValueError):
        check("P1", False, f"co5-probe exited {run.get('rc')} with no answer: "
              f"{(run.get('stderr') or '')[-300:]}")
        return
    for row in answer.get("rows", []):
        check("P1", row.get("pass") is True, row.get("detail", ""))
    if not answer.get("rows"):
        check("P1", False, "co5-probe answered no rows")


# ---- the canned probe -----------------------------------------------------------------------

def canned_probe():
    """`co2a_probe.swift` built as `co4_proof.probe_row` builds it, for the canned packs."""
    global built
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co2a_probe.swift", entry)
    sources = app_sources(ROOT) + [str(HERE / "cutout_spike" / "mask_track_writer.swift")]
    binary = out / "co2a-probe"
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        detail = "the canned packs' probe did not build: " + "; ".join(error.diagnostics[:6])
        for row in CANNED_ROWS:
            check(row, False, detail)
        return
    co2a_proof.PROBE = binary
    co2a_proof.WORK = WORK
    built = True


# ---- the canned rows ------------------------------------------------------------------------

class Scene(co2a_proof.Drawn):
    """A 640 × 360 transparent canvas: the cut-out camera (`barcode.mov`, scale 1/3) on the back
    track and the flagged full-canvas red shape on a track in front."""

    def __init__(self, client, name, cutout=True, background="remove"):
        co2a_proof.barcode_fixtures()
        super().__init__(client, name)
        self.media_id, self.copy, self.duration = self.media(co2a_proof.BARCODE, "barcode")
        self.camera = self.place(self.media_id, cutout=cutout)
        if cutout and background != "remove":
            self.call("set_video", clips=[self.camera], patch={"cutout": {
                "background": background}})
        self.shape_track = self.add_track()
        self.shape = self.add_shape(self.shape_track)

    def place(self, media, track=None, at=0, cutout=True):
        """A clip of `media` filling the canvas at scale 1/3 (Fit new clips gives it that scale
        when the canvas fits it already, so the scale is written only when it differs)."""
        if track is None:
            tracks = self.project()["tracks"]
            if not tracks:
                self.call("add_track")
                tracks = self.project()["tracks"]
            track = tracks[0]["id"]
        before = {c["id"] for c in self.project()["clips"]}
        self.call("add_clip", track=track, media=media, at=at)
        clip = next(c for c in self.project()["clips"] if c["id"] not in before)
        patch = {}
        if abs((clip.get("video") or {}).get("scale", 1.0) - 1 / 3) > 1e-9:
            patch["scale"] = 1 / 3
        if cutout:
            patch["cutout"] = {}
        if patch:
            self.call("set_video", clips=[clip["id"]], patch=patch)
        return clip["id"]

    def add_track(self, index=None):
        before = {t["id"] for t in self.project()["tracks"]}
        self.call("add_track", **({} if index is None else {"index": index}))
        return next(t["id"] for t in self.project()["tracks"] if t["id"] not in before)

    def add_shape(self, track):
        before = {c["id"] for c in self.project()["clips"]}
        self.call("add_shape_clip", track=track, at=0, duration=10 * SEC, shape={
            "kind": "rectangle", "width": W, "height": H, "fill": RED, "stroke": None})
        shape = next(c["id"] for c in self.project()["clips"] if c["id"] not in before)
        self.call("set_video", clips=[shape], patch={"behind_subject": True})
        return shape

    def pack(self, **extra):
        return co2a_proof.install_pack(self.path, self.media_id, self.copy, self.duration,
                                       **extra)

    def frame(self, t, tag):
        return self.render(t, tag)[1]

    def hidden(self, clip, t, tag):
        self.call("set_video", clips=[clip], patch={"opacity": 0.0})
        out = self.frame(t, tag)
        self.call("set_video", clips=[clip], patch={"opacity": 1.0})
        return out

    def flag_off(self, t, tag):
        self.call("set_video", clips=[self.shape], patch={"behind_subject": False})
        out = self.frame(t, tag)
        self.call("set_video", clips=[self.shape], patch={"behind_subject": True})
        return out

    def mask(self, t):
        """The mask the camera draws at `t`, read from the pack: (bytes, width, height)."""
        pack = self.path / f"cache/analysis/masks/{self.media_id}/masks.pack"
        frames, _, mw, mh = co2a_proof.read_pack(pack)
        shown = max(i for i, f in enumerate(frames) if f[0] <= t)
        raw = WORK / f"{self.path.stem}-mask-{t}.bin"
        co2a_proof.run_probe(["mask", str(pack), str(frames[shown][2]), str(raw)])
        return raw.read_bytes(), mw, mh


def classes(mask, mw, mh, dy=0):
    """Each canvas pixel's class by its 3 × 3 neighbourhood (`dy` shifts the layer down):
    'one' all-255, 'zero' all-0, else None."""
    out = []
    for y in range(H):
        for x in range(W):
            ly = y - dy
            if not 0 <= ly < H:
                out.append(None)
            elif co2a_proof.neighbourhood(mask, mw, mh, x, ly, lambda v: v == 0):
                out.append("zero")
            elif co2a_proof.neighbourhood(mask, mw, mh, x, ly, lambda v: v == 255):
                out.append("one")
            else:
                out.append(None)
    return out


def px(frame, i):
    return frame[4 * i:4 * i + 4]


def two_classes(row, cut, shape_hidden, camera_hidden, kinds, what):
    """B1's oracle: all-255 pixels equal `shape_hidden`, all-0 ones `camera_hidden`."""
    zero = one = zero_bad = one_bad = 0
    for i, kind in enumerate(kinds):
        if kind == "zero":
            zero += 1
            zero_bad += px(cut, i) != px(camera_hidden, i)
        elif kind == "one":
            one += 1
            one_bad += px(cut, i) != px(shape_hidden, i)
    check(row, zero > 1000 and one > 1000 and not zero_bad and not one_bad,
          f"{what}: {one} all-255 pixels equal the shape hidden ({one_bad} differ), {zero} "
          f"all-0 pixels the camera hidden ({zero_bad} differ)")


def b1_b3(client):
    scene = Scene(client, "b1")
    try:
        scene.pack()
        mask, mw, mh = scene.mask(T)
        kinds = classes(mask, mw, mh)
        cut = scene.frame(T, "cut")
        shape_hidden = scene.hidden(scene.shape, T, "shape-hidden")
        camera_hidden = scene.hidden(scene.camera, T, "camera-hidden")
        off = scene.flag_off(T, "off")
        two_classes("B1", cut, shape_hidden, camera_hidden, kinds, "the flagged shape at 1 s")
        moved = sum(1 for i, k in enumerate(kinds) if k == "one" and px(cut, i) != px(off, i))
        check("B1", moved > 1000, f"{moved} all-255 pixels differ from the flag-off frame")
        if "B3" not in selected:
            return
        steps = [
            ("split at 3 s", lambda: scene.call("split", clips=[scene.camera], at=3 * SEC)),
            ("its undo", lambda: scene.call("undo")),
            ("a move onto a new back track", lambda: scene.call(
                "move_clip", clips=[scene.camera], delta=0, track=scene.add_track(index=0))),
            ("its undo", lambda: scene.call("undo")),
        ]
        for what, step in steps:
            step()
            again = scene.frame(T, f"b3-{len(results.get('B3', []))}")
            check("B3", again == cut, f"after {what}: the frame at 1 s byte-identical to B1's")
    finally:
        co2a_proof.close(client, scene.path)


def b2(client):
    scene = Scene(client, "b2")
    try:
        scene.pack()
        front_track = scene.add_track()
        before = {c["id"] for c in scene.project()["clips"]}
        scene.call("add_clip", track=front_track, media=scene.media_id, at=0)
        front = next(c["id"] for c in scene.project()["clips"] if c["id"] not in before)
        scene.call("set_video", clips=[front], patch={
            "scale": 1 / 3, "y": float(FRONT_Y), "opacity": 0.5, "cutout": {}})
        mask, mw, mh = scene.mask(T)
        back = classes(mask, mw, mh)
        ahead = classes(mask, mw, mh, dy=FRONT_Y)
        cut = scene.frame(T, "cut")
        off = scene.flag_off(T, "off")
        both = [i for i in range(W * H) if back[i] == "zero" and ahead[i] == "one"]
        bad = sum(1 for i in both if px(cut, i) != px(off, i))
        check("B2", len(both) > 1000 and not bad,
              f"{len(both)} pixels where the back camera's mask is all-0 and the front "
              f"camera's all-255 equal the flag-off frame ({bad} differ)")
    finally:
        co2a_proof.close(client, scene.path)


def b4(client):
    scene = Scene(client, "b4", background="keep")
    try:
        scene.pack()
        mask, mw, mh = scene.mask(T)
        kinds = classes(mask, mw, mh)
        cut = scene.frame(T, "cut")
        shape_hidden = scene.hidden(scene.shape, T, "shape-hidden")
        camera_hidden = scene.hidden(scene.camera, T, "camera-hidden")
        whole = all(shape_hidden[i] == 255 for i in range(3, len(shape_hidden), 4))
        check("B4", whole, "background keep: the camera is drawn whole (the shape-hidden frame "
              "is opaque at every pixel)")
        two_classes("B4", cut, shape_hidden, camera_hidden, kinds, "background keep")
    finally:
        co2a_proof.close(client, scene.path)


def b5(client):
    scene = Scene(client, "b5")
    try:
        scene.pack()
        shadow = {"color": [0, 0, 0, 1], "opacity": 1.0, "blur": 0.0, "angle": 270.0}
        scene.call("set_video", clips=[scene.camera], patch={"shadow": {
            **shadow, "distance": 3.0 * SHIFT}})
        scene.call("set_video", clips=[scene.shape], patch={"shadow": {
            **shadow, "distance": float(SHIFT)}})
        mask, mw, mh = scene.mask(T)
        kinds = classes(mask, mw, mh)
        cut = scene.frame(T, "cut")
        shape_hidden = scene.hidden(scene.shape, T, "shape-hidden")
        camera_hidden = scene.hidden(scene.camera, T, "camera-hidden")
        zero = [i for i in range(SHIFT * W, W * H)
                if kinds[i] == "zero" and kinds[i - SHIFT * W] == "zero"]
        one = [i for i in range(SHIFT * W, W * H)
               if kinds[i] == "one" and kinds[i - SHIFT * W] == "one"]
        # The rows just below the band: all-0 here, inside the band 20 px above, where the
        # camera's own shadow would cut the shape if the copy kept it.
        under = [i for i in range(SHIFT * W, W * H)
                 if kinds[i] == "zero" and kinds[i - SHIFT * W] == "one"]
        zero_bad = sum(1 for i in zero + under if px(cut, i) != px(camera_hidden, i))
        one_bad = sum(1 for i in one if px(cut, i) != px(shape_hidden, i))
        check("B5", len(zero) > 1000 and len(under) > 100 and not zero_bad,
              f"{len(zero) + len(under)} all-0 pixels ({len(under)} under the band, where the "
              f"camera's shadow falls) equal the camera hidden ({zero_bad} differ): the copy "
              f"casts no shadow")
        check("B5", len(one) > 1000 and not one_bad,
              f"{len(one)} all-255 pixels whose pixel {SHIFT} px above is all-255 equal the "
              f"shape hidden ({one_bad} differ): the shape's shadow is cut with it")
    finally:
        co2a_proof.close(client, scene.path)


def b8(client):
    def twin(name):
        scene = Scene(client, name, cutout=False)
        scene.call("delete", clips=[scene.shape])
        scene.call("remove_track", track=scene.shape_track)
        scene.call("set_playhead", t=T)
        return scene

    menu, tool = twin("b8-menu"), twin("b8-tool")
    try:
        starts = [menu.project(), tool.project()]
        got = menu.call("perform_menu_item", path=INSERT)
        answer = tool.call("text_behind_subject")
        made = [menu.project(), tool.project()]
        check("B8", made[0] == made[1],
              f"the menu ({got.get('selector')}, verdict {got.get('verdict')}) and the tool "
              f"(title {answer.get('text')}) made equal projects")
        grew = (len(made[1]["clips"]) == len(starts[1]["clips"]) + 1
                and len(made[1]["tracks"]) == len(starts[1]["tracks"]) + 1
                and answer.get("cutout_added") is True)
        check("B8", grew, f"one clip and one track more, cutout_added "
              f"{answer.get('cutout_added')}, duration {answer.get('duration')}")
        for doc, start, what in [(menu, starts[0], "the menu"), (tool, starts[1], "the tool")]:
            doc.call("undo")
            check("B8", doc.project() == start, f"one undo returns {what}'s project to its start")
    finally:
        co2a_proof.close(client, menu.path)
        co2a_proof.close(client, tool.path)


def b9(client):
    scene = Scene(client, "b9")
    try:
        scene.pack(coverage=[[200, co2a_proof.FRAMES - 1]])
        t = 2 * SEC  # frame 60, outside the coverage
        missed = scene.render(t, "missed")[0]
        scene.call("set_video", clips=[scene.shape], patch={"behind_subject": False})
        off = scene.render(t, "off")[0]
        inside_off = scene.frame(250 * FRAME, "inside-off")
        scene.call("set_video", clips=[scene.shape], patch={"behind_subject": True})
        inside = scene.frame(250 * FRAME, "inside")
        check("B9", inside is not None and inside != inside_off,
              "control: at frame 250, inside the coverage, the flag cuts the shape")
        check("B9", missed is not None and missed == off,
              "a pack whose coverage [200, 299] misses frame 60: the flagged frame is "
              "byte-identical to the flag-off one (the copy draws nothing)")
    finally:
        co2a_proof.close(client, scene.path)


def b10(client):
    scene = Scene(client, "b10")
    try:
        scene.call("trim_end", clip=scene.camera, to=4 * SEC)
        track = next(c["track"] for c in scene.project()["clips"] if c["id"] == scene.camera)
        incoming = scene.place(scene.media_id, track=track, at=3 * SEC, cutout=False)
        kind = next(c for c in scene.project()["clips"] if c["id"] == incoming)
        check("B10", (kind.get("transition_in") or {}).get("kind") == "cross_dissolve",
              f"the incoming clip's transition: {kind.get('transition_in')}")
        scene.pack()
        t = 3 * SEC + SEC // 2
        mask, mw, mh = scene.mask(t)
        kinds = classes(mask, mw, mh)
        cut = scene.frame(t, "cut")
        off = scene.flag_off(t, "off")
        shape_hidden = scene.hidden(scene.shape, t, "shape-hidden")
        one = [i for i, k in enumerate(kinds) if k == "one"]
        worst, far = 0, 0
        for i in one:
            for c in range(4):
                want = (off[4 * i + c] + shape_hidden[4 * i + c]) / 2
                d = abs(cut[4 * i + c] - want)
                worst = max(worst, d)
                far += d > MIX_TOLERANCE
        apart = sum(1 for i in one if px(off, i) != px(shape_hidden, i))
        check("B10", len(one) > 1000 and apart > 1000 and not far,
              f"at p = 0.5, {len(one)} all-255 pixels within ±{MIX_TOLERANCE} of the mean of "
              f"the flag-off and shape-hidden frames: worst {worst:.1f}, {far} channels off")
    finally:
        co2a_proof.close(client, scene.path)


# ---- B7: the real launch --------------------------------------------------------------------

def b7(client):
    push, _ = co2a_proof.person_fixtures()
    path = WORK / "b7.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = co2a_proof.Doc(client, path)
    try:
        canvas = doc.project()["canvas"]
        if (canvas["width"], canvas["height"], canvas["fps"]) != (1920, 1080, [30, 1]):
            doc.call("set_canvas", width=1920, height=1080, fps=[30, 1])
        copy = WORK / "media" / "push.mov"
        copy.parent.mkdir(parents=True, exist_ok=True)
        if not copy.exists():
            shutil.copyfile(push, copy)
        media = doc.call("import_media", path=str(copy))["media"]
        doc.call("add_track")
        track = doc.project()["tracks"][0]["id"]
        doc.call("add_clip", track=track, media=media, at=0)
        made = doc.call("text_behind_subject", at=0, content="BEHIND")
        title = made["text"]
        for _ in range(60):
            try:
                answer = doc.call("get_media_analysis", media=media, kind="masks",
                                  **{"from": 0, "to": PLAY_SECONDS * SEC})
                break
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        else:
            raise RuntimeError("the masks analysis did not finish in 60 calls")
        check("B7", answer.get("subject_found") is True,
              f"masks over 0–{PLAY_SECONDS} s: subject_found {answer.get('subject_found')}")

        def composed():
            doc.call("set_playhead", t=0)
            return doc.call("play_preview", seconds=PLAY_SECONDS)["frames_composed"]

        on = [composed() for _ in range(PLAY_RUNS)]
        doc.call("set_video", clips=[title], patch={"behind_subject": False})
        off = [composed() for _ in range(PLAY_RUNS)]
        ratio = statistics.median(on) / max(1, statistics.median(off))
        check("B7", ratio >= PLAY_FLOOR,
              f"frames composed with the title behind {on}, without {off}: median ratio "
              f"{ratio:.3f} (at least {PLAY_FLOOR})")
    finally:
        co2a_proof.close(client, path)


# ---- launches -------------------------------------------------------------------------------

def launch_rows(binary, arguments, log, bodies):
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for names, _ in bodies:
                for name in names & selected:
                    check(name, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid} ({' '.join(arguments) or 'no flags'})",
              flush=True)
        for names, body in bodies:
            if not names & selected:
                continue
            try:
                body(launched.client)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                for name in names & selected:
                    check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    if selected & set(CANNED_ROWS):
        canned_probe()
        if built:
            launch_rows(binary, CANNED, WORK / "instance.log", [
                ({"B1", "B3"}, b1_b3), ({"B2"}, b2), ({"B4"}, b4), ({"B5"}, b5),
                ({"B8"}, b8), ({"B9"}, b9), ({"B10"}, b10)])
    if selected & set(REAL_ROWS):
        launch_rows(binary, [], WORK / "instance-real.log", [({"B7"}, b7)])


# ---- mutants and main -----------------------------------------------------------------------

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def mutant_copy(name):
    edits = MUTANTS[name][1]
    made, reason = tree_copy.make_copy(str(WORK.parent / "co5-mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if any(path.startswith("core/") for path, _, _ in edits):
        reason = own_core(copy)
        if reason:
            return None, reason
    for path, anchor, replacement in edits:
        target = copy / path
        if not target.resolve().is_relative_to(WORK.parent / "co5-mutant"):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return copy, None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0])
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if selected & (set(APP_ROWS) - {"Z1"}):
        selected |= {"Z1"}
    remove_work()
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else None
    probe_tree = ROOT
    before = {}
    if args.mutant:
        print(f"CO5 — the {args.mutant} MUTANT ({', '.join(MUTANTS[args.mutant][0])} must "
              f"FAIL, {proof_app.config()} build)", flush=True)
        before = {p: sha(ROOT / p) for p, _, _ in MUTANTS[args.mutant][1]}
        copy, why = mutant_copy(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        if selected <= set(PROBE_ROWS):
            probe_tree = copy
        else:
            app, why = tree_copy.build_app(copy, BUILD_BOUND)
            if app is None:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            binary = proof_app.executable(app)
    else:
        print(f"CO5 — Text Behind Subject ({proof_app.config()} build)", flush=True)
    if "P1" in selected:
        p1(probe_tree)
    if selected & set(APP_ROWS):
        binary = binary or proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        after = {p: sha(ROOT / p) for p in before}
        restored = before == after
        print(f"the tree's mutated files' SHA-256 unchanged: {restored}")
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed)) and restored
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if named & set(failed) else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
