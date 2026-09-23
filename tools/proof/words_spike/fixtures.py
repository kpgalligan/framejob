#!/usr/bin/env python3
"""Road map 8, spike W0 — the four fixtures, and the truth each one carries.

Only synthetic audio ever leaves this machine, and only three of these four
files are ever uploaded (`ten.wav` is not: C0's q8 already measured the cloud
at 147× real time, and ten minutes of audio buys nothing this spike asks).

* `pangram.wav` — `say`'s rendering of road map 4's three pangrams with its
  two `[[slnc]]` pauses. `SPEECH_TEXT` is IMPORTED from
  `tools/proof/silence2_proof.py`, and the truth pauses are MEASURED from the
  WAV this host just wrote through `cloud_spike.fixtures.truth_pauses`, then
  printed beside road map 4's 2.72–4.29 / 6.68–7.81.
* `talk.wav` — `TALK_TEXT`, a synthetic talking-head script written below:
  about 120 words with numbers, contractions, a hyphenated compound, the
  punctuation `,;:?!…`, and one quoted phrase. No names and no addresses.
* `ten.wav` — `talk.wav` repeated with 0.8 s of digital silence between the
  copies until it passes 600 s, written by Python's `wave`.
* `isolated.wav` — every word of `SPEECH_TEXT` rendered ALONE by `say` and
  concatenated with 300 ms of silence between them.

**`say` has no word timing.** `isolated.wav` is the nearest thing to a known
per-word start this spike can build, and it is an APPROXIMATION of speech: a
list of words said one at a time is not a sentence, and no engine's timing on
it transfers unchanged to running speech. It exists so q2's two engines can be
compared against the same third number rather than only against each other.

**And each rendered word carries the synthesizer's own leading silence.**
C0 measured 330–370 ms of it per `[[slnc]]` boundary
(`cloud_spike/fixtures.py:31`, the rule at `:35-54`), so a word's known start
is NOT its concatenation offset: it is `offset + onset(word.wav)`, where
`onset` applies that same −40 dBFS / 10 ms bucket rule to the lone rendering.
`fixtures.json` records both per word, with the median leading silence beside
them, and q2's deltas are against the corrected number with the raw-offset
delta printed alongside so the bias stays visible.
"""

import importlib.util
import json
import os
import re
import sys
import wave
from array import array

HERE = os.path.dirname(os.path.abspath(__file__))
PROOF = os.path.normpath(os.path.join(HERE, ".."))
CLOUD = os.path.join(PROOF, "cloud_spike")
# APPENDED, never inserted: `cloud_spike/` has a `fixtures.py` of its own, and
# putting that directory first would make this file import itself by another
# name half the time. The one module whose name collides is loaded by path
# under a name of its own, below.
for folder in (PROOF, CLOUD):
    if folder not in sys.path:
        sys.path.append(folder)

import local_rows                                                    # noqa: E402
from silence2_proof import SPEECH_TEXT                               # noqa: E402


