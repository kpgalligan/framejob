#!/usr/bin/env python3
"""Road map "creator-jobs" CO0 — the cutout spikes CO-S1 and CO-S2.

    python3 tools/proof/cutout_spike/cutout_spike.py [--only s1,s2,device] [--pack]
                                                      [--device cpu|gpu|neural_engine]
                                                      [--build-only] [--selftest]

CO-S1 (speed only: S-KEY1 is missing) — `mask_speed`, built from its own file
alone: every candidate (person `.balanced`, person `.accurate`, the person
instance mask scaled) × every rate (every frame, 15 and 10 a second) on
`push_1080.mov` at the source size and on `push_4k.mov` at the source size
and a long side of 1920, three runs each, the median kept; the first request
of a fresh process per candidate; then `deciders.s1_speed_only`. S-KEY1's and
S-TH1's rows are skipped by name and owed (J, B, flicker, Best, the read
size, the rotation).

CO-S2 — `mask_track_probe`, built from `app/Sources` with
`mask_track_writer.swift`: the bar-code fixtures, then per encoding (HEVC
8-bit full range, ProRes 422 Proxy) and chunk length (5, 10, 30 s) the
rows (1) registration (eleven cases at every frame and 15 a second, scored
here against `deciders.expected_mask`), (3) and (4) over CO-S1's dumped masks
of `push_1080`, (5) playback, (6) build; per encoding (2) colour and the
fixed cost of one chunk; then `deciders.s2_track`. `--pack` (and
automatically when the track answers `none`) measures the per-media mask pack
on (1), (2), (5), (6) after a free-space check, then `deciders.s2_pack`.
CO-S3 is not run (S-KEY1 missing).

`--only device` (road map CO1's head) — CJ-S2's rule 1 read for the mask
request: `mask_speed devices` on every frame of `push_1080.mov`, person
`.balanced`, a fresh request per frame, three runs pinned to each of the CPU,
the GPU and the Neural Engine, each run's SHA-256 over its masks' bytes and
its realtime factor; then `deciders.device_rule`. R0 checks CJ-S2's hash;
results in `tools/proof/work/creator_spike/CJ-S2-masks/`. `--only s1 --device
D` re-measures Standard alone (person `.balanced` at every, 15 and 10 a second
on both push-ins) pinned to D, results in `CO-S1-D/`.

`fixtures()` also makes M5's 640 × 360 lossless push-in and its three
rotation twins (`co1_proof.py`'s M5): `push_640.mov`, `push_640_cw.mov` (its
`transpose=1`, tagged to display as it does), `push_640_t.mov` (the same
frames untagged, 360 × 640) and `push_640_r.mov` (`push_640.mov` tagged to
display as `push_640_t.mov`); each pair is checked to decode, rotated by
ffmpeg, to the same first frame.

R0: each spike's rule hash is checked first (`rule.check_rule`); a mismatch
prints `RULE CHANGED <id>` and writes nothing. Results:
`tools/proof/work/creator_spike/CO-S1/results.json` and `CO-S2/`. Fixtures:
`tools/proof/media/cutout/` (reused while they probe as made; each source
image's SHA-256 in `fixtures.json`). Builds: `tools/proof/work/cutout_spike/bin/`.

Exit 0: every requested row answered or skipped by name; 1: an instrument
failure, a selftest row, or a changed rule; 2: not performed (the core's
staticlib or the codecs' stamp missing).
"""

import argparse
import hashlib
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
sys.path.insert(0, str(PROOF / "creator_spike"))
sys.path.insert(0, str(HERE))
import deciders  # noqa: E402
import lane_spike  # noqa: E402
import rule  # noqa: E402
import swift_build  # noqa: E402

FFMPEG = "/opt/homebrew/bin/ffmpeg"
FFPROBE = "/opt/homebrew/bin/ffprobe"
MEDIA = ROOT / "tools/proof/media/cutout"
WORK = ROOT / "tools/proof/work/cutout_spike"
BIN = WORK / "bin"
SPIKES = ROOT / "tools/proof/work/creator_spike"
LIBRARY = ROOT / "core/target/release/libframejob_core.a"
CODEC_STAMP = ROOT / "build/codecs/stamp.json"
MUSE = Path("/Library/Application Support/Adobe/CEP/extensions/com.adobe.ccx.fnft-3.5.0/"
            "images/empty-state/video-hero-MUSE.jpg")
