#!/usr/bin/env python3
"""Issue #282 (spec §11 GR-21) — a converting media's thumbnails (Camera Log,
HLG and PQ) drawn through step 0, and regenerated when `media.color` changes,
over MCP. Written before any product edit, so the controls are captured on the
untouched tree.

    python3 tools/proof/log_thumbs_proof.py [--app PATH] [--only TH,T1,...]
    python3 tools/proof/log_thumbs_proof.py capture DIR [--only H0,Z1]   # the CONTROL tree
    python3 tools/proof/log_thumbs_proof.py compare DIR [--only T1,...]
    python3 tools/proof/log_thumbs_proof.py --measure      # TT: the converted pass's wall time (recorded)
    python3 tools/proof/log_thumbs_proof.py --mutant NAME [--control DIR]

log_proof.py's shape, and its fixtures and decoding (imported, with
hdr_proof.py's). Launches the app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`) on a scratch socket of its own and stops only that
process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/log_thumbs/run/home`; every package, PNG
and copy of a run is under `tools/proof/work/log_thumbs/run/`, removed at the
start and at exit. The fixtures are log_proof's and hdr_proof's, made once
under their own `work/` folders and kept; TT's under
`tools/proof/work/log_thumbs/media/`. `capture` copies T4's `bt709.mov` and
T5's `slog3.mov` into `DIR/media/`, and every later T4 and T5 reads them from
there (a marker carries the file's size and modification second). No menu
item is performed and no default written. Every call is bounded
(`CALL_BOUND`), every ffmpeg and ffprobe too, and every wait for a strip
(`STRIP_BOUND`, rule H). Every project is made with `new_project {path}`, so
its strip is in `<package>/cache/thumbs/<id>/`, and closed (`close_project`,
discard). This script NEVER records the screen and spends nothing.

A strip has LANDED when its `complete.json` decodes to the shape the row
expects: the flat `CacheStamp` (a `size` key) or GR-21's
`ConvertedThumbsStamp` (a `source` key, with the expected `log` and `gamut`,
or `lutSize` and `lutPath`, or `transfer`). Pixels: `0.jpg` is read as rgb24
through ffmpeg (no colour management), its sample points mapped
proportionally from the canvas to the thumbnail's own size; `render_frame`'s
PNG through hdr_proof's `Frame` (rgb48le, rounded to 8 bits, exact for an
8-bit PNG). Projects are the fixture alone on its own 1024×128 canvas at
30 fps; the render is at tick 0, the thumbnail's own second.

Rows:
- **H0** (CONTROL, capture only; GR-21's HDR question): hdr_proof's `hlg`,
  `pq`, `b2020_709` and `p3_709` alone, on the untouched tree: flat markers;
  `0.jpg` against `render_frame` at tick 0 on the grey row every 8th column:
  HLG's and PQ's worst |Δ| > 4 (the plain generator is not step 0), the SDR
  pair's ≤ 5. Written to `DIR/h0.json` with every worst |Δ|.
- **TH**: the same four: `hlg` and `pq` hold a converted marker whose
  `transfer` is "hlg" / "pq" and whose `0.jpg` = the render ±4 on the grey
  row; `b2020_709` and `p3_709` a flat marker and ±5. Fails when
  `DIR/h0.json` is missing or did not hold, except under `compare DIR`:
  H0 is #282's untouched-tree control and holds only on a tree before #282
  (its held copy is `tools/proof/work/i282/ctl/h0.json`), so there TH scores
  its own figures and prints DIR's H0 state as a note.
- **T0** (CONTROL, capture): on the untouched tree, T1's comparison fails at
  the 90 % patch by ≥ 20 levels for every T1 case.
- **T1**: `applelog.mov` and `applelog2.mov` (detected at import),
  `slog3.mov` (S-Log3 / S-Gamut3.Cine set) and `vlog.mov` (V-Log set), and
  `slog3.mov` with Use LUT (`set_media_color {lut}`, log_proof's 33³ cube):
  the converted marker, then `0.jpg` = the render on the grey row every 8th
  column and the three patches, ±4.
- **T2**: `slog3.mov` with no Camera Log: the strip = the unconverted render
  ±4 and the marker flat; after `set_media_color` S-Log3: = the converted
  render ±4 and a `ConvertedThumbsStamp`; after `color: null`: flat again and
  = the log render; with S-Log3 set again, then the LUT: = the LUT render.
- **T3**: `undo` and `redo` of the set: the marker and the strip follow each.
- **T4** (STOP): `bt709.mov` (no Camera Log): every `.jpg` and
  `complete.json` byte-equal to the capture's. In capture, two packages of it
  must be byte-equal (the instrument's CONTROL).
- **T5**: the converted marker's `source` equals the capture's flat marker of
  the same file (`DIR/media/slog3.mov`); `log` / `gamut` are as set and no
  `lut*` key; with Use LUT, `lutSize` / `lutModified` are the cube's own,
  `lutPath` resolves to the cube, and no `log` / `gamut` key.
- **T6**: Use LUT on `slog3.mov` with a copy of the 33³ cube; saved, closed;
  the cube rewritten in place with log_proof's 17³ cube (its modification
  time moved 10 s on); reopened: the marker carries the new size and second,
  `0.jpg` was rewritten, and it = the new LUT's render ±4. (The two cubes
  sample one function, so the pixels alone do not tell them apart; the marker
  and the rewrite do.)
- **T7**: `hlg` alone: the `transfer` marker and ±4; S-Log3 set: a log
  marker (no `transfer`) = the converted render ±4; `color: null`: the
  `transfer` marker again, ±4 (all on the grey row).
- **T8**: `hlg` and `bt709.mov` imported into one project, both strips
  landed, saved, closed; bt709's `complete.json` deleted; reopened: once
  bt709's flat marker lands again, hlg's `0.jpg` (inode, mtime_ns) and
  `complete.json` bytes stay as they were before the reopen for 5 s (the
  no-op pass holds an HDR strip without opening its asset's picture).
- **T9** (issue batch B99, #291, spec §11 GR-23): log_proof's
  `slog3_fr_vp9e.mp4` and `slog3_vr_vp9e.mp4` (S-Log3 set on both, the
  full-range clip at 0 and the video-range one at 2 s) and `bt709.mov`
  (imported, no clip) in one project: the full-range marker is `wrapped`
  with `fullRange` true and the video-range marker's keys are exactly
  `source`, `log` and `gamut`, each `0.jpg` = its render ±4; saved, closed,
  the full-range `complete.json` rewritten without `fullRange` (the marker a
  build before B99 wrote) and bt709's deleted, reopened: `fullRange` true
  lands again, `0.jpg`'s (inode, mtime_ns) moved, and = the render ±4;
  saved, closed, bt709's marker deleted again, reopened: once bt709's flat
  marker lands, both VP9 strips stay unchanged for 5 s (T8's method).
- **TP** (hdr H-1, #281, spec §11 HD-12): hdr_proof's `pq_hdr10` (x265's SEI,
  MaxCLL 4,000) alone: a converted marker carrying `peak: 4000` and nothing
  of a Camera Log or a transfer, `0.jpg` = the render ±4 on the grey row;
  after `set_media_color {peak: 1000}`: the marker's `peak` 1000 and = the
  1,000 render ±4; `pq_plain` (no metadata) alone: the `transfer: "pq"`
  marker as before, ±4.
- **TS0** (CONTROL, capture only; #323, spec §11 HD-21): hdr_proof's `still_hlg.png`,
  `still_pq.png` and `still_pq_cll.png` (`hdr_stills`, `pq_meta_stills`, made once under its
  `work/hdr/media/`), each alone, on the untouched tree: a flat marker, and `0.jpg` leaves
  `render_frame` at tick 0 by > 4 somewhere on the grey row (every 8th column). Written to
  `DIR/ts0.json` with `held` and every worst |Δ|, a record like H0's that TS does not read.
- **TS** (#323, spec §11 HD-21; reads no control file): (a) `still_hlg.png` alone: the
  `transfer: "hlg"` marker; (b) `still_pq.png`: `transfer: "pq"`; (c) `still_pq_cll.png`:
  `peak: 4000`, then after `set_media_color {peak: 1000}` `peak: 1000`. Each `0.jpg` = a fresh
  render ±4 on the grey row and 640×80. (d) (a)'s project saved and closed, its
  `complete.json` rewritten as the marker's `source` (the flat stamp an older build wrote),
  reopened: the `transfer` marker lands again, `0.jpg`'s (inode, mtime_ns) moved, ±4. (e) T8's
  method, `bt709.mov` imported as the trigger: saved, closed, the trigger's marker deleted,
  reopened: once its flat marker lands, the still's `0.jpg` and `complete.json` stay unchanged
  for 5 s.
- **TU** (#323; only with `--only`, against `--control tools/proof/work/i323/ctl` or the
  capture DIR): `still8.png` and `still16_srgb.png` (copied into `DIR/media/` by capture), each
  alone: every `.jpg` and `complete.json` byte-equal to `DIR/tu/<name>/` and the marker flat.
  In capture, two packages of each must hold byte-equal strips (the CONTROL). A run whose
  control lacks one of those files exits 2 before anything is built or launched.
- **TT** (`--measure`, recorded and not scored): a 60 s 1920×1080 10-bit
  HEVC (libx265, `ultrafast`, default GOP) file imported: seconds from the
  import call to the flat marker; then S-Log3 set: seconds from
  `set_media_color` to the converted marker.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Frame Job: ` line.
- **S2** (`--mutant no-supersede` only): `cache_pass_probe.py --only S2` over
  the copy's `app/Sources`.

`capture DIR` runs H0, T0, T4 and T5's capture (`--only` scores and writes
only the rows named, TS0 and TU's capture among them: #323's control is
`capture tools/proof/work/i323/ctl --only TS0,TU,Z1`). `compare DIR` runs TH,
T1–T9, TP, TS and Z1. A plain run is TH, T1, T2, T3, T6, T7, T8, T9, TP, TS and
Z1 (`--only` adds T4, T5 or TU, read against `--control`; TU needs
`--control tools/proof/work/i323/ctl`). `--mutant NAME` builds a COPY of the tree
(`tree_copy.make_copy`), applies its edits (each anchor asserted to occur
exactly once), builds it by the copy's own `make app-debug` (`make app` under
`RC_PROOF_APP=release`) and runs the rows it names (TH, T4 and T5 against
`--control`, default tools/proof/work/i282/ctl; #323's six `still-*` mutants
always with `--control tools/proof/work/i323/ctl`, which TU reads); `no-supersede` builds no app
and runs `cache_pass_probe.py`'s S2 over the copy. MUTANT PASS when every
named row FAILED. Exit 0 when every scored row passed (a mutant: caught); 1
when one failed (a mutant: survived); 2 when the control could not be
performed.
"""

