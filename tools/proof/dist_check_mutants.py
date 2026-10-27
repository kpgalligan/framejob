#!/usr/bin/env python3
"""Road map 12 A4, #145, road map 14 MC3, B88 and Sparkle — `dist_check.py`'s helper rows
(D6–D13), D14, the MCP proxy's and snapshot's rows (D15–D24), the Release entitlements and
seal rows (D25–D27) and the updater's rows (D28–D32 and D35, spec §11 PUB-6..PUB-9), each
made to fail on purpose.

    python3 tools/proof/dist_check_mutants.py [--release APP] [--dist APP]

Every case runs `dist_check.py` as a child with one side a SKELETON bundle,
`work/dist_check_mutants/<case>/Frame Job.app`: `Contents/MacOS/Frame Job` a
symlink to the real app's untouched binary, and COPIES (never links) of the
real `Contents/Info.plist`, `Contents/Helpers/framejob-agent`,
`Contents/Helpers/framejob-mcp` and `Contents/Resources/agent-catalog.json`,
and a `ditto` copy of the real `Contents/Frameworks/Sparkle.framework`, for
every mutation: the helper or the proxy mutated and re-signed ad hoc, the
snapshot removed, re-versioned or swapped for the OTHER side's, the
framework removed, its binary's signature removed (`sparkle-unsigned`) or its
first helper (`dist_check.sparkle_helper_paths`' order) re-signed ad hoc
without the hardened runtime, or the Info.plist copy's `SUFeedURL` emptied
(`feed-empty`), its `SUPublicEDKey` made base64 of 31 bytes (`key-short`) or,
in Release's, its `SUFeedURL` set to Distribution's (`release-feed`). The
other side is the real app. Nothing is written into `build/`. Five cases
mutate a whole bundle, the real app `ditto`ed to `<case>/<side>/Frame Job.app`:
`app-entitlements` re-signs Distribution ad hoc with
`dist_check.APP_ENTITLEMENTS` plus `get-task-allow` (#145), which D14 must
refuse for the `get-task-allow` alone; `app-entitlements-mic-only` re-signs
Release with `dist_check.APP_ENTITLEMENTS` alone — Distribution's exact set
(`audio-input` and, since camera-recording CR1a, `camera`) without
`get-task-allow`; the name is kept from when that set was the microphone
alone — which D25's exact set must refuse (a "contains" check would pass
it); `noop-sign`
does to Release what a no-op build did before issue batch B88's fix — `codesign
-s - -f` of the executable alone, then a byte appended to
`agent-catalog.json` — which D25 (no entitlements) and D26 (the seal) must
refuse; `seal-broken` appends a byte to Distribution's `agent-catalog.json`
after signing, which D27 must refuse while D14 still passes; `sparkle-load`
restores the Sparkle load command Release's `-dead_strip_dylibs` drops (spec
§11 PUB-7): `install_name_tool -change` turns the first of Release's load
commands at least as long as Distribution's Sparkle one into it, then the
bundle is re-signed ad hoc with the hardened runtime and
`dist_check.RELEASE_ENTITLEMENTS`, which D35 alone must refuse.

A case passes iff dist_check's FAIL ids equal the expected set exactly, its
last line is `dist_check: <35 - |set|>/35`, and it exits 0 for an empty set
and 1 otherwise. `control` (both real) and `skeleton` (both skeletons,
helpers, proxies and snapshots copied untouched) expect nothing to fail: they
prove the skeleton is not itself a failure. A setup command that fails (a
copy, a `codesign`, the offset not found) is a scored FAIL naming it. Each
case's directory is removed after scoring. The last line is
`dist_check_mutants: <passed>/30`; the exit is 0 only at 30/30.

The control needs a Distribution build whose `SUPublicEDKey` passes D31: until
the owner's key lands, build Distribution with a stand-in 32-byte key on the
command line (`RC_SPARKLE_PUBLIC_KEY=AAAA…AAA=`, `tools/proof/README.md`).
"""

