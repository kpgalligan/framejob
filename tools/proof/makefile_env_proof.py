#!/usr/bin/env python3
"""Road map 6 §10.13 (the C1 reader review), H·2, and road map 12 A1 part 2 —
`make app` does not write the two keys to disk.

`xcodebuild` records every task's ENVIRONMENT in its build database under
`build/Build/Intermediates.noindex/XCBuildData/`, so a `make app` run from a
shell that exports `RC_ASSEMBLYAI_KEY` used to leave that key's value there
(road map 6 §10.12 has the measurement), and `ANTHROPIC_API_KEY` is the
same kind of value. The `Makefile` carries one directive per key,
`unexport RC_ASSEMBLYAI_KEY` and `unexport ANTHROPIC_API_KEY`, above
`.PHONY`, which cover every recipe in the file — `app`, `rust`, `test`,
`lint`, `fmt`, `project`, `typecheck` and `run`.

    (unset ANTHROPIC_API_KEY RC_ASSEMBLYAI_KEY; python3 tools/proof/makefile_env_proof.py)
    (unset …; python3 tools/proof/makefile_env_proof.py --mutant no-unexport)
    (unset …; python3 tools/proof/makefile_env_proof.py --mutant no-unexport-anthropic)

**It measures `app` ONLY, and says so.** `app` is the one recipe that runs
`xcodebuild`, which is the one tool measured to write its environment down.
The other recipes are covered by the same directive and are not built here.

**The values used are DUMMIES and never the person's.** The child's
environment is built from `os.environ` with both keys POPPED and
`RCDUMMY-makefile-env-proof-5d1c` and
`RCDUMMY-makefile-env-proof-anthropic-9b3e` put in their places; the
person's own values are never read, printed, searched for or written. The
search afterwards is IN PROCESS — the bytes of each dummy against the bytes
of every file under the copy's `build/` and `Reelcut.xcodeproj/` — and
nothing but paths and booleans is ever printed.

**The tree is never touched.** Everything happens in a COPY at
`tools/proof/work/makefile-env/tree`, made by `tree_copy.make_copy`: `app/`
and `agent/` (without `node_modules`, because the helper's build step runs
`bun install` and `bun build`, which write into it) are COPIED, and every
other build input `project.yml` names is a SYMLINK to the tree's (`core`
already built, so `project.yml`'s pre-build `cargo build --release` is a
no-op and the copy links the tree's `libreelcut_core.a`).

The three rows:

* the build made `Reelcut.app`'s binary — a failed build holds nothing, and
  "no file holds the dummy" would be true of it for the wrong reason;
* no file under the copy's `build/` or `Reelcut.xcodeproj/` holds the
  AssemblyAI dummy's bytes;
* no file there holds the Anthropic dummy's bytes.

Each directive is asserted to occur exactly once in the tree's `Makefile`.
Under `--mutant no-unexport` the AssemblyAI directive is removed in the
COPY and its row FAILS; under `--mutant no-unexport-anthropic` the
Anthropic one is, and that row FAILS. Those are the CONTROLS that this
instrument can see a leak of either key at all. A mutant run exits 1 when a
row failed (caught) and 0 when none did (it survived); a copy that could
not be made or a build that failed performs no control and exits 2 (rule R,
issue batch B13), printing `mutant <name>: the control could not be
performed — <why>`. Without `--mutant` either is a scored FAIL, exit 1.
`make app` runs through `bounded.run` in its own session, so a build that
passes `--wall` has its whole process group killed (rule H, issue batch
B28): `make` and `xcodebuild` die with the group, while what `xcodebuild`'s
build service starts in its own process groups (`swift-frontend`,
build-phase scripts) can outlive it.
"""

import argparse
import os
import shutil
import sys
import time

import tree_copy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "graphics_spike"))
import bounded  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "makefile-env")

# Each key: its dummy (recognisable, and nothing else in the tree or in any
# SDK spells it), its directive as it stands in the tree's Makefile, the
# mutant that removes that directive, and the row's name.
KEYS = [
    {"key": "RC_ASSEMBLYAI_KEY", "dummy": "RCDUMMY-makefile-env-proof-5d1c",
     "directive": "unexport RC_ASSEMBLYAI_KEY\n", "mutant": "no-unexport",
     "label": "AssemblyAI"},
    {"key": "ANTHROPIC_API_KEY", "dummy": "RCDUMMY-makefile-env-proof-anthropic-9b3e",
     "directive": "unexport ANTHROPIC_API_KEY\n", "mutant": "no-unexport-anthropic",
     "label": "Anthropic"},
]

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
    """`os.environ` with the person's keys POPPED and the dummies in their
    places.

    `pop` never binds the old value to a name here, so this process does not
    read the person's keys in order to remove them."""
    env = dict(os.environ)
    for one in KEYS:
        env.pop(one["key"], None)
        env[one["key"]] = one["dummy"]
    return env


