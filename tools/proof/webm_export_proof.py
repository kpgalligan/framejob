#!/usr/bin/env python3
"""Road map "codec-export" C3 — the `av1_webm` row: AV1 in WebM through the bundled
SVT-AV1, written by the core's own WebM writer (`rc_webm_*`), with Opus sound from
AudioToolbox (spec §11 CX-6, CX-7, CX-15).

    python3 tools/proof/webm_export_proof.py [--app debug|release|PATH]
    python3 tools/proof/webm_export_proof.py --probe          # the P and A rows alone, no app
    python3 tools/proof/webm_export_proof.py --mutant NAME

Launches its own instances of the chosen app (`proof_app.py`: `--app`, else
`RC_PROOF_APP`, else Debug; a build older than its inputs is refused) on scratch
sockets, works under `tools/proof/work/webm-export/`, closes every project it opens
with `discard: true` and stops each instance by its own PID. It reuses
`av1_export_proof.py`'s helpers by import (its instance, documents, exports, ffprobe
readers and sheet reading). ffprobe and ffmpeg (Homebrew, with libdav1d and Opus) only
READ the files.

"A1's project" is `av1_export_proof.py`'s: AV.mov (640 × 360, 30 fps, 5 s) under a
two-second text clip; here it also carries two chapter markers, "Intro" at 0 s and
"Body" at 2.5 s. Each W row is ffprobe/ffmpeg over it exported as `av1_webm` unless it
says otherwise. Rows (`<ID> ok|FAIL — <detail>`, then `scores: n/m`; exit 0 iff all
passed):

* Z1 — every instance's log is silent (no `Frame Job: `, `Svt[` or `SVT-AV1: ` line).
* W1 — done; format `matroska,webm`; video `av1` Main `yuv420p10le` 640 × 360; audio
  `opus` 48 kHz stereo; the format's duration 5.0 s ± one frame.
* W2 — `ffmpeg -v error` decodes the file with no line; 150 video frames; exactly
  240,000 audio samples (the s16le stereo byte count / 4): #337's length through
  CodecDelay and DiscardPadding; and the first audio packet at −CodecDelay (ffprobe's
  `initial_padding`, the pre-skip, above 0 and the packet at −padding / 48 kHz in whole
  ms). The last because ffmpeg trims OpusHead's pre-skip whatever CodecDelay says, so the
  count alone does not see a CodecDelay of 0 (measured, C3).
* W3 — A5's key rule on the WebM's video blocks, their key flags read from the file by
  the walk (ffprobe's and `trace_headers`' flags for AV1 in Matroska are ffmpeg's AV1
  parser's, from the bitstream, so they cannot see the container's flag): the first a
  key, every key 2 s or less from the next, fewer keys than blocks, each block's key flag
  the bitstream's shown KEY_FRAME both ways, no hidden intra frame.
* W4 — a Python EBML walk of the file: the Segment's size is the file's length less
  the Segment's header; the SeekHead's entries (Info, Tracks, Chapters, Cues) each
  resolve to that element; every video key block starts a Cluster; the Cues hold one
  CuePoint per key-started Cluster, each at its Cluster's position and time.
* W5 — `ffprobe -show_chapters`: "Intro" 0.0–2.5 s and "Body" 2.5–5.0 s.
* W6 — the 1 s – 3 s in/out export: 60 frames, 96,000 samples, and the chapters
  clamped and rebased: "Intro" 0.0–1.5 s, "Body" 1.5–2.0 s.
* W7 — `size: [640, 480]` is 640 × 480 with the picture letterboxed (A8's rule).
* W8 — A1's project made HLG, exported at the default, `pq` and `sdr`: the answer's
  dynamic range; ffprobe's `yuv420p10le` / Main and its colour tags; the sequence
  headers' CICP (9/18/9, 9/16/9, 1/1/1, video range); the walk's Colour (the same
  CICP, Range 1, BitsPerChannel 10, and on PQ alone MasteringMetadata and MaxCLL 1000 /
  MaxFALL 0); on PQ the stream's mastering-display side data at HD-5's values (P3-D65,
  0.005–1,000 cd/m²), on the others no HDR side data. The light level is read from the
  walk alone: ffmpeg's Matroska demuxer exports a content-light-level side data only
  when MaxCLL and MaxFALL are both non-zero, and HD-5's MaxFALL is 0 (measured, C3).
* W9 — A6's cancel on a 24-clip 1080p project exported as `av1_webm`: cancelled
  within 10 s while encoding, and no file at the path.
* W10 — the default rate's audio bytes are more than 1.25 × those of an
  `audio_bitrate: 64000` export.
* W11 — with `loudness_lufs: -16`, ffmpeg ebur128's integrated loudness is −16 ± 1 LU.
* W12 — `import_media` of W1's file: on an M1 or M2, refused in
  `codec_import_proof.av1_sentence`'s words; on an M3 or later, a 5.0 s 640 × 360
  media with audio.
* W13 — a project holding only a 5 s text clip (no media, so no audio track) exported
  as `av1_webm`: done; exactly one stream, `av1` 640 × 360; `ffmpeg -v error` decodes
  150 frames with no line; the walk finds one TrackEntry.
* S4 — the export sheet pinned to `{"preset_id":"av1_webm"}` reads Format
  "AV1 (WebM)" and the footnote "AV1 · WEBM · Balanced".
* R1 — the measurement behind one reader per output (fix pass 1, CX-15 (2)): the probe
  `webm_readers_probe.swift` (no app; the tree's export shaders as its `default.metallib`)
  reads A1's project through `ExportWriter`'s two outputs on one reader and on two readers,
  each on a thread of its own, from builds of their own: 150 frames each, every frame's
  64RGBAHalf bytes equal, the I010 of frames 0, 75 and 149 byte-equal, and 240,000 frames of
  16-bit sound equal sample for sample.
* F1–F3 — G-17's windows closed on the WebM path: W9's 24-clip 1080p project exported as
  `av1_webm` on an instance launched with `-RCDevWebMFault` (`ExportWebMDevFault`): F1
  `audio@40` (the audio pump fails at its 40th read), F2 `video@30` (the video sink fails at
  its 30th packet), F3 `audio-hold@40` (the audio pump held 3 s at its 40th read, before the
  read, and `cancel_export` sent when the hold's log line appears). Each ends — F1 and F2
  `failed` naming the dev fault, F3 `cancelled` — within 10 s of the fault's log line (F3: of
  the cancel), with no file at the path, and the writer's `framejob webm dev readers:` line
  reads exactly `video 4, audio 4`: both readers cancelled (status 4) by their own pumps,
  and two readers (the line adds ` (one reader)` when the outputs share one).
* P1–P5, A1–A5 — the probe `webm_audio_probe.swift` (fix pass 1), compiled AS
  `main.swift` over `app/Sources` on `swift_build.py`'s line, no app: P1–P5 the Opus
  encoder's FIFO fed by the buffer's BYTES (a short last buffer, a buffer cut by `fit`, bytes
  that outrun or fall short of the sample count, and 402 bytes refused in a sentence);
  A1–A5 `ExportAudioEnd.align`, the sound placed at its stamps (zeros for a gap, the covered
  head cut, a buffer covered whole dropped, no gap untouched, the zeros stopped at the
  target). A probe that will not build is a scored FAIL of every P and A row.

Mutants (`--mutant NAME`, a tree copy built as Debug with the named anchor replaced;
exit 1 and `MUTANT CAUGHT` when exactly the named rows fail — `cargo-<file>` is that
cargo test file run in the copy):

  codec-delay-zero     the TrackEntry's CodecDelay written 0: W2, cargo. Not E38 or E39
                       (measured, C3): `export_offset_proof.py` places clicks by sample in
                       the decoded stream, and ffmpeg trims OpusHead's pre-skip whatever
                       CodecDelay says, so only the packets' times (W2) move
  no-discard-padding   the tail packet's DiscardPadding never sent: W2, W6
  clusters-by-time     Clusters every 1.5 s instead of at video keys: W4, cargo
  no-cues              no Cues written: W4
  colour-unwritten     no Colour element: W8, cargo
  chapters-unclamped   a chapter before the range not pinned to its start: W6
  all-key              every video block flagged key: W3
  gain-skipped         the loudness gain never kept: W11
  opus-length-exact    the encoder's old check, bytes = samples × 4, put back: P3, P4
                       (a probe mutant: the copy is `app/Sources` alone, no app built)
  gap-unfilled         `align` never fills a gap: A1, A5 (a probe mutant)
  head-uncut           `align` cuts a covered head from the buffer's tail: A2 (a probe mutant)
  shared-reader        the audio output put on the video's reader again: the F rows (a
                       fault mutant: the copy's app built, the F rows alone run)
  audio-cancel-dropped the audio pump's own `cancelReading` on a stop dropped: F1–F3 (a
                       fault mutant)

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import json
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
from codec_import_proof import av1_sentence  # noqa: E402

WORK = HERE / "work" / "webm-export"
av1.WORK = WORK            # the reused Instance and mutant builder work here
SEC = av1.SEC
FRAMES = 150
SAMPLES = 240_000          # 5 s at 48 kHz
CANCEL_BOUND = 10.0
CHAPTERS = [("Intro", 0.0, 2.5), ("Body", 2.5, 5.0)]
CHAPTERS_IN_OUT = [("Intro", 0.0, 1.5), ("Body", 1.5, 2.0)]

ROWS = ["Z1", "W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "W10", "W11", "W12",
        "W13", "S4"]
FAULTS = {"F1": ("audio@40", "failed"), "F2": ("video@30", "failed"),
          "F3": ("audio-hold@40", "cancelled")}
FAULT_BOUND = 10.0
PROBE_ROWS = ["P1", "P2", "P3", "P4", "P5", "A1", "A2", "A3", "A4", "A5"]
PROBE_SWIFT = HERE / "webm_audio_probe.swift"
READERS_SWIFT = HERE / "webm_readers_probe.swift"

SOURCES = "app/Sources"
MUTANTS = {
    "codec-delay-zero": {"rows": ["W2"], "cargo": "webm_writer", "anchors": [
        ("core/src/webm_ebml.rs", "            uint(CODEC_DELAY, delay_ns),\n",
         "            uint(CODEC_DELAY, 0 * delay_ns),\n")]},
    "no-discard-padding": {"rows": ["W2", "W6"], "anchors": [
        (f"{SOURCES}/ExportWebMWriter+Audio.swift",
         "                try add(packet, index == tail.count - 1 ? paddingNs : 0)\n",
         "                try add(packet, index == tail.count - 1 ? 0 * paddingNs : 0)\n")]},
    "clusters-by-time": {"rows": ["W4"], "cargo": "webm_writer", "anchors": [
        ("core/src/webm_writer.rs",
         "            Some(c) => video_key || p.ms.saturating_sub(c.ms) > MAX_RELATIVE_MS,\n",
         "            Some(c) => p.ms.saturating_sub(c.ms) >= 1_500 + 0 * MAX_RELATIVE_MS,\n")]},
    "no-cues": {"rows": ["W4"], "anchors": [
        ("core/src/webm_writer.rs", "        if !self.cues.is_empty() {\n",
         "        if self.cues.is_empty() && !self.cues.is_empty() {\n")]},
    "colour-unwritten": {"rows": ["W8"], "cargo": "webm_writer", "anchors": [
        ("core/src/webm_ebml.rs", "            master(COLOUR, &c),\n",
         "            {\n                drop(c);\n                Vec::new()\n            },\n")]},
    "chapters-unclamped": {"rows": ["W6"], "anchors": [
        (f"{SOURCES}/ExporterWriter+Chapters.swift",
         "            if chapter.start <= start {\n",
         "            if chapter.start <= start && false {\n")]},
    "all-key": {"rows": ["W3"], "anchors": [
        (f"{SOURCES}/ExportPacketSink.swift",
         "                track: ReelWebM.video, ptsNs: Self.nanoseconds(time), key: key,\n",
         "                track: ReelWebM.video, ptsNs: Self.nanoseconds(time), key: key || true,\n")]},
    "gain-skipped": {"rows": ["W11"], "anchors": [
        (f"{SOURCES}/ExportWebMWriter.swift",
         "        audioGain = ExportAudioGain(linearGain: gain)\n",
         "        _ = ExportAudioGain(linearGain: gain)\n")]},
    "opus-length-exact": {"rows": ["P3", "P4"], "probe": True, "anchors": [
        (f"{SOURCES}/ExportOpusEncoder.swift",
         "        guard bytes % frameBytes == 0 else {\n",
         "        guard bytes == CMSampleBufferGetNumSamples(sample) * frameBytes else {\n")]},
    "gap-unfilled": {"rows": ["A1", "A5"], "probe": True, "anchors": [
        (f"{SOURCES}/ExportAudioEnd.swift", "        if frame > written {\n",
         "        if frame > written && false {\n")]},
    "shared-reader": {"rows": ["F1", "F2", "F3"], "fault": True, "anchors": [
        (f"{SOURCES}/ExportWebMWriter.swift",
         "        audioReader = hasAudio ? try Self.reader(built.composition, range: range) : nil\n",
         "        audioReader = hasAudio ? videoReader : nil\n")]},
    "audio-cancel-dropped": {"rows": ["F1", "F2", "F3"], "fault": True, "anchors": [
        (f"{SOURCES}/ExportWebMWriter.swift",
         "                if isStopping { audioReader.cancelReading() }\n",
         "                if isStopping && false { audioReader.cancelReading() }\n")]},
    "head-uncut": {"rows": ["A2"], "probe": True, "anchors": [
        (f"{SOURCES}/ExportAudioEnd.swift",
         "            sampleRange: CFRange(location: covered, length: frames - covered),\n",
         "            sampleRange: CFRange(location: 0, length: frames - covered),\n")]},
}

results = {}


def check(ident, ok, detail):
    results[ident] = bool(ok)
    print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def run(argv, seconds=600):
    return bounded.run([str(a) for a in argv], seconds)


# ---- reading the files -------------------------------------------------------------

def probe(path):
    """ffprobe's format name and duration and its streams."""
    ran = run(["ffprobe", "-v", "error", "-show_entries",
               "format=format_name,duration:stream=codec_type,codec_name,profile,pix_fmt,"
               "width,height,sample_rate,channels", "-of", "json", path])
    got = json.loads(ran["stdout"] or "{}")
    return got.get("format", {}), got.get("streams", [])


