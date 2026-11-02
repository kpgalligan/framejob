#!/usr/bin/env python3
"""Road map "creator-jobs" CJ2a, spike CJ-S3 — the lane (decides CJ-21 and
CJ-23).

    python3 tools/proof/creator_spike/lane_spike.py              # (a) and (c)
    python3 tools/proof/creator_spike/lane_spike.py --playback   # (b), over MCP
    python3 tools/proof/creator_spike/lane_spike.py --playback --kind masks   # (b), CO1
    python3 tools/proof/creator_spike/lane_spike.py --playback --kind faces   # (b), CJ3

(a) and (c): `lane_spike.swift`, built from `app/Sources` through
`swift_build.py`, decodes a whole file through the direct reader and, for a
file whose picture converts, through the converted reader, at long sides 256
and 1280, as one job and as two at once; every measurement three times, the
median kept (three lanes share the machine). Inputs: S-TH4 under
`tools/proof/media/creator/S-TH4/` when it exists, else the synthetic 4K HEVC
10-bit HLG file and the 1080p H.264 file (`analysis_fixtures.py`), S-TH4 then
owed. Rules (the road map's): (a) width 2 only if two jobs reach at least
1.5× one job's throughput — applied at shots' size (256) on each file through
the reader (c) gives it, every one of them; else 1. (c) converted for
converting media, direct for the rest. `callWaitLimit` (CJ-25, fixed by this
phase's spec): the time ten minutes of the 4K HLG source take through the
converted reader at 256, × 2, rounded up to 10 s, clamped to 30…300 s.

(b) `--playback` (needs the Debug or Release app with this phase's lane):
`play_preview`'s composed frames over 20 s of a 1080p30 timeline, idle, then
with another document's `shots` job wanted through `analysis_job` (which
returns at once), three times each, median. A drop of more than 2 % turns the
pause on (CJ-21's amendment).

`--kind masks` (road map CO1's head, CO-12): (b) re-run with a `masks` job on
the ten-minute still over its first 120 s, wanted through `analysis_job`; each
busy run's document is its own and is CLOSED after the run (the job
cancelled) instead of drained. Results in `CJ-S3-masks/results.json`.
`--kind faces` (road map CJ3, CJ-35): the same with a `faces` job over the
still's whole ten minutes (a 120 s window landed in about 9 s, inside the 20 s
play); results in `CJ-S3-faces/results.json`.

Writes `tools/proof/work/creator_spike/CJ-S3/results.json` (merged: a
`--playback` run keeps (a) and (c)).
"""

import argparse
import json
import math
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
import analysis_fixtures as fixtures  # noqa: E402
import rule  # noqa: E402
import swift_build  # noqa: E402

WORK = ROOT / "tools/proof/work/creator_spike/CJ-S3"
STH4 = ROOT / "tools/proof/media/creator/S-TH4"
RUNS = 3


def resources(out):
    """`Blank.mp4` and a `default.metallib` of the tree's `Compositor.metal`
    beside the binary (its `Bundle.main`), as `graphics_proof.py`'s probe has
    them: the converted reader's compositor loads its library from there."""
    import bounded  # noqa: E402 — on swift_build's path

    shared = ROOT / "app/Resources"
    if not (out / "Blank.mp4").exists():
        shutil.copy2(shared / "Blank.mp4", out / "Blank.mp4")
    shader = shared / "Shaders/Compositor.metal"
    metallib, air = out / "default.metallib", out / "Compositor.air"
    if not metallib.exists() or shader.stat().st_mtime > metallib.stat().st_mtime:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o",
                            str(air)], 300)
        if step["rc"] == 0:
            step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                                str(metallib)], 300)
        if step["rc"] != 0 or not metallib.exists():
            raise SystemExit(f"the shader did not build: {step['stderr'][-400:]}")


def build():
    WORK.mkdir(parents=True, exist_ok=True)
    resources(WORK)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "lane_spike.swift", entry)
    sources = sorted(p for p in (ROOT / "app/Sources").glob("*.swift") if p.name != "main.swift")
    binary = WORK / "lane-spike"
    swift_build.build(sources=[*sources, entry], output=binary, optimize=True)
    return binary


def measure(binary, movie, mode, side, jobs):
    runs = []
    for _ in range(RUNS):
        run = subprocess.run([str(binary), str(movie), mode, str(side), str(jobs)],
                             capture_output=True, text=True, timeout=1800)
        if run.returncode != 0:
            return {"error": run.stderr[-400:] or run.stdout[-400:]}
        runs.append(json.loads(run.stdout.strip().splitlines()[-1]))
    fps = [r["fps"] for r in runs]
    return {"fps_runs": fps, "fps": statistics.median(fps), "frames": runs[0]["frames"],
            "size": [runs[0]["width"], runs[0]["height"]]}


