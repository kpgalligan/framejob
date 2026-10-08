#!/usr/bin/env python3
"""Issue batch B88 phase 2 — which app a proof drives, and the refusal to
drive one older than its sources. `tools/proof/README.md`'s "Which app a
proof drives (proof_app.py)" is the long form.

    python3 tools/proof/proof_app.py launch [--app debug|release|PATH] [-- ARG…]
    python3 tools/proof/proof_app.py check [--app debug|release|PATH]
    python3 tools/proof/proof_app.py --selftest | --mutant exe-marker|md-counted|exe-mtime-running

`RC_PROOF_APP`: `debug` (`make app-debug`, spec §11 V-4, V-5; the default
while unset), `release` (`make app`) or a `.app` or executable path. The marker of
a complete build is the bundle's `_CodeSignature/CodeResources`; there is no
override variable. Imports nothing from `tools/proof` (`mcp.py` imports it)
but in the `launch` command. A `--mutant` must fail exactly its rows:
`exe-marker` (the executable's mtime as the marker) F3 F4; `md-counted`
(every `*.md` an input) F5; `exe-mtime-running` (an instance refused when its
executable is newer than its start) R1 R2.
"""

import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "tools/proof/work/proof_app"
ENV = "RC_PROOF_APP"
DEFAULT = "debug"       # spec §11 V-4: the loop drives Debug; release_only pins Release
MAKE_TARGET = {"debug": "app-debug", "release": "app"}
DOMAINS = {"debug": "com.kgalligan.Reelcut.debug", "release": "com.kgalligan.Reelcut"}
FOLDER = {"debug": "Debug", "release": "Release"}
FOLDER_TARGET = {"Debug": "app-debug", "Release": "app", "Distribution": "dist"}
WALKED = ("app", "agent", "mcp-proxy/src", "core/src", "graphic/src")
LISTED = ("mcp-proxy/Cargo.*", "core/Cargo.*", "graphic/Cargo.*", "core/include/reelcut_core.h",
          "core/target/release/libreelcut_core.a", "docs/graphics-api.md",
          "docs/graphics-api.d.ts", "graphic/tests/graphics/*.js", "project.yml", "VERSION")
SKIPPED_DIRS = {"node_modules", "target", "build", ".git", "__pycache__"}
SKIPPED_FILES = {"app/Info.plist", "app/Reelcut.entitlements"}
KEPT_MD = "docs/graphics-api.md"
EXPECTED = {"exe-marker": {"F3", "F4"}, "md-counted": {"F5"},
            "exe-mtime-running": {"R1", "R2"}}
MUTANT = None


class StaleApp(RuntimeError):
    """A built app, or a running instance of one, older than its inputs."""


def _choice():
    """("debug" | "release", the path RC_PROOF_APP names or None)."""
    value = os.environ.get(ENV, "").strip()
    if not value or value in MAKE_TARGET:
        return value or DEFAULT, None
    if not (value.endswith(".app") or "/" in value):
        raise ValueError(f"{ENV}={value!r} is not debug, release or a .app or executable path")
    product = _product(path := Path(os.path.abspath(os.path.expanduser(value))))
    return ("debug" if product and product[1] == "Debug" else "release"), path


def config(release_only=None):
    """"debug" or "release"; Release for a `release_only` proof (a Debug path refused)."""
    chosen, path = _choice()
    if release_only is not None and path is not None and chosen == "debug":
        raise ValueError(f"{ENV}={path} is a Debug build, and this proof is Release-only: "
                         f"{release_only}")
    return chosen if release_only is None else "release"


def _bundle_of(path):
    path = Path(path)
    return path.parents[2] if path.parent.name == "MacOS" else path


def bundle(tree=ROOT, release_only=None):
    """`RC_PROOF_APP`'s path in the repo, else the chosen product under `tree`."""
    chosen, (_, path) = config(release_only), _choice()
    if path is not None and Path(tree).resolve() == ROOT:
        return _bundle_of(path)
    return Path(tree) / "build/Build/Products" / FOLDER[chosen] / "Reelcut.app"


def binary(tree=ROOT, release_only=None):
    """The chosen executable: what `require_fresh` checks before a launch."""
    _, path = _choice()
    if path is not None and Path(tree).resolve() == ROOT and path.parent.name == "MacOS":
        config(release_only)        # a Debug path is refused for a release_only proof
        return path
    return bundle(tree, release_only) / "Contents/MacOS/Reelcut"


def domain(release_only=None):
    """The chosen bundle's `CFBundleIdentifier`, else `DOMAINS[config]`."""
    try:
        with open(bundle(release_only=release_only) / "Contents/Info.plist", "rb") as handle:
            identifier = plistlib.load(handle).get("CFBundleIdentifier")
        if isinstance(identifier, str) and identifier:
            return identifier
    except (OSError, plistlib.InvalidFileException, ValueError):
        pass
    return DOMAINS[config(release_only)]


