#!/usr/bin/env python3
"""Road map "swift-helper" SA3 — `tools/agent/build_helper.sh`'s rules (spec §11 SA-8), over toy
packages. A line of `make test`.

    python3 tools/proof/agent_build_proof.py                  # K1–K10; exit 0 when all pass
    python3 tools/proof/agent_build_proof.py --mutant NAME    # one of MUTANTS: the rows run with
                                                              # the script copied, one anchor
                                                              # replaced; exactly EXPECTED[NAME]
                                                              # must FAIL (exit 1)

A toy is a package of the helper's shape — a kit embedding `table.json` through a relative link
to `agent/prices/table.json`, the executable `framejob-agent`, and a test target (SwiftPM loads a
manifest's every target, so the shape needs one) — with no dependency, so a cold release build
takes seconds and no network. Each toy tree is under `tools/agent/work/build-proof/` (ignored,
made fresh) and holds its own copy of the script under test in its `tools/agent/`, as a tree
does, byte-identical to the tree's or with one mutant's edit; tree C's `tools` is a link to A's,
as a tree copy's is. The product prints `<marker>|<table>|<key seen or not>`.

  K1   cold: exit 0, "built", the helper at the destination prints A's marker and table, signed
       with the hardened runtime and no entitlements; the stamp written, and the path record
       naming the scratch path
  K2   the same again: "skipped"
  K3   a source edit: "built" in place (a sentinel in the scratch path survives), the new marker
  K4   an edit of the table the link points at: "built", the new table (the key reads through
       links)
  K5   tree B, its `agent/` copied with `shutil.copytree` (the link becomes the table's bytes, as
       `tree_copy.py` copies it) and its scratch path a `cp -cRp` clone of A's: "skipped", A's
       helper (a clone is served at another path while its key matches)
  K6   tree B2, made as B is from a fresh clone of A's, with a source edited: "emptied", the
       sentinel the clone carried gone, the record naming B2's scratch path, B2's marker (a miss
       on a scratch path made elsewhere builds cold)
  K7   tree C, reached through a `tools` link to A's: C's marker (the tree is $PROJECT_DIR, not
       the script's own path); with PROJECT_DIR unset the script refuses, naming it, and writes
       no helper
  K8   tree D built, then a source that does not compile: non-zero, no helper at the destination
       (which the good build had written) and no stamp
  K9   tree E (its manifest carrying a fresh nonce, so SwiftPM's manifest cache cannot answer),
       built with both keys set to dummies and FJ_AGENT_STRICT=1 in the caller's environment:
       the manifest's `Context.environment` saw no key
  K10  the script spells no `agent-swift-test`, and a sentinel in tree A's
       `build/agent-swift-test` survives every run (SA-12's scratch path is the suite's)

The mutants each replace one anchor of `tools/agent/build_helper.sh` in the copy:
`path-in-key` (the scratch path in the key) K5; `no-table-in-key` (`find` without `-L`) K4 and
K5 (the link's target unread, and a copy's regular file read where the tree's link is not);
`tree-from-script` (the tree from the script's physical path) K7; `miss-keeps-foreign` (no
emptying) K6;
`failure-masked` (SwiftPM's failure carried on) K8; `env-not-scrubbed` (`env` without `-i`) K9.
An instrument that cannot run is a scored FAIL; a mutant run exits 1 when exactly its rows
FAILed, 0 when any of them passed or another row failed, and 2 when a row was an instrument
failure (rule R). No key is read: every child has `ANTHROPIC_API_KEY` and `RC_ASSEMBLYAI_KEY`
popped, and K9's are the dummies below. Each child runs under a wall in its own process group
(`bounded.run`).
"""

import argparse
import os
import shutil
import subprocess
import sys
import uuid
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402

SCRIPT = "tools/agent/build_helper.sh"
WORK = ROOT / "tools/agent/work/build-proof"
WALL = 600
DUMMIES = {"ANTHROPIC_API_KEY": "RCDUMMY-agent-build-proof-anthropic",
           "RC_ASSEMBLYAI_KEY": "RCDUMMY-agent-build-proof-assemblyai", "FJ_AGENT_STRICT": "1"}
