#!/usr/bin/env python3
"""Camera recording CR1a (spec §11 CAM-3): the camera recorder, measured through the app's own
sources; CR1b (CAM-4): `record_screen`'s camera, through the server's own functions; and CR1c
(CAM-5): the recorder panel's Camera source and the countdown's prepared capture.

    python3 tools/proof/camera_recording_probe.py [--sources DIR] [--only SECTIONS] [--mutant NAME]

`camera_recording_probe.swift` is built with `swift_build.py`'s line over `--sources` (every
file but `main.swift`) and an Info.plist section (`-sectcreate __TEXT __info_plist`,
`recording_probe.build_voice_probe`'s line) holding `NSCameraUsageDescription` and
`NSMicrophoneUsageDescription`, then run once per section, each in a process of its own, under
`TZ=UTC`. Prints `<ID> pass|fail|skip — <detail>` per row, then `scores: N/M`. Everything is
written under `tools/proof/work/camera-recording-probe/`.

Sections and rows:
  values   V1–V3 CAM-3's best format on CR0's three D1 lists (FaceTime HD's 7 → index 3,
           1760×1328@30; OBS → 1920×1080@60; the iPhone's 8 → index 7, 1920×1440@60, over
           index 6 on rate); V4 a portrait-only list (CAM-2 over every format); V5 an all-under-30
           list (→ the active format, nil without one); V6 `canvasRate` and `spelled`; V7
           `cameraStem` at a fixed date; V8 `nextCameraURL` against a held movie, a held
           microphone file and a file on disk; V9 `match`; V10 `defaultIndex`; V11 the two
           sentences; V12a–d `cameraMicOffset` (the PTS path over contrary arrivals, the arrival
           fallback, the sign, 0); V13 `cameraRefusal`'s four statuses; V14
           `RecorderError.cameraDevice`. Two SOURCE reads: V15 `cameraMicFinished`'s body sets
           `micProblem` and never calls `beginCameraFinishing(`; V16 `startCamera` reads
           `RecordingGrant.cameraStatus` before any `CameraCapture(`. V17 CAM-3's warm-up:
           `isSteady` over the cold start's intervals (33.3, 35.0, 43.3, 30.0 ms at 30 fps), the
           run of 5 and the 1 s bound, and `WarmUp.note` (nil steady; the rate named; no frame).
  landing  L1 a `.camera` result over ffmpeg fixtures (a 1920×1080 30 fps `.mov`, an `.m4a`)
           through `RecordingLanding.placement`: the picture on a track, the voice on a back
           track named Microphone; L2 `ProjectDocument.untitled(around:)`: the canvas 1920×1080
           at 30; L3 the result is `isCamera`, not `isVoiceOver`, and carries its camera.
  granted  a real `ScreenRecorder()` on `defaultIndex`'s camera and the default microphone:
           2 s, a 1 s pause, 2 s more. G0 it recorded; G1 2 segments, `pauses` 1, stopped by
           `stop()`, no camera problem; G2 each `.mov`'s size (ffprobe) equals the format applied,
           which is CAM-3's pick for that camera; G3 each `.mov`'s decoded frames are ≥ 98 % of
           (last − first PTS + one frame) × rate; G4 each |micOffset| < 0.5 s; G5 the names
           (`Camera Recording <date> at <time>.mov`, its ` (Microphone).m4a`) and the choice's rate
           the format's; G6 the warm-up hold (CAM-3): its length from the session's start within
           the bound (+ 0.15 s for the timer), its buffers, intervals and rate, and the result's
           `camera.note` nil when the stream was steady, naming the rate when the bound passed;
           a steady warm-up must have seen at least `WARM_UP_RUN` + 1 buffers (#372 item 2).
           Then, after that stop has answered plus 1 s, CR1c's prepared capture (CAM-5 (5)) on
           fresh recorders with no microphone: G7 `prepareCamera` (how long it held main), the
           countdown's 3 s, then `startCamera` adopts it and answers in < `PREPARED_START_MAX`
           with the slot emptied, 2 s recorded as one segment at ≥ 98 % frames by G3's decode,
           no `camera.note`; G8 a prepared capture discarded after 1 s: the slot nil and its
           session stopped 0.5 s later; G9 `startCamera` straight after `prepareCamera`, the
           prepared start not yet answered, JOINS it: no error before `armCeiling`, `.recording`,
           the slot nil, 1 s recorded as one segment, no note (the call-to-answer time beside
           CR1a's cold 1.943–1.962 s). Skipped by name when no camera is connected or the
           Camera grant is not authorized (nothing is recorded); G4 is skipped by name when the
           Microphone grant is not authorized (the recording is made without one). Never asks
           for a grant.
  tool     CR1b, `AgentServer.shared`'s own functions, no camera and no grant: T1
           `recordingSourceKind` with source camera — alone, a camera named, one stranger, all
           seven in `cameraRefusedArguments` order, a null size — and `source: "x"`'s
           vocabulary; T2 `camera` with screen (the default and named) and with voice_over
           beating `display`, a blank camera with screen and a null with voice_over admitted;
           T3 `recordingCameraID` over V1–V3's three lists: the default (built-in, then
           `preferredID`), a name in any case, an id, unknown, an empty list, unknown + denied
           (the lookup sentence), known + notDetermined and the default + restricted
           (`cameraRefusal`), known + authorized; T4 `cameraFields` without and with
           `problem`/`note`; T5 `recordingFields` of a camera result carries `camera` (and
           `has_audio` false, `stopped_by` system_stopped), a screen result's none; T6
           `resultNotes` of a camera result ends with its `problem` and `note`, a screen
           result's is the microphone's clause alone.
  panel    CR1c, `RecorderPanelController.shared` never shown, `.prohibited`, a spy sealed in
           `grantDoors` before `shared` exists, the eight `FrameJobRecording…` keys put back; fake
           rows (`probe-camera`, a "None connected" row, `probe-mic`) find no device. P1 the
           Source rows end Window… (1), Camera (3), Microphone Only (2), screens + 4, and the
           Camera popup is `connected()`'s names (or "None connected"); P2 Camera via
           `controlChanged` → `.camera` with `probe-camera`, the five (System Audio, Show Clicks,
           Size, Include Frame Job windows, Rate) disabled with their values kept, Camera,
           Microphone, Record Into and Source live, the size note `cameraSizeNote(nil)`; a
           display row → the five back, Camera disabled, `camera` nil; P3 session only: the
           display key's 777 kept, the camera key `probe-camera`, eight keys, the row and camera
           kept through `rebuildSources()` + `restoreChoices()`; P4 `cameraStep` over four
           statuses, `cameraPaneURL`, `cameraOpenedNote(.denied)` exact; P5 the press (no camera,
           `notDetermined` and its held answer on the hidden panel, denied and restricted, the
           microphone's ask, the countdown with Microphone Off; 0 Screen Recording reads or
           requests) and a comment-stripped read of `cameraAnswered` (its `cameraStatus()`
           before `checkMicrophoneGrant` and `beginCountdown`); P6 `hidesForRecording` and the
           Pause / Resume button; P7 `landingNote`'s camera sentences; P8 `cameraSizeNote` on
           V1's FaceTime and V3's iPhone lists and nil; P9 comment-stripped reads: the
           countdown's `prepareCamera`, the four `discardPreparedCamera`s, `startRecording`'s
           `launchCamera`, the meter's `cameraSession`.

Mutants (each a `--mutant` edit of a copy of `--sources`), run with `--only values` but the
`tool` five, run with `--only tool`, the `panel` eight, run with `--only panel`, and `no-hold`,
`prepare-ignored` and `join-weak`, run with `--only granted` (they need the camera):
  format-any-shape    no landscape filter                                 → V1
  offset-by-arrival   the PTS ignored                                     → V12a
  offset-sign         the PTS difference negated                          → V12a, V12c
  canvas-rate-60      `canvasRate` answers 60                             → V6
  grant-unread        the `cameraStatus` guard deleted from `startCamera` → V16
  mic-ends-recording  an unasked microphone did-finish ends the recording → V15
  no-hold             `warmUpRun` 0: the warm-up ends at its first buffer → G6
  camera-strangers-admitted  a camera's strangers list emptied                 → T1
  camera-elsewhere-admitted  `camera` taken with any source                    → T2
  grant-before-lookup  the Camera grant read before the lookup                 → T3
  camera-key-dropped  `recordingFields` writes no `camera`                     → T5
  camera-notes-dropped  `resultNotes` leaves out the camera's two sentences    → T6
  camera-screen-grant-read  `beginIfGranted`'s camera line deleted             → P5
  camera-grant-unasked  `cameraStep` `.notDetermined` → `.openPane`            → P4, P5
  camera-row-live     `syncCameraControls` leaves the five live                → P2
  camera-row-persisted  the persist guard's `, !cameraSelected` dropped        → P3
  camera-panel-hides  `hidesForRecording` → `source != .voiceOver`             → P6
  camera-problem-unsaid  `landingNote` ignores `camera`                        → P7
  countdown-unprepared  `beginCountdown`'s `prepareCamera` line deleted        → P9
  camera-answer-unread  `cameraAnswered`'s `cameraStatus()` re-read deleted    → P5
  prepare-ignored     `takeCameraCapture` never adopts                         → G7
  join-weak           the prepared start's completion holds `[weak prepared]`  → G9

Exit (cache_pass_probe.py's rule): a plain run exits 0 iff no row failed (a skip by name is
not a failure) and 1 when one did; a build failure is B0's FAIL. A `--mutant` run exits 1 when
every row it names failed (caught), 0 when one passed (survived), and 2 when the control could
not be performed: a `before` text not found exactly once, the copy did not build, or a named
row was not scored. No ffmpeg (needed by landing and granted) exits 2.
"""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/camera-recording-probe"
SECTIONS = ["values", "landing", "granted", "tool", "panel"]
ROWS = {
    "values": ["V1", "V2", "V3", "V4", "V5", "V6", "V7", "V8", "V9", "V10", "V11", "V12a", "V12b",
               "V12c", "V12d", "V13", "V14", "V15", "V16", "V17"],
    "landing": ["L1", "L2", "L3"],
    "granted": ["G0", "G1", "G2", "G3", "G4", "G5", "G6", "G7", "G8", "G9"],
    "tool": ["T1", "T2", "T3", "T4", "T5", "T6"],
    "panel": ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9"],
}
SECTION_WALL = 180
STEM_EPOCH = 1793034873   # 2026-10-26 17:14:33 UTC
STEM_WANT = "Camera Recording 2026-10-26 at 17.14.33"
FRAMES_PASS = 0.98
HOLD_BOUND = 1.0          # CameraCapture.warmUpBound
HOLD_SLACK = 0.15         # the bound's timer and the hop to main
WARM_UP_RUN = 5           # CameraCapture.warmUpRun, written here rather than read from Swift
PREPARED_START_MAX = 0.3  # G7: a start that adopts a warm prepared capture answers within this
INFO_PLIST = """<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>NSCameraUsageDescription</key><string>The Frame Job camera recording probe records a short camera clip to check the recorder.</string>
<key>NSMicrophoneUsageDescription</key><string>The Frame Job camera recording probe records the microphone beside the camera.</string>
</dict></plist>
"""

