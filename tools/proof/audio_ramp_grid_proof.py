#!/usr/bin/env python3
"""kpgalligan/framejob#355 — the Audio inspector's Fade in, Fade out and
Ducking Attack and Release store the length typed, off the frame grid; the
fade handle's drag and Reveal's rows still snap (spec §11 #355).

    python3 tools/proof/audio_ramp_grid_proof.py
    python3 tools/proof/audio_ramp_grid_proof.py --baseline <commit>

One instrument, the probe `audio_ramp_grid_probe.swift`, compiled AS
`main.swift` over every file in `app/Sources` but the app's own `main.swift`
on `swift_build.py`'s line (a probe that will not build is a scored FAILURE,
never an exit). On a 30 fps canvas, where a frame is 20 000 ticks: A1–A4
commit 0.01 s / 0.11 s / 0.01 s / 0.26 s through Ducking ▸ Attack, Ducking ▸
Release, Fades ▸ Fade in and Fades ▸ Fade out, and pass only when the one op
heard carries 6000 / 66000 / 6000 / 156000 ticks and the document stores
that; A5 commits 10 ms through Compressor ▸ Attack (6000, its own converter);
G1–G2 drag the fade-in and fade-out handles (`FadeHandleSession`) 6000 and
156000 ticks from their edge, which must snap to 0 and 160000; G3 commits
0.26 s through Reveal ▸ In, which must still snap to 160000.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources app/Bridging` and exits 0 only when A1–A4 FAIL there (the old
rows snapped) and A5, G1–G3 pass.
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
WORK = os.path.join(HERE, "work", "audio-ramp-grid")
PROBE_SWIFT = os.path.join(HERE, "audio_ramp_grid_probe.swift")

GROUPS = ["A1", "A2", "A3", "A4", "A5", "G1", "G2", "G3"]
SNAPPED = {"A1", "A2", "A3", "A4"}  # the rows the old tree must fail

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    """`av`: a video with sound, clip 2; `text`: a text clip, clip 2."""
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    return {
        "av": e2.write_package("audio-ramp-grid-av", e2.project(
            [ci.media_clip(2, 91, 0, [], video=True)], media=[ci2.movie(91, True)])),
        "text": e2.write_package("audio-ramp-grid-text", e2.project([ci2.text_clip(2)])),
    }


def build_probe(sources, out):
    os.makedirs(out, exist_ok=True)
    entry = os.path.join(out, "main.swift")
    with open(PROBE_SWIFT) as f:
        source = f.read()
    current = None
    if os.path.exists(entry):
        with open(entry) as f:
            current = f.read()
    if current != source:
        with open(entry, "w") as f:
            f.write(source)
    binary = os.path.join(out, "audio-ramp-grid-probe")
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
    print("\n1 — the probe: A1–A5 the Audio inspector's ramps, G1–G3 what still snaps")
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
    # A missing or doubled row is a scored failure of its own; a full set
    # adds no row, so the count is the build row and the eight.
    if not (all(sum(1 for r in rows if r["name"].startswith(g + " ")) == 1 for g in GROUPS)
            and len(rows) == len(GROUPS)):
        check("the probe answers every row, one each (A1–A5, G1–G3)", False,
              f"{len(rows)} rows: {[r['name'].split(' ')[0] for r in rows]}")
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
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    failed = {n.split(" ")[0] for n, ok in RESULTS if not ok}
    if failed == SNAPPED:
        print(f"BASELINE PASS: exactly A1–A4 failed on {commit} (the old rows snapped), "
              f"{elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: want exactly A1–A4 failed on {commit}, got "
          f"{sorted(failed)}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#355 — the Audio inspector's ramps off the frame grid; the handle and Reveal snap")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
