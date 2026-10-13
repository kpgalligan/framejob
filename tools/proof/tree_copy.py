#!/usr/bin/env python3
"""Issue batch B7 (#146) — the one tree copy every proof that BUILDS the app
in a copy gets its copy from.

    python3 tools/proof/tree_copy.py --selftest

A proof that builds a mutant app must not build in the tree: xcodegen writes
`FrameJob.xcodeproj/`, `app/Info.plist` and `app/FrameJob.entitlements`, and
the helper's build step runs `bun install` and `bun build`, which write into
`agent/`. So the copy's `app/` and `agent/` are COPIED (`COPIED`), and every
other build input is a SYMLINK to the tree's — `core` already built, so
`project.yml`'s pre-build `cargo build --release` is a no-op and the copy
links the tree's `libframejob_core.a`.

**The build inputs are derived from `project.yml`, not listed by hand.**
`build_inputs` answers every top-level directory of the tree (no leading
`.`, not in `GENERATED`) whose name `project.yml` spells as `NAME/` not
preceded by a name character — `app/Sources`, `$PROJECT_DIR/core`,
`"$PROJECT_DIR/agent/build.sh"`. So a build step that reads a new top-level
directory is linked into every copy the day it lands, and no builder's copy
can miss it (#146: `graphics_proof.py`'s copy missed `agent/` and `docs/`).
`GENERATED` (`build`, `FrameJob.xcodeproj`) is never linked: a copy writes
its own.

`make_copy(dest, agent=True)`, in order: remove `dest` (`remove_tree`), make it; copy `app/`
without `Info.plist` or `*.entitlements`; copy `project.yml`, `Makefile`
and `VERSION` (`COPIED_FILES`: the copy's own `make project` reads all
three, spec §11 PUB-2); when `agent`, copy `agent/` without `node_modules`; link every
other build input. It answers `(dest, None)`, or `(None, reason)` on an
`OSError`. `agent=False` is the assistant spike's, which splices
Rasterize's `agent/` in its place.

**A copy builds through `build_app(dest, seconds, env=None,
release_only=None)`** (issue batch B88): `make app-debug` or `make app` in
`dest`, as `proof_app.config(release_only)` chooses (`RC_PROOF_APP`), under
`bounded.run`'s wall-clock bound, answering `(the copy's Frame Job.app, None)`
or `(None, reason)`: the target, its status, whether it expired, and its
first six `error:` lines (else its output's tail). A build that succeeded
prints one line with its target and its seconds.

**A built app is unregistered before its folder goes** (#223). Xcode and
`/usr/bin/open` register a `.app` with LaunchServices, and deleting the
folder leaves the registration behind. `unregister_apps(path)` runs
`lsregister -u` on every `*.app` holding `Contents/Info.plist` at or under
`path` (never descending into a found `.app`, `Intermediates.noindex`,
`node_modules` or `.git`, never following a symlink, never raising), and
`remove_tree(path)` is it followed by `shutil.rmtree`. Every proof that
deletes a folder that can hold a built `.app` deletes it through
`remove_tree`.

The selftest, in a fresh `work/tree_copy/`:

* T1 — the tree's `project.yml` names `agent`, `app`, `core`, `docs` and
  `graphic`, and neither `GENERATED` name;
* T2 — a copy's `app/` is a real directory holding `Sources/main.swift` and
  no `Info.plist` or `*.entitlements` at its top; its `agent/` is real, holds
  `build.sh` and no `node_modules`; every other input is a symlink resolving
  to the tree's; `project.yml`, `Makefile` and `VERSION` are byte-equal to the tree's;
* T3 — `agent=False` leaves no `agent`;
* T4 (CONTROL) — the tree's `project.yml` text plus a line
  `cp "$PROJECT_DIR/designs/x" "$dest/"` also names `designs`: a new input
  is seen;
* T5 — no LaunchServices effect: a fake `.app` (an `Info.plist` only) under
  `work/tree_copy/ls/` is found by `unregister_apps`, one under an
  `Intermediates.noindex/` is not, and `remove_tree` leaves nothing.

An instrument that cannot run is a FAIL, never an exit.
"""

import argparse
import filecmp
import os
import re
import shutil
import subprocess
import sys

import mcp
import proof_app

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "graphics_spike"))
import bounded  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, "tools", "proof", "work", "tree_copy")

COPIED = ("app", "agent")                      # the build writes into these, so copied
COPIED_FILES = ("project.yml", "Makefile", "VERSION")   # what `make project` reads
GENERATED = ("build", "FrameJob.xcodeproj")     # never linked


