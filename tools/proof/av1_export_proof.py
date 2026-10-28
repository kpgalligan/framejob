#!/usr/bin/env python3
"""Road map "codec-export" C1 and C2 — the `av1` row: AV1 in MP4 through the bundled
SVT-AV1, 10-bit, with HLG, PQ and HDR10 in an HLG project (spec §11 CX-1, CX-2, CX-9,
CX-10, CX-12, CX-13, CX-14).

    python3 tools/proof/av1_export_proof.py [--app debug|release|PATH] [--rate]
    python3 tools/proof/av1_export_proof.py --mutant NAME

Launches its own instances of the chosen app (`proof_app.py`: `--app`, else
`RC_PROOF_APP`, else Debug; a build older than its inputs is refused) on scratch
sockets, works under `tools/proof/work/av1-export/`, closes every project it opens
with `discard: true` and stops each instance by its own PID. ffprobe and ffmpeg
(Homebrew, with libdav1d) only READ the files: this Mac has no AV1 decoder, so
nothing here imports or plays an AV1 file through Frame Job or AVFoundation.

Rows (`<ID> ok|FAIL — <detail>`, then `scores: n/m`; exit 0 iff all passed):

* Z1 — every instance's log is silent: no `Frame Job: ` line (the parity check),
  no `Svt[` line (SVT's own banner, which CX-12 (6) routes away) and no
  `SVT-AV1: ` line (a warning or error it passed on).
* A1 — `export {preset: av1}` of AV.mov (640 × 360, 30 fps, 5 s) under a text
  clip is done; ffprobe reads video `av1` / `av01` / Main / `yuv420p10le` /
  640 × 360 and audio `aac` / `mp4a`, and the video lasts 5.0 s ± one frame.
* A2 — the file's compatible brands include `av01`.
* A3a — the bitstream: `-bsf:v trace_headers`' every sequence header has
  `color_description_present_flag` 1, `color_primaries`, `transfer_characteristics`
  and `matrix_coefficients` 1/1/1 and `color_range` 0.
* A3b — the container: the `av01` sample entry's `colr` box, read from the MP4's
  own bytes (moov/trak/mdia/minf/stbl/stsd), is `nclx` 1/1/1 with full_range 0.
* A4 — `ffmpeg -v error` decodes the file with no error line, ffprobe's decoded
  frame count is the range's (150), and `trace_headers` shows no temporal
  delimiter OBU (type 2).
* A5 — A1's file: the first packet is a keyframe (K), the longest K-to-K gap is
  ≤ 2.0 s, the key count is ≤ ceil(duration / 2 s) + 1 with at least one packet
  that is not K, and through `trace_headers` every K packet's shown frame is a
  KEY_FRAME (`frame_type` 0 with `show_frame` 1) and no other packet's is, and
  no packet holds a hidden intra frame (`frame_type` 0 or 2 with `show_frame` 0:
  an open GOP's forward keyframe).
* A6 — a 1920 × 1080, 30 fps, 120 s project (AV.mov 24 times, filling the
  canvas) exported at Balanced, cancelled once its progress is above 0 while it
  encodes — after the loudness measurement's phase, whose progress is the bar's
  first share, so the cancel meets the encoder and not the measurement: the
  status reads `cancelled` within 10 s of `cancel_export`, and no file is at
  the path. (Uncancelled, its 3,600 frames take far longer than 10 s at
  SVT-AV1's ~41–148 fps at 1080p, `designs/codec-export.md`'s spike.)
* A7 — A1's project at each `encoder_speed` (faster, balanced, smaller): each
  done, its answer's `encoder_speed` the one asked, and the three files' sizes
  pairwise more than 1 % apart; `encoder_speed: "fast"` and `encoder_speed` on `h264`
  are each refused naming `encoder_speed`, and nothing is at either path.
* A8 — `size: [640, 480]` on the 640 × 360 canvas is 640 × 480 with the
  picture letterboxed (the top 56 rows' luma ≤ 20, the middle rows' mean above
  20, frame 0's Y plane); `size: "720p"` decodes at 1280 × 720.
* A9 — an in/out export of 1 s to 3 s holds 60 frames.
* H1 — A1's project made HLG (`set_canvas output "hlg"`, "the HLG doc"), `av1` with
  no `dynamic_range`: the answer's `dynamic_range` is `hlg`; ffprobe reads
  `yuv420p10le` / Main and the tags `bt2020nc/arib-std-b67/bt2020`; `trace_headers`'
  CICP is 9/18/9 with `color_range` 0; the `av01` entry's `colr` is `nclx` 9/18/9/0;
  the entry holds no `mdcv` or `clli` box; the stream carries no mastering or light
  level side data, and neither does frame 0 of the raw OBU stream copied out of the
  file (`-c:v copy -f obu`, no container to borrow from) decoded by libdav1d.
* H2 — the HLG doc at `pq`: the answer says `pq`; tags `bt2020nc/smpte2084/bt2020`,
  CICP 9/16/9, `colr` `nclx` 9/16/9/0. The container: the stream's side data is
  `hdr_proof.py`'s HDR10_SIDE strings, and the `av01` entry holds an `mdcv` and a
  `clli` box, `clli` (1000, 0). The bitstream: frame 0 of the raw OBU stream
  decoded by libdav1d carries a mastering display (each chromaticity within
  1/50000 of P3-D65's, max 1000 ± 1/256, min 0.005 ± 1/16384) and a content light
  level (MaxCLL 1000, MaxFALL 0).
* H3 — the HLG doc at `sdr`: the answer says `sdr`; `yuv420p10le`, bt709 × 3,
  CICP 1/1/1, `colr` `nclx` 1/1/1/0, no `mdcv`/`clli` box and no HDR10 side data.
* H4 — the code values against `hevc_10bit`, each export made as `av1` and as
  `hevc_10bit` at `video_bitrate` 20,000,000 and decoded by ffmpeg as
  `yuv420p10le`: (a) A1's SDR project and the HLG doc at hlg, pq and sdr, frames
  0–149, each plane's mean absolute difference ≤ 6 codes (twelve numbers); (b) a
  fixture made here, `WORK/stripes.mov` (640 × 360 ProRes 422 HQ, three 120-row
  stripes of 100 % red, green and blue, BT.709), alone in an SDR project exported
  at the default and in an HLG project at hlg and at pq: frame 30, each stripe's
  inner patch (luma rows 120k+30…120k+89 × columns 64…575, chroma rows
  60k+15…60k+44 × columns 32…287), |mean(av1) − mean(hevc_10bit)| ≤ 4 codes per
  plane (27 numbers). A failed export, decode or fixture fails H4.
* H5 — refused by sentence, no file left: `av1` `pq` in A1's SDR project
  (`dynamic_range "pq" needs an HLG project; set_canvas output "hlg" first`) and
  `h264` `hlg` in the HLG doc (`h264 is 8-bit and writes the SDR version; export
  dynamic_range "hlg" as hevc_10bit, av1, av1_webm, vp9_webm, prores_422 or prores_4444`).
* S1 — an instance pinned with `screens.py`'s PINS, `-RCDevAppearance light`
  and `FrameJobExportChoice` `{"preset_id":"av1","encoder_speed":"smaller"}`:
  File ▸ Export… shows Format "AV1 (MP4)", the popup after "Speed:" reads
  "Smaller file" and is drawn enabled, and the footnote is
  "AV1 · MP4 · Smaller file".
* S2 — the same pinned to `{"preset_id":"h264"}`: the Speed popup is drawn
  disabled. "Drawn enabled / disabled": the layout dump carries no enabled
  flag, so the popup's darkest pixel is compared with the Format popup's in
  the same light capture — within 40 levels is enabled, more than 60 lighter
  is disabled.
* S3 — as S1, pinned to `{"preset_id":"av1"}`, on an HLG project: the popup
  after "Dynamic Range:" reads "HDR (HLG)" and is drawn enabled by S1's rule.
* R1, R2 — only with `--rate` (CX-13's soft-capped CRF): the owner's full-length
  clip `tools/proof/media/owner-sync/IMG_0018.MOV` (1920 × 1080, 30 fps,
  55.27 s) exported once as `prores_422` (the reference), then, R1 at "Format
  default" (no `video_bitrate`: the cap is HEVC's 0.07 bits per pixel per
  frame) and R2 at the sheet's High tier (`video_bitrate` 0.129 × 0.6 to the
  nearest 100 kbps, asked of both), as `hevc_10bit` and as `av1` at each speed
  (CX-14 (6)): each `av1` file's video bit rate (ffprobe, the whole file's
  average) is at most 1.30 × the cap (CX-13's soft cap) and its VMAF against
  the reference (ffmpeg's libvmaf, both as 10-bit 4:2:0) is at or above the
  `hevc_10bit` file's.
  Prints each rate, its share of the cap, each VMAF and each encode's frames
  per second. A missing fixture skips R by name; a libvmaf that cannot run is
  a FAIL.

`--mutant NAME` builds a copy of the tree (`tree_copy.make_copy`; `core/` made
the copy's own for a core mutant, `hevc_alpha_proof.own_core`) with each of the
mutant's anchors replaced (each found exactly once), builds its app
(`tree_copy.build_app`), runs every row but R on it (and, for a core mutant,
its `cargo test` file in the copy's core), and exits 1 when exactly the named
rows fail (caught), 0 when none of them does (survived), 3 when they fail
with others beside them, and 2 when the control could not be performed (a
copy, an anchor, a build or a launch).

  td-kept                    the core's strip keeps every temporal delimiter:
                             A4 and `cargo test --test av1_mp4`
  brand-unpatched            the finished file is never branded: A2
  open-gop                   `SVT_AV1_FWDKF_REFRESH` (an open GOP): A5 (hidden
                             INTRA_ONLY frames, one key) and Z1 (SVT-AV1's warning
                             that it set hierarchical levels to 4 for it)
  speed-ignored              SVT's preset fixed at 6: A7
  encode-ignores-cancel      every `isStopping()` in `ExportEncodePump` removed: A6
  speed-on-any-row           the core takes `encoder_speed` on any row: A7 and
                             `cargo test --test export_av1`
  colour-untagged-bitstream  SVT's CICP left unset (the encoder's three
                             `picture.` lines): A3a, H1, H2, H3
  colour-untagged-container  the picture's extensions never merged into the
                             format description: A3b, H1, H2, H3
  av1-not-hdr                `av1` out of the core's HDR_ROWS: H1, H2, H4, S3 and
                             `cargo test --test dynamic_range`
  matrix-709-in-hdr          the HLG and PQ pictures' luma weights BT.709's: H4
  full-range-samples         the kernel's Y = round(1023·Y′), C = round(512 +
                             1023·C′): H4
  pq-tagged-hlg              SVT's transfer HLG on PQ: H2
  pq-no-container-metadata   the mastering and light-level extensions dropped
                             from PQ: H2
  pq-no-bitstream-metadata   SVT's two parse calls never made: H2
  metadata-on-hlg            `carriesHDR10` true for HLG: H1

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import atexit
import json
import math
import operator
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from array import array
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = HERE / "work" / "av1-export"
AV = HERE / "media" / "AV.mov"
OWNER = HERE / "media" / "owner-sync" / "IMG_0018.MOV"
SEC = 600_000
FRAMES = 150                     # AV.mov's 5 s at 30 fps
CANCEL_BOUND = 10.0
CAP_TOLERANCE = 1.30             # CX-13 (1): a soft cap; hard footage measured up to 1.254 ×
H4_RATE = 20_000_000
H4_FRAME_BOUND = 6               # H4 (a): each plane's mean absolute difference, in codes
H4_PATCH_BOUND = 4               # H4 (b): each patch's mean difference, in codes; fixed
# H2's bitstream reading: P3-D65 as SVT writes it (0.16 fixed point) within 1/50000.
MASTERING = {"red_x": 0.680, "red_y": 0.320, "green_x": 0.265, "green_y": 0.690,
             "blue_x": 0.150, "blue_y": 0.060, "white_point_x": 0.3127,
             "white_point_y": 0.3290}
REFUSED_SDR = "dynamic_range \"pq\" needs an HLG project; set_canvas output \"hlg\" first"
REFUSED_8BIT = ("h264 is 8-bit and writes the SDR version; export dynamic_range \"hlg\" as "
                "hevc_10bit, av1, av1_webm, vp9_webm, prores_422 or prores_4444")

ROWS = ["Z1", "A1", "A2", "A3a", "A3b", "A4", "A5", "A6", "A7", "A8", "A9", "H1", "H2", "H3",
        "H4", "H5", "S1", "S2", "S3"]

SOURCES = "app/Sources"
MUTANTS = {
    "td-kept": {"rows": ["A4"], "cargo": "av1_mp4", "anchors": [
        ("core/src/av1_mp4.rs", "        if obu.kind != OBU_TEMPORAL_DELIMITER {\n",
         "        if obu.kind != OBU_TEMPORAL_DELIMITER || obu.kind == OBU_TEMPORAL_DELIMITER {\n")]},
    "brand-unpatched": {"rows": ["A2"], "anchors": [
        (f"{SOURCES}/ExporterWriter.swift", "                try ExportAV1Track.brandFile(destination)\n",
         "                _ = destination\n")]},
    "open-gop": {"rows": ["A5", "Z1"], "anchors": [
        (f"{SOURCES}/ExportAV1Encoder.swift", "        config.intra_refresh_type = SVT_AV1_KF_REFRESH\n",
         "        config.intra_refresh_type = SVT_AV1_FWDKF_REFRESH\n")]},
    "speed-ignored": {"rows": ["A7"], "anchors": [
        (f"{SOURCES}/ExportAV1Encoder.swift", "        config.enc_mode = speed.svtPreset\n",
         "        config.enc_mode = 6\n")]},
    "encode-ignores-cancel": {"rows": ["A6"], "anchors": [
        (f"{SOURCES}/ExportEncodePump.swift", "                guard !isStopping() else { return finish(false) }\n",
         "                guard !false else { return finish(false) }\n"),
        (f"{SOURCES}/ExportEncodePump.swift",
         "        guard !finished, !encoderFailed, !isStopping(), let encoder else { return }\n",
         "        guard !finished, !encoderFailed, let encoder else { return }\n"),
        (f"{SOURCES}/ExportPacketSink.swift",
         "            guard !isStopping() else { return ExportPacketSinkStopped() }\n",
         "            guard !false else { return ExportPacketSinkStopped() }\n")]},
    "speed-on-any-row": {"rows": ["A7"], "cargo": "export_av1", "anchors": [
        ("core/src/export.rs",
         "        let speed = match (encoder_speed(overrides)?, preset.takes_encoder_speed()) {\n",
         "        let speed = match (encoder_speed(overrides)?, true) {\n")]},
    "colour-untagged-bitstream": {"rows": ["A3a", "H1", "H2", "H3"], "anchors": [
        (f"{SOURCES}/ExportAV1Encoder.swift",
         "        config.color_primaries = picture.primaries\n"
         "        config.transfer_characteristics = picture.transfer\n"
         "        config.matrix_coefficients = picture.matrix\n", "")]},
    "colour-untagged-container": {"rows": ["A3b", "H1", "H2", "H3"], "anchors": [
        (f"{SOURCES}/ExportAV1Track.swift",
         "        extensions.merge(picture.formatExtensions) { _, picture in picture }\n", "")]},
    "av1-not-hdr": {"rows": ["H1", "H2", "H4", "S3"], "cargo": "dynamic_range", "anchors": [
        ("core/src/dynamic_range.rs",
         'pub(crate) const HDR_ROWS: [&str; 6] = [\n    "hevc_10bit",\n    "av1",\n',
         'pub(crate) const HDR_ROWS: [&str; 5] = [\n    "hevc_10bit",\n')]},
    "matrix-709-in-hdr": {"rows": ["H4"], "anchors": [
        (f"{SOURCES}/ExportAV1Picture.swift",
         "        self == .sdr ? (0.2126, 0.0722) : (0.2627, 0.0593)\n",
         "        (0.2126, 0.0722)\n")]},
    "full-range-samples": {"rows": ["H4"], "anchors": [
        ("app/Resources/Shaders/ExportI010.metal",
         "            planes[at.y * u.lumaStride + at.x] = ushort(round(64.0 + 876.0 * luma));\n",
         "            planes[at.y * u.lumaStride + at.x] = ushort(round(1023.0 * luma));\n"),
        ("app/Resources/Shaders/ExportI010.metal",
         "    planes[u.cbOffset + chroma] = ushort(clamp(round(512.0 + 896.0 * cb / count), 0.0, "
         "1023.0));\n",
         "    planes[u.cbOffset + chroma] = ushort(clamp(round(512.0 + 1023.0 * cb / count), 0.0, "
         "1023.0));\n"),
        ("app/Resources/Shaders/ExportI010.metal",
         "    planes[u.crOffset + chroma] = ushort(clamp(round(512.0 + 896.0 * cr / count), 0.0, "
         "1023.0));\n",
         "    planes[u.crOffset + chroma] = ushort(clamp(round(512.0 + 1023.0 * cr / count), 0.0, "
         "1023.0));\n")]},
    "pq-tagged-hlg": {"rows": ["H2"], "anchors": [
        (f"{SOURCES}/ExportAV1Picture.swift", "        case .pq: return EB_CICP_TC_SMPTE_2084\n",
         "        case .pq: return EB_CICP_TC_HLG\n")]},
    "pq-no-container-metadata": {"rows": ["H2"], "anchors": [
        (f"{SOURCES}/ExportAV1Picture.swift", "        if carriesHDR10 {\n",
         "        if carriesHDR10 && false {\n")]},
    "pq-no-bitstream-metadata": {"rows": ["H2"], "anchors": [
        (f"{SOURCES}/ExportAV1Encoder.swift",
         "            if picture.carriesHDR10 {\n"
         "                try Self.setHDR10(&config)\n"
         "            }\n", "")]},
    "metadata-on-hlg": {"rows": ["H1"], "anchors": [
        (f"{SOURCES}/ExportAV1Picture.swift", "        self == .pq\n", "        self != .sdr\n")]},
}

results = {}


def check(ident, ok, detail):
    results[ident] = bool(ok)
    print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- reading the files (ffprobe, ffmpeg, the MP4's bytes) ------------------------

def run(argv, seconds=600):
    return bounded.run([str(a) for a in argv], seconds)


def streams(path):
    ran = run(["ffprobe", "-v", "error", "-show_entries",
               "stream=codec_type,codec_name,codec_tag_string,profile,pix_fmt,width,height,"
               "duration,bit_rate,nb_frames,time_base", "-of", "json", path])
    return json.loads(ran["stdout"] or "{}").get("streams", [])


def video_stream(path):
    return next((s for s in streams(path) if s.get("codec_type") == "video"), {})


def brands(path):
    ran = run(["ffprobe", "-v", "error", "-show_entries", "format_tags=compatible_brands",
               "-of", "json", path])
    return (json.loads(ran["stdout"] or "{}").get("format", {}).get("tags", {})
            .get("compatible_brands", ""))


def decoded_frames(path):
    ran = run(["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
               "-show_entries", "stream=nb_read_frames", "-of", "csv=p=0", path])
    try:
        return int(ran["stdout"].strip().split(",")[0])
    except ValueError:
        return None


def decode_errors(path):
    ran = run(["ffmpeg", "-hide_banner", "-v", "error", "-i", path, "-f", "null", "-"])
    return ran["rc"], [line for line in ran["stderr"].splitlines() if line.strip()]


def packets(path):
    """ffprobe's video packets: [(pts seconds, key)]."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "packet=pts_time,flags", "-of", "csv=p=0", path])
    out = []
    for line in ran["stdout"].splitlines():
        parts = line.strip().split(",")
        if len(parts) >= 2 and parts[0] not in ("", "N/A"):
            out.append((float(parts[0]), "K" in parts[1]))
    return out