# name: (file from the repo root, the text there exactly once, what replaces it)
MUTANTS = {
    "path-in-key": (SCRIPT, "        printf 'script %s\\n' \"$SELF_DIGEST\"\n",
                    "        printf 'script %s\\n' \"$SELF_DIGEST\"\n"
                    "        printf 'scratch %s\\n' \"$SCRATCH\"\n"),
    "no-table-in-key": (SCRIPT, "find -L agent/Sources -type f", "find agent/Sources -type f"),
    "tree-from-script": (SCRIPT, 'TREE="$(cd "$PROJECT_DIR" && pwd -P)"',
                         'TREE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"'),
    "miss-keeps-foreign": (SCRIPT, '        if [ "$RECORDED" != "$SCRATCH" ]; then',
                           "        if false; then"),
    "failure-masked": (SCRIPT, "SwiftPM failed to build framejob-agent from $TREE/agent\" >&2\n"
                               "        exit 1\n",
                       "SwiftPM failed to build framejob-agent from $TREE/agent\" >&2\n"
                       "        true\n"),
    "env-not-scrubbed": (SCRIPT, 'SCRUBBED=(env -i "HOME=$HOME"', 'SCRUBBED=(env "HOME=$HOME"'),
}
EXPECTED = {"path-in-key": {"K5"}, "no-table-in-key": {"K4", "K5"},
            "tree-from-script": {"K7"}, "miss-keeps-foreign": {"K6"},
            "failure-masked": {"K8"}, "env-not-scrubbed": {"K9"}}
ROWS = [f"K{n}" for n in range(1, 11)]

MANIFEST = """// swift-tools-version: 6.0
// agent_build_proof's toy ({nonce}): the helper's shape, no dependency.
import PackageDescription

let seen = Context.environment["ANTHROPIC_API_KEY"] != nil
    || Context.environment["RC_ASSEMBLYAI_KEY"] != nil

let package = Package(
    name: "Toy",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "framejob-agent", targets: ["framejob-agent"])],
    targets: [
        .target(name: "Kit", resources: [.embedInCode("table.json")]),
        .executableTarget(name: "framejob-agent", dependencies: ["Kit"],
                          swiftSettings: seen ? [.define("KEY_SEEN")] : []),
        .testTarget(name: "KitTests", dependencies: ["Kit"]),
    ]
)
"""
KIT = """public enum Kit {{
    public static let marker = "{marker}"
    public static var table: String {{ String(decoding: PackageResources.table_json, as: UTF8.self) }}
}}
"""
MAIN = """import Kit
#if KEY_SEEN
let keys = "key seen"
#else
let keys = "no key"
#endif
print("\\(Kit.marker)|\\(Kit.table)|\\(keys)")
"""
TEST = "import XCTest\n@testable import Kit\n\nfinal class KitTests: XCTestCase {\n" \
       "    func testMarker() { XCTAssertFalse(Kit.marker.isEmpty) }\n}\n"


def child_env(project_dir=None, extra=None):
    """The caller's environment with both keys, FJ_AGENT_STRICT and Xcode's identity popped."""
    env = bounded.child_env()
    for key in ("ANTHROPIC_API_KEY", "RC_ASSEMBLYAI_KEY", "FJ_AGENT_STRICT", "PROJECT_DIR",
                "EXPANDED_CODE_SIGN_IDENTITY"):
        env.pop(key, None)
    if project_dir is not None:
        env["PROJECT_DIR"] = str(project_dir)
    env.update(extra or {})
    return env


def toy(tree, marker, table, script, nonce="fixed"):
    """A toy package at `tree/agent`, the script under test at `tree/tools/agent/`, and
    `tree/build/` made."""
    tools(tree, script)
    agent = tree / "agent"
    (agent / "prices").mkdir(parents=True)
    (agent / "prices" / "table.json").write_text(table)
    kit = agent / "Sources" / "Kit"
    kit.mkdir(parents=True)
    (kit / "Kit.swift").write_text(KIT.format(marker=marker))
    os.symlink("../../prices/table.json", kit / "table.json")
    (agent / "Sources" / "framejob-agent").mkdir(parents=True)
    (agent / "Sources" / "framejob-agent" / "main.swift").write_text(MAIN)
    (agent / "Tests" / "KitTests").mkdir(parents=True)
    (agent / "Tests" / "KitTests" / "KitTests.swift").write_text(TEST)
    (agent / "Package.swift").write_text(MANIFEST.format(nonce=nonce))
    (tree / "build").mkdir(parents=True, exist_ok=True)


def tools(tree, script):
    """The script under test, a regular file in the tree's own `tools/agent/`, as a tree holds it."""
    path = tree / SCRIPT
    path.parent.mkdir(parents=True)
    path.write_text(script)
    path.chmod(0o755)


def clone(source, tree, script, marker=None):
    """Tree `tree`: `source`'s `agent/` copied with `shutil.copytree` (a link becomes its target's
    bytes, as `tree_copy.py` copies it), its own script, and `source`'s scratch path cloned with
    `cp -cRp`; the clone's exit status."""
    shutil.copytree(source / "agent", tree / "agent")
    tools(tree, script)
    (tree / "build").mkdir(parents=True)
    if marker is not None:
        mark(tree, marker)
    return subprocess.run(["cp", "-cRp", str(source / "build/agent-swift"),
                           str(tree / "build/agent-swift")], capture_output=True,
                          timeout=300).returncode


