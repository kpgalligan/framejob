#!/usr/bin/env python3
"""Road map "creator-jobs" TX3a (spec §11 TX-30…TX-33): delete words — the
Transcript tab's selection as the in/out range, ⌫ as one "Delete Words",
TX-32's widening and refusals, and `get_timeline_transcript`'s `cut_start` and
`cut_end`.

    python3 tools/proof/transcript_cut_proof.py [--only IDS]
    python3 tools/proof/transcript_cut_proof.py --mutant NAME
    python3 tools/proof/transcript_cut_proof.py --mutants

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The one app
launch is TX1's (`assistant_session_proof.App` with a 0700 `-RCSecretFolder`
holding the dummy `proof-key`, `-RCAssemblyAIEndpoint` at the fake). Fixture
media: TX1's `say` phrases (`timeline_transcript_proof.fixtures`), TX-S3's
joined fixture (`transcript_spike/cut_spike.joined_fixture`: phrases joined by
60–1,000 ms of zero samples, every true onset known) and a 20 s silent WAV,
all under `tools/proof/work/`. Every word is this Mac's (the package's own
`cache/device-transcripts/`); nothing is recognised twice to make an oracle.

Probe rows (`transcript_cut_probe.swift`, built through `swift_build.build()`
over `app/Sources` or a mutant's copy): U0 builds; U1…U6 as its header says.

App rows (the app `proof_app` chooses; `RC_PROOF_APP=release` for the record):
  Z0  no `Frame Job: ` line; every `get_timeline_transcript` word carries
      `cut_start` ≤ `cut_end`, and the tab's tokens equal the tool's words,
      cut keys included.
  C1  the joined fixture: for every boundary, the first word of the phrase
      after it has its `cut_start` at or before the phrase's true onset — TX-S3's
      verdict (E0) clips no onset. The edges inside the previous phrase are
      reported, not scored (TX-30: E0 does not claim the silence).
  C2  three words cut one at a time (the tab's Delete, last first) and as one
      selection give equal `get_project` placements per track (start, in,
      duration, media; ids aside).
  C3  the 1 s cap: A, 20 s of silent B-roll, then C: A's last word's
      `cut_end` is its end plus 1 s, snapped, and the tab's Delete of it leaves
      the B-roll starting `cut_end − A's end` later into its source.
  C4  crosstalk: A on track 1, B on track 2 overlapping A's tail: selecting a
      track-1 word X that a track-2 word Y runs into widens the selection over
      Y, and the Delete leaves neither id.
  C4b on the same layout fresh, `ripple_delete_ranges` of X's own
      `cut_start`/`cut_end` from `get_timeline_transcript` gives the placements
      of the tab's Delete of X (Y taken whole).
  C5  the same with track 2 locked: `cut.refusal` is TX-32's locked sentence
      naming the track, and Edit ▸ Delete changes nothing.
  C6  a project of N clips (A and one-frame text clips): N = RC_MAX_CLIPS − 1
      and a mid-clip word: `clips_peak` RC_MAX_CLIPS + 1, refused with N = that
      peak and no step; N = RC_MAX_CLIPS − 2: `clips_peak` RC_MAX_CLIPS, the
      Delete applies and `get_project`'s clip count is `clips_after`.
  C7  the tab's Delete (`transcript_view` selects, `perform_menu_item` Edit ▸
      Delete) is one step `undo` names "Delete Words" and that takes the
      project back; its placements equal `ripple_delete_ranges` of the read's
      range (first word's `cut_start`, last word's `cut_end`).
  C8  two WAV exports decoded to PCM are equal sample for sample — after C7's
      tab Delete, and after its `ripple_delete_ranges` on the original.
  C9  words selected after a clip B: `in_out_range` is `transcript_view`'s
      `cut`; B ripple-deleted, the range follows the re-mapped selection's new
      `cut`; after `set_range` elsewhere a further edit leaves it alone.

Mutants (`--mutant NAME`, or all with `--mutants`): each anchor occurs once;
a mutant is caught when every row it names fails. Mutants 1–9 are caught by
the probe, which runs the very functions C1–C6 drive; 10 needs an app copy.
  guard-0             E2's onset is the run's end, no guard (U1)
  no-cap              the 1 s cap removed (U2)
  snap-apart          the start snapped down, the end up (U6)
  no-widening         the widening returns the selection as given (U3)
  no-locked-refusal   refusal 2 off (U4)
  fallback-no-lead    E2's and E1's fallback without the lead (U1)
  no-ceiling          the ceiling check skipped (U5)
  after-no-spanning   the count after misses the clips spanning the range (U5)
  ceiling-on-after    the ceiling tested on `clipsAfter`, not the peak (U5)
  no-replan           no re-plan after a rebuild (C9; an app built from a tree
                      copy)

Exit: 0 iff every row passed or was a named host SKIP (a mutant run: 0 when
caught, 1 when it survived, 2 when the control could not be performed).
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import traceback
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "transcript_spike"))
import swift_build  # noqa: E402
import bounded  # noqa: E402 — on swift_build's path
import timeline_transcript_proof as ttp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/transcript_cut"
PROBE = ROOT / "tools/proof/transcript_cut_probe.swift"
PROBE_ROWS = ["U0", "U1", "U2", "U3", "U4", "U5", "U6"]
APP_ROWS = ["Z0", "C1", "C2", "C3", "C4", "C4b", "C5", "C6", "C7", "C8", "C9"]
ROWS = PROBE_ROWS + APP_ROWS
SEC = 600_000
LEAD = 162_000  # CaptionPages.lead(for: .apple): only to find a boundary's word, as TX-S3 does
MAX_CLIPS = 4096  # RC_MAX_CLIPS, core/include/framejob_core.h
TOOL = "transcript_view"
LOCKED = "Track {} is locked and has words in this cut: unlock it to cut here."
CEILING = ("This cut would make {} clips; a project holds at most 4096. Lock a track that needs "
           "no cut, such as a music bed, or cut less.")

TC = "TranscriptCut.swift"
TP = "TranscriptCut+Plan.swift"
PANE = "TranscriptPane.swift"
MUTANTS = {
    "guard-0": ("probe", ["U1"], [(TC, "onset = runEnd - guardTicks", "onset = runEnd")]),
    "no-cap": ("probe", ["U2"], [
        (TC, "end = min(edges(selection.upperBound + 1).onset, latestEnd + TranscriptCut.cap)",
         "end = edges(selection.upperBound + 1).onset")]),
    "snap-apart": ("probe", ["U6"], [
        (TP, "var start = max(0, ReelTime.snapToFrame(range.start, fps: fps))",
         "var start = max(0, TimelineTranscript.frameFloor(range.start, fps: fps))"),
        (TP, "var end = max(0, ReelTime.snapToFrame(range.end, fps: fps))",
         "var end = max(0, TimelineTranscript.frameFloor(range.end, fps: fps) + fps.frameDuration)")]),
    "no-widening": ("probe", ["U3"], [
        (TP, "        var current = selection\n        while true {\n",
         "        var current = selection\n        while current.isEmpty {\n"),
        (TP, "            current = low...high\n        }\n    }\n",
         "            current = low...high\n        }\n        return current\n    }\n")]),
    "no-locked-refusal": ("probe", ["U4"], [
        (TP, "        } else if range.end > range.start,\n            let index",
         "        } else if false, range.end > range.start,\n            let index")]),
    "fallback-no-lead": ("probe", ["U1"], [
        (TC, "var onset = word.source + lead", "var onset = word.source")]),
    "no-ceiling": ("probe", ["U5"], [
        (TP, "        } else if peak > ceiling {\n", "        } else if false, peak > ceiling {\n")]),
    "after-no-spanning": ("probe", ["U5"], [
        (TP, "            if clip.start < range.start, clip.end > range.end {\n                count += 1\n"
             "            } else if",
         "            if clip.start < range.start, clip.end > range.end {\n"
         "            } else if")]),
    "ceiling-on-after": ("probe", ["U5"], [
        (TP, "        } else if peak > ceiling {\n", "        } else if after > ceiling {\n")]),
    "no-replan": ("app", ["C9"], [
        (PANE, "        if rangeSet != nil, host?.transcriptRange == rangeSet {\n",
         "        if false, rangeSet != nil, host?.transcriptRange == rangeSet {\n")]),
}


# --------------------------------------------------------------------------
# Probe and mutation

apply_edits = ttp.apply_edits
Rows = ttp.Rows


def probe_rows(results, wanted, mutant=None):
    here = WORK / (f"mutant-{mutant}" if mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = ROOT / "app/Sources"
    if mutant:
        shutil.copytree(ROOT / "app/Sources", here / "Sources")
        why = apply_edits(MUTANTS[mutant][2], here / "Sources")
        if why:
            return why
        sources = here / "Sources"
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "transcript-cut-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        results.score("U0", False, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8])))
        return None
    results.score("U0", True, f"built from {sources}")
    ran = bounded.run([str(binary)], 300, cwd=str(here))
    (here / "stderr.txt").write_text(ran["stderr"])
    try:
        answers = json.loads(ran["stdout"].strip().splitlines()[-1])["rows"]
    except (ValueError, KeyError, IndexError):
        answers = []
    for row in wanted:
        if row == "U0":
            continue
        answer = next((a for a in answers if a.get("id") == row), None)
        if answer is None:
            results.score(row, False, f"no row (exit {ran['rc']}): {ran['stderr'][-300:]}")
        else:
            results.score(row, answer.get("pass") is True, answer.get("detail", ""))
    return None


# --------------------------------------------------------------------------
# Fixtures


def silent_wav(name, seconds):
    path = WORK / f"{name}.wav"
    if not path.exists():
        WORK.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(16000)
            out.writeframes(b"\0\0" * 16000 * seconds)
    return path


def ceiling_package(name, speech, total):
    """A package of `total` clips: `speech` (media 1) at 0 on track 3, then
    `total − 1` one-frame text clips on track 4 after it (one id space)."""
    seconds = ttp.seconds_of(speech)
    length = round(seconds * SEC)
    frame = SEC // 30
    clips = [{"id": 10, "track": 3, "start": 0, "duration": length,
              "source": {"kind": "media", "media": 1, "in": 0, "reversed": False},
              "enabled": {"video": True, "audio": True}}]
    at = length + SEC
    for index in range(total - 1):
        clips.append({"id": 100 + index, "track": 4, "start": at + index * frame,
                      "duration": frame, "source": {"kind": "text"}, "text": {"content": "x"}})
    body = {"version": 38,
            "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "timecode_frames": True},
            "media": [{"id": 1, "path": str(speech), "kind": "audio", "duration": length,
                       "has_audio": True}],
            "tracks": [{"id": 3, "name": "Speech", "muted": False, "locked": False},
                       {"id": 4, "name": "Titles", "muted": False, "locked": False}],
            "clips": clips, "markers": [], "nests": [], "next_id": 100 + total + 10}
    path = WORK / f"{name}-{os.getpid()}.framejob"
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)
    (path / "project.json").write_text(json.dumps(body))
    return path


def placements(project):
    """Per track, the clips' (start, in, duration, media), ids aside."""
    out = {}
    for clip in project["clips"]:
        source = clip.get("source", {})
        out.setdefault(clip["track"], []).append(
            (clip["start"], source.get("in"), clip["duration"], source.get("media"),
             source.get("kind")))
    return {track: sorted(rows) for track, rows in out.items()}


