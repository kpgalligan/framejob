#!/usr/bin/env python3
"""Road map "creator-jobs" CO1 — person masks on the Mac (spec §11 CO-10…CO-15).

    python3 tools/proof/co1_proof.py [--only P1,M3,…] [--mutant NAME] [--app PATH]

The fixtures are `cutout_spike.fixtures()`'s (`tools/proof/media/cutout/`,
made on first use) and this script's own beside them: `push_60.mov`
(`push_1080.mov` looped three times, `-c copy`), M4's three from the owner's
talking head (`OWNER`; the push-in's poster is too weak a person for an IoU
bar: a plain re-encode keeps a mean IoU of 0.73) — `talk_sdr.mov` (its first
20 s as SDR), `talk_applelog.mov` (a `lut3d` cube undoing GR-16's display
transform with `log_proof.py`'s Apple Log encode, HEVC Main 10),
`talk_hlg.mov` (a cube inverting GR-15's HLG arm, tagged
bt2020/arib-std-b67/bt2020nc, frames 119 and 270 dropped) and
`talk_sdr_hevc.mov` (the noise floor, printed) — and `push_640_relinked.mov`
(`push_640.mov` with a title, `-c copy`). Every row
is a read-back: the probe's own answer, a tool's answer, or the bytes of the
cache's marker and `masks.pack` (parsed here; masks compared by the probe's
`compare` mode, which decompresses them).

**Probe rows** (`co1_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app): P1 a fresh pack reads
back byte-exact; P2 two publishes of disjoint ranges in either order give the
union, earlier blobs in place, an equal pts keeping its on-disk slot; P3
`shown(at:)`; P4 the found flag at exactly 0.5 %; P5 the `vision` field alone
makes a miss, and a masks stamp's JSON; P6 a throwing write leaves the store
as it was; P7 a publish during a save; P8 `runs`, the capped rate's nearest
slot and `covered`; P9 a marker whose pack is deleted, garbage or another
size; P10 a publish of a range that made no mask (0 × 0, no frames) keeps the
pack, its size and every frame, and the coverage becomes the union; P11
`AnalysisMasks.run` over a request whose one range lies wholly past the grid
(a missing file) answers true with no trap, no progress and nothing published
(#456).

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`), each launch on a
scratch `CFFIXED_USER_HOME`; Z1 is each launch's parity grep:
- M1 `push_60.mov` asked for 12–37 s writes a pack whose frame table is exactly
  the frames of grid indices 360…1109 at ffprobe's presentation times, once
  each, coverage [[360, 1109]].
- M2 the whole `cache/analysis/masks/` folder removed and asked again: every
  mask the first run's size (CO-10's 512 × 384) and within 1/255 of the first
  run's at every pixel.
- M3 the stamp names kind version, request, quality, revision, rate, read
  size, OS build and CO-11's device, and no path.
- M4 the Apple Log twin (`set_media_color {log: apple_log}`) and the HLG twin,
  read through the third arm over 0–10 s (both of the HLG twin's dropped
  frames): mean IoU ≥ 0.98 against the SDR push-in's masks at shared pts,
  their frame tables the files' own pts.
- M5 the 640 × 360 push-in (uncompressed BGRA in MOV: AVFoundation refuses PNG
  in MOV) and its rotation-tagged transpose: masks within
  1/255; the portrait pair likewise; each pack's `mask_size` printed.
- M6 `relink_media` to another file: a miss, the stamp's source changed, the
  pack holding only the new run's frames.
- M7 `save_project` five times during a running job: after each, the pack
  absent or parsing whole with the marker's coverage matching its frames; no
  save refused.
- M8 `close_project` during a running job: outcome `cancelled`; the marker and
  pack read after the run ended are byte-identical 3 s later, and a marker
  written (the cancelled job's publish, spec §11 CJ-21 as amended by #435)
  covers one range from index 0.
- M9 (Release only: Debug's per-pixel loops are unoptimised) the M1 window's
  realtime factor, median of three cold runs, ≥ 0.8 × CO-11's Standard factor.

`--mutant NAME`: the named decision broken in a copy — `app/Sources` copied
for the probe's rows, the tree copied and built (`tree_copy.py`) for the
app's — and only its row run; CAUGHT (exit 0) when that row fails, SURVIVED
(exit 1) otherwise.
"""

