#!/usr/bin/env python3
"""Road map 11's V3 — the screen catalog, captured from a Reelcut of its own.

    python3 tools/proof/screens.py [--port 4871] [--app APP] [--screens DIR]
        [--out DIR] [--only ID,…] [--compare EARLIER_OUT]

It launches its OWN Release instance on `--port` (the log names the port it
actually bound), with every `UserDefaults` key a captured screen draws pinned
as a launch argument (`PINS`), an empty `-RCSecretFolder`, a `-RCSpendFolder`
that does not exist (removed before each launch and never created, so
Settings' month line is an empty month and the person's ledger is never read,
spec §11 P-5, P-7), a dead loopback AssemblyAI endpoint and no recent
documents; builds the fixture projects the
screens name (`FIXTURES`) from `tools/proof/media/`, and for a fixture that
names `sound` clips waits until `detect_silence` answers no `pending_peaks`
for them (`wait_for_peaks`, printed as `fixture <name>: peaks cached after …`),
so a timeline capture never races a waveform band; walks every screen file
in `--screens` (default `designs/screens/`) in name order; captures each
screen light and dark through `snapshot_ui`; and writes `--out` (default
`tools/proof/work/screens/<YYYY-MM-DD-HHMMSS>/`): the PNGs, their layout
dumps, `screens.md` (each picture beside its prose and its layout problems)
and `results.json`. It kills only the processes it started.

**Each look is its own instance.** The walk runs twice: once on an instance
launched with `-RCDevAppearance light`, then on one launched with
`-RCDevAppearance dark` (`DevAppearance.swift`, a dev-only launch default that
sets `NSApp.appearance` before any window is built). `snapshot_ui` is never
asked for an appearance: switching a live window left the colours its views
took when they were built in the launch appearance, so such a capture was a
mix the app never draws. Every capture must answer the look its instance was
launched in, or the screen fails.

A screen file is a JSON front block (```` ```json screen ```` … ```` ``` ````)
and prose; `designs/screens/README.md` is the format. Every step is checked
before the first one runs, so a broken screen file fails by name and runs
nothing.

Rows print as `<ID> <pass|fail|skip> — <reason>`: `P1.<look>` each launch,
`P2` the pins cover every key, `P3.<look>` each instance's end, and one row
per screen, scored after both looks (a screen passes only if both did; each
look's result prints first as an indented progress line). Then the new layout
problems (reported, never scored), `recorder panel up`, `scores:`, `digest:`
(sha256 of the sorted `ID=state` lines) and `out:`. With `--compare`, each
PNG against the same name in an earlier run (not scored). Exit 0 iff no row
failed.

**The recorder panel.** File ▸ New Recording… puts up a non-activating panel
whose default button is Record. Shown with Reelcut in the background it no
longer takes key (spec §11, "The recorder panel takes key only from an active
Reelcut", #137), but an instance that is ACTIVE when New Recording… runs
still gets a key panel with Record on Return, and this script cannot hold its
child inactive. So it is allowed only in the LAST screen run, its captures
follow the perform at once, and the instance is stopped right after them;
the time from the perform's answer to the child's exit is printed per look as
`recorder panel up`, with the listing's `active` read before the perform
(`active before New Recording…`). It goes up once per instance, so twice a
run.
"""

import argparse
import datetime
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import v2_snapshot  # noqa: E402
from dev_tools import DEV_TOOLS, dev_marker_count  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402

SOURCES = os.path.join(ROOT, "app", "Sources")
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work", "screens")
FIXTURE_DIR = os.path.join(WORK, "fixtures")
DEFAULT_APP = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
DEFAULT_SCREENS = os.path.join(ROOT, "designs", "screens")
SECOND = 600_000

STEP_TOOLS = ("set_selection", "set_playhead", "detect_silence", "perform_menu_item",
              "cancel_sheet", "select_inspector_tab")
LOOKS = ("light", "dark")
APPEARANCE_KEY = "RCDevAppearance"
WINDOWS = ("welcome", "settings", "editor", "sheet", "recorder")
REGIONS = ("toolbar", "preview", "inspector", "timeline")
NEW_RECORDING = ["File", "New Recording…"]
FRONT_KEYS = {"title", "project", "steps", "captures", "after", "expect", "skip"}
STEP_KEYS = {"call", "args", "until_absent", "within"}

# Every section id (`id: "x.y", title:` in app/Sources) → COLLAPSED, pinned to
# its first-run state: `not defaultExpanded`, except the two a captured
# sub-tab opens through `ClipPane.makeSections()`'s `expandByDefault` walk
# (ClipPane.swift:210-214) because every section of that sub-tab defaults
# closed — Sound's `audio.volume` (09) and Clip's `clip.timing` (10). A pin
# stops the walk (InspectorSection.swift:143-146), so those two are pinned
# OPEN; 09's and 10's `expect`s catch a pin that drifts.
SECTIONS = {
    "audio.compressor": True, "audio.duck": True, "audio.fades": True, "audio.mix": True,
    "audio.noise": True, "audio.volume": False,
    "clip.timing": False,
    "doc.appearance": False, "doc.canvas": False, "doc.markers": False, "doc.rate": False,
    "doc.summary": False,
    "graphic.properties": False, "graphic.size": True, "graphic.source": True,
    "graphic.timeline": True,
    "media.files": False,
    "shape.arrows": True, "shape.fill": True, "shape.gradient": True, "shape.kind": False,
    "shape.stroke": True,
    "text.animation": True, "text.backdrop": True, "text.box": True, "text.content": False,
    "text.font": True, "text.outline": True, "text.presets": True, "text.style": True,
    "video.chroma": True, "video.color": True, "video.corner": True, "video.crop": True,
    "video.filters": True, "video.motion": True, "video.obscure": True,
    "video.reflection": True, "video.shadow": True, "video.speed": True,
    "video.spotlight": True, "video.transform": False, "video.transition": True,
}


