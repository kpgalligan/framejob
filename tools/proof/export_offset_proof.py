#!/usr/bin/env python3
"""Issue #298 — where every export path places a sample relative to the
timeline, measured against sample-exact click fixtures. Phase 1 measured the
offsets and the stage (file, AVFoundation decode/SRC, composition insert,
mix, time-pitch, writer) where each enters; phase 2 removed them at their
causes (spec §11 SY-23..SY-27) and this is now the standing pin: every E, R
and X row is scored against SY-27's tolerance. Clean-up batch 3 (SY-35..SY-38)
added the late head's separating fixture (#307), an MP3 read past its own
LAME/Xing encoder delay (#306) and keep pitch outside the band on a real
recording (#299).

    python3 tools/proof/export_offset_proof.py [<dir>/agent.sock] [--only ID,ID,...]
    python3 tools/proof/export_offset_proof.py --mutants [--mutant NAME,NAME,...]

Z0, Z2, L1–L12 and X1–X15 need no app; every other row needs the running instance's
socket (`proof_app.py launch`; `--app release` for the recorded run) and the
script exits 2 when one is asked for without it. Rows print
`<ID> ok|measured|FAIL — <detail>`, then the E and L tables, then `scores: n/m`; exit
0 iff every requested row passed. Everything is under
`tools/proof/work/export-offset/` (fixtures in `fixtures/`, names carrying
`-v1`, made once). Every project is closed with `discard: true`; no menu item
is performed. ffmpeg and ffprobe are proof-time dependencies (as
`audio_sync_proof.py`'s S18); a WAV is read by Python's `wave` alone, the
ground truth for every WAV export.

Fixtures, 10 s each, a click at every frame F of CLICK_FRAMES (15, 39, …, 279
at 30 fps — multiples of 3, so each frame start is a whole sample at 16 and
48 kHz): a Hann pulse 1 ms wide, amplitude 0.5, centred on F/30 s,
v(n) = 0.25·(1 + cos(π(n − c)/h)) for |n − c| < h, h = rate/2000 samples.
  clicks16 / clicks48     mono s16 WAV at 16 / 48 kHz (`write_clicks_wav`)
  clicks44                the same at 44.1 kHz
  clicks44-aac / -mp3     clicks44 through ffmpeg: `-c:a aac -b:a 192k` (.m4a),
                          `-c:a libmp3lame -b:a 192k` (.mp3)
  clicks48-mp3            clicks48 through `-c:a libmp3lame -b:a 192k`
  clicks44s-mp3           clicks44 through `-ac 2 -c:a libmp3lame -b:a 192k`
                          (stereo: Core Audio accepts ffmpeg's tag, a packet table)
  clicks44-mp3-noxing     clicks44-mp3's recipe with `-write_xing 0` (no tag)
  clicks24-mp3            clicks44 through `-ar 24000 -c:a libmp3lame -b:a 64k`
                          (MPEG-2)
  clicks44-mp3-itunsmpb   noxing's frames behind an ID3v2.3 tag of one COMM
                          `iTunSMPB` frame (576 priming, 792 remainder, 441,000
                          valid; `write_itunsmpb`, Python)
  clicks44-late           an 11 s grey 320×180 H.264 movie from 0 with clicks44
                          as pcm_s16le from 0.5 s (`-itsoffset 0.5`): its audio
                          track starts 0.5 s in (SOURCE_OFFSET), Z0 checks
                          ffprobe's start_time 0.500 ± 0.001
  clicks16-late5          the same recipe over clicks16 from 5 s (`-itsoffset 5`,
                          a 16 s movie; #307, SY-35)
  clicks48-lead37         clicks48 with every click 37 samples later (Z1)
  cam-pcm48 / cam-aac48   `export_offset_writer.swift`: AVFoundation's H.264
                          movie, white on the click frames, 48 kHz mono LPCM
                          s16 / AAC 128 kbps
  cam-ff16                `audio_sync_proof.py`'s CAMERA recipe over clicks16
                          (lavfi gray, libx264 30 fps, pcm_s16le, -shortest)

The 48 kHz copies (SY-23) outlive a code change, so `clear_rate_copies()`
removes `FrameJob/AudioRate48` under `$TMPDIR` and under `getconf
DARWIN_USER_TEMP_DIR` before the first probe run or app row, and `--mutants`
before its `before` and before each mutant's X run.

`locate` finds each click near its expected time: the sample of largest |x|
within ±60 ms, then the normalised correlation with the click template at
the read's rate over ±1 ms of it, refined parabolically; a click whose best
r is under 0.5 is not found. Expected timeline time of a click at source
time c: `start + (c + SOURCE_OFFSET − in)/speed` from `get_project`'s clip; in
an `in_out` export, minus the in point.

SY-27's pin (`pinned`): |median| ≤ 1.0 ms and spread ≤ 0.5 ms with ≥ 10 of
12 found, for ×1, varispeed, in-band keep pitch, LPCM/AAC, gain, pan, noise
reduction and range rows; |median| ≤ 5.0 ms for keep pitch outside the band
(KEEP_ROWS: E9, E11, E12, E29); the video presets' flashes on exactly their
timeline frames with every |click − flash| ≤ 1.0 ms.

Rows:
  Z0  each fixture read back (`read_wav` / `read_ffmpeg`) finds all 12
      clicks within 0.05 ms of the written times (0.5 ms for cam-aac48 and
      clicks44-aac); the writer's movies flash on exactly CLICK_FRAMES (pts
      F/30 ± 1 ms); cam-ff16 is flat grey and checked for sound only;
      clicks44-late's and clicks16-late5's audio start_time is 0.500 / 5.000
      ± 0.001 s (else the fixture is a failure); every MP3 but noxing and
      itunsmpb is read by ffmpeg (0.5 ms); `afinfo` prints no `valid frames`
      line for clicks44-mp3, clicks48-mp3, clicks24-mp3 and noxing, and
      `audio 441000 valid frames + 576 priming + 792 remainder = 442368` for
      clicks44s-mp3 and itunsmpb — a miss names the fixture: "not the class
      the rows assume"
  Z1  E4's project with clicks48-lead37: its median − E4's = 37/48 000 s
      ± 0.05 ms
  Z2  `locate` on synthetic 48 kHz trains with clicks at +0.0, +0.3, +0.7
      sample finds each within 0.01 ms (no file)
  Z3  E2's WAV by `locate` and by S18's method (`wav_samples`, `envelope`,
      `window_lag` against the fixture's envelope placed at the clip's start,
      over the file's click span); `window_lag` takes a whole-ms offset, so
      the start is rounded and the rounding taken back out of the lag
  R1  `audio_sync_proof.fixtures()`'s RECORDER at frame 206, ×1, `audio_wav`,
      S18's `window_lag` on [12 s, 22 s) (#298 reported +25.71 ms); ok with
      r ≥ 0.8 and |lag| ≤ 1.0 ms
  R2  the same at `set_speed {rate: 0.99999, keep_pitch: false}` (#298:
      −2.81 ms), the same pin
  R3–R7  the same clip at ×0.99999 keep (R3, #299's in-band case), ×0.9 and
      ×1.1 keep (R4, R5), ×0.9 and ×1.1 off (R6, R7, the controls), each by
      `stretched_lag` against the recorder's own envelope stretched by the
      speed on its media windows [12 s, 22 s) and [128 s, 138 s); R6 and R7
      pinned (both |lag| ≤ 1.0 ms, r ≥ 0.8). R3, R4 and R5 (reach ±200 ms)
      are MEASURED rows (#299 open, SY-37): printed `measured` when both
      windows are found (r ≥ 0.5, inside the reach), never pinned to a lag;
      their detail names SY-37's class (a defect when a window has r < 0.8,
      |lag| > 5.0 ms or a lag at the edge)
  E1–E34  one project each (`E_ROWS`), exported and located; ok when the
      export completed, ≥ 10 of 12 clicks were found (E23: all 10 of its
      in-range clicks) and SY-27's pin holds (E30, E33: the MP3s, read past
      their encoder delay, SY-36; E32 the late head, SY-35). E34 (×1.1 keep
      pitch) is a MEASURED row: ≥ 10 found, its median printed, not pinned. The detail
      prints the median and spread of found − expected, the count, the
      least r and the pin
  L1–L11  `export_offset_probe.swift`'s stage reads (its header lists them),
      each located; ok when every read completed and found ≥ 10 of 12. A
      probe that does not build or answer FAILS every L and X row asked.
      L10 is also the trim's gate: every `trimmed` read within 0.1 ms of
      ffmpeg's read of the same file, the tabled MP3s' native reads within
      0.1 ms of 0, noxing's 576/44.1 ms late ± 0.1
  L12  `MP3Gapless`'s tag reader and trim, checked inside the probe (no read)
  X1–X15  the probe's in-process exports and the sync cache (its header lists
      them), each located and pinned: ≥ 10 found, |median| ≤ 1.0 ms, spread
      ≤ 0.5 ms; X14 (no tag) instead 12 found and |X14 − X2 − 576/44.1| ≤
      0.1 ms
Under the L table, per fixture and speed, the first stage of
asset48 → comp → mix → export whose median moves by more than 0.1 ms from
the stage before it, and native against asset48 (the decoder's SRC).

`--mutants` (`audio_sync_proof.py`'s pattern): each copies `app/Sources`
under `work/export-offset/mutants/<name>/`, applies its edit (its `before`
asserted to occur exactly once), rebuilds the probe (900 s wall) and runs its
X group (240 s wall); killed when every named row fails. `before` — the
unmutated tree — runs exactly once first and must pass every X row; a copy
that does not build or answer is a failed control, never a kill. M7 and M8
are the core's (`core/tests/pitch_band.rs`), run by hand. `--mutant` runs
`before` and only the named mutants. Exit 0 when every mutant was killed.
"""

