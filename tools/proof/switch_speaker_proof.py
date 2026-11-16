#!/usr/bin/env python3
"""Road map "creator-jobs" SW2b — Clip ▸ Switch by Speaker… and `switch_by_speaker`
(spec §11 SW-23, SW-26), over F-TURNS (SW-27).

    python3 tools/proof/switch_speaker_proof.py [SOCKET] [--only S1,S5,…] [--mutant NAME]
                                                [--app PATH]

SOCKET is a running instance's `<dir>/agent.sock` (`proof_app.py launch`); without it the rows
launch their own instance on a scratch `CFFIXED_USER_HOME`. S10 (and S13's dev-accept half)
always launch one more instance of the same build with `-RCDevSwitchSpeakerAccept YES
-FrameJobSwitchSpeakerMinShot 3`. F-TURNS is `creator_spike/f_turns.py`'s (run first, reused
while its manifest's generator hash holds); without `say -v Samantha` or `Daniel` it exits 2 and
every row is skipped by name. Each document is built over MCP — tracks back to front Wide, Cam B,
Cam A (two abutting files), Mic B, Mic A on a 1920 × 1080, 30 fps canvas, every clip selected —
and its loudness and speech caches waited for (a call refused as "still being analyzed" is
polled). Packages are made under `tools/proof/work/sw2b/`. A frame is 20 000 ticks. Every
expected number is worked here from the manifest (onsets, expected shots, the card colours, the
frame code), never read back from the code under test.

Rows:
- Z0 `grep "Frame Job: "` of every instance's log prints nothing.
- S1 `apply: false` on all six variants: the shot angles equal the manifest's, every cut on the
  frame grid and within τ = 147.3 ms of onset − lead (b24_f45's shot 17 (b) late by at most
  99,313 ticks, SW-S4's named limit); the applied answer on b18_f55 scored the same way; and
  b18_f55 at `min_shot` 0.5, where a reply's shot no longer merges away and only `min_turn`
  holds it, scored the same way.
- S2 b12_f55 with `bleed_db` 15: no shot of a person who is silent (no solo turn of theirs
  overlaps it) for the whole shot.
- S3 `render_frame` at each turn's middle after the switch: the centre pixel is that speaker's
  card colour, ±3 per channel — the card as the app draws it, read before the switch with only
  that camera shown (the untagged H.264 cards decode about 12 levels off the generator's hex),
  each card first held nearest its own hex.
- S4 an `audio_wav` export of the mix, decoded to PCM, sample-identical before and after.
- S5 one undo step "Switch by Speaker" giving back the project; the ops' shape: one new track
  "Program" directly in front of Cam A, the answer's `ops` = 1 + one `copy_pieces` per angle
  clip the pieces come from + one `set_track` per angle track + one `set_enabled` per camera
  clip, the angle tracks hidden, every piece's picture on and sound off.
- S6 `apply: false` answers the shots the applied call answers, `applied` false, `track` null,
  and the project unchanged.
- S7 (a) a microphone's loudness cache file deleted while open: refused as still being
  analysed; (b) a spare track holding 4,091 one-frame pieces: refused in SW-24's ceiling
  sentence.
- S8 an In–Out range 40–100 s: `render_frame` at 5, 20, 35, 110, 130 and 150 s byte-identical
  before and after; every angle track's clips split at 40 s and 100 s, pictures off inside
  and on outside, no track hidden; every angle piece in the selection after the edit (SW-23
  (f), the tail of a clip split at both ends included).
- S9 each shot of Cam A crossing its two files' join is two Program pieces, one of each file,
  meeting at the join; `render_frame` ten frames past the join reads Cam A's second file's
  frame 10 from the frame code.
- S10 its own instance (`-RCDevSwitchSpeakerAccept YES -FrameJobSwitchSpeakerMinShot 3`): first
  the 3 s and 2 s `apply: false` shots must differ; then Clip ▸ Switch by Speaker… by
  `perform_menu_item` on one copy gives, in `get_project`, the project `switch_by_speaker
  {min_shot: 3}` gives on another copy.
- S11 a second run with `track` = the Program track and `min_shot` 4: no new track, the Program
  track holds exactly that plan's pieces; a track holding a selected clip and an empty track
  refused in their sentences, nothing changed.
- S12 the default (no microphone is a camera) switches `enabled.audio` off on every camera clip
  inside the range and on no microphone; `mute_cameras: false` leaves every clip's
  `enabled.audio` as it was.
- S13 a document whose Cam B has sound, detached with `detach_audio`: `switch_by_speaker`
  (`apply` true and false) refused in SW-23 (h)'s sentence naming the picture half and its
  partner, the project unchanged; the sheet's summary (`snapshot_ui`) shows the same sentence;
  and in the dev-accept instance, whose accept presses Switch only on an edit, the sheet changes
  nothing (the layout dump carries no enabled state, so this is how "Switch disabled" is read).
- S14 (#457) a document with one camera clip selected, whose plan is refused ("needs at least
  two angles"): `{mute_cameras: "yes"}` answers exactly "mute_cameras must be true or false."
  and `{apply: "maybe"}` "apply must be true or false." — the argument errors before any plan —
  with the project and its undo top unchanged.
- S15 (#602) Replace the shots on near a transition: a front track "Earlier" holding a piece of
  the wide [40 s, 44 s) and a piece of Cam B [43 s, 48 s) dissolving into it for 1 s (a `split`
  of the wide's piece at 42.2 s alone refused in #427's sentence); `switch_by_speaker {track:
  Earlier, from: 42.2 s, to: 48 s}` applies, the track holding the wide's piece as [40 s,
  42.2 s) under its own id followed by exactly that plan's pieces, Cam B's piece gone, both
  microphone tracks' clips as they were; one undo gives the state before, and the fixture's six
  edits undone give the base.

`--mutant NAME` edits a `tree_copy.py` copy's Swift, builds its app and runs the named row on it:
CAUGHT exits 1, SURVIVED 0, a control that could not be performed 2. Thirteen mutants:
min-turn-ignored, crosstalk-never-wide, lead-twice, snap-removed (S1); ceiling-removed (S7);
whole-track-hidden (S8); sheet-min-shot-not-passed (S10); replace-clear-removed (S11);
mute-default-inverted (S12); linked-refusal-removed (S13); arguments-after-plan (S14);
replace-lifts-every-track, replace-by-split-and-delete (S15).
"""

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/sw2b"
FTURNS = ROOT / "tools/proof/media/creator/f_turns"
HOME = WORK / "home"
KEEP = {"media", "mutant-target"}
SEC = 600_000
FRAME = 20_000
LEAD = 0.2
TAU = 38_400 + 30_000 + 20_000  # two VAD chunks + half the window + one frame (SW-27)
NAMED_LIMIT = ("b24_f45", 17, "b", 99_313)  # SW-S4's named limit
MAX_CLIPS = 4096
CALL_BOUND = 900
CACHE_BOUND = 900
BUILD_BOUND = 1800
APPLIED = "b18_f55"
BLEEDY = "b12_f55"
COLOURS = {"a": (0xC0, 0x39, 0x2B), "b": (0x29, 0x80, 0xB9), "wide": (0x27, 0xAE, 0x60)}
ROWS = ["Z0"] + [f"S{i}" for i in range(1, 16)]
MAIN_ROWS = {"S1", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "S11", "S12", "S15"}
REFUSED = "Switch by Speaker was refused: "

