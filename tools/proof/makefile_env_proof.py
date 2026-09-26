#!/usr/bin/env python3
"""Road map 6 §10.13 (the C1 reader review), H·2 — `make app` does not write
the AssemblyAI key to disk.

`xcodebuild` records every task's ENVIRONMENT in its build database under
`build/Build/Intermediates.noindex/XCBuildData/`, so a `make app` run from a
shell that exports `RC_ASSEMBLYAI_KEY` used to leave that key's value there
(road map 6 §10.12 has the measurement). The `Makefile` now
carries one directive, `unexport RC_ASSEMBLYAI_KEY`, above `.PHONY`, which
covers every recipe in the file — `app`, `rust`, `test`, `lint`, `fmt`,
`project`, `typecheck` and `run`.

    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/makefile_env_proof.py
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/makefile_env_proof.py --mutant no-unexport

**It measures `app` ONLY, and says so.** `app` is the one recipe that runs
`xcodebuild`, which is the one tool measured to write its environment down.
The other recipes are covered by the same directive and are not built here.

**The value used is a DUMMY and never the person's.** The child's environment
is built from `os.environ` with `RC_ASSEMBLYAI_KEY` POPPED and
`RCDUMMY-makefile-env-proof-5d1c` put in its place; the person's own value is
never read, printed, searched for or written. The search afterwards is IN
PROCESS — the bytes of the dummy against the bytes of every file under the
copy's `build/` and `Reelcut.xcodeproj/` — and nothing but paths and booleans
is ever printed.

**The tree is never touched.** Everything happens in a COPY under
`tools/proof/work/makefile-env/` whose `core` is a SYMLINK to the tree's
already-built one, so `project.yml`'s pre-build `cargo build --release` is a
no-op and the copy links the tree's `libreelcut_core.a` —
`cloud_captions_proof.py`'s `build_mutant` shape.

The three rows:

* the build made `Reelcut.app`'s binary — a failed build holds nothing, and
  "no file holds the dummy" would be true of it for the wrong reason;
* no file under the copy's `build/` or `Reelcut.xcodeproj/` holds the dummy's
  bytes;
* under `--mutant no-unexport` — the directive's line asserted to occur
  exactly once in the tree's `Makefile` and removed in the COPY — the second
  row FAILS. That is the CONTROL that this instrument can see a leak at all.
"""

import argparse
import os
import shutil
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "makefile-env")

KEY = "RC_ASSEMBLYAI_KEY"
# Recognisable, and nothing else in the tree or in any SDK spells it.
DUMMY = "RCDUMMY-makefile-env-proof-5d1c"

# The one directive, as it stands in the tree's Makefile.
DIRECTIVE = "unexport RC_ASSEMBLYAI_KEY\n"

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def child_env():
    """`os.environ` with the person's key POPPED and the dummy in its place.

    `pop` never binds the old value to a name here, so this process does not
    read the person's key in order to remove it."""
    env = dict(os.environ)
    env.pop(KEY, None)
    env[KEY] = DUMMY
    return env


def make_copy(mutant):
    """A COPY of the tree with `core` a symlink, and the directive removed
    when the mutant asks for it. Answers the copy's root, or None and a
    reason."""
    shutil.rmtree(WORK, ignore_errors=True)
    os.makedirs(WORK)
    root = os.path.join(WORK, "tree")
    os.makedirs(root)
    shutil.copytree(os.path.join(ROOT, "app"), os.path.join(root, "app"),
                    ignore=shutil.ignore_patterns("Info.plist", "*.entitlements"))
    for one in ("project.yml", "Makefile"):
        shutil.copy2(os.path.join(ROOT, one), os.path.join(root, one))
    os.symlink(os.path.join(ROOT, "core"), os.path.join(root, "core"))

    makefile = os.path.join(root, "Makefile")
    with open(makefile) as handle:
        text = handle.read()
    count = text.count(DIRECTIVE)
    if mutant == "no-unexport":
        if count != 1:
            return None, (f"the directive occurs {count} times in the Makefile, not once — "
                          f"the mutant needs re-aiming")
        with open(makefile, "w") as handle:
            handle.write(text.replace(DIRECTIVE, ""))
        print(f"  mutant no-unexport: {DIRECTIVE.strip()!r} removed from the COPY — the "
              f"CONTROL that this instrument can see a leak\n")
    elif count != 1:
        return None, (f"the tree's Makefile carries the directive {count} times, not once")
    return root, None


def build(root, wall):
    """`make app` inside the copy, with the dummy exported. Answers the
    binary's path, or None and a reason."""
    binary = os.path.join(root, "build", "Build", "Products", "Release", "Reelcut.app",
                          "Contents", "MacOS", "Reelcut")
    started = time.time()
    try:
        run = subprocess.run(["make", "app"], cwd=root, capture_output=True, text=True,
                             env=child_env(), timeout=wall, stdin=subprocess.DEVNULL)
    except subprocess.TimeoutExpired:
        return None, f"the copy's `make app` passed its {wall:.0f} s wall"
    if run.returncode != 0:
        errors = [line for line in run.stdout.splitlines() if "error:" in line]
        return None, "`make app` failed:\n      " + "\n      ".join(errors[:6] or ["(none)"])
    if not os.path.exists(binary):
        return None, f"`make app` succeeded and wrote no binary at {binary}"
    print(f"  built {binary} in {time.time() - started:.0f} s")
    return binary, None


def holders(root):
    """Every file under the copy's `build/` and `Reelcut.xcodeproj/` whose
    BYTES hold the dummy, as paths relative to the copy.

    In process, with `open(..., 'rb')` and `in`: nothing is shelled out to,
    so the dummy is never a process argument and never reaches a log."""
    needle = DUMMY.encode("utf-8")
    found = []
    scanned = 0
    for folder in ("build", "Reelcut.xcodeproj"):
        base = os.path.join(root, folder)
        for here, _, names in os.walk(base):
            for name in names:
                path = os.path.join(here, name)
                if os.path.islink(path):
                    continue
                try:
                    with open(path, "rb") as handle:
                        body = handle.read()
                except OSError:
                    continue
                scanned += 1
                if needle in body:
                    found.append(os.path.relpath(path, root))
    return found, scanned


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=["no-unexport"],
                        help="remove the `unexport` directive in the COPY — the CONTROL, "
                             "under which the leak row must FAIL")
    parser.add_argument("--wall", type=float, default=900,
                        help="the copy's `make app` wall-clock bound in seconds (rule H)")
    arguments = parser.parse_args()

    started = time.time()
    print("road map 6 §10.13, H·2 — `make app` and the AssemblyAI key\n")
    print("  (this measures the `app` recipe ONLY: it is the one that runs xcodebuild, "
          "which is the one tool measured to write its environment down)\n")

    root, reason = make_copy(arguments.mutant)
    if root is None:
        check("the tree copy is made and the directive is where it is expected", False, reason)
        print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
        return 1

    binary, reason = build(root, arguments.wall)
    check("the copy's `make app` built Reelcut.app's binary — a failed build holds nothing, "
          "and \"no file holds the dummy\" would be true of it for the wrong reason",
          binary is not None, reason or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
        return 1

    found, scanned = holders(root)
    check(f"no file under the copy's build/ or Reelcut.xcodeproj/ holds the dummy "
          f"({scanned} files read)",
          not found, "held by:\n       " + "\n       ".join(found[:8]))

    print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
