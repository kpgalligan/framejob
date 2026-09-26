"""Road map 4, S1 — Remove Silences judged by VOICE, driven against the built
binary over MCP. §4g's claims 1–11.

Every claim here is a placement read back through `detect_silence` and
`get_project`, a comparison against a reference walk carried IN THIS FILE, or
a sample-for-sample comparison of two exports decoded to PCM. Nothing reads
the app's source, and every check is one that would fail against a build where
the voice path did nothing.

**The truth is measured, not assumed.** `clean.wav` is `say`'s rendering of
three pangrams with two `[[slnc]]` pauses in it, and what those pauses
actually are is the −40 dBFS LEVEL run over the file's DIGITAL silence, which
is exact there — so `TRUTH` is read out of the binary under test in `level`
mode with no padding, once per run, and every voice-mode edge is measured
against it. The fixtures are `say`'s and ffmpeg's, so their lengths are HOST
STATE: nothing here hard-codes a second of the recording.

**The reference walk** (`expected_spans`) mirrors `SilenceDetector.detect`,
`refine`, `MediaPeaks.sourceTick`, `MediaPeaks.window` and
`MediaPeaks.bucketIndex` in Python over the probabilities the app itself
wrote into `cache/speech/<id>.bin`. It is what makes claims 1(a), 1(c) and 9
TICK-EXACT rather than tolerant: a tolerance of one bucket would hide every
mutant the max-over-a-step rule and the reversed mirror have. The segment it
walks is read back off `get_project` — a clip's `source_duration` is what the
plan resolved for it, which a clip at a SPEED other than 1 leaves different
from its `duration`, so `sourceTick` is given both (`core/src/evaluate.rs`,
`core/src/edit_clip.rs`). A whole-file clip at rate 1 is the case where the
two now agree: its duration is the media's snapped DOWN, so the segment plays
at rate exactly 1 (spec §11, kpgalligan/reelcut#22); claim 1(d) is the row
where they differ — a ×2 clip whose segment is EXACTLY twice its duration,
since every site that writes a window is now held to the file (spec §11,
D4-3) — so the walk's scale factor is not an identity everywhere.

Three of the four deviations from §4g recorded in
`archive/reelcut-roadmap-4.md` §8 belong to this half, each asserted here as
the tree behaves (§8's (iii), claim 12's sha256 pin, is
`silence2_probe.py`'s):

  (i)   §4g says the edges land INWARD and asks for the sign. They do at the
        START; an END may overrun the truth, because the model's last speech
        chunk ends up to one chunk before the next word and `snapDownToFrame`
        only takes an end DOWN to the frame grid. §2's q6 row measured +0.03
        on clean and hum3 and +0.06 on quiet2, so `OVERRUN` is that row plus
        one 32 ms chunk and the sign is asserted at the start only.
  (ii)  §4g's claim 3 says level mode answers "six" ranges on `quiet2.wav`.
        That count is a property of the fixture's noise, not of the code, so
        it is PRINTED with what it actually was — as is the lead-in span
        `quiet2.wav` produces (q6: the soft first word "The" missed at that
        SNR, §5's recorded limit), printed and not scored.
  (iv)  claim 11 used to TRIM the clip to the last whole frame inside the
        file before exporting, because a whole clip's duration was
        `snapped(media.duration)`, which rounds UP past the end of this
        fixture: the plan played the segment at 0.9990, AVFoundation
        resampled it, two exports of the same material drifted by about
        seventeen samples, and the claim would have been measuring the
        resampler. The core now snaps a media clip's length DOWN (spec §11,
        kpgalligan/reelcut#22, closed 2026-09-19), so the trim is GONE, the
        rate is exactly 1, and the cut export is BYTE-identical to the uncut
        one with the proposed spans excised — stronger than the tolerance
        §4g asked for. The first row of the section asserts the length the
        core minted, which is what the trim used to buy.

Fixtures: made by the script into `work/silence2/fixtures/` when absent or on
`--remake`, never into `media/` (`media/speech.aiff` is phase 4's different
text). `say`, `ffmpeg` and `ffprobe` are needed at proof time.

    python3 tools/proof/silence2_proof.py [port] [--remake]
"""

import math
import os
import re
import shutil
import struct
import subprocess
import sys
import time
from array import array
from collections import namedtuple

from mcp import MCP, ToolError

PORT = 4823
REMAKE = False


def read_arguments():
    """Read in `main`, not at import: `silence2_probe.py` IMPORTS this module
    for the fixture recipes — one spelling of `say`'s text and of the five
    mixes, not two — and its own argv is not this one's."""
    global PORT, REMAKE
    for argument in sys.argv[1:]:
        if argument == "--remake":
            REMAKE = True
        else:
            PORT = int(argument)


HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
FIXTURES = os.path.join(WORK, "silence2", "fixtures")

SEC = 600_000
# One peaks bucket, and the step the detector walks in (`MediaPeaks.bucketTicks`).
BUCKET = 6_000
# One Silero probability's worth of SOURCE time (`MediaSpeech.chunkTicks`):
# 512 samples at 16 kHz, 32 ms, 19 200 ticks.
CHUNK = 19_200

# How far past the truth an END may land, per fixture, in seconds: §2's q6 row
# plus one chunk. Deviation (i) above.
OVERRUN = {"clean": 0.07, "hum3": 0.07, "quiet2": 0.10}
# How far past the truth a START may land — q6's 60–100 ms offset lag, with
# room. The SIGN is asserted too: a start never lands EARLY.
START_LAG = 0.15

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


def note(what):
    """Printed, never scored — §8's deviations (i) and (ii) evidence and the
    two fixture-dependent counts §4g named."""
    print(f"  --   {what}")


def summary(aborted=None):
    tail = f" — ABORTED by {aborted}" if aborted else ""
    print(f"\n{checks - len(failures)}/{checks} checks passed{tail}")
    if failures:
        for line in failures:
            print(f"  FAILED: {line}")
    if failures or aborted:
        sys.exit(1)


def seconds(ticks):
    return ticks / SEC


def ticks_of(value):
    return int(round(value * SEC))


def show(ranges):
    """A list of spans in seconds, for a check's own message."""
    return [[round(seconds(a), 4), round(seconds(b), 4)] for a, b in ranges]


# ---- The fixtures ---------------------------------------------------------
#
# The six recipes are VERBATIM from `tools/proof/silence_spike/README.md`, so
# what S0 measured and what S1 is proved against are the same signals. The
# four after them are this script's own: the clean file at the project's rate,
# the phase 3 tone, a file that is voice THEN tone, and a movie with no sound.


def run(command):
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"{command[0]} failed: {(result.stderr or result.stdout).strip()[:400]}")


SPEECH_TEXT = (
    "The quick brown fox jumps over the lazy dog. [[slnc 1200]] "
    "Pack my box with five dozen liquor jugs. [[slnc 800]] "
    "How vexingly quick daft zebras jump.")

MIXES = {
    "quiet.wav": ["-i", "SPEECH", "-af", "volume=-30dB", "-ar", "48000"],
    "quiet2.wav": [
        "-i", "SPEECH", "-f", "lavfi", "-i",
        "anoisesrc=color=pink:sample_rate=48000:duration=11:amplitude=0.0008",
        "-filter_complex",
        "[0]volume=-35dB[s];[s][1]amix=inputs=2:duration=first:normalize=0[o]",
        "-map", "[o]", "-ar", "48000"],
    "hum.wav": [
        "-i", "SPEECH", "-f", "lavfi", "-i",
        "sine=frequency=120:sample_rate=22050:duration=11",
        "-filter_complex",
        "[1]volume=-45dB[h];[0][h]amix=inputs=2:duration=first:normalize=0[o]",
        "-map", "[o]", "-ar", "48000"],
    "hum2.wav": [
        "-i", "SPEECH", "-f", "lavfi", "-i",
        "sine=frequency=120:sample_rate=22050:duration=11",
        "-filter_complex",
        "[1]volume=-30dB[h];[0]volume=-20dB[s];"
        "[s][h]amix=inputs=2:duration=first:normalize=0[o]",
        "-map", "[o]", "-ar", "48000"],
    "hum3.wav": [
        "-i", "SPEECH", "-f", "lavfi", "-i",
        "sine=frequency=120:sample_rate=22050:duration=11",
        "-filter_complex",
        "[1]volume=-14dB[h];[0]volume=-20dB[s];"
        "[s][h]amix=inputs=2:duration=first:normalize=0[o]",
        "-map", "[o]", "-ar", "48000"],
}

