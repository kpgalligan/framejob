#!/usr/bin/env python3
"""Road map "codec-export" C5 — the `vp9_alpha_webm` row: VP9 with alpha in WebM, libvpx's
8-bit Profile 0 picture and a second, frame-aligned libvpx stream of its alpha written as
each video block's BlockAdditional 1 with `AlphaMode` 1 by the core's WebM writer, with Opus
sound, G-35's straight alpha and the alpha rows' shape rule (spec §11 CX-17).

    python3 tools/proof/vp9_alpha_export_proof.py [--app debug|release|PATH]
    python3 tools/proof/vp9_alpha_export_proof.py --probe          # P1 alone, no app
    python3 tools/proof/vp9_alpha_export_proof.py --mutant NAME

Launches its own instances of the chosen app (`proof_app.py`: `--app`, else
`RC_PROOF_APP`, else Debug; a build older than its inputs is refused) on scratch sockets,
works under `tools/proof/work/vp9-alpha-export/`, closes every project it opens with
`discard: true` and stops each instance by its own PID. It reuses `vp9_export_proof.py`'s,
`webm_export_proof.py`'s and `av1_export_proof.py`'s helpers by import (the instance, the
documents, the exports, the ffprobe readers, the EBML walk, the sheet reading, the mutant
builder). ffprobe and ffmpeg (Homebrew, with the `libvpx-vp9` decoder, the only one that
reads a VP9 alpha) only READ the files, and make the DISC source.

The fixtures. "A1's project" is `webm_export_proof.py`'s (AV.mov, 640 × 360, 30 fps, 5 s,
under a two-second text clip, chapter markers "Intro" at 0 s and "Body" at 2.5 s): opaque.
CLEAR and FAINT are `hevc_alpha_proof.py`'s: a 640 × 360 transparent canvas with a red
200 × 120 card for a second, FAINT's at opacity 0.5. DISC is the spike's alpha source (S §4,
`mkalpha.sh`: testsrc2 whose alpha is a moving opaque disc over a 0–50 % ramp, 2 s at
30 fps) regenerated as ProRes 4444 at 640 × 360 and 1920 × 1080 and imported on a
transparent canvas of its size. TITLE is a 1920 × 1080 transparent canvas holding a
two-second text clip. Rows (`<ID> ok|FAIL — <detail>`, then `scores: n/m`; exit 0 iff all
passed):

* Z1 — every instance's log is silent (no `Frame Job: `, `Svt[` or `SVT-AV1: ` line).
* A1 — A1's project as `vp9_alpha_webm`: done; format `matroska,webm`; video `vp9`
  Profile 0 640 × 360 with ffprobe's stream tag `alpha_mode=1`; audio `opus`. The walk: the
  video TrackEntry's CodecID `V_VP9`, `MaxBlockAdditionID` 1, its Video's `AlphaMode` 1 and
  Colour 1/1/1 with Range 1 and BitsPerChannel 8; every video block a BlockGroup whose Block
  flags are 0 holding exactly one BlockMore with BlockAddID 1; a ReferenceBlock exactly on
  the blocks whose picture is not a VP9 KEY_FRAME, each the previous video block's time
  less its own.
* A2 — `ffmpeg -v error -c:v libvpx-vp9` decodes the file with no line, as `yuva420p`;
  150 video frames; exactly 240,000 audio samples (#337's length).
* A3 — keys every ⌊2·fps⌋ frames from frame 0 (blocks 0, 60 and 120, where a BlockGroup
  with no ReferenceBlock is a key), and each block's alpha payload's VP9 header (show_frame
  1, frame_type) is a KEY_FRAME exactly when the block is a key.
* A4 — the alpha, decoded by `libvpx-vp9`, against the same project's `prores_4444` alpha
  (rounded to 8 bits): DISC at 1920 × 1080, 1280 × 720 and 640 × 360 (three of the alpha
  level's size bands, CX-17 (6) as amended) and TITLE, each at the Low and the Maximum tier
  (`video_bitrate` 0.0386 and 0.1157 bits per pixel per frame): every frame's alpha PSNR
  ≥ 48.0 dB; and CLEAR's alpha exactly 0 at the corner and 255 at the card's centre on every
  frame. Each export's alpha share of the video bytes is printed, not scored.
* A5 — FAINT's card, decoded by `libvpx-vp9` with BT.709 video range to RGBA: alpha
  128 ± 3, red ≥ 250, green and blue ≤ 5 — straight colour, not halved (G-35); and A1's
  opaque project: its picture against `vp9_webm`'s, both decoded as yuv420p, each plane's
  mean absolute difference over frames 0–149 ≤ 6 codes, and its alpha 255 everywhere.
* A6 — V5's chapters ("Intro" 0.0–2.5 s, "Body" 2.5–5.0 s) and its 1 s – 3 s in/out
  export: 60 frames, 96,000 samples, the chapters clamped and rebased.
* A7 — V6's cancel: the 24-clip 1080p project, `cancel_export` while it encodes:
  `cancelled` within 10 s and no file at the path.
* A8 — a project holding only a 5 s text clip (no audio track): done; exactly one stream,
  `vp9` 640 × 360, tagged `alpha_mode=1`.
* A9 — the HLG doc (A1's project made HLG): the default export answers `dynamic_range`
  `sdr` and is Profile 0 `yuv420p` 8-bit with Colour 1/1/1; `dynamic_range: "hlg"` is refused
  in the core's sentence and leaves no file.
* A10 — CLEAR at `[640, 480]`, another shape: refused in `alphaAspectMismatch`'s sentence,
  no file.
* A11 — `encoder_speed: "faster"` refused in the core's sentence, no file; A1's answer
  carries no `encoder_speed`.
* A12 — `import_media` of A1's file: a 5.0 s 640 × 360 media with audio, whose render at
  3 s is A1's project's within 8/255 per RGB channel (the colour kept, every sample's sync
  flag the block's); and of CLEAR's file over a white canvas: the render at 0.5 s is black
  at the corner and red at the card — the alpha is dropped on import (CX-17 (7), the
  accepted limit, pinned).
* S1 — the export sheet in an HLG project pinned to `{"preset_id":"vp9_alpha_webm"}`:
  Format "VP9 with Alpha (WebM)", the Speed and Dynamic Range popups drawn disabled
  (`av1_export_proof.py` S2's rule: each one's darkest pixel more than 60 levels lighter
  than the Format popup's), Dynamic Range reading "SDR version", and a footnote naming VP9,
  WEBM and alpha.
* P1 — the probe `vp9_alpha_probe.swift` (no app): `VP9AlphaEncoder` over stub encoders
  pairs four matched frames (pts, key, both payloads); a pts mismatch and a key mismatch
  throw their sentences ("libvpx's alpha stream answered frame 2 where the picture's
  answered 1.", "libvpx's alpha frame 1 and picture frame 1 disagree on being a
  keyframe."), and one stream ending first throws; `VP9Encoder.keyInterval` is 48, 59, 60
  and 120 at 24, 29.97, 30 and 60 fps. A probe that will not build is P1's FAIL.

Mutants (`--mutant NAME`, a tree copy built as Debug with the named anchor replaced; exit 1
and `MUTANT CAUGHT` when exactly the named rows fail — `cargo-<file>` is that cargo test file
run in the copy):

  not-straightened      the frame never straightened before conversion: A5
  alpha-mode-unwritten  no `AlphaMode` in the video TrackEntry: A1, A8 (both read ffprobe's
                        `alpha_mode` tag), cargo webm_writer_alpha; not A2 (measured: ffmpeg's
                        libvpx decoder reads the BlockAdditional without AlphaMode)
  no-reference-block    no ReferenceBlock on any block, so every block reads as a key: A1,
                        A3, A12
  alpha-video-range     the alpha plane written in video range, 16 + 219·a: A4, and A5 (its
                        opaque alpha reads 235, not 255)
  alpha-cq-63           `alphaCQLevel(pixels:)` 63 at every size: A4
  alpha-cq-one-band     the size bands collapsed to the 1080p band's level (40): A4, on DISC
                        at 640 × 360 alone (measured: DISC 1280 × 720 reads 48.75 dB at 40)
  no-shape-guard        `ExportWebMWriter` without `checkAlphaSurvivesTheSize`: A10
  alpha-row-hdr         `vp9_alpha_webm` among the core's HDR_ROWS: A9, S1 (the Dynamic Range
                        popup live on HDR (HLG)), cargo dynamic_range

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import json
import math
import os
import re
import subprocess
import sys
import time
from array import array
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import vp9_export_proof as vp9  # noqa: E402
import av1_export_proof as av1  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import webm_export_proof as webm  # noqa: E402

WORK = HERE / "work" / "vp9-alpha-export"
av1.WORK = WORK            # the reused Instance, fixtures and mutant builder work here
webm.WORK = WORK
vp9.WORK = WORK
# The walk descends into BlockAdditions and BlockMore too (CX-17 (5)).
webm.MASTERS = webm.MASTERS | {0x75A1, 0xA6}
SEC = av1.SEC
PRESET = "vp9_alpha_webm"
FRAMES = 150
SAMPLES = 240_000
KEY_INTERVAL = 60          # ⌊2 · 30⌋
PSNR_FLOOR = 48.0
FRAME_BOUND = 6
RENDER_BOUND = 8
TIERS = {"Low": 0.0386, "Maximum": 0.1157}
REFUSED_SPEED = ("vp9_alpha_webm has no encoder speed; encoder_speed applies to av1 and "
                 "av1_webm")
REFUSED_HLG = ("vp9_alpha_webm is 8-bit and writes the SDR version; export dynamic_range "
               "\"hlg\" as hevc_10bit, av1, av1_webm, vp9_webm, prores_422 or prores_4444")
SHAPE_SENTENCE = ("An export that keeps transparency has to have the canvas's own shape. "
                  "This canvas is 640 × 360 and 640 × 480 is a different shape")
CARD_CENTRE = (320, 180)

ROWS = ["Z1", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A12",
        "S1", "P1"]

SOURCES = "app/Sources"
MUTANTS = {
    "not-straightened": {"rows": ["A5"], "anchors": [
        (f"{SOURCES}/ExportEncodePump.swift",
         "                guard !straightens || ExportStraightAlpha.straighten(pixels) else {\n",
         "                guard true || ExportStraightAlpha.straighten(pixels) else {\n")]},
    "alpha-mode-unwritten": {"rows": ["A1", "A8"], "cargo": "webm_writer_alpha", "anchors": [
        ("core/src/webm_ebml.rs", "            alpha_mode,\n", "")]},
    "no-reference-block": {"rows": ["A1", "A3", "A12"], "anchors": [
        ("core/src/webm_writer.rs",
         "                (!p.key).then(|| self.last_video_ms.unwrap_or(p.ms) as i64 - p.ms as i64);\n",
         "                (!p.key && false).then(|| self.last_video_ms.unwrap_or(p.ms) as i64 - p.ms as "
         "i64);\n")]},
    "alpha-video-range": {"rows": ["A4", "A5"], "anchors": [
        ("app/Resources/Shaders/ExportI010.metal",
         "    planes[u.alphaOffset + gid.y * u.lumaStride + gid.x] = uchar(round(255.0 * a));\n",
         "    planes[u.alphaOffset + gid.y * u.lumaStride + gid.x] = uchar(round(16.0 + 219.0 "
         "* a));\n")]},
    "alpha-cq-63": {"rows": ["A4"], "anchors": [
        (f"{SOURCES}/ExportVP9Encoder.swift", "        return band.level\n",
         "        return 63\n")]},
    "alpha-cq-one-band": {"rows": ["A4"], "anchors": [
        (f"{SOURCES}/ExportVP9Encoder.swift",
         "        let band = alphaCQBands.last(where: { $0.pixels <= pixels }) ?? "
         "alphaCQBands[0]\n",
         "        let band = alphaCQBands[2]\n")]},
    "no-shape-guard": {"rows": ["A10"], "anchors": [
        (f"{SOURCES}/ExportWebMWriter.swift",
         "        try ExportWriter.checkAlphaSurvivesTheSize(settings, canvas: canvas)\n", "")]},
    "alpha-row-hdr": {"rows": ["A9", "S1"], "cargo": "dynamic_range", "anchors": [
        ("core/src/dynamic_range.rs", 'pub(crate) const HDR_ROWS: [&str; 6] = [\n',
         'pub(crate) const HDR_ROWS: [&str; 7] = [\n'),
        ("core/src/dynamic_range.rs", '    "vp9_webm",\n',
         '    "vp9_webm",\n    "vp9_alpha_webm",\n')]},
}

results = {}


def check(ident, ok, detail):
    results[ident] = bool(ok)
    print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


def run(argv, seconds=600):
    return bounded.run([str(a) for a in argv], seconds)


def export(doc, path, **arguments):
    return av1.export(doc, path, **{"preset": PRESET, **arguments})


def refused(doc, path, **arguments):
    """The sentence an export is refused or fails in (at the call or in export_status),
    or None when it was written."""
    Path(path).unlink(missing_ok=True)
    try:
        doc.client.export_with({"project": doc.path, "path": str(path),
                                **{"preset": PRESET, **arguments}})
    except mcp.ToolError as error:
        return str(error)
    return None


def tier_rate(width, height, tier):
    return round(width * height * 30 * TIERS[tier])


# ---- the fixtures (also `work/codec-spike/alpha_vp9.py`'s) ---------------------------

def disc_source(width, height, path):
    """The spike's transparent source (`mkalpha.sh`) at `width` × `height` as ProRes 4444
    with alpha: testsrc2 whose alpha is an opaque disc (radius 300/1080 of the height)
    moving 500/1920 of the width either side of the centre over a 2 s period, over a ramp
    from 0 to 50 % across the width. Made once."""
    path = Path(path)
    if path.exists():
        return path
    path.parent.mkdir(parents=True, exist_ok=True)
    swing, radius = 500 * width / 1920, 300 * height / 1080
    alpha = (f"if(lt(hypot(X-{width / 2}-{swing}*sin(2*PI*T/2),Y-{height / 2}),{radius}),"
             "255,255*X/W*0.5)")
    ran = run(["ffmpeg", "-nostdin", "-v", "error", "-y", "-f", "lavfi", "-i",
               f"testsrc2=s={width}x{height}:r=30:d=2", "-vf",
               f"format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='{alpha}'",
               "-c:v", "prores_ks", "-profile:v", "4444", "-pix_fmt", "yuva444p10le",
               "-alpha_bits", "16", str(path)], 600)
    if ran["rc"] != 0 or not path.exists():
        raise RuntimeError(f"the DISC source could not be made: {ran['stderr'][-300:]}")
    return path


def clear_doc(instance, name, opacity=None):
    """CLEAR (or FAINT with `opacity`): a red 200 × 120 card for a second on a 640 × 360
    transparent canvas."""
    doc = av1.Doc(instance, name)
    doc.call("set_canvas", background=[0, 0, 0, 0])
    doc.call("add_shape_clip", track=doc.track(), at=0, duration=SEC,
             shape={"kind": "rectangle", "width": 200, "height": 120, "stroke": None,
                    "fill": [1, 0, 0, 1]})
    if opacity is not None:
        clips = doc.call("get_project")["project"]["clips"]
        doc.call("set_video", clips=[clips[0]["id"]], patch={"opacity": opacity})
    return doc


def disc_doc(instance, name, width, height):
    """DISC: the spike's source at its size on a transparent canvas of that size."""
    source = disc_source(width, height, WORK / "fixtures" / f"disc-{width}x{height}.mov")
    doc = av1.Doc(instance, name, width, height)
    doc.call("set_canvas", background=[0, 0, 0, 0])
    doc.call("add_clip", track=doc.track(), media=doc.media(source), at=0)
    return doc


