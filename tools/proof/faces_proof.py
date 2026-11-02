#!/usr/bin/env python3
"""Road map "creator-jobs" CJ3 — face samples on the Mac (spec §11 CJ-30…CJ-35).

    python3 tools/proof/faces_proof.py [--only P1,F3,…] [--mutant NAME] [--app PATH]

The fixtures are `face_fixtures.py`'s (`tools/proof/media/analysis/`, made on
first use; a missing FlexAudio picture is a scored failure naming its path).
Every row is a read-back: the probe's own answer, a tool's answer, or the
bytes of the cache's marker and `samples.bin`.

**Probe rows** (`faces_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app): P1 `samples.bin`'s
round trip, two publishes of disjoint ranges in either order giving equal
bytes, a damaged on-disk file replaced and its coverage reset; P2 CJ-31's
order and `topLeft`; P3 the sample a frame serves on 25 fps pts at 10 a
second (the first frame at or after, frame 3 for sample 1) and a gap over
one interval giving −1; P4 the stamp (kind version, `vision`, the per-request
`device` exactly CJ-32's, no path); P5 `facesAnswer`: at most 4 decimals in
its bytes, NaN null, a one-face row's bytes with and without `clip` (printed
for CJ-34), the cap's refusal naming the `source` of the first row that does
not fit and the same samples to that `to` answering.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`), on a scratch
`CFFIXED_USER_HOME`; Z1 is the launch's parity grep:
- F1 `faces_moving.mov`: the face centre's path within 2 % of the frame
  width (RMS) of the truth path; and through `clip` on a placement trimmed to
  play 10–40 s: every row's `source` in the window, `frame` at or after it
  within one sample, `clip_time` = `source` − the window's start, `timeline` =
  the clip's start + `clip_time`, the path again within 2 %.
- F2 `cache/analysis/faces/` removed and asked again: `samples.bin` byte-
  identical to the first run's (CJ-32's branch 1), the second call not
  cached, the stamp's `device` as P4. F2b `faces_converting.mov` (25 fps) with
  `set_media_color {log: slog3}`: the stamp's reader `converted`, every
  sample's `frame` the first of the file's frame pts (ffprobe) at or after its
  `source`, within one sample.
- F3 the portrait pair: |roll| < π/8 wherever a face is found; the rotated
  file finds a face in at least 90 % of the samples the upright one does, and
  there its face centre is within 2 % of the frame width (RMS) of the upright
  run's (F1's measure; the two files are separate lossy encodes).
- F4 `faces_two.mov`: every sample whose two truth boxes are whole in the frame
  holds two faces, left to right, each overlapping its truth; the first sample
  after the back face's truth box has left holds one.
- F5 S-TH1's mouth gap in speech against pauses: skipped by name, owed.
- F6 `faces_small.mov`'s recall at CJ-S2's size, beside CJ-S2's figure (at
  least 98 % of it).
- F7 seconds of work per minute of source (F1's run), recorded.

`--mutant NAME`: the named decision broken in a copy — `app/Sources` copied
for the probe's rows, the tree copied and built (`tree_copy.py`) for the
app's — and only its row run; CAUGHT (exit 0) when that row fails, SURVIVED
(exit 1) otherwise.
"""

import argparse
import json
import math
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "creator_spike"))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import face_fixtures  # noqa: E402
import faces_deciders  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/faces-proof"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
INTERVAL = 60_000            # one sample at 10 a second (CJ-30)
DEVICE = "rectangles:neural_engine;landmarks:neural_engine"   # CJ-32
SPIKE = ROOT / "tools/proof/work/creator_spike/CJ-S2/results.json"
SPIKE_SMALL_RECALL = 1.0     # CJ-30: CJ-S2's rule 3 at 720 (600 samples)
P_ROWS = ["P1", "P2", "P3", "P4", "P5"]
APP = ["F1", "F2", "F3", "F4", "F5", "F6", "F7"]
ROWS = P_ROWS + APP + ["Z1"]

