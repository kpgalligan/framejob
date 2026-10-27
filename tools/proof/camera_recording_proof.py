#!/usr/bin/env python3
"""Camera recording CR1b (spec §11 CAM-4) — `record_screen {source: "camera", camera?}`, driven
against a running instance over MCP, with CR2a's `camera_format` (CAM-6) — and CR1c's recorder
panel (CAM-5), seen through `snapshot_ui`, in `recording_proof.py`'s shape: two tiers, the split
between them the whole design. A host with no camera, or whose terminal holds no Camera grant,
still measures the catalog, every refusal and their order; the recording itself is measured
only where one can be made, and a run that could not make one SAYS so with a count.

    python3 tools/proof/camera_recording_proof.py <dir>/agent.sock [log path]

The instance at the socket is the one `RC_PROOF_APP` chose (`proof_app.py launch`, Debug by
default; `mcp.MCP` refuses a stale one). It was started from the shell, so it runs under the
TERMINAL's Camera and Microphone grants (road map 3 R0 q1), never the app icon's, and nothing
here asks for either. Every file is written under `tools/proof/work/camera-recording-proof/`
and removed at the end; the one document it makes is closed again, and so is the new project
the last row opens.

**Headless** (always):
* Catalog: `record_screen` declares its fourteen arguments plus `project`, `camera` and
  `camera_format` strings;
  `source`'s enum is `["screen", "voice_over", "camera"]`; the description names
  `source: "camera"`, `Camera Recording`, `camera.problem` and the default camera; the log
  holds no `Frame Job: ` parity line.
* Refusals, each the EXACT sentence, together leaving `get_project` byte-identical with no
  undo step; the ORDER by combined calls: `seconds: 0` beats `source: "x"`; `source: "x"`
  lists `screen, voice_over, camera`; one stranger, then all seven in
  `cameraRefusedArguments` order; `{size: null}` admitted (the project sentence answers);
  `camera` with screen, and with voice_over beating `display`; a stranger beats
  `project: "/nowhere"`, and `{source: camera, project: "/nowhere"}` is the project sentence;
  `microphone: true` the Microphone sentence without the grant, else the project sentence;
  an unknown `camera` against the proof's own document is the lookup's sentence (every camera
  listed as `Name (id)`, or "No camera is connected."), whatever the Camera grant says.
  CR2a: `camera_format` with screen (exact); `camera_format: 5` (`stringArg`'s sentence);
  `{source: camera, camera_format: "0x0"}` the format sentence for the default camera (its
  formats listed, `best` first) when a camera is connected, else "No camera is connected.";
  an unknown camera with `camera_format: "0x0"` the camera's sentence — the lookup first.

**Detection**: `{seconds: 2, source: camera, place: false, path}` against that document. The
Camera sentence or "No camera is connected." skips the granted tier with its count; a result
runs it; any other refusal is a FAIL.

**Granted**: the detection's answer (the dated name, `camera.{name, id, format}`, the file's
size the format's, 1.5–3.5 s, `has_audio` false, one segment never paused, stopped by the
tool, `mic_offset` 0, `media` and no `clip`); `camera: <id>` and `camera: <NAME upper-cased>`
naming the same camera; `microphone: true` with place (skipped with its count without the
Microphone grant): the picture at the playhead, the voice on the Microphone track, their starts
`mic_offset` apart within half a frame, one undo taking both and leaving the files; and, with
no project open once its own document is closed (else skipped by name), `landed: new_project`
with the canvas the file's size at the format's rate, rounded. CR2a: from the format sentence's
list, the first spelling that is not `best` and differs from the detection's `camera.format`,
recorded for 2 s with `camera_format`: the answer's `camera.format` and the file's size are that
row's (skipped by name when the camera lists no such row).

**The panel** (CR1c, run LAST, after its own document is closed): `perform_menu_item ["File",
"New Recording…"]` answers; `snapshot_ui {window: "recorder"}`'s layout dump lists views whose
texts are `Camera:` and `Format:` (CR2a) and reports no layout problem; the log still holds no `Frame Job: ` line. Its
rows only show the panel: no row is changed, so no defaults key moves. The panel is left up;
the instance is stopped by its pid.

Exit 0 when nothing failed (a skip is not a failure; it is printed with its count), 1 when a
check failed.
"""

import json
import os
import re
import shutil
import sys
import time

