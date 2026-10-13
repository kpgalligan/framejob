#!/usr/bin/env python3
"""Black-box cache checks; --integration compiles real historical consumers."""

import argparse
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

import reference_build


def insist(condition, label):
    if not condition:
        raise AssertionError(label)
    print(f"PASS: {label}")


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(value)


def fake_tools(folder):
    script = folder / "fake_tool"
    write(script, '''#!/usr/bin/env python3
import os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
assert 'RC_ASSEMBLYAI_KEY' not in os.environ
if '--version' in args or '-version' in args:
    print(name + ' fixture 1.0')
    sys.exit(0)
if name == 'xcrun':
    print('/fixture/SDK' if '--show-sdk-path' in args else '15.0')
    sys.exit(0)
with open(os.environ['FAKE_EVENTS'], 'a') as events:
    events.write(name + ' ' + ' '.join(args) + '\\n')
if name == 'cargo':
    manifest = pathlib.Path(args[args.index('--manifest-path') + 1])
    target = pathlib.Path(args[args.index('--target-dir') + 1])
    assert '/tree/core/' in str(manifest) and manifest.is_file()
    assert args[args.index('--target') + 1] == 'aarch64-apple-darwin'
    old = (manifest.parent.parent / 'app/Bridging/Reelcut-Bridging-Header.h').exists()
    lib = target / 'aarch64-apple-darwin/release' / ('libreelcut_core.a' if old else 'libframejob_core.a')
    lib.parent.mkdir(parents=True, exist_ok=True)
    lib.write_bytes(b'historical library ' + manifest.read_bytes())
elif name == 'swiftc':
    header = pathlib.Path(args[args.index('-import-objc-header') + 1])
    libdir = pathlib.Path(args[args.index('-L') + 1])
    assert '/tree/app/Bridging/' in str(header) and header.is_file()
    assert '/target/aarch64-apple-darwin/release' in str(libdir)
    linked = [arg[2:] for arg in args if arg.startswith('-l')]
    assert len(linked) == 1 and (libdir / ('lib' + linked[0] + '.a')).is_file()
    assert any('/tree/app/Sources/' in arg for arg in args)
    assert '-module-cache-path' in args and any('fmodules-cache-path=' in arg for arg in args)
    assert 'HARNESS_REFERENCE_BUILD' in args
    if os.environ.get('FAKE_SWIFT_FAIL'):
        print('app/Sources/ReelCore.swift: rc_project_apply: injected compiler failure', file=sys.stderr)
        sys.exit(1)
    out = pathlib.Path(args[args.index('-o') + 1])
    out.write_text('#!/bin/sh\\nexit 0\\n')
    out.chmod(0o755)
''')
    script.chmod(0o755)
    for name in ("cargo", "swiftc", "rustc", "xcrun"):
        (folder / name).symlink_to(script)


def fixture(folder):
    """A repo of three commits: `old` under the names from before rename R1,
    then `first` and `second` under the new ones."""
    root = folder / "repo"
    write(root / "app/Sources/A.swift", "let history = 0\n")
    write(root / "app/Bridging/Reelcut-Bridging-Header.h", "// old-named header\n")
    write(root / "core/src/lib.rs", "// old core\n")
    write(root / "core/include/reelcut_core.h", "// old-named C API\n")
    write(root / "core/Cargo.toml", "[package]\nname = 'fixture'\nversion = '0.1.0'\n")
    write(root / "core/Cargo.lock", "# lock\n")
    subprocess.run(["git", "init", "-q", str(root)], check=True)
    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
    subprocess.run(["git", "-C", str(root), "-c", "user.name=Proof", "-c",
                    "user.email=proof@example.test", "commit", "-qm", "old"], check=True)
    old = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    subprocess.run(["git", "-C", str(root), "rm", "-q", "app/Bridging/Reelcut-Bridging-Header.h",
                    "core/include/reelcut_core.h"], check=True)
    write(root / "app/Sources/A.swift", "let history = 1\n")
    write(root / "app/Bridging/FrameJob-Bridging-Header.h", "// old header\n")
    write(root / "core/include/framejob_core.h", "// old C API\n")
    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
    subprocess.run(["git", "-C", str(root), "-c", "user.name=Proof", "-c",
                    "user.email=proof@example.test", "commit", "-qm", "one"], check=True)
    first = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    write(root / "app/Sources/A.swift", "let history = 2\n")
    subprocess.run(["git", "-C", str(root), "add", "."], check=True)
    subprocess.run(["git", "-C", str(root), "-c", "user.name=Proof", "-c",
                    "user.email=proof@example.test", "commit", "-qm", "two"], check=True)
    second = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    write(root / "core/target/release/libframejob_core.a", "current library")
    harness = folder / "main.swift"
    caller = folder / "caller.py"
    fonts = folder / "Fonts"
    write(harness, "let instrument = 1\n")
    write(caller, "# caller 1\n")
    write(fonts / "face.otf", "font 1\n")
    return root, old, first, second, harness, caller, fonts


