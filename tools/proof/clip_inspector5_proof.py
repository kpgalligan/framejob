#!/usr/bin/env python3
"""Road map 9, phase 4 — retiming by drag: a band's body moves an action and
its outer 5 pt resize it, on the timeline and in the Clip tab's lane; the
lane's hatch, fades and wedges.

    python3 tools/proof/clip_inspector5_proof.py
    python3 tools/proof/clip_inspector5_proof.py --mutant walls

Two instruments, `clip_inspector4_proof.py`'s shape:

* **the probe**, `clip_inspector5_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `harness/build.sh`'s swiftc line (a probe that will not build is a scored
  FAILURE, never an exit). Rows D1–D6: the session's arithmetic (D1 ×8), the
  timeline driven through `beginGesture` / `continueGesture` / `endGesture`
  in a real editor (D2 ×7), the lane driven by synthesized mouse events into
  its own handlers (D3 ×5), the hover and the grip rule (D4 ×4), `hit(at:)`
  (D5 ×2) and the lane's decor geometry (D6 ×4).
* **the harness**, the editor at 1440 × 862, dark, M, Picture. Rows H1–H3:
  the render is deterministic; the `av` lane's bottom-left 10 pt hold the
  fade (pixels lighter than the well) and its bottom-right corner does not;
  with action 1 selected and nothing hovered, the selected band's last 5 pt
  are its fill only — grips are hover-only (spec §11 CI-11).

**Deviation, recorded in road map 9 §10.** The spec's `zero` fixture — the
card plus a zero-length action at 0.5 s — is a project the core refuses to
open (`model_query.rs` `check_clips`: every action has a positive duration,
and every commit validates). So D1's zero-length wall is asked of the card IN
MEMORY, and D3's last row reads the core's refusal of the fixture instead of
pressing a band no lane can show.

`--mutant walls` builds the probe AND the harness over a COPY of
`app/Sources` whose `ActionDragSession.update` ignores `lowerWall` and
`upperWall`. Exit 0 means EXACTLY the rows in `MUTANT_EXPECTED` failed in the
copy and nothing else did — D1's three wall rows and D2's abutting drop,
whose one far tick the core then refuses, so the band stays.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (Image, clip, project, write_package, video_props)
import clip_inspector_proof as ci  # noqa: E402  (action, media_clip, build_probe, near)
import clip_inspector2_proof as ci2  # noqa: E402  (movie, pinned metrics)
import clip_inspector4_proof as ci4  # noqa: E402  (build_harness)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector5")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector5_probe.swift")
TICKS = e2.TICKS

WIDTH, HEIGHT = e2.WIDTH, e2.HEIGHT       # 1440 × 862
INSPECTOR_X = 1136                        # WIDTH − DS.panelWidth
SIDE = 10                                 # InspectorMetrics.inset
CHIP = 40                                 # ActionLaneView.chipWidth
# The lane's well, in window points: the pinned block's top, the selection
# header, then `ActionLaneView`'s top, header row and gap; the chip and 4 pt.
WELL_TOP = ci2.PINNED_TOP + ci2.HEADER_H + 8 + 18 + 6    # 152
WELL_H = 28
WELL_X0 = INSPECTOR_X + SIDE + CHIP + 4                  # 1190
WELL_X1 = WIDTH - SIDE                                   # 1430
CLIP_SECONDS = 6
CORNER = 10                               # the fade's 10 pt
LIGHTER = 12                              # channel-sum margin over the well
FILL_TOLERANCE = 3                        # per channel, against the band's fill

MUTANT_FILE = "ActionDragSession.swift"
MUTANT_ANCHOR = "        let low = lowerWall, high = upperWall\n"
MUTANT_EXPECTED = [
    "D1 walls: a move stops at 0 on the left and abuts action 4 (start 1.5 s) on the right",
    "D1 walls: resize(.end) keeps the start and caps at the upper wall (2.5 s)",
    "D1 walls: a zero-length action at the band's start (0.5 s) is a wall — a move left "
    "stops there",
    "D2 walls: one far tick (+5 s) lands abutting action 4 (start 1.5 s)",
]

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


def card(actions):
    return e2.clip(2, 0, e2.GREY, name="Card", duration=CLIP_SECONDS * TICKS, actions=actions)


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    two = [ci.action(3, 0.5, 1.5, {"video": {"opacity": 0.5}}),
           ci.action(4, 2.5, 4.0, {"video": {"x": 100.0}})]
    zero = {"id": 5, "start": int(0.5 * TICKS), "duration": 0, "curve": "linear",
            "end": {"video": {"y": 50.0}}}
    first = ci.media_clip(2, 91, 0, [], video=True)
    first["audio"] = {"fade_in": TICKS}
    first["video"] = e2.video_props(e2.motion(e2.edge("fade", 0.5)))
    second = ci.media_clip(3, 91, 5 * TICKS, [], video=True)
    second["transition_in"] = {"kind": "cross_dissolve", "curve": "linear", "audio": False}
    return {
        "chrome": e2.write_package("ci5-chrome", e2.project([card(two)])),
        "zero": e2.write_package("ci5-zero", e2.project([card(two + [zero])])),
        "av": e2.write_package("ci5-av", e2.project([first, second],
                                                     media=[ci2.movie(91, True)])),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`clip_inspector_proof.build_probe`'s swiftc line, over THIS phase's
    probe source (its module global names the file it compiles)."""
    ci.PROBE_SWIFT = PROBE_SWIFT
    return ci.build_probe(sources, out)


