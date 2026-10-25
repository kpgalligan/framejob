#!/usr/bin/env python3
"""kpgalligan/framejob#345 — both canvas text commits send their `set_text`
through `TextPatch.contentEdit` (spec §11 W-2), so a word-count change on a
word-timed page lands untimed instead of erroring.

    python3 tools/proof/canvas_text_commit_proof.py
    python3 tools/proof/canvas_text_commit_proof.py --baseline 0038186

One instrument, the probe `canvas_text_commit_probe.swift`, compiled AS
`main.swift` over every file in `app/Sources` but the app's own `main.swift`
on `swift_build.py`'s line (a probe that will not build is a scored FAILURE,
never an exit). C0 (a CONTROL) opens the in-canvas editor over one text clip
"so here's the thing" that the probe has timed with four word timings; W1–W5
commit an edit by Return, by the Esc sheet's Apply and by a blur, and read
back the page's content, its timings, the sheet and the undo stack; P1 asks
`PreviewCanvasView.textCommitOp` directly.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources app/Bridging` with `-D HARNESS_REFERENCE_BUILD` (P1 compiled out)
and exits 0 only when EXACTLY the labels in `BASELINE_EXPECTED` fail there and
no P1 row is present: each of W1, W3 and W5 catches its own commit path's bare
`TextPatch(content:)`, and C0, W2 and W4 must pass on both trees.
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
import text_apply_proof as ta  # noqa: E402  (build_shader)
import reference_build  # noqa: E402
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "canvas-text-commit")
PROBE_SWIFT = os.path.join(HERE, "canvas_text_commit_probe.swift")

# The labels that fail on the baseline: the three commits of a word-count
# change, one per commit path (Return, the sheet's Apply, a blur).
BASELINE_EXPECTED = ["W1", "W3", "W5"]

GROUPS = ["C0", "W1", "W2", "W3", "W4", "W5"]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    """`page`: one text clip "so here's the thing", id 2, auto-sized and
    centred; the probe times it."""
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    return {"page": e2.write_package("canvas-text-commit",
                                     e2.project([te.text_clip("so here's the thing")]))}


def build_probe(sources, out, reference=False):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "canvas-text-commit-probe")
    shader, why = ta.build_shader(out, os.path.dirname(os.path.dirname(sources)))
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
    print("\n1 — the probe: C0 and W1–W5 the app's own window, P1 the helper")
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
    groups = GROUPS if reference else GROUPS + ["P1"]
    check(f"the probe answers every row ({', '.join(groups)} present, one row per C and "
          "W label)",
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
    absent = [r["name"] for r in rows if r["name"].startswith("P1 ")]
    structural = [n for n, ok in RESULTS
                  if not ok and not n.startswith(("C", "W"))]
    if failed == sorted(BASELINE_EXPECTED) and not absent and not structural:
        print(f"BASELINE PASS: exactly {', '.join(sorted(BASELINE_EXPECTED))} FAILED on "
              f"{commit} and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: failed {failed} (want {sorted(BASELINE_EXPECTED)}), P1 rows "
          f"present {absent}, other failures {structural}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#345 — both canvas text commits go through TextPatch.contentEdit (W-2)")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
