#!/usr/bin/env python3
"""kpgalligan/reelcut#35 — Space toggles play wherever nothing is typing.

    python3 tools/proof/space_key_proof.py
    python3 tools/proof/space_key_proof.py --baseline b69972e

One instrument, the probe `space_key_probe.swift`, compiled AS `main.swift`
over every file in `app/Sources` but the app's own `main.swift` on
`harness/build.sh`'s swiftc line (a probe that will not build is a scored
FAILURE, never an exit). S1 asks `SpaceKey.route` row by row; S2 drives the
app's own window with synthesized Space events and reads whether play
toggled.

`--baseline <commit>` builds the same probe over `git archive <commit>
app/Sources` with `-D HARNESS_REFERENCE_BUILD` (S1, S2g and S2h compiled out)
and exits 0 only when EXACTLY the rows in `BASELINE_EXPECTED` fail there and
no S1, S2g or S2h row is present — the fix is what S2a and S2b measure, and
only they.

S2h (road map 12 A2) is the Assistant tab's composer. The probe runs with a
DUMMY key in a `-RCSecretFolder` of its own (so the composer shows),
`-ReelcutInspectorCollapsed NO`, and ANTHROPIC_API_KEY and RC_ASSEMBLYAI_KEY
popped from its environment: no person's key is read.
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
WORK = os.path.join(HERE, "work", "space-key")
PROBE_SWIFT = os.path.join(HERE, "space_key_probe.swift")
# The item composes through the app's Metal compositor, which loads
# `default.metallib` from the directory a bare swiftc binary is in
# (`mixed_audio_probe.py`'s `build_shader`).
SHADER = os.path.join(ROOT, "app", "Resources", "Shaders", "Compositor.metal")
MOVIE = os.path.join(HERE, "media", "A.mov")
TICKS = e2.TICKS

BASELINE_EXPECTED = ["S2a", "S2b"]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def packages():
    """The card of the spec, 0–6 s, and after it 6 s of `media/A.mov`
    (README "Make the test media once"). The movie is there for ONE reason:
    a shape-only plan has no media track, so `Playback.startRebuild` drops
    the item and the transport refuses — measured, `playerLayer.player`
    had no `currentItem` over the card alone. The playhead starts at 0, on
    the card."""
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
    return {"card": e2.write_package("space-card", card)}


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
    binary = os.path.join(out, "space-key-probe")
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
    print("\n1 — the probe: S1 the route, S2 the app's own window")
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
    secrets = os.path.join(out, "secrets")
    shutil.rmtree(secrets, ignore_errors=True)
    os.makedirs(secrets)
    with open(os.path.join(secrets, "anthropic-key"), "w") as f:
        f.write("space-key-dummy-key\n")
    env = dict(os.environ)
    env.pop("ANTHROPIC_API_KEY", None)
    env.pop("RC_ASSEMBLYAI_KEY", None)
    result = subprocess.run([binary, request, answer, "-RCSecretFolder", secrets,
                             "-ReelcutInspectorCollapsed", "NO"],
                            capture_output=True, text=True, timeout=300, env=env)
    if result.returncode != 0 or not os.path.exists(answer):
        check("the probe runs", False, (result.stdout + result.stderr).strip()[-400:])
        return None
    with open(answer) as f:
        rows = json.load(f)["rows"]
    groups = ["S2a", "S2b", "S2c", "S2d", "S2e", "S2f"]
    if not reference:
        groups = ["S1", "S2g"] + groups + ["S2h"]
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
    absent = [r["name"] for r in rows
              if r["name"].startswith(("S1 ", "S2g ", "S2h "))]
    structural = [n for n, ok in RESULTS if not ok and not n.startswith("S")]
    if failed == sorted(BASELINE_EXPECTED) and not absent and not structural:
        print(f"BASELINE PASS: exactly {', '.join(BASELINE_EXPECTED)} FAILED on {commit} and "
              f"nothing else did, {elapsed:.0f} s")
        return 0
    print(f"BASELINE FAILURE: failed {failed} (want {BASELINE_EXPECTED}), S1/S2g/S2h rows "
          f"present {absent}, other failures {structural}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--baseline":
        return baseline(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("#35 — Space toggles play wherever nothing is typing")
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"),
                 packages())
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
