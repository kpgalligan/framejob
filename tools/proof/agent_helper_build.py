#!/usr/bin/env python3
"""Road map "swift-helper" SA3 — the Swift helper a proof runs, built by the app's own script,
`tools/agent/build_helper.sh` (spec §11 SA-8). Imported; no rows of its own.

    release(destination)               the tree's helper: PROJECT_DIR the tree, so it shares the app
                                       build's scratch path, build/agent-swift, and its stamp
    mutant(name, edits, destination)   a helper mutant: the edits applied on the persistent mutant
                                       tree, build/agent-swift-mutant/, and the script run there

Both answer `(path, detail)` — the helper, stripped and signed as the bundle's is, and what the
script did ("skipped", "built", "emptied, then built") with the seconds — or `(None, why)`.

**The mutant tree.** Never SwiftPM on a clone of the tree's scratch path (a changed `agent/`
cannot be built there, road map §13, SA0 item 9), and never an edit of the tree's own
`agent/Sources`. One tree per worktree, `build/agent-swift-mutant/`: its `agent/` is brought to
the tree's — `Package.swift`, `Package.resolved`, `Sources/` and `Tests/` (SwiftPM loads every
target the manifest declares, so the tests must be there), read through links so the kit's
`anthropic.json` is the table's bytes — by content, writing only a file that differs, so
SwiftPM's next build there is incremental; then each edit's anchor must occur exactly once in
its file, and is replaced. The script then builds on `build/agent-swift-mutant/build/agent-swift`,
cold once and in seconds after (the script's own rule empties it when it was made elsewhere, as a
lane's copy of `build/` would have). A lock (`build/agent-swift-mutant.lock`, held from the sync
until the helper is copied out) serialises two proofs building mutants at once.

Every child has both keys, `FJ_AGENT_STRICT` and `EXPANDED_CODE_SIGN_IDENTITY` popped, so the
helper is signed ad hoc; the script scrubs SwiftPM's environment itself.
"""

import fcntl
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402

SCRIPT = ROOT / "tools/agent/build_helper.sh"
MUTANT_TREE = ROOT / "build/agent-swift-mutant"
LOCK = ROOT / "build/agent-swift-mutant.lock"
SYNCED = ("Package.swift", "Package.resolved", "Sources", "Tests")
WALL = 1500  # a cold build of Slaude: SA0 measured 122–392 s under load


def child_env(project_dir):
    env = bounded.child_env()
    for key in ("ANTHROPIC_API_KEY", "FJ_AGENT_STRICT", "EXPANDED_CODE_SIGN_IDENTITY"):
        env.pop(key, None)
    env["PROJECT_DIR"] = str(project_dir)
    return env


def build(project_dir, destination):
    """The script on `project_dir`, the helper at `destination`: (path, detail) or (None, why)."""
    destination = Path(destination)
    destination.parent.mkdir(parents=True, exist_ok=True)
    ran = bounded.run(["/bin/bash", str(SCRIPT), str(destination)], WALL, cwd=str(ROOT),
                      env=child_env(project_dir))
    lines = (ran["stdout"] + ran["stderr"]).splitlines()
    said = [line[len("build_helper: "):].split(";")[0] for line in lines
            if line.startswith("build_helper: ")]
    if ran["expired"] or ran["rc"] != 0 or not destination.is_file():
        errors = [line for line in lines if "error" in line] or lines
        return None, (f"build_helper.sh exit {ran['rc']} (expired {ran['expired']}) on "
                      f"{project_dir}: {errors[-3:]}")
    return destination, f"{said[-1] if said else 'built'}, {ran['seconds']} s"


def release(destination):
    """The tree's helper, as the app build makes it."""
    return build(ROOT, destination)


def files(agent):
    """{path relative to `agent`: absolute path} for SYNCED, links followed."""
    found = {}
    for name in SYNCED:
        top = agent / name
        if top.is_file():
            found[name] = top
        elif top.is_dir():
            for path in sorted(top.rglob("*")):
                if path.is_file() and path.name != ".DS_Store":
                    found[str(path.relative_to(agent))] = path
    return found


def sync():
    """The mutant tree's `agent/` brought to the tree's, by content; the files written."""
    source, target = ROOT / "agent", MUTANT_TREE / "agent"
    want = files(source)
    written = 0
    for relative, path in want.items():
        data = path.read_bytes()
        mine = target / relative
        if mine.is_symlink() or not mine.is_file() or mine.read_bytes() != data:
            mine.parent.mkdir(parents=True, exist_ok=True)
            if mine.is_symlink():
                mine.unlink()
            mine.write_bytes(data)
            written += 1
    for relative, path in files(target).items():
        if relative not in want:
            path.unlink()
            written += 1
    return written


def mutant(name, edits, destination):
    """The helper with `edits` — `(file from the repo root, under agent/, the text there exactly
    once, its replacement)` each — built on the mutant tree: (path, detail) or (None, why)."""
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        try:
            written = sync()
            for file, anchor, replacement in edits:
                if not file.startswith("agent/"):
                    return None, f"mutant {name}: {file} is not under agent/"
                path = MUTANT_TREE / file
                text = path.read_text()
                if text.count(anchor) != 1:
                    return None, (f"mutant {name}: its anchor occurs {text.count(anchor)} times "
                                  f"in {file}")
                path.write_text(text.replace(anchor, replacement))
            helper, detail = build(MUTANT_TREE, destination)
            return helper, (f"mutant {name} on {MUTANT_TREE.relative_to(ROOT)} ({written} files "
                            f"synced): {detail}")
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)
