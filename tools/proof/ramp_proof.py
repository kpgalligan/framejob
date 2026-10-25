#!/usr/bin/env python3
"""Speed ramps SR2a, SR2b, SR1d, SR3a, SR3b, SR4 and SR5 (spec §11 SR-10, SR-2, SR-6,
SR-12, SR-13, SR-15, SR-18, SR-19, SR-20, SR-21, SR-22), against the built app: an action's
`end.speed` through `set_action_end` over MCP — the door, the slot rule's R1
sentence, the ×12 answer, undo and redo (SR2a) — a ramped clip's rendered
audio in the export and in playback (SR2b, #111), Keep pitch inside a ramp
kept and placed by SR-13's led rate-mode arm (SR1d: K1, L1–L3), `trim_end`
and `split` on a ramped clip read through its map (SR3a: T1, S1), and
`set_speed` scaling a ramp's whole profile, the ×12 answer and the export
agreeing on the rate the clip names, and `set_canvas`'s re-snap keeping a
speed action past the clip's end (SR3b: V1–V3, C1), and Swift's readers
through `rc_project_source_map` — the filmstrip, the waveform, transcripts,
captions, fillers and silence — and Synchronize Audio refusing a ramp (SR4:
F1–F5, Q0–Q4, Y1), and the UI — the Speed section's Rate inside an action, the
band, the ×12 question for an end rate, the Speed sheet's ramp line — and
`set_action` on an action past its clip's end (SR5: G1–G6, Z1, Z2).

    env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py [--only IDS]
    env -u RC_ASSEMBLYAI_KEY RC_PROOF_APP=release python3 tools/proof/ramp_proof.py --baseline
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_proof.py --only E1 --mutant expect-shift
    env -u RC_ASSEMBLYAI_KEY python3 tools/proof/ramp_proof.py --only L1,L2,L3 --mutant keep-shift

One owned instance (`mcp.launch` on `proof_app`'s app — Debug by default,
`RC_PROOF_APP=release` for the record), launched with `-RCDevRampRenderHold 2`
(every ramp render held 2 s, so an export that follows an edit at once must
wait), on a scratch socket, logging to `tools/proof/work/ramp/framejob.log`,
stopped by its PID; nothing else is ever killed. Every project is written under
`tools/proof/work/ramp/`, which each run empties, and closed once its row is
scored. No row performs a menu item. SR2a's, SR3a's and SR3b's fixture is
`tools/proof/media/AV.mov` (5 s, 30 fps, 48 kHz sound); SR2b's are
`ramp_spike.make_fixtures(False)`'s clicks and sine movies (20 s, 320 × 180,
30 fps, frame i showing i in ten bars); a missing fixture is a scored FAIL.
SR2b's measuring is `ramp_spike`'s and `render_spike`'s, imported, never copied;
its probe reads (the plan, playback) are `ramp_spike_probe.swift`'s, built
through `ramp_spike.build_probe` over this tree's `app/Sources`, after the
instance has stopped.

SR2b's projects are one media clip at 0 on a 320 × 180 30 fps canvas, from
source in 1 s (`add_clip`, `trim_start` 1 s, `move_clip` −1 s, `set_speed`,
`trim_end`). RV1 is SR1b's: 8 s at ×1, keep pitch off, `add_action` [1 s, 3 s),
`set_action` linear, `set_action_end {speed: 2}`; RK1 the same at a ×1.1 base,
keep pitch on. Each is scored against `render_spike.variants()`'s RV1 or RK1.

D0  the instance listens, and `Frame Job: ` never appears in its log.
D1  a 2 s AV.mov clip, `add_action` [0, 1 s), `set_action_end {speed: 2}`
    applies; `get_project` holds `end.speed` 2 and the clip's start and
    duration as they were before the edit.
D2  a 2 s clip at in 0, an action over [0, 2 s) (linear, so S(D) = 1 s +
    x s): `speed: 5` is refused with R1, whose ×{fit} is this proof's own
    oracle from `get_project`'s media duration, floor(duration / 1 s − 1,
    0.001), and whose overrun is 6 s less that duration; then that rate
    applies.
D3  a 6-frame clip ramped over its length to ×20 answers `audio_left_out`
    [clip] and SpeedAudioDrop's one-clip `audio_note`, its template written
    here.
D4  `speed: "fast"`, and `speed: 2` on a text clip's action, are each an
    error carrying the core's exact sentence.
D5  `undo` takes D1's speed out of the end, and `redo` puts it back.
X0  the fixtures made and read back (`ramp_spike.z0`).
U1  CX1 (×1), CX2 (×2, keep pitch off) and CK05 (×0.5, keep pitch on), each
    4 s of the clicks fixture, rebuilt as `--baseline` built them: the plan
    text and `prores_422`'s video md5 equal `work/ramp-baseline/baseline.json`'s
    exactly. Every audio stream (`audio_wav`'s and `prores_422`'s, all three
    projects) is decoded (pcm_f32le, its own channels) and must be identical
    to the baseline's same stream, kept beside `baseline.json`, over
    min(round(timeline × rate), its length, the baseline's length). Each
    stream's length against the timeline, short or past the end, is
    reported, not scored (#337). Why not
    md5s: an export's audio length is not stable run to run, which predates
    SR2b — at `5042934` CK05's two exports gave two md5s (Apple's
    time-pitch), and CX2's `prores_422` audio ran 4 048 frames (≈ 84 ms) past
    its wav in one run and not in another, the samples identical over their
    common length.
E1  RV1 on clicks, `audio_wav` exported as the very next call after
    `set_action_end`, then `prores_422`: 0 wrong frames (`video_wrong` against
    RV1's G1 segments), clicks found == expected and `varispeed_pass` on the
    ideal map, and `<pkg>/cache/ramp-audio/<media>-<16 hex>.caf` exists.
E2  RV1 on sine: no `click_events(dense_scan(…), 0)` and no dropout.
N1  E1's document: an `audio_wav` export of the constant clip, made before
    `set_action_end`, and one after `undo` of it, have equal audio md5s.
K1  RK1 on sine: `pitch_track`'s windows, median |cents| ≤ 25 against
    220 Hz, separately over the windows inside the ramp (1 s, 3 s) and those
    outside it — Keep pitch holds inside a ramp (SR-13; SR-11 lifted).
L1  RK1 (×1.1 base, linear, `ramp_end` ×2) on clicks, keep pitch on,
    `audio_wav`: found share ≥ L_FOUND and max |diff| ≤ L_CEILING_MS against
    the ideal map — SR-7's floor and ceiling from SR1d's measured run's export
    controls (RC-on-x1.1 33/33 max 3.59 ms, RC-on-x2 60/60 max 12.60 ms:
    floor 1.00 − 0.10, ceiling 12.60 + 5.0). The lead is Apple's unpublished
    behaviour (SR-13): a macOS change that moves it fails here.
L2  RK2 (×0.9 base, `ramp_doc` curve ease_out, `ramp_end` ×0.5), likewise
    (RC-on-x0.9 27/27 max 4.89 ms, RC-on-x0.5 15/15 max 14.14 ms: floor 0.90,
    ceiling 19.14 ms).
L3  RK3 (×2 base, ease_in_out, `ramp_end` ×0.5), the owner's accepted limit
    (SR-15): found share ≥ 0.90 and max |diff| ≤ its measured worst in SR1d's
    run, 22.10 ms, plus a 5.0 ms margin (SR-7's own slack) = 27.10 ms, so the
    limit cannot grow unseen; SR1e kept the 56 ms lead and this ceiling
    (SR-16), and no other L row was added: H7 and H8 cross the same cliff.
R1  RV1 on clicks exported forward, then `set_reversed true`, the reverse
    waited for (`precision_proof.wait_reverse`), exported again: 0 wrong
    frames and clicks found == expected on the mirrored map (the reversed
    stream's clicks, frame j showing 599 − j), `varispeed_pass`, and the
    reversed render's file is named apart from the forward one's (SR-6 as
    amended by SR2b) — its audio md5 differs from the forward export's.
W1  RV1 on clicks, then `undo` and `redo` as the next two calls, inside the
    render's hold: the running render is dropped (no owner wants it) and
    wanted again — before it stops, when the redo beats the hold's next
    cancellation poll (every 50 ms). Its file lands within W1_BOUND_S
    (else FAIL, no export made: one would wait for ever), and an `audio_wav`
    export then holds every click on the ideal map (`varispeed_pass`). The
    redo must follow the edit by less than the hold, or the row reached
    nothing and FAILs.
P1  RV1 (exported once) and a ×1 control (6 s) saved and closed, then the
    spike probe's `playback` group (`tap`, `frames`) on both packages: 0 wrong
    frames on both, RV1's tap after `pt1`'s m1 (the control's playback against
    its export) found == expected and `varispeed_pass`, and
    `agreement(export, playback)` ok. Both corrected taps are trimmed, not
    zero-padded (`render_spike.place_corrected`, SR-17): a click outside the
    samples the tap carried is unobserved, not missed.
T1  a 2 s AV.mov clip at in 0, `add_action` [0, 1 s), `set_action_end
    {speed: 2}`, then `trim_end` to 10 s: the duration is snapped_down(1 s +
    (file − 1.5 s) / 2), the end S∞ reaches inside the file, from
    `get_project`'s media duration (SR-18 (a)); the end rate is kept.
S1  a 2 s AV.mov clip at in 0, `add_action` [0, 2 s) (linear), `set_action_end
    {speed: 3}`, then `split` at 1 s: the second half's `in` is 900000
    (S(1 s) = 1.5 s) and its `speed` ×2, the head's end `speed` ×2 and the
    tail's ×3, the rates within 1e-9 (SR-18 (e)).
V1  a 2 s AV.mov clip at in 0, `add_action` [0, 1 s), `set_action_end
    {speed: 2}`, then `set_speed rate 2`: speed 2, end `speed` 4, duration
    600000 and the action [0, 300000) — one factor scales the whole profile
    (SR-19 (a), (b)).
V2  the same clip at `set_speed rate 7` (end ×14) answers `audio_left_out`
    [clip] and D3's one-clip `audio_note`.
V3  a 1 s AV.mov clip at in 0, `add_action` [0, 1 s), `set_action_end
    {speed: 6}`, `trim_end` to 300000, and AV.mov ×1 at 1 s cut to 1.5 s;
    then `set_speed rate 2.5`: duration 120000, the action [0, 240000) and
    end 15, and the answer carries `audio_left_out` [clip] though the clip
    reaches only ×8.75 inside itself (SR-19 (d), the rate it names); an
    `audio_wav` export (`read_ffmpeg`) is silent (max |x| < 1e-4) over
    [0, 0.2 s) and carries the tone (RMS > 0.01) over [1.1 s, 1.4 s].
C1  a 2 s AV.mov clip at in 0, `add_action` [0, 2 s), `set_action_end
    {speed: 3}`, `trim_end` to 1 s, then `set_canvas fps [25, 1]`: the
    action stays [0, 1200000) with end 3, the duration 600000 (SR-19 (g)).

SR4's F rows read `ramp_mapper_probe.swift`, copied in as `main.swift` under
`work/ramp/mapper/` and built with `swift_build.build()` over this tree's
`app/Sources` (as `transcript_proof.build` builds its probe), run once under a
60 s wall (a timeout fails every F row). Its projects are in-process, a 10 s
A/V media with no file, a clip at 0.5 s from in 0.5 s, 5 s long, ramped by an
action [0, 2 s), linear, to ×2 — S(t) = t + t²/4 s, then 3 s + 2(t − 2 s), so
it reads S(5 s) = 9 s — beside a ×1.5 constant twin and a reversed ramped
twin. Every oracle is this file's S and S⁻¹ (`s_of`, `s_inv`).
F1  `ReelProject.sourceMap`: ramped true, the breakpoints 0, every 600 ticks
    to 2 s, 2 s and D, each source in + round(S) (±1), equal to the plan's
    audio `ramp.map`; the constant twin [[0, in], [D, in + round(D × 1.5)]]
    and ramped false; the reversed twin's map the forward one's; an unknown
    id nil.
F2  `TimelineView.sourceTime(…map:)` at every frame: in + ⌊S(t − start)⌋
    (±1), the reversed twin file − that; the constant map and a nil map equal
    the three-argument form exactly at every frame.
F3  `Transcriber.jobs(…maps:)`'s job (in, round(S(D)), the map, the base
    speed); `MediaTranscript.project` and `Transcriber.project` against
    start + round½(S⁻¹(m − in)) (±2); `recognitionJob` for [2 s, 3 s), each
    end and the whole clip, padded 2 s of SOURCE and mapped back (±2), its
    1 s placed as the whole job places it; the three-argument form refuses
    the ramped clip by SR-20 (f)'s sentence and gives the constant twin the
    four-argument form's job.
F4  `MediaPeaks.sourceTick` on the plan's ramp audio segment at every frame
    against in + ⌊S(t − start)⌋ (±1); the constant segment's reading exactly
    in + ⌊(t − start) × source_duration / duration⌋.
F5  SR-20 (c): a 100 000-point map (clip 600·k, source 600·k + 3k(k + 1)) is
    made; 100 000 `source(atClip:)`, 100 000 `clip(atSource:)` at an LCG's
    positions and 10 000 `sourceTick` on a decoded `PlanSegment` carrying it,
    each batch under 2 s, every breakpoint hit exact.
Q0–Q3 run on a second owned instance (`mcp.launch` with `-RCSecretFolder` a
0700 folder of dummy 0600 keys and `-RCAssemblyAIEndpoint` at
`cloud_captions_probe.Fake("ramp")`, under `hold_cloud_lock(1800)`, logging
to `work/ramp/framejob-cloud.log`), serving `cloud_captions_proof`'s
DISFLUENT_WORDS; `transcribe {engine: assemblyai, place: false}`, no paid
request.
Q0  that instance listens and its log holds no `Frame Job: `.
Q1  speech.mov at 1 s, in 0, 3 s long, ramped [0, 2 s) to ×2 (it reads 5 s
    of 5.248 s): `get_transcript`'s words, crossing the ramp and the ×2
    piece, at start + round½(S⁻¹(m − in)) (±2), kept by in ≤ m < in +
    round(S(D)).
Q2  a ×1.5 speech.mov clip: its words exactly `cloud_captions_proof.mapped`.
Q3  `detect_fillers` on Q1's clip: TR-9's grid (`fillers_proof.tr9`) placed
    through S⁻¹ and snapped inward to frames, each edge equal (or a frame
    off where S⁻¹ lies within 2 ticks of a frame boundary, reported).
Q4  (main instance) silence.mov at 0, in 0, 5 s, ramped as F's (it reads 9 s
    of 10 s): `detect_silence {clips, mode: level, min_length: 120000}`,
    re-asked while `pending_peaks`, finds [S⁻¹(2 s), S⁻¹(3.5 s)] and
    [S⁻¹(6 s), S⁻¹(7 s)] inset by `padding`, each edge within a 10 ms bucket
    and a frame.
Y1  (main instance) a 2 s AV.mov clip ramped [0, 1 s) to ×2 and a constant
    AV.mov clip on a second track: `sync_audio` with either as anchor is
    refused, naming `clip <ramped>: ` and `AudioSync.ramped`'s sentence.

SR5's G rows read `ramp_ui_probe.swift`, copied in as `main.swift` under
`work/ramp/ui/` and built as the mapper probe is, run once under a 60 s wall (a
timeout fails every G row). Its project is in-process, written to
`work/ramp/ui/ramp-ui.framejob` and opened in a `ProjectDocument` with an
`InspectorViewController`: clip "one" (10 s media, at 0.5 s from in 0.5 s, 5 s)
with action A [0, 2 s) linear to ×2 and action B [3 s, 4 s) to opacity 0.5;
clip "two" (2 s, an action [0, 2 s) linear to ×3, then `trim_end` to 1 s, so the
action runs past the end); and, from a 60 s media at in 0, P (0.5 s at ×1, one
action [0, 0.5 s) to ×2), Q (`set_speed` 13, then 0.5 s, one action to ×13) and
R (a constant ×2 clip, 0.5 s).
G1  `VideoPane.rateOps` at ×3: A selected → one `set_action_end {speed: 3}` on
    A; B selected → the same on B; none selected → one `set_speed` on clip one;
    two clips → one `set_speed` each. With A selected the Keep pitch row's own
    ops (its default's) are one `set_speed` at the BASE ×1 with `keep_pitch`,
    its gutter writes `speed` and is ⊘, and Fit to's is ⊘ too (SR-21 (a)).
G2  `VideoPane.rateRead`: A → 2 (its end), B → 2 (the core's rate in force at
    B's end), none → 1 (the base), at the playhead at clip 1 s → 1.5 (and the
    "now" reading 1.5), the past-end action selected → its end ×3, not the ×2
    the clip reaches at its end (SR-21 (b)).
G3  `ActionBands.keys`: A's end → [speed]; a zoom end naming a rate → [scale,
    speed, x, y] and `isZoom` false; the bare zoom true; A not a zoom (SR-21 (d)).
G4  `SpeedAudioDrop`: each trial a `set_action_end {speed}`, its outcome arm
    scored `applied` FIRST (any other arm fails the row): P's end ×14 (it reads
    3.75 s) → [P] at 14; P's end ×12 → []; Q's end ×14, already above ×12 → [];
    `mayCross` true for an end naming `speed` and `set_speed`, false for an
    opacity end and `set_action`; the Speed section's note on P from the
    applied ×14 snapshot is "Audio is silent above ×12", on R nil (SR-21 (e)).
G5  `paths(of:)`: `set_speed` → [speed], Rate's ops with A → [speed]; A's keyed
    paths [speed]; `clearOps([speed])` → one `set_action_end {speed: null}`;
    the Clip sub-tab's ◆N 1 for A, 0 for B; Rate's mark keyed with A, other(1)
    with none selected (SR-21 (c)).
G6  `SpeedSheetController.readout` of clip one at ×2: its last line
    `rampLine`, once; the trial's A end ×4 at base ×2 (rule L); R at ×1 reads
    exactly ["1 clip · 00:00:00:15 → 00:00:01:00"], no ramp line (SR-21 (f)).
Z1  (main instance) a constant AV.mov clip, `add_action` [1 s, 2 s), `trim_end`
    to 1.5 s: `set_action curve` applies with the span unchanged; duration +1
    frame is refused in `action_past_end`'s whole sentence; start −1 frame
    applies; start +1 frame (from 1 s) is refused likewise; `undo` restores the
    start (SR-22, #338).
Z2  (main instance) AV.mov 2 s ramped [0, 2 s) to ×2, `trim_end` to 1 s: `set_action
    curve ease_out` applies on the past-end speed action and `set_action_end
    {speed: 2.5}` applies; the span and the clip's duration are kept.

`--baseline` (before any SR2b app edit, on Release) builds CX1, CX2 and CK05
and writes `tools/proof/work/ramp-baseline/baseline.json`: the commit and dirt
of the app's own tree (`--app` may name another checkout's build), the app,
each project's plan text and md5s, and every audio stream's decoded PCM beside
it (`<name>-<stream>.f32`); it runs no row but X0 and prints `BL`.
`--mutant expect-shift` moves E1's expected clicks 2 ms late (no rebuild): E1
must fail. `--mutant keep-shift` moves each L row's expectation
`keep_shift_s(variant)` late, 2 × its ceiling + 1 ms, so a shifted click lands
past the ceiling or outside the reach whatever the residuals' sign: L1, L2
and L3 must fail. Rows print `<ID> pass|fail — <detail>`, then `n/m`; exit 0 iff every
row run passed. `--only D1,E1` runs those rows (D0 always; Q0 with any Q1–Q3,
and Q1 with Q3).
"""

