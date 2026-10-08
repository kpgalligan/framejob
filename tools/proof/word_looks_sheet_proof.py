#!/usr/bin/env python3
"""Issue batch B86 phase 2 (#96; spec §11 W-15) — the three word-caption looks
through `transcribe` and in the Generate Captions sheet, over MCP, on an
instance this script launches.

    python3 tools/proof/word_looks_sheet_proof.py [--app PATH] [--lock-wait SECONDS]
    python3 tools/proof/word_looks_sheet_proof.py --mutant looks-not-placed
        (also refusals-dropped, tool-reads-remembered, note-never-shown)

ONE launch of the built app `proof_app` picks (Debug unless `RC_PROOF_APP=release`)
on a scratch socket (`mcp.launch`), stopped by
this script alone, **in a scratch home**
(`CFFIXED_USER_HOME=tools/proof/work/word-looks-sheet/home`), pointed at
`cloud_captions_probe`'s stand-in for AssemblyAI (`Fake`, under
`hold_cloud_lock`: `-RCAssemblyAIEndpoint`, a scratch `-RCSecretFolder`, the
dummy key `proof-key` — nothing here reaches AssemblyAI and nothing is paid
for), and with the sheet's remembered choices set in the ARGUMENT domain,
which is never persisted: `-ReelcutCaptionEngine apple -ReelcutCaptionStyle
pill -ReelcutCaptionSlide YES -ReelcutCaptionFill YES -ReelcutCaptionDim YES`.
No remembered control is clicked and no persisting menu item is performed:
the one menu item is File ▸ Generate Captions…, whose sheet is cancelled.

The fixture is built over MCP: 1920×1080 at 30 fps on black, one clip over
`tools/proof/media/speech.aiff`. Every `transcribe` names
`engine: "assemblyai"`, so the words are the stand-in's five — "Hello there
everyone", a 0.6 s pause, "welcome back" — and every instant a row renders is
computed from the placed clips' own `words`, read through `get_project`, on
the frame grid. **Every placing call carries `replace: true`**, so exactly one
caption track exists at every render; "off" is the same call without the
switch. Frames are `render_frame` PNGs at `max_width` 960, kept under
`tools/proof/work/word-looks-sheet/frames/`; pixels are read through
`word_looks_proof.py`'s `Picture`.

Rows:
- **H0** (CONTROL): `<home>/Library/Application Support` is a directory.
- **C1** (CONTROL): `tools/list` shows `slide`, `fill` and `dim` as described
  booleans, each description holding its literal style list.
- **T1** `style: pill, slide: true`: `looks` is `["slide"]`; every placed clip
  has `active_pill.glide` true, `active_fill` false, `pause_dim` 0. With `a`
  the first page's second word's start: the plate colour's centre at the
  first frame ≥ `a` + 0.05 s lies strictly between its centres at the last
  frame before `a` and the first ≥ `a` + 0.25 s; off, that frame's centre
  equals the later one's and its PNG differs from on.
- **T2** `style: karaoke, fill: true`: `active_fill` true on every clip.
  Half-way through the second word's fill (`min(end − start, 0.6 s)`) the
  last active-colour column lies strictly inside the middle 60 % of the span
  from its value one frame before the word to its value after the fill; off,
  it is already at the end.
- **T3** `style: karaoke, dim: true`: `pause_dim` 0.5 on every clip. At the
  first frame ≥ 0.15 s after the first page's last word ends the ink's mean
  distance from the background is 0.5 ± 0.05 of the off frame's at that
  instant; inside the last word the on and off PNGs are byte-identical.
- **T4**: `slide` with karaoke, `fill` with pill, `fill` with one_word, `dim`
  with subtitles, and `slide` with pill and `place: false` — each `true` is
  refused in its literal sentence and `get_project` is unchanged; all three
  `false` with subtitles and `place: false` is accepted.
- **T5**: `style: pill` with no boolean, on this launch whose remembered boxes
  are all on: no `looks` key; `glide` false, `active_fill` false, `pause_dim`
  0 on every clip.
- **U1**: File ▸ Generate Captions… (`perform_menu_item`), `snapshot_ui
  {window: "sheet"}`, `cancel_sheet`. In the layout dump the three boxes (by
  id and title) and the note (by id and text) are present and not hidden,
  each box at least its intrinsic width, the note at most 258 pt wide (its
  frame less a label's 2 pt inset each side) and at least its intrinsic
  height, and no `problems` entry names any of the four.
- **Z1** (CONTROL): the project closes, and the launch's log holds no
  `Reelcut: ` line.

`--mutant NAME` builds a COPY of the tree (`tree_copy.make_copy`), replaces
the mutant's one anchor in the copy's `app/Sources` (asserted to occur
exactly once), builds it by the copy's own `make app-debug` (`make app` under
`RC_PROOF_APP=release`; `tree_copy.build_app`), and runs the rows on it:
  looks-not-placed       the handler hands `place` no looks: T1, T2 and T3
                         must ALL fail.
  refusals-dropped       a `true` that would show nothing is not refused: T4
                         must fail.
  tool-reads-remembered  the tool reads the sheet's remembered boxes when a
                         boolean is absent: T5 must fail.
  note-never-shown       the on-device note stays hidden: U1 must fail.
Exit 0 means every named row FAILED in the copy — caught; 1 that one passed —
survived; 2 that the control could not be performed. A plain run exits 0 iff
every row passed; 3 is `mcp.py`'s, a moved default.
"""

