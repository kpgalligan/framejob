#!/usr/bin/env python3
"""The probe builder (issue batch B88 phase 1a): the ONE swiftc line a proof,
a probe or the offscreen harness compiles app sources with, and its cache.

    python3 tools/proof/swift_build.py build --output PATH [--define D]… [--force] SOURCE…
    python3 tools/proof/swift_build.py typecheck [--define D]… [--sources DIR] PROBE.swift…
    python3 tools/proof/swift_build.py --selftest

`build()` compiles on every core (`-j <cores>`, or `-whole-module-optimization`)
into `work/swift-build/<key>/`. The key hashes this file, `swiftc --version`, the
SDK and its `SDKSettings.json`, the argv less its `-o`/`-j` values, the output's
file name (linked under it: the signature's identifier), the bytes of
every source, of the bridging header and each header it reaches by a quoted
`#include`, of the staticlib, the two encoder archives and their stamp
(`build/codecs/`, spec §11 CX-4: every app build links them, `codec_args()`) and each
link input, four toolchain variables and the tree's path (`#file` embeds it). An entry is reused only when its binary still
hashes to its manifest's digest, and is delivered to the caller's own path and
name (a bare binary's defaults domain and `proof_defaults.py --ran` are that name).
Every child runs under `bounded.run`, in its own process group; README: the selftest.
"""

import argparse
import contextlib
import fnmatch
import hashlib
import json
import os
import re
import shutil
import sys
import tempfile
import time
from pathlib import Path
from typing import NamedTuple, Sequence

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402

CACHE = ROOT / "tools/proof/work/swift-build"
KEEP_ENTRIES = 32
BRIDGING = ROOT / "app/Bridging/FrameJob-Bridging-Header.h"
LIBRARY = ROOT / "core/target/release/libframejob_core.a"
# The bundled encoders (road map "codec-export" C0): `make codecs` installs them, and
# every swiftc line that compiles app/Sources finds their headers and links them.
CODECS = ROOT / "build/codecs"
CODEC_ARCHIVES = (CODECS / "lib/libSvtAv1Enc.a", CODECS / "lib/libvpx.a")
CODEC_STAMP = CODECS / "stamp.json"
TARGET = "arm64-apple-macos26.0"
ENV_KEYS = ("DEVELOPER_DIR", "SDKROOT", "TOOLCHAINS", "MACOSX_DEPLOYMENT_TARGET")
STRIPPED = ("-o", "-j", "-output-file-map")  # flags whose VALUES the key ignores
INCLUDE = re.compile(r'^\s*#\s*include\s+"([^"]+)"', re.M)


class SwiftBuildFailed(RuntimeError):
    """`.diagnostics` (≤12 `error:` lines, else the tail), `.log` (None when nothing
    ran), `.expired` (the wall bound killed it), `.rc` (swiftc's status, or None)."""

    def __init__(self, message, diagnostics=(), log=None, expired=False, rc=None):
        super().__init__(message)
        self.diagnostics = list(diagnostics) or [message]
        self.log = log
        self.expired = expired
        self.rc = rc


class Built(NamedTuple):
    binary: Path
    key: str
    reused: bool
    seconds: float


def app_sources(folder=None):
    """Every `*.swift` in `folder` (default `app/Sources`) but `main.swift`, sorted."""
    folder = Path(folder) if folder is not None else ROOT / "app/Sources"
    return sorted(p for p in folder.iterdir() if p.suffix == ".swift" and p.name != "main.swift")


def _sha(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def _label(path):
    path = Path(path).resolve()
    return str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path)


_TOOLS = {}


def _tools():
    """swiftc's version and the SDK, read once per process."""
    if not _TOOLS:
        version = bounded.run(["xcrun", "swiftc", "--version"], 60)
        sdk = bounded.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], 60)
        if version["rc"] != 0 or sdk["rc"] != 0 or not sdk["stdout"].strip():
            raise SwiftBuildFailed("swift_build: xcrun failed: "
                                   + (version["stderr"] + sdk["stderr"]).strip()[-300:])
        path = sdk["stdout"].strip()
        settings = Path(path) / "SDKSettings.json"
        _TOOLS.update(swiftc=(version["stdout"] + version["stderr"]).strip(), sdk=path,
                      sdk_settings=_sha(settings) if settings.exists() else None)
    return _TOOLS


