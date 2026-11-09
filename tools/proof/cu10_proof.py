#!/usr/bin/env python3
"""Road map "creator-jobs" CU10 — the recorder polishes on landing (spec §11 CU-100…CU-103).

    python3 tools/proof/cu10_proof.py [SOCKET] [--only P1,P2,…] [--mutant NAME] [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the plain
rows launch their own instance. P1b always launches its own, with Auto Zoom's and Speed Up
Typing's nine remembered sheet keys pinned at `AutoZoomSettings()`'s and
`SpeedUpTypingSettings()`'s values by launch arguments (nothing is written to the defaults
domain); the three `FrameJobRecording…` polish keys never reach `land_recording`'s panel door,
which builds its own choice. Launches run on a scratch `CFFIXED_USER_HOME`; packages and media
are made under `tools/proof/work/cu10/`. The movie is ffmpeg's `testsrc` (640 × 360, 30 fps,
20 s, no sound) with a v1 cursor file beside it (`core/src/cursor_file.rs`): two clicks, ⌘S at
5.0 s and typing 4.0–16.0 s; the voice is 20 s of silence, so its speech cannot exist before the
landing. Every recording is landed by the dev tool `land_recording` into a fresh saved package.

Rows:
- Z0 `grep "Frame Job: "` of every instance's log prints nothing.
- P1 the door tool with `keys: "shortcuts"` and all three: the answer holds `auto_zoom`,
  `shortcut_overlays` and `speed_up_typing` objects; undo reads "Speed Up Typing", "Add Shortcut
  Overlays", "Auto Zoom", then "Add Recording"; `get_project` (before the undos) equals a second
  fresh package landed with none and given `auto_zoom`, `add_shortcut_overlays` and
  `speed_up_typing {clips}` by hand, in that order.
- P1b the door panel with `follow_wait`: `polish_pending` false, the same three names in order
  and the same project as P1's.
- P2 the speed-up waited for speech: `speed_up_typing.speech_saved` names the voice's media.
- P3 `auto_zoom: true` refused by name with `source: voice_over` (`record_screen`, before any
  grant) and without `movie` (`land_recording`).
- P4 `auto_zoom: true, place: false` and `speed_up_typing: true` without `keys` refused in
  CU-102 (b)'s sentences through both tools; the project unchanged.
- P5 (#458) its own instance (P1b's pins): a package holding a nest (a clip of the silence at
  60 s, nested) before the landing; the door panel with `enhance: true` and `auto_zoom: true`,
  the voice spoken (`say -v Samantha`, padded to 20 s; without the voice the row fails naming
  it), no `follow_wait`; at once `set_scope` into the nest, 3 s, `set_scope` out. Within 300 s
  the screen clip holds Auto Zoom's actions, and the undo names read "Auto Zoom" then "Add
  Recording", with only "Enhance Voice" allowed between them: the polish waited out the nest
  rather than dropping (Enhance is there for its wait, which holds the polish past the nest;
  its own step is not required — on a Debug build the panel door's Enhance Voice makes no step
  on this fixture even with no nest open, filed as its own issue by fixes batch c1; on Release
  it does, and the undo reads all three).

`--mutant NAME` edits a `tree_copy.py` copy, builds its app and runs P1 on it: `wrong-order`
(the commands reversed) and `one-step` (the tool door's three runs inside one undo group).
CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits 2.
"""

import argparse
import json
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
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/cu10"
HOME = WORK / "home"
KEEP = {"media"}
CALL_BOUND = 600
BUILD_BOUND = 1500
W, H = 640, 360
PLAIN = ["P1", "P2", "P3", "P4"]
PANEL = ["P1b"]
NESTED = ["P5"]
ROWS = ["Z0"] + PLAIN + PANEL + NESTED
NESTED_STEPS = [["Auto Zoom", "Add Recording"], ["Auto Zoom", "Enhance Voice", "Add Recording"]]
SPOKEN = ("This is the voice of a screen recording. Each sentence is spoken clearly, so the "
          "speech is found and the voice can be enhanced once the recording has landed.")
PANEL_ARGS = [
    "-FrameJobAutoZoomZoom", "2", "-FrameJobAutoZoomLead", "0.6", "-FrameJobAutoZoomStay", "2.5",
    "-FrameJobAutoZoomFollow", "YES", "-FrameJobAutoZoomReplace", "NO",
    "-FrameJobAutoZoomMotionBlur", "YES", "-FrameJobSpeedUpTypingRate", "4",
    "-FrameJobSpeedUpTypingShortest", "3", "-FrameJobSpeedUpTypingKeepPitch", "YES",
]
STEPS = ["Speed Up Typing", "Add Shortcut Overlays", "Auto Zoom", "Add Recording"]
POLISH = ["auto_zoom", "shortcut_overlays", "speed_up_typing"]
SENTENCES = {
    "zoom_place": "auto_zoom: true plans on the landed screen clips, so it needs place: true.",
    "speed_keys": "speed_up_typing: true needs keys: \"shortcuts\" — without it the cursor file "
                  "records no typing to speed up.",
    "voice": "With source voice_over, auto_zoom cannot be given — a voice-over records the "
             "microphone alone.",
    "movie": "auto_zoom cannot be given without movie — a voice-over has no screen clips.",
}

