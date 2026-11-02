#!/usr/bin/env python3
"""Road map "creator-jobs" CO2a1 and CO2a2 — `video.cutout`, the recipe's
`cutout` key (spec §11 CO-20, CO-21, CO-23) and Remove Background drawn from
the cached masks (CO-24…CO-29).

    python3 tools/proof/co2a_proof.py [--only B0,D13p,…] [--mutant NAME] [--app PATH]

CO2a1's app fixture is a version-38 project over a copy of `media/A.mov`
(640×360, 30 fps, 10 s): one clip at 0 for 6 s and one zoom action over [1 s,
3 s) ending at scale 2, on a 1280×720 canvas.

**Probe rows** (`co2a_probe.swift` with `cutout_spike/mask_track_writer.swift`,
built from `app/Sources` with `FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no
app):
- B0 the probe builds (a failed build is a scored FAIL, and so are the rest).
- D13p a two-media project (media 5 and 7, clips 11 and 12): `VideoProps.cutout`
  equals the JSON; `VideoPatch(cutout: .some(p))` writes all five keys and
  `.some(nil)` an `NSNull`; `recipe(at:)`'s layer `cutout` decodes mask media
  5 for clip 11 and 7 for clip 12, and the rest; `recipeJSON` names media 5.
- D1p (CO-24) ten cases' plans — a trim, ×0.5, ×2, ×1.37, a ramp, a freeze, a
  reverse, a split, a nest and a cross-dissolve — at every composition frame,
  against a pack analysed at every frame and one at 15 a second: the probe's
  `sourceTick` equals this script's (exact, nearest tick, halves away from 0),
  and the slot's mask frame equals `deciders.expected_mask` of the frame shown
  there (a reversed clip's at `T − s − 1`, mirrored by `deciders.ends`).

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`) on a scratch
`CFFIXED_USER_HOME`, in two launches. The canned rows' launch adds `-RCDevAnalysisHold 3600`
to `-RCDevAnalysisCanned YES`: since CO2b (spec §11 CO-22) a cut-out clip's document wants its
masks at once, and any publish deletes a canned marker, so no job may land there; a frame whose
masks are missing (D14, D3's two misses) therefore waits 30 s before drawing uncut. D2 and D4,
which make real masks through `get_media_analysis`, run in a second launch with neither flag.
The canned launch's rows:
- D8 each refusal in CO-20's sentence, `get_project` unchanged after each: a
  cutout on a text clip; an action end naming `video.cutout.subject`, then
  `.quality`; `off: ["video.cutout"]`; `edge: 2`.
- D10 the version-38 fixture as a package's `project.json`, opened: every key
  the fixture spells equal, `version` the header's, no `cutout` anywhere;
  `render_frame` at 3 times; `save_project` to a new package, `close_project`,
  `open_project`: `get_project` equal and the 3 PNGs byte-identical.
- D13 `set_video {cutout: {}}` → the five defaults; `{background: "keep",
  edge: 0.25}` merges; `null` removes the key.
- D14 3 `render_frame`s of a clip with a cutout and no masks cached and of the
  same clip with none: byte-identical (CO-6).
- D1 the ten cases on one track of a 640 × 360 transparent canvas, each bar-code
  clip `barcode.mov` (300 frames 1920 × 1080, frame k carrying k, CO-S2's
  writer) at scale 1/3 with a cutout, from a canned pack (every frame, then 15
  a second): a `prores_4444` export decoded by ffmpeg, each frame's picture code
  (read through the mask's solid-255 band, rows 35–65 %) and alpha code (the
  analysed frame's index, rows 75–95 %) scored by `deciders.expected_mask`; in
  the cross-dissolve (outgoing `A.mov`, opaque and full-frame; incoming the
  cut-out bar code) the outgoing alpha where the incoming's mask is 0 is
  round(255·(1 − p)) ±1 at each overlap frame (never 255 through it, 0 after
  it), and the incoming's codes are scored after the overlap.
- D11 the freeze case's frames (a still of frame k draws k's mask), D16 the
  reverse case's (frame k draws the forward mask at `T − end`), from D1's.
- D2 (the second launch) `push_1080.mov` (`cutout_spike.fixtures()`), masks made by
  `get_media_analysis` over 0–2 s, at 3 `render_frame`s on an opaque canvas:
  every pixel whose 3 × 3 mask-texel neighbourhood is all 0 equals the frame
  with the clip hidden (opacity 0), and all ≥ 192 (where r0's remap is exactly
  1; the push-in's masks top out at 246, so none is 255) the uncut frame, byte
  for byte
  (the mask read by the probe's `mask` mode from the pack this script parses).
- D3 a canned pack whose coverage [200, 299] misses frame 60, and a stamped
  marker of another stamp, each draw byte-identical to cutout off (control:
  frame 250 draws its mask).
- D4 (the second launch) `screen_4k.mov`'s real masks over 0–2 s (no person): 3 frames with the
  cutout equal those with none, byte for byte (CO-5).
- D6 a blur-0 shadow 20 px down: where the layer's alpha is 0, the shadow's
  alpha is the layer's 20 px above, within 1/255.
- D7 the same frame in an SDR and an HLG project: alpha within 1/255.
- D12 `barcode_rot.mov` (the bar code's first 3 s transposed, tagged
  `-display_rotation 90`): at 3 frames the picture code and the alpha code
  both read k.
- D15 a cutout-less project (A.mov, corner radius, shadow, a zoom action):
  3 `render_frame` PNGs and a 2 s `prores_4444` export's per-frame md5 equal
  those of the base's app (`BASE`: the tree copied, its `app/` replaced by
  `git archive BASE app`, built by `tree_copy.build_app`).
- Z1 each launch's `grep "Frame Job: "` prints nothing.

`--mutant NAME`: CO2a2's decision broken in a tree copy (`tree_copy.py`), the
copy built as the proof's configuration, and only its rows run; CAUGHT (exit
0) when one of them fails.

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import json
import re
import shutil
import struct
import subprocess
import sys
import time
from fractions import Fraction
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "cutout_spike"))
sys.path.insert(0, str(HERE / "creator_spike"))
import bounded  # noqa: E402
import cutout_spike  # noqa: E402
import deciders  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co2a"
HOME = WORK / "home"
HEADER = ROOT / "core/include/framejob_core.h"
MOVIE = ROOT / "tools/proof/media/A.mov"
CALL_BOUND = 300
SEC = 600_000
PROBE_ROWS = ["B0", "D13p", "D1p"]
DRAWN = ["D1", "D11", "D16", "D2", "D3", "D4", "D6", "D7", "D12", "D15"]
APP_ROWS = ["D8", "D10", "D13", "D14"] + DRAWN + ["Z1"]
ROWS = PROBE_ROWS + APP_ROWS
FFMPEG = cutout_spike.FFMPEG
BARCODE_DIR = cutout_spike.MEDIA / "co2a"
BARCODE = BARCODE_DIR / "barcode.mov"
ROTATED = BARCODE_DIR / "barcode_rot.mov"
PUSH = cutout_spike.MEDIA / "push_1080.mov"
SCREEN = cutout_spike.MEDIA / "screen_4k.mov"
FRAMES = 300
FRAME = 20_000
W, H = 640, 360
REVERSE_BOUND = 300
EXPORT_BOUND = 900
BUILD_BOUND = 1500
SHADOW_SHIFT = 20
# D2's uncut class: r0's remap at edge 0 and feather 0 is smoothstep(0.25, 0.75, m), exactly 1
# for every m ≥ 0.75 — every bilinear mix of texels ≥ 192 (192/255 > 0.75). The push-in's
# person never reaches 255 (CO-S1's poster: its masks top out at 246), so no texel is 255.
SATURATED = 192
D2_TIMES = [3 * SEC // 2, 5 * SEC // 3, 19 * SEC // 10]
D4_TIMES = [SEC // 3, SEC, 5 * SEC // 3]
D15_TIMES = [SEC // 4, SEC, 3 * SEC // 2]
# The integration HEAD CO2a2 was built on: D15's base app.
BASE = "f82c5b202e4d517abb20a85882cfc61bf99a7377"
CANNED = ["-RCDevAnalysisCanned", "YES"]
# No job may land beside a canned marker (CO-22: a cut-out clip wants its masks at once).
HELD = ["-RCDevAnalysisHold", "3600"]
PROBE = None

LOOKUP = "app/Sources/CutoutLookup.swift"
DRAW = "app/Sources/Compositor+Cutout.swift"
SHADER = "app/Resources/Shaders/Compositor.metal"
MUTANTS = {
    "partner-box": (["D1"], [(
        "app/Sources/Compositor+Uniforms.swift",
        "            partner.cutout?.background != .remove,\n", "")]),
    "oriented-uv": (["D12"], [(
        SHADER, "    float2 cutoutUV = uv;\n",
        "    float2 cutoutUV = orientedUV(uv, u.sourceQuarterTurns, u.sourceMirrored);\n")]),
    "one-frame-late": (["D1"], [(
        LOOKUP, "        guard let f = pack.shown(at: query) else { return nil }\n",
        "        guard let f = pack.shown(at: query - Int64(grid.frameTicks.rounded()))\n"
        "        else { return nil }\n")]),
    "nearest-frame": (["D1"], [(
        DRAW, "                sourceTick: CutoutLookup.sourceTick(segment, at: t),\n",
        "                sourceTick: Ticks((Double(CutoutLookup.sourceTick(segment, at: t))\n"
        "                    / pack.grid.frameTicks).rounded() * pack.grid.frameTicks),\n")]),
    "miss-transparent": (["D3"], [(
        DRAW, "            let texture = cutoutMasks.texture(pack, slot: slot)\n"
        "        else { return placeholder }\n",
        "            let texture = cutoutMasks.texture(pack, slot: slot)\n"
        "        else { uniforms.opacity = 0; return placeholder }\n")]),
    "shadow-placeholder": (["D6"], [(
        "app/Sources/Compositor+Dissolve.swift",
        "curves: prepared.curves, cutout: prepared.cutout, cursor: prepared.cursor,",
        "curves: prepared.curves, cutout: placeholder, cursor: prepared.cursor,")]),
    "co5-per-range": (["D4"], [(
        LOOKUP, "            .contains(where: \\.subjectFound)\n", "            .isEmpty == false\n")]),
    "mask-lifted": (["D7"], [(
        SHADER, "    float m = mask.sample(samp, uv).r;\n",
        "    float m = u.hlgOutput > 0.5 ? pow(mask.sample(samp, uv).r, 0.8)\n"
        "                                : mask.sample(samp, uv).r;\n")]),
    "pivot": (["D16"], [(
        LOOKUP, "ReverseMirror.mirrored(sourceTick, about: $0) - 1 }",
        "ReverseMirror.mirrored(sourceTick, about: $0) }")]),
}
RENDER_TIMES = [SEC // 2, 2 * SEC, 4 * SEC]
DEFAULTS = {"subject": "person", "quality": "standard", "background": "remove",
            "edge": 0.0, "feather": 0.0}
SUBJECT_SENTENCE = "video.cutout.subject is not an animation target"
QUALITY_SENTENCE = "video.cutout.quality is not an animation target"
OFF_SENTENCE = ("video.cutout cannot be keyed off at an action's end; "
                "set_video {cutout: null} removes it")
EDGE_SENTENCE = "video.cutout.edge must be between -1 and 1, not 2"

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, never a copy."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


def movie():
    copy = WORK / "media" / "A.mov"
    if not copy.exists():
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(MOVIE, copy)
    return copy


def fixture():
    """The version-38 project: A.mov, one clip, one zoom action."""
    return {
        "version": 38,
        "canvas": {"width": 1280, "height": 720, "fps": [30, 1]},
        "media": [{"id": 1, "path": str(movie()), "kind": "video", "duration": 10 * SEC,
                   "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                   "has_audio": False}],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": 6 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0}, "video": {},
                   "actions": [{"id": 4, "start": SEC, "duration": 2 * SEC,
                                "curve": "linear",
                                "end": {"video": {"scale": 2.0, "x": 120.0}}}]}],
        "next_id": 5,
    }


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the probe row -------------------------------------------------------------

def probe_rows(force=False):
    rows = [r for r in PROBE_ROWS if r in selected]
    if not rows and not force:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co2a_probe.swift", entry)
    sources = sorted(str(p) for p in (ROOT / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    sources.append(str(HERE / "cutout_spike" / "mask_track_writer.swift"))
    binary = out / "co2a-probe"
    try:
        swift_build.build(sources=sources + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        detail = "the probe did not build: " + "; ".join(error.diagnostics[:6])
        for row in rows:
            check(row, False, detail)
        return
    check("B0", True, f"built {binary.name}")
    global PROBE
    PROBE = binary
    request = out / "request.json"
    request.write_text(json.dumps({"movie": str(movie())}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=300)
        whole = json.loads(run.stdout)
        answer = whole["rows"]
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        for row in rows:
            if row != "B0":
                check(row, False, f"the probe gave no answer: {error}")
        return
    if "D1p" in rows:
        score_d1p(whole.get("d1p") or {})
    by_id = {r["id"]: r for r in answer}
    for row in rows:
        if row in ("B0", "D1p"):
            continue
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


def nearest_tick(value):
    """A `Fraction` to the nearest integer, halves away from 0."""
    whole = abs(value.numerator) * 2 + value.denominator
    rounded = whole // (2 * value.denominator)
    return rounded if value >= 0 else -rounded


def score_d1p(answer):
    """The probe's rows against this script's own source tick and `deciders`."""
    problems = answer.get("problems") or []
    rows = answer.get("rows") or []
    analysed = {rate: deciders.analysed_frames(range(FRAMES), rate) for rate in ("every", "15")}
    check("D1p", not problems and answer.get("analysed") == analysed,
          f"the cases built and the packs' analysed frames are CJ-23's: {problems[:3]}")
    tallies, wrong = {}, []
    for case, rate, t, _, _, sin, sd, start, d, s, pivot, mask in rows:
        mine = nearest_tick(Fraction(sin) + Fraction((t - start) * sd, d)) if d > 0 else sin
        picture = ((pivot - mine - 1) if pivot >= 0 else mine) // FRAME
        want = (expected(picture, analysed[rate], pivot >= 0)
                if 0 <= picture < FRAMES else None)
        got = mask // FRAME if mask >= 0 and mask % FRAME == 0 else None
        ok = s == mine and got == want
        tallies.setdefault((case, rate), [0, 0])[0 if ok else 1] += 1
        if not ok:
            wrong.append((case, rate, t, s, mine, picture, got, want))
    for (case, rate), (good, bad) in sorted(tallies.items()):
        if bad:
            check("D1p", False, f"{case} at {rate}: {bad} of {good + bad} frames wrong")
    check("D1p", len(tallies) == 20 and not wrong,
          f"{len(rows)} (frame, segment, pack) rows over {len(tallies)} case × rate pairs: "
          f"the source tick and the slot's mask frame as expected"
          + (f"; first wrong (case, rate, t, s, mine, picture, got, want) {wrong[:3]}"
             if wrong else ""))


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, Path(path)

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def frames(self, tag):
        shots = []
        for t in RENDER_TIMES:
            out = WORK / f"{tag}-{t}.png"
            if out.exists():
                out.unlink()
            self.call("render_frame", t=t, path=str(out))
            shots.append(out.read_bytes() if out.exists() else None)
        return shots


def new_doc(client, name):
    path = WORK / f"{name}.framejob"
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    doc = Doc(client, path)
    doc.call("set_canvas", width=1280, height=720, fps=[30, 1])
    doc.call("save_project")
    return doc


def close(client, path):
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass


def error_of(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def contains(whole, part):
    """Every key `part` spells is in `whole` with an equal value; lists by index."""
    if isinstance(part, dict):
        return isinstance(whole, dict) and all(
            k in whole and contains(whole[k], v) for k, v in part.items())
    if isinstance(part, list):
        return isinstance(whole, list) and len(whole) == len(part) and all(
            contains(w, p) for w, p in zip(whole, part))
    if isinstance(part, (int, float)) and not isinstance(part, bool):
        return isinstance(whole, (int, float)) and not isinstance(whole, bool) and whole == part
    return whole == part


def media_clip(doc):
    """A.mov added and placed at 0 on the first track; the clip's id."""
    doc.call("add_media", descriptor={
        "path": str(movie()), "kind": "video", "duration": 10 * SEC, "width": 640,
        "height": 360, "fps": [30, 1], "has_video": True})
    project = doc.project()
    tracks = project["tracks"]
    if not tracks:
        doc.call("add_track")
        tracks = doc.project()["tracks"]
    doc.call("add_clip", track=tracks[0]["id"], media=project["media"][0]["id"], at=0)
    return doc.project()["clips"][0]["id"], tracks[0]["id"]


