#!/usr/bin/env python3
"""Road map "creator-jobs" CJ2a — the analysis lane, its store and reader, and
`shots` (spec §11 CJ-20…CJ-27).

    python3 tools/proof/analysis_proof.py [--only P1,A3,…] [--mutant NAME] [--app PATH]

The fixtures are `analysis_fixtures.py`'s (made on first use). Every row is a
read-back: a probe's own answer, a tool's answer, or the bytes of the
cache's marker and `frames.bin`.

**Probe rows** (`analysis_probe.swift`, built from `app/Sources` with
`FRAMEJOB_DEV_TOOLS` through `swift_build.py`; no app):
- P1 each stamp field alone (source size, modified second, duration, version,
  parameters, OS build, device, reader) makes a lookup miss.
- P2 coverage unions merge adjacent ranges; the hit rule counts the read
  margin (m + 1 = 13) each side.
- P3 the cut rule: a flash, a tie to the earlier, a dissolve under T, m, no
  frame within m + 1 after, the media's end.
- P4 `frames.bin` round trip, against hand-spelt little-endian bytes.
- P5 a canned marker answers only with the flag and a matching source.
- P6 a trimmed, a ×2 and a reversed clip's window and clip times.
- P7 the VFR twin: `frames.bin` over the 21 indices after each gap equal from a
  whole-file job and from a job starting just after the gap, and the cut at
  4 s found by both.
- P8 two publishes of disjoint ranges from one on-disk state, in either order
  and at once, both kept.
- P9 a publish started while `CacheLedger.saveBegan` holds the folder writes no
  marker or payload until `saveEnded`, then both (CJ-22's one door).
- P10 `AnalysisShots.run` over `shots.mov`'s whole grid cancelled at half
  answers false and keeps what it stored (spec §11 CJ-21 as amended by #435):
  one range [0, k], 0 < k < the last index, records 0…k byte-equal to a whole
  run's.
- P11 the cancel publish only merges: (a) inside `publishCancelled` under
  another stamp over a cache leaves marker and `frames.bin` byte-identical;
  (b) under the cache's own stamp it merges; (c) on an empty cache it writes;
  (d) an ordinary publish under another stamp still replaces (CJ-22).

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`), each launch on a
scratch `CFFIXED_USER_HOME`; Z1 is each launch's parity grep:
- A1 `get_media_analysis {media, kind: shots}` answers exactly the fixture's
  hard cuts (60, 120, 180, 240): none at the flash (150) or inside the
  dissolve (300…329); `cached` false and a `run`.
- A2 a second call answers `cached: true`, no `run`, the marker's and
  payload's bytes unchanged.
- A3 a window inside the coverage is a hit; one past it runs only the
  missing range (cached false, cuts 180 and 240) and the coverage becomes the
  union, the earlier payload bytes unchanged.
- A4 the media's modification time moved: the next call is a miss whose stamp
  names the new second.
- A5 (hold 3 s) `analysis_job` X; `save_project` X; `analysis_job {wait}`: X
  landed after the save returned; the next `save_project` is not refused; the
  marker and payload are there.
- A6 (hold) `analysis_job {}` (t0); `analysis_job` Y; `close_project` Y;
  `analysis_job {wait: 5}`: Y cancelled within 1.5 s of t0, no marker or
  payload for its media.
- A7 (hold) two documents' jobs at once: their runs do not overlap (width 1,
  CJ-S3).
- A8 a canned marker (a fake cut at frame 7) is replaced by a real job
  without `-RCDevAnalysisCanned YES`, and answered (`canned`, cuts [7]) with
  it.
- A9 a whole-file call, and two half-window calls split at the flash (151) in
  either order: the halves' cuts together, and the whole window after them,
  equal the whole-file call's cuts, and the three payloads are equal.
- A10 `set_media_color` with a Camera Log: the next call is a miss whose
  stamp names the converted reader and its conversion; clearing it, another
  miss, raw again.
- A11 (hold) `analysis_job` X; `relink_media` X's media to the same file (a
  copy at another path keeping its bytes and modification second, since a
  relink to its own path is an identity); `analysis_job {wait}`: X landed
  after the relink returned.
- A12 with `clip`: a trimmed, a ×2 and a reversed placement each answer every
  cut in its window once, at `clip_time` and `timeline` as the clip's in,
  speed, start and the media's duration put it.
- A13 (its own launch, hold 50 s) `get_media_analysis {media, kind: masks}` on
  `hlg_4k.mov` (the third arm) refuses with "call again to continue"; within
  15 s the masks marker covers one range [0, k], k < 599, and `masks.pack`
  exists: a call past its wait keeps what the job analysed (#435).
- A14 (a document made and closed on a plain launch, then opened on a launch
  of its own with the job held 3 s and every save held 25 s after its package
  is written and before it is swapped in, `-RCDevSaveHold`, spec §11 #429)
  `analysis_job` X; `save_project` X; `analysis_job {wait}`: X landed, its
  `save_waits` rose by one (its publish found the save in flight and waited),
  the marker and payload are in the package after the save, and
  `get_media_analysis` answers `cached: true` with the window's cut (60). A run
  whose publish did not meet the save fails by that name.

`--mutant NAME`: the named decision broken in a copy — `app/Sources` copied
for the probe's rows, the tree copied and built (`tree_copy.py`,
`adjustment_proof.py`'s pattern) for the app's — and only its row run; the
mutant is CAUGHT (exit 0) when that row fails, SURVIVED (exit 1) otherwise.
"""