def _product(path):
    """(tree, configuration folder, bundle) of a built product's path, else None."""
    path = Path(os.path.abspath(path))
    app = _bundle_of(path)
    if app.name != "Reelcut.app" or (app != path and path.parts[-3:] != (
            "Contents", "MacOS", "Reelcut")):
        return None
    products = app.parent.parent
    if (app.parent.name not in FOLDER_TARGET or products.name != "Products"
            or products.parent.name != "Build" or products.parent.parent.name != "build"):
        return None
    return products.parent.parent.parent, app.parent.name, app


def _counted(relative):
    if relative.rsplit("/", 1)[-1].startswith(".") or relative in SKIPPED_FILES:
        return False
    return not relative.endswith(".md") or relative == KEPT_MD or MUTANT == "md-counted"


def inputs(tree):
    """Every file whose change makes a built app stale (the module doc)."""
    tree = Path(tree)
    for top in WALKED:
        for here, dirs, files in os.walk(tree / top):
            dirs[:] = sorted(d for d in dirs if d not in SKIPPED_DIRS and not d.startswith("."))
            yield from (Path(here) / name for name in sorted(files)
                        if _counted((Path(here) / name).relative_to(tree).as_posix()))
    for pattern in LISTED:
        yield from (path for path in sorted(tree.glob(pattern))
                    if path.is_file() and _counted(path.relative_to(tree).as_posix()))


def newest(tree):
    """(the newest input relative to `tree`, its mtime), or (None, 0.0)."""
    found, when = None, 0.0
    for path in inputs(tree):
        try:
            mtime = path.stat().st_mtime
        except OSError:
            continue
        if mtime > when:
            found, when = path.relative_to(tree).as_posix(), mtime
    return found, when


def _when(seconds):
    return time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(seconds))


def _stale(path):
    """The refusal for a product path, or None (fresh, or not a product)."""
    if (product := _product(path)) is None:
        return None
    tree, folder, app = product
    exe, target = app / "Contents/MacOS/Reelcut", FOLDER_TARGET[folder]
    marker = exe if MUTANT == "exe-marker" else app / "Contents/_CodeSignature/CodeResources"
    try:
        built = marker.stat().st_mtime
    except OSError:
        return (f"refusing {exe}: no complete build ({app}/Contents/_CodeSignature/CodeResources "
                f"is missing); rebuild with `make {target}`")
    found, when = newest(tree)
    if found is not None and when > built:
        return (f"refusing {exe}: {found} (modified {_when(when)}) is newer than its last "
                f"complete build ({_when(built)}); rebuild with `make {target}`")
    return None


def require_fresh(path):
    """Raises `StaleApp` for a product with no complete build since its newest input."""
    if reason := _stale(path):
        raise StaleApp(reason)


def running_verdict(started, executable, pid=None):
    """The refusal of an instance started (whole epoch seconds) before the
    newest input, else `require_fresh`'s; never by the executable's mtime."""
    if (product := _product(executable)) is None:
        return None
    tree, folder, _app = product
    found, when = newest(tree)
    if MUTANT == "exe-mtime-running":
        found, when = "its executable", Path(executable).stat().st_mtime
    if found is not None and int(when) > started:
        return (f"relaunch pid {pid} after `make {FOLDER_TARGET[folder]}`: {found} (modified "
                f"{_when(when)}) is newer than the instance (started {_when(started)})")
    return _stale(executable)


def _instance(pid):
    """(its executable, its start in epoch seconds), or None."""
    try:
        listed = subprocess.run(["lsof", "-p", str(pid), "-a", "-d", "txt", "-Fn"],
                                capture_output=True, text=True, timeout=30)
        names = [line[1:] for line in listed.stdout.splitlines() if line.startswith("n")]
        began = subprocess.run(["ps", "-o", "lstart=", "-p", str(pid)], capture_output=True,
                               text=True, timeout=30, env={**os.environ, "LC_ALL": "C"})
        stamp = " ".join(began.stdout.split())
        if names and stamp:
            return Path(names[0]), time.mktime(time.strptime(stamp, "%a %b %d %H:%M:%S %Y"))
    except (OSError, subprocess.TimeoutExpired, ValueError):
        pass
    return None


def require_running_fresh(pid):
    """`running_verdict` as `StaleApp`; one stderr line if `lsof`/`ps` cannot say."""
    if (seen := _instance(pid)) is None:
        sys.stderr.write(f"proof_app: could not read pid {pid}'s executable or start; its "
                         "freshness is not checked\n")
    elif reason := running_verdict(seen[1], seen[0], pid=pid):
        raise StaleApp(reason)


