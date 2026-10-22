#!/usr/bin/env python3
"""Spec §11 PR-11's pin (issue batch B102, #295): every frame Frame Job writes
as an image file carries the one BT.709 label, its pixels unchanged. Issue
batch B101 wrote this script as a measurement (what label a written frame
carried, which followed the sources); B102 scores every row to PR-11.

    python3 tools/proof/frame_label_proof.py [--app PATH] [--only F1,F5,...]
    python3 tools/proof/frame_label_proof.py capture DIR    # the CONTROL tree: every image file kept in DIR
    python3 tools/proof/frame_label_proof.py compare DIR [--only ...]   # adds P1, P2 and E3's pixels
    python3 tools/proof/frame_label_proof.py same-pixels A B            # no app
    python3 tools/proof/frame_label_proof.py [compare DIR] --mutant NAME

Each written file's label is read off the file (a PNG's `sRGB` or `iCCP` chunk
and the profile's name, else `sips -g profile`). Each file is decoded raw to
`rgb48le` by ffmpeg (which applies no profile) and again after `sips
--matchTo` the system's sRGB profile, and the two compared (mean and max |Δ|
in 8-bit levels, the 16-bit sample / 257) — B101's colour-managed read, still
printed.

Launches the app `proof_app` picks (Debug unless `RC_PROOF_APP=release`) on
a scratch socket of its own and stops only that process. **The instance runs
in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/frame_label/run/
home`; every package, frame and export is under `tools/proof/work/
frame_label/run/`, removed at the start and at exit. The fixtures are made
once under `tools/proof/work/frame_label/media/` and kept. No menu item is
performed and no default written. Every call is bounded (`CALL_BOUND`), every
ffmpeg, ffprobe and sips too. Every project is closed (`close_project`,
discard). This script never records the screen and spends nothing.

Fixtures (320×180, 30 fps, 1 s): `h264_none.mp4` (testsrc2, libx264
yuv420p, tags unknown ×3), `h264_709.mp4` and `prores_709.mov` (through
`bt709_fixture.make`: bt709 ×3), `prores_none.mov` (prores_ks profile 3
yuv422p10le, unknown ×3), `still8.png` (an opaque rgb24 testsrc2 frame) and
`still16.png` (an rgb48be ramp, written here). A fixture is kept only when
ffprobe reads what it should; a refusal is an instrument failure (exit 2).

PR-11's label: a PNG's (and an APNG's) `iCCP` named `LABEL_NAME`, exactly as
B101's F2 control carried it (the space the generator gives a BT.709-tagged
source); a JPEG's and a HEIC's `sips` profile `HDTV`; a GIF's `GIF_LABEL`
(PR-11's GIF clause, from E3's control).

Rows (each scene on a 320×180 30 fps canvas, rendered at 0.5 s):
- **F0** (no app): a scan of `app/Sources` (a mutant's copy's): `AgentServer+
  Render.swift` and `EditorViewController+SaveFrame.swift` each call
  `FrameWriter.writeFrame(` and never `FrameWriter.write(`, and
  `ExporterImageSequence.swift` calls `FrameWriter.labelled(`.
- **F1–F4**: `h264_none`, `h264_709`, `prores_none`, `prores_709` alone.
- **F5, F6**: `still8` fully covering `prores_none` / `prores_709` (#295's
  case); **F7**: `still8` over `h264_709`; **F8**: `still8` alone.
- **F9**: `still16` alone (spec §11 PR-9's reader).
- **F10**: `prores_709` with `{log: slog3}` (a converting composition).
  Each of F1–F10 passes when its PNG carries the label at its `DEPTH`
  (B101's table). **F6** also holds the pair rule: F5 and F6 carry equal
  labels, and their raw and matched reads are equal (|Δ| 0).
- **F11**: F1's, F2's and F9's frames written as `jpeg` and `heic`: profile
  `HDTV`, at `F11_DEPTH`.
- **E1**: an `h264` export of F1's and F2's projects: ffprobe's tags (read,
  printed).
- **E2**: an `apng` export of the same two: the file's `iCCP` is the label.
- **E3**: a `gif` export of the same two: its label is `GIF_LABEL`, and in
  `compare DIR` its raw decode equals DIR's GIF.
- **P1** (`compare DIR`): every image file DIR holds is written again and its
  raw decode (`rgba64le`) equals DIR's.
- **P2** (`compare DIR`): a file whose DIR copy already carried its PR-11
  label is byte-identical to it.
- **Z1** (CONTROL): no `Frame Job: ` line, every project closed.

`capture DIR` runs every row (the control is expected to FAIL F0, F1, F3, F5,
F6, F8, F9, F11 and E2) and copies every image file it wrote, with
`capture.json` (each file's label), into DIR. `same-pixels A B` launches no
app: every `png`, `jpg`, `heic` and `gif` present in both folders is decoded
raw (`rgba64le`), the max |Δ| printed beside both labels; it passes when at
least one file was compared and every max |Δ| is 0.

`--mutant NAME` follows log_proof.py's `build_mutant`: a COPY of the tree
(`tree_copy.make_copy`), each anchor asserted to occur exactly once, built
by the copy's own `make app-debug` (`make app` under `RC_PROOF_APP=release`);
every row runs on it (F0 scans the copy). MUTANT PASS when every named row
FAILED. `gif-flipped` runs as `compare DIR --mutant gif-flipped` against the
control's capture, so E3's pixels and P1 also score; when E3's control shows
a GIF carries no label and the flip moves neither E3's label nor its pixels,
the survivor is recorded as an equivalent mutant (precision_proof.py's
`jpeg-deep` wording), E3 and P1 staying the guards.

Exit 0 when every scored row passes (a mutant: caught); 1 when one failed (a
mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import json
import shutil
import struct
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import bt709_fixture  # noqa: E402
import hdr_proof as hdr  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/frame_label"
WORK = BASE / "run"
HOME = WORK / "home"
SCRATCH = WORK / "decoded"
MEDIA = BASE / "media"
CALL_BOUND = 300
TOOL_BOUND = 120
BUILD_BOUND = 1500
W, H = 320, 180
SEC = 600_000
T = SEC // 2
SRGB = "/System/Library/ColorSync/Profiles/sRGB Profile.icc"
ROWS = ["F0", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "E1", "E2",
        "E3", "P1", "P2", "Z1"]
COMPARE_ROWS = {"P1", "P2"}
IMAGE_SUFFIXES = {".png", ".jpg", ".heic", ".gif"}
# PR-11's label: a PNG's `iCCP` profile name as B101's F2 control carried it,
# and `sips`'s profile name for a JPEG and a HEIC (B101's F11 of F2).
LABEL_NAME = "kCGColorSpaceCoreMedia709"
PNG_LABEL = f"iCCP '{LABEL_NAME}'"
SIPS_LABEL = "HDTV"
# PR-11's GIF clause, from E3's control (B102, the unchanged tree): a GIF
# export carries no colour label (no `ICCRGBG1` extension; `sips` reads the
# sRGB ImageIO assumes for every GIF), so a GIF is left as it is.
GIF_LABEL = "no ICC extension; sips profile 'sRGB IEC61966-2.1'"
# row: (label, [fixtures back to front], Camera Log of the first or None)
SCENES = {"F1": ("h264_none alone", ["h264_none"], None),
          "F2": ("h264_709 alone", ["h264_709"], None),
          "F3": ("prores_none alone", ["prores_none"], None),
          "F4": ("prores_709 alone", ["prores_709"], None),
          "F5": ("still8 fully covering prores_none", ["prores_none", "still8"], None),
          "F6": ("still8 fully covering prores_709", ["prores_709", "still8"], None),
          "F7": ("still8 fully covering h264_709", ["h264_709", "still8"], None),
          "F8": ("still8 alone", ["still8"], None),
          "F9": ("still16 alone", ["still16"], None),
          "F10": ("prores_709 with {log: slog3}", ["prores_709"], {"log": "slog3"})}
# Each row's PNG depth, B101's table (PR-11 moves the label alone).
DEPTH = {"F1": 8, "F2": 8, "F3": 16, "F4": 16, "F5": 16, "F6": 16, "F7": 8, "F8": 8, "F9": 16,
         "F10": 16}
# F11's `sips` bitsPerSample: JPEG 8; HEIC 8, but 10 for F9's deep still (PR-9's S10).
F11_DEPTH = {("F1", "jpeg"): "8", ("F1", "heic"): "8", ("F2", "jpeg"): "8",
             ("F2", "heic"): "8", ("F9", "jpeg"): "8", ("F9", "heic"): "10"}
RENDER_SWIFT = "app/Sources/AgentServer+Render.swift"
SAVE_SWIFT = "app/Sources/EditorViewController+SaveFrame.swift"
SEQUENCE_SWIFT = "app/Sources/ExporterImageSequence.swift"
WRITER_SWIFT = "app/Sources/FrameWriter.swift"
# name: ([(file, anchor, replacement), …], the rows that must fail).
MUTANTS = {
    # render_frame writes through the unlabelled `write`.
    "render-unlabelled": ([(RENDER_SWIFT,
                            "            try FrameWriter.writeFrame(image, as: format, to: url)\n",
                            "            try FrameWriter.write(image, as: format, to: url)\n")],
                          ["F0", "F1"]),
    # Save Frame… writes through the unlabelled `write` (no proof can press it).
    "saveframe-unlabelled": ([(SAVE_SWIFT,
                               "                result = Result { try FrameWriter.writeFrame(image, "
                               "as: format, to: url) }\n",
                               "                result = Result { try FrameWriter.write(image, as: "
                               "format, to: url) }\n")], ["F0"]),
    # An APNG's frames left as they are.
    "apng-unlabelled": ([(SEQUENCE_SWIFT, "        case .apng: return true\n",
                          "        case .apng: return false\n")], ["E2"]),
    # `frameSpace` as the other variant A4 names, `CGColorSpace.itur_709`.
    "label-itur709": ([(WRITER_SWIFT,
                        "        return CVImageBufferCreateColorSpaceFromAttachments(attachments)?"
                        ".takeRetainedValue()\n            ?? CGColorSpace(name: "
                        "CGColorSpace.itur_709)!\n",
                        "        return CGColorSpace(name: CGColorSpace.itur_709)!\n")],
                      ["F1", "F2"]),
    # A GIF's frames labelled too (run as `compare DIR --mutant gif-flipped`).
    "gif-flipped": ([(SEQUENCE_SWIFT, "        case .gif: return false\n",
                      "        case .gif: return true\n")], ["E3"]),
}
UNKNOWN = {"color_primaries": "unknown", "color_transfer": "unknown", "color_space": "unknown"}
rows = {}
selected = set(ROWS)
REFUSED = {}


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def attempt(client, tool, arguments):
    try:
        # `export` answers an id since #326; the helper follows it to the file.
        answer = (client.export_with(arguments) if tool == "export"
                  else client.call_with(tool, arguments))
        return {"ok": True, "reply": answer}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


# ---- fixtures -------------------------------------------------------------------

def tags_of(path):
    probe = bt709_fixture.stream(path)
    return {k: probe.get(k, "unknown") for k in UNKNOWN}, probe


def untagged(path, graph, codec, want):
    """`path` from ffmpeg `graph` + `codec` with every tag `unknown`, kept only
    when ffprobe reads `want` and unknown ×3; else None."""
    if not path.exists():
        made = bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *graph, *codec,
                            "-color_primaries", "unknown", "-color_trc", "unknown",
                            "-colorspace", "unknown", str(path)], TOOL_BOUND)
        if made["rc"] != 0 or not path.exists():
            REFUSED[path.name] = f"ffmpeg: rc {made['rc']} {made['stderr'][-300:]}"
            path.unlink(missing_ok=True)
            return None
    tags, probe = tags_of(path)
    wrong = {k: probe.get(k) for k, v in want.items() if probe.get(k) != v}
    if wrong or tags != UNKNOWN:
        REFUSED[path.name] = f"ffprobe read {wrong or 'as wanted'}, tags {tags}"
        path.unlink(missing_ok=True)
        return None
    print(f"       {path.name} kept: {probe.get('codec_name')} {probe.get('pix_fmt')}, tags "
          f"{bt709_fixture.tags(probe)}", flush=True)
    return path


def write_png16(path):
    """A 16-bit RGB (rgb48be) horizontal ramp, W×H, no colour chunk."""
    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))
    row = b"".join(struct.pack(">HHH", v, v, 65535 - v)
                   for v in (round(65535 * x / (W - 1)) for x in range(W)))
    raw = b"".join(b"\x00" + row for _ in range(H))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 16, 2,
                                                                       0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
    return path


def fixtures():
    """{name: path}; a refused fixture is missing and named in REFUSED."""
    MEDIA.mkdir(parents=True, exist_ok=True)
    source = ["-f", "lavfi", "-i", f"testsrc2=size={W}x{H}:rate=30:duration=1"]
    tagged = ["-f", "lavfi", "-i",
              f"testsrc2=size={W}x{H}:rate=30:duration=1,{bt709_fixture.SETPARAMS}"]
    x264 = ["-c:v", "libx264", "-pix_fmt", "yuv420p"]
    prores = ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"]
    made = {
        "h264_none": untagged(MEDIA / "h264_none.mp4", source, x264,
                              {"codec_name": "h264", "pix_fmt": "yuv420p"}),
        "prores_none": untagged(MEDIA / "prores_none.mov", source, prores,
                                {"codec_name": "prores", "pix_fmt": "yuv422p10le"}),
    }
    for name, codec, want, pix_fmt in (
            ("h264_709.mp4", x264, {"codec_name": "h264", "pix_fmt": "yuv420p"}, "yuv420p"),
            ("prores_709.mov", prores, {"codec_name": "prores", "pix_fmt": "yuv422p10le"},
             "yuv422p10le")):
        path, why = bt709_fixture.make(MEDIA / name, tagged, codec, want, pix_fmt, TOOL_BOUND)
        made[name.split(".")[0]] = path
        if path is None:
            REFUSED[name] = why
    still8 = MEDIA / "still8.png"
    if not still8.exists():
        bounded.run(["ffmpeg", "-nostdin", "-v", "error", "-y", *source, "-frames:v", "1",
                     "-pix_fmt", "rgb24", str(still8)], TOOL_BOUND)
    probe = bt709_fixture.stream(still8) if still8.exists() else {}
    made["still8"] = still8 if probe.get("pix_fmt") == "rgb24" else None
    if made["still8"] is None:
        REFUSED["still8.png"] = f"ffprobe read {probe}"
    still16 = MEDIA / "still16.png"
    if not still16.exists():
        write_png16(still16)
    probe = bt709_fixture.stream(still16)
    made["still16"] = still16 if probe.get("pix_fmt") == "rgb48be" else None
    if made["still16"] is None:
        REFUSED["still16.png"] = f"ffprobe read {probe}"
    return {k: v for k, v in made.items() if v is not None}


# ---- reading a written file -----------------------------------------------------

def png_chunks(path):
    """[(kind, data)] of a PNG (an APNG too), or [] when it is not one."""
    data = Path(path).read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return []
    chunks, at = [], 8
    while at + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[at:at + 8])
        chunks.append((kind.decode("latin-1"), data[at + 8:at + 8 + length]))
        at += 12 + length
    return chunks


def label(path):
    """(depth, the label) of a written file."""
    chunks = png_chunks(path)
    if chunks:
        kinds = [k for k, _ in chunks]
        ihdr = dict(chunks).get("IHDR", b"")
        depth = ihdr[8] if len(ihdr) > 8 else None
        if "iCCP" in kinds:
            name = dict(chunks)["iCCP"].split(b"\0", 1)[0].decode("latin-1")
            text = f"iCCP '{name}'"
        elif "sRGB" in kinds:
            text = f"sRGB chunk (intent {dict(chunks)['sRGB'][0]})"
        else:
            text = "no colour chunk"
        extra = [k for k in kinds if k in ("cHRM", "gAMA", "cICP", "eXIf")]
        return depth, text + (f"; also {extra}" if extra else "")
    ran = bounded.run(["sips", "-g", "profile", "-g", "bitsPerSample", str(path)], TOOL_BOUND)
    lines = dict(line.strip().split(": ", 1) for line in ran["stdout"].splitlines()
                 if ": " in line)
    text = f"sips profile '{lines.get('profile')}'"
    if Path(path).suffix.lower() == ".gif":
        # A GIF's only colour label is an `ICCRGBG1` application extension;
        # without one, ImageIO (and so `sips`) reads it as sRGB (B102's E3).
        carried = b"ICCRGBG1" in Path(path).read_bytes()
        text = f"{'an' if carried else 'no'} ICC extension; {text}"
    return lines.get("bitsPerSample"), text


def decoded(path):
    """`path`'s first frame as rgb48le samples (ffmpeg applies no profile); a
    JPEG or HEIC goes through `sips -s format png` first, which keeps its
    profile and its values. None when it does not read."""
    source = Path(path)
    if not png_chunks(source):
        source = WORK / f"{Path(path).stem}-{Path(path).suffix[1:]}-plain.png"
        bounded.run(["sips", "-s", "format", "png", str(path), "--out", str(source)], TOOL_BOUND)
    data = bt709_fixture.decode(source, "rgb48le") if source.exists() else None
    return data[:W * H * 6] if data and len(data) >= W * H * 6 else None


def matched(path):
    """`path` after `sips --matchTo` the system sRGB profile, as a PNG."""
    out = WORK / f"{Path(path).stem}-{Path(path).suffix[1:]}-matched.png"
    out.unlink(missing_ok=True)
    ran = bounded.run(["sips", "-s", "format", "png", "--matchTo", SRGB, str(path), "--out",
                       str(out)], TOOL_BOUND)
    return out if ran["rc"] == 0 and out.exists() else None


def delta(a, b):
    """(mean, max) |a − b| over every sample, in 8-bit levels."""
    if a is None or b is None or len(a) != len(b):
        return None
    va = struct.unpack(f"<{len(a) // 2}H", a)
    vb = struct.unpack(f"<{len(b) // 2}H", b)
    gaps = [abs(x - y) for x, y in zip(va, vb)]
    return round(sum(gaps) / len(gaps) / 257, 3), round(max(gaps) / 257, 3)


def read(path):
    """A written file's figures: depth, label, raw, matched, raw → matched Δ."""
    depth, text = label(path)
    raw = decoded(path)
    match = matched(path)
    match_raw = decoded(match) if match else None
    return {"depth": depth, "label": text, "raw": raw, "matched": match_raw,
            "delta": delta(raw, match_raw), "matched_label": label(match) if match else None}


