#!/usr/bin/env python3
"""Road map "creator-jobs" CJ6, spike CJ-S1 — the clip ceiling (decides CJ-9;
spec §11 CJ-60).

    python3 tools/proof/creator_spike/ceiling_spike.py [--n 4096,8192,16384,32768]
        [--headroom K] [--app debug|release|<path>] [--proof]

For each N a package `n<N>.framejob` holds N − K one-second media clips (the
1080p H.264 fixture, `analysis_fixtures.h264_1080`) over four tracks: a
one-clip template made over MCP (`new_project`, `import_media`, `add_track`
×3, `add_clip`, `save_project`), its clip replicated round-robin over the
tracks, butt-joined per track, source `in` cycling 0…19 s, ids from
`next_id`. Every clip boundary is on a whole second, so a split at a whole
second + 0.5 s lies strictly inside one clip on every track and adds exactly 4
clips (`edit_clip.rs`'s `split_under_playhead`).

Rows (the rule is the road map's, `rule.py` recomputes its hash first):
- (1) `split` at the middle, (2) open + plan, (3) the recipe at 20 times and
  (7) the timeline drawn at the fit-all and the default zoom are
  `ceiling_spike.swift`'s, built from `app/Sources` through `swift_build.py`
  against `core/target/release` (the scratch build's cap past 4,096).
- Over MCP, on an instance this script launches (`proof_app.py`'s choice:
  `RC_PROOF_APP` or `--app`) on a scratch home: (4) one `ripple_delete_ranges`
  of 100 frame-snapped 0.5 s ranges spread over the timeline, then `undo`,
  each from the call to its answer; (5) `get_project` right after (4)'s undo;
  (6) a `split` at the middle, then `play_preview {seconds: 0.5}` until it
  composes a frame (at most 10 s) — the wall time to that answer, an UPPER
  bound — and `get_project` must then show 4 more clips. (4)–(6) are the
  median of 3 runs, each on the package reopened unsaved. (8) the app's RSS
  (`ps -o rss=`) before and after 50 `split`s at 50 distinct k + 0.5 s; then
  200 more clips must show.

The rule: N passes when (1) ≤ 50 ms, (2) ≤ 500 ms, (3) ≤ 2 ms, (4) ≤ 1 s
each, (5) ≤ 1 s, (6) ≤ 2 s, (7) ≤ 33 ms at both zooms and (8) grows by at
most a sixteenth of physical memory; N_max is the largest N whose every row
passes, every smaller N having passed. A row that cannot run is a scored
failure, never an exit.

Writes `tools/proof/work/creator_spike/CJ-S1/results.json` (`CJ-S1-proof/`
with `--proof`).
"""

import argparse
import json
import os
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
import analysis_fixtures as fixtures  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import rule  # noqa: E402
import swift_build  # noqa: E402

SPIKE = "CJ-S1"
SEC = 600_000
FRAME = SEC // fixtures.FPS
TRACKS = 4
RUNS = 3
DEFAULT_N = [4096, 8192, 16384, 32768]
LIMITS = {"split_ms": 50, "open_plan_ms": 500, "recipe_ms": 2, "ripple_ms": 1000,
          "ripple_undo_ms": 1000, "next_call_ms": 1000, "first_frame_s": 2,
          "timeline_fit_ms": 33, "timeline_default_ms": 33}
PROBE_ROWS = ["split_ms", "open_plan_ms", "recipe_ms", "timeline_fit_ms", "timeline_default_ms"]
CALL_BOUND = 600
PRISTINE = {}  # package → the project.json it was made with


def folder(proof):
    return rule.WORK / (f"{SPIKE}-proof" if proof else SPIKE)


# ---- the probe ---------------------------------------------------------------------

def build(work):
    entry = work / "main.swift"
    shutil.copyfile(HERE / "ceiling_spike.swift", entry)
    binary = work / "ceiling-spike"
    swift_build.build(sources=[*swift_build.app_sources(), entry], output=binary, optimize=True)
    return binary


def probe_rows(binary, package, work, n):
    out = work / f"probe-n{n}.json"
    out.unlink(missing_ok=True)
    try:
        run = subprocess.run([str(binary), str(package / "project.json"), str(out)],
                             capture_output=True, text=True, timeout=3600)
    except subprocess.TimeoutExpired:
        return None, "the probe ran past 3600 s"
    if run.returncode != 0 or not out.exists():
        return None, f"the probe exited {run.returncode}: {(run.stderr or run.stdout)[-400:]}"
    return json.loads(out.read_text()), None


# ---- the packages ------------------------------------------------------------------

def template(client, work):
    """The one-clip package every N is made from: its `project.json` as a dict."""
    path = work / "template.framejob"
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass
    if path.exists():
        shutil.rmtree(path)
    client.call("new_project", path=str(path))
    media = client.call("import_media", project=str(path),
                        path=str(fixtures.h264_1080()))["media"]
    for _ in range(TRACKS - 1):
        client.call("add_track", project=str(path))
    tracks = client.call("get_project", project=str(path))["project"]["tracks"]
    client.call("add_clip", project=str(path), track=tracks[0]["id"], media=media, at=0)
    client.call("save_project", project=str(path))
    client.call("close_project", project=str(path), discard=True)
    return path, json.loads((path / "project.json").read_text())


