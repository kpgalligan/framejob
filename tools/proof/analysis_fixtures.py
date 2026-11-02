#!/usr/bin/env python3
"""Road map "creator-jobs" CJ2a — the analysis fixtures, made with ffmpeg
(spikes CJ-S3 and CJ-S4, `analysis_proof.py`; CJ2b's `shot_split_proof.py`).

    python3 tools/proof/analysis_fixtures.py                 # every file fixture
    python3 tools/proof/analysis_fixtures.py --flattened SOCK  # and the 40-clip export

Every file lands in `tools/proof/media/analysis/` (gitignored) and is reused
while it probes as made; `--force` remakes them.

- `shots.mov`: 1280 × 720 at 30 fps, 380 frames. `testsrc` [0, 60), the
  same `testsrc` hue-shifted [60, 120), `testsrc2` [120, 180) with one white
  frame at `FLASH` (150), a green card [180, 240), a FlexAudio cover (`COVER`,
  720 × 720 on black) [240, 300), an `xfade` dissolve into a second cover
  (`COVER_B`) over [300, 330), that cover [330, 380). The hard cuts are
  `SHOTS_CUTS` (60, 120, 180, 240); the cut at 60 changes only chroma (the
  `hue` filter leaves Y alone). The dissolve is between photographs, whose
  histograms move a little each frame; `dissolve_patterns.mov` is the one
  between test patterns.
- `shots_sound.mov` (CJ2b): `shots.mov`'s video stream copied (`-c:v copy`)
  with a 1 kHz sine AAC track of its length, so `detach_audio` gives the
  picture a linked sound (`shot_split_proof.py` S4).
- `dissolve_patterns.mov`: `testsrc` dissolving into `testsrc2` over [60, 90),
  140 frames: CJ-S4's measure of a dissolve between flat-coloured patterns,
  whose every bar crosses a histogram bin in one frame.
- `shots_vfr.mov`: the same frames less `VFR_REMOVED` (119, the frame just
  before the cut at 120, and 270), timestamps kept (`select` and
  `-fps_mode passthrough`).
- `moving_still.mov`: a FlexAudio cover (`COVER`, its SHA-256 in
  `fixtures.json`) at 720 × 720 drifting over black at 1920 × 1080, 30 fps, ten
  minutes: CJ-S4's no-cut input while S-TH1 is missing.
- `hlg_4k.mov`: `testsrc2` at 3840 × 2160, 30 fps, 20 s, HEVC Main 10 tagged
  bt2020/arib-std-b67/bt2020nc (`hdr_proof.py`'s HLG tags, hevc_videotoolbox).
- `h264_1080.mov`: `testsrc2` at 1920 × 1080, 30 fps, 20 s, H.264.
- `variant_{0..3}.mov`: four `testsrc` variants (`testsrc`, `testsrc2`, each
  of them hue-shifted), 1280 × 720, 30 fps, 20 s: the 40-clip project's media.
- `flattened.mp4` and `flattened.json` (`--flattened`): 40 clips cut from the
  variants, no two neighbours alike, laid end to end in a Frame Job project,
  exported by Frame Job (`h264`); the cut list is every clip's start after the
  first, read back from `get_project`, as frames.
"""

import argparse
import hashlib
import json
import os
import random
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "tools/proof/media/analysis"
FLEX = Path("/System/Library/Photos/Resources/FlexAudio")
COVER = FLEX / "18f501e0-4e5d-4af0-95ba-7ad429ee44d8.jpg"
COVER_B = FLEX / "5F39145D-BCF7-42F1-921A-0FAF214F8A88.jpg"
FPS = 30
TICKS = 600000
SHOTS_FRAMES = 380
SHOTS_CUTS = [60, 120, 180, 240]
FLASH = 150
DISSOLVE = (300, 330)
VFR_REMOVED = [119, 270]
HLG_TAGS = ("bt2020", "arib-std-b67", "bt2020nc")
CLIPS = 40


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def ffmpeg(args, out, seconds=1800):
    out.parent.mkdir(parents=True, exist_ok=True)
    temp = out.with_name(out.stem + ".partial" + out.suffix)
    run = subprocess.run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", *args,
                          str(temp)], capture_output=True, text=True, timeout=seconds)
    if run.returncode != 0 or not temp.exists():
        raise SystemExit(f"ffmpeg failed making {out.name}: {run.stderr[-800:]}")
    os.replace(temp, out)
    return out


