#!/usr/bin/env python3
"""Road map "creator-jobs" FC3 — sound events heard on the Mac (spec §11 FC-30…FC-34).

    python3 tools/proof/sound_events_proof.py [--only P1,E3,…] [--mutant NAME] [--app PATH]

The fixtures are made on first use under `tools/proof/work/sound-events-proof/
fixtures/` from `say` and ffmpeg: a speech recording (`speech.wav`, 48 kHz
mono), the same behind 2 s and behind 4 s of silence, its MP3 (libmp3lame, with the
LAME tag whose encoder delay `MP3Gapless.leadingTrim` reads), a movie of that
sound under a test picture, a picture with no sound, and three cuts of the
speech 9.0 s (12 hops), 9.1 s and 9.4 s long. Every row is a read-back: the
probe's own answer, a tool's answer, or the bytes of the cache's marker and
`windows.bin`.

**Probe rows** (`sound_events_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app): P1 `windows.bin`'s
round trip with NaN kept, two publishes in either order giving equal bytes, a
damaged file replaced and its coverage reset; P2 `ticks(of: k) == k × hop` to
10⁶, the count ⌈duration / hop⌉, `kind.grid(of:)` the hop grid; P3 the stamp
(version the table's, the sound queue, device `auto`, no vision, reader `raw`
with `color.log` set where faces' is `converted`, the parameters' keys); P4 the
MP3's `readWindow` read starting at `leadingTrim` + k0 hops, its first 2 s
against the WAV's at lag 0 ± 16 samples; P5 `SoundEvents.events` on a ×2 and a
ramped clip against `MediaPeaks.sourceTick` within 600 ticks, a reversed clip
none; P6 a run published every buffer and cancelled once four windows are
covered: one range from 0, every covered window answered, within 0.01 of a
whole run (FC-30: the values move in the third decimal under load); P7 two
half runs against a whole run within 0.01, NaN against a value a failure; P8
`soundEventsAnswer`'s decimals, nulls and cap; P9 the NaN tail — a cut-short
decode covers no tail, and a completed run over 9.0, 9.1 and 9.4 s of speech
covers every window, the overhanging ones NaN, and a whole lookup hits; P10 a
run at the default publish interval cancelled at half keeps its answered
prefix (spec §11 CJ-21 as amended by #435): one range from 0, short of the
end, every covered window answered, within 0.01 of a whole run.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`), on a scratch
`CFFIXED_USER_HOME`; Z1 is each launch's parity grep:
- E1 the speech onset (the first rising 0.5 crossing of `speech`) moves by
  2.000 s ± one hop with 2 s of silence prepended: the speech behind 2 s of
  silence against the same behind 4 s (a window's start can be no earlier
  than 0, so the first is not the bare speech, whose onset window starts at
  the file's first sample).
- E2 the MP3's and the WAV's onsets within one hop.
- E3 the movie's second call `cached` with `windows.bin` unchanged;
  `set_media_color {log: slog3}` keeps it cached; an mtime touch is a miss.
- E4 a window inside the coverage is a hit; `analysis_job` past it runs only
  the missing range, and the coverage becomes the union.
- E5 (hold 3 s) `close_project` while the job holds: outcome `cancelled`, no
  marker or payload.
- E6 the answer's rows equal `windows.bin` decoded here, at four places.
- E7 with `clip` on a ×2 clip trimmed 1 s in: `clip_time` = (source − in) / 2,
  `timeline` = start + `clip_time`.
- E8 the refusals: no sound, a reversed clip, `faces` on audio.
- E9 S-EV recall and E10 S-MU confusion: skipped by name, owed.
- E11 (hold 3 s) `sound_events` then `shots` on one movie: the shots job starts
  before the sound job ends.

`--mutant NAME`: the named decision broken in a copy — `app/Sources` copied
for the probe's rows, the tree copied and built (`tree_copy.py`) for the
app's — and only its rows run; CAUGHT (exit 0) when one of them fails,
SURVIVED (exit 1) otherwise.
"""

