#!/usr/bin/env python3
"""Road map "creator-jobs" SW8 — Switch by Speaker with one shared microphone, decided by faces
(spec §11 SW-80…SW-87), over F-TURNS' cameras (SW-27) and ONE microphone.

    python3 tools/proof/switch_faces_proof.py [--only M1,M3,…] [--mutant NAME] [--app PATH]

The rows launch their own instances on a scratch `CFFIXED_USER_HOME`. Launch 1 is
`-RCDevAnalysisCanned YES -RCDevAnalysisHold 3600` (canned analyses honoured, and no job runs
beside a canned marker: `co7_proof.py`'s CANNED) for M0–M5; launch 2 adds
`-RCDevSwitchSpeakerAccept YES` for M6. F-TURNS is `creator_spike/f_turns.py`'s (run first,
reused while its manifest's generator hash holds); without `say -v Samantha` or `Daniel` it exits
2 and every row is skipped by name.

Each document is built over MCP — tracks back to front Wide, Cam B, Cam A (two abutting files),
Mic on a 1920 × 1080, 30 fps canvas, every clip selected — with `mic_a_b12_f55.wav` the one
microphone (M4's adds Mic B: the two-microphone F-TURNS selection). Each camera's `faces` is
canned (`canned_framing.write_faces`, 36-byte records, one face per card): inside each of that
speaker's utterances (`turns[].onset_seconds…end_seconds`, both for crosstalk) the mouth gap
alternates 0.05/0.20 of the box per sample at width 0.5, and outside it holds at 0.05; the wide
has two still faces. Its loudness and speech caches are waited for (a call refused as "still
being analysed" is polled). Packages are made under `tools/proof/work/sw8/`. A frame is 20 000
ticks. Every expected number is worked here from the manifest, never read back from the code
under test. τ_f = 64 ms (two VAD chunks) + 250 ms (half the face window) + 100 ms (one face
sample) + one frame = 268,400 ticks, fixed before the run.

Rows:
- M0 `grep "Frame Job: "` of every instance's log prints nothing.
- M1 `wide` the wide's track, `min_shot` 2: `mode` "faces", two speakers (the wide not among
  them) and the hedge as `note`; the shots' angles equal the manifest's `expected_shots`, every
  cut on the frame grid within τ_f of onset − lead; one undo step "Switch by Speaker" that gives
  back `get_project`.
- M2 no arguments, `apply: false`: `wide` null, three speakers sharing the microphone, every
  shot ≥ 3 s, nothing changed.
- M3 cam_b's canned faces removed: the call waits the 60 s bound and is refused with the
  `.timedOut` sentence naming cam_b's media and "call switch_by_speaker again"; nothing changed.
- M4 the two-microphone F-TURNS selection answers `mode` "microphones".
- M5 Clip ▸ Switch by Speaker… with cam_b's faces absent: `snapshot_ui` shows the sheet titled
  "Analyzing"; `cancel_sheet`; nothing changed.
- M6 (launch 2) the menu's project, pressed by the dev accept, equals `switch_by_speaker {}`'s on
  a copy (S10's shape).

`--mutant NAME` edits a `tree_copy.py` copy's Swift, builds its app and runs the named row on it:
CAUGHT exits 1, SURVIVED 0, a control that could not be performed 2. One mutant: wait-removed
(no want, no wait: M3 answers `read`'s pending refusal instead).
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
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/sw8"
FTURNS = ROOT / "tools/proof/media/creator/f_turns"
HOME = WORK / "home"
KEEP = {"mutant-target"}
SEC = 600_000
FRAME = 20_000
LEAD = 0.2
TAU_F = 38_400 + 150_000 + 60_000 + 20_000  # 64 ms + 250 ms + 100 ms + one frame (SW-87)
MIC = "mic_a_b12_f55.wav"
MIC_B = "mic_b_b12_f55.wav"
CALL_BOUND = 900
CACHE_BOUND = 900
BUILD_BOUND = 1800
WAIT_LIMIT = 60
HEDGE = "Faces guess who is talking; check the cuts."
SPEAKER = "Switch by Speaker"
CANNED = ["-RCDevAnalysisCanned", "YES", "-RCDevAnalysisHold", "3600"]
ACCEPT = ["-RCDevSwitchSpeakerAccept", "YES"]
ROWS = ["M0", "M1", "M2", "M3", "M4", "M5", "M6"]
MENU = ["Clip", "Switch by Speaker…"]

TOOL = "app/Sources/AgentServer+Switch.swift"
# name → (row, [(path, anchor, replacement)])
MUTANTS = {
    "wait-removed": ("M3", [(TOOL, "guard wants.isEmpty else { return (call, wants, nil) }",
                             "guard wants.isEmpty || true else { return (call, wants, nil) }")]),
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


def t(seconds):
    return int(round(seconds * SEC))


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


def talking(spans, offset):
    """faces_at for a card whose media starts `offset` s into the timeline: one face, its mouth
    gap alternating 0.05/0.20 of the box per sample inside `spans`, else 0.05, width 0.5."""
    def faces_at(t_media):
        k = int(round(t_media * canned_framing.SAMPLES_PER_SECOND))
        at = t_media + offset
        inside = any(a <= at < b for a, b in spans)
        box = dict(canned_framing.face(960.0))
        box["gap"] = (0.05 if k % 2 == 0 else 0.20) if inside else 0.05
        box["width"] = 0.5
        return [box]
    return faces_at


def still_pair(t_media):
    out = []
    for cx in (640.0, 1280.0):
        box = dict(canned_framing.face(cx))
        box["gap"], box["width"] = 0.05, 0.5
        out.append(box)
    return out


class Doc:
    """F-TURNS' cameras and one microphone (two with `two_mics`) as a saved package, every clip
    selected, the cameras' faces canned."""

    def __init__(self, client, manifest, name, two_mics=False, canned=True):
        self.client = client
        self.manifest = manifest
        self.name = name
        self.path = WORK / f"{name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=1920, height=1080, fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            self.save()
            first = self.state()["tracks"][0]["id"]
            self.call_with("set_track", {"track": first, "name": "Wide"})
            names = ["Cam B", "Cam A"] + (["Mic B", "Mic A"] if two_mics else ["Mic"])
            ids = {"Wide": first}
            for title in names:
                ids[title] = self.call_with("add_track", {"name": title})["new_tracks"][0]
            self.wide, self.b, self.a = ids["Wide"], ids["Cam B"], ids["Cam A"]
            self.mic = ids.get("Mic") or ids["Mic A"]
            self.c_wide, self.m_wide = self.place(FTURNS / "cam_wide.mov", self.wide)
            self.c_b, self.m_b = self.place(FTURNS / "cam_b.mov", self.b)
            self.c_a1, self.m_a1 = self.place(FTURNS / "cam_a_1.mov", self.a)
            self.half = self.end(self.c_a1)
            self.c_a2, self.m_a2 = self.place(FTURNS / "cam_a_2.mov", self.a, at=self.half)
            clips = [self.c_wide, self.c_b, self.c_a1, self.c_a2]
            if two_mics:
                clips.append(self.place(FTURNS / MIC_B, ids["Mic B"])[0])
            self.c_mic, _ = self.place(FTURNS / MIC, self.mic)
            self.clips = clips + [self.c_mic]
            self.names = {self.wide: "wide", self.b: "b", self.a: "a"}
            if canned:
                self.can()
            self.select()
        except Exception:
            self.close()
            raise

    def can(self):
        """Each camera's canned faces, in its media's own seconds — written only once the app's
        import pass has made the package's `cache/`, so the package's own date never moves."""
        deadline = time.monotonic() + 120
        while not (self.path / "cache").is_dir():
            if time.monotonic() > deadline:
                raise RuntimeError(f"{self.path}/cache was never made")
            time.sleep(0.5)
        state = self.state()
        duration = {m["id"]: m["duration"] for m in state["media"]}
        half = self.half / SEC
        cams = [(self.m_wide, "cam_wide.mov", still_pair),
                (self.m_b, "cam_b.mov", talking(utterances(self.manifest, "b"), 0.0)),
                (self.m_a1, "cam_a_1.mov", talking(utterances(self.manifest, "a"), 0.0)),
                (self.m_a2, "cam_a_2.mov", talking(utterances(self.manifest, "a"), half))]
        for media, file, faces_at in cams:
            canned_framing.write_faces(self.path, media, FTURNS / file, duration[media], faces_at)

    def uncan(self, media):
        folder = self.path / "cache/analysis/faces"
        shutil.rmtree(folder / str(media), ignore_errors=True)
        (folder / f"{media}.json").unlink(missing_ok=True)

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

    def select(self, clips=None):
        self.call("set_selection", clips=clips or self.clips)

    def switch(self, **arguments):
        return self.call_with("switch_by_speaker", arguments)

    def ready(self, **arguments):
        """Polls `apply: false` until no microphone is still being analyzed."""
        deadline = time.monotonic() + CACHE_BOUND
        while True:
            try:
                return self.switch(apply=False, **arguments)
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


