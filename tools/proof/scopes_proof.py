#!/usr/bin/env python3
"""Road map "grading-2", phase G2-1 (spec §11 GR-10) — the scopes: the RGB
parade, the Rec. 709 vectorscope and the R′G′B′Y′ histogram beside the luma
waveform, View ▸ Scopes' two slots, and `render_frame {parade, vectorscope,
histogram}`.

    python3 tools/proof/scopes_proof.py [--app PATH] [--only S1,M1,...]
    python3 tools/proof/scopes_proof.py --mutant NAME

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
- **S6**: every kind's counts total the pixels (×3, ×4) on GR-10's five
  fixtures, at sizes the threadgroup does not divide.
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
- **T1**: each scope's GPU time at 1080p and 4K on the five fixtures, through
  an IOSurface 64RGBAHalf wrap as the tap's, median of 10 after 2 warm-ups.
  Scored: the worst 4K figure of each of parade, vectorscope and histogram
  ≤ 1.1 ms (GR-10). The waveform and the waveform + vectorscope pair are
  recorded, with `pmset -g`'s power lines.
- **T2**: the tree's parade against the same shader with its one
  `bool banded = ` line forced to `false` (every group adding globally),
  timed back to back on the five 4K fixtures as T1 times them. Scored: on the
  fixture where the forced-global parade is slowest (flat on the M2 Max), the
  banded time ≤ 0.75 × the global one, which says the banded path is the one
  running (T1 alone cannot: the global parade sits about T1's 1.1 ms). The
  other fixtures are recorded; banding gains nothing on them. A shader with no
  such line, or more than one, is a FAILURE, never a skip.

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
- **Z1** (CONTROL): the fixture holds, the project closes and the log holds
  no `Frame Job: ` line.

`--mutant NAME`, one of the eleven below, builds a COPY of the tree
(`tree_copy.make_copy`), applies its edits (each anchor asserted to occur
exactly once), builds it by the copy's own `make app-debug` (`make app` under
`RC_PROOF_APP=release`) and runs every row but H1–H3 on it, the probe built
over the copy's `app/Sources` and its shader. MUTANT PASS when every named
row FAILED and no other scored row did, but a row the mutant tolerates
(`TOLERATED`), which the MUTANT line names when it failed:
  cb-cr-swapped        the kernel puts Cr on the Cb axis: S1 M1
  bt601                the vectorscope's matrix is BT.601's: S1 M1
  bins-edged           the chroma bins floor instead of round: S1 S2
  vectorscope-global   every vectorscope pixel adds globally: T1
  histogram-global     every histogram pixel adds globally: T1
  histogram-luma-601   the histogram's Y′ takes BT.601's weights: S5
  pick-persisted       a pick is written to UserDefaults: S9
  tap-first-kind-only  the tap measures only the first shown kind: S7 S8
  slots-not-shrunk     the bodies stay at their preferred heights: S10
  parade-band-misplaced  the parade's merge puts both bands in the group's
                       first column: S3
  parade-global        every parade group adds globally: T2 (T1 tolerated: the
                       forced-global parade measured 1.15 ms at 4K on flat in
                       G2-5 (1.019–1.042 in G2-1), at or over T1's 1.1 ms)
Exit 0 when every scored row passed (a mutant: caught); 1 when one failed
(a mutant: survived); 2 when the control could not be performed.
"""

import argparse
import atexit
import json
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
KINDS = ["waveform", "parade", "vectorscope", "histogram"]
ROWS = ["S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "T1", "T2", "M1", "M2",
        "M3", "M4", "H1", "H2", "H3", "Z1"]
S_ROWS = {"S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "T1", "T2"}
M_ROWS = {"M1", "M2", "M3", "M4"}
H_ROWS = {"H1", "H2", "H3"}
SCOPES = ["View", "Scopes"]
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
        "bool central = false;")], ["T1"]),
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
        "app/Sources/WaveformTap.swift", "analyzer.encode(kinds, frame: texture, into: buffer)",
        "analyzer.encode(Set(ScopeKind.allCases.filter(kinds.contains).prefix(1)), "
        "frame: texture, into: buffer)")], ["S7", "S8"]),
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
}
# A row a mutant may fail BECAUSE of it, besides the rows it must fail.
TOLERATED = {"parade-global": ["T1"]}
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


def bins_of(r, g, b):
    cb, cr = chroma(r, g, b)
    return bin_of(cb), bin_of(cr)


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


def score_t1(body):
    figures = (body.get("records") or {}).get("T1") or {}
    worst = {}
    for scope in ("parade", "vectorscope", "histogram", "waveform", "waveform+vectorscope"):
        values = (figures.get("4K") or {}).get(scope) or {}
        worst[scope] = (max(values.values()), max(values, key=values.get)) if values else None
    for size in ("1080p", "4K"):
        for scope, values in sorted((figures.get(size) or {}).items()):
            note(f"T1 {size} {scope}: " + ", ".join(f"{k} {v:.3f}" for k, v in
                                                    sorted(values.items())) + " ms")
    note(f"T1 host: {figures.get('gpu')}; " + " | ".join(power()))
    scored = [worst.get(s) for s in ("parade", "vectorscope", "histogram")]
    check(f"T1 the worst 4K GPU time of each scope is ≤ {BOUND_MS} ms (GR-10): parade "
          f"{worst.get('parade')}, vectorscope {worst.get('vectorscope')}, histogram "
          f"{worst.get('histogram')} (recorded: waveform {worst.get('waveform')}, waveform + "
          f"vectorscope {worst.get('waveform+vectorscope')})",
          all(w is not None and w[0] <= BOUND_MS for w in scored))


def score_t2(body):
    figures = (body.get("records") or {}).get("T2") or {}
    pairs = figures.get("4K") or {}
    for name, pair in sorted(pairs.items()):
        note(f"T2 4K {name}: banded {pair.get('banded')}, global {pair.get('global')} ms")
    banded = [pair.get("banded") for pair in pairs.values()]
    global_ = [pair.get("global") for pair in pairs.values()]
    whole = (len(pairs) == 5 and not figures.get("anchor") and not figures.get("error")
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
    request.write_text(json.dumps({"package": str(package), "shader": str(shader)}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        body = json.loads(answer.read_text())
    except (OSError, ValueError):
        body = {}
    answered = body.get("rows") or []
    if "S1" in selected:
        score_s1(body)
    if "T1" in selected:
        score_t1(body)
    if "T2" in selected:
        score_t2(body)
    for name in scored:
        if name in ("S1", "T1", "T2"):
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
    panel, slots = None, []
    for line in ran.stdout.splitlines():
        parts = line.split()
        if line.startswith("seeing panel "):
            panel = [float(v) for v in parts[2:6]]
        elif line.startswith("seeing slot "):
            slots.append((parts[2], parts[3], [float(v) for v in parts[4:8]]))
    if ran.returncode != 0 or not out.exists() or panel is None:
        return None, (ran.stdout + ran.stderr).strip()[-400:] or "no panel line"
    return (panel, slots), None


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
        panel, slots = got
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
    args = parser.parse_args()
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
