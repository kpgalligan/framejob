#!/usr/bin/env python3
"""ai-docs batch c3 (#527, spec §11 #527): Make Vertical's Follow Speaker reads a microphone with no
speech under a shot as that person not talking there, and a shot none of whose microphones has
speech follows its faces with the core's reason; `reframe_clip` still refuses a silent microphone.

    python3 tools/proof/ai_docs_c3_proof.py [--only F1,S1,…] [--mutant NAME] [--app PATH]
                                            [--expect-red]
    RC_PROOF_APP=release python3 tools/proof/ai_docs_c3_proof.py
    RC_PROOF_APP=<a base .app> python3 tools/proof/ai_docs_c3_proof.py --expect-red

The built app (`proof_app`'s choice) under a scratch home, driven over MCP, over F-TURNS
(`vr6b_proof.py`'s `Doc`, W's analyses canned). THE FIXTURE: Mic A split at the last utterance's
end + 0.6 s, snapped up to the 30 fps grid, so a long piece holding every turn and a short piece
holding only F-TURNS' room tone; the long piece's sound off. Every call is
`make_vertical_version {shape 9:16, follow speaker, copy false}`. `(c)` marks a CONTROL, which
passes on the base too; every other row is red on the frozen base app (`main` at `d40d1f81`), and
`--expect-red` exits 0 only when that holds and no row failed for want of running.

Launch 1 (`vr6b_proof.LAUNCH_1`):
- F3 (c) nothing muted, `mics [A short, B]`, `mic_faces [1, 2]`: `speaker` names A's long piece.
- F1 the fixture, `mics [A short, B]`, `mic_faces [1, 2]`: answered, canvas 1080 × 1920, `speaker`
  W on [A short, B] with [1, 2], W has no reason, the summary's " Follows whoever is talking in 1
  clip.", no cut and face 2 (B's) framed at W's middle, face 1 not.
- F6 the fixture with no `mic_faces`: answered, W's reason names the weak match ("faces do not show
  which microphone is whose").
- F5 (c) the fixture, `reframe_clip {follow speaker, mics [A short, B], mic_faces [1, 2]}` from
  1920 × 1080: refused with SW-24's no-speech sentence, the project unchanged.
- F4 (c) both A pieces muted: `speaker` [], W's reason names the long piece's "sound is off".
- F2 Mic B split at the same tick and B's long piece muted too, `mics [A short, B short]`:
  answered, `speaker` [], W `followed` with "it follows its faces, not who is talking, because
  clip W has no turn of its microphones inside it, so there is no speaker to follow".
- F7 (c) Mic A's loudness cache removed: refused "make_vertical_version was refused: The
  microphone on track <Mic A> is still being analyzed — its loudness has not been measured yet.",
  nothing made.
Launch 2 (`-RCDevAnalysisCanned YES -FrameJobFollowKind speaker`), File ▸ Make Vertical Version…
read through `snapshot_ui` and closed by `cancel_sheet`:
- S2 (c) the unmuted fixture's sheet: its summary " Follows whoever is talking in 1 clip."
- S1 the fixture's sheet: no shown text holds "has no speech", a "Makes a … version." line is
  shown, and the not-sure note.
- Z1 (c) `grep "Frame Job: "` of each launch's log prints nothing.

`--mutant NAME`: the named decision broken in a tree copy from `tree_copy.py`, its app built, and
only its row run (with Z1). CAUGHT exits 1 (the named row failed), SURVIVED exits 0, and a control
that could not be performed (the copy did not build, an anchor not found once) exits 2. F-TURNS
needs `say`'s Samantha and Daniel; without them the script exits 2, skipped by name.
"""

import argparse
import re
import shutil
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import tree_copy  # noqa: E402
import vr6_proof as vr6  # noqa: E402
import vr6b_proof as vr6b  # noqa: E402

WORK = ROOT / "tools/proof/work/ai-docs-c3"
HOME = WORK / "home"
CALL_BOUND = 900
BUILD_BOUND = 1800
SHEET_BOUND = 60
TICKS = 600_000
FRAME = TICKS // 30
LAUNCH_2 = ["-RCDevAnalysisCanned", "YES", "-FrameJobFollowKind", "speaker"]
TALKING = " Follows whoever is talking in 1 clip."
SUMMARY = re.compile(r"Makes a \d+ × \d+ version\.")

