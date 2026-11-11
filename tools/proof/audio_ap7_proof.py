"""The live loudness meter (road map "audio" AP7, spec §11 AU-70..AU-78, AU-161).

    python3 tools/proof/audio_ap7_proof.py --probe [--mutants] [--sources DIR]
    python3 tools/proof/audio_ap7_proof.py <dir>/agent.sock

`--probe` compiles `audio_ap7_probe.swift` as main.swift over app/Sources through
swift_build (a failed build is a scored failure) and runs it. No app, no ffmpeg.
Signals are written into sinks' rings as two or three tracks whose writes lead by
0, 2.7 and 13.4 ms, in chunks cycling 1920/512/4096 frames, consumed at rate 1:

  T1   Tech 3341 case 1 (20 s stereo 1 kHz at -23 dBFS): M, S, I -23.0 ±0.1.
  T2   case 2 (-33): M, S, I -33.0 ±0.1.
  T3   case 3, T4 case 4, T5 case 5: I -23.0 ±0.1.
  T6   case 9 (1.34 s at -20 / 1.66 s at -30, x5): S -23.0 ±0.1 at every 100 ms from 3 s.
  T7   case 12 (0.18 s at -20 / 0.22 s at -30, x25): M -23.0 ±0.1 at every 100 ms from 0.4 s.
  T8   true peak, Tech 3341 cases 15-19: fs/4 at 0° and 45°, fs/6 at 60°, fs/8 at 67.5°
       (analytic -6.02 dBFS), and fs/4 at 45° with every sample at 0 dBFS (+3.01 dBTP):
       each +0.2/-0.4 dB, every tone with a 20 ms raised-cosine fade-in; the rest of the
       3 x 4 grid is printed as `info`, not scored.
  T9   case 1 at 44.1 kHz (±0.1, and within 0.02 LU of 48 kHz) and fs/4 at 45° at 44.1 kHz.
  T10  the mix (a stereo tone under a 0.5 hold, mono noise under a 1 -> 0.25 ramp, the tone
       again, correlated, under a fade) against a fresh LoudnessMeter fed sum(env * x):
       |dI|, |dM|, |dS| <= 0.01 LU.
  T11  a +0.5 s seek resets `jump`; a rebuild 0.3 s behind (new sinks) and a pause resumed
       0.2 s behind neither reset nor double count: frames fed == to - from, I within 0.01;
       a seek as the player delivers it (each track a buffer of the old position first,
       one track a second one after another moved) resets exactly once, from the new frame.
  T12  a stalled track and a track past its last span are not waited on.
  T13  3 s unread overruns the ring: resets `overrun`, measuring goes on.
  T14  rate 2 measures nothing (M, S nil; I, TP held; measuring false); stop() holds M, S,
       I, TP, fires onReading once, empties the rings; a resume at x1 continues, no reset.
  T15  the bars: two correlated 0.5 sines read peak 1.0, a sine and its inverse 0, where
       the per-track sum reads 1.0.
  T16  a 0.3 s and a 1 s gap between two clips on one track, and on one of two tracks: no
       reset, frames fed == to - from, I within 0.01 LU of the reference with silence.
  T17  the tap (AU-161): a buffer with no duration (the player's filler) is a mark in the
       ring, its frame and length and none of its samples; a sourced buffer is audio; a
       buffer with no time is nothing; 63 fillers and then audio overrun nothing.
  T18  marks in the sum (AU-161), as the player was measured to deliver them: a seek's
       fillers in separate ticks reset once and the measurement starts at the first audio
       (3072 frames past the seek), a track whose audio starts 1024 frames later silent
       until it does; pause and continue (three fillers, audio 3072 and 7167 frames on) and
       a six-second pause whose 63 fillers a second stop drained do not reset, frames fed
       == to - from, I within 0.01 of the reference with silence in the gap; audio 5375
       frames past a stopped stream resets; a seek while paused or just before the stop,
       its marks drained by a stop, resets at the audio after it, forwards and backwards; a
       tick at rate 0 that took 8192 frames rendered ahead leaves a resume; a stream that
       ran on at x2, before or after a stop (or two), is not resumed.

`--mutants` runs the twenty-one mutants, each over its own copy of app/Sources, and scores
each killed when its named row fails. Output under tools/proof/work/audio-ap7-probe.

With a socket (an instance launched by `proof_app.py launch`), L1-L4 drive the real
player over MCP (L1-L3 described at `live_rows`). Exit 0 when every row passes.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/audio-ap7-probe"
ROWS = [f"T{n}" for n in range(1, 19)]

MUTANTS = [
    ("mono-in-one-channel", "T10", "LiveLoudness+Sum.swift",
     "right[o] += chunk.channels == 2 ? chunk.right[i] * gain : x",
     "right[o] += chunk.channels == 2 ? chunk.right[i] * gain : 0"),
    ("envelope-dropped", "T10", "LiveLoudness+Sum.swift",
     "let gain = Float(MediaPeaks.envelope(ramps, at: f * ReelTime.perSecond / Int64(rate)))",
     "let gain: Float = ramps == nil ? 1 : 1"),
    ("summed-by-arrival", "T10", "LiveLoudness+Sum.swift",
     "let origin = chunk.start",
     # each track's pending data laid from the reached frame, as it arrived, its times
     # ignored (clamped so the loop's range stays valid)
     "let origin = min(max(at + chunk.start - (lane.pending.first?.start ?? chunk.start), "
     "at - Int64(chunk.frames) + 1), limit - 1)"),
    ("jump-does-not-reset", "T11", "LiveLoudness+Sum.swift",
     "if !fresh { reset(.jump) }",
     "if false { reset(.jump) }"),
    ("frames-before-reached-counted", "T11", "LiveLoudness+Sum.swift",
     "guard chunk.end > reached else { return }",
     "if chunk.start < reached { self.reached = chunk.start }"),
    ("stall-guard-removed", "T12", "LiveLoudness+Sum.swift",
     "if owed < leading - Self.frames(Self.stallLag, rate) { continue }",
     "if false, owed < leading - Self.frames(Self.stallLag, rate) { continue }"),
    ("not-sounding-only-past-last-span", "T16", "LiveLoudness+Sum.swift",
     "spanFrames = track.sounding.map { LiveLoudness.frames($0, rate: rate) }",
     "spanFrames = track.sounding.isEmpty ? [] : [LiveLoudness.frames("
     "track.sounding[0].lowerBound..<track.sounding[track.sounding.count - 1].upperBound, "
     "rate: rate)]"),
    ("measured-at-any-rate", "T14", "LiveLoudness.swift",
     "guard playRate == 1 else {", "guard playRate > 0 else {"),
    ("short-term-over-4", "T6", "Loudness.swift",
     "static let shortTermSubBlocks = 30", "static let shortTermSubBlocks = 4"),
    ("tables-at-every-rate", "T9", "Loudness.swift",
     "if sampleRate == LoudnessMeter.requiredSampleRate {", "if sampleRate > 0 {"),
    ("bars-from-per-track-sum", "T15", "LiveLoudness.swift",
     "bars = live ? mixBars() : nil",
     "bars = live ? LevelMeterTrack.mix(meters, at: 0) : nil"),
    # AU-161
    ("filler-captured", "T17", "AudioTap.swift",
     "guard sourced else {", "guard sourced || true else {"),
    ("filler-unmarked", "T17", "AudioTap.swift",
     "meter.mark(start: first, frames: frames, sampleRate: Int(sampleRate))", "_ = first"),
    ("mark-reads-as-overrun", "T18", "LevelMeter.swift",
     "guard header.frames >= 0, header.frames <= Self.capacityFrames,",
     "guard header.frames > 0, header.frames <= Self.capacityFrames,"),
    ("mark-without-length", "T18", "LiveLoudness+Sum.swift",
     "lane.stream = chunk.streamEnd\n                end = chunk.streamEnd",
     "lane.stream = chunk.end\n                end = chunk.end"),
    ("awaiting-after-a-mark", "T18", "LiveLoudness+Sum.swift",
     "where !moved.contains(ObjectIdentifier(lane)) && lane.end == nil {",
     "where !moved.contains(ObjectIdentifier(lane)) {"),
    ("resume-asked-of-the-sum", "T18", "LiveLoudness+Sum.swift",
     "|| (!lane.resuming", "|| (true"),
    ("resume-after-another-rate", "T18", "LiveLoudness.swift",
     "lane.resuming = measured || lane.resuming", "lane.resuming = true"),
    ("stop-adopts-a-seek", "T18", "LiveLoudness.swift",
     "!continues(chunk.start, after: stream, rate: rate) {\n                    continue",
     "!continues(chunk.start, after: stream, rate: rate) {\n                    lane.stream = chunk.streamEnd"),
    ("tick-at-rest-drops-its-drain", "T18", "LiveLoudness.swift",
     "stop(holding: drained)", "stop()"),
    ("resume-through-another-rate", "T18", "LiveLoudness.swift",
     "item.lane.resuming = false", "_ = item"),
]


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/audio_ap7_probe.swift", entry)
    binary = out / "audio-ap7-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, name):
    """({row: passed}, problem, stdout); a row with any FAIL line failed."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=1800)
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
    problem = "" if result.returncode == 0 else f"exit {result.returncode}: {result.stderr[-400:]}"
    return rows, problem, result.stdout