def video_of(doc, clip):
    return next(c for c in doc.project()["clips"] if c["id"] == clip).get("video") or {}


def d8(client):
    doc = new_doc(client, "d8")
    try:
        clip, track = media_clip(doc)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        doc.call("add_text_clip", track=track, at=11 * SEC)
        text = next(c["id"] for c in doc.project()["clips"] if c["id"] != clip)
        doc.call("add_action", clip=clip, at=SEC)
        action = next(c for c in doc.project()["clips"] if c["id"] == clip)["actions"][0]["id"]
        before = doc.project()
        cases = [
            ("a text clip", f"clip {text} is a text clip and cannot take a cutout",
             lambda: doc.call("set_video", clips=[text], patch={"cutout": {}})),
            ("an end's subject", SUBJECT_SENTENCE,
             lambda: doc.call("set_action_end", clip=clip, action=action,
                              patch={"video": {"cutout": {"subject": "person"}}})),
            ("an end's quality", QUALITY_SENTENCE,
             lambda: doc.call("set_action_end", clip=clip, action=action,
                              patch={"video": {"cutout": {"quality": "standard"}}})),
            ("off video.cutout", OFF_SENTENCE,
             lambda: doc.call("set_action_end", clip=clip, action=action, patch={},
                              off=["video.cutout"])),
            ("edge 2", EDGE_SENTENCE,
             lambda: doc.call("set_video", clips=[clip], patch={"cutout": {"edge": 2}})),
        ]
        for what, sentence, body in cases:
            message = error_of(body) or ""
            check("D8", sentence in message, f"{what}: {message[:200] or 'no error'}")
            check("D8", doc.project() == before, f"{what}: get_project unchanged")
    finally:
        close(client, doc.path)


