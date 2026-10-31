"""The gate and the de-esser over MCP (road map "audio" AP4, spec §11
AU-40..AU-46).

Usage: python3 tools/proof/audio_ap4_proof.py <dir>/agent.sock

Every claim about sound is MEASURED on an exported WAV against the same
project exported without the stage, never read back from the app alone. The
reference level L (AU-41) is this script's BS.1770 (`phase5_proof.integrated`)
over the dry export, which `loudness_normalize_proof.py` holds within 0.5 LU
of the app's reading; an export with a gate or de-esser also exercises the
export's wait for the clip's loudness (AU-42).

  P1  set_audio's gate and de_esser round-trip; {} stores the defaults; null
      clears; each bound and an unknown inner key is refused by name and
      changes nothing.
  P2  the saved file is at the header's version, the keys only where set, and
      set-then-cleared exports the bytes never-set does.
  P3  1 kHz bursts at −20 dBFS over −60 dBFS RMS noise, ratio 20, range 20:
      the gaps' floor 20 ±0.5 dB under the ungated export's, the bursts'
      middles ±0.05 dB.
  P4  a −50 dBFS 300 Hz bed after a −20 dBFS burst, hold 50 and 200 ms: the
      gain's −10 dB crossing (fitted over the release) within ±3 ms of t_f +
      hold + release·ln 2.
  P5  voice-band tones (300 Hz–2 kHz) and 6–9 kHz noise bursts at least 12 dB
      over the threshold through the sidechain, de-esser at 4 kHz with the
      default threshold and range: the bursts' 6–9 kHz energy down by
      [range − 2, range + 0.5] dB, the tones' 300 Hz–2 kHz energy ±0.5 dB,
      between bursts ±0.1 dB, no third-octave band 2–12 kHz louder than
      ungated by more than 0.2 dB.
  P6  reported: the owner's recording under the default gate — the pause floor
      (p10 of 50 ms RMS) not raised and speech (p90) within ±1 dB.
  P7  paste_attributes carries both.
"""

import json
import math
import os
import subprocess
import sys

import numpy as np

import eq_probe
import limiter_proof
import phase5_proof as p5
from eq_proof import loudness_place, report, write_wav
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


def left_of(path):
    """An export's left channel as floats (16-bit, exact)."""
    return np.array(channels(pcm(path))[0])


def level_of(path):
    """L (AU-41): this script's BS.1770 over the export."""
    return integrated(channels(pcm(path)))


def db(x):
    return 20 * math.log10(x)


def rms_db(y):
    return 10 * math.log10(float(np.mean(np.square(y))) + 1e-30)


# ---- fixtures ---------------------------------------------------------------

BURST = (0.5, 1.0)  # the burst's place in each 2 s period, seconds
P5_FC = 4000.0


def bandpass_noise(n, low, high, rng):
    spectrum = np.fft.rfft(rng.standard_normal(n))
    freqs = np.fft.rfftfreq(n, 1 / RATE)
    spectrum[(freqs < low) | (freqs > high)] = 0
    y = np.fft.irfft(spectrum, n)
    return y / np.sqrt(np.mean(y ** 2))


def fixtures():
    rng = np.random.default_rng(2026_10_30)
    t = np.arange(10 * RATE) / RATE
    noise = 0.001 * rng.standard_normal(len(t))  # −60 dBFS RMS
    phase = t % 2
    bursts = ((phase >= BURST[0]) & (phase < BURST[1])) * 0.1 * np.sin(2 * np.pi * 1000 * t)
    write_wav("ap4-bursts.wav", bursts + noise, bursts + noise)

    n = np.arange(int(2.5 * RATE))
    burst = (n < RATE // 2) * 0.1 * np.sin(2 * np.pi * 1000 * n / RATE)
    bed = (n >= RATE // 2) * 10 ** (-50 / 20) * np.sin(2 * np.pi * 300 * (n - RATE // 2) / RATE)
    write_wav("ap4-release.wav", burst + bed, burst + bed)

    t = np.arange(8 * RATE) / RATE
    tones = sum(0.03 * np.sin(2 * np.pi * f * t) for f in (300, 700, 1200, 2000))
    hiss = 0.15 * bandpass_noise(len(t), 6000, 9000, rng)
    gate = ((t % 1) >= 0.4) & ((t % 1) < 0.48)
    write_wav("ap4-sibilance.wav", tones + gate * hiss, tones + gate * hiss)

    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(RODE), "-c:a", "pcm_s16le",
                    "-ar", str(RATE), "-ac", "1", os.path.join(p5.FIXTURES, "ap4-rode.wav")],
                   check=True)