def _plist(value):
    if value is True:
        return "<true/>"
    if value is False:
        return "<false/>"
    if isinstance(value, float):
        return f"<real>{value:g}</real>"
    if isinstance(value, int):
        return f"<integer>{value}</integer>"
    return value


# tools/proof/harness/main.swift:289-395's `pinDefaults` — every key and value
# but `AgentServerEnabled` (the launch turns the server on) — plus each
# section's collapsed state. Booleans and numbers go as plist fragments, which
# the argument domain parses into typed values.
PINS = [(key, _plist(value)) for key, value in [
    ("ReelcutInspectorWidth", 304.0),
    ("ReelcutTimelineHeight", 300.0),
    ("ReelcutInspectorCollapsed", False),
    ("ReelcutTimelineTrackHeight", 1),
    ("ReelcutSnappingEnabled", True),
    ("ReelcutSafeGuidesVisible", False),
    ("ReelcutInspectorRescaleClips", False),
    ("ReelcutExportChoice", ""),
    ("ReelcutPreviewQuality", 0),
    ("NSWindow Frame ReelcutPreviewWindow", ""),
    ("ReelcutRecordingDisplay", 0),
    ("ReelcutRecordingMicrophone", ""),
    ("ReelcutRecordingSystemAudio", True),
    ("ReelcutRecordingShowClicks", False),
    ("ReelcutRecordingRate", 60),
    ("ReelcutRecordingSize", "nominal"),
    ("ReelcutCaptionEngine", "apple"),
    ("ReelcutAssemblyAIRegion", "us"),
    ("ReelcutCaptionStyle", "subtitles"),
    ("ReelcutAssistantModel", ""),
    ("ReelcutAssistantAutoCompact", True),
    ("ReelcutAssistantAutoCompactTokens", 300000),
    ("ReelcutAssistantClearToolResults", False),
    ("AppleShowScrollBars", "Always"),
]] + [(f"ReelcutInspectorSection.{sid}", _plist(collapsed))
      for sid, collapsed in sorted(SECTIONS.items())]

# A `static let …Key = "(Reelcut|RC)…"` literal no captured screen draws,
# and why. P2 requires every such literal in PINS or here.
NOT_SHOWN = {
    "ReelcutCompositorTiming": "a diagnostic switch for the compositor's timing log; nothing "
                               "on screen reads it",
    "RCFFmpegImport": "the opt-in ffmpeg rewrap policy, read at import; the fixtures import "
                      ".mov and .m4a files AVFoundation opens itself, and no screen shows it",
    "RCFFmpegPath": "the ffmpeg binary override, read only when a rewrap runs; none does",
    "RCRecordingFolder": "where a finished recording is written, read when one lands; the "
                         "recorder panel does not show it and nothing records",
    "RC_ASSEMBLYAI_KEY": "an environment variable, stripped from the child's environment at "
                         "launch",
    "RCDevAssistantSend": "a dev launch default that runs one assistant turn after launch "
                          "(DevAssistantLaunch.swift); no screen launches with it",
    "RCDevAssistantReport": "the report path beside RCDevAssistantSend; no screen launches "
                            "with it",
    "ReelcutScreenRecordingAsked": "whether the panel has put up the Screen Recording prompt "
                                   "once; read only by a press of Record, which no screen makes",
}

# Filed layout defects, each named by its issue, and deliberate findings,
# each named by why. A problem's text is `views[problem.view].text`; an
# `overhang` key must equal the problem's `detail.overhang` exactly.
KNOWN = {
    # MediaPane.bar's doc comment: the Media pane's section bars are pinned
    # 10 pt past each side of the inset so the rule spans the panel; 10b's
    # prose names the three per capture.
    "deliberate: MediaPane.bar's 10 pt overhang": {
        "kind": "outside_superview", "class": "BarView", "overhang": [10, 0, 10, 0]},
}

FIXTURES = {
    "empty": {"path": os.path.join(FIXTURE_DIR, "Empty.reelcut"), "clips": []},
    "demo": {"path": os.path.join(FIXTURE_DIR, "Demo.reelcut"),
             "clips": ["video", "text", "graphic", "shape", "tone"],
             "media": ["speech.mov", "toneA.m4a", "toneB.m4a"], "sound": ["video", "tone"]},
}
CANVAS = {"width": 960, "height": 540, "fps": [30, 1], "background": [0.0, 0.0, 0.0, 1.0],
          "fit_new_clips": True}
GRAPHIC_SOURCE = os.path.join(ROOT, "graphic", "tests", "graphics", "lower-third.js")


class LaunchError(RuntimeError):
    pass


class FixtureError(RuntimeError):
    pass


class ScreenError(RuntimeError):
    pass


# ---------------------------------------------------------------------------
# The instance.


def log_path(out, look=None):
    return os.path.join(out, "app.log" if look is None else f"app.{look}.log")


