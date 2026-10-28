#!/usr/bin/env python3
"""Road map "codec-export" C4 — the `vp9_webm` row: VP9 through the bundled libvpx in the
core's WebM (`rc_webm_*`) with Opus sound, 8-bit Profile 0 for an SDR picture and 10-bit
Profile 2 for HLG and PQ (spec §11 CX-3, CX-8, CX-15, CX-16).

    python3 tools/proof/vp9_export_proof.py [--app debug|release|PATH] [--rate]
    python3 tools/proof/vp9_export_proof.py --probe          # P1 alone, no app
    python3 tools/proof/vp9_export_proof.py --mutant NAME

Launches its own instances of the chosen app (`proof_app.py`: `--app`, else
`RC_PROOF_APP`, else Debug; a build older than its inputs is refused) on scratch sockets,
works under `tools/proof/work/vp9-export/`, closes every project it opens with
`discard: true` and stops each instance by its own PID. It reuses `webm_export_proof.py`'s
and `av1_export_proof.py`'s helpers by import (the instance, the documents, the exports, the
ffprobe readers, the EBML walk, the sheet reading). ffprobe and ffmpeg (Homebrew, with
libvpx-vp9 decoding and Opus) only READ the files.

"A1's project" is `webm_export_proof.py`'s: AV.mov (640 × 360, 30 fps, 5 s) under a
two-second text clip, with chapter markers "Intro" at 0 s and "Body" at 2.5 s; "the HLG doc"
is the same made HLG. Each V row is over A1's project exported as `vp9_webm` unless it says
otherwise. Rows (`<ID> ok|FAIL — <detail>`, then `scores: n/m`; exit 0 iff all passed):

* Z1 — every instance's log is silent (no `Frame Job: `, `Svt[` or `SVT-AV1: ` line).
* V1 — done; format `matroska,webm`; video `vp9` Profile 0 `yuv420p` 640 × 360; audio
  `opus` 48 kHz stereo; the format's duration 5.0 s ± one frame. The walk: the video
  TrackEntry's CodecID `V_VP9`, no CodecPrivate, Colour 1/1/1 with Range 1 and
  BitsPerChannel 8.
* V2 — `ffmpeg -v error` decodes the file with no line; 150 video frames; exactly 240,000
  audio samples (#337's length).
* V3 — the video blocks as the walk reads them: the first a key, every key 2 s or less from
  the next (and from the end), fewer keys than blocks, and each block's key flag equal to
  "its first frame's VP9 uncompressed header has show_existing_frame 0 and frame_type 0
  (KEY_FRAME)", both ways.
* V4 — SDR pixels: A1's project as `vp9_webm` and as `hevc`, both at `video_bitrate`
  20,000,000, decoded by ffmpeg as yuv420p: each plane's mean absolute difference over
  frames 0–149 ≤ 6 codes; and `av1_export_proof.py`'s stripes fixture (100 % red, green and
  blue) in an SDR project, frame 30, each stripe's inner patch mean per plane within 3 codes.
* V5 — W5's chapters ("Intro" 0.0–2.5 s, "Body" 2.5–5.0 s), and W6's 1 s – 3 s in/out
  export: 60 frames, 96,000 samples, the chapters clamped and rebased.
* V6 — W9's cancel: a 24-clip 1080p project exported as `vp9_webm`, `cancel_export` while
  it encodes: `cancelled` within 10 s and no file at the path.
* V7 — `encoder_speed: "faster"` on `vp9_webm` is refused in the core's sentence (`vp9_webm
  has no encoder speed; encoder_speed applies to av1 and av1_webm`) and leaves no file; V1's
  done answer carries no `encoder_speed`.
* V8 — the HLG doc at the default, `pq` and `sdr`: the answer's `dynamic_range` (hlg, pq,
  sdr); ffprobe's profile and pixel format (Profile 2 `yuv420p10le`, Profile 2
  `yuv420p10le`, Profile 0 `yuv420p`) and colour tags; `trace_headers`' `color_space` (5, 5,
  2: BT.2020, BT.2020, BT.709) and `color_range` 0; the walk's Colour (9/18/9 with 10 bits;
  9/16/9 with 10 bits, MasteringMetadata and MaxCLL 1000 / MaxFALL 0; 1/1/1 with 8 bits;
  Range 1 on all three); on PQ the stream's mastering-display side data at HD-5's values, on
  the others no HDR side data.
* V9 — HDR pixels: the HLG doc at `hlg` and at `pq` as `vp9_webm` and as `hevc_10bit` at
  20,000,000 b/s, decoded as yuv420p10le: each plane's mean absolute difference over frames
  0–149 ≤ 6 codes; and the stripes fixture in an HLG project at hlg and pq, frame 30, each
  patch mean within 4 codes.
* V10 — `import_media` of V1's file and of V8's `hlg` file: each a 5.0 s (± one frame)
  640 × 360 media with audio. A project holding V1's media alone, rendered at 3 s
  (`render_frame`), against A1's project's render at 3 s (past the text clip): each RGB
  channel's mean absolute difference ≤ 8/255.
* V11 — a project holding only a 5 s text clip (no audio track): done; exactly one stream,
  `vp9` 640 × 360.
* S1 — the export sheet pinned to `{"preset_id":"vp9_webm"}`: Format "VP9 (WebM)", the Speed
  popup drawn disabled (`av1_export_proof.py` S2's rule: its darkest pixel more than 60
  levels lighter than the Format popup's) and the footnote "VP9 · WEBM".
* P1 — the probe `vp9_rate_probe.swift` (no app): `SVTAV1Encoder.crf` at CX-14's five
  points, two points between them and one beyond each end equals the table, per speed;
  `VP9Encoder.cqLevel` at CX-16's five points, a point inside each interval and one beyond
  each end, per depth. A probe that will not build is P1's FAIL.
* R1, R2 — only with `--rate`: the owner's IMG_0018.MOV (1920 × 1080, 30 fps, 55 s) in an
  SDR project, exported as `prores_422` (the reference), then R1 at Format default (no
  `video_bitrate`; the cap HEVC's 0.07 bits per pixel per frame) and R2 at the sheet's High
  tier (0.129 × 0.6, to 100 kb/s, asked of both), as `hevc` and as `vp9_webm`: the
  `vp9_webm` file's video rate (its packets' bytes over the duration) ≤ 1.30 × the cap and
  its VMAF against the reference (libvmaf, both as yuv420p) at or above `hevc`'s.
* R3 — only with `--rate`: the same clip in an HLG project at `hlg`, Format default, as
  `hevc_10bit` and `vp9_webm` against its `prores_422` reference, scored as yuv420p10le:
  ≤ 1.30 × the cap and VMAF at or above `hevc_10bit`'s. A missing fixture skips R by name.

Mutants (`--mutant NAME`, a tree copy built as Debug with the named anchor replaced; exit 1
and `MUTANT CAUGHT` when exactly the named rows fail — `cargo-<file>` is that cargo test file
run in the copy):

  vp9-not-hdr          `vp9_webm` out of the core's HDR_ROWS: V8, V9, cargo dynamic_range
  hdr-at-8-bits        `VP9Encoder.bitDepth` 8 for every picture: V8 (V9 cannot see it: the
                       8-bit samples are the 10-bit ones ÷ 4)
  sdr-at-10-bits       `VP9Encoder.bitDepth` 10 for every picture: V1 and V8 (V8's `sdr`
                       case reads the same profile; V4 cannot see it, a 10-bit file decoded
                       as yuv420p staying within its bounds)
  transfer-unlabelled  the HDR pictures' CICP transfer 2 (unspecified) in the layout: V8
  no-hdr10-in-webm     PQ's two blobs dropped from the layout: V8
  all-key              every VP9 packet flagged key: V3, and V10 (measured: the copy marks every
                       sample a sync sample, so the render at 3 s decodes an inter frame as a
                       key, R/G/B ≈ 125/255 from the source's)
  kf-interval-default  `kf_max_dist` unset (libvpx's 128 frames): V3
  full-range-8bit      the I420 kernel's Y = round(255·Y′), C = round(128 + 255·C′): V4
  speed-on-vp9         `Preset::takes_encoder_speed` any writer row: V7, S1 (the settings'
                       speed is the footnote's) and cargo export_vp9
  sdr-copy-unlabelled  the rewrap's SDR labels dropped (CX-16 (10)): V10, the 640 × 360 copy
                       read as BT.601 (and `hdr_proof.py --mutant sdr-copy-unlabelled` H7s)

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import json
import operator
import os
import re
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import av1_export_proof as av1  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import webm_export_proof as webm  # noqa: E402

WORK = HERE / "work" / "vp9-export"
av1.WORK = WORK            # the reused Instance, fixtures and mutant builder work here
webm.WORK = WORK
SEC = av1.SEC
FRAMES = 150
SAMPLES = 240_000
CANCEL_BOUND = 10.0
CAP_TOLERANCE = av1.CAP_TOLERANCE
PIXEL_RATE = 20_000_000
FRAME_BOUND = 6
SDR_PATCH_BOUND = 3
HDR_PATCH_BOUND = 4
RENDER_BOUND = 8
REFUSED_SPEED = "vp9_webm has no encoder speed; encoder_speed applies to av1 and av1_webm"

ROWS = ["Z1", "V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "S1",
        "P1"]

# P1's expected tables (spec §11 CX-14 (6), CX-16 (8)): bits per pixel per frame → value.
SVT_EXPECTED = {
    0.02: (36, 36, 36), 0.0386: (36, 36, 36), 0.045: (32, 33, 33), 0.0579: (26, 28, 28),
    0.07: (22, 24, 24), 0.0772: (20, 24, 24), 0.09: (17, 21, 21), 0.1157: (12, 16, 16),
    0.2: (12, 16, 16)}
VP9_EXPECTED = {
    0.02: (34, 34), 0.0386: (34, 34), 0.045: (31, 32), 0.0579: (26, 28), 0.064: (22, 25),
    0.07: (20, 24), 0.074: (18, 24), 0.0772: (18, 24), 0.09: (16, 22), 0.1157: (14, 20),
    0.2: (14, 20)}

SOURCES = "app/Sources"
MUTANTS = {
    "vp9-not-hdr": {"rows": ["V8", "V9"], "cargo": "dynamic_range", "anchors": [
        ("core/src/dynamic_range.rs", 'pub(crate) const HDR_ROWS: [&str; 6] = [\n',
         'pub(crate) const HDR_ROWS: [&str; 5] = [\n'),
        ("core/src/dynamic_range.rs", '    "vp9_webm",\n', '')]},
    "hdr-at-8-bits": {"rows": ["V8"], "anchors": [
        (f"{SOURCES}/ExportVP9Encoder.swift", "        picture == .sdr ? 8 : 10\n",
         "        picture == .sdr ? 8 : 8\n")]},
    "sdr-at-10-bits": {"rows": ["V1", "V8"], "anchors": [
        (f"{SOURCES}/ExportVP9Encoder.swift", "        picture == .sdr ? 8 : 10\n",
         "        picture == .sdr ? 10 : 10\n")]},
    "transfer-unlabelled": {"rows": ["V8"], "anchors": [
        (f"{SOURCES}/ExportAV1Picture.swift", "        case .hlg: return (9, 18, 9)\n",
         "        case .hlg: return (9, 2, 9)\n"),
        (f"{SOURCES}/ExportAV1Picture.swift", "        case .pq: return (9, 16, 9)\n",
         "        case .pq: return (9, 2, 9)\n")]},
    "no-hdr10-in-webm": {"rows": ["V8"], "anchors": [
        (f"{SOURCES}/ExportWebMLayout.swift", "        let hdr10 = picture.carriesHDR10\n",
         "        let hdr10 = picture.carriesHDR10 && false\n")]},
    "all-key": {"rows": ["V3", "V10"], "anchors": [
        (f"{SOURCES}/ExportVP9Encoder.swift",
         "                isKey: frame.flags & vpx_codec_frame_flags_t(VPX_FRAME_IS_KEY) != 0))\n",
         "                isKey: true || frame.flags & vpx_codec_frame_flags_t(VPX_FRAME_IS_KEY) "
         "!= 0))\n")]},
    "kf-interval-default": {"rows": ["V3"], "anchors": [
        (f"{SOURCES}/ExportVP9Encoder.swift",
         "        config.kf_max_dist = UInt32(max(1, (2 * perSecond).rounded(.down)))\n", "")]},
    "full-range-8bit": {"rows": ["V4"], "anchors": [
        ("app/Resources/Shaders/ExportI010.metal",
         "            planes[at.y * u.lumaStride + at.x] = uchar(round(16.0 + 219.0 * luma));\n",
         "            planes[at.y * u.lumaStride + at.x] = uchar(round(255.0 * luma));\n"),
        ("app/Resources/Shaders/ExportI010.metal",
         "    planes[u.cbOffset + chroma] = uchar(clamp(round(128.0 + 224.0 * cb / count), 0.0, "
         "255.0));\n",
         "    planes[u.cbOffset + chroma] = uchar(clamp(round(128.0 + 255.0 * cb / count), 0.0, "
         "255.0));\n"),
        ("app/Resources/Shaders/ExportI010.metal",
         "    planes[u.crOffset + chroma] = uchar(clamp(round(128.0 + 224.0 * cr / count), 0.0, "
         "255.0));\n",
         "    planes[u.crOffset + chroma] = uchar(clamp(round(128.0 + 255.0 * cr / count), 0.0, "
         "255.0));\n")]},
    # The ruling on C4's STOP (CX-16 (10)): an SDR WebM copy left unlabelled, as before it;
    # also `hdr_proof.py`'s mutant of the same name (H7s).
    "sdr-copy-unlabelled": {"rows": ["V10"], "anchors": [
        (f"{SOURCES}/ContainerRewrapWriter.swift",
         "            extensions.merge(sdrLabels(v)) { _, label in label }\n", "")]},
    "speed-on-vp9": {"rows": ["V7", "S1"], "cargo": "export_vp9", "anchors": [
        ("core/src/export_table.rs", "        self.writer.is_some_and(Writer::takes_speed)\n",
         "        self.writer.is_some()\n")]},
}

results = {}


def check(ident, ok, detail):
    results[ident] = bool(ok)
    print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def run(argv, seconds=600):
    return bounded.run([str(a) for a in argv], seconds)


def export(doc, path, **arguments):
    return av1.export(doc, path, **{"preset": "vp9_webm", **arguments})


# ---- reading the files -------------------------------------------------------------

def probe(path):
    ran = run(["ffprobe", "-v", "error", "-show_entries",
               "format=format_name,duration:stream=codec_type,codec_name,profile,pix_fmt,"
               "width,height,sample_rate,channels,color_space,color_transfer,color_primaries",
               "-of", "json", path])
    got = json.loads(ran["stdout"] or "{}")
    return got.get("format", {}), got.get("streams", [])


def video_entry(path):
    """The video TrackEntry as the walk reads it: (CodecID, has CodecPrivate, Colour)."""
    data, segment = webm.segment_of(path)
    for entry in webm.track_entries(segment):
        kind = webm.first(entry[4], 0x83)
        if kind and webm.uint(data, kind) == 1:
            codec = webm.first(entry[4], 0x86)
            name = data[codec[2]:codec[2] + codec[3]].decode("latin-1") if codec else None
            return name, webm.first(entry[4], 0x63A2) is not None, webm.colour_of(data, segment)
    return None, None, None


def video_payloads(path):
    """The video SimpleBlocks in file order: [(seconds, key flag, payload)]."""
    data, segment = webm.segment_of(path)
    out = []
    for cluster in (e for e in (segment[4] if segment else []) if e[0] == 0x1F43B675):
        base = webm.uint(data, webm.first(cluster[4], 0xE7))
        for block in (e for e in cluster[4] if e[0] == 0xA3):
            body = data[block[2]:block[2] + block[3]]
            track, n = webm.vint(body, 0, False)
            if track == 1:
                ms = base + int.from_bytes(body[n:n + 2], "big", signed=True)
                out.append((ms / 1000, bool(body[n + 2] & 0x80), body[n + 3:]))
    return out


def shown_key(payload):
    """Whether the payload's first frame's uncompressed header (VP9 bitstream §6.2) has
    show_existing_frame 0 and frame_type 0; None when it is not a VP9 frame header."""
    if not payload:
        return None
    bits = "".join(f"{b:08b}" for b in payload[:2])
    if bits[:2] != "10":
        return None
    profile = int(bits[2]) | (int(bits[3]) << 1)
    at = 5 if profile == 3 else 4
    return bits[at] == "0" and bits[at + 1] == "0"


def trace_colour(path):
    """`trace_headers`' `color_space` and `color_range` values over the stream."""
    _, per_packet = av1.trace(path)
    every = [f for p in per_packet for f in p["fields"]]
    return (sorted({v for k, v in every if k == "color_space"}),
            sorted({v for k, v in every if k == "color_range"}))


