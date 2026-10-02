"""Road map 2, phase 5 — Sound, driven against the built binary over MCP.

Every claim here is one of two things: a SAMPLE-FOR-SAMPLE comparison of two
decoded exports, or a number this script measured off an exported file with
its own arithmetic. Nothing is believed because the app reported it — the
whole point of 5d is that an export can report −14.0 LUFS and write something
else, and a check that reads the report back is a check that build would
pass.

The five parts, and what each is measured with:

* **5a the mono fold** — three claims off one fixture whose channels are
  DIFFERENT (440 Hz at half scale left, 880 Hz at a quarter right), because
  "left equals right" is a tautology on any of the stereo tones in `media/`.
  With `mono` on the two channels are equal sample for sample; each of those
  samples is within one 16-bit LSB of the MEAN of the two channels the same
  timeline writes with `mono` off, which is what tells an average from
  "copy the left channel over the right"; and setting `mono` and clearing it
  again writes a file byte-identical to the one written before it was ever
  set. That last is the baseline the contract's D-A5 asks for, taken HERE
  rather than read off a stored file: a pre-phase binary is not available to
  a script, and a stored one would only prove that a file on disk had not
  changed.

  The same three claims are then made of a NEST clip's `mono`, over a clip
  panned hard left BEFORE it was nested — the one arrangement that tells a
  fold of the nest's MIX from a fold carried down to the head of the inner
  clip's own chain, which would run before that pan and leave the file hard
  left. A nest clip's id names no audio segment, so this is the case where
  the checkbox was accepted, kept lit and saved while folding nothing.

* **5b the meters** — NOT PROVED HERE, and this is the honest statement of
  why. `LevelMeter` publishes a struct to a view (`LevelMeterView`) and
  nothing in `AgentCatalog.swift` reaches it: the meter's model has no MCP
  surface at all, so there is no call this script could make that would read
  a level off it, and adding a tool so that a proof could exist would be the
  proof deciding the product's API. The contract's own claim — that a
  −20 dBFS tone publishes −20 dBFS within ±0.5 dB — is a unit-style check
  against `LevelMeter`, and the resting appearance D-B5 fixes is what
  `phase5_chrome.py` photographs offscreen. Neither belongs in a script whose
  currency is exports and rendered frames.

* **5c Normalise Clip** — the placement is read back through the tool, and
  then the LEVEL is measured on an exported WAV. A −6 dBFS tone normalises to
  a file whose loudest sample is −1 dBFS ±0.1; a −40 dBFS tone cannot get
  there (the model's volume ceiling is 4×) and its file lands at the −27.96
  the result claimed rather than at −1, which is the whole of D-C7. The
  refusals are read for the words that name the clip: a silent clip, a clip
  whose peaks file this script DELETED off the package (the deterministic
  spelling of "not analysed yet"), a clip id that is not in the project, and a
  NEST — whose sound is measured coming out of the export first, because the
  claim about that refusal is that it does not tell a clip you can hear that it
  plays no sound.
  One job's failure is one job's problem — a mixed call normalises the good
  clip and reports the other under `skipped`. And the reversed mirror is
  measured by the only means that can tell it from its absence: a fixture
  loud in its first half and quiet in its second, trimmed to its first 1.4 s
  forwards and backwards, must measure 20 dB apart.

* **5d loudness on export** — the script implements BS.1770-4 (below) and
  measures the WRITTEN FILE. That is what makes the ±0.5 LU claim a claim:
  `ExportLoudness` reports "measured + gain", so a build whose writer dropped
  the gain would report −14.0 LUFS over a file that still held −6.7, and
  every check that read the report would pass. The report is still asserted —
  against this script's own measurement, which is the other half of the same
  claim.

  **True peak gets its own, looser tolerance (±0.3 dB) and two invariants**,
  and the reason is in the standard rather than in either implementation:
  BS.1770-4's true-peak estimate is a 4× oversampling FIR, Annex 2 allows
  ±0.4 dB of it against the real inter-sample maximum, and two correct
  implementations differing in tap alignment or in where they quantise will
  not agree to the millidecibel the way two integrated-loudness passes over
  identical samples do. A tolerance alone would pass against a build that
  reported the SAMPLE peak and called it true, so it is joined by the two
  invariants that fail such a build: true peak is never below sample peak,
  and a 45° fs/4 sine — whose samples all sit at ±0.7071 of its real
  amplitude — must read at least 2.5 dB above its sample peak.

  **Two more claims are about the report itself**, and both are about a
  number that is right in the ordinary case and wrong in one particular one.
  The ceiling is SWEPT across the gain's own 0.01 dB grid — five ceilings
  0.002 dB apart — because a cap quantised to the nearest step lands over the
  ceiling for about half the measured peaks it could meet, so a single
  fixture answers "the true peak does not exceed the ceiling" by luck rather
  than by construction. And a mix driven PAST full scale is exported, because
  the measure pass reads float while the write pass decodes Int16, which
  saturates before the gain: the file then holds a signal the measurement
  never saw, and the report has to say whose numbers it is publishing.
  `phase5_chrome.py`'s section 9 sweeps the same arithmetic 200 peaks at a
  time with no export in it at all.

* **5e WAV and AIFF** — `ffprobe` reports 48 kHz LPCM for both (little-endian
  in the RIFF, big-endian in the IFF, which is the container's decision), the
  two files of one project decode to IDENTICAL PCM, and neither went near
  `ImageSequenceWriter`: it refuses an unknown container outright, it writes
  no audio track at all, and `Exporter.measuresLoudness` gives an image
  sequence no `loudness` block — so a 21-second timeline (630 frames, past
  that writer's 600-frame cap) coming back as a PCM file WITH a loudness
  block is three separate ways of saying the same thing. The contrast is
  measured beside it: the same timeline exported as GIF reports no loudness.

**Fixtures.** This script writes its own, with `ffmpeg`, into
`work/fixtures/` — `aevalsrc` with an explicit expression per channel, so
every amplitude and phase is exact and stated here rather than inherited from
whatever `media/` happens to hold. (`amerge` of two mono sines does NOT do
it: it lands 18 dB down, which is how this was found.) They are rewritten on
every run: a fixture that could be stale is a fixture that could be lying.

**ffmpeg IS needed at proof time**, to decode each export to raw PCM. And the
standing limit is respected throughout: audio export is not bit-deterministic
near a duck ramp edge, so nothing here has a duck or a fade on it, and every
byte-identity claim is made over a plain, unramped timeline.
"""

import array
import json
import math
import os
import re
import shutil
import subprocess
import sys
import time

from mcp import MCP, ToolError, target

SOCKET = target(sys.argv)
HERE = os.path.dirname(os.path.abspath(__file__))
WORK = os.path.join(HERE, "work")
FIXTURES = os.path.join(WORK, "fixtures")

SEC = 600_000
RATE = 48000

# The whole catalog after phase 5: 53 ops (`core/src/edit.rs`'s OP_NAMES) plus
# the 18 tools that mirror no op — phase 4's 17 and `normalize_clip`, which is
# an app-state composite over the peaks cache and deliberately not an op. The
# EXACT count belongs to the NEWEST phase's script, because it is the only
# thing that tells a stale binary on the port from the build under test;
# phases 1 to 4 keep floors so a later phase's tools never fail an older
# proof. When phase 6 lands, this assertion moves to its script and this one
# becomes a floor.
TOOLS = 71

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


