#!/usr/bin/env python3
"""Road map "creator-jobs" VR6b — Make Vertical follows the speaker: `make_vertical_version`'s
`mics` and File ▸ Make Vertical Version…'s Follow Speaker with its microphone picker and
face-to-mic confirmation (spec §11 VR-64…VR-68), over F-TURNS' two microphones (SW-27).

    python3 tools/proof/vr6b_proof.py [--only Q1,Q5,…] [--mutant NAME]

F-TURNS is `creator_spike/f_turns.py`'s (run first, reused while its manifest's generator hash
holds); without `say -v Samantha` or `Daniel` it exits 2 and every row is skipped by name. Every
instance runs on a scratch `CFFIXED_USER_HOME` (the sheet writes the Follow key).

Each document is built over MCP on a 1920 × 1080, 30 fps canvas: `cam_wide.mov` W (the
two-shot) on track "Wide" at 0, `mic_a_b12_f55.wav` on "Mic A" and `mic_b_b12_f55.wav` on "Mic
B" at 0, and `cam_b.mov` S on "Wide" after the microphones' span. W's analyses are canned as
`vr6_proof.py`'s (`canned_framing.write` with `landmarks`: face 1 at x 0.42, face 2 at 0.58,
y 0.4, each mouth alternating 0.05/0.20 of width 0.5 inside its speaker's utterances and 0.05
outside); S's with one still face at x 0.5. A microphone's loudness and speech caches are waited
for (their `complete.json`) before a row reads them. Expected values come from a REFERENCE
document built the same way and framed by the tools Make Vertical's step is made of —
`set_canvas {1080, 1920, rescale_clips: false}`, `add_track {0, "Backgrounds"}`, `reframe_clip`
— or from F-TURNS' manifest, never from the code under test.

Rows:
- Z0 `grep "Frame Job: "` of each launch's log prints nothing.
Launch 1 (`-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600`):
- Q1 `{shape: "9:16", follow: speaker, mics: [A, B], copy: false}`: `speaker == [{W, [A, B],
  [1, 2]}]`, W and S `followed` with no reason, the summary's " Follows whoever is talking in 1
  clip."; W's `video` and `actions` equal the reference's `reframe_clip {W, speaker, mics [A, B],
  zoom 1, where_empty fit, from 1920 × 1080, backdrop}`; undo "Make Vertical" gives back the
  project.
- Q2 `mic_faces: [2, 1]`: answered `[2, 1]`, W equal to the reference with `mic_faces [2, 1]`.
- Q3 constant mouths: W `followed`, its reason starting "it follows its faces, not who is
  talking, because clip W's faces do not show", `speaker` [], W equal to a reference `follow:
  face`.
- Q4 nothing made, each in its sentence: speaker without `mics`; `mics: [A]` (no speaker clip);
  an unknown id; Mic A's loudness cache removed (SW-24's "still being analysed").
Launch 2 (`-RCDevAnalysisCanned YES -FrameJobFollowKind speaker -RCDevVerticalAccept in-place`):
- Q5 the menu on Q1's fixture: within 60 s the canvas is 1080 × 1920 in place and W equals the
  reference's (and Q1's, when Q1 ran); undo "Make Vertical".
- Q6 the menu on Q3's fixture: 10 s with nothing made; the sheet's layout dump shows "Mic A",
  "Mic B", two "Choose a face" pop-ups and the not-sure note; `cancel_sheet`.
- Q7 a fixture with W's analysis not canned (and no S): the Analyzing sheet within 60 s, closed
  within 300 s, then within 30 s the Make Vertical sheet up again, Follow on Speaker, with Mic A
  and Mic B ticked (their Faces rows shown); `cancel_sheet`, nothing made.
- Q8 `vr6b_probe.swift` (built through `swift_build.build`, run under the scratch home on a
  suite of its own): the key `speaker` read as Speaker by `VerticalVersion.remembered` and as
  Subject by `FollowSubjectSettings.remembered`; Subject written back; `cursor` read as Subject. A
  probe that does not build is a scored failure.

`--mutant NAME` runs the named row on a mutated `tree_copy.py` copy (its app built; Q8's probe
from its sources): CAUGHT exits 1, SURVIVED 0, a control that could not be performed 2. Eight
mutants (VR-68).
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
import canned_framing  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/vr6b"
FTURNS = ROOT / "tools/proof/media/creator/f_turns"
HOME = WORK / "home"
KEEP = {"mutant-target"}
MIC_A = "mic_a_b12_f55.wav"
MIC_B = "mic_b_b12_f55.wav"
CALL_BOUND = 900
CACHE_BOUND = 900
BUILD_BOUND = 1800
F1, F2, FS = 0.42, 0.58, 0.5
PICTURE = (1920, 1080)
STEP = "Make Vertical"
MENU = ["File", "Make Vertical Version…"]
LAUNCH_1 = ["-RCDevAnalysisCanned", "YES", "-RCDevAnalysisHold", "3600"]
LAUNCH_2 = ["-RCDevAnalysisCanned", "YES", "-FrameJobFollowKind", "speaker",
            "-RCDevVerticalAccept", "in-place"]
ROWS = ["Z0", "Q1", "Q2", "Q3", "Q4", "Q5", "Q6", "Q7", "Q8"]
FIRST = {"Q1", "Q2", "Q3", "Q4"}
SECOND = {"Q5", "Q6", "Q7"}
UNSURE = ("The faces do not show clearly who is on each microphone: choose each microphone's "
          "face.")

PLAN = "app/Sources/VerticalVersion+Plan.swift"
SPEAKER = "app/Sources/VerticalVersion+Speaker.swift"
PICKER = "app/Sources/VerticalSpeakerPicker.swift"
EDITOR = "app/Sources/EditorViewController+VerticalVersion.swift"
VERSION = "app/Sources/VerticalVersion.swift"
# name → (row, [(path, anchor, replacement)])
MUTANTS = {
    "every-picture-speaker": ("Q1", [(
        PLAN, "follow = speakerOf[id] == nil ? .face : .speaker", "follow = .speaker")]),
    "speaker-retried-keep": ("Q3", [(
        PLAN, "speakerWhy = refusal.reason\n                        used = .face",
        "speakerWhy = refusal.reason\n                        used = .keep")]),
    "mic-faces-dropped": ("Q2", [(
        PLAN, "mics: own?.mics, micFaces: own?.micFaces, subjects: read)",
        "mics: own?.mics, micFaces: nil, subjects: read)")]),
    "preset-when-unsure": ("Q6", [(PICKER, "if let match, match.sure {",
                                   "if let match, match.sure || true {")]),
    "preset-transposed": ("Q5", [(
        PICKER, "faces.firstIndex(where: { $0.face == match.assignment[n] })",
        "faces.firstIndex(where: { $0.face == match.assignment[match.assignment.count - 1 - n] })"
    )]),
    "handoff-committed": ("Q7", [(EDITOR, "if handOff.settings.follow == .speaker {",
                                  "if false, handOff.settings.follow == .speaker {")]),
    "turns-unfilled": ("Q1", [(SPEAKER, "            out[entry.clip] = own\n",
                               "            out[entry.clip] = own.filter { $0.key != \"turns\" }\n")]),
    "remembered-ignores-speaker": ("Q8", [(
        VERSION, "settings.follow = kind.flatMap { follows.contains($0) ? $0 : nil } ?? .subject",
        "settings.follow = kind.flatMap { FollowSubject.follows.contains($0) ? $0 : nil } "
        "?? .subject")]),
}

results = {}
selected = set(ROWS)
memo = {}


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
    """vr6_proof.py's faces: face 1 talks in `one`'s utterances, face 2 in `two`'s; a speaker of
    None never moves its mouth."""
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


def one_face(_t_media):
    box = dict(canned_framing.face(FS * PICTURE[0], 0.4 * PICTURE[1]))
    box["gap"], box["width"] = 0.05, 0.5
    return [box]


class Doc:
    """A saved package over MCP: W, Mic A and Mic B at 0 and (with `second`) S after them, W's
    analyses canned unless `canned` is false, S's always."""

    def __init__(self, client, manifest, name, mouths=("a", "b"), canned=True, second=True):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=PICTURE[0], height=PICTURE[1], fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            self.save()
            first = self.state()["tracks"][0]["id"]
            self.call_with("set_track", {"track": first, "name": "Wide"})
            ids = {"Wide": first}
            for title in ("Mic B", "Mic A"):
                ids[title] = self.call_with("add_track", {"name": title})["new_tracks"][0]
            self.wide_track = first
            self.mic_b_track, self.mic_a_track = ids["Mic B"], ids["Mic A"]
            self.c_wide, self.m_wide = self.place(FTURNS / "cam_wide.mov", first)
            self.c_b, self.m_b = self.place(FTURNS / MIC_B, self.mic_b_track)
            self.c_a, self.m_a = self.place(FTURNS / MIC_A, self.mic_a_track)
            self.c_s = self.m_s = None
            if second:
                after = max(self.end(c) for c in (self.c_wide, self.c_a, self.c_b))
                self.c_s, self.m_s = self.place(FTURNS / "cam_b.mov", first, at=after)
            self.wait_cache()
            media = {m["id"]: m["duration"] for m in self.state()["media"]}
            if canned:
                canned_framing.write(self.path, self.m_wide, FTURNS / "cam_wide.mov",
                                     media[self.m_wide], [30, 1], two_faces(manifest, *mouths),
                                     landmarks=True)
            if second:
                canned_framing.write(self.path, self.m_s, FTURNS / "cam_b.mov", media[self.m_s],
                                     [30, 1], one_face, landmarks=True)
            self.save()
        except Exception:
            self.close()
            raise

    def wait_cache(self):
        """`cache/` made, then each microphone's loudness and speech markers written."""
        deadline = time.monotonic() + CACHE_BOUND
        markers = [self.path / "cache" / kind / f"{m}.complete.json"
                   for kind in ("loudness", "speech") for m in (self.m_a, self.m_b)]
        while not all(p.exists() for p in markers):
            if time.monotonic() > deadline:
                raise RuntimeError(f"the microphones' caches were not written within "
                                   f"{CACHE_BOUND} s: {[str(p) for p in markers if not p.exists()]}")
            time.sleep(0.5)

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

    def framed(self, state=None):
        """W's `video` and `actions`, the two things a framing writes."""
        w = self.clip(self.c_wide, state)
        return {"video": w.get("video"), "actions": w.get("actions")}

    def vertical(self, **arguments):
        call = {"shape": "9:16", "follow": "speaker", "mics": [self.c_a, self.c_b],
                "copy": False, **arguments}
        return self.call_with("make_vertical_version", call)

    def reference(self, follow, **arguments):
        """Make Vertical's step by hand: the canvas, Backgrounds, then W's own reframe_clip."""
        self.call("set_canvas", width=1080, height=1920, rescale_clips=False)
        track = self.call_with("add_track", {"index": 0, "name": "Backgrounds"})["new_tracks"][0]
        call = {"clip": self.c_wide, "follow": follow, "zoom": 1, "where_empty": "fit",
                "from_width": PICTURE[0], "from_height": PICTURE[1], "backdrop": track,
                **arguments}
        if follow == "speaker":
            call.setdefault("mics", [self.c_a, self.c_b])
        self.call_with("reframe_clip", call)
        return self.framed()

    def undo_all(self, base):
        for _ in range(3):
            if model(self.state()) == base:
                break
            self.call("undo")
        return model(self.state()) == base

    def save(self):
        self.call("save_project")

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def entry(answer, cid):
    return next((c for c in answer.get("clips") or [] if c["clip"] == cid), None)


