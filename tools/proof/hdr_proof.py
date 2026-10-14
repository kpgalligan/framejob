#!/usr/bin/env python3
"""Road map "grading-3", phase T3-1 (spec §11 GR-15) — honest sources and
Frame Job's own HDR→SDR at step 0, over MCP and two probes over `app/Sources`.
Written before any product edit, so the control is captured on the untouched
tree. T3-3 (the close) added H1a, H7 and TI's export wall time, measuring two
of GR-15's unmeasured claims; the product was not edited for them.

    python3 tools/proof/hdr_proof.py [--app PATH] [--only H1a,H2,H7,...]
    python3 tools/proof/hdr_proof.py capture DIR    # the CONTROL tree: H1's references, H2–H6 shown failing
    python3 tools/proof/hdr_proof.py compare DIR [--only H1,...]
    python3 tools/proof/hdr_proof.py --measure      # TI: step 0's 4K cost (Release figures)
    python3 tools/proof/hdr_proof.py --mutant NAME [--control DIR]

curves_proof.py's shape. Launches the app `proof_app` picks (Debug unless
`RC_PROOF_APP=release`) on a scratch socket of its own and stops only that
process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/hdr/run/home`; every package, PNG and
export of a run is under `tools/proof/work/hdr/run/`, removed at the start and
at exit. The fixtures are made once under `tools/proof/work/hdr/media/` and
kept; `capture` copies H1's into `DIR/media/`, and every later run reads H1's
from there, so the control and the tree draw the same bytes (a VideoToolbox
encode is not repeatable). No menu item is performed and no default written:
`--measure` passes `-FrameJobCompositorTiming YES` as a launch argument. Every
call is bounded (`CALL_BOUND`), every ffmpeg and ffprobe too. Every project is
closed (`close_project`, discard). This script NEVER records the screen.

Fixtures (each kept only when ffprobe reads what it should; a refused fixture
is its row's FAIL, named): `base.mov`, the road map's ramp — 1024×128, 1 s,
10-bit ProRes 422 HQ, the grey ramp on rows 0–63 (Y = 64 + X·876/1023, Cb =
Cr = 512; read on row 32) over the chroma ramp on rows 64–127 (Cb rising
112→912, Cr falling 912→112; read on row 96) — re-tagged by stream copy with
`prores_metadata` and the container's `colr` (`+write_colr`) as `bt709`,
`hlg` (bt2020/arib-std-b67/bt2020nc), `pq` (bt2020/smpte2084/bt2020nc),
`b2020_709` (bt2020/bt709/bt2020nc), `p3_709` (smpte432/bt709/bt709), and
`untagged` (the bsf's `unknown`, no `colr`); by `hevc_videotoolbox` Main 10
from it, `hlg_hevc.mov` (the HLG tags), `srgb.mov` (bt709/iec61966-2-1/bt709)
and `b2020_2020.mov` (bt2020/bt2020-10/bt2020nc); 640×360 1 s `testsrc2`
movies — H.264 BT.709 and untagged, HEVC 8-bit tagged with the matrix only,
ProRes 4444 with an alpha ramp — an 8-bit PNG of it, and container_import_proof
.py's P1 VP9 WebM; `applelog.mov`, `bt709.mov` relabelled Apple Log by
`applelog_writer.swift` (ffprobe `bt2020nc/unknown/bt2020`, the label read
back); and, for TI only, 4K 4 s ProRes twins of the ramp, HLG and BT.709.
For H1a: `hevc_alpha.mov`, 640×360 1 s `testsrc2` with an alpha ramp through
`hevc_videotoolbox` from `bgra`, BT.709-tagged by `setparams` (the `-color_*`
flags alone do not stick from `bgra`). For H7: `pq_plain.mov` and
`pq_hdr10.mov`, the ramp through `libx265` lossless 4:2:0 10-bit with the PQ
tags, the second with x265's `master-display` and `max-cll` (HDR10 static
metadata naming a 4,000 cd/m² peak, not the conversion's 1,000); issue batch
B96 (#281) added `pq_hdr10_600.mov` (a 600 cd/m² display, MaxCLL 600) and
`pq_hdr10_cll.mov` (the 4,000 cd/m² display, MaxCLL 1,000), which separates
the two fields.
The oracle: the codes ffmpeg reads back from a fixture, through the matrix
its tags name (limited range), then this script's own formula with GR-15's
numbers (`convert`), the matrices derived here from the published
chromaticities and D65 (`to709`).

Rows (projects are the fixture alone on a canvas its size, 30 fps):
- **H1** (STOP; `compare DIR` and mutants): every SDR fixture (`bt709`,
  `untagged`, both H.264, the matrix-only HEVC, the PNG, the ProRes 4444, the
  WebM), `srgb.mov`, `applelog.mov` and the BT.709 ramp reversed
  (`set_reversed`): `render_frame` at 0 and 0.5 s byte-identical to DIR's PNGs,
  and `hdr_pick_probe.swift`'s picks at three points at 0.5 s equal to DIR's.
  R0's `rec_tags.mov` joins it when the selector's arm for its tags is nil.
- **H1a** (T3-3; GR-15's "ProRes 4444 with alpha, the WebM rewrap, the
  HEVC-with-alpha path" in a converting composition): prores4444 | hlg |
  hevc_alpha | webm, 1 s each on one 640×360 track, saved; at 0.5 s into
  each non-HLG clip the tree probe's PNG bytes and picks equal the base
  tree's (716720c, a version-18 copy, as H1m). CONTROL: at the HLG clip the
  tree's PNG differs from the base's (the composition converts).
- **H2**: the HLG, PQ and HLG HEVC ramps alone, and BT.709 | HLG | BT.709 (1 s
  each): each `prores_422` export's first frame of the HDR clip equals its
  frame +5 on the grey row (every 8th column) ±1, and `render_frame` at both
  ticks equals the export there ±1 (the first-frame flash; a parity row).
- **H3**: the HLG and PQ grey rows at 0.5 s, every 8th column, = the oracle ±1
  at 8 bits; and Apple's six measured points (HLG 0.25/0.5/0.75/1.0 → 0.215/
  0.384/0.604/1.0, PQ 0.5/0.75 → 0.719/1.0), read off the render at those
  signals, within 3/255 (GR-15's bound, written before measuring).
- **H4**: the HLG chroma row: every even column whose source chroma (max − min
  of R'G'B') is ≥ 0.05 and whose converted linear colour (after the matrix,
  before the lift) leaves [0, 1]³ — at least 20 of them, counted on the
  oracle (a CONTROL on the fixture) — and the column nearest the brief's
  patch (0.42, 0.84, 1.17): the render's hue in linear BT.709 opponent space
  (p = r − g, q = (r + g)/2 − b, atan2(q, p)) within 2° of the oracle's
  pre-lift colour, and its values = the oracle ±2.
- **H5**: `b2020_709`, `p3_709`, `b2020_2020` at 0.5 s: the grey row = the
  signal ±1, the chroma row (every 8th even column) = the oracle ±2.
- **H6**: `hdr_pick_probe.swift` on the HLG ramp over a magenta canvas
  background: the eyedropper's pick at (256, 96) at 0.5 s equals the
  `prores_422` export's pixel there (frame 15) ±2; keyed with the probe's key
  (`set_video` chroma, tolerance 0.05), the export shows magenta there ±8.
- **H7** (T3-3; GR-15's "HDR10 static metadata on a converted frame"; B96
  for #281): CONTROL first, ffprobe's first frame of each of `pq_hdr10`,
  `pq_hdr10_600` and `pq_hdr10_cll` names "Mastering display metadata" and
  "Content light level metadata" with its own peaks (`max_luminance=
  40000000/10000` and `max_content=4000`; 6000000/10000 and 600;
  40000000/10000 and 1000; the conversion assumes 1,000) and `pq_plain`'s
  none of them; then each of the four alone at 0.5 s: the grey row (every
  8th column) = the PQ oracle ±1 at 8 bits (H3's loop), and every render's
  PNG bytes equal pq_plain's (lossless twins; if not, the worst |Δ| is
  printed and held to ±1). Because no metadata peak is the conversion's own,
  equal renders show the shoulder ignores it rather than follows it.
  Printed, unscored: Apple's reading of each file (`hdr_pick_probe.swift`'s
  `plain` request, as H1w's oracle) at the grey row every 64th column, and
  each HDR10 file's worst |Δ| against `pq_plain`'s — whether Apple's own
  reading follows the metadata, and which field.
- **R0** (GR-15's owed check; NEVER records the screen, never searches the
  disk): ffprobe reads the labels of the newest-by-name `Screen Recording
  *.mov` in `~/Movies/Frame Job Recordings/` (that folder only, read-only,
  labels only: its pixels are never imported, rendered or copied), the
  selector's arm for them (`arm`, Approach 3's table) is printed, and
  `rec_tags.mov` — the ramp as `srgb.mov` is made, carrying exactly those
  three tags — joins H1 (arm nil) or H5 (`sdrWide`). No such file: "no
  recording on disk; GRD-16", scored nothing.
- **TI** (`--measure`, mutants): the 4K HLG twin placed twice (8 s) exported
  `prores_422` on an instance of its own, then the BT.709 twin on another;
  every compositor timing line (`[framejob] compositor: … over 120 frames, N
  input passes`) reports 120 passes for HLG and 0 for BT.709, at least two
  lines each; the averages, their difference, each export's wall time
  (`time.monotonic()` around the `export` call, recorded, not scored) and the
  host state are printed.
- **P1–P4**: `hdr_probe.swift` over `app/Sources` (a probe that will not build
  is a scored FAIL of all four).
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Frame Job: ` line.

H1a and H7 run in a plain run, `compare` and `--only`; never under
`capture`, `--measure` or a mutant's default selection.
`capture DIR` records H1's references (`DIR/h1-*.png`, `DIR/media/`,
`DIR/capture.json` with the picks and the reverse's digest) and runs H2–H6 and
R0, which must FAIL on the control (each discriminates). `--mutant NAME`
builds a COPY of the tree (`tree_copy.make_copy`), applies its edits (each
anchor asserted to occur exactly once), builds it by the copy's own `make
app-debug` (`make app` under `RC_PROOF_APP=release`) and runs every row on it
(H1 against `--control`, default tools/proof/work/t3-1/ctl), the probes built
over the copy's `app/Sources`. MUTANT PASS when every named row FAILED; every
other row that failed is printed.
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed (a
mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import hashlib
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

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import reference_build  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

BASE = ROOT / "tools/proof/work/hdr"
WORK = BASE / "run"
HOME = WORK / "home"
MEDIA = BASE / "media"
CONTROL = "tools/proof/work/t3-1/ctl"
PICK_PROBE = ROOT / "tools/proof/hdr_pick_probe.swift"
MATH_PROBE = ROOT / "tools/proof/hdr_probe.swift"
WRITER = ROOT / "tools/proof/applelog_writer.swift"
RECORDINGS = Path.home() / "Movies" / "Frame Job Recordings"
CALL_BOUND = 300
BUILD_BOUND = 1500
REVERSE_BOUND = 300
SEC = 600_000
FRAME = SEC // 30
T = SEC // 2
W, H = 1024, 128
GREY_ROW, CHROMA_ROW = 32, 96
SW, SH = 640, 360
BASE_FILTER = ("color=c=black:size=1024x128:rate=30:duration=1,format=yuv422p10le,"
               "geq=lum='64+X*876/(W-1)':cb='if(lt(Y,64),512,112+X*800/(W-1))':"
               "cr='if(lt(Y,64),512,912-X*800/(W-1))'")
TAG709 = ["-colorspace", "bt709", "-color_primaries", "bt709", "-color_trc", "bt709"]
# name: (primaries, transfer, matrix) for prores_metadata and colr; None = untagged.
RETAGS = {"bt709": ("bt709", "bt709", "bt709"),
          "untagged": None,
          "hlg": ("bt2020", "arib-std-b67", "bt2020nc"),
          "pq": ("bt2020", "smpte2084", "bt2020nc"),
          "b2020_709": ("bt2020", "bt709", "bt2020nc"),
          "p3_709": ("smpte432", "bt709", "bt709")}
HEVC10 = {"hlg_hevc": ("bt2020", "arib-std-b67", "bt2020nc"),
          "srgb": ("bt709", "iec61966-2-1", "bt709"),
          "b2020_2020": ("bt2020", "bt2020-10", "bt2020nc"),
          "p3srgb": ("smpte432", "iec61966-2-1", "bt709")}
# GR-15's numbers (spec §11 GR-15, T3-1's append) and the standards' constants.
HLG_GAMMA, HLG_GAIN, KNEE, HLG_WHITE = 0.96, 1.07, 0.39, 1.07
PQ_REFERENCE, PQ_WHITE, DISPLAY_GAMMA = 203.0, 1000.0, 2.4
# The gamma of Core Media's BT.709 profile (`curv` 502/256): the sRGB arm's encode
# is its inverse (GR-15 as amended, M7).
CM709_GAMMA = 502 / 256
HLG_A = 0.17883277
HLG_B = 1 - 4 * HLG_A
HLG_C = 0.5 - HLG_A * math.log(4 * HLG_A)
PQ_M1, PQ_M2 = 2610 / 16384, 2523 / 4096 * 128
PQ_C1, PQ_C2, PQ_C3 = 3424 / 4096, 2413 / 4096 * 32, 2392 / 4096 * 32
# Published chromaticities (x, y) of R, G, B, and D65.
PRIMARIES = {"bt709": ((0.640, 0.330), (0.300, 0.600), (0.150, 0.060)),
             "bt2020": ((0.708, 0.292), (0.170, 0.797), (0.131, 0.046)),
             "p3d65": ((0.680, 0.320), (0.265, 0.690), (0.150, 0.060))}
D65 = (0.3127, 0.3290)
LUMA2020 = (0.2627, 0.6780, 0.0593)
LUMA709 = (0.2126, 0.7152, 0.0722)
KR_KB = {"bt709": (0.2126, 0.0722), "bt2020nc": (0.2627, 0.0593)}
APPLE = {"hlg": [(0.25, 0.215), (0.5, 0.384), (0.75, 0.604), (1.0, 1.0)],
         "pq": [(0.5, 0.719), (0.75, 1.0)]}
APPLE_BOUND = 3
PATCH = (0.42, 0.84, 1.17)
TIMING = re.compile(r"\[framejob\] compositor: ([\d.]+) ms average, ([\d.]+) ms worst over 120 "
                    r"frames(?:, (\d+) input passes)?")
# H1's SDR fixtures: (name, canvas width, height).
H1_FIXTURES = [("bt709", W, H), ("untagged", W, H), ("h264_709", SW, SH),
               ("h264_untagged", SW, SH), ("hevc8_matrix", SW, SH), ("still8", SW, SH),
               ("prores4444", SW, SH), ("webm", SW, SH), ("srgb", W, H), ("applelog", W, H)]
H1_SUFFIX = {"still8": ".png", "webm": ".webm"}
PICK_POINTS = {(W, H): [[256.5, 32.5], [512.5, 96.5], [900.5, 100.5]],
               (SW, SH): [[320.5, 180.5], [100.5, 60.5], [540.5, 300.5]]}
ROWS = ["H1", "H1m", "H1a", "H1s", "H1w", "H2", "H3", "H4", "H5", "H6", "H7", "R0", "TI", "P1",
        "P2", "P3", "P4", "Z1"]
# H7's fixtures: libx265 lossless with the PQ tags; pq_hdr10 adds HDR10 static metadata
# naming a 4,000 cd/m² peak, not the 1,000 the conversion assumes (GR-15's PQ 1000/203),
# so equal renders mean the metadata is ignored, not followed. Issue batch B96 (#281)
# added two: pq_hdr10_600 (a 600 cd/m² mastering display and MaxCLL 600, both below
# the conversion's white) and pq_hdr10_cll (the 4,000 cd/m² display with MaxCLL 1,000),
# which separates the two fields in Apple's reading.
PQ_X265 = "lossless=1:colorprim=bt2020:transfer=smpte2084:colormatrix=bt2020nc"
HDR10_DISPLAY = ":master-display=G(13250,34500)B(7500,3000)R(34000,16000)WP(15635,16450)"
# name: (the mastering display's maximum luminance in x265's 0.0001 cd/m², MaxCLL).
HDR10_FIXTURES = {"pq_hdr10": (40000000, 4000), "pq_hdr10_600": (6000000, 600),
                  "pq_hdr10_cll": (40000000, 1000)}
H7_FIXTURES = ["pq_plain"] + list(HDR10_FIXTURES)
SIDE_DATA = ("Mastering display metadata", "Content light level metadata")


def hdr10_params(name):
    """x265's HDR10 static metadata for `name` (an HDR10_FIXTURES key)."""
    luminance, cll = HDR10_FIXTURES[name]
    return f"{HDR10_DISPLAY}L({luminance},50):max-cll={cll},400"