def audio_samples(path):
    """The decoded audio's sample frames: the s16le stereo byte count / 4."""
    out = Path(str(path) + ".s16")
    out.unlink(missing_ok=True)
    ran = run(["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:a:0", "-ac", "2", "-f",
               "s16le", out])
    try:
        count = out.stat().st_size // 4 if ran["rc"] == 0 else None
    except OSError:
        count = None
    out.unlink(missing_ok=True)
    return count


def audio_start(path):
    """The first audio packet's time and the stream's initial padding (CodecDelay in
    samples) as ffprobe reads them: (seconds, samples), None where unread."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
               "stream=initial_padding:packet=pts_time", "-read_intervals", "%+#1", "-of",
               "json", path])
    got = json.loads(ran["stdout"] or "{}")
    first = (got.get("packets") or [{}])[0].get("pts_time")
    padding = (got.get("streams") or [{}])[0].get("initial_padding")
    return (float(first) if first is not None else None), padding


def chapters(path):
    ran = run(["ffprobe", "-v", "error", "-show_chapters", "-of", "json", path])
    listed = json.loads(ran["stdout"] or "{}").get("chapters", [])
    return [(c.get("tags", {}).get("title"), round(float(c["start_time"]), 3),
             round(float(c["end_time"]), 3)) for c in listed]


def audio_bytes(path):
    ran = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
               "packet=size", "-of", "csv=p=0", path])
    return sum(int(line.split(",")[0]) for line in ran["stdout"].split() if line.strip())


def integrated_lufs(path):
    ran = run(["ffmpeg", "-hide_banner", "-nostats", "-i", path, "-map", "0:a:0", "-af",
               "ebur128", "-f", "null", "-"])
    found = re.findall(r"I:\s+(-?[0-9.]+) LUFS", ran["stderr"])
    return float(found[-1]) if found else None


# ---- the EBML walk ------------------------------------------------------------------

MASTERS = {0x1A45DFA3, 0x18538067, 0x114D9B74, 0x4DBB, 0x1549A966, 0x1654AE6B, 0xAE, 0xE0,
           0x55B0, 0x55D0, 0xE1, 0x1043A770, 0x45B9, 0xB6, 0x80, 0x1F43B675, 0xA0,
           0x1C53BB6B, 0xBB, 0xB7}


def vint(data, at, keep_marker):
    first = data[at]
    length = 1
    while length <= 8 and not first & (0x80 >> (length - 1)):
        length += 1
    value = first if keep_marker else first & (0xFF >> length)
    for b in data[at + 1:at + length]:
        value = (value << 8) | b
    return value, length


def walk(data, start, end):
    """[(id, element start, data start, size, children)] from `start` to `end`."""
    out, at = [], start
    while at < end:
        ident, a = vint(data, at, True)
        size, b = vint(data, at + a, False)
        body = at + a + b
        if size == (1 << (7 * b)) - 1 or body + size > end:
            raise ValueError(f"element {ident:#x} at {at} has an unknown or long size")
        kids = walk(data, body, body + size) if ident in MASTERS else []
        out.append((ident, at, body, size, kids))
        at = body + size
    return out


def uint(data, element):
    return int.from_bytes(data[element[2]:element[2] + element[3]], "big")


def first(elements, ident):
    return next((e for e in elements if e[0] == ident), None)


def segment_of(path):
    data = Path(path).read_bytes()
    top = walk(data, 0, len(data))
    return data, first(top, 0x18538067)


def track_entries(segment):
    tracks = first(segment[4], 0x1654AE6B)
    return [e for e in tracks[4] if e[0] == 0xAE] if tracks else []


def colour_of(data, segment):
    """The video TrackEntry's Colour as a dict, or None when it has none."""
    for entry in track_entries(segment):
        video = first(entry[4], 0xE0)
        colour = video and first(video[4], 0x55B0)
        if colour:
            names = {0x55B1: "matrix", 0x55B2: "bits", 0x55B9: "range", 0x55BA: "transfer",
                     0x55BB: "primaries", 0x55BC: "max_cll", 0x55BD: "max_fall"}
            out = {names[e[0]]: uint(data, e) for e in colour[4] if e[0] in names}
            out["mastering"] = first(colour[4], 0x55D0) is not None
            return out
    return None


