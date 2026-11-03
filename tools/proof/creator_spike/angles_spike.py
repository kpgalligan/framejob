#!/usr/bin/env python3
"""Road map "creator-jobs" SW0, spike SW-S2 — several 4K angles, a thousand
shots, three hours (spec §11 SW-1, SW-2, SW-5; its verdict SW-6).

    python3 tools/proof/creator_spike/angles_spike.py [--long] [--keep-long]
        [--build-4k] [--clean] [--rows a,b,c,d] [--runs N] [--app debug|release|<path>]

The fixtures are `angles_fixtures.py`'s (`tools/proof/media/creator/`):
`--long` makes the three-hour file and runs (d) on it BEFORE F-4K exists, then
removes it unless `--keep-long`; `--build-4k` makes F-4K (kept); `--clean`
removes every fixture first. A fixture the disk rule refuses prints its
`STOP:` line and the script exits 3.

`rule.check_rule("SW-S2")` runs first. Every package is made over MCP on a
"maker" instance (`new_project`, `set_canvas`, `import_media`, `add_track`,
one `add_clip` per role and that role's `set_video` or `set_track`), its
caches waited for (every media's markers, then a cache listing steady for
2 s: `derived_proof.py`'s rule; bound 30 min for the long file, else 10; a
first pass still missing a marker at 180 s is given one fresh pass by saving,
closing and reopening the package, recorded as `reopened_templates`), then
saved; its clips are then replicated by writing the package's `project.json`
(ids from `next_id`, every time frame-snapped: 20020 ticks a frame at 29.97,
10010 at 59.94). Each timing instance opens a package, waits for the open's
rebuild to land (`playback_rebuilds`), and checks the markers again before its
first measured call: a missing one fails the row by name. Preview Quality is
set ONLY by the launch argument `-FrameJobPreviewQuality 0|1`. Instances run
on a scratch `CFFIXED_USER_HOME`, each launched and stopped by its own PID.
Shot lists come from `random.Random` with a fixed seed per row: lengths
uniform in 2–8 s, angles alternating, the last cut to the row's end. Every
row repeats `--runs` times, each run with `rule.host()`'s facts.

- (a) one Full instance on a 3840×2160 canvas: a1/a2 (H.264) and a3/a4 (HEVC)
  300 s, source in = timeline start; p1/p2 (ProRes 422 HQ) 300 s, source in
  = start mod 52 s; h1/h2 (HEVC 59.94) 120 s on a 59.94 canvas. Played by
  60 s `play_preview` calls from `set_playhead` at k·60 s, `frames_expected`
  and `frames_composed` summed. A pair's figure is its runs' median ratio;
  the plan's assignment is kept when every pair's is ≥ 0.99, else SW2c.
- (b) two hours: four hidden angle tracks of twelve 600 s placements of a1…a4,
  two tracks of twelve mic1/mic2 placements, a 1,000-shot program track (999
  boundaries, the 11 multiples of 600 s forced, the rest drawn with no gap
  under 1 s, each shot's angle not the last one's, source in = start mod
  600 s). Per run: the open's entry landed, `reset`, then ten `roll`s of
  boundaries that are not multiples of 600 s, each +15 frames, each followed
  by polling `playback_rebuilds` every 100 ms (bound 60 s) for its landed
  entry. The figure is the median `landed_ms` over every run's rolls; it
  passes at ≤ 1,500 ms.
- (c) N = 1…4 angle tracks, a1…a4 at `scale` 0.5 in a 2×2 grid on a
  1920×1080 canvas at 29.97, under a front program track at `opacity` 0.5
  alternating among the N angles: 60 s on a Half and on a Full instance per
  N. The live cell count is the largest N whose median Half ratio is ≥ 0.98
  (N ≥ 4: four live; 2–3: live up to N, the rest refreshed when paused; < 2:
  every cell refreshed only when paused or after a switch).
- (d) one clip of `long_hevc.mov`, imported and saved on the maker; the timing
  instance reopens it. Per run, for 0:30:00, 1:00:00, 2:00:00 and 2:59:00:
  `set_playhead` 0 and play 0.5 s, then `set_playhead` T and `play_preview
  {seconds: 0.5}` until `frames_composed` ≥ 1 (bound 30 s; the refusal "The
  preview was still seeking after 5 s, …" counts as not yet). The wall time
  from the `set_playhead` send is recorded as an upper bound, pass or fail,
  with the count of still-seeking refusals. Recorded; no threshold.

A row whose runs fall on both sides of its threshold is `noise_bound: true`,
its verdict "re-run on a quiet machine". A row that cannot run is a scored
failure, never an exit. Rows merge into
`tools/proof/work/creator_spike/SW-S2/results.json`: the file is read first,
only the keys of the rows run are replaced, and the merged rows go to
`rule.write_results`.
"""