# ---- launch 1: the tool ----------------------------------------------------------------

def q1_q2(client, manifest):
    doc = Doc(client, manifest, "talk")
    ref = Doc(client, manifest, "talk-ref")
    try:
        base = model(doc.state())
        ref_base = model(ref.state())
        want = ref.reference("speaker")
        answer = doc.vertical()
        state = doc.state()
        got = doc.framed(state)
        memo["Q1"] = got
        w, s = entry(answer, doc.c_wide), entry(answer, doc.c_s)
        speaker = answer.get("speaker")
        expected = [{"clip": doc.c_wide, "mics": [doc.c_a, doc.c_b], "mic_faces": [1, 2]}]
        canvas = state.get("canvas") or {}
        check("Q1", speaker == expected
              and w == {"clip": doc.c_wide, "treatment": "followed"}
              and s == {"clip": doc.c_s, "treatment": "followed"}
              and " Follows whoever is talking in 1 clip." in (answer.get("summary") or "")
              and (canvas.get("width"), canvas.get("height")) == (1080, 1920),
              f"speaker {speaker}; W {w}; S {s}; canvas {canvas.get('width')} × "
              f"{canvas.get('height')}; summary {answer.get('summary', '')[:160]!r}")
        check("Q1", got == want,
              f"W's video and {len(got['actions'] or [])} actions equal the reference's "
              f"reframe_clip ({len(want['actions'] or [])} actions): {got == want}")
        undone = doc.call("undo").get("undone")
        check("Q1", undone == STEP and model(doc.state()) == base,
              f"one undo, named {undone!r}, gives back the project {model(doc.state()) == base}")
        if "Q2" in selected:
            back = ref.undo_all(ref_base)
            want2 = ref.reference("speaker", mic_faces=[2, 1])
            answer2 = doc.vertical(mic_faces=[2, 1])
            got2 = doc.framed()
            speaker2 = answer2.get("speaker")
            check("Q2", back and speaker2 == [{"clip": doc.c_wide, "mics": [doc.c_a, doc.c_b],
                                                "mic_faces": [2, 1]}]
                  and got2 == want2 and got2 != got,
                  f"reference given back {back}; speaker {speaker2}; W equal to the reference "
                  f"with mic_faces [2, 1] {got2 == want2}, unlike Q1's {got2 != got}")
            doc.call("undo")
    finally:
        doc.close()
        ref.close()