import argparse
import atexit
import json
import math
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
import analysis_fixtures as fixtures  # noqa: E402
import bounded  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/analysis-proof"
HOME = WORK / "home"
CALL_BOUND = 300
BUILD_BOUND = 1500
FRAME = 20_000  # ticks a frame at 30 fps
P_ROWS = ["P1", "P2", "P3", "P4", "P5", "P6", "P7", "P8", "P9", "P10", "P11"]
PLAIN = ["A1", "A2", "A3", "A4", "A8", "A9", "A10", "A12"]
HELD = ["A5", "A6", "A7", "A11"]
TIMED_OUT = ["A13"]
SAVE_HELD = ["A14"]
APP_ROWS = PLAIN + HELD + TIMED_OUT + SAVE_HELD
ROWS = P_ROWS + APP_ROWS + ["Z1"]
HOLD = ["-RCDevAnalysisHold", "3"]
LONG_HOLD = ["-RCDevAnalysisHold", "50"]   # A13: the job runs about 10 s inside the call's 60 s
# A14: every save held this long, under the ledger's 30 s publish wait. The job is
# held 3 s and then reads A14_FRAMES frames (about half a second), so its publish
# comes well inside the hold; a run where it does not fails by name. The document
# is made on a launch without the hold, so A14's is the one save held.
SAVE_HOLD_SECONDS = 25
A14_FRAMES = 100
SAVE_HOLD = HOLD + ["-RCDevSaveHold", str(SAVE_HOLD_SECONDS)]
CANNED = ["-RCDevAnalysisCanned", "YES"]

# The analysis store's one write, inside the ledger and outside it.
WRITE_INSIDE = ("let published = MediaImporter.CacheLedger.shared.publish(\n"
                "            in: cacheDir, for: nil, waited: &waited) { body() }")
WRITE_OUTSIDE = "body(); let published = true"