import argparse
import json
import os
import shutil
import statistics
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "cutout_spike"))
sys.path.insert(0, str(HERE / "creator_spike"))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import cutout_spike  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co1-proof"
HOME = WORK / "home"
MEDIA = cutout_spike.MEDIA
FFMPEG, FFPROBE = cutout_spike.FFMPEG, cutout_spike.FFPROBE
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
STANDARD_FACTOR = 1.228   # CO-11: Standard on the GPU at 1080p30 (`CO-S1-gpu`)
LANDSCAPE_MASK = [512, 384]   # CO-10
# The owner's own talking head (an iPhone HLG recording; `owner-sync`, gitignored,
# never committed): M4's person. Without it M4 is skipped by name and owed.
OWNER = ROOT / "tools/proof/media/owner-sync/IMG_0018.MOV"
P_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11"]
PLAIN = ["M1", "M2", "M3", "M4", "M5", "M6", "M9"]
JOBS = ["M7", "M8"]
ROWS = P_ROWS + PLAIN + JOBS + ["Z1"]
RELEASE_ONLY = {"M9": "Debug's per-pixel loops are unoptimised (spec §11 V-4)"}

MASKS = "app/Sources/AnalysisMasks.swift"
STORE = "app/Sources/AnalysisStore.swift"
MUTANTS = {
    "device-unpinned": (["M3"], [(
        "app/Sources/AnalysisVision.swift", "                request.setComputeDevice(pick, for: stage)\n",
        "")]),
    "fast-quality": (["M2"], [(
        MASKS, "        request.qualityLevel = .balanced\n", "        request.qualityLevel = .fast\n")]),
    "times-off-by-one": (["M1"], [(
        MASKS, "job.frames.append((pts, Int32(k)))",
        "job.frames.append((pts + Int64(grid.frameTicks.rounded()), Int32(k)))")]),
    "converted-via-composition": (["M4"], [(
        MASKS, "arm: request.input == nil ? .standard : .inputPass)", "arm: .standard)")]),
    "marker-before-pack": (["P6"], [(
        STORE, "            try? fm.removeItem(at: partial)\n            let mergedOnDisk: Bool\n",
        "            try JSONEncoder().encode(AnalysisMarker(stamp: stamp, canned: nil, "
        "source: stamp.source, files: files, coverage: covered.map { [$0.lowerBound, "
        "$0.upperBound] })).write(to: marker, options: .atomic)\n"
        "            try? fm.removeItem(at: partial)\n            let mergedOnDisk: Bool\n")]),
    "range-end-dropped": (["M1"], [(
        MASKS, "try publish(request, &job, through: range, size: size)",
        "try publish(request, &job, through: range.lowerBound...max(range.lowerBound, "
        "range.upperBound - 1), size: size)")]),
    "found-threshold": (["P4"], [(
        "app/Sources/MaskPack.swift", "return above * 200 >= width * height",
        "return above * 200 > width * height")]),
    "missing-pack-hit": (["P9"], [(
        STORE, "marker.answers(for: stamp),\n            let file = marker.files.first,\n"
        "            FileManager.default.fileExists(\n"
        "                atPath: payloadURL(kind, media: media, file: file, in: cacheDir).path)\n",
        "marker.answers(for: stamp)\n")]),
    "masks-crossed-range": (["P11"], [(
        MASKS, "            guard lo <= hi else { continue }\n", "")]),
}

results = {}
selected = set(ROWS)
probe_binary = None


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


# ---- fixtures ------------------------------------------------------------------

def ffmpeg(args, out):
    cutout_spike.ffmpeg(args, out)