import argparse
import copy
import json
import os
import random
import shutil
import statistics
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(PROOF / "graphics_spike"))
import angles_fixtures as fx  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import rule  # noqa: E402

SPIKE = "SW-S2"
SEC = 600_000
FRAME30 = 20_020
FRAME60 = 10_010
NTSC = [30000, 1001]
NTSC60 = [60000, 1001]
CALL_BOUND = 900
WORK = rule.WORK / SPIKE
RESULTS = WORK / "results.json"
SEEKING = "still seeking after 5 s"
SEEDS = {"a": 5201, "b": 5202, "c": 5203}
PAIRS = {  # name → (media a, media b, seconds, source-in modulus or None, canvas fps)
    "h264": ("a1_h264.mov", "a2_h264.mov", 300, None, NTSC),
    "hevc": ("a3_hevc.mov", "a4_hevc.mov", 300, None, NTSC),
    "prores": ("p1_prores.mov", "p2_prores.mov", 300, 52, NTSC),
    "hevc5994": ("h1_hevc5994.mov", "h2_hevc5994.mov", 120, None, NTSC60),
}
ANGLES = ["a1_h264.mov", "a2_h264.mov", "a3_hevc.mov", "a4_hevc.mov"]
GRID = [(-480.0, -270.0), (480.0, -270.0), (-480.0, 270.0), (480.0, 270.0)]
D_TIMES = [1800, 3600, 7200, 10740]
A_RULE, B_RULE, C_RULE = 0.99, 1500.0, 0.98


def say(text):
    print(text, flush=True)


def snap_down(ticks, frame):
    return (ticks // frame) * frame


def pmset():
    run = subprocess.run(["pmset", "-g"], capture_output=True, text=True).stdout
    return " ".join(line.strip() for line in run.splitlines() if "powermode" in line.lower()
                    or "lowpowermode" in line.lower())


def facts():
    return {**rule.host(), "pmset": pmset(),
            "loadavg": subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True,
                                      text=True).stdout.strip()}


# ---- instances -----------------------------------------------------------------

class Instance:
    """One launched app, stopped by its own PID."""

    count = 0

    def __init__(self, binary, quality=0, label="i"):
        Instance.count += 1
        home = WORK / "home"
        home.mkdir(parents=True, exist_ok=True)
        self.log = WORK / f"{label}-{Instance.count}.log"
        self.launched = mcp.launch(str(binary), ["-FrameJobPreviewQuality", str(quality)],
                                   env=bounded.child_env({"CFFIXED_USER_HOME": str(home)}),
                                   log_path=str(self.log), timeout=CALL_BOUND, seconds=120)
        if self.launched.client is None:
            self.launched.stop()
            raise RuntimeError(f"the app did not listen ({self.log.name})")
        self.client = self.launched.client
        say(f"  instance PID {self.launched.child.pid} quality {quality} ({self.log.name})")

    def call(self, package, tool, **arguments):
        return self.client.call_with(tool, {"project": str(package), **arguments})

    def parity(self):
        try:
            return [line.strip() for line in open(self.log, errors="replace")
                    if "Frame Job: " in line]
        except OSError:
            return [f"{self.log} could not be read"]

    def stop(self):
        self.launched.stop()

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.stop()


PARITY = []


def run_instance(binary, quality, label, body):
    with Instance(binary, quality, label) as instance:
        try:
            return body(instance)
        finally:
            PARITY.extend(instance.parity())


# ---- caches (derived_proof.py's wait_caches / missing_markers, copied) -----------------

def listing(folder):
    folder = Path(folder)
    if not folder.exists():
        return []
    out = []
    for p in sorted(folder.rglob("*")):
        st = p.lstat()
        out.append((str(p.relative_to(folder)), st.st_size, st.st_ino, st.st_mtime_ns))
    return out