def video_blocks(path):
    """The video track's blocks in file order, as the file flags them: [(seconds, key)]."""
    data, segment = segment_of(path)
    out = []
    for cluster in (e for e in (segment[4] if segment else []) if e[0] == 0x1F43B675):
        base = uint(data, first(cluster[4], 0xE7))
        for block in (e for e in cluster[4] if e[0] == 0xA3):
            body = data[block[2]:block[2] + block[3]]
            track, n = vint(body, 0, False)
            if track == 1:
                ms = base + int.from_bytes(body[n:n + 2], "big", signed=True)
                out.append((ms / 1000, bool(body[n + 2] & 0x80)))
    return out


def walk_misses(path):
    """W4's reading: (misses, a summary)."""
    data, segment = segment_of(path)
    misses = []
    if segment is None:
        return ["no Segment"], ""
    if segment[2] + segment[3] != len(data):
        misses.append(f"Segment size {segment[3]} + header {segment[2]} ≠ {len(data)}")
    level = segment[4]
    head = level[0] if level else None
    seen = []
    if head is None or head[0] != 0x114D9B74:
        misses.append("the Segment's first element is not a SeekHead")
    else:
        for seek in (e for e in head[4] if e[0] == 0x4DBB):
            target = uint(data, first(seek[4], 0x53AB))
            at = segment[2] + uint(data, first(seek[4], 0x53AC))
            found = next((e for e in level if e[1] == at), None)
            if found is None or found[0] != target:
                misses.append(f"the seek to {target:#x} lands on {found and hex(found[0])}")
            seen.append(target)
    want = [0x1549A966, 0x1654AE6B, 0x1043A770, 0x1C53BB6B]
    if seen != want:
        misses.append(f"the SeekHead names {[hex(s) for s in seen]}")
    started = []        # (ms, position) of each key-started Cluster
    for cluster in (e for e in level if e[0] == 0x1F43B675):
        base = uint(data, first(cluster[4], 0xE7))
        blocks = [e for e in cluster[4] if e[0] in (0xA3, 0xA0)]
        for index, block in enumerate(blocks):
            if block[0] != 0xA3:
                continue
            body = data[block[2]:block[2] + block[3]]
            track, n = vint(body, 0, False)
            key = bool(body[n + 2] & 0x80)
            ms = base + int.from_bytes(body[n:n + 2], "big", signed=True)
            if track == 1 and key and index != 0:
                misses.append(f"the video key at {ms} ms does not start its Cluster")
            if track == 1 and key and index == 0:
                started.append((ms, cluster[1] - segment[2]))
    cues = first(level, 0x1C53BB6B)
    points = []
    for point in (cues[4] if cues else []):
        positions = first(point[4], 0xB7)
        points.append((uint(data, first(point[4], 0xB3)),
                       uint(data, first(positions[4], 0xF1))))
    if not points or points != started:
        misses.append(f"CuePoints {points} against key-started Clusters {started}")
    return misses, f"{len(started)} key-started Clusters at {[s[0] for s in started]} ms, " \
        f"CuePoints {len(points)}, SeekHead {[hex(s) for s in seen]}, file {len(data)} bytes"