def pts_ticks(path):
    """Every frame's presentation time in source ticks, from ffprobe, sorted."""
    run = subprocess.run([FFPROBE, "-v", "error", "-select_streams", "v:0", "-show_entries",
                          "packet=pts_time", "-of", "json", str(path)], capture_output=True,
                         text=True, timeout=600)
    packets = json.loads(run.stdout).get("packets") or []
    return sorted(round(float(p["pts_time"]) * SEC) for p in packets if "pts_time" in p)


def count_of(path):
    probe = cutout_spike.frame_count(path) if path.exists() else None
    return probe["frames"] if probe else None


def cube(path, function, size=33):
    lines = [f"LUT_3D_SIZE {size}"]
    step = size - 1
    for b in range(size):
        for g in range(size):
            for r in range(size):
                out = function([r / step, g / step, b / step])
                lines.append(" ".join(f"{min(1.0, max(0.0, v)):.6f}" for v in out))
    path.write_text("\n".join(lines) + "\n")


def apple_log_of(sdr):
    """An SDR BT.709 pixel → the Apple Log signal GR-16's display transform
    brings back to it (`log_proof.display`'s gamma and shoulder undone, then
    the exposure and the BT.2020 matrix, then Apple's encode)."""
    import log_proof as lp
    linear = [c ** lp.DISPLAY_GAMMA for c in sdr]
    top = max(linear)
    if top > lp.KNEE:
        low, high = lp.KNEE, lp.LOG_WHITE
        for _ in range(60):
            mid = (low + high) / 2
            low, high = (mid, high) if lp.shoulder(mid, lp.LOG_WHITE) < top else (low, mid)
        linear = [c * low / top for c in linear]
    to2020 = lp.mat_inv(lp.to709("bt2020"))
    light = lp.mat_vec(to2020, [c / lp.EXPOSURE for c in linear])
    return [lp.encode_curve("apple_log", max(c, 0.0)) for c in light]


def hlg_of(sdr):
    """An SDR BT.709 pixel → the HLG signal GR-15's step 0 brings back to it in
    an SDR project (`hdr_proof.convert("hlg", "bt2020", …)` inverted in closed
    form: the gamma and the shoulder undone, BT.709 → BT.2020, the OOTF's
    gain and γ on BT.2020 luminance undone, the HLG OETF). Not
    `InputConversions.liftSDR`, which is HD-3's lift INTO an HLG project: a
    lifted twin converts back 34 levels darker on average (frame 60's means
    127 against 93), and its masks kept a mean IoU of 0.9707."""
    import hdr_proof as hdr
    linear = [max(c, 0.0) ** hdr.DISPLAY_GAMMA for c in sdr]
    top = max(linear)
    if top > hdr.KNEE:
        low, high = hdr.KNEE, hdr.HLG_WHITE
        for _ in range(60):
            mid = (low + high) / 2
            low, high = (mid, high) if hdr.shoulder(mid, hdr.HLG_WHITE) < top else (low, mid)
        linear = [c * low / top for c in linear]
    light = [max(c, 0.0) for c in hdr.mat_vec(hdr.mat_inv(hdr.to709("bt2020")), linear)]
    display = sum(w * c for w, c in zip(hdr.LUMA2020, light))
    if display <= 0:
        return [0.0, 0.0, 0.0]
    ys = (display / hdr.HLG_GAIN) ** (1 / hdr.HLG_GAMMA)
    return [hdr.hlg_oetf(c / (hdr.HLG_GAIN * ys ** (hdr.HLG_GAMMA - 1))) for c in light]


def fixtures():
    cutout_spike.fixtures({})
    looped = MEDIA / "push_60.mov"
    if count_of(looped) != 1800:
        listing = WORK.parent / "co1-push60.txt"
        listing.write_text("".join(f"file '{MEDIA / 'push_1080.mov'}'\n" for _ in range(3)))
        ffmpeg(["-f", "concat", "-safe", "0", "-i", str(listing), "-c", "copy",
                "-video_track_timescale", "600"], looped)
    if count_of(looped) != 1800:
        raise SystemExit(f"{looped} does not hold 1800 frames")
    if OWNER.exists():
        talk_fixtures()
    relinked = MEDIA / "push_640_relinked.mov"
    if not relinked.exists():
        ffmpeg(["-i", str(MEDIA / "push_640.mov"), "-c", "copy", "-metadata",
                "title=relinked"], relinked)


