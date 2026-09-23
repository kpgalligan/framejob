#!/usr/bin/env python3
"""Road map 9, phase 2 — the Clip tab's sub-tabs and the pinned block.

    python3 tools/proof/clip_inspector2_proof.py
    python3 tools/proof/clip_inspector2_proof.py --mutant tabs

Two instruments, `clip_inspector_proof.py`'s shape:

* **the probe**, `clip_inspector2_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `harness/build.sh`'s swiftc line (a probe that will not build is a scored
  FAILURE, never an exit). Rows T1–T7: the tabs per kind and the default,
  the section ids per tab, the choice kept and forgotten, the two renamed
  titles, the `◆N` count, the block pinned outside the scroll view, and the
  park clamp on a clip shorter than a frame.
* **the harness**, the editor at 1440 × 862, dark, M, phase 1's fixture — one
  shape card of 6 s with two linear actions, 0.5–1.5 s ({video: {opacity}})
  and 2.5–4.0 s ({video: {x}}), the card selected and the playhead at 5 s —
  through the harness's fourteenth argument, `subTab`. Rows H1–H4: the render
  is deterministic, the active cell's fill swaps with the tab, the `◆1` badge
  is mint and only with the action selected, and the inspector slider's knob
  is the 7 × 11 block on device pixels.

`--mutant tabs` builds the probe over a COPY of `app/Sources` whose
`ClipPane.makeSections()` ignores `activeSubTab` (every tab's sections, in
one list). Exit 0 means T2 rows FAILED in the copy and no other row did.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (Image, clip, project, write_package, build_harness)
import clip_inspector_proof as ci  # noqa: E402  (action, two_tracks, media_clip, px, near)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector2")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector2_probe.swift")
TICKS = e2.TICKS

WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT       # 1440 × 862
INSPECTOR_X, INSPECTOR_W = 1136, 304      # WIDTH − DS.panelWidth
PINNED_TOP = 44 + 32                      # DS.toolbarHeight + DS.tabHeight
HEADER_H = 44                             # ClipSelectionHeaderView.height
LANE_H = 8 + 18 + 6 + 28 + 9              # ActionLaneView: top, headerRow, gap, laneRow, bottom
DETAIL_H = 6 + 22                         # … gap + detailRow, with an action selected
SUB_TOP, CELL = 8, 24                     # ClipSubTabsView.top, .cell
SUB_H = SUB_TOP + CELL + 8                # … + bottom
SIDE = 10                                 # InspectorMetrics.inset
TABS = ["shape", "picture", "clip"]       # the card's tabs, in order
PLAYHEAD = 5

MUTANT_FILE = "ClipPane.swift"
MUTANT_EDITS = [
    ("        switch activeSubTab {\n", "        for tab in subTabs {\n        switch tab {\n"),
    ("        }\n        // A tab that would open",
     "        }\n        }\n        // A tab that would open"),
    ("            sections = [", "            sections += ["),
]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def text_clip(cid):
    return {
        "id": cid, "track": 1, "start": 0, "duration": 6 * TICKS,
        "source": {"kind": "text"}, "enabled": {"video": True, "audio": True},
        "speed": 1.0, "video": e2.video_props(), "audio": None,
        "text": {
            "content": "Hello", "font": "SourceSans3-SemiBold", "size": 72.0,
            "color": [1.0, 1.0, 1.0, 1.0], "align": "center", "valign": "middle",
            "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": None,
            "width": None,
        },
        "shape": None, "actions": [], "transition_in": None, "name": None, "label": None,
    }


def movie(mid, audio):
    return {"id": mid, "path": f"/fixtures/talk{mid}.mov", "kind": "video",
            "duration": 60 * TICKS, "width": 1920, "height": 1080, "fps": [30, 1],
            "has_video": True, "has_audio": audio}


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    six = 6 * TICKS
    av = e2.project([
        ci.media_clip(2, 91, 0, [ci.action(10, 1, 2, {"audio": {"volume": 0.5}})], video=True),
        ci.media_clip(3, 91, 0, [], video=True),
    ], media=[movie(91, True)])
    park = e2.project([e2.clip(2, 2 * TICKS, e2.GREY, duration=1_000, actions=[
        {"id": 3, "start": 0, "duration": 1_000, "curve": "linear",
         "end": {"video": {"opacity": 0.5}}}])])
    chrome = e2.project([
        e2.clip(2, 0, e2.GREY, name="Card", duration=six, actions=[
            ci.action(3, 0.5, 1.5, {"video": {"opacity": 0.5}}),
            ci.action(4, 2.5, 4.0, {"video": {"x": 100.0}})])])
    return {
        "av": e2.write_package("ci2-av", ci.two_tracks(av, {2: 1, 3: 7})),
        "video": e2.write_package("ci2-video", e2.project(
            [ci.media_clip(2, 92, 0, [], video=True)], media=[movie(92, False)])),
        "audio": e2.write_package("ci2-audio", e2.project(
            [ci.media_clip(2, 90, 0, [], video=False)], media=e2.AUDIO_MEDIA)),
        "text": e2.write_package("ci2-text", e2.project([text_clip(2)])),
        "shape": e2.write_package("ci2-shape", e2.project([e2.clip(2, 0, e2.GREY)])),
        "park": e2.write_package("ci2-park", park),
        "chrome": e2.write_package("ci2-chrome", chrome),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`clip_inspector_proof.build_probe`'s swiftc line, over THIS phase's
    probe source (its module global names the file it compiles)."""
    ci.PROBE_SWIFT = PROBE_SWIFT
    return ci.build_probe(sources, out)


