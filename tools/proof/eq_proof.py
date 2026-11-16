"""The EQ, hum notch and channel pick over MCP (road map "audio" AP3, spec §11
AU-31..AU-35, AU-37).

Usage: python3 tools/proof/eq_proof.py <dir>/agent.sock

Every response is MEASURED on an exported WAV against the analytic response
`eq_probe.py`'s numpy RBJ computes from the parameters, never read back from
the app alone.

  E1  set_audio's eq, hum and channels round-trip; each bound and an unknown
      key is refused by name and changes nothing; null clears; {eq:
      {high_pass: {}}} stores the slot's defaults.
  E2  a stepped sine (S1's 20 log-spaced 20 Hz–20 kHz) through (a) HP24 + low
      shelf + three bells + high shelf + LP24 and (b) HP12 + LP12: each step's
      level against the dry export's within ±0.1 dB of the analytic product,
      wherever that is ≥ −60 dB.
  E3  hum 60 Hz × 4 at 30 dB and 50 Hz × 8 at 48 dB: −depth ±0.1 dB at each
      harmonic, and within ±0.1 dB of analytic at k·f0 ± f0/20.
  E4  left, right and swapped exports sample-identical to the dry export's
      channel; mono with left equals the left channel.
  E5  a stereo file with the voice on the left only: normalize_clip's
      measured_lufs with left = both + 3.01 (±0.05), and each normalised export
      at −16 ±0.5 LUFS by phase5_proof's BS.1770.
  E6  right-only then left-only abutting, noise reduction on a later clip: the
      tone's onset at the cut ±1 ms (the head stages looked up 10.7 ms ahead,
      AU-34), not 10.7 ms late.
  E7  the saved file is at the header's version, the keys only where set, and
      set-then-cleared exports the same bytes as never set.
  E8  reported: the owner's recording through the three presets — the pause
      floor and the octave band levels, dry against wet.
"""

import json
import math
import os
import subprocess
import sys
import wave

import numpy as np

import eq_probe
import limiter_proof
import phase5_proof as p5
from mcp import MCP, ToolError
from phase5_proof import Session, channels, integrated, pcm

RATE = 48000
RODE = eq_probe.RODE
checks = 0
failures = []


def check(ok, what):
    global checks
    checks += 1
    print(("  ok   " if ok else "  FAIL ") + what)
    if not ok:
        failures.append(what)
    return ok


def write_wav(name, left, right):
    """A 16-bit stereo 48 kHz WAV under phase 5's fixtures."""
    os.makedirs(p5.FIXTURES, exist_ok=True)
    stereo = np.stack([left, right], axis=1)
    ints = np.clip(np.round(stereo * 32767), -32768, 32767).astype("<i2")
    with wave.open(os.path.join(p5.FIXTURES, name), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(RATE)
        handle.writeframes(ints.tobytes())


GRID = np.geomspace(20, 20000, 20)
STEP = RATE  # one second per tone
# Two seconds per hum tone: a notch's pole bandwidth is f0/10 (AU-33), so its
# ringing decays with a time constant of about 64 ms, and at 48 dB deep the
# ringing at 0.5 s still sits about 20 dB under the notched tone itself.
HUM_STEP = 2 * RATE
HUM_CASES = [(60, 30.0, 4), (50, 48.0, 8)]


def hum_freqs(f0, harmonics):
    out = []
    for k in range(1, harmonics + 1):
        out += [k * f0, k * f0 - f0 / 20, k * f0 + f0 / 20]
    return out


def stepped(freqs, amplitude=0.25, step=STEP):
    n = np.arange(step)
    return np.concatenate([amplitude * np.sin(2 * np.pi * f * n / RATE) for f in freqs])


def fixtures():
    sweep = stepped(GRID)
    write_wav("eq-sweep.wav", sweep, sweep)
    for f0, _, harmonics in HUM_CASES:
        tones = stepped(hum_freqs(f0, harmonics), step=HUM_STEP)
        write_wav(f"eq-hum{f0}.wav", tones, tones)
    n = np.arange(2 * RATE)
    rng = np.random.default_rng(2026_10_30)
    write_wav("eq-pair.wav", 0.3 * np.sin(2 * np.pi * 440 * n / RATE)
              + 0.05 * rng.standard_normal(len(n)),
              0.3 * np.sin(2 * np.pi * 1000 * n / RATE))
    one = np.arange(RATE)
    write_wav("eq-onset.wav", 0.5 * np.sin(2 * np.pi * 1000 * one / RATE), np.zeros(RATE))
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(RODE), "-t", "12", "-f", "f32le", "-acodec",
         "pcm_f32le", "-ar", str(RATE), "-ac", "1", "-"], capture_output=True, check=True).stdout
    voice = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    write_wav("eq-voice-left.wav", voice, np.zeros(len(voice)))
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(RODE), "-c:a", "pcm_s16le",
                    "-ar", str(RATE), "-ac", "1", os.path.join(p5.FIXTURES, "eq-rode.wav")],
                   check=True)


