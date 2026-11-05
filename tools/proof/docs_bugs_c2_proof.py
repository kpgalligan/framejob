#!/usr/bin/env python3
"""Docs bugs, batch c2 (#496 #489 #501 #502, spec §11 TX-35, TX-36): Generate Captions reads what
is heard, the Transcript tab names clips, Remove Filler Words says a file is missing, and
detect_fillers says what its wall is.

    python3 tools/proof/docs_bugs_c2_proof.py [--only C1,P2,…] [--mutant NAME] [--app PATH]
                                              [--base-sources PATH]
    RC_PROOF_APP=release python3 tools/proof/docs_bugs_c2_proof.py

The built app (`proof_app`'s choice) with the dummy `proof-key` in a scratch `-RCSecretFolder`,
AssemblyAI at the loopback `assemblyai_fake.py` under the cloud instruments' lock: nothing is paid
for. Presses and labels past `snapshot_ui`'s 200 characters run in `docs_bugs_c2_probe.swift`, built
through `swift_build.build()` and loaded with `docs_bugs_c2_beep.c`, so a press never sounds, over
packages the app saved. `(c)` marks a CONTROL, which passes on the base too; every other row is red
on the frozen base app with `--base-sources` set to the base's `app/Sources`.

- C0 (c) nothing muted: `clips_read` both. C1 one clip muted with `set_audio`, `transcribe {engine:
  assemblyai}` with no clips: `clips_read` the other, no `trimmed`, each line once. C2 the same with
  `set_track muted`. C3 the same with a solo on the other track. C4 (c) `clips: [muted]`: read. C5
  every clip muted, none named: TX-35's refusal, no track added. C6 the sheet's capture reads
  "1 clip". C7 (c) audio switched off alone: the older refusal.
- P1 (probe) a muted clip beside a heard one: `jobs(in: .all)` the heard clip. P2 everything muted,
  nothing selected, both engines: the heard sentence, and the note lacks "Only a clip whose media
  has sound". P3 (c) the muted clip selected: `jobs(in: .selection)` reads it. P4 the same: the sheet
  opens on Whole timeline, jobs the heard clip. P5 (c) both selected: opens on Selected clips, 2
  jobs. P6 (c) every clip muted, one selected: opens on Selected clips, 1 job. P7 (c) audio off
  alone, both engines: "Nothing to transcribe", and the note keeps its sentence.
- N1 the tab's same-speech note names both clips and ids. N2 a clip's audio off: the named row. N3
  (c) `get_timeline_transcript`'s `notes` and `no_words[].tag` as TX-10 words them.
- F1 (probe) a press on the lost row: no beep, button off, the row and `lastError` say the file is
  missing, nothing uploaded. F2 (probe) a press on the other row, the run ends: the note names the
  lost file. F3 (probe) the sheet reopened: the note, no row. F4 `transcribe_for_fillers` on the lost
  file: the missing sentence. F5 (c) a present file no clip plays: the older sentence. F6
  `detect_fillers` with one of two files lost: the note. F7 the only file lost: the note, and not
  "Nothing in scope". F8 (probe) the same project, the sheet: the same.
- W1 a bare overlap and W2 a stored transition: "uh" 9.3-9.6 s and "um" 11.4-11.7 s dropped with the
  new sentence. W3 (c) "um" 8.5-8.8 s kept, and with B moved away nothing dropped. W4 `tools/list`'s
  `detect_fillers` has the clause and not "crosses a transition". W5 (c) B on a second track over A's
  fillers, playing a media with no transcript: nothing dropped.
- H1 (probe) the sheet's hint holds the new clause and not "a nest or a transition". H2 (probe) W1's
  project: the note holds the new left-in clause.

Z1 is `grep "Frame Job: "` over the launch's log.

`--mutant NAME`: the named decision broken in a tree copy from `tree_copy.py`, and only its rows run
(with Z1): the app and the probe are built from the copy when a row drives the app, the probe alone
otherwise. CAUGHT exits 1 (a named row failed), SURVIVED exits 0, and a control that could not be
performed (the copy did not build, an anchor not found once) exits 2.
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
import cloud_captions_probe as cloud  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs-bugs-c2"
HOME = WORK / "home"
FILES = WORK / "files"
OUT = WORK / "probe"
PROBE = HERE / "docs_bugs_c2_probe.swift"
BEEP = HERE / "docs_bugs_c2_beep.c"
SEC = 600_000
CALL_BOUND = 600
BUILD_BOUND = 1500
PROBE_BOUND = 200
PINS = ["-FrameJobInspectorCollapsed", "NO", "-FrameJobCaptionEngine", "apple"]

ONLY_SOUND = "Only a clip whose media has sound"
HEARD_SUMMARY = "No clip here can be heard. Select one to caption it."
NOTHING = "Nothing to transcribe"
UNHEARD = ("Nothing in this timeline can be heard, so nothing was transcribed. Name a clip in clips "
           "to transcribe it anyway.")
NO_SOUND = "Nothing in this timeline has recorded sound to transcribe."
ROW_MISSING = "This file is missing. Relink it to transcribe it."
DROPPED = ("it reaches an overlap between two clips on one track, or the area around it, where a cut "
           "would leave one clip's tail under the other")
CLAUSE = ("and when it reaches an overlap between two clips on one unlocked track, with a stored "
          "transition or without one, or the area around it, as wide again as the overlap on each "
          "side.")
HINT = ("A filler that would cut into another clip's word, a nest, or an overlap between two clips "
        "on one track or the area around it is left in.")
LEFT_IN = ("left in: too short to cut, or cutting would reach another clip's word, a nest, or an "
           "overlap between two clips on one track or the area around it.")

APP_ROWS = ["C0", "C1", "C2", "C3", "C4", "C5", "C6", "C7", "N1", "N2", "N3", "F4", "F5", "F6", "F7",
            "W1", "W2", "W3", "W4", "W5"]
PROBE_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "F1", "F2", "F3", "F8", "H1", "H2"]
ROWS = APP_ROWS + PROBE_ROWS + ["Z1"]

SHEET = "app/Sources/TranscribeSheetController.swift"
CLOUD = "app/Sources/TranscribeSheetController+Cloud.swift"
TOOL = "app/Sources/AgentServer+Captions.swift"
JOBS = "app/Sources/Transcriber+Jobs.swift"
PRESS = "app/Sources/FillerSheetController+Transcribe.swift"
FILLERS = "app/Sources/FillerSheetController.swift"
FILLER_TOOL = "app/Sources/AgentServer+Fillers.swift"
SCOPE_TEST = ("if outcome.clips.isEmpty, outcome.needsTranscript.isEmpty, outcome.locked.isEmpty,\n"
              "            input.missing.isEmpty\n        {")
SCOPE_KEPT = ("if outcome.clips.isEmpty, outcome.needsTranscript.isEmpty, outcome.locked.isEmpty\n"
              "        {")
# name: (the rows it must turn red, whether a row drives the app, the edits).
MUTANTS = {
    "selection-filtered": (["P3", "P6"], False, [(
        SHEET, "for: scope == .selection ? held : Transcriber.heard(held, in: plan), in: snapshot,",
        "for: Transcriber.heard(held, in: plan), in: snapshot,")]),
    "named-filtered": (["C4"], True, [(
        TOOL,
        "let clips = named.map { ids in ids.compactMap { snapshot.clip($0) } }\n"
        "            ?? Transcriber.heard(snapshot.clips, in: document.editedProject.plan)",
        "let clips = Transcriber.heard(\n"
        "            named.map { ids in ids.compactMap { snapshot.clip($0) } } ?? snapshot.clips,\n"
        "            in: document.editedProject.plan)")]),
    "audible-ignored": (["P1"], False, [(
        JOBS, "if SilenceDetector.isAudible(track.ramps, over: span) { heard.insert(segment.clip) }",
        "_ = span\n                heard.insert(segment.clip)")]),
    "default-on-unheard": (["P4"], False, [(
        SHEET, "let selected = Transcriber.heard(clips(in: .selection), in: plan)",
        "let selected = clips(in: .selection)")]),
    "stale-note": (["P2"], False, [
        (SHEET, "if jobs.isEmpty, !unheardScope {", "if jobs.isEmpty {"),
        (CLOUD, "if jobs.isEmpty, !unheardScope {", "if jobs.isEmpty {")]),
    "tool-sentence-in-tab": (["N1"], True, [(
        "app/Sources/TranscriptTabSource.swift", "TimelineTranscript.sameSpeechShown(shown,",
        "TimelineTranscript.sameSpeech(shown,")]),
    "press-no-rebuild": (["F1"], False, [(
        PRESS,
        ": \"No clip plays “\\(name)”, so nothing was uploaded.\"\n"
        "            rebuildRows()\n",
        ": \"No clip plays “\\(name)”, so nothing was uploaded.\"\n")]),
    "missing-after-noclip": (["F1"], False, [(
        PRESS,
        "        if urls[media] == nil { return \"This file is missing. Relink it to transcribe "
        "it.\" }\n"
        "        return \"No clip plays this file, so it cannot be transcribed\"\n",
        "        if urls[media] != nil { return \"No clip plays this file, so it cannot be "
        "transcribed\" }\n"
        "        return \"No clip plays this file, so it cannot be transcribed\"\n")]),
    "missing-empty": (["F3"], False, [(
        "app/Sources/FillerDetector.swift", "missing: missing.sorted())", "missing: [])")]),
    "nothing-in-scope-kept": (["F7", "F8"], True, [
        (FILLERS, SCOPE_TEST, SCOPE_KEPT), (FILLER_TOOL, SCOPE_TEST, SCOPE_KEPT)]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def attempt(names, body):
    """`body` when any of `names` is selected; an instrument that raises fails them, never exits."""
    if not selected & set(names):
        return
    try:
        body()
    except Exception as error:  # noqa: BLE001
        for name in names:
            check(name, False, f"the row could not run: {error!r}")


# ---- the fixtures -----------------------------------------------------------------------

def word(text, start, end):
    return {"text": text, "start": start, "end": end, "confidence": 0.9, "speaker": None}


SPEECH = [word(t, 300 + i * 450, 700 + i * 450) for i, t in enumerate(
    "Every morning the harbour fills with small boats and loud gulls. Please write the totals in "
    "the third column of the sheet.".split())]
FILLED = [word("one", 1000, 2000), word("two", 7000, 8000), word("um", 8500, 8800),
          word("three", 8900, 9200), word("uh", 9300, 9600), word("four", 9700, 9900),
          word("er", 10400, 10600), word("five", 10700, 10900), word("six", 11000, 11300),
          word("um", 11400, 11700), word("seven", 11800, 12500), word("eight", 13000, 13900),
          word("uh", 14000, 14300), word("nine", 14400, 15000)]


def sound(path, seconds=36):
    """A wave file: AssemblyAI is the stand-in, so what it holds is never recognised."""
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                    f"sine=frequency=300:duration={seconds}", "-ar", "16000", "-ac", "1", str(path)],
                   check=True, timeout=120)
    return str(path)


def movie(path, wave):
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                    "color=c=gray:s=640x360:r=30", "-i", str(wave), "-shortest", "-c:v", "libx264",
                    "-pix_fmt", "yuv420p", "-c:a", "aac", str(path)], check=True, timeout=120)
    return str(path)


def secret_folder():
    folder = WORK / "secrets"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    descriptor = os.open(folder / "assemblyai-key", os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(descriptor, "w") as handle:
        handle.write("proof-key\n")
    return folder


class Session:
    """One project in the instance: `lab.py`'s helpers, each with the project named."""

    count = 0

    def __init__(self, client, name):
        Session.count += 1
        self.client = client
        self.path = str(FILES / f"{name}-{Session.count}.framejob")
        self.client.call_with("new_project", {"path": self.path})

    def op(self, tool, **arguments):
        return self.client.call_with(tool, dict(arguments, project=self.path))

    def project(self):
        return self.op("get_project")["project"]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def new_track(self):
        self.op("add_track")
        return self.tracks()[-1]

    def media_of(self, path):
        return self.op("import_media", path=str(path))["media"]

    def add(self, media, at=0, track=None, duration=None):
        track = track if track is not None else self.tracks()[0]
        clip = self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]
        if duration is not None:
            self.op("trim_end", clip=clip, to=at + duration)
        return clip

    def pair(self, media):
        """A camera and a microphone with the same words, the microphone 0.2 s later."""
        camera, mic = self.media_of(media["camera"]), self.media_of(media["mic"])
        front, second = self.tracks()[0], self.new_track()
        self.front, self.second = front, second
        return self.add(camera, track=front), self.add(mic, at=int(0.2 * SEC), track=second)

    def close(self):
        try:
            self.op("close_project", discard=True)
        except mcp.ToolError:
            pass

    def wait_sheet(self, seconds=10):
        began = time.monotonic()
        while time.monotonic() - began < seconds:
            if (self.op("perform_menu_item").get("window") or {}).get("sheet") is not None:
                break
            time.sleep(0.1)
        time.sleep(0.3)

    def texts(self, name, **arguments):
        shot = self.op("snapshot_ui", path=str(WORK / f"{name}.png"), **arguments)
        with open(shot["layout_path"]) as handle:
            views = json.load(handle)["views"]
        return [v["text"] for v in views if v.get("text") and not v.get("hidden")]