def close(value, wanted, tolerance):
    return value is not None and math.isfinite(value) and abs(value - wanted) <= tolerance


def fmt(value):
    """A level for a check's message. A missing or non-finite one is spelled
    out rather than formatted, so a check that failed because the key was not
    there says so instead of raising inside its own explanation."""
    if value is None:
        return "absent"
    if not math.isfinite(value):
        return str(value)
    return f"{value:.4f}"


# ---- BS.1770-4, in pure Python -------------------------------------------
#
# Transcribed from Recommendation ITU-R BS.1770-4 (10/2015), not from
# `app/Sources/Loudness.swift`: the two agreeing is the claim, so they cannot
# share a line. The coefficient TABLES are of course the same numbers — they
# are the standard's, and an implementation that invented its own would be
# measuring something else — but the filtering, the gating and the peak search
# below were written from the text.
#
# It is fast enough to be uninteresting: the K-weighting is two direct-form-I
# biquads over a few hundred thousand samples, and the true-peak search only
# interpolates where it has to (see `true_peak`).

# Table 1, stage 1: the "spherical head" high shelf, at 48 kHz.
STAGE1 = (
    1.53512485958697, -2.69169618940638, 1.19839281085285,
    -1.69065929318241, 0.73248077421585,
)
# Table 2, stage 2: the RLB high-pass, at 48 kHz.
STAGE2 = (1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621)

# Annex 2 § 3's order-48, 4-phase interpolating FIR, phase 0 first, tap 0
# first. Phase 3 is phase 0 reversed and phase 2 is phase 1 reversed, which is
# the linear-phase symmetry a correct transcription has.
PEAK_FIR = (
    (0.0017089843750, 0.0109863281250, -0.0196533203125, 0.0332031250000,
     -0.0594482421875, 0.1373291015625, 0.9721679687500, -0.1022949218750,
     0.0476074218750, -0.0266113281250, 0.0148925781250, -0.0083007812500),
    (-0.0291748046875, 0.0292968750000, -0.0517578125000, 0.0891113281250,
     -0.1665039062500, 0.4650878906250, 0.7797851562500, -0.2003173828125,
     0.1015625000000, -0.0582275390625, 0.0330810546875, -0.0189208984375),
    (-0.0189208984375, 0.0330810546875, -0.0582275390625, 0.1015625000000,
     -0.2003173828125, 0.7797851562500, 0.4650878906250, -0.1665039062500,
     0.0891113281250, -0.0517578125000, 0.0292968750000, -0.0291748046875),
    (-0.0083007812500, 0.0148925781250, -0.0266113281250, 0.0476074218750,
     -0.1022949218750, 0.9721679687500, 0.1373291015625, -0.0594482421875,
     0.0332031250000, -0.0196533203125, 0.0109863281250, 0.0017089843750),
)
PEAK_TAPS = len(PEAK_FIR[0])

# Equation (2)'s offset, Γa, and Γr's offset below the gated mean.
OFFSET = -0.691
ABSOLUTE_GATE = -70.0
RELATIVE_GATE = -10.0


def biquad(samples, coefficients):
    """One direct-form-I section over a whole channel, in doubles."""
    b0, b1, b2, a1, a2 = coefficients
    x1 = x2 = y1 = y2 = 0.0
    out = [0.0] * len(samples)
    for index, x in enumerate(samples):
        y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, x
        y2, y1 = y1, y
        out[index] = y
    return out


def db(magnitude):
    """A linear magnitude as a level. −inf for nothing at all."""
    return 20 * math.log10(magnitude) if magnitude > 0 else -math.inf


def loudness_of(mean_square):
    return OFFSET + 10 * math.log10(mean_square) if mean_square > 0 else -math.inf


def integrated(channels):
    """Integrated loudness in LUFS, or None where the standard has none —
    a programme shorter than one 400 ms block, or one entirely gated out.

    Mono and stereo only, which is what an export mix is: BS.1770-4's Table 3
    weights the surround channels 1.41, and every weight here is 1.0."""
    weighted = [biquad(biquad(c, STAGE1), STAGE2) for c in channels]
    hop = int(RATE * 0.1)
    length = min(len(c) for c in weighted)
    # A running sum per 100 ms sub-block; a 400 ms gating block is four
    # consecutive ones, which is what 75 % overlap means.
    sub_blocks = []
    start = 0
    while start + hop <= length:
        total = 0.0
        for channel in weighted:
            for index in range(start, start + hop):
                total += channel[index] * channel[index]
        sub_blocks.append(total)
        start += hop
    if len(sub_blocks) < 4:
        return None
    blocks = [
        sum(sub_blocks[b:b + 4]) / (4.0 * hop) for b in range(len(sub_blocks) - 3)
    ]
    above_absolute = [ms for ms in blocks if loudness_of(ms) > ABSOLUTE_GATE]
    if not above_absolute:
        return None
    threshold = loudness_of(sum(above_absolute) / len(above_absolute)) + RELATIVE_GATE
    kept = [ms for ms in above_absolute if loudness_of(ms) > threshold]
    if not kept:
        return None
    return loudness_of(sum(kept) / len(kept))


def sample_peak(channels):
    return max(max(abs(s) for s in c) for c in channels)


def true_peak(channels):
    """The largest interpolated magnitude, as a linear number.

    Only positions whose 12-tap window holds a sample at or above a fixed
    fraction of the sample peak are interpolated, and the fraction is chosen
    so the shortcut is EXACT rather than a heuristic: an interpolated value is
    at most Σ|h| times the largest sample in its window, Σ|h| is 2.023 at
    worst over these four phases, so a window whose every sample is under
    peak/2.5 cannot reach 0.81 × peak — and the true peak is never below the
    sample peak, which is already in `best`. On a sparse programme that is a
    few hundred positions instead of a few hundred thousand."""
    peak = sample_peak(channels)
    if peak <= 0:
        return 0.0
    threshold = peak / 2.5
    best = peak
    for channel in channels:
        length = len(channel)
        positions = set()
        for index, value in enumerate(channel):
            if abs(value) >= threshold:
                positions.update(
                    range(max(0, index), min(length, index + PEAK_TAPS)))
        for position in sorted(positions):
            first = position - PEAK_TAPS + 1
            for phase in PEAK_FIR:
                total = 0.0
                for tap in range(PEAK_TAPS):
                    source = first + tap
                    if 0 <= source < length:
                        total += channel[source] * phase[PEAK_TAPS - 1 - tap]
                if abs(total) > best:
                    best = abs(total)
    return best


# ---- decoding an export ---------------------------------------------------


def pcm(path):
    """`path` decoded to raw signed 16-bit LE stereo 48 kHz, as bytes — the
    same incantation `phase2_proof.py` uses, so two phases' sample comparisons
    are over the same thing."""
    out = os.path.splitext(path)[0] + ".pcm"
    subprocess.run(
        [
            "ffmpeg", "-v", "error", "-y", "-i", path, "-vn", "-f", "s16le",
            "-acodec", "pcm_s16le", "-ar", "48000", "-ac", "2", out,
        ],
        check=True,
    )
    with open(out, "rb") as handle:
        return handle.read()