def title_doc(instance, name):
    """TITLE: a two-second text clip on a 1920 × 1080 transparent canvas."""
    doc = av1.Doc(instance, name, 1920, 1080)
    doc.call("set_canvas", background=[0, 0, 0, 0])
    doc.call("add_text_clip", track=doc.track(), at=0, duration=2 * SEC,
             text={"content": "Frame Job"})
    return doc


# ---- reading the files -------------------------------------------------------------

def probe_alpha(path):
    """ffprobe's format, video and audio streams, with the video's `alpha_mode` tag."""
    ran = run(["ffprobe", "-v", "error", "-show_entries",
               "format=format_name,duration:stream=codec_type,codec_name,profile,pix_fmt,"
               "width,height,sample_rate,channels:stream_tags=alpha_mode", "-of", "json",
               path])
    got = json.loads(ran["stdout"] or "{}")
    streams = got.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), {})
    audio = next((s for s in streams if s.get("codec_type") == "audio"), {})
    return got.get("format", {}), video, audio, streams


def entry_alpha(path):
    """The video TrackEntry's CodecID, MaxBlockAdditionID and its Video's AlphaMode."""
    data, segment = webm.segment_of(path)
    for entry in webm.track_entries(segment):
        kind = webm.first(entry[4], 0x83)
        if kind and webm.uint(data, kind) == 1:
            codec = webm.first(entry[4], 0x86)
            name = data[codec[2]:codec[2] + codec[3]].decode("latin-1") if codec else None
            most = webm.first(entry[4], 0x55EE)
            video = webm.first(entry[4], 0xE0)
            mode = video and webm.first(video[4], 0x53C0)
            return (name, most and webm.uint(data, most), mode and webm.uint(data, mode),
                    webm.colour_of(data, segment))
    return None, None, None, None