import argparse
import contextlib
import json
import math
import os
import re
import shutil
import statistics
import subprocess
import sys
import time
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/proof/graphics_spike"))
sys.path.insert(0, str(ROOT / "tools/proof"))
sys.path.insert(0, str(ROOT / "tools/proof/ramp_spike"))
import bounded  # noqa: E402
import mcp  # noqa: E402
import precision_proof  # noqa: E402
import proof_app  # noqa: E402
import ramp_spike as rs  # noqa: E402
import render_spike as rsp  # noqa: E402
import swift_build  # noqa: E402
import tree_copy  # noqa: E402
from export_offset_proof import read_ffmpeg  # noqa: E402
from media_less_playback_probe import build_shader  # noqa: E402

WORK = ROOT / "tools/proof/work/ramp"
EXPORTS = WORK / "exports"
PROBE_WORK = WORK / "probe"
BASELINE = ROOT / "tools/proof/work/ramp-baseline/baseline.json"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
SPEECH_MOV = ROOT / "tools/proof/media/speech.mov"
SILENCE_MOV = ROOT / "tools/proof/media/silence.mov"
MAPPER_PROBE = ROOT / "tools/proof/ramp_mapper_probe.swift"
MAPPER_WORK = WORK / "mapper"
UI_PROBE = ROOT / "tools/proof/ramp_ui_probe.swift"
UI_WORK = WORK / "ui"
UI_WALL = 60
MAPPER_WALL = 60
F5_BOUND_S = 2.0
Q4_BUCKET = 6_000
SYNC_RAMPED = ("ramps its speed (a speed action changes its rate over its length); "
               "Synchronize Audio lines up clips playing at one rate.")
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
HOLD_S = 2
W1_BOUND_S = 60
SR2A_ROWS = ["D1", "D2", "D3", "D4", "D5"]
SR2B_ROWS = ["X0", "U1", "E1", "E2", "N1", "K1", "L1", "L2", "L3", "R1", "W1", "P1"]
SR3A_ROWS = ["T1", "S1"]
SR3B_ROWS = ["V1", "V2", "V3", "C1"]
SR4_PROBE_ROWS = ["F1", "F2", "F3", "F4", "F5"]
SR4_CLOUD_ROWS = ["Q0", "Q1", "Q2", "Q3"]
SR4_APP_ROWS = ["Q4", "Y1"]
SR5_PROBE_ROWS = ["G1", "G2", "G3", "G4", "G5", "G6"]
SR5_APP_ROWS = ["Z1", "Z2"]
ROWS = (["D0"] + SR2A_ROWS + SR2B_ROWS + SR3A_ROWS + SR3B_ROWS + SR4_PROBE_ROWS
        + SR4_CLOUD_ROWS + SR4_APP_ROWS + SR5_PROBE_ROWS + SR5_APP_ROWS)
RAMP_LINE = "Each speed ramp keeps its shape: the rates it names scale with the base rate."
SILENT_NOTE = "Audio is silent above ×12"
# name: (rate, keep pitch or None for the default, length ticks)
CONSTANTS = {"CX1": (1.0, None, 4 * SEC), "CX2": (2.0, False, 4 * SEC),
             "CK05": (0.5, True, 4 * SEC)}
CONTROL_LENGTH = 6 * SEC
RAMP_SPAN_S = (1.0, 3.0)
PITCH_CENTS = 25.0
SHIFT_S = 0.002
MUTANTS = ["expect-shift", "keep-shift"]
# SR1d's measured run (archive/speed-ramps.md's SR1d record, results.json at
# 2026-10-23 21:34:59): SR-7's floor (the lower export control found share −
# 0.10) and ceiling (the greater export control max |diff| + 5.0 ms) for RK1
# and RK2; RK3's measured worst 22.10 ms + a 5.0 ms margin (SR-15).
L_FOUND = {"RK1": 0.90, "RK2": 0.90, "RK3": 0.90}
L_CEILING_MS = {"RK1": 17.60, "RK2": 19.14, "RK3": 27.10}
# row: (variant, base rate, curve, end rate), keep pitch on, on clicks.
L_ROWS = {"L1": ("RK1", 1.1, "linear", 2), "L2": ("RK2", 0.9, "ease_out", 0.5),
          "L3": ("RK3", 2.0, "ease_in_out", 0.5)}
NAME = re.compile(r"^(\d+)-[0-9a-f]{16}\.caf$")

rows = {}
MUTANT = None


def check(row, good, detail=""):
    rows[row] = bool(good)
    print(f"{row} {'pass' if good else 'fail'} — {detail}", flush=True)


def attempt(client, tool, arguments):
    """One MCP call: a refusal or an error is an answer, not an exception."""
    try:
        return {"ok": True, "reply": client.call_with(tool, arguments)}
    except mcp.ToolError as error:
        return {"ok": False, "error": str(error)}


def must(client, tool, arguments):
    got = attempt(client, tool, arguments)
    if not got["ok"]:
        raise RuntimeError(f"{tool} {arguments}: {got['error']}")
    return got["reply"]


def rust_float(value):
    """A rate as the core's `{}` prints an f64: `4`, `2.666`."""
    return str(int(value)) if float(value).is_integer() else repr(float(value))