POLISH_FILE = "app/Sources/RecordingPolish.swift"
TOOL_FILE = "app/Sources/AgentServer+RecordingPolish.swift"
# name → (rows, [(path, anchor, replacement)])
MUTANTS = {
    "wrong-order": (["P1"], [(
        POLISH_FILE, "        Command.allCases.filter { command in\n",
        "        Command.allCases.reversed().filter { command in\n")]),
    "one-step": (["P1"], [(
        TOOL_FILE, "        while let command = remaining.first {\n",
        "        let mutantUndo = onMain { document.undoManager }\n"
        "        onMain {\n"
        "            mutantUndo?.groupsByEvent = false\n"
        "            mutantUndo?.beginUndoGrouping()\n"
        "        }\n"
        "        defer {\n"
        "            onMain {\n"
        "                mutantUndo?.endUndoGrouping()\n"
        "                mutantUndo?.groupsByEvent = true\n"
        "            }\n"
        "        }\n"
        "        while let command = remaining.first {\n")]),
}

results = {}
selected = set(ROWS)


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


# ---- media and the cursor file -------------------------------------------------

def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {
        "screen.mov": ["-f", "lavfi", "-i", f"testsrc=size={W}x{H}:rate=30:duration=20",
                       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0"],
        "silence.m4a": ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "20",
                        "-c:a", "aac"],
    }
    for name, args in made.items():
        out = folder / name
        if not out.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", *args, str(out)], check=True,
                           timeout=300, env=bounded.child_env())
    return {name.split(".")[0]: folder / name for name in made}


def spoken_voice():
    """A 20 s spoken voice (`say -v Samantha`, padded), made once; None when `say` cannot."""
    out = WORK / "media" / "spoken.m4a"
    if out.exists():
        return out
    aiff = WORK / "media" / "spoken.aiff"
    said = subprocess.run(["say", "-v", "Samantha", "-o", str(aiff), SPOKEN],
                          capture_output=True, text=True, timeout=120)
    if said.returncode != 0 or not aiff.exists():
        return None
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(aiff), "-af", "apad", "-t", "20",
                    "-ar", "48000", "-ac", "1", "-c:a", "aac", str(out)], check=True,
                   timeout=300, env=bounded.child_env())
    return out


def us(seconds):
    return int(round(seconds * 1e6))


CLICKS = [(2.0, 320, 180), (17.0, 200, 150)]
SHORTCUTS = [5.0]
TYPING = (4.0, 16.0)


def cursor_body():
    """A v1 cursor file: CLICKS (seconds, px x, px y), ⌘S at SHORTCUTS, typed marks every
    0.25 s over TYPING, one move at the centre."""
    n, k = len(CLICKS), len(SHORTCUTS)
    typed, s = [], TYPING[0]
    while s < TYPING[1] - 1e-9:
        typed.append(us(s))
        s += 0.25
    typed.append(us(TYPING[1]))
    return {
        "format": "framejob-cursor", "version": 1, "in_picture": False, "source": "display",
        "display_id": 1, "source_frame": [0, 0, W * 50, H * 50], "point_size": [W * 50, H * 50],
        "pixels_per_point": 2.0, "content_size": [W, H], "movie_size": [W, H],
        "anchor": "e2", "anchor_host_us": 1000, "cursor_image": "none",
        "moves": {"t": [0], "x": [W * 25], "y": [H * 25]},
        "images": [], "image_changes": {"t": [], "id": []}, "hidden": {"from": [], "to": []},
        "clicks": {"t": [us(c[0]) for c in CLICKS], "button": [0] * n, "down": [1] * n,
                   "x": [int(c[1] * 50) for c in CLICKS], "y": [int(c[2] * 50) for c in CLICKS],
                   "count": [1] * n},
        "scrolls": {"t": [], "x": [], "y": [], "dx": [], "dy": []},
        "geometry": [{"t": 0, "screen_rect": [0, 0, W * 50, H * 50],
                      "content_rect": [0, 0, W * 50, H * 50], "content_scale": 1.0,
                      "scale_factor": 2.0}],
        "dirty": {"t": [], "x": [], "y": [], "w": [], "h": []},
        "keys": {"shortcut": {"t": [us(t) for t in SHORTCUTS], "keys": ["cmd+s"] * k,
                              "code": [1] * k},
                 "typed": {"t": typed}},
    }


