#!/usr/bin/env python3
"""Road maps "audio-sync" (AS-1, AS-2) and "audio-sync-2" (AS-3, AS-4) — spec
§11 SY-1..SY-22 — Clip ▸ Synchronize Audio and `sync_audio`, over MCP against a
running instance, then the probe's rows over `app/Sources`.

    python3 tools/proof/audio_sync_proof.py <dir>/agent.sock [--only S1,P3,...]
    python3 tools/proof/audio_sync_proof.py [<dir>/agent.sock] --mutants
    python3 tools/proof/audio_sync_proof.py --cost    # P19 alone: SY-22's budget

The instance is the caller's (`proof_app.py launch`; Debug while iterating,
`RC_PROOF_APP=release` for the recorded run). Every package and fixture is
under `tools/proof/work/audio-sync/`; every project is closed (`close_project`,
discard). The only menu item performed is Clip ▸ Synchronize Audio, which
persists nothing. S18 decodes two `audio_wav` exports with `ffmpeg`; S23 has
ffmpeg's `areverse` write the owner's recorder reversed into
`tools/proof/work/audio-sync/`.

Fixtures (Python `wave`, 16 kHz mono, seeded): SOURCE, 150 s of irregular
noise and tone bursts over a quiet floor; RECORDER, SOURCE delayed by
d = 50133 samples (3.1333125 s — off the 10 ms bucket grid, and chosen so S1's
and S2's starts sit within 0.01 frame of a whole 30 fps frame), −9 dB, a
one-pole low-pass and seeded noise at −40 dBFS; UNRELATED, the same made from
another seed; DRIFT, SOURCE resampled by k = 1 + 200e-6 (linear
interpolation; recorder bucket m holds source (m·160 − d)·k) and processed as
RECORDER, so the fixture's drift is (1 − 1/k)·1e6 ppm; CAMERA, ffmpeg's mux of
SOURCE (`pcm_s16le`) under `color` video (libx264, 30 fps) into a `.mov`.

OWNERLIKE (AS-3, SY-15; the owner's traits, made from seeds): UTTER, 5 s of
speech-like syllables (120–280 ms, gaps 40–200 ms, f0 gliding within
110–190 Hz, 20 harmonics weighted by three formant bumps); COMPETE, 13 s of
SOURCE-style bursts; CAMERA2 (`camera2-v1.mov`), 60 s of a −66 dBFS floor with
UTTER at 31.2 s and COMPETE at [47 s, 60 s), muxed as CAMERA is; RECORDER2
(`recorder2-v2.wav`), 165 s of low-frequency rumble (31, 47, 63 and 82 Hz and
low-passed noise, about −14 dBFS RMS) under COMPETE at 0 s and UTTER at
31.2 + 118.70 s (a whole number of samples), both through RECORDER's −9 dB,
low-pass and noise. Recorder − camera is 118.70 s for UTTER and −47 s for
COMPETE. The OWNER's files are `tools/proof/media/owner-sync/IMG_0018.MOV` and
`record.aifc` (gitignored, never copied out of `tools/proof/`).

Every media's `cache/peaks/<id>.bin`, `cache/sync/<id>.complete.json` and
`cache/speech/<id>.complete.json` are each waited for (120 s) before it is used, and
each marker's seconds after `import_media` are printed (the time to ready).

Rows (30 fps; "unchanged" is `get_project`'s project, key-sorted, equal
before and after, and the last undo step not "Synchronize Audio"):
  S1   camera at 10 s, recorder at 0 on a second track: the recorder lands on
       exactly frame 206 (unsnapped 6.8666875 s), the camera unmoved, `moved`
       true and `anchor` the camera; its row `drift_corrected` false, `speed`
       1 and `|drift_ms|` < 5 (no drift to correct); `refined` "phat" and
       `|offset − truth| ≤ 600` ticks (1 ms; truth −1,879,987.5, SY-20),
       `coarse_offset` printed; one `undo` names "Synchronize Audio" and puts
       the recorder back at 0. Every synced row prints `refined`, its z and
       both offsets.
  S2   camera at 0, recorder at 20 s, `anchor` the recorder: the camera lands
       on exactly frame 694 (unsnapped 23.1333125 s), the recorder unmoved.
  S3   camera and UNRELATED: refused "no matching sound found", or answered
       `moved: false` with UNRELATED in `weak` (SY-18) — no row chosen by
       confidence either way — unchanged; it prints which, and the z.
  S4   a still (freeze_frame) and the recorder: refused "plays no sound",
       unchanged.
  S5   the recorder's audio disabled: refused "plays no sound", unchanged.
  S6   the recorder at ×2, refused "plays at ×2"; the camera reversed,
       refused "plays reversed"; each unchanged.
  S7   camera and recorder on one track: refused "are on one track",
       unchanged.
  S8   camera at 0, recorder at 0 (SY-16): the recorder is trimmed instead —
       start 0, `in` 94 frames (1,880,000, the snapped 3.1333125 s),
       `trimmed` the same, the camera unmoved; one `undo` restores start 0 and
       in 0.
  S9   camera trimmed to [10 s, 20 s), recorder front-trimmed to start at
       100 s: refused "would not play at any moment", unchanged.
  S10  camera at 10 s and DRIFT: corrected (`drift_corrected` true), the
       clip's `keep_pitch` false and its speed s within SY-7's 2 ms over the
       150 s overlap (`|s·k − 1|·150,000 ≤ 2`), the recorder on frame 206;
       one `undo` restores speed 1 and start 0.
  S11  the recorder nested: refused "is a nest", unchanged.
  S12  one clip: refused "needs at least two clips", unchanged.
  S13  S1's call again: `moved` false, `note` "already in sync", no undo step.
  S14  `set_selection` [camera, recorder] then `perform_menu_item ["Clip",
       "Synchronize Audio"]`: the recorder lands where S1's did.
  S15  the catalog row: no `scope`; `clips` (minItems 2, required), `anchor`,
       `accept_weak` (boolean), `project`.
  S16  the recorder's track holds a 2 s text clip ending 1 s after where S1's
       recorder lands, the recorder placed after it: refused "would overlap
       clip M on its track", unchanged, no transition anywhere.
  S17  S10's call again on the corrected recorder: `moved` false, "already in
       sync", `|drift_ms|` ≤ 2, and no new step (one `undo` still restores
       speed 1 and start 0).
  S18  after S10, the camera's audio off, `export` `audio_wav`, decoded by
       ffmpeg to 16 kHz mono; 1 ms abs-max envelopes against SOURCE placed at
       10 s, the lag on [12 s, 22 s) and [148 s, 158 s) by brute force over
       ±40 ms with parabolic refinement: |Δlag| ≤ 3 ms and each |lag| ≤ 20 ms.
       Control: `set_speed` rate 1 on the recorder, exported again: |Δlag| ≥
       20 ms.
       S10 and S17 print `drift_on`, `drift_windows`, the error and the
       call's wall seconds.
  S19  CAMERA2 placed at 0, trimmed to in 29.72 s for 25.52 s and moved to
       2 s; RECORDER2 at 0 trimmed to in 147.63 s for 17.34 s and moved to 0,
       on track 1; default anchor: the recorder lands on exactly
       snap(cam.start − cam.in + rec.in − 118.70 s) (from read-back values;
       1.2 s, a whole frame, so the snap's boundaries lie half a frame either
       side of the truth — SY-15 as amended), `search` "played", the camera
       unmoved; `refined` "phat" and `|offset − truth| ≤ 600` ticks (truth
       −118.70 s).
  S20  the OWNER's files placed as the owner placed them (camera at 0 from
       29.72 s for 25.52 s; recorder at 0 from 147.63 s for 17.34 s on track
       1), default anchor: first without `accept_weak`, `moved` false, `weak`
       [the recorder], its row `chosen_by` "placement" and `matched_on`
       "speech", unchanged and no step (SY-18, SY-19); then with
       `accept_weak: true`: synced, the camera unmoved, the recorder at start 0
       with its `in` advanced by e ≈ 0.77 s (`trimmed` e); T = (rec.in −
       rec.start) − (cam.in − cam.start) within 1/30 s of 118.68 s; one `undo`
       restores both clips. The unsnapped −offset/600000 is printed.
  S21  the same with `anchor` the recorder (weak first, `weak` [the camera],
       then accepted): the camera moves by about +0.77 s,
       `trimmed` 0, and the same bound on T.
       S20 and S21 are a scored FAIL when either OWNER file is absent.
       Every S row that syncs prints its candidates (search, offset, z).
  S22  camera and UNRELATED both at 0 (placement lag 0, so the near-placement
       rule can reach them): S3's test — refused, or weak and not applied.
  S23  the masked null (SY-17): the OWNER's camera placed as in S20, the
       owner's recorder time-reversed placed at 0 from 8.0 s for 17.34 s on
       track 1: S3's test. Control: both played windows hold ≥ 125 frames the
       cached VAD calls speech (`cache/speech/<id>.bin`, SY-17's centre-chunk
       rule rebuilt here), so the search ran on speech; both counts printed.
  S24  the Weak match sheet (SY-19): S20's placement, `set_selection` both,
       `perform_menu_item ["Clip", "Synchronize Audio"]` answers a sheet;
       `snapshot_ui {window: "sheet"}`'s layout texts hold "Weak match…",
       "Apply" and "Cancel"; `cancel_sheet` answers `cancel_button`, "Cancel"
       and no sheet; unchanged, no step. The Synchronizing Audio sheet comes
       first (SY-22): `snapshot_ui` is polled every 0.25 s (≤ 600 s) until the
       sheet's texts no longer hold "Synchronizing Audio".
       S23 and S24 are a scored FAIL when either OWNER file is absent.
       S20 and S21 print `refined`, `refine_confidence` and both offsets, and
       pass with `refined` either "phat" or "coarse" (SY-20's fallback); S22
       and S23 also need `refined` "coarse" on the mover's row.
       S14 polls `perform_menu_item` with no path every 0.1 s (≤ 600 s) until
       the window has no sheet, and prints the wait.
  S25  (its own instance, launched with `-RCDevSyncHold 3`, stopped by its
       pid) S1's placement, both selected, the menu item: a sheet whose texts
       hold "Synchronizing Audio" and "Cancel"; the item again is refused "is
       disabled here"; the camera moved a frame under it (control: the sheet
       still up after the move); once the sheet goes (≤ 600 s) the recorder is
       still at 0, the camera at 10 s + 1 frame, the top step the move's, and
       the editor's texts hold "Refused: the project changed while
       Synchronize Audio was matching".
  S26  (the same instance) a fresh S1 placement: the menu item, `cancel_sheet`
       answers "Cancel" and no sheet; 4 s later nothing changed and no new
       step. Control: the menu item again, waited out, lands the recorder on
       frame 206.
  P1–P18 `audio_sync_probe.swift`, built by `swift_build.build` over
       `app/Sources` (a failed build is a scored FAIL of all eighteen); each
       row's sentence is the probe's.
  P19  (`--cost` only) the probe built -O whole-module and run with `cost
       work/audio-sync/cost`: SY-22's ≤ 1.5 s of CPU for a one-hour pair; the
       folder is removed after.

`--mutants`: the thirty-nine below, probe-only. Each copies `app/Sources` under
`work/audio-sync/mutants/<name>/`, applies its edit (its `before` asserted to
occur exactly once), rebuilds the probe (900 s wall) and runs it (240 s wall);
killed when a named row fails; a copy that does not build or answer is a failed
control, never a kill. Exit 0 when every scored row passed (with
`--mutants`, when all thirty-nine were killed); 1 otherwise.
"""

