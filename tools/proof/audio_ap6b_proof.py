"""The leveller over MCP and exports (road map "audio" AP6 part 2, spec §11
AU-66, AU-67).

Usage: python3 tools/proof/audio_ap6b_proof.py <dir>/agent.sock

Every claim about sound is MEASURED on an exported WAV: loudness by
phase5_proof's BS.1770 (`integrated`), true peak by limiter_probe's two meters
(`true_peaks`), and the speech's short-term loudness range by this script's own
numpy over the fixture's KNOWN speech segments, by AU-67's definition (10 ms
K-weighted steps, 3 s windows at 0.1 s, EBU Tech 3342's gates, p95 − p10). A
gain is 10·log10 of Σout²/Σin² per 10 ms of the levelled export against the
same clip's export with the leveller null. Fixtures: audio_ap6b_probe.make_fixtures'
off-mic and steady `say` speech over a −60 dBFS bed, and the owner's
samples/Rode-usb-mic.m4a.

  P1  set_audio's leveller: {} stores the four defaults, a field merges, null
      clears; each bound and `threshold_db` refused by name, changing nothing;
      paste_attributes carries it; one undo takes it back.
  P2  the off-mic fixture, the leveller alone, 24-bit WAV: (a) the speech's
      range over WHOLE segments, starts included, out ≤ in − 5 LU; (b) each
      segment's first 0.5 s mean gain within ±3 dB of its settled gain (the
      median over [3 s, end − 0.5 s)); (c) each pause from 0.4 s in to 0.5 s
      before its end moves ≤ 0.1 dB; (d) over each whole pause the gain stays
      within the gains of the last 0.5 s before it and the first 0.5 s after
      it, ±0.5 dB. Every figure printed.
  P3  loudness_meter after play_preview 12 s from 0, then 8 s from 20 s (a
      seek), each within 0.01 LU of the export over the same frames (the
      seek's row absolute since spec §11 AU-161, #405).
  P4  enhance_voice on the off-mic fixture: the leveller on and its reason; the
      export at −16 ±0.5 LUFS and ≤ −1 dBTP; the last verify within 0.1 LU of
      −16; presses 2 and 3 "made no change".
  P5  the steady fixture: Enhance sets the leveller null and gives its reason;
      presses 2 and 3 "made no change"; three rounds of set_audio {volume: 1}
      then normalize_clip {mode: loudness} give processed_lufs equal within
      0.0005 LU, and equal to Enhance's.
  P6  the owner's recording: speech_range_lu, the leveller on or off and why,
      printed; the decision matches the rule; a second call "made no change".
  P7  the steady fixture levelled, an action over [21, 23) s taking the target
      0 → −6: against the same export with no action, the gain 0 ±0.05 dB
      before 21 s and −6 ±0.05 dB after 23 s.
  P8  an instance with the Leveler section open (`<false/>` in the argument
      domain only): snapshot_ui on audio.leveller shows its rows' labels
      (Target, Max Boost, Max Cut, Response, Status, Loudness) and the Status
      read-out "Aims at …"; then the clip split at 0.2 s and its first piece
      selected, the Status reads "Not leveling: it plays for under 0.4 s"
      (spec §11 #526 as extended by #541).
"""

import json
import math
import os
import sys
import time

import numpy as np

import audio_ap6b_probe as fixture
import audio_ap7_proof as ap7
import limiter_probe
import mcp as mcp_module
import phase5_proof as p5
import proof_app
from mcp import MCP, ToolError
from phase5_proof import Session, channels, integrated, pcm

RATE = 48000
SEC = 600_000
STEP = RATE // 100
DEFAULTS = {"target_db": 0.0, "max_up_db": 12.0, "max_down_db": 12.0, "response": 1200000}
RODE = os.path.join(os.path.dirname(os.path.dirname(p5.HERE)), "samples", "Rode-usb-mic.m4a")

checks = 0
failures = []


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)
    return ok


def f(x, places=2):
    return "None" if x is None else f"{x:.{places}f}"


