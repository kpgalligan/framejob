#!/usr/bin/env python3
"""Road map "creator-jobs" CO3 — Remove Background in the inspector and the menus (spec §11
CO-30, CO-31, CO-32).

    python3 tools/proof/co3_proof.py [--only I1,I4,…] [--mutant NAME] [--app PATH]

**Probe rows** (`co3_probe.swift`, built from `app/Sources` with `FRAMEJOB_DEV_TOOLS` through
`swift_build.py`; no app; a failed build is a scored FAIL of each):
- I1 the Background section is registered right after Chroma Key, and its checkbox commits
  exactly one `set_video {cutout: {five defaults}}` step, "Remove Background".
- I3 with an action selected, Edge writes `set_action_end {video: {cutout: {edge}}}` alone,
  Background `{background}` alone, the checkbox's gutter is ⊘ and its write the base
  `set_video {cutout: null}`.
- I5 Clip ▸ Remove Background follows Look with no key; its state is off / mixed / on for none /
  some / all cut out, and on a mixed selection the toggle turns on only the off clip (the other's
  edge kept), one undo step.
- I6p the probe's own centroid over a hand-made pack is the value worked by hand.
- I8 `CutoutStatus.progress`'s three cases, each 0.400.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`), on a scratch
`CFFIXED_USER_HOME`, with the Background section pinned open in the argument domain
(`-FrameJobInspectorSection.video.cutout <false/>`, which persists nothing), the person rows on
`co2a_proof.person_fixtures()`'s push-in (`push_1080.mov`) and screen recording
(`screen_4k.mov`), each row in its own package, closed after it.
Launch H (`-RCDevAnalysisHold 3600`):
- I2 (held) the push-in clip [0, 2 s) cut out and selected, Picture ▸ Background: Status reads
  "Analyzing 0 %" (`snapshot_ui`'s layout dump).
- I4 (held) `analyze_cutout {wait: 0}` answers `analyzing`, `ready` false, `covered < frames`,
  centroid null.
Launch N (no hold):
- I4 `analyze_cutout {wait: 60}` answers `ready` with `covered == frames ==`
  `get_media_analysis {media, kind: masks}`'s `frames` over the clip's need (CO-22's need
  holds one frame more than `get_media_analysis {clip}`'s window: the frame at the window's end
  its last tick can ask for).
- I2 that clip's Status reads "Ready"; a screen-recording clip [0, 2 s) answers `no_person` and
  its Status reads "No person found".
- I6 `analyze_cutout`'s centroid equals the probe's own centroid of the pack over the clip's
  need and the marker's coverage (`co3-probe centroid`) within 1e-6 px.
- I7 clip A of the push-in [0, 2 s) lands ready; `cache/analysis/masks/` made read-only (as
  co2b's W5 makes it) and clip B playing [10 s, 12 s) of the same media cut out: B answers
  `failed` with its sentence and its Status reads "Failed: …", while A answers `ready` with a
  centroid; the folder restored, `analyze_cutout {clips: [B], wait: 0}` (the same
  `analyzeMasksNow()` the pane's Analyze Now runs) takes B's Status out of "Failed" within
  `I7_BOUND` s (it reads "Analyzing N %" or "Ready"), then `{clips: [B], wait: 60}` answers
  ready.
- Z1 each launch's `grep "Frame Job: "` prints nothing.

A row needing `tools/proof/media/cutout/`'s fixtures fails naming the fixture's error.

`--mutant NAME`: CO-30's or CO-31's decision broken in a tree copy (`tree_copy.py`), the copy
built as the proof's configuration (and the probe from the copy's `app/Sources`), and only its
rows run; CAUGHT (exit 0) when one of them fails. The tree's mutated file's SHA-256 is read before
and after and must be unchanged.

Prints `scores: P/N`; exits 0 iff every scored row passed.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
sys.path.insert(0, str(HERE / "cutout_spike"))
import bounded  # noqa: E402
import co2a_proof  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co3"
HOME = WORK / "home"
SEC = 600_000
FRAME = 20_000
W, H = 640, 360
CALL_BOUND = 600
BUILD_BOUND = 1500
# Fixed before the run: how long `snapshot_ui` is polled for a Status (a held job's first read,
# a landed job's redraw), and I7's bound for Status to leave "Failed" after Analyze Now.
STATUS_BOUND = 10
I7_BOUND = 2.0
# How many `{wait: 60}` calls a row may make before its clip must be settled (three lanes'
# load on Debug); a mutant that answers before the window is covered answers every one at once.
WAIT_CALLS = 3
PIN = ["-FrameJobInspectorSection.video.cutout", "<false/>"]
HOLD = ["-RCDevAnalysisHold", "3600"]
PROBE_ROWS = ["I1", "I3", "I5", "I6p", "I8"]
APP_ROWS = ["I2", "I4", "I6", "I7", "Z1"]
ROWS = PROBE_ROWS + APP_ROWS

STATUS = "app/Sources/CutoutStatus.swift"
SERVER = "app/Sources/AgentServer+Cutout.swift"
MUTANTS = {
    "M1-unregistered": (["I1"], [(
        "app/Sources/ClipPane.swift",
        "                if videoPane.allCutoutable { sections.append(videoPane.cutoutSection("
        "cutoutMemo)) }\n", "")]),
    "M2-no-structural": (["I3"], [(
        "app/Sources/InspectorBinding+Writes.swift",
        "        if patch.cutout != nil {\n            base.cutout = patch.cutout\n"
        "            animatable.cutout = nil\n        }\n", "")]),
    "M3-early-answer": (["I4"], [(
        SERVER, "            if read.details.allSatisfy({ $0.status.state.isSettled }) "
        "|| Date() >= deadline\n",
        "            if true || read.details.allSatisfy({ $0.status.state.isSettled }) "
        "|| Date() >= deadline\n")]),
    "M4-no-mixed": (["I5"], [(
        STATUS, "        return on == targets.count ? .on : .mixed\n", "        return .on\n")]),
    "M5-unscaled": (["I6"], [(
        STATUS, "            x: sumX / Double(frames) * Double(mediaWidth) / Double(pack.width),\n"
        "            y: sumY / Double(frames) * Double(mediaHeight) / Double(pack.height))\n",
        "            x: sumX / Double(frames),\n            y: sumY / Double(frames))\n")]),
    "M6-no-retry": (["I7"], [(
        "app/Sources/ProjectDocument+Masks.swift",
        "        CutoutWants.queue.async { AnalysisLane.shared.retry(owner: owner) }\n", "")]),
    # Objection 4's two guards together: any failed run of the media fails a clip, checked
    # before `covered == frames` (either guard alone keeps clip A ready).
    "M7-failure-first": (["I7"], [(
        STATUS, "        let covered = count(intersect(need, coverage))\n",
        "        let covered = count(intersect(need, coverage))\n"
        "        if let cacheDir, let failure = ownerRequests(owner, media: id, cacheDir: cacheDir)\n"
        "            .lazy.compactMap({ AnalysisLane.shared.run(of: $0)?.outcome }).first(where: {\n"
        "                if case .failed = $0 { return true } else { return false } }),\n"
        "            case .failed(let why) = failure\n"
        "        {\n"
        "            return answer(.failed(why), media: media, need: need, coverage: coverage,\n"
        "                frames: frames, covered: covered, cache: cacheDir)\n"
        "        }\n")]),
    "M8-progress-over": (["I8"], [(
        STATUS, "        let cOut = c - count(intersect(coveredNeed, running))\n",
        "        let cOut = c\n")]),
}

results = {}
selected = set(ROWS)
PROBE = None


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the grid and the need rule, as this script reads CO-22 -------------------------------

def need_of(lower, upper, media):
    """CO-22 (a)'s need of a forward window `[lower, upper)`."""
    num, den = media["fps"]
    rate = num / (600_000 * den)
    last = max(1, -int(-(media["duration"] * rate - 1e-6) // 1)) - 1

    def index(ticks):
        value = ticks * rate
        return min(last, max(0, int(value + 0.5)))
    low = min(last, max(0, int((lower * rate + 1e-9) // 1)))
    high = index(max(lower, upper - 1))
    return [min(low, high), high]


# ---- the probe rows ------------------------------------------------------------------------

def build_probe(root=ROOT):
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co3_probe.swift", entry)
    sources = sorted(str(p) for p in (Path(root) / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = out / "co3-probe"
    swift_build.build(sources=sources + [str(entry)], output=binary,
                      defines=["FRAMEJOB_DEV_TOOLS"])
    return binary


def probe_rows(root=ROOT):
    global PROBE
    rows = [r for r in PROBE_ROWS if r in selected]
    if not rows and "I6" not in selected:
        return
    try:
        PROBE = build_probe(root)
    except swift_build.SwiftBuildFailed as error:
        for row in rows + (["I6"] if "I6" in selected else []):
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    if not rows:
        return
    request = WORK / "probe" / "request.json"
    request.write_text(json.dumps({"work": str(WORK / "probe" / "work")}))
    try:
        run = subprocess.run([str(PROBE), str(request)], capture_output=True, text=True,
                             timeout=300)
        lines = [line for line in run.stdout.splitlines() if line.startswith("{")]
        answer = {r["id"]: r for r in json.loads(lines[-1])["rows"]}
    except (subprocess.TimeoutExpired, ValueError, KeyError, IndexError) as error:
        for row in rows:
            check(row, False, f"the probe gave no answer: {error}")
        return
    for row in rows:
        got = answer.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


def probe_centroid(pack, need, coverage, width, height):
    if PROBE is None:
        raise RuntimeError("the probe was not built")
    request = WORK / "probe" / f"centroid-{os.getpid()}-{time.monotonic_ns()}.json"
    request.write_text(json.dumps({"pack": str(pack), "need": need, "coverage": coverage,
                                   "width": width, "height": height}))
    run = subprocess.run([str(PROBE), "centroid", str(request)], capture_output=True,
                         text=True, timeout=120)
    lines = [line for line in run.stdout.splitlines() if line.startswith("{")]
    answer = json.loads(lines[-1])
    if not answer.get("ok"):
        raise RuntimeError(f"the probe could not read {pack}: {answer}")
    return answer


# ---- the app rows --------------------------------------------------------------------------

class Doc:
    """A 640 × 360, 30 fps project of its own package."""

    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=W, height=H, fps=[30, 1], background=[0.2, 0.3, 0.4, 1])
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def media(self, fixture):
        media = self.call("import_media", path=str(fixture))["media"]
        return next(m for m in self.project()["media"] if m["id"] == media)

    def clip(self, media, start_in=0, duration=2 * SEC, track_index=0):
        """A clip of `media` on track `track_index` playing `[start_in, start_in + duration)`."""
        tracks = self.project()["tracks"]
        while len(tracks) <= track_index:
            self.call("add_track")
            tracks = self.project()["tracks"]
        track = tracks[track_index]["id"]
        before = {c["id"] for c in self.project()["clips"]}
        self.call("add_clip", track=track, media=media["id"], at=0)
        clip = next(c["id"] for c in self.project()["clips"] if c["id"] not in before)
        self.call("trim_end", clip=clip, to=start_in + duration)
        if start_in:
            self.call("trim_start", clip=clip, to=start_in)
        return clip

    def clip_json(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def marker(self, media):
        try:
            return json.loads((self.path / f"cache/analysis/masks/{media}.json").read_text())
        except (OSError, ValueError):
            return None

    def pack(self, media):
        return self.path / f"cache/analysis/masks/{media}/masks.pack"

    def show(self, clip):
        """Selects `clip` and shows Picture ▸ Background."""
        self.call("set_selection", clips=[clip])
        self.client.call("select_inspector_tab", tab="clip", sub_tab="picture",
                         section="video.cutout")

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def status_text(client, tag):
    """The Background section's Status read-out: the first `option.display` part after the
    "Status" label in the editor's layout dump; None when not found."""
    picture = WORK / f"snapshot-{tag}-{time.monotonic_ns()}.png"
    try:
        shot = client.call("snapshot_ui", window="editor", path=str(picture))
        with open(shot.get("layout_path") or "") as handle:
            views = json.load(handle)["views"]
    except (mcp.ToolError, OSError, ValueError, KeyError):
        return None
    start = next((i for i, v in enumerate(views)
                  if v.get("text") == "Status" and not v.get("hidden")), None)
    if start is None:
        return None
    for v in views[start + 1:]:
        if v.get("class") == "UISnapshotPart" and v.get("id") == "option.display":
            return v.get("text")
    return None


def wait_status(client, tag, accept, bound=STATUS_BOUND):
    """Polls the Status until `accept(text)` or `bound` s; (text, seconds)."""
    started = time.monotonic()
    text = None
    while True:
        text = status_text(client, tag)
        if text is not None and accept(text):
            return text, time.monotonic() - started
        if time.monotonic() - started >= bound:
            return text, time.monotonic() - started
        time.sleep(0.1)


def analyze(doc, clips, wait):
    return doc.call("analyze_cutout", clips=clips, wait=wait)


def settled(doc, clips):
    """`{wait: 60}` up to `WAIT_CALLS` times until every clip has settled; (answer, calls)."""
    answer = None
    for calls in range(1, WAIT_CALLS + 1):
        answer = analyze(doc, clips, 60)
        if all(row["state"] != "analyzing" for row in answer["clips"]):
            return answer, calls
    return answer, WAIT_CALLS


def row_of(answer, clip):
    return next((row for row in (answer or {}).get("clips", []) if row["clip"] == clip), None)


def short(row):
    if row is None:
        return "no row"
    keys = ("state", "progress", "frames", "covered", "ready", "subject_found", "centroid",
            "error")
    return "{" + ", ".join(f"{k}: {row.get(k)}" for k in keys if k in row) + "}"


def held_rows(client, push):
    doc = Doc(client, "held")
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        doc.show(clip)
        text, took = wait_status(client, "held", lambda t: t == "Analyzing 0 %")
        check("I2", text == "Analyzing 0 %",
              f"held: Status read {text!r} after {took:.1f} s (want \"Analyzing 0 %\")")
        row = row_of(analyze(doc, [clip], 0), clip)
        check("I4", row is not None and row["state"] == "analyzing" and row["ready"] is False
              and row["covered"] < row["frames"] and row["centroid"] is None,
              f"held, wait 0: {short(row)}")
    finally:
        doc.close()


def centroid_row(doc, media, need, row):
    coverage = (doc.marker(media["id"]) or {}).get("coverage") or []
    mine = probe_centroid(doc.pack(media["id"]), [need], coverage, media["width"],
                          media["height"])
    got = (row or {}).get("centroid")
    dx = abs(got["x"] - mine["x"]) if got and mine.get("x") is not None else None
    dy = abs(got["y"] - mine["y"]) if got and mine.get("y") is not None else None
    check("I6", dx is not None and dy is not None and dx <= 1e-6 and dy <= 1e-6
          and mine["frames"] > 0,
          f"analyze_cutout {got}; the probe's ({mine.get('x')}, {mine.get('y')}) over "
          f"{mine.get('frames')} frames of need {need}, coverage {coverage}; "
          f"|Δ| ({dx}, {dy}) ≤ 1e-6")


def person_rows(client, push, screen):
    doc = Doc(client, "person")
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        answer, calls = settled(doc, [clip])
        row = row_of(answer, clip)
        clip_json = doc.clip_json(clip)
        lower = clip_json["source"]["in"]
        need = need_of(lower, lower + clip_json["duration"], media)
        # CO-22's need holds the frame at the window's end its last tick can ask for, one more
        # than `get_media_analysis {clip}`'s window, so the store is asked over the need's
        # ticks: index k's frame is [k·20,000, (k + 1)·20,000).
        analysis = doc.call("get_media_analysis", media=media["id"], kind="masks",
                            **{"from": need[0] * FRAME, "to": (need[1] + 1) * FRAME})
        check("I4", row is not None and row["state"] == "ready" and row["ready"] is True
              and row["covered"] == row["frames"] == analysis.get("frames")
              == need[1] - need[0] + 1,
              f"wait 60 ({calls} call(s)): {short(row)}; need {need}; get_media_analysis "
              f"frames over it {analysis.get('frames')}")
        doc.show(clip)
        text, took = wait_status(client, "ready", lambda t: t == "Ready")
        check("I2", text == "Ready", f"landed: Status read {text!r} after {took:.1f} s")
        if "I6" in selected:
            centroid_row(doc, media, need, row)
    finally:
        doc.close()
    doc = Doc(client, "screen")
    try:
        media = doc.media(screen)
        clip = doc.clip(media)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        answer, calls = settled(doc, [clip])
        row = row_of(answer, clip)
        doc.show(clip)
        text, took = wait_status(client, "noperson", lambda t: t == "No person found")
        check("I2", row is not None and row["state"] == "no_person" and row["ready"] is True
              and row["centroid"] is None and text == "No person found",
              f"screen recording ({calls} call(s)): {short(row)}; Status {text!r} after "
              f"{took:.1f} s")
    finally:
        doc.close()


def i7(client, push):
    doc = Doc(client, "pair")
    folder = doc.path / "cache/analysis/masks"
    try:
        media = doc.media(push)
        a = doc.clip(media)
        doc.call("set_video", clips=[a], patch={"cutout": {}})
        first, _ = settled(doc, [a])
        if (row_of(first, a) or {}).get("state") != "ready":
            check("I7", False, f"clip A did not land ready: {short(row_of(first, a))}")
            return
        os.chmod(folder, 0o555)
        b = doc.clip(media, start_in=10 * SEC, track_index=1)
        doc.call("set_video", clips=[b], patch={"cutout": {}})
        answer, calls = settled(doc, [a, b])
        row_a, row_b = row_of(answer, a), row_of(answer, b)
        sentence = f"Clip {b}'s person masks could not be made: "
        doc.show(b)
        failed_text, _ = wait_status(client, "failed", lambda t: t.startswith("Failed: "))
        ok_failed = (row_b is not None and row_b["state"] == "failed"
                     and sentence in (row_b.get("error") or "")
                     and (failed_text or "").startswith("Failed: ")
                     and row_a is not None and row_a["state"] == "ready"
                     and row_a["centroid"] is not None)
        os.chmod(folder, 0o755)
        analyze(doc, [b], 0)
        left, took = wait_status(
            client, "retry",
            lambda t: not t.startswith("Failed") and (t.startswith("Analyzing ") or t == "Ready"),
            bound=I7_BOUND)
        ok_left = (left is not None and not left.startswith("Failed")
                   and (left.startswith("Analyzing ") or left == "Ready") and took <= I7_BOUND)
        again, again_calls = settled(doc, [b])
        row_again = row_of(again, b)
        check("I7", ok_failed and ok_left and (row_again or {}).get("state") == "ready",
              f"read-only ({calls} call(s)): A {short(row_a)}, B {short(row_b)}, B's Status "
              f"{failed_text!r}; restored: Status {left!r} after {took:.2f} s (≤ {I7_BOUND}); "
              f"wait 60 ({again_calls} call(s)): B {short(row_again)}")
    finally:
        try:
            os.chmod(folder, 0o755)
        except OSError:
            pass
        doc.close()


def launch_rows(binary, arguments, log, bodies):
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    try:
        if launched.client is None:
            for names, _ in bodies:
                for name in names & selected:
                    check(name, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid} ({' '.join(arguments)})", flush=True)
        for names, body in bodies:
            if not names & selected:
                continue
            try:
                body(launched)
            except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
                for name in names & selected:
                    check(name, False, f"{type(error).__name__}: {error}")
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{log.name}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def app_rows(binary):
    try:
        push, screen = co2a_proof.person_fixtures()
    except Exception as error:  # noqa: BLE001 — the fixture's failure is the rows'
        for name in selected & {"I2", "I4", "I6", "I7"}:
            check(name, False, f"the person fixtures (tools/proof/media/cutout/): {error}")
        return
    if selected & {"I2", "I4"}:
        launch_rows(binary, HOLD + PIN, WORK / "instance-h.log",
                    [({"I2", "I4"}, lambda l: held_rows(l.client, push))])
    launch_rows(binary, PIN, WORK / "instance-n.log",
                [({"I2", "I4", "I6"}, lambda l: person_rows(l.client, push, screen)),
                 ({"I7"}, lambda l: i7(l.client, push))])


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def mutant_tree(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "co3-mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return Path(made), None


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0])
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
    if selected & (set(APP_ROWS) - {"Z1"}):
        selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    root = ROOT
    binary = Path(args.app) if args.app else None
    before = {}
    if args.mutant:
        print(f"CO3 — the {args.mutant} MUTANT ({', '.join(MUTANTS[args.mutant][0])} must "
              f"FAIL, {proof_app.config()} build)", flush=True)
        before = {p: sha(ROOT / p) for p, _, _ in MUTANTS[args.mutant][1]}
        root, why = mutant_tree(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
        if selected & set(APP_ROWS):
            app, why = tree_copy.build_app(root, BUILD_BOUND)
            if app is None:
                print(f"mutant {args.mutant}: the control could not be performed — {why}")
                return 2
            binary = proof_app.executable(app)
    else:
        print(f"CO3 — Remove Background in the inspector and the menus "
              f"({proof_app.config()} build)", flush=True)
    probe_rows(root)
    if selected & set(APP_ROWS):
        binary = binary or proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\nscores: {len(passed)}/{len(results)}" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        after = {p: sha(ROOT / p) for p in before}
        restored = before == after
        print(f"the tree's mutated files' SHA-256 unchanged: {restored}")
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed)) and restored
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if named & set(failed) else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed and results else 1


if __name__ == "__main__":
    sys.exit(main())