import argparse
import array
import json
import math
import os
import re
import shutil
import statistics
import sys
import time
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HERE = ROOT / "tools/proof"
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE / "graphics_spike"))
import bounded  # noqa: E402
import swift_build  # noqa: E402
from audio_sync_proof import envelope, fixtures as sync_fixtures, wav_samples, window_lag  # noqa: E402
from mcp import MCP, ToolError  # noqa: E402

WORK = HERE / "work/export-offset"
FIXTURES = WORK / "fixtures"
EXPORTS = WORK / "exports"
PROBE_DIR = WORK / "probe"
PROBE_RUNS = WORK / "probe-runs"
PROBE_SWIFT = HERE / "export_offset_probe.swift"
WRITER_SWIFT = HERE / "export_offset_writer.swift"
WRITER = WORK / "writer" / "export_offset_writer"
BLANK = ROOT / "app/Resources/Blank.mp4"
BUILD_WALL = 900
RUN_WALL = 240

CLICK_FRAMES = [15 + 24 * k for k in range(12)]
CLICKS = [f / 30 for f in CLICK_FRAMES]  # source seconds
SEC = 600_000
F206 = 206 * 20_000
LENGTH_S = 10
LEAD = 37
TARGET_MS = 1.0
TARGET_SPREAD_MS = 0.5
KEEP_TARGET_MS = 5.0
NR_DELAY_MS = 512 / 48_000 * 1000
SOURCE_OFFSET = {"clicks44-late": 0.5, "clicks16-late5": 5.0}  # s: where its audio track starts
FIXTURE_FILES = {
    "clicks16": "clicks16-v1.wav", "clicks48": "clicks48-v1.wav",
    "clicks48-lead37": "clicks48-lead37-v1.wav", "clicks44": "clicks44-v1.wav",
    "clicks44-aac": "clicks44-aac-v1.m4a", "clicks44-mp3": "clicks44-mp3-v1.mp3",
    "clicks44-late": "clicks44-late-v1.mov", "cam-pcm48": "cam-pcm48-v1.mov",
    "cam-aac48": "cam-aac48-v1.mov", "cam-ff16": "cam-ff16-v1.mov",
    "clicks48-mp3": "clicks48-mp3-v1.mp3", "clicks16-late5": "clicks16-late5-v1.mov",
    "clicks44s-mp3": "clicks44s-mp3-v1.mp3", "clicks44-mp3-noxing": "clicks44-mp3-noxing-v1.mp3",
    "clicks44-mp3-itunsmpb": "clicks44-mp3-itunsmpb-v1.mp3", "clicks24-mp3": "clicks24-mp3-v1.mp3",
}
# The fixtures whose tag Core Audio ignores (no packet table: trimmed by
# `MP3Gapless`) and those it reads as a packet table (left alone).
UNTABLED_MP3 = ["clicks44-mp3", "clicks48-mp3", "clicks24-mp3", "clicks44-mp3-noxing"]
TABLED_MP3 = ["clicks44s-mp3", "clicks44-mp3-itunsmpb"]
TABLE_LINE = "audio 441000 valid frames + 576 priming + 792 remainder = 442368"
NOXING_LATE_MS = 576 / 44.1  # the encoder delay no tag names, left in
FLASH_SHARE = (320 * 180) / (640 * 360)  # the movie's share of the canvas

Z_ROWS = ["Z0", "Z1", "Z2", "Z3"]
R_ROWS = [f"R{n}" for n in range(1, 8)]
# row: (speed, keep_pitch, reach ms, pinned) — R1 ×1, R2 #298's varispeed, R3–R7 #299 (SY-37).
R_EDITS = {
    "R1": (None, None, 40, True), "R2": (0.99999, False, 40, True),
    "R3": (0.99999, True, 200, False), "R4": (0.9, True, 200, False),
    "R5": (1.1, True, 200, False), "R6": (0.9, False, 40, True), "R7": (1.1, False, 40, True),
}
R_WINDOWS = [(12_000, 22_000), (128_000, 138_000)]  # ms of the recorder (media), R3–R7
DEFECT_MS = 5.0  # SY-37: outside the band, a window past this is a defect
L_ROWS = [f"L{n}" for n in range(1, 13)]
X_ROWS = [f"X{n}" for n in range(1, 16)]
NO_READ_ROWS = {"L12"}  # checked inside the probe; no manifest read

# row: (fixture, start ticks, edit, preset). An edit: None (×1),
# ("speed", rate, keep_pitch), ("loudness", lufs), ("pan", value), ("nr", value),
# ("range", start, end).
E_ROWS = {
    "E1": ("clicks16", 0, None, "audio_wav"),
    "E2": ("clicks16", F206, None, "audio_wav"),
    "E3": ("clicks16", 10 * SEC, None, "audio_wav"),
    "E4": ("clicks48", F206, None, "audio_wav"),
    "E5": ("clicks16", F206, ("speed", 0.99999, False), "audio_wav"),
    "E6": ("clicks48", F206, ("speed", 0.99999, False), "audio_wav"),
    "E7": ("clicks16", F206, ("speed", 0.5, False), "audio_wav"),
    "E8": ("clicks48", F206, ("speed", 0.5, False), "audio_wav"),
    "E9": ("clicks48", F206, ("speed", 0.5, True), "audio_wav"),
    "E10": ("clicks16", F206, ("speed", 0.99999, True), "audio_wav"),
    "E11": ("clicks48", F206, ("speed", 2, True), "audio_wav"),
    "E12": ("clicks16", F206, ("speed", 0.5, True), "audio_wav"),
    "E13": ("cam-pcm48", 10 * SEC, None, "audio_wav"),
    "E14": ("cam-aac48", 10 * SEC, None, "audio_wav"),
    "E15": ("cam-ff16", 10 * SEC, None, "audio_wav"),
    "E16": ("cam-pcm48", 10 * SEC, None, "prores_422"),
    "E17": ("cam-aac48", 10 * SEC, None, "prores_422"),
    "E18": ("cam-pcm48", 10 * SEC, None, "h264"),
    "E19": ("cam-aac48", 10 * SEC, None, "h264"),
    "E20": ("clicks48", F206, ("loudness", -16), "audio_wav"),
    "E21": ("clicks48", F206, ("pan", -0.5), "audio_wav"),
    "E22": ("clicks48", F206, ("nr", 0.5), "audio_wav"),
    "E23": ("clicks48", F206, ("range", 5 * SEC, 15 * SEC), "audio_wav"),
    "E24": ("clicks44", F206, None, "audio_wav"),
    "E25": ("clicks16", 60 * SEC, None, "audio_wav"),
    "E26": ("clicks44-aac", F206, None, "audio_wav"),
    "E27": ("clicks48", 0, ("nr", 0.5), "audio_wav"),
    "E28": ("clicks48", F206, ("speed", 0.25, False), "audio_wav"),
    "E29": ("clicks48", F206, ("speed", 0.9, True), "audio_wav"),
    "E30": ("clicks44-mp3", F206, None, "audio_wav"),
    "E31": ("clicks44-late", F206, None, "audio_wav"),
    "E32": ("clicks16-late5", F206, None, "audio_wav"),
    "E33": ("clicks48-mp3", F206, None, "audio_wav"),
    "E34": ("clicks48", F206, ("speed", 1.1, True), "audio_wav"),
}
E_IDS = list(E_ROWS)
KEEP_ROWS = {"E9", "E11", "E12", "E29"}
# #299 (SY-37, ruling 3): keep pitch's time-pitch algorithms move real sound,
# so these rows run every pass and print their readings, scored on the
# instrument only (the export decoded, the clicks or windows found).
MEASURED_ROWS = {"R3", "R4", "R5", "E34"}
VIDEO_ROWS = {"E16", "E17", "E18", "E19"}
EXTENSIONS = {"audio_wav": "wav", "prores_422": "mov", "h264": "mp4"}
ALL_ROWS = Z_ROWS + R_ROWS + E_IDS + L_ROWS + X_ROWS
NO_APP = {"Z0", "Z2"} | set(L_ROWS) | set(X_ROWS)