import argparse
import base64
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dist_check  # noqa: E402
import proof_app  # noqa: E402

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
    ("no-proxy-release", ("release",), "no-proxy", {"D15", "D17", "D19"}),
    ("no-proxy-dist", ("dist",), "no-proxy", {"D16", "D18", "D20"}),
    ("proxy-no-runtime-dist", ("dist",), "proxy-no-runtime", {"D18"}),
    ("proxy-entitlement-release", ("release",), "proxy-entitlement", {"D19"}),
    ("no-snapshot-dist", ("dist",), "no-snapshot", {"D22", "D24"}),
    ("snapshot-version-release", ("release",), "snapshot-version", {"D21"}),
    ("dist-snapshot-in-release", ("release",), "other-snapshot", {"D23"}),
    ("release-snapshot-in-dist", ("dist",), "other-snapshot", {"D24"}),
    ("app-entitlements-mic-only-release", ("release",), "app-entitlements-mic-only", {"D25"}),
    ("noop-sign-release", ("release",), "noop-sign", {"D25", "D26"}),
    ("seal-broken-dist", ("dist",), "seal-broken", {"D27"}),
    ("sparkle-missing-dist", ("dist",), "sparkle-missing", {"D28", "D29"}),
    ("sparkle-unsigned-dist", ("dist",), "sparkle-unsigned", {"D28"}),
    ("sparkle-helper-no-runtime-dist", ("dist",), "sparkle-helper-no-runtime", {"D29"}),
    ("feed-empty-dist", ("dist",), "feed-empty", {"D30"}),
    ("key-short-dist", ("dist",), "key-short", {"D31"}),
    ("release-feed", ("release",), "release-feed", {"D32"}),
    ("sparkle-load-release", ("release",), "sparkle-load", {"D35"}),
]
# The cases that mutate a whole `ditto`ed bundle rather than a skeleton.
WHOLE = {"app-entitlements", "app-entitlements-mic-only", "noop-sign", "seal-broken",
         "sparkle-load"}
OTHER = {"release": "dist", "dist": "release"}


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


def copy_in(source, target, mode=None):
    """Copy one file of the real bundle into the skeleton; a failure is a SetupError."""
    try:
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(source, target)
        if mode is not None:
            os.chmod(target, mode)
    except OSError as error:
        raise SetupError(f"copy {source}: {error}")


def run_tool(arguments, what):
    """Run a setup tool; a failure is a SetupError naming `what`."""
    try:
        done = subprocess.run(arguments, capture_output=True, timeout=300,
                              env=dist_check.child_env())
    except (OSError, subprocess.TimeoutExpired) as error:
        raise SetupError(f"{what}: {error}")
    if done.returncode != 0:
        raise SetupError(f"{what} exit {done.returncode}: "
                         f"{done.stderr.decode('utf-8', 'replace').strip()[:300]}")


def info_plist(app, real_app, other_app, mutation):
    """The skeleton's Info.plist, a COPY of the real bundle's, its updater keys mutated
    (spec §11 PUB-6..PUB-8, D30–D32)."""
    target = os.path.join(app, dist_check.INFO_PLIST)
    copy_in(os.path.join(real_app, dist_check.INFO_PLIST), target)
    if mutation not in ("feed-empty", "key-short", "release-feed"):
        return
    try:
        with open(target, "rb") as handle:
            info = plistlib.load(handle)
        if mutation == "feed-empty":
            info["SUFeedURL"] = ""
        elif mutation == "key-short":
            info["SUPublicEDKey"] = base64.b64encode(b"\1" * 31).decode("ascii")
        else:
            with open(os.path.join(other_app, dist_check.INFO_PLIST), "rb") as handle:
                info["SUFeedURL"] = plistlib.load(handle)["SUFeedURL"]
        with open(target, "wb") as handle:
            plistlib.dump(info, handle)
    except (OSError, KeyError, ValueError, plistlib.InvalidFileException) as error:
        raise SetupError(f"rewrite {target}: {error}")


def sparkle(app, real_app, mutation):
    """The skeleton's Sparkle.framework, a `ditto` copy of the real bundle's, its binary
    or its first helper mutated (spec §11 PUB-7, D28/D29)."""
    if mutation == "sparkle-missing":
        return
    framework = os.path.join(app, dist_check.SPARKLE)
    run_tool(["ditto", os.path.join(real_app, dist_check.SPARKLE), framework],
             f"ditto {os.path.join(real_app, dist_check.SPARKLE)}")
    if mutation == "sparkle-unsigned":
        binary = os.path.realpath(os.path.join(framework, "Sparkle"))
        run_tool(["codesign", "--remove-signature", binary],
                 f"codesign --remove-signature {binary}")
    elif mutation == "sparkle-helper-no-runtime":
        helpers = dist_check.sparkle_helper_paths(framework)
        if not helpers:
            raise SetupError(f"no helper under {framework}")
        sign(helpers[0])


def sparkle_load(app, real, case_dir):
    """Give the `ditto`ed bundle's executable a Sparkle load command, Distribution's own,
    in place of the first of its load commands at least as long (spec §11 PUB-7, D35);
    then re-sign the bundle as Release is signed."""
    binary = os.path.realpath(str(proof_app.executable(app)))
    dist_paths, reason = dist_check.load_commands(str(proof_app.executable(real["dist"])))
    if dist_paths is None:
        raise SetupError(f"Distribution's load commands: {reason}")
    wanted = [path for path in dist_paths if dist_check.SPARKLE_LOAD in path]
    if len(wanted) != 1:
        raise SetupError(f"{len(wanted)} Sparkle load commands in the Distribution binary")
    paths, reason = dist_check.load_commands(binary)
    if paths is None:
        raise SetupError(f"the copy's load commands: {reason}")
    room = [path for path in paths if len(path) >= len(wanted[0])
            and dist_check.SPARKLE_LOAD not in path]
    if not room:
        raise SetupError(f"no load command in {binary} as long as {wanted[0]}")
    run_tool(["install_name_tool", "-change", room[0], wanted[0], binary],
             f"install_name_tool -change {room[0]}")
    plist = os.path.join(case_dir, "release.plist")
    with open(plist, "wb") as handle:
        plistlib.dump(dist_check.RELEASE_ENTITLEMENTS, handle)
    sign(app, "--options", "runtime", "--entitlements", plist)