def talk_fixtures():
    """M4's three, from the owner's talking head (`OWNER`, never committed):
    `talk_sdr.mov` its first 20 s as SDR (the HLG signal re-matrixed to BT.709
    and tagged so: a clear, large person, which the push-in's poster is not —
    a plain HEVC re-encode of `push_1080.mov` keeps only a mean IoU of 0.73 of
    its masks), then the Apple Log and HLG twins of it through the cubes."""
    sdr = MEDIA / "talk_sdr.mov"
    tags709 = "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709"
    if count_of(sdr) != 600:
        ffmpeg(["-i", str(OWNER), "-t", "20", "-an", "-vf",
                "scale=in_color_matrix=bt2020:in_range=tv:out_color_matrix=bt709:out_range=tv,"
                f"format=yuv420p,{tags709}", "-c:v", "libx264", "-preset", "veryfast", "-crf",
                "16", "-video_track_timescale", "600"], sdr)
    apple = MEDIA / "talk_applelog.mov"
    if count_of(apple) != 600:
        lut = MEDIA / "applelog.cube"
        cube(lut, apple_log_of)
        ffmpeg(["-i", str(sdr), "-vf",
                f"scale=in_color_matrix=bt709:in_range=tv,format=rgb48le,lut3d=file={lut},"
                f"scale=out_color_matrix=bt709:out_range=tv,format=p010le,{tags709}",
                "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-b:v", "40M", "-tag:v",
                "hvc1", "-video_track_timescale", "600"], apple)
    floor = MEDIA / "talk_sdr_hevc.mov"  # printed beside M4: the masks' noise floor
    if count_of(floor) != 600:
        ffmpeg(["-i", str(sdr), "-vf", f"format=p010le,{tags709}", "-c:v", "hevc_videotoolbox",
                "-profile:v", "main10", "-b:v", "40M", "-tag:v", "hvc1",
                "-video_track_timescale", "600"], floor)
    hlg = MEDIA / "talk_hlg.mov"
    if count_of(hlg) != 598:
        lut = MEDIA / "hlg.cube"
        cube(lut, hlg_of)
        ffmpeg(["-i", str(sdr), "-vf",
                "select='not(eq(n\\,119))*not(eq(n\\,270))',scale=in_color_matrix=bt709:"
                f"in_range=tv,format=rgb48le,lut3d=file={lut},scale=out_color_matrix=bt2020:"
                "out_range=tv,format=p010le,setparams=color_primaries=bt2020:"
                "color_trc=arib-std-b67:colorspace=bt2020nc", "-fps_mode", "passthrough",
                "-c:v", "hevc_videotoolbox", "-profile:v", "main10", "-b:v", "40M", "-tag:v",
                "hvc1", "-video_track_timescale", "600"], hlg)


# ---- the pack, read here -------------------------------------------------------

def parse_pack(path):
    """(width, height, frames [(pts, index, slot)], masks [(pts, offset, length,
    found)]); raises ValueError for a pack that does not parse."""
    data = Path(path).read_bytes()
    if len(data) < 40 or data[-40:-36] != b"FJMP":
        raise ValueError("not a pack")
    version, w, h, nf, nm, tables, zero = struct.unpack("<IIIIIQQ", data[-36:])
    if version != 1 or zero != 0 or tables + nf * 16 + nm * 24 != len(data) - 40:
        raise ValueError(f"version {version}, tables {tables}, {nf} frames, {nm} masks, "
                         f"{len(data)} bytes")
    frames = [struct.unpack_from("<qiI", data, tables + i * 16) for i in range(nf)]
    base = tables + nf * 16
    masks = [struct.unpack_from("<qQIB", data, base + i * 24) for i in range(nm)]
    if any(o + n > tables for _, o, n, _ in masks) or any(s >= nm for _, _, s in frames):
        raise ValueError("a mask or a slot past the tables")
    return w, h, frames, masks


