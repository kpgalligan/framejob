#!/usr/bin/env python3
"""Issue batch B79 — an agent's `open_project` reads off the main thread and
answers when the read ends, with no window and no question (spec §11 #231).

    python3 tools/proof/agent_open_proof.py [--megabytes N] [--mutant NAME]

Builds `agent_open_probe.swift` over app/Sources (minus `main.swift`) on
harness/build.sh's swiftc line, rebuilt only when stale, under
`tools/proof/work/agent-open-build/`, and runs it once over a WebM big enough
that its built-in copy (spec §11 #216-R) takes many main-thread ticks. No app
instance is launched and nothing is activated: the probe is a `.prohibited`
process that calls `AgentLane.shared.serve` from a background thread, as the
MCP server thread does, while main spins its run loop.

**Fixture**, made at proof time and never committed: a 10 s 1920x1080
VP9+Opus seed (`-deadline realtime -cpu-used 8 -b:v 40M`), stream-copied
with `-stream_loop … -c copy` until `big.webm` is at least `--megabytes`.

**Scratch home.** `tools/proof/work/agent-open/` is removed at start and at
exit. It holds the fixture, the run's packages and `home/`, and every probe
(the baseline and each mutant) runs with `CFFIXED_USER_HOME=<work>/home`,
which moves `AppSupport.directory` there for an unsandboxed process: nothing
this proof copies lands in the owner's
`~/Library/Application Support/Reelcut/Rewrapped/`, and a run killed by its
alarm leaves only the work folder, which the next run removes. A run writes
about 4 x `--megabytes` there (the fixture and three copies, at most the
fixture and one copy on disk at once). Not a line of `make test`.

Rows (a 10 ms main run-loop timer counts, during each call, its ticks, the
ticks that saw a `.partial.mov` in `Rewrapped/`, and the ticks with
`RewrapProgressWindowController.live` non-empty):

- **A0** the probe built (a failed build is a scored FAILURE), the fixture's
  size, and the probe's `AppSupport.subdirectory("Rewrapped")`, read before
  any call: it must lie inside `<work>/home`, else A0 fails and A1–A7 do not
  run.
- **A1** `open_project {big.webm}` answers a project with one media, its path
  directly in the scratch home's `Reelcut/Rewrapped/` and on disk; the
  call's seconds are printed. **A2** at least 10 ticks saw the partial: main
  ran while the copy was written. **A3** `live` was empty at every tick.
- **A4** the project saved, closed, its `project.json` media path rewritten
  to `/nonexistent-b79/<name>` with `bookmark` null and the copy removed
  (`container_import_proof.py` M9's method): `open_project {package}` answers
  a path directly in the scratch home's `Reelcut/Rewrapped/`, on disk, with
  `original.path` the WebM. **A5** at least 10 ticks saw the partial. **A6**
  `live` was empty at every tick.
- **A7** the package closed and its copy removed again; on the first tick
  that sees the partial, main adds a stub `ProjectDocument` whose `fileURL`
  is the package: the call answers `already_open` and one open document is
  at that path.

`--mutant NAME` builds the probe over a copy of app/Sources with one text
replaced and must fail exactly `EXPECTED[NAME]` (then MUTANT PASS, exit 0):
`open-on-main` (`"open_project"` out of the off-main set), `quiet-watch`
(`probeBlocking` passes its watch inside `withoutAsking`),
`recopy-agent-watch` (the re-copy's guard back to the main thread alone) and
`no-recheck` (step C adds the document it made without looking again). Exit
2 when the control could not be performed.

`--megabytes` defaults to the first of 256, 512 and 1024 whose baseline run
printed at least 30 partial ticks for both A2 and A5 (the proof README's B79
section names each size tried).
"""

import argparse
import atexit
import json
import math
import os
import shutil
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402

WORK = os.path.join(HERE, "work", "agent-open")
BUILD = os.path.join(HERE, "work", "agent-open-build")
HOME = os.path.join(WORK, "home")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "agent_open_probe.swift")
LIB = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
WALL_BUILD, WALL_RUN, WALL_FFMPEG = 900, 900, 600
ROWS = ["A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7"]
DEFAULT_MEGABYTES = 256

# name: (file in app/Sources, before — exactly once, after)
MUTANTS = {
    "open-on-main": ("AgentServer.swift",
                     '"transcribe", "record_screen", "render_graphic", "open_project",',
                     '"transcribe", "record_screen", "render_graphic",'),
    "quiet-watch": ("MediaImporter+Probe.swift", "watch: quiet ? nil : watch)",
                    "watch: watch)"),
    "recopy-agent-watch": ("ProjectDocument+MissingCopies.swift",
                           "let shown = Thread.isMainThread || MediaImporter.isWithoutAsking"
                           " ? nil : watch",
                           "let shown = Thread.isMainThread ? nil : watch"),
    "no-recheck": ("AgentServer+Project.swift",
                   "if let answer = try self.alreadyOpen(url) {\n                document.close()",
                   "if false, let answer = try self.alreadyOpen(url) {\n"
                   "                document.close()"),
}

