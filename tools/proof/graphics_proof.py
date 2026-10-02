#!/usr/bin/env python3
"""A graphic clip DRAWN, against the built app: road map 10's G3b and G3c
(§10.6) — the draw, then a failing graphic's error card, `render_frame`'s
diagnostics, the export gate and the pinned set — G4a (§10.7), the
agent's write/read loop: `write_graphic`, `get_graphic`, `graphic_reference`,
`get_project`'s `graphics` and the reference written into `graphics/` — and
G4b (§10.7), `render_graphic`'s contact sheet, the two imports and the loop
end to end — and G5b (§10.9), W1: a font landed from the shell in a
module-less `graphics/` reaches the library through the store's own post.

One owned instance on its own port, launched and stopped by PID, with its log
at `tools/proof/work/graphics/reelcut-<port>.log`; nothing else is ever
killed. Every child runs under `graphics_spike/bounded.py`, and every wait is
a bounded poll. The G3 rows' modules are written OUTSIDE a package and `mv`d
into its `graphics/` from the shell; the G rows write through `write_graphic`.
`bar.js` is this
script's own: one rect at x = frame × 4, 100 wide, 100 + 20 × len(title)
tall, filled with `props.color` — no fonts, and no `meta` size, so its raster
is the 1920 × 1080 canvas and maps 1:1. Frame N is N × 20000 ticks.

P1  `add_graphic_clip {name: "bar", track, at: 0}` (polled for at most 5 s
    while the store sees the module land) → `get_project` shows
    `graphic.name == "bar"` and duration 2 400 000 (meta's 120 frames);
P2  frame 30, where the rect covers x ∈ [120, 220): the EDGE pixels
    (122,50) == (255,90,54) and (222,50) == (0,0,0) pin the frame number
    (both flip at frame 31); (50,50) is black; a CONTROL: frame 31 differs;
P3  `move_clip` by 17 frames: frame 47 byte-identical to P2's frame 30; undo;
S1  `split` at frame 40: frame 41 byte-identical before and after; undo;
R1  `set_graphic {props: {title: "B"}}` changes frame 30; `{props: {nope:
    1}}` is refused naming `props.nope`; ONE undo restores P2's bytes;
H1  a `bar.js` whose colour default is #2d7ff9 `mv`d in: within 5 s pixel
    (170,50) == (45,127,249);
L1  `set_graphic {props: {color: "#2d7ff9"}}`, then a `bar.js` whose schema
    has no `color` (and whose rect is 120 wide, so its landing is visible at
    (230,50)): the stale stored prop still draws, (170,50) == (45,127,249);
F1  `lower-third` on its own project: frame 30 pixel (100,900) ==
    (255,90,54), the accent bar (fonts through the bundled library).
    MEASURED, not scored: mismatching pixels and the max channel delta
    against `graphics_ffi_probe.py`'s frame-30 BGRA over black;
K1  save, stop, relaunch, `open_project`: frame 30 byte-identical;
K2  `save_project {path: P1b}`: `P1b/graphics/bar.js` present, frame 30
    identical;
T1  `set_canvas {fps: [30000, 1001]}`: frame 30 at tick 600 600
    byte-identical to the 30 fps canvas's frame 30;
K3  an untitled `new_project`, `bar.js` moved into its new
    `<DARWIN_USER_TEMP_DIR>/Reelcut/*-graphics` root, a clip added,
    `save_project {path: P2}`, relaunch, `open_project`: frame 30 identical;
A1  a transparent canvas plus `callout`, exported as `prores_4444`, decoded
    at 2 s with ffmpeg: alpha 0 at (0,0) and 255 at (1300,432), the stroke;
E1  (P1 reopened, `throw10.js`, `spin.js`, `nofont.js` mv'd into it and a
    front track added; each E row adds its own clip there and `undo`es it)
    `throw10`: frame 9's reply does not name `throw10` (`bar`'s stale-`color`
    warning from L1 is G-4's leniency and stays) and (50,50) is RED; frame
    10's reply names `"throw10"`, `frame 10` and `boom at ten`, (1,540) is
    the card's border (230,40,40) and (1900,1060) its fill (64,8,8); an
    `export {preset: h264}` answers an error naming `"throw10"` and `frame
    10`, and no file is at the path;
C4  `render_graphic {name: throw10, frames: [9, 10], max_width: 8192}` names
    `"throw10"`, `frame 10` and `boom at ten`; cell 1 is the error card
    ((1929,540) BORDER, (3828,1060) CARD) and cell 0's (50,50) is RED;
E2  `spin` (`while(true){}`): `render_frame` at frame 0 returns within 3 s
    (wall clock printed) with `budget` in its text; `get_project` then
    answers within 5 s;
E3  `nofont` (`font-family="'Nope Sans'"`): one `render_frame` at frame 0
    names `Nope Sans` and `IBM Plex Mono` (the pool's hit path is Q3's —
    every `render_frame` builds a fresh compositor);
E4  a fresh project with `pin.js` and a 3 s `pin` clip, exported as
    `prores_4444` over MCP, decoded at 2 s: (480,540) within ±6 of RED —
    `export` passes the document's set (an offline key with no pin slates).
    It does NOT race a module swap: the server is one thread and `export`
    holds it, so no MCP call can observe the registry mid-export;
Q1  (`graphics_pin_probe.swift`, built from `app/Sources` like
    `phase7_chrome.py`'s probe, over the saved project PQ — `pin.js` and
    `nofont.js`, a 3 s `pin` clip) `queue pin`: the job enqueued with the
    document's set, then the canvas turned blue and the document's set
    REMOVED before any frame: at 1 s (480,540) within ±6 of RED and
    (1440,540) of BLACK; CONTROL `queue nopin`: (480,540) is NOT RED;
Q2  the same through `Exporter.export` directly: `direct pin` RED,
    `direct nopin` not;
Q3  `hit`: one `LayerRenderers` asked twice for `nofont`: both answers'
    `warnings` name `Nope Sans`, and the second is the pool's hit (the same
    texture object);
G6  (first, on the fresh launch, before any project is open) `graphic_reference
    {}` is not an error and its text is `docs/graphics-api.md` and the app's
    `Contents/Resources/GraphicsAPI.md`, both;
G1  (after A1) `new_project {path: WG}`; `get_graphic {}` before any write:
    folder `<WG>/graphics`, not existing, no modules; `write_graphic` of
    BROKEN_BAR (bar.js with its schema line, line 2, broken): ok false, the
    first diagnostic an error on line 2 (never the column), the file holds
    those bytes; `write_graphic` of bar.js: ok, schema keys title and color,
    revision = hashlib's, path `<WG>/graphics/bar.js`, no clips, the note says
    "not undoable";
G2  `API.md` and `API.d.ts` in `<WG>/graphics` byte-equal to
    `docs/graphics-api.md` / `docs/graphics-api.d.ts`; `get_graphic {}` now
    says the folder exists and holds one module;
G3  `add_graphic_clip {name: bar}` succeeds on the FIRST attempt (a CONTROL:
    no poll); `get_graphic {name: bar}` lists that clip and the source;
    `get_project`'s `graphics` is `[{name: bar, revision, ok: true, clips}]`;
G4  saved, `unsaved_changes` false; `write_graphic` of a blue bar.js answers the
    new revision and leaves `unsaved_changes` false (G-3); ONE `render_frame`
    at frame 30 with no poll: (170,50) is blue — the registry was current at
    the reply;
G5  `write_graphic {name: Bad}` is an error saying "is not a module name";
    `write_graphic {name: x}` with no source is an error naming `source`;
G7  `new_project {path: NG}`, `add_track`, `save_project`: NG/graphics is ABSENT
    (the manual never creates it) and `get_graphic {}` says so;
C1  (after G7, on WG, whose bar.js is BLUE since G4) `render_graphic {frames:
    [0, 0], background: "#000000", max_width: 8192}` is a 3848×1104 PNG whose
    cell 0 (columns 0–1919) and cell 1 (1928–3847) are byte-identical over
    rows 0–1079, the text naming "2 frame"; `frames: [0, 30]`: the cells differ;
C2  Placement: `render_frame` at frame 30 and `render_graphic {frame: 30,
    background: "#000000", max_width: 8192}` agree in every RGB pixel of the
    1920×1080 cell (0 of 2 073 600 differ — F1's comparison);
C3  `render_graphic {frame: 30, format: "svg"}`: ok, frame 30, the rect at
    `x="120"`, no diagnostics;
C5  (issue batch B8, #104; spec §11 G-19 (a)) `render_graphic {name: bar,
    frame: 30, format: svg, path: WORK/c5.svg}` is refused with "format svg
    takes no path, background or max_width — … (got path)." and writes no
    file; `{…, background: "#000000", max_width: 100}` is refused with "…(got
    background, max_width).";
C6  (B8, G-19 (b)) `{name: bar, frame: 150, format: svg}`, past bar's 120
    frames, is ok: `frame` 150, `ctx.durationInFrames` 120, `ctx.progress` 1
    — a frame past the length is drawn, as a longer clip draws it (G-9);
G10 (issue batch B19, #105; spec §11 G-20 (e); after G7, on the open WG)
    `graphic_reference {project: WG}` is ok and its text is
    `docs/graphics-api.md`; `{project: WORK/nowhere.reelcut}` is an error
    containing "No open project is at";
C7  (B19, G-20 (d); on WG) `render_graphic {name: bar, frames: [0, 1, 2],
    width: 8192, height: 8192, path: WORK/c7.png}` is an error naming
    134217728 and 201326592, and `c7.png` does not exist; CONTROL: `{frames:
    [0, 1]}` at 8192×8192, exactly the cap, is ok and names "2 frame";
G11 (B19, B31, #172, #183, G-20 (a)) `new_project {path: WS}`, `write_graphic`
    of 17 modules `m00`…`m16`; a SETTLE: `m00.js` rewritten in place until
    `get_graphic {name: m00}` answers its revision (a pass ran after every
    write event from the setup), then 0.3 s (one coalesce interval and margin,
    for the pass the settle's own write may leave pending); `m16.js` rewritten
    IN PLACE (same inode) from the shell: after 2 s `get_graphic {name: m16}`'s
    revision is unchanged (the 17th file is past the 16-source cap); CONTROL: `m00.js`
    then rewritten in place: within 5 s the revisions of both `m00` and
    `m16` are hashlib's of their new bytes (the next pass reads every file);
I1  `write_graphic needsfont` (120 px white text in `'Oswald'`): its sheet over
    black has 0 lit pixels and names Oswald; `import_graphic_font` of
    `/Library/Fonts/Oswald-Medium.ttf` answers families `["Oswald"]` (the
    engine's name; CoreText says "Oswald Medium"), `library_families` holding
    Oswald, IBM Plex Mono and Source Sans 3, its path in `fonts/`, not
    replaced, and `get_graphic {}`'s `families` the same list; the sheet then
    lights pixels and names no Oswald; Arial answers `["Arial"]` and replaces
    the second time; a `.ttf` holding text is refused with "loaded no face"
    and a `.txt` naming ".ttf". A missing Oswald file is a FAIL, not a skip;
I2  `write_graphic usesasset` (`<image href="${asset("red.png")}">`): its sheet
    names red.png and (50,50) is black; `import_graphic_asset` of
    `graphic/tests/assets/red.png` answers name red.png and assets
    `["red.png"]`, and so does `get_graphic {}`; the sheet's (50,50) is then
    (255,0,0) with no red.png in the text; an empty file is refused with
    "empty" and a `.txt` naming "PNG";
G9  `chmod 311 <WG>/graphics`: `write_graphic {name: ghost}` is refused saying
    it "was written" and the scan "does not list" it; `chmod 755`: the same
    write is ok;
I3  `save_project` on WG: `fonts/Oswald-Medium.ttf`, `fonts/Arial.ttf` and
    `assets/red.png` are in the package, `unsaved_changes` false;
I4  a new IE, its `graphics/` holding no module: `import_graphic_font` of
    Oswald-Medium.ttf lists Oswald in `library_families` at once, and
    `needsfont` written after it renders lit pixels naming no Oswald (the
    store posts when the library moved even with no module, G5b, so the
    import's own `rescan()` rebuilds the library);
I5  (issue batch B67, #105, spec §11 G-23; on IE after I4)
    `import_graphic_asset {path: red.png, name: "#logo&mark.png"}` answers
    `name` logo-mark.png, `renamed_from` "#logo&mark.png", `replaced` false;
    again answers logo-mark-2.png; a module drawing `asset("logo-mark-2.png")`
    renders (50,50) (255,0,0) naming no logo-mark-2.png; `name: "My Photo
    (1).png"` answers that name and no `renamed_from`. Made to fail once
    against the baseline build (B65's, before the rename);
W1  a new IW, module-less: `get_graphic {}`'s families lack Oswald (CONTROL);
    from the SHELL `mkdir -p IW/graphics/fonts` and `cp` Oswald-Medium.ttf in;
    `get_graphic {}` polled for at most 5 s until its families hold Oswald;
    `write_graphic needsfont` then renders lit pixels naming no Oswald — the
    watcher's own post, with no tool in the path (G5b);
L2  the loop of §5h on a new LP: `graphic_reference`, `write_graphic`
    BROKEN_BAR (ok false, line 2), `write_graphic` bar (ok), `render_graphic
    {frames: [0, 15, 30]}` at the DEFAULT max_width is exactly 2048×1202 and
    names "3 frame", `add_graphic_clip`, `render_frame` at frame 30 has
    (122,50) RED, `set_graphic {props: {title: "Looped"}}` changes that frame;
G8  (a fresh instance) an untitled `new_project`; its root from `get_graphic
    {}` (existing, no modules) given `fonts/Anton-Regular.ttf` only;
    `save_project {path: NF}`: `NF/graphics/fonts/Anton-Regular.ttf` exists,
    no `.js`, `get_graphic {}` now names `NF/graphics`, existing, and the
    untitled root it named before the save no longer exists (B8, G-19 (d));
Z1  `grep "Reelcut: "` over every launch's log prints nothing.

    python3 tools/proof/graphics_proof.py [--port 4879] [--app PATH]
    python3 tools/proof/graphics_proof.py --mutant frame-plus-one
    python3 tools/proof/graphics_proof.py --mutant sheet-uncapped
    python3 tools/proof/graphics_proof.py --mutant reference-unchecked
    python3 tools/proof/graphics_proof.py --mutant store-uncapped

A mutant is built in a COPY of the tree from `tree_copy.make_copy` (`app/` and
`agent/` copied, every other build input `project.yml` names linked) by
`build_mutant(file, anchor, replacement)`, the anchor asserted to occur
exactly once in `app/Sources/<file>`; the copy is built by its own `make app`
into its own directory and driven through its own rows only.
`frame-plus-one` asks the module for `frame + 1` in `LayerRenderersGraphic.swift`
and is driven through P1 and P2; P2 must FAIL. The rows past P2 are relative
and a uniform +1 moves both sides of them, so they are not expected to fail.
`sheet-uncapped` removes `render_graphic`'s pixel cap (C7 must FAIL),
`reference-unchecked` removes `graphic_reference`'s `target` line (G10), and
`store-uncapped` removes `.prefix(Self.fileSourceLimit)` from the store's
file-arm loop (G11); C7's and G10's setup is `new_project` plus
`write_graphic bar`. Exit 0 means the row FAILED in the mutant, which is the
pass, and 1 that it survived. Exit 2 (rule R, issue batch B13) means the
control could not be performed — the copy did not build or launch, the setup
did not hold, or the row's own control half failed — printed as `mutant
<name>: the control could not be performed — <why>`.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import shutil
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/graphics"
APP = ROOT / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
FIXTURES = ROOT / "graphic/tests/graphics"
FFI_BGRA = ROOT / "tools/proof/work/graphics-ffi-probe/lower-third-30.bgra"
PIN_PROBE_SOURCE = ROOT / "tools/proof/graphics_pin_probe.swift"
# Outside WORK, which every run empties, so an up-to-date probe is not rebuilt.
PIN_PROBE_DIR = ROOT / "tools/proof/work/graphics-pin-probe"
CALL_BOUND = 300
FRAME = 20000
RED, BLUE, BLACK = (255, 90, 54), (45, 127, 249), (0, 0, 0)
BORDER, CARD = (230, 40, 40), (64, 8, 8)
SECOND = 30 * FRAME
ROWS = ["G6", "P1", "P2", "P3", "S1", "R1", "H1", "L1", "F1", "K1", "K2", "T1", "K3", "A1",
        "G1", "G2", "G3", "G4", "G5", "G7", "G10", "C1", "C2", "C3", "C5", "C6", "C7", "I1", "I2",
        "G9", "I3", "I4", "I5", "W1", "L2", "G11",
        "G8", "E1", "C4", "E2", "E3", "E4", "Q1", "Q2", "Q3", "Z1"]
DOC_MD = ROOT / "docs/graphics-api.md"
DOC_DTS = ROOT / "docs/graphics-api.d.ts"
ANCHOR = "frame: frame, propsJSON: propsJSON, ctxJSON: ctxJSON,"
SHEET_GUARD = (
    "        let pixels = frames.count * context.width * context.height\n"
    "        if format == \"png\", pixels > GraphicContactSheet.maxCellPixels {\n")
REFERENCE_CHECK = (
    "        if let project = a[\"project\"], !(project is NSNull) { _ = try target(a) }\n")
# name: (file in app/Sources, anchor, replacement, the row it must fail)
MUTANTS = {
    "frame-plus-one": ("LayerRenderersGraphic.swift", ANCHOR,
                       ANCHOR.replace("frame: frame,", "frame: frame + 1,"), "P2"),
    "sheet-uncapped": ("AgentServer+GraphicRender.swift", SHEET_GUARD,
                       "        let pixels = frames.count * context.width * context.height\n"
                       "        if format == \"png\", pixels < 0 {\n", "C7"),
    "reference-unchecked": ("AgentServer+Graphics.swift", REFERENCE_CHECK, "", "G10"),
    "store-uncapped": ("GraphicStore.swift", ".prefix(Self.fileSourceLimit)", "", "G11"),
}
CAP = 134_217_728
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


def bar(color="#ff5a36", with_color=True, width=100):
    """This script's module. JS template `${…}` is spelled with `@{…}` here
    and swapped at the end, so no Python brace is doubled."""
    schema = 'title: { type: "string", default: "Jane" }'
    if with_color:
        schema += f', color: {{ type: "color", default: "{color}" }}'
    body = ('<rect x="@{frame * 4}" y="0" width="' + str(width) + '" '
            'height="@{100 + props.title.length * 20}" fill="@{props.color}"/>')
    return ("export const meta = { name: \"Bar\", durationInFrames: 120 };\n"
            "export const schema = { " + schema + " };\n"
            "export function render(frame, props, ctx) {\n"
            "  return svg(ctx, `" + body + "`);\n"
            "}\n").replace("@{", "${")


def module(render_body, frames=120):
    """A schema-less module whose `render` is `render_body`."""
    return ("export const meta = { name: \"G3c\", durationInFrames: " + str(frames) + " };\n"
            "export function render(frame, props, ctx) {\n" + render_body + "\n}\n")


# bar() with line 2, its schema, broken; `render` on line 3 is intact.
BROKEN_BAR = "\n".join(
    line if i != 1 else "export const schema = { title: ;"
    for i, line in enumerate(bar().split("\n")))

PIN_JS = ("export const meta = { name: \"Pin\", durationInFrames: 90 };\n"
          "export const schema = { color: { type: \"color\", default: \"#ff5a36\" } };\n"
          "export function render(frame, props, ctx) {\n"
          "  return svg(ctx, `<rect x=\"0\" y=\"0\" width=\"960\" height=\"1080\" "
          "fill=\"${props.color}\"/>`);\n}\n")
THROW10_JS = module(
    '  if (frame === 10) throw new Error("boom at ten");\n'
    '  return svg(ctx, `<rect x="0" y="0" width="100" height="100" fill="#ff5a36"/>`);')
SPIN_JS = module("  while (true) {}")
NOFONT_JS = module(
    "  return svg(ctx, `<text x=\"100\" y=\"300\" font-family=\"'Nope Sans'\" "
    "font-size=\"120\" fill=\"#ffffff\">Nope</text>`);")
NEEDSFONT_JS = module(
    "  return svg(ctx, `<text x=\"100\" y=\"300\" font-family=\"'Oswald'\" "
    "font-size=\"120\" fill=\"#ffffff\">Hello</text>`);")
USESASSET_JS = module(
    '  return svg(ctx, `<image href="${asset("red.png")}" x="0" y="0" width="200" '
    'height="200"/>`);')
OSWALD = Path("/Library/Fonts/Oswald-Medium.ttf")
ARIAL = Path("/System/Library/Fonts/Supplemental/Arial.ttf")
RED_PNG = ROOT / "graphic/tests/assets/red.png"
PURE_RED = (255, 0, 0)


class Instance:
    """One owned app, by PID, on its own port; each launch reads only the part
    of the log it appended."""

    def __init__(self, app, port, log):
        self.app, self.port, self.log = app, port, log
        self.child = None

    def start(self):
        offset = self.log.stat().st_size if self.log.exists() else 0
        with open(self.log, "a") as out:
            self.child = subprocess.Popen(
                [str(self.app), "-ApplePersistenceIgnoreState", "YES",
                 "-AgentServerEnabled", "YES"],
                stdin=subprocess.DEVNULL, stdout=out, stderr=out, start_new_session=True,
                env=bounded.child_env({"RC_AGENT_PORT": str(self.port)}))
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            time.sleep(0.25)
            with open(self.log) as handle:
                handle.seek(offset)
                found = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", handle.read())
            if found:
                bound = int(found.group(1))
                print(f"  instance PID {self.child.pid} on port {bound}", flush=True)
                return mcp.MCP(bound, timeout=CALL_BOUND)
        return None

    def stop(self):
        if self.child is None:
            return
        self.child.terminate()
        try:
            self.child.wait(timeout=30)
        except subprocess.TimeoutExpired:
            self.child.kill()
            self.child.wait()
        self.child = None


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


def with_project(project, arguments):
    return dict(arguments, project=str(project)) if project else dict(arguments)


def mv_in(folder, name, text, make_folder=False):
    """Writes OUTSIDE the package, then `mkdir` / `mv` — how another process
    lands a file."""
    outside = WORK / f"outside-{name}"
    outside.write_text(text)
    if make_folder:
        bounded.run(["mkdir", "-p", str(folder)], 30)
    return bounded.run(["mv", str(outside), str(Path(folder) / name)], 30)["rc"]


def temp_roots():
    """The untitled roots under `getconf DARWIN_USER_TEMP_DIR`, which TMPDIR
    does not move (G3a measured it)."""
    base = bounded.run(["getconf", "DARWIN_USER_TEMP_DIR"], 30)["stdout"].strip()
    return set(glob.glob(os.path.join(base, "Reelcut", "*-graphics")))


def complaints(log):
    try:
        return [line.strip() for line in open(log) if "Reelcut: " in line]
    except OSError:
        return ["the log could not be read"]


def project_of(client, project):
    got = attempt(client, "get_project", with_project(project, {}))
    return got["reply"]["project"] if got["ok"] else None


def land(client, project, name, track, at, extra=None):
    """`add_graphic_clip` polled for at most 5 s — a refusal is an answer
    while the store has not seen the module. The new clip, or None and the
    last sentence."""
    deadline = time.monotonic() + 5
    last = ""
    while time.monotonic() < deadline:
        got = attempt(client, "add_graphic_clip",
                      with_project(project, dict({"name": name, "track": track, "at": at},
                                                 **(extra or {}))))
        if got["ok"]:
            clips = (project_of(client, project) or {}).get("clips", [])
            ours = [c for c in clips if (c.get("graphic") or {}).get("name") == name]
            return (max(ours, key=lambda c: c["id"]) if ours else None), ""
        last = got["error"]
        time.sleep(0.2)
    return None, last


def render(client, project, t, tag):
    """`render_frame` at tick `t` into `work/<tag>.png`; its bytes, or None."""
    path = WORK / f"{tag}.png"
    if path.exists():
        path.unlink()
    got = attempt(client, "render_frame", with_project(project, {"t": t, "path": str(path)}))
    if not got["ok"] or not path.exists():
        print(f"  render {tag}: {got.get('error', 'no file')}", flush=True)
        return None
    return path.read_bytes()


def render_text(client, project, t, tag):
    """`render_frame` at `t`: (its reply text, the PNG's bytes, the wall
    clock in seconds)."""
    path = WORK / f"{tag}.png"
    if path.exists():
        path.unlink()
    started = time.monotonic()
    got = attempt(client, "render_frame", with_project(project, {"t": t, "path": str(path)}))
    seconds = time.monotonic() - started
    text = got["reply"] if got["ok"] else got["error"]
    data = path.read_bytes() if got["ok"] and path.exists() else None
    return str(text), data, seconds


def decode_png(data, upto=None):
    """`e1_proof.py`'s 8-bit non-interlaced PNG reader, stopping after row
    `upto` — a pixel near the top needs only the rows above it, which keeps a
    bounded poll from spending its bound on decoding. (width, channels, rows)."""
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        raise RuntimeError("an 8-bit non-interlaced PNG is the only kind read here")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    out, prev, pos = [], bytearray(stride), 0
    for _ in range(height if upto is None else min(height, upto + 1)):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pred = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            raise RuntimeError(f"unknown PNG filter {kind}")
        out.append(bytes(cur))
        prev = cur
    return width, channels, out


def pixel(data, x, y):
    if data is None:
        return None
    _, channels, found = decode_png(data, upto=y)
    row = found[y]
    return tuple(row[x * channels:x * channels + 3])


def poll_pixel(client, project, x, y, want, tag):
    """`render_frame` at frame 30 until (x, y) is `want`, for at most 5 s."""
    deadline = time.monotonic() + 5
    seen = None
    while time.monotonic() < deadline:
        seen = pixel(render(client, project, 30 * FRAME, tag), x, y)
        if seen == want:
            return seen
        time.sleep(0.2)
    return seen


def decode_rgba(path):
    """A PNG at `path` as (width, height, RGBA bytes) through ffmpeg — the
    sheets are up to 3848 px wide, too slow for `decode_png`'s loops — or
    None. Binary output, so not `bounded.run`; bounded all the same."""
    try:
        data = Path(path).read_bytes()
        width, height = struct.unpack(">II", data[16:24])
        raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
                              "-pix_fmt", "rgba", "-"], capture_output=True, timeout=120,
                             env=bounded.child_env()).stdout
    except (OSError, struct.error, subprocess.TimeoutExpired):
        return None
    return (width, height, raw) if len(raw) == width * height * 4 else None


def rgb_at(image, x, y):
    if image is None:
        return None
    width, _, raw = image
    i = (y * width + x) * 4
    return tuple(raw[i:i + 3])


def cell_row(image, x, y, w):
    """Row `y` of the `w` pixels from column `x`, RGBA."""
    width, _, raw = image
    return raw[(y * width + x) * 4:(y * width + x + w) * 4]


def rgb_mismatches(a, ax, b, bx, w, h):
    """Pixels of the `w`×`h` block at column `ax` of `a` and `bx` of `b`
    (both from row 0) whose RGB differ."""
    if a is None or b is None:
        return None
    count = 0
    for y in range(h):
        ra, rb = cell_row(a, ax, y, w), cell_row(b, bx, y, w)
        if all(ra[c::4] == rb[c::4] for c in range(3)):
            continue
        count += sum(1 for i in range(w) if ra[4 * i:4 * i + 3] != rb[4 * i:4 * i + 3])
    return count


def nonblack(image, w, h):
    """Pixels of the `w`×`h` block at the top left whose RGB is not black."""
    if image is None:
        return None
    count = 0
    for y in range(h):
        row = cell_row(image, 0, y, w)
        channels = [row[c::4] for c in range(3)]
        if all(ch.count(0) == w for ch in channels):
            continue
        count += sum(1 for i in range(w) if any(ch[i] for ch in channels))
    return count


def sheet(client, project, arguments, tag):
    """`render_graphic` into `work/<tag>.png`: (ok, its text or error, the
    decoded sheet or None)."""
    path = WORK / f"{tag}.png"
    if path.exists():
        path.unlink()
    got = attempt(client, "render_graphic", with_project(project, dict(arguments, path=str(path))))
    text = str(got["reply"] if got["ok"] else got["error"])
    return got["ok"], text, decode_rgba(path) if got["ok"] and path.exists() else None


def run_p1_p2(client, p1):
    """P1 and P2 — the rows the mutant is driven through too. The clip, the
    track, and frames 30's and 31's bytes (None when not rendered)."""
    made = attempt(client, "new_project", {"path": str(p1)})
    rc = mv_in(p1 / "graphics", "bar.js", bar(), make_folder=True)
    project = project_of(client, p1) or {}
    track = (project.get("tracks") or [{}])[0].get("id")
    clip, why = land(client, p1, "bar", track, 0)
    check("P1 add_graphic_clip {name: bar} lands the stored graphic, 120 frames long",
          made["ok"] and rc == 0 and clip is not None
          and clip["graphic"]["name"] == "bar" and clip["duration"] == 2_400_000,
          f"new {made['ok']}, mv rc {rc}, clip {clip}, last refusal {why!r}")
    f30 = render(client, p1, 30 * FRAME, "p2-f30")
    f31 = render(client, p1, 31 * FRAME, "p2-f31")
    edge_in, edge_out, left = pixel(f30, 122, 50), pixel(f30, 222, 50), pixel(f30, 50, 50)
    check("P2 frame 30: (122,50) is the bar's red and (222,50) black — the frame number, "
          "pinned at both edges; (50,50) black; CONTROL: frame 31 differs",
          edge_in == RED and edge_out == BLACK and left == BLACK
          and f31 is not None and f31 != f30,
          f"(122,50) {edge_in}, (222,50) {edge_out}, (50,50) {left}, "
          f"frame 31 differs {f31 is not None and f31 != f30}")
    return clip, track, f30, f31


def run(app, port):
    log = WORK / f"reelcut-{port}.log"
    wg, ng, nf = (WORK / f"{n}.reelcut" for n in ("WG", "NG", "NF"))
    p1, p1b, p2, pf, pa = (WORK / f"{n}.reelcut" for n in ("P1", "P1b", "P2", "F", "A"))
    instance = Instance(app, port, log)
    try:
        client = instance.start()
        if client is None:
            check("P1 the app launches", False, "the app never logged its port")
            return log
        run_g6(client, app)
        clip, track, f30, _ = run_p1_p2(client, p1)
        cid = clip["id"] if clip else 0

        moved = attempt(client, "move_clip", {"project": str(p1), "clips": [cid],
                                              "delta": 17 * FRAME})
        f47 = render(client, p1, 47 * FRAME, "p3-f47")
        undone = attempt(client, "undo", {"project": str(p1)})
        check("P3 move_clip by 17 frames: frame 47 byte-identical to frame 30",
              moved["ok"] and undone["ok"] and f47 is not None and f47 == f30,
              f"move {moved['ok']}, identical {f47 == f30}")

        before = render(client, p1, 41 * FRAME, "s1-before")
        split = attempt(client, "split", {"project": str(p1), "clips": [cid], "at": 40 * FRAME})
        after = render(client, p1, 41 * FRAME, "s1-after")
        halves = [c for c in (project_of(client, p1) or {}).get("clips", [])
                  if (c.get("graphic") or {}).get("name") == "bar"]
        attempt(client, "undo", {"project": str(p1)})
        check("S1 split at frame 40: frame 41 byte-identical before and after",
              split["ok"] and len(halves) == 2 and before is not None and before == after,
              f"split {split}, halves {len(halves)}, identical {before == after}")

        titled = attempt(client, "set_graphic", {"project": str(p1), "clips": [cid],
                                                 "patch": {"props": {"title": "B"}}})
        changed = render(client, p1, 30 * FRAME, "r1-b")
        refused = attempt(client, "set_graphic", {"project": str(p1), "clips": [cid],
                                                  "patch": {"props": {"nope": 1}}})
        attempt(client, "undo", {"project": str(p1)})
        restored = render(client, p1, 30 * FRAME, "r1-undone")
        check("R1 props {title: B} changes frame 30; {nope: 1} is refused naming props.nope; "
              "one undo restores P2's bytes",
              titled["ok"] and changed is not None and changed != f30
              and not refused["ok"] and "props.nope" in refused["error"]
              and restored == f30,
              f"title {titled['ok']}, changed {changed != f30}, refusal "
              f"{refused.get('error', refused)!r}, restored {restored == f30}")

        rc = mv_in(p1 / "graphics", "bar.js", bar(color="#2d7ff9"))
        seen = poll_pixel(client, p1, 170, 50, BLUE, "h1")
        check("H1 a bar.js whose colour default is #2d7ff9, mv'd in: within 5 s (170,50) is "
              "that blue", rc == 0 and seen == BLUE, f"mv rc {rc}, (170,50) {seen}")

        coloured = attempt(client, "set_graphic", {"project": str(p1), "clips": [cid],
                                                   "patch": {"props": {"color": "#2d7ff9"}}})
        rc = mv_in(p1 / "graphics", "bar.js", bar(with_color=False, width=120))
        landed = poll_pixel(client, p1, 230, 50, BLUE, "l1")
        still = pixel(render(client, p1, 30 * FRAME, "l1-final"), 170, 50)
        check("L1 the stored color survives a schema that dropped it: (170,50) is blue once the "
              "120-wide module has landed at (230,50)",
              coloured["ok"] and rc == 0 and landed == BLUE and still == BLUE,
              f"set {coloured['ok']}, mv rc {rc}, (230,50) {landed}, (170,50) {still}")

        run_f1(client, pf)

        k1_ref = render(client, p1, 30 * FRAME, "k1-before")
        saved = attempt(client, "save_project", {"project": str(p1)})
        instance.stop()
        client = instance.start()
        opened = attempt(client, "open_project", {"path": str(p1)})
        k1_after = render(client, p1, 30 * FRAME, "k1-after")
        check("K1 saved, relaunched, open_project: frame 30 byte-identical",
              saved["ok"] and opened["ok"] and k1_ref is not None and k1_after == k1_ref,
              f"save {saved['ok']}, open {opened['ok']}, identical {k1_after == k1_ref}")

        saved = attempt(client, "save_project", {"project": str(p1), "path": str(p1b)})
        k2 = render(client, p1b, 30 * FRAME, "k2")
        present = (p1b / "graphics" / "bar.js").exists()
        check("K2 save_project {path: P1b}: P1b/graphics/bar.js present, frame 30 identical",
              saved["ok"] and present and k2 == k1_ref,
              f"save {saved}, present {present}, identical {k2 == k1_ref}")

        rate = attempt(client, "set_canvas", {"project": str(p1b), "fps": [30000, 1001]})
        t1 = render(client, p1b, 30 * 20020, "t1")
        check("T1 at 29.97 fps frame 30 is tick 600600, byte-identical to 30 fps frame 30",
              rate["ok"] and t1 is not None and t1 == k1_ref,
              f"set_canvas {rate}, identical {t1 == k1_ref}")

        # A fresh instance, so the untitled draft is the only open document
        # and every call's implicit target is it.
        instance.stop()
        client = instance.start()
        roots = temp_roots()
        made = attempt(client, "new_project", {})
        new_roots = sorted(temp_roots() - roots)
        rc = mv_in(new_roots[0], "bar.js", bar()) if len(new_roots) == 1 else None
        track3 = ((project_of(client, None) or {}).get("tracks") or [{}])[0].get("id")
        clip3, why = land(client, None, "bar", track3, 0)
        k3_ref = render(client, None, 30 * FRAME, "k3-before")
        saved = attempt(client, "save_project", {"path": str(p2)})
        present = (p2 / "graphics" / "bar.js").exists()
        instance.stop()
        client = instance.start()
        opened = attempt(client, "open_project", {"path": str(p2)})
        k3 = render(client, p2, 30 * FRAME, "k3-after")
        check("K3 an untitled project's graphic, saved for the first time and reopened: frame "
              "30 identical",
              made["ok"] and len(new_roots) == 1 and rc == 0 and clip3 is not None
              and saved["ok"] and present and opened["ok"] and k3_ref is not None
              and k3 == k3_ref,
              f"new roots {new_roots}, mv rc {rc}, clip {clip3 is not None} {why!r}, "
              f"save {saved}, present {present}, identical {k3 == k3_ref}")

        run_a1(client, pa)
        run_g(client, wg, ng)
        run_g10(client, wg)
        run_c(client, wg)
        run_c7(client, wg)
        run_i(client, wg)
        run_loop(client, WORK / "LP.reelcut")
        run_g11(client, WORK / "WS.reelcut")
        # A fresh instance, K3's pattern: the untitled draft is the implicit
        # target of every call.
        instance.stop()
        client = instance.start()
        run_g8(client, nf)
        run_e(client, p1)
        run_e4(client, WORK / "E4.reelcut")
        make_pq(client, WORK / "PQ.reelcut")
    finally:
        instance.stop()
    return log


def run_f1(client, pf):
    made = attempt(client, "new_project", {"path": str(pf)})
    rc = mv_in(pf / "graphics", "lower-third.js", (FIXTURES / "lower-third.js").read_text(),
               make_folder=True)
    track = ((project_of(client, pf) or {}).get("tracks") or [{}])[0].get("id")
    clip, why = land(client, pf, "lower-third", track, 0)
    frame = render(client, pf, 30 * FRAME, "f1")
    accent = pixel(frame, 100, 900)
    check("F1 lower-third frame 30: (100,900) is the accent bar's (255,90,54)",
          made["ok"] and rc == 0 and clip is not None and accent == RED,
          f"mv rc {rc}, clip {clip is not None} {why!r}, (100,900) {accent}")
    if frame is None or not FFI_BGRA.exists():
        print(f"  F1 measured: no comparison — {FFI_BGRA} absent (run graphics_ffi_probe.py)",
              flush=True)
        return
    width, channels, found = decode_png(frame)
    bgra = FFI_BGRA.read_bytes()
    mismatched, worst = 0, 0
    for y, row in enumerate(found):
        for x in range(width):
            i, j = x * channels, (y * width + x) * 4
            delta = max(abs(row[i] - bgra[j + 2]), abs(row[i + 1] - bgra[j + 1]),
                        abs(row[i + 2] - bgra[j]))
            if delta:
                mismatched += 1
                worst = max(worst, delta)
    print(f"  F1 measured (not scored): {mismatched} of {width * len(found)} pixels differ "
          f"from the FFI probe's frame-30 BGRA over black; max channel delta {worst}",
          flush=True)


def run_a1(client, pa):
    made = attempt(client, "new_project", {"path": str(pa)})
    rc = mv_in(pa / "graphics", "callout.js", (FIXTURES / "callout.js").read_text(),
               make_folder=True)
    clear = attempt(client, "set_canvas", {"project": str(pa), "background": [0, 0, 0, 0]})
    track = ((project_of(client, pa) or {}).get("tracks") or [{}])[0].get("id")
    clip, why = land(client, pa, "callout", track, 0)
    movie = WORK / "a1.mov"
    exported = attempt(client, "export", {"project": str(pa), "preset": "prores_4444",
                                          "path": str(movie)})
    # Binary output, so not `bounded.run` (a text-mode child); bounded all the same.
    try:
        raw = subprocess.run(["ffmpeg", "-v", "error", "-ss", "2", "-i", str(movie),
                              "-vframes", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
                             capture_output=True, timeout=120,
                             env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        raw = b""
    corner = centre = None
    if len(raw) == 1920 * 1080 * 4:
        corner, centre = raw[3], raw[(432 * 1920 + 1300) * 4 + 3]
    check("A1 transparent canvas + callout as prores_4444, at 2 s: alpha 0 at (0,0), 255 on "
          "the stroke at (1300,432)",
          made["ok"] and rc == 0 and clear["ok"] and clip is not None and exported["ok"]
          and corner == 0 and centre == 255,
          f"clip {clip is not None} {why!r}, export {exported.get('error', 'ok')}, "
          f"decoded {len(raw)} bytes, alpha {corner} / {centre}")


def run_g6(client, app):
    """G6 — before any project is open: the reference needs none."""
    got = attempt(client, "graphic_reference", {})
    bundled = Path(app).resolve().parents[1] / "Resources/GraphicsAPI.md"
    doc = DOC_MD.read_bytes().decode("utf-8")
    text = got.get("reply") if got["ok"] else None
    in_app = bundled.read_bytes().decode("utf-8") if bundled.exists() else None
    check("G6 graphic_reference with no project open answers docs/graphics-api.md verbatim, "
          "which is the app's Resources/GraphicsAPI.md",
          got["ok"] and text == doc and in_app == doc,
          f"ok {got['ok']} {got.get('error', '')!r}, equals doc {text == doc}, "
          f"bundled {bundled} equals doc {in_app == doc}")


def run_g(client, wg, ng):
    """G1–G5 on WG and G7 on NG, every call naming its project."""
    folder = wg / "graphics"
    made = attempt(client, "new_project", {"path": str(wg)})
    empty = attempt(client, "get_graphic", {"project": str(wg)})
    e = empty.get("reply") or {}
    broken = attempt(client, "write_graphic", {"project": str(wg), "name": "bar",
                                               "source": BROKEN_BAR})
    b = broken.get("reply") or {}
    diagnostics = b.get("diagnostics") or [{}]
    on_disk = (folder / "bar.js").read_text() if (folder / "bar.js").exists() else None
    good = attempt(client, "write_graphic", {"project": str(wg), "name": "bar",
                                             "source": bar()})
    g = good.get("reply") or {}
    revision = hashlib.sha256(bar().encode()).hexdigest()
    check("G1 before a write the folder is <WG>/graphics and absent; a broken bar.js is ok "
          "false with an error on line 2 and its bytes on disk; bar.js is ok with schema title "
          "and color, hashlib's revision, its path, no clips and the not-undoable note",
          made["ok"] and empty["ok"] and e.get("folder") == str(folder)
          and e.get("folder_exists") is False and e.get("modules") == []
          and broken["ok"] and b.get("ok") is False and b.get("meta") == {}
          and b.get("schema") == {} and diagnostics[0].get("level") == "error"
          and diagnostics[0].get("line") == 2 and on_disk == BROKEN_BAR
          and good["ok"] and g.get("ok") is True
          and sorted((g.get("schema") or {}).keys()) == ["color", "title"]
          and g.get("revision") == revision and g.get("path") == str(folder / "bar.js")
          and g.get("clips") == [] and "not undoable" in (g.get("note") or ""),
          f"new {made['ok']}, empty {empty}, broken {broken}, on disk equal "
          f"{on_disk == BROKEN_BAR}, good {good}")

    manual = [(folder / name).read_bytes() if (folder / name).exists() else None
              for name in ("API.md", "API.d.ts")]
    listed = attempt(client, "get_graphic", {"project": str(wg)})
    l = listed.get("reply") or {}
    check("G2 API.md and API.d.ts in <WG>/graphics are the docs' bytes; get_graphic {} says "
          "the folder exists and holds one module",
          manual == [DOC_MD.read_bytes(), DOC_DTS.read_bytes()]
          and listed["ok"] and l.get("folder_exists") is True
          and [m.get("name") for m in l.get("modules") or []] == ["bar"],
          f"API.md {manual[0] == DOC_MD.read_bytes()}, API.d.ts "
          f"{manual[1] == DOC_DTS.read_bytes()}, listed {listed}")

    track = ((project_of(client, wg) or {}).get("tracks") or [{}])[0].get("id")
    added = attempt(client, "add_graphic_clip", {"project": str(wg), "name": "bar",
                                                 "track": track, "at": 0})
    ours = [c for c in (project_of(client, wg) or {}).get("clips", [])
            if (c.get("graphic") or {}).get("name") == "bar"]
    cid = ours[0]["id"] if len(ours) == 1 else None
    one = attempt(client, "get_graphic", {"project": str(wg), "name": "bar"})
    o = one.get("reply") or {}
    whole = attempt(client, "get_project", {"project": str(wg)})
    graphics = (whole.get("reply") or {}).get("graphics")
    check("G3 add_graphic_clip on the FIRST attempt; get_graphic {name: bar} lists the clip "
          "and the source; get_project's graphics is [{name, revision, ok, clips}]",
          added["ok"] and cid is not None and one["ok"] and o.get("clips") == [cid]
          and o.get("source") == bar()
          and graphics == [{"name": "bar", "revision": revision, "ok": True, "clips": [cid]}],
          f"add {added}, clip {cid}, get_graphic {one}, graphics {graphics}")

    saved = attempt(client, "save_project", {"project": str(wg)})
    clean = (project_of_reply(client, wg) or {}).get("unsaved_changes")
    blue = bar(color="#2d7ff9")
    rewritten = attempt(client, "write_graphic", {"project": str(wg), "name": "bar",
                                                  "source": blue})
    r = rewritten.get("reply") or {}
    still = (project_of_reply(client, wg) or {}).get("unsaved_changes")
    seen = pixel(render(client, wg, 30 * FRAME, "g4"), 170, 50)
    check("G4 saved and clean; write_graphic of a blue bar.js answers its revision and leaves "
          "the project clean; ONE render_frame at frame 30: (170,50) is blue",
          saved["ok"] and clean is False and rewritten["ok"] and r.get("ok") is True
          and r.get("revision") == hashlib.sha256(blue.encode()).hexdigest()
          and r.get("clips") == [cid] and still is False and seen == BLUE,
          f"save {saved['ok']}, clean {clean}, write {rewritten}, after {still}, "
          f"(170,50) {seen}")

    bad = attempt(client, "write_graphic", {"project": str(wg), "name": "Bad",
                                            "source": bar()})
    bare = attempt(client, "write_graphic", {"project": str(wg), "name": "x"})
    check("G5 write_graphic {name: Bad} is refused as not a module name; {name: x} with no "
          "source is an error naming source",
          not bad["ok"] and "is not a module name" in bad["error"]
          and not bare["ok"] and "source" in bare["error"]
          and not (folder / "Bad.js").exists() and not (folder / "x.js").exists(),
          f"Bad {bad}, bare {bare}")

    made = attempt(client, "new_project", {"path": str(ng)})
    track = attempt(client, "add_track", {"project": str(ng)})
    saved = attempt(client, "save_project", {"project": str(ng)})
    after = attempt(client, "get_graphic", {"project": str(ng)})
    check("G7 a project saved without a graphic has no graphics/ and get_graphic says so",
          made["ok"] and track["ok"] and saved["ok"] and not (ng / "graphics").exists()
          and after["ok"] and (after.get("reply") or {}).get("folder_exists") is False,
          f"new {made['ok']}, track {track['ok']}, save {saved['ok']}, exists "
          f"{(ng / 'graphics').exists()}, get_graphic {after}")


def run_c(client, wg):
    """C1–C3 on WG, whose bar.js is BLUE since G4 and whose clip is at 0."""
    ok0, text0, same = sheet(client, wg, {"name": "bar", "frames": [0, 0],
                                          "background": "#000000", "max_width": 8192}, "c1-same")
    ok1, _, apart = sheet(client, wg, {"name": "bar", "frames": [0, 30],
                                       "background": "#000000", "max_width": 8192}, "c1-apart")
    size = same[:2] if same else None
    equal = same is not None and all(cell_row(same, 0, y, 1920) == cell_row(same, 1928, y, 1920)
                                     for y in range(1080))
    differ = apart is not None and any(cell_row(apart, 0, y, 1920)
                                       != cell_row(apart, 1928, y, 1920) for y in range(1080))
    check("C1 render_graphic frames [0, 0] at max_width 8192 is a 3848×1104 sheet whose two cells "
          "are byte-identical, naming 2 frame(s); frames [0, 30]: the cells differ",
          ok0 and ok1 and size == (3848, 1104) and equal and differ and "2 frame" in text0,
          f"size {size}, identical {equal}, [0, 30] differ {differ}, says {text0!r}")

    frame_png = WORK / "c2-frame.png"
    rendered = render(client, wg, 30 * FRAME, "c2-frame")
    frame = decode_rgba(frame_png) if rendered is not None else None
    ok, text, cell = sheet(client, wg, {"name": "bar", "frame": 30, "background": "#000000",
                                        "max_width": 8192}, "c2-cell")
    missed = rgb_mismatches(cell, 0, frame, 0, 1920, 1080) \
        if frame is not None and frame[:2] == (1920, 1080) else None
    check("C2 Placement: render_frame at frame 30 and render_graphic {frame: 30} over black agree "
          "in every RGB pixel of the 1920×1080 cell",
          ok and missed == 0,
          f"render_frame {frame[:2] if frame else None}, sheet {cell[:2] if cell else None}, "
          f"{missed} of 2073600 differ, says {text!r}")

    got = attempt(client, "render_graphic", {"project": str(wg), "name": "bar", "frame": 30,
                                             "format": "svg"})
    r = got.get("reply") or {}
    check("C3 render_graphic {frame: 30, format: svg}: ok, frame 30, the rect at x=\"120\", no "
          "diagnostics",
          got["ok"] and r.get("ok") is True and r.get("frame") == 30
          and 'x="120"' in (r.get("svg") or "") and r.get("diagnostics") == [],
          f"{got}")

    refusal = ("format svg takes no path, background or max_width — those are the png contact "
               "sheet's; svg answers one frame's SVG text in the reply and writes no file (got ")
    target = WORK / "c5.svg"
    base = {"project": str(wg), "name": "bar", "frame": 30, "format": "svg"}
    pathed = attempt(client, "render_graphic", dict(base, path=str(target)))
    sheeted = attempt(client, "render_graphic",
                      dict(base, background="#000000", max_width=100))
    check("C5 render_graphic svg with path is refused naming path and writes no file; with "
          "background and max_width it is refused naming both (G-19 (a))",
          not pathed["ok"] and refusal + "path)." in pathed.get("error", "")
          and not target.exists() and not (WORK / "c5.svg.png").exists()
          and not sheeted["ok"] and refusal + "background, max_width)." in sheeted.get("error", ""),
          f"path {pathed}, file {target.exists()}, sheet args {sheeted}")

    past = attempt(client, "render_graphic", {"project": str(wg), "name": "bar", "frame": 150,
                                              "format": "svg"})
    p = past.get("reply") or {}
    ctx = p.get("ctx") or {}
    check("C6 render_graphic {frame: 150, format: svg} past bar's 120 frames is DRAWN: ok, frame "
          "150, ctx.durationInFrames 120, ctx.progress 1 (G-9, G-19 (b))",
          past["ok"] and p.get("ok") is True and p.get("frame") == 150
          and ctx.get("durationInFrames") == 120 and ctx.get("progress") == 1,
          f"{past}")


def run_i(client, wg):
    """I1, I2, G9 and I3 on WG: a font and an asset imported, the reason-less
    write fixed, and the imports saved with the package."""
    folder = wg / "graphics"
    wrote = attempt(client, "write_graphic", {"project": str(wg), "name": "needsfont",
                                              "source": NEEDSFONT_JS})
    args = {"name": "needsfont", "frame": 0, "background": "#000000", "max_width": 8192}
    ok0, before, image0 = sheet(client, wg, args, "i1-before")
    lit0 = nonblack(image0, 1920, 1080)
    font = attempt(client, "import_graphic_font", {"project": str(wg), "path": str(OSWALD)})
    f = font.get("reply") or {}
    listed = (attempt(client, "get_graphic", {"project": str(wg)}).get("reply") or {})
    ok1, after, image1 = sheet(client, wg, args, "i1-after")
    lit1 = nonblack(image1, 1920, 1080)
    arial = attempt(client, "import_graphic_font", {"project": str(wg), "path": str(ARIAL)})
    again = attempt(client, "import_graphic_font", {"project": str(wg), "path": str(ARIAL)})
    fake = WORK / "fake.ttf"
    fake.write_text("this is not a font")
    faceless = attempt(client, "import_graphic_font", {"project": str(wg), "path": str(fake)})
    notes = WORK / "notes.txt"
    notes.write_text("notes")
    texty = attempt(client, "import_graphic_font", {"project": str(wg), "path": str(notes)})
    library = set(f.get("library_families") or [])
    check("I1 needsfont (font-family 'Oswald') renders nothing and names Oswald; "
          "import_graphic_font Oswald-Medium.ttf answers the ENGINE's [\"Oswald\"], lands in "
          "fonts/, and get_graphic {} lists the same families; the render then draws with no "
          "warning; Arial answers [\"Arial\"] and replaces the second time; a faceless .ttf and "
          "a .txt are refused",
          OSWALD.exists() and wrote["ok"] and ok0 and "Oswald" in before and lit0 == 0
          and font["ok"] and f.get("families") == ["Oswald"]
          and {"Oswald", "IBM Plex Mono", "Source Sans 3"} <= library
          and f.get("path") == str(folder / "fonts/Oswald-Medium.ttf")
          and f.get("replaced") is False
          and listed.get("families") == f.get("library_families")
          and ok1 and "Oswald" not in after and (lit1 or 0) > 0
          and arial["ok"] and (arial.get("reply") or {}).get("families") == ["Arial"]
          and again["ok"] and (again.get("reply") or {}).get("replaced") is True
          and not faceless["ok"] and "loaded no face" in faceless["error"]
          and not texty["ok"] and ".ttf" in texty["error"],
          f"{OSWALD} exists {OSWALD.exists()}, write {wrote['ok']}, before {before!r} lit "
          f"{lit0}, import {font}, get_graphic families {listed.get('families')}, after "
          f"{after!r} lit {lit1}, arial {arial}, again {again}, faceless {faceless}, txt {texty}")

    wrote = attempt(client, "write_graphic", {"project": str(wg), "name": "usesasset",
                                              "source": USESASSET_JS})
    args = {"name": "usesasset", "frame": 0, "background": "#000000", "max_width": 8192}
    ok0, before, image0 = sheet(client, wg, args, "i2-before")
    asset = attempt(client, "import_graphic_asset", {"project": str(wg), "path": str(RED_PNG)})
    a = asset.get("reply") or {}
    listed = (attempt(client, "get_graphic", {"project": str(wg)}).get("reply") or {})
    ok1, after, image1 = sheet(client, wg, args, "i2-after")
    empty = WORK / "empty.png"
    empty.write_bytes(b"")
    zero = attempt(client, "import_graphic_asset", {"project": str(wg), "path": str(empty)})
    texty = attempt(client, "import_graphic_asset", {"project": str(wg), "path": str(notes)})
    black, red = rgb_at(image0, 50, 50), rgb_at(image1, 50, 50)
    check("I2 usesasset names red.png and draws black; import_graphic_asset red.png lists "
          "[\"red.png\"] (and get_graphic {} does); the render then draws (255,0,0) with no "
          "warning; an empty file and a .txt are refused",
          wrote["ok"] and ok0 and "red.png" in before and black == BLACK
          and asset["ok"] and a.get("name") == "red.png" and a.get("assets") == ["red.png"]
          and listed.get("assets") == ["red.png"]
          and ok1 and red == PURE_RED and "red.png" not in after
          and not zero["ok"] and "empty" in zero["error"]
          and not texty["ok"] and "PNG" in texty["error"],
          f"write {wrote['ok']}, before {before!r} (50,50) {black}, import {asset}, get_graphic "
          f"assets {listed.get('assets')}, after {after!r} (50,50) {red}, empty {zero}, "
          f"txt {texty}")

    locked = bounded.run(["chmod", "311", str(folder)], 30)["rc"]
    ghost = attempt(client, "write_graphic", {"project": str(wg), "name": "ghost",
                                              "source": bar()})
    unlocked = bounded.run(["chmod", "755", str(folder)], 30)["rc"]
    again = attempt(client, "write_graphic", {"project": str(wg), "name": "ghost",
                                              "source": bar()})
    check("G9 a module written into an unreadable graphics/ is refused saying it was written "
          "and the scan does not list it; readable again, the same write is ok",
          locked == 0 and not ghost["ok"] and "was written" in ghost["error"]
          and "does not list" in ghost["error"] and unlocked == 0 and again["ok"]
          and (again.get("reply") or {}).get("ok") is True,
          f"chmod {locked}/{unlocked}, locked write {ghost}, again {again}")

    saved = attempt(client, "save_project", {"project": str(wg)})
    present = [(folder / name).exists() for name in
               ("fonts/Oswald-Medium.ttf", "fonts/Arial.ttf", "assets/red.png")]
    clean = (project_of_reply(client, wg) or {}).get("unsaved_changes")
    check("I3 save_project on WG: fonts/Oswald-Medium.ttf, fonts/Arial.ttf and assets/red.png "
          "are in the package and the project is clean",
          saved["ok"] and all(present) and clean is False,
          f"save {saved}, present {present}, unsaved_changes {clean}")

    fresh = WORK / "IE.reelcut"
    made = attempt(client, "new_project", {"path": str(fresh)})
    font = attempt(client, "import_graphic_font", {"project": str(fresh), "path": str(OSWALD)})
    library = (font.get("reply") or {}).get("library_families") or []
    wrote = attempt(client, "write_graphic", {"project": str(fresh), "name": "needsfont",
                                              "source": NEEDSFONT_JS})
    ok, text, image = sheet(client, fresh, {"name": "needsfont", "frame": 0,
                                            "background": "#000000", "max_width": 8192}, "i4")
    lit = nonblack(image, 1920, 1080)
    check("I4 a font imported into a graphics/ holding NO module is in library_families at "
          "once, and a module written after it draws with it, no warning",
          made["ok"] and font["ok"] and "Oswald" in library and wrote["ok"]
          and (wrote.get("reply") or {}).get("ok") is True and ok and "Oswald" not in text
          and (lit or 0) > 0,
          f"new {made['ok']}, import {font}, write {wrote.get('ok')}, says {text!r}, lit {lit}")

    run_i5(client, fresh)
    run_w1(client, WORK / "IW.reelcut")


def run_i5(client, ie):
    """I5 on IE: a name asset(name) cannot use is filed under a legal one,
    which a module then draws (spec §11 G-23)."""
    def imported(name):
        got = attempt(client, "import_graphic_asset",
                      {"project": str(ie), "path": str(RED_PNG), "name": name})
        return got, got.get("reply") or {}
    first, r1 = imported("#logo&mark.png")
    second, r2 = imported("#logo&mark.png")
    wrote = attempt(client, "write_graphic", {
        "project": str(ie), "name": "usesrenamed",
        "source": USESASSET_JS.replace('asset("red.png")', 'asset("logo-mark-2.png")')})
    ok, text, image = sheet(client, ie, {"name": "usesrenamed", "frame": 0,
                                         "background": "#000000", "max_width": 8192}, "i5")
    drawn = rgb_at(image, 50, 50)
    plain, r3 = imported("My Photo (1).png")
    check("I5 import_graphic_asset name \"#logo&mark.png\" answers name logo-mark.png, "
          "renamed_from \"#logo&mark.png\", replaced false; again logo-mark-2.png; a module "
          "drawing asset(\"logo-mark-2.png\") renders (255,0,0) naming no warning; \"My Photo "
          "(1).png\" answers no renamed_from",
          first["ok"] and r1.get("name") == "logo-mark.png"
          and r1.get("renamed_from") == "#logo&mark.png" and r1.get("replaced") is False
          and second["ok"] and r2.get("name") == "logo-mark-2.png"
          and r2.get("renamed_from") == "#logo&mark.png" and r2.get("replaced") is False
          and wrote["ok"] and (wrote.get("reply") or {}).get("ok") is True
          and ok and drawn == PURE_RED and "logo-mark-2.png" not in text
          and plain["ok"] and r3.get("name") == "My Photo (1).png"
          and "renamed_from" not in r3,
          f"first {first}, second {second}, write {wrote.get('ok')}, says {text!r} (50,50) "
          f"{drawn}, plain {plain}")


def run_w1(client, iw):
    """W1 — the watcher's path for a font landed by ANOTHER process in a
    module-less graphics/: the store's own post reaches the registry (G5b)."""
    made = attempt(client, "new_project", {"path": str(iw)})
    before = (attempt(client, "get_graphic", {"project": str(iw)}).get("reply") or {})
    control = "Oswald" not in (before.get("families") or [])
    fonts = iw / "graphics" / "fonts"
    made_dir = bounded.run(["mkdir", "-p", str(fonts)], 30)["rc"]
    copied = bounded.run(["cp", str(OSWALD), str(fonts / OSWALD.name)], 30)["rc"]
    families, deadline = [], time.monotonic() + 5
    while time.monotonic() < deadline:
        families = ((attempt(client, "get_graphic", {"project": str(iw)}).get("reply") or {})
                    .get("families") or [])
        if "Oswald" in families:
            break
        time.sleep(0.25)
    wrote = attempt(client, "write_graphic", {"project": str(iw), "name": "needsfont",
                                              "source": NEEDSFONT_JS})
    ok, text, image = sheet(client, iw, {"name": "needsfont", "frame": 0,
                                         "background": "#000000", "max_width": 8192}, "w1")
    lit = nonblack(image, 1920, 1080)
    check("W1 a font cp'd from the shell into a module-less graphics/fonts/ reaches "
          "get_graphic's families within 5 s (CONTROL: absent before), and a module written "
          "after it draws with it, no warning",
          OSWALD.exists() and made["ok"] and control and made_dir == 0 and copied == 0
          and "Oswald" in families and wrote["ok"]
          and (wrote.get("reply") or {}).get("ok") is True and ok and "Oswald" not in text
          and (lit or 0) > 0,
          f"new {made['ok']}, before {before.get('families')}, mkdir {made_dir}, cp {copied}, "
          f"families {families}, write {wrote.get('ok')}, says {text!r}, lit {lit}")


