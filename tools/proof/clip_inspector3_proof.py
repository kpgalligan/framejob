#!/usr/bin/env python3
"""Road map 9, phase 3a — the row marks.

    python3 tools/proof/clip_inspector3_proof.py
    python3 tools/proof/clip_inspector3_proof.py --mutant marks

Two instruments, `clip_inspector2_proof.py`'s shape:

* **the probe**, `clip_inspector3_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `harness/build.sh`'s swiftc line (a probe that will not build is a scored
  FAILURE, never an exit). Rows M1–M7: the mark per row, the header marks and
  the ⊘ note, "at end", the auto-open (pinned closed, a rebuild, a close, a
  reselect), the three read times, the header's `◆N` against the sub-tab's,
  and a Document-tab row moved by exactly the 14 pt gutter.
* **the harness**, the editor at 1440 × 862, dark, M, phase 1's fixture — one
  shape card of 6 s with two linear actions, 0.5–1.5 s ({video: {opacity:
  0.5}}) and 2.5–4.0 s ({video: {x: 100}}) — the card selected, the playhead
  at 1.0 s, action 1 selected and the Picture sub-tab showing. Rows H1–H4: the
  render is deterministic, Opacity's rail holds the action ink and no accent,
  the coral tick is 2 × 11 pt on it, and the gutter's ◆ is mint.

`--mutant marks` builds the probe over a COPY of `app/Sources` whose
`keyedPaths()` answers nothing. Exit 0 means rows of M1, M2, M3, M4 and M6
FAILED in the copy and no other row did.
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
import clip_inspector2_proof as ci2  # noqa: E402  (movie)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector3")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector3_probe.swift")
TICKS = e2.TICKS

WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT       # 1440 × 862
INSPECTOR_X = 1136                        # WIDTH − DS.panelWidth
SIDE = 10                                 # InspectorMetrics.inset
GUTTER = 14                               # InspectorMetrics.markGutter
LABEL = 76                                # InspectorMetrics.labelWidth
ROW_X = INSPECTOR_X + SIDE                # a row's leading edge
SLIDER_X = ROW_X + GUTTER + LABEL + 6     # a labelled row's first control: 96 pt in
# The first section's top: the pinned block with an action selected —
# `clip_inspector2_proof`'s header, lane, detail row and sub-tab strip.
SECTIONS_TOP = ci2.PINNED_TOP + ci2.HEADER_H + ci2.LANE_H + ci2.DETAIL_H + ci2.SUB_H
PLAYHEAD = 1.0

MUTANT_FILE = "InspectorMarks.swift"
MUTANT_ANCHOR = "        guard let action = selectedAction else { return [] }\n"
MUTANT_GROUPS = ("M1 ", "M2 ", "M3 ", "M4", "M6 ")

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    six = 6 * TICKS
    chrome = e2.project([
        e2.clip(2, 0, e2.GREY, name="Card", duration=six, actions=[
            ci.action(3, 0.5, 1.5, {"video": {"opacity": 0.5}}),
            ci.action(4, 2.5, 4.0, {"video": {"x": 100.0}})])])
    av = e2.project([
        ci.media_clip(2, 91, 0, [ci.action(10, 1, 2, {"audio": {"volume": 0.5}})],
                      video=True)], media=[ci2.movie(91, True)])
    card = e2.clip(2, 0, e2.GREY, name="Card", duration=six, actions=[
        ci.action(5, 1, 2, {"video": {"blend": "multiply",
                                      "filters": [{"kind": "blur", "amount": 1.0}]}})])
    card["video"]["filters"] = [{"kind": "blur", "amount": 0.5}]
    return {
        "chrome": e2.write_package("ci3-chrome", chrome),
        "av": e2.write_package("ci3-av", av),
        "keyed": e2.write_package("ci3-keyed", e2.project([card])),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`clip_inspector_proof.build_probe`'s swiftc line, over THIS phase's
    probe source (its module global names the file it compiles)."""
    ci.PROBE_SWIFT = PROBE_SWIFT
    return ci.build_probe(sources, out)


def probe_checks(sources, out, paths):
    print("\n1 — the probe: M1 rows, M2 headers, M3 at end, M4 auto-open, M5 read times, "
          "M6 count, M7 the gutter's 14 pt")
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
    check("the probe answers every M-row (M1–M7 present)",
          all(any(r["name"].startswith(f"M{n}") for r in rows) for n in range(1, 8)),
          f"{len(rows)} rows")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])
    return binary


# ---------------------------------------------------------------------------
# The harness.


def render(binary, package, out):
    args = [binary, package, out, "dark", str(WIDTH), str(HEIGHT), "0", str(PLAYHEAD), "1",
            "clip", "-", "-", "-", "0", "picture"]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out, None