def d10(client):
    made = new_doc(client, "v38")
    close(client, made.path)
    old = fixture()
    (made.path / "project.json").write_text(json.dumps(old, indent=2))
    client.call("open_project", path=str(made.path))
    doc = Doc(client, made.path)
    saved = WORK / "v39.framejob"
    try:
        first = doc.project()
        expected = dict(old, version=format_version())
        check("D10", first.get("version") == format_version() and contains(first, expected)
              and '"cutout"' not in json.dumps(first),
              f"the v38 file opened as version {first.get('version')}, the fixture's every "
              "key equal, no cutout key")
        shots = doc.frames("v38")
        check("D10", all(s for s in shots), f"{sum(1 for s in shots if s)} frames rendered")
        if saved.exists():
            shutil.rmtree(saved)
        doc.call("save_project", path=str(saved))
        close(client, saved)
        close(client, made.path)
        client.call("open_project", path=str(saved))
        again = Doc(client, saved)
        second = again.project()
        check("D10", second == first, "saved, closed and reopened: get_project equal")
        reshots = again.frames("v39")
        same = [a is not None and a == b for a, b in zip(shots, reshots)]
        check("D10", all(same), f"the 3 PNGs byte-identical: {same}")
    finally:
        close(client, saved)
        close(client, made.path)