# ---- the projects ------------------------------------------------------------------

def a1_doc(instance, name, hlg=False):
    """A1's project with its two chapter markers (made HLG when asked)."""
    doc = av1.hlg_doc(instance, name) if hlg else av1.av_doc(instance, name)
    for title, start, _ in CHAPTERS:
        doc.call("add_marker", at=int(start * SEC), name=title, chapter=True)
    return doc


def text_doc(instance, name):
    doc = av1.Doc(instance, name)
    doc.call("add_text_clip", track=doc.track(), at=0, duration=5 * SEC,
             text={"content": "WebM"})
    return doc


def export(doc, path, **arguments):
    return av1.export(doc, path, preset="av1_webm", **arguments)


# ---- the rows ----------------------------------------------------------------------

def rows_w1_w5(doc, out):
    path = out / "w1.webm"
    try:
        done = export(doc, path)
    except mcp.ToolError as error:
        for ident in ("W1", "W2", "W3", "W4", "W5", "W12"):
            check(ident, False, f"W1's export failed: {error}")
        return None
    fmt, got = probe(path)
    video = next((s for s in got if s.get("codec_type") == "video"), {})
    audio = next((s for s in got if s.get("codec_type") == "audio"), {})
    seen = (fmt.get("format_name"), video.get("codec_name"), video.get("profile"),
            video.get("pix_fmt"), video.get("width"), video.get("height"),
            audio.get("codec_name"), audio.get("sample_rate"), audio.get("channels"))
    want = ("matroska,webm", "av1", "Main", "yuv420p10le", 640, 360, "opus", "48000", 2)
    length = float(fmt.get("duration") or 0)
    check("W1", done.get("status") == "done" and seen == want and abs(length - 5) <= 1 / 30,
          f"status {done.get('status')}, {done.get('bytes')} bytes; read {seen} (want "
          f"{want}); duration {length:.3f} s")

    rc, errors = av1.decode_errors(path)
    frames = av1.decoded_frames(path)
    samples = audio_samples(path)
    start, padding = audio_start(path)
    # The first packet sits CodecDelay early, its time in whole ms (round half up).
    delayed = (padding is not None and padding > 0 and start is not None
               and abs(start + int(padding * 1000 / 48_000 + 0.5) / 1000) < 1e-6)
    check("W2", rc == 0 and not errors and frames == FRAMES and samples == SAMPLES
          and delayed,
          f"ffmpeg rc {rc}, {len(errors)} error lines {errors[:2]}; {frames} frames (want "
          f"{FRAMES}); {samples} audio samples (want {SAMPLES}); the first audio packet at "
          f"{start} s with initial padding {padding} (want −padding/48 kHz, in ms)")

    # The key flags are the FILE's (the SimpleBlocks', read by the walk): ffprobe's and
    # trace_headers' packet flags for AV1 in Matroska are ffmpeg's AV1 parser's, read from
    # the bitstream, so they cannot see a container flag that lies (measured, C3).
    listed = video_blocks(path)
    head, per_packet = av1.trace(path)
    keys = [t for t, k in listed if k]
    gaps = [b - a for a, b in zip(keys, keys[1:])] + ([length - keys[-1]] if keys else [])
    mismatched = [i for i, (p, (_, key)) in enumerate(zip(per_packet, listed))
                  if key != av1.shows_key(p["fields"])]
    hidden = [i for i, p in enumerate(per_packet) if av1.hidden_intra(p["fields"])]
    ok = (listed and len(listed) == len(per_packet) and listed[0][1] and gaps
          and max(gaps) <= 2.0 + 1e-6 and len(keys) < len(listed) and not mismatched
          and not hidden)
    check("W3", ok, f"{len(listed)} video blocks ({len(per_packet)} traced), keys at {keys}; "
          f"longest K-to-K gap {max(gaps) if gaps else None} s (≤ 2.0); key flag ≠ shown "
          f"KEY_FRAME at {mismatched[:6]}; hidden intra frames at {hidden[:6]}")

    try:
        misses, summary = walk_misses(path)
    except (ValueError, TypeError, IndexError) as error:
        misses, summary = [f"the walk failed: {error}"], ""
    check("W4", not misses, summary + (f"; misses {misses}" if misses else ""))

    listed_chapters = chapters(path)
    check("W5", listed_chapters == CHAPTERS, f"chapters {listed_chapters} (want {CHAPTERS})")
    return path