def samples(data):
    values = array.array("h")
    values.frombytes(data)
    return values


def sides(data):
    """(left, right) as two sample arrays."""
    values = samples(data)
    return values[0::2], values[1::2]


def channels(data):
    """The two channels as floats in [−1, 1), for the measurements."""
    left, right = sides(data)
    return [[s / 32768.0 for s in left], [s / 32768.0 for s in right]]


def describe(a, b):
    """What two PCM dumps differ by, for a check that failed."""
    if len(a) != len(b):
        return f"lengths differ ({len(a)} vs {len(b)} bytes)"
    if a == b:
        return "byte-identical"
    diffs = [abs(p - q) for p, q in zip(samples(a), samples(b)) if p != q]
    return f"max |Δ| {max(diffs)}, {len(diffs)} samples differ of {len(a) // 2}"


def probe(path):
    """ffprobe's first audio stream, as a dict."""
    answer = subprocess.run(
        [
            "ffprobe", "-v", "error", "-select_streams", "a",
            "-show_entries", "stream=codec_name,sample_rate,channels",
            "-of", "json", path,
        ],
        check=True, capture_output=True, text=True,
    )
    streams = json.loads(answer.stdout).get("streams", [])
    return streams[0] if streams else {}


# ---- the fixtures ---------------------------------------------------------
#
# One `aevalsrc` expression per channel, so the amplitude and the phase of
# every fixture are written here and are exact. All are 48 kHz 16-bit stereo
# WAV, which is what the export mix is, so nothing is resampled anywhere.

FIXTURE_EXPRESSIONS = {
    # 5a. The channels must DIFFER or "left equals right" proves nothing:
    # 440 Hz at −6.02 dBFS left, 880 Hz at −12.04 dBFS right. The mono fold's
    # answer, max over t of |0.5·sin(a) + 0.25·sin(2a)|/2, is about −9.8 dBFS
    # — a number neither channel holds, which is why the mean can be asserted.
    "lr.wav": ("0.5*sin(2*PI*440*t)", "0.25*sin(2*PI*880*t)", 2),
    # 5c and 5d. A plain tone at exactly half scale: −6.020600 dBFS, which
    # normalise must turn into −1 dBFS with a volume of 1.7825.
    "half.wav": ("0.5*sin(2*PI*440*t)", "0.5*sin(2*PI*440*t)", 3),
    # 5c's clamp. −40 dBFS, which 4× can only lift to −27.96.
    "quiet.wav": ("0.01*sin(2*PI*440*t)", "0.01*sin(2*PI*440*t)", 3),
    # 5c's silence refusal: an audio track that is there and is nothing.
    "silent.wav": ("0", "0", 2),
    # 5c's reversed mirror: loud for 1.5 s, then 20 dB down for 1.5 s.
    "ramp.wav": (
        "0.5*sin(2*PI*440*t)*between(t,0,1.5)+0.05*sin(2*PI*440*t)*between(t,1.5,3)",
        "0.5*sin(2*PI*440*t)*between(t,0,1.5)+0.05*sin(2*PI*440*t)*between(t,1.5,3)",
        3,
    ),
    # 5d's ceiling. A −20 dBFS tone with one 10 ms burst near full scale: a
    # peak-to-loudness ratio near 19 dB, so a −14 LUFS target with a −1 dBTP
    # ceiling is capped by the PEAK and the file lands quieter than asked.
    "crest.wav": (
        "0.1*sin(2*PI*440*t)+0.85*sin(2*PI*1000*t)*between(t,2,2.01)",
        "0.1*sin(2*PI*440*t)+0.85*sin(2*PI*1000*t)*between(t,2,2.01)",
        4,
    ),
    # 5d's true-peak invariant. fs/4 at 45°: every sample sits at ±0.7071 of
    # the real amplitude, so the sample peak is 3.01 dB under the true one and
    # a build reporting the sample peak as the true peak cannot pass.
    "fs4.wav": (
        "0.5*sin(2*PI*12000*t+PI/4)", "0.5*sin(2*PI*12000*t+PI/4)", 1,
    ),
}


def write_fixtures():
    """Every fixture, rewritten. A stale fixture is a fixture that can lie,
    and each of these is under a second of ffmpeg."""
    os.makedirs(FIXTURES, exist_ok=True)
    for name, (left, right, seconds) in FIXTURE_EXPRESSIONS.items():
        path = os.path.join(FIXTURES, name)
        subprocess.run(
            [
                "ffmpeg", "-v", "error", "-y", "-f", "lavfi",
                # The expression is SINGLE-QUOTED inside the filter
                # description, which is lavfi's own escape and not the
                # shell's: `between(t,0,1.5)` holds commas, and an unquoted
                # one is read as the end of the option and then as three more
                # of them ("No option name near '48000:d=3'").
                "-i", f"aevalsrc='{left}|{right}':s={RATE}:d={seconds}",
                "-c:a", "pcm_s16le", path,
            ],
            check=True,
        )
    return FIXTURES


# ---- one project ----------------------------------------------------------


class Session:
    """One project, and the exports taken off it. `phase2_proof.py`'s shape
    with the audio accessors kept and the frame ones dropped: nothing in
    phase 5 is a picture."""

    def __init__(self, mcp, name):
        self.mcp = mcp
        # `<name>-<pid>.reelcut`, never a fixed name: a `project` path is
        # matched against every open document and no tool closes one, so an
        # earlier run's SAVED package would have the app answering for it.
        for stale in os.listdir(WORK):
            if re.fullmatch(rf"{re.escape(name)}-\d+\.reelcut", stale):
                shutil.rmtree(os.path.join(WORK, stale))
        self.name = name
        self.path = os.path.join(WORK, f"{name}-{os.getpid()}.reelcut")
        mcp.call("new_project", path=self.path)

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def media(self, name):
        """A fixture imported, and its waveform WAITED FOR.

        `cache/peaks/<id>.bin` is written by a fire-and-forget task at import,
        so a normalise issued in the same breath as the import legitimately
        answers "still being analysed" — measured, on the second clip of a
        two-clip fixture, before this wait existed. Waiting here is what makes
        every 5c measurement deterministic, and it leaves that refusal to be
        reached the one way a script can reach it on purpose: by deleting the
        file."""
        path = os.path.join(FIXTURES, name)
        # Importing one path twice is an identity edit and comes back as the
        # standard "made no change" refusal, so a fixture wanted on two tracks
        # is looked up rather than imported again.
        already = {m["path"]: m["id"] for m in self.project()["media"]}
        media = already[path] if path in already else self.op(
            "import_media", path=path)["media"]
        peaks = self.peaks_file(media)
        for _ in range(300):
            if os.path.exists(peaks):
                return media
            time.sleep(0.05)
        raise RuntimeError(f"{self.name}: {os.path.basename(peaks)} was never written")

    def place(self, name, at=0, track=None):
        """A clip of a fixture, on `track` or the first one."""
        media = self.media(name)
        track = track if track is not None else self.tracks()[0]
        return self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def add_track(self):
        self.mcp.call_with("add_track", {"project": self.path})
        return self.tracks()[-1]

    def export(self, label, preset="audio_wav", **kwargs):
        """One export into work/, at a path of this session's own. The tool
        replaces the extension with the container's, so the file is read out
        of the result rather than assumed."""
        target = os.path.join(WORK, f"{self.name}-{os.getpid()}-{label}")
        result = self.op("export", preset=preset, path=target, **kwargs)
        return result

    def wav(self, label, **kwargs):
        """(the file's bytes, its decoded PCM, the result) of one WAV export."""
        result = self.export(label, **kwargs)
        with open(result["path"], "rb") as handle:
            return handle.read(), pcm(result["path"]), result

    def peaks_file(self, media):
        return os.path.join(self.path, "cache", "peaks", f"{media}.bin")

    def error(self, tool, **kwargs):
        """The in-band error text of a call, or None when it succeeded."""
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def undo(self):
        return self.op("undo")["undone"]