def hdr10_peak(name):
    """What ffprobe prints for `name`'s peaks (a stale fixture fails the CONTROL)."""
    luminance, cll = HDR10_FIXTURES[name]
    return (f"max_luminance={luminance}/10000", f"max_content={cll}")


BASE_COMMIT = "716720c"
BASE_TREE = BASE / f"base-{BASE_COMMIT}"
INPUT_SWIFT = "app/Sources/InputConversions.swift"
STAGE_SWIFT = "app/Sources/Compositor+Input.swift"
COMPOSITOR = "app/Sources/Compositor.swift"
BUILDER = "app/Sources/CompositionBuilder.swift"
SHADER = "app/Resources/Shaders/Compositor.metal"
P_ROWS = {"P1", "P2", "P3", "P4"}
RECORDS = {"R0"}
# name: ([(file, anchor, replacement), …], the rows that must fail).
MUTANTS = {
    "no-conform": ([(STAGE_SWIFT, "    override var canConformColorOfSourceFrames: Bool { true }\n",
                     "    override var canConformColorOfSourceFrames: Bool { false }\n")],
                   ["H2", "H3"]),
    "hlg-branch-moved": ([(SHADER, "    return select(high, low, v <= 0.5);\n",
                           "    return select(high, low, v <= 0.45);\n")], ["P3"]),
    "matrix-transposed": ([(INPUT_SWIFT, "        return simd_float3x3(rows: rows)\n",
                            "        return simd_float3x3(columns: (rows[0], rows[1], rows[2]))\n")],
                          ["H3", "H5", "H1w", "P2", "P3"]),
    "shoulder-dropped": ([(SHADER, "    return l * (s / m);\n", "    return min(l, 1.0);\n")],
                         ["H3", "H4", "P3"]),
    "lift-dropped": ([(SHADER, "    return y <= 0.0 ? float3(0.0) : y + (l - y) * (y / (y - low));\n",
                       "    return max(l, 0.0);\n")], ["H4", "P3"]),
    "no-composition-color": ([
        (BUILDER, "            colorPrimaries: converts ? AVVideoColorPrimaries_ITU_R_709_2 : nil,\n",
         "            colorPrimaries: nil,\n"),
        (BUILDER, "            colorTransferFunction: converts ? AVVideoTransferFunction_ITU_R_709_2 : "
         "nil,\n", "            colorTransferFunction: nil,\n"),
        (BUILDER, "            colorYCbCrMatrix: converts ? AVVideoYCbCrMatrix_ITU_R_709_2 : nil,\n",
         "            colorYCbCrMatrix: nil,\n")], ["H2", "H3", "H1m"]),
    "select-by-primaries": ([(INPUT_SWIFT, "        guard logTransfer == nil else { return nil }\n",
                              "        if let wide = wide(primaries) { return wide }\n")],
                            ["H1", "P1"]),
    "convert-everywhere": ([(BUILDER, "        let converts = convertsSources(videoTracks) || "
                                      "plan.convertsMedia\n",
                             "        let converts = true\n")], ["H1", "H1m"]),
    "conform-everywhere": ([
        (COMPOSITOR, "    var canConformColorOfSourceFrames: Bool { false }\n",
         "    var canConformColorOfSourceFrames: Bool { true }\n"),
        (COMPOSITOR, "    var supportsHDRSourceFrames: Bool { false }\n",
         "    var supportsHDRSourceFrames: Bool { true }\n")], ["H1m"]),
    "srgb-arm-dropped": ([(INPUT_SWIFT, "        default: return .srgb(.bt709)\n",
                           "        default: return nil\n")], ["H1s", "P1"]),
    "srgb-starts-conversion": ([(INPUT_SWIFT,
                                 "    var startsConversion: Bool { self != .srgb(.bt709) }\n",
                                 "    var startsConversion: Bool { true }\n")], ["H1", "P1"]),
    "srgb-wide-as-sdrwide": ([(INPUT_SWIFT,
                               "        case Label.primaries2020: return .srgb(.bt2020)\n"
                               "        case Label.p3D65: return .srgb(.p3D65)\n",
                               "        case Label.primaries2020: return .sdrWide(.bt2020)\n"
                               "        case Label.p3D65: return .sdrWide(.p3D65)\n")],
                             ["H1w", "P1"]),
}
rows = {}
selected = set(ROWS)
REFUSED = {}


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good) and rows.get(key, True)
    record = key in RECORDS
    mark = "  rec  " if record else ("  ok   " if good else "  FAIL ")
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


