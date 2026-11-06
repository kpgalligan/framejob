#!/usr/bin/env python3
"""Docs-bugs batch a2 (#463, #474, #475; spec §11 K-5, K-6, K-7): canvas keys and crop mode.

    python3 tools/proof/docs_bugs_a2_proof.py [--only N1,K3,…] [--tree PATH] [--expect-red]
                                              [--mutant NAME]

The project is made by the app under test over MCP (`proof_app.binary()`, `RC_PROOF_APP`) in
`work/docs_bugs_a2/`, saved and closed: A.mov 0–10 s on V1, a rectangle 3–4.5 s, text 5–6.5 s and a
graphic from 7 s on V2, an action at 8 s, and a top `alpha` matte track holding a rectangle at
9–9.5 s. Every row but Z1 runs through `docs_bugs_a2_probe.swift`, the app's own sources on that
package: a key press and a double-click can't be sent over MCP, and crop mode has no menu item or
tool. Keys go through `EditorWindow.sendEvent`; the probe's header says what the mouse does instead.

`--tree PATH` builds the probe from `PATH/app/Sources`, its bridging header and
`PATH/core/target/release/libframejob_core.a`. `--expect-red` is the run against the base: it
exits 0 only when every row not marked CONTROL fails and every CONTROL passes, and prints a row
that does neither.

    RC_PROOF_APP=<the frozen base app> python3 tools/proof/docs_bugs_a2_proof.py \
        --tree <base tree> --expect-red

Red on the base unless marked CONTROL:
- #463, the arrows on a focused canvas. N1 ← x −1, frame unchanged, undo "Nudge". N2 ⇧→ x +10. N3
  ↑ ↓ y ∓1, frame unchanged. N4 (CONTROL) a selected clip not drawn at the playhead: the frame
  steps, no edit. N5 (CONTROL) ⌥←: no nudge. N6 (CONTROL) root focus: the frame steps. N7 ← during
  a move drag: frame unchanged, no edit; then Esc: the press's state, undo empty.
- #463, Enter, Caps Lock, Space. K1 keypad Enter leaves crop. K2 fn-Return, both forms. K3 ⇪Esc. K4
  ⇪Return. K5 ⇪Esc in a move drag: back to the press, session over, undo empty. K6 ⇪Space tap: one
  toggle, on release. K7 held ⇪Space, three repeats: no toggle until release. K8 ⇪Space-drag at
  zoom 2: pans, clip untouched. K9 ⌥Space tap on the canvas: no toggle. K10 Space taken by the
  window, overlay made first responder, release: one toggle in all. K11 Space with `.function` on
  the canvas: no arm, no toggle on press or release.
- K-5's focus. F1 canvas focused, a press over the timeline through `sendEvent`: first responder is
  the content view. F2 (CONTROL) over the canvas: it stays. F3 (CONTROL) after F1, ← steps a frame,
  no edit.
- #474. C1 timeline select, C, Esc. C2 the same, Return. C3 Crop on Canvas, then Esc. C4 a field,
  Return, C, Esc. C5 an action selected: the first Esc leaves crop and keeps the action, the second
  deselects. C6 (CONTROL) ⌥Return and ⌘Esc at the root leave it on. C7 (CONTROL) a field typing: Esc
  leaves it on. C8 (CONTROL) first responder unchanged by C. C9 root focus, keypad Enter leaves it.
- #475. S1–S3 C on shape, text, graphic: `cropMode` false, no change signalled, `setCropMode(true)`
  answers false. S4, S5 double-click shape, graphic: the same. S6 (CONTROL) double-click text opens
  the editor. S7 (CONTROL) C and double-click on the video open. S8 crop on the video, click a
  shape: off. S9 the same by `document.selection`: off. S10 selection [video, shape], crop on at
  2 s, playhead to 4 s: off. S11 (CONTROL) a crop drag on the video: one undo step "Crop". S12
  (CONTROL) C and double-click on the matte track's rectangle open.
- Z1 (CONTROL) `grep "Frame Job: "` on the log prints nothing.

`--mutant NAME` breaks one decision in a `tree_copy.py` copy, builds the probe from it and runs only
the row it must fail: CAUGHT exits 1, SURVIVED exits 0, a control that could not be performed exits
2. `guard-shift-only` N1, `no-capslock` K3, `space-any-flag` K11, `keyup-ungated` K10,
`nudge-no-box` N4, `arrow-mid-drag` N7, `crop-key-below-bare` C9, `no-leave-canvas` F1,
`crop-gate-off` S1, `update-gate-off` S9, `playhead-gate-off` S10, `matte-gate-off` S12. An
instrument that cannot run is a scored failure, never an exit.
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
import editor_keys_undo_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import proof_defaults  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/docs_bugs_a2"
FIXTURES = WORK / "fixtures"
MEDIA = ROOT / "tools/proof/media"
PROBE = "docs_bugs_a2_probe"
SEC = 600_000
PROBE_BOUND = 480
CALL_BOUND = 300

PROBE_ROWS = (["N1", "N2", "N3", "N4", "N5", "N6", "N7"]
              + [f"K{i}" for i in range(1, 12)]
              + ["F1", "F2", "F3"]
              + [f"C{i}" for i in range(1, 10)]
              + [f"S{i}" for i in range(1, 13)])
ROWS = PROBE_ROWS + ["Z1"]
CONTROLS = {"N4", "N5", "N6", "F2", "F3", "C6", "C7", "C8", "S6", "S7", "S11", "S12", "Z1"}

KEYS = "app/Sources/PreviewCanvasView+Keys.swift"
CANVAS = "app/Sources/PreviewCanvasView.swift"
WINDOW = "app/Sources/EditorWindow.swift"
EDITOR = "app/Sources/EditorViewController.swift"
CROP_KEY_LINE = "        if previewCanvas?.handleCropKey(event) == true { return true }\n"
BARE_GUARD = "        guard EditorKey.isBare(flags, scalar: scalar.value) else { return false }\n"
MUTANTS = {
    "guard-shift-only": (["N1"], [(
        KEYS, "        guard CanvasKey.isPlain(flags) else { return false }\n",
        "        guard flags.subtracting(.shift).isEmpty else { return false }\n")]),
    "no-capslock": (["K3"], [(
        WINDOW, ".subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty\n    }\n}\n",
        ".subtracting([.shift, .numericPad, .function]).isEmpty\n    }\n}\n")]),
    "space-any-flag": (["K11"], [(
        KEYS, "            guard flags.subtracting([.shift, .capsLock]).isEmpty else { return false }\n",
        "")]),
    "keyup-ungated": (["K10"], [(
        KEYS, "        guard event.keyCode == 49, spaceHeld else { return false }\n",
        "        guard event.keyCode == 49 else { return false }\n")]),
    "nudge-no-box": (["N4"], [(CANVAS, "        guard primaryBox != nil else { return false }\n", "")]),
    "arrow-mid-drag": (["N7"], [(
        KEYS, "        case 123...126 where isGestureLive:\n",
        "        case 123...126 where false:\n")]),
    "crop-key-below-bare": (["C9"], [
        (EDITOR, CROP_KEY_LINE, ""),
        (EDITOR, BARE_GUARD, BARE_GUARD + CROP_KEY_LINE)]),
    "no-leave-canvas": (["F1"], [(WINDOW, "        leaveCanvas(for: event)\n", "")]),
    "crop-gate-off": (["S1"], [(
        CANVAS, "        let allowed = on && primaryBox != nil && !primaryRefusesCrop\n",
        "        let allowed = on && primaryBox != nil\n")]),
    "update-gate-off": (["S9"], [(
        CANVAS, "        if cropMode, primaryBox == nil || primaryRefusesCrop { setCropMode(false) }\n",
        "        if cropMode, primaryBox == nil { setCropMode(false) }\n")]),
    "playhead-gate-off": (["S10"], [(
        CANVAS, "        if cropMode, primaryRefusesCrop { setCropMode(false) }\n", "")]),
    "matte-gate-off": (["S12"], [(
        KEYS, "            && snapshot.track(clip.track)?.matte == TrackMatte.none\n", "")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'}  {name}  {detail}"[:400], flush=True)


# ---- the fixture --------------------------------------------------------------------

def make_fixture(c):
    shutil.rmtree(FIXTURES, ignore_errors=True)
    FIXTURES.mkdir(parents=True)
    p = str(FIXTURES / "canvas.framejob")
    a = {"project": p}
    c.call_with("new_project", {"path": p})
    first = c.call_with("get_project", a)["project"]["tracks"][0]["id"]
    media = c.call_with("import_media", {**a, "path": str(MEDIA / "A.mov")})["media"]
    video = c.call_with("add_clip", {**a, "track": first, "media": media, "at": 0})["new_clips"][0]
    action = c.call_with("add_action", {**a, "clip": video, "at": 8 * SEC,
                                        "duration": SEC})["new_actions"][0]
    top = c.call_with("add_track", a)["new_tracks"][0]
    shape = c.call_with("add_shape_clip", {**a, "track": top, "at": 3 * SEC,
                                           "duration": int(1.5 * SEC)})["new_clips"][0]
    text = c.call_with("add_text_clip", {**a, "track": top, "at": 5 * SEC,
                                         "duration": int(1.5 * SEC)})["new_clips"][0]
    c.call_with("set_playhead", {**a, "t": 7 * SEC})
    time.sleep(1)
    graphic = c.call_with("insert_graphic", {**a, "name": "lower-third",
                                             "from": "template"})["new_clips"][0]
    front = c.call_with("add_track", a)["new_tracks"][0]
    c.call_with("set_track", {**a, "track": front, "matte": "alpha"})
    matte = c.call_with("add_shape_clip", {**a, "track": front, "at": 9 * SEC,
                                           "duration": SEC // 2})["new_clips"][0]
    c.call_with("set_playhead", {**a, "t": 2 * SEC})
    c.call_with("save_project", a)
    c.call_with("close_project", a)
    ids = {"video": video, "shape": shape, "text": text, "graphic": graphic, "action": action,
           "matte": matte}
    (FIXTURES / "ids.json").write_text(json.dumps(ids, indent=1))
    return ids


def app_fixture(binary):
    """The fixture in one launch; True when it was made. Scores Z1."""
    log = WORK / "app.log"
    launched = mcp.launch(str(binary), ["-RCDevAppearance", "dark"], log_path=str(log),
                          timeout=CALL_BOUND)
    made = False
    try:
        if launched.client is None:
            print("  the app did not listen", flush=True)
            return False
        print(f"  instance PID {launched.child.pid}", flush=True)
        ids = make_fixture(launched.client)
        print(f"  fixture {ids}", flush=True)
        made = True
    except Exception as error:  # noqa: BLE001 — a scored failure, never the run's
        print(f"  the fixture failed: {type(error).__name__}: {error}", flush=True)
    finally:
        launched.stop()
        try:
            lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
        except OSError:
            lines = [f"{log} could not be read"]
        check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")
    return made


# ---- the probe ----------------------------------------------------------------------

def build_probe(tree):
    """(the binary, None) or (None, why)."""
    folder = WORK / "probe"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    entry = folder / "main.swift"
    shutil.copyfile(HERE / f"{PROBE}.swift", entry)
    tree = Path(tree)
    # Without the metallib beside it the player never plays: K6, K7 and K10 read that.
    shader, why = editor_keys_undo_proof.build_shader(str(folder), str(tree))
    if shader is None:
        return None, why
    try:
        built = swift_build.build(
            sources=[str(p) for p in swift_build.app_sources(tree / "app/Sources")] + [str(entry)],
            output=folder / PROBE, defines=["FRAMEJOB_DEV_TOOLS"],
            bridging_header=tree / "app/Bridging/FrameJob-Bridging-Header.h",
            library=tree / "core/target/release/libframejob_core.a")
    except swift_build.SwiftBuildFailed as error:
        return None, str(error)[:600]
    print(f"  probe {built.key} reused {built.reused}, {built.seconds} s", flush=True)
    return folder / PROBE, None


def run_probe(binary, wanted):
    """Every row the probe printed, by id; (rows, why)."""
    run = WORK / "run"
    shutil.rmtree(run, ignore_errors=True)
    run.mkdir(parents=True)
    rows = {}
    command = [str(binary), str(FIXTURES / "canvas.framejob"), str(run), str(FIXTURES / "ids.json")]
    if set(wanted) != set(PROBE_ROWS):
        command.append(",".join(wanted))
    try:
        done = subprocess.run(command, capture_output=True, text=True, timeout=PROBE_BOUND)
    except subprocess.TimeoutExpired as expired:
        out = expired.stdout or b""
        (WORK / "probe.out.txt").write_bytes(out if isinstance(out, bytes) else out.encode())
        return rows, f"no answer within {PROBE_BOUND} s"
    finally:
        left = proof_defaults.remove_domain(PROBE)
        if left:
            print(f"  the probe's defaults domain: {left}", flush=True)
    (WORK / "probe.out.txt").write_text(done.stdout + "\n--- stderr\n" + done.stderr)
    for line in done.stdout.splitlines():
        if line.startswith("{"):
            row = json.loads(line)
            if "abort" in row:
                return rows, row["abort"]
            rows[row.get("row")] = row
    if done.returncode != 0:
        return rows, f"the probe exited {done.returncode}: {done.stderr[-300:]}"
    return rows, None


def score(r):
    def row(name):
        got = r.get(name)
        if got and "failed" in got:
            check(name, False, got["failed"])
            return None
        return got

    def told(name, ok):
        got = row(name)
        if got:
            shown = {k: v for k, v in got.items() if k != "row"}
            check(name, ok(got), json.dumps(shown, sort_keys=True))

    told("N1", lambda x: x["first"] == "overlay" and x["dx"] == -1 and x["frames"] == 0
         and x["undo"] == "Nudge")
    told("N2", lambda x: x["dx"] == 10 and x["frames"] == 0 and x["undo"] == "Nudge")
    told("N3", lambda x: x["up"] == -1 and x["down"] == 1 and x["up_frames"] == 0
         and x["frames"] == 0)
    told("N4", lambda x: x["first"] == "overlay" and not x["shown"] and x["dx"] == 0
         and x["frames"] == -1 and x["undo"] == "")
    told("N5", lambda x: x["dx"] == 0 and x["undo"] == "")
    told("N6", lambda x: x["first"] == "content" and x["dx"] == 0 and x["frames"] == -1
         and x["undo"] == "")
    told("N7", lambda x: x["moved"] != 0 and x["frames"] == 0 and x["mid"] == 0
         and x["back_x"] == 0 and x["back_y"] == 0 and not x["session"] and x["undo"] == "")

    told("K1", lambda x: x["on"] and not x["crop"])
    told("K2", lambda x: x["on"] and not x["keypad_form"] and x["again"] and not x["return_form"])
    told("K3", lambda x: x["on"] and not x["crop"])
    told("K4", lambda x: x["on"] and not x["crop"])
    told("K5", lambda x: x["moved"] != 0 and x["back_x"] == 0 and x["back_y"] == 0
         and not x["session"] and x["undo"] == "")
    told("K6", lambda x: not x["down"] and x["up"])
    told("K7", lambda x: x["states"] == [False, False, False, False, True])
    told("K8", lambda x: x["can_pan"] and x["session"] and x["pan"][0] != 0 and x["pan"][1] != 0
         and x["dx"] == 0 and x["dy"] == 0 and x["undo"] == "" and not x["playing"])
    told("K9", lambda x: not x["down"] and not x["up"])
    told("K10", lambda x: x["down"] and x["first"] == "overlay" and x["up"])
    told("K11", lambda x: not x["down"] and not x["up"])

    told("F1", lambda x: x["before"] == "overlay" and x["first"] == "content")
    told("F2", lambda x: x["before"] == "overlay" and x["first"] == "overlay")
    told("F3", lambda x: x["dx"] == 0 and x["frames"] == -1 and x["undo"] == "")

    for name in ("C1", "C2", "C9"):
        told(name, lambda x: x["on"] and x["first"] == "content" and not x["crop"])
    told("C3", lambda x: x["on"] and x["first"] == "content" and not x["crop"])
    told("C4", lambda x: x["typing"] != "overlay" and x["first"] == "content" and x["on"]
         and not x["crop"])
    told("C5", lambda x: x["on"] and x["selected"] and not x["crop"] and x["kept"]
         and not x["after"])
    told("C6", lambda x: x["on"] and x["first"] == "content" and x["option_return"]
         and x["command_esc"])
    told("C7", lambda x: x["on"] and x["typing"] and x["crop"])
    told("C8", lambda x: x["on"] and x["first"] == x["before"])

    for name in ("S1", "S2", "S3"):
        told(name, lambda x: x["selected"] and not x["crop"] and x["changes"] == 0
             and x["answer"] is False)
    for name in ("S4", "S5"):
        told(name, lambda x: x["selected"] and not x["crop"] and x["changes"] == 0)
    told("S6", lambda x: x["editing"] and not x["crop"])
    for name in ("S7", "S12"):
        told(name, lambda x: x["selected"] and x["by_key"] and not x["off"]
             and x["by_double_click"])
    told("S8", lambda x: x["on"] and x["selection"] and not x["crop"])
    told("S9", lambda x: x["on"] and not x["crop"])
    told("S10", lambda x: x["on"] and x["front"] and not x["crop"])
    told("S11", lambda x: x["on"] and x["left"] > 0 and x["undo"] == "Crop"
         and x["after_undo"] == 0 and x["more"] == "")


def probe_rows(tree):
    wanted = [r for r in PROBE_ROWS if r in selected]
    if not wanted:
        return
    binary, why = build_probe(tree)
    if binary is None:
        for row in wanted:
            check(row, False, f"the probe did not build: {why}")
        return
    rows, why = run_probe(binary, wanted)
    if why:
        print(f"  the probe stopped: {why}", flush=True)
    score(rows)
    for row in wanted:
        if row not in results:
            check(row, False, f"the probe printed no such row ({why or 'it finished'})")


def run_rows(binary, tree):
    if not app_fixture(binary):
        for row in PROBE_ROWS:
            check(row, False, "the fixture was not made")
        return
    probe_rows(tree)


# ---- mutants ------------------------------------------------------------------------

def digest(path):
    return hashlib.sha256((ROOT / path).read_bytes()).hexdigest()


def run_mutant(name):
    global selected
    rows, edits = MUTANTS[name]
    print(f"docs bugs a2: the {name} MUTANT ({', '.join(rows)} must FAIL)", flush=True)
    before = {path: digest(path) for path, _, _ in edits}
    selected = set(rows) | {"Z1"}
    made, why = tree_copy.make_copy(str(WORK / "mutant"), agent=False)
    if not why:
        for path, anchor, replacement in edits:
            target = Path(made) / path
            text = target.read_text()
            if text.count(anchor) != 1:
                why = f"the anchor occurs {text.count(anchor)} times in {path}"
                break
            target.write_text(text.replace(anchor, replacement))
    if why:
        print(f"mutant {name}: the control could not be performed — {why}")
        return 2
    if not app_fixture(proof_app.binary()):
        print(f"mutant {name}: the control could not be performed — no fixture")
        return 2
    probe_rows(made)
    after = {path: digest(path) for path, _, _ in edits}
    print(f"  the tree's files unchanged by SHA-256: {before == after}")
    if not all(row in results for row in rows):
        print(f"mutant {name}: the control could not be performed — {rows} never scored")
        return 2
    caught = any(not all(ok for ok, _ in results[row]) for row in rows)
    print(f"MUTANT {name} {'CAUGHT' if caught else 'SURVIVED'}: {', '.join(rows)} "
          f"{'failed' if caught else 'passed'}", flush=True)
    tree_copy.remove_tree(made)
    return 1 if caught else 0


def scores():
    failed = [n for n in ROWS if n in results and not all(ok for ok, _ in results[n])]
    passed = [n for n in ROWS if n in results and n not in failed]
    return passed, failed


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--tree", default=str(ROOT))
    parser.add_argument("--expect-red", action="store_true")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    args = parser.parse_args()
    if args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    shutil.rmtree(WORK, ignore_errors=True)
    WORK.mkdir(parents=True)
    if args.mutant:
        return run_mutant(args.mutant)
    print(f"docs bugs a2 ({proof_app.config()} build), tree {args.tree}", flush=True)
    run_rows(proof_app.binary(), args.tree)
    passed, failed = scores()
    print(f"\nscores: {len(passed)}/{len(passed) + len(failed)}"
          + (f"; failed {failed}" if failed else ""), flush=True)
    if args.expect_red:
        wrong = [r for r in failed if r in CONTROLS] + [r for r in passed if r not in CONTROLS]
        print("expected red, every row not marked CONTROL failing and every CONTROL passing: "
              + ("held" if not wrong else f"NOT held for {wrong}"), flush=True)
        return 1 if wrong else 0
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