from mcp import MCP, ToolError, log_beside, target

POSITIONAL = [arg for arg in sys.argv[1:] if not arg.startswith("--")]
SOCKET = target([sys.argv[0]] + POSITIONAL)
LOG = POSITIONAL[1] if len(POSITIONAL) > 1 else log_beside(SOCKET)

HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work", "camera-recording-proof")
RUN = os.path.join(WORK, f"{os.getpid()}-files")
DOCS = os.path.join(WORK, f"{os.getpid()}-docs")

SEC = 600_000
RECORD_PROPERTIES = {
    "display", "window", "seconds", "microphone", "system_audio", "show_clicks", "rate",
    "size", "place", "path", "include_framejob_windows", "source", "camera", "camera_format",
}
CAMERA_STRANGERS = ["display", "window", "system_audio", "show_clicks", "size",
                    "include_framejob_windows", "rate"]
STRANGER_TAIL = (" cannot be given — a camera recording records the camera alone, at the "
                 "camera's own format.")
ELSEWHERE_TAIL = " cannot be given — only source camera records a camera."
NO_OPEN_PROJECT = re.compile(
    r"^No open project is at (.+)\. get_project reports the open project's path; "
    r"open_project opens another\.$")
NO_PROJECT = "No project is open."
MIC_SENTENCE = re.compile(r"^The microphone is not granted to Frame Job \(status: (\w+)\)\. ")
CAMERA_GRANT = "The camera is not granted to Frame Job (status: "
NO_CAMERA = "No camera is connected."
NO_SUCH_CAMERA = re.compile(
    r"^No connected camera is named or has the id (.+?)\. The cameras connected are (.+)\.$")
NO_SUCH_FORMAT = re.compile(
    r"^The camera (.+) has no format 0x0\. Its formats are best((?:, [^,]+)*)\.$")
NOTHING_TO_UNDO = "There is nothing to undo."
CAMERA_NAME = re.compile(
    r"^Camera Recording \d{4}-\d{2}-\d{2} at \d{2}\.\d{2}\.\d{2}( \(\d+\))?\.mov$")
FORMAT = re.compile(r"^(\d+)x(\d+)@([\d.]+)$")
PARITY = "Frame Job: "

DETECTION_CHECKS = 7
CHOICE_CHECKS = 2
MIC_CHECKS = 4
NEW_PROJECT_CHECKS = 2
FORMAT_CHECKS = 2

checks = 0
failures = []
skipped = []
host = {"microphone": False, "formats": []}


def check(ok_, what):
    global checks
    checks += 1
    print(f"  {'ok  ' if ok_ else 'FAIL'} {what}")
    if not ok_:
        failures.append(what)


def skip(what, count):
    print(f"  SKIP {what} — {count} checks not run")
    skipped.append((what, count))


def section(name, run, *args):
    """One section; a raise scores ONE failure and the run goes on."""
    global checks
    print(f"\n{name}")
    try:
        run(*args)
    except Exception as error:  # noqa: BLE001 — the point is to keep scoring
        checks += 1
        what = f"section {name.split(' ')[0]} ran to the end (raised {error!r})"
        print(f"  FAIL {what}")
        failures.append(what)


def attempt(mcp, args):
    """(answer, None) or (None, the refusal without the tool's prefix)."""
    try:
        return mcp.call_with("record_screen", args), None
    except ToolError as error:
        text = str(error)
        prefix = "record_screen: "
        return None, (text[len(prefix):] if text.startswith(prefix) else text)


def refusal(mcp, args):
    return attempt(mcp, args)[1]


def state(mcp, document=None):
    return mcp.call_with("get_project", {"project": document} if document else {})


def fingerprint(mcp, document):
    return json.dumps(state(mcp, document), sort_keys=True)


def project(mcp, document):
    return state(mcp, document)["project"]


def close(mcp, document):
    try:
        mcp.call_with("close_project", {"project": document, "discard": True})
    except ToolError as error:
        print(f"  (could not close {document}: {error})")


def format_size(fmt):
    m = FORMAT.match(fmt or "")
    return (int(m[1]), int(m[2]), float(m[3])) if m else None


# ---- headless -------------------------------------------------------------------------