MUTANTS = {
    "stamp-no-os-build": (["P1"], [(
        "app/Sources/AnalysisStamp.swift", "            && osBuild == other.osBuild\n", "")]),
    "stamp-no-reader": (["A10"], [(
        "app/Sources/AnalysisStamp.swift",
        "            && reader == other.reader && conversion == other.conversion\n", "")]),
    "write-outside-publish": (["P9"], [(
        "app/Sources/AnalysisStore.swift", WRITE_INSIDE, WRITE_OUTSIDE)]),
    "write-outside-publish-app": (["A14"], [(
        "app/Sources/AnalysisStore.swift", WRITE_INSIDE, WRITE_OUTSIDE)]),
    "save-not-announced": (["A14"], [(
        "app/Sources/ProjectDocument+CacheSaves.swift",
        "let save = MediaImporter.CacheLedger.shared.saveBegan(cacheDir: directory)",
        "let save = 0")]),
    "partial-taken-covered": (["A3"], [(
        "app/Sources/AnalysisStore.swift",
        "return missing.isEmpty ? .hit(marker) : .miss(missing)",
        "return marker.ranges.contains(where: { $0.overlaps(need) }) ? .hit(marker) "
        ": .miss(missing)")]),
    "margin-unread": (["A9"], [(
        "app/Sources/ProjectDocument+Analysis.swift",
        ".map { [grid.need($0, margin: kind.margin)] } ?? []",
        ".map { [grid.need($0, margin: 0)] } ?? []")]),
    "width-wrong": (["A7"], [(
        "app/Sources/AnalysisLane.swift", "static let pictureWidth = 1",
        "static let pictureWidth = 2")]),
    "flash-rule-removed": (["A1"], [(
        "app/Sources/AnalysisShots.swift",
        "if let next, records[next].d2 < threshold { continue }", "_ = next")]),
    "canned-without-flag": (["A8"], [(
        "app/Sources/AnalysisStamp.swift",
        "return UserDefaults.standard.bool(forKey: AnalysisLane.devCannedKey)", "return true")]),
    "hold-no-cancel-poll": (["A6"], [(
        "app/Sources/AnalysisLane.swift", "while Date() < until, !cancelled() {",
        "while Date() < until {")]),
    "cancel-unpublished-shots": (["P10"], [(
        "app/Sources/AnalysisShots.swift",
        "                if lastIndex >= coveredFrom {\n                    AnalysisStore.publishCancelled",
        "                if false, lastIndex >= coveredFrom {\n                    AnalysisStore.publishCancelled")]),
    "cancel-replaces-stamp": (["P11"], [(
        "app/Sources/AnalysisStore.swift",
        "        if replaces, Thread.current.threadDictionary[mergeOnlyKey] != nil { return false }\n",
        "")]),
    "cancel-unpublished-masks": (["A13"], [(
        "app/Sources/AnalysisMasks.swift",
        "                    done.upperBound >= job.from\n",
        "                    done.upperBound >= job.from, false\n")]),
    "preroll-by-index": (["P7"], [(
        "app/Sources/AnalysisFrames.swift", "guard kept.count < 2 else { break }", "break")]),
}

results = {}
selected = set(ROWS)


def check(name, ok, detail=""):
    if name not in selected:
        return
    results.setdefault(name, []).append((bool(ok), detail))
    print(f"  {'ok  ' if ok else 'FAIL'} {name} {detail}", flush=True)


def remove_work():
    if WORK.exists():
        tree_copy.remove_tree(str(WORK))


# ---- the probe rows ------------------------------------------------------------

def probe_rows(sources):
    rows = [r for r in P_ROWS if r in selected]
    if not rows:
        return
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "analysis_probe.swift", entry)
    swift = sorted(str(p) for p in Path(sources).glob("*.swift") if p.name != "main.swift")
    binary = out / "analysis-probe"
    try:
        swift_build.build(sources=swift + [str(entry)], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"])
    except swift_build.SwiftBuildFailed as error:
        for row in rows:
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    request = out / "request.json"
    request.write_text(json.dumps({"shots": str(fixtures.shots()),
                                   "vfr": str(fixtures.vfr_twin()),
                                   "work": str(out / "run")}))
    try:
        run = subprocess.run([str(binary), str(request)], capture_output=True, text=True,
                             timeout=900)
        answer = json.loads(run.stdout)["rows"]
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        for row in rows:
            check(row, False, f"the probe gave no answer: {error}")
        return
    by_id = {r["id"]: r for r in answer}
    for row in rows:
        got = by_id.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


# ---- the app rows --------------------------------------------------------------

class Doc:
    def __init__(self, client, name):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=1280, height=720, fps=[30, 1])
        self.call("save_project")

    @classmethod
    def opened(cls, client, name):
        """The package an earlier launch's `Doc(client, name)` saved, opened."""
        doc = cls.__new__(cls)
        doc.client = client
        doc.path = WORK / f"{name}.framejob"
        client.call("open_project", path=str(doc.path))
        return doc

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def state(self):
        return self.call("get_project")["project"]

    def media(self, tag):
        """A copy of the shots fixture of its own (its own file, so its own
        cache), imported."""
        copy = WORK / "media" / f"shots_{tag}.mov"
        copy.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixtures.shots(), copy)
        return self.call("import_media", path=str(copy))["media"], copy

    def analysis(self, **arguments):
        return self.call("get_media_analysis", kind="shots", **arguments)

    def marker(self, media):
        path = self.path / "cache/analysis/shots" / f"{media}.json"
        return path.read_bytes() if path.exists() else None

    def payload(self, media):
        path = self.path / "cache/analysis/shots" / str(media) / "frames.bin"
        return path.read_bytes() if path.exists() else None

    def coverage(self, media):
        raw = self.marker(media)
        return json.loads(raw)["coverage"] if raw else None

    def close(self):
        try:
            self.client.call("close_project", project=str(self.path), discard=True)
        except mcp.ToolError:
            pass


