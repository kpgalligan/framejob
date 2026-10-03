#!/usr/bin/env python3
"""Issue batch B75 (#223) — the LaunchServices registrations of Reelcut
bundles, and the ones whose folder is gone.

    python3 tools/proof/stale_registrations.py                 # list (read only)
    python3 tools/proof/stale_registrations.py --unregister    # OPT-IN, see below
    python3 tools/proof/stale_registrations.py --under PATH    # either mode, PATH only
    python3 tools/proof/stale_registrations.py --selftest      # S1–S3

Xcode and `/usr/bin/open` register every `.app` they build or launch, and a
proof that deleted its copy without `lsregister -u` left the registration
behind (the proofs now delete through `tree_copy.remove_tree`). This lists
what is left: it parses `lsregister -dump` (bounded at 120 s) for every
record whose identifier contains `reelcut` (any case), dedupes them by
(identifier, path), and prints the totals (all, at missing paths, at
existing paths) and each missing path with its identifier.

`--unregister` runs `lsregister -u` ONLY on a path where `os.path.lexists`
is false, re-checked just before each call; an existing path is never
touched. It is the owner's to run: no proof calls it, and nothing here runs
it without the flag. `--under PATH` limits both modes to paths under PATH.

`--selftest`, in a `mkdtemp` of its own: a bundle with the identifier
`com.kgalligan.reelcut.lsselftest.<pid>` registered with `lsregister -f`.

* S1 — the dump lists it;
* S2 — after the bundle is deleted and the unregister path runs with
  `--under` the temp folder, the dump no longer lists it;
* S3 (CONTROL) — the count of registrations OUTSIDE the temp folder is the
  same before S1 and after S2: nothing else was unregistered.

Exit 0, or 1 for a failed row or a dump that could not be read.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

PROOF = os.path.dirname(os.path.abspath(__file__))
if PROOF not in sys.path:
    sys.path.insert(0, PROOF)
from mcp import LSREGISTER  # noqa: E402

DUMP_TIMEOUT = 120
CALL_TIMEOUT = 60
SEPARATOR = re.compile(r"^-{20,}$")
FIELD = re.compile(r"^(path|identifier):\s+(.*?)\s*$")
HANDLE = re.compile(r"\s+\(0x[0-9a-fA-F]+\)$")


def registrations():
    """`[(identifier, path)]`, deduped and sorted, for every dump record whose
    identifier contains `reelcut`; or `(None, reason)` when the dump fails."""
    try:
        done = subprocess.run([LSREGISTER, "-dump"], capture_output=True, text=True,
                              errors="replace", timeout=DUMP_TIMEOUT)
    except subprocess.TimeoutExpired:
        return None, f"lsregister -dump took longer than {DUMP_TIMEOUT} s"
    except OSError as error:
        return None, f"lsregister -dump could not run: {error}"
    if done.returncode != 0:
        return None, f"lsregister -dump exited {done.returncode}"
    found = set()
    record = {}

    def close():
        identifier, path = record.get("identifier"), record.get("path")
        if identifier and path and "reelcut" in identifier.lower():
            found.add((identifier, path))

    for line in done.stdout.splitlines():
        if SEPARATOR.match(line):
            close()
            record = {}
            continue
        match = FIELD.match(line)
        if match and match.group(1) not in record:
            record[match.group(1)] = HANDLE.sub("", match.group(2))
    close()
    return sorted(found), None


def is_under(path, under):
    if under is None:
        return True
    for one, root in ((path, under),
                      (os.path.realpath(path), os.path.realpath(under))):
        root = root.rstrip("/")
        if one == root or one.startswith(root + "/"):
            return True
    return False


def unregister_missing(entries, under):
    """`lsregister -u` on each path in `entries` under `under` that does not
    exist, re-checked just before the call. Answers `[(path, rc)]`."""
    done = []
    for path in sorted({path for _identifier, path in entries}):
        if not is_under(path, under) or os.path.lexists(path):
            continue
        try:
            rc = subprocess.run([LSREGISTER, "-u", path], capture_output=True,
                                timeout=CALL_TIMEOUT).returncode
        except (subprocess.TimeoutExpired, OSError):
            rc = None
        done.append((path, rc))
    return done


def report(under, unregister):
    entries, reason = registrations()
    if entries is None:
        print(f"the registrations could not be read: {reason}")
        return 1
    entries = [entry for entry in entries if is_under(entry[1], under)]
    missing = [entry for entry in entries if not os.path.lexists(entry[1])]
    scope = f" under {under}" if under else ""
    print(f"reelcut registrations{scope}: {len(entries)} — "
          f"{len(missing)} at missing paths, {len(entries) - len(missing)} at existing paths")
    for identifier, path in missing:
        print(f"  missing  {path}  ({identifier})")
    if unregister:
        done = unregister_missing(missing, under)
        for path, rc in done:
            print(f"  lsregister -u {path} → {'timeout' if rc is None else rc}")
        print(f"unregistered {len(done)} missing path(s); existing paths untouched")
    elif missing:
        print("(read only; --unregister removes the missing paths' registrations, "
              "and only those)")
    return 0


def selftest():
    rows = []

    def row(ident, ok, detail):
        rows.append(ok)
        print(f"{ident} {'ok' if ok else 'FAIL'} — {detail}")

    identifier = f"com.kgalligan.reelcut.lsselftest.{os.getpid()}"
    temp = tempfile.mkdtemp(prefix="rc-lsselftest-")
    app = os.path.join(temp, "LSSelftest.app")
    try:
        before, reason = registrations()
        if before is None:
            row("S0", False, reason)
            print(f"{sum(rows)}/{len(rows)}")
            return 1
        outside_before = {tuple(e) for e in before if not is_under(e[1], temp)}
        os.makedirs(os.path.join(app, "Contents", "MacOS"))
        with open(os.path.join(app, "Contents", "Info.plist"), "w") as handle:
            handle.write(
                '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n'
                "<key>CFBundleExecutable</key><string>lsselftest</string>\n"
                f"<key>CFBundleIdentifier</key><string>{identifier}</string>\n"
                "<key>CFBundlePackageType</key><string>APPL</string>\n"
                "</dict></plist>\n")
        script = os.path.join(app, "Contents", "MacOS", "lsselftest")
        with open(script, "w") as handle:
            handle.write("#!/bin/sh\nexit 0\n")
        os.chmod(script, 0o755)
        try:
            rc = subprocess.run([LSREGISTER, "-f", app], capture_output=True,
                                timeout=CALL_TIMEOUT).returncode
        except (subprocess.TimeoutExpired, OSError) as error:
            rc = repr(error)

        # S1
        listed, reason = registrations()
        mine = [e for e in (listed or []) if e[0] == identifier]
        row("S1", bool(mine),
            f"lsregister -f exited {rc}; the dump lists {mine}" if mine
            else f"lsregister -f exited {rc}; the dump does not list {identifier}"
            + (f" ({reason})" if reason else ""))

        # S2
        shutil.rmtree(app, ignore_errors=True)
        done = unregister_missing(listed or [], temp)
        after, reason = registrations()
        left = [e for e in (after or []) if e[0] == identifier]
        row("S2", after is not None and not left,
            f"after the bundle went and {len(done)} unregister call(s) under {temp}, "
            + (f"the dump still lists {left}" if left else
               f"the dump no longer lists it" if after is not None else reason))

        # S3 (CONTROL)
        # Only a DISAPPEARED entry fails it: another session may register an app meanwhile.
        outside_after = {tuple(e) for e in (after or []) if not is_under(e[1], temp)}
        gone = sorted(outside_before - outside_after)
        row("S3", after is not None and not gone,
            f"CONTROL: registrations outside the temp folder {len(outside_before)} before, "
            f"{len(outside_after)} after" + (f"; gone: {gone}" if gone else ""))
    except Exception as error:  # an instrument that cannot run is a FAIL
        row("S9", False, f"the selftest raised {error!r}")
    finally:
        if os.path.isdir(app):
            subprocess.run([LSREGISTER, "-u", app], capture_output=True, timeout=CALL_TIMEOUT)
        shutil.rmtree(temp, ignore_errors=True)
    print(f"{sum(rows)}/{len(rows)}")
    return 0 if all(rows) else 1


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--unregister", action="store_true",
                        help="lsregister -u the registrations at MISSING paths only")
    parser.add_argument("--under", metavar="PATH",
                        help="only registrations at paths under PATH")
    parser.add_argument("--selftest", action="store_true", help="S1–S3 in a mkdtemp")
    arguments = parser.parse_args(argv)
    if arguments.selftest:
        return selftest()
    return report(arguments.under, arguments.unregister)


if __name__ == "__main__":
    sys.exit(main())