import argparse
import atexit
import json
import os
import shutil
import struct
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import hdr_proof as hdr  # noqa: E402
import log_proof as lp  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/log_thumbs"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CONTROL = "tools/proof/work/i282/ctl"
CALL_BOUND = 300
BUILD_BOUND = 1500
STRIP_BOUND = 120
MEASURE_BOUND = 900
W, H = lp.W, lp.H
GREY_ROW, PATCH_ROW, PATCH_X = lp.GREY_ROW, lp.PATCH_ROW, lp.PATCH_X
TOLERANCE = 4
T0_GAP = 20
# H0's and TH's fixtures: the two step 0 now draws (their `transfer`) and the
# SDR wide-gamut pair that stays on the plain generator (±5: the JPEG's 1
# level and H1w's 4).
HDR_DRAWN = {"hlg": "hlg", "pq": "pq"}
HDR_PLAIN = ["b2020_709", "p3_709"]
SDR_BOUND = 5
T8_HOLD = 5
SLOG3 = {"log": "slog3", "gamut": "s_gamut3_cine"}
# T1's cases: (tag, fixture, the setting — None keeps import's detected colour,
# "lut" is Use LUT with the 33³ cube — and the converted marker's log, gamut).
T1_CASES = [("applelog", "applelog", None, ("apple_log", "bt2020")),
            ("applelog2", "applelog2", None, ("apple_log2", "apple_wide_gamut")),
            ("slog3", "slog3", SLOG3, ("slog3", "s_gamut3_cine")),
            ("vlog", "vlog", {"log": "vlog"}, ("vlog", "v_gamut")),
            ("slog3-lut", "slog3", "lut", None)]
ROWS = ["H0", "TH", "T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "TP", "TS0",
        "TS", "TU", "TT", "S2", "Z1"]
RECORDS = {"TT"}
# Clean-up 3 batch B, phase 2 (#323, spec §11 HD-21): an HDR still's one tile through step 0.
# TS_STILLS: TS0's and TS's row names → hdr_proof's still names (made once under its MEDIA);
# TS_SIZE the tile's size (`thumbnailHeight` × 4 on the longest side of a 1024×128 still);
# TU_STILLS: TU's SDR stills → their file names in DIR/media/.
TS_STILLS = {"still_hlg": "still_hlg_png", "still_pq": "still_pq_png",
             "still_pq_cll": "still_pq_cll"}
TS_SIZE = "640×80"
TU_STILLS = {"still8": "still8.png", "still16_srgb": "still16_srgb.png"}
SOURCE_SWIFT = "app/Sources/MediaImporter+ThumbnailSource.swift"
IMPORTER_SWIFT = "app/Sources/MediaImporter.swift"
THUMBS_SWIFT = "app/Sources/MediaImporter+Thumbnails.swift"
WATCH_SWIFT = "app/Sources/ProjectDocument+ConvertedThumbnails.swift"
LEDGER_SWIFT = "app/Sources/MediaCacheLedger.swift"
# name: ([(file, anchor, replacement), …], the rows that must fail).
MUTANTS = {
    "plain-always": ([(SOURCE_SWIFT,
                       "        guard let effective, effective.color?.lut == nil || "
                       "effective.lutURL != nil else {\n",
                       "        guard let effective, false else {\n")], ["T1", "T2"]),
    "no-watch": ([(WATCH_SWIFT,
                   "            MediaImporter.generateCaches(for: media, url: url, in: cache, "
                   "urls: urls)\n",
                   "            _ = (media, url, cache, urls)\n")], ["T2", "T3"]),
    "flat-head": ([(SOURCE_SWIFT,
                    "        return readConverted(at: marker) == current\n",
                    "        return readStamp(at: marker) == stamp\n")], ["T2"]),
    "always-wrapped": ([(SOURCE_SWIFT,
                         "        guard let input else { return writeStamp(stamp, to: marker) }\n",
                         "        guard let input else { return writeStamp([\"source\": stamp], "
                         "to: marker) }\n")], ["T4"]),
    "lut-unstamped": ([(SOURCE_SWIFT,
                        "        let file = lut.flatMap(Self.fileStamp)\n",
                        "        let file: (size: Int64, modified: Int64)? = nil\n")], ["T6"]),
    "lut-unmapped": ([(SOURCE_SWIFT,
                       "            MediaColor(log: $0.log, gamut: $0.gamut, lut: lutID, "
                       "detected: false)\n",
                       "            MediaColor(log: $0.log, gamut: $0.gamut, lut: $0.lut, "
                       "detected: false)\n")], ["T1"]),
    "no-supersede": ([(LEDGER_SWIFT,
                       "            if latest[key]?.path != path || latest[key]?.input != input {\n",
                       "            if latest[key]?.path != path {\n")], ["S2"]),
    "hdr-plain": ([(SOURCE_SWIFT,
                    "        let effective = input ?? track.flatMap(ThumbnailInput.init(track:))\n",
                    "        let effective = input\n")], ["TH", "T7"]),
    "hdr-wide": ([(SOURCE_SWIFT,
                   "            case .hlg: found = .hlg\n",
                   "            case .hlg, .sdrWide: found = .hlg\n")], ["TH"]),
    "hdr-unheld": ([(SOURCE_SWIFT,
                     "                || readConverted(at: marker)?.holdsHDR(of: stamp) == true\n",
                     "                || false\n")], ["T8"]),
    # B99 (#291, spec §11 GR-23): the marker never records the range, then
    # the head check never reads it.
    "range-unstamped": ([(SOURCE_SWIFT,
                          "        self.fullRange = fullRange && input.readsRange ? true : nil\n",
                          "        self.fullRange = nil\n")], ["T9"]),
    "range-head-blind": ([(SOURCE_SWIFT,
                           "        let fullRange = track.map(CompositionBuilder.isFullRange) "
                           "== true\n",
                           "        let fullRange = track.map { _ in false } == true\n")],
                         ["T9"]),
    # Clean-up 3 batch B, phase 2 (#323, spec §11 HD-21): an HDR still's tile.
    "still-plain": ([(IMPORTER_SWIFT,
                      "        let input = media.kind == .image ? input ?? ThumbnailInput(still: "
                      "url) : input\n",
                      "        let input = input\n")], ["TS"]),
    "still-peak-ignored": ([(SOURCE_SWIFT,
                             "            return color.pq?.effectivePeak != nil ? color : nil  "
                             "// HD-21\n",
                             "            return nil\n")], ["TS"]),
    "still-sdr-converted": ([(SOURCE_SWIFT,
                              "        default: return nil  // an SDR still keeps today's tile\n",
                              "        default: transfer = .hlg\n")], ["TU"]),
    "still-head-blind": ([(IMPORTER_SWIFT,
                           "        if let stamp, thumbsAreCurrent(stamp, input: input, url: url, "
                           "at: marker) { return }\n",
                           "        if let stamp, thumbsAreCurrent(stamp, input: media.kind == "
                           ".image ? nil : input, url: url, at: marker) { return }\n")], ["TS"]),
    "still-flat-marker": ([(THUMBS_SWIFT,
                            "                    writeThumbsStamp(stamp, input: input, "
                            "fullRange: false, to: marker)\n",
                            "                    writeStamp(stamp, to: marker)\n")], ["TS"]),
    "still-unbounded": ([(SOURCE_SWIFT,
                          "        generator.maximumSize = CGSize(width: thumbnailHeight * 4, "
                          "height: thumbnailHeight * 4)\n",
                          "")], ["TS"]),
}
rows = {}
selected = set()
REFUSED = {}
attempt, reply = hdr.attempt, hdr.reply


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    mark = "  rec  " if key in RECORDS else ("  ok   " if good else "  FAIL ")
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