import argparse
import array
import json
import math
import os
import random
import re
import shutil
import subprocess
import sys
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof"))
import mcp as mcp_client  # noqa: E402
import proof_app  # noqa: E402
import swift_build  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402

WORK = ROOT / "tools/proof/work/audio-sync"
FIXTURES = WORK / "fixtures"
PROBE = ROOT / "tools/proof/audio_sync_probe.swift"
RATE = 16_000
SECONDS = 150
DELAY = 50_133                       # samples: 3.1333125 s
DRIFT_K = 1 + 200e-6
DRIFT_PPM = (1 - 1 / DRIFT_K) * 1e6  # the fixture's drift, in the proof's sign
SEC = 600_000
FRAME = SEC // 30
BUILD_WALL = 900
RUN_WALL = 240
SHEET_WAIT = 600                     # s: a sheet's poll bound, mcp.py's call timeout
COST = WORK / "cost"                 # P19's one-hour fixture, removed when it ends
HOLD = 3                             # s: S25's and S26's -RCDevSyncHold
S_ROWS = [f"S{n}" for n in range(1, 27)]
OWNER = ROOT / "tools/proof/media/owner-sync"
OWNER_FILES = {"owner_camera": OWNER / "IMG_0018.MOV", "owner_recorder": OWNER / "record.aifc"}
UTTER_AT = 31.2                      # s, in CAMERA2
UTTER_GAP = 118.70                   # s, recorder − camera for UTTER (1,899,200 samples)
OWNER_GAP = 118.68                   # s, the owner's recorder − camera (round 2's request)
P_ROWS = [f"P{n}" for n in range(1, 19)]
ENVELOPE = RATE // 1000              # samples per 1 ms envelope bucket

# name: (the rows it must fail, file, before, after)
MUTANTS = {
    "lag-sign": (["P1"], "AudioSync.swift",
                 "anchor.zero - mover.zero + lagTicks", "anchor.zero - mover.zero - lagTicks"),
    "anchor-inverted": (["P2"], "AudioSync.swift",
                        "if a.start != b.start { return a.start < b.start }",
                        "if a.start != b.start { return a.start > b.start }"),
    "ratio-dropped": (["P11"], "AudioSync+Search.swift",
                      "\n            || best.z - result.candidates[1].z >= AudioSyncMatch.confidentMargin",
                      "\n            || true"),
    "before-zero-dropped": (["P12"], "AudioSync.swift",
                            "let excess = max(0, -(mover.start + delta))", "let excess: Ticks = 0"),
    "overlap-dropped": (["P6"], "AudioSync.swift",
                        "guard overlapStart < overlapEnd else {",
                        "guard overlapStart < overlapEnd || true else {"),
    "same-track-dropped": (["P6"], "AudioSync.swift",
                           "ids.count > 1 else { continue }", "ids.count > 99 else { continue }"),
    "neighbour-dropped": (["P6"], "AudioSync.swift",
                          "start < $0.end && $0.start < end", "false && $0.start < end"),
    "ppm-scale": (["P5"], "AudioSyncDrift.swift", "ppm: rate * 1e6,", "ppm: rate * 1e9,"),
    "min-windows-dropped": (["P5"], "AudioSyncDrift.swift",
                            "guard centres.count >= driftMinimumWindows else {",
                            "guard centres.count >= driftMinimumWindows || true else {"),
    "small-drift-corrected": (["P8"], "AudioSync+Correction.swift",
                              "abs(fit.milliseconds) < minimumCorrectionMilliseconds",
                              "abs(fit.milliseconds) < 0"),
    "uncertain-corrected": (["P8"], "AudioSync+Correction.swift",
                            "abs(fit.milliseconds) < minimumSignificance * fit.errorMilliseconds",
                            "abs(fit.milliseconds) < 0 * fit.errorMilliseconds"),
    "rate-limit-dropped": (["P8"], "AudioSync+Correction.swift",
                           "guard inBand(corrected) else {",
                           "guard inBand(corrected) || true else {"),
    "speed-not-compounded": (["P8"], "AudioSync+Correction.swift",
                             "speed * (1 - fit.rate)", "1 * (1 - fit.rate)"),
    "resample-dropped": (["P8"], "AudioSyncMatch.swift",
                         "guard speed != 1, speed.isFinite, speed > 0, count > 1 else { return frames }",
                         "guard speed == 1, speed.isFinite, speed > 0, count > 1 else { return frames }"),
    "rate-sign": (["P7"], "AudioSync+Correction.swift",
                  "speed * (1 - fit.rate)", "speed * (1 + fit.rate)"),
    "order-inverted": (["P7"], "AudioSync+Correction.swift",
                       "if newDuration > duration {", "if newDuration < duration {"),
    "end-unchecked": (["P7"], "AudioSync.swift",
                      "if delta != 0 || newDuration != duration,", "if delta != 0,"),
    "pivot-dropped": (["P7"], "AudioSync.swift",
                      "delta = correctedDelta(", "_ = correctedDelta("),
    # AS-3 (SY-12..SY-16)
    "trim-floor-dropped": (["P12"], "AudioSync.swift",
                           "guard newDuration - excess >= input.fps.frameDuration else {",
                           "guard newDuration - excess >= input.fps.frameDuration || true else {"),
    "confident-z": (["P11"], "AudioSync+Search.swift",
                    "best.z >= AudioSyncMatch.confidentZ", "best.z >= 0"),
    "plausible-floor-dropped": (["P11"], "AudioSync+Search.swift",
                                "near.z >= AudioSyncMatch.plausibleZ", "near.z >= -Double.infinity"),
    "radius-dropped": (["P11"], "AudioSyncMatch.swift",
                       "guard abs(lag - placementLag) <= Double(radius) else { continue }",
                       "guard abs(lag - placementLag) >= 0 else { continue }"),
    "played-first-dropped": (["P11"], "AudioSync+Search.swift",
                             "        if playable {\n", "        if playable && false {\n"),
    "window-offset-dropped": (["P11"], "AudioSync+Search.swift",
                              "offset: anchorWindow.lowerBound - moverWindow.lowerBound,",
                              "offset: 0,"),
    "standardise-dropped": (["P10"], "AudioSyncMatch.swift",
                            "            : (standardised(anchor), standardised(mover))",
                            "            : (anchor, mover)"),
    # AS-3's second fix pass (SY-17..SY-19)
    "speech-mask-dropped": (["P14"], "AudioSyncMatch.swift",
                            "let onSpeech = spoken(anchorSpeech) && spoken(moverSpeech)",
                            "let onSpeech = false"),
    "speech-floor-dropped": (["P14"], "AudioSyncMatch.swift",
                             "static let minimumSpeechFrames = 125",
                             "static let minimumSpeechFrames = 0"),
    "speech-threshold": (["P14"], "AudioSyncMatch.swift",
                         "return probabilities[index] >= speechProbability",
                         "return probabilities[index] > speechProbability"),
    "speech-chunk-offset": (["P14"], "AudioSyncMatch.swift",
                            "Int((Ticks(f) * SyncFeatures.frameTicks + frameCentreTicks) / chunk)",
                            "Int((Ticks(f) * SyncFeatures.frameTicks) / chunk)"),
    "masked-standardise-all": (
        ["P14"], "AudioSyncMatch.swift",
        "            for f in counted { sum += Double(frames[f * width + k]) }\n"
        "            let mean = sum / Double(counted.count)\n"
        "            var squares = 0.0\n"
        "            for f in counted {\n"
        "                let d = Double(frames[f * width + k]) - mean\n"
        "                squares += d * d\n"
        "            }\n"
        "            let sd = (squares / Double(counted.count)).squareRoot()",
        "            for f in 0..<count { sum += Double(frames[f * width + k]) }\n"
        "            let mean = sum / Double(count)\n"
        "            var squares = 0.0\n"
        "            for f in 0..<count {\n"
        "                let d = Double(frames[f * width + k]) - mean\n"
        "                squares += d * d\n"
        "            }\n"
        "            let sd = (squares / Double(count)).squareRoot()"),
    "weak-applied": (["P15"], "AudioSync+Weak.swift",
                     "guard row.chosenBy == .placement else { return false }",
                     "guard row.chosenBy == .placement && false else { return false }"),
    "weak-unchanged-listed": (["P15"], "AudioSync+Weak.swift",
                              "return row.delta != 0 || row.trimmed > 0", "return true"),
    # AS-4 (SY-20, SY-21)
    "phat-clear-z": (["P16"], "AudioSyncPHAT.swift",
                     "static let clearZ = 15.0", "static let clearZ = 0.0"),
    "phat-edge-dropped": (["P16"], "AudioSyncPHAT.swift",
                          "let clear = z >= clearZ && abs(lag) < reachSamples\n",
                          "let clear = z >= clearZ\n"),
    "phat-reach-dropped": (["P16"], "AudioSyncPHAT.swift",
                           "        let low = max(0, zero - reachSamples)\n"
                           "        let high = min(lags - 1, zero + reachSamples)\n",
                           "        let low = 0\n"
                           "        let high = lags - 1\n"),
    "phat-shift-dropped": (["P17"], "AudioSync.swift",
                           "if let refinement, refinement.clear {",
                           "if let refinement, refinement.clear && false {"),
    "drift-window-z": (["P5"], "AudioSyncDrift.swift",
                       "found.z >= driftWindowZ", "found.z >= -Double.infinity"),
    "drift-phat-dropped": (["P17"], "AudioSyncDrift.swift",
                           "if phatCentres.count >= driftMinimumWindows,",
                           "if phatCentres.count >= driftMinimumWindows && false,"),
    # AS-4's amendment (SY-21's robust filter)
    "drift-inliers-dropped": (["P5"], "AudioSyncDrift.swift",
                              "return r.map { abs($0) <= threshold }",
                              "return r.map { _ in true }"),
}