MUTANTS = {
    "device-unpinned": (["P4"], [(
        "app/Sources/AnalysisVision.swift",
        "                request.setComputeDevice(pick, for: stage)\n", "")]),
    "orientation-ignored": (["F3"], [(
        "app/Sources/AnalysisFrames.swift", "var upright = Upright(transform: transform)",
        "var upright = Upright(transform: .identity)")]),
    "y-not-flipped": (["P2"], [(
        "app/Sources/AnalysisFaces.swift",
        "CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)",
        "CGRect(x: box.minX, y: box.minY, width: box.width, height: box.height)")]),
    "source-in-clip-ticks": (["F1"], [(
        "app/Sources/AgentServer+AnalysisFaces.swift",
        "            let source = grid.ticks(of: k)\n",
        "            let source = clip.map { $0.clipTime(ofSource: grid.ticks(of: k)) } "
        "?? grid.ticks(of: k)\n")]),
    "nearest-frame": (["P3"], [(
        "app/Sources/AnalysisFaces.swift",
        "        let after = previous ?? Int64.min\n        let upto = pts\n",
        "        let after = previous.map { ($0 + pts) / 2 } ?? Int64.min\n"
        "        let upto = pts + (pts - (previous ?? pts)) / 2\n")]),
}

results = {}
selected = set(ROWS)
row_bytes = {}


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def skip(name, why):
    if name in selected:
        print(f"  SKIP {name} {why}", flush=True)


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


# ---- the probe rows ------------------------------------------------------------

def probe_rows(sources):
    rows = [r for r in P_ROWS if r in selected]
    if not rows:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "faces_probe.swift", entry)
    binary = out / "faces-probe"
    try:
        swift_build.build(sources=[*swift_build.app_sources(sources), entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        for row in rows:
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    request = out / "request.json"
    request.write_text(json.dumps({"fixture": str(face_fixtures.path("faces_moving")),
                                   "work": str(out / "run")}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=900)
        answer = json.loads(run.stdout)
    except (subprocess.TimeoutExpired, ValueError) as error:
        for row in rows:
            check(row, False, f"the probe gave no answer: {error}")
        return
    by_id = {r["id"]: r for r in answer.get("rows", [])}
    for row in rows:
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))
    if "row_bytes" in answer:
        row_bytes.update(answer["row_bytes"])
        print(f"  CJ-34 row bytes: {json.dumps({k: v for k, v in row_bytes.items() if k != 'sample'})}")


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def media(self, fixture, tag):
        copy = WORK / "media" / f"{tag}{Path(fixture).suffix}"
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixture, copy)
        return self.call("import_media", path=str(copy))["media"], copy

    def faces(self, **arguments):
        """`get_media_analysis {kind: faces}`, called again while a call
        refuses at its wait's bound (what it covered is kept)."""
        for _ in range(60):
            try:
                return self.call("get_media_analysis", kind="faces", **arguments)
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        raise RuntimeError("the faces analysis did not finish in 60 calls")

    def folder(self):
        return self.path / "cache/analysis/faces"

    def samples_file(self, media):
        return self.folder() / str(media) / "samples.bin"

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def centre(box):
    return box[0] + box[2] / 2, box[1] + box[3] / 2


def path_rms(answer, record, name, width):
    """(RMS of the first face's centre against the truth, in px, over the
    samples holding a face; samples with a frame; samples with no face)."""
    errors, framed, empty = [], 0, 0
    for row in answer["samples"]:
        if row["frame"] is None:
            continue
        framed += 1
        if not row["faces"]:
            empty += 1
            continue
        truth = face_fixtures.truth(name, row["frame"] / SEC, record)[0]
        (fx, fy), (tx, ty) = centre(row["faces"][0]["box"]), centre(truth)
        errors.append(((fx - tx) * width) ** 2 + ((fy - ty) * width * 9 / 16) ** 2)
    rms = math.sqrt(sum(errors) / len(errors)) if errors else None
    return rms, framed, empty