BASE = float(int(time.time()) - 10000)


def _tree(name, folder="Debug", marker=True, exe=100, built=100, newer=()):
    """Inputs at BASE, skipped files at +500, the exe and marker, then `newer`."""
    files = {"app/Sources/a.swift": 0, "app/CLAUDE.md": 0, "docs/graphics-api.md": 0,
             "project.yml": 0, "agent/src/x.ts": 0, "core/target/release/libreelcut_core.a": 0,
             "agent/node_modules/y.js": 500, "app/Info.plist": 500, "app/.DS_Store": 500,
             "app/Reelcut.entitlements": 500, "core/target/debug/z.o": 500, "README.md": 500}
    app = WORK / name / "build/Build/Products" / folder / "Reelcut.app"
    stamps = {**{WORK / name / one: when for one, when in {**files, **dict(newer)}.items()},
              app / "Contents/MacOS/Reelcut": exe}
    if marker:
        stamps[app / "Contents/_CodeSignature/CodeResources"] = built
    for path, when in stamps.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x\n")
        os.utime(path, (BASE + when, BASE + when))
    return app


def selftest(mutant=None):
    global MUTANT
    MUTANT, saved, results = mutant, os.environ.get(ENV), []
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)

    def row(name, ok, detail):
        results.append((name, bool(ok)))
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)

    def refusal(path):
        try:
            return require_fresh(path)
        except StaleApp as error:
            return str(error)

    def chosen(value, call, *more, **options):
        os.environ.pop(ENV, None) if value is None else os.environ.__setitem__(ENV, str(value))
        try:
            return call(*more, **options)
        except ValueError as error:
            return f"ValueError: {error}"

    try:
        said = refusal(_tree("fresh") / "Contents/MacOS/Reelcut")
        row("F1", said is None and refusal(WORK / "fresh/build/Build/Products/Debug/Reelcut.app")
            is None, f"fresh, with node_modules, Info.plist, a dot-file, target/ newer: {said}")
        said = refusal(_tree("stale", newer=[("app/Sources/a.swift", 200)])) or ""
        row("F2", f"app/Sources/a.swift (modified {_when(BASE + 200)}) is newer than its last "
            f"complete build ({_when(BASE + 100)}); rebuild with `make app-debug`" in said, said)
        said = refusal(_tree("nomarker", marker=False)) or ""
        row("F3", "no complete build" in said and said.endswith(
            "_CodeSignature/CodeResources is missing); rebuild with `make app-debug`"), said)
        said = refusal(_tree("failed-helper", built=-10, newer=[("agent/src/x.ts", 50)])) or ""
        row("F4", f"agent/src/x.ts (modified {_when(BASE + 50)})" in said,
            f"executable newer than the input, marker older: {said}")
        said = refusal(_tree("claude-md", newer=[("app/CLAUDE.md", 200)]))
        row("F5", said is None, f"an app/CLAUDE.md newer than the marker: {said}")
        said = refusal(_tree("api-md", newer=[("docs/graphics-api.md", 200)])) or ""
        row("F6", "docs/graphics-api.md (modified" in said, said)

        exe = _tree("running", exe=300, built=300) / "Contents/MacOS/Reelcut"
        said = running_verdict(BASE + 200, exe, pid=4242)
        row("R1", said is None, f"started after the newest input, rewritten since: {said}")
        exe = _tree("relaunch", exe=300, built=300, newer=[("app/Sources/a.swift", 250)])
        said = running_verdict(BASE + 200, exe / "Contents/MacOS/Reelcut", pid=4242) or ""
        row("R2", said == "relaunch pid 4242 after `make app-debug`: app/Sources/a.swift "
            f"(modified {_when(BASE + 250)}) is newer than the instance (started "
            f"{_when(BASE + 200)})", said)
        exe = _tree("running-stale", newer=[("app/Sources/a.swift", 250)])
        said = running_verdict(BASE + 300, exe / "Contents/MacOS/Reelcut", pid=4242) or ""
        row("R3", said.startswith("refusing "), f"started after the input, product stale: {said}")

        named = {one: refusal(_tree(f"target-{one}", folder=one, newer=[("project.yml", 200)]))
                 for one in ("Release", "Distribution")}
        row("T1", MAKE_TARGET == {"debug": "app-debug", "release": "app"}
            and str(named["Release"]).endswith("`make app`")
            and str(named["Distribution"]).endswith("`make dist`"), f"{MAKE_TARGET}; {named}")

        debug_app = WORK / "stale/build/Build/Products/Debug/Reelcut.app"
        release_app = WORK / "target-Release/build/Build/Products/Release/Reelcut.app"
        products = ROOT / "build/Build/Products"
        exe = debug_app / "Contents/MacOS/Reelcut"
        cases = [("unset", (None, config), DEFAULT),
                 ("debug", ("debug", bundle), products / "Debug/Reelcut.app"),
                 ("release", ("release", binary),
                  products / "Release" / exe.relative_to(debug_app.parent)),
                 ("a Debug .app", (debug_app, config), "debug"),
                 ("its bundle", (debug_app, bundle), debug_app),
                 ("its executable", (exe, binary), exe),
                 ("a tree copy", ("debug", bundle, WORK / "copy"),
                  WORK / "copy/build/Build/Products/Debug/Reelcut.app"),
                 ("bogus", ("bogus", config), "ValueError: RC_PROOF_APP='bogus' is not debug, "
                  "release or a .app or executable path")]
        wrong = {name: got for name, call, want in cases if (got := chosen(*call)) != want}
        row("E1", not wrong, f"{ENV} parsed; wrong: {wrong or 'none'}")
        why = {"release_only": "needs a grant"}
        seen = {"debug": chosen("debug", bundle, **why), "a Debug path": chosen(debug_app, bundle,
                **why), "a Release path": chosen(release_app, bundle, **why)}
        row("E2", seen["debug"] == products / "Release/Reelcut.app"
            and str(seen["a Debug path"]).endswith("Release-only: needs a grant")
            and seen["a Release path"] == release_app, f"release_only: {seen}")

        with open(release_app / "Contents/Info.plist", "wb") as handle:
            plistlib.dump({"CFBundleIdentifier": "com.example.proof-app"}, handle)
        seen = (chosen(release_app, domain), chosen(debug_app, domain))
        row("D1", seen == ("com.example.proof-app", DOMAINS["debug"]),
            f"read from Info.plist, else DOMAINS: {seen}")
        declared = re.findall(r"^\s*PRODUCT_BUNDLE_IDENTIFIER:\s*(\S+)\s*$",
                              (ROOT / "project.yml").read_text(), re.M)
        row("D2", declared == [DOMAINS["debug"]], f"project.yml's bundle identifiers {declared}")

        loose = WORK / "loose/Reelcut.app"
        shutil.copytree(debug_app, loose)
        row("C1", refusal(loose) is None and running_verdict(0, loose / "Contents/MacOS/Reelcut")
            is None and _product("/Applications/Reelcut.app/Contents/MacOS/Reelcut") is None,
            "CONTROL: a stale copy outside build/Build/Products, and /Applications', not checked")
    finally:
        os.environ.pop(ENV, None) if saved is None else os.environ.__setitem__(ENV, saved)
    failed = {name for name, ok in results if not ok}
    print(f"{len(results) - len(failed)}/{len(results)} rows pass")
    ok = failed == EXPECTED[mutant] if mutant else not failed
    print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
          f"{sorted(EXPECTED[mutant])}" if mutant else "PASS" if ok else "FAIL")
    return 0 if ok else 1


