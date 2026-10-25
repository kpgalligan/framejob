#!/usr/bin/env python3
"""Issue batch B88 phase 4 — `make gate`, the one Full verification command.
`tools/proof/README.md`'s "The gate (gate.py)" is the long form.

    python3 tools/proof/gate.py [--force] [--wait SECONDS]
    python3 tools/proof/gate.py --selftest | --mutant no-tools|stamp-always|md-counted|warning-count

Six steps, serially, stopping at the first failure: `names`
(`name_residue.py`, spec §11 NM-8: no line or path spells the old name
outside its allow-list; every file is its input, `*.md` included), `typecheck` (`make
typecheck`, passing only with no `error:` and exactly TYPECHECK_BASELINE's
warnings, by file and message), `fmt` (`cargo fmt --check` in core, graphic,
mcp-proxy), `lint` (`make lint`), `test` (`make test`) and `app` (`make app`,
then dist_check's D25 and D26 over the Release app: its entitlements and its
seal, the defect a no-op build once shipped and only `make dist` read).

A step is skipped when its hash equals its last pass. The hash is sha256
over the content of the step's own files among `git ls-files -co
--exclude-standard` (STEP_INPUTS; `gate.py` and the `Makefile` in every
step) and a tool fingerprint (TOOLS' output). It is taken before the step and
again after it, and the pass is stamped only when the two are equal, so a
step whose inputs changed while it ran runs again next time. Writes go only
under `build/gate/`: `lock`, `state.json`, `<step>.log`, `times.tsv`. Exit 0
PASS, 1 FAIL, 3 BLOCKED (another gate holds the lock past `--wait`).

A `--mutant` runs the selftest alone and must fail exactly its rows:
`no-tools` (the fingerprint left out of the hash) H2; `stamp-always` (a pass
stamped with unequal hashes) H3; `md-counted` (every `*.md` an input) M4 M5
M6; `warning-count` (warnings compared by count, not file and message) W2.
"""

import argparse
import collections
import fcntl
import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = "tools/proof/gate.py"
GATE = ROOT / "build/gate"
ALWAYS = (HERE, "Makefile")
STEPS = ("names", "typecheck", "fmt", "lint", "test", "app")
BOUNDS = {"names": 120, "typecheck": 300, "fmt": 120, "lint": 600, "test": 900, "app": 1500}
COMMANDS = {
    "names": [["python3", "tools/proof/name_residue.py"]],
    "typecheck": [["make", "typecheck"]],
    "fmt": [["cargo", "fmt", "--check"]] * 3,
    "lint": [["make", "lint"]],
    "test": [["make", "test"]],
    "app": [["make", "app"]],
}
FOLDERS = {"fmt": ("core", "graphic", "mcp-proxy")}
# The step's own files: folders and files, then which `*.md` count (none, unless named).
STEP_INPUTS = {
    "names": (("",), ("",)),
    "typecheck": (("app/Sources", "app/Bridging", "core/include", "agent"), ()),
    "fmt": (("core", "graphic", "mcp-proxy"), ()),
    "lint": (("core", "graphic", "mcp-proxy"), ()),
    "test": (("",), ("designs/spec/", "docs/")),
    "app": (("app", "agent", "core", "graphic", "mcp-proxy", "project.yml", "VERSION",
             "docs/graphics-api.md", "docs/graphics-api.d.ts", "tools/proof/dist_check.py"),
            ("docs/graphics-api.md",)),
}
EXCLUDED = ("archive/", ".secrets/")
TOOLS = (["xcrun", "swiftc", "--version"], ["xcodebuild", "-version"],
         ["xcrun", "--show-sdk-path"], ["rustc", "-Vv"], ["cargo", "clippy", "-V"],
         ["bun", "--version"], ["xcodegen", "--version"], ["cargo", "fmt", "--version"])
