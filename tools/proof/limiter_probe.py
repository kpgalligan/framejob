"""The clip limiter's probe (road map "audio" AP2, spec §11 AU-20..AU-25).

`limiter_probe.swift` compiled with app/Sources through swift_build: the
product's `AudioLimiterStage`, chain, tap context, schedule, `AudioLimiterModel`
and Normalize plan, run on S1's crest signal and the owner's recording.

  L1  latency: an impulse comes out 158 samples late and unchanged; the leads
      (1,975 ticks, 8,375 with noise reduction).
  L2  the ceiling, by THIS script's own meters (a 4x, 64-tap-per-phase Kaiser
      beta 10 oversampler and BS.1770-4 Annex 2's 12-tap phases, both over |x|
      too): every output at or under its ceiling + 0.001 dB, at -1, -3 and 0 dBTP,
      on the crest signal, the recording +28 dB, a stereo pair, the recording
      normalised (L8's output) and a clip told its base volume (x8 material at
      volume 4, through `AudioDSPParameters`).
  L3  512, 4096 and irregular blocks byte-identical, settings changing at cuts.
  L4  reset() gives a fresh stage's bytes.
  L5  nil settings: an exact delay.
  L6  the release reaches exactly 1 (the output equals the input after it).
  L7  the product's tap context under a muted AVPlayer against an AVAssetReader:
      the same samples within the first 4 s (S1's method).
  L8  AudioLimiterModel's loudness against the stage's (LoudnessMeter) on the
      owner's recording, Normalize's own volume and limiter: <= 0.3 LU.
  L9  NormalizeChoice's default mode is Loudness.

--measure <file> prints a file's true peak by both meters (any file ffmpeg
reads; other proofs import `true_peaks`). --mutants runs the mutants, each over
its own copy of app/Sources, scored killed when its named row fails. Build
failures are scored. Needs ffmpeg, numpy and samples/Rode-usb-mic.m4a. Output
is under tools/proof/work/limiter-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np

import swift_build

ROOT = Path(__file__).resolve().parents[2]
RODE = ROOT / "samples/Rode-usb-mic.m4a"
WORK = ROOT / "tools/proof/work/limiter-probe"
FIXTURES = WORK / "fixtures"
FS = 48000
ROWS = [f"L{n}" for n in range(1, 10)]

MUTANTS = [
    ("M1 annex2-only", "L2", "AudioLimiterStage.swift",
     "for phase in 0..<3 {", "for phase in 0..<0 {"),
    ("M2 kaiser-only", "L2", "AudioLimiterStage.swift",
     "// Annex 2 at m: x[m − 5 … m + 6].\n                for phase in 0..<4 {",
     "// Annex 2 at m: x[m − 5 … m + 6].\n                for phase in 0..<0 {"),
    ("M5 gain-not-told", "L2", "AudioTapSchedule.swift",
     # Re-aimed (#554): the base volume is the local `volume` there now.
     "ceilingDb: $0.ceilingDb, volume: volume,", "ceilingDb: $0.ceilingDb, volume: 1,"),
    ("M6 model-off", "L8", "AudioNormalize+Loudness.swift",
     "guard !reading.steps.isEmpty else {", "guard false else {"),
    ("M7 reset-incomplete", "L4", "AudioLimiterStage.swift",
     "        envelope = 1\n        sampleIndex = 0", "        sampleIndex = 0"),
    ("M8 default-peak", "L9", "NormalizeChoice.swift",
     "?? .loudness", "?? .peak"),
]

# ---- the meters -------------------------------------------------------------

TAPS, HALF, BETA = 64, 32, 10.0
_OFFSETS = np.arange(-(HALF - 1), HALF + 1)  # x[m + j]
KAISER = []
for _p in (1, 2, 3):
    _t = _p / 4 - _OFFSETS
    _r = np.clip(1 - (_t / (HALF + 0.5)) ** 2, 0, None)
    _h = np.sinc(_t) * np.i0(BETA * np.sqrt(_r)) / np.i0(BETA)
    KAISER.append(_h / _h.sum())

# BS.1770-4 Annex 2's four phases (as `Loudness.swift` and phase5_proof.py read them).
ANNEX2 = [np.array(row) for row in [
    (0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000, -0.0594482421875,
     0.1373291015625, 0.9721679687500, -0.1022949218750, 0.0476074218750, -0.0266113281250,
     0.0148925781250, -0.0083007812500),
    (-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250, -0.1665039062500,
     0.4650878906250, 0.7797851562500, -0.2003173828125, 0.1015625000000, -0.0582275390625,
     0.0330810546875, -0.0189208984375),
    (-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000, -0.2003173828125,
     0.7797851562500, 0.4650878906250, -0.1665039062500, 0.0891113281250, -0.0517578125000,
     0.0292968750000, -0.0291748046875),
    (-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750, -0.1022949218750,
     0.9721679687500, 0.1373291015625, -0.0594482421875, 0.0332031250000, -0.0196533203125,
     0.0109863281250, 0.0017089843750),
]]


def kaiser_true_peak(x):
    """max(|x|, |x(m + p/4)|) for p = 1..3, linear; zero outside the signal."""
    x = np.asarray(x, dtype=np.float64)
    best = float(np.max(np.abs(x))) if len(x) else 0.0
    for h in KAISER:
        # y[m] = Σ_j h[j] x[m + j], at every m the signal reaches (zeros
        # either side, so the onset and the tail are read too).
        y = np.correlate(np.pad(x, (TAPS, TAPS)), h, mode="valid")
        best = max(best, float(np.max(np.abs(y))))
    return best


def annex2_true_peak(x):
    """max(|x|, |Annex 2's four phases|), linear; the whole convolution."""
    x = np.asarray(x, dtype=np.float64)
    best = float(np.max(np.abs(x))) if len(x) else 0.0
    for phase in ANNEX2:
        best = max(best, float(np.max(np.abs(np.convolve(x, phase)))))
    return best


def db(x):
    return 20 * np.log10(x) if x > 0 else -np.inf


def channels_of(path):
    """A file decoded by ffmpeg to float32 at its own channel count and 48 kHz."""
    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=channels", "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    count = int(probe.stdout.strip() or 2)
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-vn", "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(FS), "-"], capture_output=True, check=True).stdout
    data = np.frombuffer(raw, dtype="<f4").astype(np.float64)
    return [data[c::count] for c in range(count)]