def d13_d14(client):
    doc = new_doc(client, "d13")
    try:
        clip, _ = media_clip(doc)
        uncut = doc.frames("uncut") if "D14" in selected else []
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        stored = video_of(doc, clip).get("cutout")
        check("D13", stored == DEFAULTS, f"{{cutout: {{}}}} stored {stored}")
        doc.call("set_video", clips=[clip], patch={"cutout": {"background": "keep", "edge": 0.25}})
        merged = video_of(doc, clip).get("cutout")
        want = dict(DEFAULTS, background="keep", edge=0.25)
        check("D13", merged == want, f"a patch merged to {merged}")
        if "D14" in selected:
            cut = doc.frames("cut")
            same = [a is not None and a == b for a, b in zip(uncut, cut)]
            check("D14", len(uncut) == 3 and all(same),
                  f"3 frames with the cutout equal the uncut ones: {same}")
        doc.call("set_video", clips=[clip], patch={"cutout": None})
        removed = video_of(doc, clip)
        check("D13", "cutout" not in removed, f"null removed it: {sorted(removed)}")
    finally:
        close(client, doc.path)


# ---- CO2a2: fixtures, canned packs and reading frames -----------------------------

def ffmpeg(args, out, seconds=600):
    out.parent.mkdir(parents=True, exist_ok=True)
    partial = out.with_name(out.stem + ".partial" + out.suffix)
    run = subprocess.run([FFMPEG, "-v", "error", "-y", *args, str(partial)],
                         capture_output=True, text=True, timeout=seconds,
                         env=bounded.child_env())
    if run.returncode != 0 or not partial.exists():
        raise RuntimeError(f"ffmpeg for {out.name}: {run.stderr[-400:]}")
    partial.replace(out)


def barcode_fixtures():
    """`barcode.mov` (300 frames, 1920×1080, frame k carrying k, CO-S2's writer through the
    probe's `barcode` mode) and `barcode_rot.mov` (its first 3 s transposed and tagged
    `-display_rotation 90`, so it displays as `barcode.mov`)."""
    BARCODE_DIR.mkdir(parents=True, exist_ok=True)
    if not BARCODE.exists():
        answer = run_probe(["barcode", str(BARCODE), str(FRAMES)])
        if not answer.get("ok"):
            raise RuntimeError(f"the bar-code movie was not written: {answer}")
    if not ROTATED.exists():
        transposed = BARCODE_DIR / "barcode_t.mov"
        ffmpeg(["-i", str(BARCODE), "-t", "3", "-vf", "transpose=1", "-c:v", "libx264",
                "-preset", "veryfast", "-crf", "12", "-g", "30", "-pix_fmt", "yuv420p",
                "-video_track_timescale", "600"], transposed)
        ffmpeg(["-display_rotation", "90", "-i", str(transposed), "-c", "copy"], ROTATED)


def person_fixtures():
    """`push_1080.mov` and `screen_4k.mov`, `cutout_spike.fixtures()`'s."""
    if not (PUSH.exists() and SCREEN.exists()):
        cutout_spike.fixtures({})
    return PUSH, SCREEN


def run_probe(args):
    if PROBE is None:
        raise RuntimeError("the probe was not built")
    run = subprocess.run([str(PROBE), *args], capture_output=True, text=True, timeout=1200)
    lines = [line for line in run.stdout.splitlines() if line.strip()]
    if run.returncode != 0 or not lines:
        raise RuntimeError(f"co2a-probe {args[0]} exited {run.returncode}: {run.stderr[-400:]}")
    return json.loads(lines[-1])


def source_id(path, duration):
    stat = Path(path).stat()
    return {"duration": duration, "modified": round(stat.st_mtime), "size": stat.st_size}


def install_pack(package, media, path, duration, rate="every", kind="barcode",
                 coverage=None, marker=None, frames=FRAMES):
    """A canned `masks` pack and marker for `media` (CJ-26): the probe's `pack` mode writes
    `cache/analysis/masks/<media>/masks.pack`; the marker carries `canned: true`, the file's
    identity and `coverage` (the whole file by default), or is `marker` as given."""
    folder = package / "cache/analysis/masks"
    pack_dir = folder / str(media)
    pack_dir.mkdir(parents=True, exist_ok=True)
    spec = WORK / f"pack-{package.stem}-{media}.json"
    spec.write_text(json.dumps({"out": str(pack_dir / "masks.pack"), "frames": frames,
                                "rate": rate, "kind": kind}))
    answer = run_probe(["pack", str(spec)])
    if not answer.get("ok"):
        raise RuntimeError(f"the canned pack was not written: {answer}")
    body = marker if marker is not None else {
        "canned": True, "coverage": coverage or [[0, frames - 1]], "files": ["masks.pack"],
        "source": source_id(path, duration)}
    (folder / f"{media}.json").write_text(json.dumps(body, sort_keys=True))
    return answer["analysed"]


def read_pack(path):
    """A `masks.pack`'s frame and mask tables (spec §11 CO-10), parsed here: (frames as
    (pts, index, slot), masks as (pts, found), width, height)."""
    data = Path(path).read_bytes()
    foot = len(data) - 40
    if data[foot:foot + 4] != b"FJMP":
        raise RuntimeError(f"{path} is not a mask pack")
    _, width, height, nframes, nmasks, tables = struct.unpack_from("<IIIIIQ", data, foot + 4)
    frames = [struct.unpack_from("<qiI", data, tables + 16 * i) for i in range(nframes)]
    base = tables + 16 * nframes
    masks = [(struct.unpack_from("<q", data, base + 24 * i)[0], data[base + 24 * i + 20] != 0)
             for i in range(nmasks)]
    return frames, masks, width, height


def decode_png(path):
    """`path` as raw RGBA bytes (ffmpeg); None when it does not decode."""
    run = subprocess.run([FFMPEG, "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt",
                          "rgba", "-"], capture_output=True, timeout=120,
                         env=bounded.child_env())
    return run.stdout if run.returncode == 0 and run.stdout else None


def movie_frames(path, width=W, height=H):
    """Every frame of `path` as raw RGBA, streamed from ffmpeg."""
    size = width * height * 4
    child = subprocess.Popen([FFMPEG, "-v", "error", "-i", str(path), "-f", "rawvideo",
                              "-pix_fmt", "rgba", "-"], stdout=subprocess.PIPE,
                             env=bounded.child_env())
    try:
        while True:
            chunk = child.stdout.read(size)
            if len(chunk) < size:
                break
            yield chunk
    finally:
        child.stdout.close()
        child.wait(timeout=60)