# name: (the X rows it must fail, file, before, after)
MUTANTS = {
    "M1-no-copy": (["X1", "X2"], "AudioRateCopy.swift",
                   "signature.sampleRate != Double(sampleRate)", "false"),
    "M2-no-varispeed-lead": (["X3"], "CompositionBuilder+AudioPlacement.swift",
                             "static let varispeedSourceLead: Ticks = 575",
                             "static let varispeedSourceLead: Ticks = 0"),
    "M3-noise-lead-everywhere": (["X7"], "CompositionBuilder+AudioPlacement.swift",
                                 "trackLead: usesNoiseReduction ? noiseReductionLead : 0,",
                                 "trackLead: noiseReductionLead,"),
    "M4-no-noise-lead": (["X4"], "CompositionBuilder+AudioPlacement.swift",
                         "Ticks(AudioNoiseReductionStage.window) * ReelTime.perSecond / 48_000",
                         "0"),
    "M5-no-head-cut": (["X5"], "CompositionBuilder+AudioPlacement.swift",
                       "let cut = max(0, -at0, sourceCut)", "let cut = max(0, sourceCut)"),
    "M6-source-clamp": (["X3"], "CompositionBuilder+AudioPlacement.swift",
                        "let in0 = sourceIn - lead", "let in0 = max(0, sourceIn - lead)"),
    "M9-no-gap-padding": (["X8"], "AudioRateCopy.swift",
                          "if start - end > 1 {", "if false && start - end > 1 {"),
    "M10-no-head-range": (["X9"], "AudioRateCopy.swift",
                          "if head > .zero {", "if false && head > .zero {"),
    "M11-no-mp3-copy": (["X11"], "AudioRateCopy.swift",
                        "signature.sampleRate != Double(sampleRate) || trim > .zero",
                        "signature.sampleRate != Double(sampleRate)"),
    "M12-no-copy-trim": (["X10", "X11", "X15"], "AudioRateCopy.swift",
                         "if trim > .zero {", "if false && trim > .zero {"),
    "M13-no-sync-trim": (["X12"], "MediaImporter+SyncFeatures.swift",
                         "if trim > .zero {", "if false && trim > .zero {"),
    "M14-delay-field": (["X10", "X11"], "MP3Gapless.swift",
                        "let delay = Int(packed >> 12)", "let delay = Int(packed & 0xFFF)"),
    "M15-no-table-guard": (["X13"], "MP3Gapless.swift",
                           "guard hasPacketTable(url) == false else { return .zero }",
                           "guard hasPacketTable(url) != nil else { return .zero }"),
}

results = {}
e_table = []
l_table = []


def score(row, ok, detail):
    """A MEASURED_ROWS row prints `measured` when its instrument held (it
    counts toward the score; its reading is never pinned)."""
    results[row] = (bool(ok), detail)
    word = ("measured" if row in MEASURED_ROWS else "ok") if ok else "FAIL"
    print(f"{row} {word} — {detail}", flush=True)


class FixtureError(RuntimeError):
    pass


# ---- children under Rule H -----------------------------------------------------


def run(argv, seconds=RUN_WALL):
    """`bounded.run`, raising on expiry or a non-zero exit."""
    ran = bounded.run([str(a) for a in argv], seconds)
    if ran["expired"]:
        raise FixtureError(f"{Path(str(argv[0])).name} ran past {seconds} s and was killed")
    if ran["rc"] != 0:
        raise FixtureError(f"{Path(str(argv[0])).name} exited {ran['rc']}: "
                           f"{(ran['stderr'] or ran['stdout']).strip()[-300:]}")
    return ran


# ---- fixtures ------------------------------------------------------------------


def click_value(d, h):
    return 0.25 * (1 + math.cos(math.pi * d / h)) if abs(d) < h else 0.0


def write_clicks_wav(path: Path, rate: int, lead: int = 0) -> None:
    """Mono s16 via `wave`: 10 s, a click centred at rate·F/30 + lead samples."""
    total = rate * LENGTH_S
    data = [0.0] * total
    h = rate / 2000
    reach = math.ceil(h)
    for f in CLICK_FRAMES:
        c = rate * f // 30 + lead
        for n in range(max(0, c - reach), min(total, c + reach + 1)):
            data[n] += click_value(n - c, h)
    pcm = array.array("h", (max(-32767, min(32767, int(round(v * 32767)))) for v in data))
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(pcm.tobytes())


def fixture_path(name):
    return FIXTURES / FIXTURE_FILES[name]


def build_writer():
    try:
        swift_build.build(sources=[WRITER_SWIFT], output=WRITER, timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        raise FixtureError("export_offset_writer did not build: "
                           + "; ".join(error.diagnostics[:4]))
    return WRITER


def make_fixtures():
    """{name: path}, each made once (a failed make leaves no file)."""
    FIXTURES.mkdir(parents=True, exist_ok=True)
    made = {}
    for name, rate, lead in [("clicks16", 16_000, 0), ("clicks48", 48_000, 0),
                             ("clicks48-lead37", 48_000, LEAD), ("clicks44", 44_100, 0)]:
        path = fixture_path(name)
        if not path.exists():
            write_clicks_wav(path, rate, lead)
        made[name] = path
    frames = ",".join(str(f) for f in CLICK_FRAMES)
    for name, kind in [("cam-pcm48", "pcm"), ("cam-aac48", "aac")]:
        path = fixture_path(name)
        if not path.exists():
            writer = build_writer()
            try:
                run([writer, path, kind, frames])
            except FixtureError:
                path.unlink(missing_ok=True)
                raise
        made[name] = path
    path = fixture_path("cam-ff16")
    if not path.exists():
        try:
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                 f"color=c=gray:s=320x180:r=30:d={LENGTH_S}", "-i", made["clicks16"],
                 "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", "-shortest",
                 path])
        except FixtureError:
            path.unlink(missing_ok=True)
            raise
    made["cam-ff16"] = path
    lame = ["-c:a", "libmp3lame", "-b:a", "192k"]
    for name, base, codec in [("clicks44-aac", "clicks44", ["-c:a", "aac", "-b:a", "192k"]),
                              ("clicks44-mp3", "clicks44", lame),
                              ("clicks48-mp3", "clicks48", lame),
                              ("clicks44s-mp3", "clicks44", ["-ac", "2", *lame]),
                              ("clicks44-mp3-noxing", "clicks44", [*lame, "-write_xing", "0"]),
                              ("clicks24-mp3", "clicks44",
                               ["-ar", "24000", "-c:a", "libmp3lame", "-b:a", "64k"])]:
        path = fixture_path(name)
        if not path.exists():
            try:
                run(["ffmpeg", "-v", "error", "-y", "-i", made[base], *codec, path])
            except FixtureError:
                path.unlink(missing_ok=True)
                raise
        made[name] = path
    path = fixture_path("clicks44-late")
    if not path.exists():
        try:
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                 "color=c=gray:s=320x180:r=30:d=11", "-itsoffset", "0.5", "-i",
                 made["clicks44"], "-map", "0:v", "-map", "1:a", "-c:v", "libx264",
                 "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", path])
        except FixtureError:
            path.unlink(missing_ok=True)
            raise
    made["clicks44-late"] = path
    path = fixture_path("clicks16-late5")
    if not path.exists():
        try:
            run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i",
                 "color=c=gray:s=320x180:r=30:d=16", "-itsoffset", "5", "-i",
                 made["clicks16"], "-map", "0:v", "-map", "1:a", "-c:v", "libx264",
                 "-pix_fmt", "yuv420p", "-c:a", "pcm_s16le", path])
        except FixtureError:
            path.unlink(missing_ok=True)
            raise
    made["clicks16-late5"] = path
    path = fixture_path("clicks44-mp3-itunsmpb")
    if not path.exists():
        write_itunsmpb(made["clicks44-mp3-noxing"], path)
    made["clicks44-mp3-itunsmpb"] = path
    return made