# ---- the catalog ----------------------------------------------------------


def catalog_part(mcp):
    """The EXACT tool count, which is this script's job now, and the shape of
    what phase 5 added to the catalog."""
    print("catalog")
    names = mcp.tools()
    # A FLOOR, not an equality. It was `==` while phase 5 was the newest
    # phase, because the exact count is the only thing that tells a stale
    # binary on the port from the build under test — but that job belongs to
    # whichever phase is newest, and phase 6 took it over with two background
    # tools. Phase 4 handed the same duty to phase 5 the same way.
    check(
        len(names) >= TOOLS,
        f"the catalog holds phase 5's {TOOLS} tools or more (got {len(names)})",
    )
    check("normalize_clip" in names, "normalize_clip is a tool")

    schemas = mcp.schemas()

    def schema_of(name):
        """One tool's schema, or a stand-in that fails every check below
        rather than aborting: a binary missing the tool is exactly the case
        these exist for, and it should read as failures and not a traceback."""
        found = schemas.get(name)
        if found is None:
            return {"properties": {}, "required": ["(no such tool)"], "description": ""}
        return found["inputSchema"]

    normalize = schema_of("normalize_clip")
    check(
        set(normalize["properties"]) == {"clips", "peak_db", "project"},
        f"normalize_clip declares clips and peak_db (and project): "
        f"{sorted(normalize['properties'])}",
    )
    check(
        normalize["required"] == ["clips"],
        f"and requires clips — a whole-timeline normalise is not a thing "
        f"({normalize['required']})",
    )
    peak = normalize["properties"].get("peak_db", {})
    check(
        peak.get("type") == "number" and peak.get("minimum") == -60
        and peak.get("maximum") == 0,
        f"with peak_db a number bounded −60…0 dBFS: {peak.get('minimum')}…{peak.get('maximum')}",
    )
    told = schemas.get("normalize_clip", {}).get("description", "")
    check(
        "REPLACES volume" in told and "4×" in told,
        "normalize_clip's description states the two decisions a caller has to know: it "
        "REPLACES the volume, and the model's 4× ceiling can stop it short",
    )

    export = schema_of("export")
    for key, low, high in [("loudness_lufs", -70, 0), ("peak_dbtp", -20, 0)]:
        field = export["properties"].get(key, {})
        check(
            field.get("type") == "number" and field.get("minimum") == low
            and field.get("maximum") == high,
            f"export declares {key} as a number bounded {low}…{high}: "
            f"{field.get('minimum')}…{field.get('maximum')}",
        )
    check(
        "REFUSED" in export["properties"].get("peak_dbtp", {}).get("description", ""),
        "and says peak_dbtp on its own is REFUSED rather than accepted and left inert",
    )

    patch = schema_of("set_audio")["properties"].get("patch", {}).get("description", "")
    check("mono" in patch, "set_audio's patch description names mono")


# ---- 5a: the mono fold ----------------------------------------------------


def mono_part(mcp):
    """Three claims off one asymmetric fixture. The negative control comes
    first: if the two channels of the `mono` off export were already equal,
    everything below would be true of a build with no fold in it."""
    print("\n5a — mix to mono")
    s = Session(mcp, "phase5-mono")
    clip = s.place("lr.wav")

    off_bytes, off, _ = s.wav("off")
    left, right = sides(off)
    apart = sum(1 for a, b in zip(left, right) if a != b)
    check(
        len(left) == 2 * RATE and apart > len(left) // 2,
        f"the fixture's channels really do differ with mono OFF, or nothing below would be "
        f"a check at all ({apart} of {len(left)} frames differ; peaks "
        f"{max(map(abs, left))} left, {max(map(abs, right))} right)",
    )

    s.op("set_audio", clips=[clip], patch={"mono": True})
    check(s.clip(clip)["audio"]["mono"] is True, "set_audio {mono: true} lands on the clip")
    on_bytes, on, _ = s.wav("on")
    on_left, on_right = sides(on)
    mismatches = sum(1 for a, b in zip(on_left, on_right) if a != b)
    check(
        len(on_left) == len(left) and mismatches == 0,
        f"with mono ON the left channel equals the right SAMPLE FOR SAMPLE "
        f"({mismatches} of {len(on_left)} frames differ)",
    )
    # An average, not a copy. Both channels of the mono file should sit within
    # one 16-bit LSB of the mean of the two the same timeline wrote unfolded —
    # one LSB because the fold happens in float, before the quantisation the
    # unfolded file already carries. A build that copied the left channel over
    # the right would be out by half the difference between them, which is
    # thousands of LSBs here.
    worst = max(abs(m - (a + b) / 2) for m, a, b in zip(on_left, left, right))
    check(
        worst <= 1,
        f"and each of those samples is the MEAN of the two unfolded channels, within one "
        f"16-bit LSB (worst {worst})",
    )
    check(on_bytes != off_bytes, "so the mono file is not the unfolded file")

    s.op("set_audio", clips=[clip], patch={"mono": False})
    check(s.clip(clip)["audio"]["mono"] is False, "set_audio {mono: false} clears it")
    back_bytes, back, _ = s.wav("back")
    check(
        back_bytes == off_bytes,
        f"and with mono off again the export is BYTE-IDENTICAL to the one taken before it "
        f"was ever set — the fold costs a project that does not ask for it nothing "
        f"({describe(off, back)})",
    )


# ---- 5a: the fold a NEST clip asks for ------------------------------------