results = {}


def score(row, ok, detail):
    results[row] = (bool(ok), detail)
    print(f"{row} {'ok' if ok else 'FAIL'} — {detail}", flush=True)


# ---- fixtures ------------------------------------------------------------------


def source_samples(seed, seconds=SECONDS):
    """`seconds` (150) of bursts — noise or a tone, 30–400 ms, gaps of 50–600
    ms — over a floor at about −66 dBFS."""
    rng = random.Random(seed)
    total = RATE * seconds
    out = array.array("d", (rng.gauss(0, 0.0005) for _ in range(total)))
    n = int(rng.uniform(0.05, 0.6) * RATE)
    while n < total:
        length = int(rng.uniform(0.03, 0.4) * RATE)
        level = rng.uniform(0.1, 0.8)
        tone = rng.random() < 0.5
        freq = rng.uniform(200, 2000)
        attack = int(0.004 * RATE)
        for i in range(min(length, total - n)):
            env = level * min(1.0, i / attack) * (1 - 0.6 * i / length)
            value = math.sin(2 * math.pi * freq * i / RATE) if tone else rng.uniform(-1, 1)
            out[n + i] += env * value
        n += length + int(rng.uniform(0.05, 0.6) * RATE)
    return out


def recorded(samples, seed, delay=DELAY, k=1.0):
    """`samples` delayed by `delay` (and read at rate `k`), −9 dB, a one-pole
    low-pass and noise at −40 dBFS."""
    rng = random.Random(seed)
    count = int(len(samples) / k) + delay
    gain = 10 ** (-9 / 20)
    alpha = 0.35
    held = 0.0
    out = array.array("d", bytes(8 * count))
    last = len(samples) - 1
    for n in range(count):
        t = (n - delay) * k
        if t < 0 or t >= last:
            x = 0.0
        else:
            i = int(t)
            f = t - i
            x = samples[i] * (1 - f) + samples[i + 1] * f
        held += alpha * (gain * x - held)
        out[n] = held + rng.gauss(0, 0.01)
    return out


def utterance(seed, seconds=5.0):
    """Speech-like syllables: 120–280 ms each, gaps of 40–200 ms, f0 gliding
    between two values in 110–190 Hz, 20 harmonics weighted by three formant
    bumps, a raised-cosine envelope; peak about 0.5."""
    rng = random.Random(seed)
    total = int(seconds * RATE)
    out = array.array("d", bytes(8 * total))
    n = int(rng.uniform(0.04, 0.2) * RATE)
    while n < total:
        length = min(int(rng.uniform(0.12, 0.28) * RATE), total - n)
        f_start, f_end = rng.uniform(110, 190), rng.uniform(110, 190)
        formants = [(rng.uniform(300, 900), 120), (rng.uniform(900, 2500), 200),
                    (rng.uniform(2500, 3500), 300)]
        phases = [0.0] * 20
        for i in range(length):
            f0 = f_start + (f_end - f_start) * i / length
            env = 0.5 - 0.5 * math.cos(2 * math.pi * i / length)
            value = 0.0
            for h in range(20):
                phases[h] += 2 * math.pi * (h + 1) * f0 / RATE
                weight = sum(math.exp(-(((h + 1) * f0 - f) / bw) ** 2) for f, bw in formants)
                value += weight * math.sin(phases[h])
            out[n + i] = 0.12 * env * value
        n += length + int(rng.uniform(0.04, 0.2) * RATE)
    return out


def rumble(seed, seconds):
    """Low-frequency rumble: sines at 31, 47, 63 and 82 Hz and one-pole
    low-passed noise, scaled to about −14 dBFS RMS."""
    rng = random.Random(seed)
    total = int(seconds * RATE)
    phases = [rng.uniform(0, 2 * math.pi) for _ in range(4)]
    freqs = (31, 47, 63, 82)
    out = array.array("d", bytes(8 * total))
    held = 0.0
    for n in range(total):
        held += 0.02 * (rng.gauss(0, 1) - held)
        out[n] = sum(math.sin(2 * math.pi * f * n / RATE + p) for f, p in zip(freqs, phases)) \
            + 4 * held
    rms = math.sqrt(sum(v * v for v in out) / total)
    scale = 10 ** (-14 / 20) / rms
    for n in range(total):
        out[n] *= scale
    return out