def refused():
    return {**hdr.REFUSED, **lp.REFUSED, **REFUSED}


# ---- the documents --------------------------------------------------------------

class Doc(hdr.Doc):
    """hdr_proof's document under this script's WORK, at the fixtures' size;
    `place` keeps the Camera Log import wrote (log_proof's)."""

    def __init__(self, client, name):
        self.client, self.width, self.height = client, W, H
        self.path = WORK / f"{name}.framejob"
        self._media = {}
        self.made = attempt(client, "new_project", {"path": str(self.path)})["ok"]
        self.call("set_canvas", width=W, height=H, fps=[30, 1])
        c = self.project().get("canvas") or {}
        self.ok = self.made and c.get("width") == W and c.get("height") == H
        self.why = None if self.ok else "the project or its canvas was not made"

    media_id = lp.Doc.media_id
    place = lp.Doc.place

    def color(self, media, color):
        got = self.call("set_media_color", media=media, color=color)
        if not got["ok"]:
            self.ok, self.why = False, f"set_media_color {color}: {got.get('error')}"
        return got["ok"]

    def render(self, tag, t=0):
        out = WORK / f"{tag}.png"
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=t, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        f = hdr.Frame(out, W, H)
        return f if f.ok else None

    def strip(self, media):
        return Path(self.path) / "cache" / "thumbs" / str(media)


def flat(marker):
    return "size" in marker and "source" not in marker


def wrapped(log=None, gamut=None, lut_size=None):
    """A `ConvertedThumbsStamp` with `log` and `gamut` and no `transfer`, or
    (with `lut_size`) one whose `lutSize` is that, which names a `lutPath`
    and no curve."""
    def holds(marker):
        if "source" not in marker:
            return False
        if lut_size is not None:
            return (marker.get("lutSize") == lut_size and "lutPath" in marker
                    and "log" not in marker)
        return (marker.get("log") == log and marker.get("gamut") == gamut
                and "transfer" not in marker)
    return holds


def transferred(transfer):
    """A `ConvertedThumbsStamp` of an HDR input: `transfer` and nothing of a
    Camera Log."""
    def holds(marker):
        return ("source" in marker and marker.get("transfer") == transfer
                and not {"log", "gamut", "lutPath", "lutSize", "lutModified"} & set(marker))
    return holds


def shape(marker):
    if marker is None:
        return "none"
    if "source" in marker:
        return "converted " + json.dumps({k: v for k, v in marker.items() if k != "source"})
    return "flat" if "size" in marker else "unknown " + json.dumps(marker)[:120]


def wait_marker(doc, media, want, bound=STRIP_BOUND):
    """(marker, seconds) once `complete.json` decodes and `want` holds of it;
    (None, why) at the bound."""
    path = doc.strip(media) / "complete.json"
    start = time.monotonic()
    while True:
        try:
            marker = json.loads(path.read_text())
        except (OSError, ValueError):
            marker = None
        if marker is not None and want(marker):
            return marker, time.monotonic() - start
        if time.monotonic() - start > bound:
            return None, f"no such marker within {bound} s (last: {shape(marker)})"
        time.sleep(0.1)


class Thumb:
    """A strip's JPEG as rgb24 through ffmpeg; samples by canvas coordinates."""

    def __init__(self, path):
        probe = hdr.stream(path)
        self.width, self.height = int(probe.get("width") or 0), int(probe.get("height") or 0)
        raw = hdr.decode(path, "rgb24") if self.width and self.height else None
        n = self.width * self.height * 3
        self.ok = bool(raw) and len(raw) >= n
        self.values = struct.unpack(f"{n}B", raw[:n]) if self.ok else ()

    def px8(self, x, y):
        tx = min(self.width - 1, int((x + 0.5) * self.width / W))
        ty = min(self.height - 1, int((y + 0.5) * self.height / H))
        at = (ty * self.width + tx) * 3
        return list(self.values[at:at + 3])


def points(grey_only=False):
    grey = [(x, GREY_ROW) for x in range(0, W, 8)]
    return grey if grey_only else grey + [(x, PATCH_ROW) for x in PATCH_X]


def gap(a, b):
    return max(abs(p - q) for p, q in zip(a, b))


def compare(doc, media, render, grey_only=False):
    """(worst |Δ| over the points, |Δ| at the 90 % patch, thumbnail size) of
    `0.jpg` against `render`; (None, None, why) when either is missing."""
    thumb = Thumb(doc.strip(media) / "0.jpg")
    if render is None or not thumb.ok:
        return None, None, "no render" if render is None else "0.jpg did not decode"
    worst = max(gap(thumb.px8(x, y), render.px8(x, y)) for x, y in points(grey_only))
    patch = gap(thumb.px8(PATCH_X[2], PATCH_ROW), render.px8(PATCH_X[2], PATCH_ROW))
    return worst, patch, f"{thumb.width}×{thumb.height}"


# ---- H0, TH ---------------------------------------------------------------------

def profile(doc, media, render, bound):
    """Where on the grey row the thumbnail leaves `render` by more than
    `bound`: the count, the worst column, and every 64th column's pair."""
    thumb = Thumb(doc.strip(media) / "0.jpg")
    pairs = [(x, thumb.px8(x, GREY_ROW), render.px8(x, GREY_ROW)) for x, _ in points(True)]
    over = [x for x, a, b in pairs if gap(a, b) > bound]
    x, a, b = max(pairs, key=lambda p: gap(p[1], p[2]))
    shown = ", ".join(f"x{px} {pa[1]}/{pb[1]}" for px, pa, pb in pairs if px % 64 == 0)
    return (f"; {len(over)} of {len(pairs)} columns over, worst at x {x} (thumb {a}, render "
            f"{b}); green thumb/render: {shown}")

def hdr_case(client, name, want, bound, state):
    """`name` alone, once a marker `want` holds of has landed: (worst |Δ| of
    `0.jpg` against the render on the grey row, the marker, a note)."""
    path = hdr.fixture(name)
    if path is None:
        return None, None, f"refused {hdr.REFUSED.get(name)}"
    doc = Doc(client, f"hdr-{name}")
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    marker, why = wait_marker(doc, media, want) if clip is not None else (None, doc.why)
    render = doc.render(f"hdr-{name}") if marker else None
    worst, _, size = compare(doc, media, render, grey_only=True) \
        if marker else (None, None, why)
    where = profile(doc, media, render, bound) if worst is not None else ""
    state[f"hdr-{name} closed"] = doc.close()
    return worst, marker, f"{size}{where}"


def run_h0(client, control, state):
    """H0 (capture): the plain generator's HDR strips on the untouched tree."""
    misses, notes, worsts = [], [], {}
    for name in list(HDR_DRAWN) + HDR_PLAIN:
        worst, _, note = hdr_case(client, name, flat, TOLERANCE, state)
        worsts[name] = worst
        notes.append(f"{name} worst |Δ| {worst} ({note})")
        if worst is None:
            misses.append(f"{name}: {note}")
        elif name in HDR_DRAWN and worst <= TOLERANCE:
            misses.append(f"{name}: worst {worst} ≤ {TOLERANCE}, the plain strip already matches")
        elif name not in HDR_DRAWN and worst > SDR_BOUND:
            misses.append(f"{name}: worst {worst} > {SDR_BOUND}")
    held = not misses
    (control / "h0.json").write_text(json.dumps(
        {"held": held, "worst": worsts, "config": proof_app.config()}, indent=1, sort_keys=True))
    check(f"H0 CONTROL: on the untouched tree HLG's and PQ's flat strips leave their render by "
          f"> {TOLERANCE} on the grey row, the SDR pair's by ≤ {SDR_BOUND}", held,
          "; ".join(notes) + (f"; misses {misses}" if misses else ""))