# The five exact-length segments of `media/silence.mov`'s track (README.md's
# own recipe), audio only: quiet over exactly 2.000–3.500 s and 6.000–7.000 s.
TONE_GAPS = [(2.000, 3.500), (6.000, 7.000)]
# Where `tone.wav` is laid in `voicetone.wav` — the voice is padded to exactly
# this, so the two halves' arithmetic is a round number.
VOICE_LENGTH = 11.0


def fixture(name):
    return os.path.join(FIXTURES, name)


def make_fixtures():
    os.makedirs(FIXTURES, exist_ok=True)
    speech = fixture("speech.aiff")
    if REMAKE or not os.path.exists(speech):
        run(["say", "-o", speech, SPEECH_TEXT])
    for name, recipe in MIXES.items():
        if not REMAKE and os.path.exists(fixture(name)):
            continue
        run(["ffmpeg", "-y", "-v", "error"]
            + [speech if part == "SPEECH" else part for part in recipe]
            + [fixture(name)])
    if REMAKE or not os.path.exists(fixture("clean.wav")):
        run(["ffmpeg", "-y", "-v", "error", "-i", speech, "-ar", "48000",
             fixture("clean.wav")])
    if REMAKE or not os.path.exists(fixture("tone.wav")):
        run(["ffmpeg", "-y", "-v", "error",
             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2",
             "-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono:d=1.5",
             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=2.5",
             "-f", "lavfi", "-i", "anullsrc=r=48000:cl=mono:d=1",
             "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3",
             "-filter_complex", "[0:a][1:a][2:a][3:a][4:a]concat=n=5:v=0:a=1[a]",
             "-map", "[a]", "-c:a", "pcm_s16le", "-ac", "2", "-t", "10",
             fixture("tone.wav")])
    if REMAKE or not os.path.exists(fixture("voicetone.wav")):
        # The voice PADDED to exactly 11.000 s, so the tone's own gaps sit at
        # a round offset and nothing about the two halves' boundary depends on
        # how long `say` happened to talk for.
        padded = fixture("padded.wav")
        run(["ffmpeg", "-y", "-v", "error", "-i", fixture("clean.wav"),
             "-f", "lavfi", "-i", "anullsrc=r=48000:cl=stereo",
             "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1[c]", "-map", "[c]",
             "-t", str(VOICE_LENGTH), "-c:a", "pcm_s16le", "-ac", "2", padded])
        run(["ffmpeg", "-y", "-v", "error", "-i", padded, "-i", fixture("tone.wav"),
             "-filter_complex", "[0:a][1:a]concat=n=2:v=0:a=1[o]", "-map", "[o]",
             "-c:a", "pcm_s16le", "-ac", "2", fixture("voicetone.wav")])
    if REMAKE or not os.path.exists(fixture("corrupt.m4a")):
        # A file whose MIDDLE will not decode: the clean fixture as AAC with
        # bytes 45%–70% of the way through the container zeroed, leaving the
        # `moov` (and so the DURATION) intact. AVFoundation starts the read,
        # yields about two seconds and then gives up — the input the reader
        # review's R2·1 needed and could not get from a truncated WAV, whose
        # duration AVFoundation reads off the bytes that are actually there.
        aac = fixture("corrupt.m4a")
        run(["ffmpeg", "-y", "-v", "error", "-i", fixture("clean.wav"),
             "-c:a", "aac", "-b:a", "128k", aac])
        with open(aac, "rb") as handle:
            raw = bytearray(handle.read())
        for index in range(int(len(raw) * 0.45), int(len(raw) * 0.70)):
            raw[index] = 0
        with open(aac, "wb") as handle:
            handle.write(bytes(raw))
    if REMAKE or not os.path.exists(fixture("mute.mov")):
        run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi", "-i",
             "testsrc=size=320x180:rate=30:duration=2", "-pix_fmt", "yuv420p",
             "-c:v", "libx264", "-an", fixture("mute.mov")])


def duration_of(path):
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", path], check=True, capture_output=True, text=True)
    return float(out.stdout.strip())


# ---- PCM, phase 2's ------------------------------------------------------


def pcm(path):
    """`path` decoded to raw signed 16-bit LE stereo 48 kHz, as bytes —
    `phase2_proof.py`'s own line, so two scripts' sample comparisons mean the
    same thing. The `.pcm` lands beside the file, which is always under
    `work/`."""
    out = os.path.splitext(path)[0] + ".pcm"
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
         "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", out], check=True)
    with open(out, "rb") as handle:
        return handle.read()


def wobble(a, b):
    """(max |Δ|, count of differing samples) between two PCM dumps of the same
    length, or None when they are not."""
    if len(a) != len(b):
        return None
    if a == b:
        return (0, 0)
    first, second = array("h"), array("h")
    first.frombytes(a)
    second.frombytes(b)
    diffs = [abs(p - q) for p, q in zip(first, second) if p != q]
    return (max(diffs), len(diffs))


# ---- The reference walk --------------------------------------------------
#
# `SilenceDetector.detect` and `refine` in Python, over `MediaPeaks.window`'s
# arithmetic at the 32 ms grid. The three pieces that are easy to get wrong,
# and which a tick-exact comparison is here to hold:
#
#   * `sourceTick` divides the segment's own `sourceDuration` by its
#     `duration` — the rate the plan RESOLVED — and floors. It is not
#     `× speed`, and `sourceDuration != duration` off the frame grid.
#   * `bucketIndex` floors toward MINUS infinity, which matters only for the
#     reversed mirror, where a window can run past the media's start.
#   * the frame snap is directional (up for a start, down for an end) and it
#     happens AFTER the padding, which happens after the minimum length.

Segment = namedtuple("Segment", "start duration source_in source_duration")