def launch(app, port, out, look=None):
    """Start `app` with the pins, and with `look` as `-RCDevAppearance`;
    answer the child and the port it bound. Raises LaunchError when no port
    shows in the log within 60 s."""
    os.makedirs(out, exist_ok=True)
    secrets = os.path.join(os.path.dirname(os.path.abspath(out)), "secrets")
    shutil.rmtree(secrets, ignore_errors=True)
    os.makedirs(secrets)
    if os.listdir(secrets):
        raise LaunchError(f"{secrets} is not empty after it was rebuilt")
    spend = os.path.join(os.path.dirname(os.path.abspath(out)), "spend")
    shutil.rmtree(spend, ignore_errors=True)
    if os.path.exists(spend):
        raise LaunchError(f"{spend} is still there after it was removed")
    argv = [os.path.join(app, "Contents", "MacOS", "Reelcut"),
            "-ApplePersistenceIgnoreState", "YES", "-AgentServerEnabled", "YES",
            "-RCSecretFolder", secrets, "-RCSpendFolder", spend,
            "-RCAssemblyAIEndpoint", "http://127.0.0.1:9",
            "-NSRecentDocumentsLimit", "0"]
    for key, value in PINS:
        argv += [f"-{key}", value]
    if look is not None:
        argv += [f"-{APPEARANCE_KEY}", look]
    env = bounded.child_env({"RC_AGENT_PORT": str(port)})
    env.pop("ANTHROPIC_API_KEY", None)
    log = log_path(out, look)
    handle = open(log, "w")
    try:
        child = subprocess.Popen(argv, env=env, stdin=subprocess.DEVNULL, stdout=handle,
                                 stderr=subprocess.STDOUT, start_new_session=True)
    finally:
        handle.close()
    deadline = time.monotonic() + 60
    pattern = re.compile(r"listening on http://127\.0\.0\.1:(\d+)/mcp")
    while time.monotonic() < deadline:
        if child.poll() is not None:
            raise LaunchError(f"the app exited ({child.returncode}) before binding a port; "
                              f"see {log}")
        found = pattern.findall(open(log, errors="replace").read())
        if found:
            return child, int(found[-1])
        time.sleep(0.25)
    stop(child)
    raise LaunchError(f"no port in {log} after 60 s")


def stop(child):
    """terminate(), then kill() after 10 s — that pid only."""
    if child.poll() is not None:
        return
    child.terminate()
    try:
        child.wait(timeout=10)
    except subprocess.TimeoutExpired:
        child.kill()
        child.wait()


def parity_lines(out, look=None):
    path = log_path(out, look)
    if not os.path.exists(path):
        return [f"no {os.path.basename(path)}"]
    return [line.rstrip() for line in open(path, errors="replace") if "Reelcut: " in line]


# ---------------------------------------------------------------------------
# Fixtures.


def _project(mcp, path):
    return mcp.call("get_project", project=path)["project"]


def _call(mcp, tool, project, **arguments):
    return mcp.call_with(tool, dict(arguments, project=project))


def build_fixture(mcp, name):
    """Write the package, open it, run the ops, save it. Answers the package
    path and clip name → id. Raises FixtureError."""
    spec = FIXTURES[name]
    for medium in spec.get("media", []):
        if not os.path.exists(os.path.join(MEDIA, medium)):
            raise FixtureError(
                f"tools/proof/media/{medium} is missing — make it with tools/proof/README.md's "
                "recipe (its \"Running one\" section)")
    path = spec["path"]
    os.makedirs(FIXTURE_DIR, exist_ok=True)
    v2_snapshot.write_package(path, dict(CANVAS), [])
    ids = {}
    try:
        mcp.call("open_project", path=path)
        if name == "demo":
            ids = _demo_ops(mcp, path)
        mcp.call("save_project", project=path)
    except ToolError as error:
        raise FixtureError(f"building {name}: {error}") from error
    return path, ids


def wait_for_peaks(mcp, path, clips, within=60):
    """Poll `detect_silence` in level mode (read-only: no undo step, no
    selection change) every 0.5 s until its answer names no `pending_peaks`,
    so the timeline draws every sound clip's waveform band. Answers
    `(polls, ms)`. Raises FixtureError after `within` s."""
    started = time.monotonic()
    polls = 0
    while True:
        polls += 1
        answer = mcp.call("detect_silence", project=path, clips=clips, mode="level")
        pending = answer.get("pending_peaks") if isinstance(answer, dict) else None
        if not pending:
            return polls, int((time.monotonic() - started) * 1000)
        if time.monotonic() - started > within:
            raise FixtureError(f"{len(pending)} media still pending_peaks after {within} s")
        time.sleep(0.5)


def _demo_ops(mcp, path):
    _call(mcp, "set_track", path, track=1, name="Video")
    for track in ("Titles", "Graphics", "Shapes", "Music"):
        _call(mcp, "add_track", path, name=track)
    tracks = {t["name"]: t["id"] for t in _project(mcp, path)["tracks"]}

    def clip_on(track):
        clips = [c for c in _project(mcp, path)["clips"] if c["track"] == tracks[track]]
        if len(clips) != 1:
            raise FixtureError(f"building demo: track {track} holds {len(clips)} clips, not 1")
        return clips[0]["id"]

    ids = {}
    video = _call(mcp, "import_media", path, path=os.path.join(MEDIA, "speech.mov"))
    _call(mcp, "add_clip", path, media=_media_id(video), track=tracks["Video"], at=0)
    ids["video"] = clip_on("Video")
    _call(mcp, "add_text_clip", path, track=tracks["Titles"], at=0, duration=5 * SECOND,
          text="Reelcut")
    ids["text"] = clip_on("Titles")
    with open(GRAPHIC_SOURCE) as handle:
        source = handle.read()
    wrote = _call(mcp, "write_graphic", path, name="lower-third", source=source)
    if isinstance(wrote, dict) and wrote.get("ok") is False:
        raise FixtureError(f"building demo: lower-third.js did not compile: {wrote}")
    deadline = time.monotonic() + 5
    while True:
        try:
            _call(mcp, "add_graphic_clip", path, name="lower-third", track=tracks["Graphics"],
                  at=0)
            break
        except ToolError:
            if time.monotonic() > deadline:
                raise
            time.sleep(0.2)
    ids["graphic"] = clip_on("Graphics")
    _call(mcp, "add_shape_clip", path, track=tracks["Shapes"], at=0, duration=5 * SECOND,
          shape="ellipse")
    ids["shape"] = clip_on("Shapes")
    tone = _call(mcp, "import_media", path, path=os.path.join(MEDIA, "toneA.m4a"))
    _call(mcp, "add_clip", path, media=_media_id(tone), track=tracks["Music"], at=0)
    ids["tone"] = clip_on("Music")
    # Imported last, so every earlier media and clip id is unchanged.
    _media_id(_call(mcp, "import_media", path, path=os.path.join(MEDIA, "toneB.m4a")))
    return ids