def fixtures():
    fixture.make_fixtures(p5.FIXTURES)
    import subprocess
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", RODE, "-c:a", "pcm_s16le", "-ar",
                    str(RATE), "-ac", "1", os.path.join(p5.FIXTURES, "ap6b-rode.wav")],
                   check=True)


def ready(s, clip):
    """Waits for the clip's media's loudness and speech caches."""
    media = s.clip(clip)["source"]["media"]
    markers = [os.path.join(s.path, "cache", kind, f"{media}.complete.json")
               for kind in ("loudness", "speech")]
    p5.wait_for_files(markers, f"{s.name}: media {media}'s loudness or speech cache")
    return clip


def wav24(s, label):
    """An export's two channels as float64 (24-bit WAV, decoded by ffmpeg)."""
    result = s.op("export", preset="audio_wav", audio_bits=24,
                  path=os.path.join(p5.WORK, f"{s.name}-{os.getpid()}-{label}"))
    return limiter_probe.channels_of(result["path"]), result["path"]


def kweighted(chans):
    return [np.array(p5.biquad(p5.biquad(list(c), p5.STAGE1), p5.STAGE2)) for c in chans]


def steps(chans):
    """Each 10 ms step's Σ over the channels of the mean K-weighted square."""
    weighted = kweighted(chans)
    n = min(len(w) for w in weighted) // STEP * STEP
    return sum(np.mean(np.square(w[:n]).reshape(-1, STEP), axis=1) for w in weighted)


def loud(e):
    return -0.691 + 10 * np.log10(np.maximum(e, 1e-30))


def speech_range(energies, spans):
    """AU-67's range over the steps whose midpoints lie in `spans` (seconds)."""
    mids = (np.arange(len(energies)) + 0.5) / 100
    mask = np.zeros(len(energies), dtype=bool)
    for start, end in spans:
        mask |= (mids >= start) & (mids < end)
    e = energies[mask]
    windows = np.array([e[k:k + 300].mean() for k in range(0, len(e) - 300 + 1, 10)])
    passed = windows[loud(windows) >= -70]
    relative = loud(passed.mean()) - 20
    kept = np.sort(loud(passed[loud(passed) >= relative]))
    return float(np.percentile(kept, 95) - np.percentile(kept, 10))


def gains(wet, dry):
    """The gain per 10 ms, dB: 10·log10 of Σout²/Σin² over each step."""
    n = min(len(wet), len(dry)) // STEP * STEP
    out = np.sum(np.square(wet[:n]).reshape(-1, STEP), axis=1)
    into = np.sum(np.square(dry[:n]).reshape(-1, STEP), axis=1)
    return 10 * np.log10(np.maximum(out, 1e-30) / np.maximum(into, 1e-30))


def window_db(wet, dry, start, end):
    """The gain over [start, end) seconds: Σout²/Σin² over the span."""
    a, b = int(start * RATE), int(end * RATE)
    return 10 * math.log10(float(np.sum(np.square(wet[a:b]))) / float(np.sum(np.square(dry[a:b]))))


# ---- P1 ---------------------------------------------------------------------