def row_w6(doc, out):
    path = out / "w6.webm"
    try:
        doc.call("set_range", start=1 * SEC, end=3 * SEC)
        export(doc, path, range="in_out")
        frames, samples, listed = av1.decoded_frames(path), audio_samples(path), chapters(path)
        check("W6", frames == 60 and samples == 96_000 and listed == CHAPTERS_IN_OUT,
              f"{frames} frames (want 60), {samples} samples (want 96000), chapters "
              f"{listed} (want {CHAPTERS_IN_OUT})")
    except mcp.ToolError as error:
        check("W6", False, str(error))


def row_w7(doc, out):
    path = out / "w7.webm"
    try:
        export(doc, path, size=[640, 480])
        video = av1.video_stream(path)
        plane = av1.y_plane(path, 640, 480)
        top = max(plane[:640 * 56]) if plane else None
        middle = (sum(plane[640 * 200:640 * 280]) / (640 * 80)) if plane else None
        ok = ((video.get("width"), video.get("height")) == (640, 480) and top is not None
              and top <= 20 and middle > 20)
        check("W7", ok, f"{video.get('width')} × {video.get('height')}, the top 56 rows' "
              f"highest luma {top} (≤ 20), the middle rows' mean "
              f"{middle if middle is None else round(middle, 1)} (> 20)")
    except mcp.ToolError as error:
        check("W7", False, str(error))


def row_w8(doc, out):
    lines, misses = [], []
    for asked, cicp, tags, hdr10 in [
            (None, (9, 18, 9), "bt2020nc/arib-std-b67/bt2020", False),
            ("pq", (9, 16, 9), "bt2020nc/smpte2084/bt2020", True),
            ("sdr", (1, 1, 1), "bt709/bt709/bt709", False)]:
        want = asked or "hlg"
        path = out / f"w8-{want}.webm"
        try:
            done = export(doc, path, **({} if asked is None else {"dynamic_range": asked}))
        except mcp.ToolError as error:
            misses.append(f"{want}: {error}")
            continue
        pix, profile, seen_tags = av1.colour_tags(path)
        values = av1.cicp_of(path)
        data, segment = segment_of(path)
        colour = colour_of(data, segment) if segment else None
        stream = av1.stream_side(path)
        kinds = set(stream[1]) if stream else None
        hdr_kinds = {"Mastering display metadata", "Content light level metadata"}
        mastering = {"max_luminance": "1000/1", "min_luminance": "1/200", "red_x": "17/25",
                     "red_y": "8/25", "green_x": "53/200", "green_y": "69/100",
                     "blue_x": "3/20", "blue_y": "3/50", "white_point_x": "3127/10000",
                     "white_point_y": "329/1000"}
        want_colour = {"matrix": cicp[2], "bits": 10, "range": 1, "transfer": cicp[1],
                       "primaries": cicp[0], "mastering": hdr10}
        if hdr10:
            want_colour.update({"max_cll": 1000, "max_fall": 0})
        row_misses = []
        if done.get("dynamic_range") != want:
            row_misses.append(f"answer {done.get('dynamic_range')!r}")
        if (pix, profile, seen_tags) != ("yuv420p10le", "Main", tags):
            row_misses.append(f"read {pix} / {profile} / {seen_tags}")
        if values != {"color_description_present_flag": [1], "color_primaries": [cicp[0]],
                      "transfer_characteristics": [cicp[1]],
                      "matrix_coefficients": [cicp[2]], "color_range": [0]}:
            row_misses.append(f"CICP {values}")
        if colour != want_colour:
            row_misses.append(f"Colour {colour}")
        if kinds is None:
            row_misses.append("ffprobe could not read the side data")
        elif hdr10 and ("Mastering display metadata" not in kinds
                        or {k: stream[0].get(k) for k in mastering} != mastering):
            row_misses.append(f"side data {sorted(kinds)} {stream[0]}")
        elif not hdr10 and hdr_kinds & kinds:
            row_misses.append(f"side data {sorted(kinds)}")
        misses += [f"{want}: {m}" for m in row_misses]
        lines.append(f"{want}: {pix} / {profile} / {seen_tags}, Colour {colour}, side data "
                     f"{sorted(kinds) if kinds is not None else None}")
    check("W8", not misses, "; ".join(lines) + (f"; misses {misses}" if misses else ""))