def build_inputs(project_yml=None):
    """Every top-level directory of the tree that `project_yml` (text; the
    tree's own file by default) names as `NAME/`, sorted."""
    if project_yml is None:
        with open(os.path.join(ROOT, "project.yml")) as handle:
            project_yml = handle.read()
    found = []
    for name in sorted(os.listdir(ROOT)):
        if name.startswith(".") or name in GENERATED:
            continue
        if not os.path.isdir(os.path.join(ROOT, name)):
            continue
        if re.search(r"(?<![A-Za-z0-9_.-])" + re.escape(name) + "/", project_yml):
            found.append(name)
    return found


SKIPPED_DIRS = ("Intermediates.noindex", "node_modules", ".git")


def unregister_apps(path):
    """`lsregister -u` on every directory named `*.app` holding
    `Contents/Info.plist` at or under `path`. Answers `[(app, rc)]`, `rc`
    None on a timeout or an `OSError`; never raises."""
    found = []
    try:
        path = os.fspath(path)
        if not os.path.isdir(path) or os.path.islink(path):
            return found
        candidates = []
        if path.rstrip("/").endswith(".app"):
            candidates.append(path)
        else:
            for here, dirs, _files in os.walk(path, followlinks=False):
                keep = []
                for name in dirs:
                    if name in SKIPPED_DIRS:
                        continue
                    full = os.path.join(here, name)
                    if name.endswith(".app") and not os.path.islink(full):
                        candidates.append(full)
                        continue
                    keep.append(name)
                dirs[:] = keep
        for app in candidates:
            if not os.path.isfile(os.path.join(app, "Contents", "Info.plist")):
                continue
            try:
                rc = subprocess.run([mcp.LSREGISTER, "-u", app], capture_output=True,
                                    timeout=60).returncode
            except (subprocess.TimeoutExpired, OSError):
                rc = None
            found.append((app, rc))
    except Exception:  # never raises: a removal still goes ahead
        pass
    return found


def remove_tree(path):
    """`unregister_apps(path)`, then `shutil.rmtree(path, ignore_errors=True)`."""
    unregister_apps(path)
    shutil.rmtree(path, ignore_errors=True)


def make_copy(dest, agent=True):
    """A copy of the tree at `dest` that the app builds in: `app/` (and,
    when `agent`, `agent/`) copied, `project.yml`, `Makefile` and `VERSION` copied,
    every other build input a symlink. Answers `(dest, None)` or
    `(None, reason)`."""
    try:
        remove_tree(dest)
        os.makedirs(dest)
        shutil.copytree(os.path.join(ROOT, "app"), os.path.join(dest, "app"),
                        ignore=shutil.ignore_patterns("Info.plist", "*.entitlements"))
        for one in COPIED_FILES:
            shutil.copy2(os.path.join(ROOT, one), os.path.join(dest, one))
        if agent:
            shutil.copytree(os.path.join(ROOT, "agent"), os.path.join(dest, "agent"),
                            ignore=shutil.ignore_patterns("node_modules"))
        for name in build_inputs():
            if name in COPIED:
                continue
            os.symlink(os.path.join(ROOT, name), os.path.join(dest, name))
    except OSError as error:
        return None, f"the tree copy at {dest} could not be made: {error}"
    return dest, None


def build_app(dest, seconds, env=None, release_only=None):
    """The copy's own app, built by the chosen configuration's `make` target
    in `dest`: `(bundle, None)`, or `(None, reason)`."""
    try:
        target = proof_app.MAKE_TARGET[proof_app.config(release_only)]
        app = proof_app.bundle(dest, release_only)
    except ValueError as error:
        return None, str(error)
    built = bounded.run(["make", target], seconds, cwd=str(dest), env=env)
    if built["rc"] != 0 or built["expired"] or not proof_app.executable(app).exists():
        output = built["stdout"] + built["stderr"]
        errors = [line for line in output.splitlines() if "error:" in line]
        return None, (f"make {target} rc {built['rc']} (expired {built['expired']}, "
                      f"{built['seconds']:.0f} s): "
                      + ("\n      ".join(errors[:6]) or output[-600:]))
    print(f"tree_copy: make {target} built {app} in {built['seconds']:.0f} s", flush=True)
    return app, None