def video_groups(path):
    """The video blocks in file order: [{ms, group, flags, payload, reference, additions}],
    `reference` the ReferenceBlock (signed) or None and `additions` [(BlockAddID, bytes)]."""
    data, segment = webm.segment_of(path)
    out = []
    for cluster in (e for e in (segment[4] if segment else []) if e[0] == 0x1F43B675):
        base = webm.uint(data, webm.first(cluster[4], 0xE7))
        for element in cluster[4]:
            reference, additions = None, []
            if element[0] == 0xA3:
                block = element
            elif element[0] == 0xA0:
                block = webm.first(element[4], 0xA1)
                ref = webm.first(element[4], 0xFB)
                if ref:
                    reference = int.from_bytes(data[ref[2]:ref[2] + ref[3]], "big",
                                               signed=True)
                adds = webm.first(element[4], 0x75A1)
                for more in (e for e in (adds[4] if adds else []) if e[0] == 0xA6):
                    ident, body = webm.first(more[4], 0xEE), webm.first(more[4], 0xA5)
                    additions.append((ident and webm.uint(data, ident),
                                      body and data[body[2]:body[2] + body[3]]))
            else:
                continue
            body = data[block[2]:block[2] + block[3]]
            track, n = webm.vint(body, 0, False)
            if track != 1:
                continue
            out.append({"ms": base + int.from_bytes(body[n:n + 2], "big", signed=True),
                        "group": element[0] == 0xA0, "flags": body[n + 2],
                        "payload": body[n + 3:], "reference": reference,
                        "additions": additions})
    return out