FLEX = Path("/System/Library/Photos/Resources/FlexAudio/AAE4E824-DD67-4DB0-933F-AD2D619E4EF6.jpg")
CANDIDATES = ("person-balanced", "person-accurate", "instance-scaled")
RUNS = 3
HLG_TAGS = ("bt2020", "arib-std-b67", "bt2020nc")
VFR_DROPPED = (119, 270, 899)
EXTRA_FREE = 10 * 10**9


class Failure(Exception):
    """An instrument failure: scored, exit 1."""


def log(message):
    print(message, flush=True)


def load():
    return subprocess.run(["sysctl", "-n", "vm.loadavg"], capture_output=True,
                          text=True).stdout.strip()


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for block in iter(lambda: handle.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


# MARK: - Builds

def build_mask_speed():
    folder = BIN / "mask_speed"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    shutil.copyfile(HERE / "mask_speed.swift", entry)
    binary = folder / "mask_speed"
    swift_build.build(sources=[entry], output=binary, optimize=True)
    return binary


def build_mask_track_probe():
    folder = BIN / "mask_track_probe"
    folder.mkdir(parents=True, exist_ok=True)
    lane_spike.resources(folder)
    entry = folder / "main.swift"
    shutil.copyfile(HERE / "mask_track_probe.swift", entry)
    binary = folder / "mask_track_probe"
    swift_build.build(sources=[*swift_build.app_sources(), HERE / "mask_track_writer.swift",
                               entry], output=binary, optimize=True)
    return binary


def builds():
    """Both probes; a probe that does not build is a scored failure."""
    out = {}
    for name, make in (("mask_speed", build_mask_speed),
                       ("mask_track_probe", build_mask_track_probe)):
        try:
            out[name] = make()
            log(f"built {name}: {out[name]}")
        except swift_build.SwiftBuildFailed as failed:
            detail = "\n".join(failed.diagnostics[:12]) if failed.diagnostics else str(failed)
            raise Failure(f"{name} did not build: {detail}") from failed
        except SystemExit as failed:  # lane_spike.resources' shader build
            raise Failure(f"{name}'s resources did not build: {failed}") from failed
    return out


# MARK: - Fixtures

def frame_count(path):
    run = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-count_packets",
                          "-show_entries", "stream=nb_read_packets,width,height,codec_name",
                          "-of", "json", str(path)], capture_output=True, text=True, timeout=600)
    if run.returncode != 0:
        return None
    stream = (json.loads(run.stdout).get("streams") or [{}])[0]
    return {"frames": int(stream.get("nb_read_packets", 0)), "width": stream.get("width"),
            "height": stream.get("height"), "codec": stream.get("codec_name")}


def ffmpeg(args, out, seconds=1800):
    temp = out.with_name(out.stem + ".partial" + out.suffix)
    run = subprocess.run([FFMPEG, "-y", "-hide_banner", "-loglevel", "error", *args, str(temp)],
                         capture_output=True, text=True, timeout=seconds)
    if run.returncode != 0 or not temp.exists():
        raise Failure(f"ffmpeg failed making {out.name}: {run.stderr[-600:]}")
    os.replace(temp, out)


