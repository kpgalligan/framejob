#!/usr/bin/env python3
"""Road map "grading", phase GR3 (spec §11 GR-4, GR-5) — seeing the grade end
to end: the `ungraded` recipe option (`render_frame {ungraded}`, View ▸ Show
Ungraded on the window's preview only), the luma waveform (View ▸ Waveform's
panel, `render_frame {waveform}`), the probe's rows over `app/Sources` and the
harness's captures.

    python3 tools/proof/seeing_proof.py [--app PATH] [--only U1,V1,...]
    python3 tools/proof/seeing_proof.py --mutant NAME

Launches the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket of its own, and stops only that process. **The instance
runs in a scratch home**, `CFFIXED_USER_HOME=tools/proof/work/seeing/home`, and
every package, fixture and PNG is under `tools/proof/work/seeing/`, removed at
the start and at exit. The only menu items performed are View ▸ Show Ungraded
and View ▸ Waveform, which persist nothing (GR-4, GR-5); `DEFAULTS MOVED` from
`mcp.py` stops the run. Every call is bounded (`CALL_BOUND`), every ffmpeg too
(120 s), every wait on the panel too (`PANEL_WAIT`). Every project is closed
(`close_project`, discard).

Fixtures, written by this script: CARD, a 640×360 grey-128 PNG; RAMP, a
1920×360 PNG whose column x is round(255·x/1919); MOVIE, a 2 s 640×360 30 fps
ffmpeg `testsrc2` H.264 file. Frames are taken at t = 0.5 s.

Project G (640×360, black): MOVIE on track A at exposure +1 and temperature
+0.5; a half-size CARD on B at brightness 0.1 and hue 30; a CARD on C nested
(`nest`), the clip inside at exposure −1 and contrast 0.3 (`scope`); a CARD on
a `luma` matte track D at exposure +1. N is its frame BEFORE any grade.
- **U1**: `render_frame {ungraded: true}` of the graded project = N's bytes
  (decoded at 16 bits a channel), ≠ the graded frame, and its text says "with
  every grade removed".
- **U2**: with View ▸ Show Ungraded ON in G's window, an un-optioned
  `render_frame` = the graded frame's bytes.
- **U3**: with it still ON, the `prores_422` export's frame 15 is within ±8 of
  the graded frame at every 16th pixel and differs from the ungraded one by
  more than 30 somewhere.
- **U4**: `render_frame {ungraded: "yes"}` is refused, naming `ungraded`.

Project V (1920×360, RAMP):
- **W1**: `render_frame {waveform: true}` on the neutral ramp: the sentence
  "Waveform: highlights clipped in …" sits before "Written to", its JSON holds
  1920 × 360, and in every column bin the levels lie within the bin's rendered
  values and the counts total 360 × the bin's pixel columns.
- **V1**: at exposure +2, `SETTLE` s after the edit, View ▸ Waveform shown,
  paused: the panel's readouts
  (`snapshot_ui`, ids `waveform.highlights` / `waveform.shadows`) are within
  0.2 points of `render_frame {waveform}`'s percentages, which clip high in
  more than 10 % of pixels.
- **V2**: after View ▸ Show Ungraded the readouts are within 0.2 points of
  `render_frame {ungraded, waveform}`'s, which differ from V1's by > 1 point.
- **V3**: the panel is 248 pt wide and the canvas ends at its leading edge;
  off, it is hidden and zero wide and the canvas spans the pane.
- **V4**: the "Ungraded" tag (`preview.ungraded`) shows only while the switch
  is on.
- **P1–P7**: `waveform_probe.swift`, built by `swift_build.build` over
  `app/Sources` (a failed build is a scored FAILURE of every P row), its kernel
  compiled from the tree's `Waveform.metal`: P1 a 256-wide ramp → counts[c][c]
  = 360 and nothing else; P2 grey 128 → level 128; P3 (1,0,0)/(0,1,0)/(0,0,1)
  → 54/182/18; P4 254.6/255 → 255, 254.4/255 → 254, 0.4/255 → 0, 0.6/255 → 1,
  1.5 → 255, −0.5 → 0; P5 the marks at 0.5 % and the readouts' spelling; P6 the
  two commands on and off write no `UserDefaults` key and `RecipeSource` holds
  `ungraded` for the document's key only; P7 latest wins — three 4K frames
  offered back to back, the last delivered trace is the third's.
- **G1** (RECORD, unscored): the pass's GPU time at 1080p and 4K (the median
  of ten).
- **H1–H2** (not under `--mutant`: the harness builds the tree's own sources):
  the harness with `seeing=waveform,ungraded,ramp`, light and dark, each twice:
  H1 byte-identical twice; H2 the trace's well (its rect less the 24 pt label
  gutter) holds trace pixels (≥ 200 near white) and the red clip marks (≥ 4 px).
- **Z1** (CONTROL): the fixtures hold, the projects close and the log holds no
  `Reelcut: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`; a `core/`
mutant makes the copy's `core/` its own through `hevc_alpha_proof.own_core`
and links the tree's `core/tests`), applies its edits (each anchor asserted
to occur exactly once), builds it by the copy's own `make app-debug` (`make
app` under `RC_PROOF_APP=release`) and runs every row on it, the probe built
over the copy's `app/Sources` and its shader. A core mutant also runs `cargo
test --release --no-fail-fast --test ungraded` in the copy's own `core/` (row
CT). MUTANT PASS when every named row FAILED and no other scored row did:
  ungraded-ignored       the option never reaches `layer`: U1 U3 V2 CT
  ungraded-tone-only     the option strips Light's nine and keeps Color's four: U1 CT
  view-key-leaks         a key with no options reads another key's: U2 U3
  luma-weights-swapped   the kernel weighs blue as red: P3
  level-floors           the kernel floors Y′·255 instead of rounding: P1 P2 P4 W1 V1
  no-paused-refresh      the two commands do not compose the paused frame again: V1 V2
  pending-dropped        a frame offered while one is in flight is dropped: P7
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
from hevc_alpha_proof import own_core  # noqa: E402

WORK = ROOT / "tools/proof/work/seeing"
HOME = WORK / "home"
PROBE = ROOT / "tools/proof/waveform_probe.swift"
SHADER = "app/Resources/Shaders/Waveform.metal"
CALL_BOUND = 300
BUILD_BOUND = 1500
PANEL_WAIT = 20
SETTLE = 2
SEC = 600_000
T = SEC // 2
CARD_W, CARD_H = 640, 360
RAMP_W, RAMP_H = 1920, 360
GREY = 128
ROWS = ["U1", "U2", "U3", "U4", "W1", "V1", "V2", "V3", "V4", "P1", "P2", "P3", "P4", "P5",
        "P6", "P7", "G1", "H1", "H2", "Z1"]
RECORDS = {"G1"}
G_ROWS = {"U1", "U2", "U3", "U4"}
V_ROWS = {"W1", "V1", "V2", "V3", "V4"}
P_ROWS = {"P1", "P2", "P3", "P4", "P5", "P6", "P7", "G1"}
H_ROWS = {"H1", "H2"}
UNGRADED = ["View", "Show Ungraded"]
WAVEFORM = ["View", "Waveform"]
# name: ([(file, anchor, replacement), …], the rows that must fail)
MUTANTS = {
    "ungraded-ignored": ([(
        "core/src/recipe.rs",
        "self.layer(instance, t, &assignment, roles, opts.ungraded)",
        "self.layer(instance, t, &assignment, roles, false)")], ["U1", "U3", "V2", "CT"]),
    "ungraded-tone-only": ([(
        "core/src/recipe.rs",
        "            moved.color = ColorAdjust::default();\n",
        "            moved.color = ColorAdjust {\n"
        "                brightness: moved.color.brightness,\n"
        "                contrast: moved.color.contrast,\n"
        "                saturation: moved.color.saturation,\n"
        "                hue: moved.color.hue,\n"
        "                ..ColorAdjust::default()\n"
        "            };\n")], ["U1", "CT"]),
    "view-key-leaks": ([(
        "app/Sources/RecipeSource.swift",
        "let asked = options[key] ?? .none",
        "let asked = options[key] ?? options.values.first ?? .none")], ["U2", "U3"]),
    "luma-weights-swapped": ([(
        SHADER,
        "constant float3 kLumaWeights = float3(0.2126, 0.7152, 0.0722);",
        "constant float3 kLumaWeights = float3(0.0722, 0.7152, 0.2126);")], ["P3"]),
    "level-floors": ([(
        SHADER,
        "uint(dot(rgb, kLumaWeights) * 255.0 + 0.5)",
        "uint(dot(rgb, kLumaWeights) * 255.0)")], ["P1", "P2", "P4", "W1", "V1"]),
    "no-paused-refresh": ([(
        "app/Sources/EditorViewController+Seeing.swift",
        "        playback.refreshPausedFrame()\n",
        "")], ["V1", "V2"]),
    "pending-dropped": ([(
        "app/Sources/WaveformTap.swift",
        "            tap.pending = frame\n",
        "")], ["P7"]),
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


def decoded(movie, n, width, height):
    """Frame `n` of `movie` as RGBA bytes; (None, why) or (bytes, n)."""
    try:
        raw = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(movie), "-vf", f"select=eq(n\\,{n})",
             "-fps_mode", "passthrough", "-vframes", "1", "-f", "rawvideo", "-pix_fmt",
             "rgba", "-"], capture_output=True, timeout=120, env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired) as error:
        return None, f"ffmpeg: {error}"
    return (raw, n) if len(raw) == width * height * 4 else (None, "no frame decoded")


class Frame:
    """One `render_frame`: its path, its text, its decoded RGBA, its width."""

    def __init__(self, path, text, raw, width):
        self.path, self.text, self.raw, self.width = path, text, raw, width

    def px(self, x, y):
        at = (y * self.width + x) * 4
        return tuple(self.raw[at:at + 3])


def max_diff(a, b, points):
    return max(max(abs(p - q) for p, q in zip(a.px(x, y), b.px(x, y))) for x, y in points)


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

    def place(self, track, media):
        before = {c["id"] for c in self.project().get("clips") or []}
        got = self.call("add_clip", track=track, media=media, at=0)
        new = [c["id"] for c in self.project().get("clips") or [] if c["id"] not in before]
        return new[0] if got["ok"] and len(new) == 1 else None

    def media(self, path):
        return reply(self.call("import_media", path=str(path))).get("media")

    def color(self, clips, scope=None, **keys):
        arguments = {"clips": clips, "patch": {"color": keys}}
        if scope is not None:
            arguments["scope"] = scope
        return self.call("set_video", **arguments)

    def frame(self, tag, deep=False, **options):
        """`render_frame` at T with `options`, decoded; a Frame, or None."""
        out = WORK / f"{tag}.png"
        for stale in (out, Path(str(out) + ".waveform.json")):
            if stale.exists():
                stale.unlink()
        got = self.call("render_frame", t=T, path=str(out), **options)
        raw = (decode(out, self.width, self.height, deep) if got["ok"] and out.exists()
               else None)
        if raw is None:
            print(f"       render {tag}: {got.get('error', 'no file or a wrong size')}",
                  flush=True)
            return None
        return Frame(out, got["reply"] if isinstance(got["reply"], str) else "", raw,
                     self.width)

    def menu(self, path):
        return self.call("perform_menu_item", path=path)

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
    """The panel's two readouts as percentages, or None for "—"/absent."""
    found = []
    for identifier in ("waveform.highlights", "waveform.shadows"):
        v = view(views, identifier)
        m = PERCENT.search((v or {}).get("text") or "") if v and not v.get("hidden") else None
        found.append(float(m.group(1)) if m else None)
    return tuple(found)