def frames(answer):
    return [c["frame"] for c in answer.get("cuts", [])]


def attempt(body, name):
    try:
        return body()
    except Exception as error:  # noqa: BLE001 — a row's failure, never the run's
        check(name, False, f"{type(error).__name__}: {error}")
        return None


def plain_rows(client):
    doc = Doc(client, "plain")
    end = fixtures.SHOTS_FRAMES * FRAME

    def a1_a2():
        media, _ = doc.media("a")
        first = doc.analysis(media=media)
        got = frames(first)
        check("A1", got == fixtures.SHOTS_CUTS and not first["cached"] and "run" in first
              and first["size"] == [1280, 720],
              f"cuts {got} (want {fixtures.SHOTS_CUTS}; the flash {fixtures.FLASH} and the "
              f"dissolve {fixtures.DISSOLVE} hold none), cached {first['cached']}, run "
              f"{first.get('run')}, size {first['size']}")
        marker, payload = doc.marker(media), doc.payload(media)
        second = doc.analysis(media=media)
        check("A2", second["cached"] and "run" not in second and frames(second) == got
              and doc.marker(media) == marker and doc.payload(media) == payload
              and marker is not None,
              f"cached {second['cached']}, run {second.get('run')}, marker and payload bytes "
              f"{'unchanged' if doc.marker(media) == marker and doc.payload(media) == payload else 'CHANGED'}")
    if selected & {"A1", "A2"}:
        attempt(a1_a2, "A1")

    def a3():
        media, _ = doc.media("b")
        doc.analysis(media=media, **{"from": 0, "to": 200 * FRAME})
        before = doc.coverage(media)
        held = doc.payload(media)
        inside = doc.analysis(media=media, **{"from": 50 * FRAME, "to": 150 * FRAME})
        past = doc.analysis(media=media, **{"from": 150 * FRAME, "to": 300 * FRAME})
        after = doc.coverage(media)
        now = doc.payload(media)
        kept = held is not None and now is not None and now[:213 * 16] == held[:213 * 16]
        check("A3", before == [[0, 212]] and inside["cached"] and not past["cached"]
              and frames(past) == [180, 240] and after == [[0, 312]] and kept,
              f"coverage {before} → {after} (want [[0, 212]] → [[0, 312]]); inside cached "
              f"{inside['cached']}; past cached {past['cached']}, cuts {frames(past)}; the "
              f"first job's bytes {'kept' if kept else 'CHANGED'}")
    if "A3" in selected:
        attempt(a3, "A3")

    def a4():
        media, copy = doc.media("c")
        first = doc.analysis(media=media)
        again = doc.analysis(media=media)
        stat = copy.stat()
        os.utime(copy, (stat.st_atime, stat.st_mtime + 10))
        moved = doc.analysis(media=media)
        was = first["stamp"]["source"]["modified"]
        is_ = moved["stamp"]["source"]["modified"]
        check("A4", again["cached"] and not moved["cached"] and is_ == was + 10,
              f"cached again {again['cached']}; after the touch cached {moved['cached']}, "
              f"modified {was} → {is_}")
    if "A4" in selected:
        attempt(a4, "A4")

    def a8_without():
        media, copy = doc.media("canned")
        state["canned"] = (doc, media, copy)
        write_canned(doc, media, copy)
        got = doc.analysis(media=media)
        replaced = json.loads(doc.marker(media) or b"{}")
        check("A8", not got["cached"] and frames(got) == fixtures.SHOTS_CUTS
              and replaced.get("canned") is None and replaced.get("stamp"),
              f"without the flag: cached {got['cached']}, cuts {frames(got)}, the marker "
              f"{'replaced by a stamped one' if replaced.get('stamp') else 'NOT replaced'}")
    if "A8" in selected:
        attempt(a8_without, "A8")

    def a9():
        split = 151 * FRAME
        d, _ = doc.media("d")
        whole = frames(doc.analysis(media=d))
        orders = {}
        for tag, halves in (("e", [(0, split), (split, end)]), ("f", [(split, end), (0, split)])):
            m, _ = doc.media(tag)
            parts = []
            for low, high in halves:
                parts += frames(doc.analysis(media=m, **{"from": low, "to": high}))
            after = doc.analysis(media=m)
            orders[tag] = (sorted(parts), frames(after), after["cached"], doc.payload(m))
        same = all(o[0] == whole and o[1] == whole and o[2] and o[3] == doc.payload(d)
                   for o in orders.values())
        check("A9", same and whole == fixtures.SHOTS_CUTS,
              f"whole {whole}; first-then-second halves {orders['e'][0]}, then whole "
              f"{orders['e'][1]} (cached {orders['e'][2]}); second-then-first "
              f"{orders['f'][0]}, {orders['f'][1]} (cached {orders['f'][2]}); payloads "
              f"{'equal' if all(o[3] == doc.payload(d) for o in orders.values()) else 'DIFFER'}")
    if "A9" in selected:
        attempt(a9, "A9")

    def a10():
        media, _ = doc.media("g")
        raw = doc.analysis(media=media)
        doc.call("set_media_color", media=media, color={"log": "slog3"})
        log = doc.analysis(media=media)
        doc.call("set_media_color", media=media, color=None)
        back = doc.analysis(media=media)
        check("A10", raw["stamp"]["reader"] == "raw" and not log["cached"]
              and log["stamp"]["reader"] == "converted" and log["stamp"].get("conversion")
              and (log["stamp"]["conversion"] or {}).get("log") == "slog3"
              and not back["cached"] and back["stamp"]["reader"] == "raw",
              f"raw {raw['stamp']['reader']}; with S-Log3 cached {log['cached']}, reader "
              f"{log['stamp']['reader']}, conversion {log['stamp'].get('conversion')}; back "
              f"cached {back['cached']}, reader {back['stamp']['reader']}")
    if "A10" in selected:
        attempt(a10, "A10")

    def a12():
        media, _ = doc.media("h")
        project = doc.state()
        track = project["tracks"][0]["id"]
        duration = next(m for m in project["media"] if m["id"] == media)["duration"]
        made = []
        for at, edit in ((0, "trim"), (20 * 600_000, "speed"), (40 * 600_000, "reverse")):
            clip = doc.call("add_clip", track=track, media=media, at=at)["new_clips"][0]
            if edit == "trim":
                doc.call("trim_start", clip=clip, to=at + 600_000)
            elif edit == "speed":
                doc.call("set_speed", clip=clip, rate=2)
            else:
                doc.call("set_reversed", clip=clip, reversed=True)
            made.append((edit, clip))
        clips = {c["id"]: c for c in doc.state()["clips"]}
        details, ok = [], True
        for edit, clip_id in made:
            clip = clips[clip_id]
            source = clip["source"]
            cin, speed, start = source.get("in", 0), clip.get("speed", 1), clip["start"]
            reversed_ = source.get("reversed", False)
            length = round(clip["duration"] * speed)
            low, high = ((duration - cin - length, duration - cin) if reversed_
                         else (cin, cin + length))
            want = []
            for k in fixtures.SHOTS_CUTS:
                s = k * FRAME
                if low <= s < high:
                    played = duration - s if reversed_ else s
                    t = round((played - cin) / speed)
                    want.append({"frame": k, "source": s, "clip_time": t, "timeline": start + t})
            got = doc.analysis(clip=clip_id)
            cuts = sorted(got["cuts"], key=lambda c: c["frame"])
            good = cuts == want and got.get("clip") == clip_id
            ok = ok and good
            details.append(f"{edit}: {[(c['frame'], c['clip_time'], c['timeline']) for c in cuts]}"
                           + ("" if good else f" (want {[(c['frame'], c['clip_time'], c['timeline']) for c in want]})"))
        check("A12", ok, "; ".join(details))
    if "A12" in selected:
        attempt(a12, "A12")
    doc.close()