def _media_id(answer):
    media = answer.get("media") if isinstance(answer, dict) else None
    if isinstance(media, dict):
        return media["id"]
    if isinstance(media, int):
        return media
    raise FixtureError(f"import_media answered no media id: {answer}")


# ---------------------------------------------------------------------------
# Screen files.


def read_screen(path):
    """(front block, prose). Raises ScreenError("front block: …")."""
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()
    first = next((i for i, line in enumerate(lines) if line.strip()), None)
    if first is None or lines[first].strip() != "```json screen":
        raise ScreenError("front block: the first non-blank line is not ```json screen")
    end = next((i for i in range(first + 1, len(lines)) if lines[i] == "```"), None)
    if end is None:
        raise ScreenError("front block: no closing ``` line")
    try:
        front = json.loads("\n".join(lines[first + 1:end]))
    except json.JSONDecodeError as error:
        raise ScreenError(f"front block: not JSON — {error}") from error
    if not isinstance(front, dict):
        raise ScreenError("front block: not a JSON object")
    return front, "\n".join(lines[end + 1:]).strip()


def clip_names(value):
    """Every `$clip:<name>` anywhere in a JSON value."""
    if isinstance(value, str):
        return [value[6:]] if value.startswith("$clip:") else []
    if isinstance(value, list):
        return [n for item in value for n in clip_names(item)]
    if isinstance(value, dict):
        return [n for item in value.values() for n in clip_names(item)]
    return []


def substitute(value, ids):
    if isinstance(value, str) and value.startswith("$clip:"):
        return ids[value[6:]]
    if isinstance(value, list):
        return [substitute(item, ids) for item in value]
    if isinstance(value, dict):
        return {k: substitute(v, ids) for k, v in value.items()}
    return value


def validate(front, menu, last):
    """Every check a screen's front block must pass before anything runs.
    `menu` is the startup listing's leaves by path tuple; `last` whether this
    screen is the run's last. Raises ScreenError("front block: …")."""
    def bad(text):
        raise ScreenError(f"front block: {text}")

    unknown = sorted(set(front) - FRONT_KEYS)
    if unknown:
        bad(f"unknown key {unknown[0]!r}")
    if not isinstance(front.get("title"), str) or not front.get("title"):
        bad("title is required and must be a string")
    skip = front.get("skip")
    if skip is not None and not isinstance(skip, str):
        bad("skip must be a string (the reason)")
    if skip:
        return
    if "project" not in front:
        bad("project is required (null, \"empty\" or \"demo\")")
    project = front["project"]
    if project is not None and project not in FIXTURES:
        bad(f"project {project!r} is not null, \"empty\" or \"demo\"")
    known_clips = FIXTURES[project]["clips"] if project else []

    def steps(key):
        value = front.get(key, [])
        if not isinstance(value, list):
            bad(f"{key} must be a list")
        for n, step in enumerate(value):
            where = f"{key}[{n}]"
            if not isinstance(step, dict):
                bad(f"{where} is not an object")
            extra = sorted(set(step) - STEP_KEYS)
            if extra:
                bad(f"{where} has unknown key {extra[0]!r}")
            call = step.get("call")
            if call not in STEP_TOOLS:
                bad(f"{where} calls {call!r}, which is not one of {', '.join(STEP_TOOLS)}")
            args = step.get("args", {})
            if not isinstance(args, dict):
                bad(f"{where}.args is not an object")
            if "project" in args:
                bad(f"{where} names its own project; screens.py adds the fixture's")
            for name in clip_names(args):
                if name not in known_clips:
                    bad(f"{where} names $clip:{name}, which the "
                        f"{project or 'no-project'} fixture does not have")
            if "until_absent" in step:
                if not isinstance(step["until_absent"], str):
                    bad(f"{where}.until_absent must be a key name")
                if not isinstance(step.get("within"), (int, float)):
                    bad(f"{where}.until_absent needs within, in seconds")
            elif "within" in step:
                bad(f"{where}.within needs until_absent")
            if call == "perform_menu_item":
                path = args.get("path")
                if not isinstance(path, list) or not all(isinstance(t, str) for t in path):
                    bad(f"{where}.path must be a list of titles")
                leaf = menu.get(tuple(path))
                if leaf is None:
                    bad(f"{where}: {' ▸ '.join(path)} is not a menu leaf")
                if leaf.get("verdict") not in ("sheet", "window"):
                    bad(f"{where}: {' ▸ '.join(path)} has verdict {leaf.get('verdict')!r}, "
                        "not sheet or window")
                if leaf.get("selector") == "newRecording:" or path == NEW_RECORDING:
                    if path != NEW_RECORDING or key != "steps" or not last:
                        bad("New Recording… must be the last screen run")

    steps("steps")
    steps("after")
    # The recorder screen's instance is stopped straight after its captures,
    # so an `after` step there would run against a dead instance. It stays
    # last and stopped: an instance active when New Recording… runs still
    # gets a key panel with Record on Return (#137's decision), and the
    # script cannot hold its child inactive.
    if any(isinstance(s, dict) and s.get("call") == "perform_menu_item"
           and (s.get("args") or {}).get("path") == NEW_RECORDING
           for s in front.get("steps", []) or []) and front.get("after"):
        bad("the New Recording… screen cannot have after steps")
    captures = front.get("captures", [])
    if not isinstance(captures, list) or not captures:
        bad("captures must be a non-empty list")
    names = set()
    for n, cap in enumerate(captures):
        where = f"captures[{n}]"
        if not isinstance(cap, dict) or set(cap) - {"name", "window", "view"}:
            bad(f"{where} must be {{name, window, view?}}")
        name = cap.get("name")
        if not isinstance(name, str) or not re.fullmatch(r"[a-z0-9-]+", name) or name in names:
            bad(f"{where}.name must be a unique [a-z0-9-]+ name")
        names.add(name)
        if cap.get("window") not in WINDOWS:
            bad(f"{where}.window must be one of {', '.join(WINDOWS)}")
        if "view" in cap:
            if cap["window"] != "editor":
                bad(f"{where}.view is for window editor only")
            if cap["view"] not in REGIONS:
                bad(f"{where}.view must be one of {', '.join(REGIONS)}")
        if cap["window"] in ("editor", "sheet") and project is None:
            bad(f"{where}: window {cap['window']} needs a project")
    expect = front.get("expect", [])
    if not isinstance(expect, list):
        bad("expect must be a list")
    for n, item in enumerate(expect):
        where = f"expect[{n}]"
        if not isinstance(item, dict) or item.get("capture") not in names:
            bad(f"{where}.capture must name a capture")
        tests = set(item) - {"capture"}
        if len(tests) != 1 or not tests <= {"visible_text", "no_visible_text"}:
            bad(f"{where} needs exactly one of visible_text, no_visible_text")
        if not isinstance(item[tests.pop()], str):
            bad(f"{where}'s text must be a string")


