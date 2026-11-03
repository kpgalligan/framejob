#!/usr/bin/env python3
"""Road map "creator-jobs" VR1 — people and salient regions on the Mac, and
View ▸ Show Subjects (spec §11 VR-10…VR-16).

    python3 tools/proof/vr1_proof.py [--only P1,V3,…] [--mutant NAME] [--app PATH]

The fixtures are `face_fixtures.py`'s (`tools/proof/media/analysis/`, made on
first use). Every row is a read-back: the probe's own answer, a tool's answer,
or the bytes of the cache's marker and `samples.bin`.

**Probe rows** (`vr1_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app): P1 `samples.bin`'s
codec (`FJSB`, 20-byte boxes, a sample's people then its salient boxes) and the
merge in either order, a damaged file replaced; P2 CJ-31's order and the y
flip; P3 the stamp (`upper_body`, revision 2, the per-request `device`) and the
requests (`upperBodyOnly` true, VR-4 as VR-10 amends it); P4
`subjectsAnswer`: at most 4 decimals, the row's bytes (VR-14), the cap's
refusal; P5 `FramingAnalysis.windows`: two clips of one media merged once
widened, a third apart, a ×2 clip of another media, a text clip skipped; P6
every `subjects` sample instant a `faces` one, and `sampleIndex`; P7 the
overlay's corners on a cropped, scaled, moved and turned placement against
(★) written out, and its source tick on a ×2, a reversed and a ramped clip
against the speed, `ReverseMirror` and the `SourceMap`.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`), on a scratch
`CFFIXED_USER_HOME`; Z1 is each launch's parity grep:
- V1 `faces_moving.mov`: a person box holds the `faces` kind's face centre in
  at least 95 % of the samples holding both; `subjects_moving.mov`'s two men
  recorded (truth centres held), no threshold.
- V2 `cache/analysis/subjects/` removed and asked again: `samples.bin`
  byte-identical, the second call not cached, the stamp's `device`
  `AnalysisSubjects.device` and its vision `upper_body`.
- V3 the portrait pair: the rotated file's person centres within 2 % of the
  frame width (RMS) of the upright run's, on samples where both find one.
- V4 every `subjects` `source` is a `faces` `source` (V1's answers).
- V6 `analysis_job {clips}` over two separated clips of one media and one of
  another, waited: each kind's marker coverage equals the grid's need over
  each window ± 1 s, widened by the kind's margin, merged.
- V8 an uncached clip selected, View ▸ Show Subjects by `perform_menu_item`,
  five playhead moves: `lane_queued` unchanged, no `cache/analysis/subjects`,
  the item off again (mcp.py's DEFAULTS MOVED guard ends the run).
- V9 in a launch of its own with `-RCDevAnalysisHold 5`, `analysis_job
  {media, kind: subjects}` on a fresh media, the only job: `ended_at` at least
  `started_at` + 5 s and `outcome` landed.
- V10 S-TH4 (HLG) person recall: skipped by name, owed.

`--mutant NAME`: the named decision broken in a copy — `app/Sources` copied
for the probe's rows, the tree copied and built as Release (`tree_copy.py`)
for the app's — and only its row run; CAUGHT (exit 0) when that row fails,
SURVIVED (exit 1) otherwise.
"""

import argparse
import json
import math
import shutil
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "creator_spike"))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import face_fixtures  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import subjects_deciders  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/vr1-proof"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
SEC = 600_000
DEVICE = "people:neural_engine;salient:neural_engine"   # VR-11
SHOTS_MARGIN = 13            # AnalysisShots.margin, CJ-24
P_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7"]
APP = ["V1", "V2", "V3", "V4", "V6", "V8", "V9", "V10"]
ROWS = P_ROWS + APP + ["Z1"]