GRANT_GUARD = """        let cameraGrant = RecordingGrant.cameraStatus
        guard cameraGrant == .authorized else {
            return refuseCamera(.startFailed(RecordingGrant.cameraRefusal(cameraGrant)), completion)
        }
"""
# `recordingCameraID`'s grant guard, which `grant-before-lookup` moves above the lookup.
GRANT_AFTER_LOOKUP = """        guard status == .authorized else {
            throw ToolError(message: RecordingGrant.cameraRefusal(status))
        }
"""
# `cameraAnswered`'s re-read of the Camera grant, which `camera-answer-unread` deletes.
CAMERA_REREAD = """        let status = Self.grantDoors.cameraStatus()
        guard status == .authorized else {
            setNote(RecordingGrant.cameraRefusal(status))
            return
        }
"""
# The prepared start's completion, holding its `PreparedCamera` strongly; `join-weak` weakens it.
JOIN_STRONG = """        capture.start { error in
            prepared.answered = true
            prepared.startError = error
            let waiting = prepared.waiting
            prepared.waiting = nil
            waiting?(error)
        }
"""
JOIN_WEAK = """        capture.start { [weak prepared] error in
            prepared?.answered = true
            prepared?.startError = error
            let waiting = prepared?.waiting
            prepared?.waiting = nil
            waiting?(error)
        }
"""
# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "format-any-shape": (["V1"], [
        ("CameraDevices.swift",
         "let landscape = formats.indices.filter { formats[$0].width > formats[$0].height }",
         "let landscape = Array(formats.indices)")]),
    "offset-by-arrival": (["V12a"], [
        ("ScreenRecorder+CameraFinishing.swift", "if let cameraPTS, let micPTS {",
         "if let cameraPTS, let micPTS, cameraPTS.isNaN {")]),
    "offset-sign": (["V12a", "V12c"], [
        ("ScreenRecorder+CameraFinishing.swift", "seconds = cameraPTS - micPTS",
         "seconds = micPTS - cameraPTS")]),
    "canvas-rate-60": (["V6"], [
        ("CameraDevices.swift", "max(1, Int(format.maxRate.rounded()))", "60")]),
    "grant-unread": (["V16"], [("ScreenRecorder+Camera.swift", GRANT_GUARD, "")]),
    "mic-ends-recording": (["V15"], [
        ("ScreenRecorder+CameraFinishing.swift",
         "// The picture records on: a microphone never ends a camera recording (CAM-3).",
         "if unasked, state == .recording { beginCameraFinishing() }")]),
    "no-hold": (["G6"], [
        ("CameraCapture.swift", "static let warmUpRun = 5", "static let warmUpRun = 0")]),
    # CR1b (spec §11 CAM-4), each run with `--only tool`.
    "camera-strangers-admitted": (["T1"], [
        ("AgentServer+RecordingCamera.swift",
         "let strangers = Self.cameraRefusedArguments.filter { a[$0] != nil && !(a[$0] is NSNull) }",
         "let strangers = [String]()")]),
    "camera-elsewhere-admitted": (["T2"], [
        ("AgentServer+RecordingCamera.swift", "guard kind == .camera || camera == nil else {",
         "guard kind == .camera || camera == nil || true else {")]),
    "grant-before-lookup": (["T3"], [
        ("AgentServer+RecordingCamera.swift", GRANT_AFTER_LOOKUP, ""),
        ("AgentServer+RecordingCamera.swift", "        let index: Int?\n",
         GRANT_AFTER_LOOKUP + "        let index: Int?\n")]),
    "camera-key-dropped": (["T5"], [
        ("AgentServer+RecordingResult.swift",
         '            fields["camera"] = cameraFields(camera, id: result.choice.camera)\n', "")]),
    "camera-notes-dropped": (["T6"], [
        ("AgentServer+RecordingResult.swift",
         "            result.camera?.problem, result.camera?.note,\n", "")]),
    # CR1c (spec §11 CAM-5): the panel's eight, each run with `--only panel`, and the
    # recorder's two, each run with `--only granted` (they need the camera).
    "camera-screen-grant-read": (["P5"], [
        ("RecorderPanelController+Recording.swift",
         "        if cameraSelected { return beginCameraIfGranted() }\n", "")]),
    "camera-grant-unasked": (["P4", "P5"], [
        ("RecordingSetup+Camera.swift", "        case .notDetermined: return .ask\n",
         "        case .notDetermined: return .openPane\n")]),
    "camera-row-live": (["P2"], [
        ("RecorderPanelController+Camera.swift",
         "        for control in screenAndRate { control.isEnabled = false }\n",
         "        _ = screenAndRate\n")]),
    "camera-row-persisted": (["P3"], [
        ("RecorderPanelController+Rows.swift",
         "        if sourcePopup.selectedItem?.tag != Self.windowTag, !voiceOverSelected, !cameraSelected {\n",
         "        if sourcePopup.selectedItem?.tag != Self.windowTag, !voiceOverSelected {\n")]),
    "camera-panel-hides": (["P6"], [
        ("RecorderPanelController+VoiceOver.swift",
         "-> Bool { source != .voiceOver && source != .camera }\n", "-> Bool { source != .voiceOver }\n")]),
    "camera-problem-unsaid": (["P7"], [
        ("RecorderPanelController+Landing.swift",
         "    ) -> String {\n        var sentences: [String] = []\n",
         "    ) -> String {\n        let camera: RecordingCamera? = nil\n        var sentences: [String] = []\n")]),
    "countdown-unprepared": (["P9"], [
        ("RecorderPanelController+Recording.swift",
         "        recorder.prepareCamera(for: currentChoice())\n", "")]),
    "camera-answer-unread": (["P5"], [
        ("RecorderPanelController+Grants.swift", CAMERA_REREAD, "")]),
    "prepare-ignored": (["G7"], [
        ("ScreenRecorder+CameraPrepare.swift",
         "            prepared.adopted = true\n            return prepared.capture\n",
         "            _ = prepared\n")]),
    "join-weak": (["G9"], [
        ("ScreenRecorder+CameraPrepare.swift", JOIN_STRONG, JOIN_WEAK)]),
}
# The section a mutant runs when `--only` is not given.
MUTANT_SECTION = {"no-hold": "granted", "camera-strangers-admitted": "tool",
                  "camera-elsewhere-admitted": "tool", "grant-before-lookup": "tool",
                  "camera-key-dropped": "tool", "camera-notes-dropped": "tool",
                  "camera-screen-grant-read": "panel", "camera-grant-unasked": "panel",
                  "camera-row-live": "panel", "camera-row-persisted": "panel",
                  "camera-panel-hides": "panel", "camera-problem-unsaid": "panel",
                  "countdown-unprepared": "panel", "camera-answer-unread": "panel",
                  "prepare-ignored": "granted", "join-weak": "granted"}