def decode8(path, frames=None, index=None):
    """The video decoded as yuv420p bytes; None when ffmpeg failed."""
    argv = ["ffmpeg", "-v", "error", "-i", str(path)]
    argv += (["-vf", f"select=eq(n\\,{index})", "-frames:v", "1"] if index is not None
             else ["-frames:v", str(frames)])
    try:
        ran = subprocess.run(argv + ["-f", "rawvideo", "-pix_fmt", "yuv420p", "-"],
                             capture_output=True, timeout=600)
    except subprocess.TimeoutExpired:
        return None
    return ran.stdout if ran.returncode == 0 and ran.stdout else None


def differences8(a, b, width, height, frames):
    spans, per = av1.plane_spans(width, height)
    if len(a) != per * frames or len(b) != per * frames:
        return None
    totals = [0, 0, 0]
    for f in range(frames):
        base = f * per
        for k, (start, end) in enumerate(spans):
            totals[k] += sum(map(abs, map(operator.sub, a[base + start:base + end],
                                          b[base + start:base + end])))
    return [totals[k] / ((end - start) * frames) for k, (start, end) in enumerate(spans)]


def patch8(data, width, height, stripe):
    spans, per = av1.plane_spans(width, height)
    if len(data) != per:
        return None
    half = (width + 1) // 2

    def mean(start, stride, rows, cols):
        total = sum(sum(data[start + r * stride + cols[0]:start + r * stride + cols[1] + 1])
                    for r in range(rows[0], rows[1] + 1))
        return total / ((rows[1] - rows[0] + 1) * (cols[1] - cols[0] + 1))

    return [mean(0, width, (120 * stripe + 30, 120 * stripe + 89), (64, 575)),
            mean(spans[1][0], half, (60 * stripe + 15, 60 * stripe + 44), (32, 287)),
            mean(spans[2][0], half, (60 * stripe + 15, 60 * stripe + 44), (32, 287))]