def run_th(client, control, state, gated=True):
    """TH: HLG and PQ drawn through step 0 (a `transfer` marker, ±4); the SDR
    wide-gamut pair still plain (a flat marker, ±5). Ungated (`compare DIR`),
    a DIR whose H0 did not hold is a note, not a miss: H0 holds only on a
    tree before #282."""
    misses, notes = [], []
    try:
        h0 = json.loads((control / "h0.json").read_text())
    except (OSError, ValueError):
        h0 = None
    if not (isinstance(h0, dict) and h0.get("held") is True):
        if gated:
            misses.append(f"{control.name}/h0.json is missing or did not hold")
        else:
            held = h0.get("held") if isinstance(h0, dict) else None
            state_h0 = "missing" if h0 is None else f"held {held}"
            notes.append(f"note: {control.name}/h0.json {state_h0} (H0 is #282's untouched-tree "
                         "control, held only before #282; its held copy is "
                         "tools/proof/work/i282/ctl/h0.json), TH scored on its own figures")
    for name in list(HDR_DRAWN) + HDR_PLAIN:
        drawn = name in HDR_DRAWN
        want = transferred(HDR_DRAWN[name]) if drawn else flat
        bound = TOLERANCE if drawn else SDR_BOUND
        worst, marker, note = hdr_case(client, name, want, bound, state)
        notes.append(f"{name} {shape(marker)[:70]} worst |Δ| {worst} (bound {bound}, {note})")
        if worst is None or worst > bound:
            misses.append(f"{name}: worst {worst}")
    check("TH HLG and PQ strips drawn through step 0 (transfer marker, ±4 on the grey row); the "
          "SDR wide-gamut pair plain (flat marker, ±5)", not misses, "; ".join(notes)
          + (f"; misses {misses}" if misses else ""))


# ---- T0, T1 ---------------------------------------------------------------------

def t1_case(client, tag, name, setting, want, control_tree):
    """One T1 case: (worst, patch gap, why)."""
    path = lp.fixture(name)
    if path is None:
        return None, None, f"refused {lp.REFUSED.get(name)}"
    doc = Doc(client, f"t1-{tag}")
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    expect = flat
    if clip is not None and setting == "lut":
        cube = lp.fixture("lut33")
        lut = doc.media_id(cube) if cube else None
        if lut is not None and doc.color(media, {"lut": lut}):
            expect = wrapped(lut_size=cube.stat().st_size)
    elif clip is not None and setting is not None:
        doc.color(media, setting)
        expect = wrapped(*want)
    elif clip is not None:
        expect = wrapped(*want)
    if control_tree:
        expect = flat   # the untouched tree never writes the converted marker
    marker, why = wait_marker(doc, media, expect) if doc.ok else (None, doc.why)
    worst, patch, size = compare(doc, media, doc.render(f"t1-{tag}")) if marker \
        else (None, None, why)
    doc.close()
    return worst, patch, size


def run_t1(client, control_tree):
    misses, notes, gaps = [], [], []
    for tag, name, setting, want in T1_CASES:
        worst, patch, size = t1_case(client, tag, name, setting, want, control_tree)
        notes.append(f"{tag} worst |Δ| {worst}, 90 % patch |Δ| {patch} ({size})")
        if worst is None or worst > TOLERANCE:
            misses.append(tag)
        if patch is None or patch < T0_GAP:
            gaps.append(tag)
    if control_tree:
        check(f"T0 CONTROL: on the untouched tree each T1 strip differs from its render at the "
              f"90 % patch by ≥ {T0_GAP} levels", not gaps, "; ".join(notes)
              + (f"; under {T0_GAP}: {gaps}" if gaps else ""))
        return
    check("T1 a converting media's 0.jpg = its render at tick 0 ±4 (Apple Log, Apple Log 2, "
          "S-Log3, V-Log, Use LUT)", not misses, "; ".join(notes)
          + (f"; misses {misses}" if misses else ""))


# ---- T2, T3 ---------------------------------------------------------------------

def step(doc, media, label, want, tag, misses, notes, grey_only=False):
    """Waits for the marker `want` holds of, then holds 0.jpg to a fresh
    render ±4."""
    marker, why = wait_marker(doc, media, want)
    if marker is None:
        misses.append(f"{label}: {why}")
        return
    worst, _, size = compare(doc, media, doc.render(tag), grey_only)
    notes.append(f"{label} {shape(marker)[:60]} worst {worst}")
    if worst is None or worst > TOLERANCE:
        misses.append(f"{label}: worst {worst} ({size})")


def run_t2(client, state):
    misses, notes = [], []
    path, cube = lp.fixture("slog3"), lp.fixture("lut33")
    doc = Doc(client, "t2")
    clip = doc.place(path) if doc.ok and path else None
    media = doc._media.get(path)
    if clip is None:
        misses.append(f"setup: {doc.why}")
    else:
        step(doc, media, "none", flat, "t2-none", misses, notes)
        if doc.color(media, SLOG3):
            step(doc, media, "S-Log3", wrapped("slog3", "s_gamut3_cine"), "t2-slog3", misses,
                 notes)
        if doc.color(media, None):
            step(doc, media, "cleared", flat, "t2-cleared", misses, notes)
        if doc.color(media, SLOG3):
            step(doc, media, "S-Log3 again", wrapped("slog3", "s_gamut3_cine"), "t2-again",
                 misses, notes)
        lut = doc.media_id(cube) if cube else None
        if lut is not None and doc.color(media, {"lut": lut}):
            step(doc, media, "LUT", wrapped(lut_size=cube.stat().st_size), "t2-lut", misses,
                 notes)
        if not doc.ok:
            misses.append(doc.why)
    state["t2 closed"] = doc.close()
    check("T2 set, clear, set and LUT: the marker and 0.jpg follow each (±4)", not misses,
          "; ".join(notes) + (f"; misses {misses}" if misses else ""))


def run_t3(client, state):
    misses, notes = [], []
    path = lp.fixture("slog3")
    doc = Doc(client, "t3")
    clip = doc.place(path) if doc.ok and path else None
    media = doc._media.get(path)
    if clip is None:
        misses.append(f"setup: {doc.why}")
    else:
        step(doc, media, "none", flat, "t3-none", misses, notes)
        if doc.color(media, SLOG3):
            step(doc, media, "set", wrapped("slog3", "s_gamut3_cine"), "t3-set", misses, notes)
        undone = doc.call("undo")
        if undone["ok"]:
            step(doc, media, "undo", flat, "t3-undo", misses, notes)
        else:
            misses.append(f"undo: {undone.get('error')}")
        redone = doc.call("redo")
        if redone["ok"]:
            step(doc, media, "redo", wrapped("slog3", "s_gamut3_cine"), "t3-redo", misses, notes)
        else:
            misses.append(f"redo: {redone.get('error')}")
        if not doc.ok:
            misses.append(doc.why)
    state["t3 closed"] = doc.close()
    check("T3 undo and redo of the set: the marker and 0.jpg follow each (±4)", not misses,
          "; ".join(notes) + (f"; misses {misses}" if misses else ""))


# ---- T4, T5 ---------------------------------------------------------------------

def control_media(name, control, capture):
    """T4's and T5's fixture: copied into DIR/media by capture, read from there."""
    copy = control / "media" / f"{name}.mov"
    if capture:
        made = hdr.fixture(name) if name == "bt709" else lp.fixture(name)
        if made is None:
            return None
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(made, copy)
    if not copy.exists():
        REFUSED[name] = f"{copy} is missing from the control"
        return None
    return copy


def strip_bytes(client, tag, path, state):
    """`path` alone, its flat strip landed: {file name: bytes} of every .jpg
    and complete.json, or (None, why)."""
    doc = Doc(client, tag)
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    marker, why = wait_marker(doc, media, flat) if clip is not None else (None, doc.why)
    files = None
    if marker is not None:
        files = {p.name: p.read_bytes() for p in sorted(doc.strip(media).iterdir())
                 if p.suffix in (".jpg", ".json")}
    state[f"{tag} closed"] = doc.close()
    return files, (None if files is not None else why)


def run_t4(client, control, capture, state):
    path = control_media("bt709", control, capture)
    if path is None:
        check("T4 (STOP) bt709.mov's strip", False, f"refused {refused().get('bt709')}")
        return
    folder = control / "t4"
    if capture:
        first, why = strip_bytes(client, "t4-a", path, state)
        second, why2 = strip_bytes(client, "t4-b", path, state)
        same = first is not None and first == second
        state["t4 control"] = same
        if same:
            folder.mkdir(parents=True, exist_ok=True)
            for name, data in first.items():
                (folder / name).write_bytes(data)
        landed = "both landed" if first is not None and second is not None \
            else f"{why if first is None else why2}"
        print(f"  {'ok  ' if same else 'FAIL'} T4 CONTROL: two packages of bt709.mov hold "
              f"byte-equal strips ({sorted(first or {})}; {landed})",
              flush=True)
        return
    want = {p.name: p.read_bytes() for p in sorted(folder.glob("*"))} if folder.is_dir() else {}
    got, why = strip_bytes(client, "t4", path, state)
    differ = sorted(set(want) ^ set(got or {})) + sorted(
        n for n in set(want) & set(got or {}) if want[n] != got[n])
    check(f"T4 (STOP) bt709.mov's every .jpg and complete.json byte-equal to {control.name}'s",
          bool(want) and got is not None and not differ,
          f"captured {sorted(want)}; got {sorted(got or {})}; differ {differ}; {why or ''}")


