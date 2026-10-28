#!/usr/bin/env python3
"""Road map "codec-export" C1 — the `av1` row: AV1 in MP4 through the bundled
SVT-AV1 (spec §11 CX-1, CX-2, CX-9, CX-10, CX-12, CX-13).

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
  clip is done; ffprobe reads video `av1` / `av01` / Main / `yuv420p` /
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
* R1, R2 — only with `--rate` (CX-13's soft-capped CRF): the owner's full-length
  clip `tools/proof/media/owner-sync/IMG_0018.MOV` (1920 × 1080, 30 fps,
  55.27 s) exported once as `prores_422` (the reference), then, R1 at "Format
  default" (no `video_bitrate`: the cap is HEVC's 0.07 bits per pixel per
  frame) and R2 at the sheet's High tier (`video_bitrate` 0.129 × 0.6 to the
  nearest 100 kbps, asked of both), as `hevc` and as `av1` at each speed:
  each `av1` file's video bit rate (ffprobe, the whole file's average) is at
  most 1.25 × the cap (CX-13's soft cap) and its VMAF against the reference
  (ffmpeg's libvmaf, both as 8-bit 4:2:0) is at or above the `hevc` file's.
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
  colour-untagged-bitstream  SVT's CICP left unset: A3a
  colour-untagged-container  the format description's colour extensions
                             dropped: A3b

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import atexit
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
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

ROWS = ["Z1", "A1", "A2", "A3a", "A3b", "A4", "A5", "A6", "A7", "A8", "A9", "S1", "S2"]

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
        (f"{SOURCES}/ExportEncodePump.swift", "            guard !isStopping() else { return false }\n",
         "            guard !false else { return false }\n")]},
    "speed-on-any-row": {"rows": ["A7"], "cargo": "export_av1", "anchors": [
        ("core/src/export.rs",
         "        let speed = match (encoder_speed(overrides)?, preset.takes_encoder_speed()) {\n",
         "        let speed = match (encoder_speed(overrides)?, true) {\n")]},
    "colour-untagged-bitstream": {"rows": ["A3a"], "anchors": [
        (f"{SOURCES}/ExportAV1Encoder.swift",
         "        config.color_primaries = EB_CICP_CP_BT_709\n"
         "        config.transfer_characteristics = EB_CICP_TC_BT_709\n"
         "        config.matrix_coefficients = EB_CICP_MC_BT_709\n", "")]},
    "colour-untagged-container": {"rows": ["A3b"], "anchors": [
        (f"{SOURCES}/ExportAV1Track.swift",
         "            kCMFormatDescriptionExtension_ColorPrimaries as String:\n"
         "                kCMFormatDescriptionColorPrimaries_ITU_R_709_2,\n"
         "            kCMFormatDescriptionExtension_TransferFunction as String:\n"
         "                kCMFormatDescriptionTransferFunction_ITU_R_709_2,\n"
         "            kCMFormatDescriptionExtension_YCbCrMatrix as String:\n"
         "                kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,\n"
         "            kCMFormatDescriptionExtension_FullRangeVideo as String: false,\n", "")]},
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


def colr_of(path):
    """The `av01` sample entry's `colr` box: (type, primaries, transfer, matrix,
    full_range) or None, read from the file's bytes."""
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
            for child, cbody, cstop in boxes(data, entry[0] + 78, entry[1]):
                if child == "colr" and data[cbody:cbody + 4] == b"nclx":
                    p, t, m = struct.unpack(">HHH", data[cbody + 4:cbody + 10])
                    return ("nclx", p, t, m, data[cbody + 10] >> 7)
            return None
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
    want = ("av1", "av01", "Main", "yuv420p", 640, 360, "aac", "mp4a")
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


def sheet_reading(app, label, choice):
    """One pinned instance: File ▸ Export… on a project, the sheet read and cancelled."""
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
        doc = av_doc(instance, "sheet")
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
        reading.update({
            "format": fmt and fmt.get("text"), "speed": speed and speed.get("text"),
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
    logs += [one["instance"], two["instance"]]

    def drawn(reading):
        if reading.get("speed_dark") is None or reading.get("format_dark") is None:
            return None
        lighter = reading["speed_dark"] - reading["format_dark"]
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


# ---- the rate (CX-13) ------------------------------------------------------------

def vmaf(distorted, reference, log):
    """libvmaf's pooled mean of `distorted` against `reference`, both as 8-bit 4:2:0
    (ffmpeg's libvmaf filter, as the spike scored); None when it cannot run."""
    lavfi = ("[0:v]format=yuv420p,setpts=PTS-STARTPTS[d];[1:v]format=yuv420p,setpts=PTS-STARTPTS[r];"
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
                hevc = out / f"{ident}-hevc.mp4"
                try:
                    export(doc, hevc, preset="hevc", **extra)
                except mcp.ToolError as error:
                    check(ident, False, f"the hevc export failed: {error}")
                    continue
                floor = vmaf(hevc, reference, out / f"{ident}-hevc.vmaf.json")
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
                      f"({'video_bitrate ' + str(asked) if asked else 'Format default'}); hevc "
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
    run_s_rows(app, logs)
    if rate:
        run_r_rows(app, logs)
    found = [(i.label, line) for i in logs for line in i.complaints()]
    check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="the av1 row (codec-export C1)")
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