def _headers(header):
    """The bridging header and every file it reaches by a quoted #include."""
    seen, queue = [], [Path(header).resolve()]
    while queue:
        path = queue.pop(0)
        if path in seen or not path.exists():
            continue
        seen.append(path)
        for name in INCLUDE.findall(path.read_text(errors="replace")):
            queue.append((path.parent / name).resolve())
    return seen


def codec_args():
    """The encoders' header path and archives, for any swiftc line over app/Sources."""
    return ["-Xcc", f"-I{CODECS}/include", *map(str, CODEC_ARCHIVES)]


def _argv(*, sources, output, defines=(), optimize=False, wmo=False, link_args=(),
          bridging_header=None, library=None, jobs=None):
    """The one place the line is spelled."""
    bridging = Path(bridging_header or BRIDGING)
    library = Path(library or LIBRARY)
    argv = ["xcrun", "swiftc"] + [x for d in defines for x in ("-D", d)] + ["-O"] * optimize
    argv += ["-whole-module-optimization"] if wmo else ["-j", str(jobs or os.cpu_count())]
    argv += ["-sdk", _tools()["sdk"], "-target", TARGET, "-module-name", "FrameJob",
             "-import-objc-header", str(bridging), "-L", str(library.parent), "-lframejob_core"]
    argv += codec_args()
    argv += [str(s) for s in sources] + [str(a) for a in link_args] + ["-o", str(output)]
    return argv


def _key(argv, files, output):
    """sha256 (16 hex) of the key document: `argv` less the values of STRIPPED,
    `files` hashed by content, and `output`'s file name — the linker signs the binary
    with that name as its identifier, which LaunchServices keys a bare binary by."""
    kept = [_label(a) if a.startswith(str(ROOT)) else a for i, a in enumerate(argv)
            if a not in STRIPPED and (i == 0 or argv[i - 1] not in STRIPPED)]
    tools = _tools()
    document = {"helper": _sha(__file__), "swiftc": tools["swiftc"], "sdk": tools["sdk"],
                "sdk_settings": tools["sdk_settings"], "argv": kept, "root": str(ROOT),
                "name": Path(output).name,
                "files": [[_label(f), _sha(f)] for f in files],
                "env": {k: os.environ.get(k) for k in ENV_KEYS}}
    text = json.dumps(document, sort_keys=True)
    return hashlib.sha256(text.encode()).hexdigest()[:16], document


def _key_files(sources, bridging_header, library, link_inputs):
    return ([Path(s) for s in sources] + _headers(bridging_header or BRIDGING)
            + [Path(library or LIBRARY)] + list(CODEC_ARCHIVES) + [CODEC_STAMP]
            + [Path(p) for p in link_inputs])


def cache_key(*, sources, output, defines=(), optimize=False, wmo=False, link_args=(),
              link_inputs=(), bridging_header=None, library=None):
    argv = _argv(sources=sources, output="<output>", defines=defines, optimize=optimize,
                 wmo=wmo, link_args=link_args, bridging_header=bridging_header, library=library)
    return _key(argv, _key_files(sources, bridging_header, library, link_inputs), output)[0]


def _diagnostics(output):
    errors = ([line for line in output.splitlines() if ": error:" in line]
              or [line for line in output.splitlines() if "error:" in line])
    return errors[:12] or [line for line in output.strip().splitlines()[-4:] if line.strip()]


def _prune():
    """Keep the KEEP_ENTRIES newest by manifest mtime; drop a dead process's tmp folder."""
    entries = []
    for path in CACHE.iterdir() if CACHE.is_dir() else ():
        if path.name.startswith("tmp-"):
            pid = path.name.split("-")[1]
            try:
                os.kill(int(pid), 0)
            except ProcessLookupError:
                shutil.rmtree(path, ignore_errors=True)
            except (ValueError, PermissionError):
                pass
        elif path.is_dir() and (path / "manifest.json").exists():
            entries.append(((path / "manifest.json").stat().st_mtime, path))
    for _, path in sorted(entries, reverse=True)[KEEP_ENTRIES:]:
        stale = CACHE / f"tmp-{os.getpid()}-{os.urandom(4).hex()}"
        with contextlib.suppress(OSError):  # renamed first: a cut-short removal is a tmp- folder
            os.rename(path, stale)
            shutil.rmtree(stale, ignore_errors=True)