SHOTS = "app/Sources/SpeakerSwitch+Shots.swift"
PLANNER = "app/Sources/SpeakerSwitch.swift"
EDIT = "app/Sources/SpeakerSwitch+Edit.swift"
SHEET = "app/Sources/SwitchSpeakerSheetController.swift"
HANDLER = "app/Sources/AgentServer+Switch.swift"
# Replace the shots on's clear, one `lift_range` held to its track (spec §11 #602).
REPLACE_LIFT = "if let why = try refusal(.liftRange(from: from, to: to, tracks: [replacing])) {"
# The clear it replaced: a `split` of each straddler at each bound, then one `delete`.
SPLIT_AND_DELETE = """            for at in [from, to] {
                for clip in trial.project.snapshot.clips(onTrack: replacing)
                where clip.start < at && at < clip.end {
                    if let why = try split(clip, at: at) { return .refused(why) }
                }
            }
            let cleared = trial.project.snapshot.clips(onTrack: replacing).filter(inside).map(\\.id)
            if !cleared.isEmpty, let why = try refusal(.delete(clips: cleared)) {
                return .refused(why)
            }
"""
# name → (row, [(path, anchor, replacement)])
MUTANTS = {
    "min-turn-ignored": ("S1", [(SHOTS, "angle = length >= ticks(settings.minTurn)",
                                 "angle = length >= 0")]),
    "crosstalk-never-wide": ("S1", [(SHOTS, "                    ? wide : nil\n",
                                     "                    ? nil : nil\n")]),
    "lead-twice": ("S1", [(SHOTS, "Ticks(turn.start) * step - ticks(settings.lead)))",
                           "Ticks(turn.start) * step - 2 * ticks(settings.lead)))")]),
    "snap-removed": ("S1", [(SHOTS, "func snap(_ t: Ticks) -> Ticks { ReelTime.snapToFrame(t, fps: fps) }",
                             "func snap(_ t: Ticks) -> Ticks { t }")]),
    "ceiling-removed": ("S7", [(PLANNER, "        if input.clipCount + added > most {",
                                "        if false, input.clipCount + added > most {")]),
    "whole-track-hidden": ("S8", [(EDIT, "if !all.isEmpty, all.allSatisfy({ ids.contains($0.id) && inside($0) }) {",
                                   "if !all.isEmpty {")]),
    "sheet-min-shot-not-passed": ("S10", [(
        SHEET, "from: document, clips: nil, pairing: chosenPairing, range: nil, settings: settings)",
        "from: document, clips: nil, pairing: chosenPairing, range: nil,\n"
        "            settings: { var s = settings; s.minShot = SpeakerSwitch.Settings().minShot; "
        "return s }())")]),
    "replace-clear-removed": ("S11", [(EDIT, REPLACE_LIFT, "if false, " + REPLACE_LIFT[3:])]),
    "mute-default-inverted": ("S12", [(EDIT, "return !input.microphones.contains { angles.contains($0.track) }",
                                       "return input.microphones.contains { angles.contains($0.track) }")]),
    "linked-refusal-removed": ("S13", [(EDIT, "if let partner = clip.linked {",
                                        "if false, let partner = clip.linked {")]),
    "replace-lifts-every-track": ("S15", [(
        EDIT, "refusal(.liftRange(from: from, to: to, tracks: [replacing]))",
        "refusal(.liftRange(from: from, to: to, tracks: nil))")]),
    "replace-by-split-and-delete": ("S15", [(
        EDIT, "            " + REPLACE_LIFT + "\n                return .refused(why)\n            }\n",
        SPLIT_AND_DELETE)]),
    "arguments-after-plan": ("S14", [(
        HANDLER,
        "        let mute = try boolArg(a, \"mute_cameras\")\n"
        "        let apply = try boolArg(a, \"apply\") ?? true\n",
        "        let mute = try? boolArg(a, \"mute_cameras\")\n"
        "        let apply = (try? boolArg(a, \"apply\")) ?? true\n")]),
}