# ---- P1 ---------------------------------------------------------------------

GATE_DEFAULTS = {"threshold_db": -10.0, "ratio": 4.0, "range_db": 20.0, "attack": 600,
                 "hold": 30000, "release": 60000}
DE_ESSER_DEFAULTS = {"frequency": 6000.0, "threshold_db": 0.0, "range_db": 6.0}


def setting_rows(m):
    print("\nP1 — set_audio's gate and de_esser")
    s = Session(m, "ap4-set")
    clip = s.place("ap4-bursts.wav")
    gate = {"threshold_db": -15.0, "ratio": 10.0, "range_db": 40.0, "attack": 1200,
            "hold": 60000, "release": 120000}
    de_esser = {"frequency": 5000.0, "threshold_db": -3.0, "range_db": 10.0}
    s.op("set_audio", clips=[clip], patch={"gate": gate, "de_esser": de_esser})
    audio = s.clip(clip)["audio"]
    check(audio.get("gate") == gate and audio.get("de_esser") == de_esser,
          f"P1 both round-trip: {audio.get('gate')}, {audio.get('de_esser')}")
    for patch, name in [({"gate": {"threshold_db": -41}}, "audio.gate.threshold_db"),
                        ({"gate": {"ratio": 21}}, "audio.gate.ratio"),
                        ({"gate": {"range_db": 0.5}}, "audio.gate.range_db"),
                        ({"gate": {"attack": 60001}}, "audio.gate.attack"),
                        ({"gate": {"hold": -1}}, "audio.gate.hold"),
                        ({"gate": {"release": 599}}, "audio.gate.release"),
                        ({"de_esser": {"frequency": 1999}}, "audio.de_esser.frequency"),
                        ({"de_esser": {"threshold_db": 21}}, "audio.de_esser.threshold_db"),
                        ({"de_esser": {"range_db": 25}}, "audio.de_esser.range_db"),
                        ({"gate": {"knee": 3}}, "gate.knee"),
                        ({"de_esser": {"ratio": 3}}, "de_esser.ratio")]:
        text = s.error("set_audio", clips=[clip], patch=patch) or ""
        check(name in text and "made no change" not in text,
              f"P1 {patch} refused naming {name}: {text[:110]!r}")
    check(s.clip(clip)["audio"] == audio, "P1 and the refusals changed nothing")
    s.op("set_audio", clips=[clip], patch={"gate": None, "de_esser": None})
    audio = s.clip(clip)["audio"]
    check("gate" not in audio and "de_esser" not in audio,
          f"P1 null clears both: {sorted(audio)}")
    s.op("set_audio", clips=[clip], patch={"gate": {}, "de_esser": {}})
    audio = s.clip(clip)["audio"]
    check(audio.get("gate") == GATE_DEFAULTS and audio.get("de_esser") == DE_ESSER_DEFAULTS,
          f"P1 {{}} stores the defaults: {audio.get('gate')}, {audio.get('de_esser')}")
    m.call("close_project", project=s.path, discard=True)


# ---- P2 ---------------------------------------------------------------------