def catalog_part(mcp):
    tool = mcp.schemas().get("record_screen") or {}
    schema = tool.get("inputSchema") or {}
    properties = schema.get("properties") or {}
    declared = set(properties)
    check(declared == RECORD_PROPERTIES | {"project"},
          f"record_screen declares its fourteen arguments plus project: "
          f"{sorted(declared - RECORD_PROPERTIES - {'project'})} unexpected, "
          f"{sorted((RECORD_PROPERTIES | {'project'}) - declared)} missing")
    check(properties.get("camera", {}).get("type") == "string",
          f"camera is declared a string: {properties.get('camera', {}).get('type')!r}")
    check(properties.get("camera_format", {}).get("type") == "string",
          f"camera_format is declared a string: "
          f"{properties.get('camera_format', {}).get('type')!r}")
    check(properties.get("source", {}).get("enum") == ["screen", "voice_over", "camera"],
          f"source's enum has the three members: {properties.get('source', {}).get('enum')}")
    description = tool.get("description") or ""
    for phrase in ('source: "camera"', "Camera Recording", "camera.problem", "the default camera"):
        check(phrase in description, f"the description names {phrase!r}")
    lines = None
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8", errors="replace") as handle:
            lines = [line.rstrip() for line in handle if PARITY in line]
    check(lines == [], f"the instance's log ({LOG}) holds no {PARITY!r} parity line: {lines}")


def refusal_part(mcp, document):
    before = fingerprint(mcp, document)

    def refused(args, expected, why):
        message = refusal(mcp, dict(args, project=args.get("project", document)))
        check(message == expected, f"{json.dumps(args)} → {why}: {message!r}")

    nowhere = "/nowhere/x.framejob"
    refused({"seconds": 0, "source": "x"}, "seconds must be 1…600 (got 0).",
            "ORDER: seconds 0 beats source x")
    refused({"seconds": 2, "source": "x"},
            'source must be one of screen, voice_over, camera (got "x").',
            "source x is refused listing all three")
    refused({"seconds": 2, "source": "camera", "rate": 30},
            "With source camera, rate" + STRANGER_TAIL, "one stranger is refused by name")
    refused({"seconds": 2, "source": "camera", "rate": 30, "include_framejob_windows": False,
             "size": "best", "show_clicks": False, "system_audio": False, "window": 5,
             "display": 0},
            "With source camera, " + ", ".join(CAMERA_STRANGERS) + STRANGER_TAIL,
            "all seven are refused together, in cameraRefusedArguments order")
    message = refusal(mcp, {"seconds": 2, "source": "camera", "size": None, "project": nowhere})
    check(message is not None and NO_OPEN_PROJECT.match(message) is not None,
          f"{{size: null}} is not given — the project sentence answers: {message!r}")
    refused({"seconds": 2, "camera": "FaceTime HD Camera"},
            "With source screen, camera" + ELSEWHERE_TAIL, "camera with the default screen source")
    refused({"seconds": 2, "source": "voice_over", "camera": "X", "display": 0},
            "With source voice_over, camera" + ELSEWHERE_TAIL,
            "ORDER: camera with voice_over beats the voice-over's display")
    refused({"seconds": 2, "source": "camera", "display": 0, "project": nowhere},
            "With source camera, display" + STRANGER_TAIL,
            "ORDER: a stranger beats a project naming nothing")
    message = refusal(mcp, {"seconds": 2, "source": "camera", "project": nowhere})
    check(message is not None and NO_OPEN_PROJECT.match(message) is not None
          and nowhere in message,
          f"{{source: camera, project: /nowhere}} → the project sentence: {message!r}")
    message = refusal(mcp, {"seconds": 2, "source": "camera", "microphone": True,
                            "project": nowhere})
    named = MIC_SENTENCE.match(message or "")
    host["microphone"] = message is not None and NO_OPEN_PROJECT.match(message) is not None
    check(named is not None or host["microphone"],
          "microphone: true → the Microphone sentence without the grant, else the project "
          f"sentence (the grant {'held' if host['microphone'] else 'absent'}): {message!r}")
    wanted = f"No Such Camera {os.getpid()}"
    message = refusal(mcp, {"seconds": 2, "source": "camera", "camera": wanted,
                            "project": document})
    listed = NO_SUCH_CAMERA.match(message or "")
    entries = listed[2].split(", ") if listed else []
    check(message == NO_CAMERA
          or (listed is not None and listed[1] == wanted and entries
              and all(re.match(r"^.+ \([^()]+\)$", entry) for entry in entries)),
          f"an unknown camera is the LOOKUP's sentence, each camera as Name (id), whatever the "
          f"Camera grant says: {message!r}")
    format_refusals(mcp, document, refused)
    after = fingerprint(mcp, document)
    undone = None
    try:
        mcp.call_with("undo", {"project": document})
    except ToolError as error:
        undone = str(error)
    check(after == before and undone is not None and NOTHING_TO_UNDO in undone,
          f"the refusals left get_project byte-identical and pushed no undo step: {undone!r}")


