#!/usr/bin/env python3
"""Issue #298 phase 1 — where every export path places a sample relative to
the timeline, measured against sample-exact click fixtures, and the stage
(file, AVFoundation decode/SRC, composition insert, mix, time-pitch, writer)
where each offset enters. No product code and no decision: phase 2's fix is
specified from what this prints.

    python3 tools/proof/export_offset_proof.py [<dir>/agent.sock] [--only ID,ID,...]

Z0, Z2 and L1–L9 need no app; every other row needs the running instance's
socket (`proof_app.py launch`; `--app release` for the recorded run) and the
script exits 2 when one is asked for without it. Rows print
`<ID> ok|FAIL — <detail>`, then the E and L tables, then `scores: n/m`; exit
0 iff every requested row passed. Everything is under
`tools/proof/work/export-offset/` (fixtures in `fixtures/`, names carrying
`-v1`, made once). Every project is closed with `discard: true`; no menu item
is performed. ffmpeg and ffprobe are proof-time dependencies (as
`audio_sync_proof.py`'s S18); a WAV is read by Python's `wave` alone, the
ground truth for every WAV export.

Fixtures, 10 s each, a click at every frame F of CLICK_FRAMES (15, 39, …, 279
at 30 fps — multiples of 3, so each frame start is a whole sample at 16 and
48 kHz): a Hann pulse 1 ms wide, amplitude 0.5, centred on F/30 s,
v(n) = 0.25·(1 + cos(π(n − c)/h)) for |n − c| < h, h = rate/2000 samples.
  clicks16 / clicks48     mono s16 WAV at 16 / 48 kHz (`write_clicks_wav`)
  clicks48-lead37         clicks48 with every click 37 samples later (Z1)
  cam-pcm48 / cam-aac48   `export_offset_writer.swift`: AVFoundation's H.264
                          movie, white on the click frames, 48 kHz mono LPCM
                          s16 / AAC 128 kbps
  cam-ff16                `audio_sync_proof.py`'s CAMERA recipe over clicks16
                          (lavfi gray, libx264 30 fps, pcm_s16le, -shortest)

`locate` finds each click near its expected time: the sample of largest |x|
within ±60 ms, then the normalised correlation with the click template at
the read's rate over ±1 ms of it, refined parabolically; a click whose best
r is under 0.5 is not found. Expected timeline time of a click at source
time c: `start + (c − in)/speed` from `get_project`'s clip; in an `in_out`
export, minus the in point.

Rows:
  Z0  each fixture read back (`read_wav` / `read_ffmpeg`) finds all 12
      clicks within 0.05 ms of the written times (0.5 ms for cam-aac48); the
      writer's movies flash on exactly CLICK_FRAMES (pts F/30 ± 1 ms);
      cam-ff16 is flat grey and checked for sound only
  Z1  E4's project with clicks48-lead37: its median − E4's = 37/48 000 s
      ± 0.05 ms
  Z2  `locate` on synthetic 48 kHz trains with clicks at +0.0, +0.3, +0.7
      sample finds each within 0.01 ms (no file)
  Z3  E2's WAV by `locate` and by S18's method (`wav_samples`, `envelope`,
      `window_lag` against the fixture's envelope placed at the clip's start,
      over the file's click span); `window_lag` takes a whole-ms offset, so
      the start is rounded and the rounding taken back out of the lag
  R1  `audio_sync_proof.fixtures()`'s RECORDER at frame 206, ×1, `audio_wav`,
      S18's `window_lag` on [12 s, 22 s) (#298 reported +25.71 ms)
  R2  the same at `set_speed {rate: 0.99999, keep_pitch: false}` (#298:
      −2.81 ms)
  E1–E23  one project each (`E_ROWS`), exported and located; ok when the
      export completed and ≥ 10 of 12 clicks were found (E23: all 10 of its
      in-range clicks); the detail prints the median and spread of
      found − expected, the count, the least r and `target met|missed`
      against phase 2's target (not scored here)
  L1–L9  `export_offset_probe.swift`'s stage reads (its header lists them),
      each located; ok when every read completed and found ≥ 10 of 12. A
      probe that does not build or answer FAILS all nine
Under the L table, per fixture and speed, the first stage of
asset48 → comp → mix → export whose median moves by more than 0.1 ms from
the stage before it, and native against asset48 (the decoder's SRC).
"""

import argparse
import array
import json
import math
import os
import re
import shutil
import statistics
import sys
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/proof"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402
from audio_sync_proof import envelope, fixtures as sync_fixtures, wav_samples, window_lag  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402