def setting_rows(m):
    print("\nP1 — set_audio's leveller")
    s = Session(m, "ap6b-set")
    a = s.place("ap6b-steady.wav")
    b = s.place("ap6b-steady.wav", at=80 * SEC)
    s.op("set_audio", clips=[a], patch={"leveller": {}})
    check(s.clip(a)["audio"].get("leveller") == DEFAULTS,
          f"P1 {{}} stores the four defaults: {s.clip(a)['audio'].get('leveller')}")
    s.op("set_audio", clips=[a], patch={"leveller": {"target_db": -3, "max_up_db": 18}})
    held = s.clip(a)["audio"].get("leveller") or {}
    check(held.get("target_db") == -3 and held.get("max_up_db") == 18
          and held.get("response") == 1200000, f"P1 a field merges: {held}")
    audio = s.clip(a)["audio"]
    for patch, name in [({"leveller": {"target_db": -21}}, "audio.leveller.target_db"),
                        ({"leveller": {"target_db": 11}}, "audio.leveller.target_db"),
                        ({"leveller": {"max_up_db": 25}}, "audio.leveller.max_up_db"),
                        ({"leveller": {"max_down_db": -1}}, "audio.leveller.max_down_db"),
                        ({"leveller": {"response": 299999}}, "audio.leveller.response"),
                        ({"leveller": {"response": 6000001}}, "audio.leveller.response"),
                        ({"leveller": {"threshold_db": -25}}, "leveller.threshold_db"),
                        ({"leveller": {"attack": 3}}, "leveller.attack")]:
        text = s.error("set_audio", clips=[a], patch=patch) or ""
        check(name in text and "made no change" not in text,
              f"P1 {patch} refused naming {name}: {text[:110]!r}")
    check(s.clip(a)["audio"] == audio, "P1 and the refusals changed nothing")
    source = s.clip(a)
    s.op("paste_attributes", clips=[b], payload={"clips": [source], "media": []},
         groups=["audio"])
    check(s.clip(b)["audio"].get("leveller") == source["audio"]["leveller"],
          f"P1 paste_attributes carries it: {s.clip(b)['audio'].get('leveller')}")
    before = s.clip(a)["audio"]
    s.op("set_audio", clips=[a], patch={"leveller": None})
    check("leveller" not in s.clip(a)["audio"], "P1 null clears it")
    undone = s.undo()
    check(s.clip(a)["audio"] == before,
          f"P1 one undo ({undone!r}) puts it back: {s.clip(a)['audio'].get('leveller')}")
    m.call("close_project", project=s.path, discard=True)


# ---- P2, P3 -----------------------------------------------------------------

def offmic_rows(m):
    print("\nP2 — the off-mic fixture, the leveller alone")
    s = Session(m, "ap6b-offmic")
    clip = ready(s, s.place("ap6b-offmic.wav"))
    dry, _ = wav24(s, "dry")
    s.op("set_audio", clips=[clip], patch={"leveller": {}})
    wet, _ = wav24(s, "levelled")
    spans = fixture.segments(fixture.OFF_MIC_PEAKS)
    # One channel: the export is the mono fixture in both, and a range is a
    # difference, so the other channel's equal share changes nothing.
    before = speech_range(steps(dry[:1]), spans)
    after = speech_range(steps(wet[:1]), spans)
    check(after <= before - 5,
          f"P2 (a) the speech's range over whole segments {before:.2f} LU in, {after:.2f} LU out "
          f"(≤ in − 5)")
    g = gains(wet[0], dry[0])
    worst_start = 0.0
    for k, (start, end) in enumerate(spans):
        first = float(np.mean(g[int(start * 100):int((start + 0.5) * 100)]))
        settled = float(np.median(g[int((start + 3) * 100):int((end - 0.5) * 100)]))
        worst_start = max(worst_start, abs(first - settled))
        print(f"  note P2 segment {k + 1}: first 0.5 s {first:+.3f} dB, settled {settled:+.3f} dB")
    # ±3 dB (spec §11 AU-67 (e)): the window holds the glide's end on the bed
    # before each sentence's first word, and the sentences open louder than
    # their middles, which the curve follows; v1's carry-over (~12 dB) fails.
    check(worst_start <= 3, f"P2 (b) each segment's first 0.5 s within ±3 dB of its settled "
          f"gain: worst {worst_start:.3f} dB")
    worst_move, worst_out = 0.0, 0.0
    for k in range(len(spans) - 1):
        start, end = spans[k][1], spans[k + 1][0]
        inner = g[int((start + 0.4) * 100):int((end - 0.5) * 100)]
        move = float(inner.max() - inner.min())
        whole = g[int(start * 100):int(end * 100)]
        last = float(np.mean(g[int((start - 0.5) * 100):int(start * 100)]))
        nxt = float(np.mean(g[int(end * 100):int((end + 0.5) * 100)]))
        low, high = min(last, nxt) - 0.5, max(last, nxt) + 0.5
        out = max(0.0, low - float(whole.min()), float(whole.max()) - high)
        worst_move = max(worst_move, move)
        worst_out = max(worst_out, out)
        print(f"  note P2 pause {k + 1}: moves {move:.3f} dB from 0.4 s to 0.5 s before its end; "
              f"over the whole pause [{whole.min():+.3f}, {whole.max():+.3f}] dB against "
              f"{last:+.3f} before and {nxt:+.3f} after")
    check(worst_move <= 0.1, f"P2 (c) each pause from 0.4 s in to 0.5 s before its end moves "
          f"≤ 0.1 dB: worst {worst_move:.3f} dB")
    check(worst_out <= 0, f"P2 (d) each whole pause stays within the gains of the 0.5 s before "
          f"and after it, ±0.5 dB: worst {worst_out:.3f} dB outside")

    print("\nP3 — the live meter against the export")
    plays = ((0, 12), (20, 8))
    levelled = meter_plays(s, wet, plays)
    m.call("close_project", project=s.path, discard=True)
    # Both rows are absolute (spec §11 AU-161, #405): the player's filler at a
    # seek is a mark, none of its samples, so the seek's play starts at its
    # first audio. Before it this row was held against a control.
    label, got, long_enough, delta = levelled[0]
    check(long_enough and abs(delta) <= 0.01, f"P3 {label}: {got}; ΔI {delta:+.4f} LU (≤ 0.01)")
    label, got, long_enough, delta = levelled[1]
    check(long_enough and abs(delta) <= 0.01,
          f"P3 {label} (a seek): {got}; ΔI {delta:+.4f} LU (≤ 0.01)")