def format_refusals(mcp, document, refused):
    """CR2a (CAM-6 (6)): `camera_format` refused with screen and as a number, the format sentence
    for the default camera after the lookup, and the lookup's sentence before it."""
    refused({"seconds": 2, "camera_format": "1920x1080@30"},
            "With source screen, camera_format" + ELSEWHERE_TAIL,
            "camera_format with the default screen source")
    refused({"seconds": 2, "source": "camera", "camera_format": 5},
            "camera_format must be a string.", "camera_format: 5 is stringArg's refusal")
    message = refusal(mcp, {"seconds": 2, "source": "camera", "camera_format": "0x0",
                            "project": document})
    listed = NO_SUCH_FORMAT.match(message or "")
    host["formats"] = [f for f in (listed[2] if listed else "").split(", ") if f]
    check(message == NO_CAMERA or (listed is not None and host["formats"]
                                   and all(FORMAT.match(f) for f in host["formats"])),
          f"camera_format 0x0 is the format sentence for the default camera, its formats "
          f"listed after best (or no camera): {message!r}")
    wanted = f"No Such Camera {os.getpid()}"
    message = refusal(mcp, {"seconds": 2, "source": "camera", "camera": wanted,
                            "camera_format": "0x0", "project": document})
    check(message == NO_CAMERA or (NO_SUCH_CAMERA.match(message or "") is not None
                                   and wanted in message),
          f"an unknown camera with camera_format 0x0 is the CAMERA's sentence — the lookup "
          f"first: {message!r}")


# ---- detection and the granted tier ---------------------------------------------------


def granted_tier(mcp, document):
    total = DETECTION_CHECKS + CHOICE_CHECKS + FORMAT_CHECKS + MIC_CHECKS + NEW_PROJECT_CHECKS
    answer, message = attempt(mcp, {"seconds": 2, "source": "camera", "place": False,
                                    "path": RUN, "project": document})
    if message is not None and (message.startswith(CAMERA_GRANT) or message == NO_CAMERA):
        skip(f"the granted tier: {message[:120]}", total)
        return
    check(answer is not None and message is None,
          f"the detection call recorded (any refusal but the Camera grant's or no camera is a "
          f"failure): {message!r}")
    if answer is None:
        skip("the granted tier's rows: the detection call failed", total)
        return
    camera = detection_rows(mcp, answer, document)
    choice_rows(mcp, camera, document)
    format_rows(mcp, camera, document)
    if host["microphone"]:
        microphone_rows(mcp, document)
    else:
        skip("the microphone rows: the Microphone grant is not held here", MIC_CHECKS)
    close(mcp, document)
    new_project_rows(mcp)


def detection_rows(mcp, answer, document):
    path = answer.get("path") or ""
    check(os.path.dirname(path) == RUN and CAMERA_NAME.match(os.path.basename(path)) is not None
          and os.path.exists(path),
          f"the file is a dated Camera Recording <date> at <time>.mov in the folder, on disk: "
          f"{path!r}")
    camera = answer.get("camera") or {}
    size = format_size(camera.get("format"))
    check(all(isinstance(camera.get(k), str) and camera.get(k) for k in ("name", "id", "format"))
          and size is not None,
          f"camera carries name, id and format: {camera}")
    check(size is not None and (answer.get("width"), answer.get("height")) == size[:2],
          f"the file's size is the format's: {answer.get('width')}×{answer.get('height')} for "
          f"{camera.get('format')}")
    duration = answer.get("duration") or 0
    check(1.5 * SEC <= duration <= 3.5 * SEC,
          f"a 2 s span records 1.5–3.5 s of picture: {duration / SEC:.3f} s")
    check(answer.get("has_audio") is False and answer.get("audio_tracks") == 0,
          f"has_audio false, audio_tracks 0 — the movie holds no sound: "
          f"{answer.get('has_audio')}, {answer.get('audio_tracks')}")
    check(len(answer.get("segments") or []) == 1 and answer.get("pauses") == 0
          and answer.get("stopped_by") == "stopped" and answer.get("mic_offset") == 0,
          f"one segment, pauses 0, stopped_by stopped, mic_offset 0: "
          f"{len(answer.get('segments') or [])}, {answer.get('pauses')}, "
          f"{answer.get('stopped_by')}, {answer.get('mic_offset')}")
    listed = {m["id"]: m for m in project(mcp, document)["media"]}
    check(answer.get("landed") == "document" and answer.get("media") in listed
          and "clip" not in answer,
          f"landed in the document as media with no clip (place: false): "
          f"{answer.get('landed')}, media {answer.get('media')}, clip {answer.get('clip')}")
    return camera