def libvpx(path, *args, seconds=600):
    """ffmpeg reading `path` through the libvpx VP9 decoder (the alpha's only reader)."""
    return subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-c:v", "libvpx-vp9", "-i",
                           str(path), *map(str, args)], capture_output=True, timeout=seconds)


def decoded_format(path, out):
    """The pixel format the libvpx decoder answers, as a rawvideo stream keeps it."""
    nut = out / (Path(path).stem + "-format.nut")
    nut.unlink(missing_ok=True)
    ran = libvpx(path, "-frames:v", "1", "-map", "0:v", "-c:v", "rawvideo", "-y", nut)
    if ran.returncode != 0 or not nut.exists():
        return None
    got = run(["ffprobe", "-v", "error", "-show_entries", "stream=pix_fmt", "-of",
               "csv=p=0", nut])
    nut.unlink(missing_ok=True)
    return got["stdout"].strip() or None


def libvpx_frames(path):
    ran = libvpx(path, "-map", "0:v", "-f", "framecrc", "-")
    if ran.returncode != 0:
        return None
    return sum(1 for line in ran.stdout.decode(errors="replace").splitlines()
               if line.strip() and not line.startswith("#"))


def alpha_planes(path, width, height):
    """The alpha of every frame through libvpx, 8-bit: a list of frames' bytes, or None."""
    ran = libvpx(path, "-vf", "alphaextract", "-f", "rawvideo", "-pix_fmt", "gray", "-")
    size = width * height
    if ran.returncode != 0 or not ran.stdout or len(ran.stdout) % size:
        return None
    return [ran.stdout[k:k + size] for k in range(0, len(ran.stdout), size)]


ROUND16 = None


def reference_alpha(path, width, height):
    """A ProRes 4444 file's alpha per frame, rounded to 8 bits: round(v · 255 / 65535) of
    its 16-bit reading (the decoder's depth widened by bit replication)."""
    global ROUND16
    if ROUND16 is None:
        ROUND16 = bytes((v * 255 + 32767) // 65535 for v in range(65536))
    ran = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(path), "-vf",
                          "alphaextract,format=gray16le", "-f", "rawvideo", "-pix_fmt",
                          "gray16le", "-"], capture_output=True, timeout=600)
    size = width * height
    if ran.returncode != 0 or not ran.stdout or len(ran.stdout) % (2 * size):
        return None
    words = array("H")
    words.frombytes(ran.stdout)
    if sys.byteorder != "little":
        words.byteswap()
    table = ROUND16
    eight = bytes(table[v] for v in words)
    return [eight[k:k + size] for k in range(0, len(eight), size)]


def alpha_share(path):
    """The alpha stream's share of the video bytes: its BlockAdditionals over them plus the
    Blocks' pictures, as "alpha share x % (n kb/s)" over the file's 2 s at 30 fps."""
    try:
        groups = video_groups(path)
    except (OSError, ValueError, IndexError, TypeError) as error:
        return f"alpha share unread ({type(error).__name__})"
    alpha = sum(len(body or b"") for g in groups for _, body in g["additions"])
    picture = sum(len(g["payload"]) for g in groups)
    if not groups or not alpha + picture:
        return "alpha share unread (no video blocks)"
    seconds = len(groups) / 30
    return (f"alpha share {100 * alpha / (alpha + picture):.1f} % "
            f"({alpha * 8 / seconds / 1000:.1f} kb/s)")


def psnr(a, b):
    """8-bit PSNR of two frames' bytes; inf when they are equal."""
    if a == b:
        return math.inf
    total = sum((x - y) * (x - y) for x, y in zip(a, b))
    return 10 * math.log10(255 * 255 * len(a) / total)


def rgba_centre(path, width, height, at):
    """The pixel at `at` of frame 15, libvpx-decoded and converted to RGBA through BT.709
    video range."""
    ran = libvpx(path, "-vf", "select=eq(n\\,15),scale=in_color_matrix=bt709:in_range=tv,"
                 "format=rgba", "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-")
    if ran.returncode != 0 or len(ran.stdout) != width * height * 4:
        return None
    i = (at[1] * width + at[0]) * 4
    return list(ran.stdout[i:i + 4])