def write_itunsmpb(noxing: Path, path: Path) -> None:
    """`noxing`'s frames behind an ID3v2.3 tag of one COMM frame, `eng`,
    `iTunSMPB`: 576 priming, 792 remainder, 441 000 valid frames."""
    data = noxing.read_bytes()
    audio = data
    if data[:3] == b"ID3":
        size = 0
        for byte in data[6:10]:
            size = size << 7 | (byte & 0x7F)
        audio = data[10 + size + (10 if data[5] & 0x10 else 0):]
    text = " 00000000 00000240 00000318 000000000006BAA8" + " 00000000" * 8
    body = b"\x00" + b"eng" + b"iTunSMPB\x00" + text.encode("ascii")
    frame = b"COMM" + len(body).to_bytes(4, "big") + b"\x00\x00" + body
    n = len(frame)
    synchsafe = bytes([(n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F])
    partial = path.with_name(path.name + ".partial")
    partial.write_bytes(b"ID3\x03\x00\x00" + synchsafe + frame + audio)
    partial.rename(path)


def afinfo_table(path):
    """The `valid frames` lines `afinfo` prints for the file (its packet
    table), stripped; none when Core Audio has none."""
    ran = run(["afinfo", path], 60)
    return [line.strip() for line in ran["stdout"].splitlines() if "valid frames" in line]


def audio_start_time(path):
    """ffprobe's start_time of the first audio stream, in seconds."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
               "stream=start_time", "-of", "csv=p=0", path])
    return float(ran["stdout"].strip().split(",")[0])


# ---- the 48 kHz copies (SY-23) -------------------------------------------------


def rate_copy_dirs():
    """`FrameJob/AudioRate48` under `$TMPDIR` (when set) and under `getconf
    DARWIN_USER_TEMP_DIR`: the app's `NSTemporaryDirectory()` is one of them."""
    roots = []
    if os.environ.get("TMPDIR"):
        roots.append(Path(os.environ["TMPDIR"]))
    ran = bounded.run(["getconf", "DARWIN_USER_TEMP_DIR"], 30)
    if ran["rc"] == 0 and ran["stdout"].strip():
        roots.append(Path(ran["stdout"].strip()))
    out = []
    for root in roots:
        folder = root / "FrameJob" / "AudioRate48"
        if folder not in out:
            out.append(folder)
    return out


def clear_rate_copies():
    """Removes every 48 kHz copy, so what is measured is the current code's."""
    for folder in rate_copy_dirs():
        shutil.rmtree(folder, ignore_errors=True)


_fixtures = None


def fixtures():
    global _fixtures
    if _fixtures is None:
        _fixtures = make_fixtures()
    return _fixtures


# ---- readers -------------------------------------------------------------------


def read_wav(path: Path) -> tuple[list[float], int]:
    """Python `wave` only (no ffmpeg): integer PCM, channels averaged."""
    with wave.open(str(path), "rb") as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 2:
        values = array.array("h", raw)
        scale = 32768
    elif width == 4:
        values = array.array("i", raw)
        scale = 2 ** 31
    elif width == 3:
        values = [int.from_bytes(raw[i:i + 3], "little", signed=True)
                  for i in range(0, len(raw) - 2, 3)]
        scale = 2 ** 23
    else:
        raise ValueError(f"{path.name}: {width}-byte samples")
    if channels == 1:
        return [v / scale for v in values], rate
    out = []
    for i in range(0, len(values) - channels + 1, channels):
        out.append(sum(values[i:i + channels]) / (channels * scale))
    return out, rate


def stream_rate(path):
    ran = run(["ffprobe", "-v", "error", "-select_streams", "a:0", "-show_entries",
               "stream=sample_rate", "-of", "csv=p=0", path])
    return int(ran["stdout"].strip().split(",")[0])


def read_ffmpeg(path: Path) -> tuple[list[float], int]:
    """ffmpeg to mono float32 at the stream's own rate (edit lists honoured as
    ffmpeg does by default); for `.mov` / `.mp4` only."""
    rate = stream_rate(path)
    out = path.with_name(path.name + ".f32")
    run(["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:a:0", "-ac", "1", "-ar",
         str(rate), "-f", "f32le", "-acodec", "pcm_f32le", out])
    data = array.array("f", out.read_bytes())
    out.unlink(missing_ok=True)
    return list(data), rate


def read_f32(path: Path, rate: int) -> list[float]:
    """The probe's raw output: mono float32 LE."""
    return list(array.array("f", Path(path).read_bytes()))


def read_any(path: Path):
    path = Path(path)
    return read_wav(path) if path.suffix == ".wav" else read_ffmpeg(path)


# ---- locating ------------------------------------------------------------------


def template(rate):
    h = rate / 2000
    half = math.ceil(h)
    values = [click_value(k, h) for k in range(-half, half + 1)]
    return values, half, math.sqrt(sum(v * v for v in values))


def locate(samples, rate: int, expected: list[float],
           reach_ms: float = 60.0) -> list[tuple[float | None, float]]:
    """Per expected time (s): (found time s, or None when r < 0.5; r)."""
    values, half, norm = template(rate)
    reach = int(round(reach_ms * rate / 1000))
    fine = max(1, int(round(rate / 1000)))
    n = len(samples)
    out = []

    def r_at(c):
        a, b = c - half, c + half + 1
        if a < 0 or b > n:
            return 0.0
        seg = samples[a:b]
        energy = math.sqrt(sum(x * x for x in seg))
        return sum(x * y for x, y in zip(seg, values)) / (energy * norm) if energy > 0 else 0.0

    for t in expected:
        centre = int(round(t * rate))
        lo, hi = max(0, centre - reach), min(n, centre + reach + 1)
        if hi <= lo:
            out.append((None, 0.0))
            continue
        coarse = max(range(lo, hi), key=lambda i: abs(samples[i]))
        scores = {c: r_at(c) for c in range(coarse - fine, coarse + fine + 1)}
        best = max(scores, key=scores.get)
        r = scores[best]
        offset = 0.0
        if best - 1 in scores and best + 1 in scores:
            left, right = scores[best - 1], scores[best + 1]
            bend = left - 2 * r + right
            if bend < 0:
                offset = max(-0.5, min(0.5, 0.5 * (left - right) / bend))
        out.append(((best + offset) / rate if r >= 0.5 else None, r))
    return out


def summary(found, expected) -> dict:
    diffs = [(f - e) * 1000 for (f, _), e in zip(found, expected) if f is not None]
    rs = [r for _, r in found]
    return {
        "found": len(diffs), "of": len(expected),
        "median_ms": statistics.median(diffs) if diffs else None,
        "spread_ms": (max(diffs) - min(diffs)) if diffs else None,
        "min_r": min(rs) if rs else None,
        "diffs": diffs,
    }


def fmt(value, places=3):
    return "—" if value is None else f"{value:+.{places}f}"


def describe(s):
    return (f"{s['found']}/{s['of']} found, median {fmt(s['median_ms'])} ms, spread "
            f"{fmt(s['spread_ms'])} ms, min r {s['min_r']:.3f}" if s["min_r"] is not None
            else f"{s['found']}/{s['of']} found")


def flash_times(path: Path, threshold: float = 128) -> list[float]:
    """The times of video frames whose mean luma (16×9 gray) is over
    `threshold` (128 for a picture the flash fills)."""
    ran = run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
               "frame=best_effort_timestamp_time", "-of", "csv=p=0", path])
    times = [float(line.strip().split(",")[0]) for line in ran["stdout"].splitlines()
             if line.strip()]
    out = Path(path).with_name(Path(path).name + ".gray")
    run(["ffmpeg", "-v", "error", "-y", "-i", path, "-map", "0:v:0", "-fps_mode",
         "passthrough", "-vf", "scale=16:9,format=gray", "-f", "rawvideo", out])
    raw = out.read_bytes()
    out.unlink(missing_ok=True)
    means = [sum(raw[i:i + 144]) / 144 for i in range(0, len(raw) - 143, 144)]
    return [t for t, m in zip(times, means) if m > threshold]


# ---- the app's projects --------------------------------------------------------


class Session:
    def __init__(self, mcp, name):
        self.mcp = mcp
        for stale in WORK.iterdir():
            if re.fullmatch(rf"{re.escape(name)}-\d+\.framejob", stale.name):
                shutil.rmtree(stale)
        self.path = str(WORK / f"{name}-{os.getpid()}.framejob")
        mcp.call("new_project", path=self.path)
        self.op("set_canvas", width=640, height=360, fps=30)

    def op(self, name, **kwargs):
        return self.mcp.call(name, project=self.path, **kwargs)

    def project(self):
        return self.op("get_project")["project"]

    def clip(self, clip):
        return {c["id"]: c for c in self.project()["clips"]}[clip]

    def media(self, path):
        """`import_media`, then its peaks waited for (60 s), as
        `audio_sync_proof.Session.media` does."""
        media = self.op("import_media", path=str(path))["media"]
        peaks = Path(self.path) / "cache" / "peaks" / f"{media}.bin"
        for _ in range(1200):
            if peaks.exists():
                return media
            time.sleep(0.05)
        raise RuntimeError(f"{peaks} was never written")

    def place(self, path, at):
        media = self.media(path)
        track = self.project()["tracks"][0]["id"]
        return self.op("add_clip", track=track, media=media, at=at)["new_clips"][0]

    def close(self):
        try:
            self.op("close_project", discard=True)
        except ToolError:
            pass


