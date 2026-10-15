#!/usr/bin/env python3
"""Road map "grading-2", phase G2-4 (spec §11 GR-13) — the qualifier end to
end over MCP: `set_video {patch: {qualifier: {hue|saturation|luma: {…},
invert}}}` on an adjustment clip, the recipe's adjustment `qualifier`, the
adjustment pass's `q` (read from the destination before the grade, times
the opacity and the matte), `render_frame {selection}`, View ▸ Show
Selection and its tag, read back as `render_frame` bytes and two exports;
then the probe's rows over `app/Sources`. Grading-4 T4-4 (spec §11 GR-35)
adds the qualifier's cleanup blur, `video.qualifier.blur`: N0's two qualified
frames, project NC and rows Q1–Q6, probe rows K9 and K10, and eight mutants.

    python3 tools/proof/qualifier_proof.py [--app PATH] [--only H1,S1,...]
    python3 tools/proof/qualifier_proof.py capture DIR    # the unqualified control, before any product edit
    python3 tools/proof/qualifier_proof.py compare DIR    # every row, and N0 against DIR
    python3 tools/proof/qualifier_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/qualifier/home`,
and every package, fixture and PNG is under `tools/proof/work/qualifier/`,
removed at the start and at exit (the control folder DIR is not). The only
menu item performed is View ▸ Show Selection, which persists nothing
(GR-13); `DEFAULTS MOVED` from `mcp.py` stops the run. Every call is bounded
(`CALL_BOUND`), every ffmpeg too (120 s). Every project is closed
(`close_project`, discard).

Fixtures, written by this script: CARD, a 640×360 grey-128 PNG; RAMP, a
1920×360 PNG whose column x is grey round(255·x/1919); HUE, a 1440×360 PNG
whose column x is HSV hue 360·x/1440 and row y saturation 1 − y/359 at V 1;
HUE50, the same at V 0.5; DARK, 1440×360, column x the hue as HUE, saturation
1, row y V = y/359; NOISE, a 640×360 PNG each of whose pixels is (0, 255, 0) or
(255, 0, 0) by the top bit of a seeded 64-bit LCG (50 %); MOVIE, a 2 s 640×360 30 fps ffmpeg `testsrc2` H.264 file.
Every reading (hue, C, S, V, Y′) is the oracle's (`reading`, GR-13's
formulas) of the fixture's own bytes, which Z1 holds equal to the rendered
picture behind the adjustment clip. Frames are taken at t = 0.5 s unless a
row says otherwise; "the selection" is `render_frame {selection: <clip>}`.

Projects, each 30 fps: C (640×360, CARD and an adjustment clip at exposure
+1), Q (1440×360, HUE, an empty track for HUE50 or DARK, and an adjustment
clip at Color saturation −1 in front; B is Q's frame before the adjustment
clip, G0 its graded frame with no qualifier), R (1920×360, RAMP and an
adjustment clip), M (640×360, MOVIE, black), S (CARD and an adjustment clip,
saved twice for N2), P (HUE, two adjustment clips and a red rectangle in
front, saved for the probe), NC (640×360, NOISE and an adjustment clip at
Color saturation −1 with hue {120, 40, 0}: green selected, red not).
"oracle(σ)" is a separable Gaussian, in Python, of the blur-0 selection's
bytes, its edges clamped, σ quantised as `blurKernel` does (round(4σ)/4), the
kernel 4σ either side.
- **N0** (`compare DIR` only; scored on Release and under `--mutant`, printed
  elsewhere): eight frames — card, card-adjusted (C's adjustment clip),
  card-matted (the same under a rectangle on an alpha matte track over its left
  half), ramp, hue (G0), hue-qualified and hue-selection (H1's graded frame and
  its selection, a qualifier with no blur), movie — decoded at 16 bits a
  channel are byte-identical to `capture DIR`'s, taken on the untouched tree's
  Release build.
- **N1** (C): `{qualifier: {hue: null, saturation: null, luma: null}}` answers
  "made no change" and `get_project` holds no `qualifier`.
- **N2** (S): saved unqualified, `project.json` holds no `qualifier`; saved
  with hue {120, 40, 20} and `luma: {}`, the clip's `video.qualifier` is
  exactly those two ranges (luma the default {0, 1, 0.1}); both files'
  `version` is the header's `RC_FORMAT_VERSION`.
- **H1** (Q): hue {120, 40, 20}: the selection's top row is 255 ±1 where
  d ≤ 20°, 0 (±1) where d ≥ 40°, and monotone between (non-decreasing from
  80° to 100°, non-increasing from 140° to 160°, ±1); the graded frame's
  columns at d ≥ 40° are byte-identical to B, and at d ≤ 20° the rows with
  C ≥ 0.06 are G0's ±1.
- **W1** (Q): centres 0 and 350 (width 40, softness 20) select across the
  wrap: the top row 255 where d ≤ 20° and 0 where d ≥ 40°, d wrapping.
- **G1** (Q, R): hue {0, 360, 0}: the selection is 0 at every sampled pixel
  with C ≤ 0.02 and 255 at C ≥ 0.06 (every 8th row of every 16th column of
  HUE), and 0 everywhere on RAMP.
- **S1** (Q): saturation {0.4, 0.6, 0.1} by row: 255 on rows with S in
  0.42–0.58, 0 on rows with S ≤ 0.28 or ≥ 0.72, monotone between (±1).
- **S1b** (Q, HUE50 over HUE): the same range and the same claims (V 0.5; a
  chroma reading would select S 0.8–1 instead).
- **S2** (Q, DARK over HUE): saturation {0.4, 1, 0}: 0 on rows at V ≤ 0.03,
  255 at V ≥ 0.10, non-decreasing between (±1).
- **L1** (R): luma {0.25, 0.75, 0.1}: 255 on columns with Y′ in 0.25–0.75, 0
  at Y′ ≤ 0.15 or ≥ 0.85, monotone between (±1).
- **I1** (Q): H1's range inverted: the selection = 255 − H1's ±1 at every
  sample.
- **M1** (Q): a 480×360 white rectangle on an alpha matte track directly over
  the adjustment track covers the left third (hues 0–120, so H1's band 80–160
  straddles its edge): the selection = H1's ±1 left of x 476 and 0 right of
  x 484; the graded frame right of x 484 — the band's selected right half
  included — is B's bytes.
- **D1** (Q): H1's range with the grade Color hue +120 (saturation 0): at
  d ≤ 20° the rows with C ≥ 0.06 equal the unqualified hue-turned frame ±1,
  and at d ≥ 40° they are B.
- **E1** (Q): with the adjustment clip selected and View ▸ Show Selection
  on, an un-optioned `render_frame` = H1's graded bytes; the `prores_422`
  export's frame 15 is within ±8 of it at every 16th pixel and > 30 off the
  selection somewhere.
- **V1** (Q): the menu item's state and the "Selection" tag
  (`preview.selection`) are on only while Show Selection is; saved and
  reopened, it is off.
- **B1** (Q): the selection after the adjustment clip ends is black at every
  pixel; a red rectangle on a track in front leaves the selection H1's bytes.
- **F1** (C): `{selection: <the media clip>}` and `{selection: "x"}` are
  refused, naming `selection`.
- **A1** (Q): a 1 s action from hue centre 100 to 140 (width 40, softness
  20): at 0.5 s the selection's top row equals the static centre-120 one ±1.
- **A2** (Q): a 1 s linear action from centre 350 to 10 (width 20, softness
  0): at 0.5 s the top row is 255 at hue 0 and 0 at hue 180; at 0.3 s (frame
  9 at 30 fps) it equals the static centre-356 one ±1.
- **R1** (C): `hue.center` 400, saturation low 0.8 over high 0.2 and a hue on
  the media clip are refused in their three sentences, the project
  unchanged; centre 360, width 360, softness 180 and saturation 0…1 are
  accepted.
- **P0** (C): `paste_attributes` adjustment → media lands without a
  qualifier; media → adjustment keeps the target's own; adjustment →
  adjustment copies it.
- **U1** (Q): undo after H1's qualifier brings G0's bytes back, redo H1's.
- **V2** (Q): with H1's qualifier, `{ungraded}` is B's bytes and `{ungraded,
  selection}` is H1's selection's.
- **Q1** (NC): the selection's variance at blur 0, 0.05, 0.15 and 0.4 falls,
  each below half the one before.
- **Q2** (NC): blur 0.25's selection = oracle(6): max |Δ| ≤ 4 levels, mean
  |Δ| ≤ 1 (the bound written before measuring).
- **Q3** (NC): blur 0.25's graded frame = round(B + (G − B)·s/255) ±2 at every
  pixel (B the fixture, G the unqualified graded frame, s Q2's selection).
- **Q4** (NC): a 320×360 white rectangle on an alpha matte track over the left
  half: blur 0.25's selection is 0 at every x ≥ 321 and, at x ≤ 318, within
  Q2's bound of Q2's own oracle(6) — the matte cuts the coverage and leaves q
  unchanged, so never an oracle of Q4's matted selection.
- **Q5** (NC): a 1 s linear action from blur 0 to `{blur: 0.5}`: at 0.5 s
  within Q2's bound of oracle(6), at 1.5 s of oracle(12).
- **Q6** (NC): blur 1.5 and −0.1 refused in their sentence, `{blur: 0.3}` on the
  media clip refused naming it, the project unchanged; 0 and 1 accepted; saved
  with blur 0.25, `video.qualifier.blur` is 0.25 and `version` the header's.
- **K1–K10**: `qualifier_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of all ten), on project
  P; each row's sentence is the probe's.
- **Z1** (CONTROL): the fixtures hold (B, B50 and BD are the fixtures'
  bytes), the projects close and the log holds no `Frame Job: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it, the probe built
over the copy's `app/Sources`. A core mutant also runs `cargo test --release
--no-fail-fast --test qualifier --test selection --test qualifier_blur` in the
copy's own `core/` (row CT). A mutant whose names include N0
(`blur-zero-breaks-pass`) runs as `compare DIR --mutant NAME` under
`RC_PROOF_APP=release`, so N0 is held to the Release control. MUTANT PASS when every named row FAILED and no other scored row
did; the names are every row each mutant was measured to fail (MUTANTS).
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import colorsys
import json
import math
import re
import shutil
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/qualifier"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/qualifier_probe.swift"
HEADER = ROOT / "core/include/framejob_core.h"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
# A2's early sample: frame 9 at 30 fps (0.3 s), where the centre is 356. A
# time between frames (0.25 s is frame 7.5) renders the frame it snaps to.
A2_EARLY = 3 * SEC // 10
CARD_W, CARD_H = 640, 360
RAMP_W, RAMP_H = 1920, 360
HUE_W, HUE_H = 1440, 360
# M1's matte window: the left third of HUE (hues 0–120), across H1's band.
M1_EDGE = HUE_W // 3
GREY = 128
SHOW = ["View", "Show Selection"]
NEUTRAL = ["card", "card-adjusted", "card-matted", "ramp", "hue", "hue-qualified",
           "hue-selection", "movie"]
ROWS = ["N0", "N1", "N2", "H1", "W1", "G1", "S1", "S1b", "S2", "L1", "I1", "M1", "D1", "E1",
        "V1", "B1", "F1", "A1", "A2", "R1", "P0", "U1", "V2", "Q1", "Q2", "Q3", "Q4", "Q5",
        "Q6", "K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K10", "Z1"]
RECORDS = set()
C_ROWS = {"N1", "F1", "R1", "P0"}
Q_ROWS = {"H1", "W1", "G1", "S1", "S1b", "S2", "I1", "M1", "D1", "E1", "V1", "B1", "A1",
          "A2", "U1", "V2"}
R_ROWS = {"G1", "L1"}
K_ROWS = {"K1", "K2", "K3", "K4", "K5", "K6", "K7", "K8", "K9", "K10"}
NC_ROWS = {"Q1", "Q2", "Q3", "Q4", "Q5", "Q6"}
SHADER = "app/Resources/Shaders/Compositor.metal"
WEIGHT = "    float w = saturate(u.opacity * coverage * selected);\n"
SHOWN = "        return float4(float3(saturate(selected * coverage)), 1.0);\n    }\n"
SELECTION = "app/Sources/Compositor+Selection.swift"
MAP_READ = "    float4 dst = destination.read(uint2(in.position.xy));\n"
MAP_WEIGHT = "    return float4(qualifierWeight(c, q), 0.0, 0.0, 1.0);\n"
KERNEL = "        let blur = sigma >= MetalRenderer.minShadowSigma ? blurKernel(sigma: sigma) : nil\n"
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "hue-wrap-broken": ([(
        SHADER,
        "        float d = abs(hue - q.hueCenter);\n        d = min(d, 360.0 - d);\n",
        "        float d = abs(hue - q.hueCenter);\n")], ["W1", "G1"]),
    "softness-inside": ([(
        SHADER,
        "    return 1.0 - smoothstep(edge, edge + softness, x);\n",
        "    return 1.0 - smoothstep(edge - softness, edge, x);\n")],
        ["H1", "S1", "S1b", "L1", "W1", "D1"]),
    "chroma-guard-removed": ([(
        SHADER,
        "        w *= smoothstep(0.02, 0.06, chroma);\n",
        "")], ["G1"]),
    "saturation-reads-chroma": ([(
        SHADER,
        "        float s = mx > 0.0 ? saturate(chroma / mx) : 0.0;\n",
        "        float s = chroma;\n")], ["S1b", "S2"]),
    "near-black-guard-removed": ([(
        SHADER,
        "        s *= smoothstep(0.03, 0.10, mx);\n",
        "")], ["S2"]),
    "hue-long-way": ([(
        "core/src/actions.rs",
        "            align_hue_center(&mut state, &mut target);\n",
        "")], ["A2", "CT"]),
    "q-from-graded": ([
        (SHADER,
         WEIGHT,
         "    float w = saturate(u.opacity * coverage\n"
         "        * (q.enabled > 0.5 ? qualifierWeight(c, q) : 1.0));\n")], ["D1", "H1"]),
    "matte-not-multiplied": ([(
        SHADER,
        WEIGHT,
        "    float w = saturate(u.opacity * (q.enabled > 0.5 ? selected : coverage));\n")],
        ["M1"]),
    "selection-reaches-export": ([(
        "app/Sources/RecipeSource.swift",
        "let asked = options[key] ?? .none",
        "let asked = options[key]\n"
        "            ?? RecipeOptions(selection: options.values.compactMap(\\.selection).first)")],
        ["E1"]),
    "qualifier-on-any-clip": ([(
        "core/src/edit_adjustment.rs",
        "    if is_adjustment(clip) || props.qualifier.is_neutral() {\n",
        "    if true {\n")], ["R1", "CT"]),
    "paste-keeps-qualifier": ([(
        "core/src/edit_paste_attributes.rs",
        "                    into.qualifier = Qualifier::default();\n",
        "")], ["P0", "CT"]),
    "selection-drops-mattes": ([(
        "core/src/recipe_selection.rs",
        "        .filter(|(index, (_, fact))| *index < keep || fact.drawn_into)\n",
        "        .filter(|(index, _)| *index < keep)\n")], ["M1", "CT"]),
    "pick-not-behind": ([(
        "app/Sources/EditorViewController+Qualifier.swift",
        "        let options = RecipeOptions(behind: clip)\n",
        "        let options = RecipeOptions()\n")], ["K3"]),
    # grading-4 T4-4 (spec §11 GR-35), the qualifier's cleanup blur.
    "selection-shows-unblurred": ([(
        SHADER,
        "        selected = q.blurred > 0.5 ? selectionMap.read(uint2(in.position.xy)).r\n",
        "        selected = false ? selectionMap.read(uint2(in.position.xy)).r\n")],
        ["Q1", "Q2", "Q4", "Q5"]),
    "grade-reads-inline-q": ([(
        SHADER, SHOWN,
        SHOWN + "    if (q.enabled > 0.5) {\n        selected = qualifierWeight(c, q);\n    }\n")],
        ["Q3"]),
    "sigma-not-scaled": ([(
        "app/Sources/QualifierProps.swift",
        "        let sigma = Float(blur * Self.blurSigmaMax) / canvasPerDest\n",
        "        let sigma = Float(blur * Self.blurSigmaMax)\n")], ["K9"]),
    "blur-zero-breaks-pass": ([(
        "app/Sources/Compositor+Adjustment.swift",
        "            let sigma = layer.qualifier.selectionSigma(canvasPerDest: u.canvasPerDestX),\n",
        "            !layer.qualifier.isNeutral,\n"
        "            case let sigma = layer.qualifier.selectionSigma(\n"
        "                canvasPerDest: u.canvasPerDestX) ?? 0,\n")], ["N0"]),
    "coverage-blurred": ([
        (SHADER,
         "                                               texture2d<float> destination "
         "[[texture(0)]]) {\n",
         "                                               texture2d<float> destination "
         "[[texture(0)]],\n"
         "                                               texture2d<float> matte "
         "[[texture(1)]]) {\n"),
        (SHADER, MAP_WEIGHT,
         "    constexpr sampler edge(filter::linear, address::clamp_to_edge);\n"
         "    float2 uv = in.position.xy / float2(destination.get_width(), "
         "destination.get_height());\n"
         "    return float4(qualifierWeight(c, q) * matte.sample(edge, uv).r, 0.0, 0.0, 1.0);\n"),
        (SHADER, WEIGHT,
         "    float w = saturate(u.opacity * (q.blurred > 0.5 ? 1.0 : coverage) * selected);\n"),
        (SHADER, SHOWN,
         "        return float4(float3(saturate(selected * (q.blurred > 0.5 ? 1.0 : coverage))), "
         "1.0);\n    }\n"),
        (SELECTION, "    struct QualifierSurfaces {\n",
         "    nonisolated(unsafe) static var mutantCoverage: MTLTexture?\n"
         "    struct QualifierSurfaces {\n"),
        (SELECTION, "            encoder.setFragmentTexture(target, index: 0)\n",
         "            encoder.setFragmentTexture(target, index: 0)\n"
         "            encoder.setFragmentTexture(MetalRenderer.mutantCoverage, index: 1)\n"),
        ("app/Sources/Compositor+Adjustment.swift",
         "        var selectionTexture = placeholder\n",
         "        var selectionTexture = placeholder\n"
         "        MetalRenderer.mutantCoverage = matte\n")], ["Q4"]),
    "colour-blurred-not-q": ([
        (SHADER, MAP_READ,
         "    float4 dst = float4(0.0);\n"
         "    int2 last = int2(destination.get_width(), destination.get_height()) - 1;\n"
         "    for (int dy = -2; dy <= 2; ++dy) {\n"
         "        for (int dx = -2; dx <= 2; ++dx) {\n"
         "            int2 at = clamp(int2(in.position.xy) + int2(dx, dy), int2(0), last);\n"
         "            dst += destination.read(uint2(at));\n"
         "        }\n"
         "    }\n"
         "    dst /= 25.0;\n"),
        (SELECTION, KERNEL, "        let blur: MPSImageGaussianBlur? = nil\n")],
        # Q1 measured too: the average is the same at every blur, so the
        # variance stops falling (its first run, T4-4's record).
        ["Q1", "Q2", "Q4", "Q5"]),
    "blur-ignored-by-neutral": ([(
        "core/src/model_grade.rs",
        "            && !self.invert\n            && self.blur == 0.0\n",
        "            && !self.invert\n")], ["CT", "Q6"]),
    "blur-not-interpolated": ([(
        "core/src/actions.rs",
        "        if !video.qualifier.is_neutral() {\n"
        "            fields.insert(\"qualifier\".to_string(), qualifier_json(&video.qualifier));\n"
        "        }\n",
        "")], ["CT", "Q5"]),
}
rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
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


def format_version():
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


# ---- the oracle (GR-13's readings, of 8-bit bytes) --------------------------

def reading(rgb):
    """(hue in degrees, C, S, V, Y′) of an 8-bit RGB triple, as GR-13 reads
    the destination: HSV hue (0 when C is 0), C = max − min, S = C / max (0
    when max is 0), V = max, Rec. 709 Y′."""
    r, g, b = (c / 255 for c in rgb)
    mx, mn = max(r, g, b), min(r, g, b)
    chroma = mx - mn
    if chroma == 0:
        hue = 0.0
    elif mx == r:
        hue = 60 * (((g - b) / chroma) % 6)
    elif mx == g:
        hue = 60 * ((b - r) / chroma + 2)
    else:
        hue = 60 * ((r - g) / chroma + 4)
    hue %= 360
    s = chroma / mx if mx > 0 else 0.0
    return hue, chroma, s, mx, 0.2126 * r + 0.7152 * g + 0.0722 * b


def distance(hue, center):
    d = abs(hue - center) % 360
    return min(d, 360 - d)


# ---- pixels -------------------------------------------------------------------

def write_rgb_png(path, width, height, pixel):
    """An 8-bit RGB PNG, untagged, whose pixel (x, y) is `pixel(x, y)`."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            raw.extend(pixel(x, y))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b""))
    return path