def run_t5(client, control, capture, state):
    path = control_media("slog3", control, capture)
    reference = control / "t5-flat.json"
    if path is None:
        check("T5 the converted marker's source", False, f"refused {refused().get('slog3')}")
        return
    if capture:
        doc = Doc(client, "t5-capture")
        clip = doc.place(path) if doc.ok else None
        media = doc._media.get(path)
        marker, why = wait_marker(doc, media, flat) if clip is not None else (None, doc.why)
        state["t5-capture closed"] = doc.close()
        state["t5 captured"] = marker is not None
        if marker is not None:
            reference.write_text(json.dumps(marker, sort_keys=True))
        print(f"  {'ok  ' if marker else 'FAIL'} T5 capture: slog3.mov's flat marker "
              f"{'recorded' if marker is not None else why}", flush=True)
        return
    try:
        flat_marker = json.loads(reference.read_text())
    except (OSError, ValueError):
        flat_marker = None
    misses, notes = [], []
    cube = WORK / "t5.cube"
    source_cube = lp.fixture("lut33")
    if source_cube:
        shutil.copy2(source_cube, cube)
    doc = Doc(client, "t5")
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    if clip is None or flat_marker is None:
        misses.append(f"setup: {doc.why or 'no captured flat marker'}")
    else:
        if doc.color(media, SLOG3):
            marker, why = wait_marker(doc, media, wrapped("slog3", "s_gamut3_cine"))
            good = (marker is not None and marker.get("source") == flat_marker
                    and not {"lutPath", "lutSize", "lutModified"} & set(marker))
            notes.append(f"S-Log3: source equal {marker and marker.get('source') == flat_marker}"
                         f", keys {sorted(marker or {})}")
            if not good:
                misses.append(f"S-Log3: {why or shape(marker)}")
        lut = doc.media_id(cube) if source_cube else None
        stat = cube.stat() if source_cube else None
        if lut is not None and doc.color(media, {"lut": lut}):
            marker, why = wait_marker(doc, media, wrapped(lut_size=stat.st_size))
            named = marker is not None and isinstance(marker.get("lutPath"), str) \
                and Path(marker["lutPath"]).resolve() == cube.resolve()
            good = (marker is not None and marker.get("source") == flat_marker
                    and marker.get("lutModified") == round(stat.st_mtime) and named
                    and not {"log", "gamut"} & set(marker))
            notes.append(f"LUT: {shape(marker)[:90]}, the cube's {stat.st_size} bytes at "
                         f"{round(stat.st_mtime)}, lutPath names it {named}")
            if not good:
                misses.append(f"LUT: {why or shape(marker)}")
        if not doc.ok:
            misses.append(doc.why)
    state["t5 closed"] = doc.close()
    check(f"T5 the converted marker's source is {control.name}'s flat marker of the same file; "
          "log, gamut and lut* as set, lutPath the cube's", not misses, "; ".join(notes)
          + (f"; misses {misses}" if misses else ""))


# ---- T6 -------------------------------------------------------------------------

def run_t6(client, state):
    misses, notes = [], []
    path, big, small = lp.fixture("slog3"), lp.fixture("lut33"), lp.fixture("lut17")
    cube = WORK / "t6.cube"
    if not (path and big and small):
        check("T6 a LUT rewritten in place", False, f"refused {refused()}")
        return
    shutil.copyfile(big, cube)
    doc = Doc(client, "t6")
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    lut = doc.media_id(cube) if clip is not None else None
    jpg = doc.strip(media) / "0.jpg" if media is not None else None
    before = None
    if lut is None or not doc.color(media, {"lut": lut}):
        misses.append(f"setup: {doc.why}")
    else:
        step(doc, media, "33³", wrapped(lut_size=cube.stat().st_size), "t6-33", misses, notes)
        if not doc.call("save_project")["ok"]:
            misses.append("save_project refused")
        before = (jpg.stat().st_ino, jpg.stat().st_mtime_ns) if jpg.exists() else None
    state["t6 closed"] = doc.close()
    if misses:
        check("T6 a LUT rewritten in place: rebuilt to the new LUT at the next open", False,
              f"misses {misses}")
        return
    old = cube.stat().st_mtime
    cube.write_text(small.read_text())
    os.utime(cube, (old + 10, old + 10))
    stat = cube.stat()
    opened = attempt(client, "open_project", {"path": str(doc.path)})
    if not opened["ok"]:
        misses.append(f"open_project: {opened.get('error')}")
    else:
        marker, why = wait_marker(doc, media, wrapped(lut_size=stat.st_size))
        if marker is None:
            misses.append(f"reopened: {why}")
        else:
            moved = marker.get("lutModified") == round(stat.st_mtime)
            after = (jpg.stat().st_ino, jpg.stat().st_mtime_ns) if jpg.exists() else None
            rewritten = after is not None and after != before
            worst, _, size = compare(doc, media, doc.render("t6-17"))
            notes.append(f"17³: {shape(marker)[:80]}; second moved {moved}; 0.jpg rewritten "
                         f"{rewritten}; worst {worst}")
            if not (moved and rewritten and worst is not None and worst <= TOLERANCE):
                misses.append(f"17³: moved {moved}, rewritten {rewritten}, worst {worst} ({size})")
        state["t6 reopened closed"] = doc.close()
    check("T6 a LUT rewritten in place: rebuilt to the new LUT at the next open (marker, rewrite, "
          "±4)", not misses, "; ".join(notes) + (f"; misses {misses}" if misses else ""))


# ---- T7, T8 ---------------------------------------------------------------------

def run_t7(client, state):
    misses, notes = [], []
    path = hdr.fixture("hlg")
    doc = Doc(client, "t7")
    clip = doc.place(path) if doc.ok and path else None
    media = doc._media.get(path)
    if clip is None:
        misses.append(f"setup: {doc.why or refused().get('hlg')}")
    else:
        step(doc, media, "HLG", transferred("hlg"), "t7-hlg", misses, notes, grey_only=True)
        if doc.color(media, SLOG3):
            step(doc, media, "S-Log3", wrapped("slog3", "s_gamut3_cine"), "t7-slog3", misses,
                 notes, grey_only=True)
        if doc.color(media, None):
            step(doc, media, "cleared", transferred("hlg"), "t7-cleared", misses, notes,
                 grey_only=True)
        if not doc.ok:
            misses.append(doc.why)
    state["t7 closed"] = doc.close()
    check("T7 an HLG file: transfer marker, S-Log3 set → log marker, cleared → transfer marker "
          "(each ±4 on the grey row)", not misses, "; ".join(notes)
          + (f"; misses {misses}" if misses else ""))


def peaked(peak):
    """A `ConvertedThumbsStamp` of a PQ media drawn at its peak (hdr H-1, spec §11
    HD-12): `peak` and nothing of a Camera Log or a transfer."""
    def holds(marker):
        return ("source" in marker and marker.get("peak") == peak
                and not {"log", "gamut", "lutPath", "lutSize", "lutModified", "transfer"}
                & set(marker))
    return holds


def run_tp(client, state):
    """TP (hdr H-1, #281): a PQ file's strip follows its peak."""
    misses, notes = [], []
    path, plain = hdr.fixture("pq_hdr10"), hdr.fixture("pq_plain")
    doc = Doc(client, "tp")
    clip = doc.place(path) if doc.ok and path else None
    media = doc._media.get(path)
    if clip is None:
        misses.append(f"setup: {doc.why or refused().get('pq_hdr10')}")
    else:
        step(doc, media, "pq_hdr10", peaked(4000), "tp-4000", misses, notes, grey_only=True)
        if doc.color(media, {"peak": 1000}):
            step(doc, media, "{peak: 1000}", peaked(1000), "tp-1000", misses, notes,
                 grey_only=True)
        if not doc.ok:
            misses.append(doc.why)
    state["tp closed"] = doc.close()
    other = Doc(client, "tp-plain")
    clip = other.place(plain) if other.ok and plain else None
    media = other._media.get(plain)
    if clip is None:
        misses.append(f"setup: {other.why or refused().get('pq_plain')}")
    else:
        step(other, media, "pq_plain", transferred("pq"), "tp-plain", misses, notes,
             grey_only=True)
    state["tp-plain closed"] = other.close()
    check("TP a PQ file's strip at its peak: pq_hdr10's marker carries peak 4000 and 0.jpg = "
          "its render ±4; after {peak: 1000} the marker's 1000 and = the 1,000 render ±4; "
          "pq_plain's marker unchanged (transfer pq)", not misses, "; ".join(notes)
          + (f"; misses {misses}" if misses else ""))