import argparse
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "creator_spike"))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import sound_deciders  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/sound-events-proof"
FIX = WORK.parent / "sound-events-fixtures"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
HOP = 450_000
HOP_S = 0.75
GROUPS = ["laughter", "applause", "cheering", "crowd", "music", "speech"]
HOLD = ["-RCDevAnalysisHold", "3"]
P_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10"]
PLAIN = ["E1", "E2", "E3", "E4", "E6", "E7", "E8", "E9", "E10"]
HELD = ["E5", "E11"]
ROWS = P_ROWS + PLAIN + HELD + ["Z1"]
TEXT = ("The quick brown fox jumps over the lazy dog. We recorded this sentence to measure when "
        "speech begins, and how long it carries on, before a short pause and a second sentence. "
        "Sound events are read per window of the recording, so a laugh or a round of applause can "
        "be found again later. This third sentence keeps talking for a while longer, so the file "
        "runs past twenty seconds and a second window of the media can be asked for on its own.")

MUTANTS = {
    "window-start": (["P2", "E6"], [(
        "app/Sources/AnalysisStamp.swift",
        "            return AnalysisGrid(hopTicks: SoundEvents.hopTicks, duration: media.duration)",
        "            return AnalysisGrid(hopTicks: SoundEvents.windowTicks, duration: media.duration)")]),
    "mp3-trim-skipped": (["P4"], [(
        "app/Sources/MediaImporter+Speech.swift",
        "                start: CMTimeAdd(trim, window.start), duration: window.duration)",
        "                start: window.start, duration: window.duration)")]),
    "early-publish": (["P6"], [(
        "app/Sources/AnalysisSoundEvents.swift",
        "                    if let through = covered.first?.upperBound {",
        "                    if let through = Optional(range.upperBound), !covered.isEmpty {")]),
    "cover-whole-range": (["P9", "P7"], [
        ("app/Sources/AnalysisSoundEvents.swift",
         "        if let decodedEnd, from <= range.upperBound {",
         "        if from <= range.upperBound {"),
        ("app/Sources/AnalysisSoundEvents.swift",
         "                if grid.ticks(of: k) + SoundEvents.windowTicks > decodedEnd { tail.append(k) }",
         "                tail.append(k)")]),
    "table-version": (["P3"], [
        ("app/Sources/AnalysisStamp.swift",
         "        case .soundEvents: return SoundEvents.tableVersion",
         "        case .soundEvents: return 1"),
        ("app/Sources/SoundEvents.swift",
         "    static let tableVersion = 1", "    static let tableVersion = 2")]),
    "cancel-unpublished-sound": (["P10"], [(
        "app/Sources/AnalysisSoundEvents.swift",
        "        guard let answered = prefix.covered.first else { return }\n",
        "        guard let answered = prefix.covered.first, answered.isEmpty else { return }\n")]),
    "sound-holds-picture": (["E11"], [(
        "app/Sources/AnalysisLane.swift",
        "        while running.keys.filter({ !$0.kind.usesSoundQueue }).count < width,",
        "        while running.count < width,")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def skip(name, why):
    if name in selected:
        print(f"  SKIP {name} {why}", flush=True)


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


# ---- fixtures ------------------------------------------------------------------

def run(command, timeout=300):
    subprocess.run(command, check=True, timeout=timeout, capture_output=True)


def ffmpeg(*args):
    run(["ffmpeg", "-y", "-v", "error", *map(str, args)])


def fixtures():
    """The fixtures by name, made when absent."""
    FIX.mkdir(parents=True, exist_ok=True)
    out = {name: FIX / name for name in (
        "speech.wav", "speech_lead2.wav", "speech_lead4.wav", "speech.mp3", "movie.mov", "picture.mov",
        "len_9.00.wav", "len_9.10.wav", "len_9.40.wav")}
    aiff = FIX / "speech.aiff"
    if not aiff.exists():
        run(["say", "-v", "Samantha", "-o", str(aiff), TEXT], timeout=120)
    if not out["speech.wav"].exists():
        ffmpeg("-i", aiff, "-ar", 48000, "-ac", 1, "-c:a", "pcm_s16le", out["speech.wav"])
    for name, lead in (("speech_lead2.wav", 2000), ("speech_lead4.wav", 4000)):
        if not out[name].exists():
            ffmpeg("-i", out["speech.wav"], "-af", f"adelay={lead}:all=1", "-ar", 48000, "-ac",
                   1, "-c:a", "pcm_s16le", out[name])
    if not out["speech.mp3"].exists():
        ffmpeg("-i", out["speech.wav"], "-c:a", "libmp3lame", "-b:a", "128k", out["speech.mp3"])
    if not out["movie.mov"].exists():
        ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x180:rate=30", "-i", out["speech.wav"],
               "-shortest", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac",
               out["movie.mov"])
    if not out["picture.mov"].exists():
        ffmpeg("-f", "lavfi", "-i", "testsrc=size=320x180:rate=30", "-t", 5, "-c:v", "libx264",
               "-pix_fmt", "yuv420p", out["picture.mov"])
    for name, samples in (("len_9.00.wav", 432_000), ("len_9.10.wav", 436_800),
                          ("len_9.40.wav", 451_200)):
        if not out[name].exists():
            ffmpeg("-i", out["speech.wav"], "-af", f"atrim=end_sample={samples}", "-c:a",
                   "pcm_s16le", out[name])
    return out


# ---- the probe rows ------------------------------------------------------------

def probe_rows(sources, fx):
    rows = [r for r in P_ROWS if r in selected]
    if not rows:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "sound_events_probe.swift", entry)
    binary = out / "sound-events-probe"
    try:
        swift_build.build(sources=[*swift_build.app_sources(sources), entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        for row in rows:
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    request = out / "request.json"
    request.write_text(json.dumps({
        "work": str(out / "run"), "wav": str(fx["speech.wav"]), "mp3": str(fx["speech.mp3"]),
        "movie": str(fx["movie.mov"]),
        "lengths": [str(fx[n]) for n in ("len_9.00.wav", "len_9.10.wav", "len_9.40.wav")]}))
    try:
        done = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                              timeout=900)
        answer = json.loads(done.stdout)
    except (subprocess.TimeoutExpired, ValueError) as error:
        for row in rows:
            check(row, False, f"the probe gave no answer: {error}")
        return
    by_id = {r["id"]: r for r in answer.get("rows", [])}
    for row in rows:
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def media(self, fixture, tag):
        copy = WORK / "media" / f"{tag}{Path(fixture).suffix}"
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixture, copy)
        return self.call("import_media", path=str(copy))["media"], copy

    def events(self, **arguments):
        """`get_media_analysis {kind: sound_events}`, called again while a call
        refuses at its wait's bound (what it covered is kept)."""
        for _ in range(30):
            try:
                return self.call("get_media_analysis", kind="sound_events", **arguments)
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        raise RuntimeError("the sound_events analysis did not finish in 30 calls")

    def folder(self):
        return self.path / "cache/analysis/sound_events"

    def marker(self, media):
        path = self.folder() / f"{media}.json"
        return json.loads(path.read_text()) if path.exists() else None

    def payload(self, media):
        path = self.folder() / str(media) / "windows.bin"
        return path.read_bytes() if path.exists() else None

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def decode(data):
    """`windows.bin` → [[six floats or None], …]."""
    assert data[:4] == b"FJSE", data[:4]
    version, record, count, groups = struct.unpack_from("<HHII", data, 4)
    assert (version, record, groups) == (1, 24, 6), (version, record, groups)
    assert len(data) == 16 + count * record
    out = []
    for k in range(count):
        values = struct.unpack_from("<6f", data, 16 + k * record)
        out.append([None if math.isnan(v) else v for v in values])
    return out


def onset(answer):
    windows = [(r["source"] / SEC, r["speech"]) for r in answer["windows"]]
    found = sound_deciders.crossings(windows, 0.5)
    return found[0] if found else None


def plain_rows(client, fx):
    doc = Doc(client, "events")
    keep = {}

    def e1():
        plain, _ = doc.media(fx["speech_lead2.wav"], "lead2")
        later, _ = doc.media(fx["speech_lead4.wav"], "lead4")
        a, b = doc.events(media=plain), doc.events(media=later)
        first, second = onset(a), onset(b)
        moved = second - first if first is not None and second is not None else None
        check("E1", moved is not None and abs(moved - 2.0) <= HOP_S + 1e-9
              and a["window"] == 900_000 and a["hop"] == HOP,
              f"speech onset behind 2 s of silence {first} s, behind 4 s {second} s: moved {moved} s (want "
              f"2.000 ± {HOP_S}); {a['count']} and {b['count']} windows")
    if "E1" in selected:
        attempt(e1, "E1")

    def e2():
        if "speech" not in keep:
            plain, _ = doc.media(fx["speech.wav"], "speech")
            keep["speech"] = (plain, doc.events(media=plain))
        mp3, _ = doc.media(fx["speech.mp3"], "speech-mp3")
        a, b = keep["speech"][1], doc.events(media=mp3)
        first, second = onset(a), onset(b)
        ok, misses, tolerated = sound_deciders.agreement(
            {"speech": [(r["source"] / SEC, r["speech"]) for r in a["windows"]]},
            {"speech": [(r["source"] / SEC, r["speech"]) for r in b["windows"]]}, HOP_S)
        check("E2", first is not None and second is not None
              and abs(second - first) <= HOP_S + 1e-9,
              f"onsets WAV {first} s, MP3 {second} s (want within {HOP_S}); every speech "
              f"crossing matched (FC-30's test) {ok}, {len(misses)} unmatched, "
              f"{len(tolerated)} tolerated; {a['count']} and {b['count']} windows")
    if "E2" in selected:
        attempt(e2, "E2")

    def e3():
        media, copy = doc.media(fx["movie.mov"], "movie")
        first = doc.events(media=media)
        bytes1 = doc.payload(media)
        second = doc.events(media=media)
        bytes2 = doc.payload(media)
        doc.call("set_media_color", media=media, color={"log": "slog3"})
        third = doc.events(media=media)
        stat = copy.stat()
        os.utime(copy, (stat.st_atime, stat.st_mtime + 10))
        fourth = doc.events(media=media)
        keep["movie"] = (media, fourth)
        reader = (second.get("stamp") or {}).get("reader")
        check("E3", first["cached"] is False and second["cached"] is True and bytes1 == bytes2
              and third["cached"] is True and fourth["cached"] is False and reader == "raw",
              f"cached {first['cached']}, {second['cached']} (bytes unchanged "
              f"{bytes1 == bytes2}, {len(bytes1 or b'')}), after slog3 {third['cached']} "
              f"(want true), after an mtime touch {fourth['cached']} (want false); reader "
              f"{reader}")
    if "E3" in selected:
        attempt(e3, "E3")

    def e4():
        media, _ = doc.media(fx["speech.wav"], "speech-e4")
        doc.events(media=media, to=6 * SEC)
        before = doc.marker(media)["coverage"]
        inside = doc.events(media=media, **{"from": SEC, "to": 4 * SEC})
        wanted = doc.client.call_with("analysis_job", {
            "project": str(doc.path), "media": media, "kind": "sound_events", "to": 15 * SEC})
        waited = doc.client.call_with("analysis_job", {"wait": 60})
        rows = [r for r in waited["jobs"] if r["media"] == media and r["kind"] == "sound_events"
                and r["project"] and os.path.realpath(r["project"]) == os.path.realpath(doc.path)]
        last = rows[-1] if rows else {}
        after = doc.marker(media)["coverage"]
        k6 = math.ceil(6 * SEC / HOP) - 1
        k15 = math.ceil(15 * SEC / HOP) - 1
        check("E4", before == [[0, k6]] and inside["cached"] is True
              and not wanted["wanted"]["hit"] and last.get("ranges") == [[k6 + 1, k15]]
              and last.get("outcome") == "landed" and after == [[0, k15]],
              f"coverage after 0–6 s {before} (want [[0, {k6}]]); 1–4 s cached "
              f"{inside['cached']}; analysis_job to 15 s ran {last.get('ranges')} (want "
              f"[[{k6 + 1}, {k15}]]), {last.get('outcome')}; coverage then {after} (want "
              f"[[0, {k15}]])")
    if "E4" in selected:
        attempt(e4, "E4")

    def e6():
        if "speech" not in keep:
            plain, _ = doc.media(fx["speech.wav"], "speech")
            keep["speech"] = (plain, doc.events(media=plain))
        media, answer = keep["speech"]
        stored = decode(doc.payload(media))
        rows = answer["windows"]
        picks = sorted({0, len(rows) // 3, 2 * len(rows) // 3, len(rows) - 1})
        bad = []
        for i in picks:
            r = rows[i]
            k = r["source"] // HOP
            want = [None if v is None else round(v, 4) for v in stored[k]]
            got = [r[g] for g in GROUPS]
            same = all((w is None and g is None) or (w is not None and g is not None
                                                     and abs(w - g) < 5e-5)
                       for w, g in zip(want, got))
            if r["source"] != k * HOP or not same or r["source"] % HOP:
                bad.append((r["source"], got, want))
        check("E6", len(picks) == 4 and not bad and len(rows) == answer["count"],
              f"{answer['count']} rows; at rows {picks} the answer against windows.bin "
              f"({len(stored)} windows): {len(bad)} differ {bad[:2]}")
    if "E6" in selected:
        attempt(e6, "E6")

    def e7():
        media, _ = doc.media(fx["movie.mov"], "movie-e7")
        track = doc.state()["tracks"][0]["id"]
        clip = doc.call("add_clip", track=track, media=media, at=0)["new_clips"][0]
        doc.call("trim_start", clip=clip, to=SEC)
        doc.call("set_speed", clip=clip, rate=2)
        placed = next(c for c in doc.state()["clips"] if c["id"] == clip)
        cin, start = placed["source"].get("in", 0), placed["start"]
        answer = doc.events(clip=clip)
        bad = [r["source"] for r in answer["windows"]
               if r["clip_time"] != round((r["source"] - cin) / 2)
               or r["timeline"] != start + r["clip_time"] or r["source"] < cin]
        check("E7", answer["count"] > 0 and not bad and answer.get("clip") == clip,
              f"in {cin}, start {start}, speed {placed.get('speed')}: {answer['count']} rows, "
              f"{len(bad)} off (source − in) / 2 or start + clip_time {bad[:3]}")
    if "E7" in selected:
        attempt(e7, "E7")

    def e8():
        said = []

        def refused(**arguments):
            try:
                doc.call("get_media_analysis", **arguments)
                return "answered"
            except mcp.ToolError as error:
                said.append(str(error))
                return str(error)
        picture, _ = doc.media(fx["picture.mov"], "picture")
        a = refused(media=picture, kind="sound_events")
        media, _ = doc.media(fx["movie.mov"], "movie-e8")
        track = doc.state()["tracks"][0]["id"]
        clip = doc.call("add_clip", track=track, media=media, at=600 * SEC)["new_clips"][0]
        doc.call("set_reversed", clip=clip, reversed=True)
        b = refused(clip=clip, kind="sound_events")
        audio, _ = doc.media(fx["speech.wav"], "speech-e8")
        c = refused(media=audio, kind="faces")
        want_a = f"Media {picture} has no sound, so it has no sound_events to find."
        want_b = (f"Clip {clip} plays in reverse, so its sound events are not read: its sound "
                  "plays backwards.")
        want_c = f"Media {audio} has no moving picture, so it has no faces to find."
        check("E8", want_a in a and want_b in b and want_c in c,
              f"no sound: {a!r}; reversed: {b!r}; faces on audio: {c!r}")
    if "E8" in selected:
        attempt(e8, "E8")

    skip("E9", "S-EV (the owner's labelled laughter, applause and cheering) is missing: "
         "recall per group at a threshold is owed")
    skip("E10", "S-MU (the owner talking over music) is missing: music confusion is owed")
    doc.close()


def held_rows(client, fx):
    def dev(**arguments):
        return client.call_with("analysis_job", arguments)

    def mine(answer, doc, media, kind):
        return [r for r in answer["jobs"] if r["media"] == media and r["kind"] == kind
                and r["project"] and os.path.realpath(r["project"]) == os.path.realpath(doc.path)]

    def e5():
        doc = Doc(client, "held-cancel")
        media, _ = doc.media(fx["movie.mov"], "held-cancel")
        wanted = dev(project=str(doc.path), media=media, kind="sound_events")
        doc.close()
        waited = dev(wait=10)
        rows = mine(waited, doc, media, "sound_events")
        outcome = rows[-1].get("outcome") if rows else None
        marker = (doc.folder() / f"{media}.json").exists()
        payload = (doc.folder() / str(media)).exists()
        check("E5", not wanted["wanted"]["hit"] and outcome == "cancelled" and not marker
              and not payload,
              f"outcome {outcome} (want cancelled); marker {marker}, payload folder {payload} "
              f"(want neither)")
    if "E5" in selected:
        attempt(e5, "E5")

    def e11():
        doc = Doc(client, "held-both")
        media, _ = doc.media(fx["movie.mov"], "held-both")
        dev(project=str(doc.path), media=media, kind="sound_events")
        dev(project=str(doc.path), media=media, kind="shots")
        waited = dev(wait=60)
        sound = (mine(waited, doc, media, "sound_events") or [{}])[-1]
        shots = (mine(waited, doc, media, "shots") or [{}])[-1]
        s_end, p_start = sound.get("ended_at"), shots.get("started_at")
        check("E11", s_end is not None and p_start is not None and p_start < s_end
              and sound.get("outcome") == "landed" and shots.get("outcome") == "landed",
              f"sound {sound.get('started_at')}…{s_end} ({sound.get('outcome')}), shots "
              f"started {p_start} ({shots.get('outcome')}): shots before the sound job ended "
              f"{p_start is not None and s_end is not None and p_start < s_end}")
        doc.close()
    if "E11" in selected:
        attempt(e11, "E11")


def launch(binary, arguments, tag):
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def app_rows(binary, fx):
    plans = [("plain", [], plain_rows, set(PLAIN)), ("held", HOLD, held_rows, set(HELD))]
    for tag, arguments, body, rows in plans:
        if not selected & rows:
            continue
        launched, log = launch(binary, arguments, tag)
        try:
            if launched.client is None:
                for row in selected & rows:
                    check(row, False, f"{tag}: the app did not listen")
                continue
            print(f"  {tag} instance PID {launched.child.pid}", flush=True)
            body(launched.client, fx)
        finally:
            launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace")
                     if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


# ---- mutants -------------------------------------------------------------------

def apply(root, name):
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(root) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return None


def mutant_sources(name):
    copy = WORK / "mutant-tree" / "app/Sources"
    shutil.rmtree(WORK / "mutant-tree", ignore_errors=True)
    shutil.copytree(ROOT / "app/Sources", copy)
    why = apply(WORK / "mutant-tree", name)
    return (None, why) if why else (copy, None)


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "sound-events-mutant"))
    if made is None:
        return None, reason
    why = apply(made, name)
    if why:
        return None, why
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0])
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if selected & set(PLAIN + HELD):
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    try:
        fx = fixtures()
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, OSError) as error:
        print(f"  FAIL fixtures: {error}")
        return 1
    sources = ROOT / "app/Sources"
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"FC3 — the {args.mutant} MUTANT ({', '.join(named)}: one must FAIL)", flush=True)
        if set(named) & set(P_ROWS):
            sources, why = mutant_sources(args.mutant)
            if why:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
        if set(named) & set(PLAIN + HELD):
            binary, why = mutant_app(args.mutant)
            if why:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
    else:
        print(f"FC3 — sound events on the Mac ({proof_app.config()} build)", flush=True)
    started = time.time()
    probe_rows(sources, fx)
    if selected & set(PLAIN + HELD):
        if binary is None:
            binary = proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary, fx)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else "")
          + f" ({time.time() - started:.0f} s)")
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
