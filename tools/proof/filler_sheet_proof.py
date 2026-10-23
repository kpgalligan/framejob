#!/usr/bin/env python3
"""Cut by transcript CT-3 (spec §11 TR-7, TR-10): Clip ▸ Remove Filler Words…,
its wash and its commit, the re-transcribe its rows offer, and that
re-transcribe's mirror `transcribe_for_fillers`, withheld from the assistant.

    python3 tools/proof/filler_sheet_proof.py [--mutant NAME] [--only IDS]

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The app rows'
instance is given the dummy key `proof-key` against `assemblyai_fake.py`
(`cloud_captions_proof.Instance`), T4's none at all; the probe presses no
Transcribe button.

Probe rows (`filler_sheet_probe.swift`, copied in as `main.swift` and built with
`swift_build.build()` over `swift_build.app_sources()` of `app/Sources`, or of
a mutant's copy, run once with `media/speech.mov` as its argument under
`tools/proof/work/filler-sheet/<tree|mutant-NAME>/`, killed at a 240 s wall; a
missing `speech.mov` is a scored FAIL):
  S0  the probe builds (a build failure is this row's scored FAIL).
  S1  a document with one clip and a hand-built `Input` holding two separate
      filler runs: the summary is "2 cuts · removes T" from `detect`, Remove is
      enabled, `timeline.candidateSpans == outcome.spans`, no rows.
  S2  presented with a still animator, `applyButton.performClick(nil)` gives
      the clips a twin document gets from `.rippleDeleteRanges` of both spans;
      the undo is "Remove Filler Words" and one undo restores;
      `viewDidDisappear()` clears the wash.
  S3  a media whose marker is current for captions but not fillers (stamped
      from `speech.mov`, `disfluencies: false`, a readable transcript): one
      row, `FillerTranscription.estimate` fate `.upload(.refresh)`, the row's
      line `describe` of it with "1 file to upload", the cloud-only note and
      `uploadHint` of the probe's region shown; keyless the button is off and
      the note holds `noKeyNote`, keyed it is on; Remove off, "No cuts".
  S4  `options(for:)` keeps a marker's language, speakers and vocabulary with
      the shipped models and fillers; nil is detection, none, none.
  S5  `jobs(for:)` drops another media's clip and a reversed one.
  S6  `AssistantToolTable.refusal` is the row's sentence and
      `assistantCatalog` drops the tool.
  S7  S1's input needing the media, keyed: Remove and Transcribe on; after
      `runStarted(media:)` Remove is off, `runningMedia` is the media, and the
      row's button reads "Stop", enabled.

App rows (the app `proof_app` chooses — Debug by default, `RC_PROOF_APP=release`
for the record — through `cloud_captions_proof.Instance`/`Session` and the fake
serving `cloud_captions_proof.DISFLUENT_WORDS`):
  T0  the startup parity log is empty; `transcribe_for_fillers` takes exactly
      `media` and `project`, `media` required; `detect_fillers`' text names
      "Remove Filler Words…" and "transcribe_for_fillers" and not "future".
  T1  `transcribe` (assemblyai, place false, speakers true), then
      `fillers_proof.py` M4's raw edits strip `disfluencies`: `detect_fillers`
      needs the media; `transcribe_for_fillers` makes one submit with
      `disfluencies` and `speaker_labels` true, answers `uploaded` [m] and
      `ready` true, leaves `get_project` unchanged; `detect_fillers` then
      answers [[1460000, 1780000]].
  T2  a second call: no submit, `uploaded` [], `cached` [m], the note.
  T3  refused: no `media`, 987654, a media no clip plays.
  T4  on an `Instance(key=None)`: the credential sentence and no upload.
  T5  T1's package, Clip ▸ Remove Filler Words…: the sheet's dump reads
      "1 cut · removes 00:00:00:16"; the timeline PNG with the sheet up
      differs from the one after `cancel_sheet`, which equals the one before.
  T6  a never-transcribed session: the dump shows the media's name,
      "Transcribe", the cloud-only note and "deleted from AssemblyAI once the
      words have been read back"; then `cancel_sheet`.

Mutants (`--mutant`, probe rows only), each anchor asserted to occur once:
  options-drop-request     `marker?.speakerLabels ?? false` → `false` (S4)
  estimate-no-refresh      `refresh = true` → `false` (S3)
  no-wash                  refresh's `candidateSpans = outcome.spans` → `[]` (S1)
  wash-kept                the teardown's clear removed (S2)
  first-span-only          the commit's `outcome.spans.map` → `.prefix(1).map` (S2)
  remove-always-enabled    Remove's enable line → `true` (S3)
  remove-live-during-run   `&& runningMedia == nil` removed from it (S7)
  transcribe-without-key   the rows' credential gate removed (S3)
  not-withheld             the table row's tool name changed (S6)

Exit: a plain run exits 0 iff every row passed, else 1. A `--mutant` run
exits 0 when every row the mutant names failed (caught), 1 when one passed
(survived), and 2 when the control could not be performed: an anchor not
found exactly once, the copy did not build, or a named row was not scored.
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

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/filler-sheet"
PROBE = ROOT / "tools/proof/filler_sheet_probe.swift"
SPEECH = ROOT / "tools/proof/media/speech.mov"
PROBE_ROWS = ["S0", "S1", "S2", "S3", "S4", "S5", "S6", "S7"]
APP_ROWS = ["T0", "T1", "T2", "T3", "T4", "T5", "T6"]
ROWS = PROBE_ROWS + APP_ROWS
WALL = 240
SEC = 600_000

FT = "FillerTranscription.swift"
FS = "FillerSheetController.swift"
FX = "FillerSheetController+Transcribe.swift"
AT = "AssistantToolTable.swift"
ENABLE = "isEnabled = !outcome.spans.isEmpty && runningMedia == nil"
# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "options-drop-request": (["S4"], [(FT, "marker?.speakerLabels ?? false", "false")]),
    "estimate-no-refresh": (["S3"], [(FT, "refresh = true", "refresh = false")]),
    "no-wash": (["S1"], [(FS, "candidateSpans = outcome.spans", "candidateSpans = []")]),
    "wash-kept": (["S2"], [(FS, "        timeline?.candidateSpans = []\n", "")]),
    "first-span-only": (["S2"], [(FS, "outcome.spans.map", "outcome.spans.prefix(1).map")]),
    "remove-always-enabled": (["S3"], [(FS, ENABLE, "isEnabled = true")]),
    "remove-live-during-run": (["S7"], [(FS, ENABLE, "isEnabled = !outcome.spans.isEmpty")]),
    "transcribe-without-key": (["S3"], [(FX, "idle && hasCredential && runnable",
                                         "idle && runnable")]),
    "not-withheld": (["S6"], [(AT, 'tool: "transcribe_for_fillers", rule: .withheld',
                               'tool: "transcribe_for_fillers_kept", rule: .withheld')]),
}

CLOUD_ONLY = ("Filler words are found only in an AssemblyAI transcript made with filler words — "
              "transcription on this Mac does not report them. These files have none yet:")


# --------------------------------------------------------------------------
# The probe


def build(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "filler-sheet-probe"
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
        result = subprocess.run([str(binary), str(SPEECH)], capture_output=True, text=True,
                                timeout=WALL, cwd=here)
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

    def score(self, row, ok, detail):
        self.results[row] = (bool(ok), detail)


def close(session):
    try:
        session.op("close_project", discard=True)
    except Exception:  # noqa: BLE001 — closing is housekeeping
        pass


def sheet_texts(session, tag):
    """The visible texts of the window's sheet (`snapshot_ui`'s layout dump)."""
    shot = session.op("snapshot_ui", window="sheet", path=str(WORK / f"sheet-{tag}.png"))
    with open(shot.get("layout_path") or "") as handle:
        return [v.get("text") for v in json.load(handle)["views"]
                if not v.get("hidden") and v.get("text")]


def timeline_png(session, tag):
    """The editor's timeline as PNG bytes."""
    path = WORK / f"timeline-{tag}.png"
    shot = session.op("snapshot_ui", window="editor", view="timeline", path=str(path))
    return Path(shot.get("path") or path).read_bytes()