def _launch(arguments):
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import mcp  # noqa: E402 — the launch command alone imports it (mcp imports this module)

    require_fresh(exe := binary())
    socket_path = mcp.scratch_socket()
    folder = os.path.dirname(socket_path)
    os.makedirs(os.path.join(folder, "home"))
    env = {**mcp._child_env(), "CFFIXED_USER_HOME": os.path.join(folder, "home")}
    started = mcp.launch(exe, arguments, env=env, socket_path=socket_path, seconds=60)
    if started.client is None:
        started.stop()
        print(f"proof_app: {exe} did not listen at {socket_path} within 60 s; its log is "
              f"{started.log_path}", file=sys.stderr)
        return 1
    print(f"folder {folder}\nsocket {socket_path}\nlog {started.log_path}\n"
          f"pid {started.child.pid}")
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    passed = argv[argv.index("--") + 1:] if "--" in argv else []
    argv = argv[:argv.index("--")] if "--" in argv else argv
    parser = argparse.ArgumentParser(description="which app a proof drives (B88)")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    parser.add_argument("command", nargs="?", choices=("launch", "check"))
    parser.add_argument("--app", help="debug, release or a .app or executable path")
    args = parser.parse_args(argv)
    if args.selftest or args.mutant:
        return selftest(args.mutant)
    if args.app:
        os.environ[ENV] = args.app
    try:
        if args.command == "launch":
            return _launch(passed)
        if args.command == "check":
            require_fresh(exe := binary())
            print(f"fresh: {exe}" if _product(exe) else f"{exe} is not a built product: unchecked")
            return 0
    except (StaleApp, ValueError) as error:
        print(f"proof_app: {error}", file=sys.stderr)
        return 1
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