def missing_markers(instance, package):
    cache = Path(package) / "cache"
    missing = []
    for media in instance.call(package, "get_project")["project"]["media"]:
        m = media["id"]
        wanted = []
        if media.get("kind") != "audio" and media.get("width"):
            wanted.append(f"thumbs/{m}/complete.json")
        if media.get("has_audio"):
            wanted += [f"{k}/{m}.complete.json" for k in ("peaks", "loudness", "speech", "sync")]
        missing += [w for w in wanted if not (cache / w).exists()]
    return missing


def wait_caches(instance, package, bound):
    began = time.monotonic()
    while time.monotonic() - began < bound:
        missing = missing_markers(instance, package)
        if not missing:
            break
        time.sleep(0.5)
    else:
        raise RuntimeError(f"{Path(package).name}: markers missing after {bound} s: "
                           f"{missing_markers(instance, package)}")
    last = None
    while time.monotonic() - began < bound:
        now = listing(Path(package) / "cache")
        if now == last:
            return time.monotonic() - began
        last = now
        time.sleep(2)
    raise RuntimeError(f"{Path(package).name}: the cache never settled")


# ---- packages ------------------------------------------------------------------------

def fresh(instance, path, width, height, fps):
    try:
        instance.client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass
    if path.exists():
        shutil.rmtree(path)
    instance.client.call("new_project", path=str(path))
    instance.call(path, "set_canvas", width=width, height=height, fps=fps)


def tracks_of(instance, path, want):
    while len(instance.call(path, "get_project")["project"]["tracks"]) < want:
        instance.call(path, "add_track")
    return [t["id"] for t in instance.call(path, "get_project")["project"]["tracks"]]


REOPENED = {}  # package name → the markers its first cache pass left missing


def save_template(instance, path, bound):
    """Waits for the caches, then saves. A first pass that leaves a marker
    missing for 180 s is given one more: the package saved, closed and opened
    again, which starts a fresh pass (seen on 2026-11-03: `a2_h264.mov`'s strip
    stopping with tiles 511–527 unwritten and no marker beside `a1_h264.mov`'s
    pass, while the file decodes whole), then the full bound."""
    try:
        waited = wait_caches(instance, path, min(180, bound))
    except RuntimeError:
        REOPENED[path.name] = missing_markers(instance, path)
        say(f"  {path.name}: markers missing after 180 s, {REOPENED[path.name]}: reopened")
        instance.call(path, "save_project")
        instance.client.call("close_project", project=str(path), discard=True)
        instance.client.call("open_project", path=str(path))
        waited = 180 + wait_caches(instance, path, bound)
    instance.call(path, "save_project")
    instance.client.call("close_project", project=str(path), discard=True)
    say(f"  {path.name}: caches settled in {waited:.0f} s, saved")
    return json.loads((path / "project.json").read_text())


def media_ids(instance, path, files):
    return {name: instance.call(path, "import_media", path=str(fx.F4K / name))["media"]
            for name in files}


def role_clip(project, media):
    return next(c for c in project["clips"] if c["source"].get("media") == media)


def write_project(path, project, clips):
    document = copy.deepcopy(project)
    next_id = project["next_id"]
    for clip in clips:
        clip["id"] = next_id
        next_id += 1
    document["clips"] = clips
    document["next_id"] = next_id
    text = json.dumps(document)
    (path / "project.json").write_text(text)
    return text


def placed(template, track, start, duration, source_in, media=None):
    clip = copy.deepcopy(template)
    clip["track"] = track
    clip["start"] = start
    clip["duration"] = duration
    clip["source"]["in"] = source_in
    if media is not None:
        clip["source"]["media"] = media
    clip["actions"] = []
    return clip


def shot_list(rng, end, frame, count_of):
    """[(start, duration, angle index)]: 2–8 s, frame-snapped, alternating."""
    shots, t, k = [], 0, 0
    while t < end:
        frames = max(1, round(rng.uniform(2, 8) * SEC / frame))
        duration = min(frames * frame, end - t)
        shots.append((t, duration, k % count_of))
        t += duration
        k += 1
    return shots


# ---- (a) ------------------------------------------------------------------------------

