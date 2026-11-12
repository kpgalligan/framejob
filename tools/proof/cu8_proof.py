#!/usr/bin/env python3
"""Road map "creator-jobs" CU8 — Clip ▸ Add Shortcut Overlays and `add_shortcut_overlays`
(spec §11 CU-80…CU-85).

    python3 tools/proof/cu8_proof.py [SOCKET] [--only O1,O4,…] [--mutant NAME] [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the
rows launch their own instance on a scratch `CFFIXED_USER_HOME`. Packages and media are made
under `tools/proof/work/cu8/`. The movie is ffmpeg's `testsrc` (640 × 360, 30 fps, 20 s), with
a v1 cursor file beside it written here per `core/src/cursor_file.rs`, its `keys.shortcut`
filled (`import_media` attaches it, CU-34). Every canvas is 640 × 360 at 30 fps unless said; a
frame is 20 000 ticks at 30 fps and 10 000 at 60. D_min(n) = 10n + 25 frames (CU-80).

Rows:
- O0 `grep "Frame Job: "` of every instance's log prints nothing.
- O1 `cmd+s`, `cmd+shift+4`, `ctrl+left`, `cmd+plus` at source 1, 4, 7, 10 s of a clip at
  container 2 s: four clips at 3, 6, 9, 12 s of 45, 55, 45, 45 frames, `keys` verbatim, label
  "", bottom, dark, on one new front "Shortcuts" track, drawn by `keyboard-keys`.
- O1b at 60 fps, `cmd+s` at 1.0 s and `cmd+c` at 2.0 s: [1.0, 2.0) s, then from 2.0 s.
- O2 `cmd+s` then `cmd+c` 0.3 s later: at 30 fps one 45-frame clip and `dropped` 1; at 60 fps
  two clips, the first 0.75 s.
- O2b at 60 fps `cmd+shift+4` then `cmd+c` 0.3 s later: one 90-frame clip, `dropped` 1.
- O3 `cmd+z` three times 0.3 s apart: one clip from the first press to 2.1 s past it, label
  "×3", `merged` 2.
- O4 a second run on another clip reuses `keyboard-keys` (one module file, its bytes the
  bundle's) and the free Shortcuts track; a third over an occupied span adds a new track.
- O4b a clip on a track added in FRONT of a free Shortcuts track: a new Shortcuts track in
  front of it, the old one unchanged; a hand-edited `keyboard-keys.js` makes the run write
  `keyboard-keys-2`.
- O5 `render_frame` 30 frames into an overlay differs from the same frame with the Shortcuts
  track hidden, and only in the frame's bottom half; each is read to the nearest 8-bit level
  (`png_read.rgba8`), since the overlay's frame is a 16-bit PNG (spec §11 PR-20).
- O6 every overlay of every fixture here lasts at least D_min(n) frames, on the grid.
- O7 Clip ▸ Add Shortcut Overlays by `perform_menu_item` gives the project
  `add_shortcut_overlays` gives with the defaults on a copy, one undo step that restores the
  project.
- O8 refusals by sentence (reversed, no cursor file, not a media clip, duration 0.2, position
  "left", `to` ≤ `from`) and a file with no shortcuts: the note, no undo step, no module file.
- O9 is `core/tests/shortcut_overlays.rs`'s `o9_…` (through S, `from`/`to`).

`--mutant NAME`: the named decision broken. A core mutant edits a copy of `core/` (beside a
link to `graphic/`) and runs `cargo test --release --test shortcut_overlays`: CAUGHT when a
test of its rows fails. `plus-not-mapped` edits a copy of `graphic/` and runs the templates
test. `module-rewritten` edits a `tree_copy.py` copy and runs O4 on its built app. CAUGHT exits
1, SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import png_read  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/cu8"
HOME = WORK / "home"
KEEP = {"media", "mutant-target", "mutant-graphic-target"}
SEC = 600_000
CALL_BOUND = 600
BUILD_BOUND = 1500
W, H = 640, 360
TEMPLATE = ROOT / "graphic/tests/graphics/keyboard-keys.js"
NOTHING = ("No shortcut was recorded in the selected clips' played windows, so nothing was "
           "added.")
PLAIN = ["O1", "O1b", "O2", "O2b", "O3", "O4", "O4b", "O5", "O6", "O7", "O8"]
ROWS = ["O0"] + PLAIN

OVERLAYS = "core/src/cursor_overlays.rs"
PLANNER_APP = "app/Sources/ShortcutOverlays.swift"
TEMPLATE_PATH = "graphic/tests/graphics/keyboard-keys.js"
# name → (rows, [(path, anchor, replacement)], "core", "graphic" or "app")
MUTANTS = {
    "overlap-allowed": (["O1b"], [(OVERLAYS, "                cur.end = start;\n", "")], "core"),
    "times-without-s": (["O9"], [(
        OVERLAYS, ".saturating_add(clip_time(clip, s - source_in))",
        ".saturating_add((s - source_in) + 0 * clip_time(clip, 0))")], "core"),
    "dmin-ignored": (["O2", "O2b", "O6"], [(
        OVERLAYS, "    10 * keycaps as i64 + 25\n", "    let _ = keycaps;\n    0\n")], "core"),
    "repeats-not-merged": (["O3"], [(
        OVERLAYS, "if p.keys == cur.keys {", "if false && p.keys == cur.keys {")], "core"),
    "track-behind-reused": (["O4b"], [(
        OVERLAYS, "if index > front_of_clips && ", "if ")], "core"),
    "plus-not-mapped": (["plus"], [(
        TEMPLATE_PATH, 'const key = t.toLowerCase() === "plus" ? "+" : t;',
        "const key = t;")], "graphic"),
    "module-rewritten": (["O4"], [(
        PLANNER_APP, "return same.contains(templateName) ? templateName : same.min()",
        "return same.isEmpty ? nil : nil")], "app"),
}

results = {}
selected = set(ROWS)
# (fps, keys, duration ticks, at ticks) of every overlay any row placed, for O6.
placed_overlays = []


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


# ---- media and cursor files ----------------------------------------------------

def movies():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    out = folder / "screen.mov"
    if not out.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"testsrc=size={W}x{H}:rate=30:duration=20", "-c:v", "libx264",
                        "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0", str(out)],
                       check=True, timeout=300, env=bounded.child_env())
    return {"screen": out}


def t(seconds):
    """Seconds to ticks."""
    return int(round(seconds * SEC))


def cursor_body(shortcuts):
    """A v1 cursor file with `(seconds, keys)` shortcuts and one move at the centre."""
    n = len(shortcuts)
    return {
        "format": "framejob-cursor", "version": 1, "in_picture": False, "source": "display",
        "display_id": 1, "source_frame": [0, 0, W * 50, H * 50], "point_size": [W * 50, H * 50],
        "pixels_per_point": 2.0, "content_size": [W, H], "movie_size": [W, H],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "none",
        "moves": {"t": [0], "x": [W * 25], "y": [H * 25]},
        "images": [], "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [], "button": [], "down": [], "x": [], "y": [], "count": []},
        "scrolls": {"t": [], "x": [], "y": [], "dx": [], "dy": []},
        "geometry": [{"t": 0, "screen_rect": [0, 0, W * 50, H * 50],
                      "content_rect": [0, 0, W * 50, H * 50], "content_scale": 1.0,
                      "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [int(round(s * 1e6)) for s, _ in shortcuts],
                              "keys": [k for _, k in shortcuts], "code": [1] * n},
                 "typed": {"t": []}},
    }


def recording(files, name, shortcuts, cursor=True):
    """`<WORK>/rec/<name>/A.mov` with its `A.fjcursor` beside (unless `cursor` is false)."""
    folder = WORK / "rec" / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "A.mov"
    shutil.copyfile(files["screen"], path)
    if cursor:
        (folder / "A.fjcursor").write_text(json.dumps(cursor_body(shortcuts)))
    return path


# ---- a document ----------------------------------------------------------------

class Doc:
    """One saved package on a 640 × 360 canvas at `fps`."""

    def __init__(self, client, name, fps=30):
        self.client = client
        self.fps = fps
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=W, height=H, fps=[fps, 1])

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def track(self):
        tracks = self.state()["tracks"]
        if not tracks:
            self.call("add_track")
            tracks = self.state()["tracks"]
        return tracks[0]["id"]

    def place(self, movie, at=0, track=None, cursor=True):
        media = self.call("import_media", path=str(movie))["media"]
        track = track if track is not None else self.track()
        clip = self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]
        row = next(m for m in self.state()["media"] if m["id"] == media)
        assert bool(row.get("cursor")) == cursor, f"import of {movie}: cursor {row.get('cursor')}"
        return clip

    def overlays(self, **arguments):
        answer = self.call("add_shortcut_overlays", **arguments)
        for o in answer.get("overlays", []):
            placed_overlays.append((self.fps, o["keys"], o["duration"], o["at"]))
        return answer

    def on_track(self, track, state=None):
        state = state or self.state()
        return sorted((c for c in state["clips"] if c["track"] == track),
                      key=lambda c: c["start"])

    def modules(self):
        folder = self.path / "graphics"
        return sorted(p.name for p in folder.glob("*.js")) if folder.exists() else []

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def refusal(body):
    """The tool's sentence, without `mcp.py`'s "<tool>: " prefix; None when it applied."""
    try:
        body()
    except mcp.ToolError as error:
        text = str(error)
        prefix = "add_shortcut_overlays: "
        return text[len(prefix):] if text.startswith(prefix) else text
    return None


def frames(ticks, fps):
    return ticks * fps / SEC


def shapes(answer, fps):
    """(at seconds, frames, keys, label) of each overlay."""
    return [(round(o["at"] / SEC, 4), frames(o["duration"], fps), o["keys"], o["label"])
            for o in answer.get("overlays", [])]


# ---- the rows ------------------------------------------------------------------

O1_KEYS = [(1.0, "cmd+s"), (4.0, "cmd+shift+4"), (7.0, "ctrl+left"), (10.0, "cmd+plus")]


def o1_o5(client, files):
    doc = Doc(client, "o1")
    try:
        clip = doc.place(recording(files, "o1", O1_KEYS), at=t(2.0))
        answer = doc.overlays(clip=clip)
        state = doc.state()
        front = state["tracks"][-1]
        on = doc.on_track(front["id"], state)
        got = [(c["start"], c["duration"], (c.get("graphic") or {}).get("name"),
                (c.get("graphic") or {}).get("props")) for c in on]
        want = [(t(at), n * SEC // 30, "keyboard-keys",
                 {"keys": keys, "label": "", "position": "bottom", "theme": "dark"})
                for (at, keys), n in zip([(3.0, "cmd+s"), (6.0, "cmd+shift+4"),
                                          (9.0, "ctrl+left"), (12.0, "cmd+plus")],
                                         [45, 55, 45, 45])]
        props_ok = all(g[:3] == w[:3] and all((g[3] or {}).get(k) == v for k, v in w[3].items())
                       for g, w in zip(got, want)) and len(got) == len(want)
        check("O1", front["name"] == "Shortcuts" and answer.get("new_track") is True
              and answer.get("track") == front["id"] and props_ok
              and answer.get("module") == "keyboard-keys" and answer.get("written") is True
              and doc.modules() == ["keyboard-keys.js"],
              f"front track {front['name']!r}; clips {[(g[0], g[1], g[2]) for g in got]}; "
              f"props {[g[3] for g in got]}; answer module {answer.get('module')} written "
              f"{answer.get('written')} new_track {answer.get('new_track')}; graphics "
              f"{doc.modules()}")
        if "O5" in selected:
            o5(doc, front["id"], t(3.0) + 30 * SEC // 30)
    finally:
        doc.close()


def decode_png(path):
    """The frame's RGBA in 8-bit levels (`png_read.rgba8`): since spec §11 PR-20 the frame
    with an overlay is a 16-bit PNG and the one with the track hidden an 8-bit one, so both
    are read to the nearest level, which ffmpeg's own `rgba` conversion is not (#566)."""
    found = png_read.rgba8(path, env=bounded.child_env())
    return found[2] if found is not None and found[:2] == (W, H) else None