def run(command, **kw):
    return subprocess.run(command, capture_output=True, text=True, **kw)


def build(sources, here):
    """(binary, None) or (None, why): `swift_build.build` with the Info.plist section."""
    entry = here / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/camera_recording_probe.swift", entry)
    plist = here / "Info.plist"
    plist.write_text(INFO_PLIST)
    binary = here / "camera-recording-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(
            sources=swift + [str(entry)], output=binary,
            link_args=["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker",
                       "__info_plist", "-Xlinker", str(plist)],
            link_inputs=[str(plist)])
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc: " + "; ".join((errors or error.diagnostics)[:6])
    return binary, None


def mutate(sources, name, dest):
    """A copy of `sources` with the mutant's edits; why when a `before` is not found once."""
    shutil.copytree(sources, dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before.strip()[:60]}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def section(binary, here, name, request):
    """(rows, facts) one section's process answered, or (None, why)."""
    path = here / f"request-{name}.json"
    path.write_text(json.dumps(request))
    env = dict(os.environ, TZ="UTC")
    try:
        result = run([str(binary), name, str(path)], timeout=SECTION_WALL, env=env)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {SECTION_WALL} s"
    (here / f"stderr-{name}.txt").write_text(result.stderr)
    try:
        answer = json.loads(result.stdout.strip().splitlines()[-1])
        return (answer["rows"], answer["facts"]), None
    except (ValueError, KeyError, IndexError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def body_of(text, signature):
    """The text of the function whose declaration starts `signature`, through its matching
    closing brace; None when it is not there exactly once."""
    if text.count(signature) != 1:
        return None
    start = text.index(signature)
    depth, i, opened = 0, start, False
    while i < len(text):
        if text[i] == "{":
            depth += 1
            opened = True
        elif text[i] == "}":
            depth -= 1
            if opened and depth == 0:
                return text[start:i + 1]
        i += 1
    return None


def source_rows(sources):
    """V15 and V16: the two source reads."""
    rows = {}
    finishing = (sources / "ScreenRecorder+CameraFinishing.swift")
    body = body_of(finishing.read_text() if finishing.exists() else "", "func cameraMicFinished(")
    if body is None:
        rows["V15"] = (False, "cameraMicFinished not found exactly once")
    else:
        sets = "micProblem =" in body
        ends = "beginCameraFinishing(" in body
        rows["V15"] = (sets and not ends,
                       f"cameraMicFinished sets micProblem {sets}, calls beginCameraFinishing( {ends}")
    camera = sources / "ScreenRecorder+Camera.swift"
    body = body_of(camera.read_text() if camera.exists() else "", "func startCamera(")
    if body is None:
        rows["V16"] = (False, "startCamera not found exactly once")
    else:
        grant = body.find("RecordingGrant.cameraStatus")
        capture = body.find("CameraCapture(")
        rows["V16"] = (grant >= 0 and capture >= 0 and grant < capture,
                       f"RecordingGrant.cameraStatus at {grant}, the first CameraCapture( at {capture}")
    return rows


def uncommented(path):
    """The file's text with every `//` comment taken out (no string in the bodies read holds
    `//`); "" when the file is missing."""
    text = path.read_text() if path.exists() else ""
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def panel_source_rows(sources):
    """P5's read of the camera prompt's answer, and P9: comment-stripped reads of the panel's
    countdown, its discards and its dispatch, and the recorder's meter."""
    rows = {}
    grants = uncommented(sources / "RecorderPanelController+Grants.swift")
    body = body_of(grants, "func cameraAnswered(")
    if body is None:
        rows["P5"] = (False, "cameraAnswered not found exactly once")
    else:
        names = all(n in body for n in ("isVisible == true", "recordButton.isEnabled = true",
                                        "cameraStatus()", "cameraRefusal"))
        read, mic, count = (body.find("cameraStatus()"), body.find("checkMicrophoneGrant"),
                            body.find("beginCountdown"))
        ordered = 0 <= read < mic and read < count and count >= 0
        rows["P5"] = (names and ordered,
                      f"cameraAnswered names the visible guard, Record re-enabled, cameraStatus() and "
                      f"cameraRefusal {names}; cameraStatus() at {read}, checkMicrophoneGrant at {mic}, "
                      f"beginCountdown at {count}")
    recording = uncommented(sources / "RecorderPanelController+Recording.swift")
    base = uncommented(sources / "RecorderPanelController.swift")
    microphone = uncommented(sources / "ScreenRecorder+Microphone.swift")
    reads = []
    for text, signature, wanted in (
            (recording, "func beginCountdown(", ["prepareCamera("]),
            (recording, "func cancelCountdown(", ["discardPreparedCamera("]),
            (recording, "func abandonStart(", ["discardPreparedCamera("]),
            (recording, "func startFailed(", ["discardPreparedCamera("]),
            (base, "func panelWillClose(", ["discardPreparedCamera("]),
            (recording, "func startRecording(", [".camera", "launchCamera(choice)"]),
            (microphone, "func publishMicrophoneLevel(", ["cameraSession"])):
        body = body_of(text, signature)
        reads.append((signature, body is not None and all(w in body for w in wanted), wanted))
    rows["P9"] = (all(ok for _, ok, _ in reads),
                  "; ".join(f"{sig[5:-1]} names {' and '.join(w)} {ok}" for sig, ok, w in reads))
    return rows


def fixtures(here):
    """The landing's two files, made by ffmpeg; (movie, voice) or None and why."""
    movie, voice = here / "camera-1080p30.mov", here / "camera-voice.m4a"
    for argv in (
            ["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30",
             "-t", "2", "-c:v", "libx264", "-pix_fmt", "yuv420p", str(movie)],
            ["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000",
             "-t", "2", "-c:a", "aac", str(voice)]):
        done = run(argv, timeout=120)
        if done.returncode != 0:
            return None, f"{' '.join(argv[:6])}… exit {done.returncode}: {done.stderr[-200:]}"
    return (movie, voice), None


def movie_facts(path):
    """ffprobe's decoded frame count, size and the packets' PTS span of a movie."""
    done = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-count_frames",
                "-show_entries", "stream=width,height,nb_read_frames", "-of", "json", path],
               timeout=120)
    stream = (json.loads(done.stdout or "{}").get("streams") or [{}])[0]
    pts = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "packet=pts_time", "-of", "csv=p=0", path], timeout=120)
    times = sorted(float(t) for t in pts.stdout.split() if t.strip() and t != "N/A")
    return {"width": stream.get("width"), "height": stream.get("height"),
            "frames": int(stream.get("nb_read_frames") or 0),
            "first": times[0] if times else None, "last": times[-1] if times else None}