def shown_key(payload):
    """`vp9_export_proof.py`'s reading: the payload's first frame is a shown KEY_FRAME."""
    return vp9.shown_key(payload)


# ---- the rows ----------------------------------------------------------------------

def rows_a1_a3(doc, out):
    path = out / "a1.webm"
    try:
        done = export(doc, path)
    except mcp.ToolError as error:
        for ident in ("A1", "A2", "A3", "A5", "A11", "A12"):
            check(ident, False, f"A1's export failed: {error}")
        return None, None
    fmt, video, audio, _ = probe_alpha(path)
    seen = (fmt.get("format_name"), video.get("codec_name"), video.get("profile"),
            video.get("width"), video.get("height"),
            (video.get("tags") or {}).get("alpha_mode"), audio.get("codec_name"))
    want = ("matroska,webm", "vp9", "Profile 0", 640, 360, "1", "opus")
    codec, most, mode, colour = entry_alpha(path)
    want_colour = {"matrix": 1, "bits": 8, "range": 1, "transfer": 1, "primaries": 1,
                   "mastering": False}
    blocks = video_groups(path)
    shapes = [i for i, b in enumerate(blocks)
              if not b["group"] or b["flags"] != 0 or len(b["additions"]) != 1
              or b["additions"][0][0] != 1 or not b["additions"][0][1]]
    references = []
    for i, b in enumerate(blocks):
        key = shown_key(b["payload"])
        want_ref = None if key else (blocks[i - 1]["ms"] - b["ms"] if i else None)
        if key is None or b["reference"] != want_ref or (not key and i == 0):
            references.append((i, b["reference"], want_ref))
    check("A1", done.get("status") == "done" and seen == want and codec == "V_VP9"
          and most == 1 and mode == 1 and colour == want_colour and len(blocks) == FRAMES
          and not shapes and not references,
          f"status {done.get('status')}, {done.get('bytes')} bytes; read {seen} (want {want}); "
          f"walk CodecID {codec!r}, MaxBlockAdditionID {most}, AlphaMode {mode}, Colour "
          f"{colour}; {len(blocks)} video blocks, not a BlockGroup of one BlockAddID 1 with "
          f"flags 0 at {shapes[:6]}; ReferenceBlock wrong at {references[:6]}")

    errors = libvpx(path, "-f", "null", "-")
    lines = [line for line in errors.stderr.decode(errors="replace").splitlines()
             if line.strip()]
    pix = decoded_format(path, out)
    frames = libvpx_frames(path)
    samples = webm.audio_samples(path)
    check("A2", errors.returncode == 0 and not lines and pix == "yuva420p"
          and frames == FRAMES and samples == SAMPLES,
          f"libvpx-vp9 rc {errors.returncode}, {len(lines)} lines {lines[:2]}; decoded as "
          f"{pix} (want yuva420p); {frames} frames (want {FRAMES}); {samples} audio samples "
          f"(want {SAMPLES})")

    keys = [i for i, b in enumerate(blocks) if b["reference"] is None]
    want_keys = list(range(0, len(blocks), KEY_INTERVAL))
    alpha_keys = [i for i, b in enumerate(blocks)
                  if b["additions"] and shown_key(b["additions"][0][1]) != (b["reference"] is None)]
    check("A3", blocks and keys == want_keys and not alpha_keys,
          f"key blocks (no ReferenceBlock) {keys} (want every {KEY_INTERVAL} from 0: "
          f"{want_keys}); an alpha payload's KEY_FRAME disagreeing with its block at "
          f"{alpha_keys[:6]}")
    return path, done


def row_a4(instance, out):
    lines, ok = [], True
    # (label, make, width, height): DISC at each of the alpha level's bands A4 reaches
    # (CX-17 (6) as amended: 640 × 360, 1280 × 720, 1920 × 1080) and TITLE, all scored.
    cases = [("DISC 1080p", lambda: disc_doc(instance, "a4-disc1080", 1920, 1080), 1920, 1080),
             ("TITLE", lambda: title_doc(instance, "a4-title"), 1920, 1080),
             ("DISC 1280×720", lambda: disc_doc(instance, "a4-disc720", 1280, 720), 1280, 720),
             ("DISC 640×360", lambda: disc_doc(instance, "a4-disc360", 640, 360), 640, 360)]
    for label, make, width, height in cases:
        doc = None
        try:
            doc = make()
            tag = label.split()[0].lower() + str(width)
            master = out / f"a4-{tag}-prores_4444.mov"
            export(doc, master, preset="prores_4444")
            reference = reference_alpha(master, width, height)
            if reference is None:
                ok = False
                lines.append(f"{label}: the ProRes 4444 alpha could not be read ✗")
                continue
            for tier in TIERS:
                path = out / f"a4-{tag}-{tier}.webm"
                export(doc, path, video_bitrate=tier_rate(width, height, tier))
                planes = alpha_planes(path, width, height)
                if planes is None or len(planes) != len(reference):
                    ok = False
                    lines.append(f"{label} {tier}: {None if planes is None else len(planes)} "
                                 f"alpha frames against {len(reference)} ✗")
                    continue
                scores = [psnr(a, b) for a, b in zip(planes, reference)]
                worst = min(scores)
                where = scores.index(worst)
                good = worst >= PSNR_FLOOR
                ok = ok and good
                finite = [s for s in scores if math.isfinite(s)]
                mean = sum(finite) / len(finite) if finite else math.inf
                lines.append(f"{label} {tier}: worst {worst:.2f} dB at frame {where}, mean of "
                             f"the finite {mean:.2f} dB, {len(scores) - len(finite)} exact, "
                             f"{alpha_share(path)} (printed)" + ("" if good else " ✗"))
        except (mcp.ToolError, KeyError, RuntimeError, OSError) as error:
            ok = False
            lines.append(f"{label}: {type(error).__name__}: {error} ✗")
        finally:
            if doc is not None:
                doc.close()
    doc = None
    try:
        doc = clear_doc(instance, "a4-clear")
        path = out / "a4-clear.webm"
        export(doc, path)
        planes = alpha_planes(path, 640, 360)
        x, y = CARD_CENTRE
        wrong = ([k for k, p in enumerate(planes) if p[0] != 0 or p[y * 640 + x] != 255]
                 if planes else None)
        good = planes is not None and len(planes) == 30 and not wrong
        ok = ok and good
        lines.append(f"CLEAR: {len(planes) if planes else None} frames, corner ≠ 0 or card ≠ "
                     f"255 at {wrong[:6] if wrong is not None else None}" + ("" if good else " ✗"))
    except (mcp.ToolError, KeyError, OSError, TypeError) as error:
        ok = False
        lines.append(f"CLEAR: {type(error).__name__}: {error} ✗")
    finally:
        if doc is not None:
            doc.close()
    check("A4", ok, f"alpha PSNR against prores_4444's, every frame ≥ {PSNR_FLOOR} dB: "
          + "; ".join(lines))