def mutation(path):
    old = path.read_bytes()
    stamp = path.stat()
    changed = old.replace(b"1", b"2", 1) if b"1" in old else old[:-1] + bytes([old[-1] ^ 1])
    insist(len(changed) == len(old) and changed != old, f"same-size mutation {path.name}")
    path.write_bytes(changed)
    os.utime(path, ns=(stamp.st_atime_ns, stamp.st_mtime_ns))


def unit():
    with tempfile.TemporaryDirectory(prefix="framejob-ref-unit-") as temporary:
        folder = Path(temporary)
        tools = folder / "tools"
        tools.mkdir()
        fake_tools(tools)
        root, old, first, second, harness, caller, fonts = fixture(folder)
        builder_copy = folder / "reference_build.py"
        shutil.copyfile(reference_build.__file__, builder_copy)
        original_file = reference_build.__file__
        old_env = os.environ.copy()
        os.environ["PATH"] = str(tools) + os.pathsep + old_env["PATH"]
        os.environ["FAKE_EVENTS"] = str(folder / "events")
        os.environ["RC_ASSEMBLYAI_KEY"] = "must-not-reach-compiler"
        before = folder / "before"
        current_lib = root / "core/target/release/libframejob_core.a"
        reference_build.__file__ = str(builder_copy)
        try:
            def build(commit=first, defines=()):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    answer = reference_build.build_reference(root=str(root), before=str(before),
                        commit=commit, harness_main=str(harness), fonts=str(fonts),
                        proof_script=str(caller), defines=defines)
                return answer, output.getvalue()

            def events():
                return (folder / "events").read_text().splitlines()

            (binary, sha, note), message = build()
            insist(binary and sha == first and note.startswith("this tree's own")
                   and "built" in message and len(events()) == 2, "cold build and matching archive")
            stamp = json.loads((before / "stamp.json").read_text())
            insist(set(stamp) == {"version", "key", "commit", "note", "tree_sha256", "binary_sha256"}
                   and all(len(stamp[k]) == 64 for k in ("key", "tree_sha256", "binary_sha256")),
                   "stamp contract and digests")
            binary_mtime = Path(binary).stat().st_mtime_ns
            stamp_mtime = (before / "stamp.json").stat().st_mtime_ns
            (_, _, _), message = build()
            insist("cache hit" in message and len(events()) == 2
                   and Path(binary).stat().st_mtime_ns == binary_mtime
                   and (before / "stamp.json").stat().st_mtime_ns == stamp_mtime,
                   "warm hit preserves outputs")

            for label, path in (("instrument", harness), ("current source", root / "app/Sources/A.swift"),
                                ("current header", root / "core/include/framejob_core.h"),
                                ("current library", current_lib), ("font", fonts / "face.otf"),
                                ("caller", caller), ("builder", builder_copy)):
                old_count = len(events())
                mutation(path)
                (rebuilt, _, _), message = build()
                insist(rebuilt and "built" in message and len(events()) == old_count + 2,
                       f"{label} content invalidates cache")
            write(root / "app/Sources/New.swift", "let added = true\n")
            old_count = len(events())
            build()
            insist(len(events()) == old_count + 2, "source membership invalidates cache")
            os.environ["RUSTFLAGS"] = "-C debuginfo=0"
            old_count = len(events())
            build()
            insist(len(events()) == old_count + 2, "effective Rust override invalidates cache")
            os.environ.pop("RUSTFLAGS")
            for name in ("CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS",
                         "CARGO_PROFILE_RELEASE_OPT_LEVEL"):
                _, message = build()
                _, message = build()
                insist("cache hit" in message, f"warm cache before {name} override")
                for value in ("fixture-one", "fixture-two"):
                    old_count = len(events())
                    os.environ[name] = value
                    (rebuilt, _, _), message = build()
                    insist(rebuilt and "built" in message and len(events()) == old_count + 2,
                           f"{name}={value} invalidates warm cache")
                    old_count = len(events())
                    _, message = build()
                    insist("cache hit" in message and len(events()) == old_count,
                           f"{name}={value} warms cache")
                os.environ.pop(name)
            (rebuilt, sha, _), message = build(second)
            insist(rebuilt and sha == second and "built" in message
                   and (before / "tree/app/Sources/A.swift").read_text() == "let history = 2\n",
                   "reference commit changes archive")
            for label, damage in (("corrupt stamp", lambda: (before / "stamp.json").write_text("{")),
                                  ("missing binary", lambda: Path(binary).unlink()),
                                  ("altered archive", lambda: (before / "tree/app/Sources/A.swift").write_text("bad")),
                                  ("altered font", lambda: (before / "Fonts/face.otf").write_text("bad"))):
                old_count = len(events())
                damage()
                (rebuilt, _, _), message = build(second)
                insist(rebuilt and "built" in message and len(events()) == old_count + 2,
                       f"{label} invalidates cache")
            (before / "stamp.json").unlink()
            lib_digest = hashlib.sha256(current_lib.read_bytes()).hexdigest()
            lib_mtime = current_lib.stat().st_mtime_ns
            os.environ["FAKE_SWIFT_FAIL"] = "1"
            (failed, _, diagnostic), _ = build(second)
            insist(failed is None and "rc_project_apply" in diagnostic
                   and not (before / "stamp.json").exists(), "compile failure has no success stamp")
            os.environ.pop("FAKE_SWIFT_FAIL")
            (retried, _, _), _ = build(second)
            insist(retried and (before / "stamp.json").exists(), "failed build retries cleanly")
            insist(hashlib.sha256(current_lib.read_bytes()).hexdigest() == lib_digest
                   and current_lib.stat().st_mtime_ns == lib_mtime,
                   "historical builds leave current staticlib unchanged")

            first_tree = subprocess.check_output(["git", "-C", str(root), "rev-parse",
                                                  f"{first}^{{tree}}"], text=True).strip()
            old_count = len(events())
            (from_tree, sha, _), message = build(first_tree)
            insist(from_tree and sha == first_tree and "built" in message
                   and len(events()) == old_count + 2
                   and (before / "tree/app/Sources/A.swift").read_text() == "let history = 1\n"
                   and not (before / "tree/graphic").exists(),
                   "a tree id resolves and builds that tree, with no graphic/ when it has none")
            (_, _, _), message = build(first_tree)
            insist("cache hit" in message and len(events()) == old_count + 2,
                   "a tree id's build is cached")

            write(root / "graphic/src/lib.rs", "// old graphics engine\n")
            write(root / "graphic/Cargo.toml", "[package]\nname = 'graphic'\n")
            subprocess.run(["git", "-C", str(root), "add", "graphic"], check=True)
            graphic_tree = subprocess.check_output(["git", "-C", str(root), "write-tree"],
                                                   text=True).strip()
            (with_graphic, sha, _), message = build(graphic_tree)
            insist(with_graphic and sha == graphic_tree and "built" in message
                   and (before / "tree/graphic/src/lib.rs").read_text()
                   == "// old graphics engine\n",
                   "a tree with graphic/ archives it beside its core")

            def swift_line():
                return [line for line in events() if line.startswith("swiftc ")][-1]

            (defined, _, _), message = build(graphic_tree, ("PROBE_ONE",))
            insist(defined and "built" in message and "-D PROBE_ONE" in swift_line(),
                   "a define reaches the swiftc line and invalidates the cache")
            old_count = len(events())
            _, message = build(graphic_tree, ("PROBE_ONE",))
            insist("cache hit" in message and len(events()) == old_count,
                   "the same define is a cache hit")
            (changed, _, _), message = build(graphic_tree, ("PROBE_TWO",))
            insist(changed and "built" in message and len(events()) == old_count + 2
                   and "-D PROBE_TWO" in swift_line() and "PROBE_ONE" not in swift_line(),
                   "a changed define invalidates the cache")

            # Rename R1 (spec §11 NM-6): each tree is built under its own names.
            def names_used(line):
                words = line.split()
                return (words[words.index("-module-name") + 1],
                        Path(words[words.index("-import-objc-header") + 1]).name,
                        [w for w in words if w.startswith("-l")],
                        [words[i + 1] for i, w in enumerate(words) if w == "-D"])

            (built_old, _, _), _ = build(old, ("FRAMEJOB_DEV_TOOLS",))
            seen = names_used(swift_line())
            insist(built_old and reference_build.tree_names(before / "tree")
                   == reference_build.OLD_NAMES
                   and seen == ("Reelcut", "Reelcut-Bridging-Header.h", ["-lreelcut_core"],
                                ["HARNESS_REFERENCE_BUILD", "REELCUT_DEV_TOOLS"]),
                   f"an old-named tree builds under its own names: {seen}")
            (built_new, _, _), _ = build(second, ("FRAMEJOB_DEV_TOOLS",))
            seen = names_used(swift_line())
            insist(built_new and reference_build.tree_names(before / "tree")
                   == reference_build.NEW_NAMES
                   and seen == ("FrameJob", "FrameJob-Bridging-Header.h", ["-lframejob_core"],
                                ["HARNESS_REFERENCE_BUILD", "FRAMEJOB_DEV_TOOLS"]),
                   f"a new-named tree builds under the new names: {seen}")
        finally:
            reference_build.__file__ = original_file
            os.environ.clear()
            os.environ.update(old_env)


