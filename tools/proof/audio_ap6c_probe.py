"""Enhance the microphone when it lands — the probe (road map "audio" AP6 part 3,
spec §11 AU-68, AU-69).

`audio_ap6c_probe.swift` compiled with app/Sources through swift_build, with
`app/Resources/Models` copied beside the binary (speech_cache_probe.py's copy),
over `RecorderPanelController.shared` never shown, under grant doors that read
and ask nothing, the eighteen `FrameJobRecording…` values put back at the end:

  P1  the panel's box: its title and key, its row directly under Microphone
      with no label, its tooltip naming the step; an absent key restores off;
      persistChoices writes it and restoreChoices reads it back; Microphone Off
      greys it with its value kept and the choice false; a microphone makes it
      live on a display, Microphone Only and Camera, the choice true; unticked
      the choice false; greyed while counting down and recording.
  P2  `voicePaths`: a voice-over's files; a screen recording's microphone files
      and a left-out segment's, never a movie or the camera; none without a
      microphone.
  P3  `decide`'s table: drop before enhance before give-up, 299 s waits and
      300 s gives up, busy waits.
  P4  `recordingEnhance`: absent, false and null false; "yes" boolArg's
      sentence; true without a microphone the microphone sentence, with
      place false the place sentence, both wrong the microphone sentence.
  P5  the follow's end: after `.drop` (`tick` driven) and after `.enhance` (the
      follow's own timer, a silent voice measured in a document with its
      editor window, refused at the inspector's foot under −70 LUFS), not
      pending and the timer invalid, one refusal.
  P6  the follow IS the press (AU-68 (e), #412), read from the sources by this
      runner (so a mutant's copy is what it reads): `AudioEnhance.choose(` and
      `AudioEnhance.jobs(` each appear once across the sources, both in
      `AudioMeasureDoor.swift`; `enhance_voice`'s `enhanceVoice(_ a:)` makes
      one `onMain` hop and never calls `enhanceVoice(document:`; in
      `enhanceLanded` and `enhanceRead` the run is made only after the
      `isEmpty` refusal.

--mutants runs M1–M10, each over its own copy of app/Sources, scored killed when
its named row fails. Build failures are scored. Output is under
tools/proof/work/audio-ap6c-probe.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/audio-ap6c-probe"
ROWS = ["P1", "P2", "P3", "P4", "P5", "P6"]

# M10's anchor: `enhanceVoice(_ a:)`'s one hop through to its measured call.
ONE_HOP = (
    "        let read = try onMain { () throws -> EnhanceRead in\n"
    "            let document = try self.target(a)\n"
    "            let clips = try self.clipsArg(a, \"clips\", document)\n"
    "            let range = AudioNormalize.targetLUFSRange\n"
    "            let requested = try self.doubleArg(a, \"target_lufs\")\n"
    "                ?? AudioNormalize.defaultTargetLUFS\n"
    "            guard requested.isFinite, range.contains(requested) else {\n"
    "                throw ToolError(\n"
    "                    message: \"target_lufs must be a loudness from \\(range.lowerBound) to \"\n"
    "                        + \"\\(range.upperBound) LUFS, and the default is \"\n"
    "                        + \"\\(AudioNormalize.defaultTargetLUFS).\")\n"
    "            }\n"
    "            return try self.enhanceRead(document: document, clips: clips, "
    "targetLUFS: requested)\n"
    "        }\n"
    "        return try enhanceMeasured(read, stop: stop)\n")
TWO_HOPS = (
    ONE_HOP
    .replace("        let read = try onMain { () throws -> EnhanceRead in\n",
             "        let (document, clips, requested) = try onMain {\n"
             "            () throws -> (ProjectDocument, [UInt32], Double) in\n")
    .replace("            return try self.enhanceRead(document: document, clips: clips, "
             "targetLUFS: requested)\n",
             "            return (document, clips, requested)\n")
    .replace("        return try enhanceMeasured(read, stop: stop)\n",
             "        _ = stop\n"
             "        return try enhanceVoice(document: document, clips: clips, "
             "targetLUFS: requested)\n"))

MUTANTS = [
    ("M1 absent-key-on", "P1", "RecorderPanelController+Choices.swift",
     "            defaults.bool(forKey: Self.enhanceMicrophoneKey) ? .on : .off",
     "            (defaults.object(forKey: Self.enhanceMicrophoneKey) == nil\n"
     "                || defaults.bool(forKey: Self.enhanceMicrophoneKey)) ? .on : .off"),
    ("M2 no-mic-ignored", "P1", "RecorderPanelController+Choices.swift",
     "choice.enhanceMicrophone = enhanceMicrophoneCheckbox.state == .on && choice.microphone != nil",
     "choice.enhanceMicrophone = enhanceMicrophoneCheckbox.state == .on"),
    ("M3 movie-is-voice", "P2", "RecordingEnhance.swift",
     "if result.isVoiceOver { paths += result.segments.map { $0.descriptor.path } }",
     "paths += result.segments.map { $0.descriptor.path }"),
    ("M4 wait-limit-3", "P3", "RecordingEnhance.swift",
     "static let waitLimit: TimeInterval = 300", "static let waitLimit: TimeInterval = 3"),
    ("M5 busy-ignored", "P3", "RecordingEnhance.swift",
     "if analysed && !busy { return .enhance(clips) }", "if analysed { return .enhance(clips) }"),
    ("M6 give-up-first", "P3", "RecordingEnhance.swift",
     "        if clips.isEmpty { return .drop }\n",
     "        if elapsed >= waitLimit { return .giveUp }\n        if clips.isEmpty { return .drop }\n"),
    ("M7 no-mic-admitted", "P4", "AgentServer+RecordingArguments.swift",
     "        guard microphone else {\n", "        guard microphone || true else {\n"),
    ("M8 place-false-admitted", "P4", "AgentServer+RecordingArguments.swift",
     "        guard place else {\n", "        guard place || true else {\n"),
    ("M9 follow-kept", "P5", "RecordingEnhance.swift",
     "        end(follow, key: document.recipeKey)\n", "        _ = follow\n"),
    ("M10 two-hops", "P6", "AgentServer+EnhanceVoice.swift", ONE_HOP, TWO_HOPS),
]


def between(text, start, end):
    """The text from `start` up to the next `end` after it, or None."""
    at = text.find(start)
    if at < 0:
        return None
    stop = text.find(end, at + len(start))
    return text[at:] if stop < 0 else text[at:stop]


def one_setup(sources):
    """P6's checks over `sources`: [(name, good, detail)]."""
    files = {p.name: p.read_text() for p in Path(sources).glob("*.swift")}
    checks = []
    for call in ("AudioEnhance.choose(", "AudioEnhance.jobs("):
        where = {name: text.count(call) for name, text in files.items() if call in text}
        checks.append((f"{call} once, in AudioMeasureDoor.swift",
                       where == {"AudioMeasureDoor.swift": 1}, f"{where}"))
    server = files.get("AgentServer+EnhanceVoice.swift", "")
    entry = between(server, "func enhanceVoice(_ a:", "func ")
    checks.append(("enhanceVoice(_ a:) makes one onMain hop, never enhanceVoice(document:",
                   entry is not None and entry.count("onMain") == 1
                   and "enhanceVoice(document:" not in entry,
                   "no enhanceVoice(_ a:)" if entry is None else
                   f"onMain {entry.count('onMain')}, enhanceVoice(document: "
                   f"{entry.count('enhanceVoice(document:')}"))
    door = files.get("AudioMeasureDoor.swift", "")
    for name, body in (("enhanceLanded", between(door, "static func enhanceLanded(",
                                                  "static func ")),
                       ("enhanceRead", between(server, "private func enhanceRead(", "func "))):
        empty = body.find("isEmpty") if body else -1
        made = body.find("makeRun(") if body else -1
        checks.append((f"{name} makes its run only after the isEmpty refusal",
                       0 <= empty < made,
                       f"isEmpty at {empty}, makeRun( at {made}"))
    return checks