# ---- scoring -----------------------------------------------------------------------

def score(doc, shots, expected):
    """(pass, detail): the angles, the frame grid and τ_f."""
    got = [doc.names.get(s["angle"], "?") for s in shots]
    want = [row["angle"] for row in expected]
    misses, errors = [], []
    if got != want:
        misses.append(f"angles {got} against {want}")
    for index, row in enumerate(expected):
        if index >= len(shots):
            break
        start = shots[index]["start"]
        if start % FRAME:
            misses.append(f"shot {index} at tick {start} is off the frame grid")
        if row.get("onset_ticks") is None:
            if start != 0:
                misses.append(f"shot {index} starts at {start}, not the range's start")
            continue
        late = start - (row["onset_ticks"] - t(LEAD))
        errors.append(late / 600)
        if abs(late) > TAU_F:
            angle = got[index] if index < len(got) else "?"
            misses.append(f"shot {index} ({angle}) {late / 600:.1f} ms from onset − lead")
    worst = max((abs(e) for e in errors), default=0)
    detail = (f"{len(shots)} shots, worst {worst:.1f} ms"
              + (f"; misses: {misses}" if misses else ""))
    return not misses, detail


def sheet_texts(doc, tag):
    got = doc.call("snapshot_ui", window="sheet", path=str(WORK / f"{tag}.png"))
    path = got.get("layout_path") if isinstance(got, dict) else None
    if not path:
        return []
    views = json.loads(Path(path).read_text()).get("views") or []
    return [v.get("text") for v in views if v.get("text") and not v.get("hidden")]


