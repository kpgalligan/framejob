#!/usr/bin/env python3
"""Road map "creator-jobs" TX3a, spike TX-S3 — cut edges (decides TX-30's rule).

    python3 tools/proof/transcript_spike/cut_spike.py

Fixtures: (1) `say` phrases (`fill_spike.PHRASES`, cycled) joined by digital
silences of 60, 120, 250, 500 and 1,000 ms, each length four times, so 20
boundaries; a phrase's true onset is its offset in the file plus its own
file's first sample over −40 dBFS, its true end its last such sample. (2) the
owner's o2, `tools/proof/media/filler-sample/test-recording.aifc`. (3) S-TH1
and S-RT1 under `tools/proof/media/creator/<id>/` — absent, each is skipped by
name and owed.

Words and caches come from the app (`proof_app` chooses it; `make app-debug`
first): one instance on a scratch socket, each fixture imported into a
scratch project and placed at 0 at ×1, `get_timeline_transcript` read (this
Mac's recogniser, whole file), and the package's `cache/speech/<id>.bin` and
peaks read by `cut_spike.swift` through `MediaImporter.loadSpeech` and
`loadPeaks`, which runs `TranscriptCut.sourceOnsets` under E0, E1 and E2 at
G 0, 32, 64 and 96 ms.

Measured: on (1), per boundary, the first word of the phrase after it (the
word spelled as the phrase's first word whose E1-corrected start lies within
1 s of the phrase's true onset — position alone misleads, since on-device
words tile the audio and a phrase's last word runs on into the silence):
clipped (onset > true onset) and the error (onset − true onset, ms). On (2) and (3): every
word's onset after the first, the share in voice-cache non-speech and under
−40 dBFS in the peak cache; for E2 also the same over the edges a run placed
(`from_run`: the onset moved off E1's), the share the rule's "keeps" reads.

Rule (the road map's, `rule_sha256` in CJ0a's table): E2 with the smallest
guard that clips no onset on (1) and keeps at least 95 % of real-speech edges
in non-speech; else E1 if it clips none on (1); else E0, with JOB-11 the only
judge. Results: `tools/proof/work/creator_spike/TX-S3/results.json`; once
S-TH1 is read (road map CJ7: `IMG_0181.MOV` by `sth1.movie()`, an S-RT1 file
by suffix, movie first, never `notes.txt`), `TX-S3-STH1/results.json`.
"""

import json
import shutil
import struct
import subprocess
import sys
import time
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
PROOF = HERE.parent
ROOT = PROOF.parents[1]
sys.path.insert(0, str(PROOF))
sys.path.insert(0, str(PROOF / "creator_spike"))
sys.path.insert(0, str(HERE))
import fill_spike  # noqa: E402 — the phrases
import mcp  # noqa: E402
import proof_app  # noqa: E402
import rule  # noqa: E402
import swift_build  # noqa: E402

SPIKE = "TX-S3"
WORK = ROOT / "tools/proof/work/transcript_spike/cut"
SILENCES_MS = [60, 120, 250, 500, 1000]
ROUNDS = 4
O2 = ROOT / "tools/proof/media/filler-sample/test-recording.aifc"
OWNER = {"S-TH1": ROOT / "tools/proof/media/creator/S-TH1",
         "S-RT1": ROOT / "tools/proof/media/creator/S-RT1"}
RULES = ["E0", "E1", "E2-0", "E2-32", "E2-64", "E2-96"]
GUARDS = {"E2-0": 0, "E2-32": 32, "E2-64": 64, "E2-96": 96}
SEC = 600_000
RATE = 16000
LOUD = 327.68  # −40 dBFS of 16-bit full scale


def audible(body):
    """(first, last) sample index over −40 dBFS in 16-bit mono `body`."""
    samples = struct.unpack(f"<{len(body) // 2}h", body)
    loud = [i for i, s in enumerate(samples) if abs(s) > LOUD]
    return (loud[0], loud[-1]) if loud else (0, len(samples) - 1)


