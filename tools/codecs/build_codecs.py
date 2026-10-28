#!/usr/bin/env python3
"""The encoder build (road map "codec-export" C0, spec §11 CX-4, CX-5): SVT-AV1 and
libvpx, fetched as pinned tarballs, checked by SHA-256, built arm64, static and
encoder-only at the app's deployment target, and installed into `build/codecs/`.

    python3 tools/codecs/build_codecs.py              # build or reuse
    python3 tools/codecs/build_codecs.py --selftest   # no network, no cmake
    python3 tools/codecs/build_codecs.py --print-key  # this run's key alone, on stdout
    python3 tools/codecs/build_codecs.py --mutant key-no-tools|reuse-unchecked|sha-unchecked

`make codecs` and project.yml's "Build Codecs" pre-build step both run it. It prints
`codecs: reused <key>` or `codecs: built <key> in <s> s` on stdout. The install is
`build/codecs/`: `include/`, `lib/libSvtAv1Enc.a`, `lib/libvpx.a`,
`licenses/<library>/<file>` and `stamp.json` ({"key", "inputs", "outputs"}). It is reused
only when the stamp's key equals this run's key (sha256 over this file's bytes, PINS,
the tool versions and DEPLOYMENT_TARGET) AND every output still hashes as recorded.

ROOT is this file's RESOLVED path, so a tree copy (`tools/proof/tree_copy.py`, whose
`tools/` is a symlink) builds and reuses the tree's own `build/codecs/`, under LOCK.
Every build line, and `tool_versions()`, runs under `build_env()`, so a shell's
`make codecs` and Xcode's step compute one key. The tarballs are kept in
`build/codecs-downloads/`; a download whose digest is not the pin's is deleted and the
build fails, naming both digests. `tools/codecs/PROVENANCE.md` records each pin.

A licence entry naming a `.c` file installs its leading comment (`leading_comment()`):
SVT-AV1's `vector.c` carries its own MIT notice (spec §11 PUB-10, amending CX-5).
`--print-key` is what the publish workflow caches `build/codecs` under (PUB-12).

A `--mutant` runs the selftest alone and must fail exactly its rows: `key-no-tools` (the
tool versions left out of the key) K1; `reuse-unchecked` (a stamp reused without hashing
its outputs) R1 R2; `sha-unchecked` (a download kept without comparing its digest) S1.
E0/E1 are `leading_comment()`'s control and its refusal.
Stdlib only, Python 3.9 (`/usr/bin/python3`, which Xcode's step finds first).
"""

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import NamedTuple


class Pin(NamedTuple):
    name: str
    version: str
    url: str
    sha256: str
    commit: str  # `git get-tar-commit-id` of the tarball
    archive: str
    licenses: tuple  # ((path in the source tree, installed name), ...)


PINS = (
    Pin("svt-av1", "4.2.0",
        "https://gitlab.com/AOMediaCodec/SVT-AV1/-/archive/v4.2.0/SVT-AV1-v4.2.0.tar.gz",
        "c7b13c4a84bd3751aa35fcc72be13e6875467e7c2216879251a486e5b1e4e740",
        "9292ec8e32bce26f781f277ec8739b53426c4300",
        "libSvtAv1Enc.a",
        (("LICENSE.md", "LICENSE.md"), ("LICENSE-BSD2.md", "LICENSE-BSD2.md"),
         ("PATENTS.md", "PATENTS.md"),
         ("third_party/fastfeat/LICENSE", "fastfeat-LICENSE"),
         ("third_party/safestringlib/LICENSE", "safestringlib-LICENSE"),
         ("Source/Lib/Codec/vector.c", "vector.c-LICENSE"))),
    Pin("libvpx", "1.17.0",
        "https://github.com/webmproject/libvpx/archive/refs/tags/v1.17.0.tar.gz",
        "1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a",
        "6df3ec34557879fff673706f4a1d9fbd0f3a6f0e",
        "libvpx.a",
        (("LICENSE", "LICENSE"), ("PATENTS", "PATENTS"), ("AUTHORS", "AUTHORS"))),
)
DEPLOYMENT_TARGET = "26.0"
ROOT = Path(__file__).resolve().parents[2]
INSTALL = ROOT / "build/codecs"
DOWNLOADS = ROOT / "build/codecs-downloads"
WORK = ROOT / "build/codecs-work"
LOCK = ROOT / "build/codecs.lock"
CMAKE_DIRS = ("/opt/homebrew/bin", "/usr/local/bin")
SYSTEM_PATH = "/usr/bin:/bin:/usr/sbin:/sbin"
EXPECTED = {"key-no-tools": {"K1"}, "reuse-unchecked": {"R1", "R2"},
            "sha-unchecked": {"S1"}}