# The rows each mutant must fail, and only those (measured on 2026-10-03).
# `open-on-main` also fails A7: with the read on main no tick sees the
# partial, so the stub is never added and the call opens the package.
EXPECTED = {
    "open-on-main": {"A2", "A5", "A7"},
    "quiet-watch": {"A3"},
    "recopy-agent-watch": {"A6"},
    "no-recheck": {"A7"},
}


def child_env(scratch_home):
    env = bounded.child_env()
    env.pop("ANTHROPIC_API_KEY", None)
    if scratch_home:
        env["CFFIXED_USER_HOME"] = HOME
    return env


def run(argv, seconds, cwd=None, scratch_home=False):
    """A bounded child. Only the probe runs with the scratch home: swiftc and
    ffmpeg keep the caller's."""
    return bounded.run(argv, seconds, cwd=cwd, env=child_env(scratch_home))


def remove_work():
    shutil.rmtree(WORK, ignore_errors=True)


def make_fixture(megabytes):
    """(path, None) or (None, reason): `big.webm`, at least `megabytes` MiB."""
    seed, big = os.path.join(WORK, "seed.webm"), os.path.join(WORK, "big.webm")
    made = run(["ffmpeg", "-y", "-v", "error",
                "-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30:duration=10",
                "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=10",
                "-c:v", "libvpx-vp9", "-pix_fmt", "yuv420p", "-deadline", "realtime",
                "-cpu-used", "8", "-b:v", "40M", "-c:a", "libopus", seed], WALL_FFMPEG)
    if made["rc"] or made["expired"] or not os.path.exists(seed):
        return None, "the seed was not made: " + (
            "ffmpeg expired" if made["expired"] else made["stderr"].strip()[-300:])
    wanted = megabytes * 1024 * 1024
    loops = max(0, math.ceil(wanted / os.path.getsize(seed)) - 1)
    looped = run(["ffmpeg", "-y", "-v", "error", "-stream_loop", str(loops), "-i", seed,
                  "-c", "copy", big], WALL_FFMPEG)
    if looped["rc"] or looped["expired"] or not os.path.exists(big):
        return None, "big.webm was not made: " + (
            "ffmpeg expired" if looped["expired"] else looped["stderr"].strip()[-300:])
    os.remove(seed)
    if os.path.getsize(big) < wanted:
        return None, f"big.webm is {os.path.getsize(big)} bytes, under {wanted}"
    return big, None


def mutant_sources(name):
    """(a copy of app/Sources with the mutant's text replaced once, None), or
    (None, reason)."""
    file, before, after = MUTANTS[name]
    target = os.path.join(BUILD, "mutants", name, "Sources")
    shutil.rmtree(target, ignore_errors=True)
    try:
        os.makedirs(target)
        for entry in sorted(os.listdir(SOURCES)):
            if entry.endswith(".swift"):
                shutil.copy2(os.path.join(SOURCES, entry), os.path.join(target, entry))
        path = os.path.join(target, file)
        with open(path, encoding="utf-8") as stream:
            text = stream.read()
        count = text.count(before)
        if count != 1:
            return None, f"{file} holds {before!r} {count} times, not once"
        with open(path, "w", encoding="utf-8") as stream:
            stream.write(text.replace(before, after))
    except OSError as error:
        return None, f"the copy could not be made: {error}"
    return target, None


