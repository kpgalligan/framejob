#!/usr/bin/env python3
"""Issue batch B25 (#85, spec §11 CI-16): a selected clip's obscure regions are
drawn on the canvas with a move grip and eight resize handles, a drag is ONE
`video.obscure` write and ONE undo step, and Esc during any canvas drag puts
the press's state back with no step.

    python3 tools/proof/obscure_handles_probe.py [--sources DIR]
    python3 tools/proof/obscure_handles_probe.py --baseline COMMIT
    python3 tools/proof/obscure_handles_probe.py --mutant NAME

`obscure_handles_probe.swift` is compiled AS `main.swift` over `--sources`
(default `app/Sources`) minus the app's `main.swift`, on `swift_build.py`'s
line (`-D FRAMEJOB_DEV_TOOLS`, the bridging header, `-lframejob_core`),
with `Compositor.metal` built into a `default.metallib` beside it
(`editor_keys_undo_proof.build_shader`), and run once over four packages this
script writes under `work/obscure-handles/fixtures/` at the header's
`RC_FORMAT_VERSION`: canvas 1920 × 1080 @ 30, black; clip 2 a grey 800 × 450
rectangle, 0–6 s, video x 120, y −60, scale 0.6, rotation 30, crop l 40 b 30;
R0 = rect (−150, −60) 300 × 180, feather 20, pixelate, 1; R1 = ellipse
(180, 90) 200 × 140, feather 10, blur, 0.8.
  regions  R0, R1; playhead 1 s; clip 2 selected
  action   regions plus action 3 at 2–4 s ending {video: {x: 200}}; playhead
           3 s, the action selected
  short    action with the end {video: {obscure: [R0]}} instead
  cover    one rect region (0, 0) 760 × 420 (the cropped rect itself)
A travel of dv view points is `ds = R(−θ)(dv / k) / s` source pixels (θ 30°,
k the canvas's points per pixel, s 0.6), tolerance 0.01 px. "One step" is the
undo name, one undo back to the fixture's JSON exactly, then nothing left to
undo, and no live edit after the release.

Rows:
  B0  the probe builds.
  F0  CONTROL: every package opens, the box is at rotation 30 and scale 0.6,
      the lists read back (short's end list has one entry), every region edge
      on screen is ≥ 24 pt, and cover's topRight grip is within 0.5 pt of the
      layer's topRight handle. The split is pinned (an argument-domain
      inspector width 304, timeline height 300, inspector shown; B32), and
      the detail ends with the margin, the shortest edge − 24 pt.
  D0  CONTROL: nothing selected, the overlay has alpha 0 within ±1 px of each
      region edge's ¼ and ¾ points and each centre.
  D1  selected: the same points all carry ink.
  M1  R0's centre dragged (30, 20) pt in 3 ticks: R0's centre moves by ds, its
      other fields, R1 and every other key unchanged; one "Move Region" step.
  M2  R1's bottomRight dragged (24, 12) pt: its top-left is kept, its
      bottom-right moves by ds; one "Resize Region" step.
  M3  ⌥ on R0's right handle, (20, 0) pt: centre and height kept, width grows
      by 2 × ds.x; one step.
  X0  an EXISTING session: the body pressed at source (−300, 150) and dragged
      (20, 0) pt in 2 ticks (x changed and live mid-drag), then Esc: the
      fixture's JSON, nothing to undo, no live edit, no move session.
  X1  R1's centre dragged (15, 0) pt (R1 moved and live mid-drag), then Esc:
      X0's four answers.
  T1  action: M1's drag writes actions[0].end.video.obscure = [R0 + ds, R1]
      and leaves the base list alone; one step.
  G1  short: ink on both regions' edges, alpha 0 at both centres (no grips);
      a drag from R0's centre by (20, 0) pt is one "Move" step with the base
      list and the end list unchanged.
  C1  CONTROL: the body at source (−300, 150) dragged (20, 0) pt: "Move", x
      changes, the list is unchanged.
  C2  CONTROL: cover — a press on the layer's topRight handle sets
      `canvas.scaling`; after the drag the step is "Scale", the list unchanged.
  L1  a `get_project` submitted on `AgentLane.shared` mid-drag of R0's centre
      has no answer in a 0.5 s hold, and after the release answers within
      10 s with R0 moved.
  H1  plain run only: `harness/build.sh`, then `regions` rendered light
      (`… 1440 862 0 1 1 clip`) twice, byte-identical; the path is printed.
  H2  the same, dark.

Exit (rule R). A plain run exits 0 iff every row passed and 1 otherwise (a
build failure is B0's FAIL). `--baseline COMMIT` builds the same probe over
`git archive COMMIT app/Sources` with the CURRENT staticlib: 1 CAUGHT when
exactly D1 M1 M2 M3 X0 X1 T1 G1 L1 fail and F0 D0 C1 C2 pass, 0 SURVIVED
otherwise, 2 NOT PERFORMED when the archive, the build or the run failed, a
row was not written, or a control failed. `--mutant NAME` edits a copy of
`--sources`: 1 caught (every row it names failed), 0 survived (one passed),
2 not performed (an anchor not found exactly once, the copy did not build,
or any row is an instrument failure).
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (video_props, project, write_package)
import editor_keys_undo_proof as eku  # noqa: E402  (build_shader)
import reference_build  # noqa: E402
import swift_build  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/obscure-handles"
PROBE = ROOT / "tools/proof/obscure_handles_probe.swift"
HEADER = ROOT / "core/include/framejob_core.h"
HARNESS = ROOT / "tools/proof/harness/build.sh"
PROBE_ROWS = ["F0", "D0", "D1", "M1", "M2", "M3", "X0", "X1", "T1", "G1", "C1", "C2", "L1"]
CONTROLS = ["F0", "D0", "C1", "C2"]
BASELINE_EXPECTED = ["D1", "M1", "M2", "M3", "X0", "X1", "T1", "G1", "L1"]
BUILD_WALL = 900
RUN_WALL = 300
HARNESS_WALL = 900
TICKS = e2.TICKS

# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "no-draw": (["D1", "G1"], [
        ("PreviewCanvasView.swift", "        drawObscureRegions()\n", "")]),
    "canvas-delta": (["M1", "M2", "M3"], [
        ("CanvasObscureSession.swift", "let at = frame.sourcePoint(point)",
         "let at = CGPoint(x: grab.x + point.x - frame.canvasPoint(source: grab).x, "
         "y: grab.y + point.y - frame.canvasPoint(source: grab).y)")]),
    "no-live-end": (["M1", "M2"], [
        ("PreviewCanvasView.swift",
         "            obscureDrag = nil\n            onLiveEnd?(session.undoName)\n",
         "            obscureDrag = nil\n            _ = session\n")]),
    "grips-first": (["C2"], [
        ("PreviewCanvasView.swift", "found.yieldsToObscureGrip", "true")]),
    "no-count-gate": (["G1"], [
        ("PreviewCanvasView+Obscure.swift",
         "return list.count == box.video.obscure.count ? list : nil", "return list")]),
    "cancel-commits": (["X0", "X1"], [
        ("PreviewCanvasView.swift", "        onLiveCancel?()", "        onLiveEnd?(\"Cancel\")")]),
}


def run(command, timeout, env=None):
    return subprocess.run(command, capture_output=True, text=True, timeout=timeout, env=env)


def format_version():
    found = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    return int(found.group(1)) if found else 10


# ---------------------------------------------------------------------------
# The fixtures.

R0 = {"shape": "rect", "x": -150.0, "y": -60.0, "width": 300.0, "height": 180.0,
      "feather": 20.0, "kind": "pixelate", "amount": 1.0}
R1 = {"shape": "ellipse", "x": 180.0, "y": 90.0, "width": 200.0, "height": 140.0,
      "feather": 10.0, "kind": "blur", "amount": 0.8}
COVER = {"shape": "rect", "x": 0.0, "y": 0.0, "width": 760.0, "height": 420.0,
         "feather": 20.0, "kind": "pixelate", "amount": 1.0}


def fixture_clip(regions, end=None):
    clip = e2.clip(2, 0, e2.GREY, duration=6 * TICKS)
    clip["shape"]["width"] = 800.0
    clip["shape"]["height"] = 450.0
    video = clip["video"]
    video.update({"x": 120.0, "y": -60.0, "scale": 0.6, "rotation": 30.0,
                  "crop": {"l": 40.0, "t": 0.0, "r": 0.0, "b": 30.0},
                  "obscure": [dict(r) for r in regions]})
    if end is not None:
        clip["actions"] = [{"id": 3, "start": 2 * TICKS, "duration": 2 * TICKS,
                            "curve": "linear", "end": end}]
    return clip


def packages():
    fixtures = WORK / "fixtures"
    fixtures.mkdir(parents=True, exist_ok=True)
    e2.CHROME = str(fixtures)
    version = format_version()

    def package(name, clip):
        body = e2.project([clip])
        body["version"] = version
        return e2.write_package(name, body)

    return {
        "regions": package("regions", fixture_clip([R0, R1])),
        "action": package("action", fixture_clip([R0, R1], {"video": {"x": 200.0}})),
        "short": package("short", fixture_clip([R0, R1], {"video": {"obscure": [dict(R0)]}})),
        "cover": package("cover", fixture_clip([COVER])),
    }


# ---------------------------------------------------------------------------
# The probe.

def build(sources, here):
    """(binary, None) or (None, why)."""
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "obscure-handles-probe"
    shader, why = eku.build_shader(str(here), sources.parents[1])
    if shader is None:
        return None, why
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, f"app source set incomplete ({len(swift)} files in {sources})"
    lib = ROOT / "core/target/release/libframejob_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        swift_build.build(sources=swift + [entry], output=binary,
                          defines=reference_build.tree_defines(sources.parents[1],
                                                               ["FRAMEJOB_DEV_TOOLS"]),
                          timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        if error.expired:
            return None, f"swiftc did not finish within {BUILD_WALL} s"
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, None


def run_probe(binary, here, paths):
    """({row: (ok, detail)}, None) or (None, why)."""
    request = here / "request.json"
    request.write_text(json.dumps(paths, indent=2))
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    try:
        ran = run([str(binary), str(request)], RUN_WALL, env)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {RUN_WALL} s"
    (here / "stderr.txt").write_text(ran.stderr)
    for line in ran.stdout.splitlines():
        if line.startswith("ANSWER "):
            try:
                answer = json.loads(line[len("ANSWER "):])
            except ValueError as error:
                return None, f"the answer did not read: {error}"
            return {r["id"]: (bool(r["ok"]), r["detail"]) for r in answer["rows"]}, None
    return None, f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; the reason when a
    `before` text is not found exactly once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before.strip()}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def archive(commit, dest):
    """app/Sources at `commit` under `dest`; the reason when it failed."""
    dest.mkdir(parents=True)
    got = subprocess.run(["git", "-C", str(ROOT), "archive", commit, "app/Sources",
                          "app/Bridging"], capture_output=True)
    if got.returncode:
        return f"git archive {commit} failed: {got.stderr.decode(errors='replace').strip()}"
    untar = subprocess.run(["tar", "-x", "-C", str(dest)], input=got.stdout,
                           capture_output=True)
    if untar.returncode:
        return f"tar failed: {untar.stderr.decode(errors='replace').strip()}"
    return None


# ---------------------------------------------------------------------------
# The photographs.

def photographs(package, here):
    """{H1: (ok, detail), H2: …} — `regions` light and dark, twice each."""
    out = {}
    try:
        built = run([str(HARNESS)], HARNESS_WALL)
    except subprocess.TimeoutExpired:
        why = f"harness/build.sh did not finish within {HARNESS_WALL} s"
        return {"H1": (False, why, True), "H2": (False, why, True)}
    if built.returncode:
        why = "harness/build.sh: " + (built.stdout + built.stderr).strip()[-400:]
        return {"H1": (False, why, True), "H2": (False, why, True)}
    binary = built.stdout.strip().splitlines()[-1]
    photos = here / "photos"
    photos.mkdir(parents=True, exist_ok=True)
    for row, look in (("H1", "light"), ("H2", "dark")):
        paths = [photos / f"regions-{look}-{n}.png" for n in (1, 2)]
        whys = []
        for path in paths:
            if path.exists():
                path.unlink()
            try:
                got = run([binary, package, str(path), look, "1440", "862", "0", "1", "1",
                           "clip"], 300)
                if got.returncode or not path.exists():
                    whys.append(f"{path.name}: exit {got.returncode} "
                                f"{(got.stdout + got.stderr).strip()[-200:]}")
            except subprocess.TimeoutExpired:
                whys.append(f"{path.name}: no picture within 300 s")
        if whys:
            out[row] = (False, "; ".join(whys), True)
            continue
        same = paths[0].read_bytes() == paths[1].read_bytes()
        out[row] = (same, f"{paths[0]} and {paths[1]} byte-identical {same} "
                          f"({paths[0].stat().st_size} bytes)", False)
    return out


# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--baseline")
    group.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.baseline:
        here = WORK / "baseline"
    elif args.mutant:
        here = WORK / f"mutant-{args.mutant}"
    else:
        here = WORK / "tree"
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    label = (f"mutant {args.mutant}" if args.mutant else
             f"baseline {args.baseline}" if args.baseline else "tree")

    def not_performed(why):
        print(f"{label}: the control could not be performed — {why}")
        return 2

    sources = args.sources.resolve()
    if args.baseline:
        why = archive(args.baseline, here / "src")
        if why:
            return not_performed(why)
        sources = here / "src/app/Sources"
        print(f"BASELINE {args.baseline}: app/Sources in {sources.relative_to(ROOT)}, "
              "linked to the current libframejob_core.a")
    elif args.mutant:
        why = mutate(sources, args.mutant, here / "Sources")
        if why:
            return not_performed(why)
        sources = here / "Sources"

    results = {}  # row: (ok, detail, instrument)
    binary, why = build(sources, here / "probe")
    results["B0"] = (binary is not None, why or f"built from {sources}", binary is None)
    if binary is None:
        for row in PROBE_ROWS:
            results[row] = (False, "not run: the probe did not build", True)
    else:
        answer, why = run_probe(binary, here / "probe", packages())
        for row in PROBE_ROWS:
            if answer is None:
                results[row] = (False, f"no row: {why}", True)
            elif row not in answer:
                results[row] = (False, "no row: the probe did not write it", True)
            else:
                results[row] = (*answer[row], False)
    rows = ["B0"] + PROBE_ROWS
    if not args.baseline and not args.mutant:
        results.update(photographs(packages()["regions"], here))
        rows += ["H1", "H2"]

    for row in rows:
        good, detail, _ = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in rows if results[row][0])
    print(f"scores: {passed}/{len(rows)}")

    if not args.baseline and not args.mutant:
        return 0 if passed == len(rows) else 1
    instruments = [row for row in rows if results[row][2]]
    if instruments:
        return not_performed(f"instrument failures: {', '.join(instruments)}")
    failed = sorted(row for row in rows if not results[row][0])
    if args.baseline:
        controls = [row for row in CONTROLS if not results[row][0]]
        if controls:
            return not_performed(f"controls failed on {args.baseline}: {', '.join(controls)}")
        if failed == sorted(BASELINE_EXPECTED):
            print(f"BASELINE CAUGHT: exactly {' '.join(BASELINE_EXPECTED)} failed and "
                  "every other row passed")
            return 1
        print(f"BASELINE SURVIVED: failed {failed}, want {sorted(BASELINE_EXPECTED)}")
        return 0
    named = MUTANTS[args.mutant][0]
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 0
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed "
          f"(all failures: {', '.join(failed)})")
    return 1


if __name__ == "__main__":
    sys.exit(main())