def inputs():
    owned = sorted(STH4.glob("*.mov")) + sorted(STH4.glob("*.mp4")) if STH4.exists() else []
    if owned:
        return {"S-TH4": owned[0]}, None
    return ({"hlg_4k": fixtures.hlg_4k(), "h264_1080": fixtures.h264_1080()},
            "S-TH4 is missing: synthetic files, S-TH4 owed")


def lane_rows():
    binary = build()
    files, owed = inputs()
    table = {}
    for name, movie in files.items():
        for mode in ("direct", "converted"):
            for side in (256, 1280):
                for jobs in (1, 2):
                    row = measure(binary, movie, mode, side, jobs)
                    table[f"{name}/{mode}/{side}/{jobs}"] = row
                    print(f"{name} {mode} {side} ×{jobs}: {row.get('fps', row.get('error'))}",
                          flush=True)
    return table, owed


def decide(table):
    # (c): the reader each file gets — converted where it converts (the
    # converted run answers), direct for the rest.
    chosen, ratios = {}, {}
    for key in table:
        name = key.split("/")[0]
        converted = table.get(f"{name}/converted/256/1", {})
        chosen[name] = "converted" if "fps" in converted else "direct"
    for name, mode in chosen.items():
        one = table[f"{name}/{mode}/256/1"]["fps"]
        two = table[f"{name}/{mode}/256/2"]["fps"]
        ratios[name] = two / one
    width = 2 if all(r >= 1.5 for r in ratios.values()) else 1
    hlg = table.get("hlg_4k/converted/256/1") or table.get("S-TH4/converted/256/1") or {}
    ten_minutes = 10 * 60 * 30 / hlg["fps"] if "fps" in hlg else None
    limit = None
    if ten_minutes is not None:
        limit = min(300, max(30, math.ceil(ten_minutes * 2 / 10) * 10))
    direct_cost = {}
    for name in chosen:
        d = table.get(f"{name}/direct/256/1", {}).get("fps")
        c = table.get(f"{name}/converted/256/1", {}).get("fps")
        if d and c:
            direct_cost[name] = d / c  # the converted reader's cost per frame, × the direct one
    return {"reader": chosen, "two_over_one": ratios, "picture_width": width,
            "ten_minutes_4k_hlg_converted_256_s": ten_minutes, "call_wait_limit_s": limit,
            "converted_cost_over_direct": direct_cost}


def playback(socket, args):
    import mcp  # noqa: E402

    if args.kind in ("masks", "faces"):
        return playback_kind(socket, args.kind)
    client = mcp.MCP(socket)
    movie = fixtures.h264_1080()
    package = WORK / "playback.framejob"
    other = WORK / "other.framejob"
    for path in (package, other):
        try:
            client.call("close_project", project=str(path), discard=True)
        except Exception:  # noqa: BLE001 — not open
            pass
        if path.exists():
            shutil.rmtree(path)
    client.call("new_project", path=str(package))
    try:  # a new project is 1920 × 1080 at 30 already: an identity
        client.call("set_canvas", project=str(package), width=1920, height=1080, fps=[30, 1])
    except mcp.ToolError:
        pass
    state = client.call("get_project", project=str(package))["project"]
    track = state["tracks"][0]["id"]
    media = client.call("import_media", project=str(package), path=str(movie))["media"]
    client.call("add_clip", project=str(package), track=track, media=media, at=0)
    client.call("save_project", project=str(package))
    # Another document, with a ten-minute file per busy run (each its own
    # cache, so each run's job really decodes): APFS clones of the still.
    client.call("new_project", path=str(other))
    still = fixtures.moving_still(10)
    stills = []
    for n in range(RUNS):
        clone = WORK / f"still-{n}.mov"
        clone.unlink(missing_ok=True)
        subprocess.run(["cp", "-c", str(still), str(clone)], check=True)
        stills.append(client.call("import_media", project=str(other), path=str(clone))["media"])
    client.call("save_project", project=str(other))

    def composed():
        client.call("set_playhead", project=str(package), t=0)
        answer = client.call("play_preview", project=str(package), seconds=20)
        return answer["frames_composed"]

    def drain(media):
        # A Debug build's job can outlast one wait: wait until it has ended.
        for _ in range(20):
            answer = client.call("analysis_job", wait=60)
            row = next((j for j in answer["jobs"] if j["media"] == media), {})
            if row.get("outcome"):
                return row
        return row

    idle, busy, jobs = [], [], []
    for n in range(RUNS):
        idle.append(composed())
        wanted = client.call("analysis_job", project=str(other), media=stills[n], kind="shots")
        busy.append(composed())
        row = drain(stills[n])
        jobs.append({"hit": wanted["wanted"]["hit"], "started_at": row.get("started_at"),
                     "ended_at": row.get("ended_at"), "outcome": row.get("outcome")})
    for path in (package, other):
        try:
            client.call("close_project", project=str(path), discard=True)
        except Exception:  # noqa: BLE001
            pass
    i, b = statistics.median(idle), statistics.median(busy)
    drop = (i - b) / i if i else None
    return {"idle_runs": idle, "busy_runs": busy, "jobs": jobs, "idle": i, "busy": b,
            "drop": drop, "pause": drop is not None and drop > 0.02}