def package_a(maker, name):
    first, second, seconds, modulus, fps = PAIRS[name]
    frame = FRAME60 if fps == NTSC60 else FRAME30
    path = WORK / f"a-{name}.framejob"
    fresh(maker, path, 3840, 2160, fps)
    ids = media_ids(maker, path, [first, second])
    track = tracks_of(maker, path, 1)[0]
    clip = maker.call(path, "add_clip", track=track, media=ids[first], at=0)["new_clips"][0]
    maker.call(path, "trim_end", clip=clip, to=10 * SEC)
    maker.call(path, "add_clip", track=track, media=ids[second], at=10 * SEC)
    project = save_template(maker, path, 600)
    roles = [role_clip(project, ids[first]), role_clip(project, ids[second])]
    end = snap_down(seconds * SEC, frame)
    clips = []
    for start, duration, k in shot_list(random.Random(SEEDS["a"]), end, frame, 2):
        source_in = start if modulus is None else snap_down(start % (modulus * SEC), frame)
        clips.append(placed(roles[k], track, start, duration, source_in))
    write_project(path, project, clips)
    return {"package": path, "seconds": seconds, "shots": len(clips), "end": end}


def opened(instance, package, bound=120):
    """Opens a package and waits for the open's rebuild to land; answers the log."""
    instance.client.call("open_project", path=str(package))
    deadline = time.monotonic() + bound
    while time.monotonic() < deadline:
        log = instance.call(package, "playback_rebuilds")
        rows = log["rebuilds"]
        if not log["rebuilding"] and rows and rows[-1]["landed_ms"] is not None:
            return log
        time.sleep(0.1)
    raise RuntimeError(f"{package.name}: the open's rebuild did not land in {bound} s")


def markers_hold(instance, package):
    missing = missing_markers(instance, package)
    if missing:
        raise RuntimeError(f"{package.name}: cache markers missing at the timing instance: "
                           f"{missing}")


def play_span(instance, package, seconds):
    expected = composed = 0
    for k in range(0, seconds, 60):
        instance.call(package, "set_playhead", t=k * SEC)
        answer = play(instance, package, min(60, seconds - k))
        expected += answer["frames_expected"]
        composed += answer["frames_composed"]
    return {"expected": expected, "composed": composed,
            "ratio": round(composed / expected, 4) if expected else None}


def play(instance, package, seconds, bound=30):
    """`play_preview`, called again while it refuses as still seeking."""
    deadline = time.monotonic() + bound
    while True:
        try:
            return instance.call(package, "play_preview", seconds=seconds)
        except mcp.ToolError as error:
            if SEEKING not in str(error) or time.monotonic() > deadline:
                raise


def row_a(binary, runs, made):
    out = {"pairs": {}, "rule": f"every pair's median ratio >= {A_RULE}"}
    for name in PAIRS:
        record = {"runs": []}
        out["pairs"][name] = record
        info = made.get(name)
        if info is None or "error" in info:
            record["error"] = (info or {}).get("error", "not made")
            continue
        record.update({k: v for k, v in info.items() if k != "package"})
        for run in range(runs):
            def body(instance, info=info):
                opened(instance, info["package"])
                markers_hold(instance, info["package"])
                host = facts()
                figures = play_span(instance, info["package"], info["seconds"])
                instance.client.call("close_project", project=str(info["package"]),
                                     discard=True)
                return {**figures, "host": host}
            try:
                got = run_instance(binary, 0, f"a-{name}", body)
            except Exception as error:  # noqa: BLE001 — a scored failure
                got = {"error": f"{type(error).__name__}: {error}"[:400], "ratio": None}
            say(f"  (a) {name} run {run + 1}: {got.get('ratio')} "
                f"({got.get('composed')}/{got.get('expected')}) {got.get('error', '')}")
            record["runs"].append(got)
        ratios = [r["ratio"] for r in record["runs"] if r.get("ratio") is not None]
        record["median"] = statistics.median(ratios) if len(ratios) == runs else None
        record["spread"] = [min(ratios), max(ratios)] if ratios else None
        record["noise_bound"] = bool(ratios) and min(ratios) < A_RULE <= max(ratios)
    medians = [p.get("median") for p in out["pairs"].values()]
    out["noise_bound"] = any(p.get("noise_bound") for p in out["pairs"].values())
    # A pair whose every run is below the rule decides the row ("SW2c is owed") whatever
    # a straddling pair's median turns out to be, so the row is noise-bound only when no
    # pair has decided it.
    below = any(max(r["ratio"] for r in p["runs"]) < A_RULE
                for p, m in zip(out["pairs"].values(), medians) if m is not None)
    if any(m is None for m in medians):
        out["verdict"] = "FAILED: a pair could not be measured"
        out["pass"] = False
    elif below:
        out["noise_bound"] = False
        out["pass"] = False
        out["verdict"] = "SW2c is owed"
    elif out["noise_bound"]:
        out["verdict"] = "re-run on a quiet machine"
        out["pass"] = None
    else:
        out["pass"] = all(m >= A_RULE for m in medians)
        out["verdict"] = "keep the plan's assignment" if out["pass"] else "SW2c is owed"
    return out