def consumer_unit():
    import phase5_chrome as phase5
    import recording_probe as recording

    drift = "app/Sources/ReelCore.swift: rc_project_apply: injected compiler failure"
    with tempfile.TemporaryDirectory(prefix="framejob-ref-consumer-") as temporary:
        with patch.object(phase5, "CHROME", temporary), \
             patch.object(phase5, "build_harness", return_value=(None, drift)), \
             patch.object(phase5, "gain_checks", side_effect=lambda: phase5.check("independent gain", True)):
            phase5.RESULTS.clear()
            with contextlib.redirect_stdout(io.StringIO()) as output:
                try:
                    phase5.main()
                except SystemExit as error:
                    status = error.code
            text = output.getvalue()
            insist(status != 0 and "FAIL: the current harness builds" in text
                   and "PASS: independent gain" in text and "SKIPPED" not in text,
                   "phase 5 current-build failure is scored; independent gain runs")

        phase5.RESULTS.clear()
        with patch.object(phase5, "CHROME", temporary), \
             patch.object(phase5, "BEFORE", str(Path(temporary) / "before")), \
             patch.object(phase5, "build_harness", return_value=("current", None)), \
             patch.object(phase5, "build_reference", return_value=(None, "revision", drift)), \
             patch.object(phase5, "write_package", return_value="fixture.framejob"), \
             patch.object(phase5, "reading_checks", side_effect=lambda _: phase5.check("independent meter", True)), \
             patch.object(phase5, "gain_checks", side_effect=lambda: phase5.check("independent gain", True)):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                try:
                    phase5.main()
                except SystemExit as error:
                    status = error.code
            text = output.getvalue()
            insist(status != 0 and "FAIL: the reference tree built" in text
                   and "PASS: independent meter" in text and "PASS: independent gain" in text
                   and "SKIPPED" not in text, "phase 5 FFI-text failure is scored, not skipped")

        def welcome_failure(current):
            recording.failed = 0
            recording.passed = 0
            recording.skipped = 0
            recording.skips.clear()
            with patch.object(recording, "BEFORE", str(Path(temporary) / "recording-before")), \
                 patch.object(recording, "RENDERS", str(Path(temporary) / "renders")), \
                 patch.object(recording, "run_probe", return_value=({"buttons": []}, None)), \
                 patch.object(recording, "build_harness", return_value=(None, [drift]) if current else ("current", None)), \
                 patch.object(recording, "build_reference", return_value=(None, "revision", drift)):
                with contextlib.redirect_stdout(io.StringIO()) as output:
                    recording.section_welcome("probe", recording.TREE_SOURCES)
            text = output.getvalue()
            insist(recording.failed >= 2 and "FAIL 6b: the reference tree built" in text
                   and ("FAIL 6b: the tree's harness builds" in text) == current
                   and not recording.skips,
                   f"recording {'current and reference' if current else 'reference'} FFI-text failures score")

        welcome_failure(False)
        welcome_failure(True)