def trace(path):
    """`trace_headers` over the video: (header fields before the first packet,
    [{"key": bool, "fields": [(name, value)]}] per packet)."""
    ran = run(["ffmpeg", "-hide_banner", "-v", "trace", "-i", path, "-map", "0:v:0", "-c",
               "copy", "-bsf:v", "trace_headers", "-f", "null", "-"])
    head, out = [], []
    for line in ran["stderr"].splitlines():
        if "[trace_headers" not in line or "] " not in line:
            continue
        body = line.split("] ", 1)[1]
        started = re.match(r"Packet: \d+ bytes, (key frame, )?pts", body)
        if started:
            out.append({"key": bool(started.group(1)), "fields": []})
            continue
        field = re.match(r"\d+\s+(\S+)\s+[01]+ = (-?\d+)$", body.strip())
        if field:
            (out[-1]["fields"] if out else head).append((field.group(1), int(field.group(2))))
    return head, out


def shows_key(fields):
    """Whether a packet's shown frame is a KEY_FRAME: a frame header with
    `frame_type` 0 and `show_frame` 1."""
    frame_type = None
    for name, value in fields:
        if name == "show_existing_frame":
            frame_type = None
        elif name == "frame_type":
            frame_type = value
        elif name == "show_frame" and value == 1 and frame_type == 0:
            return True
    return False