def run_loop(client, lp):
    """L2 — the agent's loop of §5h on a new project, as an agent would run it."""
    made = attempt(client, "new_project", {"path": str(lp)})
    reference = attempt(client, "graphic_reference", {})
    broken = attempt(client, "write_graphic", {"project": str(lp), "name": "bar",
                                               "source": BROKEN_BAR})
    b = broken.get("reply") or {}
    first = (b.get("diagnostics") or [{}])[0]
    good = attempt(client, "write_graphic", {"project": str(lp), "name": "bar",
                                             "source": bar()})
    looked = attempt(client, "render_graphic", {"project": str(lp), "name": "bar",
                                                "frames": [0, 15, 30]})
    text = str(looked.get("reply") or looked.get("error"))
    written = re.search(r"Written to (\S+\.png)\.$", text)
    size = None
    if written and Path(written.group(1)).exists():
        size = struct.unpack(">II", Path(written.group(1)).read_bytes()[16:24])
    track = ((project_of(client, lp) or {}).get("tracks") or [{}])[0].get("id")
    added = attempt(client, "add_graphic_clip", {"project": str(lp), "name": "bar",
                                                 "track": track, "at": 0})
    clips = [c for c in (project_of(client, lp) or {}).get("clips", [])
             if (c.get("graphic") or {}).get("name") == "bar"]
    before = render(client, lp, 30 * FRAME, "l2-before")
    titled = attempt(client, "set_graphic", {"project": str(lp),
                                             "clips": [c["id"] for c in clips],
                                             # Not "Loop": bar() draws only the title's
                                             # LENGTH, and "Loop" is as long as "Jane".
                                             "patch": {"props": {"title": "Looped"}}})
    after = render(client, lp, 30 * FRAME, "l2-after")
    check("L2 the loop: reference, a broken write (ok false, line 2), a good one, render_graphic "
          "of frames 0, 15, 30 at the default max_width is exactly 2048×1202, add_graphic_clip, "
          "render_frame's (122,50) is RED, set_graphic props changes the frame",
          made["ok"] and reference["ok"] and broken["ok"] and b.get("ok") is False
          and first.get("line") == 2 and good["ok"] and (good.get("reply") or {}).get("ok")
          and looked["ok"] and "3 frame" in text and "frames 0, 15, 30" in text
          and size == (2048, 1202) and added["ok"] and len(clips) == 1
          and pixel(before, 122, 50) == RED and titled["ok"] and after is not None
          and after != before,
          f"new {made['ok']}, reference {reference['ok']}, broken {b.get('ok')} line "
          f"{first.get('line')}, good {good.get('ok')}, render says {text!r}, size {size}, "
          f"add {added['ok']} clips {len(clips)}, (122,50) {pixel(before, 122, 50)}, "
          f"set {titled['ok']}, differs {after is not None and after != before}")


