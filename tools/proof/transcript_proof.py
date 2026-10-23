#!/usr/bin/env python3
"""Cut by transcript CT-4 (spec §11 TR-5, TR-11, AI-16 as TR-11 amends it),
#331 (TR-13) and #332 (TR-14): `get_transcript`, its `from`/`to` window, its
on-device cache, the false-start turn through the assistant, and Stop on its
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
  P2  `deviceWords` over `Heard(runs:over:)` of the clip: runs at start +
      t / speed, one at the window's source end dropped, sorted, "uh" flagged.
  P3  `cached` over a temp cache: a disfluent marker → `fillersReported`
      true; a marker without → false; a changed source stamp → nil; no file
      → nil.
  P4  `window` on a 10 s clip at 1 s (in 0.5 s, speed 2): neither bound →
      nil; `from` alone → [from, clip end); `to` alone → [clip start, to);
      a wider pair clamped to the clip; equal and reversed bounds `.empty`;
      `from` at the clip's end, `to` at its start and a pair past it
      `.outside`; each `errorDescription` TR-13's exact sentence.
  P5  `overlapping` over [1000000, 2000000): a word across `from`, one
      inside, one across `to` and a zero-length word at `from` kept whole;
      a word ending at `from`, one starting at `to` and a zero-length word
      at `to` dropped; the input order kept.
  P6  `recognitionJob` on P4's clip (the 2 s pad is 600000 ticks at speed
      2): a middle window, one at the clip's start and one at its end give
      their padded start, duration, in and length, clamped to the clip; the
      whole clip gives the job itself; 1 s into the middle sub-run is
      `Transcriber.project`'s 7 s into the clip's, within 1 tick.
  P7  `DeviceTranscriptCache` over a temp cache and a stat-able file (TR-14):
      empty → nil; a run over [0 s, 6 s) stored, a lookup of [1 s, 2 s) hits
      and of [5 s, 7 s) is nil; the same lookup under language fr-FR, another
      system or version + 1 nil; the file rewritten to another size, with a
      fresh stamp, nil; `merged` narrow then wide → 1 run, then disjoint → 2,
      another stamp → 1; garbage bytes read nil and a store over them
      succeeds; `Heard(runs:over:)` clamps to [0, sourceLength] and drops a
      NaN.
  P8  `heard()` with a counting `recognize`: the 1st call cached false and
      the file written, the 2nd cached true with still 1 run; no `cacheDir`
      runs every time and writes nothing; a throwing `recognize` rethrows and
      writes nothing; `cancelled` true and a `recognize` that rewrites the
      media file write nothing.

App rows (the app `proof_app` chooses — Debug by default, `RC_PROOF_APP=release`
for the record; host-state input `media/speech.mov`, whose absence is a
scored FAIL):
  G0  no `Frame Job: ` line; `get_transcript` takes exactly clip, from,
      language, project and to, clip required.
  G1  a 5 s clip at 0, `transcribe {engine: assemblyai, place: false}` over
      the fake serving `cloud_captions_proof.DISFLUENT_WORDS`, saved:
      `get_transcript {clip}` answers engine assemblyai, fillers_reported
      true, words (text, start, end) == `mapped(clip, DISFLUENT_WORDS)`,
      filler true exactly on "um,", "Uh", "er"; `get_project` unchanged and
      no AssemblyAI request.
  G6  on G1's project (TR-13): {from 600000, to 1200000} answers exactly
      Hello, there and everyone with G1's own times (Hello and everyone
      across the edges), from/to echoed, count 3; {from 1800000} answers
      welcome and back with to echoed as 3000000; {to 360000} answers count
      0 and the windowed note; `get_project` unchanged, no AssemblyAI
      request. Every bound is asserted on the canvas's frame grid first.
  G7  the window's refusals by exact sentence on a fresh 5 s clip at 0:
      (600000, 600000) and (1200000, 600000) empty; (600001, 605000) empty
      naming the snapped pair; {from 3600000} and {to 0} outside; {from
      "soon"} the unreadable-time sentence; a bad window with a misspelt
      language answers the window refusal (the order).
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
      Its words are kept for G8.
  G8  speech.mov added as G5 adds it, windowed on G5's "fox" (TR-13): engine
      apple, a word that normalises to "fox", from/to echoed, every word
      overlapping the echoed window, fewer words than G5's, no AssemblyAI
      request. A named host SKIP when G5 was.
  G9  speech.mov copied (`shutil.copy2`) into work/transcript/, a new session
      on the copy (TR-14): call 1 engine apple, cached false, and
      `<package>/cache/device-transcripts/<media>-<language>.json` holds 1
      run; call 2 cached true, the same words (both wall times reported, not
      scored); "planted" written as the file's first word → call 3 answers it,
      cached true; a window on one word → cached true, call 3's overlapping
      words, still 1 run; the copy's mtime moved 10 s forward → cached false,
      no "planted", the stamp's `modified` changed; no AssemblyAI request. The
      copy and the package are removed. A named host SKIP when G5 was.
  G10 a fresh package: a windowed call → cached false, 1 run shorter than the
      clip; the same window → cached true; the whole clip → cached false,
      then 1 run (the windowed one pruned). A named host SKIP when G5 was.
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
      has no problems, no stand-in failure, and the package's
      `cache/device-transcripts/` holds no file (TR-14: a cancelled run stores
      nothing). A named host SKIP when G5 was.

Mutants (`--mutant`), each anchor asserted to occur once in its file:
  no-filler-flag         filler always false (P1, P2)
  unsorted               no sort (P1)
  device-past-clip-end   no source-end filter (P2)
  fillers-reported-any   fillersReported true for any current marker (P3)
  stale-cache-read       file and marker read with MediaTranscript.read
                         directly, no source stamp (P3)
  window-start-only      the overlap test is start in [from, to) (P5)
  window-no-clamp        no max/min against the clip (P4)
  window-equal-allowed   `to <= from` is `to < from` (P4)
  window-outside-allowed the `.outside` throw removed (P4)
  no-recognition-pad     the pad is 0 (P6)
  device-stamp-ignored   `lookup`'s stamp test removed (P7)
  device-stamp-source-only  `lookup` compares only the stamps' `source` (P7)
  device-overlap-hit     `covers` is an overlap, not containment (P7)
  device-no-prune        `merged` keeps the runs the new one contains (P7)
  device-no-read         `heard` never looks the run up (P8)
  device-cancelled-stores  `heard`'s `!cancelled()` test removed (P8)
  device-no-restamp      `heard`'s stamp-after-the-run test removed (P8)
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
PROBE_ROWS = ["P0", "P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8"]
APP_ROWS = ["G0", "G1", "G6", "G7", "G2", "G3", "G4", "G5", "G8", "G9", "G10", "A1", "A2",
            "A3"]
ROWS = PROBE_ROWS + APP_ROWS
WALL = 240
SEC = 600_000
KEY = "proof-key"

TR = "TranscriptReader.swift"
TS = "AgentServer+Transcript.swift"
DC = "DeviceTranscriptCache.swift"
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
    "device-past-clip-end": (["P2"], [(TR, "            guard run.start < end else { continue }\n",
                                       "")]),
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
    "window-start-only": (["P5"], [
        (TR, "word.start < window.to && max(word.end, word.start + 1) > window.from",
         "word.start >= window.from && word.start < window.to")]),
    "window-no-clamp": (["P4"], [
        (TR, "        let lower = max(from ?? job.start, job.start)\n"
             "        let upper = min(to ?? clipEnd, clipEnd)\n",
         "        let lower = from ?? job.start\n"
         "        let upper = to ?? clipEnd\n")]),
    "window-equal-allowed": (["P4"], [
        (TR, "if let from, let to, to <= from {", "if let from, let to, to < from {")]),
    "window-outside-allowed": (["P4"], [
        (TR, "        guard lower < upper else {\n"
             "            throw WindowError.outside(\n"
             "                from: from, to: to, clip: job.clip, start: job.start, end: clipEnd)\n"
             "        }\n", "")]),
    "no-recognition-pad": (["P6"], [
        (TR, "let pad = Ticks((recognitionPadSeconds * Double(ReelTime.perSecond) / speed)"
             ".rounded(.up))",
         "let pad: Ticks = 0")]),
    "device-stamp-ignored": (["P7"], [
        (DC, "        guard file.stamp == stamp else { return nil }\n", "")]),
    "device-stamp-source-only": (["P7"], [
        (DC, "guard file.stamp == stamp else { return nil }",
         "guard file.stamp.source == stamp.source else { return nil }")]),
    "device-overlap-hit": (["P7"], [
        (DC, "return self.sourceIn <= sourceIn && end <= ownEnd",
         "return sourceIn < ownEnd && end > self.sourceIn")]),
    "device-no-prune": (["P7"], [
        (DC, "let kept = file.runs.filter { !heard.covers(sourceIn: $0.sourceIn, "
             "sourceLength: $0.sourceLength) }",
         "let kept = file.runs")]),
    "device-no-read": (["P8"], [
        (DC, "let hit = lookup(run, media: run.media, stamp: stamp, in: cacheDir)",
         "let hit = Optional<Heard>.none")]),
    "device-cancelled-stores": (["P8"], [
        (DC, "        guard !cancelled() else { return (heard, false) }\n", "")]),
    "device-no-restamp": (["P8"], [
        (DC, "        guard currentStamp(media, url: run.source, language: language) == stamp "
             "else { return (heard, false) }\n", "")]),
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


def grid(session):
    """(on_grid, snap) for the session's canvas rate: whether a tick is a
    frame boundary, and the frame boundary nearest it (a fixture's expected
    snapped value, which TR-13's sentences name)."""
    num, den = session.project()["canvas"]["fps"]
    per = 600_000 * den

    def on_grid(ticks):
        return ticks * num % per == 0

    def snap(ticks):
        frames = (2 * ticks * num + per) // (2 * per)
        return frames * per // num
    return on_grid, snap


def overlaps(word, lo, hi):
    """TR-13's overlap rule: a word with no length belongs when lo <= start < hi."""
    return word["start"] < hi and max(word["end"], word["start"] + 1) > lo


def device_dir(session):
    return os.path.join(session.path, "cache", "device-transcripts")


def device_files(session):
    """The names in the package's `cache/device-transcripts/` (TR-14)."""
    try:
        return sorted(os.listdir(device_dir(session)))
    except OSError:
        return []


def device_file(session, media, language):
    """The package's cached on-device file for (media, language), parsed, or
    None when it is not there or does not parse."""
    path = os.path.join(device_dir(session), f"{media}-{language}.json")
    try:
        with open(path) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


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
                return (not complaints and keys == ["clip", "from", "language", "project", "to"]
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

            def g6():
                session, clip = state.get("g1"), state.get("g1_clip")
                if session is None or clip is None:
                    return False, "G1's session is not available"
                on_grid, _ = grid(session)
                bounds = [600000, 1200000, 1800000, 360000, 0, 5 * SEC]
                off = [b for b in bounds if not on_grid(b)]
                if off:
                    return False, f"fixture bounds {off} are not on the canvas's frame grid"
                every = {w[0]: w for w in state["g1_words"]}
                mark = aai_requests()
                before = session.op("get_project")
                middle = session.op("get_transcript", clip=clip, **{"from": 600000, "to": 1200000})
                tail = session.op("get_transcript", clip=clip, **{"from": 1800000})
                head = session.op("get_transcript", clip=clip, to=360000)
                after = session.op("get_project")
                sent = aai_requests() - mark
                want_middle = [every["Hello"], every["there"], every["everyone"]]
                want_tail = [every["welcome"], every["back"]]
                straddle = (every["Hello"][1] < 600000 < every["Hello"][2]
                            and every["everyone"][1] < 1200000 < every["everyone"][2])
                note = f"No words were heard in clip {clip} between 0 and 360000 ticks."
                got_middle = triples(middle.get("words") or [])
                got_tail = triples(tail.get("words") or [])
                return (got_middle == want_middle and straddle
                        and (middle.get("from"), middle.get("to")) == (600000, 1200000)
                        and middle.get("count") == 3
                        and got_tail == want_tail
                        and (tail.get("from"), tail.get("to")) == (1800000, 3000000)
                        and tail.get("count") == 2
                        and head.get("count") == 0 and head.get("words") == []
                        and (head.get("from"), head.get("to")) == (0, 360000)
                        and head.get("note") == note
                        and before == after and sent == 0,
                        f"[600000, 1200000) → {got_middle} (from {middle.get('from')}, to "
                        f"{middle.get('to')}, count {middle.get('count')}), edges straddled "
                        f"{straddle}; from 1800000 → {got_tail} (to {tail.get('to')}); to 360000 → "
                        f"count {head.get('count')}, note {head.get('note')!r}; get_project "
                        f"unchanged {before == after}; AssemblyAI requests {sent}")
            run("G6", g6)

            def g7():
                session = cloud.Session(app, "transcript-G7")
                try:
                    media = session.media_of(str(SPEECH))
                    clip = session.add(media, at=0, duration=5 * SEC)
                    on_grid, snap = grid(session)
                    bounds = [600000, 1200000, 3600000, 0, 5 * SEC]
                    off = [b for b in bounds if not on_grid(b)]
                    if off:
                        return False, f"fixture bounds {off} are not on the canvas's frame grid"
                    lo, hi = snap(600001), snap(605000)

                    def empty(f, to):
                        return (f"get_transcript: to must be after from: the window from {f} to "
                                f"{to} ticks (both snapped to frames) is empty.")

                    def outside(bounds_):
                        return (f"get_transcript: The window {bounds_} is outside clip {clip}, "
                                f"which plays from 0 to {5 * SEC} ticks.")
                    cases = [
                        ({"from": 600000, "to": 600000}, empty(600000, 600000)),
                        ({"from": 1200000, "to": 600000}, empty(1200000, 600000)),
                        ({"from": 600001, "to": 605000}, empty(lo, hi)),
                        ({"from": 3600000}, outside("from 3600000")),
                        ({"to": 0}, outside("to 0")),
                        ({"from": "soon"},
                         "get_transcript: from must be a time in ticks (600000 per second)."),
                        ({"from": 600000, "to": 600000, "language": "xx-notalanguage"},
                         empty(600000, 600000)),
                    ]
                    wrong = []
                    for arguments, want in cases:
                        got = session.error("get_transcript", clip=clip, **arguments)
                        if got != want:
                            wrong.append(f"{arguments} → {got!r}, want {want!r}")
                    return (not wrong and lo == hi,
                            f"{len(cases) - len(wrong)}/{len(cases)} refusals by their sentence; "
                            f"(600001, 605000) snapped to ({lo}, {hi})"
                            + ("" if not wrong else " — " + "; ".join(wrong)))
                finally:
                    close(session)
            run("G7", g7)

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
                    state["g5_words"] = got
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

            def g8():
                if state.get("no_device"):
                    return None, f"G5 was a host skip: {state['no_device'][:160]!r}"
                whole = state.get("g5_words")
                fox = next((w for w in whole or [] if normalized(w.get("text", "")) == "fox"),
                           None)
                if fox is None:
                    return False, "G5's words are not available"
                session = cloud.Session(app, "transcript-G8")
                try:
                    media = session.media_of(str(SPEECH))
                    clip = session.add(media, at=0)
                    # "fox"'s raw recogniser times widened outward to whole
                    # frames, so a word shorter than a frame cannot snap to an
                    # empty window and fail as a refusal.
                    num, den = session.project()["canvas"]["fps"]
                    per = 600_000 * den
                    first = fox["start"] * num // per
                    last = max(-(-fox["end"] * num // per), first + 1)
                    mark = aai_requests()
                    answer = session.op("get_transcript", clip=clip,
                                        **{"from": first * per // num, "to": last * per // num})
                    sent = aai_requests() - mark
                    got = answer.get("words") or []
                    spoken = [normalized(w.get("text", "")) for w in got]
                    lo, hi = answer.get("from"), answer.get("to")
                    inside = (isinstance(lo, int) and isinstance(hi, int)
                              and all(overlaps(w, lo, hi) for w in got))
                    return (answer.get("engine") == "apple" and "fox" in spoken and inside
                            and answer.get("count") == len(got) and len(got) < len(whole)
                            and sent == 0,
                            f"fox at [{fox['start']}, {fox['end']}) in G5; window echoed [{lo}, "
                            f"{hi}); engine {answer.get('engine')}; {len(got)} words {spoken} "
                            f"against G5's {len(whole)}; every word overlaps {inside}; "
                            f"AssemblyAI requests {sent}")
                finally:
                    close(session)
            run("G8", g8)

            def g9():
                if state.get("no_device"):
                    return None, f"G5 was a host skip: {state['no_device'][:160]!r}"
                copy = WORK / f"speech-G9-{os.getpid()}.mov"
                shutil.copy2(SPEECH, copy)
                session = None
                try:
                    session = cloud.Session(app, "transcript-G9")
                    media = session.media_of(str(copy))
                    clip = session.add(media, at=0)
                    problems = []
                    mark = aai_requests()

                    def call(**window):
                        began = time.monotonic()
                        answer = session.op("get_transcript", clip=clip, **window)
                        return answer, time.monotonic() - began
                    one, first_s = call()
                    language = one.get("language")
                    stored = device_file(session, media, language) or {}
                    if one.get("engine") != "apple" or one.get("cached") is not False:
                        problems.append(f"call 1 engine {one.get('engine')}, cached "
                                        f"{one.get('cached')}")
                    if len(stored.get("runs") or []) != 1:
                        problems.append(f"call 1 left {len(stored.get('runs') or [])} runs in "
                                        f"{device_files(session)}")
                    two, second_s = call()
                    if two.get("cached") is not True or two.get("words") != one.get("words"):
                        problems.append(f"call 2 cached {two.get('cached')}, the same words "
                                        f"{two.get('words') == one.get('words')}")
                    planted = False
                    if stored.get("runs") and stored["runs"][0].get("words"):
                        stored["runs"][0]["words"][0]["text"] = "planted"
                        path = os.path.join(device_dir(session), f"{media}-{language}.json")
                        with open(path, "w") as handle:
                            json.dump(stored, handle, sort_keys=True)
                        planted = True
                    three, _ = call()
                    texts = [w.get("text") for w in three.get("words") or []]
                    if not planted or three.get("cached") is not True or "planted" not in texts:
                        problems.append(f"planted {planted}; call 3 cached {three.get('cached')}, "
                                        f"words {texts[:6]}")
                    # A window on one word, widened outward to whole frames.
                    words3 = three.get("words") or []
                    target = words3[len(words3) // 2] if words3 else None
                    windowed = None
                    if target is not None:
                        num, den = session.project()["canvas"]["fps"]
                        per = 600_000 * den
                        lo_f = target["start"] * num // per
                        hi_f = max(-(-target["end"] * num // per), lo_f + 1)
                        windowed, _ = call(**{"from": lo_f * per // num, "to": hi_f * per // num})
                        lo, hi = windowed.get("from"), windowed.get("to")
                        want = [w for w in words3 if overlaps(w, lo, hi)]
                        runs_now = len((device_file(session, media, language) or {}).get("runs")
                                       or [])
                        if (windowed.get("cached") is not True
                                or windowed.get("words") != want or runs_now != 1):
                            problems.append(f"window [{lo}, {hi}) cached {windowed.get('cached')}, "
                                            f"call 3's words {windowed.get('words') == want}, "
                                            f"{runs_now} runs")
                    else:
                        problems.append("call 3 answered no word to window on")
                    before = (stored.get("stamp") or {}).get("source", {}).get("modified")
                    moved = os.stat(copy).st_mtime + 10
                    os.utime(copy, (moved, moved))
                    four, _ = call()
                    after = ((device_file(session, media, language) or {}).get("stamp") or {}) \
                        .get("source", {}).get("modified")
                    texts4 = [w.get("text") for w in four.get("words") or []]
                    if (four.get("cached") is not False or "planted" in texts4
                            or before is None or after == before):
                        problems.append(f"after the mtime moved: cached {four.get('cached')}, "
                                        f"planted {'planted' in texts4}, modified {before} → "
                                        f"{after}")
                    sent = aai_requests() - mark
                    if sent:
                        problems.append(f"AssemblyAI requests {sent}")
                    return not problems, (
                        f"language {language!r}; call 1 {first_s:.2f} s (cached "
                        f"{one.get('cached')}), call 2 {second_s:.2f} s (cached "
                        f"{two.get('cached')}); planted answered {'planted' in texts}; window "
                        f"cached {(windowed or {}).get('cached')}; after the mtime moved cached "
                        f"{four.get('cached')}, modified {before} → {after}"
                        + ("" if not problems else " — " + "; ".join(problems)))
                finally:
                    if session is not None:
                        close(session)
                        shutil.rmtree(session.path, ignore_errors=True)
                        state.setdefault("made", []).append(session.path)
                    with contextlib.suppress(OSError):
                        os.remove(copy)
            run("G9", g9)

            def g10():
                if state.get("no_device"):
                    return None, f"G5 was a host skip: {state['no_device'][:160]!r}"
                session = cloud.Session(app, "transcript-G10")
                try:
                    media = session.media_of(str(SPEECH))
                    clip = session.add(media, at=0)
                    placed = session.clip(clip)
                    _, snap = grid(session)
                    window = {"from": snap(SEC), "to": snap(2 * SEC)}
                    problems = []
                    first = session.op("get_transcript", clip=clip, **window)
                    language = first.get("language")
                    runs1 = (device_file(session, media, language) or {}).get("runs") or []
                    if (first.get("cached") is not False or len(runs1) != 1
                            or not runs1[0].get("source_length", 0) < placed["duration"]):
                        problems.append(f"windowed call cached {first.get('cached')}, runs "
                                        f"{[(r.get('source_in'), r.get('source_length')) for r in runs1]}"
                                        f" against the clip's {placed['duration']}")
                    again = session.op("get_transcript", clip=clip, **window)
                    if again.get("cached") is not True:
                        problems.append(f"the same window cached {again.get('cached')}")
                    whole = session.op("get_transcript", clip=clip)
                    runs2 = (device_file(session, media, language) or {}).get("runs") or []
                    if whole.get("cached") is not False or len(runs2) != 1:
                        problems.append(f"the whole clip cached {whole.get('cached')}, "
                                        f"{len(runs2)} runs")
                    return not problems, (
                        f"window [{window['from']}, {window['to']}) → cached "
                        f"{first.get('cached')}, run lengths "
                        f"{[r.get('source_length') for r in runs1]} (clip {placed['duration']}); "
                        f"again cached {again.get('cached')}; whole clip cached "
                        f"{whole.get('cached')}, then {len(runs2)} run(s) of lengths "
                        f"{[r.get('source_length') for r in runs2]}"
                        + ("" if not problems else " — " + "; ".join(problems)))
                finally:
                    close(session)
                    shutil.rmtree(session.path, ignore_errors=True)
                    state.setdefault("made", []).append(session.path)
            run("G10", g10)

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
                    stored = device_files(session)
                    if stored:
                        problems.append(f"cache/device-transcripts/ holds {stored} after Stop")
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
            # The app's background media passes (speech, sync) can write into
            # G9's and G10's packages after their close, so they are removed
            # again once the instance has stopped and nothing can write.
            for path in state.get("made", []):
                shutil.rmtree(path, ignore_errors=True)
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
    needs = {"G3": "G2", "A1": "G1", "A2": "A1", "A3": "G5", "G6": "G1", "G8": "G5",
             "G9": "G5", "G10": "G5"}
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