def fixtures(record):
    """The push-ins and the screen recording (CO-S1, CO-S2 (5)), and M5's
    640 × 360 push-in and its rotation twins; a missing source image is a
    scored failure naming its path."""
    MEDIA.mkdir(parents=True, exist_ok=True)
    # FlexAudio's cover first: person `.balanced` finds no person in MUSE's
    # back view (a 1080p still of it: mask maximum 45 levels, no pixel above
    # 127; the cover: 246, 4.3 % above 127), and (3) needs a person's edge.
    image = FLEX if FLEX.exists() else MUSE
    if not image.exists():
        raise Failure(f"no source image: neither {FLEX} nor {MUSE} exists")
    record["source_image"] = {"path": str(image), "sha256": sha256(image),
                              "why": "MUSE's person is not found by person .balanced"}
    frame = ("scale=1080:1080:flags=bicubic,pad=1920:1080:420:0:color=0x303030,"
             if image == FLEX else "")
    push = (frame + "scale=3840:2160,zoompan=z='1+0.25*on/600':x='iw/2-(iw/zoom/2)':"
            "y='ih/2-(ih/zoom/2)':d=1:s={size}:fps=30,noise=alls=6:allf=t,format=yuv420p")
    wanted = {
        "push_1080.mov": (["-loop", "1", "-framerate", "30", "-i", str(image), "-t", "20",
                           "-vf", push.format(size="1920x1080"),
                           "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", "-g", "60",
                           "-video_track_timescale", "600"], (600, 1920, 1080)),
        "push_4k.mov": (["-loop", "1", "-framerate", "30", "-i", str(image), "-t", "20",
                         "-vf", push.format(size="3840x2160"),
                         "-c:v", "hevc_videotoolbox", "-b:v", "40M", "-tag:v", "hvc1",
                         "-video_track_timescale", "600"], (600, 3840, 2160)),
        "screen_4k.mov": (["-f", "lavfi", "-i", "testsrc2=size=3840x2160:rate=30:duration=30",
                           "-vf", "format=yuv420p", "-c:v", "hevc_videotoolbox", "-b:v", "30M",
                           "-tag:v", "hvc1", "-color_primaries", "bt709", "-color_trc", "bt709",
                           "-colorspace", "bt709", "-video_track_timescale", "600"],
                          (900, 3840, 2160)),
    }
    made = {}
    previous = MEDIA / "fixtures.json"
    same_image = previous.exists() and json.loads(previous.read_text()).get(
        "source_image", {}).get("sha256") == record["source_image"]["sha256"]
    for name, (args, (frames, width, height)) in wanted.items():
        out = MEDIA / name
        probe = frame_count(out) if out.exists() else None
        remake = name.startswith("push") and not same_image
        if remake or not (probe and probe["frames"] == frames and probe["width"] == width):
            log(f"making {name}")
            ffmpeg(args, out)
            probe = frame_count(out)
        if not (probe and probe["frames"] == frames and probe["width"] == width
                and probe["height"] == height):
            raise Failure(f"{name} probes as {probe}, not {frames} frames at {width}×{height}")
        made[name] = probe
    made.update(rotation_fixtures())
    record["fixtures"] = made
    (MEDIA / "fixtures.json").write_text(json.dumps(record, indent=1, sort_keys=True))
    return made


def first_frame_md5(path):
    """The first frame's MD5 as ffmpeg decodes it, display rotation applied."""
    run = subprocess.run([FFMPEG, "-v", "error", "-i", str(path), "-frames:v", "1", "-f",
                          "framemd5", "-pix_fmt", "rgb24", "-"], capture_output=True, text=True,
                         timeout=120)
    lines = [line for line in run.stdout.splitlines() if line and not line.startswith("#")]
    return lines[0].split(",")[-1].strip() if lines else None


def rotation_fixtures():
    """M5's four: a 3 s 640 × 360 push-in in MOV (`push_1080.mov`'s first 3 s),
    uncompressed BGRA (`rawvideo` bgra: AVFoundation on macOS 26.5.1 refuses
    PNG in MOV, -11833, and decodes rgb24 twins up to 0.65 levels apart), its
    `transpose=1` tagged `-display_rotation 90` to display alike
    (`push_640_cw`), the transposed frames untagged (`push_640_t`, 360 × 640)
    and the original tagged `-display_rotation -90` to display as that
    (`push_640_r`). Each pair must decode, rotated, to the same first frame."""
    base, cw = MEDIA / "push_640.mov", MEDIA / "push_640_cw.mov"
    upright, tagged = MEDIA / "push_640_t.mov", MEDIA / "push_640_r.mov"
    probe = frame_count(base) if base.exists() else None
    if not (probe and probe["frames"] == 90 and probe["width"] == 640
            and probe["codec"] == "rawvideo"):
        ffmpeg(["-i", str(MEDIA / "push_1080.mov"), "-t", "3", "-vf", "scale=640:360",
                "-c:v", "rawvideo", "-pix_fmt", "bgra", "-video_track_timescale", "600"], base)
    if not upright.exists() or upright.stat().st_mtime < base.stat().st_mtime:
        ffmpeg(["-i", str(base), "-vf", "transpose=1", "-c:v", "rawvideo", "-pix_fmt", "bgra",
                "-video_track_timescale", "600"], upright)
    for source, out, angle in ((upright, cw, "90"), (base, tagged, "-90")):
        if not out.exists() or out.stat().st_mtime < source.stat().st_mtime:
            ffmpeg(["-display_rotation", angle, "-i", str(source), "-c", "copy"], out)
    for a, b in ((base, cw), (upright, tagged)):
        if first_frame_md5(a) is None or first_frame_md5(a) != first_frame_md5(b):
            raise Failure(f"{b.name} does not display as {a.name}: first frames "
                          f"{first_frame_md5(a)} and {first_frame_md5(b)}")
    return {p.name: frame_count(p) for p in (base, cw, upright, tagged)}