def plain_rows(client, record):
    doc = Doc(client, "faces")
    fps = {}

    def f1():
        media, _ = doc.media(face_fixtures.path("faces_moving"), "moving")
        fps["moving"] = media
        answer = doc.faces(media=media)
        fps["moving_answer"] = answer
        rms, framed, empty = path_rms(answer, record, "faces_moving", 1920)
        ok = rms is not None and rms <= 0.02 * 1920 and answer["count"] == 600
        track = doc.state()["tracks"][0]["id"]
        clip = doc.call("add_clip", track=track, media=media, at=0)["new_clips"][0]
        doc.call("trim_start", clip=clip, to=10 * SEC)
        doc.call("trim_end", clip=clip, to=40 * SEC)
        placed = next(c for c in doc.state()["clips"] if c["id"] == clip)
        trimmed = doc.faces(clip=clip)
        lo, hi = 10 * SEC, 40 * SEC
        bad = [r["source"] for r in trimmed["samples"] if not (
            lo <= r["source"] < hi and r["frame"] is not None
            and 0 <= r["frame"] - r["source"] < INTERVAL
            and r["clip_time"] == r["source"] - lo
            and r["timeline"] == placed["start"] + r["clip_time"])]
        rms2, framed2, empty2 = path_rms(trimmed, record, "faces_moving", 1920)
        ok2 = not bad and trimmed["count"] == 300 and rms2 is not None and rms2 <= 0.02 * 1920
        check("F1", ok and ok2,
              f"whole media: {answer['count']} samples, RMS {rms:.2f} px over {framed - empty} "
              f"with a face ({empty} without; bar {0.02 * 1920:.1f}); trimmed placement "
              f"(start {placed['start']}): {trimmed['count']} samples (want 300), "
              f"{len(bad)} rows off their window, frame, clip_time or timeline "
              f"{bad[:3]}, RMS {rms2:.2f} px ({empty2} without a face)")
    if selected & {"F1", "F2", "F7"}:
        attempt(f1, "F1")

    def f2():
        media = fps["moving"]
        first = doc.samples_file(media).read_bytes()
        shutil.rmtree(doc.folder())
        answer = doc.faces(media=media)
        second = doc.samples_file(media).read_bytes()
        stamp = answer.get("stamp") or {}
        check("F2", first == second and answer["cached"] is False
              and stamp.get("device") == DEVICE,
              f"samples.bin {len(first)} and {len(second)} bytes, identical {first == second}; "
              f"second call cached {answer['cached']} (want false); stamp device "
              f"{stamp.get('device')} (want {DEVICE}), reader {stamp.get('reader')}")

        media, copy = doc.media(face_fixtures.path("faces_converting"), "converting")
        doc.call("set_media_color", media=media, color={"log": "slog3"})
        answer = doc.faces(media=media)
        frames = face_fixtures.frame_ticks(copy)
        wrong = []
        for row in answer["samples"]:
            want = next((p for p in frames if p >= row["source"]), None)
            if want is not None and want - row["source"] >= INTERVAL:
                want = None
            if row["frame"] != want:
                wrong.append((row["source"], row["frame"], want))
        reader = (answer.get("stamp") or {}).get("reader")
        check("F2", reader == "converted" and not wrong and answer["count"] == 200,
              f"F2b the converting fixture at 25 fps: reader {reader} (want converted), "
              f"{answer['count']} samples, {len(wrong)} whose frame is not the first at or "
              f"after its source {wrong[:3]}")
    if "F2" in selected:
        attempt(f2, "F2")

    def f3():
        up, _ = doc.media(face_fixtures.path("faces_portrait"), "portrait")
        rot, _ = doc.media(face_fixtures.OUT / "faces_portrait_rot.mov", "portrait_rot")
        a, b = doc.faces(media=up), doc.faces(media=rot)
        rolls = [f["roll"] for r in a["samples"] + b["samples"] for f in r["faces"]]
        tilted = [x for x in rolls if x is None or abs(x) >= math.pi / 8]
        found_up = [r for r in a["samples"] if len(r["faces"]) == 1]
        squares, worst = [], 0.0
        by_source = {r["source"]: r for r in b["samples"]}
        for r in found_up:
            other = by_source.get(r["source"])
            if other and len(other["faces"]) == 1:
                one, two = r["faces"][0]["box"], other["faces"][0]["box"]
                (ux, uy), (rx, ry) = centre(one), centre(two)
                squares.append(((ux - rx) * 1080) ** 2 + ((uy - ry) * 1920) ** 2)
                worst = max([worst] + [abs(x - y) for x, y in zip(one, two)])
        share = len(squares) / len(found_up) if found_up else 0
        rms = math.sqrt(sum(squares) / len(squares)) if squares else None
        check("F3", not tilted and found_up and share >= 0.9 and rms is not None
              and rms <= 0.02 * 1080 and a["size"] == b["size"] == [1080, 1920],
              f"sizes {a['size']} and {b['size']}; {len(rolls)} faces, {len(tilted)} with "
              f"|roll| ≥ π/8 {tilted[:3]}; upright one face in {len(found_up)} of "
              f"{a['count']}, the rotated too in {len(squares)} ({share:.3f}, want ≥ 0.9); "
              f"the centres {rms and round(rms, 2)} px apart (RMS; want ≤ {0.02 * 1080:.1f}, "
              f"2 % of the width), the largest box value difference {worst:.4f}")
    if "F3" in selected:
        attempt(f3, "F3")

    def f4():
        media, _ = doc.media(face_fixtures.path("faces_two"), "two")
        answer = doc.faces(media=media)
        leaves = record["two_leaves_s"]
        whole_bad, both_rows, after = [], 0, None
        for r in answer["samples"]:
            if r["frame"] is None:
                continue
            t = r["frame"] / SEC
            back, front = face_fixtures.truth("faces_two", t, record)
            whole = all(b[1] >= 0 and b[1] + b[3] <= 1 for b in (back, front))
            if whole:
                both_rows += 1
                boxes = [f["box"] for f in r["faces"]]
                if not (len(boxes) == 2 and centre(boxes[0])[0] < centre(boxes[1])[0]
                        and faces_deciders.overlaps(boxes[0], back)
                        and faces_deciders.overlaps(boxes[1], front)):
                    whole_bad.append((r["source"], len(boxes)))
            if after is None and t > leaves:
                after = r
        ok = both_rows > 0 and not whole_bad and after is not None and len(after["faces"]) == 1
        check("F4", ok,
              f"{both_rows} samples with both whole, {len(whole_bad)} not two faces left to "
              f"right on their truths {whole_bad[:3]}; the back face leaves at {leaves:.3f} s, "
              f"the next sample ({after and after['source'] / SEC} s) holds "
              f"{after and len(after['faces'])} (want 1)")
    if "F4" in selected:
        attempt(f4, "F4")

    skip("F5", "S-TH1 (the owner's talking head) is missing: its mouth gap in speech against "
         "pauses is owed")

    def f6():
        media, _ = doc.media(face_fixtures.path("faces_small"), "small")
        answer = doc.faces(media=media)
        pairs = [(face_fixtures.truth("faces_small", r["frame"] / SEC, record)[0],
                  [f["box"] for f in r["faces"]]) for r in answer["samples"]
                 if r["frame"] is not None]
        recall = faces_deciders.recall(pairs)
        spike = SPIKE_SMALL_RECALL
        if SPIKE.exists():
            rows = json.loads(SPIKE.read_text()).get("size_rows", {})
            spike = rows.get("720", {}).get("recall", spike)
        check("F6", recall is not None and recall >= 0.98 * spike,
              f"recall {recall:.4f} over {len(pairs)} samples at 720, CJ-S2's {spike:.4f} "
              f"(want ≥ 98 % of it)")
    if "F6" in selected:
        attempt(f6, "F6")

    def f7():
        answer = fps.get("moving_answer") or {}
        run = answer.get("run") or {}
        started, ended = run.get("started_at"), run.get("ended_at")
        seconds = ended - started if started is not None and ended is not None else None
        per_minute = seconds / 1.0 if seconds is not None else None
        check("F7", per_minute is not None,
              f"F1's whole-media run: {seconds and round(seconds, 2)} s for 60 s of 1080p30 "
              f"source, {per_minute and round(per_minute, 2)} s per minute ({proof_app.config()})")
    if "F7" in selected:
        attempt(f7, "F7")
    doc.close()