def expected_times(clip, in_point=None, fixture=None):
    """Each click's expected time in the file, (source s, file s); clicks
    outside the clip's window, or outside [in, out) of an in/out export, are
    left out. A fixture whose audio starts late has its clicks that much
    later in the source (SOURCE_OFFSET)."""
    start = clip["start"] / SEC
    source_in = clip["source"].get("in", 0) / SEC
    speed = clip.get("speed", 1) or 1
    end = start + clip["duration"] / SEC
    offset = SOURCE_OFFSET.get(fixture, 0.0)
    out = []
    for c in CLICKS:
        c = c + offset
        t = start + (c - source_in) / speed
        if not (start <= t < end):
            continue
        if in_point is not None:
            lo, hi = in_point
            if not (lo <= t < hi):
                continue
            t -= lo
        out.append((c, t))
    return out


_e_cache = {}


def run_e(mcp, row, fixture_override=None):
    """One E row's export, measured: a dict (memoised per row and fixture)."""
    key = (row, fixture_override)
    if key in _e_cache:
        return _e_cache[key]
    fixture, at, edit, preset = E_ROWS[row]
    fixture = fixture_override or fixture
    tag = row if fixture_override is None else f"{row}-{fixture_override}"
    EXPORTS.mkdir(parents=True, exist_ok=True)
    out = EXPORTS / f"{tag}.{EXTENSIONS[preset]}"
    out.unlink(missing_ok=True)
    session = Session(mcp, f"offset-{tag.lower()}")
    result = {"row": row, "fixture": fixture, "preset": preset, "path": out}
    try:
        clip = session.place(fixtures()[fixture], at)
        export = {"preset": preset, "path": str(out)}
        in_point = None
        if edit and edit[0] == "speed":
            session.op("set_speed", clip=clip, rate=edit[1], keep_pitch=edit[2])
        elif edit and edit[0] == "loudness":
            export["loudness_lufs"] = edit[1]
        elif edit and edit[0] == "pan":
            session.op("set_audio", clips=[clip], patch={"pan": edit[1]})
        elif edit and edit[0] == "nr":
            session.op("set_audio", clips=[clip], patch={"noise_reduction": edit[1]})
        elif edit and edit[0] == "range":
            session.op("set_range", start=edit[1], end=edit[2])
            export["range"] = "in_out"
            in_point = (edit[1] / SEC, edit[2] / SEC)
        placed = session.clip(clip)
        result["clip"] = {k: placed.get(k) for k in ("start", "duration", "speed")}
        session.op("export", **export)
    finally:
        session.close()
    pairs = expected_times(placed, in_point, fixture)
    expected = [t for _, t in pairs]
    samples, rate = read_any(out)
    found = locate(samples, rate, expected)
    result.update(summary(found, expected))
    result["rate"] = rate
    result["expected"] = expected
    result["found_times"] = [f for f, _ in found]
    if preset in ("prores_422", "h264"):
        # The 320×180 movie sits unscaled on the 640×360 canvas, a quarter of
        # its area, so a white frame's mean over the whole picture is a
        # quarter of a full one's: the threshold is scaled by the same share.
        flashes = flash_times(out, 128 * FLASH_SHARE)
        result["flashes"] = flashes
        result["flash_frames"] = sorted(round(t * 30) for t in flashes)
        result["expected_frames"] = sorted(round(t * 30) for t in expected)
        av = []
        clicks = [f for f, _ in found if f is not None]
        for t in flashes:
            near = min(clicks, key=lambda c: abs(c - t), default=None)
            if near is not None and abs(near - t) < 0.1:
                av.append((near - t) * 1000)
        result["av_ms"] = av
    _e_cache[key] = result
    return result


def pinned(s):
    """SY-27's exact pin over a located summary: (ok, sentence)."""
    if s is None or s["median_ms"] is None:
        return False, "pin missed (nothing found)"
    met = (s["found"] >= 10 and abs(s["median_ms"]) <= TARGET_MS
           and s["spread_ms"] <= TARGET_SPREAD_MS)
    return met, ("pin " + ("met" if met else "missed")
                 + f" (≥ 10 found, |median| ≤ {TARGET_MS} ms, spread ≤ {TARGET_SPREAD_MS} ms)")


def e_target(row, r):
    """SY-27's pin for one E row: (ok, sentence)."""
    if r["median_ms"] is None:
        return False, "pin missed (nothing found)"
    if row in MEASURED_ROWS:
        return True, (f"measured, not pinned (#299 open; SY-37's {KEEP_TARGET_MS} ms would read "
                      + ("within" if abs(r["median_ms"]) <= KEEP_TARGET_MS else "OVER") + ")")
    if row in KEEP_ROWS:
        met = abs(r["median_ms"]) <= KEEP_TARGET_MS
        return met, "pin " + ("met" if met else "missed") + f" (|median| ≤ {KEEP_TARGET_MS} ms)"
    if row in VIDEO_ROWS:
        av = r.get("av_ms") or []
        on_frame = r.get("flash_frames") == r.get("expected_frames")
        av_ok = bool(av) and max(abs(v) for v in av) <= TARGET_MS
        return on_frame and av_ok, ("pin " + ("met" if on_frame and av_ok else "missed")
                                    + f" (flash on its timeline frame {on_frame}, "
                                    f"|click − flash| ≤ {TARGET_MS} ms {av_ok})")
    met, sentence = pinned(r)
    if row == "E22":
        base = _e_cache.get(("E4", None))
        if base and base["median_ms"] is not None:
            delta = r["median_ms"] - base["median_ms"]
            sentence += (f"; E22 − E4 {delta:+.3f} ms (the reducer's {NR_DELAY_MS:.3f} ms, "
                         "led by SY-25)")
    return met, sentence


def e_row(mcp, row):
    try:
        if row == "E22":
            run_e(mcp, "E4")  # its base, measured once
        r = run_e(mcp, row)
    except Exception as error:  # an instrument failure is this row's scored FAIL
        score(row, False, f"{type(error).__name__}: {error}")
        e_table.append((row, E_ROWS[row], None))
        return
    need = r["of"] if row == "E23" else 10
    met, sentence = e_target(row, r)
    ok = r["found"] >= need and (row != "E23" or r["of"] == 10) and met
    detail = f"{r['fixture']} {r['preset']} → {r['rate']} Hz; {describe(r)}; {sentence}"
    if row in VIDEO_ROWS:
        av = r.get("av_ms") or []
        detail += (f"; flashes {len(r['flashes'])} on frames {r['flash_frames']} (timeline "
                   f"{r['expected_frames']}); A/V click − flash median "
                   f"{fmt(statistics.median(av) if av else None)} ms, range "
                   f"{fmt(min(av) if av else None)}…{fmt(max(av) if av else None)} ms")
    score(row, ok, detail)
    e_table.append((row, E_ROWS[row], r))


# ---- Z rows --------------------------------------------------------------------