# ---- (b) ------------------------------------------------------------------------------

def package_b(maker):
    path = WORK / "b-two-hours.framejob"
    fresh(maker, path, 3840, 2160, NTSC)
    files = ANGLES + ["mic1.wav", "mic2.wav"]
    ids = media_ids(maker, path, files)
    tracks = tracks_of(maker, path, 7)  # 0–3 angles, 4–5 mics, 6 the program (front)
    for k in range(4):
        maker.call(path, "set_track", track=tracks[k], hidden=True)
    for k, name in enumerate(files):
        maker.call(path, "add_clip", track=tracks[k], media=ids[name], at=0)
    project = save_template(maker, path, 600)
    roles = {name: role_clip(project, ids[name]) for name in files}
    block = 600 * SEC
    clips = []
    for k, name in enumerate(files):
        for j in range(12):
            clips.append(placed(roles[name], tracks[k], j * block, block, 0))
    end = 12 * block
    rng = random.Random(SEEDS["b"])
    forced = [j * block for j in range(1, 12)]
    boundaries = set(forced)
    while len(boundaries) < 999:
        candidate = snap_down(rng.randrange(SEC, end - SEC), FRAME30)
        if all(abs(candidate - b) >= SEC for b in boundaries):
            boundaries.add(candidate)
    cuts = [0, *sorted(boundaries), end]
    angle, program = None, []
    for start, stop in zip(cuts, cuts[1:]):
        angle = rng.choice([a for a in range(4) if a != angle])
        name = ANGLES[angle]
        program.append(placed(roles[name], tracks[6], start, stop - start,
                              snap_down(start % block, FRAME30)))
    clips += program
    text = write_project(path, project, clips)
    by_start = {c["start"]: c["id"] for c in clips if c["track"] == tracks[6]}
    rollable = [b for b in sorted(boundaries) if b % block != 0]
    return {"package": path, "pristine": text, "by_start": by_start, "rollable": rollable,
            "shots": len(program), "clips": len(clips)}


def row_b(binary, runs, made):
    out = {"runs": [], "rule": f"median landed_ms <= {B_RULE:.0f}"}
    if made is None or "error" in made:
        out.update({"error": (made or {}).get("error", "not made"), "pass": False,
                    "verdict": "FAILED: not made"})
        return out
    out.update({"shots": made["shots"], "clips": made["clips"]})
    package = made["package"]
    for run in range(runs):
        (package / "project.json").write_text(made["pristine"])
        picks = random.Random(SEEDS["b"] * 100 + run).sample(made["rollable"], 10)

        def body(instance, picks=picks):
            first = opened(instance, package, bound=300)
            markers_hold(instance, package)
            host = facts()
            instance.call(package, "playback_rebuilds", reset=True)
            rolls = []
            for boundary in picks:
                clip = made["by_start"][boundary]
                sent = time.monotonic()
                instance.call(package, "roll", clip=clip, to=boundary + 15 * FRAME30)
                landed = None
                while time.monotonic() - sent < 60:
                    log = instance.call(package, "playback_rebuilds")
                    rows = log["rebuilds"]
                    if len(rows) > len(rolls) and rows[-1]["landed_ms"] is not None:
                        landed = rows[-1]
                        break
                    time.sleep(0.1)
                rolls.append({"boundary": boundary, "clip": clip,
                              "built_ms": landed and landed["built_ms"],
                              "landed_ms": landed and landed["landed_ms"],
                              "wall_s": round(time.monotonic() - sent, 3)})
            instance.client.call("close_project", project=str(package), discard=True)
            return {"open": first["rebuilds"][-1], "rolls": rolls, "host": host}
        try:
            got = run_instance(binary, 0, "b", body)
        except Exception as error:  # noqa: BLE001
            got = {"error": f"{type(error).__name__}: {error}"[:400], "rolls": []}
        landed = [r["landed_ms"] for r in got["rolls"] if r["landed_ms"] is not None]
        got["median_landed_ms"] = statistics.median(landed) if landed else None
        say(f"  (b) run {run + 1}: open {got.get('open')}, roll landed_ms {landed} "
            f"{got.get('error', '')}")
        out["runs"].append(got)
    every = [r["landed_ms"] for g in out["runs"] for r in g["rolls"]]
    measured = [v for v in every if v is not None]
    run_medians = [g["median_landed_ms"] for g in out["runs"] if g["median_landed_ms"]]
    out["median_landed_ms"] = statistics.median(measured) if measured else None
    out["spread_ms"] = [min(measured), max(measured)] if measured else None
    out["run_medians_ms"] = run_medians
    out["noise_bound"] = bool(run_medians) and min(run_medians) <= B_RULE < max(run_medians)
    if len(measured) != len(every) or not every or len(out["runs"]) != runs:
        out.update({"pass": False, "verdict": "FAILED: a roll did not land or a run failed"})
    elif out["noise_bound"]:
        out.update({"pass": None, "verdict": "re-run on a quiet machine"})
    else:
        out["pass"] = out["median_landed_ms"] <= B_RULE
        out["verdict"] = ("within 1,500 ms" if out["pass"]
                          else "over 1,500 ms: the figure in the guide and a candidate issue")
    return out