def hidden_intra(fields):
    """Whether a packet holds an intra frame that is not shown — a KEY_FRAME or an
    INTRA_ONLY frame (`frame_type` 0 or 2) with `show_frame` 0, shown later by
    `show_existing_frame`: an open GOP's forward keyframe, which SVT-AV1 v4.2.0
    writes as a hidden INTRA_ONLY frame."""
    frame_type = None
    for name, value in fields:
        if name == "show_existing_frame":
            frame_type = None
        elif name == "frame_type":
            frame_type = value
        elif name == "show_frame" and value == 0 and frame_type in (0, 2):
            return True
    return False


def y_plane(path, width, height, index=0):
    ran = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-vf",
                          f"select=eq(n\\,{index})", "-frames:v", "1", "-f", "rawvideo",
                          "-pix_fmt", "yuv420p", "-"], capture_output=True, timeout=120)
    data = ran.stdout
    return data[:width * height] if len(data) >= width * height else None


def boxes(data, start, end):
    at = start
    while at + 8 <= end:
        size, kind = struct.unpack(">I4s", data[at:at + 8])
        header = 8
        if size == 1:
            size, header = struct.unpack(">Q", data[at + 8:at + 16])[0], 16
        elif size == 0:
            size = end - at
        if size < header or at + size > end:
            return
        yield kind.decode("latin-1"), at + header, at + size
        at += size


def av01_children(path):
    """The `av01` sample entry's child boxes as [(type, body bytes)], or None when the
    file has no `av01` entry, read from the file's bytes."""
    data = Path(path).read_bytes()

    def find(start, end, chain):
        for kind, body, stop in boxes(data, start, end):
            if kind != chain[0]:
                continue
            if len(chain) == 1:
                return body, stop
            if kind == "stsd":
                body += 8            # version, flags, entry count
            found = find(body, stop, chain[1:])
            if found:
                return found
        return None

    for _, trak, trak_end in [b for b in boxes(data, 0, len(data)) if b[0] == "moov"]:
        for kind, body, stop in boxes(data, trak, trak_end):
            if kind != "trak":
                continue
            entry = find(body, stop, ["mdia", "minf", "stbl", "stsd", "av01"])
            if not entry:
                continue
            # VisualSampleEntry: 6 reserved + 2 index + 16 pre_defined/reserved + 4 size
            # + 8 resolution + 4 reserved + 2 frame count + 32 compressor + 2 depth + 2 -1.
            return [(child, data[cbody:cstop])
                    for child, cbody, cstop in boxes(data, entry[0] + 78, entry[1])]
    return None


def colr_of(path):
    """The `av01` sample entry's `colr` box: (type, primaries, transfer, matrix,
    full_range) or None, read from the file's bytes."""
    for child, body in av01_children(path) or []:
        if child == "colr" and body[:4] == b"nclx" and len(body) >= 11:
            p, t, m = struct.unpack(">HHH", body[4:10])
            return ("nclx", p, t, m, body[10] >> 7)
    return None


def hdr_boxes(path):
    """(the `av01` entry's child box types, `clli`'s body as (MaxCLL, MaxFALL) or None);
    None when the file has no `av01` entry."""
    children = av01_children(path)
    if children is None:
        return None
    clli = next((struct.unpack(">HH", body[:4]) for kind, body in children
                 if kind == "clli" and len(body) >= 4), None)
    return [kind for kind, _ in children], clli