def joined_fixture():
    """WORK/joined.wav and its phrases: [{onset, end}] in ticks."""
    bodies = fill_spike.say_phrases()
    gaps = [ms for _ in range(ROUNDS) for ms in SILENCES_MS]
    body, phrases, gap_before = bytearray(), [], []
    for index in range(len(gaps) + 1):
        phrase = bodies[index % len(bodies)]
        first, last = audible(phrase)
        at = len(body) // 2
        phrases.append({"onset": round((at + first) * SEC / RATE),
                        "end": round((at + last + 1) * SEC / RATE),
                        "first_word": fill_spike.PHRASES[index % len(bodies)].split()[0]})
        body += phrase
        if index < len(gaps):
            gap_before.append(gaps[index])
            body += b"\0\0" * (RATE * gaps[index] // 1000)
    path = WORK / "joined.wav"
    WORK.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(bytes(body))
    return path, phrases, gap_before


def build():
    entry = WORK / "main.swift"
    shutil.copyfile(HERE / "cut_spike.swift", entry)
    binary = WORK / "cut-spike"
    swift_build.build(sources=[*swift_build.app_sources(), entry], output=binary)
    return binary


def read_fixture(client, path, tag):
    """(package, media id, engine, words) of `path` placed at 0 at ×1, its
    voice cache waited for."""
    package = WORK / f"{tag}.framejob"
    shutil.rmtree(package, ignore_errors=True)
    client.call("new_project", path=str(package))

    def call(tool, **arguments):
        return client.call_with(tool, dict(arguments, project=str(package)))

    media = call("import_media", path=str(path))["media"]
    track = call("get_project")["project"]["tracks"][0]["id"]
    call("add_clip", track=track, media=media, at=0)
    speech = package / "cache" / "speech" / f"{media}.bin"
    deadline = time.time() + 300
    while time.time() < deadline and not speech.exists():
        time.sleep(0.5)
    time.sleep(1)
    answer = call("get_timeline_transcript")
    call("save_project")
    call("close_project")
    words = answer.get("words", [])
    engine = words[0]["engine"] if words else "apple"
    return package, media, engine, words


def onsets(binary, package, media, engine, words, tag):
    request = WORK / f"{tag}-request.json"
    out = WORK / f"{tag}-out.json"
    request.write_text(json.dumps({
        "cache": str(package / "cache"), "media": media, "engine": engine,
        "words": [{"text": w["text"], "source": w["start"], "source_end": w["end"]}
                  for w in words]}))
    run = subprocess.run([str(binary), str(request), str(out)], capture_output=True, text=True,
                         timeout=600)
    if run.returncode != 0:
        raise SystemExit(f"cut-spike {tag}: rc {run.returncode}: {run.stderr[-400:]}")
    return json.loads(out.read_text())


def boundaries(answer, words, phrases, gaps, lead):
    """Per rule, per boundary: the first word of the phrase after it."""
    out = {}

    def spelled(text):
        return "".join(c for c in text.lower() if c.isalnum())
    starts = [w["start"] + lead for w in words]
    for name in RULES:
        rows = []
        for k in range(1, len(phrases)):
            onset = phrases[k]["onset"]
            want = spelled(phrases[k]["first_word"])
            index = next((i for i, s in enumerate(starts)
                          if spelled(words[i]["text"]) == want and abs(s - onset) < SEC), None)
            if index is None:
                rows.append({"boundary": k, "gap_ms": gaps[k - 1], "word": None})
                continue
            edge = answer["rules"][name]["onsets"][index]
            rows.append({"boundary": k, "gap_ms": gaps[k - 1], "word": words[index]["text"],
                         "edge": edge, "true_onset": onset,
                         "previous_end": phrases[k - 1]["end"],
                         "clipped": edge > onset, "error_ms": round((edge - onset) / 600, 1)})
        out[name] = rows
    return out


def shares(answer):
    """Per rule: shares of onsets (after the first) in non-speech and quiet."""
    out = {}
    for name in RULES:
        row = answer["rules"][name]
        pairs = list(zip(row["nonspeech"], row["quiet"]))[1:]
        runs = row.get("from_run", [True] * len(row["nonspeech"]))[1:]
        known = [p for p in pairs if p[0] is not None]
        placed = [p for p, r in zip(pairs, runs) if r and p[0] is not None]

        def share(items, at):
            values = [i[at] for i in items if i[at] is not None]
            return round(sum(values) / len(values), 4) if values else None
        out[name] = {"edges": len(pairs), "nonspeech": share(known, 0), "quiet": share(pairs, 1),
                     "run_edges": len(placed), "run_nonspeech": share(placed, 0),
                     "run_quiet": share(placed, 1)}
    return out


def verdict(fixture, real):
    """The rule, applied: (rule, why)."""
    def clips(name):
        return sum(1 for row in fixture[name] if row.get("clipped") or row.get("word") is None)
    for name in ["E2-0", "E2-32", "E2-64", "E2-96"]:
        keeps = [r[name]["run_nonspeech"] for r in real.values()]
        if clips(name) == 0 and keeps and all(k is not None and k >= 0.95 for k in keeps):
            return name, f"{name}: no clipped onset on (1), run edges in non-speech {keeps}"
    if clips("E1") == 0:
        return "E1", "no E2 guard met both; E1 clips no onset on (1)"
    return "E0", "neither E2 nor E1 met the rule; E0, JOB-11 the only judge"


MOVIE_SUFFIXES = (".mov", ".mp4", ".m4v")
AUDIO_SUFFIXES = (".wav", ".aif", ".aiff", ".aifc", ".m4a", ".mp3", ".caf")


def owner_file(name, folder):
    """The owner's recording in `folder`, picked by suffix: S-TH1's movie is
    `sth1.movie()` (`IMG_0181.MOV`, never its side-on add-on); otherwise the
    first movie, else the first audio file; never `notes.txt` (road map CJ7)."""
    if name == "S-TH1":
        import sth1
        return sth1.movie()
    files = sorted(folder.iterdir()) if folder.is_dir() else []
    for suffixes in (MOVIE_SUFFIXES, AUDIO_SUFFIXES):
        found = [p for p in files if p.suffix.casefold() in suffixes]
        if found:
            return found[0]
    return None


def main():
    WORK.mkdir(parents=True, exist_ok=True)
    rule.check_rule(SPIKE)
    path, phrases, gaps = joined_fixture()
    binary = build()
    app = proof_app.binary()
    launched = mcp.launch(app, timeout=900)
    if launched.client is None:
        raise SystemExit(f"the app did not come up: {launched.log_path}")
    try:
        package, media, engine, words = read_fixture(launched.client, path, "joined")
        joined = onsets(binary, package, media, engine, words, "joined")
        fixture = boundaries(joined, words, phrases, gaps, joined["lead"])
        real, skipped = {}, {}
        if O2.exists():
            package, media, engine, o2_words = read_fixture(launched.client, O2, "o2")
            real["o2"] = shares(onsets(binary, package, media, engine, o2_words, "o2"))
            real["o2"]["words"] = len(o2_words)
        else:
            skipped["o2"] = f"{O2} is absent"
        for name, folder in OWNER.items():
            recording = owner_file(name, folder)
            if recording is None:
                skipped[name] = f"{folder} holds no recording: owed"
                continue
            package, media, engine, owner_words = read_fixture(launched.client, recording, name)
            real[name] = shares(onsets(binary, package, media, engine, owner_words, name))
            real[name]["words"] = len(owner_words)
    finally:
        launched.stop()
    chosen, why = verdict(fixture, {k: v for k, v in real.items()})
    summary = {name: {"clipped": sum(1 for r in rows if r.get("clipped")),
                      "unmatched": sum(1 for r in rows if r.get("word") is None),
                      "max_error_ms": max((r["error_ms"] for r in rows if "error_ms" in r),
                                          default=None),
                      "min_error_ms": min((r["error_ms"] for r in rows if "error_ms" in r),
                                          default=None)}
               for name, rows in fixture.items()}
    results = {"verdict": chosen, "why": why, "fixture_summary": summary,
               "fixture_boundaries": fixture, "real": real, "skipped": skipped,
               "silences_ms": SILENCES_MS, "rounds": ROUNDS, "app": str(app),
               "joined_words": len(words), "guards_ms": GUARDS}
    if "S-TH1" in real:
        import sth1
        results.update(sth1.record())
    out = rule.write_results(SPIKE, results, folder="TX-S3-STH1" if "S-TH1" in real else None)
    for name in RULES:
        print(f"{name}: (1) {summary[name]}; real "
              + "; ".join(f"{k} {v[name]}" for k, v in real.items()))
    for name, why_skipped in skipped.items():
        print(f"SKIP {name}: {why_skipped}")
    print(f"verdict: {chosen} — {why}")
    print(f"results: {out}")


if __name__ == "__main__":
    main()
