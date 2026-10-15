#!/usr/bin/env python3
"""Road map "grading-2", phase G2-3 (spec §11 GR-12) — the curves end to end
over MCP: `set_video {patch: {curves: {master|red|green|blue: [[x, y], …]}}}`,
the recipe's `curves`, and the compositor's step 4c.2 behind `curvesEnabled`
in the layer stage and the adjustment pass, through the 1,024-texel strip at
`texture(3)`, read back as `render_frame` bytes and one export; then the
probe's rows over `app/Sources`. Road map "grading-4", phase T4-2 (spec §11
GR-32) adds the hue curves, `video.curves.hue_hue` and `.hue_sat`, through
the strip's second row behind `hueCurvesEnabled` (rows H1–H16), the editor's
hover readout and ⇧ axis lock and the Hue and Sat cells (probe rows
P12–P19), and four tone-curved frames to N0.

    python3 tools/proof/curves_proof.py [--app PATH] [--only K1,C1,...]
    python3 tools/proof/curves_proof.py capture DIR    # the uncurved control, before any product edit
    python3 tools/proof/curves_proof.py compare DIR    # every row, and N0 against DIR
    python3 tools/proof/curves_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/curves/home`, and
every package, fixture and PNG is under `tools/proof/work/curves/`, removed at
the start and at exit (the control folder DIR is not). No menu item is
performed. Every call is bounded (`CALL_BOUND`), every ffmpeg too (120 s).
Every project is closed (`close_project`, discard).

Fixtures, written by this script (as `wheels_proof.py`'s): CARD, a 640×360
grey-128 PNG; HUE, a 720×120 PNG whose column x is HSV(x/2°, 1, 1) in 8
bits; GREY, a 720×120 grey ramp (column x round(255·x/719)); TINTED and
ROSE, 720×120 cards of (130, 128, 128) and (153, 102, 102); RAMP, a 1920×360 PNG whose column x is round(255·x/1919); MOVIE,
a 2 s 640×360 30 fps ffmpeg `testsrc2` H.264 file; DEEP, a 2 s 1920×360 black
10-bit ProRes 422 HQ file made through `bt709_fixture.make` (issue #292:
`setparams` on its input and the tags on its output, kept only when ffprobe
reads bt709 ×3 and its first frame reads back against its own graph; a
refusal is an instrument failure, exit 2), placed UNDER the ramp (covered by
it), so the ramp's `render_frame` is a 16-bit PNG (spec §11 PR-4: 16-bit
when any source is deeper) whose inputs are still the ramp's exact 8-bit
codes. Frames are taken at t = 0.5 s unless a row says otherwise; v is the
uncurved render's own value at the sample, so every formula is over measured
bytes. The oracle is this script's own Fritsch–Carlson (`fc`), written from
the paper (SIAM J. Numer. Anal. 17(2), 1980) as GR-12 states it, independent
of `CurveTable`.

Projects, each 30 fps: C (640×360, CARD), R (1920×360, DEEP under RAMP), M
(640×360, MOVIE, background black), S (CARD, saved twice for N2), A1–A3
(CARD, one action each), P (two CARD clips on two tracks with master curves
whose middles are 0.6 and 0.4, saved for the probe).
- **N0** (`compare DIR` only; scored on Release, printed elsewhere): seven
  frames with no curve — card, card-toned (exposure +1), card-wheeled (lift
  master 0.5), card-adjusted (an adjustment clip at exposure +1 over the
  card), ramp, ramp-looked (Warm), movie — and since T4-2 four with tone
  curves only — card-curved (M1's two), card-adjusted-curved (J1's), ramp-curved
  (K1's) and movie-curved (X1's) — decoded at 16 bits a channel are
  byte-identical to `capture DIR`'s, taken on the untouched tree's Release
  build.
- **N1** (C): master `[[0,0],[0.5,0.5],[1,1]]` answers "made no change",
  `get_project` holds no `curves`, and the frame is unchanged.
- **N2** (S): saved uncurved, `project.json` holds no `curves`; saved with red
  `[[0,0],[0.5,0.7],[1,1]]`, the clip's `video.curves` is exactly that red
  curve; both files' `version` is the header's `RC_FORMAT_VERSION`.
- **K1** (R): master `[[0,0],[64/255,40/255],[192/255,215/255],[1,1]]` hits
  each point at the first column the ramp wrote 0, 64, 192 and 255: ±1 at 8
  bits (the 16-bit sample / 257, rounded: ffmpeg's own 8-bit decode of a
  16-bit PNG truncates), and within one 10-bit level (1/1023) at 16 bits.
  The input is the code the ramp WROTE at the column, never the render's.
- **K3** (R): `[[0,0.2],[0.45,0.25],[0.5,0.9],[1,1]]`: along the ramp the
  16-bit output never falls below its running maximum by more than 1 (a
  Catmull–Rom tangent dips about 14 levels of 255 inside the first segment).
- **C1** (R): red `[[0,0],[0.5,0.7],[1,1]]`: R follows `fc` of the written
  code at every 16th column ±1 (8 bits, as K1 reads them); G and B at every
  column are within max(1, one half-float step at v) 16-bit levels of the
  uncurved frame's.
- **M1** (C): master `[[0,0],[0.5,0.25],[1,1]]` with red
  `[[0,0],[0.25,0.75],[1,1]]`: R = red(master(v)), G = B = master(v), ±1.
- **O1** (C): lift master 0.5, then master `[[0,0],[0.5,0.25],[1,1]]` on top:
  every sample = curve(v + 0.125(1 − v)) ±1 (4c.2 after 4c.1: about 82,
  where the curve before the lift gives about 88).
- **A1** (A1): base master `[[0,0],[0.5,0.4],[1,1]]`, a 1 s action to
  `[[0,0],[0.5,0.8],[1,1]]`: at 0.5 s the frame equals the static
  `[[0,0],[0.5,0.6],[1,1]]` frame ±1 (clip_state's 0.6 is `core/tests/curves.rs`'s).
- **A2** (A2): no curve, an action to `[[0,0],[0.5,0.8],[1,1]]`: at 0.5 s the
  frame equals the static `[[0,0],[0.5,0.65],[1,1]]` frame ±1.
- **A3** (A3): base master `[[0,0],[0.5,0.8],[1,1]]`, an action whose end sets
  master to `[[0,0],[1,1]]`: `get_project` keeps that key in the end, at 0.5 s
  the frame equals the static 0.65 frame ±1, and at 1.5 s it is the uncurved
  card's bytes.
- **J1** (C): an adjustment clip with master `[[0,0],[0.5,0.25],[1,1]]` over
  the card renders the card curved directly, ±1 at every sample.
- **X1** (M): master `[[0,0],[0.25,0.1],[0.75,0.9],[1,1]]` and red
  `[[0,0],[0.5,0.7],[1,1]]` on the movie: the `prores_422` export's frame 15
  is within ±8 of `render_frame` at every 16th pixel, and the curved frame
  differs from the uncurved by more than 30 somewhere.
- **U1** (C): undo after a master curve brings the uncurved pixels back, redo
  the curved ones.
- **V1** (C): with master and red curves set, `render_frame {ungraded: true}`
  is the uncurved bytes (and the plain frame is not).
- **P0** (C): `paste_attributes` of a payload clip whose video holds curves
  leaves the target's `video.curves` equal to the payload's.
- **R1** (C): 17 points, red[2].x 1.2 and a master x falling are refused by
  their three sentences, the project unchanged; a curve with points at
  exactly x 0 and 1 and y 0 and 1 is accepted.
- **H1** (H, HUE): hue_hue `[[0,0],[60,0],[120,40],[180,0]]`: every column
  at hue ≤ 55° or ≥ 185° is the uncurved bytes, the rest the oracle ±1 (the
  oracle: this script's periodic Fritsch–Carlson `fc_periodic`, its strip
  `HueStrip` and the step `hue_step`, from GR-32's sentences, applied to the
  uncurved render's own value). **H2**: hue_sat `[[0,1],[60,1],[120,0],[180,1]]`
  the same, the 120° column grey. **H3** (GREY, TINTED): hue_hue +90 and
  hue_sat 0 change no byte (the chroma guard). **H4**: the wrap
  `[[10,40],[180,0],[350,-20]]`: hue 0°, 5° and 355° per the oracle ±1, its
  shift at 0° exactly 10°. **H6**: an adjustment clip with H1's and H2's
  curves = the clip curved directly ±1. **H7**: the five refusals by their
  sentences, the project unchanged; an identity hue patch "made no change".
  **H8** (two projects): a same-count action at 0.5 s = the static middle
  curve ±1; none → H2's = the half curve ±1. **H9**: `render_frame
  {ungraded}` with both set = the uncurved bytes. **H12** (ROSE and H15's
  frames): Rec. 709 luma kept ±1 under +90° and on every HUE column under
  ±40°. **H13**: hue_hue +60 with hue_sat 0 at 60°: the red column is the
  oracle with the gain read at its own hue (not grey). **H14**: red
  `[[0,0],[1,0]]` then H2's hue_sat: the yellow column turns green and so
  grey. **H15** (independent of the oracle: hues by `colorsys`): under
  hue_hue ±40 every column's signed HSV-hue change is the value ±1° at output
  chroma ≥ 64 and ±2° everywhere, and the 120° column lands in (120°, 180°]
  under +40 and [80°, 120°) under −40. **H16** (a RECORD, PASS whenever it
  measures): Color's Hue +40 on HUE, the 0° and 120° columns' signed change
  and its direction against the label's sign.
- **P1–P19**: `curves_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of every P row), P1–P11
  and P16–P17 on project P; each row's sentence is the probe's. T4-2's: P7
  the strip 1,024 × 2 and the 2 × 2 placeholder; P12 the periodic spline
  against `fc_periodic` on 200 seeded hue curves per domain, 1e-9; P13 the
  two flags; P14 the ⇧ lock; P15 the readout's text at three points; P16
  the six cells and a Hue gesture in degrees, one step; P17 the In and Out
  fields' units and clamps across Red → Hue → Sat → Red; P18 a hue point
  held inside 0…359.9; P19 the six labels fit their cells at the 230 pt
  plot.
- **Z1** (CONTROL): the fixtures hold (the ramp's frame a 16-bit PNG), the
  projects close and the log holds no `Frame Job: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it, the probe built
over the copy's `app/Sources`. A core mutant also runs `cargo test --release
--no-fail-fast --test curves --test ungraded` in the copy's own `core/` (row
CT). MUTANT PASS when every named row FAILED and no other scored row did:
  catmull-rom              interior tangents (y(k+1) − y(k−1)) / (x(k+1) − x(k−1)),
                           no Fritsch–Carlson limit: K3 P6
  master-channel-swapped   the strip holds master(channel(v)): M1
  strip-without-half-texel the strip sampled at v, not v·(n−1)/n + 0.5/n: C1
  strip-rgba16             the strip uploaded as rgba16Float: P7
  rising-check-dropped     the x-rising refusal gone: R1 CT
  curves-before-wheels     step 4c.2 moved before 4c.1: O1
  ungraded-misses-curves   `ungraded` keeps the curves: V1 CT
  adjust-without-curves    the adjustment pass has no step 4c.2: J1
  identity-kept            `set_video` stores an identity curve: N1 CT
  identity-not-aligned     no identity alignment in an action: A2 A3 CT
  hue-wrap-dropped         a hue curve flat outside its first and last x: H4 P12
  hue-from-graded          the gain sampled at the turned hue: H13
  hue-shift-reversed       the turn's degrees negated: H15 H1 H4 H13
  luma-not-kept            the turn as HSV(h + degrees, S, V): H12 H1 H4 H13
  gamut-limit-dropped      k fixed at 1: H15 H12 H1 H4 H13
  chroma-guard-dropped     no chroma guard on the hue curves: H3
  hue-before-channel-curves  the hue curves before the channel curves: H14
  row-0-at-centre          row 0 sampled at y 0.5: K1 C1 M1 O1
(A turn edit fails every row whose oracle turns a colour — H1, H4, H13 — and
row 0 at y 0.5 every tone row, O1 too: each is named, as it fails by
construction.)
  shift-lock-ignored       the drag's ⇧ ignored: P14
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import colorsys
import json
import math
import re
import struct
import subprocess
import sys
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import bt709_fixture  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/curves"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/curves_probe.swift"
HEADER = ROOT / "core/include/framejob_core.h"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
CARD_W, CARD_H = 640, 360
RAMP_W, RAMP_H = 1920, 360
GREY = 128
CHANNELS = ["master", "red", "green", "blue"]
NEUTRAL = ["card", "card-toned", "card-wheeled", "card-adjusted", "ramp", "ramp-looked",
           "movie", "card-curved", "card-adjusted-curved", "ramp-curved", "movie-curved"]
HUE_W, HUE_H = 720, 120
ROWS = ["N0", "N1", "N2", "K1", "K3", "C1", "M1", "O1", "A1", "A2", "A3", "J1", "X1", "U1",
        "V1", "P0", "R1", "H1", "H2", "H3", "H4", "H6", "H7", "H8", "H9", "H12", "H13", "H14",
        "H15", "H16", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11",
        "P12", "P13", "P14", "P15", "P16", "P17", "P18", "P19", "Z1"]
RECORDS = {"H16"}
C_ROWS = {"N1", "M1", "O1", "J1", "U1", "V1", "P0", "R1"}
R_ROWS = {"K1", "K3", "C1"}
M_ROWS = {"X1"}
A_ROWS = {"A1", "A2", "A3"}
H_ROWS = {"H1", "H2", "H3", "H4", "H6", "H7", "H8", "H9", "H12", "H13", "H14", "H15", "H16"}
P_ROWS = {"P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11", "P12", "P13",
          "P14", "P15", "P16", "P17", "P18", "P19"}
SHADER = "app/Resources/Shaders/Compositor.metal"
TABLE = "app/Sources/CurveTable.swift"
TEXTURES = "app/Sources/CurveTextures.swift"
EDITOR = "app/Sources/CurveEditorView.swift"
STEP_4C1 = ("        // (4c.1) The wheels (spec §11 GR-11): once per pixel, after tone and\n"
            "        // before the look. Behind `wheelsEnabled`, so an unwheeled layer never\n"
            "        // enters it.\n"
            "        if (u.wheelsEnabled > 0.5) {\n"
            "            rgb = gradeWheels(rgb, u);\n"
            "        }\n\n")
STEP_4C2 = ("        // (4c.2) The curves (spec §11 GR-12): once per pixel, after the wheels\n"
            "        // and before the look, through the strip at `texture(3)`. Behind\n"
            "        // `curvesEnabled`, so an uncurved layer never enters it.\n"
            "        if (u.curvesEnabled > 0.5) {\n"
            "            rgb = gradeCurves(rgb, curves, samp);\n"
            "        }\n\n")
ADJUST_4C2 = ("    if (u.curvesEnabled > 0.5) {\n"
              "        c = gradeCurves(c, curves, samp);\n"
              "    }\n")
STEP_HUE = ("        // (4c.2) The hue curves (spec §11 GR-32): once per pixel, after the\n"
            "        // channel curves and before the look, through the strip's second row.\n"
            "        // Behind `hueCurvesEnabled`, so a layer without them never enters it.\n"
            "        if (u.hueCurvesEnabled > 0.5) {\n"
            "            rgb = gradeHueCurves(rgb, curves, samp);\n"
            "        }\n\n")
HUE_GAIN = ("    if (abs(curve.g - 1.0) > 1e-6) {\n"
            "        out = mix(float3(dot(out, float3(0.2126, 0.7152, 0.0722))), out, curve.g);\n"
            "    }\n")
HUE_RETURN = "    return y + max(k, 0.0) * d;\n"
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "catmull-rom": ([
        (TABLE,
         "            tangents[k] = before * after <= 0 ? 0 : (before + after) / 2\n",
         "            tangents[k] = (ys[k + 1] - ys[k - 1]) / (xs[k + 1] - xs[k - 1])\n"),
        (TABLE,
         "            if squared > 9 {\n",
         "            if false {\n")], ["K3", "P6"]),
    "master-channel-swapped": ([(
        TABLE,
        "            let m = value(curves.master, at: x)\n"
        "            out[4 * i] = Float(value(curves.red, at: m))\n"
        "            out[4 * i + 1] = Float(value(curves.green, at: m))\n"
        "            out[4 * i + 2] = Float(value(curves.blue, at: m))\n",
        "            out[4 * i] = Float(value(curves.master, at: value(curves.red, at: x)))\n"
        "            out[4 * i + 1] = Float(value(curves.master, at: value(curves.green, at: x)))\n"
        "            out[4 * i + 2] = Float(value(curves.master, at: value(curves.blue, at: x)))\n")],
        ["M1"]),
    "strip-without-half-texel": ([(
        SHADER,
        "    float3 at = saturate(rgb) * ((n - 1.0) / n) + 0.5 / n;\n",
        "    float3 at = saturate(rgb);\n")], ["C1"]),
    "strip-rgba16": ([(
        TEXTURES,
        "        format = device.supports32BitFloatFiltering ? .rgba32Float : .rgba16Float\n",
        "        format = .rgba16Float\n")], ["P7"]),
    "rising-check-dropped": ([(
        "core/src/grade_check.rs",
        "            if index > 0 && point[0] <= points[index - 1][0] {\n",
        "            if false {\n")], ["R1", "CT"]),
    "curves-before-wheels": ([
        (SHADER, STEP_4C2, ""),
        (SHADER, STEP_4C1, STEP_4C2 + STEP_4C1)], ["O1"]),
    "ungraded-misses-curves": ([(
        "core/src/recipe.rs",
        "            moved.curves = Curves::default();\n",
        "")], ["V1", "CT"]),
    "adjust-without-curves": ([(SHADER, ADJUST_4C2, "")], ["J1"]),
    "identity-kept": ([(
        "core/src/edit_props.rs",
        "                    props.curves.drop_identities();\n",
        "")], ["N1", "CT"]),
    "identity-not-aligned": ([(
        "core/src/actions.rs",
        "            align_identity_curves(&mut state, &mut target);\n",
        "")], ["A2", "A3", "CT"]),
    # T4-2 (spec §11 GR-32): one per decision.
    "hue-wrap-dropped": ([(
        TABLE,
        "            if x < xs[0] {\n"
        "                x += period\n"
        "            } else if x < xs[n - 1] {\n",
        "            if x < xs[0] {\n"
        "                return ranged(ys[0])\n"
        "            } else if x >= xs[n - 1] {\n"
        "                return ranged(ys[n - 1])\n"
        "            } else {\n")], ["H4", "P12"]),
    "hue-from-graded": ([(
        SHADER, HUE_GAIN,
        "    float3 o = saturate(out);\n"
        "    float omx = max(o.r, max(o.g, o.b));\n"
        "    float oh = hsvHue(o, omx, omx - min(o.r, min(o.g, o.b)));\n"
        "    float gain = strip.sample(samp, float2((oh / 360.0) * ((n - 1.0) / n) + 0.5 / n,"
        " 0.75)).g;\n"
        "    if (abs(gain - 1.0) > 1e-6) {\n"
        "        out = mix(float3(dot(out, float3(0.2126, 0.7152, 0.0722))), out, gain);\n"
        "    }\n")], ["H13"]),
    "hue-shift-reversed": ([(
        SHADER,
        "        out = gradeHueShift(out, h, 360.0 * curve.r);\n",
        "        out = gradeHueShift(out, h, -360.0 * curve.r);\n")], ["H15", "H1", "H4", "H13"]),
    "luma-not-kept": ([(
        SHADER, HUE_RETURN,
        "    float s = mx > 0.0 ? (mx - mn) / mx : 0.0;\n"
        "    float3 full = saturate(abs(fmod(fmod(hue + degrees + 360.0, 360.0) / 60.0"
        " + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0);\n"
        "    return mx * mix(float3(1.0), full, s);\n")], ["H12", "H1", "H4", "H13"]),
    "gamut-limit-dropped": ([(SHADER, HUE_RETURN, "    return y + d;\n")],
                            ["H15", "H12", "H1", "H4", "H13"]),
    "chroma-guard-dropped": ([(
        SHADER,
        "    return mix(rgb, out, smoothstep(0.02, 0.06, chroma));\n",
        "    return out;\n")], ["H3"]),
    "hue-before-channel-curves": ([
        (SHADER, STEP_HUE, ""),
        (SHADER, STEP_4C2, STEP_HUE + STEP_4C2)], ["H14"]),
    "row-0-at-centre": ([(
        SHADER,
        "    return float3(strip.sample(samp, float2(at.r, 0.25)).r,\n"
        "                  strip.sample(samp, float2(at.g, 0.25)).g,\n"
        "                  strip.sample(samp, float2(at.b, 0.25)).b);\n",
        "    return float3(strip.sample(samp, float2(at.r, 0.5)).r,\n"
        "                  strip.sample(samp, float2(at.g, 0.5)).g,\n"
        "                  strip.sample(samp, float2(at.b, 0.5)).b);\n")],
        ["K1", "C1", "M1", "O1"]),
    "shift-lock-ignored": ([(EDITOR, "        if lock {\n", "        if lock && false {\n")],
                           ["P14"]),
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
    """`RC_FORMAT_VERSION` off the tree's own header, not a copy: a copy goes
    stale at every bump (`e2_proof.py`'s helper)."""
    match = re.search(r"#define RC_FORMAT_VERSION (\d+)", HEADER.read_text())
    if match is None:
        raise RuntimeError(f"{HEADER} has no `#define RC_FORMAT_VERSION <n>` line")
    return int(match.group(1))


# ---- the oracle -----------------------------------------------------------------

def fc(points, x):
    """The Fritsch–Carlson monotone cubic at `x`, clamped 0…1, as GR-12 states
    it: secants; end tangents the end secants; an interior tangent the mean of
    its two secants, or 0 where they differ in sign or one is 0; per segment a
    flat secant zeroes both tangents, else α² + β² > 9 scales both by
    3/√(α² + β²); flat outside the first and last x."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    n = len(points)
    if x <= xs[0]:
        return min(max(ys[0], 0.0), 1.0)
    if x >= xs[-1]:
        return min(max(ys[-1], 0.0), 1.0)
    d = [(ys[k + 1] - ys[k]) / (xs[k + 1] - xs[k]) for k in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for k in range(1, n - 1):
        m[k] = 0.0 if d[k - 1] * d[k] <= 0 else (d[k - 1] + d[k]) / 2
    for k in range(n - 1):
        if d[k] == 0:
            m[k] = m[k + 1] = 0.0
            continue
        a, b = m[k] / d[k], m[k + 1] / d[k]
        s = a * a + b * b
        if s > 9:
            t = 3 / math.sqrt(s)
            m[k], m[k + 1] = t * a * d[k], t * b * d[k]
    k = max(i for i in range(n - 1) if xs[i] <= x)
    h = xs[k + 1] - xs[k]
    t = (x - xs[k]) / h
    y = ((2 * t ** 3 - 3 * t ** 2 + 1) * ys[k] + (t ** 3 - 2 * t ** 2 + t) * h * m[k]
         + (-2 * t ** 3 + 3 * t ** 2) * ys[k + 1] + (t ** 3 - t ** 2) * h * m[k + 1])
    return min(max(y, 0.0), 1.0)


def fc_periodic(points, x, low, high, period=360.0):
    """GR-32's periodic Fritsch–Carlson at `x`, clamped to `low`…`high`:
    n secants, the last from the last point to the first one period on;
    every tangent the mean of the secants either side of it (indices mod n),
    or 0 where they differ in sign or one is 0; per segment in order, the
    wrap segment last, a flat secant zeroes both tangents, else α² + β² > 9
    scales both by 3/√(α² + β²); outside the first and last x, the wrap
    segment. Written from the paper as GR-32 states it, not from
    `CurveTable`."""
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    n = len(points)
    x = math.fmod(x, period)
    if x < 0:
        x += period

    def run(k):
        return (xs[k + 1] if k < n - 1 else xs[0] + period) - xs[k]

    d = [(ys[(k + 1) % n] - ys[k]) / run(k) if run(k) > 0 else 0.0 for k in range(n)]
    m = [0.0 if d[k - 1] * d[k] <= 0 else (d[k - 1] + d[k]) / 2 for k in range(n)]
    for k in range(n):
        j = (k + 1) % n
        if d[k] == 0:
            m[k] = m[j] = 0.0
            continue
        a, b = m[k] / d[k], m[j] / d[k]
        s = a * a + b * b
        if s > 9:
            t = 3 / math.sqrt(s)
            m[k], m[j] = t * a * d[k], t * b * d[k]
    if x < xs[0]:
        x += period
        k = n - 1
    elif x >= xs[-1]:
        k = n - 1
    else:
        k = max(i for i in range(n - 1) if xs[i] <= x)
    j = (k + 1) % n
    h = run(k)
    t = (x - xs[k]) / h
    y = ((2 * t ** 3 - 3 * t ** 2 + 1) * ys[k] + (t ** 3 - 2 * t ** 2 + t) * h * m[k]
         + (-2 * t ** 3 + 3 * t ** 2) * ys[j] + (t ** 3 - t ** 2) * h * m[j])
    return min(max(y, low), high)


SHIFT_IDENTITY = [[0, 0], [180, 0]]
GAIN_IDENTITY = [[0, 1], [180, 1]]
STRIP_N = 1024


def luma(rgb):
    return 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]


def hsv_hue(c):
    """GR-13's HSV hue of a saturated colour, degrees, 0 with no chroma."""
    mx, mn = max(c), min(c)
    chroma = mx - mn
    if chroma <= 0:
        return 0.0
    r, g, b = c
    if mx == r:
        return 60 * math.fmod((g - b) / chroma + 6, 6)
    if mx == g:
        return 60 * ((b - r) / chroma + 2)
    return 60 * ((r - g) / chroma + 4)


def hue_chroma(degrees):
    """The fully saturated hue less its Rec. 709 luma (`lookHueChroma`)."""
    full = [min(max(abs(math.fmod(degrees / 60 + o, 6) - 3) - 1, 0), 1) for o in (0, 4, 2)]
    y = luma(full)
    return [f - y for f in full]


class HueStrip:
    """Row 1 of the strip as GR-32 fills it — texel i the shift in turns and
    the gain at hue 360·i/1023 — sampled linearly at the texel-centre span."""

    def __init__(self, shift, gain):
        hues = [360 * i / (STRIP_N - 1) for i in range(STRIP_N)]
        self.turns = [fc_periodic(shift, h, -180, 180) / 360 for h in hues]
        self.gains = [fc_periodic(gain, h, 0, 2) for h in hues]

    def at(self, h):
        pos = h / 360 * (STRIP_N - 1)
        i = min(int(math.floor(pos)), STRIP_N - 1)
        f = pos - i
        j = min(i + 1, STRIP_N - 1)
        return (self.turns[i] + (self.turns[j] - self.turns[i]) * f,
                self.gains[i] + (self.gains[j] - self.gains[i]) * f)


def hue_shift(rgb, hue, degrees):
    """GR-32's turn: Cr along the hue `hue + degrees` less its luma, added to
    the luma, scaled by the largest k ≤ 1 keeping every channel inside
    [min(0, min rgb), max(1, max rgb)]."""
    y = luma(rgb)
    mx, mn = max(rgb), min(rgb)
    d = [(mx - mn) * v for v in hue_chroma(math.fmod(hue + degrees + 360, 360))]
    lo, hi = min(0.0, mn), max(1.0, mx)
    k = 1.0
    for v in d:
        if v > 0:
            k = min(k, (hi - y) / v)
        elif v < 0:
            k = min(k, (lo - y) / v)
    return [y + max(k, 0.0) * v for v in d]


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def hue_step(rgb, strip):
    """Step 4c.2's second half on an encoded colour (floats), as GR-32 states
    it: the hue read once, the turn, then the gain about the luma, weighted
    by the chroma guard."""
    c = [min(max(v, 0.0), 1.0) for v in rgb]
    chroma = max(c) - min(c)
    h = hsv_hue(c)
    turns, gain = strip.at(h)
    out = list(rgb)
    if abs(turns) > 1e-6:
        out = hue_shift(out, h, 360 * turns)
    if abs(gain - 1) > 1e-6:
        y = luma(out)
        out = [y + (v - y) * gain for v in out]
    w = smoothstep(0.02, 0.06, chroma)
    return [a + (b - a) * w for a, b in zip(rgb, out)]


def hue_codes(pixel, strip, tone=None):
    """The 8-bit codes `hue_step` makes of an uncurved 8-bit `pixel`, with
    `tone` (per-channel functions) applied first when given."""
    rgb = [v / 255 for v in pixel]
    if tone is not None:
        rgb = [f(v) for f, v in zip(tone, rgb)]
    return tuple(code(v) for v in hue_step(rgb, strip))


def signed_hue_change(before, after):
    """The HSV hue change from 8-bit `before` to `after` (colorsys), in
    degrees, wrapped into (−180, 180]."""
    a = colorsys.rgb_to_hsv(*[v / 255 for v in before])[0] * 360
    b = colorsys.rgb_to_hsv(*[v / 255 for v in after])[0] * 360
    change = (b - a) % 360
    return change - 360 if change > 180 else change


def half_step(value):
    """One half-float step at `value` (0…1), in 16-bit levels."""
    if value <= 2 ** -14:
        return 2 ** -24 * 65535
    return 2 ** (math.floor(math.log2(value)) - 10) * 65535


# ---- pixels -------------------------------------------------------------------

def write_png(path, width, height, value_of_x):
    """An 8-bit RGB PNG, untagged, whose column x is grey `value_of_x(x)`."""
    row = bytes([0]) + b"".join(bytes([value_of_x(x)] * 3) for x in range(width))
    raw = row * height

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return path


def write_rgb_png(path, width, height, rgb_of_x):
    """An 8-bit RGB PNG, untagged, whose column x is the colour `rgb_of_x(x)`."""
    row = bytes([0]) + b"".join(bytes(rgb_of_x(x)) for x in range(width))
    raw = row * height

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return path


def hue_column(x):
    """HUE's column x: HSV(x / 2 degrees, 1, 1) in 8 bits."""
    return tuple(round(255 * v) for v in colorsys.hsv_to_rgb(x / 2 / 360, 1, 1))


def png_depth(path):
    """A PNG's IHDR bit depth, or None."""
    try:
        data = Path(path).read_bytes()[:32]
    except OSError:
        return None
    return data[24] if data[:8] == b"\x89PNG\r\n\x1a\n" else None


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
    """One decoded frame: `raw` RGBA bytes, `deep` its 16-bit decode (lazily),
    `width`, and the PNG's path."""

    def __init__(self, path, raw, width, height):
        self.path, self.raw, self.width, self.height = path, raw, width, height
        self._deep = None

    def px(self, x, y):
        at = (y * self.width + x) * 4
        return tuple(self.raw[at:at + 3])

    def px8(self, x, y):
        """The 16-bit sample rounded to 8 bits (v16 / 257): a 16-bit frame's
        own 8-bit reading, where ffmpeg's `rgba` decode truncates."""
        return tuple(round(c / 257) for c in self.px16(x, y))

    def px16(self, x, y):
        if self._deep is None:
            self._deep = decode(self.path, self.width, self.height, deep=True) or b""
        at = (y * self.width + x) * 8
        if len(self._deep) < at + 6:
            return (0, 0, 0)
        return struct.unpack("<3H", self._deep[at:at + 6])


def code(value):
    return round(255 * min(max(value, 0.0), 1.0))


def close_to(got, want, tolerance=1):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


def same_pixels(a, b):
    return a is not None and b is not None and a.raw == b.raw


GRID = [(x, y) for y in range(20, CARD_H, 40) for x in range(20, CARD_W, 40)]


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

    def curves(self, clips, **channels):
        return self.call("set_video", clips=clips, patch={"curves": channels})

    def color(self, clips, **keys):
        return self.call("set_video", clips=clips, patch={"color": keys})

    def wheels(self, clips, **wheels):
        return self.call("set_video", clips=clips, patch={"wheels": wheels})

    def uncurve(self, clips):
        return self.curves(clips, **{c: None for c in CHANNELS})

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
        return Frame(out, raw, self.width, self.height)


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
    card = write_png(WORK / "card.png", CARD_W, CARD_H, lambda x: GREY)
    ramp = write_png(WORK / "ramp.png", RAMP_W, RAMP_H, lambda x: round(255 * x / (RAMP_W - 1)))
    movie = WORK / "testsrc2.mp4"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={CARD_W}x{CARD_H}:rate=30:duration=2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)], 120)
    deep, deep_why = bt709_fixture.make(
        WORK / "deep.mov", ["-f", "lavfi", "-i", f"color=c=black:size={RAMP_W}x{RAMP_H}:"
                            f"rate=30:duration=2,{bt709_fixture.SETPARAMS}"],
        ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"],
        {"codec_name": "prores", "pix_fmt": "yuv422p10le", "width": RAMP_W, "height": RAMP_H},
        "yuv422p10le", 120)
    return (card, ramp, movie if made["rc"] == 0 and movie.exists() else None, deep, deep_why)