def barcode_fixtures(probe):
    """barcode.mov, barcode_rev.mov, long_60m.mov (the probe's writer) and
    hlg_vfr.mov (`ffmpeg`: barcode's first 40 s, frames 119, 270 and 899
    dropped, HEVC Main 10 tagged HLG)."""
    wanted = {"barcode": 4800, "barcode_rev": 4800, "long_60m": 108_000}
    for name, frames in wanted.items():
        out = MEDIA / f"{name}.mov"
        got = frame_count(out) if out.exists() else None
        if not (got and got["frames"] == frames):
            log(f"writing {name}.mov ({frames} frames)")
            run_probe(probe, ["fixtures", str(MEDIA), name], timeout=3600)
            got = frame_count(out)
            if not (got and got["frames"] == frames):
                raise Failure(f"{name}.mov probes as {got}, not {frames} frames")
    hlg = MEDIA / "hlg_vfr.mov"
    got = frame_count(hlg) if hlg.exists() else None
    if not (got and got["frames"] == 1200 - len(VFR_DROPPED)):
        primaries, transfer, matrix = HLG_TAGS
        params = f"color_primaries={primaries}:color_trc={transfer}:colorspace={matrix}"
        keep = "*".join(f"not(eq(n\\,{n}))" for n in VFR_DROPPED)
        ffmpeg(["-i", str(MEDIA / "barcode.mov"), "-t", "40", "-vf",
                f"select='{keep}',format=yuv420p10le,setparams={params}", "-fps_mode",
                "passthrough", "-c:v", "hevc_videotoolbox", "-profile:v", "main10",
                "-pix_fmt", "p010le", "-tag:v", "hvc1", "-b:v", "20M", "-color_primaries",
                primaries, "-color_trc", transfer, "-colorspace", matrix,
                "-video_track_timescale", "600"], hlg)
        got = frame_count(hlg)
        if not (got and got["frames"] == 1200 - len(VFR_DROPPED)):
            raise Failure(f"hlg_vfr.mov probes as {got}")
    times = pts_frames(hlg)
    expected = [f for f in range(1200) if f not in VFR_DROPPED]
    if times != expected:
        raise Failure(f"hlg_vfr.mov's frames are not barcode's less {VFR_DROPPED}: "
                      f"{len(times)} frames, first differences "
                      f"{[t for t in times if t not in expected][:5]}")


def pts_frames(path):
    """A movie's frame times in 1/30 s (integers), from ffprobe."""
    run = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "packet=pts_time", "-of", "json", str(path)], capture_output=True,
                         text=True, timeout=600)
    packets = json.loads(run.stdout).get("packets") or []
    return sorted(round(float(p["pts_time"]) * 30) for p in packets if "pts_time" in p)


# MARK: - Running probes

def run_probe(binary, args, timeout=1800):
    """A probe's `ANSWER` (or `mask_speed`'s last JSON line); a crash or a
    missing answer is an instrument failure."""
    started = time.monotonic()
    run = subprocess.run([str(binary), *args], capture_output=True, text=True, timeout=timeout,
                         cwd=str(Path(binary).parent))
    lines = [line for line in run.stdout.splitlines() if line.strip()]
    if run.returncode != 0 or not lines:
        raise Failure(f"{Path(binary).name} {' '.join(args[:3])} exited {run.returncode}: "
                      f"{(run.stderr or run.stdout)[-800:]}")
    last = lines[-1]
    if last.startswith("ANSWER "):
        last = last[len("ANSWER "):]
    try:
        answer = json.loads(last)
    except json.JSONDecodeError as error:
        raise Failure(f"{Path(binary).name}: no answer ({error}): {last[-300:]}") from error
    answer["_seconds"] = round(time.monotonic() - started, 2)
    return answer


# MARK: - CO-S1