def write_wav(path, samples):
    data = array.array("h", (max(-32767, min(32767, int(round(s * 32767)))) for s in samples))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def fixtures():
    """The five files, written once per tree (the names carry their version)."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    names = {key: FIXTURES / f"{key}-v1.{ext}" for key, ext in
             [("source", "wav"), ("recorder", "wav"), ("unrelated", "wav"), ("drift", "wav"),
              ("camera", "mov")]}
    if all(p.exists() for p in names.values()):
        return names
    source = source_samples(1)
    write_wav(names["source"], source)
    write_wav(names["recorder"], recorded(source, 2))
    write_wav(names["unrelated"], recorded(source_samples(3), 4))
    write_wav(names["drift"], recorded(source, 5, k=DRIFT_K))
    mux(names["source"], names["camera"], SECONDS)
    return names


def mux(wav, mov, seconds):
    """`wav` (`pcm_s16le`) under `color` video (libx264, 30 fps) into `mov`."""
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
         f"color=c=gray:s=320x180:r=30:d={seconds}", "-i", str(wav),
         "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-shortest",
         str(mov)], check=True, timeout=300)


def fixtures2():
    """CAMERA2 and RECORDER2, written once per tree (the names carry their
    version)."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    names = {"camera2": FIXTURES / "camera2-v1.mov", "recorder2": FIXTURES / "recorder2-v2.wav"}
    if all(p.exists() for p in names.values()):
        return names
    utter = utterance(21)
    compete = source_samples(22, seconds=13)
    rng = random.Random(23)
    camera = array.array("d", (rng.gauss(0, 0.0005) for _ in range(60 * RATE)))
    at = int(round(UTTER_AT * RATE))
    for i, v in enumerate(utter):
        camera[at + i] += v
    for i, v in enumerate(compete[:13 * RATE]):
        camera[47 * RATE + i] += v
    wav = FIXTURES / "camera2-v1.wav"
    write_wav(wav, camera)
    mux(wav, names["camera2"], 60)
    heard = array.array("d", bytes(8 * 165 * RATE))
    for i, v in enumerate(compete[:13 * RATE]):
        heard[i] += v
    later = at + int(round(UTTER_GAP * RATE))
    for i, v in enumerate(utter):
        heard[later + i] += v
    recorder = recorded(heard, 24, delay=0)
    noise = rumble(25, 165)
    write_wav(names["recorder2"], [r + q for r, q in zip(recorder, noise)])
    return names


# ---- one project ---------------------------------------------------------------


class Session:
    def __init__(self, mcp, name, files):
        self.mcp = mcp
        self.files = files
        for stale in WORK.iterdir():
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale.name):
                shutil.rmtree(stale)
        self.path = str(WORK / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360, fps=30)
        self.imported = {}

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def text(self):
        return json.dumps(self.project(), sort_keys=True)

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def start(self, clip):
        return self.clip(clip)["start"]

    def in_point(self, clip):
        return self.clip(clip)["source"]["in"]

    def place_trimmed(self, key, track_index, at, source_in, length):
        """A clip at 0, `trim_start` to `source_in`, `trim_end` to that start
        plus `length`, then `move_clip` to `at`: the owner's order."""
        clip = self.place(key, 0, track_index)
        for name, to in (("trim_start", source_in), ("trim_end", None)):
            try:
                self.op(name, clip=clip, to=to if to is not None else self.start(clip) + length)
            except ToolError as error:  # the file already ends there: an identity
                if "made no change" not in str(error):
                    raise
        start = self.start(clip)
        if at != start:
            self.op("move_clip", clips=[clip], delta=at - start)
        return clip

    def tracks(self):
        return [t["id"] for t in self.project()["tracks"]]

    def track(self, index):
        while len(self.tracks()) <= index:
            self.mcp.call_with("add_track", {"project": self.path})
        return self.tracks()[index]

    def media(self, key):
        if key in self.imported:
            return self.imported[key]
        began = time.monotonic()
        media = self.op("import_media", path=str(self.files[key]))["media"]
        cache = Path(self.path) / "cache"
        # Each marker's seconds after import_media was called: the time to
        # ready a person meets before Synchronize Audio can match the file.
        landed = [f"import {time.monotonic() - began:.1f} s"]
        for label, wanted in (("peaks", cache / "peaks" / f"{media}.bin"),
                              ("sync", cache / "sync" / f"{media}.complete.json"),
                              ("speech", cache / "speech" / f"{media}.complete.json")):
            # 120 s: in one Debug run the owner's 165 s recorder's features
            # landed just over 60 s after its import; the times printed
            # below are the measurement.
            for _ in range(2400):
                if wanted.exists():
                    break
                time.sleep(0.05)
            else:
                raise RuntimeError(f"{wanted} was never written")
            landed.append(f"{label} {time.monotonic() - began:.1f} s")
        print(f"  media {key} ({Path(self.files[key]).name}): " + ", ".join(landed)
              + " after import_media", flush=True)
        self.imported[key] = media
        return media

    def place(self, key, at, track_index):
        media = self.media(key)
        return self.op("add_clip", track=self.track(track_index), media=media,
                       at=at)["new_clips"][0]

    def sync(self, **kwargs):
        return self.op("sync_audio", **kwargs)

    def error(self, tool, **kwargs):
        try:
            self.op(tool, **kwargs)
            return None
        except ToolError as error:
            return str(error)

    def last_step(self):
        """The undo stack's top step's name, put back with a redo."""
        try:
            name = self.op("undo")["undone"]
        except ToolError:
            return None
        self.op("redo")
        return name

    def close(self):
        try:
            self.op("close_project", discard=True)
        except ToolError:
            pass


def refused(session, label, words, **kwargs):
    """(ok, detail): sync_audio refused naming `words`, the project unchanged
    and no Synchronize Audio step on the stack."""
    before = session.text()
    message = session.error("sync_audio", **kwargs)
    after = session.text()
    step = session.last_step()
    ok = (message is not None and "Synchronize Audio was refused" in message
          and words in message and before == after and step != "Synchronize Audio")
    flat = " ".join(str(message).split())
    return ok, (f"{label}: {flat[:400]}; unchanged {before == after}; last step {step!r}")


def recorder_row(answer, clip):
    return next((r for r in answer.get("synced", []) if r["clip"] == clip), {})


def match_text(row):
    """A synced row's match: its z, how it was found, its candidates, and its
    refinement (SY-20): `refined`, its z, the refined and the coarse offset."""
    candidates = ", ".join(f"{c.get('offset', 0) / SEC:+.3f} s z {c.get('confidence', 0):.2f}"
                           for c in row.get("candidates", []))
    return (f"z {row.get('confidence')}, {row.get('search')}/{row.get('chosen_by')} on "
            f"{row.get('matched_on')}, candidates [{candidates}], trimmed {row.get('trimmed')}; "
            f"refined {row.get('refined')!r} (z {row.get('refine_confidence')}), offset "
            f"{row.get('offset')}, coarse_offset {row.get('coarse_offset')}")


def not_applied(session, label, mover, refined=None, **kwargs):
    """(ok, detail): sync_audio, called without `accept_weak`, either refused
    "no matching sound found" or answered `moved: false` with `mover` in
    `weak` (SY-18) — no row chosen by confidence either way, and with
    `refined` the mover's row (when there is one) refined so (S22's and S23's
    "coarse", SY-20's negatives) — the
    project unchanged and no Synchronize Audio step. A call that moved
    anything is undone after it is described."""
    before = session.text()
    try:
        answer, message = session.sync(**kwargs), None
    except ToolError as error:
        answer, message = None, str(error)
    after = session.text()
    if answer is not None and answer.get("moved") is True:
        undone = session.op("undo")["undone"]
        row = recorder_row(answer, mover)
        return False, (f"{label}: MOVED without accept_weak — {match_text(row)}; undo "
                       f"{undone!r}, restored {session.text() == before}")
    step = session.last_step()
    if answer is None:
        how = "refused"
        ok = ("Synchronize Audio was refused" in message and "no matching sound found" in message)
        said = " ".join(message.split())[:500]
    else:
        rows = answer.get("synced", [])
        how = "weak, not applied"
        ok = (answer.get("ok") is True and answer.get("moved") is False
              and mover in answer.get("weak", [])
              and not any(r.get("chosen_by") == "confidence" for r in rows)
              and (refined is None or recorder_row(answer, mover).get("refined") == refined))
        said = (f"weak {answer.get('weak')}, {match_text(recorder_row(answer, mover))}; note "
                f"{answer.get('note')!r}")
    ok = ok and before == after and step != "Synchronize Audio"
    return ok, f"{label}: {how} — {said}; unchanged {before == after}; last step {step!r}"


def speech_frames(session, media, clip):
    """How many of `clip`'s played-window feature frames the cached Silero VAD
    calls speech (SY-17's mask, rebuilt here from `cache/speech/<id>.bin`):
    frame f's centre chunk is (f·9600 + 19200) // 19200, speech at ≥ 0.5."""
    cache = Path(session.path) / "cache"
    probabilities = array.array("f", (cache / "speech" / f"{media}.bin").read_bytes())
    frames = (cache / "sync" / f"{media}.bin").stat().st_size // (26 * 4)
    c = session.clip(clip)
    low = min(max(0, math.floor(c["source"]["in"] / 9600)), frames)
    high = min(max(low, math.ceil((c["source"]["in"] + c["duration"]) / 9600)), frames)
    count = 0
    for f in range(low, high):
        chunk = min((f * 9600 + 19200) // 19200, len(probabilities) - 1)
        count += probabilities[chunk] >= 0.5
    return count


def reversed_owner_recorder():
    """The owner's recorder time-reversed (S23), by ffmpeg's `areverse`, into
    `tools/proof/work/audio-sync/` (gitignored) and nowhere else."""
    out = WORK / "owner-recorder-reversed.wav"
    if not out.exists():
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(OWNER_FILES["owner_recorder"]),
                        "-af", "areverse", str(out)], check=True, timeout=300)
    return out