MUTANT = None


class BuildFailed(RuntimeError):
    pass


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def find_cmake():
    """`cmake` on PATH, else in each CMAKE_DIRS entry (Xcode's PATH may lack Homebrew)."""
    found = shutil.which("cmake")
    if found:
        return Path(found)
    for folder in CMAKE_DIRS:
        candidate = Path(folder) / "cmake"
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    raise BuildFailed("codecs: cmake not found on PATH or in "
                      f"{', '.join(CMAKE_DIRS)} — install it with `brew install cmake`")


def build_env():
    """The scrubbed environment every build line and `tool_versions()` run under."""
    env = {"HOME": os.environ.get("HOME", "/tmp"), "LANG": "C",
           "TMPDIR": os.environ.get("TMPDIR", "/tmp"),
           "MACOSX_DEPLOYMENT_TARGET": DEPLOYMENT_TARGET,
           "PATH": f"{SYSTEM_PATH}:{find_cmake().parent}"}
    if os.environ.get("DEVELOPER_DIR"):
        env["DEVELOPER_DIR"] = os.environ["DEVELOPER_DIR"]
    return env


def _output(argv, env):
    done = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=120)
    if done.returncode != 0:
        raise BuildFailed(f"codecs: {' '.join(map(str, argv))} exited {done.returncode}: "
                          + (done.stderr or done.stdout).strip()[-300:])
    return (done.stdout + done.stderr).strip()


def tool_versions():
    env = build_env()
    return {"clang": _output(["xcrun", "clang", "--version"], env),
            "cmake": _output([str(find_cmake()), "--version"], env),
            "sdk": _output(["xcrun", "--show-sdk-version"], env)}


def gather_inputs():
    return {"script": sha256(__file__), "pins": [list(p) for p in PINS],
            "tools": tool_versions(), "deployment_target": DEPLOYMENT_TARGET}


def key(inputs):
    """sha256 hex over this file's bytes, PINS, the tool versions and DEPLOYMENT_TARGET."""
    document = dict(inputs)
    if MUTANT == "key-no-tools":
        document.pop("tools", None)
    return hashlib.sha256(json.dumps(document, sort_keys=True).encode()).hexdigest()


def verdict(stamp, want):
    """("reuse"|"build", reason): reuse only with an equal key and every output as recorded."""
    try:
        recorded = json.loads(Path(stamp).read_text())
        outputs = recorded["outputs"]
        if not isinstance(outputs, dict) or not outputs:
            return "build", "the stamp records no outputs"
    except FileNotFoundError:
        return "build", "no stamp"
    except (OSError, ValueError, KeyError, TypeError) as error:
        return "build", f"the stamp is unreadable ({error})"
    if recorded.get("key") != want:
        return "build", f"the key changed ({str(recorded.get('key'))[:16]} → {want[:16]})"
    if MUTANT != "reuse-unchecked":
        top = Path(stamp).parent
        for relative, digest in sorted(outputs.items()):
            path = top / relative
            if not path.is_file():
                return "build", f"{relative} is missing"
            if sha256(path) != digest:
                return "build", f"{relative} no longer hashes as recorded"
    return "reuse", "the stamp's key and every output match"


def check_download(path, expected):
    """Raises naming both digests, and deletes the file, unless it hashes to `expected`."""
    actual = sha256(path)
    if actual != expected and MUTANT != "sha-unchecked":
        Path(path).unlink()
        raise BuildFailed(f"codecs: {Path(path).name} has SHA-256 {actual}, expected "
                          f"{expected}; it was deleted")


def leading_comment(path):
    """The text between the file's leading `/*` and its first `*/`, blank edge lines
    stripped, with one final newline; BuildFailed naming the file when it has none."""
    text = Path(path).read_text(encoding="utf-8", errors="replace").lstrip()
    end = text.find("*/")
    if not text.startswith("/*") or end < 0:
        raise BuildFailed(f"codecs: {path} has no leading /* … */ comment to install")
    lines = text[2:end].split("\n")
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    if not lines:
        raise BuildFailed(f"codecs: {path}'s leading comment is empty")
    return "\n".join(lines) + "\n"


