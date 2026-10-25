#!/usr/bin/env python3
"""Issue #351: the speech cache's accept/reject rules and the shared append's
wait, from app/Sources through swift_build (`speech_cache_probe.swift`).

S1-S9 `loadSpeech` and `speechIsCurrent` over scratch files; W0-W3
`writeSpeech` with a nil stamp, a marker that will not write, and a refused
pair rebuilt (the Silero model is copied beside the binary); A1-A3
`AudioRateCopy.append`'s wait, which `Transcriber.extract` calls since #351.
A build failure is scored. --sources points at a copied app/Sources tree;
--mutant NAME (or `all`) applies one of MUTANTS to a copy and answers MUTANT
PASS when exactly its rows failed. Everything is written beneath
tools/proof/work/speech-cache-probe.
"""
import argparse
import math
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import wave

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/speech-cache-probe"

# name: (file in app/Sources, [(old, new)…], the rows that must fail)
MUTANTS = {
    "no-marker-gate": ("MediaCacheFiles.swift", [(
        "        guard readSpeechStamp(at: speechMarkerURL(for: media, in: cacheDir))?.version\n"
        "            == speechVersion\n        else { return nil }\n", "")], {"S2", "S3", "S4"}),
    "no-whole-floats": ("MediaCacheFiles.swift", [(", data.count % 4 == 0\n", "\n")],
                        {"S5", "S9"}),
    "current-by-exists": ("MediaImporter+Speech.swift", [(
        "return loadSpeech(for: media.id, in: cacheDir) != nil",
        "return FileManager.default.fileExists(atPath: speechURL(for: media.id, in: cacheDir).path)"
    )], {"S9"}),
    "nil-stamp-writes": ("MediaImporter+Speech.swift", [
        ("guard let stamp, let vad = SileroVAD.bundled() else { return }",
         "guard let vad = SileroVAD.bundled() else { return }"),
        ("            let marker = speechMarkerURL(for: media.id, in: cacheDir)\n",
         "            guard let stamp else { return }\n"
         "            let marker = speechMarkerURL(for: media.id, in: cacheDir)\n")], {"W1"}),
    "no-rollback": ("MediaImporter+Speech.swift", [(
        "                try? FileManager.default.removeItem(at: file)\n                return\n"
        "            }\n            postCacheChange(media: media.id, kind: speechKind)",
        "                return\n            }\n"
        "            postCacheChange(media: media.id, kind: speechKind)")], {"W2"}),
    "no-cancel-in-wait": ("AudioRateCopy.swift", [
        ("            if cancelled() { return \"cancelled\" }\n", "")], {"A2"}),
    "no-status-exit": ("AudioRateCopy.swift", [(
        "            guard writer.status == .writing else {\n"
        "                return writer.error?.localizedDescription ?? \"the writer stopped\"\n"
        "            }\n", "")], {"A1"}),
}


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def fixture():
    """One second of a 16 kHz mono 440 Hz tone, 16-bit."""
    path = WORK / "tone.wav"
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(16_000)
        out.writeframes(b"".join(
            struct.pack("<h", round(0.25 * 32767 * math.sin(2 * math.pi * 440 * n / 16_000)))
            for n in range(16_000)))
    return path


def build(sources):
    entry = WORK / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/speech_cache_probe.swift", entry)
    binary = WORK / "bin" / "speech-cache-probe"
    binary.parent.mkdir(parents=True, exist_ok=True)
    swift = sorted(str(p) for p in sources.glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    # `SileroVAD.bundledURL` looks beside a binary that is not a bundle.
    models = binary.parent / "Models"
    shutil.rmtree(models, ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Models", models)
    return binary, ""


def probe(sources, echo=True):
    """The run's failed row ids, or None when the probe would not build."""
    shutil.rmtree(WORK / "cache", ignore_errors=True)
    (WORK / "cache").mkdir(parents=True)
    wav = fixture()
    binary, problem = build(sources)
    if not check("B0 the probe builds", binary is not None, problem):
        return None
    result = subprocess.run([str(binary), str(wav), str(WORK / "cache")],
                            capture_output=True, text=True, timeout=300)
    if echo:
        sys.stdout.write(result.stdout)
    failed = {line.split()[1] for line in result.stdout.splitlines()
              if line.strip().startswith("FAIL")}
    if result.returncode != 0 and not failed:
        failed.add("exit")
    check("the probe exits 0", result.returncode == 0, result.stderr[-600:])
    return failed


def mutant(name):
    file, edits, expected = MUTANTS[name]
    copy = WORK / f"mutant-{name}"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(ROOT / "app/Sources", copy)
    text = (copy / file).read_text()
    for old, new in edits:
        if text.count(old) != 1:
            return check(f"MUTANT {name} applies", False, f"{old!r} found {text.count(old)}x")
        text = text.replace(old, new)
    (copy / file).write_text(text)
    failed = probe(copy, echo=False)
    shutil.rmtree(copy, ignore_errors=True)
    return check(f"MUTANT {'PASS' if failed == expected else 'FAIL'} {name}",
                 failed == expected,
                 f"failed {sorted(failed) if failed is not None else 'the build'}, "
                 f"expected {sorted(expected)}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutant", choices=sorted(MUTANTS) + ["all"])
    args = parser.parse_args()
    if args.mutant:
        names = sorted(MUTANTS) if args.mutant == "all" else [args.mutant]
        return 0 if all([mutant(name) for name in names]) else 1
    failed = probe(args.sources)
    return 0 if failed == set() else 1


if __name__ == "__main__":
    sys.exit(main())