def run_g8(client, nf):
    """G8 — an untitled root holding only fonts/ is carried by the first save."""
    made = attempt(client, "new_project", {})
    before = attempt(client, "get_graphic", {})
    b = before.get("reply") or {}
    root = b.get("folder")
    copied = False
    if root:
        fonts = Path(root) / "fonts"
        fonts.mkdir(parents=True, exist_ok=True)
        shutil.copy2(ROOT / "app/Resources/Fonts/Anton-Regular.ttf",
                     fonts / "Anton-Regular.ttf")
        copied = True
    saved = attempt(client, "save_project", {"path": str(nf)})
    font = (nf / "graphics/fonts/Anton-Regular.ttf").exists()
    modules = sorted(p.name for p in (nf / "graphics").glob("*.js"))
    after = attempt(client, "get_graphic", {})
    a = after.get("reply") or {}
    gone = bool(root) and not Path(root).exists()
    check("G8 an untitled root holding only fonts/Anton-Regular.ttf, saved to NF: the font "
          "arrives, no module does, get_graphic now names NF/graphics, and the untitled root "
          "is gone (G-19 (d))",
          made["ok"] and before["ok"] and b.get("folder_exists") is True
          and b.get("modules") == [] and copied and saved["ok"] and font and modules == []
          and after["ok"] and a.get("folder") == str(nf / "graphics")
          and a.get("folder_exists") is True and gone,
          f"new {made['ok']}, before {before}, save {saved}, font {font}, modules {modules}, "
          f"after {after}, root gone {gone}")