def _fetch(pin):
    DOWNLOADS.mkdir(parents=True, exist_ok=True)
    path = DOWNLOADS / pin.url.rsplit("/", 1)[1]
    if path.is_file() and sha256(path) == pin.sha256:
        return path
    part = path.with_name(path.name + ".part")
    print(f"codecs: fetching {pin.url}", file=sys.stderr, flush=True)
    done = subprocess.run(["/usr/bin/curl", "-fsSL", "--retry", "3", "-o", str(part), pin.url],
                          capture_output=True, text=True, timeout=600)
    if done.returncode != 0:
        part.unlink(missing_ok=True)
        raise BuildFailed(f"codecs: fetching {pin.url} failed (curl {done.returncode}): "
                          + done.stderr.strip()[-300:])
    os.replace(part, path)
    check_download(path, pin.sha256)
    return path


def _run(argv, cwd, env, log):
    log.write(f"$ (cd {cwd}) {' '.join(map(str, argv))}\n")
    log.flush()
    done = subprocess.run([str(a) for a in argv], cwd=str(cwd), env=env, stdout=log,
                          stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    if done.returncode != 0:
        raise BuildFailed(f"codecs: {Path(str(argv[0])).name} exited {done.returncode} "
                          f"in {cwd} (log {log.name})")


def _build_one(pin, tarball, env, jobs):
    """Extract, configure, build and install one library into WORK/<name>/stage."""
    top = WORK / pin.name
    shutil.rmtree(top, ignore_errors=True)
    (top / "build").mkdir(parents=True)
    stage = top / "stage"
    with open(WORK / f"{pin.name}.log", "w") as log:
        _run(["/usr/bin/tar", "-xzf", tarball, "-C", top], top, env, log)
        sources = [p for p in top.iterdir() if p.is_dir() and p.name not in ("build", "stage")]
        if len(sources) != 1:
            raise BuildFailed(f"codecs: {tarball.name} unpacked to {sorted(map(str, sources))}")
        source, build = sources[0], top / "build"
        if pin.name == "svt-av1":
            _run(["cmake", "-G", "Unix Makefiles", "-DCMAKE_BUILD_TYPE=Release",
                  "-DCMAKE_OSX_ARCHITECTURES=arm64",
                  f"-DCMAKE_OSX_DEPLOYMENT_TARGET={DEPLOYMENT_TARGET}",
                  f"-DCMAKE_INSTALL_PREFIX={stage}", "-DBUILD_SHARED_LIBS=OFF",
                  "-DBUILD_DEC=OFF", "-DBUILD_APPS=OFF", "-DBUILD_TESTING=OFF",
                  "-S", source, "-B", build], build, env, log)
            _run(["cmake", "--build", build, f"-j{jobs}"], build, env, log)
            _run(["cmake", "--install", build], build, env, log)
        else:
            _run([source / "configure", "--target=arm64-darwin25-gcc", f"--prefix={stage}",
                  "--enable-static", "--disable-shared", "--disable-vp8", "--enable-vp9",
                  "--enable-vp9-highbitdepth", "--disable-vp9-decoder", "--disable-examples",
                  "--disable-tools", "--disable-unit-tests", "--disable-docs",
                  "--disable-webm-io", "--disable-libyuv"], build, env, log)
            _run(["make", f"-j{jobs}"], build, env, log)
            _run(["make", "install"], build, env, log)
    return source, stage


def _assemble(built, target):
    """include/, lib/<archive> and licenses/<name>/ from each stage into `target`."""
    for pin, (source, stage) in built:
        archive = stage / "lib" / pin.archive
        if not archive.is_file():
            raise BuildFailed(f"codecs: {pin.name} installed no {pin.archive}")
        (target / "lib").mkdir(parents=True, exist_ok=True)
        shutil.copy2(archive, target / "lib" / pin.archive)
        shutil.copytree(stage / "include", target / "include", dirs_exist_ok=True)
        licences = target / "licenses" / pin.name
        licences.mkdir(parents=True, exist_ok=True)
        for inside, installed in pin.licenses:
            if inside.endswith(".c"):
                (licences / installed).write_text(leading_comment(source / inside),
                                                  encoding="utf-8")
            else:
                shutil.copyfile(source / inside, licences / installed)


def _outputs(top):
    return {p.relative_to(top).as_posix(): sha256(p)
            for p in sorted(top.rglob("*")) if p.is_file() and p.name != "stamp.json"}


def build_or_reuse():
    started = time.monotonic()
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    with open(LOCK, "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)  # a racing build of the same tree waits, then reuses
        inputs = gather_inputs()
        want = key(inputs)
        action, reason = verdict(INSTALL / "stamp.json", want)
        if action == "reuse":
            print(f"codecs: reused {want}", flush=True)
            return 0
        print(f"codecs: building ({reason})", file=sys.stderr, flush=True)
        env, jobs = build_env(), os.cpu_count() or 4
        WORK.mkdir(parents=True, exist_ok=True)
        built = [(pin, _build_one(pin, _fetch(pin), env, jobs)) for pin in PINS]
        fresh = Path(tempfile.mkdtemp(prefix="codecs.new-", dir=INSTALL.parent))
        try:
            _assemble(built, fresh)
            stamp = {"key": want, "inputs": inputs, "outputs": _outputs(fresh)}
            (fresh / "stamp.json").write_text(json.dumps(stamp, indent=1, sort_keys=True))
            fresh.chmod(0o755)
            old = INSTALL.parent / f"codecs.old-{os.getpid()}"
            if INSTALL.exists():
                os.rename(INSTALL, old)
            os.rename(fresh, INSTALL)
            shutil.rmtree(old, ignore_errors=True)
        finally:
            shutil.rmtree(fresh, ignore_errors=True)
        shutil.rmtree(WORK, ignore_errors=True)
        print(f"codecs: built {want} in {time.monotonic() - started:.0f} s", flush=True)
        return 0


# ---- the selftest: no network, no cmake ------------------------------------------


def selftest(mutant=None):
    global MUTANT, CMAKE_DIRS
    MUTANT, results = mutant, []

    def row(name, ok, detail):
        results.append((name, bool(ok)))
        print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)

    scratch = Path(tempfile.mkdtemp(prefix="build_codecs-selftest-"))
    saved_path, saved_dirs = os.environ.get("PATH", ""), CMAKE_DIRS
    try:
        base = {"script": "a" * 64, "pins": [list(p) for p in PINS],
                "tools": {"clang": "clang 1", "cmake": "cmake 1", "sdk": "26.0"},
                "deployment_target": DEPLOYMENT_TARGET}
        first = key(base)
        row("K0", first == key(dict(base)) and len(first) == 64,
            f"CONTROL: the same inputs twice give {first[:16]}")
        tools = {**base, "tools": {**base["tools"], "cmake": "cmake 2"}}
        sdk = {**base, "tools": {**base["tools"], "sdk": "26.1"}}
        row("K1", key(tools) != first and key(sdk) != first,
            "a changed cmake version and a changed SDK each change the key: "
            f"{key(tools) != first}, {key(sdk) != first}")
        pins = [list(p) for p in PINS]
        pins[1][3] = "0" * 64
        changes = {"the script's bytes": key({**base, "script": "b" * 64}),
                   "a pin's digest": key({**base, "pins": pins}),
                   "the deployment target": key({**base, "deployment_target": "27.0"})}
        same = [name for name, value in changes.items() if value == first]
        row("K2", not same, f"changed for {len(changes) - len(same)}/{len(changes)}"
            + (f" (unchanged: {same})" if same else ""))

        install = scratch / "install"
        (install / "lib").mkdir(parents=True)
        (install / "lib/libx.a").write_bytes(b"archive-1")
        (install / "licenses").mkdir()
        (install / "licenses/LICENSE").write_bytes(b"licence-1")

        def stamp(text_key=first):
            (install / "stamp.json").write_text(json.dumps(
                {"key": text_key, "inputs": base, "outputs": _outputs(install)}))
        stamp()
        r0 = verdict(install / "stamp.json", first)
        row("R0", r0[0] == "reuse", f"CONTROL: an equal key and equal outputs: {r0}")
        (install / "lib/libx.a").write_bytes(b"archive-2")
        r1 = verdict(install / "stamp.json", first)
        row("R1", r1[0] == "build" and "libx.a" in r1[1], f"an output's byte changed: {r1}")
        (install / "lib/libx.a").unlink()
        r2 = verdict(install / "stamp.json", first)
        row("R2", r2[0] == "build" and "missing" in r2[1], f"an output removed: {r2}")
        (install / "lib/libx.a").write_bytes(b"archive-1")
        r3 = verdict(install / "stamp.json", "f" * 64)
        r4 = verdict(scratch / "none.json", first)
        (scratch / "bad.json").write_text("{")
        r5 = verdict(scratch / "bad.json", first)
        row("R3", r3[0] == r4[0] == r5[0] == "build",
            f"another key, no stamp, a broken stamp all build: {r3}, {r4}, {r5}")

        good = scratch / "good.tar.gz"
        good.write_bytes(b"tarball")
        digest = hashlib.sha256(b"tarball").hexdigest()
        try:
            check_download(good, digest)
            row("S0", good.exists(), "CONTROL: a matching digest passes and keeps the file")
        except BuildFailed as error:
            row("S0", False, f"a matching digest raised: {error}")
        bad = scratch / "bad.tar.gz"
        bad.write_bytes(b"tampered")
        actual = hashlib.sha256(b"tampered").hexdigest()
        try:
            check_download(bad, digest)
            row("S1", False, f"a mismatched digest passed; the file kept: {bad.exists()}")
        except BuildFailed as error:
            named = digest in str(error) and actual in str(error)
            row("S1", named and not bad.exists(),
                f"raised naming both digests: {named}; deleted: {not bad.exists()}")

        problems = []
        for pin in PINS:
            if len(pin.sha256) != 64 or any(c not in "0123456789abcdef" for c in pin.sha256):
                problems.append(f"{pin.name}'s sha256")
            if len(pin.commit) != 40 or any(c not in "0123456789abcdef" for c in pin.commit):
                problems.append(f"{pin.name}'s commit")
            if not pin.url.startswith("https://") or f"v{pin.version}" not in pin.url:
                problems.append(f"{pin.name}'s url")
            if not pin.archive.endswith(".a") or not pin.licenses:
                problems.append(f"{pin.name}'s archive or licences")
        row("P1", not problems and [p.name for p in PINS] == ["svt-av1", "libvpx"],
            f"the pins are well formed: {problems or 'yes'}")

        fake = scratch / "brew-bin"
        fake.mkdir()
        (fake / "cmake").write_text("#!/bin/sh\necho cmake version 0\n")
        (fake / "cmake").chmod(0o755)
        os.environ["PATH"] = SYSTEM_PATH
        CMAKE_DIRS = (str(scratch / "absent"), str(fake))
        found = find_cmake() if shutil.which("cmake") is None else None
        env = build_env() if found else {}
        allowed = {"HOME", "TMPDIR", "LANG", "DEVELOPER_DIR", "MACOSX_DEPLOYMENT_TARGET",
                   "PATH"}
        row("C1", found == fake / "cmake" and set(env) <= allowed
            and env.get("PATH") == f"{SYSTEM_PATH}:{fake}"
            and env.get("MACOSX_DEPLOYMENT_TARGET") == DEPLOYMENT_TARGET,
            f"without Homebrew on PATH cmake is found in CMAKE_DIRS ({found}), and the "
            f"environment is {sorted(env)} with PATH {env.get('PATH')}")
        CMAKE_DIRS = (str(scratch / "absent"),)
        try:
            find_cmake()
            row("C2", False, "no cmake anywhere, and find_cmake answered one")
        except BuildFailed as error:
            row("C2", "brew install cmake" in str(error), f"no cmake raises: {error}")

        excerpt = "The MIT License(MIT)\nCopyright(c) 2016 Someone\n\nPermission is granted."
        header = scratch / "header.c"
        header.write_text(f"/*\n\n{excerpt}\n\n*/\n\n#include <x.h>\n/* later */\n")
        got = leading_comment(header)
        row("E0", got == excerpt + "\n",
            f"CONTROL: a .c file's leading comment is excerpted exactly: {got!r}")
        bare = scratch / "bare.c"
        bare.write_text("#include <x.h>\n/* not leading */\n")
        try:
            got = leading_comment(bare)
            row("E1", False, f"a file with no leading comment answered {got!r}")
        except BuildFailed as error:
            row("E1", str(bare) in str(error), f"no leading comment raises: {error}")
    finally:
        os.environ["PATH"], CMAKE_DIRS = saved_path, saved_dirs
        shutil.rmtree(scratch, ignore_errors=True)

    failed = {name for name, ok in results if not ok}
    print(f"{len(results) - len(failed)}/{len(results)} rows pass")
    ok = failed == EXPECTED[mutant] if mutant else not failed
    print(f"MUTANT {'PASS' if ok else 'FAIL'}: {mutant} failed {sorted(failed)}, expected "
          f"{sorted(EXPECTED[mutant])}" if mutant else "PASS" if ok else "FAIL")
    return 0 if ok else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description="the encoder build (codec-export C0)")
    parser.add_argument("--selftest", action="store_true",
                        help="K0–K2, R0–R3, S0–S1, P1, C1–C2, E0–E1")
    parser.add_argument("--mutant", choices=sorted(EXPECTED))
    parser.add_argument("--print-key", action="store_true",
                        help="print this run's key alone (the publish workflow's cache key)")
    args = parser.parse_args(argv)
    if args.selftest or args.mutant:
        return selftest(args.mutant)
    if args.print_key:
        try:
            print(key(gather_inputs()), flush=True)
            return 0
        except (BuildFailed, OSError, subprocess.SubprocessError) as error:
            print(f"error: {error}", file=sys.stderr, flush=True)
            return 1
    try:
        return build_or_reuse()
    except (BuildFailed, OSError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr, flush=True)
        return 1


if __name__ == "__main__":
    sys.exit(main())