def waveform_of(frame):
    """The JSON `render_frame {waveform}` wrote beside `frame`, or {}."""
    try:
        return json.loads(Path(str(frame.path) + ".waveform.json").read_text())
    except (OSError, ValueError, AttributeError):
        return {}


def opened(client, name, width, height, background=None):
    """A new project at `name`, its canvas sized; (Doc, fixture ok)."""
    path = WORK / f"{name}.reelcut"
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
    return card, ramp, (movie if made["rc"] == 0 and movie.exists() else None)


# ---- project G: the graded stack (U1–U4) ---------------------------------------

def run_g(client, card, movie, state):
    doc, sized = opened(client, "G", CARD_W, CARD_H, background=[0, 0, 0, 1])
    a_track = (doc.tracks() or [{}])[0].get("id")
    movie_media, card_media = doc.media(movie), doc.media(card)
    m = doc.place(a_track, movie_media)
    b_track = doc.new_track()
    b = doc.place(b_track, card_media)
    placed = [doc.call("set_video", clips=[b], patch={"scale": 0.5, "x": -120})["ok"]]
    c_track = doc.new_track()
    c = doc.place(c_track, card_media)
    placed.append(doc.call("set_video", clips=[c], patch={"scale": 0.4, "x": 150, "y": 60})["ok"])
    placed.append(doc.call("nest", clips=[c])["ok"])
    nest = (doc.project().get("nests") or [{}])[0]
    inner = ((nest.get("clips") or [{}])[0]).get("id")
    d_track = doc.new_track()
    d = doc.place(d_track, card_media)
    placed.append(doc.call("set_video", clips=[d], patch={"scale": 0.6})["ok"])
    placed.append(doc.call("set_track", track=d_track, matte="luma")["ok"])
    neutral = doc.frame("g-neutral", deep=True)
    graded = [doc.color([m], exposure=1, temperature=0.5)["ok"],
              doc.color([b], brightness=0.1, hue=30)["ok"],
              doc.color([inner], scope=nest.get("id"), exposure=-1, contrast=0.3)["ok"],
              doc.color([d], exposure=1)["ok"]]
    fixture = (sized and None not in (m, b, c, d, inner) and all(placed) and all(graded)
               and neutral is not None)
    state["g_fixture"] = fixture
    print(f"  G: clips {m} {b} {d}, nest {nest.get('id')} holding {inner}; placed {placed}, "
          f"graded {graded}", flush=True)
    if not fixture:
        return close(client, doc.path) and fixture
    graded_frame = doc.frame("g-graded", deep=True)
    ungraded = doc.frame("g-ungraded", deep=True, ungraded=True)

    # U1
    check("U1 render_frame {ungraded} of the graded stack (two tracks, a nested clip, a luma "
          "matte clip) = the bytes of the same stack before any grade, ≠ the graded frame, "
          "and says \"with every grade removed\"",
          ungraded is not None and graded_frame is not None and ungraded.raw == neutral.raw
          and graded_frame.raw != neutral.raw and "with every grade removed" in ungraded.text,
          f"ungraded = neutral {ungraded is not None and ungraded.raw == neutral.raw}; graded "
          f"≠ neutral {graded_frame is not None and graded_frame.raw != neutral.raw}; text "
          f"{(ungraded.text if ungraded else '')[:160]!r}")

    # U4
    refused = doc.call("render_frame", t=T, ungraded="yes")
    check("U4 render_frame {ungraded: \"yes\"} is refused, naming ungraded",
          not refused["ok"] and "ungraded" in refused.get("error", ""),
          f"answer {refused.get('error') or 'ACCEPTED'!r}")

    # U2, U3 — the switch on in this window
    switched = doc.menu(UNGRADED)
    plain = doc.frame("u2-plain", deep=True)
    check("U2 with View ▸ Show Ungraded on in this window, an un-optioned render_frame is the "
          "graded frame's bytes",
          switched["ok"] and plain is not None and graded_frame is not None
          and plain.raw == graded_frame.raw,
          f"menu {switched.get('error', 'ok')}; equal "
          f"{plain is not None and graded_frame is not None and plain.raw == graded_frame.raw}")
    out = WORK / "U3.mov"
    exported = doc.call("export", preset="prores_422", path=str(out), size="document")
    raw, which = (decoded(out, 15, CARD_W, CARD_H) if exported["ok"] and out.exists()
                  else (None, "no file"))
    shallow_graded = doc.frame("u3-graded")
    shallow_ungraded = doc.frame("u3-ungraded", ungraded=True)
    samples = [(x, y) for y in range(0, CARD_H, 16) for x in range(0, CARD_W, 16)]
    misses, apart = [], 0
    if raw is not None and shallow_graded is not None and shallow_ungraded is not None:
        export = Frame(out, "", raw, CARD_W)
        misses = [(x, y, export.px(x, y), shallow_graded.px(x, y)) for x, y in samples
                  if max(abs(p - q) for p, q in zip(export.px(x, y),
                                                     shallow_graded.px(x, y))) > 8]
        apart = max_diff(export, shallow_ungraded, samples)
    check(f"U3 with the switch on, the prores_422 export's frame {which} is within ±8 of the "
          f"graded frame at {len(samples)} samples and differs from the ungraded one by > 30",
          exported["ok"] and raw is not None and shallow_graded is not None and not misses
          and apart > 30,
          f"export {exported.get('error', 'ok')}; {misses[:3] or 'all within'}; "
          f"from ungraded {apart}")
    doc.menu(UNGRADED)
    return close(client, doc.path)