def s1(binaries, results, device=None):
    """CO-S1; with `device` (road map CO1's re-measure) Standard alone,
    pinned to it, and no first-request row."""
    speed = binaries["mask_speed"]
    rows, firsts = {}, {}
    candidates = (deciders.STANDARD,) if device else CANDIDATES
    pinned = [device] if device else []
    for movie, sizes in (("push_1080", ("source",)), ("push_4k", ("source", "1920"))):
        for size in sizes:
            for candidate in candidates:
                for rate in deciders.RATES:
                    runs = []
                    for _ in range(RUNS):
                        answer = run_probe(speed, ["job", str(MEDIA / f"{movie}.mov"),
                                                   candidate, rate, size, *pinned],
                                           timeout=3600)
                        answer["load"] = load()
                        runs.append(answer)
                    key = f"{candidate}/{rate}/{movie}/{size}"
                    factors = [r["realtime"] for r in runs]
                    rows[key] = {"realtime": statistics.median(factors), "realtime_runs": factors,
                                 "requests": runs[0]["requests"], "frames": runs[0]["frames"],
                                 "mask": f"{runs[0]['mask_w']}x{runs[0]['mask_h']}",
                                 "read": f"{runs[0]['read_w']}x{runs[0]['read_h']}",
                                 "revision": runs[0]["revision"], "device": runs[0]["device"],
                                 "loads": [r["load"] for r in runs]}
                    log(f"CO-S1 {key}: {rows[key]['realtime']:.3f}× "
                        f"({', '.join(f'{f:.3f}' for f in factors)}) mask {rows[key]['mask']} "
                        f"load {runs[-1]['load']}")
    for candidate in () if device else CANDIDATES:
        firsts[candidate] = run_probe(speed, ["first", str(MEDIA / "push_1080.mov"), candidate])
        log(f"CO-S1 first {candidate}: {firsts[candidate]['first_call_ms']:.1f} ms")
    verdict = deciders.s1_speed_only(rows)
    standard = f"{verdict['standard']}/{verdict['rate']}"
    k_source = rows.get(f"{standard}/push_4k/source", {}).get("realtime")
    k_1920 = rows.get(f"{standard}/push_4k/1920", {}).get("realtime")
    verdict.update({"realtime_4k_source": k_source, "realtime_4k_1920": k_1920,
                    "mask": rows[f"{standard}/push_1080/source"]["mask"],
                    "first_call_ms": (firsts.get(verdict["standard"]) or {}).get(
                        "first_call_ms"), "device": device or "neural_engine"})
    owed = ["S-KEY1 missing: J, B (gesture), flicker, Best (d), the read size (e) and the "
            "rotated composite (f) are owed, and CO-S3",
            "S-TH1 missing: its speed rows are owed"]
    for line in owed:
        log(f"SKIP {line}")
    line = (f"VERDICT standard={verdict['standard']} rate={verdict['rate']} "
            + (f"device={device} " if device else "")
            + f"realtime_1080={fmt(verdict['realtime_1080'])} "
            f"realtime_4k={fmt(k_source)}@source,{fmt(k_1920)}@1920 mask={verdict['mask']} "
            f"first_call_ms={fmt(verdict['first_call_ms'], 1)} read_size=owed best=owed "
            f"flicker=owed rotation=owed")
    results.update({"rows": rows, "first": firsts, "verdict": verdict, "verdict_line": line,
                    "owed": owed})
    return line


def fmt(value, places=2):
    return "none" if value is None else f"{value:.{places}f}"


# MARK: - CJ-S2 rule 1 for the mask request (road map CO1)

def device_spike(binaries, results):
    speed = binaries["mask_speed"]
    rows = {}
    movie = str(MEDIA / "push_1080.mov")
    for device in deciders.DEVICES:
        runs = []
        for n in range(RUNS):
            answer = run_probe(speed, ["devices", movie, device], timeout=7200)
            answer["load"] = load()
            runs.append(answer)
            log(f"CJ-S2 masks {device} run {n + 1}: {answer['realtime']:.3f}× sha256 "
                f"{answer['sha256'][:16]}… {answer['requests']} masks of "
                f"{answer['mask_w']}x{answer['mask_h']} on {answer['device']} "
                f"load {answer['load']}")
        rows[device] = {"sha256": [r["sha256"] for r in runs],
                        "realtime": [r["realtime"] for r in runs],
                        "requests": runs[0]["requests"], "frames": runs[0]["frames"],
                        "mask": f"{runs[0]['mask_w']}x{runs[0]['mask_h']}",
                        "revision": runs[0]["revision"], "named": runs[0]["device"],
                        "loads": [r["load"] for r in runs]}
    verdict = deciders.device_rule(rows)
    same = ",".join(f"{d}:{'yes' if verdict['identical'][d] else 'no'}" for d in deciders.DEVICES)
    speeds = ",".join(f"{d}:{fmt(verdict['realtime'][d])}" for d in deciders.DEVICES)
    line = (f"VERDICT device={verdict['device']} branch={verdict['branch']} identical={same} "
            f"realtime={speeds} compare={verdict['compare']}")
    results.update({"rows": rows, "verdict": verdict, "verdict_line": line})
    return line


