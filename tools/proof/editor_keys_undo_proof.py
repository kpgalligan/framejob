#!/usr/bin/env python3
"""Issue batch B3 — editor keys, undo steps, the transition ring
(kpgalligan/reelcut#59 #60 #61 #66 #68 #69).

    python3 tools/proof/editor_keys_undo_proof.py
    python3 tools/proof/editor_keys_undo_proof.py --baseline <commit>

One instrument, the probe `editor_keys_undo_probe.swift`, compiled AS
`main.swift` over every file in `app/Sources` but the app's own `main.swift`
on `harness/build.sh`'s swiftc line (a probe that will not build is a scored
FAILURE, never an exit). Its row groups:

  U  `performGroupedEdit` of an identity and of a refusal leaves undo and
     redo as they were (#59); U3 a real grouped edit, the control.
  F  after an inspector number field commits (Return) or cancels (Esc), a
     bare I / O acts with no click first (#60).
  C  bare keys with Caps Lock, and ↓ / End with the flags the keyboard sends
     (#61); C4 ⌘ ⌥ ⌃ stay out of the map, the control.
  R  the timeline rename field: Esc keeps the old name with no step; a rename
     ended by a click on a track's M is its own step (#69); R3 Return, the
     control.
  M  a Media-tab search that hides the selected row clears it, so Insert /
     Overwrite go dead (#68); M1 a matching search, the control.
  D  the selected clip's ring is not painted over by the NEXT clip's
     transition hatch (#66); D2 and D3 are controls.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD`, linked to the CURRENT
`libreelcut_core.a` (valid while the batch changes nothing under `core/`),
and exits 0 only when EXACTLY the rows in `BASELINE_EXPECTED` fail there and
every control passes.

The probe runs with `-ReelcutInspectorCollapsed NO`, and ANTHROPIC_API_KEY
and RC_ASSEMBLYAI_KEY popped from its environment.
"""

import json
import os
import shutil
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (the helpers: clip, project, write_package)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "editor-keys-undo")
PROBE_SWIFT = os.path.join(HERE, "editor_keys_undo_probe.swift")
# The editor composes through the app's Metal compositor, which loads
# `default.metallib` from the directory a bare swiftc binary is in
# (`mixed_audio_probe.py`'s `build_shader`).
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
MOVIE = os.path.join(HERE, "media", "A.mov")
TICKS = e2.TICKS

