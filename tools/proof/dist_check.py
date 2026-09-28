#!/usr/bin/env python3
"""Road map 11 V0 and road map 12 A4 — the binary check `make dist` runs.

The Distribution configuration is Release without the Swift condition
`REELCUT_DEV_TOOLS` (spec §11 V-1), so its binary must hold none of the dev
tools' code. This reads each app's `Contents/MacOS/Reelcut` in process, as
bytes, and looks for ONE needle: the `devToolsMarker` literal declared in
`app/Sources/AgentServer+DevTools.swift`, read out of that file at every run.

    python3 tools/proof/dist_check.py [--release APP] [--dist APP]

**Why a marker and not the tool names.** Swift string literals of 15 UTF-8
bytes or fewer are stored inline in the code of an `-O` binary, not as
contiguous bytes (`RC_AGENT_PORT`, 13, and `unsaved_changes`, 15, are found 0
times in the Release binary; `AgentServerEnabled`, 18, once), so a short tool
name could never be found in either build and an absence check on it would
pass for nothing. The marker is at least 16 bytes, and the flag-on
`devTools()` logs it, which keeps the literal live in the optimised binary.

**The helper (road map 12 A4).** Both bundles carry the assistant helper,
`Contents/Helpers/reelcut-agent`, which `agent/build.sh helper` copies in and
signs `--options runtime` with `agent/entitlements.plist` before Xcode signs
the app. Without `com.apple.security.cs.allow-jit` under the hardened runtime
the helper dies at launch; with more, it holds a right it does not need. The
rows check `runtime` in the CodeDirectory flags, not `adhoc`, so a Developer
ID signature passes too. `codesign -dv` writes its display to stderr, so the
flags are read there; the entitlements are read from stdout.

The thirteen rows, none ever skipped:

* D1 — the needle is read from the seam file: exactly one bare declaration
  line, ASCII, at least 16 UTF-8 bytes;
* D2 — the Release binary exists;
* D3 — the Distribution binary exists;
* D4 — the Release binary holds the needle: the POSITIVE CONTROL, without
  which an absence check passes against a build that never had it;
* D5 — the Distribution binary does not hold the needle;
* D6 / D7 — the Release / Distribution helper exists;
* D8 / D9 — it is signed with the hardened runtime (`runtime` in the
  CodeDirectory flags) and `codesign --verify --strict` accepts it;
* D10 / D11 — its entitlements are exactly `com.apple.security.cs.allow-jit`;
* D12 / D13 — it does not hold the needle.

If D1 fails, D4, D5, D12 and D13 FAIL too, and so does each when its binary
or helper is missing. A missing `codesign`, a timeout or output that does not
parse FAILs the row with the reason. `tools/proof/dist_check_mutants.py`
makes each helper row fail on purpose. The last line is
`dist_check: <passed>/13`; the exit is 0 only at 13/13.
"""

import argparse
import os
import plistlib
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEAM = os.path.join(ROOT, "app", "Sources", "AgentServer+DevTools.swift")
DEFAULT_RELEASE = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
DEFAULT_DIST = os.path.join(ROOT, "build", "Build", "Products", "Distribution", "Reelcut.app")

# The declaration line, bare: nothing after the closing quote.
DECLARATION = re.compile(r'^\s*static let devToolsMarker = "([^"\\\n]+)"\s*$', re.M)
# Below this, the literal is stored inline in code and never found as bytes.
MIN_BYTES = 16
# The assistant helper, inside each bundle; its one entitlement (agent/entitlements.plist).
HELPER = os.path.join("Contents", "Helpers", "reelcut-agent")
ENTITLEMENTS = {"com.apple.security.cs.allow-jit": True}
TOTAL = 13
# The CodeDirectory line's flags; `Executable Segment flags=0x1` has no parentheses.
FLAGS = re.compile(r"flags=0x[0-9a-fA-F]+\(([^)]*)\)")
TIMEOUT = 120

passed = 0
failed = 0