results = {}
selected = set(ROWS)
BINARY = None


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


def cam_b_with_sound():
    """S13's Cam B: cam_b.mov with b18_f55's Mic B muxed in as its own sound."""
    out = WORK / "media" / "cam_b_sound.mov"
    if out.exists():
        return out
    out.parent.mkdir(parents=True, exist_ok=True)
    partial = out.with_suffix(".partial.mov")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(FTURNS / "cam_b.mov"), "-i",
                    str(FTURNS / f"mic_b_{APPLIED}.wav"), "-map", "0:v", "-map", "1:a",
                    "-c:v", "copy", "-c:a", "aac", str(partial)],
                   check=True, timeout=600, env=bounded.child_env())
    partial.rename(out)
    return out


class Doc:
    """One F-TURNS variant as a saved package, its clips selected and its caches made."""

    def __init__(self, client, manifest, variant, name=None, sound_cam_b=False):
        self.client = client
        self.name = name or variant
        self.variant = variant
        self.path = WORK / f"{self.name}.framejob"
        self.close()
        if self.path.exists():
            shutil.rmtree(self.path)
        row = next(v for v in manifest["variants"] if v["name"] == variant)
        client.call("new_project", path=str(self.path))
        try:
            try:
                self.call("set_canvas", width=1920, height=1080, fps=[30, 1])
            except mcp.ToolError as error:
                if "made no change" not in str(error):
                    raise
            first = self.state()["tracks"][0]["id"]
            self.call_with("set_track", {"track": first, "name": "Wide"})
            names = (["Sound"] if sound_cam_b else []) + ["Cam B", "Cam A", "Mic B", "Mic A"]
            ids = {"Wide": first}
            for title in names:
                ids[title] = self.call_with("add_track", {"name": title})["new_tracks"][0]
            order = [tr["id"] for tr in self.state()["tracks"]]
            want = [ids[n] for n in ["Wide"] + names]
            if order != want:
                raise RuntimeError(f"tracks back to front {order}, wanted {want}")
            self.wide, self.b, self.a = ids["Wide"], ids["Cam B"], ids["Cam A"]
            self.mic_b, self.mic_a = ids["Mic B"], ids["Mic A"]
            self.sound = ids.get("Sound")
            cam_b = cam_b_with_sound() if sound_cam_b else FTURNS / "cam_b.mov"
            self.c_wide = self.place(FTURNS / "cam_wide.mov", self.wide)
            self.c_b = self.place(cam_b, self.b)
            self.c_a1 = self.place(FTURNS / "cam_a_1.mov", self.a)
            self.half = self.end(self.c_a1)
            self.c_a2 = self.place(FTURNS / "cam_a_2.mov", self.a, at=self.half)
            self.c_mb = self.place(FTURNS / row["mic_b"], self.mic_b)
            self.c_ma = self.place(FTURNS / row["mic_a"], self.mic_a)
            self.clips = [self.c_wide, self.c_b, self.c_a1, self.c_a2, self.c_mb, self.c_ma]
            self.angle_clips = self.clips[:4]
            self.names = {self.wide: "wide", self.b: "b", self.a: "a"}
            state = self.state()
            self.media_of = {c["id"]: c["source"]["media"] for c in state["clips"]}
            self.select()
        except Exception:
            self.close()
            raise

    def call(self, tool, **arguments):
        return self.call_with(tool, arguments)

    def call_with(self, tool, arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def place(self, path, track, at=0):
        media = self.call("import_media", path=str(path))["media"]
        return self.call("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def clip(self, cid, state=None):
        return next(c for c in (state or self.state())["clips"] if c["id"] == cid)

    def end(self, cid, state=None):
        c = self.clip(cid, state)
        return c["start"] + c["duration"]

    def on_track(self, track, state=None):
        return sorted((c for c in (state or self.state())["clips"] if c["track"] == track),
                      key=lambda c: c["start"])

    def select(self, clips=None):
        self.call("set_selection", clips=clips or self.clips)

    def switch(self, **arguments):
        return self.call_with("switch_by_speaker", arguments)

    def ready(self):
        """Polls `apply: false` until no microphone is still being analyzed."""
        deadline = time.monotonic() + CACHE_BOUND
        while True:
            try:
                return self.switch(apply=False)
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

def score(doc, shots, expected, variant):
    """(pass, detail): SW-27's angles, grid and τ, with SW-S4's named limit."""
    got = [doc.names.get(s["angle"], "?") for s in shots]
    want = [row["angle"] for row in expected]
    misses, limited, errors = [], [], []
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
        angle = got[index] if index < len(got) else "?"
        if abs(late) > TAU:
            if (variant, index, angle) == NAMED_LIMIT[:3] and TAU < late <= NAMED_LIMIT[3]:
                limited.append(f"shot {index} ({angle}) {late / 600:.1f} ms, the named limit")
            else:
                misses.append(f"shot {index} ({angle}) {late / 600:.1f} ms from onset − lead")
    worst = max((abs(e) for e in errors), default=0)
    detail = (f"{variant}: {len(shots)} shots, worst {worst:.1f} ms"
              + (f"; limited: {limited}" if limited else "")
              + (f"; misses: {misses}" if misses else ""))
    return not misses, detail


def rgb(path):
    """The PNG at `path` as an H × W × 3 uint8 array, decoded by ffmpeg."""
    probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
                            "stream=width,height", "-of", "csv=p=0", str(path)],
                           capture_output=True, text=True, check=True)
    width, height = (int(x) for x in probe.stdout.strip().split(","))
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "rawvideo",
                          "-pix_fmt", "rgb24", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.uint8).reshape(height, width, 3)