def q3(client, manifest):
    doc = Doc(client, manifest, "constant", mouths=(None, None))
    ref = Doc(client, manifest, "constant-ref", mouths=(None, None))
    try:
        want = ref.reference("face")
        answer = doc.vertical()
        got = doc.framed()
        w = entry(answer, doc.c_wide) or {}
        start = (f"it follows its faces, not who is talking, because clip {doc.c_wide}'s faces "
                 f"do not show")
        check("Q3", w.get("treatment") == "followed" and (w.get("reason") or "").startswith(start)
              and answer.get("speaker") == [] and got == want,
              f"W {w.get('treatment')!r}, reason {(w.get('reason') or '')[:140]!r}; speaker "
              f"{answer.get('speaker')}; W equal to a reference follow: face {got == want}")
    finally:
        doc.close()
        ref.close()


def q4(client, manifest):
    doc = Doc(client, manifest, "refusals")
    try:
        base = model(doc.state())
        cases = [
            ({"mics": None},
             "make_vertical_version's follow speaker needs mics: two to four clips, one on "
             "each microphone's track."),
            ({"mics": [doc.c_a]},
             "make_vertical_version found no full-frame movie clip playing beside two of the "
             "microphones in mics, so nobody is framed by who is talking."),
            ({"mics": [doc.c_a, 99999]}, "No clip has id 99999."),
        ]
        for arguments, sentence in cases:
            call = {k: v for k, v in arguments.items() if v is not None}
            if arguments.get("mics", 0) is None:
                why = refused(lambda: doc.call_with("make_vertical_version", {
                    "shape": "9:16", "follow": "speaker", "copy": False}))
            else:
                why = refused(lambda: doc.vertical(**call))
            check("Q4", why is not None and sentence in why and model(doc.state()) == base,
                  f"{arguments}: {why!r}")
        for path in (doc.path / "cache/loudness").glob(f"{doc.m_a}.*"):
            path.unlink()
        why = refused(lambda: doc.vertical())
        sentence = (f"make_vertical_version was refused: The microphone on track "
                    f"{doc.mic_a_track} is still being analysed — its loudness has not been "
                    f"measured yet.")
        check("Q4", why is not None and sentence in why and model(doc.state()) == base,
              f"Mic A's loudness removed: {why!r}")
    finally:
        doc.close()


