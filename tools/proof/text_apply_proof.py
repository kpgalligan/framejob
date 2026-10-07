#!/usr/bin/env python3
"""kpgalligan/reelcut#37 — Return applies in the canvas text editor, and Esc
asks before dropping a change (spec §11 K-2).

    python3 tools/proof/text_apply_proof.py
    python3 tools/proof/text_apply_proof.py --baseline 7e946ed

One instrument, the probe `text_apply_probe.swift`, compiled AS `main.swift`
over every file in `app/Sources` but the app's own `main.swift` on
`swift_build.py`'s line (a probe that will not build is a scored
FAILURE, never an exit). K1 asks `TextEditKey.route` row by row; A0–A11 open
the in-canvas editor over one text clip "Hello" in the app's own window, send
Return, modified Returns and Esc through `NSWindow.sendEvent`, press the
sheet's buttons, and read back the clip's content, the editor, the sheet and
the undo stack. A0 and A7 are CONTROLS.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (K1 compiled out) and exits 0
only when EXACTLY the labels in `BASELINE_EXPECTED` fail there and no K1 row
is present — the fix is what those rows measure, and the CONTROLS must pass on
both trees.
"""

import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (the helpers: project, write_package)
import text_edit_proof as te  # noqa: E402  (text_clip)
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "text-apply")
PROBE_SWIFT = os.path.join(HERE, "text_apply_probe.swift")
# The editor's window builds the app's Metal compositor, which loads
# `default.metallib` from the directory a bare swiftc binary is in
# (`mixed_audio_probe.py`'s `build_shader`).
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")

# The labels that fail on the baseline, as the run printed them.
BASELINE_EXPECTED = ["A1", "A10", "A11", "A2", "A4", "A6", "A8", "A9"]

GROUPS = ["A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7", "A8", "A9", "A10", "A11"]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    """`auto`: one text clip "Hello", id 2, auto-sized and centred."""
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    return {"auto": e2.write_package("text-apply", e2.project([te.text_clip("Hello")]))}


# ---------------------------------------------------------------------------
# The probe.


def build_shader(out):
    """The app's own `Compositor.metal` beside the binary."""
    lib = os.path.join(out, "default.metallib")
    air = os.path.join(out, "Compositor.air")
    if os.path.exists(lib) and os.path.getmtime(SHADER) < os.path.getmtime(lib):
        return lib, None
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", SHADER, "-o", air],
                          capture_output=True, text=True)
    if step.returncode != 0:
        return None, "xcrun metal failed: " + step.stderr.strip()[:300]
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metallib", air, "-o", lib],
                          capture_output=True, text=True)
    if step.returncode != 0 or not os.path.exists(lib):
        return None, "xcrun metallib failed: " + step.stderr.strip()[:300]
    return lib, None


def build_probe(sources, out, reference=False):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "text-apply-probe")
    shader, why = build_shader(out)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    defines = ["HARNESS_REFERENCE_BUILD"] if reference else []
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
    print("\n1 — the probe: K1 the route, A0–A11 the app's own window")
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
    result = subprocess.run([binary, request, answer], capture_output=True, text=True,
                            timeout=300)
    if result.returncode != 0 or not os.path.exists(answer):
        check("the probe runs", False, (result.stdout + result.stderr).strip()[-400:])
        return None
    with open(answer) as f:
        rows = json.load(f)["rows"]
    groups = GROUPS if reference else ["K1"] + GROUPS
    check(f"the probe answers every row ({', '.join(groups)} present, one row per A label)",
          all(any(r["name"].startswith(g + " ") for r in rows) for g in groups)
          and all(sum(1 for r in rows if r["name"].startswith(g + " ")) == 1
                  for g in GROUPS),
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
    archive = subprocess.run(["git", "-C", ROOT, "archive", commit, "app/Sources"],
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
    absent = [r["name"] for r in rows if r["name"].startswith("K1 ")]
    structural = [n for n, ok in RESULTS if not ok and not n.startswith("A")]
    if failed == sorted(BASELINE_EXPECTED) and not absent and not structural:
        print(f"BASELINE PASS: exactly {', '.join(sorted(BASELINE_EXPECTED))} FAILED on "
              f"{commit} and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: failed {failed} (want {sorted(BASELINE_EXPECTED)}), K1 rows "
          f"present {absent}, other failures {structural}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#37 — Return applies in the canvas text editor; Esc asks before dropping a change")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