# ---------------------------------------------------------------------------
# The run.


class Run:
    def __init__(self, args):
        self.args = args
        self.out = args.out
        self.rows = []
        self.states = {}
        self.new_problems = []
        self.results = []
        self.records = {}
        self.looks = {}
        self.recorder_ms = {}
        self.recorder_facts = {}
        self.recorder_before = {}
        self.child = None
        self.begin(None)

    def begin(self, look):
        """A fresh instance's state, for `look`."""
        self.look = look
        self.fixtures = {}
        self.blocked = None
        self.mcp = None
        self.p3 = None

    def score(self, rid, state, reason, extra=None):
        self.states[rid] = state
        self.rows.append(dict({"id": rid, "state": state, "reason": reason}, **(extra or {})))
        print(f"{rid} {state} — {reason}", flush=True)

    def call(self, tool, arguments):
        return self.mcp.call_with(tool, arguments)

    def snap(self, arguments):
        answer = v2_snapshot.snap(self.mcp, **arguments)
        v2_snapshot.captures.clear()
        answer.pop("_image", None)
        answer.pop("_bytes", None)
        return answer

    # -- P rows ------------------------------------------------------------

    def row_p1(self, port, look):
        self.begin(look)
        rid = f"P1.{look}"
        notes, ok = [], True
        try:
            self.child, bound = launch(self.args.app, port, self.out, look)
        except LaunchError as error:
            self.score(rid, "fail", f"launch: {error}")
            return f"launch: {error}"
        print(f"app: pid {self.child.pid} port {bound}", flush=True)
        try:
            self.mcp = MCP(bound, timeout=180)
            deadline = time.monotonic() + 15
            welcome = False
            while time.monotonic() < deadline and not welcome:
                listing = self.snap({})
                welcome = any(w.get("kind") == "welcome" for w in listing.get("windows", []))
                if not welcome:
                    time.sleep(0.25)
            tools = self.mcp.tools()
        except (OSError, RuntimeError) as error:
            self.score(rid, "fail", f"MCP: {error}")
            return f"MCP: {error}"
        alive = self.child.poll() is None
        parity = parity_lines(self.out, look)
        marker = dev_marker_count(log_path(self.out, look))
        missing = [n for n in DEV_TOOLS if n not in tools]
        ok = alive and welcome and not parity and not missing and marker == len(DEV_TOOLS)
        notes = [f"pid {self.child.pid} alive {alive}", f"port {bound}",
                 f"welcome {welcome}", f"`Reelcut: ` lines {len(parity)}",
                 f"dev tools missing {missing}", f"marker count {marker} (want {len(DEV_TOOLS)})"]
        self.score(rid, "pass" if ok else "fail", "; ".join(notes))
        return None if ok else "; ".join(notes)

    def row_p2(self):
        declared = set()
        literals = set()
        for name in sorted(os.listdir(SOURCES)):
            if not name.endswith(".swift"):
                continue
            text = open(os.path.join(SOURCES, name), encoding="utf-8").read()
            declared |= set(re.findall(r'id: "([a-z]+\.[a-zA-Z.]+)", title:', text))
            literals |= set(re.findall(r'static let \w*Key = "((?:Reelcut|RC)[^"]*)"', text))
        pinned = {key for key, _ in PINS} | {APPEARANCE_KEY}
        problems = []
        if declared != set(SECTIONS):
            problems.append(f"sections in app/Sources but not SECTIONS "
                            f"{sorted(declared - set(SECTIONS))}, in SECTIONS but not app/Sources "
                            f"{sorted(set(SECTIONS) - declared)}")
        uncovered = sorted(k for k in literals if k not in pinned and k not in NOT_SHOWN)
        if uncovered:
            problems.append(f"keys neither pinned nor in NOT_SHOWN {uncovered}")
        stale = sorted(k for k in NOT_SHOWN if k not in literals)
        if stale:
            problems.append(f"NOT_SHOWN keys that are no such literal {stale}")
        self.score("P2", "fail" if problems else "pass",
                   "; ".join(problems) or f"{len(declared)} section ids pinned; {len(literals)} "
                   f"key literals: {len(literals & pinned)} pinned (one, {APPEARANCE_KEY}, "
                   f"per look), {len(literals & set(NOT_SHOWN))} not shown")

    def row_p3(self):
        alive = self.child is not None and self.child.poll() is None
        parity = parity_lines(self.out, self.look)
        self.p3 = (alive and not parity,
                   f"child alive {alive}; `Reelcut: ` lines {len(parity)}"
                   + (f" ({parity[0][:120]})" if parity else ""))

    def finish(self):
        """P3's reading, then the child stopped, then P3 scored."""
        if self.p3 is None:
            self.row_p3()
        if self.child is not None:
            stop(self.child)
        ok, reason = self.p3
        self.score(f"P3.{self.look}", "pass" if ok else "fail", reason)

    # -- screens -----------------------------------------------------------

    def fixture(self, name):
        if name not in self.fixtures:
            try:
                path, ids = build_fixture(self.mcp, name)
                sound = FIXTURES[name].get("sound")
                if sound:
                    polls, ms = wait_for_peaks(self.mcp, path, [ids[c] for c in sound])
                    print(f"fixture {name}: peaks cached after {polls} poll(s), {ms} ms",
                          flush=True)
                self.fixtures[name] = ("ok", (path, ids))
            except FixtureError as error:
                self.fixtures[name] = ("fail", str(error))
            except (ToolError, OSError, RuntimeError) as error:
                self.fixtures[name] = ("fail", f"building {name}: {error}")
        state, value = self.fixtures[name]
        if state != "ok":
            raise ScreenError(value)
        return value

    def run_steps(self, steps, path, ids):
        for step in steps:
            args = substitute(step.get("args", {}), ids)
            if path:
                args["project"] = path
            answer = self.call(step["call"], args)
            if "until_absent" in step:
                deadline = time.monotonic() + step["within"]
                while isinstance(answer, dict) and step["until_absent"] in answer:
                    if time.monotonic() > deadline:
                        raise ScreenError(f"{step['call']} still answered "
                                          f"{step['until_absent']} after {step['within']} s")
                    time.sleep(0.5)
                    answer = self.call(step["call"], args)
            yield step, answer

    def run_screen(self, sid, front, prose):
        project = front["project"]
        path, ids = (None, {})
        if project:
            path, ids = self.fixture(project)
            self.call("open_project", {"path": path})
        if any(isinstance(s, dict) and s.get("call") == "perform_menu_item"
               and (s.get("args") or {}).get("path") == NEW_RECORDING
               for s in front.get("steps", []) or []):
            self.recorder_before[self.look] = self.snap({}).get("active")
        performed_recorder = None
        for step, answer in self.run_steps(front.get("steps", []), path, ids):
            if step["call"] == "perform_menu_item" and step["args"].get("path") == NEW_RECORDING:
                performed_recorder = time.monotonic()
        captures = []
        look = self.look
        try:
            for cap in front["captures"]:
                base = f"{sid}.{cap['name']}.{look}"
                arguments = {"window": cap["window"],
                             "path": os.path.join(self.out, base + ".png")}
                if "view" in cap:
                    arguments["view"] = cap["view"]
                if path and cap["window"] in ("editor", "sheet"):
                    arguments["project"] = path
                answer = self.snap(arguments)
                captures.append((cap, look, answer))
        except BaseException:
            # The recorder panel is key when Reelcut was active before it, and
            # its Return is Record: a failed capture stops the instance NOW,
            # not at finish(). The script cannot hold its child inactive.
            if performed_recorder is not None:
                stop(self.child)
                self.recorder_ms[look] = int(round((time.monotonic() - performed_recorder) * 1000))
            raise
        if performed_recorder is not None:
            self.recorder_facts[look] = [a.get("window_facts") for _, _, a in captures]
            self.row_p3()
            stop(self.child)
            self.recorder_ms[look] = int(round((time.monotonic() - performed_recorder) * 1000))
        wrong = [f"{cap['name']} answered {a.get('appearance')!r}" for cap, _, a in captures
                 if a.get("appearance") != look]
        if wrong:
            raise ScreenError(f"the instance was launched {look}, but "
                              + "; ".join(wrong))
        else:
            list(self.run_steps(front.get("after", []), path, ids))
        return captures

    def check_expect(self, front, captures):
        for item in front.get("expect", []):
            for cap, look, answer in captures:
                if cap["name"] != item["capture"]:
                    continue
                views = load_layout(answer)["views"]
                visible = {v.get("text") for v in views if not v.get("hidden")}
                if "visible_text" in item and item["visible_text"] not in visible:
                    return (f"expect: no visible view reads {item['visible_text']!r} in "
                            f"{cap['name']} ({look})")
                if "no_visible_text" in item and item["no_visible_text"] in visible:
                    return (f"expect: a visible view reads {item['no_visible_text']!r} in "
                            f"{cap['name']} ({look})")
        return None

    def sheet_check(self, sid):
        """After a screen: an attached sheet fails it and is cancelled."""
        if self.child is None or self.child.poll() is not None:
            return None
        listing = self.snap({})
        for window in listing.get("windows", []):
            sheet = window.get("sheet")
            if window.get("kind") == "editor" and sheet:
                try:
                    self.call("cancel_sheet", {"project": window.get("project")})
                except ToolError:
                    pass
                again = self.snap({})
                if any(w.get("kind") == "editor" and w.get("sheet")
                       for w in again.get("windows", [])):
                    self.blocked = f"a sheet from {sid} could not be closed"
                return f"left a sheet attached: {sheet.get('class')}"
        return None

    def classify(self, sid, captures):
        rows = []
        for cap, look, answer in captures:
            layout = load_layout(answer)
            views = layout["views"]
            known, new = [], []
            for problem in layout.get("problems", []):
                text = views[problem["view"]].get("text") if problem["view"] < len(views) else None
                issue = next((i for i, k in KNOWN.items() if matches(k, problem, text)), None)
                entry = {"kind": problem["kind"], "class": problem["class"], "text": text,
                         "frame": problem["frame"], "detail": problem.get("detail")}
                if issue:
                    known.append(dict(entry, issue=issue))
                else:
                    new.append(entry)
                    self.new_problems.append((f"{sid}.{cap['name']}.{look}", entry))
            png = answer["path"]
            rows.append({
                "name": cap["name"], "look": look, "window": cap["window"],
                "view": cap.get("view"), "png": os.path.basename(png),
                "sha256": sha256_file(png) if os.path.exists(png) else None,
                "scale": answer.get("scale"), "points": answer.get("points"),
                "width_px": answer.get("width_px"), "height_px": answer.get("height_px"),
                "window_facts": answer.get("window_facts"), "known": known, "new": new,
                "private_problems": len(layout.get("private_problems", [])),
            })
        return rows

    def screen(self, file, sid, menu, last, p1_error):
        """This instance's look of one screen, kept in `self.looks[sid]` and
        printed as a progress line; `conclude` scores the screen."""
        record = self.records.get(sid)
        if record is None:
            record = {"id": sid, "file": os.path.relpath(file, ROOT), "title": sid, "prose": "",
                      "captures": []}
            self.records[sid] = record
            self.results.append(record)

        def done(state, reason, captures=()):
            self.looks.setdefault(sid, {})[self.look] = (state, reason, list(captures))
            print(f"  {sid} {self.look}: {state} — {reason}", flush=True)

        try:
            front, prose = read_screen(file)
            record["title"] = front.get("title") if isinstance(front.get("title"), str) else sid
            record["prose"] = prose
            validate(front, menu, last)
        except ScreenError as error:
            return done("fail", str(error))
        if front.get("skip"):
            return done("skip", front["skip"])
        if p1_error:
            return done("fail", f"P1.{self.look}: {p1_error}")
        if self.blocked:
            return done("fail", self.blocked)
        if self.child is None or self.child.poll() is not None:
            return done("fail", "the instance is not running")
        failure = None
        captures = []
        try:
            captures = self.run_screen(sid, front, prose)
            failure = self.check_expect(front, captures)
        except (ScreenError, ToolError, OSError, RuntimeError, KeyError, ValueError) as error:
            failure = str(error) or type(error).__name__
        try:
            sheet = self.sheet_check(sid)
        except (ToolError, OSError, RuntimeError) as error:
            sheet = f"listing the windows after the screen: {error}"
        failure = failure or sheet
        done("fail" if failure else "pass", failure or f"{len(captures)} captures", captures)

    def conclude(self, sid):
        """Both looks of one screen, scored as one row. A failed `expect` in
        either look deletes every capture of the screen."""
        record = self.records[sid]
        looks = self.looks.get(sid, {})
        results = [(look, looks.get(look, ("fail", "never run", []))) for look in LOOKS]
        failed = [(look, reason) for look, (state, reason, _) in results if state == "fail"]
        captures = [c for _, (_, _, caps) in results for c in caps]
        if any(reason.startswith("expect:") for _, reason in failed):
            for _, _, answer in captures:
                for key in ("path", "layout_path"):
                    if answer.get(key) and os.path.exists(answer[key]):
                        os.remove(answer[key])
            captures = []
        names = []
        for cap, _, _ in captures:
            if cap["name"] not in names:
                names.append(cap["name"])
        captures.sort(key=lambda c: (names.index(c[0]["name"]), LOOKS.index(c[1])))
        record["captures"] = self.classify(sid, captures) if captures else []
        if failed:
            reasons = {reason for _, reason in failed}
            if len(reasons) == 1 and len(failed) == len(LOOKS):
                reason = reasons.pop()
            else:
                reason = "; ".join(f"{look}: {reason}" for look, reason in failed)
            record["reason"] = reason
            self.score(sid, "fail", reason)
        elif all(state == "skip" for _, (state, _, _) in results):
            record["reason"] = results[0][1][1]
            self.score(sid, "skip", record["reason"])
        else:
            shots = len(record["captures"])
            news = sum(len(c["new"]) for c in record["captures"])
            record["reason"] = f"{shots} captures, {news} new problems"
            self.score(sid, "pass", record["reason"])
        record["state"] = self.states[sid]