def obu_of(path):
    """The video copied out of `path` as a raw OBU stream (`<path>.obu`), which has no
    container to borrow side data from; None when ffmpeg could not."""
    obu = Path(f"{path}.obu")
    obu.unlink(missing_ok=True)
    ran = run(["ffmpeg", "-v", "error", "-i", path, "-map", "0:v:0", "-c:v", "copy", "-f",
               "obu", obu])
    return obu if ran["rc"] == 0 and obu.exists() and obu.stat().st_size > 0 else None


def side_pairs(text):
    """`key=value` lines of ffprobe's default output, and the side data types named."""
    pairs, kinds = {}, []
    for line in text.splitlines():
        key, _, value = line.strip().partition("=")
        if key == "side_data_type":
            kinds.append(value)
        elif value and key not in pairs:
            pairs[key] = value
    return pairs, kinds


def stream_side(path):
    """The video stream's side data (the container's `mdcv`/`clli` as ffprobe reads them):
    (pairs, types) or None when ffprobe failed."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "stream_side_data_list", path])
    return side_pairs(ran["stdout"]) if ran["rc"] == 0 else None


def bitstream_side(obu):
    """Frame 0 of a raw OBU stream decoded by libdav1d: its side data as (pairs, types),
    or None when no frame was decoded."""
    ran = run(["ffprobe", "-v", "error", "-c:v", "libdav1d", "-read_intervals", "%+#1",
               "-show_frames", "-show_entries", "frame=pix_fmt,side_data_list", obu])
    text = ran["stdout"]
    if ran["rc"] != 0 or "[FRAME]" not in text:
        return None
    return side_pairs(text.split("[FRAME]", 1)[1].split("[/FRAME]", 1)[0])


def colour_tags(path):
    ran = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "stream=pix_fmt,profile,color_space,color_transfer,color_primaries", "-of",
               "json", path])
    got = (json.loads(ran["stdout"] or "{}").get("streams") or [{}])[0]
    return (got.get("pix_fmt"), got.get("profile"),
            f"{got.get('color_space')}/{got.get('color_transfer')}/{got.get('color_primaries')}")


def cicp_of(path):
    """Every value `trace_headers` reads for the sequence headers' colour fields."""
    head, per_packet = trace(path)
    every = head + [f for p in per_packet for f in p["fields"]]
    names = ("color_description_present_flag", "color_primaries", "transfer_characteristics",
             "matrix_coefficients", "color_range")
    return {n: sorted({v for k, v in every if k == n}) for n in names}


def fraction(text):
    try:
        top, _, bottom = text.partition("/")
        return float(top) / float(bottom or 1)
    except (ValueError, ZeroDivisionError, AttributeError):
        return None


# ---- the instance ----------------------------------------------------------------

class Instance:
    def __init__(self, label, app, arguments=(), env=None, home=False):
        self.label = label
        self.dir = WORK / label
        tree_copy.remove_tree(str(self.dir))
        self.dir.mkdir(parents=True)
        self.log = self.dir / "instance.log"
        if home:
            (self.dir / "home").mkdir()
            env = {**(env or {}), "CFFIXED_USER_HOME": str(self.dir / "home")}
        self.launched = mcp.launch(str(proof_app.executable(app)), list(arguments),
                                   env=bounded.child_env(env or {}), log_path=str(self.log),
                                   timeout=900)
        self.client = self.launched.client

    def stop(self):
        self.launched.stop()
        mcp.remove_scratch(self.launched.socket_path)

    def complaints(self):
        try:
            lines = self.log.read_text(errors="replace").splitlines()
        except OSError:
            return ["the log could not be read"]
        return [line.strip() for line in lines
                if "Frame Job: " in line or "Svt[" in line or "SVT-AV1: " in line]


class Doc:
    def __init__(self, instance, name, width=640, height=360):
        self.client = instance.client
        self.path = str(instance.dir / f"{name}.framejob")
        self.client.call("new_project", path=self.path)
        try:
            self.call("set_canvas", width=width, height=height, fps=30)
        except mcp.ToolError as error:
            if "made no change" not in str(error):    # a new project is 1920 × 1080 at 30
                raise

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": self.path, **arguments})

    def track(self):
        return self.call("get_project")["project"]["tracks"][0]["id"]

    def media(self, path):
        return self.call("import_media", path=str(path))["media"]

    def close(self):
        try:
            self.call("close_project", discard=True)
        except mcp.ToolError:
            pass


def av_doc(instance, name):
    """AV.mov from 0 under a two-second text clip on a track of its own."""
    doc = Doc(instance, name)
    media = doc.media(AV)
    doc.call("add_clip", track=doc.track(), media=media, at=0)
    doc.call("add_track", name="Titles")
    titles = doc.call("get_project")["project"]["tracks"][-1]["id"]
    doc.call("add_text_clip", track=titles, at=0, duration=2 * SEC, text={"content": "AV1"})
    return doc


def export(doc, path, **arguments):
    Path(path).unlink(missing_ok=True)
    return doc.client.export_with({"project": doc.path, "path": str(path), **arguments})


def refusal(doc, path, **arguments):
    Path(path).unlink(missing_ok=True)
    try:
        answer = doc.client.call_with("export", {"project": doc.path, "path": str(path),
                                                 **arguments})
    except mcp.ToolError as error:
        return str(error)
    if isinstance(answer, dict) and "export_id" in answer:
        try:
            doc.client.wait_export(answer["export_id"], seconds=300)
        except mcp.ToolError:
            pass
    return None


# ---- the rows --------------------------------------------------------------------

def rows_a1_a5(doc, out):
    a1 = out / "a1.mp4"
    try:
        done = export(doc, a1, preset="av1")
    except mcp.ToolError as error:
        for ident in ("A1", "A2", "A3a", "A3b", "A4", "A5"):
            check(ident, False, f"A1's export failed: {error}")
        return
    got = streams(a1)
    video = next((s for s in got if s.get("codec_type") == "video"), {})
    audio = next((s for s in got if s.get("codec_type") == "audio"), {})
    seen = (video.get("codec_name"), video.get("codec_tag_string"), video.get("profile"),
            video.get("pix_fmt"), video.get("width"), video.get("height"),
            audio.get("codec_name"), audio.get("codec_tag_string"))
    want = ("av1", "av01", "Main", "yuv420p10le", 640, 360, "aac", "mp4a")
    length = float(video.get("duration") or 0)
    check("A1", done.get("status") == "done" and seen == want and abs(length - 5) <= 1 / 30,
          f"status {done.get('status')}, {done.get('bytes')} bytes; read {seen} (want {want}); "
          f"video {length:.3f} s")
    found = brands(a1)
    check("A2", "av01" in found, f"compatible brands {found!r}")

    head, per_packet = trace(a1)
    every = head + [f for p in per_packet for f in p["fields"]]
    names = ("color_description_present_flag", "color_primaries", "transfer_characteristics",
             "matrix_coefficients", "color_range")
    values = {n: sorted({v for k, v in every if k == n}) for n in names}
    check("A3a", values == {names[0]: [1], names[1]: [1], names[2]: [1], names[3]: [1],
                            names[4]: [0]},
          f"the sequence headers' {values}")
    colr = colr_of(a1)
    check("A3b", colr == ("nclx", 1, 1, 1, 0), f"the av01 entry's colr {colr}")

    rc, errors = decode_errors(a1)
    count = decoded_frames(a1)
    tds = [v for k, v in every if k == "obu_type" and v == 2]
    check("A4", rc == 0 and not errors and count == FRAMES and not tds,
          f"ffmpeg rc {rc}, {len(errors)} error lines {errors[:2]}; {count} frames decoded "
          f"(want {FRAMES}); {len(tds)} temporal delimiters in {len(per_packet)} packets")

    listed = packets(a1)
    keys = [t for t, k in listed if k]
    gaps = [b - a for a, b in zip(keys, keys[1:])] + ([length - keys[-1]] if keys else [])
    bound = math.ceil(length / 2) + 1
    mismatched = [i for i, p in enumerate(per_packet) if p["key"] != shows_key(p["fields"])]
    hidden = [i for i, p in enumerate(per_packet) if hidden_intra(p["fields"])]
    ok = (len(listed) == len(per_packet) and listed and listed[0][1] and gaps
          and max(gaps) <= 2.0 + 1e-6 and len(keys) <= bound and len(keys) < len(listed)
          and not mismatched and not hidden)
    check("A5", ok, f"{len(listed)} packets ({len(per_packet)} traced), keys at {keys}; "
          f"longest K-to-K gap {max(gaps) if gaps else None} s (≤ 2.0); {len(keys)} keys "
          f"(≤ {bound}), {len(listed) - len(keys)} not; K flag ≠ shown KEY_FRAME at "
          f"{mismatched[:6]}; hidden intra frames at {hidden[:6]}")