LAUNCH_ONE = ["F3", "F1", "F6", "F5", "F4", "F2", "F7"]
LAUNCH_TWO = ["S2", "S1"]
ROWS = LAUNCH_ONE + LAUNCH_TWO + ["Z1"]
CONTROLS = {"F3", "F4", "F5", "F7", "S2", "Z1"}

SPEAKER = "app/Sources/VerticalVersion+Speaker.swift"
FRAMING = "app/Sources/AgentServer+Framing.swift"
TURNS = "app/Sources/FramingSpeaker.swift"
# name: (the row it must turn red, the edits).
MUTANTS = {
    "vertical-refuses-silence": ("F1", [(
        SPEAKER, "mics: entry.mics, silence: .notTalking)", "mics: entry.mics, silence: .refuses)")]),
    "reframe-allows-silence": ("F5", [(
        FRAMING, "silence: .refuses)", "silence: .notTalking)")]),
    "not-talking-drops-problems": ("F7", [(
        TURNS, "input.problems + (silence == .refuses ? SpeakerSwitch.silentMicrophones(input) : [])",
        "(silence == .refuses ? input.problems + SpeakerSwitch.silentMicrophones(input) : [])")]),
}

results = {}
broken = set()
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'PASS' if ok else 'FAIL'} {name}: {detail}", flush=True)


def attempt(names, body):
    """`body` when any of `names` is selected; an instrument that raises fails them, never exits."""
    if not selected & set(names):
        return
    try:
        body()
    except Exception as error:  # noqa: BLE001
        for name in names:
            if name in selected and name not in results:
                broken.add(name)
            check(name, False, f"the row could not run: {error!r}")


# ---- the fixture ------------------------------------------------------------------------