def write_canned(doc, media, copy):
    """A canned marker for `media`: its source identity and one fake cut at
    frame 7 over the whole file."""
    project = doc.state()
    duration = next(m for m in project["media"] if m["id"] == media)["duration"]
    count = max(1, math.ceil(duration * 30 / 600_000 - 1e-6))  # the media's whole grid
    stat = copy.stat()
    import struct
    records = bytearray()
    for k in range(count):
        d1 = 1.5 if k == 7 else 0.0
        d2 = 1.5 if k == 8 else 0.0
        records += struct.pack("<qff", k * FRAME if k < fixtures.SHOTS_FRAMES else -1, d1, d2)
    folder = doc.path / "cache/analysis/shots" / str(media)
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "frames.bin").write_bytes(bytes(records))
    marker = {"canned": True, "coverage": [[0, count - 1]], "files": ["frames.bin"],
              "source": {"duration": duration, "modified": round(stat.st_mtime),
                         "size": stat.st_size}}
    (doc.path / "cache/analysis/shots" / f"{media}.json").write_text(
        json.dumps(marker, sort_keys=True))


def canned_rows(client):
    doc = Doc(client, "canned")

    def body():
        media, copy = doc.media("canned2")
        write_canned(doc, media, copy)
        got = doc.analysis(media=media)
        check("A8", got["cached"] and got.get("canned") is True and frames(got) == [7],
              f"with the flag: cached {got['cached']}, canned {got.get('canned')}, cuts "
              f"{frames(got)} (want [7])")
    attempt(body, "A8")
    doc.close()