def meter_plays(s, export, plays):
    """`loudness_meter` after `play_preview` for each (from, seconds) in
    `plays`, in order, each against `export` over the frames it measured: (the
    play, the reading, whether it measured all but 2 s of the play, ΔI = live
    − export in LU, signed)."""

    def play(seconds):
        deadline = time.monotonic() + 60
        while True:
            try:
                return s.op("play_preview", seconds=seconds)
            except ToolError as error:
                if "nothing to play" not in str(error) or time.monotonic() > deadline:
                    raise
                time.sleep(0.5)

    rows = []
    for at, seconds in plays:
        s.op("set_playhead", t=at * SEC)
        s.op("loudness_meter", reset=True)
        play(seconds)
        got = s.op("loudness_meter")
        rate = got["sample_rate"] or RATE
        start = round(got["from_frame"] * RATE / rate) if got["from_frame"] is not None else 0
        end = round(got["to_frame"] * RATE / rate) if got["to_frame"] is not None else 0
        want = ap7.measure([list(export[0][start:end]), list(export[1][start:end])], p5)
        live = got["integrated_lufs"]
        delta = live - want["I"] if isinstance(live, (int, float)) and want["I"] is not None \
            else math.inf
        rows.append((f"{seconds} s from {at} s",
                     f"meter [{got['from_frame']}, {got['to_frame']}) I {live}, the export over "
                     f"the same frames I {ap7.fmt(want['I'])}",
                     end - start >= (seconds - 2) * RATE, delta))
    return rows


# ---- P4–P6 enhance ----------------------------------------------------------

def leveller_reason(row):
    return next((r for r in row["reasons"] if r.startswith("Leveler:")), "")


def presses_after(s, clip, label):
    """Presses 2 and 3: each must answer "made no change"."""
    for press in (2, 3):
        text = s.error("enhance_voice", clips=[clip]) or ""
        check("made no change" in text, f"{label} press {press}: {text[:80]!r}")


