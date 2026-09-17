"""Road map 2, phase 3 — the screencast trio (schema v4), driven against the
built binary over MCP.

Every claim is a placement read back through `get_project`, a BYTE comparison
of two `render_frame` PNGs, a MEASUREMENT of one rendered PNG against a
prediction made from another, or the length of a real export. Nothing here
reads the source, and every check is one that would FAIL against a build where
the op did nothing.

The three parts, and what each is measured with:

* **3a Remove Silences** — `media/silence.mov`, a 10 s test card whose 48 kHz
  LPCM track is SAMPLE-EXACTLY quiet over 2.000–3.500 s and 6.000–7.000 s (the
  recipe is in README.md). `detect_silence` must find those two spans, the
  three settings must each move the answer the way they say, and
  `ripple_delete_ranges` must cut them: the export gets shorter by exactly the
  removed total, and the frames either side of each cut are byte-identical to
  the frames that were either side of the span.

* **3b Zoom to Region** — `media/A.mov` is ffmpeg's `testsrc`, whose middle
  band is flat colour bars with hard vertical edges. The base frame is
  rendered at scale 1 on a canvas the size of the source, so a canvas pixel IS
  a source pixel and those edges can be located to a fraction of a pixel; the
  zoomed frame is then measured against where the zoom's own arithmetic says
  they must land. The action's end patch is never read back for a placement
  claim — it has 32 core tests behind it, and what is unproved is that the
  recipe, the compositor and the maths agree.

* **3c Obscure** — the same test card under one pixelating region. Pixels
  outside the region must be byte-identical, and inside, at `amount` 1, the
  picture must be flat 64-SOURCE-pixel blocks anchored at the texture origin
  (`CompositorEffects.swift`'s header doc is where that number is written
  down; the blocks measured here are interior ones, never one the region's
  edge cuts).

Media: A.mov (the silent test card) and silence.mov; the recipes are in
README.md. `ffprobe` is needed at proof time, to measure the two exports'
lengths independently of what the app reports.
"""

import hashlib
import json
import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
import zlib

from mcp import MCP, ToolError

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4823
HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "media")
WORK = os.path.join(HERE, "work")

SEC = 600_000
# One peaks bucket, in ticks: `ReelTime.perSecond / MediaImporter.peakBucketsPerSecond`
# (`MediaPeaks.bucketTicks`). The detector's resolution, and the tolerance
# CONTRACT §6 allows a detected span.
BUCKET = 6_000

# What `media/silence.mov` actually holds, in seconds — the fixture's own
# truth, not the app's answer. Sample-exact by construction (README.md).
QUIET = [(2.000, 3.500), (6.000, 7.000)]

CANVAS = (640, 360)

failures = []
checks = 0


def check(ok, what):
    global checks
    checks += 1
    if ok:
        print(f"  ok   {what}")
    else:
        print(f"  FAIL {what}")
        failures.append(what)


def digest(path):
    with open(path, "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()[:16]


def ticks_of(seconds):
    """Seconds as ticks. Named for `ReelTime.ticks(seconds:)`, whose answer
    this has to agree with for any comparison here to mean anything."""
    return int(round(seconds * SEC))


def fmt(value):
    """A measured position, or the word for not having found one — so a check
    that failed still says what it saw instead of raising in its own message."""
    return "none" if value is None else format(value, ".2f")


def same_region(stored, wanted):
    """Whether a region read back is the one that was sent. Compared field by
    field rather than as text: `-64.0` goes over the wire as `-64` and a
    string comparison would fail on the JSON spelling of a whole number, which
    is not a claim anyone wants to make."""
    return set(stored) == set(wanted) and all(stored[k] == v for k, v in wanted.items())


def copy_package(source, destination):
    """A byte copy of a `.reelcut` package, skipping a file that vanishes
    under `cache/` — the instance under proof writes thumbnails while the copy
    runs. `phase2_proof.py` argues the whole thing; the short version is that
    everything under `cache/` is regenerable and no part of any claim made
    here, `cache/` itself must exist or `save_project` refuses the document as
    changed by another application, and a file that vanishes ANYWHERE else is
    still an error."""
    for root, _, files in os.walk(source):
        relative = os.path.relpath(root, source)
        target = destination if relative == "." else os.path.join(destination, relative)
        os.makedirs(target, exist_ok=True)
        for name in files:
            try:
                shutil.copy2(os.path.join(root, name), os.path.join(target, name))
            except FileNotFoundError:
                if relative.split(os.sep)[0] != "cache":
                    raise


def probe_duration(path):
    """An exported file's length in seconds, measured by ffprobe rather than
    believed from the tool's own answer."""
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path],
        check=True, capture_output=True, text=True)
    return float(out.stdout.strip())


# ---- PNG, in pure Python, and the things measured on one ------------------
#
# The same decoder `phase2_chrome.py` uses: chunks, zlib, the five filters. It
# is copied rather than imported because that file is a SCRIPT — importing it
# would run its main — and because a proof that measures its own evidence
# should carry the decoder it trusts.


def decode_png(path):
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise RuntimeError(f"{path} is not a PNG")
    pos, idat, header = 8, [], None
    while pos < len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", body)
        elif kind == b"IDAT":
            idat.append(body)
        elif kind == b"IEND":
            break
    width, height, depth, colour, _, _, interlace = header
    if depth != 8 or interlace != 0:
        raise RuntimeError(f"{path}: only 8-bit non-interlaced PNGs are decoded here")
    channels = {0: 1, 2: 3, 4: 2, 6: 4}[colour]
    raw = zlib.decompress(b"".join(idat))
    stride = width * channels
    bpp = channels
    rows, prev, pos = [], bytearray(stride), 0
    for _ in range(height):
        kind = raw[pos]
        cur = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for i in range(bpp, stride):
                cur[i] = (cur[i] + cur[i - bpp]) & 255
        elif kind == 2:
            for i in range(stride):
                cur[i] = (cur[i] + prev[i]) & 255
        elif kind == 3:
            for i in range(bpp):
                cur[i] = (cur[i] + (prev[i] >> 1)) & 255
            for i in range(bpp, stride):
                cur[i] = (cur[i] + ((cur[i - bpp] + prev[i]) >> 1)) & 255
        elif kind == 4:
            for i in range(bpp):
                cur[i] = (cur[i] + prev[i]) & 255
            for i in range(bpp, stride):
                a, b, c = cur[i - bpp], prev[i], prev[i - bpp]
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                if pa <= pb and pa <= pc:
                    pred = a
                elif pb <= pc:
                    pred = b
                else:
                    pred = c
                cur[i] = (cur[i] + pred) & 255
        elif kind != 0:
            raise RuntimeError(f"{path}: unknown filter {kind}")
        rows.append(bytes(cur))
        prev = cur
    return width, height, channels, rows


class Frame:
    """One rendered PNG, decoded.

    Positions are PIXEL INDICES: pixel `x` covers [x, x+1) and is sampled at
    its centre, x + 0.5. Predictions below are made in canvas COORDINATES and
    converted once, because half a pixel is the size of the error this is
    looking for."""

    def __init__(self, path):
        self.path = path
        self.width, self.height, self.channels, self.rows = decode_png(path)

    def pixel(self, x, y):
        return tuple(self.rows[y][x * self.channels:(x + 1) * self.channels])

    def row(self, y, channel=0):
        row = self.rows[y]
        return [row[x * self.channels + channel] for x in range(self.width)]

    def column(self, x, channel=0):
        return [row[x * self.channels + channel] for row in self.rows]

    def changed(self, other):
        """Every (x, y) whose bytes differ from `other`'s."""
        out = []
        ch = self.channels
        for y, (ra, rb) in enumerate(zip(self.rows, other.rows)):
            if ra == rb:
                continue
            for x in range(self.width):
                if ra[x * ch:(x + 1) * ch] != rb[x * ch:(x + 1) * ch]:
                    out.append((x, y))
        return out