def attempt(client, tool, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    if client is None:
        return {"ok": False, "error": "no instance"}
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def reply(got):
    return got["reply"] if got["ok"] and isinstance(got["reply"], dict) else {}


# ---- the oracle -----------------------------------------------------------------

def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def mat_vec(m, v):
    return [sum(m[i][k] * v[k] for k in range(3)) for i in range(3)]


def mat_inv(m):
    (a, b, c), (d, e, f), (g, h, i) = m
    det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    return [[(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det],
            [(f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det],
            [(d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]]


def npm(name):
    """RGB → XYZ for `name`'s primaries and D65 (the standard derivation)."""
    columns = [[x / y, 1.0, (1 - x - y) / y] for x, y in PRIMARIES[name]]
    p = [[columns[j][i] for j in range(3)] for i in range(3)]
    xw, yw = D65
    s = mat_vec(mat_inv(p), [xw / yw, 1.0, (1 - xw - yw) / yw])
    return [[p[i][j] * s[j] for j in range(3)] for i in range(3)]


def to709(name):
    """Linear `name` RGB → linear BT.709 RGB."""
    return mat_mul(mat_inv(npm("bt709")), npm(name))


def hlg_inverse(v):
    v = max(v, 0.0)
    return v * v / 3 if v <= 0.5 else (math.exp((v - HLG_C) / HLG_A) + HLG_B) / 12


def pq_eotf(v):
    p = min(max(v, 0.0), 1.0) ** (1 / PQ_M2)
    return (max(p - PQ_C1, 0.0) / (PQ_C2 - PQ_C3 * p)) ** (1 / PQ_M1)


def shoulder(m, white):
    if m <= KNEE:
        return m
    if m >= white:
        return 1.0
    t, tw = (m - KNEE) / (1 - KNEE), (white - KNEE) / (1 - KNEE)
    return KNEE + (1 - KNEE) * t * (1 + t / (tw * tw)) / (1 + t)


def convert(kind, primaries, rgb):
    """GR-15's step 0 on one straight R'G'B' signal: (the encoded output, the
    linear BT.709 colour before the lift). `kind` is hlg, pq, sdr (wide-gamut
    SDR) or srgb (the sRGB arm: IEC 61966-2-1's EOTF, the matrix, the inverse
    of Core Media's 709 gamma)."""
    m = to709(primaries)
    if kind == "srgb":
        light = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
                 for c in (max(v, 0.0) for v in rgb)]
        linear = mat_vec(m, light)
        return [max(c, 0.0) ** (1 / CM709_GAMMA) for c in linear], linear
    if kind == "sdr":
        linear = mat_vec(m, [max(c, 0.0) ** DISPLAY_GAMMA for c in rgb])
        return [max(c, 0.0) ** (1 / DISPLAY_GAMMA) for c in linear], linear
    if kind == "hlg":
        e = [hlg_inverse(c) for c in rgb]
        ys = sum(w * c for w, c in zip(LUMA2020, e))
        light = [HLG_GAIN * c * ys ** (HLG_GAMMA - 1) if ys > 1e-6 else 0.0 for c in e]
        white = HLG_WHITE
    else:
        light = [pq_eotf(c) * 10000 / PQ_REFERENCE for c in rgb]
        white = PQ_WHITE / PQ_REFERENCE
    linear = mat_vec(m, light)
    out = list(linear)
    low = min(out)
    if low < 0:
        y = sum(w * c for w, c in zip(LUMA709, out))
        out = [0.0] * 3 if y <= 0 else [y + (c - y) * y / (y - low) for c in out]
    top = max(out)
    if top > KNEE:
        out = [c * shoulder(top, white) / top for c in out]
    return [max(c, 0.0) ** (1 / DISPLAY_GAMMA) for c in out], linear


def code8(value):
    return round(255 * min(max(value, 0.0), 1.0))


def hue(rgb):
    p = rgb[0] - rgb[1]
    q = (rgb[0] + rgb[1]) / 2 - rgb[2]
    return math.degrees(math.atan2(q, p))


def hue_gap(a, b):
    d = abs(a - b) % 360
    return min(d, 360 - d)


# ---- the selector's table, mirrored (Approach 3) for R0 ------------------------

def arm(primaries, transfer):
    """The arm `InputConversion.choose` gives ffprobe's names; None = identity."""
    gamut = {"bt2020": "bt2020", "smpte432": "p3d65", "bt709": "bt709"}
    if transfer in ("arib-std-b67", "smpte2084"):
        kind = "hlg" if transfer == "arib-std-b67" else "pq"
        return f"{kind}({gamut.get(primaries, 'bt2020')})"
    if transfer == "iec61966-2-1":
        return f"srgb({gamut.get(primaries, 'bt709')})"
    if transfer in ("bt709", "bt2020-10", "bt2020-12") and primaries in ("bt2020", "smpte432"):
        return f"sdrWide({gamut[primaries]})"
    return None


# ---- fixtures -------------------------------------------------------------------

def ffmpeg_make(out, argv, seconds=600):
    if out.exists():
        return out
    MEDIA.mkdir(parents=True, exist_ok=True)
    made = bounded.run(["ffmpeg", "-v", "error", "-y", *argv, str(out)], seconds)
    if made["rc"] != 0 or not out.exists():
        print(f"       ffmpeg {out.name}: rc {made['rc']} {made['stderr'][-300:]}", flush=True)
        out.unlink(missing_ok=True)
        return None
    return out


def stream(path):
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                       "stream=codec_name,profile,pix_fmt,width,height,color_space,"
                       "color_transfer,color_primaries", "-of", "json", str(path)], 60)
    try:
        return json.loads(ran["stdout"])["streams"][0]
    except (ValueError, KeyError, IndexError):
        return {}


def tags(probe):
    return "/".join(str(probe.get(k, "-")) for k in ("color_space", "color_transfer",
                                                     "color_primaries"))


def checked(name, out, want):
    """`out` kept only when ffprobe reads every (key, value) of `want`; else
    None, REFUSED[name] saying why, and the file removed."""
    if out is None:
        REFUSED[name] = REFUSED.get(name) or f"{name} was not made"
        return None
    probe = stream(out)
    wrong = {k: probe.get(k) for k, v in want.items()
             if probe.get(k, "unknown" if v == "unknown" else None) != v}
    if wrong:
        REFUSED[name] = f"{out.name} refused: ffprobe read {wrong}, want {want}"
        print(f"       {REFUSED[name]}", flush=True)
        out.unlink(missing_ok=True)
        return None
    return out


def base():
    return checked("base", ffmpeg_make(MEDIA / "base.mov", [
        "-f", "lavfi", "-i", BASE_FILTER, "-c:v", "prores_ks", "-profile:v", "3",
        "-pix_fmt", "yuv422p10le"]), {"codec_name": "prores", "pix_fmt": "yuv422p10le",
                                      "width": W, "height": H})


def retag(name):
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    tagset = RETAGS[name]
    if tagset is None:
        bsf, colr = "prores_metadata=color_primaries=unknown:color_trc=unknown:colorspace=unknown", []
        want = {"codec_name": "prores"}
    else:
        primaries, transfer, matrix = tagset
        bsf = (f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:"
               f"colorspace={matrix}")
        colr = ["-color_primaries", primaries, "-color_trc", transfer, "-colorspace", matrix,
                "-movflags", "+write_colr"]
        want = {"color_primaries": primaries, "color_transfer": transfer, "color_space": matrix}
    out = MEDIA / f"{name}.mov"
    made = ffmpeg_make(out, ["-i", str(source), "-c", "copy", "-bsf:v", bsf, *colr], 120)
    kept = checked(name, made, want)
    if kept is not None and tagset is None:
        probe = stream(kept)
        known = {"bt709", "bt2020", "smpte432", "arib-std-b67", "smpte2084", "bt2020nc",
                 "iec61966-2-1", "bt2020-10"}
        if any(probe.get(k) in known for k in
               ("color_primaries", "color_transfer", "color_space")):
            REFUSED[name] = f"untagged.mov refused: ffprobe read {tags(probe)}"
            kept.unlink()
            return None
    return kept


def hevc10(name, tagset, out=None):
    """The ramp through `hevc_videotoolbox` Main 10 with `tagset`'s three tags
    (None for one ffprobe reads as absent), as precision's ramp10_hlg is made."""
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    primaries, transfer, matrix = tagset
    params, flags, want = [], [], {"codec_name": "hevc", "profile": "Main 10",
                                   "pix_fmt": "yuv420p10le"}
    for key, flag, value in (("color_primaries", "-color_primaries", primaries),
                             ("color_trc", "-color_trc", transfer),
                             ("colorspace", "-colorspace", matrix)):
        if value not in (None, "unknown"):
            params.append(f"{key}={value}")
            flags += [flag, value]
    want.update({k: v for k, v in (("color_primaries", primaries),
                                   ("color_transfer", transfer), ("color_space", matrix))
                 if v not in (None, "unknown")})
    vf = "format=yuv420p10le" + (",setparams=" + ":".join(params) if params else "")
    made = ffmpeg_make(out or MEDIA / f"{name}.mov", [
        "-i", str(source), "-vf", vf, "-c:v", "hevc_videotoolbox", "-profile:v", "main10",
        "-pix_fmt", "p010le", "-tag:v", "hvc1", "-b:v", "20M", *flags], 300)
    return checked(name, made, want)


def testsrc(name, extra, want, suffix=".mov", source="testsrc2"):
    return checked(name, ffmpeg_make(MEDIA / f"{name}{suffix}", [
        "-f", "lavfi", "-i", f"{source}=size={SW}x{SH}:rate=30:duration=1", *extra], 300), want)


def applelog():
    out = MEDIA / "applelog.mov"
    if not out.exists():
        source = retag("bt709")
        if source is None:
            REFUSED["applelog"] = REFUSED.get("bt709")
            return None
        writer = BASE / "applelog-writer" / "applelog_writer"
        try:
            swift_build.build(sources=[WRITER], output=writer, timeout=BUILD_BOUND)
        except swift_build.SwiftBuildFailed as failure:
            REFUSED["applelog"] = f"applelog_writer did not build: {str(failure)[:300]}"
            return None
        made = bounded.run([str(writer), str(source), str(out)], 120)
        print(f"       applelog_writer: {(made['stdout'] + made['stderr']).strip()[-200:]}",
              flush=True)
        if made["rc"] != 0 or not out.exists():
            REFUSED["applelog"] = f"applelog_writer exited {made['rc']}"
            out.unlink(missing_ok=True)
            return None
    return checked("applelog", out, {"color_space": "bt2020nc", "color_transfer": "unknown",
                                     "color_primaries": "bt2020"})


def fixture(name):
    """`name`'s file under MEDIA, made when missing; None when refused."""
    if name in RETAGS:
        return retag(name)
    if name in HEVC10:
        return hevc10(name, HEVC10[name])
    if name == "applelog":
        return applelog()
    if name == "h264_709":
        return testsrc(name, ["-vf", "setparams=color_primaries=bt709:color_trc=bt709:"
                              "colorspace=bt709", "-c:v", "libx264", "-pix_fmt", "yuv420p",
                              "-crf", "18", *TAG709],
                       {"codec_name": "h264", "color_space": "bt709", "color_transfer": "bt709",
                        "color_primaries": "bt709"}, ".mp4")
    if name == "h264_untagged":
        return testsrc(name, ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18"],
                       {"codec_name": "h264"}, ".mp4")
    if name == "hevc8_matrix":
        made = testsrc(name, ["-vf", "format=yuv420p,setparams=colorspace=bt709",
                              "-c:v", "hevc_videotoolbox", "-profile:v", "main", "-tag:v",
                              "hvc1", "-b:v", "8M", "-colorspace", "bt709"],
                       {"codec_name": "hevc", "pix_fmt": "yuv420p", "color_space": "bt709"})
        probe = stream(made) if made else {}
        if made and (probe.get("color_primaries", "unknown") != "unknown"
                     or probe.get("color_transfer", "unknown") != "unknown"):
            REFUSED[name] = f"hevc8_matrix refused: ffprobe read {tags(probe)}"
            made.unlink()
            return None
        return made
    if name == "still8":
        return checked(name, ffmpeg_make(MEDIA / "still8.png", [
            "-f", "lavfi", "-i", f"testsrc2=size={SW}x{SH}:rate=1:duration=1", "-frames:v", "1",
            "-pix_fmt", "rgb24"]), {"pix_fmt": "rgb24"})
    if name == "prores4444":
        return testsrc(name, ["-vf", "format=yuva444p10le,geq=lum='lum(X,Y)':cb='cb(X,Y)':"
                              "cr='cr(X,Y)':a='X*1023/(W-1)',setparams=color_primaries=bt709:"
                              "color_trc=bt709:colorspace=bt709", "-c:v", "prores_ks",
                              "-profile:v", "4", "-pix_fmt", "yuva444p10le", *TAG709],
                       {"codec_name": "prores", "pix_fmt": "yuva444p12le",
                        "color_transfer": "bt709"})
    if name == "webm":
        return checked(name, ffmpeg_make(MEDIA / "webm.webm", [
            "-f", "lavfi", "-i", f"testsrc2=size={SW}x{SH}:rate=30:duration=2",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2",
            "-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p", "-b:v", "500k", "-c:a", "libopus"]),
            {"codec_name": "vp9"})
    if name == "hevc_alpha":
        return testsrc(name, ["-vf", "format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':"
                              "a='255*X/(W-1)',setparams=color_primaries=bt709:color_trc=bt709:"
                              "colorspace=bt709", "-c:v", "hevc_videotoolbox", "-alpha_quality",
                              "0.75", "-pix_fmt", "bgra", "-tag:v", "hvc1", "-b:v", "8M"],
                       {"codec_name": "hevc", "color_transfer": "bt709",
                        "color_primaries": "bt709"})
    if name in H7_FIXTURES:
        return pq_x265(name)
    if name in ("hlg4k", "bt709_4k"):
        return four_k(name)
    if name in MEDIA_REC:
        return MEDIA_REC[name]
    raise ValueError(name)


def pq_x265(name):
    """H7's fixtures: the ramp through libx265 lossless, 4:2:0 10-bit, PQ-tagged;
    each HDR10_FIXTURES name with its x265 HDR10 static metadata."""
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    params = PQ_X265 + (hdr10_params(name) if name in HDR10_FIXTURES else "")
    made = ffmpeg_make(MEDIA / f"{name}.mov", [
        "-i", str(source), "-vf", "format=yuv420p10le,setparams=color_primaries=bt2020:"
        "color_trc=smpte2084:colorspace=bt2020nc", "-c:v", "libx265", "-preset", "fast",
        "-tag:v", "hvc1", "-color_primaries", "bt2020", "-color_trc", "smpte2084",
        "-colorspace", "bt2020nc", "-x265-params", params], 300)
    return checked(name, made, {"codec_name": "hevc", "pix_fmt": "yuv420p10le",
                                "color_primaries": "bt2020", "color_transfer": "smpte2084",
                                "color_space": "bt2020nc"})


def four_k(name):
    """TI's 4K 4 s ProRes twins: the ramp scaled up, looped, re-tagged."""
    source = base()
    if source is None:
        REFUSED[name] = REFUSED.get("base")
        return None
    plain = ffmpeg_make(MEDIA / "ramp4k.mov", [
        "-stream_loop", "3", "-i", str(source), "-vf", "scale=3840:2160:flags=bilinear",
        "-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"], 600)
    if plain is None:
        REFUSED[name] = "ffmpeg did not make ramp4k.mov"
        return None
    primaries, transfer, matrix = RETAGS["hlg" if name == "hlg4k" else "bt709"]
    made = ffmpeg_make(MEDIA / f"{name}.mov", [
        "-i", str(plain), "-c", "copy", "-bsf:v",
        f"prores_metadata=color_primaries={primaries}:color_trc={transfer}:colorspace={matrix}",
        "-color_primaries", primaries, "-color_trc", transfer, "-colorspace", matrix,
        "-movflags", "+write_colr"], 120)
    return checked(name, made, {"width": 3840, "height": 2160, "color_transfer": transfer})


def h1_file(name):
    """H1's fixture's file name in `DIR/media/`."""
    return name + H1_SUFFIX.get(name, ".mp4" if name.startswith("h264") else ".mov")


def h1_media(name, control):
    """H1's fixture: DIR's copy when DIR holds one (compare, mutants), else
    MEDIA's (capture copies it into DIR)."""
    if control is not None:
        copy = control / "media" / h1_file(name)
        if copy.exists():
            return copy
        REFUSED[name] = f"{copy} is missing from the control"
        return None
    return fixture(name)


# ---- decoding -------------------------------------------------------------------

def decode(path, pix_fmt, frames=1, extra=()):
    argv = ["ffmpeg", "-v", "error", "-i", str(path), *extra]
    if frames is not None:
        argv += ["-frames:v", str(frames)]
    try:
        raw = subprocess.run(argv + ["-f", "rawvideo", "-pix_fmt", pix_fmt, "-"],
                             capture_output=True, timeout=300, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw or None


class Yuv:
    """One frame's 10-bit planes: Y at (x, y), chroma at its subsampled site."""

    def __init__(self, raw, width, height, sub_x, sub_y):
        n = width * height
        cw, ch = -(-width // sub_x), -(-height // sub_y)
        values = struct.unpack(f"<{n + 2 * cw * ch}H", raw[:2 * (n + 2 * cw * ch)])
        self.y, self.cb, self.cr = values[:n], values[n:n + cw * ch], values[n + cw * ch:]
        self.width, self.cw, self.sx, self.sy = width, cw, sub_x, sub_y

    def codes(self, x, y):
        c = (y // self.sy) * self.cw + x // self.sx
        return self.y[y * self.width + x], self.cb[c], self.cr[c]

    def rgb(self, x, y, matrix):
        """Limited-range R'G'B' (unclamped) through `matrix`'s Kr, Kb."""
        return rgb_of(*self.codes(x, y), matrix)


def rgb_of(luma, cb, cr, matrix):
    """10-bit limited-range codes → R'G'B' (unclamped) through `matrix`'s Kr, Kb."""
    kr, kb = KR_KB[matrix]
    yy, pb, pr = (luma - 64) / 876, (cb - 512) / 896, (cr - 512) / 896
    r = yy + 2 * (1 - kr) * pr
    b = yy + 2 * (1 - kb) * pb
    g = (yy - kr * r - kb * b) / (1 - kr - kb)
    return [r, g, b]


def envelope(kind, primaries, codes, matrix):
    """H4/H5's bound: per channel, the 8-bit range of the oracle evaluated at
    the fixture's Y', Cb and Cr codes each moved by −1, 0, +1 (27 evaluations),
    widened by 1 level. (low, high) triples."""
    luma, cb, cr = codes
    outs = [[code8(c) for c in convert(kind, primaries,
                                       rgb_of(luma + a, cb + b, cr + c, matrix))[0]]
            for a in (-1, 0, 1) for b in (-1, 0, 1) for c in (-1, 0, 1)]
    return ([min(o[i] for o in outs) - 1 for i in range(3)],
            [max(o[i] for o in outs) + 1 for i in range(3)])


def inside(got, bounds):
    low, high = bounds
    return all(lo <= g <= hi for g, lo, hi in zip(got, low, high))


def yuv_frames(path, width, height, count=1):
    """The first `count` frames of a 4:2:2 or 4:2:0 10-bit file as Yuv, or None."""
    probe = stream(path)
    fmt = "yuv420p10le" if "420" in probe.get("pix_fmt", "") else "yuv422p10le"
    sub_y = 2 if fmt == "yuv420p10le" else 1
    raw = decode(path, fmt, count)
    size = 2 * (width * height + 2 * -(-width // 2) * -(-height // sub_y))
    if not raw or len(raw) < size * count:
        return None
    return [Yuv(raw[i * size:(i + 1) * size], width, height, 2, sub_y) for i in range(count)]


class Frame:
    """A render_frame PNG decoded at 16 bits (`rgb48le`)."""

    def __init__(self, path, width, height):
        raw = decode(path, "rgb48le")
        self.ok = bool(raw) and len(raw) >= width * height * 6
        self.values = struct.unpack(f"<{width * height * 3}H", raw[:width * height * 6]) \
            if self.ok else ()
        self.width, self.path = width, path

    def px(self, x, y):
        at = (y * self.width + x) * 3
        return [v / 65535 for v in self.values[at:at + 3]]

    def px8(self, x, y):
        return [round(v * 65535 / 257) for v in self.px(x, y)]


def close_to(a, b, tolerance):
    return all(abs(x - y) <= tolerance for x, y in zip(a, b))


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()[:16]


# ---- the documents --------------------------------------------------------------

class Doc:
    def __init__(self, client, name, width, height):
        self.client, self.width, self.height = client, width, height
        self.path = WORK / f"{name}.framejob"
        self.made = attempt(client, "new_project", {"path": str(self.path)})["ok"]
        self.call("set_canvas", width=width, height=height, fps=[30, 1])
        c = self.project().get("canvas") or {}
        self.ok = self.made and c.get("width") == width and c.get("height") == height
        self.why = None if self.ok else "the project or its canvas was not made"

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def track(self):
        return (self.project().get("tracks") or [{}])[0].get("id")

    def place(self, path, at=0):
        """`path` imported (once) and placed on the first track at `at`; the clip id."""
        media = getattr(self, "_media", {})
        if path not in media:
            got = self.call("import_media", path=str(path))
            media[path] = reply(got).get("media")
            if media[path] is None:
                self.ok, self.why = False, f"import {Path(path).name}: {got.get('error')}"
            self._media = media
            # T3-2 (GR-16): an Apple-Log-labelled file is converted from import;
            # Camera Log ▸ None keeps every scene as T3-1 rendered it. Never
            # fires on the control, whose media carry no `color`.
            row = next((m for m in self.project().get("media") or []
                        if m.get("id") == media[path]), {})
            if row.get("color") is not None:
                self.call("set_media_color", media=media[path], color=None)
        if media[path] is None:
            return None
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=self.track(), media=media[path], at=at)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        if not got["ok"] or len(new) != 1:
            self.ok, self.why = False, f"add_clip {Path(path).name}: {got.get('error')}"
            return None
        return new[0]

    def render(self, tag, t=T):
        out = WORK / f"{tag}.png"
        out.unlink(missing_ok=True)
        got = self.call("render_frame", t=t, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def export(self, tag):
        out = WORK / f"{tag}.mov"
        out.unlink(missing_ok=True)
        got = self.call("export", preset="prores_422", path=str(out), size="document")
        if not (got["ok"] and out.exists()):
            print(f"       export {tag}: {got.get('error', 'no file')}", flush=True)
            return None
        return out

    def save(self, name):
        path = WORK / f"{name}.framejob"
        got = self.call("save_project", path=str(path))
        if got["ok"]:
            self.path = path
        return path if got["ok"] else None

    def close(self):
        return attempt(self.client, "close_project",
                       {"project": str(self.path), "discard": True})["ok"]


def wait_reverse(doc, tag):
    """precision_proof.py's wait: `cache/reversed/*.mov` with no `.partial`
    and no sheet. (files, None) or (files, why)."""
    folder = Path(doc.path) / "cache" / "reversed"
    deadline = time.monotonic() + REVERSE_BOUND
    while True:
        files = sorted(folder.glob("*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob("*.partial"))
        if files and not partial:
            got = doc.call("snapshot_ui", window="sheet", path=str(WORK / f"{tag}-sheet.png"))
            if not got["ok"] and "no sheet attached" in got.get("error", ""):
                return files, None
        if time.monotonic() > deadline:
            doc.call("cancel_sheet")
            return files, f"the reverse did not finish within {REVERSE_BOUND} s"
        time.sleep(0.25)


# ---- the pick probe -------------------------------------------------------------

def build_probe(source, sources, name):
    """`source` as `main.swift` over `sources` (an `app/Sources`), beside that
    tree's `Compositor.metal` as `default.metallib` and `Blank.mp4`. (binary,
    None) or (None, why)."""
    folder = WORK / name
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(source.read_text())
    resources = Path(sources).parent / "Resources"
    shader = resources / "Shaders/Compositor.metal"
    air, library = folder / "Compositor.air", folder / "default.metallib"
    shutil.copy2(resources / "Blank.mp4", folder / "Blank.mp4")
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                       300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                            str(library)], 300)
    if step["rc"] != 0 or not library.exists():
        return None, f"the shader did not build: {step['stderr'][-400:]}"
    try:
        defines = reference_build.tree_defines(Path(sources).parents[1], ["FRAMEJOB_DEV_TOOLS"])
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / name, defines=defines, timeout=BUILD_BOUND)
    except swift_build.SwiftBuildFailed as error:
        return None, f"{error} {error.diagnostics[:6]}"
    return built.binary, None


def base_sources():
    """716720c's `app/Sources` (and `app/Resources`, and `app/Bridging`, whose
    name says which dev-tools flag the tree spells), by `git archive` into
    BASE_TREE, made once and kept; None and why when the archive fails."""
    sources = BASE_TREE / "app/Sources"
    if (sources / "Compositor.swift").exists() and (BASE_TREE / "app/Bridging").is_dir():
        return sources, None
    tree_copy.remove_tree(str(BASE_TREE)) if BASE_TREE.exists() else None
    BASE_TREE.mkdir(parents=True)
    archive = BASE / f"base-{BASE_COMMIT}.tar"
    made = bounded.run(["git", "-C", str(ROOT), "archive", "-o", str(archive), BASE_COMMIT,
                        "app/Sources", "app/Resources", "app/Bridging"], 120)
    if made["rc"] == 0:
        made = bounded.run(["tar", "-xf", str(archive), "-C", str(BASE_TREE)], 120)
    archive.unlink(missing_ok=True)
    if made["rc"] != 0 or not (sources / "Compositor.swift").exists():
        return None, f"git archive {BASE_COMMIT} failed: {made['stderr'][-300:]}"
    return sources, None


def base_copy(package):
    """A copy of `package` whose `project.json` says version 18 — the base tree
    (716720c) refuses a newer file, and every number up to 18 it reads — or
    None and why when the package's media carry `color` (T3-2, GR-16), which
    the base tree would drop, so its frame would not be the tree's."""
    source = Path(package)
    try:
        text = (source / "project.json").read_text()
        project = json.loads(text)
    except (OSError, ValueError) as error:
        return None, f"{source.name}: {error}"
    if any(m.get("color") is not None for m in project.get("media") or []):
        return None, f"{source.name}: a media carries color"
    copy = source.with_name(source.stem + "-v18.framejob")
    if copy.exists():
        shutil.rmtree(copy)
    shutil.copytree(source, copy)
    (copy / "project.json").write_text(re.sub(r'"version":\s*\d+', '"version": 18', text,
                                              count=1))
    return copy, None


def run_picks(sources, picks, name="hdr_pick_probe"):
    """`hdr_pick_probe.swift` built over `sources` (None: the base tree) over
    `picks`; {tag: answer row}, or {"error": why}."""
    if sources is None:
        sources, why = base_sources()
        name = "hdr_pick_probe_base"
        if sources is None:
            return {"error": why}
    binary, why = build_probe(PICK_PROBE, sources, name)
    if binary is None:
        return {"error": f"the pick probe ({name}) did not build: {why}"}
    request, answer = WORK / f"{name}.json", WORK / f"{name}-answer.json"
    answer.unlink(missing_ok=True)
    request.write_text(json.dumps({"picks": picks}))
    ran = bounded.run([str(binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        return {row["tag"]: row for row in json.loads(answer.read_text())["rows"]}
    except (OSError, ValueError, KeyError):
        return {"error": f"the pick probe answered nothing (rc {ran['rc']}): "
                         f"{(ran['stdout'] + ran['stderr'])[-400:]}"}


# ---- H1 -------------------------------------------------------------------------

def h1_scene(client, name, path, width, height, reverse=False):
    """`path` alone (reversed when asked), rendered at 0 and T and saved for the
    pick probe: {renders: {tick: png}, package, clip, reverse file} or a why."""
    doc = Doc(client, f"h1-{name}", width, height)
    clip = doc.place(path) if doc.ok else None
    files = []
    if reverse and clip is not None:
        doc.call("set_reversed", clip=clip, reversed=True)
        files, late = wait_reverse(doc, f"h1-{name}")
        if late:
            doc.ok, doc.why = False, late
    renders = {t: doc.render(f"h1-{name}-{t}", t) for t in (0, T)} if doc.ok else {}
    package = doc.save(f"h1-{name}-saved") if doc.ok else None
    closed = doc.close()
    good = doc.ok and clip is not None and all(renders.values()) and package is not None
    return {"renders": renders, "package": package, "clip": clip,
            "reverse": files[0] if files else None, "why": doc.why, "ok": good,
            "closed": closed, "size": (width, height)}


def run_h1(client, mode, control, sources, state, extra=()):
    """H1's scenes; capture writes DIR's references, compare holds the tree to them."""
    scenes = {}
    fixtures = list(H1_FIXTURES) + list(extra)
    for name, width, height in fixtures:
        path = h1_media(name, None if mode == "capture" else control)
        if path is None:
            scenes[name] = {"ok": False, "why": REFUSED.get(name), "closed": True}
            continue
        if mode == "capture":
            (control / "media").mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, control / "media" / h1_file(name))
        scenes[name] = h1_scene(client, name, path, width, height)
    ramp = h1_media("bt709", None if mode == "capture" else control)
    scenes["reversed"] = h1_scene(client, "reversed", ramp, W, H, reverse=True) if ramp \
        else {"ok": False, "why": REFUSED.get("bt709"), "closed": True}
    picks = [{"tag": name, "package": str(s["package"]), "tick": T, "clips": [s["clip"]],
              "points": PICK_POINTS[s["size"]]} for name, s in scenes.items() if s["ok"]]
    answered = run_picks(sources, picks) if picks else {"error": "no scene"}
    state["h1_closed"] = all(s.get("closed") for s in scenes.values())
    record = {"picks": {}, "reverse": None}
    if mode == "capture":
        for name, s in scenes.items():
            for t, png in (s.get("renders") or {}).items():
                if png:
                    shutil.copy2(png, control / f"h1-{name}-{t}.png")
            row = answered.get(name) or {}
            record["picks"][name] = row.get("picked")
        rev = scenes["reversed"].get("reverse")
        if rev:
            shutil.copy2(rev, control / "media" / "reversed-intermediate.mov")
            record["reverse"] = digest(rev)
        state["h1_record"] = record
        failed = [n for n, s in scenes.items() if not s["ok"]]
        print(f"  H1 references captured for {len(scenes) - len(failed)} scenes"
              f"{'; NOT for ' + str({n: scenes[n].get('why') for n in failed}) if failed else ''}"
              f"; picks {answered.get('error') or 'answered'}", flush=True)
        state["capture_ok"] = not failed and "error" not in answered
        return
    try:
        recorded = json.loads((control / "capture.json").read_text())
    except (OSError, ValueError):
        recorded = {}
    misses = []
    for name, s in scenes.items():
        if not s["ok"]:
            misses.append(f"{name}: {s.get('why')}")
            continue
        for t, png in s["renders"].items():
            want = control / f"h1-{name}-{t}.png"
            if not want.exists():
                misses.append(f"{name}@{t}: no control PNG")
            elif png.read_bytes() != want.read_bytes():
                a, b = Frame(png, *s["size"]), Frame(want, *s["size"])
                differ = sum(1 for x, y in zip(a.values, b.values) if x != y)
                misses.append(f"{name}@{t}: PNG bytes differ ({differ} of {len(a.values)} "
                              f"16-bit samples differ)")
        got = (answered.get(name) or {}).get("picked")
        want = (recorded.get("picks") or {}).get(name)
        if got is None or got != want:
            misses.append(f"{name}: pick {got} vs control {want} "
                          f"{answered.get('error', '')}")
    rev = scenes["reversed"].get("reverse")
    same_intermediate = rev is not None and digest(rev) == recorded.get("reverse")
    check(f"H1 (STOP) {len(scenes)} SDR scenes: render_frame at 0 and 0.5 s byte-identical to "
          f"{control.name}'s, and the eyedropper's picks equal",
          not misses, f"{misses or 'all equal'}; the reverse's intermediate "
          f"{'equals' if same_intermediate else 'differs from'} the control's "
          f"({digest(rev) if rev else None} vs {recorded.get('reverse')})")


# ---- H2 -------------------------------------------------------------------------

def export_rgb8(frames, index, x, y):
    return [code8(c) for c in frames[index].rgb(x, y, "bt709")]


def run_h2(client, state):
    hlg, pq, hevc, bt709 = (fixture(n) for n in ("hlg", "pq", "hlg_hevc", "bt709"))
    scenes = [("hlg", [hlg], 0), ("pq", [pq], 0), ("hlg_hevc", [hevc], 0),
              ("sequence", [bt709, hlg, bt709], 30)]
    misses, closed, figures = [], True, []
    for name, paths, first in scenes:
        if any(p is None for p in paths):
            misses.append(f"{name}: fixture refused ({REFUSED})")
            continue
        doc = Doc(client, f"h2-{name}", W, H)
        for i, path in enumerate(paths):
            doc.place(path, at=i * SEC)
        renders = [doc.render(f"h2-{name}-{k}", (first + k) * FRAME) for k in (0, 5)] \
            if doc.ok else [None, None]
        out = doc.export(f"h2-{name}") if doc.ok else None
        closed = doc.close() and closed
        frames = yuv_frames(out, W, H, first + 6) if out else None
        if not doc.ok or frames is None or not all(renders):
            misses.append(f"{name}: {doc.why or 'no export or render'}")
            continue
        drawn = [Frame(r, W, H) for r in renders]
        worst_flash, worst_parity = 0, 0
        for x in range(0, W, 8):
            a = export_rgb8(frames, first, x, GREY_ROW)
            b = export_rgb8(frames, first + 5, x, GREY_ROW)
            worst_flash = max(worst_flash, max(abs(p - q) for p, q in zip(a, b)))
            for k, e in ((0, a), (1, b)):
                r = drawn[k].px8(x, GREY_ROW)
                worst_parity = max(worst_parity, max(abs(p - q) for p, q in zip(r, e)))
        mid = W // 2
        figures.append(f"{name}: export frame {first} vs +5 max |Δ| {worst_flash}, render vs "
                       f"export max |Δ| {worst_parity}; at x={mid} export "
                       f"{export_rgb8(frames, first, mid, GREY_ROW)} / "
                       f"{export_rgb8(frames, first + 5, mid, GREY_ROW)}, render "
                       f"{drawn[0].px8(mid, GREY_ROW)} / {drawn[1].px8(mid, GREY_ROW)}")
        if worst_flash > 1 or worst_parity > 1:
            misses.append(name)
    state["h2_closed"] = closed
    check("H2 the HDR clip's first exported frame equals its frame +5 on the grey row ±1, and "
          "render_frame at both ticks equals the export ±1 (HLG, PQ, HLG HEVC, BT.709|HLG|BT.709)",
          not misses, f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


# ---- H3, H4, H5: the conversion's values ----------------------------------------

def fixture_scene(client, name, t=T):
    """`name` alone at 1024×128 rendered at `t`: (Frame, the fixture's Yuv) or
    (None, why); the doc is closed."""
    path = fixture(name)
    if path is None:
        return None, f"{name} refused: {REFUSED.get(name)}"
    doc = Doc(client, f"v-{name}", W, H)
    doc.place(path) if doc.ok else None
    png = doc.render(f"v-{name}", t) if doc.ok else None
    closed = doc.close()
    source = yuv_frames(path, W, H)
    if png is None or source is None or not closed:
        return None, f"{name}: {doc.why or 'no render, no decode or not closed'}"
    frame = Frame(png, W, H)
    return (frame, source[0]) if frame.ok else (None, f"{name}: the PNG did not decode")


def render_at(frame, source, signal, matrix):
    """The render's encoded grey value at grey `signal`, interpolated between
    the two grey-row columns whose measured signals bracket it."""
    points = [(source.rgb(x, GREY_ROW, matrix)[1], frame.px(x, GREY_ROW)[1]) for x in range(W)]
    for (s0, v0), (s1, v1) in zip(points, points[1:]):
        if s0 <= signal <= s1 and s1 > s0:
            return v0 + (v1 - v0) * (signal - s0) / (s1 - s0)
    return points[-1][1] if signal >= points[-1][0] else points[0][1]


def run_h3(client, scenes):
    misses, figures = [], []
    for kind in ("hlg", "pq"):
        frame, source = scenes.get(kind) or (None, None)
        if frame is None:
            misses.append(f"{kind}: {source}")
            continue
        worst = 0
        for x in range(0, W, 8):
            rgb = source.rgb(x, GREY_ROW, "bt2020nc")
            want = [code8(c) for c in convert(kind, "bt2020", rgb)[0]]
            got = frame.px8(x, GREY_ROW)
            worst = max(worst, max(abs(a - b) for a, b in zip(got, want)))
            if not close_to(got, want, 1) and len(misses) < 12:
                misses.append(f"{kind} x={x} render {got} oracle {want}")
        apple = []
        for signal, target in APPLE[kind]:
            value = render_at(frame, source, signal, "bt2020nc")
            off = (value - target) * 255
            apple.append(f"{signal}→{value:.4f} ({off:+.2f})")
            if abs(off) > APPLE_BOUND:
                misses.append(f"{kind} Apple {signal}: {off:+.2f} levels")
        figures.append(f"{kind}: worst |Δ| against the oracle {worst} levels; Apple's points "
                       f"{', '.join(apple)}")
    check("H3 the HLG and PQ grey rows (every 8th column) = the oracle ±1 at 8 bits, and Apple's "
          "six points within 3/255", not misses,
          f"{misses[:12] or 'all within'}\n       " + "\n       ".join(figures))


def run_h4(scenes):
    frame, source = scenes.get("hlg") or (None, None)
    if frame is None:
        check("H4 the HLG chroma row is compressed, not clipped", False, f"{source}")
        return
    columns, nearest = [], None
    for x in range(0, W, 2):
        rgb = source.rgb(x, CHROMA_ROW, "bt2020nc")
        distance = sum((a - b) ** 2 for a, b in zip(rgb, PATCH))
        if nearest is None or distance < nearest[0]:
            nearest = (distance, x, rgb)
        out, linear = convert("hlg", "bt2020", rgb)
        if max(rgb) - min(rgb) >= 0.05 and (min(linear) < 0 or max(linear) > 1):
            columns.append(x)
    picked = sorted(set(columns) | {nearest[1]})
    misses, worst_hue, worst_value = [], 0.0, 0
    for x in picked:
        rgb = source.rgb(x, CHROMA_ROW, "bt2020nc")
        out, linear = convert("hlg", "bt2020", rgb)
        want = [code8(c) for c in out]
        bounds = envelope("hlg", "bt2020", source.codes(x, CHROMA_ROW), "bt2020nc")
        got = frame.px8(x, CHROMA_ROW)
        rendered = [c ** DISPLAY_GAMMA for c in frame.px(x, CHROMA_ROW)]
        gap = hue_gap(hue(rendered), hue(linear))
        worst_hue = max(worst_hue, gap)
        worst_value = max(worst_value, max(abs(a - b) for a, b in zip(got, want)))
        if (gap > 2 or not inside(got, bounds)) and len(misses) < 10:
            misses.append(f"x={x} render {got} oracle {want} envelope {bounds} hue gap "
                          f"{gap:.2f}°")
    _, px, prgb = nearest
    patch = f"the patch column x={px} (source {[round(c, 3) for c in prgb]}): render " \
            f"{frame.px8(px, CHROMA_ROW)}, oracle " \
            f"{[code8(c) for c in convert('hlg', 'bt2020', prgb)[0]]}"
    check(f"H4 the HLG chroma row: {len(columns)} columns (≥ 20, CONTROL) out of [0,1]³ after the "
          f"matrix, and the brief's patch: hue within 2°, values inside the oracle's ±1-code "
          f"envelope ±1 level",
          len(columns) >= 20 and not misses,
          f"{misses or 'all within'}; worst hue gap {worst_hue:.2f}°, worst |Δ| {worst_value}; "
          f"{patch}")


def run_h5(client, scenes, extra=None):
    names = [("b2020_709", "bt2020", "bt2020nc"), ("p3_709", "p3d65", "bt709"),
             ("b2020_2020", "bt2020", "bt2020nc")] + ([extra] if extra else [])
    misses, figures = [], []
    for name, primaries, matrix in names:
        frame, source = scenes.get(name) or (None, None)
        if frame is None:
            misses.append(f"{name}: {source}")
            continue
        grey_worst = chroma_worst = 0
        where, outside = None, []
        for x in range(0, W, 8):
            want = [code8(c) for c in source.rgb(x, GREY_ROW, matrix)]
            got = frame.px8(x, GREY_ROW)
            grey_worst = max(grey_worst, max(abs(a - b) for a, b in zip(got, want)))
            rgb = source.rgb(x, CHROMA_ROW, matrix)
            want = [code8(c) for c in convert("sdr", primaries, rgb)[0]]
            bounds = envelope("sdr", primaries, source.codes(x, CHROMA_ROW), matrix)
            got = frame.px8(x, CHROMA_ROW)
            gap = max(abs(a - b) for a, b in zip(got, want))
            if gap > chroma_worst:
                chroma_worst, where = gap, (x, got, want)
            if not inside(got, bounds):
                outside.append((x, got, bounds))
        mid = W // 2
        figures.append(f"{name}: grey worst |Δ| {grey_worst}, chroma worst |Δ| {chroma_worst} "
                       f"(x, render, oracle {where}); outside the envelope {outside[:3]}; "
                       f"grey at x={mid} {frame.px8(mid, GREY_ROW)} (signal "
                       f"{[code8(c) for c in source.rgb(mid, GREY_ROW, matrix)]})")
        if grey_worst > 1 or outside:
            misses.append(name)
    check("H5 the wide-gamut SDR files (BT.2020/BT.709, P3/BT.709, BT.2020/BT.2020-10): the grey "
          "row = the signal ±1, the chroma row inside the oracle's ±1-code envelope ±1 level",
          not misses,
          f"failed {misses or 'none'}\n       " + "\n       ".join(figures))


# ---- H6 -------------------------------------------------------------------------

def run_h6(client, sources, state):
    """H6 (revision 2): the HLG ramp's pick against the pick of its own
    `prores_422` export placed alone (a BT.709 file, today's path), both
    through the tree probe, ±3; the keyed export magenta ±8; the base-tree
    probe must fail the pick half (the CONTROL)."""
    hlg = fixture("hlg")
    if hlg is None:
        check("H6 the eyedropper picks the colour the export keys on", False,
              f"hlg refused: {REFUSED.get('hlg')}")
        return
    doc = Doc(client, "h6", W, H)
    doc.call("set_canvas", background=[1, 0, 1, 1])
    clip = doc.place(hlg) if doc.ok else None
    package = doc.save("h6-saved") if doc.ok else None
    first = doc.export("h6-plain") if doc.ok else None
    ref = Doc(client, "h6-ref", W, H)
    ref_clip = ref.place(first) if ref.ok and first else None
    ref_package = ref.save("h6-ref-saved") if ref_clip is not None else None
    state["h6_ref_closed"] = ref.close()
    point = [[256.5, 96.5]]
    asks = [{"tag": "hlg", "package": str(package), "tick": T, "clips": [clip], "points": point},
            {"tag": "ref", "package": str(ref_package), "tick": T, "clips": [ref_clip],
             "points": point}] if package and ref_package else []
    tree = run_picks(sources, asks) if asks else {"error": "not saved"}
    copies = [base_copy(ask["package"]) for ask in asks]
    refused = [why for copy, why in copies if copy is None]
    older = [dict(ask, package=str(copy)) for ask, (copy, _) in zip(asks, copies)]
    base = ({"error": f"the base tree's copy: {'; '.join(refused)}"} if refused
            else run_picks(None, older)) if asks else {"error": "not saved"}

    def pick(answer, tag):
        got = ((answer.get(tag) or {}).get("picked") or [None])[0]
        return [code8(c) for c in got] if got else None
    key = ((tree.get("hlg") or {}).get("keys") or [None])[0]
    keyed = doc.call("set_video", clips=[clip], patch={"chroma": {
        "key": key, "tolerance": 0.05, "softness": 0.1, "spill": 0.5}}) if key else {"ok": False}
    second = doc.export("h6-keyed") if keyed["ok"] else None
    state["h6_closed"] = doc.close()
    keyed_frames = yuv_frames(second, W, H, 16) if second else None
    shown = export_rgb8(keyed_frames, 15, 256, CHROMA_ROW) if keyed_frames else None
    mine, theirs = pick(tree, "hlg"), pick(tree, "ref")
    base_mine, base_theirs = pick(base, "hlg"), pick(base, "ref")
    agrees = mine is not None and theirs is not None and close_to(mine, theirs, 3)
    control_fails = base_mine is not None and base_theirs is not None \
        and not close_to(base_mine, base_theirs, 3)
    good = agrees and shown is not None and close_to(shown, [255, 0, 255], 8) and control_fails
    check("H6 the eyedropper's pick at (256, 96) at 0.5 s on the HLG ramp equals the pick of its "
          "own prores_422 export placed alone ±3, keyed with it (tolerance 0.05) the export shows "
          "magenta there ±8, and the base tree fails the pick half (CONTROL)", good,
          f"tree picks HLG {mine} / its export {theirs} (key {key}); keyed export {shown}; "
          f"base-tree picks {base_mine} / {base_theirs} (fails: {control_fails}); "
          f"{tree.get('error', '')} {base.get('error', '')} {doc.why or ''} "
          f"keyed {keyed.get('error', 'ok')}")


# ---- H1m, H1s, H1w: mixed compositions and the sRGB arm --------------------------

def saved_scene(client, name, paths, width=W, height=H):
    """`paths` one after another (1 s each) on one track, saved; (package,
    clip ids, Doc) — the Doc still open."""
    doc = Doc(client, name, width, height)
    clips = [doc.place(path, at=i * SEC) for i, path in enumerate(paths)] if doc.ok else []
    package = doc.save(f"{name}-saved") if doc.ok and all(c is not None for c in clips) \
        else None
    return package, clips, doc


def run_h1m(client, control, sources, state):
    """H1m (STOP): two mixed projects, at ticks showing no converted source:
    the base-tree probe's and the tree probe's PNG bytes and picks equal. The
    base tree reads a version-18 copy of each package (`base_copy`, T3-2); a
    package whose media carry `color` is a FAIL."""
    names = {n: h1_media(n, control) for n in ("srgb", "bt709", "untagged", "applelog")}
    names["hlg"] = fixture("hlg")
    scenes = [("mix_sdr", ["srgb", "bt709", "untagged"], [T, SEC + T, 2 * SEC + T]),
              ("mix_hdr", ["untagged", "hlg", "bt709", "applelog"], [T, 2 * SEC + T, 3 * SEC + T])]
    misses, asks = [], {"tree": [], "base": []}
    for scene, members, ticks in scenes:
        if any(names[m] is None for m in members):
            misses.append(f"{scene}: a fixture is missing ({REFUSED})")
            continue
        package, clips, doc = saved_scene(client, f"h1m-{scene}", [names[m] for m in members])
        state[f"h1m_{scene}_closed"] = doc.close()
        if package is None:
            misses.append(f"{scene}: {doc.why or 'not saved'}")
            continue
        older, why = base_copy(package)
        if older is None:
            misses.append(f"{scene}: the base tree's copy: {why}")
            continue
        for tick in ticks:
            for which in asks:
                asks[which].append({"tag": f"{scene}@{tick}",
                                    "package": str(package if which == "tree" else older),
                                    "tick": tick, "clips": clips, "points": PICK_POINTS[(W, H)],
                                    "png": str(WORK / f"h1m-{which}-{scene}-{tick}.png")})
    tree = run_picks(sources, asks["tree"]) if asks["tree"] else {"error": "no scene"}
    base = run_picks(None, asks["base"]) if asks["base"] else {"error": "no scene"}
    for ask in asks["tree"]:
        tag = ask["tag"]
        a, b = tree.get(tag) or {}, base.get(tag) or {}
        pa, pb = Path(a.get("png") or "/nonexistent"), Path(b.get("png") or "/nonexistent")
        if not (pa.exists() and pb.exists()):
            misses.append(f"{tag}: no PNG ({a.get('error') or tree.get('error')} / "
                          f"{b.get('error') or base.get('error')})")
            continue
        if pa.read_bytes() != pb.read_bytes():
            fa, fb = Frame(pa, W, H), Frame(pb, W, H)
            differ = sum(1 for x, y in zip(fa.values, fb.values) if x != y)
            misses.append(f"{tag}: PNG bytes differ ({differ} 16-bit samples differ)")
        if a.get("picked") != b.get("picked"):
            misses.append(f"{tag}: picks {a.get('picked')} vs base {b.get('picked')}")
    check("H1m (STOP) srgb|bt709|untagged and untagged|hlg|bt709|applelog, at ticks showing no "
          "converted source: the tree's PNG bytes and picks equal the base tree's (716720c)",
          not misses and bool(asks["tree"]), f"{misses or 'all equal'}")


def run_h1a(client, sources, state):
    """H1a (T3-3): alpha and WebM sources in a converting composition —
    prores4444 | hlg | hevc_alpha | webm on one 640×360 track; at the ticks
    showing no HLG the tree probe's PNG bytes and picks equal the base tree's
    (a version-18 copy, as H1m); at the HLG tick the tree's PNG must differ
    from the base's (the CONTROL: the tree's composition converts)."""
    members = ["prores4444", "hlg", "hevc_alpha", "webm"]
    paths = [fixture(n) for n in members]
    name = "H1a prores4444|hlg|hevc_alpha|webm (640×360): at the non-HLG ticks the tree's PNG " \
           "bytes and picks equal the base tree's (716720c); at the HLG tick the PNGs differ " \
           "(CONTROL)"
    if any(path is None for path in paths):
        check(name, False, f"a fixture is missing: {[n for n, p in zip(members, paths) if p is None]} "
                           f"({REFUSED})")
        return
    package, clips, doc = saved_scene(client, "h1a-mix", paths, SW, SH)
    state["h1a_closed"] = doc.close()
    if package is None:
        check(name, False, f"not saved: {doc.why}")
        return
    older, why = base_copy(package)
    if older is None:
        check(name, False, f"the base tree's copy: {why}")
        return
    control_tick = SEC + T
    ticks = [T, control_tick, 2 * SEC + T, 3 * SEC + T]
    asks = {which: [{"tag": f"h1a@{tick}", "package": str(package if which == "tree" else older),
                     "tick": tick, "clips": clips, "points": PICK_POINTS[(SW, SH)],
                     "png": str(WORK / f"h1a-{which}-{tick}.png")} for tick in ticks]
            for which in ("tree", "base")}
    tree = run_picks(sources, asks["tree"])
    base = run_picks(None, asks["base"])
    misses, figures, control = [], [], None
    for tick in ticks:
        tag = f"h1a@{tick}"
        a, b = tree.get(tag) or {}, base.get(tag) or {}
        pa, pb = Path(a.get("png") or "/nonexistent"), Path(b.get("png") or "/nonexistent")
        if not (pa.exists() and pb.exists()):
            misses.append(f"{tag}: no PNG ({a.get('error') or tree.get('error')} / "
                          f"{b.get('error') or base.get('error')})")
            continue
        same = pa.read_bytes() == pb.read_bytes()
        differ = 0
        if not same:
            fa, fb = Frame(pa, SW, SH), Frame(pb, SW, SH)
            differ = sum(1 for x, y in zip(fa.values, fb.values) if x != y)
        figures.append(f"{tag}: PNG bytes {'equal' if same else f'differ ({differ} 16-bit samples)'}"
                       f"; picks tree {a.get('picked')} base {b.get('picked')}")
        if tick == control_tick:
            control = not same
            continue
        if not same:
            misses.append(f"{tag}: PNG bytes differ ({differ} 16-bit samples differ)")
        if a.get("picked") != b.get("picked"):
            misses.append(f"{tag}: picks {a.get('picked')} vs base {b.get('picked')}")
    if control is not True:
        misses.append(f"CONTROL h1a@{control_tick}: the HLG tick's PNGs "
                      f"{'are equal' if control is False else 'were not drawn'}")
    check(name, not misses, f"{misses or 'all equal, the control differs'}\n       "
          + "\n       ".join(figures))


# ---- H7 -------------------------------------------------------------------------

def side_data(path, peak=()):
    """The side data ffprobe names on `path`'s first video frame, then the
    `peak` lines (`hdr10_peak`) it prints."""
    ran = bounded.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-read_intervals",
                       "%+#1", "-show_frames", "-show_entries", "frame=side_data_list",
                       str(path)], 60)
    lines = {line.strip() for line in ran["stdout"].splitlines()}
    return [name for name in SIDE_DATA if name in ran["stdout"]] + \
        [line for line in peak if line in lines]


def run_h7(client, sources, state):
    """H7 (T3-3; B96 for #281): PQ with and without HDR10 static metadata
    converts the same; Apple's own reading of each file printed beside it."""
    name = "H7 PQ with and without HDR10 static metadata (4,000 cd/m² display and MaxCLL; 600 " \
           "and 600; 4,000 and MaxCLL 1,000): ffprobe names the side data and each fixture's " \
           "own peaks, and none on pq_plain (CONTROL); each of the four grey rows (every 8th " \
           "column) = the PQ oracle ±1, and the four renders' PNG bytes equal"
    paths = {n: fixture(n) for n in H7_FIXTURES}
    if any(path is None for path in paths.values()):
        check(name, False, f"refused {REFUSED}")
        return
    found = {n: side_data(paths[n], hdr10_peak(n) if n in HDR10_FIXTURES else ())
             for n in H7_FIXTURES}
    control = not found["pq_plain"] and all(
        found[n] == list(SIDE_DATA + hdr10_peak(n)) for n in HDR10_FIXTURES)
    misses = [] if control else [f"CONTROL: side data {found}"]
    figures, frames = [f"side data {found}"], {}
    for fixture_name in H7_FIXTURES:
        frame, source = fixture_scene(client, fixture_name)
        if frame is None:
            misses.append(f"{fixture_name}: {source}")
            continue
        frames[fixture_name] = frame
        worst = 0
        for x in range(0, W, 8):
            rgb = source.rgb(x, GREY_ROW, "bt2020nc")
            want = [code8(c) for c in convert("pq", "bt2020", rgb)[0]]
            got = frame.px8(x, GREY_ROW)
            worst = max(worst, max(abs(a - b) for a, b in zip(got, want)))
            if not close_to(got, want, 1) and len(misses) < 12:
                misses.append(f"{fixture_name} x={x} render {got} oracle {want}")
        mid = W // 2
        figures.append(f"{fixture_name}: worst |Δ| against the oracle {worst} levels; x={mid} "
                       f"render {frame.px8(mid, GREY_ROW)} oracle "
                       f"{[code8(c) for c in convert('pq', 'bt2020', source.rgb(mid, GREY_ROW, 'bt2020nc'))[0]]}")
    if len(frames) == len(H7_FIXTURES):
        a = frames["pq_plain"]
        for other in HDR10_FIXTURES:
            b = frames[other]
            if Path(a.path).read_bytes() == Path(b.path).read_bytes():
                figures.append(f"pq_plain's and {other}'s render PNG bytes equal")
                continue
            worst = max((abs(round(x / 257) - round(y / 257)) for x, y in zip(a.values, b.values)),
                        default=0)
            figures.append(f"pq_plain's and {other}'s render PNG bytes differ; worst |Δ| {worst} "
                           "levels")
            if worst > 1:
                misses.append(f"{other}'s render differs from pq_plain's by {worst} levels")
    # Unscored (B96, #281): Apple's reading of each file's own labels and side
    # data — `hdr_pick_probe.swift`'s `plain` request (H1w's oracle), an
    # AVAssetImageGenerator frame with no composition — at the grey row, every
    # 64th column, and each one's worst |Δ| against pq_plain's.
    points = [[x + 0.5, GREY_ROW + 0.5] for x in range(0, W, 64)]
    apple = run_picks(sources, [{"tag": n, "plain": str(paths[n]), "tick": T, "clips": [],
                                 "points": points} for n in H7_FIXTURES])
    read = {}
    for n in H7_FIXTURES:
        row = apple.get(n) or {}
        got = row.get("picked")
        read[n] = [[code8(c) for c in one] if one else None for one in got] if got else None
        figures.append(f"Apple's reading of {n} (x = 0, 64, …, 960; unscored): "
                       f"{read[n] if read[n] is not None else row.get('error') or apple.get('error')}")
    for n in HDR10_FIXTURES:
        a, b = read.get("pq_plain"), read.get(n)
        if a is None or b is None or any(p is None or q is None for p, q in zip(a, b)):
            figures.append(f"Apple's reading, {n} against pq_plain: not read")
            continue
        worst = max(max(abs(x - y) for x, y in zip(p, q)) for p, q in zip(a, b))
        figures.append(f"Apple's reading, {n} against pq_plain: worst |Δ| {worst} levels")
    state["h7_side_data"] = found
    state["h7_apple"] = read
    check(name, not misses, f"{misses or 'all within'}\n       " + "\n       ".join(figures))


def run_srgb_rows(client, control, sources, state):
    """H1s and H1w: the sRGB arm, BT.709 primaries in a converting composition
    and P3 D65 primaries alone."""
    srgb, hlg, p3 = h1_media("srgb", control), fixture("hlg"), fixture("p3srgb")
    plan = [("alone", [srgb]), ("mixed", [srgb, hlg]), ("p3", [p3])]
    made = {}
    for name, paths in plan:
        if any(path is None for path in paths):
            made[name] = None
            continue
        package, clips, doc = saved_scene(client, f"srgb-{name}", paths)
        exported = doc.export(f"srgb-{name}") if package else None
        state[f"srgb_{name}_closed"] = doc.close()
        made[name] = (package, clips, exported) if package and exported else None
    asks = [{"tag": n, "package": str(m[0]), "tick": T, "clips": m[1],
             "points": PICK_POINTS[(W, H)]} for n, m in made.items() if m]
    oracle_ask = [{"tag": "oracle", "plain": str(p3), "tick": T, "clips": [],
                   "points": PICK_POINTS[(W, H)]}] if p3 else []
    tree = run_picks(sources, asks + oracle_ask) if asks else {"error": "no scene"}
    base = run_picks(None, asks) if asks else {"error": "no scene"}

    def picks(answer, tag):
        got = (answer.get(tag) or {}).get("picked")
        return [[code8(c) for c in one] if one else None for one in got] if got else None

    def near(a, b, tolerance):
        return a is not None and b is not None and all(
            x is not None and y is not None and close_to(x, y, tolerance) for x, y in zip(a, b))
    frames = {n: (yuv_frames(m[2], W, H, 16) if m else None) for n, m in made.items()}

    # H1s
    alone, mixed = picks(tree, "alone"), picks(tree, "mixed")
    base_mixed = picks(base, "mixed")
    rows_ok, worst, mid = True, 0, None
    if frames.get("alone") and frames.get("mixed"):
        for row in (GREY_ROW, CHROMA_ROW):
            for x in range(0, W, 8):
                a = export_rgb8(frames["alone"], 15, x, row)
                b = export_rgb8(frames["mixed"], 15, x, row)
                worst = max(worst, max(abs(p - q) for p, q in zip(a, b)))
        mid = (export_rgb8(frames["alone"], 15, 512, GREY_ROW),
               export_rgb8(frames["mixed"], 15, 512, GREY_ROW))
        rows_ok = worst <= 6 and close_to(*mid, 1)
    else:
        rows_ok = False
    control = base_mixed is not None and alone is not None and not near(
        base_mixed[:1], alone[:1], 2)
    check("H1s srgb|hlg against srgb alone: the tree's picks at 0.5 s ±2, the prores_422 export's "
          "frame 15 rows (every 8th column) ±6 and ±1 at x=512 on the grey row; the base tree's "
          "grey pick fails (CONTROL)",
          near(mixed, alone, 2) and rows_ok and control,
          f"picks mixed {mixed} / alone {alone}; base-tree mixed {base_mixed} (fails: {control}); "
          f"export rows worst |Δ| {worst}, x=512 alone/mixed {mid}; "
          f"{tree.get('error', '')} {base.get('error', '')}")

    # H1w
    oracle, mine, base_p3 = picks(tree, "oracle"), picks(tree, "p3"), picks(base, "p3")
    grey = None
    if frames.get("p3") and frames.get("alone"):
        grey = (export_rgb8(frames["p3"], 15, 512, GREY_ROW),
                export_rgb8(frames["alone"], 15, 512, GREY_ROW))
    control_w = base_p3 is not None and oracle is not None and not near(base_p3[:1], oracle[:1], 2)
    check("H1w p3srgb.mov alone (smpte432/iec61966-2-1/bt709): the tree's picks at 0.5 s = Apple's "
          "reading of the file's own labels ±2, the export's grey at x=512 = srgb alone's ±1; "
          "the base tree's grey pick fails (CONTROL)",
          near(mine, oracle, 2) and grey is not None and close_to(*grey, 1) and control_w,
          f"picks tree {mine} / oracle {oracle}; base-tree {base_p3} (fails: {control_w}); "
          f"export grey x=512 p3/alone {grey}; refused {REFUSED.get('p3srgb', 'none')}")


# ---- R0 -------------------------------------------------------------------------

def run_r0(state):
    """The labels of the newest existing recording, never its pixels; the
    rec_tags fixture, and where it is scored."""
    found = sorted(RECORDINGS.glob("Screen Recording *.mov")) if RECORDINGS.is_dir() else []
    if not found:
        check("R0 no recording on disk; GRD-16", True, f"{RECORDINGS} holds none")
        return None
    newest = found[-1]
    probe = stream(newest)
    primaries = probe.get("color_primaries", "unknown")
    transfer = probe.get("color_transfer", "unknown")
    matrix = probe.get("color_space", "unknown")
    chosen = arm(primaries, transfer)
    out = MEDIA / f"rec_tags-{primaries}-{transfer}-{matrix}.mov"
    made = hevc10("rec_tags", (primaries, transfer, matrix), out)
    check(f"R0 the newest recording's labels (read only): {newest.name}: primaries {primaries}, "
          f"transfer {transfer}, matrix {matrix}; the selector's arm: {chosen or 'nil (identity)'}",
          True, f"codec {probe.get('codec_name')} {probe.get('pix_fmt')}; rec_tags.mov "
          f"{'made: ' + tags(stream(made)) if made else 'REFUSED: ' + str(REFUSED.get('rec_tags'))}"
          f"; scored under {'H1' if chosen in (None, 'srgb(bt709)') else 'H5' if chosen.startswith('sdrWide') else 'none'}")
    state["r0"] = {"file": newest.name, "tags": [primaries, transfer, matrix], "arm": chosen}
    if made is None:
        state["r0_fixture"] = False
        return None
    return {"path": made, "arm": chosen, "primaries": primaries, "matrix": matrix}


# ---- TI -------------------------------------------------------------------------

def host_state():
    power = bounded.run(["pmset", "-g"], 30)["stdout"]
    mode = re.search(r"powermode\s+(\d+)", power)
    source = bounded.run(["pmset", "-g", "batt"], 30)["stdout"].splitlines()[:1]
    load = bounded.run(["sysctl", "-n", "vm.loadavg"], 30)["stdout"].strip()
    return f"powermode {mode.group(1) if mode else '?'}; {' '.join(source)}; loadavg {load}"


def run_ti(binary):
    figures, misses = [], []
    for name, want in (("hlg4k", 120), ("bt709_4k", 0)):
        path = fixture(name)
        if path is None:
            misses.append(f"{name} refused: {REFUSED.get(name)}")
            continue
        log = WORK / f"ti-{name}.log"
        before = host_state()
        wall = None
        launched = mcp.launch(str(binary), ["-FrameJobCompositorTiming", "YES"],
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                misses.append(f"{name}: the instance did not listen")
                continue
            doc = Doc(launched.client, f"ti-{name}", 3840, 2160)
            doc.place(path, 0)
            doc.place(path, 4 * SEC)
            start = log.stat().st_size if log.exists() else 0
            started = time.monotonic()
            out = doc.export(f"ti-{name}") if doc.ok else None
            wall = time.monotonic() - started
            time.sleep(1)
            with open(log, errors="replace") as handle:
                handle.seek(start)
                lines = TIMING.findall(handle.read())
            doc.close()
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
        found = [l for l in open(log, errors="replace") if "Frame Job: " in l]
        passes = [None if p == "" else int(p) for _, _, p in lines]
        averages = [float(a) for a, _, _ in lines]
        worst = [float(w) for _, w, _ in lines]
        figures.append(f"{name}: {len(lines)} lines, passes {passes}, average ms "
                       f"{averages}, worst {worst}; export wall s "
                       f"{'%.2f' % wall if wall is not None and out else None} (recorded, not "
                       f"scored); host before {before}; after {host_state()}")
        if out is None or len(lines) < 2 or any(p != want for p in passes) or found:
            misses.append(f"{name}: export {'ok' if out else 'missing'}, lines {len(lines)}, "
                          f"passes {passes}, complaints {found[:2]}")
        else:
            figures.append(f"{name} mean average {sum(averages) / len(averages):.3f} ms")
    check("TI the 4K HLG twin's timing lines report 120 input passes per 120 frames and the "
          "BT.709 twin's 0 (≥ 2 lines each); the averages printed", not misses,
          f"{misses or 'as wanted'}\n       " + "\n       ".join(figures))


# ---- P1–P4 ----------------------------------------------------------------------

def run_math_probe(sources):
    if not MATH_PROBE.exists():
        for name in sorted(P_ROWS & selected):
            check(f"{name} hdr_probe.swift exists", False, f"no {MATH_PROBE}")
        return
    binary, why = build_probe(MATH_PROBE, sources, "hdr_probe")
    if binary is None:
        for name in sorted(P_ROWS & selected):
            check(f"{name} the probe builds over app/Sources", False, why)
        return
    request, answer = WORK / "math.json", WORK / "math-answer.json"
    answer.unlink(missing_ok=True)
    shader = Path(sources).parent / "Resources/Shaders/Compositor.metal"
    request.write_text(json.dumps(math_request(shader)))
    ran = bounded.run([str(binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(P_ROWS & selected):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], row.get("detail", ""))


def half(value):
    """`value` rounded to IEEE half, as an `rgba16Float` texel stores it."""
    return struct.unpack("<e", struct.pack("<e", value))[0]


def math_request(shader):
    """The probe's inputs: the shader, the derived matrices, the selector's
    cases (names the probe maps to Core Video's and Core Media's constants),
    and the oracle's answers for P3: grey steps and 512 seeded triples per
    case, each input rounded to half first (the source texture's own values)."""
    cases = [  # (transfer, primaries, log, want, startsConversion)
        ("HLG", "2020", None, "hlg(bt2020)", True),
        ("HLG", "P3D65", None, "hlg(p3D65)", True),
        ("HLG", "709", None, "hlg(bt709)", True),
        ("HLG", None, None, "hlg(bt2020)", True),
        ("HLG", "DCIP3", None, "hlg(bt2020)", True),
        ("PQ", "2020", None, "pq(bt2020)", True),
        ("PQ", "P3D65", None, "pq(p3D65)", True),
        ("PQ", None, None, "pq(bt2020)", True),
        ("709", "2020", None, "sdrWide(bt2020)", True),
        ("2020", "2020", None, "sdrWide(bt2020)", True),
        ("709", "P3D65", None, "sdrWide(p3D65)", True),
        ("709", "DCIP3", None, "nil", None),
        ("709", "709", None, "nil", None),
        ("sRGB", "709", None, "srgb(bt709)", False),
        ("sRGB", None, None, "srgb(bt709)", False),
        ("sRGB", "P3D65", None, "srgb(p3D65)", True),
        ("sRGB", "2020", None, "srgb(bt2020)", True),
        ("sRGB", "DCIP3", None, "srgb(bt709)", False),
        (None, None, None, "nil", None),
        (None, "2020", None, "nil", None),
        (None, "2020", "AppleLog", "nil", None),
        ("HLG", "2020", "AppleLog", "nil", None),
        ("240M", "2020", None, "nil", None),
    ]
    steps = [i / 32 for i in range(33)] + [0.453, 0.4999, 0.5001, 1.1]
    seed = 0x5eed_0f15
    triples = []
    for _ in range(512):
        triple = []
        for _ in range(3):
            seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
            triple.append((seed >> 11) / 2 ** 53 * 1.1 - 0.02)
        triples.append(triple)
    p3 = []
    for kind, code, primaries in (("hlg", 1, "bt2020"), ("pq", 2, "bt2020"),
                                  ("sdr", 3, "bt2020"), ("sdr", 3, "p3d65"),
                                  ("hlg", 1, "p3d65"), ("pq", 2, "bt709"),
                                  ("srgb", 4, "bt709"), ("srgb", 4, "p3d65")):
        grey = steps + ([0.02, 0.04] if kind == "srgb" else [])
        inputs = [[half(c) for c in rgb] for rgb in [[g, g, g] for g in grey] + triples]
        p3.append({"kind": kind, "code": code, "primaries": primaries, "inputs": inputs,
                   "outputs": [convert(kind, primaries, rgb)[0] for rgb in inputs]})
    return {"shader": str(shader), "cases": cases,
            "matrices": {name: to709(name) for name in PRIMARIES},
            "p3": p3,
            "constants": {"hlgSystemGamma": HLG_GAMMA, "hlgGain": HLG_GAIN,
                          "shoulderKnee": KNEE, "hlgWhite": HLG_WHITE,
                          "pqReferenceWhite": PQ_REFERENCE, "pqWhite": PQ_WHITE,
                          "displayGamma": DISPLAY_GAMMA, "coreMedia709Gamma": CM709_GAMMA}}


# ---- the run --------------------------------------------------------------------

def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        return [f"{log} could not be read"]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's edits, built by its own make.
    (app bundle, copy) or (None, why)."""
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
    parser.add_argument("--measure", action="store_true", help="TI alone")
    parser.add_argument("--mutant", choices=sorted(MUTANTS) or None)
    parser.add_argument("--control", default=CONTROL)
    args = parser.parse_args()
    if args.mode and not args.folder:
        print(f"{args.mode} needs a folder")
        return 2
    control = (ROOT / (args.folder or args.control)).resolve()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    elif args.measure:
        selected = {"TI", "Z1"}
    else:
        selected.discard("TI")
        if args.mutant:
            selected -= {"H1a", "H7"}
    if args.mode == "capture":
        selected = {"H1", "H2", "H3", "H4", "H5", "H6", "R0", "Z1"}
        control.mkdir(parents=True, exist_ok=True)
    if args.mode is None and not args.mutant:
        selected -= {"H1"}
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][1] if args.mutant else []
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading-3 T3-1 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
    else:
        what = args.mode or ("measure" if args.measure else "run")
        print(f"grading-3 T3-1 — honest sources over MCP ({what}, {config} build {binary})",
              flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    state = {}
    closed = True
    log = WORK / "instance.log"
    needs_instance = bool(selected & {"H1", "H1m", "H1a", "H1s", "H1w", "H2", "H3", "H4", "H5",
                                      "H6", "H7", "R0"})
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
                recording = run_r0(state) if "R0" in selected or "H1" in selected \
                    or "H5" in selected else None
                extra_h1, extra_h5 = [], None
                if recording and recording["arm"] in (None, "srgb(bt709)"):
                    extra_h1 = [("rec_tags", W, H)]
                    MEDIA_REC["rec_tags"] = recording["path"]
                elif recording and recording["arm"].startswith("sdrWide"):
                    gamut = "p3d65" if "p3D65" in recording["arm"] else "bt2020"
                    extra_h5 = ("rec_tags", gamut, recording["matrix"]
                                if recording["matrix"] in KR_KB else "bt709")
                    MEDIA_REC["rec_tags"] = recording["path"]
                if "H1" in selected:
                    run_h1(client, args.mode, control, sources, state, extra_h1)
                if "H1m" in selected:
                    run_h1m(client, control, sources, state)
                if "H1a" in selected:
                    run_h1a(client, sources, state)
                if selected & {"H1s", "H1w"}:
                    run_srgb_rows(client, control, sources, state)
                if "H2" in selected:
                    run_h2(client, state)
                scenes = {}
                wanted = set()
                if selected & {"H3", "H4"}:
                    wanted |= {"hlg", "pq"}
                if "H5" in selected:
                    wanted |= {"b2020_709", "p3_709", "b2020_2020"} | (
                        {"rec_tags"} if extra_h5 else set())
                for name in sorted(wanted):
                    scenes[name] = fixture_scene(client, name)
                if "H3" in selected:
                    run_h3(client, scenes)
                if "H4" in selected:
                    run_h4(scenes)
                if "H5" in selected:
                    run_h5(client, scenes, extra_h5)
                if "H6" in selected:
                    run_h6(client, sources, state)
                if "H7" in selected:
                    run_h7(client, sources, state)
            except Exception as error:  # a row that could not run is a failure
                import traceback
                traceback.print_exc()
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
                closed = False
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    if "TI" in selected:
        run_ti(binary)
    if selected & P_ROWS:
        run_math_probe(sources)
    found = complaints(log) if needs_instance else []
    fixtures_ok = all(v for k, v in state.items() if k.endswith("fixture"))
    closed = closed and all(v for k, v in state.items() if k.endswith("closed"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Frame Job: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; state {{{', '.join(f'{k}: {v}' for k, v in state.items() if k != 'h1_record')}}}; "
          f"refused {REFUSED or 'none'}; complaints {found}")
    if needs_instance:
        print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    if args.mode == "capture":
        record = dict(state.get("h1_record") or {}, r0=state.get("r0"),
                      tree=str(ROOT), config=config)
        (control / "capture.json").write_text(json.dumps(record, indent=1))
        shown = [n for n in ("H2", "H3", "H4", "H5", "H6") if n in rows]
        failing = [n for n in shown if not rows[n]]
        print(f"captured into {args.folder}; on the control H2–H6 FAILED: {failing} "
              f"(passed, so not discriminating: {[n for n in shown if rows[n]]})")
        return 0 if rows.get("Z1") and state.get("capture_ok") else 1
    scored = [name for name in ROWS if name in rows and name not in RECORDS]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing or not fixtures_ok:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}, fixtures {state}")
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


MEDIA_REC = {}

if __name__ == "__main__":
    sys.exit(main())