def z0():
    files = fixtures()
    notes, ok = [], True
    for name in ["clicks16", "clicks48", "clicks48-lead37", "clicks44", "clicks44-aac",
                 "clicks44-mp3", "clicks48-mp3", "clicks44s-mp3", "clicks24-mp3", "cam-pcm48",
                 "cam-aac48", "cam-ff16"]:
        samples, rate = read_any(files[name])
        lead = LEAD / 48_000 if name == "clicks48-lead37" else 0
        expected = [c + lead for c in CLICKS]
        s = summary(locate(samples, rate, expected), expected)
        lossy = ("cam-aac48", "clicks44-aac", "clicks44-mp3", "clicks48-mp3", "clicks44s-mp3",
                 "clicks24-mp3")
        tolerance = 0.5 if name in lossy else 0.05
        worst = max((abs(d) for d in s["diffs"]), default=None)
        good = s["found"] == 12 and worst is not None and worst <= tolerance
        ok &= good
        notes.append(f"{name} {rate} Hz {s['found']}/12, worst |Δ| {fmt(worst, 4)} ms "
                     f"(≤ {tolerance}), median {fmt(s['median_ms'], 4)}")
        if name in ("cam-pcm48", "cam-aac48"):
            flashes = flash_times(files[name])
            frames = [round(t * 30) for t in flashes]
            off = max((abs(t - round(t * 30) / 30) * 1000 for t in flashes), default=None)
            good = frames == CLICK_FRAMES and off is not None and off <= 1.0
            ok &= good
            notes.append(f"{name} flashes on {frames == CLICK_FRAMES and 'CLICK_FRAMES' or frames}"
                         f" (pts off its frame ≤ {fmt(off, 4)} ms)")
    for name in ["clicks44-late", "clicks16-late5"]:
        start = audio_start_time(files[name])
        good = abs(start - SOURCE_OFFSET[name]) <= 0.001
        ok &= good
        notes.append(f"{name} audio start_time {start:.6f} s (want "
                     f"{SOURCE_OFFSET[name]:.3f} ± 0.001)")
    # The class each MP3 row assumes: Core Audio's packet table, or none.
    for name in UNTABLED_MP3 + TABLED_MP3:
        lines = afinfo_table(files[name])
        want = [TABLE_LINE] if name in TABLED_MP3 else []
        good = lines == want
        ok &= good
        notes.append(f"{name} afinfo {lines or 'no valid frames line'}"
                     + ("" if good else " — FAIL: not the class the rows assume"))
    score("Z0", ok, "; ".join(notes))


def z2():
    rate = 48_000
    total = rate * LENGTH_S
    h = rate / 2000
    data = [0.0] * total
    centres = []
    for k, f in enumerate(CLICK_FRAMES):
        c = rate * f / 30 + [0.0, 0.3, 0.7][k % 3]
        centres.append(c / rate)
        for n in range(int(c - h) - 1, int(c + h) + 2):
            data[n] += click_value(n - c, h)
    found = locate(data, rate, centres)
    s = summary(found, centres)
    worst = max((abs(d) for d in s["diffs"]), default=None)
    score("Z2", s["found"] == 12 and worst is not None and worst <= 0.01,
          f"{s['found']}/12 found, worst |Δ| {fmt(worst, 5)} ms (want ≤ 0.01), min r "
          f"{s['min_r']:.4f}")


def z1(mcp):
    e4 = run_e(mcp, "E4")
    lead = run_e(mcp, "E4", "clicks48-lead37")
    want = LEAD / 48_000 * 1000
    if e4["median_ms"] is None or lead["median_ms"] is None:
        score("Z1", False, f"E4 {describe(e4)}; lead37 {describe(lead)}")
        return
    delta = lead["median_ms"] - e4["median_ms"]
    score("Z1", abs(delta - want) <= 0.05,
          f"lead37 median {fmt(lead['median_ms'])} − E4 {fmt(e4['median_ms'])} = "
          f"{delta:+.4f} ms (want {want:.4f} ± 0.05); lead37 {describe(lead)}")


def z3(mcp):
    e2 = run_e(mcp, "E2")
    start_ms = e2["clip"]["start"] / SEC * 1000
    offset = round(start_ms)
    mix = envelope(wav_samples(Path(e2["path"])))
    source = envelope(wav_samples(fixtures()["clicks16"]))
    lag, r = window_lag(mix, source, offset + 400, offset + 9400, offset_ms=offset)
    # `window_lag` measures against the source placed at the whole-ms `offset`;
    # the clip starts at `start_ms`, so its lag reads (start_ms − offset) ms
    # more than the clip's own delay. That rounding is taken back out.
    rounding = start_ms - offset
    corrected = lag - rounding
    located = e2["median_ms"]
    measured = located is not None and r > 0
    score("Z3", measured,
          f"locate median {fmt(located)} ms; S18 method lag {lag:+.3f} ms (r {r:.3f}) against "
          f"the fixture at {offset} ms, the clip at {start_ms:.3f} ms, rounding "
          f"{rounding:+.3f} ms taken out → {corrected:+.3f} ms; S18 − locate "
          f"{fmt(corrected - located if located is not None else None)} ms")


# ---- R rows --------------------------------------------------------------------


def stretched_lag(mix, media, clip_start_ms: float, in_ms: float, speed: float, lo_ms: int,
                  hi_ms: int, reach: int = 40) -> tuple[float, float]:
    """(lag ms, peak r): the mix's 1 ms envelope over the timeline span media
    window [lo_ms, hi_ms) plays at, against the media's envelope linearly
    interpolated at (t + 0.5 − L − clip_start_ms)·speed + in_ms − 0.5, by
    mean-removed normalised correlation at each whole ms L in ±reach, refined
    parabolically (`window_lag`'s shape). A lag of exactly ±reach is on the
    edge (no refinement)."""
    a = round(clip_start_ms + (lo_ms - in_ms) / speed)
    b = round(clip_start_ms + (hi_ms - in_ms) / speed)
    xs = mix[a:b]
    mx = sum(xs) / len(xs)
    xc = [x - mx for x in xs]
    ex = math.sqrt(sum(x * x for x in xc))
    last = len(media) - 1

    def at(u):
        if u <= 0:
            return media[0]
        if u >= last:
            return media[last]
        i = int(u)
        f = u - i
        return media[i] * (1 - f) + media[i + 1] * f

    scores = []
    for lag in range(-reach, reach + 1):
        ys = [at((t + 0.5 - lag - clip_start_ms) * speed + in_ms - 0.5) for t in range(a, b)]
        my = sum(ys) / len(ys)
        yc = [y - my for y in ys]
        ey = math.sqrt(sum(y * y for y in yc))
        scores.append(sum(p * q for p, q in zip(xc, yc)) / (ex * ey) if ex and ey else 0)
    best = max(range(len(scores)), key=lambda i: scores[i])
    offset = 0.0
    if 0 < best < len(scores) - 1:
        left, centre, right = scores[best - 1], scores[best], scores[best + 1]
        bend = left - 2 * centre + right
        if bend < 0:
            offset = max(-0.5, min(0.5, 0.5 * (left - right) / bend))
    return best - reach + offset, scores[best]


def r_rows(mcp, wanted):
    files = sync_fixtures()
    source = envelope(wav_samples(Path(files["source"])))
    media = envelope(wav_samples(Path(files["recorder"])))
    session = Session(mcp, "offset-r")
    issue = {"R1": "+25.71", "R2": "−2.81"}
    try:
        clip = session.place(files["recorder"], F206)
        for row in R_ROWS:
            if row not in wanted:
                continue
            speed, keep, reach, pin = R_EDITS[row]
            if speed is not None:
                session.op("set_speed", clip=clip, rate=speed, keep_pitch=keep)
            out = EXPORTS / f"{row}.wav"
            EXPORTS.mkdir(parents=True, exist_ok=True)
            out.unlink(missing_ok=True)
            session.op("export", preset="audio_wav", path=str(out))
            mix = envelope(wav_samples(out))
            if row in ("R1", "R2"):
                lag, r = window_lag(mix, source, 12_000, 22_000)
                score(row, r >= 0.8 and abs(lag) <= TARGET_MS,
                      f"{'×1' if row == 'R1' else '×0.99999 keep_pitch false'}: "
                      f"S18 lag {lag:+.2f} ms (r {r:.3f}) on [12 s, 22 s) (want |lag| ≤ "
                      f"{TARGET_MS} ms, r ≥ 0.8); #298 reported {issue[row]} ms")
                continue
            placed = session.clip(clip)
            start_ms = placed["start"] / SEC * 1000
            in_ms = placed["source"].get("in", 0) / SEC * 1000
            rate = placed.get("speed", 1) or 1
            lags = [stretched_lag(mix, media, start_ms, in_ms, rate, lo, hi, reach)
                    for lo, hi in R_WINDOWS]
            edge = [abs(lag) >= reach for lag, _ in lags]
            text = "; ".join(
                f"[{lo // 1000} s, {hi // 1000} s) lag {lag:+.3f} ms (r {r:.3f})"
                + (" at the edge" if on_edge else "")
                for (lo, hi), (lag, r), on_edge in zip(R_WINDOWS, lags, edge))
            label = f"×{rate} keep_pitch {str(keep).lower()}, reach ±{reach} ms"
            if pin:
                ok = all(r >= 0.8 and abs(lag) <= TARGET_MS for lag, r in lags) and not any(edge)
                score(row, ok, f"{label}: {text} (want both |lag| ≤ {TARGET_MS} ms, r ≥ 0.8)")
            else:
                # Measured (ruling 3): the instrument holds when each window
                # is found — a finite lag inside the reach at r ≥ 0.5.
                found = all(math.isfinite(lag) and math.isfinite(r) and r >= 0.5 and not on_edge
                            for (lag, r), on_edge in zip(lags, edge))
                defect = any(r < 0.8 or abs(lag) > DEFECT_MS or on_edge
                             for (lag, r), on_edge in zip(lags, edge))
                score(row, found,
                      f"{label}: {text}; not pinned (#299 open); SY-37's class: "
                      + ("DEFECT (r < 0.8, |lag| > 5.0 ms or at the edge)" if defect
                         else "within SY-27's 5.0 ms (every window r ≥ 0.8, inside the reach)")
                      + ("" if found else "; a window not found (r < 0.5 or at the edge)"))
    finally:
        session.close()


