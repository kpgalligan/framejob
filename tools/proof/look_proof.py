#!/usr/bin/env python3
"""Road map "grading", phases GR5a and GR5b (spec §11 GR-7) — looks end to end
over MCP: `set_video {patch: {look: {kind, amount}}}`, the recipe's `look` (its
kind, amount and the core's definition), the GPU bake into a 33³ lattice and
step 4d at `texture(2)` behind `lookEnabled`, read back as `render_frame` bytes
and one export (GR5a); the Color sub-tab's Look section, its gallery's
thumbnails and Clip ▸ Look ▸ (GR5b); then the probe's rows over `app/Sources`
and the tree's shader.

    python3 tools/proof/look_proof.py [--app PATH] [--only D1,M1,...]
    python3 tools/proof/look_proof.py capture DIR      # the neutral control, before any product edit
    python3 tools/proof/look_proof.py compare DIR      # every row, and N0 against DIR
    python3 tools/proof/look_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/look/home`, and
every package, fixture and PNG is under `tools/proof/work/look/`, removed at
the start and at exit (the control folder DIR is not). It performs only
Clip ▸ Look ▸ items, which persist nothing. A scratch home does not move
`UserDefaults` (#238), so the sections GR5b reads are pinned by argument-domain
plist fragments (stored value: COLLAPSED) — `video.look` open, `video.light`
and `video.color` closed — and the inspector's width at 304 pt, and `-RCDevLookGalleryDump WORK/dump` has the
gallery write each completed generation; G3's second instance pins
`video.look` closed and dumps to `WORK/dump-closed`. Every call is bounded
(`CALL_BOUND`), every ffmpeg too (120 s). Every project is closed
(`close_project`, discard).

Fixtures, written by this script: CHART, a 640×360 PNG whose top half is a
grey ramp (column x is round(255·x/639)) and whose bottom half is six
saturated patches — red, green, blue, cyan, magenta, yellow; CARD, a 640×360
grey-128 PNG; MOVIE, a 2 s 640×360 30 fps ffmpeg `testsrc2` H.264 file.
Frames are taken at t = 0.5 s unless a row says otherwise, and compared at
SAMPLES (every 20th column of six rows, three in each half), ±1 a channel
unless a row says otherwise.

Projects, each 30 fps, 640×360: H (CHART), C (CARD), M (MOVIE, background
black).
- **N0** (`compare DIR` only; scored on Release, printed elsewhere): the
  neutral frames — chart, adjustment (the chart under a fresh adjustment
  clip), card, movie — decoded at 16 bits a channel are byte-identical to
  `capture DIR`'s, taken on the untouched tree's Release build.
- **R1** (H): `{look: {kind: warm, amount: 1.5}}` is refused by
  "video.look.amount must be between 0 and 1, not 1.5" and `{look: {kind:
  sepia}}` by `bad value at "look.kind" in a video patch: unknown variant
  `sepia`, expected one of …`; the project is unchanged.
- **K1** (H): the kinds R1's second sentence names, in its order, are the
  eight and `lut` (GR-8) the `set_video` catalog entry's look clause lists, in
  its order.
- **D1** (H): each of the eight at amount 1 differs from the neutral chart, and
  from each of the other seven, by more than 3 levels at some sample.
- **P1** (H): a save before any look holds no `look` key; a save with
  `{kind: vintage, amount: 0.8}` holds exactly `{"kind": "vintage", "amount":
  0.8}` as the clip's `video.look`, the group's last key.
- **A0** (H): `{kind: teal_orange, amount: 0}` renders the neutral chart's bytes.
- **M1** (H): `teal_orange` at amount 0.5 is within ±1 of the midpoint of the
  neutral chart and D1's `teal_orange` at every sample.
- **U2** (H): `{kind: vivid}` after M1 keeps the clip's amount 0.5 and renders
  neither M1's bytes nor D1's `vivid`; undo brings M1's bytes back, redo the
  `vivid` frame's.
- **U1** (H): `render_frame {ungraded: true}` of the chart under `vivid` is the
  neutral chart's bytes; so is the chart under an adjustment clip carrying
  `vivid` (J1's project).
- **J1** (H): `look: null` takes the chart back to its neutral bytes; then an
  adjustment clip on a new front track with `vivid` over the chart renders
  D1's `vivid` ±1 at every sample.
- **A1** (H): base `{kind: warm, amount: 0}` and a 1 s action from 0 s whose
  end is `{look: {amount: 1}}`: at 0.5 s every sample where neutral and D1's
  `warm` differ by more than 2 lies strictly between them, and at 1.5 s the
  frame is D1's `warm` bytes.
- **O1** (C): the card at temperature +0.5 under `black_white` has R = G = B
  ±1 at every sample (the look after tone), and the card at temperature +0.5
  alone does not.
- **X1** (M): `teal_orange` on the movie: the `prores_422` export's frame 15 is
  within ±8 of `render_frame` at every 16th pixel, and the looked frame differs
  from the neutral one by more than 10 somewhere.
- **L1–L5**: `look_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of all five), with the
  tree's `Compositor.metal` compiled by `makeLibrary(source:)` together with
  the probe's own kernels: L1 the 2³ placeholder and a neutral 33³ bake through
  `gradeLook` return all 16,777,216 8-bit colours as themselves; L2 the
  neutral bake's texels equal their coordinates; L3 `apply(look:)` (amount and
  flag) and `lookAmount` / `lookEnabled` at offsets 456 / 460 of 512 (464 until
  grading-2 G2-2's wheels group); L4
  (RECORD, unscored) the eight bakes' milliseconds; L5 `teal_orange`'s
  lattice (its definition read off the core's recipe) answers B > R at grey
  0.2 and R > B at grey 0.8.
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Reelcut: ` line (either instance's).

GR5b — project MG, 30 fps 640×360: MOVIE at 0 with `{warm, 0.5}` and IM (CARD)
at 2 s on the first track, TX (a text clip) at 2 s on a second, AJ (an
adjustment clip) over 0–4 s on a third; saved as MG (and, after the rows, with
IM at `{cool, 0.5}`, as MG-cool) for the probe and G3. MOVIE selected, the
playhead at 0.5 s, `select_inspector_tab {clip, color}`:
- **G1**: the first manifest naming [MOVIE] at t 0.5 s (≤ 30 s): per tile, the
  click's `set_video` then `render_frame {t, max_width: 256}` is BYTE-identical
  to its PNG (`undo` after each applied one); the nine pairwise differ.
- **G2**: no new generation in 1.5 s unchanged; `set_playhead 1.0 s` → a
  generation at 1.0 s; the playhead at the clip's end → one at its start (0).
- **S1**: `section: video.look`, once not pending: the inspector's layout dump
  holds the nine names in reading order (3 rows by y, 3 by x), each inside the
  captured inspector, and no layout problem on a gallery view; `section:
  video.nothing` is refused naming the held ids.
- **S2**: MOVIE alone shows "Amount" and a field "50%"; MOVIE + IM no
  "Amount"; CONTROL: IM alone none.
- **LM1**: MOVIE + IM, Clip ▸ Look ▸ Vivid: `{vivid, 0.5}`, `{vivid, 1}`;
  `undo` answers "Look" and restores both. **LM2**: … ▸ None removes both;
  `undo` restores. **LM3**: TX alone refused "is disabled here", unchanged;
  CONTROL: AJ alone, Faded lands `{faded, 1}`. (The spec's M1–M3, renamed:
  GR5a already has an M1.)
- **G3**: a second instance with `video.look` pinned closed, MG open, the same
  selection, playhead and sub-tab, 3 s: no generation and no pending key.
  CONTROL: G1's instance made one.
- **B1–B4**: `look_probe.swift` (one build with L1–L5): B1 `lookMenu()` is the
  eight names, a separator, None, tags 0…7 and −1, no key equivalents, and
  Clip ▸ Look follows Motion in the main menu; B2 the validator's checkmarks,
  dashes and enabling over MG and MG-cool; B3 `summary`, `shared`, `time` and
  `op` on fixed inputs; B4 the Color sections (Light, Color, Wheels, Curves,
  Look since grading-2 G2-3), a Warm and a None tile's one
  `set_video` named "Look" and the outlines, in a headless `ClipPane`.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it, the probe built
over the copy's `app/Sources` and its shader. A core mutant also runs `cargo
test --release --no-fail-fast --test look --test ungraded` in the copy's own
`core/` (row CT). MUTANT PASS when every named row FAILED and no other scored
row did:
  look-before-tone          step 4d moved before 4c: O1
  amount-ignored            `lookAmount` always 1: M1 A1 U2 L3
  ungraded-keeps-look       the `ungraded` option keeps the look: U1 CT
  adjustment-ignores-look   the adjustment pass has no step 4d: J1
  amount-range-dropped      the amount's range check gone: R1 CT
  split-ignored             the bake skips the split tone: L5
  kindless-look-kept        `evaluate_clip`'s look guard gone: CT
  kind-drops-amount         `LookGallery.op` adds amount 1: G1 LM1 B3 B4
  menu-no-dash              the validator's .mixed is .off: B2
  gallery-ignores-playhead  the thumbnail time is the clip's start: G1 G2 B3
  renders-while-closed      the gallery is open whenever in a window: G3
  amount-row-always         the Amount row for any selection: S2
  thumbnail-not-click       the trial op adds amount 1: G1
  adjustment-not-a-target   an adjustment clip takes no look: LM3 B2
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
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from hevc_alpha_proof import own_core  # noqa: E402
from tone_proof import Frame, decode, same_pixels, write_png  # noqa: E402

WORK = ROOT / "tools/proof/work/look"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/look_probe.swift"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
T = SEC // 2
W, H = 640, 360
GREY = 128
KINDS = ["warm", "cool", "teal_orange", "vivid", "faded", "vintage", "dramatic", "black_white"]
PATCHES = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (0, 255, 255), (255, 0, 255), (255, 255, 0)]
SAMPLES = [(x, y) for y in (40, 90, 140, 220, 270, 320) for x in range(10, W, 20)]
NEUTRAL = ["chart", "adjustment", "card", "movie"]
ROWS = ["N0", "R1", "K1", "D1", "P1", "A0", "M1", "U2", "U1", "J1", "A1", "O1", "X1",
        "G1", "G2", "S1", "S2", "LM1", "LM2", "LM3", "G3",
        "L1", "L2", "L3", "L4", "L5", "B1", "B2", "B3", "B4", "Z1"]
RECORDS = {"L4"}
H_ROWS = {"R1", "K1", "D1", "P1", "A0", "M1", "U2", "U1", "J1", "A1"}
C_ROWS = {"O1"}
M_ROWS = {"X1"}
L_ROWS = {"L1", "L2", "L3", "L4", "L5"}
MG_ROWS = {"G1", "G2", "S1", "S2", "LM1", "LM2", "LM3"}
B_ROWS = {"B1", "B2", "B3", "B4"}
# The rows that need project MG built (and its two packages saved).
MG_NEEDED = MG_ROWS | {"G3", "B2", "B3", "B4"}
DUMP = WORK / "dump"
DUMP_CLOSED = WORK / "dump-closed"
MG = WORK / "MG.reelcut"
MG_COOL = WORK / "MG-cool.reelcut"
LOOK_MENU = ["Clip", "Look"]
DISABLED = "is disabled here"
TILE_NAMES = ["None", "Warm", "Cool", "Teal & Orange", "Vivid", "Faded", "Vintage", "Dramatic",
              "Black & White"]
GALLERY = "app/Sources/LookGallery.swift"


def pins(closed, dump):
    """The argument-domain pins (stored value: COLLAPSED), the inspector's
    width (screens.py's 304, so the gallery's rows do not follow a width the
    domain holds), and the dump folder."""
    return ["-ReelcutInspectorWidth", "<real>304</real>",
            "-ReelcutInspectorSection.video.look", "<true/>" if closed else "<false/>",
            "-ReelcutInspectorSection.video.light", "<true/>",
            "-ReelcutInspectorSection.video.color", "<true/>",
            "-RCDevLookGalleryDump", str(dump)]


SHADER = "app/Resources/Shaders/Compositor.metal"
STEP_4D = ("        // (4d) The look (spec §11 GR-7): once per pixel, right after tone and\n"
           "        // before the point filters. Behind `lookEnabled`, so a look-less layer\n"
           "        // never samples `texture(2)`.\n"
           "        if (u.lookEnabled > 0.5) {\n"
           "            rgb = gradeLook(rgb, look, samp, u);\n"
           "        }\n\n")
STEP_4C = "        // (4c) Tone (spec §11 GR-2): once per pixel, after the regions' own\n"
ADJUST_4D = ("    if (u.lookEnabled > 0.5) {\n"
             "        c = gradeLook(c, look, samp, u);\n"
             "    }\n")
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "look-before-tone": ([
        (SHADER, STEP_4D, ""),
        (SHADER, STEP_4C, STEP_4D + STEP_4C)], ["O1"]),
    "amount-ignored": ([(
        "app/Sources/LookProps.swift",
        "lookAmount = Float(min(max(amount, 0), 1))",
        "lookAmount = 1")], ["M1", "A1", "U2", "L3"]),
    "ungraded-keeps-look": ([(
        "core/src/recipe.rs",
        "            moved.look = None;\n",
        "")], ["U1", "CT"]),
    "adjustment-ignores-look": ([(SHADER, ADJUST_4D, "")], ["J1"]),
    "amount-range-dropped": ([(
        "core/src/props_check.rs",
        "        in_range(\"video.look.amount\", look.amount, 0.0, 1.0)?;\n",
        "")], ["R1", "CT"]),
    "split-ignored": ([(
        SHADER,
        "        c = lookSplitTone(c, b);\n",
        "")], ["L5"]),
    "kindless-look-kept": ([(
        "core/src/actions.rs",
        "            if video\n"
        "                .get(\"look\")\n"
        "                .is_some_and(|look| !look.is_null() && !self.evaluates_as_look(look))\n"
        "            {\n"
        "                video.insert(\"look\".to_string(), Value::Null);\n"
        "            }\n",
        "")], ["CT"]),
    "kind-drops-amount": ([(
        GALLERY,
        "kind.map { LookPatch(kind: $0) }",
        "kind.map { LookPatch(kind: $0, amount: 1) }")], ["G1", "LM1", "B3", "B4"]),
    "menu-no-dash": ([(
        "app/Sources/EditorViewController+Look.swift",
        "carrying == targets.count ? .on : .mixed",
        "carrying == targets.count ? .on : .off")], ["B2"]),
    "gallery-ignores-playhead": ([(
        GALLERY,
        "first.start <= playhead && playhead < first.end ? playhead : first.start",
        "first.start")], ["G1", "G2", "B3"]),
    "renders-while-closed": ([(
        "app/Sources/LookGalleryView.swift",
        "open: window != nil && !isHiddenOrHasHiddenAncestor)",
        "open: window != nil)")], ["G3"]),
    "amount-row-always": ([(
        "app/Sources/VideoPane+Look.swift",
        "rows += allLooked ? [",
        "rows += true ? [")], ["S2"]),
    "thumbnail-not-click": ([(
        GALLERY,
        "inputs.project.applying(Self.op(tile, clips: inputs.ids))",
        "inputs.project.applying(.setVideo(clips: inputs.ids, patch: VideoPatch(look: "
        ".some(tile.map { LookPatch(kind: $0, amount: 1) }))))")], ["G1"]),
    "adjustment-not-a-target": ([(
        GALLERY,
        "(InspectorTab.hasSourcePixels($0, in: snapshot) || InspectorTab.isAdjustment($0))",
        "InspectorTab.hasSourcePixels($0, in: snapshot)")], ["LM3", "B2"]),
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


# ---- pixels -------------------------------------------------------------------

def write_chart(path):
    """CHART: the grey ramp over the six saturated patches, 8-bit RGB."""
    def pixel(x, y):
        if y < H // 2:
            v = round(255 * x / (W - 1))
            return (v, v, v)
        return PATCHES[min(x * len(PATCHES) // W, len(PATCHES) - 1)]

    raw = b"".join(bytes([0]) + b"".join(bytes(pixel(x, y)) for x in range(W))
                   for y in range(H))

    def chunk(kind, data):
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return path


def spread(a, b):
    """The largest channel difference between two frames over SAMPLES."""
    if a is None or b is None:
        return -1
    return max(max(abs(p - q) for p, q in zip(a.px(x, y), b.px(x, y))) for x, y in SAMPLES)


def close_to(got, want, tolerance=1.0):
    return all(abs(a - b) <= tolerance for a, b in zip(got, want))


# ---- the documents ------------------------------------------------------------

class Doc:
    """One open project and the calls the rows make on it."""

    def __init__(self, client, path):
        self.client, self.path = client, path

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=str(self.path)))

    def project(self):
        return reply(self.call("get_project")).get("project") or {}

    def tracks(self):
        return self.project().get("tracks") or []

    def clips(self):
        return self.project().get("clips") or []

    def clip(self, clip):
        return next((c for c in self.clips() if c.get("id") == clip), {})

    def new_track(self):
        before = {t.get("id") for t in self.tracks()}
        self.call("add_track")
        made = [t.get("id") for t in self.tracks() if t.get("id") not in before]
        return made[0] if len(made) == 1 else None

    def added(self, tool, **arguments):
        """`tool` that places one clip; its id, or None."""
        before = {c["id"] for c in self.clips()}
        got = self.call(tool, **arguments)
        new = [c["id"] for c in self.clips() if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def media(self, path):
        return reply(self.call("import_media", path=str(path))).get("media")

    def look(self, clips, look):
        return self.call("set_video", clips=clips, patch={"look": look})

    def frame(self, tag, t=T, **options):
        """`render_frame` at `t`, decoded; a Frame, or None."""
        out = WORK / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = self.call("render_frame", t=t, path=str(out), **options)
        raw = decode(out, W, H) if got["ok"] and out.exists() else None
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        return Frame(out, raw, W)


def opened(client, name, background=None):
    """A new 640 × 360 project at `name` holding `media`'s one clip on its
    first track; (Doc, sized)."""
    path = WORK / f"{name}.reelcut"
    made = attempt(client, "new_project", {"path": str(path)})
    doc = Doc(client, path)
    arguments = {"width": W, "height": H, "fps": [30, 1]}
    if background is not None:
        arguments["background"] = background
    doc.call("set_canvas", **arguments)
    c = doc.project().get("canvas") or {}
    return doc, made["ok"] and c.get("width") == W and c.get("height") == H


def placed(doc, fixture):
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(fixture)
    return doc.added("add_clip", track=track, media=media, at=0) if media is not None else None


def close(client, path):
    return attempt(client, "close_project", {"project": str(path), "discard": True})["ok"]


def fixtures():
    chart = write_chart(WORK / "chart.png")
    card = write_png(WORK / "card.png", W, H, lambda x: GREY)
    movie = WORK / "testsrc2.mp4"
    made = bounded.run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
                        f"testsrc2=size={W}x{H}:rate=30:duration=2",
                        "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)], 120)
    return chart, card, (movie if made["rc"] == 0 and movie.exists() else None)


# ---- N0: the neutral frames ---------------------------------------------------

class Neutral:
    """Where the neutral frames go: `capture` writes them to DIR, `compare`
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
            want = decode(self.folder / f"{name}.png", W, H, deep=True)
            got = decode(frame.path, W, H, deep=True)
            if want is None or got is None:
                self.misses.append(f"{name}: {'no control' if want is None else 'no decode'}")
            elif want != got:
                differ = sum(1 for i in range(0, len(got), 2) if got[i:i + 2] != want[i:i + 2])
                self.misses.append(f"{name}: {differ} of {len(got) // 2} 16-bit samples differ")
        return frame