def o5(doc, track, at):
    shown = WORK / "o5-shown.png"
    hidden = WORK / "o5-hidden.png"
    doc.call("render_frame", t=at, path=str(shown))
    doc.call("set_track", track=track, hidden=True)
    doc.call("render_frame", t=at, path=str(hidden))
    a, b = decode_png(shown), decode_png(hidden)
    if a is None or b is None:
        check("O5", False, "a frame did not decode")
        return
    rows = {i // (W * 4) for i in range(0, len(a), 4) if a[i:i + 4] != b[i:i + 4]}
    check("O5", rows and min(rows) >= H // 2,
          f"{len(rows)} rows differ, from row {min(rows) if rows else '-'} to "
          f"{max(rows) if rows else '-'} (the bottom half starts at {H // 2})")


def o1b(client, files):
    doc = Doc(client, "o1b", fps=60)
    try:
        clip = doc.place(recording(files, "o1b", [(1.0, "cmd+s"), (2.0, "cmd+c")]))
        got = shapes(doc.overlays(clip=clip), 60)
        want = [(1.0, 60, "cmd+s", ""), (2.0, 90, "cmd+c", "")]
        check("O1b", got == want, f"{got} (want {want})")
    finally:
        doc.close()


def o2(client, files):
    shortcuts = [(1.0, "cmd+s"), (1.3, "cmd+c")]
    for fps, want_overlays, want_dropped in (
            (30, [(1.0, 45, "cmd+s", "")], 1),
            (60, [(1.0, 45, "cmd+s", ""), (1.75, 90, "cmd+c", "")], 0)):
        doc = Doc(client, f"o2-{fps}", fps=fps)
        try:
            clip = doc.place(recording(files, f"o2-{fps}", shortcuts))
            answer = doc.overlays(clip=clip)
            got = shapes(answer, fps)
            note = answer.get("note")
            want_note = "1 shortcut came too close to show." if want_dropped else None
            check("O2", got == want_overlays and answer.get("dropped") == want_dropped
                  and note == want_note,
                  f"{fps} fps: {got} dropped {answer.get('dropped')} note {note!r}")
        finally:
            doc.close()
    doc = Doc(client, "o2b", fps=60)
    try:
        clip = doc.place(recording(files, "o2b", [(1.0, "cmd+shift+4"), (1.3, "cmd+c")]))
        answer = doc.overlays(clip=clip)
        got = shapes(answer, 60)
        check("O2b", got == [(1.0, 90, "cmd+shift+4", "")] and answer.get("dropped") == 1,
              f"{got} dropped {answer.get('dropped')}")
    finally:
        doc.close()


def o3(client, files):
    doc = Doc(client, "o3")
    try:
        clip = doc.place(recording(files, "o3", [(1.0, "cmd+z"), (1.3, "cmd+z"),
                                                 (1.6, "cmd+z")]))
        answer = doc.overlays(clip=clip)
        got = shapes(answer, 30)
        check("O3", got == [(1.0, 63, "cmd+z", "×3")] and answer.get("merged") == 2,
              f"{got} merged {answer.get('merged')}")
    finally:
        doc.close()


def o4(client, files):
    doc = Doc(client, "o4")
    try:
        first = doc.place(recording(files, "o4-a", [(1.0, "cmd+s")]))
        one = doc.overlays(clip=first)
        second = doc.place(recording(files, "o4-b", [(1.0, "cmd+c")]), at=t(25.0))
        two = doc.overlays(clip=second)
        same = (doc.path / "graphics/keyboard-keys.js").read_bytes() == TEMPLATE.read_bytes()
        check("O4", two.get("module") == "keyboard-keys" and two.get("written") is False
              and two.get("track") == one.get("track") and two.get("new_track") is False
              and doc.modules() == ["keyboard-keys.js"] and same,
              f"second run: module {two.get('module')} written {two.get('written')} track "
              f"{two.get('track')} (first {one.get('track')}) new {two.get('new_track')}; "
              f"graphics {doc.modules()}, bytes the bundle's {same}")
        three = doc.overlays(clip=first)
        check("O4", three.get("new_track") is True and three.get("track") != one.get("track"),
              f"over the occupied span: new_track {three.get('new_track')} track "
              f"{three.get('track')}")
    finally:
        doc.close()


def o4b(client, files):
    doc = Doc(client, "o4b")
    try:
        first = doc.place(recording(files, "o4b-a", [(1.0, "cmd+s")]))
        one = doc.overlays(clip=first)
        old = one.get("track")
        before = doc.on_track(old)
        front = doc.call("add_track")["new_tracks"][0]
        third = doc.place(recording(files, "o4b-c", [(1.0, "cmd+c")]), at=t(30.0), track=front)
        answer = doc.overlays(clip=third)
        state = doc.state()
        ids = [tr["id"] for tr in state["tracks"]]
        new = answer.get("track")
        check("O4b", answer.get("new_track") is True and new != old and new in ids
              and ids.index(new) > ids.index(front)
              and state["tracks"][ids.index(new)]["name"] == "Shortcuts"
              and doc.on_track(old, state) == before,
              f"new_track {answer.get('new_track')} track {new} (old {old}, the clip's "
              f"{front}); order {ids}; old track unchanged {doc.on_track(old, state) == before}")
        edited = TEMPLATE.read_text() + "\n// edited by hand\n"
        doc.call("write_graphic", name="keyboard-keys", source=edited)
        again = doc.overlays(clip=first)
        check("O4b", again.get("module") == "keyboard-keys-2" and again.get("written") is True
              and doc.modules() == ["keyboard-keys-2.js", "keyboard-keys.js"],
              f"after a hand edit: module {again.get('module')} written {again.get('written')}; "
              f"graphics {doc.modules()}")
    finally:
        doc.close()


def o6():
    short = [(fps, keys, frames(d, fps)) for fps, keys, d, at in placed_overlays
             if frames(d, fps) < 10 * len([k for k in keys.split("+") if k]) + 25]
    off = [(fps, at) for fps, _, d, at in placed_overlays
           if (at * fps) % SEC or (d * fps) % SEC]
    check("O6", placed_overlays and not short and not off,
          f"{len(placed_overlays)} overlays; under D_min {short}; off the grid {off}")


def without_ids(clips):
    return sorted(({k: v for k, v in c.items() if k not in ("id", "track")} for c in clips),
                  key=lambda c: c["start"])


def o7(client, files):
    doc = Doc(client, "o7")
    copy = Doc(client, "o7-copy")
    try:
        movie = recording(files, "o7", O1_KEYS)
        clip = doc.place(movie)
        twin = copy.place(movie)
        doc.call("set_selection", clips=[clip])
        before = doc.state()
        pressed = doc.call("perform_menu_item", path=["Clip", "Add Shortcut Overlays"])
        began = time.monotonic()
        while time.monotonic() - began < 30 and doc.state() == before:
            time.sleep(0.25)
        after = doc.state()
        copy.overlays(clip=twin)
        tool = copy.state()
        menu_clips = without_ids(doc.on_track(after["tracks"][-1]["id"], after))
        tool_clips = without_ids(copy.on_track(tool["tracks"][-1]["id"], tool))
        names = ([tr["name"] for tr in after["tracks"]], [tr["name"] for tr in tool["tracks"]])
        undone = doc.call("undo").get("undone")
        back = doc.state() == before
        check("O7", menu_clips and menu_clips == tool_clips and names[0] == names[1]
              and undone == "Add Shortcut Overlays" and back,
              f"perform_menu_item ok {pressed.get('ok')}; the menu placed {len(menu_clips)}, "
              f"the tool {len(tool_clips)}, equal {menu_clips == tool_clips}; tracks {names}; "
              f"undo named {undone!r}, restored {back}")
    finally:
        doc.close()
        copy.close()


def o8(client, files):
    doc = Doc(client, "o8")
    try:
        clip = doc.place(recording(files, "o8", [(1.0, "cmd+s")]))
        cases = [
            ("duration 0.2", dict(clip=clip, duration=0.2), "Duration is 0.2 s; it runs 0.5–10."),
            ("to ≤ from", dict(clip=clip, **{"from": 100, "to": 100}),
             "To (100) must be after from (100)."),
        ]
        for tag, arguments, want in cases:
            said = refusal(lambda: doc.call("add_shortcut_overlays", **arguments))
            check("O8", said == want, f"{tag}: {said!r}")
        said = refusal(lambda: doc.call("add_shortcut_overlays", clip=clip, position="left"))
        check("O8", said is not None and "position" in said and "left" in said,
              f"position left: {said!r}")
        text = doc.call("add_text_clip", track=doc.track(), at=t(25.0))["new_clips"][0]
        said = refusal(lambda: doc.call("add_shortcut_overlays", clip=text))
        check("O8", said is not None and said.startswith(f"Clip {text} is not a media clip"),
              f"text clip: {said!r}")
        bare = doc.place(recording(files, "o8-bare", [], cursor=False), at=t(30.0),
                         cursor=False)
        said = refusal(lambda: doc.call("add_shortcut_overlays", clip=bare))
        check("O8", said is not None and "has no cursor file" in said, f"no cursor: {said!r}")
        doc.call("set_reversed", clip=clip, reversed=True)
        said = refusal(lambda: doc.call("add_shortcut_overlays", clip=clip))
        want = (f"Clip {clip} plays reversed; Add Shortcut Overlays places only clips that "
                "play forward.")
        check("O8", said == want, f"reversed: {said!r}")
    finally:
        doc.close()
    doc = Doc(client, "o8-empty")
    try:
        clip = doc.place(recording(files, "o8-empty", []))
        before = doc.state()
        answer = doc.overlays(clip=clip)
        after = doc.state()
        undone = doc.call("undo").get("undone")
        check("O8", answer.get("note") == NOTHING and answer.get("ok") is True
              and before == after and undone != "Add Shortcut Overlays"
              and doc.modules() == [] and answer.get("written") is False,
              f"no shortcuts: note {answer.get('note')!r}; unchanged {before == after}; the "
              f"next undo {undone!r}; graphics {doc.modules()}")
    finally:
        doc.close()


# ---- launches ------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("O0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def plain_rows(client, files):
    if {"O1", "O5"} & selected:
        attempt(lambda: o1_o5(client, files), *({"O1", "O5"} & selected))
    for names, body in ((["O1b"], o1b), (["O2", "O2b"], o2), (["O3"], o3), (["O4"], o4),
                        (["O4b"], o4b), (["O7"], o7), (["O8"], o8)):
        if set(names) & selected:
            attempt(lambda body=body: body(client, files), *(set(names) & selected))
    if "O6" in selected:
        o6()


def with_instance(binary, arguments, tag, body):
    log = WORK / f"instance-{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return False
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)
    return True