def refusal(call):
    """A tool's refusal sentence, or None when it answered."""
    try:
        call()
    except mcp.ToolError as error:
        return str(error)
    return None


def spoken(answer):
    lines = [cue["text"] for cue in answer.get("cues", [])]
    return len(lines) == len(set(lines)) and bool(lines)


def brief(answer):
    return {key: answer.get(key) for key in ("clips_read", "captions", "trimmed", "placed")}


# ---- the app's rows ---------------------------------------------------------------------

def caption_rows(client, media):
    def c0():
        s = Session(client, "c0")
        c, k = s.pair(media)
        answer = s.op("transcribe", engine="assemblyai", place=False)
        check("C0", answer.get("clips_read") == [c, k], str(brief(answer)))
        s.close()

    def muted_row(row, silence):
        def body():
            s = Session(client, row.lower())
            c, k = s.pair(media)
            silence(s, c)
            answer = s.op("transcribe", engine="assemblyai")
            check(row, answer.get("clips_read") == [k] and "trimmed" not in answer and spoken(answer),
                  f"{brief(answer)}; each line once {spoken(answer)}")
            s.close()
        return body

    def c4():
        s = Session(client, "c4")
        c, _ = s.pair(media)
        s.op("set_audio", clips=[c], patch={"muted": True})
        answer = s.op("transcribe", engine="assemblyai", place=False, clips=[c])
        check("C4", answer.get("clips_read") == [c], str(brief(answer)))
        s.close()

    def c5():
        s = Session(client, "c5")
        c, k = s.pair(media)
        s.op("set_audio", clips=[c, k], patch={"muted": True})
        before = len(s.tracks())
        said = refusal(lambda: s.op("transcribe", engine="assemblyai"))
        after = len(s.tracks())
        check("C5", said is not None and UNHEARD in said and after == before,
              f"{said!r}; tracks {before} → {after}")
        s.close()

    def c6():
        s = Session(client, "c6")
        c, _ = s.pair(media)
        s.op("set_audio", clips=[c], patch={"muted": True})
        s.op("set_selection", clips=[])
        s.op("perform_menu_item", path=["File", "Generate Captions…"])
        s.wait_sheet()
        texts = s.texts("c6", window="sheet")
        s.op("cancel_sheet")
        time.sleep(0.3)
        summary = [t for t in texts if " of audio" in t]
        check("C6", any(t.startswith("1 clip ") for t in summary), f"summary {summary}")
        s.close()

    def c7():
        s = Session(client, "c7")
        clip = s.add(s.media_of(media["mic"]))
        s.op("set_enabled", clip=clip, audio=False)
        said = refusal(lambda: s.op("transcribe", engine="assemblyai"))
        check("C7", said is not None and NO_SOUND in said, repr(said))
        s.close()

    attempt(["C0"], c0)
    attempt(["C1"], muted_row(
        "C1", lambda s, c: s.op("set_audio", clips=[c], patch={"muted": True})))
    attempt(["C2"], muted_row("C2", lambda s, c: s.op("set_track", track=s.front, muted=True)))
    attempt(["C3"], muted_row("C3", lambda s, c: s.op("set_track", track=s.second, solo=True)))
    attempt(["C4"], c4)
    attempt(["C5"], c5)
    attempt(["C6"], c6)
    attempt(["C7"], c7)