def mark(tree, marker):
    (tree / "agent" / "Sources" / "Kit" / "Kit.swift").write_text(KIT.format(marker=marker))


def build(tree, destination, env=None, through=None):
    """The script run on `tree` (its own copy, else `through`'s): (exit, its `build_helper:` line
    or its last error line)."""
    script = (through or tree) / SCRIPT
    ran = bounded.run(["/bin/bash", str(script), str(destination)], WALL, cwd=str(tree),
                      env=env or child_env(tree))
    lines = (ran["stdout"] + ran["stderr"]).splitlines()
    said = [line for line in lines if line.startswith("build_helper: ")]
    errors = [line for line in lines if "error" in line]
    text = said[-1] if said else (errors[-1] if errors else (lines[-1] if lines else "(nothing)"))
    rc = None if ran["expired"] else ran["rc"]
    return rc, text[:240]


def runs(helper):
    """What the helper prints, or None."""
    try:
        done = subprocess.run([str(helper)], capture_output=True, text=True, timeout=30,
                              env=child_env())
    except (OSError, subprocess.TimeoutExpired):
        return None
    return done.stdout.strip() if done.returncode == 0 else None


def signing(helper):
    """(the CodeDirectory flags, whether the entitlements are empty)."""
    shown = subprocess.run(["codesign", "-dv", "--verbose=4", str(helper)], capture_output=True,
                           text=True, timeout=60)
    flags = next((part.split("(")[1].rstrip(")").split(",") for part in shown.stderr.split()
                  if part.startswith("flags=0x") and "(" in part), [])
    ents = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(helper)],
                          capture_output=True, timeout=60)
    return flags, ents.returncode == 0 and not ents.stdout.strip()


def stamp(tree):
    return tree / "build/agent-swift/.framejob-helper-stamp"


def record(tree):
    path = tree / "build/agent-swift/.framejob-helper-path"
    return path.read_text().strip() if path.is_file() else None


def scratch_of(tree):
    return str((tree / "build/agent-swift").resolve())


def failing_package(script=None, d=None):
    """K8: a toy built, then a source that does not compile; (ok, detail). `script` defaults to
    the tree's, and `d` to a fresh folder of its own (`assistant_helper_proof.py`'s P1 calls it
    so, spec §11 SA-8: a failed SwiftPM build fails the app build's step)."""
    if script is None:
        script = (ROOT / SCRIPT).read_text()
    if d is None:
        d = ROOT / "tools/agent/work/failing-package"
        shutil.rmtree(d, ignore_errors=True)
    toy(d, "D", "d1", script)
    dest_d = d / "dest" / "framejob-agent"
    rc_good, _ = build(d, dest_d, child_env(d))
    had = dest_d.is_file()
    (d / "agent/Sources/Kit/Kit.swift").write_text("public enum Kit { this does not compile }\n")
    rc, said = build(d, dest_d, child_env(d))
    return (rc_good == 0 and had and rc not in (0, None) and not dest_d.exists()
            and not stamp(d).exists(),
            f"the good build exit {rc_good}, a helper {had}; the broken one exit {rc}, "
            f"{said!r}; a helper left {dest_d.exists()}, a stamp left {stamp(d).exists()}")