def make_copy(mutant):
    """A COPY of the tree from `tree_copy.make_copy`, and a directive
    removed when the mutant asks for it. Answers the copy's root, or None
    and a reason."""
    shutil.rmtree(WORK, ignore_errors=True)
    root, reason = tree_copy.make_copy(os.path.join(WORK, "tree"))
    if root is None:
        return None, reason

    makefile = os.path.join(root, "Makefile")
    with open(makefile) as handle:
        text = handle.read()
    for one in KEYS:
        count = text.count(one["directive"])
        if count != 1:
            return None, (f"the tree's Makefile carries {one['directive'].strip()!r} {count} "
                          f"times, not once" + (" — the mutant needs re-aiming"
                                                if mutant == one["mutant"] else ""))
    for one in KEYS:
        if mutant == one["mutant"]:
            text = text.replace(one["directive"], "")
            with open(makefile, "w") as handle:
                handle.write(text)
            print(f"  mutant {mutant}: {one['directive'].strip()!r} removed from the COPY — "
                  f"the CONTROL that this instrument can see a leak of that key\n")
    return root, None


def build(root, wall):
    """`make app` inside the copy, with the dummy exported. Answers the
    binary's path, or None and a reason."""
    binary = os.path.join(root, "build", "Build", "Products", "Release", "Reelcut.app",
                          "Contents", "MacOS", "Reelcut")
    started = time.time()
    run = bounded.run(["make", "app"], wall, cwd=root, env=child_env())
    if run["expired"]:
        return None, f"the copy's `make app` passed its {wall:.0f} s wall"
    if run["rc"] != 0:
        errors = [line for line in run["stdout"].splitlines() if "error:" in line]
        last = [line for line in run["stderr"].strip().splitlines() if line.strip()][-1:]
        lines = errors[:6] or last or ["(none)"]
        return None, "`make app` failed:\n      " + "\n      ".join(lines)
    if not os.path.exists(binary):
        return None, f"`make app` succeeded and wrote no binary at {binary}"
    print(f"  built {binary} in {time.time() - started:.0f} s")
    return binary, None


def holders(root):
    """For each dummy, every file under the copy's `build/` and
    `Reelcut.xcodeproj/` whose BYTES hold it, as paths relative to the copy.

    In process, with `open(..., 'rb')` and `in`: nothing is shelled out to,
    so a dummy is never a process argument and never reaches a log."""
    needles = {one["dummy"]: one["dummy"].encode("utf-8") for one in KEYS}
    found = {dummy: [] for dummy in needles}
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
                for dummy, needle in needles.items():
                    if needle in body:
                        found[dummy].append(os.path.relpath(path, root))
    return found, scanned


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--mutant", choices=[one["mutant"] for one in KEYS],
                        help="remove one key's `unexport` directive in the COPY — the "
                             "CONTROL, under which that key's leak row must FAIL")
    parser.add_argument("--wall", type=float, default=900,
                        help="the copy's `make app` wall-clock bound in seconds (rule H)")
    arguments = parser.parse_args()

    started = time.time()
    print("road map 6 §10.13, H·2, and road map 12 A1 part 2 — `make app` and the two keys\n")
    print("  (this measures the `app` recipe ONLY: it is the one that runs xcodebuild, "
          "which is the one tool measured to write its environment down)\n")

    root, reason = make_copy(arguments.mutant)
    if root is None:
        check("the tree copy is made and the directive is where it is expected", False, reason)
        print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
        return not_performed(arguments.mutant, reason)

    binary, reason = build(root, arguments.wall)
    check("the copy's `make app` built Reelcut.app's binary — a failed build holds nothing, "
          "and \"no file holds the dummy\" would be true of it for the wrong reason",
          binary is not None, reason or "")
    if binary is None:
        print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
        return not_performed(arguments.mutant, reason)

    found, scanned = holders(root)
    for one in KEYS:
        held = found[one["dummy"]]
        check(f"no file under the copy's build/ or Reelcut.xcodeproj/ holds the "
              f"{one['label']} dummy ({scanned} files read)",
              not held, "held by:\n       " + "\n       ".join(held[:8]))

    print(f"\n{passed}/{passed + failed} checks passed in {time.time() - started:.0f} s")
    return 0 if failed == 0 else 1


def not_performed(mutant, reason):
    """A copy or build that failed: 2 under `--mutant` (rule R, issue batch
    B13 — the control could not be performed), the scored FAIL's 1 without."""
    if not mutant:
        return 1
    print(f"mutant {mutant}: the control could not be performed — "
          f"{((reason or '').strip().splitlines() or ['no reason given'])[0]}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