def strip_state(doc, media):
    """(inode, mtime_ns) of `0.jpg` and the bytes of `complete.json`, or None."""
    jpg, marker = doc.strip(media) / "0.jpg", doc.strip(media) / "complete.json"
    try:
        return (jpg.stat().st_ino, jpg.stat().st_mtime_ns, marker.read_bytes())
    except OSError:
        return None


def run_t8(client, state):
    misses, notes = [], []
    hlg, bt709 = hdr.fixture("hlg"), hdr.fixture("bt709")
    if not (hlg and bt709):
        check("T8 an HDR strip held across a reopen", False, f"refused {refused()}")
        return
    doc = Doc(client, "t8")
    one = doc.media_id(hlg) if doc.ok else None
    two = doc.media_id(bt709) if doc.ok else None
    before = None
    if one is None or two is None:
        misses.append(f"setup: {doc.why}")
    else:
        got, why = wait_marker(doc, one, transferred("hlg"))
        got2, why2 = wait_marker(doc, two, flat)
        if got is None or got2 is None:
            misses.append(f"first strips: hlg {why or 'landed'}, bt709 {why2 or 'landed'}")
        elif not doc.call("save_project")["ok"]:
            misses.append("save_project refused")
        before = strip_state(doc, one)
    state["t8 closed"] = doc.close()
    if misses or before is None:
        check("T8 an HDR strip held across a reopen", False,
              f"misses {misses or ['no hlg strip before the reopen']}")
        return
    (doc.strip(two) / "complete.json").unlink(missing_ok=True)
    opened = attempt(client, "open_project", {"path": str(doc.path)})
    if not opened["ok"]:
        misses.append(f"open_project: {opened.get('error')}")
    else:
        landed, why = wait_marker(doc, two, flat)
        if landed is None:
            misses.append(f"bt709 after the reopen: {why}")
        else:
            end, moved = time.monotonic() + T8_HOLD, None
            while moved is None and time.monotonic() < end:
                now = strip_state(doc, one)
                if now != before:
                    moved = "gone" if now is None else (
                        "0.jpg rewritten" if now[:2] != before[:2] else "complete.json changed")
                time.sleep(0.1)
            notes.append(f"bt709's flat marker back; hlg's strip over {T8_HOLD} s: "
                         f"{moved or 'unchanged'}")
            if moved:
                misses.append(f"hlg: {moved}")
        state["t8 reopened closed"] = doc.close()
    check(f"T8 hlg's strip and marker untouched by the reopen's pass ({T8_HOLD} s after bt709's "
          "marker is back)", not misses, "; ".join(notes)
          + (f"; misses {misses}" if misses else ""))


# ---- T9 (B99, #291) -------------------------------------------------------------

T9_TITLE = ("T9 a full-range VP9 S-Log3 strip's marker records fullRange; a video-range one's "
            "is source, log and gamut alone; a marker without fullRange is drawn again at the "
            f"next open, and an unchanged reopen holds both strips for {T8_HOLD} s (each ±4)")


def wants_range(full):
    """T9's markers: S-Log3 / S-Gamut3.Cine with `fullRange` true (`full`), or
    exactly `source`, `log` and `gamut`."""
    curve = wrapped("slog3", "s_gamut3_cine")

    def holds(marker):
        if not curve(marker):
            return False
        if full:
            return marker.get("fullRange") is True
        return set(marker) == {"source", "log", "gamut"}
    return holds


def t9_compare(doc, media, at, tag, notes, misses, label):
    """`media`'s 0.jpg against the render at `at` ±4."""
    worst, _, size = compare(doc, media, doc.render(tag, t=at))
    notes.append(f"{label} worst {worst} ({size})")
    if worst is None or worst > TOLERANCE:
        misses.append(f"{label}: worst {worst}")


def t9_hold(doc, ids, before, misses, notes):
    """T8's method: every strip in `ids` stays as `before` for T8_HOLD s."""
    end, moved = time.monotonic() + T8_HOLD, {}
    while time.monotonic() < end and len(moved) < len(ids):
        for name, media in ids.items():
            now = strip_state(doc, media)
            if name not in moved and now != before[name]:
                moved[name] = "gone" if now is None else (
                    "0.jpg rewritten" if now[:2] != before[name][:2] else "complete.json changed")
        time.sleep(0.1)
    notes.append(f"unchanged reopen over {T8_HOLD} s: {moved or 'both unchanged'}")
    misses.extend(f"{name}: {why}" for name, why in moved.items())


def run_t9(client, state):
    """T9 (B99): each step's miss is scored and the row goes on; only a step
    the next one needs (the project, a strip, a save, a reopen) stops it."""
    misses, notes = [], []
    full_path, video_path = lp.fixture("slog3_fr_vp9e"), lp.fixture("slog3_vr_vp9e")
    trigger_path = hdr.fixture("bt709")
    if not (full_path and video_path and trigger_path):
        check(T9_TITLE, False, f"refused {refused()}")
        return
    at = {"full": 0, "video": 2 * hdr.SEC}
    doc = Doc(client, "t9")
    full_clip = doc.place(full_path, at=at["full"]) if doc.ok else None
    video_clip = doc.place(video_path, at=at["video"]) if full_clip is not None else None
    trigger = doc.media_id(trigger_path) if video_clip is not None else None
    ids = {"full": doc._media.get(full_path), "video": doc._media.get(video_path)}
    before, stop = None, None
    if trigger is None or not (doc.color(ids["full"], SLOG3) and doc.color(ids["video"], SLOG3)):
        stop = f"setup: {doc.why}"
    else:
        # 1 and 2: the full-range marker records its range; the video-range
        # one is today's shape.
        for name in ("full", "video"):
            marker, why = wait_marker(doc, ids[name], wants_range(name == "full"))
            if marker is None:
                misses.append(f"{name} range: {why}")
                continue
            notes.append(f"{name} range {shape(marker)[:90]}")
            t9_compare(doc, ids[name], at[name], f"t9-{name}", notes, misses, f"{name} range")
        landed, why = wait_marker(doc, trigger, flat)
        if landed is None:
            stop = f"bt709: {why}"
        elif not doc.call("save_project")["ok"]:
            stop = "save_project refused"
        else:
            before = strip_state(doc, ids["full"])
    state["t9 closed"] = doc.close()
    if stop or before is None:
        check(T9_TITLE, False,
              "; ".join(notes) + f"; misses {misses + [stop or 'no full-range strip']}")
        return
    # 3 and 4: the marker a build before B99 wrote is drawn again.
    marker_path = doc.strip(ids["full"]) / "complete.json"
    old = json.loads(marker_path.read_text())
    notes.append(f"the marker rewritten without fullRange (it held {old.get('fullRange')})")
    marker_path.write_text(json.dumps({k: v for k, v in old.items() if k != "fullRange"}))
    (doc.strip(trigger) / "complete.json").unlink(missing_ok=True)
    opened = attempt(client, "open_project", {"path": str(doc.path)})
    held = None
    if not opened["ok"]:
        stop = f"open_project: {opened.get('error')}"
    else:
        marker, why = wait_marker(doc, ids["full"], wants_range(True))
        now = strip_state(doc, ids["full"])
        redrawn = now is not None and now[:2] != before[:2]
        notes.append(f"the stale marker: {shape(marker)[:90] if marker else why}; 0.jpg "
                     f"rewritten {redrawn}")
        if marker is None or not redrawn:
            misses.append(f"stale marker: fullRange landed {marker is not None}, 0.jpg "
                          f"rewritten {redrawn}")
        else:
            t9_compare(doc, ids["full"], at["full"], "t9-redrawn", notes, misses, "redrawn")
        landed, why = wait_marker(doc, trigger, flat)
        if landed is None:
            stop = f"bt709 after the first reopen: {why}"
        elif not doc.call("save_project")["ok"]:
            stop = "save_project refused after the first reopen"
        else:
            held = {name: strip_state(doc, media) for name, media in ids.items()}
        state["t9 reopened closed"] = doc.close()
    if stop or held is None or None in held.values():
        check(T9_TITLE, False,
              "; ".join(notes) + f"; misses {misses + [stop or 'no strip held']}")
        return
    # 5: an unchanged reopen holds both strips.
    (doc.strip(trigger) / "complete.json").unlink(missing_ok=True)
    opened = attempt(client, "open_project", {"path": str(doc.path)})
    if not opened["ok"]:
        misses.append(f"open_project again: {opened.get('error')}")
    else:
        landed, why = wait_marker(doc, trigger, flat)
        if landed is None:
            misses.append(f"bt709 after the second reopen: {why}")
        else:
            t9_hold(doc, ids, held, misses, notes)
        state["t9 held closed"] = doc.close()
    check(T9_TITLE, not misses, "; ".join(notes) + (f"; misses {misses}" if misses else ""))


# ---- TS0, TS, TU (#323) ---------------------------------------------------------

