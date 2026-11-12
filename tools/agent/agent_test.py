#!/usr/bin/env python3
"""`make agent-test` — the Swift assistant helper's suite (road map "swift-helper" SA1, spec
§11 SA-12), a line of `make test`.

    python3 tools/agent/agent_test.py                  # the guard, then the suite
    python3 tools/agent/agent_test.py --tree DIR       # the same over another tree (a measurement)
    python3 tools/agent/agent_test.py --selftest       # the guard over scratch folders, no SwiftPM
    python3 tools/agent/agent_test.py --mutant guard-noop   # the selftest with the guard a no-op;
                                                            # must fail S1 and S2

The suite is `swift test` on `agent/` with `FJ_AGENT_STRICT=1` (the helper's own targets built
with warnings as errors, `agent/Package.swift`), on its own scratch path, `build/agent-swift-test`:
a debug build of Slaude, the kit, the executable and the tests. `build/agent-swift` is the app
build's release scratch path (SA3, SA-8) and is never touched here.

The guard (SA-12). SwiftPM cannot build on a scratch path made at another path: the cloned module
cache's precompiled headers name the path they were built at, and every compile fails (road map
§13, SA0 items 3 and 9). Every lane worktree starts by CoW-copying the integration worktree's
`build/`, so without the guard the first `make test` in each would fail. So the scratch path holds
a marker, `.framejob-scratch-path`, with its own absolute path; before SwiftPM runs, a scratch path
whose marker is missing or names another path is emptied, and the marker written. A copied scratch
path therefore builds Slaude cold once (the cost the owner accepted, road map §12 answer 5), and
one made here is reused.

The selftest's rows: S1 a scratch folder with no marker is emptied and marked; S2 one whose marker
names another path is emptied and marked; S3 one whose marker names it is kept as it is; S4 a
missing folder is made and marked. Each is a sentinel file seen gone or kept. Writes go only under
the scratch path and, for the selftest, `tools/agent/work/`. Exit 0 PASS, 1 FAIL (the selftest)
or the suite's own status.
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRATCH = "build/agent-swift-test"
MARKER = ".framejob-scratch-path"
SELFTEST = ROOT / "tools/agent/work/selftest"
EXPECTED = {"guard-noop": {"S1", "S2"}}
MUTANT = None


def guard(scratch):
    """Empties `scratch` unless its marker names it, then marks it. Answers what it did."""
    scratch = Path(scratch).resolve()
    own = str(scratch)
    marker = scratch / MARKER
    if not scratch.exists():
        scratch.mkdir(parents=True)
        marker.write_text(own + "\n")
        return "made"
    recorded = marker.read_text().strip() if marker.is_file() else None
    if recorded == own:
        return "kept"
    if MUTANT == "guard-noop":
        return "kept"
    shutil.rmtree(scratch)
    scratch.mkdir(parents=True)
    marker.write_text(own + "\n")
    return "emptied: " + ("no marker" if recorded is None else f"made at {recorded}")


def suite(tree):
    """The guard, then `swift test` on the tree's package; the suite's exit status."""
    tree = Path(tree).resolve()
    scratch = tree / SCRATCH
    print(f"agent-test: scratch path {scratch}: {guard(scratch)}", flush=True)
    env = dict(os.environ)
    for key in ("ANTHROPIC_API_KEY", "RC_ASSEMBLYAI_KEY"):
        env.pop(key, None)
    env["FJ_AGENT_STRICT"] = "1"
    argv = ["xcrun", "swift", "test", "--package-path", str(tree / "agent"), "--scratch-path", str(scratch)]
    print("agent-test: " + " ".join(argv), flush=True)
    return subprocess.run(argv, cwd=tree, env=env, stdin=subprocess.DEVNULL).returncode


def selftest():
    """S1–S4 over scratch folders; the failed row ids."""
    shutil.rmtree(SELFTEST, ignore_errors=True)
    SELFTEST.mkdir(parents=True)
    failed = []

    def row(row_id, ok, detail):
        print(f"{row_id} {'ok' if ok else 'FAIL'} — {detail}", flush=True)
        if not ok:
            failed.append(row_id)

    def folder(name, marker):
        path = SELFTEST / name
        path.mkdir()
        (path / "sentinel").write_text("built\n")
        if marker is not None:
            (path / MARKER).write_text(marker + "\n")
        return path

    def marked(path):
        target = path / MARKER
        return target.is_file() and target.read_text().strip() == str(path.resolve())

    s1 = folder("s1", None)
    said = guard(s1)
    row("S1", not (s1 / "sentinel").exists() and marked(s1), f"no marker: {said}")
    s2 = folder("s2", "/elsewhere/build/agent-swift-test")
    said = guard(s2)
    row("S2", not (s2 / "sentinel").exists() and marked(s2), f"another path's marker: {said}")
    s3 = SELFTEST / "s3"
    s3.mkdir()
    (s3 / "sentinel").write_text("built\n")
    (s3 / MARKER).write_text(str(s3.resolve()) + "\n")
    said = guard(s3)
    row("S3", (s3 / "sentinel").exists() and marked(s3), f"its own marker: {said}")
    s4 = SELFTEST / "s4" / "build" / "agent-swift-test"
    said = guard(s4)
    row("S4", s4.is_dir() and marked(s4) and len(list(s4.iterdir())) == 1, f"missing: {said}")
    shutil.rmtree(SELFTEST, ignore_errors=True)
    print(f"{4 - len(failed)}/4", flush=True)
    return failed


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--tree", default=str(ROOT), help="the tree whose agent/ the suite runs")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    args = parser.parse_args()
    if args.mutant:
        MUTANT = args.mutant
        failed = set(selftest())
        if failed == EXPECTED[args.mutant]:
            print(f"mutant {args.mutant}: caught — {', '.join(sorted(failed))} failed", flush=True)
            return 1
        print(f"mutant {args.mutant}: failed {sorted(failed)}, expected {sorted(EXPECTED[args.mutant])}", flush=True)
        return 0
    if args.selftest:
        return 1 if selftest() else 0
    return suite(args.tree)


if __name__ == "__main__":
    sys.exit(main())
