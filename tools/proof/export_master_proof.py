"""The export's master (road map "audio" AP2 part 2, spec §11 AU-27..AU-29).

    python3 tools/proof/export_master_proof.py <dir>/agent.sock [--only X1,X5,...]
    python3 tools/proof/export_master_proof.py --probe

Every export with sound reads the mix as float, gains it, holds it under its
`peak_dbtp` (−1 dBTP by default) with the master limiter, compensates the
limiter's 158 frames and quantises once to 16 or 24 bits. Every ceiling here
is MEASURED on the exported file by `limiter_probe.py`'s two meters
(`true_peaks`: a 4x, 64-tap-per-phase Kaiser beta 10 oversampler and BS.1770-4
Annex 2's phases, both over |x|), and every loudness by `phase5_proof.py`'s
BS.1770-4 pass, never read back from the app alone.

Over MCP (the caller owns the instance; nothing is launched or killed; every
project is closed with `discard`):

  X1  two limited crest clips (volume 8, clip limiter −1) through a 1 s
      cross-dissolve, no peak_dbtp: <= −1 + 0.001 dBTP by both meters; the
      same with peak_dbtp 0 reads over −1 (AU-22's case is real).
  X2  a nest clip at volume 2 around a limited clip (volume 8, −1): the same.
  X3  an action raising a limited clip's volume 1 → 4: the same.
  X4  peak_dbtp −3 alone (no loudness_lufs), the crest at volume 2: accepted,
      echoed (ceiling_dbtp −3, no target_lufs), <= −3 + 0.001 by both meters.
  X5  half.wav (a 0.5 sine) at volume 4 un-normalised: no full-scale sample,
      <= −1 + 0.001 by both meters, its steady 0.5–2.5 s within −50 dB of a
      fitted 440 Hz sine, limited_db 7.0 ± 0.2, no "clipped".
  X6  half.wav exported un-normalised (under the ceiling) decodes identical
      to the fixture's own PCM, its first and last 158 frames included.
  X7  audio_bits 24 on audio_wav and audio_aiff: ffprobe pcm_s24le and
      pcm_s24be, the two decode alike; a quiet tone normalised to −20 LUFS has
      non-zero low 8 bits in >= 90 % of its samples, and its 16-bit twin is it
      rounded within 1 LSB; the result echoes audio_bits 24.
  X8  a float32 fixture tone at −90 dBFS, clip volume 32, un-normalised at 24
      bits: its sine-fit residual <= −120 dBFS, where the 16-bit export of the
      same reads >= −105.
  X9  phase5's crest fixture normalised to −14 LUFS: within ±0.5 LU,
      <= −1 + 0.001 by both meters.
  X10 samples/Rode-usb-mic.m4a, the clip raw, loudness −16: within ±0.5 LU,
      <= −1 + 0.001 by both meters (skipped by name when the file is absent).
  X11 audio_bits refused on h264 and as 20, by name; a result's loudness has
      limited_db and capped_by_gain and no capped_by_peak.

`--probe` (no app) builds `export_master_probe.swift` with app/Sources through
`swift_build` and scores its rows M1–M3: the master's placement by stamp (a
hole fed as zeros, an overlap's covered head cut, a late first buffer). A probe
that will not build is a scored failure. Rows print `<ID> ok|FAIL — <detail>`,
then `n/m`; exit 0 iff every row asked passed. Needs ffmpeg, ffprobe and numpy.
Output is under tools/proof/work/export-master/.
"""

import argparse
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import sys
import wave

import numpy as np

import limiter_probe
import phase5_proof as p5
import swift_build
from mcp import MCP, ToolError
from phase5_proof import Session

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WORK = HERE / "work" / "export-master"
RODE = ROOT / "samples" / "Rode-usb-mic.m4a"
CREST = "limiter-crest.wav"          # S1's crest signal halved, limiter_proof's fixture
QUIET = "master-quiet.wav"           # a 0.02 sine, 3 s, 16-bit
FAINT = "master-faint-f32.wav"       # a −90 dBFS 440 Hz sine, 3 s, float32
SEC = p5.SEC
LATENCY = 158
X_ROWS = [f"X{n}" for n in range(1, 12)]
M_ROWS = ["M1", "M2", "M3"]

