"""The loudness cache's arithmetic probe (road map "audio" AP1, spec §11 AU-10..AU-15).

`loudness_cache_probe.swift` compiled with app/Sources through swift_build: the
cache built by the product's own pass, read back by `ClipLoudness`, against
`LoudnessMeter` fed exactly each window.

  C1   the files: width, size and marker, mono and stereo.
  C2   the whole owner's recording against the meter as dual mono (0.1 LU, TP 0.01 dB).
  C3   spike S4's ten named windows forward (0.1 LU).
  C4   the same windows reversed, against the meter on reversed samples (0.1 LU).
  C5   stereo identity, mono fold and hard pan against the meter on transformed samples.
  C6   44.1 kHz fixtures against the meter on ffmpeg's 48 kHz copies (0.1 LU).
  C7   under 0.4 s played and a -85 dBFS tone read nil.
  C8   Loudness mode's three caps, limited_by, a tie, a turn-down, the non-finite target.
  C9   a stale-version or other-grain marker reads absent.
  C10  ClipLoudness.Memo: pending, held, then the reading after invalidate().
  C11  the memo through a live edit: the held reading, no file read, no recompute.

Build failures are scored. --sources points at a copied app/Sources tree;
--mutants runs the seven arithmetic mutants, each over its own copy, and
scores each killed when its named row fails. Needs ffmpeg and
samples/Rode-usb-mic.m4a. All output is under tools/proof/work/loudness-cache-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
RODE = ROOT / "samples/Rode-usb-mic.m4a"
WORK = ROOT / "tools/proof/work/loudness-cache-probe"
FIXTURES = WORK / "fixtures"

MUTANTS = [
    ("mono-not-doubled", "C2", "ClipLoudness.swift",
     "return 2 * Double(r[base]) }  // dual mono", "return Double(r[base]) }  // dual mono"),
    ("reversed-forward-order", "C4", "ClipLoudness.swift",
     "steps.append(energy(cache, from: min(a, b), to: max(a, b), matrix))",
     "steps.insert(energy(cache, from: min(a, b), to: max(a, b), matrix), "
     "at: pivot == nil ? steps.count : steps.count - Int(k))"),
    ("no-relative-gate", "C3", "ClipLoudness.swift",
     "let kept = gated.filter { loudness($0) > threshold }", "let kept = gated; _ = threshold"),
    ("no-true-peak-cap", "C8", "AudioNormalize+Loudness.swift",
     "let cap = min(peakCap, maxGain)", "let cap = maxGain"),
    ("limited-by-nil", "C8", "AudioNormalize+Loudness.swift",
     "let limit: Limit? = wanted <= cap ? nil", "let limit: Limit? = true ? nil"),
    ("tables-at-44k", "C6", "LoudnessBlocks.swift",
     "if sampleRate == LoudnessMeter.requiredSampleRate {", "if sampleRate > 0 {"),
    ("version-unchecked", "C9", "MediaImporter+Loudness.swift",
     "marker.version == loudnessVersion,", "marker.version >= 0,"),
]


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def ffmpeg(*args):
    result = subprocess.run(["ffmpeg", "-y", "-v", "error", *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError("ffmpeg " + " ".join(args) + ": " + result.stderr[-400:])


def fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    if not RODE.exists():
        raise RuntimeError(f"{RODE} is missing (the owner's recording, samples/README.md)")
    rode = FIXTURES / "rode.m4a"
    shutil.copyfile(RODE, rode)
    # L the recording, R the recording reversed at -6 dB: S4's stereo fixture.
    ffmpeg("-i", str(rode), "-filter_complex",
           "[0:a]asplit[a][b];[b]areverse,volume=-6dB[r];[a][r]join=inputs=2:channel_layout=stereo[o]",
           "-map", "[o]", "-ar", "48000", "-c:a", "pcm_f32le", str(FIXTURES / "stereo.wav"))
    ffmpeg("-i", str(rode), "-ar", "44100", "-c:a", "pcm_f32le", str(FIXTURES / "rode44.wav"))
    # 30 Hz and 1.6 kHz: where the RLB high-pass and the shelf move with the rate.
    ffmpeg("-f", "lavfi", "-i", "sine=f=30:r=44100:d=10", "-f", "lavfi",
           "-i", "sine=f=1600:r=44100:d=10", "-filter_complex", "amix=inputs=2",
           "-c:a", "pcm_f32le", str(FIXTURES / "tone44.wav"))
    for stem in ("rode44", "tone44"):
        ffmpeg("-i", str(FIXTURES / f"{stem}.wav"), "-ar", "48000", "-c:a", "pcm_f32le",
               str(FIXTURES / f"{stem}to48.wav"))
    # ffmpeg's sine is at 1/8 (-18 dBFS); -67 dB more is about -85 dBFS.
    ffmpeg("-f", "lavfi", "-i", "sine=f=1000:r=48000:d=5", "-af", "volume=-67dB",
           "-c:a", "pcm_f32le", str(FIXTURES / "quiet48.wav"))


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/loudness_cache_probe.swift", entry)
    binary = out / "loudness-cache-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    return binary, ""


def run(sources, name):
    """The probe's lines and whether each row passed: {row: bool}."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem, ""
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    result = subprocess.run([str(binary), str(FIXTURES), str(scratch)], capture_output=True,
                            text=True, timeout=900)
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
    return rows, result.stderr[-600:], result.stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", action="store_true")
    args = parser.parse_args()
    try:
        fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
    if args.mutants:
        return mutants(args.sources)
    rows, problem, stdout = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    sys.stdout.write(stdout)
    expected = [f"C{n}" for n in range(1, 12)]
    good = all(rows.get(row) for row in expected)
    good &= check("every row C1..C11 ran", all(row in rows for row in expected),
                  ", ".join(row for row in expected if row not in rows) or "")
    passed = sum(1 for row in expected if rows.get(row))
    print(f"\n{passed}/{len(expected)} rows passed")
    return 0 if good else 1


def mutants(sources):
    killed = 0
    for name, row, file, old, new in MUTANTS:
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
              f"{row} {'failed' if dead else 'passed'}; failing rows: "
              + ", ".join(sorted(r for r, ok in rows.items() if not ok)))
    print(f"\n{killed}/{len(MUTANTS)} mutants killed")
    return 0 if killed == len(MUTANTS) else 1


if __name__ == "__main__":
    sys.exit(main())