def check(name, good, detail=""):
    print(("  ok   " if good else "  FAIL ") + name + (f": {detail}" if detail else ""))
    return bool(good)


def build(sources, name):
    out = WORK / name
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(ROOT / "tools/proof/audio_ap6c_probe.swift", entry)
    binary = out / "audio-ap6c-probe"
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    try:
        swift_build.build(sources=swift + [entry], output=binary, optimize=True)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join(error.diagnostics[:8])
    models = binary.parent / "Models"
    shutil.rmtree(models, ignore_errors=True)
    shutil.copytree(ROOT / "app/Resources/Models", models)
    return binary, ""


def run(sources, name, quiet=False):
    """{row: bool}, the probe's stderr tail."""
    binary, problem = build(sources, name)
    if binary is None:
        return None, problem
    scratch = WORK / name / "scratch"
    shutil.rmtree(scratch, ignore_errors=True)
    scratch.mkdir(parents=True)
    try:
        result = subprocess.run([str(binary), str(scratch)], capture_output=True, text=True,
                                timeout=300)
    except subprocess.TimeoutExpired:
        return {}, "the probe timed out"
    rows = {}
    for line in result.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2 and parts[0] in ("ok", "FAIL"):
            rows[parts[1]] = rows.get(parts[1], True) and parts[0] == "ok"
    if result.returncode != 0:
        for row in ROWS:
            rows.setdefault(row, False)
    lines = []
    for name, good, detail in one_setup(sources):
        rows["P6"] = rows.get("P6", True) and bool(good)
        lines.append(("  ok   " if good else "  FAIL ") + "P6 " + name
                     + (f": {detail}" if detail else ""))
    if not quiet:
        sys.stdout.write(result.stdout + "".join(line + "\n" for line in lines))
    return rows, result.stderr[-600:]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, default=ROOT / "app/Sources")
    parser.add_argument("--mutants", action="store_true")
    args = parser.parse_args()
    if args.mutants:
        return mutants(args.sources)
    rows, problem = run(args.sources, "probe")
    if rows is None:
        check("source probe builds", False, problem)
        return 1
    good = all(rows.get(row) for row in ROWS)
    good &= check("every row ran", all(row in rows for row in ROWS),
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
        rows, problem = run(tree, f"mutant-{slug}", quiet=True)
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