rows = []


def row(row_id, ok, detail):
    rows.append((row_id, bool(ok)))
    print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- fixtures and measures -------------------------------------------------

def fixtures():
    p5.write_fixtures()
    limiter_probe_fixture()
    for name, expression, codec in (
            (QUIET, "0.02*sin(2*PI*440*t)", "pcm_s16le"),
            (FAINT, f"{10 ** (-90 / 20):.12f}*sin(2*PI*440*t)", "pcm_f32le")):
        subprocess.run(
            ["ffmpeg", "-v", "error", "-y", "-f", "lavfi",
             "-i", f"aevalsrc='{expression}|{expression}':s=48000:d=3",
             "-c:a", codec, os.path.join(p5.FIXTURES, name)], check=True, timeout=60)


def limiter_probe_fixture():
    """limiter_proof.py's crest fixture: S1's crest signal halved, stereo."""
    crest = limiter_probe.crest_signal() / 2
    stereo = np.stack([crest, crest[::-1]], axis=1)
    ints = np.clip(np.round(stereo * 32767), -32768, 32767).astype("<i2")
    with wave.open(os.path.join(p5.FIXTURES, CREST), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(48000)
        handle.writeframes(ints.tobytes())


def peaks(path, ceiling):
    kaiser, annex = limiter_probe.true_peaks(path)
    return kaiser, annex, kaiser <= ceiling + 0.001 and annex <= ceiling + 0.001


def peak_text(kaiser, annex):
    return f"{kaiser:.4f} (Kaiser) / {annex:.4f} (Annex 2) dBTP"


def lufs(path):
    return p5.integrated(p5.channels(p5.pcm(path)))


def ints32(path):
    """The file decoded by ffmpeg to signed 32-bit (a 24-bit sample << 8), stereo."""
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-vn", "-f", "s32le", "-acodec", "pcm_s32le",
         "-ar", "48000", "-ac", "2", "-"], capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype="<i4").astype(np.int64)


def s16(path):
    return np.frombuffer(p5.pcm(path), dtype="<i2").astype(np.int64)


def codec_name(path):
    return subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=codec_name", "-of", "csv=p=0", path], capture_output=True,
        text=True).stdout.strip()


def residual_db(left, start, end, frequency=440.0):
    """The RMS, dBFS, of `left[start:end]` less its least-squares sine at `frequency`."""
    t = np.arange(start, end) / 48000.0
    x = np.asarray(left[start:end], dtype=np.float64)
    basis = np.stack([np.sin(2 * np.pi * frequency * t), np.cos(2 * np.pi * frequency * t),
                      np.ones_like(t)], axis=1)
    fit, *_ = np.linalg.lstsq(basis, x, rcond=None)
    rest = x - basis @ fit
    rms = math.sqrt(float(np.mean(rest ** 2)))
    amplitude = math.hypot(fit[0], fit[1])
    return (20 * math.log10(rms) if rms > 0 else -math.inf), amplitude


# ---- the rows ---------------------------------------------------------------

def crest_clip(s, at=0, volume=8, limited=True):
    clip = s.place(CREST, at=at)
    patch = {"volume": volume}
    if limited:
        patch["limiter"] = {}
    s.op("set_audio", clips=[clip], patch=patch)
    return clip


