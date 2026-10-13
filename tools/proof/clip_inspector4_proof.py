#!/usr/bin/env python3
"""Road map 9, phase 3b — Reset/Clear, the row ×, the row menus and the
refusal strip.

    python3 tools/proof/clip_inspector4_proof.py
    python3 tools/proof/clip_inspector4_proof.py --mutant reset

Two instruments, `clip_inspector3_proof.py`'s shape:

* **the probe**, `clip_inspector4_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `swift_build.py`'s line (a probe that will not build is a scored
  FAILURE, never an exit). Rows R1–R8: Reset shown only when a section
  differs (R1), the summary's three inks (R2), Clear and what it removes
  (R3), the row's × on hover (R4), the row menus, never read after a hover
  (R5), the `.defaults` read mode (R6), the refusal strip in a real editor
  (R7) and the sections whose `differs` is explicit (R8).
* **the harness**, the editor at 1440 × 862, dark, M, one shape card of 6 s
  with two linear actions (0.5–1.5 s {video: {opacity: 0.5}}, 2.5–4.0 s
  {video: {x: 100}}), the card selected, Picture showing. Rows H1–H3: the
  render is deterministic; with no action (playhead 5 s) the Transform
  header's trailing 70 pt hold no button; with action 1 selected (playhead
  1 s) they hold the Clear button.

  "No button" is read as: no column of that region carries a run of
  non-fill pixels taller than 14 pt. The summary is drawn there once the
  button is hidden (it stops short of the VISIBLE button only), and its mono
  10 glyphs are under 12 pt tall; a button is a 22 pt box, whose edges and
  face run the region's height.

`--mutant reset` builds the probe AND the harness over a COPY of
`app/Sources` whose `InspectorRowDefault.derived` answers `differs` true
always. Exit 0 means EXACTLY the rows in `MUTANT_EXPECTED` failed in the copy
and nothing else did — R8's explicit `differs` rows hold, which is what shows
that path does not lean on `derived`.
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
import clip_inspector_proof as ci  # noqa: E402  (action, media_clip, build_probe)
import clip_inspector2_proof as ci2  # noqa: E402  (movie, text_clip, pinned metrics)
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector4")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector4_probe.swift")
HARNESS_MAIN = os.path.join(HERE, "harness", "main.swift")
TICKS = e2.TICKS

WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT       # 1440 × 862
INSPECTOR_X = 1136                        # WIDTH − DS.panelWidth
FILL_X = INSPECTOR_X + 150                # inside the header, between title and summary
HEADER = 28                               # InspectorMetrics.headerHeight
TRAILING = 70                             # the region H2 and H3 read
# The first section's header top: the pinned block, without and with an
# action selected (`clip_inspector2_proof`'s header, lane, detail row, strip).
TOP_NO_ACTION = ci2.PINNED_TOP + ci2.HEADER_H + ci2.LANE_H + ci2.SUB_H
TOP_ACTION = TOP_NO_ACTION + ci2.DETAIL_H
TOLERANCE = 10                            # per channel, against the header's fill
NO_BUTTON_RUN = 14                        # pt; a glyph is shorter
BUTTON_RUN = 18                           # pt; a 22 pt button's edge is longer

MUTANT_FILE = "InspectorMarks.swift"
MUTANT_ANCHOR = "                return read() != binding.at(.defaults, read)\n"
MUTANT_EXPECTED = [
    "R1 no action: Transform at its default shows no button (Reset hidden)",
    "R1 … Shadow, off, shows no button (Reset hidden)",
    "R2 … Transform's summary at its default is DS.textFaint",
    "R5 … at 100% the item is there and disabled",
]

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
    text = ci2.text_clip(2)
    text["video"]["scale"] = 2.0
    text["text"]["font"] = "Menlo-Regular"
    filters = e2.clip(2, 0, e2.GREY, name="Card", duration=six)
    filters["video"]["filters"] = [{"kind": "blur", "amount": 0.0}]
    ellipse = e2.clip(2, 0, e2.GREY, name="Card", duration=six)
    ellipse["shape"].update({"kind": "ellipse", "width": 500.0, "height": 500.0})
    stroke = e2.clip(2, 0, e2.GREY, name="Card", duration=six)
    stroke["shape"]["stroke"] = {"width": 12.0, "color": [1.0, 0.0, 0.0, 1.0]}
    return {
        "chrome": e2.write_package("ci4-chrome", chrome),
        "av": e2.write_package("ci4-av", av),
        "text": e2.write_package("ci4-text", e2.project([text])),
        "filters": e2.write_package("ci4-filters", e2.project([filters])),
        "ellipse": e2.write_package("ci4-ellipse", e2.project([ellipse])),
        "stroke": e2.write_package("ci4-stroke", e2.project([stroke])),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`clip_inspector_proof.build_probe`'s build, over THIS phase's
    probe source (its module global names the file it compiles)."""
    ci.PROBE_SWIFT = PROBE_SWIFT
    return ci.build_probe(sources, out)


def probe_checks(sources, out, paths):
    print("\n1 — the probe: R1 Reset, R2 inks, R3 Clear, R4 the ×, R5 menus, R6 defaults, "
          "R7 the refusal strip, R8 explicit differs")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
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
        return
    with open(answer) as f:
        rows = json.load(f)["rows"]
    check("the probe answers every R-row (R1–R8 present)",
          all(any(r["name"].startswith(f"R{n} ") for r in rows) for n in range(1, 9)),
          f"{len(rows)} rows")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---------------------------------------------------------------------------