# `make typecheck`'s warnings at HEAD 0b380d2, verbatim (CLAUDE.md: "0 errors and 4 warnings",
# deliberate, spec §11 W-8): (file basename, message). A fifth, or one gone, fails the step.
TYPECHECK_BASELINE = (
    ("Exporter.swift", "'copyCGImage(at:actualTime:)' was deprecated in macOS 15.0: Use "
     "generateCGImageAsynchronouslyForTime:completionHandler: instead [#DeprecatedDeclaration]"),
    ("CompositionBuilder.swift", "'tracks(withMediaType:)' was deprecated in macOS 13.0: Use "
     "loadTracks(withMediaType:) instead [#DeprecatedDeclaration]"),
    ("CompositionBuilder.swift", "'timeRange' was deprecated in macOS 13.0: Use "
     "load(.timeRange) instead [#DeprecatedDeclaration]"),
    ("CompositionBuilder+Orientation.swift", "'preferredTransform' was deprecated in macOS 13.0: Use "
     "load(.preferredTransform) instead [#DeprecatedDeclaration]"),
)
DIAGNOSTIC = re.compile(r"^(?P<path>[^\s:][^:]*):\d+(?::\d+)?: (?P<kind>warning|error): (?P<msg>.*)$")
ERROR_LINE = re.compile(r"^(?!\s*(?:PASS|ok)\b).*(?:error:|error\[|FAILED|(?:^|\s)FAIL\b|panicked"
                        r"|Fatal error|\*\*\*)")
EXPECTED = {"no-tools": {"H2"}, "stamp-always": {"H3"}, "md-counted": {"M4", "M5", "M6"},
            "warning-count": {"W2"}}
MUTANT = None


def wants(step, path):
    """Whether `path` (ROOT-relative, `/`-separated) is one of the step's inputs."""
    if path in ALWAYS:
        return True
    if path.startswith(EXCLUDED):
        return False
    roots, kept_md = STEP_INPUTS[step]
    if path.endswith(".md") and not path.startswith(kept_md) and MUTANT != "md-counted":
        return False
    return any(root == "" or path == root or path.startswith(root + "/") for root in roots)


def step_hash(step, digests, tools):
    """sha256 over the step's files' (path, digest) and the tool fingerprint."""
    files = [[path, digests[path]] for path in sorted(digests) if wants(step, path)]
    document = {"step": step, "files": files}
    if MUTANT != "no-tools":
        document["tools"] = tools
    return hashlib.sha256(json.dumps(document, sort_keys=True).encode()).hexdigest()


def record(state, step, before, after):
    """Stamp the pass only when the inputs did not change while the step ran."""
    if before != after and MUTANT != "stamp-always":
        return False
    state[step] = before
    return True


def typecheck_verdict(text, returncode):
    """None when the log is a clean typecheck, else the lines that say why not."""
    found, errors = [], []
    for line in text.splitlines():
        match = DIAGNOSTIC.match(line)
        if match and match["kind"] == "error":
            errors.append(line)
        elif match:
            found.append((os.path.basename(match["path"]), match["msg"]))
    if MUTANT == "warning-count":
        same = len(found) == len(TYPECHECK_BASELINE)
    else:
        same = collections.Counter(found) == collections.Counter(TYPECHECK_BASELINE)
    if returncode == 0 and not errors and same:
        return None
    lines = errors[:5] or ([] if returncode == 0 else [f"make typecheck exit {returncode}"])
    if not same:
        extra = collections.Counter(found) - collections.Counter(TYPECHECK_BASELINE)
        gone = collections.Counter(TYPECHECK_BASELINE) - collections.Counter(found)
        lines += [f"new warning: {name}: {message}" for name, message in extra.elements()]
        lines += [f"baseline warning gone: {name}: {message}" for name, message in gone.elements()]
    return lines[:4] + [f"see build/gate/typecheck.log; the baseline is TYPECHECK_BASELINE in {HERE}"]