def converted(probe, png):
    out = os.path.join(WORK, "converted.json")
    result = subprocess.run([probe, "--convert", png, out], capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None
    with open(out) as f:
        inks = json.load(f)
    if not all(len(inks.get(k, [])) == 3 for k in ("mint", "accent", "coral")):
        return None
    return inks


HARNESS_ROWS = [
    "H1 action 1 selected at 1.0 s, Picture, rendered twice → byte-identical PNGs",
    "H2 Opacity's rail holds the action ink (converted mint, ≥ 10·s px on its centreline) "
    "and no DS.accent pixel",
    "H3 a DS.playhead run on that rail exactly 2·s px wide",
    "H3 … and 11·s px tall",
    "H4 the gutter's ◆ — mint pixels in the Opacity row's first 14 pt — and none in the "
    "Scale row's",
]


def harness_checks(chrome, probe):
    print("\n2 — the harness: dark, 1440 × 862, M, action 1 selected at 1.0 s, Picture")
    binary, error = e2.build_harness()
    renders = {}
    for tag in ("a", "b"):
        if error:
            break
        renders[tag], error = render(binary, chrome, os.path.join(WORK, f"ci3-{tag}.png"))
    if error:
        for name in HARNESS_ROWS:
            check(name, False, error)
        return
    with open(renders["a"], "rb") as a, open(renders["b"], "rb") as b:
        check(HARNESS_ROWS[0], a.read() == b.read())
    image = e2.Image(renders["a"])
    s = image.scale
    ch = image.channels
    inks = converted(probe, renders["a"]) if probe else None
    if not inks:
        for name in HARNESS_ROWS[1:]:
            check(name, False, "the probe could not convert the inks to the PNG's space")
        return
    mint, accent, coral = (tuple(int(round(c)) for c in inks[k])
                           for k in ("mint", "accent", "coral"))
    print(f"       {os.path.relpath(renders['a'], ROOT)}: {image.width}×{image.height} px, "
          f"scale {s:g}, {inks['space']}: mint {mint}, accent {accent}, coral {coral}")

    def at(x, y):
        return tuple(image.rows[y][x * ch:x * ch + 3])

    # The gutter column, down the section stack: where its mint is, is the
    # Opacity row (the only keyed row on the tab).
    g0, g1 = int(ROW_X * s), int((ROW_X + GUTTER) * s)
    top, bottom = int(SECTIONS_TOP * s), int((SECTIONS_TOP + 400) * s)
    ys = [y for y in range(top, bottom)
          if any(ci.near(at(x, y), mint, 2) for x in range(g0, g1))]
    if not ys:
        for name in HARNESS_ROWS[1:]:
            check(name, False, f"no mint in the gutter column x {ROW_X}–{ROW_X + GUTTER} pt")
        return
    centre = (ys[0] + ys[-1]) // 2
    # Scale is the section's first row: 28 pt of header and 2 pt of inset down.
    scale_y = int((SECTIONS_TOP + 28 + 2 + 11) * s)
    scale_mint = sum(1 for y in range(scale_y - int(8 * s), scale_y + int(8 * s))
                     for x in range(g0, g1) if ci.near(at(x, y), mint, 2))
    check(HARNESS_ROWS[4], len(ys) >= 2 and scale_mint == 0 and abs(scale_y - centre) > 20 * s,
          f"mint rows y {ys[0] / s:g}–{ys[-1] / s:g} pt; {scale_mint} px in the Scale row at "
          f"{scale_y / s:g} pt")

    # The rail's centreline: the row inside ±3 pt of the ◆'s centre with the
    # most mint right of the label column.
    x0, x1 = int(SLIDER_X * s), int((INSPECTOR_X + 304 - SIDE) * s)

    def mint_in(y):
        return sum(1 for x in range(x0, x1) if ci.near(at(x, y), mint, 2))
    rail = max(range(centre - int(3 * s), centre + int(3 * s) + 1), key=mint_in)
    line = [at(x, rail) for x in range(x0, x1)]
    mints = sum(1 for p in line if ci.near(p, mint, 2))
    accents = sum(1 for p in line if ci.near(p, accent, 2))
    check(HARNESS_ROWS[1], mints >= 10 * s and accents == 0,
          f"rail y {rail / s:g} pt: {mints} mint px, {accents} accent px")

    runs = []
    for i, p in enumerate(line):
        if ci.near(p, coral, 2):
            if runs and runs[-1][1] == i:
                runs[-1][1] = i + 1
            else:
                runs.append([i, i + 1])
    widths = [b - a for a, b in runs]
    k = int(round(s))
    check(HARNESS_ROWS[2], widths == [2 * k], f"coral runs {[(x0 + a, b - a) for a, b in runs]}")
    if not runs:
        check(HARNESS_ROWS[3], False, "no coral run")
        return
    column = x0 + runs[0][0]
    y0 = y1 = rail
    while y0 > 0 and ci.near(at(column, y0 - 1), coral, 2):
        y0 -= 1
    while y1 + 1 < image.height and ci.near(at(column, y1 + 1), coral, 2):
        y1 += 1
    check(HARNESS_ROWS[3], y1 - y0 + 1 == 11 * k, f"{y1 - y0 + 1} px, y {y0}–{y1}")


# ---------------------------------------------------------------------------


def mutant():
    began = time.time()
    with tempfile.TemporaryDirectory(prefix="framejob-clip-inspector3-marks-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, MUTANT_FILE)
        with open(path) as f:
            text = f.read()
        if text.count(MUTANT_ANCHOR) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(MUTANT_ANCHOR)} times")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(MUTANT_ANCHOR, MUTANT_ANCHOR + "        return []\n"
                                 "        // mutant: nothing is keyed\n"
                                 "        _ = action\n", 1))
        print(f"MUTANT marks: keyedPaths() answers nothing, in {sources}")
        paths = packages()
        probe_checks(sources, os.path.join(temp, "out"), paths)
    built = bool(RESULTS) and RESULTS[0][1]
    failed = [n for n, ok in RESULTS if not ok]
    groups = {g: [n for n in failed if n.startswith(g)] for g in MUTANT_GROUPS}
    others = [n for n in failed if not n.startswith(MUTANT_GROUPS)]
    elapsed = time.time() - began
    if built and all(groups.values()) and not others:
        print(f"MUTANT PASS: marks — {len(failed)} row(s) of M1, M2, M3, M4 and M6 FAILED in "
              f"the copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: marks — built {built}, failures per group "
          f"{ {g: len(v) for g, v in groups.items()} }, other failures {others}, "
          f"{elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] == "marks":
        return mutant()
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Road map 9, phase 3a — the row marks")
    paths = packages()
    probe = probe_checks(
        os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"), paths)
    harness_checks(paths["chrome"], probe)
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