def crossing(values, a, b):
    """Where a step between the plateaux at `a` and `b` crosses its own
    half-way level, in pixel indices, linearly interpolated.

    The estimator has to be the SAME on both frames for a prediction to mean
    anything, and this one is: it depends only on the two plateau values and
    the samples between them, so magnifying a monotone edge moves its answer
    by exactly the magnification. `a` and `b` are chosen well inside the two
    flat colours, never at the edge itself."""
    low, high = values[a], values[b]
    if abs(high - low) < 100:
        return None
    mid = (low + high) / 2.0
    for k in range(a, b):
        first, second = values[k], values[k + 1]
        if (first - mid) * (second - mid) <= 0 and first != second:
            return k + (mid - first) / (second - first)
    return None


def box(pixels):
    """(x0, y0, x1, y1) of a list of pixels, inclusive."""
    xs = [x for x, _ in pixels]
    ys = [y for _, y in pixels]
    return min(xs), min(ys), max(xs), max(ys)


class Session:
    """One project. The same shape as `phase2_proof.py`'s, plus the frame
    accessors this phase measures with."""

    def __init__(self, mcp, name, open_from=None):
        self.mcp = mcp
        # `<name>-<pid>.reelcut`, never a fixed name: a `project` path is
        # matched against every open document and no tool closes one, so two
        # earlier runs' SAVED packages would have the app answering for an old
        # one (measured in phase 2). Older runs' under this name go.
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        if open_from is None:
            mcp.call("new_project", path=self.path)
            self.mcp.call("set_canvas", project=self.path,
                          width=CANVAS[0], height=CANVAS[1])
            return
        copy_package(open_from, self.path)
        answer = self.mcp.call("open_project", path=self.path)
        check(
            not answer.get("already_open"),
            f"{name}: the copy was opened from disk, not matched to an open document",
        )

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def png(self, t):
        """The path of the PNG `render_frame` wrote — the tool answers with a
        sentence naming the file, so it is read out of that."""
        answer = self.op("render_frame", t=int(t))
        found = re.search(r"Written to (\S+\.png)\.", str(answer))
        assert found, f"render_frame said something else: {answer}"
        return found.group(1)

    def frame(self, t):
        """The rendered frame as a hash — the byte-comparison currency."""
        return digest(self.png(t))

    def image(self, t):
        """The rendered frame decoded, for the checks that MEASURE one."""
        return Frame(self.png(t))

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        return json.dumps(self.project(), sort_keys=True, separators=(",", ":"))

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def lanes(self):
        """Every track's clips as an ascending `(start, duration, source in)`
        sequence, with `next_id`.

        Ids are not part of any op's contract — a cut mints them — so this is
        the oracle two cutting paths are compared with. `source in` is in it
        because two edits can leave clips in the same PLACES holding different
        material, which is exactly how a left-to-right ripple differs from a
        right-to-left one. `next_id` is in it because a merge that did not
        happen shows up nowhere else: cutting at a boundary that already
        exists mints a fragment and then removes it again."""
        project = self.project()
        out = {}
        for clip in sorted(project["clips"], key=lambda c: (c["track"], c["start"])):
            out.setdefault(clip["track"], []).append(
                (clip["start"], clip["duration"], clip["source"]["in"]))
        return out, project["next_id"]

    def clip_of(self, name):
        """A one-clip project holding `name` from the media folder, from the
        start of track 1."""
        media = self.op("import_media", path=os.path.join(MEDIA, name))["media"]
        track = self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=0)["new_clips"][0]

    def fps(self):
        rate = self.project()["canvas"]["fps"]
        return rate[0] / rate[1]

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def undo(self):
        return self.op("undo")["undone"]

    def save(self):
        return self.op("save_project")

    def export(self, name):
        """An H.264 export into work/, and its length two ways: what the tool
        reports, and what ffprobe measures on the file.

        A fixed name, unlike the packages': an export path is not matched
        against the open documents, so there is nothing for a stale one to
        confuse, and overwriting it keeps work/ from growing a pair of movies
        per run."""
        target = os.path.join(WORK, f"{name}.mp4")
        if os.path.exists(target):
            os.remove(target)
        result = self.op("export", preset="h264", path=target)
        return result["duration"], probe_duration(result["path"])


# ---- 3a: Remove Silences --------------------------------------------------


def detect(session, **settings):
    """`detect_silence`, waiting out the peaks cache.

    `ProjectDocument.generateCaches` writes `cache/peaks/<media>.bin` in a
    fire-and-forget task at import, and the detector reports a media whose
    waveform has not landed as `pending_peaks` and proposes nothing inside it
    — deliberately, since deleting a clip because its cache was late is the
    one failure this feature must not have. So a run against a just-imported
    file has to wait, and a proof that did not would be measuring silence that
    is only the cache's."""
    for _ in range(60):
        answer = session.op("detect_silence", **settings)
        if "pending_peaks" not in answer:
            return answer
        time.sleep(0.5)
    raise RuntimeError("the peaks cache never landed for media/silence.mov")


def silence_part(mcp):
    print("\n3a — detect_silence")
    s = Session(mcp, "silence")
    clip = s.clip_of("silence.mov")
    frame = int(round(SEC / s.fps()))
    check(frame == 20_000, f"the fixture's project is 30 fps (a frame is {frame} ticks)")
    length = s.clip(clip)["duration"]
    check(length == 10 * SEC, f"the whole 10 s file is on the timeline ({length} ticks)")

    found = detect(s)
    padding = found["padding"]
    ranges = found["ranges"]
    check(
        found["scope"] == "audible" and found["clips"] == [clip],
        f"the default scope is every audible clip, and it is clip {clip}",
    )
    check(
        (found["threshold_db"], found["min_length"], padding)
        == (-40.0, ticks_of(0.5), ticks_of(0.1)),
        "the defaults are −40 dBFS, 0.5 s and 0.1 s (D-A12)",
    )
    check(len(ranges) == 2, f"two quiet spans are found (got {len(ranges)}: {ranges})")
    if len(ranges) == 2:
        for (start, end), (from_s, to_s) in zip(ranges, QUIET):
            want = (ticks_of(from_s) + padding, ticks_of(to_s) - padding)
            slack = max(abs(start - want[0]), abs(end - want[1]))
            check(
                slack <= BUCKET,
                f"the {from_s}–{to_s} s span is found within one bucket of {want} "
                f"— got ({start}, {end}), off by {slack} ticks",
            )
    check(
        found["removes"] == sum(end - start for start, end in ranges),
        f"`removes` is the total of the spans ({found['removes']} ticks)",
    )

    # The three settings, each in the direction it claims. None of these can
    # pass on a build that ignores its argument: every one asserts an answer
    # that DIFFERS from the default run's.
    wide = detect(s, padding=0)["ranges"]
    check(
        wide == [[ticks_of(a), ticks_of(b)] for a, b in QUIET],
        f"padding 0 widens both spans to the file's exact quiet stretches: {wide}",
    )
    fewer = detect(s, min_length=ticks_of(1.2))["ranges"]
    check(
        fewer == [ranges[0]],
        f"a 1.2 s minimum drops the 1.0 s span and keeps the 1.5 s one: {fewer}",
    )
    # At FULL SCALE nothing can be louder than the threshold, so the whole
    # covered extent reads as quiet — and only the covered extent, which is
    # the "a hole in the timeline is not dead air" rule showing through. A
    # level nearer the tone's would be a hostage to the fixture's amplitude.
    loud = detect(s, threshold_db=0)
    check(
        loud["ranges"] == [[padding, 10 * SEC - padding]],
        f"a threshold at full scale makes the whole clip read as quiet, and only "
        f"the clip: {loud['ranges']}",
    )
    check(
        loud["removes"] > found["removes"],
        f"which removes more than the default −40 dBFS does "
        f"({loud['removes']} > {found['removes']} ticks)",
    )
    return ranges