import argparse
import atexit
import json
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
import v2_snapshot  # noqa: E402
from cloud_captions_probe import Fake, hold_cloud_lock  # noqa: E402
from word_looks_proof import Picture, attempt, canon, centre, reply  # noqa: E402

WORK = ROOT / "tools/proof/work/word-looks-sheet"
HOME = WORK / "home"
FRAMES = WORK / "frames"
SECRETS = WORK / "secrets"
PROJECT = WORK / "looks.reelcut"
APP = proof_app.bundle()
SPEECH = ROOT / "tools/proof/media/speech.aiff"
CALL_BOUND = 300
SEC = 600_000
FRAME = 20_000
DUMMY = "proof-key"
WORDS = [
    {"text": "Hello", "start": 600, "end": 1120, "confidence": 0.98, "speaker": None},
    {"text": "there", "start": 1180, "end": 1600, "confidence": 0.96, "speaker": None},
    {"text": "everyone", "start": 1700, "end": 2400, "confidence": 0.91, "speaker": None},
    {"text": "welcome", "start": 3000, "end": 3600, "confidence": 0.93, "speaker": None},
    {"text": "back", "start": 3700, "end": 4100, "confidence": 0.95, "speaker": None},
]
REMEMBERED = ["-ReelcutCaptionEngine", "apple", "-ReelcutCaptionStyle", "pill",
              "-ReelcutCaptionSlide", "YES", "-ReelcutCaptionFill", "YES",
              "-ReelcutCaptionDim", "YES"]
# The literals C1 and T4 hold the app's derived lists to.
STYLE_LISTS = {"slide": "pill", "fill": "highlight, karaoke or build",
               "dim": "highlight, pill, karaoke, build or one_word"}
TITLES = {"captions.look.slide": "Slide the pill", "captions.look.fill": "Fill words as spoken",
          "captions.look.dim": "Dim in pauses"}