def _deliver(binary, output, expected=None):
    temp = Path(f"{output}.tmp-{os.getpid()}")
    temp.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(binary, temp)
    if expected is not None and _sha(temp) != expected:  # the copy's bytes are the ones checked
        return os.unlink(temp)  # None: nothing delivered
    os.chmod(temp, 0o755)
    os.replace(temp, output)
    return True


def build(*, sources: Sequence, output, defines: Sequence[str] = (), optimize: bool = False,
          wmo: bool = False, link_args: Sequence[str] = (), link_inputs: Sequence = (),
          bridging_header=None, library=None, timeout: float = 900,
          force: bool = False) -> Built:
    library = Path(library or LIBRARY)
    if not library.exists():
        raise SwiftBuildFailed(f"{library} is missing — run `cd core && cargo build --release` "
                               "first")
    absent = [str(p) for p in CODEC_ARCHIVES + (CODEC_STAMP,) if not p.exists()]
    if absent:
        raise SwiftBuildFailed(f"{', '.join(absent)} missing — run `make codecs` first")
    missing = [str(s) for s in list(sources) + list(link_inputs) if not Path(s).exists()]
    if missing:
        raise SwiftBuildFailed(f"swift_build: no such input: {', '.join(missing[:4])}")
    files = _key_files(sources, bridging_header, library, link_inputs)
    shape = dict(defines=defines, optimize=optimize, wmo=wmo, link_args=link_args,
                 bridging_header=bridging_header, library=library)
    key, document = _key(_argv(sources=sources, output="<output>", **shape), files, output)
    entry, started = CACHE / key, time.monotonic()
    if not force and entry.exists():  # a malformed entry, or one moved away mid-read, is rebuilt
        with contextlib.suppress(OSError, ValueError, KeyError, TypeError):
            recorded = json.loads((entry / "manifest.json").read_text())["binary_sha256"]
            if _deliver(entry / "binary", output, recorded):
                os.utime(entry / "manifest.json")
                print(f"swift_build: reused {key}", file=sys.stderr, flush=True)
                return Built(Path(output), key, True, round(time.monotonic() - started, 3))
        print(f"swift_build: entry {key} failed its digest; rebuilding", file=sys.stderr,
              flush=True)
    CACHE.mkdir(parents=True, exist_ok=True)
    temp = CACHE / f"tmp-{os.getpid()}-{os.urandom(4).hex()}"
    temp.mkdir()
    # Linked under the caller's own file name, which the linker writes into the ad-hoc
    # signature as its identifier, then kept in the entry as `binary`.
    linked = temp / "link" / Path(output).name
    linked.parent.mkdir()
    argv = _argv(sources=sources, output=linked, **shape)
    ran = bounded.run(argv, timeout, env=bounded.child_env())
    output_text = ran["stdout"] + ran["stderr"]
    (temp / "build.log").write_text(" ".join(argv) + "\n\n" + output_text)
    if not ran["expired"] and ran["rc"] == 0 and linked.exists():
        os.rename(linked, temp / "binary")
    if ran["expired"] or ran["rc"] != 0 or not (temp / "binary").exists():
        log = CACHE / "failed" / f"{key}.log"
        log.parent.mkdir(exist_ok=True)
        os.replace(temp / "build.log", log)
        shutil.rmtree(temp, ignore_errors=True)
        why = f"ran past {timeout} s and was killed" if ran["expired"] else f"exited {ran['rc']}"
        raise SwiftBuildFailed(f"swiftc {why} (log {log})", _diagnostics(output_text), log,
                               ran["expired"], ran["rc"])
    seconds = round(time.monotonic() - started, 1)
    manifest_doc = {"key": key, "inputs": document, "binary_sha256": _sha(temp / "binary"),
                    "seconds": seconds}
    (temp / "manifest.json").write_text(json.dumps(manifest_doc, indent=1, sort_keys=True))
    _deliver(temp / "binary", output)  # this process's own fresh build, whatever the cache keeps
    stale = CACHE / f"tmp-{os.getpid()}-{os.urandom(4).hex()}"
    with contextlib.suppress(OSError):  # whatever holds the key (force, failed, malformed) goes
        os.rename(entry, stale)
        shutil.rmtree(stale, ignore_errors=True)
    with contextlib.suppress(OSError):  # lost to a racing build of the same key: its entry stays
        os.rename(temp, entry)
    shutil.rmtree(temp, ignore_errors=True)  # already gone unless the rename was lost
    print(f"swift_build: built {key} in {seconds} s", file=sys.stderr, flush=True)
    _prune()
    return Built(Path(output), key, False, seconds)