PROBE_COUNTS = {"D1": 8, "D2": 7, "D3": 5, "D4": 4, "D5": 2, "D6": 4}


def probe_checks(sources, out, paths):
    print("\n1 — the probe: D1 session, D2 timeline, D3 lane, D4 hover, D5 hit, D6 decor")
    binary, error = build_probe(sources, out)
    check("the probe builds over app/Sources", binary is not None, error or "")
    if binary is None:
        return
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
        return
    with open(answer) as f:
        rows = json.load(f)["rows"]
    counts = {k: sum(1 for r in rows if r["name"].startswith(k + " ")) for k in PROBE_COUNTS}
    check("the probe answers every D-row (D1 ×8, D2 ×7, D3 ×5, D4 ×4, D5 ×2, D6 ×4) and no "
          "D0 fixture row", counts == PROBE_COUNTS
          and not any(r["name"].startswith("D0 ") for r in rows), f"{counts}")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---------------------------------------------------------------------------
# The harness.


def render(binary, package, out, playhead, action):
    args = [binary, package, out, "dark", str(WIDTH), str(HEIGHT), "0", str(playhead), "1",
            "clip", "-", "-", "-", action, "picture"]
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode != 0 or not os.path.exists(out):
        return None, (result.stdout + result.stderr).strip()[-400:]
    return out, None


HARNESS_ROWS = [
    "H1 the chrome card at 5 s, Picture, rendered twice → byte-identical PNGs",
    f"H2 av: the lane's bottom-left {CORNER} pt hold pixels lighter than the well (the fade "
    "in) and its bottom-right corner holds none (no fade out)",
    "H3 chrome, action 1 selected, nothing hovered: the selected band's last 5 pt (lower "
    "half) are its fill only — no grip",
]


def pixel(image, x, y):
    """The pixel at DEVICE (x, y), as RGB."""
    ch = image.channels
    return tuple(image.rows[y][x * ch:x * ch + 3])


def lighter_count(image, x0, x1, y0, y1, well):
    s = image.scale
    count = 0
    for y in range(int(y0 * s), int(y1 * s)):
        for x in range(int(x0 * s), int(x1 * s)):
            if sum(pixel(image, x, y)) > sum(well) + LIGHTER:
                count += 1
    return count


