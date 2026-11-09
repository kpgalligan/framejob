#!/usr/bin/env python3
"""Road map "creator-jobs" TX2a and TX2b (spec §11 TX-20…TX-27): the
Transcript tab, its view, its fill, its bar and the dev tool `transcript_view`.

    python3 tools/proof/transcript_tab_proof.py [--only IDS]
    python3 tools/proof/transcript_tab_proof.py --mutant NAME
    python3 tools/proof/transcript_tab_proof.py --mutants

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The one app
launch is TX1's (`timeline_transcript_proof.py`): `assistant_session_proof.App`
with a 0700 `-RCSecretFolder` holding the dummy `proof-key`, and
`-RCAssemblyAIEndpoint` at `assemblyai_fake.py`, which serves T6's words.
Fixture media are TX1's `say` phrases (`timeline_transcript_proof.fixtures`),
`long_fixture`'s ~3,600 s WAV (TX1's P12), a 120 s silent WAV and a 3,600 s
silent AAC (`ffmpeg -f lavfi anullsrc`) under `tools/proof/work/transcript_tab/`.

Probe rows (`transcript_tab_probe.swift`, built through `swift_build.build()`
with `-D FRAMEJOB_DEV_TOOLS`, run with `--fonts app/Resources/Fonts`, the app's
`Compositor.metal` beside it): T0 builds; T1, T3p, T5, T7, T8, T9, T10, T13p
as its header says; T4p a click while playing keeps playing; T14p a drag past
a line's end or before its start maps to the line's last or first character
(the line answers NSNotFound off its glyphs) and never traps; T15p eighteen
drags along a line (the middle, top or bottom line shown; straight, wobbling ±3
pt, or 80 pt past the edge; paused, then looping while playing) move the scroll
by no more than 0.5 pt (TX-22 at CP1). T16 (#444) a voice cache replaced under
shown `.assemblyai` words (alpha [10.0, 10.4) s, beta [12.9, 13.3) s, preloaded
with an all-voiced cache) and announced as `word_onset_probe.swift`'s U9 does:
within 5 s one pause token follows clip 3's alpha and beta starts a paragraph.
T17 (#444) the same landing while the tab's cloud load of a planted transcript
is held (`TranscriptTabSource.loadHold`, as U10): after the release the cloud
words show with the new cache's pause and paragraph break.

App rows (the app `proof_app` chooses; `RC_PROOF_APP=release` for the record):
  Z0  no `Frame Job: ` line; `transcript_view` takes exactly click, focus,
      language, project, read, select, select_pause (TX3b), stop_after, wait
      and words_from.
  M1  `perform_menu_item ["View","Transcript"]` shows the tab with the view
      first responder; a hidden tab is refused by its sentence; and
      `select_inspector_tab {tab: "transcript"}` reaches it.
  T2  on TX1's fixtures (two tracks, a nest, a locked track, a clip with its
      audio off): the tokens and `no_words` equal `get_timeline_transcript`'s,
      every key and id included.
  T3  after `play_preview`, `highlight` is the latest token started at the
      answered `playhead`.
  T4  `click: i` puts the playhead at word i's frame-snapped start; paused
      stays paused (the playing half is the probe's T4p: no MCP door starts
      playback); the selection is TX-31's plan of word i (TX3a), i inside it.
  T6  a 3,600 s silent AAC with 27,000 words in 900 paragraphs (1.6 s gaps)
      served by the fake through `transcribe {engine: assemblyai, place:
      false}`: 900 paragraphs, and over 5 `split`s the median
      `last_rebuild_ms` is under 100. RELEASE ONLY (spec §11 V-4, #522): on
      a Debug app (its `CFBundleIdentifier` is Debug's) T6 is a named SKIP,
      because the 100 ms bound is a Release number and a Debug rebuild of
      the same tab takes about 250 ms; the rest of the proof runs on either.
  T11 `transcript_spike/view_spike.py --measure` meets TX-S2's rule.
  T12 A (under the playhead) and the long WAV, both read on this Mac: A's
      tokens appear while `fill.media` is still the long WAV's; a hidden tab
      is refused; shown again, the long run starts over (its fraction falls,
      the tab wanting it), so hiding released the want and the run was
      cancelled; hidden and shown again at once, it is wanted anew too.

TX2b's rows (spec §11 TX-24…TX-27; the road map's T8–T11, renamed because
T8–T11 are TX2a's probe rows):
  B1  (a) A on track 1, B on track 2: `words_from: t2` shows tokens equal to
      `get_timeline_transcript {tracks: [t2]}`'s words, all on t2, fewer than
      All tracks'; `words_from: null` equals the unfiltered call. (b) A on t1
      and `ten.wav` on t2, shown and at once `words_from: t1, wait: 60`:
      settled, no token of ten's and no `<ten>-*.json` in the package.
  B2  a second installed language (a named host SKIP with fewer than two):
      `language: L2, wait: 60` reads A again, and both `<A>-<L1>.json` and
      `<A>-<L2>.json` are kept.
  B3  (a) Stop during the tab's read of `ten.wav` while
      `get_timeline_transcript` waits on it (`stop_after: 3`): the call lands
      ten's words after more than 3 s; the tab reads stopped with no want;
      Read shows ten's tokens, idle. (b) ten and the long WAV queued behind
      it: after `stop_after: 1`, every answer for 4 s is stopped with no want,
      never the long media in `fill`, "2 files not read", and no
      `<long>-*.json`.

Other rows: T11 above; B4 `screens.py --only 11c-transcript-tab` on the
app `proof_app` chooses, rc 0 and "new problems: 0".

Mutants (`--mutant NAME`, or all with `--mutants`): each anchor occurs once;
a mutant is caught when every row it names fails.
  highlight-containment  the highlight by containment (T3p)
  follow-pause-ignored   the 3 s follow pause ignored (T8)
  space-consumed         the view swallows every key it does not take, Space
                         included, so J and L never reach the editor (T5)
  paragraph-1.0s         the paragraph pause at 1.0 s (T9)
  live-rebuild           a rebuild during a live gesture (T7)
  clip-picked-switches   a click on a clip switches to Clip (T10)
  line-index-unchecked   the line's NSNotFound added to the offset (T14p)
  drag-follows           a press and a drag no longer pause the follow (T15p)
  one-wait               every miss wanted at once under a single wait (T12;
                         an app built from a tree copy)
  words-from-ignored     Words from's track filter removed at the fill and at
                         the words (B1; a tree copy)
  stop-cancels-all       the bar's Stop drops every owner's want
                         (`TranscriptFill.drop()`) (B3; a tree copy)
  speech-kept            the pane's `reloadSpeech` call removed: a landed voice
                         cache leaves the kept one in the table (T16)
  paragraphs-kept        `reloadSpeech` ends after its drop: the pause set is
                         not read again (T16's paragraph half)
  cloud-epoch-unchecked  a cloud load that read before a landing merges what
                         it read (T17)

Exit: 0 iff every row passed or was a named host SKIP (a mutant run: 0 when
caught, 1 when it survived, 2 when the control could not be performed).
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import statistics
import subprocess
import sys
import time
import traceback
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import swift_build  # noqa: E402
import bounded  # noqa: E402 — on swift_build's path
import timeline_transcript_proof as ttp  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/transcript_tab"
PROBE = ROOT / "tools/proof/transcript_tab_probe.swift"
FONTS = ROOT / "app/Resources/Fonts"
PROBE_ROWS = ["T0", "T1", "T3p", "T4p", "T5", "T7", "T8", "T9", "T10", "T13p", "T14p", "T15p",
              "T16", "T17"]
APP_ROWS = ["Z0", "M1", "T2", "T3", "T4", "T6", "T12", "B1", "B2", "B3"]
OTHER_ROWS = ["T11", "B4"]
ROWS = PROBE_ROWS + APP_ROWS + OTHER_ROWS
SEC = 600_000
KEY = "proof-key"
TOOL = "transcript_view"
HIDDEN = 'transcript_view: select_inspector_tab {tab: "transcript"} first.'
# T6 alone is pinned to Release (spec §11 V-4; #522): the root CLAUDE.md's
# `release_only=` for one row of a proof whose other rows run on Debug, so
# `git grep release_only= tools/proof` finds it here.
T6_RELEASE_ONLY = ("its 100 ms median rebuild is a Release number: a Debug build "
                   "rebuilds the same 27,000 tokens in about 250 ms")

TT = "TranscriptTokens.swift"
TH = "TranscriptView+Highlight.swift"
TK = "TranscriptView+Keys.swift"
TS = "TranscriptTabSource.swift"
TF = "TranscriptFill.swift"
IV = "InspectorViewController.swift"
TL = "TranscriptView+Layout.swift"
TD = "TranscriptView+Delete.swift"
TP = "TranscriptPane.swift"
MUTANTS = {
    "highlight-containment": ("probe", ["T3p"], [
        (TT, "        return low == 0 ? nil : low - 1\n",
         "        return low == 0 || tokens[low - 1].word.end <= playhead ? nil : low - 1\n")]),
    "follow-pause-ignored": ("probe", ["T8"], [
        (TH, "guard follow, let valid, !personScrolledRecently else { return }",
         "guard follow, let valid else { return }")]),
    "space-consumed": ("probe", ["T5"], [
        (TK, "        default: super.keyDown(with: event)\n", "        default: break\n")]),
    "paragraph-1.0s": ("probe", ["T9"], [
        (TT, "static let paragraphPause: Ticks = ReelTime.perSecond * 3 / 2",
         "static let paragraphPause: Ticks = ReelTime.perSecond")]),
    "live-rebuild": ("probe", ["T7"], [
        (TS, "        if document.isLiveEditing {\n            dirty = true\n            return\n"
             "        }\n", ""),
        (TS, "        if document?.isLiveEditing == true {\n            dirty = true\n"
             "            return\n        }\n", "")]),
    "clip-picked-switches": ("probe", ["T10"], [
        (IV, "        if tab == .transcript { (pane(for: .transcript) as? TranscriptPane)?"
             ".reveal(selectedClips); return }\n", "")]),
    "line-index-unchecked": ("probe", ["T14p"], [
        (TL, "        guard index != NSNotFound, index >= 0 else {\n", "        guard true else {\n")]),
    "drag-follows": ("probe", ["T15p"], [
        (TK, "        personScrolled()  // a press pauses the follow, as a scroll does (TX-22 at CP1)\n", ""),
        (TD, "        personScrolled()  // the follow waits while the person selects (TX-22 at CP1)\n", "")]),
    "speech-kept": ("probe", ["T16"], [
        (TP, "            source.reloadSpeech(media: media)\n", "")]),
    "paragraphs-kept": ("probe", ["T16"], [
        (TS, "        guard shown, let heard = words[media], deviceItems[media] == nil,\n",
         "        if true { return }\n"
         "        guard shown, let heard = words[media], deviceItems[media] == nil,\n")]),
    "cloud-epoch-unchecked": ("probe", ["T17"], [
        (TS, "                    if epochs[media] != self.epoch(media) "
             "{ self.reloadSpeech(media: media) }\n", "")]),
    "one-wait": ("app", ["T12"], [(TS, "let take = 1\n", "let take = pending.count\n")]),
    "words-from-ignored": ("app", ["B1"], [
        (TS, "        let instances = read.instances.filter { wordsFrom == nil || $0.track == wordsFrom }\n",
         "        let instances = read.instances\n"),
        (TS, "            let shown = all.filter { wordsFrom == nil || $0.track == wordsFrom }\n",
         "            let shown = all\n")]),
    "stop-cancels-all": ("app", ["B3"], [
        (TF, "    private func drop() {\n", "    func drop() {\n"),
        (TS, "        fill.release(owner: owner)  // Stop: the tab's want only (TX-26)\n",
         "        fill.drop()  // Stop: the tab's want only (TX-26)\n")]),
}


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


def silent_aac():
    path = WORK / "silent-3600.m4a"
    if not path.exists():
        WORK.mkdir(parents=True, exist_ok=True)
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        "anullsrc=r=16000:cl=mono", "-t", "3600", "-c:a", "aac", "-b:a", "16k",
                        str(path)], check=True, timeout=600)
    return path


def probe_package():
    """Media 20, a 120 s silent WAV, under clip 3 (0–60 s) and clip 4 (70–130 s)."""
    wav = silent_wav("silent-120", 120)
    clips = [
        {"id": cid, "track": 1, "start": start, "duration": 60 * SEC,
         "source": {"kind": "media", "media": 20, "in": 0, "reversed": False},
         "enabled": {"video": True, "audio": True}}
        for cid, start in ((3, 0), (4, 70 * SEC))]
    body = {"version": 37,
            "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "timecode_frames": True},
            "media": [{"id": 20, "path": str(wav), "kind": "audio", "duration": 120 * SEC,
                       "has_audio": True}],
            "tracks": [{"id": 1, "name": "Track 1", "muted": False, "locked": False}],
            "clips": clips, "markers": [], "nests": [], "next_id": 100}
    path = WORK / "probe.framejob"
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)
    (path / "project.json").write_text(json.dumps(body, indent=1))
    return path


def cloud_words():
    """27,000 words in 900 paragraphs of 30, 4 s apart: each word 60 ms, every
    80 ms, so 1.68 s of silence ends each paragraph."""
    out = []
    for paragraph in range(900):
        base = paragraph * 4000
        for index in range(30):
            start = base + index * 80
            out.append({"text": f"w{paragraph}x{index}", "start": start, "end": start + 60,
                        "confidence": 0.9, "speaker": None})
    return out


# --------------------------------------------------------------------------
# Probe and mutation


def apply_edits(edits, folder):
    for file, before, after in edits:
        path = Path(folder) / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe_rows(results, wanted, mutant=None):
    import space_key_proof
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
    shader, why = space_key_proof.build_shader(str(here))
    if shader is None:
        results.score("T0", False, f"the shader: {why}")
        return None
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "transcript-tab-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        results.score("T0", False, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8])))
        return None
    results.score("T0", True, f"built from {sources}")
    ran = bounded.run([str(binary), str(probe_package()), "--fonts", str(FONTS)], 300,
                      cwd=str(here))
    (here / "stderr.txt").write_text(ran["stderr"])
    try:
        answers = json.loads(ran["stdout"].strip().splitlines()[-1])["rows"]
    except (ValueError, KeyError, IndexError):
        answers = []
    for row in wanted:
        if row == "T0":
            continue
        answer = next((a for a in answers if a.get("id") == row), None)
        if answer is None:
            results.score(row, False, f"no row (exit {ran['rc']}): {ran['stderr'][-300:]}")
        else:
            results.score(row, answer.get("pass") is True, answer.get("detail", ""))
    return None


def spike_row(results):
    ran = bounded.run([sys.executable, str(ROOT / "tools/proof/transcript_spike/view_spike.py"),
                       "--measure"], 900, cwd=str(ROOT))
    lines = [l for l in ran["stdout"].splitlines() if l.strip()]
    results.score("T11", ran["rc"] == 0, f"view_spike.py --measure rc {ran['rc']}: {lines[-3:]}")


# --------------------------------------------------------------------------
# The app rows


Rows = ttp.Rows


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


def snap(ticks, fps):
    num, den = fps
    frame = SEC * den / num
    return round(round(ticks / frame) * frame)


def is_debug_app(app_path):
    """True when `app_path` (a bundle or its executable) is a Debug build:
    its `CFBundleIdentifier` is Debug's own (spec §11 V-5). A path outside a
    products folder is read the same way, so a frozen Debug copy counts."""
    import proof_app
    bundle = Path(app_path)
    if bundle.parent.name == "MacOS":
        bundle = bundle.parents[2]
    try:
        with open(bundle / "Contents/Info.plist", "rb") as handle:
            identifier = plistlib.load(handle).get("CFBundleIdentifier")
    except (OSError, plistlib.InvalidFileException):
        return False
    return identifier == proof_app.DOMAINS["debug"]


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
        with contextlib.suppress(Exception):
            session.op("close_project", discard=True)

    stand_in = app = None
    with contextlib.closing(lock), cloud_captions_probe.Fake("transcript-tab") as aai:
        try:
            stand_in = sp.Fake(str(WORK / "anthropic-fake"))
            app = sp.App("transcript-tab", app_path,
                         ["-RCSecretFolder", secret_folder(), "-RCAssemblyAIEndpoint", aai.base],
                         stand_in.base)
            app.connect()

            def session_of(name):
                return cloud.Session(app, f"tab-{name}")

            def view(session, **arguments):
                return session.op(TOOL, **arguments)

            def tracks(session):
                return [t["id"] for t in session.project()["tracks"]]

            def z0():
                complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
                schema = app.mcp.schemas().get(TOOL, {}).get("inputSchema", {})
                keys = sorted(schema.get("properties", {}))
                return (not complaints and keys == ["click", "focus", "language", "project", "read",
                                                    "select", "select_pause", "stop_after", "wait",
                                                    "words_from"],
                        f"parity lines {complaints[:3]}; properties {keys}")
            run("Z0", z0)

            def m1():
                s = session_of("m1")
                try:
                    s.add(s.media_of(str(files["A"])), at=0)
                    s.op("perform_menu_item", path=["View", "Transcript"])
                    first = view(s, wait=60)
                    s.op("select_inspector_tab", tab="clip")
                    hidden = s.error(TOOL)
                    s.op("select_inspector_tab", tab="transcript")
                    again = view(s, wait=30)  # hidden, the tab dropped its words: read again
                    return (first.get("first_responder") is True and hidden == HIDDEN
                            and again.get("ok") is True and len(again.get("tokens", [])) > 5,
                            f"first responder {first.get('first_responder')}; hidden {hidden!r}; "
                            f"shown again: {len(again.get('tokens', []))} tokens")
                finally:
                    close(s)
            run("M1", m1)

            def t2():
                s = session_of("t2")
                state["t2"] = s
                a, b, c = (s.media_of(str(files[n])) for n in ("A", "B", "C"))
                t1 = tracks(s)[0]
                t2_ = s.op("add_track") and tracks(s)[-1]
                s.add(a, at=0, track=t1)
                s.add(b, at=SEC, track=t2_)
                inner = s.add(c, at=23 * SEC, track=t1)
                s.op("nest", clips=[inner], name="Intro")
                quiet = s.add(b, at=40 * SEC, track=t1)
                s.op("set_enabled", clip=quiet, audio=False)
                s.op("set_track", track=t2_, locked=True)
                s.op("select_inspector_tab", tab="transcript")
                shown = view(s, wait=60)
                read = s.op("get_timeline_transcript")
                tokens = [{k: v for k, v in t.items() if k not in ("index", "paragraph", "struck")}
                          for t in shown.get("tokens", [])]
                state["t2_shown"] = shown
                kinds = {(w.get("editable"), w.get("why", "")[:6]) for w in read.get("words", [])}
                return (shown.get("settled") is True and tokens == read.get("words")
                        and shown.get("no_words") == read.get("no_words")
                        and len(tokens) > 20 and len(shown.get("no_words", [])) == 1
                        and len(kinds) >= 3,
                        f"{len(tokens)} tokens, {len(read.get('words', []))} words, equal "
                        f"{tokens == read.get('words')}; no_words {shown.get('no_words')} vs "
                        f"{read.get('no_words')}; editability {sorted(kinds, key=str)}")
            run("T2", t2)

            def t3():
                s = state.get("t2")
                if s is None:
                    return False, "T2 did not run"
                s.op("set_playhead", t=0)
                played = s.op("play_preview", seconds=2)
                shown = view(s)
                starts = [t["start"] for t in shown.get("tokens", [])]
                want = max((i for i, st in enumerate(starts) if st <= shown["playhead"]),
                           default=None)
                return (shown.get("highlight") == want and want is not None,
                        f"played to {played.get('to')}; playhead {shown.get('playhead')}; "
                        f"highlight {shown.get('highlight')} (want {want})")
            run("T3", t3)

            def t4():
                s = state.get("t2")
                if s is None:
                    return False, "T2 did not run"
                fps = s.project()["canvas"]["fps"]
                shown = view(s, click=7)
                token = shown["tokens"][7]
                want = snap(token["start"], fps)
                # Since TX3a (TX-31) a click's one word is planned: the selection
                # is the plan's, widened over a word of the other track it cuts into.
                selection = shown.get("selection") or [None, None]
                planned = (shown.get("cut") or {}).get("selection")
                return (shown.get("playhead") == want and selection == planned
                        and selection[0] <= 7 <= selection[1]
                        and shown.get("playing") is False,
                        f"playhead {shown.get('playhead')} (want {want}); selection "
                        f"{selection} (the plan's {planned}); playing {shown.get('playing')}")
            run("T4", t4)
            if state.get("t2") is not None:
                close(state["t2"])

            def t6():
                if is_debug_app(app_path):
                    return None, (f"release_only: {T6_RELEASE_ONLY}; run it with "
                                  "RC_PROOF_APP=release")
                words = cloud_words()
                cloud.scenario(aai, words=words, disfluent_words=words)
                s = session_of("t6")
                try:
                    media = s.media_of(str(silent_aac()))
                    clip = s.add(media, at=0)
                    s.op("transcribe", engine="assemblyai", place=False)
                    s.op("select_inspector_tab", tab="transcript")
                    shown = view(s, wait=60)
                    paragraphs = len(shown.get("paragraphs", []))
                    times = []
                    for k in range(5):
                        at = (300 + 600 * k) * SEC + 7 * 20_000
                        target = next(c["id"] for c in s.project()["clips"]
                                      if c["start"] < at < c["start"] + c["duration"])
                        s.op("split", clips=[target], at=at)
                        after = view(s, wait=30)
                        times.append(after.get("last_rebuild_ms"))
                    median = statistics.median(times) if None not in times else None
                    return (paragraphs == 900 and len(shown.get("tokens", [])) == 27_000
                            and median is not None and median < 100,
                            f"clip {clip}; {len(shown.get('tokens', []))} tokens in {paragraphs} "
                            f"paragraphs; rebuilds after 5 splits {times} ms, median {median}")
                finally:
                    close(s)
            run("T6", t6)

            def t12():
                import speech_engine_proof
                _, ten, _, _ = speech_engine_proof.make_fixtures()
                long, seconds = sp.long_fixture(ten)
                s = session_of("t12")
                try:
                    a = s.media_of(str(files["A"]))
                    big = s.media_of(long)
                    first = s.add(a, at=0)
                    s.add(big, at=s.clip(first)["duration"] + SEC)
                    s.op("set_playhead", t=0)
                    s.op("select_inspector_tab", tab="transcript")
                    early = None
                    deadline = time.time() + 240
                    while time.time() < deadline:
                        shown = view(s)
                        fill = shown.get("fill") or {}
                        heard = [t for t in shown.get("tokens", []) if t["media"] == a]
                        if heard and fill.get("media") == big and fill.get("fraction", 0) >= 0.05:
                            early = shown
                            break
                        time.sleep(0.5)
                    if early is None:
                        return False, (f"A's tokens never showed while the long WAV ({big}) was "
                                       f"read: last fill {shown.get('fill')}, "
                                       f"{len(shown.get('tokens', []))} tokens")
                    before = early["fill"]["fraction"]
                    s.op("select_inspector_tab", tab="clip")
                    hidden = s.error(TOOL)
                    time.sleep(1.5)
                    s.op("select_inspector_tab", tab="transcript")

                    def wanted_again(below, bound=90):
                        # The long WAV read again from its start: wanted anew.
                        deadline = time.time() + bound
                        while True:
                            shown = view(s)
                            fill = shown.get("fill") or {}
                            if fill.get("media") == big and fill.get("fraction", 1) < below \
                                    and shown.get("owns_want") is True:
                                return shown
                            if time.time() >= deadline:
                                return None
                            time.sleep(0.25)
                    again = wanted_again(before)
                    # Hidden and shown at once, before the waiter wakes: the long
                    # media must still be wanted again, not skipped as running.
                    mid = None
                    deadline = time.time() + 90
                    while again is not None and time.time() < deadline:
                        mid = (view(s).get("fill") or {})
                        if mid.get("media") == big and mid.get("fraction", 0) >= 0.01:
                            break
                        time.sleep(0.25)
                    quick = None
                    if again is not None and mid and mid.get("fraction", 0) >= 0.01:
                        s.op("select_inspector_tab", tab="clip")
                        s.op("select_inspector_tab", tab="transcript")
                        quick = wanted_again(mid["fraction"])
                    return (early.get("owns_want") is True and hidden == HIDDEN
                            and again is not None and quick is not None,
                            f"a {seconds:.0f} s WAV; A's {len([t for t in early['tokens'] if t['media'] == a])} "
                            f"tokens shown while the long run stood at {before:.3f}; owns_want "
                            f"{early.get('owns_want')}; hidden {hidden!r}; shown again the long "
                            f"run read anew: {again and again.get('fill')}; hidden and shown at "
                            f"once from {mid and mid.get('fraction')}: "
                            f"{quick and quick.get('fill')}")
                finally:
                    close(s)
            run("T12", t12)

            def bare(shown):
                return [{k: v for k, v in t.items() if k not in ("index", "paragraph", "struck")}
                        for t in shown.get("tokens", [])]

            def media_files(session, media):
                folder = ttp.device_dir(session)
                names = sorted(os.listdir(folder)) if os.path.isdir(folder) else []
                return [n for n in names if n.startswith(f"{media}-") and n.endswith(".json")]

            def reading(session, media, bound=180):
                # The tab reads `media` on this Mac and owns its want.
                deadline = time.time() + bound
                shown = {}
                while time.time() < deadline:
                    shown = view(session)
                    fill = shown.get("fill") or {}
                    if fill.get("media") == media and fill.get("fraction", 0) >= 0.01 \
                            and shown.get("owns_want") is True and shown["bar"]["stop_shown"]:
                        return shown, None
                    time.sleep(0.25)
                return None, f"the tab never read media {media}: last {shown.get('fill')}, " \
                             f"status {shown.get('status')}"

            def b1():
                s = session_of("b1")
                try:
                    a, b = s.media_of(str(files["A"])), s.media_of(str(files["B"]))
                    t1 = tracks(s)[0]
                    t2_ = s.op("add_track") and tracks(s)[-1]
                    s.add(a, at=0, track=t1)
                    s.add(b, at=SEC, track=t2_)
                    s.op("select_inspector_tab", tab="transcript")
                    every = view(s, wait=60)
                    narrowed = view(s, words_from=t2_, wait=60)
                    read = s.op("get_timeline_transcript", tracks=[t2_])
                    shown = bare(narrowed)
                    again = view(s, words_from=None, wait=60)
                    whole = s.op("get_timeline_transcript")
                    first = (shown == read.get("words") and shown
                             and all(t["track"] == t2_ for t in shown)
                             and len(shown) < len(every.get("tokens", []))
                             and narrowed["bar"]["words_from"] == t2_
                             and bare(again) == whole.get("words")
                             and again["bar"]["words_from"] is None)
                finally:
                    close(s)
                detail = (f"(a) all tracks {len(every.get('tokens', []))} tokens; words_from {t2_}: "
                          f"{len(shown)} tokens, equal to the tool's {len(read.get('words', []))} "
                          f"{shown == read.get('words')}; null: equal {bare(again) == whole.get('words')}")
                import speech_engine_proof
                _, ten, _, _ = speech_engine_proof.make_fixtures()
                s = session_of("b1b")
                try:
                    a = s.media_of(str(files["A"]))
                    tenth = s.media_of(ten)
                    t1 = tracks(s)[0]
                    t2_ = s.op("add_track") and tracks(s)[-1]
                    s.add(a, at=0, track=t1)
                    s.add(tenth, at=0, track=t2_)
                    s.op("set_playhead", t=0)
                    s.op("select_inspector_tab", tab="transcript")
                    narrowed = view(s, words_from=t1, wait=60)
                    stray = [t for t in narrowed.get("tokens", []) if t["media"] == tenth]
                    files_ten = media_files(s, tenth)
                    second = (narrowed.get("settled") is True and narrowed.get("tokens")
                              and not stray and not files_ten)
                finally:
                    close(s)
                detail += (f"; (b) settled {narrowed.get('settled')}, "
                           f"{len(narrowed.get('tokens', []))} tokens, {len(stray)} of ten's, "
                           f"ten's cache files {files_ten}")
                return bool(first) and bool(second), detail
            run("B1", b1)

            def b2():
                s = session_of("b2")
                try:
                    a = s.media_of(str(files["A"]))
                    s.add(a, at=0)
                    s.op("select_inspector_tab", tab="transcript")
                    first = view(s, wait=60)
                    languages = [l["identifier"] for l in first["bar"]["languages"]]
                    if len(languages) < 2:
                        return None, f"this Mac has {len(languages)} installed recognition " \
                                     f"language(s) ({languages}); B2 needs two"
                    before = media_files(s, a)
                    l1 = before[0][len(f"{a}-"):-len(".json")] if before else None
                    l2 = next(l for l in languages if l != l1)
                    shown = view(s, language=l2, wait=60)
                    after = media_files(s, a)
                    return (shown.get("settled") is True and shown["bar"]["language"] == l2
                            and l1 is not None and f"{a}-{l1}.json" in after
                            and f"{a}-{l2}.json" in after and shown.get("tokens"),
                            f"languages {languages}; first read {before}; language {l2}: "
                            f"settled {shown.get('settled')}, bar {shown['bar']['language']}, "
                            f"{len(shown.get('tokens', []))} tokens, files {after}")
                finally:
                    close(s)
            run("B2", b2)

            def b3():
                import speech_engine_proof
                _, ten, _, _ = speech_engine_proof.make_fixtures()
                s = session_of("b3")
                try:
                    tenth = s.media_of(ten)
                    s.add(tenth, at=0)
                    s.op("set_playhead", t=0)
                    s.op("select_inspector_tab", tab="transcript")
                    early, why = reading(s, tenth)
                    if early is None:
                        return False, f"(a) {why}"
                    scheduled = view(s, stop_after=3)
                    started = time.time()
                    try:
                        call = s.op("get_timeline_transcript")
                    except Exception as problem:  # noqa: BLE001 — the call's refusal is the answer
                        call = {"error": str(problem)}
                    took = time.time() - started
                    after = view(s)
                    heard = [w for w in call.get("words", []) if w["media"] == tenth]
                    resumed = view(s, read=True, wait=30)
                    ok_a = (call.get("ok") is True and heard and took > 3
                            and scheduled["bar"]["stop_after"] == "pending"
                            and after["bar"]["stop_after"] == "pressed"
                            and after.get("status") == "stopped" and after.get("owns_want") is False
                            and after["bar"]["read_shown"] is True
                            and [t for t in resumed.get("tokens", []) if t["media"] == tenth]
                            and resumed.get("status") == "idle")
                    detail = (f"(a) the call took {took:.1f} s, ok {call.get('ok')}, {len(heard)} words "
                              f"of ten {call.get('error', '')}; after: stop_after "
                              f"{after['bar']['stop_after']}, status {after.get('status')} "
                              f"{after.get('status_text')}, owns_want {after.get('owns_want')}; "
                              f"Read: {len(resumed.get('tokens', []))} tokens, status "
                              f"{resumed.get('status')}")
                finally:
                    close(s)
                long, seconds = sp.long_fixture(ten)
                s = session_of("b3b")
                try:
                    tenth = s.media_of(ten)
                    big = s.media_of(long)
                    first = s.add(tenth, at=0)
                    s.add(big, at=s.clip(first)["duration"] + SEC)
                    s.op("set_playhead", t=0)
                    s.op("select_inspector_tab", tab="transcript")
                    early, why = reading(s, tenth)
                    if early is None:
                        return False, detail + f"; (b) {why}"
                    view(s, stop_after=1)
                    answers, pressed_at = [], None
                    deadline = time.time() + 30
                    while time.time() < deadline:
                        shown = view(s)
                        if shown["bar"]["stop_after"] == "pressed":
                            pressed_at = pressed_at or time.time()
                            answers.append(shown)
                        if pressed_at and time.time() - pressed_at >= 4:
                            break
                        time.sleep(0.25)
                    wrong = [a for a in answers
                             if a.get("status") != "stopped" or a.get("owns_want") is not False
                             or (a.get("fill") or {}).get("media") == big
                             or not any("2 files not read" in t for t in a.get("status_text", []))]
                    big_files = media_files(s, big)
                    ok_b = bool(answers) and not wrong and not big_files
                    detail += (f"; (b) a {seconds:.0f} s WAV queued: {len(answers)} answers after the "
                               f"press, {len(wrong)} wrong "
                               f"{[(w.get('status'), w.get('fill'), w.get('status_text')) for w in wrong[:2]]}"
                               f"; last {answers[-1].get('status_text') if answers else None}; "
                               f"the long media's cache files {big_files}")
                finally:
                    close(s)
                return bool(ok_a) and ok_b, detail
            run("B3", b3)
        finally:
            if app is not None:
                app.stop()
            if stand_in is not None:
                stand_in.stop()


def screen_row(results):
    """B4: the screen `11c-transcript-tab` captured light and dark with no new
    layout problem, on the app `proof_app` chooses."""
    import proof_app
    ran = bounded.run([sys.executable, str(ROOT / "tools/proof/screens.py"), "--only",
                       "11c-transcript-tab", "--app", str(proof_app.bundle())], 900, cwd=str(ROOT))
    lines = [l for l in ran["stdout"].splitlines() if l.strip()]
    news = [l for l in lines if l.startswith("new problems:")]
    results.score("B4", ran["rc"] == 0 and news == ["new problems: 0"],
                  f"screens.py --only 11c-transcript-tab rc {ran['rc']}: {lines[-4:]}")


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
        if "T0" not in probe_wanted:
            probe_wanted = ["T0"] + probe_wanted
        why = probe_rows(results, probe_wanted, mutant if kind == "probe" else None)
        if why:
            return None, why
    if "T11" in wanted:
        spike_row(results)
    if "B4" in wanted:
        screen_row(results)
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
    kind, named, _ = MUTANTS[name]
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
    return 0 if ttp.report(results, [r for r in ROWS if r in wanted or r == "T0"]) else 1


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