def compare(pairs):
    """The probe's `compare` mode over (a, b) pack paths."""
    request = WORK / "compare.json"
    request.write_text(json.dumps({"fixture": str(MEDIA / "push_640.mov"),
                                   "work": str(WORK / "probe" / "compare"),
                                   "compare": [{"a": str(a), "b": str(b)} for a, b in pairs]}))
    run = subprocess.run([str(probe_binary), str(request)], capture_output=True, text=True,
                         timeout=900)
    return json.loads(run.stdout)["pairs"]


# ---- the probe rows ------------------------------------------------------------

def build_probe(sources):
    global probe_binary
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co1_probe.swift", entry)
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    binary = out / "co1-probe"
    swift_build.build(sources=swift + [str(entry)], output=binary, defines=["FRAMEJOB_DEV_TOOLS"])
    probe_binary = binary
    return binary


def probe_rows(sources):
    rows = [r for r in P_ROWS if r in selected]
    try:
        binary = build_probe(sources)
    except swift_build.SwiftBuildFailed as error:
        for row in rows or list(selected - {"Z1"}):
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return False
    if not rows:
        return True
    request = WORK / "probe" / "request.json"
    request.write_text(json.dumps({"fixture": str(MEDIA / "push_640.mov"),
                                   "work": str(WORK / "probe" / "run")}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=900)
        answer = json.loads(run.stdout)["rows"]
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        for row in rows:
            check(row, False, f"the probe gave no answer: {error}")
        return True
    by_id = {r["id"]: r for r in answer}
    for row in rows:
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))
    return True


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def media(self, fixture, tag):
        copy = WORK / "media" / f"{tag}{fixture.suffix}"
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixture, copy)
        return self.call("import_media", path=str(copy))["media"], copy

    def masks(self, media, **window):
        """`get_media_analysis {kind: masks}`, called again while a call
        refuses at its wait's bound (what it covered is kept)."""
        for _ in range(60):  # a Debug build's third arm reads about 0.5 frames a second
            try:
                return self.call("get_media_analysis", media=media, kind="masks", **window)
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        raise RuntimeError("the masks analysis did not finish in 60 calls")

    def folder(self):
        return self.path / "cache/analysis/masks"

    def pack(self, media):
        return self.folder() / str(media) / "masks.pack"

    def marker(self, media):
        return self.folder() / f"{media}.json"

    def coverage(self, media):
        path = self.marker(media)
        return json.loads(path.read_bytes())["coverage"] if path.exists() else None

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def window_frames(path, low, high):
    """(pts, index) of every frame of `path` whose grid index is in low…high."""
    out = []
    for pts in pts_ticks(path):
        k = round(pts * 30 / SEC)
        if low <= k <= high:
            out.append((pts, k))
    return out