def integration():
    import phase5_chrome as phase5
    import recording_probe as recording

    with tempfile.TemporaryDirectory(prefix="framejob-ref-integration-") as temporary:
        folder = Path(temporary)
        mutated = folder / "main.swift"
        mutated.write_text(Path(phase5.HARNESS_MAIN).read_text()
                           + '\n#if HARNESS_REFERENCE_BUILD\n#error("reference instrument mutation")\n#endif\n')
        originals = (phase5.CHROME, phase5.BEFORE, phase5.HARNESS_MAIN,
                     recording.BEFORE, recording.RENDERS, recording.HARNESS_MAIN)
        phase5.CHROME = str(folder / "chrome")
        phase5.BEFORE = str(folder / "chrome/before")
        phase5.HARNESS_MAIN = str(mutated)
        recording.BEFORE = str(folder / "recording/before")
        recording.RENDERS = str(folder / "recording/welcome")
        recording.HARNESS_MAIN = str(mutated)
        try:
            phase5.RESULTS.clear()
            with contextlib.redirect_stdout(io.StringIO()) as output:
                try:
                    phase5.main()
                except SystemExit as error:
                    status = error.code
            text = output.getvalue()
            insist(status != 0 and "FAIL: the reference tree built" in text
                   and "reference instrument mutation" in text and "SKIPPED" not in text,
                   "real compiler failure scores phase 5 without a historical skip")
            print(text[-1800:])

            recording.failed = 0
            recording.passed = 0
            recording.skipped = 0
            recording.skips.clear()
            probe, error = recording.build_probe(recording.TREE_SOURCES)
            insist(probe is not None, f"current recording probe builds: {error}")
            with contextlib.redirect_stdout(io.StringIO()) as output:
                recording.section_welcome(probe, recording.TREE_SOURCES)
            text = output.getvalue()
            insist(recording.failed >= 2 and "FAIL 6b: the reference tree built" in text
                   and "reference instrument mutation" in text and not recording.skips,
                   "real compiler failure scores recording welcome without a historical skip")
            print(text[-1800:])
            insist(not (Path(phase5.BEFORE) / "stamp.json").exists()
                   and not (Path(recording.BEFORE) / "stamp.json").exists(),
                   "failed reference builds publish no cache stamp")
        finally:
            (phase5.CHROME, phase5.BEFORE, phase5.HARNESS_MAIN,
             recording.BEFORE, recording.RENDERS, recording.HARNESS_MAIN) = originals


if __name__ == "__main__":
    args = argparse.ArgumentParser()
    args.add_argument("--integration", action="store_true")
    options = args.parse_args()
    try:
        unit()
        consumer_unit()
        if options.integration:
            integration()
    except Exception as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