def job(answer, path, media):
    for row in answer["jobs"]:
        if row["project"] and mcp_path(row["project"]) == mcp_path(path) and row["media"] == media:
            return row
    return None


def mcp_path(path):
    return os.path.realpath(str(path))


def held_rows(client):
    def dev(**arguments):
        return client.call_with("analysis_job", arguments)

    def a5():
        doc = Doc(client, "held-x")
        media, _ = doc.media("x")
        wanted = dev(project=str(doc.path), media=media, kind="shots")
        doc.call("save_project")
        mark = dev()["now"]
        waited = dev(wait=30)
        row = job(waited, doc.path, media) or {}
        saved = doc.call("save_project")
        check("A5", not wanted["wanted"]["hit"] and row.get("outcome") == "landed"
              and row.get("ended_at", 0) > mark and saved.get("ok", True) is not False
              and doc.marker(media) is not None and doc.payload(media) is not None,
              f"landed {row.get('outcome')} at {row.get('ended_at')} after the save's return "
              f"{mark}; the next save {'ok' if saved.get('ok', True) is not False else saved}; "
              f"marker and payload {'there' if doc.marker(media) and doc.payload(media) else 'MISSING'}")
        doc.close()
    if "A5" in selected:
        attempt(a5, "A5")

    def a6():
        doc = Doc(client, "held-y")
        media, _ = doc.media("y")
        t0 = dev()["now"]
        dev(project=str(doc.path), media=media, kind="shots")
        doc.close()
        waited = dev(wait=5)
        row = job(waited, doc.path, media) or {}
        gone = doc.marker(media) is None and doc.payload(media) is None
        ended = row.get("ended_at")
        check("A6", row.get("outcome") == "cancelled" and ended is not None
              and ended - t0 < 1.5 and gone,
              f"outcome {row.get('outcome')}, ended {None if ended is None else round(ended - t0, 3)} s "
              f"after t0 (want < 1.5); marker and payload {'absent' if gone else 'WRITTEN'}")
    if "A6" in selected:
        attempt(a6, "A6")

    def a7():
        p, q = Doc(client, "held-p"), Doc(client, "held-q")
        mp, _ = p.media("p")
        mq, _ = q.media("q")
        dev(project=str(p.path), media=mp, kind="shots")
        dev(project=str(q.path), media=mq, kind="shots")
        waited = dev(wait=30)
        a, b = job(waited, p.path, mp) or {}, job(waited, q.path, mq) or {}
        spans = sorted([(a.get("started_at"), a.get("ended_at")), (b.get("started_at"),
                                                                     b.get("ended_at"))],
                       key=lambda s: s[0] or 0)
        apart = None not in (spans[0][1], spans[1][0]) and spans[1][0] >= spans[0][1]
        check("A7", a.get("outcome") == "landed" and b.get("outcome") == "landed" and apart,
              f"runs {spans} ({'one at a time' if apart else 'OVERLAP'}) at width 1")
        p.close()
        q.close()
    if "A7" in selected:
        attempt(a7, "A7")

    def a11():
        doc = Doc(client, "held-r")
        media, copy = doc.media("r")
        dev(project=str(doc.path), media=media, kind="shots")
        # The same bytes and modification second at another path: relink to the
        # file's own path is an identity, so nothing would run.
        twin = copy.with_name(copy.stem + "-relinked.mov")
        shutil.copy2(copy, twin)
        relinked = doc.call("relink_media", media=media, path=str(twin))
        mark = dev()["now"]
        waited = dev(wait=30)
        row = job(waited, doc.path, media) or {}
        check("A11", row.get("outcome") == "landed" and row.get("ended_at", 0) > mark,
              f"relink {relinked.get('ok', relinked)}; the job {row.get('outcome')} at "
              f"{row.get('ended_at')}, the relink returned by {mark}")
        doc.close()
    if "A11" in selected:
        attempt(a11, "A11")