def name_rows(client, media):
    def body():
        s = Session(client, "names")
        c, k = s.pair(media)
        s.op("save_project")
        s.op("transcribe", engine="assemblyai", place=False)
        tool = s.op("get_timeline_transcript")
        s.op("select_inspector_tab", tab="transcript")
        s.op("transcript_view", wait=60)
        texts = s.texts("n1", window="editor")
        note = (f"“Interview.mov” (clip {c}) and “Mic.wav” (clip {k}) carry the same speech. Mute "
                "one, or switch its audio off, to read it once.")
        check("N1", note in texts, f"lines with 'same speech' "
              f"{[t for t in texts if 'same speech' in t]}")

        s.op("set_enabled", clip=c, audio=False)
        s.op("transcript_view", wait=60)
        texts = s.texts("n2", window="editor")
        row = f"“Interview.mov” (clip {c}) — its audio is switched off"
        check("N2", row in texts, f"lines with 'switched off' "
              f"{[t for t in texts if 'switched off' in t]}")

        off = s.op("get_timeline_transcript")
        same = (f"Clips {c} and {k} carry the same speech. Mute one, or switch its audio off, to "
                "read it once.")
        tags = [row.get("tag") for row in off.get("no_words", [])]
        check("N3", same in tool.get("notes", []) and tags == [f"clip {c}"],
              f"notes {tool.get('notes')}; tags {tags}")
        s.close()

    attempt(["N1", "N2", "N3"], body)