def frame_md5s(path):
    run = subprocess.run([FFMPEG, "-v", "error", "-i", str(path), "-f", "framemd5", "-"],
                         capture_output=True, text=True, timeout=300, env=bounded.child_env())
    return [line.split(",")[-1].strip() for line in run.stdout.splitlines()
            if line and not line.startswith("#")]


def code(frame, channel, band_y, width=W, height=H):
    """CO-S2's bar code read back (`BarCode.read`): 22 block patches across the frame at
    `band_y`, block 0 white and block 1 black the references, blocks 2…21 the 20 bits.
    `channel` 3 is alpha; else the mean of R, G and B."""
    blocks, r = 22, max(1, min(width // 22 // 4, height // 40))
    cy = int(band_y * height)

    def level(x, y):
        at = (y * width + x) * 4
        if channel == 3:
            return frame[at + 3]
        return (frame[at] + frame[at + 1] + frame[at + 2]) / 3

    def patch(i):
        cx = int((i + 0.5) * width / blocks)
        values = [level(x, y) for y in range(max(0, cy - r), min(height - 1, cy + r) + 1)
                  for x in range(max(0, cx - r), min(width - 1, cx + r) + 1)]
        return sum(values) / len(values)

    white, black = patch(0), patch(1)
    if white - black < 64:
        return None
    threshold = (white + black) / 2
    value = 0
    for i in range(2, blocks):
        value = (value << 1) | (1 if patch(i) > threshold else 0)
    return value


def alpha_at(frame, x, y, width=W):
    return frame[(y * width + x) * 4 + 3]


def expected(picture, analysed, reversed_clip):
    reverse = (FRAMES, deciders.ends(range(FRAMES), FRAMES)) if reversed_clip else None
    return deciders.expected_mask(picture, analysed, reverse=reverse)


class Drawn(Doc):
    """A 640 × 360, 30 fps project on a transparent canvas (CO2a2's rows)."""

    def __init__(self, client, name, background=(0, 0, 0, 0)):
        path = WORK / f"{name}.framejob"
        if path.exists():
            shutil.rmtree(path)
        client.call("new_project", path=str(path))
        super().__init__(client, path)
        self.call("set_canvas", width=W, height=H, fps=[30, 1], background=list(background))
        self.call("save_project")

    def media(self, fixture, tag):
        copy = WORK / "media" / f"{tag}{fixture.suffix}"
        copy.parent.mkdir(parents=True, exist_ok=True)
        if not copy.exists():
            shutil.copyfile(fixture, copy)
        media = self.call("import_media", path=str(copy))["media"]
        duration = next(m for m in self.project()["media"] if m["id"] == media)["duration"]
        return media, copy, duration

    def clip(self, media, scale, cutout=True):
        tracks = self.project()["tracks"]
        if not tracks:
            self.call("add_track")
            tracks = self.project()["tracks"]
        before = {c["id"] for c in self.project()["clips"]}
        self.call("add_clip", track=tracks[0]["id"], media=media, at=0)
        clip = next(c["id"] for c in self.project()["clips"] if c["id"] not in before)
        patch = {"scale": scale}
        if cutout:
            patch["cutout"] = {}
        self.call("set_video", clips=[clip], patch=patch)
        return clip

    def render(self, t, tag):
        out = WORK / f"{self.path.stem}-{tag}-{t}.png"
        if out.exists():
            out.unlink()
        self.call("render_frame", t=t, path=str(out))
        return (out.read_bytes(), decode_png(out)) if out.exists() else (None, None)

    def masks(self, media, **window):
        for _ in range(60):
            try:
                return self.call("get_media_analysis", media=media, kind="masks", **window)
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        raise RuntimeError("the masks analysis did not finish in 60 calls")

    def wait_reverse(self, media):
        folder = self.path / "cache" / "reversed"
        deadline = time.monotonic() + REVERSE_BOUND
        while time.monotonic() < deadline:
            files = sorted(folder.glob(f"{media}-*.mov")) if folder.is_dir() else []
            partial = folder.is_dir() and any(folder.glob(f"{media}-*.partial"))
            if files and not partial:
                try:
                    self.call("snapshot_ui", window="sheet",
                              path=str(WORK / f"{self.path.stem}-sheet.png"))
                except mcp.ToolError as error:
                    if "no sheet attached" in str(error):
                        return None
            time.sleep(0.25)
        try:
            self.call("cancel_sheet")
        except mcp.ToolError:
            pass
        return f"the reverse did not finish within {REVERSE_BOUND} s"


# ---- D1, D11, D16: the ten cases exported ------------------------------------------

def d1_project(barcode, outgoing):
    """The ten cases on one track, a gap between each (spec §11 CO-29). Each bar-code clip
    is 1920 × 1080 at scale 1/3, filling the 640 × 360 canvas, with a cutout."""
    cut = {"subject": "person", "quality": "standard", "background": "remove", "edge": 0.0,
           "feather": 0.0}

    def bar(cid, start, duration, source_in, track=3, **extra):
        return {"id": cid, "track": track, "start": start, "duration": duration,
                "source": {"kind": "media", "media": 1, "in": source_in},
                "video": {"scale": 1 / 3, "cutout": cut}, **extra}

    fps30 = [30, 1]
    return {
        "version": format_version(),
        "canvas": {"width": W, "height": H, "fps": fps30, "background": [0, 0, 0, 0]},
        "media": [
            {"id": 1, "path": str(barcode), "kind": "video", "duration": FRAMES * FRAME,
             "width": 1920, "height": 1080, "fps": fps30, "has_video": True, "has_audio": False},
            {"id": 2, "path": str(outgoing), "kind": "video", "duration": 10 * SEC,
             "width": 640, "height": 360, "fps": fps30, "has_video": True, "has_audio": False},
        ],
        "tracks": [{"id": 3, "name": "Track 1"}],
        "clips": [
            bar(11, 0, 2 * SEC, 2 * SEC),
            bar(12, 3 * SEC, 2 * SEC, 0, speed=0.5),
            bar(13, 6 * SEC, 2 * SEC, SEC, speed=2.0),
            bar(14, 9 * SEC, 2 * SEC, SEC // 2, speed=1.37),
            bar(15, 12 * SEC, 3 * SEC, 0),
            bar(16, 16 * SEC, 2 * SEC, 3 * SEC),
            bar(17, 20 * SEC, 2 * SEC, SEC),
            bar(18, 23 * SEC, 2 * SEC, 4 * SEC),
            {"id": 19, "track": 3, "start": 26 * SEC, "duration": 2 * SEC,
             "source": {"kind": "nest", "project": 50}},
            {"id": 20, "track": 3, "start": 29 * SEC, "duration": 2 * SEC,
             "source": {"kind": "media", "media": 2, "in": 0}},
            bar(21, 30 * SEC, 2 * SEC, 7 * SEC,
                transition_in={"kind": "cross_dissolve", "curve": "linear", "audio": False}),
        ],
        "nests": [{"id": 50, "name": "Nest", "width": W, "height": H,
                   "tracks": [{"id": 53, "name": "Inner"}],
                   "clips": [bar(51, 0, 2 * SEC, 6 * SEC, track=53)]}],
        "next_id": 100,
    }


CASES = {11: "trim", 12: "x0.5", 13: "x2", 14: "x1.37", 15: "ramp", 16: "freeze",
         17: "reverse", 18: "split", 19: "nest", 21: "dissolve"}


def d1_doc(client, tag, barcode, rate):
    """The D1 project opened, its edits made (the ramp, the freeze, the reverse, the split),
    its canned pack installed: (doc, case of each clip id, analysed frames)."""
    made = Drawn(client, f"d1-{tag}")
    close(client, made.path)
    (made.path / "project.json").write_text(json.dumps(
        d1_project(barcode, movie()), indent=1))
    client.call("open_project", path=str(made.path))
    doc = Drawn.__new__(Drawn)
    Doc.__init__(doc, client, made.path)
    cases = dict(CASES)

    def edit(case, tool, **arguments):
        before = {c["id"] for c in doc.project()["clips"]}
        doc.call(tool, **arguments)
        for c in doc.project()["clips"]:
            if c["id"] not in before:
                cases[c["id"]] = case

    edit("ramp", "add_speed_ramp", clip=15, shape="ramp_up", rate=2, curve="linear")
    edit("freeze", "freeze_frame", clip=16, at=17 * SEC, duration=SEC)
    doc.call("set_reversed", clip=17, reversed=True)
    at = next(c["start"] for c in doc.project()["clips"] if c["id"] == 18) + SEC
    edit("split", "split", clips=[18], at=at)
    why = doc.wait_reverse(1)
    if why:
        raise RuntimeError(why)
    analysed = install_pack(doc.path, 1, barcode, FRAMES * FRAME, rate=rate)
    return doc, cases, analysed


def d1(client):
    """D1 at every frame and at 15 a second; D11 (the freeze) and D16 (the reverse) are
    read from the same frames."""
    barcode = WORK / "media" / "barcode.mov"
    barcode.parent.mkdir(parents=True, exist_ok=True)
    if not barcode.exists():
        shutil.copyfile(BARCODE, barcode)
    for rate in ("every", "15"):
        doc, cases, analysed = d1_doc(client, rate, barcode, rate)
        try:
            want = deciders.analysed_frames(range(FRAMES), rate)
            check("D1", analysed == want, f"{rate}: the pack's analysed frames are CJ-23's "
                  f"({len(analysed)} of {FRAMES})")
            score_d1(doc, cases, analysed, rate)
        finally:
            close(client, doc.path)


def score_d1(doc, cases, analysed, rate):
    clips = doc.project()["clips"]
    spans = [(c["id"], c["start"], c["start"] + c["duration"]) for c in clips]
    movie_out = WORK / f"d1-{rate}.mov"
    if movie_out.exists():
        movie_out.unlink()
    doc.client.export_with({"project": str(doc.path), "preset": "prores_4444",
                            "path": str(movie_out)}, seconds=EXPORT_BOUND)
    outgoing = next(s for s in spans if s[0] == 20)
    incoming = next(s for s in spans if s[0] == 21)
    tallies = {}
    misses = {}
    weights = []
    for n, frame in enumerate(movie_frames(movie_out)):
        t = n * FRAME
        covering = [cid for cid, a, b in spans if a <= t < b]
        if not covering:
            continue
        if 20 in covering and 21 in covering:
            p = (t - incoming[1]) / (outgoing[2] - incoming[1])
            got = alpha_at(frame, W // 2, int(H * 0.15))
            weights.append((n, p, got, abs(got - round(255 * (1 - p))) <= 1))
            continue
        bars = [cid for cid in covering if cid != 20]
        if not bars:
            continue
        case = cases.get(bars[0], "?")
        picture, mask = code(frame, 0, 0.5), code(frame, 3, 0.85)
        ok = picture is not None and 0 <= picture < FRAMES and mask == expected(
            picture, analysed, case == "reverse")
        tallies.setdefault(case, [0, 0])
        tallies[case][0 if ok else 1] += 1
        if not ok:
            misses.setdefault(case, []).append((n, picture, mask))
    for case in ["trim", "x0.5", "x2", "x1.37", "ramp", "freeze", "reverse", "split", "nest",
                 "dissolve"]:
        good, bad = tallies.get(case, [0, 0])
        detail = (f"{rate}: {case}, {good} frames, each picture code's expected mask "
                  f"(deciders.expected_mask) read from the alpha"
                  + (f"; {bad} wrong, first (frame, picture, mask) {misses[case][:3]}"
                     if bad else ""))
        check("D1", good > 0 and bad == 0, detail)
        if case == "freeze":
            check("D11", good > 0 and bad == 0, detail)
        if case == "reverse":
            check("D16", good > 0 and bad == 0, detail)
    wrong = [w for w in weights if not w[3]]
    check("D1", len(weights) >= 25 and not wrong,
          f"{rate}: the dissolve's outgoing alpha where the incoming's mask is 0 is "
          f"round(255·(1 − p)) ±1 at {len(weights)} overlap frames"
          + (f"; wrong (frame, p, alpha) {[(n, round(p, 3), a) for n, p, a, _ in wrong[:4]]}"
             if wrong else ""))


# ---- D2, D4: real packs ---------------------------------------------------------------

def neighbourhood(mask, mw, mh, x, y, test):
    """Whether the 3 × 3 mask texels around canvas pixel (x, y)'s texel all pass `test`."""
    tx, ty = int((x + 0.5) / W * mw), int((y + 0.5) / H * mh)
    for j in range(ty - 1, ty + 2):
        for i in range(tx - 1, tx + 2):
            if not (0 <= i < mw and 0 <= j < mh) or not test(mask[j * mw + i]):
                return False
    return True


def d2(client):
    push, _ = person_fixtures()
    doc = Drawn(client, "d2", background=(0.2, 0.3, 0.4, 1))
    try:
        media, copy, duration = doc.media(push, "push")
        clip = doc.clip(media, 1 / 3)
        answer = doc.masks(media, **{"from": 0, "to": 2 * SEC})
        check("D2", answer.get("subject_found") is True,
              f"get_media_analysis over 0–2 s: subject_found {answer.get('subject_found')}, "
              f"{answer.get('frames')} frames, mask_size {answer.get('mask_size')}")
        frames, masks, mw, mh = read_pack(doc.path / f"cache/analysis/masks/{media}/masks.pack")
        for t in D2_TIMES:
            cut_png, cut = doc.render(t, "cut")
            doc.call("set_video", clips=[clip], patch={"opacity": 0.0})
            _, hidden = doc.render(t, "hidden")
            doc.call("set_video", clips=[clip], patch={"opacity": 1.0, "cutout": None})
            _, uncut = doc.render(t, "uncut")
            doc.call("set_video", clips=[clip], patch={"cutout": {}})
            shown = max(i for i, f in enumerate(frames) if f[0] <= t)
            raw = WORK / f"d2-mask-{t}.bin"
            run_probe(["mask", str(doc.path / f"cache/analysis/masks/{media}/masks.pack"),
                       str(frames[shown][2]), str(raw)])
            mask = raw.read_bytes()
            zero = one = zero_bad = one_bad = differs = 0
            for y in range(H):
                for x in range(W):
                    at = (y * W + x) * 4
                    if neighbourhood(mask, mw, mh, x, y, lambda v: v == 0):
                        zero += 1
                        zero_bad += cut[at:at + 4] != hidden[at:at + 4]
                        differs += uncut[at:at + 4] != hidden[at:at + 4]
                    elif neighbourhood(mask, mw, mh, x, y, lambda v: v >= SATURATED):
                        one += 1
                        one_bad += cut[at:at + 4] != uncut[at:at + 4]
            check("D2", zero > 1000 and one > 1000 and differs > 0 and not zero_bad
                  and not one_bad,
                  f"t {t}: {zero} pixels in an all-0 neighbourhood equal the clip hidden "
                  f"({zero_bad} differ; {differs} of them differ uncut), {one} in an all-"
                  f"≥{SATURATED} one equal the uncut frame ({one_bad} differ); the mask of pack "
                  f"frame "
                  f"{shown}, slot {frames[shown][2]}, {mw} × {mh}")
    finally:
        close(client, doc.path)


def d4(client):
    _, screen = person_fixtures()
    doc = Drawn(client, "d4", background=(0.2, 0.3, 0.4, 1))
    try:
        media, copy, duration = doc.media(screen, "screen")
        clip = doc.clip(media, 1 / 6)
        answer = doc.masks(media, **{"from": 0, "to": 2 * SEC})
        check("D4", answer.get("subject_found") is False and answer.get("frames", 0) > 0,
              f"get_media_analysis over 0–2 s: subject_found {answer.get('subject_found')}, "
              f"{answer.get('frames')} frames")
        cut = [doc.render(t, "cut")[0] for t in D4_TIMES]
        doc.call("set_video", clips=[clip], patch={"cutout": None})
        uncut = [doc.render(t, "uncut")[0] for t in D4_TIMES]
        same = [a is not None and a == b for a, b in zip(cut, uncut)]
        check("D4", all(same), f"no person found in the clip's window: the 3 frames with the "
              f"cutout equal the uncut ones byte for byte: {same}")
    finally:
        close(client, doc.path)


# ---- D3, D6, D7, D12: canned packs ----------------------------------------------------

def bar_doc(client, name, fixture=None, background=(0, 0, 0, 0)):
    doc = Drawn(client, name, background=background)
    media, copy, duration = doc.media(fixture or BARCODE, "rot" if fixture else "barcode")
    clip = doc.clip(media, 1 / 3)
    return doc, media, copy, duration, clip


def d3(client):
    doc, media, copy, duration, clip = bar_doc(client, "d3")
    try:
        t = 2 * SEC  # frame 60, outside coverage [200, 299]
        install_pack(doc.path, media, copy, duration, coverage=[[200, FRAMES - 1]])
        missed = doc.render(t, "coverage")[0]
        inside = doc.render(250 * FRAME, "inside")[1]
        drawn = inside is not None and code(inside, 3, 0.85) == 250
        stamped = {
            "coverage": [[0, FRAMES - 1]], "files": ["masks.pack"],
            "source": source_id(copy, duration),
            "stamp": {"source": source_id(copy, duration), "kind": "masks", "version": 1,
                      "parameters": "0" * 64, "osBuild": "0A0", "device": "cpu",
                      "reader": "raw"}}
        install_pack(doc.path, media, copy, duration, marker=stamped)
        other = doc.render(t, "stamp")[0]
        doc.call("set_video", clips=[clip], patch={"cutout": None})
        off = doc.render(t, "off")[0]
        check("D3", drawn, "control: frame 250, inside the coverage, draws its mask (alpha "
              "code 250)")
        check("D3", missed is not None and missed == off,
              "a pack whose coverage [200, 299] misses frame 60 draws byte-identical to cutout "
              "off")
        check("D3", other is not None and other == off,
              "a marker of another stamp (osBuild, device, parameters) draws byte-identical to "
              "cutout off")
    finally:
        close(client, doc.path)


def d6(client):
    doc, media, copy, duration, clip = bar_doc(client, "d6")
    try:
        install_pack(doc.path, media, copy, duration)
        t = 3 * SEC
        _, plain = doc.render(t, "plain")
        doc.call("set_video", clips=[clip], patch={"shadow": {
            "color": [0, 0, 0, 1], "opacity": 1.0, "blur": 0.0, "angle": 270.0,
            "distance": 3.0 * SHADOW_SHIFT}})
        _, shadowed = doc.render(t, "shadow")
        worst = checked = 0
        for y in range(SHADOW_SHIFT, H):
            for x in range(W):
                if alpha_at(plain, x, y) != 0:
                    continue
                checked += 1
                worst = max(worst, abs(alpha_at(shadowed, x, y)
                                       - alpha_at(plain, x, y - SHADOW_SHIFT)))
        check("D6", checked > 10000 and worst <= 1,
              f"a blur-0 shadow {SHADOW_SHIFT} px down: where the layer's alpha is 0, the "
              f"shadow's alpha equals the layer's {SHADOW_SHIFT} px above, worst {worst}/255 "
              f"over {checked} pixels")
    finally:
        close(client, doc.path)


def d7(client):
    doc, media, copy, duration, clip = bar_doc(client, "d7")
    try:
        install_pack(doc.path, media, copy, duration)
        t = 3 * SEC
        _, sdr = doc.render(t, "sdr")
        doc.call("set_canvas", output="hlg")
        _, hlg = doc.render(t, "hlg")
        worst = max(abs(sdr[i] - hlg[i]) for i in range(3, len(sdr), 4))
        partial = sum(1 for i in range(3, len(sdr), 4) if 0 < sdr[i] < 255)
        check("D7", worst <= 1 and code(sdr, 3, 0.85) == 90 and partial > 0,
              f"the HLG project's coverage against the SDR project's: worst {worst}/255 over "
              f"{len(sdr) // 4} pixels ({partial} partial); the alpha code 90")
    finally:
        close(client, doc.path)


def d12(client):
    barcode_fixtures()
    doc, media, copy, duration, clip = bar_doc(client, "d12", fixture=ROTATED)
    try:
        install_pack(doc.path, media, copy, duration, frames=90)
        for k in (15, 40, 75):
            _, frame = doc.render(k * FRAME, "rot")
            picture = code(frame, 0, 0.5) if frame else None
            mask = code(frame, 3, 0.85) if frame else None
            check("D12", picture == k and mask == k,
                  f"the 90°-tagged clip at frame {k}: picture code {picture}, alpha code "
                  f"{mask} (both {k}: registered and upright)")
    finally:
        close(client, doc.path)


# ---- D15: the base app ------------------------------------------------------------------

def d15_fixture():
    return {
        "version": format_version(),
        "canvas": {"width": W, "height": H, "fps": [30, 1]},
        "media": [{"id": 1, "path": str(movie()), "kind": "video", "duration": 10 * SEC,
                   "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
                   "has_audio": False}],
        "tracks": [{"id": 2, "name": "Track 1"}],
        "clips": [{"id": 3, "track": 2, "start": 0, "duration": 2 * SEC,
                   "source": {"kind": "media", "media": 1, "in": 0},
                   "video": {"corner_radius": 24.0, "shadow": {
                       "color": [0, 0, 0, 1], "opacity": 0.6, "blur": 8.0, "angle": 315.0,
                       "distance": 10.0}},
                   "actions": [{"id": 4, "start": SEC // 2, "duration": SEC,
                                "curve": "linear",
                                "end": {"video": {"scale": 0.7, "x": 60.0}}}]}],
        "next_id": 5,
    }


def d15_outputs(client, tag):
    made = Drawn(client, f"d15-{tag}", background=(0, 0, 0, 1))
    close(client, made.path)
    (made.path / "project.json").write_text(json.dumps(d15_fixture(), indent=1))
    client.call("open_project", path=str(made.path))
    doc = Drawn.__new__(Drawn)
    Doc.__init__(doc, client, made.path)
    try:
        pngs = [doc.render(t, tag)[0] for t in D15_TIMES]
        out = WORK / f"d15-{tag}.mov"
        if out.exists():
            out.unlink()
        client.export_with({"project": str(doc.path), "preset": "prores_4444",
                            "path": str(out)}, seconds=EXPORT_BOUND)
        return pngs, frame_md5s(out)
    finally:
        close(client, doc.path)


def base_app():
    """The base's app (`BASE`): the tree copied, its `app/` replaced by `git archive BASE
    app`, built by `tree_copy.build_app` (the proof's configuration)."""
    made, reason = tree_copy.make_copy(str(WORK.parent / "co2a-base"))
    if made is None:
        return None, reason
    shutil.rmtree(Path(made) / "app")
    archive = subprocess.run(["git", "-C", str(ROOT), "archive", BASE, "app"],
                             capture_output=True, timeout=120)
    if archive.returncode != 0:
        return None, f"git archive {BASE} app: {archive.stderr[-300:]}"
    untar = subprocess.run(["tar", "-x", "-C", made], input=archive.stdout,
                           capture_output=True, timeout=120)
    if untar.returncode != 0:
        return None, f"tar: {untar.stderr[-300:]}"
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def d15(ours):
    """`ours` the outputs of this build; the base's from its own instance."""
    binary, why = base_app()
    if binary is None:
        check("D15", False, f"the base app did not build: {why}")
        return
    log = WORK / "base.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            check("D15", False, "the base app did not listen")
            return
        theirs = d15_outputs(launched.client, "base")
    finally:
        launched.stop()
    same = [a is not None and a == b for a, b in zip(ours[0], theirs[0])]
    check("D15", len(same) == 3 and all(same),
          f"3 render_frames of a cutout-less project, PNG bytes against the base {BASE[:8]}'s "
          f"app: {same}")
    check("D15", ours[1] and ours[1] == theirs[1],
          f"a 2 s prores_4444 export: {len(ours[1])} frames' md5 against the base's "
          f"{len(theirs[1])}, {'equal' if ours[1] == theirs[1] else 'different'}")


def launch_rows(binary, arguments, log, bodies):
    """`bodies` in one instance launched with `arguments`; Z1 over its log."""
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    ours = None
    try:
        if launched.client is None:
            for names, _ in bodies:
                for row in names & selected:
                    check(row, False, "the app did not listen")
            return None
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
        if "D15" in selected and any("D15" in names for names, _ in bodies):
            try:
                ours = d15_outputs(launched.client, "ours")
            except Exception as error:  # noqa: BLE001
                check("D15", False, f"this build's outputs: {type(error).__name__}: {error}")
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace")
                     if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return ours


def app_rows(binary):
    ours = None
    try:
        if selected & {"D1", "D11", "D16", "D12"}:
            barcode_fixtures()
        if selected & {"D3", "D6", "D7"} and not BARCODE.exists():
            barcode_fixtures()
    except Exception as error:  # noqa: BLE001 — the fixture's failure is the rows'
        for name in selected & {"D1", "D11", "D16", "D12", "D3", "D6", "D7"}:
            check(name, False, f"the bar-code fixtures: {error}")
    canned = [({"D8"}, d8), ({"D10"}, d10), ({"D13", "D14"}, d13_d14),
              ({"D1", "D11", "D16"}, d1), ({"D3"}, d3), ({"D6"}, d6), ({"D7"}, d7),
              ({"D12"}, d12), ({"D15"}, lambda client: None)]
    real = [({"D2"}, d2), ({"D4"}, d4)]
    if any(names & selected for names, _ in canned):
        ours = launch_rows(binary, CANNED + HELD, WORK / "instance.log", canned)
    if any(names & selected for names, _ in real):
        launch_rows(binary, [], WORK / "instance-real.log", real)
    if ours is not None:
        try:
            d15(ours)
        except Exception as error:  # noqa: BLE001
            check("D15", False, f"{type(error).__name__}: {error}")


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(APP_ROWS):
            selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else None
    if args.mutant:
        print(f"CO2a2 — the {args.mutant} MUTANT ({', '.join(MUTANTS[args.mutant][0])} must "
              f"FAIL, {proof_app.config()} build)", flush=True)
        binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CO2a1 and CO2a2 — the cutout in the model and drawn ({proof_app.config()} "
              "build)", flush=True)
    probe_rows(force=bool(selected & set(DRAWN)))
    if selected & set(APP_ROWS):
        binary = binary or proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed and results else 1


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "co2a-mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


if __name__ == "__main__":
    sys.exit(main())
