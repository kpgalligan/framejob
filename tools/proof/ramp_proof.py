#!/usr/bin/env python3
"""Speed ramps SR2a, SR2b and SR1d (spec §11 SR-10, SR-2, SR-6, SR-12, SR-13,
SR-15), against the built app: an action's `end.speed` through
`set_action_end` over MCP — the door, the slot rule's R1 sentence, the ×12
answer, undo and redo (SR2a) — a ramped clip's rendered audio in the export
and in playback (SR2b, #111), and Keep pitch inside a ramp kept and placed by
SR-13's led rate-mode arm (SR1d: K1, L1–L3).

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
scored. No row performs a menu item. SR2a's fixture is
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
    SR2b — at `de1e51e` CK05's two exports gave two md5s (Apple's
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
row run passed. `--only D1,E1` runs those rows (D0 always).
"""

import argparse
import contextlib
import json
import math
import os
import re
import statistics
import subprocess
import sys
import time
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
import tree_copy  # noqa: E402
from export_offset_proof import read_ffmpeg  # noqa: E402
from media_less_playback_probe import build_shader  # noqa: E402

WORK = ROOT / "tools/proof/work/ramp"
EXPORTS = WORK / "exports"
PROBE_WORK = WORK / "probe"
BASELINE = ROOT / "tools/proof/work/ramp-baseline/baseline.json"
AV_MOV = ROOT / "tools/proof/media/AV.mov"
SEC = 600_000
FRAME = 20_000
CALL_BOUND = 600
HOLD_S = 2
W1_BOUND_S = 60
SR2A_ROWS = ["D1", "D2", "D3", "D4", "D5"]
SR2B_ROWS = ["X0", "U1", "E1", "E2", "N1", "K1", "L1", "L2", "L3", "R1", "W1", "P1"]
ROWS = ["D0"] + SR2A_ROWS + SR2B_ROWS
# name: (rate, keep pitch or None for the default, length ticks)
CONSTANTS = {"CX1": (1.0, None, 4 * SEC), "CX2": (2.0, False, 4 * SEC),
             "CK05": (0.5, True, 4 * SEC)}
CONTROL_LENGTH = 6 * SEC
RAMP_SPAN_S = (1.0, 3.0)
PITCH_CENTS = 25.0
SHIFT_S = 0.002
MUTANTS = ["expect-shift", "keep-shift"]
# SR1d's measured run (designs/speed-ramps.md's SR1d record, results.json at
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
               "P1": p1_app}


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


# ---- the run ---------------------------------------------------------------------


def complaints(log):
    try:
        with open(log, errors="replace") as handle:
            return [line.rstrip() for line in handle if "Frame Job: " in line]
    except OSError as error:
        return [f"the log could not be read: {error}"]


def needs(name):
    if name in SR2A_ROWS:
        return [AV_MOV]
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
            for name in chosen:
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
    print(f"speed ramps SR2a/SR2b — set_action_end's speed and the rendered ramp audio — "
          f"{binary}" + (f" — mutant {MUTANT}" if MUTANT else ""), flush=True)
    state = {}
    run_app(binary, chosen, state)
    run_probe(chosen, state)
    scored = ["D0"] + chosen
    passed = sum(1 for name in scored if rows.get(name))
    print(f"{passed}/{len(scored)} in {time.monotonic() - started:.0f} s")
    return 0 if passed == len(scored) else 1


if __name__ == "__main__":
    sys.exit(main())
