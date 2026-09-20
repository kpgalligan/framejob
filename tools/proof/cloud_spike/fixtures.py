#!/usr/bin/env python3
"""Road map 6, spike C0 — the fixtures, and the truth every timing is against.

Only synthetic audio ever leaves this machine. `speech.aiff` is `say`'s
rendering of road map 4's three pangrams with its two `[[slnc]]` pauses, and
`SPEECH_TEXT` is IMPORTED from `tools/proof/silence2_proof.py` so there is one
spelling of it in the tree; `speech.wav` is that file through the spike's own
`extract wav`, at `Transcriber.extractSettings`; `hour.wav` is `speech.wav`
looped by the `wave` module to exactly 3600 s (115.2 MB) for q8; and the two
`late.*` files are q4's, a black picture with the same speech starting 1.5 s
into it.

The TRUTH pauses are MEASURED from the WAV this host just wrote — the −40 dBFS
level rule over 10 ms peak buckets, spans of half a second or more — and
printed beside road map 4 §2's 2.72–4.29 / 6.68–7.81. A difference over 0.05 s
is a host-state note, not a failure: `say`'s rendering is host state, as road
map 4 recorded.
"""

import os
import sys
import wave
from array import array

from local_rows import build, run_bounded, spoken

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from silence2_proof import SPEECH_TEXT                              # noqa: E402

# Road map 4 §2's measured pauses in the same `say` rendering.
ROADMAP_4_PAUSES = [[2.72, 4.29], [6.68, 7.81]]
HOUR = 3600


def truth_pauses(path):
    """The −40 dBFS level rule over 10 ms peak buckets, spans ≥ 0.5 s."""
    with wave.open(path) as handle:
        rate = handle.getframerate()
        samples = array("h")
        samples.frombytes(handle.readframes(handle.getnframes()))
    bucket = rate // 100
    threshold = 32767 * (10 ** (-40 / 20))
    quiet = [max(abs(v) for v in samples[i:i + bucket]) < threshold
             for i in range(0, len(samples) - bucket + 1, bucket)]
    spans = []
    start = None
    for index, value in enumerate(quiet + [False]):
        if value and start is None:
            start = index
        elif not value and start is not None:
            if (index - start) * 0.01 >= 0.5:
                spans.append([round(start * 0.01, 3), round(index * 0.01, 3)])
            start = None
    return spans


def loop_to_an_hour(source, destination):
    with wave.open(source) as handle:
        params = handle.getparams()
        data = handle.readframes(handle.getnframes())
    frames = len(data) // (params.sampwidth * params.nchannels)
    needed = HOUR * params.framerate
    times = needed // frames + 1
    with wave.open(destination, "w") as out:
        out.setparams(params)
        out.writeframes((data * times)[:needed * params.sampwidth * params.nchannels])
    return frames / params.framerate


class Fixtures:
    """Built once, on the first row that asks. The hour is built only for q8."""

    def __init__(self, work, here, say):
        self.work = str(work)
        self.here = here
        self.folder = os.path.join(self.work, "fixtures")
        self.say = say
        self.extract = None
        self.seconds = 0.0
        self.pauses = []
        self.loop_seconds = 0.0
        self.formats = []
        self.notes = []
        self.ready = False

    def path(self, name):
        return os.path.join(self.folder, name)

    def run(self, argv, timeout=600):
        return run_bounded(argv, timeout=timeout)

    def build(self):
        if self.ready:
            return self
        os.makedirs(self.folder, exist_ok=True)
        self.extract, error = build([os.path.join(self.here, "extract.swift")],
                                               os.path.join(self.work, "bin", "extract"))
        if self.extract is None:
            raise RuntimeError(f"extract.swift did not build: {error}")
        if not os.path.exists(self.path("speech.aiff")):
            self.run(["say", "-o", self.path("speech.aiff"), SPEECH_TEXT], timeout=120)
        if not os.path.exists(self.path("speech.wav")):
            self.run([self.extract, "wav", self.path("speech.aiff"), self.path("speech.wav")])
        written = spoken(self.run([self.extract, "tracks", self.path("speech.wav")]))
        self.seconds = written.get("asset_duration") or 0.0
        self.pauses = truth_pauses(self.path("speech.wav"))
        self.say(f"fixture: {self.seconds:.3f} s, pauses {self.pauses} "
                 f"(road map 4 measured {ROADMAP_4_PAUSES})")
        for mine, theirs in zip(self.pauses, ROADMAP_4_PAUSES):
            for a, b in zip(mine, theirs):
                if abs(a - b) > 0.05:
                    self.notes.append(
                        f"a truth pause edge moved {abs(a - b):.3f} s from road map 4's "
                        f"{theirs} — host state, not a failure")
        for name, argv in (("late.mov", ["-c:v", "libx264", "-c:a", "pcm_s16le"]),
                           ("late.mp4", ["-c:v", "libx264", "-c:a", "aac"])):
            if os.path.exists(self.path(name)):
                continue
            self.run(["ffmpeg", "-y", "-v", "error",
                      "-f", "lavfi", "-i", "color=c=black:s=320x240:r=30:d=13",
                      "-itsoffset", "1.5", "-i", self.path("speech.aiff"),
                      "-map", "0:v", "-map", "1:a"] + argv + ["-shortest", self.path(name)])
        self.ready = True
        return self

    def smaller_formats(self):
        """q2's candidates: AAC at the first bitrate the encoder takes, then FLAC."""
        if self.formats:
            return self.formats
        refusals = {}
        for bitrate in (64000, 48000, 32000, 24000):
            name = f"speech_aac_{bitrate}.m4a"
            answer = spoken(self.run(
                [self.extract, "m4a", self.path("speech.wav"), self.path(name), str(bitrate)]))
            if answer.get("ok"):
                self.formats.append((f"m4a_{bitrate}", self.path(name)))
                break
            refusals[bitrate] = answer.get("error")
        flac = spoken(self.run(
            [self.extract, "flac", self.path("speech.wav"), self.path("speech.flac")]))
        if flac.get("ok"):
            self.formats.append(("flac", self.path("speech.flac")))
        self.aac_refusals = refusals
        self.flac = flac
        return self.formats

    def hour(self):
        if not os.path.exists(self.path("hour.wav")):
            self.loop_seconds = loop_to_an_hour(self.path("speech.wav"), self.path("hour.wav"))
        else:
            with wave.open(self.path("speech.wav")) as handle:
                self.loop_seconds = handle.getnframes() / handle.getframerate()
        return self.path("hour.wav")
