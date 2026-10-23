#!/usr/bin/env python3
"""Cut by transcript CT-4 (spec §11 TR-5, TR-11, AI-16 as TR-11 amends it):
`get_transcript`, the false-start turn through the assistant, and Stop on its
on-device run.

    python3 tools/proof/transcript_proof.py [--mutant NAME] [--only IDS]

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The one app
launch (`assistant_session_proof.App`) is given a 0700 `-RCSecretFolder`
holding 0600 `anthropic-key` and `assemblyai-key`, both the dummy `proof-key`,
`-RCAssemblyAIEndpoint` at `assemblyai_fake.py` (`cloud_captions_probe.Fake`)
and `RC_ASSISTANT_BASE_URL` at `anthropic_fake.py`
(`assistant_session_proof.Fake`). No paid request is made.

Probe rows (`transcript_probe.swift`, copied in as `main.swift` and built with
`swift_build.build()` over `swift_build.app_sources()` of `app/Sources`, or of
a mutant's copy, run once under `tools/proof/work/transcript/<tree|mutant-NAME>/`,
killed at a 240 s wall):
  P0  the probe builds (a build failure is this row's scored FAIL).
  P1  `cloudWords` with job start 1 s, in 0.5 s, speed 2, a file served out
      of order: a word before `in` absent, one at `in` present; the ticks are
      `MediaTranscript.words`' own and the words sorted; "um,", "Uh" and "er"
      fillers, "umbrella" not.
  P2  `deviceWords`: runs at start + t / speed, one at the clip's end dropped,
      sorted, "uh" flagged.
  P3  `cached` over a temp cache: a disfluent marker → `fillersReported`
      true; a marker without → false; a changed source stamp → nil; no file
      → nil.

App rows (the app `proof_app` chooses — Debug by default, `RC_PROOF_APP=release`
for the record; host-state input `media/speech.mov`, whose absence is a
scored FAIL):
  G0  no `Frame Job: ` line; `get_transcript` takes exactly clip, language
      and project, clip required.
  G1  a 5 s clip at 0, `transcribe {engine: assemblyai, place: false}` over
      the fake serving `cloud_captions_proof.DISFLUENT_WORDS`, saved:
      `get_transcript {clip}` answers engine assemblyai, fillers_reported
      true, words (text, start, end) == `mapped(clip, DISFLUENT_WORDS)`,
      filler true exactly on "um,", "Uh", "er"; `get_project` unchanged and
      no AssemblyAI request.
  G2  fillers_proof M3's shape (a clip at 1 s, in 0.5 s): the words equal
      `mapped` for that clip.
  G3  M4's raw edit on G2's package (`disfluencies` out of the marker and
      `requested`): fillers_reported false, the same words, the filler
      sentence in note.
  G4  refusals by exact sentence: no clip; clip 987654; a text clip; a
      misspelt language.
  G5  a new project with speech.mov and no cache: engine apple,
      fillers_reported false, "quick" and "fox" among the normalised words,
      every start in [clip start, clip end), sorted, no AssemblyAI request.
      A named host SKIP when refused as not installed or not available.
  A1  on G1's project, the stand-in turn get_transcript → ripple_delete_ranges
      [[360000, 960000]] ("Hello there", the false start) → "Cut.": finished,
      no error result, the get_transcript result holds G1's words, the clips
      (0, 360000, 0) and (360000, 2040000, 960000), one MCP undo restores
      (0, 3000000, 0), no stand-in failure and no AssemblyAI request.
  A2  that turn's first POST lists get_transcript with defer_loading true,
      and its system holds the "Cutting words:" paragraph verbatim.
  A3  Stop reaches the on-device run: `long_fixture`'s ~3600 s long.wav at 0,
      no cache, the model's get_transcript sent with stop_after STOP_AFTER:
      `stopped_turn(…, "get_transcript", "The transcription was cancelled.")`
      has no problems, no stand-in failure. A named host SKIP when G5 was.

Mutants (`--mutant`), each anchor asserted to occur once in its file:
  no-filler-flag         filler always false (P1, P2)
  unsorted               no sort (P1)
  device-past-clip-end   no end filter (P2)
  fillers-reported-any   fillersReported true for any current marker (P3)
  stale-cache-read       file and marker read with MediaTranscript.read
                         directly, no source stamp (P3)
  no-transcript-stop     the `stop?.onCancel { token.cancel() }` line deleted
                         from AgentServer+Transcript.swift in a tree copy
                         (`tree_copy.make_copy` into work/transcript/mutant/tree,
                         `tree_copy.build_app`), then G5 and A3 in that app: A3
                         must fail with LATE among its problems

Exit: a plain run exits 0 iff every row passed or was a named host SKIP,
else 1. A `--mutant` run exits 0 when every row the mutant names failed
(caught), 1 when one passed (survived), and 2 when the control could not be
performed: an anchor not found exactly once, the copy did not build, a named
row was not scored or was a host SKIP, or A3 failed without LATE.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import string
import subprocess
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import swift_build  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/transcript"
PROBE = ROOT / "tools/proof/transcript_probe.swift"
SPEECH = ROOT / "tools/proof/media/speech.mov"
PROBE_ROWS = ["P0", "P1", "P2", "P3"]
APP_ROWS = ["G0", "G1", "G2", "G3", "G4", "G5", "A1", "A2", "A3"]
ROWS = PROBE_ROWS + APP_ROWS
WALL = 240
SEC = 600_000
KEY = "proof-key"

TR = "TranscriptReader.swift"
TS = "AgentServer+Transcript.swift"
STOP_LINE = "stop?.onCancel { token.cancel() }"
# name: (the rows it must fail, [(file, before, after), ...]); the app mutant's
# one edit deletes its line.
MUTANTS = {
    "no-filler-flag": (["P1", "P2"], [
        (TR, "filler: FillerWords.isFiller($0.element.text)", "filler: false"),
        (TR, "filler: FillerWords.isFiller(run.text)", "filler: false")]),
    "unsorted": (["P1"], [
        (TR, "        words.sorted {\n"
             "            ($0.word.start, $0.word.end, $0.index) < ($1.word.start, $1.word.end, "
             "$1.index)\n"
             "        }.map(\\.word)\n",
         "        words.map(\\.word)\n")]),
    "device-past-clip-end": (["P2"], [(TR, "            guard start < end else { continue }\n", "")]),
    "fillers-reported-any": (["P3"], [
        (TR, "FillerDetector.fillersFile(for: media, url: url, in: cacheDir) != nil", "true")]),
    "stale-cache-read": (["P3"], [
        (TR, "        guard\n"
             "            let file = FillerDetector.transcriptFile(\n"
             "                for: media, url: url, in: cacheDir, use: .captions)\n"
             "        else { return nil }\n",
         "        guard let file = MediaTranscript.read(for: media.id, in: cacheDir),\n"
         "            MediaTranscript.readStamp(for: media.id, in: cacheDir) != nil\n"
         "        else { return nil }\n")]),
    "no-transcript-stop": (["A3"], [(TS, STOP_LINE, None)]),
}
APP_MUTANT = "no-transcript-stop"

FALSE_START = ("Cutting words: `detect_fillers` answers the filler words (um, uh) as ranges for "
               "`ripple_delete_ranges`. A false start, words the speaker abandoned or said again, "
               "is a judgement of meaning, so cut one only when the person asks: read the clip's "
               "words and their times with `get_transcript`, say which words you will cut, then "
               "cut them in one `ripple_delete_ranges` call, each range from the first cut "
               "word's start to the last cut word's end.")
FILLER_NOTE = ("These words were not transcribed with filler words, so a filler missing here "
               "may still be in the audio.")
CANCELLED = "The transcription was cancelled."
FILLERS = {"um", "uh", "hmm", "mhm", "uh-huh", "ah", "huh", "hm", "m", "er", "erm"}


def normalized(text):
    return text.lower().strip(string.punctuation + string.whitespace)


# --------------------------------------------------------------------------
# The probe


def build(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "transcript-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def mutate(name, dest):
    """A copy of `app/Sources` with the mutant's edits; why, when an anchor is
    not found exactly once."""
    shutil.copytree(ROOT / "app/Sources", dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    try:
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=WALL,
                                cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


# --------------------------------------------------------------------------
# The app rows


class Rows:
    def __init__(self):
        self.results = {}
        self.skipped = {}

    def score(self, row, ok, detail):
        if ok is None:
            self.skipped[row] = detail
        else:
            self.results[row] = (bool(ok), detail)


def close(session):
    try:
        session.op("close_project", discard=True)
    except Exception:  # noqa: BLE001 — closing is housekeeping
        pass


def secret_folder():
    """A 0700 folder holding 0600 `anthropic-key` and `assemblyai-key`, both
    the dummy."""
    folder = WORK / "secrets"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    for name in ("anthropic-key", "assemblyai-key"):
        descriptor = os.open(folder / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write(KEY + "\n")
    return str(folder)


def triples(words):
    return [(w.get("text"), w.get("start"), w.get("end")) for w in words]


def build_mutant_app():
    """(app path, None) or (None, why): the tree copied, the stop line deleted
    from the copy's AgentServer+Transcript.swift, `tree_copy.build_app` run."""
    import assistant_session_proof as session_proof
    import tree_copy
    base = WORK / "mutant"
    tree_copy.remove_tree(str(base))
    root, reason = tree_copy.make_copy(str(base / "tree"))
    if root is None:
        return None, reason
    path = os.path.join(root, "app", "Sources", TS)
    with open(path) as handle:
        lines = handle.read().splitlines(keepends=True)
    hits = [line for line in lines if line.strip() == STOP_LINE]
    if len(hits) != 1:
        return None, f"{TS} has {len(hits)} `{STOP_LINE}` lines, not 1"
    with open(path, "w") as handle:
        handle.write("".join(line for line in lines if line.strip() != STOP_LINE))
    print(f"mutant: {STOP_LINE} deleted from the copy's {TS}; building it (up to "
          f"{session_proof.WALL_BUILD} s)…", flush=True)
    app, reason = tree_copy.build_app(root, session_proof.WALL_BUILD,
                                      env=session_proof.child_env())
    if app is None:
        return None, reason
    return str(app), None