NOTE_ID = "captions.look.dimnote"
NOTE = "On-device words rarely carry a pause; this shows mostly with AssemblyAI."
# A label's FRAME is 2 pt wider than its text on each side (app/CLAUDE.md;
# measured here: a 261.5 pt frame round a 257.5 pt intrinsic width). The dump
# records frames; the note's width is its frame less the two insets, the
# alignment rect `snapshot_ui`'s own rules measure (#140).
LABEL_INSET = 2
ROWS = ["H0", "C1", "T1", "T2", "T3", "T4", "T5", "U1", "Z1"]
CAPTIONS = "AgentServer+Captions.swift"
# name: (file, anchor, replacement, the rows that must ALL fail)
MUTANTS = {
    "looks-not-placed": (
        CAPTIONS,
        "                    style: style, looks: asked.looks, replacing: replacing)\n",
        "                    style: style, looks: .none, replacing: replacing)\n",
        ("T1", "T2", "T3")),
    "refusals-dropped": (
        CAPTIONS,
        "        for look in CaptionLooks.Look.allCases where looks[look] {\n"
        "            guard look.isLive(for: style) else {\n",
        "        for look in CaptionLooks.Look.allCases where looks[look] && false {\n"
        "            guard look.isLive(for: style) else {\n",
        ("T4",)),
    "tool-reads-remembered": (
        CAPTIONS,
        "            guard let value = try boolArg(a, look.rawValue) else { continue }\n",
        "            guard let value = try boolArg(a, look.rawValue) else {\n"
        "                looks[look] = UserDefaults.standard.bool(forKey: look.defaultsKey)\n"
        "                continue\n"
        "            }\n",
        ("T5",)),
    "note-never-shown": (
        "TranscribeSheetController+Looks.swift",
        "        dimNoteLabel.isHidden = !(engine == .apple && dimCheckbox.isEnabled)\n",
        "        dimNoteLabel.isHidden = true\n",
        ("U1",)),
}
rows = {}


def check(name, good, detail=""):
    rows[name.split()[0]] = bool(good)
    print(("  ok   " if good else "  FAIL ") + name + (f"\n       {detail}" if detail else ""),
          flush=True)


# ---- the project -------------------------------------------------------------------

class Project:
    def __init__(self, client):
        self.client = client
        self.path = str(PROJECT)
        self.steps = []
        self.note("new_project", {"path": self.path})
        self.note("set_canvas", {"project": self.path, "width": 1920, "height": 1080,
                                 "fps": [30, 1], "background": [0.0, 0.0, 0.0, 1.0]})
        media = reply(self.note("import_media", {"project": self.path, "path": str(SPEECH)}))
        track = ((self.get().get("tracks") or [{}])[0]).get("id")
        self.note("add_clip", {"project": self.path, "track": track,
                               "media": media.get("media"), "at": 0})
        # A new project may already BE this canvas, and then `set_canvas` is an
        # identity ("made no change"), not a failure: the canvas is read back.
        canvas = self.get().get("canvas") or {}
        self.canvas_ok = (canvas.get("width"), canvas.get("height"), canvas.get("fps")) == (
            1920, 1080, [30, 1])
        self.built = self.canvas_ok and all(
            step["ok"] or (tool == "set_canvas" and "made no change" in step["error"])
            for tool, step in self.steps)

    def note(self, tool, arguments):
        got = attempt(self.client, tool, arguments)
        self.steps.append((tool, got))
        return got

    def problems(self):
        return [f"{tool}: {got['error']}" for tool, got in self.steps if not got["ok"]] + (
            [] if self.canvas_ok else ["the canvas did not read back as 1920×1080 at 30 fps"])

    def get(self):
        got = attempt(self.client, "get_project", {"project": self.path})
        return reply(got).get("project") or {}

    def transcribe(self, **arguments):
        """`transcribe` on the stand-in's engine; the attempt, refusal or not."""
        call = dict(arguments, project=self.path, engine="assemblyai")
        return attempt(self.client, "transcribe", call)

    def pages(self):
        """The placed caption clips, in time order, and how many caption tracks hold them."""
        project = self.get()
        tracks = {t["id"] for t in project.get("tracks") or []
                  if t.get("name", "").startswith("Captions")}
        clips = sorted((c for c in project.get("clips") or [] if c.get("track") in tracks),
                       key=lambda c: c["start"])
        return clips, len(tracks)

    def frame(self, tag, ticks):
        """`render_frame` at `ticks`, 960 wide; the PNG's bytes, or None."""
        out = FRAMES / f"{tag}.png"
        if out.exists():
            out.unlink()
        got = attempt(self.client, "render_frame",
                      {"project": self.path, "t": ticks, "path": str(out), "max_width": 960})
        return out.read_bytes() if got["ok"] and out.exists() else None

    def close(self):
        return attempt(self.client, "close_project", {"project": self.path, "discard": True})


