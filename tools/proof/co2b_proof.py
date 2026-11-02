#!/usr/bin/env python3
"""Road map "creator-jobs" CO2b — masks made on demand, and files that wait (spec §11 CO-22).

    python3 tools/proof/co2b_proof.py [--only P1,W4,…] [--mutant NAME] [--app PATH]

**Probe rows** (`co2b_probe.swift`, built from `app/Sources` with `FRAMEJOB_DEV_TOOLS` through
`swift_build.py`; no app; a failed build is a scored FAIL of both):
- P1 the windows and the need rule: a frame-aligned forward window, a ×0.5 one, a reversed one,
  a `freeze_frame` hold and a direct zero-length window, one at the media's end — each against
  the values worked by hand, and every query CO-24's lookup makes inside the need.
- P2 the keep rule: a running request meeting the need kept and excluded from the new one; an
  ended one not kept; a running one no longer meeting it dropped; a queued one wholly inside the
  need kept; a queued one only overlapping it (part outside) dropped, the new request covering
  the needed part.

**App rows** over MCP (`proof_app.binary()`, `RC_PROOF_APP`, or `--app`), on a scratch
`CFFIXED_USER_HOME`, the person rows on `co2a_proof.person_fixtures()`'s push-in
(`push_1080.mov`, 20 s), imported into each row's own package. Launch A
(`-RCDevAnalysisHold 3`: each job waits 3 s before its first frame):
- W1 `set_video {cutout: {}}` on a clip playing [1 s, 3 s) of the push-in → within
  `ANALYSIS_BOUND` the marker's coverage equals the need of the clip's window exactly (30…90).
- W2 `trim_start` widening it to [0.5 s, 3 s) → `mask_wants`' next document request holds only
  the new indices (15…29), and the pack's earlier mask blobs keep their offsets and bytes.
- W3b `render_frame` right after setting a cutout returns the cut picture: equal to a render
  after the job landed, differing from cutout off, and no uncut sentence.
- W4 a `prores_4444` export started while the marker does not yet cover the window: its frames
  decoded equal `render_frame`'s at three times, the alpha within 1/255 and the colour as seen
  (premultiplied) within `PRORES_COLOUR` levels, ProRes's own loss.
- W4b in a second project made as W4's (the push-in imported anew into its own package), the
  cutout set and, asserted immediately before the export starts, the marker NOT covering the
  window: an `apng` export's frames equal `render_frame`'s the same way.
- W5 with `cache/analysis/masks/` read-only, the export fails with `cutoutFailed` naming the
  clip, and no file exists.
- W6 a reversed cut-out clip's coverage is its mirrored window's need; its frame at 1 s draws
  the forward mask of the pack frame shown at `T − s − 1` (every pixel whose 3 × 3 mask-texel
  neighbourhood is all 0 equals the clip hidden, all ≥ 192 the uncut frame).
- W7 after W4's export, its `mask_wants` rows (role `export`) are `wanted: false`.
- W8 a 75 s 1080p `testsrc2` clip: after the first mid-job publish, `set_video {opacity: 0.9}`;
  the job ends `landed`, no document row `cancelled`, coverage equals the need.
- W9 a fresh 75 s 1080p `testsrc2` clip with its cutout set, a `prores_4444` export of the
  whole timeline started after the document job's first mid-job publish: the export's
  `mask_wants` rows include the document's running request, exactly one masks run from the set
  to the export's end analyses the clip's frames (any remainder holds no index of the
  document's request), and the export completes.
Launch B (`-RCDevAnalysisHold 3600`):
- W3 `render_frame` (a client bound of `W3_CALL_BOUND`, 90 s) returns in 30–45 s, its PNG
  byte-identical to cutout off and its text holding the clip's sentence.
- Z1 each launch's `grep "Frame Job: "` prints nothing.

`--mutant NAME`: CO-22's decision broken in a tree copy (`tree_copy.py`), the copy built as the
proof's configuration (and the probe from the copy's `app/Sources`), and only its rows run;
CAUGHT (exit 0) when one of them fails. The tree's mutated file's SHA-256 is read before and
after and must be unchanged.

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
import cutout_spike  # noqa: E402
import mcp  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402

WORK = ROOT / "tools/proof/work/co2b"
HOME = WORK / "home"
FIXTURES = cutout_spike.MEDIA / "co2b"
TESTSRC = FIXTURES / "testsrc_75.mov"
MOVIE = ROOT / "tools/proof/media/A.mov"
FFMPEG = cutout_spike.FFMPEG
SEC = 600_000
FRAME = 20_000
W, H = 640, 360
CALL_BOUND = 600
# Fixed before the run: how long a 2 s window's job may take to land (3 s hold, ~1.6 s of
# analysis at CO-11's 1.23× real time, three lanes' load), and a 75 s window's.
ANALYSIS_BOUND = 120
LONG_BOUND = 480
W3_CALL_BOUND = 90
W3_LOW, W3_HIGH = 30, 45
EXPORT_BOUND = 900
# W9: the rest of a 75 s 1080p analysis, then 75 s of ProRes 4444 (a Debug run under three lanes'
# load took longer than 900 s).
LONG_EXPORT_BOUND = 2400
BUILD_BOUND = 1500
REVERSE_BOUND = 300
# W4: ProRes 4444's colour is lossy (the first Debug run's worst premultiplied channel was 1.98
# levels, its alpha 1); the alpha, which the cutout writes, is held to 1/255.
PRORES_COLOUR = 3
SATURATED = co2a_proof.SATURATED
HOLD_A = ["-RCDevAnalysisHold", "3"]
HOLD_B = ["-RCDevAnalysisHold", "3600"]
PROBE_ROWS = ["P1", "P2"]
A_ROWS = ["W1", "W2", "W3b", "W4", "W7", "W4b", "W5", "W6", "W8", "W9"]
B_ROWS = ["W3"]
APP_ROWS = A_ROWS + B_ROWS + ["Z1"]
ROWS = PROBE_ROWS + APP_ROWS
TIMES = [SEC // 3, SEC, 5 * SEC // 3]
APNG_FRAMES = [5, 25, 45]
UNCUT = "is drawn uncut: its person masks were not ready within 30 s."

WANTS = "app/Sources/CutoutWants.swift"
MASKS = "app/Sources/Exporter+Masks.swift"
RAMP = "app/Sources/Exporter+RampAudio.swift"
WAIT_LINE = ("        try waitForMasks(plan: plan, urls: urls, settings: settings, key: key, "
             "cancelled: cancelled)\n")
GUARD_LINE = "        guard !settings.isImageSequence else { return try build() }\n"
MUTANTS = {
    "M1-no-export-wait": (["W4"], [(RAMP, WAIT_LINE, "")]),
    "M2-wait-after-guard": (["W4b"], [(RAMP, WAIT_LINE + GUARD_LINE, GUARD_LINE + WAIT_LINE)]),
    "M3-open-only": (["W2"], [
        ("app/Sources/ProjectDocument+RampAudio.swift",
         "            self?.rampAudioDidSettle()\n        }\n        ensureMasks()\n",
         "            self?.rampAudioDidSettle()\n        }\n"),
        ("app/Sources/ProjectDocument.swift",
         "        ensureReversedMedia()\n        ensureRampAudio()\n    }\n\n    override func close()",
         "        ensureReversedMedia()\n        ensureRampAudio()\n        ensureMasks()\n    }\n\n"
         "    override func close()")]),
    "M4-unbounded-frame": (["W3"], [(
        MASKS, "        let deadline = Date().addingTimeInterval(limit)\n",
        "        let deadline = Date.distantFuture\n")]),
    "M5-no-release": (["W7"], [(
        "app/Sources/Exporter.swift", "            Exporter.releaseMasks(key: key)\n", "")]),
    "M6-kept-empty": (["P2", "W8"], [(
        WANTS, "    ) -> [AnalysisRequest] {\n        previous.filter { request in\n",
        "    ) -> [AnalysisRequest] {\n        if !previous.isEmpty { return [] }\n"
        "        return previous.filter { request in\n")]),
    "M7-export-previous-empty": (["W9"], [(
        MASKS, "            let previous = AnalysisLane.shared.openRequests(kind: .masks, "
        "cacheDir: cacheDir)\n",
        "            let previous: [AnalysisRequest] = []\n")]),
    "M8-queued-as-running": (["P2"], [(
        WANTS, "            case .queued:\n                return request.ranges.allSatisfy {\n",
        "            case .queued:\n"
        "                return request.ranges.contains { range in ranges.contains "
        "{ $0.overlaps(range) } }\n"
        "                    || request.ranges.allSatisfy {\n")]),
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

def grid_of(media):
    num, den = media["fps"]
    rate = num / (600_000 * den)
    count = max(1, -int(-(media["duration"] * rate - 1e-6) // 1))
    return rate, count - 1


def need_of(lower, upper, media):
    """CO-22 (a)'s need of a forward window `[lower, upper)`."""
    rate, last = grid_of(media)

    def index(ticks):
        value = ticks * rate
        return min(last, max(0, int(value + 0.5) if value >= 0 else -int(-value + 0.5)))
    low = min(last, max(0, int((lower * rate + 1e-9) // 1)))
    high = index(max(lower, upper - 1))
    return [min(low, high), high]


# ---- the probe rows ------------------------------------------------------------------------

def build_probe(root=ROOT):
    out = WORK / "probe"
    out.mkdir(parents=True, exist_ok=True)
    entry = out / "main.swift"
    shutil.copyfile(HERE / "co2b_probe.swift", entry)
    sources = sorted(str(p) for p in (Path(root) / "app/Sources").glob("*.swift")
                     if p.name != "main.swift")
    binary = out / "co2b-probe"
    swift_build.build(sources=sources + [str(entry)], output=binary,
                      defines=["FRAMEJOB_DEV_TOOLS"])
    return binary


def probe_rows(root=ROOT):
    global PROBE
    rows = [r for r in PROBE_ROWS if r in selected]
    try:
        PROBE = build_probe(root)
    except swift_build.SwiftBuildFailed as error:
        for row in rows:
            check(row, False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return
    if not rows:
        return
    movie = WORK / "media" / "A.mov"
    movie.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(MOVIE, movie)
    scratch = WORK / "p2-cache"
    request = WORK / "probe" / "request.json"
    request.write_text(json.dumps({"movie": str(movie), "scratch": str(scratch)}))
    try:
        run = subprocess.run([str(PROBE), str(request)], capture_output=True, text=True,
                             timeout=300)
        answer = {r["id"]: r for r in json.loads(run.stdout)["rows"]}
    except (subprocess.TimeoutExpired, ValueError, KeyError) as error:
        for row in rows:
            check(row, False, f"the probe gave no answer: {error}")
        return
    for row in rows:
        got = answer.get(row)
        check(row, got is not None and got["pass"], (got or {}).get("detail", "no row"))


def probe_mask(pack, slot, out):
    run = subprocess.run([str(PROBE), "mask", str(pack), str(slot), str(out)],
                         capture_output=True, text=True, timeout=120)
    answer = json.loads(run.stdout.strip().splitlines()[-1])
    if not answer.get("ok"):
        raise RuntimeError(f"the probe could not read slot {slot} of {pack}")
    return answer["width"], answer["height"]


# ---- fixtures ------------------------------------------------------------------------------

def testsrc():
    """A 75 s 1080p `testsrc2` movie at 30 fps (W8, W9), made once."""
    if not TESTSRC.exists():
        co2a_proof.ffmpeg(["-f", "lavfi", "-i", "testsrc2=size=1920x1080:rate=30:duration=75",
                           "-c:v", "libx264", "-preset", "veryfast", "-crf", "23", "-g", "60",
                           "-pix_fmt", "yuv420p", "-video_track_timescale", "600"], TESTSRC)
    return TESTSRC


# ---- the app rows --------------------------------------------------------------------------

class Doc:
    """A 640 × 360, 30 fps project of its own package."""

    def __init__(self, client, name, background=(0.2, 0.3, 0.4, 1)):
        self.client = client
        self.path = WORK / f"{name}.framejob"
        if self.path.exists():
            shutil.rmtree(self.path)
        client.call("new_project", path=str(self.path))
        self.call("set_canvas", width=W, height=H, fps=[30, 1], background=list(background))
        self.call("save_project")

    def call(self, tool, **arguments):
        return self.client.call_with(tool, {"project": str(self.path), **arguments})

    def project(self):
        return self.call("get_project")["project"]

    def media(self, fixture):
        media = self.call("import_media", path=str(fixture))["media"]
        return next(m for m in self.project()["media"] if m["id"] == media)

    def clip(self, media, start_in=0, duration=2 * SEC, scale=1 / 3):
        """A clip of `media` at `start_in` playing `[start_in, start_in + duration)` of it (the
        whole media when `duration` is None)."""
        tracks = self.project()["tracks"]
        if not tracks:
            self.call("add_track")
            tracks = self.project()["tracks"]
        self.call("add_clip", track=tracks[0]["id"], media=media["id"], at=0)
        clip = self.project()["clips"][-1]["id"]
        if duration is not None:
            self.call("trim_end", clip=clip, to=start_in + duration)
        if start_in:
            self.call("trim_start", clip=clip, to=start_in)
        try:
            self.call("set_video", clips=[clip], patch={"scale": scale})
        except mcp.ToolError as error:
            # A clip placed already fitted to the canvas at that scale is an identity.
            if "made no change" not in str(error):
                raise
        return clip

    def clip_json(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def render(self, t, tag):
        out = WORK / f"{self.path.stem}-{tag}-{t}.png"
        if out.exists():
            out.unlink()
        text = self.client.call_with(
            "render_frame", {"project": str(self.path), "t": t, "path": str(out)})
        data = out.read_bytes() if out.exists() else None
        return data, (co2a_proof.decode_png(out) if data else None), text

    def marker(self, media):
        path = self.path / f"cache/analysis/masks/{media}.json"
        try:
            return json.loads(path.read_text())
        except (OSError, ValueError):
            return None

    def coverage(self, media):
        return (self.marker(media) or {}).get("coverage")

    def pack(self, media):
        return self.path / f"cache/analysis/masks/{media}/masks.pack"


def close(client, path):
    try:
        client.call("close_project", project=str(path), discard=True)
    except mcp.ToolError:
        pass


def covers(coverage, need):
    return any(lo <= need[0] and need[1] <= hi for lo, hi in coverage or [])


def window_of(clip, media):
    """The clip's forward window at ×1: `[in, in + duration)`, mirrored when reversed."""
    lower = clip["source"]["in"]
    upper = lower + clip["duration"]
    if clip["source"].get("reversed"):
        return media["duration"] - upper, media["duration"] - lower
    return lower, upper


def mask_wants(client):
    return client.call("analysis_job").get("mask_wants", [])


def new_rows(client, seen, role, media, bound=30):
    """`mask_wants` rows of `role` and `media` under an owner not in `seen`, waiting up to
    `bound` s for the first."""
    deadline = time.monotonic() + bound
    while True:
        rows = [r for r in mask_wants(client) if r["role"] == role and r["media"] == media
                and r["owner"] not in seen]
        if rows or time.monotonic() >= deadline:
            return rows
        time.sleep(0.1)


def owners(client, role):
    return {r["owner"] for r in mask_wants(client) if r["role"] == role}


def owner_rows(client, owner):
    return [r for r in mask_wants(client) if r["owner"] == owner]


def wait_landed(client, owner, bound):
    """Until every row of `owner` has an outcome; the rows."""
    deadline = time.monotonic() + bound
    while True:
        rows = owner_rows(client, owner)
        if rows and all("outcome" in r for r in rows):
            return rows
        if time.monotonic() >= deadline:
            raise RuntimeError(f"owner {owner}'s jobs did not end within {bound} s: {rows}")
        time.sleep(0.25)


def cut_out(doc, clip, media):
    """Sets the cutout; the new document owner's first row."""
    seen = owners(doc.client, "document")
    doc.call("set_video", clips=[clip], patch={"cutout": {}})
    rows = new_rows(doc.client, seen, "document", media)
    if not rows:
        raise RuntimeError("no document want was logged after set_video {cutout: {}}")
    return rows[0]["owner"]


def worst(a, b, channels=(0, 1, 2, 3)):
    if a is None or b is None or len(a) != len(b):
        return None
    return max(max(abs(a[i + c] - b[i + c]) for c in channels) for i in range(0, len(a), 4))


def worst_premultiplied(a, b):
    """The largest difference of two straight-alpha RGBA frames as seen: each colour channel
    times its alpha (/255), and the alpha — a colour under alpha 0 is no picture."""
    if a is None or b is None or len(a) != len(b):
        return None
    out = 0.0
    for i in range(0, len(a), 4):
        aa, ba = a[i + 3], b[i + 3]
        out = max(out, abs(aa - ba), *(abs(a[i + c] * aa - b[i + c] * ba) / 255 for c in range(3)))
    return out


def w1_w2(client, push):
    doc = Doc(client, "w1")
    try:
        media = doc.media(push)
        clip = doc.clip(media, start_in=SEC, duration=2 * SEC)
        window = window_of(doc.clip_json(clip), media)
        need = need_of(*window, media)
        start = time.monotonic()
        owner = cut_out(doc, clip, media["id"])
        rows = wait_landed(client, owner, ANALYSIS_BOUND)
        took = time.monotonic() - start
        check("W1", doc.coverage(media["id"]) == [need] and need == [30, 90]
              and all(r["outcome"] == "landed" for r in rows),
              f"window {window}: coverage {doc.coverage(media['id'])}, the need {need}, landed "
              f"in {took:.1f} s (bound {ANALYSIS_BOUND} s); rows {[r['ranges'] for r in rows]}")
        if "W2" not in selected:
            return
        frames, masks, _, _ = co2a_proof.read_pack(doc.pack(media["id"]))
        before = blobs(doc.pack(media["id"]))
        first = [r["ranges"] for r in owner_rows(client, owner)]
        doc.call("trim_start", clip=clip, to=SEC // 2)
        wider = window_of(doc.clip_json(clip), media)
        wide_need = need_of(*wider, media)
        deadline = time.monotonic() + 30
        later = []
        while time.monotonic() < deadline and not later:
            later = [r for r in owner_rows(client, owner) if r["ranges"] not in first]
            time.sleep(0.1)
        rows = wait_landed(client, owner, ANALYSIS_BOUND)
        after = blobs(doc.pack(media["id"]))
        kept = all(after.get(pts) == blob for pts, blob in before.items())
        check("W2", later and later[0]["ranges"] == [[wide_need[0], need[0] - 1]]
              and doc.coverage(media["id"]) == [wide_need],
              f"widened to {wider}: the next document request {later[0]['ranges'] if later else None}"
              f" (the new indices {[wide_need[0], need[0] - 1]}), coverage "
              f"{doc.coverage(media['id'])}")
        check("W2", kept and len(before) == len(masks) and len(after) > len(before),
              f"the pack's {len(before)} earlier mask blobs keep their offsets and bytes "
              f"({len(after)} now)")
    finally:
        close(client, doc.path)


def blobs(pack):
    """Each mask's pts → (offset, length, its bytes), read from the pack's mask table."""
    import struct
    data = Path(pack).read_bytes()
    foot = len(data) - 40
    _, _, _, nframes, nmasks, tables = struct.unpack_from("<IIIIIQ", data, foot + 4)
    base = tables + 16 * nframes
    out = {}
    for i in range(nmasks):
        pts, offset, length = struct.unpack_from("<qQI", data, base + 24 * i)
        out[pts] = (offset, length, data[offset:offset + length])
    return out


def w3b(client, push):
    doc = Doc(client, "w3b")
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        off, _, _ = doc.render(SEC, "off")
        owner = cut_out(doc, clip, media["id"])
        now, _, text = doc.render(SEC, "now")
        wait_landed(client, owner, ANALYSIS_BOUND)
        later, _, _ = doc.render(SEC, "later")
        check("W3b", now is not None and now == later and now != off and UNCUT not in text,
              f"render_frame right after the cutout: equal to the render after the job landed "
              f"{now == later}, differing from cutout off {now != off}, no uncut sentence "
              f"{UNCUT not in text}")
    finally:
        close(client, doc.path)


def export_frames(path, count=None):
    return list(co2a_proof.movie_frames(path))


def w4_w7(client, push):
    doc = Doc(client, "w4", background=(0, 0, 0, 0))
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        need = need_of(*window_of(doc.clip_json(clip), media), media)
        cut_out(doc, clip, media["id"])
        pending = not covers(doc.coverage(media["id"]), need)
        seen = owners(client, "export")
        out = WORK / "w4.mov"
        client.export_with({"project": str(doc.path), "preset": "prores_4444", "path": str(out)},
                           seconds=EXPORT_BOUND)
        frames = export_frames(out)
        scores = []
        for t in TIMES:
            _, picture, _ = doc.render(t, "w4")
            k = t // FRAME
            frame = frames[k] if k < len(frames) else None
            seen_as = worst_premultiplied(frame, picture)
            scores.append((k, None if seen_as is None else round(seen_as, 2),
                           worst(frame, picture, (3,))))
        cut = sum(1 for i in range(3, len(picture or b""), 4) if picture[i] == 0)
        check("W4", pending and cut > 0 and all(
            s is not None and s <= PRORES_COLOUR and a is not None and a <= 1
            for _, s, a in scores),
              f"the marker did not cover {need} when the export started ({pending}); "
              f"{len(frames)} frames; (frame, worst premultiplied RGBA ≤ {PRORES_COLOUR}, worst "
              f"alpha ≤ 1) against render_frame {scores}; {cut} pixels cut to alpha 0 in the last")
        if "W7" in selected:
            rows = [r for r in mask_wants(client) if r["role"] == "export"
                    and r["owner"] not in seen]
            check("W7", rows and not any(r["wanted"] for r in rows),
                  f"after the export: its {len(rows)} mask_wants rows "
                  f"{[(r['ranges'], r['wanted']) for r in rows]} all wanted false")
    finally:
        close(client, doc.path)


def w4b(client, push):
    doc = Doc(client, "w4b", background=(0, 0, 0, 0))
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        need = need_of(*window_of(doc.clip_json(clip), media), media)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        pending = not covers(doc.coverage(media["id"]), need)
        out = WORK / "w4b.png"
        client.export_with({"project": str(doc.path), "preset": "apng", "size": "document",
                            "path": str(out)}, seconds=EXPORT_BOUND)
        frames = export_frames(out)
        scores = []
        for k in APNG_FRAMES:
            t = k * SEC // 25
            _, picture, _ = doc.render(t, "w4b")
            scores.append((k, worst(frames[k] if k < len(frames) else None, picture)))
        check("W4b", pending and all(s is not None and s <= 1 for _, s in scores),
              f"the marker did not cover {need} immediately before the apng export ({pending}); "
              f"{len(frames)} frames; (frame, worst RGBA) against render_frame {scores}")
    finally:
        close(client, doc.path)


def w5(client, push):
    doc = Doc(client, "w5")
    folder = doc.path / "cache/analysis/masks"
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        folder.mkdir(parents=True, exist_ok=True)
        os.chmod(folder, 0o555)
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        out = WORK / "w5.mov"
        try:
            client.export_with({"project": str(doc.path), "preset": "prores_4444",
                                "path": str(out)}, seconds=EXPORT_BOUND)
            message = None
        except mcp.ToolError as error:
            message = str(error)
        want = f"Clip {clip}'s person masks could not be made: "
        check("W5", message is not None and want in message and not out.exists(),
              f"with cache/analysis/masks/ read-only the export failed: "
              f"{(message or 'no failure')[:240]}; the file exists {out.exists()}")
    finally:
        try:
            os.chmod(folder, 0o755)
        except OSError:
            pass
        close(client, doc.path)


def wait_reverse(doc, media):
    folder = doc.path / "cache" / "reversed"
    deadline = time.monotonic() + REVERSE_BOUND
    while time.monotonic() < deadline:
        files = sorted(folder.glob(f"{media}-*.mov")) if folder.is_dir() else []
        partial = folder.is_dir() and any(folder.glob(f"{media}-*.partial"))
        if files and not partial:
            try:
                doc.call("snapshot_ui", window="sheet", path=str(WORK / "w6-sheet.png"))
            except mcp.ToolError as error:
                if "no sheet attached" in str(error):
                    return
        time.sleep(0.25)
    raise RuntimeError(f"the reverse did not finish within {REVERSE_BOUND} s")


def w6(client, push):
    doc = Doc(client, "w6")
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        doc.call("set_reversed", clip=clip, reversed=True)
        wait_reverse(doc, media["id"])
        source = doc.clip_json(clip)
        window = window_of(source, media)
        need = need_of(*window, media)
        owner = cut_out(doc, clip, media["id"])
        wait_landed(client, owner, ANALYSIS_BOUND)
        check("W6", doc.coverage(media["id"]) == [need],
              f"reversed, in {source['source']['in']}: the forward window {window}, coverage "
              f"{doc.coverage(media['id'])}, its need {need}")
        t = SEC
        s = source["source"]["in"] + t
        query = media["duration"] - s - 1
        frames, _, mw, mh = co2a_proof.read_pack(doc.pack(media["id"]))
        shown = max(i for i, f in enumerate(frames) if f[0] <= query)
        raw = WORK / "w6-mask.bin"
        probe_mask(doc.pack(media["id"]), frames[shown][2], raw)
        mask = raw.read_bytes()
        _, cut, _ = doc.render(t, "cut")
        doc.call("set_video", clips=[clip], patch={"opacity": 0.0})
        _, hidden, _ = doc.render(t, "hidden")
        doc.call("set_video", clips=[clip], patch={"opacity": 1.0, "cutout": None})
        _, uncut, _ = doc.render(t, "uncut")
        zero = one = zero_bad = one_bad = 0
        for y in range(H):
            for x in range(W):
                at = (y * W + x) * 4
                if co2a_proof.neighbourhood(mask, mw, mh, x, y, lambda v: v == 0):
                    zero += 1
                    zero_bad += cut[at:at + 4] != hidden[at:at + 4]
                elif co2a_proof.neighbourhood(mask, mw, mh, x, y, lambda v: v >= SATURATED):
                    one += 1
                    one_bad += cut[at:at + 4] != uncut[at:at + 4]
        check("W6", zero > 1000 and one > 1000 and not zero_bad and not one_bad,
              f"t {t}: the forward mask of pack frame {shown} (pts {frames[shown][0]} ≤ T − s − 1 "
              f"= {query}): {zero} pixels in an all-0 neighbourhood equal the clip hidden "
              f"({zero_bad} differ), {one} in an all-≥{SATURATED} one equal the uncut frame "
              f"({one_bad} differ)")
    finally:
        close(client, doc.path)


def wait_mid_publish(doc, media, owner, bound):
    """Until the marker exists while the document's request has no outcome: the first mid-job
    publish. The request's row."""
    deadline = time.monotonic() + bound
    while time.monotonic() < deadline:
        rows = owner_rows(doc.client, owner)
        if rows and all("outcome" in r for r in rows):
            raise RuntimeError(f"the job ended before any mid-job publish: {rows}")
        if doc.marker(media) is not None:
            running = [r for r in rows if "started_at" in r and "outcome" not in r]
            if running:
                return running[0]
        time.sleep(0.2)
    raise RuntimeError(f"no mid-job publish within {bound} s")


def w8(client):
    doc = Doc(client, "w8")
    try:
        media = doc.media(testsrc())
        clip = doc.clip(media, duration=None)
        need = need_of(*window_of(doc.clip_json(clip), media), media)
        owner = cut_out(doc, clip, media["id"])
        running = wait_mid_publish(doc, media["id"], owner, LONG_BOUND)
        early = doc.coverage(media["id"])
        doc.call("set_video", clips=[clip], patch={"opacity": 0.9})
        rows = wait_landed(client, owner, LONG_BOUND)
        same = [r for r in rows if r["ranges"] == running["ranges"]]
        check("W8", same and all(r["outcome"] == "landed" for r in same)
              and not any(r["outcome"] == "cancelled" for r in rows)
              and doc.coverage(media["id"]) == [need],
              f"the first mid-job publish covered {early}; after opacity 0.9 the job "
              f"{running['ranges']} ended {[r['outcome'] for r in same]}, document rows "
              f"{[(r['ranges'], r['outcome']) for r in rows]}, coverage "
              f"{doc.coverage(media['id'])}, the need {need}")
    finally:
        close(client, doc.path)


def overlaps(a, b):
    return any(x[0] <= y[1] and y[0] <= x[1] for x in a for y in b)


def w9(client):
    doc = Doc(client, "w9", background=(0, 0, 0, 0))
    try:
        media = doc.media(testsrc())
        clip = doc.clip(media, duration=None)
        need = need_of(*window_of(doc.clip_json(clip), media), media)
        set_at = client.call("analysis_job")["now"]
        owner = cut_out(doc, clip, media["id"])
        running = wait_mid_publish(doc, media["id"], owner, LONG_BOUND)
        seen = owners(client, "export")
        out = WORK / "w9.mov"
        answer = client.export_with(
            {"project": str(doc.path), "preset": "prores_4444", "path": str(out)},
            seconds=LONG_EXPORT_BOUND)
        ended_at = client.call("analysis_job")["now"]
        rows = mask_wants(client)
        export = [r for r in rows if r["role"] == "export" and r["owner"] not in seen
                  and r["media"] == media["id"]]
        mine = [r for r in rows if r["media"] == media["id"]
                and (r["owner"] == owner or r in export)]
        runs = {}
        for r in mine:
            if "started_at" in r and set_at <= r["started_at"] <= ended_at:
                runs[json.dumps(r["ranges"])] = r["ranges"]
        analysing = [ranges for ranges in runs.values() if overlaps(ranges, [need])]
        others = [ranges for ranges in runs.values() if ranges != running["ranges"]]
        check("W9", any(r["ranges"] == running["ranges"] for r in export),
              f"the export's rows {[r['ranges'] for r in export]} include the document's "
              f"running request {running['ranges']}")
        check("W9", len(analysing) == 1 and not any(overlaps(o, running["ranges"])
                                                     for o in others),
              f"masks runs started from the set to the export's end: {list(runs.values())}; "
              f"analysing the clip's need {need}: {len(analysing)}")
        check("W9", out.exists() and answer.get("status") == "done",
              f"the export completed: {answer.get('status')}, {out.exists()}")
    finally:
        close(client, doc.path)


def w3(client, push):
    doc = Doc(client, "w3")
    try:
        media = doc.media(push)
        clip = doc.clip(media)
        off, _, _ = doc.render(SEC, "off")
        doc.call("set_video", clips=[clip], patch={"cutout": {}})
        client.timeout = W3_CALL_BOUND
        start = time.monotonic()
        try:
            cut, _, text = doc.render(SEC, "held")
        except Exception as error:  # noqa: BLE001 — a timeout is the row's failure
            check("W3", False, f"render_frame did not return within {W3_CALL_BOUND} s: {error}")
            return
        finally:
            client.timeout = CALL_BOUND
        took = time.monotonic() - start
        sentence = f"Clip {clip} {UNCUT}"
        check("W3", W3_LOW <= took <= W3_HIGH and cut == off and sentence in text,
              f"render_frame took {took:.1f} s ({W3_LOW}–{W3_HIGH}); byte-identical to cutout "
              f"off {cut == off}; the sentence {'present' if sentence in text else 'absent'}")
    finally:
        close(client, doc.path)


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
    push = None
    try:
        push, _ = co2a_proof.person_fixtures()
    except Exception as error:  # noqa: BLE001 — the fixture's failure is the rows'
        for name in selected & (set(A_ROWS) | set(B_ROWS)) - {"W8", "W9"}:
            check(name, False, f"the push-in fixture: {error}")
    if push is not None or selected & {"W8", "W9"}:
        a = [({"W1", "W2"}, lambda l: w1_w2(l.client, push)),
             ({"W3b"}, lambda l: w3b(l.client, push)),
             ({"W4", "W7"}, lambda l: w4_w7(l.client, push)),
             ({"W4b"}, lambda l: w4b(l.client, push)),
             ({"W5"}, lambda l: w5(l.client, push)),
             ({"W6"}, lambda l: w6(l.client, push)),
             ({"W8"}, lambda l: w8(l.client)),
             ({"W9"}, lambda l: w9(l.client))]
        if push is None:
            a = a[-2:]
        if selected & set(A_ROWS):
            launch_rows(binary, HOLD_A, WORK / "instance-a.log", a)
    if push is not None and "W3" in selected:
        launch_rows(binary, HOLD_B, WORK / "instance-b.log",
                    [({"W3"}, lambda l: w3(l.client, push))])


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def mutant_tree(name):
    made, reason = tree_copy.make_copy(str(WORK.parent / "co2b-mutant"))
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
        if selected & set(APP_ROWS):
            selected.add("Z1")
    elif args.only:
        selected = {r.strip() for r in args.only.split(",") if r.strip()}
        unknown = selected - set(ROWS)
        if unknown:
            print(f"unknown rows: {sorted(unknown)}")
            return 2
        if selected & set(APP_ROWS):
            selected.add("Z1")
    remove_work()
    HOME.mkdir(parents=True)
    root = ROOT
    binary = Path(args.app) if args.app else None
    before = {}
    if args.mutant:
        print(f"CO2b — the {args.mutant} MUTANT ({', '.join(MUTANTS[args.mutant][0])} must "
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
        print(f"CO2b — masks made on demand, and files that wait ({proof_app.config()} build)",
              flush=True)
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