def ceiling_row(m, row_id, label, build):
    """A project `build` makes, exported with no peak_dbtp (the master's −1) and with
    peak_dbtp 0 (the loosest), both measured."""
    s = Session(m, f"master-{row_id.lower()}")
    try:
        build(s)
        held = s.export(f"{row_id.lower()}-held")
        loose = s.export(f"{row_id.lower()}-loose", peak_dbtp=0)
    finally:
        m.call("close_project", project=s.path, discard=True)
    kaiser, annex, under = peaks(held["path"], -1.0)
    loose_k, loose_a, _ = peaks(loose["path"], -1.0)
    real = max(loose_k, loose_a) > -1.0 + 0.001
    row(row_id, under and real,
        f"{label}: {peak_text(kaiser, annex)} at the default ceiling (≤ −1 + 0.001); "
        f"with peak_dbtp 0 it reads {peak_text(loose_k, loose_a)}, so the case passes the "
        f"clip limiter's −1 ({'yes' if real else 'NO — vacuous'})")


def x1(m):
    def build(s):
        a = crest_clip(s)
        end = s.clip(a)["start"] + s.clip(a)["duration"]
        b = crest_clip(s, at=end)
        s.op("add_transition", clip=b, duration=SEC, ripple=True)
    ceiling_row(m, "X1", "two limited crest clips (×8, −1) through a 1 s cross-dissolve", build)


def x2(m):
    def build(s):
        inner = crest_clip(s)
        s.op("nest", clips=[inner])
        nest = next(c["id"] for c in s.project()["clips"]
                    if (c.get("source") or {}).get("kind") == "nest")
        s.op("set_audio", clips=[nest], patch={"volume": 2})
    ceiling_row(m, "X2", "a nest clip at volume 2 around a limited clip (×8, −1)", build)


def x3(m):
    def build(s):
        clip = crest_clip(s, volume=1)
        length = s.clip(clip)["duration"]
        action = s.op("add_action", clip=clip, at=0, duration=length)["new_actions"][0]
        s.op("set_action_end", clip=clip, action=action, patch={"audio": {"volume": 4}})
    ceiling_row(m, "X3", "an action raising a limited clip (−1) from volume 1 to 4", build)


def x4(m):
    s = Session(m, "master-x4")
    try:
        crest_clip(s, volume=2, limited=False)
        result = s.export("x4", peak_dbtp=-3)
    finally:
        m.call("close_project", project=s.path, discard=True)
    loud = result.get("loudness") or {}
    kaiser, annex, under = peaks(result["path"], -3.0)
    row("X4", under and loud.get("ceiling_dbtp") == -3 and "target_lufs" not in loud,
        f"peak_dbtp −3 alone: accepted, ceiling_dbtp {loud.get('ceiling_dbtp')}, target "
        f"{loud.get('target_lufs', 'absent')}; {peak_text(kaiser, annex)} (≤ −3 + 0.001)")


def x5(m):
    s = Session(m, "master-x5")
    try:
        clip = s.place("half.wav")
        s.op("set_audio", clips=[clip], patch={"volume": 4})
        result = s.export("x5")
    finally:
        m.call("close_project", project=s.path, discard=True)
    loud = result.get("loudness") or {}
    data = s16(result["path"])
    full = int(np.sum((data == 32767) | (data == -32768)))
    kaiser, annex, under = peaks(result["path"], -1.0)
    residual, amplitude = residual_db(data[0::2] / 32768.0, 24000, 120000)
    relative = residual - 20 * math.log10(amplitude) if amplitude > 0 else math.inf
    limited = loud.get("limited_db")
    ok = (full == 0 and under and relative <= -50 and limited is not None
          and abs(limited - 7.0) <= 0.2 and "clipped" not in loud.get("summary", ""))
    row("X5", ok,
        f"half.wav ×4 un-normalised: {full} full-scale samples, {peak_text(kaiser, annex)}, "
        f"0.5–2.5 s {relative:.1f} dB from a fitted sine (≤ −50), limited_db {limited} "
        f"(7.0 ± 0.2), summary “{loud.get('summary')}”")


