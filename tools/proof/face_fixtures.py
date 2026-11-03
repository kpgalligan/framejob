#!/usr/bin/env python3
"""Road map "creator-jobs" CJ3 — the face fixtures (spike CJ-S2, `faces_proof.py`).

    python3 tools/proof/face_fixtures.py [--force]

Every file lands in `tools/proof/media/analysis/` (gitignored) beside CJ2a's
fixtures and is reused while it probes as made (size, fps, frame count);
`--force` remakes them. The source pictures are read in place from
`/System/Library/Photos/Resources/FlexAudio/` (the album covers macOS ships);
a missing one is a scored failure naming its path (`FAIL fixtures …`, exit 1).

`COVER` is the two-person cover; `CROP` (x, y, side in its 256 × 256 pixels)
is a square around the front, lower-right man that Vision finds exactly one
face in (checked on every make). The truth of a fixture at time t is the
overlay's top-left corner at t plus the face box the spike probe's `image`
mode finds on the source picture, scaled to the overlay's side (`truth`).

- `faces_moving.mov`: the crop at `SIDE` (540) drifting over black at
  1920 × 1080, 30 fps, 60 s, H.264 (libx264), the moving still's cosine
  drift: x = (W − S)(½ − ½ cos 2πt/23), y = (H − S)(½ − ½ cos 2πt/17).
- `faces_moving_4k.mov`: the same at 3840 × 2160 (the crop at 1080), 30 fps,
  60 s, HEVC (hevc_videotoolbox, 8-bit).
- `faces_small.mov`: the crop scaled so its face box is an eighth of the
  frame's height (`small_side`), the same drift, 1080p30, 60 s.
- `faces_two.mov`: the whole cover at 1080 × 1080, centred on 1920 × 1080,
  still for 5 s and then sliding UP at `TWO_SPEED` px/s, 20 s: the back
  (upper-left) man's face leaves through the top at `two_leaves()` while the
  front man's is still whole. (The two faces overlap in x, so a slide left
  cannot take one face out with the other still whole.)
- `faces_portrait.mov` (1080 × 1920 upright) and `faces_portrait_rot.mov`
  (its frames turned a quarter anticlockwise, coded 1920 × 1080 and tagged
  `-display_rotation -90` to display as the upright one): the crop at 540 with
  the drift, 30 fps, 20 s, H.264.
- `faces_converting.mov`: `faces_moving`'s picture at 25 fps, 20 s, H.264 —
  `faces_proof.py` sets `set_media_color {log: "slog3"}` on it, so it reads
  through the converted reader.
- `subjects_moving.mov` (road map VR1, spike VR-S1): the whole cover at 720
  drifting on the moving still's cosine path over 1920 × 1080, 30 fps, 60 s,
  H.264 — made because Vision's whole-body person request found a person in
  under 95 % of `faces_moving`'s samples (a face crop is not a body); spec §11
  VR-4's amendment cites both modes' figures on it. Its truth is both cover
  faces at the drift.

`faces.json` holds each FlexAudio image's SHA-256, the crop, each fixture's
overlay (side, path), size, fps, duration and SHA-256, and the face boxes the
`image` mode finds on the cover and on the crop.
"""

import argparse
import hashlib
import json
import math
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import swift_build  # noqa: E402

OUT = ROOT / "tools/proof/media/analysis"
WORK = ROOT / "tools/proof/work/creator_spike/faces"
FLEX = Path("/System/Library/Photos/Resources/FlexAudio")
COVER = FLEX / "e5fc4933-8a24-410e-9e4a-ec155980a389.jpg"
CROP = (52, 125, 130)  # x, y, side in COVER's pixels: the front man alone
SIDE = 540
TWO_HOLD = 5.0
TWO_SPEED = 60.0
SUBJECTS_SIDE = 720
TICKS = 600_000


class Missing(Exception):
    pass


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


def stream(path):
    """{width, height, fps, frames, rotation} of the first video stream, or None."""
    run = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=width,height,r_frame_rate,nb_read_packets"
                          ":stream_side_data=rotation", "-of", "json", str(path)],
                         capture_output=True, text=True, timeout=600)
    if run.returncode != 0:
        return None
    streams = json.loads(run.stdout).get("streams") or []
    if not streams:
        return None
    s = streams[0]
    num, den = (int(v) for v in s["r_frame_rate"].split("/"))
    rotation = 0
    for side in s.get("side_data_list") or []:
        if "rotation" in side:
            rotation = int(side["rotation"])
    return {"width": s["width"], "height": s["height"], "fps": num / den,
            "frames": int(s.get("nb_read_packets", 0)), "rotation": rotation}


def frame_ticks(path):
    """Every frame's presentation time in ticks, from ffprobe, sorted."""
    run = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "packet=pts_time", "-of", "json", str(path)], capture_output=True,
                         text=True, timeout=600)
    packets = json.loads(run.stdout).get("packets") or []
    return sorted(round(float(p["pts_time"]) * TICKS) for p in packets if "pts_time" in p)