def launch(binary):
    log = WORK / "instance.log"
    launched = mcp.launch(str(binary), [],
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def app_rows(binary, record):
    if not selected & set(APP):
        return
    launched, log = launch(binary)
    try:
        if launched.client is None:
            for row in selected & set(APP):
                check(row, False, "the app did not listen")
            return
        print(f"  instance PID {launched.child.pid}", flush=True)
        plain_rows(launched.client, record)
    finally:
        launched.stop()
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


# ---- mutants -------------------------------------------------------------------

def mutant_sources(name):
    copy = WORK / "mutant-sources"
    shutil.rmtree(copy, ignore_errors=True)
    shutil.copytree(ROOT / "app/Sources", copy)
    for path, anchor, replacement in MUTANTS[name][1]:
        target = copy / Path(path).name
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    return copy, None


def mutant_app(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "faces-mutant"))
    if made is None:
        return None, reason
    for path, anchor, replacement in MUTANTS[name][1]:
        target = Path(made) / path
        text = target.read_text()
        if text.count(anchor) != 1:
            return None, f"the anchor occurs {text.count(anchor)} times in {path}"
        target.write_text(text.replace(anchor, replacement))
    app, reason = tree_copy.build_app(Path(made), BUILD_BOUND)
    return (proof_app.executable(app), None) if app else (None, reason)


