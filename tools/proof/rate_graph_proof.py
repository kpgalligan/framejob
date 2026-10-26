#!/usr/bin/env python3
"""#339 (spec §11 SR-26) — a speed ramp's rate graph on the action lane.

    python3 tools/proof/rate_graph_proof.py
    python3 tools/proof/rate_graph_proof.py --mutant <name>

Two instruments:

* **the probe**, `rate_graph_probe.swift`, compiled AS `main.swift` over every
  file in `app/Sources` but the app's own `main.swift` on `swift_build.py`'s
  line (a probe that will not build is a scored FAILURE, never an exit), in
  process over a `ReelProject.new` project. Rows R1–R7: the core's `rate`
  list decoded into `SourceMap.rate` against the closed-form oracle; no line
  for a constant clip, a ramped clip whose rate never moves, a nil map and a
  text clip; the line's geometry on a speed-up and a slow-down; the band's
  curve under the line; `SourceMap(json:)`'s check; and the painter's two
  strokes in a flipped 1× bitmap.
* **the harness** (`harness/build.sh`), dark, 1440 × 862, over two packages
  that differ only in one Speed action's end rate: U (×1 → ×2 over
  [1 s, 3 s) of a 5 s media clip) and its twin F (→ ×1, ramped but the rate
  never moving), the clip selected, the Clip tab, the playhead at 0.5 s
  (before the ramp, so the Speed section reads ×1 in both). H1 at size L: the
  two PNGs differ, every differing pixel lies in the clip's timeline action
  lane or the Clip tab's lane row, and there are differences in both. H2 at
  size S: differences only in the Clip tab's lane row (the timeline draws no
  line at S).

`--mutant <name>` undoes one decision in a COPY and exit 0 means exactly the
rows that decision answers FAILED there and no other did. Swift mutants build
the probe (and, for `timeline-unwired`, the harness) over a copy of
`app/Sources`; core mutants run `cargo test --release --test
ramp_rate_profile` over a copy of `core/` with its own target dir and pass
when a test there fails:

* `rate-edges-only` (core) — a ramp piece pushes only its edges.
* `no-rate-key` (core) — `source_map` omits `rate`.
* `flat-drawn` — `RateGraph.points` drops its max > min test; R2 fails.
* `y-inverted` — y measured from `minY`; R3 and R4 fail (R7 paints
  hand-built points).
* `curve-kept` — `bandCurve` always answers the curve; R5 fails.
* `rate-unchecked` — the rate check drops its first-tick test; R6 fails.
* `timeline-unwired` — `drawActionBands` never calls `RateGraph.draw`; H1
  fails.

An anchor that does not occur exactly once in its file is `MUTANT FAILURE`,
exit 2.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (Image, changed_pixels, project, write_package, …)
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "rate-graph")
PROBE_SWIFT = os.path.join(HERE, "rate_graph_probe.swift")
TICKS = e2.TICKS
PROBE_WALL = 300

WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT       # 1440 × 862
CLIP_X0 = e2.CLIP_X0                      # 132: time zero
ZOOM = e2.ZOOM                            # 42 pt per second
LANE_TOP = e2.STRIP_Y + e2.STRIP_H        # 643: the content's top, under the strip
LANE_HEIGHTS = [5, 12, 18]                # DS.actionLaneHeights
INSPECTOR_X = e2.INSPECTOR_X              # 1136
LANE_X0 = INSPECTOR_X + 10 + 40 + 4       # the Clip tab lane: after the Clip chip
LANE_ROW = 28                             # ActionLaneView.laneRow
LANE_ROW_Y = 152                          # its top in the window: the band clip_inspector_proof
                                          # measures at 156–176 pt is this row inset 4 and 4
CLIP_SECONDS = 5
PLAYHEAD = 0.5

# mode → (file, anchor, replacement, what the copy does, the rows it must fail)
SWIFT_MUTANTS = {
    "flat-drawn": (
        "RateGraph.swift", "              fastest > slowest\n", "              true\n",
        "RateGraph.points draws a line whose rate never moves",
        lambda name: name.startswith("R2 ")),
    "y-inverted": (
        "RateGraph.swift",
        "                y: rect.maxY - CGFloat((point.rate - slowest) / range) * rect.height)",
        "                y: rect.minY + CGFloat((point.rate - slowest) / range) * rect.height)",
        "RateGraph.points measures y from minY",
        lambda name: name.startswith(("R3 ", "R4 "))),
    "curve-kept": (
        "RateGraph.swift", "        graphed && action.end.speed != nil ? nil : action.curve\n",
        "        action.curve\n",
        "bandCurve always answers the action's curve",
        lambda name: name.startswith("R5 ")),
    "rate-unchecked": (
        "SourceMap.swift",
        "        guard rate.count >= 2, rate[0].tick == 0, rate[rate.count - 1].tick == end else {",
        "        guard rate.count >= 2, rate[rate.count - 1].tick == end else {",
        "SourceMap's rate check drops its first-tick test",
        lambda name: name.startswith("R6 ")),
    "timeline-unwired": (
        "TimelineActionBands.swift", "        if let graph { RateGraph.draw(graph, in: lane) }\n",
        "",
        "drawActionBands never draws the line",
        lambda name: name.startswith("H1 ")),
}

# mode → (file under core/src, anchor, replacement, what the copy does)
CORE_MUTANTS = {
    "rate-edges-only": (
        "speed_map.rs", "                    for k in 0..=RATE_SAMPLES {\n",
        "                    for k in [0, RATE_SAMPLES] {\n",
        "a ramp piece pushes only its edges"),
    "no-rate-key": (
        "speed_segments.rs", "        if let Some(rate) = rate {\n",
        "        if let Some(rate) = rate.filter(|_| false) {\n",
        "source_map omits rate"),
}

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


# ---------------------------------------------------------------------------
# The packages.


def media_clip(end_rate):
    return {
        "id": 5, "track": 1, "start": 0, "duration": CLIP_SECONDS * TICKS,
        "source": {"kind": "media", "media": 91, "in": 0, "reversed": False},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": e2.video_props(), "audio": {}, "text": None, "shape": None,
        "actions": [{"id": 13, "start": TICKS, "duration": 2 * TICKS, "curve": "linear",
                     "end": {"speed": end_rate}}],
        "transition_in": None, "name": None, "label": None,
    }


MEDIA = [{
    "id": 91, "path": "/fixtures/rate-graph.mov", "kind": "video",
    "duration": 60 * TICKS, "width": 1920, "height": 1080, "fps": [30, 1],
    "has_video": True, "has_audio": True,
}]


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    paths = {}
    for name, rate in (("U", 2.0), ("F", 1.0)):
        body = e2.project([media_clip(rate)], media=MEDIA)
        body["version"] = 27
        paths[name] = e2.write_package(f"rate-graph-{name}", body)
    return paths


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    shutil.copyfile(PROBE_SWIFT, entry)
    binary = os.path.join(out, "rate-graph-probe")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    try:
        built = swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed: " + "; ".join(
            [str(error)] + (errors[:6] or ["(no error lines)"]))
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s")
    return binary, None


def probe_checks(sources, out):
    print("\n1 — the probe: R1 the rate list, R2 no line, R3/R4 geometry, R5 the band's curve, "
          "R6 the check, R7 the painter")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
    try:
        ran = subprocess.run([binary], capture_output=True, text=True, timeout=PROBE_WALL,
                             cwd=out)
    except subprocess.TimeoutExpired:
        check("the probe runs", False, f"no answer within {PROBE_WALL} s")
        return
    try:
        answer = json.loads(ran.stdout)
    except ValueError:
        check("the probe runs", False, f"exit {ran.returncode}: {ran.stderr[-400:]}")
        return
    check("the probe's fixtures are made", not answer.get("problems"),
          "; ".join(answer.get("problems", [])))
    rows = answer.get("rows", [])
    check("the probe answers every R-row (R1–R7 present)",
          all(any(r["name"].startswith(f"R{n} ") for r in rows) for n in range(1, 8)),
          f"{len(rows)} rows")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---------------------------------------------------------------------------
# The harness.


def build_harness(sources):
    """`build.sh`'s harness over `app/Sources`, or one over `sources` (a
    mutant's copy) built in its own folder. (binary, None) or (None, why)."""
    if sources is None:
        return e2.build_harness()
    here = os.path.join(os.path.dirname(sources), "harness")
    os.makedirs(here, exist_ok=True)
    files = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    binary = os.path.join(here, "harness")
    try:
        swift_build.build(sources=files + [os.path.join(HERE, "harness", "main.swift")],
                          output=binary, defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc failed: " + "\n".join(error.diagnostics).strip()[-600:]
    resources = os.path.join(ROOT, "app", "Resources")
    shutil.copytree(os.path.join(resources, "Fonts"), os.path.join(here, "Fonts"))
    shutil.copytree(os.path.join(resources, "Models"), os.path.join(here, "Models"))
    shutil.copy(os.path.join(ROOT, "docs", "graphics-api.md"),
                os.path.join(here, "GraphicsAPI.md"))
    shutil.copy(os.path.join(ROOT, "docs", "graphics-api.d.ts"),
                os.path.join(here, "GraphicsAPI.d.ts"))
    return binary, None


def render(binary, package, out, size):
    args = [binary, package, out, "dark", str(WIDTH), str(HEIGHT), "0", str(PLAYHEAD),
            str(size), "clip", "-", "-", "-", "-"]
    if os.path.exists(out):
        os.remove(out)
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return e2.Image(out), None


def timeline_lane(size):
    """The clip's action lane on the timeline, in points: (x0, y0, x1, y1)."""
    return (CLIP_X0, LANE_TOP, CLIP_X0 + CLIP_SECONDS * ZOOM, LANE_TOP + LANE_HEIGHTS[size])


def inspector_row():
    """The Clip tab's lane row, in points: (x0, y0, x1, y1). Its right end is
    the window's, since the pane's width depends on whether the host shows
    legacy scrollers."""
    return (LANE_X0, LANE_ROW_Y, WIDTH, LANE_ROW_Y + LANE_ROW)


def harness_checks(sources, out):
    print("\n2 — the harness: U against its twin F, dark, 1440 × 862, the Clip tab")
    rows = {
        2: "H1 at L: the PNGs differ only in the clip's timeline action lane and the Clip "
           "tab's lane row, and in both",
        0: "H2 at S: the PNGs differ only in the Clip tab's lane row",
    }
    binary, error = build_harness(sources)
    if binary is None:
        for name in rows.values():
            check(name, False, error)
        return
    paths = packages()
    for size, name in rows.items():
        images = {}
        for twin in ("U", "F"):
            image, error = render(binary, paths[twin], os.path.join(
                out, f"rate-graph-{twin}-{size}.png"), size)
            if image is None:
                break
            images[twin] = image
        if len(images) != 2:
            check(name, False, error)
            continue
        changed = e2.changed_pixels(images["U"], images["F"])
        s = images["U"].scale
        lane, row = timeline_lane(size), inspector_row()
        in_lane, in_row, stray = [], [], []
        for x, y in changed:
            px, py = x / s, y / s
            if lane[0] <= px < lane[2] and lane[1] <= py < lane[3]:
                in_lane.append((x, y))
            elif row[0] <= px < row[2] and row[1] <= py < row[3]:
                in_row.append((x, y))
            else:
                stray.append((x, y))
        want_lane = size == 2
        ok = bool(changed) and not stray and bool(in_row) and bool(in_lane) == want_lane
        span = (f"y {min(y for _, y in in_row) / s:g}–{(max(y for _, y in in_row) + 1) / s:g} pt"
                if in_row else "none")
        detail = (f"{len(changed)} px differ: {len(in_lane)} in the timeline lane {lane}, "
                  f"{len(in_row)} in the Clip tab's lane row {row} ({span}), "
                  f"{len(stray)} elsewhere")
        if stray:
            detail += "\n" + e2.describe(e2.clusters(stray), s)
        check(name, ok, detail)


# ---------------------------------------------------------------------------


def swift_mutant(mode):
    began = time.time()
    file, anchor, replacement, note, expected = SWIFT_MUTANTS[mode]
    with tempfile.TemporaryDirectory(prefix=f"framejob-rate-graph-{mode}-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, file)
        with open(path) as f:
            text = f.read()
        if text.count(anchor) != 1:
            print(f"MUTANT FAILURE: {mode} — the anchor occurs {text.count(anchor)} times "
                  f"in {file}")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(anchor, replacement))
        print(f"MUTANT {mode}: {note}, in {sources}")
        probe_checks(sources, os.path.join(temp, "probe"))
        if mode == "timeline-unwired":
            out = os.path.join(temp, "png")
            os.makedirs(out)
            harness_checks(sources, out)
    built = bool(RESULTS) and RESULTS[0][1]
    failed = [n for n, ok in RESULTS if not ok]
    wanted = [n for n in failed if expected(n)]
    others = [n for n in failed if not expected(n)]
    elapsed = time.time() - began
    if built and wanted and not others:
        print(f"MUTANT PASS: {mode} — {len(wanted)} row(s) it answers FAILED in the copy "
              f"and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {mode} — built {built}, expected failures {wanted}, other "
          f"failures {others}, {elapsed:.0f} s")
    return 1


def core_mutant(mode):
    began = time.time()
    file, anchor, replacement, note = CORE_MUTANTS[mode]
    with tempfile.TemporaryDirectory(prefix=f"framejob-rate-graph-{mode}-") as temp:
        core = os.path.join(temp, "core")
        shutil.copytree(os.path.join(ROOT, "core"), core,
                        ignore=shutil.ignore_patterns("target", ".git", ".DS_Store"))
        # The core's path dependency on `graphic`, linked beside the copy:
        # read, never written — the build goes to the copy's own target dir.
        os.symlink(os.path.join(ROOT, "graphic"), os.path.join(temp, "graphic"))
        path = os.path.join(core, "src", file)
        with open(path) as f:
            text = f.read()
        if text.count(anchor) != 1:
            print(f"MUTANT FAILURE: {mode} — the anchor occurs {text.count(anchor)} times "
                  f"in {file}")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(anchor, replacement))
        print(f"MUTANT {mode}: {note}, in {core}")
        environment = dict(os.environ, CARGO_TARGET_DIR=os.path.join(temp, "target"))
        command = ["cargo", "test", "--release", "--test", "ramp_rate_profile"]
        try:
            result = subprocess.run(command, cwd=core, env=environment, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                    timeout=900, start_new_session=True)
        except subprocess.TimeoutExpired:
            print(f"MUTANT FAILURE: {mode}: cargo did not finish in 900 s")
            return 2
    output = result.stdout
    compiled = "Finished `release` profile" in output
    failed = [line for line in output.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    print("\n".join(line for line in output.splitlines()
                    if line.startswith(("test ", "test result", "error"))))
    elapsed = time.time() - began
    if compiled and failed and result.returncode != 0:
        print(f"MUTANT PASS: {mode} — {len(failed)} ramp_rate_profile test(s) FAILED in the "
              f"copy, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {mode} — compiled {compiled}, failed {failed}, "
          f"rc {result.returncode}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant":
        if sys.argv[2] in SWIFT_MUTANTS:
            return swift_mutant(sys.argv[2])
        if sys.argv[2] in CORE_MUTANTS:
            return core_mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#339 — a speed ramp's rate graph on the action lane")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        check("the core library is built", False, f"{lib} is missing — run `make rust`")
    else:
        probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"))
        harness_checks(None, WORK)
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