# ---- (c) ------------------------------------------------------------------------------

def package_c(maker):
    path = WORK / "c-template.framejob"
    fresh(maker, path, 1920, 1080, NTSC)
    ids = media_ids(maker, path, ANGLES)
    tracks = tracks_of(maker, path, 5)  # 0–3 the cells, 4 the program (front)
    for k, name in enumerate(ANGLES):
        clip = maker.call(path, "add_clip", track=tracks[k], media=ids[name],
                          at=0)["new_clips"][0]
        x, y = GRID[k]
        maker.call(path, "set_video", clips=[clip], patch={"x": x, "y": y, "scale": 0.5})
    program = maker.call(path, "add_clip", track=tracks[4], media=ids[ANGLES[0]],
                         at=70 * SEC)["new_clips"][0]
    maker.call(path, "set_video", clips=[program], patch={"x": 0, "y": 0, "scale": 0.5,
                                                          "opacity": 0.5})
    project = save_template(maker, path, 600)
    cells = {name: next(c for c in project["clips"] if c["source"]["media"] == ids[name]
                        and c["track"] != tracks[4]) for name in ANGLES}
    prog = next(c for c in project["clips"] if c["track"] == tracks[4])
    end = snap_down(60 * SEC, FRAME30)
    packages = {}
    for n in range(1, 5):
        target = WORK / f"c-n{n}.framejob"
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(path, target)
        clips = [placed(cells[ANGLES[k]], tracks[k], 0, end, 0) for k in range(n)]
        for start, duration, k in shot_list(random.Random(SEEDS["c"] + n), end, FRAME30, n):
            clips.append(placed(prog, tracks[4], start, duration, start, ids[ANGLES[k]]))
        write_project(target, project, clips)
        packages[n] = target
    return {"packages": packages}


def row_c(binary, runs, made):
    out = {"by_n": {}, "rule": f"the largest N whose median Half ratio >= {C_RULE}"}
    if made is None or "error" in made:
        out.update({"error": (made or {}).get("error", "not made"), "pass": False,
                    "verdict": "FAILED: not made"})
        return out
    for n in range(1, 5):
        out["by_n"][str(n)] = {"half": [], "full": []}
    for run in range(runs):
        for quality, key in ((1, "half"), (0, "full")):
            def body(instance):
                got = {}
                for n, package in made["packages"].items():
                    try:
                        opened(instance, package)
                        markers_hold(instance, package)
                        host = facts()
                        got[n] = {**play_span(instance, package, 60), "host": host}
                    except Exception as error:  # noqa: BLE001
                        got[n] = {"error": f"{type(error).__name__}: {error}"[:300],
                                  "ratio": None}
                    try:
                        instance.client.call("close_project", project=str(package),
                                             discard=True)
                    except mcp.ToolError:
                        pass
                return got
            try:
                got = run_instance(binary, quality, f"c-{key}", body)
            except Exception as error:  # noqa: BLE001
                got = {n: {"error": f"{type(error).__name__}: {error}"[:300], "ratio": None}
                       for n in range(1, 5)}
            for n, figures in got.items():
                out["by_n"][str(n)][key].append(figures)
                say(f"  (c) run {run + 1} {key} N={n}: {figures.get('ratio')} "
                    f"{figures.get('error', '')}")
    live, noisy, failed = 0, False, False
    for n in range(1, 5):
        cell = out["by_n"][str(n)]
        for key in ("half", "full"):
            ratios = [r["ratio"] for r in cell[key] if r.get("ratio") is not None]
            cell[f"{key}_median"] = statistics.median(ratios) if len(ratios) == runs else None
            cell[f"{key}_spread"] = [min(ratios), max(ratios)] if ratios else None
        halves = [r["ratio"] for r in cell["half"] if r.get("ratio") is not None]
        cell["noise_bound"] = bool(halves) and min(halves) < C_RULE <= max(halves)
        noisy = noisy or cell["noise_bound"]
        failed = failed or cell["half_median"] is None
        if cell["half_median"] is not None and cell["half_median"] >= C_RULE:
            live = n
    out["live_cells"] = live
    out["noise_bound"] = noisy
    mapping = ("four live" if live >= 4 else
               f"live up to {live}, the rest refreshed when paused" if live >= 2 else
               "every cell refreshed only when paused or after a switch")
    if failed:
        out.update({"pass": False, "verdict": "FAILED: an N could not be measured"})
    elif noisy:
        out.update({"pass": None, "verdict": f"re-run on a quiet machine (as measured: {live}, "
                                             f"{mapping})"})
    else:
        out.update({"pass": True, "verdict": mapping})
    return out