def decoded_ratio(path, rate):
    """G3's measure: decoded frames / ((last − first PTS + one frame) × rate); None when it
    cannot be read."""
    m = movie_facts(path)
    if m["first"] is None or not rate:
        return None, m
    expected = (m["last"] - m["first"] + 1.0 / rate) * rate
    return (round(m["frames"] / expected, 4) if expected else None), m


def prepared_rows(facts):
    """G7–G9 (CR1c, CAM-5 (5)): the countdown's prepared capture adopted, let go, joined."""
    rows = {}
    match = re.match(r"^(\d+)x(\d+)@([\d.]+)$", facts.get("best") or "")
    rate = float(match[3]) if match else 0
    g7 = facts.get("G7") or {}
    segments = g7.get("segments") or []
    ratios = [decoded_ratio(path, rate) for path in segments]
    took = g7.get("startSeconds")
    rows["G7"] = (g7.get("prepared") is True and not g7.get("error") and not g7.get("stopError")
                  and took is not None and took < PREPARED_START_MAX
                  and g7.get("preparedAfter") is False and len(segments) == 1
                  and all(r is not None and r >= FRAMES_PASS for r, _ in ratios)
                  and g7.get("note") is None,
                  f"prepareCamera held main {g7.get('prepareSeconds') or 0:.3f} s; the prepared start "
                  f"had answered {g7.get('answeredAtStart')} after the countdown's 3 s; "
                  f"startCamera answered in {took if took is None else round(took, 3)} s "
                  f"(< {PREPARED_START_MAX} s), the slot nil after {g7.get('preparedAfter') is False}; "
                  f"{len(segments)} segment(s), frames "
                  + ", ".join(f"{m['frames']}/{r}" for r, m in ratios)
                  + f"; note {g7.get('note')}; {g7.get('error') or g7.get('stopError') or ''}")
    g8 = facts.get("G8") or {}
    rows["G8"] = (g8.get("held") is True and g8.get("slotNil") is True and g8.get("running") is False,
                  f"a capture prepared {g8.get('held')}; after discardPreparedCamera the slot nil "
                  f"{g8.get('slotNil')}, its session running {g8.get('running')}")
    g9 = facts.get("G9") or {}
    took = g9.get("startSeconds")
    ceiling = g9.get("ceiling") or 20
    joined = g9.get("prepared") is True and g9.get("answeredAtStart") is False
    rows["G9"] = (joined and not g9.get("error") and not g9.get("stopError") and took is not None
                  and took < ceiling and g9.get("state") == "recording"
                  and g9.get("preparedAfter") is False and len(g9.get("segments") or []) == 1
                  and g9.get("note") is None,
                  f"startCamera called with the prepared start unanswered {joined} (else it did not "
                  f"reach the join); answered in {took if took is None else round(took, 3)} s "
                  f"(ceiling {ceiling:g} s; CR1a's cold start 1.943–1.962 s), state {g9.get('state')}, "
                  f"the slot nil {g9.get('preparedAfter') is False}; "
                  f"{len(g9.get('segments') or [])} segment(s), note {g9.get('note')}; "
                  f"{g9.get('error') or g9.get('stopError') or ''}")
    return rows