def filler_rows(client, media):
    def two_files():
        one, two = FILES / "Lost One.wav", FILES / "Kept Two.wav"
        spare = FILES / "Spare.wav"
        for path in (one, two, spare):
            shutil.copyfile(media["mic"], path)
        s = Session(client, "f46")
        m1, m2 = s.media_of(one), s.media_of(two)
        m3 = s.media_of(spare)
        s.add(m1, at=0)
        s.add(m2, at=40 * SEC)
        s.op("save_project")
        os.remove(one)

        said = refusal(lambda: s.op("transcribe_for_fillers", media=m1))
        want = f"Media {m1}'s file is missing, so it cannot be transcribed. Relink it first."
        check("F4", said is not None and want in said, repr(said))

        said = refusal(lambda: s.op("transcribe_for_fillers", media=m3))
        want = f"No clip in this timeline plays media {m3} from its file, so it cannot be transcribed."
        check("F5", said is not None and want in said, repr(said))

        note = s.op("detect_fillers").get("note", "")
        want = (f"Media {m1} is missing its file, so its fillers cannot be found. relink_media finds "
                "it again.")
        check("F6", want in note, repr(note))
        s.close()

    def only_file():
        path = FILES / "Only.wav"
        shutil.copyfile(media["mic"], path)
        s = Session(client, "f7")
        m = s.media_of(path)
        s.add(m)
        s.op("save_project")
        os.remove(path)
        note = s.op("detect_fillers").get("note", "")
        want = f"Media {m} is missing its file, so its fillers cannot be found."
        check("F7", want in note and "Nothing in scope" not in note, repr(note))
        s.close()

    attempt(["F4", "F5", "F6"], two_files)
    attempt(["F7"], only_file)


