#!/usr/bin/env python3
"""Issue batch B79 — an agent's `open_project` reads off the main thread and
answers when the read ends, with no window and no question (spec §11 #231).
Issue batch B81 — while either side's read is in flight, an agent's
`open_project` and a person's open end as one document at the path (#234).

    python3 tools/proof/agent_open_proof.py [--megabytes N] [--mutant NAME]
    python3 tools/proof/agent_open_proof.py --clean

Builds `agent_open_probe.swift` over app/Sources (minus `main.swift`) on
swift_build.py's line, cached by content, under
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
`~/Library/Application Support/Frame Job/Rewrapped/`, and a run killed by its
alarm leaves only the work folder, which the next run removes. A run writes
about 4 x `--megabytes` there (the fixture and three copies, at most the
fixture and one copy on disk at once). Not a line of `make test`.

**The build folder**, `tools/proof/work/agent-open-build/`, is kept between
runs so a repeat run does not rebuild the probe: `probe/` (the baseline's,
about 30 MB) stays, and a mutant's `mutants/<name>/` (about 35 MB, rebuilt on
every run because its sources are copied afresh) is removed when its run
ends. `--clean` removes the whole build folder and exits 0, running nothing.

Rows (a 10 ms main run-loop timer counts, during each call, its ticks, the
ticks that saw a `.partial.mov` in `Rewrapped/`, and the ticks with
`RewrapProgressWindowController.live` non-empty):

- **A0** the probe built (a failed build is a scored FAILURE), the fixture's
  size, and the probe's `AppSupport.subdirectory("Rewrapped")`, read before
  any call: it must lie inside `<work>/home`, else A0 fails and A1–A14 do not
  run.
- **A1** `open_project {big.webm}` answers a project with one media, its path
  directly in the scratch home's `Frame Job/Rewrapped/` and on disk; the
  call's seconds are printed, divided into before the partial was first
  seen, while it was written and after it was last seen (#235). **A2** at
  least 3 ticks saw the partial: main ran while the copy was written — a
  count, not a timing; how long a copy lasts is the disk's. **A3** `live`
  was empty at every tick.
- **A4** the project saved, closed, its `project.json` media path rewritten
  to `/nonexistent-b79/<name>` with `bookmark` null and the copy removed
  (`container_import_proof.py` M9's method): `open_project {package}` answers
  a path directly in the scratch home's `Frame Job/Rewrapped/`, on disk, with
  `original.path` the WebM. **A5** at least 3 ticks saw the partial. **A6**
  `live` was empty at every tick.
- **A7** the package closed and its copy removed again; on the first tick
  that sees the partial, main adds a stub `ProjectDocument` whose `fileURL`
  is the package: the call answers `already_open` and one open document is
  at that path.

A8–A14 (#234) race a person's open of the package against an agent's call.
The probe's controller is the app's `ProjectDocumentController` with seams:
a read is HELD after it is made, off main, until the other side has got as
far as the row needs, each hold bounded at 120 s (an expired hold fails its
row by name); the Open panel answers the package with no panel; a presented
error is counted. No row removes a copy or waits on a partial tick, and each
starts with every document closed. A person's read is let go, in mode
`seen`, once `opens(of:)` has answered above 0 or the row's agent call has
answered, and in mode `answered` once that call has answered; an agent's
read, where the row says so, once the person-style open has been called.
The two `makeDocument` overrides also note `Thread.isMainThread` as each
person's read is entered; A8, A10 and A11 print the count and want at least
one such read and none on the main thread. That is this probe's process (a
`.prohibited` one) at those three doors, not every door of the app.

- **A8** File ▸ Open's own action, `openDocument(nil)`; once the public
  open's override is entered, `open_project {package}` (mode `seen`):
  `already_open: true`; one document at the path, the one the person's
  open's completion carries; error nil; the override entered once; 0 errors
  presented; the person's read entered off the main thread. **A9** the agent
  read nothing during A8.
- **A10** `open_project` first, its read held; then
  `openDocument(withContentsOf:display:)` — Welcome's and `FileDropView`'s
  call — once that read is entered (mode `seen`): `already_open: true`, one
  document, the person's; one read by the agent, its document not among the
  open ones; the person's read entered off the main thread.
- **A11** A8 by `reopenDocument(for:withContentsOf:display:)`, the person's
  one read entered off the main thread.
- **A12** `AgentServer.personOpenWait = 1` (put back after A13): the
  person-style open, then `open_project` (mode `answered`): the refusal
  ("… is being opened in a window …"), no sooner than 1 s, 0 reads by the
  agent; then one document, the person's.
- **A13** A10's order, mode `answered`: the refusal, no sooner than 1 s
  after the person's open was called; one read by the agent, its document
  not among the open ones; then one document, the person's.
- **A14** the person-style open, then `new_project {path: package}` (mode
  `answered`): `refuseHeldPath`'s refusal; `project.json`'s bytes
  unchanged; then one document at the path and no other open.

`--mutant NAME` builds the probe over a copy of app/Sources with one text
replaced and must fail exactly `EXPECTED[NAME]` (then MUTANT PASS, exit 0):
`open-on-main` (`"open_project"` out of the off-main set), `quiet-watch`
(`probeBlocking` passes its watch inside `withoutAsking`),
`recopy-agent-watch` (the re-copy's guard back to the main thread alone),
`no-recheck` (step C adds the document it made without looking for a holder
again) and `no-inflight` (`ProjectDocumentController.isOpening` answers
false: the establishing run for what the app did before #234, which must
print "2 open documents" for A8 and A10). Exit 2 when the control could not
be performed.

`--megabytes` defaults to 256, which B79 chose as the first of 256, 512 and
1024 whose baseline run printed at least 30 partial ticks for both A2 and A5
(the proof README's B79 section names each size tried). That count was the
host's disk (#235): B81's baseline printed 22 and 19 at the same size, and
A2 and A5 now want 3, so the default is not re-chosen by it.
"""

