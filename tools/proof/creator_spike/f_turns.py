#!/usr/bin/env python3
"""F-TURNS (road map "creator-jobs" SW2a, spec §11 SW-27): two people talking,
made on the Mac, with their truth measured.

Samantha (A) and Daniel (B) read a scripted turn table through `say -v`. Each
utterance becomes a SOLO stem first (48 kHz mono, its active part at −26 dBFS
RMS); each microphone is its own stem at 0 dB, the other stem at the bleed
and seeded pink noise at the floor's RMS dBFS, written 24-bit:
`mic_{a,b}_b{12,18,24}_f{55,45}.wav`. A turn's onset is the first sample of
its solo stem above −40 dBFS. The cameras are flat colour cards, 1920×1080 at
30 fps, H.264, no audio, with a 16-block binary frame code along the bottom
(bit 0 leftmost): `cam_a_1.mov` and `cam_a_2.mov` abutting at a frame
mid-way, `cam_b.mov` and `cam_wide.mov`.

The table holds turns of 3 s or more, two replies of 0.6 s or less in 0.8 s
gaps (which must not cut), one crosstalk passage of 2.5 s or more followed by
a pause of 0.6 s or more, and one silence of 3 s or more. `manifest.json`
holds the variants, the cameras, the turns with onsets and the expected
shots `[{angle, onset}]`, WRITTEN FROM THIS TABLE'S DESIGN (the range opens
on the wide; a turn by someone other than the shot's person cuts to them; a
reply never cuts; crosstalk cuts to the wide; silence holds) — never by the
planner's code.

Output: tools/proof/media/creator/f_turns/ (gitignored), reused while the
manifest's `generator_sha256` equals this script's; `--force` rebuilds.
Exit 2 (skipped by name) when `say -v Samantha` or `say -v Daniel` is missing.

    python3 tools/proof/creator_spike/f_turns.py [--force]
"""

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "tools/proof/media/creator/f_turns"
RATE = 48_000
TICKS = 600_000
FPS = 30
VOICES = {"a": "Samantha", "b": "Daniel"}
BLEEDS = (12, 18, 24)
FLOORS = (55, 45)
STEM_RMS_DB = -26.0
ONSET_DB = -40.0
TRIM_DB = -50.0
COLOURS = {"a": "0xC0392B", "b": "0x2980B9", "wide": "0x27AE60"}

# (kind, speaker, gap before in seconds, text[, rate]). kind: turn, reply,
# crosstalk (both speakers, texts A then B). The gap is from the previous
# utterance's last sample above −40 dBFS to this one's onset.
TABLE = [
    ("turn", "a", 3.0, "Welcome back to the show. Today we are talking about how small teams "
                       "ship software without burning out."),
    ("turn", "b", 0.8, "Thanks for having me. I think the first thing is to keep the scope "
                       "honest and the release train on time."),
    ("turn", "a", 0.8, "That makes sense. How do you decide what to cut when the schedule gets "
                       "tight near the end of a cycle?"),
    ("reply", "b", 0.8, "Right.", 200),
    ("turn", "a", 0.8, "Because in my experience the hardest part is telling people their "
                       "favourite feature has to wait."),
    ("turn", "b", 1.0, "We write the tradeoff down in one paragraph and share it early, so "
                       "nobody is surprised on launch day."),
    ("reply", "a", 0.8, "Sure.", 200),
    ("turn", "b", 0.8, "And we keep a short list of things we will never compromise on, like "
                       "data loss and crashes."),
    ("crosstalk", "both", 1.2, ("Wait, so you never ship a crash fix late?",
                                "No, no, we always ship those right away.")),
    ("turn", "a", 1.0, "Okay, that is a good rule. Let us talk about testing, because that is "
                       "where most teams struggle."),
    ("turn", "b", 0.8, "Testing is a habit more than a tool. We run the whole suite before "
                       "every merge, and it takes about eight minutes."),
    ("turn", "a", 3.5, "Eight minutes sounds long to some people, but it is short compared to "
                       "a broken release on a Friday afternoon."),
    ("turn", "b", 0.8, "Exactly, and the suite pays for itself the first time it catches a "
                       "regression that a reviewer missed."),
    ("turn", "a", 0.8, "What about the people side? How do you keep everyone from working "
                       "nights when a deadline gets close?"),
    ("turn", "b", 0.8, "We move the date instead of the people. It sounds simple, but it took "
                       "us years to actually believe it."),
    ("turn", "a", 0.9, "I want to ask about tools for a moment. Which ones have actually "
                       "changed the way your team works day to day?"),
    ("turn", "b", 1.1, "Honestly, a shared checklist for releases did more than any fancy "
                       "system we tried in the last five years."),
    ("turn", "a", 0.8, "A checklist seems almost too simple. Did people push back when you "
                       "first asked them to follow it every time?"),
    ("turn", "b", 0.9, "At first they did, until the checklist caught a missing migration "
                       "that would have broken every customer's data."),
    ("turn", "a", 1.0, "That kind of story wins people over quickly. What would you tell a "
                       "team that is just starting out this year?"),
    ("turn", "b", 0.8, "Start small, write things down, and measure the boring parts, because "
                       "that is where the time quietly disappears."),
    ("turn", "a", 1.2, "Measuring the boring parts is great advice. I think our listeners will "
                       "take that one straight to their next planning meeting."),
    ("turn", "b", 0.8, "I hope so. And remember that a calm team ships better work than a "
                       "tired one, every single time."),
    ("turn", "a", 0.8, "That is a strong place to end. Thank you so much for joining us and "
                       "sharing all of this today."),
    ("turn", "b", 0.8, "Thank you, it was a pleasure. I hope some of this helps the teams who "
                       "are listening."),
]


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def have_voices():
    listing = subprocess.run(["say", "-v", "?"], capture_output=True, text=True).stdout
    names = {line.split()[0] for line in listing.splitlines() if line.strip()}
    return [v for v in VOICES.values() if v not in names]


