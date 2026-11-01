"""Match Audio over MCP and exports (road map "audio" AP12, spec §11
AU-120..AU-129).

Usage: python3 tools/proof/audio_ap12_proof.py <dir>/agent.sock

Every claim about sound is MEASURED on an exported WAV: loudness by
phase5_proof's BS.1770 (`integrated`), each third-octave band by this proof's
own numpy (an 8192-point Hann STFT, hop 4096, both channels' power summed,
bins in [c·2^(−1/6), c·2^(1/6)) around c = 1000·2^(n/3)), over each clip's own
range of the timeline (`set_range`, `range: "in_out"`). Fixtures: 10 s of pink
noise written here (seeded), a copy of it TILTED by an export through an EQ
(low shelf 250 Hz +4, band 2.5 kHz +3 dB Q 1, high shelf 4 kHz −5) at −10 dB,
`say` speech and a copy 12 dB down, 2 s of silence, and the owner's
samples/Rode-usb-mic.m4a with a tilted, quieter copy of itself.

  A1   pink noise as the reference for its tilted copy, `set_media_speech`
       spanning both files: matched; every band 100 Hz–10 kHz of the target's
       export within ±1 dB of the reference's, and its loudness within
       ±0.5 LU; the row's `set` holds eq and volume and get_project holds them.
  A2   the `say` speech and its copy 12 dB down, loudness only (eq false):
       within ±0.5 LU; `set` is the volume alone.
  A3   the owner's recording as the reference for a tilted, quieter copy of
       itself (speech from the VAD cache): bands ±1 dB, ±0.5 LU; skipped by name
       when samples/ is absent.
  A4   in A1's project, with a second target: a second call "made no change";
       one undo ("Match Audio") restores both targets' audio groups.
  A5   a target with its own tonal tilt in its EQ (high shelf 3 kHz +6) and a
       high-pass (40 Hz, 24 dB/oct): the tilt replaced by a ≈ flat fit (every
       fitted gain within ±1 dB), the high-pass kept, and its export's bands
       within ±1 dB of the reference's.
  A6   refused by name, changing nothing: a missing `reference`, a silent
       reference, `loudness: false, eq: false`, an unknown key; a silent target
       skipped by name beside a matched one.
  A7   Clip ▸ Match Audio… on an instance launched with
       `-RCDevMatchAudioAccept YES`: writes what the tool writes (eq equal, the
       volume within 0.05 dB).
  A8   the parity log is clean (no "Frame Job: " line in the instance's log).
"""

import json
import os
import subprocess
import sys
import time
import wave

import mcp as mcp_module
import phase5_proof as p5
import proof_app
from mcp import MCP, ToolError
from phase5_proof import Session, channels, integrated, pcm

import numpy as np

ROOT = os.path.dirname(os.path.dirname(p5.HERE))
RODE = os.path.join(ROOT, "samples", "Rode-usb-mic.m4a")
RATE = 48000
SEC = 600000
TILT = {"high_pass": None, "low_shelf": {"frequency": 250, "gain_db": 4}, "band_1": None,
        "band_2": {"frequency": 2500, "gain_db": 3, "q": 1}, "band_3": None,
        "high_shelf": {"frequency": 4000, "gain_db": -5}, "low_pass": None, "bypass": False}
QUIETER = 10 ** (-10 / 20)
SENTENCE = ("The quick brown fox jumps over the lazy dog, and then it runs into the woods "
            "to look for something to eat before the sun goes down over the hills.")
BANDS = range(-11, 12)

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


# ---- fixtures and measurement ------------------------------------------------