def round_half_away(numer, denom):
    sign = -1 if (numer < 0) != (denom < 0) else 1
    n, d = abs(numer), abs(denom)
    return sign * ((2 * n + d) // (2 * d))


def nearest_frame(t, frame, fps=None):
    """`ReelTime.snapToFrame` — `frame_index` then `tick_at_frame`, each
    rounding half away from zero (`core/src/time.rs:145-176`).

    At 30 fps `frame` is 20 000 and at 100 fps 6 000; at 30000/1001 it is
    20 020. Every one of those is a WHOLE number of ticks, so the composition
    collapses to one rounding and `fps` may be left out. The recorder's
    24981/1000 is not: a frame there is 24018.25 ticks, the app's
    `Fps.frameDuration` truncates it to 24018, and the boundary has to be
    computed from the rate itself — which is what `fps` is for (§1e)."""
    if fps is not None:
        index = round_half_away(t * fps[0], SEC * fps[1])
        return round_half_away(index * SEC * fps[1], fps[0])
    return round_half_away(t, frame) * frame


def snap_up(t, frame, fps=None):
    """`SilenceDetector+Walls.snapUpToFrame`."""
    near = nearest_frame(t, frame, fps)
    return near if near >= t else nearest_frame(near + frame, frame, fps)


def snap_down(t, frame, fps=None):
    """`SilenceDetector+Walls.snapDownToFrame`."""
    near = nearest_frame(t, frame, fps)
    return near if near <= t else nearest_frame(near - frame, frame, fps)


def source_tick(seg, t):
    """`MediaPeaks.sourceTick` — double arithmetic, floored."""
    if seg.duration <= 0:
        return seg.source_in
    offset = float(t - seg.start) * float(seg.source_duration) / float(seg.duration)
    return seg.source_in + math.floor(offset)


def expected_spans(p, seg, confidence, min_length, padding, frame,
                   reversed_pivot=None, rule="max", fps=None):
    """The spans `detect` must answer for ONE segment over the probabilities
    `p`, in project ticks. `rule` is `max` — the shipped rule — or `mean`,
    which exists only for the sensitivity line claim 1(c) prints."""
    start = seg.start
    end = seg.start + seg.duration
    t = (start // BUCKET) * BUCKET
    run_start = None
    runs = []
    while t < end:
        slot_end = t + BUCKET
        first_tick, last_tick = max(t, start), min(slot_end, end)
        covered = last_tick > first_tick
        quiet = True
        if covered:
            first = source_tick(seg, first_tick)
            last = max(first, source_tick(seg, last_tick) - 1)
            if reversed_pivot is None:
                low, high = first, last
            else:
                low, high = reversed_pivot - last, reversed_pivot - first
            # Python's `//` floors, which IS `MediaPeaks.bucketIndex`, negative
            # branch included.
            lower = max(0, low // CHUNK)
            upper = min(len(p) - 1, high // CHUNK)
            if lower > upper:
                # Outside the file the cache was built from: `window` answers
                # nil and `speechMax` reads 0 (`MediaSpeech.swift`).
                value = 0.0
            else:
                window = p[lower:upper + 1]
                value = max(window) if rule == "max" else sum(window) / len(window)
            quiet = value < confidence
        if covered and quiet:
            if run_start is None:
                run_start = max(t, start)
        elif run_start is not None:
            runs.append((run_start, min(t, end)))
            run_start = None
        t = slot_end
    if run_start is not None and end > run_start:
        runs.append((run_start, end))

    out = []
    for begin, finish in runs:
        if finish - begin < min_length:
            continue
        low, high = begin + padding, finish - padding
        if high <= low:
            continue
        snapped = (snap_up(low, frame, fps), snap_down(high, frame, fps))
        if snapped[0] >= 0 and snapped[1] > snapped[0]:
            out.append(snapped)
    return out


# ---- One project ---------------------------------------------------------


class Session:
    """One project, `phase3_proof.py`'s shape.

    `<name>-<pid>.reelcut` under `work/`, older pids' swept: a `project` path
    is matched against every open document and no tool closes one, so two
    runs' saved packages would have the app answering for an old one. The
    package is written by `new_project` itself, which is what makes
    `cache/speech/<id>.bin` readable from here — and NOTHING here calls
    `save_project` after an import, because a save that lands while
    `generateCaches` is still writing can leave the package without the peaks
    half (seen once, on this binary: the detector then reports the media
    pending for ever)."""

    def __init__(self, mcp, name, fps=None):
        self.mcp = mcp
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)
        if fps is not None:
            # BEFORE any clip: `set_canvas` re-snaps clip times to the new
            # grid, and what claim 1(c) needs is a clip whose duration was
            # snapped at 100 fps in the first place.
            self.op("set_canvas", fps=list(fps))

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def op_with(self, name, arguments):
        return self.mcp.call_with(name, dict(arguments, project=self.path))

    def project(self):
        return self.op("get_project")["project"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def frame(self):
        rate = self.project()["canvas"]["fps"]
        return SEC * rate[1] // rate[0]

    def lay(self, name, at=0, track=None):
        """A fixture imported and laid at `at` on a track. Answers (media, clip)."""
        media = self.op("import_media", path=fixture(name))["media"]
        if track is None:
            track = self.project()["tracks"][0]["id"]
        clip = self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]
        return media, clip

    def probabilities(self, media):
        """The floats the app itself wrote — `cache/speech/<id>.bin`, one
        32-bit LE float per chunk. Read off the package, never recomputed."""
        path = os.path.join(self.path, "cache", "speech", f"{media}.bin")
        with open(path, "rb") as handle:
            raw = handle.read()
        return list(struct.unpack(f"<{len(raw) // 4}f", raw))

    def segment(self, clip, media):
        """The clip as `evaluate.rs` resolves it: `source_duration` is the
        clip's duration times its speed, CLAMPED to what the file has left
        after the in point (`evaluate.rs`'s `segment_of`). The product is
        rounded half AWAY from zero as `evaluate.rs` does it, not Python's
        half-to-even, so a speed whose product lands on `.5` cannot put the
        walk one tick off the app."""
        project = self.project()
        c = {x["id"]: x for x in project["clips"]}[clip]
        m = {x["id"]: x for x in project["media"]}[media]
        source_in = c["source"]["in"]
        product = math.floor(c["duration"] * c["speed"] + 0.5)
        length = min(product, m["duration"] - source_in)
        return Segment(c["start"], c["duration"], source_in, max(1, length))

    def media_duration(self, media):
        return {x["id"]: x for x in self.project()["media"]}[media]["duration"]


def detect(session, **settings):
    """`detect_silence`, waiting out BOTH caches.

    `pending_peaks` is the union of the two waiters (`AgentServer+Silence`), so
    one poll covers the waveform and the model alike: a run against a
    just-imported file that did not wait would be measuring the cache rather
    than the recording. Phase 3's loop, with a longer cap because a Silero
    pass over a ten-second file is not instant on a cold model."""
    for _ in range(120):
        answer = session.op("detect_silence", **settings)
        if "pending_peaks" not in answer:
            return answer
        time.sleep(0.5)
    raise RuntimeError(f"the caches never landed for {settings}")


def spans(answer):
    return [tuple(span) for span in answer["ranges"]]


def nth(found, index):
    """The index-th span, or None. Every per-pause row is written over the
    TRUTH's two pauses rather than zipped against what was found, so a build
    that finds nothing still scores the same number of rows and a mutant's
    score is comparable with the tree's."""
    return found[index] if index < len(found) else None


def off(ticks):
    return "none" if ticks is None else round(seconds(ticks), 4)


def inside(span, pause, overrun):
    """Whether a proposed span sits inside a truth pause: the START never
    early, the END allowed to overrun by `overrun` seconds — deviation (i)."""
    return (span[0] >= pause[0]
            and span[0] - pause[0] <= ticks_of(START_LAG)
            and span[1] >= pause[0]
            and span[1] - pause[1] <= ticks_of(overrun))


# ---- 1. The clean fixture ------------------------------------------------


def clean_part(mcp):
    """§4g claim 1, in three rows.

    (a) the voice answer IS the reference walk over the app's own cache, tick
    for tick — the strongest form of the claim, and the one that holds the
    step rule, the source-tick arithmetic and the snap order at once;
    (b) it sits inside the truth, late at the start and no further past the
    end than `OVERRUN` — §4g's "edges inward", with deviation (i);
    (c) the same at a 100 fps canvas, where one frame IS one bucket and the
    snap can absorb nothing, which is the row the max-over-a-step rule is
    scored on;
    (d) and the clean clip once more at ×2, the one row in the suite where
    the segment's `source_duration` and `duration` DIFFER.
    """
    print("\n1 — the clean fixture, voice against the truth and against the walk")
    s = Session(mcp, "silence2-clean")
    media, clip = s.lay("clean.wav")
    answer = detect(s)
    check(s.frame() == 20_000, f"the project is 30 fps (a frame is {s.frame()} ticks)")
    check(
        answer["mode"] == "voice" and answer["voice_confidence"] == 0.5,
        f"voice is the default mode at confidence {answer['voice_confidence']} "
        f"(got {answer['mode']})")

    truth = spans(detect(s, mode="level", threshold_db=-40, padding=0))
    check(
        len(truth) == 2,
        f"the truth — the −40 dBFS level run over the file's DIGITAL silence, "
        f"measured on this run's own `say` output: {show(truth)}")
    if len(truth) != 2:
        raise RuntimeError("the clean fixture did not render two pauses")
    words = []
    clip_span = (0, s.clip(clip)["duration"])
    edge = clip_span[0]
    for pause in truth:
        words.append((edge, pause[0]))
        edge = pause[1]
    words.append((edge, clip_span[1]))
    note(f"the three word runs between them: {show(words)}")

    p = s.probabilities(media)
    segment = s.segment(clip, media)
    check(
        len(p) > 0 and segment.source_duration == segment.duration,
        f"{len(p)} probabilities on disk, over a clip whose duration "
        f"({segment.duration}) is the media length snapped DOWN and whose "
        f"source range is {segment.source_duration} — the two AGREE for a "
        f"whole-file clip, so the plan plays it at rate 1 (spec §11); the walk "
        f"is given both because a clip at another SPEED still differs — 1(d)")

    walked = expected_spans(
        p, segment, answer["voice_confidence"], answer["min_length"],
        answer["padding"], s.frame())
    check(
        spans(answer) == walked,
        f"1a the default voice answer IS the reference walk over the app's own "
        f"cache, tick for tick: {spans(answer)} vs {walked}")

    bare = detect(s, padding=0)
    walked_bare = expected_spans(
        p, segment, bare["voice_confidence"], bare["min_length"], 0, s.frame())
    check(
        spans(bare) == walked_bare,
        f"1a and so is the answer with no padding: {spans(bare)} vs {walked_bare}")

    check(
        len(spans(bare)) == 2,
        f"1b voice finds both pauses and only those: {show(spans(bare))}")
    for index, pause in enumerate(truth):
        span = nth(spans(bare), index)
        late = None if span is None else span[0] - pause[0]
        over = None if span is None else span[1] - pause[1]
        check(
            late is not None and 0 <= late <= ticks_of(START_LAG),
            f"1b the {round(seconds(pause[0]), 2)} s pause's start lands LATE and "
            f"by at most {START_LAG} s — {off(late)} s (the sign is "
            f"the claim: a start never lands early)")
        check(
            over is not None and -ticks_of(START_LAG) <= over <= ticks_of(OVERRUN["clean"]),
            f"1b and its end within [−{START_LAG}, +{OVERRUN['clean']}] s of the "
            f"truth — {off(over)} s (deviation (i): the sign is not "
            f"asserted at the end)")

    # (c) 100 fps: a frame is 6 000 ticks, exactly one bucket, so `refine`'s
    # snap can move an edge by less than the detector's own resolution and the
    # answer is the walk with nothing absorbed.
    hundred = Session(mcp, "silence2-clean-100", fps=(100, 1))
    media100, clip100 = hundred.lay("clean.wav")
    fast = detect(hundred)
    check(hundred.frame() == BUCKET,
          f"1c the second project is 100 fps, one frame per bucket "
          f"({hundred.frame()} ticks)")
    p100 = hundred.probabilities(media100)
    segment100 = hundred.segment(clip100, media100)
    walked100 = expected_spans(
        p100, segment100, fast["voice_confidence"], fast["min_length"],
        fast["padding"], BUCKET)
    check(
        spans(fast) == walked100,
        f"1c at 100 fps the voice answer is the walk tick for tick: "
        f"{spans(fast)} vs {walked100}")

    # The sensitivity line — PRINTED, never scored. It is what says whether
    # the max→mean mutant can be seen on THIS host's fixture at all.
    mean100 = expected_spans(
        p100, segment100, fast["voice_confidence"], fast["min_length"],
        fast["padding"], BUCKET, rule="mean")
    moved = sum(1 for a, b in zip(walked100, mean100) for x, y in zip(a, b) if x != y)
    note(
        f"sensitivity: the MEAN rule over a step answers {mean100} where the max "
        f"rule answers {walked100} — "
        + (f"{moved} edge(s) move at 100 fps" if mean100 != walked100
           else "IDENTICAL on this host's fixture"))

    # (d) the scale factor `sourceTick` divides by, exercised. Every row above
    # walks a whole-file clip at rate 1, where the plan resolves
    # `source_duration == duration` and that factor is an IDENTITY a mutant
    # could drop unseen. A trim cannot break the equality — at rate 1 the plan
    # resolves `min(duration, media.duration − in)`, which a shorter window
    # only makes smaller — so this row changes the clip's SPEED instead, which
    # is what the factor is made of. At ×2 the segment is EXACTLY twice the
    # duration: `set_speed` snaps the duration and then holds it to what the
    # file still holds at the new rate (spec §11, D4-3), where it used to
    # write a nearest-snapped 3 120 000 whose 6 240 000 ticks of source
    # overran the file and came back clamped at a ratio of 1.99795. So the
    # ratio is asserted exactly here, and a walk that used `× speed` in place
    # of the plan's own ratio is now EQUIVALENT rather than sharp — what
    # stays sharp is the factor itself (a dropped `sourceTick` factor moves
    # these ticks) and the spans against the walk. The session is left at ×2
    # and handed on to `refusal_part`, which asserts argument sentences only.
    s.op("set_speed", clip=clip, rate=2)
    sped = s.segment(clip, media)
    twice = detect(s, padding=0)
    walked_sped = expected_spans(
        p, sped, twice["voice_confidence"], twice["min_length"], 0, s.frame())
    check(
        sped.source_duration == 2 * sped.duration and spans(twice) == walked_sped,
        f"1d at ×2 the segment's source range ({sped.source_duration}) is EXACTLY "
        f"twice its duration ({sped.duration}), and the voice answer is still the "
        f"walk over that segment tick for tick: {spans(twice)} vs "
        f"{walked_sped}")
    return s, truth, spans(answer), spans(bare)


# ---- 1e. The recorder's own rate -----------------------------------------


def offgrid_part(mcp):
    """The reader review's R4·2 (`archive/reelcut-roadmap-4.md` §8).

    Every other walked row in this file is at 30 or 100 fps, and 30000/1001
    would be no different: all three put a frame on a WHOLE number of ticks.
    `ScreenRecorder` mints **24981/1000**, where a frame is 24018.25 ticks —
    `Fps.frameDuration` truncates it to 24018 and `snapUpToFrame` /
    `snapDownToFrame` compose the nearest snap with that truncated step, which
    nothing in the suite reached. The row walks the rate itself."""
    print("\n1e — the clean fixture at the recorder's own 24981/1000")
    rate = (24981, 1000)
    s = Session(mcp, "silence2-offgrid", fps=rate)
    media, clip = s.lay("clean.wav")
    answer = detect(s)
    frame = SEC * rate[1] // rate[0]
    check(
        s.frame() == frame == 24_018,
        f"a frame at {rate[0]}/{rate[1]} is {SEC * rate[1] / rate[0]:.2f} ticks and the "
        f"step the snaps take is the truncated {s.frame()}")
    walked = expected_spans(
        s.probabilities(media), s.segment(clip, media), answer["voice_confidence"],
        answer["min_length"], answer["padding"], frame, fps=rate)
    check(
        spans(answer) == walked,
        f"the voice answer is the walk over that RATIONAL grid tick for tick: "
        f"{spans(answer)} vs {walked}")
    check(
        all(
            nearest_frame(edge, frame, rate) == edge
            for span in spans(answer) for edge in span),
        f"and every bound it answers is a real boundary of a grid whose frames "
        f"are 24018 and 24019 ticks apart by turns: {spans(answer)}")


# ---- 2. hum3.wav, the headline ------------------------------------------


def hum3_part(mcp, truth, clean_bare):
    """The fixture the shipped rule is BLIND to: a −32 dBFS hum under the
    speech, which never drops under −40, so level mode answers nothing at all
    and voice mode answers both pauses on the same bounds it found in the
    clean file."""
    print("\n2 — hum3.wav: the level rule is blind, the voice rule is not")
    s = Session(mcp, "silence2-hum3")
    media, clip = s.lay("hum3.wav")
    level = detect(s, mode="level")
    check(
        spans(level) == [],
        f"level at −40 dBFS finds NOTHING under the hum: {show(spans(level))}")
    voice = spans(detect(s, padding=0))
    check(len(voice) == 2, f"voice finds both pauses: {show(voice)}")
    for index, pause in enumerate(truth):
        span = nth(voice, index)
        check(
            span is not None and inside(span, pause, OVERRUN["hum3"]),
            f"{show([span])[0] if span else 'nothing'} sits inside the "
            f"{show([pause])[0]} pause (start late by "
            f"{off(None if span is None else span[0] - pause[0])} s, end past it by "
            f"{off(None if span is None else span[1] - pause[1])} s ≤ {OVERRUN['hum3']})")
    for index in range(len(truth)):
        span, clean = nth(voice, index), nth(clean_bare, index)
        drift = (None if span is None or clean is None
                 else max(abs(span[0] - clean[0]), abs(span[1] - clean[1])))
        check(
            drift is not None and drift <= ticks_of(0.10),
            f"and within 0.10 s of the clean file's own bounds "
            f"{show([clean])[0] if clean else 'nothing'} — off by {off(drift)} s")


# ---- 3. quiet2.wav, where level cuts into a word -------------------------


def quiet2_part(mcp, truth):
    """−35 dB speech over pink noise. Level mode chops it into pieces, some of
    them inside WORDS; voice mode answers the two pauses. §4g's "six" is a
    property of this noise and is printed (deviation (ii)), as is the lead-in
    span q6 recorded and §5 keeps as a limit (deviation (ii) too)."""
    print("\n3 — quiet2.wav: level cuts into a word, voice does not")
    s = Session(mcp, "silence2-quiet2")
    media, clip = s.lay("quiet2.wav")
    level = spans(detect(s, mode="level", padding=0))
    voice = spans(detect(s, padding=0))
    note(f"level answers {len(level)} ranges (§4g said six): {show(level)}")
    check(
        len(level) > len(voice),
        f"level answers MORE ranges than voice ({len(level)} > {len(voice)})")
    strays = [r for r in level
              if all(r[1] <= pause[0] or r[0] >= pause[1] for pause in truth)]
    check(
        strays != [],
        f"and at least one of them lies wholly OUTSIDE both real pauses — a cut "
        f"into a word: {show(strays)}")

    lead_in = [r for r in voice if r[1] <= truth[0][0]]
    scored = [r for r in voice if r not in lead_in]
    note(
        f"voice answers a lead-in span {show(lead_in)} as well — q6's soft first "
        f"word missed at this SNR, §5's recorded limit, printed and not scored")
    check(
        len(scored) == 2,
        f"voice answers both pauses and nothing else inside the speech: "
        f"{show(scored)}")
    for index, pause in enumerate(truth):
        span = nth(scored, index)
        check(
            span is not None and inside(span, pause, OVERRUN["quiet2"]),
            f"{show([span])[0] if span else 'nothing'} sits inside the "
            f"{show([pause])[0]} pause (end past it by "
            f"{off(None if span is None else span[1] - pause[1])} s ≤ "
            f"{OVERRUN['quiet2']})")


# ---- 4. A tone, and the per-voice fallback -------------------------------


def tone_part(mcp, truth):
    """The fallback: a voice whose source window holds no voice ANYWHERE is
    judged by level for its whole span, which is what makes phase 3's own
    fixtures answer what they always did (claim 5 runs them).

    The two-clip variant is the one that shows the fallback's KEY. A file that
    is voice-then-tone, split in two, must have its tone clip judged by level
    and its VOICE clip judged by the MODEL, so the voice half is SCORED here
    against the reference walk over clip A's own segment. Only the spans
    ending strictly before the split are compared, on both sides: the voice
    clip ends in a quiet run of its own, and a build that judges the tone clip
    by voice merges that run past the split into one span the walk over clip A
    alone cannot answer. The two real pauses are what the row is about."""
    print("\n4 — a tone answers the same in both modes, through the fallback")
    s = Session(mcp, "silence2-tone")
    media, clip = s.lay("tone.wav")
    voice = detect(s)
    level = detect(s, mode="level")
    check(
        spans(voice) == spans(level) and voice["removes"] == level["removes"],
        f"voice and level answer the SAME ranges and the same total "
        f"({show(spans(voice))}, {voice['removes']} ticks)")
    check(
        voice["judged_by_level"] == [media],
        f"and the tone media is named in judged_by_level: "
        f"{voice['judged_by_level']} (media {media})")
    padding = voice["padding"]
    want = [(ticks_of(a) + padding, ticks_of(b) - padding) for a, b in TONE_GAPS]
    check(
        len(spans(voice)) == 2
        and all(max(abs(g[0] - w[0]), abs(g[1] - w[1])) <= BUCKET
                for g, w in zip(spans(voice), want)),
        f"and they are the fixture's own gaps within one bucket: {show(spans(voice))} "
        f"vs {show(want)}")

    print("\n4 — voice THEN tone, split into two clips")
    two = Session(mcp, "silence2-voicetone")
    media2, clip2 = two.lay("voicetone.wav")
    two.op("split", at=ticks_of(VOICE_LENGTH))
    laid = sorted(
        ((c["start"], c["duration"], c["id"]) for c in two.project()["clips"]))
    check(
        len(laid) == 2 and laid[1][0] == ticks_of(VOICE_LENGTH),
        f"the fixture: two clips of one file, cut at {VOICE_LENGTH} s — {laid}")
    answer = detect(two, padding=0)
    padding_default = detect(two)["padding"]
    found = spans(answer)
    tail = [r for r in found if r[0] >= ticks_of(VOICE_LENGTH)]
    head = [r for r in found if r[1] <= ticks_of(VOICE_LENGTH)]
    want_tail = [(ticks_of(VOICE_LENGTH + a), ticks_of(VOICE_LENGTH + b))
                 for a, b in TONE_GAPS]
    check(
        len(tail) == 2,
        f"inside the tone clip the answer is the tone's TWO gaps, never one span "
        f"covering the clip: {show(tail)}")
    check(
        len(tail) == 2
        and all(max(abs(g[0] - w[0]), abs(g[1] - w[1])) <= BUCKET
                for g, w in zip(tail, want_tail)),
        f"and they land where the tone's gaps are: {show(tail)} vs {show(want_tail)}")
    check(
        answer["judged_by_level"] == [media2],
        f"the media is named in judged_by_level: {answer['judged_by_level']}")
    present = [r for r in head
               if any(inside(r, pause, OVERRUN["clean"]) for pause in truth)]
    check(
        len(present) == 2,
        f"and inside the VOICE clip both real pauses are still proposed: "
        f"{show(present)} of {show(head)}")
    V = ticks_of(VOICE_LENGTH)
    p2 = two.probabilities(media2)
    seg_A = two.segment(laid[0][2], media2)
    walk_A = expected_spans(
        p2, seg_A, answer["voice_confidence"], answer["min_length"],
        answer["padding"], two.frame())
    check(
        [r for r in found if r[1] < V] == [r for r in walk_A if r[1] < V],
        f"and the VOICE clip is judged by the MODEL, tick for tick against the "
        f"walk over its own segment: {show([r for r in found if r[1] < V])} vs "
        f"{show([r for r in walk_A if r[1] < V])}")
    by_level = [r for r in spans(detect(two, mode="level", padding=0)) if r[1] < V]
    note(
        f"level mode over the same two clips answers "
        f"{show(by_level)} before the split — "
        f"{'the same as' if by_level == [r for r in walk_A if r[1] < V] else 'DIFFERENT from'} "
        f"the model's walk, which is the row's power on this host. "
        f"(default padding here would be {padding_default} ticks)")

    # The second sceptic pass's item 5, on the TONE session above rather than
    # a new document: the `waveformOnly` clause of the pending note said
    # "spans inside them ARE proposed here" without ever intersecting
    # `proposedMedia` — the mirror image of the defect the review's finding 2
    # fixed. A media judged BY LEVEL is exactly the one that clause is about,
    # and with its waveform gone NOTHING inside it is proposed; duck the clip
    # and the FLOOR proposes its span with the same waveform still missing.
    print("\n4 — the waveform withheld over a media that is judged by level")
    os.remove(os.path.join(s.path, "cache", "peaks", f"{media}.bin"))
    withheld = s.op("detect_silence")
    check(
        spans(withheld) == []
        and withheld.get("pending_peaks") == [media]
        and "voice_pending" not in withheld
        and withheld.get("judged_by_level") == [media],
        f"with its waveform gone the tone media is a WAVEFORM waiter judged by "
        f"level, and nothing inside it is proposed: {show(spans(withheld))}, "
        f"pending_peaks {withheld.get('pending_peaks')}, voice_pending "
        f"{withheld.get('voice_pending')}, judged_by_level "
        f"{withheld.get('judged_by_level')}")
    check(
        (withheld.get("note") or "") == (
            "Analysis is still running for 1 media file(s); call again in a moment. "
            "For that file it is the WAVEFORM that has not landed, which in voice mode "
            "decides only a clip holding no voice, and nothing inside them is proposed "
            "here. 1 media file(s) hold no voice in at least one clip and were judged "
            "by level there."),
        f"and the clause says so in the whole sentence, rather than claiming spans "
        f"that are not there: {withheld.get('note')!r}")
    s.op("set_audio", clips=[clip], patch={"volume": 0.001})
    ducked = s.op("detect_silence")
    check(
        spans(ducked) != [],
        f"ducked to 0.001 with the SAME waveform missing, the floor proposes its "
        f"span: {show(spans(ducked))}")
    check(
        (ducked.get("note") or "") == (
            "Analysis is still running for 1 media file(s); call again in a moment. "
            "For that file it is the WAVEFORM that has not landed, which in voice mode "
            "decides only a clip holding no voice, so spans inside them ARE proposed "
            "here. A clip there that holds no voice is proposed only where the mix "
            "already turns it down far enough to be quiet. 1 media file(s) hold no "
            "voice in at least one clip and were judged by level there."),
        f"and the clause turns over to the proposed wording, with the mix named as "
        f"what made it quiet: {ducked.get('note')!r}")
    # NOTHING BELOW THIS in `tone_part`: the two rows above changed the
    # session in place (the peaks file removed, then the clip ducked), so a
    # row appended here would inherit that state. A new row takes its own
    # `Session`.


# ---- 6. The scope rule, in voice mode ------------------------------------


def scope_part(mcp, clean_default):
    """`phase3_silence_scope.py`'s fixture — two tracks of one recording, the
    front one muted — asked in VOICE mode. The rule it proves is the one that
    keeps `ripple_delete_ranges` from taking an audible voiceover away with a
    muted music bed, and the gain FLOOR that runs before the model is what
    has to keep it true here."""
    print("\n6 — a silenced clip proposes nothing in voice mode either")
    s = Session(mcp, "silence2-scope")
    media, voice_clip = s.lay("clean.wav")
    before = {t["id"] for t in s.project()["tracks"]}
    s.op_with("add_track", {"name": "Music"})
    front = next(t["id"] for t in s.project()["tracks"] if t["id"] not in before)
    music = s.op("add_clip", track=front, media=media, at=0)["new_clips"][0]
    s.op("set_track", track=front, muted=True)

    silenced = detect(s, clips=[music])
    check(
        spans(silenced) == [] and silenced["clips"] == [],
        f"the MUTED clip proposes no cut and nothing was analysed: "
        f"{silenced['ranges']}, clips {silenced['clips']}")
    s.op("set_selection", clips=[music])
    opened = detect(s)
    check(
        opened["scope"] == "audible",
        f"with only the muted clip selected the default scope is audible "
        f"(got {opened['scope']})")
    check(
        spans(opened) == clean_default,
        f"and the audible track answers exactly what the one-clip project did: "
        f"{show(spans(opened))}")

    # The other way a mix silences a clip: unmute the front and SOLO the back.
    s.op("set_track", track=front, muted=False)
    back = next(t["id"] for t in s.project()["tracks"] if t["id"] in before)
    s.op("set_track", track=back, solo=True)
    soloed = detect(s)
    check(
        spans(soloed) == clean_default,
        f"and a solo on the other track leaves the same answer: "
        f"{show(spans(soloed))}")
    check(
        spans(detect(s, clips=[music])) == [],
        f"while the solo-silenced clip proposes nothing on its own")


# ---- 7. A nest is still a wall ------------------------------------------


def nest_part(mcp, clean_default):
    """Phase 3's nest fixture, asked in voice mode. `Source::Nest` has no in
    point, so splitting a nest clip strands the rest of it — the wall is
    subtracted before the minimum length and must survive the model."""
    print("\n7 — a nest is a wall in voice mode too")
    s = Session(mcp, "silence2-nest")
    media, plain = s.lay("clean.wav")
    length = s.clip(plain)["duration"]
    inner = s.op("add_clip", track=s.project()["tracks"][0]["id"], media=media,
                 at=length)["new_clips"][0]
    s.op("nest", clips=[inner])
    nests = [c for c in s.project()["clips"] if c["source"]["kind"] == "nest"]
    check(
        len(nests) == 1 and nests[0]["start"] == length,
        f"the fixture: one clip on the timeline and a second nested at {length} "
        f"({[(c['start'], c['duration']) for c in nests]})")
    nest = nests[0]
    start, end = nest["start"], nest["start"] + nest["duration"]
    found = spans(detect(s))
    reaching = [r for r in found if r[1] > start and r[0] < end]
    check(
        not reaching,
        f"no proposed span reaches into the nest [{start}, {end}): "
        f"{show(reaching) or 'none'} of {show(found)}")
    check(
        [r for r in found if r[1] <= start] == clean_default,
        f"and the identical dead air in FRONT of it is still found, unchanged: "
        f"{show([r for r in found if r[1] <= start])}")


# ---- 8. A speech cache withheld -----------------------------------------


def withheld_part(mcp, truth):
    """The cache deleted under the detector's nose. A media whose
    probabilities have not landed is NEVER quiet — proposing to delete a whole
    clip because a cache was late is the one failure this feature must not
    have — and it is named in `voice_pending` so a caller knows to wait."""
    print("\n8 — a media whose speech cache is missing is never quiet")
    s = Session(mcp, "silence2-withheld")
    media, clip = s.lay("clean.wav")
    detect(s)
    binary = os.path.join(s.path, "cache", "speech", f"{media}.bin")
    marker = os.path.join(s.path, "cache", "speech", f"{media}.complete.json")
    os.remove(binary)
    check(
        os.path.exists(marker) and not os.path.exists(binary),
        "the `.bin` is deleted and its marker left behind")
    # NOT `detect`: this is the state `detect` is written to wait out.
    pending = s.op("detect_silence")
    check(
        pending.get("voice_pending") == [media]
        and media in pending.get("pending_peaks", []),
        f"voice mode names the media in voice_pending and folds it into "
        f"pending_peaks: {pending.get('voice_pending')}, "
        f"{pending.get('pending_peaks')}")
    check(
        spans(pending) == [],
        f"and proposes NOTHING inside it: {pending['ranges']}")
    check(
        spans(detect(s, mode="level", threshold_db=-40, padding=0)) == truth,
        "while level mode still answers the truth, the cache being none of its "
        "business")

    fresh = os.path.join(WORK, f"silence2-relink-{os.getpid()}.wav")
    shutil.copy(fixture("clean.wav"), fresh)
    s.op("relink_media", media=media, path=fresh)
    answer = None
    for _ in range(120):
        answer = s.op("detect_silence")
        if "voice_pending" not in answer and "pending_peaks" not in answer:
            break
        time.sleep(0.5)
    check(
        answer is not None and "voice_pending" not in answer,
        f"a relink to a fresh copy rebuilds the cache and the media leaves "
        f"voice_pending: {answer.get('voice_pending')}")
    check(
        spans(answer) != [],
        f"and the answer comes back: {show(spans(answer))}")


# ---- 9. A reversed clip's pauses mirror ---------------------------------


def reversed_part(mcp):
    """The only peaks and speech files that exist are of the FORWARD file, so
    a reversed clip's window is mirrored about the MEDIA's duration —
    `MediaPeaks.reversedPivot`, the media's length and not the clip's. The
    walk is given the same pivot and the row is tick-exact against it."""
    print("\n9 — a reversed clip is measured against the mirrored window")
    s = Session(mcp, "silence2-reversed")
    media, clip = s.lay("clean.wav")
    forward = spans(detect(s))
    s.op("set_reversed", clip=clip, reversed=True)
    answer = detect(s)
    pivot = s.media_duration(media)
    segment = s.segment(clip, media)
    walked = expected_spans(
        s.probabilities(media), segment, answer["voice_confidence"],
        answer["min_length"], answer["padding"], s.frame(), reversed_pivot=pivot)
    check(
        spans(answer) == walked,
        f"the reversed answer is the mirrored walk about the MEDIA's duration "
        f"({pivot}) tick for tick: {spans(answer)} vs {walked}")
    check(
        spans(answer) != forward,
        f"and it is not the forward answer: {show(spans(answer))} vs "
        f"{show(forward)}")


# ---- 10. The refusals ---------------------------------------------------


def refusal_part(session):
    """Four rules of the tool's own and one of the argument GATE's, each by
    its exact sentence.

    The last of the four is the reader review's finding 1
    (`archive/reelcut-roadmap-4.md` §8): the two durations stopped going
    through `optionalTimeArg` — rightly, it snapped them — and went through
    `intArg`, which has no CEILING, so `padding: Int64.max` reached
    `refine`'s `run.start + settings.padding` and killed the app rather than
    answering. Measured on the pre-fix binary before the fix went in:
    `Remote end closed connection without response`, crash report
    `Reelcut-2026-09-20-051240.ips`, `EXC_BREAKPOINT` / "Swift runtime
    failure: arithmetic overflow" inside `SilenceDetector.refine`. This row
    asks for a refusal and a live socket."""
    print("\n10 — the voice arguments' refusals, word for word")
    wanted = [
        (dict(voice_confidence=0.5, mode="level"),
         'voice_confidence only applies in mode: "voice".'),
        (dict(voice_confidence=0.95),
         "voice_confidence must be a number in 0.1…0.9."),
        (dict(mode="voise"), 'mode must be "voice" or "level".'),
        (dict(padding=9223372036854775807),
         "padding must be a length in ticks (600000 per second) from 0 to "
         "9000000000000000."),
        # The second sceptic pass's item 2: the ceiling was scored for
        # `padding` alone, so a build that kept the guard on one duration and
        # dropped it on the other still scored full. Both ends of both
        # arguments now have a row.
        (dict(min_length=9000000000000001),
         "min_length must be a length in ticks (600000 per second) from 0 to "
         "9000000000000000."),
        (dict(min_length=-1),
         "min_length must be a length in ticks (600000 per second) from 0 to "
         "9000000000000000."),
        (dict(padding=-1),
         "padding must be a length in ticks (600000 per second) from 0 to "
         "9000000000000000."),
    ]
    for arguments, sentence in wanted:
        try:
            session.op("detect_silence", **arguments)
            check(False, f"{arguments} is refused — it was NOT")
        except ToolError as error:
            check(
                str(error) == f"detect_silence: {sentence}",
                f"{arguments} is refused in the rule's own sentence: {str(error)!r}")
    try:
        session.op("detect_silence", voice_confidance=0.5)
        check(False, "a misspelt argument is refused by the gate — it was NOT")
    except ToolError as error:
        check(
            "does not take voice_confidance" in str(error),
            f"and a STRANGER key is refused by name before the handler runs: "
            f"{str(error)!r}")
    # And the bound is PUBLISHED, not only enforced: the gate reads names
    # alone, so a caller that never sends a bad number learns the ceiling
    # from `tools/list` or from nowhere (the second sceptic pass, item 4).
    published = (session.mcp.schemas()["detect_silence"]["inputSchema"]
                 .get("properties", {}))
    check(
        all(published.get(key, {}).get("minimum") == 0
            and published.get(key, {}).get("maximum") == 9000000000000000
            for key in ("min_length", "padding")),
        f"and detect_silence PUBLISHES that ceiling on both durations: "
        f"min_length {published.get('min_length', {}).get('minimum')}…"
        f"{published.get('min_length', {}).get('maximum')}, "
        f"padding {published.get('padding', {}).get('minimum')}…"
        f"{published.get('padding', {}).get('maximum')}")


# ---- 8b. A decode that stops part way ------------------------------------


def partial_part(mcp):
    """The reader review's R2·1 (`archive/reelcut-roadmap-4.md` §8).

    `writeSpeech`'s loop ends on a nil sample buffer, and a nil buffer means
    the track ran out OR the decode gave up. The second leaves the rest of the
    zero-filled buffer at ZERO, and a zero probability is "nobody is talking",
    so the pass used to write a `.bin` for a file it had only half read and
    then CERTIFY it with a marker — and voice mode proposed cutting the whole
    undecodable tail (measured: 8.3 s of this 10.4 s fixture, the reader
    stopping at 2.05 s). `reader.status` is now read BEFORE the cancel and
    anything but `.completed` writes nothing, which is §4a's own posture for a
    reader that will not build or start: no `.bin`, no marker, the media
    `voice_pending` and never quiet, retried on the next open.

    The peaks pass now makes the same completion decision for level mode.
    This app check observes pending status; `peaks_probe.py` awaits the
    actual importer pass before asserting that neither file was published."""
    print("\n8b — a media whose decode stops part way is never certified")
    s = Session(mcp, "silence2-partial")
    media, _ = s.lay("corrupt.m4a")
    speech = os.path.join(s.path, "cache", "speech", f"{media}.bin")
    marker = os.path.join(s.path, "cache", "speech", f"{media}.complete.json")
    peaks = os.path.join(s.path, "cache", "peaks", f"{media}.bin")
    note(f"the fixture is {duration_of(fixture('corrupt.m4a')):.3f} s")
    check(
        not os.path.exists(speech) and not os.path.exists(marker),
        f"no speech `.bin` and no marker are written for it "
        f"(bin {os.path.exists(speech)}, marker {os.path.exists(marker)})")
    answer = s.op("detect_silence")
    check(
        answer.get("voice_pending") == [media],
        f"voice mode names it as pending rather than counting it silent: "
        f"{answer.get('voice_pending')}")
    check(
        spans(answer) == [],
        f"and proposes NOTHING inside it: {show(spans(answer))}")
    level_answer = s.op("detect_silence", mode="level")
    level = spans(level_answer)
    check(
        level_answer.get("pending_peaks") == [media] and level == []
        and not os.path.exists(peaks)
        and not os.path.exists(os.path.join(s.path, "cache", "peaks", f"{media}.complete.json")),
        f"level names undecoded audio as pending and proposes no tail: "
        f"{level_answer.get('pending_peaks')}, {show(level)}")


# ---- 8c. The waveform withheld, the voice cache in place ------------------


def waveform_part(mcp, truth):
    """The reader review's R3·1 (`archive/reelcut-roadmap-4.md` §8).

    Claim 8 withholds the SPEECH cache. This withholds the WAVEFORM and keeps
    the speech, which is the case the note got wrong: `pending_peaks` folds
    both waiters (K21), and the sentence beside it said "Nothing inside them
    is proposed for removal" — about media whose spans were in the very same
    reply, because in voice mode the model has landed and the waveform decides
    only a clip holding no voice. The promise is made now about what the
    ANSWER shows: a waiter the reply already proposes a span inside is
    dropped from it and counted in its own clause, whichever cache is late
    and whichever mode ran (finding 2, the ducked rows at the foot)."""
    print("\n8c — the waveform withheld with the voice cache in place")
    s = Session(mcp, "silence2-nopeaks")
    media, _ = s.lay("clean.wav")
    before = spans(detect(s))
    os.remove(os.path.join(s.path, "cache", "peaks", f"{media}.bin"))
    answer = s.op("detect_silence")
    check(
        spans(answer) == before and before != [],
        f"voice mode answers exactly what it did with the waveform on disk: "
        f"{show(spans(answer))}")
    check(
        answer.get("pending_peaks") == [media] and "voice_pending" not in answer,
        f"the media is a WAVEFORM waiter and not a voice one: "
        f"{answer.get('pending_peaks')}, {answer.get('voice_pending')}")
    check(
        (answer.get("note") or "") == (
            "Analysis is still running for 1 media file(s); call again in a moment. "
            "For that file it is the WAVEFORM that has not landed, which in voice mode "
            "decides only a clip holding no voice, so spans inside them ARE proposed here."),
        f"and the note says those spans are proposed rather than denying them, in the "
        f"whole sentence — no clause about \"the rest\" of one that was not printed: "
        f"{answer.get('note')!r}")
    level = s.op("detect_silence", mode="level")
    check(
        spans(level) == []
        and (level.get("note") or "") == (
            "Analysis is still running for 1 media file(s); call again in a moment. "
            "Nothing inside them is proposed for removal."),
        f"while LEVEL proposes nothing inside it and keeps the promise, which is "
        f"where it holds: {show(spans(level))}, {level.get('note')!r}")
    note(f"the truth for this fixture is {show(truth)}")

    # The reader review's finding 2, the SECOND route to the same broken
    # promise: the gain FLOOR is asked before either cache
    # (`SilenceDetector.isQuiet`), so a clip the mix has ducked to 0.001 is
    # quiet with no speech cache on disk at all — and the note used to deny
    # the range printed beside it. Measured on the pre-fix binary: ranges
    # [[60000, 6160000]], `voice_pending` [2], note "… Nothing inside them is
    # proposed for removal."
    d = Session(mcp, "silence2-ducked")
    media, clip = d.lay("clean.wav")
    detect(d)
    d.op("set_audio", clips=[clip], patch={"volume": 0.001})
    os.remove(os.path.join(d.path, "cache", "speech", f"{media}.bin"))
    ducked = d.op("detect_silence")
    check(
        ducked.get("voice_pending") == [media],
        f"a clip ducked under the threshold with its SPEECH cache withheld is a "
        f"voice waiter: {ducked.get('voice_pending')}")
    check(
        spans(ducked) != [],
        f"and the floor proposes its span anyway, before either cache is asked: "
        f"{show(spans(ducked))}")
    check(
        (ducked.get("note") or "") == (
            "Analysis is still running for 1 media file(s); call again in a moment. "
            "That file holds spans that ARE proposed here: the mix turns them down far "
            "enough to be quiet before either cache is asked."),
        f"and the note counts it as proposed rather than promising nothing inside it "
        f"is: {ducked.get('note')!r}")


# ---- 10b. The two durations ---------------------------------------------


def duration_part(mcp):
    """The reader review's R1·1 (`archive/reelcut-roadmap-4.md` §8).

    `min_length` and `padding` are DURATIONS, and the sheet puts neither on
    the frame grid (`SilenceSheetController`'s unsnapped
    `ReelTime.ticks(seconds:)`). The tool read both through
    `optionalTimeArg`, which snaps every tick it is handed, so at the
    DEFAULT 30 fps it ran the sheet's own 0.05 s — 30000 — as 40000, ran
    `min_length: 45000` as 40000, and dropped `padding: 9999` to ZERO,
    cutting the material the caller asked to keep. Both are read as given
    now, and the frame rule stays where it belongs: on the span BOUNDS
    `refine` produces, which the walk asserts here tick for tick."""
    print("\n10b — min_length and padding run as given, not snapped to the grid")
    s = Session(mcp, "silence2-durations")
    media, clip = s.lay("clean.wav")
    detect(s)
    probabilities, segment = s.probabilities(media), s.segment(clip, media)
    for key, value in (("padding", 30_000), ("min_length", 45_000), ("padding", 9_999)):
        answer = detect(s, **{key: value})
        check(
            answer[key] == value,
            f"{key}: {value} runs as {answer[key]} — a duration is not a "
            f"position and is not rounded to the {s.frame()}-tick grid")
        # The walk is given what the CALLER asked for, never what the answer
        # echoed: a build that rounds the argument and then reports the
        # rounded value would agree with itself on both rows.
        asked = {"min_length": answer["min_length"], "padding": answer["padding"]}
        asked[key] = value
        walked = expected_spans(
            probabilities, segment, answer["voice_confidence"],
            asked["min_length"], asked["padding"], s.frame())
        check(
            spans(answer) == walked,
            f"and its spans are the walk at the {key} ASKED FOR, tick for tick: "
            f"{show(spans(answer))}")


# ---- 11. The cut the answer asks for ------------------------------------


def export_part(mcp, clean_default):
    """Phase 3 proves `ripple_delete_ranges` cuts what it is given. This
    proves the voice answer was the right thing to send: the export of the cut
    timeline is the uncut export with exactly those spans excised, BYTE for
    byte.

    Byte for byte rather than nearly so is what kpgalligan/reelcut#22 bought.
    A whole clip's duration used to be `snapped(media.duration)`, which for
    this fixture rounds UP past the end of the file, so the plan's
    `source_duration / duration` was 0.9990 rather than 1 and every segment
    was played slightly slow; a ripple then split it into three segments, each
    resampled on its own, and two exports of the same material drifted by
    about seventeen samples (measured). The core now snaps that length DOWN
    (spec §11), so the clip lands on the last whole frame INSIDE the file, the
    rate is exactly 1, nothing is resampled — and the trim this section used
    to do first is gone, replaced by the row that asserts what the core
    minted."""
    print("\n11 — the voice answer, cut and exported")
    s = Session(mcp, "silence2-export")
    media, clip = s.lay("clean.wav")
    frame = s.frame()
    inside_file = s.media_duration(media) // frame * frame
    check(
        s.clip(clip)["duration"] == inside_file,
        f"a whole-file clip lands on the last whole frame inside the file "
        f"({inside_file} of {s.media_duration(media)} ticks), so the plan plays "
        f"it at rate 1 and nothing is resampled")
    found = detect(s)
    answer = spans(found)
    # The reader review's R4·1: this section used to take the answer on
    # trust and prove only that the CUT matched it, which a build with no
    # voice rule at all satisfies (W1 and W2 both passed every row here). The
    # spans about to be exported are walked first, so what is proved is that
    # the model's own answer is the one that was sent.
    walked = expected_spans(
        s.probabilities(media), s.segment(clip, media), found["voice_confidence"],
        found["min_length"], found["padding"], frame)
    check(
        answer == walked,
        f"the spans about to be cut are the MODEL's, walked over the app's own "
        f"cache: {show(answer)} against {show(walked)}")
    check(
        answer == clean_default,
        f"the same one-clip project answers what section 1 measured: "
        f"{show(answer)}")
    whole = os.path.join(WORK, f"silence2-whole-{os.getpid()}.wav")
    cut = os.path.join(WORK, f"silence2-cut-{os.getpid()}.wav")
    for target in (whole, cut):
        if os.path.exists(target):
            os.remove(target)
    before = pcm(s.op("export", preset="audio_wav", path=whole)["path"])
    if not answer:
        # Nothing to send, which is a failure of the ANSWER and not a reason to
        # abort the run: the two rows below still score, so a mutant's total is
        # the tree's total.
        check(False, "the cut export is the uncut one minus the proposed spans — "
                     "there were no spans to send")
        check(False, "and sample for sample over the common length — same")
        return
    s.op("ripple_delete_ranges", ranges=[[a, b] for a, b in answer])
    after = pcm(s.op("export", preset="audio_wav", path=cut)["path"])

    def sample_of(ticks):
        return ticks * 48_000 // SEC

    expected = bytearray()
    edge = 0
    for a, b in answer:
        expected += before[sample_of(edge) * 4:sample_of(a) * 4]
        edge = b
    expected += before[sample_of(edge) * 4:]
    expected = bytes(expected)
    check(
        len(after) == len(expected),
        f"the cut export is the uncut one minus the proposed spans, to the "
        f"SAMPLE: {len(after) // 4} against {len(expected) // 4} frames")
    measured = wobble(after, expected)
    check(
        after == expected,
        f"and BYTE for byte, not to a tolerance: {measured} "
        f"(max |Δ|, differing samples)")


# ---- 5. Phase 3, re-run against this binary -----------------------------


def phase3_part():
    """§4g claim 5, and it runs LAST because it opens eighteen more documents.

    `mode` defaults to VOICE now, and phase 3's fixtures are tones with no
    voice in them at all — so these two scripts pass only because the level
    fallback catches a media that holds no voice anywhere. It is a claim to
    run, not to assume."""
    print("\n5 — phase 3's own proofs, against this binary")
    for name, expected in (("phase3_proof.py", 121), ("phase3_silence_scope.py", 8)):
        result = subprocess.run(
            [sys.executable, os.path.join(HERE, name), str(PORT)],
            capture_output=True, text=True)
        last = [line for line in result.stdout.splitlines() if "checks passed" in line]
        line = last[-1].strip() if last else "(no count line)"
        found = re.match(r"(\d+)/(\d+) checks passed$", line)
        check(
            result.returncode == 0 and found is not None
            and found.group(1) == found.group(2),
            f"{name} scores full against this binary: {line} "
            f"(exit {result.returncode})")
        # The COUNT is printed, not scored. §4g wrote down what each script
        # had when S1 landed; a later road map adding a row to one of them is
        # not this phase's failure, and "full" is the claim.
        note(
            f"{name} ran {found.group(2) if found else '?'} checks "
            f"(§4g quoted {expected} at the time)")


def main():
    read_arguments()
    for tool in ("say", "ffmpeg", "ffprobe"):
        if shutil.which(tool) is None:
            summary(aborted=f"{tool} is not on PATH and every fixture needs it")
    os.makedirs(WORK, exist_ok=True)
    # The per-run scratch audio (the relink copy and the two exports, plus the
    # `.pcm` each leaves beside it) is swept by pid the way `Session` sweeps
    # stale packages, so a hundred runs do not leave four hundred files.
    for stale in os.listdir(WORK):
        if re.fullmatch(r"silence2-(relink|whole|cut)-\d+\.(wav|pcm)", stale):
            os.remove(os.path.join(WORK, stale))
    make_fixtures()
    print(f"fixtures in {FIXTURES}")
    for name in ("clean.wav", "hum3.wav", "quiet2.wav", "tone.wav",
                 "voicetone.wav", "mute.mov"):
        print(f"  {name}: {duration_of(fixture(name)):.3f} s")

    mcp = MCP(PORT)
    names = mcp.tools()
    check(len(names) >= 77, f"the catalog holds 77 tools or more (got {len(names)})")

    session, truth, default, bare = clean_part(mcp)
    offgrid_part(mcp)
    hum3_part(mcp, truth, bare)
    quiet2_part(mcp, truth)
    tone_part(mcp, truth)
    scope_part(mcp, default)
    nest_part(mcp, default)
    withheld_part(mcp, truth)
    partial_part(mcp)
    waveform_part(mcp, truth)
    reversed_part(mcp)
    refusal_part(session)
    duration_part(mcp)
    export_part(mcp, default)
    phase3_part()
    summary()


if __name__ == "__main__":
    try:
        main()
    except (ToolError, AssertionError, KeyError, IndexError, RuntimeError, OSError,
            StopIteration, struct.error, subprocess.CalledProcessError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
