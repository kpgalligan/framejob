#!/usr/bin/env python3
"""Road map 9, phase 5 — the rest of the mode: canvas gestures follow the
selected action (spec §11 CI-13), a switch inside an action keys the property
OFF (CI-14), `mixed` on every sub-row and the animated collapse (CI-15), and
the three open nits.

    python3 tools/proof/clip_inspector6_proof.py
    python3 tools/proof/clip_inspector6_proof.py --mutant target
    python3 tools/proof/clip_inspector6_proof.py --mutant live

Two instruments, `clip_inspector4_proof.py`'s shape:

* **the probe**, `clip_inspector6_probe.swift`, compiled AS `main.swift` over
  every file in `app/Sources` but the app's own `main.swift` on
  `harness/build.sh`'s swiftc line (a probe that will not build is a scored
  FAILURE, never an exit). Rows K1 (the target, the move session through the
  live edit, the nudge in a real editor, the scrub into a span, a move held
  across that scrub, a text clip's width drag, a shape's box scale), K2 (the
  Drop shadow switch keyed off, and Clear), K4 (`mixed` on Shadow ▸ Blur and
  Compressor ▸ Ratio), K5 (the header click's state is synchronous) and K6
  (Box ▸ Width's default, the lane's cursor rects).
  K6's other two rows live where their instruments are: the floored wall in
  `clip_inspector5_probe.swift`, the strip at two widths in
  `clip_inspector4_probe.swift`.
* **the built app**, launched by this script on its own port
  (`RC_AGENT_PORT`, default 4851) and driven over `mcp.py`. Rows K3:
  `set_action_end {off: ["video.shadow"]}` stores the null, the frame at the
  action's end is BYTE-identical to the same project with the base shadow
  removed and differs from the frame before; `off: ["video.opacity"]` and
  `["video.motion"]` are errors naming the path; `offf` is refused by the
  argument gate; the log carries no `Reelcut: ` line. The script kills only
  the process it started.

`--mutant MODE` builds the probe over a COPY of `app/Sources` with one
mutation, `MUTANTS[MODE]`, and exit 0 means EXACTLY that mode's `expected`
rows failed in the copy and nothing else did. The built app is not re-run
under a mutant: it is the tree's binary, not the copy's.

* `target`: `CanvasEditTarget.op(video:clip:)` answers `.setVideo` always.
  The four K1 routing rows fail; the shape row, the text row (which routes
  through `op(text:)`), the start-state rows and the mouse-down capture row
  (both arms then answer `set_video`) hold.
* `live`: `PreviewCanvasView.gestureTarget` reads the LIVE `editTarget`
  instead of the target captured at mouse-down. Exactly the capture row
  fails: the drag's tick keys action 4's end once the playhead has scrubbed
  into its span.
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import e2_chrome as e2  # noqa: E402  (clip, project, write_package, GREY)
import clip_inspector_proof as ci  # noqa: E402  (action, media_clip, build_probe)
import clip_inspector2_proof as ci2  # noqa: E402  (movie, text_clip)
from mcp import MCP, ToolError  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
WORK = os.path.join(HERE, "work", "clip-inspector6")
PROBE_SWIFT = os.path.join(HERE, "clip_inspector6_probe.swift")
APP = os.path.join(ROOT, "build", "Build", "Products", "Release", "Reelcut.app", "Contents",
                   "MacOS", "Reelcut")
PORT = 4851
TICKS = e2.TICKS
SIX = 6 * TICKS

MUTANTS = {
    "target": {
        "file": "CanvasEditTarget.swift",
        "anchor": ("        return .setActionEnd(clip: clip, action: action, "
                   "patch: ActionPatch(video: patch))\n"),
        "replacement": ("        // mutant: every video op is set_video\n"
                        "        _ = action\n"
                        "        return .setVideo(clips: [clip], patch: patch)\n"),
        "expected": [
            "K1 op(video:): the selected action's clip → set_action_end on action 4; another "
            "clip → set_video; .base → set_video",
            "K1 a CanvasMoveSession's ops(to:) through the live edit moves action 4's END x by "
            "the delta (100 → 130, y 0 → 20) and leaves the base at 0 — ONE undo step",
            "K1 nudge in a real editor: with action 4 selected its END x goes 100 → 110 (base "
            "0); with none the BASE x goes 0 → 10 (end 110)",
            # Added 2026-09-24 (phase 5 review, finding 2): the playhead's entry rule is a
            # routing row.
            "K1 scrubbing the playhead into action 4's span selects it and a nudge keys its END "
            "x 100 → 110 (base 0); scrubbed back out, a nudge keys it again 110 → 120 (base 0)",
        ],
        "note": "CanvasEditTarget.op(video:clip:) answers .setVideo always",
    },
    # Added 2026-09-24 (phase 5 review 2): the target a drag writes is captured at mouse-down.
    "live": {
        "file": "PreviewCanvasView.swift",
        "anchor": "    private(set) var gestureTarget = CanvasEditTarget.base\n",
        "replacement": ("    // mutant: the gesture reads the LIVE target on every tick\n"
                        "    var gestureTarget: CanvasEditTarget { get { editTarget } set {} }\n"),
        "expected": [
            "K1 a move begun with no action selected and held while the playhead scrubs into "
            "action 4's span (the live editTarget becomes action 4) writes the BASE x 0 → 10 "
            "and leaves its end x at 100 — the target captured at mouse-down",
        ],
        "note": "PreviewCanvasView.gestureTarget reads the LIVE editTarget",
    },
}
PROBE_COUNTS = {"K1": 9, "K2": 3, "K4": 2, "K5": 1, "K6": 2}

RESULTS = []


def check(name, ok, detail=""):
    RESULTS.append((name, bool(ok)))
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
    if detail:
        print("       " + detail)


# A white shadow, so it shows on the black canvas: the K3 frames differ by it.
SHADOW = {"color": [1.0, 1.0, 1.0, 1.0], "opacity": 1.0, "blur": 12.0, "angle": 45.0,
          "distance": 40.0}


def card(cid, start, blur=12.0, actions=None):
    clip = e2.clip(cid, start, e2.GREY, name="Card", duration=SIX, actions=actions or [])
    clip["video"]["shadow"] = dict(SHADOW, blur=blur)
    return clip


def chrome_actions():
    return [ci.action(3, 0.5, 1.5, {"video": {"opacity": 0.5}}),
            ci.action(4, 2.5, 4.0, {"video": {"x": 100.0}})]


def compressor(ratio):
    return {"threshold_db": -20.0, "ratio": ratio, "attack": 6000, "release": 60000,
            "makeup_db": 0.0}


def packages():
    os.makedirs(WORK, exist_ok=True)
    e2.CHROME = WORK
    text = ci2.text_clip(2)
    text["text"]["width"] = 300.0
    text["actions"] = [ci.action(3, 0.5, 1.5, {"text": {"width": 600.0}})]
    first = ci.media_clip(2, 91, 0, [], video=True)
    first["audio"] = {"compressor": compressor(2.0)}
    second = ci.media_clip(3, 91, SIX, [], video=True)
    second["audio"] = {"compressor": compressor(4.0)}
    return {
        "chrome": e2.write_package("ci6-chrome", e2.project([card(2, 0, actions=chrome_actions())])),
        "pair": e2.write_package("ci6-pair", e2.project([
            card(2, 0, actions=chrome_actions()), card(5, SIX, blur=24.0)])),
        "text": e2.write_package("ci6-text", e2.project([text])),
        "duo": e2.write_package("ci6-duo", e2.project([first, second],
                                                      media=[ci2.movie(91, True)])),
    }


# ---------------------------------------------------------------------------
# The probe.


def build_probe(sources, out):
    """`clip_inspector_proof.build_probe`'s swiftc line, over THIS phase's
    probe source (its module global names the file it compiles)."""
    ci.PROBE_SWIFT = PROBE_SWIFT
    return ci.build_probe(sources, out)


def probe_checks(sources, out, paths):
    print("\n1 — the probe: K1 the target, K2 keyed off, K4 mixed, K5 the collapse, K6 the nits")
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
    check("the probe answers every K-row (K1 ×9, K2 ×3, K4 ×2, K5 ×1, K6 ×2) and no K0 "
          "fixture row", counts == PROBE_COUNTS
          and not any(r["name"].startswith("K0 ") for r in rows), f"{counts}")
    for row in rows:
        check(row["name"], row["ok"], "" if row["ok"] else row["detail"])


# ---------------------------------------------------------------------------
# The built app, over MCP.


K3_ROWS = [
    "K3 the app binds its own port and its log carries no `Reelcut: ` line",
    "K3 set_action_end {off: [video.shadow]} on the shadowed card: get_project holds "
    "end.video.shadow == null",
    "K3 render_frame at the action's end (1.5 s) is BYTE-identical to the same project with the "
    "base shadow removed, and differs from the frame before",
    "K3 off: [video.opacity] is an error naming video.opacity",
    "K3 off: [video.motion] is an error in the op's own sentence",
    "K3 an argument spelled offf is refused by the gate, by name",
]


def parity_lines(log_path):
    with open(log_path, encoding="utf-8", errors="replace") as log:
        return [line.rstrip() for line in log if "Reelcut: " in line]


def launch(log_path):
    env = os.environ.copy()
    env["RC_AGENT_PORT"] = str(PORT)
    log = open(log_path, "w", encoding="utf-8")
    process = subprocess.Popen([APP, "-ApplePersistenceIgnoreState", "YES",
                                "-AgentServerEnabled", "YES"],
                               stdout=log, stderr=subprocess.STDOUT, env=env)
    bound = None
    until = time.monotonic() + 30
    while time.monotonic() < until and process.poll() is None and bound is None:
        with open(log_path, encoding="utf-8", errors="replace") as text:
            found = re.search(r"listening on http://127\.0\.0\.1:(\d+)/mcp", text.read())
        if found:
            bound = int(found.group(1))
        else:
            time.sleep(0.2)
    return process, log, bound


def error_of(call):
    try:
        call()
    except ToolError as error:
        return str(error)
    return None


def mcp_checks(chrome):
    print(f"\n2 — the built app over MCP ({os.path.relpath(APP, ROOT)})")
    if not os.path.exists(APP):
        for name in K3_ROWS:
            check(name, False, "no built app — run `make app` first")
        return
    frames = os.path.join(WORK, "frames")
    os.makedirs(frames, exist_ok=True)
    log_path = os.path.join(WORK, f"reelcut-{PORT}.log")
    process, log, bound = launch(log_path)
    try:
        if bound is None:
            for name in K3_ROWS:
                check(name, False, f"the app bound no port; log {log_path}")
            return
        time.sleep(0.5)
        mcp = MCP(bound, timeout=120)
        mcp.call("open_project", path=chrome)

        def op(tool, **arguments):
            return mcp.call_with(tool, dict(arguments, project=chrome))

        def frame(name):
            path = os.path.join(frames, name)
            if os.path.exists(path):
                os.remove(path)
            op("render_frame", t=int(1.5 * TICKS), path=path)
            with open(path, "rb") as f:
                return f.read()

        before = frame("k3-before.png")
        op("set_action_end", clip=2, action=3, patch={}, off=["video.shadow"])
        project = op("get_project")["project"]
        clip = {c["id"]: c for c in project["clips"]}[2]
        end = {a["id"]: a for a in clip["actions"]}[3]["end"]
        video = end.get("video", {})
        check(K3_ROWS[1], "shadow" in video and video["shadow"] is None, f"end {end}")
        keyed = frame("k3-keyed-off.png")
        op("undo")
        op("set_video", clips=[2], patch={"shadow": None})
        removed = frame("k3-base-removed.png")
        check(K3_ROWS[2], keyed == removed and keyed != before,
              f"keyed-off {len(keyed)} B, base-removed {len(removed)} B, before "
              f"{len(before)} B; identical {keyed == removed}, differs from before "
              f"{keyed != before}")
        op("undo")
        opacity = error_of(lambda: op("set_action_end", clip=2, action=3, patch={},
                                      off=["video.opacity"]))
        check(K3_ROWS[3], opacity is not None and "video.opacity" in opacity, f"{opacity}")
        motion = error_of(lambda: op("set_action_end", clip=2, action=3, patch={},
                                     off=["video.motion"]))
        check(K3_ROWS[4], motion is not None
              and "video.motion is not an animation target" in motion, f"{motion}")
        gate = error_of(lambda: op("set_action_end", clip=2, action=3, patch={},
                                   offf=["video.shadow"]))
        check(K3_ROWS[5], gate is not None and "offf" in gate, f"{gate}")
        lines = parity_lines(log_path)
        check(K3_ROWS[0], bound == PORT and not lines and process.poll() is None,
              f"bound {bound}, parity lines {lines[:3]}")
    except (ToolError, RuntimeError, OSError, KeyError) as error:
        done = {name for name, _ in RESULTS}
        for name in K3_ROWS:
            if name not in done:
                check(name, False, f"{type(error).__name__}: {error}")
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        log.close()


# ---------------------------------------------------------------------------


def mutant(mode):
    spec = MUTANTS[mode]
    expected = spec["expected"]
    began = time.time()
    with tempfile.TemporaryDirectory(prefix=f"reelcut-clip-inspector6-{mode}-") as temp:
        sources = os.path.join(temp, "Sources")
        shutil.copytree(os.path.join(ROOT, "app", "Sources"), sources)
        path = os.path.join(sources, spec["file"])
        with open(path) as f:
            text = f.read()
        if text.count(spec["anchor"]) != 1:
            print(f"MUTANT FAILURE: the anchor occurs {text.count(spec['anchor'])} times")
            return 2
        with open(path, "w") as f:
            f.write(text.replace(spec["anchor"], spec["replacement"], 1))
        print(f"MUTANT {mode}: {spec['note']}, in {sources}")
        paths = packages()
        probe_checks(sources, os.path.join(temp, "probe"), paths)
    failed = [n for n, ok in RESULTS if not ok]
    built = bool(RESULTS) and RESULTS[0][1]
    elapsed = time.time() - began
    if built and sorted(failed) == sorted(expected):
        print(f"MUTANT PASS: {mode} — exactly the {len(expected)} expected row(s) FAILED "
              f"in the copy and nothing else did, {elapsed:.0f} s")
        return 0
    print(f"MUTANT FAILURE: {mode} — built {built}; missing failures "
          f"{[n for n in expected if n not in failed]}; unexpected failures "
          f"{[n for n in failed if n not in expected]}, {elapsed:.0f} s")
    return 1


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "--mutant" and sys.argv[2] in MUTANTS:
        return mutant(sys.argv[2])
    if len(sys.argv) != 1:
        sys.exit(__doc__)
    print("Road map 9, phase 5 — the rest of the mode")
    paths = packages()
    probe_checks(os.path.join(ROOT, "app", "Sources"), os.path.join(WORK, "probe"), paths)
    mcp_checks(paths["chrome"])
    good = sum(1 for _, ok in RESULTS if ok)
    print(f"\n{good}/{len(RESULTS)} checks passed")
    return 0 if RESULTS and good == len(RESULTS) else 1


if __name__ == "__main__":
    sys.exit(main())