def build_probe(sources, probe_dir):
    """(binary, None) or (None, reason). Rebuilt only when stale."""
    os.makedirs(probe_dir, exist_ok=True)
    binary = os.path.join(probe_dir, "agent_open_probe")
    entry = os.path.join(probe_dir, "main.swift")
    with open(PROBE_SWIFT, encoding="utf-8") as stream:
        source = stream.read()
    if not os.path.exists(entry) or open(entry, encoding="utf-8").read() != source:
        with open(entry, "w", encoding="utf-8") as stream:
            stream.write(source)
    for name in ("Fonts", "Models"):
        src = os.path.join(ROOT, "app", "Resources", name)
        dst = os.path.join(probe_dir, name)
        if not os.path.isdir(dst) or os.path.getmtime(src) > os.path.getmtime(dst):
            shutil.rmtree(dst, ignore_errors=True)
            shutil.copytree(src, dst)
    if not os.path.exists(LIB):
        return None, f"{LIB} is missing — run `make rust` first"
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    if len(swift) < 100:
        return None, "app source set incomplete"
    stamp = os.path.join(probe_dir, "sources.txt")
    listing = "\n".join(swift)
    same_set = os.path.exists(stamp) and open(stamp, encoding="utf-8").read() == listing
    headers = [os.path.join(ROOT, "app", "Bridging", "Reelcut-Bridging-Header.h"),
               os.path.join(ROOT, "core", "include", "reelcut_core.h")]
    if same_set and os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary)
            for f in swift + [entry, LIB, os.path.abspath(__file__)] + headers):
        print(f"probe: {binary} (up to date)", flush=True)
        return binary, None
    sdk = run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)["stdout"].strip()
    if os.path.exists(binary):
        os.remove(binary)
    print(f"probe: building over {len(swift)} sources (up to {WALL_BUILD} s)…", flush=True)
    started = time.time()
    built = run(["swiftc", "-D", "REELCUT_DEV_TOOLS", "-sdk", sdk,
                 "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
                 "-import-objc-header", headers[0],
                 "-L", os.path.dirname(LIB), "-lreelcut_core"] + swift + [entry, "-o", binary],
                WALL_BUILD)
    if built["rc"] != 0 or not os.path.exists(binary):
        errors = [line for line in built["stderr"].splitlines() if ": error:" in line]
        tail = [line for line in built["stderr"].strip().splitlines()[-4:] if line.strip()]
        return None, (f"swiftc exited {built['rc']} (expired {built['expired']}): "
                      + " | ".join(errors[:6] or tail or ["(no output)"]))
    with open(stamp, "w", encoding="utf-8") as stream:
        stream.write(listing)
    print(f"probe: built in {time.time() - started:.0f} s", flush=True)
    return binary, None


def run_probe(binary, fixture):
    """(answer, None) or (None, reason)."""
    runs = os.path.join(WORK, "run")
    os.makedirs(runs, exist_ok=True)
    ran = run([binary, runs, fixture, HOME], WALL_RUN, cwd=os.path.dirname(binary),
              scratch_home=True)
    if ran["expired"]:
        return None, f"the probe ran past {WALL_RUN} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            return json.loads(line[len("ANSWER "):]), None
    return None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--megabytes", type=int, default=DEFAULT_MEGABYTES,
                        help="the fixture's least size, in MiB")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()

    results = []

    def row(row_id, ok, detail):
        results.append((row_id, bool(ok)))
        print(("  ok   " if ok else "  FAIL ") + f"{row_id} {detail}", flush=True)

    remove_work()
    atexit.register(remove_work)
    sources, probe_dir = SOURCES, os.path.join(BUILD, "probe")
    if args.mutant:
        sources, why = mutant_sources(args.mutant)
        if sources is None:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        probe_dir = os.path.join(BUILD, "mutants", args.mutant, "probe")
    binary, why = build_probe(sources, probe_dir)
    if binary is None:
        if args.mutant:
            print(f"mutant {args.mutant}: the control could not be performed — the probe "
                  f"did not build: {why}")
            return 2
        row("A0", False, f"the probe builds from {sources}: {why}")
        print("passed 0/1")
        return 1

    os.makedirs(os.path.join(HOME, "Library", "Application Support"))
    fixture, why = make_fixture(args.megabytes)
    if fixture is None:
        print(f"instrument failure: {why}")
        return 2
    megabytes = os.path.getsize(fixture) / (1024 * 1024)
    print(f"fixture: big.webm, {megabytes:.1f} MiB (--megabytes {args.megabytes}); scratch home "
          f"{HOME}", flush=True)

    answer, why = run_probe(binary, fixture)
    got = {r["id"]: r for r in (answer or {}).get("rows", [])}
    if answer is None and args.mutant:
        print(f"mutant {args.mutant}: the control could not be performed — {why}")
        return 2
    a0 = got.get("A0")
    if a0 is None:
        row("A0", False, f"the probe built; no A0 row: {why or 'the probe did not answer it'}")
    else:
        row("A0", a0["ok"], "the probe built; " + a0["detail"])
    for row_id in ROWS[1:]:
        r = got.get(row_id)
        if r is None:
            unrun = a0 is None or not a0["ok"]
            row(row_id, False, "not run: " + ((why or "A0 failed") if unrun
                                             else "the probe did not answer it"))
        else:
            row(row_id, r["ok"], r["detail"])
    if answer is not None:
        print("measure: " + json.dumps(answer.get("measure", {}), sort_keys=True), flush=True)

    failed = {row_id for row_id, ok in results if not ok}
    print(f"passed {len(results) - len(failed)}/{len(results)}")
    if not args.mutant:
        return 1 if failed else 0
    expected = EXPECTED[args.mutant]
    verdict = "MUTANT PASS" if failed == expected else "MUTANT FAIL"
    print(f"{verdict}: {args.mutant} failed {sorted(failed)}, expected {sorted(expected)}")
    return 0 if failed == expected else 1


if __name__ == "__main__":
    sys.exit(main())