def row_a6(instance, out):
    path = out / "a6.mp4"
    path.unlink(missing_ok=True)
    detail = ""
    ok = False
    doc = None
    try:
        doc = Doc(instance, "a6", 1920, 1080)
        media = doc.media(AV)
        track = doc.track()
        for k in range(24):
            doc.call("add_clip", track=track, media=media, at=k * 5 * SEC)
        clips = [c["id"] for c in doc.call("get_project")["project"]["clips"]]
        doc.call("set_video", clips=clips, patch={"scale": 3.0})
        length = doc.call("get_project")["project"]
        started = doc.client.call_with("export", {"project": doc.path, "path": str(path),
                                                  "preset": "av1", "encoder_speed": "balanced"})
        job = started["export_id"]
        # The export measures its sound first (the "Measuring loudness…" phase, whose
        # progress is the bar's first share, and the bar is put at that share's end when
        # the writer starts); the cancel must land while SVT-AV1 encodes, so it waits for
        # the phase to end and then for the bar to move past where the writer started it.
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
            detail = (f"cancelled while encoding, at progress {progress:.4f} (the measurement "
                      f"ended at {measured}, the writer started at {floor}); status {final.get('status')!r} "
                      f"{took:.2f} s after cancel_export (≤ {CANCEL_BOUND}); a file at the "
                      f"path: {exists}; the project {len(clips)} clips, "
                      f"{length['canvas']['width']} × {length['canvas']['height']}")
    except (mcp.ToolError, KeyError) as error:
        detail = f"{type(error).__name__}: {error}"
    finally:
        if doc is not None:
            doc.close()
    check("A6", ok, detail)


def row_a7(doc, out, a1_bytes):
    sizes, lines, ok = {}, [], True
    for speed in ("faster", "balanced", "smaller"):
        path = out / f"a7-{speed}.mp4"
        started = time.monotonic()
        try:
            done = export(doc, path, preset="av1", encoder_speed=speed)
        except mcp.ToolError as error:
            ok = False
            lines.append(f"{speed}: {error}")
            continue
        sizes[speed] = done.get("bytes")
        good = done.get("status") == "done" and done.get("encoder_speed") == speed
        ok = ok and good
        lines.append(f"{speed}: {done.get('status')}, echoed {done.get('encoder_speed')!r}, "
                     f"{done.get('bytes')} bytes, {time.monotonic() - started:.1f} s")
    # Pairwise more than 1 % apart: SVT-AV1's threads make two encodes of one
    # project at one speed differ by a few bytes (A1 against A7's balanced, printed),
    # so "different" alone would pass with the speed ignored.
    values = [v or 0 for v in sizes.values()]
    distinct = len(values) == 3 and all(
        abs(a - b) > 0.01 * max(a, b) for i, a in enumerate(values) for b in values[i + 1:])
    noise = (abs(sizes["balanced"] - a1_bytes) if a1_bytes and sizes.get("balanced")
             else None)
    bad = refusal(doc, out / "a7-fast.mp4", preset="av1", encoder_speed="fast")
    other = refusal(doc, out / "a7-h264.mp4", preset="h264", encoder_speed="faster")
    left = [p.name for p in (out / "a7-fast.mp4", out / "a7-h264.mp4") if p.exists()]
    refused = (bad is not None and "encoder_speed" in bad and other is not None
               and "encoder_speed" in other and not left)
    check("A7", ok and distinct and refused,
          "; ".join(lines) + f"; sizes pairwise more than 1 % apart {distinct} (A1's balanced "
          f"encode of the same project differs from this one by {noise} bytes); "
          f"\"fast\" → {bad!r}; "
          f"h264 → {other!r}; files left {left}")


def row_a8(doc, out):
    box = out / "a8-box.mp4"
    hd = out / "a8-720p.mp4"
    detail, ok = "", False
    try:
        export(doc, box, preset="av1", size=[640, 480])
        export(doc, hd, preset="av1", size="720p")
        video = video_stream(box)
        plane = y_plane(box, 640, 480)
        top = max(plane[:640 * 56]) if plane else None
        middle = (sum(plane[640 * 200:640 * 280]) / (640 * 80)) if plane else None
        wide = video_stream(hd)
        rc, errors = decode_errors(hd)
        ok = ((video.get("width"), video.get("height")) == (640, 480) and top is not None
              and top <= 20 and middle > 20
              and (wide.get("width"), wide.get("height")) == (1280, 720) and rc == 0
              and not errors)
        detail = (f"[640, 480]: {video.get('width')} × {video.get('height')}, the top 56 rows' "
                  f"highest luma {top} (≤ 20), the middle rows' mean "
                  f"{middle if middle is None else round(middle, 1)} (> 20); 720p: "
                  f"{wide.get('width')} × {wide.get('height')}, decode rc {rc} {errors[:2]}")
    except mcp.ToolError as error:
        detail = str(error)
    check("A8", ok, detail)


def row_a9(doc, out):
    path = out / "a9.mp4"
    try:
        doc.call("set_range", start=1 * SEC, end=3 * SEC)
        export(doc, path, preset="av1", range="in_out")
        count = decoded_frames(path)
        check("A9", count == 60, f"{count} frames decoded from the 1 s – 3 s export (want 60)")
    except mcp.ToolError as error:
        check("A9", False, str(error))


def run_a_rows(app, logs):
    out = WORK / "out"
    tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = Instance("a", app)
    logs.append(instance)
    try:
        if instance.client is None:
            for ident in ("A1", "A2", "A3a", "A3b", "A4", "A5", "A6", "A7", "A8", "A9"):
                check(ident, False, f"the app did not listen ({instance.log})")
            return
        try:
            doc = av_doc(instance, "a1")
        except (mcp.ToolError, KeyError, IndexError) as error:
            for ident in ("A1", "A2", "A3a", "A3b", "A4", "A5", "A7", "A8", "A9"):
                check(ident, False, f"A1's project could not be made: {error}")
            doc = None
        try:
            if doc is not None:
                rows_a1_a5(doc, out)
                a1 = out / "a1.mp4"
                row_a7(doc, out, a1.stat().st_size if a1.exists() else None)
                row_a8(doc, out)
                row_a9(doc, out)
        finally:
            if doc is not None:
                doc.close()
        row_a6(instance, out)
    finally:
        instance.stop()


# ---- HDR (CX-14) -----------------------------------------------------------------

def hlg_doc(instance, name):
    """A1's project made an HLG project ("the HLG doc")."""
    doc = av_doc(instance, name)
    doc.call("set_canvas", output="hlg")
    return doc


def hdr10_misses(stream, boxes_seen, frame):
    """What H2's container and bitstream readings lack of HD-5's HDR10 metadata."""
    misses = []
    try:
        from hdr_proof import HDR10_SIDE
    except ImportError as error:
        return [f"hdr_proof's HDR10_SIDE could not be read: {error}"]
    pairs = stream[0] if stream else {}
    seen = {k: pairs.get(k) for k in HDR10_SIDE}
    if seen != HDR10_SIDE:
        misses.append(f"stream side data {seen}")
    types, clli = boxes_seen or ([], None)
    if "mdcv" not in types or "clli" not in types or clli != (1000, 0):
        misses.append(f"av01 children {types}, clli {clli}")
    if frame is None:
        return misses + ["the OBU stream's frame 0 could not be decoded"]
    values, kinds = frame
    off = {k: values.get(k) for k, want in MASTERING.items()
           if fraction(values.get(k)) is None or abs(fraction(values[k]) - want) > 1 / 50000}
    peak, floor = fraction(values.get("max_luminance")), fraction(values.get("min_luminance"))
    if (off or peak is None or abs(peak - 1000) > 1 / 256 or floor is None
            or abs(floor - 0.005) > 1 / 16384 or values.get("max_content") != "1000"
            or values.get("max_average") != "0"
            or "Mastering display metadata" not in kinds
            or "Content light level metadata" not in kinds):
        misses.append(f"the bitstream's frame 0: {kinds}, off {off}, max {values.get('max_luminance')}, "
                      f"min {values.get('min_luminance')}, MaxCLL {values.get('max_content')}, "
                      f"MaxFALL {values.get('max_average')}")
    return misses