def probe(sources):
    rows, problem, stdout = run(sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    sys.stdout.write(stdout)
    good = check("the probe exited 0", not problem, problem)
    missing = [row for row in ROWS if row not in rows]
    good &= check("every row T1..T18 ran", not missing, ", ".join(missing))
    passed = sum(1 for row in ROWS if rows.get(row))
    good &= passed == len(ROWS)
    print(f"\n{passed}/{len(ROWS)} rows passed")
    return 0 if good else 1


def mutants(sources, only=None):
    chosen = [m for m in MUTANTS if only is None or m[0] in only]
    killed = 0
    for name, row, file, old, new in chosen:
        tree = WORK / f"mutant-{name}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        path = tree / file
        text = path.read_text()
        if text.count(old) != 1:
            check(f"mutant {name}", False, f"anchor not found once in {file}")
            continue
        path.write_text(text.replace(old, new))
        rows, problem, _ = run(tree, f"mutant-{name}")
        if rows is None:
            check(f"mutant {name} ({row})", False, "did not build: " + problem)
            continue
        dead = rows.get(row) is False
        killed += dead
        check(f"mutant {name} killed by {row}", dead,
              f"{row} {'failed' if dead else 'passed' if rows.get(row) else 'did not run'}; "
              "failing rows: " + ", ".join(sorted(r for r, ok in rows.items() if not ok))
              + (f"; {problem}" if problem else ""))
    print(f"\n{killed}/{len(chosen)} mutants killed")
    return 0 if chosen and killed == len(chosen) else 1


# ---- L1-L4: the real player, over MCP -----------------------------------------

LIVE_WORK = ROOT / "tools/proof/work/audio-ap7"
SEC = 600_000


def live_rows(socket):
    """L1  `loudness_meter {reset}` (resets 1, `manual`), `play_preview` 8 s at x1 from 0
           over a stereo tone (a 1 s fade-in) on track 1 and mono noise on track 2 as
           two clips with a 0.4 s gap at 3.0-3.4 s; then `audio_wav` exported and
           measured over [from_frame, to_frame) with phase5_proof's BS.1770-4: |dI|,
           |dM| and |dS| (the last completed block and 3 s) <= 0.1 LU, |dTP| <= 0.2 dB;
           `resets` still 1 (the gap did not reset), `last_reset` manual, `measuring`
           false after the play.
       L2  reset, then `play_preview` 4 s from 4 s with `seek_to` 1 s: resets +1, `jump`,
           and I within 0.01 LU of L1's export over [from_frame, to_frame), 1.5 s or more
           (AU-161: on the tree before it the filler read 0.0654 LU low).
       L3  reset, then two plays of 2 s back to back from 1 s, and a third after 6 s
           paused (AU-161: it reset `jump` on the tree before it): no reset, from_frame
           kept, to_frame moved on each time; then `set_playhead` to 6 s while paused
           and a fourth play: resets +1, `jump`, from_frame within 0.5 s past 6 s.
       L4  `loudness_meter` in tools/list with `reset` described; the instance's log
           holds no `Frame Job: ` line."""
    sys.argv[1:] = [socket]  # phase5_proof reads its socket at import
    import phase5_proof as p5
    from mcp import MCP, ToolError

    results = []

    def row(name, good, detail):
        results.append(bool(good))
        print(("  ok   " if good else "  FAIL ") + f"{name}: {detail}")

    LIVE_WORK.mkdir(parents=True, exist_ok=True)
    tone = LIVE_WORK / "tone.wav"
    noise_a = LIVE_WORK / "noise-a.wav"
    noise_b = LIVE_WORK / "noise-b.wav"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                    "aevalsrc='0.25*sin(2*PI*440*t)|0.2*sin(2*PI*660*t)':s=48000:d=10",
                    "-c:a", "pcm_s16le", str(tone)], check=True)
    for path, seconds, seed in ((noise_a, 3, 7), (noise_b, 7, 11)):
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                        f"anoisesrc=d={seconds}:c=pink:a=0.15:seed={seed}:r=48000",
                        "-ac", "1", "-c:a", "pcm_s16le", str(path)], check=True)

    mcp = MCP(socket)
    p5.WORK = str(LIVE_WORK)
    p5.FIXTURES = str(LIVE_WORK)
    session = p5.Session(mcp, "ap7-live")
    try:
        track1 = session.tracks()[0]
        clip = session.place("tone.wav", at=0, track=track1)
        session.op("set_audio", clips=[clip], patch={"fade_in": SEC})
        track2 = session.add_track()
        session.place("noise-a.wav", at=0, track=track2)
        session.place("noise-b.wav", at=int(3.4 * SEC), track=track2)

        def meter(**kwargs):
            return session.op("loudness_meter", **kwargs)

        def play(seconds, **kwargs):
            deadline = time.monotonic() + 60
            while True:
                try:
                    return session.op("play_preview", seconds=seconds, **kwargs)
                except ToolError as error:
                    if "nothing to play" not in str(error) or time.monotonic() > deadline:
                        raise
                    time.sleep(0.5)

        # L1
        session.op("set_playhead", t=0)
        first = meter(reset=True)
        played = play(8)
        got = meter()
        rate = got["sample_rate"] or 48000
        start = round(got["from_frame"] * 48000 / rate) if got["from_frame"] is not None else 0
        end = round(got["to_frame"] * 48000 / rate) if got["to_frame"] is not None else 0
        _, data, _ = session.wav("l1")
        left, right = p5.channels(data)
        want = measure([left[start:end], right[start:end]], p5)
        diffs = {
            key: abs(got[name] - want[key]) if isinstance(got[name], (int, float))
            and want[key] is not None else float("inf")
            for key, name in (("I", "integrated_lufs"), ("M", "momentary_lufs"),
                              ("S", "short_term_lufs"), ("TP", "true_peak_dbtp"))}
        row("L1", first["resets"] >= 1 and first["last_reset"] == "manual"
            and end - start >= 7 * 48000 and diffs["I"] <= 0.1 and diffs["M"] <= 0.1
            and diffs["S"] <= 0.1 and diffs["TP"] <= 0.2 and got["resets"] == first["resets"]
            and got["last_reset"] == "manual" and got["measuring"] is False,
            f"played {played.get('from')}..{played.get('to')} ticks; meter [{got['from_frame']}, "
            f"{got['to_frame']}) at {got['sample_rate']} Hz, I {got['integrated_lufs']} M "
            f"{got['momentary_lufs']} S {got['short_term_lufs']} TP {got['true_peak_dbtp']}; "
            f"export I {fmt(want['I'])} M {fmt(want['M'])} S {fmt(want['S'])} TP "
            f"{fmt(want['TP'])}; |dI| {fmt(diffs['I'])} |dM| {fmt(diffs['M'])} |dS| "
            f"{fmt(diffs['S'])} |dTP| {fmt(diffs['TP'])}; resets {first['resets']} -> "
            f"{got['resets']} ({got['last_reset']}), measuring {got['measuring']}")

        # L2
        before = meter(reset=True)
        session.op("set_playhead", t=4 * SEC)
        play(4, seek_to=SEC)
        after = meter()
        rate = after["sample_rate"] or 48000
        start = round((after["from_frame"] or 0) * 48000 / rate)
        end = round((after["to_frame"] or 0) * 48000 / rate)
        sought = measure([left[start:end], right[start:end]], p5)["I"]
        seek_i = abs(after["integrated_lufs"] - sought) if isinstance(
            after["integrated_lufs"], (int, float)) and sought is not None else float("inf")
        row("L2", after["resets"] == before["resets"] + 1 and after["last_reset"] == "jump"
            and end - start >= 1.5 * 48000 and seek_i <= 0.01,
            f"a seek from about 6 s to 1 s: resets {before['resets']} -> {after['resets']} "
            f"({after['last_reset']}), meter [{after['from_frame']}, {after['to_frame']}) I "
            f"{after['integrated_lufs']}; export I {fmt(sought)}; |dI| {fmt(seek_i)} (<= 0.01)")

        # L3
        before = meter(reset=True)
        session.op("set_playhead", t=SEC)
        play(2)
        one = meter()
        play(2)
        two = meter()
        # Long enough for the player to stop handing the taps its fillers (about 5.3 s).
        time.sleep(6)
        play(2)
        three = meter()
        # A seek made while paused is not a resume (AU-161 (c)): no reset asked for,
        # a second for the seek to land and the player's fillers to reach the taps.
        session.op("set_playhead", t=6 * SEC)
        time.sleep(1)
        play(2)
        four = meter()
        rate = four["sample_rate"] or 48000
        row("L3", one["resets"] == before["resets"] == two["resets"] == three["resets"]
            and one["from_frame"] is not None
            and two["from_frame"] == one["from_frame"] == three["from_frame"]
            and (three["to_frame"] or 0) > (two["to_frame"] or 0) > (one["to_frame"] or 0)
            and four["resets"] == three["resets"] + 1 and four["last_reset"] == "jump"
            and 6 * rate <= (four["from_frame"] or 0) <= 6.5 * rate
            and (four["to_frame"] or 0) - (four["from_frame"] or 0) >= 1.5 * rate,
            f"resets {before['resets']}, {one['resets']}, {two['resets']}, after 6 s paused "
            f"{three['resets']} ({three['last_reset']}); from {one['from_frame']}, "
            f"{two['from_frame']}, {three['from_frame']}; to {one['to_frame']}, "
            f"{two['to_frame']}, {three['to_frame']}; then a seek to 6 s while paused and a "
            f"play: resets {four['resets']} ({four['last_reset']}), meter "
            f"[{four['from_frame']}, {four['to_frame']})")

        # L4
        listed = mcp.schemas()
        schema = listed.get("loudness_meter", {}).get("inputSchema", {}).get("properties", {})
        log = Path(socket).parent / "framejob.log"
        complaints = [line for line in log.read_text(errors="replace").splitlines()
                      if "Frame Job: " in line] if log.exists() else ["no log"]
        row("L4", "loudness_meter" in listed and "description" in schema.get("reset", {})
            and not complaints,
            f"listed {'loudness_meter' in listed}, reset described "
            f"{'description' in schema.get('reset', {})}; log {log}: "
            f"{len(complaints)} complaint line(s) {complaints[:2]}")
    finally:
        try:
            session.op("close_project")
        except ToolError:
            pass
    passed = sum(results)
    print(f"\n{passed}/{len(results)} rows passed")
    return 0 if passed == len(results) == 4 else 1


