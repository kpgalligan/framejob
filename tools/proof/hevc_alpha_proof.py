#!/usr/bin/env python3
"""Issue batch B85 phase 3 (#103; spec §11 G-33) — the size an export reports
is the size the file has, on an instance this script launches.

    python3 tools/proof/hevc_alpha_proof.py --rows size [--app PATH]
    python3 tools/proof/hevc_alpha_proof.py --record-baseline [--app PATH]

**This file holds phase A's rows only** (`--rows size`, G-33's even rule): the
launcher, the fixtures, the readers, the baseline recorder and Gate A. The
rows of the `hevc_alpha` row, the fill rule and the encoder outcome, with
their mutants and controls, are phase B's and are not written yet; without
`--rows size` the script says so and exits 2.

Launches the Release build on a scratch socket of its own and stops only
that process. **The instance runs in a scratch home**,
`CFFIXED_USER_HOME=tools/proof/work/hevc-alpha/home`, and every package, PNG
and export is under `tools/proof/work/hevc-alpha/`, which is removed at the
start and at exit. It is launched with every key of `screens.py`'s `PINS` as
a launch argument (never written), `ReelcutInspectorWidth` replaced by 280
and `ReelcutExportChoice` by `{"preset_id":"hevc_alpha"}` — sent as
`<string>…</string>`, because the argument domain DROPS a value that begins
with a brace and is not a property list, and the sheet then opens on the
owner's own remembered choice (measured: it did). One menu item is
performed, File ▸ Export…, and its sheet is cancelled. **Neither that nor
the `export` tool writes the remembered export choice**, by reading: its one
writer is `ExportChoice.remember()` (`ExportPresetsStore.swift`), whose one
caller is `ExportSheetController.commit(queue:)` — the Export and Add to
Queue buttons; `cancel_sheet` presses the sheet's Escape button, whose
action only dismisses, and the tool's handler (`AgentServer+Render.swift`)
reads and writes no default. What a RUN shows of it is `mcp.py`'s guard: a
moved owner-visible key is a `mcp: DEFAULTS MOVED` line on stderr, and
status 3 when no other Reelcut shares the domain — so the run's stderr is
kept beside its score. Every export is one second, and the largest frame
written is 1280 × 720.

Fixtures: **CLEAR** 640 × 360, background alpha 0, an opaque red 200 × 120
card; **SUBWHITE** 334 × 222 and **WIDE** 400 × 100, an opaque white
background under a white card (the card is there for the duration);
**ODDFULL** `open_project` of a 321 × 181 opaque red PNG ffmpeg wrote,
trimmed to a second and saved as a package (the picture covers the canvas);
**ODD** the same with the background at alpha 0 and the picture at half
scale; **TALLFULL** the same as ODDFULL from a 181 × 320 PNG; **ODDBIG**
`open_project` of a 1001 × 667 PNG, never exported.

Rows of `--rows size` (Gate A):
- **H0**: with the instance listening, `<home>/Library/Application Support`
  is a directory (the scratch home took). When it fails no tool is called.
- **T0**: `export`'s `size` description holds "written one pixel smaller on
  that edge".
- **R1**: ODDFULL with no `size` as `h264`, `hevc` and `prores_422`, and
  `hevc` again with `size: "document"`: the answer's `width` × `height` is
  320 × 180 and so is ffprobe's stream. The line prints the baseline's pair
  for each. **R2**: TALLFULL the same, 180 × 320.
- **R3**: ODDFULL as `prores_4444`, `apng` and `gif` with no `size`: the
  answer and the file are 321 × 181.
- **R4**: CLEAR as `h264` at `[321, 181]`: answer and file 320 × 180; as
  `prores_4444` at `[321, 181]`: both 321 × 181; CLEAR with no `size` as
  `h264`, `hevc`, `prores_422` and `prores_4444`: both 640 × 360.
- **E2**: File ▸ Export… on ODDFULL, `snapshot_ui` of the sheet,
  `cancel_sheet`: the Format popup reads "H.264 (MP4)" or "HEVC with Alpha
  (MOV)" — which fails the row when the pin did not take and the owner's
  remembered format is another one (as it was on this host); in phase A,
  where a taken pin names a row the build lacks and the sheet falls back to
  H.264, an owner who last exported H.264 cannot be told apart, and phase
  B's row requires "HEVC with Alpha (MOV)" exactly — the Size popup reads
  exactly "Document (even) · 320 × 180", a text begins "320 × 180 · ", the
  two size fields read 320 and 180, and no text holds "321 × 181". On
  ODDBIG the Size popup reads "Document (even) · 1000 × 666" with no
  `truncated` problem naming it and an intrinsic width no wider than its
  frame; on CLEAR, "Document size · 640 × 360".
- **B1**: CLEAR as `hevc`: everything the baseline holds for it is equal —
  ffprobe's stream and format values, the extension, the set of alphas, the
  corner pixel and the SHA-256 of frame 0's decoded RGBA.
- **B4**: `prores_4444` for CLEAR at the document size, CLEAR at `720p` and
  ODD at the document size: the size and frame 0's digest equal the
  baseline's.
- **G1**: ODDFULL and TALLFULL with no `size` as `h264`, `hevc` and
  `prores_422`: frame 0's digest equals the baseline's, and so do eight
  pixels — the middle row's columns 0, 1, w−2, w−1 and the middle column's
  rows 0, 1, h−2, h−1 — at least one of them black (the pad phase A must
  leave there); and `export` of CLEAR as `hevc_alpha` is refused as an
  unknown preset with no file. So phase A moved no pixel where it acts, and
  the row is red on a tree that already fills or already lists the row.
- **Z1**: every project closes, and the launch's log holds no `Reelcut: `
  line.

**The baseline** is `tools/proof/hevc_alpha_baseline.json`, written only by
`--record-baseline`, on the build BEFORE G-33's code: it refuses to write
unless `git status` shows `core/` and `app/` unchanged, the answer for
ODDFULL and TALLFULL says the canvas's odd size over an evened file on each
of `h264`, `hevc` and `prores_422` (R1's and R2's comparison FAILS — that
refusal to pass is Gate A's red), and each of those files' eight pixels
holds a black one. It keeps, per case, only what every recording agreed
on: a first run writes `recordings: 1`, a second merges into it, and a value
two recordings disagree on is stored `null` and named under `disagreed`.
The rows refuse a baseline of fewer than two recordings.

**The baseline is one host's bytes and one build's**, and says which. Its
cases are hardware H.264 and HEVC bitstreams, ffprobe's exact `size` and
`bit_rate` and ffmpeg's RGBA digests, so it is stamped with `host` — the
chip, the macOS version and build, and ffmpeg's version (`host()`) — and
the rows print it under their heading. **When today's host is not the
baseline's, no row is scored: the script names both and exits 2** (the
instrument, not the product). `head` is the commit of the BUILD's tree, not
of this checkout: `--app` has to be
`build/Build/Products/Release/Reelcut.app` at the top of a git work tree
(`build_tree`), `head` is that tree's `git rev-parse HEAD`, the `git status`
above is that tree's, and a build anywhere else — a proof's tree copy has no
`.git` — is not recorded.
What it cannot see is a STALE build inside its tree: `make app` there
first. A recording at another commit or on another host than the file's
starts the file over. So another host records its own, from a work tree of
a commit before G-33's code built there, with this script and `--app`
aimed at that build. Where a digest is `null` its row compares the case's five
sample pixels exactly instead (G1: the classes of the eight pixels — black,
red or neither) and says so on its line. Besides the cases above it
holds what phase B's rows will be read against: SUBWHITE's right-hand edge
at `720p` (B2), WIDE at `[402, 100]` on the three opaque rows — the
columns of the middle row's black pixels (L2) — and that `prores_4444`
refuses that size (S2).

Exit 0 when every row passed (the last line is `n/n`), 1 when one failed, 2
when the instrument could not run — which includes a baseline recorded on
another host; 3 is `mcp.py`'s, a moved default.
"""