def saved_rows(m):
    print("\nP2 — the saved file, and set-then-cleared")
    s = Session(m, "ap4-saved")
    a = s.place("ap4-bursts.wav")
    b = s.place("ap4-bursts.wav", at=12 * p5.SEC)
    m.call("save_project", project=s.path)
    with open(os.path.join(s.path, "project.json")) as handle:
        plain = handle.read()
    s.op("set_audio", clips=[a], patch={"gate": {}, "de_esser": {"frequency": 5000}})
    m.call("save_project", project=s.path)
    with open(os.path.join(s.path, "project.json")) as handle:
        text = handle.read()
    saved = json.loads(text)
    clips = {c["id"]: c for c in saved["clips"]}
    version = limiter_proof.format_version()
    check(saved.get("version") == version,
          f"P2 the file is version {saved.get('version')}, the header's {version}")
    check(all(key in clips[a]["audio"] for key in ("gate", "de_esser"))
          and not any(key in clips[b]["audio"] for key in ("gate", "de_esser"))
          and text.count('"gate"') == 1 and text.count('"de_esser"') == 1,
          f"P2 both on clip {a} only")
    check(not any(f'"{key}"' in plain for key in ("gate", "de_esser")),
          "P2 before they were set, the file had neither key")
    m.call("close_project", project=s.path, discard=True)

    s = Session(m, "ap4-never")
    clip = s.place("ap4-bursts.wav")
    s.op("set_audio", clips=[clip], patch={"volume": 0.8})
    never = pcm(s.export("never")["path"])
    m.call("close_project", project=s.path, discard=True)
    s = Session(m, "ap4-cleared")
    clip = s.place("ap4-bursts.wav")
    s.op("set_audio", clips=[clip], patch={"volume": 0.8, "gate": {}, "de_esser": {}})
    s.op("set_audio", clips=[clip], patch={"gate": None, "de_esser": None})
    cleared = pcm(s.export("cleared")["path"])
    check(len(never) > 0 and never == cleared,
          f"P2 set then cleared: {len(cleared)} bytes against {len(never)}, "
          f"{'identical' if never == cleared else 'DIFFERENT'}")
    m.call("close_project", project=s.path, discard=True)


# ---- P3, P4 -----------------------------------------------------------------

def windows(period, lo, hi, total):
    """Sample ranges [k·period + lo, k·period + hi) inside `total`."""
    out = []
    k = 0
    while (k * period + hi) * RATE <= total:
        out.append((int((k * period + lo) * RATE), int((k * period + hi) * RATE)))
        k += 1
    return out