def plain_rows(client):
    doc = Doc(client, "plain")
    first = {}

    def m1_m3():
        media, copy = doc.media(MEDIA / "push_60.mov", "push60")
        answer = doc.masks(media, **{"from": 12 * SEC, "to": 37 * SEC})
        first.update(media=media, answer=answer, copy=copy)
        w, h, frames, _ = parse_pack(doc.pack(media))
        got = [(pts, index) for pts, index, _ in frames]
        want = window_frames(copy, 360, 1109)
        check("M1", got == want and doc.coverage(media) == [[360, 1109]]
              and len(set(p for p, _ in got)) == len(got),
              f"{len(got)} frames, indices {got[0][1] if got else None}…"
              f"{got[-1][1] if got else None} (want {len(want)}, 360…1109, at ffprobe's pts: "
              f"{'equal' if got == want else 'DIFFER at ' + str([g for g, x in zip(got, want) if g != x][:3])}); "
              f"coverage {doc.coverage(media)}; answer frames {answer.get('frames')}, runs "
              f"{answer.get('count')}, mask_size {answer.get('mask_size')}, subject_found "
              f"{answer.get('subject_found')}")
        stamp = answer.get("stamp") or {}
        vision = stamp.get("vision") or {}
        text = json.dumps(stamp)
        named = (stamp.get("version") == 1 and stamp.get("kind") == "masks"
                 and vision.get("request") == "person_segmentation"
                 and vision.get("quality") == "balanced" and vision.get("revision") == 1
                 and vision.get("rate") == "every" and vision.get("readSize") == "source"
                 and bool(stamp.get("osBuild")) and stamp.get("device") == "gpu")
        no_path = str(WORK) not in text and copy.name not in text and "/" not in text
        check("M3", named and no_path,
              f"stamp {text} ({'names all' if named else 'MISSING a field or the GPU'}; "
              f"{'no path' if no_path else 'HOLDS A PATH'})")
    if selected & {"M1", "M2", "M3", "M9"}:
        attempt(m1_m3, "M1")

    def m2():
        media = first["media"]
        kept = WORK / "m2-first.pack"
        shutil.copyfile(doc.pack(media), kept)
        shutil.rmtree(doc.folder())
        again = doc.masks(media, **{"from": 12 * SEC, "to": 37 * SEC})
        pair = compare([(kept, doc.pack(media))])[0]
        size = pair.get("a_size")
        check("M2", not again["cached"] and pair.get("shared") == 750
              and pair.get("a_frames") == pair.get("b_frames") == 750
              and size == pair.get("b_size") == LANDSCAPE_MASK and pair.get("max_diff", 255) <= 1,
              f"again cached {again['cached']}; {pair}")
    if "M2" in selected and first:
        attempt(m2, "M2")

    def m4():
        sdr, _ = doc.media(MEDIA / "talk_sdr.mov", "talk_sdr")
        apple, apple_copy = doc.media(MEDIA / "talk_applelog.mov", "talk_applelog")
        doc.call("set_media_color", media=apple, color={"log": "apple_log"})
        hlg, hlg_copy = doc.media(MEDIA / "talk_hlg.mov", "talk_hlg")
        # 0–10 s holds both of the HLG twin's dropped frames (119 and 270).
        window = {"from": 0, "to": 10 * SEC}
        answers = {name: doc.masks(m, **window) for name, m in (("sdr", sdr), ("applelog", apple),
                                                               ("hlg", hlg))}
        pairs = compare([(doc.pack(sdr), doc.pack(apple)), (doc.pack(sdr), doc.pack(hlg))])
        details, ok = [], True
        for (name, copy, media), pair in zip((("applelog", apple_copy, apple),
                                              ("hlg", hlg_copy, hlg)), pairs):
            _, _, frames, _ = parse_pack(doc.pack(media))
            got = [pts for pts, _, _ in frames]
            # The file's own pts on the media's grid (CJ-23): index round(pts × fps),
            # the first frame on an index winning — a variable frame rate's
            # nominal 29.9 fps puts two frames on one index now and then.
            num, den = next(m for m in doc.state()["media"] if m["id"] == media)["fps"]
            want, seen = [], set()
            for p in pts_ticks(copy):
                k = round(p * num / (den * SEC))
                if p < 10 * SEC and k not in seen and k * den * SEC < 10 * SEC * num:
                    seen.add(k)
                    want.append(p)
            own = got == want
            reader = (answers[name].get("stamp") or {}).get("reader")
            good = own and pair.get("mean_iou", 0) >= 0.98 and reader == "converted"
            ok = ok and good
            details.append(f"{name}: reader {reader}, frame table "
                           + ("the file's own pts" if own else
                              f"NOT the file's pts (missing {sorted(set(want) - set(got))[:4]}, "
                              f"extra {sorted(set(got) - set(want))[:4]})")
                           + f" ({len(frames)} frames at {num}/{den} fps), shared "
                           f"{pair.get('shared')}, mean IoU {pair.get('mean_iou', 0):.4f} (median "
                           f"{pair.get('median_iou', 0):.4f}, least {pair.get('min_iou', 0):.4f}, "
                           f"{pair.get('below_090')} under 0.9)")
        floor, _ = doc.media(MEDIA / "talk_sdr_hevc.mov", "talk_sdr_hevc")
        doc.masks(floor, **window)
        base = compare([(doc.pack(sdr), doc.pack(floor))])[0]
        details.append(f"for the record, the SDR re-encoded as HEVC 10-bit at 40 Mb/s: mean IoU "
                       f"{base.get('mean_iou', 0):.4f} (median {base.get('median_iou', 0):.4f}, "
                       f"least {base.get('min_iou', 0):.4f}, {base.get('below_090')} under 0.9)")
        check("M4", ok, "; ".join(details))
    if "M4" in selected:
        if OWNER.exists():
            attempt(m4, "M4")
        else:
            print(f"  SKIP M4: the owner's talking head {OWNER} is missing (owed)")
            selected.discard("M4")

    def m5():
        made = {}
        for name in ("push_640", "push_640_cw", "push_640_t", "push_640_r"):
            media, _ = doc.media(MEDIA / f"{name}.mov", name)
            made[name] = (media, doc.masks(media))
        pairs = compare([(doc.pack(made["push_640"][0]), doc.pack(made["push_640_cw"][0])),
                         (doc.pack(made["push_640_t"][0]), doc.pack(made["push_640_r"][0]))])
        sizes = {n: a.get("mask_size") for n, (_, a) in made.items()}
        ok = all(p.get("max_diff", 255) <= 1 and p.get("shared") == 90 for p in pairs)
        check("M5", ok, f"landscape and its tagged transpose: {pairs[0]}; portrait pair: "
              f"{pairs[1]}; mask_size {sizes}")
    if "M5" in selected:
        attempt(m5, "M5")

    def m6():
        media, _ = doc.media(MEDIA / "push_640.mov", "relink")
        before = doc.masks(media)
        twin = WORK / "media" / "relink-target.mov"
        shutil.copyfile(MEDIA / "push_640_relinked.mov", twin)
        doc.call("relink_media", media=media, path=str(twin))
        after = doc.masks(media, **{"from": 1 * SEC, "to": 2 * SEC})
        _, _, frames, _ = parse_pack(doc.pack(media))
        indices = [index for _, index, _ in frames]
        was, now = before["stamp"]["source"], after["stamp"]["source"]
        check("M6", not after["cached"] and was != now and indices == list(range(30, 60))
              and doc.coverage(media) == [[30, 59]],
              f"after the relink cached {after['cached']}; source {was} → {now}; pack frames "
              f"{indices[:2]}…{indices[-1:]} ({len(indices)}), coverage {doc.coverage(media)}")
    if "M6" in selected:
        attempt(m6, "M6")

    def m9():
        media = first["media"]
        factors = []
        for _ in range(3):
            shutil.rmtree(doc.folder(), ignore_errors=True)
            answer = doc.masks(media, **{"from": 12 * SEC, "to": 37 * SEC})
            run = answer.get("run") or {}
            factors.append(25 / (run["ended_at"] - run["started_at"]))
        median = statistics.median(factors)
        check("M9", median >= 0.8 * STANDARD_FACTOR,
              f"realtime {[round(f, 3) for f in factors]}, median {median:.3f} (want ≥ "
              f"{0.8 * STANDARD_FACTOR:.3f}, 0.8 × CO-11's {STANDARD_FACTOR}); load "
              f"{cutout_spike.load()}")
    if "M9" in selected and first:
        if proof_app.config() != "release":
            print(f"  SKIP M9 on a {proof_app.config()} build: {RELEASE_ONLY['M9']}")
            selected.discard("M9")
        else:
            attempt(m9, "M9")
    doc.close()


