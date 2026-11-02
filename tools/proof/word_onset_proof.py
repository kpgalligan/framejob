#!/usr/bin/env python3
"""Road map "creator-jobs" TX1b (spec §11 TX-15…TX-19): on-device word starts
moved to where their sound begins, for the tool, the tab, `get_transcript`
and word cuts.

    python3 tools/proof/word_onset_proof.py [--only IDS]
    python3 tools/proof/word_onset_proof.py --mutant NAME
    python3 tools/proof/word_onset_proof.py --mutants

Run it under `env -u RC_ASSEMBLYAI_KEY`: no row spends anything. The one app
launch (`assistant_session_proof.App`) is `transcript_cut_proof.py`'s: a 0700
`-RCSecretFolder` with the dummy key, the fake AssemblyAI and the Anthropic
stand-in; nothing is sent anywhere.

Probe rows (`word_onset_probe.swift`, built through `swift_build.build()` with
`-D FRAMEJOB_DEV_TOOLS` over `app/Sources` or a mutant's copy, the shader
beside it): U0 builds, U1…U10 as its header says.

Fixtures (`say`, 16 kHz LEI16, under `tools/proof/work/word_onset/` and
`work/timeline_transcript/`), each its own project, one clip at 0 at ×1, so
timeline ticks are source ticks; each waits for its voice and peaks caches
(`word_onsets.wait_voice`) before its first read. A phrase's onset is its
first sample over −40 dBFS (|s| > 327.68) after the silence, its end its last
such sample + 1, by this script's own arithmetic.
  pause.wav  four phrases joined by 2.5 s, 1.5 s and 0.8 s of zero samples.
  A, B, C    TX1's phrases (`timeline_transcript_proof.fixtures()`).
  page.wav   TX1's 600 s of A, B and C cycled with 0.5 s gaps.

App rows (the app `proof_app` chooses; `RC_PROOF_APP=release` for the record):
  Z1  the launch's log holds no `Frame Job: ` line.
  O1  pause.wav: each phrase's first word (found by spelling within 1 s) is
      within 20,000 ticks (one 30 fps frame) of its onset.
  O2  A, B and C: each file's first word within a frame of its onset.
  O3  page.wav: every phrase-initial word after a gap within a frame.
  O4  every fixture: text and `id.source` equal the stored run's words (its
      `cache/device-transcripts/` file) in TX-10's order, each start
      `word_onsets.moved` over the package's caches, each end the stored one
      (clamped to the clip, as R6-10 places it).
  O5  pause.wav: `transcript_view`'s tokens (text, start) equal the tool's.
  O6  pause.wav: `get_transcript {clip}`'s (text, start, end) equal the
      tool's, and it answers no `notes` key.
  O7  pause.wav: each phrase's last word's end less the phrase's end, in ms —
      reported, not scored (TX-19: ends are not moved).
  C1  pause.wav and page.wav: for each word before a gap of 1 s or less,
      `cut_end` ≤ the next phrase's onset (no fragment of it) and that onset
      − `cut_end` ≤ 120,000 ticks — except where TX-30's 1 s cap from that
      word's recognised END bounds the cut (its end + 1 s before the next
      word's moved start): that is the end's error, which TX-19 leaves
      unmoved, reported with the end and not scored; for each phrase-initial
      word after a gap, `cut_start` ≤ its onset.
  C2  pause.wav: the tab's Delete of the second phrase's first word
      (`transcript_view` select, `perform_menu_item` Edit ▸ Delete) is one
      step "Delete Words" whose placements equal `ripple_delete_ranges` of
      the tool's [cut_start, cut_end).

Mutants (`--mutant NAME`, or all with `--mutants`): each anchor occurs once; a
mutant is caught when every row it names fails (an O row on an app built from
a tree copy, `tree_copy.build_app`).
  no-move             TX-15 never finds a speech cell (U1, O1)
  no-refine           the peaks never read: the cell's start (U1)
  threshold-absolute  T always −40 dBFS (U6)
  median-whole-run    the median over the whole peaks cache (U6; on `pause.wav`
                      it lands each phrase 5–26 ms late, inside O1's frame)
  run-any-length      a 1-cell run qualifies (U3)
  no-limit            (d) dropped (U4)
  identity-moved      the identity tick is the moved start (U7, O4)
  lead-window         the scan from the run's start, not b − 3 cells (U8)
  epoch-ignored       a load read before a landing merged (U10)

Exit: 0 iff every row passed or was a named host SKIP (O7 is reported only);
a mutant run 0 when caught, 1 when it survived, 2 when not performed.
"""
import argparse
import contextlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import traceback
import wave

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import swift_build  # noqa: E402
import bounded  # noqa: E402 — on swift_build's path
import timeline_transcript_proof as ttp  # noqa: E402
import word_onsets  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/word_onset"
PROBE = ROOT / "tools/proof/word_onset_probe.swift"
PROBE_ROWS = ["U0", "U1", "U2", "U3", "U4", "U5", "U6", "U7", "U8", "U9", "U10"]
APP_ROWS = ["Z1", "O1", "O2", "O3", "O4", "O5", "O6", "O7", "C1", "C2"]
REPORTED = ["O7"]
ROWS = PROBE_ROWS + APP_ROWS
SEC = 600_000
FRAME = 20_000
CUT_GAP = 120_000
RATE = 16000
LOUD = 327.68  # −40 dBFS of 16-bit full scale