def hsv8(hue, s, v):
    return tuple(round(255 * c) for c in colorsys.hsv_to_rgb(hue / 360, s, v))


def hue_pixel(v_of_row=None, s_of_row=None):
    """A pixel function for the hue fixtures: column x hue 360·x/1440."""
    cache = {}

    def pixel(x, y):
        key = (x, y)
        if key not in cache:
            s = s_of_row(y) if s_of_row else 1.0
            v = v_of_row(y) if v_of_row else 1.0
            cache[key] = hsv8(360 * x / HUE_W, s, v)
        return cache[key]
    return pixel


HUE_PIXEL = hue_pixel(s_of_row=lambda y: 1 - y / (HUE_H - 1))


def noise_pixel(seed=0x7E44_4B1A):
    """NOISE's pixel function: each pixel pure green or pure red, by the top
    bit of a 64-bit LCG seeded with `seed` (50 % each)."""
    bits = bytearray(CARD_W * CARD_H)
    state = seed
    for i in range(len(bits)):
        state = (state * 6364136223846793005 + 1442695040888963407) & 0xFFFF_FFFF_FFFF_FFFF
        bits[i] = state >> 63
    return lambda x, y: (0, 255, 0) if bits[y * CARD_W + x] else (255, 0, 0)


NOISE_PIXEL = noise_pixel()
HUE50_PIXEL = hue_pixel(v_of_row=lambda y: 0.5, s_of_row=lambda y: 1 - y / (HUE_H - 1))
DARK_PIXEL = hue_pixel(v_of_row=lambda y: y / (HUE_H - 1))


