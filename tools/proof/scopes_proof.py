#!/usr/bin/env python3
"""Road map "grading-2", phase G2-1 (spec §11 GR-10) — the scopes: the RGB
parade, the Rec. 709 vectorscope and the R′G′B′Y′ histogram beside the luma
waveform, View ▸ Scopes' two slots, and `render_frame {parade, vectorscope,
histogram}`; road map "grading-4", phase T4-1 (GR-26, GR-31) — the
vectorscope's same-bin add, its zoom ×1/×2/×4 counted at the zoom, and
`render_frame {vectorscope_zoom}`.

    python3 tools/proof/scopes_proof.py [--app PATH] [--only S1,M1,...]
    python3 tools/proof/scopes_proof.py --mutant NAME
    python3 tools/proof/scopes_proof.py --central-ab [--rounds N] [--base REV]

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/scopes/home`, and
every package, fixture and PNG is under `tools/proof/work/scopes/`, removed at
the start and at exit. The only menu item performed is View ▸ Scopes, which
persists nothing (GR-5, GR-10); `DEFAULTS MOVED` from `mcp.py` stops the run.
Every call is bounded (`CALL_BOUND`), every ffmpeg too (120 s), every wait on
the panel too (`PANEL_WAIT`). The project is closed (`close_project`, discard).

Fixture, written by this script: BARS, a 640×360 PNG — the seven 75 % bars
(grey 191, yellow, cyan, green, magenta, red, blue) over its top three
quarters, the bottom quarter white (255) on the left half and black on the
right. Project S (640×360) holds it; frames are taken at t = 0.5 s.

**Probe rows** (`scopes_probe.swift`, built by `swift_build.build` over
`app/Sources`, a failed build a scored FAILURE of every probe row; its
kernels compiled from the tree's `Waveform.metal`):
- **S1**: 75 % R, G, B, Cy, Mg and Yl cards each land in ONE vectorscope bin,
  the one this script computes from the BT.709 matrix; the JSON's `targets`
  agree, and the skin line is 123.3° (±0.05).
- **S2**: a grey card, a grey ramp and a (128, 129, 128)/255 card land wholly
  in bin (128, 128) (the last: 255·Cb ≈ −0.385 and 255·Cr ≈ −0.454, so
  rounding gives 0 and flooring −1).
- **S3**: an R-only ramp's parade has its diagonal in R′ alone; G′ and B′ sit
  flat at level 0 — at 256 wide (counted globally) and at 1920, 1999 (a last
  group 7 px across) and 3840 wide (counted per band in threadgroup memory).
- **S4**: a 256-wide grey ramp's histogram is flat in all four planes.
- **S5**: on noise the histogram's Y′ plane equals the waveform's column sums
  and its readouts the waveform's; the parade marks fall at 0.5 % per channel.
- **S6**: every kind's counts total the pixels (×3, ×4) at ×1 on GR-26's six
  fixtures (GR-10's five and a flat (0.8, 0.1, 0.1) red), at sizes the
  threadgroup does not divide; at ×2 and ×4 the vectorscope against a CPU
  count of the same half floats: `off_plot` between its definite off-plot
  pixels and those plus its ties (within 1e-3 of the edges 127.5 and −128.5),
  occupied bins within ±1 both ways, the gradient crossing both zooms' edges.
- **S7**: latest wins with two kinds shown: both come back in each reading,
  the third frame's delivered once.
- **S8**: the tap's reading of a 64RGBAHalf buffer equals `analyze(image:
  kinds:)` of the same pixels, all four kinds.
- **S9**: Scopes on and off and picks in both slots write no defaults; the
  panel opens Waveform over Vectorscope; picks last across hide and show; a
  new controller restarts them; across 360 pt of pane both ways the shown and
  the tap's attached kinds follow (the top pick alone below), each flip asking
  for one frame.
- **S10**: `layout(picks:paneHeight:)` for every pick pair at 300, 359, 360,
  460, 570 and 1000: the bottom slot iff ≥ 360, bodies and chrome within the
  pane, preferred bodies when they fit, else one factor, a vectorscope side
  ≤ 224.
- **S11**: a near-grey card (every (128 ± 5)/255 channel combination): its Cb
  and Cr extents at ×2 and ×4 are 2× and 4× ×1's, ±1 bin.
- **S12**: 75 % red counts every pixel at ×1 and none at ×2, `off_plot` the
  pixels; at ×1 all four kinds' counts equal an analyser over the T4-0 tree's
  shader (`git show 31f3aa1:…/Waveform.metal`) on the six fixtures, the six
  75 % cards and pure red.
- **S14**: the panel's zoom: both slots ×1 on open; a zoom re-attaches that
  slot's pass and asks for one frame; vectorscope ×1 over ×4 is two passes,
  each slot showing its own zoom's trace; kept across hide and show and a pick
  away and back; no defaults key; a new controller ×1.
- **S15** (hdr H-4, spec §11 HD-15): with `signal: .hlg`, the six BT.2020
  75 % cards each land in ONE vectorscope bin, this script's BT.2020 bin
  (`Cb = (B′ − Y′)/1.8814`, `Cr = (R′ − Y′)/1.4746`), the HLG JSON's targets
  agree; nine colour cards' waveform and histogram Y′ levels are
  round(255·dot(rgb, BT.2020)); the parade's counts are the same at either
  signal. CONTROL: at least 4 cards whose Rec. 709 and BT.2020 levels part.
- **T1**: each scope's GPU time at 1080p and 4K on the six fixtures, through
  an IOSurface 64RGBAHalf wrap as the tap's, median of 10 after 2 warm-ups.
  Scored: the worst 4K figure of each of parade, histogram and the
  vectorscope at ×1, ×2 and ×4 ≤ 1.1 ms (GR-10, GR-26, GR-31), and (hdr H-4)
  the HLG signal's vectorscope at ×1, ×2 and ×4 and histogram. The waveform,
  the waveform + vectorscope pair and the HLG waveform are recorded, with
  `pmset -g`'s power lines.
- **T2**: the tree's parade against the same shader with its one
  `bool banded = ` line forced to `false` (every group adding globally),
  timed back to back on the five 4K fixtures as T1 times them. Scored: on the
  fixture where the forced-global parade is slowest (flat on the M2 Max), the
  banded time ≤ 0.75 × the global one, which says the banded path is the one
  running (T1 alone cannot: the global parade sits about T1's 1.1 ms). The
  other fixtures are recorded; banding gains nothing on them. A shader with no
  such line, or more than one, is a FAILURE, never a skip.
- **T3**: T2's shape for the vectorscope: the tree's ×1 pass against the same
  shader with its one `bool central = ` line forced to `false`, on the six 4K
  fixtures. Scored on near-grey by name, the fixture the central path is
  for: the tree's time ≤ 0.85 × the global one's (GR-26's same-bin add
  rescues the flat fixtures T1 used to catch a global vectorscope on). Not
  the slowest forced-global fixture: gradient sits 16 % behind near-grey
  there at a ratio about 0.9 (#296's A/B), so one loaded sample of it
  failed T3 whatever the path did. The other five are recorded.

**MCP rows** (project S):
- **M1**: `render_frame` with all four booleans: four sentences in
  `ScopeKind` order before "Written to", four JSON files, and the
  vectorscope's occupied bins agree (±1 bin) with this script's bins of the
  PNG's own pixels.
- **M2**: View ▸ Scopes shown, paused: the top slot's readouts (`snapshot_ui`,
  ids `scopes.top.highlights` / `scopes.top.shadows`) are within 0.2 points
  of the waveform JSON's percentages.
- **M3**: `render_frame {vectorscope: "yes"}` is refused, naming
  `vectorscope`.
- **M4**: `snapshot_ui`: a 248 pt panel; the pickers' parts read Waveform and
  Vectorscope; the bottom slot shows exactly when the pane is ≥ 360 pt; the
  vectorscope body is square, its side ≤ 224, centred in its slot.
- **S13**: `render_frame {vectorscope: true, vectorscope_zoom: 4}`: the JSON's
  `zoom` 4, its occupied bins within ±1 of this script's ×4 bins of the PNG,
  `off_plot` exactly this script's (the six coloured bars), every target null,
  the zoomed sentence; `vectorscope_zoom: 3`, and 2 without `vectorscope`,
  refused naming `vectorscope_zoom`.

**Harness rows** (not under `--mutant`: the harness builds the tree's own
sources), over project S saved:
- **H1**: four captures, top `k[i]` over bottom `k[i+1]` in `ScopeKind`
  order (wrapping), with the `ramp` traces, light and dark, each
  byte-identical twice.
- **H2**: every visible body holds ≥ 200 trace pixels (a channel ≥ 200; the
  waveform's and the parade's 24 pt label gutter left out).
- **H3**: at window heights giving a ≈ 460 pt and a ≥ 700 pt pane, and one
  below 360 (twice: the opening picks, and a vectorscope on top): the printed
  slot rects lie inside the panel, the bottom slot appears iff the pane is
  ≥ 360 pt, and a vectorscope is square and centred.
- **H4**: the top vectorscope at `topzoom=2` and `4` over the ramp traces,
  light and dark, each byte-identical twice and unlike the same look's ×1;
  the printed `seeing cells` rect (46 × 16) 4 pt in from the square's
  bottom-right corner.
- **Z1** (CONTROL): the fixture holds, the project closes and the log holds
  no `Frame Job: ` line.

`--mutant NAME`, one of the sixteen below, builds a COPY of the tree
(`tree_copy.make_copy`), applies its edits (each anchor asserted to occur
exactly once), builds it by the copy's own `make app-debug` (`make app` under
`RC_PROOF_APP=release`) and runs every row but H1–H4 on it, the probe built
over the copy's `app/Sources` and its shader. MUTANT PASS when every named
row FAILED and no other scored row did, but a row the mutant tolerates
(`TOLERATED`), which the MUTANT line names when it failed:
  cb-cr-swapped        the kernel puts Cr on the Cb axis: S1 M1
  bt601                the vectorscope's matrix is BT.601's: S1 M1
  bins-edged           the chroma bins floor instead of round: S1 S2
  vectorscope-global   every vectorscope pixel adds globally: T3 (T1 tolerated)
  histogram-global     every histogram pixel adds globally: T1
  histogram-luma-601   the histogram's Y′ takes BT.601's weights: S5
  pick-persisted       a pick is written to UserDefaults: S9
  tap-first-kind-only  the tap runs only the first shown pass: S7 S8 (S14
                       tolerated)
  slots-not-shrunk     the bodies stay at their preferred heights: S10
  parade-band-misplaced  the parade's merge puts both bands in the group's
                       first column: S3
  parade-global        every parade group adds globally: T2 (T1 tolerated: the
                       forced-global parade measured 1.15 ms at 4K on flat in
                       G2-5 (1.019–1.042 in G2-1), at or over T1's 1.1 ms)
  zoom-in-drawing-only the kernel bins every zoom at ×1: S11 S12 S13 (S6
                       tolerated)
  off-plot-clamped     an off-plot pixel is clamped to the edge: S6 S12 S13 (T1
                       tolerated)
  same-bin-add-dropped the same-bin add's branch is never taken: T1 (T3
                       tolerated)
  zoom-persisted       a slot's zoom is written to UserDefaults: S14
  render-ignores-zoom  `writeScopes` always gets zoom 1: S13
The mutants of the ×1 counting tolerate S12, which holds every ×1 count to
the T4-0 tree's shader. `TOLERATED` gives each tolerated row's reason.
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.

`--central-ab` (#296, spec §11 GR-26; neither `--mutant` nor `--only`, no app,
no MCP) builds the probe and times the ×1 vectorscope of three shaders on the
six 4K fixtures, each through T1's `gpuMedian` over T1's IOSurface wrap:
`base` (`git show REV:…/Waveform.metal`, `CENTRAL_BASE` the last tree with the
central path), `twin` (`base` with its one `bool central = ` line forced to
`false`, T3's twin; not exactly one such line is an instrument failure) and
`tree` (the tree's shader, the kernel a drop ships). Each of `--rounds`
(`CENTRAL_ROUNDS`) rounds times the three in `[base, tree, twin]` rotated left
by the round's index mod 3, so load falls on each alike. Per fixture and arm:
median m and spread s (the IQR of the rounds), min and max, and the paired
`tree − base`; S = max(s_base, s_tree). `tree` against `base` decides, the
twin's numbers and verdict are a record. One line, last: `STOP — spread too
wide` when any S > `CENTRAL_PRECISION` × the smaller median (exit 2); when tree
and base are the same text, the CONTROL — `CONTROL PASS` iff every |m_tree −
m_base| ≤ S, else `CONTROL FAILURE` (exit 2); else `VERDICT: KEEP (pays)` iff
near-grey's m_tree − m_base > S and no fixture's m_base − m_tree > S, else
`VERDICT: KEEP (worst fixture)` iff the worst m_tree > the worst m_base + S_W
(the two worst fixtures' S), else `VERDICT: DROP` (exit 0). The load averages
before and after, each fixture's, the GPU and `pmset`'s lines are printed.
"""