def split_tail(doc, manifest, track):
    """`track`'s one clip split at the last utterance's end + 0.6 s, snapped up to the frame
    grid: (the long piece, the short piece). The short piece holds only room tone."""
    last_end = max(t["end_seconds"] for t in manifest["turns"])
    at = (int((last_end + 0.6) * TICKS) // FRAME + 1) * FRAME
    clip = next(c for c in doc.state()["clips"] if c["track"] == track)
    doc.call("split", clips=[clip["id"]], at=at)
    pieces = sorted((c for c in doc.state()["clips"] if c["track"] == track),
                    key=lambda c: c["start"])
    return pieces[0]["id"], pieces[1]["id"]


def make(doc, mics, **extra):
    """(the answer, None) or (None, the refusal)."""
    try:
        return doc.vertical(mics=mics, **extra), None
    except mcp.ToolError as error:
        return None, str(error)


def undo_if(doc, answer):
    if answer is not None:
        doc.call("undo")


def tool_rows(client, manifest):
    def body():
        doc = vr6b.Doc(client, manifest, "follow", second=False)
        try:
            a_long, a_short = split_tail(doc, manifest, doc.mic_a_track)
            w = doc.c_wide
            mics = [a_short, doc.c_b]

            answer, refused = make(doc, mics, mic_faces=[1, 2])
            speaker = (answer or {}).get("speaker")
            check("F3", speaker == [{"clip": w, "mics": [a_long, doc.c_b], "mic_faces": [1, 2]}],
                  f"nothing muted: speaker {speaker}, refused {refused}, long piece {a_long}")
            undo_if(doc, answer)

            doc.call_with("set_enabled", {"clip": a_long, "audio": False})
            answer, refused = make(doc, mics, mic_faces=[1, 2])
            state = doc.state()
            canvas = state["canvas"]
            speaker = (answer or {}).get("speaker")
            entry = vr6b.entry(answer or {}, w) or {}
            summary = (answer or {}).get("summary") or ""
            clip = doc.clip(w, state)
            cuts = vr6.cut_keys(clip)
            mid = clip["duration"] // 2
            b_in, a_in = vr6.inside(clip, mid, 0.58), vr6.inside(clip, mid, 0.42)
            check("F1", answer is not None
                  and (canvas["width"], canvas["height"]) == (1080, 1920)
                  and speaker == [{"clip": w, "mics": [a_short, doc.c_b], "mic_faces": [1, 2]}]
                  and "reason" not in entry and TALKING in summary
                  and cuts == [] and b_in and not a_in,
                  f"A's long piece {a_long} muted: refused {refused}, canvas "
                  f"{canvas['width']}×{canvas['height']}, speaker {speaker}, W {entry}, cuts "
                  f"{cuts}, face 2 inside {b_in}, face 1 inside {a_in}, summary {summary[:160]!r}")
            undo_if(doc, answer)

            answer, refused = make(doc, mics)
            reason = (vr6b.entry(answer or {}, w) or {}).get("reason") or ""
            check("F6", answer is not None
                  and "faces do not show which microphone is whose" in reason,
                  f"no mic_faces: refused {refused}, W's reason {reason[:200]!r}")
            undo_if(doc, answer)

            before = vr6b.model(doc.state())
            try:
                doc.call_with("reframe_clip", {
                    "clip": w, "follow": "speaker", "mics": mics, "mic_faces": [1, 2],
                    "from_width": 1920, "from_height": 1080})
                refused = None
            except mcp.ToolError as error:
                refused = str(error)
            after = vr6b.model(doc.state())
            want = (f"reframe_clip was refused: The microphone on track {doc.mic_a_track} has "
                    f"no speech between")
            check("F5", refused is not None and want in refused and before == after,
                  f"reframe_clip: refused {refused!r}, unchanged {before == after}")
            if after != before:
                doc.call("undo")

            doc.call_with("set_enabled", {"clip": a_short, "audio": False})
            answer, refused = make(doc, mics, mic_faces=[1, 2])
            speaker = (answer or {}).get("speaker")
            reason = (vr6b.entry(answer or {}, w) or {}).get("reason") or ""
            check("F4", answer is not None and speaker == []
                  and f"clip {a_long}'s sound is off" in reason,
                  f"both A pieces muted: speaker {speaker}, reason {reason[:200]!r}, refused "
                  f"{refused}")
            undo_if(doc, answer)
            doc.call_with("set_enabled", {"clip": a_short, "audio": True})

            b_long, b_short = split_tail(doc, manifest, doc.mic_b_track)
            doc.call_with("set_enabled", {"clip": b_long, "audio": False})
            both = [a_short, b_short]
            answer, refused = make(doc, both, mic_faces=[1, 2])
            speaker = (answer or {}).get("speaker")
            entry = vr6b.entry(answer or {}, w) or {}
            reason = entry.get("reason") or ""
            want = (f"it follows its faces, not who is talking, because clip {w} has no turn of "
                    f"its microphones inside it, so there is no speaker to follow")
            check("F2", answer is not None and speaker == []
                  and entry.get("treatment") == "followed" and reason.startswith(want),
                  f"both long pieces muted, mics {both}: refused {refused}, speaker {speaker}, "
                  f"W {entry}")
            undo_if(doc, answer)

            loudness = doc.path / "cache" / "loudness"
            aside = WORK / "loudness-aside"
            aside.mkdir(parents=True, exist_ok=True)
            moved = [p for p in loudness.iterdir() if p.name.startswith(f"{doc.m_a}.")]
            for p in moved:
                shutil.move(str(p), str(aside / p.name))
            try:
                before = vr6b.model(doc.state())
                answer, refused = make(doc, both, mic_faces=[1, 2])
                after = vr6b.model(doc.state())
            finally:
                for p in moved:
                    shutil.move(str(aside / p.name), str(p))
            want = (f"make_vertical_version was refused: The microphone on track "
                    f"{doc.mic_a_track} is still being analyzed — its loudness has not been "
                    f"measured yet.")
            check("F7", answer is None and moved and refused is not None and want in refused
                  and before == after,
                  f"{len(moved)} loudness files of media {doc.m_a} moved aside: refused "
                  f"{refused!r}, unchanged {before == after}")
            undo_if(doc, answer)
        finally:
            doc.close()
    attempt(LAUNCH_ONE, body)


def sheet_texts(doc, tag):
    """Every shown text of Make Vertical's sheet once it shows its summary or a refusal, read
    again 2 s later; the sheet then cancelled."""
    doc.call("perform_menu_item", path=vr6b.MENU)
    began = time.monotonic()
    while time.monotonic() - began < SHEET_BOUND:
        texts = [v.get("text") or "" for v in vr6b.shown(vr6b.sheet_views(doc, tag))]
        if any(SUMMARY.match(t) or "no speech" in t for t in texts):
            break
        time.sleep(0.5)
    time.sleep(2)
    texts = [v.get("text") or "" for v in vr6b.shown(vr6b.sheet_views(doc, tag + "-settled"))]
    doc.client.call("cancel_sheet", project=str(doc.path))
    return [t for t in texts if t]


def sheet_rows(client, manifest):
    def body():
        doc = vr6b.Doc(client, manifest, "follow-sheet", second=False)
        try:
            a_long, _ = split_tail(doc, manifest, doc.mic_a_track)
            texts = sheet_texts(doc, "unmuted")
            summary = next((t for t in texts if SUMMARY.match(t)), "")
            check("S2", TALKING.strip() in summary, f"unmuted: {summary!r}")
            doc.call_with("set_enabled", {"clip": a_long, "audio": False})
            texts = sheet_texts(doc, "filed")
            speech = [t for t in texts if "has no speech" in t]
            summary = next((t for t in texts if SUMMARY.match(t)), None)
            note = vr6b.UNSURE in texts
            check("S1", not speech and summary is not None and note,
                  f"A's long piece {a_long} muted: no-speech texts {speech}, summary "
                  f"{summary!r}, not-sure note {note}")
        finally:
            doc.close()
    attempt(LAUNCH_TWO, body)


# ---- the run ----------------------------------------------------------------------------

def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def launch(binary, arguments, rows, body, tag):
    log = WORK / f"{tag}.log"
    env = bounded.child_env({"CFFIXED_USER_HOME": str(HOME)})
    launched = mcp.launch(str(binary), arguments, env=env, log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for row in sorted(rows):
                broken.add(row)
                check(row, False, "the instance did not listen")
            return
        print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
        body(launched.client)
    finally:
        launched.stop()
        parity(log, tag)


def run_rows(binary, manifest):
    first = selected & set(LAUNCH_ONE)
    if first:
        launch(binary, vr6b.LAUNCH_1, first, lambda c: tool_rows(c, manifest), "launch-1")
    second = selected & set(LAUNCH_TWO)
    if second:
        launch(binary, LAUNCH_2, second, lambda c: sheet_rows(c, manifest), "launch-2")


def mutate(name):
    """(the copy, None) or (None, why): the tree copy with the mutant's edits."""
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}: {anchor[:60]!r}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    parser.add_argument("--expect-red", action="store_true")
    args = parser.parse_args()
    if args.mutant:
        selected = {MUTANTS[args.mutant][0], "Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        selected.add("Z1")
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    vr6b.WORK = WORK
    (WORK / "sheets").mkdir()

    binary = Path(args.app) if args.app else None
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        print(f"ai-docs c3 — the {args.mutant} MUTANT ({row} must FAIL)", flush=True)
        made, why = mutate(args.mutant)
        if why is None:
            app, why = tree_copy.build_app(made, BUILD_BOUND)
            binary = proof_app.executable(app) if app else None
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"ai-docs c3 — a silent microphone under a Follow Speaker shot "
              f"({proof_app.config()} build)", flush=True)
    if binary is None:
        binary = proof_app.binary()
    if binary.suffix == ".app":
        binary = proof_app.executable(binary)

    manifest = vr6b.fturns()
    if manifest is None:
        print("SKIPPED: F-TURNS needs say's Samantha and Daniel")
        return 2

    run_rows(binary, manifest)

    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    missing = sorted(selected - set(results), key=ROWS.index)
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else "")
          + (f"; never scored {missing}" if missing else ""))
    if args.mutant:
        row = MUTANTS[args.mutant][0]
        if row not in results or row in broken:
            print(f"mutant {args.mutant}: the control could not be performed — its row did not "
                  f"run")
            return 2
        caught = row in failed
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: {row} "
              f"{'failed' if caught else 'passed'}")
        return 1 if caught else 0
    if args.expect_red:
        green = [name for name in passed if name not in CONTROLS]
        red_controls = [name for name in failed if name in CONTROLS]
        print(f"expect red: {len(failed) - len(red_controls)} rows red, green {green or 'none'}, "
              f"red controls {red_controls or 'none'}, unrun {sorted(broken) or 'none'}")
        return 0 if not green and not red_controls and not broken and not missing else 1
    return 0 if not failed and not missing and results else 1


if __name__ == "__main__":
    sys.exit(main())
