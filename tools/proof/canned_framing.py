#!/usr/bin/env python3
"""Road map "creator-jobs" VR2a2 — canned framing analyses for `vr2a_proof.py`.

A canned analysis (spec §11 CJ-26) is a marker with `"canned": true`, no stamp,
the source's identity (size, modification second, duration) and full coverage,
beside a payload this script writes byte for byte. The app honours one only in
a `FRAMEJOB_DEV_TOOLS` build launched with `-RCDevAnalysisCanned YES`, so a
proof frames a clip against faces and cuts it chose, on any Mac, with no Vision
run — `analysis_proof.write_canned`'s pattern, for all three kinds VR-12 reads:

- `shots`: `frames.bin`, one 16-byte record per media frame (`Int64` pts,
  `Float32` d1, d2; `AnalysisShots.Record`), a cut at frame k written as d1 1.5
  at k and d2 1.5 at k + 1, so the cut rule's flash test passes.
- `faces`: `samples.bin` (`FJFS`, version 1, 28-byte records without
  landmarks: x, y, w, h, confidence, roll, yaw), one row per sample of the
  10-a-second grid, the sample's pts its grid tick; `write_faces` writes the
  kind alone with 36-byte records adding the mouth's gap and width (SW8).
- `subjects`: `samples.bin` (`FJSB`, version 1, 20-byte boxes: x, y, w, h,
  confidence), every sample with no people and no salient region unless asked.

Boxes are 0…1 of the upright picture from its top-left; the faces come from
`creator_spike/reframe_spike.py`'s generator (`face`, 0.08 × 0.14 of the
picture at confidence 0.9, centred at picture pixels), and the scenarios
follow its canned inputs: a pan, an exit and cuts.
"""

import json
import math
import struct
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE / "creator_spike"))
import reframe_spike  # noqa: E402

TICKS = 600_000
SAMPLES_PER_SECOND = 10          # AnalysisFaces.rate, AnalysisSubjects.rate (VR-11)
CUT = (1.5, 1.5)                 # d1 at the cut, d2 at the next frame (CJ-24)


def count(duration, rate):
    """`AnalysisGrid.count`: indices over the media, at least one."""
    return max(1, math.ceil(duration * rate / TICKS - 1e-6))


def grid_ticks(k, rate):
    """`AnalysisGrid.ticks(of:)`."""
    return round(k / (rate / TICKS))


def face(cx, cy=432.0):
    """A face box centred at (cx, cy) px of the 1920 × 1080 picture."""
    return reframe_spike.face(cx, cy)


# ---- the payloads --------------------------------------------------------------

def shots_bytes(duration, fps, cut_frames):
    rate = fps[0] / fps[1]
    n = count(duration, rate)
    frame = TICKS * fps[1] / fps[0]
    cuts = set(cut_frames)
    out = bytearray()
    for k in range(n):
        d1 = CUT[0] if k in cuts else 0.0
        d2 = CUT[1] if (k - 1) in cuts else 0.0
        out += struct.pack("<qff", round(k * frame), d1, d2)
    return bytes(out), n


def faces_bytes(duration, faces_at, landmarks=False):
    """With `landmarks`, 36-byte records adding each box's `gap` and `width` (the mouth's,
    over the box's height; SW8's `switch_faces_proof.py`)."""
    n = count(duration, SAMPLES_PER_SECOND)
    rows, records = bytearray(), bytearray()
    first = 0
    for k in range(n):
        t = grid_ticks(k, SAMPLES_PER_SECOND)
        boxes = faces_at(t / TICKS)
        rows += struct.pack("<qII", t, first, len(boxes))
        for b in boxes:
            records += struct.pack("<7f", b["x"], b["y"], b["w"], b["h"], b["c"], 0.0, 0.0)
            if landmarks:
                records += struct.pack("<2f", b["gap"], b["width"])
        first += len(boxes)
    header = b"FJFS" + struct.pack("<HHII", 1, 36 if landmarks else 28, n, first)
    return header + bytes(rows) + bytes(records), n


def subjects_bytes(duration, people_at=None):
    n = count(duration, SAMPLES_PER_SECOND)
    rows, records = bytearray(), bytearray()
    first = 0
    for k in range(n):
        t = grid_ticks(k, SAMPLES_PER_SECOND)
        people = people_at(t / TICKS) if people_at else []
        rows += struct.pack("<qIHH", t, first, len(people), 0)
        for b in people:
            records += struct.pack("<5f", b["x"], b["y"], b["w"], b["h"], b["c"])
        first += len(people)
    header = b"FJSB" + struct.pack("<HHII", 1, 20, n, first)
    return header + bytes(rows) + bytes(records), n


# ---- the markers ---------------------------------------------------------------

def write(package, media, copy, duration, fps, faces_at, cut_frames=(), people_at=None,
          landmarks=False):
    """The three kinds' canned markers and payloads for `media` (whose file is
    `copy`) in `package`'s `cache/analysis/`; with `landmarks`, the faces' 36-byte
    records (each box's `gap` and `width`, VR6a's `vr6_proof.py`)."""
    stat = Path(copy).stat()
    source = {"duration": duration, "modified": round(stat.st_mtime), "size": stat.st_size}
    for kind, (data, n), file in (
        ("shots", shots_bytes(duration, fps, cut_frames), "frames.bin"),
        ("faces", faces_bytes(duration, faces_at, landmarks), "samples.bin"),
        ("subjects", subjects_bytes(duration, people_at), "samples.bin"),
    ):
        folder = Path(package) / "cache/analysis" / kind / str(media)
        folder.mkdir(parents=True, exist_ok=True)
        (folder / file).write_bytes(data)
        marker = {"canned": True, "coverage": [[0, n - 1]], "files": [file], "source": source}
        (Path(package) / "cache/analysis" / kind / f"{media}.json").write_text(
            json.dumps(marker, sort_keys=True))


def write_faces(package, media, copy, duration, faces_at):
    """The `faces` kind alone, with landmarks (36-byte records), canned for `media`."""
    stat = Path(copy).stat()
    source = {"duration": duration, "modified": round(stat.st_mtime), "size": stat.st_size}
    data, n = faces_bytes(duration, faces_at, landmarks=True)
    folder = Path(package) / "cache/analysis/faces" / str(media)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "samples.bin").write_bytes(data)
    marker = {"canned": True, "coverage": [[0, n - 1]], "files": ["samples.bin"], "source": source}
    (Path(package) / "cache/analysis/faces" / f"{media}.json").write_text(
        json.dumps(marker, sort_keys=True))


# ---- the scenarios (reframe_spike.py's inputs, in media seconds) ---------------

def pan(t, seconds=60.0):
    """A face from x 400 to 1520 px over `seconds`, at y 432."""
    return [face(400 + (1520 - 400) * min(t, seconds) / seconds)]


def still(t):
    return [face(960.0)]


def exit_and_back(t):
    """Still at 960 to 4 s, gone to 6 s, back at 1100 (reframe_spike's b-exit)."""
    if t < 4:
        return [face(960.0)]
    if t < 6:
        return []
    return [face(1100.0)]


def cuts(t):
    """reframe_spike's e-cuts: 0.3, 0.7 then 0.5 of the width, shots at frames
    300 and 600 (30 fps)."""
    x = 0.3 if t < 10 else 0.7 if t < 20 else 0.5
    return [face(x * 1920)]


CUT_FRAMES = (300, 600)