def row_picture(ident, doc, out, asked, cicp, tags, hdr10):
    """H1–H3: one `av1` export of the HLG doc, its tags in both places and its HDR10."""
    path = out / f"{ident.lower()}.mp4"
    try:
        done = export(doc, path, preset="av1",
                      **({} if asked is None else {"dynamic_range": asked}))
    except mcp.ToolError as error:
        check(ident, False, f"the export failed: {error}")
        return
    want = asked or "hlg"
    misses = []
    said = done.get("dynamic_range")
    if done.get("status") != "done" or said != want:
        misses.append(f"status {done.get('status')}, dynamic_range {said!r}")
    pix, profile, seen_tags = colour_tags(path)
    if (pix, profile, seen_tags) != ("yuv420p10le", "Main", tags):
        misses.append(f"read {pix} / {profile} / {seen_tags}")
    values = cicp_of(path)
    want_cicp = {"color_description_present_flag": [1], "color_primaries": [cicp[0]],
                 "transfer_characteristics": [cicp[1]], "matrix_coefficients": [cicp[2]],
                 "color_range": [0]}
    if values != want_cicp:
        misses.append(f"CICP {values}")
    colr = colr_of(path)
    if colr != ("nclx", *cicp, 0):
        misses.append(f"colr {colr}")
    boxes_seen = hdr_boxes(path)
    stream = stream_side(path)
    obu = obu_of(path)
    frame = bitstream_side(obu) if obu else None
    if boxes_seen is None or stream is None:
        misses.append(f"the container could not be read: boxes {boxes_seen}, side {stream}")
    elif hdr10:
        misses += hdr10_misses(stream, boxes_seen, frame)
    else:
        hdr_kinds = {"Mastering display metadata", "Content light level metadata"}
        types = boxes_seen[0]
        if "mdcv" in types or "clli" in types or hdr_kinds & set(stream[1]):
            misses.append(f"av01 children {types}, stream side data {stream[1]}")
        if frame is None:
            misses.append("the OBU stream's frame 0 could not be decoded")
        elif hdr_kinds & set(frame[1]):
            misses.append(f"the bitstream's frame 0 carries {frame[1]}")
    check(ident, not misses,
          f"answer {said!r} (want {want!r}); {pix} / {profile} / {seen_tags}; CICP "
          f"{[v for v in values.values()]}; colr {colr}; av01 children "
          f"{boxes_seen and boxes_seen[0]}, clli {boxes_seen and boxes_seen[1]}; stream side "
          f"data {stream and stream[1]}; the OBU stream's frame 0 {frame and frame[1]}"
          + (f"; misses {misses}" if misses else ""))