def choice_rows(mcp, camera, document):
    by_id, message = attempt(mcp, {"seconds": 1, "source": "camera", "camera": camera.get("id"),
                                   "place": False, "path": RUN, "project": document})
    got = (by_id or {}).get("camera") or {}
    check(message is None and got.get("name") == camera.get("name"),
          f"camera: <id> records the same camera: {got.get('name')!r} ({message!r})")
    upper = (camera.get("name") or "").upper()
    by_name, message = attempt(mcp, {"seconds": 1, "source": "camera", "camera": upper,
                                     "place": False, "path": RUN, "project": document})
    got = (by_name or {}).get("camera") or {}
    check(message is None and got.get("id") == camera.get("id"),
          f"camera: {upper!r} records the same id: {got.get('id')!r} ({message!r})")


def format_rows(mcp, camera, document):
    """CR2a: a recording at the first listed format that is not best and not the detection's."""
    row = next((f for f in host["formats"] if f != camera.get("format")), None)
    if row is None:
        skip(f"the camera_format rows: the camera lists no format but {camera.get('format')!r} "
             f"(listed {host['formats']})", FORMAT_CHECKS)
        return
    answer, message = attempt(mcp, {"seconds": 2, "source": "camera", "camera_format": row,
                                    "place": False, "path": RUN, "project": document})
    answer = answer or {}
    got = (answer.get("camera") or {}).get("format")
    check(message is None and got == row,
          f"camera_format {row} records at it: camera.format {got!r} ({message!r})")
    size = format_size(row)
    check(size is not None and (answer.get("width"), answer.get("height")) == size[:2],
          f"…and the file is that row's size: {answer.get('width')}×{answer.get('height')}")


def microphone_rows(mcp, document):
    reported = project(mcp, document)
    fps = reported["canvas"]["fps"]
    frame = SEC * fps[1] // fps[0]
    media_before = len(reported["media"])
    mcp.call_with("set_playhead", {"project": document, "t": 2 * SEC})
    answer, message = attempt(mcp, {"seconds": 2, "source": "camera", "microphone": True,
                                    "path": RUN, "project": document})
    answer = answer or {}
    reported = project(mcp, document)
    tracks = {t["id"]: t for t in reported["tracks"]}
    clips = {c["id"]: c for c in reported["clips"]}
    picture, voice = clips.get(answer.get("clip")), clips.get(answer.get("mic_clip"))
    check(message is None and picture is not None and picture["start"] == 2 * SEC,
          f"microphone: true with place lands the picture at the playhead: "
          f"{picture and picture['start']} ({message!r})")
    check(voice is not None and tracks.get(voice["track"], {}).get("name") == "Microphone"
          and voice["source"]["media"] == answer.get("mic_media"),
          f"…and the voice on the Microphone track: {voice}")
    offset = answer.get("mic_offset", 0)
    check(picture is not None and voice is not None
          and abs((picture["start"] - voice["start"]) - offset) <= frame // 2,
          f"their starts differ by mic_offset ({offset} ticks, {offset / 600:+.1f} ms) within half "
          f"a frame: picture {picture and picture['start']}, voice {voice and voice['start']}")
    files = [answer.get("path"), answer.get("mic_path")]
    undone = mcp.call_with("undo", {"project": document})
    after = project(mcp, document)
    check(len(after["media"]) == media_before
          and not ({answer.get("clip"), answer.get("mic_clip")} & {c["id"] for c in after["clips"]})
          and all(f and os.path.exists(f) for f in files),
          f"one undo ({undone.get('undone') if isinstance(undone, dict) else undone!r}) removes "
          f"both media and clips and leaves the files on disk: {files}")