def harness_checks(sources, out, paths):
    print("\n2 — the harness: dark, 1440 × 862, M, Picture")
    binary, error = ci4.build_harness(sources, out)
    renders = {}
    for tag, package, playhead, action in (("a", "chrome", 5, "-"), ("b", "chrome", 5, "-"),
                                           ("av", "av", 3, "-"), ("keyed", "chrome", 5, "0")):
        if error:
            break
        renders[tag], error = render(binary, paths[package],
                                     os.path.join(out, f"ci5-{tag}.png"), playhead, action)
    if error:
        for name in HARNESS_ROWS:
            check(name, False, error)
        return
    with open(renders["a"], "rb") as a, open(renders["b"], "rb") as b:
        check(HARNESS_ROWS[0], a.read() == b.read())

    image = e2.Image(renders["av"])
    s = image.scale
    width = WELL_X1 - WELL_X0
    bottom = WELL_TOP + WELL_H
    well = pixel(image, int((WELL_X0 + width * 0.3) * s), int((bottom - 4) * s))
    # Inside the well's 1 pt border on every side.
    left = lighter_count(image, WELL_X0 + 1, WELL_X0 + CORNER, bottom - CORNER, bottom - 1, well)
    right = lighter_count(image, WELL_X1 - CORNER, WELL_X1 - 1, bottom - CORNER, bottom - 1,
                          well)
    check(HARNESS_ROWS[1], left > 0 and right == 0,
          f"{os.path.relpath(renders['av'], ROOT)}: well {well}, lighter pixels bottom-left "
          f"{left}, bottom-right {right}")

    image = e2.Image(renders["keyed"])
    band_x1 = WELL_X0 + width * 1.5 / CLIP_SECONDS
    band_y0, band_y1 = WELL_TOP + 4, bottom - 4
    fill = pixel(image, int((band_x1 - 2) * s), int((band_y1 - 2) * s))
    odd = []
    for y in range(int((band_y0 + band_y1) / 2 * s), int((band_y1 - 1) * s)):
        for x in range(int((band_x1 - 5 + 0.5) * s), int((band_x1 - 0.5) * s)):
            if not ci.near(pixel(image, x, y), fill, FILL_TOLERANCE):
                odd.append((x, y, pixel(image, x, y)))
    check(HARNESS_ROWS[2], not odd and sum(fill) > 200,
          f"{os.path.relpath(renders['keyed'], ROOT)}: band ends at x {band_x1:g} pt, fill "
          f"{fill}, {len(odd)} other pixels {odd[:3]}")


# ---------------------------------------------------------------------------


def mutant():
    began = time.time()
    with tempfile.TemporaryDirectory(prefix="reelcut-clip-inspector5-walls-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, MUTANT_FILE)
        with open(path) as f:
            text = f.read()
        if text.count(MUTANT_ANCHOR) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(MUTANT_ANCHOR)} times")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(
                MUTANT_ANCHOR,
                "        // mutant: the walls are ignored\n"
                "        let low = Ticks.min / 4, high = Ticks.max / 4\n", 1))
        print(f"MUTANT walls: ActionDragSession.update ignores its walls, in {sources}")
        paths = packages()
        probe_checks(sources, os.path.join(temp, "probe"), paths)
        harness_checks(sources, os.path.join(temp, "harness"), paths)
    failed = [n for n, ok in RESULTS if not ok]
    built = bool(RESULTS) and RESULTS[0][1]
    elapsed = time.time() - began
    if built and sorted(failed) == sorted(MUTANT_EXPECTED):
        print(f"MUTANT PASS: walls — exactly the {len(MUTANT_EXPECTED)} expected row(s) FAILED "
              f"in the copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: walls — built {built}; missing failures "
          f"{[n for n in MUTANT_EXPECTED if n not in failed]}; unexpected failures "
          f"{[n for n in failed if n not in MUTANT_EXPECTED]}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] == "walls":
        return mutant()
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Road map 9, phase 4 — retiming by drag, the lane's decor")
    paths = packages()
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"), paths)
    harness_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "harness"), paths)
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