def ripple_part(mcp, spans):
    print("\n3a — ripple_delete_ranges")
    first, second = [tuple(span) for span in spans]
    removed = (first[1] - first[0]) + (second[1] - second[0])
    frame = 20_000

    s = Session(mcp, "ripple")
    s.clip_of("silence.mov")
    # The four moments the cuts happen at: the last frame BEFORE each span and
    # the first frame AFTER it. Where each lands once the ripple has shifted
    # everything left is arithmetic, not observation.
    before_1, after_1 = first[0] - frame, first[1]
    before_2, after_2 = second[0] - frame, second[1]
    was = {t: s.frame(t) for t in (before_1, after_1, before_2, after_2)}
    check(
        len(set(was.values())) == 4,
        "the four frames either side of the two spans are four different pictures",
    )
    reported, measured = s.export("cut-before")
    check(
        reported == 10 * SEC and abs(measured - 10.0) < 0.02,
        f"the export before the cut is 10 s ({reported} ticks, ffprobe {measured} s)",
    )
    lanes_before = s.lanes()
    text_before = s.text()

    s.op("ripple_delete_ranges", ranges=[list(first), list(second)])
    check(s.lanes() != lanes_before, f"the cut changed the timeline: {s.lanes()[0]}")
    shift = first[1] - first[0]
    check(
        s.frame(before_1) == was[before_1],
        "the frame just before the first cut is byte-identical to what it was",
    )
    check(
        s.frame(first[0]) == was[after_1],
        "the frame the first cut joins to is byte-identical to the one after the span",
    )
    check(
        s.frame(before_2 - shift) == was[before_2],
        "the frame before the second cut is byte-identical, moved left by the first",
    )
    check(
        s.frame(second[0] - shift) == was[after_2],
        "the frame the second cut joins to is byte-identical to the one after it",
    )
    reported, measured = s.export("cut-after")
    check(
        reported == 10 * SEC - removed,
        f"the export is the original minus the removed total exactly "
        f"({reported} = {10 * SEC} − {removed} ticks)",
    )
    check(
        abs(measured - (10 * SEC - removed) / SEC) < 0.02,
        f"and ffprobe measures the file at {measured} s",
    )

    check(s.undo() == "Remove Silences", "undo names the step Remove Silences (C3)")
    check(s.lanes() == lanes_before, "one step: the whole timeline is back")
    check(s.text() == text_before, "and the whole project JSON with it")
    check(
        all(s.frame(t) == was[t] for t in was),
        "and all four frames are byte-identical to before the cut",
    )

    # ---- the order the ranges are cut in ---------------------------------
    print("\n3a — merge, then cut, right to left")
    plural = Session(mcp, "ripple-plural")
    plural.clip_of("silence.mov")
    plural.op("ripple_delete_ranges", ranges=[list(first), list(second)])

    backwards = Session(mcp, "ripple-rtl")
    backwards.clip_of("silence.mov")
    backwards.op("ripple_delete_range", **{"from": second[0], "to": second[1]})
    backwards.op("ripple_delete_range", **{"from": first[0], "to": first[1]})

    forwards = Session(mcp, "ripple-ltr")
    forwards.clip_of("silence.mov")
    forwards.op("ripple_delete_range", **{"from": first[0], "to": first[1]})
    forwards.op("ripple_delete_range", **{"from": second[0], "to": second[1]})

    check(
        plural.lanes() == backwards.lanes(),
        f"two disjoint ranges in one op == the two singular ops applied RIGHT TO "
        f"LEFT {plural.lanes()[0]}",
    )
    check(
        plural.lanes() != forwards.lanes(),
        f"and NOT the same two applied left to right {forwards.lanes()[0]}",
    )
    # The lanes carry `source in`, so they already pin which material survived;
    # the frames say it in pixels.
    moments = (500_000, 1_500_000, 2_500_000, 3_500_000)
    check(
        [plural.frame(t) for t in moments] == [backwards.frame(t) for t in moments],
        "and four frames across the result are byte-identical",
    )
    check(
        [plural.frame(t) for t in moments] != [forwards.frame(t) for t in moments],
        "while the left-to-right cut shows different pictures",
    )

    print("\n3a — touching and overlapping ranges merge")
    for label, pair, merged, singly in [
        ("touching", [[2 * SEC, 4 * SEC], [4 * SEC, 5 * SEC]], [2 * SEC, 5 * SEC],
         [[4 * SEC, 5 * SEC], [2 * SEC, 4 * SEC]]),
        ("overlapping", [[2 * SEC, 4 * SEC], [3 * SEC, 6 * SEC]], [2 * SEC, 6 * SEC],
         [[3 * SEC, 6 * SEC], [2 * SEC, 4 * SEC]]),
    ]:
        both = Session(mcp, f"merge-{label}")
        both.clip_of("silence.mov")
        both.op("ripple_delete_ranges", ranges=pair)
        one = Session(mcp, f"merge-{label}-one")
        one.clip_of("silence.mov")
        one.op("ripple_delete_ranges", ranges=[merged])
        apart = Session(mcp, f"merge-{label}-apart")
        apart.clip_of("silence.mov")
        for span in singly:
            apart.op("ripple_delete_range", **{"from": span[0], "to": span[1]})
        check(
            both.lanes() == one.lanes(),
            f"{label} ranges cut exactly as the one range they merge to "
            f"(lanes and next_id: {one.lanes()})",
        )
        check(
            apart.lanes() != one.lanes(),
            f"and the same pair as two singular ops does NOT — {apart.lanes()}; "
            f"the merge is the difference",
        )


