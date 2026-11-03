#!/usr/bin/env python3
"""Road map "creator-jobs" SW0 — SW-S2's fixtures (spec §11 SW-2, SW-5).

    python3 tools/proof/creator_spike/angles_fixtures.py --build-4k
    python3 tools/proof/creator_spike/angles_fixtures.py --long
    python3 tools/proof/creator_spike/angles_fixtures.py --remove-long | --clean | --list

Everything lands under the gitignored `tools/proof/media/creator/` and is
never committed. The source is lavfi `testsrc2=size=3840x2160` with
`noise=alls=16:allf=t` and a hue per angle; a long file is a stream-copy concat
(`-f concat -safe 0 … -c copy`) of repeats of a one-minute encode, so the
encoding costs a minute per file and the length costs only disk.

F-4K (`f4k/`, `--build-4k`, about 34.8 GB): `a1_h264.mov`, `a2_h264.mov` (10
min at 30000/1001, `h264_videotoolbox -profile:v high -b:v 100M -g 15`,
timescale 30000, as the GH5 writes); `a3_hevc.mov`, `a4_hevc.mov` (10 min,
`hevc_videotoolbox -profile:v main10 -pix_fmt p010le -tag:v hvc1 -b:v 50M -g
30`); `p1_prores.mov`, `p2_prores.mov` (1 min, `prores_ks -profile:v 3
-pix_fmt yuv422p10le`, ProRes 422 HQ, projected at 710 Mb/s);
`h1_hevc5994.mov`, `h2_hevc5994.mov` (2 min at 60000/1001, HEVC Main 10 at
50M, `-g 60`, timescale 60000); `mic1.wav`, `mic2.wav` (10 min of mono 48 kHz
`pcm_s24le` pink noise, `anoisesrc=color=pink:amplitude=0.03`).

The long file (`long/long_hevc.mov`, `--long`): 3 h of HEVC Main 10 at 29.97
from 180 repeats of one minute, its rate the first of 50, 40, 30 and 20 Mb/s
whose projection leaves at least 20 GiB free.

**The disk rule (SW-5).** Before each output the size is projected as bitrate
× duration plus the one-minute segment; if `shutil.disk_usage`'s free space
minus that is under 20 GiB, nothing more is written and the script prints
`STOP: <file> needs <x> GiB, <y> GiB free, floor 20 GiB` and exits 3. A file
already present with a `.done` stamp beside it is kept, not made again.
"""

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "tools/proof/media/creator"
F4K = OUT / "f4k"
LONG = OUT / "long"
SEG = OUT / "segments"
GIB = 1024 ** 3
FLOOR_GIB = 20
SOURCE = "testsrc2=size=3840x2160:rate={rate}:duration=60,noise=alls=16:allf=t,hue=h={hue}"
NTSC = "30000/1001"
NTSC60 = "60000/1001"
LONG_RATES = [50, 40, 30, 20]  # Mb/s, the first that fits
LONG_MINUTES = 180

H264 = ["-c:v", "h264_videotoolbox", "-profile:v", "high", "-b:v", "100M", "-g", "15"]


def hevc(mbps, gop):
    return ["-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-pix_fmt", "p010le",
            "-tag:v", "hvc1", "-b:v", f"{mbps}M", "-g", str(gop)]


PRORES = ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"]