def fmt(value):
    return "None" if value is None else f"{value:.4f}"


def measure(channels, p5):
    """BS.1770-4 over the slice as the meter saw it: K-weighting from rest at its
    first frame, 100 ms sub-blocks from there; I gated, M the last completed
    400 ms block, S the last 3 s, TP phase5_proof's 4x true peak in dBTP."""
    hop = 4800
    weighted = [p5.biquad(p5.biquad(c, p5.STAGE1), p5.STAGE2) for c in channels]
    length = min(len(c) for c in weighted)
    subs = []
    for start in range(0, length - hop + 1, hop):
        subs.append(sum(w[i] * w[i] for w in weighted for i in range(start, start + hop)))
    blocks = [sum(subs[b:b + 4]) / (4.0 * hop) for b in range(len(subs) - 3)]
    gated = [m for m in blocks if p5.loudness_of(m) > p5.ABSOLUTE_GATE]
    integrated = None
    if gated:
        threshold = p5.loudness_of(sum(gated) / len(gated)) + p5.RELATIVE_GATE
        kept = [m for m in gated if p5.loudness_of(m) > threshold]
        integrated = p5.loudness_of(sum(kept) / len(kept)) if kept else None
    return {
        "I": integrated,
        "M": p5.loudness_of(blocks[-1]) if blocks else None,
        "S": p5.loudness_of(sum(subs[-30:]) / (30.0 * hop)) if len(subs) >= 30 else None,
        "TP": p5.db(p5.true_peak(channels)),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--only", help="with --mutants: comma-separated mutant names")
    args = parser.parse_args()
    if args.probe:
        if not args.mutants:
            return probe(args.sources)
        return mutants(args.sources, args.only.split(",") if args.only else None)
    if not args.socket:
        parser.error("pass --probe, or the running instance's socket path")
    return live_rows(args.socket)


if __name__ == "__main__":
    sys.exit(main())
