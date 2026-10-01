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
  L10     (#148) a question pending in window A holds A's next call but not
          window B's: B's call answers while A's two wait, and Deny then
          answers A's first as declined and runs A's second
  L11     (#150; AI-8, AI-13) the credential: the store first, then
          `ANTHROPIC_API_KEY` trimmed, blank is none, and with
          `RC_ASSISTANT_BASE_URL` set `store()` is an empty MemoryStore whose
          credential is the environment's — literal dummy values only
  L12     (#108) `AppSupport.ensureDirectory` makes each missing level 0700,
          leaves an existing folder's mode, refuses a file in the path by
          name; `FileStore.write` and `AssistantSpend.record` go through it —
          all under this run's work folder
  L13     (issue batch B15, #149; AI-16) a `submit` whose token was cancelled
          before it took the lock answers "Cancelled by the user." and places
          no marker; the same call with a live token places it
  C1      the control: `execute` on main mid-drag loses the marker, so the
          instrument can see #144
  M1      made to fail on purpose: L0 against a scratch copy of `main.swift`
          with the `prepareAtLaunch()` line deleted, and the probe's L1 under
          `--no-prepare`, must BOTH fail
  S1      (#108) each support-folder creator (`SUPPORT_CREATORS`) spells no
          `createDirectory(` and calls `AppSupport.ensureDirectory(` once
  M2      made to fail on purpose: S1's checker over the tree with
          `AssistantSpend.swift`'s call put back to `createDirectory(` must FAIL

    python3 tools/proof/assistant_lane_proof.py              # every row; exit 0 when all pass
    python3 tools/proof/assistant_lane_proof.py --no-prepare # the mutant alone: L0 and L1
                                                             # are expected to FAIL (exit 1)
    python3 tools/proof/assistant_lane_proof.py --mutant NAME
        # one of `MUTANTS` (one-queue → L10, no-env-fallback → L11,
        # mode-0755 → L12, no-lane-check → L13, close-ask-first → L4, B44's
        # close_project as an ask-first row): the probe built over a copy of app/Sources with
        # one text replaced, its one row run and expected to FAIL (exit 1;
        # 0 when it survives). Exit 2 when the control could not be
        # performed: a copy that cannot be made or built, or a probe that
        # printed no such row (a crash, a timeout) — never read as caught.
        # Not with --no-prepare.

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

PROBE_ROWS = ["L1", "L2", "L3", "L4", "L5", "L6", "L7", "L8", "L9", "L10", "L11", "L12", "L13",
              "C1"]

# The four files that make a folder under the support folder (#108).
SUPPORT_CREATORS = ("SecretStore.swift", "ExportPresetsStore.swift", "FFmpegRewrap.swift",
                    "AssistantSpend.swift")
ENSURE = "AppSupport.ensureDirectory("

# name: (file in app/Sources, before — exactly once, after, row)
MUTANTS = {
    "one-queue": ("AgentLane.swift", "ObjectIdentifier(document)",
                  "ObjectIdentifier(AgentLane.self)", "L10"),
    "no-env-fallback": ("AssistantConfiguration.swift", "environment[environmentKey]",
                        'environment["RC_PROBE_UNSET"]', "L11"),
    "mode-0755": ("AppSupport.swift", "0o700", "0o755", "L12"),
    "no-lane-check": ("AgentLane.swift",
                      "if cancel?.isCancelled == true { return AssistantSession.cancelledResult }",
                      "", "L13"),
    "close-ask-first": ("AssistantToolTable.swift", 'tool: "close_project", rule: .withheld',
                        'tool: "close_project", rule: .askFirst', "L4"),
}


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
# S1: the support folder's creators, read from the source.


def support_sites(texts):
    """(ok, detail): each of `SUPPORT_CREATORS` in `texts` (name → text)
    spells no `createDirectory(` and calls `AppSupport.ensureDirectory(`
    exactly once."""
    wrong = []
    for name in SUPPORT_CREATORS:
        text = texts.get(name)
        if text is None:
            wrong.append(f"{name} missing")
            continue
        creates, ensures = text.count("createDirectory("), text.count(ENSURE)
        if creates or ensures != 1:
            wrong.append(f"{name}: createDirectory( {creates}, {ENSURE} {ensures}")
    if wrong:
        return False, "; ".join(wrong)
    return True, (f"{', '.join(SUPPORT_CREATORS)}: no createDirectory(, one {ENSURE} each")


def tree_texts():
    return {name: open(os.path.join(SOURCES, name)).read() for name in SUPPORT_CREATORS
            if os.path.exists(os.path.join(SOURCES, name))}


def mutant_sources(name):
    """(WORK/mutants/<name>/Sources, None): app/Sources/*.swift copied with
    the mutant's `before` replaced exactly once; or (None, reason)."""
    file, before, after, _ = MUTANTS[name]
    target = os.path.join(WORK, "mutants", name, "Sources")
    shutil.rmtree(target, ignore_errors=True)
    try:
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
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    return target, None


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources=None, probe_dir=None):
    """(binary, None) or (None, reason). Rebuilt only when stale. `None`
    for either argument means the module's `SOURCES` / `PROBE_DIR`, read at
    call time, so an importer that sets them is heard."""
    sources = SOURCES if sources is None else sources
    probe_dir = PROBE_DIR if probe_dir is None else probe_dir
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "assistant_lane_probe")
    entry = os.path.join(probe_dir, "main.swift")
    source = open(PROBE_SWIFT).read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    for name in ("Fonts", "Models"):
        src = os.path.join(ROOT, "app", "Resources", name)
        dst = os.path.join(probe_dir, name)
        if not os.path.isdir(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `cd core && cargo build --release` first"
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    stamp = os.path.join(probe_dir, "sources.txt")
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


def run_probe(binary, extra, runs=None):
    runs = runs or os.path.join(WORK, "runs",
                                "no-prepare" if "--no-prepare" in extra else "prepare")
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
    parser.add_argument("--mutant", choices=sorted(MUTANTS),
                        help="the probe over a copy of app/Sources with one text replaced; "
                             "its row is expected to FAIL (exit 1)")
    args = parser.parse_args()
    if args.mutant and args.no_prepare:
        parser.error("--mutant cannot be combined with --no-prepare")

    results = []  # (id, ok, detail)

    def score(row_id, ok, detail, *, instrument=False):
        results.append((row_id, ok, detail, instrument))
        print(f"{'PASS' if ok else 'FAIL'} {row_id}: {detail}", flush=True)

    if args.mutant:
        sys.exit(run_mutant(args.mutant, score))

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

    ok, detail = support_sites(tree_texts())
    score("S1", ok, detail)
    texts = tree_texts()
    spend = texts.get("AssistantSpend.swift", "")
    texts["AssistantSpend.swift"] = spend.replace(ENSURE, "FileManager.default.createDirectory(")
    m2_ok, m2_detail = support_sites(texts)
    score("M2", not m2_ok,
          f"with AssistantSpend.swift's {ENSURE} put back to createDirectory(, S1's checker "
          f"fails {not m2_ok} ({m2_detail})")

    passed = sum(1 for _, ok, _, _ in results if ok)
    print(f"scores: {passed}/{len(results)} pass", flush=True)
    sys.exit(0 if passed == len(results) else 1)


def run_mutant(name, score):
    """The mutant's one row, scored; 1 when it FAILS (the expected outcome),
    0 when it survives, 2 when the control could not be performed — the copy
    could not be made or built, or the probe printed no such row (rule R,
    issue batch B13)."""
    _, _, _, row_id = MUTANTS[name]
    prefix = f"(mutant {name}) "
    sources, why = mutant_sources(name)
    if sources is None:
        print(f"mutant {name}: the control could not be performed — {why}", flush=True)
        return 2
    binary, why = build_probe(sources, os.path.join(WORK, "mutants", name, "probe"))
    if binary is None:
        print(f"mutant {name}: the control could not be performed — the probe did not "
              f"build: {why}", flush=True)
        return 2
    answer, why = run_probe(binary, ["--rows", row_id],
                            runs=os.path.join(WORK, "mutants", name, "runs"))
    r = {r["id"]: r for r in (answer or {}).get("rows", [])}.get(row_id)
    if r is None:
        why = f"no row: {why or 'the probe did not answer it'}"
        score(row_id, False, prefix + why, instrument=True)
        print(f"mutant {name}: the control could not be performed — {row_id} {why}",
              flush=True)
        return 2
    score(row_id, bool(r["ok"]), prefix + r["detail"])
    failed = not r["ok"]
    print(f"mutant {name}: {row_id} {'FAILS (expected)' if failed else 'PASSES (survived)'}",
          flush=True)
    return 1 if failed else 0


if __name__ == "__main__":
    main()