def launch_one(client, manifest):
    if selected & {"Q1", "Q2"}:
        attempt(lambda: q1_q2(client, manifest), *sorted(selected & {"Q1", "Q2"}))
    if "Q3" in selected:
        attempt(lambda: q3(client, manifest), "Q3")
    if "Q4" in selected:
        attempt(lambda: q4(client, manifest), "Q4")


# ---- launch 2: the sheet ---------------------------------------------------------------

def sheet_views(doc, tag):
    """The attached sheet's layout dump's views, or None with no sheet."""
    (WORK / "sheets").mkdir(parents=True, exist_ok=True)
    try:
        got = doc.call("snapshot_ui", window="sheet", path=str(WORK / "sheets" / f"{tag}.png"))
    except mcp.ToolError:
        return None
    path = got.get("layout_path") if isinstance(got, dict) else None
    if not path:
        return None
    return json.loads(Path(path).read_text()).get("views") or []


def shown(views):
    return [v for v in views or [] if not v.get("hidden")]


def is_vertical(views):
    return any(v.get("id") == "vertical.follow" for v in shown(views))


def is_analyzing(views):
    return any(v.get("text") == "Analyzing" for v in shown(views))


def wait_for(doc, tag, test, bound):
    began = time.monotonic()
    while time.monotonic() - began < bound:
        views = sheet_views(doc, tag)
        if views is not None and test(views):
            return views, time.monotonic() - began
        time.sleep(0.25)
    return None, time.monotonic() - began


