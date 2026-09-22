"""Build a historical chrome harness with that commit's own core and header."""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time


TARGET = "aarch64-apple-darwin"
SWIFT_TARGET = "arm64-apple-macos15.0"
FLAGS = ("-target", SWIFT_TARGET, "-module-name", "Reelcut",
         "-D", "HARNESS_REFERENCE_BUILD")
OVERRIDES = ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "RUSTUP_TOOLCHAIN", "RUSTC", "CARGO", "CC", "CFLAGS",
             "DEVELOPER_DIR", "SWIFTFLAGS", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET")
OVERRIDE_PREFIXES = ("CARGO_TARGET_", "CARGO_PROFILE_")
NOTE = "this tree's own harness/main.swift, so both renders come out of one program"


def _files(root):
    path = Path(root)
    if path.is_file():
        return [(path.name, path)]
    return [(p.relative_to(path).as_posix(), p) for p in sorted(path.rglob("*"))
            if p.is_file()]


def _digest(paths):
    h = hashlib.sha256()
    for label, path in paths:
        h.update(label.encode() + b"\0")
        if not Path(path).exists():
            h.update(b"<missing>\0")
            continue
        for relative, file in _files(path):
            h.update(relative.encode() + b"\0")
            with open(file, "rb") as stream:
                for block in iter(lambda: stream.read(1024 * 1024), b""):
                    h.update(block)
    return h.hexdigest()


def _run(args, *, env, log=None, input_bytes=None):
    result = subprocess.run(args, input=input_bytes, capture_output=True, env=env)
    output = result.stdout + result.stderr
    if log is not None:
        Path(log).write_bytes(output)
    if result.returncode:
        tail = output.decode(errors="replace").strip().splitlines()[-12:]
        raise RuntimeError(f"{' '.join(map(str, args[:4]))} exited {result.returncode}: "
                           + "\n".join(tail) + (f"\nfull log: {log}" if log else ""))
    return result.stdout.decode(errors="replace").strip()


def _version(args, env):
    return _run(args, env=env).splitlines()[0]


def _inputs(root, harness_main, fonts, proof_script):
    root = Path(root)
    paths = [("app/Sources", root / "app/Sources"),
             ("app/Bridging", root / "app/Bridging"),
             ("core/src", root / "core/src"),
             ("core/include", root / "core/include"),
             ("core/Cargo.toml", root / "core/Cargo.toml"),
             ("core/Cargo.lock", root / "core/Cargo.lock"),
             ("core/staticlib", root / "core/target/release/libreelcut_core.a"),
             ("harness", harness_main), ("builder", __file__),
             ("caller", proof_script), ("Fonts", fonts)]
    return _digest(paths)