# ---- (d) ------------------------------------------------------------------------------

def package_d(maker):
    path = WORK / "d-long.framejob"
    fresh(maker, path, 3840, 2160, NTSC)
    media = maker.call(path, "import_media", path=str(fx.long_path()))["media"]
    track = tracks_of(maker, path, 1)[0]
    maker.call(path, "add_clip", track=track, media=media, at=0)
    save_template(maker, path, 1800)
    return {"package": path}


def row_d(binary, runs, made, fixture):
    out = {"runs": [], "times_s": D_TIMES, "fixture": fixture,
           "rule": "recorded: the wall time to the first composed frame after each seek"}
    if made is None or "error" in made:
        out.update({"error": (made or {}).get("error", "not made"), "pass": False,
                    "verdict": "FAILED: not made"})
        return out
    package = made["package"]
    for run in range(runs):
        def body(instance):
            first = opened(instance, package, bound=300)
            markers_hold(instance, package)
            host = facts()
            points = []
            for t in D_TIMES:
                instance.call(package, "set_playhead", t=0)
                play(instance, package, 0.5)
                sent = time.monotonic()
                instance.call(package, "set_playhead", t=t * SEC)
                seeking, composed, error = 0, 0, None
                while time.monotonic() - sent < 30:
                    try:
                        answer = instance.call(package, "play_preview", seconds=0.5)
                    except mcp.ToolError as failure:
                        if SEEKING in str(failure):
                            seeking += 1
                            continue
                        error = str(failure)[:300]
                        break
                    composed = answer.get("frames_composed", 0)
                    if composed >= 1:
                        break
                points.append({"t_s": t, "wall_s": round(time.monotonic() - sent, 3),
                               "passed": composed >= 1 and error is None,
                               "still_seeking": seeking, "error": error})
            instance.client.call("close_project", project=str(package), discard=True)
            return {"open": first["rebuilds"][-1], "points": points, "host": host}
        try:
            got = run_instance(binary, 0, "d", body)
        except Exception as error:  # noqa: BLE001
            got = {"error": f"{type(error).__name__}: {error}"[:400], "points": []}
        say(f"  (d) run {run + 1}: {[(p['t_s'], p['wall_s'], p['passed']) for p in got['points']]}"
            f" {got.get('error', '')}")
        out["runs"].append(got)
    summary = {}
    for t in D_TIMES:
        walls = [p["wall_s"] for g in out["runs"] for p in g["points"] if p["t_s"] == t]
        passed = [p["passed"] for g in out["runs"] for p in g["points"] if p["t_s"] == t]
        summary[str(t)] = {"median_wall_s": statistics.median(walls) if walls else None,
                           "spread_s": [min(walls), max(walls)] if walls else None,
                           "passed": f"{sum(passed)}/{len(passed)}"}
    out["summary"] = summary
    complete = all(len(g["points"]) == len(D_TIMES) for g in out["runs"]) and out["runs"]
    every = all(p["passed"] for g in out["runs"] for p in g["points"])
    out["pass"] = bool(complete and every)
    out["verdict"] = "recorded" if out["pass"] else "FAILED: a point did not compose in 30 s"
    out["noise_bound"] = False
    return out