def decode(path, width, height, deep=False):
    """`path` (a PNG or a movie's first frame) as RGBA bytes through ffmpeg —
    `rgba64le` when `deep` — or None; bounded."""
    fmt, size = ("rgba64le", 8) if deep else ("rgba", 4)
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1",
                              "-f", "rawvideo", "-pix_fmt", fmt, "-"], capture_output=True,
                             timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw if len(raw) == width * height * size else None


class Frame:
    """One decoded frame: `raw` RGBA bytes, `width`, and the PNG's path."""

    def __init__(self, path, raw, width, height, text=""):
        self.path, self.raw, self.width, self.height, self.text = path, raw, width, height, text

    def px(self, x, y):
        at = (y * self.width + x) * 4
        return tuple(self.raw[at:at + 3])

    def grey(self, x, y):
        return self.px(x, y)[0]


def close_to(got, want, tolerance=1):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


def same_pixels(a, b):
    return a is not None and b is not None and a.raw == b.raw


def matches_fixture(frame, pixel, step=4):
    """Every `step`-th pixel of `frame` is the fixture's own bytes."""
    if frame is None:
        return False
    return all(frame.px(x, y) == pixel(x, y)
               for y in range(0, frame.height, step) for x in range(0, frame.width, step))


# ---- the documents ------------------------------------------------------------