def render(doc, seconds_or_ticks, tag, ticks=False):
    path = WORK / f"{doc.name}-{tag}.png"
    doc.call("render_frame", t=seconds_or_ticks if ticks else t(seconds_or_ticks), path=str(path))
    return path


def frame_code(pixels):
    """The 16-block binary frame code along the bottom (bit 0 leftmost, white = 1)."""
    row = pixels[1050]
    return sum(1 << i for i in range(16) if row[i * 120 + 60].mean() > 200)


def pcm(path):
    return subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-f", "s32le", "-acodec",
                           "pcm_s32le", "-"], capture_output=True, check=True).stdout


# ---- the rows ----------------------------------------------------------------------

def s1_variant(client, manifest, variant):
    doc = Doc(client, manifest, variant)
    try:
        answer = doc.ready()
        ok, detail = score(doc, answer["shots"], manifest["expected_shots"], variant)
        check("S1", ok, "apply: false, " + detail)
        if variant == BLEEDY:
            s2(doc, manifest)
    finally:
        doc.close()


def s2(doc, manifest):
    answer = doc.switch(apply=False, bleed_db=15)
    speaks = {"a": [], "b": []}
    for turn in manifest["turns"]:
        for who in (["a", "b"] if turn["speaker"] == "both" else [turn["speaker"]]):
            speaks[who].append((t(turn["onset_seconds"]), t(turn["end_seconds"])))
    silent = []
    for shot in answer["shots"]:
        who = doc.names.get(shot["angle"])
        if who in speaks and not any(a < shot["end"] and b > shot["start"] for a, b in speaks[who]):
            silent.append((who, shot["start"], shot["end"]))
    check("S2", not silent, f"{doc.variant} bleed_db 15: {len(answer['shots'])} shots, shots of a "
          f"silent person {silent}")


def main_rows(client, manifest):
    doc = Doc(client, manifest, APPLIED)
    try:
        r0 = doc.ready()
        doc.save()
        base = model(doc.state())
        if "S10" in selected:
            for copy in ("s10-menu", "s10-tool"):
                target = WORK / f"{copy}.framejob"
                shutil.rmtree(target, ignore_errors=True)
                shutil.copytree(doc.path, target)
        check("S6", r0.get("applied") is False and r0.get("track") is None
              and "step" not in r0 and model(doc.state()) == base,
              f"apply: false answers applied {r0.get('applied')}, track {r0.get('track')}, "
              f"the project unchanged {model(doc.state()) == base}")
        if "S1" in selected:
            # At min_shot 2 a reply's shot would merge away anyway; at 0.5 only min_turn holds it.
            fine = doc.switch(apply=False, min_shot=0.5)
            ok, detail = score(doc, fine["shots"], manifest["expected_shots"], APPLIED)
            check("S1", ok, "min_shot 0.5 (min_turn alone holds the replies), " + detail)
        before_wav = None
        if "S4" in selected:
            client.export_with({"project": str(doc.path), "preset": "audio_wav",
                                "path": str(WORK / "s4-before.wav")})
            before_wav = pcm(WORK / "s4-before.wav")
        cards = None
        if "S3" in selected:
            cards = attempt(lambda: card_colours(doc, base), "S3")
        r1 = doc.switch()
        applied = doc.state()
        ok, detail = score(doc, r1["shots"], manifest["expected_shots"], APPLIED)
        check("S1", ok and r1.get("applied") is True, "applied, " + detail)
        check("S6", r1["shots"] == r0["shots"], f"apply: false's {len(r0['shots'])} shots are "
              f"the applied call's {len(r1['shots'])}: {r1['shots'] == r0['shots']}")
        program = r1["track"]
        attempt(lambda: s5_shape(doc, r1, applied), "S5")
        if cards:
            attempt(lambda: s3(doc, manifest, cards), "S3")
        attempt(lambda: s9(doc, r1, applied), "S9")
        attempt(lambda: s12_default(doc, applied), "S12")
        if before_wav is not None:
            client.export_with({"project": str(doc.path), "preset": "audio_wav",
                                "path": str(WORK / "s4-after.wav")})
            after = pcm(WORK / "s4-after.wav")
            check("S4", len(after) > 0 and after == before_wav,
                  f"the mix decoded: {len(before_wav)} bytes before, {len(after)} after, "
                  f"identical {after == before_wav}")
        if "S11" in selected:
            attempt(lambda: s11(doc, program, applied), "S11")
        undone = doc.call("undo").get("undone")
        check("S5", undone == SPEAKER and model(doc.state()) == base,
              f"one undo, named {undone!r}, gives back the project {model(doc.state()) == base}")
        if "S12" in selected:
            attempt(lambda: s12_off(doc, base), "S12")
        if "S15" in selected:
            attempt(lambda: s15(doc, base), "S15")
        if "S8" in selected:
            attempt(lambda: s8(doc, base), "S8")
        if "S7" in selected:
            attempt(lambda: s7(doc, base), "S7")
    finally:
        doc.close()


SPEAKER = "Switch by Speaker"