PAUSE_PHRASES = ["The quick brown fox jumps over the lazy dog.",
                 "Pack my box with five dozen liquor jugs.",
                 "How vexingly quick daft zebras jump.",
                 "Sphinx of black quartz, judge my vow."]
PAUSE_GAPS_MS = [2500, 1500, 800]

WO = "WordOnsets.swift"
MUTANTS = {
    "no-move": (["U1", "O1"], [
        (WO, "        guard s >= 0, let (a, b) = firstSpeech(after: s, limit: limit, speech: speech) "
             "else {\n",
         "        guard s < 0, let (a, b) = firstSpeech(after: s, limit: limit, speech: speech) "
         "else {\n")]),
    "no-refine": (["U1"], [
        (WO, "        guard let peaks else { return fallback }\n",
         "        guard let peaks = nil as [Float]? else { return fallback }\n")]),
    "threshold-absolute": (["U6"], [
        (WO, "let threshold = max(level, floorRatio * median(peaks, from: Ticks(a) * chunk, "
             "to: fallback))", "let threshold = level")]),
    "median-whole-run": (["U6"], [
        (WO, "median(peaks, from: Ticks(a) * chunk, to: fallback)",
         "median(peaks, from: 0, to: Ticks(peaks.count) * bucket)")]),
    "run-any-length": (["U3"], [
        (WO, "b - a >= TranscriptCut.minimumRunCells", "b - a >= 1")]),
    "no-limit": (["U4"], [
        (WO, "        return onset >= limit ? fallback : onset\n", "        return onset\n")]),
    "identity-moved": (["U7", "O4"], [
        ("TimelineTranscript.swift", "var identityTick: Ticks { recognisedStart ?? source }",
         "var identityTick: Ticks { source }")]),
    "lead-window": (["U8"], [
        (WO, "let from = max(s, Ticks(a) * chunk, Ticks(b - leadCells) * chunk)",
         "let from = max(s, Ticks(a) * chunk)")]),
    "epoch-ignored": (["U10"], [
        ("TranscriptTabSource.swift", "        guard epoch == self.epoch(item.media) else {\n",
         "        guard epoch == epoch else {\n")]),
}


# --------------------------------------------------------------------------
# Fixtures


def audible(body):
    """(first, last) sample index over −40 dBFS in 16-bit mono `body`."""
    samples = struct.unpack(f"<{len(body) // 2}h", body)
    loud = [i for i, s in enumerate(samples) if abs(s) > LOUD]
    return (loud[0], loud[-1]) if loud else (0, len(samples) - 1)


def frames(path):
    with wave.open(str(path), "rb") as source:
        return source.readframes(source.getnframes())


def spelled(text):
    return "".join(c for c in text.lower() if c.isalnum())