# ---- L rows (the probe) --------------------------------------------------------


def build_probe(sources=None, here=PROBE_DIR):
    """(binary, None) or (None, why): every `app_sources(sources)` file plus the
    probe as `main.swift`, `Blank.mp4` beside (`playback_audio_proof.py`'s
    pattern)."""
    here.mkdir(parents=True, exist_ok=True)
    entry = here / "main.swift"
    source = PROBE_SWIFT.read_text()
    if not entry.exists() or entry.read_text() != source:
        entry.write_text(source)
    blank = here / "Blank.mp4"
    if not blank.exists():
        shutil.copy2(BLANK, blank)
    binary = here / "export_offset_probe"
    try:
        swift_build.build(sources=swift_build.app_sources(sources) + [entry], output=binary,
                          defines=["FRAMEJOB_DEV_TOOLS"], timeout=BUILD_WALL)
    except swift_build.SwiftBuildFailed as error:
        return None, "the probe did not build: " + "; ".join(error.diagnostics[:6])
    return binary, None


def run_probe(binary, group="all", runs=PROBE_RUNS):
    """({row: probe row}, manifest, None) or (None, None, why)."""
    shutil.rmtree(runs, ignore_errors=True)
    runs.mkdir(parents=True)
    ran = bounded.run([str(binary), str(runs), str(FIXTURES), group], RUN_WALL,
                      cwd=str(binary.parent))
    (runs / "stderr.txt").write_text(ran["stderr"])
    if ran["expired"]:
        return None, None, f"the probe ran past {RUN_WALL} s and was killed"
    for line in ran["stdout"].splitlines():
        if line.startswith("ANSWER "):
            try:
                rows = {r["id"]: r for r in json.loads(line[len("ANSWER "):]).get("rows", [])}
                manifest = json.loads((runs / "manifest.json").read_text())
            except (OSError, ValueError) as error:
                return None, None, f"the probe's answer or manifest could not be read: {error}"
            return rows, manifest, None
    return None, None, f"no answer (exit {ran['rc']}): {ran['stderr'].strip()[-400:]}"


def measure_read(entry):
    """The located summary of one manifest read, or None."""
    if not entry.get("ok"):
        return None
    path = Path(entry["path"])
    if path.suffix == ".wav":
        samples, rate = read_wav(path)
    else:
        rate = entry["rate"]
        samples = read_f32(path, rate)
    start = entry["start_ticks"] / SEC
    speed = entry["speed"] or 1
    offset = SOURCE_OFFSET.get(entry["fixture"], 0.0)
    expected = [start + (c + offset) / speed for c in CLICKS]
    return summary(locate(samples, rate, expected), expected)


def chain_key(entry):
    return entry["variant"].split("+")[0]


def probe_scores(manifest, rows, wanted, table=None):
    """{row: (ok, detail)} for the L and X rows in `wanted`, from one probe
    run's manifest; the measured reads are appended to `table` when given."""
    measured = []
    for entry in manifest:
        try:
            s = measure_read(entry)
        except (OSError, ValueError, KeyError, wave.Error) as error:
            # A read that cannot be measured scores its row FAIL (the row's
            # "under 10 found" names it); it never ends the script.
            print(f"  unreadable: {entry.get('path')}: {error}", flush=True)
            s = None
        measured.append((entry, s))
        if table is not None:
            table.append((entry, s))
    out = {}
    for row in wanted:
        probe_row = rows.get(row, {"ok": False, "detail": "the probe did not answer it"})
        mine = [(e, s) for e, s in measured if e["row"] == row]
        short = [f"{e['fixture']} {e['stage']} {e['variant']}" for e, s in mine
                 if s is None or s["found"] < 10]
        ok = probe_row["ok"] and (bool(mine) or row in NO_READ_ROWS) and not short
        if row in X_ROWS:
            x2 = next((s for e, s in measured if e["row"] == "X2"), None)
            pins = [noxing_pin(s, x2) if row == "X14" else pinned(s) for _, s in mine]
            ok = ok and all(met for met, _ in pins)
            medians = "; ".join(
                f"{e['fixture']} {e['variant']} {describe(s)}, {pin[1]}"
                for (e, s), pin in zip(mine, pins) if s is not None)
        else:
            medians = ", ".join(
                f"{e['fixture']} {e['stage']} {e['variant']} {fmt(s['median_ms'])}"
                for e, s in mine if s is not None)
        if row == "L10":
            met, sentence = l10_gate(mine)
            ok = ok and met
            medians += f"; gate {sentence}"
        out[row] = (ok, f"probe: {probe_row['detail']}; under 10 found: {short or 'none'}; "
                        f"medians (ms): {medians}")
    return out, measured


def noxing_pin(s, x2):
    """X14: an MP3 with no tag is left untrimmed — all 12 found and
    |X14 − X2 − 576/44.1| ≤ 0.1 ms."""
    if s is None or s["median_ms"] is None or x2 is None or x2["median_ms"] is None:
        return False, "untrimmed check missed (nothing found, or no X2)"
    delta = s["median_ms"] - x2["median_ms"]
    met = s["found"] == 12 and abs(delta - NOXING_LATE_MS) <= 0.1
    return met, (f"untrimmed {'met' if met else 'missed'} (X14 − X2 {delta:+.3f} ms, want "
                 f"{NOXING_LATE_MS:.3f} ± 0.1 with 12 found)")


_ffmpeg_medians = {}


def ffmpeg_median(name):
    """The fixture's clicks by ffmpeg (`read_any`), median of found − written."""
    if name not in _ffmpeg_medians:
        samples, rate = read_any(fixtures()[name])
        _ffmpeg_medians[name] = summary(locate(samples, rate, CLICKS), CLICKS)["median_ms"]
    return _ffmpeg_medians[name]


def l10_gate(mine):
    """Step 2's gate over L10's reads: (ok, sentence). Every `trimmed` read ≥ 10
    found within 0.1 ms of the same file's ffmpeg median; the tabled MP3s'
    native reads within 0.1 ms; noxing's native read 576/44.1 ms late ± 0.1."""
    notes, ok = [], True
    for e, s in mine:
        name = e["fixture"]
        if e["stage"] == "trimmed":
            want = ffmpeg_median(name)
            label = f"ffmpeg {fmt(want)}"
        elif e["stage"] == "native" and name in TABLED_MP3:
            want, label = 0.0, "0"
        elif e["stage"] == "native" and name == "clicks44-mp3-noxing":
            want, label = NOXING_LATE_MS, f"{NOXING_LATE_MS:.3f}"
        else:
            continue
        good = (s is not None and s["median_ms"] is not None and s["found"] >= 10
                and want is not None and abs(s["median_ms"] - want) <= 0.1)
        ok &= good
        got = fmt(s["median_ms"]) if s is not None else "—"
        notes.append(f"{name} {e['stage']} {got} vs {label} {'ok' if good else 'MISSED'}")
    return ok, "; ".join(notes)


def l_rows(wanted):
    """The probe's L and X rows in `wanted`, from one run of the group they
    need."""
    try:
        fixtures()
    except FixtureError as error:
        for row in wanted:
            score(row, False, f"the fixtures could not be made: {error}")
        return
    has_l = any(row in L_ROWS for row in wanted)
    has_x = any(row in X_ROWS for row in wanted)
    group = "all" if has_l and has_x else "L" if has_l else "X"
    binary, why = build_probe()
    rows = manifest = None
    if binary is not None:
        rows, manifest, why = run_probe(binary, group)
    if rows is None:
        for row in wanted:
            score(row, False, why)
        return
    scored, measured = probe_scores(manifest, rows, wanted, l_table)
    for row in wanted:
        score(row, *scored[row])
    if has_l:
        print_where(measured)