def row_a5(instance, doc, a1, out):
    lines, ok, faint = [], True, None
    try:
        faint = clear_doc(instance, "a5-faint", opacity=0.5)
        path = out / "a5-faint.webm"
        export(faint, path)
        centre = rgba_centre(path, 640, 360, CARD_CENTRE)
        good = (centre is not None and abs(centre[3] - 128) <= 3 and centre[0] >= 250
                and centre[1] <= 5 and centre[2] <= 5)
        ok = good
        lines.append(f"FAINT's centre RGBA {centre} (alpha 128 ± 3, red ≥ 250, green and "
                     f"blue ≤ 5)" + ("" if good else " ✗"))
    except (mcp.ToolError, KeyError) as error:
        ok = False
        lines.append(f"FAINT: {type(error).__name__}: {error} ✗")
    finally:
        if faint is not None:
            faint.close()
    try:
        if a1 is None:
            raise RuntimeError("A1's file is missing")
        plain = out / "a5-vp9_webm.webm"
        export(doc, plain, preset="vp9_webm")
        ours, theirs = vp9.decode8(a1, frames=FRAMES), vp9.decode8(plain, frames=FRAMES)
        diffs = (vp9.differences8(ours, theirs, 640, 360, FRAMES)
                 if ours and theirs else None)
        good = diffs is not None and all(d <= FRAME_BOUND for d in diffs)
        ok = ok and good
        lines.append("A1 against vp9_webm Y/Cb/Cr " + ("decode failed" if diffs is None else
                     "/".join(f"{d:.3f}" for d in diffs)) + f" (≤ {FRAME_BOUND})"
                     + ("" if good else " ✗"))
        planes = alpha_planes(a1, 640, 360)
        lowest = min(min(p) for p in planes) if planes else None
        good = planes is not None and len(planes) == FRAMES and lowest == 255
        ok = ok and good
        lines.append(f"A1's alpha: {len(planes) if planes else None} frames, least {lowest} "
                     "(want 255)" + ("" if good else " ✗"))
    except (mcp.ToolError, RuntimeError) as error:
        ok = False
        lines.append(f"A1: {type(error).__name__}: {error} ✗")
    check("A5", ok, "; ".join(lines))


def row_a6(doc, out, a1):
    listed = webm.chapters(a1) if a1 else None
    path = out / "a6-range.webm"
    try:
        doc.call("set_range", start=1 * SEC, end=3 * SEC)
        export(doc, path, range="in_out")
        frames, samples = libvpx_frames(path), webm.audio_samples(path)
        ranged = webm.chapters(path)
        check("A6", listed == webm.CHAPTERS and frames == 60 and samples == 96_000
              and ranged == webm.CHAPTERS_IN_OUT,
              f"chapters {listed} (want {webm.CHAPTERS}); the in/out export: {frames} frames "
              f"(want 60), {samples} samples (want 96000), chapters {ranged} (want "
              f"{webm.CHAPTERS_IN_OUT})")
    except mcp.ToolError as error:
        check("A6", False, str(error))
    finally:
        doc.call("set_range", start=0, end=5 * SEC)


def row_a7(instance, out):
    """V6's cancel, on this row: the 24-clip 1080p project."""
    path = out / "a7.webm"
    path.unlink(missing_ok=True)
    doc, ok, detail = None, False, ""
    try:
        doc = webm.long_doc(instance, "a7")
        job = doc.client.call_with("export", {"project": doc.path, "path": str(path),
                                              "preset": PRESET})["export_id"]
        ok, detail = cancel_while_encoding(doc, job, path)
    except (mcp.ToolError, KeyError) as error:
        detail = f"{type(error).__name__}: {error}"
    finally:
        if doc is not None:
            doc.close()
    check("A7", ok, detail)


def cancel_while_encoding(doc, job, path):
    """`vp9_export_proof.py` V6's reading: wait past the loudness measurement until the
    writer's progress moves, cancel, and time the stop."""
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
        return False, f"never running past the measurement with progress above it: {status}"
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
    ok = final.get("status") == "cancelled" and took <= vp9.CANCEL_BOUND and not exists
    return ok, (f"cancelled while encoding at progress {progress:.4f} (the writer started at "
                f"{floor}); status {final.get('status')!r} {took:.2f} s after cancel_export "
                f"(≤ {vp9.CANCEL_BOUND}); a file at the path: {exists}")