import argparse
import atexit
import json
import math
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402

WORK = os.path.join(HERE, "work", "agent-open")
BUILD = os.path.join(HERE, "work", "agent-open-build")
HOME = os.path.join(WORK, "home")
SOURCES = os.path.join(ROOT, "app", "Sources")
PROBE_SWIFT = os.path.join(HERE, "agent_open_probe.swift")
LIB = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
WALL_BUILD, WALL_RUN, WALL_FFMPEG = 900, 900, 600
ROWS = ["A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11", "A12", "A13",
        "A14"]
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
    # Step C's holder check (the one whose arm closes the made document).
    "no-recheck": ("AgentServer+Project.swift",
                   "if let answer = try self.alreadyOpen(url) {\n                document.close()",
                   "if false, let answer = try self.alreadyOpen(url) {\n"
                   "                document.close()"),
    "no-inflight": ("ProjectDocumentController.swift",
                    "        return controller.opens(of: url) > 0\n",
                    "        _ = controller\n        return false\n"),
}

# The rows each mutant must fail, and only those. B79's four sets were
# measured on 2026-10-03; what B81 adds to them, and `no-inflight`'s set, are
# PREDICTIONS written before the first build (the proof README's B81 section
# says how each run compared). `open-on-main` also fails A7: with the read on
# main no tick sees the partial, so the stub is never added and the call
# opens the package. With the handler on main its wait's deadline is at
# once, so A8, A11 and A12 are refused at once and A10 and A13 add the
# agent's document before the person's open is called. `no-recheck` also
# fails A10: after the wait, step C adds beside the person's document.
EXPECTED = {
    "open-on-main": {"A2", "A5", "A7", "A8", "A10", "A11", "A12", "A13"},
    "quiet-watch": {"A3"},
    "recopy-agent-watch": {"A6"},
    "no-recheck": {"A7", "A10"},
    "no-inflight": {"A8", "A9", "A10", "A11", "A12", "A13", "A14"},
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


def make_fixture(megabytes, folder=WORK):
    """(path, None) or (None, reason): `<folder>/big.webm`, at least
    `megabytes` MiB (`agent_socket_proof.py`'s K15 makes its own with this)."""
    seed, big = os.path.join(folder, "seed.webm"), os.path.join(folder, "big.webm")
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
    """(binary, None) or (None, reason), through `swift_build.build` (reused
    when every input is byte-identical to a cached build's)."""
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
    print(f"probe: {len(swift)} sources through swift_build (up to {WALL_BUILD} s)…", flush=True)
    try:
        built = swift_build.build(sources=swift + [entry], output=binary,
                                  defines=["FRAMEJOB_DEV_TOOLS"], timeout=WALL_BUILD)
    except swift_build.SwiftBuildFailed as error:
        return None, (f"swiftc exited {error.rc if error.rc is not None else 'before running'} "
                      f"(expired {error.expired}): "
                      + " | ".join(error.diagnostics[:6] or ["(no output)"]))
    print(f"probe: {binary} (up to date)" if built.reused
          else f"probe: built in {built.seconds:.0f} s", flush=True)
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
    parser.add_argument("--clean", action="store_true",
                        help="remove the build folder and exit, running nothing")
    args = parser.parse_args()
    if args.clean:
        shutil.rmtree(BUILD, ignore_errors=True)
        print(f"removed {BUILD}")
        return 0

    results = []

    def row(row_id, ok, detail):
        results.append((row_id, bool(ok)))
        print(("  ok   " if ok else "  FAIL ") + f"{row_id} {detail}", flush=True)

    remove_work()
    atexit.register(remove_work)
    sources, probe_dir = SOURCES, os.path.join(BUILD, "probe")
    if args.mutant:
        # A mutant's folder is rebuilt on every run, so it is not kept.
        atexit.register(shutil.rmtree, os.path.join(BUILD, "mutants", args.mutant),
                        ignore_errors=True)
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