def main():
    global selected
    parser = argparse.ArgumentParser()
    parser.add_argument("--only")
    parser.add_argument("--mutant", choices=sorted(MUTANTS))
    parser.add_argument("--app")
    args = parser.parse_args()
    if args.mutant:
        selected = set(MUTANTS[args.mutant][0]) | {"Z1"}
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(APP):
            selected.add("Z1")
    if selected & {"F2", "F7"}:
        selected.add("F1")  # their run's first
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    try:
        record = face_fixtures.make()
    except face_fixtures.Missing as missing:
        print(f"  FAIL fixtures: {missing} is missing")
        return 1
    sources = ROOT / "app/Sources"
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"CJ3 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        if set(named) <= set(P_ROWS):
            sources, why = mutant_sources(args.mutant)
        else:
            binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CJ3 — face samples on the Mac ({proof_app.config()} build)", flush=True)
    probe_rows(sources)
    if selected & set(APP):
        if binary is None:
            binary = proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary, record)
    if not (selected & set(APP)):
        selected.discard("Z1")
    failed = [name for name, runs in results.items() if not all(ok for ok, _ in runs)]
    passed = [name for name in results if name not in failed]
    print(f"\n{len(passed)}/{len(results)} rows passed" + (f"; failed {failed}" if failed else ""))
    if args.mutant:
        named = set(MUTANTS[args.mutant][0])
        caught = bool(named & set(failed))
        print(f"MUTANT {args.mutant} {'CAUGHT' if caught else 'SURVIVED'}: "
              f"{', '.join(sorted(named))} {'failed' if caught else 'passed'}")
        return 0 if caught else 1
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