def job(answer, path, media):
    for row in answer["jobs"]:
        if row["project"] and os.path.realpath(row["project"]) == os.path.realpath(path) \
                and row["media"] == media:
            return row
    return None


def job_rows(client):
    def dev(**arguments):
        return client.call_with("analysis_job", arguments)

    def m7():
        doc = Doc(client, "saves")
        media, _ = doc.media(MEDIA / "push_60.mov", "saves60")
        dev(project=str(doc.path), media=media, kind="masks")
        details, ok, saves = [], True, 0
        while saves < 5:
            time.sleep(6)
            row = job(dev(), doc.path, media) or {}
            try:
                doc.call("save_project")
                refused = None
            except mcp.ToolError as error:
                refused = str(error)
            saves += 1
            state, consistent = "absent", True
            for _ in range(3):
                if not doc.pack(media).exists():
                    state, consistent = "absent", True
                    break
                try:
                    _, _, frames, _ = parse_pack(doc.pack(media))
                except ValueError as error:
                    state, consistent = f"BROKEN {error}", False
                    continue
                cover = doc.coverage(media) or []
                held = [i for _, i, _ in frames]
                covered = sum(b - a + 1 for a, b in cover)
                inside = all(any(a <= i <= b for a, b in cover) for i in held)
                consistent = inside and len(held) == covered
                state = (f"{len(held)} frames = coverage {cover}" if consistent
                         else f"MISMATCH {len(held)} frames, coverage {cover}")
                if consistent:
                    break
                time.sleep(0.2)
            good = refused is None and consistent
            ok = ok and good
            details.append(f"save {saves} ({'running' if not row.get('outcome') else row['outcome']}"
                           f"): {'refused ' + refused if refused else 'saved'}, pack {state}")
        doc.close()  # cancels the job, so M8's is not queued behind it (width 1)
        check("M7", ok, "; ".join(details))
    if "M7" in selected:
        attempt(m7, "M7")

    def m8():
        doc = Doc(client, "closing")
        media, _ = doc.media(MEDIA / "push_60.mov", "closing60")
        dev(project=str(doc.path), media=media, kind="masks")
        started = None
        for _ in range(300):
            started = (job(dev(), doc.path, media) or {}).get("started_at")
            if started:
                break
            time.sleep(0.1)
        if not started:
            doc.close()
            check("M8", False, "the job never started (another job held the lane)")
            return
        time.sleep(1)

        def snapshot():
            return tuple(p.read_bytes() if p.exists() else None
                         for p in (doc.marker(media), doc.pack(media)))
        doc.close()
        row = job(dev(wait=5), doc.path, media) or {}
        held = snapshot()
        time.sleep(3)
        later = snapshot()
        cover = json.loads(held[0]).get("coverage") if held[0] is not None else None
        from_zero = cover is None or (len(cover) == 1 and cover[0][0] == 0)
        check("M8", row.get("outcome") == "cancelled" and held == later and from_zero,
              f"outcome {row.get('outcome')}; marker and pack read after the run ended "
              f"{'unchanged' if held == later else 'CHANGED'} 3 s later "
              f"({'none written' if held == (None, None) else f'coverage {cover}'}; want one "
              f"range from 0 when written)")
    if "M8" in selected:
        attempt(m8, "M8")