def nest_part(mcp):
    """A nest is a wall the detector will not cut through.

    The plan FLATTENS a nest into one segment per clip inside it, so the
    detector measures a nested clip's audio and gets back the INNER clip's
    id — the first check below is that trap, measured rather than argued.
    Acting on it would be destruction, not an edit: `Source::Nest` has no in
    point, so `ripple_delete_ranges` splitting a nest clip leaves two clips
    that each replay the nest from its first frame with the tail unreachable.
    So a nest's sound still PROTECTS a span, but no proposed span may reach
    into one.

    Two clips of the same 10 s fixture, back to back, with the SECOND nested:
    the first holds its dead air on the timeline where a cut is safe, the
    second holds exactly the same dead air behind the wall. A build that
    proposes nothing at all fails the first pair of checks; a build that cuts
    through the nest fails the second.
    """
    print("\n3a — a nest is a wall")
    s = Session(mcp, "silence-nest")
    media = s.op("import_media", path=os.path.join(MEDIA, "silence.mov"))["media"]
    track = s.project()["tracks"][0]["id"]
    plain = s.op("add_clip", track=track, media=media, at=0)["new_clips"][0]
    inner = s.op("add_clip", track=track, media=media, at=10 * SEC)["new_clips"][0]
    # No `name`: `Session.op` spends that keyword on the tool's own name, and
    # the default "Nest 1" is nothing this section reads.
    s.op("nest", clips=[inner])

    nests = [c for c in s.project()["clips"] if c["source"]["kind"] == "nest"]
    check(
        len(nests) == 1
        and (nests[0]["start"], nests[0]["duration"]) == (10 * SEC, 10 * SEC),
        f"the fixture: one 10 s clip on the timeline and a second nested at 10 s "
        f"({[(c['start'], c['duration']) for c in nests]})",
    )
    nest = nests[0]
    nest_start, nest_end = nest["start"], nest["start"] + nest["duration"]

    found = detect(s)
    ranges = found["ranges"]
    # The trap itself: the segments the detector reads inside the nest carry
    # the INNER clip's id, which `get_project` shows nowhere in `clips[]` —
    # nest_clips moves clips whole, so the id survives into the nest.
    check(
        inner in found["clips"] and nest["id"] not in found["clips"],
        f"the plan flattens the nest: the detector measured inner clip {inner}, "
        f"never the nest clip {nest['id']} ({found['clips']})",
    )

    # The guard. Without it the same two quiet stretches are proposed a
    # second time, 10 s later, INSIDE the nest.
    inside = [r for r in ranges if r[1] > nest_start and r[0] < nest_end]
    check(
        not inside,
        f"no proposed span reaches into the nest [{nest_start}, {nest_end}) "
        f"— got {inside or 'none'} of {ranges}",
    )
    # And it does not pass by proposing nothing: the identical dead air in
    # front of the nest is still found, to the same tolerance 3a's first
    # section measures.
    padding = found["padding"]
    check(
        len(ranges) == 2,
        f"the two quiet spans OUTSIDE the nest are still proposed (got {len(ranges)}: "
        f"{ranges})",
    )
    if len(ranges) == 2:
        for (start, end), (from_s, to_s) in zip(ranges, QUIET):
            want = (ticks_of(from_s) + padding, ticks_of(to_s) - padding)
            slack = max(abs(start - want[0]), abs(end - want[1]))
            check(
                slack <= BUCKET,
                f"the {from_s}–{to_s} s span is found within one bucket of {want} "
                f"— got ({start}, {end}), off by {slack} ticks",
            )

    # The harm the wall exists to prevent, in pixels and in placement: cut
    # what was proposed, and the nest must arrive intact, one clip, moved
    # left by the removed total, still showing its own 9 s frame.
    removed = sum(end - start for start, end in ranges)
    deep = nest_start + 9 * SEC
    tail = s.frame(deep)
    check(tail != s.frame(nest_start), "the nest's 9 s frame is not its first frame")
    s.op("ripple_delete_ranges", ranges=ranges)
    after = [c for c in s.project()["clips"] if c["source"]["kind"] == "nest"]
    check(
        len(after) == 1 and after[0]["duration"] == nest["duration"],
        f"the nest clip came through the cut whole, not split "
        f"({[(c['start'], c['duration']) for c in after]})",
    )
    check(
        after and after[0]["start"] == nest_start - removed,
        f"moved left by the removed total, exactly ({nest_start} − {removed})",
    )
    check(
        s.frame(deep - removed) == tail,
        "and its 9 s frame is byte-identical to what it was — the tail is still "
        "reachable",
    )


# ---- 3b: Zoom to Region ---------------------------------------------------
#
# The canvas is 640 × 360 and A.mov is 640 × 360, so an untransformed layer
# puts source pixel s at canvas pixel s. `testsrc`'s middle band is flat
# colour bars: at source row 160 the cyan/magenta edge sits near x = 159 and
# the magenta/blue edge near x = 239, and `crossing` locates both to a
# fraction of a pixel.
#
# The placement rule, restated here in the proof's own terms so nothing is
# read out of the thing being tested (CONTRACT D-B1/D-B3): a zoom to a region
# of size (rw, rh) centred at (cx, cy) in SOURCE pixels puts the region's
# centre at the canvas centre, magnified by
#
#     fit  = min(W / (k·rw + m·rh), H / (m·rw + k·rh))
#     fill = max(   the same two   )      with k = |cos θ|, m = |sin θ|
#
# — the region's extent measured THROUGH the layer's rotation, which collapses
# to min(W/rw, H/rh) at θ = 0.

ROW = 160                 # the source row the bar edges are measured on
LEFT_EDGE = (140, 180)    # windows around the two edges, well inside both bars
RIGHT_EDGE = (220, 260)


def zoom_scale(region, fill=False, rotation=0.0):
    width, height = CANVAS
    k = abs(math.cos(math.radians(rotation)))
    m = abs(math.sin(math.radians(rotation)))
    across = width / (k * region["width"] + m * region["height"])
    down = height / (m * region["width"] + k * region["height"])
    return max(across, down) if fill else min(across, down)


def landing(source_index, centre, scale, middle):
    """Where the base frame's pixel `source_index` lands once the region
    centred at `centre` has been magnified by `scale` about the canvas's
    `middle`. Pixel index in, pixel index out."""
    return middle + scale * (source_index + 0.5 - centre) - 0.5