def dropped_near(answer, a, b):
    """Whether "uh" in clip `a` and "um" in clip `b` were dropped with the new sentence."""
    rows = answer.get("dropped", [])
    return any(r["clip"] == a and r["words"] == ["uh"] and r["reason"] == DROPPED for r in rows) \
        and any(r["clip"] == b and r["words"] == ["um"] and r["reason"] == DROPPED for r in rows)


def kept(answer, clip, start):
    return any(f["clip"] == clip and f["words"] == ["um"]
               and abs(f["range"][0] / SEC - start) < 0.05 for f in answer.get("fillers", []))


def wall_rows(client, media, server, packages):
    def overlap():
        server.scenario(words=FILLED, disfluent_words=FILLED)
        s = Session(client, "walls")
        m = s.media_of(media["long"])
        front = s.tracks()[0]
        a = s.add(m, at=0, track=front, duration=11 * SEC)
        b = s.add(m, at=30 * SEC, track=front)
        s.op("trim_start", clip=b, to=40 * SEC)     # in 10 s, now at 40
        s.op("trim_end", clip=b, to=50 * SEC)       # 40 to 50
        s.op("save_project")
        s.op("transcribe", engine="assemblyai", place=False)

        apart = s.op("detect_fillers")
        s.op("move_clip", clips=[b], delta=-30 * SEC)
        bare = s.op("detect_fillers")
        check("W1", dropped_near(bare, a, b), str(bare.get("dropped")))
        check("W3", apart.get("dropped") == [] and kept(bare, a, 8.5),
              f"apart dropped {apart.get('dropped')}; overlap kept {bare.get('fillers')}")
        s.op("save_project")
        packages["overlap"] = str(FILES / "overlap.framejob")
        shutil.copytree(s.path, packages["overlap"])

        # A hard cut at 10.5 s, so add_transition's centred 1 s makes the same 10 to 11 s overlap.
        s.op("trim_end", clip=a, to=int(10.5 * SEC))
        s.op("trim_start", clip=b, to=int(10.5 * SEC))
        s.op("add_transition", clip=b, duration=SEC)
        stored = s.op("detect_fillers")
        check("W2", dropped_near(stored, a, b), str(stored.get("dropped")))
        s.close()

    def second_track():
        server.scenario(words=FILLED, disfluent_words=FILLED)
        s = Session(client, "w5")
        m, other = s.media_of(media["long"]), s.media_of(media["mic"])
        front, second = s.tracks()[0], s.new_track()
        a = s.add(m, at=0, track=front, duration=11 * SEC)
        s.add(other, at=8 * SEC, track=second, duration=10 * SEC)
        s.op("save_project")
        s.op("transcribe", engine="assemblyai", place=False, clips=[a])
        answer = s.op("detect_fillers")
        check("W5", answer.get("dropped") == [] and kept(answer, a, 8.5),
              f"dropped {answer.get('dropped')}; kept {answer.get('fillers')}")
        s.close()

    def catalog():
        text = client.schemas().get("detect_fillers", {}).get("description", "")
        check("W4", CLAUSE in text and "crosses a transition" not in text,
              f"clause {CLAUSE in text}; old words {'crosses a transition' in text}")

    attempt(["W1", "W2", "W3", "H2"], overlap)
    attempt(["W4"], catalog)
    attempt(["W5"], second_track)