def app_rows(results, wanted, app_path, mutant=False):
    import assistant_session_proof as sp
    import cloud_captions_probe
    import cloud_captions_proof as cloud

    os.makedirs(cloud.WORK, exist_ok=True)
    os.makedirs(sp.WORK, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    words = cloud.DISFLUENT_WORDS
    lock, waited, holder = cloud_captions_probe.hold_cloud_lock(1800)
    if lock is None:
        for row in wanted:
            results.score(row, False, f"not run: the cloud instruments' lock is held by {holder}")
        return

    def run(row, body):
        if row not in wanted:
            return
        try:
            ok, detail = body()
        except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
            ok, detail = False, f"{type(problem).__name__}: {problem}; " + \
                traceback.format_exc(limit=2).splitlines()[-1]
        results.score(row, ok, detail)

    stand_in = None
    app = None
    state = {}
    with contextlib.closing(lock), cloud_captions_probe.Fake("transcript") as aai:
        try:
            stand_in = sp.Fake(str(WORK / "anthropic-fake"))
            app = sp.App("transcript" + ("-mutant" if mutant else ""), app_path,
                         ["-RCSecretFolder", secret_folder(), "-RCAssemblyAIEndpoint", aai.base],
                         stand_in.base)
            app.connect()

            def aai_requests():
                return len(aai.log().get("requests", []))

            def g0():
                complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
                schema = app.mcp.schemas().get("get_transcript", {}).get("inputSchema", {})
                keys = sorted(schema.get("properties", {}))
                required = schema.get("required")
                return (not complaints and keys == ["clip", "language", "project"]
                        and required == ["clip"],
                        f"parity lines {complaints[:3]}; properties {keys}, required {required}")
            run("G0", g0)

            def g1():
                cloud.scenario(aai, disfluent_words=words)
                session = cloud.Session(app, "transcript-G1")
                state["g1"] = session
                media = session.media_of(str(SPEECH))
                clip = session.add(media, at=0, duration=5 * SEC)
                session.op("transcribe", engine="assemblyai", place=False)
                session.save()
                state["g1_clip"] = clip
                placed = session.clip(clip)
                want = triples(cloud.mapped(placed, words))
                state["g1_words"] = want
                mark = aai_requests()
                before = session.op("get_project")
                answer = session.op("get_transcript", clip=clip)
                after = session.op("get_project")
                got = answer.get("words") or []
                flagged = [w.get("text") for w in got if w.get("filler") is True]
                sent = aai_requests() - mark
                return (answer.get("ok") is True and answer.get("engine") == "assemblyai"
                        and answer.get("fillers_reported") is True and answer.get("clip") == clip
                        and answer.get("media") == media and answer.get("count") == len(got)
                        and triples(got) == want and flagged == ["um,", "Uh", "er"]
                        and all(isinstance(w.get("filler"), bool) for w in got)
                        and "note" not in answer and before == after and sent == 0,
                        f"engine {answer.get('engine')}, fillers_reported "
                        f"{answer.get('fillers_reported')}, language {answer.get('language')!r}; "
                        f"words {triples(got)} want {want}; fillers {flagged}; note "
                        f"{answer.get('note')!r}; get_project unchanged {before == after}; "
                        f"AssemblyAI requests during the call {sent}")
            run("G1", g1)

            def g2():
                cloud.scenario(aai, disfluent_words=words)
                session = cloud.Session(app, "transcript-G2")
                state["g2"] = session
                media = session.media_of(str(SPEECH))
                clip = session.add(media, at=SEC // 2, duration=5 * SEC)
                session.op("trim_start", clip=clip, to=SEC)
                session.op("transcribe", engine="assemblyai", place=False)
                session.save()
                placed = session.clip(clip)
                want = triples(cloud.mapped(placed, words))
                state.update(g2_media=media, g2_clip=clip, g2_words=want)
                answer = session.op("get_transcript", clip=clip)
                got = triples(answer.get("words") or [])
                return (placed["start"] == SEC and placed["source"]["in"] == SEC // 2
                        and want and got == want and answer.get("fillers_reported") is True,
                        f"clip start {placed['start']} in {placed['source']['in']}; words {got} "
                        f"want {want}")
            run("G2", g2)

            def g3():
                session = state.get("g2")
                if session is None:
                    return False, "G2's session is not available"
                media, clip = state["g2_media"], state["g2_clip"]
                edits = ((cloud.cache_path(session, media, marker=True),
                          '"disfluencies":true,', ""),
                         (cloud.cache_path(session, media), '"requested":{"disfluencies":true,',
                          '"requested":{'))
                found = []
                for path, before, after in edits:
                    text = cloud.read(path).decode("utf-8")
                    found.append(text.count(before) == 1)
                    with open(path, "wb") as handle:
                        handle.write(text.replace(before, after).encode("utf-8"))
                answer = session.op("get_transcript", clip=clip)
                got = triples(answer.get("words") or [])
                return (all(found) and answer.get("engine") == "assemblyai"
                        and answer.get("fillers_reported") is False
                        and got == state["g2_words"] and answer.get("note") == FILLER_NOTE,
                        f"raw edits found {found}; engine {answer.get('engine')}, "
                        f"fillers_reported {answer.get('fillers_reported')}; the same words "
                        f"{got == state['g2_words']}; note {answer.get('note')!r}")
            run("G3", g3)
            if state.get("g2") is not None:
                close(state["g2"])

            def g4():
                session = cloud.Session(app, "transcript-G4")
                try:
                    media = session.media_of(str(SPEECH))
                    clip = session.add(media, at=0, duration=5 * SEC)
                    track = session.project()["tracks"][0]["id"]
                    session.op("add_track")
                    tracks = [t["id"] for t in session.project()["tracks"]]
                    other = [t for t in tracks if t != track][0]
                    added = session.op("add_text_clip", track=other, at=0, duration=SEC)
                    text = (added.get("new_clips") or [None])[0]
                    missing = session.error("get_transcript")
                    unknown = session.error("get_transcript", clip=987654)
                    wordless = session.error("get_transcript", clip=text)
                    spelling = session.error("get_transcript", clip=clip,
                                             language="xx-notalanguage")
                    want_spelling = ("get_transcript: “xx-notalanguage” is not a language speech "
                                     "recognition knows — check the tag's spelling. It knows ")
                    return (missing == "get_transcript: Missing required argument: clip (an id)"
                            and unknown == "get_transcript: No clip has id 987654. get_project "
                            "lists the clips."
                            and wordless == f"get_transcript: Clip {text} has no words to read: "
                            "its source is not a media file, so it has no speech."
                            and (spelling or "").startswith(want_spelling),
                            f"no clip → {missing!r}; 987654 → {unknown!r}; text clip {text} → "
                            f"{wordless!r}; misspelt → {(spelling or '')[:120]!r}")
                finally:
                    close(session)
            run("G4", g4)

            def g5():
                session = cloud.Session(app, "transcript-G5")
                try:
                    media = session.media_of(str(SPEECH))
                    clip = session.add(media, at=0)
                    placed = session.clip(clip)
                    mark = aai_requests()
                    refusal = session.error("get_transcript", clip=clip)
                    if refusal is not None:
                        if "not installed" in refusal or "not available" in refusal:
                            state["no_device"] = refusal
                            return None, f"on-device recognition on this Mac: {refusal[:160]!r}"
                        return False, f"refused: {refusal!r}"
                    answer = session.op("get_transcript", clip=clip)
                    got = answer.get("words") or []
                    spoken = [normalized(w.get("text", "")) for w in got]
                    starts = [w.get("start") for w in got]
                    end = placed["start"] + placed["duration"]
                    inside = all(placed["start"] <= s < end for s in starts)
                    ordered = all((a["start"], a["end"]) <= (b["start"], b["end"])
                                  for a, b in zip(got, got[1:]))
                    flags = all(w.get("filler") == (normalized(w.get("text", "")) in FILLERS)
                                for w in got)
                    sent = aai_requests() - mark
                    return (answer.get("engine") == "apple"
                            and answer.get("fillers_reported") is False
                            and "quick" in spoken and "fox" in spoken and inside and ordered
                            and flags and answer.get("note") == FILLER_NOTE and sent == 0,
                            f"engine {answer.get('engine')}, language {answer.get('language')!r}, "
                            f"fillers_reported {answer.get('fillers_reported')}; {len(got)} "
                            f"words {spoken[:12]}; inside [{placed['start']}, {end}) {inside}; "
                            f"sorted {ordered}; flags TR-8's {flags}; note "
                            f"{answer.get('note')!r}; AssemblyAI requests {sent}")
                finally:
                    close(session)
            run("G5", g5)

            def a1():
                session, clip = state.get("g1"), state.get("g1_clip")
                if session is None:
                    return False, "G1's session is not available"
                stand_in.scenario([
                    sp.use("toolu_g1", "get_transcript", {"clip": clip}),
                    sp.use("toolu_g2", "ripple_delete_ranges", {"ranges": [[360000, 960000]]},
                           said="I'll cut \"Hello there\", the false start."),
                    sp.say("Cut.")])
                mark = aai_requests()
                ok, answer = app.call("assistant_send", project=session.path,
                                      text="Take out the false start.", timeout=sp.WALL_TURN)
                log = stand_in.log()
                state["a1_log"] = log
                if not ok:
                    return False, f"assistant_send refused: {answer}"
                problems = []
                if answer.get("state") != "finished":
                    problems.append(f"state {answer.get('state')}")
                results_ = (sp.tool_results(answer, "get_transcript")
                            + sp.tool_results(answer, "ripple_delete_ranges"))
                if [r.get("is_error") for r in results_] != [False, False]:
                    problems.append(f"results {[(r.get('name'), r.get('is_error')) for r in results_]}")
                sent = sp.posts(log)
                block = sp.tool_result_block(sent[1].get("body") or {}, "toolu_g1") \
                    if len(sent) > 1 else None
                try:
                    read = json.loads(block[1]) if block and not block[0] else {}
                except ValueError:
                    read = {}
                if triples(read.get("words") or []) != state.get("g1_words"):
                    problems.append(f"get_transcript's result {str(block)[:160]}")
                clips = [(c["start"], c["duration"], c["source"]["in"])
                         for c in session.project()["clips"] if c["source"]["kind"] == "media"]
                if sorted(clips) != [(0, 360000, 0), (360000, 2040000, 960000)]:
                    problems.append(f"clips {clips}")
                session.op("undo")
                back = [(c["start"], c["duration"], c["source"]["in"])
                        for c in session.project()["clips"] if c["source"]["kind"] == "media"]
                if back != [(0, 3000000, 0)]:
                    problems.append(f"after undo {back}")
                if log.get("failures"):
                    problems.append(f"failures {log['failures']}")
                if aai_requests() != mark:
                    problems.append(f"AssemblyAI requests {aai_requests() - mark}")
                return not problems, (f"{sp.brief(answer)}; clips {clips}; after undo {back}"
                                      + ("" if not problems else " — " + "; ".join(problems)))
            run("A1", a1)

            def a2():
                log = state.get("a1_log")
                if log is None:
                    return False, "A1's stand-in log is not available"
                sent = sp.posts(log)
                if not sent:
                    return False, "no POST in A1's log"
                first = sent[0].get("body") or {}
                tool = next((t for t in first.get("tools", []) if t.get("name") == "get_transcript"),
                            None)
                system = sp.system_text(first) or ""
                return (tool is not None and tool.get("defer_loading") is True
                        and FALSE_START in system,
                        f"get_transcript listed {tool is not None}, defer_loading "
                        f"{(tool or {}).get('defer_loading')}; the paragraph verbatim "
                        f"{FALSE_START in system}")
            run("A2", a2)
            if state.get("g1") is not None:
                close(state["g1"])

            def a3():
                if "G5" not in wanted:
                    return False, "A3 needs G5's host check"
                if state.get("no_device"):
                    return None, f"G5 was a host skip: {state['no_device'][:160]!r}"
                import speech_engine_proof  # the fixtures' one maker
                _, ten, _, _ = speech_engine_proof.make_fixtures()
                long, seconds = sp.long_fixture(ten)
                session = cloud.Session(app, "transcript-A3")
                try:
                    media = session.media_of(long)
                    clip = session.add(media, at=0)
                    stand_in.scenario([sp.use("toolu_a3", "get_transcript", {"clip": clip}),
                                       sp.say("A3: stopped.")])
                    ok, answer = app.call("assistant_send", project=session.path,
                                          text="Read the words (A3).",
                                          stop_after=sp.STOP_AFTER, timeout=sp.WALL_ST)
                    if not ok:
                        return False, f"assistant_send with stop_after refused: {answer}"
                    log = stand_in.log()
                    problems = sp.stopped_turn(answer, "get_transcript", CANCELLED)
                    if log.get("failures"):
                        problems.append(f"failures {log['failures']}")
                    results_ = sp.tool_results(answer, "get_transcript")
                    return not problems, (
                        f"a {seconds:.0f} s WAV; {sp.brief(answer)}, stopped_ms "
                        f"{answer.get('stopped_ms')}; get_transcript results "
                        f"{[(r.get('is_error'), r.get('summary')) for r in results_]}"
                        + ("" if not problems else " — " + "; ".join(problems)))
                finally:
                    close(session)
            run("A3", a3)
        finally:
            if app is not None:
                app.stop()
            if stand_in is not None:
                stand_in.stop()


# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    app_mutant = args.mutant == APP_MUTANT
    if args.mutant:
        wanted = ["G5", "A3"] if app_mutant else PROBE_ROWS
    else:
        wanted = args.only.split(",") if args.only else ROWS
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    if args.mutant and args.only:
        print("a mutant runs its own rows")
        return 2
    probe_wanted = [row for row in wanted if row in PROBE_ROWS]
    app_wanted = [row for row in wanted if row in APP_ROWS]
    if probe_wanted and "P0" not in probe_wanted:
        probe_wanted = ["P0"] + probe_wanted
    if not app_mutant and app_wanted and "G0" not in app_wanted:
        app_wanted = ["G0"] + app_wanted
    needs = {"G3": "G2", "A1": "G1", "A2": "A1", "A3": "G5"}
    for _ in range(3):
        app_wanted = sorted(set(app_wanted) | {needs[r] for r in app_wanted if r in needs},
                            key=APP_ROWS.index)
    wanted = [row for row in ROWS if row in probe_wanted + app_wanted]
    results = Rows()
    not_scored = []

    if probe_wanted:
        here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
        if here.exists():
            shutil.rmtree(here)
        here.mkdir(parents=True)
        sources = ROOT / "app/Sources"
        if args.mutant:
            why = mutate(args.mutant, here / "Sources")
            if why:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            sources = here / "Sources"
        binary, why = build(sources, here)
        results.score("P0", binary is not None, why or f"built from {sources}")
        if binary is None and args.mutant:
            print(f"P0 fail — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — the copy did "
                  "not build")
            return 2
        answers, why = (probe(binary, here) if binary is not None
                        else (None, "not run: the probe did not build"))
        for row in probe_wanted:
            if row == "P0":
                continue
            answer = next((a for a in answers or [] if a.get("id") == row), None)
            if answer is None:
                not_scored.append(row)
                results.score(row, False, f"no row: {why or 'the probe did not answer it'}")
            else:
                results.score(row, answer.get("pass") is True, answer.get("detail", ""))

    if app_wanted:
        import proof_app
        if not SPEECH.exists():
            for row in app_wanted:
                results.score(row, False, "media/speech.mov is missing: tools/proof/README.md "
                              "(\"Phase 4 adds a recording of SPEECH\") says how to make it")
        else:
            if app_mutant:
                app_path, why = build_mutant_app()
                if app_path is None:
                    print(f"mutant {args.mutant}: the control could not be performed — the copy "
                          f"did not build: {why}")
                    return 2
            else:
                app_path = str(proof_app.bundle())
                try:
                    proof_app.require_fresh(proof_app.binary())
                except proof_app.StaleApp as stale:
                    app_path = None
                    for row in app_wanted:
                        results.score(row, False, f"not run: {stale}")
            if app_path is not None:
                app_rows(results, app_wanted, app_path, mutant=app_mutant)
        for row in app_wanted:
            if row not in results.results and row not in results.skipped:
                results.score(row, False, "not scored")

    for row in wanted:
        if row in results.skipped:
            print(f"{row} SKIP — host: {results.skipped[row]}")
            continue
        good, detail = results.results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    scored = [row for row in wanted if row in results.results]
    passed = sum(1 for row in scored if results.results[row][0])
    print(f"scores: {passed}/{len(scored)}"
          + (f", skipped {', '.join(r for r in wanted if r in results.skipped)}"
             if results.skipped else ""))
    if not args.mutant:
        return 0 if passed == len(scored) else 1
    skipped = [row for row in named if row in results.skipped]
    if skipped:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) a host skip: {', '.join(skipped)}")
        return 2
    lost = [row for row in named if row in not_scored or row not in results.results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results.results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 1
    if app_mutant:
        import assistant_session_proof as sp
        if sp.LATE not in results.results["A3"][1]:
            print(f"mutant {args.mutant}: the control could not be performed — A3 failed "
                  f"without {sp.LATE!r} in its detail")
            return 2
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 0


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