def faces_rows(views):
    return [v for v in shown(views) if (v.get("id") or "").startswith("vertical.face.")]


def q5(client, manifest):
    doc = Doc(client, manifest, "menu-talk", second=True)
    ref = Doc(client, manifest, "menu-talk-ref", second=True)
    try:
        base = model(doc.state())
        want = ref.reference("speaker")
        doc.call("perform_menu_item", path=MENU)
        began, canvas = time.monotonic(), {}
        while time.monotonic() - began < 60:
            canvas = doc.state().get("canvas") or {}
            if (canvas.get("width"), canvas.get("height")) == (1080, 1920):
                break
            time.sleep(0.25)
        took = time.monotonic() - began
        made = (canvas.get("width"), canvas.get("height")) == (1080, 1920)
        got = doc.framed() if made else None
        q1 = memo.get("Q1")
        undone = doc.call("undo").get("undone") if made else None
        back = model(doc.state()) == base
        check("Q5", made and got == want and (q1 is None or got == q1) and undone == STEP
              and back,
              f"canvas {canvas.get('width')} × {canvas.get('height')} after {took:.1f} s; W "
              f"equal to the reference {got == want}"
              + ("" if q1 is None else f", to Q1's {got == q1}")
              + f"; undo {undone!r}, the project given back {back}")
    finally:
        doc.close()
        ref.close()


def q6(client, manifest):
    doc = Doc(client, manifest, "menu-constant", mouths=(None, None))
    try:
        base = model(doc.state())
        doc.call("perform_menu_item", path=MENU)
        views, _ = wait_for(doc, "q6-open", is_vertical, 30)
        stayed = True
        for _ in range(10):
            time.sleep(1)
            stayed = stayed and model(doc.state()) == base
        views = sheet_views(doc, "q6")
        texts = [v.get("text") for v in shown(views)]
        popups = faces_rows(views)
        choose = [v for v in popups if v.get("text") == "Choose a face"]
        names = all(name in texts for name in ("Mic A", "Mic B"))
        note = UNSURE in texts
        if views is not None:
            doc.call("cancel_sheet")
        check("Q6", views is not None and stayed and names and len(popups) == 2
              and len(choose) == 2 and note and model(doc.state()) == base,
              f"the sheet up {views is not None}; nothing made for 10 s {stayed}; Mic A and "
              f"Mic B shown {names}; {len(popups)} Faces pop-ups, {len(choose)} on 'Choose a "
              f"face'; the not-sure note {note}")
    finally:
        doc.close()


def q7(client, manifest):
    doc = Doc(client, manifest, "menu-uncanned", canned=False, second=False)
    try:
        base = model(doc.state())
        doc.call("perform_menu_item", path=MENU)
        seen, took = wait_for(doc, "q7-analyzing", is_analyzing, 60)
        closed, took_closed = False, 0.0
        if seen is not None:
            began = time.monotonic()
            while time.monotonic() - began < 300 and not closed:
                views = sheet_views(doc, "q7-closing")
                closed = views is None or not is_analyzing(views)
                if not closed:
                    time.sleep(0.5)
            took_closed = time.monotonic() - began
        again, took_again = (None, 0.0)
        if closed:
            again, took_again = wait_for(doc, "q7-again", is_vertical, 30)
        follow = next((v.get("text") for v in shown(again) if v.get("id") == "vertical.follow"),
                      None)
        rows = {v.get("id") for v in faces_rows(again)}
        ticked = rows == {f"vertical.face.{doc.mic_a_track}", f"vertical.face.{doc.mic_b_track}"}
        if again is not None:
            doc.call("cancel_sheet")
            time.sleep(2)
        unchanged = model(doc.state()) == base
        check("Q7", seen is not None and closed and again is not None
              and follow == "Speaker" and ticked and unchanged,
              f"Analyzing after {took:.1f} s {seen is not None}; closed after "
              f"{took_closed:.1f} s {closed}; the sheet again after "
              f"{took_again:.1f} s {again is not None}, Follow {follow!r}, Faces rows "
              f"{sorted(rows)}; nothing made {unchanged}")
    finally:
        doc.close()


