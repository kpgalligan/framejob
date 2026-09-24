#!/usr/bin/env python3
"""Road map 9, phase 1 — the selected action, the action lane, the bands.

    python3 tools/proof/clip_inspector_proof.py
    python3 tools/proof/clip_inspector_proof.py --mutant entry

Two instruments, `sharp_chrome.py`'s shape:

* **the probe**, `clip_inspector_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `harness/build.sh`'s swiftc line (a probe that will not build is a scored
  FAILURE, never an exit). Rows S1–S6: the entry rule, a selection change,
  removal and a two-clip selection, the binding's END-state reads and its
  routing, the band hit against the fade handles, the Clip tab's lane.
* **the harness**, the editor at 1440 × 862, dark, M, one shape card of 6 s
  (`e2_chrome.clip`, so the tint under the lane is `DS.clipShape` exactly)
  with two linear actions of at least 1 s — 0.5–1.5 s and 2.5–4.0 s — the
  card selected, the playhead at 5 s (clear of both bands), and the SECOND
  action selected through the harness's thirteenth argument. Every band is
  sampled at (maxX − 2, maxY − 2), which the painter keeps clear of the
  number, the glyph and the curve.

`--mutant entry` builds the probe over a COPY of `app/Sources` whose
`syncSelectedAction` ignores `lastInsideAction` (every sync selects the span
under the playhead). Exit 0 means an S1 row FAILED in the copy and no other
row did — the entry rule is what S1 measures, and only S1.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (the helpers: Image, clip, project, write_package)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector_probe.swift")
TICKS = e2.TICKS

MINT = (92, 214, 176)
CLIP_SHAPE = (0x24, 0x76, 0x86)
WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT
CLIP_X0 = e2.CLIP_X0                      # 132
ZOOM = e2.ZOOM                            # 42 pt per second
LANE_TOP = e2.STRIP_Y + e2.STRIP_H        # 643: the content's top, under the strip
LANE_M = 12                               # DS.actionLaneHeights[1]
RULER_BOTTOM = e2.TIMELINE_Y + e2.BAR_H + e2.RULER_H   # 620
INSPECTOR_X = e2.INSPECTOR_X              # 1136
LANE_X0 = INSPECTOR_X + 10 + 40 + 4       # the inspector lane: after the Clip chip, at a
LANE_X1 = INSPECTOR_X + 304 - 10          # full-width pane (a column to look in, no more)
CLIP_SECONDS = 6
ACTIONS = [(0.5, 1.5), (2.5, 4.0)]        # the second is selected
PLAYHEAD = 5

MUTANT_FILE = "ProjectDocument+SelectedAction.swift"
MUTANT_ANCHOR = "        guard under != lastInsideAction else { return }\n"

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def action(aid, start, end, patch):
    return {"id": aid, "start": int(start * TICKS), "duration": int((end - start) * TICKS),
            "curve": "linear", "end": patch}


def two_tracks(body, clip_tracks):
    """Tracks 1 and 7 — ids are unique across the WHOLE project, clips'
    included, so a track 2 would collide with clip 2."""
    body["tracks"] = [
        {"id": t, "name": f"Track {t}", "hidden": False, "muted": False, "locked": False,
         "solo": False} for t in (1, 7)]
    for c in body["clips"]:
        c["track"] = clip_tracks[c["id"]]
    return body


def media_clip(cid, media, start, actions, video):
    return {
        "id": cid, "track": 1, "start": start, "duration": CLIP_SECONDS * TICKS,
        "source": {"kind": "media", "media": media, "in": 0, "reversed": False},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": e2.video_props() if video else None, "audio": {}, "text": None,
        "shape": None, "actions": actions, "transition_in": None, "name": None,
        "label": None,
    }


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    six = CLIP_SECONDS * TICKS
    shapes = e2.project([
        e2.clip(2, 0, e2.GREY, actions=[
            action(10, 1, 2, {"video": {"opacity": 0.0}}),
            action(11, 3, 4, {"video": {"x": 100.0}})], duration=six),
        e2.clip(3, 0, e2.GREY, actions=[action(12, 1, 2.5, {"video": {"opacity": 0.5}})],
                duration=six),
        e2.clip(4, six, e2.GREY, duration=six),
    ])
    move = e2.project([
        e2.clip(2, 2 * TICKS, e2.GREY, actions=[
            action(10, 1, 2, {"video": {"opacity": 0.0}}),
            action(11, 3, 4, {"video": {"x": 100.0}})], duration=six)])
    media = e2.project([
        media_clip(4, 90, 0, [action(13, 0, 1, {"audio": {"volume": 0.5}})], video=False),
        media_clip(5, 91, 0, [action(14, 2, 3, {"video": {"x": 50.0}})], video=True),
    ], media=e2.AUDIO_MEDIA + [{
        "id": 91, "path": "/fixtures/talk.mov", "kind": "video",
        "duration": 60 * TICKS, "width": 1920, "height": 1080, "fps": [30, 1],
        "has_video": True, "has_audio": True,
    }])
    chrome = e2.project([
        e2.clip(2, 0, e2.GREY, name="Card", duration=six, actions=[
            action(3, *ACTIONS[0], {"video": {"opacity": 0.5}}),
            action(4, *ACTIONS[1], {"video": {"x": 100.0}})])])
    return {
        "shapes": e2.write_package("ci-shapes", two_tracks(shapes, {2: 1, 3: 7, 4: 1})),
        "move": e2.write_package("ci-move", move),
        "media": e2.write_package("ci-media", two_tracks(media, {4: 1, 5: 7})),
        "chrome": e2.write_package("ci-chrome", chrome),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "clip-inspector-probe")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary) for f in swift + [entry, lib]):
        return binary, None
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging",
                                             "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + swift + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["(no error lines)"])
    print(f"  probe built in {time.time() - start:.0f} s")
    return binary, None


def probe_checks(sources, out, paths):
    print("\n1 — the probe: S1 entry, S2 selection, S3 removal, S4 binding, S5 hits, S6 lane")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return None
    request = os.path.join(out, "request.json")
    answer = os.path.join(out, "answer.json")
    if os.path.exists(answer):
        os.remove(answer)
    with open(request, "w") as f:
        json.dump(paths, f, indent=2)
    result = subprocess.run([binary, request, answer], capture_output=True, text=True,
                            timeout=300)
    if result.returncode != 0 or not os.path.exists(answer):
        check("the probe runs", False, (result.stdout + result.stderr).strip()[-400:])
        return binary
    with open(answer) as f:
        rows = json.load(f)["rows"]
    check("the probe answers every S-row (S1–S6 present)",
          all(any(r["name"].startswith(f"S{n} ") for r in rows) for n in range(1, 7)),
          f"{len(rows)} rows")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])
    return binary


# ---------------------------------------------------------------------------
# The harness.


def render(binary, package, out):
    args = [binary, package, out, "dark", str(WIDTH), str(HEIGHT), "0", str(PLAYHEAD), "1",
            "clip", "-", "-", "-", "1"]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out, None


def px(image, x, y):
    """The pixel containing the POINT (x, y), top-left origin, as RGB."""
    s = image.scale
    row = image.rows[int(y * s)]
    c = image.channels
    i = int(x * s) * c
    return tuple(row[i:i + 3])


def near(a, b, tolerance):
    return all(abs(p - q) <= tolerance for p, q in zip(a, b))


HARNESS_ROWS = [
    "timeline: the selected band's (maxX − 2, maxY − 2) is the action ink (sRGB (92, 214, 176), "
    "in the PNG's space)",
    "timeline: a normal band's is 0.34·mint + 0.66·(0.78·clipShape) ± 1",
    "timeline: the old 4 pt black bar is gone (a normal band's top row is its fill)",
    "ruler: the bottom 2 pt under the selected span is the action ink",
    "inspector lane: the selected band is 20 pt tall (the 28 pt row inset 4 and 4), and its "
    "(maxX − 2, maxY − 2) is the action ink",
]


def converted(probe, png):
    """The action ink and the shape tint in the PNG's own colour space,
    through the probe's `--convert` (ColorSync), or None."""
    if probe is None:
        return None
    out = os.path.join(WORK, "converted.json")
    result = subprocess.run([probe, "--convert", png, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None
    with open(out) as f:
        return json.load(f)


def harness_checks(chrome, probe):
    print("\n2 — the harness: dark, 1440 × 862, M, the second action selected")
    binary, error = e2.build_harness()
    if error:
        for name in HARNESS_ROWS:
            check(name, False, error)
        return
    out, error = render(binary, chrome, os.path.join(WORK, "ci-dark.png"))
    if error:
        for name in HARNESS_ROWS:
            check(name, False, error)
        return
    image = e2.Image(out)
    s = image.scale
    print(f"       {os.path.relpath(out, ROOT)}: {image.width}×{image.height} px, scale {s:g}")
    inks = converted(probe, out)
    if not inks or len(inks.get("mint", [])) != 3 or len(inks.get("clipShape", [])) != 3:
        for name in HARNESS_ROWS:
            check(name, False, "the probe could not convert the inks to the PNG's space")
        return
    mint_f = inks["mint"]
    mint = tuple(int(round(c)) for c in mint_f)
    print(f"       the PNG is in {inks['space']}: sRGB mint {MINT} is {mint} there, "
          f"clipShape {CLIP_SHAPE} is "
          f"({', '.join(f'{c:.1f}' for c in inks['clipShape'])})")
    lane_bottom = LANE_TOP + LANE_M

    def band_x(seconds):
        return CLIP_X0 + seconds * ZOOM

    normal_max = band_x(ACTIONS[0][1])
    selected_max = band_x(ACTIONS[1][1])
    sample = lane_bottom - 2
    got = px(image, selected_max - 2, sample)
    check(HARNESS_ROWS[0], near(got, mint, 1), f"{got} at ({selected_max - 2:g}, {sample:g})")

    want = tuple(0.34 * m + 0.66 * 0.78 * c for m, c in zip(mint_f, inks["clipShape"]))
    got = px(image, normal_max - 2, sample)
    check(HARNESS_ROWS[1], near(got, want, 1),
          f"{got} at ({normal_max - 2:g}, {sample:g}), want "
          f"({', '.join(f'{w:.1f}' for w in want)})")
    top = px(image, normal_max - 2, LANE_TOP + 1)
    check(HARNESS_ROWS[2], top == got, f"top row {top}, bottom {got}")

    # The ruler's rule sits above its own 1 pt border line: y 617–619 pt. A
    # minor tick crosses it every few points, so the row is scanned across
    # the span and must be mostly mint; just outside the span must not be.
    y = RULER_BOTTOM - 2
    xs = [x / s for x in range(int((band_x(ACTIONS[1][0]) + 2) * s),
                               int((selected_max - 2) * s))]
    hits = sum(1 for x in xs if near(px(image, x, y), mint, 1))
    outside = px(image, band_x(ACTIONS[1][0]) - 6, y)
    check(HARNESS_ROWS[3], xs and hits >= 0.7 * len(xs) and not near(outside, mint, 1),
          f"{hits}/{len(xs)} px of the span's row are mint; 6 pt before it {outside}")

    # The inspector's lane: find the selected band's column run of mint.
    fraction = [ACTIONS[1][0] / CLIP_SECONDS, ACTIONS[1][1] / CLIP_SECONDS]
    x0 = LANE_X0 + (LANE_X1 - LANE_X0) * fraction[0]
    x1 = LANE_X0 + (LANE_X1 - LANE_X0) * fraction[1]
    column = (x0 + x1) / 2
    ys = [y / s for y in range(int(e2.TOOLBAR * s), int(e2.TIMELINE_Y * s))
          if near(px(image, column, y / s), mint, 1)]
    if not ys:
        check(HARNESS_ROWS[4], False, f"no mint in the inspector column x {column:g}")
        return
    # The FIRST run of mint rows down the column: since phase 2 the sub-tab
    # strip's mint `◆1` sits below the lane — its cell spans this column
    # (the cell's x-range includes it), 40 pt and more under the band — and
    # the band is above it. A gap of up to 4 pt stays inside the run,
    # because the selected band's curve crosses the column (measured: mint
    # at 156–164.5 and 167–175.5 pt).
    run = [ys[0]]
    for y in ys[1:]:
        if y - run[-1] > 4:
            break
        run.append(y)
    y0, y1 = run[0], run[-1] + 1 / s
    row = y1 - 2
    right = column
    while right < WIDTH - 1 and near(px(image, right + 1 / s, row), mint, 1):
        right += 1 / s
    left = column
    while left > INSPECTOR_X and near(px(image, left - 1 / s, y0 + 1), mint, 1):
        left -= 1 / s
    right += 1 / s
    got = px(image, right - 2, row)
    # Where the band sits along the lane is the probe's S6 row (`bandRects()`
    # against `laneRect`): the pane's width here depends on whether the
    # host shows legacy scrollers, so it is not re-derived from pixels.
    check(HARNESS_ROWS[4], near(got, mint, 1) and abs((y1 - y0) - 20) <= 0.5,
          f"band x {left:g}–{right:g}, y {y0:g}–{y1:g}; (maxX − 2, maxY − 2) {got}")


# ---------------------------------------------------------------------------


def mutant():
    began = time.time()
    with tempfile.TemporaryDirectory(prefix="reelcut-clip-inspector-entry-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, MUTANT_FILE)
        with open(path) as f:
            text = f.read()
        if text.count(MUTANT_ANCHOR) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(MUTANT_ANCHOR)} times")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(MUTANT_ANCHOR, ""))
        print(f"MUTANT entry: syncSelectedAction ignores lastInsideAction, in {sources}")
        paths = packages()
        del paths["chrome"]
        probe_checks(sources, os.path.join(temp, "out"), paths)
    built = bool(RESULTS) and RESULTS[0][1]
    failed = [n for n, ok in RESULTS if not ok]
    s1 = [n for n in failed if n.startswith("S1 ")]
    others = [n for n in failed if not n.startswith("S1 ")]
    elapsed = time.time() - began
    if built and s1 and not others:
        print(f"MUTANT PASS: entry — {len(s1)} S1 row(s) FAILED in the copy and nothing "
              f"else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: entry — built {built}, S1 failures {len(s1)}, other failures "
          f"{others}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] == "entry":
        return mutant()
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Road map 9, phase 1 — the selected action, the lane, the bands")
    paths = packages()
    chrome = paths.pop("chrome")
    probe = probe_checks(
        os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"), paths)
    harness_checks(chrome, probe)
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