def project_of_reply(client, project):
    """`get_project`'s whole reply, or None."""
    got = attempt(client, "get_project", with_project(project, {}))
    return got["reply"] if got["ok"] else None


def near(found, want, slack=6):
    return found is not None and all(abs(a - b) <= slack for a, b in zip(found, want))


def decode_movie(movie, seconds):
    """One RGBA frame of `movie` at `seconds` through ffmpeg, or b"" — binary
    output, so not `bounded.run` (a text-mode child); bounded all the same."""
    try:
        return subprocess.run(["ffmpeg", "-v", "error", "-ss", str(seconds), "-i", str(movie),
                               "-vframes", "1", "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
                              capture_output=True, timeout=120,
                              env=bounded.child_env()).stdout
    except (OSError, subprocess.TimeoutExpired):
        return b""


def movie_pixel(raw, x, y, width=1920, height=1080):
    if len(raw) != width * height * 4:
        return None
    i = (y * width + x) * 4
    return tuple(raw[i:i + 3])


def run_e(client, p1):
    """E1–E3 on P1, reopened in this instance: three modules mv'd in, a
    FRONT track added, and each row's clip undone before the next."""
    opened = attempt(client, "open_project", {"path": str(p1)})
    rcs = [mv_in(p1 / "graphics", name, text) for name, text in
           (("throw10.js", THROW10_JS), ("spin.js", SPIN_JS), ("nofont.js", NOFONT_JS))]
    added = attempt(client, "add_track", {"project": str(p1)})
    track = ((project_of(client, p1) or {}).get("tracks") or [{}])[-1].get("id")
    setup = f"open {opened['ok']}, mv rcs {rcs}, track {added['ok']} {track}"

    clip, why = land(client, p1, "throw10", track, 0)
    text9, f9, _ = render_text(client, p1, 9 * FRAME, "e1-f9")
    text10, f10, _ = render_text(client, p1, 10 * FRAME, "e1-f10")
    movie = WORK / "e1-export.mp4"
    exported = attempt(client, "export", {"project": str(p1), "preset": "h264",
                                          "path": str(movie)})
    # The path itself. AVFoundation's own `<name>.sb-…` temporary can outlive
    # a cancelled write for a moment and is not the file (measured, G3c).
    left = [str(movie)] if movie.exists() else []
    undone = attempt(client, "undo", {"project": str(p1)})
    error = exported.get("error", "")
    red9, border, fill = pixel(f9, 50, 50), pixel(f10, 1, 540), pixel(f10, 1900, 1060)
    check("E1 throw10: frame 9 does not name throw10 and draws RED; frame 10 names \"throw10\", "
          "frame 10 and boom at ten over the error card; the export is stopped naming both, "
          "and leaves no file",
          opened["ok"] and rcs == [0, 0, 0] and added["ok"] and clip is not None
          and 'Graphic "throw10"' not in text9 and red9 == RED
          and '"throw10"' in text10 and "frame 10" in text10 and "boom at ten" in text10
          and border == BORDER and fill == CARD
          and not exported["ok"] and '"throw10"' in error and "frame 10" in error
          and left == [] and undone["ok"],
          f"{setup}, clip {clip is not None} {why!r}, (50,50)@9 {red9}, frame 9 says "
          f"{text9!r}, frame 10 says {text10!r}, (1,540) {border}, (1900,1060) {fill}, "
          f"export {exported}, left {left}")

    ok, text, image = sheet(client, p1, {"name": "throw10", "frames": [9, 10],
                                         "max_width": 8192}, "c4")
    border, fill, red = rgb_at(image, 1929, 540), rgb_at(image, 1928 + 1900, 1060), \
        rgb_at(image, 50, 50)
    check("C4 render_graphic throw10 frames [9, 10]: the text names \"throw10\", frame 10 and "
          "boom at ten; cell 1 is the error card (border at (1929,540), fill at (3828,1060)); "
          "cell 0's (50,50) is RED",
          ok and '"throw10"' in text and "frame 10" in text and "boom at ten" in text
          and border == BORDER and fill == CARD and red == RED,
          f"says {text!r}, (1929,540) {border}, (3828,1060) {fill}, (50,50) {red}")

    clip, why = land(client, p1, "spin", track, 0)
    text0, _, seconds = render_text(client, p1, 0, "e2-f0")
    started = time.monotonic()
    got = attempt(client, "get_project", {"project": str(p1)})
    answered = time.monotonic() - started
    undone = attempt(client, "undo", {"project": str(p1)})
    print(f"  E2 render_frame took {seconds:.2f} s, get_project {answered:.2f} s", flush=True)
    check("E2 spin: render_frame at frame 0 returns within 3 s naming the budget; get_project "
          "then answers within 5 s",
          clip is not None and seconds < 3 and "budget" in text0 and got["ok"]
          and answered < 5 and undone["ok"],
          f"clip {clip is not None} {why!r}, {seconds:.2f} s, says {text0!r}, "
          f"get_project {got['ok']} in {answered:.2f} s")

    clip, why = land(client, p1, "nofont", track, 0)
    text0, _, _ = render_text(client, p1, 0, "e3-f0")
    undone = attempt(client, "undo", {"project": str(p1)})
    check("E3 nofont: render_frame names Nope Sans and IBM Plex Mono",
          clip is not None and "Nope Sans" in text0 and "IBM Plex Mono" in text0
          and undone["ok"],
          f"clip {clip is not None} {why!r}, says {text0!r}")


def pin_project(client, package, names):
    """A fresh project at `package` with `names` mv'd into its graphics/ and a
    3 s `pin` clip. (made, mv rcs, clip, last refusal)."""
    made = attempt(client, "new_project", {"path": str(package)})
    sources = {"pin.js": PIN_JS, "nofont.js": NOFONT_JS}
    rcs = [mv_in(package / "graphics", name, sources[name], make_folder=True) for name in names]
    track = ((project_of(client, package) or {}).get("tracks") or [{}])[0].get("id")
    clip, why = land(client, package, "pin", track, 0, {"duration": 3 * SECOND})
    return made["ok"], rcs, clip, why


def run_e4(client, package):
    made, rcs, clip, why = pin_project(client, package, ["pin.js"])
    movie = WORK / "e4.mov"
    exported = attempt(client, "export", {"project": str(package), "preset": "prores_4444",
                                          "path": str(movie)})
    raw = decode_movie(movie, 2)
    found = movie_pixel(raw, 480, 540)
    check("E4 a pin clip exported as prores_4444 over MCP: at 2 s (480,540) is RED — export "
          "passes the document's set",
          made and rcs == [0] and clip is not None and exported["ok"] and near(found, RED),
          f"clip {clip is not None} {why!r}, export {exported.get('error', 'ok')}, "
          f"decoded {len(raw)} bytes, (480,540) {found}")


def make_pq(client, package):
    """PQ, the probe's project: pin.js and nofont.js, a 3 s pin clip, saved."""
    made, rcs, clip, why = pin_project(client, package, ["pin.js", "nofont.js"])
    saved = attempt(client, "save_project", {"project": str(package)})
    print(f"  PQ: new {made}, mv rcs {rcs}, clip {clip is not None} {why!r}, "
          f"saved {saved['ok']}", flush=True)


def build_pin_probe():
    """`graphics_pin_probe.swift` as `main.swift` over every other file in
    `app/Sources`, on `harness/build.sh`'s swiftc line, with the app's
    `Fonts`, `Blank.mp4` and a `default.metallib` of `Compositor.metal`
    beside it — `phase7_chrome.py`'s `build_probe` and `build_shader`. Rebuilt
    only when stale. The binary, or None and why."""
    PIN_PROBE_DIR.mkdir(parents=True, exist_ok=True)
    binary = PIN_PROBE_DIR / "graphics_pin_probe"
    entry = PIN_PROBE_DIR / "main.swift"
    if not entry.exists() or entry.read_text() != PIN_PROBE_SOURCE.read_text():
        entry.write_text(PIN_PROBE_SOURCE.read_text())
    fonts = PIN_PROBE_DIR / "Fonts"
    resources = ROOT / "app/Resources"
    if not fonts.is_dir() or (resources / "Fonts").stat().st_mtime > fonts.stat().st_mtime:
        shutil.rmtree(fonts, ignore_errors=True)
        shutil.copytree(resources / "Fonts", fonts)
    if not (PIN_PROBE_DIR / "Blank.mp4").exists():
        shutil.copy2(resources / "Blank.mp4", PIN_PROBE_DIR / "Blank.mp4")
    shader = resources / "Shaders/Compositor.metal"
    metallib, air = PIN_PROBE_DIR / "default.metallib", PIN_PROBE_DIR / "Compositor.air"
    if not metallib.exists() or shader.stat().st_mtime > metallib.stat().st_mtime:
        step = bounded.run(["xcrun", "-sdk", "macosx", "metal", "-c", str(shader), "-o",
                            str(air)], 300)
        if step["rc"] == 0:
            step = bounded.run(["xcrun", "-sdk", "macosx", "metallib", str(air), "-o",
                                str(metallib)], 300)
        if step["rc"] != 0 or not metallib.exists():
            return None, f"the shader did not build: {step['stderr'][-400:]}"
    sources = sorted(path for path in (ROOT / "app/Sources").glob("*.swift")
                     if path.name != "main.swift")
    lib = ROOT / "core/target/release/libreelcut_core.a"
    if not lib.exists():
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if binary.exists() and all(path.stat().st_mtime < binary.stat().st_mtime
                               for path in sources + [entry, lib]):
        return binary, ""
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    built = bounded.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
         "-L", str(lib.parent), "-lreelcut_core"]
        + [str(path) for path in sources] + [str(entry), "-o", str(binary)], 900)
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = built["stderr"].strip().splitlines()[-4:]
        return None, f"swiftc rc {built['rc']}: {(errors or tail or ['(no output)'])[:6]}"
    return binary, ""