def nest_mono_part(mcp):
    """The same checkbox, on a NEST clip, which is where it used to do nothing.

    A nest clip's id names no audio segment — the plan replaced it with the
    clips inside it (`nest.rs`), so every segment carries an INNER id — and
    `AudioDSPParameters` is keyed by clip id. A `mono` written on a nest clip
    was therefore accepted by the core, kept lit by the checkbox, saved with
    the project and folded nothing at all, in preview and in export alike,
    until the parameters carried it down to the contents.

    The inner clip is panned HARD LEFT before it is nested, and that is what
    makes this more than a second run of 5a. Carried down to the head of the
    inner clip's Mix stage the fold would run BEFORE that pan and the file
    would come back hard left — one channel loud, the other silent — so only
    a fold at the TAIL of the inner chain, which is the fold of the nest's own
    mix, can put equal samples in both channels. Three builds are told apart
    by one comparison: no fold at all (the fixture's own two channels), a fold
    at the head (left loud, right silent) and the fold this ships.
    """
    print("\n5a — mix to mono on a nest clip")
    s = Session(mcp, "phase5-nest-mono")
    clip = s.place("lr.wav")
    s.op("set_audio", clips=[clip], patch={"pan": -1})
    nested = s.op("nest", clips=[clip])["new_clips"][0]
    check(
        s.clip(nested)["source"]["kind"] == "nest" and s.clip(nested).get("audio") is not None,
        "nest collapses the panned clip into a nest clip that carries audio props",
    )

    off_bytes, off, _ = s.wav("nest-off")
    left, right = sides(off)
    apart = sum(1 for a, b in zip(left, right) if a != b)
    check(
        len(left) == 2 * RATE and apart > len(left) // 2,
        f"the nest's two channels really do differ with mono OFF — the pan alone sees to "
        f"that ({apart} of {len(left)} frames differ; peaks {max(map(abs, left))} left, "
        f"{max(map(abs, right))} right)",
    )

    s.op("set_audio", clips=[nested], patch={"mono": True})
    check(
        s.clip(nested)["audio"]["mono"] is True,
        "set_audio {mono: true} lands on the NEST clip",
    )
    on_bytes, on, _ = s.wav("nest-on")
    on_left, on_right = sides(on)
    mismatches = sum(1 for a, b in zip(on_left, on_right) if a != b)
    check(
        len(on_left) == len(left) and mismatches == 0,
        f"and the nest's contents are folded: left equals right SAMPLE FOR SAMPLE "
        f"({mismatches} of {len(on_left)} frames differ)",
    )
    # Not the trivial way to make two channels equal. A fold that ran before
    # the inner pan would leave the right channel at zero, and a bug that
    # silenced the nest would leave both there.
    check(
        max(map(abs, on_left)) > 8000 and max(map(abs, on_right)) > 8000,
        f"in a file that is still LOUD in both channels, not silenced into agreement "
        f"(peaks {max(map(abs, on_left))} left, {max(map(abs, on_right))} right)",
    )
    worst = max(abs(m - (a + b) / 2) for m, a, b in zip(on_left, left, right))
    check(
        worst <= 1,
        f"and each sample is the MEAN of the two channels the same nest wrote UNFOLDED, "
        f"within one 16-bit LSB — the fold is of what the pan produced, not of what it "
        f"was handed (worst {worst})",
    )

    s.op("set_audio", clips=[nested], patch={"mono": False})
    back_bytes, back, _ = s.wav("nest-back")
    check(
        back_bytes == off_bytes,
        f"and clearing it writes the earlier nested export back BYTE-IDENTICALLY "
        f"({describe(off, back)})",
    )


# ---- 5c: Normalise Clip ---------------------------------------------------