def probe(path):
    """(frame count, [pts seconds]) of the first video stream."""
    run = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "frame=pts_time", "-of", "json", str(path)],
                         capture_output=True, text=True, timeout=600)
    if run.returncode != 0:
        return None
    frames = json.loads(run.stdout).get("frames") or []
    return [float(f["pts_time"]) for f in frames if "pts_time" in f]


def ready(path, force):
    return path.exists() and not force


def shots(force=False):
    out = OUT / "shots.mov"
    if ready(out, force):
        return out
    size = "1280x720"
    flash = (f"drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='eq(n,{FLASH - 120})'")
    a, b = (f"scale=720:720,pad=1280:720:280:0:black,format=yuv420p,settb=1/{FPS}",) * 2
    graph = (
        f"testsrc=size={size}:rate={FPS}:duration=2,format=yuv420p,settb=1/{FPS}[a];"
        f"testsrc=size={size}:rate={FPS}:duration=2,hue=h=120,format=yuv420p,"
        f"settb=1/{FPS}[h];"
        f"testsrc2=size={size}:rate={FPS}:duration=2,format=yuv420p,{flash},settb=1/{FPS}[b];"
        f"color=c=green:size={size}:rate={FPS}:duration=2,format=yuv420p,settb=1/{FPS}[g];"
        f"[0:v]trim=end_frame=90,setpts=PTS-STARTPTS,{a}[p1];"
        f"[1:v]trim=end_frame=80,setpts=PTS-STARTPTS,{b}[p2];"
        f"[p1][p2]xfade=transition=fade:duration=1:offset=2,format=yuv420p,"
        f"settb=1/{FPS}[px];"
        f"[a][h][b][g][px]concat=n=5:v=1:a=0,setpts=N/({FPS}*TB)[v]")
    ffmpeg(["-loop", "1", "-framerate", str(FPS), "-i", str(COVER), "-loop", "1", "-framerate",
            str(FPS), "-i", str(COVER_B), "-filter_complex", graph, "-map", "[v]", "-c:v",
            "libx264", "-crf", "12", "-pix_fmt", "yuv420p", "-r", str(FPS),
            "-video_track_timescale", "600"], out)
    count = len(probe(out) or [])
    if count != SHOTS_FRAMES:
        raise SystemExit(f"shots.mov has {count} frames, not {SHOTS_FRAMES}")
    return out


def shots_sound(force=False):
    """`shots.mov`'s video copied, with a 1 kHz sine AAC track of its length."""
    source = shots(force)
    out = OUT / "shots_sound.mov"
    if ready(out, force):
        return out
    seconds = SHOTS_FRAMES / FPS
    ffmpeg(["-i", str(source), "-f", "lavfi", "-i",
            f"sine=frequency=1000:sample_rate=48000:duration={seconds:.6f}",
            "-map", "0:v:0", "-map", "1:a:0", "-c:v", "copy", "-c:a", "aac", "-b:a", "128k",
            "-t", f"{seconds:.6f}"], out)
    count = len(probe(out) or [])
    if count != SHOTS_FRAMES:
        raise SystemExit(f"shots_sound.mov has {count} frames, not {SHOTS_FRAMES}")
    return out


