#!/usr/bin/env python3
"""Road map "mattes", phases MT2 and MT3 (#240; spec §11 MT-1..MT-6) — the
matte track end to end over MCP: `set_track {matte}`, the recipe's `matte` and
`mattes`, and the compositor's matte pass, read back as `render_frame` bytes;
then (MT3) nests, dissolves, a matted clip's shadow and reflection, and every
export preset; then (issue batch B90) nested dissolves and zooms measured.

    python3 tools/proof/matte_proof.py [--app PATH] [--only C0,A1,...]
    python3 tools/proof/matte_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/matte/home`,
and every package, movie and PNG is under `tools/proof/work/matte/`, which is
removed at the start and at exit. No menu item is performed. Every call is
bounded (`CALL_BOUND`), every ffmpeg too (120 s).

The canvas is 640×360 at 30 fps and every frame is taken at t = 0.5 s
(300000). A 2 s ffmpeg `testsrc2` movie (640×360, 30 fps) is made in the work
folder. Every claim is a byte comparison of two `render_frame` PNGs, or a
formula over measured bytes, ±1 per channel.

Project P: track A (index 0) holds the movie; track B (in front) a white
200×120 rectangle (no stroke) at the canvas centre, its box x 220–420,
y 120–240. Three references: PLAIN (B over A, ordinary), A-ALONE (B hidden)
and BG (both hidden, the canvas background alone). INSIDE is the box less
3 px, OUTSIDE everything more than 3 px from it.
- **C0** (CONTROL): two renders of PLAIN are byte-equal.
- **A1**: B an `alpha` matte: INSIDE equals A-ALONE, OUTSIDE equals BG.
- **G0**: `get_project` shows track B `matte: "alpha"`; after N0 the track
  has no `matte` key at all.
- **U0**: `undo` brings PLAIN's bytes back and `redo` A1's.
- **P6**: the matte clip's `blend: multiply`, a drop shadow and a reflection
  leave A1's bytes unchanged (MT-4: the core clears them).
- **MM**: a third track C in front of B, an `alpha` matte holding a RED
  rectangle over the box's left half: A1's bytes unchanged, and A1's two
  region claims hold — a matte in front of a matte draws nothing and cuts
  nothing, and B still cuts A.
- **V5**: B's clip trimmed to end at 0.25 s: the frame equals A-ALONE.
- **H0**: B hidden: the frame equals A-ALONE.
- **B0**: A scaled to 0.25 (so B's box shows round it if B drew) and B moved
  to index 0: the frame equals A-ALONE-SMALL (B hidden) — a back-most matte
  draws nothing and A is uncut.
- **A2**: `alpha_inverted`: INSIDE equals BG, OUTSIDE equals A-ALONE.
- **N0**: `matte: "none"` brings PLAIN's bytes back.
- **R0**: `matte: "chroma"` is refused naming the five modes, and the
  project is unchanged.
Project L, its canvas background (0.4, 0.2, 0.1): track 1 a full-canvas card
(0.2, 0.6, 0.9); track 2 a 400×200 black-to-white linear gradient at the
centre. g is a pixel's Rec. 709 luma over 255 in the gradient drawn alone;
CARD and BG are the card alone and the background alone. Sampled every 4 px
along y = 180 inside the gradient's box, and at points outside it.
- **L1**: `luma`: inside, card·g + bg·(1 − g); outside, BG.
- **L2**: `luma_inverted`: inside, card·(1 − g) + bg·g; outside, CARD.
- **L3**: the gradient's track removed and the movie on a new front track,
  a `luma` matte: every sample (every 8 px on 5 rows) is card·g + bg·(1 − g),
  g from the movie drawn alone.
Phase MT3's projects (spec §11 MT-3, MT-5). A box is (x0, y0, x1, y1) in
canvas pixels; INSIDE a box is it less MARGIN, CLEAR of boxes more than
MARGIN from each.
Project N is project P's pair (the movie on A, B's white rectangle an
`alpha` matte; MATTED its frame), each row undone after it:
- **N1**: `nest` of A's and B's clips: MATTED's bytes (the nest clip lands
  on A's track, the front-most selected track that is not a matte, and the
  nested B track carries its matte).
- **N4**: `nest` of B's clip alone: MATTED's bytes (the nest clip lands on
  B's track and its nested track is ordinary: no carry).
- **N2**: `nest` of A's clip alone: MATTED's bytes.
- **N6**: `nest` of both, then `unnest`: MATTED's bytes, and the tracks'
  `matte` list as before.
- **N3**: a second white rectangle (410–530 × 160–320) on a new front track,
  nested with B's clip, the nest clip moved onto B: inside either rectangle
  A-ALONE, clear of both BG.
- **N5** (its own project): the movie under an inner `alpha` window
  (160–400 × 100–260), nested together, the nest clip under an outer window
  (320–520 × 140–300) on the emptied matte track: A-ALONE inside the
  intersection, BG everywhere else (each matte multiplies in).
- **N7** (its own project, background black): red then green full cards
  (0–1 s, 1–2 s) under a left then a right window, nested, the nest clip
  split at 1 s and a 0.5 s dissolve made from the first half's tail (the
  halves' starts — a nest clip's origin — read back from `get_project`).
  At 1.25 s the outgoing half shows green through the right window and the
  incoming red through the left: the left window's pixels carry ≤ 2 green
  and ≥ 40 red, the right's ≤ 2 red and ≥ 40 green, and outside both ≤ 2.
  (That the recipe lists two groups there is `core/tests/matte_nest.rs`'s
  claim: no tool returns a recipe.)
Project T (background (0.4, 0.2, 0.1)): a red card then a blue one with a
0.5 s cross dissolve (linear) at 1 s; U is the unmatted dissolve at 1 s.
- **T2**: B's rectangle an `alpha` matte: U inside, BG outside.
- **T3**: the matte a uniform 50 % grey full card, `luma`: every 16th pixel is
  m·U + (1 − m)·BG, m the card's luma drawn alone (±2).
- **T1** (its own project, background black): a full card under two matte
  windows (left 0–1 s, right 1–2 s) with a 0.5 s dissolve: at 1 s each
  pixel is card × a, a the windows drawn alone (±2), and a is 0.3–0.7 at
  both windows' centres.
Project S (background (0.4, 0.2, 0.1)): a white 200×200 card (220–420 ×
60–260) with a hard red shadow (60 px at 315°) under an `alpha` window over
its left half (220–320 × 40–280).
- **S1**: the cut card white; the red cast exactly where the CUT shape
  offset by 42.43 px is and the cut card is not; BG where the uncut half's
  body and shadow would have been.
- **RF1**: the card 100 px tall (220–420 × 60–160) with a full reflection
  below it (160–260): under a window over the card alone (200–440 × 40–160)
  the reflection's area is BG and the card A-ALONE; under one over both
  (200–440 × 40–280), the reflection is the unmatted reflection's bytes.
Project E (background (0.4, 0.2, 0.1), then transparent): a full card under
an `alpha` window (200–440 × 100–260), 1 s. Each preset exported at the
document's size and its frame at 0.5 s decoded by ffmpeg (frame 0 if the
encoder kept fewer — the fixture does not move); every 8th pixel inside the
window less 8 px and every 16th more than 16 px clear of it within ±8 of
`render_frame` (solid colours, so the GIF palette holds them):
- **E1** `h264`, **E2** `hevc`, **E4** `prores_422`, **E6** `gif` over the
  opaque background.
- **E3** `hevc_alpha`, **E5** `prores_4444`, **E7** `apng` over a transparent
  canvas: alpha 255 inside and 0 outside (±2), the colour inside. A Mac
  with no HEVC-with-alpha encoder is a named host skip of E3.
- **F1** (its own project): a graphic module drawing the same window on
  the matte track over the card: `render_frame` shows the cut, and the
  `prores_422` export's `graphic prefetch:` line has hits > 0 and
  mismatched 0.
Issue batch B90 phase 1 (#252): nested dissolves and zooms MEASURED, each
row asserting today's picture ("pre") and printing the exact mix beside it.
Each its own project, background black, every transition `linear`, closed
at the end. Samples every 16th pixel of a region less MARGIN, ±2 per channel
(D1 and D6 ±3: an r8 coverage and an 8-bit half). T_A = 700000 (frame 35),
T_B = 660000 (33), T_C = 540000 (27). p is never read off the row's own
frame: it comes from DR, or from the row's own un-nested frame U.
- **DR** (CONTROL): red then green full cards (0–1 s, 1–2 s), a 0.5 s
  dissolve `after` on green: at T_A and T_B, R + G = 255 ± 2 (a timeline
  pair is exact) and p = G/255; at T_A 70 ≤ G ≤ 100. Runs whenever any D row
  does.
- **D0**: N7's construction, no matte: G = 255(1−p)², R = 255p at T_A.
- **D1**: N7's construction under a `luma` track, a left window
  (40–400 × 80–280, grey 0.4, 0–1 s) and a right one (240–600, grey 0.8,
  1–2 s), m_i and m_o their lumas drawn alone before nesting: overlap
  G = 255·m_o(1−p)²(1 − m_i·p²), R = 255·m_i·p²; right-only
  G = 255·m_o(1−p)²; left-only R = 255·m_i·p²; clear of both ≤ 2.
- **D2**: red then green with a centred dissolve, p from U at T_C, then
  nested: R = 255(1−p)², G = 255p.
- **D3**: a green card under a grey 0.4 `luma` card (m_o drawn alone),
  nested, trimmed to 1 s, a red card after it with a dissolve `after`:
  G = 255·m_o(1−p)²/(1 − p·m_o), R = 255p at T_A.
- **D4**: a red card, then a green card nested alone with a dissolve
  `after`: R = 255(1−p)², G = 255p at T_A.
- **D5**: a blue card under a white 400–600 × 120–240 rectangle, nested,
  trimmed to 1 s; a red 0–320 × 0–360 rectangle B after it with a dissolve
  `after`: in the white box R = G = 255(1−p), Blue = 255(1−p) + 255p(1−p);
  inside B R = 255p, Blue = 255(1−p).
- **D6**: a white card under two grey `luma` cards (0.4, 0.8; m_a, m_b drawn
  alone) with a centred dissolve; U at T_C gives m and p = (m − m_a)/(m_b −
  m_a); then all nested: every channel 255·(m_b·p + m_a(1−p)²).
- **D7**: red then green with a centred dissolve (p_i from U at T_B), nested,
  trimmed to 1 s, a blue card after it with a dissolve `after` (p_o from DR
  at T_B): R = 255(1−p_i)²(1−p_o), G = 255·p_i(1−p_o), Blue = 255p_o.
- **D8**: D0 with a `zoom`: inside the centred in-box (z_in = 0.75 + 0.25p of
  the canvas, 4 px kept from its edges) G = 255(1−p)², R = 255p; outside it
  G = 255(1−p), R ≤ 2.
- **Z1** (CONTROL): the log holds no `Reelcut: ` line; its tail is printed.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
anchor makes the copy's `core/` its own through `hevc_alpha_proof.own_core`),
replaces one anchor (asserted to occur exactly once), builds it by the copy's
own `make app-debug` (`make app` under `RC_PROOF_APP=release`;
`tree_copy.build_app`), and runs every row on it. A core mutant also runs
`cargo test --release --no-fail-fast --test matte --test matte_nest` in the
copy's own `core/` (row CT, scored only for a mutant that names it; the
failing files are named). The rows each must
FAIL:
  shader-no-multiply          step 7's multiply removed: A1 A2 L1
  source-drawn                render's `into` skip removed: A1 B0 MM
  resolve-mode-ignored        the resolve reads every mode as alpha: A2 L1 L2 L3
  core-no-prune               a group listed with no `into` layer: V5 H0
  core-matte-behind-matte     the target ignores a matte behind: MM
  core-untargeted-into-null   a matte layer with no target gets `into: null`:
                              B0 MM CT
  core-no-override            the source keeps shadow, reflection, blend: P6
  handler-drops-matte         the handler drops `matte`: A1 G0
  (MT3)
  dissolve-no-cover           the dissolve's cover ignores the matte: T3
  nest-always-carries         `nest` keeps every matte: N4
  nest-old-front-track        the nest clip on the front-most track: N1
  unnest-old-depth            depth from the nest's front-most track: N6 CT
  core-group-by-track         a group keyed by its track alone: N7 CT
  resolve-overwrites          the last matte in a cut set wins: N5
  reflection-placeholder      the reflection draw binds the placeholder: RF1
  (B90 phase 1)
  dissolve-cover-everywhere   an outgoing half with no partner box takes its
                              own cover: D0 D1 D2 D4 D5 D6 D7 D8
(MT3's eighth, coverage-destination-coords, is `matte_probe.py`'s.)
Rule R: exit 0 means every named row FAILED in the copy — caught; 1 that one
passed — survived; 2 that the control could not be performed (the copy did
not build or launch, the fixture did not hold, or a row was not reached). A
plain run exits 0 iff every scored row passed.
"""