def zoom_part(mcp):
    print("\n3b — zoom to region")
    s = Session(mcp, "zoom")
    clip = s.clip_of("A.mov")
    base = s.image(2 * SEC)
    row = base.row(ROW)
    left = crossing(row, *LEFT_EDGE)
    right = crossing(row, *RIGHT_EDGE)
    check(
        left is not None and right is not None
        and 150 < left < 170 and 230 < right < 250,
        f"the test card gives two measurable bar edges at source row {ROW}: "
        f"{fmt(left)} and {fmt(right)}",
    )
    if left is None or right is None:
        return

    # A 16:9 region, so fit and fill agree and this measures the placement
    # alone: 160 × 90 source pixels centred at source (200, 160).
    region = {"x": -120.0, "y": -20.0, "width": 160.0, "height": 90.0}
    centre_x = CANVAS[0] / 2 + region["x"]
    centre_y = CANVAS[1] / 2 + region["y"]
    scale = zoom_scale(region)
    s.op("add_zoom_action", clip=clip, at=1 * SEC, duration=1 * SEC, region=region)
    zoomed = s.image(2 * SEC)

    # (1) The region's centre pixel is the canvas's centre pixel.
    middle = zoomed.pixel(CANVAS[0] // 2, CANVAS[1] // 2)
    check(
        middle == base.pixel(int(centre_x), int(centre_y)),
        f"the pixel at the region's centre is the pixel at the canvas's centre "
        f"{middle}",
    )
    check(
        base.pixel(CANVAS[0] // 2, CANVAS[1] // 2) != middle,
        "and a different colour was there before the zoom, so that is not free",
    )

    # (2) The two bar edges land where the fit magnification puts them.
    zoom_row = zoomed.row(CANVAS[1] // 2)
    want_left = landing(left, centre_x, scale, CANVAS[0] / 2)
    want_right = landing(right, centre_x, scale, CANVAS[0] / 2)
    got_left = crossing(zoom_row, int(want_left) - 40, int(want_left) + 40)
    got_right = crossing(zoom_row, int(want_right) - 40, int(want_right) + 40)
    check(
        got_left is not None and abs(got_left - want_left) <= 1,
        f"the left bar edge lands at {want_left:.2f} ± 1 px — measured {fmt(got_left)}",
    )
    check(
        got_right is not None and abs(got_right - want_right) <= 1,
        f"the right bar edge lands at {want_right:.2f} ± 1 px — measured "
        f"{fmt(got_right)}",
    )

    # (3) The region's width IS the canvas's width, measured off the frame.
    if got_left is not None and got_right is not None:
        magnification = (got_right - got_left) / (right - left)
        spans = magnification * region["width"]
        check(
            abs(spans - CANVAS[0]) <= 1,
            f"the region's {region['width']:.0f} source px measure {spans:.2f} "
            f"canvas px — the canvas's own {CANVAS[0]}, ± 1 (fit)",
        )
        # Where the region's own left edge lands, extrapolated from the
        # measured edge and the measured magnification. In canvas
        # COORDINATES: the base pixel `left` is sampled at source coordinate
        # left + 0.5, and the canvas's left edge is coordinate 0, so this is
        # the one place the half pixel has to be spelled out.
        source_edge = centre_x - region["width"] / 2
        edge = (got_left + 0.5) - ((left + 0.5) - source_edge) * magnification
        check(
            abs(edge) <= 1,
            f"and the region's left edge lands on the canvas's left edge, "
            f"{edge:.2f} px from it — so the width is centred, not just right",
        )
    # Kept for the rotation contrast below: down the middle of a fit zoom the
    # picture is one flat bar.
    fit_column = zoomed.column(CANVAS[0] // 2)[40:321]
    check(s.undo() == "Zoom to Region", "undo names the step Zoom to Region (C3)")

    # (4) fill takes the larger magnification where fit takes the smaller.
    print("\n3b — fit and fill")
    wide = {"x": -100.0, "y": -20.0, "width": 160.0, "height": 45.0}
    wide_centre = CANVAS[0] / 2 + wide["x"]
    seen = {}
    for mode in ("fit", "fill"):
        want_scale = zoom_scale(wide, fill=(mode == "fill"))
        s.op("add_zoom_action", clip=clip, at=1 * SEC, duration=1 * SEC,
             region=wide, fit=mode)
        picture = s.image(2 * SEC)
        want = landing(right, wide_centre, want_scale, CANVAS[0] / 2)
        got = crossing(picture.row(CANVAS[1] // 2), int(want) - 40, int(want) + 40)
        seen[mode] = got
        check(
            got is not None and abs(got - want) <= 1,
            f"on a 32:9 region {mode} magnifies by {want_scale:g}: the bar edge "
            f"lands at {want:.2f} ± 1 px — measured {fmt(got)}",
        )
        s.undo()
    check(
        None not in seen.values() and abs(seen["fit"] - seen["fill"]) > 50,
        f"and the two are different pictures ({fmt(seen['fit'])} vs "
        f"{fmt(seen['fill'])} px)",
    )

    # (5) A rotated clip zooms to the right place.
    print("\n3b — a rotated clip")
    s.op("set_video", clips=[clip], patch={"rotation": 90})
    turned_scale = zoom_scale(region, rotation=90)
    s.op("add_zoom_action", clip=clip, at=1 * SEC, duration=1 * SEC, region=region)
    turned = s.image(2 * SEC)
    check(
        turned.pixel(CANVAS[0] // 2, CANVAS[1] // 2)
        == base.pixel(int(centre_x), int(centre_y)),
        "turned a quarter turn, the region's centre pixel is still the canvas's",
    )
    # A quarter turn puts the vertical bars ACROSS the canvas, so the two
    # edges are found down the middle instead of across it — and at the
    # rotation-aware magnification, which is 2.25 here, not the naive 4.
    column = turned.column(CANVAS[0] // 2)
    for name, source_edge in (("first", left), ("second", right)):
        want = landing(source_edge, centre_x, turned_scale, CANVAS[1] / 2)
        got = crossing(column, max(0, int(want) - 30), min(CANVAS[1] - 1, int(want) + 30))
        check(
            got is not None and abs(got - want) <= 1,
            f"the {name} bar edge lands {abs(want - (CANVAS[1] - 1) / 2):.1f} px "
            f"from the canvas centre, DOWN the middle (rotation-aware fit = "
            f"{turned_scale:g}, want {want:.2f}) — measured {fmt(got)}",
        )
    band = turned.row(CANVAS[1] // 2)[215:426]
    check(
        turned.rows != zoomed.rows
        and len(set(band)) == 1 and len(set(fit_column)) == 1,
        f"and the bars run across the turned frame, not down it — a different "
        f"picture from the unturned zoom, whose COLUMN was the flat one: "
        f"{len(set(band))} value(s) across the turned row, {len(set(fit_column))} "
        f"down the unturned column",
    )
    s.undo()
    s.undo()

    # (6) Zoom back.
    print("\n3b — zoom back")
    z = Session(mcp, "zoom-back")
    clip = z.clip_of("A.mov")
    was = {t: z.frame(t) for t in (2 * SEC, 4 * SEC)}
    z.op("add_zoom_action", clip=clip, at=1 * SEC, duration=1 * SEC, region=region)
    zoomed_now = z.frame(2 * SEC)
    check(zoomed_now != was[2 * SEC], "the zoom changed the frame at the action's end")
    check(
        z.frame(4 * SEC) != was[4 * SEC],
        "and the clip is still zoomed two seconds later (an action holds its end)",
    )
    z.op("add_zoom_action", clip=clip, at=3 * SEC, duration=1 * SEC, region=None)
    check(
        z.frame(4 * SEC) == was[4 * SEC],
        "an explicit null region zooms BACK: the frame is byte-identical to the base",
    )
    check(z.frame(2 * SEC) == zoomed_now, "and the zoom before it is untouched")
    check(z.undo() == "Zoom Back", "undo names the step Zoom Back (C3)")
    check(z.frame(4 * SEC) != was[4 * SEC], "one step: the clip is zoomed again")
    check(z.undo() == "Zoom to Region", "and the step under it is the zoom")
    check(z.frame(2 * SEC) == was[2 * SEC], "which restores the base frame byte for byte")
    message = z.error("add_zoom_action", clip=clip, at=1 * SEC) or ""
    check(
        "region" in message,
        f"an absent region is refused BY NAME, not read as a zoom back (D-B2): "
        f"{message[:60]!r}",
    )


# ---- 3c: Obscure ----------------------------------------------------------
#
# One region over the test card, its rectangle chosen to sit on the pixelate
# grid: source x 128–384, y 64–256, which is four whole 64-pixel block columns
# and three whole rows. `feather` is 0, so the mask is exactly the rectangle
# and "outside is byte-identical" is a claim about every pixel, not most.

REGION = {
    "shape": "rect", "x": -64.0, "y": -20.0, "width": 256.0, "height": 192.0,
    "feather": 0.0, "kind": "pixelate", "amount": 1.0,
}
BLOCK = 64                    # source px a side at amount 1 (CompositorEffects.swift)
RECT = (128, 64, 384, 256)    # the region in canvas pixels at scale 1


def region_at(scale):
    """The region's rectangle in canvas pixels when the layer is at `scale`,
    from the region's own numbers: a length on a layer is in SOURCE pixels, so
    scaling the layer scales the region with it."""
    cx = CANVAS[0] / 2 + scale * REGION["x"]
    cy = CANVAS[1] / 2 + scale * REGION["y"]
    return (cx - scale * REGION["width"] / 2, cy - scale * REGION["height"] / 2,
            cx + scale * REGION["width"] / 2, cy + scale * REGION["height"] / 2)


def obscure_part(mcp):
    print("\n3c — one region on the picture")
    s = Session(mcp, "obscure")
    clip = s.clip_of("A.mov")
    plain = s.image(2 * SEC)
    plain_hash = digest(plain.path)

    s.op("set_video", clips=[clip], patch={"obscure": [REGION]})
    stored = s.clip(clip)["video"]["obscure"]
    check(
        len(stored) == 1 and same_region(stored[0], REGION),
        f"the region reads back through get_project as it was sent: {stored}",
    )
    hidden = s.image(2 * SEC)
    moved = hidden.changed(plain)
    x0, y0, x1, y1 = RECT
    outside = [(x, y) for x, y in moved if not (x0 <= x < x1 and y0 <= y < y1)]
    check(
        not outside,
        f"every one of the {len(moved)} changed pixels is INSIDE the region — "
        f"nothing outside it moved by a byte",
    )
    area = (x1 - x0) * (y1 - y0)
    check(
        len(moved) > area // 4,
        f"and {100 * len(moved) // area}% of the region's pixels did change (the "
        f"rest are blocks whose source was already one colour)",
    )

    # Flat blocks of the expected size, measured in the region's INTERIOR: the
    # grid is anchored at the TEXTURE origin, so the first three whole block
    # columns of the middle block row are the honest place to look.
    print("\n3c — flat blocks of the expected size")
    row = CANVAS[1] // 2       # canvas y 180 is inside the block row 128–192
    runs, start, previous = [], 0, hidden.pixel(0, row)
    for x in range(1, CANVAS[0]):
        colour = hidden.pixel(x, row)
        if colour != previous:
            runs.append((start, x))
            start, previous = x, colour
    runs.append((start, CANVAS[0]))
    wanted = [(x0 + i * BLOCK, x0 + (i + 1) * BLOCK) for i in range(3)]
    got = [(a, b) for a, b in runs if x0 <= a < x0 + 3 * BLOCK]
    check(
        got == wanted,
        f"at amount 1 the picture is flat {BLOCK}-pixel runs on the block grid: "
        f"{got} (wanted {wanted})",
    )
    colours = [hidden.pixel(a, row) for a, _ in wanted]
    check(
        len(set(colours)) == 3,
        f"and the three neighbouring blocks are three different colours {colours}",
    )
    rows = range(y0 + BLOCK, y0 + 2 * BLOCK)
    flat, ragged = True, True
    for a, b in wanted:
        now = {hidden.pixel(x, y) for x in range(a, b) for y in rows}
        was = {plain.pixel(x, y) for x in range(a, b) for y in rows}
        flat = flat and len(now) == 1
        ragged = ragged and len(was) > 1
    check(flat, f"each is one colour over the whole {BLOCK} × {BLOCK} block")
    check(ragged, "and none of the three was one colour before the region was added")

    # Scaling the layer scales the region.
    print("\n3c — the region rides with its layer")
    offset_at = {}
    for scale in (1.0, 0.5):
        s.op("set_video", clips=[clip], patch={"scale": scale, "obscure": []})
        bare = s.image(2 * SEC)
        s.op("set_video", clips=[clip], patch={"obscure": [REGION]})
        pixels = s.image(2 * SEC).changed(bare)
        left, top, right, bottom = box(pixels)
        want = region_at(scale)
        check(
            want[0] <= left and want[1] <= top and right < want[2] and bottom < want[3],
            f"at scale {scale:g} every changed pixel is inside the region's own "
            f"rectangle {tuple(round(v) for v in want)} — measured ({left}, {top})"
            f"–({right}, {bottom})",
        )
        offset_at[scale] = ((left + right) / 2 - (CANVAS[0] - 1) / 2,
                            (top + bottom) / 2 - (CANVAS[1] - 1) / 2)
    check(
        offset_at[1.0] != (0.0, 0.0)
        and all(abs(half * 2 - whole) <= 0.5
                for half, whole in zip(offset_at[0.5], offset_at[1.0])),
        f"and halving the layer's scale halves the changed area's offset from the "
        f"canvas centre: {offset_at[1.0]} → {offset_at[0.5]}",
    )

    s.op("set_video", clips=[clip], patch={"scale": 1.0})
    check(s.frame(2 * SEC) != plain_hash, "(the region is still on the picture)")
    s.op("set_video", clips=[clip], patch={"obscure": []})
    check(
        s.frame(2 * SEC) == plain_hash,
        "clearing the list returns the frame byte-identically to before the region",
    )


def obscure_overlap_part(mcp):
    """Two regions on one fragment — the overlap rule D-C5 promises, which is
    "the strongest wins" and never "the last one written wins".

    Every frame here is compared against a reference rendered by the SAME
    specialization of the fragment stage: a list holding a blur region at any
    amount, 0 included, puts the layer on the gather build
    (`CompositorEffects.swift`'s `needsGather`), and two builds of one shader
    are not something a BYTE comparison should have to trust. So the pixelate's
    own reference carries a blur region at amount 0 — which is also half of
    what the second claim below is about.

    The test card is vertical colour bars, flat except at their edges, so both
    boxes here straddle the cyan/magenta edge at source x ≈ 159: a region over
    flat colour hides nothing measurable and would make every check vacuous."""
    print("\n3c — two regions on one fragment")
    s = Session(mcp, "obscure-overlap")
    clip = s.clip_of("A.mov")
    t = 2 * SEC

    def still(regions):
        if s.clip(clip)["video"]["obscure"] != regions:
            s.op("set_video", clips=[clip], patch={"obscure": regions})
        return s.frame(t)

    # The same box as REGION for all four, so the two masks are equal per
    # fragment and only the KINDS are being compared.
    pixelate = dict(REGION, kind="pixelate", amount=1.0)
    blur_off = dict(REGION, kind="blur", amount=0.0)
    blur_weak = dict(REGION, kind="blur", amount=0.05)     # a 1.2 px tap ring
    blur_full = dict(REGION, kind="blur", amount=1.0)      # 24 px, the maximum
    pixel_weak = dict(REGION, kind="pixelate", amount=0.05)  # a 4 px block

    plain = still([])
    pixelated = still([pixelate, blur_off])
    blurred = still([blur_weak])
    check(
        len({plain, pixelated, blurred}) == 3,
        "the plain frame, the pixelated one and the weakly blurred one are three "
        "different pictures",
    )
    check(
        still([pixelate, blur_weak]) == pixelated,
        "a 5% blur region dropped on a full-strength pixelation leaves the "
        "PIXELATION: byte-identical to the pixelate alone (D-C5, the strongest "
        "wins per fragment)",
    )
    check(
        still([pixelate, blur_weak]) != blurred,
        "and it is NOT the weak blur's own picture — a second region cannot "
        "un-hide what the first one destroyed",
    )
    check(
        still([blur_weak, pixelate]) == pixelated,
        "the same two in the other order render the same frame — the pixelation "
        "again: overlapping regions have no order (VideoPane's obscureSection "
        "says so, which is why the section has no position popup)",
    )
    # The rule's other direction, which is what tells "the strongest wins" from
    # "the pixelate always wins": at a 4-pixel block against a 24-pixel tap
    # ring the blur is the stronger, and it is the blur that shows.
    full_blur = still([blur_full])
    check(
        still([blur_full, pixel_weak]) == full_blur,
        "a 5% pixelation under a full-strength blur leaves the BLUR, "
        "byte-identical to the blur alone",
    )

    print("\n3c — a region that hides nothing changes nothing")
    # The outer region's feather is 200, so its mask ramps from 0.5 at the box
    # edge to 1 a hundred pixels inside. The inner box sits 20–60 px inside the
    # left edge, where that ramp reads about 0.6–0.8 — the one place a
    # neighbour's cover being taken at the bare max of the masks would show.
    inner = {"shape": "rect", "x": -152.0, "y": -20.0, "width": 40.0,
             "height": 40.0, "feather": 0.0, "kind": "pixelate", "amount": 0.0}
    for kind in ("pixelate", "blur"):
        outer = dict(REGION, feather=200.0, kind=kind, amount=1.0)
        ramp = still([outer])
        check(ramp != plain, f"the feathered {kind} region on its own hides something")
        check(
            still([outer, dict(inner, kind=kind, amount=0.0)]) == ramp,
            f"a {kind} region at amount 0 inside its ramp changes NOT ONE BYTE — "
            f"it is there and it hides nothing (model_regions.rs)",
        )
        check(
            still([outer, dict(inner, kind=kind, amount=1.0)]) != ramp,
            f"while the same box at amount 1 does change the frame, so the box "
            f"is somewhere the {kind} cover is what decides the picture",
        )


def obscure_action_part(mcp):
    print("\n3c — an obscured region under an action")
    s = Session(mcp, "obscure-action")
    clip = s.clip_of("A.mov")
    mid_t, end_t = 2 * SEC, 3 * SEC

    def still(regions, t):
        """The frame a STATIC region list renders — the oracle an animated one
        is compared against. The list is only written when it differs, because
        writing what is already there is a documented refusal."""
        if s.clip(clip)["video"]["obscure"] != regions:
            s.op("set_video", clips=[clip], patch={"obscure": regions})
        return s.frame(t)

    def variant(**changes):
        return dict(REGION, **changes)

    plain = still([], mid_t)
    at_zero = still([variant(amount=0.0)], mid_t)
    at_half = still([variant(amount=0.5)], mid_t)
    at_one = still([variant(amount=1.0)], mid_t)
    check(
        at_zero == plain,
        "amount 0 is a block of one pixel, which the shader skips: the frame is "
        "byte-identical to no region at all",
    )
    check(
        len({plain, at_half, at_one}) == 3,
        "and amount 0.5 and amount 1 are two more, different pictures",
    )

    still([variant(amount=0.0)], mid_t)
    action = s.op("add_action", clip=clip, at=1 * SEC, duration=2 * SEC)["new_actions"][0]
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"obscure": [variant(amount=1.0)]}})
    halfway = s.frame(mid_t)
    check(
        halfway not in (at_zero, at_one),
        "halfway through an action from amount 0 to 1 the frame is NEITHER endpoint",
    )
    check(
        halfway == at_half,
        "it is byte-identical to the still at amount 0.5 — the list interpolates "
        "per index (D-C4)",
    )
    s.op("remove_action", clip=clip, action=action)

    # The list rule's other half: an entry whose SHAPE disagrees holds, and
    # switches at the end. Asserted on the FRAME, not on the JSON.
    print("\n3c — a list entry that disagrees holds and switches at the end")
    wide = variant(width=256.0)
    narrow = variant(width=128.0)
    middle = variant(width=192.0)
    ellipse = variant(shape="ellipse", width=128.0)
    wide_still = still([wide], mid_t)
    middle_still = still([middle], mid_t)
    narrow_still = still([narrow], end_t)
    ellipse_still = still([ellipse], end_t)
    check(
        wide_still != middle_still and narrow_still != ellipse_still,
        "the stills the two animations are judged against are different pictures",
    )

    still([wide], mid_t)
    action = s.op("add_action", clip=clip, at=1 * SEC, duration=2 * SEC)["new_actions"][0]
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"obscure": [narrow]}})
    check(
        s.frame(mid_t) == middle_still,
        "an entry whose shape and kind AGREE interpolates: at the midpoint the "
        "region is 192 px wide, which is the still's own frame",
    )
    check(s.frame(end_t) == narrow_still, "and at the end it is the end state")
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"obscure": [ellipse]}})
    check(
        s.frame(mid_t) == wide_still,
        "an entry whose SHAPE disagrees HOLDS: at the midpoint the frame is still "
        "the start state's, not a 192-px-wide anything",
    )
    check(s.frame(end_t) == ellipse_still, "and it switches to the ellipse at the end")