def run_probe(binary, mode, pin, tag):
    """One probe run over PQ: its JSON answer (or an error), and the decoded
    frame at 1 s for the two export modes."""
    if binary is None:
        return {"error": "the probe did not build"}, b""
    movie = WORK / f"{tag}.mov"
    got = bounded.run([str(binary), str(WORK / "PQ.reelcut"), mode, pin, str(movie)], 600)
    try:
        answer = json.loads(got["stdout"].strip().splitlines()[-1])
    except (IndexError, ValueError):
        answer = {"error": f"rc {got['rc']}, expired {got['expired']}: "
                           f"{(got['stdout'] + got['stderr'])[-400:]}"}
    raw = decode_movie(movie, 1) if mode != "hit" and movie.exists() else b""
    return answer, raw


def run_q(binary, why):
    """Q1–Q3 through the probe; a probe that did not build fails all three."""
    for row, mode in (("Q1", "queue"), ("Q2", "direct")):
        pinned, raw = run_probe(binary, mode, "pin", f"{row.lower()}-pin")
        control, raw_control = run_probe(binary, mode, "nopin", f"{row.lower()}-nopin")
        left, right = movie_pixel(raw, 480, 540), movie_pixel(raw, 1440, 540)
        bare = movie_pixel(raw_control, 480, 540)
        check(f"{row} {mode}: the set pinned at the call draws RED at (480,540) after the "
              "document's set is removed, (1440,540) BLACK; CONTROL with no pin is not RED",
              pinned.get("setCaptured") and pinned.get("setAfterStop") is False
              and near(left, RED) and near(right, BLACK)
              and control.get("setAfterStop") is False and bare is not None
              and not near(bare, RED),
              f"{why}pin {pinned}, (480,540) {left}, (1440,540) {right}; nopin {control}, "
              f"(480,540) {bare}")
    hit, _ = run_probe(binary, "hit", "pin", "q3-hit")
    first, second = hit.get("first") or [], hit.get("second") or []
    check("Q3 one LayerRenderers asked twice for nofont: both answers warn of Nope Sans, the "
          "second from the pool (the same texture)",
          any("Nope Sans" in m for m in first) and any("Nope Sans" in m for m in second)
          and hit.get("sameTexture") is True,
          f"{why}{hit}")


