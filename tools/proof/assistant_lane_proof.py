#!/usr/bin/env python3
"""The agent lane — road map 12 A1, part 1 (spec §11 AI-2, AI-3, AI-5, AI-7,
AI-12; #144). A line of `make test`: AI-3's "`make test`-reachable
probe".

  L0      the launch path: `app/Sources/main.swift` calls
          `AgentLane.prepareAtLaunch()` at top level (between no `#if` and
          its `#endif`), before the `NSApplicationMain` line
  L1–L9   the probe's rows (`assistant_lane_probe.swift`, compiled over
          `app/Sources` minus `main.swift` on `harness/build.sh`'s swiftc line
          with `-D REELCUT_DEV_TOOLS`, rebuilt only when stale); L6 also
          requires every `AssistantPrompt.coreTools` name in the assistant's
          catalog (A1 part 3)
  C1      the control: `execute` on main mid-drag loses the marker, so the
          instrument can see #144
  M1      made to fail on purpose: L0 against a scratch copy of `main.swift`
          with the `prepareAtLaunch()` line deleted, and the probe's L1 under
          `--no-prepare`, must BOTH fail

    python3 tools/proof/assistant_lane_proof.py              # every row; exit 0 when all pass
    python3 tools/proof/assistant_lane_proof.py --no-prepare # the mutant alone: L0 and L1
                                                             # are expected to FAIL (exit 1)

A probe that does not build is a scored FAIL (exit 1), never a skip. No app
instance is launched, no media is used, and no key is read: every child gets
the environment without `RC_ASSEMBLYAI_KEY` and `ANTHROPIC_API_KEY`.
"""

import argparse
import json
import os
import re
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

WORK = os.path.join(HERE, "work", "assistant_lane")
PROBE_DIR = os.path.join(WORK, "probe")
SCRATCH = os.path.join(WORK, "scratch")
SOURCES = os.path.join(ROOT, "app", "Sources")
MAIN = os.path.join(SOURCES, "main.swift")
PROBE_SWIFT = os.path.join(HERE, "assistant_lane_probe.swift")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
PREPARE = "AgentLane.prepareAtLaunch()"
WALL_BUILD, WALL_RUN = 900, 300

PROBE_ROWS = ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "C1"]


def child_env():
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    return env


def run(argv, seconds, cwd=None):
    return bounded.run(argv, seconds, cwd=cwd, env=child_env())


# ---------------------------------------------------------------------------
# L0: the launch path, read from the source.


def launch_path(text):
    """(ok, detail): a line that is exactly `AgentLane.prepareAtLaunch()` at
    `#if` depth 0, above the first `NSApplicationMain` line."""
    depth = 0
    prepare_line = None
    inside_if = []
    main_line = None
    for number, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if re.match(r"#if\b", line):
            depth += 1
        elif re.match(r"#endif\b", line):
            depth = max(0, depth - 1)
        elif line == PREPARE:
            if depth == 0 and prepare_line is None:
                prepare_line = number
            elif depth > 0:
                inside_if.append(number)
        if main_line is None and "NSApplicationMain" in line and not line.startswith("//"):
            main_line = number
    if main_line is None:
        return False, "no NSApplicationMain line"
    if prepare_line is None:
        where = f" (only inside an #if, line {inside_if})" if inside_if else ""
        return False, f"no top-level {PREPARE} line{where}"
    if prepare_line > main_line:
        return False, f"{PREPARE} at line {prepare_line} is after NSApplicationMain ({main_line})"
    return True, f"{PREPARE} at line {prepare_line}, top level, before NSApplicationMain " \
                 f"at line {main_line}"


def mutant_main():
    """A scratch copy of main.swift with the prepare line deleted."""
    os.makedirs(SCRATCH, exist_ok=True)
    text = open(MAIN).read()
    kept = [l for l in text.splitlines(keepends=True) if l.strip() != PREPARE]
    scratch = os.path.join(SCRATCH, "main.swift")
    with open(scratch, "w") as f:
        f.write("".join(kept))
    return scratch


# ---------------------------------------------------------------------------
# The probe.