def s5_shape(doc, answer, state):
    tracks = [tr["id"] for tr in state["tracks"]]
    program = answer["track"]
    by_id = {tr["id"]: tr for tr in state["tracks"]}
    pieces = doc.on_track(program, state)
    sources = {p["source"]["media"] for p in pieces}
    angle_media = {doc.media_of[c] for c in doc.angle_clips}
    hidden = all(by_id[tr]["hidden"] for tr in (doc.wide, doc.b, doc.a))
    switches = all(p["enabled"]["video"] and not p["enabled"]["audio"] for p in pieces)
    want_ops = 1 + len(sources) + 3 + len(doc.angle_clips)
    ok = (len(tracks) == 6 and tracks.index(program) == tracks.index(doc.a) + 1
          and by_id[program]["name"] == "Program" and sources <= angle_media and hidden
          and switches and answer["ops"] == want_ops and answer.get("step") == SPEAKER)
    check("S5", ok, f"Program {program} at {tracks.index(program)} (Cam A at "
          f"{tracks.index(doc.a)}), {len(pieces)} pieces from {len(sources)} angle clips, "
          f"ops {answer['ops']} (want {want_ops}), angles hidden {hidden}, pieces picture on and "
          f"sound off {switches}, step {answer.get('step')!r}")


def card_colours(doc, base):
    """Each camera's card as the app draws it, read before the switch with only that camera
    shown (the files are untagged H.264, so the drawn colour is the decoder's, not the hex the
    generator wrote; COLOURS says which card is whose). Each must be its hex's nearest."""
    cards = {}
    for who, hide in (("a", []), ("b", [doc.a]), ("wide", [doc.a, doc.b])):
        for track in hide:
            doc.call("set_track", track=track, hidden=True)
        pixels = rgb(render(doc, 1.0, f"s3-card-{who}"))
        for _ in hide:
            doc.call("undo")
        cards[who] = tuple(int(v) for v in pixels[540, 960])
    nearest = {who: min(COLOURS, key=lambda k: sum((a - b) ** 2 for a, b in zip(got, COLOURS[k])))
               for who, got in cards.items()}
    check("S3", all(nearest[w] == w for w in cards) and model(doc.state()) == base,
          f"the cards as drawn {cards}, each nearest its own hex {nearest}")
    return cards


def s3(doc, manifest, cards):
    wrong = []
    turns = [tr for tr in manifest["turns"] if tr["kind"] == "turn"]
    for index, turn in enumerate(turns):
        middle = (turn["onset_seconds"] + turn["end_seconds"]) / 2
        pixels = rgb(render(doc, middle, f"s3-{index}"))
        got = tuple(int(v) for v in pixels[540, 960])
        want = cards[turn["speaker"]]
        if any(abs(g - w) > 3 for g, w in zip(got, want)):
            wrong.append((round(middle, 2), turn["speaker"], got))
    check("S3", not wrong, f"{len(turns)} turns' middles; off the speaker's card colour: {wrong}")


def s9(doc, answer, state):
    crossing = [s for s in answer["shots"]
                if s["angle"] == doc.a and s["start"] < doc.half < s["end"]]
    if not crossing:
        check("S9", False, f"no shot of Cam A crosses its join at {doc.half}")
        return
    m1, m2 = doc.media_of[doc.c_a1], doc.media_of[doc.c_a2]
    pieces = doc.on_track(answer["track"], state)
    good = []
    for shot in crossing:
        inside = [(p["start"], p["start"] + p["duration"], p["source"]["media"]) for p in pieces
                  if p["start"] >= shot["start"] and p["start"] < shot["end"]]
        good.append(inside == [(shot["start"], doc.half, m1), (doc.half, shot["end"], m2)])
    probe = doc.half + 10 * FRAME
    code = None
    if any(s["start"] <= probe < s["end"] for s in crossing):
        code = frame_code(rgb(render(doc, probe, "s9", ticks=True)))
    check("S9", all(good) and code == 10,
          f"{len(crossing)} Cam A shots across the join at {doc.half}: two pieces each {good}; "
          f"ten frames past the join the frame code reads {code} (want 10)")


def s12_default(doc, state):
    camera = [doc.clip(c, state)["enabled"]["audio"] for c in doc.angle_clips]
    mics = [doc.clip(c, state)["enabled"]["audio"] for c in (doc.c_mb, doc.c_ma)]
    check("S12", not any(camera) and all(mics),
          f"the default: camera clips' sound {camera} (want all off), microphones' {mics}")


def s12_off(doc, base):
    answer = doc.switch(mute_cameras=False)
    state = doc.state()
    same = all(doc.clip(c, state)["enabled"]["audio"]
               == next(x for x in base["clips"] if x["id"] == c)["enabled"]["audio"]
               for c in doc.clips)
    doc.call("undo")
    check("S12", answer.get("mute_cameras") is False and same,
          f"mute_cameras: false leaves every clip's enabled.audio {same}")


def s11(doc, program, applied):
    tracks = len(applied["tracks"])
    r2 = doc.switch(track=program, min_shot=4)
    state = doc.state()
    m1, m2 = doc.media_of[doc.c_a1], doc.media_of[doc.c_a2]
    want = []
    for shot in r2["shots"]:
        if shot["angle"] == doc.a and shot["start"] < doc.half < shot["end"]:
            want += [(shot["start"], doc.half, m1), (doc.half, shot["end"], m2)]
        else:
            media = {doc.wide: doc.media_of[doc.c_wide], doc.b: doc.media_of[doc.c_b]}.get(
                shot["angle"]) or (m1 if shot["end"] <= doc.half else m2)
            want.append((shot["start"], shot["end"], media))
    got = [(p["start"], p["start"] + p["duration"], p["source"]["media"])
           for p in doc.on_track(program, state)]
    check("S11", len(state["tracks"]) == tracks and r2["track"] == program and got == want,
          f"min_shot 4 onto Program {program}: tracks {len(state['tracks'])} (was {tracks}), "
          f"{len(got)} pieces equal the plan's {len(want)}: {got == want}")
    doc.call("undo")
    back = model(doc.state()) == model(applied)
    why = refused(lambda: doc.switch(track=doc.mic_a))
    want_why = f"Track {doc.mic_a} cannot take the shots: it holds a selected clip."
    check("S11", back and why is not None and want_why in why and model(doc.state()) == model(applied),
          f"undo gives back the first run {back}; Mic A refused: {why!r}")
    spare = doc.call_with("add_track", {"name": "Spare"})["new_tracks"][0]
    why = refused(lambda: doc.switch(track=spare))
    want_why = f"Track {spare} cannot take the shots: it has nothing between "
    doc.call("undo")
    check("S11", why is not None and want_why in why and model(doc.state()) == model(applied),
          f"an empty track refused: {why!r}")