def gate_rows(m):
    print("\nP3 — bursts over noise, ratio 20, range 20")
    s = Session(m, "ap4-bursts")
    clip = loudness_place(s, "ap4-bursts.wav")
    dry_path = s.export("dry")["path"]
    dry = left_of(dry_path)
    level = level_of(dry_path)
    s.op("set_audio", clips=[clip], patch={"gate": {"ratio": 20.0, "range_db": 20.0}})
    wet = left_of(s.export("gated")["path"])
    # The gaps' middles (well after the release), the bursts' middles.
    gaps = windows(2, 1.5, 2.4, len(dry))
    middles = windows(2, 0.65, 0.85, len(dry))
    floor_dry = rms_db(np.concatenate([dry[a:b] for a, b in gaps]))
    floor_wet = rms_db(np.concatenate([wet[a:b] for a, b in gaps]))
    burst_dry = rms_db(np.concatenate([dry[a:b] for a, b in middles]))
    burst_wet = rms_db(np.concatenate([wet[a:b] for a, b in middles]))
    print(f"  note P3 L {level:.2f} LUFS, threshold {level - 10:.2f} dBFS")
    check(abs((floor_dry - floor_wet) - 20) <= 0.5,
          f"P3 the gaps' floor {floor_dry:.2f} → {floor_wet:.2f} dBFS, "
          f"{floor_dry - floor_wet:.3f} dB lower (20 ±0.5)")
    check(abs(burst_wet - burst_dry) <= 0.05,
          f"P3 the bursts' middles {burst_dry:.3f} → {burst_wet:.3f} dBFS (±0.05)")
    m.call("close_project", project=s.path, discard=True)

    print("\nP4 — hold and release on an export")
    for hold_ms in (50, 200):
        s = Session(m, f"ap4-release-{hold_ms}")
        clip = loudness_place(s, "ap4-release.wav")
        dry_path = s.export("dry")["path"]
        dry = left_of(dry_path)
        level = level_of(dry_path)
        threshold = level - 10
        s.op("set_audio", clips=[clip], patch={"gate": {
            "ratio": 20.0, "range_db": 20.0, "hold": hold_ms * 600, "release": 60000}})
        wet = left_of(s.export("gated")["path"])
        burst_end = RATE // 2
        amplitude = float(np.max(np.abs(dry[:burst_end])))
        last = int(np.nonzero(np.abs(dry[:burst_end]) >= amplitude * 0.9999)[0][-1])
        fall_db = -20 * math.log10(math.exp(-1 / (0.010 * RATE)))
        t_f = last + (db(amplitude) - threshold) / fall_db
        expected = t_f + hold_ms * RATE / 1000 + 0.1 * RATE * math.log(2)
        bed = 10 ** (-50 / 20)
        idx = np.arange(burst_end, len(dry))
        idx = idx[np.abs(dry[idx]) >= 0.5 * bed]
        reduction = -20 * np.log10(np.abs(wet[idx]) / np.abs(dry[idx]))
        fit = (reduction > 2) & (reduction < 18)
        y = np.log(1 - reduction[fit] / 20)
        slope, intercept = np.polyfit(idx[fit].astype(float), y, 1)
        tau = -1 / slope
        onset = intercept * tau
        crossing = onset + tau * math.log(2)
        gap_ms = (crossing - expected) / 48
        check(int(fit.sum()) > 100 and abs(gap_ms) <= 3,
              f"P4 hold {hold_ms} ms: −10 dB crossed at {crossing:.0f}, expected {expected:.0f} "
              f"({gap_ms:+.2f} ms, ±3); fitted release {tau / 48:.1f} ms over {int(fit.sum())} "
              "samples")
        m.call("close_project", project=s.path, discard=True)


# ---- P5 ---------------------------------------------------------------------

def band_energy(y, low, high):
    spectrum = np.abs(np.fft.rfft(y)) ** 2
    freqs = np.fft.rfftfreq(len(y), 1 / RATE)
    return float(spectrum[(freqs >= low) & (freqs < high)].sum())


def sidechain(y):
    """The de-esser's sidechain at P5's cut: two RBJ Butterworth high-pass
    sections (eq_probe's oracle), run in float64."""
    out = np.asarray(y, dtype=float)
    for q in eq_probe.BUTTERWORTH[24]:
        b, a = eq_probe.rbj("hp", P5_FC, RATE, q=q)
        z1 = z2 = 0.0
        filtered = np.empty_like(out)
        for i, x in enumerate(out):
            v = b[0] * x + z1
            z1 = b[1] * x - a[1] * v + z2
            z2 = b[2] * x - a[2] * v
            filtered[i] = v
        out = filtered
    return out