def probe_checks(sources, out, paths):
    print("\n1 — the probe: T1 tabs, T2 sections, T3 choice, T4 titles, T5 count, T6 pinned, "
          "T7 park")
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
    check("the probe answers every T-row (T1–T7 present)",
          all(any(r["name"].startswith(f"T{n} ") for r in rows) for n in range(1, 8)),
          f"{len(rows)} rows")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])
    return binary


# ---------------------------------------------------------------------------
# The harness.


def render(binary, package, out, select_action="-", sub_tab="-"):
    args = [binary, package, out, "dark", str(WIDTH), str(HEIGHT), "0", str(PLAYHEAD), "1",
            "clip", "-", "-", "-", select_action, sub_tab]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out, None


def half_up(x):
    return int(x + 0.5)


def cell_rect(index, detail=False):
    """`ClipSubTabsView.cellRect`, in window points: equal cells whose 1 pt
    borders collapse, `PanelTabsView.tabRect`'s rounding (Swift's `.rounded()`
    is half-up here, where Python's `round` is banker's)."""
    top = PINNED_TOP + HEADER_H + LANE_H + (DETAIL_H if detail else 0) + SUB_TOP
    step = (INSPECTOR_W - 2 * SIDE - 1) / len(TABS)
    left = INSPECTOR_X + SIDE + half_up(index * step)
    right = INSPECTOR_X + SIDE + half_up((index + 1) * step) + 1
    return left, top, right, top + CELL


def fill(image, index):
    left, top, _, _ = cell_rect(index)
    return ci.px(image, left + 3, top + 3)


def mint_count(image, index, mint, detail):
    left, top, right, bottom = cell_rect(index, detail)
    s, ch = image.scale, image.channels
    return sum(1 for y in range(int((top + 1) * s), int((bottom - 1) * s))
               for x in range(int((left + 1) * s), int((right - 1) * s))
               if ci.near(tuple(image.rows[y][x * ch:x * ch + 3]), mint, 1))