class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path, width, height):
        self.client, self.path, self.width, self.height = client, path, width, height

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def tracks(self):
        return self.project().get("tracks") or []

    def new_track(self):
        before = {t.get("id") for t in self.tracks()}
        self.call("add_track")
        made = [t.get("id") for t in self.tracks() if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def added(self, tool, **arguments):
        """`tool` that places one clip; its id, or None."""
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def place(self, track, media):
        return self.added("add_clip", track=track, media=media, at=0)

    def media(self, path):
        return reply(self.call("import_media", path=str(path))).get("media")

    def clip(self, clip):
        return next((c for c in self.project().get("clips") or [] if c.get("id") == clip), {})

    def adjustment(self, track, duration=2 * SEC):
        return self.added("add_adjustment_clip", track=track, at=0, duration=duration)

    def rectangle(self, track, width, height, fill, x=0, y=0):
        clip = self.added("add_shape_clip", track=track, at=0, duration=2 * SEC,
                          shape={"kind": "rectangle", "width": width, "height": height,
                                 "stroke": None, "fill": fill})
        if clip is None or (x == 0 and y == 0):
            return clip
        return clip if self.call("set_video", clips=[clip], patch={"x": x, "y": y})["ok"] \
            else None

    def video(self, clips, **patch):
        return self.call("set_video", clips=clips, patch=patch)

    def qualify(self, clips, **ranges):
        return self.call("set_video", clips=clips, patch={"qualifier": ranges})

    def unqualify(self, clips):
        return self.qualify(clips, hue=None, saturation=None, luma=None, invert=False, blur=0)

    def menu(self, path):
        return self.call("perform_menu_item", path=path)

    def item_state(self, path):
        """The listing's `state` of the main-menu item at `path`, or None."""
        items = reply(self.call("perform_menu_item")).get("items") or []
        found = next((i for i in items if i.get("path") == path), None)
        return found.get("state") if found else None

    def preview(self, tag):
        """`snapshot_ui` of the editor's preview pane: its layout's views."""
        out = WORK / "snapshots" / f"{tag}.png"
        out.parent.mkdir(parents=True, exist_ok=True)
        got = reply(self.call("snapshot_ui", window="editor", view="preview", path=str(out),
                              fill_preview=False))
        try:
            return json.loads(Path(got.get("layout_path", "")).read_text()).get("views", [])
        except (OSError, ValueError):
            return []

    def frame(self, tag, t=T, **options):
        """`render_frame` at `t`, decoded; a Frame, or None."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out), **options)
        raw = decode(out, self.width, self.height) if got["ok"] and out.exists() else None
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        text = got["reply"] if isinstance(got["reply"], str) else json.dumps(got["reply"])
        return Frame(out, raw, self.width, self.height, text)


def opened(client, name, width, height, background=None):
    """A new project at `name`, its canvas sized; (Doc, fixture ok)."""
    path = WORK / f"{name}.framejob"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path, width, height)
    arguments = {"width": width, "height": height, "fps": [30, 1]}
    if background is not None:
        arguments["background"] = background
    doc.call("set_canvas", **arguments)
    c = doc.project().get("canvas") or {}
    return doc, made["ok"] and c.get("width") == width and c.get("height") == height


def close(client, path):
    return attempt(client, "close_project", {"project": str(path), "discard": True})["ok"]


def fixtures():
    card = write_rgb_png(WORK / "card.png", CARD_W, CARD_H, lambda x, y: (GREY,) * 3)
    ramp = write_rgb_png(WORK / "ramp.png", RAMP_W, RAMP_H,
                         lambda x, y: (round(255 * x / (RAMP_W - 1)),) * 3)
    hue = write_rgb_png(WORK / "hue.png", HUE_W, HUE_H, HUE_PIXEL)
    hue50 = write_rgb_png(WORK / "hue50.png", HUE_W, HUE_H, HUE50_PIXEL)
    dark = write_rgb_png(WORK / "dark.png", HUE_W, HUE_H, DARK_PIXEL)
    noise = write_rgb_png(WORK / "noise.png", CARD_W, CARD_H, NOISE_PIXEL)
    movie = WORK / "testsrc2.mp4"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={CARD_W}x{CARD_H}:rate=30:duration=2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)], 120)
    return {"card": card, "ramp": ramp, "hue": hue, "hue50": hue50, "dark": dark,
            "noise": noise, "movie": movie if made["rc"] == 0 and movie.exists() else None}


# ---- N0: the unqualified frames -----------------------------------------------

class Neutral:
    """Where the unqualified frames go: `capture` writes them to DIR, `compare`
    holds each against DIR's, a plain run only keeps them."""

    def __init__(self, mode, folder):
        self.mode, self.folder, self.misses, self.seen = mode, folder, [], []

    def take(self, doc, name, **options):
        frame = doc.frame(f"neutral-{name}", **options)
        self.seen.append(name)
        if frame is None:
            self.misses.append(f"{name}: no frame")
            return None
        if self.mode == "capture":
            (self.folder / f"{name}.png").write_bytes(frame.path.read_bytes())
        elif self.mode == "compare":
            want = decode(self.folder / f"{name}.png", doc.width, doc.height, deep=True)
            got = decode(frame.path, doc.width, doc.height, deep=True)
            if want is None or got is None:
                self.misses.append(f"{name}: {'no control' if want is None else 'no decode'}")
            elif want != got:
                differ = sum(1 for i in range(0, len(got), 2) if got[i:i + 2] != want[i:i + 2])
                self.misses.append(f"{name}: {differ} of {len(got) // 2} 16-bit samples differ")
        return frame


# ---- project C: the card -----------------------------------------------------

H1_HUE = {"center": 120, "width": 40, "softness": 20}


def run_c(client, media, neutral, state):
    doc, sized = opened(client, "C", CARD_W, CARD_H)
    back = (doc.tracks() or [{}])[0].get("id")
    card = doc.media(media["card"])
    clip = doc.place(back, card) if card is not None else None
    base = neutral.take(doc, "card")
    front = doc.new_track() if clip is not None else None
    adj = doc.adjustment(front) if front is not None else None
    exposed = doc.video([adj], color={"exposure": 1}) if adj else {"ok": False}
    adjusted = neutral.take(doc, "card-adjusted") if exposed["ok"] else None
    matte_track = doc.new_track() if adjusted is not None else None
    window = doc.rectangle(matte_track, CARD_W // 2, CARD_H, [1, 1, 1, 1], x=-CARD_W // 4) \
        if matte_track is not None else None
    matted = doc.call("set_track", track=matte_track, matte="alpha") if window \
        else {"ok": False}
    neutral.take(doc, "card-matted") if matted["ok"] else None
    removed = doc.call("remove_track", track=matte_track, with_clips=True) if matte_track \
        else {"ok": False}
    fixture = (sized and clip is not None and base is not None
               and base.px(CARD_W // 2, CARD_H // 2) == (GREY,) * 3 and adjusted is not None
               and matted["ok"] and removed["ok"])
    state["c_fixture"] = fixture
    print(f"  C: card clip {clip}, adjustment clip {adj}", flush=True)
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # N1
    nothing = doc.qualify([adj], hue=None, saturation=None, luma=None)
    stray = "qualifier" in (doc.clip(adj).get("video") or {})
    check("N1 an all-null qualifier answers \"made no change\" and get_project holds no "
          "qualifier", not nothing["ok"] and "made no change" in nothing.get("error", "")
          and not stray, f"answer {nothing.get('error') or nothing.get('reply')!r}; stored "
          f"{stray}")
    if nothing["ok"]:
        doc.call("undo")

    # R1
    before = doc.project()
    centre = doc.qualify([adj], hue={"center": 400})
    order = doc.qualify([adj], saturation={"low": 0.8, "high": 0.2})
    media_clip = doc.qualify([clip], hue={})
    unchanged = doc.project() == before
    for got in (centre, order, media_clip):
        if got["ok"]:
            doc.call("undo")
    edges = doc.qualify([adj], hue={"center": 360, "width": 360, "softness": 180},
                        saturation={"low": 0, "high": 1, "softness": 1})
    if edges["ok"]:
        doc.call("undo")
    wants = ["video.qualifier.hue.center must be between 0 and 360, not 400",
             "video.qualifier.saturation.low (0.8) must not be greater than "
             "video.qualifier.saturation.high (0.2)",
             f"clip {clip} is not an adjustment clip and cannot take a qualifier"]
    answers = [centre, order, media_clip]
    refused = all(not got["ok"] and want in got.get("error", "")
                  for got, want in zip(answers, wants))
    check("R1 centre 400, saturation low over high and a hue on a media clip are refused in "
          "their three sentences, the project unchanged; centre 360, width 360, softness 180 "
          "and saturation 0…1 are accepted", refused and unchanged and edges["ok"],
          "; ".join(repr(got.get("error") or "accepted") for got in answers)
          + f"; unchanged {unchanged}; edges {edges.get('error', 'accepted')}")

    # F1
    on_media = doc.call("render_frame", t=T, path=str(WORK / "f1-media.png"), selection=clip)
    on_text = doc.call("render_frame", t=T, path=str(WORK / "f1-text.png"), selection="x")
    check("F1 render_frame {selection: <media clip>} and {selection: \"x\"} are refused, "
          "naming selection",
          not on_media["ok"] and "selection" in on_media.get("error", "")
          and not on_text["ok"] and "selection" in on_text.get("error", ""),
          f"media {on_media.get('error') or 'ACCEPTED'!r}; text "
          f"{on_text.get('error') or 'ACCEPTED'!r}")

    # P0
    ranged = {"hue": {"center": 120.0, "width": 40.0, "softness": 20.0}}
    other = {"luma": {"low": 0.2, "high": 0.8, "softness": 0.05}}

    def payload(kind, video):
        clip_json = {"id": 1, "track": 0, "start": 0, "duration": SEC, "source": {"kind": kind},
                     "video": video}
        if kind == "shape":
            clip_json["shape"] = {"kind": "rectangle", "width": 10, "height": 10}
        return {"clips": [clip_json]}

    onto_media = doc.call("paste_attributes", clips=[clip],
                          payload=payload("adjustment", {"color": {"brightness": 0.1},
                                                         "qualifier": ranged}))
    media_video = doc.clip(clip).get("video") or {}
    landed = (onto_media["ok"] and "qualifier" not in media_video
              and (media_video.get("color") or {}).get("brightness") == 0.1)
    if onto_media["ok"]:
        doc.call("undo")
    own = doc.qualify([adj], **other)
    from_picture = doc.call("paste_attributes", clips=[adj],
                            payload=payload("shape", {"color": {"brightness": 0.2}}))
    adj_video = doc.clip(adj).get("video") or {}
    kept = (own["ok"] and from_picture["ok"] and adj_video.get("qualifier") == other
            and (adj_video.get("color") or {}).get("brightness") == 0.2)
    if from_picture["ok"]:
        doc.call("undo")
    between = doc.call("paste_attributes", clips=[adj],
                       payload=payload("adjustment", {"qualifier": ranged}))
    copied = between["ok"] and (doc.clip(adj).get("video") or {}).get("qualifier") == ranged
    if between["ok"]:
        doc.call("undo")
    if own["ok"]:
        doc.call("undo")
    check("P0 paste_attributes adjustment → media lands with no qualifier; media → adjustment "
          "keeps the target's own; adjustment → adjustment copies it",
          landed and kept and copied,
          f"onto media {onto_media.get('error', 'ok')} {media_video.get('qualifier')}; "
          f"from a picture {from_picture.get('error', 'ok')} {adj_video.get('qualifier')}; "
          f"between {between.get('error', 'ok')}")
    return close(client, doc.path)


# ---- project R: the ramp -----------------------------------------------------

def run_r(client, media, neutral, state):
    doc, sized = opened(client, "R", RAMP_W, RAMP_H)
    back = (doc.tracks() or [{}])[0].get("id")
    ramp = doc.media(media["ramp"])
    clip = doc.place(back, ramp) if ramp is not None else None
    base = neutral.take(doc, "ramp")
    fixture = sized and clip is not None and base is not None and \
        base.px(1, 1) == (0, 0, 0) and base.px(RAMP_W - 2, 1) == (255, 255, 255)
    state["r_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture
    front = doc.new_track()
    adj = doc.adjustment(front) if front is not None else None
    graded = doc.video([adj], color={"saturation": -1}) if adj else {"ok": False}
    state["r_fixture"] = graded["ok"]
    y = RAMP_H // 2

    # G1 (the ramp half)
    everything = doc.qualify([adj], hue={"center": 0, "width": 360, "softness": 0})
    g1 = doc.frame("g1-ramp", selection=adj)
    doc.unqualify([adj])
    lit = [x for x in range(0, RAMP_W, 8) if g1 is None or g1.grey(x, y) > 1]
    state["g1_ramp"] = (everything["ok"] and g1 is not None and not lit,
                        f"set {everything.get('error', 'ok')}; lit ramp columns {lit[:6]}")

    # L1
    luma = doc.qualify([adj], luma={"low": 0.25, "high": 0.75, "softness": 0.1})
    l1 = doc.frame("l1", selection=adj)
    doc.unqualify([adj])
    misses = []
    if l1 is not None:
        values = []
        for x in range(RAMP_W):
            ly = reading(base.px(x, y))[4]
            got = l1.grey(x, y)
            values.append((ly, got))
            if 0.25 <= ly <= 0.75 and got < 254:
                misses.append(f"x {x} Y′ {ly:.3f}: {got} (want 255)")
            if (ly <= 0.15 or ly >= 0.85) and got > 1:
                misses.append(f"x {x} Y′ {ly:.3f}: {got} (want 0)")
        rising = [v for v in values if 0.15 <= v[0] <= 0.25]
        falling = [v for v in values if 0.75 <= v[0] <= 0.85]
        misses += [f"rise at Y′ {b[0]:.3f}: {a[1]} → {b[1]}" for a, b in zip(rising, rising[1:])
                   if b[1] < a[1] - 1]
        misses += [f"fall at Y′ {b[0]:.3f}: {a[1]} → {b[1]}"
                   for a, b in zip(falling, falling[1:]) if b[1] > a[1] + 1]
    check("L1 luma {0.25, 0.75, 0.1} on RAMP: 255 on columns with Y′ in 0.25–0.75, 0 at Y′ ≤ "
          "0.15 or ≥ 0.85, monotone between", luma["ok"] and l1 is not None and not misses,
          f"set {luma.get('error', 'ok')}; {misses[:4] or 'all within'}")
    return close(client, doc.path)


# ---- project Q: the hue card -------------------------------------------------

def top_row_misses(frame, center, full, none, pixel=HUE_PIXEL, y=0):
    """The selection's row `y` against a hue band: 255 ±1 where d ≤ `full`,
    0 (±1) where d ≥ `none`."""
    if frame is None:
        return ["no frame"]
    misses = []
    for x in range(HUE_W):
        hue = reading(pixel(x, y))[0]
        d = distance(hue, center)
        got = frame.grey(x, y)
        if d <= full and got < 254:
            misses.append(f"x {x} hue {hue:.2f} d {d:.2f}: {got} (want 255)")
        elif d >= none and got > 1:
            misses.append(f"x {x} hue {hue:.2f} d {d:.2f}: {got} (want 0)")
    return misses


def by_rows(frame, pixel, columns, measure):
    """[(the row's reading, the selection's grey)] for every row of each
    column, `measure` picking the reading out of `reading`'s tuple."""
    out = []
    if frame is None:
        return out
    for x in columns:
        for y in range(HUE_H):
            out.append((x, y, measure(reading(pixel(x, y))), frame.grey(x, y)))
    return out


def level_misses(samples, inside, outside, softness_band):
    """Every sample in `inside` at 255 ±1, every one in `outside` at 0 ±1,
    and the samples in each soft band monotone toward the inside (±1)."""
    misses = []
    for x, y, value, got in samples:
        if inside(value) and got < 254:
            misses.append(f"({x},{y}) {value:.3f}: {got} (want 255)")
        if outside(value) and got > 1:
            misses.append(f"({x},{y}) {value:.3f}: {got} (want 0)")
    for low, high, rising in softness_band:
        band = sorted((value, got) for x, y, value, got in samples if low <= value <= high)
        for (a, ga), (b, gb) in zip(band, band[1:]):
            if b - a < 1e-9:
                continue
            if rising and gb < ga - 1:
                misses.append(f"not rising at {b:.3f}: {ga} → {gb}")
            if not rising and gb > ga + 1:
                misses.append(f"not falling at {b:.3f}: {ga} → {gb}")
    return misses


def run_q(client, media, neutral, state):
    doc, sized = opened(client, "Q", HUE_W, HUE_H)
    back = (doc.tracks() or [{}])[0].get("id")
    hue = doc.media(media["hue"])
    clip = doc.place(back, hue) if hue is not None else None
    over = doc.new_track() if clip is not None else None
    hue50 = doc.media(media["hue50"])
    dark = doc.media(media["dark"])
    b = doc.frame("b")
    # B50 and BD: each fixture alone over HUE, before the adjustment clip.
    b50_clip = doc.place(over, hue50) if over is not None and hue50 is not None else None
    b50 = doc.frame("b50") if b50_clip else None
    doc.call("delete", clips=[b50_clip]) if b50_clip else None
    bd_clip = doc.place(over, dark) if over is not None and dark is not None else None
    bd = doc.frame("bd") if bd_clip else None
    doc.call("delete", clips=[bd_clip]) if bd_clip else None
    front = doc.new_track() if over is not None else None
    adj = doc.adjustment(front) if front is not None else None
    graded = doc.video([adj], color={"saturation": -1}) if adj else {"ok": False}
    g0 = neutral.take(doc, "hue") if graded["ok"] else None
    # N0's two qualified frames (T4-4: a qualifier with no blur draws as it
    # did): H1's graded frame and its selection, then undone, so the rows
    # below start unqualified on any tree.
    n0_set = doc.qualify([adj], hue=H1_HUE) if g0 is not None else {"ok": False}
    if n0_set["ok"]:
        neutral.take(doc, "hue-qualified")
        neutral.take(doc, "hue-selection", selection=adj)
        doc.call("undo")
    hue_clip = doc.clip(clip)
    covers = (hue_clip.get("start", 1) == 0
              and hue_clip.get("duration", 0) >= 2 * SEC + SEC // 2)
    fixture = (sized and clip is not None and covers and matches_fixture(b, HUE_PIXEL)
               and matches_fixture(b50, HUE50_PIXEL) and matches_fixture(bd, DARK_PIXEL)
               and g0 is not None and not same_pixels(g0, b))
    state["q_fixture"] = fixture
    print(f"  Q: hue clip {clip} (covers 2.5 s {covers}), adjustment clip {adj}; B, B50 and BD "
          f"the fixtures {matches_fixture(b, HUE_PIXEL)}, {matches_fixture(b50, HUE50_PIXEL)}, "
          f"{matches_fixture(bd, DARK_PIXEL)}", flush=True)
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture
    ids = [adj]

    # H1
    h1_set = doc.qualify(ids, hue=H1_HUE)
    h1_sel = doc.frame("h1-selection", selection=adj)
    h1 = doc.frame("h1")
    misses = top_row_misses(h1_sel, 120, 20, 40)
    if h1_sel is not None:
        row = [h1_sel.grey(x, 0) for x in range(HUE_W)]
        hues = [reading(HUE_PIXEL(x, 0))[0] for x in range(HUE_W)]
        for x in range(1, HUE_W):
            if 80 <= hues[x] <= 100 and row[x] < row[x - 1] - 1:
                misses.append(f"not rising at hue {hues[x]:.2f}")
            if 140 <= hues[x] <= 160 and row[x] > row[x - 1] + 1:
                misses.append(f"not falling at hue {hues[x]:.2f}")
    graded_misses = []
    if h1 is not None:
        for x in range(HUE_W):
            d = distance(reading(HUE_PIXEL(x, 0))[0], 120)
            if d >= 40:
                if any(h1.px(x, y) != b.px(x, y) for y in range(0, HUE_H, 3)):
                    graded_misses.append(f"x {x} (d {d:.1f}) not B")
            elif d <= 20:
                for y in range(0, HUE_H, 3):
                    if reading(HUE_PIXEL(x, y))[1] >= 0.06 \
                            and not close_to(h1.px(x, y), g0.px(x, y)):
                        graded_misses.append(f"({x},{y}) {h1.px(x, y)} vs G0 {g0.px(x, y)}")
                        break
    check("H1 hue {120, 40, 20}: the selection's top row 255 where d ≤ 20°, 0 where d ≥ 40°, "
          "monotone between; the graded frame B at d ≥ 40° and G0 ±1 at d ≤ 20° (C ≥ 0.06)",
          h1_set["ok"] and not misses and h1 is not None and not graded_misses,
          f"set {h1_set.get('error', 'ok')}; selection {misses[:3] or 'all within'}; graded "
          f"{graded_misses[:3] or 'all within'}")

    # U1
    undone = doc.call("undo")
    u_plain = doc.frame("u1-undone")
    redone = doc.call("redo")
    u_again = doc.frame("u1-redone")
    check("U1 undo after H1's qualifier brings G0's bytes back, redo H1's",
          h1_set["ok"] and undone["ok"] and redone["ok"] and same_pixels(u_plain, g0)
          and same_pixels(u_again, h1) and not same_pixels(h1, g0),
          f"undo {undone.get('error', 'ok')}; redo {redone.get('error', 'ok')}; unqualified "
          f"{same_pixels(u_plain, g0)}; qualified {same_pixels(u_again, h1)}")

    # V2
    v2 = doc.frame("v2-ungraded", ungraded=True)
    v2_sel = doc.frame("v2-ungraded-selection", ungraded=True, selection=adj)
    check("V2 with H1's qualifier, {ungraded} is B's bytes and {ungraded, selection} H1's "
          "selection's", same_pixels(v2, b) and same_pixels(v2_sel, h1_sel),
          f"ungraded = B {same_pixels(v2, b)}; selection = H1's {same_pixels(v2_sel, h1_sel)}")

    # I1
    inverted = doc.qualify(ids, invert=True)
    i1 = doc.frame("i1", selection=adj)
    doc.qualify(ids, invert=False)
    i_misses = []
    if i1 is not None and h1_sel is not None:
        i_misses = [f"({x},{y}) {i1.grey(x, y)} vs 255 − {h1_sel.grey(x, y)}"
                    for y in range(0, HUE_H, 8) for x in range(0, HUE_W, 4)
                    if abs(i1.grey(x, y) - (255 - h1_sel.grey(x, y))) > 1]
    check("I1 H1's range inverted: the selection = 255 − H1's ±1",
          inverted["ok"] and i1 is not None and h1_sel is not None and not i_misses,
          f"set {inverted.get('error', 'ok')}; {i_misses[:3] or 'all within'}")

    # M1 — the window covers the left third (hues 0–120), so H1's band (80–160)
    # straddles its edge and the band's right half lies outside it.
    matte_track = doc.new_track()
    window = doc.rectangle(matte_track, M1_EDGE, HUE_H, [1, 1, 1, 1],
                           x=M1_EDGE // 2 - HUE_W // 2) if matte_track is not None else None
    matted = doc.call("set_track", track=matte_track, matte="alpha") if window \
        else {"ok": False}
    m1_sel = doc.frame("m1-selection", selection=adj)
    m1 = doc.frame("m1")
    doc.call("remove_track", track=matte_track, with_clips=True) if matte_track else None
    m_misses = []
    if m1_sel is not None and h1_sel is not None and m1 is not None:
        for y in range(0, HUE_H, 6):
            for x in range(0, HUE_W, 2):
                if x < M1_EDGE - 4 and abs(m1_sel.grey(x, y) - h1_sel.grey(x, y)) > 1:
                    m_misses.append(f"inside ({x},{y}) {m1_sel.grey(x, y)} vs H1 "
                                    f"{h1_sel.grey(x, y)}")
                if x > M1_EDGE + 4 and m1_sel.grey(x, y) > 1:
                    m_misses.append(f"outside ({x},{y}) {m1_sel.grey(x, y)} (want 0)")
                if x > M1_EDGE + 4 and m1.px(x, y) != b.px(x, y):
                    m_misses.append(f"graded outside ({x},{y}) {m1.px(x, y)} vs B {b.px(x, y)}")
    check("M1 an alpha matte over the left third, across H1's band: the selection H1's inside "
          "it and 0 outside; the graded frame outside it B's bytes (the band's selected right "
          "half untouched)",
          window is not None and matted["ok"] and m1_sel is not None and not m_misses,
          f"matte {matted.get('error', 'ok')}; {m_misses[:3] or 'all within'}")

    # D1
    turned = doc.video(ids, color={"saturation": 0, "hue": 120})
    doc.unqualify(ids)
    unqualified = doc.frame("d1-unqualified")
    doc.qualify(ids, hue=H1_HUE)
    d1 = doc.frame("d1")
    d_misses = []
    if d1 is not None and unqualified is not None:
        for x in range(HUE_W):
            d = distance(reading(HUE_PIXEL(x, 0))[0], 120)
            for y in range(0, HUE_H, 6):
                if reading(HUE_PIXEL(x, y))[1] < 0.06:
                    continue
                if d <= 20 and not close_to(d1.px(x, y), unqualified.px(x, y)):
                    d_misses.append(f"({x},{y}) d {d:.1f}: {d1.px(x, y)} vs turned "
                                    f"{unqualified.px(x, y)}")
                elif d >= 40 and d1.px(x, y) != b.px(x, y):
                    d_misses.append(f"({x},{y}) d {d:.1f}: {d1.px(x, y)} vs B {b.px(x, y)}")
    doc.video(ids, color={"saturation": -1, "hue": 0})
    check("D1 H1's range with the grade's hue +120: at d ≤ 20° the unqualified turned frame "
          "±1, at d ≥ 40° B (the selection read before the grade)",
          turned["ok"] and d1 is not None and unqualified is not None and not d_misses,
          f"set {turned.get('error', 'ok')}; {d_misses[:3] or 'all within'}")

    # B1
    gone = doc.frame("b1-after", t=2 * SEC + SEC // 2, selection=adj)
    black = gone is not None and all(gone.px(x, y) == (0, 0, 0)
                                     for y in range(0, HUE_H, 2) for x in range(0, HUE_W, 2))
    shape_track = doc.new_track()
    shape = doc.rectangle(shape_track, 200, 200, [1, 0, 0, 1]) if shape_track else None
    covered = doc.frame("b1-covered", selection=adj)
    plain = doc.frame("b1-plain")
    shown = plain is not None and plain.px(HUE_W // 2, HUE_H // 2) == (255, 0, 0)
    doc.call("remove_track", track=shape_track, with_clips=True) if shape_track else None
    check("B1 the selection after the adjustment clip ends is black; a red rectangle in front "
          "(drawn on the plain frame) is absent from the selection",
          black and shape is not None and shown and same_pixels(covered, h1_sel),
          f"black {black}; rectangle {shape}, drawn {shown}; selection H1's "
          f"{same_pixels(covered, h1_sel)}")

    # W1
    w_misses = []
    w_ok = True
    for center in (0, 350):
        got = doc.qualify(ids, hue={"center": center, "width": 40, "softness": 20})
        w_ok = w_ok and got["ok"]
        w1 = doc.frame(f"w1-{center}", selection=adj)
        w_misses += [f"centre {center}: {m}" for m in top_row_misses(w1, center, 20, 40)]
    doc.qualify(ids, hue=H1_HUE)
    check("W1 centres 0 and 350 select across the wrap: 255 where d ≤ 20°, 0 where d ≥ 40°",
          w_ok and not w_misses, "; ".join(w_misses[:4]) or "all within")

    # G1 (the hue half)
    everything = doc.qualify(ids, hue={"center": 0, "width": 360, "softness": 0})
    g1 = doc.frame("g1-hue", selection=adj)
    g_misses = []
    if g1 is not None:
        for x in range(0, HUE_W, 16):
            for y in range(0, HUE_H, 8):
                c = reading(HUE_PIXEL(x, y))[1]
                if c <= 0.02 and g1.grey(x, y) > 1:
                    g_misses.append(f"({x},{y}) C {c:.3f}: {g1.grey(x, y)} (want 0)")
                if c >= 0.06 and g1.grey(x, y) < 254:
                    g_misses.append(f"({x},{y}) C {c:.3f}: {g1.grey(x, y)} (want 255)")
    ramp_ok, ramp_detail = state.get("g1_ramp", (False, "R not run"))
    check("G1 hue {0, 360, 0}: 0 where C ≤ 0.02 and 255 where C ≥ 0.06 on HUE; 0 everywhere "
          "on RAMP", everything["ok"] and g1 is not None and not g_misses and ramp_ok,
          f"set {everything.get('error', 'ok')}; {g_misses[:3] or 'all within'}; RAMP "
          f"{ramp_detail}")
    doc.unqualify(ids)

    # S1, S1b, S2
    columns = [0, 240, 480, 720, 960, 1200]
    in_band = [(0.28, 0.42, True), (0.58, 0.72, False)]
    sat = doc.qualify(ids, saturation={"low": 0.4, "high": 0.6, "softness": 0.1})
    s1 = doc.frame("s1", selection=adj)
    s1_misses = level_misses(by_rows(s1, HUE_PIXEL, columns, lambda r: r[2]),
                             lambda s: 0.42 <= s <= 0.58, lambda s: s <= 0.28 or s >= 0.72,
                             in_band) if s1 else ["no frame"]
    check("S1 saturation {0.4, 0.6, 0.1} by row on HUE: 255 at S 0.42–0.58, 0 at S ≤ 0.28 or "
          "≥ 0.72, monotone between", sat["ok"] and not s1_misses,
          f"set {sat.get('error', 'ok')}; {s1_misses[:4] or 'all within'}")
    half = doc.place(over, hue50)
    s1b = doc.frame("s1b", selection=adj) if half else None
    s1b_misses = level_misses(by_rows(s1b, HUE50_PIXEL, columns, lambda r: r[2]),
                              lambda s: 0.42 <= s <= 0.58, lambda s: s <= 0.28 or s >= 0.72,
                              in_band) if s1b else ["no frame"]
    check("S1b the same range on HUE50 (V 0.5): 255 at S 0.42–0.58, 0 at S ≤ 0.28 or ≥ 0.72, "
          "monotone between (S = C / max, not chroma)", sat["ok"] and not s1b_misses,
          "; ".join(s1b_misses[:4]) or "all within")
    doc.call("delete", clips=[half]) if half else None
    deep = doc.place(over, dark)
    near = doc.qualify(ids, saturation={"low": 0.4, "high": 1, "softness": 0})
    s2 = doc.frame("s2", selection=adj) if deep else None
    s2_misses = level_misses(by_rows(s2, DARK_PIXEL, columns, lambda r: r[3]),
                             lambda v: v >= 0.10, lambda v: v <= 0.03,
                             [(0.03, 0.10, True)]) if s2 else ["no frame"]
    check("S2 saturation {0.4, 1, 0} on DARK: 0 on rows at V ≤ 0.03, 255 at V ≥ 0.10, "
          "non-decreasing between (the near-black guard)", near["ok"] and not s2_misses,
          f"set {near.get('error', 'ok')}; {s2_misses[:4] or 'all within'}")
    doc.call("delete", clips=[deep]) if deep else None
    doc.unqualify(ids)

    # A1, A2
    def static_row(tag, hue_range):
        doc.qualify(ids, hue=hue_range)
        frame = doc.frame(tag, selection=adj)
        doc.unqualify(ids)
        return frame

    def acted(start, end_center, t_values, tag):
        doc.qualify(ids, hue=start)
        added = doc.call("add_action", clip=adj, at=0, duration=SEC)
        actions = doc.clip(adj).get("actions") or []
        action = actions[0].get("id") if len(actions) == 1 else None
        ended = doc.call("set_action_end", clip=adj, action=action,
                         patch={"video": {"qualifier": {"hue": {"center": end_center}}}}) \
            if action else {"ok": False}
        frames = {t: doc.frame(f"{tag}-{t}", t=t, selection=adj) for t in t_values}
        if action:
            doc.call("remove_action", clip=adj, action=action)
        doc.unqualify(ids)
        return added["ok"] and ended["ok"], frames

    def row_misses(got, want):
        if got is None or want is None:
            return ["a frame is missing"]
        return [f"x {x}: {got.grey(x, 0)} vs {want.grey(x, 0)}" for x in range(HUE_W)
                if abs(got.grey(x, 0) - want.grey(x, 0)) > 1]

    want120 = static_row("a1-static", {"center": 120, "width": 40, "softness": 20})
    made, frames = acted({"center": 100, "width": 40, "softness": 20}, 140, [T], "a1")
    a1_misses = row_misses(frames.get(T), want120)
    check("A1 a 1 s action from hue centre 100 to 140: at 0.5 s the selection's top row is the "
          "static centre-120 one ±1", made and not a1_misses,
          "; ".join(a1_misses[:3]) or "all within")
    want356 = static_row("a2-static", {"center": 356, "width": 20, "softness": 0})
    made, frames = acted({"center": 350, "width": 20, "softness": 0}, 10, [T, A2_EARLY], "a2")
    mid = frames.get(T)
    zero_col = 0
    opposite = HUE_W // 2
    a2_mid = mid is not None and mid.grey(zero_col, 0) >= 254 and mid.grey(opposite, 0) <= 1
    a2_misses = row_misses(frames.get(A2_EARLY), want356)
    check("A2 a 1 s linear action from centre 350 to 10: at 0.5 s 255 at hue 0 and 0 at hue "
          "180 (the short way round); at 0.3 s (frame 9) the static centre-356 row ±1",
          made and a2_mid and not a2_misses,
          f"at 0.5 s hue 0 {mid.grey(zero_col, 0) if mid else None}, hue 180 "
          f"{mid.grey(opposite, 0) if mid else None}; at 0.3 s {a2_misses[:3] or 'within'}")

    # E1, V1 — Show Selection in this window
    doc.qualify(ids, hue=H1_HUE)
    doc.call("set_selection", clips=[adj])
    off_state = doc.item_state(SHOW)
    switched = doc.menu(SHOW)
    on_state = doc.item_state(SHOW)
    on_views = doc.preview("v1-on")
    plain = doc.frame("e1-plain")
    out = WORK / "E1.mov"
    exported = doc.call("export", preset="prores_422", path=str(out), size="document")
    raw, which = decoded(out, 15) if exported["ok"] and out.exists() else (None, "no file")
    samples = [(x, y) for y in range(0, HUE_H, 16) for x in range(0, HUE_W, 16)]
    e_misses, apart = [], 0
    if raw is not None and h1 is not None and h1_sel is not None:
        export = Frame(out, raw, HUE_W, HUE_H)
        e_misses = [(x, y, export.px(x, y), h1.px(x, y)) for x, y in samples
                    if not close_to(export.px(x, y), h1.px(x, y), 8)]
        apart = max(max(abs(p - q) for p, q in zip(export.px(x, y), h1_sel.px(x, y)))
                    for x, y in samples)
    check(f"E1 with Show Selection on, an un-optioned render_frame is H1's graded bytes and "
          f"the prores_422 export's frame {which} is within ±8 of it and > 30 off the "
          f"selection somewhere", switched["ok"] and same_pixels(plain, h1) and raw is not None
          and not e_misses and apart > 30,
          f"menu {switched.get('error', 'ok')}; plain = H1 {same_pixels(plain, h1)}; export "
          f"{exported.get('error', 'ok')}; {e_misses[:3] or 'all within'}; from the selection "
          f"{apart}")
    tag = view(on_views, "preview.selection") or {}
    tag_on = not tag.get("hidden", True) and tag.get("text") == "Selection"
    doc.menu(SHOW)
    after_state = doc.item_state(SHOW)
    off_views = doc.preview("v1-off")
    tag_off = shown_off(off_views)
    doc.menu(SHOW)
    reopen_path = WORK / "Q-saved.framejob"
    saved = doc.call("save_project", path=str(reopen_path))
    doc.path = reopen_path
    closed = close(client, doc.path)
    again = attempt(client, "open_project", {"path": str(reopen_path)})
    reopened = Doc(client, reopen_path, HUE_W, HUE_H)
    reopened_state = reopened.item_state(SHOW)
    reopened_views = reopened.preview("v1-reopened")
    check("V1 the menu state and the \"Selection\" tag are on only while Show Selection is; "
          "saved, closed and reopened it is off",
          switched["ok"] and off_state == "off" and on_state == "on" and tag_on
          and after_state == "off" and tag_off and saved["ok"] and again["ok"]
          and reopened_state == "off" and shown_off(reopened_views),
          f"states off {off_state}, on {on_state}, after {after_state}, reopened "
          f"{reopened_state}; tag {tag}; off {tag_off}; save {saved.get('error', 'ok')}; open "
          f"{again.get('error', 'ok')}")
    return close(client, reopen_path) and closed


def view(views, identifier=None, cls=None):
    return next((v for v in views if (identifier is None or v.get("id") == identifier)
                 and (cls is None or v.get("class") == cls)), None)


def shown_off(views):
    """The tag is hidden or out of the hierarchy, in a dump that has views."""
    tag = view(views, "preview.selection")
    return bool(views) and (tag is None or tag.get("hidden") is True)


def decoded(movie, n):
    """Frame `n` of `movie` as RGBA bytes at the hue size; (None, why)."""
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{n})",
             "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo", "-pix_fmt",
             "rgba", "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"ffmpeg: {error}"
    return (raw, n) if len(raw) == HUE_W * HUE_H * 4 else (None, "no frame decoded")


# ---- project NC: the noisy card and the cleanup blur (T4-4) -------------------

NC_HUE = {"center": 120, "width": 40, "softness": 0}
# Q2's bound, written before measuring: the selection against the oracle.
Q2_MAX, Q2_MEAN = 4, 1.0


def gaussian(values, width, height, sigma):
    """`values` (row-major) blurred by a separable Gaussian of `sigma`
    quantised as `blurKernel` quantises it (round(4σ)/4), its edges clamped
    (MPS's `.clamp`), the kernel 4σ either side, normalised: the oracle."""
    sigma = round(4 * sigma) / 4
    radius = max(1, math.ceil(4 * sigma))
    kernel = [math.exp(-(i * i) / (2 * sigma * sigma)) for i in range(-radius, radius + 1)]
    total = sum(kernel)
    kernel = [k / total for k in kernel]

    def line(seq):
        n = len(seq)
        padded = [seq[0]] * radius + list(seq) + [seq[-1]] * radius
        out = [0.0] * n
        for i, k in enumerate(kernel):
            out = [o + k * v for o, v in zip(out, padded[i:i + n])]
        return out
    rows = [line(values[y * width:(y + 1) * width]) for y in range(height)]
    columns = [line([rows[y][x] for y in range(height)]) for x in range(width)]
    return [columns[x][y] for y in range(height) for x in range(width)]


def greys(frame):
    return [frame.raw[i] for i in range(0, len(frame.raw), 4)] if frame else []


def variance(values):
    mean = sum(values) / len(values)
    return sum((v - mean) ** 2 for v in values) / len(values)


def against(frame, oracle, columns=None):
    """(max |Δ|, mean |Δ|) of `frame`'s greys against `oracle`, over the
    columns `columns` keeps (all when None)."""
    got = greys(frame)
    if not got or not oracle:
        return math.inf, math.inf
    deltas = [abs(got[i] - oracle[i]) for i in range(len(got))
              if columns is None or columns(i % CARD_W)]
    return max(deltas), sum(deltas) / len(deltas)


def run_nc(client, media, state):
    """Q1–Q6 on NC: NOISE, an adjustment clip at Color saturation −1 with hue
    {120, 40, 0} (green selected, red not)."""
    doc, sized = opened(client, "NC", CARD_W, CARD_H)
    back = (doc.tracks() or [{}])[0].get("id")
    noise = doc.media(media["noise"])
    clip = doc.place(back, noise) if noise is not None else None
    b = doc.frame("nc-b")
    front = doc.new_track() if clip is not None else None
    adj = doc.adjustment(front) if front is not None else None
    graded = doc.video([adj], color={"saturation": -1}) if adj else {"ok": False}
    g = doc.frame("nc-g") if graded["ok"] else None
    ranged = doc.qualify([adj], hue=NC_HUE) if graded["ok"] else {"ok": False}
    sel0 = doc.frame("nc-sel0", selection=adj) if ranged["ok"] else None
    binary = sel0 is not None and set(greys(sel0)) <= {0, 255}
    fixture = (sized and clip is not None and matches_fixture(b, NOISE_PIXEL, step=1)
               and g is not None and binary)
    state["nc_fixture"] = fixture
    print(f"  NC: noise clip {clip}, adjustment clip {adj}; B the fixture "
          f"{matches_fixture(b, NOISE_PIXEL, step=1)}, the blur-0 selection binary {binary}",
          flush=True)
    if not fixture:
        return close(client, doc.path) and False
    ids = [adj]
    base = [float(v) for v in greys(sel0)]
    oracle6 = gaussian(base, CARD_W, CARD_H, 6)

    # Q1
    variances = [(0, variance(greys(sel0)))]
    set_ok = True
    for blur in (0.05, 0.15, 0.4):
        set_ok = doc.qualify(ids, blur=blur)["ok"] and set_ok
        frame = doc.frame(f"q1-{blur}", selection=adj)
        variances.append((blur, variance(greys(frame)) if frame else math.inf))
    falling = all(b2[1] < b1[1] / 2 for b1, b2 in zip(variances, variances[1:]))
    check("Q1 the selection's variance at blur 0, 0.05, 0.15 and 0.4 falls, each below half "
          "the one before", set_ok and falling,
          "; ".join(f"blur {blur}: {v:.2f}" for blur, v in variances))

    # Q2, Q3
    quarter = doc.qualify(ids, blur=0.25)
    sel25 = doc.frame("q2-selection", selection=adj)
    graded25 = doc.frame("q3-graded")
    worst, mean = against(sel25, oracle6)
    check(f"Q2 blur 0.25's selection = the oracle's Gaussian (σ 6) of the blur-0 selection: max "
          f"|Δ| ≤ {Q2_MAX} levels, mean ≤ {Q2_MEAN}",
          quarter["ok"] and worst <= Q2_MAX and mean <= Q2_MEAN,
          f"set {quarter.get('error', 'ok')}; max {worst:.3f}, mean {mean:.4f}")
    q3_misses, q3_worst = [], 0
    if graded25 is not None and sel25 is not None:
        for y in range(CARD_H):
            for x in range(CARD_W):
                s_ = sel25.grey(x, y)
                bp, gp, got = b.px(x, y), g.px(x, y), graded25.px(x, y)
                for c in range(3):
                    want = round(bp[c] + (gp[c] - bp[c]) * s_ / 255)
                    off = abs(got[c] - want)
                    q3_worst = max(q3_worst, off)
                    if off > 2 and len(q3_misses) < 4:
                        q3_misses.append(f"({x},{y}) ch {c}: {got[c]} vs {want} (s {s_})")
    check("Q3 blur 0.25's graded frame = round(B + (G − B)·s/255) ±2 at every pixel (s Q2's "
          "selection, G the unqualified graded frame)",
          graded25 is not None and sel25 is not None and not q3_misses,
          f"worst {q3_worst}; {q3_misses or 'all within'}")

    # Q4 — the matte cuts the coverage and leaves q unchanged: the expected
    # value left of the edge is blur(q) × 1, Q2's oracle, never an oracle of
    # Q4's own matted selection.
    matte_track = doc.new_track()
    window = doc.rectangle(matte_track, CARD_W // 2, CARD_H, [1, 1, 1, 1], x=-CARD_W // 4) \
        if matte_track is not None else None
    matted = doc.call("set_track", track=matte_track, matte="alpha") if window \
        else {"ok": False}
    q4 = doc.frame("q4-selection", selection=adj) if matted["ok"] else None
    doc.call("remove_track", track=matte_track, with_clips=True) if matte_track else None
    lit = [(x, y) for y in range(CARD_H) for x in range(321, CARD_W)
           if q4 is not None and q4.grey(x, y) != 0]
    inside_worst, inside_mean = against(q4, oracle6, columns=lambda x: x <= 318)
    check(f"Q4 a 320×360 alpha matte over the left half: blur 0.25's selection is 0 at every x "
          f"≥ 321 and within Q2's bound of Q2's oracle (σ 6, unmatted) at x ≤ 318",
          matted["ok"] and q4 is not None and not lit and inside_worst <= Q2_MAX
          and inside_mean <= Q2_MEAN,
          f"matte {matted.get('error', 'ok')}; lit right of the edge {len(lit)} "
          f"{lit[:3]}; left max {inside_worst:.3f}, mean {inside_mean:.4f}")

    # Q5
    doc.qualify(ids, blur=0)
    added = doc.call("add_action", clip=adj, at=0, duration=SEC)
    actions = doc.clip(adj).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=adj, action=action,
                     patch={"video": {"qualifier": {"blur": 0.5}}}) if action \
        else {"ok": False}
    late = SEC + SEC // 2
    mid = doc.frame("q5-mid", selection=adj)
    after = doc.frame("q5-after", t=late, selection=adj)
    if action:
        doc.call("remove_action", clip=adj, action=action)
    oracle12 = gaussian(base, CARD_W, CARD_H, 12)
    mid_worst, mid_mean = against(mid, oracle6)
    late_worst, late_mean = against(after, oracle12)
    check("Q5 a 1 s linear action from blur 0 to 0.5: at 0.5 s the selection is within Q2's "
          "bound of the oracle at σ 6, at 1.5 s of the oracle at σ 12",
          added["ok"] and ended["ok"] and mid_worst <= Q2_MAX and mid_mean <= Q2_MEAN
          and late_worst <= Q2_MAX and late_mean <= Q2_MEAN,
          f"action {added.get('error', 'ok')}, end {ended.get('error', 'ok')}; at 0.5 s max "
          f"{mid_worst:.3f}, mean {mid_mean:.4f}; at 1.5 s max {late_worst:.3f}, mean "
          f"{late_mean:.4f}")

    # Q6
    doc.qualify(ids, blur=0.25)
    before = doc.project()
    high = doc.qualify(ids, blur=1.5)
    low = doc.qualify(ids, blur=-0.1)
    on_media = doc.qualify([clip], blur=0.3)
    unchanged = doc.project() == before
    for got in (high, low, on_media):
        if got["ok"]:
            doc.call("undo")
    zero = doc.qualify(ids, blur=0)
    if zero["ok"]:
        doc.call("undo")
    one = doc.qualify(ids, blur=1)
    if one["ok"]:
        doc.call("undo")
    wants = ["video.qualifier.blur must be between 0 and 1, not 1.5",
             "video.qualifier.blur must be between 0 and 1, not -0.1",
             f"clip {clip} is not an adjustment clip and cannot take a qualifier"]
    answers = [high, low, on_media]
    refused = all(not got["ok"] and want in got.get("error", "")
                  for got, want in zip(answers, wants))
    saved_path = WORK / "NC-saved.framejob"
    saved = doc.call("save_project", path=str(saved_path))
    doc.path = saved_path
    try:
        version, stored, _ = saved_qualifier(saved_path, adj)
    except (OSError, ValueError):
        version, stored = None, None
    header = format_version()
    check(f"Q6 blur 1.5 and -0.1 are refused in their sentence and {{blur: 0.3}} on the media "
          f"clip naming it, the project unchanged; 0 and 1 are accepted; saved with blur 0.25, "
          f"video.qualifier.blur is 0.25 and version {header} (the header's)",
          refused and unchanged and zero["ok"] and one["ok"] and saved["ok"]
          and (stored or {}).get("blur") == 0.25 and version == header,
          "; ".join(repr(got.get("error") or "accepted") for got in answers)
          + f"; unchanged {unchanged}; 0 {zero.get('error', 'accepted')}; 1 "
          f"{one.get('error', 'accepted')}; saved {stored}, version {version}")
    return close(client, doc.path)


# ---- project M: the movie ----------------------------------------------------

def run_m(client, media, neutral, state):
    doc, sized = opened(client, "M", CARD_W, CARD_H, background=[0, 0, 0, 1])
    track = (doc.tracks() or [{}])[0].get("id")
    movie = doc.media(media["movie"])
    clip = doc.place(track, movie) if movie is not None else None
    base = neutral.take(doc, "movie")
    state["m_fixture"] = sized and clip is not None and base is not None
    return close(client, doc.path) and state["m_fixture"]


# ---- project S: what a save writes (N2) --------------------------------------

def saved_qualifier(path, clip):
    text = (Path(path) / "project.json").read_text()
    body = json.loads(text)
    found = next((c for c in body.get("clips", []) if c.get("id") == clip), {})
    return body.get("version"), (found.get("video") or {}).get("qualifier"), text


def run_s(client, media, state):
    doc, sized = opened(client, "S", CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    card = doc.media(media["card"])
    clip = doc.place(track, card) if card is not None else None
    front = doc.new_track()
    adj = doc.adjustment(front) if front is not None else None
    state["s_fixture"] = sized and clip is not None and adj is not None
    plain_path = WORK / "S-plain.framejob"
    saved = doc.call("save_project", path=str(plain_path))
    doc.path = plain_path
    try:
        plain_version, _, plain_text = saved_qualifier(plain_path, adj)
    except (OSError, ValueError):
        plain_version, plain_text = None, "unreadable"
    doc.qualify([adj], hue=H1_HUE, luma={})
    ranged_path = WORK / "S-qualified.framejob"
    resaved = doc.call("save_project", path=str(ranged_path))
    doc.path = ranged_path
    try:
        ranged_version, ranged, _ = saved_qualifier(ranged_path, adj)
    except (OSError, ValueError):
        ranged_version, ranged = None, None
    want = {"hue": {"center": 120.0, "width": 40.0, "softness": 20.0},
            "luma": {"low": 0.0, "high": 1.0, "softness": 0.1}}
    stray = '"qualifier"' in plain_text
    version = format_version()
    check(f"N2 an unqualified save holds no `qualifier`; with hue and luma {{}} the clip's "
          f"qualifier is exactly {want}; both at version {version} (the header's)",
          saved["ok"] and resaved["ok"] and not stray and ranged == want
          and plain_version == version and ranged_version == version,
          f"unqualified has qualifier {stray}, version {plain_version}; qualified {ranged}, "
          f"version {ranged_version}")
    return close(client, doc.path)


# ---- project P and the probe -------------------------------------------------

def run_p(client, media, state):
    """HUE, adjustment clip A with hue {120, 40, 20} and adjustment clip B on
    the next two tracks, and a red 200×200 rectangle in front at the centre,
    saved for the probe; (path, ids) or (None, None)."""
    doc, sized = opened(client, "P", HUE_W, HUE_H)
    back = (doc.tracks() or [{}])[0].get("id")
    hue = doc.media(media["hue"])
    clip = doc.place(back, hue) if hue is not None else None
    front = doc.new_track()
    adj = doc.adjustment(front) if front is not None else None
    second_track = doc.new_track()
    second = doc.adjustment(second_track) if second_track is not None else None
    shape_track = doc.new_track()
    shape = doc.rectangle(shape_track, 200, 200, [1, 0, 0, 1]) if shape_track else None
    ok = sized and None not in (clip, adj, second, shape)
    ok = ok and doc.qualify([adj], hue=H1_HUE)["ok"]
    path = WORK / "P-saved.framejob"
    ok = ok and doc.call("save_project", path=str(path))["ok"]
    doc.path = path
    closed = close(client, doc.path)
    state["p_fixture"] = ok
    return (path, {"media": clip, "adjustment": adj, "second": second, "shape": shape}) \
        if ok and closed else (None, None)


# K1's ten colours: the primaries and secondaries, a grey, the ColorChecker
# "light skin" patch, a dark red and a near-black one.
K1_COLOURS = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 255, 255), (255, 0, 255),
              (255, 255, 0), (128, 128, 128), (194, 150, 130), (102, 26, 26), (5, 2, 2)]


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def k1_samples():
    """Each K1 colour with the oracle's reading: hue, C, S′ (the guarded
    saturation) and Y′."""
    out = []
    for rgb in K1_COLOURS:
        hue, chroma, s, v, luma = reading(rgb)
        out.append({"rgb": list(rgb), "hue": hue, "chroma": chroma,
                    "saturation": s * smoothstep(0.03, 0.10, v), "luma": luma})
    return out


def run_probe(sources, package, ids):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "qualifier_probe",
                                  defines=["FRAMEJOB_DEV_TOOLS"], timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        for name in sorted(K_ROWS):
            check(f"{name} the probe builds over app/Sources", False,
                  f"{error} {error.diagnostics[:6]}")
        return
    # A probe has no app bundle: K3's frame needs the compositor's library and
    # the placeholder movie beside the binary, as `matte_probe.py` puts them.
    shader = sources.parent / "Resources/Shaders/Compositor.metal"
    air, library = folder / "Compositor.air", folder / "default.metallib"
    step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o", str(air)],
                       300)
    if step["rc"] == 0:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                            str(library)], 300)
    shutil.copy2(sources.parent / "Resources/Blank.mp4", folder / "Blank.mp4")
    if step["rc"] != 0 or not library.exists():
        for name in sorted(K_ROWS):
            check(f"{name} the shader builds beside the probe", False, step["stderr"][-400:])
        return
    request, answer = folder / "request.json", folder / "answer.json"
    if answer.exists():
        answer.unlink()
    centre = (HUE_W // 2, HUE_H // 2)
    request.write_text(json.dumps({
        "package": str(package), "ids": ids, "shader": str(shader),
        "point": list(centre), "pixel": list(HUE_PIXEL(*centre)), "samples": k1_samples()}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(K_ROWS):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-3000:])
        for row in mine:
            check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---- the run ------------------------------------------------------------------

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
    """A copy of the tree with the mutant's edits, built by its own
    `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    edits, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if any(path.startswith("core/") for path, _, _ in edits):
        reason = own_core(copy)
        if reason:
            return None, reason
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            return None, f"the copy's core/tests could not be linked: {error}"
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


def core_test(copy):
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "qualifier",
                       "--test", "selection", "--test", "qualifier_blur"], 900,
                      cwd=str(copy / "core"))
    lines = (ran["stdout"] + ran["stderr"]).strip().splitlines()
    failed = [line.strip() for line in lines if line.strip().startswith("`--test ")]
    return ran["rc"] == 0 and not ran["expired"], failed or lines[-3:]


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", nargs="?", choices=["capture", "compare"])
    parser.add_argument("folder", nargs="?")
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.mode and not args.folder:
        print(f"{args.mode} needs a folder")
        return 2
    folder = (ROOT / args.folder).resolve() if args.folder else None
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mode != "compare":
        selected.discard("N0")
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    if args.mode == "capture":
        folder.mkdir(parents=True, exist_ok=True)
        selected = {"Z1"}
    named = MUTANTS[args.mutant][1] if args.mutant else []
    scored = [name for name in ROWS if name in selected and name not in RECORDS]
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading-2 G2-4 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test qualifier "
                  "--test selection --test qualifier_blur in the copy's core\n       "
                  + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print(f"grading-2 G2-4 — qualifiers over MCP ({args.mode or 'run'}, {config} build "
              f"{binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    media = fixtures()
    if media["movie"] is None:
        print("instrument failure: ffmpeg did not make the testsrc2 movie")
        return 2
    neutral = Neutral(args.mode, folder)
    log = WORK / "instance.log"
    state = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed, package, ids = True, None, None
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            capture = args.mode == "capture"
            if capture or "N0" in selected or selected & C_ROWS:
                closed = run_c(launched.client, media, neutral, state) and closed
            if capture or "N0" in selected or selected & R_ROWS:
                closed = run_r(launched.client, media, neutral, state) and closed
            if capture or "N0" in selected or selected & Q_ROWS:
                closed = run_q(launched.client, media, neutral, state) and closed
            if capture or "N0" in selected:
                closed = run_m(launched.client, media, neutral, state) and closed
            if "N2" in selected:
                closed = run_s(launched.client, media, state) and closed
            if not capture and selected & NC_ROWS:
                closed = run_nc(launched.client, media, state) and closed
            if selected & K_ROWS:
                package, ids = run_p(launched.client, media, state)
                closed = closed and package is not None
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if selected & K_ROWS:
        if package is None:
            for name in sorted(selected & K_ROWS):
                check(f"{name} project P was made and saved", False)
        else:
            run_probe(sources, package, ids)
    if "N0" in selected:
        missing = [name for name in NEUTRAL if name not in neutral.seen]
        good = not neutral.misses and not missing
        title = (f"N0 the {len(NEUTRAL)} control frames are byte-identical (16 bits a channel) to "
                 f"{args.folder}")
        if config == "release" or args.mutant:
            check(title, good, f"misses {neutral.misses}; not taken {missing}")
        else:
            selected.discard("N0")
            scored = [name for name in scored if name != "N0"]
            print(f"  note N0 is scored on Release only; on {config}: "
                  f"{'equal' if good else neutral.misses + missing}", flush=True)
    found = complaints(log)
    fixtures_ok = all(value for key, value in state.items() if key.endswith("fixture"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Frame Job: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; fixtures {state}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    if args.mode == "capture":
        taken = sorted(p.name for p in folder.glob("*.png"))
        good = rows.get("Z1") and taken == sorted(f"{n}.png" for n in NEUTRAL)
        print(f"captured {len(taken)} unqualified frames into {args.folder}: {taken}")
        return 0 if good else 1
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
        caught = not survived and not others
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy (survived: {', '.join(survived) or 'none'}; other rows failed: "
              f"{', '.join(others) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