def make_packages(client, media, packages):
    """The saved projects the probe opens: their paths, the clips and the files it deletes."""
    def saved(name, build):
        s = Session(client, name)
        built = build(s)
        s.op("save_project")
        packages[name] = s.path
        s.close()
        return built

    def muted_pair(both):
        def build(s):
            c, k = s.pair(media)
            s.op("set_audio", clips=[c, k] if both else [c], patch={"muted": True})
            return c, k
        return build

    def audio_off(s):
        clip = s.add(s.media_of(media["mic"]))
        s.op("set_enabled", clip=clip, audio=False)

    def two_files(s):
        one, two = FILES / "Drive One.wav", FILES / "Drive Two.wav"
        for path in (one, two):
            shutil.copyfile(media["mic"], path)
        s.add(s.media_of(one), at=0)
        s.add(s.media_of(two), at=40 * SEC)
        packages["lost"] = str(one)

    def only_file(s):
        path = FILES / "Drive Only.wav"
        shutil.copyfile(media["mic"], path)
        s.add(s.media_of(path))
        packages["only"] = str(path)

    if selected & {"P1", "P3", "P4", "P5"}:
        packages["ids"] = saved("muted", muted_pair(False))
    if selected & {"P2", "P6"}:
        packages["all-ids"] = saved("all-muted", muted_pair(True))
    if "P7" in selected:
        saved("off", audio_off)
    if selected & {"F1", "F2", "F3", "H1"}:
        saved("fillers", two_files)
    if "F8" in selected:
        saved("alone", only_file)