def enhance_rows(m):
    print("\nP4 — enhance_voice on the off-mic fixture")
    s = Session(m, "ap6b-enhance-offmic")
    clip = ready(s, s.place("ap6b-offmic.wav"))
    row = s.op("enhance_voice", clips=[clip])["enhanced"][0]
    reason = leveller_reason(row)
    print(f"  note P4 speech_range_lu {row.get('speech_range_lu')}; processed "
          f"{row.get('processed_lufs')}; result {row.get('result_lufs')} in {row.get('renders')} "
          f"renders; {reason}")
    check(row["set"].get("leveller") == DEFAULTS and "above 6 LU" in reason
          and s.clip(clip)["audio"].get("leveller") == DEFAULTS,
          f"P4 the leveller on at its defaults: {row['set'].get('leveller')}")
    path = s.export("enhanced")["path"]
    lufs = integrated(channels(pcm(path)))
    kaiser, annex = limiter_probe.true_peaks(path)
    check(lufs is not None and abs(lufs + 16) <= 0.5 and kaiser <= -1 + 0.001
          and annex <= -1 + 0.001,
          f"P4 the export at {f(lufs)} LUFS (−16 ±0.5), {f(kaiser, 4)} / {f(annex, 4)} dBTP (≤ −1)")
    result = row.get("result_lufs")
    check(result is not None and abs(result + 16) <= 0.1,
          f"P4 the last verify {f(result, 3)} LUFS, within 0.1 LU of −16")
    presses_after(s, clip, "P4")
    m.call("close_project", project=s.path, discard=True)

    print("\nP5 — the steady fixture")
    s = Session(m, "ap6b-enhance-steady")
    clip = ready(s, s.place("ap6b-steady.wav"))
    row = s.op("enhance_voice", clips=[clip])["enhanced"][0]
    reason = leveller_reason(row)
    enhanced = row.get("processed_lufs")
    print(f"  note P5 speech_range_lu {row.get('speech_range_lu')}; processed {enhanced}; "
          f"{reason}")
    check("leveller" in row["set"] and row["set"]["leveller"] is None
          and "at or under 6 LU, so the leveler is off" in reason,
          f"P5 the leveller null: {row['set'].get('leveller', 'absent')!r}")
    presses_after(s, clip, "P5")
    rounds = []
    for _ in range(3):
        s.op("set_audio", clips=[clip], patch={"volume": 1})
        got = s.op("normalize_clip", clips=[clip], mode="loudness")["normalized"][0]
        rounds.append(got.get("processed_lufs"))
    print(f"  note P5 processed_lufs: Enhance {enhanced}; Normalize {rounds}")
    numbers = [x for x in rounds + [enhanced] if isinstance(x, (int, float))]
    check(len(numbers) == 4 and max(numbers) - min(numbers) <= 0.0005,
          f"P5 three Normalize rounds' processed_lufs equal within 0.0005 LU and equal to "
          f"Enhance's: spread {f(max(numbers) - min(numbers), 5) if numbers else None} LU")
    m.call("close_project", project=s.path, discard=True)

    print("\nP6 — the owner's recording")
    s = Session(m, "ap6b-enhance-owner")
    clip = ready(s, s.place("ap6b-rode.wav"))
    row = s.op("enhance_voice", clips=[clip])["enhanced"][0]
    reason = leveller_reason(row)
    value = row["set"].get("leveller", "absent")
    rng = row.get("speech_range_lu")
    print(f"  note P6 speech_range_lu {rng}; leveller {json.dumps(value)}; {reason}")
    matches = rng is not None and ((rng > 6 and value == DEFAULTS)
                                   or (rng <= 6 and value is None))
    check(matches, f"P6 the decision matches the rule at {rng} LU: {value!r}")
    second = s.error("enhance_voice", clips=[clip]) or ""
    check("made no change" in second, f"P6 a second call: {second[:80]!r}")
    m.call("close_project", project=s.path, discard=True)


# ---- P7 an action's target --------------------------------------------------