# ---- mutants -------------------------------------------------------------------

def edited_copy(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def cargo_mutant(name):
    """Runs the mutant's crate tests on an edited copy: the failing tests' names, or None and
    the reason the control could not be performed."""
    kind = MUTANTS[name][2]
    copy = WORK / f"mutant-{kind}"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    if kind == "core":
        shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
        os.symlink(ROOT / "graphic", copy / "graphic")
        crate, test, target = "core", ["--test", "shortcut_overlays"], "mutant-target"
    else:
        shutil.copytree(ROOT / "graphic", copy / "graphic",
                        ignore=shutil.ignore_patterns("target"))
        crate, test, target = "graphic", ["--test", "templates", "keyboard_keys"], \
            "mutant-graphic-target"
    why = edited_copy(name, copy)
    if why:
        return None, why
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK / target)})
    run = subprocess.run(["cargo", "test", "--release", *test], cwd=copy / crate,
                         capture_output=True, text=True, timeout=BUILD_BOUND, env=env)
    (WORK / f"mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    why = edited_copy(name, Path(made))
    if why:
        return None, why
    app, why = tree_copy.build_app(made, BUILD_BOUND)
    if app is None:
        return None, why
    return proof_app.executable(app), None


def run_mutant(name, files):
    global selected
    rows, _, kind = MUTANTS[name]
    print(f"CU8 — the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    if kind in ("core", "graphic"):
        failed, why = cargo_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        prefixes = [r.lower() + "_" for r in rows] if kind == "core" else ["keyboard_keys_"]
        caught = [f for f in failed if any(f.startswith(p) for p in prefixes)]
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    binary, why = mutant_app(name)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    selected = set(rows)
    if not with_instance(binary, [], "mutant", lambda c: plain_rows(c, files)):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
    named_failed = [r for r in rows if r in results and not all(ok for ok, _ in results[r])]
    if not set(rows) & set(results):
        print(f"mutant {name}: the control could not be performed — its rows were never scored")
        return 2
    print(f"MUTANT {name} {'CAUGHT' if named_failed else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if named_failed else 'passed'}")
    return 1 if named_failed else 0


# ---- main ----------------------------------------------------------------------

def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("O0")
    if WORK.exists():
        for child in WORK.iterdir():
            if child.name not in KEEP:
                tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        files = movies() if MUTANTS[args.mutant][2] == "app" else {}
        return run_mutant(args.mutant, files)

    print(f"CU8 — shortcut overlays ({proof_app.config()} build)", flush=True)
    files = movies()
    if args.socket:
        client = mcp.MCP(args.socket, timeout=CALL_BOUND)
        plain_rows(client, files)
        parity(Path(args.socket).parent / "framejob.log", "the given instance")
    else:
        binary = Path(args.app) if args.app else proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        if not with_instance(binary, [], "plain", lambda c: plain_rows(c, files)):
            for row in selected & set(PLAIN):
                check(row, False, "the app did not listen (plain)")

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