def x6(m):
    s = Session(m, "master-x6")
    try:
        s.place("half.wav")
        result = s.export("x6")
    finally:
        m.call("close_project", project=s.path, discard=True)
    got = s16(result["path"])
    source = s16(os.path.join(p5.FIXTURES, "half.wav"))
    same = len(got) == len(source) and bool(np.array_equal(got, source))
    differ = np.nonzero(got[:min(len(got), len(source))] != source[:min(len(got), len(source))])[0]
    head = bool(np.array_equal(got[:2 * LATENCY], source[:2 * LATENCY]))
    tail = len(got) == len(source) and bool(np.array_equal(got[-2 * LATENCY:],
                                                           source[-2 * LATENCY:]))
    row("X6", same and head and tail,
        f"half.wav un-normalised decodes {'identical' if same else 'DIFFERENT'} to its "
        f"source ({len(got) // 2} vs {len(source) // 2} frames, {len(differ)} samples "
        f"differ); first {LATENCY} frames {'equal' if head else 'DIFFER'}, last "
        f"{LATENCY} {'equal' if tail else 'DIFFER'}")


def x7(m):
    s = Session(m, "master-x7")
    try:
        s.place(QUIET)
        wav = s.export("x7", preset="audio_wav", loudness_lufs=-20, audio_bits=24)
        aiff = s.export("x7", preset="audio_aiff", loudness_lufs=-20, audio_bits=24)
        twin = s.export("x7-16", preset="audio_wav", loudness_lufs=-20)
    finally:
        m.call("close_project", project=s.path, discard=True)
    codecs = (codec_name(wav["path"]), codec_name(aiff["path"]))
    deep = ints32(wav["path"]) >> 8
    deep_aiff = ints32(aiff["path"]) >> 8
    shallow = s16(twin["path"])
    alike = len(deep) == len(deep_aiff) and bool(np.array_equal(deep, deep_aiff))
    used = float(np.mean((deep & 0xFF) != 0)) if len(deep) else 0.0
    rounded = np.floor(deep / 256.0 + 0.5).astype(np.int64)
    worst = int(np.max(np.abs(rounded - shallow))) if len(rounded) == len(shallow) else None
    echoed = (wav.get("audio_bits"), aiff.get("audio_bits"), twin.get("audio_bits"))
    ok = (codecs == ("pcm_s24le", "pcm_s24be") and alike and used >= 0.9
          and worst is not None and worst <= 1 and echoed == (24, 24, 16))
    row("X7", ok,
        f"codecs {codecs}; WAV and AIFF {'alike' if alike else 'DIFFER'}; low 8 bits "
        f"non-zero in {used * 100:.1f} % (≥ 90); the 16-bit twin within {worst} LSB of the "
        f"24-bit rounded (≤ 1); audio_bits echoed {echoed}")


def x8(m):
    s = Session(m, "master-x8")
    try:
        clip = s.place(FAINT)
        s.op("set_audio", clips=[clip], patch={"volume": 32})
        deep = s.export("x8-24", preset="audio_wav", audio_bits=24)
        shallow = s.export("x8-16", preset="audio_wav")
    finally:
        m.call("close_project", project=s.path, discard=True)
    deep_left = (ints32(deep["path"]) >> 8)[0::2] / 8388608.0
    shallow_left = s16(shallow["path"])[0::2] / 32768.0
    deep_db, deep_amp = residual_db(deep_left, 24000, 120000)
    shallow_db, _ = residual_db(shallow_left, 24000, 120000)
    row("X8", deep_db <= -120 and shallow_db >= -105,
        f"a −90 dBFS float tone ×32 (amplitude {deep_amp:.6f}): sine-fit residual "
        f"{deep_db:.1f} dBFS at 24 bits (≤ −120), {shallow_db:.1f} dBFS at 16 (≥ −105)")


def x9(m):
    s = Session(m, "master-x9")
    try:
        s.place("crest.wav")
        result = s.export("x9", loudness_lufs=-14)
    finally:
        m.call("close_project", project=s.path, discard=True)
    landed = lufs(result["path"])
    kaiser, annex, under = peaks(result["path"], -1.0)
    row("X9", p5.close(landed, -14.0, 0.5) and under,
        f"phase5's crest fixture to −14: {p5.fmt(landed)} LUFS (±0.5), "
        f"{peak_text(kaiser, annex)} (≤ −1 + 0.001); {result['loudness'].get('summary')}")