WORK = HERE / "work/export-offset"
FIXTURES = WORK / "fixtures"
EXPORTS = WORK / "exports"
PROBE_DIR = WORK / "probe"
PROBE_RUNS = WORK / "probe-runs"
PROBE_SWIFT = HERE / "export_offset_probe.swift"
WRITER_SWIFT = HERE / "export_offset_writer.swift"
WRITER = WORK / "writer" / "export_offset_writer"
BLANK = ROOT / "app/Resources/Blank.mp4"
BUILD_WALL = 900
RUN_WALL = 240

CLICK_FRAMES = [15 + 24 * k for k in range(12)]
CLICKS = [f / 30 for f in CLICK_FRAMES]  # source seconds
SEC = 600_000
F206 = 206 * 20_000
LENGTH_S = 10
LEAD = 37
TARGET_MS = 1.0
TARGET_SPREAD_MS = 0.5
KEEP_TARGET_MS = 5.0
NR_DELAY_MS = 512 / 48_000 * 1000
FLASH_SHARE = (320 * 180) / (640 * 360)  # the movie's share of the canvas

Z_ROWS = ["Z0", "Z1", "Z2", "Z3"]
R_ROWS = ["R1", "R2"]
L_ROWS = [f"L{n}" for n in range(1, 10)]

# row: (fixture, start ticks, edit, preset). An edit: None (×1),
# ("speed", rate, keep_pitch), ("loudness", lufs), ("pan", value), ("nr", value),
# ("range", start, end).
E_ROWS = {
    "E1": ("clicks16", 0, None, "audio_wav"),
    "E2": ("clicks16", F206, None, "audio_wav"),
    "E3": ("clicks16", 10 * SEC, None, "audio_wav"),
    "E4": ("clicks48", F206, None, "audio_wav"),
    "E5": ("clicks16", F206, ("speed", 0.99999, False), "audio_wav"),
    "E6": ("clicks48", F206, ("speed", 0.99999, False), "audio_wav"),
    "E7": ("clicks16", F206, ("speed", 0.5, False), "audio_wav"),
    "E8": ("clicks48", F206, ("speed", 0.5, False), "audio_wav"),
    "E9": ("clicks48", F206, ("speed", 0.5, True), "audio_wav"),
    "E10": ("clicks16", F206, ("speed", 0.99999, True), "audio_wav"),
    "E11": ("clicks48", F206, ("speed", 2, True), "audio_wav"),
    "E12": ("clicks16", F206, ("speed", 0.5, True), "audio_wav"),
    "E13": ("cam-pcm48", 10 * SEC, None, "audio_wav"),
    "E14": ("cam-aac48", 10 * SEC, None, "audio_wav"),
    "E15": ("cam-ff16", 10 * SEC, None, "audio_wav"),
    "E16": ("cam-pcm48", 10 * SEC, None, "prores_422"),
    "E17": ("cam-aac48", 10 * SEC, None, "prores_422"),
    "E18": ("cam-pcm48", 10 * SEC, None, "h264"),
    "E19": ("cam-aac48", 10 * SEC, None, "h264"),
    "E20": ("clicks48", F206, ("loudness", -16), "audio_wav"),
    "E21": ("clicks48", F206, ("pan", -0.5), "audio_wav"),
    "E22": ("clicks48", F206, ("nr", 0.5), "audio_wav"),
    "E23": ("clicks48", F206, ("range", 5 * SEC, 15 * SEC), "audio_wav"),
}
E_IDS = list(E_ROWS)
KEEP_ROWS = {"E9", "E10", "E11", "E12"}
VIDEO_ROWS = {"E16", "E17", "E18", "E19"}
EXTENSIONS = {"audio_wav": "wav", "prores_422": "mov", "h264": "mp4"}
ALL_ROWS = Z_ROWS + R_ROWS + E_IDS + L_ROWS
NO_APP = {"Z0", "Z2"} | set(L_ROWS)

results = {}
e_table = []
l_table = []