STILLS = {}
TS_TITLE = ("TS an HLG or PQ still's one tile drawn through step 0: still_hlg's transfer marker, "
            "still_pq's, still_pq_cll's peak 4000 then 1000, each 0.jpg = its render ±4 on the "
            f"grey row and {TS_SIZE}; an older build's flat marker drawn again; an unchanged "
            f"reopen holds the tile for {T8_HOLD} s")


def stills(client):
    """hdr_proof's stills (HI's, P13's and HIp's), made once under its MEDIA and kept, its
    scratch projects under this script's WORK: name → path or None (hdr.REFUSED says why)."""
    if not STILLS:
        hdr.WORK = WORK
        made = hdr.hdr_stills(client)
        made.update(hdr.pq_meta_stills(made))
        STILLS.update(made)
    return STILLS


def ts_paths(client):
    """TS_STILLS' row names → paths; (None, why) when one was refused."""
    made = stills(client)
    paths = {name: made.get(source) for name, source in TS_STILLS.items()}
    absent = {name: refused().get(TS_STILLS[name]) for name, p in paths.items() if p is None}
    return (None, f"refused {absent}") if absent else (paths, None)


def run_ts0(client, control, state):
    """TS0 (capture): each HDR still's flat tile on the untouched tree leaves its render."""
    paths, why = ts_paths(client)
    misses, notes, worsts = [], [], {}
    if paths is None:
        misses.append(why)
    for name, path in (paths or {}).items():
        doc = Doc(client, f"ts0-{name}")
        clip = doc.place(path) if doc.ok else None
        media = doc._media.get(path)
        marker, why = wait_marker(doc, media, flat) if clip is not None else (None, doc.why)
        render = doc.render(f"ts0-{name}") if marker else None
        worst, _, size = compare(doc, media, render, grey_only=True) if marker \
            else (None, None, why)
        where = profile(doc, media, render, TOLERANCE) if worst is not None else ""
        state[f"ts0-{name} closed"] = doc.close()
        worsts[name] = worst
        notes.append(f"{name} worst |Δ| {worst} ({size}{where})")
        if worst is None:
            misses.append(f"{name}: {size}")
        elif worst <= TOLERANCE:
            misses.append(f"{name}: worst {worst} ≤ {TOLERANCE}, the flat tile already matches")
    held = not misses
    (control / "ts0.json").write_text(json.dumps(
        {"held": held, "worst": worsts, "config": proof_app.config()}, indent=1, sort_keys=True))
    check(f"TS0 CONTROL: on the untouched tree each HDR still lands a flat marker and its 0.jpg "
          f"leaves render_frame at tick 0 by > {TOLERANCE} on the grey row", held,
          "; ".join(notes) + (f"; misses {misses}" if misses else ""))


def ts_step(doc, media, label, want, tag, misses, notes):
    """`step` on the grey row, with 0.jpg held to TS_SIZE: the marker, or None."""
    marker, why = wait_marker(doc, media, want)
    if marker is None:
        misses.append(f"{label}: {why}")
        return None
    worst, _, size = compare(doc, media, doc.render(tag), grey_only=True)
    notes.append(f"{label} {shape(marker)[:60]} worst {worst} ({size})")
    if worst is None or worst > TOLERANCE or size != TS_SIZE:
        misses.append(f"{label}: worst {worst} ({size}, want {TS_SIZE})")
    return marker


def ts_reopen(client, doc, misses):
    opened = attempt(client, "open_project", {"path": str(doc.path)})
    if not opened["ok"]:
        misses.append(f"open_project: {opened.get('error')}")
    return opened["ok"]


def ts_hlg(client, path, trigger_path, misses, notes, state):
    """(a) still_hlg alone; (d) its marker rewritten flat, drawn again at the reopen; (e)
    T8's method with bt709.mov as the trigger."""
    doc = Doc(client, "ts-hlg")
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    before = None
    if clip is None:
        misses.append(f"(a) setup: {doc.why}")
    elif ts_step(doc, media, "(a) still_hlg", transferred("hlg"), "ts-hlg", misses, notes):
        if doc.call("save_project")["ok"]:
            before = strip_state(doc, media)
        else:
            misses.append("(a) save_project refused")
    state["ts-hlg closed"] = doc.close()
    if before is None:
        misses.append("(d), (e) not reached: no saved still_hlg tile")
        return
    # (d): the flat stamp a build before HD-21 wrote.
    marker_path = doc.strip(media) / "complete.json"
    marker_path.write_text(json.dumps(json.loads(marker_path.read_text())["source"]))
    if not ts_reopen(client, doc, misses):
        return
    held = None
    if ts_step(doc, media, "(d) the flat marker drawn again", transferred("hlg"), "ts-hlg-d",
               misses, notes):
        now = strip_state(doc, media)
        moved = now is not None and now[:2] != before[:2]
        notes.append(f"(d) 0.jpg rewritten {moved}")
        if not moved:
            misses.append("(d) 0.jpg was not rewritten")
    trigger = doc.media_id(trigger_path)
    landed, why = wait_marker(doc, trigger, flat) if trigger is not None else (None, doc.why)
    if landed is None:
        misses.append(f"(e) bt709: {why}")
    elif not doc.call("save_project")["ok"]:
        misses.append("(e) save_project refused")
    else:
        held = strip_state(doc, media)
    state["ts-hlg reopened closed"] = doc.close()
    if held is None:
        return
    # (e): an unchanged reopen holds the tile.
    (doc.strip(trigger) / "complete.json").unlink(missing_ok=True)
    if not ts_reopen(client, doc, misses):
        return
    landed, why = wait_marker(doc, trigger, flat)
    if landed is None:
        misses.append(f"(e) bt709 after the reopen: {why}")
    else:
        end, moved = time.monotonic() + T8_HOLD, None
        while moved is None and time.monotonic() < end:
            now = strip_state(doc, media)
            if now != held:
                moved = "gone" if now is None else (
                    "0.jpg rewritten" if now[:2] != held[:2] else "complete.json changed")
            time.sleep(0.1)
        notes.append(f"(e) bt709's flat marker back; still_hlg's tile over {T8_HOLD} s: "
                     f"{moved or 'unchanged'}")
        if moved:
            misses.append(f"(e) still_hlg: {moved}")
    state["ts-hlg held closed"] = doc.close()


def run_ts(client, state):
    """TS (#323, spec §11 HD-21): reads no control file."""
    misses, notes = [], []
    paths, why = ts_paths(client)
    trigger = hdr.fixture("bt709")
    if paths is None or trigger is None:
        check(TS_TITLE, False, why or f"refused {refused().get('bt709')}")
        return
    ts_hlg(client, paths["still_hlg"], trigger, misses, notes, state)
    for name, want in (("still_pq", transferred("pq")), ("still_pq_cll", peaked(4000))):
        doc = Doc(client, f"ts-{name}")
        clip = doc.place(paths[name]) if doc.ok else None
        media = doc._media.get(paths[name])
        if clip is None:
            misses.append(f"{name} setup: {doc.why}")
        elif ts_step(doc, media, f"({'b' if name == 'still_pq' else 'c'}) {name}", want,
                     f"ts-{name}", misses, notes) and name == "still_pq_cll":
            if doc.color(media, {"peak": 1000}):
                ts_step(doc, media, "(c) {peak: 1000}", peaked(1000), "ts-cll-1000", misses,
                        notes)
            else:
                misses.append(f"(c) {doc.why}")
        state[f"ts-{name} closed"] = doc.close()
    check(TS_TITLE, not misses, "; ".join(notes) + (f"; misses {misses}" if misses else ""))


def tu_control(control):
    """TU's control files: the first missing one, or None."""
    for name, file in TU_STILLS.items():
        for path in (control / "media" / file, control / "tu" / name):
            if not path.exists():
                return path
    return None


def run_tu(client, control, capture, state):
    """TU (#323): every SDR still's tile and marker byte-identical to DIR's."""
    misses, notes = [], []
    made = stills(client) if capture else {}
    for name, file in TU_STILLS.items():
        copy, folder = control / "media" / file, control / "tu" / name
        if capture:
            source = hdr.fixture("still8") if name == "still8" else made.get(name)
            if source is None:
                misses.append(f"{name}: refused {refused().get(name)}")
                continue
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, copy)
            first, why = strip_bytes(client, f"tu-{name}-a", copy, state)
            second, why2 = strip_bytes(client, f"tu-{name}-b", copy, state)
            same = first is not None and first == second
            notes.append(f"{name} {sorted(first or {})} two packages byte-equal {same}")
            if same:
                folder.mkdir(parents=True, exist_ok=True)
                for part, data in first.items():
                    (folder / part).write_bytes(data)
            else:
                misses.append(f"{name}: {why or why2 or 'the two strips differ'}")
            continue
        want = {p.name: p.read_bytes() for p in sorted(folder.glob("*"))} \
            if folder.is_dir() else {}
        got, why = strip_bytes(client, f"tu-{name}", copy, state)
        differ = sorted(set(want) ^ set(got or {})) + sorted(
            n for n in set(want) & set(got or {}) if want[n] != got[n])
        notes.append(f"{name} captured {sorted(want)}; got {sorted(got or {})}; differ {differ}")
        if not want or got is None or differ:
            misses.append(f"{name}: {why or differ or 'nothing captured'}")
    if capture:
        state["tu control"] = not misses
        print(f"  {'ok  ' if not misses else 'FAIL'} TU CONTROL: two packages of each SDR still "
              f"hold byte-equal strips ({'; '.join(notes)}"
              f"{'; misses ' + str(misses) if misses else ''})", flush=True)
        return
    check(f"TU every SDR still's .jpg and complete.json byte-equal to {control.name}'s, the "
          "marker flat", not misses, "; ".join(notes) + (f"; misses {misses}" if misses else ""))