def video_rate(path):
    """The video's bit rate: the video packets' bytes over the file's duration (a WebM
    stream carries no bit_rate)."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "packet=size:format=duration", "-of", "json", path])
    got = json.loads(ran["stdout"] or "{}")
    total = sum(int(p["size"]) for p in got.get("packets", []))
    duration = float((got.get("format") or {}).get("duration") or 0)
    return round(total * 8 / duration) if duration > 0 else 0


def rgb(png):
    ran = subprocess.run(["ffmpeg", "-v", "error", "-i", str(png), "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], capture_output=True, timeout=120)
    return ran.stdout if ran.returncode == 0 else None


def vmaf(distorted, reference, log, pix):
    """libvmaf's pooled mean of `distorted` against `reference`, paired by FRAME INDEX: a
    WebM's block times are whole milliseconds, and pairing by timestamp put a third of the
    owner clip's frames against their neighbours' (measured, C4)."""
    lavfi = (f"[0:v]format={pix},settb=1/30,setpts=N[d];[1:v]format={pix},settb=1/30,setpts=N[r];"
             f"[d][r]libvmaf=log_fmt=json:log_path={log}:n_threads=12")
    ran = run(["ffmpeg", "-hide_banner", "-v", "error", "-i", distorted, "-i", reference,
               "-lavfi", lavfi, "-f", "null", "-"], 1200)
    try:
        return json.loads(Path(log).read_text())["pooled_metrics"]["vmaf"]["mean"]
    except (OSError, ValueError, KeyError):
        print(f"  libvmaf failed (rc {ran['rc']}): {ran['stderr'][-300:]}", flush=True)
        return None


# ---- the rows ----------------------------------------------------------------------

def rows_v1_v3(doc, out):
    path = out / "v1.webm"
    try:
        done = export(doc, path)
    except mcp.ToolError as error:
        for ident in ("V1", "V2", "V3", "V7", "V10"):
            check(ident, False, f"V1's export failed: {error}")
        return None, None
    fmt, got = probe(path)
    video = next((s for s in got if s.get("codec_type") == "video"), {})
    audio = next((s for s in got if s.get("codec_type") == "audio"), {})
    seen = (fmt.get("format_name"), video.get("codec_name"), video.get("profile"),
            video.get("pix_fmt"), video.get("width"), video.get("height"),
            audio.get("codec_name"), audio.get("sample_rate"), audio.get("channels"))
    want = ("matroska,webm", "vp9", "Profile 0", "yuv420p", 640, 360, "opus", "48000", 2)
    length = float(fmt.get("duration") or 0)
    codec, private, colour = video_entry(path)
    want_colour = {"matrix": 1, "bits": 8, "range": 1, "transfer": 1, "primaries": 1,
                   "mastering": False}
    check("V1", done.get("status") == "done" and seen == want and abs(length - 5) <= 1 / 30
          and codec == "V_VP9" and private is False and colour == want_colour,
          f"status {done.get('status')}, {done.get('bytes')} bytes; read {seen} (want {want}); "
          f"duration {length:.3f} s; walk CodecID {codec!r}, CodecPrivate {private}, Colour "
          f"{colour}")

    rc, errors = av1.decode_errors(path)
    frames = av1.decoded_frames(path)
    samples = webm.audio_samples(path)
    check("V2", rc == 0 and not errors and frames == FRAMES and samples == SAMPLES,
          f"ffmpeg rc {rc}, {len(errors)} error lines {errors[:2]}; {frames} frames (want "
          f"{FRAMES}); {samples} audio samples (want {SAMPLES})")

    blocks = video_payloads(path)
    keys = [t for t, k, _ in blocks if k]
    gaps = [b - a for a, b in zip(keys, keys[1:])] + ([length - keys[-1]] if keys else [])
    mismatched = [i for i, (_, key, payload) in enumerate(blocks) if key != shown_key(payload)]
    ok = (blocks and blocks[0][1] and gaps and max(gaps) <= 2.0 + 1e-6
          and len(keys) < len(blocks) and not mismatched)
    check("V3", ok, f"{len(blocks)} video blocks, keys at {keys}; longest K-to-K gap "
          f"{max(gaps) if gaps else None} s (≤ 2.0); key flag ≠ the first frame's KEY_FRAME "
          f"header at {mismatched[:6]}")
    return path, done


def row_v4(instance, doc, out):
    lines, ok, stripes = [], True, None
    try:
        decoded = {}
        for preset in ("vp9_webm", "hevc"):
            path = out / f"v4a-{preset}.{'webm' if preset == 'vp9_webm' else 'mp4'}"
            export(doc, path, preset=preset, video_bitrate=PIXEL_RATE)
            decoded[preset] = decode8(path, frames=FRAMES)
        diffs = (differences8(decoded["vp9_webm"], decoded["hevc"], 640, 360, FRAMES)
                 if decoded["vp9_webm"] and decoded["hevc"] else None)
        good = diffs is not None and all(d <= FRAME_BOUND for d in diffs)
        ok = good
        lines.append("(a) Y/Cb/Cr " + ("decode failed" if diffs is None
                                       else "/".join(f"{d:.3f}" for d in diffs))
                     + ("" if good else " ✗"))
        fixture = av1.stripes_fixture()
        if fixture is None:
            check("V4", False, "; ".join(lines) + "; the stripes fixture could not be made")
            return
        stripes = av1.Doc(instance, "v4-stripes")
        stripes.call("add_clip", track=stripes.track(), media=stripes.media(fixture), at=0)
        decoded = {}
        for preset in ("vp9_webm", "hevc"):
            path = out / f"v4b-{preset}.{'webm' if preset == 'vp9_webm' else 'mp4'}"
            export(stripes, path, preset=preset, video_bitrate=PIXEL_RATE)
            decoded[preset] = decode8(path, index=30)
        for stripe, colour in enumerate(("red", "green", "blue")):
            means = {p: patch8(d, 640, 360, stripe) if d else None for p, d in decoded.items()}
            if means["vp9_webm"] is None or means["hevc"] is None:
                ok = False
                lines.append(f"(b) {colour}: decode failed ✗")
                continue
            parts = []
            for plane, a, b in zip(("Y", "Cb", "Cr"), means["vp9_webm"], means["hevc"]):
                good = abs(a - b) <= SDR_PATCH_BOUND
                ok = ok and good
                parts.append(f"{plane} {a:.2f}/{b:.2f} ({a - b:+.2f})" + ("" if good else " ✗"))
            lines.append(f"(b) {colour}: " + ", ".join(parts))
    except (mcp.ToolError, KeyError, IndexError, OSError) as error:
        ok = False
        lines.append(f"{type(error).__name__}: {error}")
    finally:
        if stripes is not None:
            stripes.close()
    check("V4", ok, f"vp9_webm against hevc at {PIXEL_RATE} b/s as yuv420p, (a) each plane's "
          f"mean absolute difference ≤ {FRAME_BOUND} over frames 0–{FRAMES - 1}, (b) patch "
          f"means at frame 30 within {SDR_PATCH_BOUND}: " + "; ".join(lines))


def row_v5(doc, out, v1):
    listed = webm.chapters(v1) if v1 else None
    path = out / "v5-range.webm"
    try:
        doc.call("set_range", start=1 * SEC, end=3 * SEC)
        export(doc, path, range="in_out")
        frames, samples = av1.decoded_frames(path), webm.audio_samples(path)
        ranged = webm.chapters(path)
        check("V5", listed == webm.CHAPTERS and frames == 60 and samples == 96_000
              and ranged == webm.CHAPTERS_IN_OUT,
              f"chapters {listed} (want {webm.CHAPTERS}); the in/out export: {frames} frames "
              f"(want 60), {samples} samples (want 96000), chapters {ranged} (want "
              f"{webm.CHAPTERS_IN_OUT})")
    except mcp.ToolError as error:
        check("V5", False, str(error))
    finally:
        doc.call("set_range", start=0, end=5 * SEC)


def row_v6(instance, out):
    path = out / "v6.webm"
    path.unlink(missing_ok=True)
    doc, ok, detail = None, False, ""
    try:
        doc = webm.long_doc(instance, "v6")
        job = doc.client.call_with("export", {"project": doc.path, "path": str(path),
                                              "preset": "vp9_webm"})["export_id"]
        progress, status, measured, floor = 0, {}, None, None
        deadline = time.monotonic() + 300
        while time.monotonic() < deadline:
            status = doc.client.call("export_status", export_id=job)
            progress = status.get("progress") or 0
            if status.get("status") in ("done", "failed", "cancelled"):
                break
            if status.get("phase"):
                measured = max(measured or 0, progress)
            elif status.get("status") == "running" and measured is not None:
                if floor is None:
                    floor = progress
                elif progress > floor:
                    break
            time.sleep(0.05)
        if status.get("status") != "running":
            detail = f"never running past the measurement with progress above it: {status}"
        else:
            asked = time.monotonic()
            doc.client.call("cancel_export", export_id=job)
            final = {}
            while time.monotonic() - asked < 600:
                final = doc.client.call("export_status", export_id=job)
                if final.get("status") in ("done", "failed", "cancelled"):
                    break
                time.sleep(0.05)
            took = time.monotonic() - asked
            exists = path.exists()
            ok = final.get("status") == "cancelled" and took <= CANCEL_BOUND and not exists
            detail = (f"cancelled while encoding at progress {progress:.4f} (the writer "
                      f"started at {floor}); status {final.get('status')!r} {took:.2f} s "
                      f"after cancel_export (≤ {CANCEL_BOUND}); a file at the path: {exists}")
    except (mcp.ToolError, KeyError) as error:
        detail = f"{type(error).__name__}: {error}"
    finally:
        if doc is not None:
            doc.close()
    check("V6", ok, detail)


def row_v7(doc, out, done):
    path = out / "v7.webm"
    refused = av1.refusal(doc, path, preset="vp9_webm", encoder_speed="faster")
    left = path.exists()
    carried = done is not None and "encoder_speed" in done
    check("V7", refused is not None and REFUSED_SPEED in refused and not left
          and done is not None and not carried,
          f"encoder_speed on vp9_webm → {refused!r}; a file left {left}; V1's answer carries "
          f"encoder_speed: {carried if done is not None else 'no answer'}")


def row_v8(doc, out):
    lines, misses, hlg_path = [], [], None
    mastering = {"max_luminance": "1000/1", "min_luminance": "1/200", "red_x": "17/25",
                 "red_y": "8/25", "green_x": "53/200", "green_y": "69/100", "blue_x": "3/20",
                 "blue_y": "3/50", "white_point_x": "3127/10000", "white_point_y": "329/1000"}
    for asked, cicp, bits, profile, pix, tags, space, hdr10 in [
            (None, (9, 18, 9), 10, "Profile 2", "yuv420p10le", "bt2020nc/arib-std-b67/bt2020",
             5, False),
            ("pq", (9, 16, 9), 10, "Profile 2", "yuv420p10le", "bt2020nc/smpte2084/bt2020",
             5, True),
            ("sdr", (1, 1, 1), 8, "Profile 0", "yuv420p", "bt709/bt709/bt709", 2, False)]:
        want = asked or "hlg"
        path = out / f"v8-{want}.webm"
        try:
            done = export(doc, path, **({} if asked is None else {"dynamic_range": asked}))
        except mcp.ToolError as error:
            misses.append(f"{want}: {error}")
            continue
        if want == "hlg":
            hlg_path = path
        seen_pix, seen_profile, seen_tags = av1.colour_tags(path)
        spaces, ranges = trace_colour(path)
        _, _, colour = video_entry(path)
        stream = av1.stream_side(path)
        kinds = set(stream[1]) if stream else None
        want_colour = {"matrix": cicp[2], "bits": bits, "range": 1, "transfer": cicp[1],
                       "primaries": cicp[0], "mastering": hdr10}
        if hdr10:
            want_colour.update({"max_cll": 1000, "max_fall": 0})
        row = []
        if done.get("dynamic_range") != want:
            row.append(f"answer {done.get('dynamic_range')!r}")
        if (seen_pix, seen_profile, seen_tags) != (pix, profile, tags):
            row.append(f"read {seen_pix} / {seen_profile} / {seen_tags}")
        if (spaces, ranges) != ([space], [0]):
            row.append(f"trace color_space {spaces} color_range {ranges}")
        if colour != want_colour:
            row.append(f"Colour {colour}")
        if kinds is None:
            row.append("ffprobe could not read the side data")
        elif hdr10 and ("Mastering display metadata" not in kinds
                        or {k: stream[0].get(k) for k in mastering} != mastering):
            row.append(f"side data {sorted(kinds)} {stream[0]}")
        elif not hdr10 and {"Mastering display metadata",
                            "Content light level metadata"} & kinds:
            row.append(f"side data {sorted(kinds)}")
        misses += [f"{want}: {m}" for m in row]
        lines.append(f"{want}: {seen_pix} / {seen_profile} / {seen_tags}, trace color_space "
                     f"{spaces}, Colour {colour}, side data "
                     f"{sorted(kinds) if kinds is not None else None}")
    check("V8", not misses, "; ".join(lines) + (f"; misses {misses}" if misses else ""))
    return hlg_path


def row_v9(instance, hlg, out):
    lines, ok, stripes = [], True, None
    try:
        for label in ("hlg", "pq"):
            decoded = {}
            for preset in ("vp9_webm", "hevc_10bit"):
                path = out / f"v9a-{label}-{preset}.{'webm' if preset == 'vp9_webm' else 'mp4'}"
                export(hlg, path, preset=preset, video_bitrate=PIXEL_RATE, dynamic_range=label)
                decoded[preset] = av1.decode10(path, frames=FRAMES)
            diffs = (av1.frame_differences(decoded["vp9_webm"], decoded["hevc_10bit"], 640, 360,
                                           FRAMES)
                     if decoded["vp9_webm"] and decoded["hevc_10bit"] else None)
            good = diffs is not None and all(d <= FRAME_BOUND for d in diffs)
            ok = ok and good
            lines.append(f"(a) {label}: Y/Cb/Cr " + ("decode failed" if diffs is None
                                                     else "/".join(f"{d:.3f}" for d in diffs))
                         + ("" if good else " ✗"))
        fixture = av1.stripes_fixture()
        if fixture is None:
            check("V9", False, "; ".join(lines) + "; the stripes fixture could not be made")
            return
        stripes = av1.Doc(instance, "v9-stripes")
        stripes.call("set_canvas", output="hlg")
        stripes.call("add_clip", track=stripes.track(), media=stripes.media(fixture), at=0)
        for label in ("hlg", "pq"):
            decoded = {}
            for preset in ("vp9_webm", "hevc_10bit"):
                path = out / f"v9b-{label}-{preset}.{'webm' if preset == 'vp9_webm' else 'mp4'}"
                export(stripes, path, preset=preset, video_bitrate=PIXEL_RATE,
                       dynamic_range=label)
                decoded[preset] = av1.decode10(path, index=30)
            for stripe, colour in enumerate(("red", "green", "blue")):
                means = {p: av1.patch_means(d, 640, 360, stripe) if d else None
                         for p, d in decoded.items()}
                if means["vp9_webm"] is None or means["hevc_10bit"] is None:
                    ok = False
                    lines.append(f"(b) {label} {colour}: decode failed ✗")
                    continue
                parts = []
                for plane, a, b in zip(("Y", "Cb", "Cr"), means["vp9_webm"],
                                       means["hevc_10bit"]):
                    good = abs(a - b) <= HDR_PATCH_BOUND
                    ok = ok and good
                    parts.append(f"{plane} {a:.2f}/{b:.2f} ({a - b:+.2f})"
                                 + ("" if good else " ✗"))
                lines.append(f"(b) {label} {colour}: " + ", ".join(parts))
    except (mcp.ToolError, KeyError, IndexError, OSError) as error:
        ok = False
        lines.append(f"{type(error).__name__}: {error}")
    finally:
        if stripes is not None:
            stripes.close()
    check("V9", ok, f"vp9_webm against hevc_10bit at {PIXEL_RATE} b/s as yuv420p10le, (a) "
          f"each plane's mean absolute difference ≤ {FRAME_BOUND}, (b) patch means at frame 30 "
          f"within {HDR_PATCH_BOUND}: " + "; ".join(lines))


def row_v10(instance, source, v1, hlg_file, out):
    if v1 is None or hlg_file is None:
        return check("V10", False, f"a file to import is missing: V1 {v1}, V8's hlg {hlg_file}")
    doc, lines, ok = None, [], True
    try:
        doc = av1.Doc(instance, "v10")
        media = {}
        for label, path in (("V1", v1), ("V8 hlg", hlg_file)):
            answer = doc.call("import_media", path=str(path))
            found = next(m for m in doc.call("get_project")["project"]["media"]
                         if m["id"] == answer["media"])
            media[label] = found["id"]
            good = (abs(found["duration"] / SEC - 5) <= 1 / 30
                    and (found.get("width"), found.get("height")) == (640, 360)
                    and found.get("has_audio"))
            ok = ok and good
            lines.append(f"{label}: {found['duration'] / SEC:.3f} s "
                         f"{found.get('width')} × {found.get('height')}, audio "
                         f"{found.get('has_audio')}" + ("" if good else " ✗"))
        doc.call("add_clip", track=doc.track(), media=media["V1"], at=0)
        theirs, ours = out / "v10-source.png", out / "v10-import.png"
        source.call("render_frame", t=3 * SEC, path=str(theirs))
        doc.call("render_frame", t=3 * SEC, path=str(ours))
        a, b = rgb(theirs), rgb(ours)
        if not a or not b or len(a) != len(b):
            ok = False
            lines.append(f"the renders could not be read ({len(a or b'')}, {len(b or b'')})")
        else:
            means = [sum(abs(a[i] - b[i]) for i in range(c, len(a), 3)) / (len(a) / 3)
                     for c in range(3)]
            good = all(m <= RENDER_BOUND for m in means)
            ok = ok and good
            lines.append("render at 3 s against A1's: R/G/B "
                         + "/".join(f"{m:.3f}" for m in means) + f" (≤ {RENDER_BOUND})"
                         + ("" if good else " ✗"))
    except (mcp.ToolError, KeyError, StopIteration, OSError) as error:
        ok = False
        lines.append(f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()
    check("V10", ok, "; ".join(lines))


def row_v11(instance, out):
    path = out / "v11.webm"
    doc = None
    try:
        doc = webm.text_doc(instance, "v11")
        done = export(doc, path)
        _, got = probe(path)
        seen = [(s.get("codec_type"), s.get("codec_name"), s.get("width"), s.get("height"))
                for s in got]
        check("V11", done.get("status") == "done" and seen == [("video", "vp9", 640, 360)],
              f"status {done.get('status')}; streams {seen}")
    except (mcp.ToolError, ValueError) as error:
        check("V11", False, f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def run_v_rows(app, logs):
    out = WORK / "out"
    av1.tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = av1.Instance("v", app)
    logs.append(instance)
    idents = [r for r in ROWS if r.startswith("V")]
    try:
        if instance.client is None:
            for ident in idents:
                check(ident, False, f"the app did not listen ({instance.log})")
            return
        doc = hlg = None
        try:
            doc = webm.a1_doc(instance, "v1")
            v1, done = rows_v1_v3(doc, out)
            row_v4(instance, doc, out)
            row_v5(doc, out, v1)
            row_v7(doc, out, done)
            hlg = webm.a1_doc(instance, "v8", hlg=True)
            hlg_file = row_v8(hlg, out)
            row_v9(instance, hlg, out)
            row_v10(instance, doc, v1, hlg_file, out)
        except (mcp.ToolError, KeyError, IndexError) as error:
            for ident in idents:
                if ident not in results:
                    check(ident, False, f"A1's project could not be made: {error}")
        finally:
            for d in (doc, hlg):
                if d is not None:
                    d.close()
        row_v11(instance, out)
        row_v6(instance, out)
    finally:
        instance.stop()


def run_s1(app, logs):
    reading = av1.sheet_reading(app, "s1", '{"preset_id":"vp9_webm"}')
    logs.append(reading["instance"])
    lighter = (reading["speed_dark"] - reading["format_dark"]
               if reading.get("speed_dark") is not None
               and reading.get("format_dark") is not None else None)
    check("S1", not reading.get("error") and reading.get("format") == "VP9 (WebM)"
          and lighter is not None and lighter > 60
          and reading.get("footnote") == ["VP9 · WEBM"],
          f"{reading.get('error') or ''} format {reading.get('format')!r}, Speed "
          f"{reading.get('speed')!r} {lighter} levels lighter than Format (> 60 is disabled), "
          f"footnote {reading.get('footnote')}")


# ---- the probe (P1) ----------------------------------------------------------------

def run_probe(sources=ROOT / SOURCES):
    import reference_build
    import swift_build
    out = WORK / ("probe" if Path(sources).resolve() == (ROOT / SOURCES).resolve()
                  else "probe-mutant")
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    text = (HERE / "vp9_rate_probe.swift").read_text()
    if not entry.exists() or entry.read_text() != text:
        entry.write_text(text)
    binary, answer = out / "vp9-rate-probe", out / "answer.json"
    defines = reference_build.tree_defines(Path(sources).parent.parent, ["FRAMEJOB_DEV_TOOLS"])
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, defines=defines)
        if not built.reused:
            print(f"probe built in {built.seconds:.0f} s", flush=True)
    except swift_build.SwiftBuildFailed as error:
        lines = [line for line in error.diagnostics if ": error:" in line]
        return check("P1", False, "the probe did not build: "
                     + " | ".join(lines[:3] or list(error.diagnostics[:3]) or [str(error)]))
    points = sorted(set(SVT_EXPECTED) | set(VP9_EXPECTED))
    answer.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(answer), *map(str, points)], 120)
    if ran["expired"] or ran["rc"] != 0 or not answer.exists():
        return check("P1", False, "the probe did not run: "
                     + (ran["stdout"] + ran["stderr"]).strip()[-300:])
    got = json.loads(answer.read_text())
    misses = []
    for k, bpp in enumerate(points):
        if bpp in SVT_EXPECTED:
            seen = tuple(got["svt"][s][k] for s in ("faster", "balanced", "smaller"))
            if seen != SVT_EXPECTED[bpp]:
                misses.append(f"SVT at {bpp}: {seen} (want {SVT_EXPECTED[bpp]})")
        if bpp in VP9_EXPECTED:
            seen = tuple(got["vp9"][d][k] for d in ("8", "10"))
            if seen != VP9_EXPECTED[bpp]:
                misses.append(f"VP9 at {bpp}: {seen} (want {VP9_EXPECTED[bpp]})")
    check("P1", not misses, f"{len(SVT_EXPECTED)} SVT and {len(VP9_EXPECTED)} VP9 points; "
          + (f"misses {misses}" if misses else "every value the table's"))


# ---- the rate (R1–R3) --------------------------------------------------------------

def run_r_rows(app, logs):
    if not av1.OWNER.exists():
        for ident in ("R1", "R2", "R3"):
            print(f"{ident} skipped — the owner's fixture {av1.OWNER} is not here", flush=True)
        return
    out = WORK / "rate"
    av1.tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = av1.Instance("r", app)
    logs.append(instance)
    pixels = 1920 * 1080 * 30
    high = max(100_000, round(pixels * 0.129 * 0.6 / 100_000) * 100_000)
    cases = {"R1": (False, None, round(pixels * 0.07)), "R2": (False, high, high),
             "R3": (True, None, round(pixels * 0.07))}
    try:
        if instance.client is None:
            for ident in cases:
                check(ident, False, "the app did not listen")
            return
        for hdr in (False, True):
            doc = av1.Doc(instance, f"rate-{'hlg' if hdr else 'sdr'}", 1920, 1080)
            try:
                if hdr:
                    doc.call("set_canvas", output="hlg")
                doc.call("add_clip", track=doc.track(), media=doc.media(av1.OWNER), at=0)
                pix = "yuv420p10le" if hdr else "yuv420p"
                comparator = "hevc_10bit" if hdr else "hevc"
                reference = out / f"reference-{'hlg' if hdr else 'sdr'}.mov"
                try:
                    export(doc, reference, preset="prores_422")
                except mcp.ToolError as error:
                    for ident, case in cases.items():
                        if case[0] == hdr:
                            check(ident, False, f"the ProRes 422 reference failed: {error}")
                    continue
                for ident, (case_hdr, asked, cap) in cases.items():
                    if case_hdr != hdr:
                        continue
                    extra = {"video_bitrate": asked} if asked else {}
                    theirs = out / f"{ident}-{comparator}.mp4"
                    ours = out / f"{ident}-vp9.webm"
                    try:
                        export(doc, theirs, preset=comparator, **extra)
                        started = time.monotonic()
                        export(doc, ours, **extra)
                        took = time.monotonic() - started
                    except mcp.ToolError as error:
                        check(ident, False, f"an export failed: {error}")
                        continue
                    floor = vmaf(theirs, reference, out / f"{ident}-{comparator}.json", pix)
                    score = vmaf(ours, reference, out / f"{ident}-vp9.json", pix)
                    rate = video_rate(ours)
                    ok = (floor is not None and score is not None and score >= floor
                          and 0 < rate <= CAP_TOLERANCE * cap)
                    check(ident, ok, f"cap {cap} b/s ({'video_bitrate ' + str(asked) if asked else 'Format default'}"
                          f"{', hlg' if hdr else ''}); {comparator} "
                          f"{int(av1.video_stream(theirs).get('bit_rate') or 0)} b/s, VMAF "
                          f"{floor if floor is None else round(floor, 3)}; vp9_webm {rate} b/s "
                          f"({rate / cap:.3f} of the cap, ≤ {CAP_TOLERANCE}), VMAF "
                          f"{score if score is None else round(score, 3)} ({pix}), {took:.1f} s")
            finally:
                doc.close()
    finally:
        instance.stop()


# ---- the mutants -------------------------------------------------------------------

def run_mutant(name):
    if name not in MUTANTS:
        print(f"unknown mutant {name}; the mutants are {sorted(MUTANTS)}")
        return 2
    mutant = MUTANTS[name]
    named = list(mutant["rows"])
    print(f"mutant {name}: building the copy", flush=True)
    av1.MUTANTS = MUTANTS
    app, copy = av1.build_mutant(name)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {copy}")
        return 2
    cargo = mutant.get("cargo")
    if cargo:
        ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", cargo],
                          1200, cwd=str(copy / "core"))
        out = ran["stdout"] + ran["stderr"]
        if ran["expired"] or "test result:" not in out:
            print(f"mutant {name}: the control could not be performed — cargo rc {ran['rc']}: "
                  f"{out[-600:]}")
            return 2
        failed = re.findall(r"^test (\w+) \.\.\. FAILED$", out, re.M)
        check(f"cargo-{cargo}", ran["rc"] == 0, f"failed tests {failed}")
        named.append(f"cargo-{cargo}")
    logs = []
    try:
        run_rows(app, logs, probe=False)
    except Exception as error:  # an instrument that cannot run is the control's failure
        print(f"mutant {name}: the control could not be performed — {error}")
        return 2
    failing = sorted(k for k, v in results.items() if not v)
    print(f"mutant {name}: named {sorted(named)}, failing {failing}")
    if sorted(named) == failing:
        print(f"MUTANT CAUGHT: {name}")
        return 1
    if not set(named) & set(failing):
        print(f"MUTANT SURVIVED: {name}")
        return 0
    print(f"MUTANT CAUGHT, NOT EXACTLY: {name}")
    return 3


# ---- main --------------------------------------------------------------------------

def run_rows(app, logs, rate=False, probe=True):
    run_v_rows(app, logs)
    run_s1(app, logs)
    if probe:
        run_probe()
    if rate:
        run_r_rows(app, logs)
    found = [(i.label, line) for i in logs for line in i.complaints()]
    check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="the vp9_webm row (codec-export C4)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--rate", action="store_true", help="also R1–R3 (CX-16 (7))")
    parser.add_argument("--probe", action="store_true", help="P1 alone, no app")
    parser.add_argument("--mutant", help="one of " + ", ".join(MUTANTS))
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)
    if args.probe:
        run_probe()
        print(f"scores: {sum(results.values())}/{len(results)}")
        return 0 if all(results.values()) else 1
    logs = []
    try:
        app = proof_app.bundle()
        proof_app.require_fresh(proof_app.executable(app))
    except (proof_app.StaleApp, ValueError, OSError) as error:
        check("V0", False, f"the app cannot be driven: {error}")
        print("scores: 0/1")
        return 1
    print(f"app {app}", flush=True)
    run_rows(app, logs, rate=args.rate)
    passed = sum(results.values())
    print(f"scores: {passed}/{len(results)}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