BASELINE_EXPECTED = ["U1", "U2", "F1", "F2", "F3", "C1", "C2", "C3", "R1", "R2", "M2", "D1"]
GROUPS = ["U", "F", "C", "R", "M", "D"]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    """`card` is `space_key_proof.packages()`'s fixture, written here; the
    three ring fixtures are shape cards on one track."""
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    movie = {"id": 20, "path": MOVIE, "kind": "video", "duration": 10 * TICKS,
             "width": 640, "height": 360, "fps": [30, 1], "has_video": True,
             "has_audio": False}
    tail = {
        "id": 3, "track": 1, "start": 6 * TICKS, "duration": 6 * TICKS,
        "source": {"kind": "media", "media": 20, "in": 0, "reversed": False},
        "enabled": {"video": True, "audio": True}, "speed": 1.0,
        "video": e2.video_props(), "audio": None, "text": None, "shape": None,
        "actions": [], "transition_in": None, "name": None, "label": None,
    }
    card = e2.project([e2.clip(2, 0, e2.GREY, name="Card", duration=6 * TICKS), tail],
                      media=[movie])
    blue = [0.2, 0.4, 0.8, 1.0]

    def a():
        return e2.clip(2, 0, e2.GREY, name="A", duration=6 * TICKS)

    def b(start, transition):
        clip = e2.clip(3, start, blue, name="B", duration=6 * TICKS)
        if transition:
            clip["transition_in"] = {"kind": "cross_dissolve", "curve": "linear",
                                     "audio": False}
        return clip

    return {
        "card": e2.write_package("card", card),
        "ringPair": e2.write_package("ring-pair", e2.project([a(), b(4 * TICKS, True)])),
        "ringAlone": e2.write_package("ring-alone", e2.project([a()])),
        "ringAbut": e2.write_package("ring-abut", e2.project([a(), b(6 * TICKS, False)])),
    }


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
    binary = os.path.join(out, "editor-keys-undo-probe")
    shader, why = build_shader(out)
    if shader is None:
        return None, why
    swift = sorted(os.path.join(sources, n) for n in os.listdir(sources)
                   if n.endswith(".swift") and n != "main.swift")
    lib = os.path.join(ROOT, "core", "target", "release", "libreelcut_core.a")
    if not os.path.exists(lib):
        return None, f"{lib} is missing — run `cd core && cargo build --release` first"
    if os.path.exists(binary) and all(
            os.path.getmtime(f) < os.path.getmtime(binary) for f in swift + [entry, lib]):
        return binary, None
    sdk = subprocess.run(["xcrun", "--show-sdk-path", "--sdk", "macosx"],
                         capture_output=True, text=True).stdout.strip()
    flags = ["-D", "HARNESS_REFERENCE_BUILD"] if reference else []
    start = time.time()
    result = subprocess.run(
        ["swiftc", "-sdk", sdk, "-target", "arm64-apple-macos26.0", "-module-name", "Reelcut",
         "-import-objc-header", os.path.join(ROOT, "app", "Bridging",
                                             "Reelcut-Bridging-Header.h"),
         "-L", os.path.dirname(lib), "-lreelcut_core"] + flags + swift
        + [entry, "-o", binary],
        capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(binary):
        errors = [line for line in result.stderr.splitlines() if ": error:" in line]
        return None, "swiftc failed:\n       " + "\n       ".join(
            errors[:6] or ["(no error lines)"])
    print(f"  probe built in {time.time() - start:.0f} s")
    return binary, None


def probe_checks(sources, out, paths, reference=False):
    print("\n1 — the probe: U undo, F/C bare keys, R rename, M media, D the ring")
    check("media/A.mov exists (README \"Make the test media once\")", os.path.exists(MOVIE),
          MOVIE)
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
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    try:
        result = subprocess.run([binary, request, answer, "-ReelcutInspectorCollapsed", "NO"],
                                capture_output=True, text=True, timeout=300, env=env)
    except subprocess.TimeoutExpired:
        check("the probe runs", False, "no answer in 300 s")
        return None
    if result.returncode != 0 or not os.path.exists(answer):
        check("the probe runs", False, (result.stdout + result.stderr).strip()[-400:])
        return None
    with open(answer) as f:
        rows = json.load(f)["rows"]
    check(f"the probe answers every row group ({', '.join(GROUPS)} present)",
          all(any(r["name"][0] == g and r["name"][1:2].isdigit()
                  and not r["name"].startswith(g + "0") for r in rows) for g in GROUPS),
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
          "-D HARNESS_REFERENCE_BUILD against the current libreelcut_core.a")
    rows = probe_checks(os.path.join(tree, "app", "Sources"),
                        os.path.join(tree, "out"), packages(), reference=True)
    elapsed = time.time() - began
    if rows is None:
        print(f"BASELINE FAILURE: the probe did not build or run over {commit}, "
              f"{elapsed:.0f} s")
        return 1
    failed = sorted({r["name"].split(" ")[0] for r in rows if not r["ok"]})
    structural = [n for n, ok in RESULTS
                  if not ok and not any(n.startswith(g) and n[1:2].isdigit() for g in GROUPS)]
    if failed == sorted(BASELINE_EXPECTED) and not structural:
        print(f"BASELINE PASS: exactly {', '.join(BASELINE_EXPECTED)} FAILED on {commit} and "
              f"nothing else did (every control passed), {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: failed {failed} (want {sorted(BASELINE_EXPECTED)}), other "
          f"failures {structural}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("B3 — editor keys, undo steps, the transition ring (#59 #60 #61 #66 #68 #69)")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