def s15(doc, base):
    """#602: Replace the shots on over a range whose start lies within a transition's own length
    on the replaced track. A front track "Earlier" holds a piece of the wide [40 s, 44 s) and a
    piece of Cam B [43 s, 48 s) dissolving into it for 1 s; a switch over {42.2 s, 48 s} onto it
    must apply, because what the clear leaves — the wide's piece [40 s, 42.2 s) — is legal,
    although a `split` at 42.2 s alone leaves a 1.8 s piece under a 1 s dissolve."""
    start, cut, end = t(40), t(42.2), t(48)
    earlier = doc.call_with("add_track", {"name": "Earlier"})["new_tracks"][0]
    wide, cam_b = doc.media_of[doc.c_wide], doc.media_of[doc.c_b]
    p1 = doc.call("add_clip", track=earlier, media=wide, at=start)["new_clips"][0]
    doc.call("trim_end", clip=p1, to=t(44))
    p2 = doc.call("add_clip", track=earlier, media=cam_b, at=t(44))["new_clips"][0]
    doc.call("trim_end", clip=p2, to=t(49))
    doc.call("move_clip", clips=[p2], delta=-SEC)
    edits = 6
    try:
        fixture = [(c["id"], c["start"], c["start"] + c["duration"],
                    c.get("transition_in") is not None) for c in doc.on_track(earlier)]
        check("S15", fixture == [(p1, start, t(44), False), (p2, t(43), end, True)],
              f"Earlier holds the wide [40 s, 44 s) and Cam B [43 s, 48 s) dissolving into it: "
              f"{fixture}")
        # The contrast the issue rests on: the split alone is the rule's refusal.
        sentence = (f"clips {p1} and {p2} would overlap by {SEC} ticks, more than half of the "
                    f"shorter piece the cut leaves ({(t(44) - cut) // 2} ticks)")
        why = refused(lambda: doc.call("split", clips=[p1], at=cut))
        check("S15", why is not None and sentence in why,
              f"a split of the wide's piece at 42.2 s alone is refused: {why!r}")
        doc.select()
        before = doc.state()
        mics = [doc.clip(c, before) for c in (doc.c_mb, doc.c_ma)]
        answer = None
        try:
            answer = doc.call_with("switch_by_speaker", {"track": earlier, "from": cut, "to": end})
        except mcp.ToolError as error:
            check("S15", False, f"the switch over {{42.2 s, 48 s}} onto Earlier: {error}")
            return
        state = doc.state()
        want = [(start, cut, wide)]
        media = {doc.wide: wide, doc.b: cam_b}
        for shot in answer["shots"]:
            if shot["angle"] == doc.a and shot["start"] < doc.half < shot["end"]:
                want += [(shot["start"], doc.half, doc.media_of[doc.c_a1]),
                         (doc.half, shot["end"], doc.media_of[doc.c_a2])]
            else:
                a_media = doc.media_of[doc.c_a1 if shot["end"] <= doc.half else doc.c_a2]
                want.append((shot["start"], shot["end"], media.get(shot["angle"], a_media)))
        got = [(c["start"], c["start"] + c["duration"], c["source"]["media"])
               for c in doc.on_track(earlier, state)]
        kept = doc.on_track(earlier, state)[0]["id"] if got else None
        mics_after = [doc.clip(c, state) for c in (doc.c_mb, doc.c_ma)]
        check("S15", answer.get("track") == earlier and got == want and kept == p1
              and all(c["id"] != p2 for c in state["clips"]) and mics_after == mics,
              f"applied onto Earlier {answer.get('track') == earlier}: {len(got)} pieces, the "
              f"wide's [40 s, 42.2 s) kept as clip {kept} then exactly the plan's "
              f"{len(answer['shots'])} shots {got == want}; Cam B's piece gone "
              f"{all(c['id'] != p2 for c in state['clips'])}; both microphones' clips as they "
              f"were {mics_after == mics}")
        undone = doc.call("undo").get("undone")
        check("S15", undone == SPEAKER and model(doc.state()) == model(before),
              f"one undo, named {undone!r}, gives back the project {model(doc.state()) == model(before)}")
    finally:
        for _ in range(edits):
            doc.call("undo")
        doc.select()
        check("S15", model(doc.state()) == base,
              f"the fixture's {edits} edits undone give back the base {model(doc.state()) == base}")