def style_of(clip):
    return ((clip.get("text") or {}).get("word_style")) or {}


def keys_of(clips):
    """Each clip's three look values, as (glide, active_fill, pause_dim)."""
    return [((style_of(c).get("active_pill") or {}).get("glide"), style_of(c).get("active_fill"),
             style_of(c).get("pause_dim")) for c in clips]


def at_or_after(ticks):
    return -(-int(ticks) // FRAME) * FRAME


def before(ticks):
    return (-(-int(ticks) // FRAME) - 1) * FRAME


def word(clip, index):
    """Word `index`'s (start, end) on the TIMELINE, off the clip's own `words`."""
    timing = (clip.get("text") or {}).get("words") or []
    if not -len(timing) <= index < len(timing):
        return None
    return clip["start"] + timing[index]["start"], clip["start"] + timing[index]["end"]


def plate(p):
    """The Pill preset's violet, [0.55, 0.27, 0.93]: (140, 69, 237)."""
    return abs(p[0] - 140) <= 14 and abs(p[1] - 69) <= 14 and abs(p[2] - 237) <= 14


def yellow(p):
    """Karaoke's active and spoken colour, [1, 0.85, 0]: (255, 217, 0)."""
    return p[0] >= 235 and abs(p[1] - 217) <= 14 and p[2] <= 40


def pictures(*frames):
    return None if any(f is None for f in frames) else [Picture(f) for f in frames]


# ---- rows --------------------------------------------------------------------------

def row_c1(client):
    try:
        properties = client.schemas()["transcribe"]["inputSchema"]["properties"]
    except Exception as error:  # an unreadable catalog is the row's answer
        check("C1 CONTROL: tools/list could not be read", False, f"{type(error).__name__}: {error}")
        return
    wrong = []
    for name, styles in STYLE_LISTS.items():
        entry = properties.get(name) or {}
        text = entry.get("description") or ""
        if entry.get("type") != "boolean" or f"applies with style {styles}:" not in text:
            wrong.append(f"{name}: type {entry.get('type')!r}, description {text!r}")
    check("C1 CONTROL: tools/list shows slide, fill and dim as described booleans, each "
          "description holding its literal style list", not wrong, "; ".join(wrong))


def row_t1(project):
    on = project.transcribe(style="pill", slide=True, replace=True)
    clips, tracks = project.pages()
    keys = keys_of(clips)
    second = word(clips[0], 1) if clips else None
    shots = {}
    if second:
        a = second[0]
        times = {"before": before(a), "during": at_or_after(a + 0.05 * SEC),
                 "after": at_or_after(a + 0.25 * SEC)}
        shots = {name: project.frame(f"t1-on-{name}", t) for name, t in times.items()}
    off = project.transcribe(style="pill", replace=True)
    off_clips, off_tracks = project.pages()
    off_second = word(off_clips[0], 1) if off_clips else None
    off_shots = {}
    if off_second and second:
        off_shots = {name: project.frame(f"t1-off-{name}", t) for name, t in times.items()
                     if name != "before"}
    seen = pictures(shots.get("before"), shots.get("during"), shots.get("after"),
                    off_shots.get("during"), off_shots.get("after")) if shots else None
    if seen is None:
        check("T1 the slide's frames could not be rendered", False,
              f"on {on.get('error', 'ok')}; off {off.get('error', 'ok')}; {len(clips)} clips; "
              f"second word {second}")
        return
    x1, x, x2, off_x, off_x2 = (centre(p, plate) for p in seen)
    placed = (on["ok"] and reply(on).get("looks") == ["slide"] and bool(clips) and tracks == 1
              and all(k == (True, False, 0) for k in keys))
    moving = (None not in (x1, x, x2) and min(x1, x2) < x < max(x1, x2) and x1 != x2)
    jumped = (off["ok"] and off_tracks == 1 and off_second == second
              and None not in (off_x, off_x2) and off_x == off_x2
              and off_shots.get("during") != shots.get("during"))
    check("T1 style pill, slide true: looks is [\"slide\"], every clip has glide true, "
          "active_fill false, pause_dim 0; the plate's centre 0.05 s into the second word "
          "lies strictly between its centres before the word and 0.25 s in; off, it is "
          "already there and the PNG differs",
          placed and moving and jumped,
          f"looks {reply(on).get('looks')}, {len(clips)} clips on {tracks} caption track(s), "
          f"keys {sorted(set(keys))}; on: x {x1} → {x} → {x2}; off: {off_x} at 0.05 s, "
          f"{off_x2} at 0.25 s, PNG differs {off_shots.get('during') != shots.get('during')}; "
          f"instants {times}")


def row_t2(project):
    on = project.transcribe(style="karaoke", fill=True, replace=True)
    clips, tracks = project.pages()
    keys = keys_of(clips)
    second = word(clips[0], 1) if clips else None
    shots, times = {}, {}
    if second:
        start, end = second
        takes = min(end - start, 0.6 * SEC)
        times = {"before": before(start), "half": at_or_after(start + takes / 2),
                 "after": at_or_after(start + takes)}
        shots = {name: project.frame(f"t2-on-{name}", t) for name, t in times.items()}
    off = project.transcribe(style="karaoke", replace=True)
    off_clips, off_tracks = project.pages()
    off_half = project.frame("t2-off-half", times["half"]) if times else None
    seen = pictures(shots.get("before"), shots.get("half"), shots.get("after"),
                    off_half) if shots else None
    if seen is None:
        check("T2 the fill's frames could not be rendered", False,
              f"on {on.get('error', 'ok')}; off {off.get('error', 'ok')}; {len(clips)} clips; "
              f"second word {second}")
        return
    # The first page's row is the only ink on screen at these instants.
    lasts = [(p.columns(yellow) or [None])[-1] for p in seen]
    x0, x, x1, off_x = lasts
    placed = (on["ok"] and reply(on).get("looks") == ["fill"] and bool(clips) and tracks == 1
              and all(k[1] is True for k in keys))
    inside = (None not in (x0, x, x1) and x1 > x0
              and x0 + 0.2 * (x1 - x0) < x < x0 + 0.8 * (x1 - x0))
    done = (off["ok"] and off_tracks == 1 and off_x is not None and off_x == x1
            and all(k[1] is False for k in keys_of(off_clips)))
    check("T2 style karaoke, fill true: active_fill is true on every clip; half-way through "
          "the second word's fill the last active-colour column lies strictly inside the "
          "middle 60 % of its travel; off, it is already at the end",
          placed and inside and done,
          f"looks {reply(on).get('looks')}, {len(clips)} clips on {tracks} caption track(s), "
          f"keys {sorted(set(keys), key=str)}; on: last yellow column {x0} → {x} → {x1} "
          f"(middle 60 %: {x0 + 0.2 * (x1 - x0) if None not in (x0, x1) else None} … "
          f"{x0 + 0.8 * (x1 - x0) if None not in (x0, x1) else None}); off at the half: "
          f"{off_x}; instants {times}")


def row_t3(project):
    on = project.transcribe(style="karaoke", dim=True, replace=True)
    clips, tracks = project.pages()
    keys = keys_of(clips)
    last = word(clips[0], -1) if clips else None
    shots, times = {}, {}
    if last:
        start, end = last
        times = {"inside": at_or_after((start + end) / 2), "pause": at_or_after(end + 0.15 * SEC)}
        shots = {name: project.frame(f"t3-on-{name}", t) for name, t in times.items()}
    off = project.transcribe(style="karaoke", replace=True)
    off_clips, off_tracks = project.pages()
    off_shots = {name: project.frame(f"t3-off-{name}", t) for name, t in times.items()}
    seen = pictures(shots.get("pause"), off_shots.get("pause")) if shots else None
    if seen is None or shots.get("inside") is None or off_shots.get("inside") is None:
        check("T3 the dim's frames could not be rendered", False,
              f"on {on.get('error', 'ok')}; off {off.get('error', 'ok')}; {len(clips)} clips; "
              f"last word {last}")
        return
    low, full = (p.distance() for p in seen)
    ratio = low / full if full else None
    held = bool(clips) and times["pause"] < clips[0]["start"] + clips[0]["duration"]
    placed = (on["ok"] and reply(on).get("looks") == ["dim"] and bool(clips) and tracks == 1
              and all(k[2] == 0.5 for k in keys))
    plain = (off["ok"] and off_tracks == 1 and all(k[2] == 0 for k in keys_of(off_clips)))
    check("T3 style karaoke, dim true: pause_dim is 0.5 on every clip; 0.15 s after the first "
          "page's last word the ink's distance from the background is 0.5 ± 0.05 of the off "
          "frame's; inside that word the on and off PNGs are byte-identical",
          placed and plain and held and ratio is not None and abs(ratio - 0.5) <= 0.05
          and shots["inside"] == off_shots["inside"],
          f"looks {reply(on).get('looks')}, {len(clips)} clips on {tracks} caption track(s), "
          f"keys {sorted(set(keys), key=str)}; the page still up at the pause frame {held}; "
          f"on {low:.4f}, off {full:.4f}, ratio {ratio}; inside the word equal "
          f"{shots['inside'] == off_shots['inside']}; instants {times}")


def row_t4(project):
    def only(name, style):
        return f"{name} only applies with style {STYLE_LISTS[name]} — not {style}."

    cases = [
        ({"style": "karaoke", "slide": True}, only("slide", "karaoke")),
        ({"style": "pill", "fill": True}, only("fill", "pill")),
        ({"style": "one_word", "fill": True}, only("fill", "one_word")),
        ({"style": "subtitles", "dim": True}, only("dim", "subtitles")),
        ({"style": "pill", "slide": True, "place": False},
         "slide only applies when place is true: with place false nothing is placed, so "
         "nothing is styled."),
    ]
    was = canon(project.get())
    wrong = []
    for arguments, sentence in cases:
        got = project.transcribe(**arguments)
        now = canon(project.get())
        if got["ok"] or sentence not in got["error"] or now != was:
            wrong.append(f"{arguments}: {got.get('error', 'ACCEPTED')!r}, unchanged {now == was}")
            was = now
    quiet = project.transcribe(style="subtitles", place=False, slide=False, fill=False,
                               dim=False)
    answer = reply(quiet)
    accepted = (quiet["ok"] and answer.get("placed") is False and "looks" not in answer
                and canon(project.get()) == was)
    check("T4 slide with karaoke, fill with pill, fill with one_word, dim with subtitles, and "
          "slide with pill and place false are each refused in the literal sentence and "
          "change nothing; all three false with subtitles and place false is accepted",
          not wrong and accepted,
          f"wrong {wrong}; all three false: {quiet.get('error', 'accepted')}, placed "
          f"{answer.get('placed')}, a looks key {'looks' in answer}")


def row_t5(project):
    got = project.transcribe(style="pill", replace=True)
    clips, tracks = project.pages()
    keys = keys_of(clips)
    check("T5 style pill with no boolean, on a launch whose remembered boxes are all on: no "
          "looks key, and glide false, active_fill false, pause_dim 0 on every clip",
          got["ok"] and "looks" not in reply(got) and bool(clips) and tracks == 1
          and all(k == (False, False, 0) for k in keys),
          f"{got.get('error', 'ok')}; a looks key {'looks' in reply(got)}: "
          f"{reply(got).get('looks')}; {len(clips)} clips, keys {sorted(set(keys), key=str)}")


def row_u1(project):
    client = project.client
    shown = attempt(client, "perform_menu_item",
                    {"project": project.path, "path": ["File", "Generate Captions…"]})
    layout, problem = None, ""
    if shown["ok"]:
        try:
            answer = v2_snapshot.snap(client, window="sheet", project=project.path,
                                      path=str(FRAMES / "u1-sheet.png"))
            v2_snapshot.captures.clear()
            with open(answer["layout_path"]) as handle:
                layout = json.load(handle)
        except Exception as error:  # a capture that failed is the row's answer
            problem = f"{type(error).__name__}: {error}"
    else:
        problem = shown["error"]
    cancelled = attempt(client, "cancel_sheet", {"project": project.path})
    if layout is None:
        check("U1 the sheet could not be captured", False,
              f"{problem}; cancel_sheet {cancelled.get('error', 'ok')}")
        return
    views = {v.get("id"): v for v in layout["views"] if v.get("id") and not v.get("hidden")}
    wrong = []
    for ident, title in TITLES.items():
        view = views.get(ident)
        if view is None:
            wrong.append(f"{ident} is not in the dump")
        elif view.get("text") != title or view["frame"][2] + 0.5 < view["intrinsic"][0]:
            wrong.append(f"{ident}: text {view.get('text')!r}, {view['frame'][2]} wide, "
                         f"intrinsic {view['intrinsic'][0]}")
    note = views.get(NOTE_ID)
    if note is None:
        wrong.append(f"{NOTE_ID} is not in the dump")
    elif (note.get("text") != NOTE or note["frame"][2] - 2 * LABEL_INSET > 258.5
          or note["frame"][3] + 0.5 < note["intrinsic"][1]):
        wrong.append(f"{NOTE_ID}: text {note.get('text')!r}, frame {note['frame']}, intrinsic "
                     f"{note['intrinsic']}")
    ours = {v["i"] for v in views.values() if v.get("id") in set(TITLES) | {NOTE_ID}}
    named = [p for p in layout.get("problems", []) if p.get("view") in ours]
    check("U1 File ▸ Generate Captions…: the three boxes (by id and title) and the note (by id "
          "and text) are in the sheet's layout dump and not hidden, each box at least its "
          "intrinsic width, the note at most 258 pt wide and at least its intrinsic height, "
          "and no layout problem names any of the four; the sheet is cancelled",
          not wrong and not named and cancelled["ok"],
          f"wrong {wrong}; problems naming them {named}; cancel_sheet "
          f"{cancelled.get('error', 'ok')}; the note's frame "
          f"{note['frame'] if note else None}")


# ---- the launch --------------------------------------------------------------------

def run_rows(app, fake):
    """Every row; False when the instance did not come up."""
    fake.scenario(words=WORDS)
    shutil.rmtree(SECRETS, ignore_errors=True)
    SECRETS.mkdir(parents=True)
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME), "RC_ASSEMBLYAI_KEY": DUMMY})
    env.pop("ANTHROPIC_API_KEY", None)
    log = WORK / "main.log"
    launched = mcp.launch(
        str(app / "Contents/MacOS/Reelcut"),
        arguments=["-RCSecretFolder", str(SECRETS), "-RCAssemblyAIEndpoint", fake.base,
                   "-NSRecentDocumentsLimit", "0", *REMEMBERED],
        env=env, log_path=str(log), timeout=CALL_BOUND)
    closed = None
    try:
        if launched.client is None:
            print(f"instrument failure: the app did not listen at {launched.socket_path}")
            return False
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        support = HOME / "Library/Application Support"
        check("H0 CONTROL: the scratch home took: <home>/Library/Application Support is a "
              "directory", support.is_dir(), str(support))
        if rows.get("H0"):
            row_c1(launched.client)
            project = Project(launched.client)
            if not project.built:
                for name in ("T1", "T2", "T3", "T4", "T5", "U1"):
                    check(f"{name} not run: the fixture did not build", False,
                          "; ".join(project.problems()))
            else:
                for row in (row_t1, row_t2, row_t3, row_t4, row_t5, row_u1):
                    try:
                        row(project)
                    except Exception as error:  # a row that could not run is a failure
                        check(f"{row.__name__[4:].upper()} did not run to its end", False,
                              f"{type(error).__name__}: {error}")
            closed = project.close()
        try:
            complaints = [line.strip() for line in open(log, errors="replace")
                          if "Reelcut: " in line]
        except OSError as error:
            complaints = [f"the log could not be read: {error}"]
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    if rows.get("H0"):
        check("Z1 CONTROL: the project closes and the launch's log holds no `Reelcut: ` line",
              closed is not None and closed["ok"] and not complaints,
              f"close {closed.get('error', 'ok') if closed else 'not reached'}; complaints "
              f"{complaints}")
    return True