import argparse
import atexit
import json
import os
import re
import struct
import subprocess
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import e2_chrome as e2  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/scopes"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/scopes_probe.swift"
SHADER = "app/Resources/Shaders/Waveform.metal"
CALL_BOUND = 300
BUILD_BOUND = 1500
PANEL_WAIT = 20
SETTLE = 2
SEC = 600_000
T = SEC // 2
W, H = 640, 360
BOUND_MS = 1.1
RATIO_MAX = 0.75
# T3's own bound (orchestrator's ruling, 2026-10-15): under `vectorscope-global`
# the two builds are the same shader, so the mutant's ratio is 1.0 by
# construction (its noise is the only spread); the tree measured 0.706-0.796
# under heavy load, failing 0.75 one run in three. 0.85 sits between them with
# margin on both sides. Not moved again without a new measurement.
T3_RATIO_MAX = 0.85
KINDS = ["waveform", "parade", "vectorscope", "histogram"]
ROWS = ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11", "S12", "S13", "S14",
        "S15", "T1", "T2", "T3", "M1", "M2", "M3", "M4", "H1", "H2", "H3", "H4", "Z1"]
S_ROWS = {"S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11", "S12", "S14", "S15",
          "T1", "T2", "T3"}
M_ROWS = {"M1", "M2", "M3", "M4", "S13"}
H_ROWS = {"H1", "H2", "H3", "H4"}
SCOPES = ["View", "Scopes"]
ZOOMS = [1, 2, 4]
# The T4-0 tree, whose ×1 counts S12 holds the tree's to.
BASELINE = "31f3aa1"
# `--central-ab` (#296): the last tree with the vectorscope's central path,
# the rounds, and the precision every fixture's spread must reach.
CENTRAL_BASE = "c7c0dbf"
CENTRAL_ROUNDS = 60
CENTRAL_PRECISION = 0.10
CENTRAL_ANCHOR = "bool central = "
CENTRAL_FORCED = "            bool central = false;"
VECTOR = "    float2 c = float2((rgb.b - luma) / 1.8556, (rgb.r - luma) / 1.5748);\n"
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "cb-cr-swapped": ([(
        SHADER, VECTOR,
        "    float2 c = float2((rgb.r - luma) / 1.5748, (rgb.b - luma) / 1.8556);\n")],
        ["S1", "M1"]),
    "bt601": ([(
        SHADER, "    float luma = dot(rgb, kLumaWeights);\n" + VECTOR,
        "    float luma = dot(rgb, float3(0.299, 0.587, 0.114));\n"
        "    float2 c = float2((rgb.b - luma) / 1.772, (rgb.r - luma) / 1.402);\n")],
        ["S1", "M1"]),
    "bins-edged": ([(
        SHADER, "int2(round(255.0 * c))", "int2(floor(255.0 * c))")], ["S1", "S2"]),
    "vectorscope-global": ([(
        SHADER, "bool central = all(bins >= 96u) && all(bins < 160u);",
        "bool central = false;")], ["T3"]),
    "histogram-global": ([(
        SHADER, "atomic_fetch_add_explicit(&local[plane * 256u + levels[plane]], 1u,",
        "atomic_fetch_add_explicit(&counts[plane * 256u + levels[plane]], 1u,")], ["T1"]),
    "histogram-luma-601": ([(
        SHADER, "scopeLevel(dot(rgb, kLumaWeights)));",
        "scopeLevel(dot(rgb, float3(0.299, 0.587, 0.114))));")], ["S5"]),
    "pick-persisted": ([(
        "app/Sources/ScopesPanelView.swift", "        picks[slot] = kind\n",
        "        picks[slot] = kind\n"
        "        UserDefaults.standard.set(kind.rawValue, forKey: \"RCScopePick\\(slot)\")\n")],
        ["S9"]),
    "tap-first-kind-only": ([(
        # Re-pinned in hdr H-4: the tap's encode takes the frame's signal.
        "app/Sources/WaveformTap.swift",
        "analyzer.encode(passes, frame: texture, into: buffer, signal: signal)",
        "analyzer.encode(Set(ScopePass.ordered(passes).prefix(1)), "
        "frame: texture, into: buffer, signal: signal)")], ["S7", "S8"]),
    "slots-not-shrunk": ([(
        "app/Sources/ScopesPanelView.swift",
        "        let factor = total > 0 ? min(1, room / total) : 0\n",
        "        let factor: CGFloat = 1\n")], ["S10"]),
    "parade-band-misplaced": ([(
        SHADER, "(channel * 256u + first + band) * 256u", "(channel * 256u + first) * 256u")],
        ["S3"]),
    "parade-global": ([(
        SHADER, "bool banded = last - first < kParadeBands;", "bool banded = false;")],
        ["T2"]),
    "zoom-in-drawing-only": ([(
        SHADER, "chromaBins(saturate(float3(frame.read(gid).rgb)), zoom);",
        "chromaBins(saturate(float3(frame.read(gid).rgb)), 1u);")], ["S11", "S12", "S13"]),
    "off-plot-clamped": ([(
        SHADER, "    return int2(128) + int2(round(255.0 * float(zoom) * c));\n",
        "    return clamp(int2(128) + int2(round(255.0 * float(zoom) * c)), int2(0), int2(255));\n")],
        ["S6", "S12", "S13"]),
    "same-bin-add-dropped": ([(
        SHADER, "    if (simd_all(bin == lead)) {\n", "    if (false) {\n")], ["T1"]),
    "zoom-persisted": ([(
        "app/Sources/ScopesPanelView.swift", "        slots[slot].zoom = zoom\n",
        "        slots[slot].zoom = zoom\n"
        "        UserDefaults.standard.set(zoom, forKey: \"RCScopeZoom\\(slot)\")\n")],
        ["S14"]),
    "render-ignores-zoom": ([(
        # Re-pinned in hdr H-4: `writeScopes` takes the frame's signal.
        "app/Sources/AgentServer+Render.swift",
        "scopes, vectorscopeZoom: vectorscopeZoom, signal: signal, of: image, beside: url)",
        "scopes, vectorscopeZoom: 1, signal: signal, of: image, beside: url)")], ["S13"]),
}
# A row a mutant may fail BECAUSE of it, besides the rows it must fail, each
# with its reason.
TOLERATED = {
    # The forced-global parade measured 1.15 ms at 4K on flat in G2-5
    # (1.019–1.042 in G2-1), at or over T1's 1.1 ms.
    "parade-global": ["T1"],
    # Every vectorscope pixel adding globally is T1's 1.1 ms on the
    # near-grey and noise fixtures or under it, by the host's clock; T3 is
    # the row that holds it (GR-26's same-bin add rescues the flat ones).
    "vectorscope-global": ["T1"],
    # S6's zoomed half is the same off-plot count against a CPU count:
    # a kernel that bins every zoom at ×1 leaves nothing off the plot.
    "zoom-in-drawing-only": ["S6"],
    # Clamped to the edge, the ×4 gradient piles every off-plot pixel on
    # the rim's global bins: 1.67 ms in the brief's bench.
    "off-plot-clamped": ["T1"],
    # same-bin-add-dropped tolerates nothing since #296: T3 scores near-grey
    # by name (its bins are central), and the run of 2026-10-17 read it at
    # ratio 0.576 in the copy; the old slowest-fixture pick had made the flat
    # red (about 7.2 ms in tree and twin alike) T3's fixture.
    # S14's vectorscope ×1 over ×4 is two passes of one kind through the
    # same tap: the first pass alone leaves the bottom slot without a trace.
    "tap-first-kind-only": ["S14"],
    # S12(b) holds every ×1 count to the T4-0 tree's shader, so a mutant of
    # the ×1 counting fails it too; and S11 measures ×2 and ×4 against ×1's
    # extent, which flooring at ×1 alone narrows by a bin.
    "bins-edged": ["S11", "S12"],
    "cb-cr-swapped": ["S12"],
    "bt601": ["S12"],
    "histogram-luma-601": ["S12"],
    "parade-band-misplaced": ["S12"],
}
rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    mark = "  ok   " if good else "  FAIL "
    print(mark + name + (f"\n       {detail}" if detail else ""), flush=True)