def proxy_and_snapshot(case_dir, app, real_app, other_app, mutation):
    """The skeleton's Info.plist, MCP proxy and snapshot, each a COPY of the real
    bundle's, the proxy or the snapshot mutated (road map 14 MC3, D15–D24)."""
    info_plist(app, real_app, other_app, mutation)
    if mutation != "no-proxy":
        proxy = os.path.join(app, dist_check.PROXY)
        copy_in(os.path.join(real_app, dist_check.PROXY), proxy, 0o755)
        if mutation == "proxy-no-runtime":
            sign(proxy)
        elif mutation == "proxy-entitlement":
            extra = os.path.join(case_dir, "proxy.plist")
            with open(extra, "wb") as handle:
                plistlib.dump({"com.apple.security.cs.allow-jit": True}, handle)
            sign(proxy, "--options", "runtime", "--entitlements", extra)
    if mutation == "no-snapshot":
        return
    snapshot = os.path.join(app, dist_check.SNAPSHOT)
    source = other_app if mutation == "other-snapshot" else real_app
    copy_in(os.path.join(source, dist_check.SNAPSHOT), snapshot)
    if mutation == "snapshot-version":
        try:
            with open(snapshot, encoding="utf-8") as handle:
                value = json.load(handle)
            value["version"] = "0.0.0-mutant"
            with open(snapshot, "w", encoding="utf-8") as handle:
                json.dump(value, handle)
        except (OSError, ValueError, TypeError) as error:
            raise SetupError(f"rewrite {snapshot}'s version: {error}")


def skeleton(case_dir, side, real, mutation, needle):
    """A skeleton bundle for one side, its helper, proxy or snapshot mutated;
    returns its path."""
    real_app = real[side]
    app = os.path.join(case_dir, side, "Frame Job.app")
    if mutation in WHOLE:
        try:
            done = subprocess.run(["ditto", real_app, app], capture_output=True, timeout=300,
                                  env=dist_check.child_env())
        except (OSError, subprocess.TimeoutExpired) as error:
            raise SetupError(f"ditto {real_app}: {error}")
        if done.returncode != 0:
            raise SetupError(f"ditto {real_app} exit {done.returncode}: "
                             f"{done.stderr.decode('utf-8', 'replace').strip()[:300]}")
        if mutation == "sparkle-load":
            sparkle_load(app, real, case_dir)
            return app
        if mutation == "noop-sign":
            sign(str(proof_app.executable(app)))
        if mutation in ("noop-sign", "seal-broken"):
            try:
                with open(os.path.join(app, dist_check.SNAPSHOT), "ab") as handle:
                    handle.write(b"\n")
            except OSError as error:
                raise SetupError(f"append to the snapshot: {error}")
            return app
        held = dict(dist_check.APP_ENTITLEMENTS)
        if mutation == "app-entitlements":
            held["com.apple.security.get-task-allow"] = True
        plist = os.path.join(case_dir, "app.plist")
        with open(plist, "wb") as handle:
            plistlib.dump(held, handle)
        sign(app, "--options", "runtime", "--entitlements", plist)
        return app
    macos = os.path.join(app, "Contents", "MacOS")
    os.makedirs(macos)
    binary = str(proof_app.executable(real_app))
    if not os.path.isfile(binary):
        raise SetupError(f"no binary at {binary}")
    os.symlink(binary, os.path.join(macos, "Frame Job"))
    proxy_and_snapshot(case_dir, app, real_app, real[OTHER[side]], mutation)
    sparkle(app, real_app, mutation)
    if mutation == "no-helper":
        return app
    source = os.path.join(real_app, dist_check.HELPER)
    helper = os.path.join(app, dist_check.HELPER)
    copy_in(source, helper, 0o755)
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
                apps[side] = skeleton(case_dir, side, real, mutation, needle)
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
                        help="the Release Frame Job.app")
    parser.add_argument("--dist", default=dist_check.DEFAULT_DIST,
                        help="the Distribution Frame Job.app")
    arguments = parser.parse_args()
    real = {"release": os.path.abspath(arguments.release),
            "dist": os.path.abspath(arguments.dist)}

    print("road map 12 A4, #145, road map 14 MC3, B88 and spec §11 PUB-6..PUB-9 — "
          "dist_check's helper rows (D6–D13), D14, D15–D32 and D35, each made to fail on "
          "purpose\n")
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