# ---- the spike probe's `image` mode --------------------------------------------

_binary = None


def spike_binary(sources=None):
    """`creator_spike/faces_spike.swift` over `app/Sources`, optimised."""
    global _binary
    if _binary is not None and sources is None:
        return _binary
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "creator_spike/faces_spike.swift", entry)
    binary = WORK / "faces-spike"
    swift_build.build(sources=[*swift_build.app_sources(sources), entry], output=binary,
                      optimize=True)
    if sources is None:
        _binary = binary
    return binary


def image_faces(path):
    run = subprocess.run([str(spike_binary()), "image", str(path)], capture_output=True,
                         text=True, timeout=300)
    if run.returncode != 0:
        raise SystemExit(f"faces_spike image {path}: {run.stderr[-400:]}")
    return json.loads(run.stdout.strip().splitlines()[-1])


# ---- the pictures --------------------------------------------------------------

def sources():
    """The crop as a PNG and both pictures' face boxes; raises `Missing`."""
    if not COVER.exists():
        raise Missing(str(COVER))
    WORK.mkdir(parents=True, exist_ok=True)
    crop = WORK / "crop.png"
    x, y, side = CROP
    if not crop.exists() or crop.stat().st_mtime < COVER.stat().st_mtime:
        ffmpeg(["-i", str(COVER), "-vf", f"crop={side}:{side}:{x}:{y}", "-frames:v", "1"], crop)
    cover_faces = image_faces(COVER)["faces"]
    crop_faces = image_faces(crop)["faces"]
    if len(cover_faces) != 2:
        raise SystemExit(f"Vision finds {len(cover_faces)} faces on the cover, not 2")
    if len(crop_faces) != 1:
        raise SystemExit(f"Vision finds {len(crop_faces)} faces on the crop, not exactly 1")
    return crop, cover_faces, crop_faces


def drift(width, height, side):
    x = f"({width}-{side})*(0.5-0.5*cos(2*PI*t/23))"
    y = f"({height}-{side})*(0.5-0.5*cos(2*PI*t/17))"
    return x, y


def drift_at(width, height, side, t):
    """ffmpeg's overlay position at t (it truncates the expression to an
    integer pixel)."""
    x = (width - side) * (0.5 - 0.5 * math.cos(2 * math.pi * t / 23))
    y = (height - side) * (0.5 - 0.5 * math.cos(2 * math.pi * t / 17))
    return math.floor(x), math.floor(y)


def small_side(crop_faces):
    return 2 * round(1080 / 8 / crop_faces[0]["box"][3] / 2)


# Each fixture: (file, frame w, h, fps, seconds, picture, side or None, codec).
def specs(crop_faces):
    return {
        "faces_moving": ("faces_moving.mov", 1920, 1080, 30, 60, "crop", SIDE, "h264"),
        "faces_moving_4k": ("faces_moving_4k.mov", 3840, 2160, 30, 60, "crop", 2 * SIDE, "hevc"),
        "faces_small": ("faces_small.mov", 1920, 1080, 30, 60, "crop", small_side(crop_faces),
                        "h264"),
        "faces_two": ("faces_two.mov", 1920, 1080, 30, 20, "cover", 1080, "h264"),
        "faces_portrait": ("faces_portrait.mov", 1080, 1920, 30, 20, "crop", SIDE, "h264"),
        "faces_converting": ("faces_converting.mov", 1920, 1080, 25, 20, "crop", SIDE, "h264"),
        "subjects_moving": ("subjects_moving.mov", 1920, 1080, 30, 60, "cover_moving",
                            SUBJECTS_SIDE, "h264"),
    }


def two_y(t):
    return -math.floor(max(0.0, t - TWO_HOLD) * TWO_SPEED)