def s8(doc, base):
    start, end = t(40), t(100)
    doc.call("set_range", start=start, end=end)
    times = [5, 20, 35, 110, 130, 150]
    before = [render(doc, s, f"s8-before-{i}").read_bytes() for i, s in enumerate(times)]
    doc.select()
    answer = doc.switch()
    state = doc.state()
    chosen = set(doc.call("get_project")["selection"])
    after = [render(doc, s, f"s8-after-{i}").read_bytes() for i, s in enumerate(times)]
    same = [a == b for a, b in zip(before, after)]
    by_id = {tr["id"]: tr for tr in state["tracks"]}
    splits = []
    for track in (doc.wide, doc.b, doc.a):
        clips = doc.on_track(track, state)
        edges = {c["start"] for c in clips} | {c["start"] + c["duration"] for c in clips}
        inside = [c for c in clips if c["start"] >= start and c["start"] + c["duration"] <= end]
        outside = [c for c in clips if c not in inside]
        splits.append(start in edges and end in edges and not by_id[track]["hidden"]
                      and inside and all(not c["enabled"]["video"] for c in inside)
                      and all(c["enabled"]["video"] for c in outside))
    # SW-23 (f): every piece a split made from a selected angle clip stays selected, the
    # tail after 100 s of a clip straddling both ends included.
    unselected = [c["id"] for track in (doc.wide, doc.b, doc.a)
                  for c in doc.on_track(track, state) if c["id"] not in chosen]
    doc.call("undo")
    doc.call("set_range")
    check("S8", all(same) and all(splits) and not unselected
          and answer["shots"][0]["start"] == start
          and answer["shots"][-1]["end"] == end and model(doc.state()) == base,
          f"range 40–100 s: frames at {times} byte-identical {same}; Wide, Cam B, Cam A split at "
          f"both ends, pictures off inside only, not hidden {splits}; angle pieces left out of "
          f"the selection {unselected}")


def s7(doc, base):
    spare = doc.call_with("add_track", {"name": "Spare"})["new_tracks"][0]
    count = MAX_CLIPS - len(base["clips"]) - 1
    ranges = [[i * FRAME, (i + 1) * FRAME] for i in range(count)]
    doc.call("copy_pieces", clip=doc.c_ma, track=spare, ranges=ranges)
    held = len(doc.state()["clips"])
    why = refused(lambda: doc.switch(apply=False))
    want = f"the most is {MAX_CLIPS} — raise the minimum shot."
    doc.call("undo")
    doc.call("undo")
    check("S7", why is not None and "Switch by Speaker would add" in why and want in why
          and f"clips to {held};" in why and model(doc.state()) == base,
          f"{held} clips: {why!r}")
    media = doc.media_of[doc.c_ma]
    gone = []
    for found in (doc.path / "cache" / "loudness").glob(f"{media}.*"):
        found.unlink()
        gone.append(found.name)
    why = refused(lambda: doc.switch(apply=False))
    want = (f"The microphone on track {doc.mic_a} is still being analyzed — its loudness has not "
            "been measured yet.")
    check("S7", bool(gone) and why is not None and want in why,
          f"deleted {gone}: {why!r}")


def s13_rows(client, manifest):
    doc = Doc(client, manifest, APPLIED, name="s13", sound_cam_b=True)
    try:
        doc.ready()
        detached = doc.call("detach_audio", clip=doc.c_b)
        state = doc.state()
        partner = doc.clip(doc.c_b, state).get("linked")
        doc.select()
        doc.save()
        target = WORK / "s13-accept.framejob"
        shutil.rmtree(target, ignore_errors=True)
        shutil.copytree(doc.path, target)
        before = model(doc.state())
        want = (f"clip {doc.c_b} on track {doc.b} is linked to clip {partner} (Detach Audio's "
                "pair); Switch by Speaker cuts between cameras with no link — Attach Audio first")
        whys = [refused(lambda a=apply: doc.switch(apply=a)) for apply in (True, False)]
        check("S13", partner is not None and all(w is not None and REFUSED + want in w for w in whys)
              and model(doc.state()) == before,
              f"detach_audio {detached.get('new_clips') if isinstance(detached, dict) else ''}; "
              f"both apply values refused {whys}")
        doc.call("perform_menu_item", path=["Clip", "Switch by Speaker…"])
        try:
            text = summary_text(doc, "s13-sheet")
        finally:
            doc.call("cancel_sheet")
        check("S13", text is not None and want in text and model(doc.state()) == before,
              f"the sheet's summary {text!r}")
    finally:
        doc.close()


def s14(client):
    """#457: a malformed `mute_cameras` or `apply` is refused before any plan."""
    path = WORK / "s14.framejob"
    shutil.rmtree(path, ignore_errors=True)

    def call(tool, **arguments):
        return client.call_with(tool, {"project": str(path), **arguments})

    def undo_top():
        try:
            name = call("undo").get("undone")
        except mcp.ToolError:
            return None
        call("redo")
        return name

    client.call("new_project", path=str(path))
    try:
        track = call("get_project")["project"]["tracks"][0]["id"]
        media = call("import_media", path=str(FTURNS / "cam_wide.mov"))["media"]
        clip = call("add_clip", track=track, media=media, at=0)["new_clips"][0]
        call("set_selection", clips=[clip])
        before, top = model(call("get_project")["project"]), undo_top()
        plain = refused(lambda: call("switch_by_speaker"))
        check("S14", plain is not None and REFUSED + "Switch by Speaker needs at least two angles"
              in plain, f"the plan itself is refused: {plain!r}")
        for key, value in (("mute_cameras", "yes"), ("apply", "maybe")):
            why = refused(lambda k=key, v=value: call("switch_by_speaker", **{k: v}))
            want = f"switch_by_speaker: {key} must be true or false."
            after = model(call("get_project")["project"])
            check("S14", why == want and after == before and undo_top() == top,
                  f"{{{key}: {value!r}}}: {why!r} (want {want!r}); project unchanged "
                  f"{after == before}, undo top {top!r}")
    finally:
        try:
            client.call("close_project", project=str(path), discard=True)
        except mcp.ToolError:
            pass