def converted(probe, png):
    """The action ink in the PNG's own colour space, through the probe's
    `--convert` (ColorSync), or None."""
    out = os.path.join(WORK, "converted.json")
    result = subprocess.run([probe, "--convert", png, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None
    with open(out) as f:
        return json.load(f)


HARNESS_ROWS = [
    "H1 subTab=picture rendered twice → byte-identical PNGs",
    "H2 subTab=picture: the active Picture cell's fill differs from the inactive Clip cell's",
    "H2 subTab=clip: the active Clip cell's fill differs from the inactive Picture cell's",
    "H2 … and the two fills swap between the renders",
    "H3 with action 2 selected, ≥ 8 px of the Picture cell are the action ink (the ◆1)",
    "H3 … and none without it",
    "H4 the first slider under the block (Transform's Scale): its centreline holds one "
    "colour run exactly 7·s px (7k−1 or 7k off scale 2)",
    "H4 … the block is 11·s px tall",
    "H4 … and its four corners are that colour",
]


def knob(image):
    """The first run of a width the block can have, of one colour differing
    from both neighbours, whose column is about the block's height — scanned
    down from the first section's rows, across the inspector."""
    s = image.scale
    k = int(round(s))
    lengths = {7 * k} if k == 2 else {7 * k - 1, 7 * k}
    top_pt = PINNED_TOP + HEADER_H + LANE_H + SUB_H
    ch = image.channels

    def at(x, y):
        return tuple(image.rows[y][x * ch:x * ch + 3])

    def runs(y):
        found = []
        for x in range(int((INSPECTOR_X + SIDE) * s), int((INSPECTOR_X + INSPECTOR_W) * s)):
            p = at(x, y)
            if found and found[-1][0] == p:
                found[-1][2] += 1
            else:
                found.append([p, x, 1])
        return found

    def vertical(x, y, colour):
        top = bottom = y
        while top > 0 and at(x, top - 1) == colour:
            top -= 1
        while bottom + 1 < image.height and at(x, bottom + 1) == colour:
            bottom += 1
        return top, bottom

    # Below Transform's own header (InspectorMetrics.headerHeight, 28 pt).
    for y in range(int((top_pt + 28) * s), int((top_pt + 120) * s)):
        row = runs(y)
        for i in range(1, len(row) - 1):
            colour, x0, n = row[i]
            if n not in lengths or colour in (row[i - 1][0], row[i + 1][0]):
                continue
            top, bottom = vertical(x0 + n // 2, y, colour)
            if 9 * s <= bottom - top + 1 <= 13 * s:
                return colour, x0, top, bottom, at, runs
    return None


def harness_checks(chrome, probe):
    print("\n2 — the harness: dark, 1440 × 862, M, the card selected")
    binary, error = e2.build_harness()
    renders = {}
    for tag, action, tab in (("picture-a", "-", "picture"), ("picture-b", "-", "picture"),
                             ("clip", "-", "clip"), ("action", "1", "-"),
                             ("none", "-", "-")):
        if error:
            break
        renders[tag], error = render(
            binary, chrome, os.path.join(WORK, f"ci2-{tag}.png"), action, tab)
    if error:
        for name in HARNESS_ROWS:
            check(name, False, error)
        return
    with open(renders["picture-a"], "rb") as a, open(renders["picture-b"], "rb") as b:
        check(HARNESS_ROWS[0], a.read() == b.read())
    images = {tag: e2.Image(path) for tag, path in renders.items()}
    pic, clip = images["picture-a"], images["clip"]
    s = pic.scale
    print(f"       {os.path.relpath(renders['picture-a'], ROOT)}: {pic.width}×{pic.height} px, "
          f"scale {s:g}; cells {[cell_rect(i) for i in range(3)]}")
    on_pic, off_pic = fill(pic, 1), fill(pic, 2)
    on_clip, off_clip = fill(clip, 2), fill(clip, 1)
    check(HARNESS_ROWS[1], on_pic != off_pic, f"Picture {on_pic}, Clip {off_pic}")
    check(HARNESS_ROWS[2], on_clip != off_clip, f"Clip {on_clip}, Picture {off_clip}")
    check(HARNESS_ROWS[3], on_pic == on_clip and off_pic == off_clip,
          f"active {on_pic} / {on_clip}, inactive {off_pic} / {off_clip}")

    inks = converted(probe, renders["action"]) if probe else None
    if not inks or len(inks.get("mint", [])) != 3:
        check(HARNESS_ROWS[4], False, "the probe could not convert the ink to the PNG's space")
        check(HARNESS_ROWS[5], False, "no ink")
    else:
        mint = tuple(int(round(c)) for c in inks["mint"])
        with_action = mint_count(images["action"], 1, mint, detail=True)
        without = mint_count(images["none"], 1, mint, detail=False)
        check(HARNESS_ROWS[4], with_action >= 8,
              f"{with_action} px of {mint} (sRGB {ci.MINT} in {inks['space']})")
        check(HARNESS_ROWS[5], without == 0, f"{without} px")

    found = knob(pic)
    if not found:
        for name in HARNESS_ROWS[6:]:
            check(name, False, "no knob found under the pinned block")
        return
    colour, x0, top, bottom, at, runs = found
    k = int(round(s))
    lengths = {7 * k} if k == 2 else {7 * k - 1, 7 * k}
    mid = (top + bottom) // 2
    line = runs(mid)
    run = next((r for r in line if r[1] <= x0 < r[1] + r[2]), None)
    index = line.index(run) if run else 0
    ok = (run is not None and run[0] == colour and run[2] in lengths
          and 0 < index < len(line) - 1
          and colour not in (line[index - 1][0], line[index + 1][0]))
    check(HARNESS_ROWS[6], ok,
          f"centreline y {mid} px: run {run and (run[0], run[1], run[2])}; "
          f"neighbours {ok and (line[index - 1][0], line[index + 1][0])}")
    x1 = (run[1] + run[2]) if run else x0 + 7 * k
    check(HARNESS_ROWS[7], bottom - top + 1 == 11 * k, f"{bottom - top + 1} px, y {top}–{bottom}")
    corners = [at(x0, top), at(x1 - 1, top), at(x0, bottom), at(x1 - 1, bottom)]
    check(HARNESS_ROWS[8], all(c == colour for c in corners), f"{corners} vs {colour}")


# ---------------------------------------------------------------------------


def mutant():
    began = time.time()
    with tempfile.TemporaryDirectory(prefix="reelcut-clip-inspector2-tabs-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, MUTANT_FILE)
        with open(path) as f:
            text = f.read()
        for anchor, replacement in MUTANT_EDITS:
            if anchor not in text:
                print(f"MUTANT FAILURE: the anchor {anchor!r} is missing")
                return 2
            text = text.replace(anchor, replacement)
        with open(path, "w") as f:
            f.write(text)
        print(f"MUTANT tabs: makeSections() ignores activeSubTab, in {sources}")
        paths = packages()
        del paths["chrome"]
        probe_checks(sources, os.path.join(temp, "out"), paths)
    built = bool(RESULTS) and RESULTS[0][1]
    failed = [n for n, ok in RESULTS if not ok]
    t2 = [n for n in failed if n.startswith("T2 ")]
    others = [n for n in failed if not n.startswith("T2 ")]
    elapsed = time.time() - began
    if built and t2 and not others:
        print(f"MUTANT PASS: tabs — {len(t2)} T2 row(s) FAILED in the copy and nothing "
              f"else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: tabs — built {built}, T2 failures {len(t2)}, other failures "
          f"{others}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] == "tabs":
        return mutant()
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Road map 9, phase 2 — the sub-tabs and the pinned block")
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