def make_one(spec, crop, force):
    name, width, height, fps, seconds, picture, side, codec = spec
    out = OUT / name
    got = stream(out) if out.exists() and not force else None
    if got and (got["width"], got["height"], round(got["fps"])) == (width, height, fps) \
            and got["frames"] == fps * seconds:
        return out
    source = COVER if picture in ("cover", "cover_moving") else crop
    if picture == "cover":
        x, y = str((width - side) // 2), f"-floor(max(0,t-{TWO_HOLD})*{TWO_SPEED})"
    else:
        x, y = drift(width, height, side)
    graph = (f"color=c=black:size={width}x{height}:rate={fps}:duration={seconds}[bg];"
             f"[0:v]scale={side}:{side}:flags=bicubic,format=yuv420p[fg];"
             f"[bg][fg]overlay=x='floor({x})':y='floor({y})':shortest=1:eval=frame,"
             f"format=yuv420p[v]")
    encode = (["-c:v", "libx264", "-crf", "16", "-pix_fmt", "yuv420p"] if codec == "h264" else
              ["-c:v", "hevc_videotoolbox", "-b:v", "40M", "-tag:v", "hvc1",
               "-pix_fmt", "yuv420p"])
    ffmpeg(["-loop", "1", "-framerate", str(fps), "-i", str(source), "-filter_complex", graph,
            "-map", "[v]", "-t", str(seconds), *encode, "-r", str(fps),
            "-video_track_timescale", "600"], out)
    got = stream(out)
    if not got or got["frames"] != fps * seconds:
        raise SystemExit(f"{name} probes as {got}, not {fps * seconds} frames")
    return out


def make_rotated(upright, force):
    out = OUT / "faces_portrait_rot.mov"
    got = stream(out) if out.exists() and not force else None
    if got and (got["width"], got["height"]) == (1920, 1080) and got["frames"] == 600 \
            and abs(got["rotation"]) == 90 and out.stat().st_mtime >= upright.stat().st_mtime:
        return out
    coded = WORK / "portrait_coded.mov"
    ffmpeg(["-i", str(upright), "-vf", "transpose=2", "-c:v", "libx264", "-crf", "16",
            "-pix_fmt", "yuv420p", "-video_track_timescale", "600"], coded)
    ffmpeg(["-display_rotation", "-90", "-i", str(coded), "-c", "copy"], out)
    got = stream(out)
    if not got or (got["width"], got["height"]) != (1920, 1080) or abs(got["rotation"]) != 90:
        raise SystemExit(f"faces_portrait_rot.mov probes as {got}")
    return out


# ---- the truth -----------------------------------------------------------------

def truth(name, t, record):
    """The truth face boxes at t s, top-left frame, 0…1 of the display picture:
    one box for a crop fixture, [back, front] for `faces_two` and
    `subjects_moving`."""
    row = record["fixtures"][name]
    width, height = row["size"]
    side = row["side"]
    if name == "faces_two":
        ox, oy = (width - side) // 2, two_y(t)
        boxes = record["cover_faces"]
    else:
        ox, oy = drift_at(width, height, side, t)
        boxes = record["cover_faces" if row["picture"] == "cover_moving" else "crop_faces"]
    return [((ox + b[0] * side) / width, (oy + b[1] * side) / height, b[2] * side / width,
             b[3] * side / height) for b in (f["box"] for f in boxes)]


def two_leaves(record):
    """The time the back man's truth box is wholly above the frame, and the
    time the front man's stops being whole."""
    side = record["fixtures"]["faces_two"]["side"]
    back, front = (f["box"] for f in record["cover_faces"])
    bottom = (back[1] + back[3]) * side
    top = front[1] * side
    return TWO_HOLD + bottom / TWO_SPEED, TWO_HOLD + top / TWO_SPEED


# ---- the manifest --------------------------------------------------------------

def make(force=False):
    """Every face fixture; the record (`faces.json`). Raises `Missing`."""
    crop, cover_faces, crop_faces = sources()
    record = {"cover": str(COVER), "cover_sha256": sha256(COVER), "crop": list(CROP),
              "crop_png_sha256": sha256(crop), "cover_faces": cover_faces,
              "crop_faces": crop_faces, "fixtures": {}}
    for key, spec in specs(crop_faces).items():
        path = make_one(spec, crop, force)
        name, width, height, fps, seconds, picture, side, codec = spec
        record["fixtures"][key] = {
            "path": str(path), "size": [width, height], "fps": fps, "seconds": seconds,
            "picture": picture, "side": side, "codec": codec, "sha256": sha256(path),
            "overlay": ("x=(W-S)/2, y=-floor(max(0,t-5)*60)" if picture == "cover" else
                        "x=floor((W-S)(1/2-cos(2πt/23)/2)), y=floor((H-S)(1/2-cos(2πt/17)/2))")}
    rotated = make_rotated(OUT / "faces_portrait.mov", force)
    portrait = dict(record["fixtures"]["faces_portrait"])
    portrait.update({"path": str(rotated), "sha256": sha256(rotated), "coded": [1920, 1080],
                     "display_rotation": -90})
    record["fixtures"]["faces_portrait_rot"] = portrait
    leaves, front_cut = two_leaves(record)
    record["two_leaves_s"], record["two_front_whole_until_s"] = leaves, front_cut
    (OUT / "faces.json").write_text(json.dumps(record, indent=1, sort_keys=True))
    return record


def path(name):
    return OUT / f"{name}.mov"


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args(argv)
    try:
        record = make(args.force)
    except Missing as missing:
        print(f"FAIL fixtures: {missing} is missing")
        return 1
    for name, row in sorted(record["fixtures"].items()):
        print(f"ok {row['path']} {row['size']} {row['fps']} fps {row['seconds']} s")
    print(f"crop faces {record['crop_faces']}")
    print(f"two: the back face leaves at {record['two_leaves_s']:.3f} s; the front is whole "
          f"until {record['two_front_whole_until_s']:.3f} s")
    return 0


if __name__ == "__main__":
    sys.exit(main())