def selftest():
    rows = []

    def row(ident, ok, detail):
        rows.append(ok)
        print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}")

    try:
        shutil.rmtree(WORK, ignore_errors=True)
        os.makedirs(WORK)
    except OSError as error:
        print(f"T0 FAIL — the work folder {WORK} could not be made: {error}")
        print("0/1")
        return 1

    # T1
    try:
        found = build_inputs()
        want = ["agent", "app", "core", "docs", "graphic"]
        missing = [name for name in want if name not in found]
        generated = [name for name in GENERATED if name in found]
        row("T1", not missing and not generated,
            f"inputs {found}" + (f"; missing {missing}" if missing else "")
            + (f"; generated names found {generated}" if generated else ""))
    except Exception as error:  # an instrument that cannot run is a FAIL
        row("T1", False, f"build_inputs raised {error!r}")

    # T2
    try:
        dest, reason = make_copy(os.path.join(WORK, "full"))
        if dest is None:
            row("T2", False, reason)
        else:
            problems = []
            app = os.path.join(dest, "app")
            if os.path.islink(app) or not os.path.isdir(app):
                problems.append("app/ is not a real directory")
            if not os.path.isfile(os.path.join(app, "Sources", "main.swift")):
                problems.append("app/Sources/main.swift is missing")
            top = os.listdir(app) if os.path.isdir(app) else []
            stray = [name for name in top
                     if name == "Info.plist" or name.endswith(".entitlements")]
            if stray:
                problems.append(f"app/ holds {stray}")
            agent_dir = os.path.join(dest, "agent")
            if os.path.islink(agent_dir) or not os.path.isdir(agent_dir):
                problems.append("agent/ is not a real directory")
            if not os.path.isfile(os.path.join(agent_dir, "build.sh")):
                problems.append("agent/build.sh is missing")
            if os.path.exists(os.path.join(agent_dir, "node_modules")):
                problems.append("agent/node_modules was copied")
            linked = []
            for name in build_inputs():
                if name in COPIED:
                    continue
                path = os.path.join(dest, name)
                if not os.path.islink(path):
                    problems.append(f"{name} is not a symlink")
                elif os.path.realpath(path) != os.path.realpath(os.path.join(ROOT, name)):
                    problems.append(f"{name} resolves to {os.path.realpath(path)}")
                else:
                    linked.append(name)
            for one in COPIED_FILES:
                if not filecmp.cmp(os.path.join(ROOT, one), os.path.join(dest, one),
                                   shallow=False):
                    problems.append(f"{one} differs from the tree's")
            row("T2", not problems,
                "; ".join(problems) if problems
                else f"app/ and agent/ copied, {linked} linked, {', '.join(COPIED_FILES)} equal")
    except Exception as error:
        row("T2", False, f"the copy raised {error!r}")

    # T3
    try:
        dest, reason = make_copy(os.path.join(WORK, "no-agent"), agent=False)
        if dest is None:
            row("T3", False, reason)
        else:
            present = os.path.lexists(os.path.join(dest, "agent"))
            row("T3", not present,
                "agent=False left an agent" if present else "agent=False leaves no agent")
    except Exception as error:
        row("T3", False, f"the copy raised {error!r}")

    # T4 (CONTROL)
    try:
        with open(os.path.join(ROOT, "project.yml")) as handle:
            text = handle.read()
        text += '\n          cp "$PROJECT_DIR/designs/x" "$dest/"\n'
        found = build_inputs(text)
        row("T4", "designs" in found,
            f"CONTROL: a line reading designs/ gives {found}")
    except Exception as error:
        row("T4", False, f"build_inputs raised {error!r}")

    # T5 — no LaunchServices effect: fakes that were never registered
    try:
        ls = os.path.join(WORK, "ls")
        plist = ('<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>'
                 '<key>CFBundleIdentifier</key><string>test.framejob.treecopy.t5</string>'
                 '</dict></plist>\n')
        seen = os.path.join(ls, "Seen.app")
        hidden = os.path.join(ls, "build", "Intermediates.noindex", "Hidden.app")
        for app in (seen, hidden):
            os.makedirs(os.path.join(app, "Contents"))
            with open(os.path.join(app, "Contents", "Info.plist"), "w") as handle:
                handle.write(plist)
        found = [app for app, _rc in unregister_apps(ls)]
        remove_tree(ls)
        problems = []
        if found != [seen]:
            problems.append(f"unregister_apps found {found}, wanted only {seen}")
        if os.path.lexists(ls):
            problems.append(f"remove_tree left {ls}")
        row("T5", not problems,
            "; ".join(problems) if problems
            else "the fake .app is found, the one in Intermediates.noindex is not, "
                 "and remove_tree leaves nothing")
    except Exception as error:
        row("T5", False, f"the LaunchServices row raised {error!r}")

    print(f"{sum(rows)}/{len(rows)}")
    return 0 if all(rows) else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--selftest", action="store_true",
                        help="T1–T5 in a fresh work/tree_copy/")
    arguments = parser.parse_args(argv)
    if arguments.selftest:
        return selftest()
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