def print_where(measured):
    """Per fixture and speed, the first stage whose median moves > 0.1 ms."""
    by = {}
    for entry, s in measured:
        if s is None or s["median_ms"] is None:
            continue
        if entry["row"] in ("L1", "L2"):
            by.setdefault((entry["fixture"], entry["stage"]), s["median_ms"])
        elif entry["row"] in ("L3", "L4", "L5", "L8"):
            by[(entry["fixture"], chain_key(entry), entry["stage"])] = s["median_ms"]
    print("\nWhere each offset enters (first stage moving > 0.1 ms from the one before):",
          flush=True)
    keys = sorted({(key[0], key[1]) for key in by if len(key) == 3})
    for fixture, speed in keys:
        chain = [("asset48", by.get((fixture, "asset48")))] + [
            (stage, by.get((fixture, speed, stage))) for stage in ("comp", "mix", "export")]
        steps = " → ".join(f"{stage} {fmt(m)}" for stage, m in chain)
        enters = "none (every step within 0.1 ms)"
        previous = None
        for stage, m in chain:
            if m is None:
                continue
            if previous is not None and abs(m - previous[1]) > 0.1:
                enters = f"{stage} ({m - previous[1]:+.3f} ms after {previous[0]})"
                break
            previous = (stage, m)
        native = by.get((fixture, "native"))
        asset = by.get((fixture, "asset48"))
        src = (f"; native − asset48 {native - asset:+.3f} ms"
               if native is not None and asset is not None else "")
        print(f"  {fixture} {speed}: {steps}; enters at {enters}{src}", flush=True)


# ---- tables --------------------------------------------------------------------


def print_tables():
    if e_table:
        print("\nE table (found − expected, ms):", flush=True)
        print("| Row | Media | At | Edit | Preset | Found | Median | Spread | Min r | Pin |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for row, (fixture, at, edit, preset), r in e_table:
            edit_text = "×1" if edit is None else " ".join(str(x) for x in edit)
            if r is None:
                print(f"| {row} | {fixture} | {at / SEC:.4f} s | {edit_text} | {preset} | "
                      "not measured | | | | |")
                continue
            print(f"| {row} | {fixture} | {at / SEC:.4f} s | {edit_text} | {preset} | "
                  f"{r['found']}/{r['of']} | {fmt(r['median_ms'])} | {fmt(r['spread_ms'])} | "
                  f"{r['min_r']:.3f} | {e_target(row, r)[1]} |")
    if l_table:
        print("\nL table (found − expected, ms):", flush=True)
        print("| Row | Fixture | Stage | Variant | Rate | Found | Median | Spread | Min r | "
              "First pts |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        for entry, s in l_table:
            pts = entry.get("first_pts_s")
            if s is None:
                print(f"| {entry['row']} | {entry['fixture']} | {entry['stage']} | "
                      f"{entry['variant']} | {entry['rate']} | failed: "
                      f"{str(entry.get('error'))[:120]} | | | | |")
                continue
            print(f"| {entry['row']} | {entry['fixture']} | {entry['stage']} | "
                  f"{entry['variant']} | {entry['rate']} | {s['found']}/{s['of']} | "
                  f"{fmt(s['median_ms'])} | {fmt(s['spread_ms'])} | {s['min_r']:.3f} | "
                  f"{'—' if pts is None else f'{pts:.6f}'} |")


# ---- main ----------------------------------------------------------------------


def mutant_x(sources, here):
    """{X row: (ok, detail)} from the probe built over `sources` and run on
    its X group, or (None, why) when it does not build or answer."""
    clear_rate_copies()
    binary, why = build_probe(sources, here / "probe")
    if binary is None:
        return None, why
    rows, manifest, why = run_probe(binary, "X", here / "runs")
    if rows is None:
        return None, why
    scored, _ = probe_scores(manifest, rows, X_ROWS)
    return scored, None


def mutants(only=None):
    """`only`: the mutant names to run after `before` (None: all of them)."""
    try:
        fixtures()
    except FixtureError as error:
        print(f"mutants: CONTROL FAILED — the fixtures could not be made: {error}")
        return 1
    before, why = mutant_x(None, WORK / "mutants" / "before")
    if before is None:
        print(f"before: CONTROL FAILED — {why[:300]}")
        return 1
    failing = [row for row in X_ROWS if not before[row][0]]
    print(f"before: X rows failing {failing or 'none'}", flush=True)
    for row in failing:
        print(f"    {row}: {before[row][1][:300]}")
    if failing:
        print("mutants: CONTROL FAILED — the unmutated tree fails X rows")
        return 1
    killed = []
    chosen = {name: MUTANTS[name] for name in (only or MUTANTS)}
    for name, (named, file, old, new) in chosen.items():
        here = WORK / "mutants" / name
        if here.exists():
            shutil.rmtree(here)
        sources = here / "Sources"
        shutil.copytree(ROOT / "app/Sources", sources)
        path = sources / file
        text = path.read_text()
        if text.count(old) != 1:
            print(f"mutant {name}: CONTROL FAILED — `{old}` found {text.count(old)} times")
            continue
        path.write_text(text.replace(old, new))
        rows, why = mutant_x(sources, here)
        if rows is None:
            print(f"mutant {name}: CONTROL FAILED — {why[:300]}")
            continue
        failed = [row for row in named if not rows[row][0]]
        others = [row for row in X_ROWS if row not in named and not rows[row][0]]
        caught = len(failed) == len(named)
        if caught:
            killed.append(name)
        print(f"mutant {name}: {'killed' if caught else 'SURVIVED'} — named {named} failed "
              f"{failed}; other rows failing {others}", flush=True)
        for row in named:
            print(f"    {row}: {rows[row][1][:400]}")
    print(f"mutants: {len(killed)}/{len(chosen)} killed (M7, M8: core/tests/pitch_band.rs, "
          "by hand)")
    return 0 if len(killed) == len(chosen) else 1


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("socket", nargs="?")
    parser.add_argument("--only", help="comma-separated row ids")
    parser.add_argument("--mutants", action="store_true")
    parser.add_argument("--mutant", help="with --mutants: comma-separated mutant names")
    args = parser.parse_args()
    if args.mutant and not args.mutants:
        print("--mutant needs --mutants")
        return 2
    if args.mutants:
        only = args.mutant.split(",") if args.mutant else None
        unknown = [name for name in only or [] if name not in MUTANTS]
        if unknown:
            print("unknown mutant " + ", ".join(unknown))
            return 2
        WORK.mkdir(parents=True, exist_ok=True)
        return mutants(only)
    wanted = args.only.split(",") if args.only else list(ALL_ROWS)
    unknown = [row for row in wanted if row not in ALL_ROWS]
    if unknown:
        print("unknown row " + ", ".join(unknown))
        return 2
    needs_app = [row for row in wanted if row not in NO_APP]
    if needs_app and not args.socket:
        print("rows " + ", ".join(needs_app) + " need the running instance's socket path")
        return 2
    WORK.mkdir(parents=True, exist_ok=True)

    if "Z2" in wanted:
        z2()
    if "Z0" in wanted:
        try:
            z0()
        except (FixtureError, OSError, ValueError, wave.Error) as error:
            score("Z0", False, f"{type(error).__name__}: {error}")

    probe_wanted = [row for row in L_ROWS + X_ROWS if row in wanted]
    if needs_app or probe_wanted:
        # Before the first probe run or app row: every copy measured is this
        # code's (SY-23's copies outlive a change to it).
        clear_rate_copies()

    if needs_app:
        try:
            fixtures()
            mcp = MCP(args.socket)
        except Exception as error:  # an instrument failure is a scored FAIL of the rest
            for row in needs_app:
                score(row, False, f"not run: {type(error).__name__}: {error}")
            mcp = None
        if mcp is not None:
            for row, fn in [("Z1", z1), ("Z3", z3)]:
                if row in wanted:
                    try:
                        fn(mcp)
                    except Exception as error:
                        score(row, False, f"{type(error).__name__}: {error}")
            r_wanted = [row for row in R_ROWS if row in wanted]
            if r_wanted:
                try:
                    r_rows(mcp, r_wanted)
                except Exception as error:
                    for row in r_wanted:
                        if row not in results:
                            score(row, False, f"{type(error).__name__}: {error}")
            # E4 first, so E22's difference has its base.
            for row in sorted((r for r in E_IDS if r in wanted),
                              key=lambda r: (r != "E4", E_IDS.index(r))):
                e_row(mcp, row)

    if probe_wanted:
        l_rows(probe_wanted)

    print_tables()
    passed = sum(1 for row in wanted if results.get(row, (False,))[0])
    measured = sum(1 for row in wanted if row in MEASURED_ROWS and results.get(row, (False,))[0])
    print(f"scores: {passed}/{len(wanted)}" + (f" ({measured} of them measured, not pinned)"
                                                if measured else ""))
    return 0 if passed == len(wanted) else 1


if __name__ == "__main__":
    sys.exit(main())
