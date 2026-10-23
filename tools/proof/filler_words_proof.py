#!/usr/bin/env python3
"""Cut by transcript CT-1 (spec §11 TR-1, TR-2, TR-8): fillers on the cloud
request, the marker that records them, and the one filler list captions drop —
measured through the app's own sources, with no app, no network and no key.

    python3 tools/proof/filler_words_proof.py [--mutant NAME] [--only IDS]

`filler_words_probe.swift` is copied in as `main.swift` and built with
`swift_build.build()` over `swift_build.app_sources()` of `app/Sources` (or,
under `--mutant`, of a mutated copy of it in the work folder), run once under
`tools/proof/work/filler-words/<tree|mutant-NAME>/`, killed at a 240 s wall.
Prints `<ID> pass|fail — <detail>` per row, then `scores: N/M`.

Rows:
  B0  the probe builds (a build failure is this row's scored FAIL).
  W1  the default request's wire body is exactly `audio_url`, `disfluencies`,
      `speaker_labels`, `speech_models`, with `disfluencies` true, and the
      memberwise `TranscriptOptions` init without the argument gives true.
  D1  an old `requested` block and an old cache file (no `disfluencies`)
      decode false and `File(data:)` reads; a new one round-trips true.
  D2  old legacy and narrow marker bytes decode false; a new marker encodes
      the seven sorted outer keys.
  S1  `serves`: a false marker serves `.captions` and not `.fillers`, a true
      one both; any other field or source change serves neither.
  S2  `MediaTranscript.isCurrent` is true over a temp cache holding a written
      file and a raw marker with no key.
  E1  `CloudEstimate.fate` with that marker is `.cached`, and
      `.upload(.refresh)` under refresh.
  V1  `Um,` `UH.` `Hmm?` `uh-huh` `M` `mhm` `Er,` `erm` are fillers;
      `umbrella` `uhm` `hum` `Ahh` `them` `I'm` `err` `here` are not.
  C1  `captionWords` of a file with fillers equals `words(for:in:)` of the
      same file without them, and the cache bytes keep the fillers (R6-3).
  C2  `CaptionPages.cues` over those two lists is equal for Subtitles and for
      every word style.

Mutants (`--mutant`), each anchor asserted to occur exactly once:
  fillers-kept                    captionWords' filter removed (C1, C2)
  captions-need-disfluent         serves needs `disfluencies` for captions too
                                  (S1, S2, E1)
  fillers-take-any-marker         serves answers true for fillers whatever the
                                  marker (S1)
  request-omits-disfluencies      the wire body's `disfluencies` line removed (W1)
  legacy-marker-key-required      the stamp decoder's `decodeIfPresent` is
                                  `decode` (D2, S2)
  legacy-requested-key-required   the options decoder's (D1)
  case-sensitive-fillers          `normalized` does not lowercase (V1)
  estimate-strict-marker          `CloudEstimate.fate`'s current back to `==` (E1)

Exit: a plain run exits 0 iff every row passed, else 1. A `--mutant` run
exits 0 when every row the mutant names failed (caught), 1 when one passed
(survived), and 2 when the control could not be performed: an anchor not
found exactly once, the copy did not build, or a named row was not scored.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys

import swift_build

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/filler-words"
PROBE = ROOT / "tools/proof/filler_words_probe.swift"
ROWS = ["B0", "W1", "D1", "D2", "S1", "S2", "E1", "V1", "C1", "C2"]
WALL = 240

SERVES = "use == .captions || disfluencies"
# name: (the rows it must fail, [(file, before, after), ...])
MUTANTS = {
    "fillers-kept": (["C1", "C2"], [
        ("FillerWords.swift", ".filter { !FillerWords.isFiller($0.text) }", "")]),
    "captions-need-disfluent": (["S1", "S2", "E1"], [
        ("TranscriptStamp.swift", SERVES, "disfluencies")]),
    "fillers-take-any-marker": (["S1"], [
        ("TranscriptStamp.swift", SERVES, "true")]),
    "request-omits-disfluencies": (["W1"], [
        ("AssemblyAITranscript.swift",
         "try container.encode(options.disfluencies, forKey: .disfluencies)", "")]),
    "legacy-marker-key-required": (["D2", "S2"], [
        ("TranscriptStamp.swift",
         "container.decodeIfPresent(Bool.self, forKey: .disfluencies) ?? false",
         "container.decode(Bool.self, forKey: .disfluencies)")]),
    "legacy-requested-key-required": (["D1"], [
        ("TranscriptStamp.swift",
         "keys.decodeIfPresent(Bool.self, forKey: .disfluencies) ?? false",
         "keys.decode(Bool.self, forKey: .disfluencies)")]),
    "case-sensitive-fillers": (["V1"], [
        ("FillerWords.swift", "text.lowercased().trimmingCharacters(", "text.trimmingCharacters(")]),
    "estimate-strict-marker": (["E1"], [
        ("CloudEstimate.swift", "facts.marker?.serves(wanted, for: .captions) == true",
         "facts.marker == wanted")]),
}


def build(sources, here):
    """(binary, None) or (None, why)."""
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "filler-words-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    return binary, None


def mutate(name, dest):
    """A copy of `app/Sources` with the mutant's edits; why, when an anchor is
    not found exactly once."""
    shutil.copytree(ROOT / "app/Sources", dest)
    for file, before, after in MUTANTS[name][1]:
        path = dest / file
        text = path.read_text() if path.exists() else ""
        if text.count(before) != 1:
            return f"{file}: `{before}` found {text.count(before)} times"
        path.write_text(text.replace(before, after))
    return None


def probe(binary, here):
    """The rows the probe answered, or None and why."""
    try:
        result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=WALL,
                                cwd=here)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {WALL} s"
    (here / "stderr.txt").write_text(result.stderr)
    try:
        return json.loads(result.stdout)["rows"], None
    except (ValueError, KeyError):
        return None, f"no answer (exit {result.returncode}): {result.stderr[-300:]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--only", help="comma-separated row ids")
    args = parser.parse_args()
    named = MUTANTS[args.mutant][0] if args.mutant else []
    wanted = args.only.split(",") if args.only else ROWS
    unknown = [row for row in wanted if row not in ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    if "B0" not in wanted:
        wanted = ["B0"] + wanted
    here = WORK / (f"mutant-{args.mutant}" if args.mutant else "tree")
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    sources = ROOT / "app/Sources"
    if args.mutant:
        why = mutate(args.mutant, here / "Sources")
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        sources = here / "Sources"

    results = {}
    binary, why = build(sources, here)
    results["B0"] = (binary is not None, why or f"built from {sources}")
    if binary is None and args.mutant:
        print(f"B0 fail — {why}")
        print(f"mutant {args.mutant}: the control could not be performed — the copy did not build")
        return 2
    not_scored = []
    rest = [row for row in wanted if row != "B0"]
    answers, why = (probe(binary, here) if binary is not None
                    else (None, "not run: the probe did not build"))
    for row in rest:
        answer = next((a for a in answers or [] if a.get("id") == row), None)
        if answer is None:
            not_scored.append(row)
            results[row] = (False, f"no row: {why or 'the probe did not answer it'}")
        else:
            results[row] = (answer.get("pass") is True, answer.get("detail", ""))

    for row in wanted:
        good, detail = results[row]
        print(f"{row} {'pass' if good else 'fail'} — {detail}")
    passed = sum(1 for row in wanted if results[row][0])
    print(f"scores: {passed}/{len(wanted)}")
    if not args.mutant:
        return 0 if passed == len(wanted) else 1
    lost = [row for row in named if row in not_scored or row not in results]
    if lost:
        print(f"mutant {args.mutant}: the control could not be performed — "
              f"row(s) not scored: {', '.join(lost)}")
        return 2
    survived = [row for row in named if results[row][0]]
    if survived:
        print(f"mutant {args.mutant}: SURVIVED — {', '.join(survived)} passed")
        return 1
    print(f"mutant {args.mutant}: caught — {', '.join(named)} failed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