def normalize_part(mcp):
    """The gain is read back off the tool and then MEASURED on a file."""
    print("\n5c — Normalise Clip: the level that was written")
    s = Session(mcp, "phase5-normalize")
    clip = s.place("half.wav")

    _, before, _ = s.wav("before")
    plain = db(sample_peak(channels(before)))
    check(
        close(plain, -6.0206, 0.05),
        f"the fixture exports at −6.02 dBFS before anything is normalised ({fmt(plain)})",
    )

    answer = s.op("normalize_clip", clips=[clip])
    row = answer["normalized"][0]
    check(
        row["clip"] == clip and close(row["measured_db"], -6.0206, 0.05),
        f"normalize_clip measures the clip at −6.02 dBFS ({fmt(row['measured_db'])})",
    )
    check(
        close(row["volume"], 1.7825, 0.001) and close(row["result_db"], -1.0, 0.001)
        and row["clamped"] is False,
        f"and writes volume {row['volume']:.4f}, claiming −1 dBFS ({fmt(row['result_db'])})",
    )
    check(
        close(s.clip(clip)["audio"]["volume"], row["volume"], 1e-9),
        "the clip's own audio.volume is that number",
    )

    _, after, _ = s.wav("after")
    measured = db(sample_peak(channels(after)))
    check(
        close(measured, -1.0, 0.1),
        f"and the EXPORT's loudest sample lands at −1 dBFS within ±0.1 ({fmt(measured)})",
    )

    check(
        "made no change" in (s.error("normalize_clip", clips=[clip]) or ""),
        "a second call is an identity edit and is refused as one — normalise REPLACES the "
        "volume rather than multiplying it (D-C3)",
    )
    s.undo()
    check(
        close(s.clip(clip)["audio"]["volume"], 1.0, 1e-9),
        "one undo step puts the volume back",
    )
    _, undone, _ = s.wav("undone")
    check(
        undone == before,
        f"and the export is byte-identical to the one before the normalise "
        f"({describe(before, undone)})",
    )

    # D-C7: the 4× ceiling. A −40 dBFS tone cannot reach −1, so it is
    # normalised as far as it goes and SAYS where it landed. This is the check
    # that a build reporting the requested level instead of the reached one
    # fails, and it is measured on the file rather than read off the result.
    print("\n5c — the 4× clamp: the level it actually reached")
    q = Session(mcp, "phase5-clamp")
    quiet = q.place("quiet.wav")
    answer = q.op("normalize_clip", clips=[quiet])
    row = answer["normalized"][0]
    check(
        row["clamped"] is True and close(row["volume"], 4.0, 1e-9),
        f"a −40 dBFS clip is clamped at the model's 4× ({row['volume']})",
    )
    check(
        close(row["result_db"], -27.96, 0.05),
        f"and reports the level it ACTUALLY reached, −27.96 dBFS, not the −1 it was asked "
        f"for ({fmt(row['result_db'])})",
    )
    check(
        "note" in answer and str(quiet) in answer["note"] and "4×" in answer["note"],
        f"with a note naming the clip and the ceiling: {answer.get('note', '')[:90]!r}",
    )
    _, clamped, _ = q.wav("clamped")
    measured = db(sample_peak(channels(clamped)))
    check(
        close(measured, row["result_db"], 0.1),
        f"and the EXPORT holds that level rather than −1 ({fmt(measured)})",
    )

    # The refusals, each read for the words that name the clip.
    print("\n5c — the refusals, by name")
    r = Session(mcp, "phase5-refuse")
    silent = r.place("silent.wav")
    good = r.place("half.wav", track=r.add_track())
    message = r.error("normalize_clip", clips=[silent]) or ""
    check(
        f"clip {silent}" in message and "silent over the part of it that plays" in message,
        f"a silent clip is refused by name: {message[:110]!r}",
    )
    answer = r.op("normalize_clip", clips=[silent, good])
    check(
        [row["clip"] for row in answer["normalized"]] == [good]
        and answer.get("skipped") == [
            f"clip {silent}: is silent over the part of it that plays, so there is no "
            "level to normalise."
        ],
        "and in a mixed call one job's failure is one job's problem: the good clip is "
        f"normalised and the other is reported under skipped ({answer.get('skipped')})",
    )

    n = Session(mcp, "phase5-nopeaks")
    unread = n.place("half.wav")
    media = n.clip(unread)["source"]["media"]
    peaks = n.peaks_file(media)
    check(os.path.exists(peaks), f"the peaks cache is on disk at cache/peaks/{media}.bin")
    # "Not analysed yet" is a race in real life and a deletion here: the
    # loader reads the file fresh on every call, so removing it is the
    # deterministic spelling of the state the app reaches at import.
    os.remove(peaks)
    message = n.error("normalize_clip", clips=[unread]) or ""
    check(
        f"clip {unread}" in message and "waveform has not been written" in message,
        f"a clip whose peaks are not on disk is refused by name — never normalised against "
        f"a missing cache: {message[:110]!r}",
    )
    message = n.error("normalize_clip", clips=[9999]) or ""
    check("9999" in message, f"and an id that is not a clip is refused by name: {message[:80]!r}")
    # The argument is named and the bound is quoted; the offending VALUE is
    # not, which is this server's own house style rather than the core's —
    # `AgentServer+Silence.swift`'s `threshold_db` refusal reads the same way.
    message = r.error("normalize_clip", clips=[good], peak_db=5) or ""
    check(
        "peak_db" in message and "0" in message and "request to clip" in message,
        f"peak_db above 0 dBFS is a request to clip and is refused BY NAME rather than "
        f"clamped: {message[:110]!r}",
    )

    # A NEST, which is the one refusal the segment test cannot describe. The
    # plan FLATTENS a nest, so every segment under one carries an INNER clip's
    # id and `segments[nest]` is empty — the same emptiness a still or a silent
    # movie produces, and a wholly different fact about the timeline. So the
    # premise is MEASURED first (the nest is exporting sound at the level its
    # inner clip holds) and the refusal is then read for what it says: a clip
    # you can hear must not be told it plays no sound. Without the nest arm in
    # `AudioNormalize.read` this reads "plays no sound in this timeline", which
    # is the false sentence, and both halves of the check fail.
    print("\n5c — a nest is refused as a nest")
    g = Session(mcp, "phase5-nest")
    inner = g.place("half.wav")
    nested = g.op("nest", clips=[inner])["new_clips"][0]
    check(
        g.clip(nested)["source"]["kind"] == "nest"
        and g.clip(nested).get("audio") is not None,
        "the nest clip carries audio properties of its own, which is why the button and the "
        "menu item are offered on it at all (`InspectorTab.hasAudio` asks exactly that)",
    )
    _, heard, _ = g.wav("nest")
    level = db(sample_peak(channels(heard)))
    check(
        close(level, -6.0206, 0.05),
        f"and the nest AUDIBLY plays: its export holds the inner clip's −6.02 dBFS "
        f"({fmt(level)})",
    )
    message = g.error("normalize_clip", clips=[nested]) or ""
    check(
        f"clip {nested}" in message and "is a nest" in message
        and "plays no sound" not in message,
        f"so it is refused AS A NEST — no level of its own, the peaks cache being per media "
        f"file — and never as a clip that plays no sound: {message[:150]!r}",
    )
    beside = g.place("half.wav", track=g.add_track())
    answer = g.op("normalize_clip", clips=[nested, beside])
    check(
        [row["clip"] for row in answer["normalized"]] == [beside]
        and len(answer.get("skipped", [])) == 1
        and "is a nest" in answer["skipped"][0],
        f"and in a mixed call the ordinary clip is still normalised, the nest reported under "
        f"skipped ({answer.get('skipped')})",
    )

    # D-C6's mirror. Nothing but a fixture whose two halves differ can tell a
    # mirrored window from an unmirrored one: both read the same file, both
    # answer a plausible number, and only one of them is right.
    print("\n5c — the reversed mirror")
    v = Session(mcp, "phase5-reversed")
    forward = v.place("ramp.wav")
    v.op("trim_end", clip=forward, to=int(1.4 * SEC))
    backward = v.place("ramp.wav", track=v.add_track())
    v.op("set_reversed", clip=backward, reversed=True)
    v.op("trim_end", clip=backward, to=int(1.4 * SEC))
    rows = {row["clip"]: row for row in v.op("normalize_clip", clips=[forward, backward])["normalized"]}
    check(
        close(rows[forward]["measured_db"], -6.0206, 0.05),
        f"the forward clip's first 1.4 s measures the fixture's LOUD half "
        f"({fmt(rows[forward]['measured_db'])} dBFS)",
    )
    check(
        close(rows[backward]["measured_db"], -26.02, 0.2),
        f"and the REVERSED clip's first 1.4 s measures its quiet half, 20 dB down — the "
        f"window mirrored about the media's duration, not read off the wrong end "
        f"({fmt(rows[backward]['measured_db'])} dBFS)",
    )


# ---- 5d: loudness on export ------------------------------------------------