def matches(known, problem, text):
    if problem.get("kind") != known["kind"] or problem.get("class") != known["class"]:
        return False
    if "overhang" in known and (problem.get("detail") or {}).get("overhang") != known["overhang"]:
        return False
    prefix = known.get("text_prefix")
    return prefix is None or (text or "").startswith(prefix)


def load_layout(answer):
    path = answer.get("layout_path")
    if not path:
        raise ScreenError(f"snapshot_ui wrote no layout dump for {answer.get('path')}")
    with open(path) as handle:
        return json.load(handle)


def sha256_file(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


# ---------------------------------------------------------------------------
# Output.


def write_markdown(run, scores, digest):
    app = run.args.app
    binary = os.path.join(app, "Contents", "MacOS", "Reelcut")
    mtime = (datetime.datetime.fromtimestamp(os.path.getmtime(binary)).isoformat(timespec="seconds")
             if os.path.exists(binary) else "missing")
    lines = [
        "# Reelcut screens",
        "",
        f"- Captured: {datetime.datetime.now().isoformat(timespec='seconds')}",
        f"- App: `{app}` (binary modified {mtime})",
        f"- Scores: {scores}",
        f"- Digest: `{digest}`",
        f"- New layout problems: {len(run.new_problems)}",
        "",
    ]
    for record in run.results:
        lines += [f"## {record['title']}", "",
                  f"`{record['id']}` — {run.states.get(record['id'], 'fail')}", ""]
        if record.get("prose"):
            lines += [record["prose"], ""]
        if run.states.get(record["id"]) != "pass":
            lines += [f"**Not captured:** {record.get('reason', '')}", ""]
            continue
        for cap in record["captures"]:
            lines += [f"### {cap['name']} — {cap['look']}", "",
                      f"![{record['id']} {cap['name']} {cap['look']}]({cap['png']})", "",
                      f"Scale {cap['scale']}, {cap['points'][0]:g} × {cap['points'][1]:g} pt "
                      f"({cap['width_px']} × {cap['height_px']} px)."]
            if cap["known"]:
                lines.append("Known layout problems: " + "; ".join(
                    f"{p['issue']} {p['kind']} {p['class']} {p['text']!r}" for p in cap["known"]))
            if cap["new"]:
                lines.append("**New layout problems:** " + "; ".join(
                    f"{p['kind']} {p['class']} {p['text']!r} at {p['frame']}" for p in cap["new"]))
            if not cap["known"] and not cap["new"]:
                lines.append("No layout problems.")
            lines.append("")
    with open(os.path.join(run.out, "screens.md"), "w") as handle:
        handle.write("\n".join(lines))


def compare(out, earlier):
    """Per PNG in either run: same, differs (n px in a box), size differs, or
    only in one run. Not scored."""
    ours = {n for n in os.listdir(out) if n.endswith(".png")}
    theirs = {n for n in os.listdir(earlier) if n.endswith(".png")} if os.path.isdir(earlier) \
        else set()
    same = 0
    names = sorted(ours | theirs)
    for name in names:
        if name not in ours or name not in theirs:
            print(f"{name}: only in one run")
            continue
        a, b = os.path.join(earlier, name), os.path.join(out, name)
        if open(a, "rb").read() == open(b, "rb").read():
            same += 1
            print(f"{name}: same")
            continue
        if v2_snapshot.png_size(a) != v2_snapshot.png_size(b):
            print(f"{name}: size differs ({v2_snapshot.png_size(a)} vs {v2_snapshot.png_size(b)})")
            continue
        pixels = v2_snapshot.differing(v2_snapshot.decode_png(a), v2_snapshot.decode_png(b))
        if not pixels:
            same += 1
            print(f"{name}: same (pixels; the files differ)")
            continue
        xs = [x for x, _ in pixels]
        ys = [y for _, y in pixels]
        print(f"{name}: differs: {len(pixels)} px in [{min(xs)},{min(ys)},{max(xs)},{max(ys)}]")
    print(f"compare: {same}/{len(names)} byte-identical")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=4871)
    parser.add_argument("--app", default=DEFAULT_APP)
    parser.add_argument("--screens", default=DEFAULT_SCREENS)
    parser.add_argument("--out")
    parser.add_argument("--only")
    parser.add_argument("--compare")
    args = parser.parse_args()
    args.app = os.path.abspath(args.app)
    if not args.out:
        args.out = os.path.join(WORK, datetime.datetime.now().strftime("%Y-%m-%d-%H%M%S"))
    args.out = os.path.abspath(args.out)
    os.makedirs(args.out, exist_ok=True)

    files = sorted(f for f in os.listdir(args.screens)
                   if f.endswith(".md") and f != "README.md")
    if args.only:
        wanted = [s.strip() for s in args.only.split(",") if s.strip()]
        files = [f for f in files if f[:-3] in wanted]
    ids = [f[:-3] for f in files]

    run = Run(args)
    exit_code = 1
    try:
        run.row_p2()
        for look in LOOKS:
            p1_error = run.row_p1(args.port, look)
            menu = {}
            if not p1_error:
                try:
                    listing = run.call("perform_menu_item", {})
                    menu = {tuple(item["path"]): item for item in listing["items"]}
                except (ToolError, OSError, RuntimeError) as error:
                    p1_error = f"the startup menu listing: {error}"
            for n, (file, sid) in enumerate(zip(files, ids)):
                run.screen(os.path.join(args.screens, file), sid, menu, n == len(files) - 1,
                           p1_error)
            run.finish()
        for sid in ids:
            run.conclude(sid)
    finally:
        if run.child is not None:
            stop(run.child)

    print(f"new problems: {len(run.new_problems)}")
    for where, problem in run.new_problems:
        print(f"  {where}: {problem['kind']} {problem['class']} {problem['text']!r} "
              f"at {problem['frame']} {problem.get('detail')}")
    for look in LOOKS:
        if look in run.recorder_ms:
            print(f"recorder panel up ({look}): {run.recorder_ms[look]} ms; active before New "
                  f"Recording… {run.recorder_before.get(look)}")
            for facts in run.recorder_facts.get(look) or []:
                print(f"  recorder capture: key {facts.get('key')} active {facts.get('active')} "
                      f"occluded {facts.get('occluded')}")
        else:
            print(f"recorder panel up ({look}): not shown (no New Recording… screen ran)")
    order = ([f"P1.{look}" for look in LOOKS] + ["P2"] + ids
             + [f"P3.{look}" for look in LOOKS])
    counts = {s: sum(1 for rid in order if run.states.get(rid, "fail") == s)
              for s in ("pass", "fail", "skip")}
    scores = (f"{counts['pass']} pass, {counts['fail']} fail, {counts['skip']} skip of "
              f"{len(order)}")
    digest = hashlib.sha256("\n".join(sorted(f"{rid}={run.states.get(rid, 'fail')}"
                                             for rid in order)).encode()).hexdigest()
    print(f"scores: {scores}")
    print(f"digest: {digest}")
    print(f"out: {args.out}")
    write_markdown(run, scores, digest)
    with open(os.path.join(args.out, "results.json"), "w") as handle:
        json.dump({"rows": run.rows, "scores": scores, "digest": digest,
                   "recorder_panel_up_ms": run.recorder_ms,
                   "new_problems": [dict(p, where=w) for w, p in run.new_problems],
                   "screens": run.results}, handle, indent=1)
    if args.compare:
        compare(args.out, os.path.abspath(args.compare))
    exit_code = 1 if counts["fail"] else 0
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