def list_length_part(mcp):
    """The rule `InspectorBinding.structural(video:for:)` follows, pinned at
    the level this script can reach.

    **What it can and cannot show.** The defect is in the inspector's binding:
    Add Region, Remove and "Place on Canvas" used to be routed to
    `set_action_end` like every other field, because the binding sends every
    video write to the action under the playhead. What is measured here is the
    CORE behaviour that makes that routing wrong — a list of a different LENGTH
    in an end patch is invisible for the whole span and is destroyed by the
    next write of the list the pane can read, while the same list on the BASE
    props is visible throughout the action. No check below fails merely because
    the Swift routing is reverted: no MCP tool reaches an inspector control (the
    catalog is the op table plus the app-state tools), and nothing else in the
    tree can press a button in a pane. It fails if the premise the fix rests on
    stops holding, which is the part a later reader could break by "simplifying"
    either side.
    """
    print("\n3c — a list write inside an action: a LENGTH is not an animation")
    s = Session(mcp, "obscure-length")
    clip = s.clip_of("A.mov")
    start_t, mid_t, end_t = 1 * SEC, 2 * SEC, 3 * SEC
    span = (start_t, mid_t, end_t)

    plain = {t: s.frame(t) for t in span}
    s.op("set_video", clips=[clip], patch={"obscure": [REGION]})
    shown = {t: s.frame(t) for t in span}
    check(
        all(shown[t] != plain[t] for t in span),
        "the region on the clip's own props changes the frame at the action's "
        "start, midpoint and end — the picture both routings are judged against",
    )
    s.op("set_video", clips=[clip], patch={"obscure": []})
    check(s.frame(mid_t) == plain[mid_t], "and clearing it returns the plain frame")

    # (1) What an append used to send: the longer list into the action's END
    # patch, over a base list of a different length.
    action = s.op("add_action", clip=clip, at=start_t, duration=2 * SEC)["new_actions"][0]
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"obscure": [REGION]}})
    check(
        s.frame(mid_t) == plain[mid_t],
        "a ONE-entry list in an end patch over an EMPTY base list is invisible at "
        "the midpoint — byte-identical to no region at all, because the lengths "
        "disagree and actions.rs holds the whole list",
    )
    check(
        s.frame(start_t) == plain[start_t] and s.frame(end_t) == shown[end_t],
        "it appears only on the action's last tick: an appended region is invisible "
        "everywhere the user who appended it is looking",
    )

    # (2) And it does not survive. The pane sends the whole array it can READ,
    # which check (1) just showed is the base one — there is no clip_state tool,
    # so the frame is what says which list the inspector would see.
    seen = s.clip(clip)["video"]["obscure"]
    check(seen == [], "the list under the playhead is the base's, and it is empty")
    s.op("set_action_end", clip=clip, action=action, patch={"video": {"obscure": seen}})
    stored = [a for a in s.clip(clip)["actions"] if a["id"] == action][0]
    check(
        stored.get("end", {}).get("video", {}).get("obscure") == [],
        "writing it back — which is what the next edit in the section does — leaves "
        "the end patch holding an EMPTY list: the appended region is gone, with no "
        "refusal and no undo step that names it",
    )
    check(s.frame(end_t) == plain[end_t], "and the frame at the action's end is plain again")
    s.op("remove_action", clip=clip, action=action)

    # (3) Where the fix puts it: the clip's own props, action or no action.
    s.op("set_video", clips=[clip], patch={"obscure": [REGION]})
    action = s.op("add_action", clip=clip, at=start_t, duration=2 * SEC)["new_actions"][0]
    check(
        all(s.frame(t) == shown[t] for t in span),
        "the same list on the CLIP's props is byte-identical to the no-action "
        "picture at all three times — an appended region is visible for the whole "
        "span, which is what makes it editable at all",
    )

    # (4) The boundary, so the rule stays narrow: at EQUAL lengths the very
    # same routing animates, which is what a region's end state is for. The
    # contrast with (1) is the whole rule — only a length change moves. The
    # base is still the one region check (3) put there, 256 px wide.
    narrower = dict(REGION, width=128.0)
    s.op("set_action_end", clip=clip, action=action,
         patch={"video": {"obscure": [narrower]}})
    check(
        s.frame(mid_t) not in (shown[mid_t], plain[mid_t]),
        "an end patch whose list is the SAME length moves the picture at the "
        "midpoint — neither endpoint, and not the plain frame either: that write "
        "belongs to the action, and the fix leaves it there",
    )