def build_reference(*, root: str, before: str, commit: str,
                    harness_main: str, fonts: str, proof_script: str) -> tuple[str | None, str, str]:
    """Return (binary, full commit, note); failure is data for the caller to score."""
    before = Path(before)
    root = Path(root)
    binary = before / "harness"
    stamp_path = before / "stamp.json"
    env = os.environ.copy()
    env.pop("RC_ASSEMBLYAI_KEY", None)
    try:
        sha = _run(["git", "-C", str(root), "rev-parse", "--verify", f"{commit}^{{commit}}"],
                   env=env)
    except (OSError, RuntimeError) as error:
        return None, commit, f"reference revision could not be resolved: {error}"

    try:
        sdk = _run(["xcrun", "--show-sdk-path", "--sdk", "macosx"], env=env)
        versions = {"swiftc": _version(["swiftc", "--version"], env),
                    "cargo": _version(["cargo", "--version"], env),
                    "rustc": _version(["rustc", "--version"], env),
                    "sdk": sdk,
                    "sdk_version": _version(["xcrun", "--show-sdk-version", "--sdk", "macosx"], env),
                    "swiftc_path": shutil.which("swiftc"),
                    "cargo_path": shutil.which("cargo"),
                    "rustc_path": shutil.which("rustc"),
                    "targets": [TARGET, SWIFT_TARGET], "flags": FLAGS,
                    "overrides": {name: env.get(name) for name in sorted(set(OVERRIDES) | {
                        name for name in env if name.startswith(OVERRIDE_PREFIXES)})}}
        key = hashlib.sha256(json.dumps([sha, _inputs(root, harness_main, fonts, proof_script),
                                         versions], sort_keys=True).encode()).hexdigest()
        try:
            kept = json.loads(stamp_path.read_text())
            if (set(kept) == {"version", "key", "commit", "note", "tree_sha256", "binary_sha256"}
                    and kept.get("version") == 1 and kept.get("key") == key
                    and kept.get("commit") == sha and kept.get("note") == NOTE
                    and all(isinstance(kept.get(name), str) and len(kept[name]) == 64
                            and all(c in "0123456789abcdef" for c in kept[name])
                            for name in ("key", "tree_sha256", "binary_sha256"))
                    and binary.is_file()
                    and os.access(binary, os.X_OK)
                    and _digest([("tree", before / "tree")]) == kept.get("tree_sha256")
                    and _digest([("binary", binary)]) == kept.get("binary_sha256")
                    and _digest([("Fonts", before / "Fonts")]) == _digest([("Fonts", fonts)])):
                print(f"reference: cache hit {sha[:8]} at {binary}")
                return str(binary), sha, kept["note"]
        except (OSError, ValueError, TypeError, AttributeError, KeyError):
            pass

        start = time.monotonic()
        if before.exists():
            shutil.rmtree(before)
        tree = before / "tree"
        tree.mkdir(parents=True)
        archive = subprocess.run(["git", "-C", str(root), "archive", sha,
                                  "app/Sources", "app/Bridging", "core"],
                                 capture_output=True, env=env)
        (before / "archive.log").write_bytes(archive.stderr)
        if archive.returncode:
            raise RuntimeError(f"git archive exited {archive.returncode}: "
                               + archive.stderr.decode(errors="replace")[-1000:])
        with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
            tar.extractall(tree, filter="data")
        core = tree / "core"
        target_dir = before / "target"
        module_dir = before / "modules"
        module_dir.mkdir()
        child_env = env.copy()
        child_env["CLANG_MODULE_CACHE_PATH"] = str(module_dir / "clang")
        child_env["SWIFT_MODULE_CACHE_PATH"] = str(module_dir / "swift")
        lib = target_dir / TARGET / "release/libreelcut_core.a"
        _run(["cargo", "build", "--release", "--locked", "--manifest-path",
              str(core / "Cargo.toml"), "--target", TARGET, "--target-dir",
              str(target_dir)], env=child_env, log=before / "cargo.log")
        if not lib.is_file():
            raise RuntimeError(f"cargo succeeded without {lib}")
        sources = sorted(str(p) for p in (tree / "app/Sources").glob("*.swift")
                         if p.name != "main.swift")
        swift = ["swiftc", "-sdk", sdk, *FLAGS, "-import-objc-header",
                 str(tree / "app/Bridging/Reelcut-Bridging-Header.h"),
                 "-module-cache-path", str(module_dir / "swift"),
                 "-Xcc", f"-fmodules-cache-path={module_dir / 'clang'}",
                 "-L", str(lib.parent), "-lreelcut_core", *sources,
                 harness_main, "-o", str(binary)]
        _run(swift, env=child_env, log=before / "swiftc.log")
        if not binary.is_file() or not os.access(binary, os.X_OK):
            raise RuntimeError(f"swiftc succeeded without executable {binary}")
        shutil.copytree(fonts, before / "Fonts")
        stamp = {"version": 1, "key": key, "commit": sha, "note": NOTE,
                 "tree_sha256": _digest([("tree", tree)]),
                 "binary_sha256": _digest([("binary", binary)])}
        temporary = before / "stamp.json.tmp"
        temporary.write_text(json.dumps(stamp, indent=2) + "\n")
        os.replace(temporary, stamp_path)
        print(f"reference: built {sha[:8]} in {time.monotonic() - start:.0f} s at {binary}")
        return str(binary), sha, NOTE
    except (OSError, RuntimeError, ValueError, tarfile.TarError) as error:
        try:
            stamp_path.unlink(missing_ok=True)
        except OSError:
            pass
        return None, sha, f"the reference harness ({sha[:8]}) did not build: {error}"
