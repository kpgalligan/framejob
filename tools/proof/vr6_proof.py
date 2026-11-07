#!/usr/bin/env python3
"""Road map "creator-jobs" VR6a — `reframe_clip {follow: speaker}`: a two-shot framed on whoever
speaks (spec §11 VR-60…VR-63), over F-TURNS' two microphones (SW-27).

    python3 tools/proof/vr6_proof.py [--only P1,P3,…] [--mutant NAME]

The rows run on one instance launched `-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600` on a
scratch `CFFIXED_USER_HOME` (canned analyses honoured, no job beside a canned marker). F-TURNS is
`creator_spike/f_turns.py`'s (run first, reused while its manifest's generator hash holds);
without `say -v Samantha` or `Daniel` it exits 2 and every row is skipped by name.

Each framing document is built over MCP on a 1080 × 1920, 30 fps canvas: `cam_wide.mov` (the
two-shot) on track "Wide", `mic_a_b12_f55.wav` on "Mic A" and `mic_b_b12_f55.wav` on "Mic B", all
at 0. The wide's `shots`, `faces` and `subjects` are canned (`canned_framing.write` with
`landmarks`): two still faces, face 1 centred at x 0.42 and face 2 at 0.58 of the picture, y 0.4,
each mouth's gap alternating 0.05/0.20 of width 0.5 per sample inside its speaker's utterances
(`turns[].onset_seconds…end_seconds`, both for crosstalk) and 0.05 outside. Packages live under
`tools/proof/work/vr6/`. A frame is 20 000 ticks. Every expected number is worked here from the
manifest or from `switch_by_speaker`'s answer, never read back from the code under test.

The placement a framing gives at clip time t is the base `video` while no action has ended, else
the last ended action's end `{scale, x}` (the cuts are one-frame `linear` actions and the faces
never move, so no other action is written); a face at picture x px lands on the canvas at
540 + x + scale·(px − 960), inside the window's central 60 % across when within 324 px of 540.

Rows:
- P0 `grep "Frame Job: "` of the instance's log prints nothing.
- P1 `{follow: speaker, mics: [A, B]}` applies; one undo step "Reframe Clip" gives back the
  project; its cut keys (each one-frame action's end) equal, each within one frame, the shot
  starts of `switch_by_speaker {apply: false, min_shot: 2}` over the same microphones with
  F-TURNS' Wide, Cam B and Cam A angles (a second document, 1920 × 1080) from its first person
  shot on.
- P2 at each segment's middle the speaker's face (both faces for the wide) is inside the central
  60 % across, and for one speaker the other face is outside it (cam_a → face 1, cam_b → face 2).
- P3 the mouths swapped between the faces: B's segments frame face 1.
- P4 the mouths constant: refused naming face 1 at 42 % and face 2 at 58 %, nothing changed;
  then `mic_faces: [2, 1]` applies and A's segments frame face 2.
- P5 `get_project`'s `media` byte-identical before and after P1.
- P6 the refusals in their sentences, nothing changed: `mics: [A]`, `[A, A]`, the two-shot as a
  microphone, `mic_faces: [1]`, a canned cut inside the clip (frame 300, 00:00:10:00), Mic A's
  loudness cache removed (SW-24's "still being analyzed"), Mic B's sound off with `mic_faces:
  [1, 2]` given (the sound-off sentence naming Mic B).

`--mutant NAME` runs the named row on a mutated build: CAUGHT exits 1, SURVIVED 0, a control that
could not be performed 2. A Swift mutant edits a `tree_copy.py` copy and builds its app; a core
mutant edits the tree's own `core/src` (the copy links the tree's core), runs
`core/tests/reframe_speaker.rs` and `make app-debug`, and restores each file by its SHA-256
(rebuild the app after). Six mutants (VR-63).
"""