# ---- TT -------------------------------------------------------------------------

def tt_fixture():
    out = MEDIA / "slog3_60s.mov"
    if not out.exists():
        MEDIA.mkdir(parents=True, exist_ok=True)
        made = bounded.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                            "testsrc2=size=1920x1080:rate=30:duration=60", "-c:v", "libx265",
                            "-preset", "ultrafast", "-x265-params", "log-level=error",
                            "-pix_fmt", "yuv420p10le", "-tag:v", "hvc1", str(out)], 900)
        if made["rc"] != 0 or not out.exists():
            REFUSED["slog3_60s"] = f"ffmpeg rc {made['rc']} {made['stderr'][-300:]}"
            out.unlink(missing_ok=True)
            return None
    return hdr.checked("slog3_60s", out, {"codec_name": "hevc", "pix_fmt": "yuv420p10le",
                                          "width": 1920, "height": 1080})


def run_tt(client, state):
    path = tt_fixture()
    if path is None:
        check("TT the converted pass's wall time", False, f"refused {refused()}")
        return
    doc = Doc(client, "tt")
    start = time.monotonic()
    clip = doc.place(path) if doc.ok else None
    media = doc._media.get(path)
    flat_marker, why = wait_marker(doc, media, flat, MEASURE_BOUND) if clip is not None \
        else (None, doc.why)
    imported = time.monotonic() - start
    start = time.monotonic()
    converted, why2 = (wait_marker(doc, media, wrapped("slog3", "s_gamut3_cine"),
                                   MEASURE_BOUND) if flat_marker and doc.color(media, SLOG3)
                       else (None, why or doc.why))
    took = time.monotonic() - start
    state["tt closed"] = doc.close()
    check("TT a 60 s 1920×1080 10-bit HEVC: import → flat marker, set_media_color → converted "
          "marker", flat_marker is not None and converted is not None,
          f"import → flat marker {imported:.1f} s; S-Log3 → converted marker {took:.1f} s; "
          f"{'' if flat_marker is not None else why}"
          f"{'' if converted is not None or flat_marker is None else why2} "
          f"({proof_app.config()} build)")


# ---- S2 (no-supersede) ----------------------------------------------------------

def run_s2(sources):
    ran = bounded.run([sys.executable, str(ROOT / "tools/proof/cache_pass_probe.py"),
                       "--sources", str(sources), "--only", "S2"], 900)
    lines = [line for line in ran["stdout"].splitlines() if line.startswith("S2 ")]
    check("S2 cache_pass_probe over the copy: a changed input supersedes",
          bool(lines) and lines[0].startswith("S2 pass"),
          (lines[0] if lines else (ran["stdout"] + ran["stderr"])[-400:]))
    return bool(lines)


# ---- the run --------------------------------------------------------------------

def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def make_mutant(name, build):
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    for path, anchor, replacement in edits:
        target = copy / path
        if not target.resolve().is_relative_to(WORK):
            return None, f"{path} in the copy is the tree's own file"
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
        target.write_text(text.replace(anchor, replacement))
    if not build:
        return copy, copy
    print(f"  building the copy ({len(edits)} edit(s), each anchor found once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND)
    if app is None:
        return None, reason
    return app, copy


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture", "compare"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--measure", action="store_true")
    parser.add_argument("--control", default=CONTROL)
    args = parser.parse_args()
    if args.mode and not args.folder:
        print(f"{args.mode} needs a folder")
        return 2
    control = (ROOT / (args.folder or args.control)).resolve()
    capture = args.mode == "capture"
    named = MUTANTS[args.mutant][1] if args.mutant else []
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    elif capture:
        selected = {"H0", "T0", "T4", "T5", "Z1"}
    elif args.mode == "compare":
        selected = {"TH", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "TP", "TS", "Z1"}
    elif args.measure:
        selected = {"TT", "Z1"}
    elif args.mutant:
        selected = set(named) | ({"Z1"} if "S2" not in named else set())
    else:
        selected = {"TH", "T1", "T2", "T3", "T6", "T7", "T8", "T9", "TP", "TS", "Z1"}
    for name in ("H0", "TS0"):
        if name in selected and not capture:
            print(f"{name} runs in capture only")
            return 2
    if "TU" in selected and not capture:
        missing = tu_control(control)
        if missing is not None:
            print(f"TU: the control could not be performed — {missing} is missing")
            return 2
    if capture:
        control.mkdir(parents=True, exist_ok=True)
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    config = proof_app.config()
    if args.mutant:
        print(f"#282 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)", flush=True)
        app, copy = make_mutant(args.mutant, build="S2" not in named)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        if "S2" in named:
            if not run_s2(copy / "app/Sources"):
                print(f"mutant {args.mutant}: the control could not be performed — S2 not "
                      "scored")
                return 2
        binary = proof_app.executable(app)
    else:
        print(f"#282 — converting media's thumbnails over MCP ({args.mode or 'run'}, {config} "
              f"build {binary})", flush=True)
    state = {}
    closed = True
    log = WORK / "instance.log"
    needs_instance = bool(selected - {"Z1", "S2"})
    if needs_instance and not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    if needs_instance:
        launched = mcp.launch(str(binary), [],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                print(f"instrument failure: the app did not listen at {launched.socket_path}")
                return 2
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            client = launched.client
            try:
                if "H0" in selected and capture:
                    run_h0(client, control, state)
                if "TH" in selected and not capture:
                    run_th(client, control, state, gated=args.mode != "compare")
                if "T0" in selected and capture:
                    run_t1(client, control_tree=True)
                if "T1" in selected and not capture:
                    run_t1(client, control_tree=False)
                if "T2" in selected:
                    run_t2(client, state)
                if "T3" in selected:
                    run_t3(client, state)
                if "T4" in selected:
                    run_t4(client, control, capture, state)
                if "T5" in selected:
                    run_t5(client, control, capture, state)
                if "T6" in selected:
                    run_t6(client, state)
                if "T7" in selected:
                    run_t7(client, state)
                if "T8" in selected:
                    run_t8(client, state)
                if "T9" in selected:
                    run_t9(client, state)
                if "TP" in selected:
                    run_tp(client, state)
                if "TS0" in selected and capture:
                    run_ts0(client, control, state)
                if "TS" in selected and not capture:
                    run_ts(client, state)
                if "TU" in selected:
                    run_tu(client, control, capture, state)
                if "TT" in selected:
                    run_tt(client, state)
            except Exception as error:  # a row that could not run is a failure
                import traceback
                traceback.print_exc()
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
                closed = False
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    found = hdr.complaints(log) if needs_instance else []
    closed = closed and all(v for k, v in state.items() if k.endswith("closed"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Frame Job: ` "
          "line", closed and not found and not refused(),
          f"closed {closed}; refused {refused() or 'none'}; complaints {found}")
    if needs_instance:
        print(f"  {log.name} tail:\n    " + "\n    ".join(hdr.tail(log)), flush=True)
    if capture:
        (control / "capture.json").write_text(json.dumps({"tree": str(ROOT), "config": config},
                                                         indent=1))
        good = (all(rows.get(name) for name in ("H0", "T0", "TS0", "Z1") if name in selected)
                and ("T4" not in selected or state.get("t4 control"))
                and ("T5" not in selected or state.get("t5 captured"))
                and ("TU" not in selected or state.get("tu control")))
        print(f"captured into {args.folder} ({', '.join(sorted(selected))}): H0 "
              f"{rows.get('H0')}, T0 {rows.get('T0')}, T4 control {state.get('t4 control')}, "
              f"T5 {state.get('t5 captured')}, TS0 {rows.get('TS0')}, TU control "
              f"{state.get('tu control')}, Z1 {rows.get('Z1')}")
        return 0 if good else 1
    scored = [name for name in ROWS if name in rows and name not in RECORDS]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}" + (" (TT recorded)" if "TT" in rows else ""))
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
    if "TT" in rows and not rows["TT"]:
        return 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