def row_w9(instance, out):
    path = out / "w9.webm"
    path.unlink(missing_ok=True)
    doc, ok, detail = None, False, ""
    try:
        doc = av1.Doc(instance, "w9", 1920, 1080)
        media = doc.media(av1.AV)
        track = doc.track()
        for k in range(24):
            doc.call("add_clip", track=track, media=media, at=k * 5 * SEC)
        clips = [c["id"] for c in doc.call("get_project")["project"]["clips"]]
        doc.call("set_video", clips=clips, patch={"scale": 3.0})
        job = doc.client.call_with("export", {"project": doc.path, "path": str(path),
                                              "preset": "av1_webm"})["export_id"]
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
    check("W9", ok, detail)


def row_w10_w11(doc, out, w1):
    low = out / "w10-64k.webm"
    try:
        export(doc, low, audio_bitrate=64_000)
        full, small = audio_bytes(w1), audio_bytes(low)
        check("W10", small > 0 and full > 1.25 * small,
              f"default {full} audio bytes, 64 kb/s {small} ({full / max(small, 1):.2f} ×, "
              f"want > 1.25)")
    except mcp.ToolError as error:
        check("W10", False, str(error))
    loud = out / "w11.webm"
    try:
        export(doc, loud, loudness_lufs=-16)
        measured = integrated_lufs(loud)
        check("W11", measured is not None and abs(measured + 16) <= 1,
              f"integrated {measured} LUFS (want −16 ± 1)")
    except mcp.ToolError as error:
        check("W11", False, str(error))