def setup_bar(client, wg):
    """C7's and G10's own setup in a mutant run: WG with bar.js. Whether it held."""
    made = attempt(client, "new_project", {"path": str(wg)})
    wrote = attempt(client, "write_graphic", {"project": str(wg), "name": "bar",
                                              "source": bar()})
    return made["ok"] and wrote["ok"] and (wrote.get("reply") or {}).get("ok") is True


def run_g10(client, wg):
    """G10 — `graphic_reference` checks a `project` it is given (G-20 (e)).
    Whether its control half (the open WG answers the doc) held."""
    doc = DOC_MD.read_bytes().decode("utf-8")
    named = attempt(client, "graphic_reference", {"project": str(wg)})
    nowhere = WORK / "nowhere.reelcut"
    stray = attempt(client, "graphic_reference", {"project": str(nowhere)})
    control = named["ok"] and named.get("reply") == doc
    check("G10 graphic_reference {project: WG} answers docs/graphics-api.md; {project: "
          "nowhere.reelcut} is refused \"No open project is at\" (G-20 (e))",
          control and not stray["ok"] and "No open project is at" in stray.get("error", ""),
          f"WG ok {named['ok']} equals doc {named.get('reply') == doc} "
          f"{named.get('error', '')!r}, nowhere {stray}")
    return control