# name → (folder, rate, hue, minutes, encoder args, projected Mb/s, timescale, copy tag)
VIDEOS = {
    "a1_h264.mov": (F4K, NTSC, 0, 10, H264, 100, 30000, []),
    "a2_h264.mov": (F4K, NTSC, 90, 10, H264, 100, 30000, []),
    "a3_hevc.mov": (F4K, NTSC, 180, 10, hevc(50, 30), 50, 30000, ["-tag:v", "hvc1"]),
    "a4_hevc.mov": (F4K, NTSC, 270, 10, hevc(50, 30), 50, 30000, ["-tag:v", "hvc1"]),
    "p1_prores.mov": (F4K, NTSC, 45, 1, PRORES, 710, 30000, []),
    "p2_prores.mov": (F4K, NTSC, 135, 1, PRORES, 710, 30000, []),
    "h1_hevc5994.mov": (F4K, NTSC60, 225, 2, hevc(50, 60), 50, 60000, ["-tag:v", "hvc1"]),
    "h2_hevc5994.mov": (F4K, NTSC60, 315, 2, hevc(50, 60), 50, 60000, ["-tag:v", "hvc1"]),
}
MICS = {"mic1.wav": 1, "mic2.wav": 2}  # name → noise seed
MIC_BYTES = 600 * 48_000 * 3


class Stop(Exception):
    """The disk rule refused an output; the message is the STOP line."""


def free_gib():
    return shutil.disk_usage(OUT if OUT.exists() else ROOT).free / GIB


def guard(path, projected_bytes):
    """Refuses (`Stop`) when writing `projected_bytes` would leave < 20 GiB."""
    free = free_gib()
    need = projected_bytes / GIB
    if free - need < FLOOR_GIB:
        raise Stop(f"STOP: {path.relative_to(ROOT)} needs {need:.1f} GiB, {free:.1f} GiB free, "
                   f"floor {FLOOR_GIB} GiB")
    print(f"  {path.name}: projected {need:.1f} GiB, {free:.1f} GiB free", flush=True)


def stamp(path):
    return path.with_name(path.name + ".done")


def ready(path):
    return path.exists() and stamp(path).exists()


def run(args):
    command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", *args]
    print("  $ " + " ".join(command), flush=True)
    subprocess.run(command, check=True)


def segment(name, rate, hue, encoder, timescale):
    """One encoded minute, the unit every long file repeats."""
    SEG.mkdir(parents=True, exist_ok=True)
    out = SEG / name
    run(["-f", "lavfi", "-i", SOURCE.format(rate=rate, hue=hue), *encoder,
         "-video_track_timescale", str(timescale), "-an", str(out)])
    return out


def concat(seg, minutes, out, timescale, tag):
    listing = seg.with_suffix(".txt")
    listing.write_text("".join(f"file '{seg}'\n" for _ in range(minutes)))
    run(["-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy", *tag,
         "-video_track_timescale", str(timescale), str(out)])
    listing.unlink()


def make_video(out, rate, hue, minutes, encoder, mbps, timescale, tag):
    if ready(out):
        print(f"  {out.name}: kept", flush=True)
        return
    out.parent.mkdir(parents=True, exist_ok=True)
    minute = mbps * 1e6 / 8 * 60
    guard(out, minute * minutes + (minute if minutes > 1 else 0))
    if minutes == 1:
        run(["-f", "lavfi", "-i", SOURCE.format(rate=rate, hue=hue), *encoder,
             "-video_track_timescale", str(timescale), "-an", str(out)])
    else:
        seg = segment(out.name, rate, hue, encoder, timescale)
        try:
            concat(seg, minutes, out, timescale, tag)
        finally:
            seg.unlink(missing_ok=True)
    stamp(out).write_text(json.dumps(probe(out)))


def make_mic(out, seed):
    if ready(out):
        print(f"  {out.name}: kept", flush=True)
        return
    out.parent.mkdir(parents=True, exist_ok=True)
    guard(out, MIC_BYTES)
    run(["-f", "lavfi", "-i",
         f"anoisesrc=color=pink:amplitude=0.03:sample_rate=48000:duration=600:seed={seed}",
         "-ac", "1", "-c:a", "pcm_s24le", str(out)])
    stamp(out).write_text(json.dumps(probe(out)))