import argparse
import atexit
import json
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402
from graphics_prefetch_proof import await_line, log_size  # noqa: E402

WORK = ROOT / "tools/proof/work/matte"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
WIDTH, HEIGHT = 640, 360
SEC = 600_000
T = SEC // 2
BOX = (220, 120, 420, 240)
MARGIN = 3
ROWS = ["C0", "A1", "G0", "U0", "P6", "MM", "V5", "H0", "B0", "A2", "N0", "R0",
        "L1", "L2", "L3",
        "N1", "N4", "N2", "N6", "N3", "N5", "N7", "T2", "T3", "T1", "S1", "RF1",
        "E1", "E2", "E4", "E6", "E3", "E5", "E7", "F1",
        "DR", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8", "Z1"]
P_ROWS = {"C0", "A1", "G0", "U0", "P6", "MM", "V5", "H0", "B0", "A2", "N0", "R0"}
L_ROWS = {"L1", "L2", "L3"}
N_ROWS = {"N1", "N4", "N2", "N6", "N3"}
T_ROWS = {"T2", "T3"}
S_ROWS = {"S1", "RF1"}
E_ROWS = {"E1", "E2", "E3", "E4", "E5", "E6", "E7"}
D_ROWS = {"DR", "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7", "D8"}
MODES = ["none", "alpha", "alpha_inverted", "luma", "luma_inverted"]
# name: (file, anchor, replacement, the rows that must fail)
MUTANTS = {
    "shader-no-multiply": (
        "app/Resources/Shaders/Compositor.metal",
        "    alpha *= matteCover;",
        "    alpha *= 1.0 + 0.0 * matteCover;", ["A1", "A2", "L1"]),
    "source-drawn": (
        "app/Sources/Compositor.swift",
        "            if layer.matte?.into != nil { continue }",
        "            if layer.matte?.into != nil {}", ["A1", "B0", "MM"]),
    "resolve-mode-ignored": (
        "app/Resources/Shaders/Compositor.metal",
        "    int mode = int(u.mode + 0.5);",
        "    int mode = kMatteAlpha;", ["A2", "L1", "L2", "L3"]),
    "core-no-prune": (
        "core/src/recipe_matte.rs",
        "                .any(|r| r.into.as_ref().is_some_and(|(k, _)| k == key))",
        "                .any(|r| r.into.as_ref().is_some_and(|(k, _)| k == key) || true)",
        ["V5", "H0"]),
    "core-matte-behind-matte": (
        "core/src/recipe_matte.rs",
        "    behind.matte.is_none().then_some(behind.id)",
        "    Some(behind.id)", ["MM"]),
    "core-untargeted-into-null": (
        "core/src/recipe_matte.rs",
        "            let into = role.into.as_ref().map(|(k, mode)| id_of(k, *mode));",
        "            let into = role.into.as_ref().filter(|(k, _)| listed(k))"
        ".map(|(k, mode)| id_of(k, *mode));", ["B0", "MM", "CT"]),
    "core-no-override": (
        "core/src/recipe.rs",
        "self.layer(instance, t, &assignment, *drawn_into, matte)",
        "self.layer(instance, t, &assignment, false && *drawn_into, matte)", ["P6"]),
    "handler-drops-matte": (
        "app/Sources/AgentServer+Tracks.swift",
        "solo: solo, matte: matte)",
        "solo: solo, matte: nil)", ["A1", "G0"]),
    # MT3
    "dissolve-no-cover": (
        "app/Resources/Shaders/Compositor.metal",
        "clamp(u.partnerAlpha, 0.0, 1.0) * matteCover : 0.0;",
        "clamp(u.partnerAlpha, 0.0, 1.0) : 0.0;", ["T3"]),
    "nest-always-carries": (
        "core/src/edit_nest.rs",
        "            if carried.is_none() || carried != behind {",
        "            if false {", ["N4"]),
    "nest-old-front-track": (
        "core/src/edit_nest.rs",
        "        let Some((_, front_track)) = drawn.or(sources.last()).copied() else {",
        "        let Some((_, front_track)) = sources.last().or(drawn).copied() else {", ["N1"]),
    "unnest-old-depth": (
        "core/src/edit_nest.rs",
        "            .rposition(|t| t.matte.is_none())",
        "            .rposition(|_| true)", ["N6", "CT"]),
    "core-group-by-track": (
        "core/src/recipe_matte.rs",
        "                .take(level)",
        "                .take(0)", ["N7", "CT"]),
    "resolve-overwrites": (
        "app/Sources/Compositor+Matte.swift",
        "        descriptor.colorAttachments[0].isBlendingEnabled = true",
        "        descriptor.colorAttachments[0].isBlendingEnabled = false", ["N5"]),
    "reflection-placeholder": (
        "app/Sources/Compositor.swift",
        "                encodeReflection(uniforms: uniforms, texture: texture, encoder: encoder)\n",
        "                encoder.setFragmentTexture(placeholder, index: 1)\n"
        "                encodeReflection(uniforms: uniforms, texture: texture, encoder: encoder)\n"
        "                encoder.setFragmentTexture(matte, index: 1)\n", ["RF1"]),
    # Issue batch B90 phase 1: zoom shares the dissolve's weight branch.
    "dissolve-cover-everywhere": (
        "app/Resources/Shaders/Compositor.metal",
        "clamp(u.partnerAlpha, 0.0, 1.0) * matteCover : 0.0;",
        "clamp(u.partnerAlpha, 0.0, 1.0) * matteCover : matteCover;",
        ["D0", "D1", "D2", "D4", "D5", "D6", "D7", "D8"]),
}
rows = {}
selected = set(ROWS)


def check(name, good, detail=""):
    key = name.split()[0]
    if key not in selected:
        return
    rows[key] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


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


class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path):
        self.client = client
        self.path = path

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def tracks(self):
        return self.project().get("tracks") or []

    def track(self, track):
        return next((t for t in self.tracks() if t.get("id") == track), {})

    def new_track(self):
        """A track at the front; its id, or None."""
        before = {t.get("id") for t in self.tracks()}
        self.call("add_track")
        made = [t.get("id") for t in self.tracks() if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def place(self, tool, **arguments):
        """One clip added; its id, or None."""
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def matte(self, track, mode):
        return self.call("set_track", track=track, matte=mode)

    def frame(self, tag, t=T):
        """`render_frame` at `t`; (PNG bytes, RGBA bytes) or (None, None)."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out))
        if not (got["ok"] and out.exists()):
            print(f"       render {tag}: {got.get('error', 'no file')}", flush=True)
            return None, None
        return out.read_bytes(), rgba(out)


def rgba(path):
    """A PNG at `path` as RGBA bytes through ffmpeg, or None — bounded."""
    try:
        width, height = struct.unpack(">II", Path(path).read_bytes()[16:24])
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
                              "-pix_fmt", "rgba", "-"], capture_output=True, timeout=120,
                             env=bounded.child_env()).stdout
    except (OSError, struct.error, subprocess.TimeoutExpired):
        return None
    return raw if (width, height) == (WIDTH, HEIGHT) and len(raw) == width * height * 4 \
        else None


def px(raw, x, y):
    at = (y * WIDTH + x) * 4
    return tuple(raw[at:at + 3])


def region(inside):
    """Every pixel of the INSIDE (box less MARGIN) or the OUTSIDE (more than
    MARGIN from the box)."""
    x0, y0, x1, y1 = BOX
    for y in range(HEIGHT):
        for x in range(WIDTH):
            if inside:
                if x0 + MARGIN <= x < x1 - MARGIN and y0 + MARGIN <= y < y1 - MARGIN:
                    yield x, y
            elif not (x0 - MARGIN <= x < x1 + MARGIN and y0 - MARGIN <= y < y1 + MARGIN):
                yield x, y


def matches(got, want, points, tolerance=1):
    """(every point within `tolerance` per channel, the first miss)."""
    if got is None or want is None:
        return False, "a frame is missing"
    for x, y in points:
        a, b = px(got, x, y), px(want, x, y)
        if max(abs(p - q) for p, q in zip(a, b)) > tolerance:
            return False, f"({x},{y}) {a} vs {b}"
    return True, ""


def formula(got, samples, tolerance=1):
    """Each (x, y, expected rgb) within `tolerance`; (ok, first miss, count)."""
    if got is None:
        return False, "the frame is missing", 0
    for x, y, want in samples:
        a = px(got, x, y)
        if max(abs(p - round(q)) for p, q in zip(a, want)) > tolerance:
            return False, f"({x},{y}) {a} vs {tuple(round(q, 2) for q in want)}", len(samples)
    return True, "", len(samples)


def luma(rgb):
    return (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255.0


def mix(a, b, g):
    """a·g + b·(1 − g), per channel."""
    return tuple(p * g + q * (1 - g) for p, q in zip(a, b))


def make_movie():
    movie = WORK / "testsrc2.mp4"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={WIDTH}x{HEIGHT}:rate=30:duration=2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)], 120)
    return movie if made["rc"] == 0 and movie.exists() else None


def canvas(doc, background=None):
    arguments = {"width": WIDTH, "height": HEIGHT, "fps": [30, 1]}
    if background is not None:
        arguments["background"] = background
    doc.call("set_canvas", **arguments)
    c = doc.project().get("canvas") or {}
    return c.get("width") == WIDTH and c.get("height") == HEIGHT and c.get("fps") == [30, 1]


def movie_clip(doc, movie, track):
    media = reply(doc.call("import_media", path=str(movie))).get("media")
    if media is None:
        return None
    return doc.place("add_clip", track=track, media=media, at=0)


def shape(doc, track, patch):
    return doc.place("add_shape_clip", track=track, at=0, duration=2 * SEC,
                     shape=dict({"kind": "rectangle", "stroke": None}, **patch))


def run_p(client, movie, state):
    """Project P's rows. Answers whether the project closed."""
    p = WORK / "P.reelcut"
    made = attempt(client, "new_project", {"path": str(p)})
    doc = Doc(client, p)
    sized = canvas(doc)
    a_track = (doc.tracks() or [{}])[0].get("id")
    a = movie_clip(doc, movie, a_track)
    b_track = doc.new_track()
    b = shape(doc, b_track, {"width": 200, "height": 120, "fill": [1, 1, 1, 1]})
    plain_png, plain = doc.frame("plain")
    again_png, _ = doc.frame("plain-again")
    doc.call("set_track", track=b_track, hidden=True)
    _, alone = doc.frame("a-alone")
    doc.call("set_track", track=a_track, hidden=True)
    _, bg = doc.frame("bg")
    doc.call("set_track", track=a_track, hidden=False)
    doc.call("set_track", track=b_track, hidden=False)
    fixture = (made["ok"] and sized and a is not None and b is not None
               and None not in (plain, alone, bg) and plain != alone)
    state["fixture"] = fixture
    check("C0 CONTROL: the fixture holds and two renders of PLAIN are byte-equal",
          fixture and plain_png is not None and plain_png == again_png,
          f"new {made.get('error', 'ok')}; canvas {sized}; movie clip {a}; shape {b}")
    inside, outside = list(region(True)), list(region(False))

    # A1
    set_alpha = doc.matte(b_track, "alpha")
    m_png, matted = doc.frame("alpha")
    in_ok, in_miss = matches(matted, alone, inside)
    out_ok, out_miss = matches(matted, bg, outside)
    check("A1 alpha: INSIDE is A-ALONE's bytes and OUTSIDE is BG's",
          set_alpha["ok"] and in_ok and out_ok,
          f"set {set_alpha.get('error', 'ok')}; inside {in_miss or 'ok'}; "
          f"outside {out_miss or 'ok'}")

    # G0, first half
    shown = doc.track(b_track).get("matte")

    # U0
    undone = doc.call("undo")
    u_png, _ = doc.frame("undone")
    redone = doc.call("redo")
    r_png, _ = doc.frame("redone")
    check("U0 undo brings PLAIN's bytes back, redo A1's",
          undone["ok"] and redone["ok"] and u_png == plain_png and r_png == m_png
          and m_png is not None,
          f"undo {undone.get('error', 'ok')}; redo {redone.get('error', 'ok')}")

    # P6
    styled = doc.call("set_video", clips=[b], patch={
        "blend": "multiply",
        "shadow": {"color": [0, 0, 0, 1], "opacity": 1, "blur": 0, "distance": 24,
                   "angle": 315},
        "reflection": {"opacity": 1, "height": 1, "gap": 0, "falloff": 0}})
    p6_png, _ = doc.frame("p6")
    p6_undo = doc.call("undo")
    check("P6 the matte clip's multiply, shadow and reflection leave A1's bytes unchanged",
          styled["ok"] and p6_png == m_png and m_png is not None and p6_undo["ok"],
          f"set_video {styled.get('error', 'ok')}; undo {p6_undo.get('error', 'ok')}")

    # MM
    c_track = doc.new_track()
    c = shape(doc, c_track, {"width": 100, "height": 120, "fill": [1, 0, 0, 1]})
    moved = doc.call("set_video", clips=[c], patch={"x": -50}) if c is not None else {}
    c_matte = doc.matte(c_track, "alpha")
    mm_png, mm = doc.frame("mm")
    removed = doc.call("remove_track", track=c_track, with_clips=True)
    in_ok, in_miss = matches(mm, alone, inside)
    out_ok, out_miss = matches(mm, bg, outside)
    check("MM a matte in front of a matte draws nothing and cuts nothing; B still cuts A",
          c is not None and moved.get("ok") and c_matte["ok"] and mm_png == m_png
          and m_png is not None and in_ok and out_ok and removed["ok"],
          f"C {c}; move {moved.get('error', 'ok')}; matte {c_matte.get('error', 'ok')}; "
          f"A1's bytes {mm_png == m_png}; inside {in_miss or 'ok'}; outside "
          f"{out_miss or 'ok'}; remove {removed.get('error', 'ok')}")

    # V5
    trimmed = doc.call("trim_end", clip=b, to=SEC // 4)
    _, v5 = doc.frame("v5")
    v5_undo = doc.call("undo")
    v5_ok, v5_miss = matches(v5, alone, inside + outside, tolerance=0)
    check("V5 the matte clip trimmed away at t: the frame is A-ALONE's bytes",
          trimmed["ok"] and v5_ok and v5_undo["ok"],
          f"trim {trimmed.get('error', 'ok')}; {v5_miss or 'equal'}")

    # H0
    hid = doc.call("set_track", track=b_track, hidden=True)
    _, h0 = doc.frame("h0")
    shown_again = doc.call("set_track", track=b_track, hidden=False)
    h0_ok, h0_miss = matches(h0, alone, inside + outside, tolerance=0)
    check("H0 the matte track hidden: the frame is A-ALONE's bytes",
          hid["ok"] and h0_ok and shown_again["ok"], h0_miss or "equal")

    # B0
    small = doc.call("set_video", clips=[a], patch={"scale": 0.25})
    doc.call("set_track", track=b_track, hidden=True)
    _, alone_small = doc.frame("a-alone-small")
    doc.call("set_track", track=b_track, hidden=False)
    to_back = doc.call("move_track", track=b_track, index=0)
    _, b0 = doc.frame("b0")
    back = doc.call("move_track", track=b_track, index=1)
    big = doc.call("set_video", clips=[a], patch={"scale": 1})
    b0_ok, b0_miss = matches(b0, alone_small, inside + outside, tolerance=0)
    check("B0 a back-most matte draws nothing and A is uncut",
          small["ok"] and to_back["ok"] and back["ok"] and big["ok"] and b0_ok
          and alone_small != alone,
          f"scale {small.get('error', 'ok')}; move {to_back.get('error', 'ok')}; "
          f"{b0_miss or 'equal'}")

    # A2
    inverted = doc.matte(b_track, "alpha_inverted")
    _, a2 = doc.frame("alpha-inverted")
    in_ok, in_miss = matches(a2, bg, inside)
    out_ok, out_miss = matches(a2, alone, outside)
    check("A2 alpha_inverted: INSIDE is BG's bytes and OUTSIDE is A-ALONE's",
          inverted["ok"] and in_ok and out_ok,
          f"set {inverted.get('error', 'ok')}; inside {in_miss or 'ok'}; "
          f"outside {out_miss or 'ok'}")

    # N0, and G0's second half
    off = doc.matte(b_track, "none")
    n0_png, _ = doc.frame("none")
    check("N0 matte none brings PLAIN's bytes back",
          off["ok"] and n0_png == plain_png and plain_png is not None,
          off.get("error", "ok"))
    track_b = doc.track(b_track)
    check("G0 get_project shows matte \"alpha\", and no matte key after none",
          shown == "alpha" and "matte" not in track_b and track_b.get("id") == b_track,
          f"while alpha {shown!r}; after none {json.dumps(track_b)}")

    # R0
    before = doc.project()
    refused = doc.matte(b_track, "chroma")
    error = refused.get("error", "")
    check("R0 matte \"chroma\" is refused naming the five modes; the project is unchanged",
          not refused["ok"] and all(mode in error for mode in MODES)
          and "chroma" in error and doc.project() == before,
          f"answer {error or refused.get('reply')!r}")

    closed = attempt(client, "close_project", {"project": str(p), "discard": True})
    return closed["ok"]


def run_l(client, movie, state):
    """Project L's rows. Answers whether the project closed."""
    path = WORK / "L.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0.4, 0.2, 0.1, 1])
    card_track = (doc.tracks() or [{}])[0].get("id")
    card = shape(doc, card_track, {"width": WIDTH, "height": HEIGHT,
                                   "fill": [0.2, 0.6, 0.9, 1]})
    grad_track = doc.new_track()
    grad = shape(doc, grad_track, {
        "width": 400, "height": 200, "fill": [1, 1, 1, 1],
        "gradient": {"kind": "linear", "angle": 0,
                     "stops": [{"at": 0, "color": [0, 0, 0, 1]},
                               {"at": 1, "color": [1, 1, 1, 1]}]}})
    doc.call("set_track", track=card_track, hidden=True)
    _, gradient = doc.frame("gradient")
    doc.call("set_track", track=grad_track, hidden=True)
    _, bg = doc.frame("l-bg")
    doc.call("set_track", track=card_track, hidden=False)
    _, card_alone = doc.frame("card")
    doc.call("set_track", track=grad_track, hidden=False)
    fixture = (made["ok"] and sized and card is not None and grad is not None
               and None not in (gradient, bg, card_alone))
    state["l_fixture"] = fixture
    if not fixture:
        print(f"       project L's fixture did not hold: new {made.get('error', 'ok')}; "
              f"canvas {sized}; card {card}; gradient {grad}", flush=True)
    # Inside the gradient's box (120–520 × 80–280), less MARGIN, every 4 px on
    # its middle row; outside, a ring of points clear of it.
    inner = [(x, 180) for x in range(120 + MARGIN, 520 - MARGIN, 4)]
    outer = [(40, 40), (60, 180), (600, 180), (320, 20), (320, 340), (110, 300)]
    lumas = {(x, y): luma(px(gradient, x, y)) for x, y in inner} if gradient else {}
    spread = (min(lumas.values()), max(lumas.values())) if lumas else (0, 0)
    ramp = spread[0] < 0.1 and spread[1] > 0.9

    for name, mode in (("L1", "luma"), ("L2", "luma_inverted")):
        set_ = doc.matte(grad_track, mode)
        _, got = doc.frame(mode)
        samples = []
        if fixture:
            for x, y in inner:
                g = lumas[(x, y)] if mode == "luma" else 1 - lumas[(x, y)]
                samples.append((x, y, mix(px(card_alone, x, y), px(bg, x, y), g)))
            for x, y in outer:
                samples.append((x, y, px(bg if mode == "luma" else card_alone, x, y)))
        ok, miss, count = formula(got, samples)
        expected = "card·g + bg·(1 − g)" if mode == "luma" else "card·(1 − g) + bg·g"
        check(f"{name} {mode}: inside, {expected}; outside, "
              f"{'BG' if mode == 'luma' else 'CARD'} (±1)",
              fixture and ramp and set_["ok"] and ok and count > 0,
              f"set {set_.get('error', 'ok')}; g {spread[0]:.3f}…{spread[1]:.3f}; "
              f"{count} samples; {miss or 'all within'}")

    # L3: the movie as the luma matte.
    removed = doc.call("remove_track", track=grad_track, with_clips=True)
    movie_track = doc.new_track()
    clip = movie_clip(doc, movie, movie_track) if movie_track is not None else None
    doc.call("set_track", track=card_track, hidden=True)
    _, movie_alone = doc.frame("movie-alone")
    doc.call("set_track", track=card_track, hidden=False)
    set_ = doc.matte(movie_track, "luma")
    _, got = doc.frame("movie-luma")
    samples = []
    if fixture and movie_alone is not None:
        for y in (20, 100, 180, 260, 340):
            for x in range(4, WIDTH, 8):
                g = luma(px(movie_alone, x, y))
                samples.append((x, y, mix(px(card_alone, x, y), px(bg, x, y), g)))
    ok, miss, count = formula(got, samples)
    check("L3 the movie as a luma matte over the card: card·g + bg·(1 − g), g from the "
          "movie alone (±1)",
          fixture and removed["ok"] and clip is not None and set_["ok"] and ok and count > 0,
          f"remove {removed.get('error', 'ok')}; clip {clip}; set {set_.get('error', 'ok')}; "
          f"{count} samples; {miss or 'all within'}")

    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


# ---------------------------------------------------------------------------
# Phase MT3: nests, dissolves, shadow, reflection, every export.


def centred(box):
    """`set_video`'s x/y for a shape filling `box`: its centre's offset from
    the canvas centre (spec §5.3)."""
    return {"x": (box[0] + box[2]) / 2 - WIDTH / 2, "y": (box[1] + box[3]) / 2 - HEIGHT / 2}


def placed_shape(doc, track, box, fill, at=0, duration=2 * SEC, gradient=None):
    """An unstroked rectangle filling `box` (canvas pixels) over
    [at, at + duration); its id, or None."""
    patch = {"kind": "rectangle", "stroke": None, "width": box[2] - box[0],
             "height": box[3] - box[1], "fill": fill}
    if gradient is not None:
        patch["gradient"] = gradient
    made = doc.place("add_shape_clip", track=track, at=at, duration=duration, shape=patch)
    offset = centred(box)
    if made is None or not any(offset.values()):
        return made
    return made if doc.call("set_video", clips=[made], patch=offset)["ok"] else None


def within(box, margin, step=1):
    """Every `step`th pixel of `box` shrunk by `margin`."""
    x0, y0, x1, y1 = box
    return [(x, y) for y in range(int(y0) + margin, int(y1) - margin, step)
            for x in range(int(x0) + margin, int(x1) - margin, step)]


def clear_of(boxes, margin, step=1):
    """Every `step`th pixel of the canvas more than `margin` from every box."""
    def near(x, y):
        return any(b[0] - margin <= x < b[2] + margin and b[1] - margin <= y < b[3] + margin
                   for b in boxes)
    return [(x, y) for y in range(0, HEIGHT, step) for x in range(0, WIDTH, step)
            if not near(x, y)]


def undo(doc, count):
    """`count` undos; whether every one answered."""
    return all(doc.call("undo")["ok"] for _ in range(count))


def nest_clip_of(doc):
    """The id of the timeline's one nest clip, or None."""
    found = [c["id"] for c in doc.project().get("clips") or []
             if (c.get("source") or {}).get("kind") == "nest"]
    return found[0] if len(found) == 1 else None


def track_mattes(doc):
    return [t.get("matte", "none") for t in doc.tracks()]


def run_n(client, movie, state):
    """Project N's rows (N1–N4, N6). Answers whether the project closed."""
    path = WORK / "N.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc)
    a_track = (doc.tracks() or [{}])[0].get("id")
    a = movie_clip(doc, movie, a_track)
    b_track = doc.new_track()
    b = placed_shape(doc, b_track, BOX, [1, 1, 1, 1])
    doc.call("set_track", track=b_track, hidden=True)
    _, alone = doc.frame("n-alone")
    doc.call("set_track", track=a_track, hidden=True)
    _, bg = doc.frame("n-bg")
    doc.call("set_track", track=a_track, hidden=False)
    doc.call("set_track", track=b_track, hidden=False)
    set_ = doc.matte(b_track, "alpha")
    m_png, matted = doc.frame("n-matted")
    mattes_before = track_mattes(doc)
    fixture = (made["ok"] and sized and a is not None and b is not None and set_["ok"]
               and None not in (alone, bg, matted) and matted != alone)
    state["n_fixture"] = fixture
    if not fixture:
        print(f"       project N's fixture did not hold: new {made.get('error', 'ok')}; "
              f"canvas {sized}; movie {a}; shape {b}; matte {set_.get('error', 'ok')}",
              flush=True)

    # N1: both tracks nested.
    nested = doc.call("nest", clips=[a, b])
    on = (doc.project().get("clips") or [{}])
    lands = [c.get("track") for c in on if (c.get("source") or {}).get("kind") == "nest"]
    n1_png, _ = doc.frame("n1")
    n1_undo = undo(doc, 1)
    check("N1 nesting the matte pair keeps the bytes (the nest clip lands on the target's "
          "track)", fixture and nested["ok"] and n1_png == m_png and n1_undo,
          f"nest {nested.get('error', 'ok')}; nest clip on track {lands} (A's {a_track}); "
          f"bytes equal {n1_png == m_png}")

    # N4: only the matte clip nested.
    nested = doc.call("nest", clips=[b])
    n4_png, _ = doc.frame("n4")
    n4_undo = undo(doc, 1)
    check("N4 nesting only the matte clip keeps the bytes (no carry)",
          fixture and nested["ok"] and n4_png == m_png and n4_undo,
          f"nest {nested.get('error', 'ok')}; bytes equal {n4_png == m_png}")

    # N2: the matted clip a nest clip.
    nested = doc.call("nest", clips=[a])
    n2_png, _ = doc.frame("n2")
    n2_undo = undo(doc, 1)
    check("N2 a nest clip as the matted clip: the bytes are the matted movie's",
          fixture and nested["ok"] and n2_png == m_png and n2_undo,
          f"nest {nested.get('error', 'ok')}; bytes equal {n2_png == m_png}")

    # N6: nest, then unnest.
    nested = doc.call("nest", clips=[a, b])
    group = nest_clip_of(doc)
    opened = doc.call("unnest", clip=group) if group is not None else {"ok": False}
    n6_png, _ = doc.frame("n6")
    mattes_after = track_mattes(doc)
    n6_undo = undo(doc, 2)
    check("N6 nest then unnest of the matte pair restores the bytes and tracks[].matte",
          fixture and nested["ok"] and opened["ok"] and n6_png == m_png
          and mattes_after == mattes_before and n6_undo,
          f"unnest {opened.get('error', 'ok')}; bytes equal {n6_png == m_png}; mattes "
          f"{mattes_before} → {mattes_after}")

    # N3: a nest clip as the matte — two white rectangles, nested, moved
    # onto the matte track: the union cuts A.
    second = (410, 160, 530, 320)
    c_track = doc.new_track()
    c = placed_shape(doc, c_track, second, [1, 1, 1, 1])
    nested = doc.call("nest", clips=[b, c]) if c is not None else {"ok": False}
    group = nest_clip_of(doc)
    moved = (doc.call("move_clip", clips=[group], delta=0, track=b_track)
             if group is not None else {"ok": False})
    _, n3 = doc.frame("n3")
    in_ok, in_miss = matches(n3, alone, within(BOX, MARGIN) + within(second, MARGIN))
    out_ok, out_miss = matches(n3, bg, clear_of([BOX, second], MARGIN, 2))
    check("N3 a nest clip on the matte track: its whole composite (the union of two "
          "shapes) is the matte",
          fixture and nested["ok"] and moved["ok"] and in_ok and out_ok,
          f"nest {nested.get('error', 'ok')}; move {moved.get('error', 'ok')}; inside "
          f"{in_miss or 'ok'}; outside {out_miss or 'ok'}")

    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


def run_n5(client, movie, state):
    """Row N5: a matted nest holding its own matte pair cuts by the product."""
    path = WORK / "N5.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc)
    t1 = (doc.tracks() or [{}])[0].get("id")
    m = movie_clip(doc, movie, t1)
    t2 = doc.new_track()
    inner, outer = (160, 100, 400, 260), (320, 140, 520, 300)
    w1 = placed_shape(doc, t2, inner, [1, 1, 1, 1])
    doc.call("set_track", track=t2, hidden=True)
    _, alone = doc.frame("n5-alone")
    doc.call("set_track", track=t1, hidden=True)
    _, bg = doc.frame("n5-bg")
    doc.call("set_track", track=t1, hidden=False)
    doc.call("set_track", track=t2, hidden=False)
    set_ = doc.matte(t2, "alpha")
    nested = doc.call("nest", clips=[m, w1])
    w2 = placed_shape(doc, t2, outer, [1, 1, 1, 1])
    _, got = doc.frame("n5")
    both = (max(inner[0], outer[0]), max(inner[1], outer[1]),
            min(inner[2], outer[2]), min(inner[3], outer[3]))
    fixture = (made["ok"] and sized and m is not None and w1 is not None and w2 is not None
               and set_["ok"] and nested["ok"] and None not in (alone, bg))
    state["n5_fixture"] = fixture
    in_ok, in_miss = matches(got, alone, within(both, MARGIN))
    # Everything but the intersection: each window's own part and the rest.
    rest = [(x, y) for x, y in clear_of([both], MARGIN, 2)]
    out_ok, out_miss = matches(got, bg, rest)
    check("N5 a matted nest holding its own matte pair: the product of both (A inside the "
          "intersection, BG everywhere else)", fixture and in_ok and out_ok,
          f"movie {m}; inner {w1}; outer {w2}; nest {nested.get('error', 'ok')}; inside "
          f"{in_miss or 'ok'}; elsewhere {out_miss or 'ok'}")
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


def run_n7(client, state):
    """Row N7: a split nest clip in a dissolve, each half its own matte."""
    path = WORK / "N7.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0, 0, 0, 1])
    t1 = (doc.tracks() or [{}])[0].get("id")
    left, right = (40, 80, 280, 280), (360, 80, 600, 280)
    full = (0, 0, WIDTH, HEIGHT)
    red = placed_shape(doc, t1, full, [1, 0, 0, 1], at=0, duration=SEC)
    green = placed_shape(doc, t1, full, [0, 1, 0, 1], at=SEC, duration=SEC)
    t2 = doc.new_track()
    w_left = placed_shape(doc, t2, left, [1, 1, 1, 1], at=0, duration=SEC)
    w_right = placed_shape(doc, t2, right, [1, 1, 1, 1], at=SEC, duration=SEC)
    set_ = doc.matte(t2, "alpha")
    nested = doc.call("nest", clips=[red, green, w_left, w_right])
    first = nest_clip_of(doc)
    split = doc.call("split", clips=[first], at=SEC) if first is not None else {"ok": False}
    halves = sorted(((c["start"], c["duration"], c["id"]) for c in
                     doc.project().get("clips") or []
                     if (c.get("source") or {}).get("kind") == "nest"))
    second = halves[1][2] if len(halves) == 2 else None
    dissolved = (doc.call("add_transition", clip=second, duration=SEC // 2, align="after")
                 if second is not None else {"ok": False})
    # The halves' origins (a nest clip's origin is its start): the first
    # shows nest time t, the second t − 1 s, so at the overlap's midpoint the
    # outgoing half shows green through the right window and the incoming
    # red through the left one.
    halves = sorted(((c["start"], c["duration"]) for c in doc.project().get("clips") or []
                     if (c.get("source") or {}).get("kind") == "nest"))
    overlap = (halves == [(0, SEC + SEC // 2), (SEC, SEC)])
    mid = SEC + SEC // 4
    _, got = doc.frame("n7", t=mid)
    fixture = (made["ok"] and sized and None not in (red, green, w_left, w_right)
               and set_["ok"] and nested["ok"] and split["ok"] and dissolved["ok"] and overlap)
    state["n7_fixture"] = fixture

    def worst(points, channel):
        if got is None:
            return None
        return max(px(got, x, y)[channel] for x, y in points)

    def least(points, channel):
        if got is None:
            return None
        return min(px(got, x, y)[channel] for x, y in points)

    lp, rp = within(left, MARGIN, 4), within(right, MARGIN, 4)
    green_left, red_right = worst(lp, 1), worst(rp, 0)
    red_left, green_right = least(lp, 0), least(rp, 1)
    outside = worst(clear_of([left, right], MARGIN, 4), 0), worst(clear_of([left, right],
                                                                          MARGIN, 4), 1)
    ok = (fixture and None not in (green_left, red_right, red_left, green_right)
          and green_left <= 2 and red_right <= 2 and red_left >= 40 and green_right >= 40
          and max(outside) <= 2)
    check("N7 a split nest clip in a dissolve: each half cut by its own matte (the left "
          "window carries ≤ 2 green, the right ≤ 2 red)", ok,
          f"halves (start, duration) {halves}; transition {dissolved.get('error', 'ok')}; "
          f"left red ≥ {red_left}, green ≤ {green_left}; right green ≥ {green_right}, red ≤ "
          f"{red_right}; outside max (r, g) {outside}")
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


def run_t(client, state):
    """Rows T2 and T3: a dissolve between two matted clips."""
    path = WORK / "T.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0.4, 0.2, 0.1, 1])
    t1 = (doc.tracks() or [{}])[0].get("id")
    full = (0, 0, WIDTH, HEIGHT)
    a = placed_shape(doc, t1, full, [1, 0, 0, 1], at=0, duration=SEC)
    b = placed_shape(doc, t1, full, [0, 0, 1, 1], at=SEC, duration=SEC)
    dissolved = (doc.call("add_transition", clip=b, duration=SEC // 2)
                 if b is not None else {"ok": False})
    linear = doc.call("set_transition_style", clip=b, curve="linear")
    t2 = doc.new_track()
    w = placed_shape(doc, t2, BOX, [1, 1, 1, 1])
    doc.call("set_track", track=t2, hidden=True)
    _, unmatted = doc.frame("t-unmatted", t=SEC)
    doc.call("set_track", track=t1, hidden=True)
    _, bg = doc.frame("t-bg", t=SEC)
    doc.call("set_track", track=t1, hidden=False)
    doc.call("set_track", track=t2, hidden=False)
    set_ = doc.matte(t2, "alpha")
    _, t2_frame = doc.frame("t2", t=SEC)
    fixture = (made["ok"] and sized and None not in (a, b, w) and dissolved["ok"]
               and set_["ok"] and None not in (unmatted, bg))
    state["t_fixture"] = fixture
    # The midpoint really is a mix: neither card's red nor blue alone.
    mixed = unmatted is not None and 100 < px(unmatted, 320, 180)[0] < 160
    in_ok, in_miss = matches(t2_frame, unmatted, within(BOX, MARGIN))
    out_ok, out_miss = matches(t2_frame, bg, clear_of([BOX], MARGIN, 2))
    check("T2 a dissolve between two matted clips under a hard matte: the unmatted "
          "dissolve's bytes inside, BG outside", fixture and mixed and in_ok and out_ok,
          f"transition {dissolved.get('error', 'ok')}; linear {linear.get('error', 'ok')}; "
          f"midpoint {px(unmatted, 320, 180) if unmatted else None}; inside "
          f"{in_miss or 'ok'}; outside {out_miss or 'ok'}")

    # T3: the window becomes a uniform ~50 % grey full-canvas luma card.
    grown = doc.call("set_shape", clips=[w], patch={"width": WIDTH, "height": HEIGHT,
                                                    "fill": [0.5, 0.5, 0.5, 1]})
    doc.matte(t2, "none")
    doc.call("set_track", track=t1, hidden=True)
    _, card = doc.frame("t3-card", t=SEC)
    doc.call("set_track", track=t1, hidden=False)
    luma_ = doc.matte(t2, "luma")
    _, t3 = doc.frame("t3", t=SEC)
    samples = []
    m_values = set()
    if fixture and card is not None:
        for y in range(4, HEIGHT, 16):
            for x in range(4, WIDTH, 16):
                m = luma(px(card, x, y))
                m_values.add(round(m, 4))
                samples.append((x, y, mix(px(unmatted, x, y), px(bg, x, y), m)))
    uniform = len(m_values) == 1 and 0.4 < min(m_values or {0}) < 0.6
    ok, miss, count = formula(t3, samples, tolerance=2)
    check("T3 the same dissolve under a ~50 % grey luma card: m·mix(A, B, p) + (1 − m)·bg, "
          "m from the card's bytes (±2)",
          fixture and grown["ok"] and luma_["ok"] and uniform and ok
          and count > 0,
          f"set_shape {grown.get('error', 'ok')}; m {sorted(m_values)}; {count} samples; "
          f"{miss or 'all within'}")
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


def run_t1(client, state):
    """Row T1: a dissolve between two matte clips shapes the matte."""
    path = WORK / "T1.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0, 0, 0, 1])
    t1 = (doc.tracks() or [{}])[0].get("id")
    card = placed_shape(doc, t1, (0, 0, WIDTH, HEIGHT), [0.2, 0.6, 0.9, 1])
    t2 = doc.new_track()
    left, right = (80, 80, 280, 280), (360, 80, 560, 280)
    w1 = placed_shape(doc, t2, left, [1, 1, 1, 1], at=0, duration=SEC)
    w2 = placed_shape(doc, t2, right, [1, 1, 1, 1], at=SEC, duration=SEC)
    dissolved = (doc.call("add_transition", clip=w2, duration=SEC // 2)
                 if w2 is not None else {"ok": False})
    doc.call("set_track", track=t1, hidden=True)
    _, windows = doc.frame("t1-windows", t=SEC)
    doc.call("set_track", track=t1, hidden=False)
    doc.call("set_track", track=t2, hidden=True)
    _, card_alone = doc.frame("t1-card", t=SEC)
    doc.call("set_track", track=t2, hidden=False)
    set_ = doc.matte(t2, "alpha")
    _, got = doc.frame("t1", t=SEC)
    fixture = (made["ok"] and sized and None not in (card, w1, w2) and dissolved["ok"]
               and set_["ok"] and None not in (windows, card_alone))
    state["t1_fixture"] = fixture
    samples = []
    if fixture:
        for y in (100, 180, 260):
            for x in range(2, WIDTH, 4):
                a = luma(px(windows, x, y))
                samples.append((x, y, tuple(c * a for c in px(card_alone, x, y))))
    halfway = windows is not None and all(
        0.3 < luma(px(windows, *centre_of)) < 0.7 for centre_of in ((180, 180), (460, 180)))
    ok, miss, count = formula(got, samples, tolerance=2)
    check("T1 a dissolve between two matte clips at its midpoint: card × a, a the two "
          "windows' dissolve drawn alone (±2)", fixture and halfway and ok and count > 0,
          f"transition {dissolved.get('error', 'ok')}; window alphas at the centres "
          f"{[round(luma(px(windows, *c)), 3) for c in ((180, 180), (460, 180))] if windows else None}; "
          f"{count} samples; {miss or 'all within'}")
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


def run_s(client, state):
    """Rows S1 and RF1: the matted clip's shadow and reflection."""
    path = WORK / "S.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0.4, 0.2, 0.1, 1])
    t1 = (doc.tracks() or [{}])[0].get("id")
    card_box = (220, 60, 420, 260)
    card = placed_shape(doc, t1, card_box, [1, 1, 1, 1])
    shadowed = doc.call("set_video", clips=[card], patch={"shadow": {
        "color": [1, 0, 0, 1], "opacity": 1, "blur": 0, "distance": 60, "angle": 315}})
    t2 = doc.new_track()
    window = (220, 40, 320, 280)
    w = placed_shape(doc, t2, window, [1, 1, 1, 1])
    doc.call("set_track", track=t1, hidden=True)
    doc.call("set_track", track=t2, hidden=True)
    _, bg = doc.frame("s-bg")
    doc.call("set_track", track=t1, hidden=False)
    doc.call("set_track", track=t2, hidden=False)
    set_ = doc.matte(t2, "alpha")
    _, s1 = doc.frame("s1")
    fixture = (made["ok"] and sized and card is not None and w is not None and shadowed["ok"]
               and set_["ok"] and bg is not None)
    state["s_fixture"] = fixture
    off = 60 * 0.5 ** 0.5
    cut = (220, 60, 320, 260)
    cast = (cut[0] + off, cut[1] + off, cut[2] + off, cut[3] + off)
    uncut_cast = (320 + off, 60 + off, 420 + off, 260 + off)

    def outside(x, y, box, margin):
        return not (box[0] - margin <= x < box[2] + margin and box[1] - margin <= y < box[3]
                    + margin)

    red_points = [(x, y) for x, y in within(cast, MARGIN) if outside(x, y, cut, MARGIN)]
    white_ok, white_miss = formula(s1, [(x, y, (255, 255, 255)) for x, y in
                                        within(cut, MARGIN, 2)])[:2]
    red_ok, red_miss = formula(s1, [(x, y, (255, 0, 0)) for x, y in red_points[::3]])[:2]
    gone = [(x, y) for x, y in within(uncut_cast, MARGIN, 2) if outside(x, y, cast, MARGIN)]
    gone += [(x, y) for x, y in within((320, 60, 420, 260), MARGIN, 2)
             if outside(x, y, cast, MARGIN)]
    bg_ok, bg_miss = matches(s1, bg, gone)
    check("S1 the matted clip's drop shadow is the CUT shape, offset: red only there, the "
          "uncut half's shadow and body BG", fixture and white_ok and red_ok and bg_ok
          and len(red_points) > 0 and len(gone) > 0,
          f"shadow {shadowed.get('error', 'ok')}; cut body {white_miss or 'white'}; cast "
          f"{red_miss or 'red'} ({len(red_points)} px); the rest {bg_miss or 'BG'}")

    # RF1: the card 100 px tall with a full reflection below it.
    reshaped = doc.call("set_shape", clips=[card], patch={"height": 100})
    body = (220, 60, 420, 160)
    mirrored = (220, 160, 420, 260)
    placed = doc.call("set_video", clips=[card], patch=dict(centred(body), shadow=None,
                      reflection={"opacity": 1, "height": 1, "gap": 0, "falloff": 0}))
    covers_body = (200, 40, 440, 160)
    doc.call("set_shape", clips=[w], patch={"width": 240, "height": 120})
    doc.call("set_video", clips=[w], patch=centred(covers_body))
    doc.call("set_track", track=t2, hidden=True)
    _, reflected = doc.frame("rf-alone")
    doc.call("set_track", track=t2, hidden=False)
    _, rf_a = doc.frame("rf1-a")
    covers_both = (200, 40, 440, 280)
    doc.call("set_shape", clips=[w], patch={"height": 240})
    grown = doc.call("set_video", clips=[w], patch=centred(covers_both))
    _, rf_b = doc.frame("rf1-b")
    lit = reflected is not None and min(px(reflected, 320, 210)) > 200
    gone_ok, gone_miss = matches(rf_a, bg, within(mirrored, MARGIN))
    body_ok, body_miss = matches(rf_a, reflected, within(body, MARGIN))
    back_ok, back_miss = matches(rf_b, reflected, within(mirrored, MARGIN) + within(body,
                                                                                   MARGIN))
    check("RF1 the matted clip's reflection is cut where it lands: under a window over the "
          "card alone, BG below it; under one over both, the unmatted reflection's bytes",
          fixture and reshaped["ok"] and placed["ok"] and grown["ok"] and lit and gone_ok
          and body_ok and back_ok,
          f"reflection {placed.get('error', 'ok')}; reflection lit {lit}; below the card "
          f"{gone_miss or 'BG'}; the card {body_miss or 'A-alone'}; with the second window "
          f"{back_miss or 'A-alone'}")
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


EXPORTS = [("E1", "h264", False), ("E2", "hevc", False), ("E3", "hevc_alpha", True),
           ("E4", "prores_422", False), ("E5", "prores_4444", True), ("E6", "gif", False),
           ("E7", "apng", True)]
EXTENSION = {"h264": "mp4", "hevc": "mp4", "hevc_alpha": "mov", "prores_422": "mov",
             "prores_4444": "mov", "gif": "gif", "apng": "png"}
RATE = {"gif": 12.5, "apng": 25.0}
NO_HEVC_ALPHA = "This Mac cannot export with the “hevc_alpha” preset."
E_WINDOW = (200, 100, 440, 260)


def decoded(movie, n):
    """Frame `n` of `movie` (frame 0 when it has fewer) as RGBA bytes at the
    canvas size, and which frame it was; (None, why) — bounded."""
    for index in (n, 0):
        try:
            raw = subprocess.run(
                ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{index})",
                 "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo",
                 "-pix_fmt", "rgba", "-"],
                capture_output=True, timeout=120, env=bounded.child_env()).stdout
        except (OSError, subprocess.TimeoutExpired) as error:
            return None, f"ffmpeg: {error}"
        if len(raw) == WIDTH * HEIGHT * 4:
            return raw, index
    return None, f"no {WIDTH}x{HEIGHT} frame decoded"


def run_e(client, state):
    """Rows E1–E7: every export preset draws the matte as render_frame does."""
    path = WORK / "E.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0.4, 0.2, 0.1, 1])
    t1 = (doc.tracks() or [{}])[0].get("id")
    card = placed_shape(doc, t1, (0, 0, WIDTH, HEIGHT), [0.2, 0.6, 0.9, 1], duration=SEC)
    t2 = doc.new_track()
    w = placed_shape(doc, t2, E_WINDOW, [1, 1, 1, 1], duration=SEC)
    set_ = doc.matte(t2, "alpha")
    _, opaque = doc.frame("e-opaque")
    fixture = (made["ok"] and sized and card is not None and w is not None and set_["ok"]
               and opaque is not None)
    state["e_fixture"] = fixture
    inside = within(E_WINDOW, 8, 8)
    outside = clear_of([E_WINDOW], 16, 16)
    reference = {False: opaque}
    # The opaque rows first: the alpha rows clear the canvas.
    for name, preset, alpha in sorted(EXPORTS, key=lambda row: row[2]):
        if name not in selected:
            continue
        if alpha and True not in reference:
            clear = doc.call("set_canvas", background=[0, 0, 0, 0])
            _, reference[True] = doc.frame("e-clear")
            if not clear["ok"]:
                reference[True] = None
        want = reference[alpha]
        movie = WORK / f"E-{preset}.{EXTENSION[preset]}"
        if movie.exists():
            movie.unlink()
        got = doc.call("export", preset=preset, path=str(movie), size="document")
        if not got["ok"] and preset == "hevc_alpha" and NO_HEVC_ALPHA in got.get("error", ""):
            print(f"  skip {name} hevc_alpha: this Mac has no HEVC-with-alpha encoder "
                  f"({got['error']})", flush=True)
            state.setdefault("skipped", []).append(name)
            continue
        n = int(RATE.get(preset, 30) * 0.5)
        raw, which = decoded(movie, n) if got["ok"] and movie.exists() else (None, "no file")
        misses = []
        if raw is not None and want is not None:
            for x, y in inside + outside:
                at = (y * WIDTH + x) * 4
                frame, ref = raw[at:at + 4], px(want, x, y)
                if alpha:
                    expected_a = 255 if (x, y) in inside else 0
                    if abs(frame[3] - expected_a) > 2:
                        misses.append(f"({x},{y}) alpha {frame[3]} vs {expected_a}")
                    if expected_a == 0:
                        continue
                if max(abs(p - q) for p, q in zip(frame[:3], ref)) > 8:
                    misses.append(f"({x},{y}) {tuple(frame[:3])} vs {ref}")
        check(f"{name} {preset}: decoded frame {which} at {len(inside)} inside and "
              f"{len(outside)} outside points within ±8 of render_frame"
              + (", alpha 255 inside and 0 outside (±2)" if alpha else ""),
              fixture and raw is not None and want is not None and not misses,
              f"export {got.get('error', 'ok')}; {misses[:3] or 'all within'}"
              + (f" ({len(misses)} misses)" if misses else ""))
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


WINDOW_MODULE = ("export const meta = { name: \"Window\", durationInFrames: 30 };\n"
                 "export const schema = {};\n"
                 "export function render(frame, props, ctx) {\n"
                 "  return svg(ctx, `<rect x=\"200\" y=\"100\" width=\"240\" height=\"160\" "
                 "fill=\"#ffffff\"/>`);\n"
                 "}\n")


def run_f(client, log, state):
    """Row F1: a graphic on the matte track is prefetched for an export."""
    path = WORK / "F.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0.4, 0.2, 0.1, 1])
    t1 = (doc.tracks() or [{}])[0].get("id")
    card = placed_shape(doc, t1, (0, 0, WIDTH, HEIGHT), [0.2, 0.6, 0.9, 1], duration=SEC)
    wrote = doc.call("write_graphic", name="window", source=WINDOW_MODULE)
    t2 = doc.new_track()
    g = doc.place("add_graphic_clip", name="window", track=t2, at=0, duration=SEC)
    set_ = doc.matte(t2, "alpha")
    _, got = doc.frame("f1")
    shaped = formula(got, [(320, 180, (51, 153, 229.5)), (40, 40, (102, 51, 25.5))],
                     tolerance=2)[0]
    movie = WORK / "F.mov"
    if movie.exists():
        movie.unlink()
    start = log_size(log)
    exported = doc.call("export", preset="prores_422", path=str(movie), size="document")
    line = await_line(log, start) if exported["ok"] else None
    state["f_fixture"] = made["ok"] and sized and card is not None and g is not None
    check("F1 a graphic on the matte track: the export's `graphic prefetch:` line has hits > 0 "
          "and mismatched 0",
          made["ok"] and sized and card is not None and wrote["ok"] and g is not None and set_["ok"] and shaped and exported["ok"]
          and line is not None and line["hits"] > 0 and line["mismatched"] == 0,
          f"write {wrote.get('error', 'ok')}; clip {g}; the matte cuts the card "
          f"{shaped}; export {exported.get('error', 'ok')}; line {line}")
    closed = attempt(client, "close_project", {"project": str(path), "discard": True})
    return closed["ok"]


# ---------------------------------------------------------------------------
# Issue batch B90 phase 1 (#252): nested dissolves and zooms, measured.

T_A, T_B, T_C = 700_000, 660_000, 540_000  # frames 35, 33 and 27
FULL = (0, 0, WIDTH, HEIGHT)
D_STEP = 16
RED, GREEN, BLUE, WHITE = [1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1], [1, 1, 1, 1]


def grey(level):
    return [level, level, level, 1]


def shown(value):
    return "(" + ", ".join("·" if c is None else f"{c:.1f}" for c in value) + ")"


def claim(got, points, pre, exact, channels=(0, 1, 2), tolerance=2):
    """Each point's `channels` within `tolerance` of `pre` (a tuple, or a
    function of (x, y)); (ok, a line with the measured value at the middle
    sample, the pre-fix prediction and the exact mix there, and the first
    miss)."""
    def at(value, x, y):
        return value(x, y) if callable(value) else value

    if got is None or not points:
        return False, "the frame is missing" if got is None else "no samples"
    miss = None
    for x, y in points:
        a, want = px(got, x, y), at(pre, x, y)
        if any(abs(a[c] - round(want[c])) > tolerance for c in channels):
            miss = f"({x},{y}) {a} vs pre {shown(want)}"
            break
    x, y = points[len(points) // 2]
    return miss is None, (f"measured {px(got, x, y)} at ({x},{y}), pre {shown(at(pre, x, y))}, "
                          f"exact {shown(at(exact, x, y))}; {len(points)} samples, ±{tolerance} "
                          f"on {'RGB'[channels[0]] if len(channels) == 1 else channels}; "
                          f"{miss or 'all within pre'}")


def mean_of(raw, points, channel):
    if raw is None or not points:
        return None
    return sum(px(raw, x, y)[channel] for x, y in points) / len(points)


def mean_luma(raw, points):
    if raw is None or not points:
        return None
    return sum(luma(px(raw, x, y)) for x, y in points) / len(points)


def linear_transition(doc, clip, **arguments):
    """`add_transition` on `clip`, its curve then set linear; whether both
    answered."""
    if clip is None:
        return False
    made = doc.call("add_transition", clip=clip, **arguments)
    return made["ok"] and doc.call("set_transition_style", clip=clip, curve="linear")["ok"]


def d_project(client, name):
    """A new project at the proof's canvas, background black; (doc, whether
    it was made and sized, its first track's id)."""
    path = WORK / f"{name}.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    sized = canvas(doc, background=[0, 0, 0, 1])
    return doc, made["ok"] and sized, (doc.tracks() or [{}])[0].get("id")


def close(doc):
    return attempt(doc.client, "close_project", {"project": str(doc.path), "discard": True})["ok"]


def nest_halves(doc):
    """The timeline's nest clips as sorted (start, duration, id, track)."""
    return sorted((c["start"], c["duration"], c["id"], c.get("track"))
                  for c in doc.project().get("clips") or []
                  if (c.get("source") or {}).get("kind") == "nest")


def split_dissolve(doc, clips, kind="cross_dissolve"):
    """N7's construction: `clips` nested, the nest clip split at 1 s and a
    0.5 s `kind` made from the first half's tail, linear. Whether every step
    answered and the halves are [0, 1.5 s) and [1 s, 2 s)."""
    if None in clips:
        return False
    nested = doc.call("nest", clips=clips)
    first = nest_clip_of(doc)
    split = doc.call("split", clips=[first], at=SEC) if first is not None else {"ok": False}
    halves = nest_halves(doc)
    second = halves[1][2] if len(halves) == 2 else None
    dissolved = linear_transition(doc, second, kind=kind, duration=SEC // 2, align="after")
    return (nested["ok"] and split["ok"] and dissolved
            and [h[:2] for h in nest_halves(doc)] == [(0, SEC + SEC // 2), (SEC, SEC)])


def trimmed_nest(doc, clips):
    """`clips` nested and the nest clip trimmed to end at 1 s; (its id, its
    track), or (None, None)."""
    if None in clips or not doc.call("nest", clips=clips)["ok"]:
        return None, None
    halves = nest_halves(doc)
    if len(halves) != 1 or not doc.call("trim_end", clip=halves[0][2], to=SEC)["ok"]:
        return None, None
    return halves[0][2], halves[0][3]


def run_dr(client, state):
    """Row DR: a timeline dissolve between two full cards — exact, and the
    reference p at T_A and T_B."""
    doc, ok, t1 = d_project(client, "DR")
    red = placed_shape(doc, t1, FULL, RED, at=0, duration=SEC)
    green = placed_shape(doc, t1, FULL, GREEN, at=SEC, duration=SEC)
    dissolved = linear_transition(doc, green, duration=SEC // 2, align="after")
    _, at_a = doc.frame("dr-a", t=T_A)
    _, at_b = doc.frame("dr-b", t=T_B)
    points = within(FULL, MARGIN, D_STEP)
    fixture = ok and None not in (red, green, at_a, at_b) and dissolved
    state["dr_fixture"] = fixture
    p, sums = {}, []
    for name, raw in (("A", at_a), ("B", at_b)):
        if raw is not None:
            p[name] = mean_of(raw, points, 1) / 255
            sums += [px(raw, x, y)[0] + px(raw, x, y)[1] for x, y in points]
    state["p"] = p if fixture else {}
    exact = bool(sums) and all(abs(s - 255) <= 2 for s in sums)
    g_a = 255 * p.get("A", 0)
    check("DR CONTROL: a timeline dissolve between two full cards is exact (R + G = 255 ± 2 "
          "at T_A and T_B) and gives p = G/255 (70 ≤ G ≤ 100 at T_A)",
          fixture and exact and 70 <= g_a <= 100,
          f"transition {dissolved}; p_A {p.get('A', 0):.4f} (G {g_a:.1f}), p_B "
          f"{p.get('B', 0):.4f}; R + G {min(sums or [0])}…{max(sums or [0])} over "
          f"{len(sums)} samples")
    return close(doc)


def run_d_split(client, state, row, kind):
    """Rows D0 (`cross_dissolve`) and D8 (`zoom`): two full cards nested, the
    nest clip split and dissolving into itself (N7's construction, no
    matte), at T_A."""
    doc, ok, t1 = d_project(client, row)
    red = placed_shape(doc, t1, FULL, RED, at=0, duration=SEC)
    green = placed_shape(doc, t1, FULL, GREEN, at=SEC, duration=SEC)
    built = split_dissolve(doc, [red, green], kind)
    _, got = doc.frame(row.lower(), t=T_A)
    p = state["p"].get("A")
    state[f"{row.lower()}_fixture"] = ok and built and p is not None
    p = p or 0
    if kind == "cross_dissolve":
        good, line = claim(got, within(FULL, MARGIN, D_STEP),
                           (255 * p, 255 * (1 - p) ** 2, None), (255 * p, 255 * (1 - p), 0),
                           channels=(0, 1))
        check("D0 a nest ↔ nest dissolve at T_A, today's picture: G = 255(1−p)², R = 255p "
              "(exact: G = 255(1−p)); p from DR (±2)",
              state["d0_fixture"] and good, f"p_A {p:.4f}; built {built}; {line}")
    else:
        z = 0.75 + 0.25 * p
        box = (320 - 320 * z, 180 - 180 * z, 320 + 320 * z, 180 + 180 * z)
        in_ok, in_line = claim(got, within(box, 4, D_STEP),
                               (255 * p, 255 * (1 - p) ** 2, None),
                               (255 * p, 255 * (1 - p), 0), channels=(0, 1))
        out_ok, out_line = claim(got, clear_of([box], 4, D_STEP),
                                 (0, 255 * (1 - p), None), (0, 255 * (1 - p), 0),
                                 channels=(0, 1))
        check("D8 a zoom between nest clips at T_A, today's picture: inside the in-box "
              "G = 255(1−p)², R = 255p (exact: G = 255(1−p)); outside it G = 255(1−p), "
              "R ≤ 2; p from DR (±2)",
              state["d8_fixture"] and in_ok and out_ok,
              f"p_A {p:.4f}, z_in {z:.4f}, in-box {tuple(round(v, 1) for v in box)}; built "
              f"{built}\n       inside: {in_line}\n       outside: {out_line}")
    return close(doc)


def run_d1(client, state):
    """Row D1 (#252): N7's construction under a `luma` matte track of two
    overlapping grey windows, at T_A."""
    doc, ok, t1 = d_project(client, "D1")
    left, right = (40, 80, 400, 280), (240, 80, 600, 280)
    red = placed_shape(doc, t1, FULL, RED, at=0, duration=SEC)
    green = placed_shape(doc, t1, FULL, GREEN, at=SEC, duration=SEC)
    t2 = doc.new_track()
    w_left = placed_shape(doc, t2, left, grey(0.4), at=0, duration=SEC)
    w_right = placed_shape(doc, t2, right, grey(0.8), at=SEC, duration=SEC)
    doc.call("set_track", track=t1, hidden=True)
    _, alone_i = doc.frame("d1-left", t=T)
    _, alone_o = doc.frame("d1-right", t=SEC + T)
    doc.call("set_track", track=t1, hidden=False)
    m_i = mean_luma(alone_i, within(left, MARGIN, D_STEP))
    m_o = mean_luma(alone_o, within(right, MARGIN, D_STEP))
    set_ = doc.matte(t2, "luma")
    built = split_dissolve(doc, [red, green, w_left, w_right])
    _, got = doc.frame("d1", t=T_A)
    p = state["p"].get("A")
    fixture = ok and set_["ok"] and built and None not in (p, m_i, m_o)
    state["d1_fixture"] = fixture
    p, m_i, m_o = p or 0, m_i or 0, m_o or 0
    overlap, right_only, left_only = (240, 80, 400, 280), (400, 80, 600, 280), (40, 80, 240, 280)
    claims = [
        ("overlap", claim(got, within(overlap, MARGIN, D_STEP),
                          (255 * m_i * p ** 2, 255 * m_o * (1 - p) ** 2 * (1 - m_i * p ** 2),
                           None),
                          (255 * p * m_i, 255 * (1 - p) * m_o, 0), (0, 1), 3)),
        ("right-only", claim(got, within(right_only, MARGIN, D_STEP),
                             (None, 255 * m_o * (1 - p) ** 2, None),
                             (0, 255 * (1 - p) * m_o, 0), (1,), 3)),
        ("left-only", claim(got, within(left_only, MARGIN, D_STEP),
                            (255 * m_i * p ** 2, None, None), (255 * p * m_i, 0, 0), (0,), 3)),
        ("clear", claim(got, clear_of([left, right], MARGIN, D_STEP), (0, 0, 0), (0, 0, 0))),
    ]
    check("D1 a split nest clip dissolving under two soft windows at T_A, today's picture: "
          "overlap G = 255·m_o(1−p)²(1 − m_i·p²), R = 255·m_i·p²; right-only G = "
          "255·m_o(1−p)²; left-only R = 255·m_i·p² (±3); clear ≤ 2",
          fixture and all(good for _, (good, _) in claims),
          f"p_A {p:.4f}, m_i {m_i:.4f}, m_o {m_o:.4f}; matte {set_.get('error', 'ok')}; built "
          f"{built}" + "".join(f"\n       {name}: {line}" for name, (_, line) in claims))
    return close(doc)


def run_d2(client, state):
    """Row D2: a dissolve inside a nest, at T_C."""
    doc, ok, t1 = d_project(client, "D2")
    red = placed_shape(doc, t1, FULL, RED, at=0, duration=SEC)
    green = placed_shape(doc, t1, FULL, GREEN, at=SEC, duration=SEC)
    dissolved = linear_transition(doc, green, duration=SEC // 2)
    _, u = doc.frame("d2-u", t=T_C)
    points = within(FULL, MARGIN, D_STEP)
    g = mean_of(u, points, 1)
    nested = doc.call("nest", clips=[red, green]) if None not in (red, green) else {"ok": False}
    halves = nest_halves(doc)
    _, got = doc.frame("d2", t=T_C)
    p = (g or 0) / 255
    fixture = (ok and dissolved and nested["ok"] and len(halves) == 1 and halves[0][0] == 0
               and g is not None and 0.1 < p < 0.9)
    state["d2_fixture"] = fixture
    good, line = claim(got, points, (255 * (1 - p) ** 2, 255 * p, None),
                       lambda x, y: px(u, x, y), channels=(0, 1))
    check("D2 a dissolve inside a nest at T_C, today's picture: R = 255(1−p)², G = 255p "
          "(exact: U's bytes); p from the un-nested frame U (±2)",
          fixture and good, f"p {p:.4f}; nest {nested.get('error', 'ok')}; {line}")
    return close(doc)


def run_d3(client, state):
    """Row D3: a nest clip under a soft inner matte dissolving into a plain
    card, at T_A."""
    doc, ok, t1 = d_project(client, "D3")
    green = placed_shape(doc, t1, FULL, GREEN)
    t2 = doc.new_track()
    matte = placed_shape(doc, t2, FULL, grey(0.4))
    doc.call("set_track", track=t1, hidden=True)
    _, alone = doc.frame("d3-grey")
    doc.call("set_track", track=t1, hidden=False)
    points = within(FULL, MARGIN, D_STEP)
    m_o = mean_luma(alone, points)
    set_ = doc.matte(t2, "luma")
    group, track = trimmed_nest(doc, [green, matte])
    b = placed_shape(doc, track, FULL, RED, at=SEC, duration=SEC) if track is not None else None
    dissolved = linear_transition(doc, b, duration=SEC // 2, align="after")
    halves = nest_halves(doc)
    _, got = doc.frame("d3", t=T_A)
    p = state["p"].get("A")
    fixture = (ok and set_["ok"] and group is not None and dissolved
               and [h[:2] for h in halves] == [(0, SEC + SEC // 2)] and None not in (p, m_o))
    state["d3_fixture"] = fixture
    p, m_o = p or 0, m_o or 0
    good, line = claim(got, points, (255 * p, 255 * m_o * (1 - p) ** 2 / (1 - p * m_o), None),
                       (255 * p, 255 * (1 - p) * m_o, 0), channels=(0, 1))
    check("D3 a nest clip under a soft inner matte dissolving into a plain card at T_A, "
          "today's picture: G = 255·m_o(1−p)²/(1 − p·m_o), R = 255p (exact: G = "
          "255(1−p)m_o); p from DR (±2)",
          fixture and good, f"p_A {p:.4f}, m_o {m_o:.4f}; halves {halves}; {line}")
    return close(doc)


def run_d4(client, state):
    """Row D4: a plain card dissolving into a nest clip, at T_A."""
    doc, ok, t1 = d_project(client, "D4")
    red = placed_shape(doc, t1, FULL, RED, at=0, duration=SEC)
    green = placed_shape(doc, t1, FULL, GREEN, at=SEC, duration=SEC)
    nested = doc.call("nest", clips=[green]) if green is not None else {"ok": False}
    group = nest_clip_of(doc)
    dissolved = linear_transition(doc, group, duration=SEC // 2, align="after")
    red_now = next((c for c in doc.project().get("clips") or [] if c["id"] == red), {})
    _, got = doc.frame("d4", t=T_A)
    p = state["p"].get("A")
    fixture = (ok and red is not None and nested["ok"] and dissolved
               and (red_now.get("start"), red_now.get("duration")) == (0, SEC + SEC // 2)
               and p is not None)
    state["d4_fixture"] = fixture
    p = p or 0
    good, line = claim(got, within(FULL, MARGIN, D_STEP),
                       (255 * (1 - p) ** 2, 255 * p, None), (255 * (1 - p), 255 * p, 0),
                       channels=(0, 1))
    check("D4 a plain card dissolving into a nest clip at T_A, today's picture: R = "
          "255(1−p)², G = 255p (exact: R = 255(1−p)); p from DR (±2)",
          fixture and good, f"p_A {p:.4f}; nest {nested.get('error', 'ok')}; {line}")
    return close(doc)


def run_d5(client, state):
    """Row D5: a nest clip of two overlapping layers dissolving into a red
    rectangle, at T_A."""
    doc, ok, t1 = d_project(client, "D5")
    white_box, b_box = (400, 120, 600, 240), (0, 0, 320, 360)
    blue = placed_shape(doc, t1, FULL, BLUE)
    t2 = doc.new_track()
    white = placed_shape(doc, t2, white_box, WHITE)
    group, track = trimmed_nest(doc, [blue, white])
    b = placed_shape(doc, track, b_box, RED, at=SEC, duration=SEC) if track is not None else None
    dissolved = linear_transition(doc, b, duration=SEC // 2, align="after")
    halves = nest_halves(doc)
    _, got = doc.frame("d5", t=T_A)
    p = state["p"].get("A")
    fixture = (ok and group is not None and dissolved
               and [h[:2] for h in halves] == [(0, SEC + SEC // 2)] and p is not None)
    state["d5_fixture"] = fixture
    p = p or 0
    in_white = claim(got, within(white_box, MARGIN, D_STEP),
                     (255 * (1 - p), 255 * (1 - p), 255 * (1 - p) + 255 * p * (1 - p)),
                     (255 * (1 - p),) * 3)
    in_b = claim(got, within(b_box, MARGIN, D_STEP), (255 * p, None, 255 * (1 - p)),
                 (255 * p, 0, 255 * (1 - p)), channels=(0, 2))
    check("D5 overlapping layers in a nested half at T_A, today's picture: in the white box "
          "R = G = 255(1−p), Blue = 255(1−p) + 255p(1−p) (exact: all 255(1−p)); inside B "
          "R = 255p, Blue = 255(1−p); p from DR (±2)",
          fixture and in_white[0] and in_b[0],
          f"p_A {p:.4f}; halves {halves}\n       white box: {in_white[1]}\n       inside B: "
          f"{in_b[1]}")
    return close(doc)


def run_d6(client, state):
    """Row D6: a dissolve between two luma matte clips inside a nest, at
    T_C."""
    doc, ok, t1 = d_project(client, "D6")
    white = placed_shape(doc, t1, FULL, WHITE)
    t2 = doc.new_track()
    g_a = placed_shape(doc, t2, FULL, grey(0.4), at=0, duration=SEC)
    g_b = placed_shape(doc, t2, FULL, grey(0.8), at=SEC, duration=SEC)
    dissolved = linear_transition(doc, g_b, duration=SEC // 2)
    points = within(FULL, MARGIN, D_STEP)
    doc.call("set_track", track=t1, hidden=True)
    _, alone_a = doc.frame("d6-a", t=T)
    _, alone_b = doc.frame("d6-b", t=SEC + T)
    doc.call("set_track", track=t1, hidden=False)
    m_a, m_b = mean_luma(alone_a, points), mean_luma(alone_b, points)
    set_ = doc.matte(t2, "luma")
    _, u = doc.frame("d6-u", t=T_C)
    m = mean_luma(u, points)
    nested = (doc.call("nest", clips=[white, g_a, g_b]) if None not in (white, g_a, g_b)
              else {"ok": False})
    halves = nest_halves(doc)
    _, got = doc.frame("d6", t=T_C)
    usable = None not in (m_a, m_b, m) and abs((m_b or 0) - (m_a or 0)) > 0.1
    p = (m - m_a) / (m_b - m_a) if usable else 0
    fixture = (ok and dissolved and set_["ok"] and nested["ok"] and len(halves) == 1
               and halves[0][0] == 0 and usable and 0.1 < p < 0.9)
    state["d6_fixture"] = fixture
    level = 255 * ((m_b or 0) * p + (m_a or 0) * (1 - p) ** 2)
    good, line = claim(got, points, (level,) * 3, lambda x, y: px(u, x, y), tolerance=3)
    check("D6 a matte dissolve inside a nest at T_C, today's picture: every channel = "
          "255·(m_b·p + m_a(1−p)²) (exact: U's bytes); p from the un-nested frame U (±3)",
          fixture and good,
          f"m_a {m_a or 0:.4f}, m_b {m_b or 0:.4f}, m {m or 0:.4f}, p {p:.4f}; nest "
          f"{nested.get('error', 'ok')}; {line}")
    return close(doc)


def run_d7(client, state):
    """Row D7: a dissolve inside a nest clip that is itself dissolving into a
    blue card, at T_B."""
    doc, ok, t1 = d_project(client, "D7")
    red = placed_shape(doc, t1, FULL, RED, at=0, duration=SEC)
    green = placed_shape(doc, t1, FULL, GREEN, at=SEC, duration=SEC)
    inner = linear_transition(doc, green, duration=SEC // 2)
    points = within(FULL, MARGIN, D_STEP)
    _, u = doc.frame("d7-u", t=T_B)
    g = mean_of(u, points, 1)
    group, track = trimmed_nest(doc, [red, green])
    blue = placed_shape(doc, track, FULL, BLUE, at=SEC, duration=SEC) \
        if track is not None else None
    outer = linear_transition(doc, blue, duration=SEC // 2, align="after")
    halves = nest_halves(doc)
    _, got = doc.frame("d7", t=T_B)
    p_i, p_o = (g or 0) / 255, state["p"].get("B")
    fixture = (ok and inner and group is not None and outer
               and [h[:2] for h in halves] == [(0, SEC + SEC // 2)] and g is not None
               and 0.1 < p_i < 0.9 and p_o is not None)
    state["d7_fixture"] = fixture
    p_o = p_o or 0
    good, line = claim(got, points,
                       (255 * (1 - p_i) ** 2 * (1 - p_o), 255 * p_i * (1 - p_o), 255 * p_o),
                       (255 * (1 - p_o) * (1 - p_i), 255 * (1 - p_o) * p_i, 255 * p_o))
    check("D7 a dissolve inside a dissolving nested half at T_B, today's picture: R = "
          "255(1−p_i)²(1−p_o), G = 255·p_i(1−p_o), Blue = 255p_o (exact: R = "
          "255(1−p_o)(1−p_i)); p_i from the un-nested frame, p_o from DR (±2)",
          fixture and good, f"p_i {p_i:.4f}, p_o {p_o:.4f}; halves {halves}; {line}")
    return close(doc)


def run_d(client, state):
    """Rows DR and D0–D8. DR's project always runs: it is every other row's
    p. Answers whether every project closed."""
    closed = run_dr(client, state)
    for name, run in (("D0", lambda: run_d_split(client, state, "D0", "cross_dissolve")),
                      ("D1", lambda: run_d1(client, state)),
                      ("D2", lambda: run_d2(client, state)),
                      ("D3", lambda: run_d3(client, state)),
                      ("D4", lambda: run_d4(client, state)),
                      ("D5", lambda: run_d5(client, state)),
                      ("D6", lambda: run_d6(client, state)),
                      ("D7", lambda: run_d7(client, state)),
                      ("D8", lambda: run_d_split(client, state, "D8", "zoom"))):
        if name in selected:
            closed = run() and closed
    return closed


def tail(log, count=4):
    try:
        lines = [line.rstrip() for line in open(log, errors="replace")]
    except OSError:
        return [f"{log} could not be read"]
    return lines[-count:] or ["(empty)"]


def complaints(log):
    try:
        return [line.strip() for line in open(log, errors="replace") if "Reelcut: " in line]
    except OSError:
        return [f"{log} could not be read"]


def launch(binary, log):
    return mcp.launch(str(binary), [], env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                      log_path=str(log), timeout=CALL_BOUND)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def build_mutant(name):
    """A copy of the tree with the mutant's anchor replaced, built by its own
    `tree_copy.build_app`. (app bundle, copy) or (None, why)."""
    path, anchor, replacement, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    if path.startswith("core/"):
        reason = own_core(copy)
        if reason:
            return None, reason
        try:
            (copy / "core/tests").symlink_to(ROOT / "core/tests")
        except OSError as error:
            return None, f"the copy's core/tests could not be linked: {error}"
    target = copy / path
    if not target.resolve().is_relative_to(WORK):
        return None, f"{path} in the copy is the tree's own file"
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor!r}"
    target.write_text(text.replace(anchor, replacement))
    print("  building the copy (one anchor replaced, found once)…", flush=True)
    app, reason = tree_copy.build_app(copy, BUILD_BOUND)
    if app is None:
        return None, reason
    return app, copy


def core_test(copy):
    """`cargo test --release --no-fail-fast --test matte --test matte_nest` in
    the copy's own core: whether it passed, and the failing targets cargo
    names (both files run whatever the first answers)."""
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "matte",
                       "--test", "matte_nest"], 900, cwd=str(copy / "core"))
    lines = (ran["stdout"] + ran["stderr"]).strip().splitlines()
    failed = [line.strip() for line in lines if line.strip().startswith("`--test ")]
    return ran["rc"] == 0 and not ran["expired"], failed or lines[-3:]


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(proof_app.binary()))
    parser.add_argument("--only", help="comma-separated rows to run and score")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {name.strip() for name in args.only.split(",") if name.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    named = MUTANTS[args.mutant][3] if args.mutant else []
    scored = [name for name in ROWS if name in selected]
    binary = Path(args.app)
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    if args.mutant:
        print(f"mattes MT2/MT3 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test matte "
                  "--test matte_nest in the copy's core\n       " + " | ".join(last),
                  flush=True)
            scored.append("CT")
    else:
        print("mattes MT2/MT3 — the matte track end to end, over MCP", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    movie = make_movie()
    if movie is None:
        print("instrument failure: ffmpeg did not make the testsrc2 movie")
        return 2
    log = WORK / "instance.log"
    state = {}
    launched = launch(binary, log)
    closed = True
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        support = HOME / "Library/Application Support"
        if not support.is_dir():
            print(f"instrument failure: the scratch home did not take ({support})")
            return 2
        try:
            if selected & P_ROWS:
                closed = run_p(launched.client, movie, state) and closed
            if selected & L_ROWS:
                closed = run_l(launched.client, movie, state) and closed
            if selected & N_ROWS:
                closed = run_n(launched.client, movie, state) and closed
            if "N5" in selected:
                closed = run_n5(launched.client, movie, state) and closed
            if "N7" in selected:
                closed = run_n7(launched.client, state) and closed
            if selected & T_ROWS:
                closed = run_t(launched.client, state) and closed
            if "T1" in selected:
                closed = run_t1(launched.client, state) and closed
            if selected & S_ROWS:
                closed = run_s(launched.client, state) and closed
            if selected & E_ROWS:
                closed = run_e(launched.client, state) and closed
            if "F1" in selected:
                closed = run_f(launched.client, log, state) and closed
            if selected & D_ROWS:
                closed = run_d(launched.client, state) and closed
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("Z1 CONTROL: the projects close and the log holds no `Reelcut: ` line",
          closed and not found, f"closed {closed}; complaints {found}")
    print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    # A host skip (E3 on a Mac with no HEVC-with-alpha encoder) is named
    # where it happened and is not scored.
    scored = [name for name in scored if name not in state.get("skipped", [])]
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)}"
          + (f" (host skips: {', '.join(state['skipped'])})" if state.get("skipped") else ""))
    if args.mutant:
        missing = [name for name in named if name not in rows]
        fixtures = {key: value for key, value in state.items() if key.endswith("fixture")}
        if missing or False in fixtures.values():
            print(f"mutant {args.mutant}: the control could not be performed — rows not "
                  f"reached {missing}, fixtures {fixtures}")
            return 2
        survived = [name for name in named if rows.get(name)]
        failed = [name for name in scored if not rows.get(name)]
        caught = not survived
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{' '.join(named)} {'all FAILED' if caught else 'did not all fail'} in the "
              f"copy (failed: {', '.join(failed) or 'none'}; survived: "
              f"{', '.join(survived) or 'none'})")
        return 0 if caught else 1
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