def row_a8(instance, out):
    path = out / "a8.webm"
    doc = None
    try:
        doc = webm.text_doc(instance, "a8")
        done = export(doc, path)
        _, video, _, streams = probe_alpha(path)
        seen = [(s.get("codec_type"), s.get("codec_name"), s.get("width"), s.get("height"))
                for s in streams]
        mode = (video.get("tags") or {}).get("alpha_mode")
        check("A8", done.get("status") == "done" and seen == [("video", "vp9", 640, 360)]
              and mode == "1", f"status {done.get('status')}; streams {seen}; alpha_mode {mode}")
    except (mcp.ToolError, ValueError) as error:
        check("A8", False, f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def row_a9(instance, out):
    doc, lines, ok = None, [], True
    try:
        doc = webm.a1_doc(instance, "a9", hlg=True)
        path = out / "a9.webm"
        done = export(doc, path)
        _, video, _, _ = probe_alpha(path)
        _, _, _, colour = entry_alpha(path)
        want_colour = {"matrix": 1, "bits": 8, "range": 1, "transfer": 1, "primaries": 1,
                       "mastering": False}
        good = (done.get("dynamic_range") == "sdr" and video.get("profile") == "Profile 0"
                and video.get("pix_fmt") == "yuv420p" and colour == want_colour)
        ok = good
        lines.append(f"default: answer dynamic_range {done.get('dynamic_range')!r}, "
                     f"{video.get('profile')} {video.get('pix_fmt')}, Colour {colour}"
                     + ("" if good else " ✗"))
        hlg = out / "a9-hlg.webm"
        sentence = refused(doc, hlg, dynamic_range="hlg")
        good = sentence is not None and REFUSED_HLG in sentence and not hlg.exists()
        ok = ok and good
        lines.append(f"hlg → {sentence!r}; a file {hlg.exists()}" + ("" if good else " ✗"))
    except (mcp.ToolError, KeyError) as error:
        ok = False
        lines.append(f"{type(error).__name__}: {error} ✗")
    finally:
        if doc is not None:
            doc.close()
    check("A9", ok, "; ".join(lines))


def row_a10(instance, out):
    doc = None
    try:
        doc = clear_doc(instance, "a10")
        path = out / "a10.webm"
        sentence = refused(doc, path, size=[640, 480])
        check("A10", sentence is not None and SHAPE_SENTENCE in sentence and not path.exists(),
              f"[640, 480] on the 640 × 360 CLEAR → {sentence!r}; a file {path.exists()}")
    except (mcp.ToolError, KeyError) as error:
        check("A10", False, f"{type(error).__name__}: {error}")
    finally:
        if doc is not None:
            doc.close()


def row_a11(doc, out, done):
    path = out / "a11.webm"
    sentence = refused(doc, path, encoder_speed="faster")
    left = path.exists()
    carried = done is not None and "encoder_speed" in done
    check("A11", sentence is not None and REFUSED_SPEED in sentence and not left
          and done is not None and not carried,
          f"encoder_speed on {PRESET} → {sentence!r}; a file left {left}; A1's answer carries "
          f"encoder_speed: {carried if done is not None else 'no answer'}")


def row_a12(instance, source, a1, out):
    lines, ok, docs = [], True, []
    try:
        if a1 is None:
            raise RuntimeError("A1's file is missing")
        doc = av1.Doc(instance, "a12")
        docs.append(doc)
        answer = doc.call("import_media", path=str(a1))
        found = next(m for m in doc.call("get_project")["project"]["media"]
                     if m["id"] == answer["media"])
        good = (abs(found["duration"] / SEC - 5) <= 1 / 30
                and (found.get("width"), found.get("height")) == (640, 360)
                and found.get("has_audio"))
        ok = good
        lines.append(f"A1's file: {found['duration'] / SEC:.3f} s {found.get('width')} × "
                     f"{found.get('height')}, audio {found.get('has_audio')}"
                     + ("" if good else " ✗"))
        doc.call("add_clip", track=doc.track(), media=found["id"], at=0)
        theirs, ours = out / "a12-source.png", out / "a12-import.png"
        source.call("render_frame", t=3 * SEC, path=str(theirs))
        doc.call("render_frame", t=3 * SEC, path=str(ours))
        a, b = vp9.rgb(theirs), vp9.rgb(ours)
        if not a or not b or len(a) != len(b):
            ok = False
            lines.append(f"the renders could not be read ({len(a or b'')}, {len(b or b'')}) ✗")
        else:
            means = [sum(abs(a[i] - b[i]) for i in range(c, len(a), 3)) / (len(a) / 3)
                     for c in range(3)]
            good = all(m <= RENDER_BOUND for m in means)
            ok = ok and good
            lines.append("its render at 3 s against A1's: R/G/B "
                         + "/".join(f"{m:.3f}" for m in means) + f" (≤ {RENDER_BOUND})"
                         + ("" if good else " ✗"))
        clear = clear_doc(instance, "a12-clear")
        docs.append(clear)
        clear_file = out / "a12-clear.webm"
        export(clear, clear_file)
        white = av1.Doc(instance, "a12-white")
        docs.append(white)
        white.call("set_canvas", background=[1, 1, 1, 1])
        media = white.media(clear_file)
        white.call("add_clip", track=white.track(), media=media, at=0)
        png = out / "a12-clear-over-white.png"
        white.call("render_frame", t=SEC // 2, path=str(png))
        pixels = vp9.rgb(png)
        if not pixels or len(pixels) != 640 * 360 * 3:
            ok = False
            lines.append("the CLEAR render could not be read ✗")
        else:
            corner = list(pixels[0:3])
            i = (CARD_CENTRE[1] * 640 + CARD_CENTRE[0]) * 3
            card = list(pixels[i:i + 3])
            good = all(c < 40 for c in corner) and card[0] > 200 and max(card[1:]) < 60
            ok = ok and good
            lines.append(f"CLEAR's file over white at 0.5 s: corner {corner} (black: the alpha "
                         f"dropped on import, the accepted limit), card {card} (red)"
                         + ("" if good else " ✗"))
    except (mcp.ToolError, KeyError, StopIteration, OSError, RuntimeError) as error:
        ok = False
        lines.append(f"{type(error).__name__}: {error} ✗")
    finally:
        for doc in docs:
            doc.close()
    check("A12", ok, "; ".join(lines))


def run_a_rows(app, logs):
    out = WORK / "out"
    av1.tree_copy.remove_tree(str(out))
    out.mkdir(parents=True)
    instance = av1.Instance("a", app)
    logs.append(instance)
    idents = [r for r in ROWS if r.startswith("A")]
    try:
        if instance.client is None:
            for ident in idents:
                check(ident, False, f"the app did not listen ({instance.log})")
            return
        doc = None
        try:
            doc = webm.a1_doc(instance, "a1")
            a1, done = rows_a1_a3(doc, out)
            row_a5(instance, doc, a1, out)
            row_a6(doc, out, a1)
            row_a11(doc, out, done)
            row_a12(instance, doc, a1, out)
        except (mcp.ToolError, KeyError, IndexError) as error:
            for ident in idents:
                if ident not in results:
                    check(ident, False, f"A1's project could not be made: {error}")
        finally:
            if doc is not None:
                doc.close()
        row_a4(instance, out)
        row_a9(instance, out)
        row_a10(instance, out)
        row_a8(instance, out)
        row_a7(instance, out)
    finally:
        instance.stop()


def run_s1(app, logs):
    reading = av1.sheet_reading(app, "s1", '{"preset_id":"vp9_alpha_webm"}', hlg=True)
    logs.append(reading["instance"])

    def lighter(dark):
        return (reading[dark] - reading["format_dark"]
                if reading.get(dark) is not None and reading.get("format_dark") is not None
                else None)

    speed, dynamic = lighter("speed_dark"), lighter("range_dark")
    note = " ".join(reading.get("footnote") or [])
    named = all(word in note for word in ("VP9", "WEBM", "alpha"))
    check("S1", not reading.get("error") and reading.get("format") == "VP9 with Alpha (WebM)"
          and speed is not None and speed > 60 and dynamic is not None and dynamic > 60
          and reading.get("range") == "SDR version" and named,
          f"{reading.get('error') or ''} format {reading.get('format')!r}; Speed "
          f"{reading.get('speed')!r} {speed} levels lighter than Format, Dynamic Range "
          f"{reading.get('range')!r} {dynamic} (> 60 is disabled); footnote "
          f"{reading.get('footnote')}")


# ---- the probe (P1) ----------------------------------------------------------------

P1_PAIRS = [[k, k in (0, 3), [0x50, k], [0xA1, k]] for k in range(4)]
P1_PTS = "libvpx's alpha stream answered frame 2 where the picture's answered 1."
P1_KEY = "libvpx's alpha frame 1 and picture frame 1 disagree on being a keyframe."
P1_ENDED = "libvpx's picture answered frame 1 after the other stream ended."
P1_INTERVALS = {"24": 48, "29.97": 59, "30": 60, "60": 120}


def run_probe(sources=ROOT / SOURCES):
    import reference_build
    import swift_build
    out = WORK / ("probe" if Path(sources).resolve() == (ROOT / SOURCES).resolve()
                  else "probe-mutant")
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    text = (HERE / "vp9_alpha_probe.swift").read_text()
    if not entry.exists() or entry.read_text() != text:
        entry.write_text(text)
    binary, answer = out / "vp9-alpha-probe", out / "answer.json"
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
    answer.unlink(missing_ok=True)
    ran = bounded.run([str(binary), str(answer)], 120)
    if ran["expired"] or ran["rc"] != 0 or not answer.exists():
        return check("P1", False, "the probe did not run: "
                     + (ran["stdout"] + ran["stderr"]).strip()[-300:])
    got = json.loads(answer.read_text())
    misses = []
    matched = got.get("matched", {})
    if matched.get("pairs") != P1_PAIRS or matched.get("error") != "no error":
        misses.append(f"matched {matched}")
    if got.get("pts") != P1_PTS or got.get("pts_pairs") != 1:
        misses.append(f"pts {got.get('pts')!r} after {got.get('pts_pairs')} pairs")
    if got.get("key") != P1_KEY or got.get("key_pairs") != 1:
        misses.append(f"key {got.get('key')!r} after {got.get('key_pairs')} pairs")
    if got.get("ended") != P1_ENDED:
        misses.append(f"ended {got.get('ended')!r}")
    if got.get("intervals") != P1_INTERVALS:
        misses.append(f"intervals {got.get('intervals')} (want {P1_INTERVALS})")
    check("P1", not misses, "four matched pairs; the pts, key and ended sentences; the key "
          "intervals at 24, 29.97, 30 and 60 fps: "
          + (f"misses {misses}" if misses else "every answer the expected one"))


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

def run_rows(app, logs, probe=True):
    run_a_rows(app, logs)
    run_s1(app, logs)
    if probe:
        run_probe()
    found = [(i.label, line) for i in logs for line in i.complaints()]
    check("Z1", not found, f"{len(logs)} instance logs; complaints {found[:4]}")


def main(argv=None):
    parser = argparse.ArgumentParser(description="the vp9_alpha_webm row (codec-export C5)")
    parser.add_argument("--app", help="debug, release or a .app path (default RC_PROOF_APP)")
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
        check("A0", False, f"the app cannot be driven: {error}")
        print("scores: 0/1")
        return 1
    print(f"app {app}", flush=True)
    run_rows(app, logs)
    passed = sum(results.values())
    print(f"scores: {passed}/{len(results)}")
    return 0 if all(results.values()) else 1


if __name__ == "__main__":
    sys.exit(main())