def probe(path):
    """ffprobe's format bit rate, duration, size and the first stream's codec."""
    run_ = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries",
         "format=bit_rate,duration,size:stream=codec_name,profile,pix_fmt,r_frame_rate",
         "-of", "json", str(path)], capture_output=True, text=True)
    try:
        data = json.loads(run_.stdout)
    except ValueError:
        return {"path": str(path), "error": run_.stderr[-300:]}
    fmt = data.get("format", {})
    stream = (data.get("streams") or [{}])[0]
    return {"path": str(path.relative_to(ROOT)), "bit_rate": int(fmt.get("bit_rate", 0) or 0),
            "duration": float(fmt.get("duration", 0) or 0), "size": int(fmt.get("size", 0) or 0),
            "codec": stream.get("codec_name"), "profile": stream.get("profile"),
            "pix_fmt": stream.get("pix_fmt"), "rate": stream.get("r_frame_rate")}


def f4k_paths():
    return {**{n: F4K / n for n in VIDEOS}, **{n: F4K / n for n in MICS}}


def build_4k():
    """Every F-4K file, each guarded; answers {name: probe}."""
    print(f"F-4K into {F4K.relative_to(ROOT)}", flush=True)
    for name, (folder, rate, hue, minutes, encoder, mbps, scale, tag) in VIDEOS.items():
        make_video(folder / name, rate, hue, minutes, encoder, mbps, scale, tag)
    for name, seed in MICS.items():
        make_mic(F4K / name, seed)
    return {name: json.loads(stamp(path).read_text()) for name, path in f4k_paths().items()}


def long_path():
    return LONG / "long_hevc.mov"


def build_long():
    """The three-hour file at the first rate that fits; answers its probe and rate."""
    out = long_path()
    if ready(out):
        print(f"  {out.name}: kept", flush=True)
        return json.loads(stamp(out).read_text())
    free = free_gib()
    chosen = None
    for mbps in LONG_RATES:
        minute = mbps * 1e6 / 8 * 60
        if free - (minute * (LONG_MINUTES + 1)) / GIB >= FLOOR_GIB:
            chosen = mbps
            break
        print(f"  {out.name} at {mbps} Mb/s needs {minute * (LONG_MINUTES + 1) / GIB:.1f} GiB, "
              f"{free:.1f} GiB free: does not fit", flush=True)
    if chosen is None:
        minute = LONG_RATES[-1] * 1e6 / 8 * 60
        LONG.mkdir(parents=True, exist_ok=True)
        guard(out, minute * (LONG_MINUTES + 1))  # raises the STOP with the 20 Mb/s figures
    LONG.mkdir(parents=True, exist_ok=True)
    make_video(out, NTSC, 0, LONG_MINUTES, hevc(chosen, 30), chosen, 30000, ["-tag:v", "hvc1"])
    record = json.loads(stamp(out).read_text())
    record["chosen_mbps"] = chosen
    record["free_gib_before"] = round(free, 1)
    stamp(out).write_text(json.dumps(record))
    return record


def remove_long():
    for path in (long_path(), stamp(long_path())):
        path.unlink(missing_ok=True)
    if LONG.exists() and not any(LONG.iterdir()):
        LONG.rmdir()


def clean():
    if OUT.exists():
        shutil.rmtree(OUT)


def listing():
    rows = {}
    for path in sorted(OUT.rglob("*")) if OUT.exists() else []:
        if path.is_file() and not path.name.endswith(".done"):
            rows[str(path.relative_to(ROOT))] = path.stat().st_size
    return rows


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--build-4k", action="store_true")
    parser.add_argument("--long", action="store_true")
    parser.add_argument("--remove-long", action="store_true")
    parser.add_argument("--clean", action="store_true")
    parser.add_argument("--list", action="store_true")
    args = parser.parse_args(argv)
    subprocess.run(["df", "-h", str(ROOT)])
    try:
        if args.clean:
            clean()
        if args.remove_long:
            remove_long()
        if args.long:
            print(json.dumps(build_long(), indent=1))
        if args.build_4k:
            print(json.dumps(build_4k(), indent=1))
    except Stop as stop:
        print(stop, flush=True)
        return 3
    if args.list:
        for path, size in listing().items():
            print(f"{size:>14,}  {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