def loudness_part(mcp):
    """BS.1770-4, measured HERE over the written file. The app's report is
    asserted against this script's measurement, never in place of it."""
    print("\n5d — loudness on export: measured, not reported")
    s = Session(mcp, "phase5-loudness")
    s.place("half.wav")

    off_bytes, off, plain = s.wav("off")
    report = plain["loudness"]
    mine = integrated(channels(off))
    check(
        close(report.get("integrated_lufs"), mine, 0.1),
        f"an un-normalised export reports its own integrated loudness, and this script's "
        f"BS.1770-4 pass over the file agrees within ±0.1 LU "
        f"({fmt(report.get('integrated_lufs'))} reported, {fmt(mine)} measured)",
    )
    check(
        report["gain_db"] == 0 and "target_lufs" not in report,
        f"with no target and no gain — every export measures itself, normalised or not "
        f"({report['gain_db']}, target {report.get('target_lufs')})",
    )
    check(
        report["true_peak_dbtp"] >= report["sample_peak_dbfs"],
        f"and true peak is not below sample peak ({fmt(report['true_peak_dbtp'])} dBTP vs "
        f"{fmt(report['sample_peak_dbfs'])} dBFS)",
    )

    again_bytes, again, _ = s.wav("off2")
    check(
        again_bytes == off_bytes,
        f"two un-normalised exports of this duck-free, fade-free timeline are "
        f"byte-identical, so a difference below is the gain and nothing else "
        f"({describe(off, again)})",
    )

    norm_bytes, norm, normalized = s.wav("lufs14", loudness_lufs=-14, peak_dbtp=-1)
    landed = integrated(channels(norm))
    check(
        close(landed, -14.0, 0.5),
        f"a −14 LUFS export MEASURES −14 LUFS within ±0.5 LU over the file this script "
        f"decoded ({fmt(landed)})",
    )
    check(
        close(normalized["loudness"].get("integrated_lufs"), landed, 0.1),
        f"and the number the tool echoes is that same one within ±0.1 LU "
        f"({fmt(normalized['loudness'].get('integrated_lufs'))} reported)",
    )
    check(
        normalized["loudness"]["target_lufs"] == -14
        and normalized["loudness"]["ceiling_dbtp"] == -1
        and normalized["loudness"]["capped_by_peak"] is False,
        f"the target and the ceiling are echoed as asked, uncapped: {normalized['loudness']}",
    )
    check(
        norm_bytes != off_bytes,
        "and the normalised file is not the un-normalised one",
    )
    # The gain is ONE scalar over everything, which is what makes the reported
    # figure arithmetic rather than a guess: every sample of the normalised
    # file is the un-normalised one times it, to within the rounding both
    # files already carry.
    gain = 10 ** (normalized["loudness"]["gain_db"] / 20)
    worst = max(abs(b - a * gain) for a, b in zip(samples(off), samples(norm)))
    check(
        worst <= 2,
        f"every sample of the normalised export is the un-normalised one times the reported "
        f"gain, within 2 LSB of the rounding both carry (worst {worst})",
    )

    # The ceiling, where it actually bites. A 19 dB peak-to-loudness ratio
    # means −14 LUFS would need +5.8 dB and the peak has −0.6 dB of room, so
    # the file must land QUIETER than the target and say so.
    print("\n5d — the true-peak ceiling, where it bites")
    c = Session(mcp, "phase5-crest")
    c.place("crest.wav")
    _, capped, result = c.wav("capped", loudness_lufs=-14, peak_dbtp=-1)
    report = result["loudness"]
    check(
        report["capped_by_peak"] is True,
        f"a −14 LUFS target over a peaky programme is capped by the −1 dBTP ceiling "
        f"({report['capped_by_peak']}, gain {report['gain_db']})",
    )
    check(
        report["true_peak_dbtp"] <= -1.0 + 1e-9,
        f"the reported true peak does not exceed the ceiling ({fmt(report['true_peak_dbtp'])} "
        "dBTP)",
    )
    peak = db(true_peak(channels(capped)))
    check(
        peak <= -1.0 + 0.3,
        f"and this script's own 4× oversampling pass over the file agrees within the "
        f"±0.3 dB true peak is measured to ({fmt(peak)} dBTP)",
    )
    check(
        close(peak, report["true_peak_dbtp"], 0.3),
        f"the two true-peak measurements agree ({fmt(peak)} here, "
        f"{fmt(report['true_peak_dbtp'])} reported)",
    )
    landed = integrated(channels(capped))
    check(
        landed < -14.0 - 3,
        f"and the file lands well BELOW the target it was asked for, which is what a "
        f"ceiling that bites means ({fmt(landed)} LUFS against −14)",
    )

    # The ceiling swept ACROSS the gain's 0.01 dB grid. One export can only
    # ask about one measured true peak, and whether a round-to-nearest
    # quantisation of the cap lands over the ceiling or under it depends on
    # where that peak falls in the grid — so a single fixture answers this by
    # coin toss. Five ceilings 0.002 dB apart move the same peak through five
    # phases of one 0.01 dB step, and five points spaced a fifth of a step
    # apart cannot all miss the half of it that rounds the wrong way.
    # `phase5_chrome.py`'s section 9 sweeps 200 peaks against the same
    # arithmetic without exporting anything; this is the end-to-end half.
    ceilings = [-1.0, -1.002, -1.004, -1.006, -1.008]
    reports = []
    for index, ceiling in enumerate(ceilings):
        # `export` rather than `wav`: the claim is about the REPORT, and the
        # file each of these five wrote is the one the check above already
        # decoded and measured.
        swept = c.export(f"sweep{index}", loudness_lufs=-14, peak_dbtp=ceiling)
        reports.append(swept["loudness"])
    over = [
        (ceiling, r["true_peak_dbtp"]) for ceiling, r in zip(ceilings, reports)
        if r["true_peak_dbtp"] > ceiling + 1e-9
    ]
    check(
        not over,
        f"and no ceiling in a five-step sweep across the gain's 0.01 dB grid is EXCEEDED "
        f"— the cap is quantised toward more attenuation, never toward less "
        f"({'all five at or under' if not over else over})",
    )
    # The same five, under the round-to-NEAREST the cap used to get: the
    # measured peak is the report's own true peak less its gain, so this is
    # arithmetic over what the app just answered rather than a second guess.
    nearest = [
        ceiling for ceiling, r in zip(ceilings, reports)
        if round((ceiling - (r["true_peak_dbtp"] - r["gain_db"])) / 0.01) * 0.01
        > (ceiling - (r["true_peak_dbtp"] - r["gain_db"])) + 1e-12
    ]
    check(
        len(nearest) >= 1,
        f"…and the sweep is not vacuous: {len(nearest)} of the five would have landed "
        f"over the ceiling had the cap been rounded to the NEAREST hundredth "
        f"({[f'{x:g}' for x in nearest]})",
    )

    # A mix past full scale, which is the one case where the report cannot be
    # the file's. The measure pass reads 32-bit float on purpose; the write
    # pass decodes the same mix to Int16, which SATURATES before the gain is
    # applied. So the file holds the mix hard-clipped and then turned down,
    # and every figure the phase publishes was computed from the other one.
    # It has to say so.
    print("\n5d — a mix past full scale: whose numbers the report is")
    o = Session(mcp, "phase5-overscale")
    hot_clip = o.place("half.wav")
    # A half-scale tone at the model's 4× ceiling: +6 dBFS of mix, which is
    # what two normalised clips on two tracks would also give.
    o.op("set_audio", clips=[hot_clip], patch={"volume": 4})
    _, hot, hot_result = o.wav("hot", loudness_lufs=-14, peak_dbtp=-1)
    report = hot_result["loudness"]
    mix_peak = report["sample_peak_dbfs"] - report["gain_db"]
    check(
        mix_peak > 1.0,
        f"the mix really did pass full scale, or nothing below is a check — the measure "
        f"pass reads float and saw {fmt(mix_peak)} dBFS before the gain",
    )
    check(
        "clipped" in report["summary"],
        f"and the report SAYS the mix clipped, in the one line both consumers show — "
        f"the sheet's last line and this tool's summary ({report['summary']})",
    )
    written = integrated(channels(hot))
    check(
        written is not None
        and abs(written - report["integrated_lufs"]) > 0.5,
        f"…which it must, because the file this script decoded is {fmt(written)} LUFS "
        f"against the {fmt(report['integrated_lufs'])} reported — further apart than the "
        f"±0.5 LU an unqualified figure would be promising",
    )
    check(
        "clipped" not in plain["loudness"]["summary"],
        f"while an export INSIDE full scale says nothing of the sort, so the sentence "
        f"means something ({plain['loudness']['summary']})",
    )

    # The two invariants a tolerance alone cannot carry. fs/4 at 45° is the
    # signal whose every sample sits 3.01 dB under its real amplitude.
    print("\n5d — true peak is not sample peak")
    f = Session(mcp, "phase5-fs4")
    f.place("fs4.wav")
    _, sine, result = f.wav("fs4")
    report = result["loudness"]
    check(
        report["true_peak_dbtp"] >= report["sample_peak_dbfs"] + 2.5,
        f"a 45° fs/4 sine reads at least 2.5 dB above its own sample peak — a build "
        f"reporting the sample peak as the true one cannot ({fmt(report['true_peak_dbtp'])} "
        f"dBTP against {fmt(report['sample_peak_dbfs'])} dBFS)",
    )
    here = db(true_peak(channels(sine)))
    check(
        close(here, report["true_peak_dbtp"], 0.3),
        f"and this script's pass over the file agrees within ±0.3 dB ({fmt(here)})",
    )
    check(
        close(db(sample_peak(channels(sine))), report["sample_peak_dbfs"], 0.001),
        f"while the SAMPLE peaks agree exactly, as two counts of the same maximum should "
        f"({fmt(db(sample_peak(channels(sine))))} against {fmt(report['sample_peak_dbfs'])})",
    )