def check(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print(f"  ok   {name}")
    else:
        failed += 1
        print(f"  FAIL {name}" + (f"\n       {detail}" if detail else ""))


def read_needle():
    """The marker's bytes, or None with the reason."""
    try:
        with open(SEAM, encoding="utf-8") as handle:
            text = handle.read()
    except OSError as error:
        return None, f"cannot read {SEAM}: {error}"
    matches = DECLARATION.findall(text)
    if len(matches) != 1:
        return None, f"{len(matches)} bare `static let devToolsMarker = \"…\"` lines in {SEAM}"
    marker = matches[0]
    if not marker.isascii():
        return None, f"the marker {marker!r} is not ASCII"
    needle = marker.encode("utf-8")
    if len(needle) < MIN_BYTES:
        return None, f"the marker {marker!r} is {len(needle)} bytes, under {MIN_BYTES}"
    return needle, ""


def read_binary(app):
    """The app's executable's bytes, or None with the reason."""
    path = os.path.join(app, "Contents", "MacOS", "Reelcut")
    try:
        with open(path, "rb") as handle:
            return handle.read(), path
    except OSError as error:
        return None, f"{path}: {error}"


def read_helper(app):
    """The app's helper's bytes, or None with the reason."""
    path = os.path.join(app, HELPER)
    try:
        with open(path, "rb") as handle:
            return handle.read(), path
    except OSError as error:
        return None, f"{path}: {error}"


def child_env():
    """This process's environment without either product key, for every child."""
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    return env


def run_codesign(arguments):
    """`codesign` with the arguments: (completed process, None) or (None, the reason)."""
    try:
        return subprocess.run(["codesign"] + arguments, capture_output=True,
                              timeout=TIMEOUT, env=child_env()), None
    except FileNotFoundError:
        return None, "codesign is not on PATH"
    except subprocess.TimeoutExpired:
        return None, f"codesign {' '.join(arguments[:-1])} timed out after {TIMEOUT} s"
    except OSError as error:
        return None, f"codesign: {error}"


def helper_runtime(path):
    """Whether the helper is signed with the hardened runtime and verifies strictly."""
    shown, reason = run_codesign(["-dv", "--verbose=4", path])
    if shown is None:
        return False, reason
    stderr = shown.stderr.decode("utf-8", "replace")
    if shown.returncode != 0:
        return False, f"codesign -dv exit {shown.returncode}: {stderr.strip()[:300]}"
    match = FLAGS.search(stderr)
    if match is None:
        return False, "no `flags=0x…(…)` in codesign -dv's display"
    flags = [flag.strip() for flag in match.group(1).split(",")]
    if "runtime" not in flags:
        return False, f"CodeDirectory flags ({match.group(1)}) lack runtime in {path}"
    verified, reason = run_codesign(["--verify", "--strict", path])
    if verified is None:
        return False, reason
    if verified.returncode != 0:
        return False, (f"codesign --verify --strict exit {verified.returncode}: "
                       f"{verified.stderr.decode('utf-8', 'replace').strip()[:300]}")
    return True, f"flags ({match.group(1)})"


def helper_entitlements(path):
    """Whether the helper's entitlements are exactly ENTITLEMENTS."""
    shown, reason = run_codesign(["-d", "--entitlements", "-", "--xml", path])
    if shown is None:
        return False, reason
    if shown.returncode != 0:
        return False, (f"codesign -d --entitlements exit {shown.returncode}: "
                       f"{shown.stderr.decode('utf-8', 'replace').strip()[:300]}")
    try:
        held = plistlib.loads(shown.stdout)
    except Exception as error:  # plistlib raises several kinds on bad input
        return False, f"the entitlements do not parse ({type(error).__name__}: {error}) in {path}"
    if held != ENTITLEMENTS:
        return False, f"entitlements {held!r} in {path}"
    return True, ""


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default=DEFAULT_RELEASE, help="the Release Reelcut.app")
    parser.add_argument("--dist", default=DEFAULT_DIST, help="the Distribution Reelcut.app")
    arguments = parser.parse_args()

    needle, needle_reason = read_needle()
    print("road map 11 V0 and road map 12 A4 — no dev tools in Distribution; "
          "the helper signed in both\n")
    print(f"  needle:       {needle.decode('ascii') if needle else '(none)'}")
    print(f"  release:      {os.path.abspath(arguments.release)}")
    print(f"  distribution: {os.path.abspath(arguments.dist)}\n")

    check("D1 the needle is one bare devToolsMarker line, ASCII, at least "
          f"{MIN_BYTES} bytes", needle is not None, needle_reason)

    release, release_where = read_binary(arguments.release)
    check("D2 the Release binary exists", release is not None, release_where)
    dist, dist_where = read_binary(arguments.dist)
    check("D3 the Distribution binary exists", dist is not None, dist_where)

    if needle is None:
        check("D4 the Release binary holds the needle (the positive control)", False,
              "no needle (D1)")
        check("D5 the Distribution binary does not hold the needle", False, "no needle (D1)")
    else:
        if release is None:
            check("D4 the Release binary holds the needle (the positive control)", False,
                  "no Release binary (D2)")
        else:
            count = release.count(needle)
            check(f"D4 the Release binary holds the needle (the positive control; {count} "
                  "occurrences)", count > 0, f"0 occurrences in {release_where}")
        if dist is None:
            check("D5 the Distribution binary does not hold the needle", False,
                  "no Distribution binary (D3)")
        else:
            count = dist.count(needle)
            check("D5 the Distribution binary does not hold the needle", count == 0,
                  f"{count} occurrences in {dist_where}")

    sides = (("Release", "D6", "D8", "D10", "D12", arguments.release),
             ("Distribution", "D7", "D9", "D11", "D13", arguments.dist))
    helpers = {}
    for side, exists_id, _, _, _, app in sides:
        helper, helper_where = read_helper(app)
        helpers[side] = (helper, helper_where)
        check(f"{exists_id} the {side} helper exists", helper is not None, helper_where)
    for side, exists_id, runtime_id, _, _, _ in sides:
        helper, helper_where = helpers[side]
        name = f"{runtime_id} the {side} helper is signed with the hardened runtime"
        if helper is None:
            check(name, False, f"no {side} helper ({exists_id})")
        else:
            ok, detail = helper_runtime(helper_where)
            check(name, ok, "" if ok else detail)
    for side, exists_id, _, entitlements_id, _, _ in sides:
        helper, helper_where = helpers[side]
        name = (f"{entitlements_id} the {side} helper's entitlements are exactly "
                "com.apple.security.cs.allow-jit")
        if helper is None:
            check(name, False, f"no {side} helper ({exists_id})")
        else:
            ok, detail = helper_entitlements(helper_where)
            check(name, ok, detail)
    for side, exists_id, _, _, needle_id, _ in sides:
        helper, helper_where = helpers[side]
        name = f"{needle_id} the {side} helper does not hold the needle"
        if needle is None:
            check(name, False, "no needle (D1)")
        elif helper is None:
            check(name, False, f"no {side} helper ({exists_id})")
        else:
            count = helper.count(needle)
            check(name, count == 0, f"{count} occurrences in {helper_where}")

    print(f"\ndist_check: {passed}/{TOTAL}")
    return 0 if passed == TOTAL else 1


if __name__ == "__main__":
    sys.exit(main())