def row_w12(instance, w1):
    brand = subprocess.run(["sysctl", "-n", "machdep.cpu.brand_string"], timeout=30,
                           capture_output=True, text=True).stdout.strip()
    family = re.match(r"Apple M(\d+)", brand)
    doc = None
    try:
        doc = av1.Doc(instance, "w12")
        try:
            answer = doc.call("import_media", path=str(w1))
        except mcp.ToolError as error:
            message = str(error).split(": ", 1)[-1]
            want = av1_sentence(w1.name)
            check("W12", family is not None and int(family.group(1)) <= 2 and message == want,
                  f"{brand}: refused {message!r} (want {want!r} on an M1 or M2)")
            return
        media = next(m for m in doc.call("get_project")["project"]["media"]
                     if m["id"] == answer["media"])
        ok = (family is not None and int(family.group(1)) >= 3
              and abs(media["duration"] / SEC - 5) <= 1 / 30
              and (media.get("width"), media.get("height")) == (640, 360)
              and media.get("has_audio"))
        check("W12", ok, f"{brand}: imported {media}")
    except (mcp.ToolError, KeyError, StopIteration) as error:
        check("W12", False, f"{brand}: {type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def row_w13(instance, out):
    path = out / "w13.webm"
    doc = None
    try:
        doc = text_doc(instance, "w13")
        done = export(doc, path)
        _, got = probe(path)
        rc, errors = av1.decode_errors(path)
        frames = av1.decoded_frames(path)
        _, segment = segment_of(path)
        entries = len(track_entries(segment)) if segment else None
        seen = [(s.get("codec_type"), s.get("codec_name"), s.get("width"), s.get("height"))
                for s in got]
        ok = (done.get("status") == "done" and seen == [("video", "av1", 640, 360)]
              and rc == 0 and not errors and frames == FRAMES and entries == 1)
        check("W13", ok, f"status {done.get('status')}; streams {seen}; ffmpeg rc {rc}, "
              f"{len(errors)} error lines {errors[:2]}; {frames} frames; {entries} TrackEntry")
    except (mcp.ToolError, ValueError) as error:
        check("W13", False, f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def long_doc(instance, name):
    """W9's project: AV.mov 24 times on a 1080p canvas at scale 3."""
    doc = av1.Doc(instance, name, 1920, 1080)
    media = doc.media(av1.AV)
    track = doc.track()
    for k in range(24):
        doc.call("add_clip", track=track, media=media, at=k * 5 * SEC)
    clips = [c["id"] for c in doc.call("get_project")["project"]["clips"]]
    doc.call("set_video", clips=clips, patch={"scale": 3.0})
    return doc


def fault_row(ident, app, logs, *, spec, want, preset, word, default, cancel, out, suffix):
    """One fault row: `long_doc` exported as `preset` on an instance launched with
    `-<default> <spec>`, timed from the fault's log line (`cancel`: `cancel_export` sent at
    the hold's line, timed from it); (ok, detail). Shared with `export_readers_proof.py`."""
    instance = av1.Instance(f"fault-{ident.lower()}", app, arguments=[f"-{default}", spec])
    logs.append(instance)
    out.mkdir(parents=True, exist_ok=True)
    path = out / f"{ident.lower()}{suffix}"
    path.unlink(missing_ok=True)
    doc, ok, detail = None, False, ""
    marker = "is held" if cancel else f"framejob {word} dev fault:"
    readers_line = f"framejob {word} dev readers: "

    def log_lines():
        try:
            return instance.log.read_text(errors="replace").splitlines()
        except OSError:
            return []
    try:
        if instance.client is None:
            raise RuntimeError(f"the app did not listen ({instance.log})")
        doc = long_doc(instance, ident.lower())
        job = doc.client.call_with("export", {"project": doc.path, "path": str(path),
                                              "preset": preset})["export_id"]
        deadline, fired = time.monotonic() + 300, None
        status = {}
        while time.monotonic() < deadline:
            if any(marker in line for line in log_lines()):
                fired = time.monotonic()
                break
            status = doc.client.call("export_status", export_id=job)
            if status.get("status") in ("done", "failed", "cancelled"):
                break
            time.sleep(0.05)
        if fired is None:
            raise RuntimeError(f"the fault never fired: {status}")
        if cancel:
            doc.client.call("cancel_export", export_id=job)
        final = {}
        while time.monotonic() - fired < 120:
            final = doc.client.call("export_status", export_id=job)
            if final.get("status") in ("done", "failed", "cancelled"):
                break
            time.sleep(0.05)
        took = time.monotonic() - fired
        time.sleep(0.5)    # the readers' line follows the pumps, on main
        readers = [line.split("readers: ", 1)[1] for line in log_lines()
                   if readers_line in line]
        exists = path.exists()
        named = want == "cancelled" or "dev fault" in json.dumps(final)
        ok = (final.get("status") == want and named and took <= FAULT_BOUND and not exists
              and readers == ["video 4, audio 4"])
        detail = (f"{spec}: status {final.get('status')!r} (want {want!r}) {took:.2f} s after "
                  f"the {'cancel' if cancel else 'fault'} (≤ {FAULT_BOUND}); the dev "
                  f"fault named: {named}; readers {readers} (want ['video 4, audio 4'], 4 = "
                  f"cancelled); a file at the path: {exists}; {json.dumps(final)[:300]}")
    except (mcp.ToolError, KeyError, RuntimeError, OSError) as error:
        detail = f"{spec}: {type(error).__name__}: {error}"
    finally:
        if doc is not None:
            try:
                doc.close()
            except Exception:  # an instance that died is the row's FAIL already
                pass
        instance.stop()
    return ok, detail


def row_fault(ident, app, logs):
    spec, want = FAULTS[ident]
    ok, detail = fault_row(ident, app, logs, spec=spec, want=want, preset="av1_webm",
                           word="webm", default="RCDevWebMFault", cancel=ident == "F3",
                           out=WORK / "out", suffix=".webm")
    check(ident, ok, detail)


def run_fault_rows(app, logs):
    for ident in FAULTS:
        row_fault(ident, app, logs)


def run_w_rows(app, logs):
    out = WORK / "out"
    av1.tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = av1.Instance("w", app)
    logs.append(instance)
    idents = [r for r in ROWS if r.startswith("W")]
    try:
        if instance.client is None:
            for ident in idents:
                check(ident, False, f"the app did not listen ({instance.log})")
            return
        doc = hlg = None
        try:
            doc = a1_doc(instance, "w1")
            w1 = rows_w1_w5(doc, out)
            row_w6(doc, out)
            doc.call("set_range", start=0, end=5 * SEC)
            row_w7(doc, out)
            if w1 is not None:
                row_w10_w11(doc, out, w1)
                row_w12(instance, w1)
            else:
                for ident in ("W10", "W11"):
                    check(ident, False, "W1's file is missing")
            hlg = a1_doc(instance, "w8", hlg=True)
            row_w8(hlg, out)
        except (mcp.ToolError, KeyError, IndexError) as error:
            for ident in idents:
                if ident not in results:
                    check(ident, False, f"A1's project could not be made: {error}")
        finally:
            for d in (doc, hlg):
                if d is not None:
                    d.close()
        row_w13(instance, out)
        row_w9(instance, out)
    finally:
        instance.stop()


def run_s4(app, logs):
    reading = av1.sheet_reading(app, "s4", '{"preset_id":"av1_webm"}')
    logs.append(reading["instance"])
    check("S4", not reading.get("error") and reading.get("format") == "AV1 (WebM)"
          and reading.get("footnote") == ["AV1 · WEBM · Balanced"],
          f"{reading.get('error') or ''} format {reading.get('format')!r}, footnote "
          f"{reading.get('footnote')}")


# ---- the probe ---------------------------------------------------------------------

def run_probe(sources):
    """P1–P5 and A1–A5: `webm_audio_probe.swift` built over `sources` and run."""
    import reference_build
    import swift_build
    out = WORK / ("probe" if Path(sources).resolve() == (ROOT / SOURCES).resolve()
                  else "probe-mutant")
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    text = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != text:
        entry.write_text(text)
    binary, answer = out / "webm-audio-probe", out / "answer.json"
    defines = reference_build.tree_defines(Path(sources).parent.parent, ["FRAMEJOB_DEV_TOOLS"])
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=binary, defines=defines)
        if not built.reused:
            print(f"probe built in {built.seconds:.0f} s", flush=True)
    except swift_build.SwiftBuildFailed as error:
        lines = [line for line in error.diagnostics if ": error:" in line]
        for ident in PROBE_ROWS:
            check(ident, False, "the probe did not build: "
                  + " | ".join(lines[:3] or list(error.diagnostics[:3]) or [str(error)]))
        return
    answer.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(answer)], 120)
    if ran["expired"] or ran["rc"] != 0 or not answer.exists():
        for ident in PROBE_ROWS:
            check(ident, False, "the probe did not run: "
                  + (ran["stdout"] + ran["stderr"]).strip()[-300:])
        return
    answered = {r["name"].split(" ")[0]: r for r in json.loads(answer.read_text())["rows"]}
    for ident in PROBE_ROWS:
        row = answered.get(ident)
        if row is None:
            check(ident, False, "the probe answered no such row")
        else:
            check(ident, row["ok"], f"{row['name'][len(ident) + 1:]}: {row['detail']}")