# ---- the run ------------------------------------------------------------------------

def merged_rows(new_rows):
    rows = {}
    if RESULTS.exists():
        try:
            rows = json.loads(RESULTS.read_text()).get("rows", {})
        except ValueError:
            rows = {}
    rows.update(new_rows)
    return rows


def build_packages(binary, wanted):
    made = {}

    def body(maker):
        if "a" in wanted:
            for name in PAIRS:
                try:
                    made.setdefault("a", {})[name] = package_a(maker, name)
                except Exception as error:  # noqa: BLE001
                    made.setdefault("a", {})[name] = {"error": f"{type(error).__name__}: {error}"}
                    say(f"  (a) {name} not made: {error}")
        for key, maker_fn in (("b", package_b), ("c", package_c), ("d", package_d)):
            if key in wanted:
                try:
                    made[key] = maker_fn(maker)
                except Exception as error:  # noqa: BLE001
                    made[key] = {"error": f"{type(error).__name__}: {error}"[:400]}
                    say(f"  ({key}) not made: {error}")
    try:
        run_instance(binary, 0, "maker", body)
    except Exception as error:  # noqa: BLE001
        for key in wanted:
            made.setdefault(key, {"error": f"the maker failed: {error}"[:400]})
    return made


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-4k", action="store_true")
    parser.add_argument("--long", action="store_true")
    parser.add_argument("--keep-long", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--rows", default="a,b,c,d")
    parser.add_argument("--runs", type=int, default=3)
    parser.add_argument("--app")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    rule.check_rule(SPIKE)
    wanted = [r.strip() for r in args.rows.split(",") if r.strip()]
    if set(wanted) - {"a", "b", "c", "d"}:
        print(f"unknown rows: {wanted}")
        return 2
    WORK.mkdir(parents=True, exist_ok=True)
    for stale in WORK.glob("*.framejob"):
        shutil.rmtree(stale)
    fixtures = {}
    try:
        if args.clean:
            fx.clean()
        subprocess.run(["df", "-h", str(ROOT)])
        if args.long:
            fixtures["long"] = fx.build_long()
        if args.build_4k:
            subprocess.run(["df", "-h", str(ROOT)])
            fixtures["f4k"] = fx.build_4k()
    except fx.Stop as stop:
        print(stop, flush=True)
        return 3
    binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    say(f"SW-S2 rows {wanted}, {args.runs} runs, {proof_app.config()} build ({binary})")
    made = build_packages(binary, wanted)
    rows = {}
    if "d" in wanted:
        fixture = fixtures.get("long") or (json.loads(fx.stamp(fx.long_path()).read_text())
                                           if fx.ready(fx.long_path()) else None)
        rows["d"] = row_d(binary, args.runs, made.get("d"), fixture)
        if args.long and not args.keep_long:
            fx.remove_long()
            rows["d"]["fixture_removed"] = True
    if "a" in wanted:
        rows["a"] = row_a(binary, args.runs, made.get("a", {}))
    if "b" in wanted:
        rows["b"] = row_b(binary, args.runs, made.get("b"))
    if "c" in wanted:
        rows["c"] = row_c(binary, args.runs, made.get("c"))
    for key, row in rows.items():
        row["build"] = proof_app.config()
        row["app"] = str(binary)
        row["runs_asked"] = args.runs
        row["parity"] = list(PARITY)
        row["reopened_templates"] = dict(REOPENED)
        row["when"] = time.strftime("%Y-%m-%d %H:%M:%S")
        if key in ("a", "b", "c") and fixtures.get("f4k"):
            row["fixtures"] = fixtures["f4k"]
    previous = {}
    if RESULTS.exists():
        try:
            previous = json.loads(RESULTS.read_text())
        except ValueError:
            previous = {}
    all_fixtures = {**previous.get("fixtures", {}), **fixtures}
    path = rule.write_results(SPIKE, {"rows": merged_rows(rows), "fixtures": all_fixtures})
    for key, row in sorted(rows.items()):
        say(f"({key}) {row.get('verdict')} — pass {row.get('pass')}, "
            f"noise_bound {row.get('noise_bound')}")
    say(f"parity: {PARITY[:3] or 'nothing'}")
    say(f"results: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