import argparse
import hashlib
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
import canned_framing  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/vr6"
FTURNS = ROOT / "tools/proof/media/creator/f_turns"
HOME = WORK / "home"
KEEP = {"mutant-target"}
SEC = 600_000
FRAME = 20_000
MIC_A = "mic_a_b12_f55.wav"
MIC_B = "mic_b_b12_f55.wav"
CALL_BOUND = 900
CACHE_BOUND = 900
BUILD_BOUND = 1800
F1, F2 = 0.42, 0.58                     # the faces' centres, 0…1 across
PICTURE = (1920, 1080)
CANVAS = (1080, 1920)
CENTRAL = 0.3 * CANVAS[0]               # half the central 60 % across
REFRAME = "Reframe Clip"
CANNED = ["-RCDevAnalysisCanned", "YES", "-RCDevAnalysisHold", "3600"]
ROWS = ["P0", "P1", "P2", "P3", "P4", "P5", "P6"]
CUT_FRAME = 300

SPEAKER_RS = "core/src/reframe_speaker.rs"
SUBJECTS = "app/Sources/FramingSubjects.swift"
TURNS = "app/Sources/SpeakerSwitch+Turns.swift"
# name → (row, kind, [(path, anchor, replacement)])
MUTANTS = {
    "hold-removed": ("P1", "core", [(SPEAKER_RS, "while out.len() > 1 {",
                                     "while out.len() > usize::MAX {")]),
    "assignment-transposed": ("P3", "core", [(
        SPEAKER_RS, "None if found.sure => found.assignment.clone(),",
        "None if found.sure => found.assignment.iter().rev().copied().collect(),")]),
    "both-never-kept": ("P1", "core", [(SPEAKER_RS, "Some(if fits(current, other, a, b) {",
                                        "Some(if false && fits(current, other, a, b) {")]),
    "sure-ignored": ("P4", "core", [(SPEAKER_RS, "None if found.sure =>",
                                     "None if found.sure || true =>")]),
    "mouth-unfilled": ("P1", "swift", [(
        SUBJECTS, "if index < mouths.count, let mouth = mouths[index] {",
        "if false, index < mouths.count, let mouth = mouths[index] {")]),
    "lead-dropped": ("P1", "swift", [(
        TURNS, "input.from + Ticks(run.start) * step - ticks(settings.lead), fps: input.fps))",
        "input.from + Ticks(run.start) * step - 0, fps: input.fps))")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def skip(name, why):
    if name in selected:
        results.setdefault(name, []).append(("skip", why))
        print(f"  skip {name} {why}", flush=True)


def attempt(body, *names):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        for name in names:
            check(name, False, f"{type(error).__name__}: {error}")
        return None


def refused(body):
    try:
        body()
    except mcp.ToolError as error:
        return str(error)
    return None


def model(state):
    return {k: state.get(k) for k in ("canvas", "tracks", "clips", "media", "markers", "nests")}


# ---- the fixture -------------------------------------------------------------------

def fturns():
    """The manifest, or None when F-TURNS is skipped by name (no voice)."""
    run = subprocess.run([sys.executable, str(HERE / "creator_spike/f_turns.py")],
                         capture_output=True, text=True, timeout=3600)
    print("  " + run.stdout.strip(), flush=True)
    if run.returncode == 2:
        return None
    if run.returncode != 0:
        raise RuntimeError("f_turns.py failed: " + (run.stderr or run.stdout)[-800:])
    return json.loads((FTURNS / "manifest.json").read_text())


def utterances(manifest, who):
    """`who`'s utterances in timeline seconds; crosstalk counts for both."""
    return [(turn["onset_seconds"], turn["end_seconds"]) for turn in manifest["turns"]
            if turn["speaker"] in (who, "both")]


def two_faces(manifest, one, two):
    """faces_at for the wide: face 1 talks in `one`'s utterances, face 2 in `two`'s; a speaker
    of None never moves its mouth."""
    spans = {1: utterances(manifest, one) if one else [],
             2: utterances(manifest, two) if two else []}

    def faces_at(t_media):
        k = int(round(t_media * canned_framing.SAMPLES_PER_SECOND))
        out = []
        for n, cx in ((1, F1), (2, F2)):
            box = dict(canned_framing.face(cx * PICTURE[0], 0.4 * PICTURE[1]))
            inside = any(a <= t_media < b for a, b in spans[n])
            box["gap"] = (0.05 if k % 2 == 0 else 0.20) if inside else 0.05
            box["width"] = 0.5
            out.append(box)
        return out
    return faces_at


class Doc:
    """A saved package over MCP; `framing` builds the 1080 × 1920 two-shot with Mic A and Mic B
    and cans the wide's analyses, else the 1920 × 1080 switch document with F-TURNS' angles."""

    def __init__(self, client, manifest, name, mouths=("a", "b"), cut=False, framing=True):
        self.client = client
        self.manifest = manifest
        self.path = WORK / f"{name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            size = CANVAS if framing else PICTURE
            try:
                self.call("set_canvas", width=size[0], height=size[1], fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            self.save()
            first = self.state()["tracks"][0]["id"]
            self.call_with("set_track", {"track": first, "name": "Wide"})
            names = ["Mic B", "Mic A"] if framing else ["Cam B", "Cam A", "Mic B", "Mic A"]
            ids = {"Wide": first}
            for title in names:
                ids[title] = self.call_with("add_track", {"name": title})["new_tracks"][0]
            self.wide_track = first
            self.c_wide, self.m_wide = self.place(FTURNS / "cam_wide.mov", first)
            clips = [self.c_wide]
            if not framing:
                self.b_track, self.a_track = ids["Cam B"], ids["Cam A"]
                clips.append(self.place(FTURNS / "cam_b.mov", self.b_track)[0])
                c_a1, _ = self.place(FTURNS / "cam_a_1.mov", self.a_track)
                clips.append(c_a1)
                clips.append(self.place(FTURNS / "cam_a_2.mov", self.a_track,
                                        at=self.end(c_a1))[0])
            self.mic_b_track, self.mic_a_track = ids["Mic B"], ids["Mic A"]
            self.c_b, self.m_b = self.place(FTURNS / MIC_B, self.mic_b_track)
            self.c_a, self.m_a = self.place(FTURNS / MIC_A, self.mic_a_track)
            self.clips = clips + [self.c_b, self.c_a]
            if framing:
                self.can(two_faces(manifest, *mouths), cut)
        except Exception:
            self.close()
            raise

    def can(self, faces_at, cut):
        """The wide's canned analyses, written once the import pass has made `cache/`."""
        deadline = time.monotonic() + 120
        while not (self.path / "cache").is_dir():
            if time.monotonic() > deadline:
                raise RuntimeError(f"{self.path}/cache was never made")
            time.sleep(0.5)
        duration = {m["id"]: m["duration"] for m in self.state()["media"]}[self.m_wide]
        canned_framing.write(self.path, self.m_wide, FTURNS / "cam_wide.mov", duration, [30, 1],
                             faces_at, cut_frames=(CUT_FRAME,) if cut else (), landmarks=True)

    def call(self, tool, **arguments):
        return self.call_with(tool, arguments)

    def call_with(self, tool, arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def place(self, path, track, at=0):
        media = self.call("import_media", path=str(path))["media"]
        return self.call("add_clip", track=track, media=media, at=at)["new_clips"][0], media

    def clip(self, cid, state=None):
        return next(c for c in (state or self.state())["clips"] if c["id"] == cid)

    def end(self, cid, state=None):
        c = self.clip(cid, state)
        return c["start"] + c["duration"]

    def frame(self, **arguments):
        """`reframe_clip {follow: speaker, mics: [A, B]}` plus `arguments`, polled while a
        microphone is still being analyzed (the import's caches)."""
        call = {"clip": self.c_wide, "follow": "speaker", "mics": [self.c_a, self.c_b],
                **arguments}
        deadline = time.monotonic() + CACHE_BOUND
        while True:
            try:
                return self.call_with("reframe_clip", call)
            except mcp.ToolError as error:
                if "still being analyzed" not in str(error) or time.monotonic() > deadline:
                    raise
            time.sleep(2)

    def save(self):
        self.call("save_project")

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


# ---- reading a framing back -------------------------------------------------------

def cut_keys(clip):
    """Each one-frame action's end, in timeline ticks (the clip starts at 0)."""
    return sorted(a["start"] + a["duration"] for a in clip.get("actions") or []
                  if a["duration"] == FRAME)


def placement(clip, t):
    """(scale, x) at clip tick `t`: the last action ended by `t`, else the base."""
    video = clip.get("video") or {}
    scale, x = video.get("scale", 1.0), video.get("x", 0.0)
    for a in sorted(clip.get("actions") or [], key=lambda a: a["start"] + a["duration"]):
        if a["start"] + a["duration"] > t:
            break
        end = (a.get("end") or {}).get("video") or {}
        scale, x = end.get("scale", scale), end.get("x", x)
    return scale, x


def on_canvas(clip, t, cx):
    scale, x = placement(clip, t)
    return CANVAS[0] / 2 + x + scale * (cx * PICTURE[0] - PICTURE[0] / 2)


def inside(clip, t, cx):
    return abs(on_canvas(clip, t, cx) - CANVAS[0] / 2) <= CENTRAL


def expected_shots(answer, doc):
    """switch_by_speaker's shots from its first person shot on, as (start, end, who)."""
    names = {doc.a_track: "a", doc.b_track: "b", doc.wide_track: "wide"}
    shots = [(s["start"], s["end"], names.get(s["angle"], "?")) for s in answer["shots"]]
    first = next(i for i, s in enumerate(shots) if s[2] != "wide")
    return shots[first:]


def segments(clip, shots):
    """The framing's segments, each the switch shot it should be: (from, to, who)."""
    keys = [0] + cut_keys(clip)
    ends = keys[1:] + [clip["duration"]]
    return [(a, b, shots[i][2] if i < len(shots) else "?") for i, (a, b) in
            enumerate(zip(keys, ends))]


def frames_as(clip, shots, faces_of):
    """(ok, detail): at each segment's middle the face `faces_of(who)` names is inside the
    central 60 %, the other outside it unless both are named."""
    misses = []
    for a, b, who in segments(clip, shots):
        mid = (a + b) // 2
        want = faces_of(who)
        for n, cx in ((1, F1), (2, F2)):
            here = inside(clip, mid, cx)
            if (n in want) != here:
                misses.append(f"{who} at {mid / SEC:.2f} s: face {n} "
                              f"{'outside' if n in want else 'inside'} "
                              f"({on_canvas(clip, mid, cx):.0f} px)")
    return not misses, f"{len(segments(clip, shots))} segments" + (
        f"; misses {misses[:4]}" if misses else "")


TRUE = {"a": {1}, "b": {2}, "wide": {1, 2}}


# ---- the rows ----------------------------------------------------------------------

def switch_shots(client, manifest):
    doc = Doc(client, manifest, "switch", framing=False)
    try:
        doc.call("set_selection", clips=doc.clips)
        deadline = time.monotonic() + CACHE_BOUND
        while True:
            try:
                answer = doc.call("switch_by_speaker", apply=False, min_shot=2)
                break
            except mcp.ToolError as error:
                if "still being analyzed" not in str(error) or time.monotonic() > deadline:
                    raise
            time.sleep(2)
        return expected_shots(answer, doc)
    finally:
        doc.close()


def p1_p2_p5(client, manifest, shots):
    doc = Doc(client, manifest, "talk")
    try:
        doc.save()
        base = model(doc.state())
        media = json.dumps(base["media"], sort_keys=True)
        answer = doc.frame()
        after = doc.state()
        clip = doc.clip(doc.c_wide, after)
        keys = cut_keys(clip)
        want = [s[0] for s in shots[1:]]
        far = [(k, w) for k, w in zip(keys, want) if abs(k - w) > FRAME]
        check("P1", answer.get("ok") is True and len(keys) == len(want) and not far,
              f"{len(keys)} cut keys against {len(want)} shot starts; beyond a frame "
              f"{far[:4]}")
        ok, detail = frames_as(clip, shots, lambda who: TRUE[who])
        check("P2", ok, detail)
        check("P5", json.dumps(after["media"], sort_keys=True) == media,
              "get_project's media byte-identical before and after")
        undone = doc.call("undo").get("undone")
        check("P1", undone == REFRAME and model(doc.state()) == base,
              f"one undo, named {undone!r}, gives back the project {model(doc.state()) == base}")
        p6_free(doc, base)
    finally:
        doc.close()


def p3(client, manifest, shots):
    doc = Doc(client, manifest, "swapped", mouths=("b", "a"))
    try:
        doc.frame()
        clip = doc.clip(doc.c_wide)
        ok, detail = frames_as(clip, shots, lambda who: {"a": {2}, "b": {1}, "wide": {1, 2}}[who])
        b_frames_one = all(inside(clip, (a + b) // 2, F1) and not inside(clip, (a + b) // 2, F2)
                           for a, b, who in segments(clip, shots) if who == "b")
        check("P3", ok and b_frames_one, "mouths swapped: B's segments frame face 1; " + detail)
    finally:
        doc.close()


def p4(client, manifest, shots):
    doc = Doc(client, manifest, "constant", mouths=(None, None))
    try:
        doc.save()
        base = model(doc.state())
        why = refused(lambda: doc.frame())
        want = ("name each microphone's face with mic_faces, in mics' order — face 1 at 42 % "
                "across the picture, face 2 at 58 %")
        check("P4", why is not None and want in why and "do not show which microphone is whose"
              in why and model(doc.state()) == base,
              f"refused {why!r}; the project unchanged {model(doc.state()) == base}")
        doc.frame(mic_faces=[2, 1])
        clip = doc.clip(doc.c_wide)
        a_frames_two = all(inside(clip, (a + b) // 2, F2) and not inside(clip, (a + b) // 2, F1)
                           for a, b, who in segments(clip, shots) if who == "a")
        ok, detail = frames_as(clip, shots, lambda who: {"a": {2}, "b": {1}, "wide": {1, 2}}[who])
        check("P4", ok and a_frames_two, "mic_faces [2, 1]: A's segments frame face 2; " + detail)
    finally:
        doc.close()


def p6_free(doc, base):
    """The subject-free refusals, on P1's document after its undo."""
    if "P6" not in selected:
        return
    a, b, w = doc.c_a, doc.c_b, doc.c_wide
    for arguments, sentence in (
        ({"mics": [a]}, "follow speaker needs two to four microphone clips in mics, not 1"),
        ({"mics": [a, a]}, f"clip {a} is named twice in mics"),
        ({"mics": [a, w]},
         f"clip {w} is the clip being framed, so it cannot be one of its microphones"),
        ({"mic_faces": [1]},
         "mic_faces needs one face number for each of the 2 microphones in mics, not 1"),
    ):
        why = refused(lambda: doc.frame(**arguments))
        check("P6", why is not None and sentence in why and model(doc.state()) == base,
              f"{arguments}: {why!r}")


def p6_cut(client, manifest):
    doc = Doc(client, manifest, "cut", cut=True)
    try:
        doc.save()
        base = model(doc.state())
        why = refused(lambda: doc.frame())
        sentence = (f"clip {doc.c_wide} changes shot at 00:00:10:00; follow speaker frames one "
                    f"wide shot — split the clip at its shot changes first")
        check("P6", why is not None and sentence in why and model(doc.state()) == base,
              f"a canned cut at frame {CUT_FRAME}: {why!r}")
        for path in (doc.path / "cache/loudness").glob(f"{doc.m_a}.*"):
            path.unlink()
        why = refused(lambda: doc.call_with("reframe_clip", {
            "clip": doc.c_wide, "follow": "speaker", "mics": [doc.c_a, doc.c_b]}))
        sentence = (f"The microphone on track {doc.mic_a_track} is still being analyzed — its "
                    f"loudness has not been measured yet.")
        check("P6", why is not None and sentence in why and model(doc.state()) == base,
              f"Mic A's loudness removed: {why!r}")
        doc.call("set_enabled", clip=doc.c_b, audio=False)
        base = model(doc.state())
        why = refused(lambda: doc.call_with("reframe_clip", {
            "clip": doc.c_wide, "follow": "speaker", "mics": [doc.c_a, doc.c_b],
            "mic_faces": [1, 2]}))
        sentence = (f"clip {doc.c_b}'s sound is off, so it never says who is talking; turn its "
                    f"sound on or leave it out of mics")
        check("P6", why is not None and sentence in why and model(doc.state()) == base,
              f"Mic B's sound off, mic_faces given: {why!r}")
    finally:
        doc.close()


def instance_rows(client, manifest):
    shots = attempt(lambda: switch_shots(client, manifest), *sorted(selected - {"P0"}))
    if shots is None:
        return
    print(f"  switch_by_speaker: {len(shots)} shots from the first person shot on", flush=True)
    if selected & {"P1", "P2", "P5", "P6"}:
        attempt(lambda: p1_p2_p5(client, manifest, shots), *sorted(selected & {"P1", "P2", "P5",
                                                                                "P6"}))
    if "P3" in selected:
        attempt(lambda: p3(client, manifest, shots), "P3")
    if "P4" in selected:
        attempt(lambda: p4(client, manifest, shots), "P4")
    if "P6" in selected:
        attempt(lambda: p6_cut(client, manifest), "P6")


# ---- the launch --------------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("P0", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def rows(binary, manifest):
    log = WORK / "instance.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), CANNED, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(selected - {"P0"}):
                check(row, False, "the instance did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        instance_rows(launched.client, manifest)
    finally:
        launched.stop()
        parity(log)


# ---- mutants -----------------------------------------------------------------------

def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def edited(edits, root):
    for path, anchor, replacement in edits:
        target = root / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def run_mutant(name):
    global selected
    row, kind, edits = MUTANTS[name]
    print(f"VR6a — the {name} MUTANT ({row} must FAIL)", flush=True)
    manifest = fturns()
    if manifest is None:
        print(f"mutant {name}: the control could not be performed — F-TURNS skipped (no voice)")
        return 2
    selected = {row, "P0"}
    if kind == "swift":
        made, why = tree_copy.make_copy(str(WORK / "mutant"))
        why = why or edited(edits, Path(made))
        if why:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        app, why = tree_copy.build_app(made, BUILD_BOUND)
        if app is None:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        rows(proof_app.executable(app), manifest)
    else:
        kept = {path: (ROOT / path).read_bytes() for path, _, _ in edits}
        digests = {path: sha256(ROOT / path) for path in kept}
        try:
            why = edited(edits, ROOT)
            if why:
                print(f"mutant {name}: the control could not be performed — {why}")
                return 2
            test = bounded.run(["cargo", "test", "--release", "--test", "reframe_speaker"],
                               BUILD_BOUND, cwd=str(ROOT / "core"))
            print(f"  core/tests/reframe_speaker.rs under the mutant: rc {test['rc']} "
                  f"({'FAILED' if test['rc'] else 'passed'})", flush=True)
            built = bounded.run(["make", "app-debug"], BUILD_BOUND, cwd=str(ROOT))
            if built["rc"] != 0:
                print(f"mutant {name}: the control could not be performed — make app-debug rc "
                      f"{built['rc']}: {(built['stdout'] + built['stderr'])[-600:]}")
                return 2
            rows(proof_app.binary(), manifest)
        finally:
            for path, data in kept.items():
                (ROOT / path).write_bytes(data)
                assert sha256(ROOT / path) == digests[path], f"{path} not restored"
            print("  restored by SHA-256: " + ", ".join(kept) + " (rebuild the app)", flush=True)
    if row not in results:
        print(f"mutant {name}: the control could not be performed — {row} was never scored")
        return 2
    caught = any(ok is False for ok, _ in results[row])
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


# ---- main --------------------------------------------------------------------------

def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("P0")
    WORK.mkdir(parents=True, exist_ok=True)
    for child in WORK.iterdir():
        if child.name not in KEEP:
            tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)

    print(f"VR6a — follow speaker ({proof_app.config()} build)", flush=True)
    manifest = fturns()
    if manifest is None:
        for row in sorted(selected - {"P0"}):
            skip(row, "F-TURNS needs say's Samantha and Daniel")
    else:
        rows(proof_app.binary(), manifest)

    failed = [n for n, runs in results.items() if any(ok is False for ok, _ in runs)]
    skipped = [n for n, runs in results.items() if all(ok == "skip" for ok, _ in runs)]
    passed = [n for n in results if n not in failed and n not in skipped]
    missing = sorted(selected - set(results), key=ROWS.index)
    print(f"\n{len(passed)}/{len(results)} rows passed"
          + (f"; failed {failed}" if failed else "") + (f"; skipped {skipped}" if skipped else "")
          + (f"; never scored {missing}" if missing else ""))
    return 0 if not failed and not missing and results else 1


if __name__ == "__main__":
    sys.exit(main())
