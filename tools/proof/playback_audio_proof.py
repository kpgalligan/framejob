#!/usr/bin/env python3
"""Issue batch B11: a reversed clip inside a nest is analysed mirrored (#64),
and a metered composition track adds to the meter only while one of its OWN
sounding spans holds the playhead (#65).

Neither is reachable over MCP — a peaks window and a meter reading are not
ops — so this is `CLAUDE.md`'s instrument for app ARITHMETIC: a probe
(`playback_audio_probe.swift`) compiled as `main.swift` against every other
file in `app/Sources` on `harness/build.sh`'s swiftc line, with `Blank.mp4`
beside the binary, rebuilt only when stale. The probe's header lists the
fixtures and the nine rows:

  N1  the nested reversed clip's pivot, from the PARENT plan, is the media's
      duration
  N2  level-mode silence detection with the nest closed equals the same with
      it open; non-empty; inside [0, 3 s]
  N3  (CONTROL) the forward twin: pivot nil; closed equals open; [3 s, 6 s]
  N4  (CONTROL) the two twins' plan JSON is byte-identical
  M1  F1 at 4 s: the WAV family alone
  M2  F2 at 4 s: the long track alone
  M3  (CONTROL) F2 at 1 s: both tracks count
  M4  F1 at 7 s (the missing clip): silent
  M5  F1: two meters, family 0 sounding [0, 2 s), the other [3 s, 5 s)

    python3 tools/proof/playback_audio_proof.py
    python3 tools/proof/playback_audio_proof.py --mutant nest-lookup|always-sounding|plan-track-spans

Rows print `<ID> ok|FAIL — <detail>`, then `n/m`; exit 0 iff every row
passes. `--mutant` builds the probe over a copy of `app/Sources` with one text
replaced (asserted to occur exactly once) and runs every row: it exits 1 when
exactly the rows it targets FAIL (expected), 0 when a targeted row survives or
another row fails with it, 2 when the copy or the build could not be made.
A probe that does not build is a scored FAIL, never a skip. Every child runs
under `graphics_spike/bounded.py`; no app instance is launched and no key is
read.
"""

import argparse
import json
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

WORK = os.path.join(HERE, "work", "playback_audio")
PROBE_DIR = os.path.join(WORK, "probe")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "playback_audio_probe.swift")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
WALL_BUILD, WALL_RUN = 900, 300
ROWS = ["N1", "N2", "N3", "N4", "M1", "M2", "M3", "M4", "M5"]

PLAN_TRACK_SPANS = ("planTrack.segments.filter { $0.duration > 0 }"
                    ".map { $0.start..<($0.start + $0.duration) }")

# name: (file in app/Sources, before — exactly once, after, the rows it must fail)
MUTANTS = {
    "nest-lookup": (
        "MediaPeaks.swift",
        "\n            ?? snapshot.nests.lazy.compactMap { $0.clips.first { $0.id == segment.clip } }"
        ".first",
        "", ["N1", "N2"]),
    "always-sounding": (
        "LevelMeter.swift", "sounding.contains { $0.contains(t) }", "true",
        ["M1", "M2", "M4"]),
    "plan-track-spans": (
        "CompositionBuilder+AudioTracks.swift", "sounding: family.sounding",
        "sounding: " + PLAN_TRACK_SPANS, ["M1", "M4", "M5"]),
}


def mutant_sources(name):
    """(WORK/mutants/<name>/Sources, None): app/Sources/*.swift copied with
    the mutant's `before` replaced exactly once; or (None, reason)."""
    file, before, after, _ = MUTANTS[name]
    target = os.path.join(WORK, "mutants", name, "Sources")
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target)
    for entry in sorted(os.listdir(SOURCES)):
        if entry.endswith(".swift"):
            shutil.copy2(os.path.join(SOURCES, entry), os.path.join(target, entry))
    path = os.path.join(target, file)
    text = open(path).read() if os.path.exists(path) else ""
    count = text.count(before)
    if count != 1:
        return None, f"{file} holds {before!r} {count} times, not once"
    with open(path, "w") as f:
        f.write(text.replace(before, after))
    return target, None