def de_esser_rows(m):
    print("\nP5 — sibilant bursts over voice-band tones, de-esser at 4 kHz")
    s = Session(m, "ap4-sibilance")
    clip = loudness_place(s, "ap4-sibilance.wav")
    dry_path = s.export("dry")["path"]
    dry = left_of(dry_path)
    level = level_of(dry_path)
    s.op("set_audio", clips=[clip], patch={"de_esser": {"frequency": P5_FC}})
    wet = left_of(s.export("de-essed")["path"])
    bursts = windows(1, 0.405, 0.48, len(dry))
    between = windows(1, 0.0, 0.39, len(dry))[1:]
    side_peak = max(float(np.max(np.abs(sidechain(dry[a:b])))) for a, b in bursts[:3])
    over = db(side_peak) - level
    check(over >= 12, f"P5 the bursts' sidechain peaks sit {over:.1f} dB over the threshold "
          f"(L {level:.2f} LUFS, ≥ 12)")
    hiss_drop = 10 * math.log10(
        sum(band_energy(dry[a:b], 6000, 9000) for a, b in bursts)
        / sum(band_energy(wet[a:b], 6000, 9000) for a, b in bursts))
    check(4.0 <= hiss_drop <= 6.5,
          f"P5 the bursts' 6–9 kHz energy {hiss_drop:.2f} dB lower (range 6: 4…6.5)")
    tones = 10 * math.log10(band_energy(wet, 250, 2100) / band_energy(dry, 250, 2100))
    check(abs(tones) <= 0.5, f"P5 the tones' 300 Hz–2 kHz energy {tones:+.3f} dB (±0.5)")
    quiet = rms_db(np.concatenate([wet[a:b] for a, b in between])) - rms_db(
        np.concatenate([dry[a:b] for a, b in between]))
    check(abs(quiet) <= 0.1, f"P5 between the bursts {quiet:+.3f} dB (±0.1)")
    loudest, at = -math.inf, 0
    for k in range(-1, 9):  # third-octave centres 2 kHz … 12.7 kHz
        centre = 1000 * 2 ** ((k + 3) / 3)
        low, high = centre / 2 ** (1 / 6), centre * 2 ** (1 / 6)
        if centre < 2000 or centre > 12700:
            continue
        gain = 10 * math.log10((band_energy(wet, low, high) + 1e-30)
                               / (band_energy(dry, low, high) + 1e-30))
        if gain > loudest:
            loudest, at = gain, centre
    check(loudest <= 0.2,
          f"P5 no third-octave band 2–12 kHz louder than ungated: the loudest {loudest:+.3f} dB "
          f"at {at:.0f} Hz (≤ 0.2)")
    m.call("close_project", project=s.path, discard=True)


# ---- P6 ---------------------------------------------------------------------

def owner_rows(m):
    print("\nP6 — the owner's recording under the default gate (reported)")
    s = Session(m, "ap4-owner")
    clip = loudness_place(s, "ap4-rode.wav")
    dry_path = s.export("dry")["path"]
    dry = left_of(dry_path)
    s.op("set_audio", clips=[clip], patch={"gate": {}})
    wet = left_of(s.export("gated")["path"])

    def speech(y):
        frame = RATE // 20
        frames = y[:len(y) // frame * frame].reshape(-1, frame)
        rms = np.sqrt(np.mean(frames ** 2, axis=1) + 1e-20)
        return 20 * np.log10(np.percentile(rms, 90))

    (floor_dry, _), (floor_wet, _) = report(dry), report(wet)
    p90_dry, p90_wet = speech(dry), speech(wet)
    print(f"  note P6 L {level_of(dry_path):.2f} LUFS; pause floor {floor_dry:.2f} → "
          f"{floor_wet:.2f} dBFS ({floor_wet - floor_dry:+.2f} dB); speech p90 {p90_dry:.2f} → "
          f"{p90_wet:.2f} dBFS ({p90_wet - p90_dry:+.2f} dB)")
    check(floor_wet <= floor_dry and abs(p90_wet - p90_dry) <= 1,
          "P6 the pause floor is not raised and speech holds within ±1 dB")
    m.call("close_project", project=s.path, discard=True)


# ---- P7 ---------------------------------------------------------------------

def paste_rows(m):
    print("\nP7 — paste_attributes")
    s = Session(m, "ap4-paste")
    a = s.place("ap4-bursts.wav")
    b = s.place("ap4-bursts.wav", at=12 * p5.SEC)
    s.op("set_audio", clips=[a], patch={"gate": {"hold": 120000}, "de_esser": {"range_db": 9}})
    source = s.clip(a)
    s.op("paste_attributes", clips=[b], payload={"clips": [source], "media": []},
         groups=["audio"])
    target = s.clip(b)["audio"]
    check(target.get("gate") == source["audio"]["gate"]
          and target.get("de_esser") == source["audio"]["de_esser"],
          f"P7 paste_attributes carries both: {target.get('gate')}, {target.get('de_esser')}")
    m.call("close_project", project=s.path, discard=True)


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    os.makedirs(p5.FIXTURES, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    for part in (setting_rows, saved_rows, gate_rows, de_esser_rows, owner_rows, paste_rows):
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