def recording(files):
    """One recording's files, shared by every landing so two projects can be compared: the
    movie, its cursor file and the voice."""
    folder = WORK / "rec"
    folder.mkdir(parents=True, exist_ok=True)
    movie, cursor, voice = folder / "A.mov", folder / "A.fjcursor", folder / "A (Microphone).m4a"
    if not movie.exists():
        shutil.copyfile(files["screen"], movie)
        shutil.copyfile(files["silence"], voice)
    cursor.write_text(json.dumps(cursor_body()))
    return {"movie": str(movie), "cursor": str(cursor), "voice": [str(voice)]}


# ---- a document ----------------------------------------------------------------

class Doc:
    """One saved package on a 640 × 360, 30 fps canvas."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=W, height=H, fps=[30, 1])

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def undo_names(self, n):
        return [self.call("undo").get("undone") for _ in range(n)]

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def refusal(body):
    try:
        body()
    except mcp.ToolError as error:
        text = str(error)
        return text.split(": ", 1)[1] if ": " in text else text
    return None


def screen_clips(state, movie):
    ids = {m["id"] for m in state["media"] if m.get("path") == movie}
    return sorted(c["id"] for c in state["clips"] if (c.get("source") or {}).get("media") in ids)


def voice_media(state, rec):
    return [m["id"] for m in state["media"] if m.get("path") == rec["voice"][0]]


def by_hand(client, rec):
    """A fresh package landed with no polish, then the three tools by hand on its screen
    clips; `speed_up_typing` retried while the voice's speech is still being detected."""
    doc = Doc(client, "p1-hand")
    try:
        doc.call("land_recording", keys="shortcuts", **rec)
        clips = screen_clips(doc.state(), rec["movie"])
        doc.call("auto_zoom", clips=clips)
        doc.call("add_shortcut_overlays", clips=screen_clips(doc.state(), rec["movie"]))
        began = time.monotonic()
        while True:
            said = refusal(lambda: doc.call("speed_up_typing",
                                            clips=screen_clips(doc.state(), rec["movie"])))
            if said is None:
                break
            if "has not been detected yet" not in said or time.monotonic() - began > 300:
                raise AssertionError(f"speed_up_typing by hand refused: {said}")
            time.sleep(1)
        return doc.state()
    finally:
        doc.close()


hand_state = {}


def p1_p2(client, files):
    rec = recording(files)
    doc = Doc(client, "p1")
    try:
        answer = doc.call("land_recording", keys="shortcuts", auto_zoom=True,
                          shortcut_overlays=True, speed_up_typing=True, **rec)
        objects = {k: isinstance(answer.get(k), dict) for k in POLISH}
        errors = {k: answer.get(k + "_error") for k in POLISH if answer.get(k + "_error")}
        landed = doc.state()
        names = doc.undo_names(4)
        saved = (answer.get("speed_up_typing") or {}).get("speech_saved")
        voice = voice_media(landed, rec)
    finally:
        doc.close()
    hand = by_hand(client, rec)
    hand_state["state"] = hand
    same = landed == hand
    check("P1", all(objects.values()) and not errors and names == STEPS and same,
          f"answer objects {objects}, errors {errors}; undo {names}; get_project equal to the "
          f"hand-run package's {same}")
    check("P2", bool(voice) and saved == voice,
          f"speech_saved {saved} (the voice is media {voice})")


def p1b(client, files):
    rec = recording(files)
    doc = Doc(client, "p1b")
    try:
        answer = doc.call("land_recording", keys="shortcuts", auto_zoom=True,
                          shortcut_overlays=True, speed_up_typing=True, door="panel",
                          follow_wait=330, **rec)
        landed = doc.state()
        names = doc.undo_names(4)
    finally:
        doc.close()
    hand = hand_state.get("state")
    if hand is None:
        hand = by_hand(client, rec)
    same = landed == hand
    check("P1b", answer.get("polish_pending") is False and answer.get("enhance_pending") is False
          and names == STEPS and same,
          f"polish_pending {answer.get('polish_pending')}; undo {names}; get_project equal to "
          f"P1's {same}")