def playback_kind(socket, kind):
    """(b) with a `kind` job (masks, CO1; faces, CJ3): per run an idle play,
    then a document of its own wanting the job over the still's first 120 s
    (masks) or all of it (faces, so the job outlasts the play), the play, and
    the document closed (its job cancelled)."""
    import mcp  # noqa: E402

    client = mcp.MCP(socket)
    folder = ROOT / f"tools/proof/work/creator_spike/CJ-S3-{kind}"
    folder.mkdir(parents=True, exist_ok=True)
    movie = fixtures.h264_1080()
    package = folder / "playback.framejob"
    try:
        client.call("close_project", project=str(package), discard=True)
    except Exception:  # noqa: BLE001 — not open
        pass
    if package.exists():
        shutil.rmtree(package)
    client.call("new_project", path=str(package))
    state = client.call("get_project", project=str(package))["project"]
    track = state["tracks"][0]["id"]
    media = client.call("import_media", project=str(package), path=str(movie))["media"]
    client.call("add_clip", project=str(package), track=track, media=media, at=0)
    client.call("save_project", project=str(package))
    still = fixtures.moving_still(10)

    def composed():
        client.call("set_playhead", project=str(package), t=0)
        return client.call("play_preview", project=str(package), seconds=20)["frames_composed"]

    idle, busy, jobs = [], [], []
    for n in range(RUNS):
        idle.append(composed())
        other = folder / f"other-{n}.framejob"
        if other.exists():
            shutil.rmtree(other)
        client.call("new_project", path=str(other))
        clone = folder / f"still-{n}.mov"
        clone.unlink(missing_ok=True)
        subprocess.run(["cp", "-c", str(still), str(clone)], check=True)
        media_n = client.call("import_media", project=str(other), path=str(clone))["media"]
        client.call("save_project", project=str(other))
        seconds = 600 if kind == "faces" else 120
        wanted = client.call("analysis_job", project=str(other), media=media_n, kind=kind,
                             **{"from": 0, "to": seconds * 600_000})
        busy.append(composed())
        # The last such row: an instance that ran this before lists that run's
        # jobs first, under the same project path and media id.
        row = ([j for j in client.call("analysis_job")["jobs"]
                if j["media"] == media_n and j["project"]
                and Path(j["project"]).resolve() == other.resolve()] or [{}])[-1]
        client.call("close_project", project=str(other), discard=True)
        jobs.append({"hit": wanted["wanted"]["hit"], "started_at": row.get("started_at"),
                     "ended_at": row.get("ended_at"), "outcome": row.get("outcome")})
    try:
        client.call("close_project", project=str(package), discard=True)
    except Exception:  # noqa: BLE001
        pass
    i, b = statistics.median(idle), statistics.median(busy)
    drop = (i - b) / i if i else None
    return {"kind": kind, "idle_runs": idle, "busy_runs": busy, "jobs": jobs, "idle": i,
            "busy": b, "drop": drop, "pause": drop is not None and drop > 0.02}


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--playback", action="store_true")
    parser.add_argument("--socket")
    parser.add_argument("--kind", choices=("shots", "masks", "faces"), default="shots")
    args = parser.parse_args(argv)
    rule.check_rule("CJ-S3")
    folder = f"CJ-S3-{args.kind}" if args.kind in ("masks", "faces") else None
    path = (WORK.parent / folder if folder else WORK) / "results.json"
    previous = json.loads(path.read_text()) if path.exists() else {}
    results = {k: previous[k] for k in ("lane", "verdict", "owed") if k in previous}
    if args.playback:
        if not args.socket:
            raise SystemExit("--playback needs --socket of a running Frame Job with the lane")
        results["playback"] = playback(args.socket, args)
        print(json.dumps(results["playback"], indent=1))
    else:
        table, owed = lane_rows()
        results["lane"], results["owed"] = table, owed
        results["verdict"] = decide(table)
        print(json.dumps(results["verdict"], indent=1))
    written = rule.write_results("CJ-S3", results, folder=folder)
    print(f"results: {written}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