def tree_digests():
    """{path: sha256 of its content} over `git ls-files -co --exclude-standard`."""
    listed = subprocess.run(["git", "ls-files", "-co", "--exclude-standard", "-z"], cwd=ROOT,
                            capture_output=True, check=True).stdout.decode().split("\0")
    digests = {}
    for path in filter(None, listed):
        if path.startswith(".secrets/"):
            continue
        full = ROOT / path
        try:
            if full.is_symlink():
                digests[path] = "link:" + os.readlink(full)
            else:
                digests[path] = hashlib.sha256(full.read_bytes()).hexdigest()
        except OSError as error:
            digests[path] = f"unreadable: {error.strerror}"
    return digests


def fingerprint():
    out = []
    for argv in TOOLS:
        try:
            done = subprocess.run(argv, cwd=ROOT, capture_output=True, text=True, timeout=60)
            out.append(f"$ {' '.join(argv)} (exit {done.returncode})\n{done.stdout}{done.stderr}")
        except (OSError, subprocess.TimeoutExpired) as error:
            out.append(f"$ {' '.join(argv)}: {type(error).__name__}")
    return "\n".join(out)


def child_env():
    keys = ("ANTHROPIC_API_KEY", "RC_ASSEMBLYAI_KEY")
    return {k: v for k, v in os.environ.items() if k not in keys}