def build_probe():
    """(binary, None) or (None, reason). Rebuilt only when stale."""
    os.makedirs(PROBE_DIR, exist_ok=True)
    binary = os.path.join(PROBE_DIR, "assistant_lane_probe")
    entry = os.path.join(PROBE_DIR, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    for name in ("Fonts", "Models"):
        src = os.path.join(ROOT, "app", "Resources", name)
        dst = os.path.join(PROBE_DIR, name)
        if not os.path.isdir(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release` first"
    swift = sorted(os.path.join(SOURCES, n) for n in os.listdir(SOURCES)
                   if n.endswith(".swift") and n != "main.swift")
    stamp = os.path.join(PROBE_DIR, "sources.txt")
    listing = "\n".join(swift)
    same_set = os.path.exists(stamp) and open(stamp).read() == listing
    if same_set and os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary)
            # The two headers too: a change to only the C contract or the
            # bridging header must rebuild, not reuse a probe built against the old one.
            for f in swift + [entry, LIB, os.path.abspath(__file__),
                              os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
                              os.path.join(ROOT, "core", "include", "reelcut_core.h")]):
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    if os.path.exists(binary):
        os.remove(binary)
    print(f"probe: building over {len(swift)} sources (up to {WALL_BUILD} s)…", flush=True)
    started = time.time()
    built = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                 "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                 "-import-objc-header",
                 os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
                 "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary],
                WALL_BUILD)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [l for l in built["stderr"].splitlines() if ": error:" in l]
        tail = [l for l in built["stderr"].strip().splitlines()[-4:] if l.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w") as f:
        f.write(listing)
    print(f"probe: built in {time.time() - started:.0f} s", flush=True)
    return binary, None


def run_probe(binary, extra):
    runs = os.path.join(WORK, "runs", "no-prepare" if "--no-prepare" in extra else "prepare")
    shutil.rmtree(runs, ignore_errors=True)
    os.makedirs(runs, exist_ok=True)
    ran = run([binary, runs] + extra, WALL_RUN, cwd=os.path.dirname(binary))
    if ran["expired"]:
        return None, f"the probe ran past {WALL_RUN} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--no-prepare", action="store_true",
                        help="the made-to-fail run: L0 on a scratch main.swift without the "
                             "prepare line, and the probe without prepareAtLaunch()")
    args = parser.parse_args()

    results = []  # (id, ok, detail)

    def score(row_id, ok, detail):
        results.append((row_id, ok, detail))
        print(f"{'PASS' if ok else 'FAIL'} {row_id}: {detail}", flush=True)

    if args.no_prepare:
        ok, detail = launch_path(open(mutant_main()).read())
        score("L0", ok, "(scratch main.swift, prepare line deleted) " + detail)
    else:
        ok, detail = launch_path(open(MAIN).read())
        score("L0", ok, detail)

    binary, why = build_probe()
    if binary is None:
        for row_id in (["L1"] if args.no_prepare else PROBE_ROWS):
            score(row_id, False, f"the probe did not build: {why}")
        if not args.no_prepare:
            score("M1", False, f"the probe did not build: {why}")
    else:
        extra = ["--no-prepare", "--rows", "L1"] if args.no_prepare else []
        answer, why = run_probe(binary, extra)
        got = {r["id"]: r for r in (answer or {}).get("rows", [])}
        for row_id in (["L1"] if args.no_prepare else PROBE_ROWS):
            r = got.get(row_id)
            if r is None:
                score(row_id, False, f"no row: {why or 'the probe did not answer it'}")
            else:
                score(row_id, bool(r["ok"]), r["detail"])
        if answer is not None:
            os.makedirs(WORK, exist_ok=True)
            name = "answer-no-prepare.json" if args.no_prepare else "answer.json"
            with open(os.path.join(WORK, name), "w") as f:
                json.dump(answer, f, indent=1, sort_keys=True)
        if not args.no_prepare:
            # M1: the same instrument, made to fail on purpose.
            l0_ok, l0_detail = launch_path(open(mutant_main()).read())
            mutant, why = run_probe(binary, ["--no-prepare", "--rows", "L1"])
            l1 = {r["id"]: r for r in (mutant or {}).get("rows", [])}.get("L1")
            l1_failed = l1 is not None and not l1["ok"]
            score("M1", (not l0_ok) and l1_failed,
                  f"without the prepare line L0 fails {not l0_ok} ({l0_detail}); without "
                  f"prepareAtLaunch() L1 fails {l1_failed} "
                  f"({l1['detail'] if l1 else why})")

    passed = sum(1 for _, ok, _ in results if ok)
    print(f"scores: {passed}/{len(results)} pass", flush=True)
    sys.exit(0 if passed == len(results) else 1)


if __name__ == "__main__":
    main()