def readers_rows(idents, sources=ROOT / SOURCES, folder=WORK / "readers-probe"):
    """`webm_readers_probe.swift` beside the tree's two export shaders as
    `default.metallib`, `Blank.mp4`, `Silence.caf` and the fonts, run over AV.mov for the
    rows `idents`: [(ident, ok, detail)], one per ident, a FAIL for each when the instrument
    cannot run. Shared with `export_readers_proof.py` (R2, R3)."""
    import shutil
    import reference_build
    import swift_build

    def failed(why):
        return [(ident, False, why) for ident in idents]
    folder = Path(folder)
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    text = READERS_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != text:
        entry.write_text(text)
    resources = Path(sources).parent / "Resources"
    for name in ("Blank.mp4", "Silence.caf"):
        shutil.copy2(resources / name, folder / name)
    if (resources / "Fonts").is_dir():
        shutil.copytree(resources / "Fonts", folder / "Fonts", dirs_exist_ok=True)
    airs = []
    for shader in ("Compositor", "ExportI010"):
        air = folder / f"{shader}.air"
        step = run(["xcrun", "-sdk", "macosx", "metal", "-c",
                    resources / "Shaders" / f"{shader}.metal", "-o", air], 300)
        if step["rc"] != 0:
            return failed(f"{shader}.metal did not build: {step['stderr'][-300:]}")
        airs.append(air)
    step = run(["xcrun", "-sdk", "macosx", "metallib", *airs, "-o", folder / "default.metallib"],
               300)
    if step["rc"] != 0:
        return failed(f"the metallib did not build: {step['stderr'][-300:]}")
    binary, answer = folder / "webm-readers-probe", folder / "answer.json"
    try:
        defines = reference_build.tree_defines(Path(sources).parent.parent,
                                               ["FRAMEJOB_DEV_TOOLS"])
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=defines)
    except swift_build.SwiftBuildFailed as error:
        lines = [line for line in error.diagnostics if ": error:" in line]
        return failed("the probe did not build: "
                      + " | ".join(lines[:3] or list(error.diagnostics[:3]) or [str(error)]))
    answer.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(av1.AV), str(answer), ",".join(idents)], 600,
                      cwd=str(folder))
    if ran["expired"] or ran["rc"] != 0 or not answer.exists():
        return failed("the probe did not run: " + (ran["stdout"] + ran["stderr"]).strip()[-300:])
    answered = {r["name"].split(" ", 1)[0]: r for r in json.loads(answer.read_text())["rows"]}
    out = []
    for ident in idents:
        row = answered.get(ident)
        if row is None:
            out.append((ident, False, "the probe answered no such row"))
        else:
            out.append((ident, row["ok"], f"{row['name'][len(ident) + 1:]}: {row['detail']}"))
    return out


def run_readers_probe(sources=ROOT / SOURCES):
    """R1: two readers against one, through `readers_rows`."""
    for ident, ok, detail in readers_rows(("R1",), sources):
        check(ident, ok, detail)


def run_probe_mutant(name):
    """A probe mutant: `app/Sources` copied with the anchor replaced, the probe alone."""
    import shutil
    mutant = MUTANTS[name]
    copy = WORK / "mutant-probe"
    shutil.rmtree(copy, ignore_errors=True)
    sources = copy / "app" / "Sources"
    shutil.copytree(ROOT / SOURCES, sources)
    for path, anchor, replacement in mutant["anchors"]:
        target = copy / path
        text = target.read_text()
        if text.count(anchor) != 1:
            print(f"mutant {name}: the control could not be performed — the anchor occurs "
                  f"{text.count(anchor)} times in {path}")
            return 2
        target.write_text(text.replace(anchor, replacement))
    try:
        run_probe(sources)
    finally:
        shutil.rmtree(copy, ignore_errors=True)
    failing = sorted(k for k, v in results.items() if not v)
    named = sorted(mutant["rows"])
    print(f"mutant {name}: named {named}, failing {failing}")
    if any(results.get(r) is None for r in PROBE_ROWS) or (
            failing == PROBE_ROWS and named != PROBE_ROWS):
        print(f"mutant {name}: the control could not be performed — the probe failed whole")
        return 2
    if named == failing:
        print(f"MUTANT CAUGHT: {name}")
        return 1
    if not set(named) & set(failing):
        print(f"MUTANT SURVIVED: {name}")
        return 0
    print(f"MUTANT CAUGHT, NOT EXACTLY: {name}")
    return 3


# ---- the mutants -------------------------------------------------------------------

def run_mutant(name):
    if name not in MUTANTS:
        print(f"unknown mutant {name}; the mutants are {sorted(MUTANTS)}")
        return 2
    mutant = MUTANTS[name]
    if mutant.get("probe"):
        return run_probe_mutant(name)
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
        if mutant.get("fault"):
            run_fault_rows(app, logs)
        else:
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


# ---- main --------------------------------------------------------------------------

def run_rows(app, logs):
    run_w_rows(app, logs)
    run_s4(app, logs)
    run_fault_rows(app, logs)
    run_probe(ROOT / SOURCES)
    run_readers_probe()
    found = [(i.label, line) for i in logs for line in i.complaints()]
    check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="the av1_webm row (codec-export C3)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
    parser.add_argument("--mutant", help="one of " + ", ".join(MUTANTS))
    parser.add_argument("--probe", action="store_true", help="the P and A rows alone, no app")
    parser.add_argument("--readers", action="store_true",
                        help="R1 alone: two readers against one, no app")
    parser.add_argument("--faults", action="store_true", help="F1–F3 alone, on the app")
    args = parser.parse_args(argv)
    if args.app:
        os.environ[proof_app.ENV] = args.app
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)
    if args.readers:
        run_readers_probe()
        print(f"scores: {sum(results.values())}/{len(results)}")
        return 0 if all(results.values()) else 1
    if args.probe:
        run_probe(ROOT / SOURCES)
        print(f"scores: {sum(results.values())}/{len(results)}")
        return 0 if all(results.values()) else 1
    logs = []
    try:
        app = proof_app.bundle()
        proof_app.require_fresh(proof_app.executable(app))
    except (proof_app.StaleApp, ValueError, OSError) as error:
        check("W0", False, f"the app cannot be driven: {error}")
        print("scores: 0/1")
        return 1
    print(f"app {app}", flush=True)
    if args.faults:
        run_fault_rows(app, logs)
        print(f"scores: {sum(results.values())}/{len(results)}")
        return 0 if all(results.values()) else 1
    run_rows(app, logs)
    passed = sum(results.values())
    print(f"scores: {passed}/{len(results)}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