class Doc:
    """One project file, every call addressed to it."""

    def __init__(self, client, name):
        self.client = client
        self.path = str(WORK / f"{name}.framejob")
        must(client, "new_project", {"path": self.path})

    def call(self, tool, **arguments):
        return attempt(self.client, tool, dict(arguments, project=self.path))

    def must(self, tool, **arguments):
        return must(self.client, tool, dict(arguments, project=self.path))

    def project(self):
        return self.must("get_project")["project"]

    def clip(self, clip):
        return next(c for c in self.project()["clips"] if c["id"] == clip)

    def close(self):
        attempt(self.client, "close_project", {"project": self.path, "discard": True})

    def av_clip(self, length):
        """AV.mov at 0 on the first track, from in 0, cut to `length`; its
        clip id and media row."""
        media = self.must("import_media", path=str(AV_MOV))["media"]
        track = self.project()["tracks"][0]["id"]
        self.must("add_clip", track=track, media=media, at=0)
        project = self.project()
        clip = project["clips"][-1]["id"]
        if project["clips"][-1]["duration"] != length:
            self.must("trim_end", clip=clip, to=length)
        row = next(m for m in project["media"] if m["id"] == media)
        return clip, row

    def action(self, clip, at, duration):
        answer = self.must("add_action", clip=clip, at=at, duration=duration)
        return answer["new_actions"][0]

    # ---- SR2b ----

    def canvas(self):
        self.must("set_canvas", width=rs.WIDTH, height=rs.HEIGHT, fps=rs.FPS)

    def fixture_clip(self, fixture, length, rate=1.0, keep=None):
        """`fixture` at 0 from source in 1 s, at `rate` (keep pitch `keep`,
        None the default), cut to `length`; (clip, media)."""
        media = self.must("import_media", path=str(rs.FIXTURES / rs.FIXTURE_FILES[fixture]))[
            "media"]
        track = self.project()["tracks"][0]["id"]
        clip = self.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
        self.must("trim_start", clip=clip, to=rs.SOURCE_IN)
        self.must("move_clip", clips=[clip], delta=-rs.SOURCE_IN)
        if rate != 1.0 or keep is not None:
            self.must("set_speed", clip=clip, rate=rate,
                      **({} if keep is None else {"keep_pitch": keep}))
        self.must("trim_end", clip=clip, to=length)
        placed = self.clip(clip)
        if (placed["start"], placed["duration"], placed["source"].get("in")) != (
                0, length, rs.SOURCE_IN):
            raise RuntimeError(f"the clip landed as {placed}")
        return clip, media

    def export(self, preset, tag):
        """The finished export's path (`mcp.export_with` follows the queue)."""
        EXPORTS.mkdir(parents=True, exist_ok=True)
        out = EXPORTS / f"{tag}.{'wav' if preset == 'audio_wav' else 'mov'}"
        out.unlink(missing_ok=True)
        self.client.export_with({"project": self.path, "preset": preset, "path": str(out)},
                                seconds=CALL_BOUND)
        return out

    def renders(self):
        folder = Path(self.path) / "cache" / "ramp-audio"
        return sorted(p.name for p in folder.iterdir()) if folder.is_dir() else []


def media_name(row):
    """`MediaSnapshot.name`: the original's file name, else the path's."""
    original = row.get("original") or {}
    return os.path.basename(original.get("path") or row["path"])


# ---- SR2a ------------------------------------------------------------------------


def d1(client, state):
    doc = Doc(client, "d1")
    state["d1"] = doc
    clip, _ = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, SEC)
    before = doc.clip(clip)
    got = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 2})
    after = doc.clip(clip)
    end = after["actions"][0]["end"]
    kept = (after["start"], after["duration"]) == (before["start"], before["duration"])
    state["d1_clip"] = clip
    check("D1", got["ok"] and end.get("speed") == 2 and kept,
          f"answer {got.get('reply', got.get('error'))!r:.120}; end {end}; "
          f"start/duration {after['start']}/{after['duration']} "
          f"(were {before['start']}/{before['duration']})")


def d2(client, state):
    doc = Doc(client, "d2")
    clip, media = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, 2 * SEC)
    duration = media["duration"]
    fit = math.floor((duration / SEC - 1) * 1000) / 1000
    over = 6 * SEC - duration
    expected = (f"ending action {action} at ×5 would read clip {clip} {over} ticks past the "
                f"end of its media; the largest end rate that fits is ×{rust_float(fit)}")
    refused = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 5})
    named = (not refused["ok"]) and refused["error"].endswith(expected)
    applied = doc.call("set_action_end", clip=clip, action=action, patch={"speed": fit})
    end = doc.clip(clip)["actions"][0]["end"]
    check("D2", named and applied["ok"] and end.get("speed") == fit,
          f"media {duration} ticks; refusal {refused.get('error', 'none')!r}; "
          f"expected …{expected!r}; ×{rust_float(fit)} "
          f"{'applied' if applied['ok'] else applied.get('error')}, end {end}")
    doc.close()


def d3(client, state):
    doc = Doc(client, "d3")
    clip, media = doc.av_clip(6 * FRAME)
    action = doc.action(clip, 0, 6 * FRAME)
    got = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 20})
    answer = got.get("reply") if got["ok"] else {}
    note = (f"Clip {clip} (“{media_name(media)}”) now plays above ×12, so its audio is left "
            f"out: it is silent in the preview and the export.")
    good = (got["ok"] and isinstance(answer, dict)
            and answer.get("audio_left_out") == [clip] and answer.get("audio_note") == note)
    check("D3", good,
          f"audio_left_out {answer.get('audio_left_out') if isinstance(answer, dict) else None}; "
          f"audio_note {answer.get('audio_note') if isinstance(answer, dict) else got}; "
          f"expected {note!r}")
    doc.close()


def d4(client, state):
    doc = Doc(client, "d4")
    clip, _ = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, SEC)
    fast = doc.call("set_action_end", clip=clip, action=action, patch={"speed": "fast"})
    number = 'speed must be a number, not "fast"'
    track = doc.project()["tracks"][0]["id"]
    doc.must("add_text_clip", track=track, at=3 * SEC, duration=SEC)
    text = doc.project()["clips"][-1]["id"]
    text_action = doc.action(text, 0, SEC // 2)
    on_text = doc.call("set_action_end", clip=text, action=text_action, patch={"speed": 2})
    media_only = (f"clip {text} is not a media clip, and only a media clip's action can end "
                  f"at a speed")
    good = (not fast["ok"] and number in fast["error"]
            and not on_text["ok"] and media_only in on_text["error"])
    check("D4", good, f"fast: {fast.get('error', fast.get('reply'))!r}; "
                      f"text clip: {on_text.get('error', on_text.get('reply'))!r}")
    doc.close()


def d5(client, state):
    doc = state.get("d1")
    if doc is None:
        doc = Doc(client, "d1")
        state["d1"] = doc
        clip, _ = doc.av_clip(2 * SEC)
        action = doc.action(clip, 0, SEC)
        doc.must("set_action_end", clip=clip, action=action, patch={"speed": 2})
        state["d1_clip"] = clip
    clip = state["d1_clip"]
    undone = doc.call("undo")
    after_undo = doc.clip(clip)["actions"][0]["end"]
    redone = doc.call("redo")
    after_redo = doc.clip(clip)["actions"][0]["end"]
    check("D5", undone["ok"] and "speed" not in after_undo and redone["ok"]
          and after_redo.get("speed") == 2,
          f"undo {undone.get('reply', undone.get('error'))!r:.80} → end {after_undo}; "
          f"redo {redone.get('reply', redone.get('error'))!r:.80} → end {after_redo}")
    doc.close()


# ---- SR3a ------------------------------------------------------------------------


def t1(client, state):
    doc = Doc(client, "t1")
    clip, media = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, SEC)
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": 2})
    got = doc.call("trim_end", clip=clip, to=10 * SEC)
    after = doc.clip(clip)
    # S∞: 1.5 s by 1 s, then ×2 held, so the file's remainder is reached at
    # 1 s + (file − 1.5 s) / 2, floored, the end snapped down onto the grid.
    file = media["duration"]
    reach = SEC + (file - 900_000) // 2
    expected = (reach // FRAME) * FRAME
    check("T1", got["ok"] and after["duration"] == expected
          and after["actions"][0]["end"].get("speed") == 2,
          f"media {file} ticks; trim_end {got.get('reply', got.get('error'))!r:.80}; "
          f"duration {after['duration']} (expected {expected}); end {after['actions'][0]['end']}")
    doc.close()


def s1(client, state):
    doc = Doc(client, "s1")
    clip, _ = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, 2 * SEC)
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": 3})
    got = doc.call("split", clips=[clip], at=SEC)
    project = doc.project()
    first = next(c for c in project["clips"] if c["id"] == clip)
    second = next((c for c in project["clips"] if c["start"] == SEC), None)
    close = lambda a, b: a is not None and abs(a - b) < 1e-9  # noqa: E731
    head = first["actions"][0]["end"].get("speed")
    tail = second["actions"][0]["end"].get("speed") if second and second["actions"] else None
    # Linear ×1 → ×3 over 2 s cut at 1 s: S(1 s) = 1 s + 2·2 s·⅛ = 1.5 s, ×2
    # there; the head ends at ×2, the tail runs on from ×2 to ×3.
    good = (got["ok"] and second is not None and second["source"].get("in") == 900_000
            and close(second.get("speed"), 2.0) and close(head, 2.0) and close(tail, 3.0))
    check("S1", good,
          f"split {got.get('reply', got.get('error'))!r:.80}; second "
          f"{None if second is None else (second['source'].get('in'), second.get('speed'))} "
          f"(expected (900000, 2)); head end ×{head}, tail end ×{tail}")
    doc.close()


# ---- SR3b ------------------------------------------------------------------------


def left_out_note(clip, media):
    """D3's one-clip `audio_note`, SpeedAudioDrop's template."""
    return (f"Clip {clip} (“{media_name(media)}”) now plays above ×12, so its audio is left "
            f"out: it is silent in the preview and the export.")


def v_ramp(doc):
    """V1's and V2's clip: 2 s of AV.mov at in 0, [0, 1 s) ending at ×2."""
    clip, media = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, SEC)
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": 2})
    return clip, media


