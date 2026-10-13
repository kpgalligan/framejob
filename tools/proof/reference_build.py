"""Build a historical chrome harness with that commit's own core and header.

`commit` may name a commit or a tree object (a pipeline's final working tree);
the tree's `graphic/` is archived beside its core when it has one, because the
core names it as a path dependency. `defines` are `-D` flags on the swiftc line
and part of the cache key; `FRAMEJOB_DEV_TOOLS` among them is the tree's own
flag (`tree_defines`). A tree from before the rename (spec §11 NM-6) is built
under its own names: `tree_names` reads them off its bridging header."""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import time
from dataclasses import dataclass
from typing import Sequence


TARGET = "aarch64-apple-darwin"
SWIFT_TARGET = "arm64-apple-macos26.0"
FLAGS = ("-target", SWIFT_TARGET, "-D", "HARNESS_REFERENCE_BUILD")
OVERRIDES = ("RUSTFLAGS", "CARGO_ENCODED_RUSTFLAGS", "RUSTUP_TOOLCHAIN", "RUSTC", "CARGO", "CC", "CFLAGS",
             "DEVELOPER_DIR", "SWIFTFLAGS", "SDKROOT", "MACOSX_DEPLOYMENT_TARGET")
OVERRIDE_PREFIXES = ("CARGO_TARGET_", "CARGO_PROFILE_")
NOTE = "this tree's own harness/main.swift, so both renders come out of one program"


@dataclass(frozen=True)
class TreeNames:
    """What a tree calls its module, bridging header, core header, staticlib,
    dev-tools flag and document type."""
    module: str
    bridging: str
    header: str
    staticlib: str
    dev_tools: str
    project_type: str


NEW_NAMES = TreeNames("FrameJob", "app/Bridging/FrameJob-Bridging-Header.h",
                      "core/include/framejob_core.h", "libframejob_core.a", "FRAMEJOB_DEV_TOOLS",
                      "com.kgalligan.framejob-project")
# A tree from before rename R1 (spec §11 NM-6): its own names, kept to build it.
OLD_NAMES = TreeNames("Reelcut", "app/Bridging/Reelcut-Bridging-Header.h",
                      "core/include/reelcut_core.h", "libreelcut_core.a", "REELCUT_DEV_TOOLS",
                      "com.kgalligan.reelcut-project")


def tree_names(tree: Path) -> TreeNames:
    """The old names when `tree` holds the old bridging header, else the new ones."""
    return OLD_NAMES if (Path(tree) / OLD_NAMES.bridging).exists() else NEW_NAMES


def tree_defines(tree: Path, defines: Sequence[str]) -> list[str]:
    """`defines` with `FRAMEJOB_DEV_TOOLS` spelled as `tree` spells its flag."""
    names = tree_names(tree)
    return [names.dev_tools if d == NEW_NAMES.dev_tools else d for d in defines]


def tree_shader(tree: Path, text: str) -> str:
    """Metal source `text` with its `framejob_` entry points named as `tree`'s
    Swift asks for them (`reelcut_` in a tree from before the rename)."""
    return text.replace("framejob_", "reelcut_") if tree_names(tree) is OLD_NAMES else text


def link_flag(names: TreeNames) -> str:
    """The `-l` flag naming `names.staticlib`."""
    return "-l" + names.staticlib.removeprefix("lib").removesuffix(".a")


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
             ("core/staticlib", root / "core/target/release" / NEW_NAMES.staticlib),
             ("harness", harness_main), ("builder", __file__),
             ("caller", proof_script), ("Fonts", fonts)]
    return _digest(paths)


def _resolve(root, commit, env):
    """The full id of `commit` as a commit, or failing that as a tree."""
    try:
        return _run(["git", "-C", str(root), "rev-parse", "--verify", f"{commit}^{{commit}}"],
                    env=env)
    except (OSError, RuntimeError):
        return _run(["git", "-C", str(root), "rev-parse", "--verify", f"{commit}^{{tree}}"],
                    env=env)


def build_reference(*, root: str, before: str, commit: str,
                    harness_main: str, fonts: str, proof_script: str,
                    defines: Sequence[str] = ()) -> tuple[str | None, str, str]:
    """Return (binary, full commit or tree id, note); failure is data for the caller to score."""
    before = Path(before)
    root = Path(root)
    binary = before / "harness"
    stamp_path = before / "stamp.json"
    env = os.environ.copy()
    env.pop("RC_ASSEMBLYAI_KEY", None)
    defines = list(defines)
    try:
        sha = _resolve(root, commit, env)
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
                    "targets": [TARGET, SWIFT_TARGET], "flags": FLAGS, "defines": defines,
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
        top = _run(["git", "-C", str(root), "ls-tree", "--name-only", sha], env=env).splitlines()
        archive = subprocess.run(["git", "-C", str(root), "archive", sha,
                                  "app/Sources", "app/Bridging", "core",
                                  *(["graphic"] if "graphic" in top else [])],
                                 capture_output=True, env=env)
        (before / "archive.log").write_bytes(archive.stderr)
        if archive.returncode:
            raise RuntimeError(f"git archive exited {archive.returncode}: "
                               + archive.stderr.decode(errors="replace")[-1000:])
        with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
            tar.extractall(tree, filter="data")
        core = tree / "core"
        names = tree_names(tree)
        target_dir = before / "target"
        module_dir = before / "modules"
        module_dir.mkdir()
        child_env = env.copy()
        child_env["CLANG_MODULE_CACHE_PATH"] = str(module_dir / "clang")
        child_env["SWIFT_MODULE_CACHE_PATH"] = str(module_dir / "swift")
        lib = target_dir / TARGET / "release" / names.staticlib
        _run(["cargo", "build", "--release", "--locked", "--manifest-path",
              str(core / "Cargo.toml"), "--target", TARGET, "--target-dir",
              str(target_dir)], env=child_env, log=before / "cargo.log")
        if not lib.is_file():
            raise RuntimeError(f"cargo succeeded without {lib}")
        sources = sorted(str(p) for p in (tree / "app/Sources").glob("*.swift")
                         if p.name != "main.swift")
        swift = ["swiftc", "-sdk", sdk, *FLAGS, "-module-name", names.module,
                 *[x for d in tree_defines(tree, defines) for x in ("-D", d)],
                 "-import-objc-header", str(tree / names.bridging),
                 "-module-cache-path", str(module_dir / "swift"),
                 "-Xcc", f"-fmodules-cache-path={module_dir / 'clang'}",
                 "-L", str(lib.parent), link_flag(names), *sources,
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