# The harness.


def build_harness(sources, out):
    """`swift_build.build` over `sources` — the tree's own for a
    normal run, the mutant copy for `--mutant`. A harness that will not build
    is a scored failure."""
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    os.makedirs(out, exist_ok=True)
    binary = os.path.join(out, "harness")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    try:
        built = swift_build.build(sources=swift + [HARNESS_MAIN], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["(no error lines)"])
    for folder in ("Fonts", "Models"):
        if built.reused and os.path.isdir(os.path.join(out, folder)):
            continue
        shutil.rmtree(os.path.join(out, folder), ignore_errors=True)
        shutil.copytree(os.path.join(ROOT, "app", "Resources", folder),
                        os.path.join(out, folder))
    if not built.reused:
        print(f"  harness built in {built.seconds:.0f} s")
    return binary, None


def render(binary, package, out, playhead, action):
    args = [binary, package, out, "dark", str(WIDTH), str(HEIGHT), "0", str(playhead), "1",
            "clip", "-", "-", "-", action, "picture"]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out, None


HARNESS_ROWS = [
    "H1 no action at 5 s, Picture, rendered twice → byte-identical PNGs",
    f"H2 no action: the Transform header's trailing {TRAILING} pt hold no button (no run of "
    f"non-fill pixels ≥ {NO_BUTTON_RUN} pt in any column)",
    f"H3 action 1 selected at 1 s: that region holds the Clear button (a run ≥ {BUTTON_RUN} pt)",
]


def tallest_run(path, top):
    """The tallest vertical run, in points, of pixels unlike the header's own
    fill inside the Transform header's trailing region, and the fill. The
    header's right edge is found, not assumed: the scroll view keeps a
    scroller's width of the panel to the header's right."""
    image = e2.Image(path)
    s, ch = image.scale, image.channels

    def at(x, y):
        return tuple(image.rows[y][x * ch:x * ch + 3])
    # Above a button, which is 22 pt centred in the 28 pt header.
    y = int((top + 1.5) * s)
    fill = at(int(FILL_X * s), y)
    right = int(FILL_X * s)
    while right + 1 < image.width and ci.near(at(right + 1, y), fill, 2):
        right += 1
    x0, x1 = right - int(TRAILING * s), right
    y0, y1 = int((top + 1) * s), int((top + HEADER - 2) * s)
    best = 0
    for x in range(x0, x1):
        run = 0
        for y in range(y0, y1):
            if ci.near(at(x, y), fill, TOLERANCE):
                run = 0
            else:
                run += 1
                best = max(best, run)
    return best / s, fill, (right + 1) / s


def harness_checks(sources, out, chrome):
    print("\n2 — the harness: dark, 1440 × 862, M, Picture; no action at 5 s, action 1 at 1 s")
    binary, error = build_harness(sources, out)
    renders = {}
    for tag, playhead, action in (("a", 5, "-"), ("b", 5, "-"), ("keyed", 1, "0")):
        if error:
            break
        renders[tag], error = render(binary, chrome, os.path.join(out, f"ci4-{tag}.png"),
                                     playhead, action)
    if error:
        for name in HARNESS_ROWS:
            check(name, False, error)
        return
    with open(renders["a"], "rb") as a, open(renders["b"], "rb") as b:
        check(HARNESS_ROWS[0], a.read() == b.read())
    run, fill, right = tallest_run(renders["a"], TOP_NO_ACTION)
    check(HARNESS_ROWS[1], run < NO_BUTTON_RUN,
          f"{os.path.relpath(renders['a'], ROOT)}: header fill {fill} to x {right:g} pt, "
          f"tallest run {run:g} pt")
    run, fill, right = tallest_run(renders["keyed"], TOP_ACTION)
    check(HARNESS_ROWS[2], run >= BUTTON_RUN,
          f"{os.path.relpath(renders['keyed'], ROOT)}: header fill {fill} to x {right:g} pt, "
          f"tallest run {run:g} pt")


# ---------------------------------------------------------------------------


def mutant():
    began = time.time()
    with tempfile.TemporaryDirectory(prefix="framejob-clip-inspector4-reset-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, MUTANT_FILE)
        with open(path) as f:
            text = f.read()
        if text.count(MUTANT_ANCHOR) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(MUTANT_ANCHOR)} times")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(
                MUTANT_ANCHOR,
                "                // mutant: every derived default differs\n"
                "                _ = read\n"
                "                return true\n", 1))
        print(f"MUTANT reset: InspectorRowDefault.derived differs always, in {sources}")
        paths = packages()
        probe_checks(sources, os.path.join(temp, "probe"), paths)
        harness_checks(sources, os.path.join(temp, "harness"), paths["chrome"])
    failed = [n for n, ok in RESULTS if not ok]
    expected = MUTANT_EXPECTED + [HARNESS_ROWS[1]]
    built = bool(RESULTS) and RESULTS[0][1]
    elapsed = time.time() - began
    if built and sorted(failed) == sorted(expected):
        print(f"MUTANT PASS: reset — exactly the {len(expected)} expected row(s) FAILED in the "
              f"copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: reset — built {built}; missing failures "
          f"{[n for n in expected if n not in failed]}; unexpected failures "
          f"{[n for n in failed if n not in expected]}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] == "reset":
        return mutant()
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Road map 9, phase 3b — Reset/Clear, the row ×, the row menus, the refusal strip")
    paths = packages()
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"), paths)
    harness_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "harness"),
                   paths["chrome"])
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