# ---- launch 1 ----------------------------------------------------------------------

def canned_rows(client, manifest):
    if selected & {"M1", "M2", "M3", "M5", "M6"}:
        attempt(lambda: faces_rows(client, manifest), *sorted(selected & {"M1", "M2", "M3",
                                                                          "M5", "M6"}))
    if "M4" in selected:
        attempt(lambda: m4(client, manifest), "M4")


def faces_rows(client, manifest):
    doc = Doc(client, manifest, "faces")
    try:
        r2 = doc.ready()
        doc.save()
        base = model(doc.state())
        if "M6" in selected:
            for copy in ("m6-menu", "m6-tool"):
                target = WORK / f"{copy}.framejob"
                shutil.rmtree(target, ignore_errors=True)
                shutil.copytree(doc.path, target)
        speakers = r2.get("speakers") or []
        lengths = [s["end"] - s["start"] for s in r2.get("shots") or []]
        check("M2", r2.get("mode") == "faces" and r2.get("wide") is None and len(speakers) == 3
              and all(s["mic"] == doc.mic for s in speakers)
              and {s["angle"] for s in speakers} == {doc.a, doc.b, doc.wide}
              and lengths and min(lengths) >= t(3) and r2.get("applied") is False
              and model(doc.state()) == base,
              f"no arguments: mode {r2.get('mode')}, wide {r2.get('wide')}, speakers {speakers}, "
              f"{len(lengths)} shots, shortest {min(lengths, default=0) / SEC:.2f} s, the project "
              f"unchanged {model(doc.state()) == base}")
        if "M1" in selected:
            m1(doc, manifest, base)
        if selected & {"M3", "M5"}:
            doc.uncan(doc.m_b)
            if "M3" in selected:
                m3(doc, base)
            if "M5" in selected:
                m5(doc, base)
    finally:
        doc.close()


def m1(doc, manifest, base):
    r1 = doc.switch(wide=doc.wide, min_shot=2)
    speakers = r1.get("speakers") or []
    check("M1", r1.get("mode") == "faces" and r1.get("note") == HEDGE and len(speakers) == 2
          and doc.wide not in {s["angle"] for s in speakers} and r1.get("wide") == doc.wide,
          f"mode {r1.get('mode')}, note {r1.get('note')!r}, speakers {speakers}, wide "
          f"{r1.get('wide')}")
    ok, detail = score(doc, r1["shots"], manifest["expected_shots"])
    check("M1", ok and r1.get("applied") is True, "applied, " + detail)
    undone = doc.call("undo").get("undone")
    check("M1", undone == SPEAKER and model(doc.state()) == base,
          f"one undo, named {undone!r}, gives back the project {model(doc.state()) == base}")


def m3(doc, base):
    began = time.monotonic()
    why = refused(lambda: doc.switch(wide=doc.wide))
    took = time.monotonic() - began
    want = (f"The faces analysis of media {doc.m_b} did not finish in the {WAIT_LIMIT} s a call "
            f"waits; what it covered is kept — call switch_by_speaker again to continue.")
    check("M3", why is not None and want in why and took >= WAIT_LIMIT - 1
          and model(doc.state()) == base,
          f"after {took:.1f} s: {why!r}; the project unchanged {model(doc.state()) == base}")