def schema_part(mcp):
    print("\n3c — schema v4")
    s = Session(mcp, "obscure-schema")
    clip = s.clip_of("A.mov")
    s.op("set_video", clips=[clip], patch={"obscure": [REGION]})
    s.save()
    with open(os.path.join(s.path, "project.json"), encoding="utf-8") as handle:
        text = handle.read()
    root = json.loads(text)
    check(
        root["version"] == 8,
        f"the saved project.json is version 8 (got {root['version']})",
    )
    # Version 4 put `obscure` last and this check pinned it there. Version 6
    # appended `blend` after it and version 8 `motion` after that, each
    # FALSIFYING the previous wording on purpose — so the claim MOVES rather
    # than goes away, because what it is really pinning is that a new key
    # lands at the END and never in the middle. That is the whole of the
    # append-only rule, and it is what lets a v3 file diffed against a v8 one
    # differ by trailing keys rather than by a re-ordering.
    check(
        all(
            list(c["video"].keys())[-2:] == ["blend", "motion"]
            for c in root["clips"]
            if c["video"]
        ),
        "and obscure is still where version 4 left it, with version 6's blend and\n"
        "         version 8's motion appended after it",
    )
    check(
        len(root["clips"][0]["video"]["obscure"]) == 1
        and same_region(root["clips"][0]["video"]["obscure"][0], REGION),
        "holding the region as it was sent",
    )

    # A version-3 fixture: the same package with the key REMOVED, not emptied.
    fixture = os.path.join(WORK, f"obscure-v3-source-{os.getpid()}.reelcut")
    if os.path.exists(fixture):
        shutil.rmtree(fixture)
    copy_package(s.path, fixture)
    older = json.loads(text)
    older["version"] = 3
    for entry in older["clips"]:
        if entry.get("video"):
            entry["video"].pop("obscure", None)
    with open(os.path.join(fixture, "project.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps(older, indent=2))
    check(
        '"obscure"' not in json.dumps(older) and older["version"] == 3,
        "the fixture on disk is version 3 with no obscure key anywhere",
    )
    v3 = Session(mcp, "obscure-v3", open_from=fixture)
    project = v3.project()
    check(project["version"] == 8, "a version-3 file opens and reports version 8")
    check(
        all(c["video"]["obscure"] == [] for c in project["clips"] if c["video"]),
        "and every clip reads an EMPTY region list",
    )

    target = project["clips"][0]["id"]
    message = v3.error(
        "set_video", clips=[target],
        patch={"obscure": [dict(REGION, kind="glow")]}) or ""
    check(
        "kind" in message and "blur" in message and "pixelate" in message,
        f"a kind outside the closed enum is refused BY NAME: {message[:90]!r}",
    )
    message = v3.error("set_video", clips=[target], patch={"obscure": [REGION] * 5}) or ""
    check(
        "4" in message and "5" in message,
        f"and a fifth region is refused rather than silently dropped: {message[:90]!r}",
    )
    # This was a printed NOTE and not a check for as long as it was true: the
    # agent's video patch was decoded into typed Swift structs and
    # re-serialized, so an unknown key INSIDE a nested object was dropped
    # before the core's own unknown-key check could name it, for `shadow` and
    # `filters` as much as for a region. **D1·3 (kpgalligan/reelcut#4) closed
    # it**: `set_video` forwards the caller's patch to the core unread, so the
    # two calls below are refused by their dotted path, and what used to be a
    # note about a standing defect is two claims. They stay HERE, beside the
    # region list they were written for, rather than moving to
    # `tools/proof/patch_door_proof.py`: a misspelt key inside an `obscure`
    # entry is phase 3's own shape.
    inside = v3.error(
        "set_video", clips=[target], patch={"obscure": [{"kind": "blur", "amont": 0.5}]})
    check(
        inside is not None and 'unknown key "obscure[0].amont" in a video patch' in inside,
        f"a misspelt key INSIDE a region is refused by its dotted path, index and all: "
        f"{inside!r}",
    )
    older_one = v3.error("set_video", clips=[target], patch={"shadow": {"blurr": 8}})
    check(
        older_one is not None
        and 'unknown key "shadow.blurr" in a video patch' in older_one,
        f"and so is one inside the older `shadow`, which is the same rule and not a "
        f"second one: {older_one!r}",
    )


def main():
    os.makedirs(WORK, exist_ok=True)
    mcp = MCP(PORT)

    print("catalog")
    names = mcp.tools()
    # A floor, not the count, by the convention phase2_proof.py states in its
    # own comment: the EXACT count belongs to the newest phase's script, since
    # it is what tells a stale binary on the port from the build under test.
    # Phase 3 found 68 — ripple_delete_ranges, add_zoom_action and
    # detect_silence over phase 2's 65 — and held the exact count until phase 4
    # added transcribe and export_captions and took it over, exactly as this
    # line said it would.
    check(len(names) >= 68, f"the catalog holds phase 3's 68 tools or more (got {len(names)})")
    for tool in ["ripple_delete_ranges", "add_zoom_action", "detect_silence"]:
        check(tool in names, f"{tool} is a tool")

    spans = silence_part(mcp)
    ripple_part(mcp, spans)
    nest_part(mcp)
    zoom_part(mcp)
    obscure_part(mcp)
    obscure_overlap_part(mcp)
    obscure_action_part(mcp)
    list_length_part(mcp)
    schema_part(mcp)

    summary()


def summary(aborted=None):
    """The last line, and the exit status. An op that unexpectedly refused or
    errored — a `ToolError` no check was waiting for — aborts the run and is
    reported as the failure it is, with the checks that had passed by then,
    rather than as a bare traceback with no count."""
    tail = f" — ABORTED by {aborted}" if aborted else ""
    print(f"\n{checks - len(failures)}/{checks} checks passed{tail}")
    if failures:
        for line in failures:
            print(f"  FAILED: {line}")
    if failures or aborted:
        sys.exit(1)


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, RuntimeError, OSError,
            subprocess.CalledProcessError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