def write_wav(path, samples):
    data = np.clip(np.round(samples * 32767), -32768, 32767).astype("<i2")
    with wave.open(path, "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())


def pink(seconds, seed):
    """Pink noise by 1/√f shaping of seeded white noise, at −20 dBFS RMS."""
    count = seconds * RATE
    spectrum = np.fft.rfft(np.random.default_rng(seed).standard_normal(count))
    freqs = np.fft.rfftfreq(count, 1 / RATE)
    spectrum[1:] /= np.sqrt(freqs[1:])
    spectrum[0] = 0
    out = np.fft.irfft(spectrum, count)
    return out * (10 ** (-20 / 20) / np.sqrt(np.mean(out ** 2)))


def fixtures():
    os.makedirs(p5.FIXTURES, exist_ok=True)
    out = p5.FIXTURES

    def ffmpeg(*args):
        subprocess.run(["ffmpeg", "-v", "error", "-y", *args], check=True)

    write_wav(os.path.join(out, "ap12-pink.wav"), pink(10, 12))
    aiff = os.path.join(out, "ap12-say.aiff")
    subprocess.run(["say", "-o", aiff, SENTENCE], check=True)
    ffmpeg("-i", aiff, "-af", "volume=-6dB", "-c:a", "pcm_s16le", "-ar", str(RATE), "-ac", "1",
           os.path.join(out, "ap12-say.wav"))
    ffmpeg("-i", aiff, "-af", "volume=-18dB", "-c:a", "pcm_s16le", "-ar", str(RATE), "-ac", "1",
           os.path.join(out, "ap12-say-quiet.wav"))
    ffmpeg("-f", "lavfi", "-i", f"anullsrc=r={RATE}:cl=mono", "-t", "2", "-c:a", "pcm_s16le",
           os.path.join(out, "ap12-silence.wav"))
    if os.path.exists(RODE):
        ffmpeg("-i", RODE, "-c:a", "pcm_s16le", "-ar", str(RATE), "-ac", "1",
               os.path.join(out, "ap12-rode.wav"))


def bands(path):
    """Each third-octave band's level in dB over the file (both channels)."""
    left, right = (np.array(c) for c in channels(pcm(path)))
    n, hop = 8192, 4096
    window = 0.5 * (1 - np.cos(2 * np.pi * np.arange(n) / n))
    power = np.zeros(n // 2 + 1)
    frames = 0
    for start in range(0, len(left) - n + 1, hop):
        for channel in (left, right):
            power += np.abs(np.fft.rfft(channel[start:start + n] * window)) ** 2
        frames += 1
    width = RATE / n
    levels = []
    for band in BANDS:
        c = 1000 * 2 ** (band / 3)
        low = int(np.ceil(c * 2 ** (-1 / 6) / width))
        high = int(np.ceil(c * 2 ** (1 / 6) / width))
        levels.append(10 * np.log10(max(power[low:high].sum() / max(frames, 1), 1e-30)))
    return np.array(levels)


def lufs_of(path):
    return integrated(channels(pcm(path)))


def compare(reference, target):
    """(largest |band difference| over 100 Hz–10 kHz, loudness difference),
    and the differences printed."""
    a, b = bands(reference), bands(target)
    inside = [i for i, band in enumerate(BANDS) if -10 <= band <= 10]
    difference = b[inside] - a[inside]
    print("  note band differences 100 Hz–10 kHz (target − reference, dB): "
          + " ".join(f"{d:+.2f}" for d in difference))
    return float(np.max(np.abs(difference))), lufs_of(target) - lufs_of(reference)


def ranged(s, label, start, end):
    s.op("set_range", start=start, end=end)
    return s.export(label, range="in_out", peak_dbtp=0)["path"]


def ready(s, clip, kinds=("loudness",), bound=600):
    """Waits up to `bound` seconds for the clip's media's caches: the import
    makes them on the cache lane, which a loaded machine slows (measured: a
    10 s file's loudness cache 5 minutes after its import while three lanes
    built)."""
    media = s.clip(clip)["source"]["media"]
    markers = [os.path.join(s.path, "cache", kind, f"{media}.complete.json") for kind in kinds]
    began = time.monotonic()
    while time.monotonic() - began < bound:
        if all(os.path.exists(path) for path in markers):
            return clip
        time.sleep(0.05)
    raise RuntimeError(f"{s.name}: media {media}'s {kinds} cache was never written")


def place(s, name, at=0, track=None, kinds=("loudness",)):
    return ready(s, s.place(name, at=at, track=track), kinds)


def all_speech(s, clip):
    """`set_media_speech` spanning the clip's whole file."""
    media = s.clip(clip)["source"]["media"]
    duration = next(m["duration"] for m in s.project()["media"] if m["id"] == media)
    s.op("set_media_speech", media=media, spans=[[0, duration]])


def audio(s, clip):
    return s.clip(clip).get("audio") or {}


def clean(value):
    if isinstance(value, dict):
        return {k: clean(v) for k, v in value.items()
                if v is not None and not (k == "bypass" and v is False)}
    return value


def mismatches(group, set_, volume_db=1e-6):
    out = []
    for key, value in set_.items():
        held = group.get(key)
        if key == "volume" and held and value and abs(20 * np.log10(held / value)) <= volume_db:
            continue
        if clean(held) != clean(value):
            out.append(f"{key}: {held!r} against {value!r}")
    return out


def match(s, reference, clips, **kwargs):
    return s.op("match_audio", reference=reference, clips=clips, **kwargs)


def print_answer(answer):
    print(f"  note reference {json.dumps(answer.get('reference'))}, target_lufs "
          f"{answer.get('target_lufs')}")
    for row in answer.get("matched", []):
        print(f"  note clip {row['clip']}: set {json.dumps(row['set'], sort_keys=True)}; fit rms "
              f"{row.get('eq_fit_rms_db')}; volume {row.get('volume')}, result "
              f"{row.get('result_lufs')}, renders {row.get('renders')}")
    for skip in answer.get("skipped", []):
        print(f"  note skipped {skip}")


def tilted(m, source, label):
    """`source` exported through TILT at −10 dB, as a fixture file name."""
    s = Session(m, f"ap12-tilt-{label}")
    clip = place(s, source)
    s.op("set_audio", clips=[clip], patch={"eq": TILT, "volume": QUIETER})
    made = s.export("tilted", peak_dbtp=0)["path"]
    name = f"ap12-{label}-tilted.wav"
    os.replace(made, os.path.join(p5.FIXTURES, name))
    m.call("close_project", project=s.path, discard=True)
    return name


# ---- A1, A4 pink noise -------------------------------------------------------

def pink_rows(m):
    print("\nA1, A4 — pink noise matched to its tilted copy")
    name = tilted(m, "ap12-pink.wav", "pink")
    s = Session(m, "ap12-pink")
    reference = place(s, "ap12-pink.wav")
    target = place(s, name, at=12 * SEC)
    second = place(s, "ap12-pink.wav", track=s.add_track(), at=12 * SEC)
    s.op("set_audio", clips=[second], patch={"volume": 0.3})
    for clip in (reference, target):
        all_speech(s, clip)
    before = {target: audio(s, target), second: audio(s, second)}
    answer = match(s, reference, [target, second])
    print_answer(answer)
    rows = {r["clip"]: r for r in answer["matched"]}
    row = rows.get(target, {})
    check(sorted(row.get("set", {})) == ["eq", "volume"]
          and not mismatches(audio(s, target), row.get("set", {})),
          f"A1 the row sets eq and volume and get_project holds them "
          f"{mismatches(audio(s, target), row.get('set', {}))}")
    s.op("set_audio", clips=[second], patch={"muted": True})
    worst, loud = compare(ranged(s, "ref", 0, 10 * SEC), ranged(s, "tgt", 12 * SEC, 22 * SEC))
    s.undo()
    check(worst <= 1 and abs(loud) <= 0.5,
          f"A1 every band within ±1 dB (largest {f(worst)}) and loudness within ±0.5 LU "
          f"({f(loud)})")
    again = s.error("match_audio", reference=reference, clips=[target, second]) or ""
    check("made no change" in again, f"A4 a second call: {again[:80]!r}")
    undone = s.undo()
    check(undone == "Match Audio" and audio(s, target) == before[target]
          and audio(s, second) == before[second],
          f"A4 one undo ({undone!r}) restores both targets' audio groups")
    m.call("close_project", project=s.path, discard=True)
    return name, row.get("set")


# ---- A2 speech loudness ------------------------------------------------------

def speech_rows(m):
    print("\nA2 — `say` speech 12 dB apart, loudness only")
    s = Session(m, "ap12-say")
    reference = place(s, "ap12-say.wav")
    target = place(s, "ap12-say-quiet.wav", at=20 * SEC)
    answer = match(s, reference, [target], eq=False)
    print_answer(answer)
    row = answer["matched"][0]
    duration = s.clip(reference)["duration"]
    loud = lufs_of(ranged(s, "tgt", 20 * SEC, 20 * SEC + duration)) - lufs_of(
        ranged(s, "ref", 0, duration))
    check(sorted(row["set"]) == ["volume"] and abs(loud) <= 0.5
          and answer.get("target_lufs") is not None,
          f"A2 `set` {sorted(row['set'])}, loudness within ±0.5 LU ({f(loud)})")
    m.call("close_project", project=s.path, discard=True)


# ---- A3 the owner's recording --------------------------------------------------

def owner_rows(m):
    print("\nA3 — the owner's recording and a tilted, quieter copy")
    if not os.path.exists(RODE):
        check(True, f"A3 skipped: {RODE} is absent")
        return
    name = tilted(m, "ap12-rode.wav", "rode")
    s = Session(m, "ap12-rode")
    reference = place(s, "ap12-rode.wav", kinds=("loudness", "speech"))
    duration = s.clip(reference)["duration"]
    start = duration + 2 * SEC
    target = place(s, name, at=start, kinds=("loudness", "speech"))
    answer = match(s, reference, [target])
    print_answer(answer)
    worst, loud = compare(ranged(s, "ref", 0, duration),
                          ranged(s, "tgt", start, start + duration))
    check(worst <= 1 and abs(loud) <= 0.5,
          f"A3 every band within ±1 dB (largest {f(worst)}) and loudness within ±0.5 LU "
          f"({f(loud)})")
    m.call("close_project", project=s.path, discard=True)


# ---- A5 a target's own tilt and high-pass ------------------------------------

def own_eq_rows(m):
    print("\nA5 — a target's own tilt replaced, its high-pass kept")
    s = Session(m, "ap12-own")
    reference = place(s, "ap12-pink.wav")
    target = place(s, "ap12-pink.wav", at=12 * SEC)
    all_speech(s, reference)
    own = {"high_pass": {"frequency": 40, "slope": 24}, "low_shelf": None, "band_1": None,
           "band_2": None, "band_3": None, "high_shelf": {"frequency": 3000, "gain_db": 6},
           "low_pass": None, "bypass": False}
    s.op("set_audio", clips=[target], patch={"eq": own})
    answer = match(s, reference, [target])
    print_answer(answer)
    eq = audio(s, target).get("eq") or {}
    gains = [slot.get("gain_db", 0) for key, slot in eq.items()
             if key in ("low_shelf", "band_1", "band_2", "band_3", "high_shelf") and slot]
    worst, loud = compare(ranged(s, "ref", 0, 10 * SEC), ranged(s, "tgt", 12 * SEC, 22 * SEC))
    check(eq.get("high_pass") == {"frequency": 40.0, "slope": 24}
          and all(abs(g) <= 1 for g in gains) and worst <= 1,
          f"A5 the high-pass kept {eq.get('high_pass')}, the fitted gains {gains} within ±1 dB, "
          f"bands within ±1 dB (largest {f(worst)}; loudness {f(loud)} LU)")
    m.call("close_project", project=s.path, discard=True)


# ---- A6 refusals and skips ---------------------------------------------------

def refusal_rows(m):
    print("\nA6 — refusals and skips by name")
    s = Session(m, "ap12-refuse")
    reference = place(s, "ap12-pink.wav")
    target = place(s, "ap12-pink.wav", at=12 * SEC)
    silent = place(s, "ap12-silence.wav", track=s.add_track())
    s.op("set_audio", clips=[target], patch={"volume": 0.5})
    all_speech(s, reference)
    project = s.project()
    for kwargs, names, label in (
            ({"clips": [target]}, ["reference"], "a missing reference"),
            ({"reference": silent, "clips": [target]}, [f"clip {silent}", "−70"],
             "a silent reference"),
            ({"reference": reference, "clips": [target], "loudness": False, "eq": False},
             ["loudness", "eq"], "loudness and eq both false"),
            ({"reference": reference, "clips": [target], "gain": 2}, ["gain"],
             "an unknown key")):
        text = s.error("match_audio", **kwargs) or ""
        check(all(n in text for n in names) and "made no change" not in text,
              f"A6 {label} refused naming {names}: {text[:110]!r}")
    check(s.project() == project, "A6 and the refusals changed nothing")
    answer = match(s, reference, [target, silent])
    skipped = answer.get("skipped") or []
    check([r["clip"] for r in answer["matched"]] == [target] and len(skipped) == 1
          and skipped[0].startswith(f"clip {silent}:"),
          f"A6 the silent target skipped by name beside a matched one: {skipped}")
    m.call("close_project", project=s.path, discard=True)


# ---- A7 the menu ---------------------------------------------------------------

def menu_rows(m, pink_name, tool_set):
    print("\nA7 — Clip ▸ Match Audio… writes what the tool writes")
    launched = mcp_module.launch(
        proof_app.binary(), arguments=["-RCDevMatchAudioAccept", "YES"])
    try:
        if not check(launched.client is not None, "A7 an instance with the accept comes up"):
            return
        other = launched.client
        s = Session(other, "ap12-menu")
        reference = place(s, "ap12-pink.wav")
        target = place(s, pink_name, at=12 * SEC)
        second = place(s, "ap12-pink.wav", track=s.add_track(), at=12 * SEC)
        s.op("set_audio", clips=[second], patch={"volume": 0.3})
        for clip in (reference, target):
            all_speech(s, clip)
        before = audio(s, target)
        s.op("set_selection", clips=[reference, target, second])
        menu = s.op("perform_menu_item", path=["Clip", "Match Audio…"])
        began = time.monotonic()
        held = before
        while time.monotonic() - began < 600:
            sheet = ((s.op("perform_menu_item").get("window") or {}).get("sheet"))
            held = audio(s, target)
            if sheet is None and held != before:
                break
            time.sleep(0.2)
        check(held != before and not mismatches(held, tool_set or {}, volume_db=0.05),
              f"A7 the menu (sheet {menu.get('sheet')!r}, done after "
              f"{round(time.monotonic() - began, 2)} s) holds the tool's set "
              f"{mismatches(held, tool_set or {}, volume_db=0.05)}")
        other.call("close_project", project=s.path, discard=True)
    finally:
        launched.stop()


def log_rows():
    print("\nA8 — the parity log")
    log = os.path.join(os.path.dirname(p5.SOCKET), "framejob.log")
    if not os.path.exists(log):
        check(False, f"A8 {log} exists")
        return
    with open(log, encoding="utf-8", errors="replace") as handle:
        lines = [line.rstrip() for line in handle if "Frame Job: " in line]
    check(not lines, f"A8 no \"Frame Job: \" line in {log}: {lines[:3]}")


def main():
    os.makedirs(p5.WORK, exist_ok=True)
    fixtures()
    m = MCP(p5.SOCKET)
    # AP12_ONLY=pink,speech,… runs only those parts while iterating; a recorded
    # run sets nothing and runs them all.
    only = set(filter(None, os.environ.get("AP12_ONLY", "").split(",")))
    errors = (ToolError, KeyError, IndexError, RuntimeError, OSError, ValueError, TypeError)
    pink_name, tool_set = None, None
    for name, part in (("pink", pink_rows), ("speech", speech_rows), ("owner", owner_rows),
                       ("own", own_eq_rows), ("refuse", refusal_rows)):
        if only and name not in only:
            continue
        try:
            result = part(m)
            if part is pink_rows:
                pink_name, tool_set = result
        except errors as error:
            check(False, f"{part.__name__} aborted: {type(error).__name__}: {error}")
    if not only or "menu" in only:
        if pink_name is not None:
            try:
                menu_rows(m, pink_name, tool_set)
            except errors as error:
                check(False, f"menu_rows aborted: {type(error).__name__}: {error}")
        else:
            check(False, "A7 skipped: no tool row to compare with")
    log_rows()
    print(f"\n{checks - len(failures)}/{checks} checks passed")
    for line in failures:
        print(f"  FAILED: {line}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