# MARK: - CO-S2

def registration_score(path, frames_of):
    """(1): every frame's mask index against `deciders.expected_mask`; a row
    is a (case, rate), passing when it read every frame and every pair."""
    document = json.loads(Path(path).read_text())
    rows, passed, misses = [], 0, []
    cache = {}
    for row in document["rows"]:
        name = f"{row['case']}@{row['rate']}"
        if not row.get("ok"):
            rows.append({"row": name, "ok": False, "error": row.get("error")})
            misses.append(f"{name}: {row.get('error')}")
            continue
        source = row["source"]
        frames = frames_of[source]
        key = (source, row["rate"])
        if key not in cache:
            cache[key] = deciders.analysed_frames(frames, row["rate"])
        analysed = cache[key]
        reverse = None
        if row["reversed"]:
            # The pivot is the track's end (its last frame plus one), not the
            # frame count: the two differ on a source with dropped frames.
            track_end = max(frames) + 1
            end_of = deciders.ends(frames, track_end)
            reverse = (track_end, end_of)
        bad = []
        for ticks, track, picture, mask in row["records"]:
            want = deciders.expected_mask(picture, analysed, reverse)
            if mask != want:
                bad.append({"ticks": ticks, "track": track, "picture": picture, "mask": mask,
                            "want": want})
        complete = row["frames"] == row["expected_frames"] and len(row["records"]) >= row["frames"]
        ok = complete and not bad
        passed += ok
        rows.append({"row": name, "ok": ok, "frames": row["frames"],
                     "expected_frames": row["expected_frames"], "pairs": len(row["records"]),
                     "misses": len(bad), "first_misses": bad[:5], "class": row.get("class"),
                     "chunk_files": row.get("chunk_files")})
        if not ok:
            misses.append(f"{name}: {len(bad)} misses of {len(row['records'])}, frames "
                          f"{row['frames']}/{row['expected_frames']}; {bad[:2]}")
    return {"pass": passed, "rows": len(document["rows"]), "table": rows, "misses": misses}


def s1_results():
    path = SPIKES / "CO-S1/results.json"
    if not path.exists():
        raise Failure("CO-S2 needs CO-S1's results: run --only s1 first")
    return json.loads(path.read_text())


