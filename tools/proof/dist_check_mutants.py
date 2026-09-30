#!/usr/bin/env python3
"""Road map 12 A4 and #145 — `dist_check.py`'s helper rows (D6–D13) and D14, each made
to fail on purpose.

    python3 tools/proof/dist_check_mutants.py [--release APP] [--dist APP]

Every case runs `dist_check.py` as a child with one side a SKELETON bundle,
`work/dist_check_mutants/<case>/Reelcut.app`: `Contents/MacOS/Reelcut` a
symlink to the real app's untouched binary, `Contents/Helpers/reelcut-agent`
a COPY of the real helper (never a link), mutated and re-signed ad hoc. The
other side is the real app. Nothing is written into `build/`. The
`app-entitlements` case is the one whole bundle: the real Distribution app
`ditto`ed to `<case>/dist/Reelcut.app` and re-signed ad hoc with HEAD's pair
(`audio-input` and `get-task-allow`, #145), which D14 must refuse.

A case passes iff dist_check's FAIL ids equal the expected set exactly, its
last line is `dist_check: <14 - |set|>/14`, and it exits 0 for an empty set
and 1 otherwise. `control` (both real) and `skeleton` (both skeletons,
helpers copied untouched) expect nothing to fail: they prove the skeleton is
not itself a failure. A setup command that fails (a copy, a `codesign`, the
offset not found) is a scored FAIL naming it. Each case's directory is
removed after scoring. The last line is `dist_check_mutants: <passed>/12`;
the exit is 0 only at 12/12.
"""

import argparse
import os
import plistlib
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dist_check  # noqa: E402

ROOT = dist_check.ROOT
WORK = os.path.join(HERE, "work", "dist_check_mutants")
DIST_CHECK = os.path.join(HERE, "dist_check.py")
AGENT_ENTITLEMENTS = os.path.join(ROOT, "agent", "entitlements.plist")
ANCHOR = b"compaction_instructions"
FAIL_ID = re.compile(r"^  FAIL (D\d+)\b", re.M)
LAST = re.compile(r"dist_check: (\d+)/(\d+)\s*$")

# (case, the mutated side or sides, the mutation, the expected FAIL set)
CASES = [
    ("control", (), None, set()),
    ("skeleton", ("release", "dist"), None, set()),
    ("no-helper-release", ("release",), "no-helper", {"D6", "D8", "D10", "D12"}),
    ("no-helper-dist", ("dist",), "no-helper", {"D7", "D9", "D11", "D13"}),
    ("no-runtime-release", ("release",), "no-runtime", {"D8"}),
    ("no-runtime-dist", ("dist",), "no-runtime", {"D9"}),
    ("extra-entitlement-release", ("release",), "extra-entitlement", {"D10"}),
    ("extra-entitlement-dist", ("dist",), "extra-entitlement", {"D11"}),
    ("no-entitlements-dist", ("dist",), "no-entitlements", {"D11"}),
    ("marker-release", ("release",), "marker", {"D12"}),
    ("marker-dist", ("dist",), "marker", {"D13"}),
    ("app-entitlements-dist", ("dist",), "app-entitlements", {"D14"}),
]


class SetupError(Exception):
    pass


def sign(path, *options):
    """Re-sign the copy ad hoc with the options; a failure is a SetupError."""
    arguments = ["codesign", "--force", "--sign", "-", *options, path]
    try:
        done = subprocess.run(arguments, capture_output=True, timeout=120,
                              env=dist_check.child_env())
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(f"{' '.join(arguments)}: {error}")
    if done.returncode != 0:
        raise SetupError(f"{' '.join(arguments)} exit {done.returncode}: "
                         f"{done.stderr.decode('utf-8', 'replace').strip()[:300]}")