def sides(path):
    """(left, right) of an export, floats."""
    left, right = channels(pcm(path))
    return np.array(left), np.array(right)


def amplitude(y, f, start, stop):
    """The amplitude of `y`'s component at `f` over [start, stop): a least-squares
    fit of a sin + b cos + c."""
    n = np.arange(start, stop)
    w = 2 * np.pi * f * n / RATE
    basis = np.stack([np.sin(w), np.cos(w), np.ones(len(n))], axis=1)
    coef, *_ = np.linalg.lstsq(basis, y[start:stop], rcond=None)
    return math.hypot(coef[0], coef[1])


def step_levels(y, freqs, step=STEP):
    """Each step's amplitude over its last quarter, less 50 ms."""
    return [amplitude(y, f, i * step + 3 * step // 4, (i + 1) * step - RATE // 20)
            for i, f in enumerate(freqs)]


def analytic(slots, freqs):
    """The cascade's response in dB at `freqs` from the slots' parameters, by
    eq_probe's numpy oracle."""
    total = np.zeros(len(freqs))
    for kind, params in slots:
        for section in eq_probe.oracle(kind, params, RATE).values():
            total += eq_probe.magnitude_db(section, freqs, RATE)
    return total


# ---- E1 ---------------------------------------------------------------------

def setting_rows(m):
    print("\nE1 — set_audio's eq, hum and channels")
    s = Session(m, "eq-set")
    clip = s.place("eq-pair.wav")
    eq = {"high_pass": {"frequency": 90.0, "slope": 24},
          "band_2": {"frequency": 1000.0, "gain_db": 2.5, "q": 2.0}, "bypass": True}
    hum = {"frequency": 50, "depth_db": 24.0, "harmonics": 8}
    s.op("set_audio", clips=[clip], patch={"eq": eq, "hum": hum, "channels": "swapped"})
    audio = s.clip(clip)["audio"]
    check(audio.get("eq") == eq and audio.get("hum") == hum and audio.get("channels") == "swapped",
          f"E1 the three round-trip: {audio.get('eq')}, {audio.get('hum')}, "
          f"{audio.get('channels')}")
    for patch, name in [({"eq": {"high_pass": {"frequency": 5}}}, "audio.eq.high_pass.frequency"),
                        ({"eq": {"low_pass": {"slope": 18}}}, "audio.eq.low_pass.slope"),
                        ({"eq": {"low_shelf": {"gain_db": 30}}}, "audio.eq.low_shelf.gain_db"),
                        ({"eq": {"band_3": {"q": 0}}}, "audio.eq.band_3.q"),
                        ({"hum": {"frequency": 55}}, "audio.hum.frequency"),
                        ({"hum": {"depth_db": 3}}, "audio.hum.depth_db"),
                        ({"hum": {"harmonics": 9}}, "audio.hum.harmonics"),
                        ({"eq": {"band_4": {}}}, "eq.band_4"),
                        ({"hum": {"depth": 3}}, "hum.depth"),
                        ({"channels": "centre"}, "centre")]:
        text = s.error("set_audio", clips=[clip], patch=patch) or ""
        check(name in text and "made no change" not in text,
              f"E1 {patch} refused naming {name}: {text[:110]!r}")
    after = s.clip(clip)["audio"]
    check(after == audio, "E1 and the refusals changed nothing")
    s.op("set_audio", clips=[clip], patch={"eq": {"high_pass": None}})
    check("high_pass" not in s.clip(clip)["audio"]["eq"], "E1 null clears a slot")
    s.op("set_audio", clips=[clip], patch={"eq": None, "hum": None, "channels": "both"})
    audio = s.clip(clip)["audio"]
    check("eq" not in audio and "hum" not in audio and "channels" not in audio,
          f"E1 null clears the groups and both is not written: {sorted(audio)}")
    s.op("set_audio", clips=[clip], patch={"eq": {"high_pass": {}}})
    check(s.clip(clip)["audio"].get("eq") == {"high_pass": {"frequency": 80.0, "slope": 12}},
          f"E1 {{eq: {{high_pass: {{}}}}}} stores the defaults: {s.clip(clip)['audio'].get('eq')}")
    m.call("close_project", project=s.path, discard=True)


# ---- E2, E3 -----------------------------------------------------------------

E2_CASES = {
    "a": [("high_pass", {"frequency": 80.0, "slope": 24}),
          ("low_shelf", {"frequency": 150.0, "gain_db": 4.0}),
          ("band_1", {"frequency": 300.0, "gain_db": -6.0, "q": 1.0}),
          ("band_2", {"frequency": 1500.0, "gain_db": 3.0, "q": 2.0}),
          ("band_3", {"frequency": 4000.0, "gain_db": 5.0, "q": 0.7}),
          ("high_shelf", {"frequency": 8000.0, "gain_db": -6.0}),
          ("low_pass", {"frequency": 14000.0, "slope": 24})],
    "b": [("high_pass", {"frequency": 120.0, "slope": 12}),
          ("low_pass", {"frequency": 6000.0, "slope": 12})],
}


def response_rows(m):
    print("\nE2 — the stepped sine through two EQs")
    s = Session(m, "eq-sweep")
    clip = s.place("eq-sweep.wav")
    dry, _ = sides(s.export("dry")["path"])
    dry_levels = step_levels(dry, GRID)
    for name, slots in E2_CASES.items():
        s.op("set_audio", clips=[clip], patch={"eq": {k: v for k, v in slots}})
        wet, _ = sides(s.export(f"e2{name}")["path"])
        measured = 20 * np.log10(np.array(step_levels(wet, GRID)) / np.array(dry_levels))
        expected = analytic(slots, GRID)
        mask = expected >= -60
        gap = np.abs(measured - expected)[mask]
        worst = int(np.argmax(np.where(mask, np.abs(measured - expected), -1)))
        check(len(gap) >= 10 and float(gap.max()) <= 0.1,
              f"E2 ({name}) {len(gap)} steps ≥ −60 dB within {gap.max():.4f} dB of analytic "
              f"(worst at {GRID[worst]:.0f} Hz: {measured[worst]:.3f} against "
              f"{expected[worst]:.3f})")
        s.op("set_audio", clips=[clip], patch={"eq": None})
    m.call("close_project", project=s.path, discard=True)

    for f0, depth, harmonics in HUM_CASES:
        print(f"\nE3 — hum {f0} Hz × {harmonics} at {depth:g} dB")
        s = Session(m, f"eq-hum{f0}")
        clip = s.place(f"eq-hum{f0}.wav")
        freqs = hum_freqs(f0, harmonics)
        dry, _ = sides(s.export("dry")["path"])
        params = {"frequency": f0, "depth_db": depth, "harmonics": harmonics}
        s.op("set_audio", clips=[clip], patch={"hum": params})
        wet, _ = sides(s.export("hum")["path"])
        measured = 20 * np.log10(np.array(step_levels(wet, freqs, HUM_STEP))
                                 / np.array(step_levels(dry, freqs, HUM_STEP)))
        expected = analytic([("hum", params)], freqs)
        at = measured[0::3] + depth
        beside = np.concatenate([measured[1::3] - expected[1::3], measured[2::3] - expected[2::3]])
        check(bool(np.all(np.abs(at) <= 0.1)),
              f"E3 every harmonic at −{depth:g} dB ±0.1: {at.min():+.3f}…{at.max():+.3f}")
        check(bool(np.all(np.abs(beside) <= 0.1)),
              f"E3 k·f0 ± f0/20 within ±0.1 dB of analytic: {beside.min():+.3f}…"
              f"{beside.max():+.3f}")
        m.call("close_project", project=s.path, discard=True)


# ---- E4 ---------------------------------------------------------------------

def pick_rows(m):
    print("\nE4 — the channel picks")
    s = Session(m, "eq-picks")
    clip = s.place("eq-pair.wav")
    left, right = sides(s.export("dry")["path"])
    for choice, want in (("left", (left, left)), ("right", (right, right)),
                         ("swapped", (right, left))):
        s.op("set_audio", clips=[clip], patch={"channels": choice})
        got = sides(s.export(choice)["path"])
        check(len(left) > 0 and np.array_equal(got[0], want[0]) and np.array_equal(got[1], want[1]),
              f"E4 {choice}: both channels sample-identical to the dry export's")
    s.op("set_audio", clips=[clip], patch={"channels": "left", "mono": True})
    got = sides(s.export("mono-left")["path"])
    check(np.array_equal(got[0], left) and np.array_equal(got[1], left),
          "E4 mono with left: both channels the left channel")
    m.call("close_project", project=s.path, discard=True)


# ---- E5 ---------------------------------------------------------------------

def loudness_place(s, name, at=0):
    clip = s.place(name, at=at)
    media = s.clip(clip)["source"]["media"]
    marker = os.path.join(s.path, "cache", "loudness", f"{media}.complete.json")
    p5.wait_for_files([marker], f"{s.name}: the loudness cache of media {media}")
    return clip


def loudness_rows(m):
    print("\nE5 — the voice on the left only")
    results = {}
    for choice in ("both", "left"):
        s = Session(m, f"eq-loud-{choice}")
        clip = loudness_place(s, "eq-voice-left.wav")
        if choice != "both":
            s.op("set_audio", clips=[clip], patch={"channels": choice})
        row = s.op("normalize_clip", clips=[clip], mode="loudness",
                   target_lufs=-16)["normalized"][0]
        lufs = integrated(channels(pcm(s.export(f"normalized-{choice}")["path"])))
        results[choice] = (row["measured_lufs"], lufs)
        check(lufs is not None and abs(lufs + 16) <= 0.5,
              f"E5 {choice}: measured {row['measured_lufs']:.2f} LUFS, volume "
              f"{row['volume']:.3f}, the normalised export at {lufs:.2f} LUFS (−16 ±0.5)")
        m.call("close_project", project=s.path, discard=True)
    gap = results["left"][0] - results["both"][0]
    check(abs(gap - 3.0103) <= 0.05, f"E5 left reads both + {gap:.3f} LU (3.01 ±0.05)")


# ---- E6 ---------------------------------------------------------------------

def onset_rows(m):
    print("\nE6 — the head stages' lookup on a noise-reduced track")
    s = Session(m, "eq-onset")
    a = s.place("eq-onset.wav")
    b = s.place("eq-onset.wav", at=p5.SEC)
    c = s.place("eq-onset.wav", at=2 * p5.SEC)
    s.op("set_audio", clips=[a], patch={"channels": "right"})
    s.op("set_audio", clips=[b], patch={"channels": "left"})
    s.op("set_audio", clips=[c], patch={"noise_reduction": 0.5})
    _, right = sides(s.export("onset")["path"])
    loud = np.nonzero(np.abs(right) > 0.05)[0]
    onset = int(loud[0]) if len(loud) else -1
    gap_ms = (onset - RATE) / 48
    check(onset >= 0 and abs(gap_ms) <= 1,
          f"E6 the tone starts in the right channel at sample {onset}, {gap_ms:+.2f} ms from "
          "the cut (±1; 10.7 ms late without the head lookup)")
    m.call("close_project", project=s.path, discard=True)


# ---- E7 ---------------------------------------------------------------------

def saved_rows(m):
    print("\nE7 — the saved file, and set-then-cleared")
    s = Session(m, "eq-saved")
    a = s.place("eq-pair.wav")
    b = s.place("eq-pair.wav", at=3 * p5.SEC)
    m.call("save_project", project=s.path)
    with open(os.path.join(s.path, "project.json")) as handle:
        plain = handle.read()
    s.op("set_audio", clips=[a], patch={"eq": {"band_1": {"gain_db": -3}}, "hum": {},
                                        "channels": "left"})
    m.call("save_project", project=s.path)
    with open(os.path.join(s.path, "project.json")) as handle:
        text = handle.read()
    saved = json.loads(text)
    clips = {c["id"]: c for c in saved["clips"]}
    version = limiter_proof.format_version()
    check(saved.get("version") == version,
          f"E7 the file is version {saved.get('version')}, the header's {version}")
    check(all(key in clips[a]["audio"] for key in ("eq", "hum", "channels"))
          and not any(key in clips[b]["audio"] for key in ("eq", "hum", "channels"))
          and text.count('"eq"') == 1 and text.count('"hum"') == 1
          and text.count('"channels"') == 1,
          f"E7 the three on clip {a} only")
    check(not any(f'"{key}"' in plain for key in ("eq", "hum", "channels")),
          "E7 before they were set, the file had none of the keys")
    m.call("close_project", project=s.path, discard=True)

    s = Session(m, "eq-never")
    clip = s.place("eq-pair.wav")
    s.op("set_audio", clips=[clip], patch={"volume": 0.8})
    never = pcm(s.export("never")["path"])
    m.call("close_project", project=s.path, discard=True)
    s = Session(m, "eq-cleared")
    clip = s.place("eq-pair.wav")
    s.op("set_audio", clips=[clip], patch={"volume": 0.8, "eq": {"high_pass": {}},
                                           "hum": {}, "channels": "swapped"})
    s.op("set_audio", clips=[clip], patch={"eq": None, "hum": None, "channels": "both"})
    cleared = pcm(s.export("cleared")["path"])
    check(len(never) > 0 and never == cleared,
          f"E7 set then cleared: {len(cleared)} bytes against {len(never)}, "
          f"{'identical' if never == cleared else 'DIFFERENT'}")
    m.call("close_project", project=s.path, discard=True)


# ---- E8 ---------------------------------------------------------------------

def report(y):
    """(pause floor dBFS: the 10th percentile of 50 ms RMS frames; {octave: dB})."""
    frame = RATE // 20
    frames = y[:len(y) // frame * frame].reshape(-1, frame)
    rms = np.sqrt(np.mean(frames ** 2, axis=1) + 1e-20)
    floor = 20 * np.log10(np.percentile(rms, 10))
    spectrum = np.abs(np.fft.rfft(y)) ** 2
    freqs = np.fft.rfftfreq(len(y), 1 / RATE)
    bands = {}
    for centre in (63, 125, 250, 500, 1000, 2000, 4000, 8000):
        band = (freqs >= centre / np.sqrt(2)) & (freqs < centre * np.sqrt(2))
        bands[centre] = 10 * np.log10(spectrum[band].sum() + 1e-20)
    return floor, bands


def owner_rows(m):
    print("\nE8 — the owner's recording through the three presets (reported)")
    s = Session(m, "eq-owner")
    clip = s.place("eq-rode.wav")
    dry, _ = sides(s.export("dry")["path"])
    s.op("set_audio", clips=[clip], patch={"eq": {
        "high_pass": {"frequency": 80.0, "slope": 24},
        "band_1": {"frequency": 300.0, "gain_db": -3.0, "q": 1.0},
        "band_3": {"frequency": 4000.0, "gain_db": 3.0, "q": 1.0}}})
    wet, _ = sides(s.export("presets")["path"])
    (floor_dry, bands_dry), (floor_wet, bands_wet) = report(dry), report(wet)
    print(f"  note E8 pause floor {floor_dry:.2f} → {floor_wet:.2f} dBFS "
          f"({floor_wet - floor_dry:+.2f} dB)")
    print("  note E8 octave bands (wet − dry): " + ", ".join(
        f"{c} Hz {bands_wet[c] - bands_dry[c]:+.2f}" for c in bands_dry))
    m.call("close_project", project=s.path, discard=True)


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    for part in (setting_rows, response_rows, pick_rows, loudness_rows, onset_rows, saved_rows,
                 owner_rows):
        try:
            part(m)
        except (ToolError, KeyError, IndexError, RuntimeError, OSError, ValueError) as error:
            check(False, f"{part.__name__} aborted: {type(error).__name__}: {error}")
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for line in failures:
        print(f"  FAILED: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