def remove_scratch():
    """The scratch home, the secret folder and a mutant's tree copy go; the frames stay."""
    for folder in (HOME, SECRETS, WORK / "mutant"):
        if folder.exists():
            tree_copy.remove_tree(str(folder))


def build_mutant(name):
    """A copy of the tree with the mutant's one anchor replaced, built by its
    own `tree_copy.build_app`. The app bundle, or None and why."""
    file, anchor, replacement, _ = MUTANTS[name]
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    copy = Path(made)
    target = copy / "app/Sources" / file
    text = target.read_text()
    if text.count(anchor) != 1:
        return None, (f"the anchor {anchor.splitlines()[0].strip()!r} occurs "
                      f"{text.count(anchor)} times in {file}")
    target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(copy, 1500)
    if app is None:
        return None, reason
    return app, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default=str(APP))
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--lock-wait", type=float, default=3600,
                        help="how long to wait for the cloud instruments' lock, in seconds")
    args = parser.parse_args()
    lock, waited, holder = hold_cloud_lock(args.lock_wait)
    if lock is None:
        print(f"instrument failure: the cloud instruments' lock is still held by {holder} "
              f"after {waited:.0f} s")
        return 2
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    atexit.register(remove_scratch)
    HOME.mkdir(parents=True)
    FRAMES.mkdir(parents=True)
    app = Path(args.app)
    named = MUTANTS[args.mutant][3] if args.mutant else ()
    if args.mutant:
        print(f"word looks, the sheet and transcribe — the {args.mutant} MUTANT "
              f"({', '.join(named)} must FAIL)", flush=True)
        app, why = build_mutant(args.mutant)
        if app is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print("B86 phase 2 — the three looks through transcribe and in the sheet, over MCP",
              flush=True)
    if not (app / "Contents/MacOS/Reelcut").is_file():
        print(f"instrument failure: no app binary at {app / 'Contents/MacOS/Reelcut'}")
        return 2
    if not SPEECH.is_file():
        print(f"instrument failure: {SPEECH} is missing (tools/proof/README.md has its recipe)")
        return 2
    with Fake("word-looks-sheet") as fake:
        if not run_rows(app, fake):
            return 2
    passed = sum(1 for name in ROWS if rows.get(name))
    print(f"{passed}/{len(ROWS)}")
    if args.mutant:
        missing = [name for name in named if name not in rows]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — "
                  f"{', '.join(missing)} not reached")
            return 2
        failed = [name for name in ROWS if not rows.get(name)]
        caught = all(rows.get(name) is False for name in named)
        print(f"{'MUTANT PASS' if caught else 'MUTANT FAILURE'}: {args.mutant} — "
              f"{', '.join(named)} {'ALL FAILED' if caught else 'did not all fail'} in the copy "
              f"(failed: {', '.join(failed)})")
        return 0 if caught else 1
    return 0 if passed == len(ROWS) else 1


if __name__ == "__main__":
    sys.exit(main())