def summary_text(doc, tag):
    got = doc.call("snapshot_ui", window="sheet", path=str(WORK / f"{tag}.png"))
    path = got.get("layout_path") if isinstance(got, dict) else None
    if not path:
        return None
    views = json.loads(Path(path).read_text()).get("views") or []
    found = [v for v in views if v.get("id") == "switchspeaker.summary" and not v.get("hidden")]
    return found[0].get("text") if found else None


# ---- the accept instance (S10, S13's half) ----------------------------------------

def accept_rows(client):
    if "S10" in selected:
        attempt(lambda: s10(client), "S10")
    if "S13" in selected:
        attempt(lambda: s13_accept(client), "S13")


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


def s10(client):
    tool = Opened(client, "s10-tool")
    try:
        _, ids = all_clips(tool)
        tool.call("set_selection", clips=ids)
        three = tool.call("switch_by_speaker", apply=False, min_shot=3)["shots"]
        two = tool.call("switch_by_speaker", apply=False)["shots"]
        if three == two:
            check("S10", False, "the 3 s and 2 s plans are the same, so the row proves nothing")
            return
        tool.call("switch_by_speaker", min_shot=3)
        want = model(tool.call("get_project")["project"])
    finally:
        tool.close()
    menu = Opened(client, "s10-menu")
    try:
        before, ids = all_clips(menu)
        menu.call("set_selection", clips=ids)
        menu.call("perform_menu_item", path=["Clip", "Switch by Speaker…"])
        deadline = time.monotonic() + 60
        got = model(before)
        while time.monotonic() < deadline:
            got = model(menu.call("get_project")["project"])
            if len(got["tracks"]) > len(before["tracks"]):
                break
            time.sleep(0.5)
        check("S10", got == want and len(got["tracks"]) > len(before["tracks"]),
              f"the menu with Minimum shot 3 (the launch default) gives the tool's min_shot 3 "
              f"project: {got == want} ({len(three)} shots at 3 s, {len(two)} at 2 s)")
    finally:
        menu.close()


def s13_accept(client):
    doc = Opened(client, "s13-accept")
    try:
        before, _ = all_clips(doc)
        ids = [c["id"] for c in before["clips"] if c["enabled"]["video"] or
               c["track"] in {tr["id"] for tr in before["tracks"] if tr["name"].startswith("Mic")}]
        doc.call("set_selection", clips=ids)
        doc.call("perform_menu_item", path=["Clip", "Switch by Speaker…"])
        time.sleep(3)
        after = model(doc.call("get_project")["project"])
        try:
            doc.call("cancel_sheet")
            up = True
        except mcp.ToolError:
            up = False
        check("S13", up and after == model(before),
              f"with the dev accept the refused sheet stays up {up} and changes nothing "
              f"{after == model(before)}")
    finally:
        doc.close()


# ---- launches ----------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z0", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def with_instance(binary, tag, body, arguments=()):
    log = WORK / f"instance-{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), list(arguments), env=env, log_path=str(log),
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


def rows(client, manifest, binary):
    if selected & MAIN_ROWS:
        attempt(lambda: main_rows(client, manifest), *sorted(selected & MAIN_ROWS))
    if selected & {"S1", "S2"}:
        for variant in [v["name"] for v in manifest["variants"]]:
            # b18_f55 is scored by main_rows; S2 alone needs only b12_f55.
            if variant == APPLIED or ("S1" not in selected and variant != BLEEDY):
                continue
            attempt(lambda v=variant: s1_variant(client, manifest, v), "S1", "S2")
    if "S13" in selected:
        attempt(lambda: s13_rows(client, manifest), "S13")
    if "S14" in selected:
        attempt(lambda: s14(client), "S14")
    if selected & {"S10", "S13"}:
        arguments = ["-RCDevSwitchSpeakerAccept", "YES", "-FrameJobSwitchSpeakerMinShot", "3"]
        if not with_instance(binary, "accept", accept_rows, arguments):
            for row in selected & {"S10", "S13"}:
                check(row, False, "the accept instance did not listen")


def skip_all(why):
    for row in sorted(selected - {"Z0"}):
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
    print(f"SW2b — the {name} MUTANT ({row} must FAIL)", flush=True)
    manifest = fturns()
    if manifest is None:
        print(f"mutant {name}: the control could not be performed — F-TURNS skipped (no voice)")
        return 2
    selected = {row, "Z0"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"))
    why = why or edited(name, Path(made))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    app, why = tree_copy.build_app(made, BUILD_BOUND)
    if app is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    binary = proof_app.executable(app)
    if not with_instance(binary, "mutant", lambda c: rows(c, manifest, binary)):
        print(f"mutant {name}: the control could not be performed — the app did not listen")
        return 2
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
    WORK.mkdir(parents=True, exist_ok=True)
    for child in WORK.iterdir():
        if child.name not in KEEP:
            tree_copy.remove_tree(str(child)) if child.is_dir() else child.unlink()
    HOME.mkdir(parents=True, exist_ok=True)
    if args.mutant:
        return run_mutant(args.mutant)

    print(f"SW2b — Switch by Speaker ({proof_app.config()} build)", flush=True)
    binary = Path(args.app) if args.app else proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)
    manifest = fturns()
    if manifest is None:
        skip_all("F-TURNS needs say's Samantha and Daniel")
    elif args.socket:
        client = mcp.MCP(args.socket, timeout=CALL_BOUND)
        rows(client, manifest, binary)
        parity(Path(args.socket).parent / "framejob.log", "the given instance")
    else:
        if not with_instance(binary, "plain", lambda c: rows(c, manifest, binary)):
            for row in selected - {"Z0"}:
                check(row, False, "the app did not listen")

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