def launch(binary, tag):
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    for tag, body, rows in (("plain", plain_rows, set(PLAIN)), ("jobs", job_rows, set(JOBS))):
        if not selected & rows:
            continue
        launched, log = launch(binary, tag)
        try:
            if launched.client is None:
                for row in selected & rows:
                    check(row, False, f"the app did not listen ({tag})")
                continue
            print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
            body(launched.client)
        finally:
            launched.stop()
        parity(log, tag)


# ---- mutants -------------------------------------------------------------------

def mutant_sources(name):
    copy = WORK / "mutant-sources"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(ROOT / "app/Sources", copy)
    for path, anchor, replacement in MUTANTS[name][1]:
        target = copy / Path(path).name
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return copy, None


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "co1-mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(PLAIN + JOBS):
            selected.add("Z1")
    if selected & {"M2", "M9"}:
        selected.add("M1")  # their window's first run
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    fixtures()
    sources = ROOT / "app/Sources"
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"CO1 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        if set(named) <= set(P_ROWS):
            sources, why = mutant_sources(args.mutant)
        else:
            binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CO1 — person masks on the Mac ({proof_app.config()} build)", flush=True)
    built = probe_rows(sources if set(selected) & set(P_ROWS) else ROOT / "app/Sources")
    if built and selected & set(PLAIN + JOBS):
        if binary is None:
            binary = proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
