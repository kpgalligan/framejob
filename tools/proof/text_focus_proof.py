#!/usr/bin/env python3
"""Spec §11 K-4 — typing in the editor window is focus-averse.

    python3 tools/proof/text_focus_proof.py
    python3 tools/proof/text_focus_proof.py --baseline d4537dc

One instrument, the probe `text_focus_probe.swift`, compiled AS `main.swift`
over every file in `app/Sources` but the app's own `main.swift` on
`swift_build.py`'s line (a probe that will not build is a scored FAILURE,
never an exit). F1 asks `TextFocus` row by row; F2 drives the app's own
editor window with synthesized keys and clicks and reads the first
responder, each field's commit and whether Space then plays; F3 is the
Assistant composer's Return in a window of its own. F2z scores the host's
premise for the window's Tab rows: Full Keyboard Access off (with it on, Tab
is AppKit's key-view loop by K-4's exception, which F1 asks directly).

The fixture and the shader are `space_key_proof.py`'s (the card, then 6 s of
`media/A.mov`, so the transport has an item to play), written under this
proof's own work folder.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (F1 compiled out) and exits 0
only when EXACTLY the rows in `BASELINE_EXPECTED` fail there and no F1 row is
present — the rows that measure K-4, failing on the tree before it; the
others (the toolbar timecode's Return and ⇧Tab, a click inside the field,
an option field's margin, a refused send) are guards that held before and
must still hold.

The probe runs with a DUMMY key in a `-RCSecretFolder` of its own (so the
composer shows), `-FrameJobInspectorCollapsed NO`, and ANTHROPIC_API_KEY and
RC_ASSEMBLYAI_KEY popped from its environment: no person's key is read.
"""

import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import reference_build  # noqa: E402
import space_key_proof as space  # noqa: E402  (the card fixture, the shader)
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "text-focus")
PROBE_SWIFT = os.path.join(HERE, "text_focus_probe.swift")

# Measured over d4537dc, the tree before K-4: F2b the toolbar timecode's Tab
# (the next key view, the canvas overlay, took it); F2d the clip header's
# name on Return (committed, then its field editor re-attached, so Space was
# typed into it); F2e the same name on a click on the timeline (nothing
# committed, the field editor kept); F2g an option field's Tab; F2i–F2j the
# Text tab's area's Return (a new line) and Tab; F2k the composer's Tab; F3a
# the composer after a send. F2a and F2c held there too — the toolbar
# timecode's own delegate already handed the keys back on Return and ⇧Tab —
# and stay as guards.
BASELINE_EXPECTED = ["F2b", "F2d", "F2e", "F2g", "F2i", "F2j", "F2k", "F3a"]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    space.WORK = WORK
    return space.packages()


def build_probe(sources, out, reference=False):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "text-focus-probe")
    shader, why = space.build_shader(out, os.path.dirname(os.path.dirname(sources)))
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    defines = reference_build.tree_defines(os.path.dirname(os.path.dirname(sources)),
                                           ["HARNESS_REFERENCE_BUILD"] if reference else [])
    try:
        built = swift_build.build(sources=swift + [entry], output=binary, defines=defines)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["(no error lines)"])
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s")
    return binary, None


def probe_checks(sources, out, paths, reference=False):
    print("\n1 — the probe: F1 the rule, F2 the app's own window, F3 the composer's Return")
    check("media/A.mov exists (README \"Make the test media once\")", os.path.exists(space.MOVIE),
          space.MOVIE)
    binary, error = build_probe(sources, out, reference)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return None
    request = os.path.join(out, "request.json")
    answer = os.path.join(out, "answer.json")
    if os.path.exists(answer):
        os.remove(answer)
    with open(request, "w") as f:
        json.dump(paths, f, indent=2)
    secrets = os.path.join(out, "secrets")
    shutil.rmtree(secrets, ignore_errors=True)
    os.makedirs(secrets)
    with open(os.path.join(secrets, "anthropic-key"), "w") as f:
        f.write("text-focus-dummy-key\n")
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    result = subprocess.run([binary, request, answer, "-RCSecretFolder", secrets,
                             "-FrameJobInspectorCollapsed", "NO"],
                            capture_output=True, text=True, timeout=300, env=env)
    if result.returncode != 0 or not os.path.exists(answer):
        check("the probe runs", False, (result.stdout + result.stderr).strip()[-400:])
        return None
    with open(answer) as f:
        rows = json.load(f)["rows"]
    groups = ["F2z", "F2a", "F2b", "F2c", "F2d", "F2e", "F2f", "F2g", "F2h", "F2i", "F2j",
              "F2k", "F3a", "F3b"]
    if not reference:
        groups = ["F1"] + groups
    check(f"the probe answers every row group ({', '.join(groups)} present)",
          all(any(r["name"].startswith(g + " ") for r in rows) for g in groups),
          f"{len(rows)} rows")
    for row in rows:
        check(row["name"], row["ok"], row["detail"])
    return rows


def baseline(commit):
    began = time.time()
    tree = os.path.join(WORK, "baseline")
    if os.path.exists(tree):
        shutil.rmtree(tree)
    os.makedirs(tree)
    archive = subprocess.run(["git", "-C", ROOT, "archive", commit, "app/Sources",
                              "app/Bridging"],
                             capture_output=True)
    if archive.returncode != 0:
        print(f"BASELINE FAILURE: git archive {commit} failed: "
              f"{archive.stderr.decode(errors='replace').strip()}")
        return 1
    untar = subprocess.run(["tar", "-x", "-C", tree], input=archive.stdout,
                           capture_output=True)
    if untar.returncode != 0:
        print(f"BASELINE FAILURE: tar failed: {untar.stderr.decode(errors='replace').strip()}")
        return 1
    print(f"BASELINE {commit}: app/Sources in {os.path.relpath(tree, ROOT)}, built with "
          "-D HARNESS_REFERENCE_BUILD")
    rows = probe_checks(os.path.join(tree, "app", "Sources"),
                        os.path.join(tree, "out"), packages(), reference=True)
    elapsed = time.time() - began
    if rows is None:
        print(f"BASELINE FAILURE: the probe did not build or run over {commit}, "
              f"{elapsed:.0f} s")
        return 1
    failed = sorted({r["name"].split(" ")[0] for r in rows if not r["ok"]})
    absent = [r["name"] for r in rows if r["name"].startswith("F1 ")]
    structural = [n for n, ok in RESULTS if not ok and not n.startswith("F")]
    if failed == sorted(BASELINE_EXPECTED) and not absent and not structural:
        print(f"BASELINE PASS: exactly {', '.join(BASELINE_EXPECTED)} FAILED on {commit} and "
              f"nothing else did, {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: failed {failed} (want {sorted(BASELINE_EXPECTED)}), F1 rows "
          f"present {absent}, other failures {structural}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("K-4 — typing in the editor window is focus-averse")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