def run_c7(client, wg):
    """C7 — the png sheet's pixel cap (G-20 (d)). Whether its control half
    (exactly the cap draws) held."""
    target = WORK / "c7.png"
    if target.exists():
        target.unlink()
    over = attempt(client, "render_graphic", {"project": str(wg), "name": "bar",
                                              "frames": [0, 1, 2], "width": 8192,
                                              "height": 8192, "path": str(target)})
    ok, text, _ = sheet(client, wg, {"name": "bar", "frames": [0, 1], "width": 8192,
                                     "height": 8192}, "c7-control")
    error = over.get("error", "")
    check("C7 render_graphic of 3 frames at 8192×8192 is refused naming 134217728 and "
          "201326592 and writes no c7.png; CONTROL: 2 frames, exactly the cap, draw (G-20 (d))",
          not over["ok"] and str(CAP) in error and str(3 * 8192 * 8192) in error
          and not target.exists() and ok and "2 frame" in text,
          f"over {over}, c7.png {target.exists()}, control ok {ok} {text[:200]!r}")
    return ok and "2 frame" in text


def rewrite_in_place(path, text):
    """`cat staged > path` from the shell: truncated and rewritten through
    the same inode. Whether the inode held."""
    staged = WORK / f"staged-{path.name}"
    staged.write_text(text)
    before = path.stat().st_ino if path.exists() else None
    bounded.run(["/bin/sh", "-c", 'cat "$1" > "$2"', "sh", str(staged), str(path)], 30)
    return before is not None and path.stat().st_ino == before