def dissolve_patterns(force=False):
    """CJ-S4's finding input: `testsrc` dissolving into `testsrc2` over 30
    frames at [60, 90), 140 frames, no cut."""
    out = OUT / "dissolve_patterns.mov"
    if ready(out, force):
        return out
    size = "1280x720"
    graph = (f"testsrc=size={size}:rate={FPS}:duration=3,format=yuv420p,settb=1/{FPS}[d1];"
             f"testsrc2=size={size}:rate={FPS}:duration=3,trim=end_frame=80,"
             f"setpts=PTS-STARTPTS,format=yuv420p,settb=1/{FPS}[d2];"
             f"[d1][d2]xfade=transition=fade:duration=1:offset=2,format=yuv420p,"
             f"setpts=N/({FPS}*TB)[v]")
    ffmpeg(["-filter_complex", graph, "-map", "[v]", "-c:v", "libx264", "-crf", "12",
            "-pix_fmt", "yuv420p", "-r", str(FPS), "-video_track_timescale", "600"], out)
    return out


def vfr_twin(force=False):
    source = shots(force)
    out = OUT / "shots_vfr.mov"
    if ready(out, force):
        return out
    removed = "+".join(f"eq(n,{n})" for n in VFR_REMOVED)
    ffmpeg(["-i", str(source), "-vf", f"select='not({removed})'", "-fps_mode", "passthrough",
            "-c:v", "libx264", "-crf", "12", "-pix_fmt", "yuv420p",
            "-video_track_timescale", "600"], out)
    times = probe(out) or []
    want = [n for n in range(SHOTS_FRAMES) if n not in VFR_REMOVED]
    got = [round(t * FPS) for t in times]
    if got != want:
        raise SystemExit(f"shots_vfr.mov's frames are not shots.mov's less {VFR_REMOVED}")
    return out


def moving_still(minutes=10, force=False):
    out = OUT / ("moving_still.mov" if minutes == 10 else f"moving_still_{minutes}m.mov")
    if ready(out, force):
        return out
    seconds = int(minutes * 60)
    x = "(1920-720)*(0.5-0.5*cos(2*PI*t/23))"
    y = "(1080-720)*(0.5-0.5*cos(2*PI*t/17))"
    graph = (f"color=c=black:size=1920x1080:rate={FPS}:duration={seconds}[bg];"
             f"[0:v]scale=720:720,format=yuv420p[fg];"
             f"[bg][fg]overlay=x='{x}':y='{y}':shortest=1,format=yuv420p[v]")
    ffmpeg(["-loop", "1", "-framerate", str(FPS), "-i", str(COVER), "-filter_complex", graph,
            "-map", "[v]", "-t", str(seconds), "-c:v", "h264_videotoolbox", "-b:v", "12M",
            "-r", str(FPS), "-video_track_timescale", "600"], out)
    return out


def hlg_4k(force=False):
    out = OUT / "hlg_4k.mov"
    if ready(out, force):
        return out
    primaries, transfer, matrix = HLG_TAGS
    params = f"color_primaries={primaries}:color_trc={transfer}:colorspace={matrix}"
    ffmpeg(["-f", "lavfi", "-i", f"testsrc2=size=3840x2160:rate={FPS}:duration=20",
            "-vf", f"format=yuv420p10le,setparams={params}", "-c:v", "hevc_videotoolbox",
            "-profile:v", "main10", "-pix_fmt", "p010le", "-tag:v", "hvc1", "-b:v", "40M",
            "-color_primaries", primaries, "-color_trc", transfer, "-colorspace", matrix,
            "-video_track_timescale", "600"], out)
    return out


def h264_1080(force=False):
    out = OUT / "h264_1080.mov"
    if ready(out, force):
        return out
    ffmpeg(["-f", "lavfi", "-i", f"testsrc2=size=1920x1080:rate={FPS}:duration=20",
            "-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p",
            "-video_track_timescale", "600"], out)
    return out


VARIANTS = ["testsrc", "testsrc2", "testsrc,hue=h=120", "testsrc2,hue=h=240"]