def snap(ticks, fps=(30, 1)):
    num, den = fps
    frame = SEC * den / num
    return round(round(ticks / frame) * frame)


def pcm(path):
    return subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vn", "-f", "s32le", "-acodec", "pcm_s32le",
         "-"], check=True, timeout=300, capture_output=True).stdout


# --------------------------------------------------------------------------
# The app rows


def app_rows(results, wanted, app_path, files):
    import assistant_session_proof as sp
    import cloud_captions_probe
    import cloud_captions_proof as cloud
    import cut_spike

    os.makedirs(cloud.WORK, exist_ok=True)
    os.makedirs(sp.WORK, exist_ok=True)
    lock, _, holder = cloud_captions_probe.hold_cloud_lock(1800)
    if lock is None:
        for row in wanted:
            results.score(row, False, f"not run: the cloud instruments' lock is held by {holder}")
        return
    state = {}

    def run(row, body):
        if row not in wanted:
            return
        try:
            ok, detail = body()
        except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
            ok, detail = False, f"{type(problem).__name__}: {problem}; " + \
                traceback.format_exc(limit=2).splitlines()[-1]
        results.score(row, ok, detail)

    def close(session):
        with contextlib.suppress(Exception):
            session.op("close_project", discard=True)

    stand_in = app = None
    with contextlib.closing(lock), cloud_captions_probe.Fake("transcript-cut") as aai:
        try:
            stand_in = sp.Fake(str(WORK / "anthropic-fake"))
            app = sp.App("transcript-cut", app_path,
                         ["-RCSecretFolder", ttp.secret_folder(), "-RCAssemblyAIEndpoint", aai.base],
                         stand_in.base)
            app.connect()

            class Opened(cloud.Session):
                """A written package opened rather than made."""

                def __init__(self, instance, path):  # noqa: super().__init__ makes a new one
                    self.instance = instance
                    self.mcp = instance.mcp
                    self.path = str(path)
                    self.mcp.call("open_project", path=self.path)

            def session_of(name):
                return cloud.Session(app, f"cut-{name}")

            def view(session, **arguments):
                return session.op(TOOL, **arguments)

            def read(session):
                return session.op("get_timeline_transcript")

            def tracks(session):
                return [t["id"] for t in session.project()["tracks"]]

            def new_track(session):
                session.op("add_track")
                return tracks(session)[-1]

            def show(session):
                session.op("select_inspector_tab", tab="transcript")
                return view(session, wait=60)

            def delete(session, first, last):
                """The tab's Delete of tokens first…last, as a person does it."""
                view(session, focus=True, select=[first, last])
                session.op("perform_menu_item", path=["Edit", "Delete"])
                return view(session, wait=30)

            def index_of(shown, word_id):
                return next((t["index"] for t in shown.get("tokens", []) if t["id"] == word_id),
                            None)

            def z0():
                complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
                s = session_of("z0")
                try:
                    a = s.media_of(str(files["A"]))
                    s.add(a, at=0)
                    shown = show(s)
                    words = read(s).get("words", [])
                    keyed = all("cut_start" in w and w["cut_start"] <= w["cut_end"] for w in words)
                    tokens = [{k: v for k, v in t.items() if k not in ("index", "paragraph", "struck")}
                              for t in shown.get("tokens", [])]
                    return (not complaints and keyed and len(words) > 10 and tokens == words,
                            f"parity lines {complaints[:3]}; {len(words)} words, cut keys {keyed}; "
                            f"tokens equal {tokens == words}")
                finally:
                    close(s)
            run("Z0", z0)

            def c1():
                path, phrases, gaps = cut_spike.joined_fixture()
                s = session_of("c1")
                try:
                    s.add(s.media_of(str(path)), at=0)
                    show(s)
                    words = read(s).get("words", [])

                    def spelled(text):
                        return "".join(c for c in text.lower() if c.isalnum())
                    clipped, inside, found = [], [], 0
                    for k in range(1, len(phrases)):
                        onset = phrases[k]["onset"]
                        want = spelled(phrases[k]["first_word"])
                        word = next((w for w in words if spelled(w["text"]) == want
                                     and abs(w["start"] + LEAD - onset) < SEC), None)
                        if word is None:
                            continue
                        found += 1
                        if word["cut_start"] > onset:
                            clipped.append((k, gaps[k - 1], word["cut_start"] - onset))
                        if word["cut_start"] < phrases[k - 1]["end"]:
                            inside.append(round((word["cut_start"] - phrases[k - 1]["end"]) / 600))
                    return (found == len(phrases) - 1 and not clipped,
                            f"{found}/{len(phrases) - 1} boundaries found; clipped onsets "
                            f"{clipped}; edges inside the previous phrase (ms, reported) {inside}")
                finally:
                    close(s)
            run("C1", c1)

            def c2():
                together, apart = session_of("c2-together"), session_of("c2-apart")
                try:
                    for s in (together, apart):
                        s.add(s.media_of(str(files["A"])), at=0)
                    shown = show(together)
                    count = len(shown.get("tokens", []))
                    first = count // 2 - 1
                    ids = [shown["tokens"][i]["id"] for i in range(first, first + 3)]
                    delete(together, first, first + 2)
                    show(apart)
                    for word_id in reversed(ids):
                        now = view(apart, wait=10)
                        index = index_of(now, word_id)
                        if index is None:
                            return False, f"word {word_id} not shown before its own Delete"
                        delete(apart, index, index)
                    a, b = placements(together.project()), placements(apart.project())
                    return (a == b and a != {}, f"words {first}…{first + 2} of {count}; together "
                            f"{a}; one at a time {b}")
                finally:
                    close(together)
                    close(apart)
            run("C2", c2)

            def c3():
                s = session_of("c3")
                try:
                    a = s.media_of(str(files["A"]))
                    broll = s.media_of(str(silent_wav("broll-20", 20)))
                    c = s.media_of(str(files["C"]))
                    length = round(ttp.seconds_of(files["A"]) * SEC)
                    t1 = tracks(s)[0]
                    s.add(a, at=0, track=t1)
                    s.add(broll, at=length, track=t1)
                    s.add(c, at=length + 20 * SEC, track=t1)
                    shown = show(s)
                    words = read(s)["words"]
                    last = max((w for w in words if w["media"] == a), key=lambda w: w["start"])
                    index = index_of(shown, last["id"])
                    want_end = snap(last["end"] + SEC)
                    begins = next(k["start"] for k in s.project()["clips"]
                                  if k["source"].get("media") == broll)
                    delete(s, index, index)
                    after = [k for k in s.project()["clips"] if k["source"].get("media") == broll]
                    taken = after[0]["source"]["in"] if after else None
                    return (last["cut_end"] == want_end and taken == want_end - begins
                            and 0 < taken <= SEC,
                            f"A's last word {last['text']!r} ends {last['end']}, cut "
                            f"[{last['cut_start']}, {last['cut_end']}) (want end {want_end}); "
                            f"the B-roll, from {begins}, now from {taken} into its source (want "
                            f"{want_end - begins})")
                finally:
                    close(s)
            run("C3", c3)

            def crosstalk(name, locked=False):
                """A on track 1 at 0, B on track 2 from A's end − 1 s: the
                session, X (a track-1 word a track-2 word Y runs into, its own
                cut not empty) and Y."""
                s = session_of(name)
                a, b = s.media_of(str(files["A"])), s.media_of(str(files["B"]))
                t1 = tracks(s)[0]
                t2 = new_track(s)
                length = round(ttp.seconds_of(files["A"]) * SEC)
                s.add(a, at=0, track=t1)
                s.add(b, at=length - SEC, track=t2)
                if locked:
                    s.op("set_track", track=t2, locked=True)
                show(s)
                words = read(s)["words"]
                for x in words:
                    if x["track"] != t1:
                        continue
                    y = next((w for w in words if w["track"] == t2
                              and w["start"] < x["start"] < w["end"]), None)
                    if y is not None and x["cut_end"] > x["cut_start"]:
                        return s, x, y, t2
                return s, None, None, t2

            def c4():
                s, x, y, _ = crosstalk("c4")
                try:
                    if x is None:
                        return False, "no track-1 word that a track-2 word runs into"
                    shown = view(s, wait=10)
                    xi, yi = index_of(shown, x["id"]), index_of(shown, y["id"])
                    picked = view(s, focus=True, select=[xi, xi])
                    widened = (picked.get("cut") or {}).get("selection")
                    state["c4"] = (placements(s.project()), x, y)
                    s.op("perform_menu_item", path=["Edit", "Delete"])
                    after = view(s, wait=30)
                    state["c4_after"] = placements(s.project())
                    left = {json.dumps(t["id"], sort_keys=True) for t in after.get("tokens", [])}
                    gone = all(json.dumps(w["id"], sort_keys=True) not in left for w in (x, y))
                    return (widened is not None and widened[0] <= yi and widened[1] >= xi and gone,
                            f"X {x['text']!r} (token {xi}), Y {y['text']!r} (token {yi}); the "
                            f"selection widened to {widened}; neither left {gone}")
                finally:
                    close(s)
            run("C4", c4)

            def c4b():
                if "c4_after" not in state:
                    return False, "C4 did not run"
                s, x, y, _ = crosstalk("c4b")
                try:
                    if x is None or x["id"] != state["c4"][1]["id"]:
                        return False, f"the fresh layout's X {x} differs from C4's"
                    s.op("ripple_delete_ranges", ranges=[[x["cut_start"], x["cut_end"]]])
                    got = placements(s.project())
                    return (got == state["c4_after"],
                            f"X's own cut [{x['cut_start']}, {x['cut_end']}) through "
                            f"ripple_delete_ranges: {got}; the tab's Delete: {state['c4_after']}")
                finally:
                    close(s)
            run("C4b", c4b)

            def c5():
                s, x, y, t2 = crosstalk("c5", locked=True)
                try:
                    if x is None:
                        return False, "no track-1 word that a track-2 word runs into"
                    name = next(t["name"] for t in s.project()["tracks"] if t["id"] == t2) or str(t2)
                    before = placements(s.project())
                    shown = view(s, wait=10)
                    xi = index_of(shown, x["id"])
                    picked = view(s, focus=True, select=[xi, xi])
                    refusal = (picked.get("cut") or {}).get("refusal")
                    s.op("perform_menu_item", path=["Edit", "Delete"])
                    view(s, wait=10)
                    same = placements(s.project()) == before
                    return (refusal == LOCKED.format(name) and same,
                            f"X {x['text']!r} {x['start']}–{x['end']} (token {xi}), Y "
                            f"{y['text']!r} {y['start']}–{y['end']}; cut {picked.get('cut')}; "
                            f"refusal {refusal!r}; placements unchanged {same}")
                finally:
                    close(s)
            run("C5", c5)

            def c6():
                outcomes = []
                for total, refused in ((MAX_CLIPS - 1, True), (MAX_CLIPS - 2, False)):
                    s = Opened(app, ceiling_package(f"c6-{total}", files["A"], total))
                    try:
                        shown = show(s)
                        tokens = shown.get("tokens", [])
                        middle = len(tokens) // 2
                        picked = view(s, focus=True, select=[middle, middle])
                        cut = picked.get("cut") or {}
                        s.op("perform_menu_item", path=["Edit", "Delete"])
                        view(s, wait=10)
                        count = len(s.project()["clips"])
                        if refused:
                            ok = (cut.get("clips_peak") == MAX_CLIPS + 1
                                  and cut.get("refusal") == CEILING.format(MAX_CLIPS + 1)
                                  and count == total)
                        else:
                            ok = (cut.get("clips_peak") == MAX_CLIPS and cut.get("refusal") is None
                                  and count == cut.get("clips_after") == total + 1)
                        outcomes.append((ok, f"N {total}: peak {cut.get('clips_peak')}, after "
                                             f"{cut.get('clips_after')}, refusal "
                                             f"{cut.get('refusal')!r}; clips now {count}"))
                    finally:
                        close(s)
                return all(o[0] for o in outcomes), "; ".join(o[1] for o in outcomes)
            run("C6", c6)

            def c7():
                s = session_of("c7")
                state["c7"] = s
                s.add(s.media_of(str(files["A"])), at=0)
                shown = show(s)
                original = placements(s.project())
                words = read(s)["words"]
                count = len(shown.get("tokens", []))
                first = count // 3
                last = first + 2
                head = next(w for w in words if w["id"] == shown["tokens"][first]["id"])
                tail = next(w for w in words if w["id"] == shown["tokens"][last]["id"])
                delete(s, first, last)
                tab = placements(s.project())
                wav = WORK / "exports" / "c8-tab.wav"
                wav.parent.mkdir(parents=True, exist_ok=True)
                wav.unlink(missing_ok=True)
                s.mcp.export_with({"project": s.path, "preset": "audio_wav", "path": str(wav)},
                                  seconds=600)
                undone = s.op("undo").get("undone")
                back = placements(s.project()) == original
                s.op("ripple_delete_ranges", ranges=[[head["cut_start"], tail["cut_end"]]])
                tool = placements(s.project())
                state["c8"] = wav
                return (undone == "Delete Words" and back and tab == tool and tab != original,
                        f"words {first}…{last}: undo names {undone!r}, back {back}; the tab's "
                        f"placements equal ripple_delete_ranges [{head['cut_start']}, "
                        f"{tail['cut_end']})'s: {tab == tool}")
            run("C7", c7)

            def c8():
                s = state.get("c7")
                if s is None or "c8" not in state:
                    return False, "C7 did not run"
                try:
                    wav = WORK / "exports" / "c8-tool.wav"
                    wav.unlink(missing_ok=True)
                    s.mcp.export_with({"project": s.path, "preset": "audio_wav", "path": str(wav)},
                                      seconds=600)
                    a, b = pcm(state["c8"]), pcm(wav)
                    return (a == b and len(a) > 0,
                            f"the tab's export {len(a)} bytes of PCM, the tool's {len(b)}; equal "
                            f"{a == b}")
                finally:
                    close(s)
            run("C8", c8)

            def c9():
                s = session_of("c9")
                try:
                    a, b = s.media_of(str(files["A"])), s.media_of(str(files["B"]))
                    t1 = tracks(s)[0]
                    first_clip = s.add(b, at=0, track=t1)
                    s.add(a, at=round(ttp.seconds_of(files["B"]) * SEC), track=t1)
                    shown = show(s)
                    words = read(s)["words"]
                    mine = [w for w in words if w["media"] == a]
                    index = index_of(shown, mine[len(mine) // 2]["id"])
                    picked = view(s, focus=True, select=[index, index + 1])
                    one = picked.get("cut") or {}
                    set1 = s.op("get_project").get("in_out_range")
                    s.op("ripple_delete", clips=[first_clip])
                    moved = view(s, wait=10)
                    two = moved.get("cut") or {}
                    set2 = s.op("get_project").get("in_out_range")
                    s.op("set_range", start=0, end=SEC)
                    new_track(s)
                    view(s, wait=10)
                    set3 = s.op("get_project").get("in_out_range")
                    follows = (set1 == {"start": one.get("start"), "end": one.get("end")}
                               and set2 == {"start": two.get("start"), "end": two.get("end")}
                               and two.get("start") is not None and two.get("start") < one["start"])
                    return (follows and set3 == {"start": 0, "end": SEC},
                            f"selected: range {set1}, cut {one.get('start')}…{one.get('end')}; B "
                            f"ripple-deleted: range {set2}, cut {two.get('start')}…"
                            f"{two.get('end')}; set elsewhere then an edit: {set3}")
                finally:
                    close(s)
            run("C9", c9)
        finally:
            if app is not None:
                app.stop()
            if stand_in is not None:
                stand_in.stop()


# --------------------------------------------------------------------------
# Running


def build_mutant_app(name):
    import assistant_session_proof as sp
    import tree_copy
    base = WORK / f"mutant-app-{name}"
    tree_copy.remove_tree(str(base))
    root, reason = tree_copy.make_copy(str(base / "tree"))
    if root is None:
        return None, reason
    why = apply_edits(MUTANTS[name][2], Path(root) / "app" / "Sources")
    if why:
        return None, why
    print(f"mutant {name}: building the copy (up to {sp.WALL_BUILD} s)…", flush=True)
    return tree_copy.build_app(root, sp.WALL_BUILD, env=sp.child_env())


def run_rows(wanted, mutant=None):
    results = Rows()
    probe_wanted = [r for r in wanted if r in PROBE_ROWS]
    app_wanted = [r for r in wanted if r in APP_ROWS]
    kind = MUTANTS[mutant][0] if mutant else None
    if probe_wanted:
        if "U0" not in probe_wanted:
            probe_wanted = ["U0"] + probe_wanted
        why = probe_rows(results, probe_wanted, mutant if kind == "probe" else None)
        if why:
            return None, why
    if app_wanted:
        import proof_app
        if kind == "app":
            app_path, why = build_mutant_app(mutant)
            if app_path is None:
                return None, f"the copy did not build: {why}"
        else:
            app_path = str(proof_app.bundle())
            try:
                proof_app.require_fresh(proof_app.binary())
            except proof_app.StaleApp as stale:
                for row in app_wanted:
                    results.score(row, False, f"not run: {stale}")
                return results, None
        app_rows(results, app_wanted, str(app_path), ttp.fixtures())
        for row in app_wanted:
            if row not in results.results and row not in results.skipped:
                results.score(row, False, "not scored")
    return results, None


def mutant_run(name):
    _, named, _ = MUTANTS[name]
    results, why = run_rows(list(named), mutant=name)
    if results is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    ttp.report(results, list(named))
    lost = [r for r in named if r not in results.results]
    if lost:
        print(f"mutant {name}: the control could not be performed — not scored: {', '.join(lost)}")
        return 2
    survived = [r for r in named if results.results[r][0]]
    if survived:
        print(f"mutant {name}: SURVIVED — {', '.join(survived)} passed")
        return 1
    print(f"mutant {name}: caught — {', '.join(named)} failed")
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    if args.mutants:
        codes = {name: mutant_run(name) for name in MUTANTS}
        print("mutants: " + ", ".join(
            f"{n} {'caught' if c == 0 else 'SURVIVED' if c == 1 else 'NOT PERFORMED'}"
            for n, c in codes.items()))
        return 0 if all(c == 0 for c in codes.values()) else 1
    if args.mutant:
        return mutant_run(args.mutant)
    wanted = args.only.split(",") if args.only else ROWS
    unknown = [r for r in wanted if r not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    results, why = run_rows(wanted)
    if results is None:
        print(f"not run: {why}")
        return 1
    return 0 if ttp.report(results, [r for r in ROWS if r in wanted or r == "U0"]) else 1


if __name__ == "__main__":
    code = 2
    try:
        code = main()
    finally:
        cloud = sys.modules.get("cloud_captions_proof")
        if cloud is not None:
            from mcp import remove_scratch
            for scratch in cloud.SCRATCH:
                remove_scratch(scratch)
    sys.exit(code)