def rows(script):
    """K1–K10 with `script`, the text under test; {row: (ok, detail)}."""
    out = {}
    a, b, b2, c, d, e = (WORK / name for name in ("a", "b", "b2", "c", "d", "e"))
    toy(a, "A", "v1", script)
    suite = a / "build" / "agent-swift-test"
    suite.mkdir(parents=True)
    (suite / "sentinel").write_text("the suite's\n")
    dest = a / "dest" / "framejob-agent"

    rc, said = build(a, dest)
    flags, empty = signing(dest) if dest.is_file() else ([], False)
    printed = runs(dest)
    out["K1"] = (rc == 0 and "built" in said and "emptied" not in said and printed == "A|v1|no key"
                 and "runtime" in flags and empty and stamp(a).is_file()
                 and record(a) == scratch_of(a),
                 f"exit {rc}, {said!r}; prints {printed!r}; flags {flags}, entitlements empty "
                 f"{empty}; stamp {stamp(a).is_file()}, record {record(a)!r}")

    rc, said = build(a, dest)
    out["K2"] = (rc == 0 and "skipped" in said, f"exit {rc}, {said!r}")

    (a / "build/agent-swift/sentinel").write_text("kept\n")
    mark(a, "A2")
    rc, said = build(a, dest)
    printed = runs(dest)
    kept = (a / "build/agent-swift/sentinel").exists()
    out["K3"] = (rc == 0 and "built" in said and "emptied" not in said and kept
                 and printed == "A2|v1|no key",
                 f"exit {rc}, {said!r}; sentinel kept {kept}; prints {printed!r}")

    (a / "agent/prices/table.json").write_text("v2")
    rc, said = build(a, dest)
    printed = runs(dest)
    out["K4"] = (rc == 0 and "built" in said and printed == "A2|v2|no key",
                 f"exit {rc}, {said!r}; prints {printed!r}")

    cloned = clone(a, b, script)
    regular = (b / "agent/Sources/Kit/table.json").is_file() and not \
        (b / "agent/Sources/Kit/table.json").is_symlink()
    dest_b = b / "dest" / "framejob-agent"
    rc, said = build(b, dest_b, child_env(b))
    printed = runs(dest_b)
    out["K5"] = (cloned == 0 and regular and rc == 0 and "skipped" in said
                 and printed == "A2|v2|no key",
                 f"clone exit {cloned}; B's table a regular file {regular}; exit {rc}, "
                 f"{said!r}; prints {printed!r}")

    cloned = clone(a, b2, script, "B")
    dest_b2 = b2 / "dest" / "framejob-agent"
    rc, said = build(b2, dest_b2, child_env(b2))
    printed = runs(dest_b2)
    gone = not (b2 / "build/agent-swift/sentinel").exists()
    out["K6"] = (cloned == 0 and rc == 0 and "emptied" in said and gone
                 and record(b2) == scratch_of(b2) and printed == "B|v2|no key",
                 f"a fresh clone of A's, exit {cloned}, B's source: exit {rc}, {said!r}; the "
                 f"clone's sentinel gone {gone}; record {record(b2)!r}; prints {printed!r}")

    toy(c, "C", "c1", script)
    shutil.rmtree(c / "tools")
    os.symlink(str(a / "tools"), c / "tools")
    dest_c = c / "dest" / "framejob-agent"
    rc, said = build(c, dest_c, child_env(c))
    printed = runs(dest_c)
    dest_u = c / "unset" / "framejob-agent"
    rc_u, said_u = build(c, dest_u, child_env(None))
    out["K7"] = (rc == 0 and printed == "C|c1|no key" and rc_u not in (0, None)
                 and "PROJECT_DIR" in said_u and not dest_u.exists(),
                 f"through C's tools link: exit {rc}, prints {printed!r}; PROJECT_DIR unset: exit "
                 f"{rc_u}, {said_u!r}, a helper written {dest_u.exists()}")

    out["K8"] = failing_package(script, d)

    toy(e, "E", "e1", script, nonce=uuid.uuid4().hex)
    dest_e = e / "dest" / "framejob-agent"
    rc, said = build(e, dest_e, child_env(e, DUMMIES))
    printed = runs(dest_e)
    out["K9"] = (rc == 0 and printed == "E|e1|no key",
                 f"with both keys and FJ_AGENT_STRICT set by the caller: exit {rc}, prints "
                 f"{printed!r}")

    survived = (suite / "sentinel").exists()
    out["K10"] = ("agent-swift-test" not in script and survived,
                  f"`agent-swift-test` in the script: {'agent-swift-test' in script}; the suite's "
                  f"sentinel survived {survived}")
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    text = (ROOT / SCRIPT).read_text()
    if args.mutant:
        _, anchor, replacement = MUTANTS[args.mutant]
        if text.count(anchor) != 1:
            print(f"mutant {args.mutant}: the control could not be performed — its anchor occurs "
                  f"{text.count(anchor)} times in {SCRIPT}", flush=True)
            return 2
        text = text.replace(anchor, replacement)
    try:
        found = rows(text)
    except Exception as error:  # noqa: BLE001 — an instrument that cannot run is a FAIL
        print(f"setup FAIL — the instrument could not run: {type(error).__name__}: {error}",
              flush=True)
        if args.mutant:
            print(f"mutant {args.mutant}: the control could not be performed — the instrument "
                  f"raised", flush=True)
            return 2
        return 1
    for row in ROWS:
        ok, detail = found.get(row, (False, "not scored"))
        print(f"{row} {'ok' if ok else 'FAIL'} — {detail}", flush=True)
    failed = {row for row in ROWS if not found.get(row, (False,))[0]}
    print(f"{len(ROWS) - len(failed)}/{len(ROWS)}", flush=True)
    shutil.rmtree(WORK, ignore_errors=True)
    if args.mutant:
        want = EXPECTED[args.mutant]
        if failed == want:
            print(f"mutant {args.mutant}: caught — exactly {', '.join(sorted(want))} failed",
                  flush=True)
            return 1
        print(f"mutant {args.mutant}: SURVIVED — failed {sorted(failed)}, expected "
              f"{sorted(want)}", flush=True)
        return 0
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