MUTANTS = {
    "grid-by-frame-index": (["V4"], [(
        "app/Sources/AnalysisStamp.swift",
        "            return AnalysisGrid(samplesPerSecond: AnalysisSubjects.rate, "
        "duration: media.duration)\n",
        "            return AnalysisGrid(media: media)\n")]),
    "orientation-not-applied": (["V3"], [(
        "app/Sources/AnalysisFrames.swift", "var upright = Upright(transform: transform)",
        "var upright = Upright(transform: .identity)")]),
    "framing-whole-media": (["V6"], [(
        "app/Sources/FramingAnalysis.swift",
        "            let lower = max(0, played.lowerBound - margin)\n"
        "            let upper = min(max(0, media.duration), played.upperBound + margin)\n",
        "            let lower: Ticks = 0\n"
        "            let upper = max(0, media.duration)\n")]),
    "source-tick-no-mirror": (["P7"], [(
        "app/Sources/SubjectsOverlay.swift",
        "        TimelineView.sourceTime(of: clip, in: media, at: playhead, map: map)\n",
        "        clip.source.isReversed\n"
        "            ? ReverseMirror.mirrored(\n"
        "                TimelineView.sourceTime(of: clip, in: media, at: playhead, map: map),\n"
        "                about: media.duration)\n"
        "            : TimelineView.sourceTime(of: clip, in: media, at: playhead, map: map)\n")]),
    "show-subjects-wants": (["V8"], [(
        "app/Sources/EditorViewController+Subjects.swift",
        "        canvas.subjects = SubjectsOverlay(document: document) { [weak canvas] in\n",
        "        if let wanted = try? FramingAnalysis.requests(\n"
        "            clips: Array(document.selection), in: document), !wanted.isEmpty\n"
        "        {\n"
        "            AnalysisLane.shared.want(\n"
        "                wanted, owner: AnalysisLane.shared.newOwner(), alive: { true },\n"
        "                settled: nil)\n"
        "        }\n"
        "        canvas.subjects = SubjectsOverlay(document: document) { [weak canvas] in\n")]),
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
    shutil.copyfile(HERE / "vr1_probe.swift", entry)
    binary = out / "vr1-probe"
    try:
        swift_build.build(sources=[*swift_build.app_sources(sources), entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        for row in rows:
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    request = out / "request.json"
    request.write_text(json.dumps({"fixture": str(face_fixtures.path("faces_moving")),
                                   "fixture_b": str(face_fixtures.path("faces_small")),
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
        print(f"  VR-14 row bytes: "
              f"{json.dumps({k: v for k, v in row_bytes.items() if k != 'sample'})}")


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

    def analysis(self, kind, **arguments):
        """`get_media_analysis`, called again while a call refuses at its
        wait's bound (what it covered is kept)."""
        for _ in range(60):
            try:
                return self.call("get_media_analysis", kind=kind, **arguments)
            except mcp.ToolError as error:
                if "call again to continue" not in str(error):
                    raise
        raise RuntimeError(f"the {kind} analysis did not finish in 60 calls")

    def folder(self, kind="subjects"):
        return self.path / "cache/analysis" / kind

    def samples_file(self, media):
        return self.folder() / str(media) / "samples.bin"

    def marker(self, kind, media):
        path = self.folder(kind) / f"{media}.json"
        return json.loads(path.read_text()) if path.exists() else None

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def centre(box):
    return box[0] + box[2] / 2, box[1] + box[3] / 2


def contains(box, point):
    return subjects_deciders.contains(box, point)


def merged(ranges):
    out = []
    for low, high in sorted(ranges):
        if out and low <= out[-1][1] + 1:
            out[-1][1] = max(out[-1][1], high)
        else:
            out.append([low, high])
    return out


def need(window, rate, duration, margin):
    """The grid indices of [from, to) widened by `margin`, as `AnalysisGrid`
    reads them (`rate` indices per tick)."""
    count = max(1, math.ceil(duration * rate - 1e-6))
    low = max(0, math.ceil(window[0] * rate - 1e-9))
    high = min(count - 1, math.ceil(window[1] * rate - 1e-9) - 1)
    if low > high:
        return None
    return [max(0, low - margin), min(count - 1, high + margin)]


def fps_of(media):
    fps = media.get("fps")
    if isinstance(fps, dict):
        return fps["num"], fps["den"]
    return fps[0], fps[1]


def plain_rows(client, record):
    doc = Doc(client, "subjects")
    kept = {}

    def v1():
        media, _ = doc.media(face_fixtures.path("faces_moving"), "moving")
        kept["moving"] = media
        subjects = doc.analysis("subjects", media=media)
        faces = doc.analysis("faces", media=media)
        kept["subjects"], kept["faces"] = subjects, faces
        by_source = {r["source"]: r for r in faces["samples"]}
        both = hits = 0
        for row in subjects["samples"]:
            face_row = by_source.get(row["source"])
            if row["frame"] is None or not face_row or not face_row["faces"]:
                continue
            both += 1
            point = centre(face_row["faces"][0]["box"])
            if any(contains(p["box"], point) for p in row["people"]):
                hits += 1
        share = hits / both if both else 0
        other, _ = doc.media(face_fixtures.path("subjects_moving"), "subjects_moving")
        answer = doc.analysis("subjects", media=other)
        figures = {}
        for face, label in ((0, "back"), (1, "front")):
            pairs = [(face_fixtures.truth("subjects_moving", r["frame"] / SEC, record)[face],
                      [p["box"] for p in r["people"]]) for r in answer["samples"]
                     if r["frame"] is not None]
            figures[label] = subjects_deciders.centre_recall(pairs)
        kept["v1"] = {"faces_moving": [hits, both], "subjects_moving": figures}
        check("V1", both > 0 and share >= 0.95 and subjects["count"] > 0,
              f"faces_moving: a person box holds the face centre in {hits}/{both} samples "
              f"({share:.4f}, want ≥ 0.95), {subjects['count']} samples at {subjects['rate']}/s; "
              f"subjects_moving (recorded): front {figures['front'][0]}/{figures['front'][1]}, "
              f"back {figures['back'][0]}/{figures['back'][1]}")
    if selected & {"V1", "V2", "V4"}:
        attempt(v1, "V1")

    def v2():
        media = kept["moving"]
        first = doc.samples_file(media).read_bytes()
        shutil.rmtree(doc.folder())
        answer = doc.analysis("subjects", media=media)
        second = doc.samples_file(media).read_bytes()
        stamp = answer.get("stamp") or {}
        vision = stamp.get("vision") or {}
        check("V2", first == second and answer["cached"] is False
              and stamp.get("device") == DEVICE and vision.get("quality") == "upper_body"
              and vision.get("revision") == 2,
              f"samples.bin {len(first)} and {len(second)} bytes, identical {first == second}; "
              f"second call cached {answer['cached']} (want false); stamp device "
              f"{stamp.get('device')} (want {DEVICE}), vision {vision}, reader "
              f"{stamp.get('reader')}")
    if "V2" in selected:
        attempt(v2, "V2")

    def v3():
        up, _ = doc.media(face_fixtures.path("faces_portrait"), "portrait")
        rot, _ = doc.media(face_fixtures.OUT / "faces_portrait_rot.mov", "portrait_rot")
        a, b = doc.analysis("subjects", media=up), doc.analysis("subjects", media=rot)
        by_source = {r["source"]: r for r in b["samples"]}
        upright = [r for r in a["samples"] if r["people"]]
        squares = []
        for r in upright:
            other = by_source.get(r["source"])
            if other and other["people"]:
                (ux, uy), (rx, ry) = centre(r["people"][0]["box"]), centre(other["people"][0]["box"])
                squares.append(((ux - rx) * 1080) ** 2 + ((uy - ry) * 1920) ** 2)
        share = len(squares) / len(upright) if upright else 0
        rms = math.sqrt(sum(squares) / len(squares)) if squares else None
        check("V3", upright and share >= 0.9 and rms is not None and rms <= 0.02 * 1080
              and a["size"] == b["size"] == [1080, 1920],
              f"sizes {a['size']} and {b['size']}; upright a person in {len(upright)} of "
              f"{a['count']}, the rotated too in {len(squares)} ({share:.3f}, want ≥ 0.9); the "
              f"first person's centres {rms and round(rms, 2)} px apart (RMS; want ≤ "
              f"{0.02 * 1080:.1f}, 2 % of the width)")
    if "V3" in selected:
        attempt(v3, "V3")

    def v4():
        subjects, faces = kept["subjects"], kept["faces"]
        face_sources = {r["source"] for r in faces["samples"]}
        stray = [r["source"] for r in subjects["samples"] if r["source"] not in face_sources]
        check("V4", subjects["count"] > 0 and not stray,
              f"{subjects['count']} subjects samples at {subjects['rate']}/s against "
              f"{faces['count']} faces samples at {faces['rate']}/s: {len(stray)} subjects "
              f"sources not a faces source {stray[:3]}")
    if "V4" in selected:
        attempt(v4, "V4")

    doc.close()

    def v6():
        framing = Doc(client, "framing")
        try:
            a, _ = framing.media(face_fixtures.path("faces_moving"), "framing_a")
            b, _ = framing.media(face_fixtures.path("faces_small"), "framing_b")
            for _ in range(2):
                framing.call("add_track")
            tracks = [t["id"] for t in framing.state()["tracks"]]
            placed = []
            for track, media, lo, hi in ((tracks[0], a, 5, 10), (tracks[1], a, 40, 45),
                                         (tracks[2], b, 20, 25)):
                clip = framing.call("add_clip", track=track, media=media,
                                    at=(100 - lo) * SEC)["new_clips"][0]
                framing.call("trim_start", clip=clip, to=100 * SEC)
                framing.call("trim_end", clip=clip, to=(100 + hi - lo) * SEC)
                placed.append((clip, media, lo, hi))
            framing.call("save_project")
            answer = framing.call("analysis_job", clips=[c for c, _, _, _ in placed])
            wanted = answer.get("wanted") or {}
            for _ in range(30):
                jobs = framing.call("analysis_job", wait=60)["jobs"]
                mine = [j for j in jobs if j["project"]
                        and Path(j["project"]).resolve() == framing.path.resolve()]
                if mine and all(j.get("outcome") for j in mine):
                    break
            outcomes = sorted({j.get("outcome") or "open" for j in mine})
            state = framing.state()
            media_rows = {m["id"]: m for m in state["media"]}
            bad = []
            for kind in ("shots", "faces", "subjects"):
                for media in (a, b):
                    row = media_rows[media]
                    duration = row["duration"]
                    if kind == "shots":
                        num, den = fps_of(row)
                        rate, margin = num / (SEC * den), SHOTS_MARGIN
                    else:
                        per = answer_rate(kind)
                        rate, margin = per / SEC, 0
                    ranges = [need((max(0, (lo - 1) * SEC), min(duration, (hi + 1) * SEC)),
                                   rate, duration, margin)
                              for _, m, lo, hi in placed if m == media]
                    want = merged([r for r in ranges if r])
                    marker = framing.marker(kind, media)
                    got = marker and marker.get("coverage")
                    if got != want:
                        bad.append(f"{kind} media {media}: coverage {got}, want {want}")
            check("V6", wanted.get("requests") == 6 and outcomes == ["landed"] and not bad,
                  f"wanted {wanted} (want 6 requests: 3 kinds × 2 media), outcomes {outcomes}; "
                  f"{'every marker as its windows ± 1 s' if not bad else '; '.join(bad)}")
        finally:
            framing.close()
    if "V6" in selected:
        attempt(v6, "V6")

    def v8():
        shown = Doc(client, "shown")
        try:
            media, _ = shown.media(face_fixtures.path("faces_small"), "shown")
            track = shown.state()["tracks"][0]["id"]
            clip = shown.call("add_clip", track=track, media=media, at=0)["new_clips"][0]
            shown.call("save_project")
            before = shown.call("analysis_job")["lane_queued"]
            shown.call("set_selection", clips=[clip])
            shown.call("perform_menu_item", path=["View", "Show Subjects"])
            for second in (1, 7, 13, 29, 41):
                shown.call("set_playhead", t=second * SEC)
            time.sleep(1.0)
            after = shown.call("analysis_job")["lane_queued"]
            folder = shown.folder()
            shown.call("perform_menu_item", path=["View", "Show Subjects"])
            check("V8", before == after and not folder.exists(),
                  f"lane_queued {before} before and {after} after Show Subjects and five "
                  f"playhead moves (want equal); cache/analysis/subjects exists "
                  f"{folder.exists()} (want false)")
        finally:
            shown.close()
    if "V8" in selected:
        attempt(v8, "V8")

    skip("V10", "S-TH4 (the owner's HLG sample) is missing: its person recall through the "
         "converted reader is owed (VR-S1 rule 5)")


_rates = {}


def answer_rate(kind):
    return _rates[kind]


def held_row(client):
    """V9: the hold, in its own launch."""
    doc = Doc(client, "held")
    try:
        media, _ = doc.media(face_fixtures.path("faces_small"), "held")
        doc.call("save_project")
        doc.call("analysis_job", media=media, kind="subjects")
        row = {}
        for _ in range(30):
            jobs = doc.call("analysis_job", wait=60)["jobs"]
            row = jobs[-1] if jobs else {}
            if row.get("outcome"):
                break
        started, ended = row.get("started_at"), row.get("ended_at")
        ok = (len(jobs) == 1 and row.get("outcome") == "landed" and started is not None
              and ended is not None and ended >= started + 5)
        check("V9", ok,
              f"{len(jobs)} job(s) (want 1); the subjects job started {started}, ended {ended} "
              f"({ended and started and round(ended - started, 2)} s; want ≥ 5 under "
              f"-RCDevAnalysisHold 5), outcome {row.get('outcome')} (want landed)")
    finally:
        doc.close()


def launch(binary, arguments=()):
    log = WORK / f"instance{'-held' if arguments else ''}.log"
    launched = mcp.launch(str(binary), list(arguments),
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def parity(log):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"grep 'Frame Job: ' in {log.name} printed {lines[:3] or 'nothing'}")


def app_rows(binary, record):
    plain = selected & (set(APP) - {"V9"})
    if plain:
        launched, log = launch(binary)
        try:
            if launched.client is None:
                for row in plain:
                    check(row, False, "the app did not listen")
            else:
                print(f"  instance PID {launched.child.pid}", flush=True)
                plain_rows(launched.client, record)
        finally:
            launched.stop()
        parity(log)
    if "V9" in selected:
        launched, log = launch(binary, ["-RCDevAnalysisHold", "5"])
        try:
            if launched.client is None:
                check("V9", False, "the app did not listen")
            else:
                print(f"  held instance PID {launched.child.pid}", flush=True)
                attempt(lambda: held_row(launched.client), "V9")
        finally:
            launched.stop()
        parity(log)


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
    made, reason = tree_copy.make_copy(str(WORK.parent / "vr1-mutant"))
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
    if selected & {"V2", "V4"}:
        selected.add("V1")  # their run's first
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))
    HOME.mkdir(parents=True)
    try:
        record = face_fixtures.make()
    except face_fixtures.Missing as missing:
        print(f"  FAIL fixtures: {missing} is missing")
        return 1
    _rates.update({"faces": 10.0, "subjects": subjects_rate()})
    sources = ROOT / "app/Sources"
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"VR1 — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        if set(named) <= set(P_ROWS):
            sources, why = mutant_sources(args.mutant)
        else:
            binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"VR1 — people and salient regions on the Mac ({proof_app.config()} build)",
              flush=True)
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


def subjects_rate():
    """`AnalysisSubjects.rate`, read from its source line (VR-11)."""
    text = (ROOT / "app/Sources/AnalysisSubjects.swift").read_text()
    for line in text.splitlines():
        if line.strip().startswith("static let rate: Double ="):
            value = line.split("=", 1)[1].strip()
            return {"AnalysisFaces.rate": 10.0,
                    "AnalysisFaces.rate / 2": 5.0}.get(value, None) or float(value)
    raise SystemExit("no AnalysisSubjects.rate line")


if __name__ == "__main__":
    sys.exit(main())