def plane_spans(width, height):
    """Each plane's (start, end) in one yuv420p10le frame, in samples, and the frame's."""
    luma = width * height
    chroma = ((width + 1) // 2) * ((height + 1) // 2)
    return [(0, luma), (luma, luma + chroma), (luma + chroma, luma + 2 * chroma)], \
        luma + 2 * chroma


def samples(data):
    """yuv420p10le bytes as 16-bit samples."""
    out = array("H")
    out.frombytes(data)
    if sys.byteorder != "little":
        out.byteswap()
    return out


def decode10(path, frames=None, index=None):
    """The video decoded by ffmpeg as yuv420p10le, frames 0…frames−1 or frame `index`;
    None when ffmpeg failed."""
    argv = ["ffmpeg", "-v", "error", "-i", str(path)]
    argv += (["-vf", f"select=eq(n\\,{index})", "-frames:v", "1"] if index is not None
             else ["-frames:v", str(frames)])
    try:
        ran = subprocess.run(argv + ["-f", "rawvideo", "-pix_fmt", "yuv420p10le", "-"],
                             capture_output=True, timeout=600)
    except subprocess.TimeoutExpired:
        return None
    return ran.stdout if ran.returncode == 0 and ran.stdout else None


def frame_differences(a, b, width, height, frames):
    """Each plane's mean absolute difference over `frames` frames, or None when either
    decode is short."""
    spans, per = plane_spans(width, height)
    one, two = samples(a), samples(b)
    if len(one) != per * frames or len(two) != per * frames:
        return None
    totals = [0, 0, 0]
    for f in range(frames):
        base = f * per
        for k, (start, end) in enumerate(spans):
            totals[k] += sum(map(abs, map(operator.sub, one[base + start:base + end],
                                          two[base + start:base + end])))
    return [totals[k] / ((end - start) * frames) for k, (start, end) in enumerate(spans)]


def patch_means(data, width, height, stripe):
    """Stripe `stripe`'s inner patch: each plane's mean, or None when the decode is short."""
    spans, per = plane_spans(width, height)
    values = samples(data)
    if len(values) != per:
        return None
    half = (width + 1) // 2

    def mean(start, stride, rows, cols):
        total = sum(sum(values[start + r * stride + cols[0]:start + r * stride + cols[1] + 1])
                    for r in range(rows[0], rows[1] + 1))
        return total / ((rows[1] - rows[0] + 1) * (cols[1] - cols[0] + 1))

    return [mean(0, width, (120 * stripe + 30, 120 * stripe + 89), (64, 575)),
            mean(spans[1][0], half, (60 * stripe + 15, 60 * stripe + 44), (32, 287)),
            mean(spans[2][0], half, (60 * stripe + 15, 60 * stripe + 44), (32, 287))]


def stripes_fixture():
    """WORK/stripes.mov: 640 × 360, three 120-row stripes of 100 % red, green and blue,
    ProRes 422 HQ tagged BT.709; None when ffmpeg failed."""
    path = WORK / "stripes.mov"
    path.unlink(missing_ok=True)
    ran = run(["ffmpeg", "-y", "-f", "lavfi", "-i", "color=c=0xFF0000:s=640x120:r=30:d=5",
               "-f", "lavfi", "-i", "color=c=0x00FF00:s=640x120:r=30:d=5", "-f", "lavfi",
               "-i", "color=c=0x0000FF:s=640x120:r=30:d=5", "-filter_complex",
               "[0][1][2]vstack=inputs=3,scale=out_color_matrix=bt709:out_range=tv,"
               "format=yuv422p10le", "-c:v", "prores_ks", "-profile:v", "3",
               "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709", path])
    return path if ran["rc"] == 0 and path.exists() else None


def row_h4(instance, sdr, hlg, out):
    """H4: av1's code values against hevc_10bit's, whole frames and saturated patches."""
    lines, ok = [], True
    stripes_docs = []
    try:
        for label, doc, extra in (("SDR project", sdr, {}),
                                  ("hlg", hlg, {"dynamic_range": "hlg"}),
                                  ("pq", hlg, {"dynamic_range": "pq"}),
                                  ("sdr", hlg, {"dynamic_range": "sdr"})):
            decoded = {}
            for preset in ("av1", "hevc_10bit"):
                path = out / f"h4a-{label.replace(' ', '-')}-{preset}.mp4"
                export(doc, path, preset=preset, video_bitrate=H4_RATE, **extra)
                decoded[preset] = decode10(path, frames=FRAMES)
            diffs = (frame_differences(decoded["av1"], decoded["hevc_10bit"], 640, 360, FRAMES)
                     if decoded["av1"] and decoded["hevc_10bit"] else None)
            good = diffs is not None and all(d <= H4_FRAME_BOUND for d in diffs)
            ok = ok and good
            lines.append(f"(a) {label}: Y/Cb/Cr "
                         + ("decode failed" if diffs is None
                            else "/".join(f"{d:.3f}" for d in diffs)) + ("" if good else " ✗"))
        fixture = stripes_fixture()
        if fixture is None:
            check("H4", False, "; ".join(lines) + "; the stripes fixture could not be made")
            return
        cases = []
        for name, hdr in (("stripes-sdr", False), ("stripes-hlg", True)):
            doc = Doc(instance, name)
            stripes_docs.append(doc)
            if hdr:
                doc.call("set_canvas", output="hlg")
            doc.call("add_clip", track=doc.track(), media=doc.media(fixture), at=0)
            cases += ([("sdr", doc, {})] if not hdr else
                      [("hlg", doc, {"dynamic_range": "hlg"}),
                       ("pq", doc, {"dynamic_range": "pq"})])
        for label, doc, extra in cases:
            decoded = {}
            for preset in ("av1", "hevc_10bit"):
                path = out / f"h4b-{label}-{preset}.mp4"
                export(doc, path, preset=preset, video_bitrate=H4_RATE, **extra)
                decoded[preset] = decode10(path, index=30)
            for stripe, colour in enumerate(("red", "green", "blue")):
                means = {preset: patch_means(data, 640, 360, stripe) if data else None
                         for preset, data in decoded.items()}
                if means["av1"] is None or means["hevc_10bit"] is None:
                    ok = False
                    lines.append(f"(b) {label} {colour}: decode failed ✗")
                    continue
                parts = []
                for plane, a, b in zip(("Y", "Cb", "Cr"), means["av1"], means["hevc_10bit"]):
                    good = abs(a - b) <= H4_PATCH_BOUND
                    ok = ok and good
                    parts.append(f"{plane} {a:.2f}/{b:.2f} ({a - b:+.2f})" + ("" if good else " ✗"))
                lines.append(f"(b) {label} {colour}: " + ", ".join(parts))
    except (mcp.ToolError, KeyError, IndexError, OSError) as error:
        ok = False
        lines.append(f"{type(error).__name__}: {error}")
    finally:
        for doc in stripes_docs:
            doc.close()
    check("H4", ok, f"av1 against hevc_10bit at {H4_RATE} b/s, (a) each plane's mean absolute "
          f"difference ≤ {H4_FRAME_BOUND} over frames 0–{FRAMES - 1}, (b) av1/hevc_10bit patch "
          f"means at frame 30, each within {H4_PATCH_BOUND}: " + "; ".join(lines))


def row_h5(sdr, hlg, out):
    pq_path, h264_path = out / "h5-pq.mp4", out / "h5-h264.mp4"
    one = refusal(sdr, pq_path, preset="av1", dynamic_range="pq")
    two = refusal(hlg, h264_path, preset="h264", dynamic_range="hlg")
    left = [p.name for p in (pq_path, h264_path) if p.exists()]
    check("H5", one is not None and REFUSED_SDR in one and two is not None
          and REFUSED_8BIT in two and not left,
          f"av1 pq in an SDR project → {one!r}; h264 hlg in an HLG project → {two!r}; files "
          f"left {left}")


def run_h_rows(app, logs):
    out = WORK / "hdr"
    tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = Instance("h", app)
    logs.append(instance)
    idents = ("H1", "H2", "H3", "H4", "H5")
    try:
        if instance.client is None:
            for ident in idents:
                check(ident, False, f"the app did not listen ({instance.log})")
            return
        docs = []
        try:
            sdr = av_doc(instance, "h-sdr")
            docs.append(sdr)
            hlg = hlg_doc(instance, "h-hlg")
            docs.append(hlg)
        except (mcp.ToolError, KeyError, IndexError) as error:
            for ident in idents:
                check(ident, False, f"the projects could not be made: {error}")
            for doc in docs:
                doc.close()
            return
        try:
            row_picture("H1", hlg, out, None, (9, 18, 9), "bt2020nc/arib-std-b67/bt2020", False)
            row_picture("H2", hlg, out, "pq", (9, 16, 9), "bt2020nc/smpte2084/bt2020", True)
            row_picture("H3", hlg, out, "sdr", (1, 1, 1), "bt709/bt709/bt709", False)
            row_h4(instance, sdr, hlg, out)
            row_h5(sdr, hlg, out)
        finally:
            for doc in docs:
                doc.close()
    finally:
        instance.stop()


# ---- the sheet -------------------------------------------------------------------

def popup_darkest(png, views, scale, popup):
    """The darkest luma inside `popup`'s frame in the capture, through ffmpeg."""
    ran = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=width,height",
                          "-of", "csv=p=0", str(png)], capture_output=True, text=True)
    width, height = (int(x) for x in ran.stdout.strip().split(",")[:2])
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(png), "-f", "rawvideo",
                          "-pix_fmt", "gray", "-"], capture_output=True).stdout
    x0, y0, w, h = (round(c * scale) for c in popup["frame"])
    pixels = [raw[y * width + x] for y in range(max(0, y0), min(height, y0 + h))
              for x in range(max(0, x0), min(width, x0 + w))]
    return min(pixels) if pixels else None


def sheet_reading(app, label, choice, hlg=False):
    """One pinned instance: File ▸ Export… on a project (an HLG one when `hlg`), the sheet
    read and cancelled."""
    from screens import PINS
    arguments = ["-RCDevAppearance", "light"]
    for key, value in PINS:
        arguments += [f"-{key}", f"<string>{choice}</string>"
                      if key == "FrameJobExportChoice" else value]
    instance = Instance(label, app, arguments, home=True)
    reading = {"instance": instance}
    try:
        if instance.client is None:
            reading["error"] = "the app did not listen"
            return reading
        doc = hlg_doc(instance, "sheet") if hlg else av_doc(instance, "sheet")
        png = instance.dir / "sheet.png"
        try:
            doc.call("perform_menu_item", path=["File", "Export…"])
            try:
                got = doc.call("snapshot_ui", window="sheet", path=str(png))
            finally:
                doc.call("cancel_sheet")
            dump = json.loads(Path(got["layout_path"]).read_text())
        finally:
            doc.close()
        views = [v for v in dump.get("views", []) if not v.get("hidden")]
        scale = dump.get("scale", 2)

        def popup_after(label_text):
            at = next((v["i"] for v in views if v.get("text") == label_text), None)
            return next((v for v in views if at is not None and v["i"] > at
                         and v.get("class") == "NSPopUpButton"), None)

        speed, fmt = popup_after("Speed:"), popup_after("Format:")
        dynamic = popup_after("Dynamic Range:")
        reading.update({
            "format": fmt and fmt.get("text"), "speed": speed and speed.get("text"),
            "range": dynamic and dynamic.get("text"),
            "range_dark": dynamic and popup_darkest(png, views, scale, dynamic),
            "footnote": [v["text"] for v in views
                         if v.get("text") and v.get("tooltip") == v["text"]],
            "speed_dark": speed and popup_darkest(png, views, scale, speed),
            "format_dark": fmt and popup_darkest(png, views, scale, fmt)})
    except (mcp.ToolError, OSError, ValueError, KeyError) as error:
        reading["error"] = f"{type(error).__name__}: {error}"
    finally:
        instance.stop()
    return reading


def run_s_rows(app, logs):
    one = sheet_reading(app, "s1", '{"preset_id":"av1","encoder_speed":"smaller"}')
    two = sheet_reading(app, "s2", '{"preset_id":"h264"}')
    three = sheet_reading(app, "s3", '{"preset_id":"av1"}', hlg=True)
    logs += [one["instance"], two["instance"], three["instance"]]

    def drawn(reading, popup="speed"):
        if reading.get(f"{popup}_dark") is None or reading.get("format_dark") is None:
            return None
        lighter = reading[f"{popup}_dark"] - reading["format_dark"]
        return "enabled" if lighter <= 40 else "disabled" if lighter > 60 else "unclear"

    check("S1", not one.get("error") and one.get("format") == "AV1 (MP4)"
          and one.get("speed") == "Smaller file" and drawn(one) == "enabled"
          and one.get("footnote") == ["AV1 · MP4 · Smaller file"],
          f"{one.get('error') or ''} format {one.get('format')!r}, Speed {one.get('speed')!r} "
          f"drawn {drawn(one)} (darkest {one.get('speed_dark')} against Format's "
          f"{one.get('format_dark')}), footnote {one.get('footnote')}")
    check("S2", not two.get("error") and two.get("format") == "H.264 (MP4)"
          and drawn(two) == "disabled",
          f"{two.get('error') or ''} format {two.get('format')!r}, Speed {two.get('speed')!r} "
          f"drawn {drawn(two)} (darkest {two.get('speed_dark')} against Format's "
          f"{two.get('format_dark')}), footnote {two.get('footnote')}")
    check("S3", not three.get("error") and three.get("format") == "AV1 (MP4)"
          and three.get("range") == "HDR (HLG)" and drawn(three, "range") == "enabled",
          f"{three.get('error') or ''} format {three.get('format')!r}, Dynamic Range "
          f"{three.get('range')!r} drawn {drawn(three, 'range')} (darkest "
          f"{three.get('range_dark')} against Format's {three.get('format_dark')})")