# ---- the probe's rows -------------------------------------------------------------------

def build_probe(sources):
    """(binary, None) or (None, why): a probe that will not build fails its rows."""
    OUT.mkdir(parents=True, exist_ok=True)
    entry = OUT / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = OUT / "docs-bugs-c2-probe"
    try:
        subprocess.run(["cc", "-dynamiclib", "-framework", "AppKit", "-o",
                        str(OUT / "beep_count.dylib"), str(BEEP)], check=True, timeout=60)
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    except (OSError, subprocess.SubprocessError) as error:
        return None, f"the beep counter: {error!r}"
    return binary, None


def probe_run(binary, *arguments):
    env = bounded.child_env({"DYLD_INSERT_LIBRARIES": str(OUT / "beep_count.dylib")})
    done = subprocess.run([str(binary), *arguments], capture_output=True, text=True, env=env,
                          timeout=PROBE_BOUND, cwd=OUT, stdin=subprocess.DEVNULL)
    lines = [line for line in done.stdout.splitlines() if line.startswith("{")]
    if not lines:
        raise RuntimeError(f"exit {done.returncode}, no answer: {done.stderr[-400:]}")
    answer = json.loads(lines[-1])
    if "error" in answer or done.returncode != 0:
        raise RuntimeError(f"exit {done.returncode}: {str(answer)[:400]}")
    if answer.get("control") != 1:
        raise RuntimeError(f"the beep counter's control moved {answer.get('control')}, not 1")
    return answer


def caption_probe_rows(binary, server, packages):
    def sheet(package, ids=()):
        return probe_run(binary, "captions", packages[package], server.base,
                         ",".join(str(i) for i in ids) or "-")

    def card(answer):
        return {key: answer[key] for key in ("scope", "jobs", "summary")}

    def one_muted():
        c, k = packages["ids"]
        none = sheet("muted")["apple"]
        check("P1", none["all"] == [k], f"jobs(in: .all) {none['all']}, heard clip {k}")
        camera = sheet("muted", [c])["apple"]
        check("P3", camera["selection"] == [c], f"jobs(in: .selection) {camera['selection']}")
        check("P4", camera["scope"] == "all" and camera["jobs"] == [k], str(card(camera)))
        both = sheet("muted", [c, k])["apple"]
        check("P5", both["scope"] == "selection" and sorted(both["jobs"]) == [c, k], str(card(both)))

    def every_clip_muted():
        c, _ = packages["all-ids"]
        answer = sheet("all-muted")
        rows = [answer["apple"], answer["assemblyai"]]
        check("P2", all(r["summary"] == HEARD_SUMMARY and ONLY_SOUND not in r["note"] for r in rows),
              str([(r["summary"], r["note"]) for r in rows]))
        chosen = sheet("all-muted", [c])["apple"]
        check("P6", chosen["scope"] == "selection" and chosen["jobs"] == [c], str(card(chosen)))

    def audio_off():
        answer = sheet("off")
        rows = [answer["apple"], answer["assemblyai"]]
        check("P7", all(r["summary"] == NOTHING and ONLY_SOUND in r["note"] for r in rows),
              str([(r["summary"], r["note"]) for r in rows]))

    attempt(["P1", "P3", "P4", "P5"], one_muted)
    attempt(["P2", "P6"], every_clip_muted)
    attempt(["P7"], audio_off)


def row_of(stage, name):
    return next((r for r in stage["rows"] if r["name"] == name), None)