def p5(client, files):
    """#458: a nest opened while both panel follow-ups wait is busy, not a drop."""
    spoken = spoken_voice()
    if spoken is None:
        check("P5", False, "say -v Samantha could not make the spoken voice")
        return
    rec = recording(files)
    voice = WORK / "rec" / "A (Spoken).m4a"
    shutil.copyfile(spoken, voice)
    rec = {**rec, "voice": [str(voice)]}
    doc = Doc(client, "p5")
    try:
        track = doc.state()["tracks"][0]["id"]
        silence = doc.call("import_media", path=str(files["silence"]))["media"]
        inner = doc.call("add_clip", track=track, media=silence, at=60 * 600_000)["new_clips"][0]
        doc.call("nest", clips=[inner])
        nest = doc.state()["nests"][0]["id"]
        answer = doc.call("land_recording", door="panel", enhance=True, auto_zoom=True, **rec)
        doc.call("set_scope", nest=nest)
        time.sleep(3)
        doc.call("set_scope")
        began = time.monotonic()
        zoomed = False
        while time.monotonic() - began < 300:
            state = doc.state()
            clips = [c for c in state["clips"] if c["id"] in screen_clips(state, rec["movie"])]
            if clips and any(c.get("actions") for c in clips):
                zoomed = True
                break
            time.sleep(1)
        took = time.monotonic() - began
        time.sleep(1)
        names = doc.undo_names(3)
    finally:
        doc.close()
    upto = names[:names.index("Add Recording") + 1] if "Add Recording" in names else names
    check("P5", answer.get("landed") == "document" and zoomed and upto in NESTED_STEPS,
          f"landed {answer.get('landed')!r}; Auto Zoom's actions seen {zoomed} after "
          f"{took:.0f} s; undo {names} (want one of {NESTED_STEPS} to Add Recording)")


def p3_p4(client, files):
    rec = recording(files)
    said = refusal(lambda: client.call("record_screen", seconds=1, source="voice_over",
                                       auto_zoom=True))
    check("P3", said == SENTENCES["voice"], f"record_screen voice_over: {said!r}")
    said = refusal(lambda: client.call("land_recording", voice=rec["voice"], auto_zoom=True))
    check("P3", said == SENTENCES["movie"], f"land_recording without movie: {said!r}")
    doc = Doc(client, "p4")
    try:
        before = doc.state()
        rows = [
            ("record_screen place false", "zoom_place",
             lambda: doc.call("record_screen", seconds=1, auto_zoom=True, place=False)),
            ("record_screen no keys", "speed_keys",
             lambda: doc.call("record_screen", seconds=1, speed_up_typing=True)),
            ("land_recording place false", "zoom_place",
             lambda: doc.call("land_recording", auto_zoom=True, place=False, **rec)),
            ("land_recording no keys", "speed_keys",
             lambda: doc.call("land_recording", speed_up_typing=True, **rec)),
        ]
        for name, want, body in rows:
            said = refusal(body)
            check("P4", said == SENTENCES[want], f"{name}: {said!r}")
        check("P4", doc.state() == before, "the project unchanged by the four refusals")
    finally:
        doc.close()


# ---- launches ------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def plain_rows(client, files):
    if {"P1", "P2"} & selected:
        attempt(lambda: p1_p2(client, files), *({"P1", "P2"} & selected))
    if {"P3", "P4"} & selected:
        attempt(lambda: p3_p4(client, files), *({"P3", "P4"} & selected))


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

def edited(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def run_mutant(name):
    global selected
    named, _ = MUTANTS[name]
    print(f"CU10 — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
    selected = set(named) | {"Z0"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    why = why or edited(name, Path(made))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, why = tree_copy.build_app(made, BUILD_BOUND)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    files = media()
    if not with_instance(proof_app.executable(app), [], "mutant",
                         lambda c: attempt(lambda: p1_p2(c, files), "P1")):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
    if not set(named) & set(results):
        print(f"mutant {name}: the control could not be performed — its rows were never scored")
        return 2
    caught = [r for r in named if r in results and not all(ok for ok, _ in results[r])]
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


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
        selected.add("Z0")
    if WORK.exists():
        for child in WORK.iterdir():
            if child.name not in KEEP:
                tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)

    print(f"CU10 — the recorder polishes on landing ({proof_app.config()} build)", flush=True)
    files = media()
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    if selected & set(PLAIN):
        if args.socket:
            client = mcp.MCP(args.socket, timeout=CALL_BOUND)
            plain_rows(client, files)
            parity(Path(args.socket).parent / "framejob.log", "the given instance")
        elif not with_instance(binary, [], "plain", lambda c: plain_rows(c, files)):
            for row in selected & set(PLAIN):
                check(row, False, "the app did not listen (plain)")
    if "P1b" in selected:
        if not with_instance(binary, PANEL_ARGS, "panel",
                             lambda c: attempt(lambda: p1b(c, files), "P1b")):
            check("P1b", False, "the app did not listen (panel)")
    if "P5" in selected:
        if not with_instance(binary, PANEL_ARGS, "nested",
                             lambda c: attempt(lambda: p5(c, files), "P5")):
            check("P5", False, "the app did not listen (nested)")

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