def typecheck(*, sources, defines=(), timeout: float = 300):
    """(exit status, swiftc's output): `-typecheck` in batch mode on every core, no link."""
    argv = ["xcrun", "swiftc", "-typecheck", "-enable-batch-mode", "-j", str(os.cpu_count())]
    argv += [x for d in defines for x in ("-D", d)] + ["-sdk", _tools()["sdk"], "-target",
             TARGET, "-module-name", "FrameJob", "-import-objc-header", str(BRIDGING),
             "-Xcc", f"-I{CODECS}/include"]
    ran = bounded.run(argv + [str(s) for s in sources], timeout, env=bounded.child_env())
    text = ran["stdout"] + ran["stderr"]
    if ran["expired"]:
        return 124, text + f"\nswift_build: typecheck ran past {timeout} s and was killed"
    return ran["rc"], text


# ---- the guard: no proof carries its own app swiftc line (phase 1b) ----------------

OWN_ARGV = {False: re.compile(r"""["'](?:[^"'\s]*/)?swiftc["']"""),  # Python: a quoted swiftc argv
            True: re.compile(r"^(?!\s*#).*\bswiftc\s", re.M)}  # shell: a swiftc command
GUARD_ALLOWED = ("swift_build.py", "reference_build*.py", "*_spike/*", "recording_spike.py")


def own_line(text, shell=False):
    """True when `text` holds a swiftc argv AND the bridging header (its name,
    `-import-objc-header` or `BRIDGING`): an app build line of its own, which must go
    through `build()` instead."""
    return bool(OWN_ARGV[shell].search(text)) and (
        BRIDGING.stem in text or "-import-objc-header" in text or "BRIDGING" in text)


def own_lines(folder=None):
    """`*.py`/`*.sh` under `folder` (default tools/proof, less its work/) outside
    GUARD_ALLOWED that carry their own app swiftc line, as folder-relative labels."""
    folder, found = Path(folder or HERE), []
    for top, dirs, names in os.walk(folder):
        dirs[:] = [d for d in dirs if d != "__pycache__" and not (top == str(folder)
                                                                  and d == "work")]
        for name in names:
            path = Path(top, name)
            label = path.relative_to(folder).as_posix()
            if (path.suffix in (".py", ".sh")
                    and not any(fnmatch.fnmatch(label, a) for a in GUARD_ALLOWED)
                    and own_line(path.read_text(errors="replace"), path.suffix == ".sh")):
                found.append(label)
    return sorted(found)


# ---- the selftest ----------------------------------------------------------------