def true_peaks(path):
    """(Kaiser dBTP, Annex 2 dBTP) of a file, the louder channel's."""
    chans = channels_of(path)
    return (db(max(kaiser_true_peak(c) for c in chans)),
            db(max(annex2_true_peak(c) for c in chans)))


# ---- the run ----------------------------------------------------------------

def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def crest_signal():
    """S1's crest signal (its gen_signals.py, its seed), 8 s at 48 kHz: true
    peaks well above sample peaks (fs/4 at 45 degrees, impulse pairs, noise
    bursts, clicks on a tone, a step, pink noise), up to 2.0."""
    rng = np.random.default_rng(20261030)
    rng.standard_normal(10 * FS)
    rng.standard_normal((10 * FS, 2))
    n = np.arange(FS)
    parts = [np.sqrt(2) * np.sin(2 * np.pi * 0.25 * n + np.pi / 4)]
    b = np.zeros(FS)
    for k in range(0, FS - 8, 2400):
        b[k:k + 4] = [1.0, 1.0, -1.0, -1.0]
    parts.append(b)
    c = np.zeros(FS)
    for k in range(0, FS, 12000):
        c[k:k + 4800] = rng.standard_normal(4800) * 0.7
    parts.append(c)
    d = 0.5 * np.sin(2 * np.pi * 60 * n / FS)
    d[::4801] += 1.5
    parts.append(d)
    parts.append(np.concatenate([0.01 * np.sin(2 * np.pi * 1000 * n[:FS // 2] / FS),
                                 2.0 * np.sin(2 * np.pi * 1000 * n[FS // 2:] / FS)]))
    w = rng.standard_normal(3 * FS)
    spectrum = np.fft.rfft(w)
    f = np.fft.rfftfreq(len(w), 1 / FS)
    spectrum[1:] /= np.sqrt(f[1:] / 20)
    spectrum[0] = 0
    pink = np.fft.irfft(spectrum, len(w))
    parts.append(pink * 1.8 / np.max(np.abs(pink)))
    return np.concatenate(parts)


def fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not RODE.exists():
        raise RuntimeError(f"{RODE} is missing (the owner's recording, samples/README.md)")
    shutil.copyfile(RODE, FIXTURES / "rode.m4a")
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(RODE), "-f", "f32le", "-acodec", "pcm_f32le",
         "-ar", str(FS), "-ac", "1", "-"], capture_output=True, check=True).stdout
    (FIXTURES / "rode.f32").write_bytes(raw)
    crest_signal().astype("<f4").tofile(FIXTURES / "crest.f32")


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/limiter_probe.swift", entry)
    binary = out / "limiter-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, name, quiet=False):
    """{row: bool}, the probe's stderr tail, and its printed lines."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    result = subprocess.run([str(binary), str(FIXTURES), str(scratch)], capture_output=True,
                            text=True, timeout=1200)
    rows = {}
    lines = []
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
            lines.append(line)
        elif parts[:1] == ["L2DATA"]:
            name_, ceiling, path = parts[1], float(parts[2]), parts[3]
            x = np.fromfile(path, dtype="<f4")
            k, a = db(kaiser_true_peak(x)), db(annex2_true_peak(x))
            good = bool(k <= ceiling + 0.001 and a <= ceiling + 0.001)
            rows["L2"] = rows.get("L2", True) and good
            lines.append(("  ok   " if good else "  FAIL ")
                         + f"L2 {name_} at {ceiling:g} dBTP: Kaiser {k:.4f}, Annex 2 {a:.4f}")
        else:
            lines.append(line)
    if not quiet:
        print("\n".join(lines))
    return rows, result.stderr[-600:], "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--measure", type=Path)
    args = parser.parse_args()
    if args.measure:
        k, a = true_peaks(args.measure)
        print(f"{args.measure}: Kaiser {k:.4f} dBTP, Annex 2 {a:.4f} dBTP")
        return 0
    try:
        fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
    if args.mutants:
        return mutants(args.sources)
    rows, problem, _ = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    good = all(rows.get(row) for row in ROWS)
    good &= check("every row L1..L9 ran", all(row in rows for row in ROWS),
                  ", ".join(row for row in ROWS if row not in rows) or "")
    passed = sum(1 for row in ROWS if rows.get(row))
    print(f"\n{passed}/{len(ROWS)} rows passed")
    if problem.strip() and not good:
        print("stderr: " + problem)
    return 0 if good else 1


def mutants(sources):
    killed = 0
    for name, row, file, old, new in MUTANTS:
        slug = name.split()[0]
        tree = WORK / f"mutant-{slug}" / "Sources"
        shutil.rmtree(tree, ignore_errors=True)
        shutil.copytree(sources, tree)
        path = tree / file
        text = path.read_text()
        if text.count(old) != 1:
            check(f"mutant {name}", False, f"anchor not found once in {file}")
            continue
        path.write_text(text.replace(old, new))
        rows, problem, _ = run(tree, f"mutant-{slug}", quiet=True)
        if rows is None:
            check(f"mutant {name} ({row})", False, "did not build: " + problem)
            continue
        dead = rows.get(row) is False
        killed += dead
        check(f"mutant {name} killed by {row}", dead,
              f"{row} {'failed' if dead else 'passed'}; failing rows: "
              + ", ".join(sorted(r for r, ok in rows.items() if not ok)))
    print(f"\n{killed}/{len(MUTANTS)} mutants killed")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