def granted_rows(facts):
    """G0–G9 from the granted section's facts; a dict of id → (state, detail) where state is
    True, False or "skip"."""
    rows = {}
    if facts.get("skip"):
        return {row: ("skip", facts["skip"]) for row in ROWS["granted"]}
    if facts.get("error"):
        rows["G0"] = (False, facts["error"])
        rows.update(prepared_rows(facts))
        return rows
    segments = facts.get("segments") or []
    rows["G0"] = (bool(segments) and facts.get("isCamera") is True and facts.get("idle") is True
                  and facts.get("onFinishCalls") == 1,
                  f"{len(segments)} segment(s), the recorder idle {facts.get('idle')}, onFinish "
                  f"{facts.get('onFinishCalls')}×, steps {facts.get('steps')}")
    rows["G1"] = (len(segments) == 2 and facts.get("pauses") == 1 and facts.get("stoppedBy") == "stopped"
                  and facts.get("problem") is None and not facts.get("unreadable"),
                  f"segments {len(segments)}, pauses {facts.get('pauses')}, stoppedBy "
                  f"{facts.get('stoppedBy')}, problem {facts.get('problem')}, left out "
                  f"{facts.get('unreadable')}")
    applied = facts.get("format", "")
    match = re.match(r"^(\d+)x(\d+)@([\d.]+)$", applied)
    width, height, rate = (int(match[1]), int(match[2]), float(match[3])) if match else (0, 0, 0)
    measured = [movie_facts(s["movie"]) for s in segments]
    rows["G2"] = (bool(match) and applied == facts.get("best")
                  and all(m["width"] == width and m["height"] == height for m in measured),
                  f"applied {applied} (CAM-3's pick {facts.get('best')}); files "
                  + ", ".join(f"{m['width']}×{m['height']}" for m in measured))
    ratios = []
    for m in measured:
        if m["first"] is None or not rate:
            ratios.append(None)
            continue
        expected = (m["last"] - m["first"] + 1.0 / rate) * rate
        ratios.append(round(m["frames"] / expected, 4) if expected else None)
    rows["G3"] = (bool(ratios) and all(r is not None and r >= FRAMES_PASS for r in ratios),
                  "decoded frames / span × rate: " + ", ".join(
                      f"{m['frames']}/{r}" for m, r in zip(measured, ratios)))
    if not facts.get("microphone"):
        rows["G4"] = ("skip", f"the Microphone grant is {facts.get('micGrant')}: recorded without "
                              "a microphone")
    else:
        offsets = [s.get("micOffset") for s in segments]
        problems = [s.get("micProblem") for s in segments]
        rows["G4"] = (all(s.get("mic") for s in segments)
                      and all(o is not None and abs(o) < 0.5 for o in offsets),
                      f"micOffset s {offsets}; problems {problems}")
    names_ok, shown = True, []
    pattern = re.compile(r"^Camera Recording \d{4}-\d\d-\d\d at \d\d\.\d\d\.\d\d( \(\d+\))?\.mov$")
    for s in segments:
        movie = os.path.basename(s["movie"])
        ok = bool(pattern.match(movie))
        if s.get("mic"):
            ok = ok and os.path.basename(s["mic"]) == movie[:-4] + " (Microphone).m4a"
        names_ok = names_ok and ok
        shown.append(movie + (" + " + os.path.basename(s["mic"]) if s.get("mic") else ""))
    rows["G5"] = (names_ok and facts.get("rate") == facts.get("bestRate"),
                  f"{shown}; rate {facts.get('rate')} (want {facts.get('bestRate')})")
    warm = facts.get("warmUp")
    if not warm:
        rows["G6"] = (False, "no warm-up was recorded")
    else:
        if warm["steady"]:
            noted = warm.get("note") is None and facts.get("note") is None
        else:
            noted = (facts.get("note") is not None and facts.get("note") == warm.get("note")
                     and f"{warm['rate']:.1f} fps" in facts["note"])
        # #372 item 2: a steady warm-up saw a run of WARM_UP_RUN intervals, so at least
        # WARM_UP_RUN + 1 buffers — `no-hold`'s ends at its first.
        enough = warm["buffers"] >= (WARM_UP_RUN + 1 if warm["steady"] else 1)
        rows["G6"] = (warm["seconds"] <= HOLD_BOUND + HOLD_SLACK and enough and noted,
                      f"hold {warm['seconds']:.3f} s (bound {HOLD_BOUND:g} s), {warm['buffers']} "
                      f"buffers (a steady one needs ≥ {WARM_UP_RUN + 1}), steady "
                      f"{warm['steady']}, ran at {warm['rate']:.2f} fps (want "
                      f"{warm['wanted']:g}); intervals ms {warm['intervals']}; the call to "
                      f"recording {facts.get('startSeconds') or 0:.3f} s; note {facts.get('note')}")
    rows.update(prepared_rows(facts))
    return rows


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated sections: " + ",".join(SECTIONS))
    args = parser.parse_args()
    wanted = (args.only.split(",") if args.only
              else ([MUTANT_SECTION.get(args.mutant, "values")] if args.mutant
                    else list(SECTIONS)))
    unknown = [s for s in wanted if s not in SECTIONS]
    if unknown:
        print("unknown section " + ", ".join(unknown))
        return 2
    if {"landing", "granted"} & set(wanted) and not shutil.which("ffmpeg"):
        print("instrument failure: ffmpeg is not on PATH (landing and granted need it)")
        return 2
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = args.sources.resolve()
    if args.mutant:
        why = mutate(sources, args.mutant, here / "Sources")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"

    results = {}
    binary, why = build(sources, here)
    results["B0"] = (binary is not None, why or f"built from {sources}")
    order = ["B0"]
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    for name in wanted:
        order += ROWS[name]
        if binary is None:
            for row in ROWS[name]:
                results[row] = (False, "not run: the probe did not build")
            continue
        request = {"work": str(here / name)}
        if name == "values":
            request.update(stemEpoch=STEM_EPOCH, stemWant=STEM_WANT)
        if name == "landing":
            made, why = fixtures(here)
            if made is None:
                for row in ROWS[name]:
                    results[row] = (False, f"fixtures: {why}")
                continue
            request.update(movie=str(made[0]), voice=str(made[1]))
        if name == "granted":
            folder = here / "recordings"
            folder.mkdir(parents=True, exist_ok=True)
            request.update(folder=str(folder))
        answer, why = section(binary, here, name, request)
        if answer is None:
            for row in ROWS[name]:
                results.setdefault(row, (False, f"no row: {why}"))
            continue
        rows, facts = answer
        (here / f"facts-{name}.json").write_text(json.dumps(facts, indent=1))
        for row in rows:
            results[row["id"]] = (bool(row["pass"]), row["detail"])
        if name == "values":
            results.update(source_rows(sources))
        if name == "granted":
            results.update(granted_rows(facts))
        if name == "panel":
            swift_p5 = results.get("P5", (False, "the section did not answer it"))
            read = panel_source_rows(sources)
            results["P9"] = read["P9"]
            results["P5"] = (swift_p5[0] is True and read["P5"][0] is True,
                             f"{swift_p5[1]} | the answer's re-read: {read['P5'][1]}")
            visible = facts.get("visible") is False and facts.get("visibleAtEnd") is False
            if not visible:
                results["P1"] = (False, f"the panel was shown: {facts}")
        for row in ROWS[name]:
            results.setdefault(row, (False, "the section did not answer it"))

    failed = 0
    for row in order:
        state, detail = results[row]
        word = "skip" if state == "skip" else ("pass" if state else "fail")
        failed += word == "fail"
        print(f"{row} {word} — {detail}")
    scored = [r for r in order if results[r][0] != "skip"]
    passed = sum(1 for r in scored if results[r][0] is True)
    print(f"scores: {passed}/{len(scored)}"
          + (f" ({len(order) - len(scored)} skipped by name)" if len(scored) < len(order) else ""))
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        missing = [r for r in named if r not in results]
        if missing:
            print(f"mutant {args.mutant}: the control could not be performed — "
                  f"{', '.join(missing)} not scored")
            return 2
        caught = all(results[r][0] is False for r in named)
        print(f"mutant {args.mutant}: {'caught' if caught else 'survived'} ({', '.join(named)})")
        return 1 if caught else 0
    if failed == 0:
        print("all checks passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