def shown(figures):
    depth, text = figures["matched_label"] or (None, None)
    return (f"depth {figures['depth']}, {figures['label']}; matched to sRGB: depth {depth}, "
            f"{text}; raw → matched |Δ| mean/max {figures['delta']}")


# ---- the scenes -----------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.made = attempt(client, "new_project", {"path": str(self.path)})["ok"]
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        canvas = self.project().get("canvas") or {}
        self.ok = self.made and canvas.get("width") == W and canvas.get("height") == H
        self.why = None if self.ok else "the project or its canvas was not made"

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def track(self, index):
        """The index-th track's id, adding tracks as needed."""
        while len(self.project().get("tracks") or []) <= index:
            if not self.call("add_track")["ok"]:
                return None
        return (self.project().get("tracks") or [])[index].get("id")

    def place(self, path, index, color=None):
        media = reply(self.call("import_media", path=str(path))).get("media")
        track = self.track(index) if media is not None else None
        if track is None:
            self.ok, self.why = False, f"import {Path(path).name}"
            return None
        if color is not None and not self.call("set_media_color", media=media,
                                                 color=color)["ok"]:
            self.ok, self.why = False, f"set_media_color on {Path(path).name}"
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=track, media=media, at=0)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not got["ok"] or len(new) != 1:
            self.ok, self.why = False, f"add_clip {Path(path).name}: {got.get('error')}"
            return None
        return new[0]

    def render(self, tag, **extra):
        suffix = {"jpeg": "jpg", "heic": "heic"}.get(extra.get("format"), "png")
        out = WORK / f"{tag}.{suffix}"
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=T, path=str(out), **extra)
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def export(self, tag, preset, suffix):
        out = WORK / f"{tag}.{suffix}"
        out.unlink(missing_ok=True)
        got = self.call("export", preset=preset, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       export {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def close(self):
        return attempt(self.client, "close_project", {"project": str(self.path),
                                                       "discard": True})["ok"]


def png_labelled(figures, depth):
    """(passes, why): `figures`' file carries PR-11's PNG label at `depth`."""
    if figures is None or figures["raw"] is None:
        return False, "not read"
    misses = []
    if not figures["label"].startswith(PNG_LABEL):
        misses.append(f"label {figures['label']!r}, not {PNG_LABEL!r}")
    if figures["depth"] != depth:
        misses.append(f"depth {figures['depth']}, not {depth}")
    return not misses, "; ".join(misses)


def run(client, media, state):
    """Every selected row; True when every project closed. Every image file
    written is listed in state["files"] ({name: path})."""
    closed = True
    frames = {}
    files = state.setdefault("files", {})
    keep = {"F1", "F2"} if selected & {"F11", "E1", "E2", "E3", "P1", "P2"} else set()
    if selected & {"F11", "P1", "P2"}:
        keep.add("F9")
    docs = {}
    verdicts = {}
    for row, (title, names, color) in SCENES.items():
        if row not in selected and row not in keep:
            continue
        missing = [n for n in names if n not in media]
        if missing:
            verdicts[row] = (title, False, f"fixtures refused: {missing}")
            continue
        doc = Doc(client, row.lower())
        for index, name in enumerate(names):
            if doc.ok:
                doc.place(media[name], index, color if index == 0 else None)
        png = doc.render(row.lower()) if doc.ok else None
        if row in keep:
            docs[row] = doc
        else:
            closed = doc.close() and closed
        figures = read(png) if png else None
        if png:
            files[png.name] = png
        frames[row] = figures
        good, why = png_labelled(figures, DEPTH[row])
        verdicts[row] = (title, good, (shown(figures) if figures else
                                       f"not reached: {doc.why or 'no render'}")
                         + (f"\n       {why}" if why else ""))
    for first, second in (("F1", "F2"), ("F5", "F6")):
        a, b = frames.get(first), frames.get(second)
        if a and b:
            raw, match = delta(a["raw"], b["raw"]), delta(a["matched"], b["matched"])
            print(f"       pair {first}/{second}: labels {a['label']!r} / {b['label']!r}; raw "
                  f"|Δ| mean/max {raw}; matched |Δ| mean/max {match}", flush=True)
            if second == "F6" and "F6" in verdicts:
                title, good, detail = verdicts["F6"]
                pair = (a["label"] == b["label"] and raw is not None and raw[1] == 0
                        and match is not None and match[1] == 0)
                verdicts["F6"] = (title, good and pair, detail + (
                    "" if pair else f"\n       the pair rule fails: F5/F6 labels "
                    f"{a['label']!r} / {b['label']!r}, raw {raw}, matched {match}"))
    if "F6" in verdicts and not (frames.get("F5") and frames.get("F6")):
        title, _, detail = verdicts["F6"]
        verdicts["F6"] = (title, False, detail + "\n       the pair rule needs F5 and F6 read")
    for row, (title, good, detail) in verdicts.items():
        if row in selected:
            depth = DEPTH[row]
            check(f"{row} {title}: labelled {PNG_LABEL} (PR-11) at depth {depth}"
                  + ("; F5/F6's pair equal" if row == "F6" else ""), good, detail)
    if selected & {"F11", "P1", "P2"}:
        figures, misses = {}, []
        for row in ("F1", "F2", "F9"):
            for kind in ("jpeg", "heic"):
                doc = docs.get(row)
                out = doc.render(f"{row.lower()}-{kind}", format=kind) if doc else None
                got = read(out) if out else None
                if out:
                    files[out.name] = out
                figures[f"{row} {kind}"] = shown(got) if got else None
                want = F11_DEPTH[(row, kind)]
                if got is None or got["raw"] is None:
                    misses.append(f"{row} {kind}: not read")
                elif got["label"] != f"sips profile '{SIPS_LABEL}'" or str(got["depth"]) != want:
                    misses.append(f"{row} {kind}: {got['label']}, depth {got['depth']} (want "
                                  f"'{SIPS_LABEL}', {want})")
        check(f"F11 F1's, F2's and F9's frames as jpeg and heic: profile '{SIPS_LABEL}' (PR-11) "
              "at F11_DEPTH", not misses,
              "; ".join(f"{k}: {v}" for k, v in figures.items()) + (
                  f"\n       misses {misses}" if misses else ""))
    if "E1" in selected:
        figures = {}
        for row in ("F1", "F2"):
            out = docs[row].export(f"{row.lower()}-h264", "h264", "mp4") if row in docs else None
            figures[row] = bt709_fixture.tags(bt709_fixture.stream(out)) if out else None
        check("E1 an h264 export of F1's and F2's projects: ffprobe's tags (transfer/primaries/"
              "matrix)", all(figures.values()), f"{figures}")
    if selected & {"E2", "P1", "P2"}:
        figures, misses = {}, []
        for row in ("F1", "F2"):
            out = docs[row].export(f"{row.lower()}-apng", "apng", "png") if row in docs else None
            if out:
                files[out.name] = out
            text = label(out)[1] if out else None
            figures[row] = (f"{label(out)}; chunks {[k for k, _ in png_chunks(out)][:8]}"
                            if out else None)
            if text is None or not text.startswith(PNG_LABEL):
                misses.append(f"{row}: {text}")
        check(f"E2 an apng export of F1's and F2's projects: the file's iCCP is {PNG_LABEL} "
              "(PR-11)", not misses, f"{figures}" + (f"\n       misses {misses}" if misses
                                                      else ""))
    if selected & {"E3", "P1", "P2"}:
        figures, misses = {}, []
        for row in ("F1", "F2"):
            out = docs[row].export(f"{row.lower()}-gif", "gif", "gif") if row in docs else None
            if out:
                files[out.name] = out
            text = label(out)[1] if out else None
            line = f"{label(out)}" if out else "not written"
            if text != GIF_LABEL:
                misses.append(f"{row}: label {text!r}, not {GIF_LABEL!r}")
            if state.get("control") is not None and out:
                want = state["control"] / out.name
                gap = delta(decode_full(out), decode_full(want)) if want.exists() else None
                line += f"; raw |Δ| mean/max against DIR's {gap}"
                if gap is None or gap[1] != 0:
                    misses.append(f"{row}: raw decode against DIR's {gap}")
            figures[row] = line
        check(f"E3 a gif export of F1's and F2's projects: label {GIF_LABEL!r} (PR-11's GIF "
              "clause)" + ("; raw decode equal to DIR's" if state.get("control") else ""),
              not misses, f"{figures}" + (f"\n       misses {misses}" if misses else ""))
    for doc in docs.values():
        closed = doc.close() and closed
    state["closed"] = closed
    return closed


# ---- F0, P1, P2, same-pixels ----------------------------------------------------

def run_f0(sources):
    """F0: the source scan."""
    misses = []
    for name in (RENDER_SWIFT, SAVE_SWIFT):
        text = (sources / Path(name).name).read_text()
        if "FrameWriter.writeFrame(" not in text:
            misses.append(f"{Path(name).name} does not call FrameWriter.writeFrame(")
        if "FrameWriter.write(" in text:
            misses.append(f"{Path(name).name} calls FrameWriter.write(")
    if "FrameWriter.labelled(" not in (sources / Path(SEQUENCE_SWIFT).name).read_text():
        misses.append("ExporterImageSequence.swift does not call FrameWriter.labelled(")
    check("F0 render_frame and Save Frame… write through FrameWriter.writeFrame and never "
          "FrameWriter.write; the image sequence calls FrameWriter.labelled (a source scan of "
          f"{sources})", not misses, f"{misses or 'all three as PR-11 says'}")


def decode_full(path):
    """`path`'s first frame, every sample, as `rgba64le` (ffmpeg applies no
    profile); a JPEG or HEIC through `sips -s format png` first. None when it
    does not read."""
    if path is None or not Path(path).exists():
        return None
    source = Path(path)
    if source.suffix.lower() in (".jpg", ".jpeg", ".heic"):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        source = SCRATCH / f"{source.parent.name}-{source.stem}-{source.suffix[1:]}-full.png"
        source.unlink(missing_ok=True)
        bounded.run(["sips", "-s", "format", "png", str(path), "--out", str(source)], TOOL_BOUND)
    return bt709_fixture.decode(source, "rgba64le") if source.exists() else None


def pr11_label(name):
    """The label PR-11 gives a file of this name."""
    suffix = Path(name).suffix.lower()
    if suffix == ".gif":
        return GIF_LABEL
    if suffix == ".png":
        return PNG_LABEL
    return f"sips profile '{SIPS_LABEL}'"


def carries(text, name):
    want = pr11_label(name)
    return text is not None and (text.startswith(want) if want == PNG_LABEL else text == want)


def run_p(control, files):
    """P1 and P2 against DIR's capture."""
    try:
        recorded = json.loads((control / "capture.json").read_text())["labels"]
    except (OSError, ValueError, KeyError):
        check("P1 every image file DIR holds is written again with an equal raw decode", False,
              f"{control} has no capture.json")
        check("P2 every file whose DIR copy carried its PR-11 label is byte-identical", False,
              f"{control} has no capture.json")
        return
    p1, p2, lines = [], [], []
    for name, then in sorted(recorded.items()):
        now = files.get(name)
        want = control / name
        if now is None:
            p1.append(f"{name}: not written")
            continue
        gap = delta(decode_full(now), decode_full(want))
        same = now.read_bytes() == want.read_bytes()
        lines.append(f"{name}: raw |Δ| mean/max {gap}; label {then!r} → {label(now)[1]!r}; "
                     f"bytes {'identical' if same else 'differ'}")
        if gap is None or gap[1] != 0:
            p1.append(f"{name}: {gap}")
        if carries(then, name) and not same:
            p2.append(name)
    print("       " + "\n       ".join(lines), flush=True)
    check(f"P1 every image file {control.name} holds ({len(recorded)}) is written again with "
          "an equal raw decode (rgba64le, max |Δ| 0)", not p1 and bool(recorded), f"{p1 or 'all equal'}")
    carried = [n for n, t in recorded.items() if carries(t, n)]
    check(f"P2 every file whose {control.name} copy carried its PR-11 label ({len(carried)}: "
          f"{carried}) is byte-identical to it", not p2, f"{p2 or 'all identical'}")


def same_pixels(a, b):
    """`same-pixels A B`: exit 0 when at least one file was compared and every
    max |Δ| is 0."""
    names = sorted(n.name for n in a.iterdir() if n.suffix.lower() in IMAGE_SUFFIXES
                   and (b / n.name).exists())
    print(f"B102 same-pixels — {a} against {b}: {len(names)} files in both; launches no app",
          flush=True)
    moved, unread, changed = [], [], 0
    for name in names:
        gap = delta(decode_full(a / name), decode_full(b / name))
        la, lb = label(a / name)[1], label(b / name)[1]
        changed += la != lb
        print(f"  {name}: raw |Δ| mean/max {gap}; labels {la!r} → {lb!r}"
              + ("" if la != lb else " (unchanged)"), flush=True)
        if gap is None:
            unread.append(name)
        elif gap[1] != 0:
            moved.append(name)
    print(f"  {len(names)} compared, {changed} labels moved, pixels moved in {moved or 'none'}, "
          f"unread {unread or 'none'}")
    return 0 if names and not moved and not unread else 1


# ---- the mutants (log_proof.py's build_mutant) ----------------------------------

def build_mutant(name):
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    for path, anchor, replacement in edits:
        target = copy / path
        if target.is_symlink() or not target.resolve().is_relative_to(WORK):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    print(f"  building the copy ({len(edits)} edit(s), each anchor found once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND)
    if app is None:
        return None, reason
    return app, copy


# ---- the run --------------------------------------------------------------------

def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture", "compare", "same-pixels"])
    parser.add_argument("folders", nargs="*")
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mode == "same-pixels":
        if len(args.folders) != 2:
            print("same-pixels needs two folders")
            return 2
        remove_work()
        atexit.register(remove_work)
        return same_pixels(*((ROOT / f).resolve() for f in args.folders))
    if args.mode and len(args.folders) != 1:
        print(f"{args.mode} needs one folder")
        return 2
    control = (ROOT / args.folders[0]).resolve() if args.mode else None
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mutant == "gif-flipped" and args.mode != "compare":
        print("gif-flipped runs as compare DIR --mutant gif-flipped")
        return 2
    if args.mode != "compare":
        selected -= COMPARE_ROWS
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][1] if args.mutant else []
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    sources = ROOT / "app/Sources"
    if args.mutant:
        print(f"B102 #295 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)", flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
    else:
        print(f"B102 #295 — every rendered frame labelled BT.709, spec §11 PR-11 "
              f"({args.mode or 'run'}, {proof_app.config()} build {binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    if "F0" in selected:
        run_f0(sources)
    media = fixtures()
    if REFUSED:
        print(f"instrument failure: fixtures refused {REFUSED}")
        return 2
    log = WORK / "instance.log"
    state = {"control": control if args.mode == "compare" else None}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            closed = run(launched.client, media, state)
        except Exception as error:  # a row that could not run is a failure
            import traceback
            traceback.print_exc()
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    files = state.get("files", {})
    if args.mode == "compare" and selected & COMPARE_ROWS:
        run_p(control, files)
    found = hdr.complaints(log)
    check("Z1 CONTROL: every project closed and the log holds no `Frame Job: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(hdr.tail(log)), flush=True)
    if args.mode == "capture":
        control.mkdir(parents=True, exist_ok=True)
        labels = {}
        for name, path in files.items():
            shutil.copy2(path, control / name)
            labels[name] = label(path)[1]
        (control / "capture.json").write_text(json.dumps(
            {"tree": str(ROOT), "config": proof_app.config(), "labels": labels}, indent=1))
        print(f"  captured {len(labels)} image files into {control}", flush=True)
    scored = [name for name in ROWS if name in rows]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mode == "capture":
        print(f"captured; on the control FAILED: {[n for n in scored if not rows[n]]}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}")
            return 2
        survived = [name for name in named if rows.get(name)]
        others = [name for name in scored if not rows.get(name) and name not in named]
        caught = not survived
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy (survived: {', '.join(survived) or 'none'}; other rows failed: "
              f"{', '.join(others) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
