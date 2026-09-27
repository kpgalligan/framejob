#!/usr/bin/env python3
"""Road map 11 V0 — the binary check `make dist` runs.

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

The five rows, none ever skipped:

* D1 — the needle is read from the seam file: exactly one bare declaration
  line, ASCII, at least 16 UTF-8 bytes;
* D2 — the Release binary exists;
* D3 — the Distribution binary exists;
* D4 — the Release binary holds the needle: the POSITIVE CONTROL, without
  which an absence check passes against a build that never had it;
* D5 — the Distribution binary does not hold the needle.

If D1 fails, D4 and D5 FAIL too, and so does either when its binary is
missing. The last line is `dist_check: <passed>/5`; the exit is 0 only at 5/5.
"""

import argparse
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SEAM = os.path.join(ROOT, "app", "Sources", "AgentServer+DevTools.swift")
DEFAULT_RELEASE = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app")
DEFAULT_DIST = os.path.join(ROOT, "build", "Build", "Products", "Distribution", "Reelcut.app")

# The declaration line, bare: nothing after the closing quote.
DECLARATION = re.compile(r'^\s*static let devToolsMarker = "([^"\\\n]+)"\s*$', re.M)
# Below this, the literal is stored inline in code and never found as bytes.
MIN_BYTES = 16

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


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default=DEFAULT_RELEASE, help="the Release Reelcut.app")
    parser.add_argument("--dist", default=DEFAULT_DIST, help="the Distribution Reelcut.app")
    arguments = parser.parse_args()

    needle, needle_reason = read_needle()
    print("road map 11 V0 — the dev tools are absent from Distribution\n")
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

    print(f"\ndist_check: {passed}/5")
    return 0 if passed == 5 else 1


if __name__ == "__main__":
    sys.exit(main())