def launch_two(client, manifest):
    if "Q5" in selected:
        attempt(lambda: q5(client, manifest), "Q5")
    if "Q6" in selected:
        attempt(lambda: q6(client, manifest), "Q6")
    if "Q7" in selected:
        attempt(lambda: q7(client, manifest), "Q7")


# ---- Q8: the probe ---------------------------------------------------------------------

def probe_row(root=ROOT):
    here = WORK / "probe"
    here.mkdir(parents=True, exist_ok=True)
    entry_file = here / "main.swift"
    shutil.copyfile(HERE / "vr6b_probe.swift", entry_file)
    binary = here / "vr6b-probe"
    sources = sorted(str(p) for p in (Path(root) / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    try:
        swift_build.build(sources=sources + [str(entry_file)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        check("Q8", False, "the probe did not build: "
              + ("; ".join(error.diagnostics[:8]) or str(error)))
        return
    run = subprocess.run([str(binary), str(here), "main"], capture_output=True, text=True,
                         timeout=600, env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}))
    (here / "stderr.txt").write_text(run.stderr)
    if run.returncode != 0:
        check("Q8", False, f"the probe exited {run.returncode}: {run.stderr[-300:]}")
        return
    for row in json.loads(run.stdout)["rows"]:
        check(row["id"], row["pass"], row["detail"])


# ---- the launches ----------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def run_launch(binary, arguments, rows, body, tag):
    log = WORK / f"{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(rows):
                check(row, False, "the instance did not listen")
            return
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)


def rows(binary, manifest, root=ROOT):
    first, second = selected & FIRST, selected & SECOND
    if first:
        run_launch(binary, LAUNCH_1, first, lambda c: launch_one(c, manifest), "launch-1")
    if second:
        run_launch(binary, LAUNCH_2, second, lambda c: launch_two(c, manifest), "launch-2")
    if "Q8" in selected:
        attempt(lambda: probe_row(root), "Q8")


# ---- mutants ---------------------------------------------------------------------------

def edited(edits, root):
    for path, anchor, replacement in edits:
        target = Path(root) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def run_mutant(name):
    global selected
    row, edits = MUTANTS[name]
    print(f"VR6b — the {name} MUTANT ({row} must FAIL)", flush=True)
    selected = {row, "Z0"} if row != "Q8" else {row}
    manifest = None
    if row != "Q8":
        manifest = fturns()
        if manifest is None:
            print(f"mutant {name}: the control could not be performed — F-TURNS skipped "
                  "(no voice)")
            return 2
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    why = why or edited(edits, Path(made) if made else WORK)
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    if row == "Q8":
        probe_row(made)
    else:
        app, why = tree_copy.build_app(made, BUILD_BOUND)
        if app is None:
            print(f"mutant {name}: the control could not be performed — {why}")
            return 2
        rows(proof_app.executable(app), manifest, made)
    if row not in results:
        print(f"mutant {name}: the control could not be performed — {row} was never scored")
        return 2
    caught = any(ok is False for ok, _ in results[row])
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
          f"{'failed' if caught else 'passed'}")
    return 1 if caught else 0


# ---- main ------------------------------------------------------------------------------

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
        if selected - {"Q8"}:
            selected.add("Z0")
    WORK.mkdir(parents=True, exist_ok=True)
    for child in WORK.iterdir():
        if child.name not in KEEP:
            tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)

    print(f"VR6b — Make Vertical follows the speaker ({proof_app.config()} build)", flush=True)
    manifest = fturns()
    if manifest is None:
        for row in sorted(selected - {"Z0", "Q8"}):
            skip(row, "F-TURNS needs say's Samantha and Daniel")
        if "Q8" in selected:
            attempt(probe_row, "Q8")
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