def wait_no_sheet(session, bound=SHEET_WAIT):
    """Seconds until the editor's window has no sheet (polled every 0.1 s
    through `perform_menu_item`'s listing), or None past `bound`."""
    began = time.monotonic()
    while time.monotonic() - began < bound:
        listing = session.op("perform_menu_item")
        if ((listing.get("window") or {}).get("sheet")) is None:
            return time.monotonic() - began
        time.sleep(0.1)
    return None


def sheet_texts(session):
    """The visible texts of the window's sheet (`snapshot_ui`'s layout), or
    None (or empty) when no sheet can be captured."""
    picture = WORK / f"sheet-{os.getpid()}.png"
    try:
        shot = session.op("snapshot_ui", window="sheet", path=str(picture))
        with open(shot.get("layout_path") or "") as handle:
            return [v.get("text") for v in json.load(handle)["views"]
                    if not v.get("hidden") and v.get("text")]
    except (ToolError, OSError, ValueError, KeyError):
        return None


def editor_texts(session):
    picture = WORK / f"editor-{os.getpid()}.png"
    shot = session.op("snapshot_ui", window="editor", path=str(picture))
    with open(shot.get("layout_path") or "") as handle:
        return [v.get("text") for v in json.load(handle)["views"]
                if not v.get("hidden") and v.get("text")]


def snap(ticks):
    return math.floor(ticks / FRAME + 0.5) * FRAME


# ---- the exported mix (S18) ----------------------------------------------------


def envelope(samples):
    """1 ms abs-max buckets of 16 kHz samples."""
    return [max(abs(v) for v in samples[i:i + ENVELOPE])
            for i in range(0, len(samples) - ENVELOPE + 1, ENVELOPE)]


def wav_samples(path):
    """The file decoded by ffmpeg to 16 kHz mono signed 16-bit, as floats."""
    out = path.with_suffix(".s16")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-ac", "1", "-ar", str(RATE),
                    "-f", "s16le", str(out)], check=True, timeout=300)
    data = array.array("h", out.read_bytes())
    return [v / 32768 for v in data]


def window_lag(mix, source, start_ms, end_ms, offset_ms=10_000, reach=40):
    """The lag L in ms (the mix's sound plays L ms after SOURCE placed at
    `offset_ms`) over [start_ms, end_ms), by normalised correlation at every
    whole ms in ±reach, refined parabolically; (lag, peak r)."""
    xs = mix[start_ms:end_ms]
    mx = sum(xs) / len(xs)
    xc = [x - mx for x in xs]
    ex = math.sqrt(sum(x * x for x in xc))
    scores = []
    for lag in range(-reach, reach + 1):
        ys = source[start_ms - offset_ms - lag:end_ms - offset_ms - lag]
        my = sum(ys) / len(ys)
        yc = [y - my for y in ys]
        ey = math.sqrt(sum(y * y for y in yc))
        scores.append(sum(a * b for a, b in zip(xc, yc)) / (ex * ey) if ex and ey else 0)
    best = max(range(len(scores)), key=lambda i: scores[i])
    offset = 0.0
    if 0 < best < len(scores) - 1:
        left, centre, right = scores[best - 1], scores[best], scores[best + 1]
        bend = left - 2 * centre + right
        if bend < 0:
            offset = max(-0.5, min(0.5, 0.5 * (left - right) / bend))
    return best - reach + offset, scores[best]


def exported_drift(session, cam, recorder, files):
    """S18: (ok, detail) over the corrected mix and the rate-1 control."""
    source = envelope(wav_samples(Path(files["source"])))
    session.op("set_enabled", clip=cam, audio=False)

    def measure(tag):
        out = WORK / f"s18-{tag}-{os.getpid()}.wav"
        if out.exists():
            out.unlink()
        session.op("export", preset="audio_wav", path=str(out))
        mix = envelope(wav_samples(out))
        early = window_lag(mix, source, 12_000, 22_000)
        late = window_lag(mix, source, 148_000, 158_000)
        return early, late

    speed = session.clip(recorder).get("speed")
    if speed == 1:
        # Not corrected: a `set_speed` to 1 would be an identity, which the
        # tool answers as an error — there is no control to run.
        return False, f"the recorder plays at ×1 (S10's drift was not corrected); no control"
    (e1, r1), (l1, q1) = measure("corrected")
    session.op("set_speed", clip=recorder, rate=1)
    (e2, r2), (l2, q2) = measure("control")
    change, control = l1 - e1, l2 - e2
    ok = (abs(change) <= 3 and abs(e1) <= 20 and abs(l1) <= 20 and abs(control) >= 20)
    return ok, (f"corrected: lag {e1:.2f} ms (r {r1:.3f}) on [12 s, 22 s), {l1:.2f} ms (r "
                f"{q1:.3f}) on [148 s, 158 s), Δ {change:.2f} ms (want |Δ| ≤ 3, each |lag| ≤ "
                f"20); control at rate 1: {e2:.2f} ms (r {r2:.3f}), {l2:.2f} ms (r {q2:.3f}), "
                f"Δ {control:.2f} ms (want |Δ| ≥ 20)")


# ---- the MCP rows --------------------------------------------------------------