# ---- 5d: the two overrides ------------------------------------------------


def overrides_part(mcp):
    """`loudness_lufs` and `peak_dbtp`: accepted, echoed, and each refusal
    naming the value the way the bitrate ones do."""
    print("\n5d — the overrides")
    s = Session(mcp, "phase5-overrides")
    s.place("half.wav")

    result = s.export("custom", loudness_lufs=-14.5, peak_dbtp=-2.5)
    check(
        result["loudness"]["target_lufs"] == -14.5
        and result["loudness"]["ceiling_dbtp"] == -2.5,
        f"a fractional target and ceiling are accepted and echoed back "
        f"({result['loudness']['target_lufs']}, {result['loudness']['ceiling_dbtp']})",
    )
    result = s.export("noceiling", loudness_lufs=-20)
    check(
        result["loudness"]["ceiling_dbtp"] == 0,
        f"a target with no ceiling gets full scale, which is 'do not push it past 0 dBTP' "
        f"({result['loudness']['ceiling_dbtp']})",
    )

    for arguments, wanted in [
        ({"loudness_lufs": -80}, ["loudness_lufs", "-70 to 0", "-80"]),
        ({"loudness_lufs": 5}, ["loudness_lufs", "-70 to 0", "5"]),
        ({"loudness_lufs": -14, "peak_dbtp": -25}, ["peak_dbtp", "-20 to 0", "-25"]),
        ({"loudness_lufs": -14, "peak_dbtp": 3}, ["peak_dbtp", "-20 to 0", "3"]),
    ]:
        message = s.error(
            "export", preset="audio_wav",
            path=os.path.join(WORK, f"{s.name}-{os.getpid()}-bad"), **arguments) or ""
        check(
            all(word in message for word in wanted),
            f"{arguments} is refused by name, with the value in the message: {message[:110]!r}",
        )

    message = s.error(
        "export", preset="audio_wav",
        path=os.path.join(WORK, f"{s.name}-{os.getpid()}-bad"), peak_dbtp=-1) or ""
    check(
        "peak_dbtp" in message and "loudness_lufs" in message and "gain-only" in message,
        f"and a ceiling with no target is refused rather than accepted and left inert — "
        f"normalisation is gain-only, so it would have nothing to cap: {message[:130]!r}",
    )
    message = s.error(
        "export", preset="audio_wav",
        path=os.path.join(WORK, f"{s.name}-{os.getpid()}-bad"), loudness_lufs="loud") or ""
    check(
        "loudness_lufs" in message and "number" in message,
        f"a target that is not a number is refused by name too: {message[:110]!r}",
    )


# ---- 5e: WAV and AIFF -----------------------------------------------------


def lpcm_part(mcp):
    """The two new rows: what ffprobe says they are, that they carry the same
    samples, and that neither went near `ImageSequenceWriter`."""
    print("\n5e — WAV and AIFF")
    s = Session(mcp, "phase5-lpcm")
    s.place("half.wav")

    wav = s.export("pcm", preset="audio_wav")
    aiff = s.export("pcm", preset="audio_aiff")
    check(
        wav["path"].endswith(".wav") and aiff["path"].endswith(".aiff"),
        f"each row writes its own container's extension ({os.path.basename(wav['path'])}, "
        f"{os.path.basename(aiff['path'])})",
    )
    check(
        wav["codec"] == "lpcm" and aiff["codec"] == "lpcm",
        f"both rows resolve to the codec lpcm ({wav['codec']}, {aiff['codec']})",
    )
    wav_stream, aiff_stream = probe(wav["path"]), probe(aiff["path"])
    check(
        wav_stream.get("codec_name") == "pcm_s16le"
        and wav_stream.get("sample_rate") == "48000"
        and wav_stream.get("channels") == 2,
        f"ffprobe reads the WAV as 48 kHz 16-bit stereo PCM: {wav_stream}",
    )
    check(
        aiff_stream.get("codec_name") == "pcm_s16be"
        and aiff_stream.get("sample_rate") == "48000"
        and aiff_stream.get("channels") == 2,
        f"and the AIFF as the same thing BIG-endian, which is the container's decision "
        f"and not the encoder's: {aiff_stream}",
    )
    wav_pcm, aiff_pcm = pcm(wav["path"]), pcm(aiff["path"])
    check(
        wav_pcm == aiff_pcm and len(wav_pcm) == 3 * RATE * 4,
        f"and the WAV and the AIFF of one project decode to IDENTICAL PCM "
        f"({describe(wav_pcm, aiff_pcm)})",
    )

    # Three ways of saying the same thing about the routing: an image-sequence
    # writer refuses an unknown container outright, writes no audio track at
    # all, and gets no loudness measurement — so a WAV that came back with
    # samples in it AND a loudness block did not go that way.
    check(
        "loudness" in wav and "loudness" in aiff,
        "both carry a loudness block, which `Exporter.measuresLoudness` withholds from "
        "every image sequence",
    )
    # And past the cap that writer would refuse at: seven 3 s clips is 21 s,
    # 630 frames at the document's 30 fps, where `ImageSequenceWriter.maxFrames`
    # is 600.
    long = Session(mcp, "phase5-long")
    track = long.tracks()[0]
    media = long.media("half.wav")
    for index in range(7):
        long.op("add_clip", track=track, media=media, at=index * 3 * SEC)
    result = long.export("long", preset="audio_wav")
    check(
        result["duration"] == 21 * SEC and result["fps"] == [30, 1],
        f"a 21 s timeline at 30 fps is 630 frames ({result['duration']} ticks at "
        f"{result['fps']})",
    )
    frames = len(pcm(result["path"])) // 4
    check(
        frames == 21 * RATE,
        f"and it exports as WAV with all 21 seconds of samples in it — past the 600-frame "
        f"cap the image writer refuses at ({frames} audio frames)",
    )

    # The contrast, so "no loudness block" means something: the same timeline
    # written by the image path really does report none.
    s.op("set_range", start=0, end=SEC)
    picture = s.export("gif", preset="gif", range="in_out")
    check(
        "loudness" not in picture,
        f"while a GIF of the same project — the image path — reports no loudness at all, "
        f"which is what the block above distinguishes ({sorted(picture)})",
    )


def main():
    os.makedirs(WORK, exist_ok=True)
    write_fixtures()
    mcp = MCP(SOCKET)
    catalog_part(mcp)
    mono_part(mcp)
    nest_mono_part(mcp)
    normalize_part(mcp)
    loudness_part(mcp)
    overrides_part(mcp)
    lpcm_part(mcp)
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
    except (ToolError, AssertionError, KeyError, IndexError, RuntimeError, OSError,
            subprocess.CalledProcessError) as error:
        summary(aborted=f"{type(error).__name__}: {error}")