def synthesise(voice, text, rate, scratch, name):
    aiff, wav = scratch / f"{name}.aiff", scratch / f"{name}.wav"
    command = ["say", "-v", voice, "-o", str(aiff)]
    if rate:
        command += ["-r", str(rate)]
    subprocess.run(command + [text], check=True)
    subprocess.run(["afconvert", "-f", "WAVE", "-d", f"LEI16@{RATE}", "-c", "1", str(aiff),
                    str(wav)], check=True, capture_output=True)
    return read_wav16(wav)


def read_wav16(path):
    data = Path(path).read_bytes()
    position = 12
    while position + 8 <= len(data):
        chunk, size = data[position:position + 4], int.from_bytes(data[position + 4:position + 8],
                                                                  "little")
        if chunk == b"data":
            raw = np.frombuffer(data[position + 8:position + 8 + size], dtype="<i2")
            return raw.astype(np.float64) / 32768.0
        position += 8 + size + (size & 1)
    raise RuntimeError(f"{path}: no data chunk")


def write_wav24(path, x):
    q = np.clip(np.round(x * 8_388_607), -8_388_608, 8_388_607).astype("<i4")
    body = q.view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    header = (b"RIFF" + (36 + len(body)).to_bytes(4, "little") + b"WAVE"
              + b"fmt " + (16).to_bytes(4, "little") + (1).to_bytes(2, "little")
              + (1).to_bytes(2, "little") + RATE.to_bytes(4, "little")
              + (RATE * 3).to_bytes(4, "little") + (3).to_bytes(2, "little")
              + (24).to_bytes(2, "little") + b"data" + len(body).to_bytes(4, "little"))
    Path(path).write_bytes(header + body)


def level(db):
    return 10 ** (db / 20)


def stem(x):
    """The utterance cropped to its part above −50 dBFS of its own peak, at
    −26 dBFS RMS: (samples, first index above −40 dBFS, last such index)."""
    x = x / max(1e-9, np.max(np.abs(x)))
    loud = np.nonzero(np.abs(x) >= level(TRIM_DB))[0]
    x = x[loud[0]:loud[-1] + 1]
    x = x * level(STEM_RMS_DB) / np.sqrt(np.mean(x * x))
    above = np.nonzero(np.abs(x) >= level(ONSET_DB))[0]
    return x, int(above[0]), int(above[-1])


def pink(n, seed, db):
    rng = np.random.default_rng(seed)
    spectrum = np.fft.rfft(rng.standard_normal(n))
    f = np.arange(len(spectrum), dtype=np.float64)
    f[0] = 1
    spectrum /= np.sqrt(f)
    spectrum[0] = 0
    noise = np.fft.irfft(spectrum, n)
    return noise * level(db) / np.sqrt(np.mean(noise * noise))


def camera(path, colour, frames):
    boxes = ",".join(
        f"drawbox=x={i * 120}:y=1020:w=120:h=60:color=white:t=fill:"
        f"enable='mod(floor(n/{2 ** i}),2)'" for i in range(16))
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
         f"color=c={colour}:s=1920x1080:r={FPS}", "-vf", boxes, "-frames:v", str(frames),
         "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", "-g", str(FPS),
         "-an", str(path)], check=True)


