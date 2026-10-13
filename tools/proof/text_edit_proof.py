#!/usr/bin/env python3
"""kpgalligan/framejob#36 — the canvas text editor grows as you type.

    python3 tools/proof/text_edit_proof.py
    python3 tools/proof/text_edit_proof.py --baseline b76a2f3

One instrument, the probe `text_edit_probe.swift`, compiled AS `main.swift`
over every file in `app/Sources` but the app's own `main.swift` on
`swift_build.py`'s line (a probe that will not build is a scored
FAILURE, never an exit). It opens the in-canvas editor over a text clip in
the app's own window, types a string one key event at a time, then applies
each typed prefix and compares the editor's frame and line count after each
key with the box the canvas draws for the applied text: T1 an auto-sized
text, T2 a fixed-width one with a backdrop. T3 opens the editor over a
left-aligned string shorter than the editor's 60 × 24 pt floor and checks the
frame hangs from the box's top-left, where the text renders (it passes on the
baseline too, which hung the floor from that corner; it is there so a floor
widened about the box's centre fails).

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (nothing is compiled out: the
probe calls only what the baseline already had) and exits 0 only when EXACTLY
the rows in `BASELINE_EXPECTED` fail there — the fix is what those rows
measure, and the CONTROLS must pass on both trees.
"""

import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (the helpers: video_props, project, write_package)
import reference_build  # noqa: E402
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "text-edit")
PROBE_SWIFT = os.path.join(HERE, "text_edit_probe.swift")
# The editor's window builds the app's Metal compositor, which loads
# `default.metallib` from the directory a bare swiftc binary is in
# (`mixed_audio_probe.py`'s `build_shader`).
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
TICKS = e2.TICKS

# The four rows the fix is about; every CONTROL passes on both trees.
BASELINE_EXPECTED = [
    f"{group} after EVERY key the editor's frame is the applied box + 2 px, within 1.0 pt"
    for group in ["T1 auto-sized:", "T2 fixed width:"]
] + [
    f"{group} after EVERY key the editor shows as many lines as the applied text renders"
    for group in ["T1 auto-sized:", "T2 fixed width:"]
]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def text_clip(content, width=None, align="center", backdrop=None, size=96.0):
    return {
        "id": 2, "track": 1, "start": 0, "duration": 6 * TICKS,
        "source": {"kind": "text"}, "enabled": {"video": True, "audio": True},
        "speed": 1.0, "video": e2.video_props(), "audio": None,
        "text": {
            "content": content, "font": "SourceSans3-SemiBold", "size": size,
            "color": [1.0, 1.0, 1.0, 1.0], "align": align, "valign": "middle",
            "line_spacing": 1.0, "tracking": 0.0, "outline": None, "backdrop": backdrop,
            "width": width,
        },
        "shape": None, "actions": [], "transition_in": None, "name": None, "label": None,
    }


def packages():
    """`auto`: "Hello", auto-sized and centred. `fixed`: "Wrap me", 700 px
    wide, left-aligned, on a backdrop of 24 px padding — the padding is in
    the box and NOT in the wrap width, which is what T2's line rows test.
    `short`: "Hi", 12 px, auto-sized and left-aligned — a box under the
    editor's 60 × 24 pt floor, which is what T3 tests."""
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    plate = {"color": [0.0, 0.0, 0.0, 0.6], "padding": 24.0, "radius": 8.0}
    return {
        "fonts": os.path.join(ROOT, "app", "Resources", "Fonts"),
        "auto": e2.write_package("text-auto", e2.project([text_clip("Hello")])),
        "fixed": e2.write_package("text-fixed", e2.project(
            [text_clip("Wrap me", width=700.0, align="left", backdrop=plate)])),
        "short": e2.write_package("text-short", e2.project(
            [text_clip("Hi", align="left", size=12.0)])),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_shader(out, tree=ROOT):
    """The app's own `Compositor.metal` beside the binary, its entry points
    named as `tree`'s sources ask for them (`reference_build.tree_shader`)."""
    lib = os.path.join(out, "default.metallib")
    air = os.path.join(out, "Compositor.air")
    source = os.path.join(out, "Compositor.metal")
    with open(SHADER) as f:
        text = reference_build.tree_shader(tree, f.read())
    if not os.path.exists(source) or open(source).read() != text:
        with open(source, "w") as f:
            f.write(text)
    if os.path.exists(lib) and os.path.getmtime(source) < os.path.getmtime(lib):
        return lib, None
    step = subprocess.run(["xcrun", "-sdk", "macosx", "metal", "-c", source, "-o", air],
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
    binary = os.path.join(out, "text-edit-probe")
    shader, why = build_shader(out, os.path.dirname(os.path.dirname(sources)))
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
    print("\n1 — the probe: T1 auto-sized, T2 fixed width, T3 under the floor, in the app's "
          "own window")
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
    check("the probe answers every group (T0 1 row, T1 and T2 5 rows each, T3 2)",
          all(sum(1 for r in rows if r["name"].startswith(g + " ")) == n
              for g, n in [("T0", 1), ("T1", 5), ("T2", 5), ("T3", 2)]),
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
    failed = sorted(r["name"] for r in rows if not r["ok"])
    structural = [n for n, ok in RESULTS if not ok and not n.startswith("T")]
    if failed == sorted(BASELINE_EXPECTED) and not structural:
        print(f"BASELINE PASS: exactly the {len(BASELINE_EXPECTED)} expected rows FAILED on "
              f"{commit} and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: failed {failed} (want {sorted(BASELINE_EXPECTED)}), other "
          f"failures {structural}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#36 — the canvas text editor grows as you type")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