# ---- project V: the ramp, its waveform and the panel (W1, V1–V4) ---------------

def bins(width):
    """Each column bin's pixel columns, as the kernel bins them."""
    out = [[] for _ in range(256)]
    for x in range(width):
        out[x * 256 // width].append(x)
    return out


def wait_readouts(doc, tag, want=None):
    """Polls the panel's readouts until both are numbers (and, given `want`,
    within 0.2 of it), at most PANEL_WAIT s; (readouts, views)."""
    deadline = time.monotonic() + PANEL_WAIT
    shown, views, n = (None, None), [], 0
    while time.monotonic() < deadline:
        views = doc.preview(f"{tag}-{n}")
        n += 1
        shown = readouts(views)
        if None not in shown and (want is None or all(
                abs(a - b) <= 0.2 for a, b in zip(shown, want))):
            break
        time.sleep(0.5)
    return shown, views


def run_v(client, ramp, state):
    doc, sized = opened(client, "V", RAMP_W, RAMP_H)
    track = (doc.tracks() or [{}])[0].get("id")
    media = doc.media(ramp)
    clip = doc.place(track, media) if media is not None else None
    fixture = sized and clip is not None
    state["v_fixture"] = fixture
    if not fixture:
        return close(client, doc.path), None

    # W1
    w = doc.frame("w1", waveform=True)
    data = waveform_of(w)
    counts = data.get("counts") or []
    misses = []
    if w is not None and len(counts) == 256:
        for c, xs in enumerate(bins(RAMP_W)):
            values = [w.px(x, RAMP_H // 2)[0] for x in xs]
            levels = [lv for lv, n in enumerate(counts[c]) if n]
            total = sum(counts[c])
            if not xs or total != RAMP_H * len(xs) or any(
                    not min(values) <= lv <= max(values) for lv in levels):
                misses.append((c, total, levels[:4], (min(values), max(values)) if xs else ()))
    text = w.text if w else ""
    said = re.search(r"Waveform: highlights clipped in \d+\.\d % of pixels, shadows in "
                     r"\d+\.\d %; its 256 × 256 counts are in (\S+\.waveform\.json)\. "
                     r"Written to \S+\.png\.$", text)
    check("W1 render_frame {waveform} on the neutral ramp: the sentence before \"Written to\", "
          "a 1920 × 360 trace, every column bin's levels within its rendered values and its "
          "counts 360 × its columns",
          w is not None and said is not None and data.get("width") == RAMP_W
          and data.get("height") == RAMP_H and len(counts) == 256 and not misses,
          f"text {text[-220:]!r}; size {data.get('width')}×{data.get('height')}; "
          f"misses {misses[:4]}")

    # V1, V3 (on)
    up = doc.color([clip], exposure=2)
    reference = waveform_of(doc.frame("v1-reference", waveform=True))
    want = (reference.get("highlights"), reference.get("shadows"))
    # The edit's own paused-frame refresh has composed and gone before the
    # panel is shown, so the frame the panel analyses is the one its own
    # command composed (the `no-paused-refresh` mutant's row).
    time.sleep(SETTLE)
    shown_menu = doc.menu(WAVEFORM)
    panel, views = wait_readouts(doc, "v1", None if None in want else want)
    check(f"V1 View ▸ Waveform shown, paused, the ramp at exposure +2: the readouts {panel} "
          f"are within 0.2 points of render_frame {{waveform}}'s {want}, highlights > 10 %",
          up["ok"] and shown_menu["ok"] and None not in panel and None not in want
          and want[0] > 10 and all(abs(a - b) <= 0.2 for a, b in zip(panel, want)),
          f"exposure {up.get('error', 'ok')}; menu {shown_menu.get('error', 'ok')}")
    canvas = view(views, cls="PreviewCanvasView") or {}
    box = view(views, "waveform.panel") or {}
    root = (views[0].get("frame") if views else None) or [0, 0, 0, 0]
    cf, pf = canvas.get("frame") or [0, 0, 0, 0], box.get("frame") or [0, 0, 0, 0]
    on_ok = (not box.get("hidden", True) and abs(pf[2] - 248) <= 0.5
             and abs(cf[0] + cf[2] - pf[0]) <= 0.5 and abs(pf[0] + pf[2] - root[2]) <= 0.5)

    # V2, V4 (on)
    switched = doc.menu(UNGRADED)
    reference2 = waveform_of(doc.frame("v2-reference", waveform=True, ungraded=True))
    want2 = (reference2.get("highlights"), reference2.get("shadows"))
    panel2, views2 = wait_readouts(doc, "v2", None if None in want2 else want2)
    check(f"V2 after View ▸ Show Ungraded the readouts {panel2} are within 0.2 points of "
          f"render_frame {{ungraded, waveform}}'s {want2}, > 1 point from V1's",
          switched["ok"] and None not in panel2 and None not in want2 and None not in want
          and abs(want2[0] - want[0]) > 1
          and all(abs(a - b) <= 0.2 for a, b in zip(panel2, want2)),
          f"menu {switched.get('error', 'ok')}")
    tag = view(views2, "preview.ungraded") or {}
    tag_on = not tag.get("hidden", True) and tag.get("text") == "Ungraded"

    # V4 (off), V3 (off)
    doc.menu(UNGRADED)
    views3 = doc.preview("v4-off")
    tag_off = (view(views3, "preview.ungraded") or {}).get("hidden") is True
    check("V4 the \"Ungraded\" tag shows while Show Ungraded is on and is hidden when it is off",
          tag_on and tag_off, f"on {tag}; off hidden {tag_off}")
    doc.menu(WAVEFORM)
    views4 = doc.preview("v3-off")
    canvas4 = (view(views4, cls="PreviewCanvasView") or {}).get("frame") or [0, 0, 0, 0]
    box4 = view(views4, "waveform.panel") or {}
    root4 = (views4[0].get("frame") if views4 else None) or [0, 0, 0, 0]
    off_ok = (box4.get("hidden") is True and abs((box4.get("frame") or [0, 0, 1, 0])[2]) <= 0.5
              and abs(canvas4[2] - root4[2]) <= 0.5)
    check("V3 the panel is 248 pt wide at the pane's right edge with the canvas ending at its "
          "leading edge; off, it is hidden and zero wide and the canvas spans the pane",
          on_ok and off_ok,
          f"on: canvas {cf}, panel {pf} (hidden {box.get('hidden')}), pane {root}; off: canvas "
          f"{canvas4}, panel {box4.get('frame')} (hidden {box4.get('hidden')}), pane {root4}")

    saved = WORK / "V-saved.reelcut"
    stored = doc.call("save_project", path=str(saved))
    doc.path = saved
    closed = close(client, doc.path)
    return closed, (saved if stored["ok"] else None)


# ---- the probe ------------------------------------------------------------------

def run_probe(sources, package):
    folder = WORK / "probe"
    folder.mkdir(parents=True, exist_ok=True)
    entry = folder / "main.swift"
    entry.write_text(PROBE.read_text())
    scored = sorted(P_ROWS - RECORDS)
    try:
        built = swift_build.build(sources=swift_build.app_sources(sources) + [entry],
                                  output=folder / "waveform_probe",
                                  defines=["REELCUT_DEV_TOOLS"], timeout=1200)
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
    ran = bounded.run([str(built.binary), str(request), str(answer)], 300,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    try:
        body = json.loads(answer.read_text())
    except (OSError, ValueError):
        body = {}
    answered = body.get("rows") or []
    for name in scored:
        mine = [r for r in answered if r["name"].split()[0] == name]
        if not mine:
            check(f"{name} the probe answered", False,
                  (ran["stdout"] + ran["stderr"]).strip()[-400:])
        for row in mine:
            check(row["name"], row["ok"], "" if row["ok"] else row["detail"])
    figures = (body.get("records") or {}).get("G1") or {}
    check("G1 RECORD: the waveform pass's GPU time, median of ten: "
          + ", ".join(f"{k} {v:.3f} ms" for k, v in sorted(figures.items())), True)


# ---- the harness ----------------------------------------------------------------

def harness_checks(package):
    binary, error = e2.build_harness()
    captures, traces = {}, {}
    for look in ("light", "dark"):
        for n in (1, 2):
            if error:
                break
            out = WORK / f"harness-{look}-{n}.png"
            ran = subprocess.run(
                [binary, str(package), str(out), look, "1440", "862", "-1", "0", "1", "clip",
                 "-", "-", "-", "-", "-", "waveform,ungraded,ramp"],
                capture_output=True, text=True, timeout=300)
            line = next((ln for ln in ran.stdout.splitlines() if ln.startswith("seeing trace ")),
                        "")
            if ran.returncode != 0 or not out.exists() or not line:
                error = (ran.stdout + ran.stderr).strip()[-400:] or "no trace line"
                break
            captures[(look, n)] = out.read_bytes()
            traces[look] = [float(v) for v in line.split()[2:]]
    if error:
        for name in sorted(H_ROWS):
            check(f"{name} the harness renders seeing=waveform,ungraded,ramp", False, error)
        return
    same = {look: captures[(look, 1)] == captures[(look, 2)] for look in ("light", "dark")}
    check("H1 the harness with seeing=waveform,ungraded,ramp is byte-identical twice, light "
          "and dark", all(same.values()), f"{same}")
    found = {}
    for look in ("light", "dark"):
        width, height, channels, image = e2.decode_png(str(WORK / f"harness-{look}-1.png"))
        scale = width / 1440
        x, y, w, h = (int(round(v * scale)) for v in traces[look])
        gutter = int(round(24 * scale))  # the labels' gutter: the well starts after it
        x, w = x + gutter, w - gutter
        bright = red = 0
        for row in image[y:y + h]:
            for px in range(x, x + w):
                r, g, b = row[px * channels:px * channels + 3]
                if min(r, g, b) >= 200:
                    bright += 1
                elif r >= 200 and g <= 110 and b <= 110:
                    red += 1
        found[look] = (bright, red)
    check("H2 the trace's well holds trace pixels (≥ 200 near white) and the red clip marks "
          "(≥ 4 px), light and dark",
          all(b >= 200 and r >= 4 for b, r in found.values()), f"(white, red) {found}")


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
    ran = bounded.run(["cargo", "test", "--release", "--no-fail-fast", "--test", "ungraded"],
                      900, cwd=str(copy / "core"))
    lines = (ran["stdout"] + ran["stderr"]).strip().splitlines()
    failed = [line.strip() for line in lines if line.strip().startswith("test ")
              and line.strip().endswith("FAILED")]
    return ran["rc"] == 0 and not ran["expired"], failed or lines[-3:]


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
    scored = [name for name in ROWS if name in selected and name not in RECORDS]
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = binary / "Contents/MacOS/Reelcut"
    sources = ROOT / "app/Sources"
    config = proof_app.config()
    if args.mutant:
        print(f"grading GR3 — the {args.mutant} MUTANT ({' '.join(named)} must FAIL)", flush=True)
        app, copy = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {copy}")
            return 2
        binary = app / "Contents/MacOS/Reelcut"
        sources = copy / "app/Sources"
        if "CT" in named:
            passed_ct, last = core_test(copy)
            rows["CT"] = passed_ct
            print(("  ok   " if passed_ct else "  FAIL ") + "CT cargo test --test ungraded in "
                  "the copy's core\n       " + " | ".join(last), flush=True)
            scored.append("CT")
    else:
        print(f"grading GR3 — seeing over MCP ({config} build {binary})", flush=True)
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    card, ramp, movie = fixtures()
    if movie is None:
        print("instrument failure: ffmpeg did not make the testsrc2 movie")
        return 2
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
            if selected & G_ROWS:
                closed = run_g(launched.client, card, movie, state) and closed
            if selected & (V_ROWS | P_ROWS | H_ROWS):
                v_closed, package = run_v(launched.client, ramp, state)
                closed = closed and v_closed
        except Exception as error:  # a row that could not run is a failure
            print(f"  instrument error: {type(error).__name__}: {error}", flush=True)
            closed = False
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if selected & P_ROWS:
        if package is None:
            for name in sorted(selected & P_ROWS - RECORDS):
                check(f"{name} project V was made and saved", False)
        else:
            run_probe(sources, package)
    if selected & H_ROWS:
        if package is None:
            for name in sorted(selected & H_ROWS):
                check(f"{name} project V was made and saved", False)
        else:
            harness_checks(package)
    found = complaints(log)
    fixtures_ok = all(value for key, value in state.items() if key.endswith("fixture"))
    check("Z1 CONTROL: the fixtures hold, the projects close and the log holds no `Reelcut: ` "
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