def s2(binaries, results, pack):
    probe = binaries["mask_track_probe"]
    speed = binaries["mask_speed"]
    s1_doc = s1_results()
    s1v = s1_doc["verdict"]
    rate = s1v["rate"]
    barcode_fixtures(probe)
    frames_of = {"barcode": list(range(4800)), "hlg_vfr": pts_frames(MEDIA / "hlg_vfr.mov")}
    WORK.mkdir(parents=True, exist_ok=True)
    rows = {"registration": {}, "colour": {}, "codec": {}, "playback": {}, "build": {},
            "fixed_s": {}, "loads": {}}
    detail = {"registration": {}, "fixed": {}, "colour": {}}
    # CO-S1's Standard masks of push_1080, dumped once at its rate.
    dump = WORK / f"dump-{rate}"
    if not (dump / "index.json").exists():
        run_probe(speed, ["dump", str(MEDIA / "push_1080.mov"), rate, str(dump)], timeout=3600)
    for encoding in deciders.ENCODINGS:
        answer = run_probe(probe, ["fixed", str(WORK / "fixed"), encoding])
        rows["fixed_s"][encoding] = statistics.median(answer["runs"])
        detail["fixed"][encoding] = answer
        log(f"CO-S2 fixed {encoding}: {rows['fixed_s'][encoding] * 1000:.1f} ms "
            f"(median of {len(answer['runs'])})")
        answer = run_probe(probe, ["colour", str(WORK), str(MEDIA), encoding])
        rows["colour"][encoding] = {k: answer.get(k) for k in ("plain_sdr", "converting_sdr",
                                                               "converting_hlg")}
        detail["colour"][encoding] = answer
        log(f"CO-S2 colour {encoding}: {rows['colour'][encoding]}")
        for length in deciders.LENGTHS:
            key = f"{encoding}/{length}"
            rows["loads"][key] = load()
            answer = run_probe(probe, ["registration", str(WORK), str(MEDIA), encoding,
                                       str(length)], timeout=3600)
            score = registration_score(answer["path"], frames_of)
            rows["registration"][key] = {"pass": score["pass"], "rows": score["rows"]}
            detail["registration"][key] = score
            log(f"CO-S2 (1) {key}: {score['pass']}/{score['rows']}"
                + ("" if not score["misses"] else f"; {score['misses'][:3]}"))
            answer = run_probe(probe, ["codec", str(WORK), str(dump),
                                       str(MEDIA / "push_1080.mov"), encoding, str(length)],
                               timeout=3600)
            rows["codec"][key] = {k: answer.get(k) for k in ("iou", "iou_min", "iou_pooled",
                                                             "edge_mad",
                                                             "mb_per_min", "bytes", "mask",
                                                             "settings")}
            log(f"CO-S2 (3)(4) {key}: iou {answer['iou']:.4f} (min {answer['iou_min']:.4f}) "
                f"edge {answer['edge_mad']:.2f} levels, {answer['mb_per_min']:.2f} MB/min")
            answer = run_probe(probe, ["playback", str(WORK), str(MEDIA), encoding, str(length),
                                       rate], timeout=1800)
            rows["playback"][key] = answer
            log(f"CO-S2 (5) {key}: with {answer['with']} without {answer['without']} → "
                f"{answer['ratio'] * 100:.2f} %")
            answer = run_probe(probe, ["build", str(WORK), str(MEDIA), encoding, str(length),
                                       rate], timeout=1800)
            rows["build"][key] = answer
            log(f"CO-S2 (6) {key}: +{answer['delta_ms']:.1f} ms (median of 10; with "
                f"{statistics.median(answer['with_ms']):.1f}, without "
                f"{statistics.median(answer['without_ms']):.1f})")
    verdict = deciders.s2_track(rows, s1v)
    results.update({"rows": rows, "detail": detail, "track": verdict, "s1": s1v})
    lines = []
    if verdict["route"] == "mask-track":
        lines.append(track_line(verdict))
    if pack or verdict["route"] == "none":
        pack_rows = s2_pack_rows(probe, frames_of, dump)
        rows["pack"] = pack_rows
        packed = deciders.s2_pack(rows)
        results["pack"] = packed
        if verdict["route"] == "none":
            route = packed["route"]
            reg = packed.get("registration") or {}
            lines.append(f"VERDICT route={route} encoding=none chunk_s=none class=none "
                         f"registration={reg.get('pass')}/{reg.get('rows')} "
                         f"colour_max={packed.get('colour_max')} iou=none edge_mad=none "
                         f"mb_per_min=none playback={pct(packed.get('playback_ratio'))} "
                         f"build_ms=+{fmt(packed.get('build_delta_ms'), 1)} fixed_pct=none")
        else:
            log(f"pack (measured with --pack, not chosen): {packed}")
    results["verdict_lines"] = lines
    return lines


def pct(ratio):
    return "none" if ratio is None else f"{ratio * 100:.2f}"


def track_line(v):
    reg = v["registration"]
    return (f"VERDICT route=mask-track encoding={v['encoding']} chunk_s={v['chunk_s']} "
            f"class={v['class']} registration={reg['pass']}/{reg['rows']} "
            f"colour_max={fmt(v['colour_max'])} iou={v['iou']:.4f} "
            f"edge_mad={fmt(v['edge_mad'])} mb_per_min={fmt(v['mb_per_min'])} "
            f"playback={pct(v['playback'])} build_ms=+{fmt(v['build_ms'], 1)} "
            f"fixed_pct={fmt(v['fixed_pct'])}")


