#!/usr/bin/env python3
"""kpgalligan/framejob#357 — the inspector's props are edited by copy-and-
mutate, and the seventeen tri-state (`T??`) patch keys are written by one
helper; neither moves an op byte.

    python3 tools/proof/props_mutate_proof.py
    python3 tools/proof/props_mutate_proof.py --baseline f1dce3011f951bfea6e5aa20753c331b88d3179c

One instrument, the probe `props_mutate_probe.swift`, compiled AS `main.swift`
over every file in `app/Sources` but the app's own `main.swift` on
`swift_build.py`'s line (a probe that will not build is a scored FAILURE,
never an exit). N1–N17 build each tri-state key's patch at `.none`,
`.some(nil)` and `.some(v)` (motion also at `.some(MotionProps())`) and
compare the ops' JSON to literals taken from the probe's output on
f1dce3011f951bfea6e5aa20753c331b88d3179c, the tree before #357. W1–W9 commit
one value through one inspector row each (Chroma, Reflection, Spotlight,
Obscure, Gradient, Outline, Backdrop, Reveal, Ducking) over a clip whose
object has every field away from its default, and compare the ops the row
sends to the whole object rebuilt through its memberwise initialiser.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources app/Bridging` and exits 0 only when EVERY row passes there too:
the literals are the old tree's bytes, and the old rows already kept every
field.
"""

import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (clip, project, write_package, GREY)
import clip_inspector_proof as ci  # noqa: E402  (media_clip)
import clip_inspector2_proof as ci2  # noqa: E402  (movie, text_clip)
import swift_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "props-mutate")
PROBE_SWIFT = os.path.join(HERE, "props_mutate_probe.swift")

GROUPS = [f"N{i}" for i in range(1, 18)] + [f"W{i}" for i in range(1, 10)]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    """`av`: a video with sound, clip 2; `text`: a text clip, clip 2;
    `shape`: a grey card, clip 2."""
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    return {
        "av": e2.write_package("props-mutate-av", e2.project(
            [ci.media_clip(2, 91, 0, [], video=True)], media=[ci2.movie(91, True)])),
        "text": e2.write_package("props-mutate-text", e2.project([ci2.text_clip(2)])),
        "shape": e2.write_package("props-mutate-shape", e2.project(
            [e2.clip(2, 0, e2.GREY, duration=6 * e2.TICKS)])),
    }


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    if not os.path.exists(entry) or open(entry).read() != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "props-mutate-probe")
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libframejob_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    try:
        built = swift_build.build(sources=swift + [entry], output=binary)
    except swift_build.SwiftBuildFailed as error:
        errors = [line for line in error.diagnostics if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["(no error lines)"])
    if not built.reused:
        print(f"  probe built in {built.seconds:.0f} s")
    return binary, None


def probe_checks(sources, out, paths):
    print("\n1 — the probe: N1–N17 the tri-state keys' bytes, W1–W9 one row write each")
    binary, error = build_probe(sources, out)
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
    check(f"the probe answers every row, one each ({GROUPS[0]}–N17, W1–W9)",
          all(sum(1 for r in rows if r["name"].startswith(g + " ")) == 1 for g in GROUPS)
          and len(rows) == len(GROUPS),
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
    print(f"BASELINE {commit}: app/Sources in {os.path.relpath(tree, ROOT)}")
    rows = probe_checks(os.path.join(tree, "app", "Sources"),
                        os.path.join(tree, "out"), packages())
    elapsed = time.time() - began
    if rows is None:
        print(f"BASELINE FAILURE: the probe did not build or run over {commit}, "
              f"{elapsed:.0f} s")
        return 1
    failed = [n for n, ok in RESULTS if not ok]
    if not failed:
        print(f"BASELINE PASS: every row passed on {commit}, {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: {len(failed)} failed on {commit}: {failed}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#357 — props edited by copy-and-mutate; tri-state keys through one writer")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