def note(text):
    print(f"  rec   {text}", flush=True)


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


# ---- BT.709, computed here ----------------------------------------------------

def half_away(v):
    """round() as Metal and Swift's `.rounded()` do: halves away from zero."""
    return int(v + 0.5) if v >= 0 else -int(-v + 0.5)


def chroma(r, g, b):
    y = 0.2126 * r + 0.7152 * g + 0.0722 * b
    return (b - y) / 1.8556, (r - y) / 1.5748


def bin_of(c):
    return min(255, max(0, 128 + half_away(255 * c)))


# hdr H-4 (spec §11 HD-15 (e)): BT.2020's, for an HLG signal.
LUMA2020 = (0.2627, 0.6780, 0.0593)
LUMA709 = (0.2126, 0.7152, 0.0722)


def chroma2020(r, g, b):
    y = LUMA2020[0] * r + LUMA2020[1] * g + LUMA2020[2] * b
    return (b - y) / 1.8814, (r - y) / 1.4746


def luma_level(rgb, weights):
    return min(255, max(0, half_away(255 * sum(w * c for w, c in zip(weights, rgb)))))


def bins_of(r, g, b):
    cb, cr = chroma(r, g, b)
    return bin_of(cb), bin_of(cr)


def zoomed_bins_of(r, g, b, zoom):
    """GR-31's bins at `zoom` > 1: (cb, cr), or None off the plot."""
    raw = [128 + half_away(255 * zoom * c) for c in chroma(r, g, b)]
    return tuple(raw) if all(0 <= v <= 255 for v in raw) else None


# ---- pixels -------------------------------------------------------------------

BARS = [(191, 191, 191), (191, 191, 0), (0, 191, 191), (0, 191, 0), (191, 0, 191),
        (191, 0, 0), (0, 0, 191)]