def s2_pack_rows(probe, frames_of, dump):
    """The per-media pack on (1), (2), (5), (6), after the free-space check."""
    estimate = 0
    for name, masks in (("barcode-every", 4800), ("barcode-15", 2400), ("hlg_vfr-every", 1197),
                        ("hlg_vfr-15", 600)):
        estimate += masks * 512 * 288  # an upper bound: every mask stored raw
    estimate += 108_000 * 12 + 108_000 * 20  # long_60m's tables
    free = shutil.disk_usage(ROOT).free
    if free < estimate + EXTRA_FREE:
        raise Failure(f"the pack needs {estimate + EXTRA_FREE} bytes free (its estimate "
                      f"{estimate} + 10 GB); {free} are: short by "
                      f"{estimate + EXTRA_FREE - free}")
    out = {"estimate_bytes": estimate, "free_bytes": free}
    answer = run_probe(probe, ["pack", str(WORK), str(MEDIA), "registration"], timeout=3600)
    score = registration_score(answer["path"], frames_of)
    out["registration"] = {"pass": score["pass"], "rows": score["rows"]}
    out["registration_detail"] = score
    log(f"CO-S2 pack (1): {score['pass']}/{score['rows']}"
        + ("" if not score["misses"] else f"; {score['misses'][:3]}"))
    answer = run_probe(probe, ["pack", str(WORK), str(MEDIA), "colour"])
    out["colour_max"] = answer["colour_max"]
    log(f"CO-S2 pack (2): max {answer['colour_max']} levels over {answer['compared']} masks")
    answer = run_probe(probe, ["pack", str(WORK), str(MEDIA), "playback"], timeout=1800)
    out["playback_ratio"] = answer["ratio"]
    out["playback"] = answer
    log(f"CO-S2 pack (5): with {answer['with']} without {answer['without']}")
    answer = run_probe(probe, ["pack", str(WORK), str(MEDIA), "build"], timeout=1800)
    out["build_delta_ms"] = answer["delta_ms"]
    out["build"] = answer
    log(f"CO-S2 pack (6): +{answer['delta_ms']:.1f} ms")
    # No rule: the pack's size over CO-S1's Vision masks, beside (4)'s.
    answer = run_probe(probe, ["pack", str(WORK), str(MEDIA), "size", str(dump)], timeout=1800)
    out["size"] = answer
    log(f"CO-S2 pack size (no rule): {answer['bytes']} bytes for {answer['masks']} masks of "
        f"{answer['mask']}, {answer['mb_per_min']:.2f} MB/min")
    return out


# MARK: - Main

def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--only", default="s1,s2")
    parser.add_argument("--device", choices=deciders.DEVICES)
    parser.add_argument("--pack", action="store_true")
    parser.add_argument("--build-only", action="store_true")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return 1 if deciders.selftest() else 0
    if not LIBRARY.exists() or not CODEC_STAMP.exists():
        missing = [str(p) for p in (LIBRARY, CODEC_STAMP) if not p.exists()]
        print(f"NOT PERFORMED: {', '.join(missing)} missing (cargo build --release, make codecs)")
        return 2
    only = {part.strip() for part in args.only.split(",") if part.strip()}
    spikes = {"s1": "CO-S1", "s2": "CO-S2", "device": "CJ-S2"}
    if not args.build_only:
        for part in sorted(only):
            computed, table, match = rule.check_rule(spikes[part])
            if not match:
                print(f"RULE CHANGED {spikes[part]}")
                return 1
    host = rule.host()
    log(f"host: {host['os']} ({host['os_build']}), {host['device']}, AC power "
        f"{host['ac_power']}, load {load()}")
    try:
        binaries = builds()
    except Failure as failure:
        print(f"FAIL {failure}")
        return 1
    if args.build_only:
        return 0
    log("CO-S3 owed: S-KEY1 missing (CO4 shipped r0, spec §11 CO-40; runs when S-KEY1 exists)")
    lines, status = [], 0
    try:
        if "s1" in only:
            record = {}
            fixtures(record)
            results = {"fixtures": record, "load_start": load()}
            lines.append(s1(binaries, results, args.device))
            results["load_end"] = load()
            path = rule.write_results(
                "CO-S1", results, folder=f"CO-S1-{args.device}" if args.device else None)
            log(f"results: {path}")
        if "device" in only:
            record = {}
            fixtures(record)
            results = {"fixtures": record, "load_start": load(),
                       "ac_power": rule.host()["ac_power"]}
            lines.append(device_spike(binaries, results))
            results["load_end"] = load()
            path = rule.write_results("CJ-S2", results, folder="CJ-S2-masks")
            log(f"results: {path}")
        if "s2" in only:
            record = {}
            fixtures(record)
            results = {"fixtures": record, "load_start": load(),
                       "ac_power": rule.host()["ac_power"]}
            lines += s2(binaries, results, args.pack)
            results["load_end"] = load()
            path = rule.write_results("CO-S2", results)
            log(f"results: {path}")
    except Failure as failure:
        print(f"FAIL {failure}")
        status = 1
    for line in lines:
        print(line)
    return status


if __name__ == "__main__":
    sys.exit(main())
