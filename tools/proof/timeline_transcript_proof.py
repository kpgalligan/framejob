#!/usr/bin/env python3
"""Road map "creator-jobs" TX1 (spec §11 TX-10…TX-14): `get_timeline_transcript`,
the plan's nested `path` and `origin`, and the whole-file fill.

    python3 tools/proof/timeline_transcript_proof.py [--only IDS]
    python3 tools/proof/timeline_transcript_proof.py --mutant NAME
    python3 tools/proof/timeline_transcript_proof.py --mutants

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The one app
launch (`assistant_session_proof.App`) is given a 0700 `-RCSecretFolder` holding
the dummy `proof-key` for both keys, `-RCAssemblyAIEndpoint` at
`assemblyai_fake.py` (`cloud_captions_probe.Fake`) and `RC_ASSISTANT_BASE_URL`
at `anthropic_fake.py` (`assistant_session_proof.Fake`), as `transcript_proof.py`
does. Fixture media are `say` phrases under `tools/proof/work/timeline_transcript/`;
`media/speech.mov` is host input (P7, P9). Every expected word comes from the
package's own `cache/device-transcripts/` file (or the fake's served words),
each start moved by `word_onsets.moved` over the package's voice and peaks
caches (TX1b, spec §11 TX-15), placed here by R6-10's arithmetic: nothing is
recognised twice to make an oracle. Every import but P12's waits for its
media's voice and peaks caches (`word_onsets.wait_voice`) before any read.

Probe rows (`timeline_transcript_probe.swift`, built through `swift_build.build()`
over `app/Sources` or a mutant's copy): T0 builds, T1…T11 as its header says.

App rows (the app `proof_app` chooses; `RC_PROOF_APP=release` for the record):
  G0  no `Frame Job: ` line; the tool takes exactly from, language, project,
      to and tracks, none required.
  G1  refusals by exact sentence: an empty window, a window past the timeline,
      an unknown track, a misspelt language.
  P1  tracks 1 and 2: clip A at 0 on track 1, clip B at 1 s on track 2, clip C
      at 23 s on track 1 (in 3 s, 2 s long): every word, in order (start, end, front
      track first, source order), equals the cache files' words placed by
      R6-10; engine apple; each word editable with its clip, track and media.
  P10 each heard media's cache file holds ONE run, from 0 for the media's
      whole duration.
  P11 a second call answers the same words and touches no cache file.
  P11b P1's clip C trimmed 3 s outward and a second clip of C's file placed:
      the words of both, and no cache file touched.
  P2  a muted track's clip of A gives no words; its twin on track 1 does.
  P3  a clip of A nested: its words at the nest clip's start plus inner time,
      not editable with TX-11's nest sentence, `id.nest_path` the nest clip.
  P3b the nest clip duplicated: the words twice, distinct ids.
  P3c the duplicate trimmed shorter than its nest: only the words it plays.
  P3d a clip of B placed twice: k 0 then 1 for each source tick; after a
      ripple delete before both, the same ids one second earlier.
  P3e a nested clip with audio off under `no_words`, named "clip N in nest M".
  P4  two clips joined by a transition: a word under it not editable with
      the transition sentence; one 3 s away editable.
  P5  a locked track's words not editable with the lock sentence.
  P6  a ramped clip's words (`add_speed_ramp`) equal `get_transcript`'s.
  P7  a reversed speech.mov clip under `no_words` with the gate's sentence.
  P8  A and a copy of A's file on two tracks over the same 7 s: the same-speech
      note naming both clips.
  P9  speech.mov transcribed through the fake (`transcribe {engine:
      assemblyai, place: false}`): engine assemblyai, `fillers_reported` true,
      the words `cloud_captions_proof.mapped`'s, no request during the call and
      no device-transcripts file.
  P12 the assistant's Stop during a fill over `long_fixture`'s ~3600 s WAV:
      "The transcription was cancelled.", nothing stored.
  P13 paging: two clips of a 600 s file: pages of at most 2000 words with
      `next_from` on the frame grid, followed to the end, together holding
      every word (a word repeated across a page edge with the same id).

Mutants (`--mutant NAME`, or all with `--mutants`): each anchor occurs once;
a mutant is caught when every row it names fails.
  no-heard          `isAudible`'s guard removed (T2)
  track-tie         the order's track term reversed (T1)
  no-nest-offset    the nested shift removed (T3, T4)
  path-top-level    `plan.rs` writes `path`/`origin` on every segment, in a
                    copy of `core/` (C1: `cargo test --test plan_instances`)
  no-k              k always 0 (T5)
  played-span       the fill reads the played length, not the file (P10,
                    P11b; an app built from a tree copy)
  stop-all          a release drops every owner's want (T11)
  cancel-sticks     a run cancelled and wanted again before it unwound keeps
                    `.cancelled` (T11)
  page-off-by-one   a page holds 1999 words (T10)

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
import swift_build  # noqa: E402
import bounded  # noqa: E402 — on swift_build's path
import word_onsets  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/timeline_transcript"
PROBE = ROOT / "tools/proof/timeline_transcript_probe.swift"
SPEECH = ROOT / "tools/proof/media/speech.mov"
PROBE_ROWS = ["T0", "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9", "T10", "T11"]
APP_ROWS = ["G0", "G1", "P1", "P10", "P11", "P11b", "P2", "P3", "P3b", "P3c", "P3d", "P3e",
            "P4", "P5", "P6", "P7", "P8", "P9", "P12", "P13"]
CORE_ROWS = ["C1"]
ROWS = PROBE_ROWS + APP_ROWS + CORE_ROWS
SEC = 600_000
KEY = "proof-key"
TOOL = "get_timeline_transcript"
CANCELLED = "The transcription was cancelled."
NEST_WHY = "Inside nest {}: open it (⌘↓) to cut its words."
WALL_WHY = "Under a transition: a cut here would leave one clip's tail under its neighbour."
LOCK_WHY = ("Track {} is locked: a cut would leave these words in place and move everything "
            "after them.")

TT = "TimelineTranscript.swift"
TF = "TranscriptFill.swift"
TH = "AgentServer+TimelineTranscript.swift"
MUTANTS = {
    "no-heard": ("probe", ["T2"], [
        (TT, "                guard SilenceDetector.isAudible(track.ramps, over: span) else "
             "{ continue }\n", "")]),
    "track-tie": ("probe", ["T1"], [
        (TT, "($0.start, $0.end, -$0.trackIndex, $0.order, $0.instance)",
         "($0.start, $0.end, $0.trackIndex, $0.order, $0.instance)"),
        (TT, "< ($1.start, $1.end, -$1.trackIndex, $1.order, $1.instance)",
         "< ($1.start, $1.end, $1.trackIndex, $1.order, $1.instance)")]),
    "no-nest-offset": ("probe", ["T3", "T4"], [
        (TT, "                    start += shift\n                    end += shift\n", "")]),
    "path-top-level": ("core", ["C1"], [
        ("plan.rs", "(voice.stages.len() > 1, voice.stages.first())",
         "(!voice.stages.is_empty(), voice.stages.first())")]),
    "no-k": ("probe", ["T5"], [(TT, "let k = counts[key, default: 0]", "let k = 0")]),
    "played-span": ("app", ["P10", "P11b"], [
        (TH, "                items.append(item)\n",
         "                items.append(TranscriptFill.Item(media: item.media, url: item.url, "
         "name: item.name, duration: context.instances.first(where: { $0.job.media == id })?"
         ".job.sourceLength ?? item.duration, stamp: item.stamp, cacheDir: item.cacheDir, "
         "language: item.language, record: item.record))\n")]),
    "stop-all": ("probe", ["T11"], [
        (TF, "        owners[owner] = nil\n        reconcileLocked()\n",
         "        owners = [:]\n        reconcileLocked()\n")]),
    "cancel-sticks": ("probe", ["T11"], [
        (TF, "outcomes[next] = outcome == .cancelled && rewanted ? nil : outcome",
         "outcomes[next] = outcome")]),
    "page-off-by-one": ("probe", ["T10"], [
        (TT, "var count = pageLimit\n", "var count = pageLimit - 1\n")]),
}

PHRASES = {
    "A": "Every morning the harbour fills with small boats and loud gulls, and the fishermen "
         "call to each other across the water.",
    "B": "Please write the totals in the third column of the sheet before the meeting on "
         "Thursday afternoon.",
    "C": "Turn left at the old church, then follow the river for a mile until you reach the "
         "stone bridge.",
}


# --------------------------------------------------------------------------
# Fixtures


def say(name, text):
    path = WORK / f"{name}.wav"
    if not path.exists():
        WORK.mkdir(parents=True, exist_ok=True)
        subprocess.run(["say", "-o", str(path), "--file-format=WAVE", "--data-format=LEI16@16000",
                        text], check=True, timeout=120)
    return path


def seconds_of(path):
    with wave.open(str(path), "rb") as source:
        return source.getnframes() / source.getframerate()


def fixtures():
    out = {name: say(name, text) for name, text in PHRASES.items()}
    copy = WORK / "A-copy.wav"
    if not copy.exists():
        shutil.copyfile(out["A"], copy)
    out["A2"] = copy
    page = WORK / "page.wav"
    if not page.exists():
        bodies = []
        for name in ("A", "B", "C"):
            with wave.open(str(out[name]), "rb") as source:
                bodies.append(source.readframes(source.getnframes()))
        gap = b"\0\0" * 8000
        body, index = bytearray(), 0
        while len(body) < 600 * 16000 * 2:
            body += bodies[index % 3] + gap
            index += 1
        with wave.open(str(page), "wb") as dest:
            dest.setnchannels(1)
            dest.setsampwidth(2)
            dest.setframerate(16000)
            dest.writeframes(bytes(body[:600 * 16000 * 2]))
    out["page"] = page
    return out


# --------------------------------------------------------------------------
# Probe, core and mutation


def mutate_tree(name, dest):
    """A copy of `app/Sources` with the mutant's edits; why, on a bad anchor."""
    shutil.copytree(ROOT / "app/Sources", dest)
    return apply_edits(MUTANTS[name][2], dest)