def build_probe(sources=SOURCES, probe_dir=PROBE_DIR):
    """(binary, None) or (None, reason). Rebuilt only when stale."""
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "playback_audio_probe")
    entry = os.path.join(probe_dir, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    blank = os.path.join(probe_dir, "Blank.mp4")
    if not os.path.exists(blank):
        shutil.copy2(os.path.join(ROOT, "app", "Resources", "Blank.mp4"), blank)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release` first"
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    stamp = os.path.join(probe_dir, "sources.txt")
    listing = "\n".join(swift)
    same_set = os.path.exists(stamp) and open(stamp).read() == listing
    if same_set and os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary)
            for f in swift + [entry, LIB,
                              os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
                              os.path.join(ROOT, "core", "include", "reelcut_core.h")]):
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None
    sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    if os.path.exists(binary):
        os.remove(binary)
    print(f"probe: building over {len(swift)} sources (up to {WALL_BUILD} s)…", flush=True)
    started = time.time()
    built = bounded.run(
        ["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk, "-target", "arm64-apple-macos26.0",
         "-module-name", "Reelcut", "-import-objc-header",
         os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary],
        WALL_BUILD)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = [line for line in built["stderr"].strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w") as f:
        f.write(listing)
    print(f"probe: built in {time.time() - started:.0f} s", flush=True)
    return binary, None


def run_probe(binary, runs):
    """The probe's rows by id, or (None, why)."""
    shutil.rmtree(runs, ignore_errors=True)
    os.makedirs(runs, exist_ok=True)
    ran = bounded.run([binary, runs], WALL_RUN, cwd=os.path.dirname(binary))
    if ran["expired"]:
        return None, f"the probe ran past {WALL_RUN} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            answer = json.loads(line[len("ANSWER "):])
            return {r["id"]: r for r in answer.get("rows", [])}, None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


def score_rows(got, why, prefix=""):
    """Print every row; the set of failing ids."""
    failing = set()
    for row_id in ROWS:
        r = (got or {}).get(row_id)
        ok = bool(r and r["ok"])
        detail = r["detail"] if r else f"no row: {why or 'the probe did not answer it'}"
        print(f"{row_id} {'ok' if ok else 'FAIL'} — {prefix}{detail}", flush=True)
        if not ok:
            failing.add(row_id)
    print(f"{len(ROWS) - len(failing)}/{len(ROWS)}", flush=True)
    return failing


def run_mutant(name):
    _, _, _, targets = MUTANTS[name]
    sources, why = mutant_sources(name)
    if sources is None:
        print(f"mutant {name}: {why}", flush=True)
        return 2
    binary, why = build_probe(sources, os.path.join(WORK, "mutants", name, "probe"))
    if binary is None:
        print(f"mutant {name}: the probe did not build: {why}", flush=True)
        return 2
    got, why = run_probe(binary, os.path.join(WORK, "mutants", name, "runs"))
    failing = score_rows(got, why, f"(mutant {name}) ")
    expected = set(targets)
    exact = failing == expected
    print(f"mutant {name}: failing {sorted(failing)}, targeted {sorted(expected)} — "
          + ("FAILS as listed (expected)" if exact else
             "a targeted row SURVIVES" if not expected <= failing else
             f"also failing {sorted(failing - expected)}"), flush=True)
    return 1 if exact else 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="the probe over a copy of app/Sources with one text replaced; "
                             "its rows are expected to FAIL (exit 1)")
    args = parser.parse_args()
    if args.mutant:
        sys.exit(run_mutant(args.mutant))
    binary, why = build_probe()
    got = None
    if binary is None:
        why = f"the probe did not build: {why}"
    else:
        got, why = run_probe(binary, os.path.join(WORK, "runs"))
    failing = score_rows(got, why)
    sys.exit(0 if not failing else 1)


if __name__ == "__main__":
    main()