def variants(force=False):
    made = []
    for index, spec in enumerate(VARIANTS):
        out = OUT / f"variant_{index}.mov"
        made.append(out)
        if ready(out, force):
            continue
        source, _, extra = spec.partition(",")
        chain = f"{source}=size=1280x720:rate={FPS}:duration=20" + (f",{extra}" if extra else "")
        ffmpeg(["-f", "lavfi", "-i", chain, "-c:v", "libx264", "-crf", "14", "-pix_fmt",
                "yuv420p", "-video_track_timescale", "600"], out)
    return made


def plan(seed=7):
    """40 (variant, in frame, length frames), no two neighbours alike."""
    rng = random.Random(seed)
    rows, last = [], None
    for _ in range(CLIPS):
        variant = rng.choice([v for v in range(len(VARIANTS)) if v != last])
        length = rng.randint(15, 75)
        start = rng.randint(0, 20 * FPS - length - 1)
        rows.append((variant, start, length))
        last = variant
    return rows


def flattened(client, force=False):
    """The 40-clip project exported by Frame Job over MCP; (export, cut frames)."""
    out = OUT / "flattened.mp4"
    record = OUT / "flattened.json"
    if out.exists() and record.exists() and not force:
        return out, json.loads(record.read_text())["cuts"]
    files = variants(force)
    package = OUT / "flattened.framejob"
    if package.exists():
        subprocess.run(["rm", "-rf", str(package)], check=True)
    for open_doc in [package]:
        try:
            client.call("close_project", project=str(open_doc), discard=True)
        except Exception:  # noqa: BLE001 — not open
            pass
    if package.exists():
        subprocess.run(["rm", "-rf", str(package)], check=True)
    client.call("new_project", path=str(package))
    project = str(package)
    client.call("set_canvas", project=project, width=1280, height=720, fps=[FPS, 1])
    track = client.call("get_project", project=project)["project"]["tracks"][0]["id"]
    media = [client.call("import_media", project=project, path=str(f))["media"] for f in files]
    position = 0
    for variant, start, length in plan():
        at = position * TICKS // FPS
        clip = client.call("add_clip", project=project, track=track, media=media[variant],
                           at=at)["new_clips"][0]
        client.call("trim_end", project=project, clip=clip, to=at + length * TICKS // FPS)
        if start:
            client.call("slip", project=project, clip=clip, delta=start * TICKS // FPS)
        position += length
    state = client.call("get_project", project=project)["project"]
    starts = sorted(c["start"] for c in state["clips"])
    cuts = [round(s * FPS / TICKS) for s in starts[1:]]
    if out.exists():
        out.unlink()
    client.export(project=project, preset="h264", path=str(out))
    client.call("close_project", project=project, discard=True)
    record.write_text(json.dumps({"cuts": cuts, "frames": position, "plan": plan()}, indent=1))
    return out, cuts


def manifest():
    rows = {"cover": str(COVER), "cover_sha256": sha256(COVER) if COVER.exists() else None}
    for path in sorted(OUT.glob("*")):
        if path.is_file() and path.suffix in (".mov", ".mp4"):
            rows[path.name] = sha256(path)
    (OUT / "fixtures.json").write_text(json.dumps(rows, indent=1, sort_keys=True))
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--flattened", metavar="SOCKET")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--still-minutes", type=float, default=10)
    args = parser.parse_args(argv)
    for make in (shots, shots_sound, vfr_twin, dissolve_patterns, hlg_4k, h264_1080, variants):
        made = make(args.force)
        print(f"ok {made}")
    print(f"ok {moving_still(args.still_minutes, args.force)}")
    if args.flattened:
        sys.path.insert(0, str(HERE))
        import mcp  # noqa: E402

        out, cuts = flattened(mcp.MCP(args.flattened), args.force)
        print(f"ok {out} ({len(cuts)} cuts)")
    print(json.dumps(manifest(), indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
