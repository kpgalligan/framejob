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

import swift_build

ROOT = Path(__file__).resolve().parents[2]
SPEECH = ROOT / "tools/proof/media/speech.mov"
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


def edges(name, rate, duration=2):
    """Mono 16-bit PCM at 0.125 whose first frame in every 10 ms bucket is
    0.75 (both int16-exact): a frame that crosses a bucket edge leaves a
    bucket at 0.125, so the oracle is 0.75 in every bucket."""
    path = FIXTURES / name
    expected = [0.0] * (duration * 100)
    frames = bytearray()
    for frame in range(rate * duration):
        level = 0.75 if frame % (rate // 100) == 0 else 0.125
        value = round(level * 32768)
        frames.extend(struct.pack("<h", value))
        bucket = frame * 100 // rate
        expected[bucket] = max(expected[bucket], abs(value) / 32768)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(rate)
        out.writeframes(frames)
    with wave.open(str(path), "rb") as source:
        assert source.getnframes() == rate * duration
    return path, expected


def fixtures():
    FIXTURES.mkdir(parents=True, exist_ok=True)
    oracle = {}
    for rate in (44100, 48000):
        for channels, stem in ((1, "mono"), (2, "stereo")):
            name = f"{stem}{rate // 1000}.wav" if rate == 48000 else f"{stem}44.wav"
            _, oracle[name] = wav(name, rate, channels)
    _, oracle["silent48.wav"] = wav("silent48.wav", 48000, 1, silent=True)
    _, oracle["edges48.wav"] = edges("edges48.wav", 48000)
    _, oracle["edges44.wav"] = edges("edges44.wav", 44100)
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
    # ffmpeg 9 picks the movie timescale itself (48000 here); the row asks
    # for the millisecond target edit list earlier ffmpeg wrote by default.
    result = run(["ffmpeg", "-y", "-v", "error", "-itsoffset", "0.25", "-i",
                  str(FIXTURES / "stereo48.wav"), "-c:a", "aac", "-b:a", "128k",
                  "-movie_timescale", "1000", str(delayed_aac)])
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
    good = check("fixture frame counts and codec files exist", all(
        (FIXTURES / name).stat().st_size > 44 for name in
        ("mono44.wav", "mono48.wav", "stereo44.wav", "stereo48.wav",
         "silent48.wav", "edges48.wav", "edges44.wav", "tone.aac.m4a",
         "delayed.mov", "delayed.aac.m4a", "corrupt.m4a", "truncated.wav")))
    # Issue #285's media: the README's speech.mov recipe (Phase 4's `say` +
    # ffmpeg block, under "Make the test media once") writes it to media/.
    if SPEECH.exists():
        shutil.copyfile(SPEECH, FIXTURES / "speech.mov")
    elif (FIXTURES / "speech.mov").exists():
        (FIXTURES / "speech.mov").unlink()
    return good & check("speech.mov copied from tools/proof/media", SPEECH.exists(),
                        "" if SPEECH.exists() else
                        f"{SPEECH} is missing: make it with tools/proof/README.md's "
                        "speech.mov recipe (Phase 4's `say` + ffmpeg block)")


def build(sources):
    WORK.mkdir(parents=True, exist_ok=True)
    entry = WORK / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/peaks_probe.swift", entry)
    binary = WORK / "peaks-probe"
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
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