def new_project_rows(mcp):
    try:
        found = state(mcp).get("project")
    except ToolError as error:
        found = None if NO_PROJECT in str(error) else str(error)
    if found is not None:
        where = found.get("path") if isinstance(found, dict) else found
        skip(f"the new-project rows: a project is open on this instance ({where!r})",
             NEW_PROJECT_CHECKS)
        return
    answer, message = attempt(mcp, {"seconds": 2, "source": "camera", "path": RUN})
    answer = answer or {}
    path = answer.get("path")
    check(message is None and answer.get("landed") == "new_project",
          f"with no project open it lands as a new project: {answer.get('landed')} ({message!r})")
    if not path:
        skip("the canvas row: no recording landed", 1)
        return
    try:
        canvas = project(mcp, path)["canvas"]
        size = format_size((answer.get("camera") or {}).get("format"))
        want = (size[0], size[1], [round(size[2]), 1]) if size else None
        got = (canvas.get("width"), canvas.get("height"), canvas.get("fps"))
        check(want is not None and got == want and (answer.get("width"), answer.get("height"))
              == want[:2],
              f"its canvas is the file's size at the format's rate, rounded: {got}, want {want}")
    finally:
        close(mcp, path)


# ---- the panel (CR1c) ------------------------------------------------------------------


def panel_part(mcp):
    try:
        mcp.call_with("perform_menu_item", {"path": ["File", "New Recording…"]})
        performed = None
    except ToolError as error:
        performed = str(error)
    check(performed is None, f"perform_menu_item File ▸ New Recording… answers: {performed!r}")
    result = mcp._request("tools/call", {"name": "snapshot_ui",
                                         "arguments": {"window": "recorder"}})
    text = "".join(p.get("text", "") for p in result.get("content", []) if p.get("type") == "text")
    check(not result.get("isError"), f"snapshot_ui {{window: recorder}} answers: {text[:200]!r}")
    if result.get("isError"):
        skip("the panel's layout rows: no capture", 2)
        return
    answer = json.loads(text)
    with open(answer["layout_path"]) as handle:
        layout = json.load(handle)
    texts = [view.get("text") for view in layout.get("views", [])]
    labels = [t for t in texts if t and t.endswith(":")]
    check("Camera:" in texts and "Format:" in texts,
          f"the recorder panel's layout lists views reading 'Camera:' and 'Format:': {labels}")
    problems = layout.get("problems", [])
    check(problems == [], f"the recorder panel's layout reports no problem: {problems}")
    lines = None
    if os.path.exists(LOG):
        with open(LOG, encoding="utf-8", errors="replace") as handle:
            lines = [line.rstrip() for line in handle if PARITY in line]
    check(lines == [], f"the log still holds no {PARITY!r} line: {lines}")


def main():
    os.makedirs(RUN, exist_ok=True)
    os.makedirs(DOCS, exist_ok=True)
    mcp = MCP(SOCKET, timeout=180)
    print(f"camera recording CR1b/CR1c/CR2a — record_screen's camera and the panel, against "
          f"{SOCKET}")
    document = os.path.join(DOCS, f"camera-{os.getpid()}.framejob")
    try:
        section("A — the catalog", catalog_part, mcp)
        mcp.call_with("new_project", {"path": document})
        section("B — the refusals, exact and in order, touching nothing", refusal_part, mcp,
                document)
        section("C — detection, then the granted tier", granted_tier, mcp, document)
    finally:
        try:
            listed = state(mcp, document)
        except ToolError:
            listed = None
        if listed is not None:
            close(mcp, document)
        time.sleep(0.5)
        shutil.rmtree(os.path.join(WORK, f"{os.getpid()}-files"), ignore_errors=True)
        shutil.rmtree(DOCS, ignore_errors=True)
    section("D — the recorder panel's Camera row (CR1c)", panel_part, mcp)

    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for what, count in skipped:
        print(f"  skipped: {what} — {count} checks")
    if skipped:
        print(f"  skipped in all: {sum(count for _, count in skipped)} checks")
    for what in failures:
        print(f"  FAILED: {what}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