def mcp_rows(sock, wanted, files):
    mcp = MCP(sock)
    want = set(wanted)

    if want & {"S1", "S10", "S13", "S14"}:
        a = Session(mcp, "sync-a", files)
        try:
            cam = a.place("camera", 10 * SEC, 0)
            rec = a.place("recorder", 0, 1)
            answer = a.sync(clips=[cam, rec])
            row = recorder_row(answer, rec)
            landed = a.start(rec)
            undone = a.op("undo")["undone"]
            back = a.start(rec)
            if "S1" in want:
                drift_ms = row.get("drift_ms")
                truth = -DELAY / RATE * SEC
                offset = row.get("offset")
                score("S1", answer.get("moved") is True and answer.get("anchor") == cam
                      and landed == 206 * FRAME and a.start(cam) == 10 * SEC
                      and undone == "Synchronize Audio" and back == 0
                      and row.get("drift_corrected") is False and row.get("speed") == 1
                      and drift_ms is not None and abs(drift_ms) < 5
                      and row.get("refined") == "phat" and offset is not None
                      and abs(offset - truth) <= 600,
                      f"recorder at {landed} (want {206 * FRAME}, frame 206), camera at "
                      f"{a.start(cam)}, offset {offset} (want {truth:.1f} ±600, 1 ms; "
                      f"|Δ| {abs((offset or 0) - truth):.1f}), coarse_offset "
                      f"{row.get('coarse_offset')} (|Δ| "
                      f"{abs((row.get('coarse_offset') or 0) - truth):.1f}), {match_text(row)}; drift "
                      f"{row.get('drift_ppm')} ppm, {drift_ms} ms "
                      f"(want |·| < 5), ±{row.get('drift_error_ms')} ms on {row.get('drift_on')} "
                      f"over {row.get('drift_windows')} windows, corrected "
                      f"{row.get('drift_corrected')}, speed {row.get('speed')}, note "
                      f"{row.get('drift_note')!r}; undo {undone!r} → {back}")
            if "S13" in want:
                a.op("redo")
                again = a.sync(clips=[cam, rec])
                step = a.last_step()
                score("S13", again.get("moved") is False and again.get("note") == "already in sync"
                      and step == "Synchronize Audio" and a.start(rec) == 206 * FRAME,
                      f"moved {again.get('moved')}, note {again.get('note')!r}, top step "
                      f"{step!r} (S1's, not a second)")
                a.op("undo")
            if "S14" in want:
                a.op("set_selection", clips=[cam, rec])
                menu = a.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                waited = wait_no_sheet(a)
                score("S14", waited is not None and a.start(rec) == landed == 206 * FRAME
                      and a.start(cam) == 10 * SEC,
                      f"menu → sheet {menu.get('sheet') if isinstance(menu, dict) else menu!r}, "
                      f"gone after {waited if waited is None else round(waited, 2)} s; recorder "
                      f"at {a.start(rec)} (S1 {landed})")
        finally:
            a.close()

    if want & {"S10", "S17", "S18"}:
        h = Session(mcp, "sync-h", files)
        try:
            cam = h.place("camera", 10 * SEC, 0)
            drift = h.place("drift", 0, 1)
            began = time.monotonic()
            answer = h.sync(clips=[cam, drift])
            wall = time.monotonic() - began
            row = recorder_row(answer, drift)
            clip = h.clip(drift)
            speed = clip.get("speed")
            keep = (clip.get("audio") or {}).get("keep_pitch")
            landed = clip.get("start")
            undone = h.op("undo")["undone"]
            back = h.clip(drift)
            h.op("redo")
            if "S10" in want:
                spread = abs(speed * DRIFT_K - 1) * 150_000 if speed else None
                ok = (answer.get("moved") is True and row.get("drift_corrected") is True
                      and keep is False and spread is not None and spread <= 2
                      and landed == 206 * FRAME and undone == "Synchronize Audio"
                      and back.get("speed") == 1 and back.get("start") == 0)
                score("S10", ok, f"drift fixture {row.get('drift_ppm')} ppm (true "
                      f"{DRIFT_PPM:.2f}), {row.get('drift_ms')} ms ±{row.get('drift_error_ms')} "
                      f"ms on {row.get('drift_on')} over {row.get('drift_windows')} windows "
                      f"(the call {wall:.2f} s); corrected {row.get('drift_corrected')}, note "
                      f"{row.get('drift_note')!r}; speed {speed} (want 1/k {1 / DRIFT_K:.7f}; "
                      f"|s·k − 1|·150 000 = {spread} ms, want ≤ 2), keep_pitch {keep}, recorder "
                      f"at {landed} (want {206 * FRAME}, frame 206), duration "
                      f"{clip.get('duration')}, {match_text(row)}; undo {undone!r} → speed "
                      f"{back.get('speed')}, "
                      f"start {back.get('start')}")
            if "S17" in want:
                began = time.monotonic()
                again = h.sync(clips=[cam, drift])
                again_wall = time.monotonic() - began
                again_row = recorder_row(again, drift)
                residual = again_row.get("drift_ms")
                once = h.op("undo")["undone"]
                after_one = h.clip(drift)
                h.op("redo")
                score("S17", again.get("moved") is False and again.get("note") == "already in sync"
                      and residual is not None and abs(residual) <= 2
                      and once == "Synchronize Audio" and after_one.get("speed") == 1
                      and after_one.get("start") == 0,
                      f"moved {again.get('moved')}, note {again.get('note')!r}, re-measured "
                      f"{again_row.get('drift_ppm')} ppm, {residual} ms (want |·| ≤ 2) "
                      f"±{again_row.get('drift_error_ms')} ms on {again_row.get('drift_on')} "
                      f"over {again_row.get('drift_windows')} windows (the call "
                      f"{again_wall:.2f} s), corrected "
                      f"{again_row.get('drift_corrected')}, drift note "
                      f"{again_row.get('drift_note')!r}; one undo ({once!r}) → speed "
                      f"{after_one.get('speed')}, start {after_one.get('start')} (S10's step, not a "
                      "second)")
            if "S18" in want:
                try:
                    ok, detail = exported_drift(h, cam, drift, files)
                except ToolError as error:  # scored here, so the session goes on
                    ok, detail = False, f"a tool refused: {error}"
                score("S18", ok, detail)
        finally:
            h.close()

    if "S2" in want or "S12" in want:
        b = Session(mcp, "sync-b", files)
        try:
            cam = b.place("camera", 0, 0)
            rec = b.place("recorder", 20 * SEC, 1)
            if "S12" in want:
                ok, detail = refused(b, "one clip", "needs at least two clips", clips=[cam])
                score("S12", ok, detail)
            if "S2" in want:
                answer = b.sync(clips=[cam, rec], anchor=rec)
                score("S2", answer.get("anchor") == rec and b.start(cam) == 694 * FRAME
                      and b.start(rec) == 20 * SEC,
                      f"camera at {b.start(cam)} (want {694 * FRAME}, frame 694), recorder at "
                      f"{b.start(rec)}, anchor {answer.get('anchor')}, "
                      f"{match_text(recorder_row(answer, cam))}")
        finally:
            b.close()

    if "S3" in want:
        c = Session(mcp, "sync-c", files)
        try:
            cam = c.place("camera", 10 * SEC, 0)
            other = c.place("unrelated", 0, 1)
            ok, detail = not_applied(c, "unrelated", other, clips=[cam, other])
            score("S3", ok, detail)
        finally:
            c.close()

    if "S22" in want:
        c = Session(mcp, "sync-v", files)
        try:
            cam = c.place("camera", 0, 0)
            other = c.place("unrelated", 0, 1)
            ok, detail = not_applied(c, "unrelated, both at 0", other, refined="coarse",
                                     clips=[cam, other])
            score("S22", ok, detail)
        finally:
            c.close()

    if want & {"S4", "S5", "S6"}:
        d = Session(mcp, "sync-d", files)
        try:
            cam = d.place("camera", 10 * SEC, 0)
            rec = d.place("recorder", 0, 1)
            if "S4" in want:
                d.op("freeze_frame", clip=cam, at=12 * SEC, duration=SEC)
                still = next(c["id"] for c in d.project()["clips"]
                             if c["source"]["kind"] == "still")
                ok, detail = refused(d, "still", f"clip {still}: plays no sound",
                                     clips=[still, rec])
                d.op("undo")
                score("S4", ok, detail)
            if "S5" in want:
                d.op("set_enabled", clip=rec, audio=False)
                ok, detail = refused(d, "audio off", f"clip {rec}: plays no sound",
                                     clips=[cam, rec])
                d.op("undo")
                score("S5", ok, detail)
            if "S6" in want:
                d.op("set_speed", clip=rec, rate=2)
                ok1, detail1 = refused(d, "×2", f"clip {rec}: plays at ×2", clips=[cam, rec])
                d.op("undo")
                d.op("set_reversed", clip=cam, reversed=True)
                ok2, detail2 = refused(d, "reversed", f"clip {cam}: plays reversed",
                                       clips=[cam, rec])
                d.op("undo")
                score("S6", ok1 and ok2, f"{detail1}; {detail2}")
        finally:
            d.close()

    if "S7" in want:
        e = Session(mcp, "sync-e", files)
        try:
            cam = e.place("camera", 0, 0)
            rec = e.place("recorder", 160 * SEC, 0)
            ok, detail = refused(e, "one track", "are on one track", clips=[cam, rec])
            score("S7", ok, detail)
        finally:
            e.close()

    if "S8" in want:
        f = Session(mcp, "sync-f", files)
        try:
            cam = f.place("camera", 0, 0)
            rec = f.place("recorder", 0, 1)
            answer = f.sync(clips=[cam, rec])
            row = recorder_row(answer, rec)
            landed, source_in = f.start(rec), f.in_point(rec)
            undone = f.op("undo")["undone"]
            back, back_in = f.start(rec), f.in_point(rec)
            want_in = 94 * FRAME
            score("S8", answer.get("moved") is True and landed == 0 and source_in == want_in
                  and row.get("trimmed") == want_in and f.start(cam) == 0
                  and undone == "Synchronize Audio" and back == 0 and back_in == 0,
                  f"recorder at {landed} (want 0), in {source_in} (want {want_in}, frame 94; "
                  f"unsnapped {DELAY / RATE * SEC:.1f}), {match_text(row)} (want {want_in}), "
                  f"camera at {f.start(cam)}; undo {undone!r} → start {back}, in {back_in}")
        finally:
            f.close()

    if "S9" in want:
        g = Session(mcp, "sync-g", files)
        try:
            cam = g.place("camera", 10 * SEC, 0)
            rec = g.place("recorder", 0, 1)
            g.op("trim_end", clip=cam, to=20 * SEC)
            g.op("trim_start", clip=rec, to=100 * SEC)
            ok, detail = refused(g, "never meet", "would not play at any moment",
                                 clips=[cam, rec])
            score("S9", ok, detail)
        finally:
            g.close()

    if "S11" in want:
        i = Session(mcp, "sync-i", files)
        try:
            cam = i.place("camera", 10 * SEC, 0)
            rec = i.place("recorder", 0, 1)
            nest = i.op("nest", clips=[rec])["new_clips"][0]
            ok, detail = refused(i, "nest", f"clip {nest}: is a nest", clips=[cam, nest])
            score("S11", ok, detail)
        finally:
            i.close()

    if "S15" in want:
        tool = mcp.schemas().get("sync_audio", {})
        schema = tool.get("inputSchema", {})
        props = schema.get("properties", {})
        ok = (set(props) == {"clips", "anchor", "accept_weak", "project"} and "scope" not in props
              and schema.get("required") == ["clips"] and props["clips"].get("minItems") == 2
              and props["anchor"].get("type") == "integer"
              and props["accept_weak"].get("type") == "boolean"
              and "Synchronize Audio" in tool.get("description", ""))
        score("S15", ok, f"properties {sorted(props)}, required {schema.get('required')}, clips "
              f"minItems {props.get('clips', {}).get('minItems')}, accept_weak "
              f"{props.get('accept_weak', {}).get('type')}")

    if "S16" in want:
        j = Session(mcp, "sync-j", files)
        try:
            cam = j.place("camera", 10 * SEC, 0)
            lane = j.track(1)
            land = 206 * FRAME
            filler = j.op("add_text_clip", track=lane, at=land + SEC - 2 * SEC,
                          duration=2 * SEC)["new_clips"][0]
            rec = j.place("recorder", land + SEC + 2 * FRAME, 1)
            ok, detail = refused(j, "neighbour", f"clip {rec}: would overlap clip {filler} on "
                                 "its track", clips=[cam, rec])
            transitions = [c["id"] for c in j.project()["clips"] if c.get("transition_in")]
            score("S16", ok and not transitions, f"{detail}; transitions {transitions}")
        finally:
            j.close()

    if "S19" in want:
        k = Session(mcp, "sync-k", files)
        try:
            cam = k.place_trimmed("camera2", 0, 2 * SEC, round(29.72 * SEC), round(25.52 * SEC))
            rec = k.place_trimmed("recorder2", 1, 0, round(147.63 * SEC), round(17.34 * SEC))
            cam_start, cam_in, rec_in = k.start(cam), k.in_point(cam), k.in_point(rec)
            exact = cam_start - cam_in + rec_in - round(UTTER_GAP * SEC)
            want_start = snap(exact)
            answer = k.sync(clips=[cam, rec])
            row = recorder_row(answer, rec)
            landed = k.start(rec)
            truth = -round(UTTER_GAP * SEC)
            offset = row.get("offset")
            score("S19", landed == want_start and row.get("search") == "played"
                  and k.start(cam) == cam_start and answer.get("anchor") == cam
                  and row.get("refined") == "phat" and offset is not None
                  and abs(offset - truth) <= 600,
                  f"camera at {cam_start} in {cam_in}, recorder in {rec_in}: recorder at {landed} "
                  f"(want {want_start}, frame {want_start // FRAME}; unsnapped {exact}), "
                  f"recorder − camera {-(offset or 0) / SEC:.5f} s (true {UTTER_GAP}; offset "
                  f"{offset}, want {truth} ±600), coarse {-(row.get('coarse_offset') or 0) / SEC:.5f} "
                  f"s; {match_text(row)}; camera at {k.start(cam)}")
        finally:
            k.close()

    for name, named_anchor in (("S20", "camera"), ("S21", "recorder")):
        if name not in want:
            continue
        missing = [str(p) for p in OWNER_FILES.values() if not p.exists()]
        if missing:
            score(name, False, f"the owner's files are absent: {', '.join(missing)}")
            continue
        o = Session(mcp, f"sync-{name.lower()}", files)
        try:
            cam = o.place_trimmed("owner_camera", 0, 0, round(29.72 * SEC), round(25.52 * SEC))
            rec = o.place_trimmed("owner_recorder", 1, 0, round(147.63 * SEC),
                                  round(17.34 * SEC))
            before = {c: (o.start(c), o.in_point(c), o.clip(c)["duration"]) for c in (cam, rec)}
            anchor = cam if named_anchor == "camera" else rec
            moved = rec if anchor == cam else cam
            # First without accept_weak (SY-19): a weak match on speech,
            # answered moved: false, nothing changed and no step.
            text = o.text()
            asked = o.sync(clips=[cam, rec], anchor=anchor)
            asked_row = recorder_row(asked, moved)
            asked_step = o.last_step()
            weak_ok = (asked.get("moved") is False and asked.get("weak") == [moved]
                       and asked_row.get("chosen_by") == "placement"
                       and asked_row.get("matched_on") == "speech"
                       and o.text() == text and asked_step != "Synchronize Audio")
            weak_said = (f"without accept_weak: moved {asked.get('moved')}, weak "
                         f"{asked.get('weak')}, {match_text(asked_row)}, unchanged "
                         f"{o.text() == text}, last step {asked_step!r}")
            answer = o.sync(clips=[cam, rec], anchor=anchor, accept_weak=True)
            row = recorder_row(answer, moved)
            after = {c: (o.start(c), o.in_point(c)) for c in (cam, rec)}
            gap = ((after[rec][1] - after[rec][0]) - (after[cam][1] - after[cam][0])) / SEC
            undone = o.op("undo")["undone"]
            restored = {c: (o.start(c), o.in_point(c), o.clip(c)["duration"]) for c in (cam, rec)}
            unsnapped = -(row.get("offset") or 0) / SEC if anchor == cam \
                else (row.get("offset") or 0) / SEC
            if anchor == cam:
                shape = (after[cam][:2] == before[cam][:2] and after[rec][0] == 0
                         and row.get("trimmed", 0) > 0
                         and after[rec][1] == before[rec][1] + row.get("trimmed", 0))
                what = (f"recorder start {after[rec][0]}, in {before[rec][1]} → {after[rec][1]} "
                        f"(e {row.get('trimmed', 0) / SEC:.3f} s), camera unmoved "
                        f"{after[cam] == before[cam][:2]}")
            else:
                shift = after[cam][0] - before[cam][0]
                shape = (after[rec] == before[rec][:2] and row.get("trimmed") == 0
                         and 0.5 * SEC <= shift <= 1.0 * SEC and after[cam][1] == before[cam][1])
                what = (f"camera moved {shift / SEC:+.3f} s (want about +0.77), trimmed "
                        f"{row.get('trimmed')}, recorder unmoved {after[rec] == before[rec][:2]}")
            score(name, weak_ok and answer.get("moved") is True and shape
                  and abs(gap - OWNER_GAP) <= 1 / 30 and undone == "Synchronize Audio"
                  and restored == before,
                  f"anchor the {named_anchor}: {weak_said}; with accept_weak: {what}; "
                  f"T = recorder − camera {gap:.4f} s (want "
                  f"{OWNER_GAP} ± 1/30); unsnapped −offset/600000 {unsnapped:.4f} s; "
                  f"{match_text(row)}; undo {undone!r} restores both {restored == before}")
        finally:
            o.close()


    if "S23" in want:
        missing = [str(p) for p in OWNER_FILES.values() if not p.exists()]
        if missing:
            score("S23", False, f"the owner's files are absent: {', '.join(missing)}")
        else:
            o = Session(mcp, "sync-s23", {**files, "owner_reversed": reversed_owner_recorder()})
            try:
                cam = o.place_trimmed("owner_camera", 0, 0, round(29.72 * SEC),
                                      round(25.52 * SEC))
                rev = o.place_trimmed("owner_reversed", 1, 0, round(8.0 * SEC),
                                      round(17.34 * SEC))
                # The control: both played windows hold enough speech that
                # the search ran on speech, not sound (02c's objection 2).
                counts = (speech_frames(o, o.media("owner_camera"), cam),
                          speech_frames(o, o.media("owner_reversed"), rev))
                ok, detail = not_applied(o, "the owner's recorder reversed", rev,
                                         refined="coarse", clips=[cam, rev])
                score("S23", ok and min(counts) >= 125,
                      f"speech frames in the played windows: camera {counts[0]}, reversed "
                      f"recorder {counts[1]} (each ≥ 125); {detail}")
            finally:
                o.close()

    if "S24" in want:
        missing = [str(p) for p in OWNER_FILES.values() if not p.exists()]
        if missing:
            score("S24", False, f"the owner's files are absent: {', '.join(missing)}")
        else:
            o = Session(mcp, "sync-s24", files)
            try:
                cam = o.place_trimmed("owner_camera", 0, 0, round(29.72 * SEC),
                                      round(25.52 * SEC))
                rec = o.place_trimmed("owner_recorder", 1, 0, round(147.63 * SEC),
                                      round(17.34 * SEC))
                o.op("set_selection", clips=[cam, rec])
                before = o.text()
                menu = o.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                up = menu.get("sheet") is not None
                # The Synchronizing Audio sheet first (SY-22), then the weak one.
                began = time.monotonic()
                texts = None
                while time.monotonic() - began < SHEET_WAIT:
                    texts = sheet_texts(o)
                    if texts and not any("Synchronizing Audio" in x for x in texts):
                        break
                    time.sleep(0.25)
                waited = time.monotonic() - began
                texts = texts or ["(no layout)"]
                message = next((t for t in texts if "Weak match" in t), None)
                cancelled = o.op("cancel_sheet")
                down = (cancelled.get("how") == "cancel_button"
                        and cancelled.get("button") == "Cancel"
                        and "sheet" in cancelled and cancelled["sheet"] is None)
                after = o.text()
                step = o.last_step()
                # A short plan can be over before the menu answers: the weak
                # sheet seen after it is the sheet the menu brought up.
                up = up or message is not None
                score("S24", up and message is not None and "Apply" in texts
                      and "Cancel" in texts and down and before == after
                      and step != "Synchronize Audio",
                      f"menu → sheet {menu.get('sheet')!r}; the weak sheet after {waited:.2f} s; "
                      f"texts {texts[:6]}; cancel_sheet "
                      f"{cancelled.get('how')} {cancelled.get('button')!r} → sheet "
                      f"{cancelled.get('sheet')!r}; unchanged {before == after}; last step "
                      f"{step!r}")
            finally:
                o.close()


