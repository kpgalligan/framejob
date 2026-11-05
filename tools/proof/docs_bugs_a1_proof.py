#!/usr/bin/env python3
"""Docs-bugs batch a1 (#464, #465, #507, #511; spec §11 #465): timeline and clipboard.

    python3 tools/proof/docs_bugs_a1_proof.py [--only N1,D5,…] [--tree PATH] [--expect-red]
                                              [--mutant NAME]

The projects are made by the app under test over MCP (`proof_app.binary()`, `RC_PROOF_APP`) in
`work/docs_bugs_a1/`, saved and closed. The `app` rows then run over MCP; every other row runs
through `docs_bugs_a1_probe.swift`, the app's own sources on those saved packages, on a private
pasteboard (it cannot write the owner's clipboard; row PB reads the real board's change count at
both ends), and with NSEvents handed straight to the timeline's content view.

`--tree PATH` builds the probe from `PATH/app/Sources`, its bridging header and
`PATH/core/target/release/libframejob_core.a`. `--expect-red` is the run against the base: it
exits 0 only when every row not marked CONTROL fails and every CONTROL passes, and prints a row
that does neither.

    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_a1_proof.py \
        --tree <base tree> --expect-red

Red on the base unless marked CONTROL:
- #464. N1 copy, paste a nest clip: lands on a fresh nest id, payload keys clips, media, nests, no
  alert, undo "Paste". N2 a nest clip and a plain clip: both land. N3 cut then paste: lands; undo
  "Paste", then "Cut". N4 into another project: the clip, its nest and the inner media rows arrive.
  N5 a nest inside a nest: both levels, fresh ids. N6 two clips showing one nest: one nest in the
  payload, the pasted pair share one new nest. N8 inside an open nest. N9 (CONTROL) a plain clip's
  payload keys are exactly clips, media.
- PB (CONTROL) the real general board's change count, the same at start and end.
- #465. D1 ⌥-drag the first of a run to an empty track: 3 clips, originals in place, undo
  "Duplicate Clips". D2 the same to empty time. D3 (CONTROL) the last of a run. D4 (CONTROL) a plain
  drag stays "Move Clips". D5 ⌥-drag the last of a run straight onto an occupied spot: no copy, no
  undo step, the refusal flash up right after mouse-up. D6 the first of a run past the top lane: a
  new track holds the copy, one undo step. D7 (app) `duplicate {delta, track}` on the first of a
  run. D8 (CONTROL, app) `duplicate {clips}` alone still refuses, in the same sentence.
- #465, linked and two-lane; Detach Audio puts the sound at index 0, the picture at 1, a free lane
  at 2. D9 ⌥-drag the picture up a row into free time: its copy on index 2 at the drop, the sound's
  copy on index 0 at the same delta, the copies linked to each other, one undo step. D10 past the
  top lane: a new track holds the picture's copy, the sound's on index 0, one undo step. D11 the
  picture straight up at delta 0: no copy, track count unchanged, no undo step, the flash. D12 two
  unlinked clips on two lanes ⌥-dragged past the top lane: track count unchanged, no copy, no undo
  step, the flash. D13 the same plain-dragged: track count unchanged, no undo step, the flash. D14
  (CONTROL) those two, with free time after them, ⌥-dragged past the bottom lane: one new track,
  copies landed, one undo step.
- #507. M1 a row squarely on a clip: performDragOperation false, strip sentence, no change, no
  undo. M2 (CONTROL) below the lanes: false. M3 (CONTROL) free time: true, landed. M4 (CONTROL) a
  small overlap: true, landed with a cross_dissolve. M6 (CONTROL) a canvas drop: true, on a new
  track.
- #511 (app). F1 a 5 s image's tile reaches the clip's end at the default zoom. F2 below 17 pt/s
  the tile still draws. F3 a still frozen at 2 s: one colour across its 8 s. F4 a still frozen at
  8 s: no plain stretch. F5 (CONTROL) a media clip's strip still changes each second.
- Z1 (CONTROL) `grep "Frame Job: "` on the log prints nothing.

`--mutant NAME` breaks one decision in a `tree_copy.py` copy and runs only the rows it must fail:
CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits 2. A probe row's
mutant builds the probe from the copy; an `app` row's builds the copy's app; a core mutant builds
the core in the copy, in a real folder with its own target. `nests-one-level` N5,
`inner-media-dropped` N4, `nests-in-depth-form` N1, `closure-anchor` D9, `partner-shifts` D9 and
`core/tests/duplicate_destination.rs`, `no-duplicating-flash` D5, `tick-not-whole` D12,
`new-track-returns-early` D12, `drop-always-true` M1, `still-walks` F3, `image-walks` F1. An
instrument that cannot run is a scored failure, never an exit.
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import mcp  # noqa: E402
import proof_app  # noqa: E402
import proof_defaults  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs_bugs_a1"
FIXTURES = WORK / "fixtures"
MEDIA = ROOT / "tools/proof/media"
PROBE = "docs_bugs_a1_probe"
FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
FFPROBE = shutil.which("ffprobe") or "ffprobe"
SEC = 600_000
PROBE_BOUND = 240
BUILD_BOUND = 1500
CALL_BOUND = 300
PLAIN = (96, 67, 133)        # the clip body with no tile under its tint
LANE = (30, 30, 30)
TOLERANCE = 16
LANE_Y, LANE_X = 110, 134    # points: inside the first lane's strip, just right of the header

PROBE_ROWS = ["N1", "N2", "N3", "N4", "N5", "N6", "N8", "N9", "PB", "D1", "D2", "D3", "D4", "D5",
              "D6", "D9", "D10", "D11", "D12", "D13", "D14", "M1", "M2", "M3", "M4", "M6"]
APP_ROWS = ["D7", "D8", "F1", "F2", "F3", "F4", "F5"]
ROWS = PROBE_ROWS + APP_ROWS + ["Z1"]
CONTROLS = {"N9", "PB", "D3", "D4", "D8", "D14", "M2", "M3", "M4", "M6", "F5", "Z1"}
GROUP = {"N": "464", "D": "465", "M": "507"}

CLIPBOARD = "app/Sources/EditorViewController+Clipboard.swift"
TIMELINE = "app/Sources/TimelineView.swift"
DRAWING = "app/Sources/TimelineClipDrawing.swift"
EDIT_CLIP = "core/src/edit_clip.rs"
MUTANTS = {
    "nests-one-level": (["N5"], [(
        CLIPBOARD, "            queue += shown(nest[\"clips\"] as? [[String: Any]] ?? [])\n", "")]),
    "inner-media-dropped": (["N4"], [(
        CLIPBOARD,
        "            for clip in nest[\"clips\"] as? [[String: Any]] ?? [] {\n"
        "                wanted.formUnion(Self.payloadMediaIDs(clip))\n",
        "            for clip in nest[\"clips\"] as? [[String: Any]] ?? [] {\n"
        "                _ = clip\n")]),
    "nests-in-depth-form": (["N1"], [(
        CLIPBOARD, "            found.append(nest)\n",
        "            var flat = nest\n"
        "            flat[\"clips\"] = (nest[\"clips\"] as? [[String: Any]] ?? []).map {\n"
        "                var clip = $0\n"
        "                clip[\"track\"] = 0\n"
        "                return clip\n"
        "            }\n"
        "            found.append(flat)\n")]),
    "closure-anchor": (["D9"], [(
        EDIT_CLIP,
        "        let index_delta = self.track_index_delta(&selection, track)?;\n\n"
        "        let mut next = self.clone();\n",
        "        let whole: Vec<&Clip> = closure.iter().collect();\n"
        "        let index_delta = self.track_index_delta(&whole, track)?;\n\n"
        "        let mut next = self.clone();\n")]),
    "partner-shifts": (["D9"], [(
        EDIT_CLIP,
        "            if selection.iter().any(|c| c.id == clip.id) {\n"
        "                match self.landing_track(clip, index_delta)? {\n"
        "                    Ok(landed) => copy.track = landed,\n",
        "            if !selection.is_empty() {\n"
        "                match self.landing_track(clip, index_delta)? {\n"
        "                    Ok(landed) => copy.track = landed,\n")]),
    "no-duplicating-flash": (["D5"], [(
        TIMELINE, "        guard !landed else { return }\n",
        "        guard !landed, !session.duplicating else { return }\n")]),
    "tick-not-whole": (["D12"], [(
        "app/Sources/EditorViewController+SpeedAudio.swift",
        "            for op in ops where (try? trial.require(op)) != nil { return }\n",
        "            for op in ops { _ = try? trial.require(op) }\n")]),
    "new-track-returns-early": (["D12"], [(
        TIMELINE,
        "        guard session.didMove, !session.needsNewTrack || created != nil, let base = dragBase,\n",
        "        guard session.didMove, !session.needsNewTrack, let base = dragBase,\n")]),
    "drop-always-true": (["M1"], [(
        "app/Sources/MediaPaneCommands.swift",
        "        binding.apply(name, ops)\n        return landed\n",
        "        binding.apply(name, ops)\n        return landed || true\n")]),
    "still-walks": (["F3"], [(
        DRAWING,
        "        case .still(_, let at):\n            return Int(max(at, 0) / ReelTime.perSecond)\n",
        "")]),
    "image-walks": (["F1"], [(DRAWING, "        case .image:\n            return 0\n", "")]),
}
CORE_TEST = {"partner-shifts": "duplicate_destination"}   # the core test the mutant must fail too

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}  {detail}"[:400], flush=True)


# ---- the fixtures -------------------------------------------------------------------

def state(c, p):
    return c.call_with("get_project", {"project": p})["project"]


def start(c, name):
    p = str(FIXTURES / f"{name}.framejob")
    c.call_with("new_project", {"path": p})
    return p, state(c, p)["tracks"][-1]["id"]


def imported(c, p, path):
    return c.call_with("import_media", {"project": p, "path": str(path)})["media"]


def add(c, p, track, media, at):
    before = {x["id"] for x in state(c, p)["clips"]}
    c.call_with("add_clip", {"project": p, "track": track, "media": media, "at": at})
    return next(x["id"] for x in state(c, p)["clips"] if x["id"] not in before)


def nest_clip_of(c, p):
    return next(x["id"] for x in state(c, p)["clips"] if x["source"]["kind"] == "nest")


def make_fixtures(c):
    shutil.rmtree(FIXTURES, ignore_errors=True)
    FIXTURES.mkdir(parents=True)
    ids = {}

    # nest: A and B nested at 0–20, C after them, plain. other: the paste target.
    p, t = start(c, "nest")
    a, b, m = (imported(c, p, MEDIA / f"{n}.mov") for n in "ABC")
    ca, cb, cc = add(c, p, t, a, 0), add(c, p, t, b, 10 * SEC), add(c, p, t, m, 20 * SEC)
    c.call_with("nest", {"project": p, "clips": [ca, cb], "name": "Pair"})
    ids["nest"] = {"nest_clip": nest_clip_of(c, p), "plain_clip": cc}
    c.call_with("save_project", {"project": p})
    p2, _ = start(c, "other")
    c.call_with("save_project", {"project": p2})

    # deep: Pair inside Outer, with C beside it.
    p3, t = start(c, "deep")
    a, b, m = (imported(c, p3, MEDIA / f"{n}.mov") for n in "ABC")
    ca, cb, cc = add(c, p3, t, a, 0), add(c, p3, t, b, 10 * SEC), add(c, p3, t, m, 20 * SEC)
    c.call_with("nest", {"project": p3, "clips": [ca, cb], "name": "Pair"})
    inner = nest_clip_of(c, p3)
    c.call_with("nest", {"project": p3, "clips": [inner, cc], "name": "Outer"})
    ids["deep"] = {"outer_clip": nest_clip_of(c, p3), "inner_clip": inner}
    c.call_with("save_project", {"project": p3})

    # shared: a nest clip and its duplicate, two clips showing one nest.
    p4, t = start(c, "shared")
    a, b = (imported(c, p4, MEDIA / f"{n}.mov") for n in "AB")
    ca, cb = add(c, p4, t, a, 0), add(c, p4, t, b, 10 * SEC)
    c.call_with("nest", {"project": p4, "clips": [ca, cb], "name": "Pair"})
    first = nest_clip_of(c, p4)
    c.call_with("duplicate", {"project": p4, "clips": [first]})
    shown = [x["id"] for x in state(c, p4)["clips"] if x["source"]["kind"] == "nest"]
    ids["shared"] = {"first": shown[0], "second": shown[1]}
    c.call_with("save_project", {"project": p4})

    # drag: A split at 5 s, so two clips back to back, an empty track above.
    p5, t = start(c, "drag")
    a = imported(c, p5, MEDIA / "A.mov")
    whole = add(c, p5, t, a, 0)
    c.call_with("split", {"project": p5, "clips": [whole], "at": 5 * SEC})
    c.call_with("add_track", {"project": p5, "index": 1})
    s = state(c, p5)
    run = sorted(s["clips"], key=lambda x: x["start"])
    ids["drag"] = {"first": run[0]["id"], "second": run[1]["id"], "track": t,
                   "empty_track": next(x["id"] for x in s["tracks"] if x["id"] != t)}
    c.call_with("save_project", {"project": p5})

    # link: AV.mov detached, the sound behind the picture, a free lane in front.
    p6, t = start(c, "link")
    av = imported(c, p6, MEDIA / "AV.mov")
    whole = add(c, p6, t, av, 0)
    c.call_with("detach_audio", {"project": p6, "clip": whole})
    s = state(c, p6)
    c.call_with("add_track", {"project": p6, "index": len(s["tracks"])})
    s = state(c, p6)
    order = [x["id"] for x in s["tracks"]]
    picture = next(x for x in s["clips"] if x["id"] == whole)
    sound = next(x for x in s["clips"] if x["id"] != whole)
    ids["link"] = {"picture": whole, "sound": sound["id"],
                   "picture_index": order.index(picture["track"]),
                   "sound_index": order.index(sound["track"]), "tracks": len(order)}
    c.call_with("save_project", {"project": p6})

    # lanes: two unlinked clips, one a lane in front of the other, over the same time.
    p7, t = start(c, "lanes")
    c.call_with("add_track", {"project": p7, "index": 1})
    order = [x["id"] for x in state(c, p7)["tracks"]]
    a, b = (imported(c, p7, MEDIA / f"{n}.mov") for n in "AB")
    ids["lanes"] = {"back": add(c, p7, order[0], a, 0), "front": add(c, p7, order[1], b, 0)}
    c.call_with("save_project", {"project": p7})

    # drop: A on the track, B in the Media tab only.
    p8, t = start(c, "drop")
    a, b = (imported(c, p8, MEDIA / f"{n}.mov") for n in "AB")
    ids["drop"] = {"clip": add(c, p8, t, a, 0), "free_media": b, "track": t}
    c.call_with("save_project", {"project": p8})

    for path in (p, p2, p3, p4, p5, p6, p7, p8):
        c.call_with("close_project", {"project": path})
    (FIXTURES / "ids.json").write_text(json.dumps(ids, indent=1))
    return ids


# ---- the app rows: #465's tool ------------------------------------------------------

def rows_tool(c, ids):
    p = str(FIXTURES / "drag.framejob")
    d = ids["drag"]
    c.call_with("open_project", {"path": p})
    try:
        before = state(c, p)
        if "D8" in selected:
            try:
                answer = c.call_with("duplicate", {"project": p, "clips": [d["first"]]})
                check("D8", False, f"answered {json.dumps(answer)[:160]}")
            except mcp.ToolError as error:
                said = str(error)
                check("D8", re.search(r"would overlap by 3000000 ticks, more than half of the "
                                      r"shorter clip \(1500000 ticks\)", said), said[:160])
            check("D8", state(c, p)["clips"] == before["clips"], "the project did not change")
        if "D7" in selected:
            try:
                c.call_with("duplicate", {"project": p, "clips": [d["first"]], "delta": 12 * SEC,
                                          "track": d["empty_track"]})
                made = [x for x in state(c, p)["clips"]
                        if x["id"] not in {y["id"] for y in before["clips"]}]
                check("D7", len(made) == 1 and made[0]["start"] == 12 * SEC
                      and made[0]["track"] == d["empty_track"],
                      f"copies {[(x['id'], x['track'], x['start'] / SEC) for x in made]}")
                check("D7", all(x in state(c, p)["clips"] for x in before["clips"]),
                      "the originals are in place")
            except mcp.ToolError as error:
                check("D7", False, str(error)[:200])
    finally:
        c.call_with("close_project", {"project": p, "discard": True})


# ---- the app rows: #511 -------------------------------------------------------------

class Png:
    """A PNG's pixels through ffmpeg (this Python has no PIL)."""

    def __init__(self, path):
        info = json.loads(subprocess.run(
            [FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries",
             "stream=width,height", "-of", "json", str(path)], capture_output=True,
            check=True).stdout)
        self.width = info["streams"][0]["width"]
        self.height = info["streams"][0]["height"]
        self.raw = subprocess.run(
            [FFMPEG, "-v", "error", "-i", str(path), "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
            capture_output=True, check=True).stdout

    def pixel(self, x, y):
        i = (y * self.width + x) * 3
        return tuple(self.raw[i:i + 3])


def near(a, b, tolerance=TOLERANCE):
    return max(abs(x - y) for x, y in zip(a, b)) <= tolerance


def capture(c, p, name):
    """The timeline region through `snapshot_ui`; (image, scale)."""
    shot = WORK / "strips" / f"{name}.png"
    answer = c.call_with("snapshot_ui", {"project": p, "window": "editor", "view": "timeline",
                                         "path": str(shot), "layout": False})
    return Png(shot), answer["scale"]


def strip_of(image, scale):
    """The row of pixels along the first lane's strip, from the clip's left edge up to the lane's
    background."""
    y, x0 = int(LANE_Y * scale), int(LANE_X * scale)
    pixels = []
    for x in range(x0, image.width):
        px = image.pixel(x, y)
        if near(px, LANE, 8):
            break
        pixels.append(px)
    return pixels


def runs(pixels, tolerance=14, least=3):
    """Stretches of like colour: (start, end, colour)."""
    found, begin, reference = [], 0, pixels[0] if pixels else None
    for i, px in enumerate(pixels):
        if not near(px, reference, tolerance):
            if i - begin >= least:
                found.append((begin, i - 1, reference))
            begin, reference = i, px
    if pixels:
        found.append((begin, len(pixels) - 1, reference))
    return found


def wait_thumbs(p, media, want):
    folder = Path(p) / "cache/thumbs" / str(media)
    names = []
    for _ in range(150):
        names = [n for n in os.listdir(folder) if n.endswith(".jpg")] if folder.is_dir() else []
        if len(names) >= want:
            break
        time.sleep(0.2)
    return names


def fit(c, p):
    time.sleep(0.8)
    c.call_with("perform_menu_item", {"project": p, "path": ["View", "Fit Timeline"]})
    time.sleep(0.5)


def fresh(c, name):
    p = str(WORK / "strips" / f"{name}.framejob")
    c.call_with("new_project", {"path": p})
    return p, state(c, p)["tracks"][-1]["id"]


def rows_image(c, card):
    if "F1" in selected:
        p, t = fresh(c, "image")
        m = imported(c, p, card)
        c.call_with("add_clip", {"project": p, "track": t, "media": m, "at": 0})
        thumbs = wait_thumbs(p, m, 1)
        time.sleep(1)
        image, scale = capture(c, p, "image_default")
        pixels = strip_of(image, scale)
        plain = sum(1 for px in pixels if near(px, PLAIN))
        check("F1", pixels and plain <= 2 * scale and len(thumbs) == 1,
              f"thumbs {thumbs}; a clip of {len(pixels)} px, {plain} of them bare")
        c.call_with("close_project", {"project": p, "discard": True})
    if "F2" in selected:
        p, t = fresh(c, "thin")
        m = imported(c, p, card)
        movie = imported(c, p, MEDIA / "C.mov")
        c.call_with("add_clip", {"project": p, "track": t, "media": m, "at": 0})
        c.call_with("add_clip", {"project": p, "track": t, "media": movie, "at": 90 * SEC})
        wait_thumbs(p, m, 1)
        fit(c, p)
        image, scale = capture(c, p, "image_thin")
        pixels = strip_of(image, scale)
        pts = len(pixels) / scale / 5
        tile = sum(1 for px in pixels if not near(px, PLAIN))
        check("F2", pixels and pts < 17 and tile >= 0.9 * len(pixels),
              f"{pts:.1f} pt/s; the image's {len(pixels)} px, tile over {tile}")
        c.call_with("close_project", {"project": p, "discard": True})


def rows_freeze(c, hues):
    def freeze(name, at, hold):
        p, t = fresh(c, name)
        m = imported(c, p, hues)
        c.call_with("add_clip", {"project": p, "track": t, "media": m, "at": 0})
        wait_thumbs(p, m, 10)
        clip = state(c, p)["clips"][0]["id"]
        c.call_with("freeze_frame", {"project": p, "clip": clip, "at": at * SEC,
                                     "duration": hold * SEC})
        fit(c, p)
        image, scale = capture(c, p, name)
        pixels = strip_of(image, scale)
        total = max(x["start"] + x["duration"] for x in state(c, p)["clips"]) / SEC
        per = len(pixels) / total
        lo, hi = int((at + 0.05) * per), int((at + hold - 0.05) * per)
        c.call_with("close_project", {"project": p, "discard": True})
        return pixels[lo:hi]

    if "F3" in selected:
        held = freeze("freeze_mid", 2, 8)
        stretches = runs(held)
        longest = max((e - b + 1 for b, e, _ in stretches), default=0)
        check("F3", held and longest >= 0.97 * len(held),
              f"{len(stretches)} stretches over {len(held)} px, the longest {longest}")
    if "F4" in selected:
        held = freeze("freeze_end", 8, 6)
        plain = sum(1 for px in held if near(px, PLAIN))
        stretches = runs(held)
        longest = max((e - b + 1 for b, e, _ in stretches), default=0)
        check("F4", held and plain <= 0.02 * len(held) and longest >= 0.97 * len(held),
              f"{plain} bare of {len(held)} px, {len(stretches)} stretches, longest {longest}")
    if "F5" in selected:
        p, t = fresh(c, "strip")
        m = imported(c, p, hues)
        c.call_with("add_clip", {"project": p, "track": t, "media": m, "at": 0})
        wait_thumbs(p, m, 10)
        fit(c, p)
        image, scale = capture(c, p, "strip")
        pixels = strip_of(image, scale)
        stretches = runs(pixels, least=8)
        check("F5", len(stretches) >= 8, f"{len(stretches)} stretches along a 10 s strip of "
                                         f"{len(pixels)} px")
        c.call_with("close_project", {"project": p, "discard": True})


def strip_media():
    folder = WORK / "strips"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    card, hues = folder / "card.png", folder / "hues.mov"
    subprocess.run([FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i",
                    "color=c=0xff8800:size=640x360", "-frames:v", "1", str(card)], check=True)
    subprocess.run([FFMPEG, "-y", "-v", "error", "-f", "lavfi", "-i",
                    "color=c=0xff0000:size=640x360:rate=30:duration=10", "-vf",
                    "hue=H=floor(t)*PI/5", "-pix_fmt", "yuv420p", "-c:v", "libx264", str(hues)],
                   check=True)
    return card, hues


def strip_rows(c):
    card, hues = strip_media()
    rows_image(c, card)
    rows_freeze(c, hues)


def app_rows(binary):
    """The fixtures and the `app` rows in one launch; the ids, or None."""
    log = WORK / "app.log"
    launched = mcp.launch(str(binary), ["-RCDevAppearance", "dark"], log_path=str(log),
                          timeout=CALL_BOUND)
    ids = None
    try:
        if launched.client is None:
            for name in APP_ROWS:
                check(name, False, "the app did not listen")
            return None
        c = launched.client
        print(f"  instance PID {launched.child.pid}", flush=True)
        ids = make_fixtures(c)
        for names, body in ((("D7", "D8"), lambda: rows_tool(c, ids)),
                            (("F1", "F2", "F3", "F4", "F5"), lambda: strip_rows(c))):
            if not selected & set(names):
                continue
            try:
                body()
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                for name in names:
                    check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return ids


# ---- the probe rows -----------------------------------------------------------------

def build_probe(tree):
    """(the binary, None) or (None, why)."""
    folder = WORK / "probe"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    entry = folder / "main.swift"
    shutil.copyfile(HERE / f"{PROBE}.swift", entry)
    tree = Path(tree)
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


def run_probe(binary, which):
    """Every row the probe printed, by id; (rows, why)."""
    run = WORK / "run"
    shutil.rmtree(run, ignore_errors=True)
    shutil.copytree(FIXTURES, run)
    rows = {}
    try:
        done = subprocess.run([str(binary), str(run), str(run / "ids.json"), which],
                              capture_output=True, text=True, timeout=PROBE_BOUND)
    except subprocess.TimeoutExpired:
        return rows, f"no answer within {PROBE_BOUND} s"
    finally:
        left = proof_defaults.remove_domain(PROBE)
        if left:
            print(f"  the probe's defaults domain: {left}", flush=True)
    (WORK / f"probe-{which}.out.txt").write_text(done.stdout + "\n--- stderr\n" + done.stderr)
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            row = json.loads(line)
            if "abort" in row:
                return rows, row["abort"]
            rows[row.get("row")] = row
    if done.returncode != 0:
        return rows, f"the probe exited {done.returncode}: {done.stderr[-300:]}"
    return rows, None


def new_clips(row):
    known = {x["id"] for x in row["before"]["clips"]}
    return [x for x in row["after"]["clips"] if x["id"] not in known]


def originals_in_place(row):
    now = {x["id"]: x for x in row["after"]["clips"]}
    return all(now.get(x["id"], {}).get("start") == x["start"]
               and now.get(x["id"], {}).get("track") == x["track"] for x in row["before"]["clips"])


def fresh_nest(row):
    """The nests the paste added."""
    known = {x["id"] for x in row["before"]["nests"]}
    return [x for x in row["after"]["nests"] if x["id"] not in known]


def nest_of(clip):
    return clip["source"].get("project") if clip["source"].get("kind") == "nest" else None


def score_464(r):
    n1 = r.get("N1")
    if n1:
        made, nests = new_clips(n1), fresh_nest(n1)
        check("N1", n1["payload_keys"] == ["clips", "media", "nests"], f"keys {n1['payload_keys']}")
        check("N1", n1["alert"] is None, f"alert {n1['alert']}")
        check("N1", len(made) == 1 and made[0]["start"] == 40 * SEC and len(nests) == 1
              and nest_of(made[0]) == nests[0]["id"] and n1["undo"] == "Paste",
              f"landed {[(x['id'], x['start'] / SEC, x['source']) for x in made]}, "
              f"new nests {[x['id'] for x in nests]}, undo {n1['undo']}")
        check("N1", n1["payload_media"] == 2, f"{n1['payload_media']} media rows")
    n2 = r.get("N2")
    if n2:
        made = new_clips(n2)
        check("N2", n2["alert"] is None and len(made) == 2 and len(fresh_nest(n2)) == 1,
              f"alert {n2['alert']}, landed {len(made)} clips, {len(fresh_nest(n2))} new nests")
    n3 = r.get("N3")
    if n3:
        check("N3", n3["alert"] is None and n3["undo"] == "Paste"
              and n3["undo_after_paste_undone"] == "Cut" and n3["restored"],
              f"alert {n3['alert']}, undo {n3['undo']}, then {n3['undo_after_paste_undone']}, "
              f"restored {n3['restored']}")
        shown = [x for x in n3["after"]["clips"] if nest_of(x) is not None]
        check("N3", len(shown) == 1 and shown[0]["start"] == 40 * SEC,
              f"nest clips after the paste {[(x['id'], x['start'] / SEC) for x in shown]}")
    n4 = r.get("N4")
    if n4:
        after = n4["after"]
        inner = [x for n in after["nests"] for x in n["clips"]]
        check("N4", n4["alert"] is None and len(after["clips"]) == 1 and len(after["nests"]) == 1
              and len(inner) == 2 and {"A.mov", "B.mov"} <= set(after["media"]),
              f"alert {n4['alert']}, {len(after['clips'])} clips, {len(after['nests'])} nests, "
              f"{len(inner)} inner clips, media {after['media']}")
    n5 = r.get("N5")
    if n5:
        made, nests = new_clips(n5), fresh_nest(n5)
        ok = len(made) == 1 and len(nests) == 2
        detail = f"payload nests {n5['payload_nests']}, new clips {len(made)}, new nests {len(nests)}"
        if ok:
            top = next((x for x in nests if x["id"] == nest_of(made[0])), None)
            children = [nest_of(x) for x in (top or {"clips": []})["clips"]]
            ok = top is not None and any(i in {x["id"] for x in nests} for i in children)
            detail += f", the outer copy's clips show {children}"
        check("N5", ok and n5["payload_nests"] == 2 and n5["alert"] is None, detail)
    n6 = r.get("N6")
    if n6:
        made, nests = new_clips(n6), fresh_nest(n6)
        shown = {nest_of(x) for x in made}
        check("N6", n6["payload_nests"] == 1 and len(made) == 2 and len(nests) == 1
              and shown == {nests[0]["id"]},
              f"payload nests {n6['payload_nests']}, new clips {len(made)}, new nests "
              f"{[x['id'] for x in nests]}, shown {shown}")
    n8 = r.get("N8")
    if n8:
        before = {x["id"] for x in n8["before"]["nests"]}
        added = [x for x in n8["after"]["nests"] if x["id"] not in before]
        shown = [nest_of(x) for x in n8["view"]["clips"]]
        check("N8", n8["alert"] is None and n8["undo"] == "Paste" and n8["scope"] > 0
              and len(added) == 1 and added[0]["id"] in shown,
              f"alert {n8['alert']}, undo {n8['undo']}, scope {n8['scope']}, added nests "
              f"{[x['id'] for x in added]}, the view shows {shown}")
    n9 = r.get("N9")
    if n9:
        check("N9", n9["payload_keys"] == ["clips", "media"] and len(new_clips(n9)) == 1,
              f"keys {n9['payload_keys']}, landed {len(new_clips(n9))}")
    pb = r.get("PB")
    if pb:
        check("PB", pb["start"] == pb["end"], f"change count {pb['start']} then {pb['end']}")


def landed(row, want, track_index=None, name="Duplicate Clips", count=1):
    """One new copy at `want` seconds on `track_index`, the originals still there."""
    made = new_clips(row)
    return (len(made) == count and any(x["start"] == want * SEC
                                       and (track_index is None or x["index"] == track_index)
                                       for x in made)
            and originals_in_place(row) and row["undo"] == name and row["undo_steps"] == 1
            and row["restored"])


def told(row):
    return (f"undo {row['undo']} ({row['undo_steps']} steps), clips "
            f"{[(x['id'], x['index'], x['start'] / SEC) for x in row['after']['clips']]}, tracks "
            f"{len(row['after']['tracks'])}, flash {row['flash']}")


def refused(row):
    """No copy, no new track, no undo step, the flash."""
    return (not new_clips(row) and row["after"]["tracks"] == row["before"]["tracks"]
            and row["undo_steps"] == 0 and row["undo"] == "<nothing to undo>"
            and row["after"]["clips"] == row["before"]["clips"] and row["flash"])


def linked_pair(row, picture_index):
    made = new_clips(row)
    if len(made) != 2:
        return False
    sound = next((x for x in made if x["index"] == 0), None)
    picture = next((x for x in made if x["index"] != 0), None)
    return (picture is not None and sound is not None and picture["index"] == picture_index
            and picture["start"] == 12 * SEC and sound["start"] == 12 * SEC
            and picture["linked"] == sound["id"] and sound["linked"] == picture["id"]
            and originals_in_place(row) and row["undo"] == "Duplicate Clips"
            and row["undo_steps"] == 1 and row["restored"])


def score_465(r, ids):
    if "D1" in r:
        check("D1", landed(r["D1"], 12, 1), told(r["D1"]))
    if "D2" in r:
        check("D2", landed(r["D2"], 20, 0), told(r["D2"]))
    if "D3" in r:
        check("D3", landed(r["D3"], 12, 1), told(r["D3"]))
    if "D4" in r:
        row = r["D4"]
        check("D4", not new_clips(row) and row["undo"] == "Move Clips" and row["undo_steps"] == 1
              and any(x["start"] == 12 * SEC and x["index"] == 1 for x in row["after"]["clips"]),
              told(row))
    if "D5" in r:
        check("D5", refused(r["D5"]), told(r["D5"]))
    if "D6" in r:
        row = r["D6"]
        made = new_clips(row)
        check("D6", landed(row, 12) and len(row["after"]["tracks"]) == len(row["before"]["tracks"]) + 1
              and made[0]["track"] not in row["before"]["tracks"], told(row))
    link = ids["link"]
    shape = (link["sound_index"], link["picture_index"], link["tracks"]) == (0, 1, 3)
    if "D9" in r:
        check("D9", shape and linked_pair(r["D9"], 2), f"{link}; {told(r['D9'])}")
    if "D10" in r:
        row = r["D10"]
        check("D10", shape and linked_pair(row, 3)
              and len(row["after"]["tracks"]) == len(row["before"]["tracks"]) + 1, told(row))
    if "D11" in r:
        check("D11", shape and refused(r["D11"]), told(r["D11"]))
    if "D12" in r:
        check("D12", refused(r["D12"]), told(r["D12"]))
    if "D13" in r:
        check("D13", refused(r["D13"]), told(r["D13"]))
    if "D14" in r:
        row = r["D14"]
        made = new_clips(row)
        check("D14", len(made) == 2 and all(x["start"] == 30 * SEC for x in made)
              and len(row["after"]["tracks"]) == len(row["before"]["tracks"]) + 1
              and row["undo"] == "Duplicate Clips" and row["undo_steps"] == 1, told(row))


def dropped(row):
    clips = [(x["id"], x["index"], x["start"] / SEC, x["transition"]) for x in row["after"]["clips"]]
    return (f"answered {row['performDragOperation']}, undo {row['undo']}, strip "
            f"'{row['strip'][:60]}', clips {clips}")


def score_507(r):
    if "M1" in r:
        row = r["M1"]
        check("M1", row["performDragOperation"] is False and row["strip"].startswith("Refused:")
              and row["after"] == row["before"] and row["undo"] == row["undo_before"], dropped(row))
    if "M2" in r:
        check("M2", r["M2"]["performDragOperation"] is False, dropped(r["M2"]))
    if "M3" in r:
        row = r["M3"]
        check("M3", row["performDragOperation"] is True and len(new_clips(row)) == 1, dropped(row))
    if "M4" in r:
        row = r["M4"]
        made = new_clips(row)
        check("M4", row["performDragOperation"] is True and len(made) == 1
              and made[0]["transition"] == "cross_dissolve", dropped(row))
    if "M6" in r:
        row = r["M6"]
        made = new_clips(row)
        check("M6", row["performDragOperation"] is True and len(made) == 1
              and len(row["after"]["tracks"]) == len(row["before"]["tracks"]) + 1
              and made[0]["track"] not in row["before"]["tracks"], dropped(row))


def probe_rows(tree, ids):
    wanted = [r for r in PROBE_ROWS if r in selected]
    if not wanted:
        return
    binary, why = build_probe(tree)
    if binary is None:
        for row in wanted:
            check(row, False, f"the probe did not build: {why}")
        return
    groups = {GROUP[r[0]] for r in wanted if r[0] in GROUP}
    which = groups.pop() if len(groups) == 1 else "all"
    rows, why = run_probe(binary, which)
    if why:
        print(f"  the probe stopped: {why}", flush=True)
    score_464(rows)
    score_465(rows, ids)
    score_507(rows)
    for row in wanted:
        if row not in results:
            check(row, False, f"the probe printed no such row ({why or 'it finished'})")


def run_rows(binary, tree):
    ids = app_rows(binary)
    if ids is None:
        for row in PROBE_ROWS:
            check(row, False, "the fixtures were not made")
        return
    probe_rows(tree, ids)


# ---- mutants ------------------------------------------------------------------------

def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def real_core(made):
    """The copy's `core` as a real folder with its own (CoW) target, in place of the symlink."""
    link = Path(made) / "core"
    link.unlink()
    subprocess.run(["cp", "-c", "-R", str(ROOT / "core"), str(link)], check=True)


def cargo(made, *arguments):
    done = subprocess.run(["cargo", *arguments, "--release"], cwd=str(Path(made) / "core"),
                          capture_output=True, text=True, timeout=BUILD_BOUND)
    return done.returncode, (done.stdout + done.stderr)[-400:]


def run_mutant(name):
    global selected
    rows, edits = MUTANTS[name]
    print(f"docs bugs a1: the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    before = {path: digest(path) for path, _, _ in edits}
    selected = set(rows) | {"Z1"}
    on_app = any(row in APP_ROWS for row in rows)
    on_core = any(path.startswith("core/") for path, _, _ in edits)
    made, why = tree_copy.make_copy(str(WORK / "mutant"), agent=on_app)
    if not why and on_core:
        real_core(made)
    if not why:
        for path, anchor, replacement in edits:
            target = Path(made) / path
            text = target.read_text()
            if text.count(anchor) != 1:
                why = f"the anchor occurs {text.count(anchor)} times in {path}"
                break
            target.write_text(text.replace(anchor, replacement))
    if not why and on_core:
        code, tail = cargo(made, "build")
        why = None if code == 0 else f"the core did not build: {tail}"
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    if on_app:
        app, why = tree_copy.build_app(Path(made), BUILD_BOUND)
        if app is None:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        app_rows(proof_app.executable(app))
    else:
        ids = app_rows(proof_app.binary())
        if ids is None:
            print(f"mutant {name}: the control could not be performed — no fixtures")
            return 2
        probe_rows(made, ids)
    after = {path: digest(path) for path, _, _ in edits}
    print(f"  the tree's files unchanged by SHA-256: {before == after}")
    if not all(row in results for row in rows):
        print(f"mutant {name}: the control could not be performed — {rows} never scored")
        return 2
    caught = any(not all(ok for ok, _ in results[row]) for row in rows)
    if name in CORE_TEST:
        code, tail = cargo(made, "test", "--test", CORE_TEST[name])
        print(f"  core test {CORE_TEST[name]}: exit {code}", flush=True)
        caught = caught and code != 0
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
    print(f"docs bugs a1 ({proof_app.config()} build), tree {args.tree}", flush=True)
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