def apply_edits(edits, folder):
    for file, before, after in edits:
        path = Path(folder) / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe_rows(results, wanted, mutant=None):
    here = WORK / (f"mutant-{mutant}" if mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = ROOT / "app/Sources"
    if mutant:
        why = mutate_tree(mutant, here / "Sources")
        if why:
            return why
        sources = here / "Sources"
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "timeline-transcript-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        results.score("T0", False, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8])))
        return None
    results.score("T0", True, f"built from {sources}")
    speech = say("A", PHRASES["A"])
    ticks = round(seconds_of(speech) * SEC)
    ran = bounded.run([str(binary), str(here), str(speech), str(ticks)], 600, cwd=str(here))
    (here / "stderr.txt").write_text(ran["stderr"])
    try:
        answers = json.loads(ran["stdout"])["rows"]
    except (ValueError, KeyError):
        answers = []
    for row in wanted:
        if row == "T0":
            continue
        answer = next((a for a in answers if a.get("id") == row), None)
        if answer is None:
            results.score(row, False, f"no row (exit {ran['rc']}): {ran['stderr'][-300:]}")
        elif "skip" in answer:
            results.score(row, None, answer["skip"])
        else:
            results.score(row, answer.get("pass") is True, answer.get("detail", ""))
    return None


def core_row(results, mutant=None):
    """C1: `cargo test --release --test plan_instances`, in the tree or in a
    copy of `core/` beside a link to `graphic/` with the mutant's edit."""
    if mutant is None:
        folder = ROOT / "core"
    else:
        base = WORK / "mutant-core"
        shutil.rmtree(base, ignore_errors=True)
        base.mkdir(parents=True)
        os.symlink(ROOT / "graphic", base / "graphic")
        subprocess.run(["cp", "-cR", str(ROOT / "core"), str(base / "core")], check=True)
        why = apply_edits(MUTANTS[mutant][2], base / "core/src")
        if why:
            return why
        folder = base / "core"
    ran = bounded.run(["cargo", "test", "--release", "--test", "plan_instances"], 900,
                      cwd=str(folder))
    tail = (ran["stdout"] + ran["stderr"]).strip().splitlines()[-3:]
    results.score("C1", ran["rc"] == 0, f"cargo test plan_instances rc {ran['rc']}: {tail}")
    return None


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


def secret_folder():
    folder = WORK / "secrets"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    for name in ("anthropic-key", "assemblyai-key"):
        descriptor = os.open(folder / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write(KEY + "\n")
    return str(folder)


def device_dir(session):
    return os.path.join(session.path, "cache", "device-transcripts")


def device_state(session):
    """{name: (mtime_ns, size)} of every device-transcripts file."""
    out = {}
    folder = device_dir(session)
    for name in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
        info = os.stat(os.path.join(folder, name))
        out[name] = (info.st_mtime_ns, info.st_size)
    return out


def device_file(session, media, language):
    try:
        with open(os.path.join(device_dir(session), f"{media}-{language}.json")) as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return None


def place(clip, offset, words, moved=None):
    """R6-10 at speed 1 for a clip whose words land `offset` ticks later (a
    nest clip's start plus the inner clip's): `[(text, start, end, source,
    order)]` for each source word whose MOVED start (`moved`, one per word;
    the stored start without it) is in the clip's window (TX-16); `source`
    stays the stored tick, the identity's (TX-17), and the end the stored
    one."""
    source_in = clip["source"].get("in", 0)
    out = []
    for order, word in enumerate(words):
        src = moved[order] if moved is not None else word["start"]
        if not source_in <= src < source_in + clip["duration"]:
            continue

        def at(tick):
            return offset + clip["start"] + min(max(tick - source_in, 0), clip["duration"])
        out.append((word["text"], at(src), at(max(word["start"], word["end"])), word["start"],
                    order))
    return out


def expected(session, answer, heard):
    """The oracle: `heard` is [(clip, track id, offset)] for top-level clips;
    each media's words from its cache file's one run, ordered as TX-10."""
    project = session.project()
    index = {t["id"]: i for i, t in enumerate(project["tracks"])}
    languages = {m["media"]: m.get("language") for m in answer.get("media", [])}
    rows = []
    for number, (clip, track, offset) in enumerate(heard):
        media = clip["source"]["media"]
        stored = device_file(session, media, languages.get(media))
        words = stored["runs"][0]["words"] if stored and stored.get("runs") else []
        moved = word_onsets.moved(words, *word_onsets.load(session.path, media))
        for text, start, end, src, order in place(clip, offset, words, moved):
            rows.append(((start, end, -index[track], order, number),
                         (text, start, end, clip["id"], track, media)))
    rows.sort(key=lambda r: r[0])
    return [r[1] for r in rows]


def got_rows(answer):
    return [(w["text"], w["start"], w["end"], w["clip"], w["track"], w["media"])
            for w in answer.get("words", [])]


def app_rows(results, wanted, app_path, files):
    import assistant_session_proof as sp
    import cloud_captions_probe
    import cloud_captions_proof as cloud

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
        try:
            session.op("close_project", discard=True)
        except Exception:  # noqa: BLE001 — housekeeping
            pass

    stand_in = app = None
    with contextlib.closing(lock), cloud_captions_probe.Fake("timeline-transcript") as aai:
        try:
            stand_in = sp.Fake(str(WORK / "anthropic-fake"))
            app = sp.App("timeline-transcript", app_path,
                         ["-RCSecretFolder", secret_folder(), "-RCAssemblyAIEndpoint", aai.base],
                         stand_in.base)
            app.connect()

            class Voiced(cloud.Session):
                """Each import waits for its voice and peaks caches before any
                read (TX1b, spec §11 TX-18)."""

                def media_of(self, path):
                    media = super().media_of(path)
                    word_onsets.wait_voice(self.path, media)
                    return media

            def session_of(name):
                return Voiced(app, f"tt-{name}")

            def call(session, **arguments):
                return session.op(TOOL, **arguments)

            def tracks(session):
                return [t["id"] for t in session.project()["tracks"]]

            def new_track(session):
                session.op("add_track")
                return tracks(session)[-1]

            def clip_of(session, clip):
                return {c["id"]: c for c in session.project()["clips"]}[clip]

            def g0():
                complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
                schema = app.mcp.schemas().get(TOOL, {}).get("inputSchema", {})
                keys = sorted(schema.get("properties", {}))
                required = schema.get("required", [])
                return (not complaints and keys == ["from", "language", "project", "to", "tracks"]
                        and not required,
                        f"parity lines {complaints[:3]}; properties {keys}, required {required}")
            run("G0", g0)

            # P1, P10, P11, P11b, P2 share one project.
            def p1():
                s = session_of("p1")
                state["p1"] = s
                a, b, c = (s.media_of(str(files[n])) for n in ("A", "B", "C"))
                state["media"] = (a, b, c)
                t1 = tracks(s)[0]
                t2 = new_track(s)
                ca = s.add(a, at=0, track=t1)
                cb = s.add(b, at=SEC, track=t2)
                cc = s.add(c, at=20 * SEC, track=t1)
                s.op("trim_start", clip=cc, to=23 * SEC)
                s.op("trim_end", clip=cc, to=clip_of(s, cc)["start"] + 2 * SEC)
                state["p1_clips"] = (ca, cb, cc, t1, t2)
                answer = call(s)
                state["p1_answer"] = answer
                heard = [(clip_of(s, ca), t1, 0), (clip_of(s, cb), t2, 0), (clip_of(s, cc), t1, 0)]
                want = expected(s, answer, heard)
                got = got_rows(answer)
                engines = {w["engine"] for w in answer.get("words", [])}
                editable = all(w["editable"] and "why" not in w for w in answer.get("words", []))
                return (answer.get("ok") is True and got == want and len(got) > 20
                        and engines == {"apple"} and editable and answer.get("count") == len(got)
                        and "truncated" not in answer,
                        f"{len(got)} words, want {len(want)}; first {got[:3]}; engines {engines}; "
                        f"editable {editable}; media {answer.get('media')}")
            run("P1", p1)

            def p10():
                s = state.get("p1")
                if s is None:
                    return False, "P1 did not run"
                project = s.project()
                durations = {m["id"]: m["duration"] for m in project["media"]}
                languages = {m["media"]: m.get("language") for m in state["p1_answer"]["media"]}
                problems = []
                for media in state["media"]:
                    stored = device_file(s, media, languages.get(media))
                    runs = (stored or {}).get("runs", [])
                    if len(runs) != 1 or runs[0]["source_in"] != 0 \
                            or runs[0]["source_length"] != durations[media]:
                        problems.append(f"media {media}: {[(r['source_in'], r['source_length']) for r in runs]} "
                                        f"against duration {durations[media]}")
                return not problems, "; ".join(problems) or \
                    f"one whole-file run each for media {list(state['media'])}"
            run("P10", p10)

            def p11():
                s = state.get("p1")
                if s is None:
                    return False, "P1 did not run"
                before = device_state(s)
                answer = call(s)
                after = device_state(s)
                return (got_rows(answer) == got_rows(state["p1_answer"]) and before == after
                        and len(before) == 3,
                        f"same words {got_rows(answer) == got_rows(state['p1_answer'])}; cache "
                        f"files untouched {before == after} ({len(before)} files)")
            run("P11", p11)

            def p11b():
                s = state.get("p1")
                if s is None:
                    return False, "P1 did not run"
                ca, cb, cc, t1, t2 = state["p1_clips"]
                start = clip_of(s, cc)["start"]
                s.op("trim_start", clip=cc, to=start - 3 * SEC)
                c2 = s.add(state["media"][2], at=40 * SEC, track=t1)
                before = device_state(s)
                answer = call(s)
                after = device_state(s)
                heard = [(clip_of(s, ca), t1, 0), (clip_of(s, cb), t2, 0),
                         (clip_of(s, cc), t1, 0), (clip_of(s, c2), t1, 0)]
                want = expected(s, answer, heard)
                return (got_rows(answer) == want and before == after,
                        f"{len(got_rows(answer))} words, want {len(want)}; cache files untouched "
                        f"{before == after}: {before} → {after}")
            run("P11b", p11b)

            def p2():
                s = state.get("p1")
                if s is None:
                    return False, "P1 did not run"
                a = state["media"][0]
                t1 = state["p1_clips"][3]
                muted = new_track(s)
                s.op("set_track", track=muted, muted=True)
                hidden = s.add(a, at=60 * SEC, track=muted)
                twin = s.add(a, at=80 * SEC, track=t1)
                answer = call(s)
                clips = {w["clip"] for w in answer.get("words", [])}
                return (hidden not in clips and twin in clips,
                        f"muted clip {hidden} in words {hidden in clips}; twin {twin} "
                        f"{twin in clips}")
            run("P2", p2)
            if state.get("p1") is not None:
                close(state["p1"])

            def nest_project():
                s = session_of("p3")
                state["p3"] = s
                a = s.media_of(str(files["A"]))
                t1 = tracks(s)[0]
                inner = s.add(a, at=SEC, track=t1)
                s.op("nest", clips=[inner], name="Intro")
                project = s.project()
                nest_clip = next(c for c in project["clips"] if c["source"]["kind"] == "nest")
                state["p3_ids"] = (a, t1, inner, nest_clip["id"])
                return s

            def p3():
                s = nest_project()
                a, t1, inner, nested = state["p3_ids"]
                project = s.project()
                nest_clip = clip_of(s, nested)
                inner_clip = next(c for n in project["nests"] for c in n["clips"])
                answer = call(s)
                state["p3_answer"] = answer
                heard = [(dict(inner_clip), t1, nest_clip["start"])]
                want = expected(s, answer, heard)
                want = [(text, start, end, inner_clip["id"], t1, media)
                        for text, start, end, _, _, media in want]
                words = answer.get("words", [])
                whys = {w.get("why") for w in words}
                paths = {tuple(w["id"]["nest_path"]) for w in words}
                return (got_rows(answer) == want and len(want) > 5 and whys == {NEST_WHY.format("Intro")}
                        and not any(w["editable"] for w in words) and paths == {(nested,)},
                        f"{len(words)} words, want {len(want)}; why {whys}; nest paths {paths}")
            run("P3", p3)

            def p3b():
                s = state.get("p3")
                if s is None:
                    return False, "P3 did not run"
                a, t1, inner, nested = state["p3_ids"]
                s.op("duplicate", clips=[nested])
                project = s.project()
                copies = [c["id"] for c in project["clips"] if c["source"]["kind"] == "nest"]
                state["p3_copy"] = next(c for c in copies if c != nested)
                answer = call(s)
                words = answer.get("words", [])
                ids = [json.dumps(w["id"], sort_keys=True) for w in words]
                first = len(state["p3_answer"].get("words", []))
                by_path = {}
                for w in words:
                    by_path.setdefault(tuple(w["id"]["nest_path"]), []).append(w["text"])
                return (len(words) == 2 * first and len(set(ids)) == len(ids)
                        and sorted(by_path) == sorted([(nested,), (state["p3_copy"],)])
                        and len(set(map(tuple, by_path.values()))) == 1,
                        f"{len(words)} words from {first}; distinct ids {len(set(ids))}; paths "
                        f"{sorted(by_path)}")
            run("P3b", p3b)

            def p3c():
                s = state.get("p3")
                if s is None or "p3_copy" not in state:
                    return False, "P3b did not run"
                copy = clip_of(s, state["p3_copy"])
                cut = copy["start"] + 2 * SEC
                s.op("trim_end", clip=copy["id"], to=cut)
                answer = call(s)
                mine = [w for w in answer.get("words", [])
                        if w["id"]["nest_path"] == [state["p3_copy"]]]
                return (bool(mine) and all(w["start"] < cut for w in mine)
                        and len(mine) < len(state["p3_answer"].get("words", [])),
                        f"{len(mine)} words in the trimmed copy, every start before {cut}: "
                        f"{all(w['start'] < cut for w in mine)}")
            run("P3c", p3c)
            if state.get("p3") is not None:
                close(state["p3"])

            def p3d():
                s = session_of("p3d")
                try:
                    b = s.media_of(str(files["B"]))
                    t1 = tracks(s)[0]
                    first = s.add(b, at=2 * SEC, track=t1)
                    second = s.add(b, at=20 * SEC, track=t1)
                    before = call(s).get("words", [])
                    s.op("ripple_delete_range", **{"from": 0, "to": SEC})
                    after = call(s).get("words", [])
                    ks = {}
                    for w in before:
                        ks.setdefault(w["clip"], set()).add(w["id"]["k"])
                    same = [w["id"] for w in before if w["clip"] == second]
                    moved = [w["id"] for w in after if w["start"] >= 19 * SEC]
                    shifted = [w["start"] for w in after if w["start"] >= 19 * SEC]
                    return (ks.get(first) == {0} and ks.get(second) == {1} and same == moved
                            and shifted == [w["start"] - SEC for w in before if w["clip"] == second],
                            f"k by clip {ks}; the second clip's ids kept after the ripple "
                            f"{same == moved}")
                finally:
                    close(s)
            run("P3d", p3d)

            def p3e():
                s = session_of("p3e")
                try:
                    b = s.media_of(str(files["B"]))
                    t1 = tracks(s)[0]
                    inner = s.add(b, at=0, track=t1)
                    s.op("set_enabled", clip=inner, audio=False)
                    s.op("nest", clips=[inner], name="Quiet")
                    project = s.project()
                    nested = next(c["id"] for c in project["clips"] if c["source"]["kind"] == "nest")
                    inner_id = next(c["id"] for n in project["nests"] for c in n["clips"])
                    answer = call(s)
                    rows = answer.get("no_words", [])
                    want = [{"clip": inner_id, "nest_path": [nested],
                             "tag": f"clip {inner_id} in nest Quiet",
                             "reason": "its audio is switched off"}]
                    return rows == want and not answer.get("words"), f"no_words {rows}"
                finally:
                    close(s)
            run("P3e", p3e)

            def p4():
                s = session_of("p4")
                try:
                    a, b = s.media_of(str(files["A"])), s.media_of(str(files["B"]))
                    t1 = tracks(s)[0]
                    first = s.add(a, at=0, track=t1)
                    s.op("trim_end", clip=first, to=4 * SEC)
                    second = s.add(b, at=5 * SEC, track=t1)
                    s.op("trim_start", clip=second, to=6 * SEC)
                    s.op("move_clip", clips=[second], delta=-2 * SEC)
                    s.op("add_transition", clip=second, duration=SEC)
                    cut = clip_of(s, second)["start"]
                    words = call(s).get("words", [])
                    under = [w for w in words if w.get("why") == WALL_WHY]
                    far = [w for w in words if abs(w["start"] - cut) > 3 * SEC]
                    return (bool(under) and all(not w["editable"] for w in under)
                            and all(abs(w["start"] - cut) <= 3 * SEC for w in under)
                            and bool(far) and all(w["editable"] for w in far),
                            f"{len(under)} words under the transition at {cut}, "
                            f"{len(far)} far words editable {all(w['editable'] for w in far)}")
                finally:
                    close(s)
            run("P4", p4)

            def p5():
                s = session_of("p5")
                try:
                    c = s.media_of(str(files["C"]))
                    t1 = tracks(s)[0]
                    s.add(c, at=0, track=t1)
                    name = s.project()["tracks"][0]["name"]
                    s.op("set_track", track=t1, locked=True)
                    words = call(s).get("words", [])
                    whys = {w.get("why") for w in words}
                    return (bool(words) and whys == {LOCK_WHY.format(name)}
                            and not any(w["editable"] for w in words), f"why {whys}")
                finally:
                    close(s)
            run("P5", p5)

            def p6():
                s = session_of("p6")
                try:
                    a = s.media_of(str(files["A"]))
                    t1 = tracks(s)[0]
                    clip = s.add(a, at=0, track=t1)
                    s.op("trim_end", clip=clip, to=4 * SEC)
                    s.op("add_speed_ramp", clip=clip, shape="ramp_up", rate=1.5)
                    timeline = call(s).get("words", [])
                    single = s.op("get_transcript", clip=clip).get("words", [])
                    mine = [(w["text"], w["start"], w["end"]) for w in timeline if w["clip"] == clip]
                    theirs = [(w["text"], w["start"], w["end"]) for w in single]
                    return (bool(mine) and mine == theirs
                            and all(w["editable"] for w in timeline),
                            f"{len(mine)} words, get_transcript's {len(theirs)}: equal "
                            f"{mine == theirs}")
                finally:
                    close(s)
            run("P6", p6)

            def p7():
                s = session_of("p7")
                try:
                    media = s.media_of(str(SPEECH))
                    clip = s.add(media, at=0)
                    s.op("set_reversed", clip=clip, reversed=True)
                    rows = call(s).get("no_words", [])
                    want = [{"clip": clip, "nest_path": [], "tag": f"clip {clip}",
                             "reason": "it plays in reverse, so its speech cannot be transcribed"}]
                    return rows == want, f"no_words {rows}"
                finally:
                    close(s)
            run("P7", p7)

            def p8():
                s = session_of("p8")
                try:
                    a, a2 = s.media_of(str(files["A"])), s.media_of(str(files["A2"]))
                    t1 = tracks(s)[0]
                    t2 = new_track(s)
                    one = s.add(a, at=0, track=t1)
                    two = s.add(a2, at=0, track=t2)
                    notes = call(s).get("notes", [])
                    low, high = sorted([one, two])
                    want = (f"Clips {low} and {high} carry the same speech. Mute one, or switch its "
                            "audio off, to read it once.")
                    return want in notes, f"notes {notes}"
                finally:
                    close(s)
            run("P8", p8)

            def p9():
                words = cloud.DISFLUENT_WORDS
                cloud.scenario(aai, disfluent_words=words)
                s = session_of("p9")
                try:
                    media = s.media_of(str(SPEECH))
                    clip = s.add(media, at=0, duration=5 * SEC)
                    s.op("transcribe", engine="assemblyai", place=False)
                    s.save()
                    mark = len(aai.log().get("requests", []))
                    answer = call(s)
                    sent = len(aai.log().get("requests", [])) - mark
                    want = [(w["text"], w["start"], w["end"])
                            for w in cloud.mapped(s.clip(clip), words)]
                    got = [(w["text"], w["start"], w["end"]) for w in answer.get("words", [])]
                    rows = answer.get("media", [])
                    return (got == want and len(rows) == 1 and rows[0].get("engine") == "assemblyai"
                            and rows[0].get("fillers_reported") is True and sent == 0
                            and not device_state(s),
                            f"words equal {got == want} ({len(got)}); media {rows}; requests "
                            f"during the call {sent}; device files {device_state(s)}")
                finally:
                    close(s)
            run("P9", p9)

            def p12():
                import speech_engine_proof
                _, ten, _, _ = speech_engine_proof.make_fixtures()
                long, seconds = sp.long_fixture(ten)
                s = session_of("p12")
                try:
                    s.add(cloud.Session.media_of(s, long), at=0)  # no read: no wait
                    stand_in.scenario([sp.use("toolu_tt", TOOL, {}), sp.say("P12: stopped.")])
                    ok, answer = app.call("assistant_send", project=s.path,
                                          text="Read the timeline (P12).",
                                          stop_after=sp.STOP_AFTER, timeout=sp.WALL_ST)
                    if not ok:
                        return False, f"assistant_send with stop_after refused: {answer}"
                    problems = sp.stopped_turn(answer, TOOL, CANCELLED)
                    if stand_in.log().get("failures"):
                        problems.append(f"failures {stand_in.log()['failures']}")
                    if device_state(s):
                        problems.append(f"device-transcripts holds {device_state(s)} after Stop")
                    return not problems, (f"a {seconds:.0f} s WAV; {sp.brief(answer)}"
                                          + ("" if not problems else " — " + "; ".join(problems)))
                finally:
                    close(s)
            run("P12", p12)

            def p13():
                s = session_of("p13")
                try:
                    page = s.media_of(str(files["page"]))
                    t1 = tracks(s)[0]
                    s.add(page, at=0, track=t1)
                    s.add(page, at=600 * SEC, track=t1)
                    num, den = s.project()["canvas"]["fps"]
                    per = 600_000 * den
                    pages, frm = [], None
                    for _ in range(10):
                        answer = call(s, **({} if frm is None else {"from": frm}))
                        pages.append(answer)
                        if not answer.get("truncated"):
                            break
                        frm = answer["next_from"]
                        if frm * num % per != 0:
                            return False, f"next_from {frm} is off the frame grid"
                    first = pages[0]
                    project = s.project()
                    clips = [c for c in project["clips"]]
                    heard = [(c, t1, 0) for c in clips]
                    want = expected(s, first, heard)
                    seen = {}
                    for answer in pages:
                        for w in answer.get("words", []):
                            seen[json.dumps(w["id"], sort_keys=True)] = (
                                w["text"], w["start"], w["end"], w["clip"], w["track"], w["media"])
                    counts = [a.get("count") for a in pages]
                    return (len(pages) >= 2 and all(c <= 2000 for c in counts)
                            and sorted(seen.values()) == sorted(want) and len(want) > 2000,
                            f"pages {counts} over {len(want)} words; every word seen "
                            f"{sorted(seen.values()) == sorted(want)}")
                finally:
                    close(s)
            run("P13", p13)

            def g1():
                s = session_of("g1")
                try:
                    b = s.media_of(str(files["B"]))
                    s.add(b, at=0)
                    duration = s.project()["clips"][0]["duration"]
                    got = [s.error(TOOL, **{"from": SEC, "to": SEC}),
                           s.error(TOOL, **{"from": 100 * SEC}),
                           s.error(TOOL, tracks=[987654]),
                           s.error(TOOL, language="xx-NOPE")]
                    want = [f"{TOOL}: to must be after from: the window from 600000 to 600000 "
                            "ticks (both snapped to frames) is empty.",
                            f"{TOOL}: The window from 60000000 is outside the timeline, which "
                            f"runs from 0 to {duration} ticks.",
                            f"{TOOL}: No track has id 987654. get_project lists the tracks.",
                            None]
                    ok = all((g or "").endswith(w.split(": ", 1)[1]) for g, w in zip(got[:3], want[:3]))
                    language = got[3] or ""
                    ok = ok and "is not a language speech recognition knows" in language
                    return ok, f"refusals {got}"
                finally:
                    close(s)
            run("G1", g1)
        finally:
            if app is not None:
                app.stop()
            if stand_in is not None:
                stand_in.stop()


def build_mutant_app(name):
    """(app path, None) or (None, why): the tree copied, the mutant's edits
    applied to the copy's app/Sources, `tree_copy.build_app`."""
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
        if "T0" not in probe_wanted:
            probe_wanted = ["T0"] + probe_wanted
        why = probe_rows(results, probe_wanted, mutant if kind == "probe" else None)
        if why:
            return None, why
    if "C1" in wanted:
        why = core_row(results, mutant if kind == "core" else None)
        if why:
            return None, why
    if app_wanted:
        import proof_app
        if not SPEECH.exists():
            for row in app_wanted:
                results.score(row, False, "media/speech.mov is missing (tools/proof/README.md)")
            return results, None
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
        app_rows(results, app_wanted, str(app_path), fixtures())
        for row in app_wanted:
            if row not in results.results and row not in results.skipped:
                results.score(row, False, "not scored")
    return results, None


def report(results, wanted):
    for row in wanted:
        if row in results.skipped:
            print(f"{row} SKIP — host: {results.skipped[row]}")
        elif row in results.results:
            good, detail = results.results[row]
            print(f"{row} {'pass' if good else 'fail'} — {detail}")
    scored = [r for r in wanted if r in results.results]
    passed = sum(1 for r in scored if results.results[r][0])
    print(f"scores: {passed}/{len(scored)}"
          + (f", skipped {', '.join(r for r in wanted if r in results.skipped)}"
             if results.skipped else ""), flush=True)
    return passed == len(scored)


def mutant_run(name):
    kind, named, _ = MUTANTS[name]
    wanted = list(named)
    if kind == "app":
        wanted = ["P1", "P10", "P11", "P11b"]
    results, why = run_rows(wanted, mutant=name)
    if results is None:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    report(results, wanted)
    lost = [r for r in named if r not in results.results]
    if lost:
        print(f"mutant {name}: the control could not be performed — not scored or skipped: "
              f"{', '.join(lost)}")
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
        print("mutants: " + ", ".join(f"{n} {'caught' if c == 0 else 'SURVIVED' if c == 1 else 'NOT PERFORMED'}"
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
    return 0 if report(results, [r for r in ROWS if r in wanted or r == "T0"]) else 1


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