def make_package(template_path, project, work, n, clips):
    """`clips` one-second clips, round-robin over the tracks, butt-joined."""
    package = work / f"n{n}.framejob"
    if package.exists():
        shutil.rmtree(package)
    shutil.copytree(template_path, package)
    one = project["clips"][0]
    track_ids = [t["id"] for t in project["tracks"]]
    next_id = project["next_id"]
    made = []
    for k in range(clips):
        clip = json.loads(json.dumps(one))
        clip["id"] = next_id
        next_id += 1
        clip["track"] = track_ids[k % TRACKS]
        clip["start"] = (k // TRACKS) * SEC
        clip["duration"] = SEC
        clip["source"]["in"] = ((k // TRACKS) % 20) * SEC
        made.append(clip)
    document = dict(project)
    document["clips"] = made
    document["next_id"] = next_id
    PRISTINE[package] = json.dumps(document)
    (package / "project.json").write_text(PRISTINE[package])
    shortest = min(sum(1 for k in range(clips) if k % TRACKS == t) for t in range(TRACKS))
    return package, shortest


# ---- the MCP rows ------------------------------------------------------------------

def timed(body):
    started = time.monotonic()
    answer = body()
    return answer, time.monotonic() - started


def count(client, package):
    return len(client.call("get_project", project=str(package))["project"]["clips"])


def reopen(client, package):
    """The package as it was made: an autosave in place during a long run (a
    32,768-clip ripple takes minutes) can have written the last run's split."""
    try:
        client.call("close_project", project=str(package), discard=True)
    except mcp.ToolError:
        pass
    (package / "project.json").write_text(PRISTINE[package])
    client.call("open_project", path=str(package))


def ready_preview(client, package, deadline=30):
    """Untimed: the window's preview has an item (play_preview answers)."""
    end = time.monotonic() + deadline
    while time.monotonic() < end:
        try:
            client.call("play_preview", project=str(package), seconds=0.5)
            return True
        except mcp.ToolError:
            time.sleep(0.25)
    return False


def mcp_run(client, package, shortest, mid):
    """One run of (4), (5) and (6) on the package reopened unsaved."""
    row = {}
    reopen(client, package)
    ready_preview(client, package)
    span = max(shortest - 1, 1)
    seconds = sorted({k * span // 100 for k in range(100)})
    ranges = [[s * SEC + 6 * FRAME, s * SEC + 21 * FRAME] for s in seconds]
    before = count(client, package)
    try:
        _, row["ripple_ms"] = timed(lambda: client.call(
            "ripple_delete_ranges", project=str(package), ranges=ranges))
        row["ripple_ms"] *= 1000
        row["ripple_added"] = count(client, package) - before
        _, row["ripple_undo_ms"] = timed(lambda: client.call("undo", project=str(package)))
        row["ripple_undo_ms"] *= 1000
        _, row["next_call_ms"] = timed(lambda: client.call("get_project", project=str(package)))
        row["next_call_ms"] *= 1000
        row["after_undo"] = count(client, package) - before
        if row["ripple_added"] != 100 * TRACKS or row["after_undo"] != 0:
            # (4) must apply and undo, not only answer in time: a scored failure.
            row["ripple_ms"] = row["ripple_undo_ms"] = None
    except mcp.ToolError as error:
        row["error_4_5"] = str(error)[:300]
    client.call("set_playhead", project=str(package), t=mid)
    before = count(client, package)
    started = time.monotonic()
    composed, errors = 0, []
    try:
        client.call("split", project=str(package), at=mid)
        while time.monotonic() - started < 10:
            try:
                answer = client.call("play_preview", project=str(package), seconds=0.5)
            except mcp.ToolError as error:
                errors.append(str(error)[:160])
                continue
            composed = answer.get("frames_composed", 0)
            if composed >= 1:
                break
        took = time.monotonic() - started
        added = count(client, package) - before
        row["first_frame_s"] = took if composed >= 1 and added == 4 else None
        row["first_frame_detail"] = {"took_s": took, "composed": composed, "added": added,
                                     "errors": errors[:3]}
    except mcp.ToolError as error:
        row["first_frame_s"] = None
        row["first_frame_detail"] = {"error": str(error)[:300]}
    client.call("close_project", project=str(package), discard=True)
    return row


def rss(pid):
    out = subprocess.run(["ps", "-o", "rss=", "-p", str(pid)], capture_output=True, text=True)
    return int(out.stdout.strip() or 0) * 1024


def memory_row(client, package, shortest, pid):
    reopen(client, package)
    ready_preview(client, package)
    span = max(shortest - 1, 1)
    times = sorted({k * span // 49 for k in range(50)})
    before_clips = count(client, package)
    before = rss(pid)
    errors = []
    for s in times:
        try:
            client.call("split", project=str(package), at=s * SEC + SEC // 2)
        except mcp.ToolError as error:
            errors.append(str(error)[:160])
    after = rss(pid)
    added = count(client, package) - before_clips
    client.call("close_project", project=str(package), discard=True)
    ok = len(times) == 50 and added == 200 and not errors
    return {"rss_before": before, "rss_after": after, "splits": len(times), "added": added,
            "errors": errors[:3], "rss_growth_bytes": (after - before) if ok else None}


# ---- the rule ----------------------------------------------------------------------

def score(rows, physical):
    passes = {}
    for key, limit in LIMITS.items():
        value = rows.get(key)
        passes[key] = value is not None and value <= limit
    growth = rows.get("rss_growth_bytes")
    passes["rss_growth_bytes"] = growth is not None and growth <= physical / 16
    return passes


def median_or_none(values):
    present = [v for v in values if v is not None]
    return statistics.median(present) if len(present) == len(values) and present else None


def one_n(client, pid, probe, template_path, project, work, n, headroom, physical):
    clips = n - headroom
    package, shortest = make_package(template_path, project, work, n, clips)
    mid = (shortest // 2) * SEC + SEC // 2
    record = {"n": n, "clips": clips, "refused": None, "runs": RUNS, "rows": {}, "detail": {}}
    print(f"N={n}: {clips} clips, {shortest} s a track", flush=True)
    answer, why = probe_rows(probe, package, work, n) if probe else (None, "the probe did not build")
    if answer is None:
        record["detail"]["probe"] = why
        record["refused"] = why if "refused" in (why or "") else None
        for key in PROBE_ROWS:
            record["rows"][key] = None
    else:
        for key in PROBE_ROWS:
            entry = answer["rows"][key]
            record["rows"][key] = entry["median"] if not entry["failures"] else None
            record["detail"][key] = entry
    runs = []
    for _ in range(RUNS):
        try:
            runs.append(mcp_run(client, package, shortest, mid))
        except (mcp.ToolError, OSError) as error:
            runs.append({"error": str(error)[:300]})
            record["refused"] = record["refused"] or str(error)[:300]
    record["detail"]["mcp_runs"] = runs
    for key in ("ripple_ms", "ripple_undo_ms", "next_call_ms", "first_frame_s"):
        record["rows"][key] = median_or_none([r.get(key) for r in runs])
    try:
        memory = memory_row(client, package, shortest, pid)
    except (mcp.ToolError, OSError) as error:
        memory = {"error": str(error)[:300], "rss_growth_bytes": None}
    record["detail"]["memory"] = memory
    record["rows"]["rss_growth_bytes"] = memory.get("rss_growth_bytes")
    record["pass"] = score(record["rows"], physical)
    print(json.dumps({"n": n, "rows": record["rows"], "pass": record["pass"]}), flush=True)
    return record


def parity(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        return [f"{log} could not be read"]


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--n", default=",".join(map(str, DEFAULT_N)))
    parser.add_argument("--headroom", type=int, default=0)
    parser.add_argument("--app")
    parser.add_argument("--proof", action="store_true")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    rule.check_rule(SPIKE)
    ns = sorted(int(x) for x in args.n.split(",") if x.strip())
    work = folder(args.proof)
    if work.exists():
        shutil.rmtree(work)
    work.mkdir(parents=True)
    physical = int(rule.sysctl("hw.memsize") or 0)
    try:
        probe, probe_error = build(work), None
    except swift_build.SwiftBuildFailed as error:
        probe, probe_error = None, f"{error}: {error.diagnostics[:3]}"
        print(f"the probe did not build: {probe_error}", flush=True)
    binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    home = work / "home"
    home.mkdir()
    log = work / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(home)}),
                          log_path=str(log), timeout=CALL_BOUND)
    table = []
    try:
        if launched.client is None:
            raise SystemExit("the app did not listen")
        print(f"instance PID {launched.child.pid} ({proof_app.config()} build)", flush=True)
        template_path, project = template(launched.client, work)
        for n in ns:
            table.append(one_n(launched.client, launched.child.pid, probe, template_path,
                               project, work, n, args.headroom, physical))
    finally:
        launched.stop()
    n_max, passed_all = None, True
    for record in table:
        ok = all(record["pass"].values())
        passed_all = passed_all and ok
        if passed_all:
            n_max = record["n"]
    verdict = (f"raise MAX_CLIPS to {n_max}" if n_max and n_max > 4096
               else "keep 4,096")
    results = {"table": table, "n_max": n_max, "verdict": verdict, "physical_bytes": physical,
               "limits": LIMITS, "headroom": args.headroom, "app": str(binary),
               "build": proof_app.config(), "probe_error": probe_error,
               "parity": parity(log), "proof": args.proof}
    path = rule.write_results(SPIKE, results, folder=work.name)
    print(f"N_max {n_max}: {verdict}")
    print(f"results: {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