# ---- the Synchronizing Audio sheet (S25, S26; SY-22) ------------------------------


def held_rows(wanted, files):
    """S25 and S26 on an instance of their own, launched with `-RCDevSyncHold
    3` so the sheet stays up long enough to act under; stopped by its pid."""
    launched = mcp_client.launch(str(proof_app.binary()), ["-RCDevSyncHold", str(HOLD)])
    try:
        if launched.client is None:
            for row in wanted:
                score(row, False, f"instrument failure: no instance at {launched.socket_path}")
            return
        print(f"  held instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        client = launched.client
        if "S25" in wanted:
            s = Session(client, "sync-s25", files)
            try:
                cam = s.place("camera", 10 * SEC, 0)
                rec = s.place("recorder", 0, 1)
                s.op("set_selection", clips=[cam, rec])
                menu = s.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                texts = sheet_texts(s) or []
                try:
                    s.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                    again = "ran"
                except ToolError as error:
                    again = str(error)
                s.op("move_clip", clips=[cam], delta=FRAME)
                still = ((s.op("perform_menu_item").get("window") or {}).get("sheet")) is not None
                waited = wait_no_sheet(s)
                # The foot first: `last_step`'s undo and redo would clear it.
                foot = editor_texts(s)
                step = s.last_step()
                said = next((x for x in foot if x.startswith("Refused: the project changed "
                                                             "while Synchronize Audio")), None)
                ok = (menu.get("sheet") is not None and "Synchronizing Audio" in texts
                      and "Cancel" in texts and "is disabled here" in again
                      and waited is not None and s.start(rec) == 0
                      and s.start(cam) == 10 * SEC + FRAME and step == "Move Clip"
                      and said is not None
                      and said.startswith("Refused: the project changed while Synchronize "
                                          "Audio was matching"))
                detail = (f"menu → sheet {menu.get('sheet')!r}, texts {texts[:5]}; again: "
                          f"{' '.join(again.split())[:160]}; camera moved a frame under the "
                          f"sheet (control: the sheet still up after the move, {still}); gone "
                          f"after {waited if waited is None else round(waited, 2)} s; recorder at "
                          f"{s.start(rec)} (want 0), camera at {s.start(cam)} (want "
                          f"{10 * SEC + FRAME}), top step {step!r}; foot {said!r}")
                score("S25", ok and still, detail if still else "instrument failure: " + detail)
            finally:
                s.close()
        if "S26" in wanted:
            s = Session(client, "sync-s26", files)
            try:
                cam = s.place("camera", 10 * SEC, 0)
                rec = s.place("recorder", 0, 1)
                # `last_step`'s undo and redo reset the selection: asked first.
                top = s.last_step()
                s.op("set_selection", clips=[cam, rec])
                before = s.text()
                menu = s.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                cancelled = s.op("cancel_sheet")
                time.sleep(HOLD + 1)
                after = s.text()
                step = s.last_step()
                s.op("set_selection", clips=[cam, rec])
                s.op("perform_menu_item", path=["Clip", "Synchronize Audio"])
                waited = wait_no_sheet(s)
                landed = s.start(rec)
                ok = (menu.get("sheet") is not None and cancelled.get("button") == "Cancel"
                      and cancelled.get("sheet") is None and before == after and step == top
                      and waited is not None and landed == 206 * FRAME)
                score("S26", ok, f"menu → sheet {menu.get('sheet')!r}; cancel_sheet "
                      f"{cancelled.get('how')} {cancelled.get('button')!r} → sheet "
                      f"{cancelled.get('sheet')!r}; {HOLD + 1} s later unchanged {before == after}, "
                      f"top step {step!r} (was {top!r}); control: the menu again, gone after "
                      f"{waited if waited is None else round(waited, 2)} s, recorder at {landed} "
                      f"(want {206 * FRAME})")
            finally:
                s.close()
        quiet = [line for line in Path(launched.log_path).read_text(errors="replace").splitlines()
                 if "Frame Job: " in line]
        if quiet:  # its startup parity check complained: the rows it ran are not to be trusted
            print("  held instance's log: " + " | ".join(quiet[:3]), flush=True)
            for row in wanted:
                if row in results:
                    score(row, False, "instrument failure: the held instance's log has "
                          f"{len(quiet)} 'Frame Job: ' line(s), first {quiet[0]!r}; the row "
                          f"had said: {results[row][1][:200]}")
    finally:
        launched.stop()


# ---- the probe -----------------------------------------------------------------


def probe_rows(sources, here):
    """{row: (ok, detail)} from the probe built over `sources`, or a FAIL of
    every row when it does not build or answer."""
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "audio-sync-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        why = "the probe did not build: " + "; ".join(error.diagnostics[:6])
        return {row: (False, why) for row in P_ROWS}
    try:
        ran = subprocess.run([str(binary)], capture_output=True, text=True, timeout=RUN_WALL)
    except subprocess.TimeoutExpired:
        return {row: (False, f"no answer within {RUN_WALL} s") for row in P_ROWS}
    (here / "stderr.txt").write_text(ran.stderr)
    try:
        answered = {r["id"]: (r["pass"], r["detail"]) for r in json.loads(ran.stdout)["rows"]}
    except (ValueError, KeyError):
        why = f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"
        return {row: (False, why) for row in P_ROWS}
    return {row: answered.get(row, (False, "the probe did not answer it")) for row in P_ROWS}


def cost():
    """P19 alone (SY-22): the probe built as Release builds (-O, whole
    module), run with `cost <COST>`; no socket."""
    here = WORK / "cost-probe"
    if here.exists():
        shutil.rmtree(here)
    here.mkdir(parents=True)
    entry = here / "main.swift"
    shutil.copyfile(PROBE, entry)
    binary = here / "audio-sync-cost"
    try:
        swift_build.build(sources=swift_build.app_sources() + [entry], output=binary,
                          optimize=True, wmo=True, timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        score("P19", False, "the probe did not build: " + "; ".join(error.diagnostics[:6]))
        return 1
    try:
        ran = subprocess.run([str(binary), "cost", str(COST)], capture_output=True, text=True,
                             timeout=1800)
    except subprocess.TimeoutExpired:
        shutil.rmtree(COST, ignore_errors=True)
        score("P19", False, "no answer within 1800 s")
        return 1
    shutil.rmtree(COST, ignore_errors=True)
    try:
        answered = {r["id"]: (r["pass"], r["detail"]) for r in json.loads(ran.stdout)["rows"]}
    except (ValueError, KeyError):
        score("P19", False, f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}")
        return 1
    score("P19", *answered.get("P19", (False, "the probe did not answer it")))
    return 0 if results["P19"][0] else 1


def mutants():
    killed = []
    for name, (named, file, before, after) in MUTANTS.items():
        here = WORK / "mutants" / name
        if here.exists():
            shutil.rmtree(here)
        sources = here / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        path = sources / file
        text = path.read_text()
        if text.count(before) != 1:
            print(f"mutant {name}: CONTROL FAILED — `{before}` found {text.count(before)} times")
            continue
        path.write_text(text.replace(before, after))
        rows = probe_rows(sources, here / "probe")
        why = rows[named[0]][1]
        if why.startswith(("the probe did not build", "no answer")):
            print(f"mutant {name}: CONTROL FAILED — {why[:300]}")
            continue
        failed = [row for row in named if not rows[row][0]]
        others = [row for row in P_ROWS if row not in named and not rows[row][0]]
        caught = len(failed) == len(named)
        if caught:
            killed.append(name)
        print(f"mutant {name}: {'killed' if caught else 'SURVIVED'} — named {named} failed "
              f"{failed}; other rows failing {others}", flush=True)
        for row in named:
            print(f"    {row}: {rows[row][1][:300]}")
    print(f"mutants: {len(killed)}/{len(MUTANTS)} killed")
    return 0 if len(killed) == len(MUTANTS) else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--only", help="comma-separated row ids")
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--cost", action="store_true",
                        help="P19 alone: SY-22's budget on the -O whole-module probe")
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    if args.mutants:
        return mutants()
    if args.cost:
        return cost()
    wanted = args.only.split(",") if args.only else S_ROWS + P_ROWS
    unknown = [row for row in wanted if row not in S_ROWS + P_ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    s_wanted = [row for row in wanted if row in S_ROWS]
    if s_wanted:
        if not args.socket:
            print("the S rows need the running instance's socket path")
            return 2
        files = {**fixtures(), **fixtures2(), **OWNER_FILES}
        try:
            mcp_rows(args.socket, [row for row in s_wanted if row not in ("S25", "S26")], files)
            held = [row for row in s_wanted if row in ("S25", "S26")]
            if held:
                held_rows(held, files)
        except Exception as error:  # an instrument failure is a scored FAIL of the rest
            for row in s_wanted:
                if row not in results:
                    score(row, False, f"not run: {type(error).__name__}: {error}")
    p_wanted = [row for row in wanted if row in P_ROWS]
    if p_wanted:
        rows = probe_rows(ROOT / "app/Sources", WORK / "probe")
        for row in p_wanted:
            score(row, *rows[row])
    passed = sum(1 for row in wanted if results.get(row, (False,))[0])
    print(f"scores: {passed}/{len(wanted)}")
    return 0 if passed == len(wanted) else 1


if __name__ == "__main__":
    sys.exit(main())