def phrase(at, body, text):
    first, last = audible(body)
    return {"onset": round((at + first) * SEC / RATE), "end": round((at + last + 1) * SEC / RATE),
            "first_word": spelled(text.split()[0])}


def pause_fixture():
    """WORK/pause.wav and its phrases [{onset, end, first_word}]."""
    WORK.mkdir(parents=True, exist_ok=True)
    bodies = []
    for index, text in enumerate(PAUSE_PHRASES):
        path = WORK / f"pause-{index}.wav"
        if not path.exists():
            subprocess.run(["say", "-o", str(path), "--file-format=WAVE",
                            "--data-format=LEI16@16000", text], check=True, timeout=120)
        bodies.append(frames(path))
    body, phrases = bytearray(), []
    for index, part in enumerate(bodies):
        phrases.append(phrase(len(body) // 2, part, PAUSE_PHRASES[index]))
        body += part
        if index < len(PAUSE_GAPS_MS):
            body += b"\0\0" * (RATE * PAUSE_GAPS_MS[index] // 1000)
    path = WORK / "pause.wav"
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(bytes(body))
    return path, phrases


def page_phrases(files):
    """`page.wav`'s phrases as `ttp.fixtures()` joins them: A, B, C cycled, each
    followed by 0.5 s of zeros, cut at 600 s; only phrases whose onset lies a
    second before the cut."""
    bodies = [frames(files[name]) for name in ("A", "B", "C")]
    total = 600 * RATE
    at, index, out = 0, 0, []
    while at < total:
        body = bodies[index % 3]
        found = phrase(at, body, ttp.PHRASES["ABC"[index % 3]])
        if found["onset"] < 599 * SEC:
            out.append(found)
        at += len(body) // 2 + 8000
        index += 1
    return out


def probe_package():
    """Media 20, a 20 s silent WAV, under clip 3 (0–20 s)."""
    WORK.mkdir(parents=True, exist_ok=True)
    wav = WORK / "silent-20.wav"
    if not wav.exists():
        with wave.open(str(wav), "wb") as out:
            out.setnchannels(1)
            out.setsampwidth(2)
            out.setframerate(RATE)
            out.writeframes(b"\0\0" * RATE * 20)
    body = {"version": 37,
            "canvas": {"width": 1920, "height": 1080, "fps": [30, 1], "timecode_frames": True},
            "media": [{"id": 20, "path": str(wav), "kind": "audio", "duration": 20 * SEC,
                       "has_audio": True}],
            "tracks": [{"id": 1, "name": "Track 1", "muted": False, "locked": False}],
            "clips": [{"id": 3, "track": 1, "start": 0, "duration": 20 * SEC,
                       "source": {"kind": "media", "media": 20, "in": 0, "reversed": False},
                       "enabled": {"video": True, "audio": True}}],
            "markers": [], "nests": [], "next_id": 100}
    path = WORK / "probe.framejob"
    shutil.rmtree(path, ignore_errors=True)
    path.mkdir(parents=True)
    (path / "project.json").write_text(json.dumps(body, indent=1))
    return path


# --------------------------------------------------------------------------
# The probe and mutation


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
        why = apply_edits(MUTANTS[mutant][1], here / "Sources")
        if why:
            return why
        sources = here / "Sources"
    shader, why = space_key_proof.build_shader(str(here))
    if shader is None:
        results.score("U0", False, f"the shader: {why}")
        return None
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "word-onset-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        results.score("U0", False, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8])))
        return None
    results.score("U0", True, f"built from {sources}")
    ran = bounded.run([str(binary), str(probe_package())], 300, cwd=str(here))
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
# The app rows


def device_words(session, media, language):
    """The stored run's words of `media` in `language`, in file order."""
    path = os.path.join(session.path, "cache", "device-transcripts", f"{media}-{language}.json")
    try:
        with open(path) as handle:
            runs = json.load(handle).get("runs") or []
    except (OSError, ValueError):
        return None
    return runs[0]["words"] if len(runs) == 1 else None


def first_word(words, item):
    """The tool's word spelled as `item`'s first word starting within 1 s of
    its onset, else None."""
    return next((w for w in words if spelled(w["text"]) == item["first_word"]
                 and abs(w["start"] - item["onset"]) < SEC), None)


def app_rows(results, wanted, app_path, files):
    import assistant_session_proof as sp
    import cloud_captions_probe
    import cloud_captions_proof as cloud
    import transcript_cut_proof as tcp

    os.makedirs(cloud.WORK, exist_ok=True)
    os.makedirs(sp.WORK, exist_ok=True)
    lock, _, holder = cloud_captions_probe.hold_cloud_lock(1800)
    if lock is None:
        for row in wanted:
            results.score(row, False, f"not run: the cloud instruments' lock is held by {holder}")
        return
    state, opened = {}, []

    def run(row, body):
        if row not in wanted:
            return
        try:
            ok, detail = body()
        except Exception as problem:  # noqa: BLE001 — a row's throw is its answer
            ok, detail = False, f"{type(problem).__name__}: {problem}; " + \
                traceback.format_exc(limit=2).splitlines()[-1]
        results.score(row, ok, detail)

    with contextlib.closing(lock), cloud_captions_probe.Fake("word-onset") as aai:
        app = stand_in = None
        try:
            stand_in = sp.Fake(str(WORK / "anthropic-fake"))
            app = sp.App("word-onset", app_path,
                         ["-RCSecretFolder", ttp.secret_folder(), "-RCAssemblyAIEndpoint", aai.base],
                         stand_in.base)
            app.connect()

            def fixture(name, path):
                """The fixture's project, read once: {session, media, clip, words,
                stored, want, voiced}."""
                if name in state:
                    return state[name]
                s = cloud.Session(app, f"onset-{name}")
                opened.append(s)
                media = s.media_of(str(path))
                clip = s.add(media, at=0)
                voiced = word_onsets.wait_voice(s.path, media)
                answer = s.op("get_timeline_transcript")
                language = next((m.get("language") for m in answer.get("media", [])
                                 if m["media"] == media), None)
                stored = device_words(s, media, language) or []
                speech, peaks = word_onsets.load(s.path, media)
                want = word_onsets.moved(stored, speech, peaks)
                state[name] = {"session": s, "media": media, "clip": clip, "voiced": voiced,
                               "words": answer.get("words", []), "answer": answer,
                               "stored": stored, "want": want}
                return state[name]

            def pause():
                if "pause_phrases" not in state:
                    state["pause_path"], state["pause_phrases"] = pause_fixture()
                return fixture("pause", state["pause_path"]), state["pause_phrases"]

            def within(words, phrases, skip_first=False):
                rows, missing = [], []
                for index, item in enumerate(phrases):
                    if skip_first and index == 0:
                        continue
                    word = first_word(words, item)
                    if word is None:
                        missing.append(index)
                        continue
                    rows.append((index, word["text"], round((word["start"] - item["onset"]) / 600, 1)))
                late = [r for r in rows if abs(r[2] * 600) > FRAME]
                return rows, missing, late

            def z1():
                complaints = [line for line in app.log().splitlines() if "Frame Job: " in line]
                return not complaints, f"parity lines {complaints[:3]}"
            run("Z1", z1)

            def o1():
                f, phrases = pause()
                rows, missing, late = within(f["words"], phrases)
                return (f["voiced"] and not missing and not late and len(rows) == 4,
                        f"caches {f['voiced']}; (phrase, word, start − onset ms) {rows}; "
                        f"not found {missing}; off by more than a frame {late}")
            run("O1", o1)

            def o2():
                out, bad = [], []
                for name in ("A", "B", "C"):
                    f = fixture(name, files[name])
                    item = phrase(0, frames(files[name]), ttp.PHRASES[name])
                    words = sorted(f["words"], key=lambda w: w["start"])
                    head = words[0] if words else None
                    error = None if head is None else round((head["start"] - item["onset"]) / 600, 1)
                    out.append((name, head and head["text"], error, f["voiced"]))
                    if (head is None or spelled(head["text"]) != item["first_word"]
                            or abs(head["start"] - item["onset"]) > FRAME or not f["voiced"]):
                        bad.append(name)
                return not bad, f"(file, first word, start − onset ms, caches) {out}; off {bad}"
            run("O2", o2)

            def o3():
                f = fixture("page", files["page"])
                phrases = page_phrases(files)
                rows, missing, late = within(f["words"], phrases, skip_first=True)
                errors = [r[2] for r in rows]
                return (f["voiced"] and not missing and not late and rows != [],
                        f"caches {f['voiced']}; {len(rows)} of {len(phrases) - 1} phrases after a "
                        f"gap found, start − onset {min(errors, default=None)}…"
                        f"{max(errors, default=None)} ms; not found {missing[:10]}; off by more "
                        f"than a frame {late[:10]}")
            run("O3", o3)

            def o4():
                out, bad = [], []
                names = [("pause", None), ("A", files["A"]), ("B", files["B"]),
                         ("C", files["C"]), ("page", files["page"])]
                for name, path in names:
                    f = pause()[0] if name == "pause" else fixture(name, path)
                    want = f["want"]
                    if not f["stored"] or want is None:
                        bad.append(f"{name}: stored {len(f['stored'])} words, moved {want is not None}")
                        continue
                    length = f["session"].clip(f["clip"])["duration"]
                    expected = sorted(
                        ((want[i], min(max(w["start"], w["end"]), length), i, w["text"], w["start"])
                         for i, w in enumerate(f["stored"]) if want[i] < length))
                    expected = [(text, start, end, source) for start, end, _, text, source in expected]
                    got = [(w["text"], w["start"], w["end"], w["id"]["source"]) for w in f["words"]]
                    moved = sum(1 for i, w in enumerate(f["stored"]) if want[i] != w["start"])
                    out.append(f"{name} {len(got)} words, {moved} moved")
                    if got != expected:
                        first = next((i for i, (g, e) in enumerate(zip(got, expected)) if g != e),
                                     min(len(got), len(expected)))
                        bad.append(f"{name}: {len(got)} vs {len(expected)}, first difference at "
                                   f"{first}: {got[first:first + 1]} vs {expected[first:first + 1]}")
                return not bad, "; ".join(out) + (" — " + "; ".join(bad) if bad else "")
            run("O4", o4)

            def o5():
                f, _ = pause()
                s = f["session"]
                s.op("select_inspector_tab", tab="transcript")
                shown = s.op("transcript_view", wait=60)
                tokens = [(t["text"], t["start"]) for t in shown.get("tokens", [])]
                tool = [(w["text"], w["start"]) for w in f["words"]]
                return tokens == tool and tokens != [], \
                    f"{len(tokens)} tokens, {len(tool)} words; equal {tokens == tool}"
            run("O5", o5)

            def o6():
                f, _ = pause()
                answer = f["session"].op("get_transcript", clip=f["clip"])
                got = [(w["text"], w["start"], w["end"]) for w in answer.get("words", [])]
                tool = [(w["text"], w["start"], w["end"]) for w in f["words"]]
                return (got == tool and got != [] and "notes" not in answer,
                        f"{len(got)} words, equal {got == tool}; keys {sorted(answer)}")
            run("O6", o6)

            def o7():
                f, phrases = pause()
                words = f["words"]
                out = []
                for index, item in enumerate(phrases):
                    nxt = first_word(words, phrases[index + 1]) if index + 1 < len(phrases) else None
                    at = words.index(nxt) - 1 if nxt in words else len(words) - 1
                    if 0 <= at < len(words):
                        out.append((index, words[at]["text"],
                                    round((words[at]["end"] - item["end"]) / 600, 1)))
                return True, f"(phrase, last word, end − phrase end ms) {out}"
            run("O7", o7)

            def cuts(words, phrases, gaps_ms):
                """C1's checks over one fixture: problems and a summary."""
                problems, rows, capped_rows = [], [], []
                for index in range(1, len(phrases)):
                    item = phrases[index]
                    word = first_word(words, item)
                    if word is None:
                        problems.append(f"phrase {index} not found")
                        continue
                    if word["cut_start"] > item["onset"]:
                        problems.append(f"phrase {index} cut_start {word['cut_start']} past its "
                                        f"onset {item['onset']}")
                    before = words[words.index(word) - 1] if words.index(word) > 0 else None
                    if before is None or gaps_ms[index - 1] > 1000:
                        continue
                    left = item["onset"] - before["cut_end"]
                    rows.append(round(left / 600, 1))
                    capped = before["end"] + SEC < word["start"]
                    if left > CUT_GAP and capped:
                        capped_rows.append((index, before["text"], before["end"],
                                            round(left / 600, 1)))
                    if before["cut_end"] > item["onset"] or (left > CUT_GAP and not capped):
                        problems.append(f"before phrase {index}: {before['text']} cut_end "
                                        f"{before['cut_end']}, onset {item['onset']}")
                return problems, rows, capped_rows

            def c1():
                f, phrases = pause()
                p_problems, p_rows, p_capped = cuts(f["words"], phrases, PAUSE_GAPS_MS)
                g = fixture("page", files["page"])
                page = page_phrases(files)
                g_problems, g_rows, g_capped = cuts(g["words"], page, [500] * len(page))
                return (not p_problems and not g_problems and p_rows and g_rows,
                        f"pause.wav onset − cut_end ms {p_rows}; page.wav {len(g_rows)} gaps, "
                        f"{min(g_rows, default=None)}…{max(g_rows, default=None)} ms; over 0.2 s only "
                        f"by the 1 s cap from an early recognised end (reported: phrase, word, "
                        f"end, ms) "
                        f"{p_capped + g_capped}; problems {(p_problems + g_problems)[:8]}")
            run("C1", c1)

            def c2():
                f, phrases = pause()
                s = f["session"]
                s.op("select_inspector_tab", tab="transcript")
                shown = s.op("transcript_view", wait=60)
                word = first_word(f["words"], phrases[1])
                if word is None:
                    return False, "the second phrase's first word was not found"
                index = next((t["index"] for t in shown.get("tokens", []) if t["id"] == word["id"]),
                             None)
                if index is None:
                    return False, f"{word['text']} is not a token"
                original = tcp.placements(s.project())
                s.op("transcript_view", focus=True, select=[index, index])
                s.op("perform_menu_item", path=["Edit", "Delete"])
                s.op("transcript_view", wait=30)
                tab = tcp.placements(s.project())
                undone = s.op("undo").get("undone")
                back = tcp.placements(s.project()) == original
                s.op("ripple_delete_ranges", ranges=[[word["cut_start"], word["cut_end"]]])
                tool = tcp.placements(s.project())
                return (undone == "Delete Words" and back and tab == tool and tab != original,
                        f"{word['text']} [{word['cut_start']}, {word['cut_end']}): undo names "
                        f"{undone!r}, back {back}; the tab's placements equal the tool's "
                        f"{tab == tool}")
            run("C2", c2)
        finally:
            for s in opened:
                with contextlib.suppress(Exception):
                    s.op("close_project", discard=True)
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
    why = apply_edits(MUTANTS[name][1], Path(root) / "app" / "Sources")
    if why:
        return None, why
    print(f"mutant {name}: building the copy (up to {sp.WALL_BUILD} s)…", flush=True)
    return tree_copy.build_app(root, sp.WALL_BUILD, env=sp.child_env())


def run_rows(wanted, mutant=None):
    results = ttp.Rows()
    probe_wanted = [r for r in wanted if r in PROBE_ROWS]
    app_wanted = [r for r in wanted if r in APP_ROWS]
    if probe_wanted:
        if "U0" not in probe_wanted:
            probe_wanted = ["U0"] + probe_wanted
        why = probe_rows(results, probe_wanted, mutant)
        if why:
            return None, why
    if app_wanted:
        import proof_app
        if mutant:
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
    named, _ = MUTANTS[name]
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
    scored = [r for r in ROWS if (r in wanted or r == "U0") and r not in REPORTED]
    ok = ttp.report(results, scored)
    for row in REPORTED:
        if row in results.results:
            print(f"{row} reported — {results.results[row][1]}")
    return 0 if ok else 1


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
