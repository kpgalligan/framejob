"""Road map "creator-jobs" TX1b (spec §11 TX-15): the oracle for where an
on-device word's start moves, read from a package's own caches.

`moved(words, speech, peaks)` is TX-15's rule, written here from the decision
and not from `WordOnsets.swift`, over the files the app reads:
`cache/speech/<id>.bin` (one float32 Silero probability per 19,200-tick
cell) and `cache/peaks/<id>.bin` (one float32 peak per 6,000-tick bucket),
each read only when its `.complete.json` marker is beside it. Thresholds are
compared in float32, as the app compares them; the median is the element at
(n − 1)/2 of the peaks of the buckets whose start lies in the word's
non-speech run [a·cell, b·cell).

`wait_voice(package, media)` waits for both caches' markers, which the
open's or the import's cache pass writes; a read before them answers the
recogniser's starts (TX-18).
"""
import os
import struct
import time

CELL = 19_200          # MediaSpeech.chunkTicks: 512 samples at 16 kHz
BUCKET = 6_000         # MediaPeaks.bucketTicks: 10 ms
MIN_RUN = 2            # TranscriptCut.minimumRunCells
LEAD_CELLS = 3         # WordOnsets.leadCells
FLOOR_RATIO = 4.0      # WordOnsets.floorRatio, +12 dB


def f32(value):
    """`value` rounded to the nearest float32, as a Python float."""
    return struct.unpack("<f", struct.pack("<f", value))[0]


LEVEL = f32(0.01)      # −40 dBFS, linear
CONFIDENCE = f32(0.5)  # SilenceDetector.Settings.defaultVoiceConfidence


def _floats(path):
    with open(path, "rb") as handle:
        data = handle.read()
    return list(struct.unpack(f"<{len(data) // 4}f", data[:len(data) // 4 * 4]))


def _cache(package, kind, media):
    folder = os.path.join(str(package), "cache", kind)
    marker = os.path.join(folder, f"{media}.complete.json")
    body = os.path.join(folder, f"{media}.bin")
    if not (os.path.exists(marker) and os.path.exists(body)):
        return None
    return _floats(body)


def load(package, media):
    """(speech, peaks) of `media` in `package`, each None when absent."""
    return _cache(package, "speech", media), _cache(package, "peaks", media)


def wait_voice(package, media, bound=300):
    """Whether both caches' markers appeared within `bound` seconds."""
    folder = os.path.join(str(package), "cache")
    markers = [os.path.join(folder, kind, f"{media}.complete.json") for kind in ("speech", "peaks")]
    deadline = time.time() + bound
    while time.time() < deadline:
        if all(os.path.exists(m) for m in markers):
            time.sleep(0.5)  # the publish writes the marker last; the post follows it
            return True
        time.sleep(0.25)
    return False


def _first_speech(s, limit, speech):
    own = s // CELL
    run = None
    if own < len(speech) and speech[own] < CONFIDENCE:
        run = own
        while run > 0 and speech[run - 1] < CONFIDENCE:
            run -= 1
    b = own + 1
    while b < len(speech) and b * CELL < limit:
        if speech[b] >= CONFIDENCE:
            if run is not None and (run <= own or b - run >= MIN_RUN):
                return run, b
            run = None
        elif run is None:
            run = b
        b += 1
    return None


def _median(peaks, start, end):
    first = -(-start // BUCKET)
    past = min(-(-end // BUCKET), len(peaks))
    if first >= past:
        return 0.0
    ordered = sorted(peaks[first:past])
    return ordered[(len(ordered) - 1) // 2]


def onset(s, limit, speech, peaks):
    """TX-15 for one word starting at `s`, its `limit` already taken."""
    if s < 0:
        return s
    found = _first_speech(s, limit, speech)
    if found is None:
        return s
    a, b = found
    fallback = b * CELL
    if peaks is None:
        return fallback
    threshold = f32(max(LEVEL, f32(FLOOR_RATIO * _median(peaks, a * CELL, fallback))))
    start = max(s, a * CELL, (b - LEAD_CELLS) * CELL)
    first = start // BUCKET
    past = min(-(-(b + 1) * CELL // BUCKET), len(peaks))
    hit = next((i for i in range(first, past) if peaks[i] >= threshold), None)
    if hit is None:
        return fallback
    at = max(hit * BUCKET, s)
    return fallback if at >= limit else at


def moved(words, speech, peaks):
    """One moved start per word of `words` ([{start, end}] in source order,
    a stored run's), or None with no voice cache."""
    if speech is None:
        return None
    out = []
    for index, word in enumerate(words):
        end = max(word["start"], word["end"])
        limit = min(end, words[index + 1]["start"]) if index + 1 < len(words) else end
        out.append(onset(word["start"], limit, speech, peaks))
    return out