def build():
    scratch = Path(tempfile.mkdtemp(prefix="f_turns-"))
    try:
        solo = {"a": [], "b": []}  # (placement sample, samples)
        turns = []
        cursor = 0  # the previous utterance's last sample above −40 dBFS
        for index, row in enumerate(TABLE):
            kind, speaker, gap = row[0], row[1], row[2]
            rate = row[4] if len(row) > 4 else None
            if kind == "crosstalk":
                parts = []
                for who, text in zip("ab", row[3]):
                    x, first, last = stem(synthesise(VOICES[who], text, rate, scratch,
                                                     f"{index}{who}"))
                    parts.append((who, x, first, last))
                onset = cursor + round(gap * RATE)
                ends = []
                for who, x, first, last in parts:
                    place = onset - first
                    solo[who].append((place, x))
                    ends.append(place + last)
                overlap = (min(ends) - onset) / RATE
                if overlap < 2.5:
                    raise RuntimeError(f"crosstalk overlaps {overlap:.2f} s, under 2.5 s")
                turns.append({"kind": kind, "speaker": "both", "onset": onset,
                              "end": max(ends), "gap_before": gap})
                cursor = max(ends)
                continue
            x, first, last = stem(synthesise(VOICES[speaker], row[3], rate, scratch,
                                             f"{index}{speaker}"))
            onset = cursor + round(gap * RATE)
            place = onset - first
            solo[speaker].append((place, x))
            length = (last - first) / RATE
            if kind == "turn" and length < 3.0:
                raise RuntimeError(f"turn {index} lasts {length:.2f} s, under 3 s")
            if kind == "reply" and length > 0.6:
                raise RuntimeError(f"reply {index} lasts {length:.2f} s, over 0.6 s")
            turns.append({"kind": kind, "speaker": speaker, "onset": onset,
                          "end": place + last, "gap_before": gap})
            cursor = place + last

        seconds = int(np.ceil(cursor / RATE + 2.0))
        total = seconds * RATE
        stems = {}
        for who, pieces in solo.items():
            track = np.zeros(total)
            for place, x in pieces:
                track[place:place + len(x)] += x
            stems[who] = track
        # The onset is measured on the solo stem as mixed.
        for turn in turns:
            whose = ["a", "b"] if turn["speaker"] == "both" else [turn["speaker"]]
            firsts = []
            for who in whose:
                window = stems[who][max(0, turn["onset"] - RATE // 2):turn["end"] + 1]
                above = np.nonzero(np.abs(window) >= level(ONSET_DB))[0]
                firsts.append(max(0, turn["onset"] - RATE // 2) + int(above[0]))
            turn["onset"] = min(firsts)

        OUT.mkdir(parents=True, exist_ok=True)
        variants = []
        for bleed in BLEEDS:
            for floor in FLOORS:
                name = f"b{bleed}_f{floor}"
                files = {}
                for index, (own, other) in enumerate((("a", "b"), ("b", "a"))):
                    mic = stems[own] + stems[other] * level(-bleed) + pink(
                        total, 1000 + 10 * bleed + floor + index, -floor)
                    peak = float(np.max(np.abs(mic)))
                    if peak >= 1.0:
                        raise RuntimeError(f"mic_{own}_{name} clips at {peak:.3f}")
                    path = OUT / f"mic_{own}_{name}.wav"
                    write_wav24(path, mic)
                    files[own] = path.name
                variants.append({"name": name, "bleed_db": bleed, "floor_dbfs": -floor,
                                 "mic_a": files["a"], "mic_b": files["b"]})

        frames = seconds * FPS
        half = frames // 2
        cameras = {}
        for name, colour, count in (("cam_a_1", COLOURS["a"], half),
                                    ("cam_a_2", COLOURS["a"], frames - half),
                                    ("cam_b", COLOURS["b"], frames),
                                    ("cam_wide", COLOURS["wide"], frames)):
            camera(OUT / f"{name}.mov", colour, count)
            cameras[name] = {"file": f"{name}.mov", "width": 1920, "height": 1080, "fps": FPS,
                             "frames": count, "duration_ticks": count * TICKS // FPS}

        # The expected shots, from the design (module doc), never the planner.
        expected = [{"angle": "wide", "onset": None}]
        current = "wide"
        for turn in turns:
            if turn["kind"] == "turn" and turn["speaker"] != current:
                current = turn["speaker"]
                expected.append({"angle": current, "onset": turn["onset"]})
            elif turn["kind"] == "crosstalk" and current != "wide":
                current = "wide"
                expected.append({"angle": "wide", "onset": turn["onset"]})
        for row in expected:
            if row["onset"] is not None:
                row["onset_ticks"] = row["onset"] * TICKS // RATE
                row["onset_seconds"] = round(row["onset"] / RATE, 6)
        for turn in turns:
            turn["onset_seconds"] = round(turn["onset"] / RATE, 6)
            turn["end_seconds"] = round(turn["end"] / RATE, 6)

        manifest = {
            "generator_sha256": sha256(__file__), "rate": RATE, "samples": total,
            "seconds": seconds, "duration_ticks": seconds * TICKS, "voices": VOICES,
            "stem_rms_dbfs": STEM_RMS_DB, "onset_dbfs": ONSET_DB, "variants": variants,
            "cameras": cameras, "turns": turns, "expected_shots": expected,
        }
        (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
        return manifest
    finally:
        shutil.rmtree(scratch, ignore_errors=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    missing = have_voices()
    if missing:
        print(f"SKIPPED F-TURNS: say has no voice {', '.join(missing)}")
        return 2
    manifest_path = OUT / "manifest.json"
    if not args.force and manifest_path.exists():
        with open(manifest_path) as handle:
            if json.load(handle).get("generator_sha256") == sha256(__file__):
                print(f"F-TURNS reused: {OUT}")
                return 0
    manifest = build()
    print(f"F-TURNS built: {OUT} — {manifest['seconds']} s, {len(manifest['turns'])} turns, "
          f"{len(manifest['expected_shots'])} expected shots, {len(manifest['variants'])} variants")
    return 0


if __name__ == "__main__":
    sys.exit(main())