def m5(doc, base):
    doc.select()
    doc.call("perform_menu_item", path=MENU)
    texts = []
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        texts = sheet_texts(doc, "m5-sheet")
        if "Analyzing" in texts:
            break
        time.sleep(0.5)
    try:
        doc.call("cancel_sheet")
        cancelled = True
    except mcp.ToolError:
        cancelled = False
    time.sleep(2)
    check("M5", "Analyzing" in texts and cancelled and model(doc.state()) == base,
          f"the sheet reads \"Analyzing\" {'Analyzing' in texts}, cancelled {cancelled}, the "
          f"project unchanged {model(doc.state()) == base}")


def m4(client, manifest):
    doc = Doc(client, manifest, "two-mics", two_mics=True, canned=False)
    try:
        answer = doc.ready()
        check("M4", answer.get("mode") == "microphones" and "note" not in answer,
              f"two microphones: mode {answer.get('mode')}, note {answer.get('note')!r}")
    finally:
        doc.close()


# ---- launch 2 ----------------------------------------------------------------------

class Opened:
    """A copied package opened in the accept instance."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        client.call("open_project", path=str(self.path))

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def all_clips(opened):
    state = opened.call("get_project")["project"]
    return state, [c["id"] for c in state["clips"]]


def m6(client):
    tool = Opened(client, "m6-tool")
    try:
        _, ids = all_clips(tool)
        tool.call("set_selection", clips=ids)
        answer = tool.call("switch_by_speaker")
        want = model(tool.call("get_project")["project"])
    finally:
        tool.close()
    menu = Opened(client, "m6-menu")
    try:
        before, ids = all_clips(menu)
        menu.call("set_selection", clips=ids)
        menu.call("perform_menu_item", path=MENU)
        deadline = time.monotonic() + 60
        got = model(before)
        while time.monotonic() < deadline:
            got = model(menu.call("get_project")["project"])
            if len(got["tracks"]) > len(before["tracks"]):
                break
            time.sleep(0.5)
        check("M6", answer.get("mode") == "faces" and got == want
              and len(got["tracks"]) > len(before["tracks"]),
              f"the menu's project equals switch_by_speaker {{}}'s: {got == want} (the tool's "
              f"mode {answer.get('mode')}, {len(answer.get('shots') or [])} shots)")
    finally:
        menu.close()


def accept_rows(client):
    if "M6" in selected:
        attempt(lambda: m6(client), "M6")


# ---- launches ----------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("M0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def with_instance(binary, tag, body, arguments=()):
    log = WORK / f"instance-{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), list(arguments), env=env, log_path=str(log),
                          timeout=CALL_BOUND)
    try:
        if launched.client is None:
            return False
        print(f"  {tag}: instance PID {launched.child.pid} ({' '.join(arguments)})", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)
    return True


def rows(binary, manifest):
    if selected & {"M1", "M2", "M3", "M4", "M5", "M6"}:
        if not with_instance(binary, "canned", lambda c: canned_rows(c, manifest), CANNED):
            for row in selected - {"M0"}:
                check(row, False, "the canned instance did not listen")
            return
    if "M6" in selected:
        if not with_instance(binary, "accept", accept_rows, CANNED + ACCEPT):
            check("M6", False, "the accept instance did not listen")


def skip_all(why):
    for row in sorted(selected - {"M0"}):
        skip(row, why)


# ---- mutants -----------------------------------------------------------------------

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
    row, _ = MUTANTS[name]
    print(f"SW8 — the {name} MUTANT ({row} must FAIL)", flush=True)
    manifest = fturns()
    if manifest is None:
        print(f"mutant {name}: the control could not be performed — F-TURNS skipped (no voice)")
        return 2
    selected = {row, "M0"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    why = why or edited(name, Path(made))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, why = tree_copy.build_app(made, BUILD_BOUND)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    rows(proof_app.executable(app), manifest)
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
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("M0")
    WORK.mkdir(parents=True, exist_ok=True)
    for child in WORK.iterdir():
        if child.name not in KEEP:
            tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)

    print(f"SW8 — Switch by Speaker from faces ({proof_app.config()} build)", flush=True)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    manifest = fturns()
    if manifest is None:
        skip_all("F-TURNS needs say's Samantha and Daniel")
    else:
        rows(binary, manifest)

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