def action_rows(m):
    print("\nP7 — an action taking the target 0 → −6")
    s = Session(m, "ap6b-action")
    clip = ready(s, s.place("ap6b-steady.wav"))
    s.op("set_audio", clips=[clip], patch={"leveller": {}})
    plain, _ = wav24(s, "no-action")
    s.op("add_action", clip=clip, at=21 * SEC, duration=2 * SEC)
    action = [a for a in s.clip(clip)["actions"] if a["start"] == 21 * SEC][0]["id"]
    s.op("set_action_end", clip=clip, action=action,
         patch={"audio": {"leveller": {"target_db": -6}}})
    acted, _ = wav24(s, "action")
    before = window_db(acted[0], plain[0], 12, 21)
    after = window_db(acted[0], plain[0], 23, 32)
    check(abs(before) <= 0.05 and abs(after + 6) <= 0.05,
          f"P7 against the export with no action: {before:+.3f} dB over [12, 21) s (0 ±0.05), "
          f"{after:+.3f} dB over [23, 32) s (−6 ±0.05)")
    m.call("close_project", project=s.path, discard=True)


# ---- P8 the section ---------------------------------------------------------

def section_rows():
    print("\nP8 — the Leveler section in snapshot_ui")
    launched = mcp_module.launch(
        proof_app.binary(), arguments=["-FrameJobInspectorSection.audio.leveller", "<false/>"])
    try:
        if not check(launched.client is not None, "P8 an instance with the section open comes up"):
            return
        s = Session(launched.client, "ap6b-section")
        clip = ready(s, s.place("ap6b-steady.wav"))
        s.op("set_audio", clips=[clip], patch={"leveller": {}})
        s.op("set_selection", clips=[clip])
        s.op("select_inspector_tab", tab="clip", sub_tab="sound", section="audio.leveller")

        def shown(prefix):
            """The visible texts once one starts with `prefix`, or the last ones read."""
            texts = []
            for _ in range(40):
                picture = os.path.join(p5.WORK, f"ap6b-section-{os.getpid()}.png")
                shot = s.op("snapshot_ui", window="editor", path=picture)
                with open(shot.get("layout_path") or "") as handle:
                    views = json.load(handle)["views"]
                texts = [v.get("text") or "" for v in views if not v.get("hidden")]
                if any(t.startswith(prefix) for t in texts):
                    break
                time.sleep(0.25)
            return texts

        texts = shown("Aims at")
        # The rows' labels (the check's title and the header's are drawn, not
        # dumped as text) and the Status read-out's part.
        rows = ["Target", "Max Boost", "Max Cut", "Response", "Status", "Loudness"]
        aims = next((t for t in texts if t.startswith("Aims at")), None)
        check(all(r in texts for r in rows) and aims is not None and "Holds Under" not in texts,
              f"P8 rows {[r for r in rows if r in texts]}; status {aims!r}")
        # A piece playing under 0.4 s has no loudness reading (AU-14), so its
        # Status is the unmeasurable sentence, whatever its speech.
        s.op("split", clips=[clip], at=SEC // 5)
        s.op("set_selection", clips=[clip])
        s.op("select_inspector_tab", tab="clip", sub_tab="sound", section="audio.leveller")
        texts = shown("Not level")
        short = next((t for t in texts if t.startswith("Not level")), None)
        played = s.clip(clip)["duration"]
        check(short == "Not leveling: it plays for under 0.4 s" and played == SEC // 5,
              f"P8 the first piece ({played} ticks) reads {short!r}")
        launched.client.call("close_project", project=s.path, discard=True)
    finally:
        launched.stop()


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    os.makedirs(p5.FIXTURES, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    only = sys.argv[2:]
    parts = {"P1": setting_rows, "P2": offmic_rows, "P4": enhance_rows, "P7": action_rows}
    for name, part in parts.items():
        if only and name not in only:
            continue
        try:
            part(m)
        except (ToolError, KeyError, IndexError, RuntimeError, OSError, ValueError,
                TypeError) as error:
            check(False, f"{part.__name__} aborted: {type(error).__name__}: {error}")
    if not only or "P8" in only:
        try:
            section_rows()
        except (ToolError, KeyError, IndexError, RuntimeError, OSError, ValueError) as error:
            check(False, f"section_rows aborted: {type(error).__name__}: {error}")
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for line in failures:
        print(f"  FAILED: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