# ---- N0: the uncurved frames --------------------------------------------------

class Neutral:
    """Where the uncurved frames go: `capture` writes them to DIR, `compare`
    holds each against DIR's, a plain run only keeps them."""

    def __init__(self, mode, folder):
        self.mode, self.folder, self.misses, self.seen = mode, folder, [], []

    def take(self, doc, name):
        frame = doc.frame(f"neutral-{name}")
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


def card_doc(client, name, card):
    """A new CARD project; (Doc, clip, its uncurved frame, the grey value v)."""
    doc, sized = opened(client, name, CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    clip = doc.place(track, media) if media is not None else None
    base = doc.frame(f"{name}-base") if clip is not None else None
    v = base.px(CARD_W // 2, CARD_H // 2)[0] if base is not None else None
    good = sized and clip is not None and base is not None and all(
        base.px(x, y) == (v, v, v) for x, y in GRID)
    return doc, clip, (base if good else None), v


def grid_misses(frame, want_of):
    """Every GRID sample of `frame` against `want_of(x, y)` (an RGB triple), ±1."""
    if frame is None:
        return ["the frame is missing"]
    return [f"({x},{y}) {frame.px(x, y)} vs {want_of(x, y)}" for x, y in GRID
            if not close_to(frame.px(x, y), want_of(x, y))]


# ---- project C: the card -----------------------------------------------------

def run_c(client, card, neutral, state):
    doc, sized = opened(client, "C", CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    clip = doc.place(track, media) if media is not None else None
    base = neutral.take(doc, "card")
    v = base.px(CARD_W // 2, CARD_H // 2)[0] if base is not None else None
    fixture = sized and clip is not None and base is not None and all(
        base.px(x, y) == (v, v, v) for x, y in GRID)
    ids = [clip]
    # The tone, wheel and adjustment paths with no curve (N0's second to fourth).
    toned = doc.color(ids, exposure=1) if fixture else {"ok": False}
    exposed = neutral.take(doc, "card-toned") if toned["ok"] else None
    doc.color(ids, exposure=0)
    lifted = doc.wheels(ids, lift={"master": 0.5}) if fixture else {"ok": False}
    wheeled = neutral.take(doc, "card-wheeled") if lifted["ok"] else None
    doc.wheels(ids, lift={"master": 0})
    front = doc.new_track() if fixture else None
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    adjusted = doc.color([adjustment], exposure=1) if adjustment else {"ok": False}
    neutral.take(doc, "card-adjusted") if adjusted["ok"] else None
    removed = doc.call("remove_track", track=front, with_clips=True) if front else {"ok": False}
    # The tone curves (T4-2): M1's two and J1's adjustment curve, held byte-identical too.
    toned_curves = doc.curves(ids, master=[[0, 0], [0.5, 0.25], [1, 1]],
                              red=[[0, 0], [0.25, 0.75], [1, 1]]) if fixture else {"ok": False}
    curved = neutral.take(doc, "card-curved") if toned_curves["ok"] else None
    doc.uncurve(ids)
    front = doc.new_track() if fixture else None
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    adjust_curved = doc.curves([adjustment], master=[[0, 0], [0.5, 0.25], [1, 1]]) \
        if adjustment else {"ok": False}
    neutral.take(doc, "card-adjusted-curved") if adjust_curved["ok"] else None
    removed_curved = doc.call("remove_track", track=front, with_clips=True) if front \
        else {"ok": False}
    fixture = (fixture and exposed is not None and wheeled is not None and adjusted["ok"]
               and removed["ok"] and curved is not None and adjust_curved["ok"]
               and removed_curved["ok"])
    state["c_fixture"] = fixture
    print(f"  C: card clip {clip}, uncurved value {v} (written {GREY})", flush=True)
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture
    x0 = v / 255

    # N1
    diagonal = doc.curves(ids, master=[[0, 0], [0.5, 0.5], [1, 1]])
    n1 = doc.frame("n1")
    stray = "curves" in (doc.clip(clip).get("video") or {})
    check("N1 master [[0,0],[0.5,0.5],[1,1]] is an identity (\"made no change\"), get_project "
          "holds no curves, and the frame is unchanged",
          not diagonal["ok"] and "made no change" in diagonal.get("error", "") and not stray
          and same_pixels(n1, base),
          f"answer {diagonal.get('error') or diagonal.get('reply')!r}; stored curves {stray}")
    if diagonal["ok"]:
        doc.call("undo")

    # R1
    before = doc.project()
    seventeen = [[i / 16, i / 16] for i in range(17)]
    many = doc.curves(ids, red=seventeen)
    outside = doc.curves(ids, red=[[0, 0], [0.5, 0.5], [1.2, 1]])
    falling = doc.curves(ids, master=[[0, 0], [0.5, 0.3], [0.4, 0.6], [1, 1]])
    unchanged = doc.project() == before
    for got in (many, outside, falling):  # a value accepted in error is taken back
        if got["ok"]:
            doc.call("undo")
    edges = doc.curves(ids, green=[[0, 0], [0.5, 1], [1, 1]], blue=[[0, 1], [1, 0]])
    if edges["ok"]:
        doc.call("undo")
    wants = ["video.curves.red needs 2 to 16 points, not 17",
             "video.curves.red[2].x must be between 0 and 1, not 1.2",
             "video.curves.master[2].x (0.4) must be greater than video.curves.master[1].x "
             "(0.5)"]
    answers = [many, outside, falling]
    refused = all(not got["ok"] and want in got.get("error", "")
                  for got, want in zip(answers, wants))
    check("R1 17 points, red[2].x 1.2 and a falling master x are refused by their three "
          "sentences, the project unchanged; points at exactly 0 and 1 are accepted",
          refused and unchanged and edges["ok"],
          "; ".join(repr(got.get("error") or "accepted") for got in answers)
          + f"; unchanged {unchanged}; edges {edges.get('error', 'accepted')}")

    # M1
    master = [[0, 0], [0.5, 0.25], [1, 1]]
    red = [[0, 0], [0.25, 0.75], [1, 1]]
    both = doc.curves(ids, master=master, red=red)
    m1 = doc.frame("m1")
    doc.uncurve(ids)
    m = fc(master, x0)
    want = (code(fc(red, m)), code(m), code(m))
    misses = grid_misses(m1, lambda x, y: want)
    check(f"M1 master [[0,0],[0.5,0.25],[1,1]] with red [[0,0],[0.25,0.75],[1,1]]: R = "
          f"red(master(v)), G = B = master(v), ±1 (want {want})", both["ok"] and not misses,
          f"set {both.get('error', 'ok')}; {misses[:3] or 'all within'}")

    # O1
    lift = doc.wheels(ids, lift={"master": 0.5})
    curve = doc.curves(ids, master=master)
    o1 = doc.frame("o1")
    doc.uncurve(ids)
    doc.wheels(ids, lift={"master": 0})
    want = (code(fc(master, x0 + 0.125 * (1 - x0))),) * 3
    misses = grid_misses(o1, lambda x, y: want)
    check(f"O1 lift master 0.5 then master [[0,0],[0.5,0.25],[1,1]]: every sample = "
          f"curve(v + 0.125(1 − v)) ±1 (want {want[0]}, got "
          f"{o1.px(CARD_W // 2, CARD_H // 2) if o1 else None})",
          lift["ok"] and curve["ok"] and not misses, "; ".join(misses[:3]) or "all within")

    # U1
    curved = doc.curves(ids, master=master)
    u_curved = doc.frame("u1-curved")
    undone = doc.call("undo")
    u_plain = doc.frame("u1-undone")
    redone = doc.call("redo")
    u_redone = doc.frame("u1-redone")
    check("U1 undo after a master curve brings the uncurved pixels back, redo the curved ones",
          curved["ok"] and undone["ok"] and redone["ok"] and same_pixels(u_plain, base)
          and same_pixels(u_redone, u_curved) and not same_pixels(u_curved, base),
          f"set {curved.get('error', 'ok')}; undo {undone.get('error', 'ok')}; redo "
          f"{redone.get('error', 'ok')}; uncurved {same_pixels(u_plain, base)}; curved "
          f"{same_pixels(u_redone, u_curved)}")
    doc.uncurve(ids)

    # V1
    pushed = doc.curves(ids, master=master, red=red)
    plain = doc.frame("v1-plain")
    ungraded = doc.frame("v1-ungraded", ungraded=True)
    check("V1 render_frame {ungraded: true} with master and red curves set is the uncurved "
          "bytes, and the plain frame is not", pushed["ok"] and same_pixels(ungraded, base)
          and plain is not None and not same_pixels(plain, base),
          f"set {pushed.get('error', 'ok')}; ungraded {same_pixels(ungraded, base)}; plain "
          f"curved {plain is not None and not same_pixels(plain, base)}")
    doc.uncurve(ids)

    # J1
    direct_set = doc.curves(ids, master=master)
    direct = doc.frame("j1-direct")
    doc.uncurve(ids)
    front = doc.new_track()
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    adjust_set = doc.curves([adjustment], master=master) if adjustment else {"ok": False}
    j1 = doc.frame("j1")
    j_misses = grid_misses(j1, lambda x, y: direct.px(x, y)) if direct is not None \
        else ["no direct frame"]
    check("J1 an adjustment clip with master [[0,0],[0.5,0.25],[1,1]] over the card renders "
          "the card curved directly, ±1", direct_set["ok"] and adjust_set["ok"]
          and not j_misses and not same_pixels(direct, base),
          f"direct {direct_set.get('error', 'ok')}; adjustment {adjustment} "
          f"{adjust_set.get('error', 'ok')}; {j_misses[:3] or 'all within'}")
    if front is not None:
        doc.call("remove_track", track=front, with_clips=True)

    # P0
    curves = {"master": [[0.0, 0.0], [0.5, 0.3], [1.0, 1.0]], "blue": [[0.0, 0.2], [1.0, 1.0]]}
    payload = {"clips": [{
        "id": 1, "track": 0, "start": 0, "duration": SEC, "source": {"kind": "shape"},
        "video": {"curves": curves},
        "shape": {"kind": "rectangle", "width": 10, "height": 10}}]}
    pasted = doc.call("paste_attributes", clips=ids, payload=payload)
    carried = (doc.clip(clip).get("video") or {}).get("curves")
    check("P0 paste_attributes carries the payload's video.curves onto the clip",
          pasted["ok"] and carried == curves,
          f"paste {pasted.get('error', 'ok')}; target's curves {carried}")
    if pasted["ok"]:
        doc.call("undo")
    return close(client, doc.path)


# ---- projects A1–A3: the actions ---------------------------------------------

def static_frame(doc, ids, tag, curve):
    """The frame with master `curve` set, then the curve removed again."""
    got = doc.curves(ids, master=curve)
    frame = doc.frame(tag) if got["ok"] else None
    doc.uncurve(ids)
    return frame


def acted(doc, clip, end):
    """A 1 s action at 0 on `clip` whose end sets master to `end`; ok."""
    added = doc.call("add_action", clip=clip, at=0, duration=SEC)
    actions = doc.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=clip, action=action,
                     patch={"video": {"curves": {"master": end}}}) if action else {"ok": False}
    return added["ok"] and ended["ok"], actions


def run_a(client, card, state):
    closed = True
    lo, hi = [[0, 0], [0.5, 0.4], [1, 1]], [[0, 0], [0.5, 0.8], [1, 1]]
    six, six5 = [[0, 0], [0.5, 0.6], [1, 1]], [[0, 0], [0.5, 0.65], [1, 1]]

    if "A1" in selected:
        doc, clip, base, _ = card_doc(client, "A1", card)
        state["a1_fixture"] = base is not None
        ids = [clip]
        want = static_frame(doc, ids, "a1-static", six) if base else None
        set_base = doc.curves(ids, master=lo) if base else {"ok": False}
        made, _ = acted(doc, clip, hi) if base else (False, [])
        mid = doc.frame("a1-mid", t=SEC // 2)
        misses = grid_misses(mid, lambda x, y: want.px(x, y)) if want else ["no static frame"]
        check("A1 base master middle 0.4, a 1 s action to 0.8: at 0.5 s the frame equals the "
              "static 0.6 curve's, ±1", set_base["ok"] and made and not misses
              and not same_pixels(want, base), "; ".join(misses[:3]) or "all within")
        closed = close(client, doc.path) and closed

    if "A2" in selected:
        doc, clip, base, _ = card_doc(client, "A2", card)
        state["a2_fixture"] = base is not None
        ids = [clip]
        want = static_frame(doc, ids, "a2-static", six5) if base else None
        made, _ = acted(doc, clip, hi) if base else (False, [])
        mid = doc.frame("a2-mid", t=SEC // 2)
        misses = grid_misses(mid, lambda x, y: want.px(x, y)) if want else ["no static frame"]
        check("A2 no curve, a 1 s action to master middle 0.8: at 0.5 s the frame equals the "
              "static 0.65 curve's (the identity aligned to the end's x's), ±1",
              made and not misses and not same_pixels(want, base),
              "; ".join(misses[:3]) or "all within")
        closed = close(client, doc.path) and closed

    if "A3" in selected:
        doc, clip, base, _ = card_doc(client, "A3", card)
        state["a3_fixture"] = base is not None
        ids = [clip]
        want = static_frame(doc, ids, "a3-static", six5) if base else None
        set_base = doc.curves(ids, master=hi) if base else {"ok": False}
        made, _ = acted(doc, clip, [[0, 0], [1, 1]]) if base else (False, [])
        actions = doc.clip(clip).get("actions") or [{}]
        end = (((actions[0].get("end") or {}).get("video") or {}).get("curves") or {})
        kept = end.get("master") == [[0, 0], [1, 1]]
        mid = doc.frame("a3-mid", t=SEC // 2)
        after = doc.frame("a3-after", t=SEC + SEC // 2)
        misses = grid_misses(mid, lambda x, y: want.px(x, y)) if want else ["no static frame"]
        check("A3 base master middle 0.8, an end of [[0,0],[1,1]]: the end keeps the key, at "
              "0.5 s the frame equals the static 0.65 curve's ±1, and at 1.5 s it is the "
              "uncurved bytes", set_base["ok"] and made and kept and not misses
              and same_pixels(after, base),
              f"end {end}; {misses[:3] or 'mid within'}; after uncurved "
              f"{same_pixels(after, base)}")
        closed = close(client, doc.path) and closed
    return closed


# ---- project R: the ramp over the deep clip ------------------------------------

def run_r(client, ramp, deep, neutral, state):
    doc, sized = opened(client, "R", RAMP_W, RAMP_H)
    back = (doc.tracks() or [{}])[0].get("id")
    deep_media = doc.media(deep)
    under = doc.place(back, deep_media) if deep_media is not None else None
    front = doc.new_track() if under is not None else None
    media = doc.media(ramp)
    clip = doc.place(front, media) if media is not None and front is not None else None
    base = neutral.take(doc, "ramp")
    y = RAMP_H // 2
    black, white = 1, RAMP_W - 2
    deep_png = base is not None and png_depth(base.path) == 16
    fixture = (sized and clip is not None and base is not None and deep_png
               and base.px(black, y) == (0, 0, 0) and base.px(white, y) == (255, 255, 255))
    ids = [clip]
    looked = doc.call("set_video", clips=ids, patch={"look": {"kind": "warm"}}) \
        if fixture else {"ok": False}
    neutral.take(doc, "ramp-looked") if looked["ok"] else None
    doc.call("set_video", clips=ids, patch={"look": None})
    k1_curve = doc.curves(ids, master=[[0, 0], [64 / 255, 40 / 255], [192 / 255, 215 / 255],
                                       [1, 1]]) if fixture else {"ok": False}
    neutral.take(doc, "ramp-curved") if k1_curve["ok"] else None
    doc.uncurve(ids)
    fixture = fixture and looked["ok"] and k1_curve["ok"]
    state["r_fixture"] = fixture
    print(f"  R: ramp clip {clip} over deep clip {under}; the frame's PNG depth "
          f"{png_depth(base.path) if base else None}", flush=True)
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    def written(x):
        """The ramp's own code at column x, as `fixtures` wrote it."""
        return round(255 * x / (RAMP_W - 1))

    columns = {}
    for x in range(RAMP_W):
        columns.setdefault(written(x), x)

    # K1
    points = [[0, 0], [64 / 255, 40 / 255], [192 / 255, 215 / 255], [1, 1]]
    hit = doc.curves(ids, master=points)
    k1 = doc.frame("k1")
    doc.uncurve(ids)
    misses, levels = [], []
    for v, out in ((0, 0), (64, 40), (192, 215), (255, 255)):
        x = columns.get(v)
        if x is None or k1 is None:
            misses.append(f"v {v}: no column or no frame")
            continue
        got8, got16 = k1.px8(x, y), k1.px16(x, y)
        level = abs(got16[0] / 65535 - out / 255) * 1023
        levels.append(f"{v}→{level:.3f}")
        if not close_to(got8, (out,) * 3) or level > 1 or len(set(got16)) != 1:
            misses.append(f"v {v} (x {x}): {got8} / {got16}, {level:.3f} of a 10-bit level "
                          f"from {out}")
    check("K1 master through (64, 40) and (192, 215) hits each point and both ends: ±1 at 8 "
          "bits, within one 10-bit level at 16 bits", hit["ok"] and not misses,
          f"set {hit.get('error', 'ok')}; {misses or 'all within'}; 10-bit levels off "
          f"{', '.join(levels)}")

    # K3
    steep = [[0, 0.2], [0.45, 0.25], [0.5, 0.9], [1, 1]]
    set_steep = doc.curves(ids, master=steep)
    k3 = doc.frame("k3")
    doc.uncurve(ids)
    worst, where, peak = 0, None, 0
    if k3 is not None:
        for x in range(RAMP_W):
            value = k3.px16(x, y)[0]
            if peak - value > worst:
                worst, where = peak - value, x
            peak = max(peak, value)
    check("K3 a steep curve never falls along the ramp (16 bits, below its running maximum "
          f"by at most 1): worst fall {worst} at column {where}",
          set_steep["ok"] and k3 is not None and worst <= 1,
          f"set {set_steep.get('error', 'ok')}")

    # C1
    red = [[0, 0], [0.5, 0.7], [1, 1]]
    set_red = doc.curves(ids, red=red)
    c1 = doc.frame("c1")
    doc.uncurve(ids)
    r_misses, gb_misses = [], []
    if c1 is not None:
        for x in range(RAMP_W):
            v16 = base.px16(x, y)
            got16 = c1.px16(x, y)
            tolerance = max(1, math.ceil(half_step(v16[1] / 65535)))
            for c in (1, 2):
                if abs(got16[c] - v16[c]) > tolerance:
                    gb_misses.append(f"x {x} c{c}: {got16[c]} vs {v16[c]} (±{tolerance})")
            if x % 16 == 0:
                v = written(x)
                want = code(fc(red, v / 255))
                if abs(c1.px8(x, y)[0] - want) > 1:
                    r_misses.append(f"x {x}: v {v} → R {c1.px8(x, y)[0]} vs {want}")
    check("C1 red [[0,0],[0.5,0.7],[1,1]]: R follows the oracle ±1 at every 16th column; G "
          "and B within max(1, one half-float step at v) 16-bit levels of the uncurved frame",
          set_red["ok"] and c1 is not None and not r_misses and not gb_misses,
          f"set {set_red.get('error', 'ok')}; R {r_misses[:3] or 'all within'}; G/B "
          f"{len(gb_misses)} off: {gb_misses[:3]}")
    return close(client, doc.path)


# ---- projects H: the hue curves (T4-2, spec §11 GR-32) -------------------------

HUE_CURVES = ["hue_hue", "hue_sat"]
S1 = [[0, 0], [60, 0], [120, 40], [180, 0]]
G2 = [[0, 1], [60, 1], [120, 0], [180, 1]]


def hue_doc(client, name, picture, width=HUE_W, height=HUE_H):
    """A new project showing `picture`; (Doc, clip, its uncurved frame)."""
    doc, sized = opened(client, name, width, height)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(picture)
    clip = doc.place(track, media) if media is not None else None
    base = doc.frame(f"{name}-base") if clip is not None else None
    return doc, clip, (base if sized and clip is not None else None)


def curved(doc, ids, tag, **channels):
    """The frame with `channels` set, then every curve removed; (ok, Frame)."""
    got = doc.curves(ids, **channels)
    frame = doc.frame(tag) if got["ok"] else None
    doc.curves(ids, **{c: None for c in CHANNELS + HUE_CURVES})
    if not got["ok"]:
        print(f"       set {tag}: {got.get('error')}", flush=True)
    return got["ok"], frame


def column_misses(frame, want_of, columns=range(HUE_W), tolerance=1):
    """Each HUE column's middle-row pixel of `frame` against `want_of(x)`."""
    if frame is None:
        return ["the frame is missing"]
    y = HUE_H // 2
    return [f"x {x} (hue {x / 2}): {frame.px(x, y)} vs {want_of(x)}" for x in columns
            if not close_to(frame.px(x, y), want_of(x), tolerance)]


def run_h(client, state):
    hue = write_rgb_png(WORK / "hue.png", HUE_W, HUE_H, hue_column)
    grey = write_png(WORK / "grey-ramp.png", HUE_W, HUE_H, lambda x: round(255 * x / (HUE_W - 1)))
    tinted = write_rgb_png(WORK / "tinted.png", HUE_W, HUE_H, lambda x: (130, 128, 128))
    rose = write_rgb_png(WORK / "rose.png", HUE_W, HUE_H, lambda x: (153, 102, 102))
    closed = True
    y = HUE_H // 2
    doc, clip, base = hue_doc(client, "H", hue)
    fixture = base is not None and all(close_to(base.px(x, y), hue_column(x))
                                       for x in range(HUE_W))
    state["h_fixture"] = fixture
    print(f"  H: HUE clip {clip}; the uncurved columns hold HSV(x/2, 1, 1) ±1: {fixture}",
          flush=True)
    if not fixture:
        return close(client, doc.path) and False
    ids = [clip]
    plain = [base.px(x, y) for x in range(HUE_W)]

    # H1, H2
    if "H1" in selected:
        ok, frame = curved(doc, ids, "h1", hue_hue=S1)
        strip = HueStrip(S1, GAIN_IDENTITY)
        untouched = [x for x in range(HUE_W) if x / 2 <= 55 or x / 2 >= 185]
        moved = [x for x in range(HUE_W) if 55 < x / 2 < 185]
        stray = [x for x in untouched if frame is None or frame.px(x, y) != plain[x]]
        misses = column_misses(frame, lambda x: hue_codes(plain[x], strip), moved)
        check(f"H1 hue_hue {S1}: the {len(untouched)} columns at hue ≤ 55° or ≥ 185° are the "
              f"uncurved bytes, the {len(moved)} between are the oracle ±1",
              ok and not stray and not misses,
              f"changed outside {stray[:5]}; {misses[:3] or 'all within'}")
    if "H2" in selected:
        ok, frame = curved(doc, ids, "h2", hue_sat=G2)
        strip = HueStrip(SHIFT_IDENTITY, G2)
        untouched = [x for x in range(HUE_W) if x / 2 <= 55 or x / 2 >= 185]
        moved = [x for x in range(HUE_W) if 55 < x / 2 < 185]
        stray = [x for x in untouched if frame is None or frame.px(x, y) != plain[x]]
        misses = column_misses(frame, lambda x: hue_codes(plain[x], strip), moved)
        green = frame.px(240, y) if frame else None
        grey_at_120 = green is not None and max(green) - min(green) <= 1
        check(f"H2 hue_sat {G2}: the columns at hue ≤ 55° or ≥ 185° are the uncurved bytes, "
              f"the rest the oracle ±1, and hue 120 is grey ({green})",
              ok and not stray and not misses and grey_at_120,
              f"changed outside {stray[:5]}; {misses[:3] or 'all within'}")

    # H4
    if "H4" in selected:
        wrap = [[10, 40], [180, 0], [350, -20]]
        ok, frame = curved(doc, ids, "h4", hue_hue=wrap)
        strip = HueStrip(wrap, GAIN_IDENTITY)
        columns = [0, 10, 710]
        values = {x: round(fc_periodic(wrap, x / 2, -180, 180), 3) for x in columns}
        misses = column_misses(frame, lambda x: hue_codes(plain[x], strip), columns)
        check(f"H4 the wrap {wrap}: hue 0°, 5° and 355° follow the periodic oracle ±1 (its "
              f"shifts there {values[0]}°, {values[10]}°, {values[710]}°)",
              ok and not misses and abs(values[0] - 10) < 1e-9,
              f"{misses or 'all within'}; got {[frame.px(x, y) if frame else None for x in columns]}")

    # H6
    if "H6" in selected:
        ok, direct = curved(doc, ids, "h6-direct", hue_hue=S1, hue_sat=G2)
        front = doc.new_track()
        adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
            if front is not None else None
        set_adjust = doc.curves([adjustment], hue_hue=S1, hue_sat=G2) if adjustment \
            else {"ok": False}
        adjusted = doc.frame("h6-adjusted") if set_adjust["ok"] else None
        if front is not None:
            doc.call("remove_track", track=front, with_clips=True)
        misses = column_misses(adjusted, lambda x: direct.px(x, y)) if direct \
            else ["no direct frame"]
        differs = direct is not None and any(direct.px(x, y) != plain[x] for x in range(HUE_W))
        check("H6 an adjustment clip with H1's and H2's curves over HUE renders the clip "
              "curved directly, ±1 at every column", ok and set_adjust["ok"] and not misses
              and differs, f"adjustment {set_adjust.get('error', 'ok')}; "
              f"{misses[:3] or 'all within'}; differs {differs}")

    # H7
    if "H7" in selected:
        before = doc.project()
        seventeen = [[i * 20, 10] for i in range(17)]
        cases = [
            ({"hue_hue": seventeen}, "video.curves.hue_hue needs 2 to 16 points, not 17"),
            ({"hue_hue": [[0, 0], [100, 10], [360, 0]]},
             "video.curves.hue_hue[2].x must be at least 0 and below 360, not 360"),
            ({"hue_hue": [[0, 0], [100, 200]]},
             "video.curves.hue_hue[1].y must be between -180 and 180, not 200"),
            ({"hue_sat": [[0, 2.5], [100, 1]]},
             "video.curves.hue_sat[0].y must be between 0 and 2, not 2.5"),
            ({"hue_hue": [[0, 0], [120, 10], [90, 5]]},
             "video.curves.hue_hue[2].x (90) must be greater than video.curves.hue_hue[1].x "
             "(120)"),
        ]
        answers = [doc.curves(ids, **patch) for patch, _ in cases]
        for got in answers:
            if got["ok"]:
                doc.call("undo")
        unchanged = doc.project() == before
        identity = doc.curves(ids, hue_hue=[[10, 0], [200, 0]], hue_sat=[[0, 1], [300, 1]])
        if identity["ok"]:
            doc.call("undo")
        refused = all(not got["ok"] and want in got.get("error", "")
                      for got, (_, want) in zip(answers, cases))
        check("H7 the five hue refusals by their sentences, the project unchanged, and an "
              "identity hue patch \"made no change\"",
              refused and unchanged and not identity["ok"]
              and "made no change" in identity.get("error", ""),
              "; ".join(repr(got.get("error") or "accepted") for got in answers)
              + f"; unchanged {unchanged}; identity {identity.get('error') or 'accepted'}")

    # H9
    if "H9" in selected:
        pushed = doc.curves(ids, hue_hue=S1, hue_sat=G2)
        graded = doc.frame("h9-plain")
        ungraded = doc.frame("h9-ungraded", ungraded=True)
        doc.curves(ids, **{c: None for c in HUE_CURVES})
        check("H9 render_frame {ungraded: true} with both hue curves set is the uncurved bytes, "
              "and the plain frame is not", pushed["ok"] and same_pixels(ungraded, base)
              and graded is not None and not same_pixels(graded, base),
              f"set {pushed.get('error', 'ok')}; ungraded {same_pixels(ungraded, base)}")

    # H13
    if "H13" in selected:
        shift, gain = [[0, 60], [180, 60]], [[0, 1], [30, 1], [60, 0], [90, 1]]
        ok, frame = curved(doc, ids, "h13", hue_hue=shift, hue_sat=gain)
        want = hue_codes(plain[0], HueStrip(shift, gain))
        got = frame.px(0, y) if frame else None
        check(f"H13 hue_hue +60 with hue_sat 0 at 60°: the red column is the oracle with the "
              f"gain read at its own hue 0° (want {want}, got {got}; not grey)",
              ok and got is not None and close_to(got, want) and max(got) - min(got) > 32)

    # H14
    if "H14" in selected:
        red = [[0, 0], [1, 0]]
        ok, frame = curved(doc, ids, "h14", red=red, hue_sat=G2)
        tone = [lambda v: fc(red, v), lambda v: v, lambda v: v]
        want = hue_codes(plain[120], HueStrip(SHIFT_IDENTITY, G2), tone)
        got = frame.px(120, y) if frame else None
        check(f"H14 red [[0,0],[1,0]] then hue_sat 0 at 120°: the yellow column turns green "
              f"first and so grey (want {want}, got {got})",
              ok and got is not None and close_to(got, want) and max(got) - min(got) <= 1)

    # H15, then H12 over its frames
    turned = {}
    if selected & {"H15", "H12"}:
        for value in (40, -40):
            ok, frame = curved(doc, ids, f"h15{value:+d}", hue_hue=[[0, value], [180, value]])
            turned[value] = frame if ok else None
    if "H15" in selected:
        rows_ok, notes = True, []
        for value, frame in turned.items():
            if frame is None:
                rows_ok = False
                notes.append(f"{value:+d}: no frame")
                continue
            worst_strong, worst_all, strong = 0.0, 0.0, 0
            for x in range(HUE_W):
                out = frame.px(x, y)
                error = abs(signed_hue_change(plain[x], out) - value)
                worst_all = max(worst_all, error)
                if max(out) - min(out) >= 64:
                    strong += 1
                    worst_strong = max(worst_strong, error)
            green = colorsys.rgb_to_hsv(*[v / 255 for v in frame.px(240, y)])[0] * 360
            lands = 120 < green <= 180 if value > 0 else 80 <= green < 120
            rows_ok = rows_ok and worst_strong <= 1 and worst_all <= 2 and lands
            notes.append(f"{value:+d}: worst {worst_strong:.3f}° over {strong} columns at "
                         f"output chroma ≥ 64, {worst_all:.3f}° over all {HUE_W}; green → "
                         f"{green:.2f}°")
        check("H15 hue_hue ±40 on HUE, hues by colorsys: every column's signed HSV-hue change "
              "is the value ±1° at output chroma ≥ 64 and ±2° everywhere; green lands in "
              "(120°, 180°] under +40 and [80°, 120°) under −40", rows_ok, "; ".join(notes))
    if "H12" in selected:
        rose_doc, rose_clip, rose_base = hue_doc(client, "H12", rose)
        ok, rose_frame = curved(rose_doc, [rose_clip], "h12", hue_hue=[[0, 90], [180, 90]]) \
            if rose_base is not None else (False, None)
        closed = close(client, rose_doc.path) and closed
        cy = HUE_H // 2
        rose_in = luma(rose_base.px(360, cy)) if rose_base else None
        rose_out = luma(rose_frame.px(360, cy)) if rose_frame else None
        rose_hue = signed_hue_change(rose_base.px(360, cy), rose_frame.px(360, cy)) \
            if rose_base and rose_frame else None
        worst = 0.0
        for frame in turned.values():
            if frame is None:
                worst = float("inf")
                continue
            for x in range(HUE_W):
                worst = max(worst, abs(luma(frame.px(x, y)) - luma(plain[x])))
        rose_kept = rose_in is not None and rose_out is not None and abs(rose_out - rose_in) <= 1
        check(f"H12 Rec. 709 luma kept ±1: the (153,102,102) card under +90° ({rose_in} → "
              f"{rose_out}, hue {rose_hue}°) and every HUE column under ±40° (worst "
              f"{worst:.3f} levels)", ok and rose_kept and worst <= 1)

    # H16 (a record)
    if "H16" in selected:
        tinted_hue = doc.color(ids, hue=40)
        frame = doc.frame("h16") if tinted_hue["ok"] else None
        doc.color(ids, hue=0)
        notes = []
        for x in (0, 240):
            if frame is None:
                break
            change = signed_hue_change(plain[x], frame.px(x, y))
            direction = "with" if change > 0 else "against"
            notes.append(f"the {x / 2:.0f}° column moves {change:+.2f}° ({direction} the "
                         f"label's +40)")
        check("H16 RECORD Color's Hue +40 on HUE (no curves): " + "; ".join(notes or ["no frame"]),
              frame is not None)
    closed = close(client, doc.path) and closed

    # H3, on its own two projects
    if "H3" in selected:
        results = []
        for name, picture in (("H3-grey", grey), ("H3-tinted", tinted)):
            g_doc, g_clip, g_base = hue_doc(client, name, picture)
            ok, frame = curved(g_doc, [g_clip], name, hue_hue=[[0, 90], [180, 90]],
                               hue_sat=[[0, 0], [180, 0]]) if g_base is not None \
                else (False, None)
            results.append((name, ok and same_pixels(frame, g_base)))
            closed = close(client, g_doc.path) and closed
        check("H3 the grey ramp and a (130,128,128) card under hue_hue +90 and hue_sat 0 are "
              "byte-identical (the chroma guard)", all(good for _, good in results),
              f"{results}")

    # H8, on its own two projects
    if "H8" in selected:
        results = []
        a_doc, a_clip, a_base = hue_doc(client, "H8a", hue)
        if a_base is not None:
            ok, want = curved(a_doc, [a_clip], "h8a-static",
                              hue_hue=[[0, 0], [60, 0], [120, 60], [180, 0]])
            a_doc.curves([a_clip], hue_hue=S1)
            made = acted_on(a_doc, a_clip, {"hue_hue": [[0, 0], [60, 0], [120, 80], [180, 0]]})
            mid = a_doc.frame("h8a-mid", t=SEC // 2)
            misses = column_misses(mid, lambda x: want.px(x, y)) if want else ["no static"]
            results.append(("same count", ok and made and not misses, misses[:3]))
        closed = close(client, a_doc.path) and closed
        b_doc, b_clip, b_base = hue_doc(client, "H8b", hue)
        if b_base is not None:
            ok, want = curved(b_doc, [b_clip], "h8b-static",
                              hue_sat=[[0, 1], [60, 1], [120, 0.5], [180, 1]])
            made = acted_on(b_doc, b_clip, {"hue_sat": G2})
            mid = b_doc.frame("h8b-mid", t=SEC // 2)
            misses = column_misses(mid, lambda x: want.px(x, y)) if want else ["no static"]
            results.append(("from none", ok and made and not misses, misses[:3]))
        closed = close(client, b_doc.path) and closed
        check("H8 a same-count hue action at 0.5 s is the static middle curve ±1, and an "
              "action from no curve to H2's is the half curve ±1",
              len(results) == 2 and all(good for _, good, _ in results), f"{results}")
    return closed


def acted_on(doc, clip, curves):
    """A 1 s action at 0 on `clip` whose end sets `curves`; ok."""
    added = doc.call("add_action", clip=clip, at=0, duration=SEC)
    actions = doc.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=clip, action=action,
                     patch={"video": {"curves": curves}}) if action else {"ok": False}
    return added["ok"] and ended["ok"]


# ---- project M: the movie and an export --------------------------------------

def decoded(movie, n):
    """Frame `n` of `movie` as RGBA bytes at the card size; (None, why)."""
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{n})",
             "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo", "-pix_fmt",
             "rgba", "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"ffmpeg: {error}"
    return (raw, n) if len(raw) == CARD_W * CARD_H * 4 else (None, "no frame decoded")


def run_m(client, movie, neutral, state):
    doc, sized = opened(client, "M", CARD_W, CARD_H, background=[0, 0, 0, 1])
    a_track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(movie)
    clip = doc.place(a_track, media) if media is not None else None
    base = neutral.take(doc, "movie")
    fixture = sized and clip is not None and base is not None
    x1_curves = doc.curves([clip], master=[[0, 0], [0.25, 0.1], [0.75, 0.9], [1, 1]],
                           red=[[0, 0], [0.5, 0.7], [1, 1]]) if fixture else {"ok": False}
    neutral.take(doc, "movie-curved") if x1_curves["ok"] else None
    doc.uncurve([clip])
    fixture = fixture and x1_curves["ok"]
    state["m_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # X1
    up = doc.curves([clip], master=[[0, 0], [0.25, 0.1], [0.75, 0.9], [1, 1]],
                    red=[[0, 0], [0.5, 0.7], [1, 1]])
    x1 = doc.frame("x1")
    out = WORK / "X1.mov"
    exported = doc.call("export", preset="prores_422", path=str(out), size="document")
    raw, which = decoded(out, 15) if exported["ok"] and out.exists() else (None, "no file")
    samples = [(x, y) for y in range(0, CARD_H, 16) for x in range(0, CARD_W, 16)]
    misses = []
    if raw is not None and x1 is not None:
        exported_frame = Frame(out, raw, CARD_W, CARD_H)
        misses = [(x, y, exported_frame.px(x, y), x1.px(x, y)) for x, y in samples
                  if not close_to(exported_frame.px(x, y), x1.px(x, y), 8)]
    differs = x1 is not None and max(
        max(abs(a - b) for a, b in zip(x1.px(x, y), base.px(x, y))) for x, y in samples) > 30
    check(f"X1 the prores_422 export's frame {which} is within ±8 of render_frame at "
          f"{len(samples)} samples, and the curved frame differs from the uncurved by > 30",
          up["ok"] and exported["ok"] and raw is not None and x1 is not None and not misses
          and differs,
          f"set {up.get('error', 'ok')}; export {exported.get('error', 'ok')}; "
          f"{misses[:3] or 'all within'}; differs {differs}")
    return close(client, doc.path)


# ---- project S: what a save writes (N2) --------------------------------------

def saved_curves(path, clip):
    """The package's `version`, `clip`'s `video.curves` (None when absent) and
    the file's text."""
    text = (Path(path) / "project.json").read_text()
    body = json.loads(text)
    found = next((c for c in body.get("clips", []) if c.get("id") == clip), {})
    return body.get("version"), (found.get("video") or {}).get("curves"), text


def run_s(client, card, state):
    doc, sized = opened(client, "S", CARD_W, CARD_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    clip = doc.place(track, media) if media is not None else None
    state["s_fixture"] = sized and clip is not None
    plain_path = WORK / "S-plain.framejob"
    saved = doc.call("save_project", path=str(plain_path))
    doc.path = plain_path
    try:
        plain_version, _, plain_text = saved_curves(plain_path, clip)
    except (OSError, ValueError):
        plain_version, plain_text = None, "unreadable"
    red = [[0, 0], [0.5, 0.7], [1, 1]]
    doc.curves([clip], red=red)
    curved_path = WORK / "S-curved.framejob"
    resaved = doc.call("save_project", path=str(curved_path))
    doc.path = curved_path
    try:
        curved_version, curved, _ = saved_curves(curved_path, clip)
    except (OSError, ValueError):
        curved_version, curved = None, None
    stray = '"curves"' in plain_text
    version = format_version()
    check(f"N2 an uncurved save holds no `curves`; with a red curve the clip's curves are "
          f"exactly {{\"red\": {red}}}; both at version {version} (the header's)",
          saved["ok"] and resaved["ok"] and not stray and curved == {"red": red}
          and plain_version == version and curved_version == version,
          f"uncurved has curves {stray}, version {plain_version}; curved {curved}, version "
          f"{curved_version}")
    return close(client, doc.path)


# ---- project P and the probe -------------------------------------------------

def run_p(client, card, state):
    """Two card clips on two tracks with master middles 0.6 and 0.4, saved for
    the probe; (the package's path, the clip ids), or (None, None)."""
    doc, sized = opened(client, "P", CARD_W, CARD_H)
    a_track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(card)
    a = doc.place(a_track, media) if media is not None else None
    b_track = doc.new_track()
    b = doc.place(b_track, media) if media is not None else None
    ok = sized and a is not None and b is not None
    ok = ok and doc.curves([a], master=[[0, 0], [0.5, 0.6], [1, 1]])["ok"] \
        and doc.curves([b], master=[[0, 0], [0.5, 0.4], [1, 1]])["ok"]
    path = WORK / "P-saved.framejob"
    ok = ok and doc.call("save_project", path=str(path))["ok"]
    doc.path = path
    closed = close(client, doc.path)
    state["p_fixture"] = ok
    return (path, [a, b]) if ok and closed else (None, None)


def run_probe(sources, package, clips):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "curves_probe",
                                  defines=["FRAMEJOB_DEV_TOOLS"], timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        for name in sorted(P_ROWS):
            check(f"{name} the probe builds over app/Sources", False,
                  f"{error} {error.diagnostics[:6]}")
        return
    request, answer = folder / "request.json", folder / "answer.json"
    if answer.exists():
        answer.unlink()
    # The oracle's 200 seeded curves for P6, and its values at 64 inputs each.
    oracle = []
    seed = 0x5eed_c0de
    for _ in range(200):
        seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
        count = 2 + seed % 15
        xs, ys = [0.0], []
        for _ in range(count - 1):
            seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
            xs.append(xs[-1] + 0.01 + (seed >> 11) / 2 ** 53)
        for _ in range(count):
            seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
            ys.append((seed >> 11) / 2 ** 53)
        span = xs[-1]
        points = [[x / span, y] for x, y in zip(xs, ys)]
        inputs = [i / 63 for i in range(64)]
        oracle.append({"points": points, "inputs": inputs,
                       "values": [fc(points, x) for x in inputs]})
    # P12's: 200 seeded hue curves in each domain, the periodic oracle's
    # values at 64 hues each.
    hue_oracle = []
    for domain, low, high in (("hue_shift", -180.0, 180.0), ("hue_gain", 0.0, 2.0)):
        for _ in range(200):
            seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
            count = 2 + seed % 15
            xs, ys = [], []
            for _ in range(count):
                seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
                xs.append(0.5 + (seed >> 11) / 2 ** 53)
            for _ in range(count):
                seed = (seed * 6364136223846793005 + 1442695040888963407) % 2 ** 64
                ys.append(low + (high - low) * (seed >> 11) / 2 ** 53)
            total = sum(xs) * (1 + 0.02 * (seed % 7))
            at, points = 0.0, []
            for step, y in zip(xs, ys):
                points.append([359.0 * at / total, y])
                at += step
            inputs = [i * 360 / 64 + 0.37 for i in range(64)] + [0.0, 359.95]
            hue_oracle.append({"domain": domain, "points": points, "inputs": inputs,
                               "values": [fc_periodic(points, x, low, high) for x in inputs]})
    request.write_text(json.dumps({"package": str(package), "clips": clips, "oracle": oracle,
                                   "hue_oracle": hue_oracle}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(P_ROWS, key=lambda n: int(n[1:])):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
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
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "curves",
                       "--test", "ungraded"], 900, cwd=str(copy / "core"))
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
        print(f"grading-2 G2-3 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
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
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test curves "
                  "--test ungraded in the copy's core\n       " + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print(f"grading-2 G2-3 — curves over MCP ({args.mode or 'run'}, {config} build "
              f"{binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    card, ramp, movie, deep, deep_why = fixtures()
    if movie is None or deep is None:
        print("instrument failure: ffmpeg did not make the testsrc2 or the deep movie"
              + (f": {deep_why}" if deep is None else ""))
        return 2
    neutral = Neutral(args.mode, folder)
    log = WORK / "instance.log"
    state = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed, package, clips = True, None, None
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            capture = args.mode == "capture"
            if capture or "N0" in selected or selected & C_ROWS:
                closed = run_c(launched.client, card, neutral, state) and closed
            if capture or "N0" in selected or selected & R_ROWS:
                closed = run_r(launched.client, ramp, deep, neutral, state) and closed
            if capture or "N0" in selected or selected & M_ROWS:
                closed = run_m(launched.client, movie, neutral, state) and closed
            if not capture and selected & A_ROWS:
                closed = run_a(launched.client, card, state) and closed
            if not capture and selected & H_ROWS:
                closed = run_h(launched.client, state) and closed
            if "N2" in selected:
                closed = run_s(launched.client, card, state) and closed
            if selected & P_ROWS:
                package, clips = run_p(launched.client, card, state)
                closed = closed and package is not None
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if selected & P_ROWS:
        if package is None:
            for name in sorted(selected & P_ROWS):
                check(f"{name} project P was made and saved", False)
        else:
            run_probe(sources, package, clips)
    if "N0" in selected:
        missing = [name for name in NEUTRAL if name not in neutral.seen]
        good = not neutral.misses and not missing
        title = (f"N0 the {len(NEUTRAL)} frames with no hue curve are byte-identical (16 bits a "
                 f"channel) to {args.folder}")
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
        print(f"captured {len(taken)} uncurved frames into {args.folder}: {taken}")
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