state = {}


def launch(binary, arguments, tag):
    log = WORK / f"instance-{tag}.log"
    launched = mcp.launch(str(binary), arguments,
                          env=bounded.child_env({"CFFIXED_USER_HOME": str(HOME)}),
                          log_path=str(log), timeout=CALL_BOUND)
    return launched, log


def parity(log, tag):
    try:
        lines = [line.strip() for line in open(log, errors="replace") if "Frame Job: " in line]
    except OSError:
        lines = [f"{log} could not be read"]
    check("Z1", not lines, f"{tag}: grep 'Frame Job: ' printed {lines[:3] or 'nothing'}")


def timed_out_rows(client):
    """A13: a masks call past its wait keeps what its job analysed (#435)."""
    doc = Doc(client, "timed-out")

    def a13():
        hlg = WORK / "media" / "hlg_4k.mov"
        hlg.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(fixtures.hlg_4k(), hlg)
        media = doc.call("import_media", path=str(hlg))["media"]
        marker = doc.path / "cache/analysis/masks" / f"{media}.json"
        pack = doc.path / "cache/analysis/masks" / str(media) / "masks.pack"
        began = time.monotonic()
        try:
            answer = doc.call("get_media_analysis", media=media, kind="masks")
            check("A13", False, f"the call landed inside its wait after "
                  f"{time.monotonic() - began:.1f} s ({answer.get('cached')}, frames "
                  f"{len(answer.get('frames') or [])}), so no job was cancelled past it")
            return
        except mcp.ToolError as error:
            refused = str(error)
        waited = time.monotonic() - began
        coverage = None
        for _ in range(150):
            if marker.exists() and pack.exists():
                coverage = json.loads(marker.read_text()).get("coverage")
                break
            time.sleep(0.1)
        one = (coverage is not None and len(coverage) == 1 and coverage[0][0] == 0
               and coverage[0][1] < 599)
        check("A13", "call again to continue" in refused and one,
              f"the call refused after {waited:.1f} s: {refused[:160]!r}; within 15 s the marker "
              f"covers {coverage} (want one range [0, k], k < 599), masks.pack "
              f"{'exists' if pack.exists() else 'MISSING'}")
    attempt(a13, "A13")
    doc.close()


def save_held_prepare(client):
    """A14's document, made where no save is held: its media imported, saved
    clean (so no autosave is pending in the next launch) and closed."""
    def body():
        doc = Doc(client, "save-held")
        state["save-held"] = doc.media("s")[0]
        doc.call("save_project")
        doc.close()
    attempt(body, "A14")