def score(row, ok, detail):
    results[row] = (bool(ok), detail)
    print(f"{row} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


class FixtureError(RuntimeError):
    pass


# ---- children under Rule H -----------------------------------------------------


def run(argv, seconds=RUN_WALL):
    """`bounded.run`, raising on expiry or a non-zero exit."""
    ran = bounded.run([str(a) for a in argv], seconds)
    if ran["expired"]:
        raise FixtureError(f"{Path(str(argv[0])).name} ran past {seconds} s and was killed")
    if ran["rc"] != 0:
        raise FixtureError(f"{Path(str(argv[0])).name} exited {ran['rc']}: "
                           f"{(ran['stderr'] or ran['stdout']).strip()[-300:]}")
    return ran


# ---- fixtures ------------------------------------------------------------------


def click_value(d, h):
    return 0.25 * (1 + math.cos(math.pi * d / h)) if abs(d) < h else 0.0


def write_clicks_wav(path: Path, rate: int, lead: int = 0) -> None:
    """Mono s16 via `wave`: 10 s, a click centred at rate·F/30 + lead samples."""
    total = rate * LENGTH_S
    data = [0.0] * total
    h = rate / 2000
    reach = math.ceil(h)
    for f in CLICK_FRAMES:
        c = rate * f // 30 + lead
        for n in range(max(0, c - reach), min(total, c + reach + 1)):
            data[n] += click_value(n - c, h)
    pcm = array.array("h", (max(-32767, min(32767, int(round(v * 32767)))) for v in data))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def fixture_path(name):
    ext = "wav" if name.startswith("clicks") else "mov"
    return FIXTURES / f"{name}-v1.{ext}"


def build_writer():
    try:
        swift_build.build(sources=[WRITER_SWIFT], output=WRITER, timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        raise FixtureError("export_offset_writer did not build: "
                           + "; ".join(error.diagnostics[:4]))
    return WRITER


def make_fixtures():
    """{name: path}, each made once (a failed make leaves no file)."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    made = {}
    for name, rate, lead in [("clicks16", 16_000, 0), ("clicks48", 48_000, 0),
                             ("clicks48-lead37", 48_000, LEAD)]:
        path = fixture_path(name)
        if not path.exists():
            write_clicks_wav(path, rate, lead)
        made[name] = path
    frames = ",".join(str(f) for f in CLICK_FRAMES)
    for name, kind in [("cam-pcm48", "pcm"), ("cam-aac48", "aac")]:
        path = fixture_path(name)
        if not path.exists():
            writer = build_writer()
            try:
                run([writer, path, kind, frames])
            except FixtureError:
                path.unlink(missing_ok=True)
                raise
        made[name] = path
    path = fixture_path("cam-ff16")
    if not path.exists():
        try:
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                 f"color=c=gray:s=320x180:r=30:d={LENGTH_S}", "-i", made["clicks16"],
                 "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-shortest",
                 path])
        except FixtureError:
            path.unlink(missing_ok=True)
            raise
    made["cam-ff16"] = path
    return made


_fixtures = None


def fixtures():
    global _fixtures
    if _fixtures is None:
        _fixtures = make_fixtures()
    return _fixtures


# ---- readers -------------------------------------------------------------------


def read_wav(path: Path) -> tuple[list[float], int]:
    """Python `wave` only (no ffmpeg): integer PCM, channels averaged."""
    with wave.open(str(path), "rb") as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 2:
        values = array.array("h", raw)
        scale = 32768
    elif width == 4:
        values = array.array("i", raw)
        scale = 2 ** 31
    elif width == 3:
        values = [int.from_bytes(raw[i:i + 3], "little", signed=True)
                  for i in range(0, len(raw) - 2, 3)]
        scale = 2 ** 23
    else:
        raise ValueError(f"{path.name}: {width}-byte samples")
    if channels == 1:
        return [v / scale for v in values], rate
    out = []
    for i in range(0, len(values) - channels + 1, channels):
        out.append(sum(values[i:i + channels]) / (channels * scale))
    return out, rate


def stream_rate(path):
    ran = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
               "stream=sample_rate", "-of", "csv=p=0", path])
    return int(ran["stdout"].strip().split(",")[0])


def read_ffmpeg(path: Path) -> tuple[list[float], int]:
    """ffmpeg to mono float32 at the stream's own rate (edit lists honoured as
    ffmpeg does by default); for `.mov` / `.mp4` only."""
    rate = stream_rate(path)
    out = path.with_name(path.name + ".f32")
    run(["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:a:0", "-ac", "1", "-ar",
         str(rate), "-f", "f32le", "-acodec", "pcm_f32le", out])
    data = array.array("f", out.read_bytes())
    out.unlink(missing_ok=True)
    return list(data), rate


def read_f32(path: Path, rate: int) -> list[float]:
    """The probe's raw output: mono float32 LE."""
    return list(array.array("f", Path(path).read_bytes()))


def read_any(path: Path):
    path = Path(path)
    return read_wav(path) if path.suffix == ".wav" else read_ffmpeg(path)


# ---- locating ------------------------------------------------------------------


def template(rate):
    h = rate / 2000
    half = math.ceil(h)
    values = [click_value(k, h) for k in range(-half, half + 1)]
    return values, half, math.sqrt(sum(v * v for v in values))


def locate(samples, rate: int, expected: list[float],
           reach_ms: float = 60.0) -> list[tuple[float | None, float]]:
    """Per expected time (s): (found time s, or None when r < 0.5; r)."""
    values, half, norm = template(rate)
    reach = int(round(reach_ms * rate / 1000))
    fine = max(1, int(round(rate / 1000)))
    n = len(samples)
    out = []

    def r_at(c):
        a, b = c - half, c + half + 1
        if a < 0 or b > n:
            return 0.0
        seg = samples[a:b]
        energy = math.sqrt(sum(x * x for x in seg))
        return sum(x * y for x, y in zip(seg, values)) / (energy * norm) if energy > 0 else 0.0

    for t in expected:
        centre = int(round(t * rate))
        lo, hi = max(0, centre - reach), min(n, centre + reach + 1)
        if hi <= lo:
            out.append((None, 0.0))
            continue
        coarse = max(range(lo, hi), key=lambda i: abs(samples[i]))
        scores = {c: r_at(c) for c in range(coarse - fine, coarse + fine + 1)}
        best = max(scores, key=scores.get)
        r = scores[best]
        offset = 0.0
        if best - 1 in scores and best + 1 in scores:
            left, right = scores[best - 1], scores[best + 1]
            bend = left - 2 * r + right
            if bend < 0:
                offset = max(-0.5, min(0.5, 0.5 * (left - right) / bend))
        out.append(((best + offset) / rate if r >= 0.5 else None, r))
    return out


def summary(found, expected) -> dict:
    diffs = [(f - e) * 1000 for (f, _), e in zip(found, expected) if f is not None]
    rs = [r for _, r in found]
    return {
        "found": len(diffs), "of": len(expected),
        "median_ms": statistics.median(diffs) if diffs else None,
        "spread_ms": (max(diffs) - min(diffs)) if diffs else None,
        "min_r": min(rs) if rs else None,
        "diffs": diffs,
    }


def fmt(value, places=3):
    return "—" if value is None else f"{value:+.{places}f}"


def describe(s):
    return (f"{s['found']}/{s['of']} found, median {fmt(s['median_ms'])} ms, spread "
            f"{fmt(s['spread_ms'])} ms, min r {s['min_r']:.3f}" if s["min_r"] is not None
            else f"{s['found']}/{s['of']} found")


def flash_times(path: Path, threshold: float = 128) -> list[float]:
    """The times of video frames whose mean luma (16×9 gray) is over
    `threshold` (128 for a picture the flash fills)."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "frame=best_effort_timestamp_time", "-of", "csv=p=0", path])
    times = [float(line.strip().split(",")[0]) for line in ran["stdout"].splitlines()
             if line.strip()]
    out = Path(path).with_name(Path(path).name + ".gray")
    run(["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:v:0", "-fps_mode",
         "passthrough", "-vf", "scale=16:9,format=gray", "-f", "rawvideo", out])
    raw = out.read_bytes()
    out.unlink(missing_ok=True)
    means = [sum(raw[i:i + 144]) / 144 for i in range(0, len(raw) - 143, 144)]
    return [t for t, m in zip(times, means) if m > threshold]


# ---- the app's projects --------------------------------------------------------


class Session:
    def __init__(self, mcp, name):
        self.mcp = mcp
        for stale in WORK.iterdir():
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale.name):
                shutil.rmtree(stale)
        self.path = str(WORK / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360, fps=30)

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def media(self, path):
        """`import_media`, then its peaks waited for (60 s), as
        `audio_sync_proof.Session.media` does."""
        media = self.op("import_media", path=str(path))["media"]
        peaks = Path(self.path) / "cache" / "peaks" / f"{media}.bin"
        for _ in range(1200):
            if peaks.exists():
                return media
            time.sleep(0.05)
        raise RuntimeError(f"{peaks} was never written")

    def place(self, path, at):
        media = self.media(path)
        track = self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def close(self):
        try:
            self.op("close_project", discard=True)
        except ToolError:
            pass


def expected_times(clip, in_point=None):
    """Each click's expected time in the file, (source s, file s); clicks
    outside the clip's window, or outside [in, out) of an in/out export, are
    left out."""
    start = clip["start"] / SEC
    source_in = clip["source"].get("in", 0) / SEC
    speed = clip.get("speed", 1) or 1
    end = start + clip["duration"] / SEC
    out = []
    for c in CLICKS:
        t = start + (c - source_in) / speed
        if not (start <= t < end):
            continue
        if in_point is not None:
            lo, hi = in_point
            if not (lo <= t < hi):
                continue
            t -= lo
        out.append((c, t))
    return out


_e_cache = {}


def run_e(mcp, row, fixture_override=None):
    """One E row's export, measured: a dict (memoised per row and fixture)."""
    key = (row, fixture_override)
    if key in _e_cache:
        return _e_cache[key]
    fixture, at, edit, preset = E_ROWS[row]
    fixture = fixture_override or fixture
    tag = row if fixture_override is None else f"{row}-{fixture_override}"
    EXPORTS.mkdir(parents=True, exist_ok=True)
    out = EXPORTS / f"{tag}.{EXTENSIONS[preset]}"
    out.unlink(missing_ok=True)
    session = Session(mcp, f"offset-{tag.lower()}")
    result = {"row": row, "fixture": fixture, "preset": preset, "path": out}
    try:
        clip = session.place(fixtures()[fixture], at)
        export = {"preset": preset, "path": str(out)}
        in_point = None
        if edit and edit[0] == "speed":
            session.op("set_speed", clip=clip, rate=edit[1], keep_pitch=edit[2])
        elif edit and edit[0] == "loudness":
            export["loudness_lufs"] = edit[1]
        elif edit and edit[0] == "pan":
            session.op("set_audio", clips=[clip], patch={"pan": edit[1]})
        elif edit and edit[0] == "nr":
            session.op("set_audio", clips=[clip], patch={"noise_reduction": edit[1]})
        elif edit and edit[0] == "range":
            session.op("set_range", start=edit[1], end=edit[2])
            export["range"] = "in_out"
            in_point = (edit[1] / SEC, edit[2] / SEC)
        placed = session.clip(clip)
        result["clip"] = {k: placed.get(k) for k in ("start", "duration", "speed")}
        session.op("export", **export)
    finally:
        session.close()
    pairs = expected_times(placed, in_point)
    expected = [t for _, t in pairs]
    samples, rate = read_any(out)
    found = locate(samples, rate, expected)
    result.update(summary(found, expected))
    result["rate"] = rate
    result["expected"] = expected
    result["found_times"] = [f for f, _ in found]
    if preset in ("prores_422", "h264"):
        # The 320×180 movie sits unscaled on the 640×360 canvas, a quarter of
        # its area, so a white frame's mean over the whole picture is a
        # quarter of a full one's: the threshold is scaled by the same share.
        flashes = flash_times(out, 128 * FLASH_SHARE)
        result["flashes"] = flashes
        result["flash_frames"] = sorted(round(t * 30) for t in flashes)
        result["expected_frames"] = sorted(round(t * 30) for t in expected)
        av = []
        clicks = [f for f, _ in found if f is not None]
        for t in flashes:
            near = min(clicks, key=lambda c: abs(c - t), default=None)
            if near is not None and abs(near - t) < 0.1:
                av.append((near - t) * 1000)
        result["av_ms"] = av
    _e_cache[key] = result
    return result


def e_target(row, r):
    """'target met|missed' against phase 2's target (not scored here)."""
    if r["median_ms"] is None:
        return "target missed (nothing found)"
    if row == "E22":
        base = _e_cache.get(("E4", None))
        if base and base["median_ms"] is not None:
            delta = r["median_ms"] - base["median_ms"]
            return (f"E22 − E4 {delta:+.3f} ms against 512/48 000 s = {NR_DELAY_MS:.3f} ms "
                    f"(off by {delta - NR_DELAY_MS:+.3f} ms)")
        return "E4 not measured: no difference"
    if row in KEEP_ROWS:
        return "target " + ("met" if abs(r["median_ms"]) <= KEEP_TARGET_MS else "missed") \
            + f" (|median| ≤ {KEEP_TARGET_MS} ms)"
    if row in VIDEO_ROWS:
        av = r.get("av_ms") or []
        on_frame = r.get("flash_frames") == r.get("expected_frames")
        av_ok = bool(av) and max(abs(v) for v in av) <= TARGET_MS
        return "target " + ("met" if on_frame and av_ok else "missed") \
            + f" (flash on its timeline frame {on_frame}, |click − flash| ≤ {TARGET_MS} ms {av_ok})"
    met = abs(r["median_ms"]) <= TARGET_MS and r["spread_ms"] <= TARGET_SPREAD_MS
    return "target " + ("met" if met else "missed") \
        + f" (|median| ≤ {TARGET_MS} ms, spread ≤ {TARGET_SPREAD_MS} ms)"


def e_row(mcp, row):
    try:
        if row == "E22":
            run_e(mcp, "E4")  # its base, measured once
        r = run_e(mcp, row)
    except Exception as error:  # an instrument failure is this row's scored FAIL
        score(row, False, f"{type(error).__name__}: {error}")
        e_table.append((row, E_ROWS[row], None))
        return
    need = r["of"] if row == "E23" else 10
    ok = r["found"] >= need and (row != "E23" or r["of"] == 10)
    detail = f"{r['fixture']} {r['preset']} → {r['rate']} Hz; {describe(r)}; {e_target(row, r)}"
    if row in VIDEO_ROWS:
        av = r.get("av_ms") or []
        detail += (f"; flashes {len(r['flashes'])} on frames {r['flash_frames']} (timeline "
                   f"{r['expected_frames']}); A/V click − flash median "
                   f"{fmt(statistics.median(av) if av else None)} ms, range "
                   f"{fmt(min(av) if av else None)}…{fmt(max(av) if av else None)} ms")
    score(row, ok, detail)
    e_table.append((row, E_ROWS[row], r))


# ---- Z rows --------------------------------------------------------------------


def z0():
    files = fixtures()
    notes, ok = [], True
    for name in ["clicks16", "clicks48", "clicks48-lead37", "cam-pcm48", "cam-aac48",
                 "cam-ff16"]:
        samples, rate = read_any(files[name])
        lead = LEAD / 48_000 if name == "clicks48-lead37" else 0
        expected = [c + lead for c in CLICKS]
        s = summary(locate(samples, rate, expected), expected)
        tolerance = 0.5 if name == "cam-aac48" else 0.05
        worst = max((abs(d) for d in s["diffs"]), default=None)
        good = s["found"] == 12 and worst is not None and worst <= tolerance
        ok &= good
        notes.append(f"{name} {rate} Hz {s['found']}/12, worst |Δ| {fmt(worst, 4)} ms "
                     f"(≤ {tolerance}), median {fmt(s['median_ms'], 4)}")
        if name in ("cam-pcm48", "cam-aac48"):
            flashes = flash_times(files[name])
            frames = [round(t * 30) for t in flashes]
            off = max((abs(t - round(t * 30) / 30) * 1000 for t in flashes), default=None)
            good = frames == CLICK_FRAMES and off is not None and off <= 1.0
            ok &= good
            notes.append(f"{name} flashes on {frames == CLICK_FRAMES and 'CLICK_FRAMES' or frames}"
                         f" (pts off its frame ≤ {fmt(off, 4)} ms)")
    score("Z0", ok, "; ".join(notes))


def z2():
    rate = 48_000
    total = rate * LENGTH_S
    h = rate / 2000
    data = [0.0] * total
    centres = []
    for k, f in enumerate(CLICK_FRAMES):
        c = rate * f / 30 + [0.0, 0.3, 0.7][k % 3]
        centres.append(c / rate)
        for n in range(int(c - h) - 1, int(c + h) + 2):
            data[n] += click_value(n - c, h)
    found = locate(data, rate, centres)
    s = summary(found, centres)
    worst = max((abs(d) for d in s["diffs"]), default=None)
    score("Z2", s["found"] == 12 and worst is not None and worst <= 0.01,
          f"{s['found']}/12 found, worst |Δ| {fmt(worst, 5)} ms (want ≤ 0.01), min r "
          f"{s['min_r']:.4f}")


def z1(mcp):
    e4 = run_e(mcp, "E4")
    lead = run_e(mcp, "E4", "clicks48-lead37")
    want = LEAD / 48_000 * 1000
    if e4["median_ms"] is None or lead["median_ms"] is None:
        score("Z1", False, f"E4 {describe(e4)}; lead37 {describe(lead)}")
        return
    delta = lead["median_ms"] - e4["median_ms"]
    score("Z1", abs(delta - want) <= 0.05,
          f"lead37 median {fmt(lead['median_ms'])} − E4 {fmt(e4['median_ms'])} = "
          f"{delta:+.4f} ms (want {want:.4f} ± 0.05); lead37 {describe(lead)}")


def z3(mcp):
    e2 = run_e(mcp, "E2")
    start_ms = e2["clip"]["start"] / SEC * 1000
    offset = round(start_ms)
    mix = envelope(wav_samples(Path(e2["path"])))
    source = envelope(wav_samples(fixtures()["clicks16"]))
    lag, r = window_lag(mix, source, offset + 400, offset + 9400, offset_ms=offset)
    # `window_lag` measures against the source placed at the whole-ms `offset`;
    # the clip starts at `start_ms`, so its lag reads (start_ms − offset) ms
    # more than the clip's own delay. That rounding is taken back out.
    rounding = start_ms - offset
    corrected = lag - rounding
    located = e2["median_ms"]
    measured = located is not None and r > 0
    score("Z3", measured,
          f"locate median {fmt(located)} ms; S18 method lag {lag:+.3f} ms (r {r:.3f}) against "
          f"the fixture at {offset} ms, the clip at {start_ms:.3f} ms, rounding "
          f"{rounding:+.3f} ms taken out → {corrected:+.3f} ms; S18 − locate "
          f"{fmt(corrected - located if located is not None else None)} ms")


# ---- R rows --------------------------------------------------------------------


def r_rows(mcp, wanted):
    files = sync_fixtures()
    source = envelope(wav_samples(Path(files["source"])))
    session = Session(mcp, "offset-r")
    issue = {"R1": "+25.71", "R2": "−2.81"}
    try:
        clip = session.place(files["recorder"], F206)
        for row in R_ROWS:
            if row == "R2":
                session.op("set_speed", clip=clip, rate=0.99999, keep_pitch=False)
            if row not in wanted:
                continue
            out = EXPORTS / f"{row}.wav"
            EXPORTS.mkdir(parents=True, exist_ok=True)
            out.unlink(missing_ok=True)
            session.op("export", preset="audio_wav", path=str(out))
            lag, r = window_lag(envelope(wav_samples(out)), source, 12_000, 22_000)
            score(row, r >= 0.8, f"{'×1' if row == 'R1' else '×0.99999 keep_pitch false'}: "
                  f"S18 lag {lag:+.2f} ms (r {r:.3f}) on [12 s, 22 s); #298 reported "
                  f"{issue[row]} ms")
    finally:
        session.close()


# ---- L rows (the probe) --------------------------------------------------------


def build_probe():
    """(binary, None) or (None, why): every `app_sources()` file plus the probe
    as `main.swift`, `Blank.mp4` beside (`playback_audio_proof.py`'s pattern)."""
    PROBE_DIR.mkdir(parents=True, exist_ok=True)
    entry = PROBE_DIR / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    blank = PROBE_DIR / "Blank.mp4"
    if not blank.exists():
        shutil.copy2(BLANK, blank)
    binary = PROBE_DIR / "export_offset_probe"
    try:
        swift_build.build(sources=swift_build.app_sources() + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"], timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        return None, "the probe did not build: " + "; ".join(error.diagnostics[:6])
    return binary, None


def run_probe(binary):
    """({row: probe row}, manifest, None) or (None, None, why)."""
    shutil.rmtree(PROBE_RUNS, ignore_errors=True)
    PROBE_RUNS.mkdir(parents=True)
    ran = bounded.run([str(binary), str(PROBE_RUNS), str(FIXTURES)], RUN_WALL,
                      cwd=str(binary.parent))
    (PROBE_RUNS / "stderr.txt").write_text(ran["stderr"])
    if ran["expired"]:
        return None, None, f"the probe ran past {RUN_WALL} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                rows = {r["id"]: r for r in json.loads(line[len("ANSWER "):]).get("rows", [])}
                manifest = json.loads((PROBE_RUNS / "manifest.json").read_text())
            except (OSError, ValueError) as error:
                return None, None, f"the probe's answer or manifest could not be read: {error}"
            return rows, manifest, None
    return None, None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


def measure_read(entry):
    """The located summary of one manifest read, or None."""
    if not entry.get("ok"):
        return None
    path = Path(entry["path"])
    if path.suffix == ".wav":
        samples, rate = read_wav(path)
    else:
        rate = entry["rate"]
        samples = read_f32(path, rate)
    start = entry["start_ticks"] / SEC
    speed = entry["speed"] or 1
    expected = [start + c / speed for c in CLICKS]
    return summary(locate(samples, rate, expected), expected)


def chain_key(entry):
    return entry["variant"].split("+")[0]


def l_rows(wanted):
    try:
        fixtures()
    except FixtureError as error:
        for row in wanted:
            score(row, False, f"the fixtures could not be made: {error}")
        return
    binary, why = build_probe()
    rows = manifest = None
    if binary is not None:
        rows, manifest, why = run_probe(binary)
    if rows is None:
        for row in wanted:
            score(row, False, why)
        return
    measured = []
    for entry in manifest:
        try:
            s = measure_read(entry)
        except (OSError, ValueError, KeyError, wave.Error) as error:
            # A read that cannot be measured scores its row FAIL (the row's
            # "under 10 found" names it); it never ends the script.
            print(f"  unreadable: {entry.get('path')}: {error}", flush=True)
            s = None
        measured.append((entry, s))
        l_table.append((entry, s))
    for row in wanted:
        probe_row = rows.get(row, {"ok": False, "detail": "the probe did not answer it"})
        mine = [(e, s) for e, s in measured if e["row"] == row]
        short = [f"{e['fixture']} {e['stage']} {e['variant']}" for e, s in mine
                 if s is None or s["found"] < 10]
        ok = probe_row["ok"] and bool(mine) and not short
        medians = ", ".join(
            f"{e['fixture']} {e['stage']} {e['variant']} {fmt(s['median_ms'])}"
            for e, s in mine if s is not None)
        score(row, ok, f"probe: {probe_row['detail']}; under 10 found: {short or 'none'}; "
                       f"medians (ms): {medians}")
    print_where(measured)


def print_where(measured):
    """Per fixture and speed, the first stage whose median moves > 0.1 ms."""
    by = {}
    for entry, s in measured:
        if s is None or s["median_ms"] is None:
            continue
        if entry["row"] in ("L1", "L2"):
            by.setdefault((entry["fixture"], entry["stage"]), s["median_ms"])
        elif entry["row"] in ("L3", "L4", "L5", "L8"):
            by[(entry["fixture"], chain_key(entry), entry["stage"])] = s["median_ms"]
    print("\nWhere each offset enters (first stage moving > 0.1 ms from the one before):",
          flush=True)
    keys = sorted({(key[0], key[1]) for key in by if len(key) == 3})
    for fixture, speed in keys:
        chain = [("asset48", by.get((fixture, "asset48")))] + [
            (stage, by.get((fixture, speed, stage))) for stage in ("comp", "mix", "export")]
        steps = " → ".join(f"{stage} {fmt(m)}" for stage, m in chain)
        enters = "none (every step within 0.1 ms)"
        previous = None
        for stage, m in chain:
            if m is None:
                continue
            if previous is not None and abs(m - previous[1]) > 0.1:
                enters = f"{stage} ({m - previous[1]:+.3f} ms after {previous[0]})"
                break
            previous = (stage, m)
        native = by.get((fixture, "native"))
        asset = by.get((fixture, "asset48"))
        src = (f"; native − asset48 {native - asset:+.3f} ms"
               if native is not None and asset is not None else "")
        print(f"  {fixture} {speed}: {steps}; enters at {enters}{src}", flush=True)


# ---- tables --------------------------------------------------------------------


def print_tables():
    if e_table:
        print("\nE table (found − expected, ms):", flush=True)
        print("| Row | Media | At | Edit | Preset | Found | Median | Spread | Min r | Target |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for row, (fixture, at, edit, preset), r in e_table:
            edit_text = "×1" if edit is None else " ".join(str(x) for x in edit)
            if r is None:
                print(f"| {row} | {fixture} | {at / SEC:.4f} s | {edit_text} | {preset} | "
                      "not measured | | | | |")
                continue
            print(f"| {row} | {fixture} | {at / SEC:.4f} s | {edit_text} | {preset} | "
                  f"{r['found']}/{r['of']} | {fmt(r['median_ms'])} | {fmt(r['spread_ms'])} | "
                  f"{r['min_r']:.3f} | {e_target(row, r)} |")
    if l_table:
        print("\nL table (found − expected, ms):", flush=True)
        print("| Row | Fixture | Stage | Variant | Rate | Found | Median | Spread | Min r | "
              "First pts |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for entry, s in l_table:
            pts = entry.get("first_pts_s")
            if s is None:
                print(f"| {entry['row']} | {entry['fixture']} | {entry['stage']} | "
                      f"{entry['variant']} | {entry['rate']} | failed: "
                      f"{str(entry.get('error'))[:120]} | | | | |")
                continue
            print(f"| {entry['row']} | {entry['fixture']} | {entry['stage']} | "
                  f"{entry['variant']} | {entry['rate']} | {s['found']}/{s['of']} | "
                  f"{fmt(s['median_ms'])} | {fmt(s['spread_ms'])} | {s['min_r']:.3f} | "
                  f"{'—' if pts is None else f'{pts:.6f}'} |")


# ---- main ----------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    wanted = args.only.split(",") if args.only else list(ALL_ROWS)
    unknown = [row for row in wanted if row not in ALL_ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    needs_app = [row for row in wanted if row not in NO_APP]
    if needs_app and not args.socket:
        print("rows " + ", ".join(needs_app) + " need the running instance's socket path")
        return 2
    WORK.mkdir(parents=True, exist_ok=True)

    if "Z2" in wanted:
        z2()
    if "Z0" in wanted:
        try:
            z0()
        except (FixtureError, OSError, ValueError, wave.Error) as error:
            score("Z0", False, f"{type(error).__name__}: {error}")

    if needs_app:
        try:
            fixtures()
            mcp = MCP(args.socket)
        except Exception as error:  # an instrument failure is a scored FAIL of the rest
            for row in needs_app:
                score(row, False, f"not run: {type(error).__name__}: {error}")
            mcp = None
        if mcp is not None:
            for row, fn in [("Z1", z1), ("Z3", z3)]:
                if row in wanted:
                    try:
                        fn(mcp)
                    except Exception as error:
                        score(row, False, f"{type(error).__name__}: {error}")
            r_wanted = [row for row in R_ROWS if row in wanted]
            if r_wanted:
                try:
                    r_rows(mcp, r_wanted)
                except Exception as error:
                    for row in r_wanted:
                        if row not in results:
                            score(row, False, f"{type(error).__name__}: {error}")
            # E4 first, so E22's difference has its base.
            for row in sorted((r for r in E_IDS if r in wanted),
                              key=lambda r: (r != "E4", E_IDS.index(r))):
                e_row(mcp, row)

    l_wanted = [row for row in L_ROWS if row in wanted]
    if l_wanted:
        l_rows(l_wanted)

    print_tables()
    passed = sum(1 for row in wanted if results.get(row, (False,))[0])
    print(f"scores: {passed}/{len(wanted)}")
    return 0 if passed == len(wanted) else 1


if __name__ == "__main__":
    sys.exit(main())