# ---- project H: the chart ----------------------------------------------------

def saved_look(path, clip):
    """The clip's `video` group keys and its `look` in the package's
    `project.json`, and the file's text."""
    text = (Path(path) / "project.json").read_text()
    body = json.loads(text)
    found = next((c for c in body.get("clips", []) if c.get("id") == clip), {})
    video = found.get("video") or {}
    return list(video.keys()), video.get("look"), text


def catalog_kinds(client):
    """The kinds the `set_video` entry's look clause lists, in its order."""
    try:
        tool = client.schemas().get("set_video") or {}
    except Exception as error:  # an expiry is an answer
        return None, f"{type(error).__name__}: {error}"
    text = (((tool.get("inputSchema") or {}).get("properties") or {}).get("patch") or {}) \
        .get("description", "")
    found = re.search(r"look \(null, or \{kind: ([a-z_|]+)", text)
    return (found.group(1).split("|") if found else None), text[:120]


def run_h(client, chart, neutral, state):
    doc, sized = opened(client, "H")
    clip = placed(doc, chart)
    base = neutral.take(doc, "chart")
    corner = base.px(W - 1, 10) if base is not None else None
    patch = base.px(W // 12, 300) if base is not None else None
    fixture = (sized and clip is not None and base is not None
               and corner == (255, 255, 255) and close_to(patch, (255, 0, 0), 2))
    print(f"  H: chart clip {clip}; ramp end {corner}, red patch {patch}", flush=True)
    if fixture:
        front = doc.new_track()
        adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
            if front is not None else None
        fixture = adjustment is not None and neutral.take(doc, "adjustment") is not None
        fixture = fixture and doc.call("remove_track", track=front, with_clips=True)["ok"]
    state["h_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture
    ids = [clip]

    # R1, K1
    before = doc.project()
    over = doc.look(ids, {"kind": "warm", "amount": 1.5})
    unknown = doc.look(ids, {"kind": "sepia"})
    unchanged = doc.project() == before
    for got in (over, unknown):  # a value accepted in error is taken back
        if got["ok"]:
            doc.call("undo")
    want_over = "video.look.amount must be between 0 and 1, not 1.5"
    want_unknown = 'bad value at "look.kind" in a video patch: unknown variant `sepia`'
    error = unknown.get("error", "")
    check("R1 amount 1.5 and kind sepia are refused by their sentences; the project is "
          "unchanged", not over["ok"] and want_over in over.get("error", "")
          and not unknown["ok"] and want_unknown in error and unchanged,
          f"amount {over.get('error') or 'accepted'!r}; kind {error or 'accepted'!r}; "
          f"unchanged {unchanged}")
    core = re.findall(r"`([a-z_]+)`", error.split("expected one of", 1)[-1]) \
        if "expected one of" in error else None
    listed, start = catalog_kinds(client)
    check("K1 the core's kinds (R1's sentence) are the catalog's look clause's, in order, "
          "and are the eight and lut (GR-8)",
          core is not None and core == listed and core == KINDS + ["lut"],
          f"core {core}; catalog {listed} ({start!r})")

    # P1 (the look-less half)
    plain_path = WORK / "H-plain.reelcut"
    saved_plain = doc.call("save_project", path=str(plain_path))
    doc.path = plain_path
    try:
        _, plain_look, plain_text = saved_look(plain_path, clip)
    except (OSError, ValueError):
        plain_look, plain_text = None, "unreadable"

    # D1
    looked = {}
    for kind in KINDS:
        got = doc.look(ids, {"kind": kind, "amount": 1})
        looked[kind] = doc.frame(f"d1-{kind}") if got["ok"] else None
    against_none = {kind: spread(frame, base) for kind, frame in looked.items()}
    pairs = [(a, b, spread(looked[a], looked[b])) for i, a in enumerate(KINDS)
             for b in KINDS[i + 1:]]
    close_pairs = [(a, b, d) for a, b, d in pairs if d <= 3]
    check("D1 each of the eight differs from the neutral chart and from each other by more "
          "than 3 levels at some sample",
          all(d > 3 for d in against_none.values()) and not close_pairs,
          f"against none {against_none}; pairs within 3 {close_pairs}; smallest pair "
          f"{min(pairs, key=lambda p: p[2]) if pairs else None}")

    # P1 (the looked half)
    set_vintage = doc.look(ids, {"kind": "vintage", "amount": 0.8})
    looked_path = WORK / "H-looked.reelcut"
    saved_looked = doc.call("save_project", path=str(looked_path))
    doc.path = looked_path
    try:
        keys, look, _ = saved_look(looked_path, clip)
    except (OSError, ValueError):
        keys, look = [], None
    check("P1 a save with no look holds no look key; with {vintage, 0.8} the clip's "
          "video.look is exactly {kind: vintage, amount: 0.8}, the group's last key",
          saved_plain["ok"] and saved_looked["ok"] and set_vintage["ok"]
          and plain_look is None and '"look"' not in plain_text
          and look == {"kind": "vintage", "amount": 0.8}
          and list(look.keys()) == ["kind", "amount"] and keys[-1:] == ["look"],
          f"plain look {plain_look}; looked {look}; keys {keys}")

    # A0
    zero = doc.look(ids, {"kind": "teal_orange", "amount": 0})
    a0 = doc.frame("a0")
    check("A0 teal_orange at amount 0 renders the neutral chart's bytes",
          zero["ok"] and same_pixels(a0, base), f"set {zero.get('error', 'ok')}")

    # M1
    half = doc.look(ids, {"kind": "teal_orange", "amount": 0.5})
    m1 = doc.frame("m1")
    full = looked.get("teal_orange")
    misses = []
    if m1 is not None and full is not None:
        for x, y in SAMPLES:
            want = [(p + q) / 2 for p, q in zip(base.px(x, y), full.px(x, y))]
            if not close_to(m1.px(x, y), want):
                misses.append((x, y, m1.px(x, y), want))
    check("M1 teal_orange at amount 0.5 is within ±1 of the midpoint of none and full at "
          "every sample", half["ok"] and m1 is not None and full is not None and not misses
          and spread(base, full) > 3,
          f"set {half.get('error', 'ok')}; {misses[:3] or 'all within'}")

    # U2
    vivid = doc.look(ids, {"kind": "vivid"})
    u2_set = doc.frame("u2-set")
    undone = doc.call("undo")
    u2_undone = doc.frame("u2-undone")
    redone = doc.call("redo")
    u2_redone = doc.frame("u2-redone")
    want_vivid = looked.get("vivid")
    amount = ((doc.clip(clip).get("video") or {}).get("look") or {}).get("amount")
    check("U2 {kind: vivid} keeps the clip's amount 0.5 and renders vivid at 0.5; undo "
          "brings M1's bytes back, redo vivid's",
          vivid["ok"] and undone["ok"] and redone["ok"] and amount == 0.5
          and same_pixels(u2_undone, m1) and same_pixels(u2_redone, u2_set)
          and not same_pixels(u2_set, m1) and not same_pixels(u2_set, want_vivid),
          f"set {vivid.get('error', 'ok')}; amount {amount}; undo "
          f"{same_pixels(u2_undone, m1)}; redo {same_pixels(u2_redone, u2_set)}")

    # U1 (the clip's look), J1, U1 (the adjustment clip's)
    full_vivid = doc.look(ids, {"kind": "vivid", "amount": 1})
    u1_clip = doc.frame("u1-clip", ungraded=True)
    clip_ok = full_vivid["ok"] and same_pixels(u1_clip, base)
    removed = doc.look(ids, None)
    j0 = doc.frame("j1-removed")
    gone = "look" not in (doc.clip(clip).get("video") or {})
    front = doc.new_track()
    adjustment = doc.added("add_adjustment_clip", track=front, at=0, duration=2 * SEC) \
        if front is not None else None
    adjust_set = doc.look([adjustment], {"kind": "vivid"}) if adjustment else {"ok": False}
    j1 = doc.frame("j1")
    j_misses = [(x, y, j1.px(x, y), want_vivid.px(x, y)) for x, y in SAMPLES
                if j1 is not None and want_vivid is not None
                and not close_to(j1.px(x, y), want_vivid.px(x, y))]
    check("J1 look null takes the chart back to its bytes; an adjustment clip with vivid "
          "over it renders D1's vivid ±1 at every sample",
          removed["ok"] and gone and same_pixels(j0, base) and adjust_set["ok"]
          and j1 is not None and want_vivid is not None and not j_misses,
          f"null {removed.get('error', 'ok')} (gone {gone}, bytes {same_pixels(j0, base)}); "
          f"adjustment {adjustment} {adjust_set.get('error', 'ok')}; "
          f"{j_misses[:3] or 'all within'}")
    u1_adjust = doc.frame("u1-adjustment", ungraded=True)
    adjust_ok = adjust_set["ok"] and same_pixels(u1_adjust, base)
    check("U1 render_frame {ungraded: true} removes the clip's look and the adjustment "
          "clip's (both the neutral chart's bytes)", clip_ok and adjust_ok,
          f"clip {clip_ok}; adjustment {adjust_ok}")
    doc.call("remove_track", track=front, with_clips=True)

    # A1
    based = doc.look(ids, {"kind": "warm", "amount": 0})
    added = doc.call("add_action", clip=clip, at=0, duration=SEC)
    actions = doc.clip(clip).get("actions") or []
    action = actions[0].get("id") if len(actions) == 1 else None
    ended = doc.call("set_action_end", clip=clip, action=action,
                     patch={"video": {"look": {"amount": 1}}}) if action else {"ok": False}
    mid = doc.frame("a1-mid", t=SEC // 2)
    end = doc.frame("a1-end", t=SEC + SEC // 2)
    warm = looked.get("warm")
    moving, outside = 0, []
    if mid is not None and warm is not None:
        for x, y in SAMPLES:
            for c, (n, f, m) in enumerate(zip(base.px(x, y), warm.px(x, y), mid.px(x, y))):
                if abs(f - n) > 2:
                    moving += 1
                    if not min(n, f) < m < max(n, f):
                        outside.append((x, y, c, n, m, f))
    check(f"A1 a 1 s action from amount 0 to 1: mid-span strictly between none and warm at "
          f"the {moving} moving samples, and its end is D1's warm bytes",
          based["ok"] and added["ok"] and ended["ok"] and moving > 0 and not outside
          and same_pixels(end, warm),
          f"base {based.get('error', 'ok')}; end {ended.get('error', 'ok')}; outside "
          f"{outside[:3]}; end bytes {same_pixels(end, warm)}")
    return close(client, doc.path)


# ---- project C: the card -----------------------------------------------------

def run_c(client, card, neutral, state):
    doc, sized = opened(client, "C")
    clip = placed(doc, card)
    base = neutral.take(doc, "card")
    v = base.px(W // 2, H // 2)[0] if base is not None else None
    fixture = sized and clip is not None and base is not None and all(
        base.px(x, y) == (v, v, v) for x, y in SAMPLES)
    state["c_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # O1
    warmed = doc.call("set_video", clips=[clip], patch={"color": {"temperature": 0.5}})
    warm = doc.frame("o1-warm")
    grey = doc.look([clip], {"kind": "black_white"})
    o1 = doc.frame("o1")
    tinted = warm is not None and warm.px(W // 2, H // 2)[0] > warm.px(W // 2, H // 2)[2] + 2
    flat = [(x, y, o1.px(x, y)) for x, y in SAMPLES if o1 is not None
            and max(o1.px(x, y)) - min(o1.px(x, y)) > 1]
    check("O1 the card at temperature +0.5 under black_white has R = G = B ±1 at every "
          f"sample (the look after tone; warm alone {warm.px(W // 2, H // 2) if warm else None})",
          warmed["ok"] and grey["ok"] and tinted and o1 is not None and not flat,
          f"set {warmed.get('error', 'ok')}, {grey.get('error', 'ok')}; coloured "
          f"{flat[:3]}")
    return close(client, doc.path)


# ---- project M: the movie and an export --------------------------------------

def decoded(movie, n):
    """Frame `n` of `movie` as RGBA bytes; (None, why)."""
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{n})",
             "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo", "-pix_fmt",
             "rgba", "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"ffmpeg: {error}"
    return (raw, n) if len(raw) == W * H * 4 else (None, "no frame decoded")


def run_m(client, movie, neutral, state):
    doc, sized = opened(client, "M", background=[0, 0, 0, 1])
    clip = placed(doc, movie)
    base = neutral.take(doc, "movie")
    fixture = sized and clip is not None and base is not None
    state["m_fixture"] = fixture
    if neutral.mode == "capture" or not fixture:
        return close(client, doc.path) and fixture

    # X1
    up = doc.look([clip], {"kind": "teal_orange"})
    x1 = doc.frame("x1")
    out = WORK / "X1.mov"
    exported = doc.call("export", preset="prores_422", path=str(out), size="document")
    raw, which = decoded(out, 15) if exported["ok"] and out.exists() else (None, "no file")
    samples = [(x, y) for y in range(0, H, 16) for x in range(0, W, 16)]
    misses = []
    if raw is not None and x1 is not None:
        exported_frame = Frame(out, raw, W)
        misses = [(x, y, exported_frame.px(x, y), x1.px(x, y)) for x, y in samples
                  if not close_to(exported_frame.px(x, y), x1.px(x, y), 8)]
    differs = x1 is not None and max(
        max(abs(a - b) for a, b in zip(x1.px(x, y), base.px(x, y))) for x, y in samples) > 10
    check(f"X1 the prores_422 export's frame {which} is within ±8 of render_frame at "
          f"{len(samples)} samples, and the looked frame differs from the neutral by > 10",
          up["ok"] and exported["ok"] and raw is not None and x1 is not None and not misses
          and differs,
          f"set {up.get('error', 'ok')}; export {exported.get('error', 'ok')}; "
          f"{misses[:3] or 'all within'}; differs {differs}")
    return close(client, doc.path)


# ---- GR5b: project MG, the Look section and Clip ▸ Look ▸ -------------------

def manifests(folder):
    """The dump's completed generations, oldest first: each manifest with its
    folder under `dir`."""
    found = []
    for path in Path(folder).glob("*/manifest.json"):
        try:
            body = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        body["dir"] = path.parent
        found.append(body)
    return sorted(found, key=lambda m: m.get("generation", 0))


def wait_manifest(folder, want, within):
    """The first manifest `want` accepts, waiting up to `within` s; or None."""
    deadline = time.monotonic() + within
    while True:
        hit = next((m for m in manifests(folder) if want(m)), None)
        if hit is not None or time.monotonic() > deadline:
            return hit
        time.sleep(0.25)


def pending(doc):
    return "look_thumbnails_pending" in reply(doc.call("select_inspector_tab"))


def settled(doc, within=30):
    """Waits until the answer names no pending thumbnails; whether it did."""
    deadline = time.monotonic() + within
    while pending(doc):
        if time.monotonic() > deadline:
            return False
        time.sleep(0.25)
    return True


def layout(doc, tag):
    """The inspector's `snapshot_ui` layout dump: (the dump, the error)."""
    got = doc.call("snapshot_ui", window="editor", view="inspector",
                   path=str(WORK / f"{tag}.png"))
    path = reply(got).get("layout_path")
    if not path:
        return {}, got.get("error", "no layout dump")
    with open(path) as handle:
        return json.load(handle), ""


def visible_texts(views):
    return {v.get("text") for v in views if not v.get("hidden")}


def under(views, index, kinds):
    """Whether view `index` is, or sits inside, a view of a class in `kinds`."""
    by_index = {v.get("i"): v for v in views}
    view = by_index.get(index)
    while view is not None:
        if view.get("class") in kinds:
            return True
        view = by_index.get(view.get("parent"))
    return False


def looks_of(doc, clips):
    return [((doc.clip(c).get("video") or {}).get("look")) for c in clips]


def perform(doc, *path):
    return doc.call("perform_menu_item", path=list(LOOK_MENU + list(path)))


def run_mg(client, movie, card, state):
    """Project MG: MOVIE {warm, 0.5} at 0 and IM at 2 s on the first track, TX
    on a second, AJ over 0–4 s on a third; saved to MG (and, with IM at {cool,
    0.5}, to MG-cool) for the probe's B rows and G3's instance."""
    doc, sized = opened(client, "MG")
    track = (doc.tracks() or [{}])[0].get("id")
    mv = placed(doc, movie)
    warm = doc.look([mv], {"kind": "warm", "amount": 0.5}) if mv else {"ok": False}
    media = doc.media(card)
    im = doc.added("add_clip", track=track, media=media, at=2 * SEC) if media is not None \
        else None
    second = doc.new_track()
    tx = doc.added("add_text_clip", track=second, at=2 * SEC, duration=SEC) if second else None
    third = doc.new_track()
    aj = doc.added("add_adjustment_clip", track=third, at=0, duration=4 * SEC) if third else None
    saved = doc.call("save_project", path=str(MG))
    doc.path = MG
    clips = {"movie": mv, "image": im, "text": tx, "adjustment": aj}
    state["mg_fixture"] = (sized and warm["ok"] and None not in clips.values() and saved["ok"])
    state["mg_clips"] = clips
    print(f"  MG: clips {clips}; saved {saved.get('error', 'ok')}", flush=True)
    if not state["mg_fixture"]:
        return close(client, doc.path) and False
    if selected & MG_ROWS:
        run_mg_rows(doc, clips, state)
    cooled = doc.look([im], {"kind": "cool", "amount": 0.5})
    saved = doc.call("save_project", path=str(MG_COOL))
    doc.path = MG_COOL
    state["mg_fixture"] = cooled["ok"] and saved["ok"]
    return close(client, doc.path)


def run_mg_rows(doc, clips, state):
    mv, im, tx, aj = clips["movie"], clips["image"], clips["text"], clips["adjustment"]
    names = ["none"] + KINDS

    # G1
    doc.call("set_selection", clips=[mv])
    doc.call("set_playhead", t=T)
    tabs = reply(doc.call("select_inspector_tab", tab="clip", sub_tab="color"))
    first = wait_manifest(DUMP, lambda m: m.get("clips") == [mv], 30)
    state["g1_generation"] = first is not None
    found = wait_manifest(DUMP, lambda m: m.get("clips") == [mv] and m.get("t") == T, 30)
    misses, dumped = [], {}
    if found is not None:
        folder = found["dir"]
        for name in names:
            png = folder / f"{name}.png"
            dumped[name] = png.read_bytes() if png.exists() else None
            got = doc.look([mv], None if name == "none" else {"kind": name})
            same = not got["ok"] and "made no change" in got.get("error", "")
            out = WORK / f"g1-{name}.png"
            rendered = doc.call("render_frame", t=T, max_width=256, path=str(out))
            mine = out.read_bytes() if rendered["ok"] and out.exists() else None
            if got["ok"]:
                doc.call("undo")
            if not (got["ok"] or same) or mine is None or mine != dumped[name]:
                misses.append(f"{name}: set {got.get('error', 'ok')[:60]}, render "
                              f"{rendered.get('error', 'ok')[:60]}, bytes "
                              f"{'equal' if mine == dumped[name] else 'differ'}")
    blobs = [b for b in dumped.values() if b is not None]
    distinct = len(blobs) == 9 and len(set(blobs)) == 9
    check("G1 the first generation naming [MOVIE] at 0.5 s: each tile's PNG is BYTE-identical "
          "to the click's set_video then render_frame {t, max_width: 256}; the nine differ",
          tabs.get("sub_tab") == "color" and found is not None and not misses and distinct,
          f"tab {tabs.get('sub_tab')}; generation "
          f"{found.get('generation') if found else None}; misses {misses[:3]}; distinct "
          f"{len(set(blobs))} of {len(blobs)}")

    # G2
    quiet = settled(doc)
    before = [m.get("generation") for m in manifests(DUMP)]
    time.sleep(1.5)
    after = [m.get("generation") for m in manifests(DUMP)]
    still = before == after and not pending(doc)
    doc.call("set_playhead", t=2 * T)
    later = wait_manifest(DUMP, lambda m: m.get("generation", 0) > max(after or [0])
                          and m.get("t") == 2 * T, 30)
    clip = doc.clip(mv)
    end = (clip.get("start") or 0) + (clip.get("duration") or 0)
    seen = [m.get("generation") for m in manifests(DUMP)]
    doc.call("set_playhead", t=end)
    start = wait_manifest(DUMP, lambda m: m.get("generation", 0) > max(seen or [0])
                          and m.get("t") == clip.get("start"), 30)
    check("G2 no new generation in 1.5 s unchanged; the playhead at 1.0 s renders at 1.0 s; "
          "at the clip's end, at its start",
          quiet and still and later is not None and start is not None,
          f"settled {quiet}; generations {before} → {after}; 1.0 s "
          f"{later.get('generation') if later else None}; end {end} → start "
          f"{start.get('generation') if start else None}")

    # S1
    shown = reply(doc.call("select_inspector_tab", tab="clip", sub_tab="color",
                           section="video.look"))
    quiet = settled(doc)
    dump, error = layout(doc, "s1")
    views = dump.get("views") or []
    root = views[0]["frame"] if views else [0, 0, 0, 0]
    labels = [v for v in views if v.get("class") == "NSTextField" and not v.get("hidden")
              and v.get("text") in TILE_NAMES and under(views, v["i"], {"LookTileButton"})]
    read = [v["text"] for v in sorted(labels, key=lambda v: (round(v["frame"][1]),
                                                              v["frame"][0]))]
    rows_y = sorted({round(v["frame"][1]) for v in labels})
    inside = all(v["frame"][0] >= root[0] - 0.5 and v["frame"][1] >= root[1] - 0.5
                 and v["frame"][0] + v["frame"][2] <= root[0] + root[2] + 0.5
                 and v["frame"][1] + v["frame"][3] <= root[1] + root[3] + 0.5 for v in labels)
    problems = [p for p in dump.get("problems") or []
                if under(views, p.get("view"), {"LookGalleryView", "LookTileButton"})]
    refused = doc.call("select_inspector_tab", section="video.nothing")
    want = ("The shown pane has no section video.nothing; its sections are video.light, "
            "video.color, video.look.")
    check("S1 section video.look: the nine names in reading order (3 rows by y, 3 by x), each "
          "inside the captured inspector, no layout problem on the gallery; video.nothing is "
          "refused naming the held ids",
          shown.get("sub_tab") == "color" and quiet and not error and read == TILE_NAMES
          and len(rows_y) == 3 and inside and not problems and not refused["ok"]
          and want in refused.get("error", ""),
          f"settled {quiet}; dump {error or 'ok'}; read {read}; rows {rows_y}; inside {inside}; "
          f"problems {problems[:2]}; refusal {refused.get('error', 'ACCEPTED')!r}")

    # S2
    seen = {}
    for name, selection in (("MOVIE", [mv]), ("MOVIE + IM", [mv, im]), ("IM", [im])):
        doc.call("set_selection", clips=selection)
        doc.call("select_inspector_tab", tab="clip", sub_tab="color")
        dump, error = layout(doc, "s2-" + name.replace(" + ", "-"))
        seen[name] = visible_texts(dump.get("views") or []) if not error else {error}
    check("S2 MOVIE alone shows \"Amount\" and a field \"50%\"; MOVIE + IM no \"Amount\"; "
          "CONTROL: IM alone none",
          "Amount" in seen["MOVIE"] and "50%" in seen["MOVIE"]
          and "Amount" not in seen["MOVIE + IM"] and "Amount" not in seen["IM"],
          f"MOVIE Amount {'Amount' in seen['MOVIE']}, 50% {'50%' in seen['MOVIE']}; "
          f"MOVIE + IM {'Amount' in seen['MOVIE + IM']}; IM {'Amount' in seen['IM']}")

    # LM1, LM2
    doc.call("set_selection", clips=[mv, im])
    before = looks_of(doc, [mv, im])
    vivid = perform(doc, "Vivid")
    set_to = looks_of(doc, [mv, im])
    undone = reply(doc.call("undo")).get("undone")
    restored = looks_of(doc, [mv, im])
    check("LM1 MOVIE + IM, Clip ▸ Look ▸ Vivid: {vivid, 0.5} and {vivid, 1}; undo answers "
          "\"Look\" and restores both",
          vivid["ok"] and set_to == [{"kind": "vivid", "amount": 0.5},
                                     {"kind": "vivid", "amount": 1.0}]
          and undone == "Look" and restored == before == [{"kind": "warm", "amount": 0.5}, None],
          f"perform {vivid.get('error', 'ok')}; set {set_to}; undo {undone!r}; restored "
          f"{restored} (before {before})")
    removed = perform(doc, "None")
    gone = looks_of(doc, [mv, im])
    undone = reply(doc.call("undo")).get("undone")
    back = looks_of(doc, [mv, im])
    check("LM2 … ▸ None removes both looks; undo restores",
          removed["ok"] and gone == [None, None] and undone == "Look" and back == before,
          f"perform {removed.get('error', 'ok')}; after {gone}; undo {undone!r}; back {back}")

    # LM3
    doc.call("set_selection", clips=[tx])
    untouched = doc.project()
    text = perform(doc, "Vivid")
    unchanged = doc.project() == untouched
    doc.call("set_selection", clips=[aj])
    faded = perform(doc, "Faded")
    landed = looks_of(doc, [aj])
    if faded["ok"]:
        doc.call("undo")
    check("LM3 TX alone: Clip ▸ Look ▸ Vivid is refused \"is disabled here\", nothing changes; "
          "CONTROL: AJ alone, Faded lands {faded, 1}",
          not text["ok"] and DISABLED in text.get("error", "") and unchanged and faded["ok"]
          and landed == [{"kind": "faded", "amount": 1.0}],
          f"TX {text.get('error', 'APPLIED')!r} unchanged {unchanged}; AJ "
          f"{faded.get('error', 'ok')} → {landed}")


def run_g3(binary, state):
    """A second instance with the Look section pinned CLOSED, on MG, the same
    selection, playhead and sub-tab as G1: no generation in 3 s, no pending key."""
    log = WORK / "instance-closed.log"
    launched = mcp.launch(str(binary), pins(closed=True, dump=DUMP_CLOSED),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            check("G3 the closed instance listens", False, str(launched.socket_path))
            return False, log
        doc = Doc(launched.client, MG)
        opened_mg = attempt(launched.client, "open_project", {"path": str(MG)})
        clips = state.get("mg_clips") or {}
        doc.call("set_selection", clips=[clips.get("movie")])
        doc.call("set_playhead", t=T)
        tabs = reply(doc.call("select_inspector_tab", tab="clip", sub_tab="color"))
        time.sleep(3)
        made = manifests(DUMP_CLOSED)
        answer = reply(doc.call("select_inspector_tab"))
        control = state.get("g1_generation", False)
        check("G3 the Look section pinned closed, the same selection, playhead and sub-tab: no "
              "generation in 3 s and no pending key; CONTROL: G1's instance made one",
              opened_mg["ok"] and tabs.get("sub_tab") == "color" and not made
              and "look_thumbnails_pending" not in answer and control,
              f"open {opened_mg.get('error', 'ok')}; tab {tabs.get('sub_tab')}; generations "
              f"{[m.get('generation') for m in made]}; answer keys {sorted(answer)}; control "
              f"{control}")
        return close(launched.client, MG), log
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)


# ---- the probe ---------------------------------------------------------------

def run_probe(sources, shader, state):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "look_probe", defines=["REELCUT_DEV_TOOLS"],
                                  timeout=1200)
    except swift_build.SwiftBuildFailed as error:
        for name in sorted(selected & (L_ROWS | B_ROWS)):
            check(f"{name} the probe builds over app/Sources", False,
                  f"{error} {error.diagnostics[:6]}")
        return
    request, answer = folder / "request.json", folder / "answer.json"
    if answer.exists():
        answer.unlink()
    clips = {key: value for key, value in (state.get("mg_clips") or {}).items()
             if value is not None}
    request.write_text(json.dumps({"shader": str(shader), "package": str(MG),
                                   "cool": str(MG_COOL), "clips": clips}))
    ran = bounded.run([str(built.binary), str(request), str(answer)], 600,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        answered = json.loads(answer.read_text())["rows"]
    except (OSError, ValueError, KeyError):
        answered = []
    for name in sorted(selected & (L_ROWS | B_ROWS)):
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], "" if row["ok"] and name not in RECORDS
                  else row["detail"])


# ---- the run ------------------------------------------------------------------

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
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "look",
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
        binary = binary / "Contents/MacOS/Reelcut"
    sources, shader = ROOT / "app/Sources", ROOT / SHADER
    config = proof_app.config()
    if args.mutant:
        print(f"grading GR5 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)",
              flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
        sources, shader = copy / "app/Sources", copy / SHADER
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test look "
                  "--test ungraded in the copy's core\n       " + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print(f"grading GR5 — looks over MCP ({args.mode or 'run'}, {config} build "
              f"{binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    chart, card, movie = fixtures()
    if movie is None:
        print("instrument failure: ffmpeg did not make the testsrc2 movie")
        return 2
    neutral = Neutral(args.mode, folder)
    log = WORK / "instance.log"
    state = {}
    closed = True
    capture = args.mode == "capture"
    if capture or "N0" in selected or selected & (H_ROWS | C_ROWS | M_ROWS | MG_NEEDED):
        launched = mcp.launch(str(binary), pins(closed=False, dump=DUMP),
                              env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                              log_path=str(log), timeout=CALL_BOUND)
        try:
            if launched.client is None:
                print(f"instrument failure: the app did not listen at {launched.socket_path}")
                return 2
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            try:
                if capture or "N0" in selected or selected & H_ROWS:
                    closed = run_h(launched.client, chart, neutral, state) and closed
                if capture or "N0" in selected or selected & C_ROWS:
                    closed = run_c(launched.client, card, neutral, state) and closed
                if capture or "N0" in selected or selected & M_ROWS:
                    closed = run_m(launched.client, movie, neutral, state) and closed
                if not capture and selected & MG_NEEDED:
                    closed = run_mg(launched.client, movie, card, state) and closed
            except Exception as error:  # a row that could not run is a failure
                print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
                closed = False
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    logs = [log]
    if "G3" in selected and state.get("mg_fixture"):
        try:
            closed_g3, closed_log = run_g3(binary, state)
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed_g3, closed_log = False, WORK / "instance-closed.log"
        closed = closed_g3 and closed
        logs.append(closed_log)
    if selected & (L_ROWS | B_ROWS):
        run_probe(sources, shader, state)
    if "N0" in selected:
        missing = [name for name in NEUTRAL if name not in neutral.seen]
        good = not neutral.misses and not missing
        title = (f"N0 the four neutral frames are byte-identical (16 bits a channel) to "
                 f"{args.folder}")
        if config == "release" or args.mutant:
            check(title, good, f"misses {neutral.misses}; not taken {missing}")
        else:
            selected.discard("N0")
            scored = [name for name in scored if name != "N0"]
            print(f"  note N0 is scored on Release only; on {config}: "
                  f"{'equal' if good else neutral.misses + missing}", flush=True)
    found = [line for path in logs if path.exists() for line in complaints(path)]
    fixtures_ok = all(value for key, value in state.items() if key.endswith("fixture"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Reelcut: ` "
          "line", closed and fixtures_ok and not found,
          f"closed {closed}; fixtures {state}; complaints {found}")
    if log.exists():
        print(f"  {log.name} tail:\n    " + "\n    ".join(tail(log)), flush=True)
    if capture:
        taken = sorted(p.name for p in folder.glob("*.png"))
        good = rows.get("Z1") and taken == sorted(f"{n}.png" for n in NEUTRAL)
        print(f"captured {len(taken)} neutral frames into {args.folder}: {taken}")
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