def skeleton(case_dir, side, real_app, mutation, needle):
    """A skeleton bundle for one side, its helper mutated; returns its path."""
    app = os.path.join(case_dir, side, "Reelcut.app")
    if mutation == "app-entitlements":
        try:
            done = subprocess.run(["ditto", real_app, app], capture_output=True, timeout=300,
                                  env=dist_check.child_env())
        except (OSError, subprocess.TimeoutExpired) as error:
            raise SetupError(f"ditto {real_app}: {error}")
        if done.returncode != 0:
            raise SetupError(f"ditto {real_app} exit {done.returncode}: "
                             f"{done.stderr.decode('utf-8', 'replace').strip()[:300]}")
        plist = os.path.join(case_dir, "app.plist")
        with open(plist, "wb") as handle:
            plistlib.dump({"com.apple.security.device.audio-input": True,
                           "com.apple.security.get-task-allow": True}, handle)
        sign(app, "--options", "runtime", "--entitlements", plist)
        return app
    macos = os.path.join(app, "Contents", "MacOS")
    os.makedirs(macos)
    binary = os.path.join(real_app, "Contents", "MacOS", "Reelcut")
    if not os.path.isfile(binary):
        raise SetupError(f"no binary at {binary}")
    os.symlink(binary, os.path.join(macos, "Reelcut"))
    if mutation == "no-helper":
        return app
    source = os.path.join(real_app, dist_check.HELPER)
    helper = os.path.join(app, dist_check.HELPER)
    os.makedirs(os.path.dirname(helper))
    try:
        shutil.copyfile(source, helper)
        os.chmod(helper, 0o755)
    except OSError as error:
        raise SetupError(f"copy {source}: {error}")
    if mutation == "no-runtime":
        sign(helper, "--entitlements", AGENT_ENTITLEMENTS)
    elif mutation == "extra-entitlement":
        extra = os.path.join(case_dir, "extra.plist")
        with open(extra, "wb") as handle:
            plistlib.dump({"com.apple.security.cs.allow-jit": True,
                           "com.apple.security.cs.disable-library-validation": True}, handle)
        sign(helper, "--options", "runtime", "--entitlements", extra)
    elif mutation == "no-entitlements":
        sign(helper, "--options", "runtime")
    elif mutation == "marker":
        with open(helper, "r+b") as handle:
            data = handle.read()
            offset = data.find(ANCHOR)
            if offset < 0:
                raise SetupError(f"{ANCHOR.decode()} not found in the helper copy")
            handle.seek(offset)
            handle.write(needle)
        sign(helper, "--options", "runtime", "--entitlements", AGENT_ENTITLEMENTS)
    return app


def run_case(name, sides, mutation, expected, real, needle):
    """Score one case: (ok, the line to print)."""
    case_dir = os.path.join(WORK, name)
    shutil.rmtree(case_dir, ignore_errors=True)
    os.makedirs(case_dir)
    try:
        apps = dict(real)
        try:
            for side in sides:
                apps[side] = skeleton(case_dir, side, real[side], mutation, needle)
        except (SetupError, OSError) as error:
            return False, f"setup: {error}"
        try:
            done = subprocess.run([sys.executable, DIST_CHECK, "--release", apps["release"],
                                   "--dist", apps["dist"]], capture_output=True, text=True,
                                  timeout=300, env=dist_check.child_env())
        except (OSError, subprocess.TimeoutExpired) as error:
            return False, f"dist_check did not finish: {error}"
        failed = set(FAIL_ID.findall(done.stdout))
        last = LAST.search(done.stdout)
        want_passed = dist_check.TOTAL - len(expected)
        want_rc = 0 if not expected else 1
        got = (f"FAIL {{{', '.join(sorted(failed, key=lambda d: int(d[1:])))}}}, "
               f"{last.group(0).strip() if last else 'no last line'}, rc {done.returncode}")
        ok = (failed == expected and last is not None
              and int(last.group(1)) == want_passed and int(last.group(2)) == dist_check.TOTAL
              and done.returncode == want_rc)
        if ok:
            return True, got
        want = (f"want FAIL {{{', '.join(sorted(expected, key=lambda d: int(d[1:])))}}}, "
                f"dist_check: {want_passed}/{dist_check.TOTAL}, rc {want_rc}")
        return False, f"{got}; {want}" + (f"\n       stderr: {done.stderr.strip()[:300]}"
                                          if done.stderr.strip() else "")
    finally:
        shutil.rmtree(case_dir, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default=dist_check.DEFAULT_RELEASE,
                        help="the Release Reelcut.app")
    parser.add_argument("--dist", default=dist_check.DEFAULT_DIST,
                        help="the Distribution Reelcut.app")
    arguments = parser.parse_args()
    real = {"release": os.path.abspath(arguments.release),
            "dist": os.path.abspath(arguments.dist)}

    print("road map 12 A4 — dist_check's helper rows, each made to fail on purpose\n")
    print(f"  release:      {real['release']}")
    print(f"  distribution: {real['dist']}\n")
    needle, reason = dist_check.read_needle()
    passed = 0
    for name, sides, mutation, expected in CASES:
        if needle is None:
            ok, line = False, f"no needle: {reason}"
        else:
            ok, line = run_case(name, sides, mutation, expected, real, needle)
        passed += ok
        print(f"  {'ok  ' if ok else 'FAIL'} {name} — {line}")
    shutil.rmtree(WORK, ignore_errors=True)
    print(f"\ndist_check_mutants: {passed}/{len(CASES)}")
    return 0 if passed == len(CASES) else 1


if __name__ == "__main__":
    sys.exit(main())