import argparse
import atexit
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import tree_copy  # noqa: E402
import v2_snapshot  # noqa: E402
from screens import PINS  # noqa: E402

WORK = ROOT / "tools/proof/work/hevc-alpha"
HOME = WORK / "home"
OUT = WORK / "out"
APP = ROOT / "build/Build/Products/Release/Reelcut.app"
BASELINE = ROOT / "tools/proof/hevc_alpha_baseline.json"
CALL_BOUND = 120
TOOL_BOUND = 60
SECOND = 600_000
SIZE_ROWS = ["H0", "T0", "R1", "R2", "R3", "R4", "E2", "B1", "B4", "G1", "Z1"]
EVEN_ROWS = ["h264", "hevc", "prores_422"]
EXTENSION = {"h264": "mp4", "hevc": "mp4", "hevc_alpha": "mov", "prores_422": "mov",
             "prores_4444": "mov", "gif": "gif", "apng": "png"}
A6_PHRASE = "written one pixel smaller on that edge"
CHOICE = '<string>{"preset_id":"hevc_alpha"}</string>'
# What E2's Format popup may read. Phase A's build has no `hevc_alpha` row, so
# a pin that took shows H.264 — as does an owner who last exported H.264 with
# a pin that did not. Phase B's full rows require the second title alone.
EVEN_FORMATS = ("H.264 (MP4)", "HEVC with Alpha (MOV)")
STREAM_KEYS = ("codec_name,codec_tag_string,profile,level,pix_fmt,width,height,r_frame_rate,"
               "avg_frame_rate,nb_frames,bit_rate,color_range,color_space,color_transfer,"
               "color_primaries")
FORMAT_KEYS = "format_name,nb_streams,duration,size,bit_rate"
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


# ---- readers ---------------------------------------------------------------------

def tool(argv):
    """One bounded ffmpeg, ffprobe or git child; its stdout as text."""
    done = bounded.run(argv, TOOL_BOUND)
    if done["rc"] != 0:
        raise RuntimeError(f"{argv[0]} rc {done['rc']} (expired {done['expired']}): "
                           f"{done['stderr'].strip()[-300:]}")
    return done["stdout"]