def open_sheet(session):
    """Clip ▸ Remove Filler Words…, then the window polled (≤ 10 s) until it
    has a sheet; the menu's answer."""
    import time
    answer = session.op("perform_menu_item", path=["Clip", "Remove Filler Words…"])
    began = time.monotonic()
    while time.monotonic() - began < 10:
        listing = session.op("perform_menu_item")
        if (listing.get("window") or {}).get("sheet") is not None:
            break
        time.sleep(0.1)
    time.sleep(0.3)
    return answer


def app_rows(results, wanted, binary, speech):
    import cloud_captions_proof as cloud
    import cloud_captions_probe
    import proof_app

    os.makedirs(cloud.WORK, exist_ok=True)
    WORK.mkdir(parents=True, exist_ok=True)
    words = cloud.DISFLUENT_WORDS
    try:
        proof_app.require_fresh(binary)
    except proof_app.StaleApp as stale:
        for row in wanted:
            results.score(row, False, f"not run: {stale}")
        return
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

    with contextlib.closing(lock), cloud_captions_probe.Fake("filler-sheet") as fake:
        instance = cloud.Instance("filler-sheet", fake, str(binary))
        state = {}
        try:
            def t0():
                log = cloud.read(instance.log).decode("utf-8", "replace")
                complaints = [line for line in log.splitlines() if "Frame Job: " in line]
                schemas = instance.mcp.schemas()
                schema = schemas.get("transcribe_for_fillers", {}).get("inputSchema", {})
                keys = sorted(schema.get("properties", {}))
                required = schema.get("required")
                text = schemas.get("detect_fillers", {}).get("description", "")
                return (not complaints and keys == ["media", "project"] and required == ["media"]
                        and "Remove Filler Words…" in text and "transcribe_for_fillers" in text
                        and "future" not in text,
                        f"parity lines {complaints[:3]}; properties {keys}, required {required}; "
                        f"detect_fillers names the sheet {'Remove Filler Words…' in text}, the "
                        f"tool {'transcribe_for_fillers' in text}, \"future\" {'future' in text}")
            run("T0", t0)

            def t1():
                cloud.scenario(fake, disfluent_words=words)
                session = cloud.Session(instance, "filler-sheet-T1")
                state["t1"] = session
                media = session.media_of(speech)
                session.add(media, at=0, duration=5 * SEC)
                session.save()
                state["media"] = media
                session.op("transcribe", engine="assemblyai", place=False, speakers=True)
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
                needed = session.op("detect_fillers")
                mark = len(fake.log()["requests"])
                before = session.op("get_project")
                answer = session.op("transcribe_for_fillers", media=media)
                after = session.op("get_project")
                sent = [r["json"] for r in cloud.submits({"requests": fake.log()["requests"][mark:]})]
                detected = session.op("detect_fillers")
                ok = (all(found) and needed.get("needs_transcript") == [media]
                      and len(sent) == 1 and sent[0].get("disfluencies") is True
                      and sent[0].get("speaker_labels") is True
                      and answer.get("uploaded") == [media] and answer.get("ready") is True
                      and answer.get("ok") is True and answer.get("media") == media
                      and before == after and detected.get("ranges") == [[1460000, 1780000]])
                return ok, (f"raw edits found {found}; needs {needed.get('needs_transcript')}; "
                            f"submits {len(sent)}, disfluencies "
                            f"{[s.get('disfluencies') for s in sent]}, speaker_labels "
                            f"{[s.get('speaker_labels') for s in sent]}; answer uploaded "
                            f"{answer.get('uploaded')}, ready {answer.get('ready')}, keys "
                            f"{sorted(answer)}; get_project unchanged {before == after}; ranges "
                            f"{detected.get('ranges')}")
            run("T1", t1)

            def t2():
                session, media = state.get("t1"), state.get("media")
                if session is None:
                    return False, "T1's session is not available"
                mark = len(fake.log()["requests"])
                answer = session.op("transcribe_for_fillers", media=media)
                sent = cloud.submits({"requests": fake.log()["requests"][mark:]})
                note = answer.get("note") or ""
                want = (f"Media {media} already has a transcript made with filler words, so "
                        "nothing was uploaded.")
                return (not sent and answer.get("uploaded") == [] and answer.get("cached") == [media]
                        and answer.get("ready") is True and answer.get("audio_seconds") == 0
                        and note == want,
                        f"submits {len(sent)}; uploaded {answer.get('uploaded')}, cached "
                        f"{answer.get('cached')}, ready {answer.get('ready')}, audio_seconds "
                        f"{answer.get('audio_seconds')}; note {note!r}")
            run("T2", t2)

            def t3():
                session = state.get("t1")
                if session is None:
                    return False, "T1's session is not available"
                other = session.media_of(os.path.join(os.path.dirname(speech), "speech.aiff"))
                missing = session.error("transcribe_for_fillers")
                unknown = session.error("transcribe_for_fillers", media=987654)
                unplayed = session.error("transcribe_for_fillers", media=other)
                return (missing is not None and "media" in missing
                        and unknown == "transcribe_for_fillers: No media has id 987654. "
                        "get_project lists the media; import_media adds a file."
                        and unplayed == f"transcribe_for_fillers: No clip in this timeline plays "
                        f"media {other} from its file, so it cannot be transcribed.",
                        f"no media → {missing!r}; 987654 → {unknown!r}; unplayed → {unplayed!r}")
            run("T3", t3)

            def t5():
                session = state.get("t1")
                if session is None:
                    return False, "T1's session is not available"
                session.op("set_selection", clips=[])
                first = timeline_png(session, "before")
                open_sheet(session)
                texts = sheet_texts(session, "T5")
                up = timeline_png(session, "up")
                session.op("cancel_sheet")
                import time
                time.sleep(0.3)
                down = timeline_png(session, "down")
                return ("1 cut · removes 00:00:00:16" in texts and up != first and down == first,
                        f"sheet texts {texts[:6]}; timeline with the sheet up differs "
                        f"{up != first}; after cancel equals before {down == first}")
            run("T5", t5)
            if state.get("t1") is not None:
                close(state["t1"])

            def t6():
                session = cloud.Session(instance, "filler-sheet-T6")
                try:
                    media = session.media_of(speech)
                    session.add(media, at=0, duration=5 * SEC)
                    session.op("set_selection", clips=[])
                    open_sheet(session)
                    texts = sheet_texts(session, "T6")
                    session.op("cancel_sheet")
                    name = os.path.basename(speech)
                    phrase = "deleted from AssemblyAI once the words have been read back"
                    return (name in texts and "Transcribe" in texts and CLOUD_ONLY in texts
                            and any(phrase in t for t in texts),
                            f"name {name in texts}, Transcribe {'Transcribe' in texts}, the "
                            f"cloud-only note {CLOUD_ONLY in texts}, the deletion "
                            f"{any(phrase in t for t in texts)}; texts {texts[:10]}")
                finally:
                    close(session)
            run("T6", t6)
        finally:
            instance.stop()

        if "T4" in wanted:
            keyless = cloud.Instance("filler-sheet-keyless", fake, str(binary), key=None)
            try:
                def t4():
                    cloud.scenario(fake, disfluent_words=words)
                    session = cloud.Session(keyless, "filler-sheet-T4")
                    try:
                        media = session.media_of(speech)
                        session.add(media, at=0, duration=5 * SEC)
                        refusal = session.error("transcribe_for_fillers", media=media)
                        sent = cloud.uploads(fake.log())
                        want = ("transcribe_for_fillers: No AssemblyAI API key is set. Set one "
                                "in Frame Job ▸ Settings ▸ Transcription, or RC_ASSEMBLYAI_KEY "
                                "for a proof.")
                        return (refusal == want and not sent,
                                f"refusal {refusal!r}; uploads {len(sent)}")
                    finally:
                        close(session)
                run("T4", t4)
                log = cloud.read(keyless.log).decode("utf-8", "replace")
                complaints = [line for line in log.splitlines() if "Frame Job: " in line]
                if complaints and "T4" in results.results:
                    ok, detail = results.results["T4"]
                    results.score("T4", False, f"{detail}; parity lines {complaints[:3]}")
            finally:
                keyless.stop()


# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    wanted = args.only.split(",") if args.only else (PROBE_ROWS if args.mutant else ROWS)
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    if args.mutant and any(row in APP_ROWS for row in wanted):
        print("a mutant runs the probe rows only")
        return 2
    probe_wanted = [row for row in wanted if row in PROBE_ROWS]
    app_wanted = [row for row in wanted if row in APP_ROWS]
    if probe_wanted and "S0" not in probe_wanted:
        probe_wanted = ["S0"] + probe_wanted
    if app_wanted and "T0" not in app_wanted:
        app_wanted = ["T0"] + app_wanted
    if "T2" in app_wanted or "T3" in app_wanted or "T5" in app_wanted:
        app_wanted = sorted(set(app_wanted) | {"T1"}, key=APP_ROWS.index)
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
        results.score("S0", binary is not None, why or f"built from {sources}")
        if binary is None and args.mutant:
            print(f"S0 fail — {why}")
            print(f"mutant {args.mutant}: the control could not be performed — the copy did "
                  "not build")
            return 2
        if not SPEECH.exists():
            answers, why = None, "media/speech.mov is missing"
        else:
            answers, why = (probe(binary, here) if binary is not None
                            else (None, "not run: the probe did not build"))
        for row in probe_wanted:
            if row == "S0":
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
            app_rows(results, app_wanted, proof_app.binary(), str(SPEECH))
        for row in app_wanted:
            if row not in results.results:
                results.score(row, False, "not scored")

    for row in wanted:
        good, detail = results.results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results.results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored or row not in results.results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results.results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 1
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 0


if __name__ == "__main__":
    try:
        code = main()
    finally:
        cloud = sys.modules.get("cloud_captions_proof")
        if cloud is not None:
            from mcp import remove_scratch
            for scratch in cloud.SCRATCH:
                remove_scratch(scratch)
    sys.exit(code)