def save_held_rows(client):
    """A14: a publish that meets a held save waits it out and is kept (#429)."""
    def dev(**arguments):
        return client.call_with("analysis_job", arguments)

    def a14():
        if "save-held" not in state:
            return  # the prepare launch already failed the row
        doc = Doc.opened(client, "save-held")
        media = state["save-held"]
        before = dev()["now"]
        window = {"from": 0, "to": A14_FRAMES * FRAME}
        cuts = [k for k in fixtures.SHOTS_CUTS if k < A14_FRAMES]
        wanted = dev(project=str(doc.path), media=media, kind="shots", **window)
        waits = (job(wanted, doc.path, media) or {}).get("save_waits")
        saved = doc.call("save_project")
        returned = dev()["now"]
        row = job(dev(wait=30), doc.path, media) or {}
        there = doc.marker(media) is not None and doc.payload(media) is not None
        met = waits is not None and row.get("save_waits") == waits + 1
        landed = not wanted["wanted"]["hit"] and row.get("outcome") == "landed"
        after = doc.analysis(media=media, **window) if landed else {}
        cached = after.get("cached") is True and frames(after) == cuts
        started, ended = row.get("started_at"), row.get("ended_at")
        spans = (f"the save call {before:.3f} → {returned:.3f}, the job "
                 f"{'-' if started is None else format(started, '.3f')} → "
                 f"{'-' if ended is None else format(ended, '.3f')}")
        check("A14", landed and met and there and cached
              and saved.get("ok", True) is not False,
              f"outcome {row.get('outcome')}; save_waits {waits} → {row.get('save_waits')} "
              f"({'the publish met the held save and waited' if met else 'the publish did NOT wait for a save'}); "
              f"marker and payload after the save {'there' if there else 'MISSING'}; then "
              f"cached {after.get('cached')}, cuts {frames(after)} (want {cuts}); {spans}; "
              f"every save held {SAVE_HOLD_SECONDS} s")
        doc.close()
    attempt(a14, "A14")


def app_rows(binary):
    plans = [("plain", [], plain_rows, set(PLAIN)),
             ("canned", CANNED, canned_rows, {"A8"}),
             ("held", HOLD, held_rows, set(HELD)),
             ("timed-out", LONG_HOLD, timed_out_rows, set(TIMED_OUT)),
             ("save-held-prepare", [], save_held_prepare, set(SAVE_HELD)),
             ("save-held", SAVE_HOLD, save_held_rows, set(SAVE_HELD))]
    for tag, arguments, body, rows in plans:
        if not selected & rows:
            continue
        launched, log = launch(binary, arguments, tag)
        try:
            if launched.client is None:
                for row in selected & rows:
                    check(row, False, f"the app did not listen ({tag})")
                continue
            print(f"  {tag}: instance PID {launched.child.pid}", flush=True)
            body(launched.client)
        finally:
            launched.stop()
        parity(log, tag)


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
    made, reason = tree_copy.make_copy(str(WORK / "mutant"))
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
        if selected & set(APP_ROWS):
            selected.add("Z1")
    remove_work()
    if not args.mutant:
        atexit.register(lambda: None)
    HOME.mkdir(parents=True)
    fixtures.shots()
    fixtures.vfr_twin()
    sources = ROOT / "app/Sources"
    binary = Path(args.app) if args.app else None
    if args.mutant:
        named = MUTANTS[args.mutant][0]
        print(f"CJ2a — the {args.mutant} MUTANT ({', '.join(named)} must FAIL)", flush=True)
        if set(named) <= set(P_ROWS):
            sources, why = mutant_sources(args.mutant)
        else:
            binary, why = mutant_app(args.mutant)
        if why:
            print(f"mutant {args.mutant}: the control could not be performed — {why}")
            return 2
    else:
        print(f"CJ2a — the analysis lane ({proof_app.config()} build)", flush=True)
    probe_rows(sources)
    if selected & set(APP_ROWS):
        if binary is None:
            binary = proof_app.binary()
        if binary.suffix == ".app":
            binary = proof_app.executable(binary)
        app_rows(binary)
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