def run_step(step, log):
    """(ok, the lines that say why not) for one step, its output in `log`; bounded."""
    deadline = time.monotonic() + BOUNDS[step]
    for index, argv in enumerate(COMMANDS[step]):
        cwd = ROOT / FOLDERS[step][index] if step in FOLDERS else ROOT
        log.write(f"$ (cd {cwd.relative_to(ROOT) or '.'}) {' '.join(argv)}\n")
        log.flush()
        child = subprocess.Popen(argv, cwd=cwd, env=child_env(), stdin=subprocess.DEVNULL,
                                 stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            child.wait(timeout=max(1.0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            os.killpg(child.pid, signal.SIGKILL)
            child.wait()
            return False, [f"ran past its {BOUNDS[step]} s bound"]
        finally:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
        if step == "typecheck":
            log.flush()
            why = typecheck_verdict(Path(log.name).read_text(errors="replace"), child.returncode)
            return why is None, why or []
        if child.returncode != 0:
            log.flush()
            text = Path(log.name).read_text(errors="replace").splitlines()
            lines = [line for line in text if ERROR_LINE.search(line)][:5] or text[-5:]
            return False, lines
    return release_signature(log) if step == "app" else (True, [])


def release_signature(log):
    """dist_check's D25 and D26 over the Release app `make app` just built."""
    sys.path.insert(0, str(ROOT / "tools/proof"))
    import dist_check  # noqa: E402 — the app step alone reads it
    import proof_app  # noqa: E402

    exe = str(proof_app.executable(dist_check.DEFAULT_RELEASE))
    rows = (("D25 the Release app's entitlements are exactly audio-input and get-task-allow",
             dist_check.entitlements(os.path.realpath(exe), dist_check.RELEASE_ENTITLEMENTS)),
            ("D26 the Release app passes codesign --verify --deep --strict",
             dist_check.sealed(exe)))
    failed = []
    for name, (ok, detail) in rows:
        log.write(f"gate: {'ok  ' if ok else 'FAIL'} {name}{'' if ok else ': ' + detail}\n")
        if not ok:
            failed.append(f"{name}: {detail}")
    return not failed, failed


def take_lock(wait):
    GATE.mkdir(parents=True, exist_ok=True)
    handle = open(GATE / "lock", "w")
    deadline = time.monotonic() + wait
    while True:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return handle
        except BlockingIOError:
            if time.monotonic() >= deadline:
                handle.close()
                return None
            time.sleep(0.5)


def commit_label():
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip() or "none"
    dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                           capture_output=True, text=True).stdout.strip()
    return head + ("-dirty" if dirty else "")


def gate(force, wait):
    for sig in (signal.SIGTERM, signal.SIGHUP):  # through run_step's finally: kill the group
        signal.signal(sig, lambda n, _f: sys.exit(128 + n))
    started = time.monotonic()
    lock = take_lock(wait)
    if lock is None:
        print("gate: BLOCKED (build/gate/lock)", flush=True)
        return 3
    state_path = GATE / "state.json"
    try:
        state = json.loads(state_path.read_text())
    except (OSError, ValueError):
        state = {}
    commit, unstamped = commit_label(), []
    tools, digests = fingerprint(), tree_digests()
    with open(GATE / "times.tsv", "a") as times:
        for step in STEPS:
            begun = time.monotonic()
            before = step_hash(step, digests, tools)
            if not force and state.get(step) == before:
                result = "skip"
                print(f"gate: {step} skip {time.monotonic() - begun:.0f}s", flush=True)
            else:
                with open(GATE / f"{step}.log", "w") as log:
                    ok, why = run_step(step, log)
                tools, digests = fingerprint(), tree_digests()
                after = step_hash(step, digests, tools)
                result = "pass" if ok else "FAIL"
                print(f"gate: {step} {result} {time.monotonic() - begun:.0f}s", flush=True)
                for line in why[:5]:
                    print(f"    {line.strip()[:300]}", flush=True)
                if ok and record(state, step, before, after):
                    tmp = state_path.with_suffix(f".tmp-{os.getpid()}")
                    tmp.write_text(json.dumps(state, indent=1, sort_keys=True))
                    os.replace(tmp, state_path)
                elif ok:
                    unstamped.append(step)
                    result = "pass-unstamped"
                    print(f"gate: {step} pass, not stamped: its inputs changed while it ran",
                          flush=True)
            utc = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            times.write(f"{utc}\t{commit}\t{step}\t{time.monotonic() - begun:.1f}\t{result}\n")
            times.flush()
            if result == "FAIL":
                print(f"gate: FAIL {step} {time.monotonic() - started:.0f}s", flush=True)
                return 1
    tail = f" (not stamped: {', '.join(unstamped)})" if unstamped else ""
    print(f"gate: PASS {time.monotonic() - started:.0f}s{tail}", flush=True)
    return 0


def selftest(mutant=None):
    global MUTANT
    MUTANT, results = mutant, []

    def row(name, ok, detail):
        results.append((name, bool(ok)))
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)

    # One file of each input class, and the steps a substituted digest must move.
    every = set(STEPS)
    classes = [
        ("M1", "app/Sources/Clip.swift", {"names", "typecheck", "test", "app"}),
        ("M1", "app/Bridging/x.h", {"names", "typecheck", "test", "app"}),
        ("M1", "core/include/framejob_core.h", every),
        ("M1", "agent/src/agent.ts", {"names", "typecheck", "test", "app"}),
        ("M2", "core/src/lib.rs", {"names", "fmt", "lint", "test", "app"}),
        ("M2", "graphic/src/lib.rs", {"names", "fmt", "lint", "test", "app"}),
        ("M2", "mcp-proxy/Cargo.toml", {"names", "fmt", "lint", "test", "app"}),
        ("M3", "project.yml", {"names", "test", "app"}),
        ("M3", "VERSION", {"names", "test", "app"}),
        ("M3", "app/Resources/Shaders/Compositor.metal", {"names", "test", "app"}),
        ("M3", "docs/graphics-api.md", {"names", "test", "app"}),
        ("M3", "docs/graphics-api.d.ts", {"names", "test", "app"}),
        ("M3", "tools/proof/dist_check.py", {"names", "test", "app"}),
        ("M3", "tools/proof/mcp.py", {"names", "test"}),
        ("M3", "designs/spec/x.md", {"names", "test"}),
        ("M3", "docs/manual-checks.md", {"names", "test"}),
        ("M4", "archive/x.md", set()),
        ("M4", "archive/x.py", set()),
        ("M4", "README.md", {"names"}),
        ("M5", "core/CLAUDE.md", {"names"}),
        ("M5", "app/CLAUDE.md", {"names"}),
        ("M6", "designs/adr/x.md", {"names"}),
        ("M7", HERE, every),
        ("M7", "Makefile", every),
    ]
    base = {path: "0" * 64 for _, path, _ in classes}
    hashes = {step: step_hash(step, base, "tools") for step in STEPS}
    again = {step: step_hash(step, dict(base), "tools") for step in STEPS}
    state = {}
    stamped = all(record(state, step, hashes[step], again[step]) for step in STEPS)
    row("H0", hashes == again and stamped and state == hashes,
        "CONTROL: identical digests give identical hashes, and every step is stamped")
    for name, path, expected in classes:
        changed = dict(base, **{path: "1" * 64})
        moved = {step for step in STEPS if step_hash(step, changed, "tools") != hashes[step]}
        row(name, moved == expected, f"{path} moves {sorted(moved)}, expected {sorted(expected)}")
    moved = {step for step in STEPS if step_hash(step, base, "tools 2") != hashes[step]}
    row("H2", moved == every, f"a substituted tool string moves {sorted(moved)}")
    state = {"test": "old"}
    stamped = record(state, "test", hashes["test"], hashes["app"])
    row("H3", not stamped and state == {"test": "old"}, "unequal hashes record no pass")
    row("H4", all(step_hash(step, dict(base, **{".secrets/x": "2"}), "tools") == hashes[step]
                  for step in STEPS),
        "CONTROL: a .secrets/ path is in no step's inputs")

    def log(pairs, extra=""):
        lines = []
        for index, (name, message) in enumerate(pairs):
            lines += [f"app/Sources/{name}:{100 + index}:9: warning: {message}",
                      f"    |    `- warning: {message}"]
        return "\n".join(lines) + extra + "\n$ tsc --noEmit\n"

    row("W0", typecheck_verdict(log(TYPECHECK_BASELINE), 0) is None,
        "CONTROL: the four baseline warnings, at any line, each with its caret line, pass")
    fifth = TYPECHECK_BASELINE + (("Clip.swift", "'x' was deprecated"),)
    why = typecheck_verdict(log(fifth), 0)
    row("W1", why is not None and any("Clip.swift" in line for line in why),
        f"a fifth warning fails, named: {why}")
    moved_file = (("Clip.swift", TYPECHECK_BASELINE[0][1]),) + TYPECHECK_BASELINE[1:]
    why = typecheck_verdict(log(moved_file), 0)
    row("W2", why is not None, f"a baseline warning in another file fails: {why}")
    why = typecheck_verdict(log(TYPECHECK_BASELINE[1:]), 0)
    row("W3", why is not None, f"a baseline warning gone fails: {why}")
    why = typecheck_verdict(log(TYPECHECK_BASELINE, "\napp/Sources/A.swift:1:1: error: nope"), 1)
    row("W4", why is not None and "error: nope" in why[0], f"an error fails, first: {why}")

    failed = {name for name, ok in results if not ok}
    print(f"{len(results) - len(failed)}/{len(results)} rows pass")
    ok = failed == EXPECTED[mutant] if mutant else not failed
    print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
          f"{sorted(EXPECTED[mutant])}" if mutant else "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description="make gate (B88 phase 4)")
    parser.add_argument("--force", action="store_true", help="run every step")
    parser.add_argument("--wait", type=float, default=120.0,
                        help="seconds to wait for another gate's lock (default 120)")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    args = parser.parse_args(argv)
    if args.selftest or args.mutant:
        return selftest(args.mutant)
    return gate(args.force, args.wait)


if __name__ == "__main__":
    sys.exit(main())
