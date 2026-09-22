#!/usr/bin/env python3
"""Actual app-source peaks importer, publication, and cache readback.

Build failures are scored. --sources points at a copied app/Sources tree for
sequential targeted mutants. All media is authored beneath tools/proof/work.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/peaks-probe"
FIXTURES = WORK / "fixtures"
CACHE = WORK / "cache"


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def run(command):
    return subprocess.run(command, capture_output=True, text=True)


def wav(name, rate, channels, silent=False, duration=1):
    path = FIXTURES / name
    with wave.open(str(path), "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(2)
        out.setframerate(rate)
        frames = bytearray()
        expected = [0.0] * (duration * 100)
        for frame in range(rate * duration):
            loud = 0 if silent else (0.25 if frame < rate * duration * 0.4 else 0.75)
            values = [round(loud * 32768)]
            if channels == 2:
                values.append(0 if silent else round((0.125 if frame < rate * duration * 0.4
                                                       else 0.875) * 32768))
            frames.extend(struct.pack("<" + "h" * channels, *values))
            bucket = frame * 100 // rate
            expected[bucket] = max(expected[bucket],
                                   max(abs(value) / 32768 for value in values))
        out.writeframes(frames)
    with wave.open(str(path), "rb") as source:
        assert source.getnframes() == rate * duration
        assert source.getnchannels() == channels
    return path, expected


def fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    oracle = {}
    for rate in (44100, 48000):
        for channels, stem in ((1, "mono"), (2, "stereo")):
            name = f"{stem}{rate // 1000}.wav" if rate == 48000 else f"{stem}44.wav"
            _, oracle[name] = wav(name, rate, channels)
    _, oracle["silent48.wav"] = wav("silent48.wav", 48000, 1, silent=True)
    (FIXTURES / "expected.json").write_text(json.dumps(oracle))
    # The mono48/stereo48 names are explicit: a rate check must not silently
    # run against a differently sampled fixture.
    assert (FIXTURES / "mono48.wav").exists()
    aac = FIXTURES / "tone.aac.m4a"
    result = run(["ffmpeg", "-y", "-v", "error", "-i", str(FIXTURES / "stereo48.wav"),
                  "-c:a", "aac", "-b:a", "128k", str(aac)])
    if result.returncode: raise RuntimeError("AAC fixture: " + result.stderr)
    delayed = FIXTURES / "delayed.mov"
    result = run(["ffmpeg", "-y", "-v", "error", "-itsoffset", "0.25", "-i",
                  str(FIXTURES / "stereo48.wav"), "-c:a", "pcm_s16le", str(delayed)])
    if result.returncode: raise RuntimeError("delayed PCM edit fixture: " + result.stderr)
    delayed_aac = FIXTURES / "delayed.aac.m4a"
    result = run(["ffmpeg", "-y", "-v", "error", "-itsoffset", "0.25", "-i",
                  str(FIXTURES / "stereo48.wav"), "-c:a", "aac", "-b:a", "128k",
                  str(delayed_aac)])
    if result.returncode: raise RuntimeError("delayed AAC edit fixture: " + result.stderr)
    long, _ = wav("long48.wav", 48000, 1, duration=10)
    corrupt = FIXTURES / "corrupt.m4a"
    result = run(["ffmpeg", "-y", "-v", "error", "-i", str(long), "-c:a", "aac",
                  "-b:a", "128k", str(corrupt)])
    if result.returncode: raise RuntimeError("corrupt AAC fixture: " + result.stderr)
    contents = bytearray(corrupt.read_bytes())
    for index in range(int(len(contents) * .45), int(len(contents) * .70)):
        contents[index] = 0
    corrupt.write_bytes(contents)
    truncated = FIXTURES / "truncated.wav"
    whole = (FIXTURES / "mono48.wav").read_bytes()
    truncated.write_bytes(whole[:44 + 48_000 * 2 * 6 // 10])
    return check("fixture frame counts and codec files exist", all(
        (FIXTURES / name).stat().st_size > 44 for name in
        ("mono44.wav", "mono48.wav", "stereo44.wav", "stereo48.wav",
         "silent48.wav", "tone.aac.m4a", "delayed.mov", "delayed.aac.m4a",
         "corrupt.m4a", "truncated.wav")))


def build(sources):
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/peaks_probe.swift", entry)
    binary = WORK / "peaks-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"]).stdout.strip()
    lib = ROOT / "core/target/release/libreelcut_core.a"
    result = run(["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos15.0",
                  "-module-name", "Reelcut", "-import-objc-header",
                  str(ROOT / "app/Bridging/Reelcut-Bridging-Header.h"),
                  "-L", str(lib.parent), "-lreelcut_core", *swift, str(entry),
                  "-o", str(binary)])
    if result.returncode:
        lines = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc: " + "; ".join(lines[:8] or [result.stderr[-600:]])
    return binary, ""


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    args = parser.parse_args()
    if CACHE.exists(): shutil.rmtree(CACHE)
    CACHE.mkdir(parents=True)
    try:
        good = fixtures()
    except Exception as error:
        check("fixture construction", False, str(error))
        return 1
    binary, problem = build(args.sources)
    good &= check("source probe builds", binary is not None, problem)
    if binary is None:
        print("\n1/2 checks passed" if good else "\n0/2 checks passed")
        return 1
    result = run([str(binary), str(FIXTURES), str(CACHE)])
    sys.stdout.write(result.stdout)
    good &= check("source probe exits successfully", result.returncode == 0,
                  result.stderr[-600:])
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