def revision_of(client, ws, name):
    got = attempt(client, "get_graphic", {"project": str(ws), "name": name})
    return (got.get("reply") or {}).get("revision") if got["ok"] else None


def await_revisions(client, ws, want, seconds):
    """Polls `get_graphic` every 0.2 s until each module in `want` (name →
    SHA-256 hex) answers that revision, or `seconds` pass. The revisions last
    seen, by name."""
    deadline = time.monotonic() + seconds
    seen = {}
    while True:
        seen = {name: revision_of(client, ws, name) for name in want}
        if seen == want or time.monotonic() >= deadline:
            return seen
        time.sleep(0.2)


def run_g11(client, ws):
    """G11 — module sources share the 16-file cap (G-20 (a)). Whether its
    setup and its control half held."""
    names = [f"m{i:02d}" for i in range(17)]
    made = attempt(client, "new_project", {"path": str(ws)})
    wrote = [attempt(client, "write_graphic", {
        "project": str(ws), "name": name,
        "source": module(f'  return svg(ctx, `<rect width="10" height="10" fill="#ff5a36"/>`); '
                         f'// {name}')}) for name in names]
    setup = made["ok"] and all(w["ok"] and (w.get("reply") or {}).get("ok") is True
                               for w in wrote)
    folder = ws / "graphics"
    # The SETTLE: `write_graphic` rescans synchronously, so m16's revision is
    # final at once and a stability poll could not see a coalesced pass still
    # pending from the setup's writes (#183). m00's settle revision, once seen,
    # proves a pass ran after every one of them.
    settle00 = module('  return svg(ctx, `<rect width="10" height="10" fill="#ff5a36"/>`); '
                      '// m00 settle')
    same_settle = rewrite_in_place(folder / "m00.js", settle00)
    want_settle = hashlib.sha256(settle00.encode()).hexdigest()
    seen_settle = await_revisions(client, ws, {"m00": want_settle}, 5)["m00"]
    settled = same_settle and seen_settle == want_settle
    setup = setup and settled
    # The settle's own write can leave one pass scheduled after its revision
    # is seen: a pass already pending can re-arm m00's source between `cat`'s
    # truncate and its write (`GraphicStore.armAndScan`). 0.3 s is one
    # `GraphicStore.coalesceInterval` (0.1 s, GraphicStore.swift :44) and margin.
    time.sleep(0.3)
    old16 = revision_of(client, ws, "m16")
    new16 = module('  return svg(ctx, `<rect width="20" height="20" fill="#2d7ff9"/>`); // m16 v2')
    same16 = rewrite_in_place(folder / "m16.js", new16)
    time.sleep(2)
    after16 = revision_of(client, ws, "m16")
    new00 = module('  return svg(ctx, `<rect width="20" height="20" fill="#2d7ff9"/>`); // m00 v2')
    same00 = rewrite_in_place(folder / "m00.js", new00)
    want00 = hashlib.sha256(new00.encode()).hexdigest()
    want16 = hashlib.sha256(new16.encode()).hexdigest()
    seen = await_revisions(client, ws, {"m00": want00, "m16": want16}, 5)
    seen00, seen16 = seen["m00"], seen["m16"]
    control = same00 and seen00 == want00 and seen16 == want16
    check("G11 17 modules, settled by m00.js rewritten in place until its revision is seen, "
          "then one coalesce interval: m16.js rewritten in place is NOT seen after 2 s (past "
          "the 16-source cap); CONTROL: m00.js rewritten in place, and within 5 s both "
          "revisions are hashlib's (G-20 (a))",
          setup and old16 is not None and same16 and after16 == old16 and control,
          f"setup {setup} (settle m00 {seen_settle} want {want_settle}, same inode "
          f"{same_settle}), m16 {old16} → {after16} (same inode {same16}), then m00 {seen00} "
          f"want {want00}, m16 {seen16} want {want16} (same inode {same00})")
    return setup and control


def build_mutant(file, anchor, replacement):
    """A COPY of the tree from `tree_copy.make_copy` (`app/` and `agent/`
    copied, every other build input `project.yml` names linked), `anchor`
    in `app/Sources/<file>` replaced, built by the copy's own `make app`.
    The binary, or None and why."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    target = copy / "app/Sources" / file
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, f"the anchor occurs {text.count(anchor)} times in {file}"
    target.write_text(text.replace(anchor, replacement))
    built = bounded.run(["make", "app"], 1500, cwd=str(copy))
    binary = copy / "build/Build/Products/Release/Reelcut.app/Contents/MacOS/Reelcut"
    if built["rc"] != 0 or not binary.exists():
        errors = [line for line in (built["stdout"] + built["stderr"]).splitlines()
                  if "error:" in line]
        return None, (f"make app rc {built['rc']} (expired {built['expired']}): "
                      + ("\n      ".join(errors[:6]) or built["stdout"][-600:]))
    return binary, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4879)
    parser.add_argument("--app", type=Path, default=APP)
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    if args.mutant:
        file, anchor, replacement, row = MUTANTS[args.mutant]
        print(f"graphics — the {args.mutant} MUTANT ({row} must FAIL)", flush=True)
        binary, why = build_mutant(file, anchor, replacement)
        if binary is None:
            print(f"  FAIL the mutant builds — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — the copy was "
                  f"not built: {why}")
            return 2
        instance = Instance(binary, args.port, WORK / f"reelcut-{args.port}.log")
        try:
            client = instance.start()
            if client is None:
                print("  FAIL the mutant launches")
                print(f"mutant {args.mutant}: the control could not be performed — the copy "
                      f"did not launch")
                return 2
            if args.mutant == "frame-plus-one":
                _, _, f30, f31 = run_p1_p2(client, WORK / "M.reelcut")
                why = ("P1 did not hold" if not rows.get("P1") else
                       "frame 30 was not rendered" if f30 is None else
                       "frame 31 was not rendered" if f31 is None else "")
            elif args.mutant == "store-uncapped":
                why = "" if run_g11(client, WORK / "WS.reelcut") else \
                    "the 17 writes, the m00 settle or the m00 control did not hold"
            else:
                wg = WORK / "WG.reelcut"
                if not setup_bar(client, wg):
                    why = "new_project and write_graphic bar did not hold"
                elif args.mutant == "sheet-uncapped":
                    why = "" if run_c7(client, wg) else "the 2-frame control did not draw"
                else:
                    why = "" if run_g10(client, wg) else "the reference for WG did not answer"
        finally:
            instance.stop()
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        verdict = not rows.get(row)
        print(f"the mutant is CAUGHT: {row} failed" if verdict
              else "the mutant was NOT caught")
        return 0 if verdict else 1
    print("G3b/G3c/G4a/G4b/G5b graphics — a graphic clip drawn, one failing, the agent's "
          "write/read loop, its contact sheet and imports, against the built app (proof)",
          flush=True)
    if not args.app.exists():
        print(f"  FAIL the app is not built: {args.app}")
        print(f"0/{len(ROWS)}")
        return 1
    log = run(args.app, args.port)
    binary, why = build_pin_probe()
    run_q(binary, f"the probe did not build — {why}; " if binary is None else "")
    found = complaints(log)
    check("Z1 grep \"Reelcut: \" over every launch's log prints nothing", found == [],
          f"{found[:5]}")
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
