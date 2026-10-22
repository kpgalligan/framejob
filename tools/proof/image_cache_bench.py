#!/usr/bin/env python3
"""Issue #127 G6 phase 5 — the decoded-image cache's engine bench (spec §11
G-39 (g)). It measures what the cache's stored-deflate RGBA8 PNG copies save
when resvg draws a scene, on the graphic clip covering `--from`: the test
`graphic/tests/image_bench.rs` alternates ORIG (the cache at a limit of 0)
with CACHED (1 GiB, after one untimed warm frame). The spike that decided
G-39 ran a STORED arm in CACHED's place, the library's PNG assets swapped for
copies the test built; its figures are G-39 (g)'s.

    python3 tools/proof/image_cache_bench.py PACKAGE [--from 25120000] [--frames 40] [--rounds 5]

The package is COPIED to `tools/proof/work/image-cache-bench/` and only the
copy is opened; the original is never opened, saved or committed. One owned
instance (`proof_app`'s default app: the SVG text does not depend on the
build), launched and stopped by PID on a scratch socket, opens the copy,
finds with `get_project` the clip covering `--from` on the frontmost track,
and answers `--frames` evenly spaced frames of that clip's graphic through
`render_graphic {format: "svg"}` with the clip's own props and size. They
are written to `svg/NNNN.svg` with `frames.json {width, height, files}`,
beside the copy's `graphics/assets` and `graphics/fonts`. Then `pmset -g`'s
powermode line and `sysctl -n vm.loadavg` are printed, and
`cd graphic && cargo test --release --test image_bench -- --ignored
--nocapture section_scene_orig_against_cached --exact` runs with `GRAPHIC_IMAGE_BENCH=<that folder>` and
`GRAPHIC_IMAGE_BENCH_ROUNDS`; its output is printed whole. Every child runs
under `graphics_spike/bounded.py`. `dump_scene` is the copy, launch,
dump and stop; `raster_bench.py` (G6 phase 6) dumps through it too.

Exit 0 iff the dump completed and the bench passed (its assertion: every
frame's bytes equal across the arms).
"""

import argparse
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import graphics_prefetch_proof as gp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/image-cache-bench"
TICKS = 600_000
BENCH_BOUND = 3600


def covering_clip(project, at, module=None):
    """The graphic clip covering `at` on the frontmost track (the tracks'
    last in order), or None; with `module`, only a clip whose graphic's
    name is `module`."""
    order = {track["id"]: index for index, track in enumerate(project.get("tracks", []))}
    found = [clip for clip in project.get("clips", [])
             if clip.get("graphic") and clip["start"] <= at < clip["start"] + clip["duration"]
             and (module is None or clip["graphic"].get("name") == module)]
    found.sort(key=lambda clip: order.get(clip["track"], -1))
    return found[-1] if found else None


def dump(client, package, clip, fps, count, out):
    """Writes the frames' SVGs and frames.json; (ok, detail)."""
    graphic = clip["graphic"]
    length = clip["duration"] * fps[0] // (fps[1] * TICKS)
    start = graphic.get("in") or 0
    if count > 1:
        frames = [start + round(i * (length - 1) / (count - 1)) for i in range(count)]
    else:
        frames = [start]
    (out / "svg").mkdir(parents=True)
    files = []
    for index, frame in enumerate(frames):
        got = gp.attempt(client, "render_graphic", {
            "project": str(package), "format": "svg", "name": graphic["name"],
            "frames": [frame], "props": graphic.get("props") or {},
            "width": graphic["width"], "height": graphic["height"]})
        reply = got.get("reply")
        if not got["ok"] or not isinstance(reply, dict) or not reply.get("ok"):
            return False, f"frame {frame}: {got.get('error', reply)}"
        name = f"svg/{index:04d}.svg"
        (out / name).write_text(reply["svg"])
        files.append(name)
    (out / "frames.json").write_text(json.dumps(
        {"width": graphic["width"], "height": graphic["height"], "files": files,
         "frames": frames}))
    return True, f"{graphic['name']} clip {clip['id']}: frames {frames[0]}…{frames[-1]}"


def dump_scene(source, at, frames, work, module=None):
    """`source` copied under `work` (emptied first; the original is never
    opened), one owned instance opening the copy, `frames` frames of the
    graphic clip covering `at` (with `module`, of that module) dumped into
    `work/dump` with the copy's assets and fonts, the instance stopped by
    PID and its log checked. (ok, the dump folder, detail)."""
    out = work / "dump"
    if not (source / "project.json").is_file():
        return False, out, f"{source} is not a package"
    tree_copy.remove_tree(work)
    work.mkdir(parents=True)
    package = work / source.name
    shutil.copytree(source, package, symlinks=True)
    out.mkdir()
    instance = gp.Instance(proof_app.binary(), work / "instance.log", off=False)
    try:
        client = instance.start()
        if client is None or not gp.opened(client, package):
            return False, out, "the instance did not open the copy"
        project = gp.project_of(client, package)
        clip = covering_clip(project, at, module)
        if clip is None:
            named = f" of {module}" if module else ""
            return False, out, f"no graphic clip{named} covers {at}"
        ok, detail = dump(client, package, clip, project["canvas"]["fps"], frames, out)
    finally:
        instance.stop()
    if not ok:
        return False, out, f"the dump failed: {detail}"
    complaints = gp.complaints()
    if complaints:
        return False, out, f"the log complains: {complaints}"
    for folder in ("assets", "fonts"):
        if (package / "graphics" / folder).is_dir():
            shutil.copytree(package / "graphics" / folder, out / folder)
    return True, out, detail


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--from", dest="at", type=int, default=25_120_000)
    parser.add_argument("--frames", type=int, default=40)
    parser.add_argument("--rounds", type=int, default=5)
    args = parser.parse_args()
    source = args.package.expanduser().resolve()
    print(f"#127 G6 phase 5 — the image-cache bench of {source.name} at {args.at}", flush=True)
    ok, out, detail = dump_scene(source, args.at, args.frames, WORK)
    if not ok:
        print(f"bench FAIL — {detail}")
        return 1
    print(f"  dump ok — {detail}", flush=True)
    power = bounded.run(["pmset", "-g"], 30)["stdout"]
    print("  " + next((line.strip() for line in power.splitlines() if "powermode" in line),
                      "powermode: not reported"), flush=True)
    print(f"  load average {gp.loadavg()}", flush=True)
    got = bounded.run(
        ["cargo", "test", "--release", "--test", "image_bench", "--", "--ignored", "--nocapture",
         "section_scene_orig_against_cached", "--exact"],
        BENCH_BOUND, cwd=str(ROOT / "graphic"),
        env=bounded.child_env({"GRAPHIC_IMAGE_BENCH": str(out),
                               "GRAPHIC_IMAGE_BENCH_ROUNDS": str(args.rounds)}))
    print(got["stdout"], flush=True)
    if got["rc"] != 0:
        print(got["stderr"][-4000:])
    print(f"  load average after {gp.loadavg()}", flush=True)
    good = got["rc"] == 0 and not got["expired"]
    print(f"bench {'ok' if good else 'FAIL'} — cargo exited {got['rc']}"
          f"{' (expired)' if got['expired'] else ''} in {got['seconds']} s")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