def bar_pixel(x, y):
    if y >= H * 3 // 4:
        return (255, 255, 255) if x < W // 2 else (0, 0, 0)
    return BARS[min(len(BARS) - 1, x * len(BARS) // W)]


def write_png(path, width, height, rgb_of):
    """An 8-bit RGB PNG, untagged, whose pixel (x, y) is `rgb_of(x, y)`."""
    raw = b"".join(bytes([0]) + b"".join(bytes(rgb_of(x, y)) for x in range(width))
                   for y in range(height))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return path


def decode(path, width, height):
    """`path` as RGBA bytes through ffmpeg, or None; bounded."""
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-frames:v", "1",
                              "-f", "rawvideo", "-pix_fmt", "rgba", "-"], capture_output=True,
                             timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return None
    return raw if len(raw) == width * height * 4 else None


# ---- the document ---------------------------------------------------------------

class Doc:
    def __init__(self, client, path):
        self.client, self.path = client, path

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

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


def view(views, identifier=None, cls=None):
    return next((v for v in views if (identifier is None or v.get("id") == identifier)
                 and (cls is None or v.get("class") == cls)), None)


PERCENT = re.compile(r"clipped (\d+\.\d) %")


def readouts(views):
    """The top slot's two readouts as percentages, or None for "—"/absent."""
    found = []
    for identifier in ("scopes.top.highlights", "scopes.top.shadows"):
        v = view(views, identifier)
        m = PERCENT.search((v or {}).get("text") or "") if v and not v.get("hidden") else None
        found.append(float(m.group(1)) if m else None)
    return tuple(found)


def scope_json(png, kind):
    try:
        return json.loads(Path(f"{png}.{kind}.json").read_text())
    except (OSError, ValueError):
        return {}


def wait_readouts(doc, want):
    deadline = time.monotonic() + PANEL_WAIT
    shown, views, n = (None, None), [], 0
    while time.monotonic() < deadline:
        views = doc.preview(f"m2-{n}")
        n += 1
        shown = readouts(views)
        if None not in shown and (want is None or all(
                abs(a - b) <= 0.2 for a, b in zip(shown, want))):
            break
        time.sleep(0.5)
    return shown, views


def run_mcp(client, bars, state):
    path = WORK / "S.framejob"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    doc.call("set_canvas", width=W, height=H, fps=[30, 1])
    track = ((doc.project().get("tracks") or [{}])[0]).get("id")
    media = reply(doc.call("import_media", path=str(bars))).get("media")
    placed = doc.call("add_clip", track=track, media=media, at=0) if media else {"ok": False}
    canvas = doc.project().get("canvas") or {}
    fixture = (made["ok"] and placed["ok"] and canvas.get("width") == W
               and canvas.get("height") == H)
    state["s_fixture"] = fixture
    if not fixture:
        print(f"  S: made {made.get('error', 'ok')}, placed {placed.get('error', 'ok')}, "
              f"canvas {canvas}", flush=True)
        return attempt(client, "close_project", {"project": str(path), "discard": True})["ok"], None

    # M1
    png = WORK / "m1.png"
    got = doc.call("render_frame", t=T, path=str(png), **{k: True for k in KINDS})
    text = got["reply"] if got["ok"] and isinstance(got["reply"], str) else ""
    files = {kind: scope_json(png, kind) for kind in KINDS}
    pattern = (r"Waveform: highlights clipped in \d+\.\d % of pixels, shadows in \d+\.\d %; its "
               r"256 × 256 counts are in \S+\.waveform\.json\. "
               r"Parade: red clips high in \d+\.\d % of pixels and low in \d+\.\d %, green in "
               r"\d+\.\d % and \d+\.\d %, blue in \d+\.\d % and \d+\.\d %; its 3 × 256 × 256 "
               r"counts are in \S+\.parade\.json\. "
               r"Vectorscope \(Rec\. 709 Cb and Cr of the encoded values\): \d+\.\d % of pixels "
               r"are neutral; its 256 × 256 counts are in \S+\.vectorscope\.json\. "
               r"Histogram: highlights clipped in \d+\.\d % of pixels, shadows in \d+\.\d % \(by "
               r"Y′\); its R′, G′, B′ and Y′ counts per 256 levels are in "
               r"\S+\.histogram\.json\. Written to \S+\.png\.$")
    said = re.search(pattern, text)
    raw = decode(png, W, H) if got["ok"] and png.exists() else None
    want = set()
    if raw is not None:
        for at in range(0, len(raw), 4):
            want.add(bins_of(raw[at] / 255, raw[at + 1] / 255, raw[at + 2] / 255))
    counts = files["vectorscope"].get("counts") or []
    have = {(cb, cr) for cr, row in enumerate(counts) for cb, n in enumerate(row) if n}
    # ±1 bin on each axis, both ways (Chebyshev distance).
    agree = raw is not None and bool(have) and bool(want) and all(
        min(max(abs(a[0] - b[0]), abs(a[1] - b[1])) for b in other) <= 1
        for one, other in ((have, want), (want, have)) for a in one)
    check("M1 render_frame with all four booleans: four sentences in order before \"Written "
          "to\", four JSON files, and the vectorscope's occupied bins within ±1 of the BT.709 "
          "bins of the PNG's pixels",
          said is not None and all(files.values()) and agree,
          f"text {text[-160:]!r}; files {[k for k in KINDS if files[k]]}; vectorscope bins "
          f"{sorted(have)[:10]} vs computed {sorted(want)[:10]}")

    # M3
    refused = doc.call("render_frame", t=T, vectorscope="yes")
    check("M3 render_frame {vectorscope: \"yes\"} is refused, naming vectorscope",
          not refused["ok"] and "vectorscope" in refused.get("error", ""),
          f"answer {refused.get('error') or 'ACCEPTED'!r}")

    # S13
    s13(doc)

    # M2, M4
    wave = files["waveform"]
    target = (wave.get("highlights"), wave.get("shadows"))
    time.sleep(SETTLE)
    shown_menu = doc.call("perform_menu_item", path=SCOPES)
    panel, views = wait_readouts(doc, None if None in target else target)
    check(f"M2 View ▸ Scopes shown, paused: the top slot's readouts {panel} are within 0.2 "
          f"points of the waveform JSON's {target}",
          shown_menu["ok"] and None not in panel and None not in target
          and all(abs(a - b) <= 0.2 for a, b in zip(panel, target)),
          f"menu {shown_menu.get('error', 'ok')}")
    box = view(views, "scopes.panel") or {}
    pf = box.get("frame") or [0, 0, 0, 0]
    pickers = {name: (view(views, f"scopes.{name}.picker", "UISnapshotPart") or {}).get("text")
               for name in ("top", "bottom")}
    bottom = view(views, "scopes.bottom") or {}
    trace = view(views, "scopes.bottom.trace") or {}
    sf, tf = bottom.get("frame") or [0, 0, 0, 0], trace.get("frame") or [0, 0, 0, 0]
    tall = pf[3] >= 360
    bottom_shown = bottom.get("hidden") is False
    square = (bottom_shown and abs(tf[2] - tf[3]) <= 0.5 and 0 < tf[2] <= 224.5
              and abs((tf[0] + tf[2] / 2) - (sf[0] + sf[2] / 2)) <= 0.5)
    check("M4 snapshot_ui: a 248 pt panel, pickers reading Waveform and Vectorscope, the bottom "
          "slot shown exactly when the pane is ≥ 360 pt, and (shown) the vectorscope body "
          "square, side ≤ 224, centred in its slot",
          not box.get("hidden", True) and abs(pf[2] - 248) <= 0.5
          and pickers == {"top": "Waveform", "bottom": "Vectorscope"}
          and bottom_shown == tall and (square or not tall),
          f"panel {pf}; pickers {pickers}; bottom {sf} hidden {bottom.get('hidden')}; "
          f"vectorscope {tf}")
    state["m4_tall"] = tall
    doc.call("perform_menu_item", path=SCOPES)
    saved = WORK / "S-saved.framejob"
    stored = doc.call("save_project", path=str(saved))
    doc.path = saved
    closed = attempt(client, "close_project", {"project": str(saved), "discard": True})["ok"]
    return closed, (saved if stored["ok"] else None)


def s13(doc):
    """`render_frame {vectorscope: true, vectorscope_zoom: 4}` against this
    script's ×4 bins of the PNG, and the zoom's two refusals."""
    png = WORK / "s13.png"
    got = doc.call("render_frame", t=T, path=str(png), vectorscope=True, vectorscope_zoom=4)
    text = got["reply"] if got["ok"] and isinstance(got["reply"], str) else ""
    body = scope_json(png, "vectorscope")
    said = re.search(r"Vectorscope at ×4 \(Rec\. 709 Cb and Cr of the encoded values\): "
                     r"\d+\.\d % of pixels are neutral and \d+\.\d % lie off the plot; its "
                     r"256 × 256 counts are in \S+\.vectorscope\.json\. Written to \S+\.png\.$",
                     text)
    raw = decode(png, W, H) if got["ok"] and png.exists() else None
    want, off = set(), 0
    if raw is not None:
        for at in range(0, len(raw), 4):
            one = zoomed_bins_of(raw[at] / 255, raw[at + 1] / 255, raw[at + 2] / 255, 4)
            if one is None:
                off += 1
            else:
                want.add(one)
    counts = body.get("counts") or []
    have = {(cb, cr) for cr, row in enumerate(counts) for cb, n in enumerate(row) if n}
    agree = raw is not None and bool(have) and bool(want) and all(
        min(max(abs(a[0] - b[0]), abs(a[1] - b[1])) for b in other) <= 1
        for one, other in ((have, want), (want, have)) for a in one)
    targets = body.get("targets") or {}
    three = doc.call("render_frame", t=T, vectorscope=True, vectorscope_zoom=3)
    bare = doc.call("render_frame", t=T, vectorscope_zoom=2)
    refused = [not r["ok"] and "vectorscope_zoom" in r.get("error", "") for r in (three, bare)]
    check("S13 render_frame {vectorscope: true, vectorscope_zoom: 4}: the JSON's zoom is 4, its "
          "occupied bins within ±1 of this script's ×4 bins of the PNG, off_plot exactly this "
          "script's off-plot pixels (the six coloured bars), every target null, the zoomed "
          "sentence; vectorscope_zoom 3, and 2 without vectorscope, refused naming "
          "vectorscope_zoom",
          said is not None and body.get("zoom") == 4 and agree and raw is not None
          and body.get("off_plot") == off and off > 0
          and sorted(targets) == ["B", "Cy", "G", "Mg", "R", "Yl"]
          and all(v is None for v in targets.values()) and all(refused),
          f"text {text[-200:]!r}; zoom {body.get('zoom')}; off_plot {body.get('off_plot')} vs "
          f"{off}; bins {sorted(have)[:6]} vs {sorted(want)[:6]}; targets "
          f"{targets}; refusals {three.get('error') or 'ACCEPTED'!r} / "
          f"{bare.get('error') or 'ACCEPTED'!r}")


# ---- the probe ------------------------------------------------------------------

def power():
    ran = bounded.run(["pmset", "-g"], 30)
    lines = [ln.strip() for ln in ran["stdout"].splitlines()
             if re.search(r"powermode|lowpowermode|AC Power|Battery Power|Currently drawing",
                          ln)]
    batt = bounded.run(["pmset", "-g", "batt"], 30)
    return lines + [ln.strip() for ln in batt["stdout"].splitlines()[:1]]


def score_s1(body):
    s1 = (body.get("data") or {}).get("S1") or {}
    cards = s1.get("cards") or {}
    targets = s1.get("targets") or {}
    rgb = {"R": (0.75, 0, 0), "G": (0, 0.75, 0), "B": (0, 0, 0.75), "Cy": (0, 0.75, 0.75),
           "Mg": (0.75, 0, 0.75), "Yl": (0.75, 0.75, 0)}
    misses = []
    for name, value in rgb.items():
        want = list(bins_of(*value))
        got = cards.get(name) or []
        if len(got) != 1 or got[0][:2] != want or got[0][2] != 256:
            misses.append(f"{name}: card {got[:3]} ≠ {want}")
        if targets.get(name) != want:
            misses.append(f"{name}: target {targets.get(name)} ≠ {want}")
    angle = s1.get("skin_line_degrees")
    angle_ok = isinstance(angle, (int, float)) and abs(angle - 123.3) <= 0.05
    check("S1 75 % R, G, B, Cy, Mg and Yl cards each land in ONE vectorscope bin, this "
          "script's BT.709 bin; the JSON's targets agree; the skin line is 123.3°",
          bool(cards) and not misses and angle_ok,
          f"misses {misses[:6]}; skin line {angle}")


# S15's cards (`scopes_probe.swift`), each value exact in half float.
S15_CARDS = {"R": (0.75, 0, 0), "G": (0, 0.75, 0), "B": (0, 0, 0.75), "Cy": (0, 0.75, 0.75),
             "Mg": (0.75, 0, 0.75), "Yl": (0.75, 0.75, 0), "warm": (0.875, 0.25, 0.125),
             "leaf": (0.125, 0.625, 0.375), "sky": (0.375, 0.5, 0.875)}
S15_BARS = ("R", "G", "B", "Cy", "Mg", "Yl")


def score_s15(body):
    """S15 (hdr H-4): with signal .hlg the six 75 % cards land in this script's BT.2020 bin,
    the JSON's targets agree, every card's waveform and histogram Y′ is round(255·Y′₂₀₂₀),
    and the parade is the same at either signal. CONTROL: cards whose Rec. 709 and BT.2020
    Y′ levels part."""
    s15 = (body.get("data") or {}).get("S15") or {}
    cards, levels, targets = s15.get("cards") or {}, s15.get("levels") or {}, \
        s15.get("targets") or {}
    misses, parted = [], 0
    for name in S15_BARS:
        want = [bin_of(c) for c in chroma2020(*S15_CARDS[name])]
        got = cards.get(name) or []
        if len(got) != 1 or got[0][:2] != want or got[0][2] != 256:
            misses.append(f"{name}: card {got[:3]} ≠ {want}")
        if targets.get(name) != want:
            misses.append(f"{name}: target {targets.get(name)} ≠ {want}")
    for name, rgb in S15_CARDS.items():
        want = luma_level(rgb, LUMA2020)
        parted += want != luma_level(rgb, LUMA709)
        got = levels.get(name) or {}
        for kind in ("waveform", "histogram"):
            if got.get(kind) != [want]:
                misses.append(f"{name}: {kind} Y′ {got.get(kind)} ≠ [{want}]")
    if parted < 4:
        misses.append(f"CONTROL: only {parted} cards' Rec. 709 and BT.2020 Y′ levels part")
    if s15.get("parade_same") is not True:
        misses.append(f"the parade differs across the signals ({s15.get('parade_same')})")
    check("S15 an HLG signal: the six 75 % cards each land in ONE vectorscope bin, this script's "
          "BT.2020 bin, the JSON's targets agree; nine cards' waveform and histogram Y′ levels "
          "are round(255·Y′) on BT.2020's weights; the parade is the same at either signal",
          bool(cards) and not misses,
          f"misses {misses[:6]}; {parted} of {len(S15_CARDS)} cards part Rec. 709 from BT.2020 "
          f"(CONTROL); skin line {s15.get('skin_line_degrees')} (recorded)")


T1_SCORED = ("parade", "vectorscope", "vectorscope-x2", "vectorscope-x4", "histogram",
             "vectorscope-hlg", "vectorscope-hlg-x2", "vectorscope-hlg-x4", "histogram-hlg")


def score_t1(body):
    figures = (body.get("records") or {}).get("T1") or {}
    worst = {}
    for scope in T1_SCORED + ("waveform", "waveform+vectorscope", "waveform-hlg"):
        values = (figures.get("4K") or {}).get(scope) or {}
        whole = len(values) == 6
        worst[scope] = ((max(values.values()), max(values, key=values.get)) if whole else None)
    for size in ("1080p", "4K"):
        for scope, values in sorted((figures.get(size) or {}).items()):
            note(f"T1 {size} {scope}: " + ", ".join(f"{k} {v:.3f}" for k, v in
                                                    sorted(values.items())) + " ms")
    note(f"T1 host: {figures.get('gpu')}; " + " | ".join(power()))
    scored = [worst.get(s) for s in T1_SCORED]
    check(f"T1 the worst 4K GPU time over GR-26's six fixtures of each scope, the vectorscope at "
          f"each zoom, is ≤ {BOUND_MS} ms (GR-10, GR-26, GR-31): parade {worst.get('parade')}, "
          f"vectorscope ×1 {worst.get('vectorscope')}, ×2 {worst.get('vectorscope-x2')}, ×4 "
          f"{worst.get('vectorscope-x4')}, histogram {worst.get('histogram')}; in HLG "
          f"vectorscope ×1 {worst.get('vectorscope-hlg')}, ×2 {worst.get('vectorscope-hlg-x2')}, "
          f"×4 {worst.get('vectorscope-hlg-x4')}, histogram {worst.get('histogram-hlg')} "
          f"(recorded: waveform {worst.get('waveform')}, waveform + vectorscope "
          f"{worst.get('waveform+vectorscope')}, HLG waveform {worst.get('waveform-hlg')})",
          all(w is not None and w[0] <= BOUND_MS for w in scored))


def score_t2(body):
    figures = (body.get("records") or {}).get("T2") or {}
    pairs = figures.get("4K") or {}
    for name, pair in sorted(pairs.items()):
        note(f"T2 4K {name}: banded {pair.get('banded')}, global {pair.get('global')} ms")
    banded = [pair.get("banded") for pair in pairs.values()]
    global_ = [pair.get("global") for pair in pairs.values()]
    whole = (len(pairs) == 6 and not figures.get("anchor") and not figures.get("error")
             and all(isinstance(v, (int, float)) for v in banded + global_))
    # The fixture where the forced-global parade is slowest, the one banding is for.
    at = max(pairs, key=lambda name: pairs[name].get("global")) if whole else None
    worst_b = pairs[at].get("banded") if whole else None
    worst_g = pairs[at].get("global") if whole else None
    ratio = worst_b / worst_g if whole and worst_g else None
    check(f"T2 on the fixture where the forced-global parade is slowest, the banded parade's 4K "
          f"time is ≤ {RATIO_MAX} × the global one's (the banded path is the one running): "
          f"{at}, banded {worst_b}, global {worst_g}, "
          f"ratio {None if ratio is None else round(ratio, 3)}",
          ratio is not None and worst_b <= RATIO_MAX * worst_g,
          "" if whole else f"anchor {figures.get('anchor')}; error {figures.get('error')}; "
          f"fixtures {sorted(pairs)}; host {figures.get('gpu')}")


def score_t3(body):
    """T2's shape for the vectorscope: the tree's ×1 pass against the same
    shader with its one `bool central = ` line forced to `false`."""
    figures = (body.get("records") or {}).get("T3") or {}
    pairs = figures.get("4K") or {}
    for name, pair in sorted(pairs.items()):
        note(f"T3 4K {name}: tree {pair.get('tree')}, global {pair.get('global')} ms")
    tree = [pair.get("tree") for pair in pairs.values()]
    global_ = [pair.get("global") for pair in pairs.values()]
    whole = (len(pairs) == 6 and "near-grey" in pairs and not figures.get("anchor")
             and not figures.get("error")
             and all(isinstance(v, (int, float)) for v in tree + global_))
    # Near-grey by name, the fixture the central threadgroup counts are for
    # (#296: the slowest forced-global fixture let a loaded gradient sample,
    # ratio about 0.9 at rest, take the score).
    at = "near-grey" if whole else None
    worst_t = pairs[at].get("tree") if whole else None
    worst_g = pairs[at].get("global") if whole else None
    ratio = worst_t / worst_g if whole and worst_g else None
    check(f"T3 on near-grey, the tree's 4K time "
          f"is ≤ {T3_RATIO_MAX} × the global one's (the central threadgroup path is the one "
          f"running): {at}, tree {worst_t}, global {worst_g}, "
          f"ratio {None if ratio is None else round(ratio, 3)}",
          ratio is not None and worst_t <= T3_RATIO_MAX * worst_g,
          "" if whole else f"anchor {figures.get('anchor')}; error {figures.get('error')}; "
          f"fixtures {sorted(pairs)}; host {figures.get('gpu')}")


def baseline_shader(folder):
    """The T4-0 tree's `Waveform.metal`, written beside the probe, or None."""
    ran = bounded.run(["git", "-C", str(ROOT), "show", f"{BASELINE}:{SHADER}"], 60)
    if ran["rc"] != 0 or not ran["stdout"]:
        return None
    path = folder / "baseline-Waveform.metal"
    path.write_text(ran["stdout"])
    return path


def percentile(values, q):
    """The `q` quantile of `values`, by linear interpolation between ranks."""
    ordered = sorted(values)
    at = (len(ordered) - 1) * q
    low = int(at)
    high = min(low + 1, len(ordered) - 1)
    return ordered[low] + (ordered[high] - ordered[low]) * (at - low)


def summary(values):
    """(median, IQR, min, max) of `values`."""
    return (percentile(values, 0.5), percentile(values, 0.75) - percentile(values, 0.25),
            min(values), max(values))


def loads(values):
    return " ".join(f"{v:.2f}" for v in values or [])


def central_ab(rounds, base):
    """#296's A/B: the ×1 vectorscope of `base`'s shader (the central path),
    its `central = false` twin and the tree's, interleaved per round on the
    six 4K fixtures; one verdict line, last. Exit 0, or 2 when the
    measurement could not decide or could not be made."""
    print(f"grading-4 #296 — the vectorscope's central path A/B ({rounds} rounds, base {base})",
          flush=True)
    print(f"  load before: {loads(os.getloadavg())}", flush=True)
    for line in power():
        print(f"  power: {line}", flush=True)
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    shown = bounded.run(["git", "-C", str(ROOT), "show", f"{base}:{SHADER}"], 60)
    if shown["rc"] != 0 or not shown["stdout"]:
        print(f"instrument failure: git show {base}:{SHADER} — {shown['stderr'].strip()[-300:]}")
        return 2
    base_text = shown["stdout"]
    lines = base_text.split("\n")
    matches = [i for i, line in enumerate(lines) if line.strip().startswith(CENTRAL_ANCHOR)]
    if len(matches) != 1:
        print(f"instrument failure: {len(matches)} lines of {base}'s shader start "
              f"`{CENTRAL_ANCHOR}`")
        return 2
    lines[matches[0]] = CENTRAL_FORCED
    base_path, twin_path = folder / "base-Waveform.metal", folder / "twin-Waveform.metal"
    base_path.write_text(base_text)
    twin_path.write_text("\n".join(lines))
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(ROOT / "app/Sources") + [entry],
                                  output=folder / "scopes_probe",
                                  defines=["FRAMEJOB_DEV_TOOLS"], timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        print(f"instrument failure: the probe does not build — {error} {error.diagnostics[:6]}")
        return 2
    request, answer = folder / "request.json", folder / "answer.json"
    request.write_text(json.dumps({
        "shader": str(ROOT / SHADER),
        "central_ab": {"base_shader": str(base_path), "forced_shader": str(twin_path),
                       "rounds": rounds}}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 540,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    print(f"  load after: {loads(os.getloadavg())}", flush=True)
    try:
        ab = (json.loads(answer.read_text()).get("records") or {}).get("AB") or {}
    except (OSError, ValueError):
        ab = {}
    fixtures = ab.get("fixtures") or {}
    if ab.get("error") or len(fixtures) != 6 or "near-grey" not in fixtures or any(
            len(fixtures[f].get(arm) or []) != rounds for f in fixtures
            for arm in ("base", "tree", "twin")):
        print(f"instrument failure: the probe answered {ab.get('error') or sorted(fixtures)} "
              f"(rc {ran['rc']}, expired {ran['expired']}) "
              f"{(ran['stdout'] + ran['stderr']).strip()[-400:]}")
        return 2
    identical = bool(ab.get("identical"))
    print(f"  GPU: {ab.get('gpu')}; rounds {ab.get('rounds')}; tree "
          f"{'IDENTICAL to' if identical else 'differs from'} base (the "
          f"{'CONTROL' if identical else 'measurement'})", flush=True)
    stats, spread = {}, {}
    for name, entry_ in fixtures.items():
        stats[name] = {arm: summary(entry_[arm]) for arm in ("base", "tree", "twin")}
        paired = summary([t - b for t, b in zip(entry_["tree"], entry_["base"])])
        spread[name] = max(stats[name]["base"][1], stats[name]["tree"][1])
        print(f"  {name}: " + "; ".join(
            f"{arm} {s[0]:.4f} ms, IQR {s[1]:.4f}, [{s[2]:.4f}..{s[3]:.4f}]"
            for arm, s in stats[name].items()), flush=True)
        print(f"    tree − base paired: median {paired[0]:+.4f} ms, IQR {paired[1]:.4f}; S "
              f"{spread[name]:.4f}; load {loads(entry_.get('load_before'))} → "
              f"{loads(entry_.get('load_after'))}", flush=True)
    m = {arm: {f: stats[f][arm][0] for f in stats} for arm in ("base", "tree", "twin")}
    worst_base = max(m["base"], key=m["base"].get)
    worst_tree = max(m["tree"], key=m["tree"].get)
    spread_w = max(spread[worst_base], spread[worst_tree])
    print(f"  worst: base {m['base'][worst_base]:.4f} ({worst_base}) tree "
          f"{m['tree'][worst_tree]:.4f} ({worst_tree}) S_W {spread_w:.4f}", flush=True)

    def verdict(other, s, s_w):
        """The pre-declared rule with `other` in the drop candidate's place,
        `s` each fixture's decision spread and `s_w` the worst fixtures'."""
        grey = "near-grey"
        if m[other][grey] - m["base"][grey] > s[grey] and all(
                m["base"][f] - m[other][f] <= s[f] for f in stats):
            return "KEEP (pays)"
        if max(m[other].values()) > m["base"][worst_base] + s_w:
            return "KEEP (worst fixture)"
        return "DROP"

    # The twin's verdict, under the same rule with its own spreads, as a record.
    twin_spread = {f: max(stats[f]["base"][1], stats[f]["twin"][1]) for f in stats}
    twin_worst = max(m["twin"], key=m["twin"].get)
    twin_w = max(twin_spread[worst_base], twin_spread[twin_worst])
    print(f"  rec   twin under the same rule: {verdict('twin', twin_spread, twin_w)} (worst "
          f"twin {m['twin'][twin_worst]:.4f} ({twin_worst}), S_W {twin_w:.4f})", flush=True)
    wide = [f for f in stats if spread[f] > CENTRAL_PRECISION * min(m["base"][f], m["tree"][f])]
    if wide:
        print(f"STOP — spread too wide: {', '.join(f'{f} S {spread[f]:.4f}' for f in wide)} "
              f"exceed {CENTRAL_PRECISION:.0%} of the smaller median")
        return 2
    if identical:
        apart = [f for f in stats if abs(m["tree"][f] - m["base"][f]) > spread[f]]
        if apart:
            print(f"CONTROL FAILURE: identical shaders differ by more than S on "
                  f"{', '.join(apart)}")
            return 2
        print("CONTROL PASS: identical shaders within S on every fixture")
        return 0
    print(f"VERDICT: {verdict('tree', spread, spread_w)}")
    return 0


def run_probe(sources, package):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    scored = sorted(S_ROWS)
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "scopes_probe",
                                  defines=["FRAMEJOB_DEV_TOOLS"], timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        for name in scored:
            check(f"{name} the probe builds over app/Sources", False,
                  f"{error} {error.diagnostics[:6]}")
        return
    request, answer = folder / "request.json", folder / "answer.json"
    if answer.exists():
        answer.unlink()
    shader = sources.parent / "Resources/Shaders/Waveform.metal"
    baseline = baseline_shader(folder)
    request.write_text(json.dumps({"package": str(package), "shader": str(shader),
                                   "baseline_shader": str(baseline) if baseline else ""}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        body = json.loads(answer.read_text())
    except (OSError, ValueError):
        body = {}
    answered = body.get("rows") or []
    if "S1" in selected:
        score_s1(body)
    if "S15" in selected:
        score_s15(body)
    if "T1" in selected:
        score_t1(body)
    if "T2" in selected:
        score_t2(body)
    if "T3" in selected:
        score_t3(body)
    for name in scored:
        if name in ("S1", "S15", "T1", "T2", "T3"):
            continue
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False, (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---- the harness ----------------------------------------------------------------

def harness(binary, package, out, look, height, items):
    ran = subprocess.run([binary, str(package), str(out), look, "1440", str(height), "-1", "0",
                          "1", "clip", "-", "-", "-", "-", "-", items],
                         capture_output=True, text=True, timeout=300)
    panel, slots, cells = None, [], {}
    for line in ran.stdout.splitlines():
        parts = line.split()
        if line.startswith("seeing panel "):
            panel = [float(v) for v in parts[2:6]]
        elif line.startswith("seeing slot "):
            slots.append((parts[2], parts[3], [float(v) for v in parts[4:8]]))
        elif line.startswith("seeing cells "):
            cells[parts[2]] = [float(v) for v in parts[3:7]]
    if ran.returncode != 0 or not out.exists() or panel is None:
        return None, (ran.stdout + ran.stderr).strip()[-400:] or "no panel line"
    return (panel, slots, cells), None


def bright(path, rect, kind, scale_from=1440):
    width, _, channels, image = e2.decode_png(str(path))
    scale = width / scale_from
    x, y, w, h = (int(round(v * scale)) for v in rect)
    if kind in ("waveform", "parade"):
        gutter = int(round(24 * scale))
        x, w = x + gutter, w - gutter
    count = 0
    for row in image[y:y + h]:
        for px in range(x, x + w):
            if max(row[px * channels:px * channels + 3]) >= 200:
                count += 1
    return count


def harness_checks(package):
    binary, error = e2.build_harness()
    pairs = [(KINDS[i], KINDS[(i + 1) % 4]) for i in range(4)]
    same, found, problems = {}, {}, []
    for top, bottom in pairs:
        for look in ("light", "dark"):
            captures = []
            for n in (1, 2):
                if error:
                    break
                out = WORK / f"harness-{top}-{bottom}-{look}-{n}.png"
                got, error = harness(binary, package, out, look, 1100,
                                     f"scopes,ramp,top={top},bottom={bottom}")
                if got is None:
                    break
                captures.append(out.read_bytes())
                if n == 1:
                    for name, kind, rect in got[1]:
                        found[(top, bottom, look, name)] = (kind, bright(out, rect, kind))
            if error:
                break
            same[(top, bottom, look)] = captures[0] == captures[1]
    if error:
        for name in ("H1", "H2"):
            check(f"{name} the harness renders the scopes", False, error)
    else:
        check("H1 four captures (top k[i] over bottom k[i+1]) with the ramp traces, light and "
              "dark, each byte-identical twice",
              len(same) == 8 and all(same.values()),
              f"{ {'/'.join(k): v for k, v in same.items()} }")
        weak = {"/".join(k): v for k, v in found.items() if v[1] < 200}
        check("H2 every visible body of the captures holds ≥ 200 trace pixels",
              len(found) == 16 and not weak, f"bodies {len(found)}; weak {weak}")
    runs = [(805, "scopes,ramp"), (1100, "scopes,ramp"), (650, "scopes,ramp"),
            (650, "scopes,ramp,top=vectorscope")]
    seen = []
    for height, items in runs:
        if error:
            break
        got, error = harness(binary, package, WORK / f"h3-{height}-{len(seen)}.png", "light",
                             height, items)
        if got is None:
            break
        panel, slots, _ = got
        px, py, pw, ph = panel
        inside = all(r[0] >= px - 0.5 and r[0] + r[2] <= px + pw + 0.5 and r[1] >= py - 0.5
                     and r[1] + r[3] <= py + ph + 0.5 for _, _, r in slots)
        bottom = any(name == "bottom" for name, _, _ in slots)
        squares = all(abs(r[2] - r[3]) <= 0.5 and r[2] <= 224.5
                      and abs(r[0] + r[2] / 2 - (px + pw / 2)) <= 0.5
                      for _, kind, r in slots if kind == "vectorscope")
        has_vector = any(kind == "vectorscope" for _, kind, _ in slots)
        seen.append((height, ph, inside, bottom == (ph >= 360), squares, has_vector,
                     [(n, k, r) for n, k, r in slots]))
    if error:
        check("H3 the harness renders the scopes at three pane heights", False, error)
        zoom_checks(binary, package)
        return
    panes = [s[1] for s in seen]
    spread = (any(400 <= p <= 520 for p in panes) and any(p >= 700 for p in panes)
              and sum(1 for p in panes if p < 360) == 2)
    check("H3 at panes ≈ 460, ≥ 700 and < 360 pt (twice): the slot rects lie inside the panel, "
          "the bottom slot shows iff the pane is ≥ 360, and every vectorscope shown is square "
          "and centred",
          spread and all(s[2] and s[3] and s[4] for s in seen) and all(s[5] for s in seen[:2])
          and seen[3][5],
          " | ".join(f"window {s[0]}: pane {s[1]}, inside {s[2]}, bottom rule {s[3]}, "
                     f"square {s[4]}, {s[6]}" for s in seen))
    zoom_checks(binary, package)


def zoom_checks(binary, package):
    """H4: the top vectorscope at ×2 and ×4 over the ramp traces, light and
    dark, each byte-identical twice and unlike the same look at ×1, and the
    zoom cells in the square's bottom-right corner (GR-31)."""
    captures, corner, error = {}, [], None
    if not binary:
        check("H4 the harness renders the zoomed vectorscope", False, "the harness did not build")
        return
    for look in ("light", "dark"):
        for zoom in ZOOMS:
            items = "scopes,ramp,top=vectorscope" + (f",topzoom={zoom}" if zoom > 1 else "")
            pair = []
            for n in (1, 2):
                out = WORK / f"h4-{look}-x{zoom}-{n}.png"
                got, error = harness(binary, package, out, look, 1100, items)
                if got is None:
                    break
                pair.append(out.read_bytes())
                if n == 1:
                    square = next((r for name, kind, r in got[1]
                                   if name == "top" and kind == "vectorscope"), None)
                    cells = got[2].get("top")
                    placed = (square is not None and cells is not None
                              and abs(cells[2] - 46) <= 0.5 and abs(cells[3] - 16) <= 0.5
                              and abs((cells[0] + cells[2]) - (square[0] + square[2] - 4)) <= 0.5
                              and abs((cells[1] + cells[3]) - (square[1] + square[3] - 4)) <= 0.5)
                    corner.append((look, zoom, placed, square, cells))
            if error:
                break
            captures[(look, zoom)] = pair
        if error:
            break
    if error:
        check("H4 the harness renders the zoomed vectorscope", False, error)
        return
    twice = {f"{look}×{zoom}": len(p) == 2 and p[0] == p[1] for (look, zoom), p in captures.items()}
    unlike = {f"{look}×{zoom}": captures[(look, zoom)][0] != captures[(look, 1)][0]
              for look in ("light", "dark") for zoom in (2, 4)}
    check("H4 the top vectorscope at ×2 and ×4 over the ramp traces, light and dark: each "
          "byte-identical twice and unlike the same look's ×1; the zoom cells (46 × 16) 4 pt in "
          "from the square's bottom-right corner",
          all(twice.values()) and len(twice) == 6 and all(unlike.values())
          and all(c[2] for c in corner) and len(corner) == 6,
          f"twice {twice}; unlike ×1 {unlike}; cells "
          + " | ".join(f"{c[0]} ×{c[1]}: square {c[3]}, cells {c[4]}" for c in corner))


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
    parser.add_argument("--app", default=None)
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--central-ab", action="store_true",
                        help="#296's A/B of the vectorscope's central path; launches no app")
    parser.add_argument("--rounds", type=int, default=CENTRAL_ROUNDS)
    parser.add_argument("--base", default=CENTRAL_BASE)
    args = parser.parse_args()
    if args.central_ab:
        if args.mutant or args.only:
            print("--central-ab takes neither --mutant nor --only")
            return 2
        if args.rounds < 1:
            print("--rounds must be positive")
            return 2
        remove_work()
        atexit.register(remove_work)
        HOME.mkdir(parents=True)
        return central_ab(args.rounds, args.base)
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if args.mutant:
        selected -= H_ROWS
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][1] if args.mutant else []
    scored = [name for name in ROWS if name in selected]
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading-2 G2-1 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = proof_app.executable(app)
        sources = copy / "app/Sources"
    else:
        print(f"grading-2 G2-1 — the scopes over MCP ({config} build {binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    bars = write_png(WORK / "bars.png", W, H, bar_pixel)
    log = WORK / "instance.log"
    state = {}
    launched = mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    closed, package = True, None
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        try:
            closed, package = run_mcp(launched.client, bars, state)
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if selected & S_ROWS:
        if package is None:
            for name in sorted(selected & S_ROWS):
                check(f"{name} project S was made and saved", False)
        else:
            run_probe(sources, package)
    if selected & H_ROWS:
        if package is None:
            for name in sorted(selected & H_ROWS):
                check(f"{name} project S was made and saved", False)
        else:
            harness_checks(package)
    found = complaints(log)
    fixtures_ok = all(value for key, value in state.items() if key.endswith("fixture"))
    check("Z1 CONTROL: the fixture holds, the project closes and the log holds no `Frame Job: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; fixtures {state}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing or not fixtures_ok:
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}, fixtures {state}")
            return 2
        survived = [name for name in named if rows.get(name)]
        tolerated = TOLERATED.get(args.mutant, [])
        others = [name for name in scored
                  if not rows.get(name) and name not in named and name not in tolerated]
        excused = [name for name in tolerated if name in rows and not rows.get(name)]
        caught = not survived and not others
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if not survived else 'did not all fail'} in the "
              f"copy (survived: {', '.join(survived) or 'none'}; other rows failed: "
              f"{', '.join(others) or 'none'}; tolerated rows failed: "
              f"{', '.join(excused) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