def v1(client, state):
    doc = Doc(client, "v1")
    clip, _ = v_ramp(doc)
    got = doc.call("set_speed", clip=clip, rate=2)
    after = doc.clip(clip)
    ramp = after["actions"][0]
    # One factor, 2: the base and the end rate double, every span halves.
    good = (got["ok"] and after["speed"] == 2 and ramp["end"].get("speed") == 4
            and after["duration"] == SEC and (ramp["start"], ramp["duration"]) == (0, SEC // 2))
    check("V1", good,
          f"set_speed {got.get('reply', got.get('error'))!r:.80}; speed {after['speed']}, end "
          f"{ramp['end']}, duration {after['duration']}, action [{ramp['start']}, "
          f"{ramp['start'] + ramp['duration']}) (expected 2, 4, {SEC}, [0, {SEC // 2}))")
    doc.close()


def v2(client, state):
    doc = Doc(client, "v2")
    clip, media = v_ramp(doc)
    got = doc.call("set_speed", clip=clip, rate=7)
    answer = got.get("reply") if got["ok"] else {}
    note = left_out_note(clip, media)
    good = (got["ok"] and isinstance(answer, dict)
            and answer.get("audio_left_out") == [clip] and answer.get("audio_note") == note)
    check("V2", good,
          f"audio_left_out {answer.get('audio_left_out') if isinstance(answer, dict) else None}; "
          f"audio_note {answer.get('audio_note') if isinstance(answer, dict) else got}; "
          f"expected {note!r}; end {doc.clip(clip)['actions'][0]['end']}")
    doc.close()


def v3(client, state):
    doc = Doc(client, "v3")
    media = doc.must("import_media", path=str(AV_MOV))["media"]
    track = doc.project()["tracks"][0]["id"]
    clip = doc.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
    doc.must("trim_end", clip=clip, to=SEC)
    action = doc.action(clip, 0, SEC)
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": 6})
    doc.must("trim_end", clip=clip, to=300_000)
    tone = doc.must("add_clip", track=track, media=media, at=SEC)["new_clips"][0]
    doc.must("trim_end", clip=tone, to=SEC + SEC // 2)
    row = next(m for m in doc.project()["media"] if m["id"] == media)
    got = doc.call("set_speed", clip=clip, rate=2.5)
    answer = got.get("reply") if got["ok"] else {}
    after = doc.clip(clip)
    ramp = after["actions"][0]
    # The clip ends at t = 120 000 inside [0, 240 000) ×2.5 → ×15: it reaches
    # 2.5 + 12.5 / 2 = ×8.75 and names ×15, so its audio is left out, and the
    # answer and the export agree on that.
    shaped = (after["duration"] == 120_000 and (ramp["start"], ramp["duration"]) == (0, 240_000)
              and ramp["end"].get("speed") == 15)
    answered = (got["ok"] and isinstance(answer, dict) and answer.get("audio_left_out") == [clip]
                and answer.get("audio_note") == left_out_note(clip, row))
    x, rate = read_ffmpeg(doc.export("audio_wav", "v3-wav"))
    head = x[:int(0.2 * rate)]
    body = x[int(1.1 * rate):int(1.4 * rate)]
    peak = max((abs(v) for v in head), default=1.0)
    rms = math.sqrt(sum(v * v for v in body) / len(body)) if body else 0.0
    check("V3", shaped and answered and head and peak < 1e-4 and rms > 0.01,
          f"duration {after['duration']}, action [{ramp['start']}, "
          f"{ramp['start'] + ramp['duration']}), end {ramp['end']} (expected 120000, "
          f"[0, 240000), 15); audio_left_out "
          f"{answer.get('audio_left_out') if isinstance(answer, dict) else got}; export "
          f"max |x| over [0, 0.2 s) {peak:.2e} (< 1e-4), RMS over [1.1 s, 1.4 s] {rms:.4f} "
          f"(> 0.01)")
    doc.close()


def c1(client, state):
    doc = Doc(client, "c1")
    clip, _ = doc.av_clip(2 * SEC)
    action = doc.action(clip, 0, 2 * SEC)
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": 3})
    doc.must("trim_end", clip=clip, to=SEC)
    got = doc.call("set_canvas", fps=[25, 1])
    after = doc.clip(clip)
    ramp = after["actions"][0]
    # The re-snap keeps the speed action running past the clip's end.
    good = (got["ok"] and after["duration"] == SEC
            and (ramp["start"], ramp["duration"]) == (0, 2 * SEC)
            and ramp["end"].get("speed") == 3)
    check("C1", good,
          f"set_canvas {got.get('reply', got.get('error'))!r:.80}; duration "
          f"{after['duration']}, action [{ramp['start']}, {ramp['start'] + ramp['duration']}), "
          f"end {ramp['end']} (expected {SEC}, [0, {2 * SEC}), 3)")
    doc.close()


# ---- SR2b: measuring (ramp_spike and render_spike, imported) ---------------------


def md5_of(path, stream):
    """The md5 of `path`'s decoded audio (pcm_f32le) or video stream."""
    argv = ["ffmpeg", "-v", "error", "-i", str(path), "-map", f"0:{stream}"]
    argv += (["-c:a", "pcm_f32le"] if stream == "a" else []) + ["-f", "md5", "-"]
    ran = rs.run(argv, 300)
    return ran["stdout"].strip().split("=", 1)[-1]


def pcm_of(path):
    """`path`'s decoded audio, interleaved pcm_f32le at its own channels:
    (bytes, channels, rate)."""
    probe = rs.run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
                    "stream=channels,sample_rate", "-of", "json", str(path)], 120)
    stream = json.loads(probe["stdout"])["streams"][0]
    out = Path(str(path) + ".pcm.f32")
    rs.run(["ffmpeg", "-v", "error", "-y", "-i", str(path), "-map", "0:a:0", "-c:a",
            "pcm_f32le", "-f", "f32le", str(out)], 300)
    data = out.read_bytes()
    out.unlink(missing_ok=True)
    return data, int(stream["channels"]), int(stream["sample_rate"])


def pcm_compare(got, base, length):
    """Two `pcm_of` answers against a timeline of `length` ticks: (ok, detail) —
    identical over min(round(length × rate), both lengths); each length
    against the timeline reported (#337), not scored."""
    (a, ca, ra), (b, cb, rb) = got, base
    if (ca, ra) != (cb, rb):
        return False, f"{ca} ch {ra} Hz ≠ {cb} ch {rb} Hz"
    width = 4 * ca
    n = round(length / SEC * ra)
    fa, fb = len(a) // width, len(b) // width
    m = min(n, fa, fb)
    same = m > 0 and a[:m * width] == b[:m * width]
    return same, (f"{'=' if same else '≠'} over {m} frames; against the timeline's {n}: run "
                  f"{fa - n:+d}, baseline {fb - n:+d} (#337, not scored)")


def variant(name):
    return rsp.variants()[name]


def placement(samples, rate, v, shift_s=0.0):
    """`place_ideal`, its expectation `shift_s` late (IM1) by the signal moved
    as early (`render_spike.shift_signal`)."""
    k = int(round(shift_s * rate))
    return rsp.place_ideal(rsp.shift_signal(samples, k) if k else samples, rate, v)


def place_text(s):
    return (f"{s['found']}/{s['of']} clicks, median "
            + (f"{s['median_ms']:+.3f} ms, spread {s['spread_ms']:.3f} ms"
               if s["median_ms"] is not None else "—"))


@contextlib.contextmanager
def mirrored_clicks():
    """`ramp_spike.CLICKS` as the reversed stream holds them, for one read:
    a click at source tick c of the media is at duration − c reversed."""
    kept = rs.CLICKS
    rs.CLICKS = sorted(rs.MEDIA_DURATION - c for c in kept)
    try:
        yield
    finally:
        rs.CLICKS = kept


def mirrored_wrong(bars, v):
    """`video_wrong` with reversed stream frame m showing fixture frame
    599 − m: [(frame k, read, allowed)] for every frame that does not."""
    allowed = [{rs.FIXTURE_FRAMES - 1 - m for m in ok} for ok in rs.expected_frames(v)]
    wrong = []
    for k, ok in enumerate(allowed):
        read = rs.bits_of(bars[k]) if k < len(bars) and bars[k] is not None else None
        if read not in ok:
            wrong.append((k, read, sorted(ok)))
    return wrong


def ramp_doc(client, name, fixture, base, keep, curve="linear"):
    """A document holding a ramp's clip at `base` with its action over
    [1 s, 3 s) on `curve`, the end not applied (`ramp_end` does it, so N1's
    constant export comes first); (doc, clip, media, action)."""
    doc = Doc(client, name)
    doc.canvas()
    clip, media = doc.fixture_clip(fixture, 8 * SEC, base, keep)
    action = doc.action(clip, SEC, 2 * SEC)
    made = next(a for a in doc.clip(clip)["actions"] if a["id"] == action)
    if made.get("curve", "linear") != curve:  # set_action of the same curve is an identity
        doc.must("set_action", clip=clip, action=action, curve=curve)
    return doc, clip, media, action


def ramp_end(doc, clip, action, speed=2):
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": speed})


def build_constants(client):
    """CX1, CX2, CK05: {name: {path, md5}}; each package saved, then closed."""
    out = {}
    for name, (rate, keep, length) in CONSTANTS.items():
        doc = Doc(client, name.lower())
        doc.canvas()
        doc.fixture_clip("clicks", length, rate, keep)
        doc.must("save_project")
        wav = doc.export("audio_wav", f"{name}-wav")
        mov = doc.export("prores_422", f"{name}-prores")
        out[name] = {"package": doc.path, "md5": {
            "wav_audio": md5_of(wav, "a"), "prores_audio": md5_of(mov, "a"),
            "prores_video": md5_of(mov, "v")},
            "audio": {"wav_audio": wav, "prores_audio": mov}}
        doc.close()
    return out


# ---- SR2b: the app rows ---------------------------------------------------------


def x0(client, state):
    try:
        rs.make_fixtures(False)
        ok, detail = rs.z0()
    except Exception as error:  # an instrument that breaks is a FAIL
        ok, detail = False, f"{type(error).__name__}: {error}"
    state["fixtures"] = ok
    check("X0", ok, detail)


def u1(client, state):
    state["u1"] = build_constants(client)


def rv1(client, state):
    """E1's document, shared with N1: the constant export before the ramp
    edit, then the two exports after it."""
    if "rv1" in state:
        return state["rv1"]
    doc, clip, media, action = ramp_doc(client, "rv1", "clicks", 1.0, False)
    constant = doc.export("audio_wav", "rv1-constant")
    ramp_end(doc, clip, action)
    wav = doc.export("audio_wav", "rv1-wav")      # the very next call after set_action_end
    mov = doc.export("prores_422", "rv1-prores")
    state["rv1"] = {"doc": doc, "clip": clip, "media": media, "constant": constant,
                    "wav": wav, "mov": mov, "renders": doc.renders()}
    return state["rv1"]


def e1(client, state):
    got = rv1(client, state)
    v = variant("RV1")
    x, rate = read_ffmpeg(got["wav"])
    s = placement(x, rate, v, SHIFT_S if MUTANT == "expect-shift" else 0.0)
    wrong = rs.video_wrong(rs.gray_bars(got["mov"]), v)
    named = [n for n in got["renders"] if NAME.match(n) and NAME.match(n).group(1)
             == str(got["media"])]
    good = (not wrong and s["found"] == s["of"] and s["of"] > 0 and rs.varispeed_pass(s)
            and len(named) == 1)
    check("E1", good, f"{place_text(s)} (varispeed_pass {rs.varispeed_pass(s)}); "
                      f"{len(wrong)} wrong frames (first {wrong[:3]}); cache/ramp-audio "
                      f"{got['renders']}")


def e2(client, state):
    doc, clip, _, action = ramp_doc(client, "rv1-sine", "sine", 1.0, False)
    ramp_end(doc, clip, action)
    wav = doc.export("audio_wav", "rv1-sine-wav")
    doc.close()
    v = variant("RV1")
    x, rate = read_ffmpeg(wav)
    length_s = v["length"] / SEC
    clicks = rsp.click_events(rsp.dense_scan(x, rate, length_s), 0)
    drops = rs.events(rs.dropouts(x, rate, length_s, rsp.period_fn(v)))
    check("E2", not clicks and not drops,
          f"{len(clicks)} click events (first {[c[0] for c in clicks[:5]]}); {len(drops)} "
          f"dropout events (first {drops[:5]})")


def n1(client, state):
    got = rv1(client, state)
    doc = got["doc"]
    undone = doc.call("undo")
    after = doc.export("audio_wav", "rv1-undone")
    before_md5, after_md5 = md5_of(got["constant"], "a"), md5_of(after, "a")
    speed = doc.clip(got["clip"])["actions"][0]["end"].get("speed")
    check("N1", undone["ok"] and speed is None and before_md5 == after_md5,
          f"undo {undone.get('reply', undone.get('error'))!r:.60}; end speed {speed}; "
          f"constant {before_md5} after undo {after_md5}")


def k1(client, state):
    doc, clip, _, action = ramp_doc(client, "rk1", "sine", 1.1, True)
    ramp_end(doc, clip, action)
    wav = doc.export("audio_wav", "rk1-wav")
    doc.close()
    v = variant("RK1")
    x, rate = read_ffmpeg(wav)
    track = rsp.pitch_track(x, rate, v["length"] / SEC)
    inside, outside = [], []
    for t, f in track:
        cents = abs(1200 * math.log2(f / rs.SINE_HZ))
        (inside if RAMP_SPAN_S[0] < t < RAMP_SPAN_S[1] else outside).append(cents)
    mi = statistics.median(inside) if inside else None
    mo = statistics.median(outside) if outside else None
    good = mi is not None and mo is not None and mi <= PITCH_CENTS and mo <= PITCH_CENTS
    check("K1", good, f"inside the ramp: {len(inside)} windows, median |cents| "
                      f"{'—' if mi is None else f'{mi:.2f}'}; outside: {len(outside)} windows, "
                      f"median |cents| {'—' if mo is None else f'{mo:.2f}'}; both against 220 Hz")


def keep_shift_s(variant):
    """The keep-shift mutant's move: 2 × the row's ceiling + 1 ms, in s."""
    return (2 * L_CEILING_MS[variant] + 1) / 1000


def l_row(row, client):
    """L1–L3: a Keep pitch ramp's export placement under its pinned floor
    and ceiling (SR-13's lead, SR-15's accepted limit)."""
    name, base, curve, end = L_ROWS[row]
    doc, clip, _, action = ramp_doc(client, f"{row.lower()}-{name.lower()}", "clicks", base,
                                    True, curve)
    ramp_end(doc, clip, action, end)
    wav = doc.export("audio_wav", f"{row.lower()}-{name.lower()}-wav")
    doc.close()
    v = variant(name)
    x, rate = read_ffmpeg(wav)
    s = placement(x, rate, v, keep_shift_s(name) if MUTANT == "keep-shift" else 0.0)
    worst = s["max_abs_ms"]
    good = (s["of"] > 0 and worst is not None and s["found_share"] >= L_FOUND[name]
            and worst <= L_CEILING_MS[name])
    check(row, good, f"{name}: {s['found']}/{s['of']} clicks (floor {L_FOUND[name]:.2f}), median "
                     + (f"{s['median_ms']:+.3f} ms, max |diff| {worst:.2f} ms" if worst is not None
                        else "—") + f" (ceiling {L_CEILING_MS[name]:.2f} ms)")


def r1(client, state):
    doc, clip, media, action = ramp_doc(client, "rv1-reverse", "clicks", 1.0, False)
    ramp_end(doc, clip, action)
    forward = doc.export("audio_wav", "rv1-forward-wav")
    forward_names = doc.renders()
    doc.must("set_reversed", clip=clip, reversed=True)
    _, late = precision_proof.wait_reverse(doc, media, "rv1-reverse")
    wav = doc.export("audio_wav", "rv1-reverse-wav")
    mov = doc.export("prores_422", "rv1-reverse-prores")
    reverse_names = doc.renders()
    doc.close()
    v = variant("RV1")
    x, rate = read_ffmpeg(wav)
    with mirrored_clicks():
        s = rsp.place_ideal(x, rate, v)
    wrong = mirrored_wrong(rs.gray_bars(mov), v)
    apart = bool(reverse_names) and not set(reverse_names) & set(forward_names)
    differs = md5_of(wav, "a") != md5_of(forward, "a")
    good = (late is None and not wrong and s["found"] == s["of"] and s["of"] > 0
            and rs.varispeed_pass(s) and apart and differs)
    check("R1", good, f"reverse {'ready' if late is None else late}; {place_text(s)} "
                      f"(varispeed_pass {rs.varispeed_pass(s)}); {len(wrong)} wrong frames "
                      f"(first {wrong[:3]}); renders forward {forward_names}, reversed "
                      f"{reverse_names}; audio md5 differs from the forward export's {differs}")


def w1(client, state):
    doc, clip, media, action = ramp_doc(client, "rv1-rewant", "clicks", 1.0, False)
    ramp_end(doc, clip, action)  # the render starts, held HOLD_S
    edited = time.monotonic()
    undone = doc.call("undo")    # no owner wants the running render
    redone = doc.call("redo")    # wanted again, inside the hold
    gap = time.monotonic() - edited

    def landed():
        return [n for n in doc.renders() if NAME.match(n) and NAME.match(n).group(1)
                == str(media)]
    while not landed() and time.monotonic() < edited + W1_BOUND_S:
        time.sleep(0.1)
    names, waited = landed(), time.monotonic() - edited
    s = None
    if names:
        x, rate = read_ffmpeg(doc.export("audio_wav", "rv1-rewant-wav"))
        s = placement(x, rate, variant("RV1"))
    final = doc.renders()
    doc.close()
    good = (undone["ok"] and redone["ok"] and gap < HOLD_S and len(names) == 1
            and s is not None and s["found"] == s["of"] and s["of"] > 0
            and rs.varispeed_pass(s))
    check("W1", good, f"undo {undone['ok']}, redo {redone['ok']} {gap * 1000:.0f} ms after "
                      f"the edit (hold {HOLD_S} s); cache/ramp-audio {final} after "
                      f"{waited:.1f} s (bound {W1_BOUND_S} s)"
                      + (f"; {place_text(s)} (varispeed_pass {rs.varispeed_pass(s)})" if s
                         else "; not landed, no export made"))


def p1_app(client, state):
    """RV1 and the ×1 control, each exported once, saved and closed."""
    doc, clip, _, action = ramp_doc(client, "p1-rv1", "clicks", 1.0, False)
    ramp_end(doc, clip, action)
    rv1_wav = doc.export("audio_wav", "p1-rv1-wav")
    doc.must("save_project")
    doc.close()
    control = Doc(client, "p1-control")
    control.canvas()
    control.fixture_clip("clicks", CONTROL_LENGTH, 1.0, False)
    control_wav = control.export("audio_wav", "p1-control-wav")
    control.must("save_project")
    control.close()
    state["p1"] = {"rv1": (doc.path, rv1_wav), "control": (control.path, control_wav)}


APP_RUNNERS = {"D1": d1, "D2": d2, "D3": d3, "D4": d4, "D5": d5, "X0": x0, "U1": u1, "E1": e1,
               "E2": e2, "N1": n1, "K1": k1, "R1": r1, "W1": w1,
               **{row: (lambda client, state, row=row: l_row(row, client)) for row in L_ROWS},
               "P1": p1_app, "T1": t1, "S1": s1, "V1": v1, "V2": v2, "V3": v3, "C1": c1}


# ---- SR2b: the probe's reads, after the instance stopped -------------------------


def probe():
    """(binary, None) or (None, why): the shader, then the spike probe."""
    shader, why = build_shader(str(rs.PROBE_DIR))
    if shader is None:
        return None, why
    binary, how = rs.build_probe()
    return (binary, None) if binary else (None, how)


def plans(binary, packages):
    """{name: plan text} through the probe's `plan` group; raises on a miss."""
    PROBE_WORK.mkdir(parents=True, exist_ok=True)
    jobs = [{"name": name, "project": str(Path(path) / "project.json"), "fixture": "clicks",
             "reads": ["plan"], "length": CONSTANTS[name][2]} for name, path in packages.items()]
    lines, why = rs.run_group(binary, "plan", jobs, work=PROBE_WORK)
    out = {}
    for name in packages:
        line = lines.get((name, "plan"))
        if not line or not line.get("ok"):
            raise RuntimeError(f"{name}'s plan was not read: {why or line}")
        out[name] = Path(line["path"]).read_text()
    return out



def by_pcm(name, stream):
    """Whether U1 compares `stream` by its decoded samples rather than its
    md5: every audio stream, whose length against the timeline is not stable
    run to run (#337). Plans and video are exact."""
    return stream.endswith("_audio")


def u1_probe(binary, state):
    built = state.get("u1")
    if not BASELINE.exists():
        check("U1", False, f"{BASELINE.relative_to(ROOT)} is missing — run --baseline first")
        return
    base = json.loads(BASELINE.read_text())["projects"]
    if built is None:
        check("U1", False, "the projects were not built")
        return
    text = plans(binary, {n: b["package"] for n, b in built.items()})
    same, detail = True, []
    for name in CONSTANTS:
        plan_ok = text[name] == base[name]["plan"]
        exact = {k: v for k, v in built[name]["md5"].items() if not by_pcm(name, k)}
        md5_ok = all(md5 == base[name]["md5"][stream] for stream, md5 in exact.items())
        pcm_ok, pcm_text = True, []
        for stream in [k for k in built[name]["md5"] if by_pcm(name, k)]:
            kept = base[name].get("pcm", {}).get(stream)
            if kept is None:
                ok, why = False, "no baseline PCM — run --baseline again"
            else:
                ok, why = pcm_compare(pcm_of(built[name]["audio"][stream]),
                                      ((BASELINE.parent / kept["file"]).read_bytes(),
                                       kept["channels"], kept["rate"]), CONSTANTS[name][2])
            pcm_ok = pcm_ok and ok
            pcm_text.append(f"{stream} {why}")
        same = same and plan_ok and md5_ok and pcm_ok
        detail.append(f"{name} plan {'=' if plan_ok else '≠'}, md5 "
                      + ("=" if md5_ok else f"{exact} ≠ {base[name]['md5']}")
                      + (f", pcm {'; '.join(pcm_text)}" if pcm_text else ""))
    check("U1", same, "; ".join(detail) + f" (baseline {json.loads(BASELINE.read_text())['commit']})")


def p1_probe(binary, state):
    got = state.get("p1")
    if got is None:
        check("P1", False, "the packages were not made")
        return
    rv1_v, control_v = variant("RV1"), variant("C-off-x1")
    jobs = [{"name": "RV1", "project": got["rv1"][0], "fixture": "clicks",
             "reads": ["tap", "frames"], "length": rv1_v["length"]},
            {"name": "control", "project": got["control"][0], "fixture": "clicks",
             "reads": ["tap", "frames"], "length": control_v["length"]}]
    PROBE_WORK.mkdir(parents=True, exist_ok=True)
    lines, why = rs.run_group(binary, "playback", jobs, work=PROBE_WORK)
    (PROBE_WORK / "playback-lines.json").write_text(
        json.dumps({f"{n}|{r}": line for (n, r), line in lines.items()}))
    taps = {n: lines.get((n, "tap")) for n in ("RV1", "control")}
    bars = {n: lines.get((n, "frames")) for n in ("RV1", "control")}
    if why or not all(t and t.get("ok") and t.get("chunks") for t in taps.values()) \
            or not all(b and b.get("ok") for b in bars.values()):
        check("P1", False, f"the playback reads failed: {why or [taps, bars]}"[:400])
        return
    control_x, control_rate = read_ffmpeg(got["control"][1])
    control_export = rsp.place_ideal(control_x, control_rate, control_v)
    cx, crate = rs.tap_signal(taps["control"], control_v["length"])
    k0 = int(round(rsp.coarse_ms(cx, crate, control_v) * crate / 1000))
    control_play = rsp.place_corrected(cx, crate, control_v, k0)
    ok_pt1, fine = rsp.pt1(control_export, control_play)
    m1 = None if fine is None else fine + k0 * 1000 / crate
    x, rate = rs.tap_signal(taps["RV1"], rv1_v["length"])
    k, residual = rsp.correction(m1, rate)
    played = rsp.place_corrected(x, rate, rv1_v, k, residual)
    ex, erate = read_ffmpeg(got["rv1"][1])
    exported = rsp.place_ideal(ex, erate, rv1_v)
    agree, agree_detail = rsp.agreement(exported, played)
    wrong = {"RV1": rs.video_wrong(bars["RV1"]["bars"], rv1_v),
             "control": rs.video_wrong(bars["control"]["bars"], control_v)}
    good = (ok_pt1 and m1 is not None and played["found"] == played["of"] and played["of"] > 0
            and rs.varispeed_pass(played) and agree and not wrong["RV1"]
            and not wrong["control"])
    check("P1", good,
          f"pt1 {ok_pt1}, m1 {m1 if m1 is None else f'{m1:+.3f}'} ms (coarse {k0} samples); "
          f"RV1 tap "
          f"{place_text(played)} (varispeed_pass {rs.varispeed_pass(played)}); agreement "
          f"{agree} ({agree_detail}); wrong frames RV1 {len(wrong['RV1'])}, control "
          f"{len(wrong['control'])}")


# ---- SR4: Swift's mappers (spec §11 SR-20) ---------------------------------------
#
# Every oracle here is the one ramp the rows build: base ×1, ONE linear speed
# action over clip time [0, a) ending at ×r, held after. S(t) = t + (r − 1)t²/(2a)
# inside it, then S(a) + r(t − a); S⁻¹ its inverse, closed form.


def s_of(t, a=2 * SEC, r=2):
    """S(t) in source ticks, exact (a Fraction), for clip tick t ≥ 0."""
    t = Fraction(t)
    if t <= a:
        return t + (r - 1) * t * t / (2 * a)
    return Fraction(a * (1 + r), 2) + r * (t - a)


def s_inv(u, a=2 * SEC, r=2):
    """S⁻¹(u) in clip ticks, a float, for source ticks u ≥ 0."""
    u = float(u)
    edge = a * (1 + r) / 2
    if u <= edge:
        return (-1 + math.sqrt(1 + 2 * (r - 1) * u / a)) * a / (r - 1)
    return a + (u - edge) / r


def half_up(x):
    """Round half away from zero, Swift's `.toNearestOrAwayFromZero` and Rust's `round`."""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def placed_at(source, start, source_in, duration):
    """`MediaTranscript.project` on a ramped job: start + round½(S⁻¹(m − in)),
    the offset clamped into [0, D]."""
    reach = s_of(duration)
    offset = s_inv(min(max(source - source_in, 0), reach))
    return start + half_up(min(max(offset, 0), duration))


def worst(pairs):
    """The largest |got − want| over (got, want) pairs; 0 for none."""
    return max((abs(g - w) for g, w in pairs), default=0)


def mapper_probe():
    """(readings, None) or (None, why): `ramp_mapper_probe.swift` copied in as
    `main.swift`, built over this tree's `app/Sources` (`transcript_proof.build`'s
    shape), run once under a MAPPER_WALL s wall."""
    MAPPER_WORK.mkdir(parents=True, exist_ok=True)
    entry = MAPPER_WORK / "main.swift"
    shutil.copyfile(MAPPER_PROBE, entry)
    binary = MAPPER_WORK / "ramp-mapper-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(ROOT / "app/Sources") + [entry],
                          output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    started = time.monotonic()
    try:
        ran = subprocess.run([str(binary)], capture_output=True, text=True,
                             timeout=MAPPER_WALL, cwd=MAPPER_WORK)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {MAPPER_WALL} s"
    (MAPPER_WORK / "stderr.txt").write_text(ran.stderr)
    (MAPPER_WORK / "answer.json").write_text(ran.stdout)
    try:
        answer = json.loads(ran.stdout)
    except ValueError:
        return None, f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"
    if answer.get("error") or answer.get("problems"):
        return None, f"the fixtures: {answer.get('error') or answer.get('problems')}"
    answer["wall"] = time.monotonic() - started
    return answer, None


def f1(got):
    clips, f = got["clips"], got["F1"]
    ramp, const = clips["ramped"], clips["constant"]
    points = f["ramped"]["map"] or []
    times = [0] + list(range(0, 2 * SEC, 600)) + [2 * SEC, ramp["duration"]]
    times = sorted(set(times))
    off = worst((s, ramp["in"] + half_up(s_of(c))) for c, s in points)
    shape = [c for c, _ in points] == times
    want_const = [[0, const["in"]],
                  [const["duration"], const["in"] + half_up(const["duration"] * const["speed"])]]
    good = (f["ramped"]["ramped"] is True and shape and off <= 1 and f["plan_map_equal"] is True
            and f["constant"]["ramped"] is False and f["constant"]["map"] == want_const
            and f["reversed"]["ramped"] is True and f["reversed"]["map"] == points
            and f["text_clip_nil"] is True)
    check("F1", good,
          f"ramped {f['ramped']['ramped']}, {len(points)} points (want {len(times)} at 0, every "
          f"600 to 2 s, 2 s and D; shape {shape}), max |source − in − round(S)| {off} tick(s), "
          f"equal to the plan's ramp.map {f['plan_map_equal']}; constant "
          f"{f['constant']} (want {want_const}); reversed twin's map the forward one's "
          f"{f['reversed']['map'] == points}; unknown id nil {f['text_clip_nil']}")


def f2(got):
    clips, f = got["clips"], got["F2"]
    ramp, rev = clips["ramped"], clips["reversed"]
    fwd = worst((s, ramp["in"] + math.floor(s_of(t - ramp["start"]))) for t, s in f["ramped"])
    back = worst((s, rev["file"] - (rev["in"] + math.floor(s_of(t - rev["start"]))))
                 for t, s in f["reversed"])
    frames = ramp["duration"] // FRAME
    good = (len(f["ramped"]) == frames and len(f["reversed"]) == frames and fwd <= 1
            and back <= 1 and f["constant_equal"] is True and f["nil_equal"] is True
            and f["ramp_nil_equal"] is True)
    check("F2", good,
          f"{len(f['ramped'])} frames (want {frames}): ramped max |off| {fwd} tick(s) against "
          f"in + ⌊S(t − start)⌋, reversed {back} against file − that; the constant map and a "
          f"nil map equal the 3-argument form at every frame {f['constant_equal']}/"
          f"{f['nil_equal']}, a ramped clip with a nil map too {f['ramp_nil_equal']}")


def f3(got):
    clips, f = got["clips"], got["F3"]
    ramp = clips["ramped"]
    start, src, dur = ramp["start"], ramp["in"], ramp["duration"]
    job = f["job"] or {}
    reach = half_up(s_of(dur))
    job_ok = (job.get("start") == start and job.get("duration") == dur
              and job.get("in") == src and abs(job.get("length", 0) - reach) <= 1
              and job.get("ramp") is True and job.get("speed") == 1
              and job.get("clip_start") == start)
    refusal = f"clip {ramp['clip']}: its speed ramps, and no speed map was read for it"
    three_ok = f["three_jobs"] == 0 and f["three_problems"] == [refusal]
    proj = worst((p, placed_at(m, start, src, dur)) for m, p in f.get("project", []))
    trans = worst((p, placed_at(src + t * SEC, start, src, dur))
                  for t, p in f.get("transcriber", []))
    win_ok, win_text = True, []
    for w in f.get("windows", []):
        lo = s_of(w["from"] - start) - 2 * SEC
        hi = s_of(w["to"] - start) + 2 * SEC
        low = math.floor(s_inv(min(max(lo, 0), s_of(dur))))
        high = math.ceil(s_inv(min(max(hi, 0), s_of(dur))))
        sub_start, sub_end = max(start, start + low), min(start + dur, start + high)
        whole = sub_start == start and sub_end == start + dur
        sub_in = src + half_up(s_of(sub_start - start))
        sub_len = (src + half_up(s_of(sub_end - start)) - sub_in if sub_end < start + dur
                   else src + reach - sub_in)
        sub = w["job"]
        one = placed_at(sub["in"] + SEC, start, src, dur)
        ok = (w["same"] is whole and w["map_kept"] is True
              and abs(sub["start"] - sub_start) <= 2
              and abs(sub["start"] + sub["duration"] - sub_end) <= 2
              and abs(sub["in"] - sub_in) <= 2 and abs(sub["length"] - sub_len) <= 2
              and abs(w["one_second"] - one) <= 2
              and abs(w["one_second"] - w["one_second_whole"]) <= 1)
        win_ok = win_ok and ok
        win_text.append(f"[{w['from']}, {w['to']}) → {sub['start']}+{sub['duration']} in "
                        f"{sub['in']} length {sub['length']} (want {sub_start}+"
                        f"{sub_end - sub_start} in {sub_in} length {sub_len}, whole {whole}); "
                        f"1 s in {w['one_second']} (want {one})")
    good = (job_ok and three_ok and f["constant_equal"] is True and proj <= 2 and trans <= 2
            and len(f.get("project", [])) > 0 and len(f.get("windows", [])) == 4 and win_ok)
    check("F3", good,
          f"job {job} (length want {reach}); 3-argument form {f['three_jobs']} jobs, "
          f"{f['three_problems']}; the constant twin's 3- and 4-argument jobs equal "
          f"{f['constant_equal']}; MediaTranscript.project max |off| {proj}, "
          f"Transcriber.project {trans} tick(s) against start + round½(S⁻¹(m − in)); "
          + "; ".join(win_text))


def f4(got):
    clips, f = got["clips"], got["F4"]
    if "error" in f:
        check("F4", False, f["error"])
        return
    ramp = clips["ramped"]
    seg, cseg = f["segment"], f["constant_segment"]
    off = worst((s, seg["in"] + math.floor(s_of(t - seg["start"]))) for t, s in f["ramped"])
    const = all(s == cseg["in"] + (t - cseg["start"]) * cseg["source_duration"]
                // cseg["duration"] for t, s in f["constant"])
    good = (seg["has_map"] is True and seg["start"] == ramp["start"] and seg["in"] == ramp["in"]
            and abs(seg["source_duration"] - half_up(s_of(ramp["duration"]))) <= 1
            and len(f["ramped"]) == ramp["duration"] // FRAME and off <= 1
            and cseg["ramp"] is False and const and len(f["constant"]) > 0)
    check("F4", good,
          f"the ramp audio segment {seg}: sourceTick max |off| {off} tick(s) against "
          f"in + ⌊S(t − start)⌋ over {len(f['ramped'])} frames; the constant segment {cseg} "
          f"reads in + ⌊(t − start) × sd / d⌋ exactly {const}")


def f5(got):
    f = got["F5"]
    times = {k: f.get(k) for k in ("source_seconds", "clip_seconds", "tick_seconds")}
    good = (f.get("made") is True and f.get("points") == 100_000
            and all(v is not None and v < F5_BOUND_S for v in times.values())
            and f.get("breakpoints", 0) > 0 and f.get("breakpoints_wrong") == 0
            and f.get("tick_wrong") == 0 and "tick_error" not in f)
    check("F5", good,
          f"100 000-point map made {f.get('made')} (checked in "
          f"{(f.get('check_seconds') or 0):.3f} s); 100 000 source(atClip:) "
          f"{times['source_seconds']}, 100 000 clip(atSource:) {times['clip_seconds']}, "
          f"10 000 sourceTick {times['tick_seconds']} s (each under {F5_BOUND_S} s); "
          f"{f.get('breakpoints')} breakpoints hit, {f.get('breakpoints_wrong')} inexact; "
          f"sourceTick at breakpoints {f.get('tick_wrong')} wrong "
          f"{f.get('tick_error', '')}; the probe's wall {got.get('wall', 0):.1f} s")


def run_mapper(chosen):
    wanted = [r for r in SR4_PROBE_ROWS if r in chosen]
    if not wanted:
        return
    got, why = mapper_probe()
    for name in wanted:
        if got is None:
            check(name, False, f"the mapper probe: {why}")
            continue
        try:
            {"F1": f1, "F2": f2, "F3": f3, "F4": f4, "F5": f5}[name](got)
        except Exception as error:
            check(name, False, f"the row could not run: {type(error).__name__}: {error}")


def media_clip(doc, path, at, length):
    """`path` imported and added at `at` on the first track, cut to `length`;
    (clip, media row)."""
    media = doc.must("import_media", path=str(path))["media"]
    track = doc.project()["tracks"][0]["id"]
    clip = doc.must("add_clip", track=track, media=media, at=at)["new_clips"][0]
    doc.must("trim_end", clip=clip, to=at + length)
    row = next(m for m in doc.project()["media"] if m["id"] == media)
    return clip, row


def ramp_it(doc, clip, length=2 * SEC):
    """The rows' ramp: an action at clip time 0 for `length`, linear, to ×2."""
    action = doc.action(clip, 0, length)
    doc.must("set_action_end", clip=clip, action=action, patch={"speed": 2})
    return action


def q4(client, state):
    doc = Doc(client, "q4")
    clip, _ = media_clip(doc, SILENCE_MOV, 0, 5 * SEC)
    ramp_it(doc, clip)
    placed = doc.clip(clip)
    answer = None
    deadline = time.monotonic() + 30
    while True:
        answer = doc.must("detect_silence", clips=[clip], mode="level", min_length=120_000)
        if "pending_peaks" not in answer or time.monotonic() > deadline:
            break
        time.sleep(0.5)
    doc.close()
    pad = answer.get("padding", 0)
    want = [[round(placed["start"] + s_inv(a * SEC - placed["source"].get("in", 0))) + pad,
             round(placed["start"] + s_inv(b * SEC - placed["source"].get("in", 0))) - pad]
            for a, b in ((2.0, 3.5), (6.0, 7.0))]
    ranges = answer.get("ranges") or []
    slack = Q4_BUCKET + FRAME
    off = [max(abs(g[0] - w[0]), abs(g[1] - w[1])) for g, w in zip(ranges, want)]
    good = ("pending_peaks" not in answer and len(ranges) == 2 and all(o <= slack for o in off))
    check("Q4", good,
          f"clip {placed['start']}+{placed['duration']} from in {placed['source'].get('in')}; "
          f"ranges {ranges}, want {want} (padding {pad}); edges off {off} (≤ {slack}); "
          f"mode {answer.get('mode')}, pending {answer.get('pending_peaks')}")


def y1(client, state):
    doc = Doc(client, "y1")
    clip, _ = doc.av_clip(2 * SEC)
    ramp_it(doc, clip, SEC)
    doc.must("add_track")
    project = doc.project()
    own = doc.clip(clip)["track"]
    second = next(t["id"] for t in project["tracks"] if t["id"] != own)
    media = project["media"][0]["id"]
    other = doc.must("add_clip", track=second, media=media, at=0)["new_clips"][0]
    doc.must("trim_end", clip=other, to=2 * SEC)
    sentence = f"clip {clip}: {SYNC_RAMPED}"
    answers = {}
    for anchor in (clip, other):
        answers[anchor] = doc.call("sync_audio", clips=[clip, other], anchor=anchor)
    doc.close()
    good = all(not a["ok"] and sentence in a["error"] for a in answers.values())
    check("Y1", good,
          f"ramped clip {clip}, constant clip {other}: "
          + "; ".join(f"anchor {k}: {'refused' if not v['ok'] else 'APPLIED'} "
                      f"{v.get('error', v.get('reply'))!r:.300}" for k, v in answers.items())
          + f"; want …{sentence!r}")


APP_RUNNERS.update({"Q4": q4, "Y1": y1})


# ---- SR5 -------------------------------------------------------------------------


def past_end(sentence_clip, start, duration, length):
    """`action_past_end`'s sentence (core/src/edit_action.rs), written out."""
    return (f"an action of {duration} ticks at {start} would end at {start + duration}, past "
            f"clip {sentence_clip}'s own end at {length} ticks")


def z1(client, state):
    doc = Doc(client, "z1")
    clip, _ = doc.av_clip(3 * SEC)
    action = doc.action(clip, SEC, SEC)
    doc.must("trim_end", clip=clip, to=3 * SEC // 2)
    placed = doc.clip(clip)
    length = placed["duration"]

    def span():
        stored = doc.clip(clip)["actions"][0]
        return stored["start"], stored["duration"], stored["curve"]

    before = span()
    curve = doc.call("set_action", clip=clip, action=action, curve="ease_in")
    after_curve = span()
    longer = doc.call("set_action", clip=clip, action=action, duration=SEC + FRAME)
    want_longer = past_end(clip, SEC, SEC + FRAME, length)
    earlier = doc.call("set_action", clip=clip, action=action, start=SEC - FRAME)
    after_earlier = span()
    later = doc.call("set_action", clip=clip, action=action, start=SEC + FRAME)
    want_later = past_end(clip, SEC + FRAME, SEC, length)
    undone = doc.call("undo")
    after_undo = span()
    doc.close()
    good = (length == 3 * SEC // 2 and before == (SEC, SEC, before[2])
            and curve["ok"] and after_curve == (SEC, SEC, "ease_in")
            and not longer["ok"] and longer["error"].endswith(want_longer)
            and earlier["ok"] and after_earlier == (SEC - FRAME, SEC, "ease_in")
            and not later["ok"] and later["error"].endswith(want_later)
            and undone["ok"] and after_undo == (SEC, SEC, "ease_in"))
    check("Z1", good,
          f"clip {clip} {length} ticks, action {before}; curve "
          f"{'applied' if curve['ok'] else curve.get('error')} → {after_curve}; +1 frame "
          f"{longer.get('error', 'APPLIED')!r} (want …{want_longer!r}); start −1 frame "
          f"{'applied' if earlier['ok'] else earlier.get('error')} → {after_earlier}; start "
          f"+1 frame {later.get('error', 'APPLIED')!r} (want …{want_later!r}); undo → "
          f"{after_undo}")


def z2(client, state):
    doc = Doc(client, "z2")
    clip, _ = doc.av_clip(2 * SEC)
    action = ramp_it(doc, clip)
    doc.must("trim_end", clip=clip, to=SEC)
    placed = doc.clip(clip)
    curve = doc.call("set_action", clip=clip, action=action, curve="ease_out")
    rate = doc.call("set_action_end", clip=clip, action=action, patch={"speed": 2.5})
    after = doc.clip(clip)
    stored = after["actions"][0]
    doc.close()
    good = (placed["duration"] == SEC and placed["actions"][0]["duration"] == 2 * SEC
            and curve["ok"] and rate["ok"] and stored["curve"] == "ease_out"
            and stored["end"].get("speed") == 2.5 and stored["start"] == 0
            and stored["duration"] == 2 * SEC and after["duration"] == SEC)
    check("Z2", good,
          f"clip {clip} {placed['duration']} ticks holding {placed['actions'][0]}; curve "
          f"{'applied' if curve['ok'] else curve.get('error')}; end ×2.5 "
          f"{'applied' if rate['ok'] else rate.get('error')}; now {stored}, duration "
          f"{after['duration']}")


APP_RUNNERS.update({"Z1": z1, "Z2": z2})


def ui_probe():
    """(readings, None) or (None, why): `ramp_ui_probe.swift` copied in as
    `main.swift`, built over this tree's `app/Sources` (`mapper_probe`'s shape),
    run once under a UI_WALL s wall in `work/ramp/ui/`, where it writes its
    package."""
    UI_WORK.mkdir(parents=True, exist_ok=True)
    entry = UI_WORK / "main.swift"
    shutil.copyfile(UI_PROBE, entry)
    binary = UI_WORK / "ramp-ui-probe"
    try:
        swift_build.build(sources=swift_build.app_sources(ROOT / "app/Sources") + [entry],
                          output=binary)
    except swift_build.SwiftBuildFailed as error:
        return None, "swiftc: " + "; ".join([str(error)] + list(error.diagnostics[:8]))
    try:
        ran = subprocess.run([str(binary)], capture_output=True, text=True,
                             timeout=UI_WALL, cwd=UI_WORK)
    except subprocess.TimeoutExpired:
        return None, f"no answer within {UI_WALL} s"
    (UI_WORK / "stderr.txt").write_text(ran.stderr)
    (UI_WORK / "answer.json").write_text(ran.stdout)
    try:
        answer = json.loads(ran.stdout)
    except ValueError:
        return None, f"no answer (exit {ran.returncode}): {ran.stderr[-300:]}"
    if answer.get("error") or answer.get("problems"):
        return None, f"the fixtures: {answer.get('error')} {answer.get('problems', '')}"
    return answer, None


def op(name, **args):
    return {"name": name, "args": args}


def g1(got):
    ids, clips, f = got["ids"], got["clips"], got["G1"]
    one, two = clips["one"]["id"], clips["two"]["id"]
    want_a = [op("set_action_end", clip=one, action=ids["A"], patch={"speed": 3})]
    want_b = [op("set_action_end", clip=one, action=ids["B"], patch={"speed": 3})]
    want_none = [op("set_speed", clip=one, rate=3)]
    want_two = [op("set_speed", clip=one, rate=3), op("set_speed", clip=two, rate=3)]
    keep = f["keep_pitch"]
    keep_ops = keep["ops"]
    keep_ok = (len(keep_ops) == 1 and keep_ops[0]["name"] == "set_speed"
               and keep_ops[0]["args"].get("clip") == one
               and keep_ops[0]["args"].get("rate") == 1
               and isinstance(keep_ops[0]["args"].get("keep_pitch"), bool)
               and keep["writes"] == ["speed"] and keep["mark"] == "notAnimatable")
    fit_ok = f["fit"]["writes"] == ["speed"] and f["fit"]["mark"] == "notAnimatable"
    good = (f["A"] == want_a and f["B"] == want_b and f["none"] == want_none
            and f["two"] == want_two and keep_ok and fit_ok and f["base_rate"] == 1)
    check("G1", good,
          f"A {f['A']} (want {want_a}); B {f['B']}; none {f['none']}; two clips {f['two']}; "
          f"Keep pitch with A selected {keep} (want set_speed at the base ×1, writes speed, "
          f"⊘); Fit to {f['fit']}; base {f['base_rate']}")


def g2(got):
    f = got["G2"]
    near = (lambda a, b: a is not None and abs(a - b) < 1e-9)
    good = (near(f["A"], 2) and near(f["B"], 2) and near(f["none"], 1)
            and near(f["playhead"], 1.5) and near(f["now"], 1.5) and near(f["past"], 3)
            and f["past_selected"] == got["ids"]["past"])
    check("G2", good,
          f"A {f['A']} (want 2, its end); B {f['B']} (want 2, the rate in force at its end); "
          f"none {f['none']} (want the base 1); at the playhead, clip 1 s, {f['playhead']} "
          f"and now {f['now']} (want 1.5); the past-end action {f['past']} (want its end ×3, "
          f"not the ×2 at the clip's end), selected {f['past_selected']}")


def g3(got):
    f = got["G3"]
    good = (f["keys_A"] == ["speed"] and f["keys_zoom_rate"] == ["scale", "speed", "x", "y"]
            and f["keys_zoom"] == ["scale", "x", "y"] and f["zoom"] is True
            and f["zoom_rate"] is False and f["A_zoom"] is False)
    check("G3", good, f"{f}")


def g4(got):
    clips, f, may = got["clips"], got["G4"], got["G4_may"]
    p = clips["P"]["id"]
    by = {t["name"]: t for t in f["trials"]}
    applied = all(by.get(n, {}).get("arm") == "applied" for n in ("P14", "P12", "Q14"))
    want = {"P14": [{"id": p, "speed": 14}], "P12": [], "Q14": []}
    crossings = applied and all(by[n]["crossing"] == w for n, w in want.items())
    may_ok = (may == {"end_speed": True, "end_opacity": False, "set_action": False,
                      "set_speed": True} and all(by[n]["may"] is True for n in want))
    notes = f["note_P14"] == SILENT_NOTE and f["note_R"] is None
    check("G4", applied and crossings and may_ok and notes,
          f"P {clips['P']}, Q {clips['Q']}; trials "
          + "; ".join(f"{n} {t['arm']} → {t['crossing']}" for n, t in by.items())
          + f" (want each applied, then {want}); mayCross {may}; the note on P at ×14 "
          f"{f['note_P14']!r} (want {SILENT_NOTE!r}), on the constant ×2 clip {f['note_R']!r}")


def g5(got):
    ids, clips, f = got["ids"], got["clips"], got["G5"]
    want_clear = [op("set_action_end", clip=clips["one"]["id"], action=ids["A"],
                     patch={"speed": None})]
    good = (f["set_speed"] == ["speed"] and f["rate_A"] == ["speed"]
            and f["keyed_A"] == ["speed"] and f["clear"] == want_clear
            and f["count_A"] == 1 and f["count_B"] == 0
            and f["rate_mark_A"] == "keyed" and f["rate_mark_none"] == "other(1)")
    check("G5", good,
          f"paths(set_speed) {f['set_speed']}, paths(Rate with A) {f['rate_A']}, A keys "
          f"{f['keyed_A']}; clearOps([speed]) {f['clear']} (want {want_clear}); Clip ◆N A "
          f"{f['count_A']} B {f['count_B']}; Rate's mark with A {f['rate_mark_A']}, with none "
          f"{f['rate_mark_none']} (want keyed, other(1))")


def g6(got):
    f = got["G6"]
    ramped, const = f["ramped"], f["constant"]
    want_const = ["1 clip · 00:00:00:15 → 00:00:01:00"]
    good = (f["ramp_line"] == RAMP_LINE and len(ramped) >= 2 and ramped[-1] == RAMP_LINE
            and ramped.count(RAMP_LINE) == 1 and f["trial_A"] == 4 and f["trial_speed"] == 2
            and const == want_const)
    check("G6", good,
          f"ramped readout {ramped} (want its last line {RAMP_LINE!r}); the trial's A end "
          f"{f['trial_A']} at base {f['trial_speed']} (want 4 at 2); the constant ×2 clip at "
          f"×1 {const} (want {want_const})")


def run_ui_probe(chosen):
    wanted = [r for r in SR5_PROBE_ROWS if r in chosen]
    if not wanted:
        return
    got, why = ui_probe()
    for name in wanted:
        if got is None:
            check(name, False, f"the UI probe: {why}")
            continue
        try:
            {"G1": g1, "G2": g2, "G3": g3, "G4": g4, "G5": g5, "G6": g6}[name](got)
        except Exception as error:
            check(name, False, f"the row could not run: {type(error).__name__}: {error}")


def secrets():
    """`transcript_proof.secret_folder()`'s shape: a 0700 folder holding 0600
    `anthropic-key` and `assemblyai-key`, both the dummy."""
    folder = WORK / "secrets"
    shutil.rmtree(folder, ignore_errors=True)
    folder.mkdir(parents=True)
    os.chmod(folder, 0o700)
    for name in ("anthropic-key", "assemblyai-key"):
        descriptor = os.open(folder / name, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, "w") as handle:
            handle.write("proof-key\n")
    return str(folder)


def words_of(answer):
    return [(w.get("text"), w.get("start"), w.get("end")) for w in answer.get("words") or []]


def q1(client, aai, words, state):
    import cloud_captions_proof as cloud
    cloud.scenario(aai, disfluent_words=words)
    doc = Doc(client, "q1")
    state["q1"] = doc
    clip, _ = media_clip(doc, SPEECH_MOV, SEC, 3 * SEC)
    ramp_it(doc, clip)
    doc.must("transcribe", engine="assemblyai", place=False)
    doc.must("save_project")
    placed = doc.clip(clip)
    state["q1_clip"] = (clip, placed)
    start, src, dur = placed["start"], placed["source"].get("in", 0), placed["duration"]
    reach = half_up(s_of(dur))
    want = []
    for w in words:
        m = w["start"] * 600
        if src <= m < src + reach:
            want.append((w["text"], placed_at(m, start, src, dur),
                         placed_at(max(w["start"], w["end"]) * 600, start, src, dur)))
    answer = doc.must("get_transcript", clip=clip)
    got = words_of(answer)
    texts = [g[0] for g in got] == [w[0] for w in want]
    off = worst([(g[1], w[1]) for g, w in zip(got, want)] + [(g[2], w[2]) for g, w in zip(got, want)])
    good = (answer.get("engine") == "assemblyai" and texts and len(got) == len(words)
            and off <= 2 and start == SEC and dur == 3 * SEC and src == 0)
    check("Q1", good,
          f"clip {start}+{dur} in {src}, reads round(S(D)) {reach}; words {got}; want {want}; "
          f"max |off| {off} tick(s)")


def q2(client, aai, words, state):
    import cloud_captions_proof as cloud
    cloud.scenario(aai, disfluent_words=words)
    doc = Doc(client, "q2")
    media = doc.must("import_media", path=str(SPEECH_MOV))["media"]
    track = doc.project()["tracks"][0]["id"]
    clip = doc.must("add_clip", track=track, media=media, at=0)["new_clips"][0]
    doc.must("set_speed", clip=clip, rate=1.5)
    doc.must("transcribe", engine="assemblyai", place=False)
    doc.must("save_project")
    placed = doc.clip(clip)
    want = words_of({"words": cloud.mapped(placed, words)})
    got = words_of(doc.must("get_transcript", clip=clip))
    doc.close()
    check("Q2", bool(want) and got == want,
          f"a ×{placed.get('speed')} clip {placed['start']}+{placed['duration']}: words {got}; "
          f"want cloud.mapped {want}")


def q3(client, aai, words, state):
    import fillers_proof as fp
    doc, got_clip = state.get("q1"), state.get("q1_clip")
    if doc is None or got_clip is None:
        check("Q3", False, "Q1 made no clip")
        return
    clip, placed = got_clip
    start, src, dur = placed["start"], placed["source"].get("in", 0), placed["duration"]
    reach = half_up(s_of(dur))
    fps = doc.project()["canvas"]["fps"]
    frame = SEC * fps[1] // fps[0]
    grids = fp.tr9(words, src, src, reach, 1)
    want, near = [], []
    for _, grid, _ in grids:
        a = start + s_inv(grid[0] - src)
        b = start + s_inv(grid[1] - src)
        edges = (fp.ceil_to(half_up(a), frame), fp.floor_to(half_up(b), frame))
        if edges[1] > edges[0]:
            want.append(list(edges))
            near.append([min(x % frame, frame - x % frame) <= 2 for x in (a, b)])
    answer = doc.must("detect_fillers", clips=[clip])
    doc.close()
    ranges = answer.get("ranges") or []
    ok = len(ranges) == len(want)
    for g, w, n in zip(ranges, want, near):
        for k in range(2):
            ok = ok and (g[k] == w[k] or (n[k] and abs(g[k] - w[k]) == frame))
    fillers = answer.get("fillers") or [{}]
    good = ok and bool(want) and fillers[0].get("words") == ["um,", "Uh", "er"]
    check("Q3", good,
          f"TR-9's grid {[g for _, g, _ in grids]} through S⁻¹ → {want} (an edge within 2 "
          f"ticks of a frame boundary {near}); ranges {ranges}, fillers "
          f"{[f.get('words') for f in answer.get('fillers') or []]}, dropped "
          f"{answer.get('dropped')}")


def run_cloud(binary, chosen):
    """Q0–Q3 on a second owned instance with a dummy AssemblyAI key against the
    fake, under the cloud instruments' lock."""
    wanted = [r for r in SR4_CLOUD_ROWS if r in chosen]
    if not wanted:
        return
    import cloud_captions_probe
    import cloud_captions_proof as cloud
    os.makedirs(cloud.WORK, exist_ok=True)
    if not SPEECH_MOV.exists():
        for name in wanted:
            check(name, False, f"the fixture is missing: {SPEECH_MOV}")
        return
    lock, _, holder = cloud_captions_probe.hold_cloud_lock(1800)
    if lock is None:
        for name in wanted:
            check(name, False, f"not run: the cloud instruments' lock is held by {holder}")
        return
    words = cloud.DISFLUENT_WORDS
    log = WORK / "framejob-cloud.log"
    state = {}
    with contextlib.closing(lock), cloud_captions_probe.Fake("ramp") as aai:
        launched = mcp.launch(str(binary), arguments=["-RCSecretFolder", secrets(),
                                                      "-RCAssemblyAIEndpoint", aai.base],
                              env=bounded.child_env(), log_path=str(log), timeout=CALL_BOUND)
        up = launched.client is not None
        try:
            if up:
                print(f"  cloud instance PID {launched.child.pid} at {launched.socket_path}",
                      flush=True)
            for name in [r for r in wanted if r != "Q0"]:
                if not up:
                    check(name, False, f"the app did not listen at {launched.socket_path}")
                    continue
                try:
                    {"Q1": q1, "Q2": q2, "Q3": q3}[name](launched.client, aai, words, state)
                except Exception as error:
                    check(name, False,
                          f"the row could not run: {type(error).__name__}: {error}")
            if state.get("q1") is not None:
                with contextlib.suppress(Exception):
                    state["q1"].close()
        finally:
            launched.stop()
            mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    if "Q0" in wanted:
        check("Q0", up and found == [], f"listening {up}; complaints {found[:5]}")


# ---- the run ---------------------------------------------------------------------


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def needs(name):
    if (name in SR2A_ROWS or name in SR3A_ROWS or name in SR3B_ROWS or name == "Y1"
            or name in SR5_APP_ROWS):
        return [AV_MOV]
    if name == "Q4":
        return [SILENCE_MOV]
    if name == "X0":
        return []
    return [rs.FIXTURES / f for f in rs.FIXTURE_FILES.values()]


def run_app(binary, chosen, state):
    log = WORK / "framejob.log"
    launched = mcp.launch(str(binary), arguments=["-RCDevRampRenderHold", str(HOLD_S)],
                          env=bounded.child_env(), log_path=str(log), timeout=CALL_BOUND)
    up = launched.client is not None
    try:
        if not up:
            for name in chosen:
                check(name, False, f"the app did not listen at {launched.socket_path}")
        else:
            print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
            for name in [n for n in chosen if n in APP_RUNNERS]:
                missing = [p for p in needs(name) if not p.exists()]
                if missing:
                    check(name, False, f"the fixture is missing: {missing[0]}")
                    continue
                try:
                    APP_RUNNERS[name](launched.client, state)
                except Exception as error:  # an instrument that breaks is a FAIL, not an exit
                    check(name, False, f"the row could not run: {type(error).__name__}: {error}")
                    state.setdefault("broken", set()).add(name)
            for doc in [state.get("d1"), state.get("rv1", {}).get("doc")]:
                try:
                    if doc is not None:
                        doc.close()
                except OSError:  # an instance that died answers nothing; D0 says so
                    pass
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    check("D0", up and found == [], f"listening {up}; complaints {found[:5]}")
    return up


def run_probe(chosen, state):
    wanted = [n for n in ("U1", "P1") if n in chosen and n not in state.get("broken", set())]
    if not wanted:
        return
    binary, why = probe()
    for name in wanted:
        if binary is None:
            check(name, False, f"the probe did not build: {why}")
            continue
        try:
            (u1_probe if name == "U1" else p1_probe)(binary, state)
        except Exception as error:
            check(name, False, f"the probe read could not run: {type(error).__name__}: {error}")


def baseline(binary):
    """`--baseline`: X0, then CX1, CX2 and CK05 built and read into
    `baseline.json`; 0 when it is written."""
    state = {}
    x0(None, state)
    if not state["fixtures"]:
        return 1
    log = WORK / "framejob.log"
    launched = mcp.launch(str(binary), arguments=["-RCDevRampRenderHold", str(HOLD_S)],
                          env=bounded.child_env(), log_path=str(log), timeout=CALL_BOUND)
    if launched.client is None:
        launched.stop()
        print(f"BL fail — the app did not listen at {launched.socket_path}")
        return 1
    try:
        print(f"  instance PID {launched.child.pid} at {launched.socket_path}", flush=True)
        built = build_constants(launched.client)
    finally:
        launched.stop()
        mcp.remove_scratch(launched.socket_path)
    found = complaints(log)
    probe_binary, why = probe()
    if probe_binary is None or found:
        print(f"BL fail — probe {why}; complaints {found[:5]}")
        return 1
    text = plans(probe_binary, {n: b["package"] for n, b in built.items()})
    tree = subprocess.run(["git", "-C", str(Path(binary).parent), "rev-parse", "--show-toplevel"],
                          capture_output=True, text=True).stdout.strip() or str(ROOT)
    commit = subprocess.run(["git", "-C", tree, "rev-parse", "HEAD"], capture_output=True,
                            text=True).stdout.strip()
    dirty = subprocess.run(["git", "-C", tree, "status", "--porcelain", "--", "app", "core",
                            "graphic", "agent"], capture_output=True, text=True).stdout.strip()
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    pcm = {}
    for name in CONSTANTS:
        for stream, path in built[name]["audio"].items():
            if by_pcm(name, stream):
                data, channels, rate = pcm_of(path)
                kept = f"{name}-{stream}.f32"
                (BASELINE.parent / kept).write_bytes(data)
                pcm.setdefault(name, {})[stream] = {
                    "file": kept, "channels": channels, "rate": rate,
                    "frames": len(data) // (4 * channels)}
    record = {"commit": commit, "tree": tree, "app_inputs_dirty": bool(dirty),
              "app": str(binary),
              "made": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
              "projects": {n: {"rate": CONSTANTS[n][0], "keep_pitch": CONSTANTS[n][1],
                               "length": CONSTANTS[n][2], "plan": text[n],
                               "md5": built[n]["md5"],
                               **({"pcm": pcm[n]} if n in pcm else {})} for n in CONSTANTS}}
    BASELINE.write_text(json.dumps(record, indent=1, sort_keys=True))
    for name in CONSTANTS:
        print(f"BL {name}: plan {len(text[name])} chars, {built[name]['md5']}"
              + (f", pcm {pcm[name]}" if name in pcm else ""))
    print(f"BL pass — {BASELINE.relative_to(ROOT)} at {commit} (app inputs dirty {bool(dirty)})")
    return 0


def main():
    global MUTANT
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--app", type=Path, default=None)
    parser.add_argument("--only", default="")
    parser.add_argument("--baseline", action="store_true")
    parser.add_argument("--mutant", choices=MUTANTS, default=None)
    args = parser.parse_args()
    MUTANT = args.mutant
    binary = args.app or proof_app.binary()
    tree_copy.remove_tree(str(WORK))
    WORK.mkdir(parents=True)
    started = time.monotonic()
    if not Path(binary).exists():
        print(f"the app is not built: {binary}")
        return 1
    precision_proof.WORK = WORK
    if args.baseline:
        print(f"speed ramps SR2b — the constant clips' baseline — {binary}", flush=True)
        return baseline(binary)
    chosen = [r for r in ROWS[1:] if not args.only or r in args.only.split(",")]
    if any(r in SR2B_ROWS[1:] for r in chosen) and "X0" not in chosen:
        chosen.insert(0, "X0")
    if any(r in SR4_CLOUD_ROWS[1:] for r in chosen) and "Q0" not in chosen:
        chosen.insert(chosen.index(next(r for r in chosen if r in SR4_CLOUD_ROWS)), "Q0")
    if "Q3" in chosen and "Q1" not in chosen:
        chosen.insert(chosen.index("Q3"), "Q1")
    print(f"speed ramps SR2a/SR2b/SR3a/SR3b/SR4/SR5 — set_action_end's speed, the rendered "
          f"ramp audio, edits on a ramped clip, its rate scaled and carried, Swift's mappers, "
          f"and the UI — "
          f"{binary}" + (f" — mutant {MUTANT}" if MUTANT else ""), flush=True)
    state = {}
    run_app(binary, chosen, state)
    run_probe(chosen, state)
    run_mapper(chosen)
    run_ui_probe(chosen)
    run_cloud(binary, chosen)
    scored = ["D0"] + chosen
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