def _by_path(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


_cloud = _by_path("cloud_spike_fixtures", os.path.join(CLOUD, "fixtures.py"))
ROADMAP_4_PAUSES = _cloud.ROADMAP_4_PAUSES
truth_pauses = _cloud.truth_pauses

# About 120 words, ≈45 s at `say`'s default rate. The SAME string
# `words_spike/text_probe.swift` holds as its `TALK_TEXT`; `text_rows.py`
# compares the two before q5's stress row runs and scores a difference as a
# FAILURE, so there is one text in effect even though each language needs its
# own spelling of it.
TALK_TEXT = (
    "So here's the thing about editing video on a laptop in 2026: you open a "
    "project, you scrub through forty minutes of footage, and you find the one "
    "take that actually works. That take is maybe ninety seconds long; everything "
    "else is a warm-up. The hard part isn't cutting — it's finding. Can you see "
    "what I mean? I have three cameras, two microphones, and one very patient "
    "dog. She sits off-camera and waits. When I say the word \"treat\" she stands "
    "up and ruins the shot, every time! So we renamed it. Now we call it a "
    "reward, and she hasn't worked that out yet… but she will, because she is "
    "smarter than the software."
)

# `SPEECH_TEXT` with the synthesizer's pause directives taken out, which is
# what `isolated.wav` says one word at a time.
ISOLATED_TEXT = re.sub(r"\[\[[^\]]*\]\]\s*", "", SPEECH_TEXT).strip()

TEN_TARGET_SECONDS = 600.0
TEN_GAP_SECONDS = 0.8
ISOLATED_GAP_SECONDS = 0.3


def onset(path):
    """The first 10 ms bucket whose peak reaches −40 dBFS, in seconds.

    `cloud_spike/fixtures.py:35-54`'s rule, read from the other end: that one
    looks for the QUIET spans, this one for the first loud bucket. 0.0 when
    nothing in the file reaches the threshold.
    """
    try:
        with wave.open(path) as handle:
            rate = handle.getframerate()
            samples = array("h")
            samples.frombytes(handle.readframes(handle.getnframes()))
    except (OSError, wave.Error):
        return 0.0
    bucket = max(rate // 100, 1)
    threshold = 32767 * (10 ** (-40 / 20))
    for index in range(0, len(samples) - bucket + 1, bucket):
        if max(abs(v) for v in samples[index:index + bucket]) >= threshold:
            return round(index / rate, 3)
    return 0.0


def _params(path):
    with wave.open(path) as handle:
        return handle.getparams()


def _read(path):
    with wave.open(path) as handle:
        return handle.getparams(), handle.readframes(handle.getnframes())


def concatenate(pieces, gap_seconds, destination):
    """The pieces, in order, with `gap_seconds` of digital silence between
    them. Answers the start OFFSET of each piece, in seconds."""
    params, first = _read(pieces[0])
    frame = params.sampwidth * params.nchannels
    gap = b"\x00" * (int(params.framerate * gap_seconds) * frame)
    offsets = []
    body = b""
    for index, piece in enumerate(pieces):
        if index:
            body += gap
        offsets.append(len(body) // frame / params.framerate)
        body += first if index == 0 else _read(piece)[1]
    with wave.open(destination, "w") as out:
        out.setparams(params)
        out.writeframes(body)
    return [round(value, 4) for value in offsets]


def repeat_to(source, gap_seconds, target_seconds, destination):
    """`source` again and again, a fixed silence between copies, until the
    whole is at least `target_seconds`. Answers the exact seconds written."""
    params, data = _read(source)
    frame = params.sampwidth * params.nchannels
    gap = b"\x00" * (int(params.framerate * gap_seconds) * frame)
    one = len(data) // frame / params.framerate
    copies = int(target_seconds // (one + gap_seconds)) + 1
    body = (data + gap) * copies
    with wave.open(destination, "w") as out:
        out.setparams(params)
        out.writeframes(body)
    return round(len(body) // frame / params.framerate, 3), copies


class Fixtures:
    """Built once, under `work/words_spike/fixtures/`, on the first row that
    asks. Every child goes through `local_rows.run_bounded` (rule H)."""

    def __init__(self, work, say):
        self.work = str(work)
        self.folder = os.path.join(self.work, "fixtures")
        self.say = say
        self.extract = None
        self.notes = []
        self.pauses = []
        self.seconds = {}
        self.isolated = []
        self.ten = {}
        self.ready = False

    def path(self, name):
        return os.path.join(self.folder, name)

    def run(self, argv, timeout=600):
        return local_rows.run_bounded(argv, timeout=timeout)

    def _say(self, text, aiff, wav):
        if not os.path.exists(aiff):
            self.run(["say", "-o", aiff, text], timeout=300)
        if not os.path.exists(wav):
            self.run([self.extract, "wav", aiff, wav], timeout=300)

    def _duration(self, wav):
        try:
            with wave.open(wav) as handle:
                return round(handle.getnframes() / handle.getframerate(), 3)
        except (OSError, wave.Error):
            return 0.0

    def build(self):
        if self.ready:
            return self
        os.makedirs(self.folder, exist_ok=True)
        # The cloud spike's own extractor, at `Transcriber.extractSettings`
        # (16 kHz mono 16-bit) — the settings the shipped app hands both
        # engines, so nothing here measures a different file from the product.
        self.extract, error = local_rows.build(
            [os.path.join(CLOUD, "extract.swift")], os.path.join(self.work, "bin", "extract"))
        if self.extract is None:
            raise RuntimeError(f"extract.swift did not build: {error}")

        self._say(SPEECH_TEXT, self.path("pangram.aiff"), self.path("pangram.wav"))
        self.pauses = truth_pauses(self.path("pangram.wav"))
        self.seconds["pangram.wav"] = self._duration(self.path("pangram.wav"))
        self.say(f"  fixture pangram.wav: {self.seconds['pangram.wav']:.3f} s, "
                 f"pauses {self.pauses} (road map 4 measured {ROADMAP_4_PAUSES})")
        for mine, theirs in zip(self.pauses, ROADMAP_4_PAUSES):
            for a, b in zip(mine, theirs):
                if abs(a - b) > 0.05:
                    self.notes.append(
                        f"a truth pause edge moved {abs(a - b):.3f} s from road map 4's "
                        f"{theirs} — `say` is host state, not a failure")

        self._say(TALK_TEXT, self.path("talk.aiff"), self.path("talk.wav"))
        self.seconds["talk.wav"] = self._duration(self.path("talk.wav"))
        self.say(f"  fixture talk.wav: {self.seconds['talk.wav']:.3f} s, "
                 f"{len(TALK_TEXT.split())} words")

        if not os.path.exists(self.path("ten.wav")):
            seconds, copies = repeat_to(
                self.path("talk.wav"), TEN_GAP_SECONDS, TEN_TARGET_SECONDS,
                self.path("ten.wav"))
            self.ten = {"seconds": seconds, "copies": copies, "gap_s": TEN_GAP_SECONDS}
        else:
            self.ten = {"seconds": self._duration(self.path("ten.wav")),
                        "copies": None, "gap_s": TEN_GAP_SECONDS}
        self.seconds["ten.wav"] = self.ten["seconds"]
        self.say(f"  fixture ten.wav: {self.ten['seconds']:.3f} s "
                 f"({self.ten['copies']} copies of talk.wav, {TEN_GAP_SECONDS} s apart)")

        self._isolated()
        self.seconds["isolated.wav"] = self._duration(self.path("isolated.wav"))
        median = self._median([row["onset_leading_s"] for row in self.isolated])
        self.say(f"  fixture isolated.wav: {self.seconds['isolated.wav']:.3f} s, "
                 f"{len(self.isolated)} words, median leading silence {median:.3f} s")
        with open(os.path.join(self.folder, "fixtures.json"), "w") as handle:
            json.dump({
                "seconds": self.seconds, "truth_pauses": self.pauses,
                "roadmap_4_pauses": ROADMAP_4_PAUSES, "ten": self.ten,
                "isolated_words": self.isolated,
                "isolated_median_leading_silence_s": median,
                "isolated_text": ISOLATED_TEXT, "talk_text": TALK_TEXT,
                "notes": self.notes,
                "approximation":
                    "isolated.wav is words said one at a time, not speech; "
                    "`say` publishes no word timing, so a word's known start is "
                    "its concatenation offset plus the onset measured in its own "
                    "lone rendering",
            }, handle, indent=2, sort_keys=True)
        self.ready = True
        return self

    def _median(self, values):
        rows = sorted(values)
        if not rows:
            return 0.0
        middle = len(rows) // 2
        return rows[middle] if len(rows) % 2 else (rows[middle - 1] + rows[middle]) / 2

    def _isolated(self):
        words = ISOLATED_TEXT.split()
        folder = os.path.join(self.folder, "words")
        os.makedirs(folder, exist_ok=True)
        pieces = []
        for index, word in enumerate(words):
            aiff = os.path.join(folder, f"{index:02d}.aiff")
            wav = os.path.join(folder, f"{index:02d}.wav")
            self._say(word, aiff, wav)
            pieces.append(wav)
        missing = [p for p in pieces if not os.path.exists(p)]
        if missing:
            raise RuntimeError(f"{len(missing)} lone word renderings are missing")
        offsets = concatenate(pieces, ISOLATED_GAP_SECONDS, self.path("isolated.wav"))
        self.isolated = []
        for word, piece, offset in zip(words, pieces, offsets):
            leading = onset(piece)
            self.isolated.append({
                "text": word, "offset_s": offset, "onset_leading_s": leading,
                "known_start_s": round(offset + leading, 4),
                "seconds": self._duration(piece),
            })