def probe_video(path):
    """The first video stream's codec, profile, pixel format and size, or
    None where the file holds no video (`phase7_proof.py`'s reader)."""
    answer = tool(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
                   "stream=codec_name,profile,pix_fmt,width,height", "-of", "json", str(path)])
    streams = json.loads(answer).get("streams", [])
    return streams[0] if streams else None


def probe_whole(path):
    """ffprobe's values for the first video stream and for the file."""
    answer = json.loads(tool(
        ["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
         f"stream={STREAM_KEYS}:format={FORMAT_KEYS}", "-of", "json", str(path)]))
    return (answer.get("streams") or [{}])[0], answer.get("format") or {}


class Raster:
    """Frame 0 of a written file, decoded to straight 8-bit RGBA
    (`phase7_proof.py`'s reader; the size comes off the file)."""

    def __init__(self, path):
        stream = probe_video(path)
        if stream is None:
            raise RuntimeError(f"{path} holds no video stream to decode")
        self.width, self.height = int(stream["width"]), int(stream["height"])
        done = subprocess.run(
            ["ffmpeg", "-v", "error", "-i", str(path), "-vframes", "1", "-f", "rawvideo",
             "-pix_fmt", "rgba", "-"], capture_output=True, timeout=TOOL_BOUND, check=True)
        self.data = done.stdout
        if len(self.data) != self.width * self.height * 4:
            raise RuntimeError(f"{path}: decoded {len(self.data)} bytes, wanted "
                               f"{self.width * self.height * 4}")

    def pixel(self, x, y):
        i = (y * self.width + x) * 4
        return list(self.data[i:i + 4])

    def digest(self):
        return hashlib.sha256(self.data).hexdigest()

    def alphas(self):
        return sorted(set(self.data[3::4]))

    def samples(self):
        """Five pixels: the centre and the four quarter points."""
        w, h = self.width, self.height
        return [self.pixel(x, y) for x, y in
                ((w // 2, h // 2), (w // 4, h // 4), (3 * w // 4, h // 4),
                 (w // 4, 3 * h // 4), (3 * w // 4, 3 * h // 4))]

    def eight(self):
        """The middle row's columns 0, 1, w−2, w−1, then the middle column's
        rows 0, 1, h−2, h−1."""
        w, h = self.width, self.height
        return ([self.pixel(x, h // 2) for x in (0, 1, w - 2, w - 1)]
                + [self.pixel(w // 2, y) for y in (0, 1, h - 2, h - 1)])


def kind(pixel):
    """black (every channel under 40), red (r > 200, g and b < 60) or neither."""
    r, g, b = pixel[:3]
    if r < 40 and g < 40 and b < 40:
        return "black"
    return "red" if r > 200 and g < 60 and b < 60 else "neither"


# ---- the instance ----------------------------------------------------------------

def attempt(client, name, arguments):
    """One MCP call; a refusal is an answer, and so is an expiry."""
    try:
        return {"ok": True, "reply": client.call_with(name, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}
    except Exception as error:  # a socket timeout is the expiry
        return {"ok": False, "error": f"{type(error).__name__}: {error}"}


def must(client, name, arguments):
    got = attempt(client, name, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{name} {arguments}: {got['error']}")
    return got["reply"]


def launch(app):
    """The app on a scratch socket, in the scratch home, with every pin."""
    arguments = ["-NSRecentDocumentsLimit", "0"]
    for key, value in PINS:
        if key == "ReelcutInspectorWidth":
            value = "<real>280</real>"
        elif key == "ReelcutExportChoice":
            value = CHOICE
        arguments += [f"-{key}", value]
    return mcp.launch(str(app / "Contents/MacOS/Reelcut"), arguments=arguments,
                      env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                      log_path=str(WORK / "reelcut.log"), timeout=CALL_BOUND)


# ---- fixtures --------------------------------------------------------------------

def shapes(client, name, width, height, background, card, fill):
    """A new project with one card for a second; its package."""
    path = WORK / f"{name}.reelcut"
    must(client, "new_project", {"path": str(path)})
    must(client, "set_canvas", {"project": str(path), "width": width, "height": height,
                                "background": background})
    track = must(client, "get_project", {"project": str(path)})["project"]["tracks"][0]["id"]
    must(client, "add_shape_clip",
         {"project": str(path), "track": track, "at": 0, "duration": SECOND,
          "shape": {"kind": "rectangle", "width": card[0], "height": card[1], "stroke": None,
                    "fill": fill}})
    must(client, "save_project", {"project": str(path)})
    return path


def picture(client, name, width, height, clear=False):
    """A red PNG of that size opened as a document, its clip trimmed to a
    second, saved as a package; with `clear`, the background at alpha 0 and
    the picture at half scale."""
    png = WORK / f"{name}.png"
    tool(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
          f"color=c=red:s={width}x{height}", "-frames:v", "1", str(png)])
    must(client, "open_project", {"path": str(png)})
    project = must(client, "get_project", {"project": str(png)})["project"]
    canvas = (project["canvas"]["width"], project["canvas"]["height"])
    if canvas != (width, height) or len(project["clips"]) != 1:
        raise RuntimeError(f"{name}: the document is {canvas} with {len(project['clips'])} "
                           "clips")
    clip = project["clips"][0]["id"]
    must(client, "trim_end", {"project": str(png), "clip": clip, "to": SECOND})
    if clear:
        must(client, "set_canvas", {"project": str(png), "background": [0, 0, 0, 0]})
        must(client, "set_video", {"project": str(png), "clips": [clip],
                                   "patch": {"scale": 0.5}})
    package = WORK / f"{name}.reelcut"
    must(client, "save_project", {"project": str(png), "path": str(package)})
    return package


def fixtures(client):
    white, red = [1, 1, 1, 1], [1, 0, 0, 1]
    return {
        "CLEAR": shapes(client, "CLEAR", 640, 360, [0, 0, 0, 0], (200, 120), red),
        "SUBWHITE": shapes(client, "SUBWHITE", 334, 222, white, (100, 100), white),
        "WIDE": shapes(client, "WIDE", 400, 100, white, (40, 40), white),
        "ODDFULL": picture(client, "ODDFULL", 321, 181),
        "ODD": picture(client, "ODD", 321, 181, clear=True),
        "TALLFULL": picture(client, "TALLFULL", 181, 320),
        "ODDBIG": picture(client, "ODDBIG", 1001, 667),
    }


# ---- one export, and what is read from it ----------------------------------------

def export(client, fx, fixture, preset, size=None):
    """`export` of one fixture: whether it answered, the answer's size, the
    file's size as ffprobe reads it, and the path."""
    tag = "default" if size is None else (size if isinstance(size, str)
                                          else f"{size[0]}x{size[1]}")
    path = OUT / f"{fixture}-{preset}-{tag}.{EXTENSION[preset]}"
    if path.exists():
        path.unlink()
    arguments = {"project": str(fx[fixture]), "preset": preset, "path": str(path)}
    if size is not None:
        arguments["size"] = size
    got = attempt(client, "export", arguments)
    out = {"ok": got["ok"], "error": got.get("error"), "path": path, "answer": None,
           "file": None, "written": path.exists()}
    if got["ok"] and isinstance(got["reply"], dict):
        out["answer"] = [got["reply"].get("width"), got["reply"].get("height")]
        stream = probe_video(path) if path.exists() else None
        if stream is not None:
            out["file"] = [int(stream["width"]), int(stream["height"])]
    return out


def framed(done):
    """The answer's and the file's size, frame 0's digest, five samples."""
    raster = Raster(done["path"])
    return raster, {"answer": done["answer"], "file": done["file"],
                    "frame0": raster.digest(), "samples": raster.samples()}


def case_b1(client, fx):
    done = export(client, fx, "CLEAR", "hevc")
    if not done["ok"]:
        raise RuntimeError(f"CLEAR as hevc: {done['error']}")
    raster, case = framed(done)
    stream, whole = probe_whole(done["path"])
    case.update({"extension": done["path"].suffix, "stream": stream, "format": whole,
                 "alphas": raster.alphas(), "corner": raster.pixel(0, 0)})
    return case


def case_plain(client, fx, fixture, preset, size=None):
    done = export(client, fx, fixture, preset, size)
    if not done["ok"]:
        raise RuntimeError(f"{fixture} as {preset} at {size}: {done['error']}")
    return framed(done)[1]


def case_odd(client, fx, fixture, preset):
    """An odd canvas at its default size: `framed` plus the eight pixels."""
    done = export(client, fx, fixture, preset)
    if not done["ok"]:
        raise RuntimeError(f"{fixture} as {preset}: {done['error']}")
    raster, case = framed(done)
    eight = raster.eight()
    case.update({"eight": eight, "eight_class": [kind(p) for p in eight]})
    return case


def case_b2(client, fx, preset):
    done = export(client, fx, "SUBWHITE", preset, "720p")
    if not done["ok"]:
        raise RuntimeError(f"SUBWHITE as {preset} at 720p: {done['error']}")
    raster, case = framed(done)
    w, h = raster.width, raster.height
    case["edge3"] = [raster.pixel(x, h // 2) for x in (w - 1, w - 2, w - 3)]
    return case


def case_l2(client, fx, preset):
    done = export(client, fx, "WIDE", preset, [402, 100])
    if not done["ok"]:
        raise RuntimeError(f"WIDE as {preset} at [402, 100]: {done['error']}")
    raster, case = framed(done)
    middle = raster.height // 2
    case["black"] = [x for x in range(raster.width) if kind(raster.pixel(x, middle)) == "black"]
    case["column200"] = raster.pixel(200, middle)
    return case


def case_s2(client, fx):
    done = export(client, fx, "WIDE", "prores_4444", [402, 100])
    return {"refused": not done["ok"], "error": done["error"], "written": done["written"]}


# ---- the baseline ----------------------------------------------------------------

def measure(client, fx):
    """Every case the baseline holds, on the build that is running."""
    cases = {"B1 CLEAR hevc": case_b1(client, fx),
             "B4 CLEAR prores_4444 document": case_plain(client, fx, "CLEAR", "prores_4444"),
             "B4 CLEAR prores_4444 720p": case_plain(client, fx, "CLEAR", "prores_4444", "720p"),
             "B4 ODD prores_4444 document": case_plain(client, fx, "ODD", "prores_4444"),
             "S2 WIDE prores_4444 402x100": case_s2(client, fx)}
    for preset in EVEN_ROWS:
        for fixture in ("ODDFULL", "TALLFULL"):
            cases[f"G1 {fixture} {preset}"] = case_odd(client, fx, fixture, preset)
        cases[f"B2 SUBWHITE {preset} 720p"] = case_b2(client, fx, preset)
        cases[f"L2 WIDE {preset} 402x100"] = case_l2(client, fx, preset)
    return cases


def merge(old, new, where, disagreed):
    """What both hold equal; a value they disagree on is None and named."""
    if isinstance(old, dict) and isinstance(new, dict):
        return {key: merge(old.get(key), new.get(key), where + [key], disagreed)
                for key in sorted(set(old) | set(new))}
    if old == new:
        return old
    disagreed.add(" / ".join(where))
    return None


def host():
    """What the baseline's bytes depend on besides the build: the chip (the
    hardware encoders), the macOS version and build (VideoToolbox), and
    ffmpeg's version (the decoder behind every digest, and ffprobe)."""
    def first(argv):
        text = tool(argv).strip()
        if not text:
            raise RuntimeError(f"{' '.join(argv)} printed nothing")
        return text.splitlines()[0].strip()

    return {"chip": first(["sysctl", "-n", "machdep.cpu.brand_string"]),
            "macos": f"{first(['sw_vers', '-productVersion'])} "
                     f"({first(['sw_vers', '-buildVersion'])})",
            "ffmpeg": " ".join(first(["ffmpeg", "-version"]).split()[:3])}


def host_text(stamp):
    if not isinstance(stamp, dict):
        return "no host stamped"
    return (f"{stamp.get('chip')} · macOS {stamp.get('macos')} · {stamp.get('ffmpeg')}")


def build_tree(app):
    """The git work tree a build sits in — `<tree>/build/Build/Products/
    Release/Reelcut.app`, where `make app` puts it — or None when `app` is
    anywhere else or `<tree>` is not the top of a work tree. A proof's tree
    COPY is not one: it has no `.git`, and `git` would answer for the tree
    around it."""
    app = Path(app).resolve()
    if app.parts[-5:-1] != ("build", "Build", "Products", "Release"):
        return None
    tree = app.parents[4]
    done = bounded.run(["git", "-C", str(tree), "rev-parse", "--show-toplevel"], TOOL_BOUND)
    top = done["stdout"].strip()
    if done["rc"] != 0 or not top or Path(top).resolve() != tree:
        return None
    return tree


def unchanged_build(tree):
    """The BUILD's tree's `git rev-parse HEAD`, and what its `git status`
    lists under core/ and app/."""
    head = tool(["git", "-C", str(tree), "rev-parse", "HEAD"]).strip()
    dirty = tool(["git", "-C", str(tree), "status", "--porcelain", "--", "core", "app"])
    return head, [line for line in dirty.splitlines() if line.strip()]


def record(client, fx, app, today):
    """`--record-baseline`'s measuring half: the document to write, or None
    when this build is not one a baseline may be recorded on. `today` is
    `host()`'s answer."""
    tree = build_tree(app)
    if tree is None:
        print(f"NOT RECORDED: the build's commit cannot be read — {app} is not "
              "build/Build/Products/Release/Reelcut.app at the top of a git work tree")
        return None
    head, dirty = unchanged_build(tree)
    if dirty:
        print(f"NOT RECORDED: core/ or app/ of {tree} differs from its HEAD, so this is "
              f"not the build before G-33's code: {dirty}")
        return None
    cases = measure(client, fx)
    refused = []
    for fixture, canvas, even in (("ODDFULL", [321, 181], [320, 180]),
                                  ("TALLFULL", [181, 320], [180, 320])):
        for preset in EVEN_ROWS:
            case = cases[f"G1 {fixture} {preset}"]
            print(f"  {fixture} as {preset}: the answer says {case['answer']}, the file is "
                  f"{case['file']}; the eight pixels are {case['eight_class']}", flush=True)
            if case["answer"] != canvas or case["file"] != even:
                refused.append(f"{fixture} as {preset}: R1/R2's comparison does not fail the "
                               f"way the build before G-33 fails it (wanted the answer "
                               f"{canvas} over a file of {even})")
            if "black" not in case["eight_class"]:
                refused.append(f"{fixture} as {preset}: no black pixel among the eight")
    if not cases["S2 WIDE prores_4444 402x100"]["refused"]:
        refused.append("WIDE as prores_4444 at [402, 100] was not refused")
    if refused:
        print("NOT RECORDED:\n  " + "\n  ".join(refused))
        return None
    earlier = json.loads(BASELINE.read_text()) if BASELINE.exists() else None
    if (earlier is not None and earlier.get("head") == head
            and earlier.get("host") == today):
        disagreed = set(earlier.get("disagreed") or [])
        cases = merge(earlier["cases"], cases, [], disagreed)
        count = earlier["recordings"] + 1
    else:
        if earlier is not None:
            print(f"  the earlier baseline was recorded at {earlier.get('head')} on "
                  f"{host_text(earlier.get('host'))}; starting over")
        disagreed, count = set(), 1
    return {"head": head, "host": today, "recordings": count, "disagreed": sorted(disagreed),
            "cases": cases}


def write_baseline(document):
    BASELINE.write_text(json.dumps(document, indent=1, sort_keys=True) + "\n")
    print(f"RECORDED: recording {document['recordings']} at {document['head']} on "
          f"{host_text(document['host'])}; {len(document['cases'])} cases; the recordings "
          f"disagree on {document['disagreed'] or 'nothing'}")
    if document["recordings"] < 2:
        print("  one more --record-baseline is needed: the rows refuse a baseline of fewer "
              "than two recordings")


def held(base, now):
    """Whether everything the baseline kept for a case equals today's.
    Where the recordings disagreed on `frame0`, the five sample pixels
    stand in for it, and the text says so."""
    bad = [key for key in sorted(base) if base[key] is not None and base[key] != now.get(key)]
    note = ""
    if base.get("frame0") is None:
        if base.get("samples") is None:
            bad.append("frame0 (the recordings agreed on neither it nor the samples)")
        else:
            note = " [the recordings disagreed on frame0: the samples compared exactly instead]"
    return not bad, (f"differs in {bad}" if bad else "equal") + note


# ---- the sheet -------------------------------------------------------------------

def sheet(client, project, name):
    """File ▸ Export… on `project`, the sheet's layout dump, then
    `cancel_sheet`. `(views, problems)`, or raises."""
    must(client, "perform_menu_item", {"project": str(project), "path": ["File", "Export…"]})
    try:
        answer = v2_snapshot.snap(client, window="sheet", project=str(project),
                                  path=str(OUT / f"sheet-{name}.png"))
        v2_snapshot.captures.clear()
        with open(answer["layout_path"]) as handle:
            layout = json.load(handle)
    finally:
        attempt(client, "cancel_sheet", {"project": str(project)})
    return layout["views"], layout.get("problems") or []


def read_sheet(views, problems):
    """The Format and Size popups' texts, the size fields, every text, and
    the texts a `truncated` problem names."""
    visible = [v for v in views if not v.get("hidden") and v.get("text")]
    popups = [v for v in visible if v.get("class") == "NSPopUpButton"]

    def after(label):
        at = next((v["i"] for v in visible if v["text"] == label), None)
        return next((v["text"] for v in popups if at is not None and v["i"] > at), None)

    times = next((v for v in visible if v["text"] == "×"), None)
    fields = [v["text"] for v in visible
              if times is not None and v.get("parent") == times.get("parent")
              and v["text"].isdigit()]
    truncated = [views[p["view"]].get("text") for p in problems
                 if p.get("kind") == "truncated" and p.get("view", -1) < len(views)]
    size = after("Size:")
    room = next(([v["intrinsic"][0], v["frame"][2]] for v in popups if v["text"] == size),
                None)
    return {"format": after("Format:"), "size": size, "room": room, "fields": fields,
            "texts": [v["text"] for v in visible], "truncated": truncated}


# ---- Gate A ----------------------------------------------------------------------

def sized(done):
    return f"answer {done['answer']} file {done['file']}" + (
        "" if done["ok"] else f" ({done['error']})")


def run_size(client, fx, baseline):
    cases = baseline["cases"]

    # T0 — the size description says what an odd edge does
    description = (((client.schemas().get("export") or {}).get("inputSchema") or {})
                   .get("properties", {}).get("size", {}).get("description", ""))
    check(f"T0 export's size description holds \"{A6_PHRASE}\"", A6_PHRASE in description,
          "" if A6_PHRASE in description else f"it reads: {description}")

    # R1, R2 — an odd canvas at its default size: the answer is the file's
    odd = {}
    for row, fixture, even in (("R1", "ODDFULL", [320, 180]), ("R2", "TALLFULL", [180, 320])):
        good, lines = True, []
        for preset in EVEN_ROWS:
            done = export(client, fx, fixture, preset)
            odd[(fixture, preset)] = done
            base = cases[f"G1 {fixture} {preset}"]
            good = good and done["ok"] and done["answer"] == even and done["file"] == even
            lines.append(f"{preset}: {sized(done)} (baseline: answer {base['answer']} file "
                         f"{base['file']})")
        named = export(client, fx, fixture, "hevc", "document")
        good = good and named["ok"] and named["answer"] == even and named["file"] == even
        lines.append(f"hevc, size document: {sized(named)}")
        check(f"{row} {fixture} with no size as h264, hevc and prores_422, and hevc at "
              f"`document`: the answer and the file are {even[0]} × {even[1]}",
              good, "\n       ".join(lines))

    # R3 — the rows that keep an odd edge
    good, lines = True, []
    for preset in ("prores_4444", "apng", "gif"):
        done = export(client, fx, "ODDFULL", preset)
        good = good and done["ok"] and done["answer"] == [321, 181] and done["file"] == [321, 181]
        lines.append(f"{preset}: {sized(done)}")
    check("R3 ODDFULL with no size as prores_4444, apng and gif: the answer and the file "
          "are 321 × 181", good, "; ".join(lines))

    # R4 — an asked odd size, and an even canvas
    good, lines = True, []
    for preset, size, want in (("h264", [321, 181], [320, 180]),
                               ("prores_4444", [321, 181], [321, 181]),
                               ("h264", None, [640, 360]), ("hevc", None, [640, 360]),
                               ("prores_422", None, [640, 360]),
                               ("prores_4444", None, [640, 360])):
        done = export(client, fx, "CLEAR", preset, size)
        good = good and done["ok"] and done["answer"] == want and done["file"] == want
        lines.append(f"{preset} at {size or 'no size'}: {sized(done)}")
    check("R4 CLEAR at [321, 181] is 320 × 180 as h264 and 321 × 181 as prores_4444; with no "
          "size it is 640 × 360 on h264, hevc, prores_422 and prores_4444",
          good, "\n       ".join(lines))

    # E2 — the sheet says the file's size
    try:
        on_odd = read_sheet(*sheet(client, fx["ODDFULL"], "ODDFULL"))
        on_big = read_sheet(*sheet(client, fx["ODDBIG"], "ODDBIG"))
        on_clear = read_sheet(*sheet(client, fx["CLEAR"], "CLEAR"))
        big = "Document (even) · 1000 × 666"
        check("E2 the Export sheet on ODDFULL reads \"Document (even) · 320 × 180\", a text "
              "beginning \"320 × 180 · \" and the fields 320 and 180, with no \"321 × 181\" "
              f"anywhere; on ODDBIG \"{big}\", not truncated; on CLEAR \"Document size · "
              "640 × 360\"",
              on_odd["format"] in EVEN_FORMATS
              and on_odd["size"] == "Document (even) · 320 × 180"
              and any(t.startswith("320 × 180 · ") for t in on_odd["texts"])
              and on_odd["fields"] == ["320", "180"]
              and not any("321 × 181" in t for t in on_odd["texts"])
              and on_big["format"] in EVEN_FORMATS and on_big["size"] == big
              and big not in on_big["truncated"]
              and on_big["room"] is not None and on_big["room"][0] <= on_big["room"][1]
              and on_clear["format"] in EVEN_FORMATS
              and on_clear["size"] == "Document size · 640 × 360",
              f"ODDFULL: format {on_odd['format']!r}, size {on_odd['size']!r}, fields "
              f"{on_odd['fields']}, readout "
              f"{[t for t in on_odd['texts'] if ' fps · ' in t]}\n       ODDBIG: format "
              f"{on_big['format']!r}, size {on_big['size']!r}, its intrinsic width and "
              f"its frame's {on_big['room']}, truncated {on_big['truncated']}\n       "
              f"CLEAR: format {on_clear['format']!r}, size "
              f"{on_clear['size']!r}")
    except Exception as error:  # a sheet that could not be read is a failure
        check("E2 the Export sheet says the file's size", False,
              f"{type(error).__name__}: {error}")

    # B1 — the hevc row on an even canvas is the file it was
    good, text = held(cases["B1 CLEAR hevc"], case_b1(client, fx))
    check("B1 CLEAR as hevc: ffprobe's stream and format values, the extension, the alphas, "
          "the corner and frame 0's digest equal the baseline's", good, text)

    # B4 — prores_4444 is the file it was
    good, lines = True, []
    for fixture, size in (("CLEAR", None), ("CLEAR", "720p"), ("ODD", None)):
        base = cases[f"B4 {fixture} prores_4444 {size or 'document'}"]
        now = case_plain(client, fx, fixture, "prores_4444", size)
        same, text = held(base, now)
        good = good and same
        lines.append(f"{fixture} at {size or 'the document size'}: {now['file']} {text}")
    check("B4 prores_4444 for CLEAR at the document size, CLEAR at 720p and ODD at the "
          "document size: the size and frame 0's digest equal the baseline's",
          good, "; ".join(lines))

    # G1 — phase A moved no pixel where it acts, and phase B is absent
    good, lines = True, []
    for fixture in ("ODDFULL", "TALLFULL"):
        for preset in EVEN_ROWS:
            base = cases[f"G1 {fixture} {preset}"]
            done = odd[(fixture, preset)]
            if not done["ok"] or done["file"] is None:
                good = False
                lines.append(f"{fixture} {preset}: no file ({done['error']})")
                continue
            raster = Raster(done["path"])
            eight = raster.eight()
            now = {"frame0": raster.digest(), "samples": raster.samples(), "eight": eight,
                   "eight_class": [kind(p) for p in eight]}
            if base["frame0"] is None:
                same = (base["eight_class"] is not None
                        and base["eight_class"] == now["eight_class"])
                text = ("[the recordings disagreed on frame0: the eight pixels' classes "
                        "compared instead] " + ("equal" if same else
                                                f"{now['eight_class']} against "
                                                f"{base['eight_class']}"))
            else:      # R1 and R2 score the sizes
                same, text = held({key: base[key] for key in ("frame0", "eight")}, now)
            black = now["eight_class"].count("black")
            good = good and same and black >= 1
            lines.append(f"{fixture} {preset}: {text}, {black} of the eight black")
    absent = export(client, fx, "CLEAR", "hevc_alpha")
    unknown = (not absent["ok"]) and absent["error"].startswith(
        'export: unknown export preset "hevc_alpha"') and not absent["path"].exists()
    check("G1 ODDFULL and TALLFULL as h264, hevc and prores_422: frame 0's digest and the "
          "eight edge pixels equal the baseline's, a black one among them; hevc_alpha is "
          "still an unknown preset and writes no file",
          good and unknown,
          "\n       ".join(lines) + f"\n       hevc_alpha: {absent['error'] or 'EXPORTED'}")


def close_all(client, fx):
    closes = [attempt(client, "close_project", {"project": str(path), "discard": True})
              for path in fx.values()]
    return all(c["ok"] for c in closes), [c.get("error", "ok") for c in closes]


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--rows", choices=["size"])
    parser.add_argument("--record-baseline", action="store_true")
    args = parser.parse_args()
    if not args.record_baseline and args.rows != "size":
        print("instrument failure: this file holds phase A's rows only — run it with "
              "--rows size (the hevc_alpha rows are phase B's and are not written yet)")
        return 2
    try:
        today = host()
    except Exception as error:  # no chip, no macOS version or no ffmpeg to name
        print(f"instrument failure: the host could not be read: {error}")
        return 2
    baseline = None
    if not args.record_baseline:
        if not BASELINE.exists():
            print(f"instrument failure: no baseline at {BASELINE} (--record-baseline, twice, "
                  "on the build before G-33's code)")
            return 2
        baseline = json.loads(BASELINE.read_text())
        if baseline.get("recordings", 0) < 2:
            print(f"instrument failure: the baseline holds {baseline.get('recordings')} "
                  "recording; it takes two")
            return 2
        if baseline.get("host") != today:
            print("instrument failure: the baseline "
                  + ("was recorded on another host" if isinstance(baseline.get("host"), dict)
                     else "does not say which host recorded it") + ". Its cases "
                  "are that host's encoder bitstreams, ffprobe values and ffmpeg digests, so "
                  "no row is scored against it here.\n"
                  f"  the baseline's host: {host_text(baseline.get('host'))}\n"
                  f"  today's host:        {host_text(today)}\n"
                  "  A baseline for this host is recorded from a work tree of the commit "
                  f"before G-33's code ({str(baseline.get('head'))[:7]}): tools/proof/README.md, "
                  "this proof's section.")
            return 2
    remove_work()
    atexit.register(remove_work)
    HOME.mkdir(parents=True)
    OUT.mkdir()
    binary = Path(args.app) / "Contents/MacOS/Reelcut"
    if not binary.is_file():
        print(f"instrument failure: no app binary at {binary}")
        return 2
    print("B85 phase 3 — " + ("recording the baseline" if args.record_baseline else
                              "Gate A: the size reported is the size written"), flush=True)
    print(f"  host {host_text(today)}" + ("" if args.record_baseline else
          f" — the baseline's, recorded on the build of {str(baseline.get('head'))[:7]}"),
          flush=True)
    launched = launch(Path(args.app))
    document, ran = None, False
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return 2
        client = launched.client
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        support = HOME / "Library/Application Support"
        check("H0 the scratch home took: <home>/Library/Application Support is a directory",
              support.is_dir(), str(support))
        if rows.get("H0"):
            fx = {}
            try:
                fx = fixtures(client)
                if args.record_baseline:
                    document = record(client, fx, args.app, today)
                else:
                    run_size(client, fx, baseline)
                ran = True
            except Exception as error:  # a row that could not run is a failure
                print(f"  FAIL could not go on: {type(error).__name__}: {error}", flush=True)
            closed, how = close_all(client, fx) if fx else (False, ["no fixture was made"])
            complaints = [line.strip() for line in open(WORK / "reelcut.log", errors="replace")
                          if "Reelcut: " in line]
            check("Z1 every project closes and the log holds no `Reelcut: ` line",
                  closed and not complaints, f"closed {how}; complaints {complaints}")
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if args.record_baseline:
        if not (ran and rows.get("H0") and rows.get("Z1")):
            print("NOT RECORDED: the instrument could not run")
            return 2
        if document is None:
            return 1
        write_baseline(document)
        return 0
    passed = sum(1 for name in SIZE_ROWS if rows.get(name))
    print(f"{passed}/{len(SIZE_ROWS)}")
    return 0 if passed == len(SIZE_ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