# ---- the rate (CX-13) ------------------------------------------------------------

def vmaf(distorted, reference, log):
    """libvmaf's pooled mean of `distorted` against `reference`, both as 10-bit 4:2:0
    (ffmpeg's libvmaf filter, CX-14 (6)); None when it cannot run."""
    lavfi = ("[0:v]format=yuv420p10le,setpts=PTS-STARTPTS[d];"
             "[1:v]format=yuv420p10le,setpts=PTS-STARTPTS[r];"
             f"[d][r]libvmaf=log_fmt=json:log_path={log}:n_threads=12")
    ran = run(["ffmpeg", "-hide_banner", "-v", "error", "-i", distorted, "-i", reference,
               "-lavfi", lavfi, "-f", "null", "-"], 1200)
    try:
        return json.loads(Path(log).read_text())["pooled_metrics"]["vmaf"]["mean"]
    except (OSError, ValueError, KeyError):
        print(f"  libvmaf failed (rc {ran['rc']}): {ran['stderr'][-300:]}", flush=True)
        return None


def run_r_rows(app, logs):
    if not OWNER.exists():
        for ident in ("R1", "R2"):
            print(f"{ident} skipped — the owner's fixture {OWNER} is not here", flush=True)
        return
    out = WORK / "rate"
    tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = Instance("r", app)
    logs.append(instance)
    pixels = 1920 * 1080 * 30
    # (the video_bitrate asked of both rows, the cap it makes): Format default asks none and
    # caps at HEVC's 0.07 bits per pixel per frame; High asks the sheet's tier (0.129 × 0.6,
    # to the nearest 100 kbps, ExportSheetOptions.QualityTier) of hevc and av1 alike.
    tiers = {"R1": (None, round(pixels * 0.07)),
             "R2": (max(100_000, round(pixels * 0.129 * 0.6 / 100_000) * 100_000), None)}
    try:
        if instance.client is None:
            for ident in tiers:
                check(ident, False, "the app did not listen")
            return
        doc = Doc(instance, "rate", 1920, 1080)
        try:
            media = doc.media(OWNER)
            doc.call("add_clip", track=doc.track(), media=media, at=0)
            reference = out / "reference.mov"
            try:
                export(doc, reference, preset="prores_422")
            except mcp.ToolError as error:
                for ident in tiers:
                    check(ident, False, f"the ProRes 422 reference failed: {error}")
                return
            for ident, (asked, default) in tiers.items():
                cap = asked or default
                extra = {"video_bitrate": asked} if asked else {}
                lines, ok = [], True
                hevc = out / f"{ident}-hevc_10bit.mp4"
                try:
                    export(doc, hevc, preset="hevc_10bit", **extra)
                except mcp.ToolError as error:
                    check(ident, False, f"the hevc_10bit export failed: {error}")
                    continue
                floor = vmaf(hevc, reference, out / f"{ident}-hevc_10bit.vmaf.json")
                hevc_rate = int(video_stream(hevc).get("bit_rate") or 0)
                ok = floor is not None
                for speed in ("faster", "balanced", "smaller"):
                    path = out / f"{ident}-av1-{speed}.mp4"
                    started = time.monotonic()
                    try:
                        export(doc, path, preset="av1", encoder_speed=speed, **extra)
                    except mcp.ToolError as error:
                        ok = False
                        lines.append(f"{speed}: {error}")
                        continue
                    took = time.monotonic() - started
                    video = video_stream(path)
                    rate = int(video.get("bit_rate") or 0)
                    frames = int(video.get("nb_frames") or 0)
                    score = vmaf(path, reference, out / f"{ident}-av1-{speed}.vmaf.json")
                    good = (0 < rate <= CAP_TOLERANCE * cap and score is not None
                            and floor is not None and score >= floor)
                    ok = ok and good
                    lines.append(f"{speed}: {rate} b/s ({rate / cap:.3f} of the cap), VMAF "
                                 f"{score if score is None else round(score, 3)}, {frames} frames "
                                 f"in {took:.1f} s = {frames / took:.1f} fps"
                                 + ("" if good else " ✗"))
                check(ident, ok, f"cap {cap} b/s (each file ≤ {CAP_TOLERANCE} × it) "
                      f"({'video_bitrate ' + str(asked) if asked else 'Format default'}); hevc_10bit "
                      f"{hevc_rate} b/s, VMAF {floor if floor is None else round(floor, 3)} "
                      "against the ProRes 422 reference; av1 — " + "; ".join(lines))
        finally:
            doc.close()
    finally:
        instance.stop()


# ---- the mutants -----------------------------------------------------------------

def build_mutant(name):
    """The copy with the anchors replaced, built: (app, copy) or (None, why)."""
    dest = WORK / "mutant"
    made, reason = tree_copy.make_copy(str(dest))
    atexit.register(tree_copy.remove_tree, str(dest))
    if made is None:
        return None, reason
    copy = Path(made)
    anchors = MUTANTS[name]["anchors"]
    if any(path.startswith("core/") for path, _, _ in anchors):
        from hevc_alpha_proof import own_core
        reason = own_core(copy)
        if reason:
            return None, reason
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            return None, f"the copy's core/tests could not be linked: {error}"
    for path, anchor, replacement in anchors:
        target = copy / path
        if not target.resolve().is_relative_to(dest.resolve()):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(copy, 1800)
    return (app, copy) if app else (None, reason)


def run_mutant(name):
    if name not in MUTANTS:
        print(f"unknown mutant {name}; the mutants are {sorted(MUTANTS)}")
        return 2
    named = MUTANTS[name]["rows"]
    print(f"mutant {name}: building the copy", flush=True)
    app, copy = build_mutant(name)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {copy}")
        return 2
    failed_tests = []
    cargo = MUTANTS[name].get("cargo")
    if cargo:
        ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", cargo],
                          1200, cwd=str(copy / "core"))
        out = ran["stdout"] + ran["stderr"]
        if ran["expired"] or "test result:" not in out:
            print(f"mutant {name}: the control could not be performed — cargo rc {ran['rc']}: "
                  f"{out[-600:]}")
            return 2
        failed_tests = re.findall(r"^test (\w+) \.\.\. FAILED$", out, re.M)
        check(f"cargo-{cargo}", ran["rc"] == 0, f"failed tests {failed_tests}")
        named = named + [f"cargo-{cargo}"]
    logs = []
    try:
        run_rows(app, logs)
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


# ---- main ------------------------------------------------------------------------

def run_rows(app, logs, rate=False):
    run_a_rows(app, logs)
    run_h_rows(app, logs)
    run_s_rows(app, logs)
    if rate:
        run_r_rows(app, logs)
    found = [(i.label, line) for i in logs for line in i.complaints()]
    check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="the av1 row (codec-export C1, C2)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--rate", action="store_true", help="also R1 and R2 (CX-13)")
    parser.add_argument("--mutant", help="one of " + ", ".join(MUTANTS))
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)
    logs = []
    try:
        app = proof_app.bundle()
        proof_app.require_fresh(proof_app.executable(app))
    except (proof_app.StaleApp, ValueError, OSError) as error:
        check("A0", False, f"the app cannot be driven: {error}")
        print("scores: 0/1")
        return 1
    print(f"app {app}", flush=True)
    run_rows(app, logs, rate=args.rate)
    passed = sum(results.values())
    print(f"scores: {passed}/{len(results)}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