def selftest():
    global CACHE, CODEC_ARCHIVES, CODEC_STAMP
    scratch = ROOT / "tools/proof/work/swift-build-selftest"
    shutil.rmtree(scratch, ignore_errors=True)
    (scratch / "src").mkdir(parents=True)
    saved, CACHE = CACHE, scratch / "cache"
    saved_codecs = (CODEC_ARCHIVES, CODEC_STAMP)
    results, names = [], []

    def row(name, ok, detail):
        results.append(ok)
        names.append(name)
        print(f"{'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)

    def write(name, text):
        path = scratch / "src" / name
        path.write_text(text)
        return path

    try:
        a, b = write("a.swift", "let a = 1\n"), write("b.swift", "let b = 2\n")
        inner = write("inner.h", "int inner(void);\n")
        header = write("bridge.h", '#include "inner.h"\n')
        lib, extra = write("libframejob_core.a", "lib-1"), write("extra.plist", "plist-1")
        # The K rows key stand-in encoder archives, never the tree's build/codecs/.
        CODEC_ARCHIVES = (write("libSvtAv1Enc.a", "svt-1"), write("libvpx.a", "vpx-1"))
        CODEC_STAMP = write("stamp.json", "{}")
        base = dict(sources=[a, b], output="/z/one", defines=["X"], link_inputs=[extra],
                    bridging_header=header, library=lib)
        first = cache_key(**base)
        row("K0", first == cache_key(**base), f"CONTROL: the same inputs twice give {first}")
        changes = {"the source order": cache_key(**{**base, "sources": [b, a]}),
                   "a define": cache_key(**{**base, "defines": ["Y"]}),
                   "optimize": cache_key(**{**base, "optimize": True}),
                   "the output's file name": cache_key(**{**base, "output": "/z/two"})}
        for name, path, changed in (("a source byte", a, "let a = 3\n"),
                                    ("a link input", extra, "plist-2"),
                                    ("a header reached by #include", inner, "int inner(int);\n"),
                                    ("the library's bytes", lib, "lib-2"),
                                    ("an encoder archive's bytes", CODEC_ARCHIVES[1], "vpx-2"),
                                    ("the encoders' stamp", CODEC_STAMP, '{"key": 2}')):
            was = path.read_text()
            path.write_text(changed)
            changes[name] = cache_key(**base)
            path.write_text(was)
        files = _key_files([a, b], header, lib, [extra])
        shape = dict(sources=[a, b], defines=["X"], bridging_header=header, library=lib)
        same = (_key(_argv(output="/x/one", jobs=3, **shape), files, "/x/one")[0]
                == _key(_argv(output="/y/one", jobs=9, **shape), files, "/y/one")[0] == first)
        unchanged = [k for k, v in changes.items() if v == first]
        row("K1", not unchanged and same and first == cache_key(**base),
            f"changed for {len(changes) - len(unchanged)}/{len(changes)} "
            f"(unchanged: {unchanged or 'none'}); another -o folder and -j keep the key: {same}")
        CODEC_ARCHIVES, CODEC_STAMP = saved_codecs  # the B rows link the real ones

        program = write("main.swift", 'print("swift_build selftest \\(20 + 22)")\n')
        out = scratch / "out" / "selftest-binary"

        def runs():
            ran = bounded.run([str(out)], 60)
            return ran["rc"] == 0 and ran["stdout"].strip() == "swift_build selftest 42"
        try:
            one = build(sources=[program], output=out, timeout=300)
            row("B1", not one.reused and runs(),
                f"built {one.key} in {one.seconds} s; it runs and prints its answer: {runs()}")
            two = build(sources=[program], output=out, timeout=300)
            row("B2", two.reused and two.key == one.key and runs(),
                f"the same call reused {two.key}: {two.reused}")
            # LaunchServices keys a bare binary (its recent documents, for one) by the
            # signature's identifier, which the linker takes from the -o file name.
            signed = bounded.run(["codesign", "-dv", str(out)], 60)
            identifier = re.search(r"^Identifier=(.*)$", signed["stderr"], re.M)
            identifier = identifier and identifier.group(1)
            row("B6", identifier == out.name, f"the delivered binary's signature identifier is "
                f"its own file name, {out.name}: {identifier}")
            with open(CACHE / one.key / "binary", "ab") as f:
                f.write(b"tampered")
            three = build(sources=[program], output=out, timeout=300)
            manifest = json.loads((CACHE / one.key / "manifest.json").read_text())
            row("B3", not three.reused and runs()
                and manifest["binary_sha256"] == _sha(CACHE / one.key / "binary"),
                f"a tampered entry was rebuilt: {not three.reused}")
            (CACHE / one.key / "manifest.json").write_text("{")
            (CACHE / one.key / "binary").unlink()
            four = build(sources=[program], output=out, timeout=300)
            manifest = json.loads((CACHE / one.key / "manifest.json").read_text())
            row("B5", not four.reused and runs()
                and manifest["binary_sha256"] == _sha(CACHE / one.key / "binary"),
                f"an entry with a broken manifest and no binary was rebuilt: {not four.reused}")
        except (SwiftBuildFailed, OSError, ValueError) as error:
            for name in ("B1", "B2", "B6", "B3", "B5"):
                if name not in names:
                    row(name, False, f"raised: {getattr(error, 'diagnostics', [error])[:3]}")
        bad = write("bad.swift", 'let wrong: Int = "text"\n')
        try:
            build(sources=[bad], output=scratch / "out" / "bad-binary", timeout=300)
            row("B4", False, "a type error built")
        except SwiftBuildFailed as error:
            named = any("bad.swift" in line and "error:" in line for line in error.diagnostics)
            row("B4", named and error.log is not None and error.log.exists(),
                f"raised, naming the file: {named}; {error.diagnostics[:1]}")
        argv = 'run(["swiftc", "-import-objc-header", ROOT / "app/Bridging/{}.h", "x.swift"])'
        flagged = {"a Python argv": own_line(argv.format(BRIDGING.stem)),
                   "a shell line": own_line(f"  xcrun swiftc -import-objc-header {BRIDGING.name}"
                                            " x.swift\n", shell=True),
                   "a swift_build.BRIDGING argv": own_line(
                       'run(["swiftc", "-sdk", sdk, str(swift_build.BRIDGING), "x.swift"])'),
                   "an xcrun -sdk macosx shell line": own_line(
                       f"xcrun -sdk macosx swiftc -import-objc-header {BRIDGING.name} x.swift\n",
                       shell=True)}
        passed = {"no bridging header": own_line('run(["swiftc", "x.swift", "-o", "x"])'),
                  "a shell comment": own_line(f"# swiftc {BRIDGING.name}\n", shell=True)}
        row("G0", all(flagged.values()) and not any(passed.values()),
            f"CONTROL: flagged {flagged}; not flagged {passed}")
        try:
            found = own_lines()
        except OSError as error:  # an unreadable tree is a FAIL row, never a crash
            found = [f"(the scan failed: {error})"]
        row("G1", not found, f"tools/proof files outside {GUARD_ALLOWED} carrying their own "
            f"app swiftc line: {found or 'none'}")
    finally:
        CACHE = saved
        CODEC_ARCHIVES, CODEC_STAMP = saved_codecs
    ok = bool(results) and all(results)
    print(f"{sum(results)}/{len(results)} rows pass")
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description="the probe builder (B88)")
    parser.add_argument("--selftest", action="store_true", help="K0, K1, B1–B6, G0, G1")
    sub = parser.add_subparsers(dest="command")
    b = sub.add_parser("build", help="build SOURCE… (the entry last) to --output")
    b.add_argument("--output", required=True)
    b.add_argument("--define", action="append", default=[])
    b.add_argument("--force", action="store_true")
    b.add_argument("sources", nargs="+")
    t = sub.add_parser("typecheck", help="typecheck --sources' app files with PROBE.swift…")
    t.add_argument("--define", action="append", default=[])
    t.add_argument("--sources", default=None)
    t.add_argument("probes", nargs="*")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.command == "build":
        try:
            build(sources=args.sources, output=args.output, defines=args.define,
                  force=args.force)
        except SwiftBuildFailed as error:
            print("\n  ".join([f"swift_build: {error}"] + error.diagnostics), file=sys.stderr)
            return 1
        print(args.output)
        return 0
    if args.command == "typecheck":  # the last probe holds top-level code: it is main.swift
        probes = [Path(p).resolve() for p in args.probes]
        with tempfile.TemporaryDirectory() as temp:
            entry = Path(temp).resolve() / "main.swift"
            if probes:
                shutil.copyfile(probes[-1], entry)
            rc, text = typecheck(sources=app_sources(args.sources) + probes[:-1]
                                 + [entry] * bool(probes), defines=args.define)
        sys.stdout.write(text.replace(str(entry), str(probes[-1])) if probes else text)
        return rc
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