def x10(m):
    if not RODE.exists():
        row("X10", True, f"SKIPPED: {RODE.relative_to(ROOT)} is absent")
        return
    shutil.copyfile(RODE, os.path.join(p5.FIXTURES, "rode.m4a"))
    s = Session(m, "master-x10")
    try:
        s.place("rode.m4a")
        result = s.export("x10", loudness_lufs=-16)
    finally:
        m.call("close_project", project=s.path, discard=True)
    landed = lufs(result["path"])
    kaiser, annex, under = peaks(result["path"], -1.0)
    row("X10", p5.close(landed, -16.0, 0.5) and under,
        f"the owner's recording raw to −16: {p5.fmt(landed)} LUFS (±0.5), "
        f"{peak_text(kaiser, annex)} (≤ −1 + 0.001); {result['loudness'].get('summary')}")


def x11(m):
    s = Session(m, "master-x11")
    try:
        s.place("half.wav")
        on_h264 = s.error("export", preset="h264", path=str(WORK / "x11-h264"),
                          audio_bits=24) or ""
        twenty = s.error("export", preset="audio_wav", path=str(WORK / "x11-20"),
                         audio_bits=20) or ""
        result = s.export("x11", loudness_lufs=-16)
    finally:
        m.call("close_project", project=s.path, discard=True)
    loud = result.get("loudness") or {}
    keys = "limited_db" in loud and "capped_by_gain" in loud and "capped_by_peak" not in loud
    ok = ("h264" in on_h264 and "audio_bits" in on_h264 and "audio_bits" in twenty
          and "20" in twenty and keys)
    row("X11", ok,
        f"on h264: {on_h264[:110]!r}; as 20: {twenty[:110]!r}; loudness keys "
        f"{sorted(loud)}")


X_RUN = {"X1": x1, "X2": x2, "X3": x3, "X4": x4, "X5": x5, "X6": x6, "X7": x7, "X8": x8,
         "X9": x9, "X10": x10, "X11": x11}


# ---- the probe ----------------------------------------------------------------

def probe(asked):
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "export_master_probe.swift", entry)
    binary = out / "export-master-probe"
    try:
        swift_build.build(sources=[str(p) for p in swift_build.app_sources()] + [str(entry)],
                          output=binary)
    except swift_build.SwiftBuildFailed as error:
        for name in asked:
            row(name, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=600)
    try:
        answers = {r["name"].split()[0]: r for r in json.loads(ran.stdout)["rows"]}
    except (ValueError, KeyError):
        for name in asked:
            row(name, False, f"the probe did not answer: {ran.stderr[-400:]}")
        return
    for name in asked:
        answer = answers.get(name)
        if answer is None:
            row(name, False, "the probe gave no such row")
        else:
            row(name, answer["ok"], answer["name"] + " — " + answer["detail"])


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--only")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    os.makedirs(p5.WORK, exist_ok=True)
    asked = args.only.split(",") if args.only else (M_ROWS if args.probe else X_ROWS)
    if args.probe:
        probe([a for a in asked if a in M_ROWS])
    else:
        if not args.socket:
            print("usage: export_master_proof.py <dir>/agent.sock [--only …] | --probe")
            return 2
        fixtures()
        m = MCP(args.socket)
        for name in asked:
            try:
                X_RUN[name](m)
            except (ToolError, KeyError, IndexError, RuntimeError, OSError, StopIteration,
                    subprocess.CalledProcessError) as error:
                row(name, False, f"aborted: {type(error).__name__}: {error}")
    passed = sum(1 for _, ok in rows if ok)
    print(f"{passed}/{len(rows)}", flush=True)
    return 0 if rows and passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