def filler_probe_rows(binary, server, packages):
    def presses():
        server.scenario(words=FILLED, disfluent_words=FILLED)
        name = "Drive One.wav"
        answer = probe_run(binary, "fillers", packages["fillers"], packages["lost"], server.base)
        uploads = [r for r in server.log()["requests"] if r["path"] == "/v2/upload"]
        before, after = answer["deleted"], answer["pressed"]
        lost = row_of(after, name) or {}
        said = f"“{name}” is missing, so nothing was uploaded. Relink it to transcribe it."
        check("F1", after["beeps"] == before["beeps"] and lost.get("enabled") is False
              and lost.get("estimate") == ROW_MISSING and after["last_error"] == said
              and said in after["note"] and len(uploads) == 1,
              f"beeps {before['beeps']} → {after['beeps']}, row {lost}, last_error "
              f"{after['last_error']!r}, uploads in the whole run {len(uploads)}")
        note = f"“{name}” is missing, so its fillers cannot be found. Relink it, then open this sheet"
        check("F2", note in answer["ended"]["note"], repr(answer["ended"]["note"]))
        reopened = answer["reopened"]
        check("F3", note in reopened["note"] and row_of(reopened, name) is None,
              f"note {reopened['note']!r}, rows {[r['name'] for r in reopened['rows']]}")

    def alone():
        sheet = probe_run(binary, "lost", packages["alone"], packages["only"], server.base)["sheet"]
        want = "“Drive Only.wav” is missing, so its fillers cannot be found."
        check("F8", want in sheet["note"] and "Nothing in scope" not in sheet["note"],
              repr(sheet["note"]))

    def hint():
        answer = probe_run(binary, "note", packages["fillers"], server.base)
        check("H1", any(HINT in text for text in answer["texts"])
              and not any("a nest or a transition" in text for text in answer["texts"]),
              str([text[-150:] for text in answer["texts"] if "left in" in text]))

    def left_in():
        sheet = probe_run(binary, "note", packages["overlap"], server.base)["sheet"]
        check("H2", LEFT_IN in sheet["note"], repr(sheet["note"]))

    # The hint reads the package before `presses` deletes its file.
    attempt(["H1"], hint)
    attempt(["F1", "F2", "F3"], presses)
    attempt(["F8"], alone)
    attempt(["H2"], left_in)


# ---- the run ----------------------------------------------------------------------------

def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def fixtures():
    wave = sound(FILES / "Mic.wav")
    return {"mic": wave, "camera": movie(FILES / "Interview.mov", wave),
            "long": sound(FILES / "Long.wav")}


def run_app(binary, server, media, packages):
    arguments = ["-RCSecretFolder", str(secret_folder()), "-RCAssemblyAIEndpoint", server.base,
                 *PINS]
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in selected - {"Z1"}:
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        client = launched.client
        server.scenario(words=SPEECH, disfluent_words=SPEECH)
        caption_rows(client, media)
        name_rows(client, media)
        filler_rows(client, media)
        wall_rows(client, media, server, packages)
        attempt(sorted(set(PROBE_ROWS) - {"H2"}), lambda: make_packages(client, media, packages))
    finally:
        launched.stop()
    parity(log)


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][2]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    parser.add_argument("--base-sources")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    FILES.mkdir(parents=True)
    HOME.mkdir(parents=True)
    cloud.WORK = str(WORK / "fakes")
    os.makedirs(cloud.WORK, exist_ok=True)

    binary = Path(args.app) if args.app else None
    sources = Path(args.base_sources) if args.base_sources else ROOT / "app/Sources"
    if args.mutant:
        named, drives_app, _ = MUTANTS[args.mutant]
        print(f"docs bugs c2 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        made, why = mutate(args.mutant)
        if why is None:
            sources = made / "app/Sources"
            if drives_app:
                app, why = tree_copy.build_app(made, BUILD_BOUND)
                binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"docs bugs c2 — what is heard, what is named, what is missing "
              f"({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)

    probe, why = (None, None)
    if selected & set(PROBE_ROWS):
        probe, why = build_probe(sources)
        if why:
            if args.mutant:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            for row in sorted(selected & set(PROBE_ROWS)):
                check(row, False, f"the probe did not build: {why}")
            selected -= set(PROBE_ROWS)

    media = fixtures()
    packages = {}
    with cloud.Fake("c2") as server:
        lock, _, holder = cloud.hold_cloud_lock(1800)
        if lock is None:
            print(f"the cloud instruments' lock is held: {holder}")
            return 2
        try:
            run_app(binary, server, media, packages)
            if probe is not None:
                caption_probe_rows(probe, server, packages)
                filler_probe_rows(probe, server, packages)
        finally:
            lock.close()

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        if not named & set(results):
            print(f"mutant {args.mutant}: the control could not be performed — its row was "
                  f"never scored")
            return 2
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 1 if caught else 0
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
