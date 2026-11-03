#!/usr/bin/env python3
"""Road map "creator-jobs" CU9b — Clip ▸ Speed Up Typing… and `speed_up_typing`
(spec §11 CU-91…CU-94).

    python3 tools/proof/cu9b_proof.py [SOCKET] [--only R3,R9,…] [--mutant NAME] [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the
plain rows launch their own instance. R12 always launches its own, with
`-RCDevSpeedUpTypingAccept YES -FrameJobSpeedUpTypingRate 6` (launch arguments only: nothing
is written to the defaults domain). Launches run on a scratch `CFFIXED_USER_HOME`; packages
and media are made under `tools/proof/work/cu9b/`. The movie is ffmpeg's `testsrc` (640 × 360,
30 fps, 20 s, no sound) with a v1 cursor file beside it written here per
`core/src/cursor_file.rs`, its `keys.typed` marks every 0.25 s over each stretch and its
`keys.shortcut` filled (`import_media` attaches it, CU-34); the microphones are a 660 Hz tone
and 20 s of silence. A frame is 20 000 ticks. Every expected tick is worked by hand from
CU-91: a stretch [a, b) less speech and overlays, kept when ≥ shortest, sped over
[a + 0.3 s, b − 0.3 s).

Rows:
- Z0 `grep "Frame Job: "` of every instance's log prints nothing.
- R3 typing 1.0–9.0 s on the screen, a microphone on another track whose speech is set to
  [4.0, 5.0) s by `set_media_speech`: ranges [1.3, 3.7) and [5.3, 8.7) s.
- R9 typing 0.5–10.5 s with ⌘S at 4.0 s: ranges [0.8, 3.7) and [5.8, 10.2) s ([4.0, 5.5)
  kept at ×1); after `add_shortcut_overlays {duration: 3}` (a Shortcuts-track clip [4.0, 7.0)):
  [0.8, 3.7) and [7.3, 10.2) s.
- R10 typing 2.0–8.3 s: in `get_project` the screen is [0, 2.3) at ×1, [2.3, 3.7333) s at ×4
  from source 2.3 s, then ×1 from source 8.0 s at frame 112 (2.3 + 5.7 ÷ 4 = 3.725 s → 112).
- R11 one undo names "Speed Up Typing" and gives back `get_project`'s project exactly,
  including the `media.speech` R14's step wrote.
- R12 Clip ▸ Speed Up Typing… by `perform_menu_item` on the accept instance (Rate 6 by launch
  argument) gives the project `speed_up_typing {rate: 6}` gives after one undo.
- R13 refusals by sentence: reversed, not a media clip, no cursor file, rate 9, shortest 0.5,
  a locked track after the range (the all-or-nothing sentence); and typing 2.0–4.0 s: `ok`,
  the note, no undo step.
- R14 the silent microphone with no stored speech under the typing: the step writes its spans
  (`speech_saved` names it; `get_project` has its `speech`). A "not detected yet" refusal while
  the import's pass runs is retried for up to 120 s.
- R15 one recording split at 10 s into A and B, typing 8.0–12.5 s, both clips, shortest 3:
  ONE range [8.3, 12.2) s on the grid, `short` 0.
- P1, P2 `cu9b_probe.swift` (built with `swift_build.build()`): the speech step's five answers;
  `gaveUp(waitingFor:)` false at 299 s, true at 300 s.

`--mutant NAME`: the named decision broken. A core mutant edits a copy of `core/` (beside a
link to `graphic/`) and runs `cargo test --release --test speed_up_typing`: CAUGHT when one
of its named tests fails. A probe mutant edits a copy of `app/Sources` and runs P1/P2 on it.
`sheet-rate-not-passed` edits a `tree_copy.py` copy and runs R12 on its built app. CAUGHT
exits 1, SURVIVED exits 0, a control that could not be performed exits 2.
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
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/cu9b"
HOME = WORK / "home"
KEEP = {"media", "mutant-target"}
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_WALL = 240
W, H = 640, 360
NOTE = ("no typing stretch without speech or a shortcut lasted 3 s or more in the clips' "
        "played windows, so nothing was changed")
PLAIN = ["R3", "R9", "R10", "R11", "R13", "R14", "R15"]
PROBE = ["P1", "P2"]
ACCEPT = ["R12"]
ROWS = ["Z0"] + PLAIN + ACCEPT + PROBE

TYPING = "core/src/cursor_typing.rs"
SPEECH = "app/Sources/SpeedUpTyping.swift"
SHEET = "app/Sources/SpeedUpTypingSheetController.swift"
# name → (rows or core test prefixes, [(path, anchor, replacement)], "core", "probe" or "app")
MUTANTS = {
    "speech-ignored": (["r3_"], [(
        TYPING, "speech.into_iter().chain(overlays).collect();",
        "overlays.into_iter().chain(speech.into_iter().take(0)).collect();")], "core"),
    "margins-dropped": (["r10_"], [(TYPING, "seconds_to_ticks(MARGIN));", "0);")], "core"),
    "shortcut-inside": (["r9_"], [(
        TYPING, "speech.into_iter().chain(overlays).collect();",
        "speech.into_iter().chain(overlays.into_iter().take(0)).collect();")], "core"),
    "needs-speech-skipped": (["a_media_with_sound"], [(
        TYPING, "    if !needs.is_empty() {", "    if false && !needs.is_empty() {")], "core"),
    "left-to-right": (["sync_across"], [(
        TYPING, "for &(from, to) in ranges.iter().rev() {", "for &(from, to) in ranges.iter() {")],
        "core"),
    "no-prevalidation": (["a_plan_one_range"], [(
        TYPING, "Ok(Outcome::Refused(why)) | Err(why) => return Err(refused(why)),",
        "Ok(Outcome::Refused(why)) | Err(why) => {\n                let _ = refused(why);\n"
        "            }")], "core"),
    "shortest-per-clip": (["r15_"], [(
        TYPING, "for (a, b) in united(pieces) {", "for (a, b) in pieces {")], "core"),
    "presses-window-filtered": (["a_press_before_from"], [(
        TYPING, "overlays.extend(overlay_spans(project, clip, tracks[i]));",
        "overlays.extend(\n            overlay_spans(project, clip, tracks[i])\n"
        "                .into_iter()\n                .filter(|s| s.0 >= window.0),\n"
        "        );")], "core"),
    "unavailable-as-pending": (["P1"], [(
        SPEECH, "} else if available {", "} else if true || available {")], "probe"),
    "wait-unbounded": (["P2"], [(
        SPEECH, "        elapsed >= waitLimit\n", "        false && elapsed >= waitLimit\n")],
        "probe"),
    # The planner is handed the default rate; what is remembered is still the controls', so
    # the mutant writes no key (the DEFAULTS MOVED guard).
    "sheet-rate-not-passed": (["R12"], [(
        SHEET, "cacheDirectory: document.cacheDirectory, settings: settings, from: nil, to: nil)",
        "cacheDirectory: document.cacheDirectory, settings: SpeedUpTypingSettings(),\n"
        "                from: nil, to: nil)")], "app"),
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


def t(seconds):
    """Seconds to ticks."""
    return int(round(seconds * SEC))


# ---- media and cursor files ----------------------------------------------------

def media():
    folder = WORK / "media"
    folder.mkdir(parents=True, exist_ok=True)
    made = {
        "screen.mov": ["-f", "lavfi", "-i", f"testsrc=size={W}x{H}:rate=30:duration=20",
                       "-c:v", "libx264", "-pix_fmt", "yuv420p", "-g", "30", "-bf", "0"],
        "tone.m4a": ["-f", "lavfi", "-i", "sine=frequency=660:duration=20:sample_rate=48000",
                     "-c:a", "aac"],
        "silence.m4a": ["-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono", "-t", "20",
                        "-c:a", "aac"],
    }
    for name, args in made.items():
        out = folder / name
        if not out.exists():
            subprocess.run(["ffmpeg", "-v", "error", "-y", *args, str(out)], check=True,
                           timeout=300, env=bounded.child_env())
    return {name.split(".")[0]: folder / name for name in made}


def typing(*stretches):
    """Typed marks (µs) every 0.25 s over each `(a, b)` seconds, `b` included."""
    out = []
    for a, b in stretches:
        s = a
        while s < b - 1e-9:
            out.append(int(round(s * 1e6)))
            s += 0.25
        out.append(int(round(b * 1e6)))
    return out


def cursor_body(typed, shortcuts=()):
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
        "keys": {"shortcut": {"t": [int(round(s * 1e6)) for s in shortcuts],
                              "keys": ["cmd+s"] * n, "code": [1] * n},
                 "typed": {"t": typed}},
    }


def recording(files, name, typed, shortcuts=(), cursor=True):
    """`<WORK>/rec/<name>/A.mov` with its `A.fjcursor` beside (unless `cursor` is false)."""
    folder = WORK / "rec" / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / "A.mov"
    shutil.copyfile(files["screen"], path)
    if cursor:
        (folder / "A.fjcursor").write_text(json.dumps(cursor_body(typed, shortcuts)))
    return path


def sound(files, kind, name):
    """A copy of the tone or the silence under its own name (its own media)."""
    folder = WORK / "rec" / name
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / f"{kind}.m4a"
    shutil.copyfile(files[kind], path)
    return path


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

    def track(self, index=0):
        tracks = self.state()["tracks"]
        while len(tracks) <= index:
            self.call("add_track")
            tracks = self.state()["tracks"]
        return tracks[index]["id"]

    def place(self, path, index=0, at=0):
        m = self.call("import_media", path=str(path))["media"]
        clip = self.call("add_clip", track=self.track(index), media=m, at=at)["new_clips"][0]
        return clip, m

    def pieces(self, track, state=None):
        state = state or self.state()
        return sorted(((c["start"], c["duration"], c.get("speed", 1.0),
                        (c.get("source") or {}).get("in"))
                       for c in state["clips"] if c["track"] == track), key=lambda p: p[0])

    def typing(self, **arguments):
        return self.call("speed_up_typing", **arguments)

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
        prefix = "speed_up_typing: "
        return text[len(prefix):] if text.startswith(prefix) else text
    return None


def ranges(answer):
    return [(r["from"], r["to"]) for r in answer.get("ranges", [])]


def seconds(pairs):
    return [(round(a / SEC, 4), round(b / SEC, 4)) for a, b in pairs]


# ---- the rows ------------------------------------------------------------------

def r3(client, files):
    doc = Doc(client, "r3")
    try:
        screen, _ = doc.place(recording(files, "r3", typing((1.0, 9.0))))
        _, tone = doc.place(sound(files, "tone", "r3-tone"), index=1)
        doc.call("set_media_speech", media=tone, spans=[[t(4.0), t(5.0)]])
        answer = doc.typing(clip=screen)
        want = [(t(1.3), t(3.7)), (t(5.3), t(8.7))]
        check("R3", ranges(answer) == want and answer.get("speech_saved") == [],
              f"ranges {seconds(ranges(answer))} (want {seconds(want)}); speech_saved "
              f"{answer.get('speech_saved')}")
    finally:
        doc.close()


def r9(client, files):
    for tag, overlay, want in (
            ("fallback", False, [(t(0.8), t(3.7)), (t(5.8), t(10.2))]),
            ("overlay", True, [(t(0.8), t(3.7)), (t(7.3), t(10.2))])):
        doc = Doc(client, f"r9-{tag}")
        try:
            clip, _ = doc.place(recording(files, f"r9-{tag}", typing((0.5, 10.5)), [4.0]))
            if overlay:
                placed = doc.call("add_shortcut_overlays", clip=clip, duration=3)
                spans = [(o["at"], o["at"] + o["duration"]) for o in placed.get("overlays", [])]
                assert spans == [(t(4.0), t(7.0))], f"the overlay is {seconds(spans)}"
            answer = doc.typing(clip=clip)
            check("R9", ranges(answer) == want,
                  f"{tag}: ranges {seconds(ranges(answer))} (want {seconds(want)})")
        finally:
            doc.close()


def r10(client, files):
    doc = Doc(client, "r10")
    try:
        clip, _ = doc.place(recording(files, "r10", typing((2.0, 8.3))))
        track = doc.track(0)
        doc.typing(clip=clip)
        got = doc.pieces(track)
        sped_to = 112 * FRAME
        want = [(0, t(2.3), 1.0, 0), (t(2.3), sped_to - t(2.3), 4.0, t(2.3)),
                (sped_to, None, 1.0, t(8.0))]
        ok = len(got) == 3 and all(
            g[0] == w[0] and (w[1] is None or g[1] == w[1]) and g[2] == w[2] and g[3] == w[3]
            for g, w in zip(got, want))
        check("R10", ok, f"pieces (start, duration, speed, in) {got}; want {want}")
    finally:
        doc.close()


def r11_r14(client, files):
    doc = Doc(client, "r14")
    try:
        screen, _ = doc.place(recording(files, "r14", typing((2.0, 8.3))))
        _, quiet = doc.place(sound(files, "silence", "r14-silence"), index=1)
        before = doc.state()
        answer, refused, began = None, [], time.monotonic()
        while answer is None and time.monotonic() - began < 120:
            got = []
            said = refusal(lambda: got.append(doc.typing(clip=screen)))
            if said is None:
                answer = got[0]
            elif "has not been detected yet" in said:
                refused.append(said)
                time.sleep(1)
            else:
                raise AssertionError(f"refused: {said}")
        assert answer is not None, f"still not detected after 120 s: {refused[-1:]}"
        after = doc.state()
        row = next(m for m in after["media"] if m["id"] == quiet)
        check("R14", answer.get("speech_saved") == [quiet] and "speech" in row
              and ranges(answer) == [(t(2.3), t(8.0))],
              f"speech_saved {answer.get('speech_saved')} (the silence is {quiet}); its "
              f"speech {row.get('speech')}; ranges {seconds(ranges(answer))}; "
              f"{len(refused)} 'not detected yet' refusals first")
        undone = doc.call("undo").get("undone")
        back = doc.state()
        restored = back == before
        gone = "speech" not in next(m for m in back["media"] if m["id"] == quiet)
        check("R11", undone == "Speed Up Typing" and restored and gone,
              f"undo named {undone!r}; get_project equal to before {restored}; the speech "
              f"gone again {gone}")
    finally:
        doc.close()


def r13(client, files):
    doc = Doc(client, "r13")
    try:
        clip, _ = doc.place(recording(files, "r13", typing((2.0, 8.3))))
        cases = [
            ("rate 9", dict(clip=clip, rate=9), lambda s: s == "Rate is ×9; it runs ×2–×8."),
            ("shortest 0.5", dict(clip=clip, shortest=0.5),
             lambda s: s == "Shortest is 0.5 s; it runs 1–30."),
        ]
        for tag, arguments, good in cases:
            said = refusal(lambda: doc.call("speed_up_typing", **arguments))
            check("R13", said is not None and good(said), f"{tag}: {said!r}")
        text = doc.call("add_text_clip", track=doc.track(0), at=t(25.0))["new_clips"][0]
        said = refusal(lambda: doc.call("speed_up_typing", clip=text))
        check("R13", said is not None and said.startswith(f"Clip {text} is not a media clip"),
              f"text clip: {said!r}")
        bare, _ = doc.place(recording(files, "r13-bare", [], cursor=False), at=t(30.0))
        said = refusal(lambda: doc.call("speed_up_typing", clip=bare))
        check("R13", said is not None and "has no cursor file" in said, f"no cursor: {said!r}")
        locked = doc.track(1)
        doc.call("add_text_clip", track=locked, at=t(15.0))
        doc.call("set_track", track=locked, locked=True)
        before = doc.state()
        said = refusal(lambda: doc.call("speed_up_typing", clip=clip))
        head = f"The typing from {t(2.3)} to {t(8.0)} ticks cannot be sped up: "
        check("R13", said is not None and said.startswith(head) and "locked" in said
              and doc.state() == before,
              f"a locked track after the range: {said!r}; unchanged {doc.state() == before}")
        doc.call("set_track", track=locked, locked=False)
        doc.call("set_reversed", clip=clip, reversed=True)
        said = refusal(lambda: doc.call("speed_up_typing", clip=clip))
        want = (f"Clip {clip} plays reversed; Speed Up Typing speeds only clips that play "
                "forward.")
        check("R13", said == want, f"reversed: {said!r}")
    finally:
        doc.close()
    doc = Doc(client, "r13-short")
    try:
        clip, _ = doc.place(recording(files, "r13-short", typing((2.0, 4.0))))
        before = doc.state()
        answer = doc.typing(clip=clip)
        same = doc.state() == before
        undone = doc.call("undo").get("undone")
        check("R13", answer.get("ok") is True and answer.get("note") == NOTE and same
              and answer.get("short") == 1 and undone != "Speed Up Typing",
              f"typing 2.0–4.0 s: note {answer.get('note')!r}; short {answer.get('short')}; "
              f"unchanged {same}; the next undo {undone!r}")
    finally:
        doc.close()


def r15(client, files):
    doc = Doc(client, "r15")
    try:
        a, _ = doc.place(recording(files, "r15", typing((8.0, 12.5))))
        doc.call("split", clips=[a], at=t(10.0))
        track = doc.track(0)
        ids = [c["id"] for c in sorted(doc.state()["clips"], key=lambda c: c["start"])
               if c["track"] == track]
        answer = doc.typing(clips=ids, shortest=3)
        got = ranges(answer)
        on_grid = all(x % FRAME == 0 for pair in got for x in pair)
        check("R15", len(ids) == 2 and got == [(t(8.3), t(12.2))] and on_grid
              and answer.get("short") == 0 and len(answer.get("ranges", [])) == 1,
              f"clips {ids}; ranges {seconds(got)} on the grid {on_grid}; short "
              f"{answer.get('short')}")
    finally:
        doc.close()


def r12(client, files):
    doc = Doc(client, "r12")
    try:
        clip, _ = doc.place(recording(files, "r12", typing((2.0, 8.3), (12.0, 17.0))))
        doc.call("set_selection", clips=[clip])
        before = doc.state()
        pressed = doc.call("perform_menu_item", path=["Clip", "Speed Up Typing…"])
        began = time.monotonic()
        while time.monotonic() - began < 30 and doc.state() == before:
            time.sleep(0.25)
        menu = doc.state()
        undone = doc.call("undo").get("undone")
        back = doc.state() == before
        doc.typing(clip=clip, rate=6)
        tool = doc.state()
        check("R12", menu != before and undone == "Speed Up Typing" and back and menu == tool,
              f"perform_menu_item ok {pressed.get('ok')}; the project changed "
              f"{menu != before}; undo named {undone!r}, back {back}; equal to "
              f"speed_up_typing {{rate: 6}} {menu == tool}")
    finally:
        doc.close()


# ---- the probe -----------------------------------------------------------------

def probe_rows(sources):
    here = WORK / "probe"
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    shutil.copyfile(HERE / "cu9b_probe.swift", entry)
    binary = here / "cu9b-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary)
    except swift_build.SwiftBuildFailed as error:
        for row in PROBE:
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    request = here / "request.json"
    request.write_text(json.dumps({"work": str(here / "rows")}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=PROBE_WALL, env=bounded.child_env(
                                 {"CFFIXED_USER_HOME": str(HOME)}))
    except subprocess.TimeoutExpired:
        for row in PROBE:
            check(row, False, f"the probe gave no answer within {PROBE_WALL} s")
        return
    (here / "stderr.txt").write_text(run.stderr)
    try:
        rows = {r["id"]: r for r in json.loads(run.stdout)["rows"]}
    except (ValueError, KeyError):
        rows = {}
    for row in PROBE:
        answer = rows.get(row)
        if answer is None:
            check(row, False, f"the probe did not answer it (exit {run.returncode})")
        else:
            check(row, answer["pass"], answer["detail"])


# ---- launches ------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def plain_rows(client, files):
    for names, body in ((["R3"], r3), (["R9"], r9), (["R10"], r10), (["R11", "R14"], r11_r14),
                        (["R13"], r13), (["R15"], r15)):
        if set(names) & selected:
            attempt(lambda body=body: body(client, files), *(set(names) & selected))


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


ACCEPT_ARGS = ["-RCDevSpeedUpTypingAccept", "YES", "-FrameJobSpeedUpTypingRate", "6"]


# ---- mutants -------------------------------------------------------------------

def edited(name, root):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def core_mutant(name):
    copy = WORK / "mutant-core"
    if copy.exists():
        tree_copy.remove_tree(str(copy))
    copy.mkdir(parents=True)
    shutil.copytree(ROOT / "core", copy / "core", ignore=shutil.ignore_patterns("target"))
    os.symlink(ROOT / "graphic", copy / "graphic")
    why = edited(name, copy)
    if why:
        return None, why
    env = bounded.child_env({"CARGO_TARGET_DIR": str(WORK / "mutant-target")})
    run = subprocess.run(["cargo", "test", "--release", "--test", "speed_up_typing"],
                         cwd=copy / "core", capture_output=True, text=True,
                         timeout=BUILD_BOUND, env=env)
    (WORK / f"mutant-{name}.log").write_text(run.stdout + run.stderr)
    failed = [line.split()[1] for line in run.stdout.splitlines()
              if line.startswith("test ") and line.endswith("FAILED")]
    if run.returncode != 0 and not failed:
        return None, "cargo test did not run the tests (see the log)"
    return failed, None


def run_mutant(name):
    global selected
    named, _, kind = MUTANTS[name]
    print(f"CU9b — the {name} MUTANT ({', '.join(named)} must FAIL)", flush=True)
    if kind == "core":
        failed, why = core_mutant(name)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        caught = [f for f in failed if any(f.startswith(p) for p in named)]
        print(f"failing tests: {failed or 'none'}")
        print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(named)} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    selected = set(named) | {"Z0"}
    if kind == "probe":
        copy = WORK / "mutant-sources"
        if copy.exists():
            tree_copy.remove_tree(str(copy))
        shutil.copytree(ROOT / "app/Sources", copy / "app/Sources")
        why = edited(name, copy)
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        probe_rows(copy / "app/Sources")
    else:
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
        if not with_instance(proof_app.executable(app), ACCEPT_ARGS, "mutant",
                             lambda c: attempt(lambda: r12(c, files), "R12")):
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

    print(f"CU9b — Speed Up Typing ({proof_app.config()} build)", flush=True)
    if selected & set(PROBE):
        attempt(lambda: probe_rows(ROOT / "app/Sources"), *(selected & set(PROBE)))
    if selected & set(PLAIN + ACCEPT):
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
        if "R12" in selected:
            if not with_instance(binary, ACCEPT_ARGS, "accept",
                                 lambda c: attempt(lambda: r12(c, files), "R12")):
                check("R12", False, "the app did not listen (accept)")

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
